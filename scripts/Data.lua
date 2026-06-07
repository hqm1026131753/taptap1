-- ============================================================================
-- Data.lua — 游戏数据表（武器/装备/战利品/消耗品/敌人配置）
-- ============================================================================
local M = {}

-- ----------------------------------------------------------------------------
-- 武器表（18种，对齐设计文档）
-- ammoType: "light"(手枪/冲锋枪) / "medium"(步枪/机枪) / "heavy"(霰弹枪) / "sniper"(狙击枪)
-- slot: "secondary"(副武器1×2) / "primary"(主武器1×3+)
-- fireRate: 两发间隔(s)  spread: 散布(rad)  reloadTime: 换弹(s)
-- pellets: 弹片数（霰弹专用）  reloadPerShell: 单发装填（M870）
-- ----------------------------------------------------------------------------
M.WEAPONS = {
    -- 手枪（副武器，1×2）— 使用轻型弹  [伤害已削弱30%]
    Glock       = { name="Glock 17",   icon="\xF0\x9F\x94\xAB", damage=8,  fireRate=0.28, spread=0.14, magSize=17, reloadTime=0.67, ammoType="light",   slot="secondary", rarity=1, value=200  },
    M1911       = { name="M1911",      icon="\xF0\x9F\x94\xAB", damage=13, fireRate=0.17, spread=0.10, magSize=7,  reloadTime=0.58, ammoType="light",   slot="secondary", rarity=2, value=350  },
    DesertEagle = { name="\xE6\xB2\x99\xE6\xBC\xA0\xE4\xB9\x8B\xE9\xB9\xB0", icon="\xF0\x9F\x94\xAB", damage=25, fireRate=0.27, spread=0.08, magSize=7,  reloadTime=0.83, ammoType="light",   slot="secondary", rarity=4, value=700  },
    G18         = { name="G18",        icon="\xF0\x9F\x94\xAB", damage=7,  fireRate=0.05, spread=0.22, magSize=18, reloadTime=0.75, ammoType="light",   slot="secondary", rarity=3, value=400  },
    -- 冲锋枪（主武器，1×3）— 使用轻型弹  [伤害已削弱30%]
    MP5         = { name="MP5",        icon="\xF0\x9F\x94\xAB", damage=9,  fireRate=0.07, spread=0.14, magSize=30, reloadTime=0.83, ammoType="light",   slot="primary",   rarity=2, value=400  },
    UZI         = { name="UZI",        icon="\xF0\x9F\x94\xAB", damage=8,  fireRate=0.05, spread=0.20, magSize=25, reloadTime=0.58, ammoType="light",   slot="primary",   rarity=2, value=350  },
    MP7         = { name="MP7",        icon="\xF0\x9F\x94\xAB", damage=10, fireRate=0.07, spread=0.12, magSize=40, reloadTime=0.75, ammoType="light",   slot="primary",   rarity=3, value=500  },
    P90         = { name="P90",        icon="\xF0\x9F\x94\xAB", damage=10, fireRate=0.05, spread=0.15, magSize=50, reloadTime=0.92, ammoType="light",   slot="primary",   rarity=4, value=650  },
    -- 步枪（主武器，1×3）— 使用中型弹  [伤害已削弱30%]
    M16         = { name="M16",        icon="\xF0\x9F\x94\xAB", damage=20, fireRate=0.15, spread=0.06, magSize=20, reloadTime=0.83, ammoType="medium",  slot="primary",   rarity=3, value=600  },
    AKM         = { name="AKM",        icon="\xF0\x9F\x94\xAB", damage=17, fireRate=0.12, spread=0.09, magSize=30, reloadTime=0.92, ammoType="medium",  slot="primary",   rarity=3, value=550  },
    AUG         = { name="AUG",        icon="\xF0\x9F\x94\xAB", damage=15, fireRate=0.10, spread=0.07, magSize=30, reloadTime=0.83, ammoType="medium",  slot="primary",   rarity=4, value=800  },
    -- 霰弹枪（主武器，1×4）— 使用重型弹  [伤害已削弱]
    M870        = { name="M870",       icon="\xF0\x9F\x94\xAB", damage=15, fireRate=0.23, spread=0.35, magSize=5,  reloadTime=0.25, ammoType="heavy",   slot="primary",   rarity=3, value=500,  pellets=5, reloadPerShell=true },
    M1014       = { name="M1014",      icon="\xF0\x9F\x94\xAB", damage=11, fireRate=0.17, spread=0.33, magSize=8,  reloadTime=1.00, ammoType="heavy",   slot="primary",   rarity=4, value=700,  pellets=6 },
    -- 狙击枪（主武器，1×5）— 使用狙击弹  [保持原伤害]
    AWM         = { name="AWM",        icon="\xF0\x9F\x94\xAB", damage=80, fireRate=0.55, spread=0.03, magSize=5,  reloadTime=1.00, ammoType="sniper",  slot="primary",   rarity=5, value=1200 },
    R93         = { name="R93",        icon="\xF0\x9F\x94\xAB", damage=70, fireRate=0.45, spread=0.04, magSize=5,  reloadTime=0.92, ammoType="sniper",  slot="primary",   rarity=5, value=1300 },
    -- 机枪（主武器，1×4）— 使用中型弹  [伤害已削弱30%]
    PKM         = { name="PKM",        icon="\xF0\x9F\x94\xAB", damage=14, fireRate=0.08, spread=0.16, magSize=100,reloadTime=2.00, ammoType="medium",  slot="primary",   rarity=4, value=900  },
    M250        = { name="M250",       icon="\xF0\x9F\x94\xAB", damage=15, fireRate=0.10, spread=0.12, magSize=75, reloadTime=1.67, ammoType="medium",  slot="primary",   rarity=5, value=1100 },
}
M.WEAPON_KEYS = {
    "Glock","M1911","DesertEagle","G18",
    "MP5","UZI","MP7","P90",
    "M16","AKM","AUG",
    "M870","M1014",
    "AWM","R93",
    "PKM","M250",
}

