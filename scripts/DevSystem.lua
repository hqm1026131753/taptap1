-- ============================================================================
-- DevSystem.lua — 开发者调试系统
-- F1 切换面板 | F2~F9 快捷作弊命令
-- ============================================================================
local M = {}

-- ----------------------------------------------------------------------------
-- 白名单（只有这些 TapTap 用户 ID 才能激活开发者模式）
-- ----------------------------------------------------------------------------
local DEV_WHITELIST = {
    [587393632] = true,
    [447072536] = true,
}

-- ----------------------------------------------------------------------------
-- 状态
-- ----------------------------------------------------------------------------
M.enabled   = false   -- 面板是否显示
M.godMode   = false   -- 无敌模式
M.speedMult = 1       -- 移动速度倍率 (1/2/3)

-- 通知队列
local notifications = {}  -- { text, timer, color }
local NOTIF_DURATION = 1.8

-- FPS 计算
local fpsFrames = 0
local fpsTimer  = 0
local fpsValue  = 0

-- 字体句柄（初始化一次）
local fontInited = false
local fontMono   = -1

-- ----------------------------------------------------------------------------
-- 内部：添加通知
-- ----------------------------------------------------------------------------
local function Notify(text, r, g, b)
    table.insert(notifications, 1, {
        text  = text,
        timer = NOTIF_DURATION,
        r = r or 50, g = g or 220, b = b or 100,
    })
    -- 最多保留 5 条
    if #notifications > 5 then
        table.remove(notifications)
    end
end

-- ----------------------------------------------------------------------------
-- 公共接口
-- ----------------------------------------------------------------------------

--- 检查当前用户是否在白名单中
--- @return boolean
local function IsAuthorized()
    -- 研发阶段：开放开发者模式（发布前改回白名单验证）
    return true
end

--- 切换 Dev 面板（白名单验证）
function M.Toggle()
    if not M.enabled and not IsAuthorized() then
        -- 非白名单用户无法开启
        return
    end
    M.enabled = not M.enabled
    Notify(M.enabled and "DEV PANEL: ON" or "DEV PANEL: OFF")
end

-- ----------------------------------------------------------------------------
-- 触摸激活：连续快速点击左上角 5 次开启/关闭面板
-- ----------------------------------------------------------------------------
local tapCount = 0
local tapTimer = 0
local TAP_ZONE = 60      -- 左上角热区大小（像素）
local TAP_TIMEOUT = 2.0  -- 2秒内点满5次

--- 每帧更新 tap 计时器（需在 Update 中调用）
function M.UpdateTapTimer(dt)
    if tapTimer > 0 then
        tapTimer = tapTimer - dt
        if tapTimer <= 0 then
            tapCount = 0
        end
    end
end

--- 触摸/点击时调用，传入屏幕坐标
--- @param x number
--- @param y number
function M.HandleTap(x, y)
    if x < TAP_ZONE and y < TAP_ZONE then
        tapCount = tapCount + 1
        tapTimer = TAP_TIMEOUT
        if tapCount >= 5 then
            tapCount = 0
            tapTimer = 0
            M.Toggle()
        end
    else
        tapCount = 0
        tapTimer = 0
    end
end

--- 处理快捷键（仅 Dev 开启时调用）
--- @param key number 按键码
--- @param actions table 回调表 { killAll, teleportExit, nextFloor, fullHeal, giveWeapons, giveMoney }
--- @return boolean 是否已消费该按键
function M.HandleKey(key, actions)
    if not M.enabled then return false end

    if key == KEY_F2 then
        M.godMode = not M.godMode
        Notify("GOD MODE: " .. (M.godMode and "ON" or "OFF"),
               M.godMode and 255 or 200,
               M.godMode and 200 or 80,
               50)
        return true

    elseif key == KEY_F3 then
        if actions.killAll then actions.killAll() end
        Notify("KILL ALL ENEMIES", 255, 80, 80)
        return true

    elseif key == KEY_F4 then
        if actions.nextFloor then actions.nextFloor() end
        Notify("SKIP TO NEXT FLOOR", 200, 150, 255)
        return true

    elseif key == KEY_F5 then
        if actions.teleportExit then actions.teleportExit() end
        Notify("TELEPORT TO EXIT", 80, 180, 255)
        return true

    elseif key == KEY_F6 then
        if actions.fullHeal then actions.fullHeal() end
        Notify("FULL HEAL + ARMOR", 100, 255, 100)
        return true

    elseif key == KEY_F7 then
        if actions.giveWeapons then actions.giveWeapons() end
        Notify("GIVE LEGENDARY WEAPONS", 255, 200, 50)
        return true

    elseif key == KEY_F8 then
        M.speedMult = M.speedMult % 3 + 1  -- 1→2→3→1
        Notify("SPEED: x" .. M.speedMult, 180, 220, 255)
        return true

    elseif key == KEY_F9 then
        if actions.giveMoney then actions.giveMoney() end
        Notify("MONEY +10000", 255, 215, 0)
        return true
    end

    return false
end

