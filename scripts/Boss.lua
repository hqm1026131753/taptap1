-- ============================================================================
-- Boss.lua — 铁甲猫骑士 Boss 系统（帧动画 + 技能状态机）+ 多 Boss 分发
-- ============================================================================
local World = require("World")
local Audio = require("AudioManager")

local M = {}

-- 延迟加载 Boss2（避免循环引用）
local Boss2 = nil
local function GetBoss2()
    if not Boss2 then Boss2 = require("Boss2") end
    return Boss2
end

-- ============================================================================
-- Spritesheet 帧动画系统
-- ============================================================================
local sheets = {}  -- 缓存加载的 spritesheet nvg 句柄

---@class BossAnim
---@field sheet string       -- spritesheet 路径
---@field cols number        -- 列数
---@field rows number        -- 行数
---@field frames number      -- 实际帧数
---@field frameW number      -- 每帧宽度
---@field frameH number      -- 每帧高度
---@field fps number         -- 播放速度
---@field loop boolean       -- 是否循环
---@field holdFrames table?  -- {[frameIndex]=holdDuration} 特殊帧停留

-- 动画定义
local ANIMS = {
    idle = {
        sheet = "image/boss/BOSS1/rika_d5e378d5 (1).png",
        cols = 4, rows = 4, frames = 13,
        frameW = 256, frameH = 256,
        fps = 8, loop = true,
    },
    charge = {
        sheet = "image/boss/BOSS1/rika_dfc560c6.png",
        cols = 4, rows = 3, frames = 12,
        frameW = 256, frameH = 256,
        fps = 12, loop = true,  -- 快速播放
    },
    attack = {
        sheet = "image/boss/BOSS1/rika_84b9e7d5.png",
        cols = 4, rows = 6, frames = 21,
        frameW = 256, frameH = 256,
        fps = 11, loop = false,
    },
    guard = {
        -- 复用待机 spritesheet 前7帧，第4帧停留延长
        sheet = "image/boss/BOSS1/rika_d5e378d5 (1).png",
        cols = 4, rows = 4, frames = 7,
        frameW = 256, frameH = 256,
        fps = 6, loop = false,
        holdFrames = { [4] = 1.2 },  -- 第4帧停留1.2秒
    },
    roll = {
        -- 占位：复用冲撞动画（后续替换）
        sheet = "image/boss/BOSS1/rika_dfc560c6.png",
        cols = 4, rows = 3, frames = 12,
        frameW = 256, frameH = 256,
        fps = 14, loop = true,
    },
    stomp_windup = {
        -- 泰山压顶：蓄力（帧1-5），停在最后一帧准备起跳
        sheet = "image/boss/BOSS1/rika_95db8454.png",
        cols = 4, rows = 5, totalFrames = 17,
        startFrame = 1, frames = 5,
        frameW = 256, frameH = 256,
        fps = 8, loop = false,
    },
    stomp_jump = {
        -- 泰山压顶：起跳离开画面（帧6-9）
        sheet = "image/boss/BOSS1/rika_95db8454.png",
        cols = 4, rows = 5, totalFrames = 17,
        startFrame = 6, frames = 4,
        frameW = 256, frameH = 256,
        fps = 12, loop = false,
    },
    stomp_land = {
        -- 泰山压顶：砸落地面（帧10-15）
        sheet = "image/boss/BOSS1/rika_95db8454.png",
        cols = 4, rows = 5, totalFrames = 17,
        startFrame = 10, frames = 6,
        frameW = 256, frameH = 256,
        fps = 13, loop = false,
    },
    stomp_stun = {
        -- 泰山压顶：硬直趴地（帧16-17），循环
        sheet = "image/boss/BOSS1/rika_95db8454.png",
        cols = 4, rows = 5, totalFrames = 17,
        startFrame = 16, frames = 2,
        frameW = 256, frameH = 256,
        fps = 4, loop = true,
    },

}

-- 加载 spritesheet（懒加载）
local function GetSheet(ctx, path)
    if not sheets[path] then
        sheets[path] = nvgCreateImage(ctx, path, 0)
    end
    return sheets[path]
end

-- 绘制某一帧
function M.DrawFrame(ctx, animKey, frameIndex, x, y, size, flipX)
    local anim = ANIMS[animKey]
    if not anim then return end

    local img = GetSheet(ctx, anim.sheet)
    if not img or img <= 0 then return end

    -- 支持 startFrame 偏移：animFrame 是 1-based 局部索引，映射到 sheet 全局帧
    local sheetFrame = (anim.startFrame or 1) - 1 + (frameIndex - 1)  -- 0-based global
    local col = sheetFrame % anim.cols
    local row = math.floor(sheetFrame / anim.cols)

    -- 计算源区域在整图中的UV
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
    -- 原理：pattern 平铺整张图，偏移到让目标帧落在绘制区域
    local patScale = s / anim.frameW  -- 绘制尺寸 / 帧尺寸
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

