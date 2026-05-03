vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("filetype plugin on")

local config = require("zorg").setup({
  lsp = {
    enabled = false,
  },
})

assert(config.root ~= nil and config.root ~= "", "setup should return a configured root")

vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.getcwd() .. "/.tests/sample.z"))
assert(vim.bo.filetype == "zorg", "*.z buffers should use the zorg filetype")
assert(vim.bo.commentstring == "# %s", "zorg ftplugin should set commentstring")
assert(vim.bo.comments == ":#", "zorg ftplugin should set comments")

local treesitter = require("zorg.treesitter")
assert(treesitter.has_runtime(), "Tree-sitter runtime should be available in Neovim")

local registered, register_err = treesitter.register_filetype("zorg", "zorg")
assert(registered, "zorg parser registration should be safe: " .. tostring(register_err))

local query_ok, query_files = treesitter.query_available("zorg", "highlights")
assert(query_ok, "zorg highlight query should be on runtimepath")
assert(#query_files > 0, "zorg highlight query lookup should return a runtime file")

if vim.treesitter.query and vim.treesitter.query.get_files then
  local files = vim.treesitter.query.get_files("zorg", "highlights")
  assert(#files > 0, "Neovim query lookup should find zorg highlights")
end

for _, command in ipairs({ "ZorgIndex", "ZorgQuery", "ZorgFix", "ZorgCapture" }) do
  assert(vim.fn.exists(":" .. command) == 2, command .. " should exist")
end
