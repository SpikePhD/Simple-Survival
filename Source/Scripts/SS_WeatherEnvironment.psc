Scriptname SS_WeatherEnvironment extends Quest

; ====== Debug / Config ======
bool   Property SS_DEBUG     Auto ; set TRUE in CK to spam logs
Bool   Property DebugLog     = False Auto
String Property ConfigPath   = "Data/SKSE/Plugins/SS_WeatherConfig.json" Auto

; ---------- Build/Version Tag ----------
string Property SS_BUILD_TAG Auto

; ---------- Cached snapshot for re-emit to MCM ----------
Int   _lastSnapshotId = 0
Float _lastDifficulty = 0.0

; ====== Utilities ======
Function Log(String s)
	if DebugLog
		Debug.Trace("[SS_WeatherEnvironment] " + s)
	endif
EndFunction

Float Function ReadCfgFloat(String sectionPath, Float fallback)
	; JsonUtil returns fallback when key is missing; Papyrus floats cannot be None
	return JsonUtil.GetFloatValue(ConfigPath, sectionPath, fallback)
EndFunction

Float Function DefaultClassWeight(Int c)
	; sensible defaults if JSON is missing
	if c == 0
		return 0.0
	elseif c == 1
		return 5.0
	elseif c == 2
		return 15.0
	else
		return 25.0
	endif
EndFunction

Int Function ClampClass(Int c)
	if c < 0
		return 0
	endif
	if c > 3
		return 3
	endif
	return c
EndFunction

Bool Function IsNightNow(Float startHour, Float endHour)
	Float day = Utility.GetCurrentGameTime()
	Float hours = (day - Math.Floor(day)) * 24.0
	if startHour <= endHour
		return (hours >= startHour && hours < endHour)
	else
		return (hours >= startHour || hours < endHour)
	endif
EndFunction

; "Regional" - outgoing/target weather during transitions; fall back to current
Int Function GetRegionalClassification()
	Weather w = Weather.GetOutgoingWeather()
	if w
		return ClampClass(w.GetClassification())
	endif
	w = Weather.GetCurrentWeather()
	if w
		return ClampClass(w.GetClassification())
	endif
	return 0
EndFunction

Event OnInit()
	Log("OnInit")
	RegisterForModEvent("SS_Tick3", "OnTick3")
	RegisterForModEvent("SS_Tick4", "OnTick4")
	RegisterForModEvent("SS_RequestWeatherStatus", "OnRequestStatus")
	if SS_BUILD_TAG == ""
		SS_BUILD_TAG = "Env 2025-10-16.c"
	endif
	Debug.Trace("[SS_WeatherEnvironment] OnInit build=" + SS_BUILD_TAG)
EndEvent

; Handle 3-arg tick (string, float, form)
Event OnTick3(String eventName, String reason, Float numArg, Form sender)
	HandleTick(numArg, sender)
EndEvent

; Handle 4-arg tick (string, string, float, form)
Event OnTick4(String eventName, String reason, Float numArg, Form sender)
	HandleTick(numArg, sender)
EndEvent

Function HandleTick(Float numArg, Form sender)
	if SS_DEBUG
		Debug.Trace("[SS_WeatherEnvironment] OnSSTick numArg=" + numArg + " sender=" + sender)
	endif
	Actor p = Game.GetPlayer()
	if !p
		Log("No player")
		return
	endif

	Int snapshotId = numArg as Int
	Int classRegional = GetRegionalClassification()

	Weather actualW = Weather.GetCurrentWeather()
	Int classActual = 0
	if actualW
		classActual = ClampClass(actualW.GetClassification())
	endif

	Bool isInterior = False
	Cell c = p.GetParentCell()
	if c
		isInterior = c.IsInterior()
	endif

	Float regWeight = ReadCfgFloat("weights.regional." + classRegional, DefaultClassWeight(classRegional))
	Float actWeight = ReadCfgFloat("weights.actual."   + classActual,   DefaultClassWeight(classActual))
	Float wInterior = ReadCfgFloat("weights.interior", 0.0)
	Float wExterior = ReadCfgFloat("weights.exterior", 0.0)

	Float nightStart = ReadCfgFloat("night.startHour", 20.0)
	Float nightEnd   = ReadCfgFloat("night.endHour",   6.0)
	Float nightMul   = ReadCfgFloat("night.multiplier", 1.0)
	if nightMul < 0.0
		nightMul = 0.0 ; avoid negative difficulty flips
	endif

	Float shelter = 0.0
	if isInterior
		shelter = wInterior
	else
		shelter = wExterior
	endif
	Float baseDifficulty = regWeight + actWeight + shelter

	Bool isNight = IsNightNow(nightStart, nightEnd)
	Float finalDifficulty = baseDifficulty
	if isNight
		finalDifficulty = baseDifficulty * nightMul
	endif

	; cache for re-emit
	_lastSnapshotId = snapshotId
	_lastDifficulty = finalDifficulty

	EmitEnvResults(snapshotId, finalDifficulty)
EndFunction

; ========= central emitter (v4 if possible + v3 fallback) =========
Function EmitEnvResults(Int snapshotId, Float difficulty)
	string sid = "" + snapshotId
	; 4-arg channel (when supported)
	int h = ModEvent.Create("SS_WeatherEnvResult4")
	bool okS = False
	bool okF = False
	bool okFm = False
	bool sent4 = False
	if h
		okS = ModEvent.PushString(h, sid)
		okF = ModEvent.PushFloat(h, difficulty)
		okFm = ModEvent.PushForm(h, Self as Form)
		if okS && okF && okFm
			sent4 = ModEvent.Send(h)
		endif
	endif

	; 3-arg fallback for runtimes like yours
	(Self as Form).SendModEvent("SS_WeatherEnvResult3", "", difficulty)

	if SS_DEBUG
		Debug.Trace("[SS_WeatherEnvironment] Emit " + SS_BUILD_TAG + " id=" + sid + " diff=" + difficulty + " okS=" + okS + " okF=" + okF + " okFm=" + okFm + " sent4=" + sent4 + " (also sent EnvResult3 fallback)")
	endif
EndFunction

; ========= respond to MCM status request =========
Event OnRequestStatus(String evn, String detail, Float f, Form sender)
	; Re-emit last known values so the MCM can populate immediately
	EmitEnvResults(_lastSnapshotId, _lastDifficulty)
EndEvent

Event OnPlayerLoadGame()
	Log("OnPlayerLoadGame")
EndEvent