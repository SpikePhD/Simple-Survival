Scriptname SS_MCM extends SKI_ConfigBase

; =============================================================
; Simple Survival (SS) - MCM (safe version for Papyrus, no Var)
; Integer display + live refresh from cached values + status re-request
; =============================================================

Int Property MAX_ROWS = 64 Auto
String Property ConfigPath = "Data/SKSE/Plugins/SS_WeatherConfig.json" Auto

; ---------- MCM identity required by SkyUI ----------
String Function GetName()
    return "Simple Survival (Weather)"
EndFunction

Int Function GetVersion()
    ; bump to force SkyUI to notice updates if cached
    return 10005 ; +Refresh button, manual SS_Tick
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

Int oidHdrWeather
Int oidWarmth
Int oidEnv
Int oidTier
Int oidPct
Int oidRefresh

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
Int[] oidKWEditor
Int[] oidKWBonus

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
    if _overviewReady && oid > 0
        SetTextOptionValue(oid, text)
    endif
EndFunction

Function RefreshOverview()
    SafeSet(oidWarmth, F0(_lastWarmth))
    SafeSet(oidEnv,    F0(_lastEnv))
    SafeSet(oidPct,    (F0(_lastPct) + "%"))
    SafeSet(oidTier,   ("" + _lastTier))
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
        SS_BUILD_TAG = "MCM 2025-10-17.slotsUI"
    endif
    Debug.Trace("[SS_MCM] OnGameReload build=" + SS_BUILD_TAG)

    RequestWeatherStatus()
EndEvent

Event OnTierPct(String evn, String detail, Float f, Form sender)
    _lastPct = f
    if SS_DEBUG
        Debug.Trace("[SS_MCM] TierPct evn=" + evn + " detail=" + detail + " f=" + f + " sender=" + sender)
    endif
    ; no live UI write here; Overview updates only when that page is open
EndEvent

Event OnTierLevel(String evn, String detail, Float f, Form sender)
    _lastTier = f as Int
    if SS_DEBUG
        Debug.Trace("[SS_MCM] TierLevel evn=" + evn + " detail=" + detail + " f=" + f + " sender=" + sender)
    endif
    ; no live UI write here; Overview updates only when that page is open
EndEvent

; legacy 3-arg with string second param (kept for compatibility)
Event OnEnvResult(String evn, String s, Float f)
    _lastEnv = f
    if SS_DEBUG
        Debug.Trace("[SS_MCM] EnvResult(legacy) evn=" + evn + " s=" + s + " f=" + f)
    endif
    ; no live UI write here; Overview updates only when that page is open
EndEvent

; new split handlers
Event OnEnvResult3(String evn, String detail, Float f, Form sender)
    _lastEnv = f
    if SS_DEBUG
        Debug.Trace("[SS_MCM] EnvResult3 evn=" + evn + " detail=" + detail + " f=" + f + " sender=" + sender)
    endif
    ; no live UI write here; Overview updates only when that page is open
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
    ; no live UI write here; Overview updates only when that page is open
EndEvent

; new split handlers
Event OnPlayerResult3(String evn, String detail, Float f, Form sender)
    _lastWarmth = f
    if SS_DEBUG
        Debug.Trace("[SS_MCM] PlayerResult3 evn=" + evn + " detail=" + detail + " f=" + f + " sender=" + sender)
    endif
    ; no live UI write here; Overview updates only when that page is open
EndEvent

Event OnPlayerResult4(String evn, String s, Float f, Form sender)
    OnPlayerResult3(evn, s, f, sender)
EndEvent

Event OnPageReset(String a_page)
    _overviewReady = False
    If a_page == _pageOverview
        BuildPageOverview()
        _overviewReady = True
        ; Ask subsystems; paint AFTER this event returns to avoid SkyUI error
        RequestWeatherStatus()
        RegisterForSingleUpdate(0.0) ; defer UI write out of OnPageReset
    ElseIf a_page == _pageWeather
        BuildPageWeather()
    EndIf
EndEvent

Event OnOptionSelect(Int option)
    if option == oidRefresh
        FireManualTick("MCMRefresh")
        RegisterForSingleUpdate(0.25)
    endif
