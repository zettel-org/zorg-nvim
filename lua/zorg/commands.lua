local config = require("zorg.config")

local M = {}

local test_runner = nil
local scratch_counter = 0

local completions = {
  capture = {
    "--allow-outside",
    "--body",
    "--db",
    "--dest",
    "--format",
    "--help",
    "--id",
    "--json",
    "--root",
    "--source",
    "--template",
    "--title",
  },
  export_markdown = {
    "--db",
    "--format",
    "--help",
    "--id",
    "--json",
    "--out",
    "--query",
    "--query-id",
    "--root",
    "--stdout",
    "--subtree",
  },
  fix = {
    "--check",
    "--db",
    "--format",
    "--help",
    "--json",
    "--root",
  },
  move = {
    "--check",
    "--db",
    "--format",
    "--help",
    "--json",
    "--root",
    "--to",
    "--write",
  },
  open = {
    "--db",
    "--format",
    "--help",
    "--json",
    "--root",
  },
  path = {
    "--db",
    "--format",
    "--help",
    "--json",
    "--root",
  },
  promote = {
    "--check",
    "--db",
    "--format",
    "--help",
    "--json",
    "--root",
    "--to",
    "--write",
  },
  index = {
    "--db",
    "--help",
    "--root",
  },
  import_apply = {
    "--dest",
    "--format",
    "--help",
    "--json",
    "--root",
  },
  import_plan = {
    "--dest",
    "--format",
    "--help",
    "--json",
    "--root",
  },
  query = {
    "--db",
    "--format",
    "--help",
    "--id",
    "--json",
    "--root",
  },
  extract = {
    "--byte-range",
    "--check",
    "--db",
    "--file",
    "--format",
    "--help",
    "--id",
    "--json",
    "--replace-with-link",
    "--root",
    "--to",
    "--write",
  },
  status = {
    "--db",
    "--help",
    "--root",
  },
  watch = {
    "--db",
    "--debounce",
    "--exit-after-events",
    "--exit-after-ready",
    "--format",
    "--help",
    "--json",
    "--once",
    "--root",
  },
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

local function open_scratch_lines(title, lines, filetype)
  local buffer = vim.api.nvim_create_buf(false, true)
  scratch_counter = scratch_counter + 1
  vim.api.nvim_buf_set_name(buffer, title .. " " .. scratch_counter)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false
  if filetype then
    vim.bo[buffer].filetype = filetype
  end

  pcall(vim.cmd, "botright split")
  vim.api.nvim_win_set_buf(0, buffer)
  return buffer
end

local function open_scratch(title, output, filetype)
  return open_scratch_lines(title, output_lines(output), filetype)
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
  local unavailable = output:match("unknown zorg command")
    or output:match("unsupported import")
    or output:match("unsupported export")
  local message = unavailable and ("Zorg " .. command_name .. " is unavailable in this zorg binary")
    or ("Zorg " .. command_name .. " failed")
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

local function root_args(opts)
  return { "--root", opts.root }
end

local function display_text_result(command_name, result)
  local output = result_output(result)
  if output == "" then
    notify("Zorg " .. command_name .. " completed")
    return
  end

  open_scratch("Zorg " .. command_name, output, "zorg-output")
end

local function has_json_format(args)
  return contains_flag(args, { ["--json"] = true, ["--format"] = true })
end

local function decode_json_result(command_name, result)
  local output = vim.trim(result.stdout or "")
  local ok, decoded = pcall(vim.json.decode, output)
  if ok and type(decoded) == "table" then
    return decoded
  end

  notify("Zorg " .. command_name .. " returned invalid JSON", vim.log.levels.ERROR)
  if output ~= "" then
    open_scratch("Zorg " .. command_name .. " Output", output, "zorg-output")
  end
  return nil
end

local function has_flag(args, flag)
  for _, arg in ipairs(args) do
    if arg == flag then
      return true
    end
  end

  return false
end

local function force_json_args(args)
  local filtered = {}
  local skip_next = false

  for _, arg in ipairs(args) do
    if skip_next then
      skip_next = false
    elseif arg == "--format" then
      skip_next = true
    elseif arg ~= "--json" then
      table.insert(filtered, arg)
    end
  end

  vim.list_extend(filtered, { "--format", "json" })
  return filtered
end

local function current_zorg_path_for(command_name, command_opts)
  local buffer = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buffer)

  if path == "" or vim.fn.fnamemodify(path, ":e") ~= "z" then
    notify(":Zorg" .. command_name .. " needs a .z buffer or explicit file arguments", vim.log.levels.ERROR)
    return nil
  end

  if vim.bo[buffer].modified then
    if not command_opts.bang then
      notify(
        "Write the buffer before :Zorg" .. command_name .. ", or use :Zorg" .. command_name .. "! to write first",
        vim.log.levels.ERROR
      )
      return nil
    end

    vim.cmd("write")
  end

  return path
