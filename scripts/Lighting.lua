-- ============================================================================
-- Lighting.lua — 动态光源系统（逐瓦片叠加）
-- ============================================================================
-- 用法：
--   Lighting.AddLight(x, y, radius, r, g, b, intensity, duration)
--   Lighting.Update(dt)
--   Lighting.GetTileLight(worldX, worldY)  -- 返回 lr, lg, lb (0~255 范围的叠加亮度)
--
-- 光源类型：
--   - 枪口闪光：白色/暖黄，半径大，持续 0.05~0.1s，强度高
--   - 火光：橙色，半径中等，持续性，强度抖动
--   - 爆炸：橙红，半径极大，持续 0.3s，衰减快
-- ============================================================================

local M = {}

-- 活跃光源列表
M.lights = {}

-- 持久光源（如火把、篝火）
M.persistentLights = {}

--- 添加一个临时光源（自动消失）
---@param x number 世界坐标X
---@param y number 世界坐标Y
---@param radius number 光照半径（像素）
---@param r number 颜色R (0~255)
---@param g number 颜色G (0~255)
---@param b number 颜色B (0~255)
---@param intensity number 强度 (0~1)
---@param duration number 持续时间（秒）
function M.AddLight(x, y, radius, r, g, b, intensity, duration)
    M.lights[#M.lights + 1] = {
        x = x, y = y,
        radius = radius,
        r = r, g = g, b = b,
        intensity = intensity or 1.0,
        life = duration or 0.1,
        maxLife = duration or 0.1,
    }
end

--- 添加持久光源（不会自动消失，需手动移除）
---@param id string 唯一标识
---@param x number 世界坐标X
---@param y number 世界坐标Y
---@param radius number 光照半径
---@param r number 颜色R
---@param g number 颜色G
---@param b number 颜色B
---@param intensity number 强度
---@param flicker number|nil 闪烁幅度 (0~0.5)，nil=不闪烁
function M.AddPersistentLight(id, x, y, radius, r, g, b, intensity, flicker)
    M.persistentLights[id] = {
        x = x, y = y,
        radius = radius,
        r = r, g = g, b = b,
        intensity = intensity or 1.0,
        flicker = flicker or 0,
        phase = math.random() * math.pi * 2,  -- 随机起始相位
    }
end

--- 移除持久光源
function M.RemovePersistentLight(id)
    M.persistentLights[id] = nil
end

--- 更新所有临时光源（每帧调用）
function M.Update(dt)
    for i = #M.lights, 1, -1 do
        local l = M.lights[i]
        l.life = l.life - dt
        if l.life <= 0 then
            table.remove(M.lights, i)
        end
    end
end

--- 计算某个世界坐标点受到的总光照贡献
--- 返回 lr, lg, lb (叠加亮度，0~255 范围，可以直接用于白色/彩色叠加)
---@param wx number 瓦片中心世界坐标X
---@param wy number 瓦片中心世界坐标Y
---@param time number 当前时间（用于闪烁计算）
---@return number lr
---@return number lg
---@return number lb
function M.GetTileLight(wx, wy, time)
    local lr, lg, lb = 0, 0, 0
    time = time or 0

    -- 临时光源
    for _, l in ipairs(M.lights) do
        local dx = wx - l.x
        local dy = wy - l.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < l.radius then
            -- 衰减：线性+平方混合，边缘柔和
            local t = dist / l.radius
            local atten = (1.0 - t) * (1.0 - t * t)  -- 二次衰减
            -- 生命衰减（光源临消失时减弱）
            local lifeFade = math.min(1.0, l.life / (l.maxLife * 0.3))
            local contribution = atten * l.intensity * lifeFade
            lr = lr + l.r * contribution
            lg = lg + l.g * contribution
            lb = lb + l.b * contribution
        end
    end

    -- 持久光源
    for _, l in pairs(M.persistentLights) do
        local dx = wx - l.x
        local dy = wy - l.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < l.radius then
            local t = dist / l.radius
            local atten = (1.0 - t) * (1.0 - t * t)
            -- 闪烁
            local flick = 1.0
            if l.flicker > 0 then
                flick = 1.0 - l.flicker * (0.5 + 0.5 * math.sin(time * 8.0 + l.phase))
                -- 额外高频噪声
                flick = flick - l.flicker * 0.3 * math.sin(time * 23.0 + l.phase * 2.7)
                flick = math.max(0.3, math.min(1.0, flick))
            end
            local contribution = atten * l.intensity * flick
            lr = lr + l.r * contribution
            lg = lg + l.g * contribution
            lb = lb + l.b * contribution
        end
    end

    -- 限制在 0~255
    lr = math.min(255, lr)
    lg = math.min(255, lg)
    lb = math.min(255, lb)

    return lr, lg, lb
