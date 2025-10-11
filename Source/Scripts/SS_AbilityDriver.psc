Scriptname SS_AbilityDriver extends ActiveMagicEffect

Import JsonUtil

; ---- Config / Debug ----
String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto
Float Property DamageTickInterval = 1.0 Auto
Float Property Tier2DamagePerSecond = 5.0 Auto
Float Property Tier1DamagePerSecond = 10.0 Auto
Float Property Tier0DamagePerSecond = 15.0 Auto
Float Property Tier2FloorPercent = 90.0 Auto
Float Property Tier1FloorPercent = 75.0 Auto
Float Property Tier0FloorPercent = 50.0 Auto
Float Property Tier1SpeedPenaltyPct = 10.0 Auto
Float Property Tier0SpeedPenaltyPct = 25.0 Auto
Float Property Tier4BonusMaxPct = 10.0 Auto
Float Property Tier4BonusRegenPct = 25.0 Auto

Float Property HungerTier2DamagePerSecond = 5.0 Auto
Float Property HungerTier1DamagePerSecond = 10.0 Auto
Float Property HungerTier0DamagePerSecond = 15.0 Auto
Float Property HungerTier2FloorPercent = 90.0 Auto
Float Property HungerTier1FloorPercent = 75.0 Auto
Float Property HungerTier0FloorPercent = 50.0 Auto
Float Property HungerTier2SpeedPenaltyPct = 0.0 Auto
Float Property HungerTier1SpeedPenaltyPct = 10.0 Auto
Float Property HungerTier0SpeedPenaltyPct = 25.0 Auto
Float Property HungerTier4BonusMaxPct = 10.0 Auto
Float Property HungerTier4BonusRegenPct = 10.0 Auto
Bool bTraceLogs = False

Bool Property DebugEnabled Hidden
  Bool Function Get()
    return bTraceLogs
  EndFunction
EndProperty

; ---- Tier tracking ----
Actor PlayerRef
Int   currentWeatherTier = -1
Int   currentHungerTier = -1

Float appliedSpeedDelta = 0.0
Float appliedHealRateDelta = 0.0
Float appliedStaminaRateDelta = 0.0
Float appliedMagickaRateDelta = 0.0
Float appliedHealthBonus = 0.0
Float appliedStaminaBonus = 0.0
Float appliedMagickaBonus = 0.0

Bool  updateLoopActive = False
Bool  weatherDamageLoopActive = False
Bool  hungerDamageLoopActive = False
Bool  linearDamageLoopActive = False
Float weatherDamagePerSecond = 0.0
Float weatherDamageFloorPercent = 0.0
Float hungerDamagePerSecond = 0.0
Float hungerDamageFloorPercent = 0.0

Float weatherSpeedDelta = 0.0
Bool  weatherRegenOverride = False
Float weatherRegenBonusPct = 0.0
Float weatherBonusMaxPct = 0.0

Float hungerSpeedDelta = 0.0
Bool  hungerRegenOverride = False
Float hungerRegenBonusPct = 0.0
Float hungerBonusMaxPct = 0.0

Float targetHealthRatio  = 1.0
Float targetStaminaRatio = 1.0
Float targetMagickaRatio = 1.0

Int appliedHealthPenaltyPct  = 0
Int appliedStaminaPenaltyPct = 0
Int appliedMagickaPenaltyPct = 0
Int appliedSpeedPenaltyPct   = 0

Event OnEffectStart(Actor akTarget, Actor akCaster)
  PlayerRef = akTarget
  ApplyDebug()
  RegisterForModEvent("SS_SetCold", "OnColdEvent")
  RegisterForModEvent("SS_ClearCold", "OnColdClear")
  RegisterForModEvent("SS_HungerTierChanged", "OnHungerTierChanged")
  if DebugEnabled
    Debug.Trace("[SS] Driver OnEffectStart: registered for SS_SetCold / SS_ClearCold / SS_HungerTierChanged")
  endif
EndEvent

Event OnEffectFinish(Actor akTarget, Actor akCaster)
  ClearAll()
  UnregisterForAllModEvents()
  if DebugEnabled
    Debug.Trace("[SS] AbilityDriver: finish & cleared")
  endif
  PlayerRef = None
EndEvent

