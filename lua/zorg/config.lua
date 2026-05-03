local M = {}

local defaults = {
  root = vim.fn.expand("~/zorg"),
  db_path = nil,
  database_path = nil,
  trace = nil,
  log_level = nil,
  cli = {
    command = "zorg",
  },
  commands = {
    enabled = true,
  },
  lsp = {
    enabled = true,
    command = { "zorg-ls" },
    root_markers = { ".zorgroot", "init.z" },
    db_path = nil,
    database_path = nil,
    trace = nil,
    log_level = nil,
    settings = {},
  },
  treesitter = {
    enabled = true,
    parser_name = "zorg",
  },
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  M.options.root = vim.fn.expand(M.options.root)
  if M.options.db_path then
    M.options.db_path = vim.fn.expand(M.options.db_path)
  end
  if M.options.database_path then
    M.options.database_path = vim.fn.expand(M.options.database_path)
  end
  if M.options.lsp.db_path then
    M.options.lsp.db_path = vim.fn.expand(M.options.lsp.db_path)
  end
  if M.options.lsp.database_path then
    M.options.lsp.database_path = vim.fn.expand(M.options.lsp.database_path)
  end
  return M.options
end

function M.get()
  return M.options
end

return M
