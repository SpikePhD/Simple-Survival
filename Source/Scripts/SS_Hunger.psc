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
Bool bTraceLogs = False

Keyword baseFoodKeyword
Keyword rawFoodKeyword
Keyword[] extraFoodKeywords
Int extraFoodKeywordCount
Float rawFoodFactor = 0.10
Int[] foodValueBandMins
Int[] foodValueBandMaxes
Int[] foodValueBandPoints

Event OnInit()
  InitializeModule()
EndEvent

Event OnPlayerLoadGame()
  InitializeModule()
EndEvent

Event OnPlayerSaveGame()
  EnsureInitialized()
  SaveHungerState()
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
  if hoursElapsed > 0.0
    TraceHungerTick(hoursElapsed, sleepingState)
  endif
  lastDecayCheckGameTime = nowTime
  SaveHungerState()
EndFunction

Function EnsureInitialized()
  if !bInitialized
    InitializeModule()
  endif
EndFunction

Function HandleFoodConsumed(Potion foodItem)
  EnsureInitialized()

  if !HungerEnabled
    return
  endif

  if foodItem == None
    return
  endif

  if !IsFoodItem(foodItem)
    return
  endif

  Bool rawState = IsRawFood(foodItem)
  Int restorePoints = ResolveFoodRestorePoints(foodItem, rawState)
  if restorePoints <= 0
    return
  endif

  Float nowTime = Utility.GetCurrentGameTime()
  Float newValue = lastHungerValue + restorePoints
  SetHungerValue(newValue, nowTime)
  lastDecayCheckGameTime = nowTime
  SaveHungerState()

  TraceFoodConsumed(foodItem, restorePoints)
  DispatchFoodToast(restorePoints, rawState)
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
    TraceHungerTier(resolvedTier)
    SendHungerTierEvent(resolvedTier)
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

Function SendHungerTierEvent(Int tier)
  int evt = ModEvent.Create("SS_HungerTierChanged")
  if evt
    ModEvent.PushInt(evt, tier)
    ModEvent.Send(evt)
  endif
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

Function DispatchFoodToast(Int restorePoints, Bool isRawFood)
  if restorePoints <= 0
    return
  endif

  if !IsImmersionToastsEnabled()
    return
  endif

  if Utility.IsInMenuMode()
    return
  endif

  String pointsText = Utility.ToString(restorePoints)
  String message = "That hit the spot. (+" + pointsText + ")"
  if isRawFood
    message = "Raw food barely helps. (+" + pointsText + ")"
  endif

  Debug.Notification(message)
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

  RefreshDebugTraceFlag()
  LoadFoodConsumptionConfig()
EndFunction

Function ApplyDebugFlags()
  RefreshDebugTraceFlag()
EndFunction

Function LoadFoodConsumptionConfig()
  baseFoodKeyword = ResolveKeyword("VendorItemFood")

  String rawKeywordName = JsonUtil.GetPathStringValue(CFG_PATH, "hunger.food.rawKeyword", "")
  rawFoodKeyword = ResolveKeyword(rawKeywordName)

  rawFoodFactor = JsonUtil.GetPathFloatValue(CFG_PATH, "hunger.food.rawFactor", 0.10)
  if rawFoodFactor < 0.0
    rawFoodFactor = 0.0
  endif

  Int configuredCount = JsonUtil.PathCount(CFG_PATH, "hunger.food.extraKeywords")
  if configuredCount < 0
    configuredCount = 0
  endif

  extraFoodKeywords = None
  extraFoodKeywordCount = 0

  if configuredCount <= 0
    return
  endif

  Int entryLimit = 128
  Bool hitLimit = False
  extraFoodKeywords = new Keyword[128]

  Int i = 0
  while i < configuredCount
    String basePath = "hunger.food.extraKeywords[" + Utility.ToString(i) + "]"
    String keywordName = JsonUtil.GetPathStringValue(CFG_PATH, basePath, "")
    Keyword keywordEntry = ResolveKeyword(keywordName)

    if keywordEntry != None
      if extraFoodKeywordCount < entryLimit
        extraFoodKeywords[extraFoodKeywordCount] = keywordEntry
        extraFoodKeywordCount += 1
      else
        hitLimit = True
        break
      endif
    endif

    i += 1
  endwhile

  if (!hitLimit && configuredCount > entryLimit) || hitLimit
    TraceHunger("Extra food keyword list hit the Papyrus 128 entry limit, ignoring additional entries.")
  endif

  if extraFoodKeywordCount <= 0
    extraFoodKeywords = None
    extraFoodKeywordCount = 0
  endif

  LoadFoodValueBands()
EndFunction

