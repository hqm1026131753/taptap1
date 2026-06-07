-- ============================================================================
-- World.lua — 地图（BSP随机地牢）、箱子、战利品掉落管理
-- ============================================================================
local Data = require("Data")

local M = {}

local T = 40  -- 瓦片尺寸

-- 地图尺寸（BSP生成，比静态地图更大）
M.COLS = 48
M.ROWS = 36
M.TILE = T
M.W = M.COLS * T
M.H = M.ROWS * T

-- 出口格子列表（tile==2的位置）
M.EXIT_CELLS = {}

-- 出口是否锁定（Boss层Boss未死时=true）
M.exitLocked = false

-- 运行时地图（tile: 0=地板 1=墙 2=出口）
M.cells = {}

-- 箱子列表
M.boxes = {}

-- 尸体容器列表 { x, y, loot, looted, isEnemy, name, cw, ch }
M.corpses = {}

-- 地面掉落物列表 { x,y, item, picked }
M.drops = {}

-- 全局时间（由 main.lua 每帧同步）
M.time = 0

-- 粒子列表（共享）
M.particles = {}

-- 枪口闪光列表
M.muzzleFlashes = {}

-- 浮动伤害数字列表
M.dmgPopups = {}

-- 雷电击中视觉特效列表
M.lightningFx = {}

-- 房间类型元数据。第一版先用于生成规则与小地图显示，交互事件后续逐步接入。
M.ROOM_INFO = {
    start  = { label="起点", icon="⬇", color={90, 180, 255}, alwaysVisible=true },
    exit   = { label="出口", icon="🚪", color={80, 255, 160}, alwaysVisible=false },
    battle = { label="战斗", icon="",  color={120, 150, 165}, alwaysVisible=false },
    loot   = { label="搜刮", icon="🎁", color={255, 210, 90}, alwaysVisible=false },
    shop   = { label="商店", icon="🛒", color={120, 220, 255}, alwaysVisible=false },
    event  = { label="事件", icon="❓", color={220, 180, 255}, alwaysVisible=false },
    shrine = { label="神龛", icon="✦", color={255, 220, 120}, alwaysVisible=false },
    rest   = { label="休息", icon="❤️", color={255, 120, 150}, alwaysVisible=false },
    boss   = { label="Boss", icon="👑", color={255, 90, 90}, alwaysVisible=true },
}

-- ----------------------------------------------------------------------------
-- BSP 地牢生成
-- ----------------------------------------------------------------------------
local BSP_CONFIG = {
    minLeaf     = 10,   -- 最小叶节点尺寸（保证走廊至少6格间距）
    minRoom     = 6,    -- 最小房间尺寸
    maxRoom     = 8,    -- 最大房间尺寸
    padding     = 1,    -- 房间与叶边缘间距
    corridorW   = 2,    -- 走廊宽度（2格，角色好通过）
    maxDepth    = 5,    -- 最大递归深度
}

local function newNode(x, y, w, h)
    return { x=x, y=y, w=w, h=h, left=nil, right=nil, room=nil }
end

local function splitNode(node, depth, cfg, cols, rows)
    if depth >= cfg.maxDepth then return end
    local w, h = node.w, node.h
    -- 沿较长轴切割
    local splitH
    if w < h then
        splitH = true
    elseif h < w then
        splitH = false
    else
        splitH = math.random() < 0.5
    end
    local maxSplit = (splitH and h or w) - cfg.minLeaf
    if maxSplit < cfg.minLeaf then return end
    local split = cfg.minLeaf + math.random(0, maxSplit - cfg.minLeaf)
    if splitH then
        node.left  = newNode(node.x, node.y, w, split)
        node.right = newNode(node.x, node.y + split, w, h - split)
    else
        node.left  = newNode(node.x, node.y, split, h)
        node.right = newNode(node.x + split, node.y, w - split, h)
    end
    splitNode(node.left,  depth + 1, cfg, cols, rows)
    splitNode(node.right, depth + 1, cfg, cols, rows)
end

local function createRooms(node, rooms, cfg)
    if node.left or node.right then
        if node.left  then createRooms(node.left,  rooms, cfg) end
        if node.right then createRooms(node.right, rooms, cfg) end
        return
    end
    -- 叶节点：在节点内随机放置一个房间
    local maxRW = math.min(cfg.maxRoom, node.w - cfg.padding * 2)
    local maxRH = math.min(cfg.maxRoom, node.h - cfg.padding * 2)
    if maxRW < cfg.minRoom or maxRH < cfg.minRoom then return end
    local rw = cfg.minRoom + math.random(0, maxRW - cfg.minRoom)
    local rh = cfg.minRoom + math.random(0, maxRH - cfg.minRoom)
    local rx = node.x + cfg.padding + math.random(0, node.w - rw - cfg.padding * 2)
    local ry = node.y + cfg.padding + math.random(0, node.h - rh - cfg.padding * 2)
    node.room = {
        x  = rx, y  = ry,
        w  = rw, h  = rh,
        cx = rx + math.floor(rw / 2),
        cy = ry + math.floor(rh / 2),
    }
    table.insert(rooms, node.room)
end

-- 在 cells 上刻出水平走廊（0=地板）
local function carveH(cells, x1, x2, y, cw, cols, rows)
    local minX = math.min(x1, x2)
    local maxX = math.max(x1, x2)
    for x = minX, maxX do
        for k = 0, cw - 1 do
            local ry = y + k
            if ry >= 1 and ry <= rows and x >= 1 and x <= cols then
                cells[ry][x] = 0
            end
        end
    end
end

-- 在 cells 上刻出垂直走廊
local function carveV(cells, y1, y2, x, cw, cols, rows)
    local minY = math.min(y1, y2)
    local maxY = math.max(y1, y2)
    for y = minY, maxY do
        for k = 0, cw - 1 do
            local rx = x + k
            if y >= 1 and y <= rows and rx >= 1 and rx <= cols then
                cells[y][rx] = 0
            end
        end
    end
end

local function connectRooms(cells, a, b, cw, cols, rows)
    -- L 形走廊连接两房间中心
    if math.random() < 0.5 then
        carveH(cells, a.cx, b.cx, a.cy, cw, cols, rows)
        carveV(cells, a.cy, b.cy, b.cx, cw, cols, rows)
    else
        carveV(cells, a.cy, b.cy, a.cx, cw, cols, rows)
        carveH(cells, a.cx, b.cx, b.cy, cw, cols, rows)
    end
end

-- Prim's 最小生成树：保证所有房间100%联通
local function connectAllRooms(cells, rooms, cw, cols, rows)
    if #rooms <= 1 then return end

    local inMST   = { true }     -- rooms[1] 默认已在树中
    local mstList = { rooms[1] } -- 已连通房间列表
    local added   = 1

    while added < #rooms do
        local bestDist, bestFrom, bestTo, bestToIdx = math.huge, nil, nil, nil

        for _, cRoom in ipairs(mstList) do
            for i = 1, #rooms do
                if not inMST[i] then
                    local dx = cRoom.cx - rooms[i].cx
                    local dy = cRoom.cy - rooms[i].cy
                    local d  = dx*dx + dy*dy
                    if d < bestDist then
                        bestDist  = d
                        bestFrom  = cRoom
                        bestTo    = rooms[i]
                        bestToIdx = i
                    end
                end
            end
        end

        if not bestFrom then break end  -- 防御：不应发生

        connectRooms(cells, bestFrom, bestTo, cw, cols, rows)
        inMST[bestToIdx] = true
        table.insert(mstList, bestTo)
        added = added + 1
    end
end

local function carveRoom(cells, room)
    for y = room.y, room.y + room.h - 1 do
        for x = room.x, room.x + room.w - 1 do
            cells[y][x] = 0
        end
    end
end

