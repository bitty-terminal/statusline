# Changelog

All notable changes to Bitty Statusline (`bitty-terminal.statusline`) are
recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Repository scaffold generated from
  [bitty-plugin-template](https://github.com/bitty-terminal/bitty-plugin-template):
  static manifest, a Lua 5.4 entry point, governance files, and CI.
- Independent first-party package extracted from the bundled
  `bitty-terminal.statusline` realization (OQ-053 split decision, `bitty`
  `CTX-0398`).
- Pure-Lua statusline: bounded component composition
  (`lua/statusline/format.lua`), declarative `Row`/`Text` composition
  (`lua/statusline/scene.lua`), and the activation entry point
  (`lua/statusline/init.lua`).
- Lua 5.4 behavior suite, LuaLS conformance, and SDK manifest-lint wrapper.
- Adopt the canonical `.editorconfig` baseline (`CTX-0023` slice); the
  repository-metadata baseline guide and ADR-0011 remain Proposed.

### Changed

- Realign package version from `0.1.0` to `0.0.1` per bitty-docs decision
  DIR-019 (everything pre-1.0-stable stays on the `0.0.x` line).
  `bitty-plugin.toml` and `package.json` stay in sync; no published tags or
  releases existed, so no migration is required.
- Composition uses the accepted Plugin API v1 Lua statusline slot
  (`bitty.ui.mount("statusline", ...)`) instead of the bundled realization's
  lower-level Panel Runtime path. Plugin id and capabilities
  (`terminal.semantic-read`, `ui.rich`) are unchanged from the bundled
  realization; the v1 hardening wave adds the `focus.changed` and
  `terminal.opened` lazy triggers.

### Fixed

- Hardened the v1 statusline path: refreshes keep the last-known-good row when
  a read, composition, or `bitty.ui.update` call is rejected instead of
  propagating to the event dispatcher; the block renders once at activation
  instead of staying blank until the first event; `focus.changed` and
  `terminal.opened` syncs re-render; `max_components` and
  `component_max_chars` clamp into their documented bounds; the semantic zone
  scan is capped; and only numeric `exit_code` values count as status.

[Unreleased]: https://github.com/bitty-terminal/statusline/commits/main
