Scriptname SS_WeatherPlayer extends Quest

Bool   Property DebugLog = False Auto

Float Property BONUS_HELMET    = 20.0 AutoReadOnly
Float Property BONUS_ARMOR     = 50.0 AutoReadOnly
Float Property BONUS_BOOTS     = 25.0 AutoReadOnly
Float Property BONUS_BRACELETS = 10.0 AutoReadOnly
Float Property BONUS_CLOAK     = 15.0 AutoReadOnly

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
    String base = "player/slots"
    String file = SLOT_CONFIG_PATH

    ; Ensure the JSON is loadable and valid
    if !JsonUtil.Load(file)
        if SS_DEBUG
            Debug.Trace("[SS_WeatherPlayer] JsonUtil.Load failed for " + file)
        endif
        return False
    endif
    if !JsonUtil.IsGood(file)
        if SS_DEBUG
            Debug.Trace("[SS_WeatherPlayer] JSON parse errors: " + JsonUtil.GetErrors(file))
        endif
        ; keep going but values may be defaults
    endif

    Int n = 10 ; Helmet, Armor, Boots, Bracelets, Cloak, Accessory, Extra1..Extra3, Extra4(reserved)
    _slotNames    = Utility.CreateStringArray(n)
    _slotJsonKeys = Utility.CreateStringArray(n)
    _slotBonuses  = Utility.CreateFloatArray(n)

    _slotNames[0] = "Helmet"
    _slotNames[1] = "Armor"
    _slotNames[2] = "Boots"
    _slotNames[3] = "Bracelets"
    _slotNames[4] = "Cloak"
    _slotNames[5] = "Accessory"
    _slotNames[6] = "Extra1"
    _slotNames[7] = "Extra2"
    _slotNames[8] = "Extra3"
    _slotNames[9] = "Extra4"

    Int i = 0
    while i < n
        String canonical = _slotNames[i]
        String k = _ChooseJsonKey(file, canonical)
        if k == ""
            k = canonical
        endif
        _slotJsonKeys[i] = k

        String p = base + "/" + k + "/bonus"
        _slotBonuses[i] = JsonUtil.GetPathFloatValue(file, p, 0.0)
        if SS_DEBUG
            Int[] mm = JsonUtil.PathIntElements(file, base + "/" + k + "/masks")
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

Bool Function _AnyMaskEquippedFromJson(Actor p, String slotName)
    if !p
        return False
    endif
    String file = SLOT_CONFIG_PATH
    String base = "player/slots/"

    ; try chosen key, canonical, and lowercase alias
    String canonical = _Canon(slotName)
    String k1 = slotName
    String k2 = canonical
    String k3 = _AltSlotKey(canonical)

    Int i = 0
    while i < 3
        String k = k1
        if i == 1
            k = k2
        elseif i == 2
            k = k3
        endif
        if k != ""
            String path = base + k + "/masks"
            Int[] masks = _ResolveMaskArray(file, path)
            if masks && masks.Length > 0
                Int j = 0
                while j < masks.Length
                    Int mask = masks[j]
                    if mask > 0
                        Form f = p.GetWornForm(mask)
                        if f
                            if SS_DEBUG
                                Debug.Trace("[SS_WeatherPlayer] Mask match slot='" + canonical + "' (json='" + k + "') mask=" + mask + " form=" + f + " edid=" + PO3_SKSEFunctions.GetFormEditorID(f))
                            endif
                            return True
                        endif
                    elseif SS_DEBUG
                        Debug.Trace("[SS_WeatherPlayer] Ignoring non-positive mask value=" + mask + " at path=" + path)
                    endif
                    j += 1
                endwhile
                if SS_DEBUG
                    Debug.Trace("[SS_WeatherPlayer] slot='" + canonical + "' (json='" + k + "') had masks but none are worn")
                endif
            else
                if SS_DEBUG
                    Debug.Trace("[SS_WeatherPlayer] No masks at path=" + path)
                endif
            endif
        endif
        i += 1
    endwhile
    return False
EndFunction

Int[] Function _ResolveMaskArray(String file, String path)
    Int[] ints = JsonUtil.PathIntElements(file, path)
    if ints && ints.Length > 0
        return _CompactMaskArray(ints)
    endif

    String[] names = JsonUtil.PathStringElements(file, path)
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

    Float[] floats = JsonUtil.PathFloatElements(file, path)
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

    return None
EndFunction

Int[] Function _CompactMaskArray(Int[] raw)
    if !raw
        return None
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
        return None
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
    ; consider either a bonus value or a non-empty masks array as presence
    Int ib = JsonUtil.GetPathIntValue(file, "player/slots/" + kname + "/bonus", -12345)
    Float fb = JsonUtil.GetPathFloatValue(file, "player/slots/" + kname + "/bonus", -12345.0)
    Int[] mm = JsonUtil.PathIntElements(file, "player/slots/" + kname + "/masks")
    Bool hasB = (ib != -12345) || (fb != -12345.0)
    return hasB || (mm && mm.Length > 0)
