-- ============================================================================
-- AudioManager.lua — 音频管理器 v2.0
-- 依据《修勾大逃亡 — 音效与BGM设计》重写
-- 支持：BGM动态切换、武器独立音效、3D声像、低血量警报、Boss专属音效
-- ============================================================================
local M = {}

-- ----------------------------------------------------------------------------
-- 内部状态
-- ----------------------------------------------------------------------------
local audioScene = nil  ---@type Scene
local audioNode  = nil  ---@type Node
local bgmSource  = nil  ---@type SoundSource  BGM 专用（循环）
local sfxSources = {}   -- 音效池
local SFX_POOL   = 16   -- 同时最多 16 路音效（Boss战音效多）

local sounds     = {}   -- Sound 资源缓存 { path -> Sound }
local currentBgm = nil  -- 当前播放的 BGM 路径

-- 音量（0.0 ~ 1.0）
local BGM_GAIN = 0.5
local SFX_GAIN = 0.85

-- 脚步节拍
local footstepTimer = 0
local footstepIdx   = 1

-- ----------------------------------------------------------------------------
-- BGM 路径映射（对齐设计文档规范命名）
-- ----------------------------------------------------------------------------
local BGM = {
    menu    = "audio/bgm/menu_theme.ogg",
    dungeon = "audio/bgm/dungeon_explore.ogg",
    boss    = "audio/bgm/boss_fight.ogg",
    extract = "audio/bgm/extraction.ogg",
    death   = "audio/bgm/death.ogg",
}

-- ----------------------------------------------------------------------------
-- SFX 路径映射
-- ----------------------------------------------------------------------------
local SFX = {
    -- ── 武器 ──────────────────────────────────────────────────────────────
    knife_slash     = "audio/sfx/knife_slash.ogg",
    glock_fire      = "audio/sfx/weapons/glock_fire.ogg",
    glock_reload    = "audio/sfx/weapons/glock_reload.ogg",
    mp5_fire        = "audio/sfx/weapons/mp5_fire.ogg",
    mp5_reload      = "audio/sfx/weapons/mp5_reload.ogg",
    uzi_fire        = "audio/sfx/weapons/uzi_fire.ogg",
    akm_fire        = "audio/sfx/weapons/akm_fire.ogg",
    akm_reload      = "audio/sfx/weapons/akm_reload.ogg",
    m870_fire       = "audio/sfx/weapons/m870_fire.ogg",
    m870_reload     = "audio/sfx/weapons/m870_reload.ogg",
    awm_fire        = "audio/sfx/weapons/awm_fire.ogg",
    awm_reload      = "audio/sfx/weapons/awm_reload.ogg",
    pkm_fire        = "audio/sfx/weapons/pkm_fire.ogg",
    pkm_reload      = "audio/sfx/weapons/pkm_reload.ogg",
    deagle_fire     = "audio/sfx/weapons/deagle_fire.ogg",
    p90_fire        = "audio/sfx/weapons/p90_fire.ogg",
    bullet_wall     = "audio/sfx/weapons/bullet_wall.ogg",
    empty_click     = "audio/sfx/weapons/empty_click.ogg",
    weapon_jammed   = "audio/sfx/weapon_jammed.ogg",
    sniper_shoot    = "audio/sfx/enemy/sniper_shoot.ogg",  -- 狙击手专用
    -- ── 玩家 ──────────────────────────────────────────────────────────────
    footstep_01     = "audio/sfx/player/footstep_concrete_01.ogg",
    footstep_02     = "audio/sfx/player/footstep_concrete_02.ogg",
    heal_bandage    = "audio/sfx/player/heal_bandage.ogg",
    death_player    = "audio/sfx/player/death_player.ogg",
    extraction_ok   = "audio/sfx/player/extraction_success.ogg",
    low_hp_beep     = "audio/sfx/player/low_hp_beep.ogg",
    -- ── 敌人 ──────────────────────────────────────────────────────────────
    enemy_spotted   = "audio/sfx/enemy/enemy_spotted.ogg",
    enemy_hit       = "audio/sfx/enemy/enemy_hit.ogg",
    enemy_die       = "audio/sfx/enemy/enemy_die.ogg",
    boss_roar       = "audio/sfx/enemy/boss_roar.ogg",
    boss_attack     = "audio/sfx/enemy/boss_attack.ogg",
    boss_die        = "audio/sfx/enemy/boss_die.ogg",
    -- ── UI ────────────────────────────────────────────────────────────────
    btn_hover       = "audio/sfx/ui/btn_hover.ogg",
    btn_click       = "audio/sfx/ui/btn_click.ogg",
    panel_open      = "audio/sfx/ui/panel_open.ogg",
    panel_close     = "audio/sfx/ui/panel_close.ogg",
    item_pickup     = "audio/sfx/ui/item_pickup.ogg",
    coin            = "audio/sfx/ui/coin.ogg",
    item_purchase   = "audio/sfx/ui/item_purchase.ogg",
    equip_change    = "audio/sfx/ui/equip_change.ogg",
    upgrade_success = "audio/sfx/ui/upgrade_success.ogg",
    upgrade_fail    = "audio/sfx/ui/upgrade_fail.ogg",
    error           = "audio/sfx/ui/error.ogg",
    notification    = "audio/sfx/ui/notification.ogg",
    new_floor       = "audio/sfx/ui/new_floor.ogg",
    -- ── 特效 ──────────────────────────────────────────────────────────────
    teleport_beam   = "audio/sfx/teleport_beam.ogg",
}

