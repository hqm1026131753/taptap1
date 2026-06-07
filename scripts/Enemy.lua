-- ============================================================================
-- Enemy.lua — 5种猫咪敌人 + 史莱姆 + 三态AI（巡逻/警戒/战斗）
-- ============================================================================
local Data  = require("Data")
local World = require("World")
local Audio = require("AudioManager")
local Boss  = require("Boss")
local Boss2 = require("Boss2")
local Boss3 = require("Boss3")
local Boss4 = require("Boss4")
local Slime = require("Slime")

local M = {}
M._currentFloor = 1  -- 当前层数（由 InitAll 更新）

-- 最少存活敌人数（低于此自动补充）
local MIN_ENEMIES = 4

-- ----------------------------------------------------------------------------
-- 创建单个敌人
-- ----------------------------------------------------------------------------
local function MakeEnemy(tmpl, typeKey, cx, cy)
    local e = {
        x=cx, y=cy,
        typeKey=typeKey,
        name=tmpl.name,
        color=tmpl.color,
        isBoss = tmpl.isBoss or false,

        hp=tmpl.hp, maxHp=tmpl.hp,
        speed=tmpl.speed,
        damage=tmpl.damage,
        detectRange=tmpl.detectRange,
        fovAngle=tmpl.fovAngle * math.pi / 180,  -- 转弧度
        dropRarity=tmpl.dropRarity,
        reward=tmpl.reward,

        facing=1,
        aimAngle=0,
        shootCd=0,
        hitFlash=0,

        -- 三态AI
        state="patrol",
        alertTimer=0,
        lostTimer=0,
        lastKnownX=0,
        lastKnownY=0,

        -- 巡逻随机走
        patrolTimer=0,
        patrolAngle=math.random() * math.pi * 2,

        -- 狙击手专用：保持距离范围
        rangeMin = tmpl.rangeMin,
        rangeMax = tmpl.rangeMax,

        loot = {},
    }
    return e
end

function M.New(col, row, typeKey)
    typeKey = typeKey or "scavenger"
    local tmpl = Data.ENEMY_TYPES[typeKey]
    local cx, cy = World.TileCenter(col, row)
    local e = MakeEnemy(tmpl, typeKey, cx, cy)
    -- 史莱姆专属初始化
    if tmpl.isSlime then
        Slime.Init(e)
    end
    return e
end

-- Boss 直接用世界坐标创建
function M.NewBoss(wx, wy, bossKey, floor)
    bossKey = bossKey or "miniboss"
    local tmpl = Data.BOSS_TYPES[bossKey]
    local e = MakeEnemy(tmpl, bossKey, wx, wy)
    -- 按层数缩放 Boss 属性
    local params = Data.GetFloorParams(floor or 1)
    e.hp     = math.ceil(e.hp * params.hpMult)
    e.maxHp  = e.hp
    e.speed  = e.speed * params.speedMult
    e.damage = math.ceil(e.damage * params.dmgMult)
    -- Boss 攻击速度加成：射击冷却缩短至 ×0.67（攻速 +50%）
    e.bossFireRate = 0.53   -- 0.8 × 0.67 ≈ 0.53 秒/发（基础射速提升50%）
    -- Boss 始终进入战斗状态
    e.state = "combat"
    e.alertTimer = 0
    -- Boss 掉落丰厚（使用 Boss 专属 dropTable，无则回退 BOX_LOOT_TABLE）
    local dropTbl = tmpl.dropTable or Data.BOX_LOOT_TABLE
    local count = math.random(2, 4)
    for _ = 1, count do
        local t = Data.WeightedRandom(dropTbl)
        local item = World.GenerateItem(t, tmpl.dropRarity, floor)
        if item then table.insert(e.loot, item) end
    end
    -- Boss 专属初始化
    if tmpl.isCatKnight then
        Boss.InitCatKnight(e)
    elseif tmpl.isCatHammer then
        Boss2.InitCatHammer(e)
    elseif tmpl.isArmoredCat then
        Boss3.InitArmoredCat(e)
    elseif tmpl.isCaptainClaw then
        Boss4.InitCaptainClaw(e)
    end
    return e
end

-- ----------------------------------------------------------------------------
-- 查询辅助
-- ----------------------------------------------------------------------------
-- 是否有 Boss 存活
function M.HasBossAlive(enemies)
    for _, e in ipairs(enemies) do
        if e.isBoss then return true end
    end
    return false
end

-- ----------------------------------------------------------------------------
-- 基于玩家FOV半径的可见性判断
-- fovRadius: 玩家光圈像素半径（由 main.lua 传入）
-- 返回：visible(bool), dist(number), zone("in"/"near"/"out")
--   in   → dist ≤ fovRadius 且有视线：战斗范围
--   near → fovRadius < dist ≤ fovRadius*1.35：警戒范围（靠近但不攻击）
--   out  → dist > fovRadius*1.35：完全在黑暗中，不察觉
-- ----------------------------------------------------------------------------
local function PlayerFOVCheck(e, px, py, fovRadius)
    local dx   = px - e.x
    local dy   = py - e.y
    local dist = math.sqrt(dx*dx + dy*dy)

    -- 暗影蝠保持原始感知范围；其余敌人有效发现范围缩小 25%
    local effectiveR = (e.typeKey == "mad") and fovRadius or (fovRadius * 0.80)

    if dist > effectiveR * 1.15 then
        return false, dist, "out"
    end

    -- 在感知边缘内，再检查视线
    local hasLOS = World.HasLOS(e.x, e.y, px, py)

    if dist <= effectiveR and hasLOS then
        return true, dist, "in"
    elseif dist <= effectiveR * 1.15 then
        return false, dist, "near"
    else
        return false, dist, "out"
    end
end

