local config = require("zorg.config")

local M = {}

local augroup = vim.api.nvim_create_augroup("zorg_lsp", { clear = true })
local warned_missing = false

local function executable(cmd)
  return vim.fn.executable(cmd) == 1
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

function M.root_dir(bufnr)
  local opts = config.get()
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  local start = name ~= "" and dirname(name) or (vim.uv or vim.loop).cwd()

  return root_from_markers(start, opts.lsp.root_markers) or opts.root
end

function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local opts = config.get()
  local cmd = opts.lsp.command
  local binary = cmd[1]

  if not executable(binary) then
    if not warned_missing then
      warned_missing = true
      vim.notify("zorg-ls not found; Zorg LSP was not started", vim.log.levels.WARN)
    end
    return nil
  end

  return vim.lsp.start({
    name = "zorg-ls",
    cmd = cmd,
    root_dir = M.root_dir(bufnr),
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

  vim.api.nvim_clear_autocmds({ group = augroup })
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "zorg",
    callback = function(args)
      M.start(args.buf)
    end,
  })
end

return M
