vim.opt.runtimepath:prepend(vim.fn.getcwd())

local M = {}

M.fixtures = {}

function M.assert_eq(actual, expected, message)
  assert(
    vim.deep_equal(actual, expected),
    (message or "values should match")
      .. "\nexpected: "
      .. vim.inspect(expected)
      .. "\nactual: "
      .. vim.inspect(actual)
  )
end

function M.tempdir(name)
  local path = vim.fn.tempname() .. "-" .. name
  vim.fn.mkdir(path, "p")
  return path
end

function M.write_executable(path, output)
  local lines

  if type(output) == "table" then
    lines = output
  else
    lines = { "#!/bin/sh", "echo " .. vim.fn.shellescape(output or "fake zorg") }
  end

  vim.fn.writefile(lines, path)
  vim.fn.setfperm(path, "rwxr-xr-x")
end

function M.wait_for(predicate, message, timeout)
  local ok = vim.wait(timeout or 1000, predicate, 10)
  assert(ok, message)
end

function M.capture_notifications()
  local original_notify = vim.notify
  local notifications = {}

  vim.notify = function(message, level, opts)
    table.insert(notifications, { message = message, level = level, opts = opts })
  end

  return notifications, function()
    vim.notify = original_notify
  end
end

function M.fake_runner(initial_result)
  local state = {
    runs = {},
    result = initial_result or {
      code = 0,
      stdout = "",
      stderr = "",
    },
  }

  state.runner = function(argv, on_result)
    table.insert(state.runs, vim.deepcopy(argv))
    if type(state.result) == "function" then
      on_result(vim.deepcopy(state.result(argv, state)))
    else
      on_result(vim.deepcopy(state.result))
    end
  end

  return state
end

function M.assert_last_argv(state, expected, message)
  M.assert_eq(state.runs[#state.runs], expected, message)
end

function M.assert_current_lines(expected, message)
  M.assert_eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), expected, message)
end

function M.wait_for_current_buffer_name(pattern, message)
  M.wait_for(function()
    return vim.api.nvim_buf_get_name(0):match(pattern) ~= nil
  end, message)
end

function M.fixtures.source_span(extra)
  return vim.tbl_extend("force", {
    start_byte = 0,
    end_byte = 0,
    start_line = 1,
    start_column = 1,
    end_line = 1,
    end_column = 1,
  }, extra or {})
end

function M.fixtures.query_list_row(extra)
  return vim.tbl_extend("force", {
    store_row_id = 1,
    canonical_id = "@task",
    path = "task.z",
    title = "Task",
    todo_marker = "[ ]",
    source_order = 1,
    span = M.fixtures.source_span(),
    tags = { "z/todo" },
    properties = {},
  }, extra or {})
end

function M.fixtures.query_list(rows, extra)
  return vim.tbl_extend("force", {
    schema_version = 1,
    kind = "list",
    query_source = "inline",
    query = "#z/todo",
    query_zettel = nil,
    rows = rows or {},
    diagnostics = {},
  }, extra or {})
end

function M.fixtures.query_table(columns, rows, extra)
  return vim.tbl_extend("force", {
    schema_version = 1,
    kind = "table",
    query_source = "inline",
    query = "TABLE #z/todo",
    query_zettel = nil,
    columns = columns or {
      { key = "todo", label = "Todo" },
      { key = "id", label = "ID" },
      { key = "file", label = "File" },
      { key = "title", label = "Title" },
    },
    rows = rows or {},
    diagnostics = {},
  }, extra or {})
end

function M.fixtures.watcher_event(state, extra)
  return vim.tbl_extend("force", {
    schema_version = 1,
    state = state,
    root = "/tmp/zorg",
    database = "/tmp/zorg/.zorg/zorg.sqlite3",
  }, extra or {})
end

function M.fixtures.ndjson(events)
  local lines = {}

  for _, event in ipairs(events) do
    table.insert(lines, vim.json.encode(event))
  end

  return table.concat(lines, "\n")
end

function M.fixtures.refactor_preview(operation, files, extra)
  return vim.tbl_extend("force", {
    schema_version = 1,
    plan = vim.tbl_extend("force", {
      operation = operation,
      mode = "preview",
      root = "/tmp/zorg",
      target_id = "task",
      warnings = {},
      rejections = {},
      files = files or {},
    }, extra or {}),
  }, {})
end

return M
