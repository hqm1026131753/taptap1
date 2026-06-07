-- ============================================================================
-- Boss2.lua — 铁甲猫战锤 Boss 系统（帧动画 + 技能状态机）
-- ============================================================================
local World = require("World")
local Audio = require("AudioManager")
local PlayerM = require("Player")

local M = {}

-- ============================================================================
-- Spritesheet 帧动画系统（复用 Boss.lua 相同机制）
-- ============================================================================
local sheets = {}  -- 缓存加载的 spritesheet nvg 句柄

-- 动画定义
local ANIMS = {
    idle = {
        sheet = "image/boss/rika_835a2d10.png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 1, frames = 12,
        frameW = 256, frameH = 256,
        fps = 4, loop = true,
    },
    -- 巨锤砸地（蓄力 → 跳起 → 砸地）— rika_43df0f73 4x3, 有效帧10
    hammer_windup = {
        sheet = "image/boss/rika_43df0f73 (1).png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 1, frames = 4,
        frameW = 256, frameH = 256,
        fps = 7, loop = false,
    },
    hammer_jump = {
        sheet = "image/boss/rika_43df0f73 (1).png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 5, frames = 4,
        frameW = 256, frameH = 256,
        fps = 7, loop = false,
    },
    hammer_land = {
        sheet = "image/boss/rika_dd21f71c.png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 1, frames = 2,
        frameW = 256, frameH = 256,
        fps = 6, loop = false,
    },
    hammer_recover = {
        sheet = "image/boss/rika_dd21f71c.png",
        cols = 4, rows = 3, totalFrames = 10,
        startFrame = 3, frames = 8,
        frameW = 256, frameH = 256,
        fps = 5, loop = false,
    },

    -- 震地猛击（跳 + 砸）— 专属素材 4x3=12帧
    seismic_jump = {
        sheet = "image/boss/rika_5fe6eeaa.png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 1, frames = 5,
        frameW = 256, frameH = 256,
        fps = 5, loop = false,
    },
    seismic_land = {
        sheet = "image/boss/rika_5fe6eeaa.png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 6, frames = 7,
        frameW = 256, frameH = 256,
        fps = 7, loop = false,
    },
    -- 走路（慢速播放冲锋图）
    walk = {
        sheet = "image/boss/rika_5380afd0.png",
        cols = 4, rows = 4, totalFrames = 13,
        startFrame = 1, frames = 13,
        frameW = 256, frameH = 256,
        fps = 6, loop = true,
    },
    -- 拖锤冲锋（快速播放同一组）
    charge = {
        sheet = "image/boss/rika_5380afd0.png",
        cols = 4, rows = 4, totalFrames = 13,
        startFrame = 1, frames = 13,
        frameW = 256, frameH = 256,
        fps = 10, loop = true,
    },
    -- 狂乱连击（Phase1 慢挥 + Phase2 快速气刃斩）
    flurry = {
        sheet = "image/boss/rika_2f65aac8.png",
        cols = 4, rows = 6, totalFrames = 22,
        startFrame = 1, frames = 22,
        frameW = 256, frameH = 256,
        fps = 8, loop = true,
    },
    -- Phase2 加速版
    flurry_fast = {
        sheet = "image/boss/rika_2f65aac8.png",
        cols = 4, rows = 6, totalFrames = 22,
        startFrame = 1, frames = 22,
        frameW = 256, frameH = 256,
        fps = 11, loop = true,
    },
}

-- ============================================================================
-- 动画工具
-- ============================================================================

--- 绘制单帧（与 Boss1 相同的精确 pattern 计算）
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

    local sheetW = anim.cols * anim.frameW
    local sheetH = anim.rows * anim.frameH

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
    local patW = sheetW * patScale
    local patH = sheetH * patScale
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

    boss.animTimer = boss.animTimer + (1.0 / 60.0)  -- 用固定帧率计时
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
    IDLE        = "idle",
    HAMMER_SLAM = "hammer_slam",    -- 巨锤砸击
    SEISMIC     = "seismic",        -- 震地猛击
    CHARGE      = "charge",         -- 拖锤冲锋
    FLURRY      = "flurry",         -- 狂乱连击
}

local SKILL_CD = {
    hammer_slam = 3.5,
    seismic     = 7.0,
    charge      = 5.5,
    flurry      = 10.0,
}

local PHASE2_CD_MULT = 0.7

-- ============================================================================
-- 初始化
-- ============================================================================

