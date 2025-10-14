Scriptname SS_WeatherTick extends ReferenceAlias

; ========= Config =========
Bool  Property DebugLog = False Auto

; ========= Cached state =========
Bool     _lastIsInterior
Location _lastLocation
Weather  _lastActualWeather
Int      _nextSnapshot = 1

; ========= Utilities =========
Function Log(string s)
    if DebugLog
        Debug.Trace("[SS_WeatherTick] " + s)
    endif
EndFunction

Function FireTick(string reason)
    Int snapshotId = _nextSnapshot
    _nextSnapshot = _nextSnapshot + 1

    int h = ModEvent.Create("SS_WeatherTick")
    if h
        ; strArg = reason, numArg = snapshotId
        ModEvent.PushString(h, reason)
        ModEvent.PushFloat(h, snapshotId as Float)
        ModEvent.Send(h)
        Log("Tick -> " + reason + " (id=" + snapshotId + ")")
    endif
EndFunction

; ========= Lifecycle =========
Event OnInit()
    Log("OnInit")
    InitSnapshots()

    RegisterForMenu("WaitingMenu")
    RegisterForMenu("Sleep/Wait Menu")
    RegisterForMenu("ConfigManagerMenu")
    RegisterForMenu("Mod Configuration Menu")

    PO3_Events_Alias.RegisterForWeatherChange(self)
    PO3_Events_Alias.RegisterForOnPlayerFastTravelEnd(self)
    PO3_Events_Alias.RegisterForCellFullyLoaded(self)

    ; Kick an initial evaluation so the HUD/toasts don’t wait for first change
    FireTick("Init")
EndEvent

Event OnPlayerLoadGame()
    Log("OnPlayerLoadGame")
    InitSnapshots()
    FireTick("LoadGame")
EndEvent

Function InitSnapshots()
    Actor p = GetReference() as Actor
    if !p
        return
    endif
    _lastActualWeather = Weather.GetCurrentWeather()
    _lastLocation      = p.GetCurrentLocation()
    Bool isInt = False
    Cell pc = p.GetParentCell()
    if pc
        isInt = pc.IsInterior()
    endif
    _lastIsInterior    = isInt
EndFunction

; ========= PO3 Events =========
Event OnWeatherChange(Weather akOldWeather, Weather akNewWeather)
    _lastActualWeather = akNewWeather
    FireTick("ActualWeatherChanged")
EndEvent

Event OnPlayerFastTravelEnd(float afTravelGameTimeHours)
    FireTick("FastTravelEnd")
EndEvent

Event OnCellFullyLoaded(Cell akCell)
    Actor p = GetReference() as Actor
    if !p
        return
    endif
    Bool nowInterior = p.GetParentCell().IsInterior()
    if nowInterior != _lastIsInterior
        _lastIsInterior = nowInterior
        if nowInterior
            FireTick("TransitionToInterior")
        else
            FireTick("TransitionToExterior")
        endif
    endif
EndEvent

; ========= Vanilla Events (no polling) =========
Event OnLocationChange(Location akOldLoc, Location akNewLoc)
    _lastLocation = akNewLoc
    FireTick("LocationChanged")
EndEvent

Event OnCellLoad()
    Actor p = GetReference() as Actor
    if !p
        return
    endif
    Bool nowInterior = p.GetParentCell().IsInterior()
    if nowInterior != _lastIsInterior
        _lastIsInterior = nowInterior
        if nowInterior
            FireTick("TransitionToInterior")
        else
            FireTick("TransitionToExterior")
        endif
    endif
EndEvent

; Equip/Unequip (player-only)
Event OnObjectEquipped(Form akBaseObject, ObjectReference akRef)
    if akRef == GetReference()
        FireTick("Equipped")
    endif
EndEvent

Event OnObjectUnequipped(Form akBaseObject, ObjectReference akRef)
    if akRef == GetReference()
        FireTick("Unequipped")
    endif
EndEvent

; Sleep / Wait
Event OnSleepStart(float afSleepStartTime, float afDesiredSleepEndTime)
    if GetReference() as Actor
        FireTick("SleepStart")
    endif
EndEvent

Event OnSleepStop(Bool abInterrupted)
    if GetReference() as Actor
        FireTick("SleepStop")
    endif
EndEvent

; ========= Consolidated menu events =========
Event OnMenuOpen(String menuName)
    if menuName == "WaitingMenu"
        FireTick("WaitStart")
    elseif menuName == "Sleep/Wait Menu"
        FireTick("SleepMenuOpen")
    elseif menuName == "ConfigManagerMenu" || menuName == "Mod Configuration Menu"
        FireTick("MCMOpen")
    endif
EndEvent

Event OnMenuClose(String menuName)
    if menuName == "WaitingMenu"
        FireTick("WaitStop")
    elseif menuName == "Sleep/Wait Menu"
        FireTick("SleepMenuClose")
    elseif menuName == "ConfigManagerMenu" || menuName == "Mod Configuration Menu"
        FireTick("MCMClose")
    endif
EndEvent