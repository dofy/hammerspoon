# .hammerspoon

My personal [Hammerspoon](https://www.hammerspoon.org/) configuration for automating macOS.

## Features

- **Mouse Follow** (`mouse-follow.lua`) — automatically warps the cursor to the center of a window's screen when that window gains focus, so the pointer follows your attention across multiple displays. Clicking to focus a window is detected and suppressed, so a click never yanks the mouse away.
- **Keystats** (`keystats.lua`) — records every keystroke that carries ⌘, ⌥ or ⌃, together with the frontmost application, so you can find out which shortcuts you actually use. Data lands in `~/.local/share/keystats/keystats.db`; query it with the `keystats` CLI, or watch it live with `keystats serve`.
- **Battery info** (`test.lua`) — an on-demand diagnostic that prints detailed battery stats (health, cycles, capacity, voltage…) to the Hammerspoon Console. Run `require("test").test()` in the Console.
- **Manual reload** — press `⌘ + ⌥ + ⌃ + R` to reload the config at any time.
- **Auto reload** — saving any `.lua` file under `~/.hammerspoon/` reloads the config automatically.

## Installation

1. Install [Hammerspoon](https://www.hammerspoon.org/) (e.g. `brew install --cask hammerspoon`).
2. Back up your existing config if you have one, then clone into place:

   ```sh
   git clone https://github.com/dofy/hammerspoon.git ~/.hammerspoon
   ```

3. Launch Hammerspoon and grant Accessibility permissions when prompted.
4. Reload the config (menu-bar icon → _Reload Config_, or `⌘ + ⌥ + ⌃ + R`).

## Layout

```
init.lua          # entry point: loads modules, binds reload hotkey, starts the path watcher
mouse-follow.lua  # mouse-follow module (config + start/stop/toggle)
keystats.lua      # shortcut-usage collector (writes ~/.local/share/keystats/keystats.db)
keystats/keystats # CLI over that database
keystats/server.py# live dashboard server (`keystats serve`)
keystats/report.html # dashboard page, used by both the live server and static reports
test.lua          # battery-info diagnostic (loaded on demand)
Spoons/           # bundled Spoons
```

## Keystats

Link the CLI onto your `PATH` once:

```sh
ln -s ~/.hammerspoon/keystats/keystats ~/.local/bin/keystats
```

```sh
keystats serve --open                              # live dashboard, polls every 5s
keystats status                                    # rows, date range, db size
keystats top --since 7d --app Cursor                # most used shortcuts in one app
keystats pivot --rows app --cols mods --since 30d   # any two dimensions crossed
keystats time --bucket hourofday                    # when during the day you press them
keystats unused --from combos.txt --since 30d       # bindings you configured but never pressed
keystats global --since 30d                         # global hotkey vs in-app shortcut
keystats report --since 30d --open                  # static snapshot of the dashboard
keystats sql "SELECT ..."                           # escape hatch
keystats prune --older-than 90d                     # roll old events up to the hour
```

Every query command accepts `--since` / `--until` / `--app` / `--mods` / `--key`.
Time values are `all`, `today`, `yesterday`, `7d`, `24h`, `90m`, `4w`, `3mo` or `YYYY-MM-DD`;
dimensions are `combo`, `key`, `mods`, `app`, `bundle`, `hour`, `day`, `week`, `month`, `dow`
and `hourofday`.

### The dashboard

`init.lua` already starts that dashboard: the collector supervises `keystats/server.py` as a
child task, so it is up whenever Hammerspoon is (`config.server` holds `enabled`, `host`, `port`
and the restart policy). A heavy query therefore runs in another process and can never stall the
event tap, which an in-process server would. The child watches `getppid()` and exits on its own
when Hammerspoon goes away, because a `SIGTERM` or `SIGKILL` to the parent never reaches
`hs.shutdownCallback` and the port would otherwise stay held. Reloading the config replaces the
server; if the port is already taken the collector logs it once and leaves the running server
alone rather than retrying.

`keystats serve` starts the same thing by hand on `127.0.0.1:8787` (`--port`, `--host`), for a
second instance or a different database. It polls the database every five seconds, so the
numbers move while you work; the footer carries the refresh clock and a pause button. The server
binds to loopback on purpose — this database is a record of every shortcut you press.

`keystats report` writes a self-contained snapshot of that page instead, for archiving or
sharing. Both carry a keyboard heatmap; one shortcut table combining the ranking with the
global-vs-in-app verdict (they were two views of the same per-combination aggregate); the
per-app and per-modifier split, each switchable between bars and a donut; a time-of-day
histogram and a trend chart, each switchable between bars and a line; and a collapsed
combination × app detail table. Everything re-pivots client-side from the app and modifier
selectors.

**生成分享图** rasterises the page itself into a PNG — preview, download, or copy to the
clipboard. It needs no library and works from `file://`: the page is cloned into an
`<svg><foreignObject>` together with its own stylesheet and drawn onto a canvas at 2×, which
stays untainted only because the page loads no external image or font. The resolved theme is
stamped onto the clone, since media queries inside the rasterised SVG cannot see the page's.
Interactive chrome carrying `data-noexport` — the share button itself, the pause button — is
stripped first, and the detail table is captured in whatever state it is on screen.

Window titles were collected until 2026-10-22 and then dropped: in the apps that carry the most
shortcuts the title was a constant (`微信`, `飞书`) and added nothing to the app name, while the
apps with many titles — a browser, a chat client — contributed a fresh row per page, 45% of them
seen exactly once. The dimension cost a filter, a panel, a detail column and an API branch, and
it was the only thing in the database recording *what* was on screen rather than which keys were
pressed. Per-project context, if it is ever wanted, belongs in a low-cardinality field derived at
collection time (a repository or session name parsed out of the title), not in the raw title.

### Global hotkey or in-app shortcut?

An event tap sees a keystroke *before* any app or global hotkey handler consumes it, so the only
app it can record is whoever was frontmost. A Raycast or Karabiner binding pressed while Cursor
is in front is therefore filed under Cursor. Two signals narrow it down, and `keystats global`
(and the dashboard's **全局 vs app 内** panel) report both:

- **switch hits** — when an app activation lands within `config.globalSwitchWindow` (0.6s) of a
  keystroke, that target app is stored on the event. Only counts from three hits up: closing the
  frontmost window brings another app forward on its own, so a single activation proves nothing.
- **focus** — the share of those activations that went to the most common target. A launcher
  always lands on the same app; `⌘Tab` scatters over everything, which reads as *switcher* rather
  than a launcher for any one app.
- **spread** — the Shannon entropy of the combination's distribution over apps, normalised by
  `log2(apps in range)`. A per-app shortcut clusters in one app; a global one shows up
  everywhere. Four or more apps and a spread of 0.6 or higher reads as *suspected global*.

`⌘Q` used to look like a global hotkey, because quitting the frontmost app brings the next one
forward. macOS reports the termination *after* that activation, so the quit cannot be filtered
out up front; instead the collector takes the tag back when the app that was in front turns out
to have quit. That only works while the press is still buffered, as does tagging itself — a
keystroke in the last moments before a flush is missed either way. Neither signal can see a
global binding that leaves the frontmost app alone, such as a window-management hotkey or
Raycast's panel, which does not take activation.

### What it does and does not record

A keystroke is recorded only when it carries ⌘, ⌥ or ⌃. Shift alone is capitalisation, so it
counts only as a co-modifier, and a bare arrow key, Escape or function key is navigation rather
than a shortcut (`config.includeBareSpecialKeys` turns those back on). Plain character keys are
never recorded unless `config.includePlainKeys` is set, so the database holds no typed text and
no window titles.

Real hotkeys that live on Shift alone are named individually in `config.alwaysRecord`, which
ships with Raycast's `shift+space`. Write the key the way this module spells it: modifiers in
`ctrl+alt+shift+cmd` order, then the `hs.keycodes.map` name, joined with `+`. Modifier order is normalised to `ctrl+alt+shift+cmd`, and the `fn` flag is dropped,
because macOS sets it on every arrow and function key. Keys are stored as keycodes, so switching
input source cannot split one physical key across two rows. Key repeats from holding a key down
are skipped by default. Nothing is recorded while macOS secure input is active (password fields,
or a terminal with Secure Keyboard Entry enabled) — those keystrokes never reach an event tap.

### Storage

Events are buffered in memory and flushed in one transaction every five seconds. Roughly 5k
events a day cost about 60 MB a year, so `keystats prune --older-than 90d` rolls older events up
to hour granularity. The database lives outside this repository,
under `~/.local/share/keystats/`, and is never committed.

## Configuration

Mouse-follow behavior is tuned in `init.lua`:

```lua
mouseFollow.config.moveDelay = 0.0          -- delay before moving the mouse (seconds)
mouseFollow.config.clickDetectWindow = 0.3  -- window to ignore clicks that caused focus (seconds)
```

Toggle it at runtime with `mouseFollow.toggle()`.
