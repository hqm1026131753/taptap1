---@diagnostic disable: access-invisible
-- ============================================================================
-- Slime.lua — 史莱姆小怪模块（待机/走路/跳跃攻击）
-- ============================================================================
local World = require("World")
local PlayerM = require("Player")

local M = {}

-- ============================================================================
-- 动画定义
-- ============================================================================
local ANIMS = {
    idle = {
        sheet = "image/小怪/史莱姆/rika_2328a5e5.png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 1, frames = 12,
        frameW = 128, frameH = 128,
        fps = 4, loop = true,
    },
    walk = {
        sheet = "image/小怪/史莱姆/rika_2328a5e5.png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 1, frames = 12,
        frameW = 128, frameH = 128,
        fps = 8, loop = true,
    },
    -- 跳跃攻击帧图（4x3网格，共10帧）
    jump_windup = {
        sheet = "image/小怪/史莱姆/rika_94047062.png",
        cols = 4, rows = 3, totalFrames = 10,
        startFrame = 1, frames = 2,
        frameW = 128, frameH = 128,
        fps = 5, loop = false,
    },
    jump_up = {
        sheet = "image/小怪/史莱姆/rika_94047062.png",
        cols = 4, rows = 3, totalFrames = 10,
        startFrame = 3, frames = 2,
        frameW = 128, frameH = 128,
        fps = 5, loop = false,
    },
    jump_down = {
        sheet = "image/小怪/史莱姆/rika_94047062.png",
        cols = 4, rows = 3, totalFrames = 10,
        startFrame = 5, frames = 2,
        frameW = 128, frameH = 128,
        fps = 5, loop = false,
    },
    jump_land = {
        sheet = "image/小怪/史莱姆/rika_94047062.png",
        cols = 4, rows = 3, totalFrames = 10,
        startFrame = 7, frames = 2,
        frameW = 128, frameH = 128,
        fps = 5, loop = false,
    },
    jump_recover = {
        sheet = "image/小怪/史莱姆/rika_94047062.png",
        cols = 4, rows = 3, totalFrames = 10,
        startFrame = 9, frames = 2,
        frameW = 128, frameH = 128,
        fps = 4, loop = false,
    },
}

-- 精灵图缓存
local sheets = {}

-- ============================================================================
-- 动画工具
-- ============================================================================

local function SetAnim(e, key)
    if e.slimeAnimKey ~= key then
        e.slimeAnimKey = key
        e.slimeAnimFrame = 1
        e.slimeAnimTimer = 0
    end
end

local function UpdateAnim(e)
    local anim = ANIMS[e.slimeAnimKey]
    if not anim then return 1, true end

    e.slimeAnimTimer = e.slimeAnimTimer + (1.0 / 60.0)
    local frameDur = 1.0 / anim.fps
    if e.slimeAnimTimer >= frameDur then
        e.slimeAnimTimer = e.slimeAnimTimer - frameDur
        e.slimeAnimFrame = e.slimeAnimFrame + 1
        if e.slimeAnimFrame > anim.frames then
            if anim.loop then
                e.slimeAnimFrame = 1
            else
                e.slimeAnimFrame = anim.frames
                return e.slimeAnimFrame, true
            end
        end
    end
    return e.slimeAnimFrame, false
end

-- ============================================================================
-- 初始化
-- ============================================================================
function M.Init(e)
    e.isSlime = true
    e.slimeAnimKey = "idle"
    e.slimeAnimFrame = 1
    e.slimeAnimTimer = 0

    -- 史莱姆 AI 状态
    e.slimeState = "idle"    -- "idle" / "walk" / "jump_attack"
    e.slimeTimer = 0
    e.slimeIdleDur = 1.5 + math.random() * 1.0   -- 待机时长
    e.slimeWalkDur = 1.5 + math.random() * 1.0   -- 走路时长
    e.slimeWalkAngle = math.random() * math.pi * 2

    -- 跳跃攻击参数
    e.slimeJumpState = "none"   -- "windup" / "jumping" / "landing" / "none"
    e.slimeJumpTimer = 0
    e.slimeJumpHeight = 0
    e.slimeJumpStartX = 0
    e.slimeJumpStartY = 0
    e.slimeJumpTargetX = 0
    e.slimeJumpTargetY = 0
    e._slimeAirborne = false
end

