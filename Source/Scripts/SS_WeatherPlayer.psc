Scriptname SS_WeatherPlayer extends Quest

Bool   Property DebugLog = False Auto

; ---------- Build/Version Tag + Debug ----------
bool   Property SS_DEBUG     Auto
string Property SS_BUILD_TAG Auto

; ===== JSON-config path for slots (first pass) =====
String Property SLOT_CONFIG_PATH = "SS/playerwarmth_config.json" AutoReadOnly

; Runtime slot config loaded from JSON (arrays-of-arrays avoided for Papyrus)
Int _slotCount = 0
String[] _slotNames
String[] _slotJsonKeys ; chosen JSON key per slot (handles capitalization variants)
Float[]  _slotBonuses

; === Helpers for JSON-driven slots ===
Bool Function LoadSlotConfig()
    String baseDot = "player.slots."
    String file = SLOT_CONFIG_PATH

    ; Ensure the JSON is loadable and valid
    if !JsonUtil.Load(file)
        if SS_DEBUG
            Debug.Trace("[SS_WeatherPlayer] JsonUtil.Load failed for " + file)
        endif
        _slotCount = 0
        _slotNames = None
        _slotJsonKeys = None
        _slotBonuses = None
        return False
    endif

    Int n = 5 ; Helmet, Armor, Boots, Bracelets, Cloak
    _slotNames    = Utility.CreateStringArray(n)
    _slotJsonKeys = Utility.CreateStringArray(n)
    _slotBonuses  = Utility.CreateFloatArray(n)

    _slotNames[0] = "Helmet"
    _slotNames[1] = "Armor"
    _slotNames[2] = "Boots"
    _slotNames[3] = "Bracelets"
    _slotNames[4] = "Cloak"

    Int i = 0
    while i < n
        String canonical = _slotNames[i]
        String k = canonical ; dot-path, exact casing
        _slotJsonKeys[i] = k

        ; Read bonus via DOT path only (matches your JSON layout)
        Float b = _ReadNumber(file, baseDot + k + ".bonus", 0.0)
        _slotBonuses[i] = b

        if SS_DEBUG
            ; Best-effort mask count for diagnostics (some PapyrusUtil builds accept dot paths)
            Int[] mm = JsonUtil.PathIntElements(file, baseDot + k + ".masks")
            Int mc = 0
            if mm
                mc = mm.Length
            endif
            Debug.Trace("[SS_WeatherPlayer] cfg slot='" + canonical + "' (json='" + k + "') bonus=" + _slotBonuses[i] + " masks=" + mc)
        endif
        i += 1
    endwhile

    _slotCount = n
    if SS_DEBUG
        Debug.Trace("[SS_WeatherPlayer] Loaded slot defs from JSON path=" + file)
    endif
    return True
EndFunction

Bool Function _AnyMaskEquippedFromJson(Actor p, String slotCanonical)
	if !p
		return False
	endif
	Int[] masks = _ResolveMaskArrayFor(slotCanonical)
	if masks && masks.Length > 0
		Int j = 0
		while j < masks.Length
			Int mask = masks[j]
			if mask > 0 && p.GetWornForm(mask)
				if SS_DEBUG
					Debug.Trace("[SS_WeatherPlayer] Mask match slot='" + slotCanonical + "' mask=" + mask)
				endif
				return True
			endif
			j += 1
		endWhile
		if SS_DEBUG
			Debug.Trace("[SS_WeatherPlayer] slot='" + slotCanonical + "' had masks but none are worn")
		endif
		return False
	endif
	; No masks in JSON -> canonical fallback
	return _EquippedByCanonical(p, slotCanonical)
EndFunction

