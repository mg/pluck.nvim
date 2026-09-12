local M = {}

local function dimensions(value, total, fallback)
  if type(value) ~= "number" then
    return fallback
  end
  return value > 0 and value <= 1 and math.floor(total * value) or math.floor(value)
end

local function create_window(buf, opts)
  local style = opts.style or "float"
  if style == "tab" then
    vim.cmd.tabnew()
    local empty = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_buf(0, buf)
    if vim.api.nvim_buf_is_valid(empty) and vim.api.nvim_buf_get_name(empty) == "" then
      pcall(vim.api.nvim_buf_delete, empty, { force = true })
    end
    local win = vim.api.nvim_get_current_win()
    return win,
      function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
          vim.cmd.tabclose()
        end
      end
  end
  if style == "split" or style == "vsplit" then
    vim.cmd(style)
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    return win,
      function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end
  end

  local width = dimensions(opts.width, vim.o.columns, math.floor(vim.o.columns * 0.8))
  local height = dimensions(opts.height, vim.o.lines - 2, math.floor((vim.o.lines - 2) * 0.7))
  width = math.max(20, math.min(width, vim.o.columns - 2))
  height = math.max(3, math.min(height, vim.o.lines - 4))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = opts.border or "rounded",
    title = opts.title or " Session files ",
    title_pos = "center",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2 - 1),
    col = math.floor((vim.o.columns - width) / 2),
  })
  return win,
    function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
end

local function set_key(buf, keys, callback, description)
  if type(keys) == "string" then
    keys = { keys }
  end
  for _, key in ipairs(keys or {}) do
    vim.keymap.set(
      "n",
      key,
      callback,
      { buffer = buf, nowait = true, silent = true, desc = description }
    )
  end
end

---Open the referenced-file selector for a session.
---@param session table
---@param references table[]
---@param opts? table
---@return table state
function M.open(session, references, opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "pluck"

  local win, close = create_window(buf, opts.window or {})
  local selected = {}
  local header_lines = 2

  local function render()
    local lines = {
      ("%s %s"):format(session.icon or "", session.title or session.id),
      "<Space> select  <CR> load into quickfix  q close",
    }
    if #references == 0 then
      lines[#lines + 1] = "No file references found"
    else
      for index, reference in ipairs(references) do
        lines[#lines + 1] = ("%s %s"):format(selected[index] and "●" or "○", reference.path)
      end
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, -1, "Comment", 1, 0, -1)
    for index in pairs(selected) do
      vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticOk", index + header_lines - 1, 0, 3)
    end
  end

  local function current_index()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local index = row - header_lines
    return index >= 1 and index <= #references and index or nil
  end

  local function toggle()
    local index = current_index()
    if not index then
      return
    end
    selected[index] = not selected[index] or nil
    render()
    vim.api.nvim_win_set_cursor(win, { index + header_lines, 0 })
  end

  local function confirm()
    local chosen = {}
    for index, reference in ipairs(references) do
      if selected[index] then
        chosen[#chosen + 1] = reference
      end
    end
    if #chosen == 0 then
      chosen = references
    end

    local items = {}
    for _, reference in ipairs(chosen) do
      items[#items + 1] = {
        filename = reference.path,
        lnum = 1,
        col = 1,
        text = ("[%s] %s"):format(session.harness, reference.operation),
      }
    end
    if #items > 0 then
      vim.fn.setqflist({}, "r", {
        title = "pluck: " .. (session.title or session.id),
        items = items,
      })
    end
    close()
    if opts.open_quickfix ~= false and #items > 0 then
      vim.cmd.copen()
    end
    if opts.on_load then
      opts.on_load(chosen, session)
    end
  end

  local function move(delta)
    if #references == 0 then
      return
    end
    local index = current_index() or (delta > 0 and 0 or 1)
    index = ((index - 1 + delta) % #references) + 1
    vim.api.nvim_win_set_cursor(win, { index + header_lines, 0 })
  end

  set_key(buf, opts.keys.next, function()
    move(1)
  end, "Next file")
  set_key(buf, opts.keys.prev, function()
    move(-1)
  end, "Previous file")
  set_key(buf, opts.keys.toggle, toggle, "Toggle file")
  set_key(buf, opts.keys.confirm, confirm, "Load selected files into quickfix")
  set_key(buf, opts.keys.close, close, "Close")
  render()
  if #references > 0 then
    vim.api.nvim_win_set_cursor(win, { header_lines + 1, 0 })
  end

  return { buffer = buf, window = win, selected = selected, confirm = confirm, close = close }
end

return M
