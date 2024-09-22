-- Note: Copies of builtin functions match code from Telescope 0.1.8 release

local Path = require "plenary.path"
local make_entry = require "telescope.make_entry"
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local utils = require "telescope.utils"
local log = require "telescope.log"
local async_oneshot_finder = require "telescope.finders.async_oneshot_finder"
local flatten = utils.flatten

-- Suppress LuaLS warnings about undefined fields on vim.loop
vim.loop = vim.uv or vim.loop

-- Copied from __internal.lua with no modifications
local function apply_cwd_only_aliases(opts)
  local has_cwd_only = opts.cwd_only ~= nil
  local has_only_cwd = opts.only_cwd ~= nil

  if has_only_cwd and not has_cwd_only then
    -- Internally, use cwd_only
    opts.cwd_only = opts.only_cwd
    opts.only_cwd = nil
  end

  return opts
end

-- Copied from __internal.lua with no modifications
local function buf_in_cwd(bufname, cwd)
  if cwd:sub(-1) ~= Path.path.sep then
    cwd = cwd .. Path.path.sep
  end
  local bufname_prefix = bufname:sub(1, #cwd)
  return bufname_prefix == cwd
end

-- Copy of finders.new_oneshot_job with the following changes:
-- - Assertion ensuring opts.results is not passed is removed
-- - The opts.results entry is passed through to async_oneshot_finder
local new_oneshot_job_alternate = function(command_list, opts)
  opts = opts or {}

  command_list = vim.deepcopy(command_list)
  local command = table.remove(command_list, 1)

  return async_oneshot_finder {
    entry_maker = opts.entry_maker or make_entry.gen_from_string(opts),

    cwd = opts.cwd,
    maximum_results = opts.maximum_results,

    results = opts.results,

    fn_command = function()
      return {
        command = command,
        args = command_list,
      }
    end,
  }
end

-- Copy of the builtin.oldfiles picker with the following modifications:
-- - The final pickers.new(...):find() statement is omitted
-- - The finder is returned instead
-- - A line is removed that stops oldfiles from working if cwd is root
local builtin_oldfiles_copy = function(opts)
  opts = apply_cwd_only_aliases(opts)
  opts.include_current_session = vim.F.if_nil(opts.include_current_session, true)

  local current_buffer = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buffer)
  local results = {}

  if opts.include_current_session then
    for _, buffer in ipairs(vim.split(vim.fn.execute ":buffers! t", "\n")) do
      local match = tonumber(string.match(buffer, "%s*(%d+)"))
      local open_by_lsp = string.match(buffer, "line 0$")
      if match and not open_by_lsp then
        local file = vim.api.nvim_buf_get_name(match)
        if vim.loop.fs_stat(file) and match ~= current_buffer then
          table.insert(results, file)
        end
      end
    end
  end

  for _, file in ipairs(vim.v.oldfiles) do
    local file_stat = vim.loop.fs_stat(file)
    if file_stat and file_stat.type == "file" and not vim.tbl_contains(results, file) and file ~= current_file then
      table.insert(results, file)
    end
  end

  if opts.cwd_only or opts.cwd then
    local cwd = opts.cwd_only and vim.loop.cwd() or opts.cwd
    results = vim.tbl_filter(function(file)
      return buf_in_cwd(file, cwd)
    end, results)
  end

  return finders.new_table {
    results = results,
    entry_maker = opts.entry_maker or make_entry.gen_from_file(opts),
  }
end

-- Copy of the builtin.find_files picker with the following modifications:
-- - The final pickers.new(...):find() statement is omitted
-- - The table { opts = ..., find_command = ... } is returned instead
local builtin_find_files_copy = function(opts)
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
      search_dirs[k] = utils.path_expand(v)
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
    opts.cwd = utils.path_expand(opts.cwd)
  end

  opts.entry_maker = opts.entry_maker or make_entry.gen_from_file(opts)

  return { opts = opts, find_command = find_command }
end

local starts_with = function(text, prefix)
  return text:find(prefix, 1, true) == 1
end

local get_absolute_path = function(path)
  -- The second Path:new() and tostring() is needed to ensure trailing slash is stripped
  return tostring(Path:new(Path:new(path):absolute()))
end

local is_absolute_path = function(path)
  if not utils.iswin then
    return path:find "^/" == 1
  else
    path = path:gsub("/", "\\")
    return path:find "^[a-zA-Z]:\\" == 1 or path:find "^\\\\" == 1
  end