Int[] Function _ResolveMaskArray(String file, String pathDot)
    ; DOT-path only resolution (int -> string aliases -> float)
    Int[] ints = JsonUtil.PathIntElements(file, pathDot)
    if ints && ints.Length > 0
        return _CompactMaskArray(ints)
    endif

    String[] names = JsonUtil.PathStringElements(file, pathDot)
    if names && names.Length > 0
        Int[] fromNames = Utility.CreateIntArray(names.Length)
        Int ni = 0
        while ni < names.Length
            Int maskValue = _MaskAliasToInt(names[ni])
            fromNames[ni] = maskValue
            ni += 1
        endwhile
        return _CompactMaskArray(fromNames)
    endif

    Float[] floats = JsonUtil.PathFloatElements(file, pathDot)
    if floats && floats.Length > 0
        Int[] converted = Utility.CreateIntArray(floats.Length)
        Int fi = 0
        while fi < floats.Length
            Float raw = floats[fi]
            Float rounded = Math.Floor(raw + 0.5)
            Int mask = rounded as Int
            if raw < 0.0 || mask < 0
                mask = 0
            endif
            converted[fi] = mask
            fi += 1
        endwhile
        return _CompactMaskArray(converted)
    endif

    return Utility.CreateIntArray(0)
EndFunction

; Merge canonical+alt mask arrays for a slot. Prefers canonical order, then appends unique alt entries.
Int[] Function _ResolveMaskArrayFor(String slotCanonical)
	EnsureConfigLoaded()
	String k = _Canon(slotCanonical)

	; dot first
	Int[] ints = JsonUtil.PathIntElements(SLOT_CONFIG_PATH, "player.slots." + k + ".masks")
	if ints && ints.Length > 0
		return _CompactMaskArray(ints)
	endif

	; also accept string/numeric forms on dot path
	String[] names = JsonUtil.PathStringElements(SLOT_CONFIG_PATH, "player.slots." + k + ".masks")
	if names && names.Length > 0
		Int[] fromNames = Utility.CreateIntArray(names.Length)
		Int ni = 0
		while ni < names.Length
			fromNames[ni] = _MaskAliasToInt(names[ni])
			ni += 1
		endWhile
		return _CompactMaskArray(fromNames)
	endif

	Float[] floats = JsonUtil.PathFloatElements(SLOT_CONFIG_PATH, "player.slots." + k + ".masks")
	if floats && floats.Length > 0
		Int[] converted = Utility.CreateIntArray(floats.Length)
		Int fi = 0
		while fi < floats.Length
			Float raw = floats[fi]
			converted[fi] = Math.Floor(raw + 0.5) as Int
			fi += 1
		endWhile
		return _CompactMaskArray(converted)
	endif

	; slash fallback (read-only)
	ints = JsonUtil.PathIntElements(SLOT_CONFIG_PATH, "player/slots/" + k + "/masks")
	if ints && ints.Length > 0
		return _CompactMaskArray(ints)
	endif

	return Utility.CreateIntArray(0)
EndFunction

Int[] Function _CompactMaskArray(Int[] raw)
    if !raw
        return Utility.CreateIntArray(0)
    endif
    Int keep = 0
    Int i = 0
    while i < raw.Length
        if raw[i] > 0
            keep += 1
        endif
        i += 1
    endwhile
    if keep <= 0
        return Utility.CreateIntArray(0)
    endif
    if keep == raw.Length
        return raw
    endif
    Int[] trimmed = Utility.CreateIntArray(keep)
    Int t = 0
    i = 0
    while i < raw.Length
        Int mask = raw[i]
        if mask > 0
            trimmed[t] = mask
            t += 1
        endif
        i += 1
    endwhile
    return trimmed
EndFunction

