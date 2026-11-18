-- Transient keystroke overlay. Configuration may be overridden in init.local.lua.
local M = {}
M.config = {
    enabled = false,
    hotkey = { mods = { "ctrl", "alt", "cmd" }, key = "k" },
    target = "focused", -- focused | mouse | mouseScreen
    position = "bottomLeft", -- topLeft | topRight | bottomLeft | bottomRight | center
    margin = 24,
    types = { shortcuts = true, text = false, special = true, mouse = false },
    sequenceDelay = 0.5, -- inactivity before starting a new text line
    linger = 2.0, -- seconds before fading
    fadeDuration = 0.2,
    moveDuration = 0.15,
    maxRows = 6,
    repeatMode = "normal", -- normal | badge
    textKeyMode = "input", -- input | physical (US ANSI positions)
    maxTextLength = 200, -- maximum Unicode code points kept in memory
    fontSize = 42,
    colors = { background = { white = 0, alpha = 0.8 }, text = { white = 1, alpha = 1 } },
}

local tap, binding, watchdog, animationTimer
local active = false
local rows, currentTextRow, lastRepeatRow = {}, nil, nil
local special = {
    return_ = "↩", ["return"] = "↩", tab = "⇥", space = "␣", delete = "⌫",
    forwarddelete = "⌦", padenter = "↩", padclear = "⌧", help = "?⃝", escape = "⎋", left = "←", right = "→", up = "↑", down = "↓",
    home = "↖", ["end"] = "↘", pageup = "⇞", pagedown = "⇟",
}
local function windowFrame()
    if M.config.target == "mouseScreen" then
        local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
        return screen:frame(), screen
    end
    local win
    if M.config.target == "mouse" then
        local p = hs.mouse.absolutePosition()
        for _, candidate in ipairs(hs.window.orderedWindows()) do
            local f = candidate:frame()
            if candidate:isStandard() and p.x >= f.x and p.x < f.x + f.w and p.y >= f.y and p.y < f.y + f.h then
                win = candidate
                break
            end
        end
    else
        win = hs.window.focusedWindow()
    end
    if win then return win:frame(), win:screen() end
    local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
    return screen:frame(), screen
end

-- Each line has its own canvas and expiry, so old lines can move and fade independently.
local function clearRows()
    if animationTimer then animationTimer:stop(); animationTimer = nil end
    for _, row in ipairs(rows) do row.canvas:delete() end
    rows, currentTextRow, lastRepeatRow = {}, nil, nil
end

local superscriptDigits = { ["0"] = "⁰", ["1"] = "¹", ["2"] = "²", ["3"] = "³", ["4"] = "⁴", ["5"] = "⁵", ["6"] = "⁶", ["7"] = "⁷", ["8"] = "⁸", ["9"] = "⁹" }
local function countBadge(count)
    return (tostring(count):gsub("%d", superscriptDigits))
