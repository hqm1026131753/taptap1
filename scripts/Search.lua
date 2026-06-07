-- ============================================================================
-- Search.lua — 塔可夫风格容器搜索系统
-- ============================================================================
-- 玩家靠近容器按 E → 搜索进度条 → 打开双面板（容器/背包）
-- 支持：点击转移、取全部、关闭
-- ============================================================================
local Inventory = require("Inventory")

local M = {}

-- ----------------------------------------------------------------------------
-- 搜索状态对象
-- isSearching : 进度条阶段
-- isOpen      : 面板已打开
-- progress    : 已搜索时间(s)
-- duration    : 需要的总时间(s)
-- container   : 当前容器 { loot={}, searched, w, h, label, x, y }
-- containerInv: GridInventory（搜索完成后初始化）
-- ----------------------------------------------------------------------------

function M.New()
    return {
        isSearching    = false,
        isOpen         = false,
        progress       = 0,
        duration       = 1.5,
        container      = nil,
        containerInv   = nil,
        -- 搜索动画用：物品逐一揭示
        lootPreview    = nil,   -- { name, icon, rarity, value } 列表（搜索开始时填充）
        discoveredCount = 0,    -- 当前已揭示的物品数量
    }
end

-- 获取容器 label
local function containerLabel(container)
    if container.isBoss then return "Boss战利品" end
    if container.isEnemy then return "敌人背包" end
    if container.elite then return "陈列室" end
    return "木箱"
end

-- 把容器内物品填入 GridInventory
local function buildContainerInv(container)
    local loot = container.loot or {}
    -- 容器网格：6×4（与技能文档一致）
    local cw = container.cw or 6
    local ch = container.ch or 4
    local inv = Inventory.New(cw, ch)
    for _, item in ipairs(loot) do
        Inventory.AutoPlace(inv, item)
    end
    return inv
end

-- 根据稀有度决定单件物品加载耗时（秒）
local RARITY_LOAD_TIME = { 0.5, 1.0, 1.5, 2.0, 2.5 }
local function itemLoadTime(item)
    local r = item.rarity or 1
    return RARITY_LOAD_TIME[math.max(1, math.min(5, r))]
end

-- ----------------------------------------------------------------------------
-- API
-- ----------------------------------------------------------------------------

-- 开始搜索一个容器（塔可夫逻辑：立即打开面板，物品逐一加载进格子）
function M.StartSearch(ss, container)
    if ss.isOpen then return end
    -- 已搜过的箱子：优先用上次关闭时保存的 inv 快照（保留取走物品后的状态）
    if container._fastOpen then
        local box = container._box
        ss.isSearching     = false
        ss.isOpen          = true
        ss.progress        = 0
        ss.duration        = 0
        ss.container       = container
        -- 有缓存直接复用，没有则从 loot 重建（兜底）
        if box and box._cachedInv then
            ss.containerInv = box._cachedInv
        else
            ss.containerInv = buildContainerInv(container)
        end
        ss.pendingItems    = {}
        ss.loadTimer       = 0
        ss.loadInterval    = 0
        return
    end

    -- 新容器：立即开面板，containerInv 空网格，物品排队逐一加载
    local cw = container.cw or 6
    local ch = container.ch or 4
    local loot = container.loot or {}

    -- 按稀有度计算每件物品的加载耗时，总时长为所有物品耗时之和
    local pendingItems = {}
    local totalTime = 0
    for _, item in ipairs(loot) do
        local t = itemLoadTime(item)
        totalTime = totalTime + t
        table.insert(pendingItems, { item = item, delay = t })
    end
    if totalTime == 0 then totalTime = 0.1 end  -- 空容器兜底

    ss.isSearching  = true   -- 标记为"搜索中"以便渲染层显示加载状态
    ss.isOpen       = true   -- 立即打开面板
    ss.progress     = 0
    ss.duration     = totalTime
    ss.container    = container
    ss.containerInv = Inventory.New(cw, ch)   -- 空网格，等物品逐一填入
    ss.pendingItems = pendingItems  -- 每项 { item, delay }
    ss.loadTimer    = 0
    ss.loadInterval = 0             -- 已废弃，保留字段避免渲染层读取报错
    -- 旧字段兼容
    ss.lootPreview     = nil
    ss.discoveredCount = 0