EndEvent

Function BuildPageOverview()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Weather")
    oidRefresh = AddTextOption("Refresh now", "?")
    oidWarmth = AddTextOption("Player warmth",        F0(_lastWarmth))
    oidEnv    = AddTextOption("Environmental score", F0(_lastEnv))
    oidPct    = AddTextOption("Preparedness",         (F0(_lastPct) + "%"))
    oidTier   = AddTextOption("Tier",                 ("" + _lastTier))
EndFunction

Function BuildPageWeather()
    SetCursorFillMode(TOP_TO_BOTTOM)

    ; ===== Player Warmth Base Bonuses (slot-based) =====
    AddHeaderOption("Player Warmth Base Bonuses")

    ; Slots live under player.slots.*.bonus
    oidKWLen = AddSliderOption("Helmet",  GetF("player.slots.helmet.bonus",    5.0),  "{0}") ; 0..500
    oidKWEditor = new Int[1] ; dummy to keep compiler happy for reused ids elsewhere
    oidKWBonus = new Int[1]
    oidReg0 = AddSliderOption("Armour",  GetF("player.slots.armor.bonus",     12.0), "{0}")
    oidReg1 = AddSliderOption("Boots",   GetF("player.slots.boots.bonus",     5.0),  "{0}")
    oidReg2 = AddSliderOption("Arms",    GetF("player.slots.bracelets.bonus", 3.0),  "{0}")
    oidReg3 = AddSliderOption("Cloak",   GetF("player.slots.cloak.bonus",     6.0),  "{0}")

    ; ===== Environment Warmth =====
    AddHeaderOption("Environment Warmth")
    ; Regional (classification of outgoing/current region)
    oidAct0 = AddSliderOption("Regional Pleasant", GetF("weights.regional.0", 0.0),  "{0}")
    oidAct1 = AddSliderOption("Regional Cloudy",   GetF("weights.regional.1", 5.0),  "{0}")
    oidAct2 = AddSliderOption("Regional Rainy",    GetF("weights.regional.2", 15.0), "{0}")
    oidAct3 = AddSliderOption("Regional Snowy",    GetF("weights.regional.3", 25.0), "{0}")

    ; Actual (current, immediate weather)
    oidInterior = AddSliderOption("Actual Pleasant", GetF("weights.actual.0", 0.0),  "{0}")
    oidExterior = AddSliderOption("Actual Cloudy",   GetF("weights.actual.1", 10.0), "{0}")
    oidSave     = AddSliderOption("Actual Rainy",    GetF("weights.actual.2", 25.0), "{0}")
    oidReload   = AddSliderOption("Actual Snowy",    GetF("weights.actual.3", 40.0), "{0}")

    oidNightStart = AddSliderOption("Interior", GetF("weights.interior", 0.0), "{0}") ; -500..0 via slider open
    oidNightEnd   = AddSliderOption("Exterior", GetF("weights.exterior", 5.0), "{0}")

    oidNightMul = AddSliderOption("Night multiplier", GetF("night.multiplier", 1.25), "{1}") ; 0..10 step 0.1
EndFunction

Float Function GetF(String path, Float fallback)
    return JsonUtil.GetFloatValue(ConfigPath, path, fallback)
EndFunction

Int Function GetI(String path, Int fallback)
    Float f = JsonUtil.GetFloatValue(ConfigPath, path, fallback as Float)
    return f as Int
EndFunction

String Function GetS(String path, String fallback)
    return JsonUtil.GetStringValue(ConfigPath, path, fallback)
EndFunction

Function SetF(String path, Float v)
    JsonUtil.SetFloatValue(ConfigPath, path, v)
EndFunction

