-- ============================================================================
-- main.lua — 修勾大逃亡 · 主入口
-- 20层地牢 + 每5层小Boss + 第20层最终Boss + 三选一奖励系统
-- ============================================================================
---@diagnostic disable: redefined-local
local World      = require("World")
local Player     = require("Player")
local Enemy      = require("Enemy")
local Render     = require("Render")
local Reward     = require("Reward")
local Search     = require("Search")
local Stash      = require("Stash")
local Audio      = require("AudioManager")
local MobileHUD  = require("MobileHUD")
local Data       = require("Data")
local Dev        = require("DevSystem")
local Lighting   = require("Lighting")
local BattlePrepUI = require("BattlePrepUI")
local SkillTree    = require("SkillTree")
local SkillTreeUI  = require("SkillTreeUI")
local Boss4        = require("Boss4")

-- ----------------------------------------------------------------------------
-- 全局状态
-- ----------------------------------------------------------------------------
---@type userdata
local vg = nil

-- 游戏状态机：menu / hub / skill_tree / loadout / pick / playing / paused / reward / gameover / win
local STATE = "menu"

-- 暂停菜单悬停按钮 ("resume" / "menu" / nil)
local pauseHover = nil

-- 主菜单悬停按钮 ("start"/"volume"/"howto"/nil)
local menuHover = nil
-- Hub 主界面悬停 ("start_raid"/"back"/"skill"/"stash"/"showcase"/nil)
local hubHover = nil
-- 主菜单覆盖层：玩法介绍 / 音量设置
local showHowTo     = false
local howToScrollY   = 0       -- 玩法介绍滚动偏移
local howToDragY     = nil     -- 触摸拖动起始Y（nil=未拖动）
local howToDragStartScroll = 0 -- 拖动开始时的scrollY
local showVolumeMenu = false

-- 暂停菜单音量滑块拖动状态
-- target = "bgm"/"sfx"/nil（nil 表示未拖动）
local pauseDragState = { target = nil }

-- 玩家仓库（跨局持久，启动时尝试从本地存档恢复）
local stash = Stash.Load() or Stash.New()

-- 技能树持久状态
local skillTreeState = SkillTree.Load() or SkillTree.NewState()
-- 技能树 UI 交互状态
local skillTreeHover = nil  -- 当前悬停节点id
local skillTreeScrollY = 0  -- 技能树纵向滚动偏移
local skillTreeDrag = { active = false, touchId = nil, startY = 0, startScroll = 0, moved = false }

-- 战前准备界面状态
local loadoutLayout = nil   -- Render.GetLoadoutLayout() 缓存
local loadoutState  = {     -- 战前准备 UI 状态（传入 Render/HitTest）
    activeTab      = "sell",       -- "sell" | "buy"
    activeVendorId = "therapist",  -- 当前选中的商人
    loadoutItems   = {},           -- 从仓库取出、准备带入战局的物品列表
    hoverItemId    = nil,          -- 悬停高亮
    dragItem       = nil,          -- 正在拖拽的物品 entry
    dragX          = 0,            -- 拖拽光标 X
    dragY          = 0,            -- 拖拽光标 Y
    hoverZone      = nil,          -- 当前悬停的投放区 "sell"|"loadout"|nil
    sellPending    = {},           -- 待出售队列
    selectedItemId = nil,          -- 移动端选中的物品（显示信息）
    lastTapItemId  = nil,          -- 上次点击的物品 ID（双击检测）
    lastTapTime    = 0,            -- 上次点击时间戳（双击检测）
}

-- 屏幕分辨率（每帧更新）
local SW, SH = 800, 640
-- UI 设计基准高度：以此高度为1x缩放参考，高于此则放大 UI
local UI_DESIGN_H = 640
-- UI 等效 DPR（物理DPR × UI缩放因子），用于 nvgBeginFrame 和鼠标坐标
local uiDPR = 1

-- 相机（左上角世界坐标）
local camX, camY = 0, 0

-- 相机缩放（> 1 = 放大世界，即缩小视野范围）
-- 1.43 ≈ 1/0.7，视野缩小约 30%
local CAM_ZOOM = 1.243 * 1.1       -- PC 端基准（缩小10%视野）
local CAM_ZOOM_MOBILE = 1.243 / 1.05  -- 手机端（视野比PC基准大5%）
local camZoomSmooth = CAM_ZOOM  -- 平滑缩放（避免切枪抖动）

-- 游戏对象
---@type table
local player   = nil
---@type table[]
local enemies  = {}
---@type table[]
local bullets  = {}

-- 键盘状态
local keys = { w=false, a=false, s=false, d=false }

-- 鼠标/触摸持续按压状态（用于长按连射）
local mouseLeftHeld = false
-- J 键持续按压状态
local keyJHeld = false

-- 游戏计时
local elapsedTime = 0.0
local frameDt = 1/60  -- 当前帧 dt，供渲染使用
-- Dev.Draw 复用表（避免每帧分配）
local devDrawInfo = {}
-- 进入局内淡入效果
local fadeInTimer = 0
-- 玩家入场光柱特效
local entranceTimer = 0
local ENTRANCE_DURATION = 0.5
local teleportSfxDelay = 0   -- 传送音效延迟计时

-- 玩家视野半径（像素）— 决定 FOV 暗遮罩大小 & 敌人感知范围
local PLAYER_FOV = 210

-- 视野系统：当前帧可见房间表 { room -> "full"|"outline" }
local visibleRooms = {}

-- 搜索面板布局缓存（每次打开时重新计算，避免每帧重算）
---@type table|nil
local searchPanelLayout = nil

-- 医疗快用栏悬停槽位（1/2/3 或 nil）
local medBarHover = nil

-- 备战区购买面板触摸滚动状态
local buyScrollDrag = { active=false, touchId=nil, startY=0, startScrollY=0 }

-- 备战区仓库格子触摸拖拽状态（用于区分 tap/double-tap 和 drag）
local stashDragState = { active=false, touchId=nil, startX=0, startY=0, entry=nil, gridCol=0, gridRow=0, dragging=false }

-- 备战区右侧面板触摸滚动状态（出售列表/出战列表）
local rightPanelDrag = { active=false, touchId=nil, startY=0, startScrollY=0, moved=false, target=nil }

-- ----------------------------------------------------------------------------
-- 层数 / 奖励 系统
-- ----------------------------------------------------------------------------
local currentFloor  = 1        -- 当前层（1~20）
local MAX_FLOOR     = 20

---@type table|nil
local buildState    = nil      -- 当前局的Build状态（Reward.NewBuildState()）

-- 奖励状态
local rewardChoices = nil      -- {item1, item2, item3}
local rewardHover   = nil      -- 当前悬停卡片索引

-- 出发前三选一状态
local pickChoices   = nil      -- {item1, item2, item3}（三件白色候选物）
local pickHover     = nil      -- 当前悬停卡片索引（1/2/3 或 nil）

-- 撤离/继续 选择状态
local extractHover  = nil      -- "evacuate" | "continue" | nil

-- 本局是否从撤离点成功撤离（只有此标志为 true 才保存物品）
local raidExtracted = false

-- Boss 层标记
local isBossFloor    = false
local prevBossAlive  = false   -- 上一帧 Boss 是否存活（用于检测死亡瞬间）

-- 当前显示的 Build 通知（阈值/联动）
---@type table|nil
local buildNotif     = nil   -- { text, timer, totalTime, color }

-- Tooltip 状态（物品信息浮窗）
local tooltipState = {
    visible   = false,
    info      = nil,   -- Data.GetItemTooltip 返回的 table
    posX      = 0,
    posY      = 0,
    entry     = nil,   -- 当前悬停的 entry 引用（用于判断是否切换物品）
    -- 移动端长按计时
    touchId   = nil,
    touchX    = 0,
    touchY    = 0,
    touchTime = 0,     -- 按住时长（秒）
}

-- 搜索面板双击检测状态（手机端：单点查看信息，双击取走/放回）
local searchDoubleTap = {
    lastTime    = 0,       -- 上次短按时间戳
    lastEntryId = nil,     -- 上次点击的 entry.id
    lastAction  = nil,     -- 上次操作类型 ("searchTake"/"searchPut")
    THRESHOLD   = 0.35,    -- 双击最大间隔（秒）
}

-- ----------------------------------------------------------------------------
-- 移动端状态
-- ----------------------------------------------------------------------------
local isMobile         = false   -- 是否移动平台（Start() 时确定）
---@type MobileLayout|nil
local mobileLayout     = nil     -- 当前帧布局（每帧按 SW/SH 重算）
-- 上一帧是否按住攻击（用于检测长按连射）
local mobileAttackHeld = false

-- ----------------------------------------------------------------------------
-- 辅助：相机跟随（玩家始终居中）
-- ----------------------------------------------------------------------------
local function UpdateCamera(dt)
    -- 狙击枪视野加成：装备狙击枪时视野扩大 10%（CAM_ZOOM 缩小）
    local targetZoom = CAM_ZOOM
    if player and player.weapon and player.weapon.ammoType == "sniper" then
        targetZoom = CAM_ZOOM / 1.1
    end
    -- 平滑过渡缩放值（避免切枪抖动）
    camZoomSmooth = camZoomSmooth + (targetZoom - camZoomSmooth) * math.min(1.0, 8.0 * dt)
    -- 视野虚拟尺寸 = 实际屏幕 / 缩放，相机左上角让玩家居中于此虚拟尺寸
    local vw = SW / camZoomSmooth
    local vh = SH / camZoomSmooth
    local targetX = player.x - vw * 0.5
    local targetY = player.y - vh * 0.5
    local speed = 10.0
    camX = camX + (targetX - camX) * math.min(1.0, speed * dt)
    camY = camY + (targetY - camY) * math.min(1.0, speed * dt)

    -- 屏幕震动：应用随机偏移并快速衰减
    if player and (player.screenShake or 0) > 0.1 then
        local shake = player.screenShake
        local offsetX = (math.random() * 2 - 1) * shake / camZoomSmooth
        local offsetY = (math.random() * 2 - 1) * shake / camZoomSmooth
        camX = camX + offsetX
        camY = camY + offsetY
        -- 快速衰减（约 0.1 秒内消失）
        player.screenShake = shake * math.max(0, 1 - 15 * dt)
    elseif player then
        player.screenShake = 0
    end
end

-- ----------------------------------------------------------------------------
-- 辅助：子弹更新（移动 + 碰墙消除）
-- ----------------------------------------------------------------------------
local function UpdateBullets(dt)
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        b.life = b.life - dt
        -- 剑气波：每帧生成飞行尾迹粒子
        if b.isSlashWave then
            local life01 = math.max(0, b.life / (b.maxLife or 0.9))
            World.SpawnSlashWaveTrail(b.x, b.y, b.angle, life01)
        end
        -- 敌方子弹击中玩家
        if b.isEnemy and player then
            local dx = b.x - player.x
            local dy = b.y - player.y
            local hitR = (b.radius or 4) + 12  -- 子弹半径 + 玩家半径
            if dx * dx + dy * dy < hitR * hitR then
                Player.ApplyDamage(player, b.damage or 5, b.x, b.y)
                World.SpawnSpark(b.x, b.y, 4)
                table.remove(bullets, i)
                goto continue_bullet
            end
        end
        if b.life <= 0 or World.IsWall(b.x, b.y) then
            -- 击墙火花（非超时消失的子弹才产生）
            if World.IsWall(b.x, b.y) and not b.isSlashWave then
                World.SpawnSpark(b.x, b.y, 6)
            end
            table.remove(bullets, i)
        end
        ::continue_bullet::
    end
end

-- ----------------------------------------------------------------------------
-- 进入奖励界面（层 1~19 通关后触发）
-- ----------------------------------------------------------------------------
local function EnterRewardState()
    rewardChoices = Reward.Generate(buildState)
    -- 四选一牌效果用完后复原为默认3选（在 Generate 消费 nextPickCount 之后）
    buildState.nextPickCount = 3
    rewardHover   = nil
    STATE = "reward"
    Audio.PlayNewFloor()
end

-- ----------------------------------------------------------------------------
-- 进入下一层（奖励选完后触发）
-- ----------------------------------------------------------------------------
local function AdvanceFloor()
    -- 奖励技能点（按当前层数决定数量，升层前结算）
    local spGain = SkillTree.GetPointsForFloor(currentFloor)
    skillTreeState.skillPoints = skillTreeState.skillPoints + spGain
    SkillTree.Save(skillTreeState)

    currentFloor = currentFloor + 1
    isBossFloor  = (currentFloor % 5 == 0)
    if buildState then buildState.floor = currentFloor end

    -- 新地图（保留玩家状态、装备、背包）
    local spawns, pSpawnX, pSpawnY, bossSpawn = World.Init(currentFloor)

    -- 玩家位置重置（保留所有属性）
    player.x = pSpawnX
    player.y = pSpawnY
    player.vx, player.vy = 0, 0
    player.extracting = 0
    player.extracted  = false
    player.bagOpen    = false
    player.hitFlash   = 0
    player.hitShake   = 0
    -- 重置搜索状态
    Search.CancelSearch(player.searchState)
    Search.Close(player.searchState)
    player.searchOpen = false
    searchPanelLayout = nil
    player.exitFound  = false  -- 新地图重置撤离点发现状态
    -- 重置背包拖拽状态
    if player.bagDragState then
        player.bagDragState.dragItem        = nil
        player.bagDragState.hoverWeaponSlot = nil
        player.bagDragState.srcType         = nil
        player.bagDragState.srcWeaponKey    = nil
        player.bagDragState.hoverBagGrid    = nil
    end

    enemies = Enemy.InitAll(spawns, currentFloor)
    bullets = {}

    -- Boss 层：生成 Boss
    if bossSpawn then
        local boss = Enemy.NewBoss(bossSpawn.wx, bossSpawn.wy, bossSpawn.key, currentFloor)
        -- 传递boss房边界用于激活检测
        boss.roomL = bossSpawn.roomL
        boss.roomT = bossSpawn.roomT
        boss.roomR = bossSpawn.roomR
        boss.roomB = bossSpawn.roomB
        table.insert(enemies, boss)
    end

    -- 相机重置
    camX = player.x - SW / CAM_ZOOM * 0.5
    camY = player.y - SH / CAM_ZOOM * 0.5

    fadeInTimer = 0.3
    entranceTimer = ENTRANCE_DURATION
    teleportSfxDelay = 0.2
    STATE = "playing"
    if isBossFloor then
        Audio.OnBossAppear()   -- Boss登场音效 + Boss BGM
    else
        Audio.PlayBGM("dungeon")

    end
end

-- ----------------------------------------------------------------------------
-- 进入主界面
-- ----------------------------------------------------------------------------
local function EnterHub()
    STATE = "hub"
    hubHover = nil
end

-- ----------------------------------------------------------------------------
-- 进入战前准备界面
-- ----------------------------------------------------------------------------
local function EnterLoadout()
    -- 清空上一局残留弹药（弹药不跨局保留）
    local hadAmmo = false
    if stash and stash.ammo then
        for _, cnt in pairs(stash.ammo) do
            if cnt > 0 then hadAmmo = true; break end
        end
        stash.ammo = {}
        if hadAmmo then Stash.Save(stash) end
    end

    loadoutLayout = nil
    loadoutState  = {
        activeTab      = "sell",
        activeVendorId = "therapist",
        loadoutItems   = {},
        hoverItemId    = nil,
        dragItem       = nil,
        dragX          = 0,
        dragY          = 0,
        hoverZone      = nil,
        sellPending    = {},
        buyScrollY     = 0,     -- 购买面板商品列表滚动偏移
        sellScrollY    = 0,     -- 出售待定列表滚动偏移
        equipScrollY   = 0,     -- 出战装备列表滚动偏移
        mobileSection  = "shop", -- 移动端当前 Tab（shop/bag/equip）
        multiSellMode  = false,
        selectedItemId = nil,
        lastTapItemId  = nil,
        lastTapTime    = 0,
        ammoCleared    = hadAmmo,  -- 标记本次进入时是否清空了弹药（用于提示）
        ammoClearTimer = hadAmmo and 3.0 or 0,  -- 提示显示3秒
    }
    STATE = "loadout"
    Audio.PlayBGM("menu")
end

