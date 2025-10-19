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
Weather  _lastRegionalWeather
Actor    _aliasActor

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
        SS_BUILD_TAG = "Tick 2025-10-17.d"
    endif
    Debug.Trace("[SS_WeatherTick] OnInit build=" + SS_BUILD_TAG)

    ; cache the bound alias actor for easier debugging
    _aliasActor = GetReference() as Actor
    if SS_DEBUG
        Debug.Trace("[SS_WeatherTick] Alias=" + _aliasActor)
    endif

    Log("OnInit")
    InitSnapshots()

    if SS_DEBUG
        Debug.Trace("[SS_WeatherTick] Initial regional=" + _lastRegionalWeather + " actual=" + _lastActualWeather)
    endif

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
    _lastRegionalWeather = GetRegionalWeatherSnapshot()
    _lastLocation      = p.GetCurrentLocation()
    Cell pc = p.GetParentCell()
    if pc
        _lastIsInterior = pc.IsInterior()
    else
        _lastIsInterior = False
    endif
EndFunction

Weather Function GetRegionalWeatherSnapshot()
    Weather w = Weather.GetOutgoingWeather()
    if !w
        w = Weather.GetCurrentWeather()
    endif
    return w
EndFunction

Function FireRegionalIfChanged(String reason)
    Weather current = GetRegionalWeatherSnapshot()
    if current != _lastRegionalWeather
        _lastRegionalWeather = current
        if SS_DEBUG
            Debug.Trace("[SS_WeatherTick] Regional weather changed -> FireTick(" + reason + ")")
        endif
        FireTick(reason)
    endif
EndFunction

Function UpdateInteriorStateAndFire()
    Actor p = GetReference() as Actor
    if !p
        return
    endif
    Cell pc = p.GetParentCell()
    Bool nowInterior = False
    if pc
        nowInterior = pc.IsInterior()
    endif
    if nowInterior != _lastIsInterior
        _lastIsInterior = nowInterior
        if nowInterior
            FireTick("TransitionToInterior")
        else
            FireTick("TransitionToExterior")
        endif
    endif
    FireRegionalIfChanged("RegionalWeatherChanged")
EndFunction

; ========= PO3 Events =========
Event OnWeatherChange(Weather akOldWeather, Weather akNewWeather)
    _lastActualWeather = akNewWeather
    FireRegionalIfChanged("RegionalWeatherChanged")
    FireTick("ActualWeatherChanged")
EndEvent

Event OnPlayerFastTravelEnd(float afTravelGameTimeHours)
    FireRegionalIfChanged("RegionalWeatherChanged")
    FireTick("FastTravelEnd", afTravelGameTimeHours)
EndEvent

Event OnCellFullyLoaded(Cell akCell)
    UpdateInteriorStateAndFire()
EndEvent

; ========= Vanilla Events (no polling) =========
Event OnLocationChange(Location akOldLoc, Location akNewLoc)
    _lastLocation = akNewLoc
    FireRegionalIfChanged("RegionalWeatherChanged")
    FireTick("LocationChanged")
EndEvent

Event OnCellLoad()
    UpdateInteriorStateAndFire()
EndEvent

; Equip/Unequip (player-only)
Event OnObjectEquipped(Form akBaseObject, ObjectReference akRef)
    ; Fire immediately (akRef may be None for non-persistent gear, do not gate on equality)
    FireTick("Equipped")
    ; Fire a delayed tick to catch post-swap state
    RegisterForSingleUpdate(0.50)
EndEvent

Event OnObjectUnequipped(Form akBaseObject, ObjectReference akRef)
    FireTick("Unequipped")
    RegisterForSingleUpdate(0.50)
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

Event OnUpdate()
    ; delayed follow-up for equip/unequip
    FireTick("EquipDelayed")
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