local fs = require("pluck.harness.fs")

local M = {}

local function absolute(path)
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local function resolve(path, cwd)
  if type(path) ~= "string" or path == "" or path:find("%z") then
    return nil
  end
  if path:match("^file://") then
    path = path:gsub("^file://", ""):gsub("%%(%x%x)", function(hex)
      return string.char(tonumber(hex, 16))
    end)
  elseif path:match("^%a[%w+.-]*:") then
    return nil
  end
  if not absolute(path) then
    if type(cwd) ~= "string" or not absolute(cwd) then
      return nil
    end
    path = cwd:gsub("[/\\]+$", "") .. "/" .. path
  end
  return vim.fs.normalize(path)
end

local function collector(session)
  local candidates = {}
  local sequence = 0
  return candidates,
    function(raw_path, operation, source, timestamp, extra_cwd)
      local path = resolve(raw_path, extra_cwd or session.cwd)
      if path then
        sequence = sequence + 1
        candidates[#candidates + 1] = {
          path = path,
          raw_path = raw_path,
          operation = operation,
          source = source,
          timestamp = timestamp,
          sequence = sequence,
          harness = session.harness,
        }
      end
    end
end

local function jsonl(session)
  local candidates, add = collector(session)
  local warnings = {}
  local handle = io.open(session.path, "r")
  if not handle then
    return candidates,
      { { harness = session.harness, path = session.path, message = "could not read session" } }
  end

  for line in handle:lines() do
    local ok, record = pcall(vim.json.decode, line)
    if ok and type(record) == "table" then
      local message = record.message
      local content = type(message) == "table" and message.content or nil
      if type(content) == "table" then
        for _, block in ipairs(content) do
          if type(block) == "table" then
            if session.harness == "pi" and block.type == "toolCall" then
              local operation = ({ read = "read", edit = "edit", write = "write" })[block.name]
              if operation and type(block.arguments) == "table" then
                add(block.arguments.path, operation, "tool_call", record.timestamp, record.cwd)
              end
            elseif session.harness == "claude" and block.type == "tool_use" then
              local operation = ({
                Read = "read",
                Edit = "edit",
                Write = "write",
                MultiEdit = "edit",
                NotebookEdit = "edit",
              })[block.name]
              if operation and type(block.input) == "table" then
                add(
                  block.input.file_path or block.input.notebook_path,
                  operation,
                  "tool_call",
                  record.timestamp,
                  record.cwd
                )
              end
            end
          end
        end
      end

      if session.harness == "pi" and type(message) == "table" then
        if message.role == "toolResult" and type(message.details) == "table" then
          add(
            message.details.fullOutputPath,
            "generated",
            "tool_result",
            record.timestamp,
            record.cwd
          )
        elseif message.role == "bashExecution" then
          add(message.fullOutputPath, "generated", "tool_result", record.timestamp, record.cwd)
        end
      elseif session.harness == "claude" then
        local result = record.toolUseResult
        if type(result) == "table" then
          if type(result.file) == "table" then
            add(result.file.filePath, "read", "tool_result", record.timestamp, record.cwd)
          end
          add(result.filePath, "edit", "tool_result", record.timestamp, record.cwd)
        end
        local attachment = record.attachment
        if type(attachment) == "table" then
          add(
            attachment.filename or attachment.planFilePath,
            "attach",
            "attachment",
            record.timestamp,
            record.cwd
          )
        end
        if record.type == "file-history-delta" then
          add(record.trackingPath, "history", "history", record.timestamp, record.cwd)
        elseif record.type == "file-history-snapshot" and type(record.snapshot) == "table" then
          local tracked = record.snapshot.trackedFileBackups
          if type(tracked) == "table" then
            for path in pairs(tracked) do
              add(path, "history", "history", record.snapshot.timestamp, record.cwd)
            end
          end
        end
      end
    end
  end
  handle:close()
  return candidates, warnings
end

local function run_sqlite(command, database, query, timeout)
  if vim.fn.executable(command) ~= 1 then
    return nil, command .. " is not executable"
  end
  local argv = { command, "-json", database, query }
  if vim.system then
    local result = vim.system(argv, { text = true }):wait(timeout)
    if result.code == 0 then
      return result.stdout
    end
    return nil, result.code == 124 and "sqlite query timed out" or "sqlite query failed"
  end
  local stdout = {}
  local job = vim.fn.jobstart(argv, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(stdout, data)
      end
    end,
  })
  if job <= 0 then
    return nil, "could not start sqlite"
  end
  local status = vim.fn.jobwait({ job }, timeout)[1]
  if status == -1 then
    vim.fn.jobstop(job)
    return nil, "sqlite query timed out"
  end
  if status == 0 then
    return table.concat(stdout, "\n")
  end
  return nil, "sqlite query failed"
end

local function sql_hex(value)
  return (value:gsub(".", function(char)
    return ("%02X"):format(char:byte())
  end))
end