--- 每帧更新（计算 FPS、递减通知计时器）
--- @param dt number
function M.Update(dt)
    -- FPS
    fpsFrames = fpsFrames + 1
    fpsTimer  = fpsTimer + dt
    if fpsTimer >= 0.5 then
        fpsValue  = math.floor(fpsFrames / fpsTimer + 0.5)
        fpsFrames = 0
        fpsTimer  = 0
    end

    -- 通知衰减
    for i = #notifications, 1, -1 do
        notifications[i].timer = notifications[i].timer - dt
        if notifications[i].timer <= 0 then
            table.remove(notifications, i)
        end
    end
end

--- NanoVG 渲染（面板 + 通知）
--- @param ctx userdata NanoVG context
--- @param sw number 屏幕宽
--- @param sh number 屏幕高
--- @param info table 游戏状态信息
function M.Draw(ctx, sw, sh, info)
    -- 无内容时早退，避免无谓开销
    if not M.enabled and not M.godMode and #notifications == 0 then
        return
    end

    -- 初始化字体（只执行一次）
    if not fontInited then
        fontMono = nvgCreateFont(ctx, "dev-mono", "Fonts/MiSans-Regular.ttf")
        fontInited = true
    end

    nvgSave(ctx)
    nvgReset(ctx)

    -- ========== 信息面板（左上角） ==========
    if M.enabled then
        local px, py = 10, 10
        local pw, ph = 230, 260

        -- 背景
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, px, py, pw, ph, 6)
        nvgFillColor(ctx, nvgRGBA(15, 15, 25, 210))
        nvgFill(ctx)

        -- 边框
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, px, py, pw, ph, 6)
        nvgStrokeColor(ctx, nvgRGBA(80, 200, 120, 180))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)

        -- 标题
        nvgFontFace(ctx, "dev-mono")
        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, nvgRGBA(80, 220, 120, 255))
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgText(ctx, px + 8, py + 8, "[ DEV SYSTEM ]")

        -- 内容行
        nvgFontSize(ctx, 12)
        nvgFillColor(ctx, nvgRGBA(220, 220, 220, 240))

        local lineY = py + 30
        local lineH = 18

        local function drawLine(label, value)
            nvgText(ctx, px + 8, lineY, label .. ": " .. tostring(value))
            lineY = lineY + lineH
        end

        drawLine("FPS",     fpsValue)
        drawLine("State",   info.state or "?")
        drawLine("Floor",   (info.floor or 1) .. (info.isBoss and " [BOSS]" or ""))

        if info.player then
            local p = info.player
            drawLine("Pos",     string.format("%.0f, %.0f", p.x or 0, p.y or 0))
            drawLine("HP",      string.format("%.0f / %.0f", p.hp or 0, p.maxHp or 0))
            drawLine("Armor",   string.format("%.0f", p.armor or 0))
        else
            drawLine("Player", "nil")
        end

        drawLine("Enemies",  info.enemyCount or 0)
        drawLine("Bullets",  info.bulletCount or 0)
        drawLine("Camera",   string.format("%.0f, %.0f", info.camX or 0, info.camY or 0))
        drawLine("Elapsed",  string.format("%.1fs", info.elapsed or 0))

        -- 状态标记
        lineY = lineY + 6
        if M.godMode then
            nvgFillColor(ctx, nvgRGBA(255, 200, 50, 255))
            nvgText(ctx, px + 8, lineY, "** GOD MODE **")
            lineY = lineY + lineH
        end
        if M.speedMult > 1 then
            nvgFillColor(ctx, nvgRGBA(180, 220, 255, 255))
            nvgText(ctx, px + 8, lineY, "** SPEED x" .. M.speedMult .. " **")
            lineY = lineY + lineH
        end

        -- 快捷键提示（底部）
        nvgFontSize(ctx, 10)
        nvgFillColor(ctx, nvgRGBA(140, 140, 140, 200))
        local helpY = py + ph - 60
        nvgText(ctx, px + 8, helpY,      "F2:God  F3:Kill  F4:TP Exit")
        nvgText(ctx, px + 8, helpY + 13, "F5:Next  F6:Heal  F7:Guns")
        nvgText(ctx, px + 8, helpY + 26, "F8:Speed  F9:Money")
    end

    -- ========== 通知（顶部居中） ==========
    if #notifications > 0 then
        nvgFontFace(ctx, "dev-mono")
        nvgFontSize(ctx, 16)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

        for i, n in ipairs(notifications) do
            local alpha = math.min(1.0, n.timer / 0.4) * 255
            local ny = 50 + (i - 1) * 26

            -- 背景条
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, sw * 0.5 - 140, ny - 2, 280, 22, 4)
            nvgFillColor(ctx, nvgRGBA(15, 15, 25, math.floor(alpha * 0.7)))
            nvgFill(ctx)

            -- 文字
            nvgFillColor(ctx, nvgRGBA(n.r, n.g, n.b, math.floor(alpha)))
            nvgText(ctx, sw * 0.5, ny, n.text)
        end
    end

    -- ========== God Mode 指示器（右上角小标） ==========
    if M.godMode and not M.enabled then
        nvgFontFace(ctx, "dev-mono")
        nvgFontSize(ctx, 12)
        nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(ctx, nvgRGBA(255, 200, 50, 200))
        nvgText(ctx, sw - 10, 10, "[GOD]")
    end

    nvgRestore(ctx)
end

return M
