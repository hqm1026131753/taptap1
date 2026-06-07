-- ============================================================================
-- Inventory.lua — 网格背包系统（塔可夫风格）
-- 背包是 w×h 的二维网格，每个物品占据 iw×ih 格
-- 支持旋转（90°）、自动寻空位
-- ============================================================================

local M = {}

-- ----------------------------------------------------------------------------
-- 物品网格尺寸表（文档对齐版）
-- 键为武器 key / 装备 slot / 战利品名称
-- ----------------------------------------------------------------------------
M.ITEM_SIZES = {
    -- ---- 武器 ----
    Glock        = { w=1, h=2 },
    M1911        = { w=1, h=2 },
    DesertEagle  = { w=1, h=2 },
    G18          = { w=1, h=2 },
    P90          = { w=1, h=3 },
    MP5          = { w=1, h=3 },
    UZI          = { w=1, h=3 },
    MP7          = { w=1, h=3 },
    M16          = { w=1, h=3 },
    AKM          = { w=1, h=3 },
    AUG          = { w=1, h=3 },
    M870         = { w=1, h=4 },
    M1014        = { w=1, h=4 },
    AWM          = { w=1, h=5 },
    R93          = { w=1, h=5 },
    PKM          = { w=1, h=4 },
    M250         = { w=1, h=4 },
    -- ---- 装备（占用背包时尺寸，2×2）----
    helmet       = { w=2, h=2 },
    armor        = { w=2, h=2 },
    bag          = { w=2, h=2 },
    -- ---- 战利品（按名称精确查找）----
    -- 1×1 垃圾
    ["破布"]     = { w=1, h=1 },
    ["废铁"]     = { w=1, h=1 },
    ["旧螺丝"]   = { w=1, h=1 },
    ["瓶装水"]   = { w=1, h=1 },
    -- 1×1 普通
    ["急救包"]   = { w=1, h=1 },
    ["金戒指"]   = { w=1, h=1 },
    ["银项链"]   = { w=1, h=1 },
    ["电子表"]   = { w=1, h=1 },
    ["金质指南针"] = { w=1, h=1 },
    -- 3级：部分1×1，部分1×2
    ["金链子"]   = { w=1, h=1 },
    ["夜视仪"]   = { w=2, h=1 },
    ["小熊玩偶"] = { w=1, h=2 },
    ["翡翠手镯"] = { w=1, h=1 },
    ["钻石"]     = { w=1, h=1 },
    ["古董怀表"] = { w=1, h=2 },
    ["金条"]     = { w=1, h=2 },
    -- 4级 史诗 2×2
    ["古董花瓶"] = { w=2, h=2 },
    ["金佛像"]   = { w=2, h=2 },
    ["名人字画·山水"] = { w=2, h=2 },
    ["名人字画·人物"] = { w=2, h=2 },
    ["宝石王冠"] = { w=2, h=2 },
    -- 5级 传说
    ["遗物圣器"] = { w=2, h=2 },
    ["VIP卡"]   = { w=1, h=1 },
}

-- ----------------------------------------------------------------------------
-- 堆叠支持
-- ----------------------------------------------------------------------------

-- 获取物品的堆叠键（相同键可合并）
-- 消耗品用 id，战利品用 name
function M.GetStackKey(item)
    local d = item.data or item
    if not d.stackable then return nil end
    -- 消耗品按 id 堆叠
    if d.id then return "consumable:" .. d.id end
    -- 战利品按 name 堆叠
    local nm = item.name or d.name
    if nm then return "loot:" .. nm end
    return nil
end

-- 获取物品最大堆叠数
function M.GetMaxStack(item)
    local d = item.data or item
    return d.maxStack or 1
end

-- 在背包中查找可堆叠的同类物品条目（未满栈）
function M.FindStackable(inv, item)
    local key = M.GetStackKey(item)
    if not key then return nil end
    local max = M.GetMaxStack(item)
    for _, entry in ipairs(inv.items) do
        if entry.stackKey == key and (entry.qty or 1) < max then
            return entry
        end
    end
    return nil
end

