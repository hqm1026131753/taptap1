-- ============================================================================
-- MobileHUD.lua — 手机端虚拟控制层（极简白描风格，NanoVG 图标）
-- 左下：虚拟摇杆
-- 右下：攻击按钮（大）+ 3按钮弧线（搜索/放大镜、翻滚/脚印、换弹/子弹）
-- 底部中央：医疗栏右侧放背包键（背包图标）
-- 右上：暂停按钮
-- ============================================================================
local PlatformUtils = require "urhox-libs.Platform.PlatformUtils"

local M = {}

-- ----------------------------------------------------------------------------
-- 平台检测
-- ----------------------------------------------------------------------------
function M.IsMobile()
    return PlatformUtils.IsMobilePlatform()
end

-- ----------------------------------------------------------------------------
-- 布局（按逻辑分辨率比例计算）
-- ----------------------------------------------------------------------------

---@class MobileLayout
---@field joystick  { cx:number, cy:number, outerR:number, innerR:number }
---@field btnAttack { cx:number, cy:number, r:number }
---@field btnRoll   { cx:number, cy:number, r:number }
---@field btnReload { cx:number, cy:number, r:number }
---@field btnSearch { cx:number, cy:number, r:number }
---@field btnBag    { cx:number, cy:number, r:number }
---@field btnPause  { cx:number, cy:number, r:number, x:number, y:number, w:number, h:number }
---@field btnSwap   { cx:number, cy:number, x:number, y:number, w:number, h:number }
---@field btnEvac   { cx:number, cy:number, x:number, y:number, w:number, h:number }

---计算布局
---@param sw number
---@param sh number
---@return MobileLayout
function M.Layout(sw, sh)
    local unit = math.min(sw, sh)
    local safeTop = math.max(18, math.floor(unit * 0.055))

    -- 摇杆：左下角
    local jR  = unit * 0.11
    local jCx = jR + sw * 0.08
    local jCy = sh - jR - sh * 0.10

    -- 右下角：攻击按钮（更大的圆）+ 4个按钮围在左上弧线
    local atkR  = unit * 0.11    -- 攻击键放大
    local btnR  = unit * 0.055   -- 周围按钮放大

    -- 攻击按钮位于右下角（增大底部边距防止溢出）
    local atkCx = sw - atkR - sw * 0.045
    local atkCy = sh - atkR - sh * 0.12

    -- 4个按钮围在攻击键左上弧线（不向下延伸，避免溢出屏幕）
    -- 角度约定：0°=右, 90°=下, 180°=左, 270°=上（屏幕坐标Y朝下）
    -- 安全弧线范围：190°~290°（左侧到右上方）
    local arcDist = atkR + btnR + btnR * 0.6  -- 弧线距离（从攻击键中心）

    -- 搜索：左上方向（~240°）
    local searchCx = atkCx + math.cos(math.rad(240)) * arcDist
    local searchCy = atkCy + math.sin(math.rad(240)) * arcDist
    -- 换弹：左侧偏下（~200°）
    local reloadCx = atkCx + math.cos(math.rad(200)) * arcDist
    local reloadCy = atkCy + math.sin(math.rad(200)) * arcDist
    -- 翻滚：换弹之下（~165°）
    local rollCx = atkCx + math.cos(math.rad(165)) * arcDist
    local rollCy = atkCy + math.sin(math.rad(165)) * arcDist

    -- 背包：放在药品快捷栏右侧（底部居中偏右）
    local medTotalW = 3 * 33 + 2 * 4  -- MED_N * MED_W + (MED_N-1) * MED_GAP
    local medBx = math.floor(sw / 2 - medTotalW / 2)
    local medBy = sh - 42 - 16  -- sh - MED_H - MED_MRG
    local bagCx = medBx + medTotalW + btnR + 10  -- 药品栏右边 + 间距
    local bagCy = medBy + 42 / 2  -- 垂直居中对齐药品栏

    -- 暂停/换枪按钮：层数面板左侧（与医疗用品同款像素风）
    -- 层数面板: rpW=160, rpx=sw-160-10, rpy=10
    local rpW = 160
    local rpX = sw - rpW - 10
    local btnSize = 30        -- 单按钮尺寸（正方形）
    local btnGap = 4          -- 按钮间距
    local pauseW = btnSize
    local pauseH = btnSize
    local swapW  = btnSize
    local swapH  = btnSize
    -- 两个按钮横向排列，紧贴层数面板左边
    local totalBtnW = pauseW + btnGap + swapW
    local pauseX = rpX - totalBtnW - 8
    local pauseY = safeTop
    local swapX  = pauseX + pauseW + btnGap
    local swapY  = safeTop
    local pauseCx = pauseX + pauseW / 2
    local pauseCy = pauseY + pauseH / 2
    local pauseR  = pauseW / 2

    -- 撤离按钮：攻击按钮上方
    local evH = btnR * 1.5
    local evW = btnR * 3.6
    local evX = atkCx - evW * 0.5
    local evY = atkCy - atkR - evH - btnR * 2.5
    local evCx = atkCx
    local evCy = evY + evH * 0.5

    return {
        joystick  = { cx = jCx, cy = jCy, outerR = jR, innerR = jR * 0.40 },
        btnAttack = { cx = atkCx, cy = atkCy, r = atkR },
        btnSearch = { cx = searchCx, cy = searchCy, r = btnR },
        btnRoll   = { cx = rollCx, cy = rollCy, r = btnR },
        btnBag    = { cx = bagCx, cy = bagCy, r = btnR },
        btnReload = { cx = reloadCx, cy = reloadCy, r = btnR },
        btnPause  = { cx = pauseCx, cy = pauseCy, r = pauseR, x = pauseX, y = pauseY, w = pauseW, h = pauseH },
        btnSwap   = { cx = swapX + swapW/2, cy = swapY + swapH/2, x = swapX, y = swapY, w = swapW, h = swapH },
        btnEvac   = { cx = evCx, cy = evCy, x = evX, y = evY, w = evW, h = evH },
    }
