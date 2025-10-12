Scriptname SS_WeatherEnvironment extends Quest

Import JsonUtil
Import StringUtil
Import Math

String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto

Spell Property SS_PlayerAbility Auto
SS_WeatherPlayer Property PlayerModule Auto
SS_WeatherTiers Property TierModule Auto

Bool bRunning = False
Bool bRefreshQueued = False
Bool bDebugNotifications = False
Bool bTraceLogs = False
Bool bAdaptiveTick = True

Float kFastTickH    = 0.0167
Float kNormalTickH  = 0.10
Float kSlowTickH    = 0.40
Float kColdDrainFrac = 0.05
Float kColdFloorFrac = 0.20
Float kMinRefreshGapSeconds = 0.0

Float Property LastSafeRequirement Auto
Float Property LastBaseRequirement Auto
Float Property LastWeatherBonus Auto
Float Property LastCoveragePercent Auto
Int   Property LastHealthPenalty Auto
Int   Property LastStaminaPenalty Auto
Int   Property LastMagickaPenalty Auto
Int   Property LastSpeedPenalty Auto
Int   Property LastPreparednessTier Auto

Float lastEvaluateRealTime = 0.0
String queuedSource = ""

Location lastKnownLocation
String   lastLocationName = ""
WorldSpace lastWorldspace
String     lastWorldspaceName = ""
Bool     lastInteriorState = False
Weather  lastWeatherForm
Int      lastRegionBucket = -99
Int      lastWeatherClass = -99

String pendingFastTravelOriginLocation = ""
String pendingFastTravelOriginWorldspace = ""
Bool   pendingFastTravelOriginInterior = False

String lastImmersionToast = ""
String lastTierToast = ""
String lastEnvSnapshot = ""

Bool Property DebugEnabled Hidden
  Bool Function Get()
    return bTraceLogs
  EndFunction
EndProperty

Event OnInit()
  InitConfigDefaults()
  ApplyDebugFlags()
  EnsurePlayerHasAbility()
  if PlayerModule != None
    PlayerModule.ApplyConfigDefaults()
  endif
  bRunning = True
  RegisterForModEvent("SS_QuickTick", "OnQuickTick")
  QueueInitialEvaluate("Init")
EndEvent

Event OnPlayerLoadGame()
  InitConfigDefaults()
  ApplyDebugFlags()
  EnsurePlayerHasAbility()
  if PlayerModule != None
    PlayerModule.ApplyConfigDefaults()
  endif
  bRunning = True
  QueueInitialEvaluate("OnPlayerLoadGame")
EndEvent

Function ConfigureModule(Spell ability)
  if ability != None
    SS_PlayerAbility = ability
  endif
  ApplyDebugFlags()
  EnsurePlayerHasAbility()
  if PlayerModule != None
    PlayerModule.ApplyConfigDefaults()
  endif
EndFunction

Function RequestFastTick(String source = "RequestFastTick")
  RequestEvaluate(source)
EndFunction

Function RequestEvaluate(String source, Bool forceImmediate = False)
  if source == ""
    source = "RequestFastTick"
  endif

  if forceImmediate
    if bRefreshQueued
      bRefreshQueued = False
      queuedSource = ""
    endif
    EvaluateEnvironment(source)
    return
  endif

  Float now = Utility.GetCurrentRealTime()
  Float minGap = GetMinRefreshGapSeconds()
  Float elapsed = now - lastEvaluateRealTime

  if elapsed >= minGap || elapsed < 0.0
    if bRefreshQueued
      bRefreshQueued = False
      queuedSource = ""
    endif
    EvaluateEnvironment(source)
    return
  endif

  if queuedSource != ""
    if !SourceIncludes(queuedSource, source)
      queuedSource = queuedSource + "|" + source
    endif
  else
    queuedSource = source
  endif

  if !bRefreshQueued
    bRefreshQueued = True
    Float delay = minGap - elapsed
    if delay < 0.05
      delay = 0.05
    endif
    RegisterForSingleUpdate(delay)
  endif
EndFunction

Function QueueInitialEvaluate(String source)
  if source == ""
    source = "Startup"
  endif

  if queuedSource != ""
    if !SourceIncludes(queuedSource, source)
      queuedSource = queuedSource + "|" + source
    endif
  else
    queuedSource = source
  endif

  bRefreshQueued = True
  RegisterForSingleUpdate(0.5)
