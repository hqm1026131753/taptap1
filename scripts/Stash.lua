-- ============================================================================
-- Stash.lua — 玩家仓库 + 商人系统
-- 收购价 = value × 0.9；售价 = value × 3.0
-- 商店售卖：武器、防具（含头盔胸挂背包）、药品（不卖弹药/战利品/垃圾）
-- ============================================================================
local Inventory = require("Inventory")
local Data      = require("Data")

local M = {}

-- ----------------------------------------------------------------------------
-- 仓库升级配置（对齐设计文档）
-- ----------------------------------------------------------------------------
M.UPGRADES = {
    { level=1, w=10, h=10, cost=0     },
    { level=2, w=12, h=10, cost=5000  },
    { level=3, w=14, h=12, cost=20000 },
    { level=4, w=16, h=14, cost=50000 },
}

-- ----------------------------------------------------------------------------
-- 商人数据表
-- 设计文档：商店只售卖武器、防具、背包、药品，不卖弹药/战利品/垃圾
-- buyMult: 收购倍率（基础 0.9，高价商人 × 对应类型）
-- sellMult: 卖给玩家的倍率（固定 3.0）
-- ----------------------------------------------------------------------------

-- 内部辅助：生成商店商品条目（武器）
local function WpEntry(key)
    local tmpl = Data.WEAPONS[key]
    if not tmpl then return nil end
    local iw = (tmpl.slot == "secondary") and 1 or 1
    local ih = 2
    if tmpl.slot == "primary" then
        local name = tmpl.name
        if name:find("AWM") or name:find("R93") then ih = 5
        elseif name:find("M1014") or name:find("S12K") or name:find("725") or name:find("PKM") then ih = 4
        else ih = 3 end
    end
    return {
        id    = "shop_wp_" .. key,
        name  = tmpl.name,
        icon  = tmpl.icon or "\xF0\x9F\x94\xAB",
        price = math.floor(tmpl.value * 6.0),
        iw=iw, ih=ih,
        itype = "weapon",
        rarity = tmpl.rarity,
        value  = tmpl.value,
        key    = key,
    }
end

-- 内部辅助：生成商店商品条目（防具/头盔）
local function EquipEntry(slot, id)
    local tbl
    if slot == "helmet" then tbl = Data.HELMETS
    elseif slot == "armor" then tbl = Data.ARMORS
    elseif slot == "bag"  then tbl = Data.BAGS
    end
    if not tbl then return nil end
    for _, tmpl in ipairs(tbl) do
        if tmpl.id == id then
            return {
                id    = "shop_eq_" .. slot .. "_" .. id,
                name  = tmpl.name,
                icon  = tmpl.icon or "\xF0\x9F\x9B\xA1\xEF\xB8\x8F",
                price = math.floor(tmpl.value * 6.0),
                iw=2, ih=2,
                itype = "equip",
                slot  = slot,
                rarity = tmpl.rarity,
                value  = tmpl.value,
                equipId = id,
            }
        end
    end
    return nil
end

-- 内部辅助：生成商店商品条目（弹药，qty颗为一组）
local function AmmoEntry(ammoType, qty)
    local tmpl = Data.AMMO_TYPES[ammoType]
    if not tmpl then return nil end
    local unitPrice = tmpl.value or 20
    return {
        id    = "shop_ammo_" .. ammoType,
        name  = tmpl.name .. " ×" .. qty,
        icon  = tmpl.icon or "📦",
        price = math.floor(unitPrice * qty * 0.15),  -- 每颗约15%基础价
        iw=1, ih=1,
        itype  = "ammo",
        rarity = tmpl.rarity or 1,
        value  = unitPrice * qty,
        ammoType = ammoType,
        ammoQty  = qty,  -- 每次购买获得的子弹数
        maxOwned = 99,   -- 每种弹药持有上限
    }
end

-- 内部辅助：生成商店商品条目（消耗品）
local function ConsEntry(id)
    for _, tmpl in ipairs(Data.CONSUMABLES) do
        if tmpl.id == id then
            return {
                id    = "shop_cs_" .. id,
                name  = tmpl.name,
                icon  = tmpl.icon,
                img   = tmpl.img,
                price = math.floor(tmpl.value * 3.0),
                iw = tmpl.lw or 1,
                ih = tmpl.lh or 1,
                itype  = "loot",
                rarity = tmpl.rarity,
                value  = tmpl.value,
                consId = id,
            }
        end
    end
    return nil