-- 按稀有度分桶（1~5）
M.WEAPONS_BY_RARITY = {}
for r = 1, 5 do M.WEAPONS_BY_RARITY[r] = {} end
for _, key in ipairs(M.WEAPON_KEYS) do
    local w = M.WEAPONS[key]
    w.key = key
    -- 初始弹药 = 满弹匣
    w.ammo    = w.magSize
    w.maxAmmo = w.magSize
    table.insert(M.WEAPONS_BY_RARITY[w.rarity], key)
end

-- ----------------------------------------------------------------------------
-- 弹药类型表（弹药包补充数量）
-- 4种弹药：light(手枪/冲锋枪) / medium(步枪/机枪) / heavy(霰弹枪) / sniper(狙击枪)
-- ----------------------------------------------------------------------------
M.AMMO_TYPES = {
    light  = { name="\xE8\xBD\xBB\xE5\x9E\x8B\xE5\xBC\xB9",  count=20, icon="\xF0\x9F\x93\xA6", rarity=1, value=20  },
    medium = { name="\xE4\xB8\xAD\xE5\x9E\x8B\xE5\xBC\xB9",  count=15, icon="\xF0\x9F\x93\xA6", rarity=1, value=30  },
    heavy  = { name="\xE9\x87\x8D\xE5\x9E\x8B\xE5\xBC\xB9",  count=8,  icon="\xF0\x9F\x93\xA6", rarity=1, value=35  },
    sniper = { name="\xE7\x8B\x99\xE5\x87\xBB\xE5\xBC\xB9",  count=5,  icon="\xF0\x9F\x93\xA6", rarity=2, value=50  },
}

-- ----------------------------------------------------------------------------
-- 装备表（对齐文档，加入 durability 耐久值）
-- 减伤公式：实际伤害 = 原伤 × (1 - armor/(armor+50))
-- 耐久消耗：每次被击中 -= 武器伤害 × 0.5
-- ----------------------------------------------------------------------------
M.HELMETS = {
    { id="cap",       name="\xE6\xA3\x92\xE7\x90\x83\xE5\xB8\xBD",     icon="\xF0\x9F\xA7\xA2", armor=3,  durability=20,  maxDurability=20,  rarity=1, value=30  },
    { id="helm_light",name="\xE9\x98\xB2\xE5\xBC\xB9\xE5\xA4\xB4\xE7\x9B\x94",   icon="\xE2\x9B\x91\xEF\xB8\x8F",  armor=20, durability=80,  maxDurability=80,  rarity=2, value=200 },
    { id="helm_heavy",name="\xE9\x87\x8D\xE5\x9E\x8B\xE5\xA4\xB4\xE7\x9B\x94",   icon="\xF0\x9F\xAA\x96",  armor=35, durability=120, maxDurability=120, rarity=3, value=500 },
    { id="helm_full", name="\xE5\x86\x9B\xE7\x94\xA8\xE5\x85\xA8\xE7\xBD\xA9\xE7\x9B\x94", icon="\xF0\x9F\xAA\x96",  armor=50, durability=150, maxDurability=150, rarity=4, value=1000 },
}

M.ARMORS = {
    { id="armor_tact",   name="战术背心",       icon="🛡️", armor=10, durability=40,  maxDurability=40,  rarity=1, value=80   },
    { id="armor_light",  name="轻型防弹衣",     icon="🦺", armor=20, durability=60,  maxDurability=60,  rarity=2, value=200  },
    { id="armor_medium", name="中型防弹衣",     icon="🛡️", armor=30, durability=120, maxDurability=120, rarity=3, value=450  },
    { id="armor_heavy",  name="重型防弹衣",     icon="🛡️", armor=45, durability=180, maxDurability=180, rarity=4, value=800  },
    { id="armor_ceramic",name="复合陶瓷甲",     icon="🛡️", armor=60, durability=150, maxDurability=150, rarity=5, value=1500 },
}

-- 背包（无胸挂，背包兼顾储物功能）
-- bagW×bagH = 物品网格尺寸
M.BAGS = {
    { id="small",   name="\xE5\xB0\x8F\xE8\x83\x8C\xE5\x8C\x85",               icon="\xF0\x9F\x8E\x92", bagW=5, bagH=3, rarity=1, value=80   },
    { id="medium",  name="\xE4\xB8\xAD\xE5\x9E\x8B\xE8\x83\x8C\xE5\x8C\x85",           icon="\xF0\x9F\x8E\x92", bagW=6, bagH=4, rarity=2, value=200  },
    { id="large",   name="\xE5\xA4\xA7\xE5\x9E\x8B\xE5\x86\x9B\xE7\x94\xA8\xE8\x83\x8C\xE5\x8C\x85",       icon="\xF0\x9F\x8E\x92", bagW=7, bagH=5, rarity=3, value=500  },
    { id="medic",   name="\xE9\x87\x8E\xE6\x88\x98\xE5\x8C\xBB\xE7\x96\x97\xE8\x83\x8C\xE5\x8C\x85",   icon="\xF0\x9F\x8F\xA5", bagW=8, bagH=5, rarity=4, value=700  },
    { id="assault", name="\xE7\xA9\xBF\xE5\x87\xBB\xE8\x83\x8C\xE5\x8C\x85",           icon="\xF0\x9F\x8E\x92", bagW=7, bagH=7, rarity=5, value=1000 },
}