-- ----------------------------------------------------------------------------
-- 更新单个敌人（fovRadius = 玩家视野半径像素）
-- ----------------------------------------------------------------------------
local function UpdateOne(e, dt, player, bullets, fovRadius)
    local prevX, prevY = e.x, e.y  -- 记录移动前位置（用于计算速度）
    if e.hitFlash > 0 then e.hitFlash = e.hitFlash - dt end
    if e.shootCd  > 0 then e.shootCd  = e.shootCd  - dt end

    -- Boss 专属 AI（铁甲猫骑士 + 铁甲猫战锤 + 装甲机猫）
    if Boss.IsCatKnight(e) or e.bossType == "cat_hammer" then
        Boss.Update(e, dt, player, bullets)
        return
    end
    if e.bossType == "armored_cat" then
        Boss3.Update(e, dt, player, bullets)
        return
    end
    if e.bossType == "captain_claw" then
        Boss4.Update(e, dt, player, bullets)
        return
    end

    -- 史莱姆专属 AI
    if Slime.IsSlime(e) then
        Slime.Update(e, dt, player)
        return
    end

    -- 中毒 DoT（淬毒刀锋附加）
    if e.poisonTimer and e.poisonTimer > 0 then
        e.poisonTimer = e.poisonTimer - dt
        e._poisonAccum = (e._poisonAccum or 0) + dt
        if e._poisonAccum >= 1.0 then
            e._poisonAccum = e._poisonAccum - 1.0
            local tick = e.poisonDps or 1
            e.hp = e.hp - tick
            e.hitFlash = 0.08
            World.SpawnBlood(e.x, e.y, 2)
            if e.hp <= 0 then
                e.hp = 0   -- 让后续死亡判断处理
            end
        end
        if e.poisonTimer <= 0 then
            e.poisonTimer  = 0
            e._poisonAccum = 0
        end
    end

    -- 检测玩家（基于玩家FOV半径）
    local canSeePlayer, distToPlayer, fovZone = PlayerFOVCheck(e, player.x, player.y, fovRadius)

    -- 敌人朝向：始终面向移动方向或玩家方向（combat时）
    if e.state == "combat" then
        e.aimAngle = math.atan(player.y - e.y, player.x - e.x)
        if player.x > e.x then e.facing = 1 else e.facing = -1 end
    end

    -- ======================== 状态机 ========================
    if e.state == "patrol" then
        -- 巡逻：随机游走（完全在黑暗外，无法察觉玩家）
        e.patrolTimer = e.patrolTimer - dt
        if e.patrolTimer <= 0 then
            e.patrolTimer = 1.2 + math.random() * 1.5
            e.patrolAngle = math.random() * math.pi * 2
        end
        local spd = e.speed * 0.35
        e.x = e.x + math.cos(e.patrolAngle) * spd * dt
        e.y = e.y + math.sin(e.patrolAngle) * spd * dt
        World.ResolveWall(e, e.isBoss and 26 or 13)
        e.aimAngle = e.patrolAngle
        if math.cos(e.patrolAngle) > 0 then e.facing=1 else e.facing=-1 end

        -- 只有进入玩家视野范围内（in 区）才察觉
        if fovZone == "in" then
            e.state = "alert"
            e.alertTimer = 0.4
            Audio.PlayEnemySpotted()
        end

    elseif e.state == "alert" then
        -- 警戒：朝玩家方向慢速靠近（30%速度），不射击
        local dx = player.x - e.x
        local dy = player.y - e.y
        local d  = math.sqrt(dx*dx + dy*dy)
        e.aimAngle = math.atan(dy, dx)
        if dx > 0 then e.facing = 1 else e.facing = -1 end

        -- 慢速靠近（30% 速度）
        if d > 30 then
            e.x = e.x + (dx/d) * e.speed * 0.30 * dt
            e.y = e.y + (dy/d) * e.speed * 0.30 * dt
            World.ResolveWall(e, e.isBoss and 26 or 13)
        end

        e.alertTimer = e.alertTimer - dt

        -- 进入战斗：视野内 且 等待时间结束
        if fovZone == "in" and e.alertTimer <= 0 then
            e.state = "combat"
            e.lostTimer = 0
            e.lastKnownX = player.x
            e.lastKnownY = player.y
        end

        -- 完全离开感知范围 → 回巡逻
        if fovZone == "out" then
            e.state = "patrol"
        end

    elseif e.state == "combat" then
        if fovZone == "in" then
            -- 玩家在视野内：更新最后已知位置
            e.lostTimer = 0
            e.lastKnownX = player.x
            e.lastKnownY = player.y
        elseif fovZone == "near" then
            -- 进入警戒边缘：继续追到最后已知位置，但视野内才能射击
            e.lostTimer = 0
        else
            -- 完全消失在黑暗中
            e.lostTimer = e.lostTimer + dt
            if e.lostTimer >= 2.0 then
                -- 前往最后已知位置
                local dx = e.lastKnownX - e.x
                local dy = e.lastKnownY - e.y
                local d = math.sqrt(dx*dx + dy*dy)
                if d < 20 then
                    -- 到达最后位置，还没找到 → 降级到警戒
                    e.state = "alert"
                    e.alertTimer = 1.0
                    e.lostTimer = 0
                else
                    e.x = e.x + (dx/d) * e.speed * dt
                    e.y = e.y + (dy/d) * e.speed * dt
                    World.ResolveWall(e, e.isBoss and 26 or 13)
                end
            end
        end

        -- 战斗移动 + 射击
        if e.lostTimer < 2.0 then
            local dx = player.x - e.x
            local dy = player.y - e.y
            local d  = math.sqrt(dx*dx + dy*dy)

            if e.rangeMin and e.rangeMax then
                -- 狙击手：保持距离
                if d < e.rangeMin then
                    e.x = e.x - (dx/d) * e.speed * 0.5 * dt
                    e.y = e.y - (dy/d) * e.speed * 0.5 * dt
                elseif d > e.rangeMax then
                    e.x = e.x + (dx/d) * e.speed * 0.5 * dt
                    e.y = e.y + (dy/d) * e.speed * 0.5 * dt
                end
            else
                -- 普通敌人：追击
                if d > 25 then
                    e.x = e.x + (dx/d) * e.speed * dt
                    e.y = e.y + (dy/d) * e.speed * dt
                end
            end
            World.ResolveWall(e, e.isBoss and 26 or 13)

            -- 射击：仅在玩家处于 FOV "in" 区（视野内）时才开枪
            if fovZone == "in" and e.shootCd <= 0 then
                local fireRate = 0.8
                if e.typeKey == "patrol"  then fireRate = 1.0
                elseif e.typeKey == "sniper" then fireRate = 3.0
                elseif e.typeKey == "guard"  then fireRate = 0.6
                elseif e.typeKey == "mad"    then fireRate = 99
                end
                -- Boss 覆盖：使用专属攻速（攻速+50%）
                if e.isBoss and e.bossFireRate then
                    fireRate = e.bossFireRate
                end

                if fireRate < 90 then
                    e.shootCd = fireRate
                    if e.isBoss then
                        -- Boss：8方向环形弹幕，以瞄准玩家的方向为基准均匀展开
                        local bulletSpeed = 252
                        local baseAngle = e.aimAngle  -- 第0颗正对玩家
                        for k = 0, 7 do
                            local angle = baseAngle + (math.pi * 2) * k / 8
                            bullets[#bullets + 1] = {
                                x = e.x + math.cos(angle) * 16,
                                y = e.y + math.sin(angle) * 16,
                                vx = math.cos(angle) * bulletSpeed,
                                vy = math.sin(angle) * bulletSpeed,
                                owner = "enemy",
                                dmg   = e.damage,
                                life  = 1.5,
                            }
                        end
                        World.SpawnMuzzleFlash(e.x, e.y, baseAngle, "shotgun")
                    else
                        local spread = 0.15
                        local angle = e.aimAngle + (math.random() - 0.5) * spread * 2
                        local bulletSpeed = 168
                        bullets[#bullets + 1] = {
                            x = e.x + math.cos(angle) * 16,
                            y = e.y + math.sin(angle) * 16,
                            vx = math.cos(angle) * bulletSpeed,
                            vy = math.sin(angle) * bulletSpeed,
                            owner = "enemy",
                            dmg   = e.damage,
                            life  = 1.5,
                            enemyType = e.typeKey,
                        }
                        if e.typeKey ~= "patrol" then
                            local eWtype = (e.typeKey == "sniper") and "sniper" or "smg"
                            World.SpawnMuzzleFlash(e.x + math.cos(angle)*16, e.y + math.sin(angle)*16, angle, eWtype)
                        end
                    end
                else
                    -- 暗影蝠近战
                    if d < 30 then
                        e.shootCd = 0.5
                        e._meleeDmg = e.damage
                    end
                end
            end
        end
    end

    -- 计算帧速度（供 Render 判断 walk 动画）
    if dt > 0 then
        e.vx = (e.x - prevX) / dt
        e.vy = (e.y - prevY) / dt
    else
        e.vx = 0
        e.vy = 0
    end