local function patch_paths(text, add, timestamp)
  if type(text) ~= "string" then
    return
  end
  for line in text:gmatch("[^\r\n]+") do
    local path = line:match("^%*%*%* Add File: (.+)$")
      or line:match("^%*%*%* Update File: (.+)$")
      or line:match("^%*%*%* Delete File: (.+)$")
      or line:match("^%*%*%* Move to: (.+)$")
    if path then
      add(path, "edit", "tool_call", timestamp)
    end
  end
end

local function extract_opencode_part(part, timestamp, add)
  if part.type == "tool" and type(part.state) == "table" then
    local input = part.state.input
    local operation = ({ read = "read", edit = "edit", write = "write", lsp = "read" })[part.tool]
    if operation and type(input) == "table" then
      add(input.filePath, operation, "tool_call", timestamp)
    elseif part.tool == "apply_patch" and type(input) == "table" then
      patch_paths(input.patchText, add, timestamp)
    end
    if type(part.state.attachments) == "table" then
      for _, attachment in ipairs(part.state.attachments) do
        if type(attachment) == "table" then
          add(attachment.path or attachment.url, "attach", "attachment", timestamp)
        end
      end
    end
  elseif part.type == "file" then
    local source = part.source
    if type(source) == "table" and (source.type == "file" or source.type == "symbol") then
      add(source.path, "attach", "attachment", timestamp)
    else
      add(part.url, "attach", "attachment", timestamp)
    end
  end
end

local function opencode(session, opts)
  local candidates, add = collector(session)
  local query = table.concat({
    "select p.time_created, p.data from part p",
    "join message m on m.id=p.message_id",
    "where hex(m.session_id)='" .. sql_hex(session.id) .. "'",
    "order by p.time_created, m.id, p.id",
  }, " ")
  local output, err = run_sqlite(opts.sqlite_command, session.path, query, opts.command_timeout_ms)
  if not output then
    return candidates, { { harness = "opencode", path = session.path, message = err } }
  end
  local ok, rows = true, {}
  if vim.trim(output) ~= "" then
    ok, rows = pcall(vim.json.decode, output)
  end
  if not ok or type(rows) ~= "table" then
    return candidates,
      { { harness = "opencode", path = session.path, message = "invalid sqlite output" } }
  end

  for _, row in ipairs(rows) do
    local decoded, part = pcall(vim.json.decode, row.data or "")
    if decoded and type(part) == "table" then
      extract_opencode_part(part, row.time_created, add)
    end
  end
  return candidates, {}
end

local function legacy_opencode(session)
  local candidates, add = collector(session)
  local storage = session.path:gsub("\\", "/"):match("^(.*[/]storage)/session/")
  if not storage then
    return candidates,
      { { harness = "opencode", path = session.path, message = "unknown legacy storage layout" } }
  end
  local messages = fs.scan(fs.join(storage, "message", session.id), {
    max_depth = 1,
    max_files = 10000,
    match = function(path)
      return path:sub(-5) == ".json"
    end,
  })
  table.sort(messages)
  for _, message_path in ipairs(messages) do
    local message = fs.read_json(message_path) or {}
    local message_id = message.id or message_path:match("([^/\\]+)%.json$")
    local parts = fs.scan(fs.join(storage, "part", message_id), {
      max_depth = 1,
      max_files = 10000,
      match = function(path)
        return path:sub(-5) == ".json"
      end,
    })
    table.sort(parts)
    for _, part_path in ipairs(parts) do
      local part = fs.read_json(part_path)
      if type(part) == "table" then
        extract_opencode_part(part, part.time_created or message.time_created, add)
      end
    end
  end
  return candidates, {}
end

local function timestamp_value(value)
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" then
    local date, millis = value:match("^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d)%.?(%d*)")
    if date then
      local ok, seconds = pcall(vim.fn.strptime, "%Y-%m-%dT%H:%M:%S", date)
      if ok then
        return seconds * 1000 + tonumber((millis .. "000"):sub(1, 3))
      end
    end
    return tonumber(value) or 0
  end
  return 0
end

local function newest_unique(candidates)
  table.sort(candidates, function(a, b)
    local a_time, b_time = timestamp_value(a.timestamp), timestamp_value(b.timestamp)
    if a_time ~= b_time then
      return a_time > b_time
    end
    if a.sequence ~= b.sequence then
      return a.sequence > b.sequence
    end
    return a.path < b.path
  end)

  local references = {}
  local seen = {}
  for _, reference in ipairs(candidates) do
    if not seen[reference.path] then
      seen[reference.path] = true
      references[#references + 1] = reference
    end
  end
  return references
end

---@param session table
---@param opts? table
---@return { references:table[], warnings:table[] }
function M.list(session, opts)
  vim.validate("session", session, "table")
  opts = opts or {}
  local candidates, warnings
  if session.harness == "pi" or session.harness == "claude" then
    candidates, warnings = jsonl(session)
  elseif session.harness == "opencode" and session.kind == "database" then
    candidates, warnings = opencode(session, opts)
  elseif session.harness == "opencode" then
    candidates, warnings = legacy_opencode(session)
  else
    candidates, warnings =
      {}, {
        { harness = session.harness, path = session.path, message = "reference format is not supported" },
      }
  end
  return { references = newest_unique(candidates), warnings = warnings }
end

return M
