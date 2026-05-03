local test = dofile("tests/testlib.lua")

local config = require("zorg.config")

local root = test.tempdir("zorg-root")
local db_dir = test.tempdir("zorg-db")

local opts = config.setup({
  root = root,
  database_path = db_dir .. "/main.sqlite3",
  db_path = "~/zorg-db-compat.sqlite3",
  watcher = {
    autostart = true,
    debounce_ms = 250,
    show_logs = true,
    job_policy = "per_root",
  },
  lsp = {
    database_path = db_dir .. "/lsp.sqlite3",
    db_path = "~/zorg-lsp-db.sqlite3",
  },
})

test.assert_eq(opts.root, root, "root should remain backward compatible")
test.assert_eq(
  opts.database_path,
  db_dir .. "/main.sqlite3",
  "database_path should be preserved and expanded"
)
test.assert_eq(
  opts.db_path,
  vim.fn.expand("~/zorg-db-compat.sqlite3"),
  "db_path alias should be preserved and expanded"
)
test.assert_eq(
  opts.lsp.database_path,
  db_dir .. "/lsp.sqlite3",
  "lsp database_path should be expanded"
)
test.assert_eq(
  opts.lsp.db_path,
  vim.fn.expand("~/zorg-lsp-db.sqlite3"),
  "lsp db_path alias should be expanded"
)
test.assert_eq(opts.watcher.enabled, true, "watcher integration should be enabled by default")
test.assert_eq(opts.watcher.autostart, true, "watcher autostart should be configurable")
test.assert_eq(opts.watcher.debounce_ms, 250, "watcher debounce override should be configurable")
test.assert_eq(opts.watcher.show_logs, true, "watcher log preference should be configurable")
test.assert_eq(opts.watcher.job_policy, "per_root", "watcher job policy should be configurable")

local defaults = config.setup({})
test.assert_eq(defaults.mappings.enabled, false, "mappings should stay disabled by default")
test.assert_eq(defaults.watcher.enabled, true, "watcher integration should default enabled")
test.assert_eq(defaults.watcher.autostart, false, "watcher autostart should stay disabled by default")
test.assert_eq(defaults.watcher.debounce_ms, nil, "watcher debounce should default to Rust behavior")
test.assert_eq(defaults.watcher.show_logs, false, "watcher logs should not open by default")
test.assert_eq(defaults.watcher.job_policy, "per_root", "watcher should default to one job per root")
