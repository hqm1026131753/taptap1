# 三选一 Build 流派系统 — 第二代更新版

> 融合 Choice Reward System 与 Roguelike Build 流派设计。
> 版本：v2.0 — 7 流派 × 8 卡 = 56 张 + 6 辅助卡
> 参考《杀戮尖塔》《土豆兄弟》《哈迪斯》《枪火重生》。

---

## 一、系统概述

每完成一个阶段性目标（击杀 Boss / 每 3 波结算），弹出三选一面板，玩家从三个随机奖励中选一个。每次选择都在塑造本局的 Build 路线，组合叠加产生差异化的流派。

```
触发时机（每3波 / Boss击杀）
    ↓
BuildState 计算稀有度保底 + 流派权重
    ↓
从选项池中抽取 3 个候选
    ↓
展示三选一面板（稀有度着色 + 描述）
    ↓
玩家选 1 个 → 效果生效 → 计数器更新
    ↓
检查阈值突破（3/5/7层）→ 弹出通知
    ↓
检查流派联动 → 弹出通知
    ↓
继续游戏
```

---

## 二、七个流派方向

```
火力压制 🔥    伤害 + 射速 + 弹药        → 阈值：弹射子弹    → 联动：重火力、链式反应、电磁风暴
生存龟壳 🛡️    护甲 + HP + 回复          → 阈值：自动回血    → 联动：重火力、不死猫
机动游击 💨    移速 + 换弹 + 闪避        → 阈值：残影闪现    → 联动：游猎、不死猫
暴击一击 🎯    暴击率 + 暴击伤害 + 精准  → 阈值：必暴击      → 联动：游猎、混乱子弹
特效失控 ✨    弹射 + 爆炸 + 吸血        → 阈值：全屏弹幕    → 联动：链式反应、混乱子弹
🔪 一刀流      近战伤害 + 攻速 + 生命偷取  → 阈值：剑气斩    → 联动：不死猫、重火力
⚡ 电击        雷电 + 感电 + 暴击触发    → 阈值：感电扩散    → 联动：电磁风暴、静电冲击、雷影步、过载
```

### 一刀流说明

全程使用战术刀，不能开枪。作为放弃远程能力的代价，近战奖励数值是其他流派的 **1.5~2 倍**。

```
核心差异：
  其他流派：+20% 伤害、+15% 暴击率
  一刀流：  +50% 近战伤害、一刀清场

设计原因：近战需要贴脸，风险高于远程，回报适当匹配但不过度。一刀流的阈值为 3/5/7，没有 1 层独占阈值。
```
```

---

## 三、感电机制（电击流派专属）

感电是电击流的核心状态，叠加在敌人身上的层数本身不造成伤害，作为电击卡的效果放大器。

### 数据模型

```lua
-- 每个敌人身上维护一个感电状态
ShockState = {
    stacks = 0,       -- 当前层数（0~5）
    duration = 0,     -- 剩余持续时间（秒）
}
```

### 触发与叠层

| 来源 | 叠层 | 说明 |
|------|------|------|
| 磁暴电涌（暴击落雷） | +2 层 | 核心叠层手段 |
| 高压电击（雷电跳跃） | +1 层 | 扩散叠层 |
| 电荷炸弹（5层引爆） | 消耗所有层数 | 引爆后归零 |
| 电场加速 / 静电充能 | +0 | 不叠层，只触发自身效果 |

### 效果

感电层数本身不造成伤害，它是伤害放大器。配合感电渗透卡生效：

```
每层感电使目标受到的雷电伤害 +20%
敌人当前 3 层感电 → 雷电伤害 ×（1 + 3 × 0.20）= 雷电伤害 × 1.6
```

如果没有感电渗透卡，感电层数仅作为电荷炸弹的计数器（攒到 5 层引爆）。

### 衰减规则

```lua
-- 敌人脱离雷电攻击后，感电层数每秒衰减 1 层
function UpdateShock(enemy, timeStep)
    if enemy.shock and enemy.shock.stacks > 0 then
        enemy.shock.duration = enemy.shock.duration - timeStep
        if enemy.shock.duration <= 0 then
            enemy.shock.stacks = math.max(0, enemy.shock.stacks - 1)
            enemy.shock.duration = 3  -- 每层衰减间隔 3 秒
        end
    end
end

-- 每次受到雷电攻击时，重置计时器
function ApplyShock(enemy, stacks)
    enemy.shock = enemy.shock or { stacks = 0, duration = 0 }
    enemy.shock.stacks = math.min(5, enemy.shock.stacks + stacks)
    enemy.shock.duration = 3
