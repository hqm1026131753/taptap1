-- ============================================================================
-- SkillTreeUI.lua — 技能树 UI 渲染 + 交互检测
-- 全屏面板，三列分支，纵向排布节点
-- ============================================================================
local SkillTree = require("SkillTree")
local PixelUI   = require("PixelUI")

local M = {}

-- ============================================================================
-- 布局常量
-- ============================================================================
local NODE_SIZE      = 36       -- 节点图形尺寸（菱形/六角外接圆直径）
local NODE_GAP_Y     = 52       -- 节点纵向间距
local BRANCH_GAP_X   = 180      -- 分支列间距
local FORK_OFFSET_X  = 40       -- 分叉左右偏移
local HEADER_H       = 60       -- 顶部标题区高度
local FOOTER_H       = 50       -- 底部信息区高度
local PANEL_PAD      = 16       -- 面板内边距

-- 颜色
local COL_UNLOCKED   = {80, 240, 120, 255}    -- 已解锁 绿色
local COL_AVAILABLE  = {255, 220, 80, 255}    -- 可解锁 金色闪烁
local COL_LOCKED     = {80, 90, 100, 160}     -- 上锁 灰色
local COL_CORE_RING  = {200, 120, 255, 255}   -- 核心节点外圈
local COL_LINE       = {60, 70, 80, 180}      -- 连线
local COL_LINE_ON    = {80, 200, 120, 200}    -- 已解锁连线
local COL_BG         = {10, 12, 16, 245}      -- 面板背景
local COL_HEADER_BG  = {18, 22, 30, 240}      -- 标题栏

-- ============================================================================
-- 布局计算（每帧缓存）
-- ============================================================================

---@class NodeLayout
---@field node table
---@field x number
---@field y number
---@field status string

--- 计算单个分支的节点布局
---@param nodes table[] 分支节点定义
---@param centerX number 分支中心 X
---@param startY number 起始 Y
---@param state table 技能树状态
---@return NodeLayout[]
local function LayoutBranch(nodes, centerX, startY, state)
    local layouts = {}
    local y = startY
    for _, node in ipairs(nodes) do
        local x = centerX
        -- 分叉节点偏移
        if node.side == "left" then
            x = centerX - FORK_OFFSET_X
        elseif node.side == "right" then
            x = centerX + FORK_OFFSET_X
        end
        local status = SkillTree.GetNodeStatus(state, node)
        table.insert(layouts, { node = node, x = x, y = y, status = status })
        y = y + NODE_GAP_Y
    end
    return layouts
end

--- 计算完整布局
---@param sw number 屏幕宽
---@param sh number 屏幕高
---@param state table 技能树状态
---@return table layout { branches = {...}, panelRect = {...} }
function M.CalcLayout(sw, sh, state)
    -- 面板占满全屏（留小边距）
    local margin = 12
    local px, py = margin, margin
    local pw, ph = sw - margin * 2, sh - margin * 2

    local contentTop = py + HEADER_H + PANEL_PAD
    local contentH   = ph - HEADER_H - FOOTER_H - PANEL_PAD * 2

    -- 三列分支中心
    local cx = px + pw * 0.5
    local branchCenters = {
        cx - BRANCH_GAP_X,    -- 战斗
        cx,                   -- 搜刮
        cx + BRANCH_GAP_X,    -- 生存
    }

    local branches = {}
    local branchOrder = { "combat", "looting", "survival" }
    for i, branchId in ipairs(branchOrder) do
        local nodes = SkillTree.ALL_NODES[branchId]
        local layouts = LayoutBranch(nodes, branchCenters[i], contentTop + 20, state)
        branches[i] = {
            id = branchId,
            info = SkillTree.BRANCHES[i],
            centerX = branchCenters[i],
            nodes = layouts,
        }
    end

    return {
        panelRect = { x = px, y = py, w = pw, h = ph },
        branches  = branches,
        contentTop = contentTop,
    }
end

