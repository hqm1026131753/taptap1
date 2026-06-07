-- ============================================================================
-- Boss3.lua — 装甲机猫 Boss 系统（帧动画 + 技能状态机）
-- 定位：第15层中期Boss，重型装甲+盾+炮，左手盾右手炮背部反应堆
-- ============================================================================
local World = require("World")
local Audio = require("AudioManager")

local M = {}

-- ============================================================================
-- Spritesheet 帧动画系统（与 Boss1/Boss2 相同机制）
-- ============================================================================
local sheets = {}  -- 缓存加载的 spritesheet nvg 句柄

-- 动画定义（待用户提供图片后填入路径）
local ANIMS = {
    idle = {
        sheet = "image/boss/BOSS3/rika_2ed2be4d.png",
        cols = 4, rows = 2, totalFrames = 8,
        startFrame = 1, frames = 8,
        frameW = 256, frameH = 256,
        fps = 6, loop = true,
    },
    walk = {
        sheet = "image/boss/BOSS3/rika_a7420eb2.png",
        cols = 4, rows = 4, totalFrames = 13,
        startFrame = 1, frames = 8,
        frameW = 256, frameH = 256,
        fps = 7, loop = true,
    },
    -- 盾牌冲锋（蓄力+冲刺）
    charge_windup = {
        sheet = "image/boss/BOSS3/rika_a7420eb2.png",
        cols = 4, rows = 4, totalFrames = 13,
        startFrame = 9, frames = 2,
        frameW = 256, frameH = 256,
        fps = 4, loop = false,
    },
    charge_rush = {
        sheet = "image/boss/BOSS3/rika_a7420eb2.png",
        cols = 4, rows = 4, totalFrames = 13,
        startFrame = 9, frames = 5,
        frameW = 256, frameH = 256,
        fps = 8, loop = true,
    },
    -- 激光扫射（蓄力+发射+收束）
    laser_windup = {
        sheet = "image/boss/BOSS3/rika_6f6886f0.png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 1, frames = 4,
        frameW = 256, frameH = 256,
        fps = 4, loop = false,
    },
    laser_fire = {
        sheet = "image/boss/BOSS3/rika_6f6886f0.png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 5, frames = 4,
        frameW = 256, frameH = 256,
        fps = 7, loop = true,
    },
    -- 高射炮（展开开火+变形大炮+收束）
    cannon_windup = {
        sheet = "image/boss/BOSS3/rika_1b078ced2.png",
        cols = 4, rows = 5, totalFrames = 20,
        startFrame = 1, frames = 8,
        frameW = 256, frameH = 256,
        fps = 7, loop = false,
    },
    cannon_fire = {
        sheet = "image/boss/BOSS3/rika_1b078ced2.png",
        cols = 4, rows = 5, totalFrames = 20,
        startFrame = 9, frames = 8,
        frameW = 256, frameH = 256,
        fps = 8, loop = true,
    },
    -- 狂暴（复用idle，通过drawSize放大+冒烟粒子表现）
    berserk = {
        sheet = "image/boss/BOSS3/rika_2ed2be4d.png",
        cols = 4, rows = 2, totalFrames = 8,
        startFrame = 1, frames = 8,
        frameW = 256, frameH = 256,
        fps = 7, loop = true,
    },
    -- 受击（复用idle前2帧闪烁）
    hit = {
        sheet = "image/boss/BOSS3/rika_2ed2be4d.png",
        cols = 4, rows = 2, totalFrames = 8,
        startFrame = 1, frames = 2,
        frameW = 256, frameH = 256,
        fps = 7, loop = false,
    },
}

-- ============================================================================
-- 动画工具
-- ============================================================================

--- 绘制单帧（与 Boss1/Boss2 相同的精确 pattern 计算）
function M.DrawFrame(ctx, animKey, frameIndex, x, y, size, flipX)
    local anim = ANIMS[animKey]
    if not anim then return end

    -- 加载 spritesheet（只加载一次）
    if not sheets[anim.sheet] then
        sheets[anim.sheet] = nvgCreateImage(ctx, anim.sheet, 0)
    end
    local img = sheets[anim.sheet]
    if not img or img <= 0 then return end

    -- 支持 startFrame 偏移：frameIndex 是 1-based 局部索引
    local sheetFrame = (anim.startFrame or 1) - 1 + (frameIndex - 1)  -- 0-based global
    local col = sheetFrame % anim.cols
    local row = math.floor(sheetFrame / anim.cols)

    local s = size or 64
    local drawX = x - s / 2
    local drawY = y - s / 2

    nvgSave(ctx)

    if flipX then
        nvgTranslate(ctx, x, y)
        nvgScale(ctx, -1, 1)
        nvgTranslate(ctx, -x, -y)
    end

    -- 用 imagePattern 对整个 sheet 做映射，只显示当前帧
    local patScale = s / anim.frameW
    local patW = anim.cols * anim.frameW * patScale
    local patH = anim.rows * anim.frameH * patScale
    local patX = drawX - col * anim.frameW * patScale
    local patY = drawY - row * anim.frameH * patScale

    local pat = nvgImagePattern(ctx, patX, patY, patW, patH, 0, img, 1.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, drawX, drawY, s, s)
    nvgFillPaint(ctx, pat)
    nvgFill(ctx)

    nvgRestore(ctx)
end

--- 设置当前动画（不重复设置）
function M.SetAnim(boss, key)
    if boss.animKey ~= key then
        boss.animKey = key
        boss.animFrame = 1
        boss.animTimer = 0
    end
end

