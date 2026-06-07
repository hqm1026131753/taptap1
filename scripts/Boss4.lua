-- ============================================================================
-- Boss4.lua — 军帽领主 Captain Claw Boss 系统（帧动画 + 技能状态机）
-- 定位：第20层最终Boss，高机动 + 多技能 + 九命猫复活机制
-- 技能：精准射击、猫爪突刺、四月斩、战术烟幕、军帽威严、召唤近卫
-- ============================================================================
local World = require("World")
local Audio = require("AudioManager")

local M = {}

-- 四月斩贴图（近战弧形 + 远程气刃）
---@type integer|nil
local cqSlashImg = nil   -- 近战弧形贴图
local cqBladeImg = nil   -- 远程气刃贴图
local CQ_SLASH_PATH = "image/boss/BOSS4/0e882286c7bdff814b1584be860340ee.png"
local CQ_BLADE_PATH = "image/boss/BOSS4/b8565ea8c4baff5b6ed0d75ee5769a21.png"
-- 气刃弹列表（独立于普通子弹，有贴图和旋转）
M._qiBlades = {}

-- ============================================================================
-- Spritesheet 帧动画系统
-- ============================================================================
local sheets = {}  -- 缓存 nvg 句柄

local ANIMS = {
    idle = {
        sheet = "image/boss/BOSS4/rika_cd16407b.png",
        cols = 4, rows = 3, totalFrames = 10,
        startFrame = 1, frames = 10,
        frameW = 256, frameH = 256,
        fps = 5, loop = true,
    },
    walk = {
        sheet = "image/boss/BOSS4/rika_c477609d (1).png",
        cols = 4, rows = 3, totalFrames = 12,
        startFrame = 1, frames = 8,
        frameW = 256, frameH = 256,
        fps = 6, loop = true,
    },
    -- 精准射击（预瞄 + 8连射）
    precision_shot = {
        sheet = "image/boss/BOSS4/rika_dc11ed1d.png",
        cols = 4, rows = 5, totalFrames = 17,
        startFrame = 1, frames = 17,
        frameW = 256, frameH = 256,
        fps = 7, loop = false,
    },
    -- 猫爪突刺（冲刺 + 红月斩）
    shadow_pounce = {
        sheet = "image/boss/BOSS4/rika_c01625c5.png",
        cols = 4, rows = 5, totalFrames = 18,
        startFrame = 1, frames = 18,
        frameW = 256, frameH = 256,
        fps = 8, loop = false,
    },
    -- 四月斩（4连斩 AOE）
    crescent_quadra = {
        sheet = "image/boss/BOSS4/rika_1fe66e26.png",
        cols = 4, rows = 4, totalFrames = 15,
        startFrame = 1, frames = 15,
        frameW = 256, frameH = 256,
        fps = 7, loop = false,
    },
    -- 战术烟幕（隐身阶段）
    smoke_stealth = {
        sheet = "image/boss/BOSS4/rika_3d0b951a (1).png",
        cols = 4, rows = 4, totalFrames = 15,
        startFrame = 1, frames = 15,
        frameW = 256, frameH = 256,
        fps = 7, loop = false,
    },
    -- 战术烟幕（突袭斩击）
    smoke_ambush = {
        sheet = "image/boss/BOSS4/rika_b1c55377.png",
        cols = 4, rows = 4, totalFrames = 16,
        startFrame = 1, frames = 16,
        frameW = 256, frameH = 256,
        fps = 8, loop = false,
    },
    -- 军帽威严（震退 + 蓄力光环）
    commanding = {
        sheet = "image/boss/BOSS4/rika_8a27a431.png",
        cols = 4, rows = 4, totalFrames = 16,
        startFrame = 1, frames = 16,
        frameW = 256, frameH = 256,
        fps = 7, loop = false,
    },
    -- 召唤近卫
    call_guards = {
        sheet = "image/boss/BOSS4/rika_dc11ed1d (1).png",
        cols = 4, rows = 4, totalFrames = 13,
        startFrame = 1, frames = 13,
        frameW = 256, frameH = 256,
        fps = 5, loop = false,
    },
}

-- ============================================================================
-- 动画工具
-- ============================================================================

function M.DrawFrame(ctx, animKey, frameIndex, x, y, size, flipX)
    local anim = ANIMS[animKey]
    if not anim then return end

    if not sheets[anim.sheet] then
        sheets[anim.sheet] = nvgCreateImage(ctx, anim.sheet, 0)
    end
    local img = sheets[anim.sheet]
    if not img or img <= 0 then return end

    local sheetFrame = (anim.startFrame or 1) - 1 + (frameIndex - 1)
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

function M.SetAnim(boss, key)
    if boss.animKey ~= key then
        boss.animKey = key
        boss.animFrame = 1
        boss.animTimer = 0
    end
end

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
                return boss.animFrame, true
            end
        end
    end
    return boss.animFrame, false
end

-- ============================================================================
-- 技能枚举与冷却
-- ============================================================================
local SKILL = {
    IDLE            = "idle",
    PRECISION_SHOT  = "precision_shot",   -- 精准射击
    SHADOW_POUNCE   = "shadow_pounce",    -- 猫爪突刺
    CRESCENT_QUADRA = "crescent_quadra",  -- 四月斩
    TACTICAL_SMOKE  = "tactical_smoke",   -- 战术烟幕
    COMMANDING      = "commanding",       -- 军帽威严
    CALL_GUARDS     = "call_guards",      -- 召唤近卫
}

local SKILL_CD = {
    precision_shot  = 5.0,
    shadow_pounce   = 6.0,
    crescent_quadra = 7.0,
    tactical_smoke  = 7.0,
    commanding      = 10.0,
    call_guards     = 18.0,
}

-- 阶段2冷却倍率
local PHASE2_CD_MULT = 0.7

-- ============================================================================
-- 初始化
-- ============================================================================

