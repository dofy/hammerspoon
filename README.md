# .hammerspoon

My personal [Hammerspoon](https://www.hammerspoon.org/) configuration for automating macOS.

## Features

- **Mouse Follow** (`mouse-follow.lua`) — automatically warps the cursor to the center of a window's screen when that window gains focus, so the pointer follows your attention across multiple displays. Clicking to focus a window is detected and suppressed, so a click never yanks the mouse away.
- **Keystats** (`keystats.lua`) — records every modifier-bearing keystroke, plus Escape, the function keys and the navigation keys, together with the frontmost application and the window title, so you can find out which shortcuts you actually use. Data lands in `~/.local/share/keystats/keystats.db`; query it with the `keystats` CLI described below.
- **Dia → Chrome** (`dia-to-chrome.lua`) — while Dia is the active app, `⌘ + ⌃ + C` opens the current tab's URL in Chrome.
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
dia-to-chrome.lua # Cmd+Ctrl+C in Dia opens the current tab in Chrome
keystats.lua      # shortcut-usage collector (writes ~/.local/share/keystats/keystats.db)
keystats/         # `keystats` CLI + HTML report template for that database
test.lua          # battery-info diagnostic (loaded on demand)
Spoons/           # bundled Spoons
```

## Keystats

Link the CLI onto your `PATH` once:

```sh
ln -s ~/.hammerspoon/keystats/keystats ~/.local/bin/keystats
```

```sh
keystats status                                    # rows, date range, db size
keystats top --since 7d --app Cursor                # most used shortcuts in one app
keystats top --by title --since 30d                 # which documents drive the keystrokes
keystats pivot --rows app --cols mods --since 30d   # any two dimensions crossed
keystats time --bucket hourofday                    # when during the day you press them
keystats titles --app Ghostty                       # busiest window titles
keystats unused --from combos.txt --since 30d       # bindings you configured but never pressed
keystats report --since 30d --open                  # local HTML dashboard
keystats sql "SELECT ..."                           # escape hatch
keystats prune --older-than 90d                     # roll old events up to the hour
```

Every query command accepts `--since` / `--until` / `--app` / `--title` / `--mods` / `--key`.
Time values are `all`, `today`, `yesterday`, `7d`, `24h`, `90m`, `4w`, `3mo` or `YYYY-MM-DD`;
dimensions are `combo`, `key`, `mods`, `app`, `bundle`, `title`, `hour`, `day`, `week`, `month`,
`dow` and `hourofday`. `keystats report` writes a self-contained page with a keyboard heatmap,
the top combinations, the per-app and per-modifier split, a time-of-day histogram and a trend
chart, all of which re-pivot client-side when you change the app, title or bucket selectors.

### What it does and does not record

Plain character keys are **not** recorded (`keystats.lua` → `config.includePlainKeys`), so the
database holds no typed text; only Shift-bearing combinations that also carry ⌘, ⌥ or ⌃ count as
shortcuts. Modifier order is normalised to `ctrl+alt+shift+cmd`, and the `fn` flag is dropped,
because macOS sets it on every arrow and function key. Keys are stored as keycodes, so switching
input source cannot split one physical key across two rows. Key repeats from holding a key down
are skipped by default. Nothing is recorded while macOS secure input is active (password fields,
or a terminal with Secure Keyboard Entry enabled) — those keystrokes never reach an event tap.

### Storage

Events are buffered in memory and flushed in one transaction every five seconds. Roughly 5k
events a day cost about 60 MB a year, so `keystats prune --older-than 90d` rolls older events up
to hour granularity and drops their window titles. The database lives outside this repository,
under `~/.local/share/keystats/`, and is never committed.

## Configuration

Mouse-follow behavior is tuned in `init.lua`:

```lua
mouseFollow.config.moveDelay = 0.0          -- delay before moving the mouse (seconds)
mouseFollow.config.clickDetectWindow = 0.3  -- window to ignore clicks that caused focus (seconds)
```

Toggle it at runtime with `mouseFollow.toggle()`.
