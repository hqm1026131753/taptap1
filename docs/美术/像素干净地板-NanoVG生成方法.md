# 像素地板 — 颜色/纹理变化的干净实现

不需要裂缝、坑洞、血迹，只需要每格瓷砖之间有微妙的颜色差异和纹理变化。这是比战损地板更简单的场景——去掉装饰层，只保留基底 + 变化。

## 核心逻辑

```lua
local TILE = 16
local GRID_COLS = math.ceil(SCREEN_W / TILE) + 2
local GRID_ROWS = math.ceil(SCREEN_H / TILE) + 2

for gy = 0, GRID_ROWS do
    for gx = 0, GRID_COLS do
        seedFromPos(gx, gy, 0)

        local sx = gx * TILE
        local sy = gy * TILE

        -- === 基底色 ===
        -- 图中地板的整体色调是冷灰，微偏蓝
        -- 每格在基准色上做小幅度偏移
        local baseR, baseG, baseB = 130, 140, 150

        -- 随机偏移 ±8，保持变化但不跳脱
        local variation = -8 + rand() * 16
        local r = baseR + math.floor(variation)
        local g = baseG + math.floor(variation * 0.8)
        local b = baseB + math.floor(variation * 0.6)

        -- 每格有 15% 概率整体偏移色相（偏暖或偏冷）
        if rand() < 0.15 then
            r = r + math.floor(rand() * 6)
            b = b - math.floor(rand() * 4)
        end

        nvg.BeginPath()
        nvg.Rect(sx, sy, TILE, TILE)
        nvg.FillColor(nvg.RGBA(
            math.max(0, math.min(255, r)),
            math.max(0, math.min(255, g)),
            math.max(0, math.min(255, b)),
            255
        ))
        nvg.Fill()

        -- === （可选）轻微噪声纹理 ===
        -- 在每格内画 2~4 个半透小点，模拟石材的颗粒感
        if rand() < 0.4 then
            local dots = 1 + math.floor(rand() * 3)
            for i = 1, dots do
                local dx = sx + rand() * TILE
                local dy = sy + rand() * TILE
                local dr = 1 + rand() * 2
                nvg.BeginPath()
                nvg.Circle(dx, dy, dr)
                nvg.FillColor(nvg.RGBA(
                    math.floor(r * 0.6),
                    math.floor(g * 0.6),
                    math.floor(b * 0.6),
                    60
                ))
                nvg.Fill()
            end
        end

        -- === （可选）格线 ===
        -- 图中有细格线，让 tile 边界清晰
        -- 但如果你用 Rect 绘制，相邻 tile 天然有 1px 缝隙
        -- 也可以画半透明边框
        nvg.BeginPath()
        nvg.Rect(sx, sy, TILE, TILE)
        nvg.StrokeColor(nvg.RGBA(100, 110, 120, 40))
        nvg.StrokeWidth(0.5)
        nvg.Stroke()
    end
end
```

## 只有两层

和战损地板对比：

| 战损地板 | 干净地板 |
|---------|---------|
| 基底 tile（色差随机） | 基底 tile（色差随机） |
| 磨损叠加（亮/暗半透层） | — |
| 裂缝（链式传播） | — |
| 坑洞（不规则多边形） | — |
| — | 可选：噪声颗粒点 |
| — | 可选：格线边框 |

## 墙面砖块的同理

图中的深色砖墙也是同一个逻辑——每块砖的色相/亮度在小范围内随机，拼成一面墙。区别是砖块是矩形网格但可能有错缝（每行偏移半个砖宽）。

```lua
local BRICK_W, BRICK_H = 24, 12

for row = 0, rowCount do
    local offsetX = (row % 2 == 0) and 0 or BRICK_W / 2
    for col = 0, colCount do
        seedFromPos(col, row, 1)
        local bx = col * BRICK_W + offsetX
        local by = row * BRICK_H
        local bv = -6 + rand() * 12  -- 亮度变化

        nvg.BeginPath()
        nvg.Rect(bx, by, BRICK_W, BRICK_H)
        nvg.FillColor(nvg.RGBA(
            60 + bv, 55 + bv, 65 + bv, 255
        ))
        nvg.Fill()

        -- 砖缝（深色细线）
        nvg.BeginPath()
        nvg.Rect(bx, by, BRICK_W, BRICK_H)
        nvg.StrokeColor(nvg.RGBA(25, 22, 30, 180))
        nvg.StrokeWidth(1)
        nvg.Stroke()
    end
end
```

## 一句话给 AI / 引擎

> "生成 N×M 的 tile grid，每格 16×16，基底色冷灰（130-140-150），每格随机偏移 ±8，15% 概率做色相偏转。不需要破损装饰。可选在每格内加 2~4 个半透明噪点增强材质感。砖墙同理，24×12 的错缝砖网格，亮度偏移 ±6。"
