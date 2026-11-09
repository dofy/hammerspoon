# .hammerspoon

My personal [Hammerspoon](https://www.hammerspoon.org/) configuration for automating macOS.

## Features

- **Mouse Follow** (`mouse-follow.lua`) — automatically warps the cursor to the center of a window's screen when that window gains focus, so the pointer follows your attention across multiple displays. Clicking to focus a window is detected and suppressed, so a click never yanks the mouse away.
- **Keystats** (`keystats.lua`) — records every keystroke that carries ⌘, ⌥ or ⌃, together with the frontmost application, so you can find out which shortcuts you actually use. Data lands in `~/.local/share/keystats/keystats.db`; query it with the `keystats` CLI, or watch it live with `keystats serve`.
- **Statusbar** (`statusbar.lua`) — a menu-bar host: small widget files under `statusbar/` say what to show and how often, and the host creates the status item, drives the refresh and builds the dropdown. Ships with a Kaon Router spend readout and a battery readout.
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
statusbar.lua     # menu-bar host (owns every hs.menubar item)
statusbar/        # widget files, one status item each
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
histogram and a trend chart, each switchable between bars and a line and each carrying a
labelled scale, because a chart read only through its tooltip says nothing once it becomes an
image; and a combination × app detail table. Everything re-pivots client-side from the app and modifier
selectors.

**生成分享图** rasterises the page itself into a PNG — preview, download, or copy to the
clipboard. It needs no library and works from `file://`: the page is cloned into an
`<svg><foreignObject>` together with its own stylesheet and drawn onto a canvas at 2×, which
stays untainted only because the page loads no external image or font. Inside that SVG the clone
is not `:root`, so neither the dark media query nor `:root[data-theme]` matches it and
`body { color }` never applies either; the resolved custom properties and text colour are copied
onto the clone instead of relying on a selector.
Interactive chrome carrying `data-noexport` — the share button, the pause button, the tooltip —
is stripped first, and the detail table is captured in whatever state it is on screen.

Marks carry their readout in `data-tip` rather than a `title`, because the native tooltip waits
out the OS delay before appearing and that is useless while sweeping a cursor across a chart.
One delegated `pointermove` listener positions a single bubble, clamped to the viewport, and
clears it whenever the page re-renders underneath it.

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
- **跨 app / spread** — whether the combination belongs to one application or turns up
  everywhere. It is the Shannon entropy of its distribution over apps normalised by
  `log2(apps in range)`, which counts the balance and not just the number of apps: 100 presses in
  Chrome and one in Finder is two apps but still Chrome's shortcut. Four or more apps and a
  spread of 0.6 or higher reads as *suspected global*.

The dashboard shows both as a segmented meter rather than a bare `0.37`, because the level reads
off the number of filled cells — legible in greyscale, in print and to a colour-blind viewer —
while the figure itself, the app count and which app the switches went to sit in the tooltip.

`⌘Q` used to look like a global hotkey, because quitting the frontmost app brings the next one
forward. macOS reports the termination *after* that activation, so the quit cannot be filtered
out up front; instead the collector takes the tag back when the app that was in front turns out
to have quit. That only works while the press is still buffered, as does tagging itself — a
keystroke in the last moments before a flush is missed either way. Neither signal can see a
global binding that leaves the frontmost app alone, such as a window-management hotkey or
Raycast's panel, which does not take activation.

### What it does and does not record

A keystroke is recorded only when it carries ⌘, ⌥ or ⌃. Shift alone is capitalisation, so it
counts only as a co-modifier. Escape and the function keys are the exception that
`config.includeBareFunctionKeys` records bare, on by default: macOS sets the `fn` flag on every
function key and this module drops that flag, so an unmodified F5 arrives carrying nothing at all
and would otherwise be invisible. A bare arrow key or page-up is movement rather than a shortcut
and stays out unless `config.includeBareNavigationKeys` is set. Plain character keys are never
recorded unless `config.includePlainKeys` is set, so the database holds no typed text and no
window titles.

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

### Statusbar

`init.lua` is the only file to edit. The widget list is also the on/off switch — a name in it
runs, a name commented out does not:

```lua
local statusbar = require("statusbar")
statusbar.config.widgets = {
    "kaon",
    -- "battery",
}
statusbar.config.widgetConfig.battery = {lowThreshold = 15}
statusbar.start()
```

Saving the file reloads Hammerspoon, so the change takes effect immediately. There is no runtime
toggle and nothing is stored outside the file: what the list says is what is mounted. To check
what actually came up:

```sh
hs -c 'hs.inspect(require("statusbar").status())'
```

A widget that is listed but reads `false` there failed to mount; the Hammerspoon Console carries
the reason.

#### Kaon Router spend

`statusbar/kaon.lua` shows today's Kaon Router spend in the menu bar, read from the
Kaon Admin API. It needs an automation token:

1. Open <https://kaon-router-admin.kaonai.com>, then **Automation Tokens** in the sidebar.
2. Create a token with the **`usage:read`** scope. Kaon's write scopes do not imply usage access,
   so a token without this scope gets 403 on every request, forever.
3. Store it outside this repository, readable only by you:

   ```sh
   printf '%s' 'kaon_pat_...' > ~/.config/kaon/token
   chmod 600 ~/.config/kaon/token
   ```

The token is read once at start and never printed; only HTTP status codes reach the tooltip.

The menu-bar title is the spend alone. The daily budget, what is left of it, and the weekly and
monthly figures live in the tooltip and the dropdown — the budget does not change from hour to
hour, so putting it in the title would cost width for nothing. The title does turn amber at 70%
and red at 90% of that budget.

Two numbers in the dropdown disagree on purpose. `今日` comes from `/users/me/budget`, the counter
the Kaon console's own banner shows and the one that actually gates requests. `按天 (Prometheus)`
comes from `/usage/summary`, which read about 8 USD higher for the same date. Trust `今日`.
There is no breakdown for today alone: the only range tokens are `5m | 1h | 24h | 7d | 30d`, and
`24h` comes back as five one-minute buckets rather than a day, so the breakdown covers seven days
and says so. It splits that range by model, by inference key and by provider. The provider rows
show cost without a request count because the API reports 0 requests for every provider while
still reporting its cost.

A 401, 403 or 429 stops the widget instead of retrying — `automation_protocol_throttled` and
`automation_token_suspended` are stop signals in Kaon's contract, and hammering through them
risks the token being suspended. Clear the stopped state from the dropdown's **重试**, or by
toggling the widget off and on.

#### Writing a widget

Drop a file in `statusbar/` and add its name to `config.widgets`. A widget returns a table:

```lua
local M = {}

M.label    = "Disk"   -- shown in the ⚠ tooltip when render throws
M.interval = 60       -- refresh seconds; nil means event-driven only
M.config   = {path = "/"}

function M.render(ctx)       -- required
  local free = hs.fs.volume.allVolumes()[ctx.config.path]
  if not free then return nil end          -- nil hides the item
  return {title = "💾", tooltip = ctx.config.path}
end

function M.menu(ctx) return {{title = ctx.config.path, disabled = true}} end
function M.start(ctx) end    -- install watchers here, call ctx.update() from them
function M.stop(ctx) end     -- tear them down here

return M
```

`render` may return a string, an `hs.styledtext` object, a table of
`{title =, icon =, tooltip =, template =}`, or `nil` to take the item off the bar until the next
non-nil render. `ctx` carries `ctx.name`, `ctx.config`, `ctx.bar` and `ctx.update()`.

Two rules matter:

- `render` runs on the main thread. Anything that waits on the network or a subprocess goes into
  `hs.task` or `hs.http.asyncGet`, with `ctx.update()` called from the callback — a blocking
  render freezes the menu bar.
- `click` replaces the dropdown. Define one or the other, not both.

Every call into widget code is wrapped in `pcall`. A widget that throws shows `⚠` with the error
as its tooltip, and the other widgets keep running.
