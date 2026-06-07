-- ============================================================================
-- SkillTree.lua — 局外技能树系统（数据+逻辑）
-- 三条分支（战斗/搜刮/生存），共 24 个节点
-- 升级点通过通关地牢获得，材料从局内带出
-- ============================================================================

local M = {}

-- ============================================================================
-- 分支定义
-- ============================================================================
M.BRANCHES = {
    { id = "combat",   name = "战斗",  icon = "⚔️", material = "废铁",      materialIcon = "⚙️" },
    { id = "looting",  name = "搜刮",  icon = "💰", material = "史莱姆粘液", materialIcon = "🧪" },
    { id = "survival", name = "生存",  icon = "🛡️", material = "破布",      materialIcon = "🧻" },
}

-- ============================================================================
-- 节点定义
-- type: "normal"(菱形) / "core"(六角形)
-- depth: 1~8 (决定材料消耗)
-- cost: 技能点消耗
-- materialCost: 材料消耗
-- requires: 前置节点 id 列表
-- branch: 0-indexed 分支 (position in left → mid → right split)
-- ============================================================================

-- 材料消耗查表
local function GetMaterialCost(depth, nodeType)
    if nodeType == "core" then
        if depth <= 4 then return 15 end
        return 30
    else
        if depth <= 2 then return 5 end
        if depth <= 4 then return 10 end
        if depth <= 6 then return 15 end
        return 25
    end
end

-- 战斗分支节点
M.COMBAT_NODES = {
    { id = "c1", name = "基础强化",   type = "normal", depth = 1, cost = 12, effect = "伤害 +5%",           stat = "damageBonus",    value = 0.05, requires = {} },
    { id = "c2", name = "快速换弹",   type = "normal", depth = 2, cost = 12, effect = "换弹速度 +10%",      stat = "reloadSpeed",    value = 0.10, requires = {"c1"} },
    { id = "c3", name = "精准射击",   type = "core",   depth = 3, cost = 15, effect = "散布 -15%",          stat = "spreadReduction",value = 0.15, requires = {"c2"} },
    { id = "c4l",name = "火力压制",   type = "normal", depth = 4, cost = 12, effect = "伤害 +8%",           stat = "damageBonus",    value = 0.08, requires = {"c3"}, side = "left" },
    { id = "c4r",name = "弱点锁定",   type = "normal", depth = 4, cost = 12, effect = "暴击率 +5%",         stat = "critChance",     value = 0.05, requires = {"c3"}, side = "right" },
    { id = "c6", name = "致命打击",   type = "normal", depth = 6, cost = 12, effect = "暴击伤害 +25%",      stat = "critDamage",     value = 0.25, requires = {"c4l", "c4r"} },
    { id = "c7", name = "武器精通",   type = "core",   depth = 7, cost = 15, effect = "所有武器伤害 +10%\n高稀有度武器出现率 +10%", stat = "weaponMastery", value = 0.10, requires = {"c6"} },
    { id = "c8", name = "百战精锐",   type = "normal", depth = 8, cost = 12, effect = "伤害 +15%",          stat = "damageBonus",    value = 0.15, requires = {"c7"} },
}

-- 搜刮分支节点
M.LOOTING_NODES = {
    { id = "l1", name = "高效搜刮",   type = "normal", depth = 1, cost = 12, effect = "搜索速度 +20%",      stat = "searchSpeed",    value = 0.20, requires = {} },
    { id = "l2", name = "扩容背包",   type = "normal", depth = 2, cost = 12, effect = "背包格 +2",          stat = "bagSlots",       value = 2,    requires = {"l1"} },
    { id = "l3", name = "战场缴获",   type = "core",   depth = 3, cost = 15, effect = "阵亡后保留最贵1件物品", stat = "deathSave",    value = 1,    requires = {"l2"} },
    { id = "l4l",name = "贪婪",       type = "normal", depth = 4, cost = 12, effect = "商店出售价值 +10%",   stat = "sellBonus",      value = 0.10, requires = {"l3"}, side = "left" },
    { id = "l4r",name = "轻装疾行",   type = "normal", depth = 4, cost = 12, effect = "移动速度 +20%",      stat = "moveSpeed",      value = 0.20, requires = {"l3"}, side = "right" },
    { id = "l6", name = "快速搜身",   type = "normal", depth = 6, cost = 12, effect = "搜索速度 +40%",      stat = "searchSpeed",    value = 0.40, requires = {"l4l", "l4r"} },
    { id = "l7", name = "保险箱",     type = "core",   depth = 7, cost = 15, effect = "获得2个保险箱格子\n阵亡不丢失", stat = "safeSlots", value = 2, requires = {"l6"} },
    { id = "l8", name = "满载而归",   type = "normal", depth = 8, cost = 12, effect = "背包格 +4",          stat = "bagSlots",       value = 4,    requires = {"l7"} },
}

