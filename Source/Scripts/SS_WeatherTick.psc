Scriptname SS_WeatherTick extends ReferenceAlias

; ========= Debug / Build =========
bool   property SS_DEBUG    auto
string property SS_BUILD_TAG auto

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

    ; Use ModEvent so we can push a sender Form and keep 4-arg handlers happy
    int h = ModEvent.Create("SS_Tick4")
    bool okS = False
    bool okF = False
    bool okFm = False
    bool sent4 = False
    if h
        okS = ModEvent.PushString(h, reason)
        okF = ModEvent.PushFloat(h, snapshot)
        okFm = ModEvent.PushForm(h, sender)
        if okS && okF && okFm
            sent4 = ModEvent.Send(h)
        endif
    endif

    ; Always also send 3-arg fallback for runtimes that ignore PushForm
    (sender as Form).SendModEvent("SS_Tick3", reason, snapshot)

    if SS_DEBUG
        Debug.Trace("[SS_WeatherTick] Emit " + SS_BUILD_TAG + " id=" + _nextId + " reason=" + reason + " pushedS=" + okS + " pushedF=" + okF + " pushedForm=" + okFm + " sent4=" + sent4 + " (also sent SS_Tick3 fallback)")
    endif

    Log("Tick -> " + reason + " (id=" + _nextId + ")")
EndFunction

; ========= Lifecycle =========
Event OnInit()
    if SS_BUILD_TAG == ""
        SS_BUILD_TAG = "Tick 2025-10-16.c"
    endif
    Debug.Trace("[SS_WeatherTick] OnInit build=" + SS_BUILD_TAG)

    Log("OnInit")
    InitSnapshots()

    RegisterForMenu("WaitingMenu")
    RegisterForMenu("Sleep/Wait Menu")
    RegisterForMenu("ConfigManagerMenu")
    RegisterForMenu("Mod Configuration Menu")

    PO3_Events_Alias.RegisterForWeatherChange(self)
    PO3_Events_Alias.RegisterForOnPlayerFastTravelEnd(self)
    PO3_Events_Alias.RegisterForCellFullyLoaded(self)

    ; prime downstream systems once on init so their first page open has data
    FireTick("Init")
EndEvent

Event OnPlayerLoadGame()
    Log("OnPlayerLoadGame")
    InitSnapshots()
    FireTick("Loaded")
EndEvent

Function InitSnapshots()
    Actor p = GetReference() as Actor
    if !p
        return
    endif
    _lastActualWeather = Weather.GetCurrentWeather()
    _lastLocation      = p.GetCurrentLocation()
    Cell pc = p.GetParentCell()
    if pc
        _lastIsInterior = pc.IsInterior()
    else
        _lastIsInterior = False
    endif
EndFunction

; ========= PO3 Events =========
Event OnWeatherChange(Weather akOldWeather, Weather akNewWeather)
    _lastActualWeather = akNewWeather
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
    Cell pc = p.GetParentCell()
    Bool nowInterior = pc && pc.IsInterior()
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
    Cell pc = p.GetParentCell()
    Bool nowInterior = pc && pc.IsInterior()
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