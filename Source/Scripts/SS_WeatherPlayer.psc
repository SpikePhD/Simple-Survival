Scriptname SS_WeatherPlayer extends Quest

Bool   Property DebugLog = False Auto
String Property ConfigPath = "Data/SKSE/Plugins/SS_WeatherConfig.json" Auto

; ---------- Build/Version Tag + Debug ----------
bool   Property SS_DEBUG     Auto
string Property SS_BUILD_TAG Auto

; ========= Cached snapshot for re-emit to MCM =========
Int   _lastSnapshotId = 0
Float _lastWarmth     = 0.0

Function Log(String s)
	if DebugLog
		Debug.Trace("[SS_WeatherPlayer] " + s)
	endif
EndFunction

Float Function ReadCfgFloat(String path, Float fallback)
	return JsonUtil.GetFloatValue(ConfigPath, path, fallback)
EndFunction

Int Function ReadCfgInt(String path, Int fallback)
	Float f = JsonUtil.GetFloatValue(ConfigPath, path, fallback as Float)
	return f as Int
EndFunction

String Function ReadCfgString(String path, String fallback)
	return JsonUtil.GetStringValue(ConfigPath, path, fallback)
EndFunction

; ===== Slots-only base values =====
; Reads up to 3 alternative masks for a slot and reports if anything is worn
Bool Function SlotEquipped(Actor p, String basePath)
	Int m1 = ReadCfgInt(basePath + ".mask", 0)
	Int m2 = ReadCfgInt(basePath + ".mask2", 0)
	Int m3 = ReadCfgInt(basePath + ".mask3", 0)
	Form f
	if m1 > 0
		f = p.GetWornForm(m1)
		if f
			if SS_DEBUG
				String ed = PO3_SKSEFunctions.GetFormEditorID(f)
				Debug.Trace("[SS_WeatherPlayer] " + basePath + " matched mask m1=" + m1 + " form=" + f + " edid=" + ed)
			endif
			return True
		endif
	endif
	if m2 > 0
		f = p.GetWornForm(m2)
		if f
			if SS_DEBUG
				String ed2 = PO3_SKSEFunctions.GetFormEditorID(f)
				Debug.Trace("[SS_WeatherPlayer] " + basePath + " matched mask m2=" + m2 + " form=" + f + " edid=" + ed2)
			endif
			return True
		endif
	endif
	if m3 > 0
		f = p.GetWornForm(m3)
		if f
			if SS_DEBUG
				String ed3 = PO3_SKSEFunctions.GetFormEditorID(f)
				Debug.Trace("[SS_WeatherPlayer] " + basePath + " matched mask m3=" + m3 + " form=" + f + " edid=" + ed3)
			endif
			return True
		endif
	endif
	return False
EndFunction

Float Function SlotBaseBonusIfEquipped(Actor p, String slotKey)
	String base = "player.slots." + slotKey
	Float bonus = ReadCfgFloat(base + ".bonus", 0.0)
	if bonus <= 0.0
		return 0.0
	endif
	if SlotEquipped(p, base)
		if SS_DEBUG
			Debug.Trace("[SS_WeatherPlayer] slot=" + slotKey + " equipped ? +" + bonus)
		endif
		return bonus
	endif
	if SS_DEBUG
		Debug.Trace("[SS_WeatherPlayer] slot=" + slotKey + " not equipped")
	endif
	return 0.0
EndFunction

Float Function SumBaseSlots(Actor p)
	Float total = 0.0
	; required keys in JSON: helmet, armor, boots, bracelets, cloak
	total += SlotBaseBonusIfEquipped(p, "helmet")
	total += SlotBaseBonusIfEquipped(p, "armor")
	total += SlotBaseBonusIfEquipped(p, "boots")
	total += SlotBaseBonusIfEquipped(p, "bracelets")
	total += SlotBaseBonusIfEquipped(p, "cloak")
	return total
EndFunction

; ===== Keyword bonuses (kept but optional; can be set to zero in JSON) =====
Int Function GetKeywordBonusCount()
	Int n = ReadCfgInt("player.keywordBonuses.len", 0)
	if n < 0
		return 0
	endif
	return n
EndFunction

