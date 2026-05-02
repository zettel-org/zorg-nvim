local config = require("zorg.config")

local M = {}

local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error

function M.check()
  local opts = config.get()

  start("zorg.nvim")

  ok("zorg.nvim Lua modules are loadable")

  if vim.fn.executable(opts.cli.command) == 1 then
    ok(opts.cli.command .. " is executable")
  else
    warn(
      opts.cli.command .. " was not found; command stubs will fail until the Zorg CLI is installed"
    )
  end

  if vim.fn.executable(opts.lsp.command[1]) == 1 then
    ok(opts.lsp.command[1] .. " is executable")
  else
    warn(opts.lsp.command[1] .. " was not found; LSP startup will be skipped")
  end

  if vim.fn.isdirectory(opts.root) == 1 then
    ok("Zorg root exists: " .. opts.root)
  else
    warn("Zorg root does not exist yet: " .. opts.root)
  end

  if vim.treesitter and vim.treesitter.language then
    ok("Tree-sitter runtime is available")
  else
    error("Tree-sitter runtime is unavailable in this Neovim build")
  end
end

return M
