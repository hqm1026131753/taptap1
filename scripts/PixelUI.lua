-- ============================================================
-- PixelUI.lua
-- 像素/8-bit 风格 UI 渲染管线
-- 适配 UrhoX NanoVG 全局 API（nvgXxx(ctx, ...)）
--
-- 设计原则：
--   · 圆角 = 0（所有元素硬边）
--   · 无模糊阴影，改用 1-2px 硬偏移阴影
--   · 1px 硬边描边（黑色/白色）
--   · 可选像素噪点纹理叠加
--   · 限制色板（深色调为主）
-- ============================================================

local M = {}

-- ── 纹理缓存 ──────────────────────────────────────────────────
local textureCache = {}
local NOISE_PATH = "image/pixel_noise_8_20260529065433.png"

local function getTexture(ctx, path)
    if textureCache[path] ~= nil then
        local cached = textureCache[path]
        return (cached > 0) and cached or nil
    end
    local tex = nvgCreateImage(ctx, path, 3)  -- NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY
    if tex and tex > 0 then
        textureCache[path] = tex
        return tex
    end
    textureCache[path] = 0  -- 缓存失败，避免每帧重试
    return nil
end

-- ── 色板 ──────────────────────────────────────────────────────
M.Colors = {
    bg_dark   = { 12, 16, 22, 240 },     -- 最深背景
    bg_panel  = { 22, 28, 38, 230 },      -- 面板背景
    bg_btn    = { 32, 38, 52, 240 },      -- 按钮背景
    bg_hover  = { 50, 60, 80, 245 },      -- 按钮 hover
    bg_press  = { 18, 22, 32, 250 },      -- 按钮 pressed
    border    = { 0, 0, 0, 255 },         -- 外描边（黑）
    border_in = { 60, 70, 90, 180 },      -- 内描边（暗灰）
    highlight = { 255, 255, 255, 35 },    -- 顶部高光线
    accent    = { 0, 240, 220, 230 },     -- 强调色（青绿）
    gold      = { 255, 200, 60, 230 },    -- 金色强调
    text      = { 220, 220, 240, 240 },   -- 主文字
    text_dim  = { 140, 140, 170, 180 },   -- 次要文字
    shadow    = { 0, 0, 0, 120 },         -- 硬阴影
}

-- ── 辅助：RGBA 展开 ─────────────────────────────────────────
local function rgba(c)
    return nvgRGBA(c[1], c[2], c[3], c[4])
end

-- 带 alpha 覆盖
local function rgbaA(c, a)
    return nvgRGBA(c[1], c[2], c[3], a)
end

-- ============================================================
-- DrawPanel: 像素风面板
-- 参数:
--   ctx: NanoVG 上下文
--   x, y, w, h: 位置与尺寸
--   opts: 可选配置表 {
--     bg      = {r,g,b,a},  -- 背景色（默认 bg_panel）
--     border  = true/false, -- 是否绘制边框（默认 true）
--     shadow  = true/false, -- 是否绘制硬阴影（默认 true）
--     noise   = true/false, -- 是否叠加像素噪点（默认 true）
--     noiseAlpha = 0-255,   -- 噪点透明度（默认 18）
--     highlight = true/false, -- 是否绘制顶部高光线（默认 true）
--     borderColor = {r,g,b,a}, -- 自定义边框色
--   }
-- ============================================================
function M.DrawPanel(ctx, x, y, w, h, opts)
    opts = opts or {}
    local bgColor   = opts.bg or M.Colors.bg_panel
    local doBorder  = opts.border ~= false
    local doShadow  = opts.shadow ~= false
    local doNoise   = opts.noise ~= false
    local noiseA    = opts.noiseAlpha or 18
    local doHL      = opts.highlight ~= false
    local borderC   = opts.borderColor or M.Colors.border

    -- L0: 硬阴影（2px 向下偏移，不模糊）
    if doShadow then
        nvgBeginPath(ctx)
        nvgRect(ctx, x + 2, y + 2, w, h)
        nvgFillColor(ctx, rgba(M.Colors.shadow))
        nvgFill(ctx)
    end

    -- L1: 背景填充（纯色，无渐变）
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y, w, h)
    nvgFillColor(ctx, rgba(bgColor))
    nvgFill(ctx)

    -- L8: 像素噪点纹理叠加
    if doNoise and noiseA > 0 then
        local tex = getTexture(ctx, NOISE_PATH)
        if tex then
            local pat = nvgImagePattern(ctx, x, y, 64, 64, 0, tex, noiseA / 255.0)
            nvgBeginPath(ctx)
            nvgRect(ctx, x, y, w, h)
            nvgFillPaint(ctx, pat)
            nvgFill(ctx)
        end
    end

    -- L3: 顶部高光线（1px 硬边，非渐变）
    if doHL then
        nvgBeginPath(ctx)
        nvgRect(ctx, x + 1, y + 1, w - 2, 1)
        nvgFillColor(ctx, rgba(M.Colors.highlight))
        nvgFill(ctx)
    end

    -- L6: 内描边（1px）
    if doBorder then
        nvgBeginPath(ctx)
        nvgRect(ctx, x, y, w, h)
        nvgStrokeColor(ctx, rgba(borderC))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
        -- 内侧亮边（上+左 各1px）
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, x + 1, y + h - 1)
        nvgLineTo(ctx, x + 1, y + 1)
        nvgLineTo(ctx, x + w - 1, y + 1)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 20))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
        -- 外侧暗边（下+右 各1px）
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, x + 1, y + h - 1)
        nvgLineTo(ctx, x + w - 1, y + h - 1)
        nvgLineTo(ctx, x + w - 1, y + 1)
        nvgStrokeColor(ctx, nvgRGBA(0, 0, 0, 60))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
    end
