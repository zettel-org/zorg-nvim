local config = require("zorg.config")

local M = {}

local watchers = {}
local jobstart_for_test = nil
local jobstop_for_test = nil
local augroup = vim.api.nvim_create_augroup("zorg_watcher", { clear = true })
local scratch_counter = 0

local valid_states = {
  starting = true,
  ready = true,
  indexing = true,
  indexed = true,
  degraded = true,
  error = true,
  stopping = true,
  stopped = true,
}

local function schedule(fn)
  if vim.in_fast_event and vim.in_fast_event() then
    vim.schedule(fn)
  else
    fn()
  end
end

local function notify(message, level)
  schedule(function()
    vim.notify(message, level or vim.log.levels.INFO)
  end)
end

local function configured_db_path(opts)
  return opts.database_path or opts.db_path
end

local function normalize_path(path)
  local expanded = vim.fn.expand(path)
  local resolved = vim.fn.resolve(expanded)
  local absolute = vim.fn.fnamemodify(resolved ~= "" and resolved or expanded, ":p")

  if absolute ~= "/" then
    absolute = absolute:gsub("/+$", "")
  end

  return absolute
end

local function watcher_key(root)
  return normalize_path(root)
end

local function root_args(opts)
  local root = normalize_path(opts.root)
  local args = { "--root", root }
  local db_path = configured_db_path(opts)

  if db_path and db_path ~= "" then
    vim.list_extend(args, { "--db", vim.fn.expand(db_path) })
  end

  return args
end

local function watch_argv(command_opts)
  local opts = config.get()
  local argv = { opts.cli.command, "watch" }
  vim.list_extend(argv, root_args(opts))
  vim.list_extend(argv, { "--format", "json" })

  local watcher = opts.watcher or {}
  if watcher.debounce_ms ~= nil then
    vim.list_extend(argv, { "--debounce", tostring(watcher.debounce_ms) })
  end

  vim.list_extend(argv, command_opts and command_opts.fargs or {})
  return argv
end

local function open_scratch_lines(title, lines)
  local buffer = vim.api.nvim_create_buf(false, true)
  scratch_counter = scratch_counter + 1
  vim.api.nvim_buf_set_name(buffer, title .. " " .. scratch_counter)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].filetype = "zorg-output"

  pcall(vim.cmd, "botright split")
  vim.api.nvim_win_set_buf(0, buffer)
  return buffer
end

local function summary_text(summary)
  if type(summary) ~= "table" then
    return ""
  end

  local parts = {}
  for _, key in ipairs({
    "discovered_files",
    "indexed_files",
    "unchanged_files",
    "new_files",
    "changed_files",
    "deleted_files",
    "zettel_count",
    "diagnostic_count",
    "effective_tag_count",
  }) do
    if summary[key] ~= nil then
      table.insert(parts, key .. "=" .. tostring(summary[key]))
    end
  end

  return table.concat(parts, " ")
end

local function state_message(event)
  local state = event.state or "unknown"
  local message = "Zorg watcher " .. state

  if type(event.root) == "string" and event.root ~= "" then
    message = message .. ": " .. event.root
  end

  if type(event.message) == "string" and event.message ~= "" then
    message = message .. " (" .. event.message .. ")"
  end

  return message
end

local function event_level(event)
  if event.state == "error" then
    return vim.log.levels.ERROR
  end

  if event.state == "degraded" then
    return vim.log.levels.WARN
  end

  return vim.log.levels.INFO
end

local function record_event(watcher, event)
  if event.schema_version ~= 1 or not valid_states[event.state] then
    watcher.state = "error"
    watcher.last_error = "unsupported watcher event: " .. vim.inspect(event)
    notify("Zorg watcher returned unsupported JSON: " .. watcher.last_error, vim.log.levels.ERROR)
    return
  end

  watcher.state = event.state
  watcher.last_event = event
  watcher.last_error = event.state == "error" and event.message or nil
  table.insert(watcher.events, event)
  notify(state_message(event), event_level(event))
end

local function handle_line(watcher, line)
  line = vim.trim(line or "")
  if line == "" then
    return
  end

  local ok, event = pcall(vim.json.decode, line)
  if not ok or type(event) ~= "table" then
    watcher.state = "error"
    watcher.last_error = "invalid watcher JSON: " .. line
    notify("Zorg watcher returned invalid JSON", vim.log.levels.ERROR)
    table.insert(watcher.logs, line)
    return
  end

  record_event(watcher, event)
end

local function append_job_data(watcher, data)
  if not data then
    return
  end

  for index, chunk in ipairs(data) do
    if index == 1 then
      chunk = watcher.pending_stdout .. chunk
    end

    if index < #data then
      handle_line(watcher, chunk)
    else
      watcher.pending_stdout = chunk
    end
  end
end

local function append_stderr(watcher, data)
  if not data then
    return
  end

  for _, line in ipairs(data) do
    if line ~= "" then
      table.insert(watcher.logs, line)
    end
  end
end

