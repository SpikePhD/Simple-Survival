Scriptname SS_MCM extends SKI_ConfigBase

; =============================================================
; Simple Survival (SS) - MCM (safe version for Papyrus, no Var)
; Integer display + live refresh from cached values + status re-request
; PLUS: JSON-driven sliders for player slot BONUSES (Helmet/Armor/Boots/Bracelets/Cloak)
; Writes to SS/playerwarmth_config.json using DOT paths only:
;   player.slots.<Slot>.bonus
; =============================================================

Int Property MAX_ROWS = 64 Auto
; Legacy single-config path kept for backward compat but unused by routing helpers below
String Property ConfigPath = "SS/SS_WeatherConfig.json" Auto

; Player warmth constants (legacy defaults only; JSON overrides via sliders)
Float Property BONUS_HELMET    = 20.0 AutoReadOnly
Float Property BONUS_ARMOR     = 50.0 AutoReadOnly
Float Property BONUS_BOOTS     = 25.0 AutoReadOnly
Float Property BONUS_BRACELETS = 10.0 AutoReadOnly
Float Property BONUS_CLOAK     = 15.0 AutoReadOnly

; ===== Player JSON config path =====
String Property SLOT_CONFIG_PATH = "SS/playerwarmth_config.json" AutoReadOnly

; Environment config (unchanged)
String _envCfg    = "SS/environmentwarmth_config.json"
Bool   _envOk     = False

; ---------- MCM identity required by SkyUI ----------
String Function GetName()
    return "Simple Survival (Weather)"
EndFunction

Int Function GetVersion()
    ; bump to force SkyUI to notice updates if cached
    return 10012 ; slot bonus reads prefer lowercase -> canonical; writes mirror both
EndFunction

; ---------- Build/Version Tag + Debug ----------
bool   property SS_DEBUG     auto
string property SS_BUILD_TAG auto

String _pageOverview = "Overview"
String _pageWeather  = "Weather"

Float _lastPct = 0.0
Float _lastWarmth = 0.0
Float _lastEnv = 0.0
Int   _lastTier = 0
String _lastReason = ""

; track when the overview options actually exist
Bool _overviewReady = False
String _currentPage = ""

Int oidHdrWeather
Int oidMode
Int oidCurClass
Int oidRegClass
Int oidWarmth
Int oidEnv
Int oidTier
Int oidPct
Int oidRefresh

; ===== NEW: Slot bonus sliders (JSON) =====
Int oidHdrSlotBonuses
Int oidSlotHelmet
Int oidSlotArmor
Int oidSlotBoots
Int oidSlotBracelets
Int oidSlotCloak

; ===== existing controls (unchanged) =====
Int oidHdrWeights
Int oidReg0
Int oidReg1
Int oidReg2
Int oidReg3
Int oidAct0
Int oidAct1
Int oidAct2
Int oidAct3
Int oidInterior
Int oidExterior

Int oidHdrNight
Int oidNightStart
Int oidNightEnd
Int oidNightMul

Int oidHdrMask
Int oidMaskEnabled
Int oidMaskDedupe
Int oidMaskLen
Int[] oidMaskMask
Int[] oidMaskBonus
Int[] oidMaskLabel

Int oidHdrKW
Int oidKWLen

Int oidSave
Int oidReload

Bool Property DebugLog = False Auto

; ==== Null-safe helpers (no Var type, Papyrus compatible) ====

Function Log(String s)
    If DebugLog
        Debug.Trace("[SS_MCM] " + s)
    EndIf
EndFunction

; Return rounded-to-nearest integer as string (no trailing .0)
String Function F0(Float v)
    Float rf = Math.Floor(v + 0.5)
    Int ri = rf as Int
    return "" + ri
EndFunction

; One decimal place (if/when needed elsewhere)
String Function F1(Float v)
    Float r = Math.Floor((v * 10.0) + 0.5) / 10.0
    return "" + r
EndFunction

; Safe SetTextOptionValue (only after page is built)
Function SafeSet(Int oid, String text)
    if CanUpdateOverview() && oid >= 0
        SetTextOptionValue(oid, text)
    endif
EndFunction

Bool Function CanUpdateOverview()
    if !_overviewReady
        return False
    endif
    if _currentPage != _pageOverview
        return False
    endif
    if !Utility.IsInMenuMode()
        return False
    endif
    return True
