Scriptname SS_PlayerEvents extends ReferenceAlias

Import PO3_Events_Alias

Quest Property ControllerQuest Auto
Float sleepStartGameTime = 0.0
Bool  lastSwimmingState = False

Event OnInit()
  RegisterForWeatherChange(Self)
  RegisterForOnPlayerFastTravelEnd(Self)
  TriggerEnvironmentRefresh("Init")
  lastSwimmingState = ResolveCurrentSwimmingState()
  RegisterForSingleUpdate(0.5)
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

Event OnWeatherChange(Weather akOldWeather, Weather akNewWeather)
  TriggerEnvironmentRefresh("WeatherChange")
EndEvent

Event OnPlayerFastTravelEnd(Float afTravelGameTimeHours)
  SS_Controller controller = ResolveController()
  if controller != None
    controller.NotifyFastTravelOrigin()
  endif
  TriggerEnvironmentRefresh("FastTravelEnd", controller)
EndEvent

Event OnPlayerLoadGame()
  lastSwimmingState = ResolveCurrentSwimmingState()
  RegisterForSingleUpdate(0.5)
EndEvent

Event OnUpdate()
  SS_Controller controller = ResolveController()
  Bool isSwimming = ResolveCurrentSwimmingState()
  if isSwimming != lastSwimmingState
    lastSwimmingState = isSwimming
    String source = "SwimmingStop"
    if isSwimming
      source = "SwimmingStart"
    endif
    TriggerEnvironmentRefresh(source, controller)
  elseif isSwimming && controller != None
    controller.RequestRefresh("Swimming")
  endif

  Float nextInterval = 1.5
  if isSwimming
    nextInterval = 0.5
  endif
  RegisterForSingleUpdate(nextInterval)
EndEvent

Function TriggerEnvironmentRefresh(String source = "", SS_Controller cachedController = None)
  SS_Controller controller = cachedController
  if controller == None
    controller = ResolveController()
  endif
  if controller != None
    if source != ""
      Debug.Trace("[SS] PlayerEvents: " + source + " -> refresh")
    endif
    controller.RequestRefresh(source)
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

Bool Function ResolveCurrentSwimmingState()
  Actor player = Game.GetPlayer()
  if player == None
    return False
  endif
  return player.IsSwimming()
EndFunction
