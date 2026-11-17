-- Adjust the display under the mouse through native brightness or DDC.
local M = { config = {
    cli = nil, -- Optional per-machine absolute path; nil searches common Homebrew locations.
    step = 5, timeout = 8, reconnectDelay = 3,
} }

local queue, hotkeys, keyTap, watchdog, active = {}, {}, nil, nil, nil
local screenWatcher, restoreTimers, connected, revisions = nil, {}, {}, {}
local generation = 0
local alertID
local panel, panelTimer
local ddc = {} -- uuid -> { value, written, target, max, pending }
local settingsKey = "display-brightness.saved-v1"
local saved = {}
local notify

local function findCLI()
    local paths = M.config.cli and { M.config.cli } or { "/opt/homebrew/bin/m1ddc", "/usr/local/bin/m1ddc" }
    for _, path in ipairs(paths) do
        local attrs = type(path) == "string" and path:sub(1, 1) == "/" and hs.fs.attributes(path)
        if attrs and attrs.mode == "file" and attrs.permissions and attrs.permissions:find("x", 1, true) then
            return path
        end
    end
end

local function remember(uuid, mode, value)
    saved[uuid] = { mode = mode, value = value }
    local ok = pcall(hs.settings.set, settingsKey, saved)
    if not ok then notify("亮度已调整，但保存失败", uuid) end
end

local function showBrightness(uuid, name, value, maximum)
    local screen = hs.screen.find(uuid)
    if not screen then return end
    if alertID then hs.alert.closeSpecific(alertID, 0); alertID = nil end
    local area = screen:frame()
    local width, height = 200, 156
    local frame = { x = area.x + (area.w - width) / 2,
        y = area.y + area.h - height - math.min(100, area.h * 0.12), w = width, h = height }
    if not panel then
        panel = hs.canvas.new(frame):level(hs.canvas.windowLevels.overlay)
        panel:behaviorAsLabels({ "canJoinAllSpaces", "transient", "ignoresCycle" })
        panel:clickActivating(false)
    else
        panel:frame(frame)
    end

    local fraction = maximum and maximum > 0 and math.max(0, math.min(1, value / maximum)) or nil
    local label = fraction and string.format("%d%%", math.floor(fraction * 100 + 0.5)) or tostring(value)
    local elements = {
        { type = "rectangle", action = "fill", frame = { x = 0, y = 0, w = width, h = height },
          roundedRectRadii = { xRadius = 21, yRadius = 21 }, fillColor = { white = 0.10, alpha = 0.88 } },
        { type = "text", text = name, textAlignment = "center", textSize = 12,
          textColor = { white = 1, alpha = 0.72 }, frame = { x = 10, y = 11, w = 180, h = 18 } },
        { type = "circle", action = "fill", center = { x = 100, y = 61 }, radius = 13,
          fillColor = { white = 1, alpha = 0.96 } },
        { type = "text", text = label, textAlignment = "center", textSize = 15,
          textColor = { white = 1, alpha = 0.95 }, frame = { x = 15, y = 94, w = 170, h = 20 } },
    }
    for i = 0, 7 do
        local angle = i * math.pi / 4
        elements[#elements + 1] = { type = "segments", action = "stroke", strokeWidth = 3,
            strokeColor = { white = 1, alpha = 0.96 }, coordinates = {
                { x = 100 + math.cos(angle) * 19, y = 61 + math.sin(angle) * 19 },
                { x = 100 + math.cos(angle) * 26, y = 61 + math.sin(angle) * 26 },
            } }
    end
    local filled = fraction and math.floor(fraction * 16 + 0.5) or 0
    for i = 1, 16 do
        elements[#elements + 1] = { type = "rectangle", action = "fill",
            frame = { x = 29 + (i - 1) * 9, y = 124, w = 7, h = 6 },
            roundedRectRadii = { xRadius = 1, yRadius = 1 },
            fillColor = { white = 1, alpha = i <= filled and 0.95 or 0.22 } }
    end
    panel:replaceElements(elements):show()
    if panelTimer then panelTimer:stop() end
    panelTimer = hs.timer.doAfter(1.5, function()
        if panel then panel:hide(0.2) end
        panelTimer = nil
    end)
