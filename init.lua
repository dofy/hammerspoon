-- Hammerspoon Configuration
-- Manual reload with hotkey
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "r", function() hs.reload() end)

-- hs.ipc: 允许 `hs -c "..."` 从终端查询运行中的配置
require("hs.ipc")

-- Load modules. 这里只设所有机器共用的默认值；本机个性化改 init.local.lua。
local mouseFollow = require("mouse-follow")
mouseFollow.config.moveDelay = 0.0
mouseFollow.config.clickDetectWindow = 0.3

-- Keystats: 记录带修饰键的按键，供 `keystats` CLI 统计快捷键使用情况
local keystats = require("keystats")

-- Statusbar: 状态栏挂载入口，widget 放在 statusbar/ 下。
-- 挂哪些 widget、各自参数都是每台机器自己的事，写在 init.local.lua 里；这里不挂任何 widget。
local statusbar = require("statusbar")

-- 按顺序启动的模块。init.local.lua 可以改它们的 config，或把某项设为 nil 不启动。
local modules = {
    mouseFollow = mouseFollow,
    keystats = keystats,
    statusbar = statusbar,
}
local startOrder = { "mouseFollow", "keystats", "statusbar" }

-- Per-machine overrides: init.local.lua 被 git 忽略，不存在时从 init.local.example.lua 复制。
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
        hs.alert.show("⚠️ init.local.lua 出错，见 Console", 4)
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