end

-- ----------------------------------------------------------------------------
-- 触控状态
-- ----------------------------------------------------------------------------

---@type table
local state = {
    joystickTouchId  = nil,
    joystickStartX   = 0,
    joystickStartY   = 0,
    joystickDx       = 0,
    joystickDy       = 0,
    joystickFloatCx  = 0,  -- 浮动摇杆当前绘制中心 X
    joystickFloatCy  = 0,  -- 浮动摇杆当前绘制中心 Y
    attackTouchId    = nil,
    rollTouchId      = nil,
    reloadTouchId    = nil,
    searchTouchId    = nil,
}

function M.GetJoystickDir()
    return state.joystickDx, state.joystickDy
end

function M.IsAttackHeld()
    return state.attackTouchId ~= nil
end

-- ----------------------------------------------------------------------------
-- 命中测试
-- ----------------------------------------------------------------------------
local function hitCircle(cx, cy, r, x, y)
    local dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r
end

---@param layout MobileLayout
---@param x number
---@param y number
---@param nearExit boolean|nil
---@param sw number|nil  -- 屏幕宽度（用于浮动摇杆左半屏判定）
---@return string|nil
function M.HitTest(layout, x, y, nearExit, sw)
    -- 先检测右侧所有按钮（优先于左半屏摇杆区域）
    if hitCircle(layout.btnAttack.cx, layout.btnAttack.cy, layout.btnAttack.r * 1.2, x, y) then return "attack" end
    if hitCircle(layout.btnRoll.cx, layout.btnRoll.cy, layout.btnRoll.r * 1.3, x, y) then return "roll" end
    if hitCircle(layout.btnReload.cx, layout.btnReload.cy, layout.btnReload.r * 1.3, x, y) then return "reload" end
    if hitCircle(layout.btnSearch.cx, layout.btnSearch.cy, layout.btnSearch.r * 1.3, x, y) then return "search" end
    if hitCircle(layout.btnBag.cx, layout.btnBag.cy, layout.btnBag.r * 1.3, x, y) then return "bag" end
    -- 暂停（矩形按钮，扩大点击区）
    local ps = layout.btnPause
    if x >= ps.x - 8 and x <= ps.x + ps.w + 8 and y >= ps.y - 8 and y <= ps.y + ps.h + 8 then return "pause" end
    -- 换枪（矩形按钮，扩大点击区）
    local sp = layout.btnSwap
    if x >= sp.x - 8 and x <= sp.x + sp.w + 8 and y >= sp.y - 8 and y <= sp.y + sp.h + 8 then return "swap" end
    -- 撤离
    if nearExit then
        local eb = layout.btnEvac
        if x >= eb.x - 8 and x <= eb.x + eb.w + 8 and y >= eb.y - 8 and y <= eb.y + eb.h + 8 then return "evac" end
    end

    -- 浮动摇杆：左半屏任意位置都可激活
    local halfW = (sw or 400) * 0.5
    if x < halfW then return "joystick" end

    return nil
