# 像素战损地板 — NanoVG 矢量生成方法

## 技术背景

引擎：UrhoX  
渲染：NanoVG（矢量绘图 API）  
目标：用矢量绘制模拟像素风格的地板磨损/破损效果

**关键认知**：NanoVG 画像素感场景，核心是**禁用平滑**和**约束着色**。所有坐标取整像素，避免抗锯齿，限制调色板。

---

## 图例参考

参考图是一张俯视角像素地牢/仓库场景的地板，三层结构清晰：

```
第 1 层：基底 tile grid
  规则网格，浅灰蓝色调，每格有轻微色差

第 2 层：磨损叠加
  某些 tiles 更亮（踩踏磨损）
  某些 tiles 更暗（污渍/积水）

第 3 层：破损装饰
  裂缝 — 呈锯齿线段延伸，跨越多格
  坑洞 — 不规则深色区域
  大坑 — 画面左侧一整片缺损
```

---

## 三层生成方法

### 第 1 层：基底 tile grid

每格 16×16 像素，灰蓝色调做微随机偏移：

```lua
local TILE = 16

for gy = startRow, endRow do
    for gx = startCol, endCol do
        -- 基于格子坐标播种，保证同一格每次生成一致
        seedFromPos(gx, gy, 0)

        -- 基底亮度随机偏移 0.85~1.0
        local b = 0.85 + rand() * 0.15
        local r = math.floor(100 * b)
        local g = math.floor(115 * b)
        local bl = math.floor(135 * b)

        nvg.BeginPath()
        nvg.Rect(sx, sy, TILE, TILE)
        nvg.FillColor(nvg.RGBA(r, g, bl, 255))
        nvg.Fill()
    end
end
```

### 第 2 层：磨损/污渍

每格 30% 概率叠加半透明层，产生区域性的亮度变化：

```lua
seedFromPos(gx, gy, 1)
local w = rand()

if w > 0.7 then
    -- 亮色磨损（踩踏、摩擦）
    nvg.BeginPath()
    nvg.Rect(sx, sy, TILE, TILE)
    nvg.FillColor(nvg.RGBA(180, 200, 220, 30))
    nvg.Fill()
elseif w < 0.2 then
    -- 深色污渍（油渍、泥泞）
    nvg.BeginPath()
    nvg.Rect(sx, sy, TILE, TILE)
    nvg.FillColor(nvg.RGBA(30, 35, 40, 40))
    nvg.Fill()
end
```

### 第 3 层：裂缝（链式传播）

裂缝不能逐格独立随机——没有连续性的一堆散点不是裂缝。用链式传播生成跨 tile 的连续路径：

```lua
-- 生成阶段（预处理）
local cracks = {}

for gy = startRow, endRow do
    for gx = startCol, endCol do
        seedFromPos(gx, gy, 7)

        -- 2% 概率在此格启动一条裂缝
        if rand() < 0.02 then
            local x = gx * TILE + TILE / 2
            local y = gy * TILE + TILE / 2
            local angle = rand() * math.pi * 2
            local segments = 3 + math.floor(rand() * 5)

            for i = 1, segments do
                local len = TILE * (0.3 + rand() * 1.2)
                local nx = x + math.cos(angle) * len
                local ny = y + math.sin(angle) * len
                table.insert(cracks, { x1 = x, y1 = y, x2 = nx, y2 = ny })

                x, y = nx, ny
                angle = angle + randRange(-0.6, 0.6)

                -- 裂缝不超过起始格 3 格范围
                if math.abs(x - gx * TILE) > TILE * 3 then break end
            end
        end
    end
end

-- 绘制阶段
for _, c in ipairs(cracks) do
    nvg.BeginPath()
    nvg.MoveTo(c.x1, c.y1)
    nvg.LineTo(c.x2, c.y2)
    nvg.StrokeColor(nvg.RGBA(25, 25, 30, 200))
    nvg.StrokeWidth(1.5)
    nvg.Stroke()
end
```

### 第 3 层扩展：坑洞（不规则多边形）

坑洞覆盖多个 tile，边缘有锯齿感：

```lua
seedFromPos(gx, gy, 8)

-- 0.5% 概率在此格生成一个坑洞
if rand() < 0.005 then
    local cx = gx * TILE + rand() * TILE
    local cy = gy * TILE + rand() * TILE
    local radius = TILE * (1.5 + rand() * 3)

    nvg.BeginPath()
    local points = 6 + math.floor(rand() * 6)
    for i = 0, points do
        local a = (i / points) * math.pi * 2
        local r = radius * (0.7 + rand() * 0.3)
        local px = cx + math.cos(a) * r
        local py = cy + math.sin(a) * r
        if i == 0 then
            nvg.MoveTo(px, py)
        else
            nvg.LineTo(px, py)
        end
    end
    nvg.ClosePath()
    nvg.FillColor(nvg.RGBA(15, 15, 20, 235))
    nvg.Fill()
end
```

---

## 完整的三遍渲染管线

```
第 1 遍：基底 tile grid
  灰蓝色调，亮度微随机

第 2 遍：磨损叠加
  亮色层 + 暗色层，每格独立判断

第 3 遍：裂缝 + 坑洞
  裂缝用链式传播生成路径
  坑洞用不规则多边形
```

与场景中其他元素（家具、蜡烛、角色）分开绘制，地板层只负责地面。

---

## 与 AI / 引擎沟通的精确指令

如果要把这个需求给另一个 AI 或引擎开发者，不要只说"做个像素战损地板"，用这个模板：

> "生成一个 N×M 的 tile grid，每个 tile 16×16 像素：
> 1. 基底色在灰蓝色调（RGB 100-115-135）范围内每格随机偏移 ±15%
> 2. 每格独立判断是否叠加磨损层：
>    - 30% 概率加亮色磨损层（RGBA 180-200-220, alpha 30）
>    - 20% 概率加深色污渍层（RGBA 30-35-40, alpha 40）
> 3. 跨 tile 的裂缝路径用链式传播生成：
>    - 起点概率 2%
>    - 每段长度 0.3~1.2 个 tile
>    - 方向随机偏转 ±0.6 弧度
>    - 3~5 段后终止
> 4. 坑洞用不规则多边形，覆盖 2~6 个 tile 范围
> 5. 所有坐标取整像素，不启用抗锯齿"

---

## 和 BattlefieldRenderer 的关系

当前的 `scripts/BattlefieldRenderer.lua` 已经实现了类似的框架：
- 基于坐标种子的伪随机系统（已就绪）
- 多遍渲染管线（已就绪）
- 三层地板需要改 `DrawFloor` 函数（未实现）
- 裂缝链式传播需要新加函数（未实现）

改造路径：保留 seed 系统和管线结构，把 `DrawFloor` 替换为上述三层逻辑。
