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

### Changed

- Composition uses the accepted Plugin API v1 Lua statusline slot
  (`bitty.ui.mount("statusline", ...)`) instead of the bundled realization's
  lower-level Panel Runtime path. Plugin id, capabilities
  (`terminal.semantic-read`, `ui.rich`), and lazy events are unchanged.

[Unreleased]: https://github.com/bitty-terminal/statusline/commits/main
