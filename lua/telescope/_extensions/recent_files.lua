local Path = require "plenary.path"
local make_entry = require "telescope.make_entry"
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local utils = require "telescope.utils"

local config = {}

local function buf_in_cwd(bufname, cwd)
  if cwd:sub(-1) ~= Path.path.sep then
    cwd = cwd .. Path.path.sep
  end
  local bufname_prefix = bufname:sub(1, #cwd)
  return bufname_prefix == cwd
end

local function concatArray(a, b)
  local result = {table.unpack(a)}
  table.move(b, 1, #b, #result + 1, result)
  return result
end

local recent_files = function(opts)
  ---------------------------------------------------------------------------
  -- Findfiles extension
  ---------------------------------------------------------------------------
  opts = vim.tbl_extend("force", config, opts or {})
  local find_command = (function()
    if opts.find_command then
      if type(opts.find_command) == "function" then
        return opts.find_command(opts)
      end
      return opts.find_command
    elseif 1 == vim.fn.executable "rg" then
      return { "rg", "--files", "--color", "never" }
    elseif 1 == vim.fn.executable "fd" then
      return { "fd", "--type", "f", "--color", "never" }
    elseif 1 == vim.fn.executable "fdfind" then
      return { "fdfind", "--type", "f", "--color", "never" }
    elseif 1 == vim.fn.executable "find" and vim.fn.has "win32" == 0 then
      return { "find", ".", "-type", "f" }
    elseif 1 == vim.fn.executable "where" then
      return { "where", "/r", ".", "*" }
    end
  end)()

  if not find_command then
    utils.notify("builtin.find_files", {
      msg = "You need to install either find, fd, or rg",
      level = "ERROR",
    })
    return
  end

  local command = find_command[1]
  local hidden = opts.hidden
  local no_ignore = opts.no_ignore
  local no_ignore_parent = opts.no_ignore_parent
  local follow = opts.follow
  local search_dirs = opts.search_dirs
  local search_file = opts.search_file

  if search_dirs then
    for k, v in pairs(search_dirs) do
      search_dirs[k] = vim.fn.expand(v)
    end
  end

  if command == "fd" or command == "fdfind" or command == "rg" then
    if hidden then
      find_command[#find_command + 1] = "--hidden"
    end
    if no_ignore then
      find_command[#find_command + 1] = "--no-ignore"
    end
    if no_ignore_parent then
      find_command[#find_command + 1] = "--no-ignore-parent"
    end
    if follow then
      find_command[#find_command + 1] = "-L"
    end
    if search_file then
      if command == "rg" then
        find_command[#find_command + 1] = "-g"
        find_command[#find_command + 1] = "*" .. search_file .. "*"
      else
        find_command[#find_command + 1] = search_file
      end
    end
    if search_dirs then
      if command ~= "rg" and not search_file then
        find_command[#find_command + 1] = "."
      end
      vim.list_extend(find_command, search_dirs)
    end
  elseif command == "find" then
    if not hidden then
      table.insert(find_command, { "-not", "-path", "*/.*" })
      find_command = flatten(find_command)
    end
    if no_ignore ~= nil then
      log.warn "The `no_ignore` key is not available for the `find` command in `find_files`."
    end
    if no_ignore_parent ~= nil then
      log.warn "The `no_ignore_parent` key is not available for the `find` command in `find_files`."
    end
    if follow then
      table.insert(find_command, 2, "-L")
    end
    if search_file then
      table.insert(find_command, "-name")
      table.insert(find_command, "*" .. search_file .. "*")
    end
    if search_dirs then
      table.remove(find_command, 2)
      for _, v in pairs(search_dirs) do
        table.insert(find_command, 2, v)
      end
    end
  elseif command == "where" then
    if hidden ~= nil then
      log.warn "The `hidden` key is not available for the Windows `where` command in `find_files`."
    end
    if no_ignore ~= nil then
      log.warn "The `no_ignore` key is not available for the Windows `where` command in `find_files`."
    end
    if no_ignore_parent ~= nil then
      log.warn "The `no_ignore_parent` key is not available for the Windows `where` command in `find_files`."
    end
    if follow ~= nil then
      log.warn "The `follow` key is not available for the Windows `where` command in `find_files`."
    end
    if search_dirs ~= nil then
      log.warn "The `search_dirs` key is not available for the Windows `where` command in `find_files`."
    end
    if search_file ~= nil then
      log.warn "The `search_file` key is not available for the Windows `where` command in `find_files`."
    end
  end

  if opts.cwd then
    opts.cwd = vim.fn.expand(opts.cwd)
  end

  opts.entry_maker = opts.entry_maker or make_entry.gen_from_file(opts)

  local args = vim.deepcopy(find_command)
  table.remove(args, 1)
  local job = require("plenary.job"):new {
    command = command,
    args = args,
    cwd = opts.cwd,
    writer = opts.writer,
    enable_recording = true,
  }
  local findfiles_table = job:sync()

  ---------------------------------------------------------------------------
  -- Oldfiles extension
  ---------------------------------------------------------------------------
  local oldfiles_table = {}

  for _, buffer in ipairs(vim.split(vim.fn.execute ":buffers! t", "\n")) do
    local match = tonumber(string.match(buffer, "%s*(%d+)"))
    local open_by_lsp = string.match(buffer, "line 0$")
    if match and not open_by_lsp then
      local file = vim.api.nvim_buf_get_name(match)
      if vim.loop.fs_stat(file) and match ~= current_buffer then
        table.insert(oldfiles_table, file)
      end
    end
  end

  for _, file in ipairs(vim.v.oldfiles) do
    local file_stat = vim.loop.fs_stat(file)
    if file_stat and file_stat.type == "file" and not vim.tbl_contains(oldfiles_table, file) and file ~= current_file then
      table.insert(oldfiles_table, file)
    end
  end

  local cwd = vim.loop.cwd()
  cwd = cwd .. utils.get_separator()
  cwd = cwd:gsub([[\]], [[\\]])
  oldfiles_table = vim.tbl_filter(function(file)
    return buf_in_cwd(file, cwd)
  end, oldfiles_table)

  ---------------------------------------------------------------------------
  -- Merge findfiles and oldfiles
  ---------------------------------------------------------------------------

  -- Remove cwd prefix from all entries in oldfiles
  oldfiles_table = vim.tbl_map(function(file)
    return string.gsub(file, "^" .. cwd:gsub("(%W)","%%%1"), "")
  end, oldfiles_table) 

  -- Remove oldfiles from findfiles
  findfiles_table = vim.tbl_filter(function(file)
    return not vim.tbl_contains(oldfiles_table, file)
  end, findfiles_table)

  -- Remove current_file if include_current_file is false
  if not opts.include_current_file then
    local current_file = vim.fn.expand "%"
    string.gsub(current_file, "^" .. cwd:gsub("(%W)","%%%1"), "")

    oldfiles_table = vim.tbl_filter(function(file)
      return file ~= current_file
    end, oldfiles_table)

    findfiles_table = vim.tbl_filter(function(file)
      return file ~= current_file
    end, findfiles_table)
  end

  -- Try to prioritize matches from oldfiles when searching
  local num_oldfiles = #oldfiles_table
  opts.tiebreak = function(current_entry, existing_entry, _)
    -- Use default ordering for files not in oldfiles_table
    if current_entry.index > num_oldfiles and existing_entry.index > num_oldfiles then
      return #current_entry.ordinal < #existing_entry.ordinal
    end
    -- Otherwise favor the more recent file
    return current_entry.index < existing_entry.index
  end

  -- Merge findfiles into oldfiles
  vim.list_extend(oldfiles_table, findfiles_table)

  local finder = finders.new_table {
    results = oldfiles_table,
    entry_maker = opts.entry_maker or make_entry.gen_from_file(opts),
  }

  pickers
    .new(opts, {
      prompt_title = "Recent Files",
      __locations_input = true,
      finder = finder,
      previewer = conf.grep_previewer(opts),
      sorter = conf.file_sorter(opts),
    })
    :find()
end

return require("telescope").register_extension {
  setup = function(ext_config)
    config = ext_config or {}
  end,
  exports = {
    recent_files = recent_files,
  },
}
