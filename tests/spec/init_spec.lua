-- Entry-point behavior tests for `statusline.init` against the mock host.

local MockHost = require("support.mock_host")
local format = require("statusline.format")

local CWD_EVENT = "terminal.cwd-changed"
local TITLE_EVENT = "terminal.title-changed"
local FOCUS_EVENT = "focus.changed"
local OPENED_EVENT = "terminal.opened"
local EVENT_KINDS = { CWD_EVENT, TITLE_EVENT, FOCUS_EVENT, OPENED_EVENT }

local function activate(host)
  _G.bitty = host.bitty
  package.loaded["statusline.init"] = nil
  package.loaded["statusline.format"] = nil
  package.loaded["statusline.scene"] = nil
  return require("statusline.init")
end

local function with_grants(options)
  options.grants = options.grants or { "terminal.semantic-read", "ui.rich" }
  options.events = options.events or EVENT_KINDS
  return MockHost.new(options)
end

local function run(context)
  local tap = context.tap

  -- Manifest/subscription drift guard (R28): `format.REACTIVE_EVENTS` is the
  -- single reactive rule and must list exactly the kinds declared in
  -- `bitty-plugin.toml` `lazy.events`. Parsing is a line scan scoped to the
  -- `[lazy]` section, so the test needs no TOML dependency.
  do
    local path = context.root .. "/bitty-plugin.toml"
    local file = assert(io.open(path, "r"))
    local manifest = file:read("*a")
    file:close()
    local in_lazy = false
    local declared = {}
    for line in manifest:gmatch("[^\n]+") do
      if line:match("^%[") then
        in_lazy = line:match("^%[lazy%]") ~= nil
      elseif in_lazy then
        for name in line:gmatch('"([^"]+)"') do
          declared[name] = true
        end
      end
    end
    for _, kind in ipairs(format.REACTIVE_EVENTS) do
      tap.ok(declared[kind] == true, "manifest lazy.events declares " .. kind)
      declared[kind] = nil
    end
    for kind in pairs(declared) do
      tap.ok(false, "manifest lazy.events has an undeclared kind " .. kind)
    end
  end

  -- Activation mounts the block, subscribes every declared event, and renders
  -- once so the statusline is populated before the first event (M-SL-02).
  -- Each delivered event then refreshes from the current snapshot exactly once
  -- (M-SL-03); bursts are coalesced by the host before delivery, so the plugin
  -- adds no debounce.
  do
    local host = with_grants({
      snapshot = {
        title = "hello",
        zones = { { kind = "output", metadata = { cwd = "/home/user" } } },
      },
    })
    activate(host)
    tap.equal(#host.subscriptions, #EVENT_KINDS, "every declared event subscribed")
    for index, kind in ipairs(EVENT_KINDS) do
      tap.equal(host.subscriptions[index].kind, kind, kind .. " subscribed in order")
    end
    tap.equal(#host.blocks, 1, "statusline block mounted at activation")
    tap.equal(host.blocks[1].slot, "statusline", "block mounted in the statusline slot")
    tap.equal(host.blocks[1].component.kind, "Row", "mounted block is a Row")
    tap.equal(host.updates, 1, "activation renders exactly once")
    tap.equal(
      host.blocks[1].component.children[1].text,
      "cwd:/home/user",
      "activation render carries the cwd fragment"
    )

    local cases = {
      { kind = CWD_EVENT, payload = { cwd = "/var", terminal_id = 1 }, title = "a", cwd = "/var" },
      { kind = TITLE_EVENT, payload = { title = "b", terminal_id = 1 }, title = "b", cwd = "/var" },
      -- focus.changed carries `view_id`, not `terminal_id`.
      { kind = FOCUS_EVENT, payload = { view_id = 2 }, title = "c", cwd = "/var" },
      { kind = OPENED_EVENT, payload = { terminal_id = 3 }, title = "d", cwd = "/var" },
    }
    local snapshots = host.snapshots
    local updates = host.updates
    for _, case in ipairs(cases) do
      host.snapshot = {
        title = case.title,
        zones = { { kind = "output", metadata = { cwd = case.cwd } } },
      }
      tap.equal(host:publish(case.kind, case.payload), 1, case.kind .. " has exactly one subscription")
      tap.equal(host.updates, updates + 1, case.kind .. " refreshes and updates exactly once")
      tap.equal(host.snapshots, snapshots + 1, case.kind .. " reads the semantic snapshot once")
      snapshots = snapshots + 1
      updates = updates + 1
      local row = host.blocks[1].component
      tap.equal(row.kind, "Row", case.kind .. " render is a Row")
      tap.equal(row.children[1].text, "cwd:" .. case.cwd, case.kind .. " render carries the current cwd")
      tap.equal(row.children[#row.children].text, "title:" .. case.title, case.kind .. " render carries the current title")
    end
    tap.equal(host.updates, updates, "no extra renders across the event set")
  end

  -- Snapshot failures keep the last-known-good block and never reach the
  -- dispatcher (H-SL-01 / R12).
  do
    local host = with_grants({ snapshot = { title = "hello" } })
    activate(host)
    tap.equal(host.blocks[1].component.children[1].text, "title:hello", "initial render")
    host.grants["terminal.semantic-read"] = nil
    host.snapshot = { title = "world" }
    local before = host.updates
    tap.equal(host:publish(CWD_EVENT, {}), 1, "failed refresh does not propagate to the dispatcher")
    tap.equal(host.updates, before, "failed refresh performs no update")
    tap.equal(
      host.blocks[1].component.children[1].text,
      "title:hello",
      "last-known-good output kept after failure"
    )
    host.grants["terminal.semantic-read"] = true
    tap.equal(host:publish(CWD_EVENT, {}), 1, "recovered event is delivered")
    tap.equal(host.updates, before + 1, "recovered refresh updates the block")
    tap.equal(host.blocks[1].component.children[1].text, "title:world", "recovered render composed")
  end

  -- A rejected `ui.update` (revoked `ui.rich`) keeps the last-known-good block
  -- and recovers when the grant returns (H-SL-01 / R12).
  do
    local host = with_grants({ snapshot = { title = "hello" } })
    activate(host)
    tap.equal(host.blocks[1].component.children[1].text, "title:hello", "initial render")
    host.grants["ui.rich"] = nil
    host.snapshot = { title = "world" }
    local before = host.updates
    tap.equal(host:publish(CWD_EVENT, {}), 1, "failed ui.update does not propagate to the dispatcher")
    tap.equal(host.updates, before, "failed ui.update performs no update")
    tap.equal(
      host.blocks[1].component.children[1].text,
      "title:hello",
      "last-known-good output kept after ui.update rejection"
    )
    host.grants["ui.rich"] = true
    tap.equal(host:publish(CWD_EVENT, {}), 1, "recovered event is delivered")
    tap.equal(host.updates, before + 1, "recovered refresh updates the block")
    tap.equal(host.blocks[1].component.children[1].text, "title:world", "recovered render composed")
  end

  -- Activation-time refresh with `terminal.semantic-read` denied succeeds:
  -- the mount still happens, the block stays empty, and events are delivered
  -- without crashing or propagating.
  do
    local host = MockHost.new({
      grants = { "ui.rich" },
      events = EVENT_KINDS,
      snapshot = { title = "hidden" },
    })
    local ok, module = pcall(activate, host)
    tap.ok(ok, "activation succeeds without terminal.semantic-read")
    tap.equal(type(module), "table", "activation returns the module table")
    tap.equal(#host.blocks, 1, "block still mounted")
    tap.equal(#host.blocks[1].component.children, 0, "block stays empty after the denied activation read")
    local before = host.updates
    tap.equal(host:publish(CWD_EVENT, {}), 1, "denied-read event does not propagate")
    tap.equal(host.updates, before, "denied reads never update the block")
    tap.equal(#host.blocks[1].component.children, 0, "block stays empty after a denied event read")
  end

  -- Settings adapt the composition without changing defaults.
  do
    local host = with_grants({
      settings = { show_title = false, separator = " - " },
      snapshot = {
        title = "ignored",
        zones = { { kind = "output", metadata = { cwd = "/c", exit_code = 0 } } },
      },
    })
    activate(host)
    host:publish(CWD_EVENT, {})
    local row = host.blocks[1].component
    tap.equal(row.children[1].text, "cwd:/c", "settings hide the title")
    tap.ok(#row.children >= 3, "separator setting keeps fragments distinct")
    tap.equal(row.children[2].text, " - ", "settings change the separator")
  end

  -- A host bridge without `bitty.ui` still activates and observes; it presents
  -- no block (accepted host-bridge gap).
  do
    local host = with_grants({
      snapshot = { title = "t", zones = { { kind = "output", metadata = { cwd = "/c" } } } },
    })
    host.bitty.ui = nil
    activate(host)
    tap.equal(#host.subscriptions, #EVENT_KINDS, "degraded mode subscribes declared events")
    tap.equal(#host.blocks, 0, "degraded mode mounts no block")
    local before = host.snapshots
    tap.equal(host:publish(CWD_EVENT, {}), 1, "degraded mode delivers events")
    tap.equal(host.snapshots, before + 1, "degraded mode still reads the semantic snapshot")
  end

  -- Undeclared event fails closed at activation.
  do
    local host = MockHost.new({
      grants = { "terminal.semantic-read", "ui.rich" },
      events = {},
    })
    local ok, err = pcall(activate, host)
    tap.ok(not ok, "undeclared event fails activation")
    tap.equal(type(err) == "table" and err.code or nil, "E_EVENT_UNDECLARED", "undeclared event code")
  end

  -- Missing ui.rich fails closed at activation (mount is capability-gated).
  do
    local host = MockHost.new({
      grants = { "terminal.semantic-read" },
      events = EVENT_KINDS,
    })
    local ok, err = pcall(activate, host)
    tap.ok(not ok, "missing ui.rich fails activation")
    tap.equal(type(err) == "table" and err.code or nil, "E_CAPABILITY_DENIED", "denied ui.rich code")
  end

  -- A host without a terminal surface degrades to no components (no error).
  do
    local host = with_grants({})
    host.bitty.terminal = nil
    local module = activate(host)
    local components = module.refresh()
    tap.equal(#components, 0, "no terminal surface yields no components")
    tap.equal(#host.blocks, 1, "block still mounted")
  end
end

return { run = run }