end

M.VENDORS = {
    -- ── 1. 治疗师：药品专卖 ─────────────────────────────────────────────────
    {
        id   = "therapist",
        name = "治疗师",
        icon = "\xF0\x9F\x91\xA9\xE2\x80\x8D\xE2\x9A\x95\xEF\xB8\x8F",
        desc = "专卖医疗品，高价收购药品",
        buyCat = { "med" },   -- 高价收购类别标记
        shop = {
            ConsEntry("bandage"),
            ConsEntry("medkit"),
            ConsEntry("surgery_kit"),
            ConsEntry("painkiller"),
            ConsEntry("adrenaline"),
        },
    },
    -- ── 2. 机械师：武器专卖 ─────────────────────────────────────────────────
    {
        id   = "mechanic",
        name = "机械师",
        icon = "\xF0\x9F\x94\xA7",
        desc = "武器专卖，收购武器弹药",
        buyCat = { "weapon" },
        shop = {
            AmmoEntry("light",  20),
            AmmoEntry("medium", 15),
            AmmoEntry("heavy",  8),
            AmmoEntry("sniper", 5),
            WpEntry("Glock"),
            WpEntry("MP5"),
            WpEntry("UZI"),
            WpEntry("G18"),
            WpEntry("AKM"),
            WpEntry("M16"),
            WpEntry("MP7"),
            WpEntry("M870"),
            WpEntry("AUG"),
            WpEntry("P90"),
            WpEntry("DesertEagle"),
            WpEntry("M1014"),
            WpEntry("PKM"),
            WpEntry("M250"),
            WpEntry("AWM"),
            WpEntry("R93"),
        },
    },
    -- ── 3. 服装商：防具/头盔/胸挂/背包 ─────────────────────────────────────
    {
        id   = "ragman",
        name = "服装商",
        icon = "\xF0\x9F\x91\x95",
        desc = "防具专卖，高价收购装备",
        buyCat = { "equip" },
        shop = {
            EquipEntry("helmet", "cap"),
            EquipEntry("helmet", "helm_light"),
            EquipEntry("helmet", "helm_heavy"),
            EquipEntry("helmet", "helm_full"),
            EquipEntry("armor", "armor_tact"),
            EquipEntry("armor", "armor_light"),
            EquipEntry("armor", "armor_medium"),
            EquipEntry("armor", "armor_heavy"),
            EquipEntry("armor", "armor_ceramic"),
            EquipEntry("bag", "small"),
            EquipEntry("bag", "medium"),
            EquipEntry("bag", "large"),
            EquipEntry("bag", "medic"),
            EquipEntry("bag", "assault"),
        },
    },
    -- ── 4. 黑商：什么都收，价格偏低 ─────────────────────────────────────────
    {
        id   = "fence",
        name = "黑商",
        icon = "\xF0\x9F\x95\xB5\xEF\xB8\x8F",
        desc = "什么都收，价格偏低",
        buyCat = {},   -- 无高价类别
        shop = {
            ConsEntry("bandage"),
            ConsEntry("medkit"),
            WpEntry("Glock"),
            WpEntry("MP5"),
            EquipEntry("helmet", "helm_light"),
            EquipEntry("armor", "armor_tact"),
            EquipEntry("bag", "small"),
        },
    },
}

-- nil 条目过滤（EquipEntry/WpEntry/ConsEntry 返回 nil 时清理）
for _, v in ipairs(M.VENDORS) do
    local filtered = {}
    for _, item in ipairs(v.shop) do
        if item then table.insert(filtered, item) end
    end
    v.shop = filtered
end

-- 按 id 快速查找商人
M.VENDOR_BY_ID = {}
for _, v in ipairs(M.VENDORS) do
    M.VENDOR_BY_ID[v.id] = v
end

-- ----------------------------------------------------------------------------
-- 价格常量（对齐设计文档）
-- ----------------------------------------------------------------------------
M.BUY_MULT  = 0.72  -- 收购价：物品价值 × 0.72
M.SELL_MULT = 3.0   -- 售价：物品价值 × 3.0（武器/防具单独 ×6.0）

-- 黑商的特殊收购倍率
M.FENCE_MULT = 0.56

