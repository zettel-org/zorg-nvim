local config = require("zorg.config")

local M = {}

local test_runner = nil
local scratch_counter = 0

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

local function executable(command)
  return vim.fn.executable(command) == 1
end

local function configured_db_path(opts)
  return opts.database_path or opts.db_path
end

local function store_args(opts)
  local args = { "--root", opts.root }
  local db_path = configured_db_path(opts)

  if db_path and db_path ~= "" then
    vim.list_extend(args, { "--db", db_path })
  end

  return args
end

local function contains_flag(args, flags)
  for _, arg in ipairs(args) do
    if flags[arg] then
      return true
    end
  end

  return false
end

local function result_output(result)
  return vim.trim(table.concat({
    result.stdout or "",
    result.stderr or "",
  }, "\n"))
end

local function output_lines(output)
  if output == "" then
    return { "" }
  end

  return vim.split(output, "\n", { plain = true })
end

local function open_scratch(title, output, filetype)
  local buffer = vim.api.nvim_create_buf(false, true)
  scratch_counter = scratch_counter + 1
  vim.api.nvim_buf_set_name(buffer, title .. " " .. scratch_counter)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, output_lines(output))
  vim.bo[buffer].modifiable = false
  if filetype then
    vim.bo[buffer].filetype = filetype
  end

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buffer)
  return buffer
end

local function run_with_vim_system(argv, on_result)
  vim.system(argv, { text = true }, function(result)
    on_result({
      code = result.code,
      stdout = result.stdout or "",
      stderr = result.stderr or "",
    })
  end)
end

local function append_job_data(target, data)
  if not data then
    return
  end

  for _, line in ipairs(data) do
    if line ~= "" then
      table.insert(target, line)
    end
  end
end

local function run_with_jobstart(argv, on_result)
  local stdout = {}
  local stderr = {}
  local job = vim.fn.jobstart(argv, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      append_job_data(stdout, data)
    end,
    on_stderr = function(_, data)
      append_job_data(stderr, data)
    end,
    on_exit = function(_, code)
      on_result({
        code = code,
        stdout = table.concat(stdout, "\n"),
        stderr = table.concat(stderr, "\n"),
      })
    end,
  })

  if job <= 0 then
    on_result({
      code = 127,
      stdout = "",
      stderr = "failed to start " .. table.concat(argv, " "),
    })
  end
end

local function run_async(argv, on_result)
  if test_runner then
    test_runner(argv, on_result)
    return
  end

  if vim.system then
    run_with_vim_system(argv, on_result)
    return
  end

  run_with_jobstart(argv, on_result)
end

local function fail(command_name, result)
  local output = result_output(result)
  local message = "Zorg " .. command_name .. " failed"
  if result.code then
    message = message .. " (exit " .. result.code .. ")"
  end
  if output ~= "" then
    message = message .. ": " .. output
  end

  notify(message, vim.log.levels.ERROR)
  if output ~= "" then
    schedule(function()
      open_scratch("Zorg " .. command_name .. " Error", output, "zorg-output")
    end)
  end
end

local function run_cli(command_name, argv, on_success)
  local opts = config.get()
  local command = opts.cli.command

  if not executable(command) then
    notify(command .. " not found; :Zorg" .. command_name .. " cannot run", vim.log.levels.ERROR)
    return
  end

  run_async(argv, function(result)
    schedule(function()
      if result.code == 0 then
        on_success(result)
      else
        fail(command_name, result)
      end
    end)
  end)
end

local function command_argv(parts)
  local opts = config.get()
  local argv = { opts.cli.command }
  vim.list_extend(argv, parts)
  return argv
end

local function store_command_argv(parts, extra)
  local opts = config.get()
  local argv = command_argv(parts)
  vim.list_extend(argv, store_args(opts))
  vim.list_extend(argv, extra or {})
  return argv
end

local function display_text_result(command_name, result)
  local output = result_output(result)
  if output == "" then
    notify("Zorg " .. command_name .. " completed")
    return
  end

  open_scratch("Zorg " .. command_name, output, "zorg-output")
end

local function build_query_args(command_opts)
  local raw = vim.trim(command_opts.args or "")

  if vim.startswith(raw, "--id") then
    return command_opts.fargs
  end

  return { raw }
end

local function current_zorg_path(command_opts)
  local buffer = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buffer)

  if path == "" or vim.fn.fnamemodify(path, ":e") ~= "z" then
    notify(":ZorgFix needs a .z buffer or explicit file arguments", vim.log.levels.ERROR)
    return nil
  end

  if vim.bo[buffer].modified then
    if not command_opts.bang then
      notify(
        "Write the buffer before :ZorgFix, or use :ZorgFix! to write first",
        vim.log.levels.ERROR
      )
      return nil
    end

    vim.cmd("write")
  end

  return path
end

local function build_fix_args(command_opts)
  if #command_opts.fargs > 0 then
    return command_opts.fargs
  end

  local path = current_zorg_path(command_opts)
  if not path then
    return nil
  end

  return { path }
end

local function parse_capture_result(result)
  local ok, decoded = pcall(vim.json.decode, result.stdout or "")
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  if type(decoded.destination) ~= "string" or type(decoded.zettel_id) ~= "string" then
    return nil
  end

  return decoded
end

function M.index(command_opts)
  local argv = store_command_argv({ "db", "reindex" }, command_opts.fargs)
  run_cli("Index", argv, function(result)
    display_text_result("Index", result)
  end)
end

function M.status(command_opts)
  local argv = store_command_argv({ "db", "status" }, command_opts.fargs)
  run_cli("Status", argv, function(result)
    display_text_result("Status", result)
  end)
end

function M.query(command_opts)
  local argv = store_command_argv({ "query" }, build_query_args(command_opts))
  run_cli("Query", argv, function(result)
    local output = result.stdout or ""
    if vim.trim(output) == "" then
      notify("Zorg Query returned no results")
      return
    end

    open_scratch("Zorg Query Results", vim.trim(output), "zorg-query")
  end)
end

function M.fix(command_opts)
  local args = build_fix_args(command_opts)
  if not args then
    return
  end

  local argv = command_argv({ "fix" })
  vim.list_extend(argv, args)
  run_cli("Fix", argv, function(result)
    display_text_result("Fix", result)
  end)
end

function M.capture(command_opts)
  local opts = config.get()
  local args = vim.deepcopy(command_opts.fargs)

  if not contains_flag(args, { ["--json"] = true, ["--format"] = true }) then
    table.insert(args, 1, "--json")
  end

  local argv = command_argv({ "capture" })
  vim.list_extend(argv, store_args(opts))
  vim.list_extend(argv, args)

  run_cli("Capture", argv, function(result)
    local capture = parse_capture_result(result)
    if not capture then
      display_text_result("Capture", result)
      return
    end

    notify("Captured " .. capture.zettel_id .. " -> " .. capture.destination)
    vim.cmd("edit " .. vim.fn.fnameescape(capture.destination))
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("ZorgIndex", M.index, {
    desc = "Reindex the configured Zorg root",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgStatus", M.status, {
    desc = "Show Zorg database status",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgQuery", M.query, {
    desc = "Run a Zorg LIST query",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgFix", M.fix, {
    bang = true,
    desc = "Run Zorg safe fixes",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgCapture", M.capture, {
    desc = "Capture a zettel through the Zorg CLI",
    nargs = "*",
    force = true,
  })
end

function M._set_runner_for_test(runner)
  test_runner = runner
end

return M
