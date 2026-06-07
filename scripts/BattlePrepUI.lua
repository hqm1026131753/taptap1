-- BattlePrepUI.lua
-- 战前准备页面新 UI（基于用户提供的 NanoVG 设计稿）
-- 设计基准: 1470×1080，自动缩放适配任意屏幕
--
-- 接口:
--   BattlePrepUI.Draw(vg, SW, SH, data)
--   BattlePrepUI.HitTest(mx, my, SW, SH) -> string|nil
--   BattlePrepUI.BuildData(stash, loadoutState) -> data table

local M = {}

-- ============================================================================
-- 内部常量 & 工具
-- ============================================================================
local BP_BASE_W = 1470
local BP_BASE_H = 1080

local function bp_rgba(r, g, b, a)
    return nvgRGBA(r, g, b, a or 255)
end

-- ============================================================================
-- 物品图片路径映射 & NanoVG 图片缓存
-- ============================================================================
local BP_IMG_PATHS = {
    -- 武器
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
    -- 背包
    small   = "image/小背包-0014.png",
    medium  = "image/中型背包-0015.png",
    large   = "image/大型军用背包-0016.png",
    medic   = "image/野战医疗背包-0017.png",
    assault = "image/穿击背包-0018.png",
    -- 头盔
    cap        = "image/棒球帽-0019.png",
    helm_light = "image/防弹头盔-0020.png",
    helm_heavy = "image/重型头盔-0021.png",
    helm_full  = "image/军用全罩盔-0022.png",
    -- 护甲
    armor_tact    = "image/战术背心-0023.png",
    armor_light   = "image/轻型防弹衣-0024.png",
    armor_medium  = "image/中型防弹衣-0025.png",
    armor_heavy   = "image/重型防弹衣-0027.png",
    armor_ceramic = "image/复合陶瓷甲-0028.png",
}
local bp_imgCache = {}

--- 获取物品图片句柄（根据 entry 自动匹配 key/id）
local function bp_get_item_image(vg, entry)
    if not entry or not entry.data then return nil end
    local k = entry.data.key or entry.data.id
    if not k then return nil end
    if bp_imgCache[k] then return bp_imgCache[k] end
    local path = BP_IMG_PATHS[k]
    if not path then return nil end
    local handle = nvgCreateImage(vg, path, 0)
    if handle and handle > 0 then
        bp_imgCache[k] = handle
        return handle
    end
    return nil
end

--- 在指定矩形内绘制物品图片（居中、保持比例、武器竖格旋转）
local function bp_draw_item_image(vg, img, x, y, w, h, isWeapon)
    if not img or img <= 0 then return false end
    if isWeapon and h > w then
        -- 竖格武器：旋转90°，枪长对齐框高
        local longSide = h - 6
        local shortSide = w - 6
        local imgW = longSide
        local imgH = imgW * (44/66)
        if imgH > shortSide then imgH = shortSide; imgW = imgH * (66/44) end
        nvgSave(vg)
        nvgTranslate(vg, x + w/2, y + h/2)
        nvgRotate(vg, -math.pi/2)
        local pat = nvgImagePattern(vg, -imgW/2, -imgH/2, imgW, imgH, 0, img, 1.0)
        nvgBeginPath(vg) nvgRect(vg, -imgW/2, -imgH/2, imgW, imgH)
        nvgFillPaint(vg, pat) nvgFill(vg)
        nvgRestore(vg)
    else
        -- 正常放置（保持比例居中）
        local maxW = w - 6
        local maxH = h - 6
        local imgW, imgH
        if isWeapon then
            imgW = maxW
            imgH = imgW * (44/66)
            if imgH > maxH then imgH = maxH; imgW = imgH * (66/44) end
        else
            imgW = math.min(maxW, maxH)
            imgH = imgW
        end
        local ix = x + (w - imgW) / 2
        local iy = y + (h - imgH) / 2
        local pat = nvgImagePattern(vg, ix, iy, imgW, imgH, 0, img, 1.0)
        nvgBeginPath(vg) nvgRect(vg, ix, iy, imgW, imgH)
        nvgFillPaint(vg, pat) nvgFill(vg)
    end
    return true
end

local function bp_data(data)
    return data or {}
end

local function bp_layout(SW, SH)
    local s = math.min(SW / BP_BASE_W, SH / BP_BASE_H)
    if s > 1.0 then s = 1.0 end
    local ox = (SW - BP_BASE_W * s) / 2
    local oy = (SH - BP_BASE_H * s) / 2
    return ox, oy, s
end

local function bp_to_base(mx, my, SW, SH)
    local ox, oy, s = bp_layout(SW, SH)
    return (mx - ox) / s, (my - oy) / s
end

local function bp_in_rect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function bp_fill_rect(vg, x, y, w, h, color)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, color)
    nvgFill(vg)
end

local function bp_fill_round(vg, x, y, w, h, r, color)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, color)
    nvgFill(vg)
end

local function bp_stroke_round(vg, x, y, w, h, r, color, width)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgStrokeColor(vg, color)
    nvgStrokeWidth(vg, width or 1)
    nvgStroke(vg)
end

local function bp_line(vg, x1, y1, x2, y2, color, width)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y1)
    nvgLineTo(vg, x2, y2)
    nvgStrokeColor(vg, color)
    nvgStrokeWidth(vg, width or 1)
    nvgStroke(vg)
end

local function bp_text(vg, x, y, text, size, color, face, align)
    nvgFontFace(vg, face or "sans")
    nvgFontSize(vg, size)
    nvgFillColor(vg, color)
    nvgTextAlign(vg, align or (NVG_ALIGN_LEFT | NVG_ALIGN_TOP))
    nvgText(vg, x, y, text or "")
end

local function bp_panel(vg, x, y, w, h)
    local bg = nvgLinearGradient(
        vg, x, y, x, y + h,
        bp_rgba(10, 18, 23, 246),
        bp_rgba(6, 10, 14, 248)
    )
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 5)
    nvgFillPaint(vg, bg)
    nvgFill(vg)
    bp_stroke_round(vg, x, y, w, h, 5, bp_rgba(78, 82, 82, 165), 2)
    bp_stroke_round(vg, x + 4, y + 4, w - 8, h - 8, 3, bp_rgba(6, 210, 220, 26), 1)
end

local function bp_dashed_rect(vg, x, y, w, h, color)
    local dash = 12
    local gap = 8
    local ix = x
    while ix < x + w do
        bp_line(vg, ix, y, math.min(ix + dash, x + w), y, color, 2)
        bp_line(vg, ix, y + h, math.min(ix + dash, x + w), y + h, color, 2)
        ix = ix + dash + gap
    end
    local iy = y
    while iy < y + h do
        bp_line(vg, x, iy, x, math.min(iy + dash, y + h), color, 2)
        bp_line(vg, x + w, iy, x + w, math.min(iy + dash, y + h), color, 2)
        iy = iy + dash + gap
    end
end

