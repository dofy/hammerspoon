-- arc-to-chrome.lua
-- 当 Arc 处于激活状态时,按 Cmd+Ctrl+C 用 Chrome 打开 Arc 当前激活 tab 的 URL
-- 兼容 Little Arc(独立浮窗):统一使用 Arc 自带“复制 URL 快捷键 + 读剪贴板”。
--
-- 关键点:触发热键 Cmd+Ctrl+C 时,用户仍物理按住 Cmd/Ctrl。若立刻合成
-- Cmd+Shift+C,物理按住的 Ctrl 会叠加成 Cmd+Ctrl+Shift+C,导致 Arc 复制失败。
-- 因此先等待物理修饰键释放,再合成复制快捷键;复制后轮询剪贴板直到拿到 URL。

local M = {}

M.config = {
    mods = {"cmd", "ctrl"},
    key = "C",
    -- Arc 中“复制当前页面 URL”的快捷键,默认 Cmd+Shift+C
    copyUrlMods = {"cmd", "shift"},
    copyUrlKey = "C",
    -- keyStroke 按下与抬起的间隔(微秒),太小 Arc 可能识别不到快捷键
    keyStrokeDelay = 40000,
    -- 等待物理修饰键释放
    modReleasePoll = 0.03,
    modReleaseMax = 1.0,
    -- 复制后轮询剪贴板:间隔与最长等待
    pollInterval = 0.05,
    pollMax = 1.5, -- 最多等 1.5s
    -- Arc 偶尔漏接快捷键:剪贴板仍未写入时的重发间隔
    resendInterval = 0.35,
    -- 打印执行过程到 Hammerspoon Console
    debug = false,
}

local logFile = os.getenv("HOME") .. "/.hammerspoon/arc-to-chrome.log"

local function dbg(...)
    if not M.config.debug then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    local line = os.date("%H:%M:%S") .. " " .. table.concat(parts, " ")
    print("[arc2chrome]", line)
    local f = io.open(logFile, "a")
    if f then
        f:write(line, "\n")
        f:close()
    end
end

local hotkey = nil
local appWatcher = nil

local function openInChrome(url)
    dbg("open in Chrome:", url)
    hs.execute('open -a "Google Chrome" "' .. url .. '"')
end

local function looksLikeURL(s)
    return type(s) == "string" and s:match("^%a[%w+.-]*://") ~= nil
end

local function noModifiersHeld()
    local f = hs.eventtap.checkKeyboardModifiers()
    return not (f.cmd or f.ctrl or f.alt or f.shift or f.fn)
end

local function doCopyAndOpen()
    local saved = hs.pasteboard.getContents()
    local sentinel = "__ARC2CHROME_SENTINEL__"
    hs.pasteboard.setContents(sentinel)

    local function sendCopy()
        dbg("send copy URL keystroke:", table.concat(M.config.copyUrlMods, "+"), M.config.copyUrlKey)
        hs.eventtap.keyStroke(M.config.copyUrlMods, M.config.copyUrlKey, M.config.keyStrokeDelay)
    end
    sendCopy()

    -- 轮询剪贴板:一旦被 Arc 写入合法 URL 就立即打开,兼顾速度与可靠性
    -- Arc 偶尔完全没接住快捷键(剪贴板停在 sentinel),因此在超时前定期重发
    local waited = 0
    local lastSend = 0
    local timer
    timer = hs.timer.doEvery(M.config.pollInterval, function()
        waited = waited + M.config.pollInterval
        local url = hs.pasteboard.getContents()
        dbg(string.format("poll clipboard waited=%.2fs content=%s", waited, tostring(url)))
        if url ~= sentinel and looksLikeURL(url) then
            timer:stop()
            dbg("got URL after", string.format("%.2fs", waited))
            openInChrome(url)
            if saved ~= nil then hs.pasteboard.setContents(saved) end
        elseif waited >= M.config.pollMax then
            timer:stop()
            dbg("timeout, no URL after", string.format("%.2fs", waited))
            hs.alert.show("无法获取 Arc 当前 tab 的 URL")
            if saved ~= nil then hs.pasteboard.setContents(saved) end
        elseif url == sentinel and (waited - lastSend) >= M.config.resendInterval then
            -- 仍未写入,快捷键可能被漏接,重发
            lastSend = waited
            dbg("clipboard still sentinel, resend copy keystroke")
            sendCopy()
        end
    end)
end

local function openCurrentTabInChrome()
    dbg("hotkey triggered, waiting for modifier release")
    local waited = 0
    local timer
    timer = hs.timer.doEvery(M.config.modReleasePoll, function()
        waited = waited + M.config.modReleasePoll
        if noModifiersHeld() then
            timer:stop()
            dbg("modifiers released after", string.format("%.2fs", waited))
            doCopyAndOpen()
        elseif waited >= M.config.modReleaseMax then
            timer:stop()
            dbg("modifier release wait timeout after", string.format("%.2fs", waited))
            doCopyAndOpen()
        end
    end)
end

function M.start()
    hotkey = hs.hotkey.new(M.config.mods, M.config.key, openCurrentTabInChrome)

    appWatcher = hs.application.watcher.new(function(appName, eventType, app)
        if eventType == hs.application.watcher.activated then
            if appName == "Arc" then
                dbg("Arc activated -> hotkey enabled")
                hotkey:enable()
            else
                hotkey:disable()
            end
        end
    end)
    appWatcher:start()

    local front = hs.application.frontmostApplication()
    if front and front:name() == "Arc" then
        hotkey:enable()
    end
end

function M.stop()
    if hotkey then hotkey:disable() end
    if appWatcher then appWatcher:stop() end
end

return M
