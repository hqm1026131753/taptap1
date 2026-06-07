---
name: urhox-dev-module
description: "Generate runtime developer debug modules for UrhoX engine games (Lua 5.4 / Yoga Flexbox + NanoVG). Includes FPS monitor HUD, toggleable debug panel with tabs (player controls, economy editing, item spawning, world teleport, game info), and keyboard shortcuts. Use when the user wants a developer panel, debug console, dev tools, or runtime debugging interface for their UrhoX/Lua game. Also use when the user mentions needing FPS overlay, item spawner, god mode toggle, teleport, gold editor, or any debug/inspection features for an UrhoX-based game. MANDATORY TRIGGERS: developer module, debug panel, dev tools, 开发者模块, 调试面板, 开发者面板, dev panel, debug console, runtime dev tools, FPS monitor overlay, item spawner debug, god mode toggle, 物品刷取, 上帝模式, 调试工具, 开发者工具. DO NOT use for non-UrhoX engines (Unity, Unreal, Cocos Creator, Godot) or non-Lua languages."
---

# UrhoX Developer Module

为 UrhoX 引擎（Lua 5.4 / Yoga Flexbox + NanoVG）游戏生成运行时开发者调试模块。

## 适用场景

- 用户说「给我的游戏加个开发者面板」「做个调试模块」「加个 dev 面板」
- 用户做 UrhoX / Lua 引擎游戏，需要一个运行时调试工具
- 用户需要 FPS 监控、物品刷取、数值编辑、传送跳关等功能
- 引擎技术栈：Lua 5.4、UrhoX、Yoga Flexbox UI、NanoVG、Box2D

**不要**在以下场景使用：
- 目标引擎不是 UrhoX（如 Unity、Unreal、Cocos Creator、Godot 等）
- 用户只需要 FPS 监控（这是更简单的场景，单独做即可）
- 用户语言不是 Lua（如 JS/TS/C#）

## 核心思路

UrhoX 没有内置 ImGui 或类似即时模式调试 UI。但它的 Yoga Flexbox 声明式 UI 系统足够轻量，可以直接用它搭调试面板。

核心模式：

```
1. 监控 HUD        → 常驻浮层（FPS / 坐标 / HP）, Yoga 绝对定位
2. 调试面板        → F12 开关，Tabs 分区，内部用 Switch/Slider/Button
3. 钩子系统        → 游戏模块注册回调，DevModule 不直接引用游戏代码
```

## 引擎 UI API 参考

```lua
local UI = require("urhox-libs/UI")

UI.Init({ fonts = {...}, scale = UI.Scale.DEFAULT })

-- 声明式 UI 树
local panel = UI.Panel {
    width = "100%", height = "100%",
    flexDirection = "column", justifyContent = "center",
    alignItems = "center", gap = 12,
    backgroundColor = "#222222CC",
    borderRadius = 12,
    children = {
        UI.Label { text = "Title", fontSize = 18, color = "#FFFFFF" },
        UI.Button {
            text = "Click",
            variant = "primary",
            onClick = function(self) print("clicked") end
        },
        UI.Slider {
            value = 50, min = 0, max = 100,
            onChange = function(self, v) print(v) end
        },
        UI.Switch {
            value = false,
            onChange = function(self, v) print(v) end
        },
        UI.Input {
            value = "text",
            placeholder = "input here",
            onChange = function(self, v) end
        },
    }
}

-- 事后更新
label:SetText("new text")
panel:SetVisible(true)
panel:ClearChildren()
```

## 输出结构

生成以下文件（放在游戏的 `scripts/` 目录下）：

```
scripts/
├── DevModule.lua        ← 核心开发者模块
└── (main.lua 修改)      ← 添加 require、Init、Update 调用
```

## 执行流程

### 第一步：了解游戏

在写代码前，必须先弄清楚：

1. **游戏模块结构**——有哪些 Lua 模块（Player、World、Inventory、Economy 等），它们的成员变量和方法名
2. **快捷键系统**——引擎如何注册键盘事件
3. **游戏专属功能需求**——用户要哪些调试功能（物品刷取？传送？经济编辑？）
4. **UI 风格偏好**——面板颜色、大小、位置

询问用户这些问题，如果用户说「跟上次一样」或「按通用来」，用模板里的默认配置。

### 第二步：写出 DevModule.lua

核心结构必须包含三个层次：

#### 层次 1：监控 HUD

左上角浮动显示，始终可见，不阻挡点击穿透：

```
FPS: 60                  ← 颜色随帧率变化（<20 红, <40 黄, >=40 绿）
Pos: 123.4, 567.8       ← 玩家坐标
HP: 75/100  |  💰: 2500 ← 状态摘要
⚡ GOD MODE              ← 仅上帝模式开启时显示
```

