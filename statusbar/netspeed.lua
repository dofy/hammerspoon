--- === statusbar.netspeed ===
---
--- Live upload / download rate of the primary network interface.
--- Mounted by `statusbar.lua`; see that file for the widget contract.
---
--- Where the numbers come from:
---   macOS exposes no byte counters through `hs.*`, so the widget samples
---   `netstat -ibn -I <iface>` and divides the byte delta by the time between
---   samples. netstat runs as an `hs.task`, never on the main thread.
---
--- Why `interval` is nil:
---   The host timer calls `render`, and `render` must stay cheap. If it also
---   started the sample, every `ctx.update()` from the sample callback would
---   start another one. Sampling therefore runs on this widget's own timer,
---   and `render` only formats the last result.
---
--- Which interface:
---   `config.interface = nil` follows `hs.network.primaryInterfaces()` (the
---   IPv4 default route), re-read on every sample so switching between Wi-Fi
---   and Ethernet needs no reload. With a TUN-mode proxy the primary interface
---   is a `utun*`, which still carries the real traffic. A counter that goes
---   backwards (interface changed or reset) drops that sample instead of
---   showing a negative or huge rate.
---
--- Colour:
---   Each line is coloured by its own rate through `config.colors`, a list of
---   `{below = bytes/s, color = ...}` tiers checked in order; the first tier
---   whose `below` exceeds the rate wins, and `color = nil` means the plain
---   menu-bar foreground. While both lines are plain the stacked image stays a
---   template, so macOS tints it. Once either line is coloured the image can no
---   longer be a template (macOS would tint the colour away), so the plain
---   line is painted `config.plainColor`, a mid grey readable on both a light
---   and a dark bar. The real menu-bar foreground cannot be read:
---   `hs.host.interfaceStyle()` reports the system appearance, but the bar
---   picks light or dark text from the wallpaper behind it, and on 2026-11-12
---   it drew light text while the system reported Light. `colors = false`
---   turns colouring off.

local M = {}

M.label = "网速"
M.interval = nil -- sampling has its own timer; see the note above

M.config = {
    -- Seconds between samples.
    sampleEvery = 2,
    -- nil = follow the primary interface; or a fixed name such as "en0".
    interface = nil,
    -- "stacked": upload over download in one composed template image, so it
    --            follows light/dark mode and keeps a fixed width.
    -- "inline":  one line of text, "↓1.2M ↑ 30K".
    layout = "stacked",
    -- Monospaced so the item width does not jump as digits change. Menlo is
    -- one of the few monospace fonts that pass hs.styledtext.validFont here.
    font = {name = "Menlo", size = 9},
    inlineFont = {name = "Menlo", size = 12},
    -- Below this rate (bytes/s) the line reads as idle, not as noise like 0.1K.
    idleBelow = 1024,
    -- Rate tiers, checked in order: the first tier whose `below` (bytes/s)
    -- exceeds the rate gives the colour. A tier without `below` catches the
    -- rest. `color = nil` keeps the menu-bar foreground. `false` = no colour.
    colors = {
        {below = 100 * 1024, color = nil}, -- < 100K: plain
        {below = 1024 * 1024, color = {red = 0.20, green = 0.78, blue = 0.35}}, -- < 1M: green
        {below = 10 * 1024 * 1024, color = {red = 1.00, green = 0.62, blue = 0.04}}, -- < 10M: amber
        {color = {red = 1.00, green = 0.27, blue = 0.23}} -- >= 10M: red
    },
    -- The plain line while the other line is coloured; see the note above.
    plainColor = {white = 0.6, alpha = 1}
}

-- Private state
local timer = nil
local task = nil
local last = nil -- {iface, rx, tx, t}
local rate = nil -- {rx, tx} bytes per second, last good sample
local iface = nil
local totals = nil -- {rx, tx} counters since boot for the current interface
local peak = {rx = 0, tx = 0}
local lastError = nil

-- Helpers --------------------------------------------------------------------

local function currentInterface()
    if M.config.interface then return M.config.interface end
    local v4, v6 = hs.network.primaryInterfaces()
    return v4 or v6 or nil
end

-- Fixed width: always four characters of number plus the unit, so a stacked
-- image or an inline title keeps its size from one sample to the next.
local function rateText(bps)
    if not bps or bps < M.config.idleBelow then return "   0K" end
    local units = {"K", "M", "G"}
    local v = bps / 1024
    local i = 1
    while v >= 1000 and i < #units do
        v = v / 1024
        i = i + 1
    end
    local fmt = v < 10 and "%4.1f%s" or "%4.0f%s"
    return string.format(fmt, v, units[i])
end

-- Colour for one line, or nil for the plain menu-bar foreground.
local function rateColor(bps, tiers)
    if not tiers then return nil end
    bps = bps or 0
    for _, tier in ipairs(tiers) do
        if tier.below == nil or bps < tier.below then return tier.color end
    end
    return nil
end

local function bytesText(n)
    local units = {"B", "KB", "MB", "GB", "TB"}
    local i = 1
    while n >= 1024 and i < #units do
        n = n / 1024
        i = i + 1
    end
    return string.format(i == 1 and "%d %s" or "%.1f %s", n, units[i])
end

