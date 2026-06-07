# BOSS 2 — 铁甲猫战锤（Armored Cat Hammer）

## 基本信息

| 属性 | 值 |
|------|-----|
| 名称 | 铁甲猫战锤 |
| 英文 | Armored Cat Hammer |
| 主题 | 重甲 · 巨锤 · 震地 |
| 视角 | 斜 45 度等距俯视 |
| 体型 | 矮壮猫形，全身板甲 |
| 特征 | 暗灰分段式铠甲、背甲方形背包、金属面罩遮住口鼻、黄色猫眼、手持一把和他身体差不多大的巨型木柄战锤 |

---

## 外观描述

和铁甲猫骑士同属一个系列的重甲单位。全身覆盖暗灰色分段式板甲，背部有一个方正的外挂背包。面部被金属面罩保护，只露出一双黄色猫眼。双手握持一柄巨大的木柄战锤，锤头比他的脑袋还大。整体轮廓比盾牌版更方正，重心更低，像一座会移动的攻城器械。

---

## 动作列表

### 0. 待机 Idle

He stands motionless, gripping his mallet with both hands, his yellow eyes fixed on the player, the massive hammer head resting on the ground.

他双手握锤静立，黄色眼睛死死盯着玩家，巨大的锤头垂在地上。

---

### 1. 巨锤砸击 Hammer Slam

He raises his massive mallet overhead and brings it straight down, splitting the ground in a line toward the player.

他高举巨槌过头顶，直直砸下，地面朝玩家方向裂开一道裂缝。

> 直线攻击技能。BOSS 蓄力约 0.6 秒后将锤砸下，地面裂开一道向前延伸的裂缝。裂缝范围内的玩家受到伤害并被短暂击退。裂缝宽度约 1 格，长度约 4-5 格。横向走位可躲避。

---

### 2. 旋风扫击 Spin Sweep

He grips the mallet with both hands and spins his entire body in a full circle, sweeping everything around him.

他双手握锤原地旋转一圈，横扫周围所有目标。

> 近战范围技能。BOSS 原地旋转一周，锤头划出一个大圆，击飞范围内所有目标。范围约 2 格半径。前摇较短（约 0.3 秒抬手动作），适合反制贴身的玩家。这招是 BOSS 防止玩家近身输出的主要手段。

---

### 3. 震地猛击 Seismic Leap

He jumps and drives his mallet into the ground at the landing point, sending a shockwave in all directions.

他跃起将锤砸向落点，朝四面八方扩散震波。

> 范围压制技能。BOSS 跳起约 1 秒，落地前地面出现圆形红色预警圈。落地后以落点为中心向外扩散圆形震波，震波覆盖约 3 格半径。可被跳跃躲避。BOSS 落地后有 0.8 秒硬直（拔锤动作），是输出窗口。

---

### 4. 拖锤冲锋 Grinding Charge

He drags his mallet behind him as he charges forward, leaving a trench of sparks and torn stone.

他将锤拖在身后向前冲锋，地面留下一道火花和碎石沟壑。

> 突进技能。BOSS 将锤拖在身侧向前冲刺，锤头在地面摩擦出一路火花和碎石。冲锋路径上的玩家受到伤害和被拉扯（向 BOSS 方向吸近一小段）。冲锋停止后 BOSS 接一记上撩挥锤作为收招，上撩范围较大但前摇明显，可以翻滚躲避。

---

### 5. 狂乱连击 Berserker Flurry

He roars and begins swinging his mallet in rapid, uncontrolled arcs, each hit slower but devastating.

他咆哮着开始快速乱挥大锤，每一击虽慢但极具毁灭性。

> 阶段技（Phase 2 解锁）。BOSS 半血以下触发，咆哮后进入狂乱状态，持续约 4 秒。期间连续挥锤 3-4 次，每次攻击方向随机（左右交替），单发伤害提升 50%。狂乱期间 BOSS 移动速度略微降低但不可被打断。

---

## 阶段变化（Phase 2）

半血以下触发：

- 解锁第 5 技能「狂乱连击」
- 震地猛击的震波范围扩大（3 格 → 4 格）
- 拖锤冲锋速度提升，收招上撩范围扩大
- 盔甲出现裂缝，部分碎片脱落，露出底下少量血迹
- 待机动画变化：呼吸加重，身体微微颤抖（即将暴走的前兆）

---

## 掉落物

| 物品 | 概率 | 类型 |
|------|------|------|
| 巨锤头碎片 | 30% | 素材（可用于锻造） |
| 猫战锤（武器） | 15% | 武器（慢速高伤，击退特效） |
| 厚重板甲片 | 25% | 素材（可用于防具强化） |
| 破损面罩 | 5% | 收藏品/装饰 |

---

## 对应生图 prompt

```yaml
工具: generate_image
prompt: "pixel art soul knight style boss, top-down isometric view,
         heavily armored cat, dark grey segmented plate armor,
         square backpack on back, metal face grill covering snout,
         glowing yellow eyes, both hands holding a giant wooden mallet,
         hammer head larger than his own head, stout powerful stance,
         detailed pixel shading, game boss fight,
         128x128 transparent png, dark fantasy pixel art style"
name: "boss_cat_hammer"
target_size: "128x128"
transparent: true
```
