Scriptname SS_Weather extends Quest

; =======================
; Imports / Config Path
; =======================
Import JsonUtil
Import StringUtil
Import Math
String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto

; ---------- Name-bonus cache state ----------
Bool     gearNameCacheValid = False
Int      gearNameCacheCount = 0
String[] gearNameMatchCache
Float[]  gearNameBonusCache

; Path to your JSON config (adjust if yours differs)
String   _configPath = "Data/SKSE/Plugins/SS/config.json"


; =======================
; Ability / Forms / Keywords
; =======================
Spell    Property SS_PlayerAbility    Auto    ; fill in CK with your hidden ability (has SS_AbilityDriver on its MGEF)

; =======================
; Runtime flags
; =======================
Bool  bRunning = False
Float Property LastWarmth Auto
Float Property LastSafeRequirement Auto
Float Property LastWeatherBonus Auto
Float Property LastBaseRequirement Auto
Float Property LastCoveragePercent Auto
Int   Property LastHealthPenalty Auto
Int   Property LastStaminaPenalty Auto
Int   Property LastMagickaPenalty Auto
Int   Property LastSpeedPenalty Auto
Int   lastRegionBucket = -99
Int   lastWeatherClass = -99

; --- Debug ---
Bool  bDebugNotifications = False
Bool  bTraceLogs          = False

Bool Property DebugEnabled Hidden
  Bool Function Get()
    return bTraceLogs
  EndFunction
EndProperty

; --- Cadence control (adaptive) ---
Bool  bAdaptiveTick = True       ; can expose via MCM later
Float kFastTickH    = 0.0167     ; ~60 in-game seconds
Float kNormalTickH  = 0.10       ; 6  in-game minutes
Float kSlowTickH    = 0.40       ; 24 in-game minutes
Float kColdDrainFrac = 0.05
Float kColdFloorFrac = 0.20
Float kMinRefreshGapSeconds = 0.0

Bool  bRefreshQueued = False
String queuedSource = ""
Float lastEvaluateRealTime = 0.0
String lastToastMessage = ""
String Property lastImmersionToast Auto
String Property lastTierToast Auto

Location lastKnownLocation
String   lastLocationName = ""
WorldSpace lastWorldspace
String     lastWorldspaceName = ""
Bool     lastInteriorState = False
Weather  lastWeatherForm

String pendingFastTravelOriginLocation = ""
String pendingFastTravelOriginWorldspace = ""
Bool   pendingFastTravelOriginInterior = False

Int    lastPreparednessTier = -1


; --- Warmth scoring constants ---
Float kBaseWarmthBody  = 50.0
Float kBaseWarmthHead  = 25.0
Float kBaseWarmthHands = 25.0
Float kBaseWarmthFeet  = 25.0
Float kBaseWarmthCloak = 30.0

; --- Gear warmth name bonus cache ---
Bool  _cacheReady = False
Bool  gearNameCaseInsensitive = True
Float gearNameBonusClamp = 0.0
Bool  gearNameUseLegacyFallback = False
String[] _nameBonusKeys
Float[]  _nameBonusVals

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

  if !_cacheReady
    EnsureNameBonusCache(False)
    if !_cacheReady
      return
    endif
  endif

  if forceImmediate
    if bRefreshQueued
      bRefreshQueued = False
      queuedSource = ""
    endif
    EvaluateWeather(source)
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
    EvaluateWeather(source)
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

Function RecordFastTravelOrigin()
  pendingFastTravelOriginLocation = lastLocationName
  pendingFastTravelOriginWorldspace = lastWorldspaceName
  pendingFastTravelOriginInterior = lastInteriorState
EndFunction

; =======================
; Lifecycle
; =======================
Event OnInit()
  InitConfigDefaults()
  ApplyDebugFlags()
  EnsurePlayerHasAbility()
  bRunning = True
  ; instant reactions on gear changes
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

