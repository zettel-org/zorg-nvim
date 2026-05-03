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

local function argv_has(argv, needle)
  for _, arg in ipairs(argv) do
    if arg == needle then
      return true
    end
  end

  return false
end

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

runner.result = {
  code = 0,
  stdout = vim.json.encode({
    schema_version = 1,
    command = "import legacy plan",
    mode = "plan",
    inputs = {
      {
        path = "legacy/project.zo",
        kind = "legacy_note",
      },
    },
    outputs = {
      {
        input_path = "legacy/project.zo",
        root_relative_path = "imported/legacy/project.z",
        canonical_id = "legacy/project",
        status = "planned",
        lossiness = { "tick_history_collapsed" },
      },
    },
    diagnostics = {
      {
        severity = "warning",
        kind = "lossy",
        code = "legacy.tick_history_collapsed",
        path = "legacy/project.zo",
        line = 5,
        message = "tick:: was converted to modified::",
      },
      {
        severity = "error",
        kind = "unsupported",
        code = "legacy.custom_fence",
        path = "legacy/project.zo",
        line = 9,
        message = "custom fence cannot be represented",
      },
    },
    collisions = {},
    summary = {
      planned = 1,
      lossy = 1,
      unsupported = 1,
      fatal = 1,
    },
  }),
  stderr = "",
}
vim.cmd("ZorgImportPlan legacy/project.zo --dest imported")
test.assert_last_argv(runner, {
  bin,
  "import",
  "legacy",
  "plan",
  "--root",
  root,
  "--json",
  "legacy/project.zo",
  "--dest",
  "imported",
}, "ZorgImportPlan should call the Rust JSON planner with the configured root")
test.wait_for_current_buffer_name("Zorg ImportPlan", "import plan should open a review buffer")
local import_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(table.concat(import_lines, "\n"):match("Writes"), "import plan should include write targets")
assert(table.concat(import_lines, "\n"):match("Lossy Transforms"), "import plan should separate lossy output")
assert(table.concat(import_lines, "\n"):match("Unsupported Forms"), "import plan should separate unsupported forms")
assert(table.concat(import_lines, "\n"):match("Errors"), "import plan should include errors")

local original_ui_select = vim.ui.select
local select_prompt = nil
vim.ui.select = function(items, opts, callback)
  select_prompt = opts.prompt
  callback(items[1])
end
runner.result = {
  code = 0,
  stdout = vim.json.encode({
    schema_version = 1,
    command = "import legacy apply",
    mode = "apply",
    inputs = {},
    outputs = {},
    diagnostics = {},
    collisions = {},
    summary = {
      planned = 0,
      lossy = 0,
      unsupported = 0,
      fatal = 0,
    },
    write_results = {
      {
        input_path = "legacy/project.zo",
        root_relative_path = "legacy/project.z",
        path = root .. "/legacy/project.z",
        status = "written",
      },
    },
  }),
  stderr = "",
}
vim.cmd("ZorgImportApply legacy/project.zo")
assert(select_prompt:match("Apply legacy Zorg import plan"), "ZorgImportApply should confirm before writing")
test.assert_last_argv(runner, {
  bin,
  "import",
  "legacy",
  "apply",
  "--root",
  root,
  "--json",
  "legacy/project.zo",
}, "ZorgImportApply should call the Rust JSON apply contract after confirmation")
test.wait_for_current_buffer_name("Zorg ImportApply", "import apply should open a write report")
assert(
  table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("Write Results"),
  "import apply should render write results"
)
vim.ui.select = original_ui_select

vim.cmd("edit " .. vim.fn.fnameescape(note))
vim.bo.filetype = "zorg"
runner.result = {
  code = 0,
  stdout = "# Note\n\nExported body",
  stderr = "",
}
vim.cmd("ZorgExportCurrent --stdout")
test.assert_last_argv(runner, {
  bin,
  "export",
  "markdown",
  "--root",
  root,
  "--db",
  db,
  "--id",
  "@note",
  "--stdout",
}, "ZorgExportCurrent should export the current zettel ID through the Rust CLI")
test.wait_for_current_buffer_name("Zorg ExportCurrent", "export stdout should open a Markdown buffer")
test.assert_current_lines({ "# Note", "", "Exported body" }, "export stdout should render Markdown text")

