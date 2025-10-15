Scriptname SS_WeatherEnvironment extends Quest

Bool   Property DebugLog = False Auto
String Property ConfigPath = "Data/SKSE/Plugins/SS_WeatherConfig.json" Auto

Function Log(String s)
	if DebugLog
		Debug.Trace("[SS_WeatherEnvironment] " + s)
	endif
EndFunction

Float Function ReadCfgFloat(String sectionPath, Float fallback)
	; JsonUtil returns fallback when key is missing; Papyrus floats cannot be None
	return JsonUtil.GetFloatValue(ConfigPath, sectionPath, fallback)
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

; "Regional" ˜ outgoing/target weather during transitions; fall back to current
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
	RegisterForModEvent("SS_Tick", "OnSSTick")
EndEvent

Event OnPlayerLoadGame()
	Log("OnPlayerLoadGame")
EndEvent

Event OnSSTick(String eventName, String reason, Float numArg, Form sender)
	Debug.Trace("[SS_WeatherEnvironment] OnSSTick reason=" + reason)
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

	Float regWeight = ReadCfgFloat("weights.regional." + classRegional, 0.0)
	Float actWeight = ReadCfgFloat("weights.actual."   + classActual,   0.0)
	Float wInterior = ReadCfgFloat("weights.interior", 0.0)
	Float wExterior = ReadCfgFloat("weights.exterior", 0.0)

	Float nightStart = ReadCfgFloat("night.startHour", 20.0)
	Float nightEnd   = ReadCfgFloat("night.endHour",   6.0)
	Float nightMul   = ReadCfgFloat("night.multiplier", 1.0)

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

	; ==== FIXED: emit (string, float, form) in that order ====
	Int h = ModEvent.Create("SS_WeatherEnvResult")
	if h
		String info = "id=" + snapshotId + ";reason=" + reason + ";reg=" + classRegional + ";act=" + classActual + ";interior=" + isInterior
		ModEvent.PushString(h, info)                    ; strArg
		ModEvent.PushFloat(h, finalDifficulty)          ; numArg
		ModEvent.PushForm(h, Game.GetPlayer() as Form)  ; sender
		ModEvent.Send(h)
		if DebugLog
			Log("Emit SS_WeatherEnvResult id=" + snapshotId + " diff=" + finalDifficulty)
		endif
	endif
EndEvent