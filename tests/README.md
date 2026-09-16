# Statusline test harness

Headless checks for the `lua/statusline/**` implementation. `just check`
(`lint` + `fmt-check` + `manifest` + `lua` + `test`) runs them locally and in
CI; the individual suites are also available directly.

## Prerequisites

- `lua5.4` (plugin VM baseline per ADR 0005) — required for behavior tests;
  CI installs it from the Ubuntu archive before `just check`.
- `bun` — the LuaLS and SDK-linter wrapper scripts.
- `lua-language-server` (optional) — LuaLS conformance; the check skips with
  exit 0 when it is unavailable (CI does not install it).
- `bitty-plugin-lint` from `bitty-plugin-sdk` — authoritative manifest check,
  installed at the commit pinned in `package.json`/`bun.lock` by `just install`
  and run by `just manifest`. The optional `tests/check-manifest-lint.mjs`
  wrapper discovers that local `node_modules/.bin` install first and skips only
  when the CLI is truly absent.

## Commands

```sh
just test            # lua5.4 runner + LuaLS check + SDK linter wrapper

# Behavior tests: composition policy, scene composition, lifecycle, capabilities.
just test-lua

# LuaLS conformance against the vendored Plugin API v1 definitions
# (LUA_LANGUAGE_SERVER=/path/to/server overrides discovery).
just test-luals

# Authoritative manifest check (SDK R-SDK-2), pinned by commit and run by
# `just manifest`; BITTY_PLUGIN_LINT=/path/to/bitty-plugin-sdk/src/cli.ts
# forces the optional `just test-manifest` wrapper's SDK CLI.
just test-manifest
```

## Layout

| Path                            | Purpose                                                                                |
| ------------------------------- | -------------------------------------------------------------------------------------- |
| `run.lua`                       | Plain-Lua runner; exits non-zero on assertion failure.                                 |
| `support/tap.lua`               | Assertion helper (no external test framework).                                         |
| `support/mock_host.lua`         | Fail-closed in-process `bitty` stub modeling the used v1 subset (capabilities, scene). |
| `spec/filter_spec.lua`          | Filtering and truncation policy unit tests.                                            |
| `spec/scene_spec.lua`           | Declarative scene composition unit tests.                                              |
| `spec/init_spec.lua`            | Entry-point behavior against the mock host.                                            |
| `lua-defs/bitty.d.lua`          | Vendored LuaLS definitions from bitty-plugin-sdk (origin/main `a7fcd2b`).              |
| `lua-defs/negative-fixture.lua` | Excluded-surface fixture that LuaLS must reject.                                       |
| `check-lua-luals.mjs`           | Positive/negative LuaLS workspace check.                                               |
| `check-manifest-lint.mjs`       | Runs the pinned `bitty-plugin-lint` (`node_modules/.bin`, then `PATH`).                |

## Known gaps

- The SDK mock host is a TypeScript test double; a Lua-facing adapter able to
  execute `init.lua` against it is a separate tooling task
  (`bitty-plugin-sdk` `docs/mock-host.md`, "Lua execution").
  `support/mock_host.lua` is this repository's bounded stand-in.
- The `bitty` Lua bridge does not yet implement `bitty.ui.mount`/`update`, so
  `init_spec.lua` exercises overlay behavior against the local mock host only;
  in-host activation runs in command-only mode.
- CI installs `lua5.4` and, through `bun install --frozen-lockfile`, the pinned
  `bitty-plugin-lint` that `just manifest` runs; `lua-language-server` is not
  installed, so the LuaLS wrapper reports `skipped` (exit 0) in CI.