--- 创建铁甲猫战锤 Boss 实例
function M.InitCatHammer(enemy)
    enemy.bossType = "cat_hammer"

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
    enemy.idleDuration = 1.2
    enemy.idleTimer    = 0

    -- 巨锤砸地参数
    enemy.hammerWindup  = 0.5       -- 蓄力时间（4帧/8fps=0.5s 刚好播完）
    enemy.hammerState   = "none"    -- "windup" / "jumping" / "landing" / "recover" / "none"
    enemy.hammerTimer   = 0
    enemy.hammerJumpDur = 0.5       -- 跳跃滞空时间（4帧/8fps=0.5s 全部播完）
    enemy.hammerLandDur = 0.33      -- 落地动画时间（2帧/6fps）
    enemy.hammerRecoverDur = 2.2    -- 砸地硬直（1.6s起身 + 0.6s待机喘息）
    enemy.hammerRadius  = 100       -- 砸地冲击波半径
    enemy.hammerJumpHeight = 0      -- 当前跳跃高度（视觉偏移）
    enemy._hammerAirborne = false   -- 滞空状态（无敌标记）



    -- 震地猛击参数
    enemy.seismicAirTime  = 1.0     -- 滞空时间
    enemy.seismicStunDur  = 2.0     -- 落地硬直（拔锤）
    enemy.seismicRadius   = 120     -- 震波半径（3格）
    enemy.seismicTimer    = 0
    enemy.seismicState    = "none"  -- "jumping" / "airborne" / "impact" / "stun"
    enemy.seismicLandX    = 0
    enemy.seismicLandY    = 0
    enemy._seismicAirborne = false

    -- 拖锤冲锋参数
    enemy.chargeSpeed     = 280
    enemy.chargeDuration  = 1.2     -- 冲锋持续
    enemy.chargeTimer     = 0
    enemy.chargeDir       = { x = 0, y = 0 }
    enemy.chargeState     = "none"  -- "windup" / "rushing" / "uppercut" / "none"
    enemy.chargeWindupDur = 0.4
    enemy.chargeUpperDur  = 0.5     -- 上撩收招持续

    -- 狂乱连击参数（Phase2）
    enemy.flurryDuration  = 4.0
    enemy.flurryTimer     = 0
    enemy.flurryHits      = 0       -- 已挥次数
    enemy.flurryMaxHits   = 5       -- Phase1: 5刀扇形
    enemy.flurryInterval  = 0       -- 下次挥击倒计时
    enemy.flurryState     = "none"  -- "roar" / "swinging" / "none"
    enemy.flurryDir       = 1       -- 交替方向

    -- Phase
    enemy.phase = 1
    enemy.phaseTransition = false
    enemy.phaseFlashTimer = 0

    -- 激活状态：玩家进入boss房前不行动
    enemy.activated = false

    -- 绘制尺寸（比 BOSS1 大 125%）
    enemy.drawSize = 189
    enemy.facing = 1  -- 默认朝右

    return enemy
end

--- 是否为铁甲猫战锤
function M.IsCatHammer(enemy)
    return enemy and enemy.bossType == "cat_hammer"
end

-- ============================================================================
-- 技能选择 AI
-- ============================================================================

local function ChooseSkill(boss, player)
    local available = {}
    local dist = math.sqrt((player.x - boss.x)^2 + (player.y - boss.y)^2)

    -- 巨锤砸击：中远距离优先
    if boss.skillCD.hammer_slam <= 0 then
        local w = dist > 80 and 4 or 2
        table.insert(available, { skill = SKILL.HAMMER_SLAM, weight = w })
    end

    -- 震地猛击：远距离优先
    if boss.skillCD.seismic <= 0 then
        local w = dist > 120 and 2 or 1
        table.insert(available, { skill = SKILL.SEISMIC, weight = w })
    end

    -- 拖锤冲锋：中远距离
    if boss.skillCD.charge <= 0 then
        local w = dist > 100 and 4 or 2
        table.insert(available, { skill = SKILL.CHARGE, weight = w })
    end

    -- 狂乱连击：Phase1 可用（低权重），Phase2 高优先
    if boss.skillCD.flurry <= 0 then
        local w = boss.phase >= 2 and 5 or 2
        table.insert(available, { skill = SKILL.FLURRY, weight = w })
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
    local cd = SKILL_CD[skillKey] or 3.0
    if boss.phase >= 2 then cd = cd * PHASE2_CD_MULT end
    boss.skillCD[skillKey] = cd
    boss.skill = SKILL.IDLE
    boss.idleTimer = 0
    M.SetAnim(boss, "idle")
end

-- ============================================================================
-- 各技能更新
-- ============================================================================

