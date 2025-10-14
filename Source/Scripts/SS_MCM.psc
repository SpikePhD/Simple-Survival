Scriptname SS_MCM extends SKI_ConfigBase

; =============================================================
; Simple Survival (SS) — MCM (fixed for SkyUI MCM v4 signatures)
; =============================================================

; =================== Constants ===================
Int Property MAX_ROWS = 64 Auto ; buffer for dynamic lists (mask/keyword)
String Property ConfigPath = "Data/SKSE/Plugins/SS_WeatherConfig.json" Auto

; Page names
String _pageOverview = "Overview"
String _pageWeather  = "Weather"

; Overview cached values (updated via ModEvents)
Float _lastPct = 0.0
Float _lastWarmth = 0.0
Float _lastEnv = 0.0
Int   _lastTier = 0
String _lastReason = ""

; Option IDs (Overview)
Int oidHdrWeather
Int oidWarmth
Int oidEnv
Int oidTier
Int oidPct

; Option IDs (Weather basics)
Int oidHdrWeights
Int oidReg0
Int oidReg1
Int oidReg2
Int oidReg3
Int oidAct0
Int oidAct1
Int oidAct2
Int oidAct3
Int oidInterior
Int oidExterior

Int oidHdrNight
Int oidNightStart
Int oidNightEnd
Int oidNightMul

; Mask bonuses section
Int oidHdrMask
Int oidMaskEnabled
Int oidMaskDedupe
Int oidMaskLen
Int[] oidMaskMask
Int[] oidMaskBonus
Int[] oidMaskLabel

; Keyword bonuses section
Int oidHdrKW
Int oidKWLen
Int[] oidKWEditor
Int[] oidKWBonus

; Footer buttons
Int oidSave
Int oidReload

; Debug
Bool Property DebugLog = False Auto

Function Log(String s)
	if DebugLog
		Debug.Trace("[SS_MCM] " + s)
	endif
EndFunction

; =================== ModEvent listeners ===================
Event OnConfigInit()
	; Register MCM pages
	Pages = new String[2]
	Pages[0] = _pageOverview
	Pages[1] = _pageWeather

	; Listen for results from runtime so Overview can display live values.
	RegisterForModEvent("SS_WeatherTier",       "OnTierPct")       ; numArg = pct (0..100), strArg has id/tier
	RegisterForModEvent("SS_WeatherTierLevel",  "OnTierLevel")     ; numArg = tier (0..5), strArg has id/pct
	RegisterForModEvent("SS_WeatherEnvResult",  "OnEnvResult")     ; numArg = environment value
	RegisterForModEvent("SS_WeatherPlayerResult","OnPlayerResult") ; numArg = player warmth
EndEvent

Event OnTierPct(String evn, String s, Float f, Form sender)
	_lastPct = f
	; Optional: parse tier from s if you want
EndEvent

Event OnTierLevel(String evn, String s, Float f, Form sender)
	_lastTier = f as Int
EndEvent

Event OnEnvResult(String evn, String s, Float f, Form sender)
	_lastEnv = f
EndEvent

Event OnPlayerResult(String evn, String s, Float f, Form sender)
	_lastWarmth = f
EndEvent

; =================== Page builders ===================
Event OnPageReset(String a_page)
	if a_page == _pageOverview
		BuildPageOverview()
	elseif a_page == _pageWeather
		BuildPageWeather()
	endif
EndEvent

Function BuildPageOverview()
	SetCursorFillMode(TOP_TO_BOTTOM)
	AddHeaderOption("Weather")
	; Store IDs to refresh text when the page reopens
	oidWarmth = AddTextOption("Player warmth", F1(_lastWarmth))
	oidEnv    = AddTextOption("Environmental score", F1(_lastEnv))
	oidPct    = AddTextOption("Preparedness", (F0(_lastPct) + "%"))
	oidTier   = AddTextOption("Tier", ("" + _lastTier))
EndFunction

