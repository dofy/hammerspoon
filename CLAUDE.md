# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Personal [Hammerspoon](https://www.hammerspoon.org/) configuration — Lua scripts that automate macOS via Hammerspoon's `hs.*` API. There is no build system, package manager, or test runner; code runs inside the Hammerspoon app process.

## Applying & Testing Changes

- **Reload config:** press `cmd+alt+ctrl+r` (bound in `init.lua`), or edits auto-reload via the `hs.pathwatcher` on `~/.hammerspoon/` — saving any `.lua` file triggers `hs.reload()`.
- **Debug output:** `print(...)` goes to the Hammerspoon Console (open from the menu-bar icon). There is no CLI test harness — verify behavior live in the running app.
- **Run an ad-hoc module manually:** in the Console, e.g. `require("test").test()`.

## Architecture

`init.lua` is the entry point Hammerspoon loads. It `require`s modules, configures them via their `.config` table, then calls `.start()`.

**Module convention:** each `.lua` module returns a table `M` exposing a `M.config` table plus lifecycle functions `M.start()` / `M.stop()` / `M.toggle()`. `start()` must be idempotent (call `stop()` first if already running) and store event taps / window filters in module-private locals so `stop()` can tear them down. Follow this shape when adding modules.

- `mouse-follow.lua` — warps the cursor to the center of a window's screen on focus. Uses an `hs.window.filter` for focus/creation events and an `hs.eventtap` on `leftMouseDown` to suppress warping right after a click (so clicking to focus doesn't move the mouse).
- `arc-to-chrome.lua` — when Arc is the active app, `Cmd+Ctrl+C` opens the current tab URL in Chrome. Loaded and started in `init.lua`.
- `test.lua` — battery-info diagnostic (`hs.battery.*`); not loaded by `init.lua`, invoke manually.
- `ui-demo.lua` — UI demo scratch file; not loaded by `init.lua`.

**Only modules explicitly `require`d in `init.lua` run.** `test.lua` and `Spoons/AClock.spoon` exist but are not loaded — Spoons would need `hs.loadSpoon("AClock")` to activate.

## Critical Constraint

The block in `init.lua` below the `-- never modify the code below this line` comment is the auto-reload watcher. Do not modify it — breaking it disables live reload and every subsequent edit requires a manual reload.