-- BFS 实际路径距离：找从出生房间走最远的房间（真正的"最深处"）
local function findDeepest(rooms, spawnRoom, cells, cols, rows)
    local dist = {}
    local function key(c, r) return r * (cols + 1) + c end

    local queue = { {spawnRoom.cx, spawnRoom.cy, 0} }
    local qi    = 1
    dist[key(spawnRoom.cx, spawnRoom.cy)] = 0

    while qi <= #queue do
        local c, r, d = queue[qi][1], queue[qi][2], queue[qi][3]
        qi = qi + 1
        for _, nb in ipairs({{c-1,r},{c+1,r},{c,r-1},{c,r+1}}) do
            local nc, nr = nb[1], nb[2]
            if nc >= 1 and nc <= cols and nr >= 1 and nr <= rows then
                local k = key(nc, nr)
                if not dist[k] and cells[nr][nc] ~= 1 then
                    dist[k] = d + 1
                    table.insert(queue, {nc, nr, d + 1})
                end
            end
        end
    end

    local best, bestDist = spawnRoom, -1
    for _, room in ipairs(rooms) do
        if room ~= spawnRoom then
            local d = dist[key(room.cx, room.cy)] or 0
            if d > bestDist then bestDist = d; best = room end
        end
    end
    return best
end

-- BSP 主生成函数，返回 rooms 列表
local function generateBSP(cells, cols, rows, cfg)
    -- 全部初始化为墙
    for r = 1, rows do
        cells[r] = {}
        for c = 1, cols do
            cells[r][c] = 1
        end
    end
    local root = newNode(1, 1, cols, rows)
    splitNode(root, 0, cfg, cols, rows)
    local rooms = {}
    createRooms(root, rooms, cfg)
    -- Prim's MST 保证100%联通：先连走廊，再刻房间地板
    connectAllRooms(cells, rooms, cfg.corridorW, cols, rows)
    for _, room in ipairs(rooms) do
        carveRoom(cells, room)
    end
    return rooms
end

local function roomDist(a, b)
    local dx = a.cx - b.cx
    local dy = a.cy - b.cy
    return math.sqrt(dx * dx + dy * dy)
end

local function isReservedRoom(room)
    return room.kind == "start" or room.kind == "exit" or room.kind == "boss"
end

local function collectRooms(rooms, predicate)
    local out = {}
    for _, room in ipairs(rooms) do
        if predicate(room) then table.insert(out, room) end
    end
    return out
end

