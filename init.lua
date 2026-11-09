-- Hammerspoon Configuration
-- Manual reload with hotkey
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "r", function() hs.reload() end)

-- Load modules
local mouseFollow = require("mouse-follow")

-- Configure mouse follow
mouseFollow.config.moveDelay = 0.0
mouseFollow.config.clickDetectWindow = 0.3

-- Start modules
mouseFollow.start()

-- Keystats: 记录带修饰键的按键，供 `keystats` CLI 统计快捷键使用情况
local keystats = require("keystats")
keystats.start()

-- hs.ipc: 允许 `hs -c "..."` 从终端查询运行中的配置
require("hs.ipc")

-- Statusbar: 状态栏挂载入口，widget 放在 statusbar/ 下。
-- 这个列表就是开关：留着的挂载，注释掉的不挂载。没有运行时开关，没有持久化状态。
local statusbar = require("statusbar")
statusbar.config.widgets = {
    "kaon",
    -- "battery",
}
-- 覆盖单个 widget 的参数（可选），键名同上
-- statusbar.config.widgetConfig.kaon = {warnRatio = 0.5}
-- 等宽标题：金额位数变化时菜单栏宽度不跳。本机只有 Menlo / Monaco / MesloLGS NF
-- 三个等宽字体通过 hs.styledtext.validFont，"SF Mono" 不通过。
-- 图标走 statusbar/kaon.svg（控制台自己的 favicon），文本只用等宽字体。
statusbar.config.widgetConfig.kaon = { font = { name = "Menlo", size = 13 } }
statusbar.start()

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
