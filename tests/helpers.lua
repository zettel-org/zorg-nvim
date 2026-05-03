local test = dofile("tests/testlib.lua")

local config = require("zorg.config")
local commands = require("zorg.commands")
local helpers = require("zorg.helpers")
local mappings = require("zorg.mappings")

local root = test.tempdir("zorg-root")
local bin = test.tempdir("zorg-bin") .. "/zorg"
test.write_executable(bin)

config.setup({
  root = root,
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

local setup_config = require("zorg").setup({
  cli = {
    command = bin,
  },
  lsp = {
    enabled = false,
  },
})
assert(setup_config.mappings.enabled == false, "mappings should be disabled by default")
test.assert_eq(mappings._registered_for_test(), {}, "default setup should not install keymaps")

require("zorg").setup({
  root = root,
  cli = {
    command = bin,
  },
  mappings = {
    enabled = true,
    prefix = "<leader>x",
  },
  lsp = {
    enabled = false,
  },
})
test.assert_eq(
  mappings._registered_for_test(),
  { "<leader>xi", "<leader>xq", "<leader>xf", "<leader>xc", "<leader>xs" },
  "enabled mappings should use the configured prefix"
)
assert(vim.fn.maparg("<leader>xq", "n") ~= "", "enabled mappings should be installed")

require("zorg").setup({
  root = root,
  cli = {
    command = bin,
  },
  mappings = {
    enabled = false,
    prefix = "<leader>x",
  },
  lsp = {
    enabled = false,
  },
})
test.assert_eq(mappings._registered_for_test(), {}, "disabled setup should clear managed mappings")
assert(vim.fn.maparg("<leader>xq", "n") == "", "disabled setup should remove managed mappings")

helpers.reindex_root()
test.assert_last_argv(runner, {
  bin,
  "db",
  "reindex",
  "--root",
  root,
}, "reindex helper should delegate to ZorgIndex command logic")

helpers.query("#z/todo -did:*")
test.assert_last_argv(runner, {
  bin,
  "query",
  "--root",
  root,
  "--json",
  "#z/todo -did:*",
}, "query helper should prefer JSON and preserve inline SWOG as one argument")

local note = root .. "/note.z"
vim.fn.writefile({ "%%% @note #z/ref", "Note", "%%%" }, note)
vim.cmd("edit " .. vim.fn.fnameescape(note))
vim.bo.filetype = "zorg"
helpers.fix_current_buffer()
test.assert_last_argv(
  runner,
  { bin, "fix", "--root", root, note },
  "fix helper should use current-buffer fix with store options"
)

local original_ui_input = vim.ui.input
local prompts = {}
local answers = {
  "project/template",
  "Task title",
  "Task body",
}
vim.ui.input = function(opts, callback)
  table.insert(prompts, opts.prompt)
  callback(table.remove(answers, 1))
end

helpers.capture_prompt()
test.assert_eq(
  prompts,
  { "Zorg template: ", "Zorg title: ", "Zorg body: " },
  "capture helper should prompt for template, title, and body"
)
test.assert_last_argv(runner, {
  bin,
  "capture",
  "--root",
  root,
  "--json",
  "--template",
  "project/template",
  "--title",
  "Task title",
  "--body",
  "Task body",
}, "capture helper should delegate to ZorgCapture command logic")

answers = { "#z/query" }
prompts = {}
helpers.query_prompt()
test.assert_eq(prompts, { "Zorg query: " }, "query helper should use vim.ui.input")
test.assert_last_argv(runner, {
  bin,
  "query",
  "--root",
  root,
  "--json",
  "#z/query",
}, "query prompt should delegate to ZorgQuery command logic")

vim.ui.input = original_ui_input

test.assert_eq(
  commands.complete_query("--"),
  { "--db", "--format", "--help", "--id", "--json", "--root" },
  "query completion should return cheap known flags"
)
test.assert_eq(
  commands.complete_capture("--t"),
  { "--template", "--title" },
  "capture completion should filter known flags"
)

local file_matches = commands.complete_fix(note:sub(1, #note - 2))
assert(#file_matches > 0, "fix completion should delegate non-flag args to file completion")

test.wait_for(function()
  return true
end, "helpers test should finish")