EndFunction

Event OnUpdate()
  if !bRefreshQueued
    return
  endif

  bRefreshQueued = False
  String source = queuedSource
  queuedSource = ""

  if source == ""
    source = "Queued"
  endif

  EvaluateEnvironment(source)
EndEvent

Event OnQuickTick(String speedStr, Float regenMult)
  if DebugEnabled
    Debug.Trace("[SS] QuickTick request received -> evaluate")
  endif
  RequestEvaluate("QuickTick", True)
EndEvent

Function RecordFastTravelOrigin()
  pendingFastTravelOriginLocation = lastLocationName
  pendingFastTravelOriginWorldspace = lastWorldspaceName
  pendingFastTravelOriginInterior = lastInteriorState
EndFunction

Function EvaluateEnvironment(String source = "Tick")
  if !bRunning
    return
  endif

  Actor p = Game.GetPlayer()
  if p == None
    LastSafeRequirement = 0.0
    LastBaseRequirement = 0.0
    LastWeatherBonus = 0.0
    LastCoveragePercent = 100.0
    LastPreparednessTier = 0
    LastHealthPenalty = 0
    LastStaminaPenalty = 0
    LastMagickaPenalty = 0
    LastSpeedPenalty = 0
    SendEnvChangedEvent(0.0, source)
    lastEvaluateRealTime = Utility.GetCurrentRealTime()
    return
  endif

  Location oldLocation = lastKnownLocation
  String oldLocationName = lastLocationName
  String oldWorldspaceName = lastWorldspaceName
  Bool oldInterior = lastInteriorState
  Weather previousWeather = lastWeatherForm

  Location currentLocation = p.GetCurrentLocation()
  WorldSpace currentWorldspace = p.GetWorldSpace()
  Bool isInterior = p.IsInInterior()
  String newLocationName = ResolveLocationName(currentLocation)
  String newWorldspaceName = ResolveWorldspaceName(currentWorldspace)
  Weather currentWeather = Weather.GetCurrentWeather()

  Bool coldOn    = GetB("weather.cold.enable", True)
  Bool useTierSystem = GetB("penalties.useTierSystem", True)

  Float previousRequirement = LastSafeRequirement
  Float baseRequirement = ReadBaseRequirement()
  Int regionClass = GetRegionClassification()
  Int weatherClass = GetWeatherClassification()
  Float safeRequirement = ComputeWarmthRequirement(p, baseRequirement, regionClass, weatherClass)
  Float modifierSum = safeRequirement - baseRequirement

  LastBaseRequirement = baseRequirement
  LastSafeRequirement = safeRequirement
  LastWeatherBonus = modifierSum

  Float playerWarmth = 0.0
  if PlayerModule != None
    playerWarmth = PlayerModule.RefreshPlayerWarmth(source)
  endif

  Float coveragePercent = 100.0
  Int preparednessTier = 0
  if TierModule != None
    preparednessTier = TierModule.ComputeTier(playerWarmth, safeRequirement, source)
    coveragePercent = TierModule.GetCoveragePercent()
  else
    coveragePercent = ComputeCoveragePercent(playerWarmth, safeRequirement)
    preparednessTier = DetermineCoverageTier(coveragePercent)
  endif

  LastCoveragePercent = coveragePercent
  LastPreparednessTier = preparednessTier

  Float deficit = 0.0
  if playerWarmth < safeRequirement
    deficit = safeRequirement - playerWarmth
  endif

  Float penaltyDenom = safeRequirement
  if penaltyDenom <= 0.0
    penaltyDenom = baseRequirement
  endif
  if penaltyDenom <= 0.0
    penaltyDenom = 1.0
  endif

  Int healthPenaltyPct  = ComputePenaltyPercent(deficit, penaltyDenom, 80)
  Int staminaPenaltyPct = ComputePenaltyPercent(deficit, penaltyDenom, 80)
  Int magickaPenaltyPct = ComputePenaltyPercent(deficit, penaltyDenom, 80)
  Int speedPenaltyPct   = ComputePenaltyPercent(deficit, penaltyDenom, 50)

  LastHealthPenalty  = healthPenaltyPct
  LastStaminaPenalty = staminaPenaltyPct
  LastMagickaPenalty = magickaPenaltyPct
  LastSpeedPenalty   = speedPenaltyPct

  if coldOn
    ApplyColdPenalties(preparednessTier, useTierSystem, healthPenaltyPct, staminaPenaltyPct, magickaPenaltyPct, speedPenaltyPct)
  else
    ClearColdPenalties(useTierSystem)
  endif

  Bool sourceIsFastTravel = SourceIncludes(source, "FastTravelEnd")
  Bool locationChanged = (newLocationName != oldLocationName) || (newWorldspaceName != oldWorldspaceName)
  Bool interiorChanged = isInterior != oldInterior
  Bool exitedToExterior = interiorChanged && !isInterior
  Bool forecastChanged = (regionClass != lastRegionBucket)
  Bool weatherChanged = (currentWeather != lastWeatherForm) || (weatherClass != lastWeatherClass)

  HandleImmersionToasts(source, preparednessTier, preparednessTier != lastPreparednessTier, forecastChanged, weatherChanged, locationChanged, exitedToExterior, isInterior, currentWeather, regionClass)

  if sourceIsFastTravel
    pendingFastTravelOriginLocation = ""
    pendingFastTravelOriginWorldspace = ""
    pendingFastTravelOriginInterior = False
  endif

  lastKnownLocation = currentLocation
  lastLocationName = newLocationName
  lastWorldspace = currentWorldspace
  lastWorldspaceName = newWorldspaceName
  lastInteriorState = isInterior
  lastPreparednessTier = preparednessTier
  lastRegionBucket = regionClass
  lastWeatherClass = weatherClass
  lastWeatherForm = currentWeather

  lastEnvSnapshot = BuildEnvSnapshot(safeRequirement, regionClass, weatherClass, isInterior, newLocationName, newWorldspaceName)
  SendEnvChangedEvent(safeRequirement, source, previousRequirement)

  lastEvaluateRealTime = Utility.GetCurrentRealTime()