-- ----------------------------------------------------------------------------
-- 消耗品表（医疗 + 弹药包）
-- effectType: "heal" / "ammo"
-- healPct: 回复百分比（相对 maxHp）  useTime: 使用时间(s)
-- instant: true = 立即生效（止痛药/肾上腺素立即部分）
-- speedBoost / speedDuration: 肾上腺素加速 buff
-- ammoType / ammoCount: 弹药包补充
-- ----------------------------------------------------------------------------
M.CONSUMABLES = {
    -- 医疗品（全部可堆叠）
    { id="bandage",     name="\xE7\xBB\xB7\xE5\xB8\xA6",    icon="\xF0\x9F\xA9\xB9", img="image/物品/绷带-0039.png", healPct=0.15, useTime=1.5, rarity=1, value=30,  lw=1, lh=1, effectType="heal", stackable=true, maxStack=5 },
    { id="medkit",      name="\xE6\x80\xA5\xE6\x95\x91\xE5\x8C\x85",   icon="\xF0\x9F\xA9\xB9", healPct=0.30, useTime=3.5, rarity=2, value=80,  lw=1, lh=1, effectType="heal", stackable=true, maxStack=5 },
    { id="surgery_kit", name="\xE9\x87\x8E\xE6\x88\x98\xE6\x89\x8B\xE6\x9C\xAF\xE5\x8C\x85",icon="\xF0\x9F\x8F\xA5", healPct=0.60, useTime=6.0, rarity=3, value=200, lw=1, lh=1, effectType="heal", stackable=true, maxStack=5 },
    { id="painkiller",  name="\xE6\xAD\xA2\xE7\x97\x9B\xE8\x8D\xAF",  icon="\xF0\x9F\x92\x8A", healPct=0.20, useTime=2.0, rarity=2, value=60,  lw=1, lh=1, effectType="heal", stackable=true, maxStack=5 },
    { id="adrenaline",  name="\xE8\x82\xBE\xE4\xB8\x8A\xE8\x85\xBA\xE7\xB4\xA0",icon="\xF0\x9F\x92\x89", healPct=0.40, useTime=3.0, rarity=4, value=400, lw=1, lh=1, effectType="heal",
      speedBoost=1.3, speedDuration=5.0, stackable=true, maxStack=5 },
    -- 弹药包（4种，对应4种弹药类型，可堆叠）
    { id="ammo_light",  name="轻型弹 24发", icon="📦", ammoType="light",  ammoCount=24, rarity=1, value=20, lw=1, lh=1, effectType="ammo", stackable=true, maxStack=5 },
    { id="ammo_medium", name="中型弹 19发", icon="📦", ammoType="medium", ammoCount=19, rarity=1, value=30, lw=1, lh=1, effectType="ammo", stackable=true, maxStack=5 },
    { id="ammo_heavy",  name="重型弹 12发",  icon="📦", ammoType="heavy",  ammoCount=12, rarity=1, value=35, lw=1, lh=1, effectType="ammo", stackable=true, maxStack=5 },
    { id="ammo_sniper", name="狙击弹 9发",  icon="📦", ammoType="sniper", ammoCount=9,  rarity=2, value=50, lw=1, lh=1, effectType="ammo", stackable=true, maxStack=5 },
}
M.CONSUMABLE_BY_ID = {}
for _, c in ipairs(M.CONSUMABLES) do
    M.CONSUMABLE_BY_ID[c.id] = c
end
-- 按稀有度分桶
M.CONSUMABLES_BY_RARITY = {}
for r = 1, 5 do M.CONSUMABLES_BY_RARITY[r] = {} end
for i, c in ipairs(M.CONSUMABLES) do
    if c.rarity then table.insert(M.CONSUMABLES_BY_RARITY[c.rarity], i) end
end