Function EvaluateWeather(String source = "Tick")
  if !bRunning
    return
  endif

  Actor p = Game.GetPlayer()
  if p == None
    LastWarmth = 0.0
    LastSafeRequirement = 0.0
    LastWeatherBonus = 0.0
    LastBaseRequirement = 0.0
    LastCoveragePercent = 100.0
    LastHealthPenalty  = 0
    LastStaminaPenalty = 0
    LastMagickaPenalty = 0
    LastSpeedPenalty   = 0
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

  if DebugEnabled
    Debug.Trace("[SS] EvaluateWeather (" + source + ")")
  endif

  ; ---- read config ----
  Bool  coldOn    = GetB("weather.cold.enable", True)
  Bool  useTierSystem = GetB("penalties.useTierSystem", True)
  Float baseRequirement = ReadBaseRequirement()
  Int regionClass = GetRegionClassification()
  Int weatherClass = GetWeatherClassification()
  Float safeReq     = ComputeWarmthRequirement(p, baseRequirement, regionClass, weatherClass)
  Float modifierSum = safeReq - baseRequirement
  Float autoPer   = GetF("weather.cold.autoWarmthPerPiece", 100.0)
  Float coldTick  = GetF("weather.cold.tick", 0.0) ; optional hp bleed per tick at max deficit

  EnsureNameBonusCache(ShouldForceNameBonusReload(source))

  LastBaseRequirement = baseRequirement
  LastSafeRequirement = safeReq
  LastWeatherBonus    = modifierSum
  Bool forecastChanged = (regionClass != lastRegionBucket)
  Bool weatherChanged = (currentWeather != lastWeatherForm) || (weatherClass != lastWeatherClass)

  Bool immersionToastsEnabled = IsImmersionToastsEnabled()

  ; ---- warmth/deficit from gear ----
  Float warmth = GetPlayerWarmthScoreV1(p, autoPer, source)
  LastWarmth = warmth
  Float deficit = 0.0
  if warmth < safeReq
    deficit = safeReq - warmth
  endif

  Float penaltyDenom = safeReq
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
  Float coveragePercent = ComputeCoveragePercent(warmth, safeReq)
  LastCoveragePercent = coveragePercent
  Int preparednessTier = DetermineCoverageTier(coveragePercent)
  Bool preparednessTierChanged = (preparednessTier != lastPreparednessTier)

  if useTierSystem && preparednessTierChanged
    Int tierEvent = ModEvent.Create("SS_TierChanged")
    if tierEvent
      ModEvent.PushInt(tierEvent, preparednessTier)
      ModEvent.PushString(tierEvent, source)
      ModEvent.Send(tierEvent)

      if DebugEnabled
        Debug.Trace("[SS] Sent SS_TierChanged | tier=" + preparednessTier + " source=" + source)
      endif
    endif
  endif

  ; ---- penalties mapping ----
  ; ---- apply or clear via driver ----
  if coldOn
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
        String debugMsg = "[SS] warm=" + warmth + " / req=" + baseRequirement + " + modifiers=" + modifierSum + " => " + safeReq + " | def=" + deficit + " | hpPen=" + healthPenaltyPct + "% spdPen=" + speedPenaltyPct + "%"
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

      ; optional HP bleed (scaled by relative deficit)
      if coldTick > 0.0 && deficit > 0.0
        Float denom = safeReq
        if denom <= 0.0
          denom = 1.0
        endif
        Float scale = deficit / denom
        p.DamageActorValue("Health", coldTick * scale)
      endif
    endif

    ; Cold resource drain disabled for linear penalty testing
  else
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
  endif

  Bool sourceIsFastTravel = SourceIncludes(source, "FastTravelEnd")
  Bool locationChanged = (newLocationName != oldLocationName) || (newWorldspaceName != oldWorldspaceName)
  Bool interiorChanged = isInterior != oldInterior
  Bool exitedToExterior = interiorChanged && !isInterior
  if immersionToastsEnabled
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
  endif

  if immersionToastsEnabled && preparednessTierChanged
    String tierToastMessage = GetPreparednessToastMessage(preparednessTier)
    if tierToastMessage != ""
      DispatchToast("", tierToastMessage, "Immersion")
    endif
    lastTierToast = tierToastMessage
  endif

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

  lastEvaluateRealTime = Utility.GetCurrentRealTime()
