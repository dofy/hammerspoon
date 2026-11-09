--- === statusbar.kaon ===
---
--- Kaon Router spend against the daily budget, read from the Admin API.
--- Mounted by `statusbar.lua`; see that file for the widget contract.
---
--- Which number is "today's usage":
---   `/users/me/budget` is authoritative. It is the counter the console's own
---   /keys banner shows and the one that actually gates requests.
---   `/usage/summary` is Prometheus-derived and does not reconcile with it:
---   on 2026-11-09 the budget counter read 46.06 USD while the summary's
---   by_day bucket for the same date read 54.23 USD. The summary is therefore
---   used only for the breakdown in the dropdown, and labelled as such.
---
--- Range tokens are 5m | 1h | 24h | 7d | 30d, but `range=24h` is unusable: it
--- comes back with five one-minute buckets (07:14..07:18) instead of a day, so
--- the breakdown uses `range=7d`, whose buckets really are whole days. There is
--- no way to get a by_model breakdown for today alone. `source=starrocks` is a
--- T+1 warehouse — its newest bucket is yesterday — so it is never used here.
---
--- Failure handling: a 401/403, a suspended token or a throttle is fatal. The
--- widget stops issuing requests rather than hammering the control plane, since
--- `automation_protocol_throttled` and `automation_token_suspended` are stop
--- signals in the Kaon admin contract, not retry signals. Clear the state by
--- toggling the widget off and on, or by reloading Hammerspoon.

local M = {}

M.label = "Kaon"
M.interval = 300 -- seconds; usage is not second-scale data

M.config = {
    baseURL = "https://kaon-router-admin-api.kaonai.com/api/v1",
    -- File holding the kaon_pat_* token, read once at start(). Keep it at 600.
    tokenPath = os.getenv("HOME") .. "/.config/kaon/token",
    -- Fractions of the daily budget at which the title changes colour. The
    -- budget itself is not in the title, only in the tooltip and the dropdown.
    warnRatio = 0.7,
    critRatio = 0.9,
    -- Refresh the (heavier) usage breakdown every N timer ticks. 6 * 300s = 30m.
    summaryEvery = 6,
    -- Range token for the breakdown. 24h is broken; see the note above.
    summaryRange = "7d",
    -- Warn in the tooltip once the token is within this many days of expiry.
    expiryWarnDays = 14,
    -- Seconds added per consecutive failure, capped, before another attempt.
    backoffStep = 60,
    backoffMax = 1800,
    -- Title font. nil = the macOS menu-bar default. Override from init.lua:
    --   statusbar.config.widgetConfig.kaon = {
    --       font = {name = "Menlo", size = 13}
    --   }
    -- An unknown font name is silently ignored by hs.styledtext and the default
    -- is used, so check the name with `hs.styledtext.validFont(name)` first.
    -- Keep size <= 14: macOS does not grow the menu bar, it clips the glyphs.
    font = nil,
    -- Currency marker in front of the amount.
    symbol = "$",
    -- Decimal places on the title amount. Clamped to 0..4, because the value
    -- is spliced into a string.format spec.
    decimals = 0,
    -- Append the daily budget to the title, e.g. "$46 / $100". Off by default:
    -- the budget never changes, so it spends menu-bar width on no information.
    -- The tooltip and the dropdown always carry it.
    showBudget = false,
    -- Decimal places on that budget, and what goes between the two numbers.
    budgetDecimals = 0,
    budgetSeparator = " / ",
    -- Menu-bar icon: the console's favicon shapes from
    -- kaon-router-admin.kaonai.com/favicon.svg, with its violet plate removed.
    -- NSImage renders SVG, so no raster conversion is needed. nil or a missing
    -- file = text-only title.
    iconPath = hs.configdir .. "/statusbar/kaon.svg",
    -- Points. 16 is the usual menu-bar glyph size; the bar does not grow.
    iconSize = 16,
    -- A template image is tinted by macOS to the menu-bar foreground colour,
    -- which is what makes the icon follow light/dark mode (and the inverted
    -- look under a selected/dark menu bar). Only the alpha channel is read, so
    -- the fills in the SVG do not matter. Setting this to false bakes those
    -- fills in and the icon then disappears in one of the two modes.
    iconTemplate = true,
    -- Points between the icon and the amount inside the composed image. AppKit
    -- inserts ~17pt of its own when the icon and the title are two separate
    -- things on an NSStatusItem, and `hs.menubar` exposes no way to shrink it,
    -- so the widget draws both into one image and leaves the title empty.
    iconGap = 3
}

