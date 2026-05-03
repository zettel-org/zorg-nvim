vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("filetype plugin on")

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

local function write_executable(path, output)
  vim.fn.writefile({ "#!/bin/sh", "echo " .. vim.fn.shellescape(output) }, path)
  vim.fn.setfperm(path, "rwxr-xr-x")
end

local function wait_for(predicate, message)
  local ok = vim.wait(1000, predicate, 10)
  assert(ok, message)
end

local root = vim.fn.getcwd() .. "/.tests/root"
local bin_dir = vim.fn.getcwd() .. "/.tests/bin"
vim.fn.mkdir(root, "p")
vim.fn.mkdir(bin_dir, "p")
vim.fn.writefile({}, root .. "/.zorgroot")

local zorg = bin_dir .. "/zorg"
local zorg_ls = bin_dir .. "/zorg-ls"
write_executable(zorg, "zorg 0.1.0")
write_executable(zorg_ls, "zorg-ls 0.1.0")

local original_lsp_start = vim.lsp.start
local captured_lsp_start = nil
vim.lsp.start = function(client_config, start_opts)
  captured_lsp_start = {
    client_config = client_config,
    start_opts = start_opts,
  }
  return 99
end

local config = require("zorg").setup({
  root = root,
  database_path = root .. "/.zorg/zorg.sqlite3",
  cli = {
    command = zorg,
  },
  lsp = {
    command = { zorg_ls },
    trace = "messages",
  },
})

assert(config.root ~= nil and config.root ~= "", "setup should return a configured root")

vim.cmd("edit " .. vim.fn.fnameescape(root .. "/sample.z"))
assert(vim.bo.filetype == "zorg", "*.z buffers should use the zorg filetype")
assert(vim.bo.commentstring == "# %s", "zorg ftplugin should set commentstring")
assert(vim.bo.comments == ":#", "zorg ftplugin should set comments")
assert(captured_lsp_start ~= nil, "zorg buffers should trigger LSP startup")
assert_eq(captured_lsp_start.client_config.cmd, { zorg_ls }, "LSP should use configured command")
assert_eq(captured_lsp_start.client_config.root_dir, root, "LSP should use detected root")
assert_eq(
  captured_lsp_start.client_config.initialization_options.rootPath,
  root,
  "LSP rootPath should match detected root"
)
assert_eq(
  captured_lsp_start.client_config.initialization_options.databasePath,
  root .. "/.zorg/zorg.sqlite3",
  "LSP databasePath should come from setup"
)
assert_eq(
  captured_lsp_start.client_config.initialization_options.trace,
  "messages",
  "LSP trace should come from setup"
)

local treesitter = require("zorg.treesitter")
assert(treesitter.has_runtime(), "Tree-sitter runtime should be available in Neovim")

local registered, register_err = treesitter.register_filetype("zorg", "zorg")
assert(registered, "zorg parser registration should be safe: " .. tostring(register_err))

local query_ok, query_files = treesitter.query_available("zorg", "highlights")
assert(query_ok, "zorg highlight query should be on runtimepath")
assert(#query_files > 0, "zorg highlight query lookup should return a runtime file")

if vim.treesitter.query and vim.treesitter.query.get_files then
  local files = vim.treesitter.query.get_files("zorg", "highlights")
  assert(#files > 0, "Neovim query lookup should find zorg highlights")
end

for _, command in ipairs({ "ZorgIndex", "ZorgQuery", "ZorgFix", "ZorgCapture" }) do
  assert(vim.fn.exists(":" .. command) == 2, command .. " should exist")
end

local commands = require("zorg.commands")
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

vim.cmd("ZorgIndex")
assert_eq(
  runs[#runs],
  { zorg, "db", "reindex", "--root", root, "--db", root .. "/.zorg/zorg.sqlite3" },
  "ZorgIndex argv should match the Rust CLI"
)

next_result = {
  code = 0,
  stdout = "[ ] @task  sample.z  Task",
  stderr = "",
}
vim.cmd("ZorgQuery #z/todo -did:*")
assert_eq(
  runs[#runs],
  { zorg, "query", "--root", root, "--db", root .. "/.zorg/zorg.sqlite3", "#z/todo -did:*" },
  "ZorgQuery should preserve inline SWOG as one argument"
)
wait_for(function()
  return vim.api.nvim_buf_get_name(0):match("Zorg Query Results") ~= nil
end, "ZorgQuery should open query output")

vim.cmd("edit " .. vim.fn.fnameescape(root .. "/sample.z"))
vim.bo.filetype = "zorg"
vim.cmd("ZorgFix")
assert_eq(
  runs[#runs],
  { zorg, "fix", "--root", root, "--db", root .. "/.zorg/zorg.sqlite3", root .. "/sample.z" },
  "ZorgFix should pass root and current buffer path"
)

next_result = {
  code = 0,
  stdout = vim.json.encode({
    destination = root .. "/captured.z",
    zettel_id = "@captured",
  }),
  stderr = "",
}
vim.fn.writefile({ "%%% @captured #z/ref", "Captured", "%%%" }, root .. "/captured.z")
vim.cmd("ZorgCapture --template @templates/todo --title Task")
assert_eq(runs[#runs], {
  zorg,
  "capture",
  "--root",
  root,
  "--db",
  root .. "/.zorg/zorg.sqlite3",
  "--json",
  "--template",
  "@templates/todo",
  "--title",
  "Task",
}, "ZorgCapture should request JSON and pass store options")
wait_for(function()
  return vim.api.nvim_buf_get_name(0) == root .. "/captured.z"
end, "ZorgCapture should open the captured file from JSON output")

assert(vim.fn.maparg("<leader>zq", "n") == "", "setup should not install mappings by default")

vim.lsp.start = original_lsp_start