EndFunction

Function ApplyColdResourceDrain(Actor p)
  if p == None || p.IsDead() || !p.Is3DLoaded()
    return
  endif

  String[] avNames = new String[3]
  avNames[0] = "Health"
  avNames[1] = "Stamina"
  avNames[2] = "Magicka"

  Int i = 0
  while i < avNames.Length
    String av = avNames[i]
    Float current = p.GetActorValue(av)
    Float percent = p.GetActorValuePercentage(av)
    if percent > 0.0
      Float maxValue = current / percent
      if maxValue > 0.0
        Float floorValue = maxValue * kColdFloorFrac
        if current > floorValue
          Float drain = maxValue * kColdDrainFrac
          if current - drain < floorValue
            drain = current - floorValue
          endif
          if drain > 0.0
            p.DamageActorValue(av, drain)
            if DebugEnabled
              Debug.Trace("[SS] Cold drain " + av + ": current=" + current + " max=" + maxValue + " drain=" + drain + " floor=" + floorValue)
            endif
          endif
        elseif DebugEnabled
          Debug.Trace("[SS] Cold drain skipped for " + av + " (at or below floor)")
        endif
      endif
    elseif DebugEnabled
      Debug.Trace("[SS] Cold drain skipped for " + av + " (percent=" + percent + ")")
    endif
    i += 1
  endwhile
EndFunction

; =======================
; Instant wake-ups (equip/swim)
; =======================

; =======================
; Ability ensure
; =======================
Function EnsurePlayerHasAbility()
  Actor p = Game.GetPlayer()
  if p == None || SS_PlayerAbility == None
    return
  endif
  if !p.HasSpell(SS_PlayerAbility)
    p.AddSpell(SS_PlayerAbility, False)
    if DebugEnabled
      Debug.Trace("[SS] Gave player SS_PlayerAbility")
    endif
  endif
EndFunction

; =======================
; Warmth demand helpers
; =====================

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

Bool Function SourceIncludes(String sources, String token)
  if sources == "" || token == ""
    return False
  endif
  return StringUtil.Find(sources, token) >= 0
EndFunction

Bool Function IsDebugToastsEnabled()
  return GetB("ui.toasts.debug", False)
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

Int Function DeterminePreparednessTier(Float warmth, Float safeRequirement)
  Float coverage = ComputeCoveragePercent(warmth, safeRequirement)
  return DetermineCoverageTier(coverage)
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

Int Function GetLastRegionClass()
  return lastRegionBucket
EndFunction

Int Function GetLastWeatherClass()
  return lastWeatherClass
EndFunction

Bool Function GetLastInteriorState()
  return lastInteriorState
EndFunction

Int Function GetLastPreparednessTier()
  return lastPreparednessTier
EndFunction

Int Function GetCurrentWeatherTier()
  return lastPreparednessTier
EndFunction

Float Function GetLastCoveragePercent()
  return LastCoveragePercent
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

  toastMessage = TrimWhitespace(toastMessage)
  if toastMessage == ""
    return
  endif

  if toastMessage == lastToastMessage
    return
  endif

  lastToastMessage = toastMessage

  Debug.Notification(toastMessage)

  if DebugEnabled
    Debug.Trace("[SS][" + category + "] " + toastMessage)
  endif
EndFunction