-- 根据物品获取尺寸
-- 查找优先级：1) 武器 key  2) 战利品 name  3) 战利品 data.lw/lh  4) 装备 slot  5) 默认1×1
function M.GetSize(item)
    local itype = item.itype or "valuable"

    -- 武器按 key
    if itype == "weapon" then
        local key = (item.data and item.data.key) or itype
        local s = M.ITEM_SIZES[key]
        return s and s.w or 1, s and s.h or 2
    end

    -- 装备按 slot
    if itype == "helmet" or itype == "armor" or itype == "bag" then
        local s = M.ITEM_SIZES[itype]
        return s.w, s.h
    end

    -- 战利品：先查 name，再看 data.lw/lh
    if itype == "loot" then
        local nm = item.name or (item.data and item.data.name)
        if nm then
            local s = M.ITEM_SIZES[nm]
            if s then return s.w, s.h end
        end
        -- 使用 data 里预存的 lw/lh（Data.lua 已经写入）
        local d = item.data
        if d and d.lw then return d.lw, d.lh end
        -- 按稀有度兜底
        local rarity = item.rarity or (d and d.rarity) or 1
        if rarity >= 4 then return 2, 2 end
        return 1, 1
    end

    return 1, 1
end

-- ----------------------------------------------------------------------------
-- GridInventory
-- ----------------------------------------------------------------------------
-- grid[row][col] = itemRef or nil
-- items = { {id, itype, data, x, y, iw, ih, rotated, rarity, icon, name, value} }

function M.New(width, height)
    local inv = {
        width  = width,
        height = height,
        grid   = {},
        items  = {},
        _nextId = 1,
    }
    for row = 1, height do
        inv.grid[row] = {}
        for col = 1, width do
            inv.grid[row][col] = nil
        end
    end
    return inv
end

-- 能否放下（不检查 rotated，iw/ih 已经是放置后的有效尺寸）
local function canPlace(inv, iw, ih, x, y)
    if x < 1 or y < 1 then return false end
    if x + iw - 1 > inv.width then return false end
    if y + ih - 1 > inv.height then return false end
    for row = y, y + ih - 1 do
        for col = x, x + iw - 1 do
            if inv.grid[row][col] ~= nil then return false end
        end
    end
    return true
end

-- 在 grid 上标记/清除
local function markGrid(inv, entry, v)
    local iw = entry.rotated and entry.ih or entry.iw
    local ih = entry.rotated and entry.iw or entry.ih
    for row = entry.y, entry.y + ih - 1 do
        for col = entry.x, entry.x + iw - 1 do
            inv.grid[row][col] = v
        end
    end
end

-- 自动寻找第一个能放下的位置（尝试原始方向和旋转）
function M.FindSpace(inv, iw, ih)
    -- 先试原始方向
    for y = 1, inv.height - ih + 1 do
        for x = 1, inv.width - iw + 1 do
            if canPlace(inv, iw, ih, x, y) then
                return x, y, false
            end
        end
    end
    -- 再试旋转（仅当 iw~=ih 时才有意义）
    if iw ~= ih then
        for y = 1, inv.height - iw + 1 do
            for x = 1, inv.width - ih + 1 do
                if canPlace(inv, ih, iw, x, y) then
                    return x, y, true
                end
            end
        end
    end
    return nil, nil, false
end

-- 放置物品（返回 entry 或 nil）
function M.PlaceItem(inv, item, x, y, rotated)
    local iw0, ih0 = M.GetSize(item)
    local iw = rotated and ih0 or iw0
    local ih = rotated and iw0 or ih0
    if not canPlace(inv, iw, ih, x, y) then return nil end

    local entry = {
        id      = inv._nextId,
        itype   = item.itype,
        data    = item.data,
        name    = item.name  or (item.data and item.data.name) or "?",
        icon    = item.icon  or (item.data and item.data.icon) or "📦",
        rarity  = item.rarity or (item.data and item.data.rarity) or 1,
        value   = item.value or (item.data and item.data.value) or 0,
        x       = x, y = y,
        iw      = iw0, ih = ih0,  -- 原始尺寸
        rotated = rotated or false,
        stackKey = M.GetStackKey(item),
        qty      = item.qty or 1,
    }
    inv._nextId = inv._nextId + 1
    table.insert(inv.items, entry)
    markGrid(inv, entry, entry)
    return entry
end

-- 自动放置（优先堆叠，再找空位）
function M.AutoPlace(inv, item)
    -- 尝试堆叠到已有同类物品
    local existing = M.FindStackable(inv, item)
    if existing then
        existing.qty = (existing.qty or 1) + (item.qty or 1)
        return existing
    end
    -- 无法堆叠，寻找新空位
    local iw, ih = M.GetSize(item)
    local x, y, rotated = M.FindSpace(inv, iw, ih)
    if not x then return nil end
    return M.PlaceItem(inv, item, x, y, rotated)
end

