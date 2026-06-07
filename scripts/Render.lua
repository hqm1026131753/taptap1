-- ============================================================================
-- Render.lua — 所有 NanoVG 绘制逻辑
-- ============================================================================
local Data = require("Data")
local World = require("World")
local PixelUI = require("PixelUI")
local Lighting = require("Lighting")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")
local Boss = require("Boss")
local Boss3 = require("Boss3")
local Boss4 = require("Boss4")
local Slime = require("Slime")
local BattlePrepUI = require("BattlePrepUI")

local M = {}
M.dt = 1/60  -- 每帧 dt，由 main.lua 每帧更新

-- ── 子弹贴图 ──
local bulletImg = nil
local bulletImgLoaded = false
local BULLET_IMG_PATH = "image/子弹/e94115f8c7186a701fe9645db5f4ad59.png"

local smgBulletImg = nil
local smgBulletImgLoaded = false
local SMG_BULLET_IMG_PATH = "image/子弹/605d7f05b54362dde902236dc59eac9c.png"

local hmgBulletImg = nil
local hmgBulletImgLoaded = false
local HMG_BULLET_IMG_PATH = "image/子弹/db5b3a0fbe0b4266978a2f6587acb7c7.png"

local sniperBulletImg = nil
local sniperBulletImgLoaded = false
local SNIPER_BULLET_IMG_PATH = "image/子弹/8dd08a94419f66d35ba70d4777593c70.png"

local arrowBulletImg = nil
local arrowBulletImgLoaded = false
local ARROW_BULLET_IMG_PATH = "image/小怪/骷髅射手/bullet0 (3).png"

local function LoadBulletImg(ctx)
    if bulletImgLoaded then return end
    bulletImg = nvgCreateImage(ctx, BULLET_IMG_PATH, 0)
    bulletImgLoaded = true
end

local function LoadSmgBulletImg(ctx)
    if smgBulletImgLoaded then return end
    smgBulletImg = nvgCreateImage(ctx, SMG_BULLET_IMG_PATH, 0)
    smgBulletImgLoaded = true
end

local function LoadHmgBulletImg(ctx)
    if hmgBulletImgLoaded then return end
    hmgBulletImg = nvgCreateImage(ctx, HMG_BULLET_IMG_PATH, 0)
    hmgBulletImgLoaded = true
end

local function LoadSniperBulletImg(ctx)
    if sniperBulletImgLoaded then return end
    sniperBulletImg = nvgCreateImage(ctx, SNIPER_BULLET_IMG_PATH, 0)
    sniperBulletImgLoaded = true
end

local function LoadArrowBulletImg(ctx)
    if arrowBulletImgLoaded then return end
    arrowBulletImg = nvgCreateImage(ctx, ARROW_BULLET_IMG_PATH, 0)
    arrowBulletImgLoaded = true
end

-- ── 斩击特效帧动画（精灵图，additive 混合） ──
local batSheetImgs = {}  -- 暗影蝠精灵表句柄缓存
local patrolSheetImgs = {}  -- 骷髅射手精灵表句柄缓存

local slashImg = nil
local slashImgLoaded = false
local SLASH_IMG_PATH = "image/子弹/fd8d815da6b5148ecbbd60485e1626bb.png"
local SLASH_SHEET_W = 79     -- 精灵图总宽
local SLASH_SHEET_H = 32     -- 精灵图总高
local SLASH_FRAME_COUNT = 2  -- 只用前两帧
local SLASH_FRAME_W = 26     -- 每帧宽度 ≈ 79/3

local function LoadSlashImg(ctx)
    if slashImgLoaded then return end
    slashImg = nvgCreateImage(ctx, SLASH_IMG_PATH, 0)
    slashImgLoaded = true
end

-- 玩家脚后跟灰尘粒子池
local dustParticles = {}
local DUST_MAX = 12

local T = World.TILE

-- 稀有度颜色辅助
local function RC(r)
    local c = Data.RARITY_COLOR[r] or {180,180,180}
    return c[1], c[2], c[3]
end

-- 物品图片缓存 (img path -> nvg handle)
local itemImgCache = {}
local function GetItemImg(ctx, path)
    if not path then return nil end
    if itemImgCache[path] == nil then
        itemImgCache[path] = nvgCreateImage(ctx, path, 0) or false
    end
    local h = itemImgCache[path]
    return (h and h > 0) and h or nil
end

--- 绘制物品图标：有 img 则画图片，否则画 emoji 文本
--- cx, cy: 图标中心坐标；maxW: 可用宽度；maxH: 可用高度（可选，默认等于 maxW）
--- 图片按原始比例等比缩放（contain 模式），不拉伸
local function DrawItemIcon(ctx, item, cx, cy, maxW, maxH)
    local imgPath = item.img or (item.data and item.data.img)
    if imgPath then
        local img = GetItemImg(ctx, imgPath)
        if img then
            local areaW = maxW or 28
            local areaH = maxH or areaW
            -- 获取图片原始尺寸，按比例缩放
            local iw, ih = nvgImageSize(ctx, img)
            local drawW, drawH
            if iw > 0 and ih > 0 then
                local scale = math.min(areaW / iw, areaH / ih)
                drawW = iw * scale
                drawH = ih * scale
            else
                drawW = areaW
                drawH = areaH
            end
            local pat = nvgImagePattern(ctx, cx - drawW/2, cy - drawH/2, drawW, drawH, 0, img, 1.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, cx - drawW/2, cy - drawH/2, drawW, drawH)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)
            return
        end
    end
    -- fallback: emoji
    nvgText(ctx, cx, cy, item.icon or "?", nil)
end

-- lerp
local function lerp(a, b, t) return a + (b-a)*t end

-- ============================================================================
-- 武器像素图标系统
-- ============================================================================
local WEAPON_IMG_PATHS = {
    Glock       = "image/gun/格洛克17-0063.png",
    M1911       = "image/gun/m1911-0064.png",
    DesertEagle = "image/gun/沙漠之鹰-0061.png",
    G18         = "image/gun/G18-0060.png",
    MP5         = "image/gun/MP5-0066.png",
    UZI         = "image/gun/UZI-0065.png",
    MP7         = "image/gun/MP7-0079.png",
    P90         = "image/gun/P90-0001.png",
    M16         = "image/gun/M16-0070.png",
    AKM         = "image/gun/AKM-0069.png",
    AUG         = "image/gun/AUG-0003.png",
    M870        = "image/gun/M870-0073.png",
    M1014       = "image/gun/M1014-0074.png",
    AWM         = "image/gun/AWM-0077.png",
    R93         = "image/gun/R93-0078.png",
    PKM         = "image/gun/pkm-0076.png",
    M250        = "image/gun/M250-0075.png",
}
local weaponImgCache = {}  -- key → nvg image handle
local shockEffectImg = nil  -- 感电特效序列帧



--- 获取武器图片句柄（缓存加载）
local function getWeaponImage(ctx, weaponKey)
    if weaponImgCache[weaponKey] then return weaponImgCache[weaponKey] end
    local path = WEAPON_IMG_PATHS[weaponKey]
    if not path then return nil end
    local handle = nvgCreateImage(ctx, path, NVG_IMAGE_NEAREST)
    if handle and handle > 0 then
        weaponImgCache[weaponKey] = handle
        return handle
    end
    return nil
end

-- ============================================================================
-- 背包图标
-- ============================================================================
local backpackImgs = {}  -- bagId → nvg handle
local BAG_IMG_PATHS = {
    small   = "image/小背包-0014.png",
    medium  = "image/中型背包-0015.png",
    large   = "image/大型军用背包-0016.png",
    medic   = "image/野战医疗背包-0017.png",
    assault = "image/穿击背包-0018.png",
}
local function drawBackpackIcon(ctx, x, y, size, bagId)
    local id = bagId or "small"
    local path = BAG_IMG_PATHS[id] or BAG_IMG_PATHS["small"]
    if not backpackImgs[id] then
        backpackImgs[id] = nvgCreateImage(ctx, path, 0)
    end
    local img = backpackImgs[id]
    if not img or img <= 0 then return x end
    local s = size or 14
    local pat = nvgImagePattern(ctx, x, y - s * 0.5, s, s, 0, img, 1.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y - s * 0.5, s, s)
    nvgFillPaint(ctx, pat)
    nvgFill(ctx)
    return x + s + 2
end

-- ============================================================================
-- 护甲图标
-- ============================================================================
local armorImgs = {}
local ARMOR_IMG_PATHS = {
    armor_tact = "image/战术背心-0023.png",
    armor_light = "image/轻型防弹衣-0024.png",
    armor_medium = "image/中型防弹衣-0025.png",
    armor_heavy = "image/重型防弹衣-0027.png",
    armor_ceramic = "image/复合陶瓷甲-0028.png",
}
local function drawArmorIcon(ctx, x, y, size, armorId)
    local id = armorId or ""
    local path = ARMOR_IMG_PATHS[id]
    if not path then return nil end
    if not armorImgs[id] then
        armorImgs[id] = nvgCreateImage(ctx, path, 0)
    end
    local img = armorImgs[id]
    if not img or img <= 0 then return nil end
    local s = size or 14
    local pat = nvgImagePattern(ctx, x, y - s * 0.5, s, s, 0, img, 1.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y - s * 0.5, s, s)
    nvgFillPaint(ctx, pat)
    nvgFill(ctx)
    return x + s + 2
end

-- ============================================================================
-- 头盔图标
-- ============================================================================
local helmetImgs = {}
local HELMET_IMG_PATHS = {
    cap = "image/棒球帽-0019.png",
    helm_light = "image/防弹头盔-0020.png",
    helm_heavy = "image/重型头盔-0021.png",
    helm_full = "image/军用全罩盔-0022.png",
}
local function drawHelmetIcon(ctx, x, y, size, helmetId)
    local id = helmetId or "cap"
    local path = HELMET_IMG_PATHS[id]
    if not path then return nil end
    if not helmetImgs[id] then
        helmetImgs[id] = nvgCreateImage(ctx, path, 0)
    end
    local img = helmetImgs[id]
    if not img or img <= 0 then return nil end
    local s = size or 14
    local pat = nvgImagePattern(ctx, x, y - s * 0.5, s, s, 0, img, 1.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y - s * 0.5, s, s)
    nvgFillPaint(ctx, pat)
    nvgFill(ctx)
    return x + s + 2
end

-- ============================================================================
-- 金币图标
-- ============================================================================
local moneyImg = nil
--- 绘制金币图标（左对齐，返回图标右边 x 坐标）
local function drawMoneyIcon(ctx, x, y, size)
    if not moneyImg then
        moneyImg = nvgCreateImage(ctx, "image/money-0013.png", 0)
    end
    if not moneyImg or moneyImg <= 0 then return x end
    local s = size or 14
    local pat = nvgImagePattern(ctx, x, y - s * 0.5, s, s, 0, moneyImg, 1.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y - s * 0.5, s, s)
    nvgFillPaint(ctx, pat)
    nvgFill(ctx)
    return x + s + 2
end

-- ============================================================================
-- 地板贴图
-- ============================================================================
---@type integer
local floorTileImg = nil
---@type integer
local wallTileImg = nil
---@type integer
local wallTopTileImg = nil
local FLOOR_TEX_SIZE = 64  -- 贴图原始尺寸
local WALL_TEX_SIZE = 64   -- 墙贴图原始尺寸

-- 伪随机种子系统（墙面等仍需使用）
local floorSeed = 0
local function seedFromPos(x, y, layer)
    floorSeed = ((x * 73856093) ~ (y * 19349663) ~ (layer * 83492791)) % 2147483647
end
local function rand()
    floorSeed = (floorSeed * 1103515245 + 12345) % 2147483648
    return (floorSeed % 10000) / 10000.0
end

-- ============================================================================
-- 地图
-- ============================================================================
function M.DrawMap(ctx, camX, camY, sw, sh, time, visibleRooms)
    time = time or 0

    local startCol = math.max(1, math.floor(camX/T)+1)
    local endCol   = math.min(World.COLS, math.ceil((camX+sw)/T)+1)
    local startRow = math.max(1, math.floor(camY/T)+1)
    local endRow   = math.min(World.ROWS, math.ceil((camY+sh)/T)+1)

    -- 计算玩家格子位置（用于走廊/墙壁可见性判定）
    local playerCol, playerRow = 0, 0
    if visibleRooms then
        local pcx = camX + sw * 0.5
        local pcy = camY + sh * 0.5
        playerCol = math.floor(pcx / T) + 1
        playerRow = math.floor(pcy / T) + 1
    end

    for row = startRow, endRow do
        for col = startCol, endCol do
            local tile = World.cells[row][col]
            local wx = (col-1)*T - camX
            local wy = (row-1)*T - camY

            -- 视野过滤：不可见格子不绘制（墙壁除外 - 显示为轮廓）
            if visibleRooms then
                local tileVisible = World.IsTileVisible(col, row, playerCol, playerRow, visibleRooms)
                if not tileVisible then
                    goto continue_tile
                end
            end

            if tile == 1 then
                local belowIsFloor = (row >= World.ROWS) or (World.cells[row+1][col] ~= 1)
                if belowIsFloor then
                    -- === 暴露墙面 ===
                    -- 最底行特殊规则：上方有渲染才自己渲染，上方虚空则跳过
                    local shouldRender = true
                    if row >= World.ROWS then
                        local ar = row - 1
                        if ar >= 1 and World.cells[ar][col] == 1 then
                            -- 上方是墙，检查它是否会渲染（墙面或 wall top）
                            local arBelowIsFloor = (ar >= World.ROWS) or (World.cells[ar+1][col] ~= 1)
                            if not arBelowIsFloor then
                                -- 上方不是墙面，检查它是否 adjFloor（wall top）
                                local arAdj = false
                                for dr = -1, 1 do
                                    for dc = -1, 1 do
                                        if dr ~= 0 or dc ~= 0 then
                                            local nr, nc = ar + dr, col + dc
                                            if nr >= 1 and nr <= World.ROWS and nc >= 1 and nc <= World.COLS then
                                                if World.cells[nr][nc] ~= 1 then arAdj = true end
                                            end
                                        end
                                        if arAdj then break end
                                    end
                                    if arAdj then break end
                                end
                                if not arAdj then
                                    shouldRender = false  -- 上方是虚空，自己也不渲染
                                end
                            end
                        end
                    end
                    if shouldRender then
                        if not wallTileImg then
                            wallTileImg = nvgCreateImage(ctx, "image/墙-0009.png", NVG_IMAGE_NEAREST | NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY)
                        end
                        local pat = nvgImagePattern(ctx, wx, wy, T, T, 0, wallTileImg, 1.0)
                        nvgBeginPath(ctx) nvgRect(ctx, wx, wy, T, T)
                        nvgFillPaint(ctx, pat) nvgFill(ctx)
                        nvgBeginPath(ctx) nvgRect(ctx, wx, wy, T, T)
                        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 15))
                        nvgFill(ctx)
                    end
                else
                    -- === 下方也是墙：walltop 在 DrawWallTop 中单独绘制（覆盖玩家之上） ===
                    -- 这里不绘制 walltop，仅处理 walltop 下方的补墙逻辑
                    local adjFloor = false
                    for dr = -1, 1 do
                        for dc = -1, 1 do
                            if dr ~= 0 or dc ~= 0 then
                                local nr, nc = row + dr, col + dc
                                if nr >= 1 and nr <= World.ROWS and nc >= 1 and nc <= World.COLS then
                                    if World.cells[nr][nc] ~= 1 then adjFloor = true end
                                end
                            end
                            if adjFloor then break end
                        end
                        if adjFloor then break end
                    end
                    if adjFloor then
                        -- 若 wall top 正下方视觉上是虚空，补一格墙面（这部分仍在底层绘制）
                        local br = row + 1
                        if br <= World.ROWS and World.cells[br][col] == 1 then
                            local brIsWallFace = (br >= World.ROWS) or (World.cells[br+1][col] ~= 1)
                            if not brIsWallFace then
                                local brAdj = false
                                for dr2 = -1, 1 do
                                    for dc2 = -1, 1 do
                                        if dr2 ~= 0 or dc2 ~= 0 then
                                            local nr2, nc2 = br + dr2, col + dc2
                                            if nr2 >= 1 and nr2 <= World.ROWS and nc2 >= 1 and nc2 <= World.COLS then
                                                if World.cells[nr2][nc2] ~= 1 then brAdj = true end
                                            end
                                        end
                                        if brAdj then break end
                                    end
                                    if brAdj then break end
                                end
                                if not brAdj then
                                    -- 下方是虚空，补一格墙面
                                    if not wallTileImg then
                                        wallTileImg = nvgCreateImage(ctx, "image/墙-0009.png", NVG_IMAGE_NEAREST | NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY)
                                    end
                                    local bwx = (col-1) * T - camX
                                    local bwy = br * T - T - camY
                                    local wpat = nvgImagePattern(ctx, bwx, bwy, T, T, 0, wallTileImg, 1.0)
                                    nvgBeginPath(ctx) nvgRect(ctx, bwx, bwy, T, T)
                                    nvgFillPaint(ctx, wpat) nvgFill(ctx)
                                    nvgBeginPath(ctx) nvgRect(ctx, bwx, bwy, T, T)
                                    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 15))
                                    nvgFill(ctx)
                                end
                            end
                        end
                    end
                end
            elseif tile == 2 then
                -- 撤离区地板 - 深绿底
                nvgBeginPath(ctx) nvgRect(ctx,wx,wy,T,T)
                nvgFillColor(ctx, nvgRGBA(20,60,30,255)) nvgFill(ctx)
                -- 黄色警示斜纹（每隔16px画一条）
                nvgSave(ctx)
                nvgIntersectScissor(ctx, wx, wy, T, T)
                nvgStrokeWidth(ctx, 3)
                nvgStrokeColor(ctx, nvgRGBA(200,180,30,80))
                for k = -T, T*2, 16 do
                    nvgBeginPath(ctx)
                    nvgMoveTo(ctx, wx+k,       wy)
                    nvgLineTo(ctx, wx+k+T,     wy+T)
                    nvgStroke(ctx)
                end
                nvgRestore(ctx)
                -- 绿色光晕
                local glow = nvgRadialGradient(ctx, wx+T/2, wy+T/2, 4, T*0.8,
                    nvgRGBA(80,255,120,80), nvgRGBA(80,255,120,0))
                nvgBeginPath(ctx) nvgRect(ctx,wx,wy,T,T)
                nvgFillPaint(ctx,glow) nvgFill(ctx)
            else
                -- ═══ 地板贴图平铺（随机旋转90°，略微放大消除缝隙） ═══
                if not floorTileImg then
                    floorTileImg = nvgCreateImage(ctx, "image/地板-0008.png", NVG_IMAGE_NEAREST | NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY)
                end
                seedFromPos(col, row, 3)
                local rot = math.floor(rand() * 4) * (math.pi * 0.5)
                local cx, cy = wx + T * 0.5, wy + T * 0.5
                local S = T + 2  -- 略大于 tile 消除接缝
                nvgSave(ctx)
                nvgTranslate(ctx, cx, cy)
                nvgRotate(ctx, rot)
                local pat = nvgImagePattern(ctx, -S * 0.5, -S * 0.5, S, S, 0, floorTileImg, 1.0)
                nvgBeginPath(ctx) nvgRect(ctx, -S * 0.5, -S * 0.5, S, S)
                nvgFillPaint(ctx, pat) nvgFill(ctx)
                -- 每块地砖略微深浅不同（0~7）
                seedFromPos(col, row, 9)
                local shade = math.floor(rand() * 14) - 7  -- -7 ~ +6
                if shade > 0 then
                    nvgBeginPath(ctx) nvgRect(ctx, -S * 0.5, -S * 0.5, S, S)
                    nvgFillColor(ctx, nvgRGBA(255, 255, 255, shade))
                    nvgFill(ctx)
                elseif shade < 0 then
                    nvgBeginPath(ctx) nvgRect(ctx, -S * 0.5, -S * 0.5, S, S)
                    nvgFillColor(ctx, nvgRGBA(0, 0, 0, -shade))
                    nvgFill(ctx)
                end
                nvgRestore(ctx)
            end

            -- (光照由 DrawLighting 统一绘制径向渐变)
            ::continue_tile::
        end
    end



end

-- ============================================================================
-- WallTop 图层（在玩家/敌人之上绘制，遮挡角色实现层次感）
-- ============================================================================
function M.DrawWallTop(ctx, camX, camY, sw, sh, visibleRooms)
    local startCol = math.max(1, math.floor(camX/T)+1)
    local endCol   = math.min(World.COLS, math.ceil((camX+sw)/T)+1)
    local startRow = math.max(1, math.floor(camY/T)+1)
    local endRow   = math.min(World.ROWS, math.ceil((camY+sh)/T)+1)

    -- 玩家格子位置（用于走廊/墙壁可见性判定）
    local playerCol, playerRow = 0, 0
    if visibleRooms then
        local pcx = camX + sw * 0.5
        local pcy = camY + sh * 0.5
        playerCol = math.floor(pcx / T) + 1
        playerRow = math.floor(pcy / T) + 1
    end

    for row = startRow, endRow do
        for col = startCol, endCol do
            -- 视野过滤
            if visibleRooms then
                if not World.IsTileVisible(col, row, playerCol, playerRow, visibleRooms) then
                    goto continue_walltop
                end
            end
            local tile = World.cells[row][col]
            if tile == 1 then
                local belowIsFloor = (row >= World.ROWS) or (World.cells[row+1][col] ~= 1)
                if not belowIsFloor then
                    -- 紧邻地板（含对角）才显示 wall top
                    local adjFloor = false
                    for dr = -1, 1 do
                        for dc = -1, 1 do
                            if dr ~= 0 or dc ~= 0 then
                                local nr, nc = row + dr, col + dc
                                if nr >= 1 and nr <= World.ROWS and nc >= 1 and nc <= World.COLS then
                                    if World.cells[nr][nc] ~= 1 then adjFloor = true end
                                end
                            end
                            if adjFloor then break end
                        end
                        if adjFloor then break end
                    end
                    if adjFloor then
                        if not wallTopTileImg then
                            wallTopTileImg = nvgCreateImage(ctx, "image/walltop-0011.png", NVG_IMAGE_NEAREST | NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY)
                        end
                        local wx = (col-1)*T - camX
                        local wy = (row-1)*T - camY
                        seedFromPos(col, row, 12)
                        local rot = math.floor(rand() * 4) * (math.pi * 0.5)
                        local cx, cy = wx + T * 0.5, wy + T * 0.5
                        local S = T + 2
                        nvgSave(ctx)
                        nvgTranslate(ctx, cx, cy)
                        nvgRotate(ctx, rot)
                        local pat = nvgImagePattern(ctx, -S * 0.5, -S * 0.5, S, S, 0, wallTopTileImg, 1.0)
                        nvgBeginPath(ctx) nvgRect(ctx, -S * 0.5, -S * 0.5, S, S)
                        nvgFillPaint(ctx, pat) nvgFill(ctx)
                        nvgBeginPath(ctx) nvgRect(ctx, -S * 0.5, -S * 0.5, S, S)
                        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 15))
                        nvgFill(ctx)
                        nvgRestore(ctx)
                    end
                end
            end
            ::continue_walltop::
        end
    end
end

-- ============================================================================
-- 动态光照渲染（径向渐变方式，平滑无方块感）
-- 在场景绘制完成后、FOV遮罩之前调用（世界空间坐标系）
-- ============================================================================
function M.DrawLighting(ctx, camX, camY, time)
    time = time or 0
    local lights = Lighting.lights
    local persistent = Lighting.persistentLights

    -- 临时光源（枪口闪光、爆炸等）
    for _, l in ipairs(lights) do
        local sx = l.x - camX
        local sy = l.y - camY
        -- 生命衰减
        local lifeFade = math.min(1.0, l.life / (l.maxLife * 0.3))
        local alpha = math.floor(l.intensity * lifeFade * 40)
        if alpha < 2 then goto continue_temp end
        if alpha > 140 then alpha = 140 end

        local innerR = l.radius * 0.45  -- 柔和核心区（更大=更散）
        local outerR = l.radius

        -- 彩色光晕（加法叠加）
        local grad = nvgRadialGradient(ctx, sx, sy, innerR, outerR,
            nvgRGBA(l.r, l.g, l.b, alpha),
            nvgRGBA(l.r, l.g, l.b, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, outerR)
        nvgFillPaint(ctx, grad)
        nvgFill(ctx)

        ::continue_temp::
    end

    -- 持久光源（火把、篝火等）
    for _, l in pairs(persistent) do
        local sx = l.x - camX
        local sy = l.y - camY
        -- 闪烁
        local flick = 1.0
        if l.flicker > 0 then
            flick = 1.0 - l.flicker * (0.5 + 0.5 * math.sin(time * 8.0 + l.phase))
            flick = flick - l.flicker * 0.3 * math.sin(time * 23.0 + l.phase * 2.7)
            flick = math.max(0.3, math.min(1.0, flick))
        end
        local alpha = math.floor(l.intensity * flick * 90)
        if alpha < 2 then goto continue_persist end
        if alpha > 255 then alpha = 255 end

        local innerR = l.radius * 0.12
        local outerR = l.radius * flick

        local grad = nvgRadialGradient(ctx, sx, sy, innerR, outerR,
            nvgRGBA(l.r, l.g, l.b, alpha),
            nvgRGBA(l.r, l.g, l.b, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, outerR)
        nvgFillPaint(ctx, grad)
        nvgFill(ctx)

        ::continue_persist::
    end
end

-- ============================================================================
-- 撤离点信标（停机坪效果）
-- ============================================================================
function M.DrawExitMarkers(ctx, camX, camY, sw, sh, time, exitFound)
    if not World.EXIT_CENTER then return end
    if not exitFound then return end   -- 未发现撤离点时不显示导航

    local cx = (World.EXIT_CENTER.col - 0.5) * T - camX
    local cy = (World.EXIT_CENTER.row - 0.5) * T - camY

    -- ---- 脉冲扩散圆 ----
    local p1 = (time * 1.6) % 1.0           -- 0→1 循环
    local p2 = (time * 1.6 + 0.5) % 1.0     -- 相位差半圈
    for _, p in ipairs({p1, p2}) do
        local r   = 44 + p * 40
        local alp = math.floor(180 * (1 - p))
        nvgBeginPath(ctx) nvgCircle(ctx, cx, cy, r)
        nvgStrokeColor(ctx, nvgRGBA(80,255,120,alp))
        nvgStrokeWidth(ctx, 2.5) nvgStroke(ctx)
    end

    -- ---- 外固定圆圈 ----
    nvgBeginPath(ctx) nvgCircle(ctx, cx, cy, 44)
    nvgStrokeColor(ctx, nvgRGBA(80,255,120,180))
    nvgStrokeWidth(ctx, 2) nvgStroke(ctx)

    -- ---- 中心暗底 ----
    nvgBeginPath(ctx) nvgCircle(ctx, cx, cy, 28)
    nvgFillColor(ctx, nvgRGBA(10,40,18,210)) nvgFill(ctx)
    nvgBeginPath(ctx) nvgCircle(ctx, cx, cy, 28)
    nvgStrokeColor(ctx, nvgRGBA(80,255,120,255))
    nvgStrokeWidth(ctx, 2.5) nvgStroke(ctx)

    -- ---- 旋转十字线（四条短横） ----
    local rot = time * 0.8
    for i = 0, 3 do
        local a = rot + i * math.pi * 0.5
        local ix = cx + math.cos(a) * 14
        local iy = cy + math.sin(a) * 14
        local ox = cx + math.cos(a) * 26
        local oy = cy + math.sin(a) * 26
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, ix, iy) nvgLineTo(ctx, ox, oy)
        nvgStrokeColor(ctx, nvgRGBA(80,255,120,200))
        nvgStrokeWidth(ctx, 2) nvgStroke(ctx)
    end

    -- ---- 直升机图标 + EVAC 文字 ----
    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(ctx, 22)
    nvgFillColor(ctx, nvgRGBA(100,255,140,255))
    nvgText(ctx, cx, cy - 5, "🚁", nil)
    nvgFontSize(ctx, 10)
    nvgFillColor(ctx, nvgRGBA(160,255,180,220))
    nvgText(ctx, cx, cy + 16, "EVAC", nil)

    -- ---- 屏幕边缘方向箭头（当撤离点不在视野内时） ----
    local margin = 48
    local offscreen = cx < -margin or cx > sw+margin or cy < -margin or cy > sh+margin
    if offscreen then
        -- 把方向箭头钉在屏幕边缘
        local ax = math.max(margin, math.min(sw-margin, cx))
        local ay = math.max(margin, math.min(sh-margin, cy))
        -- 箭头朝向
        local adx, ady = cx - sw*0.5, cy - sh*0.5
        local alen = math.sqrt(adx*adx + ady*ady)
        if alen > 0 then adx = adx/alen; ady = ady/alen end
        -- 边缘贴边
        local edgeX = sw*0.5 + adx * (sw*0.44)
        local edgeY = sh*0.5 + ady * (sh*0.44)
        local pulse = (math.sin(time*4)+1)*0.5
        nvgSave(ctx)
        nvgTranslate(ctx, edgeX, edgeY)
        nvgRotate(ctx, math.atan(ady, adx))
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, 12,  0)
        nvgLineTo(ctx, -8, -7)
        nvgLineTo(ctx, -8,  7)
        nvgClosePath(ctx)
        nvgFillColor(ctx, nvgRGBA(80,255,120, math.floor(180+pulse*75)))
        nvgFill(ctx)
        nvgFontSize(ctx,9) nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_TOP)
        nvgFillColor(ctx,nvgRGBA(160,255,180,220))
        nvgText(ctx,0,10,"EVAC",nil)
        nvgRestore(ctx)
    end
end

-- ============================================================================
-- FOV 暗视野遮罩（玩家光圈内透明，圈外渐变变暗）
-- px, py: 玩家屏幕坐标（世界坐标 - 相机坐标）
-- fovRadius: 视野半径（像素）
-- ============================================================================
function M.DrawFOVOverlay(ctx, px, py, sw, sh, fovRadius)
    -- 断电模式：深度黑暗，只保留玩家周围极小的有效视野
    if World.powerDown then
        local innerR = fovRadius * 0.18   -- 极小核心区
        local outerR = fovRadius * 0.38   -- 过渡更短

        local grad = nvgRadialGradient(ctx, px, py, innerR, outerR,
            nvgRGBA(0, 0, 0, 0),    -- 内圈：完全透明
            nvgRGBA(0, 0, 0, 240))  -- 外圈：几乎全黑

        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, sw, sh)
        nvgFillPaint(ctx, grad)
        nvgFill(ctx)
        return
    end

    -- 正常模式：径向渐变，内圈透明 → 外圈纯黑，一次性覆盖全屏
    -- innerR 之内：alpha=0（完全透明，看得清）
    -- outerR 之外：alpha=105（视野外明显更暗）
    local innerR = fovRadius * 0.42   -- 清晰核心区（略收窄）
    local outerR = fovRadius * 0.82   -- 过渡结束

    local grad = nvgRadialGradient(ctx, px, py, innerR, outerR,
        nvgRGBA(0, 0, 0, 0),    -- 内圈：完全透明
        nvgRGBA(0, 0, 0, 105))  -- 外圈：视野外更暗

    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, sw, sh)
    nvgFillPaint(ctx, grad)
    nvgFill(ctx)
end

-- ============================================================================
-- 断电时灯光穿透效果（屏幕空间，绘制在 FOV 遮罩之上）
-- ============================================================================
function M.DrawLampGlowthrough(ctx, camX, camY, zoom, visibleRooms)
    local rooms = World.GetRooms and World.GetRooms() or {}
    for _, room in ipairs(rooms) do
        if not room.lamp then goto continue_lampglow end
        local lamp = room.lamp
        local lwx, lwy = World.TileCenter(lamp.col, lamp.row)
        -- 换算为屏幕坐标
        local lsx = (lwx - camX) * zoom
        local lsy = (lwy - camY) * zoom
        -- 脉动动画
        local lampSeed = lamp.col * 131 + lamp.row * 97
        local lampPulse = 0.6 + 0.4 * math.sin((World.time or 0) * 2.2 + lampSeed * 0.03)
        -- 远处灯光晕（暖橙色，穿透黑暗）
        nvgBeginPath(ctx)
        nvgCircle(ctx, lsx, lsy - 6 * zoom, 28 * zoom)
        local glowA = math.floor(30 * lampPulse)
        nvgFillPaint(ctx, nvgRadialGradient(ctx, lsx, lsy - 6 * zoom, 3 * zoom, 28 * zoom,
            nvgRGBA(255, 170, 50, glowA), nvgRGBA(255, 120, 20, 0)))
        nvgFill(ctx)
        -- 核心亮点
        nvgBeginPath(ctx)
        nvgCircle(ctx, lsx, lsy - 10 * zoom, 8 * zoom)
        local coreA = math.floor(50 * lampPulse)
        nvgFillPaint(ctx, nvgRadialGradient(ctx, lsx, lsy - 10 * zoom, 1 * zoom, 8 * zoom,
            nvgRGBA(255, 230, 150, coreA), nvgRGBA(255, 180, 60, 0)))
        nvgFill(ctx)
        ::continue_lampglow::
    end
end

-- ============================================================================
-- 断电时枪火照亮效果（屏幕空间，绘制在 FOV 遮罩之上）
-- ============================================================================
function M.DrawMuzzleFlashGlow(ctx, camX, camY, zoom)
    for _, f in ipairs(World.muzzleFlashes) do
        local t = f.life / f.maxLife  -- 1→0 衰减
        local sx = (f.x - camX) * zoom
        local sy = (f.y - camY) * zoom
        local glowR = 60 * zoom * t   -- 照亮半径随时间衰减
        local alpha = math.floor(90 * t)
        -- 外层暖光扩散
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, glowR)
        nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy, 4 * zoom, glowR,
            nvgRGBA(255, 200, 100, alpha), nvgRGBA(255, 150, 50, 0)))
        nvgFill(ctx)
        -- 内层高亮核心
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, 12 * zoom * t)
        local coreA = math.floor(140 * t)
        nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy, 2 * zoom, 12 * zoom * t,
            nvgRGBA(255, 255, 220, coreA), nvgRGBA(255, 220, 100, 0)))
        nvgFill(ctx)
    end
end

-- ============================================================================
-- 箱子（普通箱子使用精灵图，精英箱保留程序化绘制）
-- ============================================================================
local boxSpriteImg = nil            -- 普通箱子缓存句柄
local eliteBoxSpriteImg = nil       -- 精英箱子（关闭）缓存句柄
local eliteBoxOpenSpriteImg = nil   -- 精英箱子（打开）缓存句柄
local BOX_SPRITE_PATH = "image/普通箱子-0003.png"
local ELITE_BOX_SPRITE_PATH = "image/精英箱子-0002.png"
local ELITE_BOX_OPEN_SPRITE_PATH = "image/精英箱子开-0008.png"
-- 普通箱子精灵图布局：128×64，每帧 64×64，左=关闭，右=打开
-- 精英箱子：关闭/打开各一张单独图，宽度一致，打开态更高（盖子掀开）
local BOX_DRAW_W = 60  -- 普通箱子屏幕绘制宽
local BOX_DRAW_H = 42  -- 普通箱子屏幕绘制高
local ELITE_BOX_DRAW_W = 46       -- 精英箱子屏幕绘制宽
local ELITE_BOX_DRAW_H = 42      -- 精英箱子关闭态绘制高
local ELITE_BOX_OPEN_W = 52      -- 精英箱子打开态绘制宽
local ELITE_BOX_OPEN_H = 54      -- 精英箱子打开态绘制高（盖子掀开更高）

function M.DrawBoxes(ctx, camX, camY, visibleRooms)
    -- 懒加载精灵图
    if not boxSpriteImg then
        boxSpriteImg = nvgCreateImage(ctx, BOX_SPRITE_PATH, NVG_IMAGE_NEAREST)
        if not boxSpriteImg or boxSpriteImg <= 0 then boxSpriteImg = -1 end
    end
    if not eliteBoxSpriteImg then
        eliteBoxSpriteImg = nvgCreateImage(ctx, ELITE_BOX_SPRITE_PATH, NVG_IMAGE_NEAREST)
        if not eliteBoxSpriteImg or eliteBoxSpriteImg <= 0 then eliteBoxSpriteImg = -1 end
    end
    if not eliteBoxOpenSpriteImg then
        eliteBoxOpenSpriteImg = nvgCreateImage(ctx, ELITE_BOX_OPEN_SPRITE_PATH, NVG_IMAGE_NEAREST)
        if not eliteBoxOpenSpriteImg or eliteBoxOpenSpriteImg <= 0 then eliteBoxOpenSpriteImg = -1 end
    end

    for _, box in ipairs(World.boxes) do
        -- 视野过滤：不在可见"full"房间内的箱子不绘制
        if visibleRooms and not World.IsPositionVisible(box.x, box.y, visibleRooms) then
            goto continue_box
        end
        local sx = box.x - camX
        local sy = box.y - camY

        -- 箱子阴影（椭圆，根据开关状态适配）
        do
            local sw, sh, ofy
            if box.elite then
                sw = box.opened and 44 or 38
                sh = box.opened and 14 or 12
                ofy = box.opened and 18 or 14
            else
                sw = box.opened and 48 or 44
                sh = box.opened and 12 or 10
                ofy = box.opened and 14 or 12
            end
            nvgBeginPath(ctx)
            nvgEllipse(ctx, sx, sy + ofy, sw * 0.5, sh * 0.5)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 50))
            nvgFill(ctx)
        end

        if box.elite then
            -- 精英箱子：关闭/打开各一张图，打开态更大
            local img = box.opened and eliteBoxOpenSpriteImg or eliteBoxSpriteImg
            local drawW = box.opened and ELITE_BOX_OPEN_W or ELITE_BOX_DRAW_W
            local drawH = box.opened and ELITE_BOX_OPEN_H or ELITE_BOX_DRAW_H
            if img and img > 0 then
                local drawX = sx - drawW / 2
                local drawY = sy - drawH / 2
                local pat = nvgImagePattern(ctx, drawX, drawY, drawW, drawH, 0, img, 0.7)
                nvgBeginPath(ctx) nvgRect(ctx, drawX, drawY, drawW, drawH)
                nvgFillPaint(ctx, pat) nvgFill(ctx)
            else
                nvgBeginPath(ctx) nvgRect(ctx,sx-12,sy-10,24,20)
                nvgFillColor(ctx, nvgRGBA(50,50,60,220)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRect(ctx,sx-12,sy-10,24,20)
                nvgStrokeColor(ctx, nvgRGBA(255,200,30,220)) nvgStrokeWidth(ctx,2) nvgStroke(ctx)
            end
        else
            -- 普通箱子：精灵表（左=关闭，右=打开）
            local img = boxSpriteImg
            if img and img > 0 then
                local drawX = sx - BOX_DRAW_W / 2
                local drawY = sy - BOX_DRAW_H / 2
                local fullW = BOX_DRAW_W * 2
                local ox = box.opened and (drawX - BOX_DRAW_W) or drawX
                local pat = nvgImagePattern(ctx, ox, drawY, fullW, BOX_DRAW_H, 0, img, 0.7)
                nvgBeginPath(ctx) nvgRect(ctx, drawX, drawY, BOX_DRAW_W, BOX_DRAW_H)
                nvgFillPaint(ctx, pat) nvgFill(ctx)
            else
                nvgBeginPath(ctx) nvgRect(ctx,sx-12,sy-10,24,20)
                nvgFillColor(ctx, nvgRGBA(50,50,60,220)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRect(ctx,sx-12,sy-10,24,20)
                nvgStrokeColor(ctx, nvgRGBA(160,160,80,220)) nvgStrokeWidth(ctx,2) nvgStroke(ctx)
            end
        end
        ::continue_box::
    end
end

function M.DrawRoomObjects(ctx, camX, camY, player, visibleRooms)
    local rooms = World.GetRooms and World.GetRooms() or {}
    local prompt = World.GetRoomInteraction and World.GetRoomInteraction(player) or nil
    for _, room in ipairs(rooms) do
        -- 视野过滤：只显示可见"full"房间的对象
        if visibleRooms and visibleRooms[room] ~= "full" then
            goto continue_roomobj
        end
        if room.kind == "shrine" or room.kind == "event" or room.kind == "rest" or room.kind == "shop" or room.kind == "power" then
            local wx, wy = World.TileCenter(room.cx, room.cy)
            local sx = wx - camX
            local sy = wy - camY
            local used = room.used == true

            if room.kind == "event" then
                -- 事件房：交互点
                local etype = room.eventType or "altar"

                if etype == "terminal" then
                    -- 情报终端：精灵图 + 蓝光
                    if not M._terminalMachineImg then
                        M._terminalMachineImg = nvgCreateImage(ctx, "image/装饰/精灵-0012.png", 0)
                    end
                    local pulse = used and 0.15 or (0.6 + 0.4 * math.sin((World.time or 0) * 2.8 + room.cx))
                    -- 外层蓝色光晕
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, sx, sy - 6, 32)
                    local glowA = used and 8 or math.floor(28 * pulse)
                    nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy - 6, 5, 32,
                        nvgRGBA(80, 160, 255, glowA), nvgRGBA(40, 120, 255, 0)))
                    nvgFill(ctx)
                    -- 内层核心蓝光
                    if not used then
                        nvgBeginPath(ctx)
                        nvgCircle(ctx, sx, sy - 12, 14)
                        local innerA = math.floor(40 * pulse)
                        nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy - 12, 2, 14,
                            nvgRGBA(150, 220, 255, innerA), nvgRGBA(80, 160, 255, 0)))
                        nvgFill(ctx)
                    end
                    -- 终端精灵图（缩小80%）+ 底部阴影
                    if M._terminalMachineImg and M._terminalMachineImg ~= 0 then
                        local rawW, rawH = nvgImageSize(ctx, M._terminalMachineImg)
                        local imgW, imgH = rawW * 0.9, rawH * 0.9
                        -- 阴影（位于精灵底部）
                        nvgBeginPath(ctx)
                        nvgEllipse(ctx, sx, sy + imgH * 0.5 - 2, 15, 4)
                        nvgFillColor(ctx, nvgRGBA(0, 0, 0, used and 25 or 50))
                        nvgFill(ctx)
                        -- 精灵图
                        local alpha = used and 0.4 or (0.85 + 0.15 * pulse)
                        nvgBeginPath(ctx)
                        nvgRect(ctx, sx - imgW * 0.5, sy - imgH * 0.5, imgW, imgH)
                        local pat = nvgImagePattern(ctx, sx - imgW * 0.5, sy - imgH * 0.5,
                            imgW, imgH, 0, M._terminalMachineImg, alpha)
                        nvgFillPaint(ctx, pat)
                        nvgFill(ctx)
                    end
                else
                    -- 祭坛/诅咒事件：水晶球精灵图 + 紫色光晕
                    if not M._eventOrbImg then
                        M._eventOrbImg = nvgCreateImage(ctx, "image/装饰/精灵-0017.png", 0)
                    end
                    local pulse = used and 0.15 or (0.6 + 0.4 * math.sin((World.time or 0) * 2.6 + room.cx))
                    -- 外层紫色光晕
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, sx, sy - 6, 30)
                    local glowA = used and 8 or math.floor(26 * pulse)
                    nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy - 6, 5, 30,
                        nvgRGBA(180, 140, 255, glowA), nvgRGBA(140, 80, 220, 0)))
                    nvgFill(ctx)
                    -- 内层核心光
                    if not used then
                        nvgBeginPath(ctx)
                        nvgCircle(ctx, sx, sy - 10, 14)
                        local innerA = math.floor(40 * pulse)
                        nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy - 10, 2, 14,
                            nvgRGBA(200, 180, 255, innerA), nvgRGBA(160, 120, 240, 0)))
                        nvgFill(ctx)
                    end
                    -- 精灵图（缩小90%）+ 阴影
                    if M._eventOrbImg and M._eventOrbImg ~= 0 then
                        local rawW, rawH = nvgImageSize(ctx, M._eventOrbImg)
                        local imgW, imgH = rawW * 0.9, rawH * 0.9
                        -- 阴影
                        nvgBeginPath(ctx)
                        nvgEllipse(ctx, sx, sy + imgH * 0.5 - 2, 14, 4)
                        nvgFillColor(ctx, nvgRGBA(0, 0, 0, used and 25 or 50))
                        nvgFill(ctx)
                        -- 精灵
                        local alpha = used and 0.4 or (0.85 + 0.15 * pulse)
                        nvgBeginPath(ctx)
                        nvgRect(ctx, sx - imgW * 0.5, sy - imgH * 0.5, imgW, imgH)
                        local pat = nvgImagePattern(ctx, sx - imgW * 0.5, sy - imgH * 0.5,
                            imgW, imgH, 0, M._eventOrbImg, alpha)
                        nvgFillPaint(ctx, pat)
                        nvgFill(ctx)
                    end
                end

                -- NPC 站在交互点左侧（纯装饰，不可交互）
                local npcOffX = -50
                local nsx = sx + npcOffX

                -- 根据事件类型选择 NPC 精灵
                local npcImg, npcFrameCount, npcCols, npcFrameSize, npcSheetW, npcSheetH
                if etype == "terminal" then
                    -- 情报终端：鸟形 NPC (512×256, 4×2, 7帧有效, 128px/帧)
                    if not M._terminalNpcImg then
                        M._terminalNpcImg = nvgCreateImage(ctx, "image/npc/rika_ebb87120.png", 0)
                    end
                    npcImg = M._terminalNpcImg
                    npcFrameCount = 7
                    npcCols = 4
                    npcFrameSize = 128
                    npcSheetW = 512
                    npcSheetH = 256
                elseif etype == "altar" then
                    -- 祭坛：蘑菇 NPC (512×384, 4×3, 9帧有效, 128px/帧)
                    if not M._altarNpcImg then
                        M._altarNpcImg = nvgCreateImage(ctx, "image/npc/rika_3626ad62.png", 0)
                    end
                    npcImg = M._altarNpcImg
                    npcFrameCount = 9
                    npcCols = 4
                    npcFrameSize = 128
                    npcSheetW = 512
                    npcSheetH = 384
                else
                    -- 诅咒：幽灵 NPC (1024×768, 4×3, 12帧, 256px/帧)
                    if not M._eventNpcImg then
                        M._eventNpcImg = nvgCreateImage(ctx, "image/npc/rika_018cab6b.png", 0)
                    end
                    npcImg = M._eventNpcImg
                    npcFrameCount = 12
                    npcCols = 4
                    npcFrameSize = 256
                    npcSheetW = 1024
                    npcSheetH = 768
                end

                -- 每个房间独立动画状态（用 room 存储）
                room._npcAnimTimer = (room._npcAnimTimer or 0) + M.dt * 10.5
                if room._npcAnimTimer >= 1.0 then
                    room._npcAnimTimer = room._npcAnimTimer - 1.0
                    room._npcFrame = ((room._npcFrame or 0) + 1) % npcFrameCount
                end
                local frame = room._npcFrame or 0

                local NPC_DRAW = 88
                local npcScale = NPC_DRAW / npcFrameSize
                local npcTotalW = npcSheetW * npcScale
                local npcTotalH = npcSheetH * npcScale
                local npcCol = frame % npcCols
                local npcRow = math.floor(frame / npcCols)

                -- NPC 脚下阴影
                nvgBeginPath(ctx)
                nvgEllipse(ctx, nsx, sy + 20, 15, 5)
                nvgFillColor(ctx, nvgRGBA(0, 0, 0, 45))
                nvgFill(ctx)

                local floatY = (etype == "curse") and math.sin((World.time or 0) * 2.0 + room.cx) * 3 or 0
                -- 根据玩家位置决定是否镜像翻转（面朝主角）
                local playerSx = player.x - camX
                local faceLeft = playerSx < nsx

                nvgSave(ctx)
                if faceLeft then
                    -- 镜像：以 NPC 中心为轴翻转
                    nvgTranslate(ctx, nsx, 0)
                    nvgScale(ctx, -1, 1)
                    nvgTranslate(ctx, -nsx, 0)
                end
                nvgBeginPath(ctx)
                local patX = nsx - NPC_DRAW * 0.5 - npcCol * NPC_DRAW
                local patY = sy - NPC_DRAW * 0.5 - npcRow * NPC_DRAW + floatY
                local pat = nvgImagePattern(ctx, patX, patY, npcTotalW, npcTotalH, 0, npcImg, 1.0)
                nvgRect(ctx, nsx - NPC_DRAW * 0.5, sy - NPC_DRAW * 0.5 + floatY, NPC_DRAW, NPC_DRAW)
                nvgFillPaint(ctx, pat)
                nvgFill(ctx)
                nvgRestore(ctx)
            elseif room.kind == "shrine" then
                -- 献祭屋：祭坛精灵图 + 灯光 + NPC
                if not M._shrineAltarImg then
                    M._shrineAltarImg = nvgCreateImage(ctx, "image/装饰/精灵-0008.png", 0)
                end
                local rr, gg, bb = 255, 200, 80
                local pulse = used and 0.15 or (0.6 + 0.4 * math.sin((World.time or 0) * 2.5 + room.cx))

                -- 外层大光晕（暖黄色柔光）
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, sy - 4, 38)
                local glowA = used and 10 or math.floor(30 * pulse)
                nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy - 4, 6, 38,
                    nvgRGBA(rr, gg, bb, glowA), nvgRGBA(rr, gg, bb, 0)))
                nvgFill(ctx)

                -- 内层强光（模拟烛光点光源）
                if not used then
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, sx, sy - 12, 18)
                    local innerA = math.floor(45 * pulse)
                    nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy - 12, 2, 18,
                        nvgRGBA(255, 240, 180, innerA), nvgRGBA(rr, gg, bb, 0)))
                    nvgFill(ctx)
                end

                -- 祭坛阴影
                nvgBeginPath(ctx)
                nvgEllipse(ctx, sx, sy + 16, 15, 4)
                nvgFillColor(ctx, nvgRGBA(0, 0, 0, used and 25 or 50))
                nvgFill(ctx)

                -- 祭坛精灵图
                local altarSize = 43
                local altarAlpha = used and 0.4 or (0.85 + 0.15 * pulse)
                nvgSave(ctx)
                nvgBeginPath(ctx)
                nvgRect(ctx, sx - altarSize * 0.5, sy - altarSize * 0.5, altarSize, altarSize)
                local altarPat = nvgImagePattern(ctx, sx - altarSize * 0.5, sy - altarSize * 0.5,
                    altarSize, altarSize, 0, M._shrineAltarImg, altarAlpha)
                nvgFillPaint(ctx, altarPat)
                nvgFill(ctx)
                nvgRestore(ctx)

                -- 献祭 NPC 站在左侧（512×256, 4×2, 8帧, 128px/帧）
                local nsx = sx - 50
                if not M._shrineNpcImg then
                    M._shrineNpcImg = nvgCreateImage(ctx, "image/npc/rika_b960a5ff (1).png", 0)
                end
                room._shrineAnimTimer = (room._shrineAnimTimer or 0) + M.dt * 10.5
                if room._shrineAnimTimer >= 1.0 then
                    room._shrineAnimTimer = room._shrineAnimTimer - 1.0
                    room._shrineFrame = ((room._shrineFrame or 0) + 1) % 8
                end
                local frame = room._shrineFrame or 0
                local NPC_DRAW = 88
                local npcScale = NPC_DRAW / 128
                local npcTotalW = 512 * npcScale
                local npcTotalH = 256 * npcScale
                local npcCol = frame % 4
                local npcRow = math.floor(frame / 4)

                -- 阴影
                nvgBeginPath(ctx)
                nvgEllipse(ctx, nsx, sy + 20, 15, 5)
                nvgFillColor(ctx, nvgRGBA(0, 0, 0, 45))
                nvgFill(ctx)

                -- 面朝主角
                local playerSx = player.x - camX
                local faceLeft = playerSx < nsx
                nvgSave(ctx)
                if faceLeft then
                    nvgTranslate(ctx, nsx, 0)
                    nvgScale(ctx, -1, 1)
                    nvgTranslate(ctx, -nsx, 0)
                end
                nvgBeginPath(ctx)
                local patX = nsx - NPC_DRAW * 0.5 - npcCol * NPC_DRAW
                local patY = sy - NPC_DRAW * 0.5 - npcRow * NPC_DRAW
                local pat = nvgImagePattern(ctx, patX, patY, npcTotalW, npcTotalH, 0, M._shrineNpcImg, 1.0)
                nvgRect(ctx, nsx - NPC_DRAW * 0.5, sy - NPC_DRAW * 0.5, NPC_DRAW, NPC_DRAW)
                nvgFillPaint(ctx, pat)
                nvgFill(ctx)
                nvgRestore(ctx)
            elseif room.kind == "shop" then
                -- 商店：精灵图 + 微绿光 + 自动售货机 NPC
                if not M._shopMachineImg then
                    M._shopMachineImg = nvgCreateImage(ctx, "image/装饰/精灵-0013.png", 0)
                end
                local pulse = used and 0.15 or (0.6 + 0.4 * math.sin((World.time or 0) * 2.5 + room.cx))
                -- 微绿光晕
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, sy - 4, 28)
                local glowA = used and 8 or math.floor(22 * pulse)
                nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy - 4, 4, 28,
                    nvgRGBA(100, 220, 180, glowA), nvgRGBA(60, 200, 150, 0)))
                nvgFill(ctx)
                -- 精灵图（缩小80%）+ 阴影
                if M._shopMachineImg and M._shopMachineImg ~= 0 then
                    local rawW, rawH = nvgImageSize(ctx, M._shopMachineImg)
                    local imgW, imgH = rawW * 0.9, rawH * 0.9
                    -- 阴影
                    nvgBeginPath(ctx)
                    nvgEllipse(ctx, sx, sy + imgH * 0.5 - 2, 17, 4)
                    nvgFillColor(ctx, nvgRGBA(0, 0, 0, used and 25 or 50))
                    nvgFill(ctx)
                    -- 精灵
                    local alpha = used and 0.45 or (0.85 + 0.15 * pulse)
                    nvgBeginPath(ctx)
                    nvgRect(ctx, sx - imgW * 0.5, sy - imgH * 0.5, imgW, imgH)
                    local pat = nvgImagePattern(ctx, sx - imgW * 0.5, sy - imgH * 0.5,
                        imgW, imgH, 0, M._shopMachineImg, alpha)
                    nvgFillPaint(ctx, pat)
                    nvgFill(ctx)
                end

                -- 商店 NPC 站在左侧（512×384, 4×3, 11帧有效, 128px/帧）
                local nsx = sx - 50
                if not M._shopNpcImg then
                    M._shopNpcImg = nvgCreateImage(ctx, "image/npc/rika_77430c21 (1).png", 0)
                end
                room._shopAnimTimer = (room._shopAnimTimer or 0) + M.dt * 10.5
                if room._shopAnimTimer >= 1.0 then
                    room._shopAnimTimer = room._shopAnimTimer - 1.0
                    room._shopFrame = ((room._shopFrame or 0) + 1) % 11
                end
                local frame = room._shopFrame or 0
                local NPC_DRAW = 88
                local npcScale = NPC_DRAW / 128
                local npcTotalW = 512 * npcScale
                local npcTotalH = 384 * npcScale
                local npcCol = frame % 4
                local npcRow = math.floor(frame / 4)

                -- 阴影
                nvgBeginPath(ctx)
                nvgEllipse(ctx, nsx, sy + 20, 15, 5)
                nvgFillColor(ctx, nvgRGBA(0, 0, 0, 45))
                nvgFill(ctx)

                -- 面朝主角
                local playerSx = player.x - camX
                local faceLeft = playerSx < nsx
                nvgSave(ctx)
                if faceLeft then
                    nvgTranslate(ctx, nsx, 0)
                    nvgScale(ctx, -1, 1)
                    nvgTranslate(ctx, -nsx, 0)
                end
                nvgBeginPath(ctx)
                local patX = nsx - NPC_DRAW * 0.5 - npcCol * NPC_DRAW
                local patY = sy - NPC_DRAW * 0.5 - npcRow * NPC_DRAW
                local pat = nvgImagePattern(ctx, patX, patY, npcTotalW, npcTotalH, 0, M._shopNpcImg, 1.0)
                nvgRect(ctx, nsx - NPC_DRAW * 0.5, sy - NPC_DRAW * 0.5, NPC_DRAW, NPC_DRAW)
                nvgFillPaint(ctx, pat)
                nvgFill(ctx)
                nvgRestore(ctx)
            elseif room.kind == "power" then
                -- 供电房：未交互时虚影态，交互后实体+发光
                if not M._powerMachineImg then
                    M._powerMachineImg = nvgCreateImage(ctx, "image/装饰/精灵-0016.png", 0)
                end
                local pulse = 0.5 + 0.5 * math.sin((World.time or 0) * 3.5 + room.cx * 1.7)
                if used then
                    -- 已激活：强烈稳定黄色发光
                    -- 外层扩散光晕
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, sx, sy - 4, 40)
                    nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy - 4, 6, 40,
                        nvgRGBA(255, 220, 50, 55), nvgRGBA(255, 180, 0, 0)))
                    nvgFill(ctx)
                    -- 内层核心亮光
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, sx, sy - 10, 20)
                    nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy - 10, 3, 20,
                        nvgRGBA(255, 255, 200, 80), nvgRGBA(255, 230, 80, 0)))
                    nvgFill(ctx)
                else
                    -- 未激活：微弱闪烁虚光（幽灵态提示）
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, sx, sy - 4, 26)
                    local glowA = math.floor(14 * pulse)
                    nvgFillPaint(ctx, nvgRadialGradient(ctx, sx, sy - 4, 3, 26,
                        nvgRGBA(200, 200, 255, glowA), nvgRGBA(150, 150, 220, 0)))
                    nvgFill(ctx)
                end
                -- 精灵图（缩小90%）+ 阴影
                if M._powerMachineImg and M._powerMachineImg ~= 0 then
                    local rawW, rawH = nvgImageSize(ctx, M._powerMachineImg)
                    local imgW, imgH = rawW * 0.9, rawH * 0.9
                    -- 阴影
                    nvgBeginPath(ctx)
                    nvgEllipse(ctx, sx, sy + imgH * 0.5 - 2, 16, 4)
                    nvgFillColor(ctx, nvgRGBA(0, 0, 0, used and 50 or 20))
                    nvgFill(ctx)
                    -- 精灵：未激活半透明虚影，激活后完全实体
                    local alpha
                    if used then
                        alpha = 1.0
                    else
                        alpha = 0.3 + 0.1 * pulse  -- 虚影闪烁 0.3~0.4
                    end
                    nvgBeginPath(ctx)
                    nvgRect(ctx, sx - imgW * 0.5, sy - imgH * 0.5, imgW, imgH)
                    local pat = nvgImagePattern(ctx, sx - imgW * 0.5, sy - imgH * 0.5,
                        imgW, imgH, 0, M._powerMachineImg, alpha)
                    nvgFillPaint(ctx, pat)
                    nvgFill(ctx)
                end
            else
                -- 休息：原有符号渲染
                local rr, gg, bb = 120, 240, 180
                local pulse = used and 0.2 or (0.65 + 0.35 * math.sin((World.time or 0) * 3.0 + room.cx))
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, sy, 18)
                nvgFillColor(ctx, nvgRGBA(rr, gg, bb, used and 16 or math.floor(34 + 28 * pulse)))
                nvgFill(ctx)
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, sy, 14)
                nvgStrokeColor(ctx, nvgRGBA(rr, gg, bb, used and 55 or 190))
                nvgStrokeWidth(ctx, 1.5)
                nvgStroke(ctx)
                nvgFontFace(ctx, "bold")
                nvgFontSize(ctx, 18)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(rr, gg, bb, used and 80 or 235))
                nvgText(ctx, sx, sy + 1, "+", nil)
            end
        end
        ::continue_roomobj::
    end

    -- 房间油灯装饰（地图生成时已预分配 room.lamp）
    if not M._lampImg then
        M._lampImg = nvgCreateImage(ctx, "image/装饰/精灵-0009.png", 0)
    end
    if not M._lampImg2 then
        M._lampImg2 = nvgCreateImage(ctx, "image/装饰/精灵-0010.png", 0)
    end
    for _, room in ipairs(rooms) do
        if not room.lamp then goto continue_lamp end
        local lamp = room.lamp
        -- 转换为世界像素坐标
        local lwx, lwy = World.TileCenter(lamp.col, lamp.row)
        -- 视野过滤：与箱子一致，按像素位置判断
        if visibleRooms and not World.IsPositionVisible(lwx, lwy, visibleRooms) then
            goto continue_lamp
        end
        local lsx = lwx - camX
        local lsy = lwy - camY
        -- 灯光脉动
        local lampSeed = lamp.col * 131 + lamp.row * 97
        local lampPulse = 0.7 + 0.3 * math.sin((World.time or 0) * 2.2 + lampSeed * 0.03)
        -- 外层大光晕（暖橙色扩散光）
        nvgBeginPath(ctx)
        nvgCircle(ctx, lsx, lsy - 6, 36)
        local outerA = math.floor(35 * lampPulse)
        nvgFillPaint(ctx, nvgRadialGradient(ctx, lsx, lsy - 6, 4, 36,
            nvgRGBA(255, 170, 50, outerA), nvgRGBA(255, 120, 20, 0)))
        nvgFill(ctx)
        -- 内层强光（烛火核心）
        nvgBeginPath(ctx)
        nvgCircle(ctx, lsx, lsy - 10, 14)
        local innerA = math.floor(55 * lampPulse)
        nvgFillPaint(ctx, nvgRadialGradient(ctx, lsx, lsy - 10, 2, 14,
            nvgRGBA(255, 230, 150, innerA), nvgRGBA(255, 180, 60, 0)))
        nvgFill(ctx)
        -- 阴影
        nvgBeginPath(ctx)
        nvgEllipse(ctx, lsx, lsy + 12, 10, 3)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 40))
        nvgFill(ctx)
        -- 灯精灵（保持原图大小32x32）— 样式已预分配
        local chosenLamp
        if lamp.style == 0 and M._lampImg and M._lampImg ~= 0 then
            chosenLamp = M._lampImg
        elseif M._lampImg2 and M._lampImg2 ~= 0 then
            chosenLamp = M._lampImg2
        else
            chosenLamp = M._lampImg
        end
        if chosenLamp and chosenLamp ~= 0 then
            local lampSize = 32
            nvgBeginPath(ctx)
            nvgRect(ctx, lsx - lampSize * 0.5, lsy - lampSize * 0.5, lampSize, lampSize)
            local lampPat = nvgImagePattern(ctx, lsx - lampSize * 0.5, lsy - lampSize * 0.5,
                lampSize, lampSize, 0, chosenLamp, 0.92)
            nvgFillPaint(ctx, lampPat)
            nvgFill(ctx)
        end
        ::continue_lamp::
    end

    -- 初始房间指示牌装饰（地图生成时已预分配 room.signpost）
    if not M._signpostImg1 then
        M._signpostImg1 = nvgCreateImage(ctx, "image/装饰/精灵-0005.png", 0)
    end
    if not M._signpostImg2 then
        M._signpostImg2 = nvgCreateImage(ctx, "image/装饰/精灵-0006.png", 0)
    end
    for _, room in ipairs(rooms) do
        if not room.signpost then goto continue_signpost end
        local sp = room.signpost
        local swx, swy = World.TileCenter(sp.col, sp.row)
        if visibleRooms and not World.IsPositionVisible(swx, swy, visibleRooms) then
            goto continue_signpost
        end
        local ssx = swx - camX
        local ssy = swy - camY
        -- 选择样式
        local chosenImg = (sp.style == 0) and M._signpostImg1 or M._signpostImg2
        if chosenImg and chosenImg ~= 0 then
            local signSize = 32
            -- 阴影
            nvgBeginPath(ctx)
            nvgEllipse(ctx, ssx, ssy + 12, 9, 3)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 35))
            nvgFill(ctx)
            -- 精灵
            nvgBeginPath(ctx)
            nvgRect(ctx, ssx - signSize * 0.5, ssy - signSize * 0.5, signSize, signSize)
            local pat = nvgImagePattern(ctx, ssx - signSize * 0.5, ssy - signSize * 0.5,
                signSize, signSize, 0, chosenImg, 0.9)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)
        end
        ::continue_signpost::
    end

    if prompt then
        local sx = prompt.x - camX
        local sy = prompt.y - camY
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 220))
        nvgText(ctx, sx, sy - 30, "[E] " .. prompt.label, nil)
    end


end

-- ============================================================================
-- 地面掉落物
-- ============================================================================
function M.DrawDrops(ctx, camX, camY, player, visibleRooms)
    local hasNearby = false
    local nearX, nearY = 0, 0
    local nearCount = 0
    for _, drop in ipairs(World.drops) do
        if not drop.picked then
            -- 视野过滤
            if visibleRooms and not World.IsPositionVisible(drop.x, drop.y, visibleRooms) then
                goto continue_drop
            end
            local sx = drop.x - camX
            local sy = drop.y - camY
            local item = drop.item
            local r,g,b = RC(item.rarity or 1)
            -- 浮动动画
            local bob = math.sin((World.time or 0) * 3 + drop.x * 0.1) * 2
            local drawY = sy + bob
            -- 发光底圆
            nvgBeginPath(ctx) nvgCircle(ctx,sx,drawY,12)
            nvgFillColor(ctx,nvgRGBA(r,g,b,40)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgCircle(ctx,sx,drawY,12)
            nvgStrokeColor(ctx,nvgRGBA(r,g,b,200)) nvgStrokeWidth(ctx,1.5) nvgStroke(ctx)
            -- 图标
            nvgFontFace(ctx,"sans") nvgFontSize(ctx,11)
            nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(r,g,b,255))
            DrawItemIcon(ctx, item, sx, drawY, 22)
            -- 检查是否在玩家拾取范围内
            if player and not drop.nopickTimer then
                local ddSq = (player.x - drop.x)^2 + (player.y - drop.y)^2
                if ddSq < 1296 then -- 36^2
                    hasNearby = true
                    nearX = nearX + sx
                    nearY = nearY + drawY
                    nearCount = nearCount + 1
                end
            end
            ::continue_drop::
        end
    end
    -- 在附近掉落物上方显示 E 键提示
    if hasNearby and nearCount > 0 then
        local cx = nearX / nearCount
        local cy = nearY / nearCount - 18
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 200))
        nvgText(ctx, cx, cy, "[E] 拾取", nil)
    end
end

-- ============================================================================
-- 粒子
-- ============================================================================
function M.DrawParticles(ctx, camX, camY)
    for _, p in ipairs(World.particles) do
        local t = p.life / p.maxLife
        local alpha = math.floor(t * 220)
        local sx = p.x - camX
        local sy = p.y - camY
        local sz = p.size * t
        local r = math.max(0.5, sz)
        -- 外层光晕（半透明扩散）
        if sz > 1.5 then
            nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, r * 2.2)
            nvgFillColor(ctx, nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 0.2)))
            nvgFill(ctx)
        end
        -- 核心粒子
        nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, r)
        nvgFillColor(ctx, nvgRGBA(p.r, p.g, p.b, alpha)) nvgFill(ctx)
    end
end

-- ============================================================================
-- 浮动伤害数字
-- ============================================================================
function M.DrawDmgPopups(ctx, camX, camY, dt)
    local popups = World.dmgPopups
    local n = #popups
    local i = 1
    while i <= n do
        local p = popups[i]
        p.life = p.life - dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy * 0.92  -- 减速上升
        if p.life <= 0 then
            popups[i] = popups[n]
            popups[n] = nil
            n = n - 1
        else
            local sx = p.x - camX
            local sy = p.y - camY
            local t = p.life / p.maxLife
            local alpha = math.floor(t * 255)
            local scale = 1.0 + (1.0 - t) * 0.3  -- 刚出现时稍大
            local txt = tostring(p.dmg)
            local sz, r, g, b2
            if p.isCrit then
                sz = 16 * scale
                r, g, b2 = 255, 50, 50
            else
                sz = 8 * scale
                r, g, b2 = 255, 255, 255
            end
            nvgFontFace(ctx, "pixel")
            nvgFontSize(ctx, sz)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            -- 4方向黑色描边
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, alpha))
            nvgText(ctx, sx - 1, sy, txt, nil)
            nvgText(ctx, sx + 1, sy, txt, nil)
            nvgText(ctx, sx, sy - 1, txt, nil)
            nvgText(ctx, sx, sy + 1, txt, nil)
            -- 主体颜色
            nvgFillColor(ctx, nvgRGBA(r, g, b2, alpha))
            nvgText(ctx, sx, sy, txt, nil)
            i = i + 1
        end
    end
end

-- ============================================================================
-- 枪口闪光
-- ============================================================================
function M.DrawMuzzleFlashes(ctx, camX, camY)
    for _, f in ipairs(World.muzzleFlashes) do
        local t = f.life / f.maxLife  -- 1→0 衰减
        local sx = f.x - camX
        local sy = f.y - camY
        local radius = f.radius * (1 + (1 - t) * 0.4)  -- 衰减时略扩
        local alpha = math.floor(t * 255)

        -- 第一层：外层橙色光晕（大范围）
        nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, radius * 2.0)
        nvgFillColor(ctx, nvgRGBA(255, 120, 20, math.floor(alpha * 0.15)))
        nvgFill(ctx)

        -- 第二层：中层暖黄（径向渐变模拟）
        nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, radius * 1.2)
        nvgFillColor(ctx, nvgRGBA(255, 200, 50, math.floor(alpha * 0.45)))
        nvgFill(ctx)

        -- 第三层：白色高亮核心
        nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, radius * 0.5)
        nvgFillColor(ctx, nvgRGBA(255, 255, 240, alpha))
        nvgFill(ctx)

        -- 方向性光条（沿射击方向的拉伸光）
        local cosA = math.cos(f.angle)
        local sinA = math.sin(f.angle)
        local len = radius * 1.8 * t
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, sx - cosA * 2, sy - sinA * 2)
        nvgLineTo(ctx, sx + cosA * len, sy + sinA * len)
        nvgStrokeColor(ctx, nvgRGBA(255, 240, 180, math.floor(alpha * 0.7)))
        nvgStrokeWidth(ctx, 3 * t)
        nvgStroke(ctx)
    end
end

-- ============================================================================
-- 雷电击中闪光特效（序列帧）
-- ============================================================================
local lightningFxImg = nil
function M.DrawLightningFx(ctx, camX, camY, dt)
    if not lightningFxImg then
        lightningFxImg = nvgCreateImage(ctx, "image/8786bcf17bd7bcd4de688b1a70a7f5fc.png", 0)
    end
    if not lightningFxImg or lightningFxImg <= 0 then return end

    local fxList = World.lightningFx
    local n = #fxList
    local i = 1
    while i <= n do
        local fx = fxList[i]
        fx.life = fx.life - dt
        if fx.life <= 0 then
            fxList[i] = fxList[n]
            fxList[n] = nil
            n = n - 1
        else
            local sx = fx.x - camX
            local sy = fx.y - camY
            local t = fx.life / fx.maxLife  -- 1→0
            local alpha = math.floor(t * 255)

            -- 4x4 网格序列帧，快速播放
            local SHEET_COLS = 4
            local TOTAL_FRAMES = 16
            local fps = 30  -- 快速闪烁
            local elapsed = fx.maxLife - fx.life
            local frame = (fx.frame0 + math.floor(elapsed * fps)) % TOTAL_FRAMES
            local col = frame % SHEET_COLS
            local row = math.floor(frame / SHEET_COLS)

            local sz = fx.size * (0.8 + t * 0.4)  -- 从大到小衰减
            local patX = sx - sz * 0.5 - col * sz
            local patY = sy - sz * 0.5 - row * sz
            local patW = sz * SHEET_COLS
            local patH = sz * SHEET_COLS
            local pat = nvgImagePattern(ctx, patX, patY, patW, patH, 0, lightningFxImg, alpha / 255.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, sx - sz * 0.5, sy - sz * 0.5, sz, sz)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)

            i = i + 1
        end
    end
end

-- ============================================================================
-- 子弹
-- ============================================================================
function M.DrawBullets(ctx, camX, camY, bullets)
    for _, b in ipairs(bullets) do
        local sx = b.x - camX
        local sy = b.y - camY

        -- ---- 剑气波：三层刀光弧形 ----
        if b.isSlashWave then
            local ang   = b.angle or math.atan(b.vy, b.vx)
            local t     = math.max(0, math.min(1, b.life / (b.maxLife or 0.9)))
            local alpha = math.floor(t * 235)
            local fx    = math.cos(ang)
            local fy    = math.sin(ang)
            local rx    = -fy        -- 法线方向
            local ry    =  fx
            local len   = 20 + t * 10   -- 前端长度随生命衰减
            local wOuter = 8 * t         -- 外层宽度
            local wMid   = 4.5 * t
            local wInner = 2 * t

            -- 外层：大面积青蓝光晕（宽扇形）
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx - fx*3,           sy - fy*3)
            nvgLineTo(ctx, sx + fx*len + rx*wOuter, sy + fy*len + ry*wOuter)
            nvgLineTo(ctx, sx + fx*(len+4),     sy + fy*(len+4))
            nvgLineTo(ctx, sx + fx*len - rx*wOuter, sy + fy*len - ry*wOuter)
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(80, 200, 255, math.floor(alpha * 0.35)))
            nvgFill(ctx)

            -- 中层：青白渐变主体
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx - fx*2,           sy - fy*2)
            nvgLineTo(ctx, sx + fx*len + rx*wMid, sy + fy*len + ry*wMid)
            nvgLineTo(ctx, sx + fx*(len+3),     sy + fy*(len+3))
            nvgLineTo(ctx, sx + fx*len - rx*wMid, sy + fy*len - ry*wMid)
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(180, 235, 255, math.floor(alpha * 0.65)))
            nvgFill(ctx)

            -- 内核：纯白锐利中线（高亮刀刃）
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx,               sy)
            nvgLineTo(ctx, sx + fx*(len+5),  sy + fy*(len+5))
            nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, alpha))
            nvgStrokeWidth(ctx, 1.8) nvgStroke(ctx)

            -- 前端刀尖高亮点
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx + fx*(len+5), sy + fy*(len+5), 2.5 * t)
            nvgFillColor(ctx, nvgRGBA(220, 248, 255, alpha))
            nvgFill(ctx)

            goto continue_draw_bullet
        end

        -- ---- 骷髅射手箭矢 ----
        if b.enemyType == "patrol" then
            LoadArrowBulletImg(ctx)
            if arrowBulletImg and arrowBulletImg ~= 0 then
                local ang = math.atan(b.vy, b.vx)
                local bW, bH = 24, 12
                nvgSave(ctx)
                nvgTranslate(ctx, sx, sy)
                nvgRotate(ctx, ang)
                nvgBeginPath(ctx)
                local pat = nvgImagePattern(ctx, -bW/2, -bH/2, bW, bH, 0, arrowBulletImg, 1.0)
                nvgFillPaint(ctx, pat)
                nvgRect(ctx, -bW/2, -bH/2, bW, bH)
                nvgFill(ctx)
                nvgRestore(ctx)
            end
            goto continue_draw_bullet
        end

        -- ---- 普通子弹（按武器类型区分形状） ----
        do
            local ang = math.atan(b.vy, b.vx)
            local cosA = math.cos(ang)
            local sinA = math.sin(ang)

            local isPlayer = (b.owner == "player")
            local wt = b.wtype  -- 武器类型标识

            -- 颜色方案
            local cr, cg, cb = 255, 230, 80
            if not isPlayer then
                cr, cg, cb = 255, 80, 60
            elseif wt == "sniper" then
                cr, cg, cb = 255, 180, 50  -- 狙击：橙色调
            end

            -- 手枪/霰弹枪：使用子弹贴图（additive 混合）
            if wt == "pistol" or wt == "shotgun" then
                LoadBulletImg(ctx)
                if bulletImg and bulletImg ~= 0 then
                    local bSize = (wt == "pistol") and 11 or 8  -- 手枪大、霰弹小
                    nvgSave(ctx)
                    nvgTranslate(ctx, sx, sy)
                    nvgRotate(ctx, ang)
                    nvgGlobalCompositeBlendFunc(ctx, NVG_ONE, NVG_ONE)
                    nvgBeginPath(ctx)
                    local pat = nvgImagePattern(ctx, -bSize/2, -bSize/2, bSize, bSize, 0, bulletImg, 1.0)
                    nvgFillPaint(ctx, pat)
                    nvgRect(ctx, -bSize/2, -bSize/2, bSize, bSize)
                    nvgFill(ctx)
                    nvgGlobalCompositeBlendFunc(ctx, NVG_ONE, NVG_ONE_MINUS_SRC_ALPHA)
                    nvgRestore(ctx)
                end
                goto continue_draw_bullet
            end

            -- 冲锋枪：使用橙色椭圆子弹贴图（additive 混合）
            if wt == "smg" then
                LoadSmgBulletImg(ctx)
                if smgBulletImg and smgBulletImg ~= 0 then
                    local bW, bH = 9, 8
                    nvgSave(ctx)
                    nvgTranslate(ctx, sx, sy)
                    nvgRotate(ctx, ang)
                    nvgGlobalCompositeBlendFunc(ctx, NVG_ONE, NVG_ONE)
                    nvgBeginPath(ctx)
                    local pat = nvgImagePattern(ctx, -bW/2, -bH/2, bW, bH, 0, smgBulletImg, 1.0)
                    nvgFillPaint(ctx, pat)
                    nvgRect(ctx, -bW/2, -bH/2, bW, bH)
                    nvgFill(ctx)
                    nvgGlobalCompositeBlendFunc(ctx, NVG_ONE, NVG_ONE_MINUS_SRC_ALPHA)
                    nvgRestore(ctx)
                end
                goto continue_draw_bullet
            end

            -- 重机枪：使用红橙色椭圆子弹贴图（additive 混合）
            if wt == "hmg" then
                LoadHmgBulletImg(ctx)
                if hmgBulletImg and hmgBulletImg ~= 0 then
                    local bW, bH = 11, 8
                    nvgSave(ctx)
                    nvgTranslate(ctx, sx, sy)
                    nvgRotate(ctx, ang)
                    nvgGlobalCompositeBlendFunc(ctx, NVG_ONE, NVG_ONE)
                    nvgBeginPath(ctx)
                    local pat = nvgImagePattern(ctx, -bW/2, -bH/2, bW, bH, 0, hmgBulletImg, 1.0)
                    nvgFillPaint(ctx, pat)
                    nvgRect(ctx, -bW/2, -bH/2, bW, bH)
                    nvgFill(ctx)
                    nvgGlobalCompositeBlendFunc(ctx, NVG_ONE, NVG_ONE_MINUS_SRC_ALPHA)
                    nvgRestore(ctx)
                end
                goto continue_draw_bullet
            end

            -- 狙击枪：使用金黄色长条弹丸贴图（additive 混合）
            if wt == "sniper" then
                LoadSniperBulletImg(ctx)
                if sniperBulletImg and sniperBulletImg ~= 0 then
                    local bW, bH = 15, 8
                    nvgSave(ctx)
                    nvgTranslate(ctx, sx, sy)
                    nvgRotate(ctx, ang)
                    nvgGlobalCompositeBlendFunc(ctx, NVG_ONE, NVG_ONE)
                    nvgBeginPath(ctx)
                    local pat = nvgImagePattern(ctx, -bW/2, -bH/2, bW, bH, 0, sniperBulletImg, 1.0)
                    nvgFillPaint(ctx, pat)
                    nvgRect(ctx, -bW/2, -bH/2, bW, bH)
                    nvgFill(ctx)
                    nvgGlobalCompositeBlendFunc(ctx, NVG_ONE, NVG_ONE_MINUS_SRC_ALPHA)
                    nvgRestore(ctx)
                end
                goto continue_draw_bullet
            end

            -- 按武器类型调整子弹参数
            -- tailLen=拖尾长度, tailW=拖尾宽度, headR=弹头半径, glowR=光晕半径, rounded=圆弧长条
            local tailLen, tailW, headR, glowR, rounded = 14, 2.5, 2.8, 5.5, false
            if wt == "rifle" then
                -- 步枪：圆弧长条
                tailLen, tailW, headR, glowR, rounded = 16, 2.8, 2.2, 4.5, true
            end

            if rounded then
                -- 圆弧长条弹型（步枪/狙击）：圆角矩形风格
                local halfW = tailW * 0.5
                nvgSave(ctx)
                nvgTranslate(ctx, sx, sy)
                nvgRotate(ctx, ang)

                -- 外层光晕
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, -tailLen * 0.3, -halfW - 2, tailLen * 1.3, (halfW + 2) * 2, halfW + 2)
                nvgFillColor(ctx, nvgRGBA(cr, cg, cb, 45))
                nvgFill(ctx)

                -- 主体圆角矩形
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, -tailLen * 0.25, -halfW, tailLen * 1.1, halfW * 2, halfW)
                nvgFillColor(ctx, nvgRGBA(cr, cg, cb, 200))
                nvgFill(ctx)

                -- 内核高亮
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, -tailLen * 0.1, -halfW * 0.5, tailLen * 0.8, halfW, halfW * 0.5)
                nvgFillColor(ctx, nvgRGBA(255, 255, 240, 230))
                nvgFill(ctx)

                nvgRestore(ctx)
            else
                -- 原始尖头拖尾弹型（冲锋枪/重机枪/霰弹枪）
                local halfTW = tailW * 0.4

                -- 第1层：外层光晕拖尾
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, sx + sinA * halfTW * 1.5, sy - cosA * halfTW * 1.5)
                nvgLineTo(ctx, sx - cosA * tailLen + sinA * halfTW * 0.5, sy - sinA * tailLen - cosA * halfTW * 0.5)
                nvgLineTo(ctx, sx - cosA * tailLen - sinA * halfTW * 0.5, sy - sinA * tailLen + cosA * halfTW * 0.5)
                nvgLineTo(ctx, sx - sinA * halfTW * 1.5, sy + cosA * halfTW * 1.5)
                nvgClosePath(ctx)
                nvgFillColor(ctx, nvgRGBA(cr, cg, cb, 40))
                nvgFill(ctx)

                -- 第2层：主拖尾线
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, sx, sy)
                nvgLineTo(ctx, sx - cosA * tailLen, sy - sinA * tailLen)
                nvgStrokeColor(ctx, nvgRGBA(cr, cg, cb, 180))
                nvgStrokeWidth(ctx, tailW)
                nvgStroke(ctx)

                -- 第3层：弹头外部光晕
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, sy, glowR)
                nvgFillColor(ctx, nvgRGBA(cr, cg, cb, 60))
                nvgFill(ctx)

                -- 第4层：弹头核心
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, sy, headR)
                nvgFillColor(ctx, nvgRGBA(255, 255, 240, 240))
                nvgFill(ctx)
            end
        end

        ::continue_draw_bullet::
    end
end

-- ============================================================================
-- 猫咪（敌人）绘制
-- ============================================================================
local function DrawCatBody(ctx, color, hitFlash, facing, state)
    local r,g,b = color[1], color[2], color[3]
    if hitFlash > 0 then r,g,b = 255,60,60 end
    local f = facing  -- 1=右

    nvgSave(ctx)
    if f < 0 then nvgScale(ctx,-1,1) end

    -- 尾巴
    nvgBeginPath(ctx)
    nvgMoveTo(ctx,-8,4)
    nvgBezierTo(ctx,-24,-2,-22,-18,-12,-14)
    nvgStrokeColor(ctx,nvgRGBA(r,g,b,220)) nvgStrokeWidth(ctx,4) nvgStroke(ctx)

    -- 身体
    nvgBeginPath(ctx) nvgEllipse(ctx,0,2,11,8)
    nvgFillColor(ctx,nvgRGBA(r,g,b,255)) nvgFill(ctx)

    -- 头
    nvgBeginPath(ctx) nvgCircle(ctx,5,-6,10)
    nvgFillColor(ctx,nvgRGBA(r,g,b,255)) nvgFill(ctx)

    -- 左耳
    nvgBeginPath(ctx) nvgMoveTo(ctx,0,-14) nvgLineTo(ctx,-3,-22) nvgLineTo(ctx,5,-17)
    nvgFillColor(ctx,nvgRGBA(r,g,b,255)) nvgFill(ctx)
    nvgBeginPath(ctx) nvgMoveTo(ctx,1,-15) nvgLineTo(ctx,-1,-20) nvgLineTo(ctx,4,-17)
    nvgFillColor(ctx,nvgRGBA(255,160,160,200)) nvgFill(ctx)

    -- 右耳
    nvgBeginPath(ctx) nvgMoveTo(ctx,8,-14) nvgLineTo(ctx,12,-22) nvgLineTo(ctx,14,-15)
    nvgFillColor(ctx,nvgRGBA(r,g,b,255)) nvgFill(ctx)
    nvgBeginPath(ctx) nvgMoveTo(ctx,8,-15) nvgLineTo(ctx,11,-20) nvgLineTo(ctx,13,-16)
    nvgFillColor(ctx,nvgRGBA(255,160,160,200)) nvgFill(ctx)

    -- 眼睛（战斗状态略微变红）
    local eyeR = (state == "combat") and 200 or 60
    nvgBeginPath(ctx) nvgEllipse(ctx,2,-7,2.5,3.2)
    nvgFillColor(ctx,nvgRGBA(eyeR,40,50,255)) nvgFill(ctx)
    nvgBeginPath(ctx) nvgEllipse(ctx,8,-7,2.5,3.2)
    nvgFillColor(ctx,nvgRGBA(eyeR,40,50,255)) nvgFill(ctx)
    -- 高光
    nvgBeginPath(ctx) nvgCircle(ctx,3,-8,1) nvgFillColor(ctx,nvgRGBA(255,255,255,200)) nvgFill(ctx)

    -- 胡须
    nvgStrokeWidth(ctx,1) nvgStrokeColor(ctx,nvgRGBA(80,80,80,160))
    nvgBeginPath(ctx) nvgMoveTo(ctx,7,-4) nvgLineTo(ctx,18,-6) nvgStroke(ctx)
    nvgBeginPath(ctx) nvgMoveTo(ctx,7,-3) nvgLineTo(ctx,18,-2) nvgStroke(ctx)
    nvgBeginPath(ctx) nvgMoveTo(ctx,7,-4) nvgLineTo(ctx,-1,-6) nvgStroke(ctx)

    nvgRestore(ctx)
end

-- 通用 Boss/敌人血条绘制（自定义 Draw 的 Boss 也需要血条）
local function DrawEnemyHPBar(ctx, e, camX, camY)
    if not e.hp or not e.maxHp or e.hp <= 0 then return end
    local sx = e.x - camX
    local sy = e.y - camY
    local isBoss = e.isBoss == true
    local bw    = isBoss and 56 or 28
    local bhOff = isBoss and -52 or -32
    local bhH   = isBoss and 6 or 4
    local barColor = isBoss and nvgRGBA(255,60,60,230) or nvgRGBA(255,107,107,220)
    -- 背景
    nvgBeginPath(ctx) nvgRect(ctx, sx-bw/2, sy+bhOff, bw, bhH)
    nvgFillColor(ctx, nvgRGBA(30,30,30,200)) nvgFill(ctx)
    -- 血条
    nvgBeginPath(ctx) nvgRect(ctx, sx-bw/2, sy+bhOff, bw*(e.hp/e.maxHp), bhH)
    nvgFillColor(ctx, barColor) nvgFill(ctx)
    -- Boss 名字标签
    if isBoss and e.name then
        nvgFontFace(ctx,"sans") nvgFontSize(ctx,13)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER+NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, nvgRGBA(255,80,80,230))
        nvgText(ctx, sx, sy+bhOff-2, e.name, nil)
    end
end

function M.DrawEnemies(ctx, camX, camY, enemies, elapsedTime, visibleRooms)
    elapsedTime = elapsedTime or 0
    for _, e in ipairs(enemies) do
        -- 视野过滤：不在可见"full"房间内的敌人不绘制
        if visibleRooms and not World.IsPositionVisible(e.x, e.y, visibleRooms) then
            goto continue_enemy
        end
        -- Boss 专属绘制
        if Boss.IsCatKnight(e) then
            Boss.Draw(ctx, e, camX, camY)
            goto continue_enemy
        end
        if e.bossType == "cat_hammer" then
            Boss.Draw(ctx, e, camX, camY)
            goto continue_enemy
        end
        if e.bossType == "armored_cat" then
            Boss3.Draw(ctx, e, camX, camY)
            DrawEnemyHPBar(ctx, e, camX, camY)
            goto continue_enemy
        end
        if e.bossType == "captain_claw" then
            Boss4.Draw(ctx, e, camX, camY)
            DrawEnemyHPBar(ctx, e, camX, camY)
            goto continue_enemy
        end
        if Slime.IsSlime(e) then
            Slime.Draw(ctx, e, camX, camY)
            DrawEnemyHPBar(ctx, e, camX, camY)
            goto continue_enemy
        end

        -- 暗影蝠：精灵表绘制（idle/attack 双动画）
        if e.typeKey == "mad" then
            local sx = e.x - camX
            local sy = e.y - camY
            -- 脚下阴影
            nvgBeginPath(ctx)
            nvgEllipse(ctx, sx, sy + 12, 16, 5)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 40))
            nvgFill(ctx)
            -- 根据状态选择动画
            local tmpl = Data.ENEMY_TYPES["mad"]
            local animKey = "idle"
            if e.state == "combat" and e.shootCd and e.shootCd > 0 then
                animKey = "attack"
            elseif e.state == "combat" or (e.vx and e.vx ~= 0) or (e.vy and e.vy ~= 0) then
                animKey = "walk"
            end
            local anim = tmpl.batAnims[animKey]
            -- 懒加载精灵表
            if not batSheetImgs[animKey] then
                batSheetImgs[animKey] = nvgCreateImage(ctx, anim.sheet, 0)
            end
            local img = batSheetImgs[animKey]
            if img and img > 0 then
                local cols = anim.cols
                local frames = anim.frames
                local fw, fh = anim.frameW, anim.frameH
                local fps = anim.fps
                -- 计算当前帧
                local t = elapsedTime + e.x * 0.03
                local frame = math.floor(t * fps) % frames
                local col = frame % cols
                local row = math.floor(frame / cols)
                -- 绘制尺寸（步行，不飞行）
                local drawSize = 82
                local flip = e.facing < 0 and -1 or 1
                nvgSave(ctx)
                nvgTranslate(ctx, sx, sy)
                nvgScale(ctx, flip, 1)
                local sheetW = cols * fw
                local sheetH = anim.rows * fh
                local patScale = drawSize / fw
                local patW = sheetW * patScale
                local patH = sheetH * patScale
                local patX = -drawSize * 0.5 - col * drawSize
                local patY = -drawSize * 0.5 - row * drawSize
                local alpha = (e.hitFlash > 0) and 0.6 or 1.0
                local pat = nvgImagePattern(ctx, patX, patY, patW, patH, 0, img, alpha)
                nvgBeginPath(ctx)
                nvgRect(ctx, -drawSize * 0.5, -drawSize * 0.5, drawSize, drawSize)
                nvgFillPaint(ctx, pat)
                nvgFill(ctx)
                nvgRestore(ctx)
            end
            DrawEnemyHPBar(ctx, e, camX, camY)
            goto continue_enemy
        end

        -- 骷髅射手（patrol）：精灵表绘制
        if e.typeKey == "patrol" then
            local sx = e.x - camX
            local sy = e.y - camY
            -- 脚下阴影
            nvgBeginPath(ctx)
            nvgEllipse(ctx, sx, sy + 12, 16, 5)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 40))
            nvgFill(ctx)
            -- 根据状态选择动画
            local tmpl = Data.ENEMY_TYPES["patrol"]
            local animKey = "idle"
            if e.state == "combat" and e.shootCd and e.shootCd > 0 then
                animKey = "attack"
            elseif (e.vx and e.vx ~= 0) or (e.vy and e.vy ~= 0) then
                animKey = "walk"
            end
            local anim = tmpl.anims[animKey]
            -- 懒加载精灵表
            if not patrolSheetImgs[animKey] then
                patrolSheetImgs[animKey] = nvgCreateImage(ctx, anim.sheet, 0)
            end
            local img = patrolSheetImgs[animKey]
            if img and img > 0 then
                local cols = anim.cols
                local frames = anim.frames
                local fw, fh = anim.frameW, anim.frameH
                local fps = anim.fps
                local t = elapsedTime + e.x * 0.03
                local frame = math.floor(t * fps) % frames
                local col = frame % cols
                local row = math.floor(frame / cols)
                local drawSize = 82
                local flip = e.facing < 0 and -1 or 1
                nvgSave(ctx)
                nvgTranslate(ctx, sx, sy)
                nvgScale(ctx, flip, 1)
                -- 受击闪红
                local alpha = (e.hitFlash > 0) and 0.5 or 1.0
                local sheetW = cols * fw
                local sheetH = anim.rows * fh
                local patScale = drawSize / fw
                local patW = sheetW * patScale
                local patH = sheetH * patScale
                local patX = -drawSize * 0.5 - col * drawSize
                local patY = -drawSize * 0.5 - row * drawSize
                local pat = nvgImagePattern(ctx, patX, patY, patW, patH, 0, img, alpha)
                nvgBeginPath(ctx)
                nvgRect(ctx, -drawSize * 0.5, -drawSize * 0.5, drawSize, drawSize)
                nvgFillPaint(ctx, pat)
                nvgFill(ctx)
                nvgRestore(ctx)
            end
            DrawEnemyHPBar(ctx, e, camX, camY)
            goto continue_enemy
        end

        local sx = e.x - camX
        local sy = e.y - camY
        local isBoss = e.isBoss == true

        -- 脚下阴影
        nvgBeginPath(ctx)
        nvgEllipse(ctx, sx, sy + 10, 15, 5)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 45))
        nvgFill(ctx)

        nvgSave(ctx)
        nvgTranslate(ctx,sx,sy)

        -- Boss：绘制红色光晕 + 2倍缩放
        if isBoss then
            local pulse = 0.7 + 0.3 * math.abs(math.sin((e.x + e.y) * 0.005))
            local gp = nvgRadialGradient(ctx, 0, 0, 10, 40,
                nvgRGBA(255, 60, 60, math.floor(100 * pulse)),
                nvgRGBA(255, 0, 0, 0))
            nvgBeginPath(ctx) nvgCircle(ctx, 0, 0, 40)
            nvgFillPaint(ctx, gp) nvgFill(ctx)
            nvgScale(ctx, 2, 2)
        end

        DrawCatBody(ctx, e.color, e.hitFlash, e.facing, e.state)

        -- ⚡ 感电层数视觉：序列帧电击特效叠加
        if e.shock and e.shock.stacks > 0 then
            if not shockEffectImg then
                shockEffectImg = nvgCreateImage(ctx, "image/8786bcf17bd7bcd4de688b1a70a7f5fc.png", 0)
            end
            if shockEffectImg and shockEffectImg > 0 then
                -- 4x4网格，每帧32x32，共16帧
                local SHEET_COLS = 4
                local FRAME_SIZE = 32
                local TOTAL_FRAMES = 16
                local fps = 10 + e.shock.stacks * 2  -- 层数越多动画越快
                local t = elapsedTime + (e.x * 0.1 + e.y * 0.07)  -- 每个敌人错开相位
                local frame = math.floor(t * fps) % TOTAL_FRAMES
                local col = frame % SHEET_COLS
                local row = math.floor(frame / SHEET_COLS)
                -- 特效尺寸随层数增大
                local effSize = isBoss and (28 + e.shock.stacks * 4) or (18 + e.shock.stacks * 3)
                local alpha = math.min(255, 140 + e.shock.stacks * 25)
                -- 用 nvgImagePattern 截取当前帧
                local patX = -effSize * 0.5 - col * effSize
                local patY = -effSize * 0.5 - row * effSize
                local patW = effSize * SHEET_COLS
                local patH = effSize * SHEET_COLS
                local pat = nvgImagePattern(ctx, patX, patY, patW, patH, 0, shockEffectImg, alpha / 255.0)
                nvgBeginPath(ctx)
                nvgRect(ctx, -effSize * 0.5, -effSize * 0.5, effSize, effSize)
                nvgFillPaint(ctx, pat)
                nvgFill(ctx)
            end
        end

        -- 状态标记（！/❗）— Boss 时字体稍大
        local markSize = isBoss and 24 or 16
        local markY    = isBoss and -46 or -30
        if e.state == "alert" then
            nvgFontFace(ctx,"sans") nvgFontSize(ctx,markSize)
            nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(255,200,0,230))
            nvgText(ctx,0,markY,"！",nil)
        elseif e.state == "combat" then
            nvgFontFace(ctx,"sans") nvgFontSize(ctx,markSize)
            nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(255,60,60,230))
            nvgText(ctx,0,markY,"❗",nil)
        end

        nvgRestore(ctx)

        -- 血条（在translate外画，避免缩放影响）
        local bw    = isBoss and 56 or 28
        local bhOff = isBoss and -52 or -32
        local bhH   = isBoss and 6 or 4
        local barColor = isBoss and nvgRGBA(255,60,60,230) or nvgRGBA(255,107,107,220)
        nvgBeginPath(ctx) nvgRect(ctx,sx-bw/2,sy+bhOff,bw,bhH)
        nvgFillColor(ctx,nvgRGBA(30,30,30,200)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRect(ctx,sx-bw/2,sy+bhOff,bw*(e.hp/e.maxHp),bhH)
        nvgFillColor(ctx,barColor) nvgFill(ctx)

        -- Boss 名字标签
        if isBoss then
            nvgFontFace(ctx,"sans") nvgFontSize(ctx,13)
            nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_BOTTOM)
            nvgFillColor(ctx,nvgRGBA(255,80,80,230))
            nvgText(ctx,sx,sy+bhOff-2,e.name,nil)
        end

        ::continue_enemy::
    end

    -- Boss4 气刃弹绘制
    Boss4.DrawQiBlades(ctx, camX, camY)
end

-- ============================================================================
-- 玩家（柴犬）绘制
-- ============================================================================
function M.DrawPlayer(ctx, player, camX, camY, entranceTimer, entranceDuration)
    -- 入场特效期间控制玩家可见度
    entranceTimer = entranceTimer or 0
    entranceDuration = entranceDuration or 0.5
    if entranceTimer > 0 then
        local progress = 1.0 - entranceTimer / entranceDuration  -- 0→1
        -- Phase1 (0~35%): 玩家完全不可见
        -- Phase2 (35%~65%): 玩家逐渐显现
        -- Phase3 (65%~100%): 玩家完全可见
        if progress < 0.35 then
            return  -- 完全不绘制玩家
        elseif progress < 0.65 then
            local fadeP = (progress - 0.35) / 0.30  -- 0→1
            nvgGlobalAlpha(ctx, fadeP)
        end
        -- progress >= 0.65: 正常绘制
    end

    local sx = player.x - camX
    local sy = player.y - camY
    -- 受击晃动偏移
    if player.hitShake and player.hitShake > 0 then
        local intensity = math.min(player.hitShake, 0.2) / 0.2 * 3
        sx = sx + (math.random() * 2 - 1) * intensity
        sy = sy + (math.random() * 2 - 1) * intensity
    end
    local r,g,b = 220,150,70
    local f = player.facing

    -- ── 翻滚动画 ──────────────────────────────────────────────
    if player.rollTimer and player.rollTimer > 0 then
        local ROLL_DUR = 0.32
        local prog = 1.0 - player.rollTimer / ROLL_DUR   -- 0→1
        local angle = prog * math.pi * 2.2               -- 旋转一圈多（720°感）
        local scale = 0.72 + 0.28 * math.sin(prog * math.pi)  -- 先缩小再恢复

        -- 无敌时发出青白色光晕
        if player.rollInvincible then
            local glowAlpha = math.floor(120 * (1.0 - prog / 0.8))
            local gp = nvgRadialGradient(ctx, sx, sy, 4, 22,
                nvgRGBA(180, 255, 255, glowAlpha), nvgRGBA(0, 220, 255, 0))
            nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, 22)
            nvgFillPaint(ctx, gp) nvgFill(ctx)
        end

        -- 翻滚身体（蜷缩 + 旋转）
        nvgSave(ctx)
        nvgTranslate(ctx, sx, sy)
        nvgRotate(ctx, angle)
        nvgScale(ctx, scale, scale)

        -- 蜷缩身体（扁圆）
        nvgBeginPath(ctx) nvgEllipse(ctx, 0, 0, 11, 8)
        nvgFillColor(ctx, nvgRGBA(r, g, b, 240)) nvgFill(ctx)
        -- 腹部
        nvgBeginPath(ctx) nvgEllipse(ctx, 1, 1, 6, 4.5)
        nvgFillColor(ctx, nvgRGBA(240, 210, 150, 200)) nvgFill(ctx)
        -- 卷起的尾巴
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, -9, 0)
        nvgBezierTo(ctx, -18, -8, -14, -16, -4, -12)
        nvgStrokeColor(ctx, nvgRGBA(r, g, b, 200)) nvgStrokeWidth(ctx, 4) nvgStroke(ctx)
        -- 蜷缩的头（靠近身体）
        nvgBeginPath(ctx) nvgCircle(ctx, 6, -5, 8)
        nvgFillColor(ctx, nvgRGBA(r, g, b, 240)) nvgFill(ctx)
        -- 耳朵（压平）
        nvgBeginPath(ctx) nvgMoveTo(ctx, 3,-11) nvgLineTo(ctx, 1,-16) nvgLineTo(ctx, 8,-13)
        nvgFillColor(ctx, nvgRGBA(r, g, b, 230)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgMoveTo(ctx, 10,-11) nvgLineTo(ctx, 13,-16) nvgLineTo(ctx, 14,-12)
        nvgFillColor(ctx, nvgRGBA(r, g, b, 230)) nvgFill(ctx)

        -- 运动残影（拖尾）
        local trailAlpha = math.floor(60 * (1.0 - prog))
        nvgBeginPath(ctx)
        nvgEllipse(ctx, -player.rollDirX * 10, -player.rollDirY * 10, 9, 6)
        nvgFillColor(ctx, nvgRGBA(r, g, b, trailAlpha)) nvgFill(ctx)

        nvgRestore(ctx)

        -- 翻滚冷却圆弧指示器（玩家脚下）
        local cdTotal = 2.5
        local cdLeft  = player.rollCd or 0
        local cdProg  = 1.0 - cdLeft / cdTotal
        if cdLeft > 0 then
            nvgBeginPath(ctx)
            nvgArc(ctx, sx, sy + 16, 7, -math.pi * 0.5,
                -math.pi * 0.5 + cdProg * math.pi * 2, NVG_CW)
            nvgStrokeColor(ctx, nvgRGBA(80, 200, 255, 180))
            nvgStrokeWidth(ctx, 2.5)
            nvgStroke(ctx)
        end
        return   -- 翻滚期间跳过普通绘制
    end

    -- ── 正常状态：Spritesheet 新主角 ──────────────────────────
    -- Walk: 1024×768，4列×3行，7帧有效
    -- Idle: 1024×512，4列×2行，8帧
    if not M._playerImg then
        M._playerImg = nvgCreateImage(ctx, "image/rika_2230ae74.png", 0)
        M._playerIdleImg = nvgCreateImage(ctx, "image/rika_d3249e66.png", 0)
        M._playerAnimTimer = 0
        M._playerFrame = 0
        M._playerIdleTimer = 0
        M._playerIdleFrame = 0
    end

    -- 动画帧更新（walk 7帧，idle 8帧）
    local useIdle
    if player.isMoving then
        useIdle = false
        M._playerAnimTimer = (M._playerAnimTimer or 0) + M.dt * 12
        if M._playerAnimTimer >= 1.0 then
            M._playerAnimTimer = M._playerAnimTimer - 1.0
            M._playerFrame = (M._playerFrame + 1) % 6
        end
        -- 重置idle帧
        M._playerIdleFrame = 0
        M._playerIdleTimer = 0
    else
        useIdle = true
        M._playerIdleTimer = (M._playerIdleTimer or 0) + M.dt * 10.5
        if M._playerIdleTimer >= 1.0 then
            M._playerIdleTimer = M._playerIdleTimer - 1.0
            M._playerIdleFrame = (M._playerIdleFrame + 1) % 8
        end
        -- 重置walk帧
        M._playerFrame = 0
        M._playerAnimTimer = 0
    end

    local angle = player.aimAngle or 0
    local ax = math.cos(angle)

    -- 选择当前帧和图片
    local frameIdx = useIdle and M._playerIdleFrame or M._playerFrame
    local frameCol = frameIdx % 4
    local row = math.floor(frameIdx / 4)
    local curImg = useIdle and M._playerIdleImg or M._playerImg

    local FRAME_W, FRAME_H = 256, 256
    local DRAW_SIZE = 82  -- 绘制尺寸

    -- NanoVG imagePattern：用 offset 选帧
    local ox = sx - DRAW_SIZE * 0.5 - frameCol * DRAW_SIZE
    local oy = sy - DRAW_SIZE * 0.5 - row * DRAW_SIZE
    -- pattern 覆盖整张图，缩放到 DRAW_SIZE 每帧
    local scaleX = DRAW_SIZE / FRAME_W
    local SHEET_W = 1024
    local SHEET_H = useIdle and 512 or 768  -- idle: 4x2, walk: 4x3
    local totalW = SHEET_W * scaleX
    local totalH = SHEET_H * scaleX

    -- 脚下阴影
    nvgBeginPath(ctx)
    nvgEllipse(ctx, sx, sy + 20, 15, 5)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 45))
    nvgFill(ctx)

    nvgSave(ctx)

    -- 受击抖动偏移
    local shakeX, shakeY = 0, 0
    if player.hitFlash > 0 then
        local intensity = math.min(player.hitFlash, 1.0) * 4
        shakeX = math.random(-1, 1) * intensity
        shakeY = math.random(-1, 1) * intensity
    end
    -- 跑动时上下跃动（配合帧动画节奏）
    local bobY = 0
    if player.isMoving then
        -- 用当前帧+插值进度驱动起伏，与动画完全同步
        local bobProgress = (M._playerFrame + (M._playerAnimTimer or 0)) / 6
        bobY = math.sin(bobProgress * math.pi * 2) * 2.5
        -- 灰尘粒子生成（每5帧一颗）
        M._dustCd = (M._dustCd or 0) + 1
        if M._dustCd >= 5 then
            M._dustCd = 0
            -- 计算移动方向（用位置差）
            local prevX = M._prevPlayerX or sx
            local prevY = M._prevPlayerY or sy
            local dx = sx - prevX
            local dy = sy - prevY
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 0.5 and #dustParticles < DUST_MAX then
                -- 身后方向 = 移动方向的反方向
                local backX = -dx / dist
                local backY = -dy / dist
                dustParticles[#dustParticles + 1] = {
                    x = sx + backX * math.random(3, 6),
                    y = sy + 18 + math.random(0, 3),
                    vx = backX * (0.3 + math.random() * 0.35),
                    vy = backY * (0.2 + math.random() * 0.3) - 0.2,
                    life = 0.7,
                    size = 3.0 + math.random() * 1.0,
                }
            end
        end
    else
        M._playerBobPhase = 0
    end
    M._prevPlayerX = sx
    M._prevPlayerY = sy
    -- 更新和绘制灰尘粒子（swap-remove O(1)）
    local n = #dustParticles
    local i = 1
    while i <= n do
        local d = dustParticles[i]
        d.life = d.life - 0.032
        d.x = d.x + d.vx
        d.y = d.y + d.vy
        d.vy = d.vy - 0.01  -- 轻微上飘
        d.size = d.size * 0.98
        if d.life <= 0 then
            dustParticles[i] = dustParticles[n]
            dustParticles[n] = nil
            n = n - 1
        else
            local a = math.floor(d.life * 100)
            nvgBeginPath(ctx) nvgCircle(ctx, d.x, d.y, d.size)
            nvgFillColor(ctx, nvgRGBA(170, 155, 130, a)) nvgFill(ctx)
            i = i + 1
        end
    end
    local drawX = sx + shakeX
    local drawY = sy + shakeY + bobY

    -- 根据瞄准方向翻转
    if ax < 0 then
        nvgTranslate(ctx, drawX, drawY)
        nvgScale(ctx, -1, 1)
        nvgTranslate(ctx, -drawX, -drawY)
    end

    local pat = nvgImagePattern(ctx,
        drawX - DRAW_SIZE * 0.5 - frameCol * DRAW_SIZE,
        drawY - DRAW_SIZE * 0.5 - row * DRAW_SIZE,
        totalW, totalH, 0, curImg, 1.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, drawX - DRAW_SIZE * 0.5, drawY - DRAW_SIZE * 0.5, DRAW_SIZE, DRAW_SIZE)
    nvgFillPaint(ctx, pat)
    nvgFill(ctx)

    -- 受击闪红：用 nvgImagePatternTinted 重绘精灵（仅不透明像素变红）
    if player.hitFlash > 0 then
        local flashAlpha = math.floor(math.min(player.hitFlash, 0.25) / 0.25 * 200)
        local tintColor = nvgRGBA(255, 50, 50, flashAlpha)
        local redPat = nvgImagePatternTinted(ctx,
            drawX - DRAW_SIZE * 0.5 - frameCol * DRAW_SIZE,
            drawY - DRAW_SIZE * 0.5 - row * DRAW_SIZE,
            totalW, totalH, 0, curImg, tintColor)
        nvgBeginPath(ctx)
        nvgRect(ctx, drawX - DRAW_SIZE * 0.5, drawY - DRAW_SIZE * 0.5, DRAW_SIZE, DRAW_SIZE)
        nvgFillPaint(ctx, redPat)
        nvgFill(ctx)
    end

    nvgRestore(ctx)

    -- 武器（沿瞄准方向，不受facing翻转影响）
    local wpn = player.weapon
    if wpn and wpn.isMelee then
        -- ----------------------------------------------------------------
        -- 战术刀挥动动画
        -- shootCd > 0 表示刚攻击完正处于冷却，progress 0→1 = 挥出→收回
        -- ----------------------------------------------------------------
        local fireRate = wpn.fireRate or 0.40
        local cd       = math.max(0, player.shootCd or 0)
        local progress = 1.0 - cd / fireRate   -- 0=刚按下, 1=冷却结束

        -- 挥刀弧度：从 -70° 扫到 +70°（以瞄准方向为中心）
        local SWING_HALF = math.rad(75)
        -- 用 sin 曲线让挥刀前半段快、后半段慢（有力感）
        local swingT   = math.sin(progress * math.pi)   -- 0→1→0 弧形曲线
        local knifeAng = player.aimAngle + SWING_HALF * (1.0 - 2.0 * progress)

        -- 刀长 / 刀柄
        local BLADE_LEN  = 22
        local HANDLE_LEN = 10
        local BLADE_W    = 4
        local HANDLE_W   = 5

        nvgSave(ctx)
        nvgTranslate(ctx, sx, sy + 5)
        nvgRotate(ctx, knifeAng)

        -- 刀柄（深棕色）
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, -HANDLE_W * 0.5, HANDLE_LEN, HANDLE_W)
        nvgFillColor(ctx, nvgRGBA(100, 65, 30, 230))
        nvgFill(ctx)

        -- 护手（横档）
        nvgBeginPath(ctx)
        nvgRect(ctx, 8, -5, 3, 10)
        nvgFillColor(ctx, nvgRGBA(140, 140, 150, 230))
        nvgFill(ctx)

        -- 刀身（渐细三角形刀刃）
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, 11,  BLADE_W * 0.5)
        nvgLineTo(ctx, 11 + BLADE_LEN, 0.8)
        nvgLineTo(ctx, 11 + BLADE_LEN, -0.8)
        nvgLineTo(ctx, 11, -BLADE_W * 0.5)
        nvgClosePath(ctx)
        nvgFillColor(ctx, nvgRGBA(200, 210, 225, 240))
        nvgFill(ctx)

        -- 刀刃高光（顶部细线）
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, 11, -BLADE_W * 0.5 + 1)
        nvgLineTo(ctx, 11 + BLADE_LEN, -0.5)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 160))
        nvgStrokeWidth(ctx, 1.2)
        nvgStroke(ctx)

        nvgRestore(ctx)

        -- 挥刀斩击帧动画（精灵图 additive 混合，黑底自动透明）
        if swingT > 0.05 then
            LoadSlashImg(ctx)
            if slashImg and slashImg ~= 0 then
                -- progress 0→1 映射到帧，加速播放（前60%时间内播完所有帧）
                local fastProgress = math.min(1.0, progress / 0.6)
                local frameIdx = math.floor(fastProgress * SLASH_FRAME_COUNT)
                frameIdx = math.max(0, math.min(SLASH_FRAME_COUNT - 1, frameIdx))

                -- 显示尺寸（放大以匹配游戏比例）
                local scale = 1.5
                local dispW = SLASH_FRAME_W * scale
                local dispH = SLASH_SHEET_H * scale
                local fullW = SLASH_SHEET_W * scale

                nvgSave(ctx)
                nvgTranslate(ctx, sx, sy)
                nvgRotate(ctx, player.aimAngle)
                nvgGlobalCompositeBlendFunc(ctx, NVG_ONE, NVG_ONE)
                -- 用裁剪 + 偏移实现精灵图帧选择
                nvgIntersectScissor(ctx, 4, -dispH/2, dispW, dispH)
                nvgBeginPath(ctx)
                local patX = 4 - frameIdx * dispW  -- 偏移到当前帧
                local pat = nvgImagePattern(ctx, patX, -dispH/2, fullW, dispH, 0, slashImg, swingT)
                nvgFillPaint(ctx, pat)
                nvgRect(ctx, patX, -dispH/2, fullW, dispH)
                nvgFill(ctx)
                nvgGlobalCompositeBlendFunc(ctx, NVG_ONE, NVG_ONE_MINUS_SRC_ALPHA)
                nvgRestore(ctx)
            end
        end
    else
        -- 枪（沿瞄准方向）—— 优先像素图片
        -- 朝左时镜像翻转，避免枪倒置
        local facingLeft = math.abs(player.aimAngle) > math.pi / 2
        nvgSave(ctx)
        nvgTranslate(ctx, sx, sy + 3)
        nvgRotate(ctx, player.aimAngle)
        -- 后坐力视觉偏移（向后方微移）
        local recoil = (player.recoilTimer and player.recoilTimer > 0) and player.recoilTimer or 0
        if recoil > 0 then
            nvgTranslate(ctx, -3.5 * recoil, 1.0 * recoil)
        end
        if facingLeft then
            nvgScale(ctx, 1, -1)
        end
        local heldImg = wpn and getWeaponImage(ctx, wpn.key)
        if heldImg then
            -- 使用图片原始尺寸（不拉伸）
            local gunW, gunH
            if wpn.slot == "secondary" then
                -- 手枪: 32x32
                gunW, gunH = 32, 32
            elseif wpn.ammoType == "sniper" or wpn.pellets
                or (wpn.ammoType == "medium" and (wpn.magSize or 0) >= 50) then
                -- 狙击/霰弹/重机枪: 64x32
                gunW, gunH = 64, 32
            else
                -- 冲锋枪/步枪: 48x32
                gunW, gunH = 48, 32
            end
            local gunX = -6
            local gunY = -gunH / 2 + 3
            local gunPaint = nvgImagePattern(ctx, gunX, gunY, gunW, gunH, 0, heldImg, 1.0)
            nvgBeginPath(ctx) nvgRect(ctx, gunX, gunY, gunW, gunH)
            nvgFillPaint(ctx, gunPaint) nvgFill(ctx)
        else
            -- 回退：简单矩形枪
            nvgBeginPath(ctx) nvgRect(ctx,2,-3,18,5)
            nvgFillColor(ctx,nvgRGBA(60,60,70,230)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgRect(ctx,16,-2,8,3)
            nvgFillColor(ctx,nvgRGBA(80,80,90,200)) nvgFill(ctx)
        end
        nvgRestore(ctx)
    end

    -- 恢复入场透明度
    if entranceTimer and entranceTimer > 0 then
        nvgGlobalAlpha(ctx, 1.0)
    end
end

-- ============================================================================
-- 玩家入场光柱特效
-- ============================================================================
function M.DrawPlayerEntrance(ctx, player, camX, camY, entranceTimer, entranceDuration)
    entranceTimer = entranceTimer or 0
    entranceDuration = entranceDuration or 0.5
    if entranceTimer <= 0 then return end

    local progress = 1.0 - entranceTimer / entranceDuration  -- 0→1
    local sx = player.x - camX
    local sy = player.y - camY

    -- ── Phase 1 (0%~35%): 光柱从天而降，由细变宽 ──────────────
    if progress < 0.35 then
        local p1 = progress / 0.35  -- 0→1
        -- 光柱参数
        local beamTopW = 2 + p1 * 10       -- 顶部宽度: 2→12
        local beamBotW = 4 + p1 * 18       -- 底部宽度: 4→22
        local beamH = 100                  -- 光柱高度
        local beamTop = sy - beamH * p1    -- 从玩家位置向上延伸
        local beamBot = sy + 6             -- 底部略低于玩家脚下

        -- 光柱主体（线性渐变：顶部亮白→底部淡蓝透明）
        local topAlpha = math.floor(180 * p1)
        local botAlpha = math.floor(100 * p1)
        local grad = nvgLinearGradient(ctx, sx, beamTop, sx, beamBot,
            nvgRGBA(220, 240, 255, topAlpha), nvgRGBA(100, 180, 255, botAlpha))
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, sx - beamTopW * 0.5, beamTop)
        nvgLineTo(ctx, sx + beamTopW * 0.5, beamTop)
        nvgLineTo(ctx, sx + beamBotW * 0.5, beamBot)
        nvgLineTo(ctx, sx - beamBotW * 0.5, beamBot)
        nvgClosePath(ctx)
        nvgFillPaint(ctx, grad) nvgFill(ctx)

        -- 顶部光晕
        local glowR = 12 + p1 * 20
        local glowA = math.floor(120 * p1)
        local glow = nvgRadialGradient(ctx, sx, beamTop + 10, 2, glowR,
            nvgRGBA(255, 255, 255, glowA), nvgRGBA(200, 230, 255, 0))
        nvgBeginPath(ctx) nvgCircle(ctx, sx, beamTop + 10, glowR)
        nvgFillPaint(ctx, glow) nvgFill(ctx)

        -- 地面光圈
        local circleA = math.floor(80 * p1)
        local circleR = 18 + p1 * 14
        local groundGlow = nvgRadialGradient(ctx, sx, sy + 12, 4, circleR,
            nvgRGBA(150, 220, 255, circleA), nvgRGBA(100, 180, 255, 0))
        nvgBeginPath(ctx) nvgEllipse(ctx, sx, sy + 12, circleR, circleR * 0.4)
        nvgFillPaint(ctx, groundGlow) nvgFill(ctx)

    -- ── Phase 2 (35%~65%): 光柱收窄，玩家逐渐显现 ─────────────
    elseif progress < 0.65 then
        local p2 = (progress - 0.35) / 0.30  -- 0→1
        -- 光柱逐渐收窄并变淡
        local beamTopW = 12 * (1.0 - p2 * 0.7)  -- 12→3.6
        local beamBotW = 22 * (1.0 - p2 * 0.6)  -- 22→8.8
        local beamH = 100
        local beamTop = sy - beamH
        local beamBot = sy + 6

        local topAlpha = math.floor(180 * (1.0 - p2 * 0.6))
        local botAlpha = math.floor(100 * (1.0 - p2 * 0.7))
        local grad = nvgLinearGradient(ctx, sx, beamTop, sx, beamBot,
            nvgRGBA(220, 240, 255, topAlpha), nvgRGBA(100, 180, 255, botAlpha))
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, sx - beamTopW * 0.5, beamTop)
        nvgLineTo(ctx, sx + beamTopW * 0.5, beamTop)
        nvgLineTo(ctx, sx + beamBotW * 0.5, beamBot)
        nvgLineTo(ctx, sx - beamBotW * 0.5, beamBot)
        nvgClosePath(ctx)
        nvgFillPaint(ctx, grad) nvgFill(ctx)

        -- 玩家周围光晕（随玩家显现而增强再减弱）
        local haloA = math.floor(150 * math.sin(p2 * math.pi))
        local haloR = 30 + p2 * 10
        local halo = nvgRadialGradient(ctx, sx, sy, 8, haloR,
            nvgRGBA(200, 235, 255, haloA), nvgRGBA(120, 200, 255, 0))
        nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, haloR)
        nvgFillPaint(ctx, halo) nvgFill(ctx)

        -- 地面光圈（渐渐消散）
        local circleA = math.floor(80 * (1.0 - p2))
        local circleR = 32 - p2 * 8
        local groundGlow = nvgRadialGradient(ctx, sx, sy + 12, 4, circleR,
            nvgRGBA(150, 220, 255, circleA), nvgRGBA(100, 180, 255, 0))
        nvgBeginPath(ctx) nvgEllipse(ctx, sx, sy + 12, circleR, circleR * 0.4)
        nvgFillPaint(ctx, groundGlow) nvgFill(ctx)

    -- ── Phase 3 (65%~100%): 残余光粒子飘散 ────────────────────
    else
        local p3 = (progress - 0.65) / 0.35  -- 0→1
        -- 几颗上升的光粒子
        local particleCount = 6
        for i = 1, particleCount do
            local seed = i * 137.5
            local px = sx + math.sin(seed + p3 * 3) * (15 + i * 5)
            local py = sy - p3 * (40 + i * 12) + math.sin(seed) * 8
            local pAlpha = math.floor(160 * (1.0 - p3))
            local pSize = (3.5 - p3 * 2.0) * (0.7 + (i % 3) * 0.2)
            local pGlow = nvgRadialGradient(ctx, px, py, 0, pSize + 3,
                nvgRGBA(200, 240, 255, pAlpha), nvgRGBA(120, 200, 255, 0))
            nvgBeginPath(ctx) nvgCircle(ctx, px, py, pSize + 3)
            nvgFillPaint(ctx, pGlow) nvgFill(ctx)
            -- 粒子核心
            nvgBeginPath(ctx) nvgCircle(ctx, px, py, pSize * 0.5)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, pAlpha)) nvgFill(ctx)
        end
        -- 残余光晕消散
        local haloA = math.floor(60 * (1.0 - p3))
        local halo = nvgRadialGradient(ctx, sx, sy, 4, 20,
            nvgRGBA(180, 230, 255, haloA), nvgRGBA(100, 180, 255, 0))
        nvgBeginPath(ctx) nvgCircle(ctx, sx, sy, 20)
        nvgFillPaint(ctx, halo) nvgFill(ctx)
    end
end

-- ============================================================================
-- 三选一奖励面板
-- choices: {item1, item2, item3}（来自 Reward.Generate）
-- hoveredIdx: 当前悬停的卡片序号（1/2/3），nil 为无悬停
-- ============================================================================
function M.DrawRewardPanel(ctx, choices, hoveredIdx, sw, sh, title, subtitle, rerollsLeft)
    -- ── 全屏遮罩（柔和暗化）────────────────────────────────────
    nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, sh)
    nvgFillColor(ctx, nvgRGBA(8, 10, 18, 200))
    nvgFill(ctx)

    -- ── 标题区 ──────────────────────────────────────────────────
    local isMobile = PlatformUtils.IsMobilePlatform()
    local titleY = sh * (isMobile and 0.13 or 0.17)
    local titleFont = isMobile and 20 or 26
    local subFont = isMobile and 10 or 13
    local titleStr    = title    or "选择新天赋！"
    local subtitleStr = subtitle or "点击卡片选择一个奖励效果"

    -- 标题（金色粗体 + 柔和发光）
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, titleFont)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 发光层
    nvgFillColor(ctx, nvgRGBA(255, 215, 0, 40))
    nvgText(ctx, sw/2, titleY + 1, titleStr, nil)
    nvgText(ctx, sw/2, titleY - 1, titleStr, nil)
    -- 主文字
    nvgFillColor(ctx, nvgRGBA(255, 215, 0, 255))
    nvgText(ctx, sw/2, titleY, titleStr, nil)

    -- 副标题
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, subFont)
    nvgFillColor(ctx, nvgRGBA(139, 148, 158, 200))
    nvgText(ctx, sw/2, titleY + (isMobile and 20 or 32), subtitleStr, nil)

    -- ── 卡片尺寸计算 ────────────────────────────────────────────
    local cardW, cardH, gap, radius
    if isMobile then
        cardW = math.floor(math.min(sw * 0.27, 150))
        cardH = math.floor(cardW * 1.5)
        gap = math.floor(cardW * 0.1)
        radius = 8
    else
        cardW, cardH = 190, 280
        gap = 28
        radius = 12
    end
    local totalW = cardW * 3 + gap * 2
    local startX = (sw - totalW) / 2
    local cardY  = isMobile and (sh * 0.25) or (sh * 0.28)

    -- 稀有度颜色
    local rarityColor = {
        [1] = {160, 168, 180},  -- 白/普通
        [2] = { 78, 204, 163},  -- 绿/优质
        [3] = { 82, 130, 235},  -- 蓝/稀有
        [4] = {168,  85, 247},  -- 紫/史诗
        [5] = {255,  60,  60},  -- 红/传说
    }

    for i, item in ipairs(choices) do
        local cx = startX + (i - 1) * (cardW + gap)
        local isHover = (hoveredIdx == i)
        local rc = rarityColor[item.rarity] or {160, 168, 180}
        local br, bg, bb = rc[1], rc[2], rc[3]

        -- 像素风卡片背景（硬边 + 阴影 + 噪点）
        PixelUI.DrawCard(ctx, cx, cardY, cardW, cardH, {
            bg = {12, 16, 24, isHover and 245 or 215},
            accentColor = {br, bg, bb, isHover and 230 or 160},
            accentHeight = 3,
        })
        -- 悬停时外描边高亮（像素风 1px 硬边）
        if isHover then
            nvgBeginPath(ctx) nvgRect(ctx, cx - 1, cardY - 1, cardW + 2, cardH + 2)
            nvgStrokeColor(ctx, nvgRGBA(br, bg, bb, 200))
            nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)
        end

        -- ── 图标（大 emoji 或图片）────────────────────────────────────
        local iconSize = isMobile and math.floor(cardW * 0.28) or 48
        local iconCy = cardY + cardH * 0.24
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, iconSize)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 240))
        DrawItemIcon(ctx, item, cx + cardW/2, iconCy, iconSize)

        -- ── 稀有度标签（像素风硬边矩形）────────────────────────
        local rarityNames = { "普通", "优质", "稀有", "史诗", "传说" }
        local rlabel = rarityNames[item.rarity] or ""
        local badgeFontSize = isMobile and 8 or 9
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, badgeFontSize)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local lw = nvgTextBounds(ctx, 0, 0, rlabel, nil, nil)
        local badgeW = lw + 12
        local badgeH = 15
        local badgeX = cx + cardW/2 - badgeW/2
        local badgeY = cardY + cardH * 0.38
        -- 硬边矩形背景
        nvgBeginPath(ctx)
        nvgRect(ctx, badgeX, badgeY - badgeH/2, badgeW, badgeH)
        nvgFillColor(ctx, nvgRGBA(br, bg, bb, 40))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgRect(ctx, badgeX, badgeY - badgeH/2, badgeW, badgeH)
        nvgStrokeColor(ctx, nvgRGBA(br, bg, bb, 120))
        nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
        -- 标签文字
        nvgFillColor(ctx, nvgRGBA(br, bg, bb, 240))
        nvgText(ctx, cx + cardW/2, badgeY, rlabel, nil)

        -- ── 名称 ────────────────────────────────────────────────
        local nameFontSize = isMobile and 12 or 15
        local nameY = cardY + cardH * 0.48
        nvgFontFace(ctx, "bold") nvgFontSize(ctx, nameFontSize)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(220, 240, 248, 245))
        nvgText(ctx, cx + cardW/2, nameY, item.name or "", nil)

        -- ── 流派标签行 ──────────────────────────────────────────
        local Reward = require("Reward")
        local tagY = cardY + math.floor(cardH * 0.56)
        if item.tags and #item.tags > 0 then
            local tagTexts = {}
            for _, tag in ipairs(item.tags) do
                local pinfo = Reward.PATH_INFO[tag]
                if pinfo then
                    table.insert(tagTexts, pinfo.icon .. pinfo.name)
                end
            end
            local tagFontSize = isMobile and 7 or 9
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, tagFontSize)
            local totalTagW = 0
            local tagWs = {}
            for _, txt in ipairs(tagTexts) do
                local tw = nvgTextBounds(ctx, 0, 0, txt, nil, nil) + 10
                table.insert(tagWs, tw)
                totalTagW = totalTagW + tw + 3
            end
            totalTagW = totalTagW - 3
            local tx0 = cx + cardW/2 - totalTagW / 2
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            for ti, txt in ipairs(tagTexts) do
                local tw = tagWs[ti]
                -- 像素风硬边标签背景
                nvgBeginPath(ctx)
                nvgRect(ctx, tx0, tagY - 7, tw, 14)
                nvgFillColor(ctx, nvgRGBA(br, bg, bb, 22)) nvgFill(ctx)
                nvgStrokeColor(ctx, nvgRGBA(br, bg, bb, 80))
                nvgStrokeWidth(ctx, 0.7) nvgStroke(ctx)
                nvgFillColor(ctx, nvgRGBA(br, bg, bb, 200))
                nvgText(ctx, tx0 + tw/2, tagY, txt, nil)
                tx0 = tx0 + tw + 3
            end
            tagY = tagY + 16
        end

        -- ── 分割线（像素风 1px）─────────────────────────────────
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, cx + 12, tagY + 2)
        nvgLineTo(ctx, cx + cardW - 12, tagY + 2)
        nvgStrokeColor(ctx, nvgRGBA(br, bg, bb, 50))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)

        -- ── 描述（自动换行 - 基于像素宽度的精确断行）─────────────
        local descFontSize = isMobile and 8 or 10
        local descY = tagY + (isMobile and 12 or 16)
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, descFontSize)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(180, 195, 210, 200))
        local descText = item.desc or ""
        local maxDescW = cardW - 16
        -- UTF-8 逐字符迭代器
        local function utf8chars(s)
            local chars = {}
            local i = 1
            while i <= #s do
                local b = s:byte(i)
                local len = 1
                if b >= 0xF0 then len = 4
                elseif b >= 0xE0 then len = 3
                elseif b >= 0xC0 then len = 2
                end
                table.insert(chars, s:sub(i, i + len - 1))
                i = i + len
            end
            return chars
        end
        -- 基于实际渲染宽度断行（支持最多5行）
        local lines = {}
        local totalBounds = nvgTextBounds(ctx, 0, 0, descText, nil, nil)
        if totalBounds > maxDescW then
            local chars = utf8chars(descText)
            local currentLine = ""
            for _, ch in ipairs(chars) do
                local testLine = currentLine .. ch
                local w = nvgTextBounds(ctx, 0, 0, testLine, nil, nil)
                if w > maxDescW and #currentLine > 0 then
                    table.insert(lines, currentLine)
                    currentLine = ch
                else
                    currentLine = testLine
                end
            end
            if #currentLine > 0 then
                table.insert(lines, currentLine)
            end
        else
            lines = { descText }
        end
        -- 绘制所有行（居中对齐）
        local lineH = descFontSize + 3
        local totalH = #lines * lineH
        local startY = descY + (lineH - totalH) * 0.5
        -- 限制不超出卡片底部（留空给"点击选择"提示）
        local maxY = cardY + cardH - (isMobile and 24 or 32)
        for li, line in ipairs(lines) do
            local ly = startY + (li - 1) * lineH
            if ly > maxY then break end
            nvgText(ctx, cx + cardW/2, ly, line, nil)
        end

        -- ── 底部提示 ────────────────────────────────────────────
        local promptY = cardY + cardH - (isMobile and 12 or 16)
        local promptFont = isMobile and 9 or 11
        if isHover then
            nvgFontFace(ctx, "bold") nvgFontSize(ctx, promptFont)
            nvgFillColor(ctx, nvgRGBA(br, bg, bb, 240))
            nvgText(ctx, cx + cardW/2, promptY, "▶ 点击选择", nil)
        else
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, promptFont)
            nvgFillColor(ctx, nvgRGBA(100, 120, 140, 80))
            nvgText(ctx, cx + cardW/2, promptY, "点击选择", nil)
        end
    end

    -- ── 刷新按钮（像素风）──────────────────────────────────────
    if rerollsLeft and rerollsLeft > 0 then
        local btnW = isMobile and 130 or 160
        local btnH = isMobile and 30 or 36
        local btnX = sw / 2 - btnW / 2
        local btnY = cardY + cardH + (isMobile and 14 or 22)
        local isHoverBtn = hoveredIdx == -1

        -- 像素风按钮
        PixelUI.DrawButton(ctx, btnX, btnY, btnW, btnH,
            "🔁 刷新选项  ×" .. rerollsLeft, {
            state = isHoverBtn and "hover" or "normal",
            fontSize = isMobile and 11 or 13,
            textColor = {255, 215, 0, isHoverBtn and 255 or 200},
            accentLeft = false,
            borderColor = {255, 215, 0, isHoverBtn and 180 or 100},
        })
    end
end

-- 判断鼠标是否悬停在某张卡片上（供 main.lua 调用）
function M.GetRewardHoverIndex(mx, my, choices, sw, sh)
    local isMobile = PlatformUtils.IsMobilePlatform()
    local cardW, cardH, gap
    if isMobile then
        cardW = math.floor(math.min(sw * 0.27, 150))
        cardH = math.floor(cardW * 1.5)
        gap = math.floor(cardW * 0.1)
    else
        cardW, cardH = 190, 280
        gap = 28
    end
    local totalW = cardW*3 + gap*2
    local startX = (sw - totalW) / 2
    local cardY  = isMobile and (sh * 0.25) or (sh * 0.28)
    for i = 1, #choices do
        local cx = startX + (i-1)*(cardW+gap)
        if mx >= cx and mx <= cx+cardW and my >= cardY and my <= cardY+cardH then
            return i
        end
    end
    return nil
end

-- 判断鼠标是否点击了刷新按钮（rerollsLeft > 0 时才有效）
function M.IsRerollButtonHit(mx, my, sw, sh, rerollsLeft)
    if not rerollsLeft or rerollsLeft <= 0 then return false end
    local isMobile = PlatformUtils.IsMobilePlatform()
    local cardW, cardH
    if isMobile then
        cardW = math.floor(math.min(sw * 0.27, 150))
        cardH = math.floor(cardW * 1.5)
    else
        cardW, cardH = 190, 280
    end
    local cardY = isMobile and (sh * 0.25) or (sh * 0.28)
    local btnW = isMobile and 130 or 160
    local btnH = isMobile and 30 or 36
    local btnX = sw / 2 - btnW / 2
    local btnY = cardY + cardH + (isMobile and 14 or 22)
    return mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH
end

-- 判断鼠标是否悬停在刷新按钮上（用于高亮，返回 true/false）
function M.IsRerollButtonHover(mx, my, sw, sh, rerollsLeft)
    return M.IsRerollButtonHit(mx, my, sw, sh, rerollsLeft)
end

-- ============================================================================
-- HUD
-- ============================================================================
-- floor: 当前层数（1~20）
-- hasBoss: 是否有 Boss 存活
-- 命中测试：武器切换区域（手机端点击）
-- 武器行固定在左上角面板内，不依赖 sw/sh
function M.HitTestWeaponSwapBtn(mx, my, isMobile, sw, sh)
    -- 左上角面板 px=10,py=10,pw=190，武器区从分割线(+38)到副武器行下方
    local py = 10
    if isMobile and sw and sh then
        py = math.max(18, math.floor(math.min(sw, sh) * 0.055))
    end
    return mx >= 10 and mx <= 200 and my >= py + 34 and my <= py + 76
end

local function DrawRoomMiniMap(ctx, player, x, y, w, h, elapsedTime)
    local rooms = World.GetRooms and World.GetRooms() or {}
    if not rooms or #rooms == 0 then return end
    h = math.max(56, h or 112)
    local pad = 6
    PixelUI.DrawPanel(ctx, x, y, w, h, {
        bg = {8, 12, 18, 145}, shadow = false, noiseAlpha = 4, highlight = false,
    })

    local mapW = w - pad * 2
    local mapH = h - pad * 2
    local scale = math.min(mapW / World.COLS, mapH / World.ROWS)
    local ox = x + pad + (mapW - World.COLS * scale) * 0.5
    local oy = y + pad + (mapH - World.ROWS * scale) * 0.5

    local t = elapsedTime or 0

    for _, room in ipairs(rooms) do
        local info = World.ROOM_INFO and World.ROOM_INFO[room.kind or "battle"] or nil
        local visible = room.discovered or (info and info.alwaysVisible)
        local rr, gg, bb = 105, 130, 145
        if info and info.color then rr, gg, bb = info.color[1], info.color[2], info.color[3] end
        local alpha = visible and 120 or 30
        local rx = ox + (room.x - 1) * scale
        local ry = oy + (room.y - 1) * scale
        local rw = math.max(2, room.w * scale)
        local rh = math.max(2, room.h * scale)

        -- 出口房间：脉冲高亮，确保始终醒目可见
        local isExit = (room.kind == "exit")
        local fillAlpha = visible and 34 or 10
        local strokeW = visible and 1.0 or 0.6
        if isExit and visible then
            local pulse = (math.sin(t * 3.0) + 1.0) * 0.5  -- 0~1 脉冲
            fillAlpha = math.floor(60 + pulse * 50)          -- 60~110
            alpha = math.floor(180 + pulse * 75)             -- 180~255
            strokeW = 1.5 + pulse * 0.5                      -- 1.5~2.0
        end

        nvgBeginPath(ctx)
        nvgRect(ctx, rx, ry, rw, rh)
        nvgFillColor(ctx, nvgRGBA(rr, gg, bb, fillAlpha))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgRect(ctx, rx, ry, rw, rh)
        nvgStrokeColor(ctx, nvgRGBA(rr, gg, bb, alpha))
        nvgStrokeWidth(ctx, strokeW)
        nvgStroke(ctx)

        if visible and info and info.icon and info.icon ~= "" then
            nvgFontFace(ctx, "sans")
            local fontSize = isExit and 12 or 10
            nvgFontSize(ctx, fontSize)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(rr, gg, bb, isExit and 255 or 230))
            local iconText = info.icon
            if room.locked then iconText = "🔒" .. iconText end
            nvgText(ctx, rx + rw * 0.5, ry + rh * 0.5, iconText, nil)
        elseif visible and room.locked then
            -- 无图标的战斗房但被锁住时显示锁
            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, 9)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 190, 70, 240))
            nvgText(ctx, rx + rw * 0.5, ry + rh * 0.5, "🔒", nil)
        end
    end

    if player then
        local pc, pr = World.WorldToTile(player.x, player.y)
        local px = ox + (pc - 0.5) * scale
        local py = oy + (pr - 0.5) * scale
        nvgBeginPath(ctx)
        nvgCircle(ctx, px, py, 2.2)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 245))
        nvgFill(ctx)
    end
end

function M.DrawHUD(ctx, player, enemies, elapsedTime, sw, sh, floor, hasBoss, isMobile)
    floor = floor or 1
    local PlayerM = require("Player")

    -- ── 像素风配色（与医疗用品快捷栏同款） ──────────────────────────
    local C_TEXT    = nvgRGBA(255,255,255,220)      -- 主文字（白）
    local C_DIM     = nvgRGBA(180,200,210,180)      -- 次要文字（冷灰）
    local C_CYAN    = nvgRGBA(0,240,255,220)        -- 主题青
    local C_RED     = nvgRGBA(255,80,80,230)        -- 血条红
    local C_BLUE    = nvgRGBA(80,180,255,230)       -- 护甲蓝
    local C_GOLD    = nvgRGBA(251,191,36,230)       -- 金色
    local C_GREEN   = nvgRGBA(74,222,128,230)       -- 加速绿
    local C_ORANGE  = nvgRGBA(251,146,60,230)       -- 警告橙

    -- ── 左上角面板（像素风暗色） ──────────────────────────────────
    local topInset = isMobile and math.max(18, math.floor(math.min(sw, sh) * 0.055)) or 10
    local px, py = 10, topInset
    local pw = 190
    local ph = isMobile and 130 or 108
    PixelUI.DrawPanel(ctx, px, py, pw, ph, {
        bg = {10,15,20,170}, shadow = false, noiseAlpha = 6, highlight = false,
    })

    -- HP 血条（红色）+ 护盾叠加（绿色）
    local hpRatio = math.max(0, player.hp / player.maxHp)
    local barX, barW, barH = px + 22, 120, 6
    -- 血条背景
    nvgBeginPath(ctx) nvgRect(ctx, barX, py + 14, barW, barH)
    nvgFillColor(ctx, nvgRGBA(15,20,25,200)) nvgFill(ctx)
    -- 血条填充（固定红色）
    if hpRatio > 0 then
        nvgBeginPath(ctx) nvgRect(ctx, barX, py + 14, barW * hpRatio, barH)
        nvgFillColor(ctx, nvgRGBA(255,80,80,220)) nvgFill(ctx)
    end
    -- 护盾叠加在血条上方（绿色）
    if player.shieldMax and player.shieldMax > 0 and (player.shieldHp or 0) > 0 then
        local shieldRatio = math.min(1, player.shieldHp / player.shieldMax)
        nvgBeginPath(ctx) nvgRect(ctx, barX, py + 14, barW * shieldRatio, barH)
        nvgFillColor(ctx, nvgRGBA(74,222,128,220)) nvgFill(ctx)
    end
    -- HP 图标 + 数值
    nvgFontFace(ctx,"sans") nvgFontSize(ctx,9)
    nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx,C_RED)
    nvgText(ctx,px+6,py+14+barH/2,"❤",nil)
    nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx,C_TEXT)
    if player.shieldMax and player.shieldMax > 0 then
        if player.shieldRechargeTimer and player.shieldRechargeTimer > 0 then
            nvgText(ctx,px+pw-8,py+14+barH/2,
                string.format("%d/%d 🔰%ds", math.max(0,math.floor(player.hp)), player.maxHp,
                    math.ceil(player.shieldRechargeTimer)), nil)
        else
            nvgText(ctx,px+pw-8,py+14+barH/2,
                string.format("%d/%d 🔰%d", math.max(0,math.floor(player.hp)), player.maxHp,
                    math.floor(player.shieldHp or 0)), nil)
        end
    else
        nvgText(ctx,px+pw-8,py+14+barH/2,
            string.format("%d/%d", math.max(0,math.floor(player.hp)), player.maxHp), nil)
    end

    -- 护甲条
    local armor = PlayerM.CalcArmorValue(player)
    local maxArmor = 110
    local armRatio = math.max(0, math.min(1, armor / maxArmor))
    nvgBeginPath(ctx) nvgRect(ctx, barX, py + 26, barW, barH)
    nvgFillColor(ctx, nvgRGBA(15,20,25,200)) nvgFill(ctx)
    if armRatio > 0 then
        nvgBeginPath(ctx) nvgRect(ctx, barX, py + 26, barW * armRatio, barH)
        nvgFillColor(ctx, nvgRGBA(80,180,255,220)) nvgFill(ctx)
    end
    nvgFontSize(ctx,9)
    nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx,C_BLUE)
    nvgText(ctx,px+6,py+26+barH/2,"🛡",nil)
    nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx,C_TEXT)
    nvgText(ctx,px+pw-8,py+26+barH/2, string.format("%d", math.floor(armor)), nil)

    -- 分割线（青色极淡）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx,px+8,py+38) nvgLineTo(ctx,px+pw-8,py+38)
    nvgStrokeColor(ctx,nvgRGBA(0,240,255,30)) nvgStrokeWidth(ctx,0.5) nvgStroke(ctx)

    -- 武器行
    local wname   = player.weapon and player.weapon.name or "无"
    local ammo    = player.weapon and player.weapon.ammo or 0
    local maxAmmo = player.weapon and player.weapon.maxAmmo or 0
    local ammoType = (player.weapon and player.weapon.ammoType) or ""
    nvgFontFace(ctx,"sans") nvgFontSize(ctx,10)
    nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx,C_TEXT)
    nvgText(ctx,px+8,py+48, "🔫 "..wname, nil)
    -- 弹药数（右侧）
    local stashRaw = PlayerM.GetStashCount and PlayerM.GetStashCount(player)
    local stash = (ammoType ~= "" and stashRaw ~= nil) and stashRaw or nil
    if player.reloadTimer and player.reloadTimer > 0 then
        local rl = player.weapon and player.weapon.reloadTime or 1.5
        local prog = 1 - (player.reloadTimer / rl)
        nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx,C_ORANGE)
        nvgText(ctx,px+pw-8,py+48, string.format("装弹 %d%%", math.floor(prog*100)), nil)
    else
        nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_MIDDLE)
        local ammoColor = (ammo == 0) and C_RED or C_DIM
        nvgFillColor(ctx,ammoColor)
        if stash then
            nvgText(ctx,px+pw-8,py+48, string.format("%d/%d +%d", ammo, maxAmmo, stash), nil)
        else
            nvgText(ctx,px+pw-8,py+48, string.format("%d/%d", ammo, maxAmmo), nil)
        end
    end
    -- 弹药储备行
    if stash and player.reloadTimer == 0 then
        nvgFontSize(ctx,8)
        nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_BASELINE)
        local stashColor = (stash == 0) and C_RED or C_DIM
        nvgFillColor(ctx,stashColor)
        nvgText(ctx,px+pw-8,py+60, string.format("储备 %d 发", stash), nil)
    end

    -- ── 手机端：副武器行 + 切换按钮 ──────────────────────────────
    if isMobile then
        local altW  = player.altWeapon
        local altName = altW and altW.name or "空"
        local altAmmo = altW and string.format("%d/%d", altW.ammo or 0, altW.maxAmmo or 0) or "--"

        nvgFontFace(ctx,"sans") nvgFontSize(ctx,9)
        nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx,C_DIM)
        nvgText(ctx,px+8, py+62, "副: "..altName, nil)
        nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx,altW and C_DIM or nvgRGBA(255,255,255,60))
        nvgText(ctx,px+pw-8, py+62, altAmmo, nil)

        -- 切换徽章（像素风暗色）
        local btnX = px + pw - 40
        local btnY2 = py + 70
        local btnW = 36
        local btnH = 14
        nvgBeginPath(ctx)
        nvgRect(ctx, btnX, btnY2, btnW, btnH)
        nvgFillColor(ctx, altW and nvgRGBA(15,25,35,220) or nvgRGBA(10,15,20,150))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgRect(ctx, btnX, btnY2, btnW, btnH)
        nvgStrokeColor(ctx, altW and nvgRGBA(0,240,255,130) or nvgRGBA(0,240,255,40))
        nvgStrokeWidth(ctx, 0.8) nvgStroke(ctx)
        nvgFontFace(ctx,"sans") nvgFontSize(ctx,8)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, altW and nvgRGBA(0,240,255,200) or nvgRGBA(0,240,255,80))
        nvgText(ctx, btnX + btnW/2, btnY2 + btnH/2, "⇄ 切换", nil)
    end

    -- 肾上腺素 buff
    local boostRow = isMobile and (py+88) or ((stash ~= nil) and (py+70) or (py+60))
    if player.speedBoostTimer and player.speedBoostTimer > 0 then
        nvgFontSize(ctx,9)
        nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx,C_GREEN)
        nvgText(ctx,px+8,boostRow,
            string.format("💉 加速 x%.1f  %.1fs", player.speedBoostMult or 1, player.speedBoostTimer), nil)
        boostRow = boostRow + 12
    end

    -- 分割线（青色极淡）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx,px+8,boostRow+2) nvgLineTo(ctx,px+pw-8,boostRow+2)
    nvgStrokeColor(ctx,nvgRGBA(0,240,255,30)) nvgStrokeWidth(ctx,0.5) nvgStroke(ctx)

    -- 击杀 + 背包格数 + 金钱
    nvgFontSize(ctx,9)
    nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
    local invUsed = #player.inventory.items
    local invCap  = player.inventory.width * player.inventory.height
    nvgFillColor(ctx,C_TEXT)
    nvgText(ctx,px+8,boostRow+12, string.format("✘ 击杀 %d", player.kills), nil)
    nvgFillColor(ctx,C_DIM)
    local curBagId = player.equip and player.equip.bag and player.equip.bag.id or "small"
    local bpIconEnd = drawBackpackIcon(ctx, px+8+56, boostRow+12, 12, curBagId)
    nvgText(ctx, bpIconEnd, boostRow+12, string.format("%d/%d", invUsed, invCap), nil)
    nvgFillColor(ctx,C_GOLD)
    nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_MIDDLE)
    local lootStr = tostring(player.lootValue)
    local lootTW = nvgTextBounds(ctx, 0, 0, lootStr)
    nvgText(ctx,px+pw-8,boostRow+12, lootStr, nil)
    drawMoneyIcon(ctx, px+pw-8-lootTW-14, boostRow+12, 12)

    -- ── 右上角面板（层数 + 小地图合体） ──────────────────────────────────
    local rpW = 160
    local rpFloorH = hasBoss and 52 or 32
    local rpMapH = isMobile and 104 or 112
    local rpH = rpFloorH + rpMapH + 4  -- 层数区 + 间隔 + 地图区
    local rpx = sw - rpW - 10
    local rpy = topInset
    PixelUI.DrawPanel(ctx, rpx, rpy, rpW, rpH, {
        bg = {10,15,20,170}, shadow = false, noiseAlpha = 6, highlight = false,
    })

    nvgFontFace(ctx,"sans")
    nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)

    -- 楼层
    nvgFontSize(ctx,12)
    nvgFillColor(ctx,C_CYAN)
    nvgText(ctx,rpx+12,rpy+18, string.format("📍 第 %d / 20 层", floor), nil)

    -- Boss 警告（脉动红字）
    if hasBoss then
        local pulse = math.floor(((math.sin(elapsedTime*4)+1)*0.5)*80 + 175)
        nvgFontSize(ctx,12)
        nvgFillColor(ctx,nvgRGBA(255,80,80,pulse))
        nvgText(ctx,rpx+12,rpy+36,"⚠ 先击败BOSS！",nil)
    end

    DrawRoomMiniMap(ctx, player, rpx, rpy + rpFloorH + 4, rpW, rpMapH, elapsedTime)

    -- 搜索动画面板（物品逐一揭示 + 放大镜）
    local ss = player.searchState
    if ss and ss.isSearching then
        local prog   = math.min(ss.progress / ss.duration, 1.0)
        local items  = ss.lootPreview or {}
        local found  = ss.discoveredCount or 0
        local label  = ss.container and (ss.container.isEnemy and
                        ("搜索: " .. (ss.container.name or "敌人")) or "开箱中...") or "搜索中..."

        -- 面板尺寸：左侧放大镜区 + 右侧物品列表
        local ITEM_H  = 26
        local listMax = math.max(3, math.min(#items, 6))  -- 最多显示6行
        local PW      = 320
        local PH      = 56 + listMax * ITEM_H + 20
        local px0     = (sw - PW) / 2
        local py0     = sh - PH - 24

        -- 面板背景（白描风格）
        nvgBeginPath(ctx) nvgRoundedRect(ctx, px0, py0, PW, PH, 10)
        nvgFillColor(ctx, nvgRGBAf(0, 0, 0, 0.45)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRoundedRect(ctx, px0, py0, PW, PH, 10)
        nvgStrokeColor(ctx, nvgRGBA(255,255,255,60)) nvgStrokeWidth(ctx, 1.0) nvgStroke(ctx)

        -- 放大镜图标（旋转动画）
        local cx = px0 + 28
        local cy = py0 + 28
        local rot = (ss.progress * 2.0) % (math.pi * 2)
        nvgSave(ctx)
        nvgTranslate(ctx, cx, cy)
        nvgRotate(ctx, rot)
        -- 镜身圆
        nvgBeginPath(ctx) nvgCircle(ctx, 0, 0, 12)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 180))
        nvgStrokeWidth(ctx, 2.0) nvgStroke(ctx)
        -- 镜柄
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, 8, 8) nvgLineTo(ctx, 16, 16)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 180))
        nvgStrokeWidth(ctx, 2.5) nvgLineCap(ctx, NVG_ROUND) nvgStroke(ctx)
        -- 内部扫描线（进度感）
        local scanY = -10 + 20 * (prog % 0.5 / 0.5)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, -9, scanY) nvgLineTo(ctx, 9, scanY)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 80))
        nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)
        nvgRestore(ctx)

        -- 标题
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 13)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 220))
        nvgText(ctx, px0 + 50, py0 + 18, label, nil)

        -- 进度条（白描风格）
        local sBarX = px0 + 50
        local sBarW = PW - 60
        local sBarY = py0 + 32
        nvgBeginPath(ctx) nvgRoundedRect(ctx, sBarX, sBarY, sBarW, 5, 2.5)
        nvgFillColor(ctx, nvgRGBAf(1,1,1,0.08)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRoundedRect(ctx, sBarX, sBarY, sBarW * prog, 5, 2.5)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 180)) nvgFill(ctx)

        -- 物品列表（逐一显示）
        local listY = py0 + 52
        nvgFontSize(ctx, 12)
        for i = 1, math.min(found, listMax) do
            local item = items[i]
            if item then
                local iy = listY + (i - 1) * ITEM_H
                -- 最新发现的那一项有出现动画（从透明淡入）
                local alpha = 220
                if i == found then
                    local t = (ss.progress - (i-1)/math.max(1,#items) * ss.duration)
                    alpha = math.floor(math.min(1.0, t * 6) * 220)
                end
                -- 稀有度色块
                local r, g, b = RC(item.rarity or 1)
                nvgBeginPath(ctx) nvgRect(ctx, px0 + 10, iy + 3, 4, ITEM_H - 8)
                nvgFillColor(ctx, nvgRGBA(r, g, b, alpha)) nvgFill(ctx)
                -- 图标
                local nameOffX = 42
                if item.itype == "bag" and item.data and BAG_IMG_PATHS[item.data.id] then
                    local bpEnd = drawBackpackIcon(ctx, px0 + 20, iy + ITEM_H/2, 14, item.data.id)
                    nameOffX = bpEnd - px0
                elseif item.itype == "helmet" and item.data and HELMET_IMG_PATHS[item.data.id] then
                    local hlEnd = drawHelmetIcon(ctx, px0 + 20, iy + ITEM_H/2, 14, item.data.id)
                    if hlEnd then nameOffX = hlEnd - px0 end
                elseif item.itype == "armor" and item.data and ARMOR_IMG_PATHS[item.data.id] then
                    local arEnd = drawArmorIcon(ctx, px0 + 20, iy + ITEM_H/2, 14, item.data.id)
                    if arEnd then nameOffX = arEnd - px0 end
                else
                    nvgFontSize(ctx, 14)
                    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFillColor(ctx, nvgRGBA(255, 255, 255, alpha))
                    DrawItemIcon(ctx, item, px0 + 20, iy + ITEM_H/2, 20)
                end
                -- 名称
                nvgFontSize(ctx, 11)
                nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(r, g, b, alpha))
                nvgText(ctx, px0 + nameOffX, iy + ITEM_H/2, item.name or "", nil)
                -- 价值
                nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(220, 190, 80, alpha))
                nvgText(ctx, px0 + PW - 10, iy + ITEM_H/2,
                    string.format("¥%d", item.value or 0), nil)
            end
        end

        -- 未发现的用问号占位（最多显示 listMax 行）
        for i = found + 1, math.min(#items, listMax) do
            local iy = listY + (i - 1) * ITEM_H
            nvgBeginPath(ctx) nvgRoundedRect(ctx, px0 + 10, iy + 3, 4, ITEM_H - 8, 2)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 40)) nvgFill(ctx)
            nvgFontSize(ctx, 11)
            nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 80))
            nvgText(ctx, px0 + 20, iy + ITEM_H/2, "?  ········", nil)
        end

        -- 超出显示行数时的省略提示
        if #items > listMax then
            local moreY = listY + listMax * ITEM_H + 4
            nvgFontSize(ctx, 10)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 100))
            nvgText(ctx, px0 + PW/2, moreY,
                string.format("还有 %d 件...", #items - listMax), nil)
        end
    end

    -- 撤离提示（底部）
    local ec = World.EXIT_CELLS[1]
    if ec then
        local ex = (ec.col-0.5)*T
        local ey = (ec.row-0.5)*T
        local ddSq = (player.x-ex)^2+(player.y-ey)^2
        if ddSq < 10000 or player.extracting > 0 then -- 100^2
            local exProg = player.extracting / 3.0
            nvgFontSize(ctx,18) nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(255,255,255,220))
            if player.extracting > 0 then
                nvgText(ctx,sw/2,sh-30,string.format("正在撤离 %.1f/3.0s (E键取消)", 3-player.extracting),nil)
                -- 进度条（白描风格）
                nvgBeginPath(ctx) nvgRoundedRect(ctx,(sw-200)/2,sh-52,200,6,3)
                nvgFillColor(ctx,nvgRGBAf(1,1,1,0.1)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRoundedRect(ctx,(sw-200)/2,sh-52,200*exProg,6,3)
                nvgFillColor(ctx,nvgRGBA(255,255,255,200)) nvgFill(ctx)
            else
                nvgText(ctx,sw/2,sh-30,"按 E 撤离",nil)
            end
        end
    end

end

-- ============================================================================
-- 通用：绘制一个 GridInventory 网格（背包或容器均可）
-- inv       : Inventory.New() 返回的网格对象
-- originX/Y : 网格左上角像素坐标
-- cellSize  : 每格像素大小
-- ctx       : NanoVG context
-- ============================================================================
local function DrawGrid(ctx, inv, originX, originY, cellSize)
    local cs = cellSize
    local iw = inv.width
    local ih = inv.height

    -- 绘制空格背景
    for row = 1, ih do
        for col = 1, iw do
            local x = originX + (col-1)*cs
            local y = originY + (row-1)*cs
            nvgBeginPath(ctx) nvgRect(ctx,x+1,y+1,cs-2,cs-2)
            nvgFillColor(ctx,nvgRGBA(10,16,20,190)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgRect(ctx,x,y,cs,cs)
            nvgStrokeColor(ctx,nvgRGBA(0,240,255,15)) nvgStrokeWidth(ctx,0.5) nvgStroke(ctx)
        end
    end

    -- 绘制物品格子
    for _, entry in ipairs(inv.items) do
        local placedW = entry.rotated and entry.ih or entry.iw
        local placedH = entry.rotated and entry.iw or entry.ih
        local x = originX + (entry.x-1)*cs
        local y = originY + (entry.y-1)*cs
        local w = placedW * cs
        local h = placedH * cs
        local r,g,b = RC(entry.rarity or 1)

        -- 物品底色（像素硬边）
        nvgBeginPath(ctx) nvgRect(ctx,x+2,y+2,w-4,h-4)
        nvgFillColor(ctx,nvgRGBA(r,g,b,35)) nvgFill(ctx)
        -- 边框（像素硬边）
        nvgBeginPath(ctx) nvgRect(ctx,x+1,y+1,w-2,h-2)
        nvgStrokeColor(ctx,nvgRGBA(r,g,b,180)) nvgStrokeWidth(ctx,1.5) nvgStroke(ctx)

        -- 图标（居中）—— 武器优先使用像素图片，枪长对框长
        local cellGunImg = (entry.itype == "weapon" and entry.data)
            and getWeaponImage(ctx, entry.data.key) or nil
        if cellGunImg then
            -- 根据武器类型确定图片实际宽高比（不拉伸）
            local imgRatioHW = 32/48  -- 默认 SMG/步枪 48x32
            if entry.data and entry.data.slot == "secondary" then
                imgRatioHW = 1.0  -- 手枪 32x32，正方形
            elseif entry.data and (
                entry.data.ammoType == "sniper" or entry.data.pellets
                or (entry.data.ammoType == "medium" and (entry.data.magSize or 0) >= 50)
            ) then
                imgRatioHW = 32/64  -- 狙击/霰弹/重机枪 64x32
            end
            local longSide = math.max(w, h) - 8
            local shortSide = math.min(w, h) - 8
            -- 按长边缩放，保持实际比例
            local cImgW = longSide
            local cImgH = cImgW * imgRatioHW
            if cImgH > shortSide then cImgH = shortSide; cImgW = cImgH / imgRatioHW end
            if h > w then
                -- 竖格：旋转90°，枪长对齐框高
                nvgSave(ctx)
                nvgTranslate(ctx, x + w/2, y + h/2)
                nvgRotate(ctx, -math.pi/2)
                local rPaint = nvgImagePattern(ctx, -cImgW/2, -cImgH/2, cImgW, cImgH, 0, cellGunImg, 1.0)
                nvgBeginPath(ctx) nvgRect(ctx, -cImgW/2, -cImgH/2, cImgW, cImgH)
                nvgFillPaint(ctx, rPaint) nvgFill(ctx)
                nvgRestore(ctx)
            else
                -- 横格或正方格：正常放置
                local cImgX = x + (w - cImgW) / 2
                local cImgY = y + (h - cImgH) / 2
                local cPaint = nvgImagePattern(ctx, cImgX, cImgY, cImgW, cImgH, 0, cellGunImg, 1.0)
                nvgBeginPath(ctx) nvgRect(ctx, cImgX, cImgY, cImgW, cImgH)
                nvgFillPaint(ctx, cPaint) nvgFill(ctx)
            end
        elseif entry.itype == "bag" and entry.data and BAG_IMG_PATHS[entry.data.id] then
            -- 背包类物品用自定义图片
            local bagImgSize = math.min(w, h) - 8
            drawBackpackIcon(ctx, x + (w - bagImgSize)/2, y + h/2, bagImgSize, entry.data.id)
        elseif entry.itype == "helmet" and entry.data and HELMET_IMG_PATHS[entry.data.id] then
            -- 头盔类物品用自定义图片
            local helmImgSize = math.min(w, h) - 8
            drawHelmetIcon(ctx, x + (w - helmImgSize)/2, y + h/2, helmImgSize, entry.data.id)
        elseif entry.itype == "armor" and entry.data and ARMOR_IMG_PATHS[entry.data.id] then
            -- 护甲类物品用自定义图片
            local armorImgSize = math.min(w, h) - 8
            drawArmorIcon(ctx, x + (w - armorImgSize)/2, y + h/2, armorImgSize, entry.data.id)
        elseif entry.data and entry.data.img then
            -- 有精灵图的物品：按格子实际宽高绘制
            local imgW = w - 6
            local imgH = h - 6
            DrawItemIcon(ctx, entry.data, x + w/2, y + h/2, imgW, imgH)
        else
            local iconSize = math.min(w, h) * 0.55
            nvgFontFace(ctx,"sans") nvgFontSize(ctx,iconSize)
            nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(255,255,255,220))
            nvgText(ctx, x+w/2, y+h/2, entry.icon or "?", nil)
        end

        -- 价值（右下角，仅在格子够大时显示）
        if h >= cs*1.8 then
            nvgFontSize(ctx,9) nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_BOTTOM)
            nvgFillColor(ctx,nvgRGBA(150,220,150,200))
            local valStr = tostring(entry.value)
            local valTW = nvgTextBounds(ctx, 0, 0, valStr)
            nvgText(ctx,x+w-3,y+h-2, valStr, nil)
            drawMoneyIcon(ctx, x+w-3-valTW-11, y+h-2-5, 10)
        end

        -- 弹药耗尽标记：武器且 ammoType 存在（非近战）且 ammo == 0 → 右上角红色 "0"
        if entry.itype == "weapon" and entry.data then
            local wpnData = entry.data
            if wpnData.ammoType and (wpnData.ammo or 0) == 0 then
                -- 红色小圆底
                local bx = x + w - 8
                local by2 = y + 8
                nvgBeginPath(ctx) nvgCircle(ctx, bx, by2, 7)
                nvgFillColor(ctx, nvgRGBA(220, 40, 40, 230)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgCircle(ctx, bx, by2, 7)
                nvgStrokeColor(ctx, nvgRGBA(255, 120, 120, 200)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
                -- 白色"0"
                nvgFontFace(ctx, "bold") nvgFontSize(ctx, 9)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
                nvgText(ctx, bx, by2, "0", nil)
            end
        end

        -- 堆叠数量角标（右下角显示 ×N）
        if (entry.qty or 1) > 1 then
            local qtyStr = "×" .. tostring(entry.qty)
            local bx = x + w - 4
            local by2 = y + h - 4
            -- 暗色底衬提高可读性
            nvgFontFace(ctx, "bold") nvgFontSize(ctx, 11)
            nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 180))
            nvgText(ctx, bx+1, by2+1, qtyStr, nil)
            -- 白色文字
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 240))
            nvgText(ctx, bx, by2, qtyStr, nil)
        end
    end
end

-- ============================================================================
-- 通用通知 Toast（始终显示，不依赖面板）
-- ============================================================================
function M.DrawNotification(ctx, notification, sw, sh)
    if not notification or not notification.timer or notification.timer <= 0 then return end
    local alpha = math.min(1, notification.timer / 0.4)
    local a255  = math.floor(alpha * 220)
    local isFull = (notification.text == "背包已满！" or notification.text == "背包已满")
    local tr, tg, tb = 230, 255, 235
    if isFull then tr, tg, tb = 255, 100, 80 end

    local tw = math.max(140, #notification.text * 7 + 20)
    local th = 26
    local tx = sw / 2 - tw / 2
    local ty = sh * 0.25 - th / 2

    nvgBeginPath(ctx) nvgRect(ctx, tx, ty, tw, th)
    nvgFillColor(ctx, nvgRGBA(10, 14, 28, math.floor(alpha * 200))) nvgFill(ctx)
    nvgBeginPath(ctx) nvgRect(ctx, tx, ty, tw, th)
    nvgStrokeColor(ctx, nvgRGBA(tr, tg, tb, a255)) nvgStrokeWidth(ctx, 1.2) nvgStroke(ctx)

    nvgFontSize(ctx, 13) nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(tr, tg, tb, a255))
    nvgText(ctx, tx + tw / 2, ty + th / 2, notification.text, nil)
end

-- ============================================================================
-- 计算背包面板布局（DrawInventoryPanel 与 HitTestInventoryPanel 共用）
-- ============================================================================
function M.GetInventoryPanelLayout(player, sw, sh, isMobile)
    local inv  = player.inventory
    local floor = math.floor

    -- ========== 手机端：全屏两栏布局（左=全部装备，右=背包网格）==========
    if isMobile then
        local TITLE_H = 34
        local BOTTOM_H = 28  -- 底部提示栏
        local MARGIN = 4
        local GAP = 6        -- 左右列间距

        local panX = MARGIN
        local panY = MARGIN
        local PW = sw - MARGIN * 2
        local PH = sh - MARGIN * 2

        -- 左列宽度：屏幕40%，最小120，最大180
        local LEFT_W = math.max(120, math.min(180, floor(PW * 0.38)))
        -- 右列起始 & 宽度
        local rightX = panX + LEFT_W + GAP
        local RIGHT_W = PW - LEFT_W - GAP - 6  -- 留少许右边距

        -- 内容区高度（标题栏和底栏之间）
        local contentH = PH - TITLE_H - BOTTOM_H - 8

        -- 动态CELL：确保网格完整显示在右列，但不要过大（上限30px）
        local cellByW = floor(RIGHT_W / inv.width)
        local cellByH = floor(contentH / inv.height)
        local CELL = math.max(18, math.min(30, cellByW, cellByH))

        -- 左列装备布局 —— 武器槽(3个) + 分隔 + 装备槽(3个)
        local contentY = panY + TITLE_H
        local leftInnerW = LEFT_W - 12  -- 左右各留6px
        local leftX = panX + 6

        -- 武器槽高度：根据剩余空间动态
        local WPN_COUNT = 3
        local EQUIP_COUNT = 3
        local TOTAL_SLOTS = WPN_COUNT + EQUIP_COUNT  -- 6个槽位
        local SEP_H = 6  -- 分隔线占位
        local slotH = math.max(28, math.min(42, floor((contentH - SEP_H * 2) / TOTAL_SLOTS)))
        local WPN_H = slotH
        local SLOT_H = slotH

        local wpnDefs = {
            { key="primaryGun",   label="主武器",  icon="\xF0\x9F\x94\xAB", slot="primary" },
            { key="secondaryGun", label="副武器", icon="\xF0\x9F\x94\xAB", slot="secondary" },
            { key="knife",        label="战术刀",  icon="\xF0\x9F\x94\xAA", slot="knife" },
        }
        local weaponSlots = {}
        for i, wd in ipairs(wpnDefs) do
            weaponSlots[i] = {
                key   = wd.key,
                label = wd.label,
                icon  = wd.icon,
                slot  = wd.slot,
                x = leftX,
                y = contentY + (i-1) * WPN_H,
                w = leftInnerW,
                h = WPN_H - 2,
            }
        end

        local sepY1 = contentY + WPN_COUNT * WPN_H + 2  -- 武器与装备间分隔

        local EQUIP_DEFS = {
            {slot="helmet", label="\xE5\xA4\xB4\xE7\x9B\x94"},
            {slot="armor",  label="\xE6\x8A\xA4\xE7\x94\xB2"},
            {slot="bag",    label="\xE8\x83\x8C\xE5\x8C\x85"},
        }
        local equipStartY = sepY1 + SEP_H
        local slots = {}
        for i, s in ipairs(EQUIP_DEFS) do
            slots[i] = {
                slot  = s.slot,
                label = s.label,
                x = leftX,
                y = equipStartY + (i-1) * SLOT_H,
                w = leftInnerW,
                h = SLOT_H - 2,
            }
        end

        -- 背包网格位置（右列居中）
        local gridTotalW = inv.width * CELL
        local gridTotalH = inv.height * CELL
        local gridX = rightX + floor((RIGHT_W - gridTotalW) / 2)
        local gridY = panY + TITLE_H + floor((contentH - gridTotalH) / 2)

        -- 关闭按钮：右下角红色长方形"返回"
        local closeBtnW = 60
        local closeBtnH = 28
        local closeBtn = { x = panX + PW - closeBtnW - 6, y = panY + PH - closeBtnH - 6, w = closeBtnW, h = closeBtnH }

        return {
            isMobile = true,
            panelX = panX, panelY = panY, panelW = PW, panelH = PH,
            CELL = CELL, LEFT_W = LEFT_W, PAD = GAP,
            SLOT_H = SLOT_H, TITLE_H = TITLE_H,
            WPN_H = WPN_H, WEAPON_SLOTS_H = WPN_COUNT * WPN_H,
            equipSlots = slots,
            weaponSlots = weaponSlots,
            bagGridX = gridX, bagGridY = gridY,
            bagCols  = inv.width,  bagRows = inv.height,
            closeBtn = closeBtn,
            -- 手机端额外布局信息
            leftX = leftX, leftInnerW = leftInnerW,
            sepY1 = sepY1, contentY = contentY,
            statY = equipStartY + EQUIP_COUNT * SLOT_H + 6,
            bottomY = panY + PH - BOTTOM_H,
        }
    end

    -- ========== PC 端：原有布局（装备在左，武器+网格在右）==========
    local CELL    = 34
    local LEFT_W  = 192
    local PAD     = 12
    local SLOT_H  = 50
    local TITLE_H = 38   -- 标题区高度（内容从 panY+38 开始）
    local WPN_H   = 44   -- 武器槽高度
    local WPN_GAP = 6    -- 武器槽区域底部间距

    local bagPxW = inv.width  * CELL
    local bagPxH = inv.height * CELL

    -- 武器区占3格（主武器、备用、刀），放在右侧顶部
    local WEAPON_SLOTS_H = WPN_H * 3 + WPN_GAP

    local RIGHT_W = bagPxW
    local RIGHT_H = WEAPON_SLOTS_H + bagPxH

    local PW = LEFT_W + PAD + RIGHT_W + PAD
    local PH = math.max(RIGHT_H + 90, 380)
    local panX = math.max(8, floor((sw - PW) / 2))
    local panY = math.max(8, floor((sh - PH) / 2))

    -- 装备槽命中区域
    local EQUIP_DEFS = {
        {slot="helmet", label="\xE5\xA4\xB4\xE7\x9B\x94"},
        {slot="armor",  label="\xE6\x8A\xA4\xE7\x94\xB2"},
        {slot="bag",    label="\xE8\x83\x8C\xE5\x8C\x85"},
    }
    local slots = {}
    for i, s in ipairs(EQUIP_DEFS) do
        slots[i] = {
            slot  = s.slot,
            label = s.label,
            x = panX + 10,
            y = panY + TITLE_H + (i-1) * SLOT_H,
            w = LEFT_W - 20,
            h = SLOT_H - 4,
        }
    end

    local rightX = panX + LEFT_W + PAD
    -- 右侧武器槽（主武器/备用/刀）
    local wpnSlotW = bagPxW     -- 与背包网格同宽
    local wpnDefs = {
        { key="primaryGun",   label="\xE4\xB8\xBB\xE6\xAD\xA6\xE5\x99\xA8",  icon="\xF0\x9F\x94\xAB", slot="primary" },
        { key="secondaryGun", label="\xE5\xA4\x87\xE7\x94\xA8\xE6\xAD\xA6\xE5\x99\xA8", icon="\xF0\x9F\x94\xAB", slot="secondary" },
        { key="knife",        label="\xE6\x88\x98\xE6\x9C\xAF\xE5\x88\x80",  icon="\xF0\x9F\x94\xAA", slot="knife" },
    }
    local weaponSlots = {}
    for i, wd in ipairs(wpnDefs) do
        weaponSlots[i] = {
            key   = wd.key,
            label = wd.label,
            icon  = wd.icon,
            slot  = wd.slot,
            x = rightX,
            y = panY + TITLE_H + (i-1) * WPN_H,
            w = wpnSlotW,
            h = WPN_H - 2,
        }
    end

    local gridY = panY + TITLE_H + WEAPON_SLOTS_H

    -- 关闭按钮（右上角标题栏，手机端专用）
    local closeBtn = { x = panX + PW - 30, y = panY + 5, w = 26, h = 26 }

    return {
        panelX = panX, panelY = panY, panelW = PW, panelH = PH,
        CELL = CELL, LEFT_W = LEFT_W, PAD = PAD,
        SLOT_H = SLOT_H, TITLE_H = TITLE_H,
        WPN_H = WPN_H, WEAPON_SLOTS_H = WEAPON_SLOTS_H,
        equipSlots = slots,
        weaponSlots = weaponSlots,
        bagGridX = rightX, bagGridY = gridY,
        bagCols  = inv.width,  bagRows = inv.height,
        closeBtn = closeBtn,
    }
end

-- ============================================================================
-- 背包面板（TAB/I 键）—— 网格版（装备槽 + 背包 + 胸挂网格）
-- ============================================================================
function M.DrawInventoryPanel(ctx, player, sw, sh, isMobile)
    local PlayerM   = require("Player")
    local Inventory = require("Inventory")
    local inv  = player.inventory

    local lp = M.GetInventoryPanelLayout(player, sw, sh, isMobile)
    local panX, panY, PW, PH = lp.panelX, lp.panelY, lp.panelW, lp.panelH
    local CELL, LEFT_W, PAD, SLOT_H = lp.CELL, lp.LEFT_W, lp.PAD, lp.SLOT_H

    -- 配色
    local C_BG     = nvgRGBA(12,17,22,248)
    local C_BORDER = nvgRGBA(0,240,255,55)
    local C_TITLE  = nvgRGBA(0,240,255,230)       -- 青蓝标题 #00f0ff
    local C_TEXT   = nvgRGBA(208,208,224,220)
    local C_DIM    = nvgRGBA(0,200,220,160)
    local C_GREEN  = nvgRGBA(78,204,163,200)       -- 已装备边框
    local C_EMPTY  = nvgRGBA(80,80,100,90)         -- 空槽边框

    -- 面板背景（像素风）
    PixelUI.DrawPanel(ctx, panX, panY, PW, PH, {
        bg = {12, 17, 22, 248},
        noiseAlpha = 14,
    })

    -- 标题栏底色（像素风硬边）
    nvgBeginPath(ctx) nvgRect(ctx, panX+1, panY+1, PW-2, 36)
    nvgFillColor(ctx, nvgRGBA(15, 22, 28, 235)) nvgFill(ctx)

    -- 标题
    nvgFontFace(ctx,"sans") nvgFontSize(ctx,15)
    nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx,C_TITLE)
    local bpTitle = " 背包  ( TAB 键关闭 )"
    local bpTitleTW = nvgTextBounds(ctx, 0, 0, bpTitle)
    nvgText(ctx, panX+PW/2 + 7, panY+18, bpTitle, nil)
    local titleBagId = player and player.equip and player.equip.bag and player.equip.bag.id or "small"
    drawBackpackIcon(ctx, panX+PW/2 - bpTitleTW/2 - 7, panY+18, 14, titleBagId)

    -- 关闭按钮（手机：右下角红色长方形"返回"；PC：右上角 ×）
    local cb = lp.closeBtn
    if cb then
        if lp.isMobile then
            -- 红色长方形返回按钮
            nvgBeginPath(ctx) nvgRect(ctx,cb.x,cb.y,cb.w,cb.h)
            nvgFillColor(ctx,nvgRGBA(180,30,30,220)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgRect(ctx,cb.x,cb.y,cb.w,cb.h)
            nvgStrokeColor(ctx,nvgRGBA(255,80,80,200)) nvgStrokeWidth(ctx,1) nvgStroke(ctx)
            nvgFontFace(ctx,"bold") nvgFontSize(ctx,13)
            nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(255,255,255,240))
            nvgText(ctx,cb.x+cb.w/2,cb.y+cb.h/2,"返回",nil)
        else
            nvgBeginPath(ctx) nvgRect(ctx,cb.x,cb.y,cb.w,cb.h)
            nvgFillColor(ctx,nvgRGBA(40,12,12,200)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgRect(ctx,cb.x,cb.y,cb.w,cb.h)
            nvgStrokeColor(ctx,nvgRGBA(220,80,80,160)) nvgStrokeWidth(ctx,1) nvgStroke(ctx)
            nvgFontFace(ctx,"bold") nvgFontSize(ctx,14)
            nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(240,100,100,230))
            nvgText(ctx,cb.x+cb.w/2,cb.y+cb.h/2,"×",nil)
        end
    end

    -- 左右分隔线
    local divX = panX + LEFT_W + PAD/2
    nvgBeginPath(ctx) nvgMoveTo(ctx,divX,panY+38) nvgLineTo(ctx,divX,panY+PH-10)
    nvgStrokeColor(ctx,C_BORDER) nvgStrokeWidth(ctx,0.8) nvgStroke(ctx)

    -- ---- 左侧：装备槽 ----
    -- 手机端：武器槽与装备槽之间的小分隔线
    if lp.isMobile and lp.sepY1 then
        local sy1 = lp.sepY1
        nvgBeginPath(ctx) nvgMoveTo(ctx, panX+10, sy1) nvgLineTo(ctx, panX+LEFT_W-4, sy1)
        nvgStrokeColor(ctx,nvgRGBA(0,240,255,40)) nvgStrokeWidth(ctx,0.6) nvgStroke(ctx)
    end

    for _, s in ipairs(lp.equipSlots) do
        local equip = player.equip[s.slot]
        local sx, sy, slotW, slotH = s.x, s.y, s.w, s.h

        if equip then
            -- 已装备：绿色底色 + 稀有度边框（像素硬边）
            local r,g,b = RC(equip.rarity or 1)
            nvgBeginPath(ctx) nvgRect(ctx,sx,sy,slotW,slotH)
            nvgFillColor(ctx,nvgRGBA(78,204,163,20)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgRect(ctx,sx,sy,slotW,slotH)
            nvgStrokeColor(ctx,nvgRGBA(r,g,b,170)) nvgStrokeWidth(ctx,1.5) nvgStroke(ctx)
        else
            -- 空槽：暗色底色 + 灰色边框（像素硬边）
            nvgBeginPath(ctx) nvgRect(ctx,sx,sy,slotW,slotH)
            nvgFillColor(ctx,nvgRGBA(255,255,255,12)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgRect(ctx,sx,sy,slotW,slotH)
            nvgStrokeColor(ctx,C_EMPTY) nvgStrokeWidth(ctx,1) nvgStroke(ctx)
        end

        -- 槽位标签（左上角）
        nvgFontSize(ctx,9) nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_TOP)
        nvgFillColor(ctx,C_DIM)
        nvgText(ctx,sx+6,sy+4,s.label,nil)

        if equip then
            local r,g,b = RC(equip.rarity or 1)
            -- 名称
            nvgFontSize(ctx,12) nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(r,g,b,240))
            -- 背包/头盔类装备用图片图标替换 emoji
            if s.slot == "bag" and equip.id and BAG_IMG_PATHS[equip.id] then
                local iconEndX = drawBackpackIcon(ctx, sx+8, sy+slotH/2+4, 16, equip.id)
                nvgText(ctx, iconEndX, sy+slotH/2+4, equip.name, nil)
            elseif s.slot == "helmet" and equip.id and HELMET_IMG_PATHS[equip.id] then
                local hlEndX = drawHelmetIcon(ctx, sx+8, sy+slotH/2+4, 16, equip.id)
                nvgText(ctx, hlEndX or (sx+26), sy+slotH/2+4, equip.name, nil)
            elseif s.slot == "armor" and equip.id and ARMOR_IMG_PATHS[equip.id] then
                local arEndX = drawArmorIcon(ctx, sx+8, sy+slotH/2+4, 16, equip.id)
                nvgText(ctx, arEndX or (sx+26), sy+slotH/2+4, equip.name, nil)
            else
                nvgText(ctx,sx+8,sy+slotH/2+4,(equip.icon or "").." "..equip.name,nil)
            end
            -- 副属性（右侧）
            local sub = nil
            if equip.armor then sub = "+"..equip.armor.."甲"
            elseif equip.extraAmmo then sub = "+"..equip.extraAmmo.."弹"
            elseif equip.bagW then sub = equip.bagW.."×"..equip.bagH
            end
            if sub then
                nvgFontSize(ctx,9) nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx,nvgRGBA(0,220,240,190))
                nvgText(ctx,sx+slotW-6,sy+slotH/2+4,sub,nil)
            end
            -- 耐久度（若有）
            if equip.durability ~= nil then
                local maxDur = equip.maxDurability or 100
                local durPct = math.max(0, equip.durability / maxDur)
                local dR = durPct > 0.5 and 78 or (durPct > 0.2 and 243 or 233)
                local dG = durPct > 0.5 and 204 or (durPct > 0.2 and 156 or 69)
                local dB = durPct > 0.5 and 163 or (durPct > 0.2 and 18 or 96)
                nvgBeginPath(ctx) nvgRect(ctx,sx+4,sy+slotH-5,slotW-8,3)
                nvgFillColor(ctx,nvgRGBA(40,40,60,140)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRect(ctx,sx+4,sy+slotH-5,(slotW-8)*durPct,3)
                nvgFillColor(ctx,nvgRGBA(dR,dG,dB,200)) nvgFill(ctx)
            end
            -- "点击卸下" 提示（右上角）
            nvgFontSize(ctx,8) nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_TOP)
            nvgFillColor(ctx,nvgRGBA(255,107,107,120))
            nvgText(ctx,sx+slotW-4,sy+3,"点击卸下",nil)
        else
            nvgFontSize(ctx,10) nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(0,240,255,22))
            nvgText(ctx,sx+8,sy+slotH/2+4,"（空槽）",nil)
        end
    end

    -- 属性统计（左下）
    local armor = PlayerM.CalcArmorValue(player)
    local statY = lp.statY or (panY + lp.TITLE_H + 4 * SLOT_H + 10)
    nvgFontSize(ctx,9) nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_TOP)
    nvgFillColor(ctx,nvgRGBA(78,204,163,200))
    nvgText(ctx,panX+10,statY,
        string.format("❤ %d/%d   🛡 %d", player.hp, player.maxHp, armor), nil)
    local bagFree  = Inventory.FreeSlots(inv)
    local bagTotal = inv.width * inv.height
    nvgFillColor(ctx,C_DIM)
    local bagStr = string.format("包:%d/%d  ", bagTotal-bagFree, bagTotal)
    nvgText(ctx,panX+10,statY+14, bagStr .. tostring(player.lootValue), nil)
    local bagStrTW = nvgTextBounds(ctx, 0, 0, bagStr)
    drawMoneyIcon(ctx, panX+10+bagStrTW, statY+14, 10)
    nvgText(ctx,panX+10,statY+28,
        string.format("击:%d  %s %d/%d", player.kills,
            player.weapon and player.weapon.name or "无",
            player.weapon and player.weapon.ammo or 0,
            player.weapon and player.weapon.maxAmmo or 0), nil)

    -- 弹药储备信息
    local stash = player.ammoStash or {}
    local ammoLabels = {
        { key="light",  name="轻型", color=nvgRGBA(180,220,255,200) },
        { key="medium", name="中型", color=nvgRGBA(255,210,100,200) },
        { key="heavy",  name="重型", color=nvgRGBA(255,140,80,200)  },
        { key="sniper", name="狙击", color=nvgRGBA(200,120,255,200) },
    }
    local ammoY = statY + 42
    nvgFontSize(ctx, 8.5)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local ammoX = panX + 10
    for _, a in ipairs(ammoLabels) do
        local cnt = stash[a.key] or 0
        nvgFillColor(ctx, cnt > 0 and a.color or nvgRGBA(80,80,100,140))
        nvgText(ctx, ammoX, ammoY, a.name .. ":" .. tostring(cnt), nil)
        ammoX = ammoX + 44
    end

    -- 底部操作提示
    nvgFontSize(ctx, lp.isMobile and 8 or 9)
    nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx,nvgRGBA(60,140,150,130))
    local hintY = lp.bottomY and (lp.bottomY + 20) or (panY+PH-6)
    if lp.isMobile then
        nvgText(ctx,panX+10,hintY,"点击装备 | 拖拽互换 | 整理",nil)
    else
        nvgText(ctx,panX+10,hintY,"左键装备  |  拖拽武器槽⇄互换/→背包卸装  |  G键整理",nil)
    end

    -- ---- 右侧：武器槽区域 ----
    local bagState  = player.bagDragState
    local dragItem  = bagState and bagState.dragItem
    local hoverWpn  = bagState and bagState.hoverWeaponSlot
    local srcWpnKey = bagState and bagState.srcWeaponKey   -- 正在从该槽拖起
    local hoverBag  = bagState and bagState.hoverBagGrid   -- 悬停的背包格子

    for _, ws in ipairs(lp.weaponSlots) do
        local wsx, wsy, wsw, wsh = ws.x, ws.y, ws.w, ws.h
        local isHover  = (hoverWpn == ws.key)
        local isSrc    = (srcWpnKey == ws.key)   -- 正在从此槽拖起
        local isActive = (player.activeSlot == ws.slot)  -- 当前选中的槽位
        -- 拖起中的武器在视觉上显示为空（Ghost 单独绘制）
        -- 主武器/备用武器栏：如果实际持刀（isMelee），视作空（刀已在刀槽显示）
        local rawWpn = (not isSrc) and player[ws.key] or nil
        local wpn = rawWpn
        if wpn and wpn.isMelee and ws.key ~= "knife" then wpn = nil end

        -- 背景（像素硬边，五态）
        nvgBeginPath(ctx) nvgRect(ctx,wsx,wsy,wsw,wsh)
        if isHover then
            nvgFillColor(ctx,nvgRGBA(0,240,255,35))
        elseif isSrc then
            nvgFillColor(ctx,nvgRGBA(255,165,0,18))  -- 橙色：被拖起
        elseif isActive then
            nvgFillColor(ctx,nvgRGBA(255,220,60,25))  -- 金黄底色：选中
        elseif wpn then
            nvgFillColor(ctx,nvgRGBA(78,204,163,18))
        else
            nvgFillColor(ctx,nvgRGBA(255,255,255,10))
        end
        nvgFill(ctx)

        -- 边框（像素硬边，五态）
        nvgBeginPath(ctx) nvgRect(ctx,wsx,wsy,wsw,wsh)
        if isHover then
            nvgStrokeColor(ctx,nvgRGBA(100,180,255,220))
            nvgStrokeWidth(ctx,1.8)
        elseif isSrc then
            nvgStrokeColor(ctx,nvgRGBA(255,165,0,200))  -- 橙色：被拖起
            nvgStrokeWidth(ctx,1.5)
        elseif isActive then
            nvgStrokeColor(ctx,nvgRGBA(255,220,60,220))  -- 金黄边框：选中
            nvgStrokeWidth(ctx,1.8)
        elseif wpn then
            local r,g,b = RC(wpn.rarity or 1)
            nvgStrokeColor(ctx,nvgRGBA(r,g,b,160))
            nvgStrokeWidth(ctx,1.2)
        else
            nvgStrokeColor(ctx,nvgRGBA(80,80,110,100))
            nvgStrokeWidth(ctx,1)
        end
        nvgStroke(ctx)

        -- 标签
        nvgFontSize(ctx,9) nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_TOP)
        nvgFillColor(ctx,nvgRGBA(0,200,220,160))
        nvgText(ctx,wsx+6,wsy+3,ws.label,nil)

        if wpn then
            local r,g,b = RC(wpn.rarity or 1)
            -- 像素图标 + 名称
            local gunImg = getWeaponImage(ctx, wpn.key)
            if gunImg then
                -- 图片原始 66x44，按槽高等比缩放
                local imgH = wsh - 8
                local imgW = imgH * (66 / 44)
                local imgX = wsx + 4
                local imgY = wsy + 4
                local imgPaint = nvgImagePattern(ctx, imgX, imgY, imgW, imgH, 0, gunImg, 1.0)
                nvgBeginPath(ctx) nvgRect(ctx, imgX, imgY, imgW, imgH)
                nvgFillPaint(ctx, imgPaint) nvgFill(ctx)
                -- 名称（图片右侧）
                nvgFontSize(ctx,11) nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx,nvgRGBA(r,g,b,240))
                nvgText(ctx, imgX + imgW + 4, wsy+wsh/2+4, wpn.name, nil)
            else
                -- 无图片回退：emoji + 名称
                nvgFontSize(ctx,13) nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx,nvgRGBA(r,g,b,240))
                nvgText(ctx,wsx+8,wsy+wsh/2+4,(wpn.icon or ws.icon).." "..wpn.name,nil)
            end
            -- 弹药（刀无弹药）
            if wpn.ammoType then
                nvgFontSize(ctx,9) nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx,nvgRGBA(0,220,240,170))
                nvgText(ctx,wsx+wsw-6,wsy+wsh/2+4,
                    string.format("%d/%d", wpn.ammo or 0, wpn.maxAmmo or 0),nil)
            end
            -- 刀槽不允许替换（右下角提示）
            if ws.key == "knife" then
                nvgFontSize(ctx,8) nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_BOTTOM)
                nvgFillColor(ctx,nvgRGBA(255,107,107,80))
                nvgText(ctx,wsx+wsw-4,wsy+wsh-3,"固定",nil)
            else
                nvgFontSize(ctx,8) nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_BOTTOM)
                nvgFillColor(ctx,nvgRGBA(0,200,220,90))
                nvgText(ctx,wsx+wsw-4,wsy+wsh-3,"拖入替换",nil)
            end
        else
            nvgFontSize(ctx,11) nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(0,240,255,22))
            nvgText(ctx,wsx+8,wsy+wsh/2+4,ws.icon.."（空）",nil)
            if ws.key ~= "knife" then
                nvgFontSize(ctx,8) nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_BOTTOM)
                nvgFillColor(ctx,nvgRGBA(0,180,200,90))
                nvgText(ctx,wsx+wsw-4,wsy+wsh-3,"拖入装备",nil)
            end
        end
    end

    -- 武器区与背包区分隔线（PC端：武器在网格上方，需要分隔；手机端：武器在左列，跳过）
    local sepY = lp.bagGridY - 4
    if not lp.isMobile then
        nvgBeginPath(ctx) nvgMoveTo(ctx,lp.bagGridX,sepY) nvgLineTo(ctx,lp.bagGridX+lp.bagCols*CELL,sepY)
        nvgStrokeColor(ctx,nvgRGBA(0,240,255,40)) nvgStrokeWidth(ctx,0.8) nvgStroke(ctx)
    end

    -- ---- 背包网格 ----
    local rightX = lp.bagGridX
    local gridY  = lp.bagGridY
    nvgFontSize(ctx, lp.isMobile and 9 or 10)
    nvgTextAlign(ctx,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx,nvgRGBA(255,215,0,180))
    local gridLabelY = lp.isMobile and (gridY - 10) or (sepY - 4)
    nvgText(ctx,rightX,gridLabelY,
        string.format("背包 %d×%d", inv.width, inv.height), nil)
    DrawGrid(ctx, inv, rightX, gridY, CELL)

    -- 背包格子悬停高亮（像素硬边）
    if hoverBag and dragItem then
        local hx = rightX + (hoverBag.col - 1) * CELL
        local hy = gridY  + (hoverBag.row - 1) * CELL
        nvgBeginPath(ctx) nvgRect(ctx,hx+1,hy+1,CELL-2,CELL-2)
        nvgFillColor(ctx,nvgRGBA(255,165,0,50)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRect(ctx,hx+1,hy+1,CELL-2,CELL-2)
        nvgStrokeColor(ctx,nvgRGBA(255,165,0,220)) nvgStrokeWidth(ctx,1.5) nvgStroke(ctx)
    end

    -- ---- 拖拽 Ghost（像素硬边）----
    if dragItem then
        local dx = (bagState.dragX or 0) - 18
        local dy = (bagState.dragY or 0) - 18
        local rc3 = Data.RARITY_COLOR[dragItem.rarity or 1] or {180,180,180}
        -- 硬阴影（2px偏移）
        nvgBeginPath(ctx) nvgRect(ctx,dx+2,dy+2,36,36)
        nvgFillColor(ctx,nvgRGBA(0,0,0,80)) nvgFill(ctx)
        -- 稀有度背景
        nvgBeginPath(ctx) nvgRect(ctx,dx,dy,36,36)
        nvgFillColor(ctx,nvgRGBA(rc3[1],rc3[2],rc3[3],90)) nvgFill(ctx)
        -- 白色边框
        nvgBeginPath(ctx) nvgRect(ctx,dx,dy,36,36)
        nvgStrokeColor(ctx,nvgRGBA(255,255,255,200)) nvgStrokeWidth(ctx,1.5) nvgStroke(ctx)
        -- 图标（优先像素图片）
        local dragGunImg = dragItem.key and getWeaponImage(ctx, dragItem.key)
        if dragGunImg then
            local gImgW, gImgH = 34, 34 * (44/66)
            local gImgX = dx + (36 - gImgW) / 2
            local gImgY = dy + (36 - gImgH) / 2
            local gPaint = nvgImagePattern(ctx, gImgX, gImgY, gImgW, gImgH, 0, dragGunImg, 1.0)
            nvgBeginPath(ctx) nvgRect(ctx, gImgX, gImgY, gImgW, gImgH)
            nvgFillPaint(ctx, gPaint) nvgFill(ctx)
        elseif dragItem.itype == "bag" and dragItem.data and BAG_IMG_PATHS[dragItem.data.id] then
            drawBackpackIcon(ctx, dx + 4, dy + 18, 28, dragItem.data.id)
        elseif dragItem.itype == "helmet" and dragItem.data and HELMET_IMG_PATHS[dragItem.data.id] then
            drawHelmetIcon(ctx, dx + 4, dy + 18, 28, dragItem.data.id)
        elseif dragItem.itype == "armor" and dragItem.data and ARMOR_IMG_PATHS[dragItem.data.id] then
            drawArmorIcon(ctx, dx + 4, dy + 18, 28, dragItem.data.id)
        elseif dragItem.data and dragItem.data.img then
            DrawItemIcon(ctx, dragItem.data, dx+18, dy+18, 28)
        else
            nvgFontSize(ctx,20) nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(255,255,255,230))
            nvgText(ctx,dx+18,dy+18,dragItem.icon or "🔫",nil)
        end
    end
end

-- ============================================================================
-- 背包面板命中测试
-- 返回: {action="equipSlot",slot=...} / {action="bagItem",id,itype,itype_orig,slot,name,entry}
--       {action="rigItem",...} / {action="weaponSlot",key=...}
--       {action="panelBg"} / nil（面板外）
-- ============================================================================
function M.HitTestInventoryPanel(layout, player, mx, my)
    if not layout then return nil end
    local lp = layout
    -- 面板外
    if mx < lp.panelX or mx > lp.panelX + lp.panelW
    or my < lp.panelY or my > lp.panelY + lp.panelH then
        return nil
    end

    -- 武器槽
    for _, ws in ipairs(lp.weaponSlots) do
        if mx >= ws.x and mx <= ws.x + ws.w
        and my >= ws.y and my <= ws.y + ws.h then
            return { action="weaponSlot", key=ws.key }
        end
    end

    -- 装备槽
    for _, s in ipairs(lp.equipSlots) do
        if mx >= s.x and mx <= s.x + s.w
        and my >= s.y and my <= s.y + s.h then
            return { action="equipSlot", slot=s.slot }
        end
    end

    local Inventory = require("Inventory")
    local cs = lp.CELL

    -- 背包网格
    local inv = player.inventory
    local bx, by = lp.bagGridX, lp.bagGridY
    if mx >= bx and mx < bx + inv.width * cs
    and my >= by and my < by + inv.height * cs then
        local col = math.floor((mx - bx) / cs) + 1
        local row = math.floor((my - by) / cs) + 1
        local entry = Inventory.HitTest(inv, col, row)
        if entry then
            return { action="bagItem", id=entry.id, itype=entry.itype,
                     slot=entry.slot, name=entry.name, entry=entry, srcInv="bag" }
        end
        return { action="panelBg" }
    end

    return { action="panelBg" }
end

-- ============================================================================
-- 计算搜索面板的布局参数（供渲染和命中测试共用）
-- 返回: { container={cellSize,gridX,gridY,w,h}, player={...},
--          takeAllBtn={x,y,w,h}, panelX,panelY,panelW,panelH }
-- ============================================================================
function M.GetSearchPanelLayout(ss, playerInv, sw, sh)
    local cInv = ss.containerInv
    if not cInv then return nil end
    local pInv = playerInv
    local CELL    = 34
    local PADDING = 16
    local TITLE_H = 30   -- 顶部标题栏高度
    local LABEL_H = 18   -- 左右标签行高
    local BTN_H   = 26
    local MID_GAP = 20   -- 两列间隔

    local playW = pInv.width  * CELL
    local playH = pInv.height * CELL
    local contW = cInv.width  * CELL
    local contH = cInv.height * CELL

    local colH = math.max(playH, contH)  -- 两列取最高者

    -- 面板总宽 = 左列 + 间隔 + 右列 + 两侧 padding
    local PW = PADDING + playW + MID_GAP + contW + PADDING
    -- 面板总高 = 标题 + 标签 + 格子 + 按钮 + padding
    local PH = TITLE_H + LABEL_H + colH + BTN_H + PADDING * 2

    local panX = math.floor((sw - PW) / 2)
    local panY = math.floor((sh - PH) / 2)

    -- 左列（玩家背包）
    local pGridX = panX + PADDING
    local pGridY = panY + TITLE_H + LABEL_H

    -- 右列（容器）
    local cGridX = panX + PADDING + playW + MID_GAP
    local cGridY = panY + TITLE_H + LABEL_H

    -- 底部按钮区：左列下方放"智能拾取"，右列下方放"全部取走"
    local btnY = panY + PH - BTN_H - PADDING
    -- 智能拾取按钮（左列居中）
    local alBtnW = math.min(playW, 96)
    local alBtnX = pGridX + (playW - alBtnW) / 2
    -- 全部取走按钮（右列居中）
    local taBtnW = math.min(contW, 96)
    local taBtnX = cGridX + (contW - taBtnW) / 2

    -- 关闭按钮（标题栏右上角，手机端专用）
    local closeBtn = { x=panX+PW-28, y=panY+2, w=26, h=26 }

    return {
        panelX = panX, panelY = panY, panelW = PW, panelH = PH,
        player     = { cellSize=CELL, gridX=pGridX, gridY=pGridY, w=pInv.width,  h=pInv.height },
        container  = { cellSize=CELL, gridX=cGridX, gridY=cGridY, w=cInv.width,  h=cInv.height },
        takeAllBtn  = { x=taBtnX, y=btnY, w=taBtnW, h=BTN_H },
        autoLootBtn = { x=alBtnX, y=btnY, w=alBtnW, h=BTN_H },
        closeBtn   = closeBtn,
        -- 用于渲染标签
        _playW = playW, _contW = contW,
        _labelY = panY + TITLE_H + LABEL_H/2,
    }
end

-- ============================================================================
-- 搜索双面板（搜索完成后显示）
-- ss         : Search 状态对象
-- playerInv  : 玩家的 GridInventory
-- layout     : GetSearchPanelLayout 返回值（避免每帧重算）
-- ============================================================================
function M.DrawSearchPanel(ctx, ss, playerInv, layout, sw, sh, time, notification)
    if not ss.isOpen or not layout then return end
    time = time or 0
    local cInv = ss.containerInv
    local pInv = playerInv

    local lp = layout
    local panX, panY, PW, PH = lp.panelX, lp.panelY, lp.panelW, lp.panelH

    -- 配色
    local C_BG     = nvgRGBA(12,17,22,250)
    local C_BORDER = nvgRGBA(0,240,255,55)
    local C_TITLE  = nvgRGBA(0,240,255,230)
    local C_DIM    = nvgRGBA(0,200,220,160)

    -- 半透明遮罩
    nvgBeginPath(ctx) nvgRect(ctx,0,0,sw,sh)
    nvgFillColor(ctx,nvgRGBA(0,0,0,160)) nvgFill(ctx)

    -- 面板背景（像素风）
    PixelUI.DrawPanel(ctx, panX, panY, PW, PH, {
        bg = {12,17,22,250}, borderColor = {0,240,255,55}, noiseAlpha = 8
    })

    -- 标题栏底色
    nvgBeginPath(ctx) nvgRect(ctx,panX,panY,PW,30)
    nvgFillColor(ctx,nvgRGBA(15,22,28,235)) nvgFill(ctx)

    -- 标题（居中）
    local cname = ss.container and ss.container.name or "容器"
    nvgFontFace(ctx,"sans") nvgFontSize(ctx,14)
    nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx,C_TITLE)
    nvgText(ctx, panX+PW/2, panY+15, "🔍 "..cname, nil)

    -- 分割线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, panX+12, panY+lp._labelY - 4)
    nvgLineTo(ctx, panX+PW-12, panY+lp._labelY - 4)
    nvgStrokeColor(ctx,C_BORDER) nvgStrokeWidth(ctx,0.8) nvgStroke(ctx)

    -- ---- 左列标签：你的背包 ----
    local pl = lp.player
    nvgFontSize(ctx,11) nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx,nvgRGBA(78,204,163,200))   -- 绿色 #4ecca3
    nvgText(ctx, pl.gridX + lp._playW/2, lp._labelY, "你的背包", nil)

    -- ---- 右列标签：容器名 ----
    local cl = lp.container
    nvgFontSize(ctx,11)
    nvgFillColor(ctx,nvgRGBA(0,220,240,200))     -- 青蓝
    nvgText(ctx, cl.gridX + lp._contW/2, lp._labelY, "容器物品", nil)

    -- 中间竖分割线
    local midX = cl.gridX - 10
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, midX, panY + 32)
    nvgLineTo(ctx, midX, panY + PH - 12)
    nvgStrokeColor(ctx,C_BORDER) nvgStrokeWidth(ctx,0.8) nvgStroke(ctx)

    -- ---- 左列：玩家背包网格 ----
    DrawGrid(ctx, pInv, pl.gridX, pl.gridY, pl.cellSize)

    -- ---- 右列：容器网格（加载中时 cInv 可能为 nil，跳过绘制）----
    if cInv then
        DrawGrid(ctx, cInv, cl.gridX, cl.gridY, cl.cellSize)
    end

    -- 加载中提示（在未填充的格子内显示小旋转弧）
    if ss.isSearching then
        local loadedCnt = ss.containerInv and #ss.containerInv.items or 0
        local pendingCnt = #(ss.pendingItems or {})
        local totalCnt = loadedCnt + pendingCnt
        local cs = cl.cellSize
        -- 遍历格子，已加载的跳过，未加载的画加载动画
        local slotIdx = 0
        for row = 0, cl.h - 1 do
            for col = 0, cl.w - 1 do
                slotIdx = slotIdx + 1
                if slotIdx > loadedCnt and slotIdx <= totalCnt then
                    local cellX = cl.gridX + col * cs
                    local cellY = cl.gridY + row * cs
                    -- 格子暗色蒙层
                    nvgBeginPath(ctx)
                    nvgRect(ctx, cellX + 1, cellY + 1, cs - 2, cs - 2)
                    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 50))
                    nvgFill(ctx)
                    -- 小旋转弧（每个格子相位错开）
                    local ccx = cellX + cs / 2
                    local ccy = cellY + cs / 2
                    local R = cs * 0.22
                    local phase = slotIdx * 0.7
                    local angle = time * 4.0 + phase
                    local arcLen = math.pi * 1.0
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, ccx, ccy, R)
                    nvgStrokeColor(ctx, nvgRGBA(60, 80, 140, 80))
                    nvgStrokeWidth(ctx, 1.5)
                    nvgStroke(ctx)
                    nvgBeginPath(ctx)
                    nvgArc(ctx, ccx, ccy, R, angle, angle + arcLen, NVG_CW)
                    nvgStrokeColor(ctx, nvgRGBA(120, 200, 255, 200))
                    nvgStrokeWidth(ctx, 1.5)
                    nvgStroke(ctx)
                end
            end
        end
    end

    -- ---- 智能拾取按钮（像素硬边，青绿色）----
    local alBtn = lp.autoLootBtn
    if alBtn then
        nvgBeginPath(ctx) nvgRect(ctx,alBtn.x,alBtn.y,alBtn.w,alBtn.h)
        nvgFillColor(ctx,nvgRGBA(5,30,22,210)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRect(ctx,alBtn.x,alBtn.y,alBtn.w,alBtn.h)
        nvgStrokeColor(ctx,nvgRGBA(78,204,163,220)) nvgStrokeWidth(ctx,1.2) nvgStroke(ctx)
        nvgFontSize(ctx,11) nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx,nvgRGBA(78,204,163,245))
        nvgText(ctx, alBtn.x+alBtn.w/2, alBtn.y+alBtn.h/2, "⚡智能拾取", nil)
    end

    -- ---- 取全部按钮（像素硬边，红色）----
    local btn = lp.takeAllBtn
    nvgBeginPath(ctx) nvgRect(ctx,btn.x,btn.y,btn.w,btn.h)
    nvgFillColor(ctx,nvgRGBA(50,10,20,200)) nvgFill(ctx)
    nvgBeginPath(ctx) nvgRect(ctx,btn.x,btn.y,btn.w,btn.h)
    nvgStrokeColor(ctx,nvgRGBA(255,107,107,200)) nvgStrokeWidth(ctx,1.2) nvgStroke(ctx)
    nvgFontSize(ctx,11) nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx,nvgRGBA(255,107,107,240))
    nvgText(ctx, btn.x+btn.w/2, btn.y+btn.h/2, "全部取走", nil)

    -- ---- 关闭按钮（像素硬边）----
    local cb = lp.closeBtn
    if cb then
        nvgBeginPath(ctx) nvgRect(ctx, cb.x, cb.y, cb.w, cb.h)
        nvgFillColor(ctx, nvgRGBA(40,12,12,200)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRect(ctx, cb.x, cb.y, cb.w, cb.h)
        nvgStrokeColor(ctx, nvgRGBA(220,80,80,160)) nvgStrokeWidth(ctx,1) nvgStroke(ctx)
        nvgFontFace(ctx,"bold") nvgFontSize(ctx,14)
        nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx,nvgRGBA(240,100,100,230))
        nvgText(ctx, cb.x+cb.w/2, cb.y+cb.h/2, "×", nil)
    end

    -- ---- ESC 提示（PC 端） ----
    nvgFontSize(ctx,10) nvgTextAlign(ctx,NVG_ALIGN_RIGHT+NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx,nvgRGBA(100,105,140,140))
    nvgText(ctx, panX+PW-10, panY+PH-6, "E / ESC 关闭", nil)

    -- ---- 通知 Toast（背包已满 / 取走物品）----
    if notification and notification.timer and notification.timer > 0 then
        local alpha   = math.min(1, notification.timer / 0.4)  -- 0.4s 淡出
        local a255    = math.floor(alpha * 220)
        local isFull  = notification.text == "背包已满！"
        local tr, tg, tb = 230, 255, 235     -- 绿色（取走成功）
        if isFull then tr, tg, tb = 255, 100, 80 end  -- 红色（背包满）

        local tw  = 130
        local th  = 24
        local tx  = panX + PW/2 - tw/2
        local ty  = panY - th - 8

        -- 背景（像素硬边）
        nvgBeginPath(ctx) nvgRect(ctx, tx, ty, tw, th)
        nvgFillColor(ctx, nvgRGBA(10,14,28, math.floor(alpha*200))) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRect(ctx, tx, ty, tw, th)
        nvgStrokeColor(ctx, nvgRGBA(tr,tg,tb, a255)) nvgStrokeWidth(ctx,1.2) nvgStroke(ctx)

        -- 文字
        nvgFontSize(ctx,12) nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(tr,tg,tb, a255))
        nvgText(ctx, tx+tw/2, ty+th/2, notification.text, nil)
    end
end

-- ============================================================================
-- 尸体（可搜索标记）
-- ============================================================================
function M.DrawCorpses(ctx, camX, camY, time, visibleRooms)
    local corpses = World.GetCorpses and World.GetCorpses() or {}
    for _, c in ipairs(corpses) do
        if not c.looted then
            -- 视野过滤
            if visibleRooms and not World.IsPositionVisible(c.x, c.y, visibleRooms) then
                goto continue_corpse
            end
            local sx = c.x - camX
            local sy = c.y - camY
            -- 闪烁光晕
            local pulse = (math.sin(time*2.5)+1)*0.5
            local glowAlpha = math.floor(30 + pulse*50)
            nvgBeginPath(ctx) nvgCircle(ctx,sx,sy,18)
            nvgFillColor(ctx,nvgRGBA(180,60,60,glowAlpha)) nvgFill(ctx)

            -- 尸体图标
            nvgFontFace(ctx,"sans") nvgFontSize(ctx,16)
            nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx,nvgRGBA(200,80,80,220))
            nvgText(ctx,sx,sy, c.isBoss and "💀" or "🐱", nil)

            -- 名称+提示（近距时更亮）
            nvgFontSize(ctx,9)
            nvgFillColor(ctx,nvgRGBA(240,160,160,180))
            nvgText(ctx,sx,sy+18, c.name or "尸体", nil)
            ::continue_corpse::
        end
    end
end

-- ============================================================================
-- 撤离/继续 选择面板
-- hoveredBtn: "evacuate" | "continue" | nil
-- ============================================================================
function M.DrawExtractChoice(ctx, player, currentFloor, sw, sh, hoveredBtn)
    -- ── 全屏遮罩 ────────────────────────────────────────────────
    nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, sh)
    local maskG = nvgLinearGradient(ctx, 0, 0, 0, sh,
        nvgRGBA(5, 8, 12, 185), nvgRGBA(8, 14, 20, 210))
    nvgFillPaint(ctx, maskG) nvgFill(ctx)

    -- ── 面板（像素风） ────────────────────────────────────────────
    local PW, PH = 500, 310
    local px = math.floor((sw - PW) / 2)
    local py = math.floor((sh - PH) / 2)

    PixelUI.DrawPanel(ctx, px, py, PW, PH, {
        bg = {10,16,22,248}, border = {78,204,163,140}, noiseAlpha = 8
    })

    -- ── 标题 ────────────────────────────────────────────────────
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 22)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(78, 204, 163, 255))
    nvgText(ctx, px + PW/2, py + 36, "🚁 到达撤离点！", nil)

    -- 统计信息
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 12)
    nvgFillColor(ctx, nvgRGBA(0, 200, 220, 180))
    local floorStatStr = string.format("第 %d 层  ·  击杀 %d 只  ·  物资  %d",
        currentFloor, player.kills or 0, player.lootValue or 0)
    nvgText(ctx, px + PW/2, py + 64, floorStatStr, nil)
    local floorStatHalf = nvgTextBounds(ctx, 0, 0, floorStatStr) / 2
    local floorMoneyPre = nvgTextBounds(ctx, 0, 0, string.format("第 %d 层  ·  击杀 %d 只  ·  物资 ", currentFloor, player.kills or 0))
    drawMoneyIcon(ctx, px + PW/2 - floorStatHalf + floorMoneyPre - 2, py + 64, 12)

    -- 分割线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, px + 30, py + 82) nvgLineTo(ctx, px + PW - 30, py + 82)
    nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, 20)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)

    -- ── 两个选择按钮 ────────────────────────────────────────────
    local btnW, btnH = 200, 80
    local gap = 20
    local totalBW = btnW * 2 + gap
    local btn1X = px + (PW - totalBW) / 2
    local btn2X = btn1X + btnW + gap
    local btnY  = py + 102

    -- 辅助：绘制选择按钮（像素风）
    local function drawChoiceBtn(bx, by, bw, bh, icon, title, sub, isH, cr, cg, cb)
        -- 像素风按钮背景
        PixelUI.DrawPanel(ctx, bx, by, bw, bh, {
            bg = {10, 16, 22, isH and 248 or 210},
            borderColor = {cr, cg, cb, isH and 220 or 70},
            shadow = isH,
            noiseAlpha = isH and 12 or 6,
            highlight = isH,
        })
        -- 悬停顶部彩条（像素风：2px硬边）
        if isH then
            nvgBeginPath(ctx) nvgRect(ctx, bx + 1, by + 1, bw - 2, 2)
            nvgFillColor(ctx, nvgRGBA(cr, cg, cb, 180)) nvgFill(ctx)
        end
        -- 图标
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 26)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
        nvgText(ctx, bx + bw/2, by + 24, icon, nil)
        -- 主标题
        nvgFontFace(ctx, "bold") nvgFontSize(ctx, 15)
        nvgFillColor(ctx, nvgRGBA(cr, cg, cb, isH and 255 or 200))
        nvgText(ctx, bx + bw/2, by + 50, title, nil)
        -- 副标题
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
        nvgFillColor(ctx, nvgRGBA(cr, cg, cb, isH and 180 or 110))
        nvgText(ctx, bx + bw/2, by + 67, sub, nil)
    end

    local ev = (hoveredBtn == "evacuate")
    local co = (hoveredBtn == "continue")
    drawChoiceBtn(btn1X, btnY, btnW, btnH,
        "🚁", "立即撤离", "带走全部物资安全撤出",
        ev, 78, 204, 163)
    drawChoiceBtn(btn2X, btnY, btnW, btnH,
        "⚔️", "继续深入", string.format("挑战第 %d 层", currentFloor + 1),
        co, 243, 156, 18)

    -- ── 底部提示 ─────────────────────────────────────────────────
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0, 160, 180, 100))
    nvgText(ctx, px + PW/2, py + PH - 16, "撤离后物资永久保留  |  阵亡则失去一切", nil)
end

-- 命中测试：返回 "evacuate" / "continue" / nil
function M.GetExtractChoiceHover(mx, my, sw, sh)
    local PW, PH = 480, 300
    local px = math.floor((sw-PW)/2)
    local py = math.floor((sh-PH)/2)
    local btnW, btnH = 190, 72
    local gap = 20
    local totalBW = btnW*2 + gap
    local btn1X = px + (PW - totalBW)/2
    local btn2X = btn1X + btnW + gap
    local btnY  = py + 110
    if mx >= btn1X and mx <= btn1X+btnW and my >= btnY and my <= btnY+btnH then
        return "evacuate"
    end
    if mx >= btn2X and mx <= btn2X+btnW and my >= btnY and my <= btnY+btnH then
        return "continue"
    end
    return nil
end

-- ============================================================================
-- 深入确认对话框（第15层 → 16-19层无法撤退警告）
-- ============================================================================

-- 共享布局常量
local DC_PW, DC_PH = 420, 240
local DC_BTN_W, DC_BTN_H = 140, 50
local DC_BTN_GAP = 30

local function getDCLayout(sw, sh)
    local px = math.floor((sw - DC_PW) / 2)
    local py = math.floor((sh - DC_PH) / 2)
    local totalBW = DC_BTN_W * 2 + DC_BTN_GAP
    local btn1X = px + (DC_PW - totalBW) / 2
    local btn2X = btn1X + DC_BTN_W + DC_BTN_GAP
    local btnY = py + DC_PH - 72
    return px, py, btn1X, btn2X, btnY
end

function M.DrawDeepConfirm(ctx, sw, sh, mx, my, floor)
    floor = floor or 15  -- 兼容旧调用
    -- 全屏遮罩
    nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, sh)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 200)) nvgFill(ctx)

    local px, py, btn1X, btn2X, btnY = getDCLayout(sw, sh)

    -- 面板主体（像素风）
    PixelUI.DrawPanel(ctx, px, py, DC_PW, DC_PH, {
        bg = {15, 12, 18, 250},
        borderColor = {255, 70, 50, 90},
        noiseAlpha = 10,
    })
    -- 顶部红色警告条（像素风硬边）
    nvgBeginPath(ctx) nvgRect(ctx, px + 1, py + 1, DC_PW - 2, 3)
    nvgFillColor(ctx, nvgRGBA(255, 70, 50, 200)) nvgFill(ctx)

    -- 标题
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 20)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 80, 60, 255))
    nvgText(ctx, px + DC_PW/2, py + 32, "⚠️ 深入警告", nil)

    -- 正文（根据当前层数动态提示下次撤离机会）
    local nextBoss = (math.floor(floor / 5) + 1) * 5  -- 下一个Boss层
    if nextBoss > 20 then nextBoss = 20 end
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 14)
    nvgFillColor(ctx, nvgRGBA(255, 220, 200, 220))
    nvgText(ctx, px + DC_PW/2, py + 68,
        string.format("继续深入后，直到第 %d 层Boss才能撤离", nextBoss), nil)
    nvgText(ctx, px + DC_PW/2, py + 92,
        string.format("第 %d ~ %d 层将无法中途撤退", floor + 1, nextBoss - 1), nil)

    nvgFontSize(ctx, 12)
    nvgFillColor(ctx, nvgRGBA(255, 160, 140, 150))
    nvgText(ctx, px + DC_PW/2, py + 118, "阵亡将失去一切物资，请谨慎抉择！", nil)

    -- 按钮悬停检测
    local hoverConfirm = (mx >= btn1X and mx <= btn1X + DC_BTN_W and my >= btnY and my <= btnY + DC_BTN_H)
    local hoverCancel = (mx >= btn2X and mx <= btn2X + DC_BTN_W and my >= btnY and my <= btnY + DC_BTN_H)

    -- 确认按钮（红色 - 像素风）
    PixelUI.DrawPanel(ctx, btn1X, btnY, DC_BTN_W, DC_BTN_H, {
        bg = hoverConfirm and {200, 50, 40, 240} or {140, 35, 30, 200},
        borderColor = {255, 80, 60, hoverConfirm and 255 or 120},
        shadow = true, noiseAlpha = 10, highlight = hoverConfirm,
    })
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 15)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 240))
    nvgText(ctx, btn1X + DC_BTN_W/2, btnY + DC_BTN_H/2, "确认深入", nil)

    -- 取消按钮（灰绿色 - 像素风）
    PixelUI.DrawPanel(ctx, btn2X, btnY, DC_BTN_W, DC_BTN_H, {
        bg = hoverCancel and {50, 140, 100, 220} or {35, 90, 70, 180},
        borderColor = {78, 204, 163, hoverCancel and 255 or 100},
        shadow = true, noiseAlpha = 10, highlight = hoverCancel,
    })
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 15)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 240))
    nvgText(ctx, btn2X + DC_BTN_W/2, btnY + DC_BTN_H/2, "返回", nil)
end

function M.GetDeepConfirmHover(mx, my, sw, sh)
    local _, _, btn1X, btn2X, btnY = getDCLayout(sw, sh)
    if mx >= btn1X and mx <= btn1X + DC_BTN_W and my >= btnY and my <= btnY + DC_BTN_H then
        return "confirm"
    end
    if mx >= btn2X and mx <= btn2X + DC_BTN_W and my >= btnY and my <= btnY + DC_BTN_H then
        return "cancel"
    end
    return nil
end

-- ============================================================================
-- 菜单
-- ============================================================================
-- 主菜单左下角按钮布局常量（供 DrawMenu 和 HitTestMenu 共用）
local MENU_BTNS = {
    { key="start",  label="开始探险" },
    { key="volume", label="音量设置" },
    { key="howto",  label="玩法介绍" },
}
local MENU_BTN_W  = 180
local MENU_BTN_H  = 44
local MENU_BTN_GAP = 12
local MENU_BTN_X  = 36
-- 按钮组底部距屏幕底部的距离
local MENU_BTN_BOTTOM = 40

function M.GetMenuBtnRects(sw, sh)
    local rects = {}
    local totalH = #MENU_BTNS * MENU_BTN_H + (#MENU_BTNS - 1) * MENU_BTN_GAP
    local baseY  = sh - MENU_BTN_BOTTOM - totalH
    for i, btn in ipairs(MENU_BTNS) do
        local y = baseY + (i - 1) * (MENU_BTN_H + MENU_BTN_GAP)
        rects[i] = { key=btn.key, label=btn.label,
                     x=MENU_BTN_X, y=y, w=MENU_BTN_W, h=MENU_BTN_H }
    end
    return rects
end

function M.HitTestMenu(mx, my, sw, sh)
    local rects = M.GetMenuBtnRects(sw, sh)
    for _, r in ipairs(rects) do
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            return r.key
        end
    end
    return nil
end

function M.DrawMenu(ctx, sw, sh, time, menuHover)
    -- ── 背景：宣传图全屏铺满 ─────────────────────────────────────
    local img = nvgCreateImage(ctx, "image/PROMO_2026-05-26T11-43-14_01.jpg", 0)
    if img and img > 0 then
        local imgPaint = nvgImagePattern(ctx, 0, 0, sw, sh, 0, img, 1.0)
        nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, sh)
        nvgFillPaint(ctx, imgPaint) nvgFill(ctx)
    else
        -- 回退深色背景
        nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, sh)
        nvgFillColor(ctx, nvgRGBA(8, 12, 16, 255)) nvgFill(ctx)
    end

    -- 底部渐变遮罩（让按钮区域可读）
    local maskH = sh * 0.5
    local maskGrad = nvgLinearGradient(ctx, 0, sh - maskH, 0, sh,
        nvgRGBA(0,0,0,0), nvgRGBA(0,0,0,210))
    nvgBeginPath(ctx) nvgRect(ctx, 0, sh - maskH, sw, maskH)
    nvgFillPaint(ctx, maskGrad) nvgFill(ctx)

    -- ── 左下角三个按钮 ────────────────────────────────────────────
    local rects = M.GetMenuBtnRects(sw, sh)
    nvgFontFace(ctx, "bold")
    nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    for _, r in ipairs(rects) do
        local hovered = (menuHover == r.key)
        local state = hovered and "hover" or "normal"
        -- 像素风按钮
        PixelUI.DrawButton(ctx, r.x, r.y, r.w, r.h, state, {
            bg = {20, 20, 20, 210},
            bg_hover = {255, 200, 60, 230},
            accentLeft = true,
            accentColor = hovered and {255, 240, 80, 255} or {200, 160, 40, 180},
            borderColor = hovered and {255, 230, 120, 255} or {180, 140, 50, 160},
        })
        -- 文字
        if hovered then
            nvgFillColor(ctx, nvgRGBA(20, 14, 0, 255))
        else
            nvgFillColor(ctx, nvgRGBA(240, 220, 160, 255))
        end
        nvgText(ctx, r.x + 16, r.y + r.h * 0.5, r.label, nil)
    end

    -- 版本号（右下角小字）
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
    nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, nvgRGBA(200, 180, 100, 120))
    nvgText(ctx, sw - 10, sh - 8, "猫咪枪手地牢 v0.1", nil)
end

-- 玩法介绍内容总高度（用于滚动限制）
local HOWTO_CONTENT_H = 0  -- 渲染后更新

function M.GetHowToMaxScroll(sw, sh)
    local panelH = math.min(480, sh - 40)
    local contentArea = panelH - 60 - 36  -- 标题区 + 底部提示
    return math.max(0, HOWTO_CONTENT_H - contentArea)
end

-- 玩法介绍覆盖层（在 menu 状态下叠加显示）
function M.DrawHowToPlay(ctx, sw, sh, scrollY, mobile)
    scrollY = scrollY or 0
    -- 半透明全屏遮罩
    nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, sh)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 200)) nvgFill(ctx)

    local panelW = math.min(540, sw - 30)
    local panelH = math.min(480, sh - 40)
    local px = (sw - panelW) / 2
    local py = (sh - panelH) / 2

    -- 面板背景
    PixelUI.DrawPanel(ctx, px, py, panelW, panelH, {
        bg = {14, 18, 22, 245},
        borderColor = {200, 160, 40, 160},
        noiseAlpha = 14,
    })
    -- 左侧黄色竖条装饰
    nvgBeginPath(ctx) nvgRect(ctx, px, py, 3, panelH)
    nvgFillColor(ctx, nvgRGBA(255, 210, 60, 220)) nvgFill(ctx)

    -- 标题（固定不滚动）
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 18)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 220, 80, 255))
    nvgText(ctx, px + panelW/2, py + 24, "玩法介绍", nil)

    -- 内容区域（可滚动）
    local contentTop = py + 50
    local contentBot = py + panelH - 36
    local contentH = contentBot - contentTop

    -- 裁剪区域
    nvgSave(ctx)
    nvgScissor(ctx, px, contentTop, panelW, contentH)

    -- 构建内容行
    local LH = 20   -- 行高
    local SH2 = 28  -- 分组标题行高
    local rows = {}

    -- === 游戏目标 ===
    table.insert(rows, { type="header", text="游戏目标" })
    table.insert(rows, { icon="⭐", text="搜刮箱子获得战利品，装备越好护甲越高", color=nvgRGBA(255,215,80,210) })
    table.insert(rows, { icon="🚪", text="到达地图南边绿色出口，撤离带走战利品", color=nvgRGBA(100,255,140,210) })
    table.insert(rows, { icon="💀", text="阵亡失去本局全部战利品，谨慎行事！", color=nvgRGBA(255,100,100,220) })
    table.insert(rows, { icon="🏆", text="每5层出现小Boss，第20层决战最终Boss", color=nvgRGBA(255,185,60,210) })

    -- === 电脑版操作 ===
    table.insert(rows, { type="header", text="电脑版操作" })
    table.insert(rows, { icon="🎮", text="W/A/S/D — 上/左/下/右 移动", color=nvgRGBA(180,230,255,230) })
    table.insert(rows, { icon="🖱", text="鼠标移动 — 瞄准方向", color=nvgRGBA(180,230,255,230) })
    table.insert(rows, { icon="💥", text="鼠标左键 — 射击", color=nvgRGBA(180,230,255,230) })
    table.insert(rows, { icon="🔍", text="E — 搜索箱子 / 进入撤离出口", color=nvgRGBA(180,230,255,230) })
    table.insert(rows, { icon="🔄", text="R — 换弹", color=nvgRGBA(180,230,255,230) })
    table.insert(rows, { icon="🎒", text="TAB — 打开/关闭背包", color=nvgRGBA(180,230,255,230) })
    table.insert(rows, { icon="🔫", text="Q — 切换主副武器", color=nvgRGBA(180,230,255,230) })
    table.insert(rows, { icon="⏸", text="ESC — 暂停菜单", color=nvgRGBA(180,230,255,230) })

    -- === 手机版操作 ===
    table.insert(rows, { type="header", text="手机版操作" })
    table.insert(rows, { icon="🕹", text="左侧虚拟摇杆 — 移动", color=nvgRGBA(180,255,200,230) })
    table.insert(rows, { icon="💥", text="射击按钮(右下) — 射击（自动瞄准最近敌人）", color=nvgRGBA(180,255,200,230) })
    table.insert(rows, { icon="🔄", text="换弹按钮(右侧) — 换弹", color=nvgRGBA(180,255,200,230) })
    table.insert(rows, { icon="🔍", text="互动按钮(右侧) — 搜索/撤离", color=nvgRGBA(180,255,200,230) })
    table.insert(rows, { icon="🎒", text="背包按钮(右上) — 打开背包", color=nvgRGBA(180,255,200,230) })
    table.insert(rows, { icon="🔫", text="切枪按钮(右侧) — 切换武器", color=nvgRGBA(180,255,200,230) })

    -- === 物品操作 ===
    table.insert(rows, { type="header", text="物品操作" })
    table.insert(rows, { icon="👆", text="电脑：单击拾起/装备，右键查看信息", color=nvgRGBA(220,200,255,230) })
    table.insert(rows, { icon="📱", text="手机：单击查看物品信息，双击拾起或丢弃", color=nvgRGBA(220,200,255,230) })
    table.insert(rows, { icon="↔", text="背包内拖拽可交换物品位置", color=nvgRGBA(220,200,255,230) })

    -- === 战备处 ===
    table.insert(rows, { type="header", text="战备处（出发前）" })
    table.insert(rows, { icon="🛒", text="购买：从商人处购买武器和装备", color=nvgRGBA(200,220,255,220) })
    table.insert(rows, { icon="💰", text="出售：将多余物品卖给商人换钱", color=nvgRGBA(200,220,255,220) })
    table.insert(rows, { icon="📦", text="装配：拖拽装备到装备栏出战", color=nvgRGBA(200,220,255,220) })
    table.insert(rows, { icon="▶", text="出发：准备好后点击出发进入战斗", color=nvgRGBA(200,220,255,220) })

    -- 计算总内容高度
    local totalH = 8  -- 顶部间距
    for _, row in ipairs(rows) do
        if row.type == "header" then
            totalH = totalH + SH2
        else
            totalH = totalH + LH
        end
    end
    totalH = totalH + 8  -- 底部间距
    HOWTO_CONTENT_H = totalH

    -- 绘制内容
    local curY = contentTop + 8 - scrollY
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    for _, row in ipairs(rows) do
        if row.type == "header" then
            local hy = curY + SH2 * 0.5
            -- 分组标题
            nvgFontFace(ctx, "bold") nvgFontSize(ctx, 13)
            nvgFillColor(ctx, nvgRGBA(255, 200, 50, 240))
            nvgText(ctx, px + 16, hy, "━ " .. row.text .. " ━", nil)
            -- 下划线
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, px + 16, curY + SH2 - 2)
            nvgLineTo(ctx, px + panelW - 16, curY + SH2 - 2)
            nvgStrokeColor(ctx, nvgRGBA(200, 160, 40, 60))
            nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
            curY = curY + SH2
        else
            local ry = curY + LH * 0.5
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, 13)
            nvgFillColor(ctx, nvgRGBA(255, 210, 60, 180))
            nvgText(ctx, px + 18, ry, row.icon, nil)
            nvgFillColor(ctx, row.color)
            nvgText(ctx, px + 42, ry, row.text, nil)
            curY = curY + LH
        end
    end

    nvgRestore(ctx)

    -- 滚动指示器（右侧滚动条）
    local maxScroll = M.GetHowToMaxScroll(sw, sh)
    if maxScroll > 0 then
        local barH = math.max(20, contentH * (contentH / HOWTO_CONTENT_H))
        local barY = contentTop + (scrollY / maxScroll) * (contentH - barH)
        nvgBeginPath(ctx) nvgRect(ctx, px + panelW - 6, barY, 3, barH)
        nvgFillColor(ctx, nvgRGBA(255, 210, 60, 100)) nvgFill(ctx)
    end

    -- 底部提示（固定不滚动）
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(140, 130, 110, 180))
    local hint = mobile and "点击空白关闭 | 上下滑动浏览" or "点击关闭 | 滚轮浏览"
    nvgText(ctx, px + panelW/2, py + panelH - 16, hint, nil)
end

-- ============================================================================
-- 结束/胜利画面
-- ============================================================================
function M.DrawEndScreen(ctx, sw, sh, isWin, player, elapsedTime)
    -- 全屏深色背景
    nvgBeginPath(ctx) nvgRect(ctx,0,0,sw,sh)
    nvgFillColor(ctx,nvgRGBA(10,15,20,240)) nvgFill(ctx)

    -- 中央面板（像素风）
    local PW, PH = 420, 300
    local px = (sw - PW) / 2
    local py = (sh - PH) / 2
    local borderC = isWin and {78,204,163,200} or {255,107,107,200}
    PixelUI.DrawPanel(ctx, px, py, PW, PH, {
        bg = {12, 17, 22, 248},
        borderColor = borderC,
        noiseAlpha = 16,
    })

    nvgFontFace(ctx,"sans")
    nvgTextAlign(ctx,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)

    -- 大标题 + 阴影
    nvgFontSize(ctx,48)
    if isWin then
        -- 撤离成功：绿色发光
        nvgFillColor(ctx,nvgRGBA(0,80,50,120))
        nvgText(ctx,sw/2+3,py+56,"✅ 撤离成功",nil)
        nvgFillColor(ctx,nvgRGBA(78,204,163,255))
        nvgText(ctx,sw/2,py+54,"✅ 撤离成功",nil)
    else
        -- 阵亡：红色发光
        nvgFillColor(ctx,nvgRGBA(100,0,0,120))
        nvgText(ctx,sw/2+3,py+56,"💀 修勾倒下了",nil)
        nvgFillColor(ctx,nvgRGBA(255,107,107,255))
        nvgText(ctx,sw/2,py+54,"💀 修勾倒下了",nil)
    end

    -- 副标题
    nvgFontSize(ctx,16)
    if isWin then
        nvgFillColor(ctx,nvgRGBA(78,204,163,180))
        nvgText(ctx,sw/2,py+88,"汪汪！成功带走了所有战利品！",nil)
    else
        nvgFillColor(ctx,nvgRGBA(255,107,107,180))
        nvgText(ctx,sw/2,py+88,"所有战利品已丢失",nil)
    end

    -- 分割线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx,px+40,py+106) nvgLineTo(ctx,px+PW-40,py+106)
    nvgStrokeColor(ctx,nvgRGBA(0,240,255,45)) nvgStrokeWidth(ctx,1) nvgStroke(ctx)

    -- 统计数据
    nvgFontSize(ctx,18)
    nvgFillColor(ctx,nvgRGBA(208,208,224,220))
    nvgText(ctx,sw/2,py+130, string.format("击杀猫咪：%d 只", player.kills), nil)
    nvgText(ctx,sw/2,py+158,
        string.format("用时：%02d:%02d", math.floor(elapsedTime/60), math.floor(elapsedTime%60)), nil)
    if isWin then
        nvgFillColor(ctx,nvgRGBA(255,215,0,230))
        local totalLootStr = string.format("战利品总价值：  %d", player.lootValue)
        nvgText(ctx,sw/2,py+186, totalLootStr, nil)
        local totalLootTW = nvgTextBounds(ctx, 0, 0, totalLootStr)
        drawMoneyIcon(ctx, sw/2 - totalLootTW/2 + nvgTextBounds(ctx, 0, 0, "战利品总价值：") - 2, py+186, 14)
    end

    -- 继续提示（闪烁）
    nvgFontSize(ctx,15)
    local alpha = math.floor(((math.sin(elapsedTime*2.5)+1)*0.5)*120 + 135)
    nvgFillColor(ctx,nvgRGBA(0,240,255,alpha))
    nvgText(ctx,sw/2,py+PH-26,"点击或按空格/回车进入战前准备",nil)
end

-- ============================================================================
-- 战前准备界面（三栏布局：仓库网格 | 出售/购买面板 | 出战装备）
-- ============================================================================
local Stash = require("Stash")

-- 辅助：绘制通用按钮
local function DrawBtn(ctx, x, y, w, h, label, r, g, b, alpha)
    alpha = alpha or 220
    nvgBeginPath(ctx) nvgRect(ctx, x, y, w, h)
    nvgFillColor(ctx, nvgRGBA(math.floor(r*0.15), math.floor(g*0.15), math.floor(b*0.15), 220))
    nvgFill(ctx)
    nvgBeginPath(ctx) nvgRect(ctx, x, y, w, h)
    nvgStrokeColor(ctx, nvgRGBA(r, g, b, alpha)) nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(r, g, b, alpha))
    nvgText(ctx, x + w/2, y + h/2, label, nil)
end

-- 计算并缓存战前准备界面的布局（避免每帧重算）
-- 返回 layout 表，包含所有可点击区域坐标
function M.GetLoadoutLayout(stash, sw, sh)
    -- ================================================================
    -- 移动端布局（手机横/竖屏，min(sw,sh) < 500）：左仓库 + 右导航栏
    -- 左侧固定显示仓库网格，右侧上方导航栏（商店/背包/装备）
    -- ================================================================
    if math.min(sw, sh) < 500 then
        local TH   = 38   -- 顶部标题栏高度
        local BH   = 50   -- 底部按钮区高度
        local PAD  = 6
        local TABH = 32   -- 右侧导航栏 Tab 高度

        -- 左右面板分割：左侧占 45%，右侧占 55%
        local leftW  = math.floor(sw * 0.45)
        local rightW = sw - leftW

        -- 仓库格子大小（适配左侧面板）
        local contentY = TH + 2
        local contentH = sh - TH - BH - 4
        local maxCellByH = math.floor((contentH - 20) / stash.inv.height)
        local maxCellByW = math.floor((leftW - PAD*2) / stash.inv.width)
        local CELL = math.max(20, math.min(28, maxCellByH, maxCellByW))

        -- 仓库网格（左侧居中）
        local gw    = stash.inv.width  * CELL
        local gh    = stash.inv.height * CELL
        local gridX = PAD + math.floor((leftW - PAD*2 - gw) / 2)
        local gridY = contentY + 16
        local grid  = { x=gridX, y=gridY, w=stash.inv.width, h=stash.inv.height, cellSize=CELL }

        -- 右侧面板区域
        local rightX = leftW
        local rightY = contentY

        -- 右侧导航栏 Tab（商店/背包/装备，各占 1/3）
        local tabW = math.floor(rightW / 3)
        local sectionTabs = {
            { key="shop",   label="商店", x=rightX,          y=rightY, w=tabW,           h=TABH },
            { key="bag",    label="背包", x=rightX+tabW,     y=rightY, w=tabW,           h=TABH },
            { key="equip",  label="装备", x=rightX+tabW*2,   y=rightY, w=rightW-tabW*2,  h=TABH },
        }

        -- 右侧内容区
        local rContentY = rightY + TABH + 4
        local rContentH = contentH - TABH - 4

        -- 底部按钮（出发/返回）
        local btnH    = BH - 14
        local btnY    = sh - BH + 5
        local backBtn  = { x=PAD,              y=btnY, w=math.floor(sw*0.3)-PAD, h=btnH }
        local startBtn = { x=math.floor(sw*0.3)+PAD, y=btnY, w=sw-math.floor(sw*0.3)-PAD*2, h=btnH }

        -- 出售/购买子 Tab 高度
        local subTabH = 28
        -- 子 Tab 下方内容区起点（出售列表 / 商人按钮 从这里开始）
        local subContentY = rContentY + subTabH + 4
        local subContentH = rContentH - subTabH - 4

        -- 商店 Tab：全部出售 / 多选出售按钮
        local shopBtnH = 30
        local shopBtnW = math.floor((rightW - PAD*3) / 2)
        local shopBtnY = rContentY + rContentH - shopBtnH - 2
        local sellAllBtn     = { x=rightX+PAD,             y=shopBtnY, w=shopBtnW, h=shopBtnH }
        local multiSellBtn   = { x=rightX+PAD*2+shopBtnW,  y=shopBtnY, w=shopBtnW, h=shopBtnH }
        -- 确认出售按钮（多选模式下显示）
        local confirmSellBtn = { x=rightX+PAD, y=shopBtnY, w=rightW-PAD*2, h=shopBtnH }

        -- 商店 Tab：待售列表区域（在子 Tab 下方）
        local sellListY0 = subContentY + 4
        local sellListH  = shopBtnY - sellListY0 - 6

        -- 商人选择按钮（商店 Tab 购买子模式，在子 Tab 下方）
        local vendorBtnW = math.floor((rightW - PAD*2) / 4)
        local vendorBtnH2 = 28
        local vendorBtns = {}
        for i, v in ipairs(Stash.VENDORS) do
            vendorBtns[i] = {
                x = rightX + PAD + (i-1)*(vendorBtnW+1),
                y = subContentY,
                w = vendorBtnW - 1,
                h = vendorBtnH2,
                vendorId = v.id,
            }
        end

        -- 购买列表（商人按钮下方）
        local buyListY0  = subContentY + vendorBtnH2 + 6
        local buyListH2  = subContentH - vendorBtnH2 - shopBtnH - 16
        local buyScrollW = 6

        -- 背包 Tab：出战装备列表（可拖入）
        local equipListY0 = rContentY + 4
        local equipRowH   = 30

        -- 装备 Tab：装备槽区域
        local slotSize = math.min(math.floor((rightW - PAD*4) / 3), math.floor((rContentH - 30) / 2))
        slotSize = math.max(32, math.min(48, slotSize))

        return {
            isMobile    = true,
            panelX      = 0,  panelY    = 0,
            panelW      = sw, panelH    = sh,
            cell        = CELL, pad     = PAD,
            titleH      = TH,
            -- 左右分割
            leftW       = leftW,
            rightX      = rightX,
            rightW      = rightW,
            -- 导航栏
            sectionTabs = sectionTabs,
            tabH        = TABH,
            -- 全局内容区
            contentY    = contentY,
            contentH    = contentH,
            -- 右侧内容区
            rContentY   = rContentY,
            rContentH   = rContentH,
            -- 底部
            startBtn    = startBtn,
            backBtn     = backBtn,
            -- 仓库（左侧固定）
            grid        = grid,
            -- 商店 Tab
            sellAllBtn     = sellAllBtn,
            multiSellBtn   = multiSellBtn,
            confirmSellBtn = confirmSellBtn,
            sellListY0  = sellListY0,
            sellListH   = sellListH,
            vendorBtns  = vendorBtns,
            vendorBtnH  = vendorBtnH2,
            buyListY0   = buyListY0,
            buyListH    = buyListH2,
            buyScrollW  = buyScrollW,
            -- 背包 Tab
            equipListY0 = equipListY0,
            equipRowH   = equipRowH,
            -- 装备 Tab
            slotSize    = slotSize,
            -- 兼容字段
            midX = rightX, midY = rContentY, midW = rightW,
            midContentY = subContentY,
            midContentH = subContentH,
            sellZone    = { x=rightX+PAD, y=subContentY, w=rightW-PAD*2, h=40 },
            sellTab     = { x=rightX+PAD, y=rContentY, w=shopBtnW, h=subTabH },
            buyTab      = { x=rightX+PAD+shopBtnW+PAD, y=rContentY, w=shopBtnW, h=subTabH },
            selectAllBtn   = sellAllBtn,
            loadoutZone = { x=rightX+PAD, y=equipListY0, w=rightW-PAD*2, h=rContentH-8 },
        }
    end

    -- ================================================================
    -- PC / 横屏布局（原有逻辑）
    -- ================================================================
    -- 自适应格子大小（根据屏幕高度，24~30px/格）
    local CELL  = math.max(24, math.min(30, math.floor((sh - 160) / 11)))
    local PAD   = 12
    local TH    = 44    -- 顶部标题栏高度（保留给内容起点计算）
    local BH    = 80    -- 底部按钮区高度（足够容纳两个按钮）

    local inv   = stash.inv
    local gw    = inv.width  * CELL   -- 仓库网格像素宽
    local gh    = inv.height * CELL   -- 仓库网格像素高

    -- 三栏宽度
    local leftW  = gw + 2*PAD          -- 左栏（仓库网格）
    local midW   = 250                 -- 中栏（出售/购买面板）
    local rightW = 190                 -- 右栏（出战装备）

    local PW = leftW + midW + rightW
    local PH = TH + math.max(gh, 340) + BH + PAD

    -- 面板完全居中
    local panX = math.floor((sw - PW) / 2)
    local panY = math.floor((sh - PH) / 2)

    -- 左栏：仓库网格起点
    local gridX = panX + PAD
    local gridY = panY + TH + PAD

    -- 中栏起点
    local midX  = panX + leftW
    local midY  = panY + TH

    -- 右栏起点
    local rightX = panX + leftW + midW
    local rightY = panY + TH

    -- 右栏按钮（底部，BH=80 可以容纳两行）
    -- startBtn 底边: panY+PH-80+10+30 = panY+PH-40  ✓ 在面板内
    -- backBtn  底边: panY+PH-80+10+36+24 = panY+PH-10 ✓ 在面板内
    local btnW     = rightW - PAD*2
    local btnBaseY = panY + PH - BH + 10
    local startBtn = { x=rightX+PAD, y=btnBaseY,    w=btnW, h=30 }
    local backBtn  = { x=rightX+PAD, y=btnBaseY+36, w=btnW, h=24 }

    -- 中栏 Tab 按钮（出售 / 购买）
    local tabH   = 28
    local tabW   = math.floor((midW - PAD*3) / 2)
    local sellTab = { x=midX+PAD,          y=midY+8, w=tabW, h=tabH }
    local buyTab  = { x=midX+PAD+tabW+PAD, y=midY+8, w=tabW, h=tabH }

    -- 中栏内容区起点（Tab 下方 8px 间距）
    local midContentY = midY + tabH + 20
    local midContentH = PH - TH - BH - tabH - 20 - PAD

    -- 购买模式商人选择按钮（4个，顶部排列）
    local vendorBtnH = 34
    local vendorBtnW = math.floor((midW - PAD*2) / 4)
    local vendorBtns = {}
    for i, v in ipairs(Stash.VENDORS) do
        vendorBtns[i] = {
            x        = midX + PAD + (i-1)*(vendorBtnW+2),
            y        = midContentY,
            w        = vendorBtnW,
            h        = vendorBtnH,
            vendorId = v.id,
        }
    end

    -- 出售拖拽投放区（中栏内容区顶部）
    local sellZone = {
        x = midX + PAD, y = midContentY,
        w = midW - PAD*2, h = 60,
    }

    -- 出战装备拖拽投放区（右栏，排除标题和底部按钮）
    local loadoutZone = {
        x = rightX + PAD, y = rightY + 28,
        w = rightW - PAD*2,
        h = startBtn.y - (rightY + 28) - 8,
    }

    -- 中栏底部操作按钮（一键全选 + 确认出售）
    local midBtmY   = midContentY + midContentH - 30
    local halfBtnW  = math.floor((midW - PAD*3) / 2)
    local selectAllBtn   = { x = midX + PAD,              y = midBtmY, w = halfBtnW, h = 26 }
    local confirmSellBtn = { x = midX + PAD*2 + halfBtnW, y = midBtmY, w = halfBtnW, h = 26 }

    return {
        panelX = panX, panelY = panY, panelW = PW, panelH = PH,
        screenW = sw, screenH = sh,   -- 保存屏幕尺寸供 HitTest 使用
        cell   = CELL, pad    = PAD,
        titleH = TH,   -- 暴露标题栏高度供渲染层使用
        grid   = { x=gridX, y=gridY, w=inv.width, h=inv.height, cellSize=CELL },
        midX   = midX,   midY   = midY,   midW   = midW,
        rightX = rightX, rightY = rightY, rightW = rightW,
        midContentY = midContentY, midContentH = midContentH,
        sellTab    = sellTab,
        buyTab     = buyTab,
        vendorBtns = vendorBtns,
        vendorBtnH = vendorBtnH,
        startBtn   = startBtn,
        backBtn    = backBtn,
        tabH       = tabH,
        sellZone      = sellZone,
        loadoutZone   = loadoutZone,
        selectAllBtn  = selectAllBtn,
        confirmSellBtn = confirmSellBtn,
        -- 购买面板商品列表可滚动区域
        -- descY = midContentY+vendorBtnH+4, listY = descY+14 → midContentY+52
        buyListY0  = midContentY + 52,
        buyListH   = midContentH - 52 - 4,
        buyScrollW = 8,  -- 滚动条宽度（px）
    }
end

-- ============================================================================
-- 命中测试
-- state = { activeTab, activeVendorId, loadoutItems, sellPending, dragItem }
-- 返回 action 字符串/表：
--   "start" / "back" / "tabSell" / "tabBuy" / "confirmSell" / "selectAll"
--   {action="stashClick",    gridCol, gridRow}
--   {action="selectVendor",  vendorId}
--   {action="buyFrom",       vendorIdx}
--   {action="removeLoadout", itemId}
--   {action="removePending", itemIdx}
-- ============================================================================
function M.HitTestLoadout(layout, mx, my, state)
    if not layout then return nil end
    state = state or {}

    -- ================================================================
    -- 移动端命中测试（左仓库 + 右导航栏）
    -- ================================================================
    if layout.isMobile then
        -- 底部按钮（任意 Tab 下均可见）
        local sb = layout.startBtn
        if mx>=sb.x and mx<=sb.x+sb.w and my>=sb.y and my<=sb.y+sb.h then return "start" end
        local bb = layout.backBtn
        if mx>=bb.x and mx<=bb.x+bb.w and my>=bb.y and my<=bb.y+bb.h then return "back" end

        -- 右侧导航栏 Tab 切换（商店/背包/装备）
        for _, tab in ipairs(layout.sectionTabs) do
            if mx>=tab.x and mx<=tab.x+tab.w and my>=tab.y and my<=tab.y+tab.h then
                return { action="mobileSection", key=tab.key }
            end
        end

        -- ---- 左侧：仓库网格（始终可交互）----
        local g = layout.grid
        if mx>=g.x and mx<=g.x+g.w*g.cellSize and my>=g.y and my<=g.y+g.h*g.cellSize then
            local col = math.floor((mx-g.x)/g.cellSize)+1
            local row = math.floor((my-g.y)/g.cellSize)+1
            return { action="mobileStashTap", gridCol=col, gridRow=row }
        end

        -- ---- 右侧：根据当前 Tab 处理 ----
        local mobileSection = state.mobileSection or "shop"

        if mobileSection == "shop" then
            -- 出售/购买子 Tab
            local st = layout.sellTab
            if mx>=st.x and mx<=st.x+st.w and my>=st.y and my<=st.y+st.h then return "tabSell" end
            local bt = layout.buyTab
            if mx>=bt.x and mx<=bt.x+bt.w and my>=bt.y and my<=bt.y+bt.h then return "tabBuy" end

            local activeTab = state.activeTab or "sell"
            if activeTab == "buy" then
                -- 商人选择
                for _, vb in ipairs(layout.vendorBtns) do
                    if mx>=vb.x and mx<=vb.x+vb.w and my>=vb.y and my<=vb.y+vb.h then
                        return { action="selectVendor", vendorId=vb.vendorId }
                    end
                end
                -- 购买列表
                local vendor = Stash.VENDOR_BY_ID[state.activeVendorId or "therapist"]
                if vendor then
                    local itemH   = 32
                    local listY0  = layout.buyListY0
                    local listH   = layout.buyListH
                    local scrollY = state.buyScrollY or 0
                    local scrollW = layout.buyScrollW or 6
                    if my >= listY0 and my <= listY0 + listH then
                        for i, _ in ipairs(vendor.shop) do
                            local rowY    = listY0 + (i-1)*itemH - scrollY
                            local cw      = layout.midW - layout.pad*2 - scrollW
                            local buyBtnX = layout.midX + layout.pad + cw - 44
                            if mx >= buyBtnX and mx <= buyBtnX+44
                            and my >= rowY+3  and my <= rowY+itemH-3 then
                                return { action="buyFrom", vendorIdx=i }
                            end
                        end
                    end
                end
            else -- sell
                -- 全部出售 / 多选出售 / 确认出售
                local isMultiSellMode = state.multiSellMode
                if isMultiSellMode then
                    local conf = layout.confirmSellBtn
                    if mx>=conf.x and mx<=conf.x+conf.w and my>=conf.y and my<=conf.y+conf.h then
                        return "confirmSell"
                    end
                else
                    local sab = layout.sellAllBtn
                    if mx>=sab.x and mx<=sab.x+sab.w and my>=sab.y and my<=sab.y+sab.h then
                        return "selectAll"
                    end
                    local msb = layout.multiSellBtn
                    if mx>=msb.x and mx<=msb.x+msb.w and my>=msb.y and my<=msb.y+msb.h then
                        return "multiSell"
                    end
                end
                -- 待售列表点击移除（考虑滚动偏移）
                local pending = state.sellPending or {}
                if #pending > 0 then
                    local sz     = layout.sellZone
                    local listY0 = sz.y + sz.h + 6 + 18
                    local rowH   = 28
                    local sellScrollY = state.sellScrollY or 0
                    for i, _ in ipairs(pending) do
                        local rowY = listY0 + (i-1)*rowH - sellScrollY
                        if my >= rowY and my <= rowY+rowH then
                            return { action="removePending", itemIdx=i }
                        end
                    end
                end
            end

        elseif mobileSection == "bag" then
            -- 背包：出战装备列表，点击行移除（考虑滚动偏移）
            local items   = state.loadoutItems or {}
            local listY0  = layout.equipListY0
            local rowH    = layout.equipRowH
            local rx      = layout.rightX
            local rw      = layout.rightW
            local equipScrollY = state.equipScrollY or 0
            for i, it in ipairs(items) do
                local rowY = listY0 + (i-1)*rowH - equipScrollY
                if mx >= rx and mx <= rx+rw and my >= rowY+2 and my <= rowY+rowH-2 then
                    return { action="removeLoadout", itemId=it.id }
                end
            end

        elseif mobileSection == "equip" then
            -- 装备槽位：点击移除对应槽位
            local items  = state.loadoutItems or {}
            local rx     = layout.rightX
            local rw     = layout.rightW
            local slotSz = layout.slotSize
            local slotGap = 8
            local cols = 3
            local totalW3 = cols * slotSz + (cols-1)*slotGap
            local startX3 = rx + math.floor((rw - totalW3) / 2)
            local startY3 = layout.rContentY + 20

            local slotKeys = {"weapon1","weapon2","armor","helmet","bag","other"}
            for idx, key in ipairs(slotKeys) do
                local col3 = ((idx-1) % cols)
                local row3 = math.floor((idx-1) / cols)
                local sx = startX3 + col3 * (slotSz + slotGap)
                local sy = startY3 + row3 * (slotSz + slotGap + 16)
                if mx>=sx and mx<=sx+slotSz and my>=sy and my<=sy+slotSz then
                    -- 找到该槽位的物品并移除
                    local weapCount = 0
                    for _, it in ipairs(items) do
                        local itype = it.itype or "other"
                        if key == "weapon1" and itype == "weapon" then
                            weapCount = weapCount + 1
                            if weapCount == 1 then return { action="removeLoadout", itemId=it.id } end
                        elseif key == "weapon2" and itype == "weapon" then
                            weapCount = weapCount + 1
                            if weapCount == 2 then return { action="removeLoadout", itemId=it.id } end
                        elseif key == itype then
                            return { action="removeLoadout", itemId=it.id }
                        end
                    end
                    return nil -- slot empty
                end
            end
        end

        return nil
    end

    -- ================================================================
    -- PC 命中测试
    -- ================================================================
    local activeTab = state.activeTab or "sell"

    -- PC 端统一使用新 BattlePrepUI 模块（sell / buy 两个 tab）
    local sw = layout.screenW or (layout.panelW + layout.panelX * 2)
    local sh = layout.screenH or (layout.panelH + layout.panelY * 2)
    local bpState = {
        activeTab      = activeTab,
        activeVendorId = state.activeVendorId,
        buyScrollY     = state.buyScrollY,
        vendors        = Stash.VENDORS,
        sellPending    = state.sellPending,
    }
    local hit = BattlePrepUI.HitTest(mx, my, sw, sh, bpState)

    if not hit then return nil end

    -- table 类型结果（buy tab: selectVendor / buyFrom）直接透传
    if type(hit) == "table" then return hit end

    -- 将新 UI 的 hit 结果翻译为原有 action 格式
    if hit == "start" then return "start" end
    if hit == "back" then return "back" end
    if hit == "tab_sell" then return "tabSell" end
    if hit == "tab_buy" then return "tabBuy" end
    if hit == "sell_all" then return "selectAll" end
    if hit == "confirm_sell" then return "confirmSell" end
    if hit == "sell_drop_zone" then return "sellDropZone" end

    -- 仓库格子点击 → 转换为 stashClick（gridCol, gridRow）
    local whIdx = hit:match("^warehouse_(%d+)$")
    if whIdx then
        local idx = tonumber(whIdx)
        local col = ((idx - 1) % 10) + 1
        local row = math.floor((idx - 1) / 10) + 1
        return { action="stashClick", gridCol=col, gridRow=row }
    end

    -- 装备槽点击 → 映射为 removeLoadout（移除对应槽位装备）
    local slotMap = {
        slot_main_weapon = "mainWeapon",
        slot_sub_weapon  = "subWeapon",
        slot_armor       = "armor",
        slot_bag         = "bag",
        slot_consumable  = "consumable",
        slot_key_item    = "keyItem",
    }
    if slotMap[hit] then
        local slotKey = slotMap[hit]
        local items = state.loadoutItems or {}
        -- 找到对应槽位的物品并移除
        for i, it in ipairs(items) do
            local itype = it.itype or ""
            local matched = false
            if slotKey == "mainWeapon" then
                -- 第一个 weapon 类型
                if itype == "weapon" then
                    local isFirst = true
                    for j = 1, i-1 do
                        if (items[j].itype or "") == "weapon" then isFirst = false; break end
                    end
                    matched = isFirst
                end
            elseif slotKey == "subWeapon" then
                -- 第二个 weapon 类型
                if itype == "weapon" then
                    local weapCount = 0
                    for j = 1, i do
                        if (items[j].itype or "") == "weapon" then weapCount = weapCount + 1 end
                    end
                    matched = (weapCount == 2)
                end
            elseif slotKey == "armor" then
                matched = (itype == "armor")
            elseif slotKey == "bag" then
                matched = (itype == "bag")
            elseif slotKey == "consumable" then
                matched = (itype == "consumable")
            elseif slotKey == "keyItem" then
                matched = (itype == "key")
            end
            if matched then
                return { action="removeLoadout", itemId=it.id }
            end
        end
        return nil
    end

    -- tip 卡片点击暂不处理
    return nil
end

-- ============================================================================
-- 绘制仓库网格（左栏）
-- ============================================================================
local function DrawStashGrid(ctx, inv, g, selectedItemId, hoverItemId)
    local cs = g.cellSize
    -- 空格背景
    for row = 1, g.h do
        for col = 1, g.w do
            local x = g.x + (col-1)*cs
            local y = g.y + (row-1)*cs
            nvgBeginPath(ctx) nvgRect(ctx, x+1, y+1, cs-2, cs-2)
            nvgFillColor(ctx, nvgRGBA(10, 16, 22, 210)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgRect(ctx, x, y, cs, cs)
            nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, 12))
            nvgStrokeWidth(ctx, 0.5) nvgStroke(ctx)
        end
    end
    -- 物品
    for _, entry in ipairs(inv.items) do
        local pw = entry.rotated and entry.ih or entry.iw
        local ph = entry.rotated and entry.iw or entry.ih
        local x  = g.x + (entry.x-1)*cs
        local y  = g.y + (entry.y-1)*cs
        local w  = pw * cs
        local h  = ph * cs
        local rc = Data.RARITY_COLOR[entry.rarity or 1] or {180,180,180}
        local r, gb, b = rc[1], rc[2], rc[3]

        local isSelected = (selectedItemId == entry.id)
        local isHover    = (hoverItemId    == entry.id)

        -- 背景填充（像素硬边）
        nvgBeginPath(ctx) nvgRect(ctx, x+2, y+2, w-4, h-4)
        if isSelected then
            nvgFillColor(ctx, nvgRGBA(255, 200, 50, 80))
        else
            nvgFillColor(ctx, nvgRGBA(r, gb, b, isHover and 55 or 28))
        end
        nvgFill(ctx)
        -- 边框（像素硬边）
        nvgBeginPath(ctx) nvgRect(ctx, x+1, y+1, w-2, h-2)
        if isSelected then
            nvgStrokeColor(ctx, nvgRGBA(0,240,255,255))
            nvgStrokeWidth(ctx, 2)
        else
            nvgStrokeColor(ctx, nvgRGBA(r, gb, b, isHover and 255 or 170))
            nvgStrokeWidth(ctx, isHover and 1.8 or 1.2)
        end
        nvgStroke(ctx)
        -- 图标 —— 武器优先使用像素图片，枪长对框长
        local cellGunImg2 = (entry.itype == "weapon" and entry.data)
            and getWeaponImage(ctx, entry.data.key) or nil
        if cellGunImg2 then
            local longSide2 = math.max(w, h) - 8
            local shortSide2 = math.min(w, h) - 8
            local cW2 = longSide2
            local cH2 = cW2 * (44/66)
            if cH2 > shortSide2 then cH2 = shortSide2; cW2 = cH2 * (66/44) end
            if h > w then
                nvgSave(ctx)
                nvgTranslate(ctx, x + w/2, y + h/2)
                nvgRotate(ctx, -math.pi/2)
                local rP2 = nvgImagePattern(ctx, -cW2/2, -cH2/2, cW2, cH2, 0, cellGunImg2, 1.0)
                nvgBeginPath(ctx) nvgRect(ctx, -cW2/2, -cH2/2, cW2, cH2)
                nvgFillPaint(ctx, rP2) nvgFill(ctx)
                nvgRestore(ctx)
            else
                local cX2 = x + (w - cW2) / 2
                local cY2 = y + (h - cH2) / 2
                local cP2 = nvgImagePattern(ctx, cX2, cY2, cW2, cH2, 0, cellGunImg2, 1.0)
                nvgBeginPath(ctx) nvgRect(ctx, cX2, cY2, cW2, cH2)
                nvgFillPaint(ctx, cP2) nvgFill(ctx)
            end
        elseif entry.itype == "bag" and entry.data and BAG_IMG_PATHS[entry.data.id] then
            -- 背包类物品用自定义图片
            local bagImgSize2 = math.min(w, h) - 8
            drawBackpackIcon(ctx, x + (w - bagImgSize2)/2, y + h/2, bagImgSize2, entry.data.id)
        elseif entry.itype == "helmet" and entry.data and HELMET_IMG_PATHS[entry.data.id] then
            -- 头盔类物品用自定义图片
            local helmImgSize2 = math.min(w, h) - 8
            drawHelmetIcon(ctx, x + (w - helmImgSize2)/2, y + h/2, helmImgSize2, entry.data.id)
        elseif entry.itype == "armor" and entry.data and ARMOR_IMG_PATHS[entry.data.id] then
            -- 护甲类物品用自定义图片
            local armorImgSize2 = math.min(w, h) - 8
            drawArmorIcon(ctx, x + (w - armorImgSize2)/2, y + h/2, armorImgSize2, entry.data.id)
        elseif entry.data and entry.data.img then
            -- 有精灵图的物品：按格子实际宽高绘制
            local imgW2 = w - 6
            local imgH2 = h - 6
            DrawItemIcon(ctx, entry.data, x + w/2, y + h/2, imgW2, imgH2)
        else
            local iconSize = math.min(w, h) * 0.50
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, iconSize)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 220))
            nvgText(ctx, x+w/2, y+h/2, entry.icon or "?", nil)
        end
        -- 名称（格子足够高时）
        if h >= cs*2 then
            nvgFontSize(ctx, 8) nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(ctx, nvgRGBA(r, gb, b, 190))
            nvgText(ctx, x+w/2, y+h-3, entry.name or "", nil)
        end
        -- 堆叠数量角标
        if (entry.qty or 1) > 1 then
            local qtyStr = "×" .. tostring(entry.qty)
            local qx = x + w - 4
            local qy = y + h - 4
            nvgFontFace(ctx, "bold") nvgFontSize(ctx, 11)
            nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 180))
            nvgText(ctx, qx+1, qy+1, qtyStr, nil)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 240))
            nvgText(ctx, qx, qy, qtyStr, nil)
        end
    end
end

-- ============================================================================
-- 绘制中栏——出售面板
-- ============================================================================
local function DrawSellPanel(ctx, lp, stash, state)
    local mx0      = lp.midX + lp.pad
    local cw       = lp.midW - lp.pad*2
    local pending  = state.sellPending or {}
    local isDragging = (state.dragItem ~= nil)
    local isHover    = isDragging and (state.hoverZone == "sell")

    -- ---- 拖拽投放区（像素硬边）----
    local sz = lp.sellZone
    nvgBeginPath(ctx) nvgRect(ctx, sz.x, sz.y, sz.w, sz.h)
    if isHover then
        nvgFillColor(ctx, nvgRGBA(60, 200, 100, 55)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRect(ctx, sz.x, sz.y, sz.w, sz.h)
        nvgStrokeColor(ctx, nvgRGBA(80, 240, 120, 230))
    elseif isDragging then
        nvgFillColor(ctx, nvgRGBA(255, 200, 50, 30)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRect(ctx, sz.x, sz.y, sz.w, sz.h)
        nvgStrokeColor(ctx, nvgRGBA(255, 200, 50, 160))
    else
        nvgFillColor(ctx, nvgRGBA(10, 16, 22, 130)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRect(ctx, sz.x, sz.y, sz.w, sz.h)
        nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, 30))
    end
    nvgStrokeWidth(ctx, isDragging and 1.8 or 1) nvgStroke(ctx)

    -- 投放区提示文字
    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if isDragging then
        nvgFontSize(ctx, 13)
        nvgFillColor(ctx, isHover and nvgRGBA(80,240,120,255) or nvgRGBA(255,200,50,220))
        nvgText(ctx, sz.x+sz.w/2, sz.y+sz.h/2-8, isHover and "松开以加入待售" or "拖拽至此出售", nil)
        nvgFontSize(ctx, 9)
        nvgFillColor(ctx, nvgRGBA(0, 160, 180, 100))
        nvgText(ctx, sz.x+sz.w/2, sz.y+sz.h/2+10, "或拖到右侧「出战装备」区携带入局", nil)
    elseif lp.isMobile then
        -- 移动端：拖拽或双击提示
        nvgFontSize(ctx, 13)
        nvgFillColor(ctx, nvgRGBA(0, 200, 220, 140))
        nvgText(ctx, sz.x+sz.w/2, sz.y+sz.h/2-10, "拖拽或双击仓库物品加入待售", nil)
        nvgFontSize(ctx, 11)
        nvgFillColor(ctx, nvgRGBA(0, 160, 180, 100))
        nvgText(ctx, sz.x+sz.w/2, sz.y+sz.h/2+10, "切换背包/装备 Tab 可携带入局", nil)
    else
        nvgFontSize(ctx, 11)
        nvgFillColor(ctx, nvgRGBA(0, 200, 220, 140))
        nvgText(ctx, sz.x+sz.w/2, sz.y+sz.h/2-8, "← 从左侧拖拽物品至此出售", nil)
        nvgFontSize(ctx, 9)
        nvgFillColor(ctx, nvgRGBA(0, 160, 180, 100))
        nvgText(ctx, sz.x+sz.w/2, sz.y+sz.h/2+10, "或拖到右侧「出战装备」区携带入局", nil)
    end

    -- ---- 待售物品列表 ----
    local listY0 = sz.y + sz.h + 6
    local rowH   = lp.isMobile and 28 or 22
    local listMaxY = lp.confirmSellBtn.y - 6
    local sellScrollY = state.sellScrollY or 0

    -- 列表标题
    if #pending > 0 then
        -- 计算总价
        local totalGold = 0
        for _, it in ipairs(pending) do
            local bestPrice = 0
            for _, v in ipairs(Stash.VENDORS) do
                local p2 = Stash.GetSellPrice(it, v)
                if p2 > bestPrice then bestPrice = p2 end
            end
            totalGold = totalGold + bestPrice
        end
        nvgFontFace(ctx, "bold") nvgFontSize(ctx, 10)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(0, 210, 230, 200))
        local pendStr = string.format("待售 %d 件，预估 ", #pending)
        nvgText(ctx, mx0, listY0 + 8, pendStr .. tostring(totalGold), nil)
        local pendTW = nvgTextBounds(ctx, 0, 0, pendStr)
        drawMoneyIcon(ctx, mx0 + pendTW, listY0 + 8, 11)
        listY0 = listY0 + 18

        -- 滚动裁剪区域
        nvgSave(ctx)
        nvgScissor(ctx, mx0 - 2, listY0, cw + 4, listMaxY - listY0)

        -- 每行（应用滚动偏移）
        for i, it in ipairs(pending) do
            local rowY = listY0 + (i-1)*rowH - sellScrollY
            if rowY + rowH < listY0 then goto continueSellRow end
            if rowY > listMaxY then break end
            local rc = Data.RARITY_COLOR[it.rarity or 1] or {180,180,180}
            -- 行背景（像素硬边）
            nvgBeginPath(ctx) nvgRect(ctx, mx0, rowY+1, cw, rowH-2)
            nvgFillColor(ctx, nvgRGBA(rc[1],rc[2],rc[3],18)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgRect(ctx, mx0, rowY+1, cw, rowH-2)
            nvgStrokeColor(ctx, nvgRGBA(rc[1],rc[2],rc[3],80)) nvgStrokeWidth(ctx,0.8) nvgStroke(ctx)
            -- 图标+名称
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, 12)
            nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(rc[1],rc[2],rc[3],210))
            if it.itype == "bag" and it.data and BAG_IMG_PATHS[it.data.id] then
                local bpEnd = drawBackpackIcon(ctx, mx0+4, rowY+rowH/2, 12, it.data.id)
                nvgText(ctx, bpEnd, rowY+rowH/2, " "..(it.name or "?"), nil)
            elseif it.itype == "helmet" and it.data and HELMET_IMG_PATHS[it.data.id] then
                local hlEnd = drawHelmetIcon(ctx, mx0+4, rowY+rowH/2, 12, it.data.id)
                nvgText(ctx, hlEnd or (mx0+18), rowY+rowH/2, " "..(it.name or "?"), nil)
            elseif it.itype == "armor" and it.data and ARMOR_IMG_PATHS[it.data.id] then
                local arEnd = drawArmorIcon(ctx, mx0+4, rowY+rowH/2, 12, it.data.id)
                nvgText(ctx, arEnd or (mx0+18), rowY+rowH/2, " "..(it.name or "?"), nil)
            elseif it.data and it.data.img then
                DrawItemIcon(ctx, it.data, mx0+12, rowY+rowH/2, 14)
                nvgText(ctx, mx0+22, rowY+rowH/2, " "..(it.name or "?"), nil)
            else
                nvgText(ctx, mx0+4, rowY+rowH/2, (it.icon or "?").." "..(it.name or "?"), nil)
            end
            -- × 移除按钮
            nvgFontFace(ctx, "bold") nvgFontSize(ctx, 10)
            nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 107, 107, 180))
            nvgText(ctx, mx0+cw-4, rowY+rowH/2, "×", nil)
            ::continueSellRow::
        end
        nvgRestore(ctx)

        -- 滚动指示条（内容超出可视区时显示）
        local totalH = #pending * rowH
        local visH = listMaxY - listY0
        if totalH > visH then
            local barH = math.max(12, visH * visH / totalH)
            local barY = listY0 + (sellScrollY / (totalH - visH)) * (visH - barH)
            nvgBeginPath(ctx) nvgRoundedRect(ctx, mx0+cw+1, barY, 3, barH, 1.5)
            nvgFillColor(ctx, nvgRGBA(0,200,220,100)) nvgFill(ctx)
        end
    else
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(0, 180, 200, 80))
        nvgText(ctx, lp.midX+lp.midW/2, listY0+12, "（待售列表为空）", nil)
    end

    -- ---- 底部：全选 + 确认出售按钮 ----
    local sb = lp.selectAllBtn
    local hasPending = (#pending > 0)
    local hasItems   = (#stash.inv.items > 0)
    -- 全选按钮（像素硬边）
    nvgBeginPath(ctx) nvgRect(ctx, sb.x, sb.y, sb.w, sb.h)
    nvgFillColor(ctx, hasItems and nvgRGBA(0, 35, 45, 220) or nvgRGBA(12,18,23,140)) nvgFill(ctx)
    nvgBeginPath(ctx) nvgRect(ctx, sb.x, sb.y, sb.w, sb.h)
    nvgStrokeColor(ctx, hasItems and nvgRGBA(0, 240, 255, 160) or nvgRGBA(0,240,255,18))
    nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, lp.isMobile and 13 or 11)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, hasItems and nvgRGBA(0,240,255,230) or nvgRGBA(0,240,255,22))
    nvgText(ctx, sb.x+sb.w/2, sb.y+sb.h/2, "全选出售", nil)
    -- 确认出售按钮（像素硬边）
    local cb = lp.confirmSellBtn
    nvgBeginPath(ctx) nvgRect(ctx, cb.x, cb.y, cb.w, cb.h)
    nvgFillColor(ctx, hasPending and nvgRGBA(0,30,40,240) or nvgRGBA(12,18,23,140)) nvgFill(ctx)
    nvgBeginPath(ctx) nvgRect(ctx, cb.x, cb.y, cb.w, cb.h)
    nvgStrokeColor(ctx, hasPending and nvgRGBA(0,240,255,200) or nvgRGBA(0,240,255,18))
    nvgStrokeWidth(ctx, hasPending and 1.5 or 1) nvgStroke(ctx)
    nvgFontFace(ctx, hasPending and "bold" or "sans") nvgFontSize(ctx, lp.isMobile and 13 or 11)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, hasPending and nvgRGBA(0,240,255,255) or nvgRGBA(0,240,255,22))
    nvgText(ctx, cb.x+cb.w/2, cb.y+cb.h/2, "✓ 确认出售", nil)
end

-- ============================================================================
-- 绘制中栏——购买面板
-- ============================================================================
local function DrawBuyPanel(ctx, lp, stash, state)
    local mx0      = lp.midX + lp.pad
    local scrollW  = lp.buyScrollW or 8
    local cw       = lp.midW - lp.pad*2 - scrollW  -- 留出滚动条宽度

    -- ---- 商人选择按钮行 ----
    local vbH = lp.vendorBtnH
    for i, v in ipairs(Stash.VENDORS) do
        local vb = lp.vendorBtns[i]
        local isActive = (state.activeVendorId == v.id)
        nvgBeginPath(ctx) nvgRect(ctx, vb.x, vb.y, vb.w, vb.h)
        if isActive then
            nvgFillColor(ctx, nvgRGBA(0,35,45,230)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgRect(ctx, vb.x, vb.y, vb.w, vb.h)
            nvgStrokeColor(ctx, nvgRGBA(0,240,255,220)) nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)
        else
            nvgFillColor(ctx, nvgRGBA(10,16,20,180)) nvgFill(ctx)
            nvgBeginPath(ctx) nvgRect(ctx, vb.x, vb.y, vb.w, vb.h)
            nvgStrokeColor(ctx, nvgRGBA(0,240,255,22)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
        end
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 16)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 220))
        nvgText(ctx, vb.x + vb.w/2, vb.y + vb.h*0.45, v.icon, nil)
    end

    -- ---- 商人介绍 ----
    local vendor = Stash.VENDOR_BY_ID[state.activeVendorId or "therapist"]
    if not vendor then return end

    local descY = lp.midContentY + vbH + 4
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, lp.isMobile and 11 or 9)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(0,200,220,140))
    nvgText(ctx, mx0, descY, vendor.name .. "：" .. vendor.desc, nil)

    -- ---- 商品列表（带滚动裁剪）----
    local itemH    = lp.isMobile and 32 or 26
    local listY0   = lp.buyListY0   -- descY + 14
    local listH    = lp.buyListH
    local scrollY  = state.buyScrollY or 0
    local totalH   = #vendor.shop * itemH

    -- 滚动条轨道背景
    local trackX = mx0 + cw + 2
    nvgBeginPath(ctx) nvgRect(ctx, trackX, listY0, scrollW - 2, listH)
    nvgFillColor(ctx, nvgRGBA(0,30,40,160)) nvgFill(ctx)

    -- 剪裁到列表区域
    nvgSave(ctx)
    nvgIntersectScissor(ctx, mx0, listY0, cw + scrollW, listH)

    if #vendor.shop == 0 then
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(120, 125, 160, 150))
        nvgText(ctx, lp.midX + lp.midW/2, listY0 + 30, "（暂无库存）", nil)
    else
        for i, shopItem in ipairs(vendor.shop) do
            local rowY   = listY0 + (i-1)*itemH - scrollY
            local rowBot = rowY + itemH
            -- 跳过完全不可见的行
            if rowBot > listY0 and rowY < listY0 + listH then
                -- 弹药上限检查
                local ammoFull = false
                if shopItem.itype == "ammo" then
                    local cur = (stash.ammo and stash.ammo[shopItem.ammoType]) or 0
                    ammoFull = cur >= (shopItem.maxOwned or 99)
                end
                local canBuy = (stash.money >= shopItem.price) and (not ammoFull)

                -- 行背景（隔行变色）
                nvgBeginPath(ctx) nvgRect(ctx, mx0, rowY+1, cw, itemH-2)
                local rowAlpha = (i % 2 == 0) and 160 or 120
                nvgFillColor(ctx, nvgRGBA(10,16,22,rowAlpha)) nvgFill(ctx)

                -- 图标
                local shopNameX = mx0+22
                if shopItem.itype == "bag" and shopItem.data and BAG_IMG_PATHS[shopItem.data.id] then
                    local bpEnd = drawBackpackIcon(ctx, mx0+2, rowY + itemH/2, 14, shopItem.data.id)
                    shopNameX = bpEnd + 2
                elseif shopItem.itype == "helmet" and shopItem.data and HELMET_IMG_PATHS[shopItem.data.id] then
                    local hlEnd = drawHelmetIcon(ctx, mx0+2, rowY + itemH/2, 14, shopItem.data.id)
                    if hlEnd then shopNameX = hlEnd + 2 end
                elseif shopItem.itype == "armor" and shopItem.data and ARMOR_IMG_PATHS[shopItem.data.id] then
                    local arEnd = drawArmorIcon(ctx, mx0+2, rowY + itemH/2, 14, shopItem.data.id)
                    if arEnd then shopNameX = arEnd + 2 end
                else
                    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 14)
                    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 200))
                    DrawItemIcon(ctx, shopItem, mx0+2, rowY + itemH/2, 20)
                end

                -- 名称
                nvgFontFace(ctx, "sans") nvgFontSize(ctx, lp.isMobile and 13 or 11)
                nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(180,230,240,220))
                nvgText(ctx, shopNameX, rowY + itemH/2, shopItem.name, nil)

                -- 弹药持有量显示
                if shopItem.itype == "ammo" then
                    local cur = (stash.ammo and stash.ammo[shopItem.ammoType]) or 0
                    local cap = shopItem.maxOwned or 99
                    local countStr = string.format(" [%d/%d]", cur, cap)
                    local nameEnd = shopNameX + nvgTextBounds(ctx, 0, 0, shopItem.name, nil, nil)
                    nvgFontSize(ctx, lp.isMobile and 11 or 9)
                    nvgFillColor(ctx, ammoFull and nvgRGBA(255,100,80,200) or nvgRGBA(120,200,160,180))
                    nvgText(ctx, nameEnd + 2, rowY + itemH/2, countStr, nil)
                end

                -- 价格
                nvgFontFace(ctx, "bold") nvgFontSize(ctx, lp.isMobile and 13 or 11)
                nvgFillColor(ctx, canBuy and nvgRGBA(255, 210, 40, 240) or nvgRGBA(150, 120, 60, 180))
                nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                local priceIconX = drawMoneyIcon(ctx, mx0+118, rowY + itemH/2, 12)
                nvgText(ctx, priceIconX, rowY + itemH/2, tostring(shopItem.price), nil)

                -- 购买按钮
                local btnX = mx0 + cw - 44
                if canBuy then
                    DrawBtn(ctx, btnX, rowY+3, 42, 20, "购买", 0, 200, 220)
                elseif ammoFull then
                    DrawBtn(ctx, btnX, rowY+3, 42, 20, "已满", 120, 80, 60, 120)
                else
                    DrawBtn(ctx, btnX, rowY+3, 42, 20, "不足", 120, 80, 60, 120)
                end
            end
        end
    end

    nvgRestore(ctx)

    -- ---- 滚动条滑块 ----
    if totalH > listH then
        local maxScroll = totalH - listH
        local thumbH    = math.max(20, listH * listH / totalH)
        local thumbY    = listY0 + (scrollY / maxScroll) * (listH - thumbH)
        nvgBeginPath(ctx) nvgRect(ctx, trackX, thumbY, scrollW - 2, thumbH)
        nvgFillColor(ctx, nvgRGBA(0, 200, 240, 180)) nvgFill(ctx)

        -- 上/下箭头提示（顶部和底部各一个小三角）
        if scrollY > 0 then
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, 9)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(0, 200, 240, 160))
            nvgText(ctx, trackX + (scrollW-2)/2, listY0 - 6, "▲", nil)
        end
        if scrollY < maxScroll then
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, 9)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(0, 200, 240, 160))
            nvgText(ctx, trackX + (scrollW-2)/2, listY0 + listH + 6, "▼", nil)
        end
    end
end

-- ============================================================================
-- 绘制战前准备界面
-- state = { activeTab, activeVendorId, selectedItemId, loadoutItems, hoverItemId }
-- ============================================================================
-- ============================================================================
-- 移动端战前准备（左仓库 + 右导航栏）
-- ============================================================================
local function DrawLoadoutScreenMobile(ctx, stash, lp, state, sw, sh)
    local inv           = stash.inv
    local mobileSection = state.mobileSection or "shop"
    local activeTab     = state.activeTab or "sell"
    local PAD           = lp.pad

    -- 全屏暗背景
    nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, sh)
    local bg = nvgLinearGradient(ctx, 0, 0, 0, sh,
        nvgRGBA(8,12,16,255), nvgRGBA(15,20,25,255))
    nvgFillPaint(ctx, bg) nvgFill(ctx)

    -- ---- 顶部标题栏 ----
    nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, lp.titleH)
    nvgFillColor(ctx, nvgRGBA(10,14,20,255)) nvgFill(ctx)
    nvgBeginPath(ctx) nvgMoveTo(ctx, 0, lp.titleH) nvgLineTo(ctx, sw, lp.titleH)
    nvgStrokeColor(ctx, nvgRGBA(0,240,255,40)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)

    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 17)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0,240,255,240))
    nvgText(ctx, 14, lp.titleH/2, "⚔ 战前准备", nil)

    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255,215,60,255))
    local moneyStr = tostring(stash.money)
    local moneyTW = nvgTextBounds(ctx, 0, 0, moneyStr)
    nvgText(ctx, sw - 12, lp.titleH/2, moneyStr, nil)
    drawMoneyIcon(ctx, sw - 12 - moneyTW - 16, lp.titleH/2, 16)

    -- ================================================================
    -- 左侧面板：仓库网格（始终显示）
    -- ================================================================
    -- 左侧面板背景
    nvgBeginPath(ctx) nvgRect(ctx, 0, lp.titleH, lp.leftW, sh - lp.titleH)
    nvgFillColor(ctx, nvgRGBA(5,9,14,200)) nvgFill(ctx)

    -- 左侧提示
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0,200,220,130))
    nvgText(ctx, lp.leftW/2, lp.contentY + 8, "单击选中 · 双击装备/卸下", nil)

    -- 绘制仓库网格
    DrawStashGrid(ctx, inv, lp.grid, state.selectedItemId, state.hoverItemId)

    -- 仓库网格中已在出战列表的物品盖 ✓ 覆层
    local loadoutIds = {}
    for _, it in ipairs(state.loadoutItems or {}) do loadoutIds[it.id] = true end
    local g  = lp.grid
    local cs = g.cellSize
    for _, entry in ipairs(inv.items) do
        if loadoutIds[entry.id] then
            local pw = entry.rotated and entry.ih or entry.iw
            local ph = entry.rotated and entry.iw or entry.ih
            local ex = g.x + (entry.x-1)*cs
            local ey = g.y + (entry.y-1)*cs
            local ew = pw * cs
            local eh = ph * cs
            nvgBeginPath(ctx) nvgRect(ctx, ex+1, ey+1, ew-2, eh-2)
            nvgFillColor(ctx, nvgRGBA(0,220,80,60)) nvgFill(ctx)
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, math.min(ew, eh)*0.45)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(80,255,120,240))
            nvgText(ctx, ex+ew/2, ey+eh/2, "✓", nil)
        end
    end

    -- 选中物品信息（左侧底部浮层）
    if state.selectedItemId then
        local selEntry = nil
        for _, e in ipairs(inv.items) do
            if e.id == state.selectedItemId then selEntry = e; break end
        end
        if selEntry then
            local tip = Data.GetItemTooltip(selEntry)
            if tip then
                local panelH2 = 52
                local panelY2 = sh - lp.startBtn.h - 20 - panelH2
                local panelX2 = 4
                local panelW2 = lp.leftW - 8
                nvgBeginPath(ctx) nvgRoundedRect(ctx, panelX2, panelY2, panelW2, panelH2, 4)
                nvgFillColor(ctx, nvgRGBA(8, 14, 22, 235)) nvgFill(ctx)
                local rc = Data.RARITY_COLOR[tip.rarity or 1] or {180,180,180}
                nvgBeginPath(ctx) nvgRoundedRect(ctx, panelX2, panelY2, panelW2, panelH2, 4)
                nvgStrokeColor(ctx, nvgRGBA(rc[1], rc[2], rc[3], 150))
                nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
                -- 标题
                nvgFontFace(ctx, "bold") nvgFontSize(ctx, 12)
                nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(ctx, nvgRGBA(rc[1], rc[2], rc[3], 255))
                nvgText(ctx, panelX2 + 6, panelY2 + 5, tip.title, nil)
                -- 属性
                local statLine = ""
                for si, st in ipairs(tip.stats) do
                    if si > 1 then statLine = statLine .. " " end
                    statLine = statLine .. st.label .. ":" .. st.value
                end
                if statLine ~= "" then
                    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
                    nvgFillColor(ctx, nvgRGBA(200, 220, 230, 200))
                    nvgText(ctx, panelX2 + 6, panelY2 + 22, statLine, nil)
                end
                -- 操作提示
                local inLoadout = loadoutIds[selEntry.id]
                local hintText = inLoadout and "双击卸下" or "双击装备"
                nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
                nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgFillColor(ctx, nvgRGBA(0, 220, 255, 180))
                nvgText(ctx, panelX2 + panelW2 - 6, panelY2 + 5, hintText, nil)
            end
        end
    end

    -- 左右分隔线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, lp.leftW, lp.titleH)
    nvgLineTo(ctx, lp.leftW, sh)
    nvgStrokeColor(ctx, nvgRGBA(0,240,255,30)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)

    -- ================================================================
    -- 右侧面板：导航栏 + 内容
    -- ================================================================
    -- 右侧导航栏 Tab
    for _, tab in ipairs(lp.sectionTabs) do
        local isActive = (mobileSection == tab.key)
        nvgBeginPath(ctx) nvgRect(ctx, tab.x, tab.y, tab.w, tab.h)
        nvgFillColor(ctx, isActive and nvgRGBA(0,28,42,255) or nvgRGBA(12,16,22,220)) nvgFill(ctx)
        if isActive then
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, tab.x+2, tab.y+tab.h-1)
            nvgLineTo(ctx, tab.x+tab.w-2, tab.y+tab.h-1)
            nvgStrokeColor(ctx, nvgRGBA(0,240,255,255)) nvgStrokeWidth(ctx, 2) nvgStroke(ctx)
        end
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 13)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, isActive and nvgRGBA(0,240,255,255) or nvgRGBA(140,170,175,180))
        nvgText(ctx, tab.x + tab.w/2, tab.y + tab.h/2, tab.label, nil)
    end
    -- Tab 底部分割线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, lp.rightX, lp.sectionTabs[1].y + lp.sectionTabs[1].h)
    nvgLineTo(ctx, sw, lp.sectionTabs[1].y + lp.sectionTabs[1].h)
    nvgStrokeColor(ctx, nvgRGBA(0,240,255,25)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)

    -- ---- 右侧内容区 ----
    if mobileSection == "shop" then
        -- 商店：出售/购买子 Tab
        local tabs2 = {
            {key="sell", label="💸 出售", btn=lp.sellTab},
            {key="buy",  label="🛒 购买", btn=lp.buyTab},
        }
        for _, tab in ipairs(tabs2) do
            local isActive2 = (activeTab == tab.key)
            local tb = tab.btn
            nvgBeginPath(ctx) nvgRect(ctx, tb.x, tb.y, tb.w, tb.h)
            if isActive2 then
                nvgFillColor(ctx, nvgRGBA(0,30,40,240)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRect(ctx, tb.x, tb.y, tb.w, tb.h)
                nvgStrokeColor(ctx, nvgRGBA(0,240,255,220)) nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)
            else
                nvgFillColor(ctx, nvgRGBA(12,18,24,200)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRect(ctx, tb.x, tb.y, tb.w, tb.h)
                nvgStrokeColor(ctx, nvgRGBA(50,60,100,130)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
            end
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, 13)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, isActive2 and nvgRGBA(0,240,255,240) or nvgRGBA(140,170,175,160))
            nvgText(ctx, tb.x+tb.w/2, tb.y+tb.h/2, tab.label, nil)
        end
        -- 出售/购买内容
        if activeTab == "sell" then
            DrawSellPanel(ctx, lp, stash, state)
        else
            DrawBuyPanel(ctx, lp, stash, state)
        end

        -- 底部：全部出售 / 多选出售 按钮（仅 sell 模式下）
        if activeTab == "sell" then
            local isMultiSellMode = state.multiSellMode
            if isMultiSellMode then
                -- 多选模式：显示确认出售按钮
                local csb = lp.confirmSellBtn
                nvgBeginPath(ctx) nvgRect(ctx, csb.x, csb.y, csb.w, csb.h)
                nvgFillColor(ctx, nvgRGBA(200,60,40,220)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRect(ctx, csb.x, csb.y, csb.w, csb.h)
                nvgStrokeColor(ctx, nvgRGBA(255,100,80,200)) nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)
                nvgFontFace(ctx, "bold") nvgFontSize(ctx, 13)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(255,255,255,240))
                local pendN = #(state.sellPending or {})
                nvgText(ctx, csb.x+csb.w/2, csb.y+csb.h/2,
                    pendN > 0 and string.format("确认出售 (%d件)", pendN) or "取消多选", nil)
            else
                -- 正常模式：全部出售 + 多选出售
                local sab = lp.sellAllBtn
                nvgBeginPath(ctx) nvgRect(ctx, sab.x, sab.y, sab.w, sab.h)
                nvgFillColor(ctx, nvgRGBA(180,50,30,200)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRect(ctx, sab.x, sab.y, sab.w, sab.h)
                nvgStrokeColor(ctx, nvgRGBA(240,80,60,180)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
                nvgFontFace(ctx, "sans") nvgFontSize(ctx, 12)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(255,255,255,220))
                nvgText(ctx, sab.x+sab.w/2, sab.y+sab.h/2, "全部出售", nil)

                local msb = lp.multiSellBtn
                nvgBeginPath(ctx) nvgRect(ctx, msb.x, msb.y, msb.w, msb.h)
                nvgFillColor(ctx, nvgRGBA(40,80,120,200)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRect(ctx, msb.x, msb.y, msb.w, msb.h)
                nvgStrokeColor(ctx, nvgRGBA(60,150,200,180)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
                nvgFontFace(ctx, "sans") nvgFontSize(ctx, 12)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(255,255,255,220))
                nvgText(ctx, msb.x+msb.w/2, msb.y+msb.h/2, "多选出售", nil)
            end
        end

    elseif mobileSection == "bag" then
        -- 背包（出战装备列表）
        local items   = state.loadoutItems or {}
        local listY0  = lp.equipListY0
        local rowH    = lp.equipRowH
        local rx      = lp.rightX
        local rw      = lp.rightW
        local equipScrollY = state.equipScrollY or 0
        local listMaxY = lp.rContentY + lp.rContentH - 4

        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(0,200,220,150))
        nvgText(ctx, rx + rw/2, listY0 - 8, string.format("出战装备 %d 件（点击移除）", #items), nil)

        if #items == 0 then
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, 13)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(60,120,130,130))
            nvgText(ctx, rx + rw/2, listY0 + 30, "（无装备）", nil)
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
            nvgFillColor(ctx, nvgRGBA(60,120,130,100))
            nvgText(ctx, rx + rw/2, listY0 + 50, "在左侧仓库双击物品装备", nil)
        else
            -- 滚动裁剪区域
            nvgSave(ctx)
            nvgScissor(ctx, rx, listY0, rw, listMaxY - listY0)

            for i, it in ipairs(items) do
                local rowY = listY0 + (i-1)*rowH - equipScrollY
                if rowY + rowH < listY0 then goto continueEquipRow end
                if rowY > listMaxY then break end
                local rc2 = Data.RARITY_COLOR[it.rarity or 1] or {180,180,180}
                -- 行背景
                nvgBeginPath(ctx) nvgRect(ctx, rx+PAD, rowY+2, rw-PAD*2, rowH-4)
                nvgFillColor(ctx, nvgRGBA(rc2[1],rc2[2],rc2[3], 20)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRect(ctx, rx+PAD, rowY+2, rw-PAD*2, rowH-4)
                nvgStrokeColor(ctx, nvgRGBA(rc2[1],rc2[2],rc2[3], 80)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
                -- 文字
                nvgFontFace(ctx, "sans") nvgFontSize(ctx, 13)
                nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(rc2[1],rc2[2],rc2[3], 230))
                local textX = rx + PAD + 6
                if it.itype == "bag" and it.data and BAG_IMG_PATHS[it.data.id] then
                    local bpEnd = drawBackpackIcon(ctx, textX, rowY+rowH/2, 13, it.data.id)
                    nvgText(ctx, bpEnd, rowY+rowH/2, " "..(it.name or "?"), nil)
                elseif it.itype == "helmet" and it.data and HELMET_IMG_PATHS[it.data.id] then
                    local hlEnd = drawHelmetIcon(ctx, textX, rowY+rowH/2, 13, it.data.id)
                    nvgText(ctx, hlEnd or (textX+14), rowY+rowH/2, " "..(it.name or "?"), nil)
                elseif it.itype == "armor" and it.data and ARMOR_IMG_PATHS[it.data.id] then
                    local arEnd = drawArmorIcon(ctx, textX, rowY+rowH/2, 13, it.data.id)
                    nvgText(ctx, arEnd or (textX+14), rowY+rowH/2, " "..(it.name or "?"), nil)
                elseif it.data and it.data.img then
                    DrawItemIcon(ctx, it.data, textX+7, rowY+rowH/2, 14)
                    nvgText(ctx, textX+16, rowY+rowH/2, " "..(it.name or "?"), nil)
                else
                    nvgText(ctx, textX, rowY+rowH/2, (it.icon or "?").." "..(it.name or "?"), nil)
                end
                -- 移除标签
                nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
                nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(240,80,80,160))
                nvgText(ctx, rx+rw-PAD-4, rowY+rowH/2, "×", nil)
                ::continueEquipRow::
            end
            nvgRestore(ctx)

            -- 滚动指示条（内容超出可视区时显示）
            local totalH = #items * rowH
            local visH = listMaxY - listY0
            if totalH > visH then
                local barH = math.max(12, visH * visH / totalH)
                local barY = listY0 + (equipScrollY / (totalH - visH)) * (visH - barH)
                nvgBeginPath(ctx) nvgRoundedRect(ctx, rx+rw-4, barY, 3, barH, 1.5)
                nvgFillColor(ctx, nvgRGBA(0,200,220,100)) nvgFill(ctx)
            end
        end

    elseif mobileSection == "equip" then
        -- 装备槽位（可拖入）
        local items  = state.loadoutItems or {}
        local rx     = lp.rightX
        local rw     = lp.rightW
        local slotSz = lp.slotSize
        local slotGap = 8
        -- 3列2行布局
        local cols = 3
        local totalW3 = cols * slotSz + (cols-1)*slotGap
        local startX3 = rx + math.floor((rw - totalW3) / 2)
        local startY3 = lp.rContentY + 20

        local slotDefs = {
            { key="weapon1", label="主武器", icon="🗡" },
            { key="weapon2", label="副武器", icon="🔫" },
            { key="armor",   label="护甲",   icon="🛡" },
            { key="helmet",  label="头盔",   icon="⛑" },
            { key="bag",     label="背包",   icon="🎒" },
            { key="other",   label="其他",   icon="📦" },
        }

        -- 按类型分组出战物品
        local equipped = {}
        for _, it in ipairs(items) do
            local itype = it.itype or "other"
            if itype == "weapon" then
                if not equipped.weapon1 then equipped.weapon1 = it
                elseif not equipped.weapon2 then equipped.weapon2 = it end
            elseif itype == "armor" then equipped.armor = it
            elseif itype == "helmet" then equipped.helmet = it
            elseif itype == "bag" then equipped.bag = it
            else
                if not equipped.other then equipped.other = it end
            end
        end

        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(0,200,220,140))
        nvgText(ctx, rx + rw/2, lp.rContentY + 8, "装备槽位（双击仓库物品装备）", nil)

        for idx, slot in ipairs(slotDefs) do
            local col3 = ((idx-1) % cols)
            local row3 = math.floor((idx-1) / cols)
            local sx = startX3 + col3 * (slotSz + slotGap)
            local sy = startY3 + row3 * (slotSz + slotGap + 16)

            local equippedItem = equipped[slot.key]

            -- 槽背景
            nvgBeginPath(ctx) nvgRoundedRect(ctx, sx, sy, slotSz, slotSz, 4)
            if equippedItem then
                local rc3 = Data.RARITY_COLOR[equippedItem.rarity or 1] or {180,180,180}
                nvgFillColor(ctx, nvgRGBA(rc3[1],rc3[2],rc3[3], 30)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRoundedRect(ctx, sx, sy, slotSz, slotSz, 4)
                nvgStrokeColor(ctx, nvgRGBA(rc3[1],rc3[2],rc3[3], 160)) nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)
            else
                nvgFillColor(ctx, nvgRGBA(15,20,28,180)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRoundedRect(ctx, sx, sy, slotSz, slotSz, 4)
                nvgStrokeColor(ctx, nvgRGBA(0,240,255,40)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
            end

            -- 槽内容
            if equippedItem then
                -- 物品图标
                nvgFontFace(ctx, "sans") nvgFontSize(ctx, slotSz * 0.4)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(255,255,255,220))
                nvgText(ctx, sx+slotSz/2, sy+slotSz/2 - 4, equippedItem.icon or slot.icon, nil)
                -- 物品名
                nvgFontFace(ctx, "sans") nvgFontSize(ctx, 9)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                nvgFillColor(ctx, nvgRGBA(200,220,230,200))
                nvgText(ctx, sx+slotSz/2, sy+slotSz-3, equippedItem.name or "?", nil)
            else
                -- 空槽图标
                nvgFontFace(ctx, "sans") nvgFontSize(ctx, slotSz * 0.35)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(60,80,100,100))
                nvgText(ctx, sx+slotSz/2, sy+slotSz/2, slot.icon, nil)
            end

            -- 槽标签
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, 9)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(ctx, nvgRGBA(120,150,160,150))
            nvgText(ctx, sx+slotSz/2, sy+slotSz+2, slot.label, nil)
        end

        -- 弹药携带情况（装备槽下方）
        local ammoY = startY3 + 2 * (slotSz + slotGap + 16) + 12
        local ammoData = stash.ammo or {}
        local ammoTypes = {
            { key="light",  label="轻型", icon="•" },
            { key="medium", label="中型", icon="◆" },
            { key="heavy",  label="重型", icon="■" },
            { key="sniper", label="狙击", icon="▲" },
        }
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(180,200,160,180))
        nvgText(ctx, rx + 8, ammoY, "弹药储备:", nil)
        local ammoX = rx + 60
        for _, at in ipairs(ammoTypes) do
            local cnt = ammoData[at.key] or 0
            if cnt > 0 then
                nvgFillColor(ctx, nvgRGBA(180,230,150,220))
            else
                nvgFillColor(ctx, nvgRGBA(80,100,70,130))
            end
            nvgText(ctx, ammoX, ammoY, at.icon .. at.label .. ":" .. cnt, nil)
            ammoX = ammoX + 58
        end
    end

    -- ---- 底部按钮 ----
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, lp.pad, lp.startBtn.y - 6)
    nvgLineTo(ctx, sw - lp.pad, lp.startBtn.y - 6)
    nvgStrokeColor(ctx, nvgRGBA(0,240,255,20)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)

    -- 返回
    local bb = lp.backBtn
    nvgBeginPath(ctx) nvgRect(ctx, bb.x, bb.y, bb.w, bb.h)
    nvgFillColor(ctx, nvgRGBA(18,22,28,220)) nvgFill(ctx)
    nvgBeginPath(ctx) nvgRect(ctx, bb.x, bb.y, bb.w, bb.h)
    nvgStrokeColor(ctx, nvgRGBA(0,240,255,40)) nvgStrokeWidth(ctx, 1) nvgStroke(ctx)
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(160,200,210,200))
    nvgText(ctx, bb.x+bb.w/2, bb.y+bb.h/2, "← 返回", nil)

    -- 出发
    local sb = lp.startBtn
    nvgBeginPath(ctx) nvgRect(ctx, sb.x, sb.y, sb.w, sb.h)
    nvgFillColor(ctx, nvgRGBA(0,25,40,245)) nvgFill(ctx)
    nvgBeginPath(ctx) nvgRect(ctx, sb.x, sb.y, sb.w, sb.h)
    nvgStrokeColor(ctx, nvgRGBA(0,240,255,210)) nvgStrokeWidth(ctx, 1.8) nvgStroke(ctx)
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 15)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0,240,255,255))
    nvgText(ctx, sb.x+sb.w/2, sb.y+sb.h/2, "▶ 出发！", nil)

    -- ---- 拖拽 Ghost + 目标区域高亮 ----
    if state.dragItem then
        local dx = (state.dragX or 0) - 18
        local dy = (state.dragY or 0) - 18
        local hz = state.hoverZone
        -- 目标区域高亮（loadoutZone 用于背包/装备 tab）
        if hz == "loadout" then
            local lz = lp.loadoutZone
            if lz then
                nvgBeginPath(ctx) nvgRect(ctx, lz.x, lz.y, lz.w, lz.h)
                nvgFillColor(ctx, nvgRGBA(80,200,80,35)) nvgFill(ctx)
                nvgBeginPath(ctx) nvgRect(ctx, lz.x, lz.y, lz.w, lz.h)
                nvgStrokeColor(ctx, nvgRGBA(100,230,100,200)) nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)
                nvgFontFace(ctx, "sans") nvgFontSize(ctx, 13)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(100,240,120,230))
                nvgText(ctx, lz.x+lz.w/2, lz.y+lz.h/2, "松开出战", nil)
            end
        end
        -- Ghost 图标跟随手指
        local item = state.dragItem
        local rc = Data.RARITY_COLOR[item.rarity or 1] or {180,180,180}
        nvgBeginPath(ctx) nvgRect(ctx, dx+2, dy+2, 36, 36)
        nvgFillColor(ctx, nvgRGBA(0,0,0,80)) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRoundedRect(ctx, dx, dy, 36, 36, 4)
        nvgFillColor(ctx, nvgRGBA(rc[1],rc[2],rc[3],60)) nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(rc[1],rc[2],rc[3],200)) nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 20)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255,255,255,230))
        DrawItemIcon(ctx, item, dx+18, dy+18, 28)
    end
end

function M.DrawLoadoutScreen(ctx, stash, layout, state, sw, sh)
    state  = state  or {}
    -- 懒计算布局
    if not layout then
        layout = M.GetLoadoutLayout(stash, sw, sh)
    end
    local lp  = layout
    local inv = stash.inv
    local activeTab = state.activeTab or "sell"

    -- 移动端分支（保留原有移动端渲染）
    if lp.isMobile then
        return DrawLoadoutScreenMobile(ctx, stash, lp, state, sw, sh)
    end

    -- PC 端：使用新战前准备 UI（sell / buy 两个 tab 统一渲染）
    local bpData = BattlePrepUI.BuildData(stash, state)
    BattlePrepUI.Draw(ctx, sw, sh, bpData)

    -- 拖拽视觉反馈叠加层
    if state.dragItem then
        BattlePrepUI.DrawDragOverlay(ctx, sw, sh, {
            hoverZone = state.hoverZone,
            activeTab = activeTab,
            dragX     = state.dragX or 0,
            dragY     = state.dragY or 0,
            dragItem  = state.dragItem,
        })
    end
    return
end
-- ============================================================================
-- 医疗快捷栏（右下角，3 格）
-- ============================================================================
local MED_W   = 33   -- 单格宽
local MED_H   = 42   -- 单格高
local MED_GAP = 4    -- 格间距
local MED_N   = 3    -- 格数量
local MED_MRG = 16   -- 屏幕边距

-- 稀有度边框颜色
local function medRarityColor(r, alpha)
    if r == 1 then return nvgRGBA(130,130,148,alpha)
    elseif r == 2 then return nvgRGBA(78,204,163,alpha)
    elseif r == 3 then return nvgRGBA(52,152,219,alpha)
    elseif r == 4 then return nvgRGBA(168,85,247,alpha)
    else                return nvgRGBA(255,107,107,alpha) end
end

-- 根据 healPct 取颜色
local function medHealColor(pct)
    if pct >= 0.5 then return nvgRGBA(52,152,219,230)     -- 高: 蓝
    elseif pct >= 0.25 then return nvgRGBA(78,204,163,230) -- 中: 绿
    else return nvgRGBA(243,156,18,230) end                -- 低: 橙
end

-- 命中测试：返回被点击的格子索引（1~3）或 nil
-- 根据是否手机端返回 MedBar 左上角坐标
-- 手机端：底部居中，避开左侧摇杆和右侧操作键
-- PC 端：右下角（保持原位）
local function medBarOrigin(sw, sh, isMobile)
    local totalW = MED_N * MED_W + (MED_N - 1) * MED_GAP
    if isMobile then
        return math.floor(sw / 2 - totalW / 2), sh - MED_H - MED_MRG
    else
        return sw - totalW - MED_MRG, sh - MED_H - MED_MRG
    end
end

function M.HitTestMedBar(mx, my, sw, sh, isMobile)
    local totalW = MED_N * MED_W + (MED_N - 1) * MED_GAP
    local bx, by = medBarOrigin(sw, sh, isMobile)
    for i = 1, MED_N do
        local sx = bx + (i - 1) * (MED_W + MED_GAP)
        if mx >= sx and mx <= sx + MED_W and my >= by and my <= by + MED_H then
            return i
        end
    end
    return nil
end

-- 绘制医疗快捷栏
-- hoverSlot: 当前悬停的格子索引（1~3），nil 表示无悬停
-- isMobile: 手机端时居中显示，避开操作键
function M.DrawMedBar(ctx, player, sw, sh, hoverSlot, isMobile, elapsedTime)
    elapsedTime = elapsedTime or 0
    local PlayerM  = require("Player")
    local medSlots = PlayerM.GetMedSlots(player)

    local totalW = MED_N * MED_W + (MED_N - 1) * MED_GAP
    local bx, by = medBarOrigin(sw, sh, isMobile)

    -- 整体背景条（像素风）
    PixelUI.DrawPanel(ctx, bx - 6, by - 6, totalW + 12, MED_H + 12, {
        bg = {10,15,20,170}, shadow = false, noiseAlpha = 6, highlight = false,
    })

    for i = 1, MED_N do
        local sx      = bx + (i - 1) * (MED_W + MED_GAP)
        local sy      = by
        local item    = medSlots[i]
        local isHover = (hoverSlot == i)
        local flash   = player.medUseFlash and player.medUseFlash[i]
        local isFlash = flash and flash > 0

        -- 格子背景（像素风硬边）
        local cellBg, cellBorder
        if isFlash then
            cellBg = {255, 255, 200, 60}
            cellBorder = {255, 240, 80, 240}
        elseif isHover and item then
            cellBg = {0, 32, 42, 235}
            local r2 = item.rarity or 1
            local rc = Data.RARITY_COLOR[r2] or {180,180,180}
            cellBorder = {rc[1], rc[2], rc[3], 220}
        elseif item then
            cellBg = {15,20,25,220}
            local r2 = item.rarity or 1
            local rc = Data.RARITY_COLOR[r2] or {180,180,180}
            cellBorder = {rc[1], rc[2], rc[3], 130}
        else
            cellBg = {15,20,25,220}
            cellBorder = {0,240,255, isHover and 30 or 12}
        end
        nvgBeginPath(ctx) nvgRect(ctx, sx, sy, MED_W, MED_H)
        nvgFillColor(ctx, nvgRGBA(cellBg[1],cellBg[2],cellBg[3],cellBg[4])) nvgFill(ctx)
        nvgBeginPath(ctx) nvgRect(ctx, sx, sy, MED_W, MED_H)
        nvgStrokeColor(ctx, nvgRGBA(cellBorder[1],cellBorder[2],cellBorder[3],cellBorder[4]))
        nvgStrokeWidth(ctx, (isFlash or isHover) and 2.0 or 1.0) nvgStroke(ctx)

        -- 键位徽章（左上角圆形）
        local badgeR = math.max(5, MED_W * 0.15)
        local badgeX = sx + badgeR + 2
        local badgeY = sy + badgeR + 2
        nvgBeginPath(ctx)
        nvgCircle(ctx, badgeX, badgeY, badgeR)
        nvgFillColor(ctx, item and nvgRGBA(12,18,23,220) or nvgRGBA(10,15,20,140))
        nvgFill(ctx)
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, math.max(7, MED_W * 0.27))
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, item and nvgRGBA(220, 220, 248, 230) or nvgRGBA(80, 80, 100, 120))
        nvgText(ctx, badgeX, badgeY, tostring(i), nil)

        if item then
            -- 数量徽章（右上角，count > 1 时显示）
            if item.count > 1 then
                local qR = math.max(5, MED_W * 0.15)
                local qx = sx + MED_W - qR - 2
                local qy = sy + qR + 2
                nvgBeginPath(ctx) nvgCircle(ctx, qx, qy, qR)
                nvgFillColor(ctx, nvgRGBA(255, 107, 107, 200)) nvgFill(ctx)
                nvgFontFace(ctx, "bold") nvgFontSize(ctx, math.max(7, MED_W * 0.24))
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(255, 255, 255, 240))
                nvgText(ctx, qx, qy, tostring(item.count), nil)
            end

            -- 图标（居中）
            local medIconSize = math.max(14, MED_W * 0.52)
            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, medIconSize)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, isHover and 255 or 220))
            DrawItemIcon(ctx, item, sx + MED_W / 2, sy + MED_H * 0.44, medIconSize)

            -- 物品名（小字，截断）
            local name = tostring(item.name or "")
            if #name > 4 then name = string.sub(name, 1, 3) .. ".." end
            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, math.max(6, MED_W * 0.18))
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(170, 170, 195, 180))
            nvgText(ctx, sx + MED_W / 2, sy + MED_H * 0.72, name, nil)

            -- 回血量
            local pct = item.data.healPct or 0
            nvgFontFace(ctx, "bold")
            nvgFontSize(ctx, math.max(7, MED_W * 0.21))
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, medHealColor(pct))
            nvgText(ctx, sx + MED_W / 2, sy + MED_H * 0.88, string.format("+%d%%", math.floor(pct * 100)), nil)

            -- 底部稀有度彩条
            local r = item.rarity or 1
            local barPad = math.max(2, MED_W * 0.12)
            nvgBeginPath(ctx)
            nvgRect(ctx, sx + barPad, sy + MED_H - 3, MED_W - barPad * 2, 2)
            nvgFillColor(ctx, medRarityColor(r, isHover and 200 or 120))
            nvgFill(ctx)
        else
            -- 空格：居中 "—"
            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, math.max(10, MED_W * 0.36))
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(0, 160, 180, 60))
            nvgText(ctx, sx + MED_W / 2, sy + MED_H / 2, "—", nil)
        end

        -- 前摇进度弧（叠在格子上方）
        local cast = player.medCast
        if cast and cast.slotIdx == i then
            local progress  = 1.0 - (cast.timer / cast.duration)
            local arcR      = MED_W * 0.44
            local cx2       = sx + MED_W * 0.5
            local cy2       = sy + MED_H * 0.5

            -- 暗化遮罩
            nvgBeginPath(ctx)
            nvgRect(ctx, sx, sy, MED_W, MED_H)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 120))
            nvgFill(ctx)

            -- 进度背景轨道
            nvgBeginPath(ctx)
            nvgArc(ctx, cx2, cy2, arcR, -math.pi * 0.5, math.pi * 1.5, NVG_CW)
            nvgStrokeColor(ctx, nvgRGBA(0,240,255,40))
            nvgStrokeWidth(ctx, 3.0)
            nvgStroke(ctx)

            -- 进度前景弧
            local endAngle = -math.pi * 0.5 + progress * math.pi * 2.0
            nvgBeginPath(ctx)
            nvgArc(ctx, cx2, cy2, arcR, -math.pi * 0.5, endAngle, NVG_CW)
            nvgStrokeColor(ctx, nvgRGBA(80, 255, 140, 230))
            nvgStrokeWidth(ctx, 3.0)
            nvgStroke(ctx)

            -- 剩余秒数
            nvgFontFace(ctx, "bold")
            nvgFontSize(ctx, math.max(8, MED_W * 0.30))
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
            nvgText(ctx, cx2, cy2, string.format("%.1f", math.max(0, cast.timer)), nil)
        end
    end

    -- 标签（栏左侧，竖排小字）
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 9)
    nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(120, 120, 148, 140))
    nvgText(ctx, bx - 10, by + MED_H / 2 - 5, "医疗", nil)
    nvgText(ctx, bx - 10, by + MED_H / 2 + 7, "快用", nil)

    -- F 键触发（slotIdx==0）：在医疗栏下方画横向进度条
    local cast0 = player.medCast
    if cast0 and cast0.slotIdx == 0 then
        local progress = 1.0 - (cast0.timer / cast0.duration)
        local barW     = MED_N * MED_W + (MED_N - 1) * MED_GAP
        local barH     = 5
        local barX     = bx
        local barY     = by + MED_H + 6
        -- 背景
        nvgBeginPath(ctx)
        nvgRect(ctx, barX, barY, barW, barH)
        nvgFillColor(ctx, nvgRGBA(10, 15, 22, 190))
        nvgFill(ctx)
        -- 进度
        nvgBeginPath(ctx)
        nvgRect(ctx, barX, barY, barW * progress, barH)
        nvgFillColor(ctx, nvgRGBA(80, 255, 140, 220))
        nvgFill(ctx)
        -- 文字
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 10)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(ctx, nvgRGBA(200, 255, 210, 220))
        nvgText(ctx, barX + barW * 0.5, barY + barH + 3,
            (cast0.data.name or "?") .. "  " .. string.format("%.1f", math.max(0, cast0.timer)) .. "s", nil)
    end

    -- ── 打药中浮动提示（屏幕中下方） ────────────────────────────
    local castAny = player.medCast
    if castAny then
        local itemName = (castAny.data and castAny.data.name) or "药品"
        local remain   = math.max(0, castAny.timer)
        local pulse    = 0.82 + 0.18 * math.sin((elapsedTime or 0) * 6.0)  -- 呼吸闪烁
        local alpha    = math.floor(220 * pulse)

        -- 标签文字（两行）
        local line1 = "正在打药中"
        local line2 = itemName .. "  " .. string.format("%.1f", remain) .. "s"

        local cx   = sw * 0.5
        local cy   = sh - MED_H - MED_MRG - 52

        -- 背景胶囊
        local padX, padY = 18, 8
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 17)
        local tw1 = nvgTextBounds(ctx, 0, 0, line1, nil, nil)
        nvgFontSize(ctx, 12)
        local tw2 = nvgTextBounds(ctx, 0, 0, line2, nil, nil)
        local capW = math.max(tw1, tw2) + padX * 2
        local capH = 44
        nvgBeginPath(ctx)
        nvgRect(ctx, cx - capW * 0.5, cy - capH * 0.5, capW, capH)
        nvgFillColor(ctx, nvgRGBA(10,15,20,math.floor(210 * pulse)))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgRect(ctx, cx - capW * 0.5, cy - capH * 0.5, capW, capH)
        nvgStrokeColor(ctx, nvgRGBA(80, 255, 160, alpha))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)

        -- 第一行："正在打药中"（绿色）
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 17)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(80, 255, 160, alpha))
        nvgText(ctx, cx, cy - 9, line1, nil)

        -- 第二行：药品名 + 倒计时（白色）
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 12)
        nvgFillColor(ctx, nvgRGBA(200, 220, 210, math.floor(190 * pulse)))
        nvgText(ctx, cx, cy + 10, line2, nil)
    end
end

-- ============================================================================
-- 暂停菜单
-- ============================================================================
-- 按钮布局常量（复用于 Draw / HitTest）
-- 滑块几何参数（供 Draw 和 HitTest 共用）
local SLIDER_W     = 210   -- 滑块轨道宽度
local SLIDER_H     = 6     -- 轨道高度
local SLIDER_R     = 10    -- 拖动手柄半径

local function PauseLayout(sw, sh)
    local PW = math.min(360, math.max(260, sw - 24))
    local PH = math.min(400, math.max(220, sh - 24))
    local ys = PH / 400
    local px = math.floor((sw - PW) / 2)
    local py = math.floor((sh - PH) / 2)
    local btnW = math.min(260, PW - 48)
    local btnH = math.max(38, math.floor(48 * math.min(1, ys)))
    local btnX = px + (PW - btnW) / 2
    local sliderW = math.min(SLIDER_W, PW - 80)
    -- 滑块中心 X（与按钮居中对齐）
    local sliderCX = px + PW / 2
    local sliderLX = sliderCX - sliderW / 2
    return {
        px = px, py = py, PW = PW, PH = PH,
        -- 设置区：从标题下方 90px 开始
        settingsY     = py + 90 * ys,
        -- BGM 滑块（中心 Y）
        bgmLabelY     = py + 130 * ys,
        bgmSliderY    = py + 152 * ys,
        bgmSliderLX   = sliderLX,
        bgmSliderW    = sliderW,
        -- SFX 滑块
        sfxLabelY     = py + 194 * ys,
        sfxSliderY    = py + 216 * ys,
        sfxSliderLX   = sliderLX,
        sfxSliderW    = sliderW,
        -- 分隔线 Y
        dividerY      = py + 250 * ys,
        -- 按钮
        resume = { x = btnX, y = py + 272 * ys, w = btnW, h = btnH },
        menu   = { x = btnX, y = py + 334 * ys, w = btnW, h = btnH },
    }
end

-- 绘制单个音量滑块（供 DrawPauseMenu 调用）
-- lx, cy = 轨道左端 X, 轨道中心 Y；w = 轨道宽；val = 0~1；isDragging = bool
local function drawVolumeSlider(ctx, lx, cy, w, val, isDragging, label, icon)
    local fillW  = w * val
    local knobX  = lx + fillW

    -- 标签 + 图标（左对齐）
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(160, 220, 240, 200))
    nvgText(ctx, lx, cy - 18, icon .. "  " .. label, nil)

    -- 百分比（右对齐）
    nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0, 240, 255, isDragging and 255 or 180))
    nvgText(ctx, lx + w, cy - 18, math.floor(val * 100) .. "%", nil)

    -- 轨道背景
    nvgBeginPath(ctx)
    nvgRect(ctx, lx, cy - SLIDER_H/2, w, SLIDER_H)
    nvgFillColor(ctx, nvgRGBA(30, 50, 65, 200))
    nvgFill(ctx)

    -- 已填充部分
    if fillW > SLIDER_H then
        nvgBeginPath(ctx)
        nvgRect(ctx, lx, cy - SLIDER_H/2, fillW, SLIDER_H)
        nvgFillColor(ctx, nvgRGBA(0, 220, 240, 220))
        nvgFill(ctx)
    end

    -- 轨道边框
    nvgBeginPath(ctx)
    nvgRect(ctx, lx, cy - SLIDER_H/2, w, SLIDER_H)
    nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, 50))
    nvgStrokeWidth(ctx, 0.8) nvgStroke(ctx)

    -- 手柄
    local hR = isDragging and (SLIDER_R + 2) or SLIDER_R
    -- 手柄发光
    local hGlow = nvgRadialGradient(ctx, knobX, cy, hR * 0.3, hR * 2.2,
        nvgRGBA(0, 240, 255, isDragging and 80 or 40), nvgRGBA(0, 240, 255, 0))
    nvgBeginPath(ctx) nvgCircle(ctx, knobX, cy, hR * 2.0)
    nvgFillPaint(ctx, hGlow) nvgFill(ctx)
    -- 手柄主体
    nvgBeginPath(ctx) nvgCircle(ctx, knobX, cy, hR)
    nvgFillColor(ctx, nvgRGBA(isDragging and 160 or 20, isDragging and 248 or 240, 255, 255))
    nvgFill(ctx)
    -- 手柄边框
    nvgBeginPath(ctx) nvgCircle(ctx, knobX, cy, hR)
    nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, isDragging and 255 or 200))
    nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)
    -- 手柄内芯
    nvgBeginPath(ctx) nvgCircle(ctx, knobX, cy, hR * 0.35)
    nvgFillColor(ctx, nvgRGBA(0, 200, 230, 255))
    nvgFill(ctx)
end

function M.DrawPauseMenu(ctx, sw, sh, time, hoveredBtn, bgmVol, sfxVol, dragState)
    bgmVol   = bgmVol   or 0.55
    sfxVol   = sfxVol   or 0.85
    dragState = dragState or {}

    -- ── 全屏半透明遮罩 ───────────────────────────────────────────
    nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, sh)
    local maskG = nvgLinearGradient(ctx, 0, 0, 0, sh,
        nvgRGBA(5, 8, 12, 200), nvgRGBA(8, 12, 18, 220))
    nvgFillPaint(ctx, maskG) nvgFill(ctx)

    -- 扫描线
    for y = 0, sh, 5 do
        nvgBeginPath(ctx) nvgMoveTo(ctx, 0, y) nvgLineTo(ctx, sw, y)
        nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, 3))
        nvgStrokeWidth(ctx, 0.5) nvgStroke(ctx)
    end

    local L = PauseLayout(sw, sh)
    local px, py, PW, PH = L.px, L.py, L.PW, L.PH

    -- ── 面板主体（像素风硬边） ─────────────────────────────────────
    PixelUI.DrawPanel(ctx, px, py, PW, PH, {
        bg = {10, 16, 22, 245},
        noiseAlpha = 16,
        borderColor = {0, 240, 255, 80},
    })

    -- ── 标题 "// PAUSED //" ─────────────────────────────────────
    local titleY = py + 46
    local glowA  = math.floor(60 + 30 * math.sin(time * 2.0))
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 26)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for d = 1, 3 do
        nvgFillColor(ctx, nvgRGBA(0, 240, 255, math.floor(glowA / d)))
        nvgText(ctx, px + PW/2 + d, titleY + d, "// PAUSED //", nil)
        nvgText(ctx, px + PW/2 - d, titleY - d, "// PAUSED //", nil)
    end
    nvgFillColor(ctx, nvgRGBA(220, 248, 255, 255))
    nvgText(ctx, px + PW/2, titleY, "// PAUSED //", nil)

    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
    nvgFillColor(ctx, nvgRGBA(0, 200, 220, 130))
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(ctx, px + PW/2, titleY + 24, "点击「继续游戏」或按 ESC 继续", nil)

    -- ── 音量设置区标题 ──────────────────────────────────────────
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0, 200, 220, 160))
    nvgText(ctx, px + PW/2, L.settingsY, "⚙  音量设置", nil)

    -- BGM 滑块
    drawVolumeSlider(ctx,
        L.bgmSliderLX, L.bgmSliderY, L.bgmSliderW,
        bgmVol, dragState.target == "bgm",
        "背景音乐", "♪")

    -- SFX 滑块
    drawVolumeSlider(ctx,
        L.sfxSliderLX, L.sfxSliderY, L.sfxSliderW,
        sfxVol, dragState.target == "sfx",
        "游戏音效", "◈")

    -- ── 分隔线 ───────────────────────────────────────────────────
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, px + 20, L.dividerY)
    nvgLineTo(ctx, px + PW - 20, L.dividerY)
    nvgStrokeColor(ctx, nvgRGBA(0, 240, 255, 30)) nvgStrokeWidth(ctx, 1.0) nvgStroke(ctx)

    -- ── 按钮渲染（像素风） ─────────────────────────────────────────
    local function drawBtn(btn, label, icon, isHover, isPrimary)
        local r = isPrimary and 0   or 255
        local g = isPrimary and 240 or 107
        local b = isPrimary and 255 or 107
        local state = isHover and "hover" or "normal"

        PixelUI.DrawButton(ctx, btn.x, btn.y, btn.w, btn.h, state, {
            bg = {10, 16, 22, 200},
            bg_hover = {r, g, b, 30},
            borderColor = isHover and {r, g, b, 220} or {r, g, b, 70},
        })

        nvgFontFace(ctx, isHover and "bold" or "sans")
        nvgFontSize(ctx, 15)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(r, g, b, isHover and 255 or 200))
        nvgText(ctx, btn.x + btn.w/2, btn.y + btn.h/2, icon .. "  " .. label, nil)
    end

    drawBtn(L.resume, "继续游戏",  "▶", hoveredBtn == "resume", true)
    drawBtn(L.menu,   "返回主菜单","⏏", hoveredBtn == "menu",   false)

    -- ── 底部提示 ─────────────────────────────────────────────────
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0, 160, 180, 80))
    nvgText(ctx, px + PW/2, py + PH - 14, "返回主菜单将结束本次行动，所有物品将会丢失", nil)
end

-- 鼠标悬停检测（按钮）
function M.GetPauseMenuHover(mx, my, sw, sh)
    local L = PauseLayout(sw, sh)
    local r = L.resume
    if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
        return "resume"
    end
    local m = L.menu
    if mx >= m.x and mx <= m.x + m.w and my >= m.y and my <= m.y + m.h then
        return "menu"
    end
    return nil
end

-- 点击命中测试（与 Hover 相同逻辑，单独导出供 main 调用）
function M.HitTestPauseMenu(mx, my, sw, sh)
    return M.GetPauseMenuHover(mx, my, sw, sh)
end

-- 检测鼠标是否落在某个滑块的可拖动区域（轨道 ±12px 高度带），返回 "bgm"/"sfx"/nil
function M.HitTestPauseSlider(mx, my, sw, sh)
    local L = PauseLayout(sw, sh)
    local hitH = 14  -- 轨道命中高度（上下各 7px）

    -- BGM 轨道区域
    if mx >= L.bgmSliderLX and mx <= L.bgmSliderLX + L.bgmSliderW
       and my >= L.bgmSliderY - hitH and my <= L.bgmSliderY + hitH then
        return "bgm"
    end
    -- SFX 轨道区域
    if mx >= L.sfxSliderLX and mx <= L.sfxSliderLX + L.sfxSliderW
       and my >= L.sfxSliderY - hitH and my <= L.sfxSliderY + hitH then
        return "sfx"
    end
    return nil
end

-- 根据鼠标 X 坐标计算滑块值（0~1），供拖动逻辑调用
function M.CalcSliderValue(mx, sw, sh, sliderTarget)
    local L = PauseLayout(sw, sh)
    local lx = sliderTarget == "bgm" and L.bgmSliderLX or L.sfxSliderLX
    local w  = sliderTarget == "bgm" and L.bgmSliderW  or L.sfxSliderW
    local v  = (mx - lx) / w
    return math.max(0, math.min(1, v))
end

-- ============================================================================
-- 狙击枪红外预瞄效果：激光线 + 狙击镜框
-- 仅在玩家持狙击枪时绘制（ammoType == "sniper"）
-- ============================================================================
function M.DrawSniperEffects(ctx, player, camX, camY, sw, sh)
    local wpn = player.weapon
    if not wpn or wpn.ammoType ~= "sniper" then return end

    local sx  = player.x - camX
    local sy  = player.y - camY
    local ang = player.aimAngle
    local nx  = math.cos(ang)
    local ny  = math.sin(ang)

    -- ── 红外激光线（射线检测碰墙）──────────────────────────────
    local LASER_MAX = 480
    local STEP      = 5
    local hitX = sx + nx * LASER_MAX
    local hitY = sy + ny * LASER_MAX
    for d = 16, LASER_MAX, STEP do
        local wx = player.x + nx * d
        local wy = player.y + ny * d
        if World.IsWall(wx, wy) then
            hitX = sx + nx * d
            hitY = sy + ny * d
            break
        end
    end

    local muzzleX = sx + nx * 16
    local muzzleY = sy + ny * 16

    -- 激光线（枪口→命中点，红色渐隐）
    local laserPaint = nvgLinearGradient(ctx, muzzleX, muzzleY, hitX, hitY,
        nvgRGBA(255, 40, 40, 210), nvgRGBA(255, 40, 40, 0))
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, muzzleX, muzzleY)
    nvgLineTo(ctx, hitX, hitY)
    nvgStrokePaint(ctx, laserPaint)
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)

    -- 命中点发光圆点
    local dotPaint = nvgRadialGradient(ctx, hitX, hitY, 1, 10,
        nvgRGBA(255, 80, 80, 230), nvgRGBA(255, 0, 0, 0))
    nvgBeginPath(ctx)
    nvgCircle(ctx, hitX, hitY, 10)
    nvgFillPaint(ctx, dotPaint)
    nvgFill(ctx)
    -- 中心小亮点
    nvgBeginPath(ctx)
    nvgCircle(ctx, hitX, hitY, 2.5)
    nvgFillColor(ctx, nvgRGBA(255, 180, 180, 255))
    nvgFill(ctx)
end

-- ============================================================================
-- Build 通知横幅（阈值突破 / 联动解锁）
-- notif: { text, timer, color={r,g,b} }，timer 由调用方每帧 -dt
-- 显示在屏幕顶部居中，淡入淡出
-- ============================================================================
function M.DrawBuildNotification(ctx, notif, sw, sh)
    if not notif or not notif.timer or notif.timer <= 0 then return end

    local SHOW  = 0.35   -- 淡入时长
    local FADE  = 0.55   -- 淡出时长
    local TOTAL = 4.0    -- 默认总时长（以 notif.totalTime 为准）
    local total = notif.totalTime or TOTAL

    local alpha
    local elapsed = total - notif.timer
    if elapsed < SHOW then
        alpha = elapsed / SHOW
    elseif notif.timer < FADE then
        alpha = notif.timer / FADE
    else
        alpha = 1.0
    end
    alpha = math.max(0, math.min(1, alpha))

    local cr = (notif.color and notif.color[1]) or 255
    local cg = (notif.color and notif.color[2]) or 220
    local cb = (notif.color and notif.color[3]) or  60

    local text  = notif.text or ""
    local bw    = math.min(sw * 0.72, 520)
    local bh    = 46
    local bx    = sw / 2 - bw / 2
    local by    = sh * 0.07 + (1 - alpha) * (-bh - 10)   -- 从顶部滑入

    -- 硬阴影（像素偏移）
    nvgBeginPath(ctx) nvgRect(ctx, bx + 2, by + 2, bw, bh)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(120 * alpha))) nvgFill(ctx)

    -- 背景
    nvgBeginPath(ctx) nvgRect(ctx, bx, by, bw, bh)
    nvgFillColor(ctx, nvgRGBA(8, 12, 18, math.floor(220 * alpha))) nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(cr, cg, cb, math.floor(180 * alpha)))
    nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)

    -- 顶部色条
    nvgBeginPath(ctx) nvgRect(ctx, bx, by, bw, 3)
    nvgFillColor(ctx, nvgRGBA(cr, cg, cb, math.floor(200 * alpha))) nvgFill(ctx)

    -- 文字
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 发光描边
    nvgFillColor(ctx, nvgRGBA(cr, cg, cb, math.floor(60 * alpha)))
    nvgText(ctx, sw/2 + 1, by + bh/2 + 1, text, nil)
    -- 主文字
    nvgFillColor(ctx, nvgRGBA(240, 248, 255, math.floor(255 * alpha)))
    nvgText(ctx, sw/2, by + bh/2, text, nil)
end

-- ============================================================================
-- 物品 Tooltip 浮窗（悬停/长按时显示）
-- ============================================================================
function M.DrawItemTooltip(ctx, tooltipInfo, posX, posY, sw, sh)
    if not tooltipInfo then return end

    local PAD_X = 10
    local PAD_Y = 8
    local LINE_H = 16
    local TITLE_H = 22
    local DESC_H = 14
    local MAX_W = 180

    -- 计算内容高度
    local statsCount = #tooltipInfo.stats
    local hasDesc = tooltipInfo.desc and #tooltipInfo.desc > 0
    local contentH = TITLE_H + statsCount * LINE_H + (hasDesc and (DESC_H + 6) or 0)
    local totalH = contentH + PAD_Y * 2
    local totalW = MAX_W

    -- 自动定位（避免超出屏幕）
    local tx = posX + 12
    local ty = posY - totalH - 4
    if ty < 4 then ty = posY + 20 end
    if tx + totalW > sw - 4 then tx = sw - 4 - totalW end
    if tx < 4 then tx = 4 end
    if ty + totalH > sh - 4 then ty = sh - 4 - totalH end

    -- 背景（像素风 Tooltip）
    PixelUI.DrawTooltip(ctx, tx, ty, totalW, totalH)

    local cx = tx + PAD_X
    local cy = ty + PAD_Y

    -- 标题（稀有度颜色）
    local r, g, b = RC(tooltipInfo.rarity or 1)
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(r, g, b, 255))
    nvgText(ctx, cx, cy, tooltipInfo.title or "???", nil)
    cy = cy + TITLE_H

    -- 属性行
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
    for _, stat in ipairs(tooltipInfo.stats) do
        -- label
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(ctx, nvgRGBA(160, 170, 190, 220))
        nvgText(ctx, cx, cy, stat.label .. ":", nil)
        -- value
        nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(ctx, nvgRGBA(230, 240, 255, 240))
        nvgText(ctx, tx + totalW - PAD_X, cy, stat.value, nil)
        cy = cy + LINE_H
    end

    -- 描述文字
    if hasDesc then
        cy = cy + 4
        nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(ctx, nvgRGBA(140, 160, 180, 180))
        nvgText(ctx, cx, cy, tooltipInfo.desc, nil)
    end
end

-- ============================================================================
-- 大厅（Lobby）— 可走动场景，替代静态 Hub
-- ============================================================================
local Lobby = nil  -- 延迟加载，避免循环依赖

local lobbyFacilityImages = {}  -- 缓存 NanoVG 图片句柄

--- 获取 Lobby 模块（延迟加载）
local function GetLobby()
    if not Lobby then Lobby = require("Lobby") end
    return Lobby
end

--- 绘制大厅地图（地板+墙壁）
-- 大厅专用贴图缓存
local lobbyFloorImg = nil
local lobbyWallImg = nil
local lobbyWallTopImg = nil

function M.DrawLobbyMap(ctx, camX, camY, vw, vh)
    local lobby = GetLobby()
    local TL = lobby.TILE

    -- 惰性加载大厅贴图
    if not lobbyFloorImg then
        lobbyFloorImg = nvgCreateImage(ctx, "image/lobby/floor.png", NVG_IMAGE_NEAREST | NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY)
    end
    if not lobbyWallImg then
        lobbyWallImg = nvgCreateImage(ctx, "image/lobby/wall.png", NVG_IMAGE_NEAREST | NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY)
    end
    if not lobbyWallTopImg then
        lobbyWallTopImg = nvgCreateImage(ctx, "image/lobby/wall_top.png", NVG_IMAGE_NEAREST | NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY)
    end

    local startCol = math.max(1, math.floor(camX / TL) + 1)
    local endCol   = math.min(lobby.COLS, math.ceil((camX + vw) / TL) + 1)
    local startRow = math.max(1, math.floor(camY / TL) + 1)
    local endRow   = math.min(lobby.ROWS, math.ceil((camY + vh) / TL) + 1)

    for row = startRow, endRow do
        for col = startCol, endCol do
            local tile = lobby.cells[row][col]
            local wx = (col - 1) * TL - camX
            local wy = (row - 1) * TL - camY

            if tile == 0 then
                -- 地板：木质/石板贴图，有则用，无则 fallback 棋盘色
                if lobbyFloorImg and lobbyFloorImg ~= 0 then
                    local pat = nvgImagePattern(ctx, wx, wy, TL, TL, 0, lobbyFloorImg, 1.0)
                    nvgBeginPath(ctx) nvgRect(ctx, wx, wy, TL, TL)
                    nvgFillPaint(ctx, pat) nvgFill(ctx)
                else
                    nvgBeginPath(ctx) nvgRect(ctx, wx, wy, TL, TL)
                    local checker = ((col + row) % 2 == 0) and 38 or 34
                    nvgFillColor(ctx, nvgRGBA(checker + 8, checker + 4, checker, 255))
                    nvgFill(ctx)
                end
                -- 微弱格线
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, wx, wy) nvgLineTo(ctx, wx + TL, wy)
                nvgMoveTo(ctx, wx, wy) nvgLineTo(ctx, wx, wy + TL)
                nvgStrokeColor(ctx, nvgRGBA(60, 50, 40, 30))
                nvgStrokeWidth(ctx, 0.5)
                nvgStroke(ctx)
            elseif tile == 1 then
                -- 墙壁
                local belowIsFloor = (row >= lobby.ROWS) or (lobby.cells[row + 1][col] ~= 1)
                if belowIsFloor then
                    -- 墙面（暴露面）
                    if lobbyWallImg and lobbyWallImg ~= 0 then
                        local pat = nvgImagePattern(ctx, wx, wy, TL, TL, 0, lobbyWallImg, 1.0)
                        nvgBeginPath(ctx) nvgRect(ctx, wx, wy, TL, TL)
                        nvgFillPaint(ctx, pat) nvgFill(ctx)
                    else
                        nvgBeginPath(ctx) nvgRect(ctx, wx, wy, TL, TL)
                        nvgFillColor(ctx, nvgRGBA(55, 45, 35, 255))
                        nvgFill(ctx)
                    end
                else
                    -- 墙顶
                    local adjFloor = false
                    for dr = -1, 1 do
                        for dc = -1, 1 do
                            if dr ~= 0 or dc ~= 0 then
                                local nr, nc = row + dr, col + dc
                                if nr >= 1 and nr <= lobby.ROWS and nc >= 1 and nc <= lobby.COLS then
                                    if lobby.cells[nr][nc] ~= 1 then adjFloor = true end
                                end
                            end
                            if adjFloor then break end
                        end
                        if adjFloor then break end
                    end
                    if adjFloor then
                        if lobbyWallTopImg and lobbyWallTopImg ~= 0 then
                            local pat2 = nvgImagePattern(ctx, wx, wy, TL, TL, 0, lobbyWallTopImg, 1.0)
                            nvgBeginPath(ctx) nvgRect(ctx, wx, wy, TL, TL)
                            nvgFillPaint(ctx, pat2) nvgFill(ctx)
                        else
                            nvgBeginPath(ctx) nvgRect(ctx, wx, wy, TL, TL)
                            nvgFillColor(ctx, nvgRGBA(40, 32, 26, 255))
                            nvgFill(ctx)
                        end
                    else
                        -- 外围黑色
                        nvgBeginPath(ctx) nvgRect(ctx, wx, wy, TL, TL)
                        nvgFillColor(ctx, nvgRGBA(5, 5, 8, 255))
                        nvgFill(ctx)
                    end
                end
            end
        end
    end
end

--- 绘制大厅设施精灵
function M.DrawLobbyFacilities(ctx, camX, camY)
    local lobby = GetLobby()
    local TL = lobby.TILE

    for _, f in ipairs(lobby.facilities) do
        -- 设施中心的像素位置
        local centerPX = (f.gx + f.w * 0.5) * TL - camX
        local centerPY = (f.gy + f.h * 0.5) * TL - camY

        -- 加载图片（仅第一次）
        if not lobbyFacilityImages[f.id] then
            lobbyFacilityImages[f.id] = nvgCreateImage(ctx, f.imagePath, NVG_IMAGE_NEAREST)
        end
        local img = lobbyFacilityImages[f.id]

        if img and img > 0 then
            -- 绘制设施精灵（居中于设施格子区域）
            local dw, dh = f.drawW, f.drawH
            local dx = centerPX - dw * 0.5 + (f.offsetX or 0)
            local dy = centerPY - dh * 0.5 + (f.offsetY or 0)
            local pat = nvgImagePattern(ctx, dx, dy, dw, dh, 0, img, 1.0)
            nvgBeginPath(ctx) nvgRect(ctx, dx, dy, dw, dh)
            nvgFillPaint(ctx, pat) nvgFill(ctx)
        else
            -- 图片加载失败时绘制占位方块
            local bw = f.w * TL
            local bh = f.h * TL
            local bx = f.gx * TL - camX
            local by = f.gy * TL - camY
            nvgBeginPath(ctx) nvgRect(ctx, bx, by, bw, bh)
            nvgFillColor(ctx, nvgRGBA(60, 80, 100, 120))
            nvgFill(ctx)
            -- 设施名字
            nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(200, 220, 240, 200))
            nvgText(ctx, bx + bw * 0.5, by + bh * 0.5, f.name, nil)
        end
    end
end

--- 绘制大厅中的玩家角色
-- 大厅玩家帧动画状态（复用地牢柴犬 spritesheet）
---@type integer
local lobbyPlayerWalkImg = nil
---@type integer
local lobbyPlayerIdleImg = nil
local lobbyAnimTimer = 0
local lobbyAnimFrame = 0
local lobbyIdleTimer = 0
local lobbyIdleFrame = 0
local lobbyPlayerMoving = false

function M.DrawLobbyPlayer(ctx, camX, camY)
    local lobby = GetLobby()
    local px = lobby.playerX - camX
    local py = lobby.playerY - camY

    -- 初始化 spritesheet（只加载一次）
    if not lobbyPlayerWalkImg then
        lobbyPlayerWalkImg = nvgCreateImage(ctx, "image/rika_2230ae74.png", 0)
        lobbyPlayerIdleImg = nvgCreateImage(ctx, "image/rika_d3249e66.png", 0)
    end

    -- 判断是否在移动
    local keys = lobby._lastKeys or {}
    local isMoving = (keys.w or keys.s or keys.a or keys.d) and true or false
    lobbyPlayerMoving = isMoving

    -- 动画帧更新（walk 7帧，idle 8帧）
    local useIdle
    if isMoving then
        useIdle = false
        lobbyAnimTimer = lobbyAnimTimer + M.dt * 12
        if lobbyAnimTimer >= 1.0 then
            lobbyAnimTimer = lobbyAnimTimer - 1.0
            lobbyAnimFrame = (lobbyAnimFrame + 1) % 6
        end
        lobbyIdleFrame = 0
        lobbyIdleTimer = 0
    else
        useIdle = true
        lobbyIdleTimer = lobbyIdleTimer + M.dt * 10.5
        if lobbyIdleTimer >= 1.0 then
            lobbyIdleTimer = lobbyIdleTimer - 1.0
            lobbyIdleFrame = (lobbyIdleFrame + 1) % 8
        end
        lobbyAnimFrame = 0
        lobbyAnimTimer = 0
    end

    -- 选择帧
    local frameIdx = useIdle and lobbyIdleFrame or lobbyAnimFrame
    local frameCol = frameIdx % 4
    local row = math.floor(frameIdx / 4)
    local curImg = useIdle and lobbyPlayerIdleImg or lobbyPlayerWalkImg

    local DRAW_SIZE = 82
    local FRAME_W, FRAME_H = 256, 256
    local scaleX = DRAW_SIZE / FRAME_W
    local SHEET_H = useIdle and 512 or 768  -- idle: 4x2, walk: 4x3
    local totalW = 1024 * scaleX
    local totalH = SHEET_H * scaleX

    -- 脚下阴影
    nvgBeginPath(ctx)
    nvgEllipse(ctx, px, py + 20, 15, 5)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 45))
    nvgFill(ctx)

    nvgSave(ctx)

    -- 根据朝向翻转（左/右）
    local angle = lobby.playerAngle
    local facingLeft = (angle > math.pi * 0.5 and angle <= math.pi * 1.5)
                    or (angle < -math.pi * 0.5 and angle >= -math.pi * 1.5)
    -- 简化：a键朝左翻转
    if angle == math.pi then
        facingLeft = true
    end
    if facingLeft then
        nvgTranslate(ctx, px, py)
        nvgScale(ctx, -1, 1)
        nvgTranslate(ctx, -px, -py)
    end

    local pat = nvgImagePattern(ctx,
        px - DRAW_SIZE * 0.5 - frameCol * DRAW_SIZE,
        py - DRAW_SIZE * 0.5 - row * DRAW_SIZE,
        totalW, totalH, 0, curImg, 1.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, px - DRAW_SIZE * 0.5, py - DRAW_SIZE * 0.5, DRAW_SIZE, DRAW_SIZE)
    nvgFillPaint(ctx, pat)
    nvgFill(ctx)

    nvgRestore(ctx)
end

--- 绘制交互提示（[E] 标记 + 底部提示栏）
function M.DrawLobbyInteractionPrompt(ctx, camX, camY, sw, sh, time)
    local lobby = GetLobby()
    local f = lobby.nearestFacility
    if not f then return end

    local TL = lobby.TILE
    -- 设施中心屏幕坐标
    local fx = (f.gx + f.w * 0.5) * TL - camX
    local fy = f.gy * TL - camY  -- 顶部

    -- [E] 浮动标记（设施上方）
    local bobY = math.sin((time or 0) * 3.0) * 3  -- 轻微上下浮动
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)

    -- 背景圆角矩形
    local tagW, tagH = 28, 20
    local tagX = fx - tagW * 0.5
    local tagY = fy - 28 + bobY - tagH
    nvgBeginPath(ctx) nvgRoundedRect(ctx, tagX, tagY, tagW, tagH, 4)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 180)) nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(255, 220, 80, 200))
    nvgStrokeWidth(ctx, 1.5) nvgStroke(ctx)

    nvgFillColor(ctx, nvgRGBA(255, 220, 80, 255))
    nvgText(ctx, fx, fy - 28 + bobY, "E", nil)

    -- 底部提示栏（屏幕空间，不受相机缩放影响 → 在缩放外绘制）
    -- 注意：此函数在相机缩放空间内被调用，底栏需要在外部绘制
    -- 这里仅绘制设施上方的 E 标记，底栏由 DrawLobbyBottomBar 处理
end

--- 绘制底部交互提示栏（屏幕空间，不受相机缩放）
function M.DrawLobbyBottomBar(ctx, sw, sh)
    local lobby = GetLobby()
    local f = lobby.nearestFacility
    if not f then return end

    local barH = 36
    local barY = sh - barH

    -- 半透明黑底
    nvgBeginPath(ctx) nvgRect(ctx, 0, barY, sw, barH)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 180)) nvgFill(ctx)
    -- 上边线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, 0, barY) nvgLineTo(ctx, sw, barY)
    nvgStrokeColor(ctx, nvgRGBA(80, 90, 100, 120))
    nvgStrokeWidth(ctx, 1) nvgStroke(ctx)

    -- 提示文字
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 220, 80, 240))
    nvgText(ctx, sw * 0.5, barY + barH * 0.5,
        "[E] " .. f.name, nil)
end

--- 绘制大厅 HUD（左上角金币、右上角返回按钮）
function M.DrawLobbyHUD(ctx, sw, sh, stash, hubHover)
    -- 左上角玩家信息
    local panelX, panelY = 12, 10
    local panelW, panelH = 160, 50
    nvgBeginPath(ctx) nvgRoundedRect(ctx, panelX, panelY, panelW, panelH, 6)
    nvgFillColor(ctx, nvgRGBA(10, 12, 16, 200)) nvgFill(ctx)

    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 220, 80, 255))
    nvgText(ctx, panelX + 10, panelY + 18, "🐱 修勾", nil)

    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 12)
    nvgFillColor(ctx, nvgRGBA(255, 215, 60, 220))
    local moneyStr = tostring(stash and stash.money or 0)
    nvgText(ctx, panelX + 10, panelY + 38, "💰 " .. moneyStr, nil)

    -- 右上角返回按钮
    local bb = M.GetLobbyBackBtnRect(sw, sh)
    local backHover = (hubHover == "back")
    nvgBeginPath(ctx) nvgRoundedRect(ctx, bb.x, bb.y, bb.w, bb.h, 4)
    if backHover then
        nvgFillColor(ctx, nvgRGBA(50, 55, 60, 220))
    else
        nvgFillColor(ctx, nvgRGBA(30, 35, 40, 180))
    end
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(100, 110, 120, backHover and 200 or 100))
    nvgStrokeWidth(ctx, 1) nvgStroke(ctx)

    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(200, 210, 220, backHover and 255 or 180))
    nvgText(ctx, bb.x + bb.w * 0.5, bb.y + bb.h * 0.5, "← 返回", nil)
end

--- 大厅返回按钮矩形
function M.GetLobbyBackBtnRect(sw, sh)
    return { x = sw - 90, y = 12, w = 72, h = 32 }
end

--- 大厅 HUD 点击检测
function M.HitTestLobby(mx, my, sw, sh)
    local bb = M.GetLobbyBackBtnRect(sw, sh)
    if mx >= bb.x and mx <= bb.x + bb.w and my >= bb.y and my <= bb.y + bb.h then
        return "back"
    end
    return nil
end

-- ============================================================================
-- 主界面（Hub）— 保留旧代码以兼容
-- ============================================================================

-- Hub 侧栏按钮定义（暂无实际功能，预留入口）
local HUB_SIDEBAR = {
    { key="skill",    label="技能树",  icon="🌳" },
    { key="stash",    label="仓库",    icon="📦" },
    { key="showcase", label="陈列柜",  icon="🏆" },
}

-- Hub 右下主按钮
local HUB_MAIN_BTN = { w=180, h=52 }

--- 获取Hub主按钮矩形
function M.GetHubMainBtnRect(sw, sh)
    local bx = sw - HUB_MAIN_BTN.w - 32
    local by = sh - HUB_MAIN_BTN.h - 32
    return { x=bx, y=by, w=HUB_MAIN_BTN.w, h=HUB_MAIN_BTN.h }
end

--- 获取Hub侧栏按钮矩形列表
function M.GetHubSidebarRects(sw, sh)
    local rects = {}
    local btnW, btnH, gap = 88, 40, 10
    local baseX, baseY = 24, 100
    for i, btn in ipairs(HUB_SIDEBAR) do
        rects[i] = {
            key = btn.key, label = btn.label, icon = btn.icon,
            x = baseX, y = baseY + (i-1)*(btnH+gap), w = btnW, h = btnH
        }
    end
    return rects
end

--- 获取Hub返回按钮矩形
function M.GetHubBackBtnRect(sw, sh)
    return { x=sw - 90, y=12, w=72, h=32 }
end

--- Hub 点击检测
function M.HitTestHub(mx, my, sw, sh)
    -- 主按钮
    local mb = M.GetHubMainBtnRect(sw, sh)
    if mx >= mb.x and mx <= mb.x+mb.w and my >= mb.y and my <= mb.y+mb.h then
        return "start_raid"
    end
    -- 返回
    local bb = M.GetHubBackBtnRect(sw, sh)
    if mx >= bb.x and mx <= bb.x+bb.w and my >= bb.y and my <= bb.y+bb.h then
        return "back"
    end
    -- 侧栏
    local sbRects = M.GetHubSidebarRects(sw, sh)
    for _, r in ipairs(sbRects) do
        if mx >= r.x and mx <= r.x+r.w and my >= r.y and my <= r.y+r.h then
            return r.key
        end
    end
    return nil
end

--- 绘制主界面
function M.DrawHub(ctx, sw, sh, stash, time, hubHover)
    -- ── 背景 ──────────────────────────────────────────────
    nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, sh)
    nvgFillColor(ctx, nvgRGBA(12, 14, 18, 255)) nvgFill(ctx)

    -- 武器剪影纹理（重复排列，极低透明度）
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 36)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local weaponGlyphs = {"🔫", "🗡️", "💣"}
    for row = 0, math.ceil(sh/72) do
        for col = 0, math.ceil(sw/72) do
            local idx = ((row + col) % #weaponGlyphs) + 1
            nvgFillColor(ctx, nvgRGBA(60, 70, 80, 16))
            nvgText(ctx, col*72 + 10, row*72 + 10, weaponGlyphs[idx], nil)
        end
    end

    -- ── 左上玩家信息面板（像素风） ──────────────────────────────────
    local panelX, panelY = 20, 16
    local panelW, panelH = 200, 90
    PixelUI.DrawPanel(ctx, panelX, panelY, panelW, panelH, {
        bg = {15, 20, 25, 220},
        borderColor = {80, 90, 100, 120},
        shadow = false,
        noiseAlpha = 10,
    })

    -- 头像+名字
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 220, 80, 255))
    nvgText(ctx, panelX + 12, panelY + 20, "🐱 修勾", nil)

    -- 金币
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 14)
    nvgFillColor(ctx, nvgRGBA(255, 215, 60, 230))
    local moneyDispStr = M.FormatMoney and M.FormatMoney(stash.money) or tostring(stash.money)
    local moneyIconEndX = drawMoneyIcon(ctx, panelX + 12, panelY + 44, 14)
    nvgText(ctx, moneyIconEndX, panelY + 44, moneyDispStr, nil)

    -- 仓库等级
    nvgFillColor(ctx, nvgRGBA(160, 200, 220, 200))
    nvgText(ctx, panelX + 12, panelY + 68, string.format("📦 仓库 Lv.%d", stash.level), nil)

    -- ── 左侧导航栏 ───────────────────────────────────────
    local sbRects = M.GetHubSidebarRects(sw, sh)
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 13)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    for _, r in ipairs(sbRects) do
        local hovered = (hubHover == r.key)
        local state = hovered and "hover" or "normal"
        PixelUI.DrawButton(ctx, r.x, r.y, r.w, r.h, state, {
            bg = {20, 25, 30, 180},
            bg_hover = {50, 60, 70, 200},
            borderColor = hovered and {80, 100, 120, 180} or {80, 100, 120, 80},
        })
        if hovered then nvgFillColor(ctx, nvgRGBA(255, 230, 120, 255))
        else nvgFillColor(ctx, nvgRGBA(180, 200, 220, 220)) end
        nvgText(ctx, r.x + 10, r.y + r.h*0.5, r.icon .. " " .. r.label, nil)
    end



    -- ── 右下主按钮："开始搜刮" ────────────────────────────
    local mb = M.GetHubMainBtnRect(sw, sh)
    local mainHover = (hubHover == "start_raid")
    local mainState = mainHover and "hover" or "normal"
    -- 像素风主按钮（红色强调）
    PixelUI.DrawButton(ctx, mb.x, mb.y, mb.w, mb.h, mainState, {
        bg = {180, 40, 35, 240},
        bg_hover = {220, 50, 40, 255},
        borderColor = mainHover and {255, 100, 80, 255} or {255, 100, 80, 140},
        noiseAlpha = 20,
    })
    -- 按钮文字
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 18)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, mb.x + mb.w*0.5, mb.y + mb.h*0.5, "开始搜刮", nil)

    -- ── 右上返回按钮（像素风） ─────────────────────────────────────
    local bb = M.GetHubBackBtnRect(sw, sh)
    local backHover = (hubHover == "back")
    PixelUI.DrawButton(ctx, bb.x, bb.y, bb.w, bb.h, backHover and "hover" or "normal", {
        bg = {30, 35, 40, 160},
        bg_hover = {30, 35, 40, 220},
        borderColor = backHover and {120, 130, 140, 200} or {120, 130, 140, 100},
    })
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(200, 210, 220, backHover and 255 or 180))
    nvgText(ctx, bb.x + bb.w*0.5, bb.y + bb.h*0.5, "← 返回", nil)

    -- 版本号
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
    nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, nvgRGBA(100, 110, 120, 100))
    nvgText(ctx, sw - 10, sh - 8, "v1.0", nil)
end

return M
