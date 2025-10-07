Scriptname SS_AbilityDriver extends ActiveMagicEffect

; This AME is the single source of truth for applying *temporary*
; SpeedMult and Regen multipliers based on ModEvents from SS_Controller.

Import JsonUtil

; ---- Config / Debug ----
String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto
Bool bTraceLogs = False

; ---- Internal tracking so we can revert cleanly ----
Int   appliedHealthPenaltyPct  = 0
Int   appliedStaminaPenaltyPct = 0
Int   appliedMagickaPenaltyPct = 0
Int   appliedSpeedPenaltyPct   = 0
Float appliedHealthMod = 0.0
Float appliedStaminaMod = 0.0
Float appliedMagickaMod = 0.0

Actor PlayerRef

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
      ModEvent.PushString(h, "")     ; arg1 required by signature
      ModEvent.PushFloat(h, 0.0)     ; arg2 required by signature
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

Event OnColdEvent(Int healthPenaltyPct, Int staminaPenaltyPct, Int magickaPenaltyPct, Int speedPenaltyPct)
  if PlayerRef == None
    return
  endif

  healthPenaltyPct  = SanitizePenalty(healthPenaltyPct, 80)
  staminaPenaltyPct = SanitizePenalty(staminaPenaltyPct, 80)
  magickaPenaltyPct = SanitizePenalty(magickaPenaltyPct, 80)
  speedPenaltyPct   = SanitizePenalty(speedPenaltyPct, 50)

  ApplySpeedPenalty(speedPenaltyPct)
  appliedHealthMod  = UpdateStatPenalty("Health",  healthPenaltyPct,  appliedHealthMod)
  appliedStaminaMod = UpdateStatPenalty("Stamina", staminaPenaltyPct, appliedStaminaMod)
  appliedMagickaMod = UpdateStatPenalty("Magicka", magickaPenaltyPct, appliedMagickaMod)

  appliedHealthPenaltyPct  = healthPenaltyPct
  appliedStaminaPenaltyPct = staminaPenaltyPct
  appliedMagickaPenaltyPct = magickaPenaltyPct
  appliedSpeedPenaltyPct   = speedPenaltyPct

  ApplyRegenPenalty("HealRateMult",    healthPenaltyPct)
  ApplyRegenPenalty("StaminaRateMult", staminaPenaltyPct)
  ApplyRegenPenalty("MagickaRateMult", magickaPenaltyPct)

  if bTraceLogs
    Float sm = PlayerRef.GetActorValue("SpeedMult")
    Float hr = PlayerRef.GetActorValue("HealRateMult")
    Float sr = PlayerRef.GetActorValue("StaminaRateMult")
    Float mr = PlayerRef.GetActorValue("MagickaRateMult")
    Debug.Trace("[SS] Driver <- hp=" + healthPenaltyPct + "% st=" + staminaPenaltyPct + "% mg=" + magickaPenaltyPct + "% speed=" + speedPenaltyPct + "% | post SpeedMult=" + sm + " HealRateMult=" + hr + " StaminaRateMult=" + sr + " MagickaRateMult=" + mr)
  endif
EndEvent

Event OnColdClear()
  ClearAll()
  if bTraceLogs
    Debug.Trace("[SS] Driver: clear request")
  endif
EndEvent

Function ClearAll()
  if PlayerRef == None
    return
  endif
  if appliedSpeedPenaltyPct != 0
    PlayerRef.ModActorValue("SpeedMult", appliedSpeedPenaltyPct)
    appliedSpeedPenaltyPct = 0
  endif

  if appliedHealthMod > 0.0
    PlayerRef.ModActorValue("Health", appliedHealthMod)
    appliedHealthMod = 0.0
  endif
  if appliedStaminaMod > 0.0
    PlayerRef.ModActorValue("Stamina", appliedStaminaMod)
    appliedStaminaMod = 0.0
  endif
  if appliedMagickaMod > 0.0
    PlayerRef.ModActorValue("Magicka", appliedMagickaMod)
    appliedMagickaMod = 0.0
  endif

  PlayerRef.SetActorValue("HealRateMult",    1.0)
  PlayerRef.SetActorValue("StaminaRateMult", 1.0)
  PlayerRef.SetActorValue("MagickaRateMult", 1.0)

  appliedHealthPenaltyPct  = 0
  appliedStaminaPenaltyPct = 0
  appliedMagickaPenaltyPct = 0
EndFunction

Function ApplySpeedPenalty(Int newPenaltyPct)
  if PlayerRef == None
    return
  endif
  if appliedSpeedPenaltyPct != 0
    PlayerRef.ModActorValue("SpeedMult", appliedSpeedPenaltyPct)
    appliedSpeedPenaltyPct = 0
  endif
  if newPenaltyPct > 0
    PlayerRef.ModActorValue("SpeedMult", -newPenaltyPct)
    appliedSpeedPenaltyPct = newPenaltyPct
  endif
EndFunction

Float Function UpdateStatPenalty(String avName, Int newPenaltyPct, Float previousAppliedMod)
  if PlayerRef == None
    return 0.0
  endif
  if previousAppliedMod > 0.0
    PlayerRef.ModActorValue(avName, previousAppliedMod)
  endif

  if newPenaltyPct <= 0
    return 0.0
  endif

  Float baseValue = PlayerRef.GetBaseActorValue(avName)
  if baseValue <= 0.0
    return 0.0
  endif

  Float newMod = baseValue * (newPenaltyPct as Float) * 0.01
  if newMod > baseValue
    newMod = baseValue
  endif
  if newMod > 0.0
    PlayerRef.ModActorValue(avName, -newMod)
  endif
  return newMod
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
