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

  -- Reactive events: statusline reacts to observation events only.
  do
    tap.ok(format.is_reactive_event("terminal.cwd-changed"), "cwd-changed reactive")
    tap.ok(format.is_reactive_event("terminal.title-changed"), "title-changed reactive")
    tap.ok(format.is_reactive_event("focus.changed"), "focus.changed reactive")
    tap.ok(format.is_reactive_event("terminal.bell"), "bell reactive")
    tap.equal(format.is_reactive_event("intercept.paste"), false, "intercept.paste not reactive")
    tap.equal(format.is_reactive_event("byte-received"), false, "byte-received not reactive")
    tap.equal(format.is_reactive_event("cell-changed"), false, "cell-changed not reactive")
  end
end

return { run = run }