-- 移除物品（按 id）；可选 amount 参数支持部分移除堆叠物品
-- 返回被移除的 entry（若是部分移除则 entry.qty 已扣减，返回的是仍存在的 entry）
function M.RemoveItem(inv, itemId, amount)
    for i, entry in ipairs(inv.items) do
        if entry.id == itemId then
            local qty = entry.qty or 1
            local toRemove = amount or qty  -- 默认全部移除
            if toRemove >= qty then
                -- 全部移除
                markGrid(inv, entry, nil)
                table.remove(inv.items, i)
                return entry
            else
                -- 部分移除（堆叠数量减少）
                entry.qty = qty - toRemove
                return entry
            end
        end
    end
    return nil
end

-- 移除一个堆叠物品（按 stackKey 查找，扣减1个；数量归零则移除条目）
function M.RemoveOne(inv, stackKey)
    for i, entry in ipairs(inv.items) do
        if entry.stackKey == stackKey then
            local qty = entry.qty or 1
            if qty <= 1 then
                markGrid(inv, entry, nil)
                table.remove(inv.items, i)
                return entry
            else
                entry.qty = qty - 1
                return entry
            end
        end
    end
    return nil
end

-- 格子命中测试（返回 entry 或 nil）
function M.HitTest(inv, gx, gy)
    if gx < 1 or gy < 1 or gx > inv.width or gy > inv.height then return nil end
    return inv.grid[gy][gx]
end

-- 剩余格子数
function M.FreeSlots(inv)
    local used = 0
    for _, e in ipairs(inv.items) do
        local iw = e.rotated and e.ih or e.iw
        local ih = e.rotated and e.iw or e.ih
        used = used + iw * ih
    end
    return inv.width * inv.height - used
end

-- 总价值（堆叠物品按 qty 累乘）
function M.TotalValue(inv)
    local v = 0
    for _, e in ipairs(inv.items) do
        v = v + (e.value or 0) * (e.qty or 1)
    end
    return v
end

