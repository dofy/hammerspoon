-- ui-demo.lua
-- 预览 Hammerspoon 各种 UI 能力。
-- 启动后菜单栏出现「🎨 UI Demo」,点开可逐个预览:
-- alert / notify / chooser / canvas / webview / dialog。

local M = {}

M.config = {
    menubarTitle = "🎨 UI Demo",
}

local menubar = nil
local canvas = nil
local webview = nil
local chooser = nil

-- 1) hs.alert:屏幕中央临时提示
local function demoAlert()
    hs.alert.show("这是 hs.alert 提示", 2)
end

-- 2) hs.notify:系统通知中心
local function demoNotify()
    hs.notify.new({
        title = "Hammerspoon",
        subTitle = "hs.notify 演示",
        informativeText = "点我会触发回调",
    }):send()
end

-- 3) hs.chooser:类 Spotlight 模糊搜索列表
local function demoChooser()
    chooser = hs.chooser.new(function(choice)
        if choice then
            hs.alert.show("你选了:" .. choice.text)
        end
    end)
    chooser:choices({
        { text = "选项 A", subText = "chooser 支持副标题" },
        { text = "选项 B", subText = "支持模糊搜索" },
        { text = "选项 C", subText = "回车确认,Esc 取消" },
    })
    chooser:show()
end

-- 4) hs.canvas:自绘浮层(圆角面板 + 文字 + 可点击关闭按钮)
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
            text = "hs.canvas 自绘面板",
            textColor = { white = 1 },
            textSize = 20,
            frame = { x = 0, y = 24, w = w, h = 30 },
            textAlignment = "center",
        },
        {
            type = "text",
            text = "可画形状/文字/图片/渐变,支持点击回调",
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
            text = "关闭",
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

-- 5) hs.webview:内嵌网页,用 HTML/CSS/JS 写界面,并与 Lua 双向通信
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
  <p>用 HTML + CSS + JS 渲染,可回调 Lua</p>
  <button onclick="ping()">点我调用 Lua</button>
  <script>
    function ping() {
      webkit.messageHandlers.uidemo.postMessage({ msg: "来自网页的问候 👋" });
    }
  </script>
</body>
</html>
]]

    local ucc = hs.webview.usercontent.new("uidemo")
    ucc:setCallback(function(message)
        local body = message.body or {}
        hs.alert.show("webview 回传:" .. (body.msg or "?"))
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

-- 6) hs.dialog:系统风格输入框 / 确认框
local function demoDialog()
    local btn, text = hs.dialog.textPrompt(
        "hs.dialog 输入框",
        "随便输入点内容:",
        "",
        "确定",
        "取消"
    )
    if btn == "确定" then
        hs.alert.show("你输入了:" .. text)
    end
end

function M.start()
    M.stop()
    menubar = hs.menubar.new()
    menubar:setTitle(M.config.menubarTitle)
    menubar:setMenu({
        { title = "1. alert 提示", fn = demoAlert },
        { title = "2. notify 系统通知", fn = demoNotify },
        { title = "3. chooser 搜索列表", fn = demoChooser },
        { title = "4. canvas 自绘面板", fn = demoCanvas },
        { title = "5. webview 网页界面", fn = demoWebview },
        { title = "6. dialog 输入框", fn = demoDialog },
        { title = "-" },
        { title = "退出 Demo", fn = function() M.stop() end },
    })
end

function M.stop()
    if menubar then menubar:delete() menubar = nil end
    if canvas then canvas:delete() canvas = nil end
    if webview then webview:delete() webview = nil end
    if chooser then chooser:delete() chooser = nil end
end

return M
