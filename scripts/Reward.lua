-- ============================================================================
-- Reward.lua — 三选一 Build 流派系统（BuildState + 选项池 + 生成逻辑）
-- 参考《杀戮尖塔》《土豆兄弟》《哈迪斯》《枪火重生》
-- ============================================================================
local M = {}

-- ============================================================================
-- 一、常量：稀有度 / 流派名
-- ============================================================================
M.RARITY_NAMES  = { "普通", "稀有", "史诗", "传说" }

-- 稀有度颜色（r,g,b）—— 供 Render.lua 使用
M.RARITY_COLOR = {
    [1] = { 160, 168, 180 },   -- 白
    [2] = {  78, 204, 163 },   -- 蓝
    [3] = { 168,  85, 247 },   -- 紫 #a855f7
    [4] = { 255,  42,  42 },   -- 大红 #ff2a2a + 发光
}

-- 流派中文名/图标
M.PATH_INFO = {
    firepower = { name = "火力压制", icon = "🔥" },
    tank      = { name = "生存龟壳", icon = "🛡️" },
    agile     = { name = "机动游击", icon = "💨" },
    crit      = { name = "暴击一击", icon = "🎯" },
    chaos     = { name = "特效失控", icon = "✨" },
    knife     = { name = "一刀流",   icon = "🔪" },
    electric  = { name = "电击",     icon = "⚡" },
    assist    = { name = "辅助",     icon = "🔧" },
}

-- ============================================================================
-- 二、阈值定义 THRESHOLDS[path][层数] = { name, desc, effect }
-- ============================================================================
local THRESHOLDS = {
    firepower = {
        -- 连续命中同一敌人5次触发额外爆炸（运行时：Enemy.lua读 p.explosionOnStack）
        [3] = { name = "过热枪管",   desc = "连续命中同一敌人5次触发额外爆炸",  effect = "explosion_on_stack",
                apply = function(p) p.explosionOnStack = true end },
        -- 弹射子弹
        [5] = { name = "弹射子弹",   desc = "子弹命中后弹射到附近另一个敌人",   effect = "bounce_once",
                apply = function(p) p.bounceCount = (p.bounceCount or 0) + 1 end },
        -- 击杀后3秒免费弹药（运行时：Player.lua读 p.ammoFreeTimer）
        [7] = { name = "无限火力",   desc = "击杀后3秒内不消耗弹药",            effect = "ammo_free_on_kill",
                apply = function(p) p.ammoFreeOnKill = true end },
    },
    tank = {
        -- 护甲额外+20点（约等于+10%减伤）
        [3] = { name = "硬化皮肤",   desc = "护甲减伤额外+10%",                 effect = "armor_bonus_pct",
                apply = function(p) p.bonusArmor = (p.bonusArmor or 0) + 20 end },
        -- 每10秒回复5%HP（运行时：Player.lua读 p.autoHealTimer / p.autoHealPct）
        [5] = { name = "自动修复",   desc = "每10秒自动回复5%HP",               effect = "auto_heal",
                apply = function(p) p.autoHealPct = (p.autoHealPct or 0) + 0.05; p.autoHealTimer = p.autoHealTimer or 0 end },
        -- HP<30%时减伤50%（运行时：Player.lua读 p.lastStand）
        [7] = { name = "铁壁",       desc = "HP低于30%时获得50%减伤5秒",        effect = "last_stand",
                apply = function(p) p.lastStand = true end },
    },
    agile = {
        -- 移速+15%，换弹+20%
        [3] = { name = "轻量化",     desc = "移速+15%，换弹速度+20%",           effect = "lightweight",
                apply = function(p) p.speedMult = (p.speedMult or 1.0) * 1.15; p.reloadMult = (p.reloadMult or 1.0) * 0.8 end },
        -- 移动时20%概率闪避（运行时：Player.lua读 p.dodgeWhileMoving）
        [5] = { name = "残影",       desc = "移动时有20%概率闪避子弹",          effect = "dodge_while_moving",
                apply = function(p) p.dodgeWhileMoving = true end },
        -- 换弹时短距离瞬移（运行时：Player.lua读 p.dashOnReload）
        [7] = { name = "闪现",       desc = "换弹时短距离瞬移",                 effect = "dash_on_reload",
                apply = function(p) p.dashOnReload = true end },
    },
    crit = {
        -- 暴击率+15%
        [3] = { name = "弱点锁定",   desc = "暴击率+15%",                       effect = "crit_rate_up",
                apply = function(p) p.critChance = (p.critChance or 0) + 0.15 end },
        -- 暴击伤害+100%
        [5] = { name = "致命一击",   desc = "暴击伤害+100%",                    effect = "crit_dmg_double",
                apply = function(p) p.critMultiplier = (p.critMultiplier or 2.0) + 1.0 end },
        -- 对满血敌人必定暴击（运行时：Enemy.lua读 p.guaranteedCritFullHp）
        [7] = { name = "百发百中",   desc = "对满血敌人必定暴击",               effect = "guaranteed_crit_full_hp",
                apply = function(p) p.guaranteedCritFullHp = true end },
    },
    chaos = {
        -- 弹射+1次
        [3] = { name = "连锁反应",   desc = "弹射+1次",                         effect = "bounce_extra",
                apply = function(p) p.bounceCount = (p.bounceCount or 0) + 1 end },
        -- 爆炸范围+50%
        [5] = { name = "爆破专家",   desc = "爆炸范围+50%",                     effect = "explosion_range_up",
                apply = function(p) p.explosionRadius = math.floor((p.explosionRadius or 40) * 1.5) end },
        -- 吸血+10%
        [7] = { name = "死亡收割",   desc = "吸血+10%",                         effect = "lifesteal_up",
                apply = function(p) p.hasLifesteal = true; p.lifestealPct = (p.lifestealPct or 0) + 0.10 end },
    },
    knife = {
        -- 近战伤害+60%，攻速+20%
        [3] = { name = "战术精通",   desc = "近战伤害+60%，攻速+20%",           effect = "knife_mastery",
                apply = function(p) p.knife.damage = math.floor(p.knife.damage * 1.6 + 0.5); p.knife.fireRate = math.max(0.05, p.knife.fireRate * 0.8) end },
        -- 挥出远程剑气波（运行时：Player.lua读 p.knifeSlashWave）
        [5] = { name = "剑气斩",     desc = "挥出远程剑气波（穿透敌人）",       effect = "knife_slash",
                apply = function(p) p.knifeSlashWave = true end },
        -- 对满血敌人秒杀（运行时：Player.lua读 p.knifeOneshot）
        [7] = { name = "一刀两断",   desc = "对满血敌人必定秒杀（Boss无效）",   effect = "knife_oneshot",
                apply = function(p) p.knifeOneshot = true end },
    },
    electric = {
        -- 雷电额外跳跃+2次
        [3] = { name = "感电扩散",   desc = "雷电命中后额外跳跃+2次",           effect = "elec_bounce_up",
                apply = function(p) p.elecExtraBounce = (p.elecExtraBounce or 0) + 2 end },
        -- 击杀感电目标触发全屏闪电链
        [5] = { name = "电磁风暴",   desc = "击杀感电目标触发全屏闪电链",       effect = "elec_chain_explosion",
                apply = function(p) p.elecChainExplosion = true end },
        -- 暴击时三道雷电同时攻击不同目标
        [7] = { name = "雷暴",       desc = "暴击时召唤三道雷电同时攻击不同目标", effect = "elec_triple_strike",
                apply = function(p) p.elecTripleStrike = true end },
    },
}

