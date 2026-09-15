-- Bounded statusline component composition policy for Bitty Statusline
-- (bitty-terminal.statusline).
--
-- Pure functions with no host dependency, so the presentation policy is unit
-- testable in plain Lua. The numeric bounds mirror the bundled Rust
-- realization (`bitty` `crates/bitty-runtime/src/statusline.rs`): at most `8`
-- components, `64` characters per component value, and `128` characters total
-- (the host overlay text bound `MAX_OVERLAY_TEXT_LEN`). Options are clamped
-- into those bounds with NaN/infinity rejected (R13), and reads inspect only
-- the newest `MAX_ZONES` semantic zones (R14).
--
-- The plugin observes read-only committed state through the accepted semantic
-- snapshot (`bitty.terminal.snapshot`, Plugin API v1 Lua Surface RFC): the
-- title is the snapshot `title`, and the cwd and last exit code come from
-- semantic-zone metadata (`zones[i].metadata.cwd` / `.exit_code`).

local M = {}

M.MAX_COMPONENTS = 8
M.MIN_COMPONENTS = 1
M.COMPONENT_MAX_CHARS = 64
M.MIN_COMPONENT_MAX_CHARS = 8
M.MAX_CHARS = 128
M.MAX_ZONES = 256
M.SEPARATOR = " | "

-- Count Unicode code points. The restricted plugin VM retains `utf8`; the byte
-- scan is a fallback that never splits a code point.
local function char_count(text)
  if utf8 ~= nil and utf8.len ~= nil then
    local count = utf8.len(text)
    if type(count) == "number" then
      return count
    end
  end
  local count = 0
  local index = 1
  local length = #text
  while index <= length do
    local byte = string.byte(text, index)
    if byte < 0x80 or byte >= 0xC0 then
      count = count + 1
    end
    index = index + 1
  end
  return count
end

-- Truncate `text` to `max` code points without splitting a UTF-8 sequence.
local function char_slice(text, max)
  if max <= 0 then
    return ""
  end
  if char_count(text) <= max then
    return text
  end
  if utf8 ~= nil and utf8.offset ~= nil then
    local offset = utf8.offset(text, max + 1)
    if offset ~= nil then
      return string.sub(text, 1, offset - 1)
    end
  end
  local count = 0
  local index = 1
  local length = #text
  while index <= length do
    local byte = string.byte(text, index)
    if byte < 0x80 or byte >= 0xC0 then
      count = count + 1
      if count > max then
        return string.sub(text, 1, index - 1)
      end
    end
    index = index + 1
  end
  return text
end

M.char_count = char_count

local function truncate(text, max)
  return char_slice(text, max)
end

-- Bounded newest-first zone window (R14): at most `MAX_ZONES` of the newest
-- zones are inspected. When `stats` is a table, skipped older zones are
-- recorded on it as `zones_truncated = true`, so callers can observe the
-- truncation. Returns the zone array and the number of entries in the window.
local function zone_scan(snapshot, stats)
  local zones = snapshot.zones
  if type(zones) ~= "table" then
    return nil, 0
  end
  local count = #zones
  if count > M.MAX_ZONES then
    if type(stats) == "table" then
      stats.zones_truncated = true
    end
    return zones, M.MAX_ZONES
  end
  return zones, count
end

-- Latest non-empty `metadata.cwd` scanning the bounded zone window.
local function latest_cwd(snapshot, stats)
  local zones, scanned = zone_scan(snapshot, stats)
  if zones == nil then
    return nil
  end
  local count = #zones
  for index = count, count - scanned + 1, -1 do
    local zone = zones[index]
    local metadata = type(zone) == "table" and zone.metadata or nil
    local cwd = type(metadata) == "table" and metadata.cwd or nil
    if type(cwd) == "string" and cwd ~= "" then
      return cwd
    end
  end
  return nil
end

-- Latest numeric `metadata.exit_code` scanning the bounded zone window. One
-- rule for exit status (R28): only numbers count, so `components` and
-- `has_status` agree on when an exit component exists; non-numeric values are
-- ignored and the scan continues to the next older zone.
local function latest_exit(snapshot, stats)
  local zones, scanned = zone_scan(snapshot, stats)
  if zones == nil then
    return nil
  end
  local count = #zones
  for index = count, count - scanned + 1, -1 do
    local zone = zones[index]
    local metadata = type(zone) == "table" and zone.metadata or nil
    if type(metadata) == "table" and type(metadata.exit_code) == "number" then
      return metadata.exit_code
    end
  end
  return nil
end

