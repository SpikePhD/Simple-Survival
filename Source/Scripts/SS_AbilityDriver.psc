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
Bool bTraceLogs = False

; ---- Tier tracking ----
Actor PlayerRef
Int   currentTier = -1

Float appliedSpeedDelta = 0.0
Float appliedHealRateDelta = 0.0
Float appliedStaminaRateDelta = 0.0
Float appliedMagickaRateDelta = 0.0
Float appliedHealthBonus = 0.0
Float appliedStaminaBonus = 0.0
Float appliedMagickaBonus = 0.0

Bool  damageLoopActive = False
Float activeDamagePerSecond = 0.0
Float activeDamageFloorPercent = 0.0

Event OnEffectStart(Actor akTarget, Actor akCaster)
  PlayerRef = akTarget
  ApplyDebug()
  RegisterForModEvent("SS_SetCold", "OnColdEvent")
  RegisterForModEvent("SS_ClearCold", "OnColdClear")
  if bTraceLogs
    Debug.Trace("[SS] Driver OnEffectStart: registered for SS_SetCold / SS_ClearCold")
  endif
EndEvent

Scriptname SS_AbilityDriver extends ActiveMagicEffect

Import JsonUtil

; ---- Config / Debug ----
String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto
Float Property DamagePerSecond = 5.0 Auto
Float Property DamageTickInterval = 1.0 Auto
Bool bTraceLogs = False
Bool useTierSystem = False

; ---- Penalty tracking ----
Int   appliedHealthPenaltyPct  = 0
Int   appliedStaminaPenaltyPct = 0
Int   appliedMagickaPenaltyPct = 0
Int   appliedSpeedPenaltyPct   = 0

Float targetHealthRatio  = 1.0
Float targetStaminaRatio = 1.0
Float targetMagickaRatio = 1.0

Bool  damageLoopActive = False
Bool  tierDamageLoopActive = False
Float tierSpeedDelta = 0.0
Bool  tierHealModified = False
Bool  tierStaminaModified = False
Bool  tierMagickaModified = False
Float tierHealRateMult = 1.0
Float tierStaminaRateMult = 1.0
Float tierMagickaRateMult = 1.0
Int   currentTier = -1
Int   lastTier = -1
Float kTierDamageTickInterval = 1.0

Actor PlayerRef

Event OnEffectStart(Actor akTarget, Actor akCaster)
  PlayerRef = akTarget
  ApplyDebug()
  useTierSystem = ReadUseTierSystemFlag()
  damageLoopActive = False
  tierDamageLoopActive = False
  tierSpeedDelta = 0.0
  tierHealModified = False
  tierStaminaModified = False
  tierMagickaModified = False
  tierHealRateMult = 1.0
  tierStaminaRateMult = 1.0
  tierMagickaRateMult = 1.0
  currentTier = -1
  lastTier = -1
  RegisterForModEvent("SS_SetCold", "OnColdEvent")
  RegisterForModEvent("SS_ClearCold", "OnColdClear")
  RegisterForModEvent("SS_TierChanged", "OnTierChanged")
  if bTraceLogs
    Debug.Trace("[SS] Driver OnEffectStart: registered for SS_SetCold / SS_ClearCold / SS_TierChanged | tierFlag=" + useTierSystem)
  endif
EndEvent

Event OnEffectFinish(Actor akTarget, Actor akCaster)
  ClearAll()
  UnregisterForAllModEvents()
  if bTraceLogs
    Debug.Trace("[SS] AbilityDriver: finish & cleared")
  endif
  PlayerRef = None
EndEvent

  currentTier = -1
  lastTier = -1
  PlayerRef = None
EndEvent

Function ApplyDebug()
  Bool dbg = JsonUtil.GetPathBoolValue(CFG_PATH, "debug.trace", False)
  bTraceLogs = dbg
EndFunction

; ========== Events from controller ==========
Event OnObjectEquipped(Form akBaseObject, ObjectReference akRef)
  if akBaseObject as Armor
    int h = ModEvent.Create("SS_QuickTick")
    if h
      ModEvent.PushString(h, "")
      ModEvent.PushFloat(h, 0.0)
      ModEvent.Send(h)
    endif
    if bTraceLogs
      Debug.Trace("[SS] Driver: equip detected -> QuickTick sent")
    endif
Bool Function ReadUseTierSystemFlag()
  Int sentinel = JsonUtil.GetPathIntValue(CFG_PATH, "penalties.useTierSystem", -9999)
  if sentinel != -9999
    return sentinel > 0
  endif
  return JsonUtil.GetPathBoolValue(CFG_PATH, "penalties.useTierSystem", False)