--- 更新动画帧计时，返回 (当前帧, 是否完毕)
function M.UpdateAnim(boss, _)
    local anim = ANIMS[boss.animKey]
    if not anim then return 1, true end

    boss.animTimer = boss.animTimer + (1.0 / 60.0)
    local frameDur = 1.0 / anim.fps
    if boss.animTimer >= frameDur then
        boss.animTimer = boss.animTimer - frameDur
        boss.animFrame = boss.animFrame + 1
        if boss.animFrame > anim.frames then
            if anim.loop then
                boss.animFrame = 1
            else
                boss.animFrame = anim.frames
                return boss.animFrame, true  -- 完毕
            end
        end
    end
    return boss.animFrame, false
end

-- ============================================================================
-- 技能枚举与冷却
-- ============================================================================
local SKILL = {
    IDLE         = "idle",
    CHARGE       = "charge",        -- 盾牌冲锋
    LASER        = "laser",         -- 激光扫射
    CANNON       = "cannon",        -- 炮击
}

local SKILL_CD = {
    charge  = 8.0,
    laser   = 8.0,
    cannon  = 5.0,
}

-- 狂暴模式：冷却减半
local BERSERK_CD_MULT = 0.5

-- ============================================================================
-- 初始化
-- ============================================================================

--- 创建装甲机猫 Boss 实例
function M.InitArmoredCat(enemy)
    enemy.bossType = "armored_cat"

    -- 动画状态
    enemy.animKey   = "idle"
    enemy.animFrame = 1
    enemy.animTimer = 0

    -- 技能状态机
    enemy.skill       = SKILL.IDLE
    enemy.skillTimer  = 0
    enemy.skillCD     = {}
    for k, _ in pairs(SKILL_CD) do
        enemy.skillCD[k] = 0
    end
    enemy.idleDuration = 1.5
    enemy.idleTimer    = 0
    enemy._attackCount = 0           -- 连续攻击计数
    enemy._walkPhase   = 0           -- 攻击间走路段数（0=正常，1/2=强制走路中）
    enemy._walkPhaseDur = 1.2        -- 每段走路持续时间
    enemy._walkPhaseTimer = 0

    -- === 盾牌冲锋参数 ===
    enemy.chargeState     = "none"    -- "windup" / "rushing" / "none"
    enemy.chargeTimer     = 0
    enemy.chargeWindupDur = 0.5       -- 蓄力时间
    enemy.chargeSpeed     = 320       -- 冲锋速度（像素/秒）
    enemy.chargeDuration  = 0.8       -- 冲锋持续
    enemy.chargeDmg       = 12        -- 冲锋伤害（设计值，实际受层数缩放）
    enemy.chargeStunDur   = 1.0       -- 命中眩晕
    enemy.chargeDir       = { x = 0, y = 0 }
    enemy._chargeWarningX = 0         -- 预警线起点
    enemy._chargeWarningY = 0
    enemy._chargeWarningDx = 0        -- 预警方向
    enemy._chargeWarningDy = 0
    enemy._chargeHit      = false     -- 本次冲锋是否已命中

    -- === 激光扫射参数 ===
    enemy.laserState      = "none"    -- "windup" / "firing" / "none"
    enemy.laserTimer      = 0
    enemy.laserWindupDur  = 1.8       -- 蓄力时间（瞄准更久）
    enemy.laserDuration   = 2.5       -- 持续扫射
    enemy.laserDPS        = 15        -- 每秒伤害
    enemy.laserWidth      = 24        -- 宽度（像素）
    enemy.laserAngle      = 0         -- 当前激光角度（弧度）
    enemy.laserTargetAngle = 0        -- 目标追踪角度
    enemy.laserTrackSpeed = 6.0       -- 追踪角速度（弧度/秒，一直盯着玩家打）
    enemy._laserDmgAccum  = 0         -- 伤害累积（每0.2秒判定一次）

    -- === 炮击参数 ===
    enemy.cannonState     = "none"    -- "windup" / "firing" / "none"
    enemy.cannonTimer     = 0
    enemy.cannonWindupDur = 0.8       -- 蓄力时间
    enemy.cannonDmgCenter = 20        -- 中心伤害
    enemy.cannonDmgEdge   = 10        -- 边缘伤害
    enemy.cannonRadius    = 80        -- 爆炸半径（像素，约2格）
    enemy._cannonTargetX  = 0         -- 落点目标
    enemy._cannonTargetY  = 0
    enemy._cannonExplTimer = 0        -- 爆炸动画计时
    enemy._cannonExploding = false    -- 是否正在爆炸

    -- === 狂暴模式 ===
    enemy.berserk         = false     -- 是否已进入狂暴
    enemy.berserkTransition = false   -- 正在播放狂暴变身动画
    enemy.berserkTimer    = 0
    enemy._smokeTimer     = 0         -- 黑烟粒子计时

    -- Phase
    enemy.phase = 1
    -- 技能循环序列（阶段一）
    enemy.skillSequence = { "charge", "laser", "cannon", "cannon", "charge" }
    enemy.skillSeqIndex = 0

    -- 激活状态
    enemy.activated = false

    -- 绘制尺寸（2×2格 = 比普通敌人大）
    enemy.drawSize = 170
    enemy.facing = 1  -- 默认朝右

    -- 行走速度（慢速坦克）
    enemy.walkSpeed = 38

    -- 伤害传递缓冲（CheckContactDamage 消费）
    enemy._pendingDmg = 0
    enemy._pendingStun = 0
    enemy._pendingKnockX = nil
    enemy._pendingKnockY = nil
    enemy._guardSpark = 0

    return enemy
end

--- 是否为装甲机猫
function M.IsArmoredCat(enemy)
    return enemy and enemy.bossType == "armored_cat"
end

-- ============================================================================
-- 技能选择 AI
-- ============================================================================

