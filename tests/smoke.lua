vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("filetype on")

local config = require("zorg").setup({
  lsp = {
    enabled = false,
  },
})

assert(config.root ~= nil and config.root ~= "", "setup should return a configured root")

vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.getcwd() .. "/.tests/sample.z"))
assert(vim.bo.filetype == "zorg", "*.z buffers should use the zorg filetype")

for _, command in ipairs({ "ZorgIndex", "ZorgQuery", "ZorgFix", "ZorgCapture" }) do
  assert(vim.fn.exists(":" .. command) == 2, command .. " should exist")
end