Keyword Function ResolveKeywordFromJsonIndex(Int i)
	String base = "player.keywordBonuses." + i
	String editorID = ReadCfgString(base + ".editorID", "")
	if editorID != ""
		Form fEd = PO3_SKSEFunctions.GetFormFromEditorID(editorID)
		if fEd
			return fEd as Keyword
		endif
	endif
	String file = ReadCfgString(base + ".file", "")
	Int idDec = ReadCfgInt(base + ".idDec", 0)
	if file != "" && idDec > 0
		Form f = Game.GetFormFromFile(idDec, file)
		if f
			return f as Keyword
		endif
	endif
	return None
EndFunction

Float Function GetKeywordBonusesFor(Armor a)
	if !a
		return 0.0
	endif
	Int count = GetKeywordBonusCount()
	if count <= 0
		return 0.0
	endif
	Float total = 0.0
	Int i = 0
	while i < count
		Keyword k = ResolveKeywordFromJsonIndex(i)
		if k && a.HasKeyword(k)
			total += ReadCfgFloat("player.keywordBonuses." + i + ".bonus", 0.0)
		endif
		i = i + 1
	endwhile
	return total
EndFunction

Float Function SumKeywordBonuses(Actor p)
	; inspect all five slots for an Armor and add keyword bonuses
	Float total = 0.0
	; helmet
	Int m = ReadCfgInt("player.slots.helmet.mask", 0)
	if m > 0
		Armor a = p.GetWornForm(m) as Armor
		if a
			total += GetKeywordBonusesFor(a)
		endif
	endif
	; armor
	m = ReadCfgInt("player.slots.armor.mask", 0)
	if m > 0
		Armor a2 = p.GetWornForm(m) as Armor
		if a2
			total += GetKeywordBonusesFor(a2)
		endif
	endif
	; boots
	m = ReadCfgInt("player.slots.boots.mask", 0)
	if m > 0
		Armor a3 = p.GetWornForm(m) as Armor
		if a3
			total += GetKeywordBonusesFor(a3)
		endif
	endif
	; bracelets
	m = ReadCfgInt("player.slots.bracelets.mask", 0)
	if m > 0
		Armor a4 = p.GetWornForm(m) as Armor
		if a4
			total += GetKeywordBonusesFor(a4)
		endif
	endif
	; cloak (check up to 3 masks for keywords too)
	Int c1 = ReadCfgInt("player.slots.cloak.mask", 0)
	Int c2 = ReadCfgInt("player.slots.cloak.mask2", 0)
	Int c3 = ReadCfgInt("player.slots.cloak.mask3", 0)
	Armor ac
	if c1 > 0
		ac = p.GetWornForm(c1) as Armor
		if ac
			total += GetKeywordBonusesFor(ac)
		endif
	endif
	if c2 > 0
		ac = p.GetWornForm(c2) as Armor
		if ac
			total += GetKeywordBonusesFor(ac)
		endif
	endif
	if c3 > 0
		ac = p.GetWornForm(c3) as Armor
		if ac
			total += GetKeywordBonusesFor(ac)
		endif
	endif
	return total
EndFunction

; ===== Debug: dump commonly used biped slot masks and the worn forms =====
Function DumpWornCommonMasks(Actor p)
	Int[] masks = new Int[18]
	masks[0] = 1      ; Head
	masks[1] = 2
	masks[2] = 4      ; Body
	masks[3] = 8
	masks[4] = 16     ; Hands/Forearms
	masks[5] = 32
	masks[6] = 64
	masks[7] = 128    ; Feet
	masks[8] = 256
	masks[9] = 512
	masks[10] = 1024
	masks[11] = 2048
	masks[12] = 4096
	masks[13] = 8192
	masks[14] = 16384 ; Cloak alt in some mods
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
	if SS_BUILD_TAG == ""
		SS_BUILD_TAG = "Player 2025-10-17.a"
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
	Float warmth = 0.0
	; 1) base values from slots
	Float baseTotal = SumBaseSlots(p)
	; 2) optional keyword bonuses (can be all zeros in JSON)
	Float kwTotal = SumKeywordBonuses(p)
	warmth = baseTotal + kwTotal

	_lastSnapshotId = snapshotId
	_lastWarmth     = warmth

	if SS_DEBUG
		DumpWornCommonMasks(p)
		Debug.Trace("[SS_WeatherPlayer] baseTotal=" + baseTotal + " kwTotal=" + kwTotal + " -> warmth=" + warmth)
	endif

	EmitPlayerResults(snapshotId, warmth)
EndFunction