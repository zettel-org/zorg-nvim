local commands = require("zorg.commands")

local M = {}

local function split_args(args)
  if not args or args == "" then
    return {}
  end

  return vim.split(args, "%s+", { trimempty = true })
end

local function command_opts(args, extra)
  local opts = vim.tbl_extend("force", {
    args = args or "",
    bang = false,
    fargs = split_args(args),
  }, extra or {})

  return opts
end

local function append_value(args, flag, value)
  if value and value ~= "" then
    table.insert(args, flag)
    table.insert(args, value)
  end
end

function M.query(query)
  if not query or vim.trim(query) == "" then
    return
  end

  commands.query(command_opts(query))
end

function M.query_prompt()
  vim.ui.input({ prompt = "Zorg query: " }, function(input)
    M.query(input)
  end)
end

function M.capture(args)
  commands.capture({
    args = table.concat(args or {}, " "),
    bang = false,
    fargs = args or {},
  })
end

function M.capture_prompt(opts)
  opts = opts or {}

  local function with_template(template)
    if not template or vim.trim(template) == "" then
      return
    end

    vim.ui.input({ prompt = "Zorg title: " }, function(title)
      if title == nil then
        return
      end

      vim.ui.input({ prompt = "Zorg body: " }, function(body)
        if body == nil then
          return
        end

        local args = { "--template", template }
        append_value(args, "--title", title)
        append_value(args, "--body", body)
        M.capture(args)
      end)
    end)
  end

  if opts.template and opts.template ~= "" then
    with_template(opts.template)
    return
  end

  vim.ui.input({ prompt = "Zorg template: " }, with_template)
end

function M.fix_current_buffer(opts)
  opts = opts or {}
  commands.fix(command_opts("", { bang = opts.bang == true }))
end

function M.reindex_root(args)
  commands.index(command_opts(args))
end

function M.status(args)
  commands.status(command_opts(args))
end

return M
