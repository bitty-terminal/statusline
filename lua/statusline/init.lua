-- Entry point for Bitty Statusline (bitty-terminal.statusline).
--
-- The host evaluates this file once per plugin activation and owns every
-- resource created here for the lifetime of that generation. Registration
-- calls (`bitty.events.subscribe`, `bitty.ui.mount`) are valid only while this
-- file executes.
--
-- Accepted surface: Plugin API v1 Lua Surface RFC (ADR 0009). Capabilities
-- requested in `bitty-plugin.toml` are `terminal.semantic-read` (read-only
-- semantic snapshot) and `ui.rich` (declarative status-component mount). The
-- identifiers are unchanged from the bundled Rust realization
-- (`bitty-terminal.statusline`); the split changes no identity.
--
-- This plugin owns the statusline presentation only. The workspaceline claim
-- (ordering, exclusive claim, close policy) and workspace lifecycle stay
-- bundled in `bitty`; shell integration stays bundled and remains the
-- OSC 7/133 semantic-zone provider the statusline observes.
--
-- v1 adapter: the accepted surface exposes no status-component provider
-- (`StatusProvider`/`status.component`; the Plugin Reuse and Provider Ecology
-- RFC is draft/post-1.0), so the plugin composes its fragments into one
-- `Row` mounted in the `statusline` slot. Host statusline support
-- (`bitty.ui.mount`/`update`) is not yet in the `bitty` Lua bridge; the plugin
-- still observes snapshots and degrades to no visible block until it lands.
-- See the README "Known gaps" section.

local format = require("statusline.format")
local scene = require("statusline.scene")

local M = {}

M.SETTINGS = {
  separator = "separator",
  show_cwd = "show_cwd",
  show_title = "show_title",
  show_exit = "show_exit",
  max_components = "max_components",
  component_max_chars = "component_max_chars",
}

local function setting(key)
  if bitty.settings == nil or type(bitty.settings.get) ~= "function" then
    return nil
  end
  local ok, value = pcall(bitty.settings.get, key)
  if ok then
    return value
  end
  return nil
end

local function options()
  local opts = {}
  local separator = setting(M.SETTINGS.separator)
  if type(separator) == "string" then
    opts.separator = separator
  end
  for _, key in ipairs({ "show_cwd", "show_title", "show_exit" }) do
    local value = setting(key)
    if type(value) == "boolean" then
      opts[key] = value
    end
  end
  local max_components = setting(M.SETTINGS.max_components)
  if type(max_components) == "number" then
    opts.max_components = max_components
  end
  local component_max_chars = setting(M.SETTINGS.component_max_chars)
  if type(component_max_chars) == "number" then
    opts.component_max_chars = component_max_chars
  end
  return opts
end

local function snapshot()
  if bitty.terminal == nil or type(bitty.terminal.snapshot) ~= "function" then
    return {}
  end
  -- Errors propagate: a denied `terminal.semantic-read` must fail closed rather
  -- than silently render an empty statusline.
  local value = bitty.terminal.snapshot({ scope = "semantic" })
  if type(value) == "table" then
    return value
  end
  return {}
end

-- The statusline block is mounted once during activation because `ui.mount` is
-- a registration-time call; events update it. When the host bridge does not
-- expose `bitty.ui`, the plugin observes snapshots but presents no block.
local block = nil
if bitty.ui ~= nil and type(bitty.ui.mount) == "function" then
  block = bitty.ui.mount("statusline", scene.empty())
end

-- Recompute the bounded components from the semantic snapshot and update the
-- mounted block. Returns the bounded component list for callers/tests.
local function refresh()
  local opts = options()
  local components = format.components(snapshot(), opts)
  if block ~= nil then
    bitty.ui.update(block, scene.row(components, opts.separator))
  end
  return components
end

M.refresh = refresh

-- Reactive recomposition on the manifest-declared observation events.
bitty.events.subscribe("terminal.cwd-changed", function(_event)
  refresh()
end)

bitty.events.subscribe("terminal.title-changed", function(_event)
  refresh()
end)

return M