end

-- ----------------------------------------------------------------------------
-- 触控事件
-- ----------------------------------------------------------------------------

function M.OnTouchBegin(layout, touchId, x, y, nearExit, sw)
    local hit = M.HitTest(layout, x, y, nearExit, sw)
    if hit == "joystick" then
        state.joystickTouchId = touchId
        state.joystickStartX  = x
        state.joystickStartY  = y
        state.joystickFloatCx = x  -- 浮动中心 = 触摸起始点
        state.joystickFloatCy = y
        state.joystickDx      = 0
        state.joystickDy      = 0
    elseif hit == "attack" then
        state.attackTouchId = touchId
    elseif hit == "roll" then
        state.rollTouchId = touchId
    elseif hit == "reload" then
        state.reloadTouchId = touchId
    elseif hit == "search" then
        state.searchTouchId = touchId
    end
    return hit
end

function M.OnTouchMove(layout, touchId, x, y)
    if touchId == state.joystickTouchId then
        local jo = layout.joystick
        local dx = x - state.joystickStartX
        local dy = y - state.joystickStartY
        local dist = math.sqrt(dx * dx + dy * dy)
        local maxDist = jo.outerR
        if dist > maxDist then
            dx = dx / dist * maxDist
            dy = dy / dist * maxDist
        end
        if maxDist > 0 then
            state.joystickDx = dx / maxDist
            state.joystickDy = dy / maxDist
        end
    end
end

function M.OnTouchEnd(touchId)
    if touchId == state.joystickTouchId then
        state.joystickTouchId = nil
        state.joystickDx = 0
        state.joystickDy = 0
    end
    if touchId == state.attackTouchId then state.attackTouchId = nil end
    if touchId == state.rollTouchId then state.rollTouchId = nil end
    if touchId == state.reloadTouchId then state.reloadTouchId = nil end
    if touchId == state.searchTouchId then state.searchTouchId = nil end
end

function M.ResetAll()
    state.joystickTouchId = nil
    state.joystickDx = 0
    state.joystickDy = 0
    state.attackTouchId = nil
    state.rollTouchId = nil
    state.reloadTouchId = nil
    state.searchTouchId = nil
end

-- ----------------------------------------------------------------------------
-- 渲染（极简白描风格）
-- ----------------------------------------------------------------------------

-- (joystickHandlePos 不再使用，浮动摇杆直接使用 state 中的浮动中心)

-- 绘制白描圆形按钮
-- 绘制圆形按钮底层（背景+描边+按压发光）
local function drawCircleBtnBase(ctx, cx, cy, r, pressed, available)
    local dimmed = (available == false)
    local alpha = dimmed and 0.05 or (pressed and 0.35 or 0.15)
    local borderA = dimmed and 35 or (pressed and 220 or 120)

    -- 半透明填充
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r)
    nvgFillColor(ctx, nvgRGBAf(1, 1, 1, alpha))
    nvgFill(ctx)

    -- 描边
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, borderA))
    nvgStrokeWidth(ctx, pressed and 2.0 or (dimmed and 0.8 or 1.2))
    nvgStroke(ctx)

    -- 按下时内发光
    if pressed then
        nvgBeginPath(ctx)
        nvgCircle(ctx, cx, cy, r * 0.85)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 60))
        nvgStrokeWidth(ctx, 1.0)
        nvgStroke(ctx)
    end
end

-- 绘制放大镜图标（搜索）
local function drawIconSearch(ctx, cx, cy, r, pressed, available)
    local dimmed = (available == false)
    local iconA = dimmed and 45 or (pressed and 255 or 200)
    local s = r * 0.45  -- 放大镜圆半径
    -- 镜体圆
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx - s * 0.15, cy - s * 0.15, s)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, iconA))
    nvgStrokeWidth(ctx, r * 0.12)
    nvgStroke(ctx)
    -- 手柄
    local hx = cx - s * 0.15 + s * 0.7
    local hy = cy - s * 0.15 + s * 0.7
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, hx, hy)
    nvgLineTo(ctx, hx + s * 0.7, hy + s * 0.7)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, iconA))
    nvgStrokeWidth(ctx, r * 0.14)
    nvgLineCap(ctx, NVG_ROUND)
    nvgStroke(ctx)
end

