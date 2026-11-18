# Hammerspoon

A personal macOS toolkit for navigating displays, showing keystrokes, and keeping useful numbers in the menu bar.

> 🖥️ **Built for multiple displays.** Brightness follows the pointer. Windows can bring the pointer along. Keystrokes and shortcuts stay visible when you need them.

## The toolkit

| Module | What it does | Guide |
| :--- | :--- | :--- |
| ☀️ **Brightness** | Adjust the display under the pointer, including external DDC displays. | [Display controls](#display-controls) |
| ⌨️ **Keycast** | Show keystrokes, shortcuts and held modifiers in a temporary overlay. | [Keycast →](docs/keycast.md) |
| 🖱️ **Mouse Follow** | Move the pointer to a window’s display when focus changes. | [Configuration](#make-it-yours) |
| 📊 **Keystats** | Record shortcut usage and explore it in a local dashboard or CLI. | [Keystats →](docs/keystats.md) |
| 📍 **Statusbar** | Mount small menu-bar widgets for Kaon Router, network speed and battery. | [Statusbar →](docs/statusbar.md) |

## Get started

1. Install [Hammerspoon](https://www.hammerspoon.org/) (`brew install --cask hammerspoon`).
2. Back up any existing `~/.hammerspoon` configuration, then clone this repository:

   ```sh
   git clone https://github.com/dofy/hammerspoon.git ~/.hammerspoon
   ```

3. Launch Hammerspoon and grant Accessibility permission when prompted.
4. Reload with `Control + Option + Command + R`, or choose **Reload Config** from the menu bar.

Saving a Lua file in the configuration directory also reloads it automatically. On first launch, `init.local.lua` is created from [`init.local.example.lua`](init.local.example.lua); it is ignored by Git and holds machine-specific settings.

## At a glance

| Control | Action |
| :--- | :--- |
| `Control + Option + Command + R` | Reload the configuration |
| `Control + Option + Command + K` | Toggle Keycast; show its status in the center of the pointer’s screen |
| `Brightness Down` / `F1` / `F14` | Dim the display under the pointer |
| `Brightness Up` / `F2` / `F15` | Brighten the display under the pointer |
| `Control + Option + Command + [` | Dim the display under the pointer |
| `Control + Option + Command + ]` | Brighten the display under the pointer |

Keycast starts off by default. Keystats starts with Hammerspoon and serves a local dashboard; its database is stored outside this repository. Status-bar widgets are selected per machine and none are mounted by default.

## Make it yours

Edit `~/.hammerspoon/init.local.lua`. The file receives a `modules` table and runs after shared defaults, before modules start:

```lua
local modules = ...

modules.keycast.config.enabled = true
modules.keycast.config.target = "mouseScreen"
modules.keycast.config.showModifiers = true
modules.statusbar.config.widgets = { "netspeed", "battery" }
-- modules.keystats = nil  -- disable a module on this machine
```

See [`init.local.example.lua`](init.local.example.lua) for more configuration examples. To enable Keycast on reload, set `modules.keycast.config.enabled = true`; its text and mouse display options remain independently configurable.

### Display controls

Brightness changes in 5-point steps. Native displays use macOS APIs; external displays use `m1ddc`, with commands serialized and the target selected at keypress time. The module checks the Apple Silicon and Intel Homebrew paths for `m1ddc`; override `modules.displayBrightness.config.cli` if it lives elsewhere. It never installs the tool.

Successfully verified values are stored per display UUID in Hammerspoon settings. On reconnect, restoration waits three seconds and yields to a manual adjustment. Existing displays are not changed on reload; restoration requires the same UUID and working native or DDC read/write support.

### Explore shortcut usage

The collector starts a local dashboard by default. Open it while Hammerspoon is running:

```sh
open http://127.0.0.1:8787
```

To use the CLI, link it onto your `PATH`:

```sh
mkdir -p ~/.local/bin
ln -s ~/.hammerspoon/keystats/keystats ~/.local/bin/keystats
```

Add `~/.local/bin` to your `PATH` if needed. See the [Keystats guide](docs/keystats.md) for queries, recording rules, retention and privacy details.

## Inside the config

```text
init.lua               Shared defaults, module startup and reload watcher
init.local.example.lua Per-machine configuration template
keycast.lua            Keystroke overlay
keystats.lua           Shortcut collector
keystats/              CLI, dashboard server and report
mouse-follow.lua       Pointer follows window focus
display-brightness.lua Native and DDC brightness controls
statusbar.lua          Menu-bar host
statusbar/             Kaon, network and battery widgets
test.lua               On-demand battery diagnostic
Spoons/                Bundled Hammerspoon extensions
```

## Guides

- ⌨️ [Keycast](docs/keycast.md) — display modes, placement and timing.
- 📊 [Keystats](docs/keystats.md) — CLI, dashboard, collection and storage.
- 📍 [Statusbar](docs/statusbar.md) — widget configuration, Kaon setup and widget authoring.