EndFunction

; ========== Events from controller ==========
Event OnObjectEquipped(Form akBaseObject, ObjectReference akRef)
  if ShouldForceRefresh(akBaseObject)
    TriggerQuickTick("equip", akBaseObject)
  endif
EndEvent

Event OnObjectUnequipped(Form akBaseObject, ObjectReference akRef)
  if akBaseObject as Armor
    int h = ModEvent.Create("SS_QuickTick")
    if h
      ModEvent.PushString(h, "")
      ModEvent.PushFloat(h, 0.0)
      ModEvent.Send(h)
    endif
    if bTraceLogs
      Debug.Trace("[SS] Driver: unequip detected -> QuickTick sent")
    endif
  endif
EndEvent

Event OnColdEvent(Int healthPenaltyPct, Int staminaPenaltyPct, Int magickaPenaltyPct, Int speedPenaltyPct, Int preparednessTier)
  if PlayerRef == None
    return
  endif

  Int tier = NormalizeTier(preparednessTier)
  if tier == currentTier
    return
  endif

  if bTraceLogs
    Debug.Trace("[SS] Driver: tier change " + currentTier + " -> " + tier)
  endif

  ClearTierEffects()
  currentTier = tier
  ApplyTierEffects(tier)
EndEvent

Event OnColdClear()
  if bTraceLogs
    Debug.Trace("[SS] Driver: OnColdClear -> reset")
  endif
  ClearAll()
EndEvent

Function ClearAll()
  if PlayerRef == None
    return
  endif

  ClearTierEffects()
  currentTier = -1
EndFunction

Function ClearTierEffects()
  if PlayerRef == None
    return
  endif

  ApplySpeedDelta(0.0)
  appliedHealRateDelta = ResetActorValueDelta("HealRateMult", appliedHealRateDelta)
  appliedStaminaRateDelta = ResetActorValueDelta("StaminaRateMult", appliedStaminaRateDelta)
  appliedMagickaRateDelta = ResetActorValueDelta("MagickaRateMult", appliedMagickaRateDelta)
  ClearMaxBonuses()
  StopTierDamageLoop()
EndFunction

Function ApplyTierEffects(Int tier)
  if ShouldForceRefresh(akBaseObject)
    TriggerQuickTick("unequip", akBaseObject)
  endif
EndEvent

Bool Function ShouldForceRefresh(Form equippedObject)
  if equippedObject == None
    return False
  endif

  if equippedObject as Armor
    return True
  endif

  if equippedObject as Light
    return True
  endif

  return False
EndFunction

Function TriggerQuickTick(String reason, Form equippedObject)
  int h = ModEvent.Create("SS_QuickTick")
  if h
    ModEvent.PushString(h, "")
    ModEvent.PushFloat(h, 0.0)
    ModEvent.Send(h)
  endif

  if !bTraceLogs
    return
  endif

  String objectName = ""
  if equippedObject != None
    objectName = equippedObject.GetName()
  endif

  Debug.Trace("[SS] Driver: " + reason + " detected -> QuickTick sent (" + objectName + ")")
EndFunction

Event OnColdEvent(Int healthPenaltyPct, Int staminaPenaltyPct, Int magickaPenaltyPct, Int speedPenaltyPct)
  if PlayerRef == None
    return
  endif

  if tier >= 4
    ApplyTierFourBonuses()
    return
  endif

  if tier == 3
    return
  endif

  if tier == 2
    StartTierDamageLoop(Tier2DamagePerSecond, Tier2FloorPercent)
  elseif tier == 1
    ApplySpeedDelta(-Tier1SpeedPenaltyPct)
    StartTierDamageLoop(Tier1DamagePerSecond, Tier1FloorPercent)
  else
    ApplySpeedDelta(-Tier0SpeedPenaltyPct)
    SuppressNaturalRegen()
    StartTierDamageLoop(Tier0DamagePerSecond, Tier0FloorPercent)
  endif
EndFunction

Function ApplyTierFourBonuses()
  if PlayerRef == None
    return
  endif

  Float bonusFrac = Tier4BonusMaxPct * 0.01
  if bonusFrac > 0.0
    appliedHealthBonus = ApplyMaxBonusForAV("Health", bonusFrac, appliedHealthBonus)
    appliedStaminaBonus = ApplyMaxBonusForAV("Stamina", bonusFrac, appliedStaminaBonus)
    appliedMagickaBonus = ApplyMaxBonusForAV("Magicka", bonusFrac, appliedMagickaBonus)
  endif

  Float regenFrac = Tier4BonusRegenPct * 0.01
  if regenFrac > 0.0
    Float factor = 1.0 + regenFrac
    appliedHealRateDelta = ApplyActorValueTarget("HealRateMult", PlayerRef.GetActorValue("HealRateMult") * factor, appliedHealRateDelta)
    appliedStaminaRateDelta = ApplyActorValueTarget("StaminaRateMult", PlayerRef.GetActorValue("StaminaRateMult") * factor, appliedStaminaRateDelta)
    appliedMagickaRateDelta = ApplyActorValueTarget("MagickaRateMult", PlayerRef.GetActorValue("MagickaRateMult") * factor, appliedMagickaRateDelta)
  endif