-- ============================================================================
-- 绘制
-- ============================================================================

--- 绘制菱形（普通节点）
local function DrawDiamond(ctx, cx, cy, size, fillColor, strokeColor)
    local hs = size * 0.5
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy - hs)
    nvgLineTo(ctx, cx + hs, cy)
    nvgLineTo(ctx, cx, cy + hs)
    nvgLineTo(ctx, cx - hs, cy)
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(fillColor[1], fillColor[2], fillColor[3], fillColor[4]))
    nvgFill(ctx)
    if strokeColor then
        nvgStrokeColor(ctx, nvgRGBA(strokeColor[1], strokeColor[2], strokeColor[3], strokeColor[4]))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)
    end
end

--- 绘制六角形（核心解锁节点）
local function DrawHexagon(ctx, cx, cy, radius, fillColor, strokeColor)
    nvgBeginPath(ctx)
    for i = 0, 5 do
        local angle = math.pi / 6 + i * math.pi / 3
        local x = cx + radius * math.cos(angle)
        local y = cy + radius * math.sin(angle)
        if i == 0 then nvgMoveTo(ctx, x, y)
        else nvgLineTo(ctx, x, y) end
    end
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(fillColor[1], fillColor[2], fillColor[3], fillColor[4]))
    nvgFill(ctx)
    if strokeColor then
        nvgStrokeColor(ctx, nvgRGBA(strokeColor[1], strokeColor[2], strokeColor[3], strokeColor[4]))
        nvgStrokeWidth(ctx, 2.5)
        nvgStroke(ctx)
    end
end

--- 绘制节点间连线
local function DrawConnection(ctx, x1, y1, x2, y2, isActive)
    local col = isActive and COL_LINE_ON or COL_LINE
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, x1, y1)
    -- 使用贝塞尔曲线使连线更自然
    local midY = (y1 + y2) * 0.5
    nvgBezierTo(ctx, x1, midY, x2, midY, x2, y2)
    nvgStrokeColor(ctx, nvgRGBA(col[1], col[2], col[3], col[4]))
    nvgStrokeWidth(ctx, isActive and 2.5 or 1.5)
    nvgStroke(ctx)
end

