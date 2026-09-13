local M = {}

local highlights = {
  pi = "DiagnosticInfo",
  claude = "DiagnosticWarn",
  opencode = "DiagnosticOk",
}

---Convert normalized sessions to picker-friendly items.
---@param sessions table[]
---@return table[]
function M.items(sessions)
  local items = {}
  for index, session in ipairs(sessions) do
    local location = session.cwd or session.path
    items[index] = {
      idx = index,
      text = table.concat({ session.title or session.id, location or "", session.harness }, " "),
      file = session.kind == "transcript" and session.path or nil,
      preview = {
        text = table.concat({
          "Harness: " .. session.harness,
          "Title:   " .. (session.title or session.id),
          "Project: " .. (session.cwd or "unknown"),
          "Storage: " .. session.path,
          "Updated: " .. tostring(session.updated_at or "unknown"),
        }, "\n"),
        ft = "text",
        loc = false,
      },
      session = session,
    }
  end
  return items
end

local function format(item)
  local session = item.session
  local location = session.cwd or session.path
  return {
    { session.icon .. " ", highlights[session.harness] },
    { session.title or session.id },
    { "  " .. location, "Comment" },
  }
end

---Open a Snacks picker containing the supplied normalized sessions.
---@param sessions table[]
---@param opts? table
---@return any
function M.snacks(sessions, opts)
  opts = opts or {}
  local snacks = rawget(_G, "Snacks")
  if not snacks then
    local ok, loaded = pcall(require, "snacks")
    snacks = ok and loaded or nil
  end
  if not snacks or not snacks.picker then
    error("pluck: snacks.nvim picker is not available")
  end

  local on_select = opts.on_select
  local picker_opts = vim.tbl_deep_extend("force", {
    title = "Pluck Session",
    items = M.items(sessions),
    format = format,
    preview = "preview",
    sort = { fields = { "idx" } },
    matcher = { sort_empty = false },
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      if on_select then
        on_select(item.session)
      else
        require("pluck").open_session(item.session, opts.session_window)
      end
      vim.api.nvim_exec_autocmds("User", {
        pattern = "PluckSessionSelected",
        data = item.session,
      })
    end,
  }, opts.snacks or {})
  return snacks.picker.pick(picker_opts)
end

return M