EndFunction

Function ApplyColdPenalties(Int preparednessTier, Bool useTierSystem, Int healthPenaltyPct, Int staminaPenaltyPct, Int magickaPenaltyPct, Int speedPenaltyPct)
  int h = ModEvent.Create("SS_SetCold")
  if h
    ModEvent.PushInt(h, healthPenaltyPct)
    ModEvent.PushInt(h, staminaPenaltyPct)
    ModEvent.PushInt(h, magickaPenaltyPct)
    ModEvent.PushInt(h, speedPenaltyPct)
    Int tierPayload = preparednessTier
    if !useTierSystem
      tierPayload = -1
    endif
    ModEvent.PushInt(h, tierPayload)
    ModEvent.Send(h)

    if bDebugNotifications
      String debugMsg = "[SS] req=" + LastBaseRequirement + " + modifiers=" + LastWeatherBonus + " => " + LastSafeRequirement
      debugMsg = debugMsg + " | hpPen=" + healthPenaltyPct + "% spdPen=" + speedPenaltyPct + "%"
      if DebugEnabled
        Debug.Trace(debugMsg)
      else
        Debug.Notification(debugMsg)
      endif
    endif

    if DebugEnabled
      String traceMsg = "[SS] Sent SS_SetCold | hp=" + healthPenaltyPct + "% st=" + staminaPenaltyPct + "% mg=" + magickaPenaltyPct + "% speed=" + speedPenaltyPct + "%"
      if tierPayload != -1
        traceMsg = traceMsg + " tier=" + tierPayload
      endif
      Debug.Trace(traceMsg)
    endif
  endif
EndFunction

Function ClearColdPenalties(Bool useTierSystem)
  if !useTierSystem
    int h2 = ModEvent.Create("SS_ClearCold")
    if h2
      ModEvent.Send(h2)
      if bDebugNotifications
        Debug.Notification("[SS] cold OFF -> clear penalties")
      endif
      if DebugEnabled
        Debug.Trace("[SS] Sent SS_ClearCold")
      endif
    endif
  endif
  LastHealthPenalty  = 0
  LastStaminaPenalty = 0
  LastMagickaPenalty = 0
  LastSpeedPenalty   = 0
EndFunction