end
```

### 各电击卡与感电的关系

| 卡牌 | 与感电的关系 |
|------|-------------|
| 磁暴电涌 | 暴击落雷 → 目标 +2 层感电 |
| 格斗之魂 | 提供暴击率 → 间接触发磁暴电涌叠层 |
| 高压电击 | 雷电跳跃 → 跳跃目标 +1 层感电 |
| 感电渗透 | 每层感电 → 雷电伤害 +20%（被动增益） |
| 电荷炸弹 | 层数≥5 时引爆，清空层数，范围伤害 |
| 静电充能 | 雷电跳跃伤害递增（和感电无关） |
| 电场加速 | 触发雷电时加速（和感电无关） |
| 双重射击 | 额外子弹间接叠层 |

### 视觉表现

敌人身上的感电层数用蓝色电火花环绕表示，层数越高电光越密集：

```lua
if enemy.shock and enemy.shock.stacks > 0 then
    local count = enemy.shock.stacks * 2
    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + time * 3
        local r = 6 + enemy.shock.stacks * 2
        nvg.BeginPath()
        nvg.MoveTo(ex + math.cos(angle) * r, ey + math.sin(angle) * r * 0.5)
        nvg.LineTo(ex + math.cos(angle) * r * 0.6, ey + math.sin(angle) * r * 0.6)
        nvg.StrokeColor(nvg.RGBA(100, 200, 255, 150 + enemy.shock.stacks * 20))
        nvg.StrokeWidth(1.5)
        nvg.Stroke()
    end
end
```

---

## 四、稀有度与保底

### 3.1 稀有度分层

| 等级 | 名称 | 颜色 | 基础概率 | 价值倍率 |
|------|------|------|---------|---------|
| 1 | 普通 | 白色 | 60% | ×1.0 |
| 2 | 稀有 | 蓝色 | 30% | ×1.5 |
| 3 | 史诗 | 紫色 #a855f7 | 8% | ×2.5 |
| 4 | 传说 | 大红色 #ff2a2a + 发光 | 2% | ×4.0 |

### 3.2 保底机制

```javascript
// 每局 BuildState 中维护
this.consecutiveNoEpic = 0; // 连续没出史诗/传说的次数

// 生成选项时调整传说权重
function getLegendaryWeight(buildState) {
  let w = 2; // 基础 2%
  if (buildState.consecutiveNoEpic >= 3) w += 8;  // 3连白→10%
  if (buildState.consecutiveNoEpic >= 5) w += 20; // 5连白→30%
  return w;
}

// 选了史诗+后重置
// 选了普通/稀有则 +1
```

---

## 五、Build 状态管理

```javascript
class BuildState {
  constructor(rngSeed) {
    this.rng = createSeededRandom(rngSeed); // 种子随机，同种子可复现
    this.chosen = [];            // 已选奖励列表
    this.counts = {};            // 各流派层数 { firepower: 3, agile: 1 }
    this.activeThresholds = [];   // 已解锁的阈值效果
    this.activeSynergies = [];    // 已激活的联动
    this.consecutiveNoEpic = 0;   // 保底计数器
    this.totalPicks = 0;
  }

  // 选择生效
  pick(reward) {
    this.chosen.push(reward);
    this.totalPicks++;
    
    // 累计流派层数
    if (reward.tags) {
      for (const tag of reward.tags) {
        this.counts[tag] = (this.counts[tag] || 0) + 1;
      }
    }
    
    // 检查阈值解锁
    this.checkThresholds();
    // 检查联动解锁
    this.checkSynergies();
    
    // 保底
    if (reward.rarity >= 3) this.consecutiveNoEpic = 0;
    else this.consecutiveNoEpic++;
  }