-- ----------------------------------------------------------------------------
-- 战利品表（18种，5级稀有度）
-- ----------------------------------------------------------------------------
M.LOOT = {
    -- 1级 垃圾（可堆叠）
    { name="\xE7\xA0\xB4\xE5\xB8\x83",     icon="\xF0\x9F\xA7\xBB", img="image/物品/破布-0040.png", rarity=1, value=10,   type="junk",     lw=1, lh=1, stackable=true, maxStack=12 },
    { name="\xE5\xBA\x9F\xE9\x93\x81",     icon="\xE2\x9A\x99\xEF\xB8\x8F",  img="image/物品/废铁-0047.png", rarity=1, value=15,   type="junk",     lw=1, lh=1, stackable=true, maxStack=12 },
    { name="\xE6\x97\xA7\xE8\x9E\xBA\xE4\xB8\x9D",   icon="\xF0\x9F\x94\xA9", img="image/物品/钉子-0041.png", rarity=1, value=12,   type="junk",     lw=1, lh=1, stackable=true, maxStack=12 },
    { name="\xE7\x93\xB6\xE8\xA3\x85\xE6\xB0\xB4",   icon="\xF0\x9F\xA7\x83", img="image/物品/瓶装水-0042.png", rarity=1, value=25,   type="junk",     lw=1, lh=1, stackable=true, maxStack=12 },
    { name="电水壶",     icon="🫖", img="image/物品/电水壶-0017.png", rarity=1, value=30,   type="junk",     lw=1, lh=2, stackable=false },
    { name="3D眼镜",    icon="🕶️", img="image/物品/3d眼镜-0018.png", rarity=1, value=20,   type="junk",     lw=2, lh=1, stackable=false },
    { name="杂志",      icon="📖", img="image/物品/杂志-0031.png", rarity=1, value=18,   type="junk",     lw=2, lh=1, stackable=true, maxStack=12 },
    { name="雨衣",      icon="🧥", img="image/物品/雨衣-0057.png", rarity=1, value=35,   type="junk",     lw=1, lh=2, stackable=false },
    -- 2级 普通
    { name="\xE9\x87\x91\xE6\x88\x92\xE6\x8C\x87",   icon="\xF0\x9F\x92\x8D", img="image/物品/金戒指-0043.png", rarity=2, value=100,  type="valuable", lw=1, lh=1 },
    { name="\xE9\x93\xB6\xE9\xA1\xB9\xE9\x93\xBE",   icon="\xF0\x9F\x93\xBF", img="image/物品/银项链-0044.png", rarity=2, value=80,   type="valuable", lw=2, lh=2 },
    { name="\xE7\x94\xB5\xE5\xAD\x90\xE8\xA1\xA8",   icon="\xE2\x8C\x9A", img="image/物品/电子表-0045.png", rarity=2, value=70,   type="valuable", lw=1, lh=1 },
    { name="雨伞",      icon="☂️", img="image/物品/雨伞-0032.png", rarity=2, value=90,   type="valuable", lw=1, lh=3 },
    { name="金质指南针", icon="🧭", img="image/物品/金质指南针-0056.png", rarity=2, value=120,  type="valuable", lw=1, lh=1 },
    { name="照相机",    icon="📷", img="image/物品/照相机-0055.png", rarity=2, value=110,  type="valuable", lw=1, lh=1 },
    -- 3级 稀有
    { name="夜视仪",    icon="🥽", img="image/物品/夜视镜-0030.png", rarity=3, value=200,  type="valuable", lw=2, lh=1 },
    { name="小熊玩偶",  icon="🧸", img="image/物品/小熊玩偶-0050.png", rarity=3, value=180,  type="valuable", lw=1, lh=2 },
    { name="锡制酒壶",   icon="🫗", img="image/物品/锡制酒壶-0019.png", rarity=3, value=250,  type="valuable", lw=1, lh=1 },
    { name="\xE9\x87\x91\xE9\x93\xBE\xE5\xAD\x90",   icon="\xF0\x9F\x93\xBF", rarity=3, value=220,  type="valuable", lw=1, lh=1 },
    { name="\xE7\xBF\xA1\xE7\xBF\xa0\xE6\x89\x8B\xE9\x95\xAF", icon="\xF0\x9F\x92\x9A", img="image/物品/玉镯子-0024.png", rarity=3, value=280,  type="valuable", lw=1, lh=1 },
    { name="\xE5\x8F\xA4\xE8\x91\xA3\xE6\x80\x80\xE8\xA1\xA8", icon="\xE2\xB8\xB1\xEF\xB8\x8F", img="image/物品/古董怀表-0052.png", rarity=3, value=320,  type="valuable", lw=1, lh=2 },
    { name="\xE9\x87\x91\xE6\x9D\xA1",     icon="\xF0\x9F\xAA\x99", rarity=3, value=500,  type="valuable", lw=1, lh=2 },
    { name="\xE9\x92\xBB\xE7\x9F\xB3",     icon="\xF0\x9F\x92\x8E", img="image/物品/钻石-0053.png", rarity=3, value=600,  type="valuable", lw=1, lh=1 },
    -- 4级 史诗
    { name="\xE5\x8F\xA4\xE8\x91\xA3\xE8\x8A\xB1\xE7\x93\xB6", icon="\xF0\x9F\x8F\xBA", rarity=4, value=800,  type="valuable", lw=2, lh=2 },
    { name="\xE9\x87\x91\xE4\xBB\x9B\xE5\x83\x8F",   icon="\xF0\x9F\xAA\xB7", rarity=4, value=1200, type="valuable", lw=2, lh=2 },
    { name="名人字画·山水", icon="🖼️", img="image/物品/画1-0049.png", rarity=4, value=1500, type="valuable", lw=2, lh=2 },
    { name="名人字画·人物", icon="🖼️", img="image/物品/画2-0048.png", rarity=4, value=1500, type="valuable", lw=2, lh=2 },
    { name="\xE5\xAE\x9D\xE7\x9F\xB3\xE7\x8E\x8B\xE5\x86\xA0", icon="\xF0\x9F\x91\x91", rarity=4, value=2000, type="valuable", lw=2, lh=2 },
    -- 5级 传说
    { name="\xE9\x81\x97\xE7\x89\xA9\xE5\x9C\xA3\xE5\x99\xA8", icon="\xF0\x9F\x94\xAE", rarity=5, value=3000, type="valuable", lw=2, lh=2 },
    { name="VIP卡",     icon="💳", img="image/物品/VIP卡-0051.png", rarity=5, value=5000, type="valuable", lw=1, lh=1 },
    { name="非洲之星", icon="💎", img="image/物品/非洲之星-0028.png", rarity=5, value=8000, type="valuable", lw=1, lh=1 },
    -- 史莱姆专属掉落
    { name="史莱姆粘液", icon="🧪", rarity=2, value=45, type="slime_material", lw=1, lh=1, stackable=true, maxStack=12 },
}

M.LOOT_BY_RARITY = {}
for r = 1, 5 do M.LOOT_BY_RARITY[r] = {} end
for i, item in ipairs(M.LOOT) do
    table.insert(M.LOOT_BY_RARITY[item.rarity], i)
end

-- 稀有度颜色
M.RARITY_COLOR = {
    [1] = {180, 180, 180},
    [2] = {100, 220, 100},
    [3] = {80, 160, 255},
    [4] = {200, 80, 255},
    [5] = {220, 30, 30},
}

