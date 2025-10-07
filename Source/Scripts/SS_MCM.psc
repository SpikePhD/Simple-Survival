Scriptname SS_MCM extends SKI_ConfigBase

Import JsonUtil

; ----------------------------
; Constants / keys
; ----------------------------
String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto

; Weather
Int _optWeatherHeader
Int _optColdEnable
Int _optWarmthReq
Int _optWeatherBase
Int _optWeatherTerrainSnow
Int _optWeatherSun
Int _optWeatherNight
Int _optWeatherRain
Int _optWeatherSnow
Int _optWeatherWind
Int _optWeatherSwim
Int _optWarmthReadout

; Food & Hunger
Int _optFoodHeader
Int _optHungerEnable
Int _optRawExpire
Int _optCookedExpire
Int _optHungerTick

; Rest
Int _optRestHeader
Int _optRestEnable
Int _optMaxBedrollHours
Int _optMaxWildernessHours
Int _optFatigueTick

; Debug
Int _optDebugHeader
Int _optDebugEnable
Int _optDebugTrace
Int _optDebugPing

Quest Property SS_CoreQuest Auto

String _currentWarmthDisplay = "--"
String _currentRequirementDisplay = "--"

; ----------------------------
; MCM lifecycle
; ----------------------------
Event OnConfigInit()
  Pages = new String[1]
  Pages[0] = "Simple Survival"
EndEvent

Event OnPageReset(String a_page)
  If (a_page != "Simple Survival")
    Return
  EndIf

  SetCursorFillMode(TOP_TO_BOTTOM)

  ; === Weather ===
  _optWeatherHeader = AddHeaderOption("Weather")
  _optColdEnable    = AddToggleOption("Enable cold effects", GetB("weather.cold.enable"))
  UpdateWarmthCache()
  _optWarmthReq       = AddTextOption("Warmth required to be safe", _currentRequirementDisplay)
  _optWeatherBase        = AddSliderOption("Base warmth needed", GetF("weather.cold.baseRequirement"), "{0}")
  _optWeatherTerrainSnow = AddSliderOption("Snowy terrain bonus", GetF("weather.cold.environmentSnowBonus"), "{0}")
  _optWeatherSun         = AddSliderOption("Sunny day bonus", GetF("weather.cold.sunPenalty"), "{0}")
  _optWeatherNight       = AddSliderOption("Night penalty", GetF("weather.cold.nightPenalty"), "{0}")
  _optWeatherRain        = AddSliderOption("Rain penalty", GetF("weather.cold.rainPenalty"), "{0}")
  _optWeatherSnow        = AddSliderOption("Snow weather penalty", GetF("weather.cold.snowPenalty"), "{0}")
  _optWeatherWind        = AddSliderOption("Wind penalty", GetF("weather.cold.windPenalty"), "{0}")
  _optWeatherSwim        = AddSliderOption("Swimming penalty", GetF("weather.cold.swimPenalty"), "{0}")
  _optWarmthReadout   = AddTextOption("Current warmth / req:", _currentWarmthDisplay)
  RefreshWarmthReadout()

  AddEmptyOption()

  ; === Food & Hunger ===
  _optFoodHeader    = AddHeaderOption("Food & Hunger")
  _optHungerEnable  = AddToggleOption("Enable hunger", GetB("hunger.enable"))
  _optRawExpire     = AddSliderOption("Raw food expires (game hours)", GetF("hunger.rawExpireHours"), "{0}")
  _optCookedExpire  = AddSliderOption("Cooked food expires (game hours)", GetF("hunger.cookedExpireHours"), "{0}")
  _optHungerTick    = AddSliderOption("Hunger drain per tick", GetF("hunger.tick"), "{2}")

  AddEmptyOption()

  ; === Rest ===
  _optRestHeader        = AddHeaderOption("Rest")
  _optRestEnable        = AddToggleOption("Enable fatigue", GetB("rest.enable"))
  _optMaxBedrollHours   = AddSliderOption("Max sleep on bedroll (h)", GetF("rest.maxBedrollHours"), "{0}")
  _optMaxWildernessHours= AddSliderOption("Max sleep in wilderness (h)", GetF("rest.maxWildernessHours"), "{0}")
  _optFatigueTick       = AddSliderOption("Fatigue gain per tick", GetF("rest.tick"), "{2}")

AddEmptyOption()
_optDebugHeader = AddHeaderOption("Debug")
_optDebugEnable = AddToggleOption("Enable on-screen debug", GetB("debug.enable"))
_optDebugTrace  = AddToggleOption("Write traces to Papyrus log", GetB("debug.trace"))
_optDebugPing   = AddTextOption("Ping driver (test event)", "Send")

EndEvent