String Function TrimWhitespace(String value)
  Int totalLength = StringUtil.GetLength(value)
  if totalLength <= 0
    return ""
  endif

  Int startIndex = 0
  Bool foundLeading = False
  while startIndex < totalLength && !foundLeading
    String currentChar = StringUtil.GetNthChar(value, startIndex)
    if !IsWhitespaceChar(currentChar)
      foundLeading = True
    else
      startIndex += 1
    endif
  endwhile

  if startIndex >= totalLength
    return ""
  endif

  Int endIndex = totalLength - 1
  Bool foundTrailing = False
  while endIndex >= startIndex && !foundTrailing
    String trailingChar = StringUtil.GetNthChar(value, endIndex)
    if !IsWhitespaceChar(trailingChar)
      foundTrailing = True
    else
      endIndex -= 1
    endif
  endwhile

  Int trimmedLength = (endIndex - startIndex) + 1
  if trimmedLength <= 0
    return ""
  endif

  return StringUtil.Substring(value, startIndex, trimmedLength)
EndFunction

Bool Function IsWhitespaceChar(String charValue)
  if StringUtil.GetLength(charValue) <= 0
    return False
  endif

  Int codeValue = StringUtil.AsOrd(charValue)
  if codeValue == 32
    return True
  elseif codeValue == 9
    return True
  elseif codeValue == 10
    return True
  elseif codeValue == 13
    return True
  endif
  return False
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

Float Function GetLastSafeRequirement()
  return LastSafeRequirement
EndFunction

Float Function GetLastWeatherBonus()
  return LastWeatherBonus
EndFunction

; =======================
; Warmth scoring (lean/auto)
; =======================
Float Function GetLastWarmth()
  return LastWarmth
EndFunction

Float Function GetPlayerWarmthScoreV1(Actor p, Float perPiece, String source = "")
  if p == None
    return 0.0
  endif

  EnsureNameBonusCache(ShouldForceNameBonusReload(source))

  Float total = 0.0
  total += ComputePieceWarmth(p, 0x00000004, kBaseWarmthBody)
  total += ComputePieceWarmth(p, 0x00000001, kBaseWarmthHead, GetHeadGear(p))
  total += ComputePieceWarmth(p, 0x00000008, kBaseWarmthHands)
  total += ComputePieceWarmth(p, 0x00000080, kBaseWarmthFeet)
  total += ComputePieceWarmth(p, 0x00010000, kBaseWarmthCloak)
  total += GetTorchWarmthBonus(p)

  if perPiece > 0.0 && perPiece != 100.0
    total *= (perPiece / 100.0)
  endif

  if p.IsSwimming()
    Float swimMalus = GetF("weather.cold.swimWarmthMalus", 0.0)
    if swimMalus > 0.0
      swimMalus = 0.0
    elseif swimMalus < -500.0
      swimMalus = -500.0
    endif
    total += swimMalus
  endif

  return total
EndFunction

Float Function GetTorchWarmthBonus(Actor wearer)
  if wearer == None
    return 0.0
  endif

  Float torchBonus = GetF("weather.cold.torchWarmthBonus", 0.0)
  if torchBonus <= 0.0
    return 0.0
  endif

  Int leftHandType = wearer.GetEquippedItemType(1)
  Int rightHandType = wearer.GetEquippedItemType(0)

  if leftHandType == 11 || rightHandType == 11
    return torchBonus
  endif

  return 0.0
EndFunction

Armor Function GetHeadGear(Actor wearer)
  if wearer == None
    return None
  endif

  Armor gear = wearer.GetWornForm(0x00000001) as Armor
  if gear != None
    return gear
  endif

  gear = wearer.GetWornForm(0x00000002) as Armor
  if gear != None
    return gear
  endif

  return wearer.GetWornForm(0x00001000) as Armor
EndFunction

Float Function ComputePieceWarmth(Actor wearer, Int slotMask, Float baseWarmth, Armor preFetched = None)
  if wearer == None
    return 0.0
  endif

  Armor a = preFetched
  if a == None
    a = wearer.GetWornForm(slotMask) as Armor
  endif
  if a == None
    return 0.0
  endif

  Float warmth = baseWarmth
  warmth += GetNameBonusForItem(a)

  return warmth
