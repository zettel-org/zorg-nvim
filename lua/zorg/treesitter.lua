local M = {}

function M.setup(opts)
  opts = opts or {}
  local parser_name = opts.parser_name or "zorg"

  if vim.treesitter and vim.treesitter.language and vim.treesitter.language.register then
    pcall(vim.treesitter.language.register, parser_name, "zorg")
  end
end

return M
