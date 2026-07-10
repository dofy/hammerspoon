-- Hammerspoon Configuration
-- Manual reload with hotkey
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "r", function() hs.reload() end)

-- Load modules
local mouseFollow = require("mouse-follow")

-- Configure mouse follow
mouseFollow.config.moveDelay = 0.0
mouseFollow.config.clickDetectWindow = 0.3

-- Start modules
mouseFollow.start()

-- Show success message
hs.alert.show("🎉 Hammerspoon 🎉", 2)

-- never modify the code below this line
function reloadConfig(files)
    doReload = false
    for _, file in pairs(files) do
        if file:sub(-4) == ".lua" then doReload = true end
    end
    if doReload then hs.reload() end
end
local configPath = os.getenv("HOME") .. "/.hammerspoon/"
myWatcher = hs.pathwatcher.new(configPath, reloadConfig):start()