EndFunction

; ================= JSON helpers for player slot bonuses =================
Bool _playerCfgOk = False
String _playerCfgPath = ""

Bool Function _TryLoadPlayerCfgAt(String file)
    Bool ok = JsonUtil.Load(file)
    if SS_DEBUG
        Debug.Trace("[SS_MCM] JsonUtil.Load('" + file + "') => " + ok)
        if ok && !JsonUtil.IsGood(file)
            Debug.Trace("[SS_MCM] JSON errors for '" + file + "': " + JsonUtil.GetErrors(file))
        endif
    endif
    if !ok
        return False
    endif
    ; Presence check: DOT path only
    Float fb = JsonUtil.GetFloatValue(file, "player.slots.Helmet.bonus", -12345.0)
    return fb != -12345.0
EndFunction

String Function _ResolvePlayerCfgPath()
    String[] cand = Utility.CreateStringArray(5)
    cand[0] = SLOT_CONFIG_PATH
    cand[1] = "Data/" + SLOT_CONFIG_PATH
    cand[2] = "SKSE/Plugins/" + SLOT_CONFIG_PATH
    cand[3] = "SKSE/Plugins/JsonUtil/" + SLOT_CONFIG_PATH
    cand[4] = "Data/SKSE/Plugins/JsonUtil/" + SLOT_CONFIG_PATH
    Int i = 0
    while i < cand.Length
        String f = cand[i]
        if f && f != ""
            if _TryLoadPlayerCfgAt(f)
                return f
            endif
        endif
        i += 1
    endwhile
    return SLOT_CONFIG_PATH
EndFunction

Function EnsurePlayerCfg()
	if _playerCfgOk
		return
	endif
	; Mirror Environment: fixed logical path under StorageUtilData
	_playerCfgPath = SLOT_CONFIG_PATH ; "SS/playerwarmth_config.json"
	JsonUtil.Load(_playerCfgPath) ; ok if file is missing; Save() will create it
	_playerCfgOk = True
	if SS_DEBUG
		Debug.Trace("[SS_MCM] Player cfg path='" + _playerCfgPath + "' (dot-paths)")
	endif
EndFunction

String Function _AltSlotKey(String k)
    if k == "Helmet"
        return "Helmet"
    elseif k == "Armor"
        return "Armor"
    elseif k == "Boots"
        return "Boots"
    elseif k == "Bracelets"
        return "Bracelets"
    elseif k == "Cloak"
        return "Cloak"
    endif
    return k
EndFunction

Bool Function _SlotKeyHasData(String file, String slotName)
    ; DOT path only
    Float fb = JsonUtil.GetFloatValue(file, "player.slots." + slotName + ".bonus", -12345.0)
    return fb != -12345.0
EndFunction

String Function _ResolveSlotKeyFor(String file, String canonical)
    ; No case/alias flipping anymore; JSON uses canonical keys
    if _SlotKeyHasData(file, canonical)
        return canonical
    endif
    return canonical
EndFunction

Float Function GetSlotBonus(String canonical, Float fallback)
	EnsurePlayerCfg()
	String slotName = canonical ; canonical only
	String dot = "player.slots." + slotName + ".bonus"
	Float sentinel = -1234567.89

	Float v = JsonUtil.GetFloatValue(_playerCfgPath, dot, sentinel)
	if v != sentinel
		return v
	endif

	; display-only compatibility
	String slash = "player/slots/" + slotName + "/bonus"
	v = JsonUtil.GetPathFloatValue(_playerCfgPath, slash, sentinel)
	if v != sentinel
		return v
	endif

	return fallback
EndFunction

Function SetSlotBonus(String canonical, Float value)
	EnsurePlayerCfg()
	String slotName = canonical
	String dot = "player.slots." + slotName + ".bonus"
	JsonUtil.SetFloatValue(_playerCfgPath, dot, value)
	JsonUtil.Save(_playerCfgPath)
	; Tell the player script to recompute immediately
	SendModEvent("SS_PlayerConfigChanged", slotName, value)
	if SS_DEBUG
		Debug.Trace("[SS_MCM] SetSlotBonus '" + slotName + "' -> " + value + " (dot-path) saved to '" + _playerCfgPath + "' and event sent")
	endif
EndFunction