--- 巨锤砸地：蓄力 → 跳起(无敌) → 砸地(AOE冲击波) → 收招硬直
local function UpdateHammerSlam(boss, dt, player, bullets)
    boss.hammerTimer = boss.hammerTimer + dt

    if boss.hammerState == "windup" then
        M.SetAnim(boss, "hammer_windup")
        M.UpdateAnim(boss, 0)
        -- 蓄力期间朝向玩家
        local dx = player.x - boss.x
        if dx > 0 then boss.facing = 1 else boss.facing = -1 end

        if boss.hammerTimer >= boss.hammerWindup then
            boss.hammerState = "jumping"
            boss.hammerTimer = 0
            boss._hammerAirborne = true
            -- 记录起跳位置和目标位置（玩家当前位置）
            boss._hammerStartX = boss.x
            boss._hammerStartY = boss.y
            boss._hammerTargetX = player.x
            boss._hammerTargetY = player.y
            M.SetAnim(boss, "hammer_jump")
        end

    elseif boss.hammerState == "jumping" then
        M.SetAnim(boss, "hammer_jump")
        M.UpdateAnim(boss, 0)
        -- 跳跃高度：快起慢落（easeOutQuad 上升 + easeInQuad 下落）
        local progress = boss.hammerTimer / boss.hammerJumpDur
        local h
        if progress < 0.45 then
            local t = progress / 0.45
            h = t * (2 - t)  -- easeOutQuad
        else
            local t = (progress - 0.45) / 0.55
            h = 1.0 - t * t  -- easeInQuad
        end
        boss.hammerJumpHeight = h * 80

        -- 大跳直接飞到玩家位置（线性插值）
        local moveP = math.min(progress / 0.9, 1.0)  -- 90%时间内到达
        boss.x = boss._hammerStartX + (boss._hammerTargetX - boss._hammerStartX) * moveP
        boss.y = boss._hammerStartY + (boss._hammerTargetY - boss._hammerStartY) * moveP
        World.ResolveWall(boss, 30)

        if boss.hammerTimer >= boss.hammerJumpDur then
            -- 落地
            boss.hammerState = "landing"
            boss.hammerTimer = 0
            boss.hammerJumpHeight = 0
            boss._hammerAirborne = false
            M.SetAnim(boss, "hammer_land")
            boss._screenShake = 0.5

            -- AOE 冲击波伤害
            local radius = boss.hammerRadius
            if boss.phase >= 2 then radius = radius * 1.3 end
            local pdx = player.x - boss.x
            local pdy = player.y - boss.y
            local dist = math.sqrt(pdx*pdx + pdy*pdy)
            if dist < radius then
                local dmg = math.floor(boss.damage * 1.4)
                PlayerM.ApplyDamage(player, dmg, boss.x, boss.y)
                -- 击退
                if dist > 1 and player.vx ~= nil then
                    player.vx = (player.vx or 0) + (pdx/dist) * 250
                    player.vy = (player.vy or 0) + (pdy/dist) * 250
                end
            end

            -- 环形碎石弹幕
            local count = boss.phase >= 2 and 10 or 6
            for i = 1, count do
                local angle = (math.pi * 2) * i / count
                bullets[#bullets + 1] = {
                    x = boss.x + math.cos(angle) * 20,
                    y = boss.y + math.sin(angle) * 20,
                    vx = math.cos(angle) * 140,
                    vy = math.sin(angle) * 140,
                    owner = "enemy",
                    dmg = math.floor(boss.damage * 0.8),
                    life = 0.7,
                    bossBullet = true,
                    isShockwave = true,
                }
            end

            -- 落地粒子
            for i = 1, 12 do
                local angle = math.random() * math.pi * 2
                local speed = 60 + math.random() * 100
                World.SpawnParticle(boss.x + (math.random()-0.5)*20,
                    boss.y + (math.random()-0.5)*20,
                    math.cos(angle)*speed, math.sin(angle)*speed,
                    200, 150, 80, 0.3 + math.random()*0.2, 4 + math.random()*3)
            end
        end

    elseif boss.hammerState == "landing" then
        M.SetAnim(boss, "hammer_land")
        local _, done = M.UpdateAnim(boss, 0)
        if done or boss.hammerTimer >= boss.hammerLandDur then
            boss.hammerState = "recover"
            boss.hammerTimer = 0
        end

    elseif boss.hammerState == "recover" then
        -- 起身硬直（输出窗口）
        local animDur = 8 / 5  -- 8帧/5fps = 1.6s
        if boss.hammerTimer < animDur then
            M.SetAnim(boss, "hammer_recover")
        else
            -- 起身播完后用待机动画填充，保持有动感
            M.SetAnim(boss, "idle")
        end
        M.UpdateAnim(boss, 0)
        if boss.hammerTimer >= boss.hammerRecoverDur then
            boss.hammerState = "none"
            boss._hammerAirborne = false
            EndSkill(boss, "hammer_slam")
        end
    end
end



