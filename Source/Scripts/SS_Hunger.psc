Scriptname SS_Hunger extends Quest

Import JsonUtil
Import StorageUtil

String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto
String Property HungerKeyLastValue = "SS.Hunger.lastValue" Auto
String Property HungerKeyLastHit100 = "SS.Hunger.lastHit100GameTime" Auto
String Property HungerKeyLastDecayCheck = "SS.Hunger.lastDecayCheckGameTime" Auto
String Property HungerKeyLastTier = "SS.Hunger.lastHungerTier" Auto
String Property lastTierToast_Hunger Auto

Bool bInitialized = False
Bool HungerEnabled = True
Int HungerMaxValue = 100
Int HungerStartValue = 100
Float HungerFedBufferHours = 4.0
Float HungerDecayPerHour = 5.0
Float HungerSleepDecayPerHour = 2.5
Int HungerTier4Min = 75
Int HungerTier3Min = 50
Int HungerTier2Min = 25
Int HungerTier1Min = 10

Int lastHungerValue = 0
Float lastHit100GameTime = 0.0
Float lastDecayCheckGameTime = 0.0
Int lastHungerTier = 0
Bool isSleepingState = False
Bool hourlyUpdateArmed = False
Bool suppressHungerTierToasts = False

Event OnInit()
  InitializeModule()
EndEvent

Event OnPlayerLoadGame()
  InitializeModule()
EndEvent

Function InitializeModule()
  InitHungerConfigDefaults()
  LoadHungerConfig()
  LoadHungerState()
  bInitialized = True
  RefreshGameTimeUpdateRegistration()
EndFunction

Function UpdateFromGameTime(Bool isSleepingOverride = False)
  EnsureInitialized()

  if !HungerEnabled
    lastDecayCheckGameTime = Utility.GetCurrentGameTime()
    SaveHungerState()
    UnregisterForUpdateGameTime()
    hourlyUpdateArmed = False
    return
  endif

  Float nowTime = Utility.GetCurrentGameTime()
  if lastDecayCheckGameTime <= 0.0
    lastDecayCheckGameTime = nowTime
    SaveHungerState()
    return
  endif

  Float deltaDays = nowTime - lastDecayCheckGameTime
  if deltaDays <= 0.0
    lastDecayCheckGameTime = nowTime
    SaveHungerState()
    return
  endif

  Float hoursElapsed = deltaDays * 24.0
  Bool sleepingState = ResolveSleepingState(isSleepingOverride)
  ApplyHungerDecay(hoursElapsed, sleepingState, nowTime)
  lastDecayCheckGameTime = nowTime
  SaveHungerState()
EndFunction

Function EnsureInitialized()
  if !bInitialized
    InitializeModule()
  endif
EndFunction

Function ApplyHungerDecay(Float hoursElapsed, Bool isSleeping, Float currentGameTime)
  if hoursElapsed <= 0.0
    return
  endif

  Float decayRate = HungerDecayPerHour
  if isSleeping
    decayRate = HungerSleepDecayPerHour
  endif

  if decayRate <= 0.0
    return
  endif

  Float effectiveHours = hoursElapsed
  if lastHungerValue >= HungerMaxValue && HungerFedBufferHours > 0.0
    Float hoursSinceHit100 = 0.0
    if lastHit100GameTime > 0.0
      hoursSinceHit100 = (currentGameTime - lastHit100GameTime) * 24.0
    endif
    Float remainingBuffer = HungerFedBufferHours - hoursSinceHit100
    if remainingBuffer > 0.0
      if remainingBuffer > effectiveHours
        remainingBuffer = effectiveHours
      endif
      effectiveHours -= remainingBuffer
    endif
  endif

  if effectiveHours <= 0.0
    return
  endif

  Float newValue = lastHungerValue * 1.0 - (decayRate * effectiveHours)
  SetHungerValue(newValue, currentGameTime)
EndFunction

