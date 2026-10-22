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
- `dia-to-chrome.lua` — when Dia is the active app, `Cmd+Ctrl+C` opens the current tab URL in Chrome. Loaded and started in `init.lua`.
- `keystats.lua` — shortcut-usage collector. An `hs.eventtap` on `keyDown` keeps only keys
  carrying cmd/alt/ctrl (shift counts only as a co-modifier unless the exact combination is
  named in `config.alwaysRecord`, which carries Raycast's `shift+space`; bare Escape / F-keys /
  arrows need `config.includeBareSpecialKeys`), buffers them in memory and flushes to SQLite (`hs.sqlite3`)
  every 5s. When an app activation arrives within `config.globalSwitchWindow` of the last
  buffered keystroke, one press is split off and tagged with that app in `event.switch_to`,
  which is the only hard evidence available that a combination was a global hotkey (an event tap
  runs before any handler consumes the key, so the frontmost app is all it can otherwise see).
  `keystats/server.py` serves the dashboard live over loopback; `keystats/report.html` is shared
  by the server and by static `keystats report` output through two markers it substitutes. The callback makes **no** OS calls: the frontmost
  app comes from an `hs.application.watcher` and the window title from an `hs.window.filter`
  subscription, because fetching an AX title in the hot path adds typing latency. A watchdog
  timer restarts the tap, since macOS silently disables a tap it considers slow. Modifier
  strings are normalised to `ctrl+alt+shift+cmd` order and the `fn` flag is dropped (macOS sets
  it on every arrow and function key). Query the database with `keystats/keystats`, a zsh CLI
  over `/usr/bin/sqlite3` that also renders `keystats/report.html` into a local dashboard.
- `test.lua` — battery-info diagnostic (`hs.battery.*`); not loaded by `init.lua`, invoke manually.
- `ui-demo.lua` — UI demo scratch file; not loaded by `init.lua`.

**Only modules explicitly `require`d in `init.lua` run.** `test.lua` and `Spoons/AClock.spoon` exist but are not loaded — Spoons would need `hs.loadSpoon("AClock")` to activate.

## Critical Constraint

The block in `init.lua` below the `-- never modify the code below this line` comment is the auto-reload watcher. Do not modify it — breaking it disables live reload and every subsequent edit requires a manual reload.