EndFunction

Float Function GetNameBonusForItem(Form akItem)
    if akItem == None
        return 0.0
    endif

    EnsureNameBonusCache(False)
    if !gearNameCacheValid || gearNameCacheCount <= 0
        return 0.0
    endif

    String n = akItem.GetName()
    if n == ""
        return 0.0
    endif
    n = TrimWhitespace(n)
    if n == ""
        return 0.0
    endif

    ; case-insensitive substring match (adjust later if you add token/boundary mode)
    String nameLower = NormalizeWarmthName(n)

    Float acc = 0.0
    int i = 0
    while i < gearNameCacheCount
        String pat = gearNameMatchCache[i]
        String trimmedPat = TrimWhitespace(pat)
        if trimmedPat != ""
            String patLower = NormalizeWarmthName(trimmedPat)
            if StringUtil.Find(nameLower, patLower) != -1
                acc += gearNameBonusCache[i]
            endif
        endif
        i += 1
    endWhile

    ; optional per-piece cap
    if acc < 0.0
        acc = 0.0
    elseif acc > 60.0
        acc = 60.0
    endif
    return acc
EndFunction

Float Function GetLegacyWarmthBonus(String lowerName)
  if lowerName == ""
    return 0.0
  endif

  Float bonus = 0.0
  Bool  hasStormcloak = False

  if StringUtil.Find(lowerName, "leather") >= 0
    bonus += 50.0
  endif
  if StringUtil.Find(lowerName, "hide") >= 0
    bonus += 50.0
  endif
  if StringUtil.Find(lowerName, "fur") >= 0
    bonus += 40.0
  endif
  if StringUtil.Find(lowerName, "pelt") >= 0
    bonus += 40.0
  endif
  if StringUtil.Find(lowerName, "bear") >= 0
    bonus += 55.0
  endif
  if StringUtil.Find(lowerName, "wolf") >= 0
    bonus += 45.0
  endif
  if StringUtil.Find(lowerName, "stormcloak") >= 0
    bonus += 55.0
    hasStormcloak = True
  endif
  if StringUtil.Find(lowerName, "imperial") >= 0
    bonus += 35.0
  endif
  if StringUtil.Find(lowerName, "studded") >= 0
    bonus += 30.0
  endif
  if StringUtil.Find(lowerName, "scaled") >= 0
    bonus += 35.0
  endif
  if StringUtil.Find(lowerName, "guard") >= 0
    bonus += 30.0
  endif
  if StringUtil.Find(lowerName, "daedric") >= 0
    bonus += 70.0
  endif
  if StringUtil.Find(lowerName, "dragonplate") >= 0
    bonus += 70.0
  endif
  if StringUtil.Find(lowerName, "dragonscale") >= 0
    bonus += 65.0
  endif
  if StringUtil.Find(lowerName, "stalhrim") >= 0
    bonus += 65.0
  endif
  if StringUtil.Find(lowerName, "ebony") >= 0
    bonus += 60.0
  endif
  if StringUtil.Find(lowerName, "orcish") >= 0
    bonus += 45.0
  endif
  if StringUtil.Find(lowerName, "dwarven") >= 0
    bonus += 40.0
  endif
  if StringUtil.Find(lowerName, "iron") >= 0
    bonus += 15.0
  endif
  if StringUtil.Find(lowerName, "steel") >= 0
    bonus += 20.0
  endif
  if StringUtil.Find(lowerName, "elven") >= 0
    bonus += 35.0
  endif
  if StringUtil.Find(lowerName, "glass") >= 0
    bonus += 45.0
  endif
  if StringUtil.Find(lowerName, "chitin") >= 0
    bonus += 35.0
  endif
  if StringUtil.Find(lowerName, "bonemold") >= 0
    bonus += 40.0
  endif
  if !hasStormcloak
    if StringUtil.Find(lowerName, "cloak") >= 0
      bonus += 35.0
    endif
  endif
  if StringUtil.Find(lowerName, "cape") >= 0
    bonus += 30.0
  endif
  if StringUtil.Find(lowerName, "shawl") >= 0
    bonus += 25.0
  endif
  if StringUtil.Find(lowerName, "wrap") >= 0
    bonus += 20.0
  endif
  if StringUtil.Find(lowerName, "mantle") >= 0
    bonus += 20.0
  endif

  return bonus
