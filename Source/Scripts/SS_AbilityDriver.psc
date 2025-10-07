Scriptname SS_AbilityDriver extends ActiveMagicEffect

; This AME is the single source of truth for applying *temporary*
; SpeedMult and Regen multipliers based on ModEvents from SS_Controller.

Import JsonUtil

; ---- Config / Debug ----
String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto
Bool bTraceLogs = False

; ---- Internal tracking so we can revert cleanly ----
Float appliedSpeedDelta = 0.0
Float appliedRegenMult  = 1.0

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

Event OnColdEvent(String speedStr, Float regenMult)
  if PlayerRef == None
    return
  endif

  ; --- parse speed ---
  Float speedDelta = 0.0
  if speedStr != ""
    speedDelta = speedStr as Float
  endif

  ; --- apply speed (delta) ---
  if speedDelta != appliedSpeedDelta
    if appliedSpeedDelta != 0.0
      PlayerRef.ModActorValue("SpeedMult", -appliedSpeedDelta)
    endif
    if speedDelta != 0.0
      PlayerRef.ModActorValue("SpeedMult", speedDelta)
    endif
    appliedSpeedDelta = speedDelta
  endif

  ; --- apply regen (absolute) ---
  if regenMult <= 0.05
    regenMult = 0.05
  endif
  if regenMult != appliedRegenMult
    PlayerRef.SetActorValue("HealRateMult",    regenMult)
    PlayerRef.SetActorValue("StaminaRateMult", regenMult)
    PlayerRef.SetActorValue("MagickaRateMult", regenMult)
    appliedRegenMult = regenMult
  endif

  if bTraceLogs
    Float sm = PlayerRef.GetActorValue("SpeedMult")
    Float hr = PlayerRef.GetActorValue("HealRateMult")
    Debug.Trace("[SS] Driver <- spd?=" + speedDelta + " | regenx=" + regenMult + " | post SpeedMult=" + sm + " HealRateMult=" + hr)
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
  if appliedSpeedDelta != 0.0
    PlayerRef.ModActorValue("SpeedMult", -appliedSpeedDelta)
    appliedSpeedDelta = 0.0
  endif
  if appliedRegenMult != 1.0
    PlayerRef.SetActorValue("HealRateMult",    1.0)
    PlayerRef.SetActorValue("StaminaRateMult", 1.0)
    PlayerRef.SetActorValue("MagickaRateMult", 1.0)
    appliedRegenMult = 1.0
  endif
EndFunction