end

--- 从枪口闪光同步创建光源（每次射击时调用）
---@param x number 枪口世界X
---@param y number 枪口世界Y
---@param wtype string|nil 武器类型
function M.AddMuzzleFlashLight(x, y, wtype)
    -- 根据武器类型调整光源参数
    local r, g, b = 255, 220, 150      -- 暖黄白
    local radius = 120                  -- 光照半径
    local intensity = 0.8
    local duration = 0.08

    if wtype == "shotgun" then
        r, g, b = 255, 180, 80          -- 更橙
        radius = 150
        intensity = 1.0
        duration = 0.10
    elseif wtype == "sniper" then
        r, g, b = 255, 240, 200         -- 偏白
        radius = 180
        intensity = 1.0
        duration = 0.06
    elseif wtype == "pistol" then
        radius = 90
        intensity = 0.6
        duration = 0.06
    elseif wtype == "smg" then
        radius = 100
        intensity = 0.5
        duration = 0.05
    elseif wtype == "hmg" then
        r, g, b = 255, 200, 100
        radius = 140
        intensity = 0.9
        duration = 0.07
    end

    M.AddLight(x, y, radius, r, g, b, intensity, duration)
end

--- 添加爆炸光源
function M.AddExplosionLight(x, y)
    M.AddLight(x, y, 250, 255, 160, 60, 1.0, 0.35)
end

--- 添加道具发光（高稀有度掉落物）
---@param id string 唯一标识（用于移除）
---@param x number 世界坐标X
---@param y number 世界坐标Y
---@param rarity number 稀有度 1~5
function M.AddItemGlow(id, x, y, rarity)
    if rarity < 3 then return end
    local params = {
        [3] = { radius = 50,  r = 80,  g = 140, b = 255, intensity = 0.4 },  -- 蓝
        [4] = { radius = 65,  r = 200, g = 80,  b = 255, intensity = 0.5 },  -- 紫
        [5] = { radius = 80,  r = 255, g = 160, b = 60,  intensity = 0.6 },  -- 金
    }
    local p = params[rarity] or params[3]
    M.AddPersistentLight(id, x, y, p.radius, p.r, p.g, p.b, p.intensity, 0.15)
end

--- 移除道具发光
function M.RemoveItemGlow(id)
    M.RemovePersistentLight(id)
end

-- ============================================================================
-- 环境暗色底层（路径 B：全屏暗色覆盖 + 光源"刮亮"）
-- ============================================================================

--- 层段环境光参数
local FLOOR_AMBIENT = {
    -- floor 1~5: 矿道（紫灰）
    { r = 20, g = 18, b = 28, alpha = 140 },
    -- floor 6~10: 洞穴（棕灰）
    { r = 25, g = 22, b = 16, alpha = 150 },
    -- floor 11~15: 熔岩（暗红）
    { r = 30, g = 12, b = 8,  alpha = 150 },
    -- floor 16~20: 虚空（深紫）
    { r = 12, g = 8,  b = 24, alpha = 160 },
}

--- 获取当前层段的环境暗色参数
---@param floor number 当前楼层
---@return table {r, g, b, alpha}
function M.GetAmbientForFloor(floor)
    local idx = math.min(4, math.max(1, math.ceil(floor / 5)))
    return FLOOR_AMBIENT[idx] or FLOOR_AMBIENT[1]
end

