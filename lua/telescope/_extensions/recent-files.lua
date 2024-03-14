local ok, telescope = pcall(require, 'telescope')

return telescope.register_extension {
    setup = function(_, _)
    end,
    exports = {
        list = function(_)
        end,
    },
}