Event OnOptionSliderOpen(Int option)
    ; Player slot sliders: 0..500 integer
    if option == oidKWLen || option == oidReg0 || option == oidReg1 || option == oidReg2 || option == oidReg3
        SetSliderDialogRange(0.0, 500.0)
        SetSliderDialogInterval(1.0)
        Float cur = 0.0
        if option == oidKWLen
            cur = GetF("player.slots.helmet.bonus", 5.0)
        elseif option == oidReg0
            cur = GetF("player.slots.armor.bonus", 12.0)
        elseif option == oidReg1
            cur = GetF("player.slots.boots.bonus", 5.0)
        elseif option == oidReg2
            cur = GetF("player.slots.bracelets.bonus", 3.0)
        elseif option == oidReg3
            cur = GetF("player.slots.cloak.bonus", 6.0)
        endif
        SetSliderDialogStartValue(cur)
        SetSliderDialogDefaultValue(cur)
        return
    endif

    ; Regional / Actual / Exterior: 0..500
    if option == oidAct0 || option == oidAct1 || option == oidAct2 || option == oidAct3 || option == oidInterior || option == oidExterior || option == oidSave || option == oidReload
        SetSliderDialogRange(0.0, 500.0)
        SetSliderDialogInterval(1.0)
        Float cur2 = 0.0
        if option == oidAct0
            cur2 = GetF("weights.regional.0", 0.0)
        elseif option == oidAct1
            cur2 = GetF("weights.regional.1", 5.0)
        elseif option == oidAct2
            cur2 = GetF("weights.regional.2", 15.0)
        elseif option == oidAct3
            cur2 = GetF("weights.regional.3", 25.0)
        elseif option == oidInterior
            cur2 = GetF("weights.actual.0", 0.0)
        elseif option == oidExterior
            cur2 = GetF("weights.actual.1", 10.0)
        elseif option == oidSave
            cur2 = GetF("weights.actual.2", 25.0)
        elseif option == oidReload
            cur2 = GetF("weights.actual.3", 40.0)
        endif
        SetSliderDialogStartValue(cur2)
        SetSliderDialogDefaultValue(cur2)
        return
    endif

    ; Interior: -500..0
    if option == oidNightStart
        SetSliderDialogRange(-500.0, 0.0)
        SetSliderDialogInterval(1.0)
        Float cur3 = GetF("weights.interior", 0.0)
        SetSliderDialogStartValue(cur3)
        SetSliderDialogDefaultValue(cur3)
        return
    endif

    ; Night multiplier 0..10 step 0.1
    if option == oidNightMul
        SetSliderDialogRange(0.0, 10.0)
        SetSliderDialogInterval(0.1)
        Float cur4 = GetF("night.multiplier", 1.25)
        SetSliderDialogStartValue(cur4)
        SetSliderDialogDefaultValue(cur4)
        return
    endif
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    ; Player slots
    if option == oidKWLen
        SetF("player.slots.helmet.bonus", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidReg0
        SetF("player.slots.armor.bonus", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidReg1
        SetF("player.slots.boots.bonus", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidReg2
        SetF("player.slots.bracelets.bonus", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidReg3
        SetF("player.slots.cloak.bonus", value)
        SetSliderOptionValue(option, value, "{0}")
    ; Regional
    elseif option == oidAct0
        SetF("weights.regional.0", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidAct1
        SetF("weights.regional.1", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidAct2
        SetF("weights.regional.2", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidAct3
        SetF("weights.regional.3", value)
        SetSliderOptionValue(option, value, "{0}")
    ; Actual
    elseif option == oidInterior
        SetF("weights.actual.0", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidExterior
        SetF("weights.actual.1", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidSave
        SetF("weights.actual.2", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidReload
        SetF("weights.actual.3", value)
        SetSliderOptionValue(option, value, "{0}")
    ; Interior / Exterior (weights)
    elseif option == oidNightStart
        SetF("weights.interior", value)
        SetSliderOptionValue(option, value, "{0}")
    elseif option == oidNightEnd
        SetF("weights.exterior", value)
        SetSliderOptionValue(option, value, "{0}")
    ; Night multiplier
    elseif option == oidNightMul
        SetF("night.multiplier", value)
        SetSliderOptionValue(option, value, "{1}")
    endif

    JsonUtil.Save(ConfigPath)
    ; Request a recompute + re-emit
    FireManualTick("MCMRefresh")
    RegisterForSingleUpdate(0.25)
EndEvent

Event OnUpdate()
    ; After a short delay post-refresh, ask subsystems to re-emit and then paint cached numbers
    RequestWeatherStatus()
    RefreshOverview()
EndEvent