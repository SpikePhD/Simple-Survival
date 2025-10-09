Scriptname SS_Weather extends Quest

; =======================
; Imports / Config Path
; =======================
Import JsonUtil
Import StringUtil
Import Math
String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto

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
Int   Property LastHealthPenalty Auto
Int   Property LastStaminaPenalty Auto
Int   Property LastMagickaPenalty Auto
Int   Property LastSpeedPenalty Auto
Int   lastRegionBucket = -99
Int   lastWeatherClass = -99

; --- Debug ---
Bool  bDebugEnabled = False
Bool  bTraceLogs    = False

; --- Cadence control (adaptive) ---
Bool  bAdaptiveTick = True       ; can expose via MCM later
Float kFastTickH    = 0.0167     ; ~60 in-game seconds
Float kNormalTickH  = 0.10       ; 6  in-game minutes
Float kSlowTickH    = 0.40       ; 24 in-game minutes
Float kColdDrainFrac = 0.05
Float kColdFloorFrac = 0.20
Float kMinRefreshGapSeconds = 0.3
Float kToastCooldownSeconds = 1.0

Bool  bRefreshQueued = False
String queuedSource = ""
Float lastEvaluateRealTime = 0.0
Float lastToastRealTime = 0.0
String lastToastMessage = ""

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
  EvaluateWeather("Init")
EndEvent

Event OnPlayerLoadGame()
  InitConfigDefaults()
  ApplyDebugFlags()
  EnsurePlayerHasAbility()
  bRunning = True
  EvaluateWeather("OnPlayerLoadGame")
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

  if bTraceLogs
    Debug.Trace("[SS] EvaluateWeather (" + source + ")")
  endif

  ; ---- read config ----
  Bool  coldOn    = GetB("weather.cold.enable", True)
  Float baseRequirement = ReadBaseRequirement()
  Int regionClass = GetRegionClassification()
  Int weatherClass = GetWeatherClassification()
  Float safeReq     = ComputeWarmthRequirement(p, baseRequirement, regionClass, weatherClass)
  Float modifierSum = safeReq - baseRequirement
  Float autoPer   = GetF("weather.cold.autoWarmthPerPiece", 100.0)
  Float coldTick  = GetF("weather.cold.tick", 0.0) ; optional hp bleed per tick at max deficit

  LastBaseRequirement = baseRequirement
  LastSafeRequirement = safeReq
  LastWeatherBonus    = modifierSum
  Bool forecastChanged = (regionClass != lastRegionBucket)
  Bool weatherChanged = (currentWeather != lastWeatherForm) || (weatherClass != lastWeatherClass)

  Bool debugToastsEnabled = IsDebugToastsEnabled()
  Bool immersionToastsEnabled = IsImmersionToastsEnabled()

  ; ---- warmth/deficit from gear ----
  Float warmth = GetPlayerWarmthScoreV1(p, autoPer)
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
  Int preparednessTier = DeterminePreparednessTier(warmth, safeReq)

  ; ---- penalties mapping ----
  ; ---- apply or clear via driver ----
  if coldOn
    int h = ModEvent.Create("SS_SetCold")
    if h
      ModEvent.PushInt(h, healthPenaltyPct)
      ModEvent.PushInt(h, staminaPenaltyPct)
      ModEvent.PushInt(h, magickaPenaltyPct)
      ModEvent.PushInt(h, speedPenaltyPct)
      ModEvent.Send(h)

      if bDebugEnabled
        String msg = "[SS] warm=" + warmth + " / req=" + baseRequirement + " + modifiers=" + modifierSum + " => " + safeReq + " | def=" + deficit + " | hpPen=" + healthPenaltyPct + "% spdPen=" + speedPenaltyPct + "%"
        if bTraceLogs
          Debug.Trace(msg)
        else
          Debug.Notification(msg)
        endif
      endif

      if bTraceLogs
        Debug.Trace("[SS] Sent SS_SetCold | hp=" + healthPenaltyPct + "% st=" + staminaPenaltyPct + "% mg=" + magickaPenaltyPct + "% speed=" + speedPenaltyPct + "%")
      endif
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

    ; Cold resource drain disabled for linear penalty testing
  else
    int h2 = ModEvent.Create("SS_ClearCold")
    if h2
      ModEvent.Send(h2)
      if bDebugEnabled
        Debug.Notification("[SS] cold OFF -> clear penalties")
      endif
      if bTraceLogs
        Debug.Trace("[SS] Sent SS_ClearCold")
      endif
    endif
    LastHealthPenalty  = 0
    LastStaminaPenalty = 0
    LastMagickaPenalty = 0
    LastSpeedPenalty   = 0
  endif

  Bool sourceIsFastTravel = SourceIncludes(source, "FastTravelEnd")
  Bool locationSource = sourceIsFastTravel || SourceIncludes(source, "LocationChange") || SourceIncludes(source, "CellAttach") || SourceIncludes(source, "CellDetach")
  Bool locationChanged = (newLocationName != oldLocationName) || (newWorldspaceName != oldWorldspaceName)
  Bool interiorChanged = isInterior != oldInterior

  if debugToastsEnabled
    if sourceIsFastTravel
      String fromLabel = FormatLocationLabel(pendingFastTravelOriginLocation, pendingFastTravelOriginWorldspace)
      Bool originInterior = pendingFastTravelOriginInterior
      if fromLabel == "Unknown"
        fromLabel = FormatLocationLabel(oldLocationName, oldWorldspaceName)
        originInterior = oldInterior
      endif
      String destLabel = FormatLocationLabel(newLocationName, newWorldspaceName)
      String fromDetail = fromLabel + " (" + FormatInteriorState(originInterior) + ")"
      String destDetail = destLabel + " (" + FormatInteriorState(isInterior) + ")"
      DispatchToast("Debug Fast Travel:", "From " + fromDetail + " -> " + destDetail, "Debug")
    elseif locationSource && (locationChanged || interiorChanged)
      if oldLocationName != "" || oldWorldspaceName != ""
        String locFrom = FormatLocationLabel(oldLocationName, oldWorldspaceName)
        String locTo = FormatLocationLabel(newLocationName, newWorldspaceName)
        DispatchToast("Debug Location:", locFrom + " -> " + locTo + " (" + FormatInteriorState(isInterior) + ")", "Debug")
      endif
    endif

    if weatherChanged
      String prevWeatherName = FormatWeatherName(previousWeather)
      String newWeatherName = FormatWeatherName(currentWeather)
      DispatchToast("Debug Weather:", prevWeatherName + " -> " + newWeatherName, "Debug")
    endif

    if preparednessTier != lastPreparednessTier && lastPreparednessTier >= 0
      DispatchToast("Debug Preparedness:", "Tier " + lastPreparednessTier + " -> Tier " + preparednessTier, "Debug")
    endif
  endif

  if immersionToastsEnabled
    Bool isTriggerSource = True
    if source == ""
      isTriggerSource = False
    elseif SourceIncludes(source, "Tick")
      isTriggerSource = False
    endif

    if !isTriggerSource
      if forecastChanged || weatherChanged || locationChanged || interiorChanged || sourceIsFastTravel
        isTriggerSource = True
      endif
    endif

    if isTriggerSource
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

      if combinedMessage != ""
        DispatchToast("", combinedMessage, "Immersion")
      endif
    endif
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
            if bTraceLogs
              Debug.Trace("[SS] Cold drain " + av + ": current=" + current + " max=" + maxValue + " drain=" + drain + " floor=" + floorValue)
            endif
          endif
        elseif bTraceLogs
          Debug.Trace("[SS] Cold drain skipped for " + av + " (at or below floor)")
        endif
      endif
    elseif bTraceLogs
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
    if bTraceLogs
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

