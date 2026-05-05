local M = {}

local internal_modules = {}

local function module_dir()
  local source = debug.getinfo(1, "S").source
  if type(source) ~= "string" or source:sub(1, 1) ~= "@" then
    error("zorg.nvim internal loader could not determine lua/zorg module path", 2)
  end

  return vim.fn.fnamemodify(source:sub(2), ":p:h")
end

local function load_internal(name)
  local modname = "zorg." .. name
  local path = module_dir() .. "/" .. name .. ".lua"
  if internal_modules[name] and package.loaded[modname] == internal_modules[name] then
    return internal_modules[name]
  end

  local loaded = package.loaded[modname]
  if type(loaded) == "table" and type(loaded.setup) == "function" then
    local source = debug.getinfo(loaded.setup, "S").source
    local loaded_path = type(source) == "string"
        and source:sub(1, 1) == "@"
        and vim.fn.fnamemodify(source:sub(2), ":p")
      or nil
    if loaded_path == path then
      internal_modules[name] = loaded
      return loaded
    end
  end

  local chunk, load_err = loadfile(path)
  if not chunk then
    error(
      "zorg.nvim failed to load internal module "
        .. modname
        .. " from "
        .. path
        .. ": "
        .. tostring(load_err),
      2
    )
  end

  package.loaded[modname] = nil
  local ok, module = pcall(chunk)
  if not ok then
    package.loaded[modname] = nil
    error(
      "zorg.nvim failed to execute internal module "
        .. modname
        .. " from "
        .. path
        .. ": "
        .. tostring(module),
      2
    )
  end

  if type(module) ~= "table" then
    package.loaded[modname] = nil
    error(
      "zorg.nvim internal module "
        .. modname
        .. " from "
        .. path
        .. " returned "
        .. type(module)
        .. "; expected table",
      2
    )
  end

  internal_modules[name] = module
  package.loaded[modname] = module
  return module
end

function M.setup(opts)
  local config_module = load_internal("config")
  if type(config_module.setup) ~= "function" then
    error("zorg.nvim internal module zorg.config is missing setup()", 2)
  end

  local config = config_module.setup(opts)

  if config.treesitter.enabled then
    load_internal("treesitter").setup(config.treesitter)
  end

  local watcher = load_internal("watcher")
  if config.commands.enabled then
    load_internal("commands").setup()
  else
    watcher.setup(config.watcher)
  end

  load_internal("mappings").setup(config.mappings)

  if config.lsp.enabled then
    load_internal("lsp").setup(config.lsp)
  end

  return config
end

return M