EndFunction

Function SuppressNaturalRegen()
  useTierSystem = ReadUseTierSystemFlag()
  if useTierSystem
    if bTraceLogs
      Debug.Trace("[SS] Driver: ignoring SS_SetCold (tier system active)")
    endif
    return
  endif

  ClearTierEffects()

  appliedHealthPenaltyPct  = SanitizePenalty(healthPenaltyPct, 80)
  appliedStaminaPenaltyPct = SanitizePenalty(staminaPenaltyPct, 80)
  appliedMagickaPenaltyPct = SanitizePenalty(magickaPenaltyPct, 80)
  appliedSpeedPenaltyPct   = SanitizePenalty(speedPenaltyPct, 50)

  targetHealthRatio  = ComputeTargetRatio(appliedHealthPenaltyPct)
  targetStaminaRatio = ComputeTargetRatio(appliedStaminaPenaltyPct)
  targetMagickaRatio = ComputeTargetRatio(appliedMagickaPenaltyPct)

  ApplySpeedPenalty(appliedSpeedPenaltyPct)
  ApplyRegenPenalty("HealRateMult",    appliedHealthPenaltyPct)
  ApplyRegenPenalty("StaminaRateMult", appliedStaminaPenaltyPct)
  ApplyRegenPenalty("MagickaRateMult", appliedMagickaPenaltyPct)

  if NeedsDamageLoop()
    EnsureDamageLoop()
  endif

  if bTraceLogs
    Float sm = PlayerRef.GetActorValue("SpeedMult")
    Float hr = PlayerRef.GetActorValue("HealRateMult")
    Float sr = PlayerRef.GetActorValue("StaminaRateMult")
    Float mr = PlayerRef.GetActorValue("MagickaRateMult")
    Debug.Trace("[SS] Driver <- hp=" + appliedHealthPenaltyPct + "% st=" + appliedStaminaPenaltyPct + "% mg=" + appliedMagickaPenaltyPct + "% speed=" + appliedSpeedPenaltyPct + "% | post SpeedMult=" + sm + " HealRateMult=" + hr + " StaminaRateMult=" + sr + " MagickaRateMult=" + mr)
  endif
EndEvent

Event OnColdClear()
  useTierSystem = ReadUseTierSystemFlag()
  if useTierSystem
    ClearTierEffects()
    if bTraceLogs
      Debug.Trace("[SS] Driver: ignoring SS_ClearCold (tier system active)")
    endif
    return
  endif

  ClearAll()
  if bTraceLogs
    Debug.Trace("[SS] Driver: clear request")
  endif
EndEvent

Event OnTierChanged(Int newTier, String changeSource)
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

Function StartTierDamageLoop(Float damagePerSecond, Float floorPercent)
  if PlayerRef == None
    return
  endif

  activeDamagePerSecond = damagePerSecond
  activeDamageFloorPercent = floorPercent

  if activeDamagePerSecond <= 0.0
    damageLoopActive = False
    return
  endif

  damageLoopActive = True
  RegisterForSingleUpdate(DamageTickInterval)
EndFunction

Function StopTierDamageLoop()
  damageLoopActive = False
  activeDamagePerSecond = 0.0
  activeDamageFloorPercent = 0.0
  UnregisterForUpdate()
EndFunction

Event OnUpdate()
  if !damageLoopActive || PlayerRef == None
    damageLoopActive = False
    return
  endif

  if activeDamagePerSecond <= 0.0
    damageLoopActive = False
    return
  endif

  ProcessTierDamageTick()

  if damageLoopActive
    RegisterForSingleUpdate(DamageTickInterval)
  endif
EndEvent

