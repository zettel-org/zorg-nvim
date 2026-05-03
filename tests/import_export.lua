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
local import_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(import_text:match("Writes"), "import plan should include write targets")
assert(import_text:match("Lossy Transforms"), "import plan should separate lossy output")
assert(import_text:match("Unsupported Forms"), "import plan should separate unsupported forms")
assert(import_text:match("Errors"), "import plan should include errors")

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

local note = root .. "/note.z"
vim.fn.writefile({ "%%% @note #z/ref", "Note", "%%%" }, note)
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
