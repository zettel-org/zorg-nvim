local test = dofile("tests/testlib.lua")

for _, name in ipairs({ "config", "treesitter", "commands", "watcher", "mappings", "lsp" }) do
  package.loaded["zorg." .. name] = true
end

local root = test.tempdir("zorg-module-loading-root")
vim.fn.writefile({}, root .. "/.zorgroot")

local config = require("zorg").setup({
  root = root,
  commands = {
    enabled = true,
  },
  watcher = {
    autostart = false,
  },
  mappings = {
    enabled = false,
  },
  lsp = {
    enabled = true,
    autostart = false,
  },
  treesitter = {
    enabled = true,
  },
})

assert(config.root == root, "setup should succeed after poisoned internal module cache")

for _, name in ipairs({ "config", "treesitter", "commands", "watcher", "mappings", "lsp" }) do
  local module = require("zorg." .. name)
  assert(
    type(module) == "table",
    "zorg." .. name .. " should be replaced with the plugin module table"
  )
end

assert(
  type(require("zorg.config").setup) == "function",
  "zorg.config.setup should be available after setup"
)
