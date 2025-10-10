Scriptname SS_MCM extends SKI_ConfigBase

Import JsonUtil

; ----------------------------
; Constants / keys
; ----------------------------
String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto

; Weather
Int _optOverviewWeatherHeader
Int _optOverviewAreaClimate
Int _optOverviewCurrentWeather
Int _optOverviewEnvWarmth
Int _optOverviewPlayerWarmth
Int _optOverviewStatus
Int _optOverviewHungerHeader
Int _optOverviewHungerStub
Int _optOverviewRestHeader
Int _optOverviewRestStub
Int _optWeatherHeader
Int _optColdEnable
Int _optWarmthReq
Int _optBaseWarmth
Int _optRegionHeader
Int _optRegionPleasant
Int _optRegionCloudy
Int _optRegionRainy
Int _optRegionSnowy
Int _optWeatherModifiersHeader
Int _optWeatherPleasant
Int _optWeatherCloudy
Int _optWeatherRainy
Int _optWeatherSnowy
Int _optEnvironmentHeader
Int _optExteriorAdjust
Int _optInteriorAdjust
Int _optNightMultiplier
Int _optWarmthReadout
Int _optPenaltyReadout
Int _optUIHeader
Int _optImmersionToasts
Int _optDebugToasts

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
String _currentPenaltyDisplay = "Health, Stamina, Magicka: 0%, Speed: 0%"
Float _lastWarmthValue = 0.0
Float _lastSafeRequirementValue = 0.0
Float _lastBaseRequirementValue = 0.0
Float _lastModifierValue = 0.0
Int _lastWarmthInt = 0
Int _lastSafeRequirementInt = 0
Int _lastBaseRequirementInt = 0
Int _lastModifierInt = 0
String _overviewAreaClimateDisplay = "--"
String _overviewCurrentWeatherDisplay = "--"
String _overviewEnvWarmthDisplay = "0"
String _overviewPlayerWarmthDisplay = "0"
String _overviewStatusDisplay = "--"

; ----------------------------
; MCM lifecycle
; ----------------------------
Event OnConfigInit()
  Pages = new String[4]
  Pages[0] = "Overview"
  Pages[1] = "Weather"
  Pages[2] = "Food"
  Pages[3] = "Rest"
EndEvent