-- 克隆一个背包到更大尺寸（换包时迁移物品）
function M.Resize(inv, newW, newH)
    local newInv = M.New(newW, newH)
    local overflow = {}  -- 放不下的物品列表
    for _, entry in ipairs(inv.items) do
        -- 还原成 item 格式（保留 qty）
        local item = { itype=entry.itype, data=entry.data, name=entry.name,
                       icon=entry.icon, rarity=entry.rarity, value=entry.value,
                       qty=entry.qty }
        if not M.AutoPlace(newInv, item) then
            overflow[#overflow + 1] = item
        end
    end
    return newInv, overflow
end

-- ----------------------------------------------------------------------------
-- 背包尺寸配置（对应装备 bag 的 id 字段）
-- ----------------------------------------------------------------------------
M.BAG_SIZES = {
    pockets = { w=4, h=3, name="口袋" },      -- 默认无包（上移一档，原小背包尺寸）
    small   = { w=5, h=4, name="小背包" },    -- 原中型背包尺寸
    medium  = { w=6, h=5, name="中型背包" },  -- 原大型背包尺寸
    large   = { w=7, h=5, name="大型军用背包" }, -- 宽型军用背包
    medic   = { w=6, h=7, name="野战医疗包" }, -- 高型医疗背包
    assault = { w=7, h=8, name="突击背包" },  -- 上移一档后最大号
}

-- 根据 bag 装备的 id 决定背包型号（优先用 id，兜底用稀有度）
function M.BagSizeKey(bagItem)
    if not bagItem then return "pockets" end
    if bagItem.id then return bagItem.id end
    -- 兜底：按稀有度
    local rarity = bagItem.rarity or 1
    if rarity >= 4 then return "assault"
    elseif rarity == 3 then return "large"
    elseif rarity == 2 then return "medium"
    else return "small" end
end

-- ----------------------------------------------------------------------------
-- 自动整理：回溯 + 旋转 算法（二维矩形装箱）
-- 大件优先 + 回溯搜索最优布局，空间利用率远优于简单贪心
-- ----------------------------------------------------------------------------
function M.AutoSort(inv)
    -- 收集所有物品快照（保留 qty）
    local snapshot = {}
    for _, entry in ipairs(inv.items) do
        local iw, ih = entry.iw, entry.ih
        table.insert(snapshot, {
            itype  = entry.itype,
            data   = entry.data,
            name   = entry.name,
            icon   = entry.icon,
            rarity = entry.rarity or 1,
            value  = entry.value or 0,
            qty    = entry.qty,
            iw     = iw,
            ih     = ih,
            area   = iw * ih,
        })
    end

    local rows = inv.height
    local cols = inv.width

    -- 排序：面积降序 → 稀有度降序 → 类型优先级 → 名称
    local ORDER = { weapon=0, helmet=1, armor=1, bag=1, loot=2 }
    table.sort(snapshot, function(a, b)
        if a.area ~= b.area then return a.area > b.area end
        if a.rarity ~= b.rarity then return a.rarity > b.rarity end
        local oa = ORDER[a.itype] or 3
        local ob = ORDER[b.itype] or 3
        if oa ~= ob then return oa < ob end
        return (a.name or "") < (b.name or "")
    end)

    -- 工作网格（nil=空）
    local grid = {}
    for r = 1, rows do
        grid[r] = {}
        for c = 1, cols do
            grid[r][c] = nil
        end
    end

    -- 辅助：检查能否放置
    local function canPlaceAt(r, c, w, h)
        if r + h - 1 > rows or c + w - 1 > cols then return false end
        for rr = r, r + h - 1 do
            for cc = c, c + w - 1 do
                if grid[rr][cc] then return false end
            end
        end
        return true
    end

    -- 辅助：在 grid 上标记/清除
    local function mark(r, c, w, h, val)
        for rr = r, r + h - 1 do
            for cc = c, c + w - 1 do
                grid[rr][cc] = val
            end
        end
    end

    -- 存储最优解
    local bestPlacements = nil  -- { {index, r, c, rotated}, ... }
    local bestPlaced = 0
    local bestValue = 0
    local searchedNodes = 0
    local MAX_NODES = 80000  -- 搜索上限（防止卡顿）

    -- 当前放置记录
    local placements = {}

    -- 回溯搜索
    local function backtrack(index, placedCount, totalValue)
        searchedNodes = searchedNodes + 1
        if searchedNodes > MAX_NODES then return end

        -- 剪枝：剩余物品全放下也超不过当前最优
        local remain = 0
        for i = index, #snapshot do remain = remain + (snapshot[i].value or 0) * (snapshot[i].qty or 1) end
        if placedCount + (#snapshot - index + 1) < bestPlaced then return end

        if index > #snapshot then
            if placedCount > bestPlaced or
               (placedCount == bestPlaced and totalValue > bestValue) then
                bestPlaced = placedCount
                bestValue = totalValue
                bestPlacements = {}
                for i = 1, #placements do bestPlacements[i] = placements[i] end
            end
            return
        end

        local item = snapshot[index]
        local iw, ih = item.iw, item.ih
        local orientations = { { w=iw, h=ih, rot=false } }
        if iw ~= ih then
            orientations[2] = { w=ih, h=iw, rot=true }
        end

        local placed = false
        for _, orient in ipairs(orientations) do
            for r = 1, rows - orient.h + 1 do
                for c = 1, cols - orient.w + 1 do
                    if canPlaceAt(r, c, orient.w, orient.h) then
                        mark(r, c, orient.w, orient.h, index)
                        placements[#placements + 1] = { index=index, r=r, c=c, rotated=orient.rot }
                        backtrack(index + 1, placedCount + 1,
                                  totalValue + (item.value or 0) * (item.qty or 1))
                        placements[#placements] = nil
                        mark(r, c, orient.w, orient.h, nil)
                        placed = true
                        -- 提前终止：已全放
                        if bestPlaced == #snapshot then return end
                        if searchedNodes > MAX_NODES then return end
                    end
                end
            end
        end

        -- 跳过当前物品（允许放不下时继续尝试后续小件）
        if not placed or bestPlaced < #snapshot then
            backtrack(index + 1, placedCount, totalValue)
        end
    end

    backtrack(1, 0, 0)

    -- 安全检查：如果回溯没有找到能放下全部物品的方案，保留原始布局（绝不丢失物品）
    if bestPlaced < #snapshot then
        -- 尝试贪心兜底（面积降序已排好）
        local newInv = M.New(cols, rows)
        newInv._nextId = inv._nextId
        local allPlaced = true
        for _, item in ipairs(snapshot) do
            if not M.AutoPlace(newInv, item) then
                allPlaced = false
                break
            end
        end
        if allPlaced then
            inv.items = newInv.items
            inv.grid  = newInv.grid
        end
        -- 贪心也放不下全部 → 不修改原布局，宁可不整理也不丢物品
        return
    end

    -- 全部物品都能放下，安全应用最优布局
    local newInv = M.New(cols, rows)
    newInv._nextId = inv._nextId

    for _, p in ipairs(bestPlacements) do
        local item = snapshot[p.index]
        M.PlaceItem(newInv, item, p.c, p.r, p.rotated)
    end

    -- 用新内容替换原网格
    inv.items = newInv.items
    inv.grid  = newInv.grid
end

return M
