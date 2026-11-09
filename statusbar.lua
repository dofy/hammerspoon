--- === statusbar ===
---
--- Menu-bar host. Owns every `hs.menubar` item in this configuration so that
--- individual widgets stay small: a widget declares what to show and how often,
--- and this module creates the item, drives the refresh timer and builds the
--- dropdown.
---
--- Everything is configured in `init.lua`, which is the only file to edit.
--- `config.widgets` is both the mount list and the on/off switch: a name in the
--- list runs, a name commented out does not. There is no runtime toggle, no
--- control item and no persisted state, so the file on disk is always the whole
--- truth about what is mounted.
---
--- A widget is a Lua file in `statusbar/` returning a table:
---
---     return {
---       label    = "Battery",          -- shown in the ⚠ tooltip when render throws
---       interval = 5,                  -- refresh seconds; nil = event-driven only
---       config   = { ... },            -- optional, overridable from init.lua
---       render   = function(ctx) ... end,  -- required
---       menu     = function(ctx) ... end,  -- optional dropdown items
---       click    = function(ctx) ... end,  -- optional; replaces the dropdown
---       start    = function(ctx) ... end,  -- optional; install watchers here
---       stop     = function(ctx) ... end,  -- optional; tear them down here
---     }
---
--- `render` returns one of:
---   * a string or an `hs.styledtext` object -- used as the item title
---   * a table `{ title =, icon =, tooltip =, template = }`
---   * `nil` -- the item leaves the menu bar until the next non-nil render
---
--- `ctx` carries `ctx.name`, `ctx.config`, `ctx.bar` (the raw `hs.menubar`) and
--- `ctx.update()`, which re-renders immediately. Event-driven widgets keep a
--- watcher in `start()` and call `ctx.update()` from its callback.
---
--- Design notes:
---  * `render` runs on the main thread, so it must not block. Anything that
---    waits on the network or a subprocess belongs in `hs.task` /
---    `hs.http.asyncGet`, with `ctx.update()` called from its callback.
---  * Every call into a widget is wrapped in `pcall`. A widget that throws
---    shows `⚠` in its title and leaves the rest of the menu bar running.
---  * macOS decides where a status item sits; `config.widgets` fixes the mount
---    order, not the on-screen order.

local M = {}

M.config = {
    -- Set in init.lua. Empty here on purpose: a default list would be a second
    -- place to look when asking what is mounted.
    widgets = {},

    -- Per-widget overrides, merged into the widget's own `config` table at
    -- mount time: widgetConfig.battery = { lowThreshold = 15 }.
    widgetConfig = {}
}

-- Private state: name -> { widget, bar, timer, ctx }
local mounted = {}
local started = false

-- Widget plumbing ------------------------------------------------------------

-- Calls into widget code. Returns nil and logs on error rather than letting one
-- bad widget take down the host.
local function guard(name, fn, ...)
    if not fn then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then
        print(string.format("statusbar: widget %q failed: %s", name,
                            tostring(result)))
        return nil, result
    end
    return result
end

local function applyRender(entry, value)
    local bar = entry.bar
    if not bar then return end

    if value == nil then
        bar:removeFromMenuBar()
        return
    end
    bar:returnToMenuBar()

    -- A styledtext object is userdata; a structured result is a plain table.
    if type(value) == "table" then
        if value.icon then bar:setIcon(value.icon, value.template ~= false) end
        if value.title then
            bar:setTitle(value.title)
        elseif not value.icon then
            bar:setTitle("")
        end
        bar:setTooltip(value.tooltip or "")
    else
        bar:setTitle(value)
    end
end

local function render(entry)
    local value, err = guard(entry.name, entry.widget.render, entry.ctx)
    if err then
        if entry.bar then
            entry.bar:returnToMenuBar()
            entry.bar:setTitle("⚠")
            -- Name the widget in the tooltip: a bare ⚠ in a crowded menu bar
            -- does not say which one broke.
            entry.bar:setTooltip(string.format("%s: %s",
                                               entry.widget.label or entry.name,
                                               tostring(err)))
        end
        return
    end
    applyRender(entry, value)
end

-- Dropdown shown when a widget item is clicked: the widget's own items, then a
-- refresh. Switching a widget is an edit to init.lua, not a menu action, so
-- nothing here changes what is mounted.
local function buildMenu(entry)
    local items = guard(entry.name, entry.widget.menu, entry.ctx) or {}
    if #items > 0 then items[#items + 1] = {title = "-"} end
    items[#items + 1] = {title = "刷新", fn = function() render(entry) end}
    return items
end

-- Mount / unmount ------------------------------------------------------------

local function loadWidget(name)
    local ok, widget = pcall(require, "statusbar." .. name)
    if not ok then
        print(string.format("statusbar: cannot load widget %q: %s", name,
                            tostring(widget)))
        return nil
    end
    if type(widget) ~= "table" or type(widget.render) ~= "function" then
        print(string.format("statusbar: widget %q has no render function", name))
        return nil
    end
    return widget
end

local function mount(name)
    if mounted[name] then return mounted[name] end

    local widget = loadWidget(name)
    if not widget then return nil end

    -- Merge init.lua overrides into the widget's own defaults.
    widget.config = widget.config or {}
    for k, v in pairs(M.config.widgetConfig[name] or {}) do
        widget.config[k] = v
    end

    local bar = hs.menubar.new()
    if not bar then
        print(string.format("statusbar: no menu bar slot for %q", name))
        return nil
    end

    local entry = {name = name, widget = widget, bar = bar, timer = nil}
    entry.ctx = {
        name = name,
        config = widget.config,
        bar = bar,
        update = function() render(entry) end
    }
    mounted[name] = entry

    if widget.click then
        bar:setClickCallback(function() guard(name, widget.click, entry.ctx) end)
    else
        -- A function menu is rebuilt on every click, so widget state stays live.
        bar:setMenu(function() return buildMenu(entry) end)
    end

    guard(name, widget.start, entry.ctx)
    render(entry)

    if widget.interval and widget.interval > 0 then
        entry.timer = hs.timer.doEvery(widget.interval,
                                       function() render(entry) end)
    end

    return entry
end

local function unmount(name)
    local entry = mounted[name]
    if not entry then return end
    mounted[name] = nil

    if entry.timer then
        entry.timer:stop()
        entry.timer = nil
    end
    guard(name, entry.widget.stop, entry.ctx)
    if entry.bar then
        entry.bar:delete()
        entry.bar = nil
    end
end

-- Public API -----------------------------------------------------------------

--- statusbar.start() -> self
--- Mounts every widget in `config.widgets`, in that order.
function M.start()
    if started then M.stop() end
    started = true
    for _, name in ipairs(M.config.widgets) do mount(name) end
    return M
end

--- statusbar.stop() -> self
function M.stop()
    for name in pairs(mounted) do unmount(name) end
    started = false
    return M
end

--- statusbar.refresh([name]) -> self
--- Re-renders one widget, or every mounted widget.
function M.refresh(name)
    if name then
        if mounted[name] then render(mounted[name]) end
        return M
    end
    for _, entry in pairs(mounted) do render(entry) end
    return M
end

--- statusbar.status() -> table
--- name -> true/false, for `hs -c 'hs.inspect(require("statusbar").status())'`.
--- A widget listed in `config.widgets` reads false only when it failed to mount;
--- the Hammerspoon Console carries the reason.
function M.status()
    local out = {}
    for _, name in ipairs(M.config.widgets) do
        out[name] = mounted[name] ~= nil
    end
    return out
end

return M