end

local function jump_to_location(command_name, result)
  local location = decode_json_result(command_name, result)
  if not location then
    return
  end

  local path = location.absolute_path
  if type(path) ~= "string" or path == "" then
    notify("Zorg " .. command_name .. " JSON did not include an absolute_path", vim.log.levels.ERROR)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))

  local span = location.source_span or {}
  local line = math.max(tonumber(span.start_line) or 1, 1)
  local column = math.max((tonumber(span.start_column) or 1) - 1, 0)
  pcall(vim.api.nvim_win_set_cursor, 0, { line, column })
end

local function open_location_command(cli_command, command_name, command_opts)
  if #command_opts.fargs == 0 then
    notify(":Zorg" .. command_name .. " requires a zettel ID", vim.log.levels.ERROR)
    return
  end

  local argv = store_command_argv({ cli_command }, force_json_args(command_opts.fargs))
  run_cli(command_name, argv, function(result)
    jump_to_location(command_name, result)
  end)
end

local function refactor_preview(command_name, result)
  local preview = decode_json_result(command_name, result)
  if not preview then
    return nil
  end

  if preview.schema_version ~= 1 or type(preview.plan) ~= "table" then
    notify("Zorg " .. command_name .. " returned an unsupported preview schema", vim.log.levels.ERROR)
    return nil
  end

  open_scratch("Zorg " .. command_name .. " Preview", vim.trim(result.stdout or ""), "json")
  return preview
end

local function refresh_refactor_buffers(preview)
  local paths = {}
  local files = preview.plan and preview.plan.files or {}

  for _, file in ipairs(files) do
    if type(file.absolute_path) == "string" then
      paths[file.absolute_path] = true
    end
  end

  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buffer)
    if paths[name] and vim.api.nvim_buf_is_loaded(buffer) and not vim.bo[buffer].modified then
      vim.api.nvim_buf_call(buffer, function()
        vim.cmd("silent! checktime")
      end)
    end
  end
end

local function reindex_after_refactor(command_name)
  local argv = store_command_argv({ "db", "reindex" }, {})
  run_cli(command_name .. " Reindex", argv, function()
    notify("Zorg " .. command_name .. " applied and reindexed")
  end)
end

local function run_refactor_write(command_name, cli_command, command_opts, preview)
  local args = force_json_args(command_opts.fargs)
  table.insert(args, "--write")

  local argv = store_command_argv({ cli_command }, args)
  run_cli(command_name, argv, function()
    refresh_refactor_buffers(preview)
    reindex_after_refactor(command_name)
  end)
end

local function confirm_refactor_write(command_name, cli_command, command_opts, preview)
  vim.ui.select({ "Apply", "Cancel" }, {
    prompt = "Apply Zorg " .. command_name .. " changes?",
  }, function(choice)
    if choice ~= "Apply" then
      notify("Zorg " .. command_name .. " cancelled")
      return
    end

    run_refactor_write(command_name, cli_command, command_opts, preview)
  end)
end

local function run_refactor_preview(command_name, cli_command, command_opts)
  if has_flag(command_opts.fargs, "--write") then
    notify(":Zorg" .. command_name .. " runs --write only after preview confirmation", vim.log.levels.ERROR)
    return
  end

  local argv = store_command_argv({ cli_command }, force_json_args(command_opts.fargs))
  run_cli(command_name, argv, function(result)
    local preview = refactor_preview(command_name, result)
    if preview then
      confirm_refactor_write(command_name, cli_command, command_opts, preview)
    end
  end)
