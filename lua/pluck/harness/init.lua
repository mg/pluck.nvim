local config = require("pluck.config")
local fs = require("pluck.harness.fs")
local uv = vim.uv or vim.loop

local M = {}

local adapters = {
  pi = require("pluck.harness.pi"),
  claude = require("pluck.harness.claude"),
  opencode = require("pluck.harness.opencode"),
}

local order = { "pi", "claude", "opencode" }

function M.names()
  return vim.deepcopy(order)
end

function M.get(name)
  return adapters[name]
end

---Find session transcript files and stores for the configured agent harnesses.
---@param options? { harnesses?: string[], cwd?: string, include_defaults?: boolean }
---@return { files: table[], warnings: table[] }
function M.find(options)
  options = options or {}
  if config.options.enabled == false then
    return { files = {}, warnings = {} }
  end
  local cwd = fs.expand(options.cwd or uv.cwd(), uv.cwd())
  local selected = options.harnesses or order
  local files = {}
  local warnings = {}
  local seen_harnesses = {}

  for _, name in ipairs(selected) do
    local adapter = adapters[name]
    if not adapter then
      error(("unknown harness: %s"):format(tostring(name)))
    end
    if not seen_harnesses[name] then
      seen_harnesses[name] = true
      local harness_config =
        vim.tbl_deep_extend("force", {}, config.options.harnesses[name] or {}, options[name] or {})
      if harness_config.enabled ~= false then
        local include_defaults = options.include_defaults
        if include_defaults == nil then
          include_defaults = config.options.include_defaults
        end
        local ok, found, adapter_warnings = pcall(adapter.find, harness_config, {
          cwd = cwd,
          include_defaults = include_defaults ~= false,
          limits = config.options.limits,
        })
        if ok then
          vim.list_extend(files, found or {})
          vim.list_extend(warnings, adapter_warnings or {})
        else
          warnings[#warnings + 1] = {
            harness = name,
            message = found,
          }
        end
      end
    end
  end

  table.sort(files, function(a, b)
    if a.harness == b.harness then
      return a.path < b.path
    end
    return a.harness < b.harness
  end)

  return { files = files, warnings = warnings }
end

return M
