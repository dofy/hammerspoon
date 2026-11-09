--- === statusbar.battery ===
---
--- Timer-driven widget: battery charge, charging state and remaining time.
--- Mounted by `statusbar.lua`; see that file for the widget contract.

local M = {}

M.label = "电池"
M.interval = 30

M.config = {
    -- Below this percentage the title turns red while on battery.
    lowThreshold = 20,
    -- Hide the item entirely while the machine runs on AC and is fully charged,
    -- so a desktop-bound laptop does not keep a dead item around.
    hideWhenFullOnAC = false
}

local function glyph(charging, percent)
    if charging then return "⚡︎" end
    if percent <= M.config.lowThreshold then return "▁" end
    return "▮"
end

-- timeRemaining() is minutes, or -1 while macOS is still calculating and -2 on
-- AC power. Both negatives mean "no estimate", not "no time left".
local function remainingText()
    local mins = hs.battery.timeRemaining()
    if not mins or mins < 0 then return nil end
    return string.format("%d:%02d", math.floor(mins / 60), mins % 60)
end

function M.render(ctx)
    local percent = hs.battery.percentage()
    if not percent then return nil end
    percent = math.floor(percent + 0.5)

    local charging = hs.battery.isCharging()
    local onAC = hs.battery.powerSource() == "AC Power"

    if ctx.config.hideWhenFullOnAC and onAC and percent >= 100 then return nil end

    local text = string.format("%s%d%%", glyph(charging, percent), percent)
    local title = text
    if not onAC and percent <= ctx.config.lowThreshold then
        title = hs.styledtext.new(text, {color = {red = 0.9, green = 0.2, blue = 0.2}})
    end

    local tooltip = onAC and "电源适配器" or "电池供电"
    local left = remainingText()
    if left then tooltip = tooltip .. "  剩余 " .. left end

    return {title = title, tooltip = tooltip}
end

function M.menu(ctx)
    local items = {
        {title = string.format("电量  %d%%", math.floor((hs.battery.percentage() or 0) + 0.5)), disabled = true},
        {title = "电源  " .. (hs.battery.powerSource() or "unknown"), disabled = true}
    }

    local left = remainingText()
    items[#items + 1] = {title = "剩余  " .. (left or "计算中"), disabled = true}

    local cycles = hs.battery.cycles()
    if cycles then items[#items + 1] = {title = "循环  " .. cycles, disabled = true} end

    local health = hs.battery.health()
    if health then items[#items + 1] = {title = "健康  " .. health, disabled = true} end

    return items
end

return M
