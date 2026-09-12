local M = {}

function M.check()
  vim.health.start("pluck")

  local version = vim.version()
  if version.major > 0 or version.minor >= 9 then
    vim.health.ok("Neovim version is supported")
  else
    vim.health.error("Neovim 0.9 or newer is required")
  end
end

return M
