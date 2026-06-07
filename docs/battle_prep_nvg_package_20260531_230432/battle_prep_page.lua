-- NanoVG battle preparation page.
-- Usage:
--   DrawBattlePrep(vg, SW, SH, data)
--   local hit = HitTestBattlePrep(mx, my, SW, SH)
--
-- Data table fields are optional:
--   gold, mode("sell"|"buy"), storageUsed, storageCapacity, storageValue,
--   totalSell, weight, maxWeight, readiness, isFirstRaid,
--   loadout = {
--     mainWeapon, subWeapon, armor, bag, consumable, keyItem
--   },
--   cards = {
--     {title="", body="", tone="green"},
--     {title="", body="", tone="blue"},
--     {title="", body="", tone="red"}
--   }

local BP_BASE_W = 1470
local BP_BASE_H = 1080

local function bp_rgba(r, g, b, a)
    return nvgRGBA(r, g, b, a or 255)
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
    bp_line(vg, x + 4, y + 35, x + 38, y + 2, bp_rgba(225, 226, 214, 255), 6)
    bp_line(vg, x + 38, y + 35, x + 4, y + 2, bp_rgba(225, 226, 214, 255), 6)
    bp_line(vg, x + 8, y + 37, x + 18, y + 27, bp_rgba(244, 142, 41, 255), 4)
    bp_line(vg, x + 34, y + 37, x + 24, y + 27, bp_rgba(244, 142, 41, 255), 4)
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
    for row = 0, 9 do
        for col = 0, 9 do
            local idx = row * 10 + col + 1
            bp_draw_cell(vg, gx + col * (cell + gap), gy + row * (cell + gap), cell, idx, idx <= used)
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

