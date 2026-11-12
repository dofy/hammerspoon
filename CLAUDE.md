# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Personal [Hammerspoon](https://www.hammerspoon.org/) configuration — Lua scripts that automate macOS via Hammerspoon's `hs.*` API. There is no build system, package manager, or test runner; code runs inside the Hammerspoon app process.

## Applying & Testing Changes

- **Reload config:** press `cmd+alt+ctrl+r` (bound in `init.lua`), or edits auto-reload via the `hs.pathwatcher` on `~/.hammerspoon/` — saving any `.lua` file triggers `hs.reload()`.
- **`hs -c` hangs during a reload.** The `hs.ipc` port blocks, rather than erroring, while the
  config is reloading, and a full reload here takes tens of seconds because `keystats.start()`
  opens SQLite and spawns the dashboard server. macOS has no `timeout`, so wrap the call in a
  background job with a hard kill instead of letting it hang. `hs.console.getConsole(true)`
  returns an `hs.styledtext` object whose serialisation over `hs.ipc` recurses until the Lua
  stack overflows — always call it with no argument. The console is capped near 100 000
  characters, so a burst of warnings flushes earlier output and makes it useless as evidence.
- **Debug output:** `print(...)` goes to the Hammerspoon Console (open from the menu-bar icon). There is no CLI test harness — verify behavior live in the running app.
- **Run an ad-hoc module manually:** in the Console, e.g. `require("test").test()`.

## Architecture

`init.lua` is the entry point Hammerspoon loads. It `require`s modules, configures them via their `.config` table, runs `init.local.lua`, then calls `.start()`.

**Per-machine overrides:** `init.local.lua` is git-ignored and holds anything one machine wants
differently. `init.lua` copies it from the tracked `init.local.example.lua` when it is missing,
then runs it with the `modules` table as its argument, after the shared defaults are set and
before any `start()`. It may change `modules.<name>.config` or set `modules.<name> = nil` to skip
starting that module. A load or runtime error in it is caught: it is printed to the Console with
an alert, and the shared defaults still start. Shared defaults go in `init.lua`; machine-specific
choices go in `init.local.lua`, never in `init.lua`. When adding a module, add it to both
`modules` and `startOrder` in `init.lua`.

**Module convention:** each `.lua` module returns a table `M` exposing a `M.config` table plus lifecycle functions `M.start()` / `M.stop()` / `M.toggle()`. `start()` must be idempotent (call `stop()` first if already running) and store event taps / window filters in module-private locals so `stop()` can tear them down. Follow this shape when adding modules.

- `mouse-follow.lua` — warps the cursor to the center of a window's screen on focus. Uses an `hs.window.filter` for focus/creation events and an `hs.eventtap` on `leftMouseDown` to suppress warping right after a click (so clicking to focus doesn't move the mouse).
- `keystats.lua` — shortcut-usage collector. An `hs.eventtap` on `keyDown` keeps only keys
  carrying cmd/alt/ctrl (shift counts only as a co-modifier unless the exact combination is
  named in `config.alwaysRecord`, which carries Raycast's `shift+space`; bare Escape and F-keys
  ride on `config.includeBareFunctionKeys`, on by default because the dropped `fn` flag leaves
  them modifier-less, while bare arrows need `config.includeBareNavigationKeys`), buffers them in
  memory and flushes to SQLite (`hs.sqlite3`) every 5s. When an app activation arrives within `config.globalSwitchWindow` of the last
  buffered keystroke, one press is split off and tagged with that app in `event.switch_to`,
  which is the only hard evidence available that a combination was a global hotkey (an event tap
  runs before any handler consumes the key, so the frontmost app is all it can otherwise see).
  A quit arrives *after* the next app activates, so `unmarkSwitch` takes that tag back when the
  app that was in front has terminated — otherwise `⌘Q` reads as a hotkey summoning whatever was
  behind it. Verdicts additionally need three hits and a concentrated target, so `⌘Tab` reads as
  a switcher rather than a launcher.
  `keystats/server.py` serves the dashboard live over loopback and is supervised from `start()`
  as an `hs.task`, so its queries cannot stall the event tap; it is passed `--exit-with-parent`
  because a signal to Hammerspoon never reaches `hs.shutdownCallback`. `keystats/report.html` is
  shared by the server and by static `keystats report` output through two markers it
  substitutes. The callback makes **no** OS calls: the frontmost
  app comes from an `hs.application.watcher`, because reading it in the hot path adds typing
  latency. Window titles were collected until 2026-10-22 and removed as noise; `start()` still
  drops `event.title_id` and the `title` table from older databases. A watchdog
  timer restarts the tap, since macOS silently disables a tap it considers slow. Modifier
  strings are normalised to `ctrl+alt+shift+cmd` order and the `fn` flag is dropped (macOS sets
  it on every arrow and function key). Query the database with `keystats/keystats`, a zsh CLI
  over `/usr/bin/sqlite3` that also renders `keystats/report.html` into a local dashboard.