end

-- ----------------------------------------------------------------------------
-- 更新所有敌人 + 子弹碰撞
-- fovRadius: 玩家视野半径（像素），由 main.lua 传入
-- ----------------------------------------------------------------------------
-- ============================================================================
-- 电击系统：感电衰减 & 雷电辅助函数
-- ============================================================================

--- 更新单个敌人的感电状态（每帧调用）
local function UpdateShock(e, dt)
    if e.shock and e.shock.stacks > 0 then
        e.shock.duration = e.shock.duration - dt
        if e.shock.duration <= 0 then
            e.shock.stacks = math.max(0, e.shock.stacks - 1)
            e.shock.duration = 3  -- 每层衰减间隔 3 秒
        end
    end
end

--- 给敌人施加感电层数
local function ApplyShock(e, stacks)
    e.shock = e.shock or { stacks = 0, duration = 0 }
    e.shock.stacks = math.min(5, e.shock.stacks + stacks)
    e.shock.duration = 3
end

--- 计算雷电伤害（考虑感电渗透加成）
local function CalcLightningDmg(baseDmg, target, player)
    local mult = 1.0
    if player.shockStackBonus and target.shock and target.shock.stacks > 0 then
        mult = mult + target.shock.stacks * player.shockStackBonus
    end
    return math.floor(baseDmg * mult)
end

--- 对目标造成雷电伤害并施加感电，返回目标是否死亡
local function StrikeLightning(target, baseDmg, shockStacks, player, enemies)
    local dmg = CalcLightningDmg(baseDmg, target, player)
    target.hp = target.hp - dmg
    target.hitFlash = 0.12
    ApplyShock(target, shockStacks)
    World.SpawnBlood(target.x, target.y, 3)
    World.SpawnLightningFx(target.x, target.y, 36)

    -- 电场加速
    if player.electricSpeedBoost then
        player.speedBoostMult  = 1.0 + (player.electricSpeedBoost or 0.05)
        player.speedBoostTimer = 2.0
    end
    -- 雷影步无敌
    if player.elecDodge then
        player.elecDodgeTimer = player.elecDodgeDur or 0.3
    end
    -- 电磁风暴联动：30%概率爆炸（限玩家视野内）
    if player.elecExplode and math.random() < (player.elecExplodeChance or 0.30) then
        local er = 60
        for _, oe in ipairs(enemies) do
            if oe ~= target and oe.hp > 0 then
                local px = oe.x - player.x
                local py = oe.y - player.y
                if px*px + py*py < 210*210 then
                    local ex = oe.x - target.x
                    local ey = oe.y - target.y
                    if ex*ex + ey*ey < er*er then
                        oe.hp = oe.hp - math.floor(dmg * 0.4)
                        oe.hitFlash = 0.1
                    end
                end
            end
        end
    end
    -- 电荷炸弹引爆：5层感电时爆炸（限玩家视野内）
    if player.shockDetonate and target.shock and target.shock.stacks >= (player.shockDetonateAt or 5) then
        target.shock.stacks = 0
        local er = 80
        for _, oe in ipairs(enemies) do
            if oe.hp > 0 then
                local px = oe.x - player.x
                local py = oe.y - player.y
                if px*px + py*py < 210*210 then
                    local ex = oe.x - target.x
                    local ey = oe.y - target.y
                    if ex*ex + ey*ey < er*er then
                        oe.hp = oe.hp - math.floor(dmg * 1.5)
                        oe.hitFlash = 0.15
                        ApplyShock(oe, 1)
                    end
                end
            end
        end
        World.SpawnBlood(target.x, target.y, 10)
    end
    return target.hp <= 0
