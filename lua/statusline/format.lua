-- Bounded statusline component composition policy for Bitty Statusline
-- (bitty-terminal.statusline).
--
-- Pure functions with no host dependency, so the presentation policy is unit
-- testable in plain Lua. The numeric bounds mirror the bundled Rust
-- realization (`bitty` `crates/bitty-runtime/src/statusline.rs`): at most `8`
-- components, `64` characters per component value, and `128` characters total
-- (the host overlay text bound `MAX_OVERLAY_TEXT_LEN`).
--
-- The plugin observes read-only committed state through the accepted semantic
-- snapshot (`bitty.terminal.snapshot`, Plugin API v1 Lua Surface RFC): the
-- title is the snapshot `title`, and the cwd and last exit code come from
-- semantic-zone metadata (`zones[i].metadata.cwd` / `.exit_code`).

local M = {}

M.MAX_COMPONENTS = 8
M.COMPONENT_MAX_CHARS = 64
M.MAX_CHARS = 128
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

-- Latest non-empty `metadata.cwd` scanning semantic zones newest-first.
local function latest_cwd(snapshot)
  local zones = snapshot.zones
  if type(zones) ~= "table" then
    return nil
  end
  for index = #zones, 1, -1 do
    local zone = zones[index]
    local metadata = type(zone) == "table" and zone.metadata or nil
    local cwd = type(metadata) == "table" and metadata.cwd or nil
    if type(cwd) == "string" and cwd ~= "" then
      return cwd
    end
  end
  return nil
end

-- Latest non-nil `metadata.exit_code` scanning semantic zones newest-first.
local function latest_exit(snapshot)
  local zones = snapshot.zones
  if type(zones) ~= "table" then
    return nil
  end
  for index = #zones, 1, -1 do
    local zone = zones[index]
    local metadata = type(zone) == "table" and zone.metadata or nil
    if type(metadata) == "table" and metadata.exit_code ~= nil then
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

-- Components for `snapshot`: `cwd:`, `title:` (from the snapshot title), and
-- `exit:` (from the latest zone exit code). Each value is truncated to the
-- per-component bound; output is bounded to the component count. Component
-- prefixes are intentional and mirror the bundled realization.
function M.components(snapshot, opts)
  snapshot = type(snapshot) == "table" and snapshot or {}
  local value_max = option(opts, "component_max_chars", M.COMPONENT_MAX_CHARS)
  local max_components = option(opts, "max_components", M.MAX_COMPONENTS)
  local comps = {}

  if option(opts, "show_cwd", true) then
    local cwd = latest_cwd(snapshot)
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
    local exit = latest_exit(snapshot)
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
-- empty string (no fallback pollution).
function M.render(snapshot, opts)
  local comps = M.components(snapshot, opts)
  if #comps == 0 then
    return ""
  end
  local separator = option(opts, "separator", M.SEPARATOR)
  local joined = table.concat(comps, separator)
  return truncate(joined, option(opts, "max_chars", M.MAX_CHARS))
end

-- Whether the snapshot carries any observable statusline data.
function M.has_status(snapshot)
  snapshot = type(snapshot) == "table" and snapshot or {}
  if type(snapshot.title) == "string" and snapshot.title ~= "" then
    return true
  end
  return latest_cwd(snapshot) ~= nil or latest_exit(snapshot) ~= nil
end

-- Whether `event_kind` is reactive for statusline. The bundled realization
-- treated cwd/title/focus/bell as reactive; the manifest declares only
-- `terminal.cwd-changed` and `terminal.title-changed` as lazy triggers, so
-- only those are subscribed in v1.
function M.is_reactive_event(event_kind)
  return event_kind == "terminal.cwd-changed"
    or event_kind == "terminal.title-changed"
    or event_kind == "focus.changed"
    or event_kind == "terminal.bell"
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