-- ----------------------------------------------------------------------------
-- 初始化一局游戏（全新开始）
-- ----------------------------------------------------------------------------
local function InitGame()
    currentFloor = 1
    isBossFloor  = false
    -- buildState 由 pick 流程提前初始化并已选好初始天赋，此处不覆盖
    if not buildState then buildState = Reward.NewBuildState() end
    buildState.floor = currentFloor
    rewardChoices = nil
    rewardHover   = nil
    buildNotif    = nil
    raidExtracted = false   -- 新局开始，尚未撤离

    local spawns, pSpawnX, pSpawnY, bossSpawn = World.Init(currentFloor)

    player   = Player.New(pSpawnX, pSpawnY)
    player.exitFound = false   -- 是否已发现撤离点（进入视野范围后置true）
    -- 背包拖拽状态（每局重置）
    player.bagDragState = {
        dragItem         = nil,   -- 正在拖拽的 inventory entry 引用
        dragX            = 0,
        dragY            = 0,
        srcInv           = nil,   -- "bag"（从背包发起时）
        srcType          = nil,   -- "inv" | "weaponSlot" | "equipSlot"（拖拽来源类型）
        srcWeaponKey     = nil,   -- 从武器槽发起时的槽位 key
        srcEquipSlot     = nil,   -- 从装备槽发起时的槽位名 ("helmet"|"armor"|"bag")
        hoverWeaponSlot  = nil,   -- 悬停的武器槽 key ("weapon"|"altWeapon"|nil)
        hoverBagGrid     = nil,   -- 悬停的背包格子 {col, row}（用于武器槽→背包）
    }
    enemies  = Enemy.InitAll(spawns, currentFloor)
    bullets  = {}
    elapsedTime = 0.0

    -- 注入战前准备时从仓库取出的物品
    local lItems = loadoutState and loadoutState.loadoutItems or {}
    if #lItems > 0 then
        local Inventory = require("Inventory")
        -- 分类：装备（bag/helmet/armor）、武器、其余
        local equipOrder = { "bag", "helmet", "armor" }
        local equipBySlot = {}
        local weapons = {}
        local nonEquip = {}
        local EQUIP_SLOTS = { helmet=true, armor=true, bag=true }
        for _, item in ipairs(lItems) do
            local slot = EQUIP_SLOTS[item.itype] and item.itype
                      or (item.itype == "equip" and item.slot)
            if slot and item.data then
                if not equipBySlot[slot] then
                    equipBySlot[slot] = item
                else
                    table.insert(nonEquip, item)
                end
            elseif item.itype == "weapon" and item.data then
                table.insert(weapons, item)
            else
                table.insert(nonEquip, item)
            end
        end
        -- 第一步：穿装备（bag 优先，扩容背包）
        for _, slot in ipairs(equipOrder) do
            local item = equipBySlot[slot]
            if item then
                player.equip[slot] = item.data
                if slot == "bag" then Player.UpdateBagSize(player) end
            end
        end
        -- 第二步：自动装备武器到主/副武器槽
        for _, item in ipairs(weapons) do
            local gun = item.data
            if not player.primaryGun then
                player.primaryGun = gun
                player.activeSlot = "primary"
            elseif not player.secondaryGun then
                player.secondaryGun = gun
            else
                -- 两槽已满，多余武器放背包
                table.insert(nonEquip, item)
            end
        end
        Player.syncWeaponRef(player)
        -- 第三步：剩余物品放入背包
        for _, item in ipairs(nonEquip) do
            Inventory.AutoPlace(player.inventory, item)
        end
        loadoutState.loadoutItems = {}
    end

    -- 注入商店购买的弹药储备（stash.ammo）到 player.ammoStash，消耗后清零
    if stash and stash.ammo then
        player.ammoStash = player.ammoStash or {}
        for atype, cnt in pairs(stash.ammo) do
            if cnt > 0 then
                player.ammoStash[atype] = (player.ammoStash[atype] or 0) + cnt
            end
        end
        stash.ammo = {}  -- 已消耗，清空
        Stash.Save(stash)
    end

    -- 应用技能树永久加成
    local bonuses = SkillTree.GetBonuses(skillTreeState)
    if bonuses.hpBonus > 0 then
        player.maxHp = player.maxHp + bonuses.hpBonus
        player.hp    = player.maxHp
    end
    if bonuses.armorBonus > 0 then
        player.bonusArmor = (player.bonusArmor or 0) + bonuses.armorBonus
    end
    if bonuses.moveSpeed > 0 then
        player.speedMult = (player.speedMult or 1.0) * (1 + bonuses.moveSpeed)
    end
    if bonuses.reloadSpeed > 0 then
        player.reloadMult = (player.reloadMult or 1.0) * (1 - bonuses.reloadSpeed)
    end
    if bonuses.damageBonus > 0 or bonuses.weaponMastery > 0 then
        -- weaponMastery 的伤害部分叠加到 damageBonus
        player.skillDmgBonus = (bonuses.damageBonus or 0) + (bonuses.weaponMastery or 0)
    end
    -- weaponMastery 的稀有度部分：概率提升武器掉落稀有度上限
    World.weaponRarityBoost = bonuses.weaponMastery or 0
    if bonuses.spreadReduction > 0 then
        player.skillSpreadReduction = bonuses.spreadReduction
    end
    if bonuses.critChance > 0 then
        player.skillCritChance = bonuses.critChance
    end
    if bonuses.critDamage > 0 then
        player.skillCritDmg = bonuses.critDamage
    end
    if bonuses.regen > 0 then
        -- regen 值为"每10秒回复X HP"的平坦值，使用独立字段（不与百分比回复混淆）
        player.flatRegen = (player.flatRegen or 0) + bonuses.regen
    end
    if bonuses.healBoost > 0 then
        player.skillHealBoost = bonuses.healBoost
    end
    if bonuses.critResist > 0 then
        player.skillCritResist = bonuses.critResist  -- 预留：敌人暴击系统实现后生效
    end
    if bonuses.searchSpeed > 0 then
        player.skillSearchSpeed = bonuses.searchSpeed
    end
    if bonuses.bagSlots > 0 then
        player.skillBagSlots = bonuses.bagSlots
        -- 扩展背包网格：每增加 width 格增加一行
        local Inventory = require("Inventory")
        local inv = player.inventory
        local extraRows = math.ceil(bonuses.bagSlots / inv.width)
        local newInv = Inventory.Resize(inv, inv.width, inv.height + extraRows)
        player.inventory = newInv
    end
    if bonuses.extraLife > 0 then
        player.extraLives = (player.extraLives or 0) + math.floor(bonuses.extraLife)
    end

    -- 第1层不是Boss层，bossSpawn 应为 nil
    if bossSpawn then
        local boss = Enemy.NewBoss(bossSpawn.wx, bossSpawn.wy, bossSpawn.key, currentFloor)
        boss.roomL = bossSpawn.roomL
        boss.roomT = bossSpawn.roomT
        boss.roomR = bossSpawn.roomR
        boss.roomB = bossSpawn.roomB
        table.insert(enemies, boss)
    end

    -- 初始相机对准玩家（玩家居中）
    camX = player.x - SW / CAM_ZOOM * 0.5
    camY = player.y - SH / CAM_ZOOM * 0.5

    fadeInTimer = 0.3
    entranceTimer = ENTRANCE_DURATION
    teleportSfxDelay = 0.2
    STATE = "playing"
end

-- ============================================================================
-- Start / Stop
-- ============================================================================
function Start()
    vg = nvgCreate(1)
    nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    nvgCreateFont(vg, "bold", "Fonts/MiSans-Bold.ttf")
    nvgCreateFont(vg, "pixel", "Fonts/PressStart2P.ttf")

    Audio.Init()
    Audio.PlayBGM("menu")

    SubscribeToEvent(vg, "NanoVGRender",   "HandleNanoVGRender")
    SubscribeToEvent("Update",             "HandleUpdate")
    SubscribeToEvent("KeyDown",            "HandleKeyDown")
    SubscribeToEvent("KeyUp",              "HandleKeyUp")
    SubscribeToEvent("MouseButtonDown",    "HandleMouseButtonDown")
    SubscribeToEvent("MouseButtonUp",      "HandleMouseButtonUp")
    SubscribeToEvent("MouseWheel",         "HandleMouseWheel")

    -- 移动端：检测平台并注册触控事件
    isMobile = MobileHUD.IsMobile()
    if isMobile then
        CAM_ZOOM = CAM_ZOOM_MOBILE  -- 手机端视野扩大 10%
        input.touchEmulation = false
        SubscribeToEvent("TouchBegin", "HandleTouchBegin")
        SubscribeToEvent("TouchMove",  "HandleTouchMove")
        SubscribeToEvent("TouchEnd",   "HandleTouchEnd")
    end
end

function Stop()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end

-- ============================================================================
-- 辅助：获取鼠标逻辑坐标（物理像素 / uiDPR = UI坐标，与 nvgBeginFrame 对齐）
-- ============================================================================
local function MousePos()
    return math.floor(input.mousePosition.x / uiDPR),
           math.floor(input.mousePosition.y / uiDPR)
end

-- ============================================================================
-- 渲染
-- ============================================================================
function HandleNanoVGRender(eventType, eventData)
    -- 计算 UI 等效 DPR：在 PC 端基于设计高度(640)进行放大，使 UI 不会因分辨率过高而过小
    local dpr = graphics:GetDPR()
    if dpr <= 0 then dpr = 1 end
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local logicalH = math.floor(physH / dpr)
    if not isMobile and logicalH > UI_DESIGN_H then
        uiDPR = dpr * (logicalH / UI_DESIGN_H)
    else
        uiDPR = dpr
    end
    SW = math.floor(physW / uiDPR)
    SH = math.floor(physH / uiDPR)

    nvgBeginFrame(vg, SW, SH, uiDPR)
    Render.dt = frameDt

    -- 移动端仅分辨率变化时重算布局
    if isMobile and (SW ~= (M_lastSW or 0) or SH ~= (M_lastSH or 0)) then
        mobileLayout = MobileHUD.Layout(SW, SH)
        M_lastSW, M_lastSH = SW, SH
    end

    if STATE == "menu" then
        Render.DrawMenu(vg, SW, SH, elapsedTime, menuHover)
        if showHowTo then
            Render.DrawHowToPlay(vg, SW, SH, howToScrollY, isMobile)
        elseif showVolumeMenu then
            Render.DrawPauseMenu(vg, SW, SH, elapsedTime, nil,
                Audio.GetBGMVolume(), Audio.GetSFXVolume(), pauseDragState)
        end

    elseif STATE == "hub" then
        Render.DrawHub(vg, SW, SH, stash, elapsedTime, hubHover)

    elseif STATE == "skill_tree" then
        SkillTreeUI.Draw(vg, SW, SH, skillTreeState, stash, skillTreeHover, elapsedTime, skillTreeScrollY)

    elseif STATE == "loadout" then
        Render.DrawLoadoutScreen(vg, stash, loadoutLayout, loadoutState, SW, SH)
        -- 弹药清空提示
        if loadoutState and loadoutState.ammoClearTimer and loadoutState.ammoClearTimer > 0 then
            local alpha = math.min(1, loadoutState.ammoClearTimer / 0.5)
            local a255  = math.floor(alpha * 220)
            local msg   = "⚠ 弹药已清空 — 每局弹药不跨局保留"
            local tw    = 280
            local th    = 30
            local tx    = SW / 2 - tw / 2
            local ty    = SH * 0.12
            nvgBeginPath(vg) nvgRoundedRect(vg, tx, ty, tw, th, 6)
            nvgFillColor(vg, nvgRGBA(20, 10, 5, math.floor(alpha * 200))) nvgFill(vg)
            nvgBeginPath(vg) nvgRoundedRect(vg, tx, ty, tw, th, 6)
            nvgStrokeColor(vg, nvgRGBA(255, 180, 60, a255)) nvgStrokeWidth(vg, 1.2) nvgStroke(vg)
            nvgFontFace(vg, "sans") nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 210, 80, a255))
            nvgText(vg, tx + tw / 2, ty + th / 2, msg, nil)
        end

    elseif STATE == "pick" then
        -- 出发前三选一：黑色背景 + 选卡面板
        nvgBeginPath(vg) nvgRect(vg, 0, 0, SW, SH)
        nvgFillColor(vg, nvgRGBA(8, 12, 18, 255)) nvgFill(vg)
        if pickChoices then
            Render.DrawRewardPanel(vg, pickChoices, pickHover, SW, SH,
                "[ 选择出发强化 ]", "选择一个天赋，带入本次行动")
        end

    elseif STATE == "playing" or STATE == "paused" then
        -- 世界层：统一缩放（使用平滑过渡的 camZoomSmooth）
        local curZoom = camZoomSmooth
        -- 传入虚拟屏幕尺寸（世界空间中的可见范围）
        local vw = SW / curZoom
        local vh = SH / curZoom
        nvgSave(vg)
        nvgScale(vg, curZoom, curZoom)
        Render.DrawMap(vg, camX, camY, vw, vh, elapsedTime, visibleRooms)
        Render.DrawExitMarkers(vg, camX, camY, vw, vh, elapsedTime, player.exitFound)
        Render.DrawRoomObjects(vg, camX, camY, player, visibleRooms)
        Render.DrawBoxes(vg, camX, camY, visibleRooms)
        Render.DrawCorpses(vg, camX, camY, elapsedTime, visibleRooms)
        Render.DrawDrops(vg, camX, camY, player, visibleRooms)
        Render.DrawParticles(vg, camX, camY)
        Render.DrawMuzzleFlashes(vg, camX, camY)
        Render.DrawBullets(vg, camX, camY, bullets)
        Render.DrawEnemies(vg, camX, camY, enemies, elapsedTime, visibleRooms)
        Render.DrawPlayer(vg, player, camX, camY, entranceTimer, ENTRANCE_DURATION)
        Render.DrawDmgPopups(vg, camX, camY, frameDt)
        Render.DrawLightningFx(vg, camX, camY, frameDt)
        Render.DrawPlayerEntrance(vg, player, camX, camY, entranceTimer, ENTRANCE_DURATION)
        -- WallTop 图层（覆盖在玩家/敌人之上，产生层次遮挡）
        Render.DrawWallTop(vg, camX, camY, vw, vh, visibleRooms)
        -- 狙击枪红外预瞄（世界空间坐标，在 scale 内一并缩放）
        Render.DrawSniperEffects(vg, player, camX, camY, vw, vh)
        -- 动态光照（径向渐变，世界空间）
        Render.DrawLighting(vg, camX, camY, elapsedTime)
        -- 环境暗色底层（路径B：全屏暗色 + 光源刮亮，世界空间）
        Lighting.RenderAmbientDarkness(vg, vw, vh, camX, camY, currentFloor, elapsedTime, player.x, player.y)
        nvgRestore(vg)
        -- FOV 暗视野遮罩（屏幕空间，玩家位置需换算为屏幕像素）
        local psx = (player.x - camX) * curZoom
        local psy = (player.y - camY) * curZoom
        Render.DrawFOVOverlay(vg, psx, psy, SW, SH, PLAYER_FOV * curZoom)
        -- 断电时：灯光穿透黑暗 + 枪火照亮（屏幕空间，在FOV遮罩之上）
        if World.powerDown then
            Render.DrawLampGlowthrough(vg, camX, camY, curZoom, visibleRooms)
            Render.DrawMuzzleFlashGlow(vg, camX, camY, curZoom)
        end
        -- 暗角效果（屏幕空间，楼层越深越重）
        Lighting.RenderVignette(vg, SW, SH, Lighting.GetVignetteIntensity(currentFloor))
        -- 受击全屏红闪（仅叠加在已有像素上，透明区域不闪）
        if player.hitFlash and player.hitFlash > 0 then
            local flashA = math.floor(math.min(player.hitFlash, 1.0) * 100)
            nvgGlobalCompositeOperation(vg, NVG_ATOP)
            -- 径向渐变：中心较淡，边缘更红（类似受伤晕影）
            local cx, cy = SW * 0.5, SH * 0.5
            local outerR = math.max(SW, SH) * 0.175
            local grad = nvgRadialGradient(vg, cx, cy, outerR * 0.3, outerR,
                nvgRGBA(255, 0, 0, math.floor(flashA * 0.3)),
                nvgRGBA(255, 0, 0, flashA))
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, SW, SH)
            nvgFillPaint(vg, grad)
            nvgFill(vg)
            nvgGlobalCompositeOperation(vg, NVG_SOURCE_OVER)
        end
        local hasBoss = Enemy.HasBossAlive(enemies)
        Render.DrawHUD(vg, player, enemies, elapsedTime, SW, SH, currentFloor, hasBoss, isMobile)
        -- 通用通知（始终显示，不依赖面板）
        Render.DrawNotification(vg, player.notification, SW, SH)
        -- 医疗快用栏（HUD 之后、面板之前）
        Render.DrawMedBar(vg, player, SW, SH, medBarHover, isMobile, elapsedTime)
        if STATE == "playing" then
            if player.bagOpen then
                Render.DrawInventoryPanel(vg, player, SW, SH, isMobile)
            end
            -- 搜索面板（优先级高于背包，盖在上方）
            if player.searchOpen then
                if not searchPanelLayout then
                    searchPanelLayout = Render.GetSearchPanelLayout(
                        player.searchState, player.inventory, SW, SH)
                end
                Render.DrawSearchPanel(vg, player.searchState, player.inventory,
                    searchPanelLayout, SW, SH, elapsedTime, player.notification)
            end
            -- 物品 Tooltip 浮窗（面板之上，最高层）
            if tooltipState.visible and tooltipState.info
            and (player.bagOpen or player.searchOpen) then
                Render.DrawItemTooltip(vg, tooltipState.info,
                    tooltipState.posX, tooltipState.posY, SW, SH)
            elseif tooltipState.visible then
                -- 面板关闭时自动清除 tooltip
                tooltipState.visible = false
                tooltipState.entry = nil
                tooltipState.info = nil
            end
        end
        -- 移动端虚拟按键（playing 状态下，面板未开启时显示）
        if isMobile and mobileLayout and STATE == "playing"
        and not player.bagOpen and not player.searchOpen then
            -- 搜索可用：附近有未搜完的容器或尸体
            local searchAvail = false
            for _, box in ipairs(World.GetBoxes()) do
                local dd = (player.x - box.x)^2 + (player.y - box.y)^2
                if dd < 44*44 then searchAvail = true; break end
            end
            if not searchAvail then
                for _, corpse in ipairs(World.GetCorpses and World.GetCorpses() or {}) do
                    if not corpse.looted then
                        local dd = (player.x - corpse.x)^2 + (player.y - corpse.y)^2
                        if dd < 42*42 then searchAvail = true; break end
                    end
                end
            end
            if not searchAvail then
                for _, drop in ipairs(World.drops) do
                    if not drop.picked and not drop.nopickTimer then
                        local dd = (player.x - drop.x)^2 + (player.y - drop.y)^2
                        if dd < 36*36 then searchAvail = true; break end
                    end
                end
            end
            if not searchAvail and World.GetRoomInteraction then
                searchAvail = World.GetRoomInteraction(player) ~= nil
            end
            -- 撤离可用：站在撤离格上且出口未锁
            local col, row = World.WorldToTile(player.x, player.y)
            local nearExit = World.IsExitCell(col, row) and not World.exitLocked
            MobileHUD.Draw(vg, mobileLayout, searchAvail, player.rollCd or 0, nearExit)
        end
        -- 暂停菜单叠加在最上层
        if STATE == "paused" then
            Render.DrawPauseMenu(vg, SW, SH, elapsedTime, pauseHover,
                Audio.GetBGMVolume(), Audio.GetSFXVolume(), pauseDragState)
        end
        -- Build 通知横幅（阈值/联动，显示在游戏中）
        Render.DrawBuildNotification(vg, buildNotif, SW, SH)
        -- 进入局内黑屏淡入
        if fadeInTimer > 0 then
            local a = math.floor((fadeInTimer / 0.3) * 255)
            nvgBeginPath(vg) nvgRect(vg, 0, 0, SW, SH)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, a)) nvgFill(vg)
        end

    elseif STATE == "extract_choice" then
        -- 背景：最后一帧游戏画面（同样缩放）
        local vw2 = SW / CAM_ZOOM
        local vh2 = SH / CAM_ZOOM
        nvgSave(vg)
        nvgScale(vg, CAM_ZOOM, CAM_ZOOM)
        Render.DrawMap(vg, camX, camY, vw2, vh2)
        Render.DrawExitMarkers(vg, camX, camY, vw2, vh2, elapsedTime, player.exitFound)
        Render.DrawEnemies(vg, camX, camY, enemies, elapsedTime)
        Render.DrawPlayer(vg, player, camX, camY)
        Render.DrawWallTop(vg, camX, camY, vw2, vh2)
        nvgRestore(vg)
        -- 选择面板（屏幕空间，不缩放）
        Render.DrawExtractChoice(vg, player, currentFloor, SW, SH, extractHover)

    elseif STATE == "deep_confirm" then
        -- 背景：最后一帧游戏画面
        local vw2 = SW / CAM_ZOOM
        local vh2 = SH / CAM_ZOOM
        nvgSave(vg)
        nvgScale(vg, CAM_ZOOM, CAM_ZOOM)
        Render.DrawMap(vg, camX, camY, vw2, vh2)
        Render.DrawExitMarkers(vg, camX, camY, vw2, vh2, elapsedTime, player.exitFound)
        Render.DrawEnemies(vg, camX, camY, enemies, elapsedTime)
        Render.DrawPlayer(vg, player, camX, camY)
        Render.DrawWallTop(vg, camX, camY, vw2, vh2)
        nvgRestore(vg)
        -- 深入确认对话框
        local dcMx, dcMy = MousePos()
        Render.DrawDeepConfirm(vg, SW, SH, dcMx, dcMy, currentFloor)

    elseif STATE == "reward" then
        -- 先画最后一帧游戏画面（同样缩放）
        local vw3 = SW / CAM_ZOOM
        local vh3 = SH / CAM_ZOOM
        nvgSave(vg)
        nvgScale(vg, CAM_ZOOM, CAM_ZOOM)
        Render.DrawMap(vg, camX, camY, vw3, vh3)
        Render.DrawEnemies(vg, camX, camY, enemies, elapsedTime)
        Render.DrawPlayer(vg, player, camX, camY)
        Render.DrawWallTop(vg, camX, camY, vw3, vh3)
        nvgRestore(vg)
        -- 三选一面板（覆盖在上方）
        if rewardChoices then
            Render.DrawRewardPanel(vg, rewardChoices, rewardHover, SW, SH, nil, nil, buildState.rerollsLeft)
        end
        -- Build 通知横幅（阈值/联动，叠在面板之上）
        Render.DrawBuildNotification(vg, buildNotif, SW, SH)

    elseif STATE == "gameover" or STATE == "win" then
        nvgSave(vg)
        nvgScale(vg, CAM_ZOOM, CAM_ZOOM)
        local vwEnd = SW / CAM_ZOOM
        local vhEnd = SH / CAM_ZOOM
        Render.DrawMap(vg, camX, camY, vwEnd, vhEnd)
        Render.DrawWallTop(vg, camX, camY, vwEnd, vhEnd)
        nvgRestore(vg)
        Render.DrawEndScreen(vg, SW, SH, STATE == "win", player or {kills=0, lootValue=0}, elapsedTime)
        if isMobile and mobileLayout then
            MobileHUD.DrawContinueBtn(vg, SW, SH, STATE == "win" and "返回" or "再来一局")
        end
    end

    -- Dev System 渲染（面板 + 通知，叠在最顶层）
    devDrawInfo.state       = STATE
    devDrawInfo.floor       = currentFloor
    devDrawInfo.isBoss      = isBossFloor
    devDrawInfo.player      = player
    devDrawInfo.enemyCount  = #enemies
    devDrawInfo.bulletCount = #bullets
    devDrawInfo.camX        = camX
    devDrawInfo.camY        = camY
    devDrawInfo.elapsed     = elapsedTime
    Dev.Draw(vg, SW, SH, devDrawInfo)

    nvgEndFrame(vg)