Function SetHungerValue(Float newValue, Float currentGameTime = -1.0)
  Float maxValue = HungerMaxValue * 1.0
  if maxValue <= 0.0
    maxValue = 100.0
  endif

  if newValue < 0.0
    newValue = 0.0
  elseif newValue > maxValue
    newValue = maxValue
  endif

  Int newIntValue = newValue as Int
  if newIntValue < 0
    newIntValue = 0
  elseif newIntValue > HungerMaxValue
    newIntValue = HungerMaxValue
  endif

  lastHungerValue = newIntValue
  if newIntValue >= HungerMaxValue
    if currentGameTime <= 0.0
      currentGameTime = Utility.GetCurrentGameTime()
    endif
    lastHit100GameTime = currentGameTime
  endif

  Int previousTier = lastHungerTier
  Int resolvedTier = DetermineHungerTier(lastHungerValue)

  if resolvedTier != previousTier
    HandleHungerTierChanged(resolvedTier, previousTier)
  endif

  lastHungerTier = resolvedTier
EndFunction

Event OnUpdateGameTime()
  hourlyUpdateArmed = False
  UpdateFromGameTime()
  RefreshGameTimeUpdateRegistration()
EndEvent

Event OnSleepStart(Float afSleepStartTime, Float afDesiredWakeTime)
  isSleepingState = True
EndEvent

Event OnSleepStop(Bool abInterrupted)
  isSleepingState = False
EndEvent

Function RefreshGameTimeUpdateRegistration()
  if HungerEnabled
    if !hourlyUpdateArmed
      RegisterForSingleUpdateGameTime(1.0)
      hourlyUpdateArmed = True
    endif
  else
    UnregisterForUpdateGameTime()
    hourlyUpdateArmed = False
  endif
EndFunction

Bool Function ResolveSleepingState(Bool overrideState = False)
  if overrideState
    return True
  endif

  if isSleepingState
    return True
  endif

  Actor player = Game.GetPlayer()
  if player != None
    return player.IsSleeping()
  endif

  return False
EndFunction

Int Function DetermineHungerTier(Int hungerValue)
  Float maxValue = HungerMaxValue * 1.0
  if maxValue <= 0.0
    maxValue = 100.0
  endif

  Float normalized = 0.0
  if hungerValue > 0
    normalized = (hungerValue as Float) / maxValue * 100.0
  endif

  if normalized < 0.0
    normalized = 0.0
  elseif normalized > 100.0
    normalized = 100.0
  endif

  if normalized >= HungerTier4Min
    return 4
  elseif normalized >= HungerTier3Min
    return 3
  elseif normalized >= HungerTier2Min
    return 2
  elseif normalized >= HungerTier1Min
    return 1
  endif
  return 0
EndFunction

Function HandleHungerTierChanged(Int newTier, Int previousTier)
  if suppressHungerTierToasts
    return
  endif

  if !HungerEnabled
    return
  endif

  if !IsImmersionToastsEnabled()
    return
  endif

  String toastMessage = GetHungerTierToastMessage(newTier)

  if toastMessage == ""
    if previousTier != newTier
      lastTierToast_Hunger = ""
    endif
    return
  endif

  if toastMessage == lastTierToast_Hunger
    return
  endif

  DispatchHungerImmersionToast(toastMessage)
EndFunction

Function DispatchHungerImmersionToast(String detail)
  if Utility.IsInMenuMode()
    return
  endif

  if detail == ""
    return
  endif

  Debug.Notification(detail)

  lastTierToast_Hunger = detail
EndFunction

String Function GetHungerTierToastMessage(Int tier)
  String tierName = ""
  String tierLine = ""

  if tier == 4
    tierName = "Well Fed"
    tierLine = "I feel strong and nourished."
  elseif tier == 3
    tierName = "Satisfied"
    tierLine = "I am content."
  elseif tier == 2
    tierName = "Hungry"
    tierLine = "My stomach growls."
  elseif tier == 1
    tierName = "Starving"
    tierLine = "Weakness creeps in, I need food."
  elseif tier == 0
    tierName = "Famished"
    tierLine = "I am famished, my body fails me!"
  endif

  if tierName == "" && tierLine == ""
    return ""
  endif

  if tierName != "" && tierLine != ""
    return tierName + " — " + tierLine
  endif

  if tierName != ""
    return tierName
  endif

  return tierLine
EndFunction