实现要点：
- 使用 `position = "absolute", top = 6, left = 8` 定位
- 设置 `pointerEvents = false` 不阻挡游戏操作
- FPS 自算：每帧记数，每 0.5 秒刷新

#### 层次 2：调试面板

F12 切换显示，Tabs 分区，浮动居中：

```
┌──────────────────────────────────────┐
│  🔧 开发者面板                   ✕  │  ← 标题栏
├──┬──┬──┬──┬──┤                       │
│玩家│经济│物品│世界│信息│               │  ← Tab 栏
├──┴──┴──┴──┴──┤                       │
│                                        │
│  (当前 Tab 内容区)                     │
│                                        │
├──────────────────────────────────────┤
│        DEV MODULE v1.0  |  F12 关闭     │  ← 底栏
└──────────────────────────────────────┘
```

Tab 切换通过 `panel:ClearChildren()` 重建内容实现。

每个 Tab 包含的功能：

| Tab | 功能 |
|-----|------|
| 玩家 | HP/速度显示、上帝模式 Switch、移速倍率 Slider、回血/补弹按钮、清敌/撤离按钮 |
| 经济 | 余额显示、加钱 Input+快捷按钮(+100/+1k/+5k/+99999)、收购/售价倍率 Slider |
| 物品 | 战利品/武器/装备分类的快捷刷取 Button、自定义 ID Input |
| 世界 | 房间/种子/耗时、楼层传送 Input+快捷(1/5/10/15/20F)、生成敌人、重新开始 |
| 信息 | 游戏状态、背包统计、快捷键提示、版本号 |

Tab 内容都用引擎内置控件实现，不需要外部依赖。

#### 层次 3：快捷键

全局快捷键，不依赖面板可见性：

| 按键 | 功能 |
|------|------|
| F12 | 开关调试面板 |
| F10 | 切换上帝模式 |

引擎提供注册式回调时用 `inputSystem:RegisterKeyCallback()`，否则在 Update 中轮询。

### 第三步：钩子系统（Hook Registry）

这是设计关键——**游戏模块不引用 DevModule**。数据传递通过钩子表单向：

```lua
-- DevModule.hooks 是一个回调表
DevModule.hooks = {}

-- 游戏模块在初始化时注册数据回调
DevModule.hooks.getPlayerHP = function()
    return player.hp, player.maxHp
end
DevModule.hooks.addGold = function(amount)
    economy.gold = economy.gold + amount
end

-- DevModule 在 Update 中调用钩子，用 pcall 包裹防止崩溃
```

必须提供完整的钩子清单，让用户一眼知道可以注册什么。同时提供一组 `HookXxx()` 便捷函数做一键注册。

### 第四步：提供集成指南

告诉用户在 `main.lua` 中怎么改：

```lua
local DevModule = require("scripts.DevModule")

function Start()
    -- ... 游戏初始化 ...
    DevModule.Init(nil, inputSystem)
    DevModule.HookPlayer(Player)
    DevModule.HookEconomy(Economy)
    DevModule.HookWorld(World)
    DevModule.HookInventory(Inventory)
    DevModule.SealHooks()
end

function Update(timeStep)
    -- ... 游戏逻辑 ...
    DevModule.Update(timeStep)
end
```

## 参考模板

完整代码模板在 `templates/DevModule.lua`。使用时：

1. 复制 `templates/DevModule.lua` 到目标项目的 `scripts/DevModule.lua`
2. 根据该游戏的模块命名，调整 `HookXxx()` 函数或手写钩子
3. 在 `main.lua` 中添加 require + Init + Update 调用

### 模板需要注意的适配点

1. **输入系统**：模板假设引擎通过 `RegisterKeyCallback(fn)` 注册键盘事件。如果引擎不用这个模式，在 `main.lua` 的 Update 中自己检测按键并调用 `DevModule._onKey(key)`
2. **钩子命名**：模板的 `HookPlayer` 等函数假设模块成员名为 `hp/maxHp/x/y/speed` 等。如果游戏模块命名不同，手写钩子而不是用 `HookXxx`
3. **FPS 计算**：模板自算 FPS，不依赖引擎 API。但如果有 `engine:fps()`，优先用它

## 质量要求

- 所有钩子调用必须用 `pcall` 包裹
- 面板隐藏时只做 HUD 更新（FPS + 坐标 + HP），不做面板数据更新
- 控件文本用 `SetText()` 方法更新，不重建整个面板
- 所有数值编辑（金币、倍率、传送等）必须有即时反馈
- 代码注释比例不低于 15%，方便用户修改
