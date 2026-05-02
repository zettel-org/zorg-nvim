local M = {}

local defaults = {
  root = vim.fn.expand("~/zorg"),
  cli = {
    command = "zorg",
  },
  commands = {
    enabled = true,
  },
  lsp = {
    enabled = true,
    command = { "zorg-ls" },
    root_markers = { ".zorgroot" },
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
  return M.options
end

function M.get()
  return M.options
end

return M
