Scriptname SS_WeatherTiers extends Quest

Bool Property DebugLog = False Auto

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
	; Mapping per your spec:
	; 0% -> Tier 0
	; >1%..24% -> Tier 1
	; >25%..49% -> Tier 2
	; >50%..74% -> Tier 3
	; >75%..99% -> Tier 4
	; 100% -> Tier 5
	; NOTE: I’ll make inclusive lower-bounds (1,25,50,75) to avoid gaps on exact integers.
	; If you want strict “>” behavior, say so and I’ll switch back.

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
	if !_haveEnv
		return
	endif
	if !_havePlayer
		return
	endif

	Float pct = 0.0

	if _envVal <= 0.0
		; Pleasant environment (no difficulty) -> treat as fully covered
		pct = 100.0
	else
		pct = (_playerVal / _envVal) * 100.0
	endif

	pct = ClampFloat(pct, 0.0, 100.0)

	Int tier = ComputeTier(pct)

	; Emit two events for convenience:
	; 1) SS_WeatherTier: numArg = percentage, strArg = "id=...;tier=..."
	Int h1 = ModEvent.Create("SS_WeatherTier")
	if h1
		ModEvent.PushFloat(h1, pct)
		ModEvent.PushString(h1, "id=" + _currentId + ";tier=" + tier + ";reason=" + _lastReason)
		ModEvent.Send(h1)
	endif

	; 2) SS_WeatherTierLevel: numArg = tier, strArg = "id=...;pct=..."
	Int h2 = ModEvent.Create("SS_WeatherTierLevel")
	if h2
		ModEvent.PushFloat(h2, tier as Float)
		ModEvent.PushString(h2, "id=" + _currentId + ";pct=" + pct + ";reason=" + _lastReason)
		ModEvent.Send(h2)
	endif

	if DebugLog
		Log("id=" + _currentId + " reason=" + _lastReason + " env=" + _envVal + " player=" + _playerVal + " pct=" + pct + " tier=" + tier)
	endif

	; Reset “have” flags for the next tick
	_haveEnv = False
	_havePlayer = False
EndFunction

; ===== Lifecycle =====
Event OnInit()
	RegisterForModEvent("SS_WeatherTick", "OnSSTick")
	RegisterForModEvent("SS_WeatherEnvResult", "OnEnv")
	RegisterForModEvent("SS_WeatherPlayerResult", "OnPlayer")
	if DebugLog
		Log("OnInit")
	endif
EndEvent

Event OnPlayerLoadGame()
	if DebugLog
		Log("OnPlayerLoadGame")
	endif
EndEvent

; ===== Event handlers =====
Event OnSSTick(String eventName, String reason, Float numArg, Form sender)
	_currentId = numArg as Int
	_lastReason = reason
	_haveEnv = False
	_havePlayer = False

	if DebugLog
		Log("Tick id=" + _currentId + " reason=" + reason)
	endif
EndEvent

Event OnEnv(String eventName, String s, Float f, Form sender)
	; We assume f is the environment difficulty (finalDifficulty)
	_envVal = f
	_haveEnv = True

	if DebugLog
		Log("EnvResult id=" + _currentId + " env=" + _envVal + " info=" + s)
	endif

	TryComputeAndEmit()
EndEvent

Event OnPlayer(String eventName, String s, Float f, Form sender)
	; We assume f is the player warmth
	_playerVal = f
	_havePlayer = True

	if DebugLog
		Log("PlayerResult id=" + _currentId + " player=" + _playerVal + " info=" + s)
	endif

	TryComputeAndEmit()
EndEvent