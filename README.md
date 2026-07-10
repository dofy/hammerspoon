# .hammerspoon

My personal [Hammerspoon](https://www.hammerspoon.org/) configuration for automating macOS.

## Features

- **Mouse Follow** (`mouse-follow.lua`) — automatically warps the cursor to the center of a window's screen when that window gains focus, so the pointer follows your attention across multiple displays. Clicking to focus a window is detected and suppressed, so a click never yanks the mouse away.
- **Manual reload** — press `⌘ + ⌥ + ⌃ + R` to reload the config at any time.
- **Auto reload** — saving any `.lua` file under `~/.hammerspoon/` reloads the config automatically.
- **Battery info** (`test.lua`) — an on-demand diagnostic that prints detailed battery stats (health, cycles, capacity, voltage…) to the Hammerspoon Console. Run `require("test").test()` in the Console.

## Installation

1. Install [Hammerspoon](https://www.hammerspoon.org/) (e.g. `brew install --cask hammerspoon`).
2. Back up your existing config if you have one, then clone into place:

   ```sh
   git clone https://github.com/dofy/hammerspoon.git ~/.hammerspoon
   ```

3. Launch Hammerspoon and grant Accessibility permissions when prompted.
4. Reload the config (menu-bar icon → *Reload Config*, or `⌘ + ⌥ + ⌃ + R`).

## Layout

```
init.lua          # entry point: loads modules, binds reload hotkey, starts the path watcher
mouse-follow.lua  # mouse-follow module (config + start/stop/toggle)
test.lua          # battery-info diagnostic (loaded on demand)
Spoons/           # bundled Spoons
```

## Configuration

Mouse-follow behavior is tuned in `init.lua`:

```lua
mouseFollow.config.moveDelay = 0.0          -- delay before moving the mouse (seconds)
mouseFollow.config.clickDetectWindow = 0.3  -- window to ignore clicks that caused focus (seconds)
```

Toggle it at runtime with `mouseFollow.toggle()`.