Event OnPageReset(String a_page)
  SetCursorFillMode(TOP_TO_BOTTOM)

  _optOverviewWeatherHeader = 0
  _optOverviewAreaClimate = 0
  _optOverviewCurrentWeather = 0
  _optOverviewEnvWarmth = 0
  _optOverviewPlayerWarmth = 0
  _optOverviewStatus = 0
  _optOverviewHungerHeader = 0
  _optOverviewHungerStub = 0
  _optOverviewRestHeader = 0
  _optOverviewRestStub = 0
  _optWarmthReadout = 0
  _optPenaltyReadout = 0

  If a_page == "Overview"
    UpdateOverviewCache()
    _optOverviewWeatherHeader = AddHeaderOption("Weather")
    _optOverviewAreaClimate = AddTextOption("Area Climate", _overviewAreaClimateDisplay)
    _optOverviewCurrentWeather = AddTextOption("Current Weather", _overviewCurrentWeatherDisplay)
    _optOverviewEnvWarmth = AddTextOption("Environmental Warmth Score", _overviewEnvWarmthDisplay)
    _optOverviewPlayerWarmth = AddTextOption("Player Warmth Score", _overviewPlayerWarmthDisplay)
    _optOverviewStatus = AddTextOption("Status", _overviewStatusDisplay)

    AddEmptyOption()

    _optOverviewHungerHeader = AddHeaderOption("Hunger")
    _optOverviewHungerStub = AddTextOption("Status", "Coming soon")

    AddEmptyOption()

    _optOverviewRestHeader = AddHeaderOption("Rest")
    _optOverviewRestStub = AddTextOption("Status", "Coming soon")

  ElseIf a_page == "Weather"
    _optWeatherHeader = AddHeaderOption("Cold Mechanics")
    _optColdEnable    = AddToggleOption("Enable cold effects", GetB("weather.cold.enable"))

    UpdateWarmthCache()
    _optWarmthReq   = AddTextOption("Warmth required to be safe", _currentRequirementDisplay)
    _optBaseWarmth  = AddSliderOption("Base warmth value", GetF("weather.cold.baseRequirement"), "{0}")

    _optRegionHeader   = AddHeaderOption("Region modifiers")
    _optRegionPleasant = AddSliderOption("Pleasant regions (FindWeather 0)", GetF("weather.cold.region.pleasant"), "{0}")
    _optRegionCloudy   = AddSliderOption("Cloudy regions (FindWeather 1)", GetF("weather.cold.region.cloudy"), "{0}")
    _optRegionRainy    = AddSliderOption("Rainy regions (FindWeather 2)", GetF("weather.cold.region.rainy"), "{0}")
    _optRegionSnowy    = AddSliderOption("Snowy regions (FindWeather 3)", GetF("weather.cold.region.snowy"), "{0}")

    _optWeatherModifiersHeader = AddHeaderOption("Weather modifiers")
    _optWeatherPleasant = AddSliderOption("Pleasant weather (GetCurrentWeather 0)", GetF("weather.cold.weather.pleasant"), "{0}")
    _optWeatherCloudy   = AddSliderOption("Cloudy weather (GetCurrentWeather 1)", GetF("weather.cold.weather.cloudy"), "{0}")
    _optWeatherRainy    = AddSliderOption("Rainy weather (GetCurrentWeather 2)", GetF("weather.cold.weather.rainy"), "{0}")
    _optWeatherSnowy    = AddSliderOption("Snowy weather (GetCurrentWeather 3)", GetF("weather.cold.weather.snowy"), "{0}")

    _optEnvironmentHeader = AddHeaderOption("Environment modifiers")
    _optExteriorAdjust    = AddSliderOption("Exterior adjustment", GetF("weather.cold.exteriorAdjust"), "{0}")
    _optInteriorAdjust    = AddSliderOption("Interior adjustment", GetF("weather.cold.interiorAdjust"), "{0}")
    _optNightMultiplier   = AddSliderOption("Night multiplier", GetF("weather.cold.nightMultiplier"), "{2}")

    _optUIHeader = AddHeaderOption("UI Feedback")
    _optImmersionToasts = AddToggleOption("Immersion toasts", GetB("ui.toasts.immersion"))
    _optDebugToasts     = AddToggleOption("Debug toasts", GetB("ui.toasts.debug"))

    AddEmptyOption()

    _optDebugHeader = AddHeaderOption("Debug")
    _optDebugEnable = AddToggleOption("Enable on-screen debug", GetB("debug.enable"))
    _optDebugTrace  = AddToggleOption("Write traces to Papyrus log", GetB("debug.trace"))
    _optDebugPing   = AddTextOption("Force refresh", "Refresh now")

  ElseIf a_page == "Food"
    _optFoodHeader    = AddHeaderOption("Food & Hunger")
    _optHungerEnable  = AddToggleOption("Enable hunger", GetB("hunger.enable"))
    _optRawExpire     = AddSliderOption("Raw food expires (game hours)", GetF("hunger.rawExpireHours"), "{0}")
    _optCookedExpire  = AddSliderOption("Cooked food expires (game hours)", GetF("hunger.cookedExpireHours"), "{0}")
    _optHungerTick    = AddSliderOption("Hunger drain per tick", GetF("hunger.tick"), "{2}")

  ElseIf a_page == "Rest"
    _optRestHeader         = AddHeaderOption("Rest")
    _optRestEnable         = AddToggleOption("Enable fatigue", GetB("rest.enable"))
    _optMaxBedrollHours    = AddSliderOption("Max sleep on bedroll (h)", GetF("rest.maxBedrollHours"), "{0}")
    _optMaxWildernessHours = AddSliderOption("Max sleep in wilderness (h)", GetF("rest.maxWildernessHours"), "{0}")
    _optFatigueTick        = AddSliderOption("Fatigue gain per tick", GetF("rest.tick"), "{2}")
  EndIf
EndEvent

; ----------------------------
; Clicks (toggles)
; ----------------------------
Event OnOptionSelect(Int a_option)
  Bool refreshNeeded = False

  If a_option == _optColdEnable
    Bool v = !GetB("weather.cold.enable")
    SetB("weather.cold.enable", v)
    SetToggleOptionValue(a_option, v)
    refreshNeeded = True

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

  ElseIf a_option == _optImmersionToasts
    Bool v6 = !GetB("ui.toasts.immersion")
    SetB("ui.toasts.immersion", v6)
    SetToggleOptionValue(a_option, v6)

  ElseIf a_option == _optDebugToasts
    Bool v7 = !GetB("ui.toasts.debug")
    SetB("ui.toasts.debug", v7)
    SetToggleOptionValue(a_option, v7)

  ElseIf a_option == _optDebugPing
    RequestControllerRefresh("MCM")
  EndIf

  If refreshNeeded
    RequestControllerRefresh()
  EndIf