-- ----------------------------------------------------------------------------
-- 敌人模板（5种）+ 专属掉落表
-- dropTable: 覆盖默认箱子产出权重；每项 { type, weight }
-- type 可为 "loot"/"weapon"/"armor"/"helmet"/"rig"/"bag"/"consumable"/"ammo"
-- ----------------------------------------------------------------------------
M.ENEMY_TYPES = {
    scavenger = {
        name="\xE6\x8B\xBE\xE8\x8D\x92\xE7\x8C\xAB", hp=32, speed=60, damage=16, detectRange=180, fovAngle=120,
        dropRarity=1, color={200,180,140}, markColor={180,140,100}, reward=30,
        rangeMin=80, rangeMax=140,
        dropTable = {
            { type="loot",        weight=60 },
            { type="ammo",        weight=30 },
            { type="consumable",  weight=10 },
        },
    },
    patrol = {
        name="骷髅射手", hp=42, speed=72, damage=20, detectRange=220, fovAngle=100,
        dropRarity=2, color={140,160,200}, markColor={100,120,160}, reward=50,
        rangeMin=100, rangeMax=170,
        anims = {
            idle = {
                sheet = "image/小怪/骷髅射手/rika_b8802352.png",
                cols = 4, rows = 2, frames = 6,
                frameW = 256, frameH = 256, fps = 6,
            },
            walk = {
                sheet = "image/小怪/骷髅射手/rika_5d5001cd.png",
                cols = 4, rows = 2, frames = 8,
                frameW = 128, frameH = 128, fps = 8,
            },
            attack = {
                sheet = "image/小怪/骷髅射手/rika_6ce241bd.png",
                cols = 4, rows = 4, frames = 16,
                frameW = 128, frameH = 128, fps = 16,
            },
        },
        dropTable = {
            { type="loot",        weight=40 },
            { type="ammo",        weight=25 },
            { type="consumable",  weight=20 },
            { type="weapon",      weight=15 },
        },
    },
    sniper = {
        name="\xE7\x8B\x99\xE5\x87\xBB\xE7\x8C\xAB", hp=32, speed=36, damage=54, detectRange=320, fovAngle=60,
        dropRarity=3, color={80,80,90}, markColor={60,60,70}, reward=80,
        rangeMin=180, rangeMax=280,
        dropTable = {
            { type="loot",        weight=30 },
            { type="ammo",        weight=40 },  -- 狙击手多掉狙击弹
            { type="consumable",  weight=10 },
            { type="weapon",      weight=20 },
        },
    },
    guard = {
        name="\xE8\xAD\xA6\xE5\xBB\xBA\xE7\x8C\xAB", hp=63, speed=60, damage=30, detectRange=200, fovAngle=110,
        dropRarity=3, color={60,80,60}, markColor={40,60,40}, reward=100,
        rangeMin=90, rangeMax=150,
        dropTable = {
            { type="loot",        weight=25 },
            { type="ammo",        weight=20 },
            { type="consumable",  weight=15 },
            { type="weapon",      weight=20 },
            { type="armor",       weight=10 },
            { type="helmet",      weight=10 },
        },
    },
    mad = {
        name="暗影蝠", hp=46, speed=120, damage=10, detectRange=160, fovAngle=150,
        dropRarity=1, color={220,60,60}, markColor={180,40,40}, reward=20,
        isBat = true,  -- 标记：使用蝙蝠精灵表绘制
        batAnims = {
            idle = {
                sheet = "image/小怪/蝙蝠/rika_99dd5cba.png",
                cols = 4, rows = 3, frames = 10,
                frameW = 128, frameH = 128, fps = 6,
            },
            walk = {
                sheet = "image/小怪/蝙蝠/rika_469f659c.png",
                cols = 4, rows = 3, frames = 9,
                frameW = 128, frameH = 128, fps = 6,
            },
            attack = {
                sheet = "image/小怪/蝙蝠/rika_7ae1350e.png",
                cols = 4, rows = 2, frames = 7,
                frameW = 128, frameH = 128, fps = 12,
            },
        },
        dropTable = {
            { type="loot",        weight=80 },
            { type="ammo",        weight=20 },
        },
    },
    slime = {
        name="史莱姆", hp=46, speed=40, damage=14, detectRange=140, fovAngle=360,
        dropRarity=1, color={120,160,80}, markColor={80,120,50}, reward=20,
        isSlime = true,  -- 标记：使用 Slime 模块处理
        dropTable = {
            { type="loot",        weight=40 },
            { type="slime_mucus", weight=35 },
            { type="consumable",  weight=15 },
            { type="ammo",        weight=10 },
        },
    },
}
M.ENEMY_TYPE_KEYS = {"scavenger","patrol","sniper","guard","mad","slime"}