local function bp_draw_center(vg, data)
    bp_panel(vg, 538, 104, 505, 900)
    bp_draw_tabs(vg, data)
    bp_stroke_round(vg, 550, 186, 477, 397, 3, bp_rgba(82, 86, 82, 150), 2)
    bp_draw_cat_scene(vg, 556, 192, 465, 386)
    bp_text(vg, 792, 394, "首次出战，当前暂无战利品", 30, bp_rgba(21, 229, 235, 255), "bold", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_text(vg, 792, 440, "完成一局后，可将搜刮到的物品", 19, bp_rgba(222, 211, 198, 230), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
    bp_text(vg, 792, 467, "带回并在这里出售或整理", 19, bp_rgba(222, 211, 198, 230), "sans", NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
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

local function bp_draw_equip_slot(vg, x, y, w, h, title, value, kind)
    bp_fill_round(vg, x, y, w, h, 3, bp_rgba(8, 14, 18, 238))
    bp_stroke_round(vg, x, y, w, h, 3, bp_rgba(83, 79, 70, 140), 2)
    bp_text(vg, x + 18, y + 20, title, 20, bp_rgba(231, 210, 173, 240), "bold", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
    bp_draw_weapon_icon(vg, x + 95, y + 9, 115, h - 18, kind)
    bp_text(vg, x + w - 34, y + h / 2, value or "未装备", 19, bp_rgba(176, 158, 137, 210), "sans", NVG_ALIGN_RIGHT | NVG_ALIGN_MIDDLE)
end

local function bp_draw_right(vg, data)
    bp_panel(vg, 1060, 104, 385, 900)
    bp_text(vg, 1086, 137, "出战装备", 24, bp_rgba(75, 224, 255, 255), "bold")
    bp_text(vg, 1238, 139, "（点击放入装备）", 16, bp_rgba(75, 224, 255, 210), "sans")

    local loadout = data.loadout or {}
    bp_draw_equip_slot(vg, 1080, 166, 342, 92, "主武器", loadout.mainWeapon or "未装备", "gun")
    bp_draw_equip_slot(vg, 1080, 263, 342, 92, "副武器", loadout.subWeapon or "未装备", "gun")
    bp_draw_equip_slot(vg, 1080, 360, 342, 92, "护甲", loadout.armor or "未装备", "armor")
    bp_draw_equip_slot(vg, 1080, 457, 342, 92, "背包", loadout.bag or "未装备", "bag")
    bp_draw_equip_slot(vg, 1080, 559, 158, 112, "消耗品", loadout.consumable or "未装备", "plus")
    bp_draw_equip_slot(vg, 1246, 559, 176, 112, "钥匙道具", loadout.keyItem or "未装备", "key")

    bp_text(vg, 1095, 700, "▣", 22, bp_rgba(234, 227, 209, 255), "bold", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
    bp_fill_round(vg, 1118, 688, 300, 24, 3, bp_rgba(2, 6, 7, 240))
    bp_fill_round(vg, 1121, 691, math.min(294, 294 * ((data.weight or 0) / math.max(1, data.maxWeight or 25))), 18, 2, bp_rgba(25, 67, 71, 210))
    bp_stroke_round(vg, 1118, 688, 300, 24, 3, bp_rgba(47, 50, 48, 170), 1)
    bp_text(vg, 1376, 700, string.format("%.1f / %.1f", data.weight or 0, data.maxWeight or 25), 18, bp_rgba(230, 216, 193, 245), "bold", NVG_ALIGN_RIGHT | NVG_ALIGN_MIDDLE)

    bp_text(vg, 1083, 753, "准备度", 19, bp_rgba(230, 216, 193, 235), "bold", NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
    local ready = data.readiness or 5
    for i = 1, 8 do
        bp_draw_paw(vg, 1161 + i * 26, 753, 13, i <= ready and bp_rgba(112, 160, 119, 220) or bp_rgba(62, 73, 65, 190))
    end
    bp_text(vg, 1418, 753, (data.isFirstRaid == false) and "准备出发" or "初次出发", 19, bp_rgba(62, 220, 255, 255), "bold", NVG_ALIGN_RIGHT | NVG_ALIGN_MIDDLE)

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

--- 绘制战前准备页面。
---@param vg userdata NanoVG上下文
---@param SW number 屏幕宽
---@param SH number 屏幕高
---@param data table|nil 页面数据，字段见文件顶部注释
function DrawBattlePrep(vg, SW, SH, data)
    data = bp_data(data)
    local ox, oy, s = bp_layout(SW, SH)
    nvgSave(vg)
    nvgTranslate(vg, ox, oy)
    nvgScale(vg, s, s)
    bp_outer_frame(vg)
    bp_draw_top(vg, data)
    bp_draw_warehouse(vg, data)
    bp_draw_center(vg, data)
    bp_draw_cards(vg, data)
    bp_draw_right(vg, data)
    bp_draw_footer(vg)
    nvgRestore(vg)
end

--- 战前准备页面点击检测。
--- 返回值：
--- "tab_sell" / "tab_buy" / "sell_drop_zone" / "sell_all" / "confirm_sell"
--- "warehouse_01".."warehouse_100"
--- "slot_main_weapon" / "slot_sub_weapon" / "slot_armor" / "slot_bag" / "slot_consumable" / "slot_key_item"
--- "tip_1" / "tip_2" / "tip_3" / "start" / "back"
---@param mx number 鼠标/触摸 X
---@param my number 鼠标/触摸 Y
---@param SW number 屏幕宽
---@param SH number 屏幕高
---@return string|nil
function HitTestBattlePrep(mx, my, SW, SH)
    local x, y = bp_to_base(mx, my, SW, SH)

    if bp_in_rect(x, y, 558, 118, 226, 52) then return "tab_sell" end
    if bp_in_rect(x, y, 798, 118, 222, 52) then return "tab_buy" end
    if bp_in_rect(x, y, 564, 493, 448, 52) then return "sell_drop_zone" end
    if bp_in_rect(x, y, 550, 605, 232, 48) then return "sell_all" end
    if bp_in_rect(x, y, 796, 605, 232, 48) then return "confirm_sell" end
    if bp_in_rect(x, y, 548, 728, 142, 260) then return "tip_1" end
    if bp_in_rect(x, y, 705, 728, 142, 260) then return "tip_2" end
    if bp_in_rect(x, y, 862, 728, 164, 260) then return "tip_3" end

    if bp_in_rect(x, y, 1080, 166, 342, 92) then return "slot_main_weapon" end
    if bp_in_rect(x, y, 1080, 263, 342, 92) then return "slot_sub_weapon" end
    if bp_in_rect(x, y, 1080, 360, 342, 92) then return "slot_armor" end
    if bp_in_rect(x, y, 1080, 457, 342, 92) then return "slot_bag" end
    if bp_in_rect(x, y, 1080, 559, 158, 112) then return "slot_consumable" end
    if bp_in_rect(x, y, 1246, 559, 176, 112) then return "slot_key_item" end
    if bp_in_rect(x, y, 1062, 796, 384, 112) then return "start" end
    if bp_in_rect(x, y, 1060, 924, 385, 70) then return "back" end

    local cell, gap = 42, 6
    local gx, gy = 50, 165
    for row = 0, 9 do
        for col = 0, 9 do
            local cx = gx + col * (cell + gap)
            local cy = gy + row * (cell + gap)
            if bp_in_rect(x, y, cx, cy, cell, cell) then
                return string.format("warehouse_%02d", row * 10 + col + 1)
            end
        end
    end

    return nil
end

