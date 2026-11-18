-- init.local.lua — 本机个性化配置，已在 .gitignore 里，改它不会产生仓库修改。
-- 首次启动时从 init.local.example.lua 自动复制生成；删掉它下次 reload 会重新生成。
-- 它在 init.lua 设完默认值之后、模块 start() 之前执行，所以这里的赋值会覆盖默认值。
-- 保存后照样自动 reload。
--
-- 参数 modules: { mouseFollow = ..., keystats = ..., statusbar = ..., displayBrightness = ..., keycast = ... }
--   改 config：modules.<name>.config.<key> = value
--   不启动某模块：modules.<name> = nil
local modules = ...

-- 示例：鼠标跟随延迟 0.1 秒
-- modules.mouseFollow.config.moveDelay = 0.1

-- 示例：本机不跑按键统计
-- modules.keystats = nil

-- 示例：m1ddc 安装在非标准路径时，只在本机覆盖；默认检测 Apple Silicon/Intel Homebrew 路径。
-- modules.displayBrightness.config.cli = "/absolute/path/to/m1ddc"
-- modules.displayBrightness.config.reconnectDelay = 3

-- 示例：状态栏挂载哪些 widget（init.lua 默认一个都不挂）。列表就是开关。
-- modules.statusbar.config.widgets = {
--     "kaon",
--     "netspeed",
--     -- "battery",
-- }
-- 示例：覆盖单个 widget 的参数
-- modules.statusbar.config.widgetConfig.kaon = { font = { name = "Menlo", size = 13 }, decimals = 1 }

-- 按键提示：默认关闭，用 ⌃⌥⌘K 开关。取消注释并按需修改。
-- modules.keycast.config.hotkey = { mods = { "ctrl", "alt", "cmd" }, key = "k" }
-- modules.keycast.config.target = "focused" -- focused：活动窗口；mouse：鼠标下的窗口
-- modules.keycast.config.position = "bottomLeft" -- topLeft / topRight / bottomLeft / bottomRight / center
-- modules.keycast.config.margin = 24
-- modules.keycast.config.types = { shortcuts = true, text = false, special = true, mouse = false }
-- modules.keycast.config.colors = { background = { white = 0.12, alpha = 0.9 }, text = { white = 1, alpha = 1 } }
-- modules.keycast.config.fontSize = 42
-- modules.keycast.config.sequenceDelay = 0.5 -- 连续文字分段间隔
-- modules.keycast.config.linger = 2.0 -- 每条提示停留时间
-- modules.keycast.config.fadeDuration = 0.2
-- modules.keycast.config.moveDuration = 0.15
-- modules.keycast.config.maxRows = 6
-- modules.keycast.config.maxTextLength = 200
-- modules.keycast.config.enabled = true -- 重载后自动开启；会展示允许的输入