-- 生存分支节点
M.SURVIVAL_NODES = {
    { id = "s1", name = "体格强化",   type = "normal", depth = 1, cost = 12, effect = "HP +20",             stat = "hpBonus",        value = 20,   requires = {} },
    { id = "s2", name = "战术护甲",   type = "normal", depth = 2, cost = 12, effect = "护甲 +8",            stat = "armorBonus",     value = 8,    requires = {"s1"} },
    { id = "s3", name = "急救专家",   type = "core",   depth = 3, cost = 15, effect = "医疗速度 +50%\n医疗回复 +20%", stat = "healBoost", value = 0.50, requires = {"s2"} },
    { id = "s4l",name = "钢铁之躯",   type = "normal", depth = 4, cost = 12, effect = "HP +40",             stat = "hpBonus",        value = 40,   requires = {"s3"}, side = "left" },
    { id = "s4r",name = "减震",       type = "normal", depth = 4, cost = 12, effect = "受暴击伤害 -20%",    stat = "critResist",     value = 0.20, requires = {"s3"}, side = "right" },
    { id = "s6", name = "自动愈合",   type = "normal", depth = 6, cost = 12, effect = "每10秒回复2HP",      stat = "regen",          value = 2,    requires = {"s4l", "s4r"} },
    { id = "s7", name = "不屈意志",   type = "core",   depth = 7, cost = 15, effect = "额外一条命\n致命伤后保留1HP", stat = "extraLife", value = 1, requires = {"s6"} },
    { id = "s8", name = "战场老兵",   type = "normal", depth = 8, cost = 12, effect = "HP +60 护甲 +12",    stat = "veteranBonus",   value = 1,    requires = {"s7"} },
}

-- 所有节点汇总表（按分支索引）
M.ALL_NODES = {
    combat   = M.COMBAT_NODES,
    looting  = M.LOOTING_NODES,
    survival = M.SURVIVAL_NODES,
}

-- 填充 materialCost（根据 depth 和 type 自动计算）
for branchId, nodes in pairs(M.ALL_NODES) do
    for _, node in ipairs(nodes) do
        node.materialCost = GetMaterialCost(node.depth, node.type)
        node.branch = branchId
    end
end

-- ============================================================================
-- 玩家技能树状态
-- ============================================================================

--- 创建空技能树存档
function M.NewState()
    return {
        skillPoints = 0,             -- 当前可用技能点
        totalPointsEarned = 0,       -- 总共获得的技能点（统计用）
        materials = {
            combat   = 0,            -- 废铁
            looting  = 0,            -- 史莱姆粘液
            survival = 0,            -- 破布
        },
        unlocked = {},               -- { [nodeId] = true } 已解锁节点
    }
end

-- ============================================================================
-- 升级点获取（层数 → 点数）
-- ============================================================================

--- 计算进入某层获得的技能点
---@param floor number 当前进入的层数(1~20)
---@return number
function M.GetPointsForFloor(floor)
    if floor >= 11 then return 2 end
    return 1
end

-- ============================================================================
-- 材料名 → 分支映射
-- ============================================================================
M.MATERIAL_TO_BRANCH = {
    ["废铁"]       = "combat",
    ["史莱姆粘液"] = "looting",
    ["破布"]       = "survival",
}