EndFunction

Function InvalidateNameBonusCache()
    gearNameCacheValid = False
    gearNameCacheCount = 0
    gearNameMatchCache = None
    gearNameBonusCache = None
EndFunction

Function EnsureNameBonusCache(bool forceReload = False)
    if gearNameCacheValid && !forceReload
        return
    endif

    ; SAFELY pull arrays from JSON (never None)
    String[] nbMatches = SS_JsonHelpers.GetStringArraySafe(_configPath, ".gear.nameBonuses.matches")
    Float[]  nbValues  = SS_JsonHelpers.GetFloatArraySafe(_configPath,  ".gear.nameBonuses.values")

    ; Empty / missing config -> disable cache harmlessly
    if nbMatches.Length == 0 || nbValues.Length == 0
        InvalidateNameBonusCache()
        return
    endif

    ; Mismatched lengths -> disable cache safely
    if nbMatches.Length != nbValues.Length
        Debug.Trace("[SS] NameBonus: length mismatch; disabling cache")
        InvalidateNameBonusCache()
        return
    endif

    ; Build final typed arrays
    gearNameCacheCount = nbMatches.Length
    gearNameMatchCache = Utility.CreateStringArray(gearNameCacheCount)
    gearNameBonusCache = Utility.CreateFloatArray(gearNameCacheCount)

    int i = 0
    while i < gearNameCacheCount
        gearNameMatchCache[i] = nbMatches[i]
        gearNameBonusCache[i] = nbValues[i]
        i += 1
    endWhile

    gearNameCacheValid = True
EndFunction

Bool Function ShouldForceNameBonusReload(String source)
    if source == ""
        return False
    endif

    if SourceIncludes(source, "MCM")
        return True
    endif
    if SourceIncludes(source, "Refresh")
        return True
    endif
    if SourceIncludes(source, "Init")
        return True
    endif
    if SourceIncludes(source, "LoadGame")
        return True
    endif
    if SourceIncludes(source, "QuickTick")
        return True
    endif
    if SourceIncludes(source, "FastTick")
        return True
    endif

    return False
EndFunction

Bool Function IsWhitespaceChar(String ch)
  if ch == " "
    return True
  endif
  if ch == "\t"
    return True
  endif
  if ch == "\n"
    return True
  endif
  if ch == "\r"
    return True
  endif
  return False
EndFunction

String Function TrimWhitespace(String value)
  if value == ""
    return value
  endif

  Int startIndex = 0
  Int endIndex = StringUtil.GetLength(value) - 1

  while startIndex <= endIndex && IsWhitespaceChar(StringUtil.GetNthChar(value, startIndex))
    startIndex += 1
  endwhile

  while endIndex >= startIndex && IsWhitespaceChar(StringUtil.GetNthChar(value, endIndex))
    endIndex -= 1
  endwhile

  if startIndex > endIndex
    return ""
  endif

  Int length = endIndex - startIndex + 1
  return StringUtil.SubString(value, startIndex, length)
EndFunction

String Function NormalizeWarmthName(String rawName)
  if rawName == ""
    return rawName
  endif

  String uppercaseChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  String lowercaseChars = "abcdefghijklmnopqrstuvwxyz"
  Int nameLength = StringUtil.GetLength(rawName)
  Int index = 0
  String normalizedName = ""
  while index < nameLength
    String currentChar = StringUtil.GetNthChar(rawName, index)
    Int uppercaseIndex = StringUtil.Find(uppercaseChars, currentChar)
    if uppercaseIndex >= 0
      String lowerChar = StringUtil.GetNthChar(lowercaseChars, uppercaseIndex)
      normalizedName += lowerChar
    else
      normalizedName += currentChar
    endif
    index += 1
  endwhile

  return normalizedName