--- 震地猛击：跳跃 → 滞空（预警圈跟踪） → 落地震波 → 硬直
local function UpdateSeismic(boss, dt, player, bullets)
    boss.seismicTimer = boss.seismicTimer + dt

    if boss.seismicState == "jumping" then
        M.SetAnim(boss, "seismic_jump")
        local _, done = M.UpdateAnim(boss, 0)
        if done then
            boss.seismicState = "airborne"
            boss.seismicTimer = 0
            boss._seismicAirborne = true
            -- 初始落点：直接锁定玩家脚下
            local margin = 40
            boss.seismicLandX = math.max(margin, math.min(World.W - margin, player.x))
            boss.seismicLandY = math.max(margin, math.min(World.H - margin, player.y))
        end

    elseif boss.seismicState == "airborne" then
        -- 些微跟踪玩家（前70%时间跟踪，后30%锁定）
        local progress = math.min(boss.seismicTimer / boss.seismicAirTime, 1.0)
        local trackFactor = math.max(0, 1.0 - (progress / 0.7))
        local baseSpeed = boss.phase >= 2 and 90 or 60
        local trackSpeed = baseSpeed * trackFactor * dt
        local dx = player.x - boss.seismicLandX
        local dy = player.y - boss.seismicLandY
        local d = math.sqrt(dx*dx + dy*dy)
        if d > 1 and trackSpeed > 0.1 then
            boss.seismicLandX = boss.seismicLandX + (dx/d) * math.min(trackSpeed, d)
            boss.seismicLandY = boss.seismicLandY + (dy/d) * math.min(trackSpeed, d)
        end
        -- 预警圈也限制在地图内
        local margin = 40
        boss.seismicLandX = math.max(margin, math.min(World.W - margin, boss.seismicLandX))
        boss.seismicLandY = math.max(margin, math.min(World.H - margin, boss.seismicLandY))

        if boss.seismicTimer >= boss.seismicAirTime then
            -- 落地（限制在地图边界内）
            boss.seismicState = "impact"
            boss.seismicTimer = 0
            boss._seismicAirborne = false
            -- Clamp 落点到地图内（复用外层 margin）
            boss.seismicLandX = math.max(margin, math.min(World.W - margin, boss.seismicLandX))
            boss.seismicLandY = math.max(margin, math.min(World.H - margin, boss.seismicLandY))
            -- 如果落点在墙内，回退到 Boss 原始位置
            if World.IsWall(boss.seismicLandX, boss.seismicLandY) then
                boss.seismicLandX = boss.x
                boss.seismicLandY = boss.y
            end
            boss.x = boss.seismicLandX
            boss.y = boss.seismicLandY
            World.ResolveWall(boss, 30)
            M.SetAnim(boss, "seismic_land")
            boss._screenShake = 0.6

            -- 圆形震波弹幕
            local radius = boss.seismicRadius
            if boss.phase >= 2 then radius = radius * 1.33 end  -- 3→4格
            local count = 12
            for i = 1, count do
                local angle = (math.pi * 2) * i / count
                bullets[#bullets + 1] = {
                    x = boss.x + math.cos(angle) * 20,
                    y = boss.y + math.sin(angle) * 20,
                    vx = math.cos(angle) * 120,
                    vy = math.sin(angle) * 120,
                    owner = "enemy",
                    dmg = math.floor(boss.damage * 1.3),
                    life = 0.6,
                    bossBullet = true,
                    isShockwave = true,
                }
            end

            -- 直接伤害判定
            local pdx = player.x - boss.x
            local pdy = player.y - boss.y
            if math.sqrt(pdx*pdx + pdy*pdy) < radius * 0.6 then
                PlayerM.ApplyDamage(player, math.floor(boss.damage * 1.5), boss.x, boss.y)
            end
        end

    elseif boss.seismicState == "impact" then
        M.SetAnim(boss, "seismic_land")
        local _, done = M.UpdateAnim(boss, 0)
        if done or boss.seismicTimer >= 0.4 then
            boss.seismicState = "stun"
            boss.seismicTimer = 0
        end

    elseif boss.seismicState == "stun" then
        -- 硬直（拔锤动作）——输出窗口
        M.SetAnim(boss, "idle")
        M.UpdateAnim(boss, 0)
        if boss.seismicTimer >= boss.seismicStunDur then
            boss.seismicState = "none"
            boss._seismicAirborne = false
            EndSkill(boss, "seismic")
        end
    end
end

--- 拖锤冲锋：前摇 → 冲刺（地面火花） → 上撩收招
local function UpdateCharge(boss, dt, player, bullets)
    boss.chargeTimer = boss.chargeTimer + dt

    if boss.chargeState == "windup" then
        M.SetAnim(boss, "idle")
        M.UpdateAnim(boss, 0)
        -- 锁定方向
        local dx = player.x - boss.x
        local dy = player.y - boss.y
        local d = math.sqrt(dx*dx + dy*dy)
        if d > 1 then
            boss.chargeDir = { x = dx/d, y = dy/d }
        end
        if dx > 0 then boss.facing = 1 else boss.facing = -1 end

        if boss.chargeTimer >= boss.chargeWindupDur then
            boss.chargeState = "rushing"
            boss.chargeTimer = 0
            M.SetAnim(boss, "charge")
        end

    elseif boss.chargeState == "rushing" then
        M.SetAnim(boss, "charge")
        M.UpdateAnim(boss, 0)
        local speed = boss.chargeSpeed
        if boss.phase >= 2 then speed = speed * 1.25 end
        boss.x = boss.x + boss.chargeDir.x * speed * dt
        boss.y = boss.y + boss.chargeDir.y * speed * dt
        World.ResolveWall(boss, 26)

        -- 路径伤害（吸引效果）
        local dx = player.x - boss.x
        local dy = player.y - boss.y
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist < 40 then
            if not boss._chargeHit then
                boss._chargeHit = true
                PlayerM.ApplyDamage(player, boss.damage, boss.x, boss.y)
                boss._screenShake = 0.3
            end
            -- 吸引玩家向 Boss 方向
            if dist > 1 and player.vx ~= nil then
                player.vx = (player.vx or 0) - (dx/dist) * 80
                player.vy = (player.vy or 0) - (dy/dist) * 80
            end
        end

        -- 火花粒子
        if math.random() < 0.4 then
            local sparkX = boss.x - boss.chargeDir.x * 20 + (math.random()-0.5) * 10
            local sparkY = boss.y - boss.chargeDir.y * 20 + (math.random()-0.5) * 10
            World.SpawnParticle(sparkX, sparkY,
                (math.random()-0.5)*60, (math.random()-0.5)*60,
                255, 200, 50, 0.2, 3)
        end

        local dur = boss.chargeDuration
        if boss.chargeTimer >= dur then
            boss.chargeState = "uppercut"
            boss.chargeTimer = 0
            boss._chargeHit = false
        end

    elseif boss.chargeState == "uppercut" then
        -- 冲撞收招
        M.SetAnim(boss, "charge")
        M.UpdateAnim(boss, 0)
        -- 收招范围伤害
        if boss.chargeTimer < 0.1 then  -- 只判定一次
            local dx = player.x - boss.x
            local dy = player.y - boss.y
            local dist = math.sqrt(dx*dx + dy*dy)
            local uppercutRange = boss.phase >= 2 and 70 or 55
            if dist < uppercutRange then
                PlayerM.ApplyDamage(player, math.floor(boss.damage * 1.3), boss.x, boss.y)
                boss._screenShake = 0.4
                -- 击飞
                if dist > 1 and player.vx ~= nil then
                    player.vx = (player.vx or 0) + (dx/dist) * 200
                    player.vy = (player.vy or 0) + (dy/dist) * 200
                end
            end
        end

        if boss.chargeTimer >= boss.chargeUpperDur then
            boss.chargeState = "none"
            EndSkill(boss, "charge")
        end
    end
