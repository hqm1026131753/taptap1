# 动态光源 — NanoVG 径向渐变方案

## 原理

并非真正的 3D 光照计算。做法是：

1. 先画完场景（地板、墙壁、家具、角色）
2. 在场景上方覆盖一层全屏深色遮罩
3. 在每个光源位置用径向渐变挖出亮区（中心透明 → 边缘遮罩色）
4. 结果：光源附近正常亮度，远处被压暗

核心：不需要改地板/墙壁的绘制逻辑，在渲染管线的最后一步叠加光照层。

---

## 基础实现

```lua
-- 第 1 步：画完场景
DrawFloor(nvg, cells, rooms, ...)
DrawWalls(nvg, cells, ...)
DrawObjects(nvg, ...)
DrawEntities(nvg, ...)

-- 第 2 步：覆盖全屏黑暗
nvg.BeginPath()
nvg.Rect(0, 0, SCREEN_W, SCREEN_H)
nvg.FillColor(nvg.RGBA(5, 5, 10, 200))  -- 深色遮罩
nvg.Fill()

-- 第 3 步：在每个光源位置挖出亮区
for _, light in ipairs(lights) do
    local px, py = light.x, light.y
    local r = light.radius

    nvg.BeginPath()
    nvg.Circle(px, py, r)
    nvg.RadialGradient(px, py, 0, r,
        nvg.RGBA(0, 0, 0, 0),                              -- 中心：全透明（正常亮度）
        nvg.RGBA(5, 5, 10, 200)                             -- 边缘：恢复到遮罩色
    )
    nvg.Fill()
end
```

---

## 光源数据结构

```lua
Light = {
    x        = 400,      -- 屏幕坐标
    y        = 250,
    radius   = 120,      -- 影响半径（像素）
    color    = { 255, 200, 150 },  -- RGB 光色，nil 时默认暖白
    innerGlow = false,    -- 是否加内圈光晕

    -- 动态光源专用
    duration = nil,       -- nil = 常亮，数字 = 持续秒数
    elapsed  = 0,         -- 已持续秒数
    flicker  = false,     -- 是否闪烁
}
```

---

## 环境光（常亮）

火把、灯笼、篝火——常亮光源，一直存在于光源列表中。

```lua
-- 单个径向渐变
nvg.BeginPath()
nvg.Circle(px, py, r)
nvg.RadialGradient(px, py, 0, r,
    nvg.RGBA(0, 0, 0, 0),
    nvg.RGBA(5, 5, 10, 200)
)
nvg.Fill()

-- 可选内圈暖色光晕（让光源位置有颜色感）
nvg.BeginPath()
nvg.Circle(px, py, r * 0.3)
nvg.RadialGradient(px, py, 0, r * 0.3,
    nvg.RGBA(255, 200, 150, 60),
    nvg.RGBA(0, 0, 0, 0)
)
nvg.Fill()
```

### 闪烁效果

每帧对 radius 做正弦微调：

```lua
-- 在 Update 中
light.phase = (light.phase or 0) + timeStep * 4
local flickerOffset = math.sin(light.phase) * 8 + math.sin(light.phase * 2.3) * 4

-- 在 Draw 中
local r = baseRadius + flickerOffset
```

---

## 动态光源（瞬态）

枪口火焰、爆炸、手电筒——持续一段时间后消失。

### 枪口火焰（Muzzle Flash）

```lua
-- 开枪时创建：
table.insert(lights, {
    x = gunX, y = gunY,
    radius = 40,
    color = { 255, 230, 200 },
    duration = 0.12,   -- 持续 0.12 秒
    elapsed = 0,
})

-- 绘制时：
local progress = light.elapsed / light.duration
local alpha = (1 - progress) * (1 - progress)  -- 二次淡出

nvg.BeginPath()
nvg.Circle(light.x, light.y, light.radius)
nvg.RadialGradient(
    light.x, light.y, 0, light.radius,
    nvg.RGBA(0, 0, 0, 0),
    nvg.RGBA(5, 5, 10, math.floor(200 * alpha))
)
nvg.Fill()
```

### 爆炸