Int Function _MaskAliasToInt(String aliasKey)
    if !aliasKey
        return 0
    endif
    ; accept common tokens and direct numeric strings
    if aliasKey == "Helmet" || aliasKey == "helmet" || aliasKey == "Head" || aliasKey == "head" || aliasKey == "Slot30" || aliasKey == "slot30" || aliasKey == "1"
        return MASK_HELMET
    elseif aliasKey == "HelmetHair" || aliasKey == "helmethair" || aliasKey == "Hair" || aliasKey == "hair" || aliasKey == "2"
        return MASK_HELMET_HAIR
    elseif aliasKey == "Circlet" || aliasKey == "circlet" || aliasKey == "Circ" || aliasKey == "circ" || aliasKey == "4096"
        return MASK_HELMET_CIRC
    elseif aliasKey == "Armor" || aliasKey == "armor" || aliasKey == "Body" || aliasKey == "body" || aliasKey == "Slot32" || aliasKey == "slot32" || aliasKey == "4"
        return MASK_ARMOR
    elseif aliasKey == "Bracelets" || aliasKey == "bracelets" || aliasKey == "Forearms" || aliasKey == "forearms" || aliasKey == "Gauntlets" || aliasKey == "gauntlets" || aliasKey == "16" || aliasKey == "Slot33" || aliasKey == "slot33"
        return MASK_BRACE
    elseif aliasKey == "BraceletsAlt" || aliasKey == "braceletsalt" || aliasKey == "Hands" || aliasKey == "hands" || aliasKey == "GauntletsAlt" || aliasKey == "gauntletsalt" || aliasKey == "8" || aliasKey == "Slot34" || aliasKey == "slot34"
        return MASK_BRACE_ALT
    elseif aliasKey == "Boots" || aliasKey == "boots" || aliasKey == "Feet" || aliasKey == "feet" || aliasKey == "Shoes" || aliasKey == "shoes" || aliasKey == "128" || aliasKey == "Slot37" || aliasKey == "slot37"
        return MASK_BOOTS
    elseif aliasKey == "BootsAlt" || aliasKey == "bootsalt" || aliasKey == "Calves" || aliasKey == "calves" || aliasKey == "Greaves" || aliasKey == "greaves" || aliasKey == "256" || aliasKey == "Slot38" || aliasKey == "slot38"
        return MASK_BOOTS_ALT
    elseif aliasKey == "Cloak" || aliasKey == "cloak" || aliasKey == "Cape" || aliasKey == "cape" || aliasKey == "Back" || aliasKey == "back" || aliasKey == "65536" || aliasKey == "Slot46" || aliasKey == "slot46"
        return MASK_CLOAK
    elseif aliasKey == "CloakAlt" || aliasKey == "cloakalt" || aliasKey == "CapeAlt" || aliasKey == "capealt" || aliasKey == "16384" || aliasKey == "Slot41" || aliasKey == "slot41"
        return MASK_CLOAK_2
    endif
    if SS_DEBUG
        Debug.Trace("[SS_WeatherPlayer] Unknown mask alias '" + aliasKey + "'")
    endif
    return 0
EndFunction
; ========= Cached snapshot for re-emit to MCM =========
Int   _lastSnapshotId = 0
Float _lastWarmth     = 0.0

; ========= Deferred re-check after ticks (covers gear swap window) =========
Bool _delayedPending = False
Int  _delayedSnapshot = 0


Function Log(String s)
	if DebugLog
		Debug.Trace("[SS_WeatherPlayer] " + s)
	endif
EndFunction

; ===== Config loader aligned with Environment script =====
Bool _cfgOk = False

Function EnsureConfigLoaded()
	if _cfgOk
		return
	endif
	Bool ok = JsonUtil.Load(SLOT_CONFIG_PATH) ; "SS/playerwarmth_config.json"
	_cfgOk = ok
	if SS_DEBUG
		Debug.Trace("[SS_WeatherPlayer] EnsureConfigLoaded ok=" + ok + " path=" + SLOT_CONFIG_PATH)
		if !ok
			Debug.Trace("[SS_WeatherPlayer] ERROR: Could not load player slot config at path=" + SLOT_CONFIG_PATH)
		endif
	endif
EndFunction

; Read a number that may be stored as float or int in JSON (slash-path only)
Float Function _ReadNumber(String file, String pathDot, Float fallback)
	; dot path only (PapyrusUtil)
	Float sentinel = -1234567.89
	Float fv = JsonUtil.GetFloatValue(file, pathDot, sentinel)
	if fv != sentinel
		return fv
	endif
	return fallback
EndFunction