end

notify = function(message, uuid)
    if panelTimer then panelTimer:stop(); panelTimer = nil end
    if panel then panel:hide() end
    if alertID then hs.alert.closeSpecific(alertID, 0) end
    local screen = uuid and hs.screen.find(uuid) or hs.mouse.getCurrentScreen()
    if screen then
        alertID = hs.alert.show(message, { fadeInDuration = 0 }, screen, 2)
    else
        alertID = hs.alert.show(message, 2)
    end
end
local processQueue

local function run(args, callback, epoch, uuid)
    local job = {}
    local executable = findCLI()
    if not executable then callback(-2, ""); return end
    local command = hs.task.new(executable, function(code, out)
        if job.timer then job.timer:stop(); job.timer = nil end
        if epoch ~= generation or job.expired then return end
        active = nil
        callback(code, out)
    end, args)
    if not command then callback(-1, ""); return end
    job.command = command
    active = job
    if not command:start() then active = nil; callback(-1, ""); return end
    job.timer = hs.timer.doAfter(M.config.timeout, function()
        if epoch ~= generation or active ~= job then return end
        job.expired = true
        active = nil
        queue = {}
        command:terminate()
        notify("DDC 命令超时，亮度状态未确认", uuid)
    end)
end

local function clamp(value, maximum)
    return math.max(0, math.min(maximum or 100, value))
end

-- Read the current DDC value and maximum once per connection. A monitor that is still
-- applying a write answers a read with 0, so a 0 is re-read once before it is trusted.
local function learn(uuid, target, epoch, callback)
    local function readValue(retried)
        run({ "display", target, "get", "luminance" }, function(code, output)
            local value = code == 0 and output and tonumber(output:match("^%s*(%d+)%s*$"))
            if value == 0 and not retried then
                local wait = {}
                wait.timer = hs.timer.doAfter(0.3, function()
                    if epoch ~= generation or active ~= wait then return end
                    active = nil
                    readValue(true)
                end)
                active = wait -- hold the queue while waiting
                return
            end
            if not value then callback(nil); return end
            run({ "display", target, "max", "luminance" }, function(maxCode, maxOutput)
                local maximum = maxCode == 0 and maxOutput and tonumber(maxOutput:match("^%s*(%d+)%s*$"))
                maximum = maximum and maximum > 0 and maximum or 100
                -- A garbled reply (25600 = 100 in the high byte, seen after toggling HDR)
                -- is above the maximum; never build a target on it.
                if value > maximum then callback(nil); return end
                callback(value, maximum)
            end, epoch, uuid)
        end, epoch, uuid)
    end
    readValue(false)
end

local function queued(uuid)
    for _, entry in ipairs(queue) do
        if entry.uuid == uuid and entry.sync then return true end
    end
    return false
end