- `statusbar.lua` — menu-bar host. Owns every `hs.menubar` item so individual widgets stay
  small: a widget declares what to show (`render`) and how often (`interval`), and the host
  creates the item, drives the timer and builds the dropdown. Widgets are files under
  `statusbar/` named in `config.widgets`, which is set **only in `init.local.lua`** —
  `statusbar.lua` ships an empty list and `init.lua` mounts nothing, because which widgets run
  is a per-machine choice; a machine whose `init.local.lua` sets no list shows no items.
  That list is also the on/off switch: a name in it runs, a name commented out does not. There
  is no runtime toggle, no control item and nothing in `hs.settings`, so the file on disk is the
  whole truth about what is mounted and a reload is the only way to change it.
  `config.widgetConfig.<name>` overrides a widget's own `config` table from the same place.
  Every call into widget code is wrapped in `pcall`: a widget that throws shows `⚠` with the
  error as its tooltip and the rest of the bar keeps running. `render` runs on the main thread,
  so anything waiting on the network or a subprocess belongs in `hs.task` / `hs.http.asyncGet`
  with `ctx.update()` called from its callback. macOS decides where a status item sits;
  `config.widgets` fixes mount order, not screen order. The host appends one `刷新` item to
  every dropdown, which only re-renders — a widget that throttles its own fetching needs its own
  forcing item.
  - `statusbar/battery.lua` — timer-driven example (`interval = 30`), present in `statusbar/`
    but commented out of `config.widgets`. `hs.battery.timeRemaining()` returns `-1` while macOS
    is still calculating and `-2` on AC power; both mean "no estimate".
  - `statusbar/netspeed.lua` — live up/down rate of the primary interface, from the byte
    delta between two `netstat -ibn -I <iface>` samples run as `hs.task`. It sets
    `interval = nil` and samples on its own timer: if `render` started the sample, each
    `ctx.update()` from the sample callback would start another. The interface follows
    `hs.network.primaryInterfaces()` on every sample (a `utun*` under a TUN-mode proxy, which
    still carries the real traffic); a counter that goes backwards drops the sample. netstat's
    Address column can be empty, so fields are counted from the end of the `<Link#N>` row.
    `layout = "stacked"` (default) draws ↑ over ↓ into one template image in Menlo 9;
    `"inline"` is one line of text. Each line is coloured by its own rate through the
    `config.colors` tiers (plain below 100K/s, then green, amber, red at 1M and 10M). Any
    coloured line makes the stacked image non-template, so the plain line is then painted
    `config.plainColor` grey. The real menu-bar foreground is unreadable: the bar picks light or
    dark text from the wallpaper, and `hs.host.interfaceStyle()` reported Light while the bar
    drew light text.
  - `statusbar/kaon.lua` — today's Kaon Router spend, over the Admin API at
    `kaon-router-admin-api.kaonai.com/api/v1`. The `kaon_pat_*` token is read once from
    `~/.config/kaon/token` (mode 600, outside this repo so it cannot be committed) and never
    printed; only HTTP status codes reach the tooltip, never a response body. Needs the
    `usage:read` scope — Kaon's write scopes explicitly do not imply usage, stats or audit
    access, so a token without it returns 403 forever. The title carries the spend alone: the
    daily budget never changes, so repeating it there spends menu-bar width on no information,
    and it still appears in the tooltip and the dropdown (`showBudget` puts it back). The budget
    is what the title's amber and red thresholds are a fraction of.
    The item is one composed image, not an icon plus a title: AppKit inserts ~17pt between an
    `NSStatusItem`'s image and its own title and `hs.menubar` exposes no way to shrink it, so the
    widget draws the glyph and the amount into a single `hs.canvas` and sets no title at all
    (an *empty* title still reserves that padding, measured). What is left — 18pt of the item's
    69pt — is AppKit's own and cannot be reached. The glyph is `statusbar/kaon.svg`, the Kaon
    console's favicon with its violet plate removed and its viewBox cropped to the artwork, and
    it ships as a **template image**: macOS tints the alpha mask to the menu-bar foreground
    colour, which is what carries light/dark mode for free. The amber/red state opts out of
    templating and paints itself, tinting the glyph through `compositeRule = "sourceAtop"` so the
    colour lands on the icon's own pixels only. Text format is configurable through `decimals`,
    `showBudget`, `budgetDecimals`, `budgetSeparator`, `symbol` and `font`; a Nerd Font glyph
    works as `symbol` only when `font` names a patched font, since fallback for those private-use
    codepoints is not guaranteed.
    Two sources disagree and the widget deliberately shows both: `/users/me/budget` is
    authoritative for today (it is the counter the console's /keys banner shows and the one that
    gates requests), while `/usage/summary` is Prometheus-derived and read ~8 USD higher for the
    same date on 2026-11-09. The breakdown uses `range=7d`; `range=24h` is unusable, returning
    five one-minute buckets instead of a day, and there is therefore no by_model breakdown for
    today alone. `source=starrocks` is a T+1 warehouse whose newest bucket is yesterday.
    The dropdown breaks the range down by model, by inference key and by provider.
    `by_provider.total_requests` is 0 for every provider while its cost is populated, so the
    provider rows show cost only; `by_model` and `by_key` both carry usable counts.
    `automation_protocol_throttled` and `automation_token_suspended` are stop signals in Kaon's
    contract, so a 401/403/429 is fatal: the widget stops requesting rather than risking token
    suspension, and only a manual retry, a toggle or a reload clears it. `start()` also reads
    `/auth/me` once for `automation_token_expires_at`, because a silently expired token would
    otherwise present as nothing but a 401.
- `test.lua` — battery-info diagnostic (`hs.battery.*`); not loaded by `init.lua`, invoke manually.
- `ui-demo.lua` — UI demo scratch file; not loaded by `init.lua`.

A widget file that is not listed in `statusbar.config.widgets` never loads, even if it sits in `statusbar/`. **Only modules explicitly `require`d in `init.lua` run.** `test.lua` and `Spoons/AClock.spoon` exist but are not loaded — Spoons would need `hs.loadSpoon("AClock")` to activate.

## Critical Constraint

The block in `init.lua` below the `-- never modify the code below this line` comment is the auto-reload watcher. Do not modify it — breaking it disables live reload and every subsequent edit requires a manual reload.