-- Private state
local token = nil
local budget = nil -- last successful /users/me/budget body
local summary = nil -- last successful /usage/summary body
local expiresAt = nil -- token expiry, epoch seconds
local lastOK = nil -- epoch seconds of the last successful budget read
local lastError = nil -- human-readable, token-free
local fatal = nil -- set once; stops all further requests
local failures = 0
local icon = nil -- hs.image, loaded once in start()
local nextFetch = 0
local inFlight = false
local tick = 0

-- Helpers --------------------------------------------------------------------

local function now() return os.time() end

local function readToken(path)
    local f = io.open(path, "r")
    if not f then return nil, "token file missing: " .. path end
    local raw = f:read("a")
    f:close()
    if not raw then return nil, "token file unreadable" end
    local t = raw:gsub("%s+$", ""):gsub("^%s+", "")
    if t == "" then return nil, "token file empty" end
    return t
end

-- Never put a response body in a user-visible string: it is control-plane data.
-- Only the status code and a fixed label are reported.
local function httpError(status)
    if status == 401 then return "401 token invalid or expired", true end
    if status == 403 then return "403 missing usage:read scope", true end
    if status == 429 then return "429 throttled", true end
    if status and status < 0 then return "network unreachable", false end
    return tostring(status) .. " unexpected status", false
end

local function decode(body)
    local ok, value = pcall(hs.json.decode, body)
    if not ok or type(value) ~= "table" then return nil end
    return value
end

-- A Kaon stop signal must not be retried; retrying risks token suspension.
local function isStopSignal(payload)
    local code = payload and (payload.code or payload.error)
    if type(code) ~= "string" then return false end
    return code:find("automation_protocol_throttled", 1, true) ~= nil or
               code:find("automation_token_suspended", 1, true) ~= nil or
               code:find("operation_plan_denied", 1, true) ~= nil
end

local function get(ctx, path, callback)
    local url = ctx.config.baseURL .. path
    hs.http.asyncGet(url, {Authorization = "Bearer " .. token}, function(status, body)
        if status == 200 then
            local payload = decode(body)
            if payload then return callback(payload) end
            lastError = "malformed JSON from " .. path
            return callback(nil)
        end
        local payload = decode(body)
        local message, stop = httpError(status)
        if isStopSignal(payload) then stop = true end
        lastError = path .. ": " .. message
        if stop then fatal = lastError end
        callback(nil)
    end)
end

-- Fetching --------------------------------------------------------------------

local function fetch(ctx)
    if fatal or inFlight or not token then return end
    if now() < nextFetch then return end
    inFlight = true
    tick = tick + 1

    local wantSummary = (summary == nil) or (tick % ctx.config.summaryEvery == 1)

    get(ctx, "/users/me/budget", function(payload)
        if payload then
            budget = payload
            lastOK = now()
            lastError = nil
            failures = 0
            -- Hold off until the next timer tick. Without this the ctx.update()
            -- below re-enters render and would fetch again immediately.
            nextFetch = now() + math.floor(M.interval * 0.9)
        else
            failures = failures + 1
            nextFetch = now() +
                            math.min(ctx.config.backoffMax,
                                     failures * ctx.config.backoffStep)
        end

        if wantSummary and not fatal then
            get(ctx, "/usage/summary?range=" .. ctx.config.summaryRange,
                function(s)
                    if s then summary = s end
                    inFlight = false
                    ctx.update()
                end)
        else
            inFlight = false
            ctx.update()
        end
    end)
end

-- Rendering -------------------------------------------------------------------