-- ============================================================================
-- 三、联动定义 SYNERGIES
-- ============================================================================
local SYNERGIES = {
    -- 护甲越高伤害越高（运行时：Enemy.lua读 p.armorScalesDamage）
    { id = "heavy_ordnance", name = "重火力",   icon = "💥",
      require = { firepower = 3, tank = 2 },
      desc   = "护甲越高伤害越高（每10护甲+5%伤害）",
      effect = "armor_scales_damage",
      apply  = function(p) p.armorScalesDamage = true end },
    -- 移动时暴击率翻倍（运行时：Enemy.lua读 p.moveCritDouble）
    { id = "sniper_dance",   name = "游猎",     icon = "🎯",
      require = { agile = 3, crit = 2 },
      desc   = "移动时暴击率翻倍",
      effect = "move_crit_double",
      apply  = function(p) p.moveCritDouble = true end },
    -- 爆炸30%概率链爆（运行时：Enemy.lua读 p.chainExplosion）
    { id = "chaos_reaction", name = "链式反应", icon = "⚡",
      require = { chaos = 2, firepower = 2 },
      desc   = "爆炸命中的敌人有30%概率再次爆炸",
      effect = "chain_explosion",
      apply  = function(p) p.chainExplosion = true end },
    -- 受致命伤害时保留1HP（运行时：Player.lua读 p.cheatDeath）
    { id = "undying",        name = "不死猫",   icon = "🐱",
      require = { tank = 2, agile = 2 },
      desc   = "受到致命伤害时保留1HP并后撤闪现",
      effect = "cheat_death",
      apply  = function(p) p.cheatDeath = true end },
    -- 击杀后闪烁到视野范围内敌人背后（冷却5秒）（运行时：Player.lua/Enemy.lua读 p.shadowStep）
    { id = "shadow_step",    name = "暗影步",   icon = "👻",
      require = { knife = 3, agile = 3 },
      desc   = "击杀敌人后瞬移到视野范围内另一个敌人背后（冷却5秒）",
      effect = "shadow_step",
      apply  = function(p) p.shadowStep = true; p.shadowStepCd = 5.0 end },
    -- 持刀时每10护甲+5%近战伤害（运行时：Player.lua读 p.bladeArmor）
    { id = "blade_armor",    name = "刀甲",     icon = "🗡️",
      require = { knife = 3, tank = 1 },
      desc   = "持刀时每10护甲+5%近战伤害",
      effect = "blade_armor",
      apply  = function(p) p.bladeArmor = true end },
    -- 暴击时随机触发弹射/爆炸/吸血（运行时：Enemy.lua读 p.randomChaosOnCrit）
    { id = "chaos_bullet",   name = "混乱子弹", icon = "🌀",
      require = { chaos = 3, crit = 1 },
      desc   = "暴击时触发随机特效（弹射/爆炸/吸血）",
      effect = "random_chaos_on_crit",
      apply  = function(p) p.randomChaosOnCrit = true end },

    -- ⚡ 电击联动（4种）
    -- 雷电命中时30%概率产生小爆炸
    { id = "elec_storm",     name = "电磁风暴", icon = "🌩️",
      require = { electric = 3, firepower = 2 },
      desc   = "雷电命中时有30%概率产生小爆炸",
      effect = "elec_explode",
      apply  = function(p) p.elecExplode = true; p.elecExplodeChance = 0.30 end },
    -- 弹射和跳跃共享触发计数，互相叠加
    { id = "static_shock",   name = "静电冲击", icon = "⚡",
      require = { electric = 2, chaos = 2 },
      desc   = "弹射和雷电跳跃共享触发计数，互相叠加",
      effect = "bounce_chain_sync",
      apply  = function(p) p.bounceChainSync = true end },
    -- 触发雷电时获得短暂无敌0.3秒
    { id = "thunder_dodge",  name = "雷影步",   icon = "🌩️",
      require = { electric = 2, agile = 2 },
      desc   = "触发雷电时获得短暂无敌0.3秒",
      effect = "elec_dodge",
      apply  = function(p) p.elecDodge = true; p.elecDodgeDur = 0.3 end },
    -- 暴击时额外对周围造成雷电伤害
    { id = "overcharge",     name = "过载",     icon = "⚡",
      require = { electric = 3, crit = 2 },
      desc   = "暴击时额外对周围敌人造成雷电伤害",
      effect = "elec_overcharge",
      apply  = function(p) p.elecOvercharge = true end },
}
M.SYNERGIES = SYNERGIES  -- 供外部读取