  // 调整后续选项权重
  adjustWeight(item) {
    let w = item.baseWeight || 50;
    
    // 已有流派 +30%
    for (const [tag, count] of Object.entries(this.counts)) {
      if (item.tags?.includes(tag)) w *= (1 + count * 0.3);
    }
    
    // 关联流派 +10%（鼓励混搭）
    const related = {
      firepower: ['chaos', 'crit', 'electric'],
      tank: ['agile', 'knife'],
      agile: ['tank', 'knife', 'electric'],
      crit: ['firepower', 'knife', 'electric'],
      chaos: ['firepower', 'crit', 'electric'],
      knife: ['agile', 'tank', 'crit'],
      electric: ['firepower', 'chaos', 'crit', 'agile'],
    };
    for (const [tag, count] of Object.entries(this.counts)) {
      if (count > 0 && related[tag]) {
        for (const rt of related[tag]) {
          if (item.tags?.includes(rt)) w *= (1 + count * 0.1);
        }
      }
    }
    
    return w;
  }
}
```

---

## 六、阈值突破

每个流派累计到 3/5/7 层时解锁质变效果，全游戏最多 15 个阈值。

| 流派 | 3 层 | 5 层 | 7 层 |
|------|------|------|------|
| 🔥 火力 | 过热枪管：连续命中同一敌人5次触发爆炸 | 弹射子弹：命中后弹射到附近敌人 | 无限火力：击杀后3秒不耗弹 |
| 🛡️ 龟壳 | 硬化皮肤：护甲减伤额外+10% | 自动修复：每10秒回复5%HP | 铁壁：HP<30%时50%减伤5秒 |
| 💨 机动 | 轻量化：移速+15%，换弹+20% | 残影：移动时20%概率闪避 | 闪现：换弹时短距离瞬移 |
| 🎯 暴击 | 弱点锁定：暴击率+15% | 致命一击：暴击伤害+100% | 百发百中：满血敌人必定暴击 |
| ✨ 特效 | 连锁反应：弹射+1次 | 爆破专家：爆炸范围+50% | 死亡收割：吸血+10% |
| 🔪 一刀流 | 战术精通：近战伤害+60% | 剑气斩：挥出远程剑气波 | 一刀两断：对满血敌人必定秒杀 |
| ⚡ 电击 | 感电扩散：雷电额外跳跃+2次 | 电磁风暴：击杀感电目标触发全屏闪电链 | 雷暴：暴击时三道雷电同时攻击不同目标 |

```javascript
const THRESHOLDS = {
  firepower: {
    3: { name: '过热枪管',   desc: '连续命中同一敌人5次触发额外爆炸',   effect: 'explosion_on_stack' },
    5: { name: '弹射子弹',   desc: '子弹命中后弹射到附近另一个敌人',    effect: 'bounce_once' },
    7: { name: '无限火力',   desc: '击杀后3秒内不消耗弹药',             effect: 'ammo_free_on_kill' },
  },
  tank: {
    3: { name: '硬化皮肤',   desc: '护甲减伤额外+10%',                  effect: 'armor_bonus_pct' },
    5: { name: '自动修复',   desc: '每10秒自动回复5%HP',                effect: 'auto_heal' },
    7: { name: '铁壁',       desc: 'HP低于30%时获得50%减伤5秒',        effect: 'last_stand' },
  },
  agile: {
    3: { name: '轻量化',     desc: '移速+15%，换弹速度+20%',            effect: 'lightweight' },
    5: { name: '残影',       desc: '移动时有20%概率闪避子弹',           effect: 'dodge_while_moving' },
    7: { name: '闪现',       desc: '换弹时短距离瞬移',                  effect: 'dash_on_reload' },
  },
  crit: {
    3: { name: '弱点锁定',   desc: '暴击率+15%',                        effect: 'crit_rate_up' },
    5: { name: '致命一击',   desc: '暴击伤害+100%',                     effect: 'crit_dmg_double' },
    7: { name: '百发百中',   desc: '对满血敌人必定暴击',                effect: 'guaranteed_crit_full_hp' },
  },
  chaos: {
    3: { name: '连锁反应',   desc: '弹射+1次',                          effect: 'bounce_extra' },
    5: { name: '爆破专家',   desc: '爆炸范围+50%',                      effect: 'explosion_range_up' },
    7: { name: '死亡收割',   desc: '吸血+10%',                          effect: 'lifesteal_up' },
  },
  knife: {
    3: { name: '战术精通',   desc: '近战伤害+60%，攻速+20%',           effect: 'knife_mastery' },
    5: { name: '剑气斩',     desc: '挥出远程剑气波（飞行物，穿透敌人）', effect: 'knife_slash' },
    7: { name: '一刀两断',   desc: '对满血敌人必定秒杀（Boss无效）',    effect: 'knife_oneshot' },
  },
  electric: {
    3: { name: '感电扩散',   desc: '雷电命中后额外跳跃+2次',            effect: 'elec_bounce_up' },
    5: { name: '电磁风暴',   desc: '每击杀一个感电目标，触发一次全屏闪电链', effect: 'elec_chain_explosion' },
    7: { name: '雷暴',       desc: '暴击时召唤三道雷电同时攻击不同目标',  effect: 'elec_triple_strike' },
  },
};

