Scriptname SS_WeatherTiers extends Quest

Bool Property DebugLog = False Auto

; ---------- Build/Version Tag + Debug ----------
bool   Property SS_DEBUG     Auto
string Property SS_BUILD_TAG Auto

; ===== Internal state for the current tick =====
Int   _currentId   = 0
Bool  _haveEnv     = False
Bool  _havePlayer  = False
Float _envVal      = 0.0
Float _playerVal   = 0.0
String _lastReason = ""

; v4-dedup flags (per tick)
Bool _sawEnv4    = False
Bool _sawPlayer4 = False

; ===== Cached outputs for re-emit to MCM =====
Float _lastPct  = 0.0
Int   _lastTier = 0
Int   _lastId   = 0

; ===== Utilities =====
Function Log(String s)
	if DebugLog
		Debug.Trace("[SS_WeatherTiers] " + s)
	endif
EndFunction

Float Function ClampFloat(Float v, Float lo, Float hi)
	Float r = v
	if r < lo
		r = lo
	endif
	if r > hi
		r = hi
	endif
	return r
EndFunction

Int Function ComputeTier(Float pct)
	Int t = 0
	Int ip = Math.Floor(pct + 0.5) as Int ; round instead of truncate
	if ip <= 0
		t = 0
	elseif ip >= 100
		t = 5
	elseif ip >= 75
		t = 4
	elseif ip >= 50
		t = 3
	elseif ip >= 25
		t = 2
	else
		t = 1
	endif
	return t
EndFunction

; ===== Id match helper (for 4-arg events) =====
Bool Function _MatchesCurrentId(String sid)
	if sid == ""
		return True ; allow 3-arg/legacy paths
	endif
	Int incoming = sid as Int
	return incoming == _currentId
EndFunction

Function TryComputeAndEmit()
	if !_haveEnv || !_havePlayer
		if SS_DEBUG
			Debug.Trace("[SS_WeatherTiers] Waiting: env=" + _haveEnv + " player=" + _havePlayer + " id=" + _currentId + " reason=" + _lastReason)
		endif
		return
	endif

	Float pct
	if _envVal <= 0.0
		if _playerVal <= 0.0
			pct = 0.0
		else
			pct = 100.0
		endif
	else
		pct = (_playerVal / _envVal) * 100.0
	endif
	pct = ClampFloat(pct, 0.0, 100.0)

	Int tier = ComputeTier(pct)
	String detailTier  = "id=" + _currentId + ";tier=" + tier + ";reason=" + _lastReason
	String detailLevel = "id=" + _currentId + ";pct=" + pct + ";reason=" + _lastReason

	; cache last results for status re-emit
	_lastPct  = pct
	_lastTier = tier
	_lastId   = _currentId
	if SS_DEBUG
		Debug.Trace("[SS_WeatherTiers] pct=" + pct + " tier=" + tier + " env=" + _envVal + " player=" + _playerVal + " reason=" + _lastReason)
	endif

	EmitTierResults(detailTier, pct, detailLevel, tier)

	_haveEnv = False
	_havePlayer = False
	_sawEnv4 = False
	_sawPlayer4 = False
EndFunction

; ===== Central emitters (push order fixed: String -> Float -> Form) =====
Function EmitTierResults(String detailTier, Float pct, String detailLevel, Int tier)
	; 1) SS_WeatherTier
	Int h1 = ModEvent.Create("SS_WeatherTier")
	if h1
		Bool okS1 = ModEvent.PushString(h1, detailTier)
		Bool okF1 = ModEvent.PushFloat(h1, pct)
		Bool okFm1 = ModEvent.PushForm(h1, Self as Form)
		if okS1 && okF1 && okFm1
			ModEvent.Send(h1)
		elseif okS1 && okF1
			ModEvent.Send(h1)
		endif
	endif
	(Self as Form).SendModEvent("SS_WeatherTier", detailTier, pct)

	; 2) SS_WeatherTierLevel
	Int h2 = ModEvent.Create("SS_WeatherTierLevel")
	if h2
		Bool okS2 = ModEvent.PushString(h2, detailLevel)
		Bool okF2 = ModEvent.PushFloat(h2, tier as Float)
		Bool okFm2 = ModEvent.PushForm(h2, Self as Form)
		if okS2 && okF2 && okFm2
			ModEvent.Send(h2)
		elseif okS2 && okF2
			ModEvent.Send(h2)
		endif
	endif
	(Self as Form).SendModEvent("SS_WeatherTierLevel", detailLevel, tier as Float)