Float Function _ReadBonus(String canonical)
	EnsureConfigLoaded()
	String canonKey = _Canon(canonical) ; force canonical keys like "Boots"
	return _ReadNumber(SLOT_CONFIG_PATH, "player.slots." + canonKey + ".bonus", 0.0)
EndFunction

; ===== Slot masks =====

; ---- Key selection helpers (case-hardened without ToLower()) ----
String Function _Canon(String k)
    if k == "Helmet" || k == "helmet"
        return "Helmet"
    elseif k == "Armor" || k == "armor"
        return "Armor"
    elseif k == "Boots" || k == "boots"
        return "Boots"
    elseif k == "Bracelets" || k == "bracelets"
        return "Bracelets"
    elseif k == "Cloak" || k == "cloak"
        return "Cloak"
    endif
    return k
EndFunction

String Function _AltSlotKey(String k)
    ; simple lowercase alias (hardcoded, no ToLower required)
    if k == "Helmet"
        return "helmet"
    elseif k == "Armor"
        return "armor"
    elseif k == "Boots"
        return "boots"
    elseif k == "Bracelets"
        return "bracelets"
    elseif k == "Cloak"
        return "cloak"
    endif
    return ""
EndFunction

Bool Function _KeyHasData(String file, String kname)
	if kname == ""
		return False
	endif
	Float sentinel = -12345.0
	String baseDot = "player.slots." + kname
	Float fb = JsonUtil.GetPathFloatValue(file, baseDot + ".bonus", sentinel)
	if fb != sentinel
		return True
	endif
	Int[] mi = JsonUtil.PathIntElements(file, baseDot + ".masks")
	if mi && mi.Length > 0
		return True
	endif
	Float[] mf = JsonUtil.PathFloatElements(file, baseDot + ".masks")
	if mf && mf.Length > 0
		return True
	endif
	String[] ms = JsonUtil.PathStringElements(file, baseDot + ".masks")
	if ms && ms.Length > 0
		return True
	endif
	return False
EndFunction

String Function _ChooseJsonKey_CanonicalOnly(String file, String canonical)
    ; Force canonical keys exactly (Helmet/Armor/Boots/Bracelets/Cloak)
    return _Canon(canonical)
EndFunction

; ===== Slot masks =====
Int Property MASK_HELMET       = 1     AutoReadOnly ; Head (0x00000001)
Int Property MASK_HELMET_HAIR  = 2     AutoReadOnly ; Hair (0x00000002) - some hoods reserve this
Int Property MASK_HELMET_CIRC  = 4096  AutoReadOnly ; Circlet (0x00001000)
Int Property MASK_ARMOR        = 4     AutoReadOnly ; Body (0x00000004)
Int Property MASK_BRACE        = 16    AutoReadOnly ; Forearms (0x00000010)
Int Property MASK_BRACE_ALT    = 8     AutoReadOnly ; Hands (0x00000008)
Int Property MASK_BOOTS        = 128   AutoReadOnly ; Feet (0x00000080)
Int Property MASK_BOOTS_ALT    = 256   AutoReadOnly ; Calves (0x00000100)
Int Property MASK_CLOAK        = 65536 AutoReadOnly ; Back/Cape (0x00010000)
Int Property MASK_CLOAK_2      = 16384 AutoReadOnly 
; === Canonical occupancy check used when JSON provides no masks ===
Bool Function _EquippedByCanonical(Actor p, String canonical)
    if !p
        return False
    endif
    if canonical == "Helmet"
        if p.GetWornForm(MASK_HELMET) || p.GetWornForm(MASK_HELMET_HAIR) || p.GetWornForm(MASK_HELMET_CIRC)
            return True
        endif
    elseif canonical == "Armor"
        if p.GetWornForm(MASK_ARMOR)
            return True
        endif
    elseif canonical == "Boots"
        if p.GetWornForm(MASK_BOOTS) || p.GetWornForm(MASK_BOOTS_ALT)
            return True
        endif
    elseif canonical == "Bracelets"
        if p.GetWornForm(MASK_BRACE) || p.GetWornForm(MASK_BRACE_ALT)
            return True
        endif
    elseif canonical == "Cloak"
        if p.GetWornForm(MASK_CLOAK) || p.GetWornForm(MASK_CLOAK_2)
            return True
        endif
    endif
    return False
