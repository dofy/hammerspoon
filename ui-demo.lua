-- ui-demo.lua
-- Preview Hammerspoon UI capabilities.
-- Start the module and use the 🎨 UI Demo menu to preview:
-- alert / notify / chooser / canvas / webview / dialog。

local M = {}

M.config = {
    menubarTitle = "🎨 UI Demo",
}

local menubar = nil
local canvas = nil
local webview = nil
local chooser = nil

-- 1) hs.alert:temporary on-screen message
local function demoAlert()
    hs.alert.show("hs.alert demo", 2)
end

-- 2) hs.notify:system notification
local function demoNotify()
    hs.notify.new({
        title = "Hammerspoon",
        subTitle = "hs.notify demo",
        informativeText = "Click to trigger the callback",
    }):send()
end

-- 3) hs.chooser:Spotlight-style fuzzy search
local function demoChooser()
    chooser = hs.chooser.new(function(choice)
        if choice then
            hs.alert.show("Selected: " .. choice.text)
        end
    end)
    chooser:choices({
        { text = "Option A", subText = "Chooser supports subtitles" },
        { text = "Option B", subText = "Fuzzy search" },
        { text = "Option C", subText = "Return to confirm, Esc to cancel" },
    })
    chooser:show()
end

-- 4) hs.canvas:custom overlay (rounded panel, text, close button)
local function demoCanvas()
    if canvas then canvas:delete() end
    local w, h = 320, 180
    local frame = hs.screen.mainScreen():frame()
    canvas = hs.canvas.new({
        x = frame.x + (frame.w - w) / 2,
        y = frame.y + (frame.h - h) / 2,
        w = w,
        h = h,
    })
    canvas:appendElements(
        {
            type = "rectangle",
            action = "fill",
            fillColor = { red = 0.09, green = 0.10, blue = 0.13, alpha = 0.95 },
            roundedRectRadii = { xRadius = 16, yRadius = 16 },
        },
        {
            type = "text",
            text = "hs.canvas panel",
            textColor = { white = 1 },
            textSize = 20,
            frame = { x = 0, y = 24, w = w, h = 30 },
            textAlignment = "center",
        },
        {
            type = "text",
            text = "Shapes, text, images, gradients, and clicks",
            textColor = { white = 0.7 },
            textSize = 13,
            frame = { x = 20, y = 64, w = w - 40, h = 40 },
            textAlignment = "center",
        },
        {
            type = "rectangle",
            action = "fill",
            fillColor = { red = 0.2, green = 0.5, blue = 1.0, alpha = 1 },
            roundedRectRadii = { xRadius = 8, yRadius = 8 },
            frame = { x = w / 2 - 50, y = h - 56, w = 100, h = 36 },
            trackMouseUp = true,
            id = "closeBtn",
        },
        {
            type = "text",
            text = "Close",
            textColor = { white = 1 },
            textSize = 15,
            frame = { x = w / 2 - 50, y = h - 48, w = 100, h = 24 },
            textAlignment = "center",
        }
    )
    canvas:mouseCallback(function(_, event, id)
        if event == "mouseUp" and id == "closeBtn" then
            canvas:delete()
            canvas = nil
        end
    end)
    canvas:clickActivating(false)
    canvas:show()
end

-- 5) hs.webview:embedded HTML/CSS/JS with two-way Lua communication
local function demoWebview()
    if webview then webview:delete() end

    local html = [[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  html, body { margin: 0; height: 100%; font-family: -apple-system, sans-serif; }
  body {
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    background: linear-gradient(135deg, #6a11cb, #2575fc); color: #fff; gap: 16px;
  }
  h2 { margin: 0; }
  p { margin: 0; opacity: .85; }
  button {
    padding: 10px 22px; border: none; border-radius: 10px; font-size: 15px;
    background: rgba(255,255,255,.2); color: #fff; cursor: pointer;
    backdrop-filter: blur(6px);
  }
  button:hover { background: rgba(255,255,255,.35); }
</style>
</head>
<body>
  <h2>hs.webview</h2>
  <p>HTML + CSS + JS with Lua callbacks</p>
  <button onclick="ping()">Call Lua</button>
  <script>
    function ping() {
      webkit.messageHandlers.uidemo.postMessage({ msg: "Hello from the webview 👋" });
    }
  </script>
</body>
</html>
]]

    local ucc = hs.webview.usercontent.new("uidemo")
    ucc:setCallback(function(message)
        local body = message.body or {}
        hs.alert.show("Webview: " .. (body.msg or "?"))
    end)

    local w, h = 420, 300
    local frame = hs.screen.mainScreen():frame()
    webview = hs.webview.new({
        x = frame.x + (frame.w - w) / 2,
        y = frame.y + (frame.h - h) / 2,
        w = w,
        h = h,
    }, { developerExtrasEnabled = true }, ucc)
    webview:windowStyle({ "titled", "closable" })
    webview:windowTitle("Webview Demo")
    webview:allowTextEntry(true)
    webview:closeOnEscape(true)
    webview:html(html)
    webview:bringToFront()
    webview:show()
end

-- 6) hs.dialog:native input and confirmation dialogs
local function demoDialog()
    local btn, text = hs.dialog.textPrompt(
        "hs.dialog prompt",
        "Enter some text:",
        "",
        "OK",
        "Cancel"
    )
    if btn == "OK" then
        hs.alert.show("Entered: " .. text)
    end
end

function M.start()
    M.stop()
    menubar = hs.menubar.new()
    menubar:setTitle(M.config.menubarTitle)
    menubar:setMenu({
        { title = "1. Alert", fn = demoAlert },
        { title = "2. Notification", fn = demoNotify },
        { title = "3. Chooser", fn = demoChooser },
        { title = "4. Canvas", fn = demoCanvas },
        { title = "5. Webview", fn = demoWebview },
        { title = "6. Dialog", fn = demoDialog },
        { title = "-" },
        { title = "Quit Demo", fn = function() M.stop() end },
    })
end

function M.stop()
    if menubar then menubar:delete() menubar = nil end
    if canvas then canvas:delete() canvas = nil end
    if webview then webview:delete() webview = nil end
    if chooser then chooser:delete() chooser = nil end
end

return M