Function HandleImmersionToasts(String source, Int preparednessTier, Bool preparednessTierChanged, Bool forecastChanged, Bool weatherChanged, Bool locationChanged, Bool exitedToExterior, Bool isInterior, Weather currentWeather, Int regionClass)
  Bool immersionToastsEnabled = IsImmersionToastsEnabled()
  if !immersionToastsEnabled
    return
  endif

  Bool sourceIsFastTravel = SourceIncludes(source, "FastTravelEnd")
  Bool isTriggerSource = True
  if source == ""
    isTriggerSource = False
  elseif SourceIncludes(source, "Tick")
    isTriggerSource = False
  endif

  if !isTriggerSource
    if forecastChanged || weatherChanged || locationChanged || exitedToExterior || sourceIsFastTravel
      isTriggerSource = True
    endif
  endif

  if isTriggerSource && !isInterior
    String forecastMessage = GetForecastToastMessage(regionClass)
    String weatherMessage = GetCurrentWeatherToastMessage(currentWeather)
    String combinedMessage = ""

    if forecastMessage != ""
      combinedMessage = forecastMessage
    endif

    if weatherMessage != ""
      if combinedMessage != ""
        combinedMessage = combinedMessage + " " + weatherMessage
      else
        combinedMessage = weatherMessage
      endif
    endif

    if combinedMessage != "" && combinedMessage != lastImmersionToast
      DispatchToast("", combinedMessage, "Immersion")
      lastImmersionToast = combinedMessage
    endif
  endif

  if preparednessTierChanged
    String tierToastMessage = GetPreparednessToastMessage(preparednessTier)
    if tierToastMessage != ""
      DispatchToast("", tierToastMessage, "Immersion")
    endif
    lastTierToast = tierToastMessage
  endif
EndFunction

Float Function ComputeWarmthRequirement(Actor p, Float baseRequirement, Int regionClass, Int weatherClass)
  Float requirement = baseRequirement
  requirement += GetRegionContribution(regionClass)
  requirement += GetWeatherContribution(weatherClass)

  Float exteriorAdjust = GetF("weather.cold.exteriorAdjust", 0.0)
  Float interiorAdjust = GetF("weather.cold.interiorAdjust", 0.0)

  if p != None && p.IsInInterior()
    requirement += interiorAdjust
  else
    requirement += exteriorAdjust
  endif

  if requirement < 0.0
    requirement = 0.0
  endif

  if IsNightTime()
    Float nightMult = GetNightMultiplier()
    requirement *= nightMult
  endif

  return requirement
EndFunction

Float Function GetEnvironmentalWarmth()
  return LastSafeRequirement
EndFunction

String Function GetLastEnvSnapshot()
  return lastEnvSnapshot
EndFunction

Float Function GetLastSafeRequirement()
  return LastSafeRequirement
EndFunction

Float Function GetLastWeatherBonus()
  return LastWeatherBonus
EndFunction

Float Function GetLastWarmth()
  if PlayerModule != None
    return PlayerModule.GetPlayerWarmth()
  endif
  return 0.0
EndFunction

Int Function GetLastPreparednessTier()
  return LastPreparednessTier
EndFunction

Function ApplyDebugFlags()
  bDebugNotifications = GetB("debug.enable", False)
  bTraceLogs          = GetB("debug.trace", False)
  if DebugEnabled
    Debug.Trace("[SS] Environment init: debug=" + bDebugNotifications + " trace=1")
  endif
EndFunction

Function EnsurePlayerHasAbility()
  if SS_PlayerAbility == None
    return
  endif

  Actor playerRef = Game.GetPlayer()
  if playerRef == None
    return
  endif

  if !playerRef.HasSpell(SS_PlayerAbility)
    playerRef.AddSpell(SS_PlayerAbility, False)
  endif
EndFunction

Int Function GetRegionClassification()
  Int idx = 3
  while idx >= 0
    Weather candidate = Weather.FindWeather(idx)
    if candidate != None
      return idx
    endif
    idx -= 1
  endwhile

  return -1
EndFunction

Int Function GetWeatherClassification()
  Weather current = Weather.GetCurrentWeather()
  if current != None
    return current.GetClassification()
  endif
  return -1
EndFunction