; ----------------------------
; Clicks (toggles)
; ----------------------------
Event OnOptionSelect(Int a_option)
  If a_option == _optColdEnable
    Bool v = !GetB("weather.cold.enable")
    SetB("weather.cold.enable", v)
    SetToggleOptionValue(a_option, v)

  ElseIf a_option == _optHungerEnable
    Bool v2 = !GetB("hunger.enable")
    SetB("hunger.enable", v2)
    SetToggleOptionValue(a_option, v2)

  ElseIf a_option == _optRestEnable
    Bool v3 = !GetB("rest.enable")
    SetB("rest.enable", v3)
    SetToggleOptionValue(a_option, v3)

  ElseIf a_option == _optDebugEnable
    Bool v4 = !GetB("debug.enable")
    SetB("debug.enable", v4)
    SetToggleOptionValue(a_option, v4)

  ElseIf a_option == _optDebugTrace
    Bool v5 = !GetB("debug.trace")
    SetB("debug.trace", v5)
    SetToggleOptionValue(a_option, v5)

  ElseIf a_option == _optDebugPing
    Int h = ModEvent.Create("SS_SetCold")
    If h
      ModEvent.PushString(h, "-5.0") ; speed delta as string
      ModEvent.PushFloat(h, 0.8)     ; regen multiplier as float
      ModEvent.Send(h)
      Debug.Notification("SS: Ping sent (-5 speed, 0.8 regen)")
    EndIf
  EndIf
EndEvent

