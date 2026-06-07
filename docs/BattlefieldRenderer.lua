-- ============================================================
-- BattlefieldRenderer.lua
-- 用 NanoVG 绘制战地风格的 BSP 地牢场景
-- 替换原有的 tilemap 逐格渲染，改为矢量绘制
--
-- 风格要点：
--   混凝土灰色地板 + 金属壁板墙面 + 3D 墙头厚感
--   地面引导线 + 房间编号钢印 + 军事标记
--   定向光照感（上亮下暗）+ 战地色调（青灰/军绿/暗橙）
-- ============================================================

local BattlefieldRenderer = {}

-- ============================================================
-- 调色板（战地风格：冷灰 + 军绿 + 标识橙）
-- ============================================================
local PALETTE = {
    -- 地板
    floorBase      = { 140, 155, 168, 255 },   -- 混凝土灰
    floorGrid      = { 125, 140, 155, 60 },    -- 地板拼缝线
    floorPanel     = { 130, 148, 162, 30 },    -- 地板面板微差

    -- 墙面
    wallFace       = { 55, 68, 82, 255 },      -- 墙面主体（军绿灰）
    wallTop        = { 70, 85, 100, 255 },     -- 墙顶高光
    wallSide       = { 40, 50, 62, 255 },      -- 墙侧阴影
    wallEdge       = { 80, 95, 110, 255 },     -- 墙棱高光

    -- 走廊
    tunnelFloor    = { 110, 125, 140, 255 },   -- 走廊地板稍暗
    tunnelWall     = { 45, 55, 68, 255 },      -- 走廊墙更暗

    -- 标识
    roomNumber     = { 180, 200, 220, 120 },   -- 房间编号
    dirLine        = { 200, 160, 80, 60 },     -- 地面引导线（暗橙）
    doorMarker     = { 220, 180, 100, 180 },   -- 门框标记

    -- 迷雾（未探索区域覆盖）
    fogOfWar       = { 8, 12, 20, 210 },       -- 战争迷雾
    fogEdge        = { 8, 12, 20, 100 },       -- 迷雾边缘过渡
}

local function rgb(t)
    return nvg.RGBA(t[1], t[2], t[3], t[4])
end

-- ============================================================
-- 绘制：单格地板
-- ============================================================
function BattlefieldRenderer.DrawFloor(nvg, x, y, s, isCorridor)
    local base = isCorridor and PALETTE.tunnelFloor or PALETTE.floorBase

    -- 底色
    nvg.BeginPath()
    nvg.Rect(x, y, s, s)
    nvg.FillColor(rgb(base))
    nvg.Fill()

    -- 面板微差（模拟混凝土预制板的接缝）
    local panelW = s * 0.92
    local panelOff = (s - panelW) / 2
    nvg.BeginPath()
    nvg.Rect(x + panelOff, y + panelOff, panelW, panelW)
    nvg.FillColor(rgb(PALETTE.floorPanel))
    nvg.Fill()

    -- 拼缝线（四边）
    nvg.StrokeColor(rgb(PALETTE.floorGrid))
    nvg.StrokeWidth(0.5)
    nvg.BeginPath()
    nvg.Rect(x, y, s, s)
    nvg.Stroke()
end

-- ============================================================
-- 绘制：单格墙体（带 3D 厚度效果）
-- ============================================================
-- 墙体用 3 个面模拟立体感：
--   顶面（亮） + 侧面（暗） + 正面（中）
-- neighborMask 标记相邻房间方向，决定哪个面露出
-- bit: 1=上, 2=右, 4=下, 8=左
function BattlefieldRenderer.DrawWall(nvg, x, y, s, neighborMask)
    neighborMask = neighborMask or 0
    local thick = s * 0.15  -- 墙头厚度比例

    -- 正面（墙面主体）
    nvg.BeginPath()
    nvg.Rect(x, y, s, s)
    nvg.FillColor(rgb(PALETTE.wallFace))
    nvg.Fill()

    -- 顶面（露出上边和左边）
    if neighborMask == 0 then
        -- 独立墙柱：四面都露顶面
        nvg.BeginPath()
        nvg.Rect(x, y, s, thick)
        nvg.FillColor(rgb(PALETTE.wallTop))
        nvg.Fill()
        nvg.BeginPath()
        nvg.Rect(x, y, thick, s)
        nvg.FillColor(rgb(PALETTE.wallTop))
        nvg.Fill()
        -- 侧面（右和下）
        nvg.BeginPath()
        nvg.Rect(x + s - thick, y, thick, s)
        nvg.FillColor(rgb(PALETTE.wallSide))
        nvg.Fill()
        nvg.BeginPath()
        nvg.Rect(x, y + s - thick, s, thick)
        nvg.FillColor(rgb(PALETTE.wallSide))
        nvg.Fill()
    else
        -- 根据邻居方向决定哪个面是"墙内"（不露出）
        local topOpen   = bit.band(neighborMask, 1) == 0
        local rightOpen = bit.band(neighborMask, 2) == 0
        local bottomOpen= bit.band(neighborMask, 4) == 0
        local leftOpen  = bit.band(neighborMask, 8) == 0

        if topOpen then
            nvg.BeginPath()
            nvg.Rect(x, y, s, thick)
            nvg.FillColor(rgb(PALETTE.wallTop))
            nvg.Fill()
        end
        if leftOpen then
            nvg.BeginPath()
            nvg.Rect(x, y, thick, s)
            nvg.FillColor(rgb(PALETTE.wallTop))
            nvg.Fill()
        end
        if rightOpen then
            nvg.BeginPath()
            nvg.Rect(x + s - thick, y, thick, s)
            nvg.FillColor(rgb(PALETTE.wallSide))
            nvg.Fill()
        end
        if bottomOpen then
            nvg.BeginPath()
            nvg.Rect(x, y + s - thick, s, thick)
            nvg.FillColor(rgb(PALETTE.wallSide))
            nvg.Fill()
        end
    end

    -- 棱边高光线（增加金属感）
    nvg.StrokeColor(rgb(PALETTE.wallEdge))
    nvg.StrokeWidth(0.8)
    nvg.BeginPath()
    nvg.Rect(x + 0.5, y + 0.5, s - 1, s - 1)
    nvg.Stroke()