-- ============================================================================
-- 四、选项池 BUILD_OPTIONS  (v2.0 — 7流派×8卡 + 6辅助)
-- ============================================================================
M.POOL = {
    -- ── 🔥 火力压制（8张）────────────────────────────────────────
    { id="dmg_1",     name="战术握把",   icon="🔫", rarity=1, tags={"firepower"}, baseWeight=50,
      desc="伤害+20%",
      effect=function(p) p.weapon.damage = math.floor(p.weapon.damage * 1.2 + 0.5) end },
    { id="dmg_2",     name="重型枪管",   icon="🔫", rarity=2, tags={"firepower"}, baseWeight=35,
      desc="伤害+40%，射速-10%",
      effect=function(p)
          p.weapon.damage   = math.floor(p.weapon.damage * 1.4 + 0.5)
          p.weapon.fireRate = p.weapon.fireRate * 1.1
      end },
    { id="dmg_3",     name="高爆弹",     icon="💥", rarity=3, tags={"firepower"}, baseWeight=18,
      desc="伤害+60%，散布+20%",
      effect=function(p)
          p.weapon.damage = math.floor(p.weapon.damage * 1.6 + 0.5)
          p.weapon.spread = (p.weapon.spread or 0.1) * 1.2
      end },
    { id="rate_1",    name="轻量化扳机", icon="🔫", rarity=1, tags={"firepower"}, baseWeight=50,
      desc="攻速+20%（射击与近战共享）",
      effect=function(p)
          p.weapon.fireRate = math.max(0.05, p.weapon.fireRate * 0.8)
          if p.knife then p.knife.fireRate = math.max(0.05, p.knife.fireRate * 0.8) end
      end },
    { id="rate_2",    name="双连发",     icon="⚡", rarity=3, tags={"firepower"}, baseWeight=20,
      desc="射速+40%",
      effect=function(p) p.weapon.fireRate = math.max(0.05, p.weapon.fireRate * 0.6) end },
    { id="ammo_1",    name="扩容弹匣",   icon="📦", rarity=1, tags={"firepower"}, baseWeight=40,
      desc="弹药上限+30%",
      effect=function(p)
          p.weapon.maxAmmo = math.ceil(p.weapon.maxAmmo * 1.3)
          p.weapon.ammo    = p.weapon.maxAmmo
      end },
    { id="ammo_2",    name="弹药回收",   icon="♻️", rarity=2, tags={"firepower"}, baseWeight=22,
      desc="击杀25%概率回1发弹药",
      effect=function(p) p.ammoOnKill = (p.ammoOnKill or 0) + 0.25 end },
    { id="infinite_ammo", name="无限弹药", icon="♾️", rarity=4, tags={"firepower"}, baseWeight=5,
      desc="弹药不再减少",
      effect=function(p) p.infiniteAmmo = true end },

    -- ── 🛡️ 生存龟壳（8张）────────────────────────────────────────
    { id="armor_1",   name="陶瓷插板",   icon="🛡️", rarity=1, tags={"tank"}, baseWeight=50,
      desc="护甲+15",
      effect=function(p) p.bonusArmor = (p.bonusArmor or 0) + 15 end },
    { id="armor_2",   name="钛合金板",   icon="🛡️", rarity=2, tags={"tank"}, baseWeight=30,
      desc="护甲+30",
      effect=function(p) p.bonusArmor = (p.bonusArmor or 0) + 30 end },
    { id="hp_1",      name="体能强化",   icon="❤️", rarity=1, tags={"tank"}, baseWeight=45,
      desc="HP上限+30",
      effect=function(p) p.maxHp = p.maxHp + 30; p.hp = math.min(p.maxHp, p.hp + 30) end },
    { id="hp_2",      name="钢铁内脏",   icon="❤️", rarity=2, tags={"tank"}, baseWeight=25,
      desc="HP上限+60",
      effect=function(p) p.maxHp = p.maxHp + 60; p.hp = math.min(p.maxHp, p.hp + 60) end },
    { id="heal_1",    name="再生",        icon="💚", rarity=2, tags={"tank"}, baseWeight=25,
      desc="每5秒回复2%HP",
      effect=function(p) p.regenPct = (p.regenPct or 0) + 0.02; p.regenTimer = p.regenTimer or 0 end },
    { id="heal_2",    name="吸血注射",    icon="🩸", rarity=3, tags={"tank"}, baseWeight=15,
      desc="击杀回复5%HP",
      effect=function(p) p.vampirePct = (p.vampirePct or 0) + 0.05 end },
    { id="shield",    name="能量护盾",    icon="🔰", rarity=3, tags={"tank"}, baseWeight=12,
      desc="每30秒获得一个挡50伤害的护盾",
      effect=function(p) p.shieldMax = (p.shieldMax or 0) + 50; p.shieldHp = (p.shieldHp or 0) + 50; p.shieldRechargeTimer = 0 end },
    { id="iron_skin", name="铁皮",        icon="🔩", rarity=2, tags={"tank"}, baseWeight=20,
      desc="受到的伤害固定-2",
      effect=function(p) p.damageReduction = (p.damageReduction or 0) + 2 end },

    -- ── 💨 机动游击（9张）────────────────────────────────────────
    { id="speed_1",   name="跑鞋",        icon="👟", rarity=1, tags={"agile"}, baseWeight=45,
      desc="移速+20%",
      effect=function(p) p.speedMult = (p.speedMult or 1.0) * 1.2 end },

    { id="reload_1",  name="快速换弹",    icon="🔄", rarity=1, tags={"agile"}, baseWeight=40,
      desc="换弹速度+30%",
      effect=function(p) p.reloadMult = (p.reloadMult or 1.0) * 0.70 end },
    { id="reload_2",  name="肌肉记忆",    icon="🔄", rarity=3, tags={"agile"}, baseWeight=18,
      desc="换弹速度+60%",
      effect=function(p) p.reloadMult = (p.reloadMult or 1.0) * 0.40 end },
    { id="dodge_1",   name="战术翻滚",    icon="💨", rarity=2, tags={"agile"}, baseWeight=20,
      desc="受伤后短暂无敌0.5秒",
      effect=function(p) p.dodgeWindow = 0.5 end },
    { id="ammo_pickup",name="搜弹手",     icon="📦", rarity=2, tags={"agile"}, baseWeight=18,
      desc="拾取子弹盒时获得弹药+15",
      effect=function(p) p.bonusAmmoPickup = (p.bonusAmmoPickup or 0) + 15 end },
    { id="light_feet", name="轻盈",       icon="🪽", rarity=4, tags={"agile"}, baseWeight=8,
      desc="移动时有50%概率闪避伤害",
      effect=function(p) p.moveDodge = (p.moveDodge or 0) + 0.5 end },
    { id="light_gear", name="轻装备",     icon="🥷", rarity=3, tags={"agile"}, baseWeight=14,
      desc="移速+15%，换弹速度+25%，受到伤害-1",
      effect=function(p)
          p.speedMult  = (p.speedMult  or 1.0) * 1.15
          p.reloadMult = (p.reloadMult or 1.0) * 0.75
          p.damageReduction = (p.damageReduction or 0) + 1
      end },
    { id="roll_cd_1",  name="灵活身法",   icon="💨", rarity=2, tags={"agile"}, baseWeight=22,
      desc="翻滚冷却-1秒",
      effect=function(p) p.rollCdReduction = (p.rollCdReduction or 0) + 1.0 end },
    { id="roll_cd_0",  name="永动机",     icon="⚡", rarity=4, tags={"agile"}, baseWeight=6,
      desc="翻滚无冷却",
      effect=function(p) p.noRollCd = true end },

    -- ── 🎯 暴击一击（8张）──────────────────────────────────────────
    { id="crit_1",    name="精准镜",      icon="🎯", rarity=2, tags={"crit"}, baseWeight=30,
      desc="暴击率+15%",
      effect=function(p) p.critChance = (p.critChance or 0) + 0.15 end },
    { id="crit_2",    name="全息瞄准",    icon="🎯", rarity=3, tags={"crit"}, baseWeight=15,
      desc="暴击率+30%",
      effect=function(p) p.critChance = (p.critChance or 0) + 0.30 end },
    { id="crit_dmg",  name="穿甲弹头",    icon="💥", rarity=3, tags={"crit"}, baseWeight=15,
      desc="暴击伤害+100%",
      effect=function(p) p.critMultiplier = (p.critMultiplier or 2.0) + 1.0 end },
    { id="crit_dmg_2",name="致命一击",    icon="💥", rarity=4, tags={"crit"}, baseWeight=8,
      desc="暴击伤害+200%",
      effect=function(p) p.critMultiplier = (p.critMultiplier or 2.0) + 2.0 end },
    { id="precision", name="稳定器",      icon="📐", rarity=2, tags={"crit"}, baseWeight=22,
      desc="散布-30%",
      effect=function(p) p.weapon.spread = (p.weapon.spread or 0.1) * 0.7 end },
    { id="execute",   name="处决",        icon="⚔️", rarity=3, tags={"crit"}, baseWeight=12,
      desc="对HP<20%的敌人必定暴击",
      effect=function(p) p.executeThresh = 0.20 end },
    { id="sniper_scope",name="狙击镜",    icon="🔭", rarity=3, tags={"crit"}, baseWeight=12,
      desc="散布-50%，伤害+15%",
      effect=function(p)
          p.weapon.spread = (p.weapon.spread or 0.1) * 0.50
          p.weapon.damage = math.floor(p.weapon.damage * 1.15 + 0.5)
      end },
    { id="mark_target",name="弱点标记",  icon="📍", rarity=3, tags={"crit"}, baseWeight=10,
      desc="连续命中同一敌人3次后，暴击率+50%",
      effect=function(p) p.markTarget = true end },

    -- ── ✨ 特效失控（8张）────────────────────────────────────────
    { id="bounce_1",  name="跳弹",        icon="💫", rarity=3, tags={"chaos"}, baseWeight=15,
      desc="子弹弹射1次",
      effect=function(p) p.bounceCount = (p.bounceCount or 0) + 1 end },
    { id="bounce_2",  name="弹射链",      icon="💫", rarity=4, tags={"chaos"}, baseWeight=8,
      desc="子弹弹射+2次",
      effect=function(p) p.bounceCount = (p.bounceCount or 0) + 2 end },
    { id="explode_1", name="爆破弹",      icon="💥", rarity=3, tags={"chaos"}, baseWeight=12,
      desc="命中产生小爆炸",
      effect=function(p) p.hasExplosion = true; p.explosionRadius = (p.explosionRadius or 0) + 40 end },
    { id="explode_2", name="地狱火",      icon="🔥", rarity=3, tags={"chaos"}, baseWeight=10,
      desc="爆炸范围+50%",
      effect=function(p) p.explosionRadius = math.floor((p.explosionRadius or 40) * 1.5 + 0.5) end },
    { id="ls_1",      name="吸血弹头",    icon="🩸", rarity=4, tags={"chaos"}, baseWeight=10,
      desc="击杀回复3%HP",
      effect=function(p) p.hasLifesteal = true; p.lifestealPct = (p.lifestealPct or 0) + 0.03 end },
    { id="ls_2",      name="血祭",        icon="🩸", rarity=4, tags={"chaos"}, baseWeight=6,
      desc="击杀回复5%HP",
      effect=function(p) p.hasLifesteal = true; p.lifestealPct = (p.lifestealPct or 0) + 0.05 end },
    { id="lightning", name="闪电链",      icon="⚡", rarity=4, tags={"chaos"}, baseWeight=7,
      desc="子弹有15%概率触发连锁闪电",
      effect=function(p) p.chainLightning = true; p.chainChance = (p.chainChance or 0) + 0.15 end },
    { id="chaos_mag", name="混乱弹夹",   icon="🎲", rarity=3, tags={"chaos"}, baseWeight=9,
      desc="每次换弹完成后随机触发一种特效（弹射/爆炸/吸血），持续8秒",
      effect=function(p) p.randomOnReload = true end },

    -- ── 🔪 一刀流（8张，删除 knife_dmg_1 / knife_charge）──────────
    { id="knife_dmg_2",  name="开刃",       icon="🗡️", rarity=2, tags={"knife"}, baseWeight=30,
      desc="近战伤害+100%",
      effect=function(p) p.knife.damage = math.floor(p.knife.damage * 2.0 + 0.5) end },
    { id="knife_spd_1",  name="轻量化刀柄", icon="🗡️", rarity=1, tags={"knife"}, baseWeight=40,
      desc="攻速+20%（近战与射击共享）",
      effect=function(p)
          if p.knife then p.knife.fireRate = math.max(0.05, p.knife.fireRate * 0.8) end
          p.weapon.fireRate = math.max(0.05, p.weapon.fireRate * 0.8)
      end },
    { id="knife_range",  name="延展刀刃",   icon="🗡️", rarity=2, tags={"knife"}, baseWeight=30,
      desc="近战攻击距离+50%",
      effect=function(p) p.knife.meleeRange = math.floor((p.knife.meleeRange or 62) * 1.5 + 0.5) end },
    { id="knife_ls",     name="嗜血",       icon="🩸", rarity=2, tags={"knife"}, baseWeight=20,
      desc="近战击杀回复10%HP",
      effect=function(p) p.knifeHealOnKill = (p.knifeHealOnKill or 0) + 0.10 end },
    { id="knife_aoe",    name="横扫",       icon="💫", rarity=3, tags={"knife"}, baseWeight=15,
      desc="近战攻击同时伤害周围所有敌人",
      effect=function(p) p.knifeAoe = true; p.knifeAoeRadius = 60 end },
    { id="knife_parry",  name="切子弹",     icon="🌀", rarity=2, tags={"knife"}, baseWeight=25,
      desc="近战攻击可以砍掉飞行中的敌方子弹",
      effect=function(p) p.knifeParry = true end },
    { id="knife_parry_2",name="弹反",       icon="🔄", rarity=3, tags={"knife"}, baseWeight=15,
      desc="砍掉的子弹反弹回敌人方向",
      effect=function(p) p.knifeParry = true; p.knifeReflect = true end },
    { id="knife_parry_3",name="刀锋风暴",   icon="🌪️", rarity=4, tags={"knife","agile"}, baseWeight=8,
      desc="砍掉子弹后3秒内攻速翻倍",
      effect=function(p) p.knifeParry = true; p.knifeRageOnParry = true end },

    -- ── ⚡ 电击（8张）────────────────────────────────────────────
    { id="magnetic_storm",   name="磁暴电涌",   icon="⚡", rarity=2, tags={"electric"}, baseWeight=30,
      desc="暴击时在目标处落下雷电",
      effect=function(p) p.electricStorm = true end },
    { id="fighting_spirit",  name="格斗之魂",   icon="💢", rarity=1, tags={"electric"}, baseWeight=50,
      desc="每10次攻击必定暴击",
      effect=function(p) p.guaranteedCritEvery = 10 end },
    { id="high_voltage",     name="高压电击",   icon="⚡", rarity=2, tags={"electric"}, baseWeight=22,
      desc="雷电命中后跳跃至附近一个敌人，每次跳跃伤害递减15%",
      effect=function(p) p.elecChain = true; p.elecChainDecay = 0.85 end },
    { id="shock_infusion",   name="感电渗透",   icon="🔵", rarity=3, tags={"electric"}, baseWeight=15,
      desc="每层感电使目标受到的雷电伤害+20%",
      effect=function(p) p.shockStackBonus = (p.shockStackBonus or 0) + 0.2 end },
    { id="double_shot_elec", name="双重射击",   icon="🔫", rarity=3, tags={"electric"}, baseWeight=18,
      desc="开火时额外发射一枚子弹（伤害减半）",
      effect=function(p) p.doubleShot = true end },
    { id="charge_bomb",      name="电荷炸弹",   icon="💥", rarity=3, tags={"electric"}, baseWeight=12,
      desc="目标感电层数达到5层时爆炸，造成范围雷电伤害",
      effect=function(p) p.shockDetonate = true; p.shockDetonateAt = 5 end },
    { id="field_accel",      name="电场加速",   icon="💨", rarity=1, tags={"electric"}, baseWeight=35,
      desc="每触发一次雷电效果，移速提升5%，持续2秒",
      effect=function(p) p.electricSpeedBoost = (p.electricSpeedBoost or 0) + 0.05 end },
    { id="static_charge",    name="静电充能",   icon="⚡", rarity=2, tags={"electric"}, baseWeight=20,
      desc="雷电每跳跃一次，伤害递增10%",
      effect=function(p) p.chainRampUp = (p.chainRampUp or 0) + 0.1 end },

    -- ── 🔧 辅助类（改变三选一规则本身）─────────────────────────
    { id="assist_reroll",    name="重选",    icon="🔁", rarity=1, tags={"assist"}, baseWeight=15,
      desc="本次三选一可刷新一次",
      effect=function(p) end },   -- 由 main.lua 逻辑层处理
    { id="assist_reroll_2",  name="两次重选",icon="🔁", rarity=2, tags={"assist"}, baseWeight=10,
      desc="获得2次重选机会（本局有效）",
      effect=function(p) p.assistRerolls = (p.assistRerolls or 0) + 2 end },
    { id="assist_pick2",     name="我全都要",icon="✋", rarity=3, tags={"assist"}, baseWeight=8,
      desc="本次三个全选",
      effect=function(p) end },   -- 由 main.lua 逻辑层处理
    { id="assist_rarity_up", name="品质提升",icon="⬆️", rarity=3, tags={"assist"}, baseWeight=6,
      desc="本次三选一全升一级稀有度",
      effect=function(p) end },   -- 由 main.lua 逻辑层处理
    { id="assist_remove",    name="排除",    icon="❌", rarity=2, tags={"assist"}, baseWeight=5,
      desc="排除一个流派（本局不再出现）",
      effect=function(p) end },   -- 由 main.lua 逻辑层处理
    { id="assist_choice_4",  name="四选一",  icon="4️⃣", rarity=2, tags={"assist"}, baseWeight=8,
      desc="下次三选一变成四选一",
      effect=function(p) end },  -- 由 main.lua 负责更新 buildState.nextPickCount
}