local function bp_outer_frame(vg)
    local bg = nvgLinearGradient(vg, 0, 0, 0, BP_BASE_H, bp_rgba(5, 12, 16, 255), bp_rgba(2, 7, 10, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, BP_BASE_W, BP_BASE_H)
    nvgFillPaint(vg, bg)
    nvgFill(vg)

    bp_stroke_round(vg, 12, 16, BP_BASE_W - 24, BP_BASE_H - 28, 8, bp_rgba(112, 106, 94, 210), 2)
    bp_stroke_round(vg, 18, 22, BP_BASE_W - 36, BP_BASE_H - 40, 4, bp_rgba(19, 222, 226, 38), 1)

    for i = 0, 19 do
        local x = 34 + i * 72
        bp_line(vg, x, 18, x + 56, 18, bp_rgba(180, 158, 118, 80), 2)
        bp_line(vg, x, BP_BASE_H - 15, x + 56, BP_BASE_H - 15, bp_rgba(180, 158, 118, 60), 2)
    end
end

local function bp_draw_coin(vg, cx, cy, r, amount)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r)
    nvgFillColor(vg, bp_rgba(247, 168, 30, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r - 4)
    nvgStrokeColor(vg, bp_rgba(255, 230, 126, 230))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)
    bp_text(vg, cx + r + 10, cy, tostring(amount or 0), 34, bp_rgba(255, 176, 48, 255), "bold", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
end

local function bp_draw_crossed_swords(vg, x, y)
    -- 左剑（从左下到右上）
    -- 剑刃（银色，较细尖锐）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + 6, y + 34)
    nvgLineTo(vg, x + 19, y + 18)
    nvgLineTo(vg, x + 32, y + 2)
    nvgLineTo(vg, x + 34, y + 4)
    nvgLineTo(vg, x + 21, y + 20)
    nvgLineTo(vg, x + 8, y + 36)
    nvgClosePath(vg)
    nvgFillColor(vg, bp_rgba(210, 215, 220, 255))
    nvgFill(vg)
    -- 左剑护手（金色横条）
    bp_line(vg, x + 14, y + 25, x + 24, y + 21, bp_rgba(244, 182, 41, 255), 3)
    -- 左剑柄（棕色）
    bp_line(vg, x + 6, y + 34, x + 2, y + 38, bp_rgba(139, 90, 43, 255), 4)

    -- 右剑（从右下到左上）
    -- 剑刃
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + 36, y + 34)
    nvgLineTo(vg, x + 23, y + 18)
    nvgLineTo(vg, x + 10, y + 2)
    nvgLineTo(vg, x + 8, y + 4)
    nvgLineTo(vg, x + 21, y + 20)
    nvgLineTo(vg, x + 34, y + 36)
    nvgClosePath(vg)
    nvgFillColor(vg, bp_rgba(210, 215, 220, 255))
    nvgFill(vg)
    -- 右剑护手（金色横条）
    bp_line(vg, x + 18, y + 21, x + 28, y + 25, bp_rgba(244, 182, 41, 255), 3)
    -- 右剑柄（棕色）
    bp_line(vg, x + 36, y + 34, x + 40, y + 38, bp_rgba(139, 90, 43, 255), 4)

    -- 中心交叉高光点
    nvgBeginPath(vg)
    nvgCircle(vg, x + 21, y + 19, 2)
    nvgFillColor(vg, bp_rgba(255, 240, 200, 180))
    nvgFill(vg)
end