end

--- 雷电链跳跃（递归跳跃最近敌人）
local function ChainLightning(origin, baseDmg, maxBounces, player, enemies, exclude, fovRadius)
    local bounces = 0
    local current = origin
    local excluded = exclude or {}
    excluded[origin] = true
    local chainDmg = baseDmg
    local fovR2 = (fovRadius or 210) * (fovRadius or 210)

    while bounces < maxBounces do
        -- 找最近的存活敌人（必须在玩家视野内）
        local best, bestDist = nil, math.huge
        for _, oe in ipairs(enemies) do
            if oe.hp > 0 and not excluded[oe] then
                -- 检查是否在玩家有效视野内
                local px = oe.x - player.x
                local py = oe.y - player.y
                if px*px + py*py < fovR2 then
                    local dx = oe.x - current.x
                    local dy = oe.y - current.y
                    local d = dx*dx + dy*dy
                    if d < 180*180 and d < bestDist then
                        bestDist = d; best = oe
                    end
                end
            end
        end
        if not best then break end

        -- 跳跃伤害递增（静电充能）
        if player.chainRampUp then
            chainDmg = math.floor(chainDmg * (1.0 + (player.chainRampUp or 0.1)))
        end
        -- 衰减（高压电击）
        if player.elecChainDecay then
            chainDmg = math.floor(chainDmg * player.elecChainDecay)
        end

        StrikeLightning(best, chainDmg, 1, player, enemies)
        excluded[best] = true
        current = best
        bounces = bounces + 1

        -- 弹射&链共享计数（静电冲击联动）
        if player.bounceChainSync then
            player._sharedBounceCount = (player._sharedBounceCount or 0) + 1
        end
    end
    return bounces
end

