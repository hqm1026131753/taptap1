# Boss 设计：军帽领主

> 像素风最终 Boss，地牢 20 层关底。
> 视觉特征：黑猫 + 军帽 + 红色围巾 + 右手枪 + 左手刀。

---

## 一、Boss 属性

| 属性 | 数值 |
|------|------|
| 名称 | 军帽领主 / Captain Claw |
| HP | 120（最终 Boss） |
| 速度 | 1.2（快速，敏捷型） |
| 体型 | 1.5×1.5 格 |

**走路姿势**：军步，步伐稳健，围巾随动作飘动。**Walk Cycle**：Military stride, steady steps, scarf flows with movement.

---

## 二、技能设计

### 技能 1：精准射击 / Precision Shot

```
描述：抬起手枪瞄准，射出一发高伤害子弹
Desc: Aims pistol and fires a high-damage shot
前摇：举枪瞄准（0.6 秒），枪口出现红色十字准星锁定玩家
伤害/Damage：28
特效：穿透敌人，可打一排
冷却/Cool Down：5 秒
应对：看到准星锁定后横向闪避，不要直线走
```

### 技能 2：猫爪突刺 / Shadow Pounce

```
描述：利用猫的敏捷，快速向玩家方向突进，接一刀斩击
Desc: Uses feline agility to dash forward, followed by a swift scimitar slash
前摇：身体下压低伏（0.3 秒），地面出现红色直线突进预警
突进伤害/Dash Dmg：12
斩击伤害/Slash Dmg：20
冷却/Cool Down：6 秒
应对：突进和斩击之间有短暂间隙，吃到突进后立刻横向翻滚躲第二刀
```

### 技能 3：战术烟幕 / Tactical Smoke

```
描述：扔出红色烟雾弹，短暂隐身并重置位置
Desc: Throws a red smoke bomb, turns invisible briefly and repositions
效果：Boss 消失在烟雾中，1.5 秒后出现在玩家侧后方
隐身期间无法被攻击
冷却/Cool Down：10 秒
触发条件：HP < 60% 时解锁
应对：看到红色烟雾扩散时立即移动位置，不要在原地等
```

### 技能 4：军帽威严 / Commanding Presence

```
描述：军帽发光，释放一股威严气场，震退周围敌人并施加标记
Desc: Hat glows, releases a commanding aura that knocks back enemies and marks the player
前摇：军帽金徽章闪烁（0.5 秒），全身发出金色光环
效果：击退周围所有单位 150px，被击中的玩家被「标记」，5 秒内下一次精准射击必中
伤害/Damage：8
范围/Range：全屏
冷却/Cool Down：10 秒
应对：被标记后立刻找掩体或准备横向闪避接下一发精准射击
```

### 技能 5：四月斩 / Crescent Quadra

```
描述：挥动弯刀，向前方连续发出四道远程半月形剑气
Desc: Slashes the scimitar, firing four ranged crescent-shaped blades forward
前摇：弯刀后摆蓄力（0.5 秒），刀身发光
伤害/Damage：每道 12
范围/Range：全屏贯穿，每道间隔 0.2 秒
弹道呈扇形扩散——第一道直线，第四道偏移最大
冷却/Cool Down：9 秒
应对：站远一点空隙更大，越远越好躲
```

### 技能 6：召唤近卫 / Call Guards

```
描述：军帽领主吹响口哨，召唤 2 名持盾近卫兵入场
Desc: Whistles sharply, summoning 2 shielded guards
近卫兵属性：HP 12，移速 0.6，持盾（正面减伤 50%），不会攻击，只挡路
冷却/Cool Down：12 秒
触发条件：HP < 60% 时解锁
应对：近卫兵只挡正面，绕到背后打掉即可
```

### 技能 7：九命猫 / Nine Lives

```
描述：军帽猫的真正底牌——第一次死亡时不会倒下
Desc: Captain Claw's true trump card — refuses to fall on first death
效果：HP 归零时触发，恢复 30% HP 并进入狂怒状态
狂怒：移速+40%，攻击频率翻倍，持续 8 秒
如果 8 秒内没被击杀，Boss 自愈到 50% HP 继续战斗
全局限定 1 次
冷却/Cool Down：Boss 整局触发 1 次
应对：准备好最后一波爆发输出，不要让他拖到自愈
```

---

## 三、战斗流程

```
阶段一（100% ~ 60% HP）：
  循环：精准射击 → 猫爪突刺 → 精准射击 → 四月斩
  节奏中等，Boss 以单体攻击为主

阶段二（60% ~ 0% HP）：
  解锁：军帽威严 + 召唤近卫
  循环：军帽威严 → 召唤近卫 → 精准射击（必中版）→ 四月斩 → 猫爪突刺
  场面开始混乱——近卫挡路，标记逼迫走位

九命猫触发（第一次击杀时）：
  保留 20% HP，进入狂怒
  所有技能冷却减半
  四月斩变为连续释放
  8 秒后若存活，自愈到 30% HP
```

---

## 四、掉落

| 物品 | 数量 | 概率 |
|------|------|------|
| 遗物圣器 🔮 | 1 | 100% |
| 传说武器（AWM/R93/PKM/M250） | 1 | 100% |
| 顶级防具（复合陶瓷甲/军用全罩盔） | 1 | 100% |
| 钻石 💎 | 2~4 | 80% |
| 肾上腺素 | 2 | 100% |
| Boss 专属掉落「军帽徽章」 | 1 | 100% |

**军帽徽章**：可在黑商处兑换 2000 金币。
