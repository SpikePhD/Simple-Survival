Scriptname SS_WeatherTick extends ReferenceAlias

; ========= Config =========
Bool  Property DebugLog = False Auto

; ========= Cached state =========
Bool     _lastIsInterior
Location _lastLocation
Weather  _lastActualWeather

; ========= Utilities =========
Function Log(string s)
    if DebugLog
        Debug.Trace("[SS_WeatherTick] " + s)
    endif
EndFunction

Int _nextId = 0

Function FireTick(string reason, float numArg = 0.0, Form sender = None)
    if sender == None
        sender = GetReference() as Form
        if sender == None
            sender = Game.GetPlayer() as Form
        endif
    endif

    _nextId += 1
    float snapshot = _nextId as Float

    ; Listeners expect: OnSSTick(string eventName, string reason, float numArg, Form sender)
    int h = ModEvent.Create("SS_Tick")
    if h
        ModEvent.PushString(h, reason)
        ModEvent.PushFloat(h, snapshot)
        ModEvent.PushForm(h, sender)
        ModEvent.Send(h)
        Log("Tick -> " + reason + " (id=" + _nextId + ")")
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

    PO3_Events_Alias.RegisterForWeatherChange(self)            ; Event OnWeatherChange(...)
    PO3_Events_Alias.RegisterForOnPlayerFastTravelEnd(self)    ; Event OnPlayerFastTravelEnd(...)
    PO3_Events_Alias.RegisterForCellFullyLoaded(self)          ; Event OnCellFullyLoaded(...)
EndEvent

Event OnPlayerLoadGame()
    Log("OnPlayerLoadGame")
    InitSnapshots()
EndEvent

Function InitSnapshots()
    Actor p = GetReference() as Actor
    if !p
        return
    endif
    _lastActualWeather = Weather.GetCurrentWeather()
    _lastLocation      = p.GetCurrentLocation()
    _lastIsInterior    = p.GetParentCell().IsInterior()
EndFunction

; ========= PO3 Events =========
Event OnWeatherChange(Weather akOldWeather, Weather akNewWeather)
    _lastActualWeather = akNewWeather
    ; Keep sender consistent as the alias/player form
    FireTick("ActualWeatherChanged")
EndEvent

Event OnPlayerFastTravelEnd(float afTravelGameTimeHours)
    FireTick("FastTravelEnd", afTravelGameTimeHours)
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