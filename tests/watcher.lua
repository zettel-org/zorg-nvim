local test = dofile("tests/testlib.lua")

local config = require("zorg.config")
local commands = require("zorg.commands")
local watcher = require("zorg.watcher")

local notifications, restore_notify = test.capture_notifications()

local root = test.tempdir("zorg-root")
local db = test.tempdir("zorg-db") .. "/zorg.sqlite3"
local bin = test.tempdir("zorg-bin") .. "/zorg"
test.write_executable(bin)

config.setup({
  root = root,
  database_path = db,
  cli = {
    command = bin,
  },
  watcher = {
    enabled = true,
    autostart = false,
    debounce_ms = 75,
    show_logs = false,
    job_policy = "per_root",
  },
  lsp = {
    enabled = false,
  },
})

local jobs = {}
local starts = {}
local stops = {}
local next_job_id = 10

watcher._reset_for_test()
watcher._set_jobstart_for_test(function(argv, opts)
  local job_id = next_job_id
  next_job_id = next_job_id + 1
  starts[#starts + 1] = vim.deepcopy(argv)
  jobs[job_id] = opts
  return job_id
end, function(job_id)
  table.insert(stops, job_id)
  jobs[job_id].on_exit(job_id, 0)
  return 1
end)
commands.setup()

vim.cmd("ZorgWatchStart")
test.assert_eq(starts[1], {
  bin,
  "watch",
  "--root",
  root,
  "--db",
  db,
  "--format",
  "json",
  "--debounce",
  "75",
}, "ZorgWatchStart should start the Rust watcher JSON contract")

jobs[10].on_stdout(10, {
  vim.json.encode(test.fixtures.watcher_event("starting", {
    root = root,
    database = db,
  })),
  vim.json.encode(test.fixtures.watcher_event("ready", {
    root = root,
    database = db,
  })),
  vim.json.encode(test.fixtures.watcher_event("indexed", {
    root = root,
    database = db,
    summary = {
      discovered_files = 1,
      indexed_files = 1,
      unchanged_files = 0,
      new_files = 1,
      changed_files = 0,
      deleted_files = 0,
      zettel_count = 1,
      diagnostic_count = 0,
      effective_tag_count = 1,
      last_indexed_at_unix_ms = 1,
    },
  })),
  "",
})
test.assert_eq(watcher._state_for_test(root).state, "indexed", "watcher should parse JSON lifecycle states")

local before_duplicate = #starts
vim.cmd("ZorgWatchStart")
test.assert_eq(#starts, before_duplicate, "duplicate watcher start should be refused for the same root")
assert(
  notifications[#notifications].message:match("already running"),
  "duplicate watcher start should notify"
)

vim.cmd("ZorgWatchStatus")
test.wait_for_current_buffer_name("Zorg Watch Status", "watch status should open a scratch buffer")
local status_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(status_text:match("State: indexed"), "watch status should render the latest lifecycle state")
assert(status_text:match("indexed_files=1"), "watch status should render indexed summary fields")

vim.cmd("ZorgWatchStop")
test.assert_eq(stops, { 10 }, "ZorgWatchStop should stop the managed job")
test.assert_eq(watcher._state_for_test(root).state, "stopped", "normal watcher exit should mark stopped")

vim.cmd("ZorgWatchStart --exit-after-ready")
test.assert_eq(starts[2], {
  bin,
  "watch",
  "--root",
  root,
  "--db",
  db,
  "--format",
  "json",
  "--debounce",
  "75",
  "--exit-after-ready",
}, "ZorgWatchStart should preserve explicit bounded watcher flags")

jobs[11].on_stdout(11, { "not json", "" })
test.assert_eq(watcher._state_for_test(root).state, "error", "invalid watcher JSON should mark an error")
assert(notifications[#notifications].message:match("invalid JSON"), "invalid watcher JSON should notify")

jobs[11].on_stderr(11, { "watcher setup failed" })
jobs[11].on_exit(11, 1)
test.assert_eq(watcher._state_for_test(root).state, "error", "failed watcher exit should stay errored")
assert(notifications[#notifications].message:match("exit 1"), "failed watcher exit should notify")

config.setup({
  root = root,
  cli = {
    command = bin,
  },
  watcher = {
    enabled = false,
  },
})

local before_disabled = #starts
vim.cmd("ZorgWatchStart")
test.assert_eq(#starts, before_disabled, "disabled watcher integration should not start a job")
assert(notifications[#notifications].message:match("disabled"), "disabled watcher start should notify")

restore_notify()