EndFunction

; =======================
; Config I/O (portable)
; =======================
Bool Function GetB(String path, Bool fallback = True)
  ; tolerant bool read (ints 0/1 or bool)
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
  ; safeThreshold (legacy compatibility)
  Float f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.safeThreshold", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.safeThreshold", 0.0)
  endif

  ; autoWarmthPerPiece
  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.autoWarmthPerPiece", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.autoWarmthPerPiece", 100.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.torchWarmthBonus", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.torchWarmthBonus", 30.0)
  endif

  ; additive weather modifiers
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

  ; cold.enable
  Int i = JsonUtil.GetPathIntValue(CFG_PATH, "weather.cold.enable", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "weather.cold.enable", 1)
  endif

  ; cold.tick (hp bleed scale)
  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.tick", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.tick", 0.0)
  endif

  ; penalties (tier defaults)
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

  ; debug toggles
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

  i = JsonUtil.GetPathIntValue(CFG_PATH, "gear.nameMatchCaseInsensitive", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "gear.nameMatchCaseInsensitive", 1)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "gear.nameBonusMaxPerItem", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "gear.nameBonusMaxPerItem", 60.0)
  endif

  Int gearBonusCount = JsonUtil.PathCount(CFG_PATH, "gear.nameBonuses")
  if gearBonusCount == -1
    JsonUtil.SetPathStringValue(CFG_PATH, "gear.nameBonuses[0].match", "fur")
    JsonUtil.SetPathFloatValue(CFG_PATH, "gear.nameBonuses[0].bonus", 20.0)
    JsonUtil.SetPathStringValue(CFG_PATH, "gear.nameBonuses[1].match", "wool")
    JsonUtil.SetPathFloatValue(CFG_PATH, "gear.nameBonuses[1].bonus", 15.0)
    JsonUtil.SetPathStringValue(CFG_PATH, "gear.nameBonuses[2].match", "bear")
    JsonUtil.SetPathFloatValue(CFG_PATH, "gear.nameBonuses[2].bonus", 30.0)
    JsonUtil.SetPathStringValue(CFG_PATH, "gear.nameBonuses[3].match", "wolf")
    JsonUtil.SetPathFloatValue(CFG_PATH, "gear.nameBonuses[3].bonus", 25.0)
  endif

  InvalidateNameBonusCache()

  JsonUtil.Save(CFG_PATH)
EndFunction

Event OnQuickTick(String speedStr, Float regenMult)
  if DebugEnabled
    Debug.Trace("[SS] QuickTick request received -> evaluate")
  endif
  RequestEvaluate("QuickTick", True)
EndEvent

Function ApplyDebugFlags()
  bDebugNotifications = GetB("debug.enable", False)
  bTraceLogs          = GetB("debug.trace", False)
  if DebugEnabled
    Debug.Trace("[SS] Controller init: debug=" + bDebugNotifications + " trace=1")
  endif

EndFunction

Event OnUpdate()
  if !bRefreshQueued
    return
  endif

  if !_cacheReady
    EnsureNameBonusCache(False)
    if !_cacheReady
      RegisterForSingleUpdate(0.5)
      return
    endif
  endif

  bRefreshQueued = False
  String source = queuedSource
  queuedSource = ""

  if source == ""
    source = "Queued"
  endif

  EvaluateWeather(source)
EndEvent

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

Float Function GetMinRefreshGapSeconds()
  Float configured = GetF("weather.cold.minRefreshGapSeconds", kMinRefreshGapSeconds)
  if configured < 0.0
    return 0.0
  endif
  return configured
EndFunction