; ----------------------------
; Sliders - open dialog with proper ranges
; ----------------------------
Event OnOptionSliderOpen(Int a_option)
  If a_option == _optWeatherBase
    SetSliderDialogStartValue(GetF("weather.cold.baseRequirement"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherTerrainSnow
    SetSliderDialogStartValue(GetF("weather.cold.environmentSnowBonus"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherSun
    SetSliderDialogStartValue(GetF("weather.cold.sunPenalty"))
    SetSliderDialogRange(-200.0, 200.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherNight
    SetSliderDialogStartValue(GetF("weather.cold.nightPenalty"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherRain
    SetSliderDialogStartValue(GetF("weather.cold.rainPenalty"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherSnow
    SetSliderDialogStartValue(GetF("weather.cold.snowPenalty"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherWind
    SetSliderDialogStartValue(GetF("weather.cold.windPenalty"))
    SetSliderDialogRange(0.0, 300.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherSwim
    SetSliderDialogStartValue(GetF("weather.cold.swimPenalty"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optRawExpire
    SetSliderDialogStartValue(GetF("hunger.rawExpireHours"))
    SetSliderDialogRange(1.0, 72.0)
    SetSliderDialogInterval(1.0)

  ElseIf a_option == _optCookedExpire
    SetSliderDialogStartValue(GetF("hunger.cookedExpireHours"))
    SetSliderDialogRange(3.0, 168.0)
    SetSliderDialogInterval(1.0)

  ElseIf a_option == _optHungerTick
    SetSliderDialogStartValue(GetF("hunger.tick"))
    SetSliderDialogRange(0.0, 5.0)
    SetSliderDialogInterval(0.05)

  ElseIf a_option == _optMaxBedrollHours
    SetSliderDialogStartValue(GetF("rest.maxBedrollHours"))
    SetSliderDialogRange(1.0, 12.0)
    SetSliderDialogInterval(1.0)

  ElseIf a_option == _optMaxWildernessHours
    SetSliderDialogStartValue(GetF("rest.maxWildernessHours"))
    SetSliderDialogRange(1.0, 12.0)
    SetSliderDialogInterval(1.0)

  ElseIf a_option == _optFatigueTick
    SetSliderDialogStartValue(GetF("rest.tick"))
    SetSliderDialogRange(0.0, 5.0)
    SetSliderDialogInterval(0.05)
  EndIf
EndEvent

Event OnOptionSliderAccept(Int a_option, Float a_value)
  If a_option == _optWeatherBase
    SetF("weather.cold.baseRequirement", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()

  ElseIf a_option == _optWeatherTerrainSnow
    SetF("weather.cold.environmentSnowBonus", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()

  ElseIf a_option == _optWeatherSun
    SetF("weather.cold.sunPenalty", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()

  ElseIf a_option == _optWeatherNight
    SetF("weather.cold.nightPenalty", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()

  ElseIf a_option == _optWeatherRain
    SetF("weather.cold.rainPenalty", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()

  ElseIf a_option == _optWeatherSnow
    SetF("weather.cold.snowPenalty", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()

  ElseIf a_option == _optWeatherWind
    SetF("weather.cold.windPenalty", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()

  ElseIf a_option == _optWeatherSwim
    SetF("weather.cold.swimPenalty", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()

  ElseIf a_option == _optRawExpire
    SetF("hunger.rawExpireHours", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")

  ElseIf a_option == _optCookedExpire
    SetF("hunger.cookedExpireHours", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")

  ElseIf a_option == _optHungerTick
    SetF("hunger.tick", a_value)
    SetSliderOptionValue(a_option, a_value, "{2}")

  ElseIf a_option == _optMaxBedrollHours
    SetF("rest.maxBedrollHours", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")

  ElseIf a_option == _optMaxWildernessHours
    SetF("rest.maxWildernessHours", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")

  ElseIf a_option == _optFatigueTick
    SetF("rest.tick", a_value)
    SetSliderOptionValue(a_option, a_value, "{2}")
  EndIf
EndEvent

Event OnOptionHighlight(Int a_option)
  If a_option == _optWarmthReadout || a_option == _optWarmthReq
    RefreshWarmthReadout()
  EndIf
EndEvent

Event OnConfigClose()
  RefreshWarmthReadout()
EndEvent

Function UpdateWarmthCache()
  Float baseReq = GetF("weather.cold.baseRequirement")
  Float weatherBonus = 0.0
  Float safeReq = baseReq
  Float warmth = 0.0

  If SS_CoreQuest != None
    SS_Controller controller = SS_CoreQuest as SS_Controller
    If controller != None
      warmth = controller.GetLastWarmth()
      weatherBonus = controller.GetLastWeatherBonus()
      safeReq = controller.GetLastSafeRequirement()
      Float controllerBase = controller.LastBaseRequirement
      if controllerBase > 0.0 || baseReq <= 0.0
        baseReq = controllerBase
      endif
      if safeReq <= 0.0
        safeReq = baseReq + weatherBonus
      endif
      if weatherBonus <= 0.0 && safeReq > baseReq
        weatherBonus = safeReq - baseReq
      endif
      if weatherBonus < 0.0
        weatherBonus = 0.0
      endif
      Int warmthInt = (warmth + 0.5) as Int
      Int safeInt = (safeReq + 0.5) as Int
      Int baseInt = (baseReq + 0.5) as Int
      Int weatherInt = (weatherBonus + 0.5) as Int
      _currentRequirementDisplay = safeInt + " (base " + baseInt + " + weather " + weatherInt + ")"
      _currentWarmthDisplay = "Warmth " + warmthInt + " / " + safeInt + " (base " + baseInt + " + weather " + weatherInt + ")"
      return
    EndIf
  EndIf

  Int baseOnly = (baseReq + 0.5) as Int
  Int weatherOnly = (weatherBonus + 0.5) as Int
  Int safeOnly = (safeReq + 0.5) as Int
  _currentRequirementDisplay = safeOnly + " (base " + baseOnly + " + weather " + weatherOnly + ")"
  _currentWarmthDisplay = "Warmth -- / " + safeOnly + " (base " + baseOnly + " + weather " + weatherOnly + ")"
EndFunction

Function RefreshWarmthReadout()
  UpdateWarmthCache()
  If _optWarmthReq != 0
    SetTextOptionValue(_optWarmthReq, _currentRequirementDisplay)
  EndIf
  If _optWarmthReadout != 0
    SetTextOptionValue(_optWarmthReadout, _currentWarmthDisplay)
  EndIf
EndFunction

; ----------------------------
; JSON helpers (Path-based; portable)
; ----------------------------
Bool Function GetB(String path, Bool fallback = True)
  ; First try reading as int (0/1); if not present, fall back to bool.
  Int sentinel = -12345
  Int asInt = JsonUtil.GetPathIntValue(CFG_PATH, path, sentinel)
  if asInt != sentinel
    return asInt > 0
  endif
  return JsonUtil.GetPathBoolValue(CFG_PATH, path, fallback)
EndFunction

Int Function GetI(String path, Int fallback = 0)
  return JsonUtil.GetPathIntValue(CFG_PATH, path, fallback)
EndFunction

Float Function GetF(String path, Float fallback = 0.0)
  return JsonUtil.GetPathFloatValue(CFG_PATH, path, fallback)
EndFunction

Function SetB(String path, Bool v)
  Int i = 0
  if v
    i = 1
  endif
  JsonUtil.SetPathIntValue(CFG_PATH, path, i)
  JsonUtil.Save(CFG_PATH)
EndFunction

Function SetI(String path, Int v)
  JsonUtil.SetPathIntValue(CFG_PATH, path, v)
  JsonUtil.Save(CFG_PATH)
EndFunction

Function SetF(String path, Float v)
  JsonUtil.SetPathFloatValue(CFG_PATH, path, v)
  JsonUtil.Save(CFG_PATH)
EndFunction