end

local function command_line_range(command_opts)
  if not command_opts.range or command_opts.range == 0 then
    return nil
  end

  local line1 = command_opts.line1
  local line2 = command_opts.line2
  local start_column = 1
  local end_line_text = vim.api.nvim_buf_get_lines(0, line2 - 1, line2, false)[1] or ""
  local end_column = #end_line_text + 1

  local visual_start = vim.fn.getpos("'<")
  local visual_end = vim.fn.getpos("'>")
  if visual_start[2] == line1 and visual_end[2] == line2 then
    start_column = math.max(visual_start[3], 1)
    end_column = math.max(visual_end[3], 1)
  end

  if line2 < line1 or (line1 == line2 and end_column < start_column) then
    line1, line2 = line2, line1
    start_column, end_column = end_column, start_column
  end

  return string.format("%d:%d-%d:%d", line1, start_column, line2, end_column)
end

local function build_extract_args(command_opts)
  local path = current_zorg_path_for("Extract", command_opts)
  if not path then
    return nil
  end

  local range = command_line_range(command_opts)
  if not range then
    notify(":ZorgExtract must be run with a visual or line range", vim.log.levels.ERROR)
    return nil
  end

  local args = vim.deepcopy(command_opts.fargs)
  local extract_id = nil
  if not has_flag(args, "--id") then
    extract_id = table.remove(args, 1)
    if not extract_id or extract_id == "" or vim.startswith(extract_id, "-") then
      notify(":ZorgExtract requires a new zettel ID or --id @new/id", vim.log.levels.ERROR)
      return nil
    end
  end

  local built = { "--file", path, "--range", range }
  if extract_id then
    vim.list_extend(built, { "--id", extract_id })
  end
  vim.list_extend(built, args)
  return built
end

local function append_section(lines, title, entries)
  table.insert(lines, "")
  table.insert(lines, title)
  if #entries == 0 then
    table.insert(lines, "  (none)")
    return
  end

  for _, entry in ipairs(entries) do
    table.insert(lines, "  " .. entry)
  end
end

local function summary_line(summary)
  summary = summary or {}
  local parts = {}
  for _, key in ipairs({ "planned", "rendered", "lossy", "unsupported", "fatal" }) do
    if summary[key] ~= nil then
      table.insert(parts, key .. "=" .. tostring(summary[key]))
    end
  end

  return table.concat(parts, "  ")
end

local function bridge_diagnostic_line(diagnostic)
  if type(diagnostic) ~= "table" then
    return tostring(diagnostic)
  end

  local location = diagnostic.path or diagnostic.source_path or diagnostic.canonical_id or ""
  if diagnostic.line then
    location = location .. ":" .. tostring(diagnostic.line)
  end

  local prefix = vim.trim(table.concat(vim.tbl_filter(function(value)
    return value and value ~= ""
  end, {
    diagnostic.severity,
    diagnostic.kind,
    diagnostic.code,
    location,
  }), " "))

  if prefix == "" then
    return diagnostic.message or vim.inspect(diagnostic)
  end

  return prefix .. ": " .. (diagnostic.message or "")
end