-- ----------------------------------------------------------------------------
-- 获取物品的类别标签
-- ----------------------------------------------------------------------------
function M.GetItemCat(item)
    if item.itype == "weapon" then return "weapon" end
    -- 装备槽（itype 就是 slot 名，如 "bag"/"armor"/"rig"/"helmet"）
    if item.itype == "helmet" or item.itype == "armor"
    or item.itype == "bag" then return "equip" end
    -- 消耗品（新格式）
    if item.itype == "consumable" then
        local d = item.data
        if d and d.effectType == "heal" then return "med" end
        return "misc"
    end
    -- 旧格式兼容（仓库里可能残留旧数据）
    if item.itype == "equip" then return "equip" end
    if item.itype == "loot" then
        local t = item.type or ""
        if t == "medkit" or t == "med" then return "med" end
        if t == "ammo"   then return "ammo" end
        return "loot"
    end
    return "misc"
end

-- ----------------------------------------------------------------------------
-- 计算出售给商人的价格
-- 逻辑：
--   黑商：value × 0.7
--   其他商人：如果 item 类别在 vendor.buyCat 中 → value × 0.9（原收购价）
--             否则 → value × 0.9（统一收购价，不再惩罚）
-- ----------------------------------------------------------------------------
function M.GetSellPrice(item, vendor)
    local baseVal = (item.value or 0) * (item.qty or 1)
    if vendor.id == "fence" then
        return math.floor(baseVal * M.FENCE_MULT)
    end
    -- 其他商人统一 90%
    return math.floor(baseVal * M.BUY_MULT)
end

-- 计算物品对所有商人的最高卖价
function M.GetBestSellPrice(item)
    local best = 0
    local bestVendorId = "fence"
    for _, v in ipairs(M.VENDORS) do
        local p = M.GetSellPrice(item, v)
        if p > best then
            best = p
            bestVendorId = v.id
        end
    end
    return best, bestVendorId
end

-- ----------------------------------------------------------------------------
-- 出售仓库中的物品给商人（confirmSell 路径）
-- ----------------------------------------------------------------------------
function M.SellItem(stash, itemId, vendorId)
    local vendor = M.VENDOR_BY_ID[vendorId]
    if not vendor then return false, 0 end

    -- 战术刀为永久道具，不可出售
    for _, entry in ipairs(stash.inv.items) do
        if entry.id == itemId then
            local k = entry.key or (entry.data and entry.data.key)
            if k == "Knife" then return false, 0 end
            break
        end
    end

    local entry = Inventory.RemoveItem(stash.inv, itemId)
    if not entry then return false, 0 end

    local price = M.GetSellPrice(entry, vendor)
    stash.money = stash.money + price
    return true, price
end

