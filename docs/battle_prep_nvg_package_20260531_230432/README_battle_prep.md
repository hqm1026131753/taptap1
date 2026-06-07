# 战前准备页面 NanoVG 交付说明

## 文件

- `battle_prep_page.lua`

## 绘制函数

```lua
DrawBattlePrep(vg, SW, SH, data)
```

布局锚点：整页以 `1470 × 1080` 为设计基准，根据 `SW / SH` 等比缩放并居中。页面包含顶部标题、左侧仓库、中央出售/购买与新手提示、右侧出战装备、出发和返回按钮。

## 点击检测

```lua
local hit = HitTestBattlePrep(mx, my, SW, SH)
```

返回值：

- `tab_sell`
- `tab_buy`
- `sell_drop_zone`
- `sell_all`
- `confirm_sell`
- `warehouse_01` 到 `warehouse_100`
- `slot_main_weapon`
- `slot_sub_weapon`
- `slot_armor`
- `slot_bag`
- `slot_consumable`
- `slot_key_item`
- `tip_1`
- `tip_2`
- `tip_3`
- `start`
- `back`

## data 参数

所有字段可选，不传也能绘制默认空仓库页面。

```lua
local data = {
    gold = 0,
    mode = "sell", -- "sell" 或 "buy"
    storageUsed = 0,
    storageCapacity = 100,
    storageValue = 0,
    totalSell = 0,
    weight = 0,
    maxWeight = 25,
    readiness = 5,
    isFirstRaid = true,
    loadout = {
        mainWeapon = "未装备",
        subWeapon = "未装备",
        armor = "未装备",
        bag = "未装备",
        consumable = "未装备",
        keyItem = "未装备",
    },
    cards = {
        { title = "搜刮撤离", body1 = "进入地牢搜刮宝藏", body2 = "成功撤离带回基地", body3 = "才算真正的收获！", tone = "green" },
        { title = "谨慎深入", body1 = "越深入，宝藏越多", body2 = "但危险也越大", body3 = "量力而行，及时撤退！", tone = "blue" },
        { title = "死亡惩罚", body1 = "战斗中死亡将失去", body2 = "全部携带物品", body3 = "小心为上，活着回来！", tone = "red" },
    }
}
```

## 接入示例

```lua
function Draw(vg, SW, SH)
    DrawBattlePrep(vg, SW, SH, BattlePrepData)
end

function OnMouseDown(mx, my, SW, SH)
    local hit = HitTestBattlePrep(mx, my, SW, SH)
    if hit == "start" then
        -- 进入地牢
    elseif hit == "back" then
        -- 返回菜单
    end
end
```