processQueue = function()
    if active or #queue == 0 then return end
    local item = table.remove(queue, 1)
    if item.restore and (revisions[item.uuid] or 0) ~= item.revision then processQueue(); return end
    local screen = hs.screen.find(item.uuid)
    if not screen or screen:getUUID():upper() ~= item.uuid:upper() then
        ddc[item.uuid] = nil
        notify("目标显示器已断开，未调整", item.uuid)
        processQueue(); return
    end
    local name = screen:name() or "显示器"
    local native = screen:getBrightness()
    if type(native) == "number" then
        if item.restore and item.restore.mode ~= "native" then processQueue(); return end
        local value = item.restore and item.restore.value or math.max(0, math.min(1, native + item.delta / 100))
        local ok = pcall(function() screen:setBrightness(value) end)
        local actual = screen:getBrightness()
        if not ok or type(actual) ~= "number" or math.abs(actual - value) > 0.02 then
            notify(name .. "亮度调整未确认", item.uuid)
        else
            if not item.restore then remember(item.uuid, "native", actual) end
            showBrightness(item.uuid, name, actual, 1)
        end
        processQueue(); return
    end
    if item.restore and item.restore.mode ~= "ddc" then processQueue(); return end
    local epoch = generation
    local target = "uuid=" .. item.uuid
    local state = ddc[item.uuid]
    if not state then state = { pending = 0 }; ddc[item.uuid] = state end
    if item.restore then
        state.target = clamp(item.restore.value, state.max or 65535)
        state.restoring = true
    end

    if not item.restore and not state.value then
        learn(item.uuid, target, epoch, function(value, maximum)
            if ddc[item.uuid] ~= state then processQueue(); return end
            if not value then
                ddc[item.uuid] = nil
                notify(name .. " DDC 读取亮度失败", item.uuid)
                processQueue(); return
            end
            state.value, state.written, state.max = value, value, maximum
            state.target = clamp(value + state.pending, maximum)
            state.pending = 0
            showBrightness(item.uuid, name, state.target, maximum)
            table.insert(queue, 1, { uuid = item.uuid, sync = true })
            processQueue()
        end)
        return
    end

    -- Always write an absolute value: `chg` reads before it writes, and a read during a
    -- previous write returns 0, which turned +5 into a jump to 5.
    if state.target == nil or state.target == state.written then processQueue(); return end
    local value = state.target
    run({ "display", target, "set", "luminance", tostring(value) }, function(code, output)
        if code == -2 then
            notify("未找到 m1ddc；请安装或设置本机路径", item.uuid)
            processQueue(); return
        end
        if ddc[item.uuid] ~= state then processQueue(); return end
        local written = output and tonumber(output:match("Writing%s+(%d+)"))
        if code ~= 0 or written ~= value then
            ddc[item.uuid] = nil -- re-read the monitor on the next press
            notify(name .. " DDC 调整失败", item.uuid)
            processQueue(); return
        end
        if state.restoring then
            -- Forget the value but keep presses made during the restore: the next
            -- sync re-reads the monitor (and its maximum) and applies them on top.
            state.restoring, state.value, state.written = nil, nil, nil
            if state.pending ~= 0 and not queued(item.uuid) then
                table.insert(queue, 1, { uuid = item.uuid, sync = true })
            end
            processQueue(); return
        end
        state.written, state.value = value, value
        remember(item.uuid, "ddc", value)
        if state.target ~= state.written then
            table.insert(queue, 1, { uuid = item.uuid, sync = true })
        end
        processQueue()
    end, epoch, item.uuid)
end

