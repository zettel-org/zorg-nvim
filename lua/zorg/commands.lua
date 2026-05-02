local config = require("zorg.config")

local M = {}

local function notify(message, level)
  vim.schedule(function()
    vim.notify(message, level or vim.log.levels.INFO)
  end)
end

local function executable(command)
  return vim.fn.executable(command) == 1
end

local function run_zorg(subcommand, args)
  local opts = config.get()
  local command = opts.cli.command

  if not executable(command) then
    vim.notify(command .. " not found; :Zorg" .. subcommand .. " cannot run", vim.log.levels.ERROR)
    return
  end

  local argv = { command, string.lower(subcommand), "--root", opts.root }
  vim.list_extend(argv, args or {})

  if vim.system then
    vim.system(argv, { text = true }, function(result)
      local output = vim.trim((result.stdout or "") .. (result.stderr or ""))
      if result.code == 0 then
        notify(output ~= "" and output or "Zorg " .. subcommand .. " completed")
      else
        notify(output ~= "" and output or "Zorg " .. subcommand .. " failed", vim.log.levels.ERROR)
      end
    end)
    return
  end

  vim.fn.jobstart(argv, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function(_, code)
      if code == 0 then
        notify("Zorg " .. subcommand .. " completed")
      else
        notify("Zorg " .. subcommand .. " failed", vim.log.levels.ERROR)
      end
    end,
  })
end

local function create_command(name, subcommand, opts)
  opts = vim.tbl_extend("force", { force = true }, opts or {})

  vim.api.nvim_create_user_command(name, function(command_opts)
    run_zorg(subcommand, command_opts.fargs)
  end, opts)
end

function M.setup()
  create_command("ZorgIndex", "Index", {
    desc = "Index the configured Zorg root",
    nargs = "*",
  })
  create_command("ZorgQuery", "Query", {
    desc = "Run a Zorg LIST query",
    nargs = "*",
  })
  create_command("ZorgFix", "Fix", {
    desc = "Run Zorg strict check or safe fixes",
    nargs = "*",
  })
  create_command("ZorgCapture", "Capture", {
    desc = "Capture a zettel through the Zorg CLI",
    nargs = "*",
  })
end

return M