-- ============================================================================
-- 更新 AI
-- ============================================================================
function M.Update(e, dt, player)
    e.slimeTimer = e.slimeTimer + dt

    -- 跳跃攻击进行中，优先处理
    if e.slimeJumpState ~= "none" then
        M.UpdateJumpAttack(e, dt, player)
        return
    end

    -- 计算与玩家距离（平方比较，避免 sqrt）
    local dx = player.x - e.x
    local dy = player.y - e.y
    local distSq = dx * dx + dy * dy

    -- 自行管理战斗状态（因为跳过了 Enemy.lua 的通用状态机）
    if distSq < e.detectRange * e.detectRange then
        e.state = "combat"
    elseif distSq > (e.detectRange * 1.8)^2 then
        e.state = "patrol"
    end

    -- 进入战斗范围：触发跳跃攻击
    if e.state == "combat" then
        -- 冷却后跳跃攻击
        if e.slimeState ~= "jump_attack" and e.slimeTimer > 1.5 then
            e.slimeState = "jump_attack"
            e.slimeJumpState = "windup"
            e.slimeJumpTimer = 0
            e.slimeTimer = 0
            SetAnim(e, "jump_windup")
            return
        end
    end

    -- 常规状态机：待机 ↔ 走路
    if e.slimeState == "idle" then
        SetAnim(e, "idle")
        if e.slimeTimer >= e.slimeIdleDur then
            e.slimeState = "walk"
            e.slimeTimer = 0
            e.slimeWalkDur = 1.5 + math.random() * 1.5
            -- 战斗状态朝玩家走，否则随机方向
            if e.state == "combat" and distSq > 1 then
                e.slimeWalkAngle = math.atan2(dy, dx)
            else
                e.slimeWalkAngle = math.random() * math.pi * 2
            end
        end

    elseif e.slimeState == "walk" then
        SetAnim(e, "walk")
        -- 移动
        local spd = e.speed * dt
        e.x = e.x + math.cos(e.slimeWalkAngle) * spd
        e.y = e.y + math.sin(e.slimeWalkAngle) * spd
        -- 朝向
        if math.cos(e.slimeWalkAngle) > 0 then e.facing = 1 else e.facing = -1 end
        World.ResolveWall(e, 12)

        if e.slimeTimer >= e.slimeWalkDur then
            e.slimeState = "idle"
            e.slimeTimer = 0
            e.slimeIdleDur = 1.0 + math.random() * 1.5
        end
    end

    UpdateAnim(e)
end

-- ============================================================================
-- 跳跃攻击
-- ============================================================================
function M.UpdateJumpAttack(e, dt, player)
    e.slimeJumpTimer = e.slimeJumpTimer + dt

    if e.slimeJumpState == "windup" then
        -- 蓄力压缩（2帧/5fps = 0.4s）
        SetAnim(e, "jump_windup")
        UpdateAnim(e)
        local dx = player.x - e.x
        if dx > 0 then e.facing = 1 else e.facing = -1 end

        if e.slimeJumpTimer >= 0.4 then
            e.slimeJumpState = "jumping"
            e.slimeJumpTimer = 0
            e._slimeAirborne = true
            e.slimeJumpStartX = e.x
            e.slimeJumpStartY = e.y
            e.slimeJumpTargetX = player.x
            e.slimeJumpTargetY = player.y
        end

    elseif e.slimeJumpState == "jumping" then
        -- 跳跃飞行（0.5s），前半段用 jump_up，后半段用 jump_down
        local jumpDur = 0.5
        local progress = math.min(e.slimeJumpTimer / jumpDur, 1.0)

        if progress < 0.5 then
            SetAnim(e, "jump_up")
        else
            SetAnim(e, "jump_down")
        end
        UpdateAnim(e)

        -- 高度抛物线
        e.slimeJumpHeight = math.sin(progress * math.pi) * 60

        -- 位移插值
        local moveP = math.min(progress / 0.9, 1.0)
        e.x = e.slimeJumpStartX + (e.slimeJumpTargetX - e.slimeJumpStartX) * moveP
        e.y = e.slimeJumpStartY + (e.slimeJumpTargetY - e.slimeJumpStartY) * moveP
        World.ResolveWall(e, 12)

        if e.slimeJumpTimer >= jumpDur then
            -- 落地
            e.slimeJumpState = "landing"
            e.slimeJumpTimer = 0
            e.slimeJumpHeight = 0
            e._slimeAirborne = false

            -- 碰撞伤害判定（平方比较）
            local dx2 = player.x - e.x
            local dy2 = player.y - e.y
            if dx2*dx2 + dy2*dy2 < 2025 then -- 45^2
                PlayerM.ApplyDamage(player, e.damage, e.x, e.y)
            end
        end

    elseif e.slimeJumpState == "landing" then
        -- 落地冲击（2帧/5fps = 0.4s）
        SetAnim(e, "jump_land")
        UpdateAnim(e)
        if e.slimeJumpTimer >= 0.4 then
            e.slimeJumpState = "recover"
            e.slimeJumpTimer = 0
        end

    elseif e.slimeJumpState == "recover" then
        -- 恢复（2帧/4fps = 0.5s）
        SetAnim(e, "jump_recover")
        UpdateAnim(e)
        if e.slimeJumpTimer >= 0.5 then
            e.slimeJumpState = "none"
            e.slimeState = "idle"
            e.slimeTimer = 0
            e.slimeIdleDur = 1.0 + math.random() * 0.5
        end
    end