end

-- ============================================================================
-- 更新循环
-- ============================================================================
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if dt > 0.1 then dt = 0.1 end
    frameDt = dt

    -- 通知计时器递减（全局，不依赖 STATE）
    if player and player.notification then
        player.notification.timer = player.notification.timer - dt
        if player.notification.timer <= 0 then
            player.notification = nil
        end
    end

    -- 战备界面弹药清空提示计时
    if STATE == "loadout" and loadoutState and loadoutState.ammoClearTimer and loadoutState.ammoClearTimer > 0 then
        loadoutState.ammoClearTimer = loadoutState.ammoClearTimer - dt
    end

    if STATE == "playing" then
        elapsedTime = elapsedTime + dt
        World.time = elapsedTime
        if player and World.DiscoverRoomAtWorld then
            World.DiscoverRoomAtWorld(player.x, player.y)
            -- 视野系统：标记进入房间 & 计算可见房间
            local curRoom = World.GetRoomAtWorld(player.x, player.y)
            if curRoom then World.EnterRoom(curRoom) end
            visibleRooms = World.GetVisibleRooms(player.x, player.y)
        end
        -- 淡入计时（先播完淡入，再播入场光柱）
        if fadeInTimer > 0 then
            fadeInTimer = fadeInTimer - dt
        elseif entranceTimer > 0 then
            entranceTimer = entranceTimer - dt
        end
        -- 传送音效延迟播放
        if teleportSfxDelay > 0 then
            teleportSfxDelay = teleportSfxDelay - dt
            if teleportSfxDelay <= 0 then
                Audio.PlayTeleportBeam()
                teleportSfxDelay = 0
            end
        end
        -- Build 通知倒计时
        if buildNotif and buildNotif.timer then
            buildNotif.timer = buildNotif.timer - dt
        end
        -- 弹出下一条 pending 通知（当前通知结束后）
        if buildState and (not buildNotif or buildNotif.timer <= 0) then
            local n = Reward.PopNotification(buildState)
            if n then
                n.totalTime = n.timer
                buildNotif  = n
            end
        end
    end

    if STATE == "menu" then
        local mx, my = MousePos()
        if showHowTo or showVolumeMenu then
            -- 覆盖层打开时更新音量滑块拖动
            if showVolumeMenu and pauseDragState.target then
                local v = Render.CalcSliderValue(mx, SW, SH, pauseDragState.target)
                if pauseDragState.target == "bgm" then Audio.SetBGMVolume(v)
                else Audio.SetSFXVolume(v) end
            end
        else
            menuHover = Render.HitTestMenu(mx, my, SW, SH)
        end
        return
    end

    if STATE == "hub" then
        local mx, my = MousePos()
        hubHover = Render.HitTestHub(mx, my, SW, SH)
        return
    end

    if STATE == "skill_tree" then
        local mx, my = MousePos()
        skillTreeHover = SkillTreeUI.HitTest(mx, my, SW, SH, skillTreeState, skillTreeScrollY)
        return
    end

    if STATE == "paused" then
        local mx, my = MousePos()
        -- 若正在拖动滑块，实时更新音量
        if pauseDragState.target then
            local v = Render.CalcSliderValue(mx, SW, SH, pauseDragState.target)
            if pauseDragState.target == "bgm" then
                Audio.SetBGMVolume(v)
            else
                Audio.SetSFXVolume(v)
            end
        end
        -- 按钮 hover（仅在不拖滑块时更新，避免鼠标划过按钮区域误触）
        if not pauseDragState.target then
            pauseHover = Render.GetPauseMenuHover(mx, my, SW, SH)
        end
        return
    end

    if STATE == "reward" then
        -- 奖励界面：更新悬停
        if rewardChoices then
            local mx, my = MousePos()
            rewardHover = Render.GetRewardHoverIndex(mx, my, rewardChoices, SW, SH)
            -- 刷新按钮悬停（用 -1 表示）
            if not rewardHover and Render.IsRerollButtonHover(mx, my, SW, SH, buildState.rerollsLeft) then
                rewardHover = -1
            end
        end
        -- 通知倒计时（reward 界面也需要）
        if buildNotif and buildNotif.timer then
            buildNotif.timer = buildNotif.timer - dt
        end
        return
    end

    if STATE == "pick" then
        -- 出发三选一：更新悬停
        if pickChoices then
            local mx, my = MousePos()
            pickHover = Render.GetRewardHoverIndex(mx, my, pickChoices, SW, SH)
        end
        return
    end

    if STATE == "extract_choice" then
        -- 撤离选择：更新悬停
        local mx, my = MousePos()
        extractHover = Render.GetExtractChoiceHover(mx, my, SW, SH)
        return
    end

    -- loadout 出售通知倒计时
    if STATE == "loadout" and loadoutState.soldTimer and loadoutState.soldTimer > 0 then
        loadoutState.soldTimer = loadoutState.soldTimer - dt
    end

    -- loadout 拖拽状态：实时更新光标位置和 hoverZone
    if STATE == "loadout" and loadoutState.dragItem then
        -- 触摸拖拽时，位置和 hoverZone 由 TouchMove 管理，跳过 MousePos
        if not (stashDragState.active and stashDragState.dragging) then
            local mx2, my2 = MousePos()
            loadoutState.dragX = mx2
            loadoutState.dragY = my2
            if not isMobile then
                -- PC 端：使用新 UI 的区域检测
                loadoutState.hoverZone = BattlePrepUI.GetDragZone(mx2, my2, SW, SH)
            elseif loadoutLayout then
                local lp = loadoutLayout
                local section = loadoutState.mobileSection or "shop"
                -- 出售区：仅 shop section 下有效
                if section == "shop" then
                    local sz = lp.sellZone
                    if mx2 >= sz.x and mx2 <= sz.x+sz.w and my2 >= sz.y and my2 <= sz.y+sz.h then
                        loadoutState.hoverZone = "sell"
                        goto continueLoadoutDrag
                    end
                end
                -- 出战区：bag/equip section 下有效
                local lz = lp.loadoutZone
                if lz and mx2 >= lz.x and mx2 <= lz.x+lz.w and my2 >= lz.y and my2 <= lz.y+lz.h then
                    loadoutState.hoverZone = "loadout"
                    goto continueLoadoutDrag
                end
                loadoutState.hoverZone = nil
                ::continueLoadoutDrag::
            end
        end
    end

    -- 背包拖拽：实时更新光标位置和悬停目标
    if STATE == "playing" and player and player.bagOpen and player.bagDragState
    and player.bagDragState.dragItem then
        local mx, my = MousePos()
        local ds = player.bagDragState
        ds.dragX = mx
        ds.dragY = my
        local lp = Render.GetInventoryPanelLayout(player, SW, SH, isMobile)

        -- 检测是否悬停在武器槽上
        ds.hoverWeaponSlot = nil
        for _, ws in ipairs(lp.weaponSlots) do
            if mx >= ws.x and mx <= ws.x + ws.w
            and my >= ws.y and my <= ws.y + ws.h then
                -- 刀槽不允许替换；从武器槽拖起时不能悬停在自身槽上
                if ws.key ~= "knife" and ws.key ~= ds.srcWeaponKey then
                    ds.hoverWeaponSlot = ws.key
                end
                break
            end
        end

        -- 检测是否悬停在背包网格上（武器槽→背包放回，或背包内移位）
        ds.hoverBagGrid = nil
        local inv = player.inventory
        local bx, by = lp.bagGridX, lp.bagGridY
        local cs = lp.CELL
        if mx >= bx and mx < bx + inv.width * cs
        and my >= by and my < by + inv.height * cs then
            local col = math.floor((mx - bx) / cs) + 1
            local row = math.floor((my - by) / cs) + 1
            ds.hoverBagGrid = { col = col, row = row }
        end
    end

    -- ========== Tooltip 悬停检测（PC 端鼠标移到物品上方） ==========
    if not isMobile and STATE == "playing" and player then
        local dragging = player.bagDragState and player.bagDragState.dragItem
        if not dragging and (player.bagOpen or player.searchOpen) then
            local mx, my = MousePos()
            local hoveredEntry = nil

            if player.searchOpen and searchPanelLayout then
                -- 搜索面板命中测试（左右两列）
                local e = Search.HitTestPanel(player.searchState, player.inventory,
                    "container", mx, my, searchPanelLayout)
                if not e then
                    e = Search.HitTestPanel(player.searchState, player.inventory,
                        "player", mx, my, searchPanelLayout)
                end
                hoveredEntry = e
            elseif player.bagOpen then
                -- 背包面板命中测试
                local lp = Render.GetInventoryPanelLayout(player, SW, SH, isMobile)
                local hit = Render.HitTestInventoryPanel(lp, player, mx, my)
                if hit then
                    if hit.action == "bagItem" and hit.entry then
                        hoveredEntry = hit.entry
                    elseif hit.action == "weaponSlot" then
                        -- 武器槽 → 取当前装备的武器
                        local wpn = player[hit.key]
                        if wpn then
                            hoveredEntry = { itype="weapon", data=wpn, name=wpn.name, rarity=wpn.rarity or 1 }
                        end
                    elseif hit.action == "equipSlot" then
                        -- 装备槽 → 取当前装备
                        local eq = player.equip and player.equip[hit.slot]
                        if eq then
                            hoveredEntry = { itype=hit.slot, data=eq, name=eq.name, rarity=eq.rarity or 1 }
                        end
                    end
                end
            end

            if hoveredEntry and hoveredEntry ~= tooltipState.entry then
                tooltipState.entry = hoveredEntry
                tooltipState.info = Data.GetItemTooltip(hoveredEntry)
                tooltipState.posX = mx
                tooltipState.posY = my
                tooltipState.visible = true
            elseif hoveredEntry then
                -- 同一物品：更新位置
                tooltipState.posX = mx
                tooltipState.posY = my
            else
                tooltipState.visible = false
                tooltipState.entry = nil
                tooltipState.info = nil
            end
        else
            -- 正在拖拽或面板关闭 → 清除 tooltip
            if tooltipState.visible then
                tooltipState.visible = false
                tooltipState.entry = nil
                tooltipState.info = nil
            end
        end
    end

    -- ========== Tooltip 长按检测（移动端） ==========
    if isMobile and tooltipState.touchId then
        tooltipState.touchTime = tooltipState.touchTime + dt
        if tooltipState.touchTime >= 0.45 and not tooltipState.visible then
            -- 长按超过 0.45 秒 → 显示已捕获的 tooltip 信息
            if tooltipState.info then
                tooltipState.posX = tooltipState.touchX
                tooltipState.posY = tooltipState.touchY
                tooltipState.visible = true
            end
        end
    end

    if STATE ~= "playing" then return end

    -- 医疗快用栏悬停检测
    do
        local mx, my = MousePos()
        medBarHover = Render.HitTestMedBar(mx, my, SW, SH, isMobile)
    end

    -- 让 Player 的近战攻击能访问当前敌人列表
    World._currentEnemies = enemies

    -- 相机先更新，瞄准角才能用最新相机坐标（解决弹道偏移）
    UpdateCamera(dt)

    -- 移动端：把摇杆方向映射到 keys（阈值 0.25 避免漂移）
    if isMobile then
        local jdx, jdy = MobileHUD.GetJoystickDir()
        keys.a = jdx < -0.25
        keys.d = jdx >  0.25
        keys.w = jdy < -0.25
        keys.s = jdy >  0.25
    end

    -- 玩家瞄准（自动锁定视野内最近敌人）
    Player.UpdateAim(player, camX, camY, enemies, PLAYER_FOV, keys)

    -- 医疗前摇更新（受击自动中断，完成后回血）
    Player.UpdateMedCast(player, dt)

    -- 长按左键 / J 键 / 移动端攻击按钮 连续射击（施法中禁用）
    if not player.bagOpen and not player.searchOpen and not Player.IsCasting(player) then
        local mobileAtk = isMobile and MobileHUD.IsAttackHeld()
        if mouseLeftHeld or keyJHeld or mobileAtk then
            Player.TryShoot(player, bullets)
        end
    end

    -- 玩家移动（搜箱子时禁止移动）
    if player.searchOpen then
        keys.w, keys.a, keys.s, keys.d = false, false, false, false
    end
    -- Dev 速度倍率
    ---@diagnostic disable-next-line: assign-type-mismatch
    local origSpeedMult = player.speedMult
    player.speedMult = (player.speedMult or 1.0) * Dev.speedMult
    Player.Update(player, dt, keys, bullets)
    player.speedMult = origSpeedMult
    local jdx2, jdy2 = isMobile and MobileHUD.GetJoystickDir() or 0, 0
    local isMoving = keys.w or keys.s or keys.a or keys.d
        or (isMobile and (math.abs(jdx2) > 0.1 or math.abs(jdy2) > 0.1))
    Audio.PlayFootstep(dt, isMoving)

    -- 搜索进度更新（物品逐一加载）
    local loadDone = Player.UpdateSearch(player, dt)
    if loadDone then
        -- 全部物品加载完成，刷新布局（格子内容已满）
        if searchPanelLayout then
            searchPanelLayout = Render.GetSearchPanelLayout(
                player.searchState, player.inventory, SW, SH)
        end
    end

    -- 更新子弹
    UpdateBullets(dt)

    -- 更新敌人（传入玩家FOV半径）
    Enemy.UpdateAll(enemies, dt, player, bullets, PLAYER_FOV)

    -- Boss4 气刃弹更新
    Boss4.UpdateQiBlades(dt, player)

    -- 粒子 & 枪口闪光 & 光照
    World.UpdateParticles(dt)
    World.UpdateMuzzleFlashes(dt)
    Lighting.Update(dt)

    -- 撤离点发现检测（进入视野范围后才显示导航）
    if not player.exitFound and World.EXIT_CENTER then
        local ex = (World.EXIT_CENTER.col - 0.5) * World.TILE
        local ey = (World.EXIT_CENTER.row - 0.5) * World.TILE
        local dx = player.x - ex
        local dy = player.y - ey
        if dx * dx + dy * dy <= PLAYER_FOV * PLAYER_FOV then
            player.exitFound = true
            player.notification = { text = "发现撤离点！", timer = 2.5 }
        end
    end

    -- 玩家死亡
    if player.hp <= 0 then
        Audio.PlayDeath()
        Audio.PlayBGM("death")
        STATE = "gameover"
        return
    end

    -- -----------------------------------------------------------------------
    -- 撤离逻辑（出口锁定 / 解锁）
    -- -----------------------------------------------------------------------
    -- Boss 层：Boss死亡才解锁出口
    if isBossFloor then
        local bossAlive = Enemy.HasBossAlive(enemies)
        if bossAlive then
            World.exitLocked = true
        else
            -- Boss 刚死亡那一帧：生成 Boss 宝箱
            if prevBossAlive then
                -- 找 Boss 尸体位置（最近一个 isBoss 尸体）
                local bx, by = player.x --[[@as number]], player.y --[[@as number]]
                for _, corpse in ipairs(World.GetCorpses()) do
                    if corpse.isBoss then bx, by = corpse.x, corpse.y; break end
                end
                World.SpawnBossChests(currentFloor, bx, by)
                player.notification = { text = "Boss 已击败！宝箱已掉落！", timer = 3.0 }
                Audio.OnBossKilled()
                -- Boss 击杀：保底计数器 +2（提升下次三选一稀有度概率）
                if buildState then
                    buildState.consecutiveNoEpic = math.min(
                        buildState.consecutiveNoEpic + 2, 5)
                end
            end
            World.exitLocked = false
        end
        prevBossAlive = bossAlive
    end

    -- 撤离计时（搜索面板打开时暂停，防止两者同时完成导致卡死）
    if player.extracting > 0 and not player.searchOpen then
        Player.UpdateExtract(player, dt)
        if player.extracted then
            -- 安全关闭搜索面板（如有残留）
            if player.searchOpen then Player.CloseSearch(player) end
            if currentFloor >= MAX_FLOOR then
                -- 第20层：直接胜利（无下一层可选）
                raidExtracted = true   -- 真正从撤离点撤离，保存物品
                STATE = "win"
                Audio.PlayExtractionSuccess()
                Audio.PlayBGM("extract")
            elseif currentFloor == 1 or isBossFloor then
                -- 第1层和Boss层（5/10/15）：可选撤离或继续
                extractHover = nil
                STATE = "extract_choice"
            else
                -- 其他层：只能继续深入，不可撤离
                extractHover = nil
                EnterRewardState()
            end
        end
    end

    -- Dev System 更新（FPS 计算、通知衰减、触摸激活计时）
    Dev.Update(dt)
    Dev.UpdateTapTimer(dt)
end