Function InitHungerConfigDefaults()
  Int sentinelInt = -12345
  Float sentinelFloat = -12345.0
  Bool needsSave = False

  Int i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.enabled", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.enabled", 1)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.max", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.max", 100)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.start", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.start", 100)
    needsSave = True
  endif

  Float f = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.fedBufferHours", sentinelFloat)
  if f == sentinelFloat
    JsonUtil.SetPathFloatValue(CFG_PATH, "hunger.fedBufferHours", 4.0)
    needsSave = True
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.decayPerHour", sentinelFloat)
  if f == sentinelFloat
    JsonUtil.SetPathFloatValue(CFG_PATH, "hunger.decayPerHour", 5.0)
    needsSave = True
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.sleepDecayPerHour", sentinelFloat)
  if f == sentinelFloat
    JsonUtil.SetPathFloatValue(CFG_PATH, "hunger.sleepDecayPerHour", 2.5)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.tiers.t4_min", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.tiers.t4_min", 75)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.tiers.t3_min", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.tiers.t3_min", 50)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.tiers.t2_min", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.tiers.t2_min", 25)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.tiers.t1_min", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.tiers.t1_min", 10)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier4.bonusMaxPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier4.bonusMaxPct", 10)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier4.bonusRegenPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier4.bonusRegenPct", 10)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier3.speedPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier3.speedPct", 0)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier3.regenStop", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier3.regenStop", 0)
    needsSave = True
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.penalties.tier3.damagePerSec", sentinelFloat)
  if f == sentinelFloat
    JsonUtil.SetPathFloatValue(CFG_PATH, "hunger.penalties.tier3.damagePerSec", 0.0)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier3.floorPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier3.floorPct", 100)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier2.speedPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier2.speedPct", 0)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier2.regenStop", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier2.regenStop", 0)
    needsSave = True
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.penalties.tier2.damagePerSec", sentinelFloat)
  if f == sentinelFloat
    JsonUtil.SetPathFloatValue(CFG_PATH, "hunger.penalties.tier2.damagePerSec", 5.0)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier2.floorPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier2.floorPct", 90)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier2.maxLossPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier2.maxLossPct", 10)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier1.speedPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier1.speedPct", -10)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier1.regenStop", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier1.regenStop", 0)
    needsSave = True
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.penalties.tier1.damagePerSec", sentinelFloat)
  if f == sentinelFloat
    JsonUtil.SetPathFloatValue(CFG_PATH, "hunger.penalties.tier1.damagePerSec", 10.0)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier1.floorPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier1.floorPct", 75)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier1.maxLossPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier1.maxLossPct", 25)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier0.speedPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier0.speedPct", -25)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier0.regenStop", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier0.regenStop", 1)
    needsSave = True
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.penalties.tier0.damagePerSec", sentinelFloat)
  if f == sentinelFloat
    JsonUtil.SetPathFloatValue(CFG_PATH, "hunger.penalties.tier0.damagePerSec", 15.0)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier0.floorPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier0.floorPct", 50)
    needsSave = True
  endif

  i = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.penalties.tier0.maxLossPct", sentinelInt)
  if i == sentinelInt
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.penalties.tier0.maxLossPct", 50)
    needsSave = True
  endif

  String rawKeyword = JsonUtil.GetPathStringValue(CFG_PATH, "hunger.food.rawKeyword", "__missing__")
  if rawKeyword == "__missing__"
    JsonUtil.SetPathStringValue(CFG_PATH, "hunger.food.rawKeyword", "VendorItemFoodRaw")
    needsSave = True
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.food.rawFactor", sentinelFloat)
  if f == sentinelFloat
    JsonUtil.SetPathFloatValue(CFG_PATH, "hunger.food.rawFactor", 0.10)
    needsSave = True
  endif

  Int bandCount = JsonUtil.PathCount(CFG_PATH, "hunger.food.valueBands")
  if bandCount <= 0
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[0].min", 0)
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[0].max", 25)
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[0].points", 10)

    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[1].min", 26)
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[1].max", 50)
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[1].points", 25)

    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[2].min", 51)
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[2].max", 75)
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[2].points", 50)

    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[3].min", 76)
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[3].max", 999999)
    JsonUtil.SetPathIntValue(CFG_PATH, "hunger.food.valueBands[3].points", 100)
    needsSave = True
  endif

  if needsSave
    JsonUtil.Save(CFG_PATH)
  endif
EndFunction