Function ApplyDebug()
  Bool dbg = JsonUtil.GetPathBoolValue(CFG_PATH, "debug.trace", False)
  bTraceLogs = dbg
EndFunction

; ========== Events from controller ==========
Event OnObjectEquipped(Form akBaseObject, ObjectReference akRef)
  if akBaseObject as Armor || akBaseObject as Light || akBaseObject as Weapon || akBaseObject as Ammo
    int h = ModEvent.Create("SS_QuickTick")
    if h
      ModEvent.PushString(h, "")
      ModEvent.PushFloat(h, 0.0)
      ModEvent.Send(h)
    endif
    if DebugEnabled
      Debug.Trace("[SS] Driver: equip detected -> QuickTick sent")
    endif
  endif
EndEvent

Event OnObjectUnequipped(Form akBaseObject, ObjectReference akRef)
  if akBaseObject as Armor || akBaseObject as Light || akBaseObject as Weapon || akBaseObject as Ammo
    int h = ModEvent.Create("SS_QuickTick")
    if h
      ModEvent.PushString(h, "")
      ModEvent.PushFloat(h, 0.0)
      ModEvent.Send(h)
    endif
    if DebugEnabled
      Debug.Trace("[SS] Driver: unequip detected -> QuickTick sent")
    endif
  endif
EndEvent

Event OnColdEvent(Int healthPenaltyPct, Int staminaPenaltyPct, Int magickaPenaltyPct, Int speedPenaltyPct, Int preparednessTier)
  if PlayerRef == None
    return
  endif

  if preparednessTier >= 0
    HandleTierUpdate(preparednessTier)
  else
    HandleLinearPenalties(healthPenaltyPct, staminaPenaltyPct, magickaPenaltyPct, speedPenaltyPct)
  endif
EndEvent

Event OnColdClear()
  if DebugEnabled
    Debug.Trace("[SS] Driver: OnColdClear -> reset")
  endif
  ClearTierEffects()
  ClearLinearEffects()
EndEvent

Event OnHungerTierChanged(Int newTier)
  if PlayerRef == None
    return
  endif

  HandleHungerTierUpdate(newTier)
EndEvent

Function ClearTierEffects()
  ResetWeatherPackage()
  currentWeatherTier = -1
  ApplyAggregatedEffects()
EndFunction


Function ClearHungerEffects()
  ResetHungerPackage()
  currentHungerTier = -1
  ApplyAggregatedEffects()
EndFunction

Function BuildWeatherPackageForTier(Int tier)
  ResetWeatherPackage()

  if tier >= 4
    weatherBonusMaxPct = Tier4BonusMaxPct
    weatherRegenBonusPct = Tier4BonusRegenPct
  elseif tier == 3
    ; no additional effects
  elseif tier == 2
    weatherDamagePerSecond = Tier2DamagePerSecond
    weatherDamageFloorPercent = Tier2FloorPercent
  elseif tier == 1
    weatherSpeedDelta = ResolvePenaltyDelta(Tier1SpeedPenaltyPct)
    weatherDamagePerSecond = Tier1DamagePerSecond
    weatherDamageFloorPercent = Tier1FloorPercent
  else
    weatherSpeedDelta = ResolvePenaltyDelta(Tier0SpeedPenaltyPct)
    weatherRegenOverride = True
    weatherDamagePerSecond = Tier0DamagePerSecond
    weatherDamageFloorPercent = Tier0FloorPercent
  endif
EndFunction

Function BuildHungerPackageForTier(Int tier)
  ResetHungerPackage()

  if tier >= 4
    hungerBonusMaxPct = HungerTier4BonusMaxPct
    hungerRegenBonusPct = HungerTier4BonusRegenPct
  elseif tier == 3
    ; no additional effects
  elseif tier == 2
    hungerSpeedDelta = ResolvePenaltyDelta(HungerTier2SpeedPenaltyPct)
    hungerDamagePerSecond = HungerTier2DamagePerSecond
    hungerDamageFloorPercent = HungerTier2FloorPercent
  elseif tier == 1
    hungerSpeedDelta = ResolvePenaltyDelta(HungerTier1SpeedPenaltyPct)
    hungerDamagePerSecond = HungerTier1DamagePerSecond
    hungerDamageFloorPercent = HungerTier1FloorPercent
  else
    hungerSpeedDelta = ResolvePenaltyDelta(HungerTier0SpeedPenaltyPct)
    hungerRegenOverride = True
    hungerDamagePerSecond = HungerTier0DamagePerSecond
    hungerDamageFloorPercent = HungerTier0FloorPercent
  endif