local function bp_draw_dog_head(vg, x, y, scale)
    local s = scale or 1
    bp_fill_round(vg, x + 7*s, y + 8*s, 35*s, 31*s, 9*s, bp_rgba(172, 102, 34, 255))
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + 10*s, y + 12*s)
    nvgLineTo(vg, x + 14*s, y + 0*s)
    nvgLineTo(vg, x + 21*s, y + 13*s)
    nvgClosePath(vg)
    nvgFillColor(vg, bp_rgba(211, 135, 46, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + 38*s, y + 12*s)
    nvgLineTo(vg, x + 34*s, y + 0*s)
    nvgLineTo(vg, x + 28*s, y + 13*s)
    nvgClosePath(vg)
    nvgFillColor(vg, bp_rgba(211, 135, 46, 255))
    nvgFill(vg)
    bp_fill_round(vg, x + 16*s, y + 21*s, 16*s, 13*s, 5*s, bp_rgba(236, 220, 183, 255))
    nvgBeginPath(vg)
    nvgCircle(vg, x + 18*s, y + 20*s, 2.5*s)
    nvgCircle(vg, x + 31*s, y + 20*s, 2.5*s)
    nvgFillColor(vg, bp_rgba(15, 17, 18, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, x + 24*s, y + 27*s, 3*s)
    nvgFillColor(vg, bp_rgba(20, 18, 18, 255))
    nvgFill(vg)
end

local function bp_draw_paw(vg, cx, cy, r, color)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy + r * 0.35, r * 0.48)
    nvgCircle(vg, cx - r * 0.45, cy - r * 0.12, r * 0.25)
    nvgCircle(vg, cx - r * 0.15, cy - r * 0.42, r * 0.25)
    nvgCircle(vg, cx + r * 0.20, cy - r * 0.42, r * 0.25)
    nvgCircle(vg, cx + r * 0.50, cy - r * 0.12, r * 0.25)
    nvgFillColor(vg, color)
    nvgFill(vg)
end

local function bp_draw_cell(vg, x, y, size, index, occupied)
    bp_fill_round(vg, x, y, size, size, 3, bp_rgba(7, 13, 17, 230))
    bp_stroke_round(vg, x, y, size, size, 3, bp_rgba(81, 86, 83, 130), 2)
    bp_stroke_round(vg, x + 4, y + 4, size - 8, size - 8, 1, bp_rgba(2, 7, 10, 210), 1)
    bp_draw_paw(vg, x + size / 2, y + size / 2 + 1, size * 0.17, bp_rgba(56, 64, 62, occupied and 130 or 55))
    if occupied then
        bp_fill_round(vg, x + 6, y + 6, size - 12, size - 12, 4, bp_rgba(26, 43, 44, 180))
        bp_text(vg, x + size / 2, y + size / 2, tostring(index), 15, bp_rgba(245, 211, 132, 230), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    end
end

local function bp_draw_warehouse(vg, data)
    bp_panel(vg, 30, 104, 495, 900)
    bp_text(vg, 56, 130, "仓库 10×10", 22, bp_rgba(75, 224, 255, 255), "bold")
    bp_text(vg, 306, 134, "（拖拽物品出售 / 携带）", 15, bp_rgba(76, 217, 244, 210), "sans")

    local used = data.storageUsed or 0
    local cell, gap = 42, 6
    local gx, gy = 50, 165
    local items = data.warehouseItems or {}

    -- 构建占用网格（标记哪些格子被物品覆盖）
    local occupied = {}
    for _, entry in ipairs(items) do
        local iw = entry.rotated and entry.ih or entry.iw
        local ih = entry.rotated and entry.iw or entry.ih
        for row = entry.y, entry.y + ih - 1 do
            for col = entry.x, entry.x + iw - 1 do
                occupied[(row - 1) * 10 + col] = true
            end
        end
    end

    -- 绘制 10×10 空格子底板
    for row = 0, 9 do
        for col = 0, 9 do
            local key = row * 10 + (col + 1)
            local cx = gx + col * (cell + gap)
            local cy = gy + row * (cell + gap)
            bp_fill_round(vg, cx, cy, cell, cell, 3, bp_rgba(7, 13, 17, 230))
            bp_stroke_round(vg, cx, cy, cell, cell, 3, bp_rgba(81, 86, 83, occupied[key] and 80 or 130), 2)
            if not occupied[key] then
                bp_draw_paw(vg, cx + cell / 2, cy + cell / 2 + 1, cell * 0.17, bp_rgba(56, 64, 62, 55))
            end
        end
    end

    -- 绘制每个物品（跨格图标 - 使用实际图片）
    local Data = require("Data")
    local RARITY_COLOR = Data.RARITY_COLOR or {}
    for _, entry in ipairs(items) do
        local iw = entry.rotated and entry.ih or entry.iw
        local ih = entry.rotated and entry.iw or entry.ih
        local px = gx + (entry.x - 1) * (cell + gap)
        local py = gy + (entry.y - 1) * (cell + gap)
        local pw = iw * cell + (iw - 1) * gap
        local ph = ih * cell + (ih - 1) * gap

        -- 物品背景（带稀有度边框色）
        local rc = RARITY_COLOR[entry.rarity] or {180, 180, 180}
        bp_fill_round(vg, px + 2, py + 2, pw - 4, ph - 4, 4, bp_rgba(18, 32, 36, 210))
        bp_stroke_round(vg, px + 2, py + 2, pw - 4, ph - 4, 4, bp_rgba(rc[1], rc[2], rc[3], 180), 2)

        -- 优先使用实际图片，fallback 到 emoji
        local img = bp_get_item_image(vg, entry)
        local isWeapon = (entry.itype == "weapon")
        if not bp_draw_item_image(vg, img, px + 2, py + 2, pw - 4, ph - 4, isWeapon) then
            -- 无图片时 fallback emoji
            local icon = entry.icon or "📦"
            local fontSize = math.min(pw, ph) * 0.52
            fontSize = math.max(14, math.min(fontSize, 28))
            bp_text(vg, px + pw / 2, py + ph / 2, icon, fontSize, bp_rgba(255, 255, 255, 240), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
        end

        -- 如果物品有数量 > 1，右下角显示数量
        if entry.qty and entry.qty > 1 then
            bp_text(vg, px + pw - 6, py + ph - 6, "×" .. tostring(entry.qty), 11, bp_rgba(245, 211, 132, 220), "bold", NVG_ALIGN_RIGHT | NVG_ALIGN_BOTTOM)
        end
    end

    if used == 0 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, 0.72)
        nvgBeginPath(vg)
        nvgCircle(vg, 275, 502, 72)
        nvgFillColor(vg, bp_rgba(9, 16, 20, 224))
        nvgFill(vg)
        bp_dashed_rect(vg, 214, 430, 122, 122, bp_rgba(78, 86, 85, 130))
        bp_draw_paw(vg, 275, 493, 42, bp_rgba(78, 91, 90, 190))
        bp_text(vg, 275, 552, "空空如也", 24, bp_rgba(158, 157, 145, 210), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
        nvgRestore(vg)
    end

    bp_fill_round(vg, 50, 895, 445, 82, 3, bp_rgba(9, 16, 20, 238))
    bp_stroke_round(vg, 50, 895, 445, 82, 3, bp_rgba(71, 74, 72, 120), 1)
    bp_line(vg, 322, 898, 322, 973, bp_rgba(80, 83, 80, 150), 1)
    bp_fill_round(vg, 73, 914, 54, 41, 4, bp_rgba(31, 47, 50, 255))
    bp_stroke_round(vg, 73, 914, 54, 41, 4, bp_rgba(238, 128, 32, 190), 2)
    bp_line(vg, 81, 928, 118, 928, bp_rgba(245, 144, 43, 255), 3)
    bp_text(vg, 148, 916, "仓库容量", 18, bp_rgba(214, 198, 170, 230), "sans")
    bp_text(vg, 148, 947, tostring(used) .. " / " .. tostring(data.storageCapacity or 100) .. " 格", 20, bp_rgba(246, 234, 212, 255), "bold")
    bp_text(vg, 356, 916, "仓库价值", 18, bp_rgba(214, 198, 170, 230), "sans")
    bp_draw_coin(vg, 382, 948, 11, data.storageValue or 0)
end

local function bp_draw_tabs(vg, data)
    local active = data.mode or "sell"
    local sellActive = active ~= "buy"
    local buyActive = active == "buy"
    local sx, sy, sw, sh = 558, 118, 226, 52
    local bx, by, bw, bh = 798, 118, 222, 52
    local sellColor = sellActive and bp_rgba(0, 211, 220, 235) or bp_rgba(93, 93, 90, 170)
    local buyColor = buyActive and bp_rgba(0, 211, 220, 235) or bp_rgba(93, 93, 90, 170)
    bp_fill_round(vg, sx, sy, sw, sh, 2, sellActive and bp_rgba(0, 65, 71, 160) or bp_rgba(10, 13, 15, 230))
    bp_stroke_round(vg, sx, sy, sw, sh, 2, sellColor, sellActive and 3 or 2)
    bp_draw_paw(vg, sx + 78, sy + 27, 14, sellActive and bp_rgba(194, 245, 178, 255) or bp_rgba(93, 93, 90, 180))
    bp_text(vg, sx + 108, sy + 26, "出售", 25, sellActive and bp_rgba(45, 242, 249, 255) or bp_rgba(122, 121, 116, 220), "bold", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
    bp_fill_round(vg, bx, by, bw, bh, 2, buyActive and bp_rgba(0, 65, 71, 160) or bp_rgba(10, 13, 15, 230))
    bp_stroke_round(vg, bx, by, bw, bh, 2, buyColor, buyActive and 3 or 2)
    bp_text(vg, bx + 70, by + 26, "购买", 25, buyActive and bp_rgba(45, 242, 249, 255) or bp_rgba(122, 121, 116, 220), "bold", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
end

local function bp_draw_cat_scene(vg, x, y, w, h)
    bp_fill_round(vg, x, y, w, h, 3, bp_rgba(7, 13, 17, 242))
    local shade = nvgRadialGradient(vg, x + w * 0.48, y + h * 0.34, 20, w * 0.58, bp_rgba(22, 45, 47, 210), bp_rgba(2, 6, 8, 245))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + 5, y + 5, w - 10, h - 10, 2)
    nvgFillPaint(vg, shade)
    nvgFill(vg)
    for row = 0, 5 do
        for col = 0, 8 do
            local bx = x + 20 + col * 52 + ((row % 2) * 24)
            local by = y + 18 + row * 28
            bp_stroke_round(vg, bx, by, 46, 24, 2, bp_rgba(35, 46, 48, 75), 1)
        end
    end
    bp_fill_round(vg, x + 118, y + 118, 42, 56, 2, bp_rgba(91, 63, 34, 180))
    bp_stroke_round(vg, x + 118, y + 118, 42, 56, 2, bp_rgba(177, 123, 51, 110), 2)
    bp_fill_round(vg, x + 165, y + 112, 48, 62, 2, bp_rgba(80, 61, 42, 180))
    bp_stroke_round(vg, x + 165, y + 112, 48, 62, 2, bp_rgba(177, 123, 51, 110), 2)

    local cx, cy = x + w * 0.52, y + 98
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - 42, cy - 18)
    nvgLineTo(vg, cx - 25, cy - 68)
    nvgLineTo(vg, cx - 8, cy - 22)
    nvgLineTo(vg, cx + 8, cy - 22)
    nvgLineTo(vg, cx + 25, cy - 68)
    nvgLineTo(vg, cx + 42, cy - 18)
    nvgClosePath(vg)
    nvgFillColor(vg, bp_rgba(48, 58, 58, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, 46)
    nvgFillColor(vg, bp_rgba(55, 65, 65, 250))
    nvgFill(vg)
    bp_fill_round(vg, cx - 36, cy + 36, 74, 70, 24, bp_rgba(51, 61, 61, 250))
    nvgBeginPath(vg)
    nvgCircle(vg, cx - 17, cy - 4, 4)
    nvgCircle(vg, cx + 17, cy - 4, 4)
    nvgFillColor(vg, bp_rgba(14, 16, 17, 255))
    nvgFill(vg)
    bp_fill_round(vg, cx - 13, cy + 12, 26, 12, 6, bp_rgba(198, 197, 181, 220))
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy + 13, 4)
    nvgFillColor(vg, bp_rgba(13, 14, 14, 255))
    nvgFill(vg)
    bp_line(vg, cx + 37, cy + 64, cx + 76, cy + 46, bp_rgba(40, 50, 50, 250), 11)
    nvgBeginPath(vg)
    nvgCircle(vg, x + w - 42, y + h - 40, 24)
    nvgFillColor(vg, bp_rgba(41, 40, 38, 180))
    nvgFill(vg)
    bp_text(vg, x + w - 42, y + h - 43, "☠", 30, bp_rgba(122, 118, 103, 150), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
end

-- ============================================================================
-- 购买面板常量
-- ============================================================================
local BUY_VENDOR_Y     = 186    -- 商人选择条 Y
local BUY_VENDOR_H     = 48     -- 商人选择条高度
local BUY_LIST_Y       = 248    -- 商品列表起始 Y
local BUY_LIST_H       = 730    -- 商品列表可视高度
local BUY_ITEM_H       = 62     -- 每个商品行高度
local BUY_LIST_X       = 556    -- 列表左边界
local BUY_LIST_W       = 470    -- 列表宽度
local BUY_SCROLL_W     = 10     -- 滚动条宽度

--- 购买面板可视列表高度/行高（供外部 clamp 用）
M.BUY_LIST_H = BUY_LIST_H
M.BUY_ITEM_H = BUY_ITEM_H

local function bp_rarity_color(rarity)
    local r = rarity or 1
    if r >= 5 then return bp_rgba(255, 170, 50, 255) end
    if r >= 4 then return bp_rgba(200, 80, 220, 255) end
    if r >= 3 then return bp_rgba(70, 140, 255, 255) end
    if r >= 2 then return bp_rgba(80, 200, 80, 255) end
    return bp_rgba(180, 180, 180, 255)
end

local function bp_draw_buy_center(vg, data)
    local vendors = data.vendors or {}
    local activeVendorId = data.activeVendorId or (vendors[1] and vendors[1].id or "")
    local scrollY = data.buyScrollY or 0

    -- 商人选择条
    local vx = BUY_LIST_X
    local vy = BUY_VENDOR_Y
    local vBtnW = math.floor(BUY_LIST_W / math.max(1, #vendors))
    for i, v in ipairs(vendors) do
        local bx = vx + (i - 1) * vBtnW
        local isActive = (v.id == activeVendorId)
        bp_fill_round(vg, bx, vy, vBtnW - 4, BUY_VENDOR_H, 3,
            isActive and bp_rgba(0, 58, 64, 200) or bp_rgba(10, 14, 17, 230))
        bp_stroke_round(vg, bx, vy, vBtnW - 4, BUY_VENDOR_H, 3,
            isActive and bp_rgba(0, 210, 220, 220) or bp_rgba(68, 72, 70, 140), isActive and 2 or 1)
        bp_text(vg, bx + (vBtnW - 4) / 2, vy + BUY_VENDOR_H / 2,
            (v.icon or "") .. " " .. (v.name or ""),
            18, isActive and bp_rgba(40, 240, 245, 255) or bp_rgba(150, 148, 140, 220),
            "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    end

    -- 商品列表区域背景
    bp_fill_round(vg, BUY_LIST_X - 2, BUY_LIST_Y, BUY_LIST_W + 4, BUY_LIST_H, 3, bp_rgba(5, 10, 13, 220))
    bp_stroke_round(vg, BUY_LIST_X - 2, BUY_LIST_Y, BUY_LIST_W + 4, BUY_LIST_H, 3, bp_rgba(60, 64, 62, 130), 1)

    -- 找到当前商人的商品
    local shopItems = {}
    for _, v in ipairs(vendors) do
        if v.id == activeVendorId then
            shopItems = v.shop or {}
            break
        end
    end

    -- 裁剪绘制商品列表
    nvgSave(vg)
    nvgScissor(vg, BUY_LIST_X, BUY_LIST_Y, BUY_LIST_W, BUY_LIST_H)

    local playerGold = data.gold or 0
    for i, item in ipairs(shopItems) do
        local rowY = BUY_LIST_Y + (i - 1) * BUY_ITEM_H - scrollY
        -- 跳过不可见行
        if rowY + BUY_ITEM_H > BUY_LIST_Y and rowY < BUY_LIST_Y + BUY_LIST_H then
            local canBuy = playerGold >= (item.price or 0)
            -- 行背景
            local rowBg = (i % 2 == 0) and bp_rgba(12, 18, 22, 200) or bp_rgba(8, 13, 16, 200)
            bp_fill_round(vg, BUY_LIST_X + 4, rowY + 2, BUY_LIST_W - BUY_SCROLL_W - 12, BUY_ITEM_H - 4, 3, rowBg)
            -- 稀有度左边条
            local rc = bp_rarity_color(item.rarity)
            bp_fill_rect(vg, BUY_LIST_X + 4, rowY + 4, 3, BUY_ITEM_H - 8, rc)
            -- 图标
            bp_text(vg, BUY_LIST_X + 22, rowY + BUY_ITEM_H / 2,
                item.icon or "📦", 22, bp_rgba(240, 240, 240, 255), "sans",
                NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
            -- 名称
            bp_text(vg, BUY_LIST_X + 52, rowY + 20,
                item.name or "???", 17, bp_rgba(230, 222, 205, 240), "bold",
                NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
            -- 价格
            bp_text(vg, BUY_LIST_X + 52, rowY + 44,
                "💰 " .. tostring(item.price or 0), 14,
                canBuy and bp_rgba(255, 200, 60, 220) or bp_rgba(180, 80, 80, 200),
                "sans", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
            -- 购买按钮
            local btnX = BUY_LIST_X + BUY_LIST_W - BUY_SCROLL_W - 78
            local btnY = rowY + 12
            local btnW = 60
            local btnH = BUY_ITEM_H - 24
            bp_fill_round(vg, btnX, btnY, btnW, btnH, 3,
                canBuy and bp_rgba(0, 60, 65, 220) or bp_rgba(20, 22, 24, 200))
            bp_stroke_round(vg, btnX, btnY, btnW, btnH, 3,
                canBuy and bp_rgba(0, 200, 210, 200) or bp_rgba(55, 58, 56, 130), 1)
            bp_text(vg, btnX + btnW / 2, btnY + btnH / 2,
                "购买", 15,
                canBuy and bp_rgba(30, 235, 240, 255) or bp_rgba(90, 92, 90, 180),
                "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
        end
    end

    nvgRestore(vg)

    -- 滚动条
    local totalH = #shopItems * BUY_ITEM_H
    if totalH > BUY_LIST_H then
        local barH = math.max(30, BUY_LIST_H * BUY_LIST_H / totalH)
        local maxScroll = totalH - BUY_LIST_H
        local barY = BUY_LIST_Y + (scrollY / maxScroll) * (BUY_LIST_H - barH)
        local barX = BUY_LIST_X + BUY_LIST_W - BUY_SCROLL_W
        bp_fill_round(vg, barX, BUY_LIST_Y, BUY_SCROLL_W, BUY_LIST_H, 4, bp_rgba(5, 8, 10, 180))
        bp_fill_round(vg, barX + 1, barY, BUY_SCROLL_W - 2, barH, 4, bp_rgba(0, 160, 170, 160))
    end
end

-- 待售列表常量（用于渲染和点击检测对齐）
local SELL_LIST_X = 556
local SELL_LIST_Y = 200
local SELL_LIST_W = 465
local SELL_ITEM_H = 36
local SELL_LIST_MAX = 8  -- 最多显示8行（超出滚动暂不实现）

local function bp_draw_sell_center(vg, data)
    local pending = data.sellPending or {}

    bp_stroke_round(vg, 550, 186, 477, 397, 3, bp_rgba(82, 86, 82, 150), 2)

    if #pending > 0 then
        -- 有待售物品：显示物品列表
        bp_text(vg, 788, 198, "待售物品（点击可取回）", 17, bp_rgba(145, 174, 181, 200), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
        local showCount = math.min(#pending, SELL_LIST_MAX)
        for i = 1, showCount do
            local entry = pending[i]
            local rowY = SELL_LIST_Y + (i - 1) * SELL_ITEM_H
            local icon = entry.icon or (entry.data and entry.data.icon) or "📦"
            local name = (entry.data and entry.data.name) or entry.name or "物品"
            -- 行背景（hover 感）
            bp_fill_round(vg, SELL_LIST_X, rowY, SELL_LIST_W, SELL_ITEM_H - 4, 3, bp_rgba(10, 20, 25, 180))
            bp_stroke_round(vg, SELL_LIST_X, rowY, SELL_LIST_W, SELL_ITEM_H - 4, 3, bp_rgba(0, 180, 190, 60), 1)
            -- 图标
            bp_text(vg, SELL_LIST_X + 20, rowY + (SELL_ITEM_H - 4) / 2, icon, 18, bp_rgba(255, 255, 255, 230), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
            -- 名称
            bp_text(vg, SELL_LIST_X + 42, rowY + (SELL_ITEM_H - 4) / 2, name, 16, bp_rgba(210, 225, 230, 230), "sans", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
            -- 取回提示
            bp_text(vg, SELL_LIST_X + SELL_LIST_W - 10, rowY + (SELL_ITEM_H - 4) / 2, "✕ 取回", 14, bp_rgba(255, 120, 100, 200), "sans", NVG_ALIGN_RIGHT | NVG_ALIGN_MIDDLE)
        end
        if #pending > SELL_LIST_MAX then
            local moreY = SELL_LIST_Y + SELL_LIST_MAX * SELL_ITEM_H
            bp_text(vg, 788, moreY + 10, string.format("...还有 %d 件", #pending - SELL_LIST_MAX), 14, bp_rgba(145, 174, 181, 160), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
        end
    else
        -- 无待售物品：显示原始说明
        bp_draw_cat_scene(vg, 556, 192, 465, 386)
        bp_text(vg, 792, 394, "首次出战，当前暂无战利品", 30, bp_rgba(21, 229, 235, 255), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
        bp_text(vg, 792, 440, "完成一局后，可将搜刮到的物品", 19, bp_rgba(222, 211, 198, 230), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
        bp_text(vg, 792, 467, "带回并在这里出售或整理", 19, bp_rgba(222, 211, 198, 230), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    end

    bp_dashed_rect(vg, 564, 493, 448, 52, bp_rgba(69, 183, 207, 190))
    bp_draw_paw(vg, 650, 520, 15, bp_rgba(133, 165, 171, 220))
    bp_text(vg, 677, 520, "将物品拖拽到此处即可出售", 19, bp_rgba(145, 174, 181, 230), "sans", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
    bp_text(vg, 735, 570, "总收益：", 20, bp_rgba(217, 206, 186, 230), "sans", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
    bp_draw_coin(vg, 807, 570, 10, data.totalSell or 0)

    local disabled = (data.totalSell or 0) <= 0
    bp_fill_round(vg, 550, 605, 232, 48, 3, disabled and bp_rgba(10, 15, 18, 218) or bp_rgba(19, 58, 61, 230))
    bp_stroke_round(vg, 550, 605, 232, 48, 3, disabled and bp_rgba(62, 65, 64, 110) or bp_rgba(42, 219, 226, 220), 2)
    bp_text(vg, 666, 630, "全部出售", 21, disabled and bp_rgba(116, 118, 116, 180) or bp_rgba(56, 235, 240, 255), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_fill_round(vg, 796, 605, 232, 48, 3, disabled and bp_rgba(10, 15, 18, 218) or bp_rgba(23, 68, 57, 230))
    bp_stroke_round(vg, 796, 605, 232, 48, 3, disabled and bp_rgba(62, 65, 64, 110) or bp_rgba(119, 226, 134, 220), 2)
    bp_text(vg, 912, 630, "✓ 确认出售", 21, disabled and bp_rgba(116, 118, 116, 180) or bp_rgba(185, 244, 186, 255), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)

    bp_stroke_round(vg, 550, 675, 477, 320, 3, bp_rgba(73, 76, 73, 145), 2)
    bp_text(vg, 556, 694, "新手指南 / 初次出发小贴士", 20, bp_rgba(73, 224, 255, 255), "bold")
    bp_text(vg, 994, 702, "?", 22, bp_rgba(223, 212, 193, 255), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
end

local function bp_draw_center(vg, data)
    bp_panel(vg, 538, 104, 505, 900)
    bp_draw_tabs(vg, data)
    if data.mode == "buy" then
        bp_draw_buy_center(vg, data)
    else
        bp_draw_sell_center(vg, data)
    end
end

local function bp_card_tone(tone)
    if tone == "red" then
        return bp_rgba(222, 77, 54, 255), bp_rgba(65, 19, 16, 230), bp_rgba(255, 110, 93, 255)
    elseif tone == "blue" then
        return bp_rgba(64, 174, 245, 255), bp_rgba(10, 35, 50, 230), bp_rgba(105, 205, 255, 255)
    end
    return bp_rgba(125, 210, 78, 255), bp_rgba(29, 50, 18, 230), bp_rgba(183, 238, 105, 255)
end

local function bp_default_card(i)
    if i == 2 then
        return { title = "谨慎深入", body1 = "越深入，宝藏越多", body2 = "但危险也越大", body3 = "量力而行，及时撤退！", tone = "blue" }
    elseif i == 3 then
        return { title = "死亡惩罚", body1 = "战斗中死亡将失去", body2 = "全部携带物品", body3 = "小心为上，活着回来！", tone = "red" }
    end
    return { title = "搜刮撤离", body1 = "进入地牢搜刮宝藏", body2 = "成功撤离带回基地", body3 = "才算真正的收获！", tone = "green" }
end

local function bp_draw_tip_card(vg, x, y, w, h, card, index)
    local c = card or bp_default_card(index)
    local edge, bg, textColor = bp_card_tone(c.tone)
    bp_fill_round(vg, x, y, w, h, 3, bg)
    bp_stroke_round(vg, x, y, w, h, 3, edge, 2)
    bp_stroke_round(vg, x + 5, y + 5, w - 10, h - 10, 2, bp_rgba(255, 255, 255, 28), 1)
    bp_text(vg, x + w / 2, y + 27, c.title or "", 18, textColor, "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    local iconY = y + 87
    if index == 1 then
        bp_draw_dog_head(vg, x + w / 2 - 26, iconY - 30, 1.15)
        bp_draw_coin(vg, x + w / 2 + 35, iconY + 14, 8, "")
    elseif index == 2 then
        nvgBeginPath(vg)
        nvgArc(vg, x + w / 2, iconY, 32, 0.15, 6.1, NVG_CW)
        nvgStrokeColor(vg, bp_rgba(104, 216, 255, 210))
        nvgStrokeWidth(vg, 7)
        nvgStroke(vg)
        bp_fill_round(vg, x + w / 2 - 22, iconY - 8, 44, 42, 18, bp_rgba(12, 15, 20, 230))
    else
        nvgBeginPath(vg)
        nvgCircle(vg, x + w / 2, iconY, 34)
        nvgFillColor(vg, bp_rgba(86, 86, 84, 240))
        nvgFill(vg)
        bp_text(vg, x + w / 2, iconY, "!", 42, bp_rgba(24, 24, 23, 255), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
        bp_draw_dog_head(vg, x + 42, iconY + 24, 0.7)
    end
    bp_text(vg, x + w / 2, y + 151, c.body1 or "", 14, bp_rgba(232, 221, 196, 235), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_text(vg, x + w / 2, y + 176, c.body2 or "", 14, bp_rgba(232, 221, 196, 235), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_text(vg, x + w / 2, y + 201, c.body3 or "", 14, bp_rgba(232, 221, 196, 235), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_draw_paw(vg, x + w / 2, y + h - 18, 10, edge)
end

local function bp_draw_cards(vg, data)
    local cards = data.cards or {}
    bp_draw_tip_card(vg, 548, 728, 142, 260, cards[1], 1)
    bp_draw_tip_card(vg, 705, 728, 142, 260, cards[2], 2)
    bp_draw_tip_card(vg, 862, 728, 164, 260, cards[3], 3)
end

local function bp_draw_weapon_icon(vg, x, y, w, h, kind)
    local cx, cy = x + w / 2, y + h / 2
    if kind == "armor" then
        bp_dashed_rect(vg, cx - 31, cy - 32, 62, 64, bp_rgba(141, 128, 111, 120))
        bp_line(vg, cx - 22, cy - 26, cx - 5, cy - 4, bp_rgba(89, 88, 82, 160), 8)
        bp_line(vg, cx + 22, cy - 26, cx + 5, cy - 4, bp_rgba(89, 88, 82, 160), 8)
        bp_fill_round(vg, cx - 25, cy - 7, 50, 46, 12, bp_rgba(57, 66, 66, 155))
    elseif kind == "bag" then
        bp_dashed_rect(vg, cx - 27, cy - 37, 54, 70, bp_rgba(141, 128, 111, 120))
        bp_fill_round(vg, cx - 30, cy - 20, 60, 55, 13, bp_rgba(54, 63, 60, 145))
        bp_stroke_round(vg, cx - 18, cy - 36, 36, 25, 12, bp_rgba(75, 79, 72, 135), 4)
    elseif kind == "plus" then
        bp_dashed_rect(vg, cx - 25, cy - 25, 50, 50, bp_rgba(141, 128, 111, 120))
        bp_line(vg, cx - 15, cy, cx + 15, cy, bp_rgba(151, 146, 131, 160), 5)
        bp_line(vg, cx, cy - 15, cx, cy + 15, bp_rgba(151, 146, 131, 160), 5)
    elseif kind == "key" then
        nvgBeginPath(vg)
        nvgCircle(vg, cx + 20, cy - 22, 12)
        nvgStrokeColor(vg, bp_rgba(70, 74, 70, 170))
        nvgStrokeWidth(vg, 7)
        nvgStroke(vg)
        bp_line(vg, cx + 12, cy - 13, cx - 30, cy + 30, bp_rgba(70, 74, 70, 170), 8)
        bp_line(vg, cx - 10, cy + 10, cx + 2, cy + 20, bp_rgba(70, 74, 70, 170), 5)
    else
        bp_dashed_rect(vg, cx - 37, cy - 24, 74, 48, bp_rgba(141, 128, 111, 120))
        bp_line(vg, cx - 40, cy - 3, cx + 45, cy - 3, bp_rgba(77, 80, 75, 160), 8)
        bp_line(vg, cx - 18, cy + 11, cx + 10, cy + 11, bp_rgba(77, 80, 75, 160), 11)
        bp_line(vg, cx + 45, cy - 3, cx + 70, cy - 3, bp_rgba(77, 80, 75, 160), 4)
    end
end

local function bp_draw_equip_slot(vg, x, y, w, h, title, slotData, kind)
    bp_fill_round(vg, x, y, w, h, 3, bp_rgba(8, 14, 18, 238))
    bp_stroke_round(vg, x, y, w, h, 3, bp_rgba(83, 79, 70, 140), 2)
    bp_text(vg, x + 18, y + 20, title, 20, bp_rgba(231, 210, 173, 240), "bold", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)

    if type(slotData) == "table" then
        -- 有装备：优先使用实际图片
        local name = slotData.name or "物品"
        local imgKey = slotData.data and (slotData.data.key or slotData.data.id)
        local img = nil
        if imgKey then
            if not bp_imgCache[imgKey] then
                local path = BP_IMG_PATHS[imgKey]
                if path then
                    local handle = nvgCreateImage(vg, path, 0)
                    if handle and handle > 0 then bp_imgCache[imgKey] = handle end
                end
            end
            img = bp_imgCache[imgKey]
        end

        if img and img > 0 then
            -- 绘制图片（左侧区域）
            local imgArea = h - 16
            local imgX = x + 50
            local imgY = y + 8
            local isWeapon = (slotData.itype == "weapon")
            if isWeapon then
                local imgW = imgArea * (66/44)
                if imgW > w * 0.45 then imgW = w * 0.45; end
                local imgH = imgW * (44/66)
                local ix = imgX
                local iy = imgY + (imgArea - imgH) / 2
                local pat = nvgImagePattern(vg, ix, iy, imgW, imgH, 0, img, 1.0)
                nvgBeginPath(vg) nvgRect(vg, ix, iy, imgW, imgH)
                nvgFillPaint(vg, pat) nvgFill(vg)
            else
                local sz = imgArea * 0.85
                local ix = imgX + (imgArea - sz) / 2
                local iy = imgY + (imgArea - sz) / 2
                local pat = nvgImagePattern(vg, ix, iy, sz, sz, 0, img, 1.0)
                nvgBeginPath(vg) nvgRect(vg, ix, iy, sz, sz)
                nvgFillPaint(vg, pat) nvgFill(vg)
            end
            -- 名称在图片右边
            bp_text(vg, x + 50 + h - 8, y + h / 2 + 4, name, 18, bp_rgba(240, 232, 210, 230), "sans", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
        else
            -- 无图片 fallback emoji + 名称
            local icon = slotData.icon or "📦"
            bp_text(vg, x + 80, y + h / 2 + 4, icon, 32, bp_rgba(255, 255, 255, 240), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
            bp_text(vg, x + 115, y + h / 2 + 4, name, 18, bp_rgba(240, 232, 210, 230), "sans", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
        end
    else
        -- 未装备：显示占位图标 + "未装备"
        bp_draw_weapon_icon(vg, x + 95, y + 9, 115, h - 18, kind)
        bp_text(vg, x + w - 34, y + h / 2, "未装备", 19, bp_rgba(176, 158, 137, 210), "sans", NVG_ALIGN_RIGHT | NVG_ALIGN_MIDDLE)
    end
end

local function bp_draw_right(vg, data)
    bp_panel(vg, 1060, 104, 385, 900)
    bp_text(vg, 1086, 137, "出战装备", 24, bp_rgba(75, 224, 255, 255), "bold")
    bp_text(vg, 1238, 139, "（点击放入装备）", 16, bp_rgba(75, 224, 255, 210), "sans")

    local loadout = data.loadout or {}
    bp_draw_equip_slot(vg, 1080, 166, 342, 92, "主武器", loadout.mainWeapon, "gun")
    bp_draw_equip_slot(vg, 1080, 263, 342, 92, "副武器", loadout.subWeapon, "gun")
    bp_draw_equip_slot(vg, 1080, 360, 342, 92, "护甲", loadout.armor, "armor")
    bp_draw_equip_slot(vg, 1080, 457, 342, 92, "背包", loadout.bag, "bag")
    bp_draw_equip_slot(vg, 1080, 559, 158, 112, "消耗品", loadout.consumable, "plus")
    bp_draw_equip_slot(vg, 1246, 559, 176, 112, "钥匙道具", loadout.keyItem, "key")

    -- 弹药携带情况
    local ammoData = data.ammo or {}
    local ammoTypes = {
        { key="light",  label="轻型弹", icon="•" },
        { key="medium", label="中型弹", icon="◆" },
        { key="heavy",  label="重型弹", icon="■" },
        { key="sniper", label="狙击弹", icon="▲" },
    }
    bp_text(vg, 1086, 690, "弹药储备", 16, bp_rgba(200,210,180,200), "bold")
    local ammoX = 1086
    for i, at in ipairs(ammoTypes) do
        local cnt = ammoData[at.key] or 0
        local col = cnt > 0 and bp_rgba(200,230,180,230) or bp_rgba(80,90,70,150)
        bp_text(vg, ammoX, 714, at.icon .. " " .. at.label .. ":" .. cnt, 14, col, "sans")
        ammoX = ammoX + 92
    end

    bp_text(vg, 1095, 748, "▣", 22, bp_rgba(234, 227, 209, 255), "bold", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
    bp_fill_round(vg, 1118, 736, 300, 24, 3, bp_rgba(2, 6, 7, 240))
    bp_fill_round(vg, 1121, 739, math.min(294, 294 * ((data.weight or 0) / math.max(1, data.maxWeight or 25))), 18, 2, bp_rgba(25, 67, 71, 210))
    bp_stroke_round(vg, 1118, 736, 300, 24, 3, bp_rgba(47, 50, 48, 170), 1)
    bp_text(vg, 1376, 748, string.format("%.1f / %.1f", data.weight or 0, data.maxWeight or 25), 18, bp_rgba(230, 216, 193, 245), "bold", NVG_ALIGN_RIGHT | NVG_ALIGN_MIDDLE)

    bp_text(vg, 1083, 780, "准备度", 19, bp_rgba(230, 216, 193, 235), "bold", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
    local ready = data.readiness or 5
    for i = 1, 8 do
        bp_draw_paw(vg, 1161 + i * 26, 780, 13, i <= ready and bp_rgba(112, 160, 119, 220) or bp_rgba(62, 73, 65, 190))
    end
    bp_text(vg, 1418, 780, (data.isFirstRaid == false) and "准备出发" or "初次出发", 19, bp_rgba(62, 220, 255, 255), "bold", NVG_ALIGN_RIGHT | NVG_ALIGN_MIDDLE)

    local pulse = nvgBoxGradient(vg, 1062, 796, 384, 112, 5, 18, bp_rgba(5, 194, 201, 160), bp_rgba(0, 242, 245, 18))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 1062, 796, 384, 112, 5)
    nvgFillPaint(vg, pulse)
    nvgFill(vg)
    bp_fill_round(vg, 1070, 806, 368, 92, 4, bp_rgba(2, 80, 84, 190))
    bp_stroke_round(vg, 1062, 796, 384, 112, 5, bp_rgba(0, 247, 248, 255), 4)
    bp_line(vg, 1118, 852, 1154, 852, bp_rgba(37, 239, 243, 255), 0)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 1135, 836)
    nvgLineTo(vg, 1135, 868)
    nvgLineTo(vg, 1165, 852)
    nvgClosePath(vg)
    nvgFillColor(vg, bp_rgba(20, 239, 244, 255))
    nvgFill(vg)
    bp_text(vg, 1256, 852, "出发!", 43, bp_rgba(30, 239, 243, 255), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_draw_dog_head(vg, 1360, 825, 0.95)

    bp_fill_round(vg, 1060, 924, 385, 70, 4, bp_rgba(11, 15, 18, 245))
    bp_stroke_round(vg, 1060, 924, 385, 70, 4, bp_rgba(70, 69, 65, 170), 2)
    bp_text(vg, 1256, 960, "← 返回菜单", 27, bp_rgba(216, 205, 187, 235), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
end

local function bp_draw_top(vg, data)
    bp_draw_crossed_swords(vg, 48, 46)
    bp_draw_dog_head(vg, 104, 41, 0.96)
    bp_text(vg, 166, 66, "战前准备", 34, bp_rgba(255, 222, 164, 255), "bold", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
    bp_draw_coin(vg, 1364, 66, 15, data.gold or 0)
end

local function bp_draw_footer(vg)
    bp_text(vg, 520, 1044, "ESC = 返回菜单", 17, bp_rgba(73, 158, 177, 210), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_text(vg, 557, 1044, "|", 22, bp_rgba(93, 123, 132, 170), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_text(vg, 682, 1044, "空格 = 直接出发", 17, bp_rgba(73, 158, 177, 210), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_text(vg, 780, 1044, "|", 22, bp_rgba(93, 123, 132, 170), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_text(vg, 940, 1044, "首次出战后将解锁更多整理内容", 17, bp_rgba(73, 158, 177, 210), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
end

-- ============================================================================
-- 公开接口: 绘制
-- ============================================================================

--- 绘制战前准备页面（新 UI）
---@param vg userdata NanoVG上下文
---@param SW number 屏幕宽
---@param SH number 屏幕高
---@param data table|nil 页面数据
function M.Draw(vg, SW, SH, data)
    data = bp_data(data)
    local ox, oy, s = bp_layout(SW, SH)
    nvgSave(vg)
    nvgTranslate(vg, ox, oy)
    nvgScale(vg, s, s)
    bp_outer_frame(vg)
    bp_draw_top(vg, data)
    bp_draw_warehouse(vg, data)
    bp_draw_center(vg, data)
    if data.mode ~= "buy" then
        bp_draw_cards(vg, data)
    end
    bp_draw_right(vg, data)
    bp_draw_footer(vg)
    nvgRestore(vg)
end

--- 绘制拖拽视觉反馈（高亮目标区 + 物品跟随光标）
--- 在 Draw 之后调用，绘制在最顶层
---@param vg userdata NanoVG上下文
---@param SW number 屏幕宽
---@param SH number 屏幕高
---@param dragInfo table|nil { dragItem, dragX, dragY, hoverZone, activeTab }
function M.DrawDragOverlay(vg, SW, SH, dragInfo)
    if not dragInfo or not dragInfo.dragItem then return end
    local ox, oy, s = bp_layout(SW, SH)
    local hoverZone = dragInfo.hoverZone
    local activeTab = dragInfo.activeTab or "sell"

    -- 高亮目标区域
    nvgSave(vg)
    nvgTranslate(vg, ox, oy)
    nvgScale(vg, s, s)

    if hoverZone == "sell" and activeTab ~= "buy" then
        -- 出售区高亮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 540, 160, 500, 520, 6)
        nvgFillColor(vg, bp_rgba(0, 200, 210, 30))
        nvgFill(vg)
        nvgStrokeColor(vg, bp_rgba(0, 230, 240, 180))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
        bp_text(vg, 790, 540, "松开出售", 26, bp_rgba(0, 240, 250, 220), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    elseif hoverZone == "loadout" then
        -- 装备区高亮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 1060, 140, 380, 560, 6)
        nvgFillColor(vg, bp_rgba(80, 200, 80, 25))
        nvgFill(vg)
        nvgStrokeColor(vg, bp_rgba(100, 230, 100, 180))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
        bp_text(vg, 1250, 430, "松开出战", 26, bp_rgba(120, 240, 130, 220), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    end

    nvgRestore(vg)

    -- 物品跟随光标（绘制在屏幕空间，不做设计坐标变换）
    local item = dragInfo.dragItem
    local dx, dy = dragInfo.dragX or 0, dragInfo.dragY or 0
    local iconSize = 36 * s
    nvgSave(vg)
    nvgGlobalAlpha(vg, 0.85)
    bp_fill_round(vg, dx - iconSize / 2, dy - iconSize / 2, iconSize, iconSize, 4, bp_rgba(15, 25, 30, 220))
    bp_stroke_round(vg, dx - iconSize / 2, dy - iconSize / 2, iconSize, iconSize, 4, bp_rgba(0, 200, 210, 200), 2)
    bp_text(vg, dx, dy, item.icon or "📦", iconSize * 0.55, bp_rgba(255, 255, 255, 255), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    nvgRestore(vg)
end

-- ============================================================================
-- 公开接口: 命中测试
-- ============================================================================

--- 战前准备页面点击检测
---@param mx number 鼠标/触摸 X（屏幕坐标）
---@param my number 鼠标/触摸 Y（屏幕坐标）
---@param SW number 屏幕宽
---@param SH number 屏幕高
---@param state table|nil 可选状态 { activeTab, activeVendorId, buyScrollY, vendors }
---@return string|table|nil
function M.HitTest(mx, my, SW, SH, state)
    local x, y = bp_to_base(mx, my, SW, SH)
    state = state or {}

    -- Tab 切换（两个 tab 始终可点）
    if bp_in_rect(x, y, 558, 118, 226, 52) then return "tab_sell" end
    if bp_in_rect(x, y, 798, 118, 222, 52) then return "tab_buy" end

    -- 右侧装备槽 + 出发/返回（两个 tab 都可用）
    if bp_in_rect(x, y, 1080, 166, 342, 92) then return "slot_main_weapon" end
    if bp_in_rect(x, y, 1080, 263, 342, 92) then return "slot_sub_weapon" end
    if bp_in_rect(x, y, 1080, 360, 342, 92) then return "slot_armor" end
    if bp_in_rect(x, y, 1080, 457, 342, 92) then return "slot_bag" end
    if bp_in_rect(x, y, 1080, 559, 158, 112) then return "slot_consumable" end
    if bp_in_rect(x, y, 1246, 559, 176, 112) then return "slot_key_item" end
    if bp_in_rect(x, y, 1062, 796, 384, 112) then return "start" end
    if bp_in_rect(x, y, 1060, 924, 385, 70) then return "back" end

    -- 仓库格子（两个 tab 都可拖拽）
    -- 整个网格区域命中：点击任意格子或格间间隔都映射到最近的 col/row
    local cell, gap = 42, 6
    local gx, gy = 50, 165
    local gridTotalW = 10 * cell + 9 * gap  -- 474
    local gridTotalH = 10 * cell + 9 * gap  -- 474
    if bp_in_rect(x, y, gx, gy, gridTotalW, gridTotalH) then
        local relX = x - gx
        local relY = y - gy
        local step = cell + gap  -- 48
        local col = math.min(math.floor(relX / step), 9)
        local row = math.min(math.floor(relY / step), 9)
        return string.format("warehouse_%02d", row * 10 + col + 1)
    end

    -- 根据当前 tab 区分中间面板交互
    local activeTab = state.activeTab or "sell"

    if activeTab == "buy" then
        -- 商人选择条
        local vendors = state.vendors or {}
        local vBtnW = math.floor(BUY_LIST_W / math.max(1, #vendors))
        for i, v in ipairs(vendors) do
            local bx = BUY_LIST_X + (i - 1) * vBtnW
            if bp_in_rect(x, y, bx, BUY_VENDOR_Y, vBtnW - 4, BUY_VENDOR_H) then
                return { action = "selectVendor", vendorId = v.id }
            end
        end

        -- 商品列表购买按钮
        if bp_in_rect(x, y, BUY_LIST_X, BUY_LIST_Y, BUY_LIST_W, BUY_LIST_H) then
            local scrollY = state.buyScrollY or 0
            local activeVendorId = state.activeVendorId or (vendors[1] and vendors[1].id or "")
            local shopItems = {}
            for _, v in ipairs(vendors) do
                if v.id == activeVendorId then shopItems = v.shop or {}; break end
            end
            for i, _ in ipairs(shopItems) do
                local rowY = BUY_LIST_Y + (i - 1) * BUY_ITEM_H - scrollY
                if rowY + BUY_ITEM_H > BUY_LIST_Y and rowY < BUY_LIST_Y + BUY_LIST_H then
                    local btnX = BUY_LIST_X + BUY_LIST_W - BUY_SCROLL_W - 78
                    local btnY = rowY + 12
                    local btnW = 60
                    local btnH = BUY_ITEM_H - 24
                    if bp_in_rect(x, y, btnX, btnY, btnW, btnH) then
                        return { action = "buyFrom", vendorIdx = i }
                    end
                end
            end
        end
    else
        -- 出售 tab 交互
        -- 待售物品列表点击（取回）
        local pending = state.sellPending or {}
        if #pending > 0 then
            local showCount = math.min(#pending, SELL_LIST_MAX)
            for i = 1, showCount do
                local rowY = SELL_LIST_Y + (i - 1) * SELL_ITEM_H
                if bp_in_rect(x, y, SELL_LIST_X, rowY, SELL_LIST_W, SELL_ITEM_H - 4) then
                    return { action = "removePending", itemIdx = i }
                end
            end
        end
        if bp_in_rect(x, y, 564, 493, 448, 52) then return "sell_drop_zone" end
        if bp_in_rect(x, y, 550, 605, 232, 48) then return "sell_all" end
        if bp_in_rect(x, y, 796, 605, 232, 48) then return "confirm_sell" end
        if bp_in_rect(x, y, 548, 728, 142, 260) then return "tip_1" end
        if bp_in_rect(x, y, 705, 728, 142, 260) then return "tip_2" end
        if bp_in_rect(x, y, 862, 728, 164, 260) then return "tip_3" end
    end

    return nil
end

-- ============================================================================
-- 公开接口: 拖拽悬停区域检测
-- 用于鼠标拖拽过程中判断当前悬停在哪个功能区
-- ============================================================================

--- 判断拖拽时鼠标所在的功能区
---@param mx number 屏幕鼠标 X
---@param my number 屏幕鼠标 Y
---@param SW number 屏幕宽
---@param SH number 屏幕高
---@return string|nil "sell"|"loadout"|nil
function M.GetDragZone(mx, my, SW, SH)
    local x, y = bp_to_base(mx, my, SW, SH)
    -- 出售区域（中间面板，包含 sell_drop_zone 及附近区域）
    if bp_in_rect(x, y, 540, 160, 500, 520) then return "sell" end
    -- 装备区域（右侧面板，包含所有装备槽位）
    if bp_in_rect(x, y, 1060, 140, 380, 560) then return "loadout" end
    return nil
end

-- ============================================================================
-- 公开接口: 数据适配器
-- 将游戏现有的 stash + loadoutState 转换为新 UI 所需的 data 格式
-- ============================================================================

--- 从游戏状态构建新 UI 的 data table
---@param stash table 仓库对象（含 money, inv, level 等）
---@param loadoutState table 当前 loadout 交互状态
---@return table
function M.BuildData(stash, loadoutState)
    loadoutState = loadoutState or {}
    local inv = stash.inv or {}
    local items = inv.items or {}
    local loadoutItems = loadoutState.loadoutItems or {}

    -- 计算仓库已用格数
    local storageUsed = #items

    -- 计算仓库总价值
    local storageValue = 0
    local Stash = require("Stash")
    for _, entry in ipairs(items) do
        local bestPrice = 0
        for _, v in ipairs(Stash.VENDORS) do
            local p = Stash.GetSellPrice(entry, v)
            if p > bestPrice then bestPrice = p end
        end
        storageValue = storageValue + bestPrice
    end

    -- 计算待售总收益
    local totalSell = 0
    local sellPending = loadoutState.sellPending or {}
    for _, entry in ipairs(sellPending) do
        local bestPrice = 0
        for _, v in ipairs(Stash.VENDORS) do
            local p = Stash.GetSellPrice(entry, v)
            if p > bestPrice then bestPrice = p end
        end
        totalSell = totalSell + bestPrice
    end

    -- 计算出战装备的负重
    local weight = 0
    local Data = require("Data")
    for _, entry in ipairs(loadoutItems) do
        if entry.data and entry.data.weight then
            weight = weight + entry.data.weight
        end
    end

    -- 计算准备度（装备数量，最高8）
    local readiness = math.min(8, #loadoutItems)

    -- 构建装备槽显示（含 icon）
    local loadout = {
        mainWeapon = nil,
        subWeapon = nil,
        armor = nil,
        bag = nil,
        consumable = nil,
        keyItem = nil,
    }
    -- 根据装备类型填充槽位
    for _, entry in ipairs(loadoutItems) do
        local itype = entry.itype or ""
        local name = (entry.data and entry.data.name) or entry.name or "物品"
        local icon = entry.icon or (entry.data and entry.data.icon) or "📦"
        local slot = { name = name, icon = icon, itype = itype, data = entry.data }
        if itype == "weapon" then
            if not loadout.mainWeapon then
                loadout.mainWeapon = slot
            elseif not loadout.subWeapon then
                loadout.subWeapon = slot
            end
        elseif itype == "armor" then
            loadout.armor = slot
        elseif itype == "bag" then
            loadout.bag = slot
        elseif itype == "consumable" then
            loadout.consumable = slot
        elseif itype == "key" then
            loadout.keyItem = slot
        end
    end

    -- 仓库容量
    local storageCapacity = (inv.width or 10) * (inv.height or 10)

    -- 最大负重
    local maxWeight = 25.0

    -- 是否首次出战
    local isFirstRaid = (#items == 0 and #loadoutItems == 0)

    -- 商人数据（购买 tab 使用）
    local vendors = {}
    for _, v in ipairs(Stash.VENDORS) do
        table.insert(vendors, {
            id   = v.id,
            name = v.name,
            icon = v.icon,
            shop = v.shop,
        })
    end

    return {
        gold = stash.money or 0,
        mode = loadoutState.activeTab or "sell",
        storageUsed = storageUsed,
        storageCapacity = storageCapacity,
        storageValue = storageValue,
        warehouseItems = items,
        totalSell = totalSell,
        sellPending = sellPending,
        weight = weight,
        maxWeight = maxWeight,
        readiness = readiness,
        isFirstRaid = isFirstRaid,
        loadout = loadout,
        cards = nil, -- 使用默认卡片
        -- 购买 tab 数据
        vendors = vendors,
        activeVendorId = loadoutState.activeVendorId or (Stash.VENDORS[1] and Stash.VENDORS[1].id or ""),
        buyScrollY = loadoutState.buyScrollY or 0,
        -- 弹药储备
        ammo = stash.ammo or {},
    }
end

return M
