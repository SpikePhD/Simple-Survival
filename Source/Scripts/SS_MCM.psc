Scriptname SS_MCM extends SKI_ConfigBase

; =============================================================
; Simple Survival (SS) — MCM (safe version for Papyrus, no Var)
; =============================================================

Int Property MAX_ROWS = 64 Auto
String Property ConfigPath = "Data/SKSE/Plugins/SS_WeatherConfig.json" Auto

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
    Pages = new String[2]
    Pages[0] = _pageOverview
    Pages[1] = _pageWeather

    RegisterForModEvent("SS_WeatherTier",       "OnTierPct")
    RegisterForModEvent("SS_WeatherTierLevel",  "OnTierLevel")
    RegisterForModEvent("SS_WeatherEnvResult",  "OnEnvResult")
    RegisterForModEvent("SS_WeatherPlayerResult","OnPlayerResult")
EndEvent

Event OnTierPct(String evn, String s, Float f, Form sender)
    _lastPct = f
EndEvent

Event OnTierLevel(String evn, String s, Float f, Form sender)
    _lastTier = f as Int
EndEvent

Event OnEnvResult(String evn, String s, Float f, Form sender)
    _lastEnv = f
EndEvent

Event OnPlayerResult(String evn, String s, Float f, Form sender)
    _lastWarmth = f
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
    oidWarmth = AddTextOption("Player warmth", F1(_lastWarmth))
    oidEnv    = AddTextOption("Environmental score", F1(_lastEnv))
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