local function ratio()
    if not budget then return nil end
    local spend = budget.personal_daily_spend_usd
    local cap = budget.personal_daily_budget_usd
    if type(spend) ~= "number" or type(cap) ~= "number" or cap <= 0 then
        return nil
    end
    return spend / cap
end

local function titleColor(r)
    if not r then return nil end
    if r >= M.config.critRatio then
        return {red = 0.90, green = 0.20, blue = 0.20}
    end
    if r >= M.config.warnRatio then
        return {red = 0.95, green = 0.65, blue = 0.15}
    end
    return nil
end

-- A configured decimal count is spliced into a format spec, so it is clamped
-- to a plain integer in 0..4 rather than trusted.
local function places(n)
    if type(n) ~= "number" then return 0 end
    return math.max(0, math.min(4, math.floor(n)))
end

-- Icon and text in one image, so the item is only as wide as its content.
-- A template image is tinted whole by macOS, which is what carries the icon
-- *and* the text through a light/dark switch; `color` is therefore only set
-- when the spend is over a threshold, and that state alone opts out of
-- templating and paints itself.
local function compose(text, color)
    if not icon then return nil end
    local font = M.config.font or {name = ".AppleSystemUIFont", size = 13}
    local st = hs.styledtext.new(text, {font = font, color = color or
                                            {white = 0, alpha = 1}})
    local ts = hs.drawing.getTextDrawingSize(st)
    local n = M.config.iconSize
    local h = math.max(n, math.ceil(ts.h))
    local w = n + M.config.iconGap + math.ceil(ts.w)

    local c = hs.canvas.new({x = 0, y = 0, w = w, h = h})
    c[1] = {
        type = "image",
        image = icon,
        frame = {x = 0, y = (h - n) / 2, w = n, h = n},
        imageScaling = "scaleProportionally"
    }
    -- Paints the colour onto the icon's own pixels only; the icon art is
    -- monochrome, so there is nothing else to preserve.
    if color then
        c[2] = {
            type = "rectangle",
            action = "fill",
            fillColor = color,
            frame = {x = 0, y = (h - n) / 2, w = n, h = n},
            compositeRule = "sourceAtop"
        }
    end
    c[#c + 1] = {
        type = "text",
        text = st,
        frame = {
            x = n + M.config.iconGap,
            y = (h - ts.h) / 2,
            w = math.ceil(ts.w) + 1,
            h = math.ceil(ts.h)
        }
    }
    local img = c:imageFromCanvas()
    c:delete()
    return img
end

-- One image and an empty title when the icon is there, the plain styled title
-- when it is not (missing file, or iconPath set to nil).
local function titleFields(text, color)
    local img = compose(text, color)
    if img then
        -- No `title` key at all: an NSStatusItem that carries a title, even an
        -- empty one, still reserves the title's padding. The host only calls
        -- setTitle when the key is present, and whether the icon is there is
        -- decided once in start(), so this never leaves a stale title behind.
        return {icon = img, template = M.config.iconTemplate and color == nil}
    end
    return {title = styled(text, color)}
end

-- Every title goes through here so the font applies to the placeholders too,
-- not only to the amber/red spend. A plain string is returned when there is
-- nothing to style, because styledtext is userdata and costs more to build.
local function styled(text, color)
    local font = M.config.font
    if not font and not color then return text end
    local attrs = {}
    if font then attrs.font = font end
    if color then attrs.color = color end
    return hs.styledtext.new(text, attrs)
end

local function expiryNote()
    if not expiresAt then return nil end
    local days = math.floor((expiresAt - now()) / 86400)
    if days < 0 then return "token 已过期" end
    if days <= M.config.expiryWarnDays then
        return string.format("token %d 天后过期", days)
    end
    return nil
end