end
local function compactText(text)
    local parts, previous, count = {}, nil, 0
    local function flush()
        if previous then parts[#parts + 1] = previous .. (count > 1 and countBadge(count) or "") end
    end
    for _, code in utf8.codes(text) do
        local char = utf8.char(code)
        if char == previous then count = count + 1 else flush(); previous, count = char, 1 end
    end
    flush()
    return table.concat(parts)
end
local function displayText(row, text)
    if M.config.repeatMode ~= "badge" then return text end
    if row.kind == "text" then return compactText(text) end
    return text .. ((row.repeatCount or 1) > 1 and countBadge(row.repeatCount) or "")
end

local function layoutRows()
    local cfg = M.config
    local bounds, screen = windowFrame()
    if not screen then return end
    local visible = screen:frame()
    local left, top = math.max(bounds.x, visible.x), math.max(bounds.y, visible.y)
    local right, bottom = math.min(bounds.x + bounds.w, visible.x + visible.w), math.min(bounds.y + bounds.h, visible.y + visible.h)
    if right <= left or bottom <= top then left, top, right, bottom = visible.x, visible.y, visible.x + visible.w, visible.y + visible.h end
    local h = math.min(cfg.fontSize * 1.8, bottom - top)
    local stride, margin = h + 6, math.max(0, cfg.margin)
    for i, row in ipairs(rows) do
        local rawText = row.text
        local text = rawText and displayText(row, rawText)
        local size = not row.mouseButton and hs.drawing.getTextDrawingSize(text, { size = cfg.fontSize })
        local maxWidth = math.max(1, right - left - 24)
        while size and size.w > maxWidth and utf8.len(rawText) and utf8.len(rawText) > 1 do
            rawText = rawText:sub(utf8.offset(rawText, 2))
            text = displayText(row, rawText)
            size = hs.drawing.getTextDrawingSize(text, { size = cfg.fontSize })
        end
        local w = math.min(math.max((size and size.w or cfg.fontSize) + 24, 42), right - left)
        local x = cfg.position:find("Right") and right - w - margin or left + margin
        local baseY = cfg.position:find("top") and top + margin + (i - 1) * stride or bottom - h - margin - (#rows - i) * stride
        if cfg.position == "center" then x, baseY = left + (right - left - w) / 2, top + (bottom - top - h) / 2 - (#rows - i) * stride end
        x, baseY = math.max(left, math.min(x, right - w)), math.max(top, math.min(baseY, bottom - h))
        local oldFrame = row.canvas:frame()
        row.fromY = row.placed and oldFrame.y or baseY
        row.targetY, row.moveStarted, row.placed = baseY, hs.timer.secondsSinceEpoch(), true
        row.canvas:frame({ x = x, y = row.fromY, w = w, h = h })
        local elements = { { type = "rectangle", action = "fill", roundedRectRadii = { xRadius = 7, yRadius = 7 }, fillColor = cfg.colors.background } }
        if row.mouseButton then
            local mw, mh = cfg.fontSize * 0.75, cfg.fontSize * 1.12
            local mx, my = (w - mw) / 2, (h - mh) / 2
            local outline, radii = { x = mx, y = my, w = mw, h = mh }, { xRadius = mw / 2, yRadius = mw / 2 }
            if row.mouseButton == "left" or row.mouseButton == "right" or row.mouseButton == "middle" then
                elements[#elements + 1] = { type = "rectangle", action = "clip", roundedRectRadii = radii, frame = outline }
                elements[#elements + 1] = { type = "rectangle", action = "fill", fillColor = cfg.colors.text,
                    frame = { x = row.mouseButton == "right" and mx + mw / 2 or mx, y = my,
                        w = row.mouseButton == "middle" and mw or mw / 2, h = mh } }
                elements[#elements + 1] = { type = "resetClip" }
            end
            elements[#elements + 1] = { type = "rectangle", action = "stroke", strokeColor = cfg.colors.text, strokeWidth = 1.5, roundedRectRadii = radii, frame = outline }
        else
            elements[#elements + 1] = { type = "text", text = text, textColor = cfg.colors.text, textSize = cfg.fontSize,
                textAlignment = "center", frame = { x = 6, y = (h - cfg.fontSize * 1.3) / 2, w = w - 12, h = cfg.fontSize * 1.3 } }
        end
        row.canvas:replaceElements(elements):show()
    end
end

local function animateRows()
    local now, cfg = hs.timer.secondsSinceEpoch(), M.config
    for i = #rows, 1, -1 do
        local row = rows[i]
        local elapsed = now - row.updatedAt
        local fade = math.max(0, cfg.fadeDuration)
        if elapsed >= cfg.linger + fade then
            if currentTextRow == row then currentTextRow = nil end
            if lastRepeatRow == row then lastRepeatRow = nil end
            row.canvas:delete(); table.remove(rows, i)
        else
            local opacity = elapsed <= cfg.linger and 1 or 1 - (elapsed - cfg.linger) / math.max(fade, 0.001)
            row.canvas:alpha(math.max(0, math.min(1, opacity)))
            local t = math.min(1, (now - row.moveStarted) / math.max(cfg.moveDuration, 0.001))
            local f = row.canvas:frame()
            f.y = row.fromY + (row.targetY - row.fromY) * (1 - (1 - t) * (1 - t))
            row.canvas:frame(f)
        end
    end
    if #rows == 0 and animationTimer then animationTimer:stop(); animationTimer = nil end
end

local function show(text, mouseButton, row, kind, repeatCount)
    if not active then return end
    if not row then
        local c = hs.canvas.new({ x = 0, y = 0, w = 1, h = 1 })
        c:level(hs.canvas.windowLevels.overlay)
        c:behavior({ "canJoinAllSpaces", "fullScreenAuxiliary", "stationary", "ignoresCycle" })
        c:clickActivating(false)
        row = { canvas = c }
        rows[#rows + 1] = row
        while #rows > math.max(1, M.config.maxRows) do
            local old = table.remove(rows, 1)
            if currentTextRow == old then currentTextRow = nil end
            if lastRepeatRow == old then lastRepeatRow = nil end
            old.canvas:delete()
        end
    end
    row.text, row.mouseButton, row.kind, row.repeatCount, row.updatedAt = text, mouseButton, kind, repeatCount, hs.timer.secondsSinceEpoch()
    row.canvas:alpha(1)
    layoutRows()
    if not animationTimer then animationTimer = hs.timer.doEvery(1 / 30, animateRows) end
    return row
end

-- macOS virtual key codes identify physical key positions. These labels follow
-- a US ANSI keyboard, independently of the current input method or layout.
local physicalKeys = {
    [0] = {"a", "A"}, [1] = {"s", "S"}, [2] = {"d", "D"}, [3] = {"f", "F"},
    [4] = {"h", "H"}, [5] = {"g", "G"}, [6] = {"z", "Z"}, [7] = {"x", "X"},
    [8] = {"c", "C"}, [9] = {"v", "V"}, [11] = {"b", "B"}, [12] = {"q", "Q"},
    [13] = {"w", "W"}, [14] = {"e", "E"}, [15] = {"r", "R"}, [16] = {"y", "Y"},
    [17] = {"t", "T"}, [18] = {"1", "!"}, [19] = {"2", "@"}, [20] = {"3", "#"},
    [21] = {"4", "$"}, [22] = {"6", "^"}, [23] = {"5", "%"}, [24] = {"=", "+"},
    [25] = {"9", "("}, [26] = {"7", "&"}, [27] = {"-", "_"}, [28] = {"8", "*"},
    [29] = {"0", ")"}, [30] = {"]", "}"}, [31] = {"o", "O"}, [32] = {"u", "U"},
    [33] = {"[", "{"}, [34] = {"i", "I"}, [35] = {"p", "P"}, [37] = {"l", "L"},
    [38] = {"j", "J"}, [39] = {"'", "\""}, [40] = {"k", "K"}, [41] = {";", ":"},
    [42] = {"\\", "|"}, [43] = {",", "<"}, [44] = {"/", "?"}, [45] = {"n", "N"},
    [46] = {"m", "M"}, [47] = {".", ">"}, [50] = {"`", "~"},
    [65] = {".", "."}, [67] = {"*", "*"}, [69] = {"+", "+"}, [75] = {"/", "/"},
    [78] = {"-", "-"}, [81] = {"=", "="}, [82] = {"0", "0"}, [83] = {"1", "1"},
    [84] = {"2", "2"}, [85] = {"3", "3"}, [86] = {"4", "4"}, [87] = {"5", "5"},
    [88] = {"6", "6"}, [89] = {"7", "7"}, [91] = {"8", "8"}, [92] = {"9", "9"},
}

local function keyText(event)
    local flags, code = event:getFlags(), event:getKeyCode()
    local name = hs.keycodes.map[code] or ""
    local isShortcut = flags.cmd or flags.alt or flags.ctrl
    local isSpecial = special[name] ~= nil or name:match("^f%d+$") ~= nil
    local allowed = M.config.types
    if isShortcut and not allowed.shortcuts then return end
    local isText = not isShortcut and (not isSpecial or (name == "space" and allowed.text))
    if not isShortcut and isSpecial and not isText and not allowed.special then return end
    if isText and not allowed.text then return end
    local key = special[name]
    if not key then
        if isSpecial then key = name:upper()
        elseif isShortcut then key = (event:getCharacters(true) or ""):upper()
        elseif M.config.textKeyMode == "physical" then
            local labels = physicalKeys[code]
            key = labels and labels[flags.shift and 2 or 1] or ""
        else key = event:getCharacters() or "" end
    end
    if key == "" or key:match("^%c") then
        if isText then return end
        key = name:upper()
    end
    if key == "" then return end
    local mods = ""
    if flags.ctrl then mods = mods .. "⌃" end
    if flags.alt then mods = mods .. "⌥" end
    if flags.shift and (isShortcut or isSpecial) then mods = mods .. "⇧" end
    if flags.cmd then mods = mods .. "⌘" end
    return mods .. key, isText and "text" or "action", isShortcut
end

-- End a text run after showing a space or punctuation, including common CJK punctuation.
local punctuation = {}
for _, code in utf8.codes("，。！？、；：‘’“”（）【】《》〈〉「」『』〔〕［］｛｝…—～·﹏．，｡､！？：；＂＇／＼＠＃＄％＆＊＋＝－＿｜") do
    punctuation[utf8.char(code)] = true
end
local function endsTextRun(label)
    if label == "␣" then return true end
    local last
    for _, code in utf8.codes(label) do last = utf8.char(code) end
    return last ~= nil and (punctuation[last] == true or last:match("^[%p]$") ~= nil)
end

local function handleKey(event)
    local label, kind = keyText(event)
    if not label then
        lastRepeatRow = nil
        local flags = event:getFlags()
        if flags.cmd or flags.alt or flags.ctrl then currentTextRow = nil end
        return
    end
    local now = hs.timer.secondsSinceEpoch()
    local repeating = M.config.repeatMode == "badge" and lastRepeatRow and lastRepeatRow.repeatLabel == label
        and lastRepeatRow.kind == kind and now - lastRepeatRow.updatedAt <= M.config.sequenceDelay
    if kind == "text" then
        if currentTextRow and now - currentTextRow.updatedAt > M.config.sequenceDelay then currentTextRow = nil end
        local row = currentTextRow or (repeating and lastRepeatRow or nil)
        local text = (row and row.text or "") .. label
        local length = utf8.len(text)
        local limit = math.max(1, math.floor(M.config.maxTextLength))
        if length and length > limit then text = text:sub(utf8.offset(text, length - limit + 1)) end
        currentTextRow = show(text, nil, row, kind)
        currentTextRow.repeatLabel = label
        lastRepeatRow = currentTextRow
        if endsTextRun(label) then currentTextRow = nil end
    else
        currentTextRow = nil
        local row = repeating and lastRepeatRow or nil
        local count = row and (row.repeatCount or 1) + 1 or 1
        lastRepeatRow = show(label, nil, row, kind, count)
        lastRepeatRow.repeatLabel = label
    end
end

function M.setEnabled(enabled)
    active = enabled
    if tap then if active then tap:start() else tap:stop() end end
    if not active then clearRows() end
end

function M.toggle()
    M.setEnabled(not active)
    hs.alert.show("按键提示：" .. (active and "开启" or "关闭"), 1)
end
function M.stop()
    M.setEnabled(false)
    if binding then binding:delete(); binding = nil end
    if watchdog then watchdog:stop(); watchdog = nil end
    tap = nil
end
function M.start()
    M.stop()
    local types = hs.eventtap.event.types
    tap = hs.eventtap.new({ types.keyDown, types.leftMouseDown, types.rightMouseDown, types.otherMouseDown }, function(event)
        if event:getType() == types.keyDown then
            hs.timer.doAfter(0, function() if active then handleKey(event) end end)
            return false
        end
        local mouseButton
        if M.config.types.mouse then
            if event:getType() == types.leftMouseDown then mouseButton = "left"
            elseif event:getType() == types.rightMouseDown then mouseButton = "right"
            elseif event:getType() == types.otherMouseDown then
                mouseButton = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) == 2 and "middle" or "other"
            end
        end
        if mouseButton then hs.timer.doAfter(0, function()
            if active then currentTextRow = nil; lastRepeatRow = nil; show(nil, mouseButton) end
        end) end
        return false
    end)
    local hotkey = M.config.hotkey
    if hotkey then binding = hs.hotkey.bind(hotkey.mods, hotkey.key, M.toggle) end
    M.setEnabled(M.config.enabled)
    watchdog = hs.timer.doEvery(5, function() if active and tap and not tap:isEnabled() then tap:start() end end)
end
return M