-- `netstat -ibn -I en0` prints one <Link#N> row per interface with 64-bit
-- byte counters. The Address column can be empty, so fields are counted from
-- the end of the row: ... Ibytes Opkts Oerrs Obytes Coll.
local function parse(out)
    for line in out:gmatch("[^\n]+") do
        if line:find("<Link#", 1, true) then
            local f = {}
            for w in line:gmatch("%S+") do f[#f + 1] = w end
            local rx, tx = tonumber(f[#f - 4]), tonumber(f[#f - 1])
            if rx and tx then return rx, tx end
        end
    end
    return nil
end

local function sample(ctx)
    if task and task:isRunning() then return end

    local name = currentInterface()
    if not name then
        iface, rate, last, totals = nil, nil, nil, nil
        lastError = "没有活动的网络接口"
        ctx.update()
        return
    end

    task = hs.task.new("/usr/sbin/netstat", function(code, out)
        task = nil
        local rx, tx = nil, nil
        if code == 0 then rx, tx = parse(out or "") end
        if not rx then
            lastError = "netstat 读取失败: " .. name
            ctx.update()
            return
        end
        lastError = nil

        local t = hs.timer.absoluteTime() / 1e9
        if last and last.iface == name and rx >= last.rx and tx >= last.tx then
            local dt = t - last.t
            if dt > 0 then
                rate = {rx = (rx - last.rx) / dt, tx = (tx - last.tx) / dt}
                peak.rx = math.max(peak.rx, rate.rx)
                peak.tx = math.max(peak.tx, rate.tx)
            end
        elseif last and last.iface ~= name then
            rate = nil -- first sample on a new interface: no delta yet
        end
        last = {iface = name, rx = rx, tx = tx, t = t}
        iface = name
        totals = {rx = rx, tx = tx}
        ctx.update()
    end, {"-ibn", "-I", name})

    if not task:start() then
        task = nil
        lastError = "无法启动 netstat"
    end
end

-- Two monospace lines in one image. With no colour it is a template: macOS
-- tints the alpha mask to the menu-bar foreground, which handles light/dark
-- mode. With a colour on either line the caller must not mark it a template.
local function stackedImage(up, down, upColor, downColor)
    local font = M.config.font
    local plain = (upColor or downColor) and M.config.plainColor or
                      {white = 0, alpha = 1}
    local top = hs.styledtext.new("↑" .. up, {font = font, color = upColor or plain})
    local bottom = hs.styledtext.new("↓" .. down,
                                     {font = font, color = downColor or plain})
    local a = hs.drawing.getTextDrawingSize(top)
    local b = hs.drawing.getTextDrawingSize(bottom)
    local w = math.ceil(math.max(a.w, b.w)) + 1
    local lineH = math.ceil(math.max(a.h, b.h))
    local h = math.max(22, lineH * 2)
    local y0 = (h - lineH * 2) / 2

    local c = hs.canvas.new({x = 0, y = 0, w = w, h = h})
    c[1] = {type = "text", text = top, frame = {x = 0, y = y0, w = w, h = lineH}}
    c[2] = {type = "text", text = bottom,
            frame = {x = 0, y = y0 + lineH, w = w, h = lineH}}
    local img = c:imageFromCanvas()
    c:delete()
    return img
end

-- Widget ---------------------------------------------------------------------

function M.start(ctx)
    last, rate, iface, totals, lastError = nil, nil, nil, nil, nil
    peak = {rx = 0, tx = 0}
    sample(ctx)
    timer = hs.timer.doEvery(ctx.config.sampleEvery, function() sample(ctx) end)
end

function M.stop()
    if timer then timer:stop() end
    if task and task:isRunning() then task:terminate() end
    timer, task = nil, nil
end

function M.render(ctx)
    local up = rateText(rate and rate.tx)
    local down = rateText(rate and rate.rx)

    local tooltip = lastError or
                        string.format("%s  ↑ %s/s  ↓ %s/s", iface or "-",
                                      (up:gsub("^%s+", "")),
                                      (down:gsub("^%s+", "")))

    local tiers = ctx.config.colors or nil
    local upColor = rateColor(rate and rate.tx, tiers)
    local downColor = rateColor(rate and rate.rx, tiers)

    if ctx.config.layout == "inline" then
        local function part(text, color)
            local attrs = {font = ctx.config.inlineFont}
            if color then attrs.color = color end
            return hs.styledtext.new(text, attrs)
        end
        return {
            title = part("↓" .. down, downColor) .. part(" ") ..
                part("↑" .. up, upColor),
            tooltip = tooltip
        }
    end
    return {
        icon = stackedImage(up, down, upColor, downColor),
        template = upColor == nil and downColor == nil,
        tooltip = tooltip
    }
end

function M.menu(ctx)
    local items = {}
    if lastError then
        items[#items + 1] = {title = lastError, disabled = true}
    end
    items[#items + 1] = {
        title = "接口  " .. (iface or "-") ..
            (ctx.config.interface and "（固定）" or "（自动）"),
        disabled = true
    }
    if rate then
        items[#items + 1] = {
            title = string.format("当前  ↑ %s/s   ↓ %s/s", bytesText(rate.tx),
                                  bytesText(rate.rx)),
            disabled = true
        }
    end
    items[#items + 1] = {
        title = string.format("峰值  ↑ %s/s   ↓ %s/s", bytesText(peak.tx),
                              bytesText(peak.rx)),
        disabled = true
    }
    if totals then
        items[#items + 1] = {
            title = string.format("开机以来  ↑ %s   ↓ %s", bytesText(totals.tx),
                                  bytesText(totals.rx)),
            disabled = true
        }
    end
    items[#items + 1] = {
        title = "清零峰值",
        fn = function() peak = {rx = 0, tx = 0} end
    }
    return items
end

return M