-- ----------------------------------------------------------------------------
-- 武器名称 → 射击/换弹 SFX key（完整覆盖所有武器）
-- ----------------------------------------------------------------------------
local WEAPON_FIRE_SFX = {
    -- 近战
    ["战术刀"]         = "knife_slash",
    -- 手枪
    ["Glock"]          = "glock_fire",
    ["Glock 17"]       = "glock_fire",
    ["G18"]            = "glock_fire",
    ["Desert Eagle"]   = "deagle_fire",
    ["DesertEagle"]    = "deagle_fire",
    -- SMG
    ["MP5"]            = "mp5_fire",
    ["MP7"]            = "mp5_fire",
    ["UZI"]            = "uzi_fire",
    ["P90"]            = "p90_fire",
    -- 步枪
    ["AKM"]            = "akm_fire",
    ["M16"]            = "akm_fire",
    ["AUG"]            = "akm_fire",
    ["M250"]           = "akm_fire",
    -- 霰弹
    ["M870"]           = "m870_fire",
    ["M1014"]          = "m870_fire",
    ["S12K"]           = "m870_fire",
    ["725"]            = "m870_fire",
    -- 机枪
    ["PKM"]            = "pkm_fire",
    -- 狙击
    ["AWM"]            = "awm_fire",
    ["R93"]            = "awm_fire",
}

local WEAPON_RELOAD_SFX = {
    ["Glock"]          = "glock_reload",
    ["Glock 17"]       = "glock_reload",
    ["G18"]            = "glock_reload",
    ["Desert Eagle"]   = "glock_reload",
    ["DesertEagle"]    = "glock_reload",
    ["MP5"]            = "mp5_reload",
    ["MP7"]            = "mp5_reload",
    ["UZI"]            = "mp5_reload",
    ["P90"]            = "mp5_reload",
    ["AKM"]            = "akm_reload",
    ["M16"]            = "akm_reload",
    ["AUG"]            = "akm_reload",
    ["M250"]           = "akm_reload",
    ["M870"]           = "m870_reload",
    ["M1014"]          = "m870_reload",
    ["S12K"]           = "m870_reload",
    ["725"]            = "m870_reload",
    ["PKM"]            = "pkm_reload",
    ["AWM"]            = "awm_reload",
    ["R93"]            = "awm_reload",
}

-- ----------------------------------------------------------------------------
-- 私有：加载并缓存 Sound 资源
-- ----------------------------------------------------------------------------
local function LoadSound(path)
    if sounds[path] then return sounds[path] end
    local s = cache:GetResource("Sound", path)
    if s then sounds[path] = s end
    return s
end

-- 预加载全部资源（Init 时调用，消除首次播放延迟）
local function PreloadAll()
    for _, path in pairs(SFX) do LoadSound(path) end
    for _, path in pairs(BGM) do LoadSound(path) end
end

-- ----------------------------------------------------------------------------
-- 初始化
-- ----------------------------------------------------------------------------
function M.Init()
    audioScene = Scene:new()
    audioNode  = audioScene:CreateChild("AudioManager")

    -- BGM 专用 SoundSource
    bgmSource           = audioNode:CreateComponent("SoundSource")
    bgmSource.soundType = "Music"
    bgmSource.gain      = BGM_GAIN

    -- 音效池（优先级高的音效独占一个 source）
    for i = 1, SFX_POOL do
        local src       = audioNode:CreateComponent("SoundSource")
        src.soundType   = "Effect"
        src.gain        = SFX_GAIN
        sfxSources[i]   = src
    end

    PreloadAll()
