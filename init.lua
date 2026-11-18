-- Hammerspoon Configuration
-- Manual reload with hotkey
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "r", function() hs.reload() end)

-- hs.ipc: allow `hs -c "..."` to query the running configuration
require("hs.ipc")

-- Load modules. Shared defaults only; machine-specific settings belong in init.local.lua.
local mouseFollow = require("mouse-follow")
mouseFollow.config.moveDelay = 0.0
mouseFollow.config.clickDetectWindow = 0.3

-- Keystats: record modified keystrokes for shortcut statistics in the `keystats` CLI
local keystats = require("keystats")

-- Statusbar: menu-bar host; widgets live under statusbar/.
-- Widget selection and settings belong in init.local.lua; none are mounted here.
local statusbar = require("statusbar")
local displayBrightness = require("display-brightness")
local keycast = require("keycast")

-- Modules start in order; init.local.lua can change config or set a module to nil.
local modules = {
    mouseFollow = mouseFollow,
    keystats = keystats,
    statusbar = statusbar,
    displayBrightness = displayBrightness,
    keycast = keycast,
}
local startOrder = { "mouseFollow", "keystats", "statusbar", "displayBrightness", "keycast" }

-- Per-machine overrides: init.local.lua is git-ignored and copied from the example when missing.
local configDir = hs.configdir .. "/"
local localPath = configDir .. "init.local.lua"
local examplePath = configDir .. "init.local.example.lua"
if not hs.fs.attributes(localPath) and hs.fs.attributes(examplePath) then
    local src = io.open(examplePath, "r")
    local dst = io.open(localPath, "w")
    if src and dst then
        dst:write(src:read("a"))
        print("init.local.lua created from init.local.example.lua")
    end
    if src then src:close() end
    if dst then dst:close() end
end
if hs.fs.attributes(localPath) then
    local chunk, err = loadfile(localPath)
    local ok = chunk ~= nil
    if ok then ok, err = pcall(chunk, modules) end
    if not ok then
        print("init.local.lua failed: " .. tostring(err))
        hs.alert.show("⚠️ init.local.lua error; see Console", 4)
    end
end

-- Start modules
for _, name in ipairs(startOrder) do
    if modules[name] then modules[name].start() end
end

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