function M.adjustMouseScreen(delta)
    local screen = hs.mouse.getCurrentScreen()
    local uuid = screen and screen:getUUID()
    if not uuid then notify("无法识别鼠标所在的显示器"); return end
    revisions[uuid] = (revisions[uuid] or 0) + 1
    if restoreTimers[uuid] then restoreTimers[uuid]:stop(); restoreTimers[uuid] = nil end
    if type(screen:getBrightness()) == "number" then
        queue[#queue + 1] = { uuid = uuid, delta = delta }
    else
        -- DDC: move the target at once and show it; the queue writes only the latest
        -- target, so a burst of presses becomes one or two writes instead of one each.
        local state = ddc[uuid]
        if not state then state = { pending = 0 }; ddc[uuid] = state end
        if state.value then
            state.target = clamp((state.target or state.value) + delta, state.max)
            showBrightness(uuid, screen:name() or "显示器", state.target, state.max)
        else
            state.pending = state.pending + delta
        end
        if not queued(uuid) then queue[#queue + 1] = { uuid = uuid, sync = true } end
    end
    local epoch = generation
    hs.timer.doAfter(0, function() if epoch == generation then processQueue() end end)
end

local function screenSet()
    local result = {}
    for _, screen in ipairs(hs.screen.allScreens()) do
        local uuid = screen:getUUID()
        if uuid then result[uuid] = true end
    end
    return result
end

local function validSaved(entry)
    if type(entry) ~= "table" or type(entry.value) ~= "number" or entry.value ~= entry.value then return false end
    if entry.mode == "native" then return entry.value >= 0 and entry.value <= 1 end
    if entry.mode == "ddc" then return entry.value >= 0 and entry.value <= 65535 and entry.value % 1 == 0 end
    return false
end

local function screenChanged()
    local current = screenSet()
    for uuid in pairs(connected) do
        if not current[uuid] then
            ddc[uuid] = nil
            revisions[uuid] = (revisions[uuid] or 0) + 1
            if restoreTimers[uuid] then restoreTimers[uuid]:stop(); restoreTimers[uuid] = nil end
        end
    end
    for uuid in pairs(current) do
        local entry = saved[uuid]
        if not connected[uuid] and validSaved(entry) then
            local revision, epoch = revisions[uuid] or 0, generation
            restoreTimers[uuid] = hs.timer.doAfter(M.config.reconnectDelay, function()
                restoreTimers[uuid] = nil
                if epoch ~= generation or not connected[uuid] or (revisions[uuid] or 0) ~= revision then return end
                queue[#queue + 1] = { uuid = uuid, restore = { mode = entry.mode, value = entry.value }, revision = revision }
                processQueue()
            end)
        end
    end
    connected = current
end

function M.start()
    M.stop()
    local stored = hs.settings.get(settingsKey)
    saved = type(stored) == "table" and stored or {}
    connected = screenSet()
    screenWatcher = hs.screen.watcher.new(screenChanged):start()
    if not findCLI() then notify("未找到 m1ddc：外接显示器 DDC 控制不可用") end
    local types = hs.eventtap.event.types
    local keys = { [hs.keycodes.map.f1] = -1, [hs.keycodes.map.f2] = 1,
        [hs.keycodes.map.f14] = -1, [hs.keycodes.map.f15] = 1 }
    keyTap = hs.eventtap.new({ types.systemDefined, types.keyDown, types.keyUp }, function(event)
        local flags = event:getFlags()
        if flags.cmd or flags.alt or flags.ctrl or flags.shift then return false end
        local direction, down
        if event:getType() == types.systemDefined then
            local key = event:systemKey()
            if key.key == "BRIGHTNESS_DOWN" then direction = -1
            elseif key.key == "BRIGHTNESS_UP" then direction = 1 end
            down = key.down
        else
            direction = keys[event:getKeyCode()]
            down = event:getType() == types.keyDown
        end
        if not direction then return false end
        if down then M.adjustMouseScreen(direction * M.config.step) end
        return true
    end):start()
    local mods = { "ctrl", "alt", "cmd" }
    local down = hs.hotkey.bind(mods, "[", function() M.adjustMouseScreen(-M.config.step) end)
    local up = hs.hotkey.bind(mods, "]", function() M.adjustMouseScreen(M.config.step) end)
    if down then hotkeys[#hotkeys + 1] = down end
    if up then hotkeys[#hotkeys + 1] = up end
    if not down or not up then notify("显示器亮度组合快捷键注册失败") end
    watchdog = hs.timer.doEvery(10, function()
        if keyTap and not keyTap:isEnabled() then keyTap:start() end
    end)
end

function M.stop()
    generation = generation + 1
    if keyTap then keyTap:stop(); keyTap = nil end
    if watchdog then watchdog:stop(); watchdog = nil end
    if screenWatcher then screenWatcher:stop(); screenWatcher = nil end
    for _, timer in pairs(restoreTimers) do timer:stop() end
    restoreTimers, connected, revisions = {}, {}, {}
    if panelTimer then panelTimer:stop(); panelTimer = nil end
    if panel then panel:delete(); panel = nil end
    ddc = {}
    if alertID then hs.alert.closeSpecific(alertID, 0); alertID = nil end
    for _, key in ipairs(hotkeys) do key:delete() end
    hotkeys = {}
    queue = {}
    if active and active.timer then active.timer:stop() end
    -- A write already sent to a monitor may still complete; do not retry it.
    active = nil
end

function M.toggle()
    if keyTap then M.stop() else M.start() end
end

return M
