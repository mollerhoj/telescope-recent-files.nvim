local base = require("telescope._extensions.base")

return require("telescope").register_extension {
  setup = base.setup,
  exports = {
    recent_files = base.logic
  },
}
