-- init.local.lua — 本机个性化配置，已在 .gitignore 里，改它不会产生仓库修改。
-- 首次启动时从 init.local.example.lua 自动复制生成；删掉它下次 reload 会重新生成。
-- 它在 init.lua 设完默认值之后、模块 start() 之前执行，所以这里的赋值会覆盖默认值。
-- 保存后照样自动 reload。
--
-- 参数 modules: { mouseFollow = ..., keystats = ..., statusbar = ... }
--   改 config：modules.<name>.config.<key> = value
--   不启动某模块：modules.<name> = nil
local modules = ...

-- 示例：鼠标跟随延迟 0.1 秒
-- modules.mouseFollow.config.moveDelay = 0.1

-- 示例：本机不跑按键统计
-- modules.keystats = nil

-- 示例：状态栏挂载哪些 widget（init.lua 默认一个都不挂）。列表就是开关。
-- modules.statusbar.config.widgets = {
--     "kaon",
--     "netspeed",
--     -- "battery",
-- }
-- 示例：覆盖单个 widget 的参数
-- modules.statusbar.config.widgetConfig.kaon = { font = { name = "Menlo", size = 13 }, decimals = 1 }