Function BuildPageWeather()
	SetCursorFillMode(TOP_TO_BOTTOM)

	; ===== Weights =====
	AddHeaderOption("Environment Weights")
	oidReg0 = AddSliderOption("Regional Pleasant (0)", GetF("weights.regional.0", 0.0), "{0}")
	oidReg1 = AddSliderOption("Regional Cloudy (1)",  GetF("weights.regional.1", 5.0), "{0}")
	oidReg2 = AddSliderOption("Regional Rainy (2)",   GetF("weights.regional.2", 15.0), "{0}")
	oidReg3 = AddSliderOption("Regional Snow (3)",    GetF("weights.regional.3", 25.0), "{0}")

	oidAct0 = AddSliderOption("Actual Pleasant (0)", GetF("weights.actual.0", 0.0), "{0}")
	oidAct1 = AddSliderOption("Actual Cloudy (1)",  GetF("weights.actual.1", 10.0), "{0}")
	oidAct2 = AddSliderOption("Actual Rainy (2)",   GetF("weights.actual.2", 25.0), "{0}")
	oidAct3 = AddSliderOption("Actual Snow (3)",    GetF("weights.actual.3", 40.0), "{0}")

	oidInterior = AddSliderOption("Interior bonus", GetF("weights.interior", 0.0), "{0}")
	oidExterior = AddSliderOption("Exterior bonus", GetF("weights.exterior", 5.0), "{0}")

	; ===== Night =====
	AddHeaderOption("Night")
	oidNightStart = AddSliderOption("Night start hour", GetF("night.startHour", 20.0), "{1}")
	oidNightEnd   = AddSliderOption("Night end hour",   GetF("night.endHour", 6.0),   "{1}")
	oidNightMul   = AddSliderOption("Night multiplier", GetF("night.multiplier", 1.25), "{2}")

	; ===== Mask bonuses =====
	AddHeaderOption("Mask Bonuses")
	Int maskEnabled = (GetF("player.maskBonuses.enabled", 1.0) >= 0.5) as Int
	oidMaskEnabled = AddToggleOption("Enabled", (maskEnabled == 1))
	Int dedupe = (GetF("player.maskBonuses.dedupeSameForm", 1.0) >= 0.5) as Int
	oidMaskDedupe = AddToggleOption("Dedupe same armor", (dedupe == 1))

	Int mlen = GetI("player.maskBonuses.len", 0)
	if mlen < 0
		mlen = 0
	elseif mlen > MAX_ROWS
		mlen = MAX_ROWS
	endif
	oidMaskLen = AddInputOption("Rows (0.." + MAX_ROWS + ")", "" + mlen)

	; allocate ID arrays once
	if oidMaskMask == None
		oidMaskMask = new Int[64]
		oidMaskBonus = new Int[64]
		oidMaskLabel = new Int[64]
	endif

	Int i = 0
	while i < mlen
		String base = "player.maskBonuses." + i
		Int m = GetI(base + ".mask", 0)
		Float b = GetF(base + ".bonus", 0.0)
		String lab = GetS(base + ".label", "")

		SetCursorPosition(0)
		oidMaskMask[i]  = AddInputOption("Mask #" + i, "" + m)
		SetCursorPosition(1)
		oidMaskBonus[i] = AddSliderOption("Bonus #" + i, b, "{0}")
		SetCursorPosition(2)
		oidMaskLabel[i] = AddInputOption("Label #" + i, lab)

		i = i + 1
	endwhile

	; ===== Keyword bonuses =====
	AddHeaderOption("Keyword Bonuses")
	Int klen = GetI("player.keywordBonuses.len", 0)
	if klen < 0
		klen = 0
	elseif klen > MAX_ROWS
		klen = MAX_ROWS
	endif
	oidKWLen = AddInputOption("Rows (0.." + MAX_ROWS + ")", "" + klen)

	if oidKWEditor == None
		oidKWEditor = new Int[64]
		oidKWBonus  = new Int[64]
	endif

	Int k = 0
	while k < klen
		String kbase = "player.keywordBonuses." + k
		String editorID = GetS(kbase + ".editorID", "")
		Float kb = GetF(kbase + ".bonus", 0.0)

		SetCursorPosition(0)
		oidKWEditor[k] = AddInputOption("EditorID #" + k, editorID)
		SetCursorPosition(1)
		oidKWBonus[k]  = AddSliderOption("Bonus #" + k, kb, "{0}")

		k = k + 1
	endwhile

	; Footer actions
	AddEmptyOption()
	AddTextOption("? Values apply immediately. Use Save to persist.", "")
	AddTextOption("Config file:", ConfigPath)
	AddEmptyOption()
	oidSave   = AddTextOption("[Save]", "Click")
	oidReload = AddTextOption("[Reload]", "Click")
EndFunction

; =================== Option Handlers ===================
Event OnOptionSelect(Int option)
	if option == oidSave
		JsonUtil.Save(ConfigPath)
		Debug.Notification("SS: Config saved")
	elseif option == oidReload
		Debug.Notification("SS: Config reloaded from file")
		ForcePageReset()
	endif
EndEvent

