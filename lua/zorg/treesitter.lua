local M = {}

local default_parser_name = "zorg"
local default_filetype = "zorg"
local query_names = { "highlights", "folds", "locals", "injections" }

local function parser_name(opts)
  return (opts and opts.parser_name) or default_parser_name
end

function M.has_runtime()
  return type(vim.treesitter) == "table" and type(vim.treesitter.language) == "table"
end

function M.register_filetype(name, filetype)
  if not M.has_runtime() then
    return false, "Tree-sitter runtime is unavailable"
  end

  local register = vim.treesitter.language.register
  if type(register) ~= "function" then
    return false, "vim.treesitter.language.register is unavailable"
  end

  local ok, err = pcall(register, name or default_parser_name, filetype or default_filetype)
  if ok then
    return true
  end

  return false, err
end

function M.parser_available(name)
  if not M.has_runtime() then
    return false, "Tree-sitter runtime is unavailable"
  end

  name = name or default_parser_name

  if type(vim.treesitter.language.inspect) == "function" then
    local ok, err = pcall(vim.treesitter.language.inspect, name)
    if ok then
      return true
    end

    return false, err
  end

  local parser_files = vim.api.nvim_get_runtime_file("parser/" .. name .. ".*", false)
  if #parser_files > 0 then
    return true
  end

  return false, "parser/" .. name .. ".* was not found on runtimepath"
end

function M.query_files(name, query_name)
  name = name or default_parser_name
  return vim.api.nvim_get_runtime_file("queries/" .. name .. "/" .. query_name .. ".scm", false)
end

function M.query_available(name, query_name)
  local files = M.query_files(name, query_name)
  if #files > 0 then
    return true, files
  end

  return false, files
end

function M.query_status(name)
  name = name or default_parser_name

  local status = {}
  for _, query_name in ipairs(query_names) do
    local ok, files = M.query_available(name, query_name)
    status[query_name] = {
      available = ok,
      files = files,
    }
  end

  return status
end

function M.setup(opts)
  opts = opts or {}
  M.register_filetype(parser_name(opts), "zorg")
end

return M