end

-- ----------------------------------------------------------------------------
-- 私有：获取空闲音效 SoundSource
-- 优先级策略：找最空闲的，实在没有就抢占索引最小的（优先级最低）
-- ----------------------------------------------------------------------------
local function GetFreeSfxSource()
    for _, src in ipairs(sfxSources) do
        if not src.playing then return src end
    end
    return sfxSources[1]
end

-- ----------------------------------------------------------------------------
-- 公开：播放 BGM（按 key，相同 BGM 不重复触发）
-- ----------------------------------------------------------------------------
function M.PlayBGM(key)
    local path = BGM[key]
    if not path then return end
    if currentBgm == path then return end

    local snd = LoadSound(path)
    if not snd then return end

    -- 只有菜单/地牢/Boss BGM 循环
    local loopKeys = { menu=true, dungeon=true, boss=true }
    snd.looped = loopKeys[key] or false

    bgmSource:Stop()
    bgmSource:Play(snd)
    currentBgm = path
end

function M.StopBGM()
    bgmSource:Stop()
    currentBgm = nil
end

-- ----------------------------------------------------------------------------
-- 公开：播放音效（基础，按 key）
-- ----------------------------------------------------------------------------
function M.PlaySFX(key, gainMult)
    local path = SFX[key]
    if not path then return end
    local snd = LoadSound(path)
    if not snd then return end

    local src  = GetFreeSfxSource()
    src.gain   = SFX_GAIN * (gainMult or 1.0)
    src.panning = 0
    src:Play(snd)
end

-- ----------------------------------------------------------------------------
-- 公开：3D 声像音效（根据屏幕 X 偏移声道，超出屏幕衰减）
-- ----------------------------------------------------------------------------
function M.PlaySFXPanned(key, screenX, screenW, gainMult)
    local path = SFX[key]
    if not path then return end
    local snd = LoadSound(path)
    if not snd then return end

    local src      = GetFreeSfxSource()
    local cx       = screenW * 0.5
    -- 声像 -1（左）~ +1（右）
    local pan      = math.max(-1, math.min(1, (screenX - cx) / cx))
    -- 距离衰减：超出屏幕中心越远越小，最低 0.3
    local distRatio = math.abs(screenX - cx) / cx
    local volMult   = math.max(0.3, 1.0 - distRatio * 0.55)

    src.gain    = SFX_GAIN * (gainMult or 1.0) * volMult
    src.panning = pan
    src:Play(snd)
end

-- ============================================================================
-- 武器音效
-- ============================================================================

function M.PlayWeaponFire(weaponName)
    local key = WEAPON_FIRE_SFX[weaponName] or "glock_fire"
    local vol = 5.0
    if key == "knife_slash" then vol = 2.16 end  -- 近战刀：降低 52%
    if key == "glock_fire" then vol = 5.2 end  -- 手枪：提升音量
    if key == "mp5_fire" or key == "uzi_fire" or key == "p90_fire" then vol = 7.0 end  -- SMG
    if key == "pkm_fire" or key == "akm_fire" or key == "m870_fire" then vol = 5.5 end  -- 步枪/霰弹
    if key == "awm_fire" or key == "deagle_fire" then vol = 6.0 end  -- 狙击/沙鹰
    M.PlaySFX(key, vol)
end

function M.PlayWeaponReload(weaponName)
    local key = WEAPON_RELOAD_SFX[weaponName] or "glock_reload"
    M.PlaySFX(key, 4.0)
end

function M.PlayEmptyClick()
    M.PlaySFX("empty_click", 3.5)
end

function M.PlayJammed()
    M.PlaySFX("weapon_jammed", 2.5)
end

-- 子弹落点音效（设计文档：不播敌人受击肉声）
function M.PlayBulletImpact(hitEnemy)
    if not hitEnemy then
        M.PlaySFX("bullet_wall", 3.2)
    end
    -- hitEnemy = true 时静音（已按设计文档去掉受击肉声）
end

-- ============================================================================
-- 玩家音效
-- ============================================================================

-- 脚步（交替两个采样，间隔 0.30s）
function M.PlayFootstep(dt, isMoving)
    if not isMoving then
        footstepTimer = 0
        return
    end
    footstepTimer = footstepTimer + dt
    if footstepTimer >= 0.30 then
        footstepTimer = 0
        footstepIdx   = (footstepIdx % 2) + 1
        M.PlaySFX("footstep_0" .. footstepIdx, 0.55)
    end