-- ============================================================================
-- 五、BuildState
-- ============================================================================

--- 新建一份 BuildState（每局开始时调用一次）
--- @return table
function M.NewBuildState()
    return {
        chosen             = {},   -- 已选奖励列表（完整 item table）
        counts             = {},   -- 各流派层数 { firepower=3, agile=1, ... }
        activeThresholds   = {},   -- 已激活的阈值 effect 字符串集合 { [eff]=true }
        activeSynergies    = {},   -- 已激活的联动 id 字符串集合 { [id]=true }
        consecutiveNoEpic  = 0,    -- 连续未出史诗/传说的次数（保底计数器）
        totalPicks         = 0,    -- 已选总次数
        pendingNotifications = {},  -- 待显示的通知列表 { {text, timer} }
        excludedTags       = {},   -- 被"排除"辅助牌封禁的流派集合 { [tag]=true }
        nextPickCount      = 3,    -- 下次三选一数量（默认3，四选一牌改为4）
    }
end

-- 内部：权重调整（已有流派加成 + 关联流派加成）
local RELATED_PATHS = {
    firepower = { "chaos", "crit", "electric" },
    tank      = { "firepower", "knife" },
    agile     = { "tank", "knife", "electric" },
    crit      = { "firepower", "knife", "electric" },
    chaos     = { "firepower", "crit", "electric" },
    knife     = { "agile", "tank", "crit" },
    electric  = { "firepower", "chaos", "crit", "agile" },
}