function M.UpdateAll(enemies, dt, player, bullets, fovRadius)
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        UpdateOne(e, dt, player, bullets, fovRadius)

        -- 感电衰减
        UpdateShock(e, dt)

        -- 中毒死亡处理（毒 DoT 可能在 UpdateOne 内把 hp 清零）
        if e.hp <= 0 and not e._poisonDeathHandled then
            -- 检查是否有毒（确认是毒死的而非其他逻辑）
            -- 为避免与子弹命中的死亡处理冲突，只处理不在子弹命中路径中的死亡
            -- 利用 poisonTimer <= 0 意味着毒刚结束（但 hp 已被扣到0）
            -- 保险起见：任何 hp<=0 且未被子弹/刀处理的都在这里清理
            e._poisonDeathHandled = true
            Audio.PlayEnemyDie()
            World.SpawnBlood(e.x, e.y, 12)
            -- 史莱姆和Boss必定掉落，其他怪50%概率
            if #e.loot > 0 and (e.isSlime or e.isBoss or math.random() < 0.5) then
                World.SpawnCorpse(e.x, e.y, e.loot, e.name, e.isBoss)
            end
            player.kills = player.kills + 1
            if player.hasLifesteal then
                local heal = math.floor(player.maxHp * (player.lifestealPct or 0.08))
                player.hp = math.min(player.maxHp, player.hp + heal)
            end
            if player.ammoFreeOnKill then player.ammoFreeTimer = 3.0 end
            player.screenShake = math.max(player.screenShake or 0, e.isBoss and 1.0 or 0.2)
            table.remove(enemies, i)
            goto continue_enemy
        end

        -- 近战伤害处理
        if e._meleeDmg then
            local PlayerM = require("Player")
            PlayerM.ApplyDamage(player, e._meleeDmg, e.x, e.y)
            e._meleeDmg = nil
            World.SpawnBlood(player.x, player.y, 4)
        end

        -- Boss接触伤害（冲锋/翻滚）
        if Boss.IsCatKnight(e) then
            local contactDmg = Boss.CheckContactDamage(e, player)
            if contactDmg and contactDmg > 0 then
                local PlayerM = require("Player")
                PlayerM.ApplyDamage(player, contactDmg, e.x, e.y)
                World.SpawnBlood(player.x, player.y, 6)
            end
        elseif e.bossType == "armored_cat" then
            local contactDmg = Boss3.CheckContactDamage(e, player)
            if contactDmg and contactDmg > 0 then
                local PlayerM = require("Player")
                PlayerM.ApplyDamage(player, contactDmg, e.x, e.y)
                World.SpawnBlood(player.x, player.y, 6)
            end
        elseif e.bossType == "captain_claw" then
            local contactDmg = Boss4.CheckContactDamage(e, player)
            if contactDmg and contactDmg > 0 then
                local PlayerM = require("Player")
                PlayerM.ApplyDamage(player, contactDmg, e.x, e.y)
                World.SpawnBlood(player.x, player.y, 6)
            end
        end

        -- Boss技能屏幕震动传递
        if e.isBoss and (e._screenShake or 0) > 0 then
            player.screenShake = math.max(player.screenShake or 0, e._screenShake)
            e._screenShake = 0
        end

        -- Boss4 召唤近卫：生成 2 只 cat_knight（30% 血量上限）
        if e._summonGuards then
            local guards = e._summonGuards
            e._summonGuards = nil
            for _, pos in ipairs(guards) do
                local guard = M.NewBoss(pos.x, pos.y, "cat_knight", M._currentFloor)
                guard.maxHp = math.ceil(guard.maxHp * 0.3)
                guard.hp = guard.maxHp
                guard.activated = true  -- 立即激活
                guard.drawSize = (guard.drawSize or 140) * 0.8  -- 稍小一点
                -- 继承 boss 房间范围
                guard.roomL = e.roomL
                guard.roomR = e.roomR
                guard.roomT = e.roomT
                guard.roomB = e.roomB
                table.insert(enemies, guard)
            end
        end

        -- 玩家子弹命中
        for j = #bullets, 1, -1 do
            local b = bullets[j]
            if b.owner == "player" then
                if b.skipEnemy == e then goto continue_bullet end
                -- ---- 剑气波：穿透命中，每个敌人只伤一次 ----
                if b.isSlashWave then
                    if b.hitEnemies[e] then goto continue_bullet end
                    local dx = b.x - e.x
                    local dy = b.y - e.y
                    if dx*dx + dy*dy < 22*22 then
                        b.hitEnemies[e] = true
                        local dmg = b.dmg
                        -- 暴击
                        local crit = player.critChance or 0
                        if player.moveCritDouble and player.isMoving then crit = crit * 2 end
                        local isCrit = player.guaranteedCritFullHp and e.hp >= e.maxHp
                        if not isCrit and crit > 0 and math.random() < crit then isCrit = true end
                        -- 处决：对HP低于阈值的敌人必定暴击
                        if not isCrit and player.executeThresh and e.hp < e.maxHp * player.executeThresh then
                            isCrit = true
                        end
                        if isCrit then
                            dmg = math.floor(dmg * (player.critMultiplier or 2.0))
                            player.screenShake = math.max(player.screenShake or 0, 0.15)
                        end
                        World.SpawnDmgPopup(e.x, e.y, dmg, isCrit)
                        -- Boss伤害分发（所有Boss走统一TakeDamage）
                        if e.isBoss then
                            local bAngle = math.atan(b.vy, b.vx)
                            local hit = Boss.TakeDamage(e, dmg, bAngle)
                            if not hit then
                                -- 被格挡，反弹子弹
                                b.owner = "enemy"
                                b.dmg = math.floor(dmg * 0.5)
                                b.vx = -b.vx
                                b.vy = -b.vy
                                b.life = 1.0
                                goto continue_bullet
                            end
                            -- hit=true: Boss内部已扣血
                        else
                            e.hp = e.hp - dmg
                        end
                        e.hitFlash = 0.15
                        if e.state == "patrol" then e.state = "alert"; e.alertTimer = 0.1 end
                        Audio.PlayEnemyHit()
                        if e.isBoss then
                            World.SpawnSpark(e.x, e.y, isCrit and 14 or 10)
                        else
                            World.SpawnBlood(e.x, e.y, isCrit and 8 or 4)
                        end
                        if e.hp <= 0 then
                            Audio.PlayEnemyDie()
                            World.SpawnBlood(e.x, e.y, 12)
                            -- 史莱姆和Boss必定掉落，其他怪50%概率
                            if #e.loot > 0 and (e.isSlime or e.isBoss or math.random() < 0.5) then
                                World.SpawnCorpse(e.x, e.y, e.loot, e.name, e.isBoss)
                            end
                            player.kills = player.kills + 1
                            if player.hasLifesteal then
                                local heal = math.floor(player.maxHp * (player.lifestealPct or 0.08))
                                player.hp = math.min(player.maxHp, player.hp + heal)
                            end
                            -- 吸血注射（vampirePct）：击杀回血
                            if player.vampirePct and player.vampirePct > 0 then
                                local vHeal = math.max(1, math.floor(player.maxHp * player.vampirePct))
                                player.hp = math.min(player.maxHp, player.hp + vHeal)
                            end
                            -- 弹药回收：25%概率归还1发弹药
                            if player.ammoOnKill and player.weapon and player.weapon.ammo ~= nil then
                                if math.random() < player.ammoOnKill then
                                    player.weapon.ammo = math.min(player.weapon.maxAmmo or 999, player.weapon.ammo + 1)
                                end
                            end
                            if player.ammoFreeOnKill then player.ammoFreeTimer = 3.0 end
                            player.screenShake = math.max(player.screenShake or 0, e.isBoss and 1.0 or 0.2)
                            table.remove(enemies, i)
                            break  -- 敌人已移除，跳出当前敌人的子弹循环
                        end
                    end
                    goto continue_bullet  -- 穿透：不移除弹体
                end
                -- ---- 普通子弹命中 ----
                local dx = b.x - e.x
                local dy = b.y - e.y
                if dx*dx + dy*dy < 16*16 then
                    -- 暴击计算
                    local dmg = b.dmg

                    -- 甲伤转化：每10护甲+5%伤害
                    if player.armorScalesDamage then
                        local PlayerM = require("Player")
                        local arv = PlayerM.CalcArmorValue(player)
                        dmg = math.floor(dmg * (1.0 + math.floor(arv / 10) * 0.05))
                    end

                    -- 弱点标记：连续命中同一敌人3次后，本次额外+50%暴击率
                    local markBonus = 0
                    if player.markTarget then
                        if player.markLastTarget == e then
                            player.markHits = (player.markHits or 0) + 1
                        else
                            player.markLastTarget = e
                            player.markHits = 1
                        end
                        if player.markHits >= 3 then
                            markBonus = 0.50
                        end
                    end

                    -- 有效暴击率（移动时双倍）
                    local crit = (player.critChance or 0) + markBonus
                    if player.moveCritDouble and player.isMoving then crit = crit * 2 end

                    -- 满血必暴击
                    local isCrit = false
                    if player.guaranteedCritFullHp and e.hp >= e.maxHp then
                        isCrit = true
                    elseif crit > 0 and math.random() < crit then
                        isCrit = true
                    end
                    -- 处决：对HP低于阈值的敌人必定暴击
                    if not isCrit and player.executeThresh and e.hp < e.maxHp * player.executeThresh then
                        isCrit = true
                    end
                    -- 格斗之魂：每N次攻击必定暴击
                    if not isCrit and player.guaranteedCritEvery then
                        player._critCounter = (player._critCounter or 0) + 1
                        if player._critCounter >= player.guaranteedCritEvery then
                            isCrit = true
                            player._critCounter = 0
                        end
                    end

                    if isCrit then
                        dmg = math.floor(dmg * (player.critMultiplier or 2.0))
                        player.screenShake = math.max(player.screenShake or 0, 0.15)
                        World.SpawnBlood(e.x, e.y, 6)
                        -- 混沌子弹：暴击时随机触发附加效果
                        if player.randomChaosOnCrit then
                            local roll = math.random(3)
                            if roll == 1 then
                                -- 弹射一次
                                b._chaosBounce = true
                            elseif roll == 2 then
                                -- 小爆炸
                                local cr = (player.explosionRadius or 48) * 0.5
                                for _, oe in ipairs(enemies) do
                                    if oe ~= e then
                                        local ex = oe.x - b.x
                                        local ey = oe.y - b.y
                                        if ex*ex + ey*ey < cr*cr then
                                            oe.hp = oe.hp - math.floor(dmg * 0.3)
                                            oe.hitFlash = 0.1
                                        end
                                    end
                                end
                                World.SpawnBlood(b.x, b.y, 5)
                            else
                                -- 吸血
                                local heal = math.max(1, math.floor(player.maxHp * 0.05))
                                player.hp = math.min(player.maxHp, player.hp + heal)
                            end
                        end

                        -- ⚡ 磁暴电涌：暴击时在目标处落下雷电
                        if player.electricStorm then
                            local lightDmg = math.floor(dmg * 0.6)
                            StrikeLightning(e, lightDmg, 2, player, enemies)

                            -- 高压电击：雷电跳跃至附近敌人
                            if player.elecChain then
                                local maxJumps = 1 + (player.elecExtraBounce or 0)
                                -- 弹射&链共享（静电冲击联动）
                                if player.bounceChainSync then
                                    maxJumps = maxJumps + (player._sharedBounceCount or 0)
                                    player._sharedBounceCount = 0
                                end
                                ChainLightning(e, lightDmg, maxJumps, player, enemies, nil, fovRadius)
                            end
                        end

                        -- ⚡ 雷暴（7层阈值）：暴击时三道雷电攻击不同目标（限玩家视野内）
                        if player.elecTripleStrike then
                            local strikeCount = 0
                            local fovR2 = fovRadius * fovRadius
                            for _, oe in ipairs(enemies) do
                                if oe ~= e and oe.hp > 0 and strikeCount < 3 then
                                    -- 必须在玩家视野内
                                    local px2 = oe.x - player.x
                                    local py2 = oe.y - player.y
                                    if px2*px2 + py2*py2 < fovR2 then
                                        local dx2 = oe.x - e.x
                                        local dy2 = oe.y - e.y
                                        if dx2*dx2 + dy2*dy2 < 250*250 then
                                            StrikeLightning(oe, math.floor(dmg * 0.5), 1, player, enemies)
                                            strikeCount = strikeCount + 1
                                        end
                                    end
                                end
                            end
                        end

                        -- ⚡ 过载联动：暴击时对周围敌人造成雷电伤害（限玩家视野内）
                        if player.elecOvercharge then
                            local ocr = 100
                            local fovR2 = fovRadius * fovRadius
                            for _, oe in ipairs(enemies) do
                                if oe ~= e and oe.hp > 0 then
                                    -- 必须在玩家视野内
                                    local px2 = oe.x - player.x
                                    local py2 = oe.y - player.y
                                    if px2*px2 + py2*py2 < fovR2 then
                                        local dx2 = oe.x - e.x
                                        local dy2 = oe.y - e.y
                                        if dx2*dx2 + dy2*dy2 < ocr*ocr then
                                            local oDmg = CalcLightningDmg(math.floor(dmg * 0.35), oe, player)
                                            oe.hp = oe.hp - oDmg
                                            oe.hitFlash = 0.1
                                            ApplyShock(oe, 1)
                                        end
                                    end
                                end
                            end
                        end
                    end

                    -- 浮动伤害数字（暴击/普通都弹）
                    World.SpawnDmgPopup(e.x, e.y, dmg, isCrit)

                    -- 过热枪管：连续命中同一敌人5次爆炸
                    if player.explosionOnStack then
                        b._hitStack = b._hitStack or {}
                        b._hitStack[e] = (b._hitStack[e] or 0) + 1
                        if b._hitStack[e] >= 5 then
                            b._hitStack[e] = 0
                            local eRadius = (player.explosionRadius or 48)
                            for _, oe in ipairs(enemies) do
                                local ex = oe.x - e.x
                                local ey = oe.y - e.y
                                if ex*ex + ey*ey < eRadius*eRadius then
                                    oe.hp = oe.hp - math.floor(dmg * 0.8)
                                    oe.hitFlash = 0.15
                                end
                            end
                            World.SpawnBlood(e.x, e.y, 10)
                        end
                    end

                    -- Boss伤害分发（所有Boss走统一TakeDamage）
                    if e.isBoss then
                        local bAngle = math.atan(b.vy, b.vx)
                        local hit = Boss.TakeDamage(e, dmg, bAngle)
                        if not hit then
                            -- 被格挡，反弹子弹
                            b.owner = "enemy"
                            b.dmg = math.floor(dmg * 0.5)
                            b.vx = -b.vx
                            b.vy = -b.vy
                            b.life = 1.0
                            goto continue_bullet
                        end
                        -- hit=true: Boss内部已扣血
                    else
                        e.hp = e.hp - dmg
                    end
                    e.hitFlash = 0.15
                    if e.state == "patrol" then e.state = "alert"; e.alertTimer = 0.1 end
                    Audio.PlayEnemyHit()
                    if e.isBoss then
                        World.SpawnSpark(e.x, e.y, 10)
                    else
                        World.SpawnBlood(e.x, e.y, 4)
                    end

                    -- 爆炸子弹 AOE
                    if player.hasExplosion then
                        local eRadius = player.explosionRadius or 48
                        for _, oe in ipairs(enemies) do
                            if oe ~= e then
                                local ex = oe.x - b.x
                                local ey = oe.y - b.y
                                if ex*ex + ey*ey < eRadius*eRadius then
                                    local aoeDmg = math.floor(dmg * 0.5)
                                    oe.hp = oe.hp - aoeDmg
                                    oe.hitFlash = 0.1
                                    -- 连锁爆炸：30%概率对AOE命中敌人再触发一次小爆炸
                                    if player.chainExplosion and math.random() < 0.30 then
                                        local cr2 = eRadius * 0.6
                                        for _, oe2 in ipairs(enemies) do
                                            if oe2 ~= oe and oe2 ~= e then
                                                local ex2 = oe2.x - oe.x
                                                local ey2 = oe2.y - oe.y
                                                if ex2*ex2 + ey2*ey2 < cr2*cr2 then
                                                    oe2.hp = oe2.hp - math.floor(aoeDmg * 0.4)
                                                    oe2.hitFlash = 0.08
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        World.SpawnBlood(b.x, b.y, 8)
                    end

                    -- 混乱弹夹特效（chaosEffect 有效期内每颗子弹附带）
                    if player.chaosEffect and player.chaosTimer and player.chaosTimer > 0 then
                        if player.chaosEffect == 1 then
                            -- 弹射：标记本颗子弹执行一次额外弹射
                            b._chaosBounce = true
                        elseif player.chaosEffect == 2 then
                            -- 爆炸：以命中点为圆心 60px 小爆炸，造成 40% 伤害
                            local cr = 60
                            for _, oe in ipairs(enemies) do
                                if oe ~= e then
                                    local ex = oe.x - b.x
                                    local ey = oe.y - b.y
                                    if ex*ex + ey*ey < cr*cr then
                                        oe.hp = oe.hp - math.floor(dmg * 0.4)
                                        oe.hitFlash = 0.1
                                    end
                                end
                            end
                            World.SpawnBlood(b.x, b.y, 5)
                        elseif player.chaosEffect == 3 then
                            -- 吸血：每次命中回复 3% 最大HP
                            local heal = math.max(1, math.floor(player.maxHp * 0.03))
                            player.hp = math.min(player.maxHp, player.hp + heal)
                        end
                    end

                    -- 闪电链：命中后15%概率连锁伤害附近1~2个敌人
                    if player.chainLightning and player.chainChance and player.chainChance > 0
                        and math.random() < player.chainChance then
                        local chainDmg = math.floor(dmg * 0.4)
                        local chainCount = 0
                        for _, oe in ipairs(enemies) do
                            if oe ~= e and oe.hp > 0 and chainCount < 2 then
                                local cx = oe.x - e.x
                                local cy = oe.y - e.y
                                if cx*cx + cy*cy < 150*150 then
                                    oe.hp = oe.hp - chainDmg
                                    oe.hitFlash = 0.10
                                    World.SpawnBlood(oe.x, oe.y, 3)
                                    chainCount = chainCount + 1
                                end
                            end
                        end
                    end

                    -- 弹射处理（含混沌子弹额外弹射）
                    local wantBounce = (player.bounceCount and player.bounceCount > 0)
                                    or b._chaosBounce
                    local bounced = false
                    if wantBounce and (b.bounces or 0) < math.max(player.bounceCount or 0, b._chaosBounce and 1 or 0) then
                        local best, bestDist = nil, math.huge
                        for _, oe in ipairs(enemies) do
                            if oe ~= e and oe.hp > 0 then
                                local ox = oe.x - b.x
                                local oy = oe.y - b.y
                                local d  = math.sqrt(ox*ox + oy*oy)
                                if d < bestDist then bestDist = d; best = oe end
                            end
                        end
                        if best then
                            local bx = best.x - b.x
                            local by = best.y - b.y
                            local len = math.sqrt(bx*bx + by*by)
                            if len > 1 then
                                b.vx = (bx/len) * 500
                                b.vy = (by/len) * 500
                            end
                            b.bounces      = (b.bounces or 0) + 1
                            b.dmg          = math.floor(b.dmg * 0.4)  -- 弹射伤害衰减60%
                            b.life         = math.max(b.life, 0.8)
                            b.skipEnemy    = e
                            b._chaosBounce = nil
                            bounced        = true
                            -- 弹射&链共享计数（静电冲击联动）
                            if player.bounceChainSync then
                                player._sharedBounceCount = (player._sharedBounceCount or 0) + 1
                            end
                        end
                    end
                    if not bounced then
                        table.remove(bullets, j)
                    end
                    if e.hp <= 0 then
                        Audio.PlayEnemyDie()
                        World.SpawnBlood(e.x, e.y, 12)
                        -- 史莱姆和Boss必定掉落，其他怪50%概率
                        if #e.loot > 0 and (e.isSlime or e.isBoss or math.random() < 0.5) then
                            World.SpawnCorpse(e.x, e.y, e.loot, e.name, e.isBoss)
                        end
                        player.kills = player.kills + 1
                        -- 吸血
                        if player.hasLifesteal then
                            local heal = math.floor(player.maxHp * (player.lifestealPct or 0.08))
                            player.hp = math.min(player.maxHp, player.hp + heal)
                        end
                        -- 吸血注射（vampirePct）：击杀回血
                        if player.vampirePct and player.vampirePct > 0 then
                            local vHeal = math.max(1, math.floor(player.maxHp * player.vampirePct))
                            player.hp = math.min(player.maxHp, player.hp + vHeal)
                        end
                        -- 弹药回收：25%概率归还1发弹药
                        if player.ammoOnKill and player.weapon and player.weapon.ammo ~= nil then
                            if math.random() < player.ammoOnKill then
                                player.weapon.ammo = math.min(player.weapon.maxAmmo or 999, player.weapon.ammo + 1)
                            end
                        end
                        -- 无限火力：枪击击杀后3秒免弹药
                        if player.ammoFreeOnKill then player.ammoFreeTimer = 3.0 end
                        -- 暗影步：枪击击杀后闪现到视野范围内敌人背后（冷却5秒）
                        if player.shadowStep then
                            local canShadow = true
                            if player.shadowStepCd and player.shadowStepCd > 0 then
                                if player._shadowStepCdTimer and player._shadowStepCdTimer > 0 then
                                    canShadow = false
                                end
                            end
                            if canShadow then
                                local fovRange = 210  -- 有效视野半径（像素）
                                local bestSS, bestSD = nil, math.huge
                                for _, oe in ipairs(enemies) do
                                    if oe ~= e and oe.hp > 0 then
                                        local od = math.sqrt((oe.x-player.x)^2+(oe.y-player.y)^2)
                                        if od < fovRange and od < bestSD then bestSD=od; bestSS=oe end
                                    end
                                end
                                if bestSS then
                                    local ba = math.atan(bestSS.y-player.y, bestSS.x-player.x)
                                    player.x = bestSS.x - math.cos(ba) * 28
                                    player.y = bestSS.y - math.sin(ba) * 28
                                    World.ResolveWall(player, 14)
                                    if player.shadowStepCd and player.shadowStepCd > 0 then
                                        player._shadowStepCdTimer = player.shadowStepCd
                                    end
                                end
                            end
                        end
                        -- ⚡ 电磁风暴阈值5：击杀感电目标触发闪电链（限玩家视野内）
                        if player.elecChainExplosion and e.shock and e.shock.stacks > 0 then
                            local fovR2 = fovRadius * fovRadius
                            for _, oe in ipairs(enemies) do
                                if oe ~= e and oe.hp > 0 then
                                    local px2 = oe.x - player.x
                                    local py2 = oe.y - player.y
                                    if px2*px2 + py2*py2 < fovR2 then
                                        StrikeLightning(oe, math.floor(dmg * 0.4), 1, player, enemies)
                                    end
                                end
                            end
                        end
                        player.screenShake = math.max(player.screenShake or 0, e.isBoss and 1.0 or 0.2)
                        table.remove(enemies, i)
                        break
                    end
                end
                ::continue_bullet::
            end
        end
        ::continue_enemy::
    end

    -- 敌人子弹命中玩家
    local PlayerM = require("Player")
    for j = #bullets, 1, -1 do
        local b = bullets[j]
        if b.owner == "enemy" then
            local dx = b.x - player.x
            local dy = b.y - player.y
            if dx*dx + dy*dy < 15*15 then
                PlayerM.ApplyDamage(player, b.dmg, b.x, b.y)
                World.SpawnBlood(player.x, player.y, 3)
                table.remove(bullets, j)
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- 初始化所有敌人
-- ----------------------------------------------------------------------------
function M.InitAll(spawnList, floor)
    M._currentFloor = floor or 1
    local enemies = {}
    local T = World.TILE
    local params = Data.GetFloorParams(floor or 1)
    for _, sp in ipairs(spawnList) do
        -- spawnList 格式：{wx, wy, typeKey}（世界坐标）
        local col = math.floor(sp[1] / T) + 1
        local row = math.floor(sp[2] / T) + 1
        local e = M.New(col, row, sp[3])
        -- 按层数缩放属性
        e.hp     = math.ceil(e.hp * params.hpMult)
        e.maxHp  = e.hp
        e.speed  = e.speed * params.speedMult
        e.damage = math.ceil(e.damage * params.dmgMult)
        -- 预生成战利品（使用该敌人类型专属 dropTable）
        e.loot = {}
        local items = {}
        local tmpl2 = Data.ENEMY_TYPES[sp[3]]
        local dropTbl2 = tmpl2.dropTable or Data.BOX_LOOT_TABLE
        local count = math.random(1, 3)
        for _ = 1, count do
            local t = Data.WeightedRandom(dropTbl2)
            local item = World.GenerateItem(t, tmpl2.dropRarity, floor)
            if item then table.insert(items, item) end
        end
        e.loot = items
        table.insert(enemies, e)
    end
    return enemies