--- 渲染环境暗色底层（路径 B）
--- 先覆盖全屏半透明暗色，再用光源"刮亮"区域
---@param ctx userdata NanoVG context
---@param sw number 屏幕宽度（世界空间）
---@param sh number 屏幕高度（世界空间）
---@param camX number 摄像机偏移X
---@param camY number 摄像机偏移Y
---@param floor number 当前楼层
---@param time number 当前时间
---@param playerX number 玩家世界坐标X
---@param playerY number 玩家世界坐标Y
function M.RenderAmbientDarkness(ctx, sw, sh, camX, camY, floor, time, playerX, playerY)
    local ambient = M.GetAmbientForFloor(floor)

    -- 以玩家为中心的径向暗色渐变（带色调的氛围暗化）
    -- 内圈透明（玩家附近不受影响），外圈叠加层段色调暗色
    -- 火炬等光源的照亮效果由 DrawLighting 的 additive 光晕单独处理
    local psx = playerX - camX
    local psy = playerY - camY
    local innerR = 120   -- 玩家周围清晰区
    local outerR = 350   -- 过渡结束

    local grad = nvgRadialGradient(ctx, psx, psy, innerR, outerR,
        nvgRGBA(ambient.r, ambient.g, ambient.b, 0),
        nvgRGBA(ambient.r, ambient.g, ambient.b, ambient.alpha))
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, sw, sh)
    nvgFillPaint(ctx, grad)
    nvgFill(ctx)
end

-- ============================================================================
-- 暗角（Vignette）
-- ============================================================================

--- 层段暗角强度
local FLOOR_VIGNETTE = {
    0.25,   -- floor 1~5: 浅暗角
    0.35,   -- floor 6~10: 标准暗角
    0.40,   -- floor 11~15: 偏重
    0.50,   -- floor 16~20: 重暗角
}

--- 获取当前层段的暗角强度
---@param floor number
---@return number intensity
function M.GetVignetteIntensity(floor)
    local idx = math.min(4, math.max(1, math.ceil(floor / 5)))
    return FLOOR_VIGNETTE[idx] or FLOOR_VIGNETTE[1]
end

--- 渲染暗角效果
---@param ctx userdata NanoVG context
---@param sw number 屏幕宽度
---@param sh number 屏幕高度
---@param intensity number 暗角强度 0~1
function M.RenderVignette(ctx, sw, sh, intensity)
    if intensity <= 0 then return end

    local cx = sw * 0.5
    local cy = sh * 0.5
    local maxDist = math.sqrt(cx * cx + cy * cy)

    local grad = nvgRadialGradient(ctx, cx, cy, maxDist * 0.55, maxDist,
        nvgRGBA(0, 0, 0, 0),
        nvgRGBA(0, 0, 0, math.floor(255 * intensity)))

    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, sw, sh)
    nvgFillPaint(ctx, grad)
    nvgFill(ctx)
end

-- ============================================================================
-- 静态光源注册辅助（房间火炬）
-- ============================================================================

--- 为一个房间生成火炬光源（四角或门两侧）
---@param room table 房间数据 {x, y, w, h}
---@param tileSize number 瓦片尺寸
---@param floor number 当前楼层（决定火炬色调）
function M.RegisterRoomTorches(room, tileSize, floor)
    -- 根据层段选择火炬颜色
    local torchColors = {
        { r = 255, g = 160, b = 80 },   -- 矿道：暖橙
        { r = 255, g = 180, b = 60 },   -- 洞穴：暖黄
        { r = 255, g = 100, b = 30 },   -- 熔岩：赤橙
        { r = 150, g = 130, b = 255 },  -- 虚空：冷蓝紫
    }
    local idx = math.min(4, math.ceil(floor / 5))
    local tc = torchColors[idx]

    -- 房间太小（< 7格宽/高）不放火炬
    if room.w < 7 or room.h < 7 then return end

    -- 在房间四角内侧 1.5 格处放火炬
    local corners = {
        { room.x + 1.5, room.y + 1.5 },
        { room.x + room.w - 1.5, room.y + 1.5 },
        { room.x + 1.5, room.y + room.h - 1.5 },
        { room.x + room.w - 1.5, room.y + room.h - 1.5 },
    }

    for i, corner in ipairs(corners) do
        -- 随机跳过一些角（不是每个角都有火炬）
        if math.random() < 0.7 then
            local wx = (corner[1] - 0.5) * tileSize
            local wy = (corner[2] - 0.5) * tileSize
            local id = string.format("torch_%d_%d_%d", room.x, room.y, i)
            M.AddPersistentLight(id, wx, wy, 130, tc.r, tc.g, tc.b, 0.8, 0.25)
        end
    end
end

--- 清空所有光源（切换关卡时）
function M.Clear()
    M.lights = {}
    M.persistentLights = {}
end

return M
