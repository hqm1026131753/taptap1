-- ============================================================================
-- Player.lua — 玩家状态、装备系统、背包、射击
-- ============================================================================
local Data      = require("Data")
local World     = require("World")
local Inventory = require("Inventory")
local Search    = require("Search")
local Audio     = require("AudioManager")

local M = {}

-- 前向声明（定义在后面，但在 EquipItem 等函数中使用）
local syncWeaponRef

-- ----------------------------------------------------------------------------
-- 玩家对象初始化
-- ----------------------------------------------------------------------------
function M.New(spawnX, spawnY)
    local T = World.TILE
    local p = {
        x = spawnX or (1.5 * T),
        y = spawnY or (1.5 * T),
        vx = 0, vy = 0,

        -- 属性
        hp        = 100,
        maxHp     = 100,

        -- 当前武器
        weapon    = Data.RandomWeapon(1),  -- 占位，后面会被 p.knife 覆盖
        shootCd     = 0,
        reloadTimer = 0,   -- >0 表示正在装弹，倒计时结束后补满
        aimAngle    = 0,
        facing      = 1,

        -- 装备槽（nil=未装备）
        equip = {
            helmet = nil,
            armor  = nil,
            bag    = nil,
        },

        -- 网格背包（GridInventory，由 Inventory.New 创建）
        -- 初始装备小背包（5×3）
        inventory    = Inventory.New(5, 3),

        -- 统计
        kills     = 0,
        lootValue = 0,  -- 当前背包总价值
        extracting = 0, -- 撤离计时

        -- Build 奖励属性（三选一系统叠加）
        speedMult   = 1.0,   -- 移速倍率（叠乘）
        reloadMult  = 1.0,   -- 装弹速度倍率（叠乘，<1 更快）
        bonusArmor  = 0,     -- 额外护甲（叠加）
        hasLifesteal  = false,
        lifestealPct  = 0,
        hasExplosion  = false,
        doubleShot    = false,

        -- 肾上腺素 buff
        speedBoostTimer = 0,    -- 剩余持续时间（秒）
        speedBoostMult  = 1.0,  -- 加速倍率（正常时 1.0）

        -- 状态
        hitFlash  = 0,
        dead      = false,

        -- 翻滚
        rollTimer   = 0,     -- 翻滚持续计时（>0 表示正在翻滚）
        rollCd      = 0,     -- 冷却剩余（3秒）
        rollDirX    = 0,     -- 翻滚方向 X（单位向量）
        rollDirY    = 0,     -- 翻滚方向 Y
        rollInvincible = false,  -- 翻滚无敌帧标志

        -- 搜索系统（Search 模块状态对象）
        searchState  = Search.New(),

        -- 背包界面开关
        bagOpen      = false,
        -- 搜索面板开关（由 searchState.isOpen 驱动，此处镜像方便渲染）
        searchOpen   = false,
    }

    -- 永久战术刀（不可丢失、不可出售、不掉落）
    p.knife = {
        key="Knife", name="战术刀", icon="🔪",
        damage=20, fireRate=0.40, spread=0, rarity=1, value=0,
        ammo=1, maxAmmo=1, ammoType=nil,
        isMelee=true,   -- 近战标记
        meleeRange=62,  -- 攻击范围（像素）
    }

    -- 武器槽位系统（固定不动，切枪只改 activeSlot）
    p.primaryGun   = nil   -- 主武器槽
    p.secondaryGun = nil   -- 副武器槽
    p.activeSlot   = "knife"  -- 当前选中: "primary" / "secondary" / "knife"
    p.weapon       = p.knife  -- 当前手持（指向 activeSlot 对应武器，射击/渲染用）

    -- 兼容旧引用（Render/Stash 读取 altWeapon）
    p.altWeapon    = nil

    -- 弹药储备 (ammoType key → 总数量)
    -- 4种：light(手枪/冲锋枪) / medium(步枪/机枪) / heavy(霰弹枪) / sniper(狙击枪)
    p.ammoStash = {}

    return p
end

-- ----------------------------------------------------------------------------
-- 护甲减伤公式: damage × (1 - armor/(armor+50))
-- ----------------------------------------------------------------------------
function M.CalcArmorValue(p)
    local v = 0
    if p.equip.helmet then v = v + p.equip.helmet.armor end
    if p.equip.armor  then v = v + p.equip.armor.armor  end
    v = v + (p.bonusArmor or 0)
    return v
end

function M.ApplyDamage(p, rawDmg, srcX, srcY)
    -- Dev God Mode：免疫所有伤害
    local Dev = require("DevSystem")
    if Dev.godMode then return 0 end
    -- 翻滚无敌帧：免疫伤害
    if p.rollInvincible then return 0 end
    -- 战术翻滚无敌窗口（受伤后0.5秒无敌）
    if p.dodgeWindowTimer and p.dodgeWindowTimer > 0 then return 0 end
    -- 残影：移动时20%概率完全闪避
    if p.dodgeWhileMoving and p.isMoving and math.random() < 0.20 then return 0 end
    -- 轻盈：移动时50%概率完全闪避（独立于残影）
    if p.moveDodge and p.moveDodge > 0 and p.isMoving and math.random() < p.moveDodge then return 0 end
    -- ⚡ 雷影步无敌：触发雷电后短暂免疫
    if p.elecDodgeTimer and p.elecDodgeTimer > 0 then return 0 end
    -- 耐久消耗：护甲/头盔各自扣减 rawDmg * 0.5 耐久
    local drain = rawDmg * 0.5
    if p.equip.helmet and p.equip.helmet.durability then
        p.equip.helmet.durability = math.max(0, p.equip.helmet.durability - drain)
    end
    if p.equip.armor and p.equip.armor.durability then
        p.equip.armor.durability = math.max(0, p.equip.armor.durability - drain)
    end

    -- 耐久归零的装备不提供护甲值
    local armor = 0
    if p.equip.helmet then
        local dur = p.equip.helmet.durability
        if dur == nil or dur > 0 then
            armor = armor + (p.equip.helmet.armor or 0)
        end
    end
    if p.equip.armor then
        local dur = p.equip.armor.durability
        if dur == nil or dur > 0 then
            armor = armor + (p.equip.armor.armor or 0)
        end
    end
    armor = armor + (p.bonusArmor or 0)

    local actual = rawDmg * (1 - armor / (armor + 50))
    -- 铁壁：HP < 30% 时减伤 50%
    if p.lastStand and p.hp <= p.maxHp * 0.30 then
        actual = actual * 0.5
    end
    actual = math.max(1, math.floor(actual + 0.5))
    -- 固定减伤（铁皮 / 轻装备）：扣减后保证至少造成 1 点伤害
    if p.damageReduction and p.damageReduction > 0 then
        actual = math.max(1, actual - p.damageReduction)
    end
    -- 能量护盾：先吸收伤害
    if p.shieldHp and p.shieldHp > 0 then
        local absorbed = math.min(p.shieldHp, actual)
        p.shieldHp = p.shieldHp - absorbed
        actual = actual - absorbed
        -- 护盾耗尽：重新开始充能倒计时
        if p.shieldHp <= 0 then
            p.shieldRechargeTimer = 30.0
        end
    end
    if actual <= 0 then return 0 end
    p.hp = p.hp - actual
    p.hitFlash = 0.25
    p.hitShake = 0.2  -- 视觉晃动持续时间
    -- 微击退
    if srcX and srcY then
        local dx = p.x - srcX
        local dy = p.y - srcY
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 1 then
            local knockDist = 6
            p.x = p.x + (dx / dist) * knockDist
            p.y = p.y + (dy / dist) * knockDist
            local World = require("World")
            World.ResolveWall(p, 14)
        end
    end
    -- 战术翻滚：受伤后触发无敌窗口
    if p.dodgeWindow and p.dodgeWindow > 0 then
        p.dodgeWindowTimer = p.dodgeWindow
    end
    if p.hp <= 0 then
        -- 技能树额外生命：消耗一条命，保留1HP并后撤
        if p.extraLives and p.extraLives > 0 then
            p.extraLives = p.extraLives - 1
            p.hp = 1
            if p.aimAngle then
                p.x = p.x - math.cos(p.aimAngle) * 60
                p.y = p.y - math.sin(p.aimAngle) * 60
                World.ResolveWall(p, 14)
            end
        -- 不死猫：一局只触发一次，保留1HP并后撤
        elseif p.cheatDeath and not p.cheatDeathUsed then
            p.hp = 1
            p.cheatDeathUsed = true
            -- 后撤：朝反向推开 60px
            if p.aimAngle then
                p.x = p.x - math.cos(p.aimAngle) * 60
                p.y = p.y - math.sin(p.aimAngle) * 60
                World.ResolveWall(p, 14)
            end
        else
            p.hp = 0
            p.dead = true
        end
    end
    return actual
end