end

-- ----------------------------------------------------------------------------
-- 自动补充（少于MIN_ENEMIES时从地图边缘刷出，Boss层不补充普通敌人）
-- ----------------------------------------------------------------------------
function M.Replenish(enemies, worldMod, hasBossFloor, player, floor)
    -- Boss层不自动补充
    if hasBossFloor then return end
    -- 计算非Boss敌人数量
    local nonBossCount = 0
    for _, e in ipairs(enemies) do
        if not e.isBoss then nonBossCount = nonBossCount + 1 end
    end
    if nonBossCount >= MIN_ENEMIES then return end
    local need = MIN_ENEMIES - nonBossCount

    local T    = worldMod and worldMod.TILE or 40
    local rows = worldMod and worldMod.ROWS or 19
    local cols = worldMod and worldMod.COLS or 24
    -- 玩家格子坐标（用于排除附近格子）
    local pCol = player and math.floor(player.x / T) + 1 or -999
    local pRow = player and math.floor(player.y / T) + 1 or -999
    local MIN_DIST = 8   -- 至少离玩家 8 格

    -- 收集所有有效地板格
    local floorCells = {}
    for r = 1, rows do
        for c = 1, cols do
            if worldMod and worldMod.TileAt(c, r) == 0 then
                local dc = c - pCol
                local dr = r - pRow
                if dc * dc + dr * dr >= MIN_DIST * MIN_DIST then
                    table.insert(floorCells, {c, r})
                end
            end
        end
    end

    local params = Data.GetFloorParams(floor or 1)
    local typeKeys = Data.ENEMY_TYPE_KEYS
    for _ = 1, need do
        local tk = typeKeys[math.random(#typeKeys)]
        if tk == "sniper" then tk = "patrol" end
        local sp = nil
        if #floorCells > 0 then
            sp = floorCells[math.random(#floorCells)]
        end
        if sp then
            local e = M.New(sp[1], sp[2], tk)
            -- 按层数缩放属性
            e.hp     = math.ceil(e.hp * params.hpMult)
            e.maxHp  = e.hp
            e.speed  = e.speed * params.speedMult
            e.damage = math.ceil(e.damage * params.dmgMult)
            e.loot = {}
            table.insert(enemies, e)
        end
    end
end

return M