end

-- 每帧更新（dt 秒）；所有物品加载完成返回 true
function M.Update(ss, dt)
    if not ss.isSearching then return false end
    ss.progress  = ss.progress + dt
    ss.loadTimer = ss.loadTimer + dt

    -- 逐一检查队首物品：loadTimer 达到该物品的 delay 后放入 containerInv
    while #ss.pendingItems > 0 do
        local head = ss.pendingItems[1]
        -- 兼容旧格式（直接是 item 对象）和新格式（{ item, delay }）
        local headDelay = type(head) == "table" and head.delay or 0
        if ss.loadTimer >= headDelay then
            ss.loadTimer = ss.loadTimer - headDelay
            local entry = table.remove(ss.pendingItems, 1)
            local realItem = (type(entry) == "table" and entry.delay ~= nil) and entry.item or entry
            Inventory.AutoPlace(ss.containerInv, realItem)
        else
            break
        end
    end

    if ss.progress >= ss.duration then
        ss.progress    = ss.duration
        ss.isSearching = false
        -- 确保剩余物品全部放入（避免计时误差丢失）
        for _, entry in ipairs(ss.pendingItems) do
            local realItem = (type(entry) == "table" and entry.delay ~= nil) and entry.item or entry
            Inventory.AutoPlace(ss.containerInv, realItem)
        end
        ss.pendingItems = {}
        -- 首次加载完成：缓存 inv 并标记已搜索（下次打开跳过加载动画）
        local box = ss.container and ss.container._box
        if box then
            box._cachedInv = ss.containerInv
            box.opened     = true
        end
        return true
    end
    return false
end

-- 中断搜索（离开容器范围）
function M.CancelSearch(ss)
    if ss.isSearching then
        ss.isSearching = false
        ss.progress    = 0
        ss.container   = nil
    end
end

-- 关闭面板（同时把当前 inv 快照写回 box，下次打开直接复用）
function M.Close(ss)
    if ss.isSearching then
        -- 加载途中强行关闭：丢弃进度，下次重新加载
        -- 不缓存、不标记 opened，确保下次搜索重播加载动画
    else
        -- 正常关闭（加载已完成）：保存快照
        local box = ss.container and ss.container._box
        if box and box.opened and ss.containerInv then
            box._cachedInv = ss.containerInv
        end
    end
    ss.isSearching  = false
    ss.pendingItems = {}
    ss.isOpen       = false
    ss.containerInv = nil
    ss.container    = nil
end

-- 从玩家背包放入容器（返回 true/false）
function M.PutItem(ss, itemId, playerInv)
    if not ss.isOpen or not ss.containerInv then return false end
    local entry = Inventory.RemoveItem(playerInv, itemId)
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
    local placed = Inventory.AutoPlace(ss.containerInv, item)
    if placed then return true end
    -- 放不进去，还回背包
    Inventory.AutoPlace(playerInv, item)
    return false
end

-- 面板格子命中测试（用于鼠标点击）
-- side="container"|"player"，mx/my 是鼠标屏幕坐标
-- 返回 entry 或 nil
function M.HitTestPanel(ss, playerInv, side, mx, my, panelLayout)
    local inv = (side == "container") and ss.containerInv or playerInv
    if not inv then return nil end
    local layout = panelLayout[side]
    if not layout then return nil end
    local cs = layout.cellSize
    local ox = layout.gridX
    local oy = layout.gridY
    local gx = math.floor((mx - ox) / cs) + 1
    local gy = math.floor((my - oy) / cs) + 1
    return Inventory.HitTest(inv, gx, gy)
end

return M