--- 绘制完整技能树面板
---@param ctx userdata NanoVG 上下文
---@param sw number 屏幕宽
---@param sh number 屏幕高
---@param state table 技能树状态
---@param stash table 仓库（用于显示材料）
---@param hoverNodeId string|nil 当前悬停的节点id
---@param time number 游戏时间（用于动画）
---@param scrollY number|nil 纵向滚动偏移（默认0）
function M.Draw(ctx, sw, sh, state, stash, hoverNodeId, time, scrollY)
    scrollY = scrollY or 0
    local layout = M.CalcLayout(sw, sh, state)
    local pr = layout.panelRect

    -- ── 背景遮罩 ──
    nvgBeginPath(ctx) nvgRect(ctx, 0, 0, sw, sh)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 200)) nvgFill(ctx)

    -- ── 主面板 ──
    PixelUI.DrawPanel(ctx, pr.x, pr.y, pr.w, pr.h, {
        bg = COL_BG,
        borderColor = {60, 70, 80, 200},
        noiseAlpha = 6,
    })

    -- ── 标题栏 ──
    nvgBeginPath(ctx) nvgRect(ctx, pr.x, pr.y, pr.w, HEADER_H)
    nvgFillColor(ctx, nvgRGBA(COL_HEADER_BG[1], COL_HEADER_BG[2], COL_HEADER_BG[3], COL_HEADER_BG[4]))
    nvgFill(ctx)

    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 20)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 240, 200, 255))
    nvgText(ctx, pr.x + pr.w * 0.5, pr.y + HEADER_H * 0.5, "🌳 技能树", nil)

    -- 技能点显示（避开左上角关闭按钮）
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 13)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(180, 220, 255, 230))
    nvgText(ctx, pr.x + 52, pr.y + HEADER_H * 0.5,
        string.format("⭐ 技能点: %d", state.skillPoints), nil)

    -- 材料显示
    nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    local matStr = string.format("⚙️%d  🧪%d  🧻%d",
        state.materials.combat,
        state.materials.looting,
        state.materials.survival)
    nvgFillColor(ctx, nvgRGBA(200, 200, 180, 220))
    nvgText(ctx, pr.x + pr.w - 20, pr.y + HEADER_H * 0.5, matStr, nil)

    -- ── 关闭按钮（左上角，手机端更易点击） ──
    local closeX = pr.x + 8
    local closeY = pr.y + 6
    local closeW, closeH = 36, 36
    PixelUI.DrawButton(ctx, closeX, closeY, closeW, closeH,
        (hoverNodeId == "__close") and "hover" or "normal", {
        bg = {60, 30, 30, 200},
        bg_hover = {120, 40, 40, 240},
        borderColor = {180, 60, 60, 200},
    })
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 200, 200, 255))
    nvgText(ctx, closeX + closeW * 0.5, closeY + closeH * 0.5, "✕", nil)

    -- ── 可滚动内容区域（裁剪 + 平移） ──
    local clipY = pr.y + HEADER_H
    local clipH = pr.h - HEADER_H - FOOTER_H
    nvgSave(ctx)
    nvgIntersectScissor(ctx, pr.x, clipY, pr.w, clipH)
    nvgTranslate(ctx, 0, -scrollY)

    -- ── 分支标题 ──
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for _, branch in ipairs(layout.branches) do
        local info = branch.info
        local unlocked, total = SkillTree.GetBranchProgress(state, branch.id)
        nvgFillColor(ctx, nvgRGBA(220, 220, 240, 240))
        nvgText(ctx, branch.centerX, layout.contentTop,
            string.format("%s %s (%d/%d)", info.icon, info.name, unlocked, total), nil)
    end

    -- ── 连线 ──
    for _, branch in ipairs(layout.branches) do
        local nodeMap = {}
        for _, nl in ipairs(branch.nodes) do
            nodeMap[nl.node.id] = nl
        end
        for _, nl in ipairs(branch.nodes) do
            for _, reqId in ipairs(nl.node.requires) do
                local parent = nodeMap[reqId]
                if parent then
                    local active = (nl.status == "unlocked" and parent.status == "unlocked")
                    DrawConnection(ctx, parent.x, parent.y + NODE_SIZE * 0.35,
                                        nl.x, nl.y - NODE_SIZE * 0.35, active)
                end
            end
        end
    end

    -- ── 节点 ──
    for _, branch in ipairs(layout.branches) do
        for _, nl in ipairs(branch.nodes) do
            local node = nl.node
            local isHover = (hoverNodeId == node.id)
            local fillColor, strokeColor

            if nl.status == "unlocked" then
                fillColor = {COL_UNLOCKED[1], COL_UNLOCKED[2], COL_UNLOCKED[3], 220}
                strokeColor = {255, 255, 255, 100}
            elseif nl.status == "available" then
                -- 闪烁效果
                local pulse = math.sin(time * 4) * 0.3 + 0.7
                local a = math.floor(pulse * 255)
                fillColor = {COL_AVAILABLE[1], COL_AVAILABLE[2], COL_AVAILABLE[3], a}
                strokeColor = {255, 255, 200, math.floor(pulse * 180)}
            else
                fillColor = {COL_LOCKED[1], COL_LOCKED[2], COL_LOCKED[3], COL_LOCKED[4]}
                strokeColor = {40, 45, 55, 160}
            end

            -- hover 高亮
            if isHover then
                strokeColor = {255, 255, 255, 220}
            end

            local size = NODE_SIZE
            if node.type == "core" then
                -- 外圈光环
                DrawHexagon(ctx, nl.x, nl.y, size * 0.58 + 3,
                    {COL_CORE_RING[1], COL_CORE_RING[2], COL_CORE_RING[3], nl.status == "unlocked" and 120 or 40}, nil)
                DrawHexagon(ctx, nl.x, nl.y, size * 0.58, fillColor, strokeColor)
            else
                DrawDiamond(ctx, nl.x, nl.y, size, fillColor, strokeColor)
            end

            -- 节点名称
            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, 10)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            local textAlpha = (nl.status == "locked") and 120 or 220
            nvgFillColor(ctx, nvgRGBA(220, 220, 240, textAlpha))
            nvgText(ctx, nl.x, nl.y + size * 0.5 + 3, node.name, nil)
        end
    end

    -- ── 结束可滚动区域 ──
    nvgRestore(ctx)

    -- ── 悬停 Tooltip ──
    if hoverNodeId and hoverNodeId ~= "__close" then
        M.DrawTooltip(ctx, sw, sh, state, hoverNodeId, layout, stash, scrollY)
    end

    -- ── 底部操作提示 ──
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 11)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, nvgRGBA(140, 150, 160, 180))
    nvgText(ctx, pr.x + pr.w * 0.5, pr.y + pr.h - 12,
        "点击可解锁节点  |  ESC 或 ✕ 关闭", nil)