checkThresholds() {
  for (const path of ['firepower','tank','agile','crit','chaos','knife','electric']) {
    const level = this.counts[path] || 0;
    for (const [need, data] of Object.entries(THRESHOLDS[path] || {})) {
      if (level >= parseInt(need) && !this.activeThresholds.includes(data.effect)) {
        this.activeThresholds.push(data.effect);
        notify(`⚡ 阈值突破：${data.name} — ${data.desc}`);
      }
    }
  }
}
```

---

## 七、流派联动

两个流派达到指定层数后激活组合效果，共 11 种联动。

| 联动 | 需求 | 效果 |
|------|------|------|
| 💥 重火力 | 火力3 + 龟壳2 | 每10护甲+5%伤害 |
| 🎯 游猎 | 机动3 + 暴击2 | 移动时暴击率翻倍 |
| ⚡ 链式反应 | 特效2 + 火力2 | 爆炸有30%概率再次爆炸 |
| 🐱 不死猫 | 龟壳2 + 机动2 | 致命伤保留1HP并闪现 |
| 🌀 混乱子弹 | 特效3 + 暴击1 | 暴击时触发随机特效 |
| 👻 暗影步 | 一刀3 + 机动3 | 击杀后闪烁到附近另一个敌人背后（冷却5秒） |
| 🗡️ 刀甲 | 一刀3 + 龟壳1 | 持刀时每10护甲+5%近战伤害 |
| 🌩️ 电磁风暴 | 电击3 + 火力2 | 雷电命中时30%概率产生小爆炸 |
| ⚡ 静电冲击 | 电击2 + 特效2 | 弹射和跳跃共享触发计数，互相叠加 |
| 🌩️ 雷影步 | 电击2 + 机动2 | 触发雷电时获得短暂无敌0.3秒 |
| ⚡ 过载 | 电击3 + 暴击2 | 暴击时额外对周围造成雷电伤害 |

```javascript
const SYNERGIES = [
  { id: 'heavy_ordnance', name: '重火力', icon: '💥', require: { firepower: 3, tank: 2 },
    desc: '护甲越高伤害越高（每10护甲+5%伤害）', effect: 'armor_scales_damage' },
  { id: 'sniper_dance',   name: '游猎',   icon: '🎯', require: { agile: 3, crit: 2 },
    desc: '移动时暴击率翻倍', effect: 'move_crit_double' },
  { id: 'chaos_reaction', name: '链式反应', icon: '⚡', require: { chaos: 2, firepower: 2 },
    desc: '爆炸命中的敌人有30%概率再次爆炸', effect: 'chain_explosion' },
  { id: 'undying',        name: '不死猫',  icon: '🐱', require: { tank: 2, agile: 2 },
    desc: '受到致命伤害时保留1HP并后撤闪现', effect: 'cheat_death' },
  { id: 'shadow_step',   name: '暗影步',  icon: '👻', require: { knife: 3, agile: 3 },
    desc: '击杀敌人后闪烁到附近另一个敌人背后（冷却5秒）', effect: 'shadow_step' },
  { id: 'blade_armor',   name: '刀甲',    icon: '🗡️', require: { knife: 3, tank: 1 },
    desc: '持刀时每10护甲+5%近战伤害', effect: 'blade_armor' },
  { id: 'chaos_bullet',   name: '混乱子弹', icon: '🌀', require: { chaos: 3, crit: 1 },
    desc: '暴击时触发随机特效（弹射/爆炸/吸血）', effect: 'random_chaos_on_crit' },

  // ⚡ 电击联动
  { id: 'elec_storm',     name: '电磁风暴', icon: '🌩️', require: { electric: 3, firepower: 2 },
    desc: '雷电命中时有30%概率产生小爆炸', effect: 'elec_explode' },
  { id: 'static_shock',   name: '静电冲击', icon: '⚡', require: { electric: 2, chaos: 2 },
    desc: '弹射和跳跃共享触发计数，互相叠加', effect: 'bounce_chain_sync' },
  { id: 'thunder_dodge',  name: '雷影步',   icon: '🌩️', require: { electric: 2, agile: 2 },
    desc: '触发雷电时获得短暂无敌0.3秒', effect: 'elec_dodge' },
  { id: 'overcharge',     name: '过载',     icon: '⚡', require: { electric: 3, crit: 2 },
    desc: '暴击时除了落雷外额外对周围敌人造成雷电伤害', effect: 'elec_overcharge' },
];