-- ============================================================================
-- Boss 动画状态更新
-- ============================================================================

--- 推进动画帧，返回当前帧索引（1-based）和是否刚结束
function M.UpdateAnim(boss, dt)
    local anim = ANIMS[boss.animKey]
    if not anim then return 1, false end

    local finished = false

    -- 检查当前帧是否有额外停留
    local holdTime = 0
    if anim.holdFrames then
        holdTime = anim.holdFrames[boss.animFrame] or 0
    end

    local frameDur = (1.0 / anim.fps) + holdTime
    boss.animTimer = boss.animTimer + dt

    if boss.animTimer >= frameDur then
        boss.animTimer = boss.animTimer - frameDur
        boss.animFrame = boss.animFrame + 1

        if boss.animFrame > anim.frames then
            if anim.loop then
                boss.animFrame = 1
            else
                boss.animFrame = anim.frames  -- 停在最后一帧
                finished = true
            end
        end
    end

    return boss.animFrame, finished
end

--- 切换动画
function M.SetAnim(boss, animKey)
    if boss.animKey == animKey then return end
    boss.animKey = animKey
    boss.animFrame = 1
    boss.animTimer = 0
end

-- ============================================================================
-- Boss 技能状态机
-- ============================================================================

-- 技能枚举
local SKILL = {
    IDLE    = "idle",
    CHARGE  = "charge",
    ROLL    = "roll",
    BARRAGE = "barrage",
    STOMP   = "stomp",
    GUARD   = "guard",
}

-- 技能冷却配置
local SKILL_CD = {
    charge  = 4.0,
    roll    = 5.0,
    barrage = 3.5,
    stomp   = 6.0,
    guard   = 8.0,
}

-- Phase2 冷却缩减
local PHASE2_CD_MULT = 0.7

--- 创建铁甲猫骑士 Boss 实例（附加在 enemy 对象上）
function M.InitCatKnight(enemy)
    enemy.bossType = "cat_knight"

    -- 动画状态
    enemy.animKey   = "idle"
    enemy.animFrame = 1
    enemy.animTimer = 0

    -- 技能状态机
    enemy.skill       = SKILL.IDLE
    enemy.skillTimer  = 0        -- 当前技能已用时间
    enemy.skillCD     = {}       -- 各技能剩余冷却
    for k, _ in pairs(SKILL_CD) do
        enemy.skillCD[k] = 0
    end
    enemy.idleDuration = 1.5     -- idle 间隔后选下一个技能
    enemy.idleTimer    = 0

    -- 冲锋参数
    enemy.chargeDir    = { x = 0, y = 0 }
    enemy.chargeSpeed  = 320
    enemy.chargeDist   = 0
    enemy.chargeMaxDist= 280
    enemy.chargeWindup = 0       -- 前摇计时
    enemy.chargeWindupDur = 0.5
    enemy.chargeState  = "none"  -- "windup" / "rushing" / "none"
    -- 冲锋连续次数 (phase2 可连续2次)
    enemy.chargeCombo  = 0
    enemy.chargeComboMax = 1

    -- 滚动参数
    enemy.rollDir      = { x = 1, y = 0 }
    enemy.rollSpeed    = 260
    enemy.rollDuration = 2.5
    enemy.rollBounces  = 0

    -- 弹幕参数
    enemy.barrageCount = 6       -- 一次射几发
    enemy.barrageFired = 0
    enemy.barrageInterval = 0.12 -- 两发间隔
    enemy.barrageTimer = 0

    -- 泰山压顶参数
    enemy.stompWindup  = 0.5     -- 蓄力时间
    enemy.stompAirTime = 1.4     -- 滞空时间（给玩家更多闪躲时间）
    enemy.stompStunDur = 2.0     -- 落地硬直（输出窗口）
    enemy.stompRange   = 100     -- 震波伤害半径
    enemy.stompTimer   = 0
    enemy.stompState   = "none"  -- "windup"/"airborne"/"impact"/"stun"
    enemy.stompLandX   = 0       -- 落地目标坐标
    enemy.stompLandY   = 0
    enemy.stompOrigX   = 0       -- 起跳位置（用于回落）
    enemy.stompOrigY   = 0

    -- 防御参数
    enemy.guardDuration = 2.5
    enemy.guardTimer    = 0
    enemy.guardFacing   = 0      -- 防御朝向角度

    -- Phase
    enemy.phase = 1
    enemy.phaseTransition = false
    enemy.phaseFlashTimer = 0

    -- 激活状态：玩家进入boss房前不行动
    enemy.activated = false

    -- 绘制尺寸
    enemy.drawSize = 120
    enemy.facing = 1  -- 默认朝右

    return enemy
end

--- 是否为铁甲猫骑士
function M.IsCatKnight(enemy)
    return enemy and enemy.bossType == "cat_knight"
end

