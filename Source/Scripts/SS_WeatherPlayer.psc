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
	Float total = 0.0
	total += SlotBaseBonusIfEquipped(p, "Helmet")
	total += SlotBaseBonusIfEquipped(p, "Armor")
	total += SlotBaseBonusIfEquipped(p, "Boots")
	total += SlotBaseBonusIfEquipped(p, "Bracelets")
	total += SlotBaseBonusIfEquipped(p, "Cloak")
	return total
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
	UnregisterForUpdate()
	if SS_BUILD_TAG == ""
		SS_BUILD_TAG = "Player 2025-10-17.hardMasks"
	endif
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
	_lastWarmth = baseTotal
	if SS_DEBUG
		DumpWornCommonMasks(p)
		Debug.Trace("[SS_WeatherPlayer] (delayed) baseTotal=" + baseTotal + " -> warmth=" + baseTotal)
	endif
	EmitPlayerResults(_delayedSnapshot, baseTotal)
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
	Float warmth    = baseTotal
	_lastSnapshotId = snapshotId
	_lastWarmth     = warmth
	if SS_DEBUG
		DumpWornCommonMasks(p)
		Debug.Trace("[SS_WeatherPlayer] (immediate) baseTotal=" + baseTotal + " -> warmth=" + warmth)
	endif
	EmitPlayerResults(snapshotId, warmth)
	; schedule a delayed re-check to catch late slot swaps
	_delayedSnapshot = snapshotId
	if !_delayedPending
		_delayedPending = True
		RegisterForSingleUpdate(0.30)
	endif
EndFunction