# pluck.nvim

A Neovim plugin written in Lua.

## Requirements

- Neovim 0.9+

## Installation

### lazy.nvim

```lua
{
  "YOUR_USERNAME/pluck.nvim",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "YOUR_USERNAME/pluck.nvim",
  config = function()
    require("pluck").setup()
  end,
}
```

## Configuration

The defaults discover sessions from each harness's standard location, environment
variables, and (where available) harness configuration or CLI:

```lua
require("pluck").setup({
  include_defaults = true,
  harnesses = {
    pi = { files = {}, roots = {} },
    claude = { files = {}, roots = {} },
    opencode = {
      files = {},
      roots = {},
      command = { "opencode" },
      detect_command = true,
    },
  },
})
```

Use `files` and `roots` to include sessions stored in non-standard locations.
Configured roots are additive unless `include_defaults` is disabled. Discovery is
bounded and does not crawl the entire home directory.

```lua
local result = require("pluck").find_sessions({
  harnesses = { "pi", "claude", "opencode" },
})

for _, session_file in ipairs(result.files) do
  print(session_file.harness, session_file.kind, session_file.path)
end
```

Each result has `harness`, `path`, `kind`, `source`, and `root` fields. `kind` is
`transcript` for JSON/JSONL files and `database` for current OpenCode SQLite
stores. Recoverable discovery problems are returned in `result.warnings`.

## Session list and pickers

Load normalized sessions ordered from newest to oldest:

```lua
local result = require("pluck").list_sessions()
for _, session in ipairs(result.sessions) do
  print(session.icon, session.harness, session.title, session.cwd)
end
```

`picker_items()` exposes generic picker-friendly entries while preserving the
normalized session under each item's `session` field:

```lua
local items, warnings = require("pluck").picker_items()
```

With [snacks.nvim](https://github.com/folke/snacks.nvim), run
`:PluckSessions` or:

```lua
require("pluck").pick({
  on_select = function(session)
    print(vim.inspect(session))
  end,
})
```

Without `on_select`, confirming emits the `User PluckSessionSelected`
autocommand with the session in `event.data`. Harness icons are configurable:

```lua
require("pluck").setup({
  sessions = {
    icons = {
      pi = "π",
      claude = "󰚩",
      opencode = "󰘦",
    },
  },
})
```

Reading current OpenCode databases requires the `sqlite3` executable. Override
it with `sessions.sqlite_command` when necessary.

Detected locations include:

- **pi:** `PI_SESSION_FILE`, `PI_CODING_AGENT_SESSION_DIR`, `sessionDir` in
  global/project settings, and `$PI_CODING_AGENT_DIR/sessions`.
- **Claude Code:** `$CLAUDE_CONFIG_DIR/projects`, an existing XDG config root,
  and `~/.claude/projects`.
- **OpenCode:** `OPENCODE_DB`, `opencode db path`, and
  `$XDG_DATA_HOME/opencode`, including legacy JSON stores.

## Health check

Run `:checkhealth pluck` or `:PluckHealth`.

## Development

Format the Lua sources with [StyLua](https://github.com/JohnnyMorganz/StyLua):

```sh
stylua lua plugin
```

## License

MIT