EndEvent

; ----------------------------
; Sliders - open dialog with proper ranges
; ----------------------------
Event OnOptionSliderOpen(Int a_option)
  If a_option == _optBaseWarmth
    SetSliderDialogStartValue(GetF("weather.cold.baseRequirement"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optRegionPleasant
    SetSliderDialogStartValue(GetF("weather.cold.region.pleasant"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optRegionCloudy
    SetSliderDialogStartValue(GetF("weather.cold.region.cloudy"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optRegionRainy
    SetSliderDialogStartValue(GetF("weather.cold.region.rainy"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optRegionSnowy
    SetSliderDialogStartValue(GetF("weather.cold.region.snowy"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherPleasant
    SetSliderDialogStartValue(GetF("weather.cold.weather.pleasant"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherCloudy
    SetSliderDialogStartValue(GetF("weather.cold.weather.cloudy"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherRainy
    SetSliderDialogStartValue(GetF("weather.cold.weather.rainy"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optWeatherSnowy
    SetSliderDialogStartValue(GetF("weather.cold.weather.snowy"))
    SetSliderDialogRange(0.0, 500.0)
    SetSliderDialogInterval(5.0)

  ElseIf a_option == _optExteriorAdjust
    SetSliderDialogStartValue(GetF("weather.cold.exteriorAdjust"))
    SetSliderDialogRange(-500.0, 500.0)
    SetSliderDialogInterval(10.0)

  ElseIf a_option == _optInteriorAdjust
    SetSliderDialogStartValue(GetF("weather.cold.interiorAdjust"))
    SetSliderDialogRange(-500.0, 500.0)
    SetSliderDialogInterval(10.0)

  ElseIf a_option == _optNightMultiplier
    SetSliderDialogStartValue(GetF("weather.cold.nightMultiplier"))
    SetSliderDialogRange(1.0, 2.0)
    SetSliderDialogInterval(0.05)

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
  Bool refreshNeeded = False

  If a_option == _optBaseWarmth
    SetF("weather.cold.baseRequirement", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optRegionPleasant
    SetF("weather.cold.region.pleasant", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optRegionCloudy
    SetF("weather.cold.region.cloudy", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optRegionRainy
    SetF("weather.cold.region.rainy", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optRegionSnowy
    SetF("weather.cold.region.snowy", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optWeatherPleasant
    SetF("weather.cold.weather.pleasant", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optWeatherCloudy
    SetF("weather.cold.weather.cloudy", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optWeatherRainy
    SetF("weather.cold.weather.rainy", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optWeatherSnowy
    SetF("weather.cold.weather.snowy", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optExteriorAdjust
    SetF("weather.cold.exteriorAdjust", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optInteriorAdjust
    SetF("weather.cold.interiorAdjust", a_value)
    SetSliderOptionValue(a_option, a_value, "{0}")
    RefreshWarmthReadout()
    refreshNeeded = True

  ElseIf a_option == _optNightMultiplier
    SetF("weather.cold.nightMultiplier", a_value)
    SetSliderOptionValue(a_option, a_value, "{2}")
    RefreshWarmthReadout()
    refreshNeeded = True

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

  If refreshNeeded
    RequestControllerRefresh()
  EndIf
EndEvent

Event OnOptionHighlight(Int a_option)
  If ((_optWarmthReadout != 0 && a_option == _optWarmthReadout) || (_optWarmthReq != 0 && a_option == _optWarmthReq))
    RefreshWarmthReadout()
  ElseIf (_optPenaltyReadout != 0 && a_option == _optPenaltyReadout)
    RefreshPenaltyReadout()
  ElseIf ((_optOverviewAreaClimate != 0 && a_option == _optOverviewAreaClimate) || (_optOverviewCurrentWeather != 0 && a_option == _optOverviewCurrentWeather) || (_optOverviewEnvWarmth != 0 && a_option == _optOverviewEnvWarmth) || (_optOverviewPlayerWarmth != 0 && a_option == _optOverviewPlayerWarmth) || (_optOverviewStatus != 0 && a_option == _optOverviewStatus))
    RefreshOverviewReadout()
  EndIf
EndEvent

Event OnConfigClose()
  RefreshWarmthReadout()
  RequestControllerRefresh()
EndEvent

Function UpdateOverviewCache()
  UpdateWarmthCache()

  _overviewAreaClimateDisplay = "--"
  _overviewCurrentWeatherDisplay = "--"

  Int preparednessTier = DeterminePreparednessTierLocal(_lastWarmthValue, _lastSafeRequirementValue)

  SS_Controller controller = None
  If SS_CoreQuest != None
    controller = SS_CoreQuest as SS_Controller
  EndIf

  If controller != None
    Int regionClass = controller.GetLastRegionClass()
    Int weatherClass = controller.GetLastWeatherClass()
    Int cachedTier = controller.GetLastPreparednessTier()
    If regionClass >= 0
      _overviewAreaClimateDisplay = ClassToLabel(regionClass)
    EndIf
    If weatherClass >= 0
      _overviewCurrentWeatherDisplay = ClassToLabel(weatherClass)
    EndIf
    If cachedTier >= 0
      preparednessTier = cachedTier
    EndIf
  EndIf

  _overviewEnvWarmthDisplay = "" + _lastSafeRequirementInt
  _overviewPlayerWarmthDisplay = "" + _lastWarmthInt
  _overviewStatusDisplay = FormatPreparednessStatus(preparednessTier)
EndFunction

Function UpdateWarmthCache()
  Float baseReq = GetF("weather.cold.baseRequirement")
  Float modifiers = 0.0
  Float safeReq = baseReq
  Float warmth = 0.0

  If SS_CoreQuest != None
    SS_Controller controller = SS_CoreQuest as SS_Controller
    If controller != None
      warmth = controller.GetLastWarmth()
      modifiers = controller.GetLastWeatherBonus()
      Float controllerBase = controller.LastBaseRequirement
      if controllerBase > 0.0 || baseReq <= 0.0
        baseReq = controllerBase
      endif
      Float controllerSafe = controller.GetLastSafeRequirement()
      if controllerSafe > 0.0
        safeReq = controllerSafe
      else
        safeReq = baseReq + modifiers
      endif
      if modifiers == 0.0
        modifiers = safeReq - baseReq
      endif
      if safeReq < 0.0
        safeReq = 0.0
      endif
      Int warmthInt = RoundFloat(warmth)
      Int safeInt = RoundFloat(safeReq)
      Int baseInt = RoundFloat(baseReq)
      Int modifierInt = RoundFloat(modifiers)
      _lastWarmthValue = warmth
      _lastSafeRequirementValue = safeReq
      _lastBaseRequirementValue = baseReq
      _lastModifierValue = modifiers
      _lastWarmthInt = warmthInt
      _lastSafeRequirementInt = safeInt
      _lastBaseRequirementInt = baseInt
      _lastModifierInt = modifierInt
      _currentRequirementDisplay = safeInt + " (base " + baseInt + " + modifiers " + modifierInt + ")"
      _currentWarmthDisplay = "Warmth " + warmthInt + " / " + safeInt + " (base " + baseInt + " + modifiers " + modifierInt + ")"
      return
    EndIf
  EndIf

  Float defaultModifiers = safeReq - baseReq
  Int baseOnly = RoundFloat(baseReq)
  Int modifiersOnly = RoundFloat(defaultModifiers)
  Int safeOnly = RoundFloat(safeReq)
  _lastWarmthValue = warmth
  _lastSafeRequirementValue = safeReq
  _lastBaseRequirementValue = baseReq
  _lastModifierValue = defaultModifiers
  _lastWarmthInt = RoundFloat(warmth)
  _lastSafeRequirementInt = safeOnly
  _lastBaseRequirementInt = baseOnly
  _lastModifierInt = modifiersOnly
  _currentRequirementDisplay = safeOnly + " (base " + baseOnly + " + modifiers " + modifiersOnly + ")"
  _currentWarmthDisplay = "Warmth -- / " + safeOnly + " (base " + baseOnly + " + modifiers " + modifiersOnly + ")"
EndFunction

Function RefreshWarmthReadout()
  UpdateWarmthCache()
  If _optWarmthReq != 0
    SetTextOptionValue(_optWarmthReq, _currentRequirementDisplay)
  EndIf
  If _optWarmthReadout != 0
    SetTextOptionValue(_optWarmthReadout, _currentWarmthDisplay)
  EndIf
  RefreshPenaltyReadout()
EndFunction

Function RefreshPenaltyReadout()
  UpdatePenaltyCache()
  If _optPenaltyReadout != 0
    SetTextOptionValue(_optPenaltyReadout, _currentPenaltyDisplay)
  EndIf
EndFunction

Function RefreshOverviewReadout()
  UpdateOverviewCache()
  If _optOverviewAreaClimate != 0
    SetTextOptionValue(_optOverviewAreaClimate, _overviewAreaClimateDisplay)
  EndIf
  If _optOverviewCurrentWeather != 0
    SetTextOptionValue(_optOverviewCurrentWeather, _overviewCurrentWeatherDisplay)
  EndIf
  If _optOverviewEnvWarmth != 0
    SetTextOptionValue(_optOverviewEnvWarmth, _overviewEnvWarmthDisplay)
  EndIf
  If _optOverviewPlayerWarmth != 0
    SetTextOptionValue(_optOverviewPlayerWarmth, _overviewPlayerWarmthDisplay)
  EndIf
  If _optOverviewStatus != 0
    SetTextOptionValue(_optOverviewStatus, _overviewStatusDisplay)
  EndIf
EndFunction

Function UpdatePenaltyCache()
  Int healthPct = 0
  Int staminaPct = 0
  Int magickaPct = 0
  Int speedPct = 0

  If SS_CoreQuest != None
    SS_Controller controller = SS_CoreQuest as SS_Controller
    If controller != None
      healthPct = controller.LastHealthPenalty
      staminaPct = controller.LastStaminaPenalty
      magickaPct = controller.LastMagickaPenalty
      speedPct = controller.LastSpeedPenalty
    EndIf
  EndIf

  String healthStr = FormatPenaltyValue(healthPct)
  String staminaStr = FormatPenaltyValue(staminaPct)
  String magickaStr = FormatPenaltyValue(magickaPct)
  String speedStr = FormatPenaltyValue(speedPct)

  if healthStr == staminaStr && healthStr == magickaStr
    _currentPenaltyDisplay = "Health, Stamina, Magicka: " + healthStr + ", Speed: " + speedStr
  else
    _currentPenaltyDisplay = "Health: " + healthStr + ", Stamina: " + staminaStr + ", Magicka: " + magickaStr + ", Speed: " + speedStr
  endif
EndFunction

String Function FormatPenaltyValue(Int pct)
  if pct <= 0
    return "0%"
  endif
  return "-" + pct + "%"
EndFunction

Int Function RoundFloat(Float value)
  if value >= 0.0
    return (value + 0.5) as Int
  endif
  return (value - 0.5) as Int
EndFunction

Int Function DeterminePreparednessTierLocal(Float warmth, Float safeRequirement)
  if safeRequirement <= 0.0
    return 4
  endif

  if warmth < 0.0
    warmth = 0.0
  endif

  Float ratio = warmth / safeRequirement
  if ratio < 0.25
    return 0
  elseif ratio < 0.50
    return 1
  elseif ratio < 0.75
    return 2
  elseif ratio < 1.0
    return 3
  endif
  return 4
EndFunction

String Function FormatPreparednessStatus(Int tier)
  if tier <= 0
    return "Freezing"
  elseif tier == 1
    return "Cold"
  elseif tier == 2
    return "Breezy"
  elseif tier == 3
    return "Under-dressed"
  endif
  return "Comfortable"
EndFunction

Int Function ClampRange(Int v, Int minV, Int maxV)
  if v < minV
    return minV
  elseif v > maxV
    return maxV
  endif
  return v
EndFunction

String Function ClassToLabel(Int cls)
  Int i = ClampRange(cls, 0, 3)
  if i == 0
    return "Pleasant"
  elseif i == 1
    return "Cloudy"
  elseif i == 2
    return "Rainy"
  endif
  return "Snowing"
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

Function RequestControllerRefresh(String reason = "MCM")
  If SS_CoreQuest != None
    SS_Controller controller = SS_CoreQuest as SS_Controller
    If controller != None
      controller.RequestRefresh(reason)
    EndIf
  EndIf
EndFunction



