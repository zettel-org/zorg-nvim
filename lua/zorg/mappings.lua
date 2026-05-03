local M = {}

local registered = {}

local function clear_registered()
  for _, lhs in ipairs(registered) do
    pcall(vim.keymap.del, "n", lhs)
  end
  registered = {}
end

local function map(lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, {
    desc = desc,
    silent = true,
  })
  table.insert(registered, lhs)
end

function M.setup(opts)
  clear_registered()

  if not opts or not opts.enabled then
    return
  end

  local prefix = opts.prefix or "<leader>z"
  local keys = opts.keys or {}

  map(prefix .. (keys.index or "i"), function()
    require("zorg.helpers").reindex_root()
  end, "Zorg reindex root")

  map(prefix .. (keys.query or "q"), function()
    require("zorg.helpers").query_prompt()
  end, "Zorg query prompt")

  map(prefix .. (keys.fix or "f"), function()
    require("zorg.helpers").fix_current_buffer()
  end, "Zorg fix current buffer")

  map(prefix .. (keys.capture or "c"), function()
    require("zorg.helpers").capture_prompt()
  end, "Zorg capture prompt")

  map(prefix .. (keys.status or "s"), function()
    require("zorg.helpers").status()
  end, "Zorg database status")
end

function M._registered_for_test()
  return vim.deepcopy(registered)
end

return M
