Scriptname SS_PlayerEvents extends ReferenceAlias

Quest Property ControllerQuest Auto

Float sleepStartGameTime = 0.0

Event OnInit()
  TriggerEnvironmentRefresh("Init")
EndEvent

Event OnLocationChange(Location akOldLoc, Location akNewLoc)
  TriggerEnvironmentRefresh("LocationChange")
EndEvent

Event OnCellAttach()
  TriggerEnvironmentRefresh("CellAttach")
EndEvent

Event OnCellDetach()
  TriggerEnvironmentRefresh("CellDetach")
EndEvent

Event OnSleepStart(Float afSleepStartTime, Float afDesiredWakeTime)
  sleepStartGameTime = Utility.GetCurrentGameTime()
EndEvent

Event OnSleepStop(Bool abInterrupted)
  Float hoursSlept = 0.0
  if sleepStartGameTime > 0.0
    Float delta = Utility.GetCurrentGameTime() - sleepStartGameTime
    if delta > 0.0
      hoursSlept = delta * 24.0
    endif
    sleepStartGameTime = 0.0
  endif

  SS_Controller controller = ResolveController()
  if controller != None
    Debug.Trace("[SS] PlayerEvents: Sleep ended (" + hoursSlept + "h) -> refresh")
    controller.NotifySleepComplete(hoursSlept)
  endif
EndEvent

Function TriggerEnvironmentRefresh(String source = "")
  SS_Controller controller = ResolveController()
  if controller != None
    if source != ""
      Debug.Trace("[SS] PlayerEvents: " + source + " -> refresh")
    endif
    controller.RequestRefresh()
  endif
EndFunction

SS_Controller Function ResolveController()
  SS_Controller controller = None

  if ControllerQuest != None
    controller = ControllerQuest as SS_Controller
  endif

  if controller == None
    Quest owningQuest = GetOwningQuest()
    if owningQuest != None
      controller = owningQuest as SS_Controller
    else
      Debug.Trace("[SS] PlayerEvents: No owning quest for alias")
    endif
  endif

  return controller
EndFunction
