Scriptname SS_MCM extends SKI_ConfigBase

; =============================================================
; Simple Survival (SS) - MCM (safe version for Papyrus, no Var)
; =============================================================

Int Property MAX_ROWS = 64 Auto
String Property ConfigPath = "SS_WeatherConfig.json" Auto

; ---------- MCM identity required by SkyUI ----------
String Function GetName()
    return "Simple Survival (Weather)"
EndFunction

Int Function GetVersion()
    ; bump to force SkyUI to notice updates if cached
    return 10002
EndFunction

; ---------- Build/Version Tag + Debug ----------
bool   property SS_DEBUG    auto
string property SS_BUILD_TAG auto

String _pageOverview = "Overview"
String _pageWeather  = "Weather"

Float _lastPct = 0.0
Float _lastWarmth = 0.0
Float _lastEnv = 0.0
Int   _lastTier = 0
String _lastReason = ""

Int oidHdrWeather
Int oidWarmth
Int oidEnv
Int oidTier
Int oidPct

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

String Function F0(Float v)
    Float r = Math.Floor(v + 0.5)
    return "" + r
EndFunction

String Function F1(Float v)
    Float r = Math.Floor((v * 10.0) + 0.5) / 10.0
    return "" + r
EndFunction

Event OnConfigInit()
    ModName = "Simple Survival (Weather)"
    Pages = new String[2]
    Pages[0] = _pageOverview
    Pages[1] = _pageWeather

    RegisterForModEvent("SS_WeatherTier",       "OnTierPct")
    RegisterForModEvent("SS_WeatherTierLevel",  "OnTierLevel")
    ; legacy names
    RegisterForModEvent("SS_WeatherEnvResult",  "OnEnvResult")
    RegisterForModEvent("SS_WeatherPlayerResult","OnPlayerResult")
    ; split result channels
    RegisterForModEvent("SS_WeatherEnvResult3",   "OnEnvResult3")
    RegisterForModEvent("SS_WeatherEnvResult4",   "OnEnvResult4")
    RegisterForModEvent("SS_WeatherPlayerResult3","OnPlayerResult3")
    RegisterForModEvent("SS_WeatherPlayerResult4","OnPlayerResult4")
EndEvent

Event OnGameReload()
    Parent.OnGameReload()
    ModName = "Simple Survival (Weather)"
    ; re-register to be safe
    RegisterForModEvent("SS_WeatherTier",       "OnTierPct")
    RegisterForModEvent("SS_WeatherTierLevel",  "OnTierLevel")
    ; legacy names
    RegisterForModEvent("SS_WeatherEnvResult",  "OnEnvResult")
    RegisterForModEvent("SS_WeatherPlayerResult","OnPlayerResult")
    ; split result channels
    RegisterForModEvent("SS_WeatherEnvResult3",   "OnEnvResult3")
    RegisterForModEvent("SS_WeatherEnvResult4",   "OnEnvResult4")
    RegisterForModEvent("SS_WeatherPlayerResult3","OnPlayerResult3")
    RegisterForModEvent("SS_WeatherPlayerResult4","OnPlayerResult4")
    if SS_BUILD_TAG == ""
        SS_BUILD_TAG = "MCM 2025-10-15.c"
    endif
    Debug.Trace("[SS_MCM] OnGameReload build=" + SS_BUILD_TAG)
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
EndEvent

Event OnPlayerResult4(String evn, String s, Float f, Form sender)
    OnPlayerResult3(evn, s, f, sender)
EndEvent

Event OnPageReset(String a_page)
    If a_page == _pageOverview
        BuildPageOverview()
    ElseIf a_page == _pageWeather
        BuildPageWeather()
    EndIf
EndEvent

Function BuildPageOverview()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Weather")
    oidWarmth = AddTextOption("Player warmth", F0(_lastWarmth))
    oidEnv    = AddTextOption("Environmental score", F0(_lastEnv))
    oidPct    = AddTextOption("Preparedness", (F0(_lastPct) + "%"))
    oidTier   = AddTextOption("Tier", ("" + _lastTier))
EndFunction

Function BuildPageWeather()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Environment Weights")

    ; Sliders read directly from JSON with sane fallbacks; no dummy arrays
    oidReg0 = AddSliderOption("Regional Pleasant (0)", GetF("weights.regional.0", 0.0), "{0}")
    oidReg1 = AddSliderOption("Regional Cloudy (1)",  GetF("weights.regional.1", 5.0), "{0}")
    oidReg2 = AddSliderOption("Regional Rainy (2)",   GetF("weights.regional.2", 15.0), "{0}")
    oidReg3 = AddSliderOption("Regional Snow (3)",    GetF("weights.regional.3", 25.0), "{0}")
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