local function render_watcher(watcher)
  local lines = {
    "Root: " .. watcher.root,
    "Database: " .. (watcher.database or "default under root"),
    "State: " .. watcher.state,
    "Job: " .. (watcher.job_id and tostring(watcher.job_id) or "none"),
  }

  if watcher.last_error then
    table.insert(lines, "Error: " .. watcher.last_error)
  end

  local summary = watcher.last_event and summary_text(watcher.last_event.summary) or ""
  if summary ~= "" then
    table.insert(lines, "Summary: " .. summary)
  end

  if #watcher.logs > 0 then
    table.insert(lines, "")
    table.insert(lines, "Logs")
    for _, line in ipairs(watcher.logs) do
      table.insert(lines, "  " .. line)
    end
  end

  if #watcher.events > 0 then
    table.insert(lines, "")
    table.insert(lines, "Events")
    for _, event in ipairs(watcher.events) do
      local line = "  " .. event.state
      local event_summary = summary_text(event.summary)
      if event_summary ~= "" then
        line = line .. " " .. event_summary
      end
      if event.message then
        line = line .. " " .. event.message
      end
      table.insert(lines, line)
    end
  end

  return lines
end

local function all_status_lines()
  local lines = {}
  local roots = vim.tbl_keys(watchers)
  table.sort(roots)

  if #roots == 0 then
    return { "No Zorg watcher has been started." }
  end

  for index, root in ipairs(roots) do
    if index > 1 then
      table.insert(lines, "")
    end
    vim.list_extend(lines, render_watcher(watchers[root]))
  end

  return lines
end

local function start_job(watcher, argv)
  local jobstart = jobstart_for_test or vim.fn.jobstart

  local job_id = jobstart(argv, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      append_job_data(watcher, data)
    end,
    on_stderr = function(_, data)
      append_stderr(watcher, data)
    end,
    on_exit = function(_, code)
      handle_line(watcher, watcher.pending_stdout)
      watcher.pending_stdout = ""
      watcher.job_id = nil
      if watcher.state ~= "error" and watcher.state ~= "stopped" then
        watcher.state = code == 0 and "stopped" or "error"
      end
      if code ~= 0 then
        watcher.last_error = "watcher exited with code " .. tostring(code)
        notify("Zorg watcher failed (exit " .. tostring(code) .. ")", vim.log.levels.ERROR)
      else
        notify("Zorg watcher stopped: " .. watcher.root)
      end
    end,
  })

  return job_id
end

function M.start(command_opts)
  local opts = config.get()
  local watcher_opts = opts.watcher or {}

  if watcher_opts.enabled == false then
    notify("Zorg watcher integration is disabled", vim.log.levels.WARN)
    return
  end

  if vim.fn.executable(opts.cli.command) ~= 1 then
    notify(opts.cli.command .. " not found; :ZorgWatchStart cannot run", vim.log.levels.ERROR)
    return
  end

  local root = normalize_path(opts.root)
  local key = watcher_key(root)
  local existing = watchers[key]
  if existing and existing.job_id then
    notify("Zorg watcher already running for " .. root, vim.log.levels.WARN)
    return existing
  end

  local argv = watch_argv(command_opts)
  local watcher = {
    argv = argv,
    database = configured_db_path(opts) and vim.fn.expand(configured_db_path(opts)) or nil,
    events = {},
    job_id = nil,
    last_error = nil,
    last_event = nil,
    logs = {},
    pending_stdout = "",
    root = root,
    state = "starting",
  }
  watchers[key] = watcher

  local job_id = start_job(watcher, argv)
  if job_id <= 0 then
    watcher.state = "error"
    watcher.last_error = "failed to start " .. table.concat(argv, " ")
    notify("Zorg watcher failed to start", vim.log.levels.ERROR)
    return watcher
  end

  watcher.job_id = job_id
  notify("Zorg watcher starting: " .. root)
  return watcher
end

function M.stop(_command_opts)
  local opts = config.get()
  local root = normalize_path(opts.root)
  local watcher = watchers[watcher_key(root)]

  if not watcher or not watcher.job_id then
    notify("No Zorg watcher is running for " .. root, vim.log.levels.WARN)
    return
  end

  watcher.state = "stopping"
  notify("Stopping Zorg watcher: " .. root)

  local jobstop = jobstop_for_test or vim.fn.jobstop
  local ok = jobstop(watcher.job_id)
  if ok == 0 then
    notify("Failed to stop Zorg watcher: " .. root, vim.log.levels.ERROR)
  end

  return watcher
end

function M.status(_command_opts)
  open_scratch_lines("Zorg Watch Status", all_status_lines())
end

function M.stop_all()
  for _, watcher in pairs(watchers) do
    if watcher.job_id then
      watcher.state = "stopping"
      local jobstop = jobstop_for_test or vim.fn.jobstop
      pcall(jobstop, watcher.job_id)
    end
  end
end

function M.setup(opts)
  opts = opts or config.get().watcher or {}
  vim.api.nvim_clear_autocmds({ group = augroup })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = M.stop_all,
  })

  if opts.autostart then
    vim.schedule(function()
      M.start({ fargs = {} })
    end)
  end
end

function M._set_jobstart_for_test(jobstart, jobstop)
  jobstart_for_test = jobstart
  jobstop_for_test = jobstop
end

function M._state_for_test(root)
  return watchers[watcher_key(root or config.get().root)]
end

function M._reset_for_test()
  watchers = {}
  jobstart_for_test = nil
  jobstop_for_test = nil
  scratch_counter = 0
end

return M