end

-- ============================================================
-- 绘制：房间编号钢印（在墙壁/地面上）
-- ============================================================
function BattlefieldRenderer.DrawRoomNumber(nvg, x, y, w, h, number)
    local fontSize = math.max(10, math.min(w, h) * 0.35)

    nvg.FontSize(fontSize)
    nvg.FontFace("sans")
    nvg.TextAlign("NVG_ALIGN_CENTER", "NVG_ALIGN_MIDDLE")
    nvg.FillColor(rgb(PALETTE.roomNumber))

    -- 在地面中央写编号
    nvg.Text(x + w / 2, y + h / 2, tostring(number))
end

-- ============================================================
-- 绘制：地面引导线（战地常见的地面方向标识）
-- ============================================================
function BattlefieldRenderer.DrawDirectionLine(nvg, x1, y1, x2, y2)
    nvg.BeginPath()
    nvg.MoveTo(x1, y1)
    nvg.LineTo(x2, y2)
    nvg.StrokeColor(rgb(PALETTE.dirLine))
    nvg.StrokeWidth(1.5)
    nvg.Stroke()
end

-- ============================================================
-- 绘制：门框标记（走廊入口两侧）
-- ============================================================
function BattlefieldRenderer.DrawDoorFrame(nvg, x, y, s, horizontal)
    local len = s * 0.3
    local gap = s * 0.1

    nvg.StrokeColor(rgb(PALETTE.doorMarker))
    nvg.StrokeWidth(2)

    if horizontal then
        -- 门框在左右两侧
        -- 上短横
        nvg.BeginPath()
        nvg.MoveTo(x + gap, y + gap)
        nvg.LineTo(x + gap + len, y + gap)
        nvg.Stroke()
        -- 下短横
        nvg.BeginPath()
        nvg.MoveTo(x + gap, y + s - gap)
        nvg.LineTo(x + gap + len, y + s - gap)
        nvg.Stroke()
    else
        -- 门框在上下两侧
        nvg.BeginPath()
        nvg.MoveTo(x + gap, y + gap)
        nvg.LineTo(x + gap, y + gap + len)
        nvg.Stroke()
        nvg.BeginPath()
        nvg.MoveTo(x + s - gap, y + gap)
        nvg.LineTo(x + s - gap, y + gap + len)
        nvg.Stroke()
    end
end