local function render_import_report(report)
  local lines = {
    report.command or "import legacy",
    summary_line(report.summary),
  }

  local writes = {}
  for _, output in ipairs(report.outputs or {}) do
    table.insert(
      writes,
      string.format(
        "%s <- %s (@%s) [%s]",
        output.root_relative_path or "(unknown)",
        output.input_path or "(unknown)",
        output.canonical_id or "?",
        output.status or "planned"
      )
    )
  end
  append_section(lines, "Writes", writes)

  local warnings = {}
  local lossy = {}
  local unsupported = {}
  local errors = {}
  for _, diagnostic in ipairs(report.diagnostics or {}) do
    local rendered = bridge_diagnostic_line(diagnostic)
    if diagnostic.severity == "warning" then
      table.insert(warnings, rendered)
    end
    if diagnostic.kind == "lossy" then
      table.insert(lossy, rendered)
    elseif diagnostic.kind == "unsupported" then
      table.insert(unsupported, rendered)
    end
    if diagnostic.severity == "error" then
      table.insert(errors, rendered)
    end
  end

  for _, output in ipairs(report.outputs or {}) do
    for _, loss in ipairs(output.lossiness or {}) do
      table.insert(lossy, (output.root_relative_path or "(unknown)") .. ": " .. tostring(loss))
    end
  end

  for _, collision in ipairs(report.collisions or {}) do
    table.insert(errors, "collision: " .. vim.inspect(collision))
  end

  append_section(lines, "Warnings", warnings)
  append_section(lines, "Lossy Transforms", lossy)
  append_section(lines, "Unsupported Forms", unsupported)
  append_section(lines, "Errors", errors)

  if report.write_results then
    local results = {}
    for _, result in ipairs(report.write_results or {}) do
      local line = string.format(
        "%s -> %s [%s]",
        result.input_path or "(unknown)",
        result.path or result.root_relative_path or "(unknown)",
        result.status or "unknown"
      )
      if result.error then
        line = line .. ": " .. result.error
      end
      table.insert(results, line)
    end
    append_section(lines, "Write Results", results)
  end

  return table.concat(lines, "\n")
end

local function render_export_report(report)
  local lines = {
    report.command or "export markdown",
    summary_line(report.summary),
  }

  if report.output then
    if report.output.mode == "directory" then
      table.insert(lines, "Output directory: " .. tostring(report.output.directory))
    elseif report.output.mode == "stdout" then
      table.insert(lines, "Output: stdout (" .. tostring(report.output.items or 0) .. " items)")
    end
  end

  local items = {}
  for _, item in ipairs(report.items or {}) do
    table.insert(
      items,
      string.format("@%s  %s  %s", item.canonical_id or "?", item.source_path or "", item.title or "")
    )
  end
  append_section(lines, "Items", items)

  local writes = {}
  if report.output and report.output.written then
    for _, write in ipairs(report.output.written) do
      table.insert(writes, string.format("@%s -> %s", write.canonical_id or "?", write.path or "?"))
    end
  end
  append_section(lines, "Written Files", writes)

  local diagnostics = {}
  for _, diagnostic in ipairs(report.diagnostics or {}) do
    table.insert(diagnostics, bridge_diagnostic_line(diagnostic))
  end
  append_section(lines, "Diagnostics", diagnostics)

  return table.concat(lines, "\n")
end

local function has_query_output_flag(args)
  return contains_flag(args, { ["--json"] = true, ["--format"] = true })
end

local function join_args(args, start_index)
  local joined = {}

  for index = start_index, #args do
    table.insert(joined, args[index])
  end

  return table.concat(joined, " ")
end

local function build_flagged_query_args(fargs)
  local args = {}
  local flags_with_value = {
    ["--db"] = true,
    ["--format"] = true,
    ["--id"] = true,
    ["--root"] = true,
  }
  local flags_without_value = {
    ["--help"] = true,
    ["--json"] = true,
  }
  local index = 1

  while index <= #fargs do
    local arg = fargs[index]

    if flags_with_value[arg] then
      table.insert(args, arg)
      if fargs[index + 1] then
        table.insert(args, fargs[index + 1])
      end
      index = index + 2
    elseif flags_without_value[arg] then
      table.insert(args, arg)
      index = index + 1
    else
      break
    end
  end

  if index <= #fargs then
    table.insert(args, join_args(fargs, index))
  end

  return args
end

local function build_query_args(command_opts)
  local raw = vim.trim(command_opts.args or "")

  if raw == "" then
    return {}
  end

  if vim.startswith(raw, "-") then
    return build_flagged_query_args(command_opts.fargs)
  end

  return { raw }
end

local function build_json_query_args(command_opts)
  local args = build_query_args(command_opts)

  if not has_query_output_flag(args) then
    table.insert(args, 1, "--json")
  end

  return args
end

local function query_wants_json(args)
  if contains_flag(args, { ["--json"] = true }) then
    return true
  end

  for index, arg in ipairs(args) do
    if arg == "--format" then
      return args[index + 1] == "json"
    end
  end

  return false
end

