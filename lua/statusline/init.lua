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
  -- Errors surface only to `refresh`, which contains them: a denied
  -- `terminal.semantic-read` keeps the last-known-good rendering instead of
  -- blanking the statusline (H-SL-01 / R12).
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

-- Last successfully composed component list, and the keep-alive rule
-- (H-SL-01 / R12): `refresh` contains every read/compose/update failure. On
-- failure the mounted block is left untouched (so the slot keeps its
-- last-known-good output) and nothing propagates to the event dispatcher.
local last_good = nil

-- Recompute the bounded components from the semantic snapshot and update the
-- mounted block. Returns the bounded component list for callers/tests, or the
-- last-known-good list when the refresh fails.
local function refresh()
  local opts = options()
  local ok, components = pcall(function()
    return format.components(snapshot(), opts)
  end)
  if not ok then
    return last_good
  end
  if block ~= nil then
    local updated = pcall(function()
      return bitty.ui.update(block, scene.row(components, opts.separator))
    end)
    if not updated then
      return last_good
    end
  end
  last_good = components
  return components
end

M.refresh = refresh

-- Reactive recomposition on the manifest-declared observation events. The
-- accepted event contract marks cwd, title, and focus changes as coalescable:
-- the host collapses rapid bursts to the latest value before delivery, so
-- plugin-side debouncing is unnecessary; `terminal.opened` is a one-shot
-- observation. Each delivered event refreshes once and the one-shot timer
-- surface is registration-window-only, so handlers refresh directly.
-- Refresh errors are contained, so a denied read or update never propagates to
-- the dispatcher (H-SL-01 / R12).
local function on_event(_event)
  pcall(refresh)
end

-- The subscription list is the single reactive rule (R28): the predicate and
-- the subscribed kinds cannot disagree because both come from
-- `format.REACTIVE_EVENTS`, which mirrors `bitty-plugin.toml` `lazy.events`.
for _, event_kind in ipairs(format.REACTIVE_EVENTS) do
  if format.is_reactive_event(event_kind) then
    bitty.events.subscribe(event_kind, on_event)
  end
end

-- Render once at activation (M-SL-02) so the statusline shows committed state
-- immediately instead of staying blank until the first event.
refresh()

return M