end

--- 狂乱连击（Phase2 专属）：咆哮 → 连续挥锤
local function UpdateFlurry(boss, dt, player, bullets)
    boss.flurryTimer = boss.flurryTimer + dt
    local isPhase2 = boss.phase >= 2

    if boss.flurryState == "roar" then
        M.SetAnim(boss, "idle")
        M.UpdateAnim(boss, 0)
        -- 咆哮 0.6 秒
        if boss.flurryTimer >= 0.6 then
            boss.flurryState = "swinging"
            boss.flurryTimer = 0
            boss.flurryHits = 0
            boss.flurryInterval = 0
            boss.flurryDir = 1
            M.SetAnim(boss, isPhase2 and "flurry_fast" or "flurry")
        end

    elseif boss.flurryState == "swinging" then
        M.SetAnim(boss, isPhase2 and "flurry_fast" or "flurry")
        M.UpdateAnim(boss, 0)
        boss.flurryInterval = boss.flurryInterval - dt

        local maxHits = isPhase2 and 9 or boss.flurryMaxHits
        local interval = boss.flurryDuration / maxHits

        if boss.flurryInterval <= 0 then
            boss.flurryHits = boss.flurryHits + 1
            boss.flurryInterval = interval
            boss.flurryDir = -boss.flurryDir
            boss._screenShake = 0.15

            local aimAngle = math.atan(player.y - boss.y, player.x - boss.x)
            local dx = player.x - boss.x
            local dy = player.y - boss.y
            local dist = math.sqrt(dx*dx + dy*dy)

            if isPhase2 then
                -- Phase2: 气刃斩 —— 11条远程高速弧形弹，铺满屏幕
                local bladeCount = 11
                local bladeSpread = 1.2  -- 宽扇形（约70度）
                for j = 1, bladeCount do
                    local angle = aimAngle - bladeSpread * 0.5 + bladeSpread * (j - 1) / (bladeCount - 1)
                    bullets[#bullets + 1] = {
                        x = boss.x + math.cos(angle) * 30,
                        y = boss.y + math.sin(angle) * 30,
                        vx = math.cos(angle) * 450,
                        vy = math.sin(angle) * 450,
                        owner = "enemy",
                        dmg = math.floor(boss.damage * 1.0),
                        life = 1.8,
                        bossBullet = true,
                        isBlade = true,
                    }
                end
                -- 近身也打
                if dist < 80 then
                    local dmg = math.floor(boss.damage * 1.5)
                    PlayerM.ApplyDamage(player, dmg, boss.x, boss.y)
                    boss._screenShake = 0.2
                    if dist > 1 and player.vx ~= nil then
                        player.vx = (player.vx or 0) + (dx/dist) * 180
                        player.vy = (player.vy or 0) + (dy/dist) * 180
                    end
                end
            else
                -- Phase1: 密集扇形子弹 —— 7发，高速远射
                local fanCount = 7
                local fanSpread = 0.9  -- 宽扇形
                for j = 1, fanCount do
                    local angle = aimAngle - fanSpread * 0.5 + fanSpread * (j - 1) / (fanCount - 1)
                    bullets[#bullets + 1] = {
                        x = boss.x + math.cos(angle) * 25,
                        y = boss.y + math.sin(angle) * 25,
                        vx = math.cos(angle) * 350,
                        vy = math.sin(angle) * 350,
                        owner = "enemy",
                        dmg = math.floor(boss.damage * 0.6),
                        life = 1.5,
                        bossBullet = true,
                    }
                end
            end

            -- 缓慢追踪玩家
            if dist > 30 then
                local chase = isPhase2 and 50 or 30
                boss.x = boss.x + (dx/dist) * chase
                boss.y = boss.y + (dy/dist) * chase
            end
            if dx > 0 then boss.facing = 1 else boss.facing = -1 end
        end

        if boss.flurryHits >= maxHits then
            boss.flurryState = "none"
            EndSkill(boss, "flurry")
        end
    end
end