end

-- ============================================================================
-- Tooltip 绘制
-- ============================================================================
function M.DrawTooltip(ctx, sw, sh, state, nodeId, layout, stash, scrollY)
    scrollY = scrollY or 0
    -- 查找节点
    local targetNode = nil
    local targetNL = nil
    for _, branch in ipairs(layout.branches) do
        for _, nl in ipairs(branch.nodes) do
            if nl.node.id == nodeId then
                targetNode = nl.node
                targetNL = nl
                break
            end
        end
        if targetNode then break end
    end
    if not targetNode then return end

    -- Tooltip 位置（节点右侧，考虑滚动偏移）
    local nodeScreenY = targetNL.y - scrollY
    local ttW, ttH = 180, 120
    local ttX = targetNL.x + NODE_SIZE * 0.5 + 10
    local ttY = nodeScreenY - ttH * 0.5

    -- 边界修正
    if ttX + ttW > sw - 20 then ttX = targetNL.x - NODE_SIZE * 0.5 - ttW - 10 end
    if ttY < 20 then ttY = 20 end
    if ttY + ttH > sh - 20 then ttY = sh - 20 - ttH end

    -- 背景
    PixelUI.DrawPanel(ctx, ttX, ttY, ttW, ttH, {
        bg = {20, 24, 32, 240},
        borderColor = {100, 110, 120, 200},
        shadow = true,
        noiseAlpha = 8,
    })

    local tx = ttX + 10
    local ty = ttY + 14

    -- 名称
    nvgFontFace(ctx, "bold") nvgFontSize(ctx, 13)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local nameCol = (targetNode.type == "core") and COL_CORE_RING or COL_UNLOCKED
    nvgFillColor(ctx, nvgRGBA(nameCol[1], nameCol[2], nameCol[3], 255))
    nvgText(ctx, tx, ty, targetNode.name, nil)
    ty = ty + 18

    -- 类型标签
    nvgFontFace(ctx, "sans") nvgFontSize(ctx, 10)
    nvgFillColor(ctx, nvgRGBA(160, 170, 180, 200))
    local typeLabel = targetNode.type == "core" and "[核心解锁]" or "[普通]"
    nvgText(ctx, tx, ty, typeLabel, nil)
    ty = ty + 16

    -- 效果
    nvgFontSize(ctx, 11)
    nvgFillColor(ctx, nvgRGBA(200, 240, 200, 240))
    -- 多行效果
    for line in targetNode.effect:gmatch("[^\n]+") do
        nvgText(ctx, tx, ty, line, nil)
        ty = ty + 14
    end
    ty = ty + 6

    -- 消耗
    local status = SkillTree.GetNodeStatus(state, targetNode)
    if status ~= "unlocked" then
        nvgFontSize(ctx, 10)
        -- 技能点
        local hasPoints = state.skillPoints >= targetNode.cost
        nvgFillColor(ctx, nvgRGBA(hasPoints and 180 or 255, hasPoints and 220 or 80, hasPoints and 255 or 80, 220))
        nvgText(ctx, tx, ty, string.format("⭐ %d 技能点", targetNode.cost), nil)
        ty = ty + 13

        -- 材料
        local branchInfo = nil
        for _, b in ipairs(SkillTree.BRANCHES) do
            if b.id == targetNode.branch then branchInfo = b; break end
        end
        local matHave = state.materials[targetNode.branch] or 0
        local hasMat = matHave >= targetNode.materialCost
        nvgFillColor(ctx, nvgRGBA(hasMat and 180 or 255, hasMat and 220 or 80, hasMat and 255 or 80, 220))
        local matName = branchInfo and branchInfo.material or "材料"
        local matIcon = branchInfo and branchInfo.materialIcon or "📦"
        nvgText(ctx, tx, ty, string.format("%s %d %s", matIcon, targetNode.materialCost, matName), nil)
        ty = ty + 13

        -- 状态提示
        if status == "locked" then
            nvgFillColor(ctx, nvgRGBA(180, 100, 100, 200))
            nvgText(ctx, tx, ty, "🔒 需先解锁前置节点", nil)
        end
    else
        nvgFontSize(ctx, 11)
        nvgFillColor(ctx, nvgRGBA(COL_UNLOCKED[1], COL_UNLOCKED[2], COL_UNLOCKED[3], 220))
        nvgText(ctx, tx, ty, "✓ 已解锁", nil)
    end