end

-- ============================================================
-- DrawButton: 像素风按钮
-- 参数:
--   state: "normal" / "hover" / "pressed" / "disabled"
--   opts: 同 DrawPanel + {
--     accentLeft = true/false,  -- 左侧竖条装饰（默认 false）
--     accentColor = {r,g,b,a}, -- 竖条颜色
--   }
-- ============================================================
function M.DrawButton(ctx, x, y, w, h, stateOrLabel, opts)
    opts = opts or {}

    -- 兼容两种调用方式：
    -- 1. DrawButton(ctx, x,y,w,h, "normal"/"hover"/..., opts)  -- 无文字
    -- 2. DrawButton(ctx, x,y,w,h, "文字标签", { state="normal", textColor=..., fontSize=... })  -- 带文字
    local state, label
    local VALID_STATES = { normal=true, hover=true, pressed=true, disabled=true, active=true }
    if opts.state or (stateOrLabel and not VALID_STATES[stateOrLabel]) then
        -- 第6参数是文字标签，按钮状态从 opts.state 取
        label = stateOrLabel
        state = opts.state or "normal"
    else
        state = stateOrLabel or "normal"
        label = nil
    end

    -- 根据状态选择背景色
    local bg
    if state == "hover" then
        bg = opts.bg_hover or M.Colors.bg_hover
    elseif state == "pressed" then
        bg = opts.bg_press or M.Colors.bg_press
    elseif state == "disabled" then
        bg = { 30, 30, 40, 150 }
    else
        bg = opts.bg or M.Colors.bg_btn
    end

    -- pressed 状态：取消阴影，位移 1px 表示按下
    local offsetY = 0
    if state == "pressed" then
        offsetY = 1
        opts.shadow = false
    end

    -- 绘制面板基底
    -- opts.border 如果是颜色表则用作 borderColor
    local borderC = opts.borderColor
        or (type(opts.border) == "table" and opts.border)
        or (state == "hover" and M.Colors.accent or M.Colors.border)
    M.DrawPanel(ctx, x, y + offsetY, w, h, {
        bg = bg,
        border = true,
        shadow = state ~= "pressed",
        noise = state ~= "disabled",
        noiseAlpha = state == "hover" and 25 or 15,
        highlight = state ~= "pressed" and state ~= "disabled",
        borderColor = borderC,
    })

    -- hover 时外发光描边效果（像素风简化：加粗外描边）
    if state == "hover" then
        nvgBeginPath(ctx)
        nvgRect(ctx, x - 1, y + offsetY - 1, w + 2, h + 2)
        nvgStrokeColor(ctx, rgbaA(M.Colors.accent, 100))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
    end

    -- 左侧竖条装饰（可选）
    if opts.accentLeft then
        local ac = opts.accentColor or M.Colors.gold
        nvgBeginPath(ctx)
        nvgRect(ctx, x, y + offsetY, 3, h)
        nvgFillColor(ctx, rgba(ac))
        nvgFill(ctx)
    end

    -- 文字标签（当 label 存在时绘制）
    if label then
        nvgFontFace(ctx, opts.fontFace or "sans")
        nvgFontSize(ctx, opts.fontSize or 12)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local tc = opts.textColor or M.Colors.text
        nvgFillColor(ctx, rgba(tc))
        nvgText(ctx, x + w/2, y + offsetY + h/2, label, nil)
    end
