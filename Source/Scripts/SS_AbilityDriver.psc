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

Event OnEffectFinish(Actor akTarget, Actor akCaster)
  ClearAll()
  UnregisterForAllModEvents()
  if bTraceLogs
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
EndFunction
