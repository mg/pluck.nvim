local function assert_equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(
      (message or "values differ")
        .. "\nexpected: "
        .. vim.inspect(expected)
        .. "\nactual: "
        .. vim.inspect(actual)
    )
  end
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/pi/nested", "p")
vim.fn.mkdir(root .. "/claude/projects/custom", "p")
vim.fn.mkdir(root .. "/opencode/storage/session/project", "p")

local pi_file = root .. "/pi/nested/pi-session.jsonl"
local claude_file = root .. "/claude/projects/custom/claude-session.jsonl"
local opencode_file = root .. "/opencode/storage/session/project/opencode-session.json"
local opencode_db = root .. "/opencode/custom.db"

vim.fn.writefile({
  [[{"type":"session","id":"pi-test","cwd":"/tmp/pi"}]],
  [[{"type":"message","timestamp":"2025-01-01T00:03:00Z","message":{"content":[{"type":"toolCall","name":"read","arguments":{"path":"a.lua"}}]}}]],
  [[{"type":"message","timestamp":"2025-01-01T00:01:00Z","message":{"content":[{"type":"toolCall","name":"edit","arguments":{"path":"b.lua"}}]}}]],
  [[{"type":"message","timestamp":"2025-01-01T00:02:00Z","message":{"content":[{"type":"toolCall","name":"read","arguments":{"path":"./a.lua"}}]}}]],
}, pi_file)
vim.fn.writefile({
  [[{"sessionId":"claude-test","slug":"claude-title","cwd":"/tmp/claude","timestamp":"2025-01-01T00:00:00Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"lib/test.lua"}}]}}]],
}, claude_file)
vim.fn.writefile({ [[{"id":"opencode-test","title":"opencode-title"}]] }, opencode_file)
vim.fn.writefile({ "sqlite fixture placeholder" }, opencode_db)
local uv = vim.uv or vim.loop
uv.fs_utime(pi_file, 100, 100)
uv.fs_utime(claude_file, 200, 200)
uv.fs_utime(opencode_file, 300, 300)

require("pluck").setup({
  include_defaults = false,
  harnesses = {
    pi = { files = { pi_file, pi_file }, roots = { root .. "/pi" } },
    claude = { roots = { root .. "/claude" } },
    opencode = {
      files = { opencode_db },
      roots = { root .. "/opencode" },
      detect_command = false,
    },
  },
})

local result = require("pluck").find_sessions()
assert_equal(#result.files, 4, "all non-standard session stores should be found")
assert_equal(#result.warnings, 0)

local found = {}
for _, file in ipairs(result.files) do
  found[file.path] = file
end
assert_equal(found[pi_file].harness, "pi")
assert_equal(found[claude_file].harness, "claude")
assert_equal(found[opencode_file].kind, "transcript")
assert_equal(found[opencode_db].kind, "database")

local listed = require("pluck").list_sessions()
assert_equal(#listed.sessions, 3)
assert_equal(listed.sessions[1].id, "opencode-test", "sessions should be newest first")
assert_equal(listed.sessions[1].icon, "󰘦")
assert_equal(listed.sessions[2].id, "claude-test")
assert_equal(listed.sessions[3].id, "pi-test")
local picker_items = require("pluck").picker_items()
assert_equal(picker_items[1].session.id, "opencode-test")
assert_equal(picker_items[1].idx, 1)

local selected
_G.Snacks = {
  picker = {
    pick = function(opts)
      return opts
    end,
  },
}
local picker = require("pluck").pick({
  on_select = function(session)
    selected = session
  end,
})
assert_equal(picker.items[1].session.id, "opencode-test")
picker.confirm({ close = function() end }, picker.items[1])
assert_equal(selected.id, "opencode-test")
_G.Snacks = nil

local pi_session
for _, session in ipairs(listed.sessions) do
  if session.id == "pi-test" then
    pi_session = session
  end
end
local references = require("pluck").list_references(pi_session)
assert_equal(#references.references, 2)
assert_equal(references.references[1].path, "/tmp/pi/a.lua")
assert_equal(references.references[2].path, "/tmp/pi/b.lua")

local claude_session
for _, session in ipairs(listed.sessions) do
  if session.id == "claude-test" then
    claude_session = session
  end
end
local claude_references = require("pluck").list_references(claude_session)
assert_equal(claude_references.references[1].path, "/tmp/claude/lib/test.lua")

if vim.fn.executable("sqlite3") == 1 then
  local reference_db = root .. "/references.db"
  local part = vim.json
    .encode({
      type = "tool",
      tool = "read",
      state = { input = { filePath = "src/quoted.lua" } },
    })
    :gsub("'", "''")
  local sql = table.concat({
    "create table message(id text, session_id text, time_created integer);",
    "create table part(id text, message_id text, time_created integer, data text);",
    "insert into message values('m1','odd''id',1);",
    ("insert into part values('p1','m1',2,'%s');"):format(part),
  }, " ")
  assert_equal(vim.fn.system({ "sqlite3", reference_db, sql }), "")
  local open_references = require("pluck").list_references({
    id = "odd'id",
    harness = "opencode",
    kind = "database",
    path = reference_db,
    cwd = "/tmp/open",
  })
  assert_equal(open_references.references[1].path, "/tmp/open/src/quoted.lua")
end

local selector = require("pluck").open_session(pi_session, {
  window = { style = "float", width = 50, height = 10 },
  open_quickfix = false,
})
selector.confirm()
local quickfix = vim.fn.getqflist()
assert_equal(#quickfix, 2, "confirming without selections should load every reference")

local selected_selector = require("pluck").open_session(pi_session, {
  window = { style = "float", width = 50, height = 10 },
  open_quickfix = false,
})
selected_selector.selected[2] = true
selected_selector.confirm()
assert_equal(#vim.fn.getqflist(), 1, "only selected references should be loaded")

local pi_only = require("pluck").find_sessions({ harnesses = { "pi" } })
assert_equal(#pi_only.files, 1)
assert_equal(pi_only.files[1].path, pi_file)

local ok = pcall(require("pluck.harness").find, { harnesses = { "missing" } })
assert_equal(ok, false, "unknown harnesses should be rejected")

-- pi resolves relative global and trusted project sessionDir values from their
-- respective configuration directories.
local agent_dir = root .. "/agent"
local project_config = root .. "/.pi"
vim.fn.mkdir(agent_dir .. "/global-sessions", "p")
vim.fn.mkdir(project_config .. "/project-sessions", "p")
vim.fn.writefile({ [[{"sessionDir":"global-sessions"}]] }, agent_dir .. "/settings.json")
vim.fn.writefile({ vim.json.encode({ [root] = true }) }, agent_dir .. "/trust.json")
vim.fn.writefile({ [[{"sessionDir":"project-sessions"}]] }, project_config .. "/settings.json")
local global_session = agent_dir .. "/global-sessions/global.jsonl"
local project_session = project_config .. "/project-sessions/project.jsonl"
vim.fn.writefile({ "{}" }, global_session)
vim.fn.writefile({ "{}" }, project_session)
local previous_agent_dir = vim.env.PI_CODING_AGENT_DIR
vim.env.PI_CODING_AGENT_DIR = agent_dir
require("pluck").setup({
  harnesses = {
    pi = { files = {}, roots = {} },
    claude = { enabled = false },
    opencode = { enabled = false },
  },
})
local settings_result = require("pluck").find_sessions({ cwd = root })
local settings_paths = {}
for _, file in ipairs(settings_result.files) do
  settings_paths[file.path] = true
end
assert_equal(settings_paths[global_session], true)
assert_equal(settings_paths[project_session], true)
vim.env.PI_CODING_AGENT_DIR = previous_agent_dir

vim.fn.delete(root, "rf")
print("pluck tests passed")
