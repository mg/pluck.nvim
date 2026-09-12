if vim.g.loaded_pluck == 1 then
  return
end
vim.g.loaded_pluck = 1

vim.api.nvim_create_user_command("PluckHealth", function()
  vim.cmd.checkhealth("pluck")
end, {
  desc = "Run pluck health checks",
})

vim.api.nvim_create_user_command("PluckSessions", function()
  local ok, err = pcall(require("pluck").pick)
  if not ok then
    vim.notify(err, vim.log.levels.ERROR, { title = "pluck.nvim" })
  end
end, {
  desc = "Pick an agent session",
})
