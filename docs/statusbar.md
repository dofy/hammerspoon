# Statusbar

[← Overview](../README.md)

Widgets are a per-machine choice, set in the git-ignored `init.local.lua`; `init.lua` mounts
none. The widget list is also the on/off switch — a name in it runs, a name commented out does
not:

```lua
local modules = ...
modules.statusbar.config.widgets = {
    "kaon",
    -- "battery",
}
modules.statusbar.config.widgetConfig.battery = {lowThreshold = 15}
```

Saving the file reloads Hammerspoon, so the change takes effect immediately. There is no runtime
toggle and nothing is stored outside the file: what the list says is what is mounted. To check
what actually came up:

```sh
hs -c 'hs.inspect(require("statusbar").status())'
```

A widget that is listed but reads `false` there failed to mount; the Hammerspoon Console carries
the reason.

## Kaon Router spend

`statusbar/kaon.lua` shows today's Kaon Router spend in the menu bar, read from the
Kaon Admin API. It needs an automation token:

1. Open <https://kaon-router-admin.kaonai.com>, then **Automation Tokens** in the sidebar.
2. Create a token with the **`usage:read`** scope. Kaon's write scopes do not imply usage access,
   so a token without this scope gets 403 on every request, forever.
3. Store it outside this repository, readable only by you:

   ```zsh
   mkdir -p ~/.config/kaon
   umask 077
   read -rs 'kaon_token?Token: '
   printf '%s' "$kaon_token" > ~/.config/kaon/token
   unset kaon_token
   chmod 600 ~/.config/kaon/token
   ```

   The prompt hides the token and avoids placing it in shell history.

The token is read once at start and never printed; only HTTP status codes reach the tooltip.

The menu-bar title is the spend alone. The daily budget, what is left of it, and the weekly and
monthly figures live in the tooltip and the dropdown — the budget does not change from hour to
hour, so putting it in the title would cost width for nothing. The title does turn amber at 70%
and red at 90% of that budget.

The glyph beside the amount is `statusbar/kaon.svg`, the Kaon console's own favicon with its
violet plate removed. It is a template image, so macOS tints it to the menu-bar foreground colour
and it follows light and dark mode without any code. Icon and amount are drawn into one image
rather than set as an icon plus a title, because AppKit reserves about 17pt between those two and
`hs.menubar` cannot shrink it; the item is 69pt wide against 51pt of content, and the remaining
18pt is AppKit's own padding.

Everything about the text is configurable from `init.local.lua`, under
`modules.statusbar.config.widgetConfig.kaon`:

```lua
modules.statusbar.config.widgetConfig.kaon = {
    font = {name = "Menlo", size = 13}, -- monospace: the width stops jumping
    decimals = 0,                       -- 0..4 on the amount
    showBudget = false,                 -- "$46 / $100" instead of "$46"
    symbol = "$",                       -- marker in front of the amount
    iconSize = 16,                      -- points; the menu bar does not grow
    iconGap = 3                         -- points between glyph and amount
}
```

`hs.styledtext.validFont` decides what `font` may name: on this machine `Menlo`, `Monaco` and
`MesloLGS NF` pass while `SF Mono` does not, because it is not installed as a system font. A
Nerd Font glyph works as `symbol` (`MesloLGS NF` carries real outlines for `nf-md-currency_usd`
`\u{F01C1}` and friends), but only with `font` pointing at a patched font — macOS fallback for
those private-use codepoints is not guaranteed to find one.

Two numbers in the dropdown disagree on purpose. `Today` comes from `/users/me/budget`, the counter
the Kaon console's own banner shows and the one that actually gates requests. `By day (Prometheus)`
comes from `/usage/summary`, which read about 8 USD higher for the same date. Trust `Today`.
There is no breakdown for today alone: the only range tokens are `5m | 1h | 24h | 7d | 30d`, and
`24h` comes back as five one-minute buckets rather than a day, so the breakdown covers seven days
and says so. It splits that range by model, by inference key and by provider. The provider rows
show cost without a request count because the API reports 0 requests for every provider while
still reporting its cost.

A 401, 403 or 429 stops the widget instead of retrying — `automation_protocol_throttled` and
`automation_token_suspended` are stop signals in Kaon's contract, and hammering through them
risks the token being suspended. Clear the stopped state from the dropdown's **Retry**, or by
toggling the widget off and on.

## Writing a widget

Drop a file in `statusbar/` and add its name to `config.widgets`. A widget returns a table:

```lua
local M = {}

M.label    = "Disk"   -- shown in the ⚠ tooltip when render throws
M.interval = 60       -- refresh seconds; nil means event-driven only
M.config   = {path = "/"}

function M.render(ctx)       -- required
  local free = hs.fs.volume.allVolumes()[ctx.config.path]
  if not free then return nil end          -- nil hides the item
  return {title = "💾", tooltip = ctx.config.path}
end

function M.menu(ctx) return {{title = ctx.config.path, disabled = true}} end
function M.start(ctx) end    -- install watchers here, call ctx.update() from them
function M.stop(ctx) end     -- tear them down here

return M
```

`render` may return a string, an `hs.styledtext` object, a table of
`{title =, icon =, tooltip =, template =}`, or `nil` to take the item off the bar until the next
non-nil render. `ctx` carries `ctx.name`, `ctx.config`, `ctx.bar` and `ctx.update()`.

Two rules matter:

- `render` runs on the main thread. Anything that waits on the network or a subprocess goes into
  `hs.task` or `hs.http.asyncGet`, with `ctx.update()` called from the callback — a blocking
  render freezes the menu bar.
- `click` replaces the dropdown. Define one or the other, not both.

Every call into widget code is wrapped in `pcall`. A widget that throws shows `⚠` with the error
as its tooltip, and the other widgets keep running.
