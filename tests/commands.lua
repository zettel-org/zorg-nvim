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

local runner = test.fake_runner({
  code = 0,
  stdout = "",
  stderr = "",
})
commands._set_runner_for_test(runner.runner)
commands.setup()

vim.cmd("ZorgIndex")
test.assert_last_argv(runner, {
  bin,
  "db",
  "reindex",
  "--root",
  root,
  "--db",
  db,
}, "ZorgIndex should call db reindex for the configured root")

vim.cmd("ZorgStatus")
test.assert_last_argv(runner, {
  bin,
  "db",
  "status",
  "--root",
  root,
  "--db",
  db,
}, "ZorgStatus should call db status for the configured root")

runner.result = {
  code = 0,
  stdout = vim.json.encode(test.fixtures.query_list({
    test.fixtures.query_list_row({
      canonical_id = "@task",
      path = "inbox.z",
      title = "Task",
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
}, "ZorgQuery should prefer JSON and preserve inline SWOG as one CLI argument")
test.wait_for_current_buffer_name("Zorg Query Results", "query output should open a result buffer")
assert(
  vim.api.nvim_buf_get_lines(0, 0, -1, false)[1]:match("@task")
    and vim.api.nvim_buf_get_lines(0, 0, -1, false)[1]:match("inbox%.z:1:1"),
  "query result buffer should render JSON row identity and location"
)

vim.cmd("ZorgQuery --id @query/daily")
test.assert_last_argv(runner, {
  bin,
  "query",
  "--root",
  root,
  "--db",
  db,
  "--json",
  "--id",
  "@query/daily",
}, "ZorgQuery --id should prefer JSON and preserve flag arguments")

runner.result = {
  code = 0,
  stdout = "[ ] @task  inbox.z  Task",
  stderr = "",
}
vim.cmd("ZorgQuery --format list #z/todo -did:*")
test.assert_last_argv(runner, {
  bin,
  "query",
  "--root",
  root,
  "--db",
  db,
  "--format",
  "list",
  "#z/todo -did:*",
}, "ZorgQuery should keep explicit text/list output requests")

runner.result = {
  code = 2,
  stdout = "",
  stderr = "query index is stale",
}
local before_failure = #notifications
vim.cmd("ZorgQuery #z/todo")
test.wait_for(function()
  return #notifications > before_failure
end, "nonzero query should notify")
assert(
  notifications[#notifications].message:match("query index is stale"),
  "nonzero notification should include stderr"
)

runner.result = {
  code = 0,
  stdout = "",
  stderr = "",
}
local note = root .. "/note.z"
vim.fn.writefile({ "%%% @note #z/ref", "Note", "%%%" }, note)
vim.cmd("edit " .. vim.fn.fnameescape(note))
vim.bo.filetype = "zorg"
vim.cmd("ZorgFix")
test.assert_last_argv(runner, {
  bin,
  "fix",
  "--root",
  root,
  "--db",
  db,
  note,
}, "ZorgFix should default to the current .z buffer and pass store options")

vim.api.nvim_buf_set_lines(0, 1, 2, false, { "Changed note" })
local before_modified = #runner.runs
local before_modified_notify = #notifications
vim.cmd("ZorgFix")
test.assert_eq(#runner.runs, before_modified, "ZorgFix should not run against an unwritten modified buffer")
assert(
  #notifications > before_modified_notify
    and notifications[#notifications].message:match("Write the buffer"),
  "modified buffer path should notify with the conservative write guidance"
)

vim.cmd("ZorgFix!")
test.assert_last_argv(runner, {
  bin,
  "fix",
  "--root",
  root,
  "--db",
  db,
  note,
}, "ZorgFix! should write before running current-buffer fix")

local captured = root .. "/captured.z"
vim.fn.writefile({ "%%% @captured #z/ref", "Captured", "%%%" }, captured)
runner.result = {
  code = 0,
  stdout = vim.json.encode({
    destination = captured,
    zettel_id = "@captured",
  }),
  stderr = "",
}

vim.cmd("ZorgCapture --template @tmpl --title Task")
test.assert_last_argv(runner, {
  bin,
  "capture",
  "--root",
  root,
  "--db",
  db,
  "--json",
  "--template",
  "@tmpl",
  "--title",
  "Task",
}, "ZorgCapture should prefer JSON and pass store options")
test.wait_for(function()
  return vim.api.nvim_buf_get_name(0) == captured
end, "capture JSON success should open the created destination")

restore_notify()