; ================= /JSON helpers =================

Function RefreshOverview()
    SafeSet(oidMode, "Gear bonuses")
    SafeSet(oidWarmth, F0(_lastWarmth))
    SafeSet(oidEnv,    F0(_lastEnv))
    SafeSet(oidPct,    (F0(_lastPct) + "%"))
    SafeSet(oidTier,   ("" + _lastTier))
EndFunction

; Show current/regional weather classes
Function RefreshWeatherClasses()
    Int cur = 0
    Int reg = 0
    Weather wCur = Weather.GetCurrentWeather()
    if wCur
        cur = wCur.GetClassification()
    endif
    Weather wOut = Weather.GetOutgoingWeather()
    if wOut
        reg = wOut.GetClassification()
    else
        reg = cur
    endif
    if cur < 0
        cur = 0
    elseif cur > 3
        cur = 3
    endif
    if reg < 0
        reg = 0
    elseif reg > 3
        reg = 3
    endif
    SafeSet(oidCurClass, ClassName(cur))
    SafeSet(oidRegClass, ClassName(reg))
EndFunction

String Function ClassName(Int c)
    if c == 0
        return "Pleasant"
    elseif c == 1
        return "Cloudy"
    elseif c == 2
        return "Rainy"
    elseif c == 3
        return "Snow"
    endif
    return "Unknown"
EndFunction

; Fire a manual SS_Tick to force recomputation by subsystems
Function FireManualTick(string reason)
    Float snapshot = Utility.RandomInt(1, 100000) as Float
    int h = ModEvent.Create("SS_Tick4")
    bool okS = False
    bool okF = False
    bool okFm = False
    if h
        okS = ModEvent.PushString(h, reason)
        okF = ModEvent.PushFloat(h, snapshot)
        okFm = ModEvent.PushForm(h, Game.GetPlayer() as Form)
        if okS && okF && okFm
            ModEvent.Send(h)
        endif
    endif
    (Game.GetPlayer() as Form).SendModEvent("SS_Tick3", reason, snapshot)
    if SS_DEBUG
        Debug.Trace("[SS_MCM] FireManualTick reason=" + reason + " snapshot=" + snapshot + " okS=" + okS + " okF=" + okF + " okFm=" + okFm)
    endif
EndFunction

; Ask subsystems to re-emit their latest values (works with v3/v4/legacy)
Function RequestWeatherStatus()
    SendModEvent("SS_RequestWeatherStatus")
EndFunction

Event OnConfigInit()
    ModName = "Simple Survival (Weather)"
    Pages = new String[2]
    Pages[0] = _pageOverview
    Pages[1] = _pageWeather

    RegisterForModEvent("SS_WeatherTier",       "OnTierPct")
    RegisterForModEvent("SS_WeatherTierLevel",  "OnTierLevel")
    ; legacy names
    RegisterForModEvent("SS_WeatherEnvResult",   "OnEnvResult")
    RegisterForModEvent("SS_WeatherPlayerResult","OnPlayerResult")
    ; split result channels
    RegisterForModEvent("SS_WeatherEnvResult3",    "OnEnvResult3")
    RegisterForModEvent("SS_WeatherEnvResult4",    "OnEnvResult4")
    RegisterForModEvent("SS_WeatherPlayerResult3", "OnPlayerResult3")
    RegisterForModEvent("SS_WeatherPlayerResult4", "OnPlayerResult4")

    RequestWeatherStatus()
EndEvent

Event OnGameReload()
    Parent.OnGameReload()
    ModName = "Simple Survival (Weather)"
    ; re-register to be safe
    RegisterForModEvent("SS_WeatherTier",       "OnTierPct")
    RegisterForModEvent("SS_WeatherTierLevel",  "OnTierLevel")
    ; legacy names
    RegisterForModEvent("SS_WeatherEnvResult",   "OnEnvResult")
    RegisterForModEvent("SS_WeatherPlayerResult","OnPlayerResult")
    ; split result channels
    RegisterForModEvent("SS_WeatherEnvResult3",    "OnEnvResult3")
    RegisterForModEvent("SS_WeatherEnvResult4",    "OnEnvResult4")
    RegisterForModEvent("SS_WeatherPlayerResult3", "OnPlayerResult3")

    RegisterForModEvent("SS_WeatherPlayerResult4", "OnPlayerResult4")

    if SS_BUILD_TAG == ""
        SS_BUILD_TAG = "MCM 2025-10-18.slotSlidersJSON"
    endif
    Debug.Trace("[SS_MCM] OnGameReload build=" + SS_BUILD_TAG)

    RequestWeatherStatus()
