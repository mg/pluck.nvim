local fs = require("pluck.harness.fs")
local util = require("pluck.harness.util")

local M = { name = "pi" }

local function session_dir_from_settings(path, base)
  local settings = fs.read_json(path)
  if type(settings) ~= "table" or type(settings.sessionDir) ~= "string" then
    return nil
  end
  return fs.expand(settings.sessionDir, base)
end

local function project_is_trusted(agent_dir, cwd)
  local trust = fs.read_json(fs.join(agent_dir, "trust.json"))
  if type(trust) ~= "table" then
    return false
  end
  return trust[fs.canonical(cwd)] == true or trust[vim.fs.normalize(cwd)] == true
end

---@param opts table
---@param ctx { cwd:string, limits:table, include_defaults:boolean }
---@return table
function M.find(opts, ctx)
  local out = util.context(M.name, ctx.cwd, ctx.limits)
  local match = function(path)
    return path:sub(-6) == ".jsonl"
  end

  for _, path in ipairs(util.list(opts.files)) do
    local _, reason = out.add(path, "transcript", "configured_file")
    if reason == "missing" then
      out.warn(path, "configured session file does not exist")
    end
  end
  for _, root in ipairs(util.list(opts.roots)) do
    out.scan(root, {
      match = match,
      kind = "transcript",
      source = "configured_root",
      explicit = true,
      max_depth = opts.max_depth,
    })
  end

  if ctx.include_defaults then
    local session_file = vim.env.PI_SESSION_FILE
    if session_file and session_file ~= "" then
      out.add(session_file, "transcript", "environment")
    end

    local agent_dir = fs.expand(vim.env.PI_CODING_AGENT_DIR or "~/.pi/agent", ctx.cwd)
    local roots = {}
    local function append(root)
      if root and root ~= "" then
        roots[#roots + 1] = root
      end
    end
    append(vim.env.PI_CODING_AGENT_SESSION_DIR)
    append(session_dir_from_settings(fs.join(agent_dir, "settings.json"), agent_dir))
    if project_is_trusted(agent_dir, ctx.cwd) then
      local project_config_dir = fs.join(ctx.cwd, ".pi")
      append(
        session_dir_from_settings(fs.join(project_config_dir, "settings.json"), project_config_dir)
      )
    end
    append(fs.join(agent_dir, "sessions"))

    for _, root in ipairs(roots) do
      out.scan(root, {
        match = match,
        kind = "transcript",
        source = "detected",
        max_depth = 2,
      })
    end
  end

  return out.files, out.warnings
end

return M