runner.result = {
  code = 0,
  stdout = vim.json.encode({
    schema_version = 1,
    command = "export markdown",
    selection = {
      kind = "single",
      canonical_id = "note",
    },
    output = {
      mode = "directory",
      directory = root .. "/out",
      written = {
        {
          canonical_id = "note",
          path = root .. "/out/note.md",
        },
      },
    },
    items = {
      {
        canonical_id = "note",
        source_path = "note.z",
        title = "Note",
      },
    },
    diagnostics = {},
    summary = {
      planned = 1,
      rendered = 1,
      lossy = 0,
      fatal = 0,
    },
  }),
  stderr = "",
}
vim.cmd("ZorgExportMarkdown --id @note --out " .. vim.fn.fnameescape(root .. "/out") .. " --json")
test.assert_last_argv(runner, {
  bin,
  "export",
  "markdown",
  "--root",
  root,
  "--db",
  db,
  "--id",
  "@note",
  "--out",
  root .. "/out",
  "--json",
}, "ZorgExportMarkdown should pass explicit export selectors and output flags")
test.wait_for_current_buffer_name("Zorg ExportMarkdown", "export JSON should open a report buffer")
assert(
  table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("Output directory"),
  "export JSON should render output-directory reporting"
)

vim.cmd("ZorgExportSubtree @note --stdout")
test.assert_last_argv(runner, {
  bin,
  "export",
  "markdown",
  "--root",
  root,
  "--db",
  db,
  "--subtree",
  "@note",
  "--stdout",
}, "ZorgExportSubtree should pass the subtree selector")

vim.cmd("ZorgExportQuery #z/todo -did:*")
test.assert_last_argv(runner, {
  bin,
  "export",
  "markdown",
  "--root",
  root,
  "--db",
  db,
  "--query",
  "#z/todo -did:*",
}, "ZorgExportQuery should preserve inline SWOG as one selector argument")

local located = root .. "/located.z"
vim.fn.writefile({ "%%% @located #z/ref", "Located", "%%%" }, located)
runner.result = {
  code = 0,
  stdout = vim.json.encode({
    schema_version = 1,
    command = "open",
    canonical_id = "located",
    absolute_path = located,
    root_relative_path = "located.z",
    source_span = test.fixtures.source_span({
      start_line = 2,
      start_column = 1,
      end_line = 2,
      end_column = 8,
    }),
    title = "Located",
    kind = "file",
  }),
  stderr = "",
}
vim.cmd("ZorgOpen @located")
test.assert_last_argv(runner, {
  bin,
  "open",
  "--root",
  root,
  "--db",
  db,
  "@located",
  "--format",
  "json",
}, "ZorgOpen should request the Rust JSON location contract")
test.wait_for(function()
  return vim.api.nvim_buf_get_name(0) == located
end, "ZorgOpen should open the located source file")
test.assert_eq(vim.api.nvim_win_get_cursor(0), { 2, 0 }, "ZorgOpen should jump to the JSON source span")

local original_refactor_select = vim.ui.select
vim.ui.select = function(items, _, callback)
  callback(items[1])
end
local promote_preview = test.fixtures.refactor_preview("promote", {
  {
    absolute_path = located,
    root_relative_path = "located.z",
    original_guard = {
      content_hash = "fnv1a64:0",
      mtime_unix_ms = vim.NIL,
      byte_len = 0,
    },
    edits = {},
  },
})
runner.result = function(argv)
  if argv[2] == "db" then
    return { code = 0, stdout = "", stderr = "" }
  end

  if argv[2] == "promote" and argv_has(argv, "--write") then
    local written = vim.deepcopy(promote_preview)
    written.plan.mode = "write"
    return { code = 0, stdout = vim.json.encode(written), stderr = "" }
  end

  return { code = 0, stdout = vim.json.encode(promote_preview), stderr = "" }