-- ============================================================
-- 绘制：整层地牢
-- ============================================================
-- cells: 二维网格，0=地板，1=墙
-- rooms: BSP 房间列表
-- explored: 已探索房间索引集合 { [idx] = true }
-- currentRoom: 当前所在房间索引
-- camera: { x, y } 相机偏移（格子坐标，用于视差/滚动）
-- tileSize: 每格像素大小
function BattlefieldRenderer.DrawDungeon(nvg, cells, rooms, explored, currentRoom, camera, tileSize)
    if not cells or #cells == 0 then return end
    if not tileSize then tileSize = 32 end

    local camX = (camera and camera.x) or 0
    local camY = (camera and camera.y) or 0
    local SW, SH = 800, 500  -- 屏幕尺寸

    -- 可见范围（格数 + 缓冲）
    local visCols = math.ceil(SW / tileSize) + 2
    local visRows = math.ceil(SH / tileSize) + 2
    local startCol = math.floor(camX)
    local startRow = math.floor(camY)

    -- ============================================================
    -- 第 1 遍：地板
    -- ============================================================
    for r = startRow, startRow + visRows do
        for c = startCol, startCol + visCols do
            if r >= 1 and r <= #cells and c >= 1 and c <= #cells[r] then
                local cell = cells[r][c]
                local sx = (c - camX) * tileSize
                local sy = (r - camY) * tileSize

                if cell == 0 then
                    -- 判断是否在走廊中（不在任何房间内的地板即走廊）
                    local inRoom = false
                    for _, room in ipairs(rooms) do
                        if c >= room.x and c < room.x + room.w
                        and r >= room.y and r < room.y + room.h then
                            inRoom = true
                            break
                        end
                    end
                    BattlefieldRenderer.DrawFloor(nvg, sx, sy, tileSize, not inRoom)
                end
            end
        end
    end

    -- ============================================================
    -- 第 2 遍：墙面（带邻居检测，构建 3D 效果）
    -- ============================================================
    for r = startRow, startRow + visRows do
        for c = startCol, startCol + visCols do
            if r >= 1 and r <= #cells and c >= 1 and c <= #cells[r] then
                local cell = cells[r][c]
                local sx = (c - camX) * tileSize
                local sy = (r - camY) * tileSize

                if cell == 1 then
                    -- 检测四个方向的邻居
                    local mask = 0
                    if r > 1     and cells[r-1][c] == 1 then mask = mask + 1 end  -- 上
                    if c < #cells[r] and cells[r][c+1] == 1 then mask = mask + 2 end  -- 右
                    if r < #cells    and cells[r+1][c] == 1 then mask = mask + 4 end  -- 下
                    if c > 1     and cells[r][c-1] == 1 then mask = mask + 8 end  -- 左

                    BattlefieldRenderer.DrawWall(nvg, sx, sy, tileSize, mask)
                end
            end
        end
    end

    -- ============================================================
    -- 第 3 遍：标识（房间编号、门框）
    -- ============================================================
    for i, room in ipairs(rooms) do
        local isExplored = explored and explored[i]
        local isCurrent = (i == currentRoom)

        if isExplored or isCurrent then
            local rx = (room.x - camX) * tileSize
            local ry = (room.y - camY) * tileSize
            local rw = room.w * tileSize
            local rh = room.h * tileSize

            -- 房间编号（仅探索过的房间）
            BattlefieldRenderer.DrawRoomNumber(nvg, rx, ry, rw, rh, i)
        end
    end

    -- 走廊尽头的门框标记
    -- 检测：房间边界上、与走廊相邻的格子
    -- 简化方案：在房间入口处画门框
    if rooms then
        for i, room in ipairs(rooms) do
            if explored and explored[i] then
                -- 在房间四个边的中点检查是否有走廊接入
                local function checkDoor(cx, cy, horiz)
                    if cx >= 1 and cx <= #cells[1] and cy >= 1 and cy <= #cells then
                        local cell = cells[cy] and cells[cy][cx]
                        if cell == 0 then  -- 走廊
                            local dx = (cx - camX) * tileSize
                            local dy = (cy - camY) * tileSize
                            BattlefieldRenderer.DrawDoorFrame(nvg, dx, dy, tileSize, horiz)
                        end
                    end
                end

                -- 上边中点
                checkDoor(room.cx, room.y - 1, true)
                -- 下边中点
                checkDoor(room.cx, room.y + room.h, true)
                -- 左边中点
                checkDoor(room.x - 1, room.cy, false)
                -- 右边中点
                checkDoor(room.x + room.w, room.cy, false)
            end
        end
    end
end

-- ============================================================
-- 绘制：战争迷雾（覆盖未探索区域）
-- ============================================================
function BattlefieldRenderer.DrawFogOfWar(nvg, cells, rooms, explored, camera, tileSize)
    if not explored then return end
    if not tileSize then tileSize = 32 end

    local camX = (camera and camera.x) or 0
    local camY = (camera and camera.y) or 0
    local SW, SH = 800, 500

    -- 对每个未探索的房间，覆盖深色迷雾
    for i, room in ipairs(rooms) do
        if not explored[i] then
            local rx = (room.x - camX) * tileSize
            local ry = (room.y - camY) * tileSize
            local rw = room.w * tileSize
            local rh = room.h * tileSize

            nvg.BeginPath()
            nvg.Rect(rx, ry, rw, rh)
            nvg.FillColor(rgb(PALETTE.fogOfWar))
            nvg.Fill()
        end
    end

    -- 未探索的走廊区域覆盖迷雾（简化：覆盖所有未标记为已探索的格子）
    -- 此处略，实际可通过 exploredCells 集合实现
end

return BattlefieldRenderer