function M.render(ctx)
    fetch(ctx)

    if fatal then
        local t = titleFields("⚠")
        t.tooltip = "Kaon: " .. fatal
        return t
    end
    if not budget then
        local t = titleFields("…")
        t.tooltip = lastError or "Kaon: 读取中"
        return t
    end

    local spend = budget.personal_daily_spend_usd or 0
    local cap = budget.personal_daily_budget_usd
    local text = string.format("%s%." .. places(M.config.decimals) .. "f",
                               M.config.symbol, spend)
    if M.config.showBudget and type(cap) == "number" then
        text = text ..
                   string.format("%s%s%." ..
                                     places(M.config.budgetDecimals) .. "f",
                                 M.config.budgetSeparator, M.config.symbol, cap)
    end

    local tip = {string.format("今日 $%.2f", spend)}
    if cap then
        tip[#tip + 1] = string.format("预算 $%.0f  剩余 $%.2f", cap, cap - spend)
    end
    if lastError then tip[#tip + 1] = "上次失败: " .. lastError end
    local note = expiryNote()
    if note then tip[#tip + 1] = note end
    if lastOK then
        tip[#tip + 1] = "更新于 " .. os.date("%H:%M", lastOK)
    end

    local t = titleFields(text, titleColor(ratio()))
    t.tooltip = table.concat(tip, "\n")
    return t
end

-- Dropdown ---------------------------------------------------------------------

local function money(v)
    if type(v) ~= "number" then return "—" end
    return string.format("$%.2f", v)
end

-- Token and RPM/TPM counts run to nine digits, which is unreadable in a menu.
local function count(v)
    if type(v) ~= "number" then return "—" end
    if v >= 1e9 then return string.format("%.1fB", v / 1e9) end
    if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
    if v >= 1e3 then return string.format("%.1fK", v / 1e3) end
    return string.format("%d", v)
end

local function budgetLine(label, spend, cap)
    if type(cap) ~= "number" then
        return string.format("%s  %s", label, money(spend))
    end
    return string.format("%s  %s / $%.0f  (剩 %s)", label, money(spend), cap,
                         money(cap - (spend or 0)))
end

local function topN(list, n)
    local copy = {}
    for _, item in ipairs(list or {}) do copy[#copy + 1] = item end
    table.sort(copy, function(a, b)
        return (a.total_cost_usd or 0) > (b.total_cost_usd or 0)
    end)
    local out = {}
    for i = 1, math.min(n, #copy) do out[i] = copy[i] end
    return out
end

function M.menu(ctx)
    local items = {}

    if fatal then
        items[#items + 1] = {title = "已停止: " .. fatal, disabled = true}
        items[#items + 1] = {title = "-"}
        items[#items + 1] = {
            title = "重试 (清除停止状态)",
            fn = function()
                fatal, failures, nextFetch = nil, 0, 0
                ctx.update()
            end
        }
        return items
    end

    if budget then
        items[#items + 1] = {
            title = budgetLine("今日", budget.personal_daily_spend_usd,
                               budget.personal_daily_budget_usd),
            disabled = true
        }
        items[#items + 1] = {
            title = budgetLine("本周", budget.personal_weekly_spend_usd,
                               budget.personal_weekly_budget_usd),
            disabled = true
        }
        items[#items + 1] = {
            title = budgetLine("本月", budget.monthly_spend_usd,
                               budget.monthly_budget_usd),
            disabled = true
        }
        if type(budget.hard_limit_usd) == "number" then
            items[#items + 1] = {
                title = "硬上限  " .. money(budget.hard_limit_usd),
                disabled = true
            }
        end
        items[#items + 1] = {
            title = string.format("限速  %s RPM / %s TPM",
                                  count(budget.rate_limit_rpm),
                                  count(budget.rate_limit_tpm)),
            disabled = true
        }
    else
        items[#items + 1] = {title = lastError or "读取中…", disabled = true}
    end

    -- The summary cannot be narrowed to today, so it is labelled by its range
    -- rather than presented as today's numbers.
    if summary then
        local range = summary.time_range or ctx.config.summaryRange
        items[#items + 1] = {title = "-"}
        local totals = summary.totals or {}
        items[#items + 1] = {
            title = string.format("近 %s  %s · %s 次 · %s token", range,
                                  money(totals.total_cost_usd),
                                  count(totals.total_requests or 0),
                                  count(totals.total_tokens or 0)),
            disabled = true
        }

        -- by_model and by_key carry usable request counts. by_provider's
        -- total_requests is 0 for every provider, so only its cost is shown.
        local function breakdown(title, list, nameKey, withRequests)
            local rows = topN(list, 5)
            if #rows == 0 then return end
            local sub = {}
            for _, r in ipairs(rows) do
                local label = r[nameKey]
                if label == nil or label == "" then label = "unknown" end
                if withRequests then
                    sub[#sub + 1] = {
                        title = string.format("%s  %s · %s 次", label,
                                              money(r.total_cost_usd),
                                              count(r.total_requests or 0)),
                        disabled = true
                    }
                else
                    sub[#sub + 1] = {
                        title = string.format("%s  %s", label,
                                              money(r.total_cost_usd)),
                        disabled = true
                    }
                end
            end
            items[#items + 1] = {
                title = title .. " (近 " .. range .. ")",
                menu = sub
            }
        end

        breakdown("按模型", summary.by_model, "model", true)
        breakdown("按 Key", summary.by_key, "api_key_name", true)
        breakdown("按供应商", summary.by_provider, "provider_id", false)

        local days = summary.by_day or {}
        if #days > 0 then
            local sub = {}
            for i = #days, 1, -1 do
                local d = days[i]
                sub[#sub + 1] = {
                    title = string.format("%s  %s · %d 次", d.date or "?",
                                          money(d.total_cost_usd),
                                          d.total_requests or 0),
                    disabled = true
                }
            end
            sub[#sub + 1] = {title = "-"}
            sub[#sub + 1] = {
                title = "与「今日」不一致属正常: 来源不同",
                disabled = true
            }
            items[#items + 1] = {title = "按天 (Prometheus)", menu = sub}
        end
    end

    local note = expiryNote()
    if note then
        items[#items + 1] = {title = "-"}
        items[#items + 1] = {title = "⚠ " .. note, disabled = true}
    end

    items[#items + 1] = {title = "-"}
    items[#items + 1] = {
        title = "打开控制台",
        fn = function()
            hs.urlevent.openURL("https://kaon-router-admin.kaonai.com/usage")
        end
    }
    -- The host already appends a plain "刷新", which only redraws and lets the
    -- backoff stand. This one ignores both and refetches the breakdown as well.
    items[#items + 1] = {
        title = "强制重新拉取",
        fn = function()
            nextFetch = 0
            summary = nil
            ctx.update()
        end
    }
    return items
end

-- Lifecycle ---------------------------------------------------------------------

function M.start(ctx)
    icon = nil
    if ctx.config.iconPath then
        icon = hs.image.imageFromPath(ctx.config.iconPath)
        if icon then
            local n = ctx.config.iconSize
            icon:setSize({w = n, h = n})
        else
            print("statusbar.kaon: cannot load icon " .. ctx.config.iconPath)
        end
    end

    token, lastError = readToken(ctx.config.tokenPath)
    budget, summary, expiresAt, lastOK = nil, nil, nil, nil
    fatal, failures, nextFetch, inFlight, tick = nil, 0, 0, false, 0

    if not token then
        fatal = lastError
        return
    end

    -- One extra call at start: a token that expires silently would otherwise
    -- kill the widget with nothing but a 401 to show for it.
    get(ctx, "/auth/me", function(payload)
        if not payload then return end
        local at = payload.automation_token_expires_at
        if type(at) ~= "string" then return end
        local y, mo, d, h, mi, s = at:match(
                                       "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
        if not y then return end
        -- The field is UTC; convert through the local offset os.time() assumes.
        local utc = os.time({
            year = tonumber(y), month = tonumber(mo), day = tonumber(d),
            hour = tonumber(h), min = tonumber(mi), sec = tonumber(s)
        })
        expiresAt = utc + os.difftime(os.time(), os.time(os.date("!*t")))
        ctx.update()
    end)
end

function M.stop(ctx)
    token, budget, summary, expiresAt, lastOK = nil, nil, nil, nil, nil
    lastError, fatal, inFlight, icon = nil, nil, false, nil
end

return M
