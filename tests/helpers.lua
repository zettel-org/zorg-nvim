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
local helpers = require("zorg.helpers")
local mappings = require("zorg.mappings")

local root = tempdir("zorg-root")
local bin = tempdir("zorg-bin") .. "/zorg"
write_executable(bin)

config.setup({
  root = root,
  cli = {
    command = bin,
  },
  lsp = {
    enabled = false,
  },
})

local runs = {}
commands._set_runner_for_test(function(argv, on_result)
  table.insert(runs, vim.deepcopy(argv))
  on_result({
    code = 0,
    stdout = "",
    stderr = "",
  })
end)
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
assert_eq(mappings._registered_for_test(), {}, "default setup should not install keymaps")

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
assert_eq(
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
assert_eq(mappings._registered_for_test(), {}, "disabled setup should clear managed mappings")
assert(vim.fn.maparg("<leader>xq", "n") == "", "disabled setup should remove managed mappings")

helpers.reindex_root()
assert_eq(runs[#runs], {
  bin,
  "db",
  "reindex",
  "--root",
  root,
}, "reindex helper should delegate to ZorgIndex command logic")

helpers.query("#z/todo -did:*")
assert_eq(runs[#runs], {
  bin,
  "query",
  "--root",
  root,
  "#z/todo -did:*",
}, "query helper should preserve inline SWOG as one argument")

local note = root .. "/note.z"
vim.fn.writefile({ "%%% @note #z/ref", "Note", "%%%" }, note)
vim.cmd("edit " .. vim.fn.fnameescape(note))
vim.bo.filetype = "zorg"
helpers.fix_current_buffer()
assert_eq(runs[#runs], { bin, "fix", note }, "fix helper should use current-buffer fix")

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
assert_eq(
  prompts,
  { "Zorg template: ", "Zorg title: ", "Zorg body: " },
  "capture helper should prompt for template, title, and body"
)
assert_eq(runs[#runs], {
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
assert_eq(prompts, { "Zorg query: " }, "query helper should use vim.ui.input")
assert_eq(runs[#runs], {
  bin,
  "query",
  "--root",
  root,
  "#z/query",
}, "query prompt should delegate to ZorgQuery command logic")

vim.ui.input = original_ui_input

assert_eq(
  commands.complete_query("--"),
  { "--db", "--help", "--id", "--root" },
  "query completion should return cheap known flags"
)
assert_eq(
  commands.complete_capture("--t"),
  { "--template", "--title" },
  "capture completion should filter known flags"
)

local file_matches = commands.complete_fix(note:sub(1, #note - 2))
assert(#file_matches > 0, "fix completion should delegate non-flag args to file completion")

wait_for(function()
  return true
end, "helpers test should finish")