local function adjustWeight(item, counts)
    local w = item.baseWeight or 50
    -- 已有流派 +30%/层
    for tag, cnt in pairs(counts) do
        if item.tags then
            for _, t in ipairs(item.tags) do
                if t == tag then w = w * (1 + cnt * 0.3) end
            end
        end
    end
    -- 关联流派 +10%/层（鼓励混搭）
    for tag, cnt in pairs(counts) do
        if cnt > 0 and RELATED_PATHS[tag] then
            for _, rt in ipairs(RELATED_PATHS[tag]) do
                if item.tags then
                    for _, t in ipairs(item.tags) do
                        if t == rt then w = w * (1 + cnt * 0.1) end
                    end
                end
            end
        end
    end
    return w
end

-- 内部：检查阈值突破，新触发时立即 apply 到 player
local function checkThresholds(bs, player)
    for path, levels in pairs(THRESHOLDS) do
        local level = bs.counts[path] or 0
        for need, data in pairs(levels) do
            if level >= need and not bs.activeThresholds[data.effect] then
                bs.activeThresholds[data.effect] = true
                -- 立即执行效果
                if data.apply and player then
                    data.apply(player)
                end
                table.insert(bs.pendingNotifications, {
                    text  = "⚡ 阈值突破：" .. data.name .. " — " .. data.desc,
                    timer = 4.0,
                    color = { 255, 220, 60 },
                })
            end
        end
    end