EndFunction

Function ApplyAggregatedEffects()
  if PlayerRef == None
    return
  endif

  Float totalSpeedDelta = weatherSpeedDelta + hungerSpeedDelta
  ApplySpeedDelta(totalSpeedDelta)

  ApplyMaxBonusTotals(weatherBonusMaxPct + hungerBonusMaxPct)
  ApplyRegenAggregates()
  UpdateDamageLoopFlags()
EndFunction

Function ApplyMaxBonusTotals(Float totalBonusPct)
  if totalBonusPct <= 0.0
    ClearMaxBonuses()
    return
  endif

  Float bonusFrac = totalBonusPct * 0.01
  appliedHealthBonus = ApplyMaxBonusForAV("Health", bonusFrac, appliedHealthBonus)
  appliedStaminaBonus = ApplyMaxBonusForAV("Stamina", bonusFrac, appliedStaminaBonus)
  appliedMagickaBonus = ApplyMaxBonusForAV("Magicka", bonusFrac, appliedMagickaBonus)
EndFunction

Function ApplyRegenAggregates()
  if PlayerRef == None
    return
  endif

  if weatherRegenOverride || hungerRegenOverride
    SuppressNaturalRegen()
    return
  endif

  Float totalBonusPct = weatherRegenBonusPct + hungerRegenBonusPct
  if totalBonusPct <= 0.0
    appliedHealRateDelta = ResetActorValueDelta("HealRateMult", appliedHealRateDelta)
    appliedStaminaRateDelta = ResetActorValueDelta("StaminaRateMult", appliedStaminaRateDelta)
    appliedMagickaRateDelta = ResetActorValueDelta("MagickaRateMult", appliedMagickaRateDelta)
    return
  endif

  Float factor = 1.0 + (totalBonusPct * 0.01)
  appliedHealRateDelta = ApplyActorValueTarget("HealRateMult", PlayerRef.GetActorValue("HealRateMult") * factor, appliedHealRateDelta)
  appliedStaminaRateDelta = ApplyActorValueTarget("StaminaRateMult", PlayerRef.GetActorValue("StaminaRateMult") * factor, appliedStaminaRateDelta)
  appliedMagickaRateDelta = ApplyActorValueTarget("MagickaRateMult", PlayerRef.GetActorValue("MagickaRateMult") * factor, appliedMagickaRateDelta)
EndFunction

Function ResetWeatherPackage()
  weatherSpeedDelta = 0.0
  weatherRegenOverride = False
  weatherRegenBonusPct = 0.0
  weatherBonusMaxPct = 0.0
  weatherDamagePerSecond = 0.0
  weatherDamageFloorPercent = 0.0
EndFunction

Function ResetHungerPackage()
  hungerSpeedDelta = 0.0
  hungerRegenOverride = False
  hungerRegenBonusPct = 0.0
  hungerBonusMaxPct = 0.0
  hungerDamagePerSecond = 0.0
  hungerDamageFloorPercent = 0.0
EndFunction

Function UpdateDamageLoopFlags()
  weatherDamageLoopActive = weatherDamagePerSecond > 0.0
  hungerDamageLoopActive = hungerDamagePerSecond > 0.0

  if weatherDamageLoopActive || hungerDamageLoopActive || linearDamageLoopActive
    EnsureUpdateLoop()
  else
    StopUpdateLoopIfIdle()
  endif
EndFunction

Float Function ResolvePenaltyDelta(Float configuredValue)
  if configuredValue > 0.0
    return -configuredValue
  endif
  return configuredValue
EndFunction

Function SuppressNaturalRegen()
  if PlayerRef == None
    return
  endif

  appliedHealRateDelta = ApplyActorValueTarget("HealRateMult", 0.0, appliedHealRateDelta)
  appliedStaminaRateDelta = ApplyActorValueTarget("StaminaRateMult", 0.0, appliedStaminaRateDelta)
  appliedMagickaRateDelta = ApplyActorValueTarget("MagickaRateMult", 0.0, appliedMagickaRateDelta)
EndFunction