-- 物品 name → 材料类型
M.ITEM_NAME_TO_MATERIAL = {
    ["废铁"]       = "combat",
    ["史莱姆粘液"] = "looting",
    ["破布"]       = "survival",
}

-- ============================================================================
-- 查询与操作
-- ============================================================================

--- 检查节点前置是否全部解锁
---@param state table 技能树状态
---@param node table 节点定义
---@return boolean
function M.PrereqsMet(state, node)
    if #node.requires == 0 then return true end
    for _, reqId in ipairs(node.requires) do
        if not state.unlocked[reqId] then return false end
    end
    return true
end

--- 检查是否可解锁某节点
---@param state table 技能树状态
---@param node table 节点定义
---@return boolean canUnlock
---@return string|nil reason 不能解锁的原因
function M.CanUnlock(state, node)
    -- 已解锁
    if state.unlocked[node.id] then return false, "已解锁" end
    -- 前置
    if not M.PrereqsMet(state, node) then return false, "前置未完成" end
    -- 技能点
    if state.skillPoints < node.cost then return false, "技能点不足" end
    -- 材料
    local matCount = state.materials[node.branch] or 0
    if matCount < node.materialCost then return false, "材料不足" end
    return true, nil
end

--- 解锁节点（扣除消耗）
---@param state table 技能树状态
---@param node table 节点定义
---@return boolean success
function M.Unlock(state, node)
    local ok, _ = M.CanUnlock(state, node)
    if not ok then return false end
    state.skillPoints = state.skillPoints - node.cost
    state.materials[node.branch] = state.materials[node.branch] - node.materialCost
    state.unlocked[node.id] = true
    return true
end

--- 获取节点状态
---@param state table
---@param node table
---@return string "unlocked"|"available"|"locked"
function M.GetNodeStatus(state, node)
    if state.unlocked[node.id] then return "unlocked" end
    if M.PrereqsMet(state, node) then return "available" end
    return "locked"
end

-- ============================================================================
-- 被动效果汇总（应用到玩家）
-- ============================================================================

--- 获取所有已解锁节点的被动加成汇总
---@param state table 技能树状态
---@return table bonuses
function M.GetBonuses(state)
    local bonuses = {
        damageBonus     = 0,    -- 伤害加成百分比
        reloadSpeed     = 0,    -- 换弹速度加成百分比
        spreadReduction = 0,    -- 散布减少百分比
        critChance      = 0,    -- 暴击率加成
        critDamage      = 0,    -- 暴击伤害加成
        weaponMastery   = 0,    -- 武器精通（伤害+稀有度概率）
        searchSpeed     = 0,    -- 搜索速度加成百分比
        bagSlots        = 0,    -- 额外背包格
        deathSave       = 0,    -- 阵亡保留物品数
        sellBonus       = 0,    -- 卖出价值加成
        moveSpeed       = 0,    -- 移动速度加成百分比
        safeSlots       = 0,    -- 保险箱格子
        hpBonus         = 0,    -- HP 加成
        armorBonus      = 0,    -- 护甲加成
        healBoost       = 0,    -- 医疗加成
        critResist      = 0,    -- 暴击抗性
        regen           = 0,    -- 每10秒回血
        extraLife       = 0,    -- 额外生命
        veteranBonus    = 0,    -- 战场老兵(HP+60,护甲+12)
    }
    for branchId, nodes in pairs(M.ALL_NODES) do
        for _, node in ipairs(nodes) do
            if state.unlocked[node.id] then
                local key = node.stat
                if bonuses[key] ~= nil then
                    bonuses[key] = bonuses[key] + node.value
                end
            end
        end
    end
    -- 战场老兵特殊处理：HP+60 护甲+12
    if bonuses.veteranBonus > 0 then
        bonuses.hpBonus = bonuses.hpBonus + 60
        bonuses.armorBonus = bonuses.armorBonus + 12
    end
    return bonuses
end

-- ============================================================================
-- 从仓库物品中提取材料计数（用于展示和结算）
-- ============================================================================