checkSynergies() {
  for (const synergy of SYNERGIES) {
    if (this.activeSynergies.includes(synergy.id)) continue;
    const met = Object.entries(synergy.require).every(
      ([tag, need]) => (this.counts[tag] || 0) >= need
    );
    if (met) {
      this.activeSynergies.push(synergy.id);
      notify(`✨ 流派联动解锁：${synergy.name} — ${synergy.desc}`);
    }
  }
}
```

---

## 八、选项池

```javascript
const BUILD_OPTIONS = [
  // 🔥 火力压制
  { id: 'dmg_1',    name: '战术握把',   icon: '🔫', desc: '伤害+20%',          rarity: 1, tags: ['firepower'], baseWeight: 50,
    effect: (p) => { p.weapon.damage *= 1.2; } },
  { id: 'dmg_2',    name: '重型枪管',   icon: '🔫', desc: '伤害+40%，射速-10%', rarity: 2, tags: ['firepower'], baseWeight: 35,
    effect: (p) => { p.weapon.damage *= 1.4; p.weapon.fireRate *= 1.1; } },
  { id: 'dmg_3',    name: '高爆弹',     icon: '💥', desc: '伤害+60%，散布+20%', rarity: 3, tags: ['firepower'], baseWeight: 18,
    effect: (p) => { p.weapon.damage *= 1.6; p.weapon.spread *= 1.2; } },
  { id: 'rate_1',   name: '轻量化扳机', icon: '🔫', desc: '射速+20%',          rarity: 1, tags: ['firepower'], baseWeight: 50,
    effect: (p) => { p.weapon.fireRate = Math.max(2, p.weapon.fireRate * 0.8); } },
  { id: 'rate_2',   name: '双连发',     icon: '⚡', desc: '射速+40%',          rarity: 3, tags: ['firepower'], baseWeight: 20,
    effect: (p) => { p.weapon.fireRate = Math.max(2, p.weapon.fireRate * 0.6); } },
  { id: 'ammo_1',   name: '扩容弹匣',   icon: '📦', desc: '弹药上限+30%',      rarity: 1, tags: ['firepower'], baseWeight: 40,
    effect: (p) => { p.maxAmmo = Math.floor(p.maxAmmo * 1.3); } },
  { id: 'ammo_2',   name: '弹药回收',   icon: '♻️', desc: '击杀25%概率回1发',  rarity: 2, tags: ['firepower'], baseWeight: 22,
    effect: (p) => { p.ammoOnKill = 0.25; } },
  { id: 'infinite_ammo', name: '无限弹药',   icon: '♾️', desc: '弹药不再减少',      rarity: 4, tags: ['firepower'], baseWeight: 5,
    effect: (p) => { p.infiniteAmmo = true; } },

  // 🛡️ 生存龟壳
  { id: 'armor_1',  name: '陶瓷插板',   icon: '🛡️', desc: '护甲+15',          rarity: 1, tags: ['tank'], baseWeight: 50,
    effect: (p) => { if (p.armor) p.armor.armor += 15; } },
  { id: 'armor_2',  name: '钛合金板',   icon: '🛡️', desc: '护甲+30',          rarity: 2, tags: ['tank'], baseWeight: 30,
    effect: (p) => { if (p.armor) p.armor.armor += 30; } },
  { id: 'hp_1',     name: '体能强化',   icon: '❤️', desc: 'HP上限+30',        rarity: 1, tags: ['tank'], baseWeight: 45,
    effect: (p) => { p.maxHp += 30; p.hp += 30; } },
  { id: 'hp_2',     name: '钢铁内脏',   icon: '❤️', desc: 'HP上限+60',        rarity: 2, tags: ['tank'], baseWeight: 25,
    effect: (p) => { p.maxHp += 60; p.hp += 60; } },
  { id: 'heal_1',   name: '再生',       icon: '💚', desc: '每5秒回复1%HP',    rarity: 2, tags: ['tank'], baseWeight: 25,
    effect: (p) => { p.regenPct = (p.regenPct || 0) + 0.01; } },
  { id: 'heal_2',   name: '吸血注射',   icon: '🩸', desc: '击杀回复3%HP',     rarity: 3, tags: ['tank'], baseWeight: 15,
    effect: (p) => { p.vampirePct = (p.vampirePct || 0) + 0.05; } },
  { id: 'shield',   name: '能量护盾',   icon: '🔰', desc: '每30秒获得一个挡50伤害的护盾', rarity: 3, tags: ['tank'], baseWeight: 12,
    effect: (p) => { p.shieldHp = 50; p.shieldRecharge = 1800; } },
  { id: 'iron_skin', name: '铁皮',     icon: '🔩', desc: '受到的伤害固定-2',      rarity: 2, tags: ['tank'], baseWeight: 20,
    effect: (p) => { p.damageReduction = (p.damageReduction || 0) + 2; } },

  // 💨 机动游击
  { id: 'speed_1',  name: '跑鞋',       icon: '👟', desc: '移速+20%',          rarity: 1, tags: ['agile'], baseWeight: 45,
    effect: (p) => { p.speed *= 1.2; } },
  { id: 'speed_2',  name: '喷射背包',   icon: '🚀', desc: '移速+40%',          rarity: 2, tags: ['agile'], baseWeight: 22,
    effect: (p) => { p.speed *= 1.4; } },
  { id: 'reload_1', name: '快速换弹',   icon: '🔄', desc: '换弹速度+30%',     rarity: 1, tags: ['agile'], baseWeight: 40,
    effect: (p) => { p.reloadTime = Math.floor(p.reloadTime * 0.7); } },
  { id: 'reload_2', name: '肌肉记忆',   icon: '🔄', desc: '换弹速度+60%',     rarity: 3, tags: ['agile'], baseWeight: 18,
    effect: (p) => { p.reloadTime = Math.floor(p.reloadTime * 0.4); } },
  { id: 'dodge_1',  name: '战术翻滚',   icon: '💨', desc: '受伤后短暂无敌0.5秒', rarity: 2, tags: ['agile'], baseWeight: 20,
    effect: (p) => { p.dodgeWindow = 30; } },
  { id: 'ammo_pickup',name: '搜弹手',   icon: '📦', desc: '拾取子弹盒时获得弹药+15', rarity: 2, tags: ['agile'], baseWeight: 18,
    effect: (p) => { p.bonusAmmoPickup = 15; } },
  { id: 'light_feet',name: '轻盈',     icon: '🪽', desc: '移动时有50%概率闪避伤害', rarity: 4, tags: ['agile'], baseWeight: 8,
    effect: (p) => { p.moveDodge = 0.5; } },

  // 🎯 暴击一击
  { id: 'crit_1',   name: '精准镜',     icon: '🎯', desc: '暴击率+15%',        rarity: 2, tags: ['crit'], baseWeight: 30,
    effect: (p) => { p.critChance = (p.critChance || 0) + 0.15; } },
  { id: 'crit_2',   name: '全息瞄准',   icon: '🎯', desc: '暴击率+30%',        rarity: 3, tags: ['crit'], baseWeight: 15,
    effect: (p) => { p.critChance = (p.critChance || 0) + 0.3; } },
  { id: 'crit_dmg', name: '穿甲弹头',   icon: '💥', desc: '暴击伤害+100%',     rarity: 3, tags: ['crit'], baseWeight: 15,
    effect: (p) => { p.critMultiplier = (p.critMultiplier || 2) + 1; } },
  { id: 'crit_dmg_2',name: '致命一击',  icon: '💥', desc: '暴击伤害+200%',     rarity: 4, tags: ['crit'], baseWeight: 8,
    effect: (p) => { p.critMultiplier = (p.critMultiplier || 2) + 2; } },
  { id: 'precision',name: '稳定器',     icon: '📐', desc: '散布-30%',          rarity: 2, tags: ['crit'], baseWeight: 22,
    effect: (p) => { p.weapon.spread *= 0.7; } },
  { id: 'execute',  name: '处决',       icon: '⚔️', desc: '对HP<20%的敌人必定暴击', rarity: 3, tags: ['crit'], baseWeight: 12,
    effect: (p) => { p.executeThresh = 0.20; } },
  { id: 'sniper_scope',name: '狙击镜', icon: '🔭', desc: '散布-50%，伤害+15%',  rarity: 3, tags: ['crit'], baseWeight: 12,
    effect: (p) => { p.weapon.spread *= 0.5; p.weapon.damage *= 1.15; } },
  { id: 'mark_target',name: '弱点标记',icon: '📍', desc: '连续命中同一敌人3次后暴击率+50%', rarity: 3, tags: ['crit'], baseWeight: 10,
    effect: (p) => { p.markTarget = true; } },

  // ✨ 特效失控
  { id: 'bounce_1',  name: '跳弹',      icon: '💫', desc: '子弹弹射1次',       rarity: 3, tags: ['chaos'], baseWeight: 15,
    effect: (p) => { p.bounceCount = (p.bounceCount || 0) + 1; } },
  { id: 'bounce_2',  name: '弹射链',    icon: '💫', desc: '子弹弹射+2次',      rarity: 4, tags: ['chaos'], baseWeight: 8,
    effect: (p) => { p.bounceCount = (p.bounceCount || 0) + 2; } },
  { id: 'explode_1', name: '爆破弹',    icon: '💥', desc: '命中产生小爆炸',    rarity: 3, tags: ['chaos'], baseWeight: 12,
    effect: (p) => { p.hasExplosion = true; p.explosionRadius = 40; } },
  { id: 'explode_2', name: '地狱火',    icon: '🔥', desc: '爆炸范围+50%',      rarity: 3, tags: ['chaos'], baseWeight: 10,
    effect: (p) => { p.explosionRadius = (p.explosionRadius || 40) * 1.5; } },
  { id: 'ls_1',      name: '吸血弹头',  icon: '🩸', desc: '击杀回复3%HP',     rarity: 4, tags: ['chaos'], baseWeight: 10,
    effect: (p) => { p.hasLifesteal = true; p.lifestealPct = 0.03; } },
  { id: 'ls_2',      name: '血祭',      icon: '🩸', desc: '击杀回复5%HP',     rarity: 4, tags: ['chaos'], baseWeight: 6,
    effect: (p) => { p.hasLifesteal = true; p.lifestealPct = (p.lifestealPct || 0) + 0.05; } },
  { id: 'lightning', name: '闪电链',    icon: '⚡', desc: '子弹有15%概率触发连锁闪电', rarity: 4, tags: ['chaos'], baseWeight: 7,
    effect: (p) => { p.chainLightning = true; p.chainChance = 0.15; } },
  { id: 'chaos_mag',  name: '混乱弹夹', icon: '🎲', desc: '每次换弹随机触发一种特效', rarity: 3, tags: ['chaos'], baseWeight: 9,
    effect: (p) => { p.randomOnReload = true; } },

  // ⚡ 电击
  { id: 'magnetic_storm',   name: '磁暴电涌',   icon: '⚡', desc: '暴击时在目标处落下雷电', rarity: 2, tags: ['electric'], baseWeight: 30,
    effect: (p) => { p.electricStorm = true; } },
  { id: 'fighting_spirit',  name: '格斗之魂',   icon: '💢', desc: '每10次攻击必定暴击', rarity: 1, tags: ['electric'], baseWeight: 50,
    effect: (p) => { p.guaranteedCritEvery = 10; } },
  { id: 'high_voltage',     name: '高压电击',   icon: '⚡', desc: '雷电命中后跳跃至附近一个敌人，每次跳跃伤害递减15%', rarity: 2, tags: ['electric'], baseWeight: 22,
    effect: (p) => { p.elecChain = true; p.elecChainDecay = 0.85; } },
  { id: 'shock_infusion',   name: '感电渗透',   icon: '🔵', desc: '每层感电效果使目标受到的雷电伤害提升20%', rarity: 3, tags: ['electric'], baseWeight: 15,
    effect: (p) => { p.shockStackBonus = 0.2; } },
  { id: 'double_shot_elec', name: '双重射击',   icon: '🔫', desc: '开火时额外发射一枚子弹（伤害减半）', rarity: 3, tags: ['electric'], baseWeight: 18,
    effect: (p) => { p.doubleShot = true; } },
  { id: 'charge_bomb',      name: '电荷炸弹',   icon: '💥', desc: '目标感电层数达到5层时爆炸，造成范围雷电伤害', rarity: 3, tags: ['electric'], baseWeight: 12,
    effect: (p) => { p.shockDetonate = true; p.shockDetonateAt = 5; } },
  { id: 'field_accel',      name: '电场加速',   icon: '💨', desc: '每触发一次雷电效果，移速提升5%，持续2秒', rarity: 1, tags: ['electric'], baseWeight: 35,
    effect: (p) => { p.electricSpeedBoost = 0.05; } },
  { id: 'static_charge',    name: '静电充能',   icon: '⚡', desc: '雷电每跳跃一次，伤害递增10%', rarity: 2, tags: ['electric'], baseWeight: 20,
    effect: (p) => { p.chainRampUp = 0.1; } },
  // 🔪 一刀流
  { id: 'knife_dmg_2',  name: '开刃',      icon: '🗡️', desc: '近战伤害+60%',           rarity: 2, tags: ['knife'], baseWeight: 30,
    effect: (p) => { p.knifeDamage = (p.knifeDamage || 10) * 1.6; } },
  { id: 'knife_spd_1',  name: '轻量化刀柄', icon: '🗡️', desc: '攻击速度+30%',         rarity: 1, tags: ['knife'], baseWeight: 40,
    effect: (p) => { p.knifeSpeed = (p.knifeSpeed || 1) * 1.3; } },
  { id: 'knife_range',  name: '延展刀刃',  icon: '🗡️', desc: '近战攻击距离+50%',        rarity: 2, tags: ['knife'], baseWeight: 30,
    effect: (p) => { p.knifeRange = (p.knifeRange || 50) * 1.5; } },
  { id: 'knife_ls',     name: '嗜血',      icon: '🩸', desc: '近战击杀回复10%HP',      rarity: 2, tags: ['knife'], baseWeight: 20,
    effect: (p) => { p.knifeHealOnKill = 0.1; } },
  { id: 'knife_aoe',    name: '横扫',      icon: '💫', desc: '近战攻击同时伤害周围所有敌人', rarity: 3, tags: ['knife'], baseWeight: 15,
    effect: (p) => { p.knifeAoe = true; p.knifeAoeRadius = 60; } },
  { id: 'knife_parry',  name: '切子弹',    icon: '🌀', desc: '近战攻击可以砍掉飞行中的敌方子弹', rarity: 2, tags: ['knife'], baseWeight: 25,
    effect: (p) => { p.knifeParry = true; } },
  { id: 'knife_parry_2',name: '弹反',      icon: '🔄', desc: '砍掉的子弹反弹回敌人方向',       rarity: 3, tags: ['knife'], baseWeight: 15,
    effect: (p) => { p.knifeParry = true; p.knifeReflect = true; } },
  { id: 'knife_parry_3',name: '刀锋风暴',  icon: '🌪️', desc: '砍掉子弹后3秒内攻速翻倍（自带切子弹效果）', rarity: 4, tags: ['knife','agile'], baseWeight: 8,
    effect: (p) => { p.knifeParry = true; p.knifeRageOnParry = true; } },

  // === 🎯 辅助类 ===
  // 不增加战斗属性，改变三选一规则本身
  { id: 'assist_reroll',   name: '重选',    icon: '🔁', desc: '本次三选一可刷新一次',        rarity: 1, tags: ['assist'], baseWeight: 15,
    effect: () => {} },
  { id: 'assist_reroll_2', name: '两次重选', icon: '🔁', desc: '获得2次重选机会（本局有效）', rarity: 2, tags: ['assist'], baseWeight: 10,
    effect: (p) => { p.assistRerolls = (p.assistRerolls || 0) + 2; } },
  { id: 'assist_pick2',    name: '我全都要', icon: '✋', desc: '本次三个全选',               rarity: 3, tags: ['assist'], baseWeight: 8,
    effect: () => {} },
  { id: 'assist_rarity_up',name: '品质提升', icon: '⬆️', desc: '本次三选一全升一级稀有度',    rarity: 3, tags: ['assist'], baseWeight: 6,
    effect: () => {} },
  { id: 'assist_remove',   name: '排除',    icon: '❌', desc: '排除一个流派（本局不再出现）',  rarity: 2, tags: ['assist'], baseWeight: 5,
    effect: () => {} },
  { id: 'assist_choice_4', name: '四选一',  icon: '4️⃣', desc: '下次三选一变成四选一',          rarity: 2, tags: ['assist'], baseWeight: 8,
    effect: () => {} },
];
```

---

## 九、选项生成逻辑

```javascript
function generateChoices(buildState, pool, count = 3) {
  // 1. 计算保底
  let legendaryWeight = 2;
  if (buildState.consecutiveNoEpic >= 3) legendaryWeight += 8;
  if (buildState.consecutiveNoEpic >= 5) legendaryWeight += 20;
  const rarityWeights = [60, 30, 8, legendaryWeight];

  // 2. 按稀有度抽取
  const choices = [];
  for (let i = 0; i < count; i++) {
    const rarity = weightedPick([1, 2, 3, 4], rarityWeights, buildState.rng);
    const candidates = pool.filter(p => p.rarity === rarity);
    if (candidates.length === 0) continue;

    // 3. 按 Build 权重排序
    const scored = candidates.map(c => ({ ...c, score: buildState.adjustWeight(c) }));
    scored.sort((a, b) => b.score - a.score);
    
    // 4. 取最高分（避免随机波动）
    choices.push(scored[0]);
  }
  return choices;
}