Float Function ApplyMaxBonusForAV(String avName, Float bonusFrac, Float currentBonus)
  if PlayerRef == None
    return 0.0
  endif

  if currentBonus != 0.0
    PlayerRef.ModActorValue(avName, -currentBonus)
    currentBonus = 0.0
  endif

  Float baseValue = PlayerRef.GetBaseActorValue(avName)
  if baseValue <= 0.0
    return 0.0
  endif

  Float bonusAmount = baseValue * bonusFrac
  if bonusAmount != 0.0
    PlayerRef.ModActorValue(avName, bonusAmount)
    currentBonus = bonusAmount
  endif
  return currentBonus
EndFunction

Float Function ApplyActorValueTarget(String avName, Float targetValue, Float currentDelta)
  if PlayerRef == None
    return 0.0
  endif

  if currentDelta != 0.0
    PlayerRef.ModActorValue(avName, -currentDelta)
    currentDelta = 0.0
  endif

  Float currentValue = PlayerRef.GetActorValue(avName)
  Float delta = targetValue - currentValue
  if delta != 0.0
    PlayerRef.ModActorValue(avName, delta)
    currentDelta = delta
  endif
  return currentDelta
EndFunction

Float Function ResetActorValueDelta(String avName, Float currentDelta)
  if PlayerRef == None
    return 0.0
  endif
  if currentDelta != 0.0
    PlayerRef.ModActorValue(avName, -currentDelta)
  endif
  return 0.0
EndFunction

Function ClearMaxBonuses()
  if PlayerRef == None
    return
  endif

  if appliedHealthBonus != 0.0
    PlayerRef.ModActorValue("Health", -appliedHealthBonus)
    appliedHealthBonus = 0.0
  endif
  if appliedStaminaBonus != 0.0
    PlayerRef.ModActorValue("Stamina", -appliedStaminaBonus)
    appliedStaminaBonus = 0.0
  endif
  if appliedMagickaBonus != 0.0
    PlayerRef.ModActorValue("Magicka", -appliedMagickaBonus)
    appliedMagickaBonus = 0.0
  endif
EndFunction

Function ApplySpeedDelta(Float newDelta)
  if PlayerRef == None
    return
  endif

  Float deltaChange = newDelta - appliedSpeedDelta
  if deltaChange != 0.0
    PlayerRef.ModActorValue("SpeedMult", deltaChange)
    appliedSpeedDelta = newDelta
  endif
EndFunction

Function ProcessDamageTick(Float damagePerSecond, Float floorPercent)
  if PlayerRef == None
    return
  endif

  Float damagePerTick = damagePerSecond * DamageTickInterval
  if damagePerTick <= 0.0
    return
  endif

  Float floorRatio = ClampFloorRatio(floorPercent)

  ApplyDamageWithFloor("Health", damagePerTick, floorRatio)
  ApplyDamageWithFloor("Stamina", damagePerTick, floorRatio)
  ApplyDamageWithFloor("Magicka", damagePerTick, floorRatio)
EndFunction

Function ApplyDamageWithFloor(String avName, Float damagePerTick, Float floorRatio)
  if PlayerRef == None
    return
  endif

  Float percent = PlayerRef.GetActorValuePercentage(avName)
  if percent <= floorRatio
    return
  endif

  Float currentValue = PlayerRef.GetActorValue(avName)
  if percent <= 0.0
    return
  endif

  Float maxValue = currentValue / percent
  if maxValue <= 0.0
    return
  endif

  Float floorValue = maxValue * floorRatio
  Float allowableDamage = currentValue - floorValue
  if allowableDamage <= 0.0
    return
  endif

  Float damage = damagePerTick
  if damage > allowableDamage
    damage = allowableDamage
  endif

  if damage > 0.0
    PlayerRef.DamageActorValue(avName, damage)
  endif
EndFunction

Float Function ClampFloorRatio(Float floorPercent)
  Float ratio = floorPercent * 0.01
  if ratio < 0.0
    ratio = 0.0
  elseif ratio > 1.0
    ratio = 1.0
  endif
  return ratio
EndFunction

Int Function NormalizeTier(Int tier)
  if tier < 0
    return 0
  elseif tier > 4
    return 4
  endif
  return tier
EndFunction