end

local make_relative_path = function(path, cwd_with_trailing_slash)
  if is_absolute_path(path) then
    if starts_with(path, cwd_with_trailing_slash) then
      return path:sub(#cwd_with_trailing_slash + 1)
    else
      return nil
    end
  else
    if starts_with(path, "./") or starts_with(path, ".\\") then
      return path:sub(3)
    else
      return path
    end
  end
end

local config = {}

local recent_files = function(opts)
  -- Merge given opts with opts provided in setup()
  opts = vim.tbl_extend("force", config, opts or {})

  opts.cwd = opts.cwd and get_absolute_path(opts.cwd) or vim.loop.cwd()
  opts.only_cwd = nil
  opts.cwd_only = nil

  local cwd_with_trailing_slash = ""
  if opts.cwd:sub(-1) == utils.get_separator() then
    cwd_with_trailing_slash = opts.cwd
  else
    cwd_with_trailing_slash = opts.cwd .. utils.get_separator()
  end

  local file_to_exclude = nil
  if not opts.include_current_file then
    local current_file = vim.api.nvim_buf_get_name(0)
    file_to_exclude = make_relative_path(current_file, cwd_with_trailing_slash)
  end

  local oldfiles_finder = builtin_oldfiles_copy(opts)

  -- Populate initial results from oldfiles, removing cwd prefix from paths
  opts.results = {}
  do
    local invalid_path_found = false
    for _, entry in ipairs(oldfiles_finder.results) do
      if entry.filename ~= nil then
        local stripped_filename = make_relative_path(entry.filename, cwd_with_trailing_slash)
        if stripped_filename ~= nil then
          entry.filename = stripped_filename
        else
          invalid_path_found = true
        end
      end
      opts.results[#opts.results + 1] = entry
    end

    if invalid_path_found then
      utils.notify("extension.recent-files", {
        msg = "One or more paths returned from oldfiles did not start with cwd. Results may have duplicates.",
        level = "WARN",
      })
    end
  end

  local num_oldfiles = #opts.results

  local oldfiles_lookup = {}
  for _, entry in ipairs(opts.results) do
    if entry.filename ~= nil then
      oldfiles_lookup[entry.filename] = true
    end
  end

  local find_files_base = builtin_find_files_copy(opts)

  if find_files_base == nil then
    return
  end

  opts = find_files_base.opts
  local find_command = find_files_base.find_command

  -- Wrap entry_maker to filter out entries already in oldfiles
  do
    local original_entry_maker = opts.entry_maker
    local invalid_path_seen = false
    opts.entry_maker = function(line)
      local entry = original_entry_maker(line)
      if entry ~= nil and entry.filename ~= nil then
        -- Strip cwd if needed to make path format consistent with existing results
        local stripped_filename = make_relative_path(entry.filename, cwd_with_trailing_slash)

        if stripped_filename ~= nil then
          entry.filename = stripped_filename
        else
          if not invalid_path_seen then
            utils.notify("extension.recent-files", {
              msg = "Find command returned an absolute path that did not start with cwd. Results may have duplicates.",
              level = "WARN",
            })
          end
          invalid_path_seen = true
        end

        -- Skip entry if file is in oldfiles or should be excluded
        if oldfiles_lookup[entry.filename] or entry.filename == file_to_exclude then
          entry = nil
        end
      end
      return entry
    end
  end

  -- Try to prioritize matches from oldfiles when searching
  opts.tiebreak = function(current_entry, existing_entry, _)
    -- Use default ordering for files not in oldfiles_table
    if current_entry.index > num_oldfiles and existing_entry.index > num_oldfiles then
      return #current_entry.ordinal < #existing_entry.ordinal
    end
    -- Otherwise favor the more recent file
    return current_entry.index < existing_entry.index
  end

  pickers
    .new(opts, {
      prompt_title = "Find Files (Recent)",
      finder = new_oneshot_job_alternate(find_command, opts),
      previewer = conf.file_previewer(opts),
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

    -- Fix `:Telescope recent-files` command not working.
    -- Ideally this plugin file would be renamed to recent_files.lua
    -- and recent_files would be used everywhere, but changing that
    -- now would break user configs.
    ["recent-files"] = recent_files,
  },
}
