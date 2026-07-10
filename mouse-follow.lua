-- Mouse Follow Module
-- 功能：当窗口获得焦点时，自动将鼠标移动到该窗口所在屏幕的中心
local M = {}

-- Configuration
M.config = {
    enabled = true,
    moveDelay = 0.0, -- delay before moving mouse (seconds)
    clickDetectWindow = 0.3 -- time window to detect recent clicks (seconds)
}

-- Private variables
local wf = nil
local lastClickTime = 0
local clickEventTap = nil

local function centerOfScreen(scr)
    local f = scr and scr:frame()
    if not f then return nil end
    return {x = f.x + f.w / 2, y = f.y + f.h / 2}
end

local function maybeWarpMouseTo(win)
    if not M.config.enabled then return end
    if win == nil or not win:isStandard() then return end

    local scr = win:screen()
    if scr == nil then return end

    local targetPos = centerOfScreen(scr)
    if targetPos == nil then return end

    -- Check if activation was caused by a recent mouse click
    local timeSinceClick = hs.timer.secondsSinceEpoch() - lastClickTime
    if timeSinceClick < M.config.clickDetectWindow then return end

    local mouseScr = hs.mouse.getCurrentScreen()

    -- If mouse is already on the target screen, don't move
    if mouseScr and scr and mouseScr:id() == scr:id() then return end

    -- Mouse is on a different screen, move it to target screen center
    hs.mouse.absolutePosition(targetPos)
end

function M.start()
    if wf then M.stop() end

    -- Track mouse clicks to avoid moving when clicking activates window
    clickEventTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown},
                                    function(event)
        lastClickTime = hs.timer.secondsSinceEpoch()
        return false -- don't block the event
    end)
    clickEventTap:start()

    -- Create window filter
    wf = hs.window.filter.new(true)

    -- Handle window focus events
    wf:subscribe(hs.window.filter.windowFocused, function(win)
        if M.config.moveDelay > 0 then
            hs.timer.doAfter(M.config.moveDelay,
                             function() maybeWarpMouseTo(win) end)
        else
            maybeWarpMouseTo(win)
        end
    end)

    -- Handle window creation (some apps create before focusing)
    wf:subscribe(hs.window.filter.windowCreated, function(win)
        hs.timer.doAfter(0.05, function() maybeWarpMouseTo(win) end)
    end)

    return M
end

function M.stop()
    if wf then
        wf:unsubscribeAll()
        wf = nil
    end
    if clickEventTap then
        clickEventTap:stop()
        clickEventTap = nil
    end
    return M
end

function M.toggle()
    M.config.enabled = not M.config.enabled
    local status = M.config.enabled and "ON" or "OFF"
    hs.alert.show("Mouse Follow: " .. status)
    return M
end

return M