Float Function GetRegionContribution(Int classification)
  if classification == 0
    return GetF("weather.cold.region.pleasant", 0.0)
  elseif classification == 1
    return GetF("weather.cold.region.cloudy", 0.0)
  elseif classification == 2
    return GetF("weather.cold.region.rainy", 0.0)
  elseif classification == 3
    return GetF("weather.cold.region.snowy", 0.0)
  endif
  return 0.0
EndFunction

Float Function GetWeatherContribution(Int classification)
  if classification == 0
    return GetF("weather.cold.weather.pleasant", 0.0)
  elseif classification == 1
    return GetF("weather.cold.weather.cloudy", 0.0)
  elseif classification == 2
    return GetF("weather.cold.weather.rainy", 0.0)
  elseif classification == 3
    return GetF("weather.cold.weather.snowy", 0.0)
  endif
  return 0.0
EndFunction

Float Function ComputeCoveragePercent(Float playerWarmth, Float environmentRequirement)
  Float coverage = 100.0

  Float requirement = environmentRequirement
  if requirement < 0.0
    requirement = 0.0
  endif

  if requirement > 0.001
    coverage = 0.0
    if playerWarmth > 0.0
      coverage = (playerWarmth / requirement) * 100.0
    endif
  endif

  if coverage < 0.0
    coverage = 0.0
  elseif coverage > 100.0
    coverage = 100.0
  endif

  return coverage
EndFunction

Int Function DetermineCoverageTier(Float coveragePercent)
  Float normalized = coveragePercent
  if normalized < 0.0
    normalized = 0.0
  elseif normalized > 100.0
    normalized = 100.0
  endif

  if normalized >= 100.0
    return 0
  elseif normalized >= 75.0
    return 1
  elseif normalized >= 50.0
    return 2
  elseif normalized >= 25.0
    return 3
  elseif normalized >= 1.0
    return 4
  endif
  return 5
EndFunction

Int Function ComputePenaltyPercent(Float deficit, Float safeRequirement, Int maxPenalty)
  if deficit <= 0.0
    return 0
  endif

  if safeRequirement <= 0.0
    return 0
  endif

  Float ratio = deficit / safeRequirement
  if ratio > 1.0
    ratio = 1.0
  elseif ratio < 0.0
    ratio = 0.0
  endif

  Float scaled = ratio * (maxPenalty as Float)
  Int penalty = RoundFloatToInt(scaled)
  if penalty > maxPenalty
    penalty = maxPenalty
  endif
  if penalty < 5
    penalty = 0
  endif
  if penalty < 0
    penalty = 0
  endif
  return penalty
EndFunction

Int Function RoundFloatToInt(Float value)
  if value >= 0.0
    return (value + 0.5) as Int
  endif
  return (value - 0.5) as Int
EndFunction

Float Function GetNightMultiplier()
  Float mult = GetF("weather.cold.nightMultiplier", 1.0)
  if mult < 1.0
    mult = 1.0
  endif
  return mult
EndFunction

Bool Function IsNightTime()
  Float currentTime = Utility.GetCurrentGameTime()
  Float fractional = currentTime - Math.Floor(currentTime)
  Float hour = fractional * 24.0
  if hour < 6.0
    return True
  endif
  if hour >= 20.0
    return True
  endif
  return False
EndFunction

Float Function ReadBaseRequirement()
  Float sentinel = -12345.0
  Float baseRequirement = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.baseRequirement", sentinel)
  if baseRequirement == sentinel
    baseRequirement = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.safeThreshold", 0.0)
  endif
  return baseRequirement
EndFunction

Bool Function SourceIncludes(String sources, String token)
  if sources == "" || token == ""
    return False
  endif
  return StringUtil.Find(sources, token) >= 0
EndFunction

Bool Function IsImmersionToastsEnabled()
  return GetB("ui.toasts.immersion", True)
EndFunction

String Function ResolveLocationName(Location loc)
  if loc != None
    String name = loc.GetName()
    if name != ""
      return name
    endif
  endif
  return ""
EndFunction

String Function ResolveWorldspaceName(WorldSpace ws)
  if ws != None
    String name = ws.GetName()
    if name != ""
      return name
    endif
  endif
  return ""
EndFunction

String Function FormatLocationLabel(String locationName, String worldspaceName)
  if locationName != ""
    return locationName
  endif
  if worldspaceName != ""
    return worldspaceName
  endif
  return "Unknown"
