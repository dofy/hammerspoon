-- init.local.lua — per-machine configuration, ignored by Git.
-- Created from init.local.example.lua if missing on reload.
-- Runs after shared defaults and before modules start, so values here override defaults.
-- Saving triggers an automatic reload.
--
-- Argument modules: { mouseFollow = ..., keystats = ..., statusbar = ..., displayBrightness = ..., keycast = ... }
--   Change config: modules.<name>.config.<key> = value
--   Skip a module: modules.<name> = nil
local modules = ...

-- Example: set mouse-follow delay to 0.1 seconds
-- modules.mouseFollow.config.moveDelay = 0.1

-- Example: disable keystroke statistics on this machine
-- modules.keystats = nil

-- Example: override a nonstandard m1ddc path; defaults detect Apple Silicon and Intel Homebrew paths.
-- modules.displayBrightness.config.cli = "/absolute/path/to/m1ddc"
-- modules.displayBrightness.config.reconnectDelay = 3

-- Example: select status-bar widgets (none are mounted by default).
-- modules.statusbar.config.widgets = {
--     "kaon",
--     "netspeed",
--     -- "battery",
-- }
-- Example: override one widget configuration
-- modules.statusbar.config.widgetConfig.kaon = { font = { name = "Menlo", size = 13 }, decimals = 1 }

-- Keycast: off by default; toggle with ⌃⌥⌘K. Uncomment and adjust as needed.
-- modules.keycast.config.hotkey = { mods = { "ctrl", "alt", "cmd" }, key = "k" }
-- modules.keycast.config.target = "focused" -- focused: active window; mouse: window under pointer; mouseScreen: pointer screen
-- modules.keycast.config.position = "bottomLeft" -- topLeft / topRight / bottomLeft / bottomRight / center
-- modules.keycast.config.margin = 24
-- modules.keycast.config.types = { shortcuts = true, text = false, special = true, mouse = false }
-- modules.keycast.config.showModifiers = true -- show held modifier keys
-- modules.keycast.config.colors = { background = { white = 0.12, alpha = 0.9 }, text = { white = 1, alpha = 1 } }
-- modules.keycast.config.fontSize = 42
-- modules.keycast.config.sequenceDelay = 0.5 -- text sequence gap in seconds
-- modules.keycast.config.linger = 2.0 -- time each line remains visible
-- modules.keycast.config.fadeDuration = 0.2
-- modules.keycast.config.moveDuration = 0.15
-- modules.keycast.config.maxRows = 6
-- modules.keycast.config.repeatMode = "badge" -- normal: every press; badge: superscript repeat count
-- modules.keycast.config.maxTextLength = 200
-- modules.keycast.config.enabled = true -- enable on reload; allowed input will be visible
