local M = {}

---Configure pluck.
---@param options? table
---@return table
function M.setup(options)
  return require("pluck.config").setup(options)
end

---Find session transcript files and stores for supported agent harnesses.
---@param options? table
---@return { files: table[], warnings: table[] }
function M.find_session_files(options)
  return require("pluck.harness").find(options)
end

---Load normalized sessions, ordered from newest to oldest.
---@param options? table
---@return { sessions: table[], warnings: table[] }
function M.list_sessions(options)
  options = options or {}
  local config = require("pluck.config")
  local session_options =
    vim.tbl_deep_extend("force", {}, config.options.sessions, options.sessions or {})
  return require("pluck.session").from_files(M.find_session_files(options), session_options)
end

---Convert sessions into generic picker items.
---@param options? table
---@return table[], table[] warnings
function M.picker_items(options)
  local result = M.list_sessions(options)
  return require("pluck.picker").items(result.sessions), result.warnings
end

---Open the session list in snacks.nvim.
---@param options? table
---@return any
function M.pick(options)
  options = options or {}
  local result = M.list_sessions(options)
  return require("pluck.picker").snacks(result.sessions, options), result.warnings
end

-- Compatibility alias for the original file-discovery API.
M.find_sessions = M.find_session_files

return M
