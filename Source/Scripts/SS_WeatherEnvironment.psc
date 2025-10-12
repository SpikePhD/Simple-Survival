Scriptname SS_WeatherEnvironment extends Quest

Import JsonUtil
Import StringUtil
Import Math

String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto

Spell Property SS_PlayerAbility Auto

Bool bRunning = False
Bool bRefreshQueued = False
Bool bTraceLogs = False

Float kMinRefreshGapSeconds = 0.0

Float Property LastSafeRequirement Auto
Float Property LastBaseRequirement Auto
Float Property LastWeatherBonus Auto

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
  bRunning = True
  RegisterForModEvent("SS_QuickTick", "OnQuickTick")
  QueueInitialEvaluate("Init")
EndEvent

Event OnPlayerLoadGame()
  InitConfigDefaults()
  ApplyDebugFlags()
  EnsurePlayerHasAbility()
  bRunning = True
  QueueInitialEvaluate("OnPlayerLoadGame")
EndEvent

Function ConfigureModule(Spell ability)
  if ability != None
    SS_PlayerAbility = ability
  endif
  ApplyDebugFlags()
  EnsurePlayerHasAbility()
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
    SendEnvChangedEvent(0.0, source)
    lastEvaluateRealTime = Utility.GetCurrentRealTime()
    return
  endif

  Location currentLocation = p.GetCurrentLocation()
  WorldSpace currentWorldspace = p.GetWorldSpace()
  Bool isInterior = p.IsInInterior()
  String newLocationName = ResolveLocationName(currentLocation)
  String newWorldspaceName = ResolveWorldspaceName(currentWorldspace)
  Weather currentWeather = Weather.GetCurrentWeather()

  Float previousRequirement = LastSafeRequirement
  Float baseRequirement = ReadBaseRequirement()
  Int regionClass = GetRegionClassification()
  Int weatherClass = GetWeatherClassification()
  Float safeRequirement = ComputeWarmthRequirement(p, baseRequirement, regionClass, weatherClass)
  Float modifierSum = safeRequirement - baseRequirement

  LastBaseRequirement = baseRequirement
  LastSafeRequirement = safeRequirement
  LastWeatherBonus = modifierSum

  if SourceIncludes(source, "FastTravelEnd")
    pendingFastTravelOriginLocation = ""
    pendingFastTravelOriginWorldspace = ""
    pendingFastTravelOriginInterior = False
  endif

  lastKnownLocation = currentLocation
  lastLocationName = newLocationName
  lastWorldspace = currentWorldspace
  lastWorldspaceName = newWorldspaceName
  lastInteriorState = isInterior
  lastRegionBucket = regionClass
  lastWeatherClass = weatherClass
  lastWeatherForm = currentWeather

  lastEnvSnapshot = BuildEnvSnapshot(safeRequirement, regionClass, weatherClass, isInterior, newLocationName, newWorldspaceName)
  SendEnvChangedEvent(safeRequirement, source, previousRequirement)

  lastEvaluateRealTime = Utility.GetCurrentRealTime()
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

Function ApplyDebugFlags()
  Bool debugNotifications = GetB("debug.enable", False)
  bTraceLogs = GetB("debug.trace", False)
  if DebugEnabled
    Debug.Trace("[SS] Environment init: debug=" + debugNotifications + " trace=1")
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

Int Function GetLastRegionClass()
  return lastRegionBucket
EndFunction

Int Function GetLastWeatherClass()
  return lastWeatherClass
EndFunction

Bool Function GetLastInteriorState()
  return lastInteriorState
EndFunction

