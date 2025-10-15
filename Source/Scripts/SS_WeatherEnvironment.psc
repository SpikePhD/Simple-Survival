Scriptname SS_WeatherEnvironment extends Quest

Bool   Property DebugLog = False Auto
String Property ConfigPath = "Data/SKSE/Plugins/SS_WeatherConfig.json" Auto

Function Log(String s)
	if DebugLog
		Debug.Trace("[SS_WeatherEnvironment] " + s)
	endif
EndFunction

Float Function ReadCfgFloat(String sectionPath, Float fallback)
	; JsonUtil returns fallback when key is missing; avoid None/NaN comparisons (Papyrus floats cannot be None)
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
		if hours >= startHour && hours < endHour
			return True
		else
			return False
		endif
	else
		if hours >= startHour || hours < endHour
			return True
		else
			return False
		endif
	endif
EndFunction

Int Function GetRegionalClassification()
	; Placeholder logic — Weather.FindWeather(int) is invalid, needs proper detection later
	return 0
EndFunction

Event OnInit()
	Log("OnInit")
	RegisterForModEvent("SS_Tick", "OnSSTick")
EndEvent

Event OnPlayerLoadGame()
	Log("OnPlayerLoadGame")
EndEvent

Event OnSSTick(String eventName, String reason, Float numArg)
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

	Int h = ModEvent.Create("SS_WeatherEnvResult")
	if h
		ModEvent.PushFloat(h, snapshotId as Float)
		ModEvent.PushFloat(h, finalDifficulty)
		ModEvent.PushString(h, "reason=" + reason + "; reg=" + classRegional + "; act=" + classActual + "; interior=" + isInterior)
		ModEvent.Send(h)
	endif

	if DebugLog
		String dbg = "id=" + snapshotId + " reason=" + reason + " regClass=" + classRegional + " actClass=" + classActual + " interior=" + isInterior + " baseDiff=" + baseDifficulty + " night=" + isNight + " mul=" + nightMul + " finalDiff=" + finalDifficulty
		Log(dbg)
	endif
EndEvent