Int Function DeterminePreparednessTier(Float warmth, Float safeRequirement)
  if safeRequirement <= 0.0
    return 4
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

String Function GetPreparednessToastMessage(Int tier)
  if tier <= 0
    return "I am freezing!"
  elseif tier == 1
    return "I am cold!"
  elseif tier == 2
    return "I feel the breeze."
  elseif tier == 3
    return "I am a bit under-dressed."
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

  toastMessage = TrimWhitespace(toastMessage)
  if toastMessage == ""
    return
  endif

  Float now = Utility.GetCurrentRealTime()
  Float elapsed = now - lastToastRealTime

  if toastMessage == lastToastMessage
    if elapsed >= 0.0 && elapsed < kToastCooldownSeconds
      return
    endif
  endif

  lastToastRealTime = now
  lastToastMessage = toastMessage

  Debug.Notification(toastMessage)

  if bTraceLogs
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

Float Function GetPlayerWarmthScoreV1(Actor p, Float perPiece)
  if p == None
    return 0.0
  endif

  Float total = 0.0
  total += ComputePieceWarmth(p, 0x00000004, kBaseWarmthBody)
  total += ComputePieceWarmth(p, 0x00000001, kBaseWarmthHead, GetHeadGear(p))
  total += ComputePieceWarmth(p, 0x00000008, kBaseWarmthHands)
  total += ComputePieceWarmth(p, 0x00000080, kBaseWarmthFeet)
  total += ComputePieceWarmth(p, 0x00010000, kBaseWarmthCloak)

  if perPiece > 0.0 && perPiece != 100.0
    total *= (perPiece / 100.0)
  endif

  return total
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
  String rawName = a.GetName()
  if rawName != ""
    String lowerName = NormalizeWarmthName(rawName)
    warmth += GetWarmthBonusFromName(lowerName)
  endif

  return warmth
EndFunction

Float Function GetWarmthBonusFromName(String lowerName)
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

  JsonUtil.Save(CFG_PATH)
EndFunction

Event OnQuickTick(String speedStr, Float regenMult)
  if bTraceLogs
    Debug.Trace("[SS] QuickTick request received -> evaluate")
  endif
  RequestEvaluate("QuickTick", True)
EndEvent

Function ApplyDebugFlags()
  bDebugEnabled = GetB("debug.enable", False)
  bTraceLogs    = GetB("debug.trace", False)
  if bTraceLogs
    Debug.Trace("[SS] Controller init: debug=" + bDebugEnabled + " trace=1")
  endif

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

  EvaluateWeather(source)
EndEvent

Float Function GetMinRefreshGapSeconds()
  Float configured = GetF("weather.cold.minRefreshGapSeconds", kMinRefreshGapSeconds)
  if configured <= 0.0
    return kMinRefreshGapSeconds
  endif
  return configured
EndFunction