-- ============================================================================
-- 开发者系统 Actions（供 DevSystem 回调）
-- ============================================================================
local devActions = {
    killAll = function()
        for i = #enemies, 1, -1 do
            enemies[i].hp = 0
        end
    end,
    teleportExit = function()
        if player and World.EXIT_CENTER then
            local T = World.TILE
            player.x = (World.EXIT_CENTER.col - 0.5) * T
            player.y = (World.EXIT_CENTER.row - 0.5) * T
        end
    end,
    nextFloor = function()
        if player and STATE == "playing" and currentFloor < MAX_FLOOR then
            AdvanceFloor()
        end
    end,
    fullHeal = function()
        if player then
            player.hp = player.maxHp
            -- 护甲补满：计算装备提供的基础护甲，用 bonusArmor 补足到 110
            local Player = require("Player")
            local baseArmor = Player.CalcArmorValue(player) - (player.bonusArmor or 0)
            player.bonusArmor = math.max(0, 110 - baseArmor)
            if player.shieldMax and player.shieldMax > 0 then
                player.shieldHp = player.shieldMax
            end
            -- 无限子弹
            player.infiniteAmmo = true
        end
    end,
    giveWeapons = function()
        if player then
            -- 给 AWM（狙击，rarity 5）作为主武器
            local awm = Data.WEAPONS["AWM"]
            if awm then
                player.primaryGun = {
                    key=awm.key, name=awm.name, rarity=awm.rarity,
                    damage=awm.damage, fireRate=awm.fireRate, spread=awm.spread,
                    magSize=awm.magSize, ammo=awm.magSize, maxAmmo=awm.magSize,
                    reloadTime=awm.reloadTime, ammoType=awm.ammoType,
                    slot=awm.slot, icon=awm.icon, value=awm.value,
                    pellets=awm.pellets, reloadPerShell=awm.reloadPerShell,
                }
            end
            -- 给 P90（冲锋枪，rarity 4）作为副武器
            local p90 = Data.WEAPONS["P90"]
            if p90 then
                player.secondaryGun = {
                    key=p90.key, name=p90.name, rarity=p90.rarity,
                    damage=p90.damage, fireRate=p90.fireRate, spread=p90.spread,
                    magSize=p90.magSize, ammo=p90.magSize, maxAmmo=p90.magSize,
                    reloadTime=p90.reloadTime, ammoType=p90.ammoType,
                    slot=p90.slot, icon=p90.icon, value=p90.value,
                    pellets=p90.pellets, reloadPerShell=p90.reloadPerShell,
                }
            end
            player.activeSlot = "primary"
            -- 同步 weapon 引用
            player.weapon = player.primaryGun or player.knife
            player.reloadTimer = 0
        end
    end,
    giveMoney = function()
        if stash then
            stash.money = (stash.money or 0) + 10000
        end
    end,
}

-- ============================================================================
-- 键盘输入
-- ============================================================================
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- Dev System: F1 切换，F2~F9 作弊命令
    if key == KEY_F1 then Dev.Toggle(); return end  -- 正式发布前注释此行
    if Dev.enabled and Dev.HandleKey(key, devActions) then return end

    if STATE == "menu" then
        if key == KEY_ESCAPE then
            showHowTo = false
            showVolumeMenu = false
            pauseDragState.target = nil
        elseif not showHowTo and not showVolumeMenu then
            if key == KEY_SPACE or key == KEY_RETURN then
                Audio.PlayBtnClick()
                EnterHub()
            end
        end
        return
    end

    if STATE == "hub" then
        if key == KEY_SPACE or key == KEY_RETURN then
            Audio.PlayBtnClick()
            EnterLoadout()
        elseif key == KEY_ESCAPE then
            Audio.PlayBtnClick()
            STATE = "menu"
        end
        return
    end

    if STATE == "skill_tree" then
        if key == KEY_ESCAPE then
            Audio.PlayBtnClick()
            STATE = "hub"
        end
        return
    end

    if STATE == "loadout" then
        if key == KEY_SPACE or key == KEY_RETURN then
            Audio.PlayBtnClick()
            -- 出发前：将出售区未确认的物品归还仓库，防止丢失
            if loadoutState and loadoutState.sellPending and #loadoutState.sellPending > 0 then
                for _, item in ipairs(loadoutState.sellPending) do
                    Stash.AddItem(stash, item)
                end
                loadoutState.sellPending = {}
                Stash.Save(stash)
            end
            -- 生成 buildState 和初始选择
            buildState = Reward.NewBuildState()
            local whitePool = {}
            for _, item in ipairs(Reward.POOL) do
                if item.rarity == 1 then table.insert(whitePool, item) end
            end
            pickChoices = Reward.Generate(buildState, whitePool, 3)
            pickHover   = nil
            STATE = "pick"
        elseif key == KEY_ESCAPE then
            Audio.PlayBtnClick()
            EnterHub()
        end
        return
    end

    if STATE == "paused" then
        if key == KEY_ESCAPE or key == KEY_RETURN or key == KEY_SPACE then
            Audio.PlayBtnClick()
            STATE = "playing"
            pauseHover = nil
        end
        return
    end

    if STATE == "gameover" or STATE == "win" then
        if key == KEY_SPACE or key == KEY_RETURN then
            Audio.PlayBtnClick()
            local bns = SkillTree.GetBonuses(skillTreeState); local dsCount = (bns.deathSave or 0) + (bns.safeSlots or 0)
            Stash.OnRaidEnd(stash, player or {inventory={items={}}, equip={}}, raidExtracted, dsCount)
            Stash.Save(stash)
            EnterLoadout()
        elseif key == KEY_ESCAPE then
            Audio.PlayBtnClick()
            STATE = "menu"
            Audio.PlayBGM("menu")
        end
        return
    end

    if STATE == "extract_choice" then
        if key == KEY_SPACE or key == KEY_RETURN then
            raidExtracted = true   -- 键盘确认撤离，保存物品
            Audio.PlayExtractionSuccess()
            Audio.PlayBGM("extract")
            STATE = "win"
        elseif key == KEY_ESCAPE then
            -- ESC → 取消撤离，返回游戏（撤离状态重置）
            player.extracted  = false
            player.extracting = 0
            STATE = "playing"
        end
        return
    end

    if STATE == "reward" then
        -- ESC 跳过奖励（直接进入下一层，不选）
        -- 注：正常流程应点卡片选择
        return
    end

    -- playing 状态
    if not player then return end
    if key == KEY_W then keys.w = true
    elseif key == KEY_S then keys.s = true
    elseif key == KEY_A then keys.a = true
    elseif key == KEY_D then keys.d = true
    elseif key == KEY_I or key == KEY_TAB then
        -- 搜索面板开启时，I/TAB 键不切换背包
        if not player.searchOpen then
            player.bagOpen = not player.bagOpen
            if player.bagOpen then Audio.PlayPanelOpen() else Audio.PlayPanelClose() end
        end
    elseif key == KEY_G then
        -- G 键快速整理背包（仅背包开启时生效）
        if player.bagOpen then
            local Inventory = require("Inventory")
            Inventory.AutoSort(player.inventory)
            player.notification = { text="背包已整理 ✓", timer=1.2 }
            Audio.PlayBtnClick()
        end
    elseif key == KEY_Q then
        if not Player.IsCasting(player) then
            Player.SwapWeapon(player)
            Audio.PlayEquip()
        end
    elseif key == KEY_R then
        if not Player.IsCasting(player) then
            Player.Reload(player)
            Audio.PlayWeaponReload(player.weapon and player.weapon.name or "")
        end
    elseif key == KEY_LSHIFT or key == KEY_RSHIFT then
        if not player.bagOpen and not player.searchOpen then
            Player.TryRoll(player, keys)
        end
    elseif key == KEY_J then
        if not Player.IsCasting(player) then
            keyJHeld = true
            Player.TryShoot(player, bullets)
        end
    elseif key == KEY_1 then
        Player.UseMedSlot(player, 1)
    elseif key == KEY_2 then
        Player.UseMedSlot(player, 2)
    elseif key == KEY_3 then
        Player.UseMedSlot(player, 3)
    elseif key == KEY_G then
        -- G 键：搜索面板打开时触发智能拾取
        if player.searchOpen and searchPanelLayout then
            Audio.PlayPickup()
            Player.AutoLoot(player)
            local ss = player.searchState
            if ss.container and ss.container._box then
                World.SyncBoxLoot(ss.container._box, ss.containerInv)
            end
            searchPanelLayout = Render.GetSearchPanelLayout(
                player.searchState, player.inventory, SW, SH)
        end
    elseif key == KEY_F then
        -- F 键：使用背包中第一个医疗消耗品
        Player.UseFirstConsumable(player)
    elseif key == KEY_ESCAPE then
        -- ESC：先关面板 → 再暂停
        if player.searchOpen then
            Player.CloseSearch(player)
            player.searchOpen = false
            searchPanelLayout = nil
            Audio.PlayPanelClose()
        elseif player.bagOpen then
            player.bagOpen = false
            Audio.PlayPanelClose()
        else
            -- 无面板开启时 ESC 暂停游戏
            Audio.PlayBtnClick()
            STATE = "paused"
            pauseHover = nil
            keys = { w=false, a=false, s=false, d=false }
            mouseLeftHeld = false
            keyJHeld = false
        end
    elseif key == KEY_E then
        -- 搜索面板打开时 E 键关闭
        if player.searchOpen then
            Player.CloseSearch(player)
            player.searchOpen = false
            searchPanelLayout = nil
            return
        end
        if not player.bagOpen then
            if isBossFloor and World.exitLocked then
                local col, row = World.WorldToTile(player.x, player.y)
                if World.IsExitCell(col, row) then return end
            end
            Player.TryInteract(player, World)
            -- 面板现在总是立即打开，立刻计算布局并标记箱子
            if player.searchOpen then
                searchPanelLayout = Render.GetSearchPanelLayout(
                    player.searchState, player.inventory, SW, SH)
                -- 立即标记箱子已开（无论物品是否加载完）
                local ss = player.searchState
                if ss.container and ss.container._box then
                    World.MarkBoxOpened(ss.container._box)
                end
            end
        end
    end
end