-- ============================================================================
-- 技能选择 AI
-- ============================================================================

local function ChooseSkill(boss, player)
    -- 收集可用技能（CD 好了的）
    local available = {}
    local distSq = (player.x - boss.x)^2 + (player.y - boss.y)^2

    -- 根据距离加权选择技能（平方比较）
    if boss.skillCD.charge <= 0 then
        local w = distSq > 22500 and 3 or 1  -- 150^2, 远距离更倾向冲锋
        table.insert(available, { skill = SKILL.CHARGE, weight = w })
    end
    if boss.skillCD.roll <= 0 then
        table.insert(available, { skill = SKILL.ROLL, weight = 2 })
    end
    if boss.skillCD.barrage <= 0 then
        local w = distSq > 6400 and 3 or 2   -- 80^2, 远距离更倾向弹幕
        table.insert(available, { skill = SKILL.BARRAGE, weight = w })
    end
    if boss.skillCD.stomp <= 0 then
        local w = distSq > 22500 and 6 or (distSq > 10000 and 3 or 1)  -- 150^2/100^2, 远距离优先泰山压顶
        table.insert(available, { skill = SKILL.STOMP, weight = w })
    end
    if boss.skillCD.guard <= 0 and boss.hp < boss.maxHp * 0.7 then
        table.insert(available, { skill = SKILL.GUARD, weight = 2 })
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
-- Boss 主更新（替代 Enemy 默认 AI）
-- ============================================================================

function M.Update(boss, dt, player, bullets)
    if not M.IsCatKnight(boss) then
        -- 分发到 Boss2
        local b2 = GetBoss2()
        if b2.IsCatHammer(boss) then
            b2.Update(boss, dt, player, bullets)
        end
        return
    end

    -- 激活检测：玩家进入boss房才开始行动
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

    -- 接触伤害冷却递减
    if (boss._contactCD or 0) > 0 then
        boss._contactCD = boss._contactCD - dt
    end

    -- 防御火花特效递减
    if (boss._guardSpark or 0) > 0 then
        boss._guardSpark = boss._guardSpark - dt
    end

    -- Phase 检测
    if boss.phase == 1 and boss.hp <= boss.maxHp * 0.5 then
        boss.phase = 2
        boss.phaseTransition = true
        boss.phaseFlashTimer = 1.5
        -- Phase2 强化
        boss.chargeSpeed = 400
        boss.chargeComboMax = 2
        boss.barrageCount = 11
        boss.rollSpeed = 320
        boss.rollDuration = 3.0
        boss.drawSize = 128  -- Phase2 稍微再大一点
    end

    -- Phase 过渡闪烁
    if boss.phaseTransition then
        boss.phaseFlashTimer = boss.phaseFlashTimer - dt
        if boss.phaseFlashTimer <= 0 then
            boss.phaseTransition = false
        end
        -- 过渡期间不执行技能
        M.SetAnim(boss, "idle")
        return
    end

    -- 更新冷却
    for k, v in pairs(boss.skillCD) do
        if v > 0 then boss.skillCD[k] = v - dt end
    end

    -- 面向玩家（滞空时不更新）
    if not boss._stompAirborne then
        if boss.skill == SKILL.IDLE or boss.skill == SKILL.BARRAGE or boss.skill == SKILL.STOMP then
            if player.x > boss.x then boss.facing = 1 else boss.facing = -1 end
            boss.aimAngle = math.atan(player.y - boss.y, player.x - boss.x)
        end
    end

    -- ======================== 技能状态机 ========================
    if boss.skill == SKILL.IDLE then
        M.SetAnim(boss, "idle")
        boss.idleTimer = boss.idleTimer + dt
        if boss.idleTimer >= boss.idleDuration then
            boss.idleTimer = 0
            local next = ChooseSkill(boss, player)
            boss.skill = next
            boss.skillTimer = 0
            -- 初始化技能
            if next == SKILL.CHARGE then
                boss.chargeState = "windup"
                boss.chargeWindup = 0
                boss.chargeDist = 0
                boss.chargeCombo = 0
                -- 锁定方向
                local dx = player.x - boss.x
                local dy = player.y - boss.y
                local d = math.sqrt(dx*dx + dy*dy)
                if d > 0 then
                    boss.chargeDir = { x = dx/d, y = dy/d }
                end
                if dx > 0 then boss.facing = 1 else boss.facing = -1 end
            elseif next == SKILL.ROLL then
                -- 随机初始方向
                local angle = math.random() * math.pi * 2
                boss.rollDir = { x = math.cos(angle), y = math.sin(angle) }
                boss.rollBounces = 0
                M.SetAnim(boss, "roll")
            elseif next == SKILL.BARRAGE then
                boss.barrageFired = 0
                boss.barrageTimer = 0
                M.SetAnim(boss, "attack")
            elseif next == SKILL.STOMP then
                boss.stompState = "windup"
                boss.stompTimer = 0
                M.SetAnim(boss, "stomp_windup")
            elseif next == SKILL.GUARD then
                boss.guardTimer = 0
                boss.guardFacing = boss.aimAngle
                M.SetAnim(boss, "guard")
            end
        end

    elseif boss.skill == SKILL.CHARGE then
        UpdateCharge(boss, dt, player, bullets)

    elseif boss.skill == SKILL.ROLL then
        UpdateRoll(boss, dt, player)

    elseif boss.skill == SKILL.BARRAGE then
        UpdateBarrage(boss, dt, player, bullets)

    elseif boss.skill == SKILL.STOMP then
        UpdateStomp(boss, dt, player, bullets)

    elseif boss.skill == SKILL.GUARD then
        UpdateGuard(boss, dt, player, bullets)
    end

    -- 房间边界约束：防止冲出 boss 房间
    if boss.roomL then
        local margin = 20
        if boss.x < boss.roomL + margin then boss.x = boss.roomL + margin end
        if boss.x > boss.roomR - margin then boss.x = boss.roomR - margin end
        if boss.y < boss.roomT + margin then boss.y = boss.roomT + margin end
        if boss.y > boss.roomB - margin then boss.y = boss.roomB - margin end
    end

    -- 更新动画帧
    M.UpdateAnim(boss, dt)