end

-- ============================================================
-- DrawBar: 像素风进度条/血条
-- 参数:
--   ratio: 0.0 ~ 1.0 填充比例
--   opts: {
--     bgColor     = {r,g,b,a},  -- 槽背景色
--     fillColor   = {r,g,b,a},  -- 填充色
--     border      = true/false,
--     height      = 数字,        -- 覆盖 h
--   }
-- ============================================================
function M.DrawBar(ctx, x, y, w, h, ratio, opts)
    opts = opts or {}
    ratio = math.max(0, math.min(1, ratio))
    local bgC = opts.bgColor or { 10, 14, 20, 200 }
    local fillC = opts.fillColor or M.Colors.accent
    local doBorder = opts.border ~= false

    -- 背景槽
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y, w, h)
    nvgFillColor(ctx, rgba(bgC))
    nvgFill(ctx)

    -- 填充部分
    if ratio > 0 then
        local fw = math.max(1, math.floor(w * ratio))
        nvgBeginPath(ctx)
        nvgRect(ctx, x, y, fw, h)
        nvgFillColor(ctx, rgba(fillC))
        nvgFill(ctx)
        -- 顶部 1px 亮线
        nvgBeginPath(ctx)
        nvgRect(ctx, x, y, fw, 1)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 40))
        nvgFill(ctx)
    end

    -- 边框
    if doBorder then
        nvgBeginPath(ctx)
        nvgRect(ctx, x, y, w, h)
        nvgStrokeColor(ctx, nvgRGBA(0, 0, 0, 200))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
    end
end

-- ============================================================
-- DrawCard: 像素风卡片（奖励面板用）
-- 带有顶部色条 + 像素边框
-- ============================================================
function M.DrawCard(ctx, x, y, w, h, opts)
    opts = opts or {}
    local accentH = opts.accentHeight or 4
    local accentC = opts.accentColor or M.Colors.accent

    -- 主面板
    M.DrawPanel(ctx, x, y, w, h, {
        bg = opts.bg or M.Colors.bg_panel,
        border = true,
        shadow = true,
        noise = true,
        noiseAlpha = 12,
    })

    -- 顶部色条
    nvgBeginPath(ctx)
    nvgRect(ctx, x + 1, y + 1, w - 2, accentH)
    nvgFillColor(ctx, rgba(accentC))
    nvgFill(ctx)
end

-- ============================================================
-- DrawTooltip: 像素风 Tooltip 浮窗
-- ============================================================
function M.DrawTooltip(ctx, x, y, w, h)
    M.DrawPanel(ctx, x, y, w, h, {
        bg = { 8, 10, 16, 245 },
        border = true,
        shadow = true,
        noise = false,
        highlight = false,
        borderColor = M.Colors.accent,
    })
end

-- ============================================================
-- DrawSeparator: 像素风分隔线
-- ============================================================
function M.DrawSeparator(ctx, x, y, w)
    -- 暗线
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y, w, 1)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 100))
    nvgFill(ctx)
    -- 亮线（下方1px）
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y + 1, w, 1)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 15))
    nvgFill(ctx)
end

-- ============================================================
-- DrawBadge: 像素风标签/徽章（如稀有度标签）
-- ============================================================
function M.DrawBadge(ctx, x, y, w, h, color)
    color = color or M.Colors.accent
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y, w, h)
    nvgFillColor(ctx, rgba(color))
    nvgFill(ctx)
    -- 1px 黑边
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y, w, h)
    nvgStrokeColor(ctx, nvgRGBA(0, 0, 0, 200))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)
end

return M