EndFunction

String Function FormatInteriorState(Bool isInterior)
  if isInterior
    return "Interior"
  endif
  return "Exterior"
EndFunction

String Function FormatWeatherName(Weather weatherForm)
  if weatherForm == None
    return "Unknown"
  endif
  String label = weatherForm.GetName()
  if label == ""
    Int formId = weatherForm.GetFormID()
    label = "Weather FormID " + formId
  endif
  if label == ""
    label = "Unknown"
  endif
  return label
EndFunction

String Function GetPreparednessToastMessage(Int tier)
  if tier >= 5
    return "I am freezing!"
  elseif tier == 4
    return "I am cold!"
  elseif tier == 3
    return "I feel the breeze."
  elseif tier == 2
    return "I am a bit under-dressed."
  elseif tier == 1
    return "I should add another layer."
  endif
  return "I am comfortable."
EndFunction

String Function GetForecastToastMessage(Int classification)
  if classification == 0
    return "Normally here the weather is pleasant."
  elseif classification == 1
    return "In this area, it's usual to see clouds in the sky."
  elseif classification == 2
    return "It's a very wet area, rains are common here."
  elseif classification == 3
    return "This area is normally covered in snow."
  endif
  return "The local climate is uncertain."
EndFunction

String Function GetCurrentWeatherToastMessage(Weather weatherForm)
  if weatherForm == None
    return "The weather is hard to read right now."
  endif
  Int skyClass = weatherForm.GetClassification()
  if skyClass == 0
    return "The skies are clear."
  elseif skyClass == 1
    return "Clouds are covering the sky."
  elseif skyClass == 2
    return "Rain is pouring from above!"
  elseif skyClass == 3
    return "It's snowing, I better be ready."
  endif
  return "The weather is shifting."
EndFunction

Function DispatchToast(String label, String detail, String category)
  if Utility.IsInMenuMode()
    return
  endif

  String toastMessage = ""
  if label != ""
    toastMessage = label
  endif

  if detail != ""
    if toastMessage != ""
      toastMessage = toastMessage + " " + detail
    else
      toastMessage = detail
    endif
  endif

  if toastMessage == ""
    return
  endif

  int toastEvent = ModEvent.Create("SS_Toast")
  if toastEvent
    ModEvent.PushString(toastEvent, toastMessage)
    ModEvent.PushString(toastEvent, category)
    ModEvent.Send(toastEvent)
  endif
EndFunction

String Function BuildEnvSnapshot(Float envWarmth, Int regionClass, Int weatherClass, Bool isInterior, String locationName, String worldspaceName)
  String snapshot = "EnvWarmth=" + envWarmth
  snapshot = snapshot + " regionClass=" + regionClass
  snapshot = snapshot + " weatherClass=" + weatherClass
  snapshot = snapshot + " interior=" + FormatInteriorState(isInterior)
  snapshot = snapshot + " location=" + FormatLocationLabel(locationName, worldspaceName)
  return snapshot
EndFunction

Function SendEnvChangedEvent(Float envWarmth, String source, Float previous)
  Bool force = SourceIncludes(source, "Force")
  Bool isFirst = (lastEvaluateRealTime <= 0.0)

  if !isFirst && !force
    if Math.Abs(envWarmth - previous) <= 0.1
      return
    endif
  endif

  int evt = ModEvent.Create("SS_Evt_EnvChanged")
  if evt
    ModEvent.PushFloat(evt, envWarmth)
    ModEvent.PushString(evt, source)
    ModEvent.Send(evt)
  endif
EndFunction

Float Function GetMinRefreshGapSeconds()
  Float configured = GetF("weather.cold.minRefreshGapSeconds", kMinRefreshGapSeconds)
  if configured < 0.0
    return 0.0
  endif
  return configured
EndFunction

Bool Function GetB(String path, Bool fallback = True)
  Int sentinel = -12345
  Int asInt = JsonUtil.GetPathIntValue(CFG_PATH, path, sentinel)
  if asInt != sentinel
    return asInt > 0
  endif
  return JsonUtil.GetPathBoolValue(CFG_PATH, path, fallback)
EndFunction

Float Function GetF(String path, Float fallback = 0.0)
  return JsonUtil.GetPathFloatValue(CFG_PATH, path, fallback)
