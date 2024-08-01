# telescope-recent-files

An extension for telescope.nvim that combines the results from builtin.oldfiles({cwd_only = true}) with builtin.find_files

In other words, it searches for files in the current directory, and displays files in order of how recently they were opened.

# Setup

Lazy:
```
{
 'nvim-telescope/telescope.nvim',
 tag = '0.1.5',
 dependencies = {
   'mollerhoj/telescope-recent-files.nvim',
 },
 config = function()
   require("telescope").load_extension("recent-files")
 end
},

-- A keymap
vim.keymap.set('n', '<leader>f', function()
  require('telescope').extensions['recent-files'].recent_files({})
end, { noremap = true, silent = true })
```

# Alternatives

I made this because I couldn't find a plugin that did exactly what I needed.

I would suggest this functionality be builtin to telescope (It would be quite simple, I would be happy to make a PR).

But based on this discussion, https://github.com/nvim-telescope/telescope.nvim/issues/2109, it seems the maintainers doesn't want it.

There are other plugins that tackles this, but have their issues:

- https://github.com/danielfalk/smart-open.nvim (Depends on a sqlite database, and does not integrate with neovims native oldfiles)
- https://github.com/nvim-telescope/telescope-frecency.nvim (Does not seem to load the oldfiles either?)

# Run on startup

The first thing I do is usually open a file within the current project I'm working in.

Thus, I've set this to run on startup:

```
vim.api.nvim_create_autocmd('VimEnter',{
  callback=function()
    if vim.fn.argc() == 0 then
      require('telescope').extensions['recent-files'].recent_files({})
    end
  end
})
```