function M.InitCaptainClaw(enemy)
    enemy.bossType = "captain_claw"

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

    -- 强制走路机制：每释放3个技能后强制走路2次
    enemy._skillUseCount  = 0    -- 已连续释放技能次数
    enemy._forceWalkCount = 0    -- 剩余强制走路次数
    enemy._forceWalkTimer = 0    -- 当前强制走路计时
    enemy._forceWalkDur   = 1.0  -- 每次强制走路持续时间

    -- === 精准射击参数 ===
    enemy.psState       = "none"     -- "windup" / "firing" / "none"
    enemy.psTimer       = 0
    enemy.psWindupDur   = 0.6        -- 瞄准蓄力
    enemy.psShotCount   = 0          -- 已射击次数
    enemy.psShotMax     = 8          -- 总射击数
    enemy.psShotInterval = 0.08      -- 射击间隔
    enemy.psShotTimer   = 0
    enemy.psBulletSpeed = 480        -- 子弹速度（像素/秒）
    enemy.psDmg         = 8          -- 每发伤害
    enemy.psGuaranteed  = false      -- 下一次精准射击必中（军帽威严触发）
    enemy.psTargetX     = 0          -- 瞄准位置
    enemy.psTargetY     = 0

    -- === 猫爪突刺参数 ===
    enemy.spState       = "none"     -- "windup" / "dashing" / "slashing" / "none"
    enemy.spTimer       = 0
    enemy.spWindupDur   = 0.3
    enemy.spDashSpeed   = 450        -- 冲刺速度
    enemy.spDashDur     = 0.35       -- 冲刺时间
    enemy.spSlashDur    = 0.4        -- 斩击持续
    enemy.spDmg         = 15         -- 斩击伤害
    enemy.spSlashRange  = 70         -- 斩击范围
    enemy.spDirX        = 0
    enemy.spDirY        = 0
    enemy._spHit        = false

    -- === 四月斩参数 ===
    enemy.cqState       = "none"     -- "slashing" / "none"
    enemy.cqTimer       = 0
    enemy.cqSlashIndex  = 0          -- 当前第几斩 (1-4)
    enemy.cqSlashMax    = 4
    enemy.cqSlashInterval = 0.3      -- 每斩间隔
    enemy._cqSlashEffects = {}       -- 近战斩击特效列表
    enemy.cqDmg         = 12         -- 每斩伤害
    enemy.cqRange       = 90         -- 斩击范围
    enemy._cqHits       = {}         -- 每斩命中记录

    -- === 战术烟幕参数 ===
    enemy.tsState       = "none"     -- "smoke" / "stealth" / "ambush" / "none"
    enemy.tsTimer       = 0
    enemy.tsSmokeDur    = 0.8        -- 烟雾扩散动画
    enemy.tsStealthDur  = 2.5        -- 隐身持续
    enemy.tsAmbushDur   = 0.7        -- 突袭斩击持续
    enemy.tsDmg         = 22         -- 突袭伤害
    enemy.tsRange       = 80         -- 突袭范围
    enemy._tsHit        = false
    enemy._tsVisible    = true       -- 是否可见
    enemy._tsSmokeX     = 0          -- 烟雾中心
    enemy._tsSmokeY     = 0

    -- === 军帽威严参数 ===
    enemy.cmState       = "none"     -- "charging" / "release" / "none"
    enemy.cmTimer       = 0
    enemy.cmChargeDur   = 1.0        -- 蓄力时间
    enemy.cmReleaseDur  = 0.5        -- 释放时间
    enemy.cmKnockRange  = 100        -- 震退范围
    enemy.cmKnockForce  = 250        -- 击退力度
    enemy._cmHit        = false

    -- === 召唤近卫参数 ===
    enemy.cgState       = "none"     -- "casting" / "none"
    enemy.cgTimer       = 0
    enemy.cgCastDur     = 1.2        -- 施法时间
    enemy._cgSummoned   = false      -- 本次是否已召唤
    enemy._guardsUsed   = false      -- 全程只能召唤一次

    -- === 九命猫（复活机制）===
    enemy.nineLives     = true       -- 是否还有复活机会
    enemy.reviving      = false      -- 正在复活动画中
    enemy.reviveTimer   = 0
    enemy.reviveDur     = 2.0        -- 复活动画时间

    -- 阶段
    enemy.phase = 1                  -- 1: 100-60%, 2: 60-0%
    enemy.phaseTransition = false
    enemy.phaseTransTimer = 0

    -- 激活状态
    enemy.activated = false

    -- 绘制尺寸
    enemy.drawSize = 160
    enemy.facing = 1

    -- 行走速度
    enemy.walkSpeed = 65

    -- 伤害传递缓冲
    enemy._pendingDmg = 0
    enemy._pendingStun = 0
    enemy._pendingKnockX = nil
    enemy._pendingKnockY = nil

    return enemy
end

function M.IsCaptainClaw(enemy)
    return enemy and enemy.bossType == "captain_claw"
end

-- ============================================================================
-- 技能选择 AI
-- ============================================================================

