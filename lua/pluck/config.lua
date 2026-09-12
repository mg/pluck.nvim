local M = {}

M.defaults = {
  enabled = true,
  include_defaults = true,
  limits = {
    max_depth = 4,
    max_files = 10000,
  },
  sessions = {
    max_metadata_lines = 500,
    sqlite_command = "sqlite3",
    command_timeout_ms = 2000,
    icons = {
      pi = "π",
      claude = "󰚩",
      opencode = "󰘦",
    },
  },
  harnesses = {
    pi = {
      enabled = true,
      files = {},
      roots = {},
    },
    claude = {
      enabled = true,
      files = {},
      roots = {},
    },
    opencode = {
      enabled = true,
      files = {},
      roots = {},
      command = { "opencode" },
      command_timeout_ms = 2000,
      detect_command = true,
    },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(options)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, options or {})
  return M.options
end

return M