-- Boss 模板（4个，对应第5/10/15/20层）
M.BOSS_TYPES = {
    -- 第5层：铁甲猫骑士（首个Boss，技能型）[血量×2]
    cat_knight = {
        name="铁甲猫骑士", hp=840, speed=72, damage=18,
        attackInterval=999,  -- 不使用默认射击（技能系统管理）
        detectRange=999, fovAngle=360,
        dropRarity=3, color={80,80,90}, markColor={60,60,70},
        reward=350, isBoss=true,
        isCatKnight=true,  -- 标记使用专属Boss系统
        dropTable = {
            { type="loot",       weight=20 },
            { type="weapon",     weight=30 },
            { type="armor",      weight=20 },
            { type="helmet",     weight=15 },
            { type="consumable", weight=15 },
        },
    },
    -- 第10层：铁甲猫战锤（重甲巨锤，震地型）[血量×2]
    cat_hammer = {
        name="铁甲猫战锤", hp=1100, speed=60, damage=24,
        attackInterval=999,  -- 不使用默认射击（技能系统管理）
        detectRange=999, fovAngle=360,
        dropRarity=4, color={100,85,60}, markColor={80,65,40},
        reward=500, isBoss=true,
        isCatHammer=true,  -- 标记使用专属Boss2系统
        dropTable = {
            { type="weapon",     weight=30 },
            { type="armor",      weight=25 },
            { type="helmet",     weight=20 },
            { type="loot",       weight=15 },
            { type="consumable", weight=10 },
        },
    },
    -- 旧矿道守卫（保留兼容）[血量×2]
    mine_boss = {
        name="矿道守卫", hp=720, speed=64, damage=20,
        attackInterval=40,
        detectRange=999, fovAngle=360,
        dropRarity=3, color={160,130,80}, markColor={120,100,60},
        reward=300, isBoss=true,
        summonType="scavenger", summonInterval=3.0,
        enrageHpRatio=0.5, enrageSpeedMult=1.3,
        dropTable = {
            { type="loot",       weight=20 },
            { type="weapon",     weight=30 },
            { type="armor",      weight=20 },
            { type="helmet",     weight=15 },
            { type="consumable", weight=15 },
        },
    },
    -- 旧第10层洞穴之王（保留兼容）[血量×2]
    cave_boss = {
        name="洞穴之王", hp=960, speed=70, damage=26,
        attackInterval=35,
        detectRange=999, fovAngle=360,
        dropRarity=4, color={90,110,160}, markColor={60,80,120},
        reward=500, isBoss=true,
        summonType="mad", summonInterval=4.0,
        dropTable = {
            { type="weapon",     weight=35 },
            { type="armor",      weight=25 },
            { type="helmet",     weight=20 },
            { type="consumable", weight=10 },
            { type="loot",       weight=10 },
        },
    },
    -- 第15层：装甲机猫（重型装甲+盾+炮，技能型）[血量×2]
    armored_cat = {
        name="装甲机猫", hp=1400, speed=55, damage=28,
        attackInterval=999,  -- 不使用默认射击（技能系统管理）
        detectRange=999, fovAngle=360,
        dropRarity=5, color={60,70,90}, markColor={40,50,70},
        reward=800, isBoss=true,
        isArmoredCat=true,  -- 标记使用专属Boss3系统
        dropTable = {
            { type="weapon",     weight=35 },
            { type="armor",      weight=25 },
            { type="helmet",     weight=20 },
            { type="consumable", weight=10 },
            { type="loot",       weight=10 },
        },
    },
    -- 第20层：军帽领主 Captain Claw（最终Boss，九命猫复活）[血量×2]
    captain_claw = {
        name="军帽领主", hp=1800, speed=65, damage=35,
        attackInterval=999,  -- 不使用默认射击（技能系统管理）
        detectRange=999, fovAngle=360,
        dropRarity=5, color={100,50,130}, markColor={80,30,110},
        reward=0, isBoss=true,
        isCaptainClaw=true,  -- 标记使用专属Boss4系统
        dropTable = {
            { type="weapon",     weight=35 },
            { type="armor",      weight=25 },
            { type="helmet",     weight=20 },
            { type="consumable", weight=10 },
            { type="loot",       weight=10 },
        },
    },
    -- 旧第20层（保留兼容别名）
    final_boss = {
        name="地牢之底", hp=1800, speed=90, damage=40,
        attackInterval=25,
        detectRange=999, fovAngle=360,
        dropRarity=5, color={180,30,200}, markColor={140,20,160},
        reward=0, isBoss=true,
        phase2HpRatio=0.6, phase3HpRatio=0.3,
        dropTable = {
            { type="weapon",     weight=35 },
            { type="armor",      weight=25 },
            { type="helmet",     weight=20 },
            { type="consumable", weight=10 },
            { type="loot",       weight=10 },
        },
    },
    -- 兼容旧引用（保留别名）
    miniboss  = nil,  -- 下方动态赋值
    finalboss = nil,
}

-- 箱子产出概率权重（新增 consumable / ammo）
M.BOX_LOOT_TABLE = {
    { type="loot",        weight=35 },
    { type="consumable",  weight=15 },
    { type="ammo",        weight=10 },
    { type="weapon",      weight=15 },
    { type="armor",       weight=8  },
    { type="helmet",      weight=7  },
    { type="bag",         weight=10 },
}

-- ============================================================================
-- 工具函数
-- ============================================================================