local function ChooseSkill(boss, player)
    -- 阶段一：按固定循环选择
    if boss.phase == 1 then
        boss.skillSeqIndex = boss.skillSeqIndex + 1
        if boss.skillSeqIndex > #boss.skillSequence then
            boss.skillSeqIndex = 1
        end
        local chosen = boss.skillSequence[boss.skillSeqIndex]
        -- 如果该技能还在冷却，选下一个可用的
        if boss.skillCD[chosen] and boss.skillCD[chosen] > 0 then
            for k, cd in pairs(boss.skillCD) do
                if cd <= 0 then return k end
            end
            return SKILL.IDLE
        end
        return chosen
    end

    -- 阶段二（狂暴）：加权随机，激光频率翻倍
    local available = {}
    local dist = math.sqrt((player.x - boss.x)^2 + (player.y - boss.y)^2)

    if boss.skillCD.charge <= 0 then
        local w = dist > 100 and 4 or 2
        table.insert(available, { skill = "charge", weight = w })
    end
    if boss.skillCD.laser <= 0 then
        table.insert(available, { skill = "laser", weight = 5 })  -- 高权重
    end
    if boss.skillCD.cannon <= 0 then
        table.insert(available, { skill = "cannon", weight = 3 })
    end

    if #available == 0 then return SKILL.IDLE end

    -- 加权随机
    local totalW = 0
    for _, v in ipairs(available) do totalW = totalW + v.weight end
    local roll = math.random() * totalW
    local sum = 0
    for _, v in ipairs(available) do
        sum = sum + v.weight
        if roll <= sum then return v.skill end
    end
    return available[#available].skill
end

-- ============================================================================
-- 技能结束工具
-- ============================================================================

local function EndSkill(boss, skillKey)
    local cd = SKILL_CD[skillKey] or 5.0
    if boss.berserk then cd = cd * BERSERK_CD_MULT end
    boss.skillCD[skillKey] = cd
    boss._attackCount = (boss._attackCount or 0) + 1
    -- 每攻击2次后，强制进入走路阶段（2段走路）
    if boss._attackCount >= 2 then
        boss._attackCount = 0
        boss._walkPhase = 1
        boss._walkPhaseTimer = 0
        boss.skill = SKILL.IDLE
        M.SetAnim(boss, "walk")
    else
        boss.skill = SKILL.IDLE
        M.SetAnim(boss, "idle")
    end
    boss.idleTimer = 0
end

-- ============================================================================
-- 各技能更新
-- ============================================================================

--- 盾牌冲锋：蓄力（预警线）→ 直线冲刺 → 命中伤害+眩晕
local function UpdateCharge(boss, dt, player)
    boss.chargeTimer = boss.chargeTimer + dt

    if boss.chargeState == "windup" then
        M.SetAnim(boss, "charge_windup")
        M.UpdateAnim(boss, 0)
        -- 蓄力时持续朝向玩家
        local dx = player.x - boss.x
        local dy = player.y - boss.y
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist > 1 then
            boss.chargeDir.x = dx / dist
            boss.chargeDir.y = dy / dist
        end
        boss._chargeWarningX = boss.x
        boss._chargeWarningY = boss.y
        boss._chargeWarningDx = boss.chargeDir.x
        boss._chargeWarningDy = boss.chargeDir.y
        if boss.chargeDir.x > 0 then boss.facing = 1 else boss.facing = -1 end

        if boss.chargeTimer >= boss.chargeWindupDur then
            boss.chargeState = "rushing"
            boss.chargeTimer = 0
            boss._chargeHit = false
            M.SetAnim(boss, "charge_rush")
        end

    elseif boss.chargeState == "rushing" then
        M.SetAnim(boss, "charge_rush")
        M.UpdateAnim(boss, 0)
        -- 直线移动
        local speed = boss.chargeSpeed
        boss.x = boss.x + boss.chargeDir.x * speed * dt
        boss.y = boss.y + boss.chargeDir.y * speed * dt
        World.ResolveWall(boss, 30)

        -- 碰撞检测（玩家）
        if not boss._chargeHit then
            local pdx = player.x - boss.x
            local pdy = player.y - boss.y
            local dist = math.sqrt(pdx*pdx + pdy*pdy)
            if dist < 45 then
                -- 命中：通过 _pendingDmg 传递给 CheckContactDamage
                boss._chargeHit = true
                boss._pendingDmg = math.ceil(boss.damage * 0.6)
                boss._pendingStun = boss.chargeStunDur
                if dist > 1 then
                    boss._pendingKnockX = (pdx/dist) * 200
                    boss._pendingKnockY = (pdy/dist) * 200
                end
                boss._screenShake = 0.5
            end
        end

        -- 冲锋结束
        local dur = boss.berserk and boss.chargeDuration * 1.2 or boss.chargeDuration
        if boss.chargeTimer >= dur then
            boss.chargeState = "none"
            EndSkill(boss, "charge")
        end
    end
end

--- 激光扫射：蓄力 → 激光扫射（缓慢跟踪玩家）
local function UpdateLaser(boss, dt, player)
    boss.laserTimer = boss.laserTimer + dt

    if boss.laserState == "windup" then
        M.SetAnim(boss, "laser_windup")
        M.UpdateAnim(boss, 0)
        -- 蓄力时锁定初始方向
        local dx = player.x - boss.x
        local dy = player.y - boss.y
        boss.laserAngle = math.atan(dy, dx)
        boss.laserTargetAngle = boss.laserAngle
        if dx > 0 then boss.facing = 1 else boss.facing = -1 end

        if boss.laserTimer >= boss.laserWindupDur then
            boss.laserState = "firing"
            boss.laserTimer = 0
            boss._laserDmgAccum = 0
            boss._screenShake = 0.4
            M.SetAnim(boss, "laser_fire")
        end

    elseif boss.laserState == "firing" then
        M.SetAnim(boss, "laser_fire")
        M.UpdateAnim(boss, 0)

        -- 先计算手臂发射点（激光真正的起点）
        local armWorldX = boss.x + (boss.facing or 1) * (boss.drawSize or 170) * 0.35
        local armWorldY = boss.y - (boss.drawSize or 170) * 0.22

        -- 从发射点到玩家的角度（修正：用发射点而非boss中心计算）
        local dx = player.x - armWorldX
        local dy = player.y - armWorldY
        boss.laserTargetAngle = math.atan(dy, dx)

        -- 角度插值（高速追踪，一直盯着玩家）
        local diff = boss.laserTargetAngle - boss.laserAngle
        -- 归一化到 [-pi, pi]
        while diff > math.pi do diff = diff - math.pi * 2 end
        while diff < -math.pi do diff = diff + math.pi * 2 end
        local trackSpeed = boss.berserk and boss.laserTrackSpeed * 1.5 or boss.laserTrackSpeed
        local maxTurn = trackSpeed * dt
        if math.abs(diff) < maxTurn then
            boss.laserAngle = boss.laserTargetAngle
        else
            boss.laserAngle = boss.laserAngle + (diff > 0 and maxTurn or -maxTurn)
        end

        -- 射线检测墙壁，计算有效激光长度
        local laserMaxLen = 600
        local lx = math.cos(boss.laserAngle)
        local ly = math.sin(boss.laserAngle)
        local stepSize = 10  -- 每10像素检测一次
        local effectiveLen = laserMaxLen
        for step = 1, math.floor(laserMaxLen / stepSize) do
            local checkDist = step * stepSize
            local wx = armWorldX + lx * checkDist
            local wy = armWorldY + ly * checkDist
            if World.IsWall(wx, wy) then
                effectiveLen = checkDist
                break
            end
        end
        boss._laserEffectiveLen = effectiveLen
        -- 墙壁撞击点产生粒子
        if effectiveLen < laserMaxLen then
            boss._laserParticleTimer = (boss._laserParticleTimer or 0) + dt
            if boss._laserParticleTimer >= 0.02 then
                boss._laserParticleTimer = boss._laserParticleTimer - 0.02
                local hitX = armWorldX + lx * effectiveLen
                local hitY = armWorldY + ly * effectiveLen
                -- 墙壁撞击火花（反弹方向）每次生成3个粒子
                for _ = 1, 3 do
                    local spreadAngle = (math.random() - 0.5) * math.pi * 1.0
                    local reflAngle = math.atan(ly, lx) + math.pi + spreadAngle
                    local spd = 50 + math.random() * 80
                    World.SpawnParticle(hitX, hitY,
                        math.cos(reflAngle)*spd, math.sin(reflAngle)*spd,
                        0, 220 + math.random(35), 255, 0.2 + math.random()*0.2, 2 + math.random()*2.5)
                end
            end
        end
        -- 沿光束方向散发粒子
        boss._laserBeamParticleTimer = (boss._laserBeamParticleTimer or 0) + dt
        if boss._laserBeamParticleTimer >= 0.05 then
            boss._laserBeamParticleTimer = boss._laserBeamParticleTimer - 0.05
            local dist = 20 + math.random() * (effectiveLen - 30)
            if dist > 0 then
                local px2 = armWorldX + lx * dist
                local py2 = armWorldY + ly * dist
                local perpAngle = math.atan(ly, lx) + math.pi * 0.5
                local drift = (math.random() - 0.5) * 30
                World.SpawnParticle(px2 + math.cos(perpAngle)*drift, py2 + math.sin(perpAngle)*drift,
                    (math.random()-0.5)*15, (math.random()-0.5)*15 - 10,
                    100, 240, 255, 0.15 + math.random()*0.1, 1.5 + math.random()*1.5)
            end
        end

        -- 伤害判定（检测玩家是否在激光线段内，受墙壁限制）
        local hitPlayer = false
        boss._laserDmgAccum = boss._laserDmgAccum + dt
        if boss._laserDmgAccum >= 0.2 then
            boss._laserDmgAccum = boss._laserDmgAccum - 0.2
            -- 玩家相对发射点的向量
            local px = player.x - armWorldX
            local py = player.y - armWorldY
            -- 投影长度
            local proj = px * lx + py * ly
            if proj > 0 and proj < effectiveLen then
                -- 垂直距离
                local perpDist = math.abs(px * ly - py * lx)
                if perpDist < boss.laserWidth / 2 + 12 then  -- 12=玩家半径
                    boss._pendingDmg = math.ceil(boss.laserDPS * 0.2)
                    hitPlayer = true
                end
            end
        end

        -- 结束条件：命中玩家后结束（给0.3秒持续伤害再收束）
        -- 安全超时：最多8秒（狂暴10秒）防止卡死
        if hitPlayer then
            boss._laserHitTimer = (boss._laserHitTimer or 0) + dt
            if boss._laserHitTimer >= 0.3 then
                boss.laserState = "none"
                boss._laserHitTimer = 0
                EndSkill(boss, "laser")
            end
        else
            boss._laserHitTimer = 0  -- 没命中就重置
        end
        -- 安全超时（防止永远不结束）
        local maxDur = boss.berserk and 7.0 or 5.0
        if boss.laserTimer >= maxDur then
            boss.laserState = "none"
            boss._laserHitTimer = 0
            EndSkill(boss, "laser")
        end
    end
end

--- 炮击：蓄力（地面预警圈）→ 发射炮弹 → 落地爆炸AOE
--- 炮击爆炸判定+弹幕（单次）
local function CannonExplode(boss, player, bullets)
    boss._cannonExploding = true
    boss._cannonExplTimer = 0
    boss._screenShake = 0.6

    local tx, ty = boss._cannonTargetX, boss._cannonTargetY
    local pdx = player.x - tx
    local pdy = player.y - ty
    local dist = math.sqrt(pdx*pdx + pdy*pdy)
    local radius = boss.berserk and boss.cannonRadius * 1.3 or boss.cannonRadius
    if dist < radius then
        local ratio = dist / radius
        local dmgBase = boss.cannonDmgCenter
        if ratio > 0.5 then
            dmgBase = boss.cannonDmgEdge
        end
        boss._pendingDmg = math.ceil(dmgBase * (boss.damage / 28))
        if dist > 1 then
            boss._pendingKnockX = (pdx/dist) * 180
            boss._pendingKnockY = (pdy/dist) * 180
        end
    end

    -- 爆炸碎片弹幕
    local count = boss.berserk and 8 or 5
    for i = 1, count do
        local angle = (math.pi * 2) * i / count + (math.random() - 0.5) * 0.3
        bullets[#bullets + 1] = {
            x = tx + math.cos(angle) * 15,
            y = ty + math.sin(angle) * 15,
            vx = math.cos(angle) * 100,
            vy = math.sin(angle) * 100,
            owner = "enemy",
            dmg = math.ceil(boss.damage * 0.3),
            life = 0.5,
            bossBullet = true,
            isShrapnel = true,
        }
    end

    -- 爆炸粒子
    for i = 1, 15 do
        local angle = math.random() * math.pi * 2
        local speed = 50 + math.random() * 120
        World.SpawnParticle(
            tx + (math.random()-0.5)*20,
            ty + (math.random()-0.5)*20,
            math.cos(angle)*speed, math.sin(angle)*speed,
            255, 120, 30, 0.3 + math.random()*0.3, 3 + math.random()*4)
    end
end

local CANNON_SHOTS = 3  -- 连发3炮

local function UpdateCannon(boss, dt, player, bullets)
    boss.cannonTimer = boss.cannonTimer + dt
    boss._cannonShot = boss._cannonShot or 0  -- 当前第几炮（0-based）

    if boss.cannonState == "windup" then
        M.SetAnim(boss, "cannon_windup")
        M.UpdateAnim(boss, 0)
        -- 仅第一帧锁定落点，之后不再跟踪（给玩家躲避时间）
        if boss.cannonTimer <= dt then
            boss._cannonTargetX = player.x
            boss._cannonTargetY = player.y
            local dx = player.x - boss.x
            if dx > 0 then boss.facing = 1 else boss.facing = -1 end
        end

        if boss.cannonTimer >= boss.cannonWindupDur then
            boss.cannonState = "firing"
            boss.cannonTimer = 0
            boss._cannonShot = boss._cannonShot + 1
            M.SetAnim(boss, "cannon_fire")
            CannonExplode(boss, player, bullets)
        end

    elseif boss.cannonState == "firing" then
        M.SetAnim(boss, "cannon_fire")
        local _, done = M.UpdateAnim(boss, 0)
        boss._cannonExplTimer = (boss._cannonExplTimer or 0) + dt
        if done or boss.cannonTimer >= 0.6 then
            boss._cannonExploding = false
            -- 还没打够2炮 → 重新蓄力
            if boss._cannonShot < CANNON_SHOTS then
                boss.cannonState = "windup"
                boss.cannonTimer = 0
                M.SetAnim(boss, "cannon_windup")
            else
                -- 2炮打完，结束技能
                boss.cannonState = "none"
                boss._cannonShot = 0
                EndSkill(boss, "cannon")
            end
        end
    end
end

-- ============================================================================
-- 主更新
-- ============================================================================

function M.Update(boss, dt, player, bullets)
    -- 激活检测
    if not boss.activated then
        if boss.roomL and player.x >= boss.roomL and player.x <= boss.roomR
           and player.y >= boss.roomT and player.y <= boss.roomB then
            boss.activated = true
        else
            M.SetAnim(boss, "idle")
            M.UpdateAnim(boss, 0)
            return
        end
    end

    -- 狂暴变身动画（逐渐放大 + 冒浓烟）
    if boss.berserkTransition then
        boss.berserkTimer = boss.berserkTimer + dt
        M.SetAnim(boss, "berserk")
        M.UpdateAnim(boss, 0)
        -- 渐变放大 170 → 187
        local t = math.min(boss.berserkTimer / 1.2, 1.0)
        boss.drawSize = 170 + math.floor(t * 17)
        -- 变身期间密集冒烟
        boss._smokeTimer = (boss._smokeTimer or 0) + dt
        if boss._smokeTimer >= 0.06 then
            boss._smokeTimer = boss._smokeTimer - 0.06
            World.SpawnParticle(
                boss.x + (math.random()-0.5) * 30,
                boss.y - 20 + (math.random()-0.5) * 15,
                (math.random()-0.5) * 50, -60 - math.random() * 40,
                40, 40, 40, 0.6 + math.random()*0.4, 4 + math.random()*3)
        end
        if boss.berserkTimer >= 1.2 then
            boss.berserkTransition = false
            boss.berserk = true
            boss.phase = 2
            boss.drawSize = 187  -- 最终尺寸（比常态大约10%）
            -- 狂暴效果：速度+30%
            boss.walkSpeed = math.floor(boss.walkSpeed * 1.3)
            -- 重置所有冷却（立即可用）
            for k, _ in pairs(boss.skillCD) do
                boss.skillCD[k] = 0
            end
            M.SetAnim(boss, "idle")
        end
        return
    end

    -- Phase 切换检测（HP < 50% 进入狂暴）
    if boss.phase == 1 and boss.hp <= boss.maxHp * 0.5 then
        boss.berserkTransition = true
        boss.berserkTimer = 0
        boss.skill = SKILL.IDLE
        -- 黑烟粒子效果在 Draw 中处理
        return
    end

    -- 冷却递减
    for k, cd in pairs(boss.skillCD) do
        if cd > 0 then
            boss.skillCD[k] = cd - dt
        end
    end

    -- 黑烟粒子（狂暴时背部持续冒浓烟 — 深灰+暗红双色）
    if boss.berserk then
        boss._smokeTimer = (boss._smokeTimer or 0) + dt
        if boss._smokeTimer >= 0.10 then
            boss._smokeTimer = boss._smokeTimer - 0.10
            -- 深灰色主烟
            World.SpawnParticle(
                boss.x + (math.random()-0.5) * 24,
                boss.y - 30 + (math.random()-0.5) * 12,
                (math.random()-0.5) * 35, -50 - math.random() * 30,
                35 + math.random(15), 30 + math.random(10), 30 + math.random(10),
                0.5 + math.random()*0.3, 3 + math.random()*2)
            -- 暗红色火星（概率50%）
            if math.random() > 0.5 then
                World.SpawnParticle(
                    boss.x + (math.random()-0.5) * 16,
                    boss.y - 25 + (math.random()-0.5) * 8,
                    (math.random()-0.5) * 20, -30 - math.random() * 20,
                    180 + math.random(75), 40 + math.random(30), 20,
                    0.3 + math.random()*0.2, 2 + math.random()*1.5)
            end
        end
    end

    -- 技能状态机
    if boss.skill == SKILL.IDLE then
        local dx = player.x - boss.x
        local dy = player.y - boss.y
        local dist = math.sqrt(dx*dx + dy*dy)

        -- 强制走路阶段（攻击2次后触发，共2段）
        if (boss._walkPhase or 0) > 0 then
            boss._walkPhaseTimer = (boss._walkPhaseTimer or 0) + dt
            -- 走路：朝玩家方向移动
            if dist > 40 then
                local moveSpeed = boss.walkSpeed * dt
                boss.x = boss.x + (dx / dist) * moveSpeed
                boss.y = boss.y + (dy / dist) * moveSpeed
                World.ResolveWall(boss, 30)
            end
            M.SetAnim(boss, "walk")
            M.UpdateAnim(boss, 0)
            if dx > 0 then boss.facing = 1 else boss.facing = -1 end

            -- 一段走完 → 下一段或结束
            if boss._walkPhaseTimer >= (boss._walkPhaseDur or 1.2) then
                boss._walkPhaseTimer = 0
                if boss._walkPhase >= 2 then
                    -- 两段走路结束，恢复正常
                    boss._walkPhase = 0
                    boss.idleTimer = 0
                else
                    boss._walkPhase = boss._walkPhase + 1
                end
            end
        else
            -- 正常 Idle 期间缓慢走向玩家
            if dist > 80 then
                local moveSpeed = boss.walkSpeed * dt
                boss.x = boss.x + (dx / dist) * moveSpeed
                boss.y = boss.y + (dy / dist) * moveSpeed
                World.ResolveWall(boss, 30)
                M.SetAnim(boss, "walk")
            else
                M.SetAnim(boss, "idle")
            end
            M.UpdateAnim(boss, 0)

            -- 朝向玩家
            if dx > 0 then boss.facing = 1 else boss.facing = -1 end

            -- Idle 计时 → 选择下一个技能
            boss.idleTimer = boss.idleTimer + dt
            if boss.idleTimer >= boss.idleDuration then
                local nextSkill = ChooseSkill(boss, player)
                if nextSkill == "charge" then
                    boss.skill = SKILL.CHARGE
                    boss.chargeState = "windup"
                    boss.chargeTimer = 0
                elseif nextSkill == "laser" then
                    boss.skill = SKILL.LASER
                    boss.laserState = "windup"
                    boss.laserTimer = 0
                elseif nextSkill == "cannon" then
                    boss.skill = SKILL.CANNON
                    boss.cannonState = "windup"
                    boss.cannonTimer = 0
                end
                boss.idleTimer = 0
            end
        end

    elseif boss.skill == SKILL.CHARGE then
        UpdateCharge(boss, dt, player)

    elseif boss.skill == SKILL.LASER then
        UpdateLaser(boss, dt, player)

    elseif boss.skill == SKILL.CANNON then
        UpdateCannon(boss, dt, player, bullets)
    end
end

-- ============================================================================
-- 受击处理
-- ============================================================================

function M.TakeDamage(boss, dmg, bulletAngle)
    -- 盾牌冲锋蓄力/冲刺期间：正面格挡
    if boss.skill == SKILL.CHARGE then
        -- 冲锋中盾在前方，检测正面格挡
        local shieldAngle = math.atan(boss.chargeDir.y, boss.chargeDir.x)
        local angleDiff = bulletAngle - shieldAngle
        while angleDiff > math.pi do angleDiff = angleDiff - math.pi * 2 end
        while angleDiff < -math.pi do angleDiff = angleDiff + math.pi * 2 end
        if math.abs(angleDiff) < math.pi * 0.4 then
            -- 正面格挡
            boss._guardSpark = 0.15
            return false
        end
    end

    -- 正常受伤
    boss.hp = boss.hp - dmg
    boss.hitFlash = 0.1
    return true
end

-- ============================================================================
-- 接触伤害检测
-- ============================================================================

function M.CheckContactDamage(boss, player)
    local Dev = require("DevSystem")
    if Dev.godMode then
        boss._pendingDmg = 0
        boss._pendingKnockX = nil
        boss._pendingKnockY = nil
        boss._pendingStun = 0
        return 0
    end
    -- 通过 _pendingDmg 返回技能造成的伤害（冲锋/激光/炮击）
    if boss._pendingDmg and boss._pendingDmg > 0 then
        local dmg = boss._pendingDmg
        boss._pendingDmg = 0
        -- 附带击退
        if boss._pendingKnockX then
            player.vx = (player.vx or 0) + (boss._pendingKnockX or 0)
            player.vy = (player.vy or 0) + (boss._pendingKnockY or 0)
            boss._pendingKnockX = nil
            boss._pendingKnockY = nil
        end
        -- 附带眩晕
        if boss._pendingStun and boss._pendingStun > 0 then
            if player.stunTimer ~= nil then
                player.stunTimer = boss._pendingStun
            end
            boss._pendingStun = 0
        end
        return dmg
    end
    return false
end

-- ============================================================================
-- 绘制
-- ============================================================================

function M.Draw(ctx, boss, camX, camY)
    local sx = boss.x - camX
    local sy = boss.y - camY
    local size = boss.drawSize or 170

    -- 脚下阴影
    nvgBeginPath(ctx)
    nvgEllipse(ctx, sx, sy + size * 0.21, size * 0.2, size * 0.065)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 55))
    nvgFill(ctx)

    -- ========== 技能特效（底层，在本体下方绘制）==========

    -- 盾牌冲锋预警线
    if boss.skill == SKILL.CHARGE and boss.chargeState == "windup" then
        local wdx = boss._chargeWarningDx or 0
        local wdy = boss._chargeWarningDy or 0
        local startX = sx
        local startY = sy
        local lineLen = 300
        -- 红色虚线预警
        nvgSave(ctx)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, startX, startY)
        nvgLineTo(ctx, startX + wdx * lineLen, startY + wdy * lineLen)
        -- 闪烁效果
        local alpha = 120 + math.floor(math.sin(boss.chargeTimer * 12) * 80)
        nvgStrokeColor(ctx, nvgRGBA(255, 50, 50, alpha))
        nvgStrokeWidth(ctx, 3)
        nvgStroke(ctx)
        nvgRestore(ctx)
    end

    -- 炮击预警圈
    if boss.skill == SKILL.CANNON and boss.cannonState == "windup" then
        local tx = boss._cannonTargetX - camX
        local ty = boss._cannonTargetY - camY
        local radius = boss.berserk and boss.cannonRadius * 1.3 or boss.cannonRadius
        -- 红色圆形预警（脉冲）
        local pulse = 0.5 + 0.5 * math.sin(boss.cannonTimer * 10)
        local alpha = math.floor(60 + pulse * 100)
        nvgBeginPath(ctx)
        nvgCircle(ctx, tx, ty, radius)
        nvgFillColor(ctx, nvgRGBA(255, 40, 40, alpha))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, tx, ty, radius)
        nvgStrokeColor(ctx, nvgRGBA(255, 80, 80, 180))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)
        -- 炮口蓄力充能（橙黄色能量聚集）
        local cprog = boss.cannonTimer / boss.cannonWindupDur
        local cRadius = 3 + cprog * 10
        local cAlpha = math.floor(60 + cprog * 195)
        -- 炮口位置（顶部偏上，朝向前方）
        local cannonMX = sx + (boss.facing or 1) * size * 0.28
        local cannonMY = sy - size * 0.32
        -- 聚能球
        nvgBeginPath(ctx)
        nvgCircle(ctx, cannonMX, cannonMY, cRadius)
        nvgFillColor(ctx, nvgRGBA(255, 180, 30, cAlpha))
        nvgFill(ctx)
        -- 外圈收束环
        nvgBeginPath(ctx)
        nvgCircle(ctx, cannonMX, cannonMY, cRadius + 5 + (1 - cprog) * 10)
        nvgStrokeColor(ctx, nvgRGBA(255, 220, 80, math.floor(cAlpha * 0.5)))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)
        -- 收束能量线
        for i = 1, 5 do
            local a = (boss.cannonTimer * 4) + i * (math.pi * 2 / 5)
            local dist = (1 - cprog) * 25 + 6
            local px = cannonMX + math.cos(a) * dist
            local py = cannonMY + math.sin(a) * dist
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, px, py)
            nvgLineTo(ctx, cannonMX + math.cos(a) * (cRadius + 1), cannonMY + math.sin(a) * (cRadius + 1))
            nvgStrokeColor(ctx, nvgRGBA(255, 200, 50, math.floor(cAlpha * 0.7)))
            nvgStrokeWidth(ctx, 1.5)
            nvgStroke(ctx)
        end
    end

    -- 炮击爆炸效果
    if boss._cannonExploding then
        local tx = boss._cannonTargetX - camX
        local ty = boss._cannonTargetY - camY
        local t = boss._cannonExplTimer or 0
        local radius = boss.cannonRadius * (0.3 + t * 2.0)
        local alpha = math.max(0, 200 - math.floor(t * 400))
        nvgBeginPath(ctx)
        nvgCircle(ctx, tx, ty, radius)
        nvgFillColor(ctx, nvgRGBA(255, 150, 30, alpha))
        nvgFill(ctx)
        -- 白色核心
        nvgBeginPath(ctx)
        nvgCircle(ctx, tx, ty, radius * 0.4)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, alpha))
        nvgFill(ctx)
    end

    -- 机械臂炮口位置（相对boss中心偏移：面朝方向前方 + 略上方）
    local armOffX = (boss.facing or 1) * size * 0.35
    local armOffY = -size * 0.22
    local armX = sx + armOffX
    local armY = sy + armOffY

    -- (激光射线移至本体绘制之后，确保图层在boss上方)

    -- 激光蓄力充能效果（机械臂聚能）
    if boss.skill == SKILL.LASER and boss.laserState == "windup" then
        local progress = boss.laserTimer / boss.laserWindupDur
        local radius = 4 + progress * 12
        local alpha = math.floor(80 + progress * 175)
        -- 聚能光球（从小到大）
        nvgBeginPath(ctx)
        nvgCircle(ctx, armX, armY, radius)
        nvgFillColor(ctx, nvgRGBA(0, 200, 255, alpha))
        nvgFill(ctx)
        -- 能量收束线（从周围向中心汇聚）
        for i = 1, 6 do
            local a = (boss.laserTimer * 3) + i * (math.pi / 3)
            local dist = (1 - progress) * 30 + 8
            local px = armX + math.cos(a) * dist
            local py = armY + math.sin(a) * dist
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, px, py)
            nvgLineTo(ctx, armX + math.cos(a) * (radius + 2), armY + math.sin(a) * (radius + 2))
            nvgStrokeColor(ctx, nvgRGBA(0, 220, 255, math.floor(alpha * 0.6)))
            nvgStrokeWidth(ctx, 1.5)
            nvgStroke(ctx)
        end
        -- 高频闪烁
        if math.sin(boss.laserTimer * 20) > 0 then
            nvgBeginPath(ctx)
            nvgCircle(ctx, armX, armY, radius * 1.6)
            nvgFillColor(ctx, nvgRGBA(0, 240, 255, 40))
            nvgFill(ctx)
        end
    end

    -- ========== 本体绘制 ==========

    -- 受击闪白
    if boss.hitFlash and boss.hitFlash > 0 then
        nvgSave(ctx)
        nvgGlobalAlpha(ctx, 0.6)
        M.DrawFrame(ctx, boss.animKey, boss.animFrame, sx, sy, size, boss.facing < 0)
        nvgRestore(ctx)
    else
        M.DrawFrame(ctx, boss.animKey, boss.animFrame, sx, sy, size, boss.facing < 0)
    end

    -- 格挡火花
    if boss._guardSpark and boss._guardSpark > 0 then
        boss._guardSpark = boss._guardSpark - (1/60)
        local sparkX = sx + boss.facing * 30
        local sparkY = sy - 10
        for i = 1, 5 do
            local angle = math.random() * math.pi * 2
            local dist = math.random() * 15
            nvgBeginPath(ctx)
            nvgCircle(ctx, sparkX + math.cos(angle)*dist, sparkY + math.sin(angle)*dist, 2 + math.random()*2)
            nvgFillColor(ctx, nvgRGBA(255, 220, 80, 200))
            nvgFill(ctx)
        end
    end

    -- ========== 激光射线（图层高于Boss本体）==========
    if boss.skill == SKILL.LASER and boss.laserState == "firing" then
        local lx = math.cos(boss.laserAngle)
        local ly = math.sin(boss.laserAngle)
        local laserLen = boss._laserEffectiveLen or 600
        local endX = armX + lx * laserLen
        local endY = armY + ly * laserLen
        -- 外层光晕（青色，最宽）
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, armX, armY)
        nvgLineTo(ctx, endX, endY)
        nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, 100))
        nvgStrokeWidth(ctx, boss.laserWidth + 8)
        nvgStroke(ctx)
        -- 中层光束（青色）
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, armX, armY)
        nvgLineTo(ctx, endX, endY)
        nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, 170))
        nvgStrokeWidth(ctx, boss.laserWidth)
        nvgStroke(ctx)
        -- 白色核心（最亮最细）
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, armX, armY)
        nvgLineTo(ctx, endX, endY)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 230))
        nvgStrokeWidth(ctx, 5)
        nvgStroke(ctx)
        -- 炮口光球
        nvgBeginPath(ctx)
        nvgCircle(ctx, armX, armY, 12)
        nvgFillColor(ctx, nvgRGBA(200, 255, 255, 230))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, armX, armY, 7)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
        nvgFill(ctx)
        -- 炮口散射粒子环
        local sparkAngle = (boss.laserTimer or 0) * 6
        for i = 1, 5 do
            local a = sparkAngle + i * (math.pi * 0.4)
            nvgBeginPath(ctx)
            nvgCircle(ctx, armX + math.cos(a)*16, armY + math.sin(a)*16, 2.5)
            nvgFillColor(ctx, nvgRGBA(180, 255, 255, 180))
            nvgFill(ctx)
        end
        -- 墙壁撞击点火花效果
        if (boss._laserEffectiveLen or 600) < 600 then
            local hitR = 6 + 3 * math.sin((boss.laserTimer or 0) * 12)
            nvgBeginPath(ctx)
            nvgCircle(ctx, endX, endY, hitR)
            nvgFillColor(ctx, nvgRGBA(0, 240, 255, 200))
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgCircle(ctx, endX, endY, hitR * 1.8)
            nvgFillColor(ctx, nvgRGBA(0, 200, 255, 60))
            nvgFill(ctx)
            -- 撞击散射线
            for i = 1, 4 do
                local sa = (boss.laserTimer or 0) * 4 + i * (math.pi * 0.5)
                local sr = 10 + math.random() * 8
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, endX, endY)
                nvgLineTo(ctx, endX + math.cos(sa)*sr, endY + math.sin(sa)*sr)
                nvgStrokeColor(ctx, nvgRGBA(150, 255, 255, 150))
                nvgStrokeWidth(ctx, 1.5)
                nvgStroke(ctx)
            end
        end
    end

    -- 狂暴状态：暗红脉动光环 + 底部热浪
    if boss.berserk then
        local pulse = 0.4 + 0.2 * math.sin((boss._smokeTimer or 0) * 5)
        -- 暗红光环
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, size * 0.48)
        nvgFillColor(ctx, nvgRGBA(200, 30, 10, math.floor(pulse * 35)))
        nvgFill(ctx)
        -- 底部热浪（橙色半圆弧）
        local heatAlpha = math.floor(30 + 20 * math.sin((boss._smokeTimer or 0) * 8))
        nvgBeginPath(ctx)
        nvgArc(ctx, sx, sy + size*0.2, size*0.35, 0, math.pi, 1)
        nvgFillColor(ctx, nvgRGBA(255, 100, 20, heatAlpha))
        nvgFill(ctx)
    end

    -- 狂暴变身过程特效
    if boss.berserkTransition then
        local t = boss.berserkTimer / 1.5  -- 0→1
        -- 屏幕震动提示（外部处理），这里画红色脉冲
        local radius = size * 0.5 * (1 + t * 0.5)
        local alpha = math.floor(100 + t * 155)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, radius)
        nvgStrokeColor(ctx, nvgRGBA(255, 50, 50, alpha))
        nvgStrokeWidth(ctx, 3)
        nvgStroke(ctx)
    end
end

return M
