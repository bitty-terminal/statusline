# Bitty Statusline

Cwd, mode, Git, and task presentation for the
[Bitty terminal](https://github.com/bitty-terminal/bitty), composed through the
statusline slot with declarative fragments only.

- Plugin id: `bitty-terminal.statusline`
- Lua module: `lua/statusline/`
- Capabilities: `terminal.semantic-read`, `ui.rich`
- Lazy events: `terminal.cwd-changed`, `terminal.title-changed`, `focus.changed`,
  `terminal.opened`

This repository is the independent first-party package created by the bundled
plugin split decision (OQ-053, `bitty-plugins-docs` `product/bundled-plugin-split-decision.md`),
owned by `bitty` `CTX-0398`. It was scaffolded from
[bitty-plugin-template](https://github.com/bitty-terminal/bitty-plugin-template).

## Status

Pre-implementation ecosystem: the plugin package, manifest, and presentation
policy are implemented and tested headlessly; the Bitty host is still landing
the Plugin API v1 statusline bridge. Nothing here is a compatibility promise
beyond the manifest `[compat]` ranges.

## Layout

| Path                            | Purpose                                                                                         |
| ------------------------------- | ----------------------------------------------------------------------------------------------- |
| `bitty-plugin.toml`             | Static manifest: identity, compatibility, capability requests, and lazy triggers.               |
| `lua/statusline/init.lua`       | Entry point evaluated once per activation; mounts the statusline block and refreshes on events. |
| `lua/statusline/format.lua`     | Bounded, host-free component composition and code-point-safe truncation.                        |
| `lua/statusline/scene.lua`      | Declarative `Row`/`Text` statusline composition.                                                |
| `tests/`                        | Lua 5.4 behavior suite, LuaLS conformance, and the SDK manifest-lint wrapper.                   |
| `scripts/validate-manifest.mjs` | Transitional manifest check; `bitty-plugin-lint` (R-SDK-2) is authoritative.                    |
| `justfile`                      | Quality gates with pinned tool versions.                                                        |

## Behavior

The plugin keeps the bundled statusline behavior and bounds:

- components composed from the read-only semantic snapshot: `cwd:` from the
  latest zone `metadata.cwd`, `title:` from the snapshot `title`, and `exit:`
  from the latest zone `metadata.exit_code`;
- at most `8` components (`STATUSLINE_MAX_COMPONENTS`), `64` characters per
  component value (`STATUSLINE_COMPONENT_MAX_CHARS`), and `128` characters
  total (`MAX_OVERLAY_TEXT_LEN`), truncated at a UTF-8 code-point boundary;
- one declarative `Row` of `Text` fragments mounted in the `statusline` slot
  (`Text`, `Row`, `Column`, `List` are the only Plugin API v1 node kinds);
- recomposition on the manifest-declared observation events
  `terminal.cwd-changed`, `terminal.title-changed`, `focus.changed` (pane/tab
  switches), and `terminal.opened`, with rapid bursts coalesced host-side by
  the accepted event contract;
- a render at activation and on every delivered event; a rejected read,
  composition, or update keeps the last-known-good row instead of blanking the
  statusline (`H-SL-01`);
- empty state yields an empty row (no fallback pollution).

Optional settings under `plugins.bitty-terminal.statusline.*` (`separator`,
`show_cwd`, `show_title`, `show_exit`, `max_components`,
`component_max_chars`) adapt the composition; every default matches the
bundled realization. Settings are not part of the v1 manifest and are read
through `bitty.settings.get`.

## What moved and what stayed bundled

This package owns the statusline presentation only. Two boundaries are
explicit (OQ-053 decision record):

- the **workspaceline claim** (ordering, exclusive claim, close policy) and
  workspace lifecycle are workspace-core behavior and stay bundled in `bitty`;
- **shell integration** stays bundled and remains the upstream provider of the
  OSC 7/133 semantic zones this plugin observes.

The plugin id and capability identifiers (`terminal.semantic-read`, `ui.rich`)
are unchanged from the bundled `bitty-terminal.statusline` manifest; the split
changes no identity. The bundled realization used the lower-level Panel
Runtime (`PanelType::Helper`); the accepted Plugin API v1 Lua path composes in
the `statusline` UI slot instead.

## Known gaps

- **Host statusline bridge.** The current `bitty` Lua bridge implements
  commands, events, settings, store, terminal snapshots, notifications, and
  timers, but not `bitty.ui.mount`/`bitty.ui.update`. The plugin activates,
  subscribes its events, and observes snapshots, but presents no visible block
  until that surface lands. Tracked as a follow-up task in `bitty`.
- **Status-component provider.** The accepted v1 surface exposes no
  `StatusProvider`/`status.component` provider contract; the Plugin Reuse and
  Provider Ecology RFC is draft/post-1.0. The plugin composes its fragments
  into one host-owned `Row` as the v1 adapter.
- **Git and task fragments.** The bundled presentation name includes Git and
  task state, but the bundled Rust realization composed only cwd, title, and
  exit code, and v1 exposes no Git/task service. Those fragments are not
  implemented here and follow the provider ecology.

## Development

Run the same gates CI runs:

```sh
bun install --frozen-lockfile
just check
```

`just check` runs Markdown lint, Prettier format check, the transitional
manifest validator, the pinned Lua parser, and the Lua/LuaLS/SDK-manifest test
suites. `lua5.4` is required for the behavior suite; `lua-language-server` and
`bitty-plugin-lint` are optional and their checks skip with exit 0 when absent.

## Install

An external package is installed from a local checkout with the Bitty CLI:

```sh
bitty plugin install /path/to/statusline
```

The registry entry in
[bitty-plugins](https://github.com/bitty-terminal/bitty-plugins) points at this
repository; this plugin previously shipped as a bundled (staged, disabled by
default) `bitty-terminal.statusline`.

## Migration note

A configuration that previously enabled or disabled the bundled
`bitty-terminal.statusline` keeps the same plugin id, capabilities, grant
identity, and lazy events, so grant records and scripts continue to resolve
after the catalog entry is replaced by this registry package. The package is
not enabled by default, and `bitty --safe` skips it exactly as it skips any
other plugin. Shell integration and the workspaceline claim are unaffected
because they remain bundled.

## Security

Only `terminal.semantic-read` and `ui.rich` are requested. The plugin has no
filesystem, process, network, clipboard, terminal-input, terminal-write, or
persistent-state authority. It observes committed terminal state read-only and
performs no I/O. Report vulnerabilities through the process in the umbrella
project's security policy rather than a public issue.