EndEvent

Event OnTierPct(String evn, String detail, Float f, Form sender)
    _lastPct = f
    if SS_DEBUG
        Debug.Trace("[SS_MCM] TierPct evn=" + evn + " detail=" + detail + " f=" + f + " sender=" + sender)
    endif
EndEvent

Event OnTierLevel(String evn, String detail, Float f, Form sender)
    _lastTier = f as Int
    if SS_DEBUG
        Debug.Trace("[SS_MCM] TierLevel evn=" + evn + " detail=" + detail + " f=" + f + " sender=" + sender)
    endif
EndEvent

; legacy 3-arg with string second param (kept for compatibility)
Event OnEnvResult(String evn, String s, Float f)
    _lastEnv = f
    if SS_DEBUG
        Debug.Trace("[SS_MCM] EnvResult(legacy) evn=" + evn + " s=" + s + " f=" + f)
    endif
EndEvent

; new split handlers
Event OnEnvResult3(String evn, String detail, Float f, Form sender)
    _lastEnv = f
    if SS_DEBUG
        Debug.Trace("[SS_MCM] EnvResult3 evn=" + evn + " detail=" + detail + " f=" + f + " sender=" + sender)
    endif
EndEvent

Event OnEnvResult4(String evn, String s, Float f, Form sender)
    OnEnvResult3(evn, s, f, sender)
EndEvent

; legacy 3-arg with string second param (kept for compatibility)
Event OnPlayerResult(String evn, String s, Float f)
    _lastWarmth = f
    if SS_DEBUG
        Debug.Trace("[SS_MCM] PlayerResult(legacy) evn=" + evn + " s=" + s + " f=" + f)
    endif
EndEvent

; new split handlers
Event OnPlayerResult3(String evn, String detail, Float f, Form sender)
    _lastWarmth = f
    if SS_DEBUG
        Debug.Trace("[SS_MCM] PlayerResult3 evn=" + evn + " detail=" + detail + " f=" + f + " sender=" + sender)
    endif
    if CanUpdateOverview()
        RefreshOverview()
    endif
EndEvent

Event OnPlayerResult4(String evn, String s, Float f, Form sender)
    OnPlayerResult3(evn, s, f, sender)
EndEvent

Event OnPageReset(String a_page)
    _currentPage = a_page
    _overviewReady = False
    If a_page == _pageOverview
        BuildPageOverview()
        _overviewReady = True
        ; Immediately paint weather + cached numbers so we don't show '?' until the deferred update
        RefreshWeatherClasses()
        RefreshOverview()
        ; Ask subsystems; paint AFTER this event returns to avoid SkyUI error
        RequestWeatherStatus()
        RegisterForSingleUpdate(0.0) ; defer UI write out of OnPageReset
    ElseIf a_page == _pageWeather
        BuildPageWeather()
    EndIf
EndEvent
Event OnConfigClose()
    _overviewReady = False
    _currentPage = ""
EndEvent

Event OnOptionSelect(Int option)
    if option == oidRefresh
        if SS_DEBUG
            Debug.Trace("[SS_MCM] Refresh clicked")
        endif
        SafeSet(oidRefresh, "...")
        FireManualTick("MCMRefresh")
        RegisterForSingleUpdate(0.25)
    endif
EndEvent

Function BuildPageOverview()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Weather")
    oidRefresh = AddTextOption("Refresh now", "?")
    oidMode    = AddTextOption("Computation Mode",   "?")
    oidCurClass = AddTextOption("Current Weather",  "?")
    oidRegClass = AddTextOption("Regional Weather", "?")
    oidWarmth = AddTextOption("Player warmth",        F0(_lastWarmth))
    oidEnv    = AddTextOption("Environmental score", F0(_lastEnv))
    oidPct    = AddTextOption("Preparedness",         (F0(_lastPct) + "%"))
    oidTier   = AddTextOption("Tier",                 ("" + _lastTier))
EndFunction