-- ----------------------------------------------------------------------------
-- 当前弹药上限
-- ----------------------------------------------------------------------------
-- 根据装备的包更新背包大小（保留已有物品）
function M.UpdateBagSize(p)
    local sizeKey = Inventory.BagSizeKey(p.equip.bag)
    local sz = Inventory.BAG_SIZES[sizeKey]
    local inv = p.inventory
    -- 如果尺寸已匹配，不需要重建
    if inv.width == sz.w and inv.height == sz.h then return end
    local newInv, overflow = Inventory.Resize(inv, sz.w, sz.h)
    p.inventory = newInv
    -- 缩包时放不下的物品掉落在脚边（绝不丢失）
    if overflow and #overflow > 0 then
        for _, item in ipairs(overflow) do
            World.drops[#World.drops + 1] = {
                x = p.x + math.random(-18, 18),
                y = p.y + math.random(-18, 18),
                item   = item,
                picked = false,
                nopickTimer = 0.8,
            }
        end
        p.notification = { text = #overflow .. " 件物品掉落在脚下", timer = 1.5 }
    end
end


-- ----------------------------------------------------------------------------
-- 拾取物品到背包（武器/装备自动比较更换）
-- ----------------------------------------------------------------------------
function M.PickupItem(p, item)
    local itype = item.itype

    -- 武器：优先填空槽，再比较稀有度决定替换
    if itype == "weapon" then
        local newW = item.data

        -- 辅助：枪放不进背包时落地，绝不丢失
        local function dropIfFull(gun)
            if not gun or gun.key == "Knife" then return end
            local old = { itype="weapon", data=gun, name=gun.name, icon="🔫", rarity=gun.rarity, value=gun.value }
            local ok = M.AddToInventory(p, old)
            if not ok then
                World.drops[#World.drops + 1] = {
                    x = p.x + math.random(-18, 18),
                    y = p.y + math.random(-18, 18),
                    item   = old,
                    picked = false,
                    nopickTimer = 0.8,  -- 短暂冷却，防止落地后立即被自动拾取导致死循环
                }
                p.notification = { text = gun.name .. " 掉落在脚下", timer = 1.5 }
            end
        end

        -- 主武器槽空：放入主武器槽并选中
        if not p.primaryGun then
            p.primaryGun = newW
            p.activeSlot = "primary"
            syncWeaponRef(p)
            p.reloadTimer = 0
            p.notification = { text = "装备: " .. newW.name, timer = 1.2 }
            return true
        end

        -- 副武器槽空：放入副武器槽（不切换选中）
        if not p.secondaryGun then
            p.secondaryGun = newW
            syncWeaponRef(p)
            p.notification = { text = "备用: " .. newW.name, timer = 1.2 }
            return true
        end

        -- 两槽都有武器：替换当前选中槽位的武器（掉落旧的）
        if p.activeSlot == "primary" or p.activeSlot == "knife" then
            if newW.rarity > p.primaryGun.rarity then
                local old = p.primaryGun
                p.primaryGun = newW
                p.activeSlot = "primary"
                syncWeaponRef(p)
                p.reloadTimer = 0
                p.notification = { text = "装备: " .. newW.name, timer = 1.2 }
                dropIfFull(old)
                return true
            elseif newW.rarity > p.secondaryGun.rarity then
                local old = p.secondaryGun
                p.secondaryGun = newW
                syncWeaponRef(p)
                p.notification = { text = "备用: " .. newW.name, timer = 1.2 }
                dropIfFull(old)
                return true
            end
        else -- activeSlot == "secondary"
            if newW.rarity > p.secondaryGun.rarity then
                local old = p.secondaryGun
                p.secondaryGun = newW
                syncWeaponRef(p)
                p.reloadTimer = 0
                p.notification = { text = "装备: " .. newW.name, timer = 1.2 }
                dropIfFull(old)
                return true
            elseif newW.rarity > p.primaryGun.rarity then
                local old = p.primaryGun
                p.primaryGun = newW
                syncWeaponRef(p)
                p.notification = { text = "主武器: " .. newW.name, timer = 1.2 }
                dropIfFull(old)
                return true
            end
        end
        -- 新枪不如现有武器：尝试放包
        local ok = M.AddToInventory(p, item)
        return ok
    end

    -- 装备槽（头盔/护甲/背包）：自动换更高稀有度
    local equipMap = { helmet="helmet", armor="armor", bag="bag" }
    local slot = equipMap[itype]
    if slot then
        local cur = p.equip[slot]
        if not cur or item.data.rarity > cur.rarity then
            if cur then
                -- 旧装备放入背包（放不下就丢弃，但不影响新装备穿戴）
                M.AddToInventory(p, { itype=slot, data=cur, value=cur.value, name=cur.name, icon=cur.icon, rarity=cur.rarity })
            end
            p.equip[slot] = item.data
            -- 装备背包时重建网格
            if slot == "bag" then M.UpdateBagSize(p) end
            return true
        else
            -- 同级或更低装备：必须放得进背包才拿
            return M.AddToInventory(p, item)
        end
    end

    -- 急救包：直接使用
    if itype == "loot" and item.data.type == "medkit" then
        p.hp = math.min(p.maxHp, p.hp + item.data.heal)
        World.SpawnPickup(p.x, p.y)
        return true
    end

    -- 消耗品：ammo 类型直接存入 ammoStash，其余放入背包
    if itype == "consumable" then
        if item.data and item.data.effectType == "ammo" then
            local atype = item.data.ammoType
            local cnt   = item.data.ammoCount or item.data.count or 0
            -- 搜弹手：额外获得弹药
            if p.bonusAmmoPickup and p.bonusAmmoPickup > 0 then
                cnt = cnt + p.bonusAmmoPickup
            end
            if atype then
                p.ammoStash = p.ammoStash or {}
                p.ammoStash[atype] = (p.ammoStash[atype] or 0) + cnt
                p.notification = { text = "+" .. cnt .. " " .. (item.data.name or "子弹"), timer = 1.2 }
                return true
            end
        end
        return M.AddToInventory(p, item)
    end

    -- 普通战利品：加入背包
    return M.AddToInventory(p, item)
end

function M.AddToInventory(p, item)
    local placed = Inventory.AutoPlace(p.inventory, item)
    if not placed then
        -- 直接放不下时，先整理背包再重试一次
        Inventory.AutoSort(p.inventory)
        placed = Inventory.AutoPlace(p.inventory, item)
        if not placed then return false end
    end
    p.lootValue = Inventory.TotalValue(p.inventory)
    return true
end

-- ----------------------------------------------------------------------------
-- 射击
-- ----------------------------------------------------------------------------
local RELOAD_TIME_DEFAULT = 1.5  -- 备用装弹时间（秒，新数据均有 reloadTime 字段）

---返回实际可取弹的 ammoType key
local function resolveAmmoKey(ammoStash, atype)
    if not atype then return nil end
    return atype
end

-- 默认近战武器（弹药耗尽时自动切换）
local MELEE_WEAPON = {
    key="Knife", name="战术刀", icon="🔪",
    damage=20, fireRate=0.45, spread=0, rarity=1, value=0,
    ammo=1, maxAmmo=1, ammoType=nil,  -- nil = 无限/近战，不消耗 ammoStash
}

-- 内部辅助：尝试将枪械存入背包；背包满则落地（不丢失）
stashGun = function(p, gun)
    if not gun or gun.key == "Knife" then return end
    local item = { itype="weapon", data=gun, name=gun.name, icon="🔫", rarity=gun.rarity, value=gun.value }
    local ok = M.AddToInventory(p, item)
    if not ok then
        World.drops[#World.drops + 1] = {
            x = p.x + math.random(-18, 18),
            y = p.y + math.random(-18, 18),
            item   = item,
            picked = false,
            nopickTimer = 0.8,
        }
    end
end

-- 同步 p.weapon / p.altWeapon 指向（根据 activeSlot 刷新）
syncWeaponRef = function(p)
    if p.activeSlot == "primary" then
        p.weapon = p.primaryGun or p.knife
    elseif p.activeSlot == "secondary" then
        p.weapon = p.secondaryGun or p.knife
    else
        p.weapon = p.knife
    end
    -- altWeapon 兼容：指向"非当前手持"的那把枪（Render 武器槽显示用）
    if p.activeSlot == "primary" then
        p.altWeapon = p.secondaryGun
    elseif p.activeSlot == "secondary" then
        p.altWeapon = p.primaryGun
    else
        p.altWeapon = p.secondaryGun or p.primaryGun
    end
end
M.syncWeaponRef = syncWeaponRef

-- Q 键：槽位循环选中（武器不移动，只切换选中哪个槽）
function M.SwapWeapon(p)
    if p.dead then return end
    -- 构建可选槽位列表（跳过空槽）
    local slots = {}
    if p.primaryGun   then slots[#slots+1] = "primary" end
    if p.secondaryGun then slots[#slots+1] = "secondary" end
    slots[#slots+1] = "knife"  -- 刀永远可选

    -- 找到当前槽位在列表中的索引，切到下一个
    local curIdx = 1
    for i, s in ipairs(slots) do
        if s == p.activeSlot then curIdx = i; break end
    end
    local nextIdx = (curIdx % #slots) + 1
    p.activeSlot = slots[nextIdx]

    syncWeaponRef(p)
    p.reloadTimer  = 0
    p.shootCd      = 0
    p.jammed       = false  -- 切枪清除卡弹状态
    p.weapon_slot1 = nil  -- 清理旧寄存逻辑
    p.weapon_slot2 = nil
    p.notification = { text = "切换: " .. p.weapon.name, timer = 1.0 }
end



function M.SwitchToMelee(p)
    -- 将所有武器槽的枪械存入背包（满则落地，绝不丢失）
    stashGun(p, p.primaryGun)
    stashGun(p, p.secondaryGun)
    -- 清空所有武器槽，切换到永久刀
    p.primaryGun   = nil
    p.secondaryGun = nil
    p.activeSlot   = "knife"
    p.altWeapon    = nil
    p.weapon_slot1 = nil
    p.weapon_slot2 = nil
    p.weapon       = p.knife
    p.reloadTimer  = 0
    p.notification = { text = "弹药耗尽！切换近战", timer = 2.0 }
end

local function startReload(p)
    if p.reloadTimer > 0 then return end          -- 已在装弹
    if p.weapon.ammo >= p.weapon.maxAmmo then return end  -- 无需装弹

    -- 近战武器（无 ammoType）：不需要装弹
    local atype = p.weapon.ammoType
    if not atype then return end

    -- 检查 ammoStash（考虑 smg→pistol 别名）
    local realKey = resolveAmmoKey(p.ammoStash or {}, atype)
    local avail = (p.ammoStash and p.ammoStash[realKey]) or 0
    if avail <= 0 then
        -- 弹药储备耗尽 → 卡弹，不自动切枪/切刀，需要玩家手动管理
        p.jammed = true
        p.notification = { text = "弹药耗尽！按Q切换武器或打开背包整理", timer = 2.5 }
        return
    end

    -- 记录本次实际消耗的弹药 key（别名解析后），装弹完成时使用
    p.reloadAmmoKey = realKey

    local base = p.weapon.reloadTime or RELOAD_TIME_DEFAULT
    -- 逐发装弹（霰弹枪 reloadPerShell）：每发用 reloadTime，装完后自动循环
    p.reloadPerShell = p.weapon.reloadPerShell == true
    p.reloadTimer = base * (p.reloadMult or 1.0)
end

function M.TryShoot(p, bullets)
    if p.dead        then return end
    if p.shootCd > 0 then return end
    -- 逐发装弹（reloadPerShell）：弹匣有弹时射击可打断装弹
    if p.reloadTimer > 0 then
        if p.reloadPerShell and p.weapon.ammo > 0 then
            p.reloadTimer    = 0
            p.reloadPerShell = false
            p.reloadAmmoKey  = nil
        else
            return
        end
    end

    -- 近战武器（战术刀）：范围攻击，不发子弹
    if p.weapon.isMelee then
        p.shootCd = p.weapon.fireRate
        local range  = p.weapon.meleeRange or 62
        -- knifeArmorDmg：每10护甲+8%近战伤害
        local armorBonus = 1.0
        if p.knifeArmorDmg then
            local armor = M.CalcArmorValue(p)
            armorBonus = 1.0 + math.floor(armor / 10) * 0.08
        end
        -- 刀甲联动：每10护甲+5%近战伤害
        if p.bladeArmor then
            local armor = M.CalcArmorValue(p)
            armorBonus = armorBonus + math.floor(armor / 10) * 0.05
        end
        local damage = p.weapon.damage * armorBonus
        -- 技能树伤害加成
        if p.skillDmgBonus and p.skillDmgBonus > 0 then
            damage = damage * (1 + p.skillDmgBonus)
        end
        -- knifeAoe：横扫范围（无方向限制）
        local aoeRange = (p.knifeAoe and (p.knifeAoeRadius or 60)) or 0

        -- 攻击方向
        local nx = math.cos(p.aimAngle)
        local ny = math.sin(p.aimAngle)

        -- 获取当前所有敌人（通过 World 挂载的全局引用）
        local enemies = World._currentEnemies
        if enemies then
            for i = #enemies, 1, -1 do
                local e = enemies[i]
                if e.hp and e.hp > 0 then
                    local dx = e.x - p.x
                    local dy = e.y - p.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local inMain = dist <= range
                    local inAoe  = aoeRange > 0 and dist <= aoeRange
                    if inMain or inAoe then
                        -- AOE 全方向命中；主攻方向检查前方扇面
                        local hit = false
                        if inAoe then
                            hit = true
                        elseif dist < 24 then
                            hit = true
                        else
                            local dot = (dx * nx + dy * ny) / dist
                            hit = dot >= -0.26   -- cos(105°) ≈ -0.26，覆盖约 210° 扇面
                        end
                        if hit then
                            -- 一刀两断：对满血敌人必定秒杀（Boss无效）
                            local actualDmg = 0
                            if p.knifeOneshot and not e.isBoss and e.hp >= e.maxHp then
                                actualDmg = e.hp
                                e.hp = 0
                            else
                                actualDmg = damage * (1 - (e.armor or 0) / ((e.armor or 0) + 50))
                                e.hp = e.hp - actualDmg
                            end
                            e.hitFlash = 0.12
                            -- 伤害数字粒子
                            World.SpawnDmgPopup(e.x, e.y, math.floor(actualDmg), false)
                            -- 淬毒刀锋：命中附带3秒中毒
                            if p.knifePoison and e.hp > 0 then
                                e.poisonTimer = 3.0
                                e.poisonDps   = math.max(1, math.floor(damage * 0.15))
                            end
                            if e.hp <= 0 then
                                Audio.PlayEnemyDie()
                                World.SpawnBlood(e.x, e.y, 12)
                                if #e.loot > 0 then
                                    World.SpawnCorpse(e.x, e.y, e.loot, e.name, e.isBoss)
                                end
                                p.kills = p.kills + 1
                                if p.hasLifesteal then
                                    local heal = math.floor(p.maxHp * (p.lifestealPct or 0.08))
                                    p.hp = math.min(p.maxHp, p.hp + heal)
                                end
                                -- 嗜血：近战击杀回复HP
                                if p.knifeHealOnKill and p.knifeHealOnKill > 0 then
                                    local kHeal = math.max(1, math.floor(p.maxHp * p.knifeHealOnKill))
                                    p.hp = math.min(p.maxHp, p.hp + kHeal)
                                end
                                -- 吸血注射（vampirePct）：击杀回复HP（tank流）
                                if p.vampirePct and p.vampirePct > 0 then
                                    local vHeal = math.max(1, math.floor(p.maxHp * p.vampirePct))
                                    p.hp = math.min(p.maxHp, p.hp + vHeal)
                                end
                                -- 无限火力：击杀后3秒免弹药
                                if p.ammoFreeOnKill then p.ammoFreeTimer = 3.0 end
                                -- 暗影步：击杀后闪烁到视野范围内另一个敌人背后（冷却5秒）
                                if p.shadowStep then
                                    local canShadow = true
                                    if p.shadowStepCd and p.shadowStepCd > 0 then
                                        if p._shadowStepCdTimer and p._shadowStepCdTimer > 0 then
                                            canShadow = false
                                        end
                                    end
                                    if canShadow then
                                        local fovRange = 210  -- 有效视野半径（像素）
                                        local best, bestDist = nil, math.huge
                                        for _, oe in ipairs(enemies) do
                                            if oe ~= e and oe.hp > 0 then
                                                local od = math.sqrt((oe.x-p.x)^2+(oe.y-p.y)^2)
                                                if od < fovRange and od < bestDist then bestDist=od; best=oe end
                                            end
                                        end
                                        if best then
                                            local ba = math.atan(best.y-p.y, best.x-p.x)
                                            p.x = best.x - math.cos(ba) * 28
                                            p.y = best.y - math.sin(ba) * 28
                                            World.ResolveWall(p, 14)
                                            if p.shadowStepCd and p.shadowStepCd > 0 then
                                                p._shadowStepCdTimer = p.shadowStepCd
                                            end
                                        end
                                    end
                                end
                                table.remove(enemies, i)
                            end
                        end
                    end
                end
            end
        end

        -- knifeParry：挥刀时清除/反弹附近敌方子弹
        if p.knifeParry and bullets then
            local parried = false
            for j = #bullets, 1, -1 do
                local b = bullets[j]
                if b.owner == "enemy" then
                    local bx = b.x - p.x
                    local by = b.y - p.y
                    if bx*bx + by*by <= range * range then
                        parried = true
                        if p.knifeReflect then
                            -- 反弹：改为玩家子弹并反向
                            b.owner = "player"
                            b.vx = -b.vx
                            b.vy = -b.vy
                        else
                            table.remove(bullets, j)
                        end
                    end
                end
            end
            -- knifeRageOnParry：成功格挡后获得3秒冲刺加速
            if parried and p.knifeRageOnParry then
                p.speedBoostMult  = 2.0
                p.speedBoostTimer = 3.0
            end
        end

        -- 刀砍特效：沿攻击方向生成刀光粒子
        Audio.PlayWeaponFire(p.weapon.name)
        World.SpawnKnifeSlash(p.x, p.y, p.aimAngle, range)

        -- 剑气斩：发射远程剑气波（穿透飞行）
        if p.knifeSlashWave and bullets then
            local sa  = p.aimAngle
            local snx = math.cos(sa)
            local sny = math.sin(sa)
            bullets[#bullets + 1] = {
                x          = p.x + snx * (range * 0.6),
                y          = p.y + sny * (range * 0.6),
                vx         = snx * 380,
                vy         = sny * 380,
                owner      = "player",
                dmg        = math.floor(p.weapon.damage * 0.65),
                life       = 0.9,
                maxLife    = 0.9,
                isSlashWave = true,
                hitEnemies  = {},   -- 穿透标记：记录已伤害的敌人
                angle       = sa,
            }
            World.SpawnKnifeSlash(p.x + snx * (range * 0.6), p.y + sny * (range * 0.6), sa, 28)
        end
        return
    end

    if p.weapon.ammo <= 0 then
        if p.infiniteAmmo then
            -- 无限弹药：静默补满，不触发装弹音效
            p.weapon.ammo = p.weapon.maxAmmo
        else
            -- 卡弹：播放卡弹音效，尝试装弹（无储备则标记 jammed）
            Audio.PlayJammed()
            p.shootCd = p.weapon.fireRate * 0.6  -- 卡弹间隔略短，给玩家反馈感
            startReload(p)
            return
        end
    end

    Audio.PlayWeaponFire(p.weapon.name)
    p.shootCd = p.weapon.fireRate
    -- 后坐力视觉效果（重武器更强）
    if p.weapon.ammoType == "sniper" or p.weapon.pellets then
        p.recoilTimer = 2.5  -- 狙击枪 / 霰弹枪
    elseif p.weapon.ammoType == "medium" and (p.weapon.magSize or 0) >= 50 then
        p.recoilTimer = 1.8  -- 重机枪
    elseif p.weapon.ammoType == "medium" then
        p.recoilTimer = 1.6  -- 步枪
    else
        p.recoilTimer = 1.0
    end
    -- 无限火力：免弹药消耗（infiniteAmmo 或 ammoFreeTimer 均豁免）
    if not (p.ammoFreeTimer and p.ammoFreeTimer > 0) and not p.infiniteAmmo then
        p.weapon.ammo = p.weapon.ammo - 1
    end

    -- 射击方向：有锁定目标则朝目标，否则按 aimAngle 自由射击
    local nx, ny
    local target = p.lockTarget
    if target and target.hp > 0 then
        local dx  = target.x - p.x
        local dy  = target.y - p.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1 then len = 1 end
        nx = dx / len
        ny = dy / len
    else
        nx = math.cos(p.aimAngle)
        ny = math.sin(p.aimAngle)
    end

    -- 枪口：沿方向偏移，锁定到枪图尖端
    local muzzleOffset = 12
    if p.weapon then
        if p.weapon.slot == "secondary" then
            muzzleOffset = 23       -- 手枪 24px
        elseif p.weapon.ammoType == "sniper" then
            muzzleOffset = 63       -- 狙击枪 64px
        elseif p.weapon.pellets then
            muzzleOffset = 43       -- 霰弹枪 44px
        elseif p.weapon.ammoType == "medium" and (p.weapon.magSize or 0) >= 50 then
            muzzleOffset = 55       -- 重机枪 56px
        elseif p.weapon.ammoType == "medium" then
            muzzleOffset = 47       -- 步枪 48px
        else
            muzzleOffset = 31       -- 冲锋枪 32px
        end
    end
    local muzzleX = p.x + nx * muzzleOffset
    local muzzleY = p.y + ny * muzzleOffset

    local SPEED   = 500
    -- 狙击枪子弹更快
    if p.weapon.ammoType == "sniper" then SPEED = 800 end
    local spread  = p.weapon.spread  or 0
    -- 技能树散布减少
    if p.skillSpreadReduction and p.skillSpreadReduction > 0 then
        spread = spread * (1 - p.skillSpreadReduction)
    end
    local pellets = p.weapon.pellets or 1
    local shots   = p.doubleShot and (pellets + 1) or pellets
    -- 技能树远程伤害加成
    local baseDmg = p.weapon.damage
    if p.skillDmgBonus and p.skillDmgBonus > 0 then
        baseDmg = baseDmg * (1 + p.skillDmgBonus)
    end

    -- 确定子弹视觉类型
    local bType = "smg"  -- 默认冲锋枪
    if p.weapon.ammoType == "sniper" then
        bType = "sniper"
    elseif p.weapon.pellets then
        bType = "shotgun"
    elseif p.weapon.ammoType == "medium" and (p.weapon.magSize or 0) >= 50 then
        bType = "hmg"
    elseif p.weapon.ammoType == "medium" then
        bType = "rifle"
    elseif p.weapon.slot == "secondary" then
        bType = "pistol"
    end

    for _ = 1, shots do
        local angle = math.atan(ny, nx)
        if spread > 0 then
            angle = angle + (math.random() - 0.5) * spread * 2
        end
        -- 暴击判定（技能树）
        local finalDmg = baseDmg
        local isCrit = false
        if p.skillCritChance and p.skillCritChance > 0 and math.random() < p.skillCritChance then
            isCrit = true
            finalDmg = finalDmg * (1.5 + (p.skillCritDmg or 0))
        end
        bullets[#bullets + 1] = {
            x     = muzzleX,
            y     = muzzleY,
            vx    = math.cos(angle) * SPEED,
            vy    = math.sin(angle) * SPEED,
            owner = "player",
            dmg   = finalDmg,
            life  = 1.2,
            wtype = bType,
            crit  = isCrit,
        }
    end

    local fireAngle = math.atan(ny, nx)
    World.SpawnMuzzleFlash(muzzleX, muzzleY, fireAngle, bType)

    -- 屏幕震动：根据武器类型设定强度（像素）
    local shakeIntensity = 1.5  -- 默认冲锋枪/手枪
    if p.weapon.ammoType == "sniper" then
        shakeIntensity = 6.0
    elseif p.weapon.pellets then
        shakeIntensity = 3.5    -- 霰弹枪
    elseif p.weapon.ammoType == "medium" and (p.weapon.magSize or 0) >= 50 then
        shakeIntensity = 2.5    -- 重机枪
    elseif p.weapon.ammoType == "medium" then
        shakeIntensity = 2.0    -- 步枪
    end
    p.screenShake = math.max(p.screenShake or 0, shakeIntensity)
end

-- R 键手动触发装弹（改为计时装弹）
function M.Reload(p)
    if p.dead then return end
    startReload(p)
end

---返回当前武器的有效弹药储备数量（考虑 smg→pistol 别名）
---供 HUD 显示使用
---@param p table
---@return number|nil  nil 表示无弹药类型（近战）
function M.GetStashCount(p)
    if not p.weapon or not p.weapon.ammoType then return nil end
    if not p.ammoStash then return 0 end
    local realKey = resolveAmmoKey(p.ammoStash, p.weapon.ammoType)
    return p.ammoStash[realKey] or 0
end

-- ----------------------------------------------------------------------------
-- 医疗快捷栏（右下角 UI）
-- ----------------------------------------------------------------------------

-- 返回最多 3 个医疗格，按种类分组
-- 每格：{ id, icon, name, data, count, rarity }
function M.GetMedSlots(p)
    local groups     = {}   -- id → group table
    local groupOrder = {}   -- 保持插入顺序

    local function scanInv(inv)
        if not inv then return end
        for _, entry in ipairs(inv.items) do
            if entry.itype == "consumable" and entry.data
               and entry.data.effectType == "heal" then
                local gid = entry.data.id or entry.data.name or "?"
                if not groups[gid] then
                    if #groupOrder >= 3 then break end
                    groups[gid] = {
                        id     = gid,
                        icon   = entry.icon or "💊",
                        name   = entry.data.name or "?",
                        data   = entry.data,
                        count  = 0,
                        rarity = entry.rarity or 1,
                    }
                    table.insert(groupOrder, gid)
                end
                groups[gid].count = groups[gid].count + 1
            end
        end
    end

    scanInv(p.inventory)

    local result = {}
    for _, gid in ipairs(groupOrder) do
        table.insert(result, groups[gid])
    end
    return result
end

-- ----------------------------------------------------------------------------
-- 医疗前摇系统
-- medCast: { timer, duration, slotIdx, entryId, inv, data }
-- ----------------------------------------------------------------------------

-- 判断当前是否正在使用医疗品
function M.IsCasting(p)
    return p.medCast ~= nil
end

-- 取消当前前摇（不消耗物品，不回血）
function M.CancelMedCast(p)
    if p.medCast then
        p.medCast = nil
        p.notification = { text = "使用中断", timer = 1.0 }
    end
end

-- 内部：开始前摇
local function startMedCast(p, entry, inv, slotIdx)
    -- 若已在使用同一物品，不重复触发
    if p.medCast and p.medCast.entryId == entry.id then return true end
    -- 打断旧前摇（换了物品）
    p.medCast = nil

    local c    = entry.data
    local dur  = c.useTime or 1.5
    -- 技能树医疗加速（healBoost 缩短前摇）
    if p.skillHealBoost and p.skillHealBoost > 0 then
        dur = dur / (1 + p.skillHealBoost)
    end
    p.medCast  = {
        timer    = dur,
        duration = dur,
        entryId  = entry.id,
        inv      = inv,
        data     = c,
        slotIdx  = slotIdx,
    }
    p.notification = { text = "使用 " .. (c.name or "?") .. "…", timer = dur + 0.2 }
    return true
end

-- 每帧更新前摇（由 main.lua 调用）
function M.UpdateMedCast(p, dt)
    local cast = p.medCast
    if not cast then return end

    -- 受到攻击时中断（hitFlash 刚被设置说明本帧刚受伤）
    if p.hitFlash and p.hitFlash > 0.20 then
        p.medCast = nil
        p.notification = { text = "受击中断！", timer = 1.0 }
        return
    end

    cast.timer = cast.timer - dt
    if cast.timer > 0 then return end

    -- 前摇完成 → 实际应用效果
    p.medCast = nil
    local c   = cast.data
    local inv = cast.inv

    -- 从背包移除/扣减1个（堆叠物品只消耗1个）
    local found = false
    for _, entry in ipairs(inv.items) do
        if entry.id == cast.entryId then
            Inventory.RemoveItem(inv, entry.id, 1)
            found = true
            break
        end
    end
    if not found then
        p.notification = { text = "物品已丢失", timer = 1.2 }
        return
    end

    -- 回血（技能树 healBoost 增加回复量）
    local healMult = 1 + (p.skillHealBoost or 0)
    local heal = math.floor((c.healPct or 0) * p.maxHp * healMult)
    p.hp = math.min(p.maxHp, p.hp + heal)
    Audio.PlayHeal()

    -- 速度 buff
    if c.speedBoost and c.speedBoost > 1.0 then
        p.speedBoostMult  = c.speedBoost
        p.speedBoostTimer = c.speedDuration or 5.0
    end

    p.notification = { text = "+" .. heal .. " HP  " .. (c.name or ""), timer = 2.0 }

    -- 使用闪光
    p.medUseFlash             = p.medUseFlash or {}
    p.medUseFlash[cast.slotIdx] = 0.4
end

-- 使用第 idx 个医疗格（1-based）；返回 true/false
function M.UseMedSlot(p, idx)
    if p.dead then return false end
    -- 若已在施法，再按同键则取消
    if p.medCast and p.medCast.slotIdx == idx then
        M.CancelMedCast(p)
        return false
    end

    local slots = M.GetMedSlots(p)
    local slot  = slots[idx]
    if not slot then
        p.notification = { text = "格子 " .. idx .. " 无药品", timer = 1.0 }
        return false
    end

    local targetId = slot.id
    local function tryFrom(inv)
        if not inv then return false end
        for _, entry in ipairs(inv.items) do
            if entry.itype == "consumable" and entry.data
               and entry.data.effectType == "heal"
               and (entry.data.id or entry.data.name or "?") == targetId then
                return startMedCast(p, entry, inv, idx)
            end
        end
        return false
    end

    if tryFrom(p.inventory) then return true end
    return false
end

-- ----------------------------------------------------------------------------
-- 消耗品使用（F 键触发）
-- ----------------------------------------------------------------------------

-- 在背包中查找第一个 effectType=="heal" 的消耗品并使用
-- 返回 true（使用成功）或 false
function M.UseFirstConsumable(p)
    if p.dead then return false end

    -- 若已在施法，F 键取消
    if p.medCast then
        M.CancelMedCast(p)
        return false
    end

    local function tryUseFrom(inv)
        if not inv then return false end
        for _, entry in ipairs(inv.items) do
            if entry.itype == "consumable" and entry.data.effectType == "heal" then
                return startMedCast(p, entry, inv, 0)   -- slotIdx=0 表示 F 键
            end
        end
        return false
    end

    if tryUseFrom(p.inventory) then return true end

    p.notification = { text = "没有可用消耗品", timer = 1.2 }
    return false
end

-- ----------------------------------------------------------------------------
-- Buff 更新（每帧由 Update 调用）
-- ----------------------------------------------------------------------------
local function UpdateBuffs(p, dt)
    if p.speedBoostTimer > 0 then
        p.speedBoostTimer = p.speedBoostTimer - dt
        if p.speedBoostTimer <= 0 then
            p.speedBoostTimer = 0
            p.speedBoostMult  = 1.0
        end
    end
    -- 医疗格使用闪光衰减
    if p.medUseFlash then
        for i, t in pairs(p.medUseFlash) do
            p.medUseFlash[i] = t - dt
            if p.medUseFlash[i] <= 0 then p.medUseFlash[i] = nil end
        end
    end
end

-- ----------------------------------------------------------------------------
-- 更新
-- ----------------------------------------------------------------------------
-- 翻滚常量
local ROLL_DURATION  = 0.32   -- 翻滚持续时长（秒）
local ROLL_SPEED     = 320    -- 翻滚移速（像素/秒）
local ROLL_INVINCIBLE_END = 0.26  -- 无敌帧结束时间（从翻滚开始计）
local ROLL_COOLDOWN  = 2.5    -- 冷却时间（秒）

-- 触发翻滚（由 main.lua 的 Shift 键调用）
function M.TryRoll(p, keys)
    if p.dead then return false end
    if p.rollTimer > 0 then return false end  -- 正在翻滚
    if p.rollCd > 0 then return false end     -- 冷却中
    if M.IsCasting(p) then return false end   -- 使用医疗中

    -- 翻滚方向：优先当前移动键，否则用面朝方向（aimAngle）
    local dx, dy = 0, 0
    if keys.w then dy = dy - 1 end
    if keys.s then dy = dy + 1 end
    if keys.a then dx = dx - 1 end
    if keys.d then dx = dx + 1 end
    if dx == 0 and dy == 0 then
        -- 无移动输入：沿面朝方向翻滚
        dx = math.cos(p.aimAngle)
        dy = math.sin(p.aimAngle)
    elseif dx ~= 0 and dy ~= 0 then
        dx = dx * 0.707; dy = dy * 0.707
    end

    p.rollTimer      = ROLL_DURATION
    -- 翻滚CD：支持 noRollCd（无CD）和 rollCdReduction（减少秒数）
    if p.noRollCd then
        p.rollCd = 0
    else
        p.rollCd = math.max(0, ROLL_COOLDOWN - (p.rollCdReduction or 0))
    end
    p.rollDirX       = dx
    p.rollDirY       = dy
    p.rollInvincible = true
    return true
end

function M.Update(p, dt, keys, bullets)
    if p.dead then return end

    -- Buff 倒计时（肾上腺素等）
    UpdateBuffs(p, dt)

    -- 战术翻滚无敌窗口倒计时
    if p.dodgeWindowTimer and p.dodgeWindowTimer > 0 then
        p.dodgeWindowTimer = p.dodgeWindowTimer - dt
        if p.dodgeWindowTimer < 0 then p.dodgeWindowTimer = 0 end
    end

    -- 能量护盾充能倒计时
    if p.shieldMax and p.shieldMax > 0 then
        if p.shieldRechargeTimer and p.shieldRechargeTimer > 0 then
            p.shieldRechargeTimer = p.shieldRechargeTimer - dt
            if p.shieldRechargeTimer <= 0 then
                p.shieldRechargeTimer = 0
                p.shieldHp = p.shieldMax   -- 护盾充满
            end
        elseif (not p.shieldHp or p.shieldHp <= 0) and (not p.shieldRechargeTimer or p.shieldRechargeTimer <= 0) then
            -- 护盾为0且没有充能倒计时：开始充能（首次获得护盾时也会触发）
            p.shieldRechargeTimer = 30.0
        end
    end

    -- HP 自动回复（regenPct：每5秒回复 regenPct*maxHp 点血量）
    if p.regenPct and p.regenPct > 0 and p.hp < p.maxHp then
        p.regenTimer = (p.regenTimer or 0) + dt
        if p.regenTimer >= 5.0 then
            p.regenTimer = p.regenTimer - 5.0
            local heal = math.max(1, math.floor(p.maxHp * p.regenPct))
            p.hp = math.min(p.maxHp, p.hp + heal)
        end
    end

    -- 技能树平坦回复（flatRegen：每10秒回复固定 HP）
    if p.flatRegen and p.flatRegen > 0 and p.hp < p.maxHp then
        p.flatRegenTimer = (p.flatRegenTimer or 0) + dt
        if p.flatRegenTimer >= 10.0 then
            p.flatRegenTimer = p.flatRegenTimer - 10.0
            local heal = math.floor(p.flatRegen)
            p.hp = math.min(p.maxHp, p.hp + heal)
        end
    end

    -- 自动修复（autoHealPct：每10秒回复 autoHealPct*maxHp）
    if p.autoHealPct and p.autoHealPct > 0 and p.hp < p.maxHp then
        p.autoHealTimer = (p.autoHealTimer or 0) + dt
        if p.autoHealTimer >= 10.0 then
            p.autoHealTimer = p.autoHealTimer - 10.0
            local heal = math.max(1, math.floor(p.maxHp * p.autoHealPct))
            p.hp = math.min(p.maxHp, p.hp + heal)
        end
    end

    -- 无限火力：击杀后免弹药计时器倒数
    if p.ammoFreeTimer and p.ammoFreeTimer > 0 then
        p.ammoFreeTimer = p.ammoFreeTimer - dt
    end

    -- 混乱弹夹特效倒计时
    if p.chaosTimer and p.chaosTimer > 0 then
        p.chaosTimer = p.chaosTimer - dt
        if p.chaosTimer <= 0 then
            p.chaosTimer  = 0
            p.chaosEffect = nil
        end
    end

    -- ⚡ 雷影步无敌倒计时
    if p.elecDodgeTimer and p.elecDodgeTimer > 0 then
        p.elecDodgeTimer = p.elecDodgeTimer - dt
        if p.elecDodgeTimer <= 0 then p.elecDodgeTimer = 0 end
    end

    -- 暗影步冷却倒计时
    if p._shadowStepCdTimer and p._shadowStepCdTimer > 0 then
        p._shadowStepCdTimer = p._shadowStepCdTimer - dt
        if p._shadowStepCdTimer <= 0 then p._shadowStepCdTimer = 0 end
    end

    -- 翻滚冷却计时
    if p.rollCd > 0 then
        p.rollCd = p.rollCd - dt
        if p.rollCd < 0 then p.rollCd = 0 end
    end

    -- 翻滚物理（覆盖普通移动）
    if p.rollTimer > 0 then
        p.rollTimer = p.rollTimer - dt
        -- 无敌帧结束判定
        if p.rollInvincible and (ROLL_DURATION - p.rollTimer) >= ROLL_INVINCIBLE_END then
            p.rollInvincible = false
        end
        if p.rollTimer <= 0 then
            p.rollTimer      = 0
            p.rollInvincible = false
        else
            -- 翻滚移动（不受普通 speedMult 影响，保持固定高速）
            p.x = p.x + p.rollDirX * ROLL_SPEED * dt
            p.y = p.y + p.rollDirY * ROLL_SPEED * dt
            World.ResolveWall(p, 14)
        end
        -- 翻滚期间跳过普通移动逻辑
        if p.rollTimer > 0 then
            if p.shootCd > 0 then p.shootCd = p.shootCd - dt end
            if p.hitFlash > 0 then p.hitFlash = p.hitFlash - dt end
            if p.hitShake and p.hitShake > 0 then p.hitShake = p.hitShake - dt end
            if p.reloadTimer > 0 then p.reloadTimer = p.reloadTimer - dt end
            return
        end
    end

    -- 移动
    local dx, dy = 0, 0
    if keys.w then dy = dy - 1 end
    if keys.s then dy = dy + 1 end
    if keys.a then dx = dx - 1 end
    if keys.d then dx = dx + 1 end
    if dx ~= 0 and dy ~= 0 then dx = dx * 0.707; dy = dy * 0.707 end

    local castMult = (p.medCast ~= nil) and 0.5 or 1.0
    p.isMoving = (dx ~= 0 or dy ~= 0)
    local spd = 171 * (p.speedMult or 1.0) * (p.speedBoostMult or 1.0) * castMult
    p.x = p.x + dx * spd * dt
    p.y = p.y + dy * spd * dt
    World.ResolveWall(p, 14)

    -- 冷却（facing 由 UpdateAim 用精确 camX 设置，此处不重复计算）
    if p.shootCd > 0 then p.shootCd = p.shootCd - dt end
    if p.recoilTimer and p.recoilTimer > 0 then p.recoilTimer = p.recoilTimer - dt * 12 end
    if p.hitFlash > 0 then p.hitFlash = p.hitFlash - dt end
    if p.hitShake and p.hitShake > 0 then p.hitShake = p.hitShake - dt end

    -- 装弹倒计时
    if p.reloadTimer > 0 then
        p.reloadTimer = p.reloadTimer - dt
        if p.reloadTimer <= 0 then
            p.reloadTimer = 0
            -- 从 ammoStash 消耗（使用别名解析后的 key）
            local atype = p.reloadAmmoKey or p.weapon.ammoType
            if atype and p.ammoStash then
                if p.reloadPerShell then
                    -- 逐发装弹：每次只装 1 发
                    local avail = p.ammoStash[atype] or 0
                    if avail > 0 and p.weapon.ammo < p.weapon.maxAmmo then
                        p.weapon.ammo      = p.weapon.ammo + 1
                        p.ammoStash[atype] = avail - 1
                    end
                    -- 弹匣未满且仍有储备：自动继续装下一发
                    local stillNeed  = p.weapon.ammo < p.weapon.maxAmmo
                    local stillHave  = (p.ammoStash[atype] or 0) > 0
                    if stillNeed and stillHave then
                        local base = p.weapon.reloadTime or RELOAD_TIME_DEFAULT
                        p.reloadTimer = base * (p.reloadMult or 1.0)
                        -- reloadAmmoKey / reloadPerShell 保持不变，继续循环
                    else
                        p.reloadPerShell = false
                        p.reloadAmmoKey  = nil
                    end
                else
                    -- 普通装弹：一次填满弹匣
                    local need  = p.weapon.maxAmmo - p.weapon.ammo
                    local avail = p.ammoStash[atype] or 0
                    local fill  = math.min(need, avail)
                    p.weapon.ammo      = p.weapon.ammo + fill
                    p.ammoStash[atype] = avail - fill
                    p.reloadAmmoKey    = nil
                    -- 闪现：装弹完成后朝瞄准方向瞬移 80px
                    if p.dashOnReload then
                        local da = p.aimAngle or 0
                        p.x = p.x + math.cos(da) * 80
                        p.y = p.y + math.sin(da) * 80
                        World.ResolveWall(p, 14)
                    end
                    -- 混乱弹夹：装弹完成后随机触发一种特效，持续8秒
                    if p.randomOnReload then
                        p.chaosEffect = math.random(3)  -- 1=弹射 2=爆炸 3=吸血
                        p.chaosTimer  = 8.0
                    end
                end
            else
                -- 近战/无类型武器：直接填满（保持兼容）
                p.weapon.ammo    = p.weapon.maxAmmo
                p.reloadPerShell = false
                p.reloadAmmoKey  = nil
            end
        end
    end

    -- 掉落物冷却倒计时（不自动拾取，需要按E）
    for _, drop in ipairs(World.drops) do
        if not drop.picked and drop.nopickTimer then
            drop.nopickTimer = drop.nopickTimer - dt
            if drop.nopickTimer <= 0 then drop.nopickTimer = nil end
        end
    end
end

-- 自动锁定有效视野内（+8%缓冲）最近的存活敌人
-- fovRadius: 玩家视野半径（像素），与 FOV 遮罩一致
local function findLockTarget(p, enemies, fovRadius)
    local limitSq  = (fovRadius * 1.08) ^ 2
    local isMelee  = p.weapon and p.weapon.isMelee
    local best, bestDistSq = nil, math.huge
    for _, e in ipairs(enemies) do
        if e.hp > 0 then
            local dx = e.x - p.x
            local dy = e.y - p.y
            local dSq = dx*dx + dy*dy
            if dSq < limitSq and dSq < bestDistSq then
                -- 近战时贴身敌人跳过 LOS（刀本就是近身攻击），远距离仍需检查
                local losOk = isMelee and (dSq < 3600) or World.HasLOS(p.x, p.y, e.x, e.y)
                if losOk then
                    bestDistSq = dSq
                    best       = e
                end
            end
        end
    end
    return best
end

-- 更新瞄准（有敌人→锁定最近敌人；无敌人→朝前进方向）
-- enemies、fovRadius、keys 由 main.lua 传入
function M.UpdateAim(p, camX, camY, enemies, fovRadius, keys)
    local target = findLockTarget(p, enemies or {}, fovRadius or 210)
    p.lockTarget = target   -- 供 TryShoot 和渲染使用

    if target then
        local dx = target.x - p.x
        local dy = target.y - p.y
        p.aimAngle = math.atan(dy, dx)
        p.facing   = (dx >= 0) and 1 or -1
    else
        -- 无敌人：枪口朝前进方向
        local k    = keys or {}
        local mvx  = (k.d and 1 or 0) - (k.a and 1 or 0)
        local mvy  = (k.s and 1 or 0) - (k.w and 1 or 0)
        if mvx ~= 0 or mvy ~= 0 then
            p.aimAngle = math.atan(mvy, mvx)
            p.facing   = (mvx >= 0) and 1 or -1
        end
        -- 静止时保持上一帧的 aimAngle/facing 不变
    end
end

-- ----------------------------------------------------------------------------
-- 搜索系统（委托给 Search 模块）
-- ----------------------------------------------------------------------------

-- 尝试对容器开始搜索（container = box 或尸体）
function M.TryStartSearch(p, container)
    if p.searchState.isOpen then return end  -- 已有面板打开
    Search.StartSearch(p.searchState, container)
    -- StartSearch 现在总是立即设 isOpen = true
    if p.searchState.isOpen then
        p.searchOpen = true
    end
end

-- 每帧更新搜索进度；完成时同步 searchOpen 标志，并返回 true
function M.UpdateSearch(p, dt)
    if not p.searchState.isSearching then return false end
    -- 技能树搜索加速（skillSearchSpeed 为百分比加速）
    local effectiveDt = dt
    if p.skillSearchSpeed and p.skillSearchSpeed > 0 then
        effectiveDt = dt * (1 + p.skillSearchSpeed)
    end
    local done = Search.Update(p.searchState, effectiveDt)
    if done then
        p.searchOpen = true
        return true
    end
    return false
end

-- 关闭搜索面板（pcall 保证即使 Search.Close 内部出错，searchOpen 也一定被清除）
function M.CloseSearch(p)
    local ok, err = pcall(Search.Close, p.searchState)
    if not ok then
        -- Close 内部出错时手动清理所有状态，防止面板永久锁死
        p.searchState.isSearching  = false
        p.searchState.isOpen       = false
        p.searchState.containerInv = nil
        p.searchState.container    = nil
        p.searchState.pendingItems = {}
        print("[CloseSearch] Search.Close error:", err)
    end
    p.searchOpen = false
end

-- 从容器取一件物品（用于鼠标点击）
function M.SearchTakeItem(p, itemId)
    local ss = p.searchState
    if not ss.isOpen or not ss.containerInv then return false end
    local entry = Inventory.RemoveItem(ss.containerInv, itemId)
    if not entry then return false end
    local item = {
        itype  = entry.itype,
        data   = entry.data,
        name   = entry.name,
        icon   = entry.icon,
        rarity = entry.rarity,
        value  = entry.value,
        qty    = entry.qty,
    }
    -- 走完整的 PickupItem 逻辑（武器自动换装、背包+胸挂双槽）
    local ok = M.PickupItem(p, item)
    if not ok then
        -- 放回容器
        Inventory.AutoPlace(ss.containerInv, item)
        -- 通知玩家背包已满
        p.notification = { text = "背包已满！", timer = 1.8 }
        return false
    end
    p.lootValue = Inventory.TotalValue(p.inventory)
    -- 取走成功提示
    p.notification = { text = "+" .. (item.name or "物品"), timer = 0.9 }
    return true
end

-- 一键取全部
function M.SearchTakeAll(p)
    local ss = p.searchState
    if not ss.isOpen or not ss.containerInv then return end
    -- 先收集所有 id，再逐一取（避免迭代中修改列表）
    local ids = {}
    for _, e in ipairs(ss.containerInv.items) do
        table.insert(ids, e.id)
    end
    local taken = 0
    for _, id in ipairs(ids) do
        if M.SearchTakeItem(p, id) then taken = taken + 1 end
    end
    p.lootValue = Inventory.TotalValue(p.inventory)
end

-- ----------------------------------------------------------------------------
-- 智能自动拾取（AutoLoot）
-- 按稀有度从高到低取物品；背包满时，若容器中有更高稀有度物品，
-- 则从背包找最低稀有度的普通战利品丢回容器腾出空间后再拾取。
-- 返回：{ taken=N, swapped=N, skipped=N }
-- ----------------------------------------------------------------------------
function M.AutoLoot(p)
    local ss = p.searchState
    if not ss.isOpen or not ss.containerInv then return { taken=0, swapped=0, skipped=0 } end
    local cInv = ss.containerInv

    -- 价值密度计算：value / 占用格数
    local function valueDensity(entry)
        local v = entry.value or 0
        local iw = entry.iw or 1
        local ih = entry.ih or 1
        local slots = iw * ih
        -- 堆叠物品按单个价值×数量计算总密度
        local qty = entry.qty or 1
        return (v * qty) / slots
    end

    -- 1. 按价值密度降序排列容器物品快照（先拿最好的）
    local snapshot = {}
    for _, e in ipairs(cInv.items) do
        table.insert(snapshot, { id=e.id, rarity=e.rarity or 1, value=e.value or 0,
                                  name=e.name, itype=e.itype,
                                  iw=e.iw or 1, ih=e.ih or 1, qty=e.qty or 1 })
    end
    table.sort(snapshot, function(a, b)
        return valueDensity(a) > valueDensity(b)
    end)

    local taken, swapped, skipped = 0, 0, 0
    local gainedValue, lostValue = 0, 0  -- 净值追踪
    local takenNames, droppedNames = {}, {}

    for _, snap in ipairs(snapshot) do
        -- 物品可能已被前一次循环取走，先确认还在
        local stillInContainer = false
        for _, e in ipairs(cInv.items) do
            if e.id == snap.id then stillInContainer = true; break end
        end
        if not stillInContainer then goto continue_al end

        -- 尝试直接拾取
        local ok = M.SearchTakeItem(p, snap.id)
        if ok then
            taken = taken + 1
            gainedValue = gainedValue + (snap.value or 0) * (snap.qty or 1)
            table.insert(takenNames, snap.name or "物品")
        else
            -- 背包满：按价值密度找背包里最差的可丢弃物品（itype=="loot"）
            local snapDensity = valueDensity(snap)

            -- 收集背包中所有 loot 类型物品，按价值密度升序排序（最差在前）
            local lootEntries = {}
            for _, be in ipairs(p.inventory.items) do
                if be.itype == "loot" then
                    table.insert(lootEntries, be)
                end
            end
            table.sort(lootEntries, function(a, b)
                return valueDensity(a) < valueDensity(b)
            end)

            -- 找到价值密度低于容器物品的背包最差物品
            local worstEntry = nil
            for _, be in ipairs(lootEntries) do
                if valueDensity(be) < snapDensity then
                    worstEntry = be
                    break
                end
            end

            if worstEntry then
                -- 把背包里最差物品放回容器
                local removed = Inventory.RemoveItem(p.inventory, worstEntry.id)
                if removed then
                    local putBack = {
                        itype = removed.itype, data = removed.data,
                        name  = removed.name,  icon = removed.icon,
                        rarity= removed.rarity, value = removed.value,
                        qty   = removed.qty,
                    }
                    Inventory.AutoPlace(cInv, putBack)
                    -- 再次尝试拾取目标物品
                    ok = M.SearchTakeItem(p, snap.id)
                    if ok then
                        taken   = taken + 1
                        swapped = swapped + 1
                        gainedValue = gainedValue + (snap.value or 0) * (snap.qty or 1)
                        lostValue = lostValue + (removed.value or 0) * (removed.qty or 1)
                        table.insert(takenNames, snap.name or "物品")
                        table.insert(droppedNames, removed.name or "物品")
                    else
                        -- 还是放不下（格子形状不匹配）：把物品放回
                        skipped = skipped + 1
                    end
                end
            else
                skipped = skipped + 1
            end
        end

        ::continue_al::
    end

    p.lootValue = Inventory.TotalValue(p.inventory)

    -- 生成通知文字（含净值变化）
    local netGain = gainedValue - lostValue
    if taken > 0 and swapped > 0 then
        local sign = netGain >= 0 and "+" or ""
        p.notification = { text = string.format("智能拾取%d件·换出%d件 %s%d", taken, swapped, sign, netGain), timer = 2.5 }
    elseif taken > 0 then
        p.notification = { text = string.format("自动拾取 %d 件 +%d", taken, gainedValue), timer = 1.8 }
    elseif skipped > 0 then
        p.notification = { text = "没有更好的物品", timer = 1.8 }
    end

    return { taken=taken, swapped=swapped, skipped=skipped, netGain=netGain,
             takenNames=takenNames, droppedNames=droppedNames }
end

-- ----------------------------------------------------------------------------
-- 背包面板：装备 / 卸装
-- ----------------------------------------------------------------------------

-- 从背包或胸挂取出指定 id 的物品，装备到对应槽位
-- 武器：替换 p.weapon（旧武器放回背包）
-- 装备：替换对应 equip 槽（旧装备放回背包）
-- 返回 true / false
function M.EquipFromInventory(p, itemId)
    -- 先在主背包找，再在胸挂找
    local entry, sourceInv
    local function findEntry(inv)
        for _, e in ipairs(inv.items) do
            if e.id == itemId then return e end
        end
        return nil
    end

    entry = findEntry(p.inventory)
    if entry then sourceInv = p.inventory end

    if not entry or not sourceInv then return false end

    local itype = entry.itype
    local itemData = entry.data

    -- ---- 武器 ----
    if itype == "weapon" then
        -- 根据武器 slot 决定放入哪个武器槽
        local targetSlot = itemData.slot or "primary"  -- "primary" 或 "secondary"

        -- 取出目标槽位中的旧武器（不是 p.weapon！）
        local oldWeapon
        if targetSlot == "secondary" then
            oldWeapon = p.secondaryGun
        else
            oldWeapon = p.primaryGun
        end

        -- 从背包移除新武器
        Inventory.RemoveItem(sourceInv, itemId)

        -- 将新武器放入对应槽位
        if targetSlot == "secondary" then
            p.secondaryGun = itemData
        else
            p.primaryGun = itemData
        end

        -- 选中该槽位并同步 p.weapon 引用
        p.activeSlot = targetSlot
        syncWeaponRef(p)
        p.reloadTimer = 0

        -- 旧武器：优先放背包，放不下则掉落地面
        if oldWeapon and oldWeapon.key ~= "Knife" then
            local oldItem = {
                itype="weapon", data=oldWeapon,
                name=oldWeapon.name, icon="🔫",
                rarity=oldWeapon.rarity, value=oldWeapon.value
            }
            local ok = M.AddToInventory(p, oldItem)
            if not ok then
                World.drops[#World.drops + 1] = {
                    x = p.x + math.random(-18, 18),
                    y = p.y + math.random(-18, 18),
                    item   = oldItem,
                    picked = false,
                    nopickTimer = 0.5,
                }
                p.notification = { text = oldWeapon.name .. " 掉落在脚下", timer = 1.5 }
            end
        end
        return true
    end

    -- ---- 装备槽（helmet / armor / bag）----
    local equipSlots = { helmet=true, armor=true, bag=true }
    local slot = (equipSlots[itype]) and itype or nil
    if not slot then return false end

    local oldEquip = p.equip[slot]
    -- 从背包移除
    Inventory.RemoveItem(sourceInv, itemId)

    -- 旧装备：优先放背包，放不下则掉落地面
    if oldEquip then
        local oldItem = {
            itype=slot, data=oldEquip,
            name=oldEquip.name, icon=oldEquip.icon,
            rarity=oldEquip.rarity, value=oldEquip.value
        }
        local ok = M.AddToInventory(p, oldItem)
        if not ok then
            World.drops[#World.drops + 1] = {
                x = p.x + math.random(-18, 18),
                y = p.y + math.random(-18, 18),
                item   = oldItem,
                picked = false,
                nopickTimer = 0.5,
            }
            p.notification = { text = oldEquip.name .. " 掉落在脚下", timer = 1.5 }
        end
    end

    -- 装备新物品
    p.equip[slot] = itemData
    if slot == "bag" then M.UpdateBagSize(p) end
    p.lootValue = Inventory.TotalValue(p.inventory)
    return true
end

-- 卸下装备槽到背包
-- 返回 true / false, reason
function M.UnequipSlot(p, slot)
    local item = p.equip[slot]
    if not item then return false, "该槽位为空" end

    -- 尝试放入背包
    local ok = M.AddToInventory(p, {
        itype=slot, data=item,
        name=item.name, icon=item.icon,
        rarity=item.rarity, value=item.value
    })
    if not ok then return false, "背包已满" end

    -- 清除装备槽并更新尺寸
    p.equip[slot] = nil
    if slot == "bag" then M.UpdateBagSize(p) end
    p.lootValue = Inventory.TotalValue(p.inventory)
    return true
end

-- ----------------------------------------------------------------------------
-- E键交互：掉落物拾取 / 容器搜索 / 撤离
-- ----------------------------------------------------------------------------

-- 收集玩家附近可拾取的掉落物
local function getNearbyDrops(p, radius)
    local nearby = {}
    for _, drop in ipairs(World.drops) do
        if not drop.picked and not drop.nopickTimer then
            local dd = math.sqrt((p.x - drop.x)^2 + (p.y - drop.y)^2)
            if dd < radius then
                nearby[#nearby + 1] = drop
            end
        end
    end
    return nearby
end

function M.TryInteract(p, worldMod)
    if p.dead then return end

    -- 面板已打开时 E 键关闭
    if p.searchOpen then
        M.CloseSearch(p)
        return
    end

    -- 0. 检查附近掉落物（最高优先）
    local nearbyDrops = getNearbyDrops(p, 36)
    if #nearbyDrops >= 2 then
        -- 多个掉落物：打开临时容器面板让玩家选择
        local loot = {}
        local dropRef = {}  -- 用于同步拾取状态
        for _, drop in ipairs(nearbyDrops) do
            loot[#loot + 1] = drop.item
            dropRef[#dropRef + 1] = drop
        end
        local cols = math.min(#loot, 5)
        local rows = math.ceil(#loot / cols)
        local container = {
            loot      = loot,
            name      = "掉落物",
            x         = p.x, y = p.y,
            cw        = cols,
            ch        = rows,
            _box      = { _isDropContainer = true, _drops = dropRef, opened = true },
            _fastOpen = true,
        }
        M.TryStartSearch(p, container)
        return
    elseif #nearbyDrops == 1 then
        -- 单个掉落物：直接拾取
        local drop = nearbyDrops[1]
        local ok = M.PickupItem(p, drop.item)
        if ok then
            drop.picked = true
            if drop._glowId then
                local LightMod = require("Lighting")
                LightMod.RemoveItemGlow(drop._glowId)
            end
            World.SpawnPickup(drop.x, drop.y)
            p.notification = { text = "拾取: " .. (drop.item.name or "物品"), timer = 1.2 }
        else
            p.notification = { text = "背包已满", timer = 1.2 }
        end
        return
    end

    -- 1. 检查附近尸体（优先）
    local corpses = worldMod.GetCorpses and worldMod.GetCorpses() or {}
    for _, corpse in ipairs(corpses) do
        if not corpse.looted then
            local dd = math.sqrt((p.x - corpse.x)^2 + (p.y - corpse.y)^2)
            if dd < 42 then
                local sameBox = p.searchState.container and p.searchState.container._box == corpse
                if not p.searchState.isSearching or not sameBox then
                    -- 与箱子保持一致：包装成 container，传入 _box/_fastOpen
                    -- 已搜过的尸体（corpse.opened=true）跳过加载动画直接复用缓存
                    local container = {
                        loot      = corpse.loot,
                        isEnemy   = corpse.isEnemy,
                        isBoss    = corpse.isBoss,
                        name      = corpse.name,
                        x         = corpse.x, y = corpse.y,
                        cw        = corpse.cw,
                        ch        = corpse.ch,
                        _box      = corpse,
                        _fastOpen = corpse.opened,
                    }
                    M.TryStartSearch(p, container)
                end
                return
            end
        end
    end

    -- 2. 检查附近箱子（搜过的也能再次打开，查看剩余物品）
    local boxes = worldMod.GetBoxes()
    for _, box in ipairs(boxes) do
        local dd = math.sqrt((p.x - box.x)^2 + (p.y - box.y)^2)
        if dd < 44 then
            if not p.searchState.isSearching or p.searchState.container ~= box then
                local loot = worldMod.PeekBox(box)
                -- 已搜过且空箱：直接打开空面板（不需要重新搜索）
                local dur = box.opened and 0.01 or nil  -- 已开箱则几乎无延迟
                local container = {
                    loot    = loot,
                    elite   = box.elite,
                    x       = box.x, y = box.y,
                    cw      = box.elite and 6 or 5,
                    ch      = box.elite and 5 or 4,
                    _box    = box,
                    _fastOpen = box.opened,  -- 已搜过的箱子快速打开
                }
                M.TryStartSearch(p, container)
            end
            return
        end
    end

    -- 3. 房间固定交互：神龛 / 事件圆盘 / 休息泉
    if worldMod.TryRoomInteract and worldMod.TryRoomInteract(p) then
        return
    end

    -- 搜索进度中但离开了范围：取消
    if p.searchState.isSearching then
        Search.CancelSearch(p.searchState)
        return
    end

    -- 4. 检查是否在出口
    local col, row = worldMod.WorldToTile(p.x, p.y)
    if worldMod.IsExitCell(col, row) then
        -- 出口被锁（Boss层Boss未死）则不能撤离
        if worldMod.exitLocked then
            return
        end
        if p.extracting <= 0 then
            p.extracting = 0.001  -- 启动计时（用正数表示进行中）
            p.extracted = false
        end
        return
    end

    -- 5. 离开出口则取消撤离
    if p.extracting > 0 and not p.extracted then
        p.extracting = 0
    end
end

-- 撤离计时更新（每帧由 main 调用）
function M.UpdateExtract(p, dt)
    if p.extracting <= 0 or p.extracted then return end
    p.extracting = p.extracting + dt
    if p.extracting >= 3.0 then
        p.extracting = 3.0
        p.extracted = true
    end
end

return M