-- ============================================================================
-- Boss 主更新
-- ============================================================================

function M.Update(boss, dt, player, bullets)
    if not M.IsCatHammer(boss) then return end

    -- 激活检测：玩家进入boss房才开始行动
    if not boss.activated then
        if boss.roomL and player.x >= boss.roomL and player.x <= boss.roomR
           and player.y >= boss.roomT and player.y <= boss.roomB then
            boss.activated = true
        else
            -- 未激活：只播idle动画
            M.SetAnim(boss, "idle")
            M.UpdateAnim(boss, 0)
            return
        end
    end

    -- 接触伤害冷却
    if (boss._contactCD or 0) > 0 then
        boss._contactCD = boss._contactCD - dt
    end

    -- Phase 判定
    if boss.phase == 1 and boss.hp <= boss.maxHp * 0.5 then
        boss.phase = 2
        boss.phaseTransition = true
        boss.phaseFlashTimer = 1.0
        boss.drawSize = 202  -- Phase2 略微变大
        -- Phase2 缩短冷却
        for k, _ in pairs(boss.skillCD) do
            boss.skillCD[k] = boss.skillCD[k] * PHASE2_CD_MULT
        end
    end
    if boss.phaseFlashTimer > 0 then
        boss.phaseFlashTimer = boss.phaseFlashTimer - dt
        if boss.phaseFlashTimer <= 0 then boss.phaseTransition = false end
    end

    -- CD 递减
    for k, v in pairs(boss.skillCD) do
        if v > 0 then boss.skillCD[k] = v - dt end
    end



    -- 朝向更新（非滞空时）
    if not boss._seismicAirborne then
        if player.x > boss.x + 5 then boss.facing = 1
        elseif player.x < boss.x - 5 then boss.facing = -1 end
    end

    -- 技能状态机
    if boss.skill == SKILL.IDLE then
        -- idle 期间慢慢走向玩家
        local dx = player.x - boss.x
        local dy = player.y - boss.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local walkSpeed = 45  -- 走路速度（慢于冲锋）
        if dist > 50 then
            -- 远于 50px 时移动靠近
            M.SetAnim(boss, "walk")
            local nx, ny = dx / dist, dy / dist
            local moveX = nx * walkSpeed * dt
            local moveY = ny * walkSpeed * dt
            -- 简易墙壁碰撞
            if not World.IsWall(boss.x + moveX, boss.y) then
                boss.x = boss.x + moveX
            end
            if not World.IsWall(boss.x, boss.y + moveY) then
                boss.y = boss.y + moveY
            end
        else
            -- 足够近时播待机动画
            M.SetAnim(boss, "idle")
        end
        M.UpdateAnim(boss, 0)
        boss.idleTimer = boss.idleTimer + dt
        if boss.idleTimer >= boss.idleDuration then
            local chosen = ChooseSkill(boss, player)
            boss.skill = chosen
            boss.skillTimer = 0

            -- 初始化各技能
            if chosen == SKILL.HAMMER_SLAM then
                boss.hammerState = "windup"
                boss.hammerTimer = 0
                boss._hammerAirborne = false
                boss.hammerJumpHeight = 0
            elseif chosen == SKILL.SEISMIC then
                boss.seismicState = "jumping"
                boss.seismicTimer = 0
                M.SetAnim(boss, "seismic_jump")
            elseif chosen == SKILL.CHARGE then
                boss.chargeState = "windup"
                boss.chargeTimer = 0
                boss._chargeHit = false
            elseif chosen == SKILL.FLURRY then
                boss.flurryState = "roar"
                boss.flurryTimer = 0
            end
        end

    elseif boss.skill == SKILL.HAMMER_SLAM then
        UpdateHammerSlam(boss, dt, player, bullets)
    elseif boss.skill == SKILL.SEISMIC then
        UpdateSeismic(boss, dt, player, bullets)
    elseif boss.skill == SKILL.CHARGE then
        UpdateCharge(boss, dt, player, bullets)
    elseif boss.skill == SKILL.FLURRY then
        UpdateFlurry(boss, dt, player, bullets)
    end
end

-- ============================================================================
-- 受击
-- ============================================================================

function M.TakeDamage(boss, dmg, bulletAngle)
    if not M.IsCatHammer(boss) then return true end

    -- 滞空无敌（震地猛击 / 巨锤砸地）
    if boss._seismicAirborne or boss._hammerAirborne then
        return false
    end

    -- 狂乱状态不可打断，但受伤
    boss.hp = boss.hp - dmg
    -- 受击粒子特效（取代闪白）
    for i = 1, 6 do
        local angle = math.random() * math.pi * 2
        local speed = 40 + math.random() * 60
        World.SpawnParticle(boss.x + (math.random()-0.5)*16, boss.y + (math.random()-0.5)*16,
            math.cos(angle)*speed, math.sin(angle)*speed,
            255, 220, 120, 0.25 + math.random()*0.15, 3 + math.random()*2)
    end
    return true
end

-- ============================================================================
-- Boss 绘制
-- ============================================================================

