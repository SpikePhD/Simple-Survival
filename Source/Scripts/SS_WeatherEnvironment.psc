Scriptname SS_WeatherEnvironment extends Quest

Bool   Property DebugLog = False Auto
String Property ConfigPath = "Data/SKSE/Plugins/SS_WeatherConfig.json" Auto

Function Log(String s)
	if DebugLog
		Debug.Trace("[SS_WeatherEnvironment] " + s)
	endif
EndFunction

Float Function ReadCfgFloat(String sectionPath, Float fallback)
	Float v = JsonUtil.GetFloatValue(ConfigPath, sectionPath, fallback)
	return v
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

; Determine a single "regional classification" (0..3) by probing
; which classifications have a valid regional weather template.
; Prefers more severe: 3(Snow) > 2(Rain) > 1(Cloudy) > 0(Pleasant).
Int Function GetRegionalClassification()
	Weather w3 = Weather.FindWeather(3)
	if w3
		return 3
	endif
	Weather w2 = Weather.FindWeather(2)
	if w2
		return 2
	endif
	Weather w1 = Weather.FindWeather(1)
	if w1
		return 1
	endif
	return 0
EndFunction

Event OnInit()
	Log("OnInit")
	RegisterForModEvent("SS_WeatherTick", "OnSSTick")
EndEvent

Event OnPlayerLoadGame()
	Log("OnPlayerLoadGame")
EndEvent

Event OnSSTick(String eventName, String reason, Float numArg, Form sender)
	Actor p = Game.GetPlayer()
	if !p
		Log("No player")
		return
	endif

	; NEW: read snapshot id from the tick
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

	; NEW: include snapshotId as first float, then the score
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