EndFunction

Float Function SumBaseSlots(Actor p)
	if !p
		return 0.0
	endif
	Float total = 0.0

	if _AnyMaskEquippedFromJson(p, "Helmet")
		Float b = _ReadBonus("Helmet")
		if SS_DEBUG && b > 0.0
			Debug.Trace("[SS_WeatherPlayer] +" + b + " from Helmet")
		endif
		total += b
	endif

	if _AnyMaskEquippedFromJson(p, "Armor")
		Float b2 = _ReadBonus("Armor")
		if SS_DEBUG && b2 > 0.0
			Debug.Trace("[SS_WeatherPlayer] +" + b2 + " from Armor")
		endif
		total += b2
	endif

	if _AnyMaskEquippedFromJson(p, "Boots")
		Float b3 = _ReadBonus("Boots")
		if SS_DEBUG && b3 > 0.0
			Debug.Trace("[SS_WeatherPlayer] +" + b3 + " from Boots")
		endif
		total += b3
	endif

	if _AnyMaskEquippedFromJson(p, "Bracelets")
		Float b4 = _ReadBonus("Bracelets")
		if SS_DEBUG && b4 > 0.0
			Debug.Trace("[SS_WeatherPlayer] +" + b4 + " from Bracelets")
		endif
		total += b4
	endif

	if _AnyMaskEquippedFromJson(p, "Cloak")
		Float b5 = _ReadBonus("Cloak")
		if SS_DEBUG && b5 > 0.0
			Debug.Trace("[SS_WeatherPlayer] +" + b5 + " from Cloak")
		endif
		total += b5
	endif

	return total
EndFunction

; --- Stubs for later passes (so this file compiles now) ---
Float Function SumKeywordBonuses(Actor p)
	return 0.0
EndFunction

Float Function SumAmbientBonuses(Actor p)
	return 0.0
EndFunction
; ===== Debug: dump commonly used biped slot masks and the worn forms =====
Function DumpWornCommonMasks(Actor p)
	Int[] masks = new Int[18]
	masks[0] = 1      ; Head
	masks[1] = 2
	masks[2] = 4      ; Body
	masks[3] = 8
	masks[4] = 16     ; Forearms
	masks[5] = 32
	masks[6] = 64
	masks[7] = 128    ; Feet
	masks[8] = 256
	masks[9] = 512
	masks[10] = 1024
	masks[11] = 2048
	masks[12] = 4096
	masks[13] = 8192
	masks[14] = 16384 ; Cloak alt
	masks[15] = 32768
	masks[16] = 65536 ; Cloak/Back
	masks[17] = 131072
	Int i = 0
	while i < masks.Length
		Int m = masks[i]
		Form f = p.GetWornForm(m)
		if f
			String ed = PO3_SKSEFunctions.GetFormEditorID(f)
			Debug.Trace("[SS_WeatherPlayer] WORN mask=" + m + " form=" + f + " edid=" + ed)
		endif
		i = i + 1
	endwhile
EndFunction

; ========= central emitter (v4 if possible + v3 fallback) =========
Function EmitPlayerResults(Int snapshotId, Float warmth)
	string sid = "" + snapshotId
	int h = ModEvent.Create("SS_WeatherPlayerResult4")
	bool okS = False
	bool okF = False
	bool okFm = False
	bool sent4 = False
	if h
		okS = ModEvent.PushString(h, sid)
		okF = ModEvent.PushFloat(h, warmth)
		okFm = ModEvent.PushForm(h, Game.GetPlayer() as Form)
		if okS && okF && okFm
			sent4 = ModEvent.Send(h)
		endif
	endif
	(Game.GetPlayer() as Form).SendModEvent("SS_WeatherPlayerResult3", "", warmth)
	if SS_DEBUG
		Debug.Trace("[SS_WeatherPlayer] Emit " + SS_BUILD_TAG + " id=" + sid + " warmth=" + warmth + " okS=" + okS + " okF=" + okF + " okFm=" + okFm + " sent4=" + sent4 + " (also sent PlayerResult3 fallback)")
	endif