--- 统计仓库中某种材料的数量
---@param stash table 仓库对象
---@param materialName string "废铁"/"史莱姆粘液"/"破布"
---@return number
function M.CountMaterialInStash(stash, materialName)
    local total = 0
    if not stash or not stash.inv or not stash.inv.items then return 0 end
    for _, entry in ipairs(stash.inv.items) do
        if entry.name == materialName then
            total = total + (entry.qty or 1)
        end
    end
    return total
end

--- 从仓库中扣除材料（消耗堆叠物品）
---@param stash table
---@param materialName string
---@param amount number
---@return boolean success
function M.ConsumeMaterialFromStash(stash, materialName, amount)
    if not stash or not stash.inv or not stash.inv.items then return false end
    local remaining = amount
    -- 从后往前遍历，方便删除
    for i = #stash.inv.items, 1, -1 do
        if remaining <= 0 then break end
        local entry = stash.inv.items[i]
        if entry.name == materialName then
            local qty = entry.qty or 1
            if qty <= remaining then
                remaining = remaining - qty
                -- 移除整个条目并释放网格
                local Inventory = require("Inventory")
                Inventory.RemoveItem(stash.inv, entry)
            else
                entry.qty = qty - remaining
                remaining = 0
            end
        end
    end
    return remaining <= 0
end

-- ============================================================================
-- 存档 Save/Load
-- ============================================================================
local SAVE_FILE = "skilltree_save.json"

--- 序列化
function M.Serialize(state)
    -- unlocked 是 {[id]=true} → 转为数组
    local unlockedList = {}
    for id, _ in pairs(state.unlocked) do
        table.insert(unlockedList, id)
    end
    return {
        version           = 1,
        skillPoints       = state.skillPoints,
        totalPointsEarned = state.totalPointsEarned,
        materials         = state.materials,
        unlocked          = unlockedList,
    }
end

--- 反序列化
function M.Deserialize(data)
    local state = M.NewState()
    state.skillPoints       = data.skillPoints or 0
    state.totalPointsEarned = data.totalPointsEarned or 0
    if data.materials then
        state.materials.combat   = data.materials.combat or 0
        state.materials.looting  = data.materials.looting or 0
        state.materials.survival = data.materials.survival or 0
    end
    -- unlocked 从数组恢复为 set
    if data.unlocked then
        for _, id in ipairs(data.unlocked) do
            state.unlocked[id] = true
        end
    end
    return state
end

--- 保存技能树到本地
function M.Save(state)
    local ok, json = pcall(cjson.encode, M.Serialize(state))
    if not ok then
        print("[SkillTree] Save encode error:", json)
        return false
    end
    local file = File(SAVE_FILE, FILE_WRITE)
    if not file:IsOpen() then
        print("[SkillTree] Save file open error")
        return false
    end
    file:WriteString(json)
    file:Close()
    print("[SkillTree] Saved OK, points=" .. state.skillPoints)
    return true
end

--- 从本地加载技能树（返回 state 或 nil）
function M.Load()
    if not fileSystem:FileExists(SAVE_FILE) then
        print("[SkillTree] No save file, starting fresh")
        return nil
    end
    local file = File(SAVE_FILE, FILE_READ)
    if not file:IsOpen() then
        print("[SkillTree] Load file open error")
        return nil
    end
    local raw = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, raw)
    if not ok or not data then
        print("[SkillTree] Load decode error:", data)
        return nil
    end
    return M.Deserialize(data)
end

-- ============================================================================
-- 统计信息
-- ============================================================================

--- 获取某分支已解锁节点数
function M.GetBranchProgress(state, branchId)
    local nodes = M.ALL_NODES[branchId]
    if not nodes then return 0, 0 end
    local unlocked = 0
    for _, node in ipairs(nodes) do
        if state.unlocked[node.id] then unlocked = unlocked + 1 end
    end
    return unlocked, #nodes
end

--- 获取总进度
function M.GetTotalProgress(state)
    local total, unlocked = 0, 0
    for _, nodes in pairs(M.ALL_NODES) do
        for _, node in ipairs(nodes) do
            total = total + 1
            if state.unlocked[node.id] then unlocked = unlocked + 1 end
        end
    end
    return unlocked, total
end

return M