end

-- ============================================================================
-- 各技能更新逻辑
-- ============================================================================

function UpdateCharge(boss, dt, player, bullets)
    if boss.chargeState == "windup" then
        M.SetAnim(boss, "idle")  -- 前摇用待机
        boss.chargeWindup = boss.chargeWindup + dt
        if boss.chargeWindup >= boss.chargeWindupDur then
            boss.chargeState = "rushing"
            boss.chargeDist = 0
            M.SetAnim(boss, "charge")
        end

    elseif boss.chargeState == "rushing" then
        local spd = boss.chargeSpeed * dt
        boss.x = boss.x + boss.chargeDir.x * spd
        boss.y = boss.y + boss.chargeDir.y * spd
        boss.chargeDist = boss.chargeDist + spd

        -- 碰墙检测
        local hitWall = World.ResolveWall(boss, 26)

        -- 到达最大距离或撞墙
        if boss.chargeDist >= boss.chargeMaxDist or hitWall then
            boss._screenShake = hitWall and 0.5 or 0.3
            boss.chargeCombo = boss.chargeCombo + 1
            -- Phase2 可连续冲锋
            if boss.chargeCombo < boss.chargeComboMax then
                -- 再来一次：重新锁定方向
                boss.chargeState = "windup"
                boss.chargeWindup = 0
                boss.chargeDist = 0
                local dx = player.x - boss.x
                local dy = player.y - boss.y
                local d = math.sqrt(dx*dx + dy*dy)
                if d > 0 then
                    boss.chargeDir = { x = dx/d, y = dy/d }
                end
                if dx > 0 then boss.facing = 1 else boss.facing = -1 end
            else
                -- 冲锋结束
                EndSkill(boss, "charge")
            end
        end
    end
end

function UpdateRoll(boss, dt, player)
    M.SetAnim(boss, "roll")
    boss.skillTimer = boss.skillTimer + dt

    local spd = boss.rollSpeed * dt
    boss.x = boss.x + boss.rollDir.x * spd
    boss.y = boss.y + boss.rollDir.y * spd

    -- 碰墙反弹
    local prevX, prevY = boss.x, boss.y
    local hitWall = World.ResolveWall(boss, 26)
    if hitWall then
        -- 简单反弹：根据位移差判断反弹轴
        local movedX = boss.x - prevX + boss.rollDir.x * spd
        local movedY = boss.y - prevY + boss.rollDir.y * spd
        -- 粗略判断：哪个轴被推回就反转哪个轴
        if math.abs(boss.x - (prevX + boss.rollDir.x * spd)) > 1 then
            boss.rollDir.x = -boss.rollDir.x
        end
        if math.abs(boss.y - (prevY + boss.rollDir.y * spd)) > 1 then
            boss.rollDir.y = -boss.rollDir.y
        end
        boss.rollBounces = boss.rollBounces + 1
        boss._screenShake = 0.3
    end

    if boss.skillTimer >= boss.rollDuration then
        EndSkill(boss, "roll")
    end
end

