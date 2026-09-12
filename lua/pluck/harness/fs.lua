local uv = vim.uv or vim.loop

local M = {}

local function is_absolute(path)
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

function M.join(...)
  local parts = { ... }
  local path = table.remove(parts, 1) or ""
  for _, part in ipairs(parts) do
    if part and part ~= "" then
      path = path:gsub("[/\\]+$", "") .. "/" .. part:gsub("^[/\\]+", "")
    end
  end
  return path
end

function M.expand(path, cwd)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  if path == "~" or path:sub(1, 2) == "~/" then
    path = (uv.os_homedir() or "") .. path:sub(2)
  end
  if not is_absolute(path) then
    path = M.join(cwd or uv.cwd(), path)
  end
  return vim.fs.normalize(path)
end

function M.is_file(path)
  local stat = path and uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

function M.is_dir(path)
  local stat = path and uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

function M.canonical(path)
  return uv.fs_realpath(path) or vim.fs.normalize(path)
end

function M.read_json(path)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  if not stat or stat.size > 1024 * 1024 then
    uv.fs_close(fd)
    return nil
  end
  local content = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  if not content then
    return nil
  end
  local ok, value = pcall(vim.json.decode, content)
  return ok and value or nil
end

---@param root string
---@param opts { max_depth?: integer, max_files?: integer, match: fun(path:string):boolean }
---@return string[], string|nil, integer
function M.scan(root, opts)
  local found = {}
  local seen_dirs = {}
  local max_depth = opts.max_depth or 4
  local max_files = opts.max_files or 10000
  local visited = 0
  local limited = false

  local function visit(dir, depth)
    if depth > max_depth or visited >= max_files then
      limited = visited >= max_files
      return
    end

    local canonical = M.canonical(dir)
    if seen_dirs[canonical] then
      return
    end
    seen_dirs[canonical] = true

    local handle = uv.fs_scandir(dir)
    if not handle then
      return
    end

    while visited < max_files do
      local name, kind = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      visited = visited + 1
      local path = M.join(dir, name)
      if kind == "file" then
        if opts.match(path) then
          found[#found + 1] = path
        end
      elseif kind == "directory" then
        visit(path, depth + 1)
      end
    end
  end

  if not M.is_dir(root) then
    return found, "directory does not exist", visited
  end
  visit(root, 0)
  if limited or visited >= max_files then
    return found, "entry limit reached", visited
  end
  return found, nil, visited
end

return M