Function BuildPageWeather()
    SetCursorFillMode(TOP_TO_BOTTOM)

    ; ===== Player Warmth Base Bonuses (gear occupancy only, JSON-backed) =====
    AddHeaderOption("Player Warmth Bonuses (JSON)")
    oidHdrSlotBonuses = AddHeaderOption("Slots")
    oidSlotHelmet     = AddSliderOption("Helmet",    GetSlotBonus("Helmet",    BONUS_HELMET),    "{0}")
    oidSlotArmor      = AddSliderOption("Armour",    GetSlotBonus("Armor",     BONUS_ARMOR),     "{0}")
    oidSlotBoots      = AddSliderOption("Boots",     GetSlotBonus("Boots",     BONUS_BOOTS),     "{0}")
    oidSlotBracelets  = AddSliderOption("Arms",      GetSlotBonus("Bracelets", BONUS_BRACELETS), "{0}")
    oidSlotCloak      = AddSliderOption("Cloak",     GetSlotBonus("Cloak",     BONUS_CLOAK),     "{0}")

    ; ===== Environment Warmth =====
    AddHeaderOption("Environment Warmth")
    ; Regional (classification of outgoing/current region)
    oidAct0 = AddSliderOption("Regional Pleasant", GetFE("weights.regional.0", 0.0),  "{0}")
    oidAct1 = AddSliderOption("Regional Cloudy",   GetFE("weights.regional.1", 5.0),  "{0}")
    oidAct2 = AddSliderOption("Regional Rainy",    GetFE("weights.regional.2", 15.0), "{0}")
    oidAct3 = AddSliderOption("Regional Snowy",    GetFE("weights.regional.3", 25.0), "{0}")

    ; Actual (current, immediate weather)
    oidInterior = AddSliderOption("Actual Pleasant", GetFE("weights.actual.0", 0.0),  "{0}")
    oidExterior = AddSliderOption("Actual Cloudy",   GetFE("weights.actual.1", 10.0), "{0}")
    oidSave     = AddSliderOption("Actual Rainy",    GetFE("weights.actual.2", 25.0), "{0}")
    oidReload   = AddSliderOption("Actual Snowy",    GetFE("weights.actual.3", 40.0), "{0}")

    oidNightStart = AddSliderOption("Interior", GetFE("weights.interior", 0.0), "{0}") ; -500..0 via slider open
    oidNightEnd   = AddSliderOption("Exterior", GetFE("weights.exterior", 5.0), "{0}")

    oidNightMul = AddSliderOption("Night multiplier", GetFE("night.multiplier", 1.25), "{1}") ; 0..10 step 0.1
EndFunction

; ===== Config helpers (split files) =====
Function EnsureEnvCfg()
    if _envOk
        return
    endif
    Bool ok = JsonUtil.Load(_envCfg)
    _envOk = ok
    if SS_DEBUG
        Debug.Trace("[SS_MCM] EnsureEnvCfg ok=" + ok + " path=" + _envCfg)
        if !ok
            Debug.Trace("[SS_MCM] ERROR: Could not load env config at path=" + _envCfg)
        endif
    endif
EndFunction

Float Function GetFE(String path, Float fallback)
    EnsureEnvCfg()
    return JsonUtil.GetFloatValue(_envCfg, path, fallback)
EndFunction

Function SetFE(String path, Float v)
    EnsureEnvCfg()
    JsonUtil.SetFloatValue(_envCfg, path, v)
EndFunction

