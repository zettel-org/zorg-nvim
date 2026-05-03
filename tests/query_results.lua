local test = dofile("tests/testlib.lua")

local config = require("zorg.config")
local commands = require("zorg.commands")

local notifications, restore_notify = test.capture_notifications()

local root = test.tempdir("zorg-root")
local db = test.tempdir("zorg-db") .. "/zorg.sqlite3"
local bin = test.tempdir("zorg-bin") .. "/zorg"
test.write_executable(bin)

config.setup({
  root = root,
  db_path = db,
  cli = {
    command = bin,
  },
  lsp = {
    enabled = false,
  },
})

local runner = test.fake_runner()
commands._set_runner_for_test(runner.runner)
commands.setup()

local source = root .. "/inbox.z"
vim.fn.writefile({
  "%%% @task #z/todo",
  "[ ] Task",
  "%%%",
}, source)

runner.result = {
  code = 0,
  stdout = vim.json.encode(test.fixtures.query_list({
    test.fixtures.query_list_row({
      canonical_id = "@task",
      path = "inbox.z",
      title = "Task",
      todo_marker = "[ ]",
      span = test.fixtures.source_span({
        start_line = 2,
        start_column = 3,
        end_line = 2,
        end_column = 10,
      }),
    }),
  })),
  stderr = "",
}

vim.cmd("ZorgQuery #z/todo -did:*")
test.assert_last_argv(runner, {
  bin,
  "query",
  "--root",
  root,
  "--db",
  db,
  "--json",
  "#z/todo -did:*",
}, "inline query should request JSON and keep the SWOG query as one argument")
test.wait_for_current_buffer_name("Zorg Query Results", "list JSON should open a query result buffer")
local list_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(list_lines[1]:match("@task"), "list buffer should render the canonical ID")
assert(list_lines[1]:match("inbox%.z:2:3"), "list buffer should render the root-relative location")

commands.open_query_result()
test.wait_for(function()
  return vim.api.nvim_buf_get_name(0) == source
end, "opening a list result should edit the source path")
test.assert_eq(vim.api.nvim_win_get_cursor(0), { 2, 2 }, "opening a list result should jump to the span")

runner.result = {
  code = 0,
  stdout = vim.json.encode(test.fixtures.query_list({}, {
    diagnostics = {
      {
        severity = "warning",
        code = "query.empty",
        message = "empty result set",
      },
    },
  })),
  stderr = "",
}
vim.cmd("ZorgQuery #z/missing")
test.wait_for_current_buffer_name("Zorg Query Results", "empty list JSON should open a result buffer")
test.assert_current_lines({
  "No query results.",
  "",
  "Diagnostics",
  "  warning query.empty: empty result set",
}, "empty query buffers should include diagnostics")

runner.result = {
  code = 0,
  stdout = vim.json.encode(test.fixtures.query_table(nil, {
    {
      todo = "[ ]",
      id = "@task",
      file = "inbox.z",
      title = "Task",
    },
  })),
  stderr = "",
}
vim.cmd("ZorgQuery TABLE #z/todo")
test.wait_for_current_buffer_name("Zorg Query Results", "table JSON should open a result buffer")
local table_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(table_lines[1]:match("todo") and table_lines[1]:match("title"), "table buffer should render headers")
assert(table_lines[3]:match("@task") and table_lines[3]:match("inbox%.z"), "table buffer should render rows")

local before_invalid = #notifications
runner.result = {
  code = 0,
  stdout = "{not json",
  stderr = "",
}
vim.cmd("ZorgQuery #z/todo")
test.wait_for(function()
  return #notifications > before_invalid
end, "invalid JSON should notify")
assert(
  notifications[#notifications].message:match("invalid JSON"),
  "invalid JSON notification should describe the decode failure"
)
test.wait_for_current_buffer_name("Zorg Query Error", "invalid JSON should open an error buffer")

restore_notify()
