local M = {}

function M.setup(opts)
  local config = require("zorg.config").setup(opts)

  if config.treesitter.enabled then
    require("zorg.treesitter").setup(config.treesitter)
  end

  if config.commands.enabled then
    require("zorg.commands").setup()
  else
    require("zorg.watcher").setup(config.watcher)
  end

  require("zorg.mappings").setup(config.mappings)

  if config.lsp.enabled then
    require("zorg.lsp").setup(config.lsp)
  end

  return config
end

return M
