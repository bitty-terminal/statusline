-- Formatting/composition policy unit tests for `statusline.format`.

local format = require("statusline.format")

local function zone(metadata)
  return { kind = "output", range = { start_line = 1, end_line = 1 }, metadata = metadata }
end

local function run(context)
  local tap = context.tap

  -- Empty state yields no components, empty render, and no status.
  do
    tap.equal(#format.components({}), 0, "empty snapshot has no components")
    tap.equal(format.render({}), "", "empty snapshot renders empty")
    tap.equal(format.has_status({}), false, "empty snapshot has no status")
  end

  -- cwd and title compose in order.
  do
    local snapshot = {
      title = "hello",
      zones = { zone({ cwd = "/home/user/projects/foo" }) },
    }
    local comps = format.components(snapshot)
    tap.equal(#comps, 2, "cwd and title compose")
    tap.equal(comps[1], "cwd:/home/user/projects/foo", "cwd component first")
    tap.equal(comps[2], "title:hello", "title component second")
    tap.equal(format.has_status(snapshot), true, "snapshot has status")
    local rendered = format.render(snapshot)
    tap.equal(rendered, "cwd:/home/user/projects/foo | title:hello", "render joins with separator")
    tap.ok(format.is_render_bounded(rendered), "render is bounded")
  end

  -- Per-component value is truncated to the bound, multibyte safe.
  do
    local long = string.rep("a", format.COMPONENT_MAX_CHARS + 100)
    local snapshot = { title = long }
    local comps = format.components(snapshot)
    tap.ok(#comps[1] <= format.COMPONENT_MAX_CHARS + #"title:", "truncated component fits prefix plus bound")
    tap.ok(format.is_component_bounded(comps[1]:sub(#"title:" + 1)), "component value is bounded")
    tap.equal(format.is_component_bounded(long), false, "unbounded value is rejected")
    tap.equal(format.is_component_bounded("short"), true, "bounded value is accepted")
    local multi = string.rep("é", format.MAX_CHARS + 20)
    tap.ok(format.is_render_bounded(format.render({ title = multi })), "multibyte render is bounded")
  end

  -- Exit code is taken from the latest zone that carries one.
  do
    local snapshot = {
      zones = {
        zone({ exit_code = 1 }),
        zone({ cwd = "/tmp" }),
        zone({ exit_code = 42 }),
      },
    }
    local comps = format.components(snapshot)
    tap.ok(#comps >= 1, "exit code produces a component")
    tap.equal(comps[#comps], "exit:42", "latest exit code wins")
    tap.ok(format.render(snapshot):find("exit:42", 1, true) ~= nil, "exit code rendered")
  end

  -- One exit-code rule (R28): only numeric exit codes count, for both
  -- `components` and `has_status`; the newest numeric value wins.
  do
    local numeric = { zones = { zone({ exit_code = 0 }) } }
    tap.equal(format.has_status(numeric), true, "numeric exit code is status")
    tap.equal(format.components(numeric)[1], "exit:0", "numeric exit code renders")
    local stringy = { zones = { zone({ exit_code = "1" }) } }
    tap.equal(format.has_status(stringy), false, "non-numeric exit code is not status")
    tap.equal(#format.components(stringy), 0, "non-numeric exit code does not render")
    local mixed = { zones = { zone({ exit_code = 7 }), zone({ exit_code = "1" }) } }
    tap.equal(format.components(mixed)[1], "exit:7", "newest numeric exit code wins")
  end

  -- Component count is bounded.
  do
    local zones = {}
    for index = 1, format.MAX_COMPONENTS + 5 do
      zones[index] = zone({ cwd = "/p" .. index })
    end
    local comps = format.components({ zones = zones })
    tap.ok(#comps <= format.MAX_COMPONENTS, "component count is bounded")
  end

  -- Options narrow or restyle the composition without changing defaults.
  do
    local snapshot = { title = "t", zones = { zone({ cwd = "/c", exit_code = 0 }) } }
    tap.equal(format.render(snapshot, { show_title = false }), "cwd:/c | exit:0", "title can be hidden")
    tap.equal(format.render(snapshot, { show_cwd = false, show_exit = false }), "title:t", "cwd/exit can be hidden")
    tap.equal(format.render(snapshot, { separator = " - " }), "cwd:/c - title:t - exit:0", "separator can change")
    tap.equal(format.render(snapshot, { max_components = 1 }), "cwd:/c", "max_components bounds output")
  end

  -- Numeric option clamps (R13): out-of-range values clamp into the documented
  -- range; non-numbers, NaN, and infinities fail closed to the default.
  do
    local snapshot = { title = "t", zones = { zone({ cwd = "/c", exit_code = 0 }) } }
    local full = "cwd:/c | title:t | exit:0"
    tap.equal(format.render(snapshot, { max_components = 1 }), "cwd:/c", "max_components 1 keeps one component")
    tap.equal(format.render(snapshot, { max_components = 0 }), "cwd:/c", "max_components 0 clamps up to 1")
    tap.equal(format.render(snapshot, { max_components = -3 }), "cwd:/c", "negative max_components clamps to 1")
    tap.equal(format.render(snapshot, { max_components = 1e9 }), full, "huge max_components clamps to 8")
    tap.equal(format.render(snapshot, { max_components = 0 / 0 }), full, "NaN max_components falls back to 8")
    tap.equal(format.render(snapshot, { max_components = math.huge }), full, "inf max_components falls back to 8")
    tap.equal(format.render(snapshot, { max_components = "4" }), full, "non-numeric max_components falls back to 8")

    local long = string.rep("x", format.COMPONENT_MAX_CHARS + 32)
    local function value_len(opts)
      local comp = format.components({ title = long }, opts)[1]
      return #comp - #"title:"
    end
    tap.equal(value_len({ component_max_chars = 10 }), 10, "in-range component_max_chars applies")
    tap.equal(value_len({ component_max_chars = -1 }), format.MIN_COMPONENT_MAX_CHARS, "negative component_max_chars clamps to 8")
    tap.equal(value_len({ component_max_chars = 0 }), format.MIN_COMPONENT_MAX_CHARS, "zero component_max_chars clamps to 8")
    tap.equal(value_len({ component_max_chars = 1e9 }), format.COMPONENT_MAX_CHARS, "huge component_max_chars clamps to 64")
    tap.equal(value_len({ component_max_chars = 0 / 0 }), format.COMPONENT_MAX_CHARS, "NaN component_max_chars falls back to 64")
    tap.equal(value_len({ component_max_chars = math.huge }), format.COMPONENT_MAX_CHARS, "inf component_max_chars falls back to 64")
    tap.equal(value_len({ component_max_chars = "64" }), format.COMPONENT_MAX_CHARS, "non-numeric component_max_chars falls back to 64")
  end

  -- Zone scan cap (R14): only the newest MAX_ZONES zones are inspected; a cwd
  -- older than the window is ignored and truncation is recorded in `stats`.
  do
    local count = format.MAX_ZONES * 4
    local zones = {}
    for index = 1, count do
      zones[index] = zone({ cwd = "/old" .. index })
    end
    local stats = {}
    local comps = format.components({ zones = zones }, nil, stats)
    tap.equal(comps[1], "cwd:/old" .. tostring(count), "newest cwd inside the window wins")
    tap.equal(stats.zones_truncated, true, "truncation recorded for a large zone list")

    local ancient = {}
    for index = 1, count do
      ancient[index] = zone({})
    end
    ancient[1] = zone({ cwd = "/ancient" })
    local ancient_stats = {}
    tap.equal(#format.components({ zones = ancient }, nil, ancient_stats), 0, "cwd older than the window is ignored")
    tap.equal(ancient_stats.zones_truncated, true, "truncation recorded when the cwd is skipped")
    tap.equal(format.has_status({ zones = ancient }), false, "has_status agrees with the bounded scan")

    local boundary = {}
    for index = 1, format.MAX_ZONES do
      boundary[index] = zone({})
    end
    boundary[1] = zone({ cwd = "/edge" })
    local boundary_stats = {}
    tap.equal(format.components({ zones = boundary }, nil, boundary_stats)[1], "cwd:/edge", "window boundary is inclusive")
    tap.equal(boundary_stats.zones_truncated, nil, "no truncation at the boundary")
  end

  -- Bounded work/output with hundreds of zones: the render stays inside every
  -- output bound and the scan stays within the window.
  do
    local zones = {}
    for index = 1, 1000 do
      zones[index] = zone({ cwd = "/p" .. index, exit_code = index })
    end
    local stats = {}
    local snapshot = { title = "t", zones = zones }
    local rendered = format.render(snapshot, nil, stats)
    tap.ok(format.is_render_bounded(rendered), "large-zones render is bounded")
    tap.ok(#format.components(snapshot) <= format.MAX_COMPONENTS, "large-zones component count is bounded")
    tap.equal(stats.zones_truncated, true, "large-zones scan records truncation")
  end

  -- Single reactive rule (R28): an event kind is reactive iff the manifest
  -- declares it and `init.lua` subscribes it via `format.REACTIVE_EVENTS`.
  do
    tap.equal(#format.REACTIVE_EVENTS, 4, "reactive set matches the manifest subscriptions")
    tap.ok(format.is_reactive_event("terminal.cwd-changed"), "cwd-changed reactive")
    tap.ok(format.is_reactive_event("terminal.title-changed"), "title-changed reactive")
    tap.ok(format.is_reactive_event("focus.changed"), "focus.changed reactive")
    tap.ok(format.is_reactive_event("terminal.opened"), "terminal.opened reactive")
    tap.equal(format.is_reactive_event("terminal.bell"), false, "bell is not subscribed and not reactive")
    tap.equal(format.is_reactive_event("intercept.paste"), false, "intercept.paste not reactive")
    tap.equal(format.is_reactive_event("byte-received"), false, "byte-received not reactive")
    tap.equal(format.is_reactive_event("cell-changed"), false, "cell-changed not reactive")
  end
end

return { run = run }