function M.Draw(ctx, boss, camX, camY)
    if not M.IsCatHammer(boss) then return end

    local sx = boss.x - camX
    local sy = boss.y - camY
    local size = boss.drawSize or 120

    -- Phase 转换闪光
    if boss.phaseTransition then
        local flash = math.sin(boss.phaseFlashTimer * 20) * 0.5 + 0.5
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, size * 0.8 * flash)
        nvgFillColor(ctx, nvgRGBA(255, 100, 30, math.floor(120 * flash)))
        nvgFill(ctx)
    end

    -- 震地猛击 - 滞空阶段（不绘制 Boss，只绘制预警圈）
    if boss._seismicAirborne then
        local landSX = boss.seismicLandX - camX
        local landSY = boss.seismicLandY - camY
        local progress = math.min(boss.seismicTimer / boss.seismicAirTime, 1.0)
        local radius = boss.seismicRadius
        if boss.phase >= 2 then radius = radius * 1.33 end

        -- 脉冲红色警告圈
        local pulse = 0.6 + 0.4 * math.sin(boss.seismicTimer * 10)
        local r = radius * pulse

        nvgBeginPath(ctx)
        nvgCircle(ctx, landSX, landSY, r)
        nvgStrokeColor(ctx, nvgRGBA(255, 50, 20, math.floor(180 * progress)))
        nvgStrokeWidth(ctx, 3)
        nvgStroke(ctx)

        -- 填充
        nvgBeginPath(ctx)
        nvgCircle(ctx, landSX, landSY, r)
        nvgFillColor(ctx, nvgRGBA(255, 30, 30, math.floor(40 + 50 * progress)))
        nvgFill(ctx)

        -- 十字准心
        local crossSize = r * 0.4
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, landSX - crossSize, landSY)
        nvgLineTo(ctx, landSX + crossSize, landSY)
        nvgMoveTo(ctx, landSX, landSY - crossSize)
        nvgLineTo(ctx, landSX, landSY + crossSize)
        nvgStrokeColor(ctx, nvgRGBA(255, 80, 80, math.floor(180 * progress)))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        -- 收缩内圈
        local innerR = r * (1.0 - progress)
        nvgBeginPath(ctx)
        nvgCircle(ctx, landSX, landSY, innerR)
        nvgStrokeColor(ctx, nvgRGBA(255, 200, 50, math.floor(200 * progress)))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        return  -- Boss 不可见
    end

    -- 硬直闪烁（震地拔锤期间）
    local flashAlpha = 0
    if boss.seismicState == "stun" then
        if math.floor(boss.seismicTimer * 10) % 2 == 0 then
            flashAlpha = 40
        end
    end

    -- 脚下阴影（紧贴身体底部，跳跃时缩小变淡）
    local shadowScale = 1.0
    local shadowAlpha = 60
    if boss._hammerAirborne and boss.hammerJumpHeight > 0 then
        shadowScale = math.max(0.4, 1.0 - boss.hammerJumpHeight / 120)
        shadowAlpha = math.floor(60 * shadowScale)
    end
    nvgBeginPath(ctx)
    nvgEllipse(ctx, sx, sy + size * 0.2, size * 0.18 * shadowScale, size * 0.05 * shadowScale)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, shadowAlpha))
    nvgFill(ctx)

    -- 绘制帧动画（居中绘制）
    local flipX = (boss.facing < 0)
    local bodyY = sy

    -- 巨锤砸地跳跃时 boss 向上偏移
    if boss._hammerAirborne and boss.hammerJumpHeight > 0 then
        bodyY = sy - boss.hammerJumpHeight
    end

    M.DrawFrame(ctx, boss.animKey, boss.animFrame, sx, bodyY, size, flipX)

    -- 闪白覆盖
    if flashAlpha > 0 then
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, bodyY, size * 0.35)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, flashAlpha))
        nvgFill(ctx)
    end

    -- Phase2 标记（盔甲裂缝视觉 - 红色裂缝线）
    if boss.phase >= 2 then
        nvgStrokeColor(ctx, nvgRGBA(200, 50, 30, 150))
        nvgStrokeWidth(ctx, 1.5)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, sx - 8, bodyY - 10)
        nvgLineTo(ctx, sx - 3, bodyY + 15)
        nvgLineTo(ctx, sx - 10, bodyY + 25)
        nvgStroke(ctx)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, sx + 5, bodyY - 5)
        nvgLineTo(ctx, sx + 10, bodyY + 18)
        nvgStroke(ctx)
    end

    -- 血条
    local barW = 64
    local barH = 6
    local barX = sx - barW * 0.5
    local barY = bodyY - size * 0.4 - 10
    local hpRatio = math.max(0, boss.hp / boss.maxHp)

    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, barX - 1, barY - 1, barW + 2, barH + 2, 3)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 160))
    nvgFill(ctx)

    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, barX, barY, barW * hpRatio, barH, 2)
    local hpColor = boss.phase >= 2 and nvgRGBA(255, 80, 20, 240) or nvgRGBA(200, 60, 60, 240)
    nvgFillColor(ctx, hpColor)
    nvgFill(ctx)

    -- Boss 名字
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 13)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    local nameColor = boss.phase >= 2 and nvgRGBA(255, 140, 30, 240) or nvgRGBA(220, 180, 100, 230)
    nvgFillColor(ctx, nameColor)
    nvgText(ctx, sx, barY - 2, boss.name, nil)

    -- === 技能视觉指示 ===

    -- 巨锤砸地 - 预警圈 & 落地冲击波
    if boss.skill == SKILL.HAMMER_SLAM then
        if boss.hammerState == "windup" then
            -- 脚下蓄力圈
            local pulse = 0.5 + 0.5 * math.sin(boss.hammerTimer * 10)
            local r = 30 + 20 * pulse
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, r)
            nvgStrokeColor(ctx, nvgRGBA(255, 120, 30, math.floor(140 * pulse)))
            nvgStrokeWidth(ctx, 2)
            nvgStroke(ctx)
        elseif boss.hammerState == "jumping" then
            -- 落点预警圈（在地面位置，boss飘在空中）
            local progress = math.min(boss.hammerTimer / boss.hammerJumpDur, 1.0)
            local radius = boss.hammerRadius
            if boss.phase >= 2 then radius = radius * 1.3 end
            local pulse = 0.6 + 0.4 * math.sin(boss.hammerTimer * 12)
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, radius * pulse * progress)
            nvgStrokeColor(ctx, nvgRGBA(255, 50, 20, math.floor(160 * progress)))
            nvgStrokeWidth(ctx, 2.5)
            nvgStroke(ctx)
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, radius * pulse * progress)
            nvgFillColor(ctx, nvgRGBA(255, 30, 30, math.floor(30 + 40 * progress)))
            nvgFill(ctx)
        elseif boss.hammerState == "landing" or boss.hammerState == "recover" then
            -- 落地冲击波：多环金色外扩
            local totalDur = boss.hammerLandDur + boss.hammerRecoverDur
            local elapsed = boss.hammerTimer
            if boss.hammerState == "recover" then elapsed = boss.hammerLandDur + boss.hammerTimer end
            local progress = math.min(elapsed / totalDur, 1.0)
            local radius = boss.hammerRadius * 1.5
            if boss.phase >= 2 then radius = radius * 1.3 end

            -- 主冲击波环（金色）
            local r1 = radius * progress
            local alpha1 = math.floor(220 * (1.0 - progress))
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, r1)
            nvgStrokeColor(ctx, nvgRGBA(255, 200, 60, alpha1))
            nvgStrokeWidth(ctx, 5 * (1.0 - progress) + 1)
            nvgStroke(ctx)

            -- 第二环（略延迟）
            local p2 = math.max(0, (progress - 0.15) / 0.85)
            if p2 > 0 then
                local r2 = radius * p2 * 0.85
                local alpha2 = math.floor(160 * (1.0 - p2))
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, sy, r2)
                nvgStrokeColor(ctx, nvgRGBA(255, 160, 30, alpha2))
                nvgStrokeWidth(ctx, 3 * (1.0 - p2) + 0.5)
                nvgStroke(ctx)
            end

            -- 第三环（再延迟）
            local p3 = math.max(0, (progress - 0.3) / 0.7)
            if p3 > 0 then
                local r3 = radius * p3 * 0.65
                local alpha3 = math.floor(120 * (1.0 - p3))
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, sy, r3)
                nvgStrokeColor(ctx, nvgRGBA(255, 120, 20, alpha3))
                nvgStrokeWidth(ctx, 2 * (1.0 - p3))
                nvgStroke(ctx)
            end

            -- 中心金色填充（快速衰减）
            local fillAlpha = math.floor(80 * math.max(0, 1.0 - progress * 2.5))
            if fillAlpha > 0 then
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, sy, r1 * 0.3)
                nvgFillColor(ctx, nvgRGBA(255, 200, 80, fillAlpha))
                nvgFill(ctx)
            end
        end
    end

    -- 震地猛击 - 落地冲击波
    if boss.seismicState == "impact" then
        local progress = math.min(boss.seismicTimer / 0.4, 1.0)
        local radius = boss.seismicRadius
        if boss.phase >= 2 then radius = radius * 1.33 end
        local r = radius * progress
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, r)
        nvgStrokeColor(ctx, nvgRGBA(255, 100, 30, math.floor(200 * (1.0 - progress))))
        nvgStrokeWidth(ctx, 4 * (1.0 - progress))
        nvgStroke(ctx)
    end

    -- 拖锤冲锋 - 方向指示
    if boss.chargeState == "windup" then
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, sx, sy)
        nvgLineTo(ctx, sx + boss.chargeDir.x * 120, sy + boss.chargeDir.y * 120)
        local pulse = 0.5 + 0.5 * math.sin(boss.chargeTimer * 14)
        nvgStrokeColor(ctx, nvgRGBA(255, 180, 50, math.floor(150 * pulse)))
        nvgStrokeWidth(ctx, 3)
        nvgStroke(ctx)
    end

    -- 狂乱连击 - 红色怒气光环
    if boss.flurryState == "swinging" then
        local pulse = 0.5 + 0.5 * math.sin(boss.flurryTimer * 8)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, size * 0.5 * (0.8 + 0.2 * pulse))
        nvgStrokeColor(ctx, nvgRGBA(255, 40, 20, math.floor(100 * pulse)))
        nvgStrokeWidth(ctx, 3)
        nvgStroke(ctx)
    end
end

return M
