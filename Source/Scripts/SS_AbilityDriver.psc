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
  currentTier = -1
  lastTier = -1
  PlayerRef = None
EndEvent

Function ApplyDebug()
  Bool dbg = JsonUtil.GetPathBoolValue(CFG_PATH, "debug.trace", False)
  bTraceLogs = dbg
EndFunction

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