end

-- ============================================================================
-- 点击检测
-- ============================================================================

--- 检测鼠标位于哪个节点上
---@param mx number 鼠标 X
---@param my number 鼠标 Y
---@param sw number 屏幕宽
---@param sh number 屏幕高
---@param state table 技能树状态
---@param scrollY number|nil 纵向滚动偏移（默认0）
---@return string|nil nodeId 命中的节点id，"__close" 表示关闭按钮，nil 表示未命中
function M.HitTest(mx, my, sw, sh, state, scrollY)
    scrollY = scrollY or 0
    local layout = M.CalcLayout(sw, sh, state)
    local pr = layout.panelRect

    -- 关闭按钮（左上角，36x36）— 不受滚动影响
    local closeX = pr.x + 8
    local closeY = pr.y + 6
    if mx >= closeX and mx <= closeX + 36 and my >= closeY and my <= closeY + 36 then
        return "__close"
    end

    -- 节点检测（圆形碰撞区域）— 需要加上滚动偏移
    local hitRadius = NODE_SIZE * 0.6
    for _, branch in ipairs(layout.branches) do
        for _, nl in ipairs(branch.nodes) do
            local dx = mx - nl.x
            local dy = (my + scrollY) - nl.y  -- 屏幕坐标转内容坐标
            if dx * dx + dy * dy <= hitRadius * hitRadius then
                return nl.node.id
            end
        end
    end

    return nil
end

--- 根据节点id查找节点定义
---@param nodeId string
---@return table|nil
function M.FindNode(nodeId)
    for _, nodes in pairs(SkillTree.ALL_NODES) do
        for _, node in ipairs(nodes) do
            if node.id == nodeId then return node end
        end
    end
    return nil
end

--- 计算技能树最大滚动范围
---@param sw number
---@param sh number
---@param state table
---@return number maxScroll
function M.GetMaxScroll(sw, sh, state)
    local layout = M.CalcLayout(sw, sh, state)
    local maxNodeY = 0
    for _, branch in ipairs(layout.branches) do
        for _, nl in ipairs(branch.nodes) do
            if nl.y > maxNodeY then maxNodeY = nl.y end
        end
    end
    local pr = layout.panelRect
    local bottomLimit = pr.y + pr.h - FOOTER_H - 20  -- 底部留出footer和间距
    return math.max(0, maxNodeY + 40 - bottomLimit)
end

return M