Function LoadHungerConfig()
  HungerEnabled = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.enabled", 1) > 0
  HungerMaxValue = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.max", 100)
  if HungerMaxValue <= 0
    HungerMaxValue = 100
  endif
  HungerStartValue = JsonUtil.GetPathIntValue(CFG_PATH, "hunger.start", HungerMaxValue)
  HungerStartValue = ClampInt(HungerStartValue, 0, HungerMaxValue)

  HungerFedBufferHours = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.fedBufferHours", 4.0)
  if HungerFedBufferHours < 0.0
    HungerFedBufferHours = 0.0
  endif

  HungerDecayPerHour = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.decayPerHour", 5.0)
  if HungerDecayPerHour < 0.0
    HungerDecayPerHour = 0.0
  endif

  HungerSleepDecayPerHour = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.sleepDecayPerHour", 2.5)
  if HungerSleepDecayPerHour < 0.0
    HungerSleepDecayPerHour = 0.0
  endif

  HungerTier4Min = ClampInt(JsonUtil.GetPathIntValue(CFG_PATH, "hunger.tiers.t4_min", 75), 0, 100)
  HungerTier3Min = ClampInt(JsonUtil.GetPathIntValue(CFG_PATH, "hunger.tiers.t3_min", 50), 0, 100)
  HungerTier2Min = ClampInt(JsonUtil.GetPathIntValue(CFG_PATH, "hunger.tiers.t2_min", 25), 0, 100)
  HungerTier1Min = ClampInt(JsonUtil.GetPathIntValue(CFG_PATH, "hunger.tiers.t1_min", 10), 0, 100)
EndFunction

Function LoadHungerState()
  Float nowTime = Utility.GetCurrentGameTime()
  Int storedValue = GetStoredInt(HungerKeyLastValue, HungerStartValue)
  storedValue = ClampInt(storedValue, 0, HungerMaxValue)

  lastHit100GameTime = GetStoredFloat(HungerKeyLastHit100, 0.0)
  if storedValue >= HungerMaxValue
    if lastHit100GameTime <= 0.0
      lastHit100GameTime = nowTime
    endif
  endif

  lastDecayCheckGameTime = GetStoredFloat(HungerKeyLastDecayCheck, 0.0)
  if lastDecayCheckGameTime <= 0.0
    lastDecayCheckGameTime = nowTime
  endif

  Int storedTier = GetStoredInt(HungerKeyLastTier, -1)

  suppressHungerTierToasts = True
  SetHungerValue(storedValue, lastHit100GameTime)
  suppressHungerTierToasts = False

  if storedTier >= 0 && storedTier <= 4
    lastHungerTier = storedTier
  else
    lastHungerTier = DetermineHungerTier(lastHungerValue)
  endif
  SaveHungerState()
EndFunction

Function SaveHungerState()
  StorageUtil.SetIntValue(None, HungerKeyLastValue, lastHungerValue)
  StorageUtil.SetFloatValue(None, HungerKeyLastHit100, lastHit100GameTime)
  StorageUtil.SetFloatValue(None, HungerKeyLastDecayCheck, lastDecayCheckGameTime)
  StorageUtil.SetIntValue(None, HungerKeyLastTier, lastHungerTier)
EndFunction

Int Function GetLastHungerValue()
  EnsureInitialized()
  return lastHungerValue
EndFunction

Float Function GetLastHit100GameTime()
  EnsureInitialized()
  return lastHit100GameTime
EndFunction

Float Function GetLastDecayCheckGameTime()
  EnsureInitialized()
  return lastDecayCheckGameTime
EndFunction

Int Function GetLastHungerTier()
  EnsureInitialized()
  return lastHungerTier
EndFunction

Int Function ClampInt(Int value, Int minValue, Int maxValue)
  if value < minValue
    value = minValue
  elseif value > maxValue
    value = maxValue
  endif
  return value
EndFunction

Bool Function IsImmersionToastsEnabled()
  return JsonUtil.GetPathIntValue(CFG_PATH, "ui.toasts.immersion", 1) > 0
EndFunction

Int Function GetStoredInt(String storageKey, Int fallback)
  if StorageUtil.HasIntValue(None, storageKey)
    return StorageUtil.GetIntValue(None, storageKey)
  endif
  return fallback
EndFunction

Float Function GetStoredFloat(String storageKey, Float fallback)
  if StorageUtil.HasFloatValue(None, storageKey)
    return StorageUtil.GetFloatValue(None, storageKey)
  endif
  return fallback
EndFunction