function HandleKeyUp(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    -- 地牢 keys
    if key == KEY_W then keys.w = false
    elseif key == KEY_S then keys.s = false
    elseif key == KEY_A then keys.a = false
    elseif key == KEY_D then keys.d = false
    elseif key == KEY_J then keyJHeld = false
    end
end

-- ============================================================================
-- 鼠标滚轮（备战区购买列表滚动）
-- ============================================================================
local function ClampBuyScroll()
    local vendor = Stash.VENDOR_BY_ID[loadoutState.activeVendorId or "therapist"]
    if not vendor then return end
    local totalH    = #vendor.shop * BattlePrepUI.BUY_ITEM_H
    local maxScroll = math.max(0, totalH - BattlePrepUI.BUY_LIST_H)
    loadoutState.buyScrollY = math.max(0, math.min(loadoutState.buyScrollY or 0, maxScroll))
end

function HandleMouseWheel(eventType, eventData)
    local wheel = eventData["Wheel"]:GetInt()
    -- 玩法介绍面板滚动
    if STATE == "menu" and showHowTo then
        howToScrollY = howToScrollY - wheel * 30
        local maxScroll = Render.GetHowToMaxScroll(SW, SH)
        howToScrollY = math.max(0, math.min(howToScrollY, maxScroll))
        return
    end
    -- 技能树滚动
    if STATE == "skill_tree" then
        skillTreeScrollY = skillTreeScrollY - wheel * 40
        local maxScroll = SkillTreeUI.GetMaxScroll(SW, SH, skillTreeState)
        skillTreeScrollY = math.max(0, math.min(skillTreeScrollY, maxScroll))
        return
    end
    if STATE ~= "loadout" then return end
    if (loadoutState.activeTab or "sell") ~= "buy" then return end
    -- wheel > 0 = 向上滚（减少偏移），wheel < 0 = 向下滚（增加偏移）
    loadoutState.buyScrollY = (loadoutState.buyScrollY or 0) - wheel * BattlePrepUI.BUY_ITEM_H
    ClampBuyScroll()
end

-- ============================================================================
-- 鼠标输入
-- ============================================================================
function HandleMouseButtonDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()

    -- 左上角连点 5 次激活开发者面板
    if button == MOUSEB_LEFT then
        local tx, ty = MousePos()
        Dev.HandleTap(tx, ty)
    end

    if STATE == "menu" then
        if button == MOUSEB_LEFT then
            local mx, my = MousePos()
            -- 覆盖层打开时：点任意处关闭（音量面板先检测滑块）
            if showHowTo then
                showHowTo = false
                return
            end
            if showVolumeMenu then
                local sliderHit = Render.HitTestPauseSlider(mx, my, SW, SH)
                if sliderHit then
                    pauseDragState.target = sliderHit
                    local v = Render.CalcSliderValue(mx, SW, SH, sliderHit)
                    if sliderHit == "bgm" then Audio.SetBGMVolume(v) else Audio.SetSFXVolume(v) end
                else
                    showVolumeMenu = false
                    pauseDragState.target = nil
                end
                return
            end
            -- 无覆盖层：路由三个按钮
            local hit = Render.HitTestMenu(mx, my, SW, SH)
            if hit == "start" then
                Audio.PlayBtnClick()
                EnterHub()
            elseif hit == "volume" then
                Audio.PlayBtnClick()
                showVolumeMenu = true
            elseif hit == "howto" then
                Audio.PlayBtnClick()
                showHowTo = true
                howToScrollY = 0
            end
        elseif button == MOUSEB_RIGHT then
            -- 右键关闭任意覆盖层
            showHowTo = false
            showVolumeMenu = false
            pauseDragState.target = nil
        end
        return
    end

    if STATE == "hub" then
        if button == MOUSEB_LEFT then
            local mx, my = MousePos()
            local hit = Render.HitTestHub(mx, my, SW, SH)
            if hit == "start_raid" then
                Audio.PlayBtnClick()
                EnterLoadout()
            elseif hit == "back" then
                Audio.PlayBtnClick()
                STATE = "menu"
            elseif hit == "skill" then
                Audio.PlayBtnClick()
                -- 同步仓库中的材料到技能树状态
                skillTreeState.materials.combat   = SkillTree.CountMaterialInStash(stash, "废铁")
                skillTreeState.materials.looting  = SkillTree.CountMaterialInStash(stash, "史莱姆粘液")
                skillTreeState.materials.survival = SkillTree.CountMaterialInStash(stash, "破布")
                skillTreeHover = nil
                skillTreeScrollY = 0
                STATE = "skill_tree"
            end
        end
        return
    end

    if STATE == "skill_tree" then
        if button == MOUSEB_LEFT then
            local mx, my = MousePos()
            local hit = SkillTreeUI.HitTest(mx, my, SW, SH, skillTreeState, skillTreeScrollY)
            if hit == "__close" then
                Audio.PlayBtnClick()
                STATE = "hub"
            elseif hit then
                -- 尝试解锁节点
                local node = SkillTreeUI.FindNode(hit)
                if node then
                    local canUnlock, _ = SkillTree.CanUnlock(skillTreeState, node)
                    if canUnlock then
                        -- 从仓库扣除材料
                        local branchInfo = nil
                        for _, b in ipairs(SkillTree.BRANCHES) do
                            if b.id == node.branch then branchInfo = b; break end
                        end
                        if branchInfo then
                            local matOk = SkillTree.ConsumeMaterialFromStash(stash, branchInfo.material, node.materialCost)
                            if matOk then
                                SkillTree.Unlock(skillTreeState, node)
                                -- 更新材料计数显示
                                skillTreeState.materials[node.branch] = SkillTree.CountMaterialInStash(stash, branchInfo.material)
                                SkillTree.Save(skillTreeState)
                                Stash.Save(stash)
                                Audio.PlayBtnClick()
                            end
                        end
                    end
                end
            end
        end
        return
    end

    if STATE == "paused" then
        if button == MOUSEB_LEFT then
            local mx, my = MousePos()
            -- 先检测是否点中滑块
            local sliderHit = Render.HitTestPauseSlider(mx, my, SW, SH)
            if sliderHit then
                pauseDragState.target = sliderHit
                -- 立即更新一次音量（点击即生效）
                local v = Render.CalcSliderValue(mx, SW, SH, sliderHit)
                if sliderHit == "bgm" then
                    Audio.SetBGMVolume(v)
                else
                    Audio.SetSFXVolume(v)
                end
            else
                local hit = Render.HitTestPauseMenu(mx, my, SW, SH)
                if hit == "resume" then
                    Audio.PlayBtnClick()
                    STATE = "playing"
                    pauseHover = nil
                elseif hit == "menu" then
                    Audio.PlayBtnClick()
                    local bns = SkillTree.GetBonuses(skillTreeState); local dsCount = (bns.deathSave or 0) + (bns.safeSlots or 0)
                    Stash.OnRaidEnd(stash, player or {inventory={items={}}, equip={}}, false, dsCount)
                    Stash.Save(stash)
                    STATE = "menu"
                    pauseHover = nil
                end
            end
        end
        return
    end

    if STATE == "loadout" then
        local mx, my = MousePos()
        -- 懒计算布局（与渲染保持同步）
        if not loadoutLayout then
            loadoutLayout = Render.GetLoadoutLayout(stash, SW, SH)
        end

        if button == MOUSEB_LEFT then
            local action = Render.HitTestLoadout(loadoutLayout, mx, my, loadoutState)

            if action == "start" then
                Audio.PlayBtnClick()
                -- 出发前：将出售区未确认的物品归还仓库，防止丢失
                if loadoutState.sellPending and #loadoutState.sellPending > 0 then
                    for _, item in ipairs(loadoutState.sellPending) do
                        Stash.AddItem(stash, item)
                    end
                    loadoutState.sellPending = {}
                    Stash.Save(stash)
                end
                -- 每次出发都重新生成 buildState，确保不带残留进度
                buildState = Reward.NewBuildState()
                local whitePool = {}
                for _, item in ipairs(Reward.POOL) do
                    if item.rarity == 1 then table.insert(whitePool, item) end
                end
                pickChoices = Reward.Generate(buildState, whitePool, 3)
                pickHover   = nil
                STATE = "pick"

            elseif action == "back" then
                Audio.PlayBtnClick()
                -- 返回菜单：loadoutItems + sellPending 全部放回仓库
                for _, item in ipairs(loadoutState.loadoutItems) do Stash.AddItem(stash, item) end
                for _, item in ipairs(loadoutState.sellPending)   do Stash.AddItem(stash, item) end
                loadoutState.loadoutItems = {}
                loadoutState.sellPending  = {}
                EnterHub()

            elseif action == "tabSell" then
                loadoutState.activeTab = "sell"

            elseif action == "tabBuy" then
                loadoutState.activeTab = "buy"

            elseif action == "confirmSell" then
                -- 确认出售 / 取消多选
                local sold, earned = 0, 0
                local Inventory = require("Inventory")
                -- 技能树出售加价
                local sellBonusMult = 1 + (SkillTree.GetBonuses(skillTreeState).sellBonus or 0)
                for _, it in ipairs(loadoutState.sellPending) do
                    local bestVendor, bestPrice = nil, 0
                    for _, v in ipairs(Stash.VENDORS) do
                        local p = Stash.GetSellPrice(it, v)
                        if p > bestPrice then bestPrice = p; bestVendor = v.id end
                    end
                    if bestVendor then
                        local finalPrice = math.floor(bestPrice * sellBonusMult)
                        stash.money = stash.money + finalPrice
                        sold   = sold + 1
                        earned = earned + finalPrice
                    end
                end
                loadoutState.sellPending = {}
                loadoutState.multiSellMode = false
                if sold > 0 then
                    Audio.PlayCoin()
                    loadoutState.soldNotify = string.format("出售 %d 件，获得 💰%d", sold, earned)
                    loadoutState.soldTimer  = 2.5
                    Stash.Save(stash)
                end

            elseif action == "selectAll" then
                -- 全选出售：仓库所有物品移入 sellPending
                local Inventory = require("Inventory")
                local toSell = {}
                for _, entry in ipairs(stash.inv.items) do
                    table.insert(toSell, entry)
                end
                for _, entry in ipairs(toSell) do
                    Inventory.RemoveItem(stash.inv, entry.id)
                    table.insert(loadoutState.sellPending, entry)
                end
                if #toSell > 0 then loadoutLayout = nil end

            elseif action == "multiSell" then
                -- 切换多选出售模式
                loadoutState.multiSellMode = not loadoutState.multiSellMode

            elseif action == "sellDropZone" then
                -- 出售拖放区被点击：切换到出售 tab（拖放逻辑由 mouseUp 处理）
                loadoutState.activeTab = "sell"

            elseif type(action) == "table" then
                local act = action.action

                if act == "stashClick" then
                    -- 仓库格子按下 → 开始拖拽（物品留在仓库，松开时才决定去向）
                    local Inventory = require("Inventory")
                    local entry = Inventory.HitTest(stash.inv, action.gridCol, action.gridRow)
                    if entry then
                        loadoutState.dragItem = entry
                        loadoutState.dragX    = mx
                        loadoutState.dragY    = my
                        loadoutState.hoverZone = nil
                    end

                elseif act == "selectVendor" then
                    loadoutState.activeVendorId = action.vendorId
                    loadoutState.buyScrollY     = 0  -- 切换商人时重置滚动

                elseif act == "buyFrom" then
                    local ok = Stash.BuyFromVendor(stash, loadoutState.activeVendorId, action.vendorIdx)
                    if ok then
                        Audio.PlayPurchase()
                        loadoutLayout = nil
                        Stash.Save(stash)
                    else
                        Audio.PlayError()
                    end

                elseif act == "removeLoadout" then
                    -- 点击出战列表物品 → 放回仓库
                    local items = loadoutState.loadoutItems
                    for i, it in ipairs(items) do
                        if it.id == action.itemId then
                            table.remove(items, i)
                            Stash.AddItem(stash, it)
                            loadoutLayout = nil
                            break
                        end
                    end

                elseif act == "removePending" then
                    -- 点击待售列表行 → 放回仓库
                    local idx = action.itemIdx
                    if idx and loadoutState.sellPending[idx] then
                        local it = table.remove(loadoutState.sellPending, idx)
                        Stash.AddItem(stash, it)
                        loadoutLayout = nil
                    end

                elseif act == "mobileSection" then
                    -- 移动端切换 Tab（stash/trade/equip）
                    loadoutState.mobileSection = action.key
                    loadoutState.selectedItemId = nil

                elseif act == "mobileStashTap" then
                    -- 移动端仓库格子点击：单击查看信息，双击根据当前 Tab 执行不同操作
                    local Inventory = require("Inventory")
                    local entry = Inventory.HitTest(stash.inv, action.gridCol, action.gridRow)
                    if entry then
                        local now = time:GetElapsedTime()
                        local DOUBLE_TAP_THRESHOLD = 0.4 -- 400ms 内算双击
                        local isDoubleTap = (loadoutState.lastTapItemId == entry.id)
                            and (now - loadoutState.lastTapTime < DOUBLE_TAP_THRESHOLD)

                        if isDoubleTap then
                            local section = loadoutState.mobileSection or "shop"
                            if section == "shop" then
                                -- 双击出售：移入待售队列
                                Inventory.RemoveItem(stash.inv, entry.id)
                                table.insert(loadoutState.sellPending, entry)
                                loadoutLayout = nil
                            else
                                -- 双击带上/装备：toggle loadoutItems
                                local items = loadoutState.loadoutItems
                                local found = false
                                for i, it in ipairs(items) do
                                    if it.id == entry.id then
                                        table.remove(items, i)
                                        Stash.AddItem(stash, it)
                                        loadoutLayout = nil
                                        found = true
                                        break
                                    end
                                end
                                if not found then
                                    Inventory.RemoveItem(stash.inv, entry.id)
                                    table.insert(items, entry)
                                    loadoutLayout = nil
                                end
                            end
                            Audio.PlayBtnClick()
                            loadoutState.selectedItemId = nil
                            loadoutState.lastTapItemId = nil
                            loadoutState.lastTapTime = 0
                        else
                            -- 单击 → 选中查看信息
                            loadoutState.selectedItemId = entry.id
                            loadoutState.lastTapItemId = entry.id
                            loadoutState.lastTapTime = now
                        end
                    else
                        -- 点击空格 → 取消选中
                        loadoutState.selectedItemId = nil
                    end
                end
            end

        elseif button == MOUSEB_RIGHT then
            -- 右键：出战列表最后一件放回仓库
            local items = loadoutState.loadoutItems
            if #items > 0 then
                local item = table.remove(items)
                Stash.AddItem(stash, item)
                loadoutLayout = nil
            end
        end
        return
    end

    if STATE == "gameover" or STATE == "win" then
        if button == MOUSEB_LEFT then
            Audio.PlayBtnClick()
            local bns = SkillTree.GetBonuses(skillTreeState); local dsCount = (bns.deathSave or 0) + (bns.safeSlots or 0)
            Stash.OnRaidEnd(stash, player or {inventory={items={}}, equip={}}, raidExtracted, dsCount)
            Stash.Save(stash)
            EnterLoadout()
        end
        return
    end

    if STATE == "extract_choice" then
        if button == MOUSEB_LEFT then
            if extractHover == "evacuate" then
                raidExtracted = true   -- 鼠标确认撤离，保存物品
                Audio.PlayBtnClick()
                Audio.PlayExtractionSuccess()
                Audio.PlayBGM("extract")
                STATE = "win"
            elseif extractHover == "continue" then
                Audio.PlayBtnClick()
                -- 第1层和Boss层（5/10/15）继续深入前弹出确认
                extractHover = nil
                STATE = "deep_confirm"
            end
        end
        return
    end

    if STATE == "deep_confirm" then
        if button == MOUSEB_LEFT then
            local mx, my = MousePos()
            local choice = Render.GetDeepConfirmHover(mx, my, SW, SH)
            if choice == "confirm" then
                Audio.PlayBtnClick()
                EnterRewardState()
            elseif choice == "cancel" then
                Audio.PlayBtnClick()
                extractHover = nil
                STATE = "extract_choice"
            end
        end
        return
    end

    if STATE == "pick" then
        if button == MOUSEB_LEFT and pickHover and pickChoices then
            local chosen = pickChoices[pickHover]
            if chosen then
                if chosen.id == "assist_reroll" then
                    -- "重选"卡：刷新出发三选一选项（排除重选卡自身避免无限循环）
                    Audio.PlayUpgradeOK()
                    local whitePool = {}
                    for _, item in ipairs(Reward.POOL) do
                        if item.rarity == 1 and item.id ~= "assist_reroll" then
                            table.insert(whitePool, item)
                        end
                    end
                    pickChoices = Reward.Generate(buildState, whitePool, 3)
                    pickHover   = nil
                else
                    Audio.PlayUpgradeOK()
                    local savedChoice = chosen
                    pickChoices = nil
                    pickHover   = nil
                    -- 先 InitGame 创建 player，再把效果应用到已存在的 player 上
                    InitGame()
                    Reward.Pick(buildState, savedChoice, player)
                end
            end
        end
        return
    end

    if STATE == "reward" then
        -- 刷新按钮点击
        if button == MOUSEB_LEFT and rewardHover == -1 and rewardChoices then
            if buildState.rerollsLeft and buildState.rerollsLeft > 0 then
                buildState.rerollsLeft = buildState.rerollsLeft - 1
                rewardChoices = Reward.Generate(buildState)
                rewardHover   = nil
            end
            return
        end
        if button == MOUSEB_LEFT and rewardHover and rewardChoices then
            local chosen = rewardChoices[rewardHover]
            if chosen then
                Audio.PlayUpgradeOK()
                -- 辅助牌特殊处理
                if chosen.id == "assist_reroll" then
                    -- 立即刷新：拾取该卡，从临时池中排除 assist_reroll，重新生成选项
                    Reward.Pick(buildState, chosen, player)
                    local noRerollPool = {}
                    for _, item in ipairs(Reward.POOL) do
                        if item.id ~= "assist_reroll" then
                            table.insert(noRerollPool, item)
                        end
                    end
                    rewardChoices = Reward.Generate(buildState, noRerollPool)
                    rewardHover   = nil
                elseif chosen.id == "assist_pick2" then
                    -- 全选：依次 Pick 三张，然后进层
                    for _, item in ipairs(rewardChoices) do
                        Reward.Pick(buildState, item, player)
                    end
                    rewardChoices = nil
                    rewardHover   = nil
                    AdvanceFloor()
                elseif chosen.id == "assist_rarity_up" then
                    -- 品质提升：收集当前三张卡的稀有度，每张+1，从对应新稀有度池重新抽取
                    local rarities = {}
                    local oldIds = {}
                    for _, item in ipairs(rewardChoices) do
                        rarities[#rarities + 1] = math.min(4, (item.rarity or 1) + 1)
                        oldIds[item.id] = true
                    end
                    local newChoices = Reward.GenerateWithRarities(buildState, rarities, oldIds)
                    if #newChoices > 0 then
                        rewardChoices = newChoices
                    end
                    rewardHover = nil
                    -- 不进层，让玩家再选一次
                elseif chosen.id == "assist_remove" then
                    -- 排除：随机封禁一个本次三选一中出现的流派标签（排除辅助自身）
                    local toExclude = nil
                    for _, item in ipairs(rewardChoices) do
                        if item.id ~= chosen.id and item.tags then
                            for _, tag in ipairs(item.tags) do
                                if tag ~= "assist" then
                                    toExclude = tag; break
                                end
                            end
                        end
                        if toExclude then break end
                    end
                    if toExclude then
                        buildState.excludedTags[toExclude] = true
                        local pinfo = Reward.PATH_INFO[toExclude]
                        local pname = pinfo and pinfo.name or toExclude
                        table.insert(buildState.pendingNotifications, {
                            text  = "❌ 已排除流派：" .. pname .. " — 本局不再出现",
                            timer = 3.5,
                            color = { 200, 80, 80 },
                        })
                    end
                    rewardChoices = nil
                    rewardHover   = nil
                    AdvanceFloor()
                else
                    -- 普通奖励（含 assist_reroll_2 / assist_choice_4 的直接 effect 版）
                    Reward.Pick(buildState, chosen, player)
                    if chosen.id == "assist_reroll_2" then
                        buildState.rerollsLeft = (buildState.rerollsLeft or 0) + 2
                    elseif chosen.id == "assist_choice_4" then
                        -- 修正：effect(p) 写的是 player.nextPickCount，但 Generate 读的是 buildState.nextPickCount
                        buildState.nextPickCount = (buildState.nextPickCount or 3) + 1
                    end
                    rewardChoices = nil
                    rewardHover   = nil
                    -- 立即弹出本次 Pick 触发的通知
                    local n = Reward.PopNotification(buildState)
                    if n then
                        n.totalTime = n.timer
                        buildNotif  = n
                    end
                    AdvanceFloor()
                end
            end
        end
        return
    end

    -- playing
    if button == MOUSEB_LEFT then
        -- 医疗快用栏点击（PC 鼠标，背包/搜索面板未开时优先拦截）
        -- 手机端触摸由 HandleTouchBegin 单独处理
        if not isMobile and not player.bagOpen and not player.searchOpen then
            local mx, my = MousePos()
            local medSlot = Render.HitTestMedBar(mx, my, SW, SH, false)
            if medSlot then
                Player.UseMedSlot(player, medSlot)
                return
            end
        end

        -- 标记左键持续按下（用于连射）
        mouseLeftHeld = true

        -- 背包面板开启时：处理面板点击
        if player.bagOpen then
            local mx, my = MousePos()
            local lp = Render.GetInventoryPanelLayout(player, SW, SH, isMobile)

            -- 关闭按钮（PC 端右上角 ×）
            local cb = lp.closeBtn
            if cb and mx >= cb.x and mx <= cb.x+cb.w and my >= cb.y and my <= cb.y+cb.h then
                player.bagOpen = false
                mouseLeftHeld = false
                Audio.PlayPanelClose()
                return
            end

            local hit = Render.HitTestInventoryPanel(lp, player, mx, my)
            if hit then  -- 非 nil = 点击落在面板内
                if hit.action == "equipSlot" then
                    -- 装备槽：若有装备则启动拖拽（拖到背包卸下）
                    local eq = player.equip and player.equip[hit.slot]
                    if eq then
                        local ds = player.bagDragState
                        ds.dragItem = {
                            itype  = hit.slot,
                            data   = eq,
                            name   = eq.name,
                            icon   = eq.icon or "🛡️",
                            rarity = eq.rarity or 1,
                            value  = eq.value  or 0,
                        }
                        ds.dragX          = mx
                        ds.dragY          = my
                        ds.srcInv         = nil
                        ds.srcType        = "equipSlot"
                        ds.srcEquipSlot   = hit.slot
                        ds.srcWeaponKey   = nil
                        ds.hoverWeaponSlot = nil
                        ds.hoverBagGrid    = nil
                    end
                elseif hit.action == "weaponSlot" then
                    -- 武器槽点击：若该槽有武器（非刀）则开始从武器槽拖拽
                    local wpnKey = hit.key
                    if wpnKey ~= "knife" and player[wpnKey] then
                        local wpn = player[wpnKey]
                        local ds  = player.bagDragState
                        -- 构造临时 entry 用于 Ghost 显示
                        ds.dragItem      = {
                            itype  = "weapon",
                            data   = wpn,
                            name   = wpn.name,
                            icon   = wpn.icon or "🔫",
                            rarity = wpn.rarity or 1,
                            value  = wpn.value  or 0,
                        }
                        ds.dragX          = mx
                        ds.dragY          = my
                        ds.srcInv         = nil
                        ds.srcType        = "weaponSlot"
                        ds.srcWeaponKey   = wpnKey
                        ds.hoverWeaponSlot = nil
                        ds.hoverBagGrid    = nil
                    end

                elseif hit.action == "bagItem" then
                    -- 武器物品：开始拖拽
                    if hit.entry and hit.entry.itype == "weapon" then
                        local ds = player.bagDragState
                        ds.dragItem        = hit.entry
                        ds.dragX           = mx
                        ds.dragY           = my
                        ds.srcInv          = hit.srcInv
                        ds.srcType         = "inv"
                        ds.srcWeaponKey    = nil
                        ds.hoverWeaponSlot = nil
                        ds.hoverBagGrid    = nil
                    else
                        -- 非武器：装备/换装逻辑不变
                        local ok = Player.EquipFromInventory(player, hit.id)
                        if ok then
                            Audio.PlayEquip()
                            player.notification = { text="已装备: "..(hit.name or "物品"), timer=1.2 }
                            player.lootValue = require("Inventory").TotalValue(player.inventory)
                        else
                            Audio.PlayError()
                            player.notification = { text="无法装备", timer=1.2 }
                        end
                    end
                end
                return  -- 吞掉点击，不触发射击
            end
            -- hit 为 nil = 点击在面板外，继续（可能触发射击）
        end

        -- 搜索面板开启时：处理面板点击
        if player.searchOpen and searchPanelLayout then
            local mx, my = MousePos()
            local lp = searchPanelLayout

            -- 关闭按钮（PC 端右上角 ×）
            local cb = lp.closeBtn
            if cb and mx >= cb.x and mx <= cb.x+cb.w and my >= cb.y and my <= cb.y+cb.h then
                Player.CloseSearch(player)
                player.searchOpen  = false
                searchPanelLayout  = nil
                mouseLeftHeld = false
                Audio.PlayPanelClose()
                return
            end

            -- 点击"智能拾取"按钮（⚡）
            local alBtn = lp.autoLootBtn
            if alBtn and mx >= alBtn.x and mx <= alBtn.x+alBtn.w and my >= alBtn.y and my <= alBtn.y+alBtn.h then
                Audio.PlayPickup()
                Player.AutoLoot(player)
                local ss = player.searchState
                if ss.container and ss.container._box then
                    World.SyncBoxLoot(ss.container._box, ss.containerInv)
                end
                searchPanelLayout = Render.GetSearchPanelLayout(
                    player.searchState, player.inventory, SW, SH)
                return
            end

            -- 点击"全部取走"按钮
            local btn = lp.takeAllBtn
            if mx >= btn.x and mx <= btn.x+btn.w and my >= btn.y and my <= btn.y+btn.h then
                Audio.PlayPickup()
                Player.SearchTakeAll(player)
                -- 同步剩余物品回箱子缓存
                local ss = player.searchState
                if ss.container and ss.container._box then
                    World.SyncBoxLoot(ss.container._box, ss.containerInv)
                end
                searchPanelLayout = Render.GetSearchPanelLayout(
                    player.searchState, player.inventory, SW, SH)
                return
            end

            -- 点击容器网格 → 取走物品
            local cl = lp.container
            if mx >= cl.gridX and mx <= cl.gridX + cl.w*cl.cellSize
            and my >= cl.gridY and my <= cl.gridY + cl.h*cl.cellSize then
                local entry = Search.HitTestPanel(
                    player.searchState, player.inventory, "container", mx, my, lp)
                if entry then
                    Audio.PlayPickup()
                    Player.SearchTakeItem(player, entry.id)
                    -- 同步剩余物品回箱子缓存
                    local ss = player.searchState
                    if ss.container and ss.container._box then
                        World.SyncBoxLoot(ss.container._box, ss.containerInv)
                    end
                    searchPanelLayout = Render.GetSearchPanelLayout(
                        player.searchState, player.inventory, SW, SH)
                end
                return
            end

            -- 点击玩家背包网格 → 放入容器（丢弃）
            local pl = lp.player
            if mx >= pl.gridX and mx <= pl.gridX + pl.w*pl.cellSize
            and my >= pl.gridY and my <= pl.gridY + pl.h*pl.cellSize then
                local entry = Search.HitTestPanel(
                    player.searchState, player.inventory, "player", mx, my, lp)
                if entry then
                    Search.PutItem(player.searchState, entry.id, player.inventory)
                    searchPanelLayout = Render.GetSearchPanelLayout(
                        player.searchState, player.inventory, SW, SH)
                end
                return
            end

            -- 面板内其他区域：吞掉事件，不触发射击
            if mx >= lp.panelX and mx <= lp.panelX+lp.panelW
            and my >= lp.panelY and my <= lp.panelY+lp.panelH then
                return
            end
            return  -- 面板开启时全部拦截左键（避免误射）
        end

        -- 单击开枪（施法中禁用）
        if not Player.IsCasting(player) then
            Player.TryShoot(player, bullets)
        end
    end
end

function HandleMouseButtonUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_LEFT then
        mouseLeftHeld = false

        -- 菜单/暂停音量滑块：松开时结束拖动
        if pauseDragState.target then
            pauseDragState.target = nil
        end

        -- 背包拖拽：松开时根据来源类型和悬停目标决定操作
        if STATE == "playing" and player and player.bagOpen
        and player.bagDragState and player.bagDragState.dragItem then
            local ds      = player.bagDragState
            local entry   = ds.dragItem
            local wpnKey  = ds.hoverWeaponSlot   -- "primaryGun" | "secondaryGun" | nil
            local bagGrid = ds.hoverBagGrid       -- {col, row} | nil
            local srcType = ds.srcType            -- "inv" | "weaponSlot" | "equipSlot"
            local srcWpnK = ds.srcWeaponKey       -- 从哪个武器槽拖起的
            local srcEqSlot = ds.srcEquipSlot     -- 从哪个装备槽拖起的

            -- 清空拖拽状态
            ds.dragItem        = nil
            ds.hoverWeaponSlot = nil
            ds.hoverBagGrid    = nil
            ds.srcType         = nil
            ds.srcWeaponKey    = nil
            ds.srcEquipSlot    = nil

            local Inventory = require("Inventory")

            if srcType == "weaponSlot" then
                -- ── 从武器槽发起的拖拽 ──────────────────────────────────
                local srcWpn = player[srcWpnK]
                if not srcWpn then return end

                if wpnKey then
                    -- 目标：另一个武器槽 → 主副武器互换
                    local dstWpn = player[wpnKey]   -- 可以是 nil
                    player[srcWpnK] = dstWpn
                    player[wpnKey]  = srcWpn
                    local Player = require("Player")
                    Player.syncWeaponRef(player)
                    local labelSrc = (srcWpnK == "primaryGun") and "主武器" or "副武器"
                    local labelDst = (wpnKey  == "primaryGun") and "主武器" or "副武器"
                    player.notification = {
                        text  = labelSrc .. " ⇄ " .. labelDst .. " 已互换",
                        timer = 1.5
                    }
                    Audio.PlayEquip()
                    player.lootValue = Inventory.TotalValue(player.inventory)

                elseif bagGrid then
                    -- 目标：背包网格 → 武器卸装并放回背包
                    local item = {
                        itype  = "weapon",
                        data   = srcWpn,
                        name   = srcWpn.name,
                        icon   = srcWpn.icon or "🔫",
                        rarity = srcWpn.rarity or 1,
                        value  = srcWpn.value  or 0,
                    }
                    -- 优先放在悬停格子，放不下则自动寻位
                    local placed = Inventory.PlaceItem(player.inventory, item,
                                       bagGrid.col, bagGrid.row, false)
                    if not placed then
                        placed = Inventory.AutoPlace(player.inventory, item)
                    end
                    if placed then
                        player[srcWpnK] = nil
                        local Player = require("Player")
                        Player.syncWeaponRef(player)
                        player.notification = {
                            text  = srcWpn.name .. " 已放回背包",
                            timer = 1.2
                        }
                        Audio.PlayEquip()
                        player.lootValue = Inventory.TotalValue(player.inventory)
                    else
                        player.notification = { text = "背包已满", timer = 1.2 }
                        Audio.PlayError()
                    end
                end
                return
            end

            if srcType == "equipSlot" then
                -- ── 从装备槽发起的拖拽 ──────────────────────────────────
                local eq = player.equip and player.equip[srcEqSlot]
                if not eq then return end

                if bagGrid then
                    -- 目标：背包网格 → 装备卸下并放入背包
                    local item = {
                        itype  = srcEqSlot,
                        data   = eq,
                        name   = eq.name,
                        icon   = eq.icon or "🛡️",
                        rarity = eq.rarity or 1,
                        value  = eq.value  or 0,
                    }
                    local placed = Inventory.PlaceItem(player.inventory, item,
                                       bagGrid.col, bagGrid.row, false)
                    if not placed then
                        placed = Inventory.AutoPlace(player.inventory, item)
                    end
                    if placed then
                        player.equip[srcEqSlot] = nil
                        -- 如果卸下的是背包，需要同步背包容量
                        if srcEqSlot == "bag" then
                            local Player = require("Player")
                            Player.UpdateBagSize(player)
                        end
                        player.notification = {
                            text  = eq.name .. " 已放回背包",
                            timer = 1.2
                        }
                        Audio.PlayEquip()
                        player.lootValue = Inventory.TotalValue(player.inventory)
                    else
                        player.notification = { text = "背包已满", timer = 1.2 }
                        Audio.PlayError()
                    end
                end
                return
            end

            -- ── 从背包发起的拖拽 ──────────────────────────────────
            if wpnKey then
                -- 目标：武器槽 → 从背包装备武器到该槽
                local srcInv = player.inventory
                local newWpn = entry.data
                if newWpn then
                    local oldWpn = player[wpnKey]
                    -- 先移除新武器腾出空间
                    local removed = Inventory.RemoveItem(srcInv, entry.id)
                    if not removed then
                        -- entry.id 已失效（可能被 AutoSort 重排），不执行操作
                        player.notification = { text = "操作失败，请重试", timer = 1.2 }
                        Audio.PlayError()
                    elseif oldWpn and oldWpn.key ~= "Knife" then
                        local oldItem = {
                            itype  = "weapon",
                            data   = oldWpn,
                            name   = oldWpn.name,
                            icon   = oldWpn.icon,
                            rarity = oldWpn.rarity or 1,
                            value  = oldWpn.value  or 0,
                        }
                        local iw, ih = Inventory.GetSize(oldItem)
                        local sx, sy = Inventory.FindSpace(srcInv, iw, ih)
                        if not sx then
                            -- 放不下，还原：把新武器放回背包，取消操作
                            Inventory.AutoPlace(srcInv, entry)
                            player.notification = { text = "背包空间不足，无法换枪", timer = 1.5 }
                            Audio.PlayError()
                        else
                            -- 能放下，执行交换
                            Inventory.AutoPlace(srcInv, oldItem)
                            player[wpnKey] = newWpn
                            local Player = require("Player")
                            Player.syncWeaponRef(player)
                            player.notification = {
                                text  = (wpnKey == "primaryGun" and "主武器" or "副武器")
                                        .. " → " .. newWpn.name,
                                timer = 1.5
                            }
                            Audio.PlayEquip()
                            player.lootValue = Inventory.TotalValue(player.inventory)
                        end
                    else
                        -- 无旧武器或是刀，直接装备
                        player[wpnKey] = newWpn
                        local Player = require("Player")
                        Player.syncWeaponRef(player)
                        player.notification = {
                            text  = (wpnKey == "primaryGun" and "主武器" or "副武器")
                                    .. " → " .. newWpn.name,
                            timer = 1.5
                        }
                        Audio.PlayEquip()
                        player.lootValue = Inventory.TotalValue(player.inventory)
                    end
                end
            end
            -- 无论是否换装成功都返回（已处理过拖拽）
            return
        end

        -- loadout 拖拽：松开鼠标时根据 hoverZone 决定物品去向
        if STATE == "loadout" and loadoutState.dragItem then
            local entry = loadoutState.dragItem
            local zone  = loadoutState.hoverZone
            loadoutState.dragItem  = nil
            loadoutState.hoverZone = nil

            if zone == "sell" then
                -- 从仓库移入待售队列
                local Inventory = require("Inventory")
                Inventory.RemoveItem(stash.inv, entry.id)
                table.insert(loadoutState.sellPending, entry)
                loadoutLayout = nil

            elseif zone == "loadout" then
                -- 从仓库移入出战装备列表
                local Inventory = require("Inventory")
                Inventory.RemoveItem(stash.inv, entry.id)
                table.insert(loadoutState.loadoutItems, entry)
                loadoutLayout = nil

            -- else: 拖拽取消，物品留在仓库
            end
        end
    end
end

-- ============================================================================
-- 移动端触控事件
-- ============================================================================

-- 统一处理"一次点击/触碰"动作（TouchBegin 或 鼠标模拟，touchId=-1）
local function HandleMobileTap(touchId, x, y)
    if not mobileLayout then return end

    -- 撤离点检测（仅 playing 且存活时有意义）
    local nearExit = false
    if STATE == "playing" and player and not player.dead and World.IsExitCell then
        local col, row = World.WorldToTile(player.x, player.y)
        nearExit = World.IsExitCell(col, row) and not World.exitLocked
    end

    local hit = MobileHUD.OnTouchBegin(mobileLayout, touchId, x, y, nearExit, SW)
    -- 注意：只有 playing 状态才需要 MobileHUD hit 才能继续
    -- paused / gameover / win / menu 状态下 MobileHUD 不可见，hit 为 nil，不能提前返回

    if STATE == "playing" then
        if not hit then return end   -- playing 下没命中 HUD 按钮则忽略
        if hit == "roll" then
            if not player.bagOpen and not player.searchOpen then
                Player.TryRoll(player, keys)
            end
        elseif hit == "reload" then
            if not Player.IsCasting(player) then
                Player.Reload(player)
                Audio.PlayWeaponReload(player.weapon and player.weapon.name or "")
            end
        elseif hit == "search" then
            -- 搜索面板开启时：关闭；否则尝试互动
            if player.searchOpen then
                Player.CloseSearch(player)
                player.searchOpen = false
                searchPanelLayout = nil
                Audio.PlayPanelClose()
            elseif not player.bagOpen then
                Player.TryInteract(player, World)
                if player.searchOpen then
                    searchPanelLayout = Render.GetSearchPanelLayout(
                        player.searchState, player.inventory, SW, SH)
                    local ss = player.searchState
                    if ss.container and ss.container._box then
                        World.MarkBoxOpened(ss.container._box)
                    end
                end
            end
        elseif hit == "bag" then
            if not player.searchOpen then
                player.bagOpen = not player.bagOpen
                if player.bagOpen then Audio.PlayPanelOpen() else Audio.PlayPanelClose() end
            end
        elseif hit == "evac" then
            -- 站在撤离格上且出口未锁：启动撤离计时
            if nearExit and not Player.IsCasting(player) and not player.searchOpen then
                if player.extracting <= 0 then
                    player.extracting = 0.001
                    player.extracted  = false
                end
            end
        elseif hit == "swap" then
            Player.SwapWeapon(player)
            Audio.PlayWeaponSwap()
        elseif hit == "pause" then
            Audio.PlayBtnClick()
            STATE = "paused"
            pauseHover = nil
            keys = { w=false, a=false, s=false, d=false }
            mouseLeftHeld = false
            mobileAttackHeld = false
            MobileHUD.ResetAll()
        end
        -- attack 按住状态在 HandleUpdate 中轮询

    elseif STATE == "paused" then
        -- 先检测暂停面板滑块（优先级最高）
        local sliderHit = Render.HitTestPauseSlider(x, y, SW, SH)
        if sliderHit then
            pauseDragState.target = sliderHit
            local v = Render.CalcSliderValue(x, SW, SH, sliderHit)
            if sliderHit == "bgm" then Audio.SetBGMVolume(v) else Audio.SetSFXVolume(v) end
        else
            -- 检测暂停面板按钮
            local panelHit = Render.HitTestPauseMenu(x, y, SW, SH)
            if panelHit == "resume" then
                Audio.PlayBtnClick()
                STATE = "playing"
                pauseHover = nil
            elseif panelHit == "menu" then
                Audio.PlayBtnClick()
                local bns = SkillTree.GetBonuses(skillTreeState); local dsCount = (bns.deathSave or 0) + (bns.safeSlots or 0)
                Stash.OnRaidEnd(stash, player or {inventory={items={}}, equip={}}, false, dsCount)
                Stash.Save(stash)
                STATE = "menu"
                pauseHover = nil
                Audio.PlayBGM("menu")
            end
        end

    elseif STATE == "gameover" or STATE == "win" then
        -- 点击屏幕中央继续按钮区域
        local cx, cy = SW * 0.5, SH * 0.88
        local r = math.min(SW, SH) * 0.075
        local dx, dy = x - cx, y - cy
        if dx*dx + dy*dy <= r*r * 2.5 then
            Audio.PlayBtnClick()
            local bns = SkillTree.GetBonuses(skillTreeState); local dsCount = (bns.deathSave or 0) + (bns.safeSlots or 0)
            Stash.OnRaidEnd(stash, player or {inventory={items={}}, equip={}}, raidExtracted, dsCount)
            Stash.Save(stash)
            EnterLoadout()
        end

    elseif STATE == "extract_choice" then
        -- 手机端直接按点击坐标判断选择（无需悬停态）
        local choice = Render.GetExtractChoiceHover(x, y, SW, SH)
        if choice == "evacuate" then
            raidExtracted = true   -- 触摸确认撤离，保存物品
            Audio.PlayBtnClick()
            Audio.PlayExtractionSuccess()
            Audio.PlayBGM("extract")
            STATE = "win"
        elseif choice == "continue" then
            Audio.PlayBtnClick()
            -- 第1层和Boss层继续深入前弹出确认
            extractHover = nil
            STATE = "deep_confirm"
        end

    elseif STATE == "deep_confirm" then
        local dcChoice = Render.GetDeepConfirmHover(x, y, SW, SH)
        if dcChoice == "confirm" then
            Audio.PlayBtnClick()
            EnterRewardState()
        elseif dcChoice == "cancel" then
            Audio.PlayBtnClick()
            extractHover = nil
            STATE = "extract_choice"
        end

    elseif STATE == "pick" then
        -- 手机端：出发三选一
        if pickChoices then
            local idx = Render.GetRewardHoverIndex(x, y, pickChoices, SW, SH)
            if idx then
                local chosen = pickChoices[idx]
                if chosen then
                    if chosen.id == "assist_reroll" then
                        -- "重选"卡：刷新出发三选一选项
                        Audio.PlayUpgradeOK()
                        local whitePool = {}
                        for _, item in ipairs(Reward.POOL) do
                            if item.rarity == 1 and item.id ~= "assist_reroll" then
                                table.insert(whitePool, item)
                            end
                        end
                        pickChoices = Reward.Generate(buildState, whitePool, 3)
                        pickHover   = nil
                    else
                        Audio.PlayUpgradeOK()
                        local savedChoice = chosen
                        pickChoices = nil
                        pickHover   = nil
                        InitGame()
                        Reward.Pick(buildState, savedChoice, player)
                    end
                end
            end
        end

    elseif STATE == "reward" then
        -- 手机端直接按点击坐标判断选择的奖励卡（无需悬停态）
        if rewardChoices then
            -- 先判断刷新按钮
            if Render.IsRerollButtonHit(x, y, SW, SH, buildState.rerollsLeft) then
                buildState.rerollsLeft = buildState.rerollsLeft - 1
                rewardChoices = Reward.Generate(buildState)
                rewardHover   = nil
                return
            end
            local idx = Render.GetRewardHoverIndex(x, y, rewardChoices, SW, SH)
            if idx then
                local chosen = rewardChoices[idx]
                if chosen then
                    Audio.PlayUpgradeOK()
                    -- 辅助牌特殊处理（与 PC 端逻辑一致）
                    if chosen.id == "assist_reroll" then
                        -- 立即刷新：拾取该卡，从临时池中排除 assist_reroll，重新生成选项
                        Reward.Pick(buildState, chosen, player)
                        local noRerollPool = {}
                        for _, item in ipairs(Reward.POOL) do
                            if item.id ~= "assist_reroll" then
                                table.insert(noRerollPool, item)
                            end
                        end
                        rewardChoices = Reward.Generate(buildState, noRerollPool)
                        rewardHover   = nil
                    elseif chosen.id == "assist_pick2" then
                        for _, item in ipairs(rewardChoices) do
                            Reward.Pick(buildState, item, player)
                        end
                        rewardChoices = nil; rewardHover = nil
                        AdvanceFloor()
                    elseif chosen.id == "assist_rarity_up" then
                        local rarities = {}
                        local oldIds = {}
                        for _, item in ipairs(rewardChoices) do
                            rarities[#rarities + 1] = math.min(4, (item.rarity or 1) + 1)
                            oldIds[item.id] = true
                        end
                        local newChoices = Reward.GenerateWithRarities(buildState, rarities, oldIds)
                        if #newChoices > 0 then
                            rewardChoices = newChoices
                        end
                        rewardHover = nil
                    elseif chosen.id == "assist_remove" then
                        local toExclude = nil
                        for _, item in ipairs(rewardChoices) do
                            if item.id ~= chosen.id and item.tags then
                                for _, tag in ipairs(item.tags) do
                                    if tag ~= "assist" then toExclude = tag; break end
                                end
                            end
                            if toExclude then break end
                        end
                        if toExclude then
                            buildState.excludedTags[toExclude] = true
                            local pinfo = Reward.PATH_INFO[toExclude]
                            local pname = pinfo and pinfo.name or toExclude
                            table.insert(buildState.pendingNotifications, {
                                text  = "❌ 已排除流派：" .. pname .. " — 本局不再出现",
                                timer = 3.5, color = { 200, 80, 80 },
                            })
                        end
                        rewardChoices = nil; rewardHover = nil
                        AdvanceFloor()
                    else
                        Reward.Pick(buildState, chosen, player)
                        if chosen.id == "assist_reroll_2" then
                            buildState.rerollsLeft = (buildState.rerollsLeft or 0) + 2
                        elseif chosen.id == "assist_choice_4" then
                            buildState.nextPickCount = (buildState.nextPickCount or 3) + 1
                        end
                        rewardChoices = nil; rewardHover = nil
                        local n = Reward.PopNotification(buildState)
                        if n then n.totalTime = n.timer; buildNotif = n end
                        AdvanceFloor()
                    end
                end
            end
        end

    elseif STATE == "menu" then
        -- 覆盖层打开时
        if showHowTo then
            -- 开始拖动滚动（TouchEnd 判断是否为点击关闭）
            howToDragY = y
            howToDragStartScroll = howToScrollY
        elseif showVolumeMenu then
            local sliderHit = Render.HitTestPauseSlider(x, y, SW, SH)
            if sliderHit then
                local v = Render.CalcSliderValue(x, SW, SH, sliderHit)
                if sliderHit == "bgm" then Audio.SetBGMVolume(v) else Audio.SetSFXVolume(v) end
            else
                showVolumeMenu = false
            end
        else
            -- 路由三个按钮
            local menuHit = Render.HitTestMenu(x, y, SW, SH)
            if menuHit == "start" then
                Audio.PlayBtnClick()
                EnterHub()
            elseif menuHit == "volume" then
                Audio.PlayBtnClick()
                showVolumeMenu = true
            elseif menuHit == "howto" then
                Audio.PlayBtnClick()
                showHowTo = true
                howToScrollY = 0
            end
        end

    elseif STATE == "hub" then
        local hit = Render.HitTestHub(x, y, SW, SH)
        if hit == "start_raid" then
            Audio.PlayBtnClick()
            EnterLoadout()
        elseif hit == "back" then
            Audio.PlayBtnClick()
            STATE = "menu"
        elseif hit == "skill" then
            Audio.PlayBtnClick()
            -- 同步仓库中的材料到技能树状态
            skillTreeState.materials.combat   = SkillTree.CountMaterialInStash(stash, "废铁")
            skillTreeState.materials.looting  = SkillTree.CountMaterialInStash(stash, "史莱姆粘液")
            skillTreeState.materials.survival = SkillTree.CountMaterialInStash(stash, "破布")
            skillTreeHover = nil
            skillTreeScrollY = 0
            STATE = "skill_tree"
        end

    elseif STATE == "skill_tree" then
        -- 如果是拖动滚动操作则跳过点击处理
        if skillTreeDrag.moved then return end
        local hit = SkillTreeUI.HitTest(x, y, SW, SH, skillTreeState, skillTreeScrollY)
        if hit == "__close" then
            Audio.PlayBtnClick()
            STATE = "hub"
        elseif hit then
            -- 尝试解锁节点
            local node = SkillTreeUI.FindNode(hit)
            if node then
                local canUnlock, _ = SkillTree.CanUnlock(skillTreeState, node)
                if canUnlock then
                    local branchInfo = nil
                    for _, b in ipairs(SkillTree.BRANCHES) do
                        if b.id == node.branch then branchInfo = b; break end
                    end
                    if branchInfo then
                        local matOk = SkillTree.ConsumeMaterialFromStash(stash, branchInfo.material, node.materialCost)
                        if matOk then
                            SkillTree.Unlock(skillTreeState, node)
                            skillTreeState.materials[node.branch] = SkillTree.CountMaterialInStash(stash, branchInfo.material)
                            SkillTree.Save(skillTreeState)
                            Stash.Save(stash)
                            Audio.PlayBtnClick()
                        end
                    end
                end
            end
        end
    end
end

function HandleTouchBegin(eventType, eventData)
    local touchX = math.floor(eventData["X"]:GetInt() / (uiDPR or 1))
    local touchY = math.floor(eventData["Y"]:GetInt() / (uiDPR or 1))
    -- 左上角连点 5 次激活开发者面板
    Dev.HandleTap(touchX, touchY)

    if not isMobile or not mobileLayout then return end
    local touchId = eventData["TouchID"]:GetInt()
    local x = touchX
    local y = touchY

    -- 备战区：购买面板列表触摸滚动拖拽（移动端 trade tab 下）
    -- 注意：这里只记录起始位置，不立即 return
    -- 真正的"是否为滚动"在 TouchMove/TouchEnd 中根据位移量判断
    if STATE == "loadout" and (loadoutState.activeTab or "sell") == "buy" then
        local lp = loadoutLayout
        local okSection = (not lp) or (not lp.isMobile) or (loadoutState.mobileSection == "shop")
        if lp and okSection
        and y >= lp.buyListY0 and y <= lp.buyListY0 + lp.buyListH
        and x >= lp.midX and x <= lp.midX + lp.midW then
            buyScrollDrag = { active=true, touchId=touchId,
                              startY=y, startScrollY=loadoutState.buyScrollY or 0,
                              startX=x, moved=false }
            -- 购买逻辑完全交给 TouchEnd（轻点/滚动在那里区分），此处直接 return
            return
        end
    end

    -- 备战区：右侧面板触摸滚动（出售列表 / 出战装备列表）
    if STATE == "loadout" then
        local lp = loadoutLayout
        if lp and lp.isMobile then
            local section = loadoutState.mobileSection or "shop"
            local inPanel = false
            local target  = nil
            if section == "shop" and (loadoutState.activeTab or "sell") == "sell" then
                -- 出售待售列表区域
                local sz = lp.sellZone
                local listTop = sz.y + sz.h + 6
                local listBot = lp.confirmSellBtn.y - 6
                if x >= lp.rightX and x <= lp.rightX + lp.rightW
                and y >= listTop and y <= listBot then
                    inPanel = true
                    target  = "sell"
                end
            elseif section == "bag" then
                -- 出战装备列表区域
                local listTop = lp.equipListY0 - 12
                local listBot = lp.rContentY + lp.rContentH
                if x >= lp.rightX and x <= lp.rightX + lp.rightW
                and y >= listTop and y <= listBot then
                    inPanel = true
                    target  = "equip"
                end
            end
            if inPanel then
                local scrollY = (target == "sell") and (loadoutState.sellScrollY or 0) or (loadoutState.equipScrollY or 0)
                rightPanelDrag = { active=true, touchId=touchId, startY=y, startScrollY=scrollY, moved=false, target=target }
                return
            end
        end
    end

    -- 技能树：触摸拖动滚动
    if STATE == "skill_tree" then
        skillTreeDrag = { active = true, touchId = touchId, startY = y, startScroll = skillTreeScrollY, moved = false }
        return
    end

    -- 备战区：移动端全屏 UI 触摸路由（直接处理，不经过 MobileHUD）
    if STATE == "loadout" then
        if not loadoutLayout then
            loadoutLayout = Render.GetLoadoutLayout(stash, SW, SH)
        end
        local action = Render.HitTestLoadout(loadoutLayout, x, y, loadoutState)
        if action then
            -- 复用鼠标点击的 loadout action 处理逻辑（通过设置伪 mouse 事件触发）
            -- 直接在此处处理 action，避免代码重复
            if action == "start" then
                Audio.PlayBtnClick()
                -- 出发前：将出售区未确认的物品归还仓库，防止丢失
                if loadoutState.sellPending and #loadoutState.sellPending > 0 then
                    for _, item in ipairs(loadoutState.sellPending) do
                        Stash.AddItem(stash, item)
                    end
                    loadoutState.sellPending = {}
                    Stash.Save(stash)
                end
                -- 每次出发都重新生成 buildState，确保不带残留进度
                buildState = Reward.NewBuildState()
                local whitePool = {}
                for _, item in ipairs(Reward.POOL) do
                    if item.rarity == 1 then table.insert(whitePool, item) end
                end
                pickChoices = Reward.Generate(buildState, whitePool, 3)
                pickHover   = nil
                STATE = "pick"
            elseif action == "back" then
                Audio.PlayBtnClick()
                for _, item in ipairs(loadoutState.loadoutItems) do Stash.AddItem(stash, item) end
                for _, item in ipairs(loadoutState.sellPending)   do Stash.AddItem(stash, item) end
                loadoutState.loadoutItems = {}
                loadoutState.sellPending  = {}
                EnterHub()
            elseif action == "tabSell" then
                loadoutState.activeTab = "sell"
            elseif action == "tabBuy" then
                loadoutState.activeTab = "buy"
            elseif action == "confirmSell" then
                local sold, earned = 0, 0
                -- 技能树出售加价
                local sellBonusMult = 1 + (SkillTree.GetBonuses(skillTreeState).sellBonus or 0)
                for _, it in ipairs(loadoutState.sellPending) do
                    local bestPrice = 0
                    for _, v in ipairs(Stash.VENDORS) do
                        local p = Stash.GetSellPrice(it, v)
                        if p > bestPrice then bestPrice = p end
                    end
                    local finalPrice = math.floor(bestPrice * sellBonusMult)
                    stash.money = stash.money + finalPrice
                    sold = sold + 1; earned = earned + finalPrice
                end
                loadoutState.sellPending = {}
                loadoutState.multiSellMode = false
                if sold > 0 then
                    Audio.PlayCoin()
                    loadoutState.soldNotify = string.format("出售 %d 件，获得 💰%d", sold, earned)
                    loadoutState.soldTimer  = 2.5
                    Stash.Save(stash)
                end
            elseif action == "selectAll" then
                local Inventory = require("Inventory")
                local toSell = {}
                for _, entry in ipairs(stash.inv.items) do table.insert(toSell, entry) end
                for _, entry in ipairs(toSell) do
                    Inventory.RemoveItem(stash.inv, entry.id)
                    table.insert(loadoutState.sellPending, entry)
                end
                if #toSell > 0 then loadoutLayout = nil end
            elseif action == "multiSell" then
                loadoutState.multiSellMode = not loadoutState.multiSellMode
            elseif type(action) == "table" then
                local act = action.action
                if act == "mobileSection" then
                    loadoutState.mobileSection = action.key
                    loadoutState.selectedItemId = nil
                elseif act == "mobileStashTap" then
                    -- 移动端仓库格子：记录触摸起点，TouchEnd 判断 tap/drag
                    local Inventory = require("Inventory")
                    local entry = Inventory.HitTest(stash.inv, action.gridCol, action.gridRow)
                    if entry then
                        stashDragState = {
                            active = true, touchId = touchId,
                            startX = x, startY = y,
                            entry = entry,
                            gridCol = action.gridCol, gridRow = action.gridRow,
                            dragging = false,
                        }
                    else
                        loadoutState.selectedItemId = nil
                    end
                elseif act == "selectVendor" then
                    loadoutState.activeVendorId = action.vendorId
                    loadoutState.buyScrollY     = 0
                elseif act == "buyFrom" then
                    local ok = Stash.BuyFromVendor(stash, loadoutState.activeVendorId, action.vendorIdx)
                    if ok then Audio.PlayPurchase(); loadoutLayout = nil; Stash.Save(stash)
                    else Audio.PlayError() end
                elseif act == "removeLoadout" then
                    local items = loadoutState.loadoutItems
                    for i, it in ipairs(items) do
                        if it.id == action.itemId then
                            table.remove(items, i)
                            Stash.AddItem(stash, it)
                            loadoutLayout = nil; break
                        end
                    end
                elseif act == "removePending" then
                    local idx = action.itemIdx
                    if idx and loadoutState.sellPending[idx] then
                        local it = table.remove(loadoutState.sellPending, idx)
                        Stash.AddItem(stash, it)
                        loadoutLayout = nil
                    end
                end
            end
        end
        return  -- loadout 状态不走 MobileHUD
    end

    -- ---- 搜索面板（手机端）：优先拦截，不传给 MobileHUD ----
    if STATE == "playing" and player and player.searchOpen and searchPanelLayout then
        local lp = searchPanelLayout

        -- 关闭按钮
        local cb = lp.closeBtn
        if cb and x >= cb.x and x <= cb.x+cb.w and y >= cb.y and y <= cb.y+cb.h then
            Player.CloseSearch(player)
            player.searchOpen  = false
            searchPanelLayout  = nil
            Audio.PlayPanelClose()
            return
        end

        -- 智能拾取按钮（⚡）
        local alBtn = lp.autoLootBtn
        if alBtn and x >= alBtn.x and x <= alBtn.x+alBtn.w and y >= alBtn.y and y <= alBtn.y+alBtn.h then
            Audio.PlayPickup()
            Player.AutoLoot(player)
            local ss = player.searchState
            if ss.container and ss.container._box then
                World.SyncBoxLoot(ss.container._box, ss.containerInv)
            end
            searchPanelLayout = Render.GetSearchPanelLayout(
                player.searchState, player.inventory, SW, SH)
            return
        end

        -- 全部取走按钮
        local btn = lp.takeAllBtn
        if x >= btn.x and x <= btn.x+btn.w and y >= btn.y and y <= btn.y+btn.h then
            Audio.PlayPickup()
            Player.SearchTakeAll(player)
            local ss = player.searchState
            if ss.container and ss.container._box then
                World.SyncBoxLoot(ss.container._box, ss.containerInv)
            end
            searchPanelLayout = Render.GetSearchPanelLayout(
                player.searchState, player.inventory, SW, SH)
            return
        end

        -- 点击容器网格 → 取走单件物品（长按则显示 Tooltip）
        local cl = lp.container
        if x >= cl.gridX and x <= cl.gridX + cl.w*cl.cellSize
        and y >= cl.gridY and y <= cl.gridY + cl.h*cl.cellSize then
            local entry = Search.HitTestPanel(
                player.searchState, player.inventory, "container", x, y, lp)
            if entry then
                -- 记录长按 tooltip 候选（清除上次单点显示的 tooltip，否则双击判定失败）
                tooltipState.visible = false
                tooltipState.touchId = touchId
                tooltipState.touchX = x
                tooltipState.touchY = y
                tooltipState.touchTime = 0
                tooltipState.entry = entry
                tooltipState.info = Data.GetItemTooltip(entry)
                tooltipState._pendingAction = "searchTake"
                tooltipState._pendingEntryId = entry.id
            end
            return
        end

        -- 点击玩家背包网格 → 放入容器（长按则显示 Tooltip）
        local pl = lp.player
        if x >= pl.gridX and x <= pl.gridX + pl.w*pl.cellSize
        and y >= pl.gridY and y <= pl.gridY + pl.h*pl.cellSize then
            local entry = Search.HitTestPanel(
                player.searchState, player.inventory, "player", x, y, lp)
            if entry then
                -- 清除上次单点显示的 tooltip，否则双击判定失败
                tooltipState.visible = false
                tooltipState.touchId = touchId
                tooltipState.touchX = x
                tooltipState.touchY = y
                tooltipState.touchTime = 0
                tooltipState.entry = entry
                tooltipState.info = Data.GetItemTooltip(entry)
                tooltipState._pendingAction = "searchPut"
                tooltipState._pendingEntryId = entry.id
            end
            return
        end

        -- 面板内任意其他区域 → 消耗掉，防止穿透到 MobileHUD
        if x >= lp.panelX and x <= lp.panelX+lp.panelW
        and y >= lp.panelY and y <= lp.panelY+lp.panelH then
            return
        end
    end

    -- ---- 武器切换（手机端）：点击左上角武器区域 ----
    if STATE == "playing" and player and not player.bagOpen and not player.searchOpen then
        if Render.HitTestWeaponSwapBtn(x, y, isMobile, SW, SH) then
            if not Player.IsCasting(player) then
                Player.SwapWeapon(player)
                Audio.PlayEquip()
            end
            return
        end
    end

    -- ---- 撤离按钮（手机端，必须先于 MedBar 检测，防止底部区域误触）----
    if STATE == "playing" and player and not player.bagOpen and not player.searchOpen and not player.dead then
        local col2, row2 = World.WorldToTile(player.x, player.y)
        local nearExitNow = World.IsExitCell and World.IsExitCell(col2, row2) and not World.exitLocked
        if nearExitNow and mobileLayout then
            local eb = mobileLayout.btnEvac
            if x >= eb.x - 8 and x <= eb.x + eb.w + 8 and y >= eb.y - 8 and y <= eb.y + eb.h + 8 then
                if not Player.IsCasting(player) and not player.searchOpen then
                    if player.extracting <= 0 then
                        player.extracting = 0.001
                        player.extracted  = false
                    end
                end
                return
            end
        end
    end

    -- ---- 医疗快捷栏（手机端）：背包/搜索面板关闭时，优先拦截 MedBar 触摸 ----
    if STATE == "playing" and player and not player.bagOpen and not player.searchOpen then
        local medSlot = Render.HitTestMedBar(x, y, SW, SH, true)
        if medSlot then
            Player.UseMedSlot(player, medSlot)
            return
        end
    end

    -- ---- 背包面板（手机端）：完整物品交互 ----
    if STATE == "playing" and player and player.bagOpen then
        local invLp = Render.GetInventoryPanelLayout(player, SW, SH, isMobile)

        -- 关闭按钮
        local cb = invLp.closeBtn
        if cb and x >= cb.x and x <= cb.x+cb.w and y >= cb.y and y <= cb.y+cb.h then
            player.bagOpen = false
            Audio.PlayPanelClose()
            return
        end

        -- 面板内点击：执行物品操作（长按显示 Tooltip）
        if x >= invLp.panelX and x <= invLp.panelX+invLp.panelW
        and y >= invLp.panelY and y <= invLp.panelY+invLp.panelH then
            local hit = Render.HitTestInventoryPanel(invLp, player, x, y)
            if hit then
                if hit.action == "equipSlot" then
                    -- 装备槽 → 启动拖拽（拖到背包卸下）
                    local eq = player.equip and player.equip[hit.slot]
                    if eq then
                        local ds = player.bagDragState
                        ds.dragItem = {
                            itype  = hit.slot,
                            data   = eq,
                            name   = eq.name,
                            icon   = eq.icon or "🛡️",
                            rarity = eq.rarity or 1,
                            value  = eq.value  or 0,
                        }
                        ds.dragX          = x
                        ds.dragY          = y
                        ds.srcInv         = nil
                        ds.srcType        = "equipSlot"
                        ds.srcEquipSlot   = hit.slot
                        ds.srcWeaponKey   = nil
                        ds.hoverWeaponSlot = nil
                        ds.hoverBagGrid    = nil
                        ds._touchId        = touchId
                    end
                elseif hit.action == "bagItem" then
                    if hit.entry and hit.entry.itype == "weapon" then
                        -- 武器物品：开始触摸拖拽（不做长按 tooltip）
                        local ds = player.bagDragState
                        ds.dragItem        = hit.entry
                        ds.dragX           = x
                        ds.dragY           = y
                        ds.srcInv          = hit.srcInv
                        ds.hoverWeaponSlot = nil
                        ds._touchId        = touchId
                    else
                        -- 非武器：记录长按 tooltip，短按装备
                        if hit.entry then
                            tooltipState.touchId = touchId
                            tooltipState.touchX = x
                            tooltipState.touchY = y
                            tooltipState.touchTime = 0
                            tooltipState.entry = hit.entry
                            tooltipState.info = Data.GetItemTooltip(hit.entry)
                            tooltipState._pendingAction = "equip"
                            tooltipState._pendingId = hit.id
                            tooltipState._pendingName = hit.name
                        end
                    end
                elseif hit.action == "weaponSlot" then
                    -- 武器槽长按查看
                    local wpn = player[hit.key]
                    if wpn then
                        tooltipState.touchId = touchId
                        tooltipState.touchX = x
                        tooltipState.touchY = y
                        tooltipState.touchTime = 0
                        tooltipState.entry = { itype="weapon", data=wpn, name=wpn.name, rarity=wpn.rarity or 1 }
                        tooltipState.info = Data.GetItemTooltip(tooltipState.entry)
                        tooltipState._pendingAction = nil -- 武器槽没有短按操作
                    end
                end
            end
            return
        end
    end

    HandleMobileTap(touchId, x, y)
end

function HandleTouchMove(eventType, eventData)
    if not isMobile or not mobileLayout then return end
    local touchId = eventData["TouchID"]:GetInt()
    local x = math.floor(eventData["X"]:GetInt() / uiDPR)
    local y = math.floor(eventData["Y"]:GetInt() / uiDPR)

    -- Tooltip 长按取消：移动超过 8px 则取消
    if tooltipState.touchId == touchId then
        local dx = math.abs(x - tooltipState.touchX)
        local dy = math.abs(y - tooltipState.touchY)
        if dx > 8 or dy > 8 then
            tooltipState.touchId = nil
            tooltipState.visible = false
            tooltipState.entry = nil
            tooltipState.info = nil
            tooltipState._pendingAction = nil
        end
    end

    -- 技能树拖动滚动
    if STATE == "skill_tree" and skillTreeDrag.active and skillTreeDrag.touchId == touchId then
        local delta = skillTreeDrag.startY - y
        skillTreeScrollY = skillTreeDrag.startScroll + delta
        local maxScroll = SkillTreeUI.GetMaxScroll(SW, SH, skillTreeState)
        skillTreeScrollY = math.max(0, math.min(skillTreeScrollY, maxScroll))
        if math.abs(delta) > 8 then skillTreeDrag.moved = true end
        return
    end

    -- 玩法介绍面板拖动滚动
    if STATE == "menu" and showHowTo and howToDragY then
        local delta = howToDragY - y
        howToScrollY = howToDragStartScroll + delta
        local maxScroll = Render.GetHowToMaxScroll(SW, SH)
        howToScrollY = math.max(0, math.min(howToScrollY, maxScroll))
        return
    end

    -- 备战区购买面板滚动拖拽
    if buyScrollDrag.active and buyScrollDrag.touchId == touchId then
        local delta = buyScrollDrag.startY - y
        loadoutState.buyScrollY = buyScrollDrag.startScrollY + delta
        ClampBuyScroll()
        if math.abs(delta) > 8 then buyScrollDrag.moved = true end
        return
    end

    -- 备战区仓库格子拖拽：超过阈值后启动 dragItem
    if stashDragState.active and stashDragState.touchId == touchId then
        local dx = math.abs(x - stashDragState.startX)
        local dy = math.abs(y - stashDragState.startY)
        if not stashDragState.dragging then
            if dx > 12 or dy > 12 then
                -- 启动拖拽
                stashDragState.dragging = true
                loadoutState.dragItem = stashDragState.entry
                loadoutState.dragX = x
                loadoutState.dragY = y
                loadoutState.hoverZone = nil
            end
        else
            -- 拖拽中：更新位置和 hoverZone
            loadoutState.dragX = x
            loadoutState.dragY = y
            if loadoutLayout then
                local lp = loadoutLayout
                local section = loadoutState.mobileSection or "shop"
                if section == "shop" then
                    local sz = lp.sellZone
                    if sz and x >= sz.x and x <= sz.x+sz.w and y >= sz.y and y <= sz.y+sz.h then
                        loadoutState.hoverZone = "sell"
                    else
                        loadoutState.hoverZone = nil
                    end
                else
                    local lz = lp.loadoutZone
                    if lz and x >= lz.x and x <= lz.x+lz.w and y >= lz.y and y <= lz.y+lz.h then
                        loadoutState.hoverZone = "loadout"
                    else
                        loadoutState.hoverZone = nil
                    end
                end
            end
        end
        return
    end

    -- 备战区右侧面板滚动拖拽
    if rightPanelDrag.active and rightPanelDrag.touchId == touchId then
        local delta = rightPanelDrag.startY - y
        local newScroll = rightPanelDrag.startScrollY + delta
        if rightPanelDrag.target == "sell" then
            local pending = loadoutState.sellPending or {}
            local rowH = 28
            local visH = loadoutLayout and loadoutLayout.sellListH or 200
            local maxScroll = math.max(0, #pending * rowH + 18 - visH)
            loadoutState.sellScrollY = math.max(0, math.min(newScroll, maxScroll))
        else
            local items = loadoutState.loadoutItems or {}
            local rowH = loadoutLayout and loadoutLayout.equipRowH or 30
            local visH = loadoutLayout and (loadoutLayout.rContentH - 20) or 200
            local maxScroll = math.max(0, #items * rowH - visH)
            loadoutState.equipScrollY = math.max(0, math.min(newScroll, maxScroll))
        end
        if math.abs(delta) > 8 then rightPanelDrag.moved = true end
        return
    end

    -- 暂停面板滑块拖动
    if STATE == "paused" and pauseDragState.target then
        local v = Render.CalcSliderValue(x, SW, SH, pauseDragState.target)
        if pauseDragState.target == "bgm" then Audio.SetBGMVolume(v) else Audio.SetSFXVolume(v) end
        return
    end

    -- 背包拖拽：更新拖拽位置和悬停目标（武器槽 + 背包格子）
    if STATE == "playing" and player and player.bagOpen and player.bagDragState
    and player.bagDragState.dragItem and player.bagDragState._touchId == touchId then
        local ds = player.bagDragState
        ds.dragX = x
        ds.dragY = y
        local lp = Render.GetInventoryPanelLayout(player, SW, SH, isMobile)
        ds.hoverWeaponSlot = nil
        for _, ws in ipairs(lp.weaponSlots) do
            if x >= ws.x and x <= ws.x + ws.w
            and y >= ws.y and y <= ws.y + ws.h then
                if ws.key ~= "knife" then
                    ds.hoverWeaponSlot = ws.key
                end
                break
            end
        end
        -- 背包格子悬停检测
        ds.hoverBagGrid = nil
        local inv = player.inventory
        local cs = lp.CELL
        local bx, by = lp.bagGridX, lp.bagGridY
        if bx and inv and x >= bx and x < bx + inv.width * cs
        and y >= by and y < by + inv.height * cs then
            local col = math.floor((x - bx) / cs) + 1
            local row = math.floor((y - by) / cs) + 1
            ds.hoverBagGrid = { col = col, row = row }
        end
        return
    end

    MobileHUD.OnTouchMove(mobileLayout, touchId, x, y)
end

function HandleTouchEnd(eventType, eventData)
    if not isMobile then return end
    local touchId = eventData["TouchID"]:GetInt()

    -- 技能树拖动结束
    if skillTreeDrag.active and skillTreeDrag.touchId == touchId then
        local wasDrag = skillTreeDrag.moved
        skillTreeDrag.active = false
        skillTreeDrag.touchId = nil
        -- 如果没有移动（轻点），触发点击逻辑
        if not wasDrag then
            local x = math.floor(eventData["X"]:GetInt() / (uiDPR or 1))
            local y = math.floor(eventData["Y"]:GetInt() / (uiDPR or 1))
            HandleMobileTap(touchId, x, y)
        end
        skillTreeDrag.moved = false
        return
    end

    -- 玩法介绍面板：拖动结束判定（移动小于8px视为点击关闭）
    if STATE == "menu" and showHowTo and howToDragY then
        local moved = math.abs(howToScrollY - howToDragStartScroll) > 8
        howToDragY = nil
        if not moved then
            showHowTo = false
        end
        return
    end

    -- Tooltip 长按结束处理
    if tooltipState.touchId == touchId then
        tooltipState.touchId = nil
        if tooltipState.visible then
            -- 长按已显示 tooltip → 仅关闭，不执行操作
            tooltipState.visible = false
            tooltipState.entry = nil
            tooltipState.info = nil
            tooltipState._pendingAction = nil
            return
        else
            -- 短按（<0.45s）
            local act = tooltipState._pendingAction
            local entryId = tooltipState._pendingEntryId
            tooltipState._pendingAction = nil

            -- 搜索面板物品：单点查看信息，双击执行取走/放回
            if (act == "searchTake" or act == "searchPut") and player and player.searchOpen then
                local now = time:GetElapsedTime()
                local dt2 = now - searchDoubleTap.lastTime
                local sameItem = (entryId == searchDoubleTap.lastEntryId)
                    and (act == searchDoubleTap.lastAction)

                if sameItem and dt2 < searchDoubleTap.THRESHOLD then
                    -- 双击 → 执行操作
                    searchDoubleTap.lastTime = 0
                    searchDoubleTap.lastEntryId = nil
                    searchDoubleTap.lastAction = nil
                    tooltipState.visible = false
                    tooltipState.entry = nil
                    tooltipState.info = nil
                    if act == "searchTake" and entryId then
                        Audio.PlayPickup()
                        Player.SearchTakeItem(player, entryId)
                        local ss = player.searchState
                        if ss.container and ss.container._box then
                            World.SyncBoxLoot(ss.container._box, ss.containerInv)
                        end
                        searchPanelLayout = Render.GetSearchPanelLayout(
                            player.searchState, player.inventory, SW, SH)
                    elseif act == "searchPut" and entryId then
                        Search.PutItem(player.searchState, entryId, player.inventory)
                        local ss = player.searchState
                        if ss.container and ss.container._box then
                            World.SyncBoxLoot(ss.container._box, ss.containerInv)
                        end
                        searchPanelLayout = Render.GetSearchPanelLayout(
                            player.searchState, player.inventory, SW, SH)
                    end
                    return
                else
                    -- 单点 → 显示物品信息 tooltip
                    searchDoubleTap.lastTime = now
                    searchDoubleTap.lastEntryId = entryId
                    searchDoubleTap.lastAction = act
                    if tooltipState.info then
                        tooltipState.visible = true
                        tooltipState.posX = tooltipState.touchX
                        tooltipState.posY = tooltipState.touchY
                    end
                    return
                end
            end

            tooltipState.entry = nil
            tooltipState.info = nil
            if act == "unequip" and player and player.bagOpen then
                local slot = tooltipState._pendingSlot
                if slot then
                    local ok, reason = Player.UnequipSlot(player, slot)
                    if ok then
                        Audio.PlayEquip()
                        player.notification = { text="卸下装备", timer=1.2 }
                        player.lootValue = require("Inventory").TotalValue(player.inventory)
                    else
                        Audio.PlayError()
                        player.notification = { text=(reason or "无法卸下"), timer=1.2 }
                    end
                end
                return
            elseif act == "equip" and player and player.bagOpen then
                local id = tooltipState._pendingId
                if id then
                    local ok = Player.EquipFromInventory(player, id)
                    if ok then
                        Audio.PlayEquip()
                        player.notification = { text="已装备: "..(tooltipState._pendingName or "物品"), timer=1.2 }
                        player.lootValue = require("Inventory").TotalValue(player.inventory)
                    else
                        Audio.PlayError()
                        player.notification = { text="无法装备", timer=1.2 }
                    end
                end
                return
            end
            -- act == nil (武器槽查看，无短按操作) → fall through
        end
    end

    -- 备战区购买面板滚动结束
    if buyScrollDrag.active and buyScrollDrag.touchId == touchId then
        local wasTap = not buyScrollDrag.moved
        buyScrollDrag.active  = false
        buyScrollDrag.touchId = nil
        if wasTap then
            -- 位移极小，视为轻点购买
            local ex = math.floor(eventData["X"]:GetInt() / uiDPR)
            local ey = math.floor(eventData["Y"]:GetInt() / uiDPR)
            if not loadoutLayout then
                loadoutLayout = Render.GetLoadoutLayout(stash, SW, SH)
            end
            local action = Render.HitTestLoadout(loadoutLayout, ex, ey, loadoutState)
            if action and type(action) == "table" and action.action == "buyFrom" then
                local ok = Stash.BuyFromVendor(stash, loadoutState.activeVendorId, action.vendorIdx)
                if ok then
                    Audio.PlayPurchase()
                    loadoutLayout = nil
                    Stash.Save(stash)
                else
                    Audio.PlayError()
                end
            end
        end
        return
    end

    -- 备战区右侧面板滚动结束
    if rightPanelDrag.active and rightPanelDrag.touchId == touchId then
        local wasTap = not rightPanelDrag.moved
        local target = rightPanelDrag.target
        rightPanelDrag.active  = false
        rightPanelDrag.touchId = nil
        if wasTap then
            -- 轻点：执行列表项目的点击操作（移除待售/移除出战）
            local ex = math.floor(eventData["X"]:GetInt() / uiDPR)
            local ey = math.floor(eventData["Y"]:GetInt() / uiDPR)
            if not loadoutLayout then
                loadoutLayout = Render.GetLoadoutLayout(stash, SW, SH)
            end
            local action = Render.HitTestLoadout(loadoutLayout, ex, ey, loadoutState)
            if action and type(action) == "table" then
                local act = action.action
                if act == "removePending" then
                    local idx = action.itemIdx
                    local pending = loadoutState.sellPending
                    if pending[idx] then
                        local item = table.remove(pending, idx)
                        Stash.AddItem(stash, item)
                        loadoutLayout = nil
                        Stash.Save(stash)
                        Audio.PlayBtnClick()
                        -- 钳制滚动（列表变短）
                        local maxS = math.max(0, #pending * 28 + 18 - 200)
                        loadoutState.sellScrollY = math.max(0, math.min(loadoutState.sellScrollY, maxS))
                    end
                elseif act == "removeLoadout" then
                    local items = loadoutState.loadoutItems
                    for i, it in ipairs(items) do
                        if it.id == action.itemId then
                            table.remove(items, i)
                            Stash.AddItem(stash, it)
                            loadoutLayout = nil
                            Stash.Save(stash)
                            Audio.PlayBtnClick()
                            -- 钳制滚动（列表变短）
                            local maxS = math.max(0, #items * 30 - 200)
                            loadoutState.equipScrollY = math.max(0, math.min(loadoutState.equipScrollY, maxS))
                            break
                        end
                    end
                end
            end
        else
            -- 滚动结束：钳制滚动范围
            if target == "sell" then
                local pending = loadoutState.sellPending or {}
                local rowH = 28
                local maxScroll = math.max(0, #pending * rowH + 18 - (loadoutLayout and loadoutLayout.sellListH or 200))
                loadoutState.sellScrollY = math.max(0, math.min(loadoutState.sellScrollY, maxScroll))
            else
                local items = loadoutState.loadoutItems or {}
                local rowH = loadoutLayout and loadoutLayout.equipRowH or 30
                local visH = loadoutLayout and (loadoutLayout.rContentH - 20) or 200
                local maxScroll = math.max(0, #items * rowH - visH)
                loadoutState.equipScrollY = math.max(0, math.min(loadoutState.equipScrollY, maxScroll))
            end
        end
        return
    end

    -- 备战区仓库格子拖拽结束
    if stashDragState.active and stashDragState.touchId == touchId then
        local wasDragging = stashDragState.dragging
        local entry = stashDragState.entry
        stashDragState.active = false
        stashDragState.touchId = nil

        if wasDragging then
            -- 拖拽完成：根据 hoverZone 决定物品去向
            local zone = loadoutState.hoverZone
            loadoutState.dragItem  = nil
            loadoutState.hoverZone = nil
            local Inventory = require("Inventory")
            local section = loadoutState.mobileSection or "shop"

            if section == "shop" and zone == "sell" then
                -- 拖到出售区
                Inventory.RemoveItem(stash.inv, entry.id)
                table.insert(loadoutState.sellPending, entry)
                loadoutLayout = nil
                Audio.PlayBtnClick()
            elseif section ~= "shop" and zone == "loadout" then
                -- 拖到出战/装备区
                Inventory.RemoveItem(stash.inv, entry.id)
                table.insert(loadoutState.loadoutItems, entry)
                loadoutLayout = nil
                Audio.PlayBtnClick()
            else
                -- 没拖到有效区域，物品留在仓库
            end
        else
            -- 没拖拽 → 执行 tap/double-tap 逻辑
            if entry then
                local now = time:GetElapsedTime()
                local DOUBLE_TAP_THRESHOLD = 0.4
                local isDoubleTap = (loadoutState.lastTapItemId == entry.id)
                    and (now - (loadoutState.lastTapTime or 0) < DOUBLE_TAP_THRESHOLD)

                if isDoubleTap then
                    local section = loadoutState.mobileSection or "shop"
                    local Inventory = require("Inventory")
                    if section == "shop" then
                        -- 双击出售
                        Inventory.RemoveItem(stash.inv, entry.id)
                        table.insert(loadoutState.sellPending, entry)
                        loadoutLayout = nil
                    else
                        -- 双击带上/装备：toggle loadoutItems
                        local items = loadoutState.loadoutItems
                        local found = false
                        for i, it in ipairs(items) do
                            if it.id == entry.id then
                                table.remove(items, i)
                                Stash.AddItem(stash, it)
                                loadoutLayout = nil; found = true; break
                            end
                        end
                        if not found then
                            Inventory.RemoveItem(stash.inv, entry.id)
                            table.insert(items, entry)
                            loadoutLayout = nil
                        end
                    end
                    Audio.PlayBtnClick()
                    loadoutState.selectedItemId = nil
                    loadoutState.lastTapItemId = nil
                    loadoutState.lastTapTime = 0
                else
                    -- 单击：选中
                    loadoutState.selectedItemId = entry.id
                    loadoutState.lastTapItemId = entry.id
                    loadoutState.lastTapTime = now
                end
            end
        end
        return
    end

    -- 暂停面板滑块释放
    if STATE == "paused" and pauseDragState.target then
        pauseDragState.target = nil
        return
    end

    -- 背包拖拽：松手完成换装/卸装
    if STATE == "playing" and player and player.bagOpen and player.bagDragState
    and player.bagDragState.dragItem and player.bagDragState._touchId == touchId then
        local ds      = player.bagDragState
        local entry   = ds.dragItem
        local wpnKey  = ds.hoverWeaponSlot
        local bagGrid = ds.hoverBagGrid
        local srcType = ds.srcType
        local srcWpnK = ds.srcWeaponKey
        local srcEqSlot = ds.srcEquipSlot
        ds.dragItem        = nil
        ds.hoverWeaponSlot = nil
        ds.hoverBagGrid    = nil
        ds.srcType         = nil
        ds.srcWeaponKey    = nil
        ds.srcEquipSlot    = nil
        ds._touchId        = nil

        local Inventory = require("Inventory")

        if srcType == "weaponSlot" then
            -- 从武器槽拖起
            local srcWpn = player[srcWpnK]
            if srcWpn then
                if wpnKey then
                    -- 主副武器互换
                    local dstWpn = player[wpnKey]
                    player[srcWpnK] = dstWpn
                    player[wpnKey]  = srcWpn
                    local Player = require("Player")
                    Player.syncWeaponRef(player)
                    Audio.PlayEquip()
                    player.notification = { text="武器已互换", timer=1.2 }
                    player.lootValue = Inventory.TotalValue(player.inventory)
                elseif bagGrid then
                    -- 卸到背包
                    local item = { itype="weapon", data=srcWpn, name=srcWpn.name,
                        icon=srcWpn.icon or "🔫", rarity=srcWpn.rarity or 1, value=srcWpn.value or 0 }
                    local placed = Inventory.PlaceItem(player.inventory, item, bagGrid.col, bagGrid.row, false)
                    if not placed then placed = Inventory.AutoPlace(player.inventory, item) end
                    if placed then
                        player[srcWpnK] = nil
                        local Player = require("Player")
                        Player.syncWeaponRef(player)
                        Audio.PlayEquip()
                        player.notification = { text=srcWpn.name.." 已放回背包", timer=1.2 }
                        player.lootValue = Inventory.TotalValue(player.inventory)
                    else
                        player.notification = { text="背包已满", timer=1.2 }
                        Audio.PlayError()
                    end
                end
            end

        elseif srcType == "equipSlot" then
            -- 从装备槽拖起
            local eq = player.equip and player.equip[srcEqSlot]
            if eq and bagGrid then
                local item = { itype=srcEqSlot, data=eq, name=eq.name,
                    icon=eq.icon or "🛡️", rarity=eq.rarity or 1, value=eq.value or 0 }
                local placed = Inventory.PlaceItem(player.inventory, item, bagGrid.col, bagGrid.row, false)
                if not placed then placed = Inventory.AutoPlace(player.inventory, item) end
                if placed then
                    player.equip[srcEqSlot] = nil
                    if srcEqSlot == "bag" then
                        local Player = require("Player")
                        Player.UpdateBagSize(player)
                    end
                    Audio.PlayEquip()
                    player.notification = { text=eq.name.." 已放回背包", timer=1.2 }
                    player.lootValue = Inventory.TotalValue(player.inventory)
                else
                    player.notification = { text="背包已满", timer=1.2 }
                    Audio.PlayError()
                end
            end

        else
            -- 从背包拖起（srcType == "inv"）
            if wpnKey then
                local srcInv = player.inventory
                local newWpn = entry.data
                if newWpn then
                    local oldWpn = player[wpnKey]
                    -- 先移除新武器腾出空间
                    local removed = Inventory.RemoveItem(srcInv, entry.id)
                    if not removed then
                        -- entry.id 已失效（可能被 AutoSort 重排），不执行操作
                        player.notification = { text = "操作失败，请重试", timer = 1.2 }
                        Audio.PlayError()
                    elseif oldWpn and oldWpn.key ~= "Knife" then
                        -- 检查旧武器能否放回背包
                        local oldItem = { itype="weapon", data=oldWpn, name=oldWpn.name,
                            icon=oldWpn.icon or "🔫", rarity=oldWpn.rarity or 1, value=oldWpn.value or 0 }
                        local iw, ih = Inventory.GetSize(oldItem)
                        local sx, sy = Inventory.FindSpace(srcInv, iw, ih)
                        if not sx then
                            -- 放不下，还原：把新武器放回背包，取消操作
                            Inventory.AutoPlace(srcInv, entry)
                            player.notification = { text = "背包空间不足，无法换枪", timer = 1.5 }
                            Audio.PlayError()
                        else
                            -- 能放下，执行交换
                            Inventory.AutoPlace(srcInv, oldItem)
                            player[wpnKey] = newWpn
                            local Player = require("Player")
                            Player.syncWeaponRef(player)
                            Audio.PlayEquip()
                            player.notification = {
                                text = (wpnKey == "primaryGun" and "主武器" or "副武器")
                                       .." → "..newWpn.name, timer=1.5
                            }
                            player.lootValue = Inventory.TotalValue(player.inventory)
                        end
                    else
                        -- 无旧武器或是刀，直接装备
                        player[wpnKey] = newWpn
                        local Player = require("Player")
                        Player.syncWeaponRef(player)
                        Audio.PlayEquip()
                        player.notification = {
                            text = (wpnKey == "primaryGun" and "主武器" or "副武器")
                                   .." → "..newWpn.name, timer=1.5
                        }
                        player.lootValue = Inventory.TotalValue(player.inventory)
                    end
                end
            end
        end
        return
    end

    MobileHUD.OnTouchEnd(touchId)
end
