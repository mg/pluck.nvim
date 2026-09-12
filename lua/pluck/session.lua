local fs = require("pluck.harness.fs")
local uv = vim.uv or vim.loop

local M = {}

local function mtime(path)
  local stat = uv.fs_stat(path)
  return stat and stat.mtime and stat.mtime.sec * 1000 or 0
end

local function stem(path)
  local name = path:match("([^/\\]+)$") or path
  return (name:gsub("%.jsonl$", ""):gsub("%.json$", ""))
end

local function read_jsonl_metadata(path, harness, max_lines)
  local handle = io.open(path, "r")
  if not handle then
    return nil, "could not read session file"
  end

  local metadata = {}
  for _ = 1, max_lines do
    local line = handle:read("*l")
    if not line then
      break
    end
    local ok, value = pcall(vim.json.decode, line)
    if ok and type(value) == "table" then
      if harness == "pi" then
        if value.type == "session" then
          metadata.id = metadata.id or value.id
          metadata.cwd = metadata.cwd or value.cwd
          metadata.created_at = metadata.created_at or value.timestamp
        elseif value.type == "session_info" then
          metadata.title = value.name or metadata.title
        end
      elseif harness == "claude" then
        metadata.id = metadata.id or value.sessionId
        metadata.cwd = metadata.cwd or value.cwd
        metadata.title = value.customTitle or metadata.title
        metadata.title = metadata.title or value.slug
        metadata.created_at = metadata.created_at or value.timestamp
      end
    end
  end
  handle:close()
  return metadata
end

local function file_session(file, opts)
  local metadata
  local err
  if file.path:sub(-6) == ".jsonl" then
    metadata, err = read_jsonl_metadata(file.path, file.harness, opts.max_metadata_lines)
  else
    metadata = fs.read_json(file.path)
    if type(metadata) == "table" and file.harness == "opencode" then
      metadata.cwd = metadata.cwd or metadata.directory
      metadata.created_at = metadata.created_at
        or metadata.time_created
        or (type(metadata.time) == "table" and metadata.time.created)
      metadata.updated_at = metadata.updated_at
        or metadata.time_updated
        or (type(metadata.time) == "table" and metadata.time.updated)
    end
  end
  if type(metadata) ~= "table" then
    return nil, err or "could not read session metadata"
  end

  local id = metadata.id or metadata.sessionId or stem(file.path)
  return {
    id = tostring(id),
    harness = file.harness,
    icon = opts.icons[file.harness] or "",
    path = file.path,
    kind = file.kind,
    source = file.source,
    cwd = metadata.cwd,
    title = metadata.title or metadata.name or metadata.slug or tostring(id),
    created_at = metadata.created_at,
    updated_at = metadata.updated_at or mtime(file.path),
  }
end

local function run(argv, timeout)
  if vim.fn.executable(argv[1]) ~= 1 then
    return nil, argv[1] .. " is not executable"
  end
  if vim.system then
    local result = vim.system(argv, { text = true }):wait(timeout)
    if result.code == 0 then
      return result.stdout
    end
    return nil, "command failed"
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
    return nil, "could not start command"
  end
  local status = vim.fn.jobwait({ job }, timeout)[1]
  if status == -1 then
    vim.fn.jobstop(job)
    return nil, "command timed out"
  end
  if status == 0 then
    return table.concat(stdout, "\n")
  end
  return nil, "command failed"
end

local function database_sessions(file, opts)
  local query = table.concat({
    "select id, title, directory, time_created, time_updated",
    "from session where parent_id is null order by time_updated desc",
  }, " ")
  local output, err =
    run({ opts.sqlite_command, "-json", file.path, query }, opts.command_timeout_ms)
  if not output then
    return nil, err
  end
  local ok, rows = pcall(vim.json.decode, output)
  if not ok or type(rows) ~= "table" then
    return nil, "sqlite returned invalid JSON"
  end

  local sessions = {}
  for _, row in ipairs(rows) do
    if row.id then
      sessions[#sessions + 1] = {
        id = tostring(row.id),
        harness = "opencode",
        icon = opts.icons.opencode or "",
        path = file.path,
        kind = "database",
        source = file.source,
        cwd = row.directory,
        title = row.title or tostring(row.id),
        created_at = row.time_created,
        updated_at = row.time_updated or mtime(file.path),
      }
    end
  end
  return sessions
end

local function sortable_time(value)
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

---@param discovered { files:table[], warnings:table[] }
---@param opts table
---@return { sessions:table[], warnings:table[] }
function M.from_files(discovered, opts)
  local sessions = {}
  local warnings = vim.deepcopy(discovered.warnings or {})

  for _, file in ipairs(discovered.files or {}) do
    if file.kind == "database" then
      local found, err = database_sessions(file, opts)
      if found then
        vim.list_extend(sessions, found)
      else
        warnings[#warnings + 1] = { harness = file.harness, path = file.path, message = err }
      end
    else
      local session, err = file_session(file, opts)
      if session then
        sessions[#sessions + 1] = session
      else
        warnings[#warnings + 1] = { harness = file.harness, path = file.path, message = err }
      end
    end
  end

  table.sort(sessions, function(a, b)
    local a_time = sortable_time(a.updated_at)
    local b_time = sortable_time(b.updated_at)
    if a_time == b_time then
      return a.id < b.id
    end
    return a_time > b_time
  end)
  return { sessions = sessions, warnings = warnings }
end

return M