Event OnOptionSliderOpen(Int option)
	Float min = 0.0
	Float max = 100.0
	Float inc = 1.0

	; Weights & general bonuses
	if option == oidReg0 || option == oidReg1 || option == oidReg2 || option == oidReg3 || \
	   option == oidAct0 || option == oidAct1 || option == oidAct2 || option == oidAct3 || \
	   option == oidInterior || option == oidExterior
		min = 0.0
		max = 100.0
		inc = 1.0

	elseif option == oidNightStart || option == oidNightEnd
		min = 0.0
		max = 24.0
		inc = 0.5

	elseif option == oidNightMul
		min = 0.1
		max = 5.0
		inc = 0.05

	else
		Int i = 0
		while i < MAX_ROWS
			if option == oidMaskBonus[i] || option == oidKWBonus[i]
				min = 0.0
				max = 100.0
				inc = 1.0
				i = MAX_ROWS ; break
			endif
			i += 1
		endwhile
	endif

	SetSliderDialogRange(min, max)
	SetSliderDialogInterval(inc)
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
	; Weights (regional/actual)
	if option == oidReg0
		SetF("weights.regional.0", value)
	elseif option == oidReg1
		SetF("weights.regional.1", value)
	elseif option == oidReg2
		SetF("weights.regional.2", value)
	elseif option == oidReg3
		SetF("weights.regional.3", value)
	elseif option == oidAct0
		SetF("weights.actual.0", value)
	elseif option == oidAct1
		SetF("weights.actual.1", value)
	elseif option == oidAct2
		SetF("weights.actual.2", value)
	elseif option == oidAct3
		SetF("weights.actual.3", value)
	elseif option == oidInterior
		SetF("weights.interior", value)
	elseif option == oidExterior
		SetF("weights.exterior", value)

	; Night
	elseif option == oidNightStart
		SetF("night.startHour", value)
	elseif option == oidNightEnd
		SetF("night.endHour", value)
	elseif option == oidNightMul
		SetF("night.multiplier", value)

	; Mask/Keyword rows
	else
		Int i = 0
		while i < MAX_ROWS
			if option == oidMaskBonus[i]
				SetF("player.maskBonuses." + i + ".bonus", value)
				i = MAX_ROWS ; break
			endif
			i = i + 1
		endwhile

		Int k = 0
		while k < MAX_ROWS
			if option == oidKWBonus[k]
				SetF("player.keywordBonuses." + k + ".bonus", value)
				k = MAX_ROWS ; break
			endif
			k = k + 1
		endwhile
	endif
EndEvent

Event OnOptionInputAccept(Int option, String str)
	; Mask/Keyword lengths
	if option == oidMaskLen
		Int mlen = ToIntSafe(str, 0)
		if mlen < 0
			mlen = 0
		elseif mlen > MAX_ROWS
			mlen = MAX_ROWS
		endif
		SetI("player.maskBonuses.len", mlen)
		ForcePageReset()
		return
	endif

	if option == oidKWLen
		Int klen = ToIntSafe(str, 0)
		if klen < 0
			klen = 0
		elseif klen > MAX_ROWS
			klen = MAX_ROWS
		endif
		SetI("player.keywordBonuses.len", klen)
		ForcePageReset()
		return
	endif

	; Mask rows: mask / label
	Int i = 0
	while i < MAX_ROWS
		if option == oidMaskMask[i]
			Int m = ToIntSafe(str, GetI("player.maskBonuses." + i + ".mask", 0))
			SetI("player.maskBonuses." + i + ".mask", m)
			return
		endif
		if option == oidMaskLabel[i]
			SetS("player.maskBonuses." + i + ".label", str)
			return
		endif
		i = i + 1
	endwhile

	; Keywords: editorID
	Int k = 0
	while k < MAX_ROWS
		if option == oidKWEditor[k]
			SetS("player.keywordBonuses." + k + ".editorID", str)
			return
		endif
		k = k + 1
	endwhile
EndEvent

Event OnOptionSelectST(Int option)
	; Not used (using simple Select above)
EndEvent

Event OnOptionToggle(Int option, Bool checked)
	if option == oidMaskEnabled
		SetF("player.maskBonuses.enabled", (checked as Float))
	elseif option == oidMaskDedupe
		SetF("player.maskBonuses.dedupeSameForm", (checked as Float))
	endif
EndEvent

; =================== JsonUtil wrappers ===================
Float Function GetF(String path, Float fallback)
	return JsonUtil.GetFloatValue(ConfigPath, path, fallback)
EndFunction

Int Function GetI(String path, Int fallback)
	Float f = JsonUtil.GetFloatValue(ConfigPath, path, fallback as Float)
	return f as Int
EndFunction

String Function GetS(String path, String fallback)
	return JsonUtil.GetStringValue(ConfigPath, path, fallback)
EndFunction

Function SetF(String path, Float v)
	JsonUtil.SetFloatValue(ConfigPath, path, v)
EndFunction

Function SetI(String path, Int v)
	JsonUtil.SetIntValue(ConfigPath, path, v)
EndFunction

Function SetS(String path, String v)
	JsonUtil.SetStringValue(ConfigPath, path, v)
EndFunction

Int Function ToIntSafe(String s, Int fallback)
	Int sign = 1
	Int i = 0
	if StringUtil.GetLength(s) > 0 && StringUtil.GetNthChar(s, 0) == "-"
		sign = -1
		i = 1
	endif
	Int acc = 0
	Int n = StringUtil.GetLength(s)
	while i < n
		Int d = (StringUtil.GetNthChar(s, i) as Int) - ("0" as Int)
		if d < 0 || d > 9
			return fallback
		endif
		acc = acc * 10 + d
		i = i + 1
	endwhile
	return acc * sign
EndFunction

String Function F0(Float v)
    ; round to 0 decimals
    Float r = Math.Floor(v + 0.5)
    return "" + r
EndFunction

String Function F1(Float v)
    ; round to 1 decimal
    Float r = Math.Floor((v * 10.0) + 0.5) / 10.0
    return "" + r
EndFunction