EndFunction

; ========= lifecycle =========
Event OnInit()
	RegisterForModEvent("SS_Tick3", "OnTick3")
	RegisterForModEvent("SS_Tick4", "OnTick4")
	RegisterForModEvent("SS_RequestWeatherStatus", "OnRequestStatus")
	RegisterForModEvent("SS_PlayerConfigChanged", "OnPlayerCfgChanged")
	UnregisterForUpdate()
	if SS_BUILD_TAG == ""
		SS_BUILD_TAG = "Player 2025-10-18.jsonSlots.v3"
	endif
	; Load JSON slot config (slots only in this pass)
	LoadSlotConfig()
	Debug.Trace("[SS_WeatherPlayer] OnInit build=" + SS_BUILD_TAG)
	if DebugLog
		Log("OnInit")
	endif
EndEvent

; respond to MCM status request by re-emitting cached warmth
Event OnRequestStatus(String evn, String detail, Float f, Form sender)
	EmitPlayerResults(_lastSnapshotId, _lastWarmth)
EndEvent

; 3-arg tick: (string, float, form)
Event OnTick3(String eventName, String reason, Float numArg, Form sender)
	HandleTick(numArg, sender)
EndEvent

; 4-arg tick: (string, string, float, form)
Event OnTick4(String eventName, String reason, Float numArg, Form sender)
	HandleTick(numArg, sender)
EndEvent

Event OnUpdate()
	; delayed second pass to catch post-equip state
	_delayedPending = False
	Actor p = Game.GetPlayer()
	if !p
		return
	endif
	Float baseTotal = SumBaseSlots(p)
	Float kwTotal   = SumKeywordBonuses(p)
	Float ambTotal  = SumAmbientBonuses(p)
	_lastWarmth = baseTotal + kwTotal + ambTotal
	if SS_DEBUG
		DumpWornCommonMasks(p)
		Debug.Trace("[SS_WeatherPlayer] (delayed) base=" + baseTotal + " kw=" + kwTotal + " amb=" + ambTotal + " -> warmth=" + _lastWarmth)
	endif
	EmitPlayerResults(_delayedSnapshot, _lastWarmth)
EndEvent

Function HandleTick(Float numArg, Form sender)
	Actor p = Game.GetPlayer()
	if SS_DEBUG
		Debug.Trace("[SS_WeatherPlayer] HandleTick numArg=" + numArg + " sender=" + sender + " p=" + p)
	endif
	if !p
		Log("No player")
		return
	endif
	Int snapshotId = numArg as Int
	Float baseTotal = SumBaseSlots(p)
	Float kwTotal   = SumKeywordBonuses(p)
	Float ambTotal  = SumAmbientBonuses(p)
	Float warmth    = baseTotal + kwTotal + ambTotal
	_lastSnapshotId = snapshotId
	_lastWarmth     = warmth
	if SS_DEBUG
		DumpWornCommonMasks(p)
		Debug.Trace("[SS_WeatherPlayer] (immediate) base=" + baseTotal + " kw=" + kwTotal + " amb=" + ambTotal + " -> warmth=" + warmth)
	endif
	EmitPlayerResults(snapshotId, warmth)
	; schedule a delayed re-check to catch late slot swaps
	_delayedSnapshot = snapshotId
	if !_delayedPending
		_delayedPending = True
		RegisterForSingleUpdate(0.30)
	endif
EndFunction

; react to MCM changes (slot bonus sliders)
Event OnPlayerCfgChanged(String evn, String slotName, Float value, Form sender)
	if SS_DEBUG
		Debug.Trace("[SS_WeatherPlayer] OnPlayerCfgChanged slot='" + slotName + "' value=" + value + " -> reloading slot config")
	endif
	LoadSlotConfig()
	; also recompute immediately so MCM sees new value
	HandleTick(_lastSnapshotId as Float, sender)
EndEvent