end

-- ============================================================================
-- 绘制
-- ============================================================================
function M.Draw(ctx, e, camX, camY)
    local sx = e.x - camX
    local sy = e.y - camY

    local size = 60  -- 史莱姆绘制尺寸（放大50%）

    -- 阴影
    local shadowScale = 1.0
    if e._slimeAirborne then
        shadowScale = 0.6
    end
    nvgBeginPath(ctx)
    nvgEllipse(ctx, sx, sy + size * 0.15, size * 0.3 * shadowScale, size * 0.08 * shadowScale)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 50))
    nvgFill(ctx)

    -- 身体 Y 偏移（跳跃时）
    local bodyY = sy - (e.slimeJumpHeight or 0)

    -- 形变效果（有专用动画帧，仅做轻微弹性辅助）
    local scaleX, scaleY = 1.0, 1.0
    if e.slimeJumpState == "windup" then
        local t = math.min(e.slimeJumpTimer / 0.4, 1.0)
        scaleX = 1.0 + t * 0.1
        scaleY = 1.0 - t * 0.15
    elseif e.slimeJumpState == "landing" then
        local t = math.min(e.slimeJumpTimer / 0.3, 1.0)
        scaleX = 1.1 - t * 0.1
        scaleY = 0.85 + t * 0.15
    end

    -- 绘制精灵帧
    local anim = ANIMS[e.slimeAnimKey or "idle"]
    if anim then
        if not sheets[anim.sheet] then
            sheets[anim.sheet] = nvgCreateImage(ctx, anim.sheet, 0)
        end
        local img = sheets[anim.sheet]
        if img and img > 0 then
            local frame = (e.slimeAnimFrame or 1)
            local sheetFrame = (anim.startFrame or 1) - 1 + (frame - 1)
            local col = sheetFrame % anim.cols
            local row = math.floor(sheetFrame / anim.cols)

            local sheetW = anim.cols * anim.frameW
            local sheetH = anim.rows * anim.frameH

            local drawW = size * scaleX
            local drawH = size * scaleY
            local drawX = sx - drawW / 2
            local drawY = bodyY - drawH / 2

            nvgSave(ctx)

            -- 翻转
            if e.facing == -1 then
                nvgTranslate(ctx, sx, bodyY)
                nvgScale(ctx, -1, 1)
                nvgTranslate(ctx, -sx, -bodyY)
            end

            -- 受击闪白
            local alpha = 1.0
            if e.hitFlash and e.hitFlash > 0 then
                alpha = 0.5 + 0.5 * math.sin(e.hitFlash * 20)
            end

            local patScaleX = drawW / anim.frameW
            local patScaleY = drawH / anim.frameH
            local patW = sheetW * patScaleX
            local patH = sheetH * patScaleY
            local patX = drawX - col * anim.frameW * patScaleX
            local patY = drawY - row * anim.frameH * patScaleY

            local pat = nvgImagePattern(ctx, patX, patY, patW, patH, 0, img, alpha)
            nvgBeginPath(ctx)
            nvgRect(ctx, drawX, drawY, drawW, drawH)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)

            nvgRestore(ctx)
        end
    end

    -- 跳跃攻击落地冲击波
    if e.slimeJumpState == "landing" or (e.slimeJumpState == "recover" and e.slimeJumpTimer < 0.3) then
        local totalT
        if e.slimeJumpState == "landing" then
            totalT = e.slimeJumpTimer / 0.7
        else
            totalT = (0.4 + e.slimeJumpTimer) / 0.7
        end
        totalT = math.min(totalT, 1.0)
        local r = 50 * totalT
        local a = math.floor(150 * (1.0 - totalT))
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, r)
        nvgStrokeColor(ctx, nvgRGBA(120, 200, 80, a))
        nvgStrokeWidth(ctx, 3 * (1.0 - totalT) + 0.5)
        nvgStroke(ctx)
    end
end

-- ============================================================================
-- 辅助查询
-- ============================================================================
function M.IsSlime(e)
    return e.isSlime == true
end

return M
