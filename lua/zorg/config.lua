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
  watcher = {
    enabled = true,
    autostart = false,
    debounce_ms = nil,
    show_logs = false,
    job_policy = "per_root",
  },
  mappings = {
    enabled = false,
    prefix = "<leader>z",
    keys = {
      capture = "c",
      export_current = "e",
      fix = "f",
      index = "i",
      open = "o",
      query = "q",
      status = "s",
      watch_start = "w",
      watch_status = "S",
      watch_stop = "W",
    },
  },
  lsp = {
    enabled = true,
    autostart = true,
    command = { "zorg-ls" },
    root_markers = { ".zorgroot", "init.z" },
    db_path = nil,
    database_path = nil,
    refresh_on_save = "diagnostics",
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

local function expand_optional(path)
  if path and path ~= "" then
    return vim.fn.expand(path)
  end

  return path
end

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  M.options.root = vim.fn.expand(M.options.root)
  M.options.db_path = expand_optional(M.options.db_path)
  M.options.database_path = expand_optional(M.options.database_path)
  M.options.lsp.db_path = expand_optional(M.options.lsp.db_path)
  M.options.lsp.database_path = expand_optional(M.options.lsp.database_path)
  return M.options
end

function M.get()
  return M.options
end

return M