Function HandleTierUpdate(Int newTier)
  ClearLinearEffects()
  Int tier = NormalizeTier(newTier)
  if tier == currentWeatherTier
    return
  endif
  if DebugEnabled
    Debug.Trace("[SS] Driver: weather tier change " + currentWeatherTier + " -> " + tier)
  endif
  BuildWeatherPackageForTier(tier)
  currentWeatherTier = tier
  ApplyAggregatedEffects()
EndFunction

Function HandleHungerTierUpdate(Int newTier)
  Int tier = NormalizeTier(newTier)
  if tier == currentHungerTier
    return
  endif
  if DebugEnabled
    Debug.Trace("[SS] Driver: hunger tier change " + currentHungerTier + " -> " + tier)
  endif
  BuildHungerPackageForTier(tier)
  currentHungerTier = tier
  ApplyAggregatedEffects()
EndFunction

Function HandleLinearPenalties(Int healthPenaltyPct, Int staminaPenaltyPct, Int magickaPenaltyPct, Int speedPenaltyPct)
  ClearTierEffects()
  ClearLinearEffects()
  currentWeatherTier = -1

  Int healthPenalty = SanitizePenalty(healthPenaltyPct, 80)
  Int staminaPenalty = SanitizePenalty(staminaPenaltyPct, 80)
  Int magickaPenalty = SanitizePenalty(magickaPenaltyPct, 80)
  Int speedPenalty = SanitizePenalty(speedPenaltyPct, 50)

  appliedHealthPenaltyPct = healthPenalty
  appliedStaminaPenaltyPct = staminaPenalty
  appliedMagickaPenaltyPct = magickaPenalty
  appliedSpeedPenaltyPct = speedPenalty

  targetHealthRatio = ComputeTargetRatio(healthPenalty)
  targetStaminaRatio = ComputeTargetRatio(staminaPenalty)
  targetMagickaRatio = ComputeTargetRatio(magickaPenalty)

  ApplySpeedPenalty(speedPenalty)
  ApplyRegenPenalty("HealRateMult", healthPenalty)
  ApplyRegenPenalty("StaminaRateMult", staminaPenalty)
  ApplyRegenPenalty("MagickaRateMult", magickaPenalty)

  if DebugEnabled
    Debug.Trace("[SS] Driver: linear penalties hp=" + healthPenalty + "% st=" + staminaPenalty + "% mg=" + magickaPenalty + "% spd=" + speedPenalty + "%")
  endif

  if NeedsLinearDamageLoop()
    StartLinearDamageLoop()
  else
    StopLinearDamageLoop()
  endif

  ApplyAggregatedEffects()
EndFunction

Function ClearAll()
  if PlayerRef == None
    return
  endif

  ClearTierEffects()
  ClearHungerEffects()
  ClearLinearEffects()
EndFunction

Function ClearLinearEffects()
  if PlayerRef == None
    return
  endif

  ApplySpeedPenalty(0)
  targetHealthRatio  = 1.0
  targetStaminaRatio = 1.0
  targetMagickaRatio = 1.0
  appliedHealthPenaltyPct  = 0
  appliedStaminaPenaltyPct = 0
  appliedMagickaPenaltyPct = 0
  appliedSpeedPenaltyPct   = 0
  PlayerRef.SetActorValue("HealRateMult", 1.0)
  PlayerRef.SetActorValue("StaminaRateMult", 1.0)
  PlayerRef.SetActorValue("MagickaRateMult", 1.0)
  StopLinearDamageLoop()
  ApplyAggregatedEffects()
EndFunction

Function ApplySpeedPenalty(Int newPenaltyPct)
  if PlayerRef == None
    return
  endif
  Int delta = newPenaltyPct - appliedSpeedPenaltyPct
  if delta != 0
    PlayerRef.ModActorValue("SpeedMult", -delta)
    appliedSpeedPenaltyPct = newPenaltyPct
  endif
EndFunction

Function ApplyRegenPenalty(String rateAV, Int penaltyPct)
  if PlayerRef == None
    return
  endif
  Float mult = 1.0
  if penaltyPct > 0
    mult = 1.0 - (penaltyPct as Float) * 0.01
    if mult < 0.2
      mult = 0.2
    endif
  endif
  PlayerRef.SetActorValue(rateAV, mult)
EndFunction

Int Function SanitizePenalty(Int value, Int maxAllowed)
  if value < 0
    value = 0
  endif
  if value > maxAllowed
    value = maxAllowed
  endif
  if value < 5
    return 0
  endif
  return value