-- 按权重随机选 type
function M.WeightedRandom(table_)
    local total = 0
    for _, entry in ipairs(table_) do total = total + entry.weight end
    local r = math.random() * total
    local acc = 0
    for _, entry in ipairs(table_) do
        acc = acc + entry.weight
        if r <= acc then return entry.type end
    end
    return table_[#table_].type
end

-- 随机战利品
function M.RandomLoot(maxRarity)
    maxRarity = maxRarity or 3
    local rWeights = {50, 30, 15, 4, 1}
    local pool, wpool = {}, {}
    for r = 1, maxRarity do
        for _, idx in ipairs(M.LOOT_BY_RARITY[r]) do
            table.insert(pool, idx)
            table.insert(wpool, rWeights[r])
        end
    end
    if #pool == 0 then return M.LOOT[1] end
    local total = 0
    for _, w in ipairs(wpool) do total = total + w end
    local roll = math.random() * total
    local acc = 0
    for i, w in ipairs(wpool) do
        acc = acc + w
        if roll <= acc then return M.LOOT[pool[i]] end
    end
    return M.LOOT[pool[1]]
end

-- 随机武器（返回含当前弹药的副本）
function M.RandomWeapon(maxRarity)
    maxRarity = maxRarity or 3
    local pool = {}
    for r = 1, maxRarity do
        for _, key in ipairs(M.WEAPONS_BY_RARITY[r]) do
            table.insert(pool, key)
        end
    end
    if #pool == 0 then pool = {"Glock"} end
    local key = pool[math.random(#pool)]
    local w = M.WEAPONS[key]
    return {
        key=key, name=w.name, icon=w.icon,
        damage=w.damage, fireRate=w.fireRate, spread=w.spread,
        rarity=w.rarity, value=w.value,
        ammo=w.magSize, maxAmmo=w.magSize,
        magSize=w.magSize, reloadTime=w.reloadTime,
        ammoType=w.ammoType, slot=w.slot,
        pellets=w.pellets, reloadPerShell=w.reloadPerShell,
    }
end

-- 随机装备（helmet/armor/rig/bag）
function M.RandomEquip(slot, maxRarity)
    maxRarity = maxRarity or 2
    local src
    if slot == "helmet" then src = M.HELMETS
    elseif slot == "armor" then src = M.ARMORS
    else                        src = M.BAGS end
    local pool = {}
    for _, item in ipairs(src) do
        if item.rarity <= maxRarity then table.insert(pool, item) end
    end
    if #pool == 0 then return src[1] end
    local item = pool[math.random(#pool)]
    local copy = {}
    for k, v in pairs(item) do copy[k] = v end
    copy.slot = slot
    return copy
end

-- 随机消耗品（医疗 or 弹药，指定最大稀有度）
function M.RandomConsumable(maxRarity)
    maxRarity = maxRarity or 2
    local pool = {}
    for _, c in ipairs(M.CONSUMABLES) do
        if c.rarity <= maxRarity then table.insert(pool, c) end
    end
    if #pool == 0 then return M.CONSUMABLES[1] end
    local c = pool[math.random(#pool)]
    local copy = {}
    for k, v in pairs(c) do copy[k] = v end
    return copy
end

-- 随机弹药包（优先与指定武器匹配）
function M.RandomAmmo(maxRarity, preferAmmoType)
    maxRarity = maxRarity or 2
    -- 优先匹配武器弹药类型
    if preferAmmoType then
        for _, c in ipairs(M.CONSUMABLES) do
            if c.effectType == "ammo" and c.ammoType == preferAmmoType and c.rarity <= maxRarity then
                local copy = {}; for k,v in pairs(c) do copy[k]=v end; return copy
            end
        end
    end
    local pool = {}
    for _, c in ipairs(M.CONSUMABLES) do
        if c.effectType == "ammo" and c.rarity <= maxRarity then table.insert(pool, c) end
    end
    if #pool == 0 then return M.CONSUMABLE_BY_ID["ammo_light"] end  -- 轻型弹兜底
    local c = pool[math.random(#pool)]
    local copy = {}; for k,v in pairs(c) do copy[k]=v end; return copy
end


-- ----------------------------------------------------------------------------
-- Boss别名兼容（旧代码用 miniboss/finalboss 的地方继续有效）
-- ----------------------------------------------------------------------------
M.BOSS_TYPES.miniboss  = M.BOSS_TYPES.mine_boss
M.BOSS_TYPES.finalboss = M.BOSS_TYPES.final_boss

-- 按层数返回对应 Boss key
function M.GetBossKey(floor)
    if floor == 5  then return "cat_knight" end
    if floor == 10 then return "cat_hammer" end
    if floor == 15 then return "armored_cat" end
    if floor == 20 then return "captain_claw" end
    return "cat_knight"
end

-- ----------------------------------------------------------------------------
-- 层数参数：普通掉落稀有度权重 {r1,r2,r3,r4,r5}，总和100
-- ----------------------------------------------------------------------------
function M.GetRarityWeights(floor)
    if floor <= 4  then return {61, 21, 10,  5,  3} end  -- r3=10% r4=5% r5=3%
    if floor <= 9  then return {17, 32, 26, 20,  5} end  -- r4=20% r5=5%
    if floor <= 14 then return { 4, 15, 25, 36, 20} end
    if floor <= 19 then return { 1,  4, 14, 31, 50} end
    return                     { 0,  0, 10, 30, 60}
end

-- Boss 宝箱稀有度权重（对应 rarity 2/3/4/5）
function M.GetBossChestWeights(floor)
    if floor == 5  then return {45, 30, 15, 10} end
    if floor == 10 then return { 0, 35, 35, 30} end
    if floor == 15 then return { 0,  0, 50, 50} end
    if floor == 20 then return { 0,  0, 20, 80} end
    return                     {45, 30, 15, 10}
end

-- 普通掉落：加权随机出一个 maxRarity 值（1~5）
function M.RollMaxRarity(floor)
    local w = M.GetRarityWeights(floor)
    local total = 0
    for _, v in ipairs(w) do total = total + v end
    local r = math.random() * total
    local acc = 0
    for i, v in ipairs(w) do
        acc = acc + v
        if r <= acc then return i end
    end
    return 5
end

-- Boss 宝箱：加权随机出一个 maxRarity（2~5）
function M.RollBossChestRarity(floor)
    local w = M.GetBossChestWeights(floor)
    local total = 0
    for _, v in ipairs(w) do total = total + v end
    local r = math.random() * total
    local acc = 0
    for i, v in ipairs(w) do
        acc = acc + v
        if r <= acc then return i + 1 end
    end
    return 5
end

-- ----------------------------------------------------------------------------
-- 层数参数：敌人倍率 / 精英概率 / Boss宝箱数
-- ----------------------------------------------------------------------------
function M.GetFloorParams(floor)
    local isBossFloor = (floor % 5 == 0)
    -- 前两层难度降低：第1关 -10%，第2关 -5%
    local earlyNerf = floor == 1 and 0.90 or (floor == 2 and 0.95 or 1.0)
    return {
        hpMult        = (1 + (floor - 1) * 0.07) * earlyNerf,
        speedMult     = math.min(1 + (floor - 1) * 0.015, 1.8),
        dmgMult       = (1 + (floor - 1) * 0.04) * earlyNerf,
        eliteChance   = isBossFloor and 0 or math.min(floor * 0.02, 0.5),
        bossChestCount = isBossFloor and (math.floor(floor / 5) + 2) or 0,
        isBossFloor   = isBossFloor,
    }
end

-- ----------------------------------------------------------------------------
-- 按层数返回战利品价值倍率（设计文档 §七 getLootValueMultiplier）
-- 用于 GenerateItem 时乘到 item.value 上，让深层物品更值钱
-- ----------------------------------------------------------------------------
function M.GetLootValueMult(floor)
    return 1.0
end

-- ----------------------------------------------------------------------------
-- 物品描述（Tooltip 用）—— 一句话简介
-- ----------------------------------------------------------------------------
M.ITEM_DESC = {
    -- 武器
    Glock       = "可靠的 9mm 手枪，后坐力小，适合新手",
    M1911       = "经典 .45 口径手枪，单发威力大",
    DesertEagle = "沙漠之鹰，近距离一击致命",
    G18         = "全自动手枪，弹幕压制利器",
    MP5         = "精准冲锋枪，中近距离全能",
    UZI         = "超高射速，弹药消耗极快",
    MP7         = "穿甲冲锋枪，弹匣容量大",
    P90         = "50发弹鼓，持续火力输出",
    M16         = "突击步枪，精度与伤害兼备",
    AKM         = "苏系突击步枪，火力凶猛",
    AUG         = "奥地利精准步枪，稳定可靠",
    M870        = "泵动霰弹枪，近距离毁灭性",
    M1014       = "半自动霰弹枪，连续输出",
    AWM         = "传说级狙击步枪，一枪一命",
    R93         = "栓动狙击步枪，弹道笔直",
    PKM         = "通用机枪，百发弹链持续压制",
    M250        = "轻量化机枪，移动中射击",
    Knife       = "贴身格斗刀，永不过时",
    -- 消耗品
    bandage     = "简易绷带，快速止血",
    medkit      = "急救包，恢复大量生命",
    surgery_kit = "野战手术包，几乎满血回复",
    painkiller  = "止痛药，缓解伤痛恢复少量血量",
    adrenaline  = "肾上腺素，回血并提升移速",
    ammo_light  = "9mm/5.7mm 轻型弹药补给",
    ammo_medium = "5.56/7.62mm 中型弹药补给",
    ammo_heavy  = "12号霰弹药补给",
    ammo_sniper = ".338/.300WM 狙击弹药补给",
    -- 头盔
    cap         = "棒球帽，聊胜于无",
    helm_light  = "防弹头盔，抵御流弹",
    helm_heavy  = "重型头盔，正面硬刚",
    helm_full   = "军用全罩盔，坚不可摧",
    -- 护甲
    armor_tact   = "战术背心，轻便灵活",
    armor_light  = "轻型防弹衣，基础防护",
    armor_medium = "中型防弹衣，均衡防护",
    armor_heavy  = "重型防弹衣，坦克般坚固",
    armor_ceramic= "复合陶瓷甲，顶级防御力但较脆弱",
    -- 背包
    small       = "小背包，勉强够用",
    medium      = "中型背包，日常搜刮标配",
    large       = "大型军用背包，装下一切",
    medic       = "野战医疗包，容量惊人",
    assault     = "穿击背包，为战斗而生",
    -- 杂物 / 战利品
    junk        = "没什么用的破烂，卖给商人换点钱",
    valuable    = "值钱的好东西，安全撤离后可换取丰厚报酬",
    slime_material = "史莱姆体内分泌的黏稠物质，据说是炼金术的重要材料",
}

--- 获取物品 Tooltip 信息
--- @param entry table 背包中的 entry（含 itype, data, name 等）
--- @return table|nil {title, stats:{}, desc:string, rarity:number}
function M.GetItemTooltip(entry)
    if not entry then return nil end
    local info = { title = entry.name or "???", stats = {}, desc = "", rarity = entry.rarity or 1 }

    if entry.itype == "weapon" then
        local d = entry.data
        if d then
            table.insert(info.stats, { label="伤害", value=tostring(d.damage or 0) .. (d.pellets and ("×"..d.pellets) or "") })
            table.insert(info.stats, { label="弹匣", value=tostring(d.ammo or 0).."/"..tostring(d.maxAmmo or d.magSize or 0) })
            table.insert(info.stats, { label="射速", value=string.format("%.0f发/s", 1/(d.fireRate or 0.2)) })
            table.insert(info.stats, { label="换弹", value=string.format("%.1fs", d.reloadTime or 1) })
            info.desc = M.ITEM_DESC[d.key] or ""
        end

    elseif entry.itype == "helmet" or entry.itype == "armor" then
        local d = entry.data or entry
        info.title = d.name or entry.name
        table.insert(info.stats, { label="护甲", value="+"..tostring(d.armor or 0) })
        local dur = d.durability or 0
        local maxDur = d.maxDurability or 1
        table.insert(info.stats, { label="耐久", value=tostring(dur).."/"..tostring(maxDur) })
        info.desc = M.ITEM_DESC[d.id] or ""

    elseif entry.itype == "bag" then
        local d = entry.data or entry
        info.title = d.name or entry.name
        table.insert(info.stats, { label="容量", value=tostring(d.bagW or 0).."×"..tostring(d.bagH or 0) })
        info.desc = M.ITEM_DESC[d.id] or ""

    elseif entry.itype == "consumable" then
        local d = entry.data or entry
        info.title = d.name or entry.name
        if d.effectType == "heal" then
            table.insert(info.stats, { label="回复", value=tostring(math.floor((d.healPct or 0)*100)).."% HP" })
            table.insert(info.stats, { label="用时", value=string.format("%.1fs", d.useTime or 1) })
            if d.speedBoost then
                table.insert(info.stats, { label="加速", value=string.format("%.0f%%×%.0fs", (d.speedBoost-1)*100, d.speedDuration or 0) })
            end
        elseif d.effectType == "ammo" then
            table.insert(info.stats, { label="弹药", value="+"..tostring(d.ammoCount or 0).." "..tostring(d.ammoType or "") })
        end
        info.desc = M.ITEM_DESC[d.id] or ""

    elseif entry.itype == "loot" then
        local d = entry.data or entry
        info.title = d.name or entry.name
        table.insert(info.stats, { label="价值", value="💰"..tostring(d.value or entry.value or 0) })
        local lootType = d.type or ""
        info.desc = M.ITEM_DESC[lootType] or ""
    end

    return info
end

return M
