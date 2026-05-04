local test = dofile("tests/testlib.lua")

local config = require("zorg.config")
local lsp = require("zorg.lsp")

local original_lsp_start = vim.lsp.start

local captured_start = nil
local start_count = 0
vim.lsp.start = function(client_config, start_opts)
  captured_start = {
    client_config = client_config,
    start_opts = start_opts,
  }
  start_count = start_count + 1
  return 42
end

local notifications, restore_notify = test.capture_notifications()

local root = test.tempdir("zorg-root")
local nested = root .. "/notes/deep"
vim.fn.mkdir(nested, "p")
vim.fn.writefile({}, root .. "/.zorgroot")
local note_path = nested .. "/note.z"
vim.fn.writefile({ "%%% @note #z/ref", "Note", "%%%" }, note_path)

local fallback_root = test.tempdir("zorg-fallback")
local database_path = test.tempdir("zorg-db") .. "/zorg.sqlite3"
local fake_ls = test.tempdir("zorg-bin") .. "/zorg-ls"
test.write_executable(fake_ls, "zorg-ls test")

config.setup({
  root = fallback_root,
  database_path = database_path,
  trace = "messages",
  lsp = {
    command = { fake_ls, "--stdio" },
    root_markers = { ".zorgroot", "init.z" },
    settings = {
      zorg = {
        test = true,
      },
    },
  },
})

vim.cmd("edit " .. vim.fn.fnameescape(note_path))
vim.bo.filetype = "zorg"
local bufnr = vim.api.nvim_get_current_buf()

local started = lsp.start(bufnr)
test.assert_eq(started, 42, "start should return the vim.lsp.start result")
test.assert_eq(start_count, 1, "start should call vim.lsp.start once")
test.assert_eq(captured_start.client_config.name, "zorg-ls", "client name should be zorg-ls")
test.assert_eq(
  captured_start.client_config.cmd[1],
  fake_ls,
  "client command should use configured binary"
)
test.assert_eq(
  captured_start.client_config.cmd[2],
  "--stdio",
  "client command should preserve extra args"
)
test.assert_eq(captured_start.client_config.root_dir, root, "root should resolve from .zorgroot")
test.assert_eq(
  captured_start.client_config.initialization_options.rootPath,
  root,
  "rootPath should match resolved root"
)
test.assert_eq(
  captured_start.client_config.initialization_options.databasePath,
  database_path,
  "databasePath should be passed"
)
test.assert_eq(
  captured_start.client_config.initialization_options.trace,
  "messages",
  "trace should be passed"
)
test.assert_eq(
  captured_start.client_config.initialization_options.refreshOnSave,
  "diagnostics",
  "refreshOnSave should default to diagnostics-only"
)
assert(
  captured_start.client_config.initialization_options.dbPath == nil,
  "dbPath should be omitted when not configured"
)
assert(captured_start.client_config.settings.zorg.test, "settings should still be passed")

local reuse = captured_start.start_opts.reuse_client
assert(
  reuse({ name = "zorg-ls", config = { root_dir = root } }, { root_dir = root }),
  "same-root zorg-ls clients should be reused"
)
assert(
  not reuse({ name = "zorg-ls", config = { root_dir = fallback_root } }, { root_dir = root }),
  "different roots should not be reused"
)
assert(
  not reuse({ name = "other-ls", config = { root_dir = root } }, { root_dir = root }),
  "other clients should not be reused"
)

local init_root = test.tempdir("zorg-init-root")
vim.fn.mkdir(init_root .. "/child", "p")
vim.fn.writefile({}, init_root .. "/init.z")
local init_note = init_root .. "/child/note.z"
vim.fn.writefile({ "%%% @init/note #z/ref", "Note", "%%%" }, init_note)
vim.cmd("edit " .. vim.fn.fnameescape(init_note))
vim.bo.filetype = "zorg"
test.assert_eq(
  lsp.root_dir(vim.api.nvim_get_current_buf()),
  init_root,
  "init.z should act as a corpus marker"
)

vim.cmd("enew")
vim.bo.filetype = "text"
captured_start = nil
local non_zorg = lsp.start(vim.api.nvim_get_current_buf())
assert(non_zorg == nil, "non-zorg buffers should not start the LSP")
assert(captured_start == nil, "non-zorg buffers should not call vim.lsp.start")

config.setup({
  root = fallback_root,
  lsp = {
    command = { "/definitely/missing/zorg-ls" },
  },
})

vim.cmd("enew")
vim.bo.filetype = "zorg"
local ok, missing_result = pcall(lsp.start, vim.api.nvim_get_current_buf())
assert(ok, "missing executable should not throw")
assert(missing_result == nil, "missing executable should skip startup")
assert(#notifications == 1, "missing executable should notify once")
lsp.start(vim.api.nvim_get_current_buf())
assert(#notifications == 1, "missing executable notification should not repeat")

lsp.setup()
local autocmds = vim.api.nvim_get_autocmds({ event = "FileType", pattern = "zorg" })
local found = false
for _, autocmd in ipairs(autocmds) do
  if autocmd.group_name == "zorg_lsp" then
    found = true
    break
  end
end
assert(found, "setup should install a FileType zorg autocmd")

config.setup({
  root = fallback_root,
  lsp = {
    autostart = false,
    command = { fake_ls },
  },
})
lsp.setup()
local disabled_autocmds = vim.api.nvim_get_autocmds({ event = "FileType", pattern = "zorg" })
local disabled_found = false
for _, autocmd in ipairs(disabled_autocmds) do
  if autocmd.group_name == "zorg_lsp" then
    disabled_found = true
    break
  end
end
assert(not disabled_found, "autostart=false should avoid the FileType zorg autocmd")

config.setup({
  root = fallback_root,
  lsp = {
    command = { fake_ls },
    refresh_on_save = "reindex",
  },
})
test.assert_eq(
  lsp.initialization_options(fallback_root).refreshOnSave,
  "reindex",
  "refreshOnSave should pass explicit reindex policy"
)

config.setup({
  root = fallback_root,
  lsp = {
    command = { fake_ls },
    refresh_on_save = false,
  },
})
test.assert_eq(
  lsp.initialization_options(fallback_root).refreshOnSave,
  false,
  "refreshOnSave should pass explicit false policy"
)

vim.lsp.start = original_lsp_start
restore_notify()
