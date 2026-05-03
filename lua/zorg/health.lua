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

local function label(value)
  if value == nil then
    return "default"
  end

  return tostring(value)
end

local function bool_label(value)
  return value and "enabled" or "disabled"
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

local function help_contains(binary, args, needle)
  local argv = { binary }
  vim.list_extend(argv, args)
  local ok_system, output = pcall(vim.fn.systemlist, argv)
  if not ok_system then
    return false
  end

  return vim.v.shell_error == 0 and table.concat(output, "\n"):match(needle) ~= nil
end

local function report_contract(binary, args, needle, ok_message, warn_message)
  if help_contains(binary, args, needle) then
    ok(ok_message)
  else
    warn(warn_message)
  end
end

local function nvim_version()
  local ok_version, version = pcall(vim.version)
  if not ok_version or type(version) ~= "table" then
    return false, "unknown"
  end

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
    report_contract(
      cli_binary,
      { "watch", "--help" },
      "json",
      "zorg watch JSON contract appears available",
      "zorg watch JSON contract was not detected; watcher commands will report unavailable"
    )
    report_contract(
      cli_binary,
      { "query", "--help" },
      "%-%-json",
      "zorg query --json contract appears available",
      "zorg query --json contract was not detected; query buffers will report unavailable"
    )
    report_contract(
      cli_binary,
      { "import", "--help" },
      "legacy",
      "zorg import legacy contract appears available",
      "zorg import legacy contract was not detected; import wrappers will report unavailable"
    )
    report_contract(
      cli_binary,
      { "export", "--help" },
      "markdown",
      "zorg export markdown contract appears available",
      "zorg export markdown contract was not detected; export wrappers will report unavailable"
    )
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

  local watcher = opts.watcher or {}
  ok("Watcher integration is " .. bool_label(watcher.enabled))
  ok("Watcher autostart is " .. bool_label(watcher.autostart))
  ok("Watcher debounce override: " .. label(watcher.debounce_ms))
  ok("Watcher log display: " .. bool_label(watcher.show_logs))
  ok("Watcher job policy: " .. label(watcher.job_policy))

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
