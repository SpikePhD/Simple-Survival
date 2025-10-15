Scriptname SS_WeatherTiers extends Quest

Bool Property DebugLog = False Auto

; ---------- Build/Version Tag + Debug ----------
bool   property SS_DEBUG    auto
string property SS_BUILD_TAG auto

; ===== Internal state for the current tick =====
Int   _currentId = 0
Bool  _haveEnv = False
Bool  _havePlayer = False
Float _envVal = 0.0
Float _playerVal = 0.0
String _lastReason = ""

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
	Int ip = pct as Int
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

Function TryComputeAndEmit()
	if !_haveEnv || !_havePlayer
		return
	endif

	Float pct = 0.0
	if _envVal <= 0.0
		pct = 100.0
	else
		pct = (_playerVal / _envVal) * 100.0
	endif
	pct = ClampFloat(pct, 0.0, 100.0)

	Int tier = ComputeTier(pct)

	; 1) SS_WeatherTier
	Int h1 = ModEvent.Create("SS_WeatherTier")
	if h1
		ModEvent.PushFloat(h1, pct)
		ModEvent.PushString(h1, "id=" + _currentId + ";tier=" + tier + ";reason=" + _lastReason)
		ModEvent.PushForm(h1, Self as Form)
		ModEvent.Send(h1)
	endif

	; 2) SS_WeatherTierLevel
	Int h2 = ModEvent.Create("SS_WeatherTierLevel")
	if h2
		ModEvent.PushFloat(h2, tier as Float)
		ModEvent.PushString(h2, "id=" + _currentId + ";pct=" + pct + ";reason=" + _lastReason)
		ModEvent.PushForm(h2, Self as Form)
		ModEvent.Send(h2)
	endif

	_haveEnv = False
	_havePlayer = False
EndFunction

; ===== Lifecycle =====
Event OnInit()
	RegisterForModEvent("SS_Tick3", "OnTick3")
	RegisterForModEvent("SS_Tick4", "OnTick4")
	RegisterForModEvent("SS_WeatherEnvResult3", "OnEnv3")
	RegisterForModEvent("SS_WeatherEnvResult4", "OnEnv4")
	RegisterForModEvent("SS_WeatherPlayerResult3", "OnPlayer3")
	RegisterForModEvent("SS_WeatherPlayerResult4", "OnPlayer4")
	if SS_BUILD_TAG == ""
		SS_BUILD_TAG = "Tiers 2025-10-15.c"
	endif
	Debug.Trace("[SS_WeatherTiers] OnInit build=" + SS_BUILD_TAG)
EndEvent

; ===== Tick Handlers =====
Event OnTick3(String eventName, String reason, Float numArg, Form sender)
	HandleTick(numArg, sender)
EndEvent

Event OnTick4(String eventName, Float numArg, Form sender)
	HandleTick(numArg, sender)
EndEvent

Function HandleTick(Float numArg, Form sender)
	_currentId = numArg as Int
	_lastReason = "Tick"
	_haveEnv = False
	_havePlayer = False
	if SS_DEBUG
		Debug.Trace("[SS_WeatherTiers] HandleTick id=" + _currentId + " sender=" + sender)
	endif
EndFunction

; ===== Result Handlers =====
Event OnEnv3(String evn, Float f, Form sender)
	_envVal = f
	_haveEnv = True
	TryComputeAndEmit()
EndEvent

Event OnPlayer3(String evn, Float f, Form sender)
	_playerVal = f
	_havePlayer = True
	TryComputeAndEmit()
EndEvent

Event OnEnv4(String evn, String s, Float f, Form sender)
	OnEnv3(evn, f, sender)
EndEvent

Event OnPlayer4(String evn, String s, Float f, Form sender)
	OnPlayer3(evn, f, sender)
EndEvent