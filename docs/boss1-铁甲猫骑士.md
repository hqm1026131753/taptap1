# BOSS 1 — 铁甲猫骑士（Armored Cat Knight）

## 基本信息

| 属性  | 值                                   |
| --- | ----------------------------------- |
| 名称  | 铁甲猫骑士                               |
| 英文  | Armored Cat Knight                  |
| 主题  | 重甲 · 盾牌 · 连射                        |
| 视角  | 俯视                                  |
| 体型  | 小型猫形，被厚重铠甲完全包裹                      |
| 特征  | 全身暗灰板甲、巨型矩形盾牌、头盔缝隙中露出橙色猫耳尖、一双发光的黄眼睛 |

---

## 外观描述

一个猫形生物被厚重的暗灰色板甲完全包裹。头盔顶部露出两只橙色尖耳朵，眼部缝隙透出冰冷的黄色光芒。左手持一面和他身体差不多大的矩形重盾，右手空出可以自由活动。整个身体呈矮胖敦实的轮廓，像一颗披甲的金属球。

---

## 动作列表

### 0. 待机 Idle

He stands motionless behind his shield, his yellow eyes scanning the player from the slit of his helmet, the only sign of life.

他持盾静立，一双黄眼睛从头盔缝隙中盯着玩家扫视，那是全身唯一证明他还活着的东西。

---

### 1. 盾牌冲锋 Shield Charge

He tucks low behind his shield and rockets forward, leaving cracked stone in his wake.

他压低身体藏在盾后向前冲刺，地面留下一道裂痕。

> 直线突进技能。BOSS 锁定玩家方向，缩在盾后高速冲锋一段距离。撞到墙壁停止，碰到玩家造成伤害和击退。动作前摇约 0.5 秒（他把盾放低的瞬间）。

---

### 2. 铁甲滚动 Armored Roll

He curls into a perfect metal ball and rolls rapidly across the arena, bouncing off walls.

他蜷成一颗完美的金属球，在场地中快速滚动，撞击墙壁反弹。

> 全场地机动技能。BOSS 蜷成一团沿随机方向滚动，遇到墙壁反弹。持续 2-3 秒，途中碰到玩家造成伤害。滚动期间 BOSS 不可被击退。

---

### 3. 连射弹幕 Barrage Fire

He plants his shield and fires a rapid burst of bullets from his free hand, spreading in a cone.

他立盾固定，空手快速射出一连串子弹，呈锥形扩散。

> 远程技能。BOSS 将盾牌插入地面固定，用空手连续射击。射出 5-8 发子弹呈锥形扩散，每发伤害不高但覆盖范围大。射击期间 BOSS 不可移动，是玩家的输出窗口。

---

### 4. 践踏震波 Stomp Shockwave

He raises one foot and slams it down, sending a ring of debris and dust outward.

他抬起一只脚猛踏地面，向外扩散出一圈碎石和烟尘。

> 范围技能。BOSS 抬脚蓄力约 0.8 秒，然后猛踏地面，以自身为中心向外扩散一圈震波。震波范围内的玩家受到伤害并被短暂减速。震波可以被跳跃或翻滚躲避。

---

### 5. 完全防御 Full Guard

He crouches behind his shield, becoming completely immobile and reflecting all frontal projectiles for a few seconds.

他蜷缩在盾牌后方完全静止数秒，弹开所有正面远程攻击。

> 防御技能。BOSS 蜷在盾后不动，持续 2-3 秒。正面射向他的子弹/远程攻击被反弹，反弹方向为来向的随机偏转。侧面和背面仍然可以被攻击。这是玩家的走位考验——绕到侧面输出。

---

## 阶段变化（Phase 2）

半血以下触发：

- 全身盔甲出现裂缝，橙色猫耳朵变成亮橙色发光
- 移动速度提升 30%
- 连射弹幕的子弹数从 5-8 发提升到 10-12 发
- 盾牌冲锋可以连续释放两次（第一次冲完立刻接第二次）

---

## 掉落物

| 物品 | 概率 | 类型 |
|------|------|------|
| 猫骑士之盾 | 25% | 防具（盾牌，高格挡率） |
| 铁甲板碎片 | 40% | 素材（可用于强化） |
| 猫眼宝石 | 15% | 素材（稀有） |
| 橙色猫毛（装饰） | 5% | 收藏品/成就物品 |

---

## 对应生图 prompt

```yaml
工具: generate_image
prompt: "pixel art soul knight style boss, top-down isometric view,
         heavily armored cat knight, dark grey plate armor,
         giant rectangular shield, orange cat ear tips peeking from helmet slit,
         glowing yellow eyes, empty right hand ready to fire,
         stout round body shape, detailed pixel shading,
         game boss fight, 128x128 transparent png,
         dark fantasy pixel art style"
name: "boss_cat_knight"
target_size: "128x128"
transparent: true
```