end

-- 内部：检查联动解锁，新触发时立即 apply 到 player
local function checkSynergies(bs, player)
    for _, synergy in ipairs(SYNERGIES) do
        if not bs.activeSynergies[synergy.id] then
            local met = true
            for tag, need in pairs(synergy.require) do
                if (bs.counts[tag] or 0) < need then met = false; break end
            end
            if met then
                bs.activeSynergies[synergy.id] = true
                -- 立即执行效果
                if synergy.apply and player then
                    synergy.apply(player)
                end
                table.insert(bs.pendingNotifications, {
                    text  = "✨ 联动解锁：" .. synergy.icon .. synergy.name .. " — " .. synergy.desc,
                    timer = 4.5,
                    color = { 168, 85, 247 },
                })
            end
        end
    end
end

--- 玩家选了一个奖励后调用：更新 BuildState、执行效果
--- @param bs table BuildState
--- @param item table 选中的奖励条目
--- @param player table 玩家对象
function M.Pick(bs, item, player)
    table.insert(bs.chosen, item)
    bs.totalPicks = bs.totalPicks + 1
    -- 累计流派层数
    if item.tags then
        for _, tag in ipairs(item.tags) do
            bs.counts[tag] = (bs.counts[tag] or 0) + 1
        end
    end
    -- 保底计数
    if item.rarity >= 3 then
        bs.consecutiveNoEpic = 0
    else
        bs.consecutiveNoEpic = bs.consecutiveNoEpic + 1
    end
    -- 检查阈值/联动（传入 player 以便立即执行 apply）
    checkThresholds(bs, player)
    checkSynergies(bs, player)
    -- 执行效果
    if item.effect then item.effect(player) end