EndFunction

; ===== Lifecycle =====
Event OnInit()
	RegisterForModEvent("SS_Tick3", "OnTick3")
	RegisterForModEvent("SS_Tick4", "OnTick4")
	RegisterForModEvent("SS_WeatherEnvResult3", "OnEnv3")
	RegisterForModEvent("SS_WeatherEnvResult4", "OnEnv4")
	RegisterForModEvent("SS_WeatherPlayerResult3", "OnPlayer3")
	RegisterForModEvent("SS_WeatherPlayerResult4", "OnPlayer4")
	RegisterForModEvent("SS_RequestWeatherStatus", "OnRequestStatus")
	if SS_BUILD_TAG == ""
		SS_BUILD_TAG = "Tiers 2025-10-17.f"
	endif
	Debug.Trace("[SS_WeatherTiers] OnInit build=" + SS_BUILD_TAG)
EndEvent

; ===== Tick Handlers =====
Event OnTick3(String eventName, String reason, Float numArg, Form sender)
	HandleTick(reason, numArg, sender)
EndEvent

Event OnTick4(String eventName, String reason, Float numArg, Form sender)
	HandleTick(reason, numArg, sender)
EndEvent

Function HandleTick(String reason, Float numArg, Form sender)
	_currentId = numArg as Int
	if reason != ""
		_lastReason = reason
	else
		_lastReason = "Tick"
	endif
	_haveEnv = False
	_havePlayer = False
	if SS_DEBUG
		Debug.Trace("[SS_WeatherTiers] HandleTick id=" + _currentId + " reason=" + reason + " sender=" + sender + " (reset env/player flags)")
	endif
EndFunction

; ===== Result Handlers =====
Event OnEnv3(String evn, String detail, Float f, Form sender)
	if _sawEnv4
		if SS_DEBUG
			Debug.Trace("[SS_WeatherTiers] Skipping Env3 (already saw Env4) id=" + _currentId)
		endif
		return
	endif
	_envVal = f
	_haveEnv = True
	if SS_DEBUG
		Debug.Trace("[SS_WeatherTiers] OnEnv3 id=" + _currentId + " f=" + f + " sender=" + sender)
	endif
	TryComputeAndEmit()
EndEvent

Event OnPlayer3(String evn, String detail, Float f, Form sender)
	if _sawPlayer4
		if SS_DEBUG
			Debug.Trace("[SS_WeatherTiers] Skipping Player3 (already saw Player4) id=" + _currentId)
		endif
		return
	endif
	_playerVal = f
	_havePlayer = True
	if SS_DEBUG
		Debug.Trace("[SS_WeatherTiers] OnPlayer3 id=" + _currentId + " f=" + f + " sender=" + sender)
	endif
	TryComputeAndEmit()
EndEvent

Event OnEnv4(String evn, String s, Float f, Form sender)
	if !_MatchesCurrentId(s)
		if SS_DEBUG
			Debug.Trace("[SS_WeatherTiers] Ignored Env id=" + s + " (current=" + _currentId + ")")
		endif
		return
	endif
	_sawEnv4 = True
	OnEnv3(evn, s, f, sender)
EndEvent

Event OnPlayer4(String evn, String s, Float f, Form sender)
	if !_MatchesCurrentId(s)
		if SS_DEBUG
			Debug.Trace("[SS_WeatherTiers] Ignored Player id=" + s + " (current=" + _currentId + ")")
		endif
		return
	endif
	_sawPlayer4 = True
	OnPlayer3(evn, s, f, sender)
EndEvent

; ===== respond to MCM status request (re-emit last known) =====
Event OnRequestStatus(String evn, String detail, Float f, Form sender)
	String detailTier  = "id=" + _lastId + ";tier=" + _lastTier + ";reason=StatusRequest"
	String detailLevel = "id=" + _lastId + ";pct=" + _lastPct  + ";reason=StatusRequest"
	EmitTierResults(detailTier, _lastPct, detailLevel, _lastTier)
EndEvent