function UpdateBarrage(boss, dt, player, bullets)
    M.SetAnim(boss, "attack")
    boss.skillTimer = boss.skillTimer + dt
    boss.barrageTimer = boss.barrageTimer + dt

    -- 持续射击直到动画结束（21帧 @ 12fps ≈ 1.75秒）
    -- 每次间隔发射一波（每波多发扇形弹）
    local bulletsPerWave = boss.phase >= 2 and 4 or 3  -- Phase2 每波4发
    local interval = boss.phase >= 2 and 0.09 or 0.1

    while boss.barrageTimer >= interval do
        boss.barrageTimer = boss.barrageTimer - interval
        boss.barrageFired = boss.barrageFired + 1

        local baseAngle = math.atan(player.y - boss.y, player.x - boss.x)
        local spread = boss.phase >= 2 and 0.55 or 0.45  -- Phase2 扇形更宽
        local bulletSpeed = 200 + math.random() * 40

        for j = 1, bulletsPerWave do
            -- 均匀扇形分布 + 少量随机偏移
            local t = (j - 1) / (bulletsPerWave - 1) - 0.5  -- -0.5 ~ 0.5
            local angle = baseAngle + t * spread * 2 + (math.random() - 0.5) * 0.15

            bullets[#bullets + 1] = {
                x = boss.x + math.cos(angle) * 20,
                y = boss.y + math.sin(angle) * 20,
                vx = math.cos(angle) * bulletSpeed,
                vy = math.sin(angle) * bulletSpeed,
                owner = "enemy",
                dmg = boss.damage,
                life = 1.6,
                bossBullet = true,
            }
        end
        World.SpawnMuzzleFlash(boss.x + math.cos(baseAngle)*20, boss.y + math.sin(baseAngle)*20, baseAngle, "smg")
        boss._screenShake = 0.15
    end

    -- 动画播完才结束技能
    local _, animDone = M.UpdateAnim(boss, 0)
    if animDone or boss.skillTimer > 2.0 then
        EndSkill(boss, "barrage")
    end
end

function UpdateStomp(boss, dt, player, bullets)
    boss.stompTimer = boss.stompTimer + dt

    if boss.stompState == "windup" then
        -- 蓄力阶段：播放 stomp_windup 动画（帧1-5）
        M.SetAnim(boss, "stomp_windup")
        if boss.stompTimer >= boss.stompWindup then
            -- 播起跳动画
            boss.stompState = "jumping"
            boss.stompTimer = 0
            boss.stompOrigX = boss.x
            boss.stompOrigY = boss.y
            M.SetAnim(boss, "stomp_jump")
            -- 预判玩家位置
            local predictTime = boss.stompAirTime * 0.6
            local pvx = (player.vx or 0)
            local pvy = (player.vy or 0)
            boss.stompLandX = player.x + pvx * predictTime
            boss.stompLandY = player.y + pvy * predictTime
        end

    elseif boss.stompState == "jumping" then
        -- 起跳动画阶段（帧6-9），播完后消失
        M.SetAnim(boss, "stomp_jump")
        local _, jumpDone = M.UpdateAnim(boss, 0)
        if jumpDone or boss.stompTimer >= 0.3 then
            boss.stompState = "airborne"
            boss.stompTimer = 0
            boss._stompAirborne = true
        end

    elseif boss.stompState == "airborne" then
        -- 滞空阶段：Boss不可见，红色预警圈些微跟踪玩家（前期快后期慢，给闪躲窗口）
        local progress = math.min(boss.stompTimer / boss.stompAirTime, 1.0)  -- 0→1
        -- 跟踪强度随时间衰减：前70%时间正常追踪，最后30%几乎停止
        local trackFactor = math.max(0, 1.0 - (progress / 0.7))  -- 70%后降为0
        local baseSpeed = boss.phase >= 2 and 100 or 70
        local trackSpeed = baseSpeed * trackFactor * dt
        local dx = player.x - boss.stompLandX
        local dy = player.y - boss.stompLandY
        local d = math.sqrt(dx*dx + dy*dy)
        if d > 1 and trackSpeed > 0.1 then
            boss.stompLandX = boss.stompLandX + (dx / d) * math.min(trackSpeed, d)
            boss.stompLandY = boss.stompLandY + (dy / d) * math.min(trackSpeed, d)
        end

        if boss.stompTimer >= boss.stompAirTime then
            -- 落地！
            boss.stompState = "impact"
            boss.stompTimer = 0
            boss._stompAirborne = false
            -- 传送到落地点
            boss.x = boss.stompLandX
            boss.y = boss.stompLandY
            -- 播砸落动画（帧10-15）
            M.SetAnim(boss, "stomp_land")
            -- 震波伤害（环形弹幕）
            local count = 16
            for i = 1, count do
                local angle = (math.pi * 2) * i / count
                bullets[#bullets + 1] = {
                    x = boss.x + math.cos(angle) * 20,
                    y = boss.y + math.sin(angle) * 20,
                    vx = math.cos(angle) * 140,
                    vy = math.sin(angle) * 140,
                    owner = "enemy",
                    dmg = math.floor(boss.damage * 1.5),
                    life = 0.5,
                    bossBullet = true,
                    isShockwave = true,
                }
            end
            -- 范围内直接伤害判定（平方比较）
            local pdx = player.x - boss.x
            local pdy = player.y - boss.y
            if pdx*pdx + pdy*pdy < boss.stompRange * boss.stompRange then
                local PlayerM = require("Player")
                PlayerM.ApplyDamage(player, math.floor(boss.damage * 2), boss.x, boss.y)
                World.SpawnBlood(player.x, player.y, 8)
            end
            -- 屏幕震动
            boss._screenShake = 0.5
        end

    elseif boss.stompState == "impact" then
        -- 砸落动画播完后进入硬直
        M.SetAnim(boss, "stomp_land")
        local _, landDone = M.UpdateAnim(boss, 0)
        if landDone or boss.stompTimer >= 0.4 then
            boss.stompState = "stun"
            boss.stompTimer = 0
            M.SetAnim(boss, "stomp_stun")
        end

    elseif boss.stompState == "stun" then
        -- 硬直阶段：播放趴地动画（帧16-17循环），玩家输出窗口
        M.SetAnim(boss, "stomp_stun")
        if boss.stompTimer >= boss.stompStunDur then
            boss.stompState = "none"
            boss._stompAirborne = false
            EndSkill(boss, "stomp")
        end
    end
