# Boss 设计：装甲机猫

> 像素风 Boss，定位为地牢 10 层或 15 层的中期关卡。
> 视觉特征：黑猫头部 + 重型装甲 + 左手盾 + 右手炮 + 背部反应堆。

---

## 一、Boss 属性

| 属性 | 数值 |
|------|------|
| 名称 | 装甲机猫 |
| HP | 80（随层数调整） |
| 速度 | 0.8（慢速，重型） |
| 体型 | 2×2 格（比普通敌人大一圈） |

**走路姿势**：每步地面震动，机身左右倾斜，盾在前炮朝下。像移动的坦克。
**Walk Cycle**：Heavy step shakes ground, body tilts side to side, shield forward cannon low. Like a moving tank.
**跑步姿势**：机身压低，盾牌举前，炮口上抬，步伐加快，地面连续震动。像失控的火车。
**Run Cycle**：Body lowers, shield raised forward, cannon lifts up, rapid steps shake ground continuously. Like a runaway train.

## 二、技能设计

### 技能 1：盾牌冲锋 / Shield Charge

```
描述：举起盾牌朝玩家方向冲刺，命中造成伤害+眩晕
Desc: Charges toward the player, deals damage and stuns on hit
前摇：盾牌发光蓄力（0.5 秒），红色直线预警
冲锋伤害/Charge Dmg：12
眩晕/Stun：1 秒
冷却/Cool Down：8 秒
应对：看到预警线后横向躲避
```

### 技能 2：激光扫射 / Laser Sweep

```
描述：肩部机炮切换为激光模式，朝玩家方向持续扫射
Desc: Shoulder cannon switches to laser mode, sweeping toward the player
前摇：机炮展开成三管，蓄力 1 秒，发出高频充能声
伤害/Damage：每秒 15（持续接触）
射程/Range：贯穿全屏
宽度/Width：24px
持续时间/Duration：2 秒
冷却/Cool Down：8 秒
视觉表现：亮青色（#00f0ff）激光，带白色核心，地面有灼烧痕迹
Visual: Cyan laser (#00f0ff) with white core, burning marks on the ground
应对：激光会缓慢跟踪，不能直线跑，需要横向急转弯
```

### 技能 3：炮击 / Cannon Shot

```
描述：发射一枚高爆弹，落地爆炸
Desc: Fires a high-explosive shell that detonates on impact
前摇：炮口蓄力闪光（0.8 秒），地面出现红色圆形预警
伤害/Damage：20（中心）/ 10（边缘）
爆炸范围/Radius：2×2 格
冷却/Cool Down：5 秒
应对：爆炸范围大但前摇长，拉开距离即可
```

### 技能 4：狂暴模式 / Berserk Mode（HP < 50%）

```
描述：Boss 进入狂暴，所有技能冷却减半，移速+30%
Desc: All skill cooldowns halved, movement speed +30%
视觉：背部反应堆冒出黑烟
Visual：Black smoke vents from the backpack reactor
```

---

## 三、战斗流程

```
阶段一（100% ~ 50% HP）：
  循环使用：盾牌冲锋 → 激光扫射 → 炮击 → 普通攻击 → 炮击 → 盾牌冲锋
  节奏缓慢，给玩家适应时间

阶段二（< 50% HP）：狂暴
  所有技能冷却减半
  连续释放激光 → 炮击 → 盾击组合
  激光扫射频率翻倍
```

---

## 四、掉落

| 物品 | 数量 | 概率 |
|------|------|------|
| 钻石 💎 | 1~2 | 70% |
| 史诗武器（AUG/沙漠之鹰） | 1 | 50% |
| 重型防弹衣 | 1 | 40% |
| 肾上腺素 | 1~2 | 60% |
| Boss 专属掉落「机猫装甲片」 | 1 | 100% |

**机猫装甲片**：可在黑商处兑换 500 金币，或作为隐藏合成材料。