-- 绘制子弹图标（换弹）
local function drawIconBullet(ctx, cx, cy, r, pressed, available)
    local dimmed = (available == false)
    local iconA = dimmed and 45 or (pressed and 255 or 200)
    local bw = r * 0.22  -- 弹壳宽度的一半
    local bh = r * 0.6   -- 弹壳高度
    -- 弹壳（圆角矩形）
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, cx - bw, cy - bh * 0.3, bw * 2, bh, bw * 0.4)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, iconA))
    nvgFill(ctx)
    -- 弹头（上方半圆）
    nvgBeginPath(ctx)
    nvgEllipse(ctx, cx, cy - bh * 0.3 - bw * 0.3, bw * 0.85, bw * 0.9)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, iconA))
    nvgFill(ctx)
    -- 底部线条（底火）
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy + bh * 0.7 - bw * 0.2, bw * 0.35)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, iconA))
    nvgFill(ctx)
end

-- 绘制脚印图标（翻滚）
local function drawIconPaw(ctx, cx, cy, r, pressed, available)
    local dimmed = (available == false)
    local iconA = dimmed and 45 or (pressed and 255 or 200)
    local s = r * 0.3
    -- 掌心（椭圆）
    nvgBeginPath(ctx)
    nvgEllipse(ctx, cx, cy + s * 0.3, s * 1.0, s * 0.75)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, iconA))
    nvgFill(ctx)
    -- 4个趾垫
    local toeR = s * 0.35
    local toes = {
        { cx - s * 0.85, cy - s * 0.4 },
        { cx - s * 0.3,  cy - s * 0.8 },
        { cx + s * 0.3,  cy - s * 0.8 },
        { cx + s * 0.85, cy - s * 0.4 },
    }
    for _, t in ipairs(toes) do
        nvgBeginPath(ctx)
        nvgCircle(ctx, t[1], t[2], toeR)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, iconA))
        nvgFill(ctx)
    end
end

-- 绘制背包图标（NanoVG简笔画）
local function drawIconBag(ctx, cx, cy, r, pressed, available)
    local dimmed = (available == false)
    local iconA = dimmed and 45 or (pressed and 255 or 200)
    local s = r * 0.4
    -- 包体（圆角矩形）
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, cx - s, cy - s * 0.5, s * 2, s * 1.6, s * 0.25)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, iconA))
    nvgStrokeWidth(ctx, r * 0.1)
    nvgStroke(ctx)
    -- 提手（半圆弧）
    nvgBeginPath(ctx)
    nvgArc(ctx, cx, cy - s * 0.5, s * 0.5, math.pi, 0, NVG_CW)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, iconA))
    nvgStrokeWidth(ctx, r * 0.1)
    nvgStroke(ctx)
    -- 口袋（中间小矩形）
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, cx - s * 0.45, cy + s * 0.2, s * 0.9, s * 0.6, s * 0.1)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(iconA * 0.6)))
    nvgStrokeWidth(ctx, r * 0.07)
    nvgStroke(ctx)
end

local function drawCircleBtn(ctx, cx, cy, r, icon, pressed, available)
    drawCircleBtnBase(ctx, cx, cy, r, pressed, available)
    -- 图标文字（仅作为fallback）
    local dimmed = (available == false)
    local iconA = dimmed and 45 or (pressed and 255 or 200)
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, r * 0.9)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, iconA))
    nvgText(ctx, cx, cy, icon, nil)
end

-- 绘制翻滚按钮（含CD效果）
local function drawRollBtn(ctx, cx, cy, r, pressed, rollCd)
    local ROLL_CD_TOTAL = 2.5
    local cdLeft = rollCd or 0
    local onCooldown = cdLeft > 0

    if onCooldown then
        local cdProg = cdLeft / ROLL_CD_TOTAL

        -- 底圆（暗色）
        nvgBeginPath(ctx)
        nvgCircle(ctx, cx, cy, r)
        nvgFillColor(ctx, nvgRGBAf(1, 1, 1, 0.08))
        nvgFill(ctx)

        -- 外框
        nvgBeginPath(ctx)
        nvgCircle(ctx, cx, cy, r)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 50))
        nvgStrokeWidth(ctx, 1.0)
        nvgStroke(ctx)

        -- CD 扇形遮罩
        local startA = -math.pi * 0.5
        local endA = startA + cdProg * math.pi * 2
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, cx, cy)
        nvgArc(ctx, cx, cy, r - 1, startA, endA, NVG_CW)
        nvgClosePath(ctx)
        nvgFillColor(ctx, nvgRGBAf(0, 0, 0, 0.35))
        nvgFill(ctx)

        -- 已冷却弧线
        local doneA = startA + (1.0 - cdProg) * math.pi * 2
        if doneA > startA then
            nvgBeginPath(ctx)
            nvgArc(ctx, cx, cy, r - 1.5, startA, doneA, NVG_CW)
            nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 180))
            nvgStrokeWidth(ctx, 2.0)
            nvgStroke(ctx)
        end

        -- CD 数字
        local cdText = cdLeft < 1.0 and string.format("%.1f", cdLeft) or string.format("%d", math.ceil(cdLeft))
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, r * 0.7)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 160))
        nvgText(ctx, cx, cy, cdText, nil)
    else
        drawCircleBtnBase(ctx, cx, cy, r, pressed, true)
        drawIconPaw(ctx, cx, cy, r, pressed, true)
    end
