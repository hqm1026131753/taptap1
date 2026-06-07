-- ============================================================================
-- Lobby.lua — 备战大厅系统
-- 单房间 BSP 场景，散布功能设施，玩家 WASD 自由走动 + E 交互
-- ============================================================================
local World = require("World")

local M = {}

-- 大厅地图尺寸（grid）
M.COLS = 20
M.ROWS = 12
M.TILE = World.TILE   -- 复用 World 的 T=40

-- 大厅房间（单房间，填满整个地图内圈）
M.room = { x = 1, y = 1, w = 20, h = 12, cx = 10, cy = 6 }
M.rooms = { M.room }

-- 大厅地图格子（0=地板, 1=墙）
M.cells = {}

-- 玩家在大厅中的位置（grid 坐标，浮点）
M.playerGX = 15
M.playerGY = 12
-- 玩家像素坐标
M.playerX = 0
M.playerY = 0
-- 玩家移动速度（格/秒）
M.MOVE_SPEED = 6.0

-- 当前最近的可交互设施（nil = 不在范围内）
---@type table|nil
M.nearestFacility = nil

-- 设施列表（适配 20×12 房间，纯贴图无碰撞）
M.facilities = {
    {
        id = "character_select",
        name = "选择角色",
        gx = 4, gy = 3,
        w = 2, h = 2,
        interactRange = 2.0,
        imagePath = "image/lobby/select_table.png",
        drawW = 64, drawH = 48,
        offsetX = 0, offsetY = -8,
    },
    {
        id = "shop",
        name = "商店",
        gx = 8, gy = 3,
        w = 2, h = 2,
        interactRange = 2.0,
        imagePath = "image/lobby/shop_counter.png",
        drawW = 64, drawH = 40,
        offsetX = 0, offsetY = -4,
    },
    {
        id = "skill_tree",
        name = "技能树",
        gx = 12, gy = 3,
        w = 2, h = 2,
        interactRange = 2.0,
        imagePath = "image/lobby/skill_tree.png",
        drawW = 64, drawH = 56,
        offsetX = 0, offsetY = -8,
    },
    {
        id = "portal",
        name = "出发",
        gx = 16, gy = 5,
        w = 3, h = 3,
        interactRange = 2.5,
        imagePath = "image/lobby/portal.png",
        drawW = 64, drawH = 64,
        offsetX = 0, offsetY = -8,
    },
    {
        id = "stash",
        name = "仓库",
        gx = 4, gy = 8,
        w = 2, h = 2,
        interactRange = 2.0,
        imagePath = "image/lobby/stash_box.png",
        drawW = 48, drawH = 48,
        offsetX = 0, offsetY = -4,
    },
    {
        id = "workbench",
        name = "工作台",
        gx = 8, gy = 8,
        w = 2, h = 2,
        interactRange = 2.0,
        imagePath = "image/lobby/workbench.png",
        drawW = 64, drawH = 48,
        offsetX = 0, offsetY = -4,
    },
    {
        id = "mail",
        name = "邮箱",
        gx = 12, gy = 8,
        w = 2, h = 2,
        interactRange = 2.0,
        imagePath = "image/lobby/mailbox.png",
        drawW = 32, drawH = 40,
        offsetX = 0, offsetY = -4,
    },
}

-- ============================================================================
-- 初始化大厅地图（生成单房间地图格子）
-- ============================================================================
function M.Init()
    M.cells = {}
    for row = 1, M.ROWS do
        M.cells[row] = {}
        for col = 1, M.COLS do
            -- 边缘2格为墙
            if row <= 2 or row >= M.ROWS - 1 or col <= 2 or col >= M.COLS - 1 then
                M.cells[row][col] = 1  -- 墙
            else
                M.cells[row][col] = 0  -- 地板
            end
        end
    end

    -- 设施纯贴图，不占格子，不阻挡移动

    -- 玩家初始位置：房间中央
    M.playerGX = math.floor(M.COLS / 2)
    M.playerGY = math.floor(M.ROWS / 2)
    M.playerX = M.playerGX * M.TILE
    M.playerY = M.playerGY * M.TILE

    M.nearestFacility = nil
end

-- ============================================================================
-- 碰墙检测（简化版，不允许穿越墙壁格子）
-- ============================================================================
local function IsWallAt(gx, gy)
    local col = math.floor(gx) + 1
    local row = math.floor(gy) + 1
    if col < 1 or col > M.COLS or row < 1 or row > M.ROWS then return true end
    return M.cells[row][col] == 1