-- ----------------------------------------------------------------------------
-- 从商人处购买物品（放入仓库）
-- ----------------------------------------------------------------------------
function M.BuyFromVendor(stash, vendorId, shopIdx)
    local vendor = M.VENDOR_BY_ID[vendorId]
    if not vendor then return false end

    local shopItem = vendor.shop[shopIdx]
    if not shopItem then return false end
    if stash.money < shopItem.price then return false end

    -- 根据商品类型构建实际物品
    local item
    if shopItem.itype == "weapon" then
        local tmpl = Data.WEAPONS[shopItem.key]
        if not tmpl then return false end
        -- data = tmpl 必须带上，UseItemFromBag 通过 entry.data 取武器数据
        item = {
            itype  = "weapon",
            name   = tmpl.name,
            icon   = tmpl.icon or "\xF0\x9F\x94\xAB",
            iw     = shopItem.iw,
            ih     = shopItem.ih,
            rarity = tmpl.rarity,
            value  = tmpl.value,
            key    = shopItem.key,
            data   = tmpl,          -- ← 修复：Player.UseItemFromBag 需要 entry.data
            -- 武器运行时字段（Data.lua 已在加载时写入 tmpl.ammo/tmpl.maxAmmo）
            ammo   = tmpl.ammo or tmpl.magSize,
            maxAmmo = tmpl.maxAmmo or tmpl.magSize,
            reserveAmmo = tmpl.magSize * 2,
        }
    elseif shopItem.itype == "equip" then
        local slot = shopItem.slot
        local tbl
        if slot == "helmet" then tbl = Data.HELMETS
        elseif slot == "armor" then tbl = Data.ARMORS
        elseif slot == "bag"  then tbl = Data.BAGS
        end
        local tmpl
        if tbl then
            for _, t in ipairs(tbl) do
                if t.id == shopItem.equipId then tmpl = t; break end
            end
        end
        if not tmpl then return false end
        -- itype 必须是 slot 名（"bag"/"armor"/"rig"/"helmet"），
        -- Inventory.GetSize / UseItemFromBag / PickupItem 都用 itype 做 key
        item = {
            itype  = slot,          -- ← 修复：不能是 "equip"，必须是 slot 名
            name   = tmpl.name,
            icon   = tmpl.icon or "\xF0\x9F\x9B\xA1\xEF\xB8\x8F",
            iw     = shopItem.iw,
            ih     = shopItem.ih,
            rarity = tmpl.rarity,
            value  = tmpl.value,
            data   = tmpl,
        }
    elseif shopItem.itype == "ammo" then
        -- 弹药购买：直接增加 stash.ammo[type]，上限99
        local atype = shopItem.ammoType
        local qty   = shopItem.ammoQty or 10
        local cap   = shopItem.maxOwned or 99
        stash.ammo = stash.ammo or {}
        local cur = stash.ammo[atype] or 0
        if cur >= cap then return false end  -- 已满
        local add = math.min(qty, cap - cur)
        stash.ammo[atype] = cur + add
        stash.money = stash.money - shopItem.price
        return true
    elseif shopItem.itype == "loot" then
        -- 消耗品：itype 必须是 "consumable"，heal 系统才能识别
        local tmpl
        for _, t in ipairs(Data.CONSUMABLES) do
            if t.id == shopItem.consId then tmpl = t; break end
        end
        if not tmpl then return false end
        item = {
            itype  = "consumable",  -- ← 修复：不能是 "loot"，heal 系统只扫 "consumable"
            name   = tmpl.name,
            icon   = tmpl.icon,
            iw     = tmpl.lw or 1,
            ih     = tmpl.lh or 1,
            rarity = tmpl.rarity,
            value  = tmpl.value,
            data   = tmpl,          -- tmpl 含 effectType="heal", healPct
        }
    else
        return false
    end

    local ok = M.AddItem(stash, item)
    if not ok then return false end  -- 仓库满

    stash.money = stash.money - shopItem.price
    return true
end

-- ----------------------------------------------------------------------------
-- 仓库初始化
-- ----------------------------------------------------------------------------
function M.New()
    local stash = {
        level = 1,
        money = 200,
        inv   = Inventory.New(10, 10),
        ammo  = {},  -- 商店购买的弹药储备 {light=N, medium=N, ...}
    }
    return stash
end

-- ----------------------------------------------------------------------------
-- 向仓库塞入一件物品（AutoPlace）
-- 返回 true = 成功，false = 仓库满
-- ----------------------------------------------------------------------------
function M.AddItem(stash, item)
    return Inventory.AutoPlace(stash.inv, item)
end

-- ----------------------------------------------------------------------------
-- 仓库升级
-- ----------------------------------------------------------------------------
function M.Upgrade(stash)
    local nextLevel = stash.level + 1
    local cfg = M.UPGRADES[nextLevel]
    if not cfg then return false end       -- 已满级
    if stash.money < cfg.cost then return false end

    stash.money = stash.money - cfg.cost
    stash.level = nextLevel

    -- 创建新网格并迁移物品
    local newInv = Inventory.New(cfg.w, cfg.h)
    for _, entry in ipairs(stash.inv.items) do
        local item = {
            itype = entry.itype, name = entry.name, icon = entry.icon,
            iw = entry.iw, ih = entry.ih, rarity = entry.rarity,
            value = entry.value, key = entry.key, slot = entry.slot,
            type = entry.type, data = entry.data,
            ammo = entry.ammo, maxAmmo = entry.maxAmmo,
            reserveAmmo = entry.reserveAmmo,
            qty = entry.qty,
        }
        Inventory.AutoPlace(newInv, item)
    end
    stash.inv = newInv
    return true
end

