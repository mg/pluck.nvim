# pluck.nvim

Pluck discovers sessions from pi, Claude Code, and OpenCode—including sessions in custom locations—and presents them newest-first in a Snacks picker. Selecting a session opens its referenced files in a configurable float, tab, or split; choose files with `<Space>` and press `<CR>` to load the selection, or every file when none is selected, into the quickfix list.

## Flow

- Run `:PluckSessions` to open the session picker:

![Selecting a session](assets/screenshot_selecting.png)

- Select a session and select the files with `j`/`k` and `<Space>`. Press `<CR>` to finish.

![Selecting referenced files](assets/screenshot_plucking.png)

- Selected files are in the quickfix list.

![Selected files in quickfix](assets/screenshot_loaded.png)

## Install

Requires Neovim 0.9+, [snacks.nvim](https://github.com/folke/snacks.nvim), and `sqlite3` for OpenCode sessions.

With `vim.pack`:

```lua
vim.pack.add({
  "https://github.com/mg/pluck.nvim",
  "https://github.com/folke/snacks.nvim",
})

require("pluck").setup()
vim.keymap.set("n", "<leader>ap", function()
  require("pluck").pick()
end, { desc = "Pick Pluck Session" })
```

## Configuration

Pass any overrides to `setup()`; the defaults are shown below:

```lua
require("pluck").setup({
  enabled = true,
  include_defaults = true, -- Search the harnesses' standard locations.
  limits = {
    max_depth = 4,         -- Maximum directory traversal depth.
    max_files = 10000,     -- Maximum filesystem entries inspected per harness.
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
  references = {
    -- Optional sqlite_command and command_timeout_ms overrides used when
    -- reading references from OpenCode sessions.
  },
  window = {
    style = "float", -- "float", "tab", "split", or "vsplit"
    width = 0.8,      -- Fraction of the editor, or an absolute column count.
    height = 0.7,     -- Fraction of the editor, or an absolute line count.
    border = "rounded",
  },
  keys = {
    next = "j",
    prev = "k",
    toggle = "<Space>",
    confirm = "<CR>",
    close = { "q", "<Esc>" },
  },
  open_quickfix = true,
  harnesses = {
    pi = {
      enabled = true,
      files = {}, -- Additional exact session files.
      roots = {}, -- Additional directories to search.
    },
    claude = {
      enabled = true,
      files = {},
      roots = {},
    },
    opencode = {
      enabled = true,
      files = {}, -- JSON session files or SQLite databases.
      roots = {},
      command = { "opencode" },
      command_timeout_ms = 2000,
      detect_command = true, -- Detect the database with `opencode db path`.
    },
  },
})
```

Set `include_defaults = false` to search only explicitly configured `files` and
`roots`. `references.sqlite_command` and `references.command_timeout_ms`
inherit their values from `sessions` when omitted.