end

function UpdateGuard(boss, dt, player, bullets)
    M.SetAnim(boss, "guard")
    boss.guardTimer = boss.guardTimer + dt

    -- 反弹正面子弹
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        if b.owner == "player" then
            -- 判断子弹是否正面命中（平方比较）
            local dx = b.x - boss.x
            local dy = b.y - boss.y
            if dx*dx + dy*dy < 1296 then -- 36^2
                -- 判断是否正面（子弹来向与防御朝向夹角 < 90°）
                local bulletAngle = math.atan(b.vy, b.vx)
                local angleDiff = math.abs(bulletAngle - boss.guardFacing + math.pi)
                -- 归一化角度差
                while angleDiff > math.pi do angleDiff = angleDiff - math.pi * 2 end
                angleDiff = math.abs(angleDiff)

                if angleDiff < math.pi * 0.6 then
                    -- 反弹！
                    local reflectAngle = bulletAngle + math.pi + (math.random() - 0.5) * 0.8
                    local spd = math.sqrt(b.vx*b.vx + b.vy*b.vy)
                    b.vx = math.cos(reflectAngle) * spd
                    b.vy = math.sin(reflectAngle) * spd
                    b.owner = "enemy"  -- 变成敌方子弹
                    b.dmg = math.ceil(b.dmg * 0.5)
                    boss._screenShake = 0.25
                end
            end
        end
    end

    if boss.guardTimer >= boss.guardDuration then
        EndSkill(boss, "guard")
    end
end

-- 技能结束 → 回到 idle + 设CD
function EndSkill(boss, skillKey)
    boss.skill = SKILL.IDLE
    boss.idleTimer = 0
    boss.idleDuration = 0.8 + math.random() * 0.6  -- 随机间隔

    -- 设置冷却
    local cd = SKILL_CD[skillKey] or 3.0
    if boss.phase >= 2 then cd = cd * PHASE2_CD_MULT end
    boss.skillCD[skillKey] = cd
end

-- ============================================================================
-- Boss 碰撞伤害检测（冲撞/滚动时碰到玩家）
-- 返回伤害值，由 main.lua 扣血
-- ============================================================================
function M.CheckContactDamage(boss, player)
    if not M.IsCatKnight(boss) then return 0 end

    -- 接触伤害冷却（防止每帧伤害）
    if (boss._contactCD or 0) > 0 then return 0 end

    -- 只在冲锋和滚动时有接触伤害
    if boss.skill ~= SKILL.CHARGE and boss.skill ~= SKILL.ROLL then
        return 0
    end
    -- 冲锋前摇不伤人
    if boss.skill == SKILL.CHARGE and boss.chargeState ~= "rushing" then
        return 0
    end

    local dx = player.x - boss.x
    local dy = player.y - boss.y
    local distSq = dx*dx + dy*dy

    if distSq < 1296 then -- 36^2
        boss._contactCD = 0.6  -- 0.6秒冷却
        return boss.damage
    end
    return 0
end

-- ============================================================================
-- Boss 受击（侧面/背面检测 for Guard）
-- 返回 true = 伤害生效, false = 被格挡
-- ============================================================================
function M.TakeDamage(boss, dmg, bulletAngle)
    if not M.IsCatKnight(boss) then
        -- 分发到 Boss2
        local b2 = GetBoss2()
        if b2.IsCatHammer(boss) then
            return b2.TakeDamage(boss, dmg, bulletAngle)
        end
        -- 分发到 Boss3
        if boss.bossType == "armored_cat" then
            local b3 = require("Boss3")
            return b3.TakeDamage(boss, dmg, bulletAngle)
        end
        -- 分发到 Boss4
        if boss.bossType == "captain_claw" then
            local b4 = require("Boss4")
            return b4.TakeDamage(boss, dmg, bulletAngle)
        end
        boss.hp = boss.hp - dmg
        return true
    end

    -- 滞空状态：无法被攻击
    if boss._stompAirborne then
        return false
    end

    -- 防御状态：检测正面格挡
    if boss.skill == SKILL.GUARD then
        local angleDiff = bulletAngle - boss.guardFacing
        -- 归一化
        while angleDiff > math.pi do angleDiff = angleDiff - math.pi * 2 end
        while angleDiff < -math.pi do angleDiff = angleDiff + math.pi * 2 end

        if math.abs(angleDiff) < math.pi * 0.5 then
            -- 正面 → 格挡（不受伤），触发火花特效
            boss._guardSpark = 0.2
            return false
        end
    end

    -- 滚动状态：不可击退但受伤
    boss.hp = boss.hp - dmg
    boss.hitFlash = 0.1
    return true