-- ----------------------------------------------------------------------------
-- 战局结束：存入仓库
-- survived = true  → 物品存入仓库
-- survived = false → 物品丢失
-- ----------------------------------------------------------------------------
function M.OnRaidEnd(stash, player, survived, deathSaveCount)
    if not survived then
        -- 技能树死亡保物：保留最值钱的 N 件物品到仓库
        if deathSaveCount and deathSaveCount > 0 then
            local inv = player.inventory
            if inv and inv.items and #inv.items > 0 then
                -- 按价值降序排列
                local sorted = {}
                for _, e in ipairs(inv.items) do sorted[#sorted + 1] = e end
                table.sort(sorted, function(a, b) return (a.value or 0) > (b.value or 0) end)
                local saveCount = math.min(deathSaveCount, #sorted)
                for i = 1, saveCount do
                    local entry = Inventory.RemoveItem(inv, sorted[i].id)
                    if entry then
                        M.AddItem(stash, {
                            itype  = entry.itype,
                            name   = entry.name,
                            icon   = entry.icon,
                            iw     = entry.iw,
                            ih     = entry.ih,
                            rarity = entry.rarity,
                            value  = entry.value,
                            key    = entry.key,
                            slot   = entry.slot,
                            type   = entry.type,
                            data   = entry.data,
                            ammo   = entry.ammo,
                            maxAmmo= entry.maxAmmo,
                            reserveAmmo = entry.reserveAmmo,
                            qty    = entry.qty,
                        })
                    end
                end
            end
        end
        return
    end

    -- 存活：背包物品 → 仓库
    local inv = player.inventory
    local ids = {}
    for _, e in ipairs(inv.items) do table.insert(ids, e.id) end
    for _, id in ipairs(ids) do
        local entry = Inventory.RemoveItem(inv, id)
        if entry then
            M.AddItem(stash, {
                itype  = entry.itype,
                name   = entry.name,
                icon   = entry.icon,
                iw     = entry.iw,
                ih     = entry.ih,
                rarity = entry.rarity,
                value  = entry.value,
                key    = entry.key,
                slot   = entry.slot,
                type   = entry.type,
                data   = entry.data,
                ammo   = entry.ammo,
                maxAmmo= entry.maxAmmo,
                reserveAmmo = entry.reserveAmmo,
                qty    = entry.qty,
            })
        end
    end
    -- 装备槽物品也存回仓库（itype = slot 名，与 World.GenerateItem 格式一致）
    local equipSlots = {"helmet","armor","bag"}
    for _, slot in ipairs(equipSlots) do
        local equip = player.equip[slot]
        if equip then
            M.AddItem(stash, {
                itype  = slot,          -- ← 修复：slot 名作 itype，与 Inventory/Player 期望一致
                name   = equip.name,
                icon   = equip.icon or "\xF0\x9F\x9B\xA1\xEF\xB8\x8F",
                iw     = 2, ih = 2,
                rarity = equip.rarity or 2,
                value  = equip.value or 100,
                data   = equip,
            })
            player.equip[slot] = nil
        end
    end

    -- 主副武器存入仓库（战术刀不存）
    local guns = {}
    if player.primaryGun and not player.primaryGun.isMelee then
        table.insert(guns, player.primaryGun)
    end
    if player.secondaryGun and not player.secondaryGun.isMelee then
        table.insert(guns, player.secondaryGun)
    end
    for _, gun in ipairs(guns) do
        M.AddItem(stash, {
            itype  = "weapon",
            name   = gun.name,
            icon   = "\xF0\x9F\x94\xAB",
            iw     = 2, ih = 1,
            rarity = gun.rarity or 2,
            value  = gun.value or 100,
            data   = gun,
            ammo   = gun.ammo,
            maxAmmo= gun.maxAmmo,
        })
    end
end

-- ============================================================================
-- 本地存档：保存 / 加载
-- ============================================================================

local SAVE_FILE = "stash_save.json"

--- 序列化仓库为可 JSON 编码的 table
function M.Serialize(stash)
    local items = {}
    for _, entry in ipairs(stash.inv.items) do
        -- data 字段可能含函数/循环引用，只保留可序列化的关键字段
        local dataS = nil
        if entry.data then
            local d = entry.data
            dataS = {
                key        = d.key,
                id         = d.id,
                name       = d.name,
                icon       = d.icon,
                rarity     = d.rarity,
                value      = d.value,
                slot       = d.slot,
                ammoType   = d.ammoType,
                magSize    = d.magSize,
                pellets    = d.pellets,
                damage     = d.damage,
                fireRate   = d.fireRate,
                reloadTime = d.reloadTime,
                spread     = d.spread,
                -- 装备字段
                armor      = d.armor,
                armorClass = d.armorClass,
                speedPenalty = d.speedPenalty,
                -- 消耗品字段
                effectType = d.effectType,
                healPct    = d.healPct,
                stackable  = d.stackable,
                maxStack   = d.maxStack,
                lw         = d.lw,
                lh         = d.lh,
            }
        end
        table.insert(items, {
            itype   = entry.itype,
            name    = entry.name,
            icon    = entry.icon,
            rarity  = entry.rarity,
            value   = entry.value,
            x       = entry.x,
            y       = entry.y,
            iw      = entry.iw,
            ih      = entry.ih,
            rotated = entry.rotated,
            qty     = entry.qty,
            stackKey = entry.stackKey,
            -- 武器运行时
            ammo    = entry.ammo,
            maxAmmo = entry.maxAmmo,
            reserveAmmo = entry.reserveAmmo,
            key     = entry.key,
            data    = dataS,
        })
    end
    return {
        version = 1,
        level   = stash.level,
        money   = stash.money,
        invW    = stash.inv.width,
        invH    = stash.inv.height,
        items   = items,
        ammo    = stash.ammo,  -- 已购弹药储备 {light=N, medium=N, ...}
    }
end

--- 保存仓库到本地文件
function M.Save(stash)
    local ok, json = pcall(cjson.encode, M.Serialize(stash))
    if not ok then
        print("[Stash] Save encode error:", json)
        return false
    end
    local file = File(SAVE_FILE, FILE_WRITE)
    if not file:IsOpen() then
        print("[Stash] Save file open error")
        return false
    end
    file:WriteString(json)
    file:Close()
    print("[Stash] Saved OK, money=" .. stash.money .. " items=" .. #stash.inv.items)
    return true
end

--- 从本地文件加载仓库（返回 stash 或 nil）
function M.Load()
    if not fileSystem:FileExists(SAVE_FILE) then
        print("[Stash] No save file found, starting fresh")
        return nil
    end
    local file = File(SAVE_FILE, FILE_READ)
    if not file:IsOpen() then
        print("[Stash] Load file open error")
        return nil
    end
    local raw = file:ReadString()
    file:Close()

    local ok, saveData = pcall(cjson.decode, raw)
    if not ok or not saveData then
        print("[Stash] Load decode error:", saveData)
        return nil
    end

    -- 恢复仓库结构
    local invW = saveData.invW or 10
    local invH = saveData.invH or 10
    local stash = {
        level = saveData.level or 1,
        money = saveData.money or 200,
        inv   = Inventory.New(invW, invH),
        ammo  = saveData.ammo or {},  -- 已购弹药储备
    }

    -- 恢复物品：尝试从 Data 表重建完整 data 引用
    for _, s in ipairs(saveData.items or {}) do
        local fullData = nil
        if s.data then
            -- 武器：用 key 从 Data.WEAPONS 重建
            if s.itype == "weapon" and s.data.key and Data.WEAPONS[s.data.key] then
                fullData = Data.WEAPONS[s.data.key]
            -- 装备：从 Data 表查找
            elseif s.itype == "helmet" or s.itype == "armor" or s.itype == "bag" then
                local tbl
                if s.itype == "helmet" then tbl = Data.HELMETS
                elseif s.itype == "armor" then tbl = Data.ARMORS
                elseif s.itype == "bag" then tbl = Data.BAGS
                end
                if tbl and s.data.id then
                    for _, t in ipairs(tbl) do
                        if t.id == s.data.id then fullData = t; break end
                    end
                end
            -- 消耗品：从 Data.CONSUMABLES 查找
            elseif s.itype == "consumable" and s.data.id then
                for _, t in ipairs(Data.CONSUMABLES) do
                    if t.id == s.data.id then fullData = t; break end
                end
            end
            -- 如果没找到完整引用，用存档里的精简 data
            if not fullData then fullData = s.data end
        end

        local item = {
            itype   = s.itype,
            name    = s.name,
            icon    = s.icon,
            rarity  = s.rarity,
            value   = s.value,
            qty     = s.qty,
            data    = fullData,
            key     = s.key,
            ammo    = s.ammo,
            maxAmmo = s.maxAmmo,
            reserveAmmo = s.reserveAmmo,
        }

        -- 用保存的位置直接放置（保留布局）
        if s.x and s.y then
            Inventory.PlaceItem(stash.inv, item, s.x, s.y, s.rotated or false)
        else
            Inventory.AutoPlace(stash.inv, item)
        end
    end

    print("[Stash] Loaded OK, money=" .. stash.money .. " items=" .. #stash.inv.items)
    return stash
end

return M