local function ChooseSkill(boss, player)
    local dist = math.sqrt((player.x - boss.x)^2 + (player.y - boss.y)^2)
    local available = {}

    -- 阶段 1 技能池: 精准射击、猫爪突刺、四月斩
    if boss.skillCD.precision_shot <= 0 then
        local w = dist > 150 and 5 or 3  -- 远距离更倾向射击
        table.insert(available, { skill = "precision_shot", weight = w })
    end
    if boss.skillCD.shadow_pounce <= 0 then
        local w = dist > 80 and 5 or 2  -- 远距离更倾向突刺拉近
        table.insert(available, { skill = "shadow_pounce", weight = w })
    end
    if boss.skillCD.crescent_quadra <= 0 then
        local w = dist < 120 and 5 or 3  -- 近距离四月斩
        table.insert(available, { skill = "crescent_quadra", weight = w })
    end

    -- 召唤近卫: 一阶段 HP<=60% 后可用，全程仅一次
    if not boss._guardsUsed and boss.hp <= boss.maxHp * 0.6 and boss.skillCD.call_guards <= 0 then
        table.insert(available, { skill = "call_guards", weight = 6 })  -- 高权重优先触发
    end

    -- 阶段 2 额外技能: 军帽威严、战术烟幕
    if boss.phase >= 2 then
        if boss.skillCD.commanding <= 0 then
            local w = dist < 100 and 2 or 1  -- 低权重，近距离稍高
            table.insert(available, { skill = "commanding", weight = w })
        end
        if boss.skillCD.tactical_smoke <= 0 then
            table.insert(available, { skill = "tactical_smoke", weight = 6 })
        end
    end

    if #available == 0 then return SKILL.IDLE end

    -- 加权随机
    local totalW = 0
    for _, v in ipairs(available) do totalW = totalW + v.weight end
    local roll = math.random() * totalW
    local acc = 0
    for _, v in ipairs(available) do
        acc = acc + v.weight
        if roll <= acc then return v.skill end
    end
    return available[#available].skill
end

-- ============================================================================
-- 辅助：朝向玩家
-- ============================================================================
local function FacePlayer(boss, player)
    if player.x > boss.x then
        boss.facing = 1
    elseif player.x < boss.x then
        boss.facing = -1
    end
end

-- ============================================================================
-- 辅助：检查当前动画是否已播放完毕
-- ============================================================================
local function IsAnimFinished(boss)
    local anim = ANIMS[boss.animKey]
    if not anim then return true end
    if anim.loop then return true end  -- 循环动画视为始终完成
    return boss.animFrame >= anim.frames
end

-- ============================================================================
-- 辅助：结束技能（延迟到动画播完）
-- ============================================================================
local function EndSkill(boss, skillKey)
    -- 如果动画还没播完，标记为待结束，稍后由 Update 检查
    if not IsAnimFinished(boss) then
        boss._pendingEndSkill = skillKey
        return
    end
    boss._pendingEndSkill = nil
    boss.skill = SKILL.IDLE
    boss.idleTimer = 0
    local baseCd = SKILL_CD[skillKey] or 5.0
    local mult = boss.phase >= 2 and PHASE2_CD_MULT or 1.0
    boss.skillCD[skillKey] = baseCd * mult

    -- 强制走路计数
    boss._skillUseCount = (boss._skillUseCount or 0) + 1
    if boss._skillUseCount >= 3 then
        boss._skillUseCount = 0
        boss._forceWalkCount = 2
        boss._forceWalkTimer = 0
    end

    M.SetAnim(boss, "idle")
end

-- ============================================================================
-- 技能逻辑：精准射击
-- ============================================================================
-- ============================================================================
-- 技能攻击帧循环配置（在攻击生效期间循环播放效果帧）
-- ============================================================================
local ATTACK_LOOPS = {
    precision_shot_fire  = { start = 11, stop = 14, fps = 8 },  -- 枪口火光
    -- shadow_pounce 不再循环，正常播放完整动画
    -- crescent_quadra 不再循环，正常播放完整动画
    smoke_stealth_smoke  = { start = 5,  stop = 8,  fps = 7 },  -- 烟雾扩散
    smoke_ambush_hit     = { start = 5,  stop = 7,  fps = 8 },  -- 突袭火焰斩
    commanding_release   = { start = 13, stop = 16, fps = 8 },  -- 能量爆发
    call_guards_cast     = { start = 5,  stop = 9,  fps = 7 },  -- 指挥召唤
}

--- 帧循环辅助：在攻击阶段手动推进帧（代替 UpdateAnim）
local function LoopAttackFrames(boss, dt, loopKey)
    local cfg = ATTACK_LOOPS[loopKey]
    if not cfg then return end
    boss._atkLoopTimer = (boss._atkLoopTimer or 0) + dt
    local frameDur = 1.0 / cfg.fps
    if boss._atkLoopTimer >= frameDur then
        boss._atkLoopTimer = boss._atkLoopTimer - frameDur
        boss.animFrame = boss.animFrame + 1
        if boss.animFrame > cfg.stop then
            boss.animFrame = cfg.start
        end
    end
end

local function UpdatePrecisionShot(boss, dt, player, bullets)
    if boss.psState == "none" then
        -- 开始蓄力
        boss.psState = "windup"
        boss.psTimer = 0
        boss.psShotCount = 0
        boss.psShotTimer = 0
        boss._atkLoopTimer = 0
        FacePlayer(boss, player)
        -- 记住瞄准方向
        boss.psTargetX = player.x
        boss.psTargetY = player.y
        M.SetAnim(boss, "precision_shot")
    end

    boss.psTimer = boss.psTimer + dt

    if boss.psState == "windup" then
        -- 蓄力阶段持续瞄准
        boss.psTargetX = player.x
        boss.psTargetY = player.y
        if boss.psTimer >= boss.psWindupDur then
            boss.psState = "firing"
            boss.psShotTimer = 0
            boss._atkLoopTimer = 0
            boss.animFrame = ATTACK_LOOPS.precision_shot_fire.start
            boss.animTimer = 0
        end
    elseif boss.psState == "firing" then
        -- 手动循环火光帧
        LoopAttackFrames(boss, dt, "precision_shot_fire")

        boss.psShotTimer = boss.psShotTimer + dt
        if boss.psShotTimer >= boss.psShotInterval then
            boss.psShotTimer = boss.psShotTimer - boss.psShotInterval
            -- 发射子弹
            local dx = player.x - boss.x
            local dy = player.y - boss.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 1 then dist = 1 end

            -- 基础方向 + 散布
            local spread = boss.psGuaranteed and 0 or (math.random() - 0.5) * 0.15
            local angle = math.atan(dy, dx) + spread
            local vx = math.cos(angle) * boss.psBulletSpeed
            local vy = math.sin(angle) * boss.psBulletSpeed

            table.insert(bullets, {
                x = boss.x + boss.facing * 20,
                y = boss.y - 10,
                vx = vx,
                vy = vy,
                damage = boss.psDmg,
                isEnemy = true,
                life = 3.0,
                radius = 4,
                color = boss.psGuaranteed and {255, 200, 50} or {255, 80, 80},
            })

            boss.psShotCount = boss.psShotCount + 1
            if boss.psShotCount >= boss.psShotMax then
                -- 射击完毕，跳到收招帧继续播放
                boss.psState = "none"
                boss.psGuaranteed = false
                boss.animFrame = ATTACK_LOOPS.precision_shot_fire.stop + 1
                boss.animTimer = 0
                EndSkill(boss, "precision_shot")
            end
        end
    end
end

-- ============================================================================
-- 技能逻辑：猫爪突刺
-- ============================================================================
local function UpdateShadowPounce(boss, dt, player)
    if boss.spState == "none" then
        boss.spState = "windup"
        boss.spTimer = 0
        boss._spHit = false
        FacePlayer(boss, player)
        -- 计算冲刺方向
        local dx = player.x - boss.x
        local dy = player.y - boss.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 1 then dist = 1 end
        boss.spDirX = dx / dist
        boss.spDirY = dy / dist
        M.SetAnim(boss, "shadow_pounce")
        boss.animFrame = 1
        boss.animTimer = 0
    end

    boss.spTimer = boss.spTimer + dt

    if boss.spState == "windup" then
        -- 正常播放前摇帧
        M.UpdateAnim(boss, dt)
        if boss.spTimer >= boss.spWindupDur then
            boss.spState = "dashing"
            boss.spTimer = 0
        end
    elseif boss.spState == "dashing" then
        -- 正常播放冲刺帧
        M.UpdateAnim(boss, dt)
        boss.x = boss.x + boss.spDirX * boss.spDashSpeed * dt
        boss.y = boss.y + boss.spDirY * boss.spDashSpeed * dt
        if boss.spTimer >= boss.spDashDur then
            boss.spState = "slashing"
            boss.spTimer = 0
            boss._screenShake = 0.2
        end
    elseif boss.spState == "slashing" then
        -- 正常播放斩击帧
        M.UpdateAnim(boss, dt)
        -- 斩击判定（仅一次）
        if not boss._spHit then
            local dx = player.x - boss.x
            local dy = player.y - boss.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < boss.spSlashRange then
                boss._pendingDmg = boss.spDmg
                boss._pendingKnockX = boss.spDirX * 150
                boss._pendingKnockY = boss.spDirY * 150
                boss._spHit = true
            end
        end
        if boss.spTimer >= boss.spSlashDur then
            boss.spState = "none"
            EndSkill(boss, "shadow_pounce")
        end
    end
end

-- ============================================================================
-- 技能逻辑：四月斩（近战+远程兼得）
-- 前2斩：近战弧形（贴图），后2斩：远程气刃弹
-- ============================================================================
local function UpdateCrescentQuadra(boss, dt, player, bullets)
    if boss.cqState == "none" then
        boss.cqState = "slashing"
        boss.cqTimer = 0
        boss.cqSlashIndex = 0
        boss._cqHits = {}
        boss._cqSlashEffects = {}  -- 近战斩击特效列表
        FacePlayer(boss, player)
        M.SetAnim(boss, "crescent_quadra")
        boss.animFrame = 1
        boss.animTimer = 0
    end

    boss.cqTimer = boss.cqTimer + dt

    if boss.cqState == "slashing" then
        -- 正常播放完整动画（不再循环）
        M.UpdateAnim(boss, dt)

        -- 检查是否触发下一斩
        local nextSlashTime = boss.cqSlashIndex * boss.cqSlashInterval
        if boss.cqTimer >= nextSlashTime and boss.cqSlashIndex < boss.cqSlashMax then
            boss.cqSlashIndex = boss.cqSlashIndex + 1
            FacePlayer(boss, player)
            local dx = player.x - boss.x
            local dy = player.y - boss.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if boss.cqSlashIndex <= 2 then
                -- === 前2斩：近战弧形 ===
                -- 向玩家方向移动
                if dist > 30 then
                    boss.x = boss.x + (dx / dist) * 25
                    boss.y = boss.y + (dy / dist) * 25
                end
                -- 判定伤害
                local pdx = player.x - boss.x
                local pdy = player.y - boss.y
                local pDist = math.sqrt(pdx * pdx + pdy * pdy)
                if pDist < boss.cqRange then
                    boss._pendingDmg = boss.cqDmg
                    local kd = pDist > 1 and pDist or 1
                    boss._pendingKnockX = (pdx / kd) * 100
                    boss._pendingKnockY = (pdy / kd) * 100
                end
                -- 记录近战斩击特效
                local angle = math.atan(dy, dx)
                table.insert(boss._cqSlashEffects, {
                    x = boss.x, y = boss.y, angle = angle,
                    timer = 0, duration = 0.4,
                })
                boss._screenShake = 0.1
            else
                -- === 后2斩：远程气刃弹 ===
                if dist < 1 then dist = 1 end
                local angle = math.atan(dy, dx)
                -- 发射气刃（扇形 2 发）
                local spread = 0.15  -- 扇形角度
                local offsets = { -spread, spread }
                for _, ofs in ipairs(offsets) do
                    local a = angle + ofs
                    local speed = 220
                    table.insert(M._qiBlades, {
                        x = boss.x + math.cos(a) * 20,
                        y = boss.y + math.sin(a) * 20,
                        vx = math.cos(a) * speed,
                        vy = math.sin(a) * speed,
                        angle = a,
                        damage = boss.cqDmg,
                        life = 2.0,
                        radius = 14,
                        frame = 1,
                        frameTimer = 0,
                    })
                end
                boss._screenShake = boss.cqSlashIndex == boss.cqSlashMax and 0.3 or 0.15
            end
        end

        -- 动画播完或攻击判定结束
        local totalDur = boss.cqSlashMax * boss.cqSlashInterval + 0.3
        if boss.cqTimer >= totalDur then
            boss.cqState = "none"
            EndSkill(boss, "crescent_quadra")
        end
    end
end

-- ============================================================================
-- 技能逻辑：战术烟幕
-- ============================================================================
local function UpdateTacticalSmoke(boss, dt, player)
    if boss.tsState == "none" then
        boss.tsState = "smoke"
        boss.tsTimer = 0
        boss._tsHit = false
        boss._tsSmokeX = boss.x
        boss._tsSmokeY = boss.y
        M.SetAnim(boss, "smoke_stealth")
        boss.animFrame = 1
        boss.animTimer = 0
    end

    boss.tsTimer = boss.tsTimer + dt

    if boss.tsState == "smoke" then
        -- 完整播完烟雾动画后再隐身
        local _, finished = M.UpdateAnim(boss, dt)
        if finished then
            boss.tsState = "stealth"
            boss.tsTimer = 0
            boss._tsVisible = false  -- 进入隐身
        end
    elseif boss.tsState == "stealth" then
        -- 隐身阶段：缓慢跟踪玩家位置
        local dx = player.x - boss.x
        local dy = player.y - boss.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 1 then
            boss.x = boss.x + (dx / dist) * 100 * dt
            boss.y = boss.y + (dy / dist) * 100 * dt
        end
        if boss.tsTimer >= boss.tsStealthDur then
            -- 突袭！出现在玩家附近
            local angle = math.random() * math.pi * 2
            boss.x = player.x + math.cos(angle) * 40
            boss.y = player.y + math.sin(angle) * 40
            boss.tsState = "ambush"
            boss.tsTimer = 0
            boss._tsVisible = true
            boss._atkLoopTimer = 0
            FacePlayer(boss, player)
            M.SetAnim(boss, "smoke_ambush")
            boss.animFrame = ATTACK_LOOPS.smoke_ambush_hit.start
            boss.animTimer = 0
            boss._screenShake = 0.3
        end
    elseif boss.tsState == "ambush" then
        -- 突袭斩击单次播放（不循环）
        local cfg = ATTACK_LOOPS["smoke_ambush_hit"]
        boss._atkLoopTimer = (boss._atkLoopTimer or 0) + dt
        local frameDur = 1.0 / cfg.fps
        if boss._atkLoopTimer >= frameDur then
            boss._atkLoopTimer = boss._atkLoopTimer - frameDur
            if boss.animFrame < cfg.stop then
                boss.animFrame = boss.animFrame + 1
            end
        end
        if not boss._tsHit and boss.tsTimer >= 0.2 then
            local dx = player.x - boss.x
            local dy = player.y - boss.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < boss.tsRange then
                boss._pendingDmg = boss.tsDmg
                local kd = dist > 1 and dist or 1
                boss._pendingKnockX = (dx / kd) * 200
                boss._pendingKnockY = (dy / kd) * 200
                boss._tsHit = true
            end
        end
        if boss.tsTimer >= boss.tsAmbushDur then
            boss.tsState = "none"
            boss.animFrame = ATTACK_LOOPS.smoke_ambush_hit.stop + 1
            boss.animTimer = 0
            EndSkill(boss, "tactical_smoke")
        end
    end
end

-- ============================================================================
-- 技能逻辑：军帽威严
-- ============================================================================
local function UpdateCommanding(boss, dt, player)
    if boss.cmState == "none" then
        boss.cmState = "charging"
        boss.cmTimer = 0
        boss._cmHit = false
        M.SetAnim(boss, "commanding")
    end

    boss.cmTimer = boss.cmTimer + dt

    if boss.cmState == "charging" then
        -- 蓄力阶段（站定不动，能量聚集）
        if boss.cmTimer >= boss.cmChargeDur then
            boss.cmState = "release"
            boss.cmTimer = 0
            boss._atkLoopTimer = 0
            boss.animFrame = ATTACK_LOOPS.commanding_release.start
            boss.animTimer = 0
            boss._screenShake = 0.4
            -- 震退范围内玩家
            local dx = player.x - boss.x
            local dy = player.y - boss.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < boss.cmKnockRange then
                local kd = dist > 1 and dist or 1
                boss._pendingDmg = 5  -- 少量伤害
                boss._pendingKnockX = (dx / kd) * boss.cmKnockForce
                boss._pendingKnockY = (dy / kd) * boss.cmKnockForce
                boss._pendingStun = 0.5
                boss._cmHit = true
                -- 触发下一次精准射击必中
                boss.psGuaranteed = true
            end
        end
    elseif boss.cmState == "release" then
        -- 释放能量帧循环
        LoopAttackFrames(boss, dt, "commanding_release")
        if boss.cmTimer >= boss.cmReleaseDur then
            boss.cmState = "none"
            boss.animFrame = ATTACK_LOOPS.commanding_release.stop  -- 最后一帧就是动画结尾
            boss.animTimer = 0
            EndSkill(boss, "commanding")
        end
    end
end

-- ============================================================================
-- 技能逻辑：召唤近卫
-- ============================================================================
local function UpdateCallGuards(boss, dt)
    if boss.cgState == "none" then
        boss.cgState = "casting"
        boss.cgTimer = 0
        boss._cgSummoned = false
        boss._atkLoopTimer = 0
        M.SetAnim(boss, "call_guards")
        boss.animFrame = ATTACK_LOOPS.call_guards_cast.start
        boss.animTimer = 0
    end

    boss.cgTimer = boss.cgTimer + dt

    if boss.cgState == "casting" then
        -- 施法帧循环
        LoopAttackFrames(boss, dt, "call_guards_cast")
        -- 施法到中段时召唤
        if not boss._cgSummoned and boss.cgTimer >= boss.cgCastDur * 0.6 then
            boss._cgSummoned = true
            boss._guardsUsed = true  -- 全程仅一次
            -- 在 Boss 两侧生成近卫（通过标记让 Enemy.lua 处理生成）
            boss._summonGuards = {
                { x = boss.x - 60, y = boss.y },
                { x = boss.x + 60, y = boss.y },
            }
        end
        if boss.cgTimer >= boss.cgCastDur then
            boss.cgState = "none"
            boss.animFrame = ATTACK_LOOPS.call_guards_cast.stop + 1
            boss.animTimer = 0
            EndSkill(boss, "call_guards")
        end
    end
end

-- ============================================================================
-- 主 Update
-- ============================================================================

function M.Update(boss, dt, player, bullets)
    -- 激活检测
    if not boss.activated then
        if boss.roomL and player.x >= boss.roomL and player.x <= boss.roomR
           and player.y >= boss.roomT and player.y <= boss.roomB then
            boss.activated = true
        else
            M.SetAnim(boss, "idle")
            M.UpdateAnim(boss, dt)
            return
        end
    end

    -- 九命猫复活：HP 从 1 → 30% → 50%，然后进入二阶段
    if boss.reviving then
        boss.reviveTimer = boss.reviveTimer + dt
        if boss._revivePhase == 1 then
            -- 快速恢复到 30%（1.0 秒内）
            local t = math.min(boss.reviveTimer / 1.0, 1.0)
            boss.hp = math.max(boss.hp, math.floor(1 + (boss._reviveTarget30 - 1) * t))
            if t >= 1.0 then
                boss.hp = boss._reviveTarget30
                boss._revivePhase = 2
                boss.reviveTimer = 0
            end
        elseif boss._revivePhase == 2 then
            -- 继续恢复到 50%（1.0 秒内）
            local t = math.min(boss.reviveTimer / 1.0, 1.0)
            boss.hp = math.max(boss.hp, math.floor(boss._reviveTarget30 + (boss._reviveTarget50 - boss._reviveTarget30) * t))
            if t >= 1.0 then
                boss.hp = boss._reviveTarget50
                boss.reviving = false
                boss.phase = 2
                boss.phaseTransition = true
                boss.phaseTransTimer = 0
                -- 进入二阶段：体型增大，速度提升
                boss.drawSize = 180
                boss.walkSpeed = 75
                boss._screenShake = 0.5
                -- 重置所有 CD
                for k, _ in pairs(boss.skillCD) do
                    boss.skillCD[k] = 0
                end
            end
        end
        return  -- 复活期间不行动
    end

    -- 阶段转换动画
    if boss.phaseTransition then
        boss.phaseTransTimer = boss.phaseTransTimer + dt
        if boss.phaseTransTimer >= 1.5 then
            boss.phaseTransition = false
        end
        return
    end

    -- CD 递减
    for k, cd in pairs(boss.skillCD) do
        if cd > 0 then
            boss.skillCD[k] = cd - dt
        end
    end

    -- 阶段2由九命猫触发，此处不再自动转换

    -- 技能状态机
    if boss.skill == SKILL.IDLE then
        -- 强制走路阶段：用完3个技能后强制走路2次
        if (boss._forceWalkCount or 0) > 0 then
            boss._forceWalkTimer = (boss._forceWalkTimer or 0) + dt
            -- 走向玩家
            local dx = player.x - boss.x
            local dy = player.y - boss.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 30 then
                local spd = boss.walkSpeed * dt
                boss.x = boss.x + (dx / dist) * spd
                boss.y = boss.y + (dy / dist) * spd
            end
            M.SetAnim(boss, "walk")
            FacePlayer(boss, player)
            if boss._forceWalkTimer >= (boss._forceWalkDur or 1.0) then
                boss._forceWalkCount = boss._forceWalkCount - 1
                boss._forceWalkTimer = 0
            end
            M.UpdateAnim(boss, dt)
            return
        end

        boss.idleTimer = boss.idleTimer + dt

        -- 走向玩家
        local dx = player.x - boss.x
        local dy = player.y - boss.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 50 then
            local spd = boss.walkSpeed * dt
            boss.x = boss.x + (dx / dist) * spd
            boss.y = boss.y + (dy / dist) * spd
            M.SetAnim(boss, "walk")
        else
            M.SetAnim(boss, "idle")
        end
        FacePlayer(boss, player)

        if boss.idleTimer >= boss.idleDuration then
            local chosen = ChooseSkill(boss, player)
            if chosen ~= SKILL.IDLE then
                boss.skill = chosen
                boss.skillTimer = 0
            end
            boss.idleTimer = 0
        end

    elseif boss._pendingEndSkill then
        -- 技能逻辑已结束，等待动画收招播完，不再执行技能逻辑

    elseif boss.skill == SKILL.PRECISION_SHOT then
        UpdatePrecisionShot(boss, dt, player, bullets)

    elseif boss.skill == SKILL.SHADOW_POUNCE then
        UpdateShadowPounce(boss, dt, player)

    elseif boss.skill == SKILL.CRESCENT_QUADRA then
        UpdateCrescentQuadra(boss, dt, player, bullets)

    elseif boss.skill == SKILL.TACTICAL_SMOKE then
        UpdateTacticalSmoke(boss, dt, player)

    elseif boss.skill == SKILL.COMMANDING then
        UpdateCommanding(boss, dt, player)

    elseif boss.skill == SKILL.CALL_GUARDS then
        UpdateCallGuards(boss, dt)
    end

    -- 动画更新（攻击帧循环阶段手动控帧，跳过通用UpdateAnim）
    local skipAnim = false
    if boss.skill == SKILL.PRECISION_SHOT and boss.psState == "firing" then
        skipAnim = true
    elseif boss.skill == SKILL.SHADOW_POUNCE and boss.spState ~= "none" then
        skipAnim = true
    elseif boss.skill == SKILL.CRESCENT_QUADRA and boss.cqState == "slashing" then
        skipAnim = true
    elseif boss.skill == SKILL.TACTICAL_SMOKE and (boss.tsState == "smoke" or boss.tsState == "ambush") then
        skipAnim = true
    elseif boss.skill == SKILL.COMMANDING and boss.cmState == "release" then
        skipAnim = true
    elseif boss.skill == SKILL.CALL_GUARDS and boss.cgState == "casting" then
        skipAnim = true
    end
    if not skipAnim then
        M.UpdateAnim(boss, dt)
    end

    -- 检查是否有待结束的技能（等动画播完）
    if boss._pendingEndSkill and IsAnimFinished(boss) then
        local key = boss._pendingEndSkill
        boss._pendingEndSkill = nil
        boss.skill = SKILL.IDLE
        boss.idleTimer = 0
        local baseCd = SKILL_CD[key] or 5.0
        local mult = boss.phase >= 2 and PHASE2_CD_MULT or 1.0
        boss.skillCD[key] = baseCd * mult
        -- 强制走路计数
        boss._skillUseCount = (boss._skillUseCount or 0) + 1
        if boss._skillUseCount >= 3 then
            boss._skillUseCount = 0
            boss._forceWalkCount = 2
            boss._forceWalkTimer = 0
        end
        M.SetAnim(boss, "idle")
    end
end

-- ============================================================================
-- 气刃弹更新（四月斩远程部分）
-- ============================================================================
function M.UpdateQiBlades(dt, player)
    for i = #M._qiBlades, 1, -1 do
        local b = M._qiBlades[i]
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        b.life = b.life - dt
        -- 帧动画（4帧循环）
        b.frameTimer = b.frameTimer + dt
        if b.frameTimer >= 0.08 then
            b.frameTimer = b.frameTimer - 0.08
            b.frame = b.frame % 4 + 1
        end
        -- 碰撞检测
        local dx = player.x - b.x
        local dy = player.y - b.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < b.radius + 12 then
            -- 命中玩家
            local PlayerM = require("Player")
            PlayerM.ApplyDamage(player, b.damage, b.x, b.y)
            table.remove(M._qiBlades, i)
        elseif b.life <= 0 then
            table.remove(M._qiBlades, i)
        end
    end
end

-- ============================================================================
-- 受击
-- ============================================================================

function M.TakeDamage(boss, dmg, bulletAngle)
    -- 隐身期间无敌
    if boss.tsState == "stealth" then
        return false
    end

    boss.hp = boss.hp - dmg
    boss.hitFlash = 0.1

    -- 九命猫判定：首次致命伤害 → HP=1 → 恢复至50%进入二阶段
    if boss.hp <= 0 and boss.nineLives then
        boss.nineLives = false
        boss.hp = 1  -- 最低降为1
        boss.reviving = true
        boss.reviveTimer = 0
        boss._reviveTarget30 = math.ceil(boss.maxHp * 0.3)
        boss._reviveTarget50 = math.ceil(boss.maxHp * 0.5)
        boss._revivePhase = 1  -- 1=恢复到30%, 2=恢复到50%
        boss._screenShake = 0.6
        -- 重置当前技能
        boss.skill = SKILL.IDLE
        boss.psState = "none"
        boss.spState = "none"
        boss.cqState = "none"
        M._qiBlades = {}
        boss.tsState = "none"
        boss.cmState = "none"
        boss.cgState = "none"
        boss._tsVisible = true
    end

    return true
end

-- ============================================================================
-- 接触伤害
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
    return nil
end

-- ============================================================================
-- 绘制
-- ============================================================================

function M.Draw(ctx, boss, camX, camY)
    local sx = boss.x - camX
    local sy = boss.y - camY
    local size = boss.drawSize or 160

    -- 隐身时不绘制本体（只绘制烟雾残留）
    if not boss._tsVisible then
        -- 绘制烟雾残影（紫色半透明闪烁）
        local alpha = math.floor(30 + 20 * math.sin((boss.tsTimer or 0) * 8))
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, 30)
        nvgFillColor(ctx, nvgRGBA(120, 40, 160, alpha))
        nvgFill(ctx)
        return
    end

    -- 脚下阴影
    nvgBeginPath(ctx)
    nvgEllipse(ctx, sx, sy + size * 0.13 + 2, size * 0.13, size * 0.04)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 50))
    nvgFill(ctx)

    -- ========== 技能特效（底层）==========

    -- 精准射击：瞄准线
    if boss.skill == SKILL.PRECISION_SHOT and boss.psState == "windup" then
        local dx = boss.psTargetX - boss.x
        local dy = boss.psTargetY - boss.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 1 then
            local ndx, ndy = dx / dist, dy / dist
            local lineLen = 250
            local alpha = 100 + math.floor(math.sin(boss.psTimer * 15) * 80)
            local r = boss.psGuaranteed and 255 or 255
            local g = boss.psGuaranteed and 200 or 50
            local b = boss.psGuaranteed and 50 or 50
            nvgSave(ctx)
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx, sy - 10)
            nvgLineTo(ctx, sx + ndx * lineLen, sy - 10 + ndy * lineLen)
            nvgStrokeColor(ctx, nvgRGBA(r, g, b, alpha))
            nvgStrokeWidth(ctx, boss.psGuaranteed and 3 or 2)
            nvgStroke(ctx)
            nvgRestore(ctx)
        end
    end

    -- 军帽威严：能量光环
    if boss.skill == SKILL.COMMANDING and boss.cmState == "charging" then
        local prog = boss.cmTimer / boss.cmChargeDur
        local radius = boss.cmKnockRange * prog
        local alpha = math.floor(40 + prog * 120)
        -- 外圈
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, radius)
        nvgStrokeColor(ctx, nvgRGBA(255, 180, 30, alpha))
        nvgStrokeWidth(ctx, 2 + prog * 3)
        nvgStroke(ctx)
        -- 内圈脉冲
        local pulse = 0.5 + 0.5 * math.sin(boss.cmTimer * 12)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, radius * 0.5 * pulse)
        nvgFillColor(ctx, nvgRGBA(255, 200, 50, math.floor(alpha * 0.4)))
        nvgFill(ctx)
    end

    -- 四月斩：近战弧形贴图特效
    if boss.skill == SKILL.CRESCENT_QUADRA and boss.cqState == "slashing" then
        -- 延迟加载贴图
        if not cqSlashImg then
            cqSlashImg = nvgCreateImage(ctx, CQ_SLASH_PATH, 0)
        end
        -- 绘制每个近战斩击特效（前2斩）
        if boss._cqSlashEffects then
            for idx, eff in ipairs(boss._cqSlashEffects) do
                local effAge = boss.cqTimer - (idx - 1) * boss.cqSlashInterval
                if effAge > 0 and effAge < eff.duration then
                    local fade = 1.0 - (effAge / eff.duration)
                    local slashSize = boss.cqRange * 1.8
                    nvgSave(ctx)
                    nvgTranslate(ctx, eff.x - camX, eff.y - camY)
                    nvgRotate(ctx, eff.angle - math.pi / 2)
                    nvgGlobalAlpha(ctx, fade)
                    local pat = nvgImagePattern(ctx, -slashSize / 2, -slashSize / 2, slashSize, slashSize, 0, cqSlashImg, 1.0)
                    nvgBeginPath(ctx)
                    nvgRect(ctx, -slashSize / 2, -slashSize / 2, slashSize, slashSize)
                    nvgFillPaint(ctx, pat)
                    nvgFill(ctx)
                    nvgRestore(ctx)
                end
            end
        end
    end

    -- 猫爪突刺：冲刺残影
    if boss.skill == SKILL.SHADOW_POUNCE and boss.spState == "dashing" then
        -- 红色残影尾迹
        for i = 1, 3 do
            local ox = -boss.spDirX * i * 15
            local oy = -boss.spDirY * i * 15
            local a = math.floor(60 - i * 15)
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx + ox, sy + oy, size * 0.2)
            nvgFillColor(ctx, nvgRGBA(200, 40, 40, a))
            nvgFill(ctx)
        end
    end

    -- 战术烟幕：烟雾效果
    if boss.skill == SKILL.TACTICAL_SMOKE and boss.tsState == "smoke" then
        local prog = boss.tsTimer / boss.tsSmokeDur
        local smokeR = 30 + prog * 60
        local alpha = math.floor(180 * (1.0 - prog * 0.5))
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, smokeR)
        nvgFillColor(ctx, nvgRGBA(80, 30, 120, alpha))
        nvgFill(ctx)
    end

    -- ========== 本体绘制 ==========

    -- 受击闪白
    local flashAlpha = 0
    if boss.hitFlash and boss.hitFlash > 0 then
        flashAlpha = math.floor((boss.hitFlash / 0.1) * 180)
    end

    -- 九命猫复活动画：闪烁 + 逐渐放大
    if boss.reviving then
        -- 总进度（两阶段各1秒，共2秒）
        local totalProg = ((boss._revivePhase == 2) and 1.0 or 0.0) + boss.reviveTimer / 1.0
        totalProg = math.min(totalProg / 2.0, 1.0)
        size = size * (1.0 + totalProg * 0.15)
        -- 闪烁效果（越接近完成闪烁越快）
        local flickerSpeed = 8 + totalProg * 8
        if math.floor(boss.reviveTimer * flickerSpeed) % 2 == 0 then
            flashAlpha = 120
        end
    end

    -- 阶段转换闪烁
    if boss.phaseTransition then
        if math.floor(boss.phaseTransTimer * 8) % 2 == 0 then
            flashAlpha = 200
        end
    end

    -- 绘制帧动画
    local flipX = (boss.facing == -1)
    M.DrawFrame(ctx, boss.animKey, boss.animFrame, sx, sy, size, flipX)

    -- 受击闪白（加法混合重绘精灵，只影响有像素的区域）
    if flashAlpha > 0 then
        nvgGlobalCompositeOperation(ctx, NVG_LIGHTER)
        nvgGlobalAlpha(ctx, flashAlpha / 255)
        M.DrawFrame(ctx, boss.animKey, boss.animFrame, sx, sy, size, flipX)
        nvgGlobalAlpha(ctx, 1.0)
        nvgGlobalCompositeOperation(ctx, NVG_SOURCE_OVER)
    end

    -- 精准射击必中标记（头顶金色星标）
    if boss.psGuaranteed then
        local starX = sx
        local starY = sy - size * 0.42
        local pulse = 0.8 + 0.2 * math.sin(os.clock() * 6)
        nvgBeginPath(ctx)
        nvgCircle(ctx, starX, starY, 6 * pulse)
        nvgFillColor(ctx, nvgRGBA(255, 220, 50, 200))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, starX, starY, 9 * pulse)
        nvgStrokeColor(ctx, nvgRGBA(255, 200, 30, 120))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)
    end