function weightedPick(items, weights, rng) {
  const total = weights.reduce((a, b) => a + b, 0);
  let roll = (rng || Math.random)() * total;
  for (let i = 0; i < items.length; i++) {
    roll -= weights[i];
    if (roll <= 0) return items[i];
  }
  return items[items.length - 1];
}
```

---

## 十、UI 渲染

```css
#choicePanel {
  position: absolute; inset: 0; display: none;
  justify-content: center; align-items: center;
  background: rgba(15,20,25,0.92); z-index: 20;
}
.choices { display: flex; gap: 20px; }
.choice-card {
  width: 200px; padding: 24px 16px;
  background: rgba(30,35,45,0.7); border: 1px solid rgba(0,240,255,0.15);
  border-radius: 8px; cursor: pointer; text-align: center;
  transition: all 0.2s; backdrop-filter: blur(4px);
}
.choice-card:hover {
  border-color: #00f0ff; transform: translateY(-6px);
  box-shadow: 0 8px 30px rgba(0,240,255,0.15);
}
.choice-card .icon { font-size: 36px; margin-bottom: 6px; }
.choice-card .name { color: #fff; font-size: 16px; font-weight: 600; }
.choice-card .desc { color: rgba(255,255,255,0.6); font-size: 12px; margin-top: 6px; }
.choice-card .rarity-tag {
  display: inline-block; padding: 2px 10px; border-radius: 10px;
  font-size: 10px; margin-top: 8px;
}
.rarity-1 { border-color: rgba(255,255,255,0.2); }
.rarity-2 { border-color: rgba(0,240,255,0.4); }
.rarity-3 { border-color: #a855f7; }
.rarity-4 { border-color: #ff2a2a; box-shadow: 0 0 20px rgba(255,42,42,0.3); }
```

```javascript
function showChoicePanel(rewards, buildState) {
  const panel = document.getElementById('choicePanel');
  panel.style.display = 'flex';
  const container = panel.querySelector('.choices');
  container.innerHTML = '';

  rewards.forEach((r) => {
    const card = document.createElement('div');
    const rarityNames = ['', '普通', '稀有', '史诗', '传说'];
    card.className = `choice-card rarity-${r.rarity}`;
    card.innerHTML = `
      <div class="icon">${r.icon}</div>
      <div class="name">${r.name}</div>
      <div class="desc">${r.desc}</div>
      <div class="rarity-tag">${rarityNames[r.rarity] || ''}</div>
    `;
    card.onclick = () => {
      buildState.pick(r);
      r.effect(player);
      panel.style.display = 'none';
    };
    container.appendChild(card);
  });
}
```

---

## 十一、触发时机

```javascript
// 每3波触发
function onWaveComplete(wave, buildState) {
  if (wave % 3 === 0) {
    const choices = generateChoices(buildState, BUILD_OPTIONS, 3);
    showChoicePanel(choices, buildState);
  }
}

// Boss击杀触发（带保底加成）
function onBossDefeated(floor, buildState) {
  buildState.consecutiveNoEpic = Math.min(buildState.consecutiveNoEpic + 2, 5);
  const choices = generateChoices(buildState, BUILD_OPTIONS, 3);
  showChoicePanel(choices, buildState);
}
```

---

## 十二、参考来源

| 游戏 | 借鉴点 | 在本系统中的体现 |
|------|--------|----------------|
| 杀戮尖塔 | 卡牌稀有度 + 保底 | 白/蓝/紫/金 + 连续白板后保底 |
| 土豆兄弟 | 属性堆叠 → 阈值质变 | 流派 3/5/7 层解锁额外效果 |
| 哈迪斯 | 神恩组合联动 | 5 种双流派联动组合 |
| 枪火重生 | 武器与 Build 解耦 | Build 不绑定具体枪械 |