end
local before_promote = #runner.runs
vim.cmd("ZorgPromote @located --to located-promoted.z")
test.assert_eq(#runner.runs, before_promote + 3, "ZorgPromote should preview, write after confirmation, and reindex")
test.assert_eq(runner.runs[before_promote + 1], {
  bin,
  "promote",
  "--root",
  root,
  "--db",
  db,
  "@located",
  "--to",
  "located-promoted.z",
  "--format",
  "json",
}, "ZorgPromote should preview through the Rust JSON contract")
test.assert_eq(runner.runs[before_promote + 2], {
  bin,
  "promote",
  "--root",
  root,
  "--db",
  db,
  "@located",
  "--to",
  "located-promoted.z",
  "--format",
  "json",
  "--write",
}, "ZorgPromote should rerun the same command with --write after confirmation")
test.assert_eq(runner.runs[before_promote + 3], {
  bin,
  "db",
  "reindex",
  "--root",
  root,
  "--db",
  db,
}, "ZorgPromote should refresh index state after a successful write")
test.wait_for_current_buffer_name("Zorg Promote Preview", "promote preview should open a review buffer")

vim.ui.select = function(items, _, callback)
  callback(items[2])
end
local before_move = #runner.runs
vim.cmd("ZorgMove @located --to moved.z")
test.assert_eq(#runner.runs, before_move + 1, "ZorgMove cancellation should stop after preview")
assert(not argv_has(runner.runs[#runner.runs], "--write"), "ZorgMove cancellation must not write")
assert(notifications[#notifications].message:match("cancelled"), "ZorgMove cancellation should notify")

vim.fn.writefile({ "%%% @note #z/ref", "Alpha beta", "%%%" }, note)
vim.cmd("edit " .. vim.fn.fnameescape(note))
vim.bo.filetype = "zorg"
vim.ui.select = function(items, _, callback)
  callback(items[1])
end
local extract_preview = test.fixtures.refactor_preview("extract", {
  {
    absolute_path = note,
    root_relative_path = "note.z",
    original_guard = {
      content_hash = "fnv1a64:1",
      mtime_unix_ms = vim.NIL,
      byte_len = 0,
    },
    edits = {},
  },
})
runner.result = function(argv)
  if argv[2] == "db" then
    return { code = 0, stdout = "", stderr = "" }
  end

  if argv[2] == "extract" and argv_has(argv, "--write") then
    local written = vim.deepcopy(extract_preview)
    written.plan.mode = "write"
    return { code = 0, stdout = vim.json.encode(written), stderr = "" }
  end

  return { code = 0, stdout = vim.json.encode(extract_preview), stderr = "" }
end
local before_extract = #runner.runs
vim.cmd("2,2ZorgExtract @note/extracted --replace-with-link")
test.assert_eq(#runner.runs, before_extract + 3, "ZorgExtract should preview, write after confirmation, and reindex")
test.assert_eq(runner.runs[before_extract + 1], {
  bin,
  "extract",
  "--root",
  root,
  "--db",
  db,
  "--file",
  note,
  "--range",
  "2:1-2:11",
  "--id",
  "@note/extracted",
  "--replace-with-link",
  "--format",
  "json",
}, "ZorgExtract should translate the selected range to the Rust line/column range contract")
vim.ui.select = original_refactor_select

runner.result = {
  code = 2,
  stdout = "",
  stderr = "unknown zorg command: promote",
}
local before_refactor_unavailable = #notifications
vim.cmd("ZorgPromote @missing")
test.wait_for(function()
  return #notifications > before_refactor_unavailable
end, "unavailable refactor command should notify")
assert(
  notifications[#notifications].message:match("unavailable"),
  "unavailable refactor notification should be explicit"
)

runner.result = {
  code = 2,
  stdout = "",
  stderr = "unknown zorg command: import",
}
local before_unavailable = #notifications
vim.cmd("ZorgImportPlan legacy/project.zo")
test.wait_for(function()
  return #notifications > before_unavailable
end, "unavailable import command should notify")
assert(
  notifications[#notifications].message:match("unavailable"),
  "unavailable import notification should be explicit"
)

restore_notify()