Event OnOptionSliderOpen(Int option)
    ; Slot bonuses 0..500
    if option == oidSlotHelmet || option == oidSlotArmor || option == oidSlotBoots || option == oidSlotBracelets || option == oidSlotCloak
        SetSliderDialogRange(0.0, 500.0)
        SetSliderDialogInterval(1.0)
        Float cur = 0.0
        if option == oidSlotHelmet
            cur = GetSlotBonus("Helmet", BONUS_HELMET)
        elseif option == oidSlotArmor
            cur = GetSlotBonus("Armor", BONUS_ARMOR)
        elseif option == oidSlotBoots
            cur = GetSlotBonus("Boots", BONUS_BOOTS)
        elseif option == oidSlotBracelets
            cur = GetSlotBonus("Bracelets", BONUS_BRACELETS)
        elseif option == oidSlotCloak
            cur = GetSlotBonus("Cloak", BONUS_CLOAK)
        endif
        SetSliderDialogStartValue(cur)
        SetSliderDialogDefaultValue(cur)
        return
    endif

    ; Regional / Actual / Exterior: 0..500
    if option == oidAct0 || option == oidAct1 || option == oidAct2 || option == oidAct3 || option == oidInterior || option == oidExterior || option == oidSave || option == oidReload || option == oidNightEnd
        SetSliderDialogRange(0.0, 500.0)
        SetSliderDialogInterval(1.0)
        Float cur2 = 0.0
        if option == oidAct0
            cur2 = GetFE("weights.regional.0", 0.0)
        elseif option == oidAct1
            cur2 = GetFE("weights.regional.1", 5.0)
        elseif option == oidAct2
            cur2 = GetFE("weights.regional.2", 15.0)
        elseif option == oidAct3
            cur2 = GetFE("weights.regional.3", 25.0)
        elseif option == oidInterior
            cur2 = GetFE("weights.actual.0", 0.0)
        elseif option == oidExterior
            cur2 = GetFE("weights.actual.1", 10.0)
        elseif option == oidSave
            cur2 = GetFE("weights.actual.2", 25.0)
        elseif option == oidReload
            cur2 = GetFE("weights.actual.3", 40.0)
        elseif option == oidNightEnd
            cur2 = GetFE("weights.exterior", 5.0)
        endif
        SetSliderDialogStartValue(cur2)
        SetSliderDialogDefaultValue(cur2)
        return
    endif

    ; Interior: -500..0
    if option == oidNightStart
        SetSliderDialogRange(-500.0, 0.0)
        SetSliderDialogInterval(1.0)
        Float cur3 = GetFE("weights.interior", 0.0)
        SetSliderDialogStartValue(cur3)
        SetSliderDialogDefaultValue(cur3)
        return
    endif

    ; Night multiplier 0..10 step 0.1
    if option == oidNightMul
        SetSliderDialogRange(0.0, 10.0)
        SetSliderDialogInterval(0.1)
        Float cur4 = GetFE("night.multiplier", 1.25)
        SetSliderDialogStartValue(cur4)
        SetSliderDialogDefaultValue(cur4)
        return
    endif
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    ; Slot bonuses
    if option == oidSlotHelmet
        SetSlotBonus("Helmet", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidSlotArmor
        SetSlotBonus("Armor", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidSlotBoots
        SetSlotBonus("Boots", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidSlotBracelets
        SetSlotBonus("Bracelets", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidSlotCloak
        SetSlotBonus("Cloak", value)
        SetSliderOptionValue(option, value, "{0}")
    ; Regional
    elseif option == oidAct0
        SetFE("weights.regional.0", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidAct1
        SetFE("weights.regional.1", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidAct2
        SetFE("weights.regional.2", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidAct3
        SetFE("weights.regional.3", value)
        SetSliderOptionValue(option, value, "{0}")
    ; Actual
    elseif option == oidInterior
        SetFE("weights.actual.0", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidExterior
        SetFE("weights.actual.1", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidSave
        SetFE("weights.actual.2", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidReload
        SetFE("weights.actual.3", value)
        SetSliderOptionValue(option, value, "{0}")
    ; Interior / Exterior (weights)
    elseif option == oidNightStart
        SetFE("weights.interior", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidNightEnd
        SetFE("weights.exterior", value)
        SetSliderOptionValue(option, value, "{0}")
    ; Night multiplier
    elseif option == oidNightMul
        SetFE("night.multiplier", value)
        SetSliderOptionValue(option, value, "{1}")
    endif

    ; Save environment config if loaded (unchanged)
    if _envOk
        JsonUtil.Save(_envCfg)
    endif
    ; Request a recompute + re-emit
    FireManualTick("MCMRefresh")
    RegisterForSingleUpdate(0.25)
EndEvent

Event OnUpdate()
    ; After a short delay post-refresh, ask subsystems to re-emit and then paint cached numbers
    if SS_DEBUG
        Debug.Trace("[SS_MCM] OnUpdate -> RequestWeatherStatus + RefreshOverview + RefreshWeatherClasses")
    endif
    if !Utility.IsInMenuMode()
        return
    endif
    RequestWeatherStatus()
    RefreshOverview()
    RefreshWeatherClasses()
    SafeSet(oidRefresh, "?")
EndEvent