local function pickRandomRoom(rooms, predicate)
    local candidates = collectRooms(rooms, predicate)
    if #candidates == 0 then return nil end
    return candidates[math.random(#candidates)]
end

local function pickMiddleRoom(rooms, spawnRoom, predicate)
    local candidates = {}
    for _, room in ipairs(rooms) do
        if predicate(room) then
            table.insert(candidates, { room=room, dist=roomDist(room, spawnRoom) })
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    local idx = math.max(1, math.min(#candidates, math.floor(#candidates * 0.55 + 0.5)))
    return candidates[idx].room
end

local function pickBossRoom(rooms, spawnRoom, exitRoom)
    local best, bestScore = nil, -999999
    for _, room in ipairs(rooms) do
        if room ~= spawnRoom and room ~= exitRoom then
            local fromSpawn = roomDist(room, spawnRoom)
            local fromExit  = roomDist(room, exitRoom)
            local score = fromSpawn + fromExit * 0.45
            if score > bestScore then
                bestScore = score
                best = room
            end
        end
    end
    return best
end

local function assignRoomTypes(rooms, spawnRoom, exitRoom, bossRoom, floor)
    floor = floor or 1
    local isBossFloor = (floor % 5 == 0)
    for _, room in ipairs(rooms) do
        room.kind = "battle"
        room.floor = floor
        room.locked = false
        room.discovered = false
        room.roomEvent = nil
    end

    spawnRoom.kind = "start"
    spawnRoom.discovered = true
    exitRoom.kind = "exit"
    exitRoom.discovered = false  -- 出口房默认隐藏，需玩家探索发现
    if bossRoom then
        bossRoom.kind = "boss"
        bossRoom.discovered = true
    end

    if not isBossFloor then
        local shopChance = ((floor + 1) % 5 == 0) and 1.0 or 0.20
        if math.random() < shopChance then
            local shop = pickMiddleRoom(rooms, spawnRoom, function(r)
                return not isReservedRoom(r) and r.kind == "battle"
            end)
            if shop then
                shop.kind = "shop"
                shop.discovered = true
            end
        end

        -- 事件房：70%概率生成
        if math.random() < 0.70 then
            local eventRoom = pickRandomRoom(rooms, function(r)
                return not isReservedRoom(r) and r.kind == "battle"
            end)
            if eventRoom then
                eventRoom.kind = "event"
                -- 预设事件类型：altar(祭坛45%) / terminal(情报终端30%) / curse(诅咒25%)
                local r = math.random(100)
                if r <= 45 then
                    eventRoom.eventType = "altar"
                elseif r <= 75 then
                    eventRoom.eventType = "terminal"
                else
                    eventRoom.eventType = "curse"
                end
            end
        end

        -- 神龛房：30%概率生成（独立于事件房，可同时存在）
        if math.random() < 0.30 then
            local shrineRoom = pickRandomRoom(rooms, function(r)
                return not isReservedRoom(r) and r.kind == "battle"
            end)
            if shrineRoom then shrineRoom.kind = "shrine" end
        end

        local restChance = (floor <= 4) and 0.30 or 0.15
        if math.random() < restChance then
            local rest = pickRandomRoom(rooms, function(r)
                return not isReservedRoom(r) and r.kind == "battle"
            end)
            if rest then rest.kind = "rest" end
        end
    end

    -- 搜刮房：每层仅1个（Boss层不生成）
    if not isBossFloor then
        local loot = pickRandomRoom(rooms, function(r)
            return not isReservedRoom(r) and r.kind == "battle"
        end)
        if loot then loot.kind = "loot" end
    end

    if floor >= 3 then
        local locked = pickRandomRoom(rooms, function(r)
            return not isReservedRoom(r)
        end)
        if locked then locked.locked = true end
    end

    -- 供电房：除了第1层和Boss层，每层3%概率出现
    if floor > 1 and not isBossFloor then
        if math.random(100) <= 3 then
            local powerRoom = pickRandomRoom(rooms, function(r)
                return not isReservedRoom(r) and r.kind == "battle"
            end)
            if powerRoom then
                powerRoom.kind = "power"
                powerRoom.discovered = true
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- 工具
-- ----------------------------------------------------------------------------
function M.TileAt(col, row)
    if row < 1 or row > M.ROWS or col < 1 or col > M.COLS then return 1 end
    
-- ----------------------------------------------------------------------------
-- Boss 死亡时在其周围生成固定宝箱（由 main.lua 在 Boss 死亡帧调用）
-- floor: 当前层数，决定宝箱数量和稀有度概率
-- bx, by: Boss 世界坐标
-- ----------------------------------------------------------------------------
function M.SpawnBossChests(floor, bx, by)
    local count = Data.GetFloorParams(floor).bossChestCount
    if count <= 0 then return end
    local tSize = M.TILE
    -- 在 Boss 位置周围扇形放置宝箱，避免重叠
    local offsets = {
        {-tSize*1.5, 0}, {tSize*1.5, 0}, {0, -tSize*1.5}, {0, tSize*1.5},
        {-tSize, -tSize}, {tSize, -tSize}, {-tSize, tSize}, {tSize, tSize},
    }
    local placed = 0
    for _, off in ipairs(offsets) do
        if placed >= count then break end
        local wx = bx + off[1]
        local wy = by + off[2]
        local bcol = math.floor(wx / tSize) + 1
        local brow = math.floor(wy / tSize) + 1
        -- 确保落在地板上
        if M.TileAt(bcol, brow) == 0 then
            -- 检查该位置是否已有箱子，避免重叠导致渲染错误
            local occupied = false
            for _, existingBox in ipairs(M.boxes) do
                if existingBox.col == bcol and existingBox.row == brow then
                    occupied = true
                    break
                end
            end
            if not occupied then
                local cx, cy = M.TileCenter(bcol, brow)
                table.insert(M.boxes, {
                    x=cx, y=cy, col=bcol, row=brow,
                    elite=true,
                    isBossChest=true,
                    floor=floor,
                    opened=false,
                    searchTimer=0,
                })
                placed = placed + 1
            end
        end
    end
end

return M.cells[row][col]
end

-- IsWall 接受世界坐标（wx, wy）
function M.IsWall(wx, wy)
    local col, row = M.WorldToTile(wx, wy)
    local t = M.TileAt(col, row)
    return t == 1
end

-- 访问器（供外部模块使用）
function M.GetBoxes()     return M.boxes     end
function M.GetRooms()     return M.rooms or {} end

function M.GetRoomAtTile(col, row)
    local rowMap = M._tileRoomMap and M._tileRoomMap[row]
    if rowMap then return rowMap[col] end
    return nil
end

function M.GetRoomAtWorld(wx, wy)
    local col, row = M.WorldToTile(wx, wy)
    return M.GetRoomAtTile(col, row)
end

function M.DiscoverRoomAtWorld(wx, wy)
    local col, row = M.WorldToTile(wx, wy)
    local room = M.GetRoomAtTile(col, row)
    if room then
        room.discovered = true
        return room
    end
    -- 玩家在走廊中（地板格子但不在房间内）→ 发现附近房间
    if M.TileAt(col, row) == 0 then
        local discoverRange = 6  -- 走廊发现范围（格）
        for _, r in ipairs(M.rooms or {}) do
            if not r.discovered then
                -- 计算玩家到房间边缘的曼哈顿距离
                local nearCol = math.max(r.x, math.min(col, r.x + r.w - 1))
                local nearRow = math.max(r.y, math.min(row, r.y + r.h - 1))
                local dist = math.abs(col - nearCol) + math.abs(row - nearRow)
                if dist <= discoverRange then
                    r.discovered = true
                end
            end
        end
    end
    return nil
end

-- ============================================================================
-- 视野系统（Visibility）
-- ============================================================================
-- 玩家当前所在房间（每帧由 main 更新）
M.playerRoom = nil

--- 标记玩家进入房间（首次进入设 entered=true）
function M.EnterRoom(room)
    if room and not room.entered then
        room.entered = true
    end
end

--- 获取玩家当前可见的房间列表
--- 返回 { room = true/false } 表：true=完整可见（显示内容），false=仅轮廓
function M.GetVisibleRooms(wx, wy)
    local visible = {}  -- room -> "full" | "outline"
    M._playerWx = wx
    M._playerWy = wy
    M._visibleCorridors = {}  -- corridor group table -> true
    local col, row = M.WorldToTile(wx, wy)
    local curRoom = M.GetRoomAtTile(col, row)

    if curRoom then
        -- 玩家在房间内：看到本房间 + 相邻走廊可达的房间
        visible[curRoom] = "full"
        M.playerRoom = curRoom
        -- Boss 房间组：紧邻 boss 房的房间全部可见
        local grp = M.bossGroup and M.bossGroup[curRoom]
        if grp then
            for _, gr in ipairs(grp) do
                visible[gr] = "full"
            end
        end
        -- 检查走廊连接的相邻房间
        local visRange = 10
        for _, r in ipairs(M.rooms or {}) do
            if r ~= curRoom then
                local nearCol = math.max(r.x, math.min(col, r.x + r.w - 1))
                local nearRow = math.max(r.y, math.min(row, r.y + r.h - 1))
                local dist = math.abs(col - nearCol) + math.abs(row - nearRow)
                if dist <= visRange then
                    if M.HasFloorPath(col, row, nearCol, nearRow) then
                        if r.entered then
                            visible[r] = "full"
                        else
                            visible[r] = "outline"
                        end
                    end
                end
            end
        end
    else
        -- 玩家在走廊中：可见走廊两端相连的房间
        M.playerRoom = nil
        local visRange = 8  -- 走廊视野范围（格）
        for _, r in ipairs(M.rooms or {}) do
            local nearCol = math.max(r.x, math.min(col, r.x + r.w - 1))
            local nearRow = math.max(r.y, math.min(row, r.y + r.h - 1))
            local dist = math.abs(col - nearCol) + math.abs(row - nearRow)
            if dist <= visRange then
                -- 检查从玩家到房间边缘是否有连通路径（全是地板）
                if M.HasFloorPath(col, row, nearCol, nearRow) then
                    if r.entered then
                        visible[r] = "full"
                    else
                        visible[r] = "outline"
                    end
                    -- Boss 组展开
                    local grp = M.bossGroup and M.bossGroup[r]
                    if grp then
                        for _, gr in ipairs(grp) do
                            if not visible[gr] then
                                visible[gr] = r.entered and "full" or "outline"
                            end
                        end
                    end
                end
            end
        end
    end
    -- 预计算可见走廊组：走廊组中任一格在玩家范围内则整组可见
    local range = curRoom and 10 or 12
    if M.corridorGroup then
        local checked = {}  -- 避免重复检查同组
        local rows = M.ROWS
        local cols = M.COLS
        -- 只检查玩家附近 range 范围内的格子
        local minR = math.max(1, row - range)
        local maxR = math.min(rows, row + range)
        local minC = math.max(1, col - range)
        local maxC = math.min(cols, col + range)
        for r = minR, maxR do
            local cgRow = M.corridorGroup[r]
            if cgRow then
                for c = minC, maxC do
                    local grp = cgRow[c]
                    if grp and not checked[grp] then
                        local dist = math.abs(c - col) + math.abs(r - row)
                        if dist <= range then
                            M._visibleCorridors[grp] = true
                            checked[grp] = true
                        end
                    end
                end
            end
        end
        -- Boss 组内走廊也标记可见
        if curRoom and M.bossGroup then
            local bgrp = M.bossGroup[curRoom]
            if bgrp then
                for _, gr in ipairs(bgrp) do
                    for r2 = gr.y, gr.y + gr.h - 1 do
                        local cgRow = M.corridorGroup[r2]
                        if cgRow then
                            for c2 = gr.x - 2, gr.x + gr.w + 1 do
                                local cg = cgRow[c2]
                                if cg then M._visibleCorridors[cg] = true end
                            end
                        end
                    end
                    -- 上下两行
                    for _, r2 in ipairs({gr.y - 1, gr.y - 2, gr.y + gr.h, gr.y + gr.h + 1}) do
                        local cgRow = M.corridorGroup[r2]
                        if cgRow then
                            for c2 = gr.x, gr.x + gr.w - 1 do
                                local cg = cgRow[c2]
                                if cg then M._visibleCorridors[cg] = true end
                            end
                        end
                    end
                end
            end
        end
    end

    return visible
end

--- 简易路径连通检查：从(c1,r1)到(c2,r2)走直线是否全为地板
function M.HasFloorPath(c1, r1, c2, r2)
    -- 先水平后垂直检查
    local stepX = (c2 > c1) and 1 or (c2 < c1 and -1 or 0)
    local stepY = (r2 > r1) and 1 or (r2 < r1 and -1 or 0)
    local cx, cy = c1, r1
    -- 水平段
    while cx ~= c2 do
        cx = cx + stepX
        local t = M.TileAt(cx, cy)
        if t ~= 0 and t ~= 2 then return false end
    end
    -- 垂直段
    while cy ~= r2 do
        cy = cy + stepY
        local t = M.TileAt(cx, cy)
        if t ~= 0 and t ~= 2 then return false end
    end
    return true
end

--- 判断一个世界坐标点是否在当前可见范围内
function M.IsPositionVisible(wx, wy, visibleRooms)
    return true
end

--- 判断一个格子是否对玩家可见（用于地图渲染）
function M.IsTileVisible(col, row, playerCol, playerRow, visibleRooms)
    return true
end

function M.SpawnItemDrop(wx, wy, item)
    if not item then return nil end
    local drop = {
        x = wx, y = wy,
        item = item,
        picked = false,
        nopickTimer = 0.25,
    }
    table.insert(M.drops, drop)
    -- 高稀有度掉落物发光
    local rarity = item.rarity or 1
    if rarity >= 3 then
        local dropId = string.format("drop_%d_%d_%d", math.floor(wx), math.floor(wy), #M.drops)
        drop._glowId = dropId
        local LightMod = require("Lighting")
        LightMod.AddItemGlow(dropId, wx, wy, rarity)
    end
    return drop
end

local function randomWeaponItem(minRarity, maxRarity, floor)
    minRarity = minRarity or 1
    maxRarity = maxRarity or 5
    local weapon = nil
    for _ = 1, 24 do
        local w = Data.RandomWeapon(maxRarity)
        if w and (w.rarity or 1) >= minRarity then weapon = w; break end
    end
    weapon = weapon or Data.RandomWeapon(maxRarity)
    local valMult = Data.GetLootValueMult(floor or 1)
    return {
        itype="weapon",
        data=weapon,
        value=math.floor((weapon.value or 0) * valMult),
        name=weapon.name,
        icon="🔫",
        rarity=weapon.rarity or minRarity,
    }
end

local function randomLegendaryItem(floor)
    local item = nil
    for _ = 1, 36 do
        local t = Data.WeightedRandom(Data.BOX_LOOT_TABLE)
        local candidate = M.GenerateItem(t, 5, floor or 1)
        if candidate and (candidate.rarity or 1) >= 5 then item = candidate; break end
    end
    return item or randomWeaponItem(5, 5, floor)
end

local function revealRandomRoom()
    local hidden = {}
    for _, room in ipairs(M.rooms or {}) do
        local info = M.ROOM_INFO[room.kind or "battle"]
        if room.kind ~= "battle" and not room.discovered
        and not (info and info.alwaysVisible) then
            table.insert(hidden, room)
        end
    end
    if #hidden == 0 then return false end
    hidden[math.random(#hidden)].discovered = true
    return true
end

function M.GetRoomInteraction(player)
    if not player or player.dead then return nil end
    local room = M.GetRoomAtWorld(player.x, player.y)
    if not room then return nil end
    if room.kind ~= "shrine" and room.kind ~= "event" and room.kind ~= "rest" and room.kind ~= "shop" and room.kind ~= "power" then return nil end
    local ox, oy = M.TileCenter(room.cx, room.cy)
    local hasNpc = (room.kind == "event" or room.kind == "shrine" or room.kind == "shop")
    local INTERACT_RANGE = 58

    -- NPC 对话（不受 room.used 限制，可反复交谈）
    if hasNpc then
        local npcX = ox - 50
        local dd = math.sqrt((player.x - npcX)^2 + (player.y - oy)^2)
        if dd <= INTERACT_RANGE then
            return { room=room, x=npcX, y=oy, label="交谈", action="talk" }
        end
    end

    -- 机关交互（消耗型，used 后不可再用）
    if not room.used then
        local dd = math.sqrt((player.x - ox)^2 + (player.y - oy)^2)
        if dd <= INTERACT_RANGE then
            if room.kind == "rest" and player.hp >= player.maxHp then return nil end
            local label
            if room.kind == "shrine" then
                label = "献祭"
            elseif room.kind == "event" then
                label = "启动"
            elseif room.kind == "shop" then
                label = "购物"
            elseif room.kind == "power" then
                label = "供电"
            else
                label = "休息"
            end
            return { room=room, x=ox, y=oy, label=label, action="mechanism" }
        end
    end

    return nil
end

function M.TryRoomInteract(player, floor)
    local inter = M.GetRoomInteraction(player)
    if not inter then return false end
    local room = inter.room
    floor = floor or room.floor or 1

    -- NPC 对话（与机关分开）
    if inter.action == "talk" then
        local lines
        if room.kind == "shop" then
            lines = {
                "暂未营业，敬请期待。",
                "货还在路上…改天再来吧。",
                "机器维修中，下次一定。",
                "库存清零了，过几天补货。",
            }
        elseif room.kind == "shrine" then
            lines = {
                "以血为引，祭坛方开。",
                "你的血…够浓吗？",
                "机关就在旁边，想好了再来。",
            }
        elseif room.kind == "event" then
            local etype = room.eventType or "altar"
            if etype == "altar" then
                lines = {
                    "这祭坛需要鲜血浇灌。",
                    "代价不菲，但值得。",
                    "旁边的机关，有勇气就按。",
                }
            elseif etype == "terminal" then
                lines = {
                    "这台终端还能用。",
                    "情报就是力量。",
                    "试试启动旁边的装置。",
                }
            else
                lines = {
                    "你感受到诅咒了吗？",
                    "力量来自牺牲。",
                    "旁边那东西…碰了就回不了头。",
                }
            end
        end
        if lines then
            player.notification = { text=lines[math.random(#lines)], timer=2.5 }
        end
        return true
    end

    if room.kind == "shop" then
        player.notification = { text="商店暂未开放。", timer=2.0 }
        return true
    end

    if room.kind == "rest" then
        local heal = math.max(1, math.floor(player.maxHp * 0.30))
        player.hp = math.min(player.maxHp, player.hp + heal)
        room.used = true
        player.notification = { text="休息泉恢复 +" .. heal .. " HP", timer=2.0 }
        M.SpawnPickup(inter.x, inter.y)
        return true
    end

    if room.kind == "shrine" then
        local cost = math.max(1, math.floor(player.maxHp * 0.25))
        player.hp = math.max(1, player.hp - cost)
        local item = randomWeaponItem(3, 5, floor)
        M.SpawnItemDrop(inter.x + 26, inter.y, item)
        room.used = true
        player.notification = { text="血祭完成，武器已显现", timer=2.4 }
        M.SpawnSpark(inter.x, inter.y, 16)
        return true
    end

    if room.kind == "event" then
        room.used = true
        local etype = room.eventType or "altar"
        if etype == "altar" then
            local cost = math.max(1, math.floor(player.maxHp * 0.45))
            player.hp = math.max(1, player.hp - cost)
            local maxR = math.random(100) <= 15 and 5 or 4
            local item = randomWeaponItem(3, maxR, floor)
            local chestX = inter.x + 30
            local chestCol = math.min(M.COLS, room.cx + 1)
            table.insert(M.boxes, {
                x=chestX, y=inter.y, col=chestCol, row=room.cy,
                elite=true, floor=floor, opened=false, searchTimer=0,
                _lootCache={ item },
            })
            player.notification = { text="祭坛升起宝箱", timer=2.2 }
            M.SpawnSpark(inter.x, inter.y, 18)
        elseif etype == "terminal" then
            local ok = revealRandomRoom()
            player.notification = { text=ok and "情报终端揭示了房间" or "没有可揭示的房间", timer=2.2 }
            M.SpawnParticle(inter.x, inter.y, 0, -40, 120, 220, 255, 0.5, 5)
        elseif etype == "curse" then
            local oldMax = player.maxHp
            player.maxHp = math.max(1, math.floor(player.maxHp * 0.75))
            player.hp = math.min(player.hp, player.maxHp)
            local item = randomWeaponItem(4, 5, floor)
            M.SpawnItemDrop(inter.x + 26, inter.y, item)
            player.notification = { text="诅咒宝物：HP上限 " .. oldMax .. "→" .. player.maxHp, timer=2.8 }
            M.SpawnBlood(inter.x, inter.y, 10)
        end
        return true
    end

    if room.kind == "power" then
        room.used = true
        M.powerDown = false
        player.notification = { text="供电恢复，视野已恢复正常", timer=2.5 }
        M.SpawnSpark(inter.x, inter.y, 20)
        return true
    end

    return false
end

function M.WorldToTile(wx, wy)
    return math.floor(wx / T) + 1, math.floor(wy / T) + 1
end

function M.TileCenter(col, row)
    return (col - 0.5) * T, (row - 0.5) * T
end

function M.IsExitCell(col, row)
    return M.TileAt(col, row) == 2
end

-- 视线检测（逐格射线，返回是否无遮挡）
function M.HasLOS(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist < 1 then return true end
    local steps = math.ceil(dist / (T * 0.5))
    for i = 1, steps - 1 do
        local t = i / steps
        local wx = x1 + dx * t
        local wy = y1 + dy * t
        local c, r = M.WorldToTile(wx, wy)
        if M.TileAt(c, r) == 1 then return false end
    end
    return true
end

-- ----------------------------------------------------------------------------
-- 碰撞解算（圆形vs瓦片）
-- ----------------------------------------------------------------------------
function M.ResolveWall(obj, radius)
    radius = radius or 14
    local x, y = obj.x, obj.y
    local r = radius

    local function blocked(wx, wy)
        local c, ro = M.WorldToTile(wx, wy)
        return M.TileAt(c, ro) == 1
    end

    if blocked(x + r, y) then x = math.floor((x + r) / T) * T - r - 0.01 end
    if blocked(x - r, y) then x = math.ceil((x - r) / T) * T + r + 0.01 end
    if blocked(x, y + r) then y = math.floor((y + r) / T) * T - r - 0.01 end
    if blocked(x, y - r) then y = math.ceil((y - r) / T) * T + r + 0.01 end

    obj.x, obj.y = x, y
end

-- ----------------------------------------------------------------------------
-- 初始化（BSP 随机地牢）
-- floor: 当前层数（1~20），影响敌人数量和 Boss 生成
-- 返回：spawnPositions, playerSpawnX, playerSpawnY, bossSpawn(可能为nil)
-- ----------------------------------------------------------------------------
function M.Init(floor)
    M.cells = {}
    M.EXIT_CELLS = {}
    M.drops = {}
    M.particles = {}
    M.muzzleFlashes = {}
    M.dmgPopups = {}
    M.lightningFx = {}
    M.corpses = {}
    M.powerDown = false  -- 供电房状态：断电

    -- 生成 BSP 地牢
    local rooms = generateBSP(M.cells, M.COLS, M.ROWS, BSP_CONFIG)
    M.rooms = rooms  -- 暴露给渲染层使用

    if #rooms == 0 then
        -- 保险：退化情况下放一个大房间
        rooms = {{ x=2, y=2, w=M.COLS-3, h=M.ROWS-3, cx=M.COLS//2, cy=M.ROWS//2 }}
        carveRoom(M.cells, rooms[1])
        M.rooms = rooms
    end

    -- 构建 tile→room O(1) 查找表
    M._tileRoomMap = {}
    for _, room in ipairs(rooms) do
        for r = room.y, room.y + room.h - 1 do
            if not M._tileRoomMap[r] then M._tileRoomMap[r] = {} end
            for c = room.x, room.x + room.w - 1 do
                M._tileRoomMap[r][c] = room
            end
        end
    end

    -- 第一个房间中心作为玩家出生点
    local spawnRoom = rooms[1]
    local spawnCol  = spawnRoom.cx
    local spawnRow  = spawnRoom.cy

    -- BFS 路径最深的房间放撤离点
    local exitRoom = findDeepest(rooms, spawnRoom, M.cells, M.COLS, M.ROWS)
    floor = floor or 1
    local isBossFloor = (floor % 5 == 0)
    local bossRoom = isBossFloor and pickBossRoom(rooms, spawnRoom, exitRoom) or nil
    assignRoomTypes(rooms, spawnRoom, exitRoom, bossRoom, floor)

    -- 检查是否有供电房 → 设置断电状态
    for _, room in ipairs(rooms) do
        if room.kind == "power" then
            M.powerDown = true
            break
        end
    end

    -- 为每个房间预生成灯装饰（确定性随机，地图生成时就固定）
    for _, room in ipairs(rooms) do
        room.lamp = nil
        -- 起始房、Boss房、出口房不放灯
        if room.kind == "start" or room.kind == "boss" or room.kind == "exit" then
            goto continue_genlamp
        end
        -- 房间至少3x3才放灯
        if room.w < 3 or room.h < 3 then
            goto continue_genlamp
        end
        -- 确定性随机：用房间坐标做种子
        local seed = room.x * 7919 + room.y * 6271 + room.w * 31
        -- 约30%的房间有灯
        if (seed % 100) >= 30 then
            goto continue_genlamp
        end
        -- 灯的位置：在房间内部（排除外围墙壁一格）
        local s2 = seed * 37 + 13
        local innerX = room.x + 1
        local innerW = room.w - 2
        local innerY = room.y + 1
        local innerH = room.h - 2
        if innerW < 1 or innerH < 1 then goto continue_genlamp end
        local lampCol = innerX + (s2 % innerW)
        local lampRow = innerY + ((s2 * 53 + 7) % innerH)
        -- 避开中心位置（交互物所在处）
        if lampCol == room.cx and lampRow == room.cy then
            lampCol = lampCol + (lampCol < room.x + room.w - 2 and 1 or -1)
        end
        -- 样式：0=精灵-0009, 1=精灵-0010
        local style = seed % 2
        room.lamp = { col = lampCol, row = lampRow, style = style }
        ::continue_genlamp::
    end

    -- 初始房间 60% 概率生成指示牌（纯装饰）
    spawnRoom.signpost = nil
    if spawnRoom.w >= 3 and spawnRoom.h >= 3 then
        local seed = spawnRoom.x * 4931 + spawnRoom.y * 3571 + spawnRoom.w * 17
        if (seed % 100) < 60 then
            -- 位置：在房间内部，避开中心
            local s2 = seed * 41 + 7
            local innerX = spawnRoom.x + 1
            local innerW = spawnRoom.w - 2
            local innerY = spawnRoom.y + 1
            local innerH = spawnRoom.h - 2
            if innerW >= 1 and innerH >= 1 then
                local col = innerX + (s2 % innerW)
                local row = innerY + ((s2 * 61 + 3) % innerH)
                -- 避开中心
                if col == spawnRoom.cx and row == spawnRoom.cy then
                    col = col + (col < spawnRoom.x + spawnRoom.w - 2 and 1 or -1)
                end
                -- 样式：0=精灵-0005, 1=精灵-0006
                local style = seed % 2
                spawnRoom.signpost = { col = col, row = row, style = style }
            end
        end
    end

    -- 出口房缩小为最小尺寸（6×6），居中于原位置
    local EXIT_SIZE = BSP_CONFIG.minRoom  -- 6
    if exitRoom.w > EXIT_SIZE or exitRoom.h > EXIT_SIZE then
        local oldX, oldY, oldW, oldH = exitRoom.x, exitRoom.y, exitRoom.w, exitRoom.h
        local newW = math.min(exitRoom.w, EXIT_SIZE)
        local newH = math.min(exitRoom.h, EXIT_SIZE)
        local newX = exitRoom.cx - math.floor(newW / 2)
        local newY = exitRoom.cy - math.floor(newH / 2)
        -- 边界钳制
        newX = math.max(2, math.min(newX, M.COLS - newW))
        newY = math.max(2, math.min(newY, M.ROWS - newH))
        -- 先把原区域填回墙壁
        for y = oldY, oldY + oldH - 1 do
            for x = oldX, oldX + oldW - 1 do
                if y >= 1 and y <= M.ROWS and x >= 1 and x <= M.COLS then
                    M.cells[y][x] = 1
                end
            end
        end
        exitRoom.x = newX
        exitRoom.y = newY
        exitRoom.w = newW
        exitRoom.h = newH
        exitRoom.cx = newX + math.floor(newW / 2)
        exitRoom.cy = newY + math.floor(newH / 2)
        carveRoom(M.cells, exitRoom)

        -- 重新连通被截断的走廊：检查旧房间边缘外侧是否有地板格（走廊入口），
        -- 如果有则从该入口向新房间方向挖通路径
        -- 上边
        if oldY - 1 >= 1 then
            for x = oldX, oldX + oldW - 1 do
                if M.cells[oldY - 1][x] == 0 then
                    for y = oldY, newY - 1 do
                        if y >= 1 and y <= M.ROWS then M.cells[y][x] = 0 end
                    end
                end
            end
        end
        -- 下边
        if oldY + oldH <= M.ROWS then
            for x = oldX, oldX + oldW - 1 do
                if M.cells[oldY + oldH][x] == 0 then
                    for y = newY + newH, oldY + oldH - 1 do
                        if y >= 1 and y <= M.ROWS then M.cells[y][x] = 0 end
                    end
                end
            end
        end
        -- 左边
        if oldX - 1 >= 1 then
            for y = oldY, oldY + oldH - 1 do
                if M.cells[y][oldX - 1] == 0 then
                    for x = oldX, newX - 1 do
                        if x >= 1 and x <= M.COLS then M.cells[y][x] = 0 end
                    end
                end
            end
        end
        -- 右边
        if oldX + oldW <= M.COLS then
            for y = oldY, oldY + oldH - 1 do
                if M.cells[y][oldX + oldW] == 0 then
                    for x = newX + newW, oldX + oldW - 1 do
                        if x >= 1 and x <= M.COLS then M.cells[y][x] = 0 end
                    end
                end
            end
        end
    end

    -- 撤离区：在该房间中心周围 3×3 格标为 2
    local ec, er = exitRoom.cx, exitRoom.cy
    for dr = -1, 1 do
        for dc = -1, 1 do
            local rr, cc = er + dr, ec + dc
            if rr >= 1 and rr <= M.ROWS and cc >= 1 and cc <= M.COLS then
                M.cells[rr][cc] = 2
                table.insert(M.EXIT_CELLS, {col=cc, row=rr})
            end
        end
    end

    -- 撤离区中心（供渲染用）
    M.EXIT_CENTER = { col = ec, row = er }

    -- 出生点保证地板，撤离中心保持2
    M.cells[spawnRow][spawnCol] = 0
    M.cells[er][ec] = 2

    -- -----------------------------------------------------------------------
    -- Wall Top 后处理：暴露墙面上方必须有一格真实墙壁
    -- 逻辑：如果一个墙(tile==1)下方是地板/出口(非墙)，则其上方必须也是墙
    -- -----------------------------------------------------------------------
    for row = 2, M.ROWS - 1 do
        for col = 1, M.COLS do
            if M.cells[row][col] == 1 then
                -- 这面墙下方是地板/出口（暴露墙面）
                local below = (row < M.ROWS) and M.cells[row+1][col] or 1
                if below ~= 1 then
                    -- 上方如果是地板，转为墙
                    local above = M.cells[row-1][col]
                    if above == 0 then
                        M.cells[row-1][col] = 1
                    end
                end
            end
        end
    end
    -- 重新保证出生点和撤离区不被覆盖
    M.cells[spawnRow][spawnCol] = 0
    M.cells[er][ec] = 2
    for _, ec2 in ipairs(M.EXIT_CELLS) do
        M.cells[ec2.row][ec2.col] = 2
    end

    -- -----------------------------------------------------------------------
    -- 箱子：每个非出生房间放 1~2 个，远端房间可能是精英箱
    -- -----------------------------------------------------------------------
    M.boxes = {}
    local distThreshold = 0
    do
        local dx = exitRoom.cx - spawnRoom.cx
        local dy = exitRoom.cy - spawnRoom.cy
        distThreshold = math.sqrt(dx*dx + dy*dy) * 0.55  -- 超过55%距离算"远端"
    end

    for _, room in ipairs(rooms) do
        if room.kind == "battle" or room.kind == "loot" then
            local count = 0
            if room.kind == "loot" then
                count = (floor <= 4) and math.random(2, 3) or math.random(3, 4)
            else
                -- 战斗房最多1个箱子
                count = 1
            end
            local usedTiles = {}  -- 防止同一房间内箱子重叠
            for _ = 1, count do
                -- 在房间内随机取一个地板格
                local bc = room.x + 1 + math.random(0, room.w - 3)
                local br = room.y + 1 + math.random(0, room.h - 3)
                bc = math.max(room.x + 1, math.min(room.x + room.w - 2, bc))
                br = math.max(room.y + 1, math.min(room.y + room.h - 2, br))
                local tileKey = bc * 10000 + br
                if not usedTiles[tileKey] then
                    usedTiles[tileKey] = true
                    -- 判断是否精英箱
                    local ddx = room.cx - spawnRoom.cx
                    local ddy = room.cy - spawnRoom.cy
                    local dist = math.sqrt(ddx*ddx + ddy*ddy)
                    local isElite = dist >= distThreshold
                    if room.kind == "loot" and math.random() < 0.20 then isElite = true end
                    if room.locked then isElite = true end
                    local cx, cy = M.TileCenter(bc, br)
                    M.boxes[#M.boxes + 1] = {
                        x=cx, y=cy, col=bc, row=br,
                        elite=isElite,
                        roomKind=room.kind,
                        lockedBonus=room.locked,
                        floor=floor,
                        opened=false,
                        searchTimer=0,
                    }
                end
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- 生成敌人刷出点：跳过出生房间，按距离分远近，远端权重更高
    -- -----------------------------------------------------------------------
    local ENEMY_TYPES = Data.ENEMY_TYPE_KEYS or {"scavenger","patrol","guard","sniper","mad"}
    local spawnPositions = {}
    local usedCells = {}

    local function cellKey(c, r) return c * 1000 + r end

    local function tryAddSpawn(room, typeHint)
        -- 在房间内部随机取一格
        for _ = 1, 8 do
            local sc = room.x + 1 + math.random(0, math.max(0, room.w - 3))
            local sr = room.y + 1 + math.random(0, math.max(0, room.h - 3))
            sc = math.max(room.x + 1, math.min(room.x + room.w - 2, sc))
            sr = math.max(room.y + 1, math.min(room.y + room.h - 2, sr))
            local k = cellKey(sc, sr)
            if not usedCells[k] and M.TileAt(sc, sr) == 0 then
                usedCells[k] = true
                local wx = (sc - 0.5) * T
                local wy = (sr - 0.5) * T
                -- 存格子坐标（兼容 Enemy.Replenish 的世界坐标格式）
                table.insert(spawnPositions, {wx, wy, typeHint})
                return true
            end
        end
        return false
    end

    -- 按距离排序所有非出生房间
    local nonSpawnRooms = {}
    for _, room in ipairs(rooms) do
        if room ~= spawnRoom then
            local ddx = room.cx - spawnRoom.cx
            local ddy = room.cy - spawnRoom.cy
            local d = math.sqrt(ddx*ddx + ddy*ddy)
            table.insert(nonSpawnRooms, {room=room, dist=d})
        end
    end
    table.sort(nonSpawnRooms, function(a, b) return a.dist < b.dist end)

    local typePool = {}
    for _, et in ipairs(ENEMY_TYPES) do
        for _ = 1, 3 do table.insert(typePool, et) end
    end

    -- 层数决定每房间敌人密度（floor越高越多）
    local densityMult = 1 + math.floor((floor - 1) / 4) * 0.4  -- 每4层+40%密度
    if isBossFloor then densityMult = densityMult * 0.6 end     -- Boss层小怪-40%
    if M.powerDown then densityMult = densityMult * 0.5 end     -- 供电层怪物-50%

    for i, entry in ipairs(nonSpawnRooms) do
        local r = entry.room
        local cnt = 0
        if r.kind == "battle" then
            local isNear = i <= math.max(1, math.floor(#nonSpawnRooms * 0.4))
            if isNear then
                cnt = 2
            else
                cnt = math.random(2, math.max(2, math.floor(3 * densityMult)))
            end
            if r.locked and math.random() < 0.5 then cnt = cnt + 1 end
        elseif r.kind == "loot" then
            cnt = (math.random() < 0.45) and 1 or 0
        end
        for _ = 1, cnt do
            local t = typePool[math.random(#typePool)]
            tryAddSpawn(r, t)
        end
    end

    -- -----------------------------------------------------------------------
    -- Boss 出生点：深端房间（exitRoom 旁边第二深）
    -- -----------------------------------------------------------------------
    local bossSpawn = nil
    if isBossFloor and bossRoom then
        -- 扩大 Boss 房间到 12×16（设计文档要求，以中心为基准，clamp 到地图边界内）
        local BOSS_W = 12
        local BOSS_H = 16
        local halfW = math.floor(BOSS_W / 2)
        local halfH = math.floor(BOSS_H / 2)
        local newX = math.max(2, bossRoom.cx - halfW)
        local newY = math.max(2, bossRoom.cy - halfH)
        -- 确保不超出地图右/下边界（留1格墙壁）
        if newX + BOSS_W - 1 > M.COLS - 1 then newX = M.COLS - BOSS_W end
        if newY + BOSS_H - 1 > M.ROWS - 1 then newY = M.ROWS - BOSS_H end
        bossRoom.x = newX
        bossRoom.y = newY
        bossRoom.w = BOSS_W
        bossRoom.h = BOSS_H
        bossRoom.cx = newX + halfW
        bossRoom.cy = newY + halfH
        -- 刻空 Boss 房间地板
        carveRoom(M.cells, bossRoom)

        -- Boss房对角掩体柱（随机选一条对角线，放2个1×2柱）
        local inset = 2
        local tl = { bossRoom.x + inset,                bossRoom.y + inset }
        local tr = { bossRoom.x + bossRoom.w - 1 - inset, bossRoom.y + inset }
        local bl = { bossRoom.x + inset,                bossRoom.y + bossRoom.h - 2 - inset }
        local br = { bossRoom.x + bossRoom.w - 1 - inset, bossRoom.y + bossRoom.h - 2 - inset }
        local pillars
        if math.random() < 0.5 then
            pillars = { tl, br }  -- 左上 + 右下
        else
            pillars = { tr, bl }  -- 右上 + 左下
        end
        for _, p in ipairs(pillars) do
            M.cells[p[2]][p[1]] = 1      -- 上格（walltop）
            M.cells[p[2] + 1][p[1]] = 1  -- 下格（墙面）
        end

        local bwx = (bossRoom.cx - 0.5) * T
        local bwy = (bossRoom.cy - 0.5) * T
        local bossKey = Data.GetBossKey(floor)
        -- 房间像素边界（用于激活检测）
        local roomPxL = (bossRoom.x - 0.5) * T
        local roomPxT = (bossRoom.y - 0.5) * T
        local roomPxR = roomPxL + bossRoom.w * T
        local roomPxB = roomPxT + bossRoom.h * T
        bossSpawn = { wx=bwx, wy=bwy, key=bossKey, roomL=roomPxL, roomT=roomPxT, roomR=roomPxR, roomB=roomPxB }
    end

    -- 出口在 Boss 层锁定（直到 Boss 死亡才开放）
    M.exitLocked = isBossFloor

    -- 预计算 Boss 房间邻居组：与 boss 房紧邻的房间视为同组
    M.bossGroup = {}  -- room -> group table (shared reference)
    if bossRoom then
        local group = { bossRoom }
        M.bossGroup[bossRoom] = group
        for _, r in ipairs(rooms) do
            if r ~= bossRoom then
                -- 检查两房间是否紧邻（边界相距 <= 2 格，含共用墙壁）
                local overlapX = not (r.x + r.w + 1 < bossRoom.x or bossRoom.x + bossRoom.w + 1 < r.x)
                local overlapY = not (r.y + r.h + 1 < bossRoom.y or bossRoom.y + bossRoom.h + 1 < r.y)
                if overlapX and overlapY then
                    group[#group + 1] = r
                    M.bossGroup[r] = group
                end
            end
        end
    end

    -- 预计算走廊连通组（flood-fill非房间地板格，相邻格归为同组）
    M.corridorGroup = {}  -- [row][col] -> group table
    local cgRows, cgCols, cgCells = M.ROWS, M.COLS, M.cells
    local visited = {}
    for row = 1, cgRows do
        M.corridorGroup[row] = {}
        visited[row] = {}
    end
    for row = 1, cgRows do
        for col = 1, cgCols do
            if cgCells[row][col] == 0 and not M.GetRoomAtTile(col, row) and not visited[row][col] then
                -- BFS flood-fill 此走廊段
                local grp = {}  -- { {col, row}, ... }
                local queue = { {col, row} }
                visited[row][col] = true
                local qi = 1
                while qi <= #queue do
                    local cur = queue[qi]; qi = qi + 1
                    grp[#grp + 1] = cur
                    M.corridorGroup[cur[2]][cur[1]] = grp
                    -- 四方向扩展
                    for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                        local nc, nr = cur[1] + d[1], cur[2] + d[2]
                        if nc >= 1 and nc <= cgCols and nr >= 1 and nr <= cgRows then
                            if not visited[nr][nc] and cgCells[nr][nc] == 0 and not M.GetRoomAtTile(nc, nr) then
                                visited[nr][nc] = true
                                queue[#queue + 1] = {nc, nr}
                            end
                        end
                    end
                end
            end
        end
    end

    -- 切层时清空旧光源，并注册出口光源
    local LightingMod = require("Lighting")
    LightingMod.Clear()
    local exitWX = (ec - 0.5) * T
    local exitWY = (er - 0.5) * T
    LightingMod.AddPersistentLight("exit_beacon", exitWX, exitWY, 140, 100, 255, 180, 0.9, 0.12)

    -- 返回玩家出生世界坐标 + 敌人刷出列表 + Boss刷出点
    local playerSpawnX = (spawnCol - 0.5) * T
    local playerSpawnY = (spawnRow - 0.5) * T
    return spawnPositions, playerSpawnX, playerSpawnY, bossSpawn
end

-- ----------------------------------------------------------------------------
-- 尸体容器 API
-- ----------------------------------------------------------------------------

-- 生成一具尸体容器（由 Enemy 模块在敌人死亡时调用）
function M.SpawnCorpse(wx, wy, lootItems, enemyName, isBoss)
    local corpse = {
        x       = wx,
        y       = wy,
        loot    = lootItems or {},
        looted  = false,
        isEnemy = true,
        isBoss  = isBoss or false,
        name    = enemyName or "敌人",
        cw      = isBoss and 6 or 5,
        ch      = isBoss and 5 or 4,
    }
    table.insert(M.corpses, corpse)
    return corpse
end

-- 获取全部尸体列表
function M.GetCorpses()
    return M.corpses
end

-- ----------------------------------------------------------------------------
-- 预览箱子内容（用于搜索面板填充）
-- 首次调用时生成并缓存战利品；已打开的箱子返回剩余内容
-- ----------------------------------------------------------------------------
function M.PeekBox(box)
    -- 如果尚未生成内容，先生成并缓存
    if not box._lootCache then
        local boxFloor = box.floor or 1
        local count, maxR
        if box.isBossChest then
            -- Boss 宝箱：固定3~4个物品，稀有度走 Boss 专属概率表
            count = math.random(3, 4)
            maxR  = Data.RollBossChestRarity(boxFloor)
        elseif box.elite then
            -- 精英箱：2~3个，稀有度比普通稍高
            count = math.random(2, 3)
            local baseR = Data.RollMaxRarity(boxFloor)
            maxR = math.min(baseR + 1, 5)
        else
            -- 普通箱：1~2个，按层数概率表
            count = math.random(1, 2)
            maxR  = Data.RollMaxRarity(boxFloor)
        end
        if box.lockedBonus then
            maxR = math.min((maxR or 1) + 1, 5)
        end
        local items = {}
        for _ = 1, count do
            local t = Data.WeightedRandom(Data.BOX_LOOT_TABLE)
            local item = M.GenerateItem(t, maxR, boxFloor)
            if item and box.lockedBonus then
                item.value = math.floor((item.value or 0) * 1.5)
            end
            if item then table.insert(items, item) end
        end
        box._lootCache = items
    end
    return box._lootCache
end

-- 标记箱子已打开（搜索完成后调用）
function M.MarkBoxOpened(box)
    box.opened = true
end

-- 同步搜索面板取走物品后，将剩余物品写回箱子缓存
function M.SyncBoxLoot(box, containerInv)
    if not box or not containerInv then return end

    -- 掉落物容器特殊处理：同步拾取状态
    if box._isDropContainer and box._drops then
        -- 收集容器中仍存在的物品名集合（用 id 匹配）
        local remainIds = {}
        for _, entry in ipairs(containerInv.items) do
            remainIds[entry.id] = true
        end
        -- 遍历原始 drop 引用列表，不在容器中的标记为已拾取
        for _, drop in ipairs(box._drops) do
            if not drop.picked then
                -- 通过 item.name+itype 匹配（容器 inv 的 entry.id 是新生成的）
                local found = false
                for _, entry in ipairs(containerInv.items) do
                    if entry.name == drop.item.name and entry.itype == drop.item.itype
                       and not entry._dropSynced then
                        entry._dropSynced = true
                        found = true
                        break
                    end
                end
                if not found then
                    drop.picked = true
                    if drop._glowId then
                        local LightMod2 = require("Lighting")
                        LightMod2.RemoveItemGlow(drop._glowId)
                    end
                    M.SpawnPickup(drop.x, drop.y)
                end
            end
        end
        -- 清理同步标记
        for _, entry in ipairs(containerInv.items) do
            entry._dropSynced = nil
        end
        return
    end

    local remaining = {}
    for _, entry in ipairs(containerInv.items) do
        table.insert(remaining, {
            itype  = entry.itype,
            data   = entry.data,
            name   = entry.name,
            icon   = entry.icon,
            rarity = entry.rarity,
            value  = entry.value,
        })
    end
    box._lootCache = remaining
end

function M.GenerateItem(itemType, maxRarity, floor)
    maxRarity = maxRarity or 3
    local valMult = Data.GetLootValueMult(floor or 1)
    local function scaled(v) return math.floor((v or 0) * valMult) end
    if itemType == "loot" then
        local loot = Data.RandomLoot(maxRarity)
        return { itype="loot", data=loot, value=scaled(loot.value), name=loot.name, icon=loot.icon, rarity=loot.rarity }
    elseif itemType == "weapon" then
        -- 技能树武器精通：概率提升稀有度上限
        local effMax = maxRarity
        if M.weaponRarityBoost and M.weaponRarityBoost > 0 and math.random() < M.weaponRarityBoost then
            effMax = math.min(maxRarity + 1, 5)
        end
        local w = Data.RandomWeapon(effMax)
        return { itype="weapon", data=w, value=scaled(w.value), name=w.name, icon="\xF0\x9F\x94\xAB", rarity=w.rarity }
    elseif itemType == "armor" then
        local e = Data.RandomEquip("armor", maxRarity)
        return { itype="armor", data=e, value=scaled(e.value), name=e.name, icon="\xF0\x9F\x9B\xA1\xEF\xB8\x8F", rarity=e.rarity }
    elseif itemType == "helmet" then
        local e = Data.RandomEquip("helmet", maxRarity)
        return { itype="helmet", data=e, value=scaled(e.value), name=e.name, icon="\xF0\x9F\xAA\x96", rarity=e.rarity }
    elseif itemType == "rig" then
        local e = Data.RandomEquip("rig", maxRarity)
        return { itype="rig", data=e, value=scaled(e.value), name=e.name, icon="\xF0\x9F\x8E\xBD", rarity=e.rarity }
    elseif itemType == "bag" then
        local e = Data.RandomEquip("bag", maxRarity)
        return { itype="bag", data=e, value=scaled(e.value), name=e.name, icon="\xF0\x9F\x8E\x92", rarity=e.rarity }
    elseif itemType == "consumable" then
        local c = Data.RandomConsumable(maxRarity)
        if not c then return nil end
        return { itype="consumable", data=c, value=scaled(c.value), name=c.name, icon=c.icon, rarity=c.rarity }
    elseif itemType == "ammo" then
        local a = Data.RandomAmmo(maxRarity)
        if not a then return nil end
        return { itype="consumable", data=a, value=scaled(a.value), name=a.name, icon=a.icon, rarity=a.rarity }
    elseif itemType == "slime_mucus" then
        -- 史莱姆专属掉落：直接返回史莱姆粘液（LOOT 表最后一项）
        local loot = Data.LOOT[#Data.LOOT]
        return { itype="loot", data=loot, value=scaled(loot.value), name=loot.name, icon=loot.icon, rarity=loot.rarity }
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- 粒子系统
-- ----------------------------------------------------------------------------
function M.SpawnParticle(x, y, vx, vy, r, g, b, life, size)
    M.particles[#M.particles + 1] = {
        x=x, y=y, vx=vx, vy=vy,
        r=r, g=g, b=b,
        life=life, maxLife=life,
        size=size or 4,
    }
end

function M.SpawnBlood(x, y, n)
    n = n or 8
    for _ = 1, n do
        local a = math.random() * math.pi * 2
        local s = 40 + math.random() * 90
        M.SpawnParticle(x, y, math.cos(a)*s, math.sin(a)*s, 210,50,50, 0.4+math.random()*0.3, 3+math.random()*3)
    end
end

function M.SpawnSpark(x, y, n)
    n = n or 8
    for _ = 1, n do
        local a = math.random() * math.pi * 2
        local s = 100 + math.random() * 160
        -- 混合白核+橙黄外层
        if math.random() < 0.3 then
            -- 白色高亮核心粒子
            M.SpawnParticle(x, y, math.cos(a)*s*0.7, math.sin(a)*s*0.7, 255,255,240, 0.10+math.random()*0.08, 2+math.random()*1.5)
        else
            -- 黄橙色火花
            M.SpawnParticle(x, y, math.cos(a)*s, math.sin(a)*s, 255,200+math.floor(math.random()*55),50+math.floor(math.random()*40), 0.18+math.random()*0.15, 2+math.random()*2.5)
        end
    end
end

-- 雷电击中闪光特效（短暂序列帧动画）
function M.SpawnLightningFx(x, y, size)
    M.lightningFx[#M.lightningFx + 1] = {
        x = x + (math.random() - 0.5) * 8,
        y = y + (math.random() - 0.5) * 8,
        life = 0.35,       -- 持续时间
        maxLife = 0.35,
        size = size or 32, -- 特效尺寸
        frame0 = math.random(0, 15),  -- 随机起始帧
    }
end

-- 浮动伤害数字（暴击时弹出红色大字）
function M.SpawnDmgPopup(x, y, dmg, isCrit)
    M.dmgPopups[#M.dmgPopups + 1] = {
        x = x + (math.random() - 0.5) * 16,
        y = y - 20,
        vy = -60,
        dmg = dmg,
        isCrit = isCrit,
        life = 0.8,
        maxLife = 0.8,
    }
end

-- 枪口闪光（射击时调用，x/y 已经是枪口尖端位置）
function M.SpawnMuzzleFlash(x, y, angle, wtype)
    M.muzzleFlashes[#M.muzzleFlashes + 1] = {
        x = x,
        y = y,
        angle = angle,
        life = 0.08,       -- 约 4-5 帧 @60fps
        maxLife = 0.08,
        radius = 14,
    }
    -- 枪口方向小火花（3粒）
    for _ = 1, 3 do
        local spread = angle + (math.random() - 0.5) * 0.6
        local s = 60 + math.random() * 100
        M.SpawnParticle(x + math.cos(angle)*4, y + math.sin(angle)*4,
            math.cos(spread)*s, math.sin(spread)*s,
            255, 220, 80, 0.06+math.random()*0.06, 1.5+math.random()*1.5)
    end
    -- 动态光照
    local Lighting = require("Lighting")
    Lighting.AddMuzzleFlashLight(x, y, wtype)
end

function M.UpdateMuzzleFlashes(dt)
    for i = #M.muzzleFlashes, 1, -1 do
        local f = M.muzzleFlashes[i]
        f.life = f.life - dt
        if f.life <= 0 then table.remove(M.muzzleFlashes, i) end
    end
end

-- 战术刀挥砍特效：少量辅助粒子（主视觉由 Render.lua 序列帧负责）
-- aimAngle: 攻击朝向角（弧度），range: 攻击范围
function M.SpawnKnifeSlash(x, y, aimAngle, range)
    -- 少量白色碎片粒子作为点缀（序列帧是主特效）
    for _ = 1, 4 do
        local spread = (math.random() - 0.5) * math.pi * 0.8
        local a = aimAngle + spread
        local s = 60 + math.random() * 50
        local dist = range * (0.5 + math.random() * 0.4)
        local px = x + math.cos(a) * dist
        local py = y + math.sin(a) * dist
        M.SpawnParticle(px, py, math.cos(a)*s, math.sin(a)*s, 220,240,255, 0.06+math.random()*0.06, 1.5+math.random()*1.5)
    end
    -- 刀尖亮点（1-2个即可）
    for _ = 1, 2 do
        local a = aimAngle + (math.random() - 0.5) * 0.4
        local dist = range * 0.85
        local px = x + math.cos(a) * dist
        local py = y + math.sin(a) * dist
        M.SpawnParticle(px, py, math.cos(a)*40, math.sin(a)*40, 255,255,255, 0.05+math.random()*0.05, 2+math.random()*1.5)
    end
end

-- 剑气波飞行尾迹（每帧调用）
function M.SpawnSlashWaveTrail(x, y, angle, life01)
    local t = life01 or 1.0
    -- 向后扩散的青白弧形粒子
    for _ = 1, 4 do
        local spread = (math.random() - 0.5) * math.pi * 0.55
        local a = angle + spread + math.pi  -- 往后飘
        local s = 50 + math.random() * 80
        local r = math.floor(140 + t * 80)
        M.SpawnParticle(x, y, math.cos(a)*s, math.sin(a)*s, r, 230, 255, 0.10 + math.random()*0.10, 1.8 + math.random()*2.2)
    end
    -- 侧向散射（模拟刀弧宽度）
    for _ = 1, 2 do
        local perp = angle + math.pi * 0.5 * (math.random() > 0.5 and 1 or -1)
        local s = 30 + math.random() * 50
        M.SpawnParticle(x, y, math.cos(perp)*s, math.sin(perp)*s, 180, 240, 255, 0.08 + math.random()*0.08, 1.2 + math.random()*1.5)
    end
    -- 中心白核亮点（短暂高亮）
    M.SpawnParticle(x, y, (math.random()-0.5)*20, (math.random()-0.5)*20, 255, 255, 255, 0.05 + math.random()*0.06, 2.5 + math.random()*2)
end

function M.SpawnPickup(x, y)
    for _ = 1, 8 do
        local a = math.random() * math.pi * 2
        M.SpawnParticle(x, y, math.cos(a)*60, math.sin(a)*60, 80,220,120, 0.4, 3)
    end
end

function M.UpdateParticles(dt)
    for i = #M.particles, 1, -1 do
        local p = M.particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vx = p.vx * 0.85
        p.vy = p.vy * 0.85
        p.life = p.life - dt
        if p.life <= 0 then table.remove(M.particles, i) end
    end
end

return M
