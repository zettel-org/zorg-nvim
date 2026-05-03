local test = dofile("tests/testlib.lua")

local config = require("zorg.config")

local reports = {}

local function record(level, message)
  table.insert(reports, { level = level, message = message })
end

vim.health = {
  start = function(message)
    record("start", message)
  end,
  ok = function(message)
    record("ok", message)
  end,
  warn = function(message)
    record("warn", message)
  end,
  error = function(message)
    record("error", message)
  end,
}

package.loaded["zorg.health"] = nil
local health = require("zorg.health")

local function messages(level)
  local found = {}

  for _, report in ipairs(reports) do
    if not level or report.level == level then
      table.insert(found, report.message)
    end
  end

  return table.concat(found, "\n")
end

local function reset_reports()
  reports = {}
end

local root = test.tempdir("zorg-root")
local bin_dir = test.tempdir("zorg-bin")
local zorg = bin_dir .. "/zorg"
local zorg_ls = bin_dir .. "/zorg-ls"

test.write_executable(zorg, {
  "#!/bin/sh",
  "if [ \"$1\" = \"--version\" ]; then echo 'zorg 1.1.0'; exit 0; fi",
  "if [ \"$1\" = \"watch\" ]; then echo 'Usage: zorg watch --format json'; exit 0; fi",
  "if [ \"$1\" = \"query\" ]; then echo 'Usage: zorg query --json'; exit 0; fi",
  "if [ \"$1\" = \"import\" ]; then echo 'Usage: zorg import legacy'; exit 0; fi",
  "if [ \"$1\" = \"export\" ]; then echo 'Usage: zorg export markdown'; exit 0; fi",
  "exit 0",
})
test.write_executable(zorg_ls, "zorg-ls 1.1.0")

config.setup({
  root = root,
  database_path = root .. "/.zorg/zorg.sqlite3",
  cli = {
    command = zorg,
  },
  lsp = {
    command = { zorg_ls },
  },
  watcher = {
    enabled = true,
    autostart = false,
    debounce_ms = 125,
    show_logs = true,
    job_policy = "per_root",
  },
})

health.check()

local all = messages()
assert(all:match("zorg 1%.1%.0"), "health should report zorg version")
assert(all:match("zorg%-ls 1%.1%.0"), "health should report zorg-ls version")
assert(all:match("Zorg root exists: " .. vim.pesc(root)), "health should report configured root")
assert(
  all:match("Configured Zorg database path: " .. vim.pesc(root .. "/.zorg/zorg.sqlite3")),
  "health should report configured database"
)
assert(all:match("Watcher integration is enabled"), "health should report watcher enabled state")
assert(all:match("Watcher autostart is disabled"), "health should report watcher autostart state")
assert(all:match("Watcher debounce override: 125"), "health should report watcher debounce")
assert(all:match("Watcher log display: enabled"), "health should report watcher log preference")
assert(all:match("Watcher job policy: per_root"), "health should report watcher job policy")
assert(all:match("zorg watch JSON contract appears available"), "health should detect watch JSON help")
assert(all:match("zorg query %-%-json contract appears available"), "health should detect query JSON help")

local unsupported_zorg = bin_dir .. "/zorg-no-json"
test.write_executable(unsupported_zorg, {
  "#!/bin/sh",
  "if [ \"$1\" = \"--version\" ]; then echo 'zorg 1.0.0'; exit 0; fi",
  "if [ \"$1\" = \"watch\" ]; then echo 'Usage: zorg watch'; exit 0; fi",
  "if [ \"$1\" = \"query\" ]; then echo 'Usage: zorg query'; exit 0; fi",
  "exit 0",
})

config.setup({
  root = root,
  cli = {
    command = unsupported_zorg,
  },
  lsp = {
    command = { zorg_ls },
  },
})

reset_reports()
health.check()
local warnings = messages("warn")
assert(
  warnings:match("zorg watch JSON contract was not detected"),
  "health should warn when watch JSON support is missing"
)
assert(
  warnings:match("zorg query %-%-json contract was not detected"),
  "health should warn when query JSON support is missing"
)

config.setup({
  root = root,
  cli = {
    command = bin_dir .. "/missing-zorg",
  },
  lsp = {
    command = { bin_dir .. "/missing-zorg-ls" },
  },
})

reset_reports()
health.check()
warnings = messages("warn")
assert(warnings:match("missing%-zorg was not found"), "health should warn when zorg is missing")
assert(warnings:match("missing%-zorg%-ls was not found"), "health should warn when zorg-ls is missing")