end

-- ============================================================================
-- 气刃弹渲染（四月斩远程部分）
-- ============================================================================
function M.DrawQiBlades(ctx, camX, camY)
    if #M._qiBlades == 0 then return end
    -- 延迟加载贴图
    if not cqBladeImg then
        cqBladeImg = nvgCreateImage(ctx, CQ_BLADE_PATH, 0)
    end
    if not cqBladeImg or cqBladeImg <= 0 then return end

    -- 气刃贴图是4帧横排 spritesheet
    local bladeFrameW = 0.25  -- 每帧占整图宽度的1/4
    local bladeSize = 72      -- 绘制尺寸

    for _, b in ipairs(M._qiBlades) do
        local bx = b.x - camX
        local by = b.y - camY
        nvgSave(ctx)
        nvgTranslate(ctx, bx, by)
        nvgRotate(ctx, b.angle)
        -- 使用 spritesheet 的当前帧
        local frameOfs = (b.frame - 1) * bladeFrameW
        -- 绘制当前帧（裁剪一帧的区域）
        local patW = bladeSize * 4  -- 整张图宽
        local patH = bladeSize      -- 整张图高
        local patX = -bladeSize / 2 - (b.frame - 1) * bladeSize
        local patY = -bladeSize / 2
        local pat = nvgImagePattern(ctx, patX, patY, patW, patH, 0, cqBladeImg, 1.0)
        nvgBeginPath(ctx)
        nvgRect(ctx, -bladeSize / 2, -bladeSize / 2, bladeSize, bladeSize)
        nvgFillPaint(ctx, pat)
        nvgFill(ctx)
        nvgRestore(ctx)
    end
end

return M