Function LoadFoodValueBands()
  Int bandCount = JsonUtil.PathCount(CFG_PATH, "hunger.food.valueBands")
  if bandCount < 0
    bandCount = 0
  endif

  if bandCount <= 0
    foodValueBandMins = None
    foodValueBandMaxes = None
    foodValueBandPoints = None
    return
  endif

  foodValueBandMins = Utility.CreateIntArray(bandCount)
  foodValueBandMaxes = Utility.CreateIntArray(bandCount)
  foodValueBandPoints = Utility.CreateIntArray(bandCount)

  Int i = 0
  while i < bandCount
    String basePath = "hunger.food.valueBands[" + Utility.ToString(i) + "]"
    foodValueBandMins[i] = JsonUtil.GetPathIntValue(CFG_PATH, basePath + ".min", 0)
    foodValueBandMaxes[i] = JsonUtil.GetPathIntValue(CFG_PATH, basePath + ".max", 0)
    foodValueBandPoints[i] = JsonUtil.GetPathIntValue(CFG_PATH, basePath + ".points", 0)
    i += 1
  endwhile
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

Bool Function IsFoodItem(Potion foodItem)
  if foodItem == None
    return False
  endif

  if baseFoodKeyword != None && foodItem.HasKeyword(baseFoodKeyword)
    return True
  endif

  if rawFoodKeyword != None && foodItem.HasKeyword(rawFoodKeyword)
    return True
  endif

  if extraFoodKeywords != None && extraFoodKeywordCount > 0
    Int i = 0
    while i < extraFoodKeywordCount
      Keyword keywordEntry = extraFoodKeywords[i]
      if keywordEntry != None && foodItem.HasKeyword(keywordEntry)
        return True
      endif
      i += 1
    endwhile
  endif

  return False
EndFunction

Bool Function IsRawFood(Potion foodItem)
  if rawFoodKeyword == None || foodItem == None
    return False
  endif

  return foodItem.HasKeyword(rawFoodKeyword)
EndFunction

Int Function ResolveFoodRestorePoints(Potion foodItem, Bool isRawFood)
  if foodItem == None
    return 0
  endif

  Int basePoints = DetermineFoodPointsForValue(foodItem.GetGoldValue())
  if basePoints <= 0
    return 0
  endif

  if isRawFood
    if rawFoodFactor <= 0.0
      return 0
    endif

    Float scaled = basePoints * rawFoodFactor
    Int adjusted = scaled as Int
    if adjusted < 0
      adjusted = 0
    endif
    return adjusted
  endif

  return basePoints
EndFunction

Int Function DetermineFoodPointsForValue(Int goldValue)
  if foodValueBandPoints == None
    return 0
  endif

  Int count = foodValueBandPoints.Length
  Int i = 0
  while i < count
    if goldValue >= foodValueBandMins[i] && goldValue <= foodValueBandMaxes[i]
      return foodValueBandPoints[i]
    endif
    i += 1
  endwhile

  return 0
EndFunction

Keyword Function ResolveKeyword(String keywordName)
  if keywordName == None
    return None
  endif

  if keywordName == ""
    return None
  endif

  Keyword resolved = Keyword.GetKeyword(keywordName)
  return resolved
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

Function RefreshDebugTraceFlag()
  bTraceLogs = JsonUtil.GetPathBoolValue(CFG_PATH, "debug.trace", False)
EndFunction

Function TraceHunger(String message)
  if !bTraceLogs
    return
  endif

  Debug.Trace("[SS][Hunger] " + message)
EndFunction

Function TraceHungerTick(Float hoursElapsed, Bool sleepingState)
  if !bTraceLogs
    return
  endif

  String stateLabel = "awake"
  if sleepingState
    stateLabel = "sleep"
  endif

  String hoursText = Utility.ToString(hoursElapsed, 2)
  String hungerText = Utility.ToString(lastHungerValue)
  TraceHunger("tick Δh=" + hoursText + " " + stateLabel + ", hunger=" + hungerText)
EndFunction

Function TraceHungerTier(Int tier)
  if !bTraceLogs
    return
  endif

  TraceHunger("tier -> " + Utility.ToString(tier))
EndFunction

Function TraceFoodConsumed(Potion foodItem, Int restorePoints)
  if !bTraceLogs
    return
  endif

  String foodName = ""
  if foodItem != None
    foodName = foodItem.GetName()
  endif

  if foodName == ""
    foodName = "(unnamed)"
  endif

  Int goldValue = 0
  if foodItem != None
    goldValue = foodItem.GetGoldValue()
  endif

  String valueText = Utility.ToString(goldValue)
  String restoreText = Utility.ToString(restorePoints)
  TraceHunger("ate " + foodName + " (value=" + valueText + ") -> +" + restoreText)
EndFunction