Function ProcessTierDamageTick()
  if PlayerRef == None
    return
  endif

  Float damagePerTick = activeDamagePerSecond * DamageTickInterval
  if damagePerTick <= 0.0
    return
  endif

  Float floorRatio = ClampFloorRatio(activeDamageFloorPercent)

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
  useTierSystem = ReadUseTierSystemFlag()
  if !useTierSystem
    if bTraceLogs
      Debug.Trace("[SS] Driver: tier change ignored (tier system disabled)")
    endif
    return
  endif

  Int sanitizedTier = newTier
  if sanitizedTier < -1
    sanitizedTier = -1
  elseif sanitizedTier > 4
    sanitizedTier = 4
  endif

  currentTier = sanitizedTier

  if bTraceLogs
    Debug.Trace("[SS] Driver: tier -> " + sanitizedTier + " (" + changeSource + ")")
  endif

  if sanitizedTier != lastTier
    ClearAll()
    ApplyTierEffects(sanitizedTier)
    lastTier = sanitizedTier
  else
    ApplyTierEffects(sanitizedTier)
  endif
EndEvent

Function ClearAll()
  if PlayerRef == None
    ClearTierEffects()
    return
  endif

  ClearTierEffects()

  ApplySpeedPenalty(0)
  targetHealthRatio  = 1.0
  targetStaminaRatio = 1.0
  targetMagickaRatio = 1.0

  ApplyRegenPenalty("HealRateMult",    0)
  ApplyRegenPenalty("StaminaRateMult", 0)
  ApplyRegenPenalty("MagickaRateMult", 0)

  appliedHealthPenaltyPct  = 0
  appliedStaminaPenaltyPct = 0
  appliedMagickaPenaltyPct = 0
  appliedSpeedPenaltyPct   = 0

  StopDamageLoop()
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

Function EnsureDamageLoop()
  if !damageLoopActive
    damageLoopActive = True
    RegisterForSingleUpdate(DamageTickInterval)
  endif
EndFunction

Function StopDamageLoop()
  damageLoopActive = False
  if !tierDamageLoopActive
    UnregisterForUpdate()
  endif
EndFunction

Bool Function NeedsDamageLoop()
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

Event OnUpdate()
  if PlayerRef == None
    damageLoopActive = False
    StopTierDamageLoop()
    return
  endif

  if useTierSystem
    if tierDamageLoopActive
      ; future tier DoT logic placeholder
      RegisterForSingleUpdate(kTierDamageTickInterval)
    endif
    return
  endif

  Bool anyPenalty = targetHealthRatio < 1.0 || targetStaminaRatio < 1.0 || targetMagickaRatio < 1.0

  ApplyDamageTowardsTarget("Health",  targetHealthRatio)
  ApplyDamageTowardsTarget("Stamina", targetStaminaRatio)
  ApplyDamageTowardsTarget("Magicka", targetMagickaRatio)

  if anyPenalty
    damageLoopActive = True
    RegisterForSingleUpdate(DamageTickInterval)
  else
    StopDamageLoop()
  endif
EndEvent

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
  Float epsilon = 0.25

  if currentValue <= targetValue + epsilon
    return False
  endif

  Float damagePerTick = DamagePerSecond * DamageTickInterval
  Float excess = currentValue - targetValue
  Float damage = damagePerTick
  if damage > excess
    damage = excess
  endif
  if damage <= 0.0
    return False
  endif

  PlayerRef.DamageActorValue(avName, damage)
  return True
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

Int Function SanitizePenalty(Int value, Int maxAllowed)
  if value < 5
    return 0
  endif
  if value > maxAllowed
    return maxAllowed
  endif
  if value < 0
    return 0
  endif
  return value
EndFunction

Function ClearTierEffects()
  Actor target = PlayerRef
  if target != None
    if tierSpeedDelta != 0.0
      target.ModActorValue("SpeedMult", -tierSpeedDelta)
    endif
    if tierHealModified
      target.SetActorValue("HealRateMult", 1.0)
    endif
    if tierStaminaModified
      target.SetActorValue("StaminaRateMult", 1.0)
    endif
    if tierMagickaModified
      target.SetActorValue("MagickaRateMult", 1.0)
    endif
  endif

  tierSpeedDelta = 0.0
  tierHealModified = False
  tierStaminaModified = False
  tierMagickaModified = False
  tierHealRateMult = 1.0
  tierStaminaRateMult = 1.0
  tierMagickaRateMult = 1.0
  StopTierDamageLoop()
EndFunction

Function ApplyTierEffects(Int tier)
  ; Placeholder for tier-based penalties
EndFunction

Function StartTierDamageLoop()
  if tierDamageLoopActive
    return
  endif
  if !useTierSystem
    return
  endif
  tierDamageLoopActive = True
  RegisterForSingleUpdate(kTierDamageTickInterval)
EndFunction

Function StopTierDamageLoop()
  tierDamageLoopActive = False
  if !damageLoopActive
    UnregisterForUpdate()
  endif
EndFunction
