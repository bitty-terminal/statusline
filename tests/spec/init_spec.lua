-- Entry-point behavior tests for `statusline.init` against the mock host.

local MockHost = require("support.mock_host")

local PLUGIN_ID = "bitty-terminal.statusline"
local CWD_EVENT = "terminal.cwd-changed"
local TITLE_EVENT = "terminal.title-changed"

local function activate(host)
  _G.bitty = host.bitty
  package.loaded["statusline.init"] = nil
  package.loaded["statusline.format"] = nil
  package.loaded["statusline.scene"] = nil
  return require("statusline.init")
end

local function with_grants(options)
  options.grants = options.grants or { "terminal.semantic-read", "ui.rich" }
  options.events = options.events or { CWD_EVENT, TITLE_EVENT }
  return MockHost.new(options)
end

local function run(context)
  local tap = context.tap

  -- Activation subscribes the declared observation events and mounts the
  -- statusline block.
  do
    local host = with_grants({
      snapshot = {
        title = "hello",
        zones = { { kind = "output", metadata = { cwd = "/home/user" } } },
      },
    })
    activate(host)
    tap.equal(#host.subscriptions, 2, "two declared events subscribed")
    tap.equal(host.subscriptions[1].kind, CWD_EVENT, "cwd-changed subscribed")
    tap.equal(host.subscriptions[2].kind, TITLE_EVENT, "title-changed subscribed")
    tap.equal(#host.blocks, 1, "statusline block mounted at activation")
    tap.equal(host.blocks[1].slot, "statusline", "block mounted in the statusline slot")
    tap.equal(host.blocks[1].component.kind, "Row", "mounted block is a Row")
    tap.equal(#host.blocks[1].component.children, 0, "mounted block starts empty")

    -- A cwd-changed event recomposes the block from the semantic snapshot.
    local before = host.updates
    host:publish(CWD_EVENT, { cwd = "/home/user", terminal_id = 1 })
    tap.ok(host.updates > before, "cwd-changed refreshes the block")
    tap.ok(host.snapshots >= 1, "refresh reads the semantic snapshot")
    local row = host.blocks[1].component
    tap.equal(row.kind, "Row", "refreshed block is a Row")
    tap.ok(#row.children >= 3, "refreshed block carries cwd and title fragments")
    tap.equal(row.children[1].text, "cwd:/home/user", "cwd fragment first")
  end

  -- Title changes refresh too.
  do
    local host = with_grants({ snapshot = { title = "t" } })
    activate(host)
    local before = host.updates
    host:publish(TITLE_EVENT, { title = "t", terminal_id = 1 })
    tap.ok(host.updates > before, "title-changed refreshes the block")
    tap.equal(host.blocks[1].component.children[1].text, "title:t", "title fragment composed")
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
    tap.equal(#host.subscriptions, 2, "degraded mode subscribes declared events")
    tap.equal(#host.blocks, 0, "degraded mode mounts no block")
    tap.equal(host:publish(CWD_EVENT, {}), 1, "degraded mode delivers events")
    tap.ok(host.snapshots >= 1, "degraded mode still reads the semantic snapshot")
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
      events = { CWD_EVENT, TITLE_EVENT },
    })
    local ok, err = pcall(activate, host)
    tap.ok(not ok, "missing ui.rich fails activation")
    tap.equal(type(err) == "table" and err.code or nil, "E_CAPABILITY_DENIED", "denied ui.rich code")
  end

  -- A terminal snapshot without `terminal.semantic-read` fails closed when a
  -- refresh is attempted.
  do
    local host = MockHost.new({
      grants = { "ui.rich" },
      events = { CWD_EVENT, TITLE_EVENT },
    })
    activate(host)
    local ok, err = pcall(host.publish, host, CWD_EVENT, {})
    tap.ok(not ok, "snapshot without capability fails closed")
    tap.equal(type(err) == "table" and err.code or nil, "E_CAPABILITY_DENIED", "denied snapshot code")
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