EndFunction

Float Function ComputeTargetRatio(Int penaltyPct)
  if penaltyPct <= 0
    return 1.0
  endif
  Float ratio = 1.0 - (penaltyPct as Float) * 0.01
  if ratio < 0.0
    ratio = 0.0
  endif
  return ratio
EndFunction

Function StartLinearDamageLoop()
  linearDamageLoopActive = True
  EnsureUpdateLoop()
EndFunction

Function StopLinearDamageLoop()
  linearDamageLoopActive = False
  StopUpdateLoopIfIdle()
EndFunction

Function EnsureUpdateLoop()
  if !updateLoopActive
    updateLoopActive = True
    RegisterForSingleUpdate(DamageTickInterval)
  endif
EndFunction

Function StopUpdateLoopIfIdle()
  if !weatherDamageLoopActive && !hungerDamageLoopActive && !linearDamageLoopActive
    updateLoopActive = False
    UnregisterForUpdate()
  endif
EndFunction

Event OnUpdate()
  if PlayerRef == None
    weatherDamageLoopActive = False
    hungerDamageLoopActive = False
    linearDamageLoopActive = False
    updateLoopActive = False
    UnregisterForUpdate()
    return
  endif

  if weatherDamageLoopActive
    ProcessDamageTick(weatherDamagePerSecond, weatherDamageFloorPercent)
  endif

  if hungerDamageLoopActive
    ProcessDamageTick(hungerDamagePerSecond, hungerDamageFloorPercent)
  endif

  if linearDamageLoopActive
    ProcessLinearDamageTick()
  endif

  if weatherDamageLoopActive || hungerDamageLoopActive || linearDamageLoopActive
    RegisterForSingleUpdate(DamageTickInterval)
  else
    updateLoopActive = False
  endif
EndEvent

Function ProcessLinearDamageTick()
  if PlayerRef == None
    StopLinearDamageLoop()
    return
  endif

  if targetHealthRatio < 1.0
    ApplyDamageTowardsTarget("Health", targetHealthRatio)
  endif
  if targetStaminaRatio < 1.0
    ApplyDamageTowardsTarget("Stamina", targetStaminaRatio)
  endif
  if targetMagickaRatio < 1.0
    ApplyDamageTowardsTarget("Magicka", targetMagickaRatio)
  endif

  if !NeedsLinearDamageLoop()
    StopLinearDamageLoop()
  endif
EndFunction

Bool Function NeedsLinearDamageLoop()
  if PlayerRef == None
    return False
  endif
  if targetHealthRatio < 1.0 && IsStatAboveTarget("Health", targetHealthRatio)
    return True
  endif
  if targetStaminaRatio < 1.0 && IsStatAboveTarget("Stamina", targetStaminaRatio)
    return True
  endif
  if targetMagickaRatio < 1.0 && IsStatAboveTarget("Magicka", targetMagickaRatio)
    return True
  endif
  return False
EndFunction

Bool Function ApplyDamageTowardsTarget(String avName, Float targetRatio)
  if PlayerRef == None
    return False
  endif
  if targetRatio >= 1.0
    return False
  endif

  Float baseValue = PlayerRef.GetBaseActorValue(avName)
  if baseValue <= 0.0
    return False
  endif

  Float targetValue = baseValue * targetRatio
  Float currentValue = PlayerRef.GetActorValue(avName)
  if currentValue <= targetValue
    return False
  endif

  Float allowableDamage = currentValue - targetValue
  if allowableDamage <= 0.0
    return False
  endif

  Float damage = allowableDamage * 0.33
  if damage < 1.0
    damage = allowableDamage
  endif

  if damage <= 0.0
    return False
  endif

  PlayerRef.DamageActorValue(avName, damage)
  return True
EndFunction

Bool Function IsStatAboveTarget(String avName, Float targetRatio)
  if PlayerRef == None
    return False
  endif
  if targetRatio >= 1.0
    return False
  endif

  Float baseValue = PlayerRef.GetBaseActorValue(avName)
  if baseValue <= 0.0
    return False
  endif

  Float targetValue = baseValue * targetRatio
  Float currentValue = PlayerRef.GetActorValue(avName)
  return currentValue > targetValue + 0.25
EndFunction