EndFunction

String Function _ChooseJsonKey(String file, String canonical)
    String c = _Canon(canonical)
    if _KeyHasData(file, c)
        return c
    endif
    String alt = _AltSlotKey(canonical)
    if _KeyHasData(file, alt)
        return alt
    endif
    return c
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
Int Property MASK_CLOAK_2      = 16384 AutoReadOnly ; Alt cloak (0x00004000)

Float Function SlotBaseBonusIfEquipped(Actor p, String slotKey)
	Float bonus = 0.0
	Int maskPrimary = 0
	Int maskSecondary = 0
	Int maskTertiary = 0
	if slotKey == "Helmet"
		bonus = BONUS_HELMET
		maskPrimary = MASK_HELMET
		maskSecondary = MASK_HELMET_HAIR
		maskTertiary = MASK_HELMET_CIRC
	elseif slotKey == "Armor"
		bonus = BONUS_ARMOR
		maskPrimary = MASK_ARMOR
	elseif slotKey == "Boots"
		bonus = BONUS_BOOTS
		maskPrimary = MASK_BOOTS
		maskSecondary = MASK_BOOTS_ALT
	elseif slotKey == "Bracelets"
		bonus = BONUS_BRACELETS
		maskPrimary = MASK_BRACE
		maskSecondary = MASK_BRACE_ALT
	elseif slotKey == "Cloak"
		bonus = BONUS_CLOAK
		maskPrimary = MASK_CLOAK
		maskSecondary = MASK_CLOAK_2
	endif
	if bonus <= 0.0
		return 0.0
	endif
	Form equippedForm = None
	String editorId = ""
	if maskPrimary > 0
		equippedForm = p.GetWornForm(maskPrimary)
		if equippedForm
			if SS_DEBUG
				editorId = PO3_SKSEFunctions.GetFormEditorID(equippedForm)
				Debug.Trace("[SS_WeatherPlayer] +" + bonus + " from slot=" + slotKey + " form=" + equippedForm + " edid=" + editorId)
			endif
			return bonus
		endif
	endif
	if maskSecondary > 0
		equippedForm = p.GetWornForm(maskSecondary)
		if equippedForm
			if SS_DEBUG
				editorId = PO3_SKSEFunctions.GetFormEditorID(equippedForm)
				Debug.Trace("[SS_WeatherPlayer] +" + bonus + " from slot=" + slotKey + " (alt mask) form=" + equippedForm + " edid=" + editorId)
			endif
			return bonus
		endif
	endif
	if maskTertiary > 0
		equippedForm = p.GetWornForm(maskTertiary)
		if equippedForm
			if SS_DEBUG
				editorId = PO3_SKSEFunctions.GetFormEditorID(equippedForm)
				Debug.Trace("[SS_WeatherPlayer] +" + bonus + " from slot=" + slotKey + " (alt mask 3) form=" + equippedForm + " edid=" + editorId)
			endif
			return bonus
		endif
	endif
	if SS_DEBUG
		Debug.Trace("[SS_WeatherPlayer] slot=" + slotKey + " not equipped")
	endif
	return 0.0
EndFunction

Float Function SumBaseSlots(Actor p)
    ; If JSON-driven slots are loaded, use them. Otherwise fall back to hardcoded slot scan.
    if _slotCount > 0 && _slotNames
        Float total = 0.0
        Int i = 0
        while i < _slotCount
            Float b = _slotBonuses[i]
            String keyForMasks = _slotJsonKeys[i]
            if keyForMasks == ""
                keyForMasks = _slotNames[i]
            endif
            if b > 0.0 && _AnyMaskEquippedFromJson(p, keyForMasks)
                if SS_DEBUG
                    Debug.Trace("[SS_WeatherPlayer] +" + b + " from slot=" + _slotNames[i] + " (json='" + keyForMasks + "')")
                endif
                total += b
            endif
            i += 1
        endwhile
        return total
    endif
    ; --- Fallback to previous hardcoded behavior ---
    Float totalFallback = 0.0
    totalFallback += SlotBaseBonusIfEquipped(p, "Helmet")
    totalFallback += SlotBaseBonusIfEquipped(p, "Armor")
    totalFallback += SlotBaseBonusIfEquipped(p, "Boots")
    totalFallback += SlotBaseBonusIfEquipped(p, "Bracelets")
    totalFallback += SlotBaseBonusIfEquipped(p, "Cloak")
    return totalFallback
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
		SS_BUILD_TAG = "Player 2025-10-18.jsonSlots.v2"
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
