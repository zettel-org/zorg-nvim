local config = require("zorg.config")

local M = {}

local augroup = vim.api.nvim_create_augroup("zorg_lsp", { clear = true })
local warned_missing = false

local function command_binary(cmd)
  if type(cmd) == "table" then
    return cmd[1]
  end

  return cmd
end

local function executable(cmd)
  return vim.fn.executable(cmd) == 1
end

local function expand(path)
  if not path or path == "" then
    return nil
  end

  local expanded = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  if #expanded > 1 then
    expanded = expanded:gsub("[/\\]+$", "")
  end

  return expanded
end

local function dirname(path)
  if vim.fs and vim.fs.dirname then
    return vim.fs.dirname(path)
  end
  return vim.fn.fnamemodify(path, ":h")
end

local function root_from_markers(path, markers)
  if not (vim.fs and vim.fs.find) then
    return nil
  end

  local found = vim.fs.find(markers, {
    path = path,
    upward = true,
  })[1]

  if found then
    return dirname(found)
  end

  return nil
end

local function is_zorg_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  return vim.bo[bufnr].filetype == "zorg"
end

function M.root_dir(bufnr)
  local opts = config.get()
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  local start = name ~= "" and dirname(name) or (vim.uv or vim.loop).cwd()

  return expand(root_from_markers(start, opts.lsp.root_markers)) or expand(opts.root)
end

function M.initialization_options(root_dir)
  local opts = config.get()
  local lsp_opts = opts.lsp or {}
  local init = {
    rootPath = expand(root_dir or opts.root),
  }

  local database_path = lsp_opts.database_path or opts.database_path
  local db_path = lsp_opts.db_path or opts.db_path
  local trace = lsp_opts.trace or opts.trace
  local log_level = lsp_opts.log_level or opts.log_level

  if database_path then
    init.databasePath = expand(database_path)
  end
  if db_path then
    init.dbPath = expand(db_path)
  end
  if trace then
    init.trace = trace
  end
  if log_level then
    init.logLevel = log_level
  end
  if lsp_opts.refresh_on_save ~= nil then
    init.refreshOnSave = lsp_opts.refresh_on_save
  end

  return init
end

function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not is_zorg_buffer(bufnr) then
    return nil
  end

  local opts = config.get()
  local cmd = opts.lsp.command
  local binary = command_binary(cmd)

  if not executable(binary) then
    if not warned_missing then
      warned_missing = true
      vim.notify("zorg-ls not found; Zorg LSP was not started", vim.log.levels.WARN)
    end
    return nil
  end

  local root_dir = M.root_dir(bufnr)

  return vim.lsp.start({
    name = "zorg-ls",
    cmd = cmd,
    root_dir = root_dir,
    initialization_options = M.initialization_options(root_dir),
    settings = opts.lsp.settings,
  }, {
    bufnr = bufnr,
    reuse_client = function(client, client_config)
      return client.name == "zorg-ls" and client.config.root_dir == client_config.root_dir
    end,
  })
end

function M.setup()
  if not vim.lsp or not vim.lsp.start then
    return
  end

  local opts = config.get()
  vim.api.nvim_clear_autocmds({ group = augroup })
  if opts.lsp and opts.lsp.autostart == false then
    return
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "zorg",
    callback = function(args)
      M.start(args.buf)
    end,
  })
end

return M
