local config = require("zorg.config")
local treesitter = require("zorg.treesitter")

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

  if treesitter.has_runtime() then
    ok("Tree-sitter runtime is available")

    local parser_name = opts.treesitter.parser_name or "zorg"
    local parser_ok, parser_err = treesitter.parser_available(parser_name)
    if parser_ok then
      ok("Tree-sitter parser is available: " .. parser_name)
    else
      warn("Tree-sitter parser is unavailable for " .. parser_name .. ": " .. tostring(parser_err))
    end

    for query_name, query in pairs(treesitter.query_status(parser_name)) do
      if query.available then
        ok("Tree-sitter " .. query_name .. " query found: " .. query.files[1])
      else
        warn("Tree-sitter " .. query_name .. " query was not found for " .. parser_name)
      end
    end
  else
    error("Tree-sitter runtime is unavailable in this Neovim build")
  end
end

return M