end

function M.PlayDeath()
    M.PlaySFX("death_player", 1.0)
end

function M.PlayHeal()
    M.PlaySFX("heal_bandage", 0.9)
end

function M.PlayExtractionSuccess()
    M.PlaySFX("extraction_ok", 1.0)
end

function M.PlayTeleportBeam()
    M.PlaySFX("teleport_beam", 0.7)
end

-- ============================================================================
-- 敌人音效
-- ============================================================================

function M.PlayEnemySpotted()
    M.PlaySFX("enemy_spotted", 0.45)
end

function M.PlayEnemyHit()
    M.PlaySFX("enemy_hit", 0.40)
end

function M.PlayEnemyDie()
    M.PlaySFX("enemy_die", 0.55)
end

-- Boss 专属
function M.PlayBossRoar()
    M.PlaySFX("boss_roar", 0.70)
end

function M.PlayBossAttack()
    M.PlaySFX("boss_attack", 0.60)
end

function M.PlayBossDie()
    M.PlaySFX("boss_die", 0.70)
end

-- 狙击手射击音效
function M.PlaySniperShoot()
    M.PlaySFX("sniper_shoot", 0.60)
end

-- ============================================================================
-- UI 音效
-- ============================================================================

function M.PlayBtnHover()      M.PlaySFX("btn_hover",       0.45) end
function M.PlayBtnClick()      M.PlaySFX("btn_click",       0.9)  end
function M.PlayPanelOpen()     M.PlaySFX("panel_open",      0.8)  end
function M.PlayPanelClose()    M.PlaySFX("panel_close",     0.8)  end
function M.PlayPickup()        M.PlaySFX("item_pickup",     0.9)  end
function M.PlayCoin()          M.PlaySFX("coin",            0.9)  end
function M.PlayPurchase()      M.PlaySFX("item_purchase",   0.9)  end
function M.PlayEquip()         M.PlaySFX("equip_change",    0.85) end
function M.PlayUpgradeOK()     M.PlaySFX("upgrade_success", 1.0)  end
function M.PlayUpgradeFail()   M.PlaySFX("upgrade_fail",    0.85) end
function M.PlayError()         M.PlaySFX("error",           0.75) end
function M.PlayNotify()        M.PlaySFX("notification",    0.7)  end
function M.PlayNewFloor()      M.PlaySFX("new_floor",       1.0)  end

-- ============================================================================
-- BGM 状态机（游戏状态切换时调用）
-- ============================================================================

function M.OnStateChange(newState, isBossFloor)
    if newState == "menu" or newState == "loadout" then
        M.PlayBGM("menu")
    elseif newState == "playing" then
        if isBossFloor then
            M.PlayBGM("boss")
        else
            M.PlayBGM("dungeon")
        end
    elseif newState == "paused" then
        -- 暂停保留当前 BGM
    elseif newState == "extract_choice" or newState == "reward" then
        -- 保留地牢/Boss BGM
    elseif newState == "win" then
        M.PlaySFX("extraction_ok", 1.0)  -- 撤离成功音效
        M.PlayBGM("extract")
    elseif newState == "gameover" then
        M.StopBGM()
        M.PlaySFX("death_player", 1.0)
        M.PlayBGM("death")
    end
end

-- Boss 登场（地牢层突然切换到 Boss BGM）
function M.OnBossAppear()
    M.PlayBossRoar()
    M.PlayBGM("boss")
end

-- Boss 击杀（恢复地牢 BGM）
function M.OnBossKilled()
    M.PlayBossDie()
    M.PlayBGM("dungeon")
end

-- ============================================================================
-- 音量控制（暂停菜单滑块）
-- ============================================================================

function M.GetBGMVolume()  return BGM_GAIN end
function M.GetSFXVolume()  return SFX_GAIN end

function M.SetBGMVolume(v)
    BGM_GAIN = math.max(0, math.min(1, v))
    if bgmSource then bgmSource.gain = BGM_GAIN end
end

function M.SetSFXVolume(v)
    local oldGain = SFX_GAIN
    SFX_GAIN = math.max(0, math.min(1, v))
    -- 所有 source 立即按比例缩放（包括正在播放的）
    for _, src in ipairs(sfxSources) do
        if src.playing and oldGain > 0 then
            -- 按比例缩放：保持 gainMult 不变
            src.gain = src.gain * (SFX_GAIN / oldGain)
        else
            src.gain = SFX_GAIN
        end
    end
end

return M
