local config = require("zorg.config")
local treesitter = require("zorg.treesitter")

local M = {}

local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error

local function command_binary(command)
  if type(command) == "table" then
    return command[1]
  end

  return command
end

local function first_line(lines)
  if type(lines) == "table" and lines[1] and lines[1] ~= "" then
    return lines[1]
  end

  return nil
end

local function executable_version(command)
  local binary = command_binary(command)
  if vim.fn.executable(binary) ~= 1 then
    return false, binary
  end

  local output = vim.fn.systemlist({ binary, "--version" })
  local version = first_line(output)
  if vim.v.shell_error == 0 and version then
    return true, binary, version
  end

  return true, binary, nil
end

local function nvim_version()
  if type(vim.version) ~= "function" then
    return false, "unknown"
  end

  local version = vim.version()
  local label =
    string.format("%d.%d.%d", version.major or 0, version.minor or 0, version.patch or 0)
  return (version.major or 0) > 0 or (version.minor or 0) >= 10, label
end

function M.check()
  local opts = config.get()

  start("zorg.nvim")

  ok("zorg.nvim Lua modules are loadable")

  local supported, version = nvim_version()
  if supported then
    ok("Neovim version is supported: " .. version)
  else
    error("Neovim 0.10 or newer is required; current version: " .. version)
  end

  local cli_found, cli_binary, cli_version = executable_version(opts.cli.command)
  if cli_found then
    ok(cli_binary .. " is executable" .. (cli_version and ": " .. cli_version or ""))
  else
    warn(cli_binary .. " was not found; command stubs will fail until the Zorg CLI is installed")
  end

  local lsp_found, lsp_binary, lsp_version = executable_version(opts.lsp.command)
  if lsp_found then
    ok(lsp_binary .. " is executable" .. (lsp_version and ": " .. lsp_version or ""))
  else
    warn(lsp_binary .. " was not found; LSP startup will be skipped")
  end

  if vim.fn.isdirectory(opts.root) == 1 then
    ok("Zorg root exists: " .. opts.root)
  else
    warn("Zorg root does not exist yet: " .. opts.root)
  end

  local database_path = opts.lsp.database_path
    or opts.database_path
    or opts.lsp.db_path
    or opts.db_path
  if database_path then
    ok("Configured Zorg database path: " .. database_path)
  else
    ok("Configured Zorg database path: default under root")
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