local function display_cell(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

local function display_path(path)
  if type(path) == "string" and path ~= "" then
    return path
  end

  return "<unknown>"
end

local function display_span(span)
  if type(span) ~= "table" then
    return ""
  end

  local line = tonumber(span.start_line)
  local column = tonumber(span.start_column)
  if not line then
    return ""
  end

  if column then
    return ":" .. line .. ":" .. column
  end

  return ":" .. line
end

local function query_location(row)
  if type(row) ~= "table" then
    return nil
  end

  local path = row.path or row.file
  if type(path) ~= "string" or path == "" then
    return nil
  end

  return {
    path = path,
    span = type(row.span) == "table" and row.span or nil,
  }
end

local function add_location(locations, line_number, row)
  local location = query_location(row)

  if location then
    locations[line_number] = location
  end
end

local function diagnostic_line(diagnostic)
  if type(diagnostic) ~= "table" then
    return tostring(diagnostic)
  end

  local severity = display_cell(diagnostic.severity)
  local code = display_cell(diagnostic.code)
  local message = display_cell(diagnostic.message or diagnostic.error)
  local prefix = vim.trim(table.concat({ severity, code }, " "))

  if prefix == "" then
    return message
  end

  return prefix .. ": " .. message
end

local function render_diagnostics(payload, lines)
  if type(payload.diagnostics) ~= "table" or #payload.diagnostics == 0 then
    return
  end

  if #lines > 0 then
    table.insert(lines, "")
  end
  table.insert(lines, "Diagnostics")

  for _, diagnostic in ipairs(payload.diagnostics) do
    table.insert(lines, "  " .. diagnostic_line(diagnostic))
  end
end

local function render_query_list(payload)
  local lines = {}
  local locations = {}
  local rows = type(payload.rows) == "table" and payload.rows or {}

  if #rows == 0 then
    table.insert(lines, "No query results.")
  else
    local id_width = 2
    local todo_width = 4

    for _, row in ipairs(rows) do
      id_width = math.max(id_width, #display_cell(row.canonical_id))
      todo_width = math.max(todo_width, #display_cell(row.todo_marker))
    end

    for _, row in ipairs(rows) do
      local line = string.format(
        "%-" .. todo_width .. "s  %-" .. id_width .. "s  %s  %s%s",
        display_cell(row.todo_marker),
        display_cell(row.canonical_id),
        display_cell(row.title),
        display_path(row.path),
        display_span(row.span)
      )
      table.insert(lines, line)
      add_location(locations, #lines, row)
    end
  end

  render_diagnostics(payload, lines)
  return lines, locations
end

local function table_column_keys(payload)
  local keys = {}

  if type(payload.columns) == "table" then
    for _, column in ipairs(payload.columns) do
      if type(column) == "table" and type(column.key) == "string" then
        table.insert(keys, column.key)
      end
    end
  end

  if #keys == 0 then
    keys = { "todo", "id", "file", "title" }
  end

  return keys
end

local function render_query_table(payload)
  local lines = {}
  local locations = {}
  local rows = type(payload.rows) == "table" and payload.rows or {}
  local keys = table_column_keys(payload)

  if #rows == 0 then
    table.insert(lines, "No query results.")
  else
    local widths = {}

    for _, key in ipairs(keys) do
      widths[key] = #key
    end

    for _, row in ipairs(rows) do
      for _, key in ipairs(keys) do
        widths[key] = math.max(widths[key], #display_cell(row[key]))
      end
    end

    local header = {}
    local separator = {}
    for _, key in ipairs(keys) do
      table.insert(header, string.format("%-" .. widths[key] .. "s", key))
      table.insert(separator, string.rep("-", widths[key]))
    end
    table.insert(lines, table.concat(header, "  "))
    table.insert(lines, table.concat(separator, "  "))

    for _, row in ipairs(rows) do
      local cells = {}
      for _, key in ipairs(keys) do
        table.insert(cells, string.format("%-" .. widths[key] .. "s", display_cell(row[key])))
      end
      table.insert(lines, table.concat(cells, "  "))
      add_location(locations, #lines, row)
    end
  end

  render_diagnostics(payload, lines)
  return lines, locations
end

local function render_query_aggregate(payload)
  local lines = {}

  if type(payload.values) == "table" then
    for key, value in pairs(payload.values) do
      table.insert(lines, key .. " " .. display_cell(value))
    end
  end

  if #lines == 0 then
    table.insert(lines, "No query results.")
  end

  render_diagnostics(payload, lines)
  return lines, {}
end

local function open_query_result_buffer(lines, locations)
  local buffer = open_scratch_lines("Zorg Query Results", lines, "zorg-query")
  vim.b[buffer].zorg_query_locations = locations

  vim.keymap.set("n", "<CR>", M.open_query_result, {
    buffer = buffer,
    desc = "Open Zorg query result",
    nowait = true,
    silent = true,
  })
  vim.keymap.set("n", "o", M.open_query_result, {
    buffer = buffer,
    desc = "Open Zorg query result",
    nowait = true,
    silent = true,
  })

  return buffer
end

local function render_query_json(result)
  local ok, payload = pcall(vim.json.decode, result.stdout or "")
  if not ok or type(payload) ~= "table" then
    notify("Zorg Query returned invalid JSON", vim.log.levels.ERROR)
    open_scratch("Zorg Query Error", result_output(result), "zorg-output")
    return
  end

  if payload.schema_version ~= 1 then
    notify(
      "Zorg Query returned unsupported JSON schema version " .. display_cell(payload.schema_version),
      vim.log.levels.ERROR
    )
    open_scratch("Zorg Query Error", vim.json.encode(payload), "zorg-output")
    return
  end

  local lines
  local locations

  if payload.kind == "list" then
    lines, locations = render_query_list(payload)
  elseif payload.kind == "table" then
    lines, locations = render_query_table(payload)
  elseif payload.kind == "aggregate" then
    lines, locations = render_query_aggregate(payload)
  else
    notify("Zorg Query returned unsupported result kind " .. display_cell(payload.kind), vim.log.levels.ERROR)
    open_scratch("Zorg Query Error", vim.json.encode(payload), "zorg-output")
    return
  end

  open_query_result_buffer(lines, locations)
end

local function current_zorg_path(command_opts)
  return current_zorg_path_for("Fix", command_opts)
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

local function current_zettel_id()
  local buffer = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buffer)

  if path == "" or vim.fn.fnamemodify(path, ":e") ~= "z" then
    notify(":ZorgExportCurrent needs a .z buffer", vim.log.levels.ERROR)
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, math.min(20, line_count), false)
  for _, line in ipairs(lines) do
    local id = line:match("^%%+%s+(@%S+)")
    if id then
      return id
    end
  end

  notify(":ZorgExportCurrent could not find a canonical @id in the current buffer", vim.log.levels.ERROR)
  return nil
end

local function run_import(command_name, mode, command_opts)
  local opts = config.get()
  local args = vim.deepcopy(command_opts.fargs)
  if not has_json_format(args) then
    table.insert(args, 1, "--json")
  end

  local argv = command_argv({ "import", "legacy", mode })
  vim.list_extend(argv, root_args(opts))
  vim.list_extend(argv, args)

  run_cli(command_name, argv, function(result)
    local report = decode_json_result(command_name, result)
    if report then
      open_scratch("Zorg " .. command_name, render_import_report(report), "zorg-output")
    end
  end)
end

local function run_export(command_name, args)
  local argv = store_command_argv({ "export", "markdown" }, args)
  run_cli(command_name, argv, function(result)
    local output = vim.trim(result.stdout or "")
    if output == "" then
      notify("Zorg " .. command_name .. " completed")
      return
    end

    if output:sub(1, 1) == "{" then
      local report = decode_json_result(command_name, result)
      if report then
        open_scratch("Zorg " .. command_name, render_export_report(report), "zorg-output")
      end
      return
    end

    open_scratch("Zorg " .. command_name, output, "markdown")
  end)
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

function M.open_query_result()
  local buffer = vim.api.nvim_get_current_buf()
  local locations = vim.b[buffer].zorg_query_locations
  local location = type(locations) == "table" and locations[vim.api.nvim_win_get_cursor(0)[1]] or nil

  if type(location) ~= "table" then
    notify("No Zorg query source location on this line", vim.log.levels.WARN)
    return
  end

  local path = location.path
  if not vim.startswith(path, "/") then
    path = vim.fs.joinpath(config.get().root, path)
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))

  if type(location.span) == "table" and tonumber(location.span.start_line) then
    local line = math.max(tonumber(location.span.start_line) or 1, 1)
    local column = math.max((tonumber(location.span.start_column) or 1) - 1, 0)
    pcall(vim.api.nvim_win_set_cursor, 0, { line, column })
  end
end

function M.query(command_opts)
  local args = build_json_query_args(command_opts)
  local wants_json = query_wants_json(args)
  local argv = store_command_argv({ "query" }, args)

  run_cli("Query", argv, function(result)
    local output = result.stdout or ""
    if vim.trim(output) == "" then
      notify("Zorg Query returned no results")
      return
    end

    if wants_json then
      render_query_json(result)
    else
      open_scratch("Zorg Query Results", vim.trim(output), "zorg-query")
    end
  end)
end

function M.fix(command_opts)
  local args = build_fix_args(command_opts)
  if not args then
    return
  end

  local argv = store_command_argv({ "fix" }, args)
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

function M.path(command_opts)
  open_location_command("path", "Path", command_opts)
end

function M.open(command_opts)
  open_location_command("open", "Open", command_opts)
end

function M.promote(command_opts)
  run_refactor_preview("Promote", "promote", command_opts)
end

function M.move(command_opts)
  run_refactor_preview("Move", "move", command_opts)
end

function M.extract(command_opts)
  local args = build_extract_args(command_opts)
  if not args then
    return
  end

  run_refactor_preview(
    "Extract",
    "extract",
    vim.tbl_extend("force", command_opts, { fargs = args })
  )
end

function M.import_plan(command_opts)
  run_import("ImportPlan", "plan", command_opts)
end

function M.import_apply(command_opts)
  local function apply()
    run_import("ImportApply", "apply", command_opts)
  end

  if command_opts.bang then
    apply()
    return
  end

  vim.ui.select({ "Apply", "Cancel" }, { prompt = "Apply legacy Zorg import plan?" }, function(choice)
    if choice == "Apply" then
      apply()
    else
      notify("Zorg ImportApply cancelled")
    end
  end)
end

function M.export_markdown(command_opts)
  run_export("ExportMarkdown", vim.deepcopy(command_opts.fargs))
end

function M.export_current(command_opts)
  local id = current_zettel_id()
  if not id then
    return
  end

  local args = { "--id", id }
  vim.list_extend(args, command_opts.fargs)
  run_export("ExportCurrent", args)
end

function M.export_subtree(command_opts)
  if #command_opts.fargs == 0 then
    notify(":ZorgExportSubtree needs a root @id", vim.log.levels.ERROR)
    return
  end

  local args = { "--subtree", command_opts.fargs[1] }
  for index = 2, #command_opts.fargs do
    table.insert(args, command_opts.fargs[index])
  end
  run_export("ExportSubtree", args)
end

function M.export_query(command_opts)
  local raw = vim.trim(command_opts.args or "")
  if raw == "" then
    notify(":ZorgExportQuery needs inline SWOG text or --query-id @id", vim.log.levels.ERROR)
    return
  end

  if vim.startswith(raw, "--query-id") then
    run_export("ExportQuery", command_opts.fargs)
    return
  end

  run_export("ExportQuery", { "--query", raw })
end

function M.watch_start(command_opts)
  require("zorg.watcher").start(command_opts)
end

function M.watch_stop(command_opts)
  require("zorg.watcher").stop(command_opts)
end

function M.watch_status(command_opts)
  require("zorg.watcher").status(command_opts)
end

function M.setup()
  require("zorg.watcher").setup()
  vim.api.nvim_create_user_command("ZorgIndex", M.index, {
    complete = M.complete_index,
    desc = "Reindex the configured Zorg root",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgStatus", M.status, {
    complete = M.complete_status,
    desc = "Show Zorg database status",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgWatchStart", M.watch_start, {
    complete = M.complete_watch,
    desc = "Start the Zorg live indexing watcher",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgWatchStop", M.watch_stop, {
    desc = "Stop the Zorg live indexing watcher",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgWatchStatus", M.watch_status, {
    desc = "Show Zorg watcher lifecycle status",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgQuery", M.query, {
    complete = M.complete_query,
    desc = "Run a Zorg query",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgFix", M.fix, {
    bang = true,
    complete = M.complete_fix,
    desc = "Run Zorg safe fixes",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgCapture", M.capture, {
    complete = M.complete_capture,
    desc = "Capture a zettel through the Zorg CLI",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgPath", M.path, {
    complete = M.complete_path,
    desc = "Open the source location for a Zorg zettel ID",
    nargs = "+",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgOpen", M.open, {
    complete = M.complete_open,
    desc = "Open the source location for a Zorg zettel ID",
    nargs = "+",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgPromote", M.promote, {
    complete = M.complete_promote,
    desc = "Preview and apply a Zorg promote refactor",
    nargs = "+",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgMove", M.move, {
    complete = M.complete_move,
    desc = "Preview and apply a Zorg move refactor",
    nargs = "+",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgExtract", M.extract, {
    bang = true,
    complete = M.complete_extract,
    desc = "Preview and apply a Zorg extract refactor from a selected range",
    nargs = "*",
    range = true,
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgImportPlan", M.import_plan, {
    complete = M.complete_import_plan,
    desc = "Preview a legacy Zorg import plan",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgImportApply", M.import_apply, {
    bang = true,
    complete = M.complete_import_apply,
    desc = "Apply a legacy Zorg import plan after confirmation",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgExportMarkdown", M.export_markdown, {
    complete = M.complete_export_markdown,
    desc = "Run zorg export markdown with explicit selectors",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgExportCurrent", M.export_current, {
    complete = M.complete_export_markdown,
    desc = "Export the current zettel to Markdown",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgExportSubtree", M.export_subtree, {
    complete = M.complete_export_markdown,
    desc = "Export a zettel subtree to Markdown",
    nargs = "*",
    force = true,
  })
  vim.api.nvim_create_user_command("ZorgExportQuery", M.export_query, {
    complete = M.complete_export_markdown,
    desc = "Export Markdown for an inline query or query zettel",
    nargs = "*",
    force = true,
  })
end

function M.complete_flags(name, arglead)
  local matches = {}

  for _, candidate in ipairs(completions[name] or {}) do
    if vim.startswith(candidate, arglead or "") then
      table.insert(matches, candidate)
    end
  end

  return matches
end

function M.complete_index(arglead)
  return M.complete_flags("index", arglead)
end

function M.complete_status(arglead)
  return M.complete_flags("status", arglead)
end

function M.complete_watch(arglead)
  return M.complete_flags("watch", arglead)
end

function M.complete_query(arglead)
  return M.complete_flags("query", arglead)
end

function M.complete_capture(arglead)
  return M.complete_flags("capture", arglead)
end

function M.complete_fix(arglead)
  if vim.startswith(arglead or "", "-") then
    return M.complete_flags("fix", arglead)
  end

  return vim.fn.getcompletion(arglead or "", "file")
end

function M.complete_path(arglead)
  return M.complete_flags("path", arglead)
end

function M.complete_open(arglead)
  return M.complete_flags("open", arglead)
end

function M.complete_promote(arglead)
  return M.complete_flags("promote", arglead)
end

function M.complete_move(arglead)
  return M.complete_flags("move", arglead)
end

function M.complete_extract(arglead)
  return M.complete_flags("extract", arglead)
end

function M.complete_import_plan(arglead)
  if vim.startswith(arglead or "", "-") then
    return M.complete_flags("import_plan", arglead)
  end

  return vim.fn.getcompletion(arglead or "", "file")
end

function M.complete_import_apply(arglead)
  if vim.startswith(arglead or "", "-") then
    return M.complete_flags("import_apply", arglead)
  end

  return vim.fn.getcompletion(arglead or "", "file")
end

function M.complete_export_markdown(arglead)
  if vim.startswith(arglead or "", "-") then
    return M.complete_flags("export_markdown", arglead)
  end

  return vim.fn.getcompletion(arglead or "", "file")
end

function M._set_runner_for_test(runner)
  test_runner = runner
end

return M