local function option(opts, name, default)
  if type(opts) == "table" and opts[name] ~= nil then
    return opts[name]
  end
  return default
end

-- Numeric option policy (R13): values outside the documented range are clamped
-- into it; non-numbers, NaN, and infinities fail closed to the default. The
-- result is an integer so callers can slice and loop safely.
local function bounded_number(opts, name, default, minimum, maximum)
  local value = option(opts, name, default)
  if
    type(value) ~= "number"
    or value ~= value
    or value == math.huge
    or value == -math.huge
  then
    return default
  end
  value = math.floor(value)
  if value < minimum then
    return minimum
  end
  if value > maximum then
    return maximum
  end
  return value
end

-- Components for `snapshot`: `cwd:`, `title:` (from the snapshot title), and
-- `exit:` (from the latest zone exit code). Each value is truncated to the
-- per-component bound; output is bounded to the component count. Component
-- prefixes are intentional and mirror the bundled realization. `stats`, when
-- provided, receives truncation records from the zone scan.
function M.components(snapshot, opts, stats)
  snapshot = type(snapshot) == "table" and snapshot or {}
  local value_max = bounded_number(
    opts,
    "component_max_chars",
    M.COMPONENT_MAX_CHARS,
    M.MIN_COMPONENT_MAX_CHARS,
    M.COMPONENT_MAX_CHARS
  )
  local max_components = bounded_number(
    opts,
    "max_components",
    M.MAX_COMPONENTS,
    M.MIN_COMPONENTS,
    M.MAX_COMPONENTS
  )
  local comps = {}

  if option(opts, "show_cwd", true) then
    local cwd = latest_cwd(snapshot, stats)
    if type(cwd) == "string" and cwd ~= "" then
      comps[#comps + 1] = "cwd:" .. truncate(cwd, value_max)
    end
  end

  if option(opts, "show_title", true) then
    local title = snapshot.title
    if type(title) == "string" and title ~= "" then
      comps[#comps + 1] = "title:" .. truncate(title, value_max)
    end
  end

  if option(opts, "show_exit", true) then
    local exit = latest_exit(snapshot, stats)
    if type(exit) == "number" then
      comps[#comps + 1] = "exit:" .. tostring(exit)
    end
  end

  if #comps > max_components then
    local bounded = {}
    for index = 1, max_components do
      bounded[index] = comps[index]
    end
    comps = bounded
  end
  return comps
end

-- Rendered statusline text: components joined with the separator and bounded
-- to the total bound at a code-point boundary. An empty snapshot yields an
-- empty string (no fallback pollution). `stats` is forwarded to the zone scan.
function M.render(snapshot, opts, stats)
  local comps = M.components(snapshot, opts, stats)
  if #comps == 0 then
    return ""
  end
  local separator = option(opts, "separator", M.SEPARATOR)
  local joined = table.concat(comps, separator)
  return truncate(joined, option(opts, "max_chars", M.MAX_CHARS))
end

-- Whether the snapshot carries any observable statusline data. The exit
-- criterion is the same numeric-only rule `components` applies (R28), so a
-- non-numeric `exit_code` is not status and yields no component.
function M.has_status(snapshot)
  snapshot = type(snapshot) == "table" and snapshot or {}
  if type(snapshot.title) == "string" and snapshot.title ~= "" then
    return true
  end
  return latest_cwd(snapshot) ~= nil or latest_exit(snapshot) ~= nil
end

-- Single reactive rule (R28): an event kind is reactive iff this plugin
-- subscribes to it. `REACTIVE_EVENTS` is that subscription set and mirrors
-- `bitty-plugin.toml` `lazy.events` exactly; `init.lua` subscribes from this
-- list through `is_reactive_event`, so the manifest, the predicate, and the
-- subscriptions cannot drift. `terminal.bell` belongs to the closed v1 event
-- set but is not subscribed in v1, so it is not reactive here.
M.REACTIVE_EVENTS = {
  "terminal.cwd-changed",
  "terminal.title-changed",
  "focus.changed",
  "terminal.opened",
}

function M.is_reactive_event(event_kind)
  for _, kind in ipairs(M.REACTIVE_EVENTS) do
    if kind == event_kind then
      return true
    end
  end
  return false
end

-- Whether `text` fits the total bound.
function M.is_render_bounded(text)
  return type(text) == "string" and char_count(text) <= M.MAX_CHARS
end

-- Whether `text` fits the per-component bound.
function M.is_component_bounded(text)
  return type(text) == "string" and char_count(text) <= M.COMPONENT_MAX_CHARS
end

return M