```lua
-- 爆炸时创建：
table.insert(lights, {
    x = boomX, y = boomY,
    radius = 150,
    color = { 255, 150, 50 },
    duration = 0.6,
    elapsed = 0,
    innerGlow = true,
})

-- 半径随时间膨胀 + 淡出
local expand = 0.5 + (light.elapsed / light.duration) * 0.5  -- 从 0.5 倍到 1 倍
local r = light.radius * expand
```

---

## 墙壁裁剪（防止光穿墙）

纯粹用径向渐变的问题：光源在房间 A，光晕会照到隔壁房间 B 的地板上。

用 BSP 房间数据约束光照半径：

```lua
function GetRoomAt(x, y)
    for _, room in ipairs(rooms) do
        if x >= room.x * TILE and x < (room.x + room.w) * TILE
        and y >= room.y * TILE and y < (room.y + room.h) * TILE then
            return room
        end
    end
    return nil
end

function RenderLight(nvg, light)
    -- 查找光源所在房间
    local room = GetRoomAt(light.x, light.y)
    if not room then return end

    -- 计算到最近墙壁的距离
    local rx, ry = room.x * TILE, room.y * TILE
    local rw, rh = room.w * TILE, room.h * TILE
    local dx = math.min(light.x - rx, rx + rw - light.x)
    local dy = math.min(light.y - ry, ry + rh - light.y)
    local wallDist = math.min(dx, dy)

    -- 光照半径不能超过到墙的距离留 1 tile 缓冲
    local radius = math.min(light.radius, wallDist - TILE * 0.5)

    -- 剪裁后如果半径太小就不画
    if radius <= 0 then return end

    nvg.BeginPath()
    nvg.Circle(light.x, light.y, radius)
    nvg.RadialGradient(light.x, light.y, 0, radius,
        nvg.RGBA(0, 0, 0, 0),
        nvg.RGBA(5, 5, 10, 200)
    )
    nvg.Fill()
end
```

裁剪后光源不会穿墙。但门洞和走廊入口是缺口，光照可以从门洞漏到走廊再漏到隔壁房间——如果你需要这个效果，用方案二。

---

## 像素风格的注意事项

### 禁用平滑渐变

NanoVG 的 RadialGradient 默认是平滑的，在像素画风下太软。用阶梯式多层实心圆替代：

```lua
-- 粗糙像素光晕
local steps   = { 0.0, 0.3, 0.6, 0.8, 1.0 }
local alphas  = { 0, 50, 110, 160, 200 }

nvg.Save()
nvg.ShapeAntiAlias(false)  -- 如果引擎暴露此 API

for i = 1, 5 do
    local r = radius * steps[i]
    nvg.BeginPath()
    nvg.Circle(cx, cy, r)
    nvg.FillColor(nvg.RGBA(0, 0, 0, alphas[i]))
    nvg.Fill()
end

nvg.Restore()
```

### 光源位置对齐像素

光源坐标取整，避免半像素偏移：

```lua
light.x = math.floor(light.x)
light.y = math.floor(light.y)
```

---

## 与 BattlefieldRenderer 的集成

在绘制管线的最后一步：

```lua
-- BattlefieldRenderer.DrawDungeon() 末尾
-- 第 4 遍：光源叠加
if lights and #lights > 0 then
    nvg.BeginPath()
    nvg.Rect(camX * tileSize, camY * tileSize, SCREEN_W, SCREEN_H)
    nvg.FillColor(nvg.RGBA(5, 5, 10, 200))
    nvg.Fill()

    for _, l in ipairs(lights) do
        local sx = (l.gridX - camX) * tileSize + tileSize / 2
        local sy = (l.gridY - camY) * tileSize + tileSize / 2
        RenderLight(nvg, { x = sx, y = sy, radius = l.radius * tileSize })
    end
end
```

---

## 一句话给 AI / 引擎

> "后处理方案。先画完整个场景，然后在场景上方覆盖全屏深色半透明矩形（RGBA 5-5-10-200），在每个光源位置叠加 RadialGradient（中心全透明 → 边缘回到遮罩色）。环境光常亮绘制，枪口火焰 0.12 秒二次淡出，爆炸 0.6 秒半径膨胀淡出。用 BSP 房间边界裁剪光照半径防止穿墙。像素风格用阶梯式多层圆替代平滑径向渐变。"
