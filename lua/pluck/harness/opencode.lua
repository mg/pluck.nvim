local fs = require("pluck.harness.fs")
local util = require("pluck.harness.util")

local M = { name = "opencode" }

local function run(argv, timeout)
  if vim.fn.executable(argv[1]) ~= 1 then
    return nil
  end
  if vim.system then
    local result = vim.system(argv, { text = true }):wait(timeout or 2000)
    if result.code == 0 then
      return vim.trim(result.stdout or "")
    end
    return nil
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
    return nil
  end
  local status = vim.fn.jobwait({ job }, timeout or 2000)[1]
  if status == -1 then
    vim.fn.jobstop(job)
    return nil
  end
  return status == 0 and vim.trim(table.concat(stdout, "\n")) or nil
end

local function kind(path)
  return path:match("%.db$") and "database" or "transcript"
end

local function is_session_storage(path)
  local normalized = path:gsub("\\", "/")
  local name = normalized:match("([^/]+)$") or ""
  if name == "opencode.db" or name:match("^opencode%-.*%.db$") then
    return true
  end
  return name:sub(-5) == ".json" and (normalized:find("/storage/session/", 1, true) ~= nil)
end

---@param opts table
---@param ctx { cwd:string, limits:table, include_defaults:boolean }
---@return table
function M.find(opts, ctx)
  local out = util.context(M.name, ctx.cwd, ctx.limits)

  for _, path in ipairs(util.list(opts.files)) do
    local _, reason = out.add(path, kind(path), "configured_file")
    if reason == "missing" then
      out.warn(path, "configured session store does not exist")
    end
  end
  for _, root in ipairs(util.list(opts.roots)) do
    out.scan(root, {
      match = is_session_storage,
      kind = "transcript",
      source = "configured_root",
      explicit = true,
      max_depth = opts.max_depth,
    })
  end

  if ctx.include_defaults then
    local database = vim.env.OPENCODE_DB
    if database and database ~= "" and database ~= ":memory:" then
      out.add(database, "database", "environment")
    end

    local command = opts.command or { "opencode" }
    if opts.detect_command ~= false then
      local argv = vim.list_extend(vim.deepcopy(command), { "db", "path" })
      local detected = run(argv, opts.command_timeout_ms)
      if detected and detected ~= "" then
        out.add(detected:match("[^\r\n]+"), "database", "command")
      end
    end

    local data_home = vim.env.XDG_DATA_HOME or "~/.local/share"
    local data_dir = fs.join(fs.expand(data_home, ctx.cwd), "opencode")
    out.scan(data_dir, {
      match = is_session_storage,
      kind = "transcript",
      source = "detected",
      max_depth = 5,
    })
  end

  for _, file in ipairs(out.files) do
    file.kind = kind(file.path)
  end
  return out.files, out.warnings
end

return M