end

-- 玩家半径（grid 单位）
local PLAYER_RADIUS = 0.35

local function ResolveCollision(px, py, newX, newY)
    -- 先尝试完整移动
    local testPoints = {
        { newX - PLAYER_RADIUS, newY - PLAYER_RADIUS },
        { newX + PLAYER_RADIUS, newY - PLAYER_RADIUS },
        { newX - PLAYER_RADIUS, newY + PLAYER_RADIUS },
        { newX + PLAYER_RADIUS, newY + PLAYER_RADIUS },
    }

    local xBlocked = false
    local yBlocked = false

    -- 测试 X 方向
    local txPoints = {
        { newX - PLAYER_RADIUS, py - PLAYER_RADIUS },
        { newX + PLAYER_RADIUS, py - PLAYER_RADIUS },
        { newX - PLAYER_RADIUS, py + PLAYER_RADIUS },
        { newX + PLAYER_RADIUS, py + PLAYER_RADIUS },
    }
    for _, p in ipairs(txPoints) do
        if IsWallAt(p[1], p[2]) then xBlocked = true; break end
    end

    -- 测试 Y 方向
    local tyPoints = {
        { px - PLAYER_RADIUS, newY - PLAYER_RADIUS },
        { px + PLAYER_RADIUS, newY - PLAYER_RADIUS },
        { px - PLAYER_RADIUS, newY + PLAYER_RADIUS },
        { px + PLAYER_RADIUS, newY + PLAYER_RADIUS },
    }
    for _, p in ipairs(tyPoints) do
        if IsWallAt(p[1], p[2]) then yBlocked = true; break end
    end

    local finalX = xBlocked and px or newX
    local finalY = yBlocked and py or newY

    return finalX, finalY
end

-- ============================================================================
-- 每帧更新（玩家移动 + 设施接近检测）
-- ============================================================================
function M.Update(dt, keys)
    -- 暴露当前按键状态供渲染层判断移动
    M._lastKeys = keys

    -- 计算移动方向
    local dx, dy = 0, 0
    if keys.w then dy = dy - 1 end
    if keys.s then dy = dy + 1 end
    if keys.a then dx = dx - 1 end
    if keys.d then dx = dx + 1 end

    -- 归一化对角移动
    if dx ~= 0 and dy ~= 0 then
        local len = math.sqrt(dx * dx + dy * dy)
        dx = dx / len
        dy = dy / len
    end

    -- 移动
    if dx ~= 0 or dy ~= 0 then
        local speed = M.MOVE_SPEED * dt
        local newGX = M.playerGX + dx * speed
        local newGY = M.playerGY + dy * speed

        -- 碰撞检测
        newGX, newGY = ResolveCollision(M.playerGX, M.playerGY, newGX, newGY)

        M.playerGX = newGX
        M.playerGY = newGY
    end

    -- 更新朝向
    M.UpdateFacing(keys)

    -- 同步像素坐标
    M.playerX = M.playerGX * M.TILE
    M.playerY = M.playerGY * M.TILE

    -- 设施接近检测
    M.nearestFacility = nil
    local nearestDist = math.huge

    for _, facility in ipairs(M.facilities) do
        -- 设施中心位置
        local fx = facility.gx + facility.w * 0.5
        local fy = facility.gy + facility.h * 0.5

        -- 玩家到设施中心的距离
        local ddx = M.playerGX - fx
        local ddy = M.playerGY - fy
        local dist = math.sqrt(ddx * ddx + ddy * ddy)

        if dist < facility.interactRange and dist < nearestDist then
            nearestDist = dist
            M.nearestFacility = facility
        end
    end
end

-- ============================================================================
-- 交互触发（按 E 时调用）
-- 返回设施 id（由 main.lua 路由到对应 UI）
-- ============================================================================
function M.Interact()
    if M.nearestFacility then
        return M.nearestFacility.id
    end
    return nil
end

-- ============================================================================
-- 获取玩家朝向角度（用于绘制方向指示，默认朝下）
-- ============================================================================
M.playerAngle = math.pi * 0.5  -- 默认朝下

function M.UpdateFacing(keys)
    if keys.w then M.playerAngle = -math.pi * 0.5
    elseif keys.s then M.playerAngle = math.pi * 0.5
    elseif keys.a then M.playerAngle = math.pi
    elseif keys.d then M.playerAngle = 0
    end
end

return M
