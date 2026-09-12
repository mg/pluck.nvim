local fs = require("pluck.harness.fs")

local M = {}

function M.context(name, cwd, limits)
  local files = {}
  local warnings = {}
  local seen = {}
  local remaining = limits.max_files

  local function warn(path, message)
    warnings[#warnings + 1] = {
      harness = name,
      path = path,
      message = message,
    }
  end

  local function add(path, kind, source, root)
    path = fs.expand(path, cwd)
    if not path or not fs.is_file(path) then
      return false, "missing"
    end
    local canonical = fs.canonical(path)
    if seen[canonical] then
      return false, "duplicate"
    end
    seen[canonical] = true
    files[#files + 1] = {
      harness = name,
      path = path,
      kind = kind,
      source = source,
      root = root,
    }
    return true
  end

  local function scan(root, scan_opts)
    root = fs.expand(root, cwd)
    if not root then
      return
    end
    if remaining <= 0 then
      warn(root, "entry limit reached")
      return
    end
    local paths, warning, visited = fs.scan(root, {
      max_depth = scan_opts.max_depth or limits.max_depth,
      max_files = remaining,
      match = scan_opts.match,
    })
    remaining = remaining - visited
    if warning and (warning ~= "directory does not exist" or scan_opts.explicit) then
      warn(root, warning)
    end
    for _, path in ipairs(paths) do
      add(path, scan_opts.kind, scan_opts.source, root)
    end
  end

  return {
    files = files,
    warnings = warnings,
    add = add,
    scan = scan,
    warn = warn,
  }
end

function M.list(value)
  return type(value) == "table" and value or {}
end

return M