end

--- 兼容旧接口（main.lua 当前还在调用 Reward.Select）
--- @param bs table BuildState
--- @param item table
--- @param player table
function M.Select(bs, item, player)
    M.Pick(bs, item, player)
end

-- ============================================================================
-- 六、生成候选选项 Generate(buildState, pool?, count?)
-- ============================================================================

-- 内部：加权随机选一个稀有度（1~4）
local function pickRarity(consecutiveNoEpic, floor)
    floor = floor or 1
    -- 基础权重：白(1) 绿(2) 紫(3) 金(4)
    -- 楼层越高，绿/紫/金概率越大
    -- floor 1~20 线性插值：每层绿+1.5, 紫+1.2, 金+0.6，白-3.3
    local floorBonus = math.max(0, floor - 1)  -- 0~19
    local whiteW  = math.max(10, 60 - floorBonus * 2.5)
    local greenW  = 30 + floorBonus * 1.2
    local purpleW = 8  + floorBonus * 1.0
    local legendW = 2  + floorBonus * 0.5
    -- 保底机制叠加
    if consecutiveNoEpic >= 3 then legendW = legendW + 8  end
    if consecutiveNoEpic >= 5 then legendW = legendW + 20 end
    local weights = { whiteW, greenW, purpleW, legendW }
    local total = 0
    for _, w in ipairs(weights) do total = total + w end
    local roll = math.random() * total
    for i, w in ipairs(weights) do
        roll = roll - w
        if roll <= 0 then return i end
    end
    return 4
end

