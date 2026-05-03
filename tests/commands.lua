vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function assert_eq(actual, expected, message)
  assert(
    vim.deep_equal(actual, expected),
    (message or "values should match")
      .. "\nexpected: "
      .. vim.inspect(expected)
      .. "\nactual: "
      .. vim.inspect(actual)
  )
end

local function tempdir(name)
  local path = vim.fn.tempname() .. "-" .. name
  vim.fn.mkdir(path, "p")
  return path
end

local function write_executable(path)
  vim.fn.writefile({ "#!/bin/sh", "echo fake zorg" }, path)
  vim.fn.setfperm(path, "rwxr-xr-x")
end

local function wait_for(predicate, message)
  local ok = vim.wait(1000, predicate, 10)
  assert(ok, message)
end

local config = require("zorg.config")
local commands = require("zorg.commands")

local original_notify = vim.notify
local notifications = {}
vim.notify = function(message, level)
  table.insert(notifications, { message = message, level = level })
end

local root = tempdir("zorg-root")
local db = tempdir("zorg-db") .. "/zorg.sqlite3"
local bin = tempdir("zorg-bin") .. "/zorg"
write_executable(bin)

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

local runs = {}
local next_result = {
  code = 0,
  stdout = "",
  stderr = "",
}

commands._set_runner_for_test(function(argv, on_result)
  table.insert(runs, vim.deepcopy(argv))
  on_result(next_result)
end)
commands.setup()

vim.cmd("ZorgIndex")
assert_eq(runs[#runs], {
  bin,
  "db",
  "reindex",
  "--root",
  root,
  "--db",
  db,
}, "ZorgIndex should call db reindex for the configured root")

vim.cmd("ZorgStatus")
assert_eq(runs[#runs], {
  bin,
  "db",
  "status",
  "--root",
  root,
  "--db",
  db,
}, "ZorgStatus should call db status for the configured root")

next_result = {
  code = 0,
  stdout = "[ ] @task  inbox.z  Task",
  stderr = "",
}
vim.cmd("ZorgQuery #z/todo -did:*")
assert_eq(runs[#runs], {
  bin,
  "query",
  "--root",
  root,
  "--db",
  db,
  "#z/todo -did:*",
}, "ZorgQuery should preserve inline SWOG as one CLI argument")
wait_for(function()
  return vim.api.nvim_buf_get_name(0):match("Zorg Query Results") ~= nil
end, "query output should open a result buffer")
assert_eq(
  vim.api.nvim_buf_get_lines(0, 0, -1, false),
  { "[ ] @task  inbox.z  Task" },
  "query result buffer should contain stdout"
)

vim.cmd("ZorgQuery --id @query/daily")
assert_eq(runs[#runs], {
  bin,
  "query",
  "--root",
  root,
  "--db",
  db,
  "--id",
  "@query/daily",
}, "ZorgQuery --id should preserve flag arguments")

next_result = {
  code = 2,
  stdout = "",
  stderr = "query index is stale",
}
local before_failure = #notifications
vim.cmd("ZorgQuery #z/todo")
wait_for(function()
  return #notifications > before_failure
end, "nonzero query should notify")
assert(
  notifications[#notifications].message:match("query index is stale"),
  "nonzero notification should include stderr"
)

next_result = {
  code = 0,
  stdout = "",
  stderr = "",
}
local note = root .. "/note.z"
vim.fn.writefile({ "%%% @note #z/ref", "Note", "%%%" }, note)
vim.cmd("edit " .. vim.fn.fnameescape(note))
vim.bo.filetype = "zorg"
vim.cmd("ZorgFix")
assert_eq(runs[#runs], { bin, "fix", note }, "ZorgFix should default to the current .z buffer")

vim.api.nvim_buf_set_lines(0, 1, 2, false, { "Changed note" })
local before_modified = #runs
local before_modified_notify = #notifications
vim.cmd("ZorgFix")
assert_eq(#runs, before_modified, "ZorgFix should not run against an unwritten modified buffer")
assert(
  #notifications > before_modified_notify
    and notifications[#notifications].message:match("Write the buffer"),
  "modified buffer path should notify with the conservative write guidance"
)

vim.cmd("ZorgFix!")
assert_eq(
  runs[#runs],
  { bin, "fix", note },
  "ZorgFix! should write before running current-buffer fix"
)

local captured = root .. "/captured.z"
vim.fn.writefile({ "%%% @captured #z/ref", "Captured", "%%%" }, captured)
next_result = {
  code = 0,
  stdout = vim.json.encode({
    destination = captured,
    zettel_id = "@captured",
  }),
  stderr = "",
}

vim.cmd("ZorgCapture --template @tmpl --title Task")
assert_eq(runs[#runs], {
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
wait_for(function()
  return vim.api.nvim_buf_get_name(0) == captured
end, "capture JSON success should open the created destination")

vim.notify = original_notify