end

-- ============================================================================
-- Boss 绘制
-- ============================================================================
function M.Draw(ctx, boss, camX, camY)
    if not M.IsCatKnight(boss) then
        -- 分发到 Boss2
        local b2 = GetBoss2()
        if b2.IsCatHammer(boss) then
            b2.Draw(ctx, boss, camX, camY)
        end
        return
    end

    local sx = boss.x - camX
    local sy = boss.y - camY
    local size = boss.drawSize or 80

    -- 泰山压顶：滞空时绘制红色预警圈（Boss不可见）
    if boss._stompAirborne then
        local landSX = boss.stompLandX - camX
        local landSY = boss.stompLandY - camY
        local progress = boss.stompTimer / boss.stompAirTime  -- 0→1

        -- 红色预警圈（脉冲闪烁，越接近落地越明亮越大）
        local baseR = boss.stompRange * 0.6
        local r = baseR * (0.6 + 0.4 * progress)
        local pulse = 0.5 + 0.5 * math.sin(progress * 20)
        local alphaVal = math.floor((120 + 100 * progress) * pulse)

        -- 外圈
        nvgBeginPath(ctx)
        nvgCircle(ctx, landSX, landSY, r)
        nvgStrokeColor(ctx, nvgRGBA(255, 40, 40, alphaVal))
        nvgStrokeWidth(ctx, 3)
        nvgStroke(ctx)

        -- 填充（半透明红）
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

        -- 收缩内圈（表示落地倒计时）
        local innerR = r * (1.0 - progress)
        nvgBeginPath(ctx)
        nvgCircle(ctx, landSX, landSY, innerR)
        nvgStrokeColor(ctx, nvgRGBA(255, 200, 50, math.floor(200 * progress)))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        return  -- Boss 不可见，不绘制本体
    end

    -- 脚下阴影
    nvgBeginPath(ctx)
    nvgEllipse(ctx, sx, sy + size * 0.15, size * 0.35, size * 0.1)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 60))
    nvgFill(ctx)

    -- Phase2 光晕
    if boss.phase >= 2 then
        local pulse = 0.6 + 0.4 * math.abs(math.sin(boss.skillTimer * 4))
        local gp = nvgRadialGradient(ctx, sx, sy, size*0.2, size*0.6,
            nvgRGBA(255, 140, 30, math.floor(80 * pulse)),
            nvgRGBA(255, 60, 0, 0))
        nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, size*0.6)
        nvgFillPaint(ctx, gp) nvgFill(ctx)
    end

    -- 受击闪白
    local alpha = 1.0
    if boss.hitFlash and boss.hitFlash > 0 then
        alpha = 0.5 + 0.5 * math.abs(math.sin(boss.hitFlash * 20))
    end

    -- Phase 过渡闪烁
    if boss.phaseTransition then
        local blink = math.floor(boss.phaseFlashTimer * 10) % 2
        if blink == 0 then alpha = 0.3 end
    end

    -- 硬直阶段半透明闪烁（提示玩家输出窗口）
    if boss.skill == SKILL.STOMP and boss.stompState == "stun" then
        local stunBlink = 0.6 + 0.4 * math.sin(boss.stompTimer * 10)
        alpha = alpha * stunBlink
    end



    -- 绘制帧动画
    nvgGlobalAlpha(ctx, alpha)
    local flipX = (boss.facing == -1)
    M.DrawFrame(ctx, boss.animKey, boss.animFrame, sx, sy - size * 0.15, size, flipX)
    nvgGlobalAlpha(ctx, 1.0)

    -- 血条
    local bw = 64
    local barY = sy - size * 0.55
    nvgBeginPath(ctx) nvgRect(ctx, sx - bw/2, barY, bw, 6)
    nvgFillColor(ctx, nvgRGBA(30, 30, 30, 200)) nvgFill(ctx)

    local hpRatio = boss.hp / boss.maxHp
    local barColor
    if boss.phase >= 2 then
        barColor = nvgRGBA(255, 140, 30, 240)  -- 橙色
    else
        barColor = nvgRGBA(255, 60, 60, 230)   -- 红色
    end
    nvgBeginPath(ctx) nvgRect(ctx, sx - bw/2, barY, bw * hpRatio, 6)
    nvgFillColor(ctx, barColor) nvgFill(ctx)

    -- Boss 名字
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 13)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    local nameColor = boss.phase >= 2 and nvgRGBA(255,160,40,240) or nvgRGBA(255,80,80,230)
    nvgFillColor(ctx, nameColor)
    nvgText(ctx, sx, barY - 2, boss.name, nil)

    -- 防御盾牌特效
    if boss.skill == SKILL.GUARD then
        local shieldR = size * 0.55
        local guardAngle = boss.guardFacing
        local shieldX = sx + math.cos(guardAngle) * size * 0.2
        local shieldY = sy + math.sin(guardAngle) * size * 0.2

        -- 能量盾半圆弧
        local pulse = 0.6 + 0.4 * math.sin(boss.guardTimer * 6)
        local arcStart = guardAngle - math.pi * 0.5
        local arcEnd = guardAngle + math.pi * 0.5

        nvgSave(ctx)
        -- 外层光弧（亮蓝/金色）
        nvgBeginPath(ctx)
        nvgArc(ctx, shieldX, shieldY, shieldR, arcStart, arcEnd, 2)
        local shieldColor = boss.phase >= 2
            and nvgRGBA(255, 180, 40, math.floor(200 * pulse))
            or nvgRGBA(80, 180, 255, math.floor(200 * pulse))
        nvgStrokeColor(ctx, shieldColor)
        nvgStrokeWidth(ctx, 4)
        nvgStroke(ctx)

        -- 内层填充（半透明）
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, shieldX, shieldY)
        nvgArc(ctx, shieldX, shieldY, shieldR * 0.9, arcStart, arcEnd, 2)
        nvgClosePath(ctx)
        local fillColor = boss.phase >= 2
            and nvgRGBA(255, 160, 20, math.floor(40 * pulse))
            or nvgRGBA(60, 140, 255, math.floor(40 * pulse))
        nvgFillColor(ctx, fillColor)
        nvgFill(ctx)

        -- 盾面纹路线条
        for i = 1, 3 do
            local t = (i / 4.0)
            local lineR = shieldR * t
            nvgBeginPath(ctx)
            nvgArc(ctx, shieldX, shieldY, lineR, arcStart, arcEnd, 2)
            local lineAlpha = math.floor(60 * pulse * (1.0 - t))
            local lineColor = boss.phase >= 2
                and nvgRGBA(255, 200, 80, lineAlpha)
                or nvgRGBA(100, 200, 255, lineAlpha)
            nvgStrokeColor(ctx, lineColor)
            nvgStrokeWidth(ctx, 1.5)
            nvgStroke(ctx)
        end

        nvgRestore(ctx)

        -- 反弹火花粒子（击中时短暂显示）
        if boss._guardSpark and boss._guardSpark > 0 then
            local sparkAlpha = boss._guardSpark / 0.2
            for i = 1, 5 do
                local a = guardAngle + (math.random() - 0.5) * 1.2
                local r = 20 + math.random() * 20
                local sparkX = shieldX + math.cos(a) * r
                local sparkY = shieldY + math.sin(a) * r
                local sparkSize = 3 + math.random() * 4
                nvgBeginPath(ctx)
                nvgCircle(ctx, sparkX, sparkY, sparkSize * sparkAlpha)
                nvgFillColor(ctx, nvgRGBA(255, 240, 100, math.floor(220 * sparkAlpha)))
                nvgFill(ctx)
            end
        end
    end

    -- 技能预警指示器
    if boss.skill == SKILL.CHARGE and boss.chargeState == "windup" then
        -- 冲锋方向指示线
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, sx, sy)
        nvgLineTo(ctx, sx + boss.chargeDir.x * 100, sy + boss.chargeDir.y * 100)
        nvgStrokeColor(ctx, nvgRGBA(255, 60, 60, math.floor(150 * (0.5 + 0.5 * math.sin(boss.chargeWindup * 12)))))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)
    elseif boss.skill == SKILL.STOMP and boss.stompState == "windup" then
        -- 蓄力预警圈（Boss脚下）
        local progress = boss.stompTimer / boss.stompWindup
        local r = 50 * progress
        nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, r)
        nvgStrokeColor(ctx, nvgRGBA(255, 200, 50, math.floor(200 * progress)))
        nvgStrokeWidth(ctx, 2.5)
        nvgStroke(ctx)
    elseif boss.skill == SKILL.STOMP and boss.stompState == "impact" then
        -- 落地冲击波扩散效果
        local progress = boss.stompTimer / 0.3
        local r = boss.stompRange * progress
        nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, r)
        nvgStrokeColor(ctx, nvgRGBA(255, 100, 30, math.floor(200 * (1.0 - progress))))
        nvgStrokeWidth(ctx, 4 * (1.0 - progress))
        nvgStroke(ctx)

    end
end

return M