--- 生成 count 个候选奖励（默认3个）
--- 每个候选：先按保底机制抽稀有度，再从该稀有度内按 Build 权重取最优的一个
--- @param bs table BuildState
--- @param pool table|nil 选项池（默认 M.POOL）
--- @param count number|nil 候选数（默认 bs.nextPickCount 或 3）
--- @return table choices 候选列表（item table 的数组）
function M.Generate(bs, pool, count)
    pool  = pool  or M.POOL
    count = count or (bs.nextPickCount or 3)

    -- 过滤被排除的流派
    local filtered = {}
    for _, item in ipairs(pool) do
        local excluded = false
        if item.tags and next(bs.excludedTags) then
            for _, tag in ipairs(item.tags) do
                if bs.excludedTags[tag] then excluded = true; break end
            end
        end
        if not excluded then table.insert(filtered, item) end
    end

    -- 已选过的 id 集合（本局已选过的卡完全不再出现）
    local chosenIds = {}
    for _, c in ipairs(bs.chosen) do chosenIds[c.id] = true end

    local choices = {}
    local usedIds = {}   -- 本次三选一内不重复

    for _ = 1, count do
        local rarity = pickRarity(bs.consecutiveNoEpic, bs.floor)

        -- 候选：该稀有度 + 本次未用 + 本局未选过
        local candidates = {}
        for _, item in ipairs(filtered) do
            if item.rarity == rarity and not usedIds[item.id] and not chosenIds[item.id] then
                table.insert(candidates, item)
            end
        end
        -- 该稀有度无候选则降级（仍排除已选过的）
        if #candidates == 0 then
            for _, item in ipairs(filtered) do
                if not usedIds[item.id] and not chosenIds[item.id] then
                    table.insert(candidates, item)
                end
            end
        end
        if #candidates == 0 then break end

        -- 按 Build 权重加权随机抽取（非贪心，保留随机性）
        local weightedList = {}
        local totalW = 0
        for _, item in ipairs(candidates) do
            local w = adjustWeight(item, bs.counts)
            w = math.max(w, 0.01)
            table.insert(weightedList, { item = item, w = w })
            totalW = totalW + w
        end
        local roll = math.random() * totalW
        local best = nil
        for _, entry in ipairs(weightedList) do
            roll = roll - entry.w
            if roll <= 0 then best = entry.item; break end
        end
        if not best then best = weightedList[#weightedList].item end

        if best then
            table.insert(choices, best)
            usedIds[best.id] = true
        end
    end

    return choices
end

--- 根据指定的稀有度列表生成卡片（用于"全升一级稀有度"效果）
--- @param bs table BuildState
--- @param rarities table 稀有度数组，如 {2, 2, 3}
--- @param excludeIds table|nil 需要排除的卡片 id 集合（避免和升级前重复）
function M.GenerateWithRarities(bs, rarities, excludeIds)
    local pool = M.POOL
    -- 过滤被排除的流派
    local filtered = {}
    for _, item in ipairs(pool) do
        local excluded = false
        if item.tags and next(bs.excludedTags) then
            for _, tag in ipairs(item.tags) do
                if bs.excludedTags[tag] then excluded = true; break end
            end
        end
        if not excluded then table.insert(filtered, item) end
    end

    -- 已选过的 id 集合
    local chosenIds = {}
    for _, c in ipairs(bs.chosen) do chosenIds[c.id] = true end
    if excludeIds then
        for id, _ in pairs(excludeIds) do chosenIds[id] = true end
    end

    local choices = {}
    local usedIds = {}

    for _, rarity in ipairs(rarities) do
        -- 候选：该稀有度 + 本次未用 + 本局未选过
        local candidates = {}
        for _, item in ipairs(filtered) do
            if item.rarity == rarity and not usedIds[item.id] and not chosenIds[item.id] then
                -- 排除辅助卡（assist 标签，避免升级后又出现辅助卡）
                local isAssist = false
                if item.tags then
                    for _, t in ipairs(item.tags) do
                        if t == "assist" then isAssist = true; break end
                    end
                end
                if not isAssist then
                    table.insert(candidates, item)
                end
            end
        end
        -- 该稀有度无候选则降级查找
        if #candidates == 0 then
            for _, item in ipairs(filtered) do
                if not usedIds[item.id] and not chosenIds[item.id] then
                    local isAssist = false
                    if item.tags then
                        for _, t in ipairs(item.tags) do
                            if t == "assist" then isAssist = true; break end
                        end
                    end
                    if not isAssist then
                        table.insert(candidates, item)
                    end
                end
            end
        end
        if #candidates == 0 then break end

        -- 按 Build 权重加权随机
        local weightedList = {}
        local totalW = 0
        for _, item in ipairs(candidates) do
            local w = adjustWeight(item, bs.counts)
            w = math.max(w, 0.01)
            table.insert(weightedList, { item = item, w = w })
            totalW = totalW + w
        end
        local roll = math.random() * totalW
        local best = nil
        for _, entry in ipairs(weightedList) do
            roll = roll - entry.w
            if roll <= 0 then best = entry.item; break end
        end
        if not best then best = weightedList[#weightedList].item end

        if best then
            table.insert(choices, best)
            usedIds[best.id] = true
        end
    end

    return choices
end

-- ============================================================================
-- 七、辅助：弹出待处理通知（每帧由 main.lua 调用）
-- 返回第一条未显示通知（并移除），或 nil
-- ============================================================================
function M.PopNotification(bs)
    if #bs.pendingNotifications > 0 then
        return table.remove(bs.pendingNotifications, 1)
    end
    return nil
end

return M