EndFunction

Int Function GetI(String path, Int fallback = 0)
  return JsonUtil.GetPathIntValue(CFG_PATH, path, fallback)
EndFunction

Function InitConfigDefaults()
  Float f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.safeThreshold", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.safeThreshold", 0.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.autoWarmthPerPiece", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.autoWarmthPerPiece", 100.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.torchWarmthBonus", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.torchWarmthBonus", 30.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.baseRequirement", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.baseRequirement", 200.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.region.pleasant", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.region.pleasant", 0.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.region.cloudy", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.region.cloudy", 30.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.region.rainy", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.region.rainy", 60.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.region.snowy", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.region.snowy", 120.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.weather.pleasant", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.weather.pleasant", 0.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.weather.cloudy", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.weather.cloudy", 25.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.weather.rainy", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.weather.rainy", 75.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.weather.snowy", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.weather.snowy", 125.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.exteriorAdjust", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.exteriorAdjust", 50.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.interiorAdjust", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.interiorAdjust", -50.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.swimWarmthMalus", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.swimWarmthMalus", 0.0)
  endif

  Float obsoleteSwimMultiplier = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.swimWarmthMultiplier", -9999.0)
  if obsoleteSwimMultiplier != -9999.0
    JsonUtil.ClearPath(CFG_PATH, "weather.cold.swimWarmthMultiplier")
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.nightMultiplier", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.nightMultiplier", 1.25)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.minRefreshGapSeconds", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.minRefreshGapSeconds", kMinRefreshGapSeconds)
  endif

  Int i = JsonUtil.GetPathIntValue(CFG_PATH, "weather.cold.enable", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "weather.cold.enable", 1)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.tick", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.tick", 0.0)
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.useTierSystem", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.useTierSystem", 1)
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier4.bonusMaxPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier4.bonusMaxPct", 10)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier4.bonusRegenPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier4.bonusRegenPct", 10)
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier3.speedPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier3.speedPct", 0)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier3.regenStop", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier3.regenStop", 0)
  endif
  f = JsonUtil.GetPathFloatValue(CFG_PATH, "penalties.tier3.damagePerSec", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "penalties.tier3.damagePerSec", 0.0)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier3.floorPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier3.floorPct", 100)
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier2.speedPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier2.speedPct", 0)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier2.regenStop", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier2.regenStop", 0)
  endif
  f = JsonUtil.GetPathFloatValue(CFG_PATH, "penalties.tier2.damagePerSec", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "penalties.tier2.damagePerSec", 5.0)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier2.floorPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier2.floorPct", 90)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier2.maxLossPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier2.maxLossPct", 10)
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier1.speedPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier1.speedPct", -10)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier1.regenStop", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier1.regenStop", 0)
  endif
  f = JsonUtil.GetPathFloatValue(CFG_PATH, "penalties.tier1.damagePerSec", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "penalties.tier1.damagePerSec", 10.0)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier1.floorPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier1.floorPct", 75)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier1.maxLossPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier1.maxLossPct", 25)
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier0.speedPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier0.speedPct", -25)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier0.regenStop", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier0.regenStop", 1)
  endif
  f = JsonUtil.GetPathFloatValue(CFG_PATH, "penalties.tier0.damagePerSec", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "penalties.tier0.damagePerSec", 15.0)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier0.floorPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier0.floorPct", 50)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.tier0.maxLossPct", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "penalties.tier0.maxLossPct", 50)
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "debug.enable", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "debug.enable", 0)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "debug.trace", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "debug.trace", 0)
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "ui.toasts.debug", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "ui.toasts.debug", 0)
  endif
  i = JsonUtil.GetPathIntValue(CFG_PATH, "ui.toasts.immersion", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "ui.toasts.immersion", 1)
  endif

  JsonUtil.Save(CFG_PATH)
EndFunction

Function NotifyConfigChanged()
  if PlayerModule != None
    PlayerModule.InvalidateNameBonusCache()
  endif
EndFunction

Int Function GetLastRegionClass()
  return lastRegionBucket
EndFunction

Int Function GetLastWeatherClass()
  return lastWeatherClass
EndFunction

Bool Function GetLastInteriorState()
  return lastInteriorState
EndFunction