end

---绘制整个移动端 HUD
---@param ctx userdata
---@param layout MobileLayout
---@param searchAvail boolean
---@param rollCd number|nil
---@param nearExit boolean|nil
function M.Draw(ctx, layout, searchAvail, rollCd, nearExit)
    -- ── 浮动摇杆（仅触摸时出现在触摸位置）──────────────────────────
    local jo = layout.joystick
    local isJoy = (state.joystickTouchId ~= nil)

    if isJoy then
        -- 浮动模式：绘制在触摸起始位置
        local fCx = state.joystickFloatCx
        local fCy = state.joystickFloatCy

        -- 外圈
        nvgBeginPath(ctx)
        nvgCircle(ctx, fCx, fCy, jo.outerR)
        nvgFillColor(ctx, nvgRGBAf(1, 1, 1, 0.12))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, fCx, fCy, jo.outerR)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 100))
        nvgStrokeWidth(ctx, 1.2)
        nvgStroke(ctx)

        -- 十字辅助线
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, fCx - jo.outerR * 0.5, fCy)
        nvgLineTo(ctx, fCx + jo.outerR * 0.5, fCy)
        nvgMoveTo(ctx, fCx, fCy - jo.outerR * 0.5)
        nvgLineTo(ctx, fCx, fCy + jo.outerR * 0.5)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 25))
        nvgStrokeWidth(ctx, 0.8)
        nvgStroke(ctx)

        -- 内手柄（按浮动中心偏移）
        local hx = fCx + state.joystickDx * jo.outerR
        local hy = fCy + state.joystickDy * jo.outerR
        nvgBeginPath(ctx)
        nvgCircle(ctx, hx, hy, jo.innerR)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 200))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, hx, hy, jo.innerR)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 240))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)
    end

    -- ── 攻击按钮（右下角，较大）──────────────────────────────────
    local atk = layout.btnAttack
    local atkPressed = state.attackTouchId ~= nil
    local atkAlpha = atkPressed and 0.3 or 0.12
    local atkBorderA = atkPressed and 220 or 100

    nvgBeginPath(ctx)
    nvgCircle(ctx, atk.cx, atk.cy, atk.r)
    nvgFillColor(ctx, nvgRGBAf(1, 1, 1, atkAlpha))
    nvgFill(ctx)
    nvgBeginPath(ctx)
    nvgCircle(ctx, atk.cx, atk.cy, atk.r)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, atkBorderA))
    nvgStrokeWidth(ctx, atkPressed and 2.5 or 1.5)
    nvgStroke(ctx)

    -- 攻击图标：准星（十字 + 圆环）
    local crossR = atk.r * 0.4
    nvgBeginPath(ctx)
    nvgCircle(ctx, atk.cx, atk.cy, crossR)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, atkPressed and 255 or 180))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)
    -- 十字线
    local lineR = atk.r * 0.6
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, atk.cx - lineR, atk.cy)
    nvgLineTo(ctx, atk.cx - crossR - 2, atk.cy)
    nvgMoveTo(ctx, atk.cx + crossR + 2, atk.cy)
    nvgLineTo(ctx, atk.cx + lineR, atk.cy)
    nvgMoveTo(ctx, atk.cx, atk.cy - lineR)
    nvgLineTo(ctx, atk.cx, atk.cy - crossR - 2)
    nvgMoveTo(ctx, atk.cx, atk.cy + crossR + 2)
    nvgLineTo(ctx, atk.cx, atk.cy + lineR)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, atkPressed and 255 or 180))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)

    -- ── 3个按钮弧线布局（攻击键周围）──────────────────────
    -- 搜索（放大镜）
    local bs = layout.btnSearch
    drawCircleBtnBase(ctx, bs.cx, bs.cy, bs.r, state.searchTouchId ~= nil, searchAvail)
    drawIconSearch(ctx, bs.cx, bs.cy, bs.r, state.searchTouchId ~= nil, searchAvail)

    -- 换弹（子弹）
    local br = layout.btnReload
    drawCircleBtnBase(ctx, br.cx, br.cy, br.r, state.reloadTouchId ~= nil, true)
    drawIconBullet(ctx, br.cx, br.cy, br.r, state.reloadTouchId ~= nil, true)

    -- 翻滚（脚印）
    drawRollBtn(ctx, layout.btnRoll.cx, layout.btnRoll.cy, layout.btnRoll.r,
        state.rollTouchId ~= nil, rollCd)

    -- 背包（药品快捷栏右侧）
    local bb = layout.btnBag
    drawCircleBtnBase(ctx, bb.cx, bb.cy, bb.r, false, true)
    drawIconBag(ctx, bb.cx, bb.cy, bb.r, false, true)

    -- ── 暂停/换枪按钮（层数面板左侧，医疗用品同款像素风）─────────────
    local ps = layout.btnPause
    local sp = layout.btnSwap

    -- 暂停按钮（像素风硬边格子）
    nvgBeginPath(ctx)
    nvgRect(ctx, ps.x, ps.y, ps.w, ps.h)
    nvgFillColor(ctx, nvgRGBA(10, 15, 20, 200))
    nvgFill(ctx)
    nvgBeginPath(ctx)
    nvgRect(ctx, ps.x, ps.y, ps.w, ps.h)
    nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, 100))
    nvgStrokeWidth(ctx, 1.0)
    nvgStroke(ctx)
    -- 暂停图标（双竖线）
    local pIco = ps.w * 0.15
    nvgBeginPath(ctx)
    nvgRect(ctx, ps.cx - pIco * 1.2, ps.cy - pIco * 1.5, pIco, pIco * 3)
    nvgRect(ctx, ps.cx + pIco * 0.2, ps.cy - pIco * 1.5, pIco, pIco * 3)
    nvgFillColor(ctx, nvgRGBA(0, 240, 255, 200))
    nvgFill(ctx)
    -- 标签
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 7)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, nvgRGBA(180, 200, 210, 160))
    nvgText(ctx, ps.cx, ps.y + ps.h - 2, "暂停", nil)

    -- 换枪按钮（像素风硬边格子）
    nvgBeginPath(ctx)
    nvgRect(ctx, sp.x, sp.y, sp.w, sp.h)
    nvgFillColor(ctx, nvgRGBA(10, 15, 20, 200))
    nvgFill(ctx)
    nvgBeginPath(ctx)
    nvgRect(ctx, sp.x, sp.y, sp.w, sp.h)
    nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, 100))
    nvgStrokeWidth(ctx, 1.0)
    nvgStroke(ctx)
    -- 换枪图标
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, sp.w * 0.45)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0, 240, 255, 200))
    nvgText(ctx, sp.cx, sp.cy - 2, "⇄", nil)
    -- 标签
    nvgFontSize(ctx, 7)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, nvgRGBA(180, 200, 210, 160))
    nvgText(ctx, sp.cx, sp.y + sp.h - 2, "换枪", nil)

    -- ── 撤离按钮（仅 nearExit 时显示）────────────────────────────
    if nearExit then
        local eb = layout.btnEvac
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, eb.x, eb.y, eb.w, eb.h, 6)
        nvgFillColor(ctx, nvgRGBAf(1, 1, 1, 0.18))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, eb.x, eb.y, eb.w, eb.h, 6)
        nvgStrokeColor(ctx, nvgRGBA(120, 255, 180, 180))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, eb.h * 0.5)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(120, 255, 180, 230))
        nvgText(ctx, eb.cx, eb.cy, "🚁 撤离", nil)
    end
end

-- 游戏结束/菜单界面"继续"按钮（白描风格）
function M.DrawContinueBtn(ctx, sw, sh, label)
    local cx = sw * 0.5
    local cy = sh * 0.88
    local r  = math.min(sw, sh) * 0.07
    local bw = r * 2.4
    local bh = r * 1.4
    local bx = cx - bw / 2
    local by = cy - bh / 2

    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, bx, by, bw, bh, 6)
    nvgFillColor(ctx, nvgRGBAf(1, 1, 1, 0.20))
    nvgFill(ctx)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, bx, by, bw, bh, 6)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 160))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)

    nvgFontSize(ctx, r * 0.7)
    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
    nvgText(ctx, cx, cy, label or "继续", nil)
    return { cx = cx, cy = cy, r = r }
end

return M
