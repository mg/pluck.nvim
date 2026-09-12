local fs = require("pluck.harness.fs")
local util = require("pluck.harness.util")

local M = { name = "claude" }

local function projects_dir(root)
  if root:match("[/\\]projects[/\\]?$") then
    return root
  end
  return fs.join(root, "projects")
end

---@param opts table
---@param ctx { cwd:string, limits:table, include_defaults:boolean }
---@return table
function M.find(opts, ctx)
  local out = util.context(M.name, ctx.cwd, ctx.limits)
  local match = function(path)
    return path:sub(-6) == ".jsonl" and not path:match("[/\\]history%.jsonl$")
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
    local roots = {}
    local function append(root)
      if root and root ~= "" then
        roots[#roots + 1] = root
      end
    end
    append(vim.env.CLAUDE_CONFIG_DIR)
    if vim.env.XDG_CONFIG_HOME then
      append(fs.join(vim.env.XDG_CONFIG_HOME, "claude"))
    end
    append("~/.claude")

    for _, root in ipairs(roots) do
      out.scan(projects_dir(fs.expand(root, ctx.cwd)), {
        match = match,
        kind = "transcript",
        source = "detected",
        max_depth = 3,
      })
    end
  end

  return out.files, out.warnings
end

return M
