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
- Commit-pinned `bitty-plugin-sdk` dev dependency (`bitty-plugin-lint`,
  R-SDK-2) in `package.json` and `bun.lock`, with `just install` and a
  fail-closed `just deps` guard; `just manifest` runs the authoritative SDK
  linter and every gate is offline after the one-time install.
- Adopt the canonical `.editorconfig` baseline (`CTX-0023` slice); the
  repository-metadata baseline guide and ADR-0011 remain Proposed.
- Repository metadata baseline: a tracked `.gitattributes` normalizing text
  files to LF and marking binary assets, and a `packageManager` bun pin in
  `package.json` with the regenerated `bun.lock` (`CTX-0006`).

### Changed

- Manifest validation now uses the authoritative commit-pinned
  `bitty-plugin-lint` from `bitty-plugin-sdk` (ref `c3fa9b0`) instead of the
  vendored transitional validator. The manifest schema stays owned by
  bitty-docs; the gates fail closed when the pinned linter is not installed.
- Every JavaScript gate now invokes the installed tool with `bun run <bin>`
  instead of `bunx --bun <tool>@<pin>`, which re-resolved over the network and
  broke the offline guarantee (`PX-0016`). Tool versions live in `package.json`
  and `bun.lock` only (the justfile no longer declares pins), and `just check`
  is proven offline under `unshare -rn`.
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
- Refresh `CONTRIBUTING.md` to the current contributor-guide structure
  (ground rules, prerequisites, setup, delivery lifecycle, contributor
  branches, capabilities, workflow snapshots) and align `SECURITY.md` with the
  canonical `bitty-docs` security corpus (`CTX-0006`).

### Removed

- Remove the vendored transitional `scripts/validate-manifest.mjs`. The SDK
  linter is now the single source of manifest validation, closing the recorded
  divergence risk tracked by the SDK manifest contract (R-SDK-2).

### Fixed

- Discover the pinned `bitty-plugin-lint` from the repository-local
  `node_modules/.bin` in `tests/check-manifest-lint.mjs`, so the optional
  `just test-manifest` wrapper exercises the installed SDK linter instead of
  skipping whenever the CLI is not on `PATH` (`PX-0016` reviewer note).
- Hardened the v1 statusline path: refreshes keep the last-known-good row when
  a read, composition, or `bitty.ui.update` call is rejected instead of
  propagating to the event dispatcher; the block renders once at activation
  instead of staying blank until the first event; `focus.changed` and
  `terminal.opened` syncs re-render; `max_components` and
  `component_max_chars` clamp into their documented bounds; the semantic zone
  scan is capped; and only numeric `exit_code` values count as status.

[Unreleased]: https://github.com/bitty-terminal/statusline/commits/main
