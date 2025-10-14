Scriptname SS_WeatherPlayer extends Quest

Bool   Property DebugLog = False Auto
String Property ConfigPath = "Data/SKSE/Plugins/SS_WeatherConfig.json" Auto

Function Log(String s)
	if DebugLog
		Debug.Trace("[SS_WeatherPlayer] " + s)
	endif
EndFunction

; ===== JSON helpers =====
Float Function ReadCfgFloat(String path, Float fallback)
	Float v = JsonUtil.GetFloatValue(ConfigPath, path, fallback)
	return v
EndFunction

Int Function ReadCfgInt(String path, Int fallback)
	Float f = JsonUtil.GetFloatValue(ConfigPath, path, fallback as Float)
	Int v = f as Int
	return v
EndFunction

String Function ReadCfgString(String path, String fallback)
	String s = JsonUtil.GetStringValue(ConfigPath, path, fallback)
	return s
EndFunction

Int Function CollectWornArmorsFromMaskList(Actor p, Armor[] outArmors)
	if !p
		return 0
	endif

	Int n = ReadCfgInt("player.maskBonuses.len", 0)
	if n <= 0
		return 0
	endif

	Bool dedupe = False
	Float fdd = JsonUtil.GetFloatValue(ConfigPath, "player.maskBonuses.dedupeSameForm", 1.0)
	if fdd >= 0.5
		dedupe = True
	endif

	Int outCount = 0
	Int i = 0
	while i < n
		String base = "player.maskBonuses." + i
		Int mask = ReadCfgInt(base + ".mask", 0)
		if mask > 0
			Form f = p.GetWornForm(mask)
			if f
				Armor a = f as Armor
				if a
					Bool already = False
					if dedupe
						Int j = 0
						while j < outCount
							if outArmors[j] == a
								already = True
							endif
							j = j + 1
						endwhile
					endif
					if !already
						outArmors[outCount] = a
						outCount = outCount + 1
					endif
				endif
			endif
		endif
		i = i + 1
	endwhile

	return outCount
EndFunction

; ===== Weight class helpers (name-proof) =====
Float Function GetWeightClassBonus(Armor a)
	if !a
		return 0.0
	endif

	; Clothing checks (SKSE helpers)
	Bool isCloth = False
	if a.IsClothingHead()
		isCloth = True
	endif
	if a.IsClothingBody()
		isCloth = True
	endif
	if a.IsClothingHands()
		isCloth = True
	endif
	if a.IsClothingFeet()
		isCloth = True
	endif

	if isCloth
		Float bCloth = ReadCfgFloat("player.weightClass.clothing", 0.0)
		return bCloth
	endif

	; Armor weight class (0=Light, 1=Heavy in practice)
	Int wc = a.GetWeightClass()
	if wc == 0
		Float bLight = ReadCfgFloat("player.weightClass.light", 0.0)
		return bLight
	elseif wc == 1
		Float bHeavy = ReadCfgFloat("player.weightClass.heavy", 0.0)
		return bHeavy
	else
		; Unknown/other -> no bonus
		return 0.0
	endif
EndFunction

; ===== Keyword bonuses (JSON ? Keyword ? HasKeyword) =====
Float Function SumMaskBonuses(Actor p)
	if !p
		return 0.0
	endif

	Float total = 0.0

	Bool enabled = False
	Float fe = JsonUtil.GetFloatValue(ConfigPath, "player.maskBonuses.enabled", 0.0)
	if fe >= 0.5
		enabled = True
	endif
	if !enabled
		return total
	endif

	Int n = ReadCfgInt("player.maskBonuses.len", 0)
	if n <= 0
		return total
	endif

	Bool dedupe = False
	Float fdd = JsonUtil.GetFloatValue(ConfigPath, "player.maskBonuses.dedupeSameForm", 1.0)
	if fdd >= 0.5
		dedupe = True
	endif

Form[] seen = None
Int seenCount = 0
if dedupe
	seen = new Form[64] ; Papyrus requires a literal
endif

	Int i = 0
	while i < n
		String base = "player.maskBonuses." + i
		Int mask = ReadCfgInt(base + ".mask", 0)
		if mask > 0
			Form f = p.GetWornForm(mask)
			if f
				if dedupe
					Bool already = False
					Int j = 0
					while j < seenCount
						if seen[j] == f
							already = True
						endif
						j = j + 1
					endwhile
					if !already
						seen[seenCount] = f
						seenCount = seenCount + 1
						Float add1 = ReadCfgFloat(base + ".bonus", 0.0)
						total = total + add1
					endif
				else
					Float add2 = ReadCfgFloat(base + ".bonus", 0.0)
					total = total + add2
				endif
			endif
		endif
		i = i + 1
	endwhile

	return total
EndFunction

Int Function GetKeywordBonusCount()
	Int n = ReadCfgInt("player.keywordBonuses.len", 0)
	if n < 0
		return 0
	endif
	return n
EndFunction

Keyword Function ResolveKeywordFromJsonIndex(Int i)
	String base = "player.keywordBonuses." + i

	; 1) Preferred: EditorID via po3 (no file/id math)
	String editorID = ReadCfgString(base + ".editorID", "")
	if editorID != ""
		Form fEd = PO3_SKSEFunctions.GetFormFromEditorID(editorID)
		if fEd
			Keyword kEd = fEd as Keyword
			if kEd
				return kEd
			endif
		endif
	endif

	; 2) Fallback: file + decimal FormID (works without po3)
	String file = ReadCfgString(base + ".file", "")
	Int idDec = ReadCfgInt(base + ".idDec", 0)
	if file != "" && idDec > 0
		Form f = Game.GetFormFromFile(idDec, file)
		if f
			Keyword k = f as Keyword
			return k
		endif
	endif

	return None
EndFunction

; ===== Slot readers =====
Armor Function GetWornArmorByMask(Actor p, Int mask)
	if mask <= 0
		return None
	endif
	Form f = p.GetWornForm(mask)
	if !f
		return None
	endif
	Armor a = f as Armor
	return a
EndFunction

Float Function SlotWarmthIfWorn(Actor p, String slotKey)
	String base = "player.slots." + slotKey
	Int mask = ReadCfgInt(base + ".mask", 0)
	Float slotBonus = ReadCfgFloat(base + ".bonus", 0.0)

	if mask <= 0
		return 0.0
	endif

	Armor a = GetWornArmorByMask(p, mask)
	if !a
		return 0.0
	endif

	Float total = slotBonus
	total = total + GetWeightClassBonus(a)     ; stable vs renames/enchants
	total = total + GetKeywordBonuses(a)       ; stable vs renames/enchants
	return total
EndFunction

Float Function GetKeywordBonuses(Armor a)
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
		if k
			Bool has = a.HasKeyword(k)
			if has
				Float add = ReadCfgFloat("player.keywordBonuses." + i + ".bonus", 0.0)
				total = total + add
			endif
		endif
		i = i + 1
	endwhile

	return total
EndFunction

; ===== Lifecycle =====
Event OnInit()
	RegisterForModEvent("SS_WeatherTick", "OnSSTick")
	if DebugLog
		Log("OnInit")
	endif
EndEvent

Event OnPlayerLoadGame()
	if DebugLog
		Log("OnPlayerLoadGame")
	endif
EndEvent

; ===== Core =====
Event OnSSTick(String eventName, String reason, Float numArg, Form sender)
	Actor p = Game.GetPlayer()
	if !p
		Log("No player")
		return
	endif

	Int snapshotId = numArg as Int

	Float warmth = 0.0

	; 1) Mask-driven bonuses
	warmth = warmth + SumMaskBonuses(p)

	; 2) Keyword bonuses across unique worn armors found from mask list
Armor[] worn = new Armor[64] ; literal size
Int count = CollectWornArmorsFromMaskList(p, worn)
	Int k = 0
	while k < count
		Float addK = GetKeywordBonuses(worn[k])
		warmth = warmth + addK
		k = k + 1
	endwhile

	; (Optional) If you later want weight-class again, loop worn[] and add GetWeightClassBonus(worn[i]) here.

	Int h = ModEvent.Create("SS_WeatherPlayerResult")
	if h
		ModEvent.PushFloat(h, snapshotId as Float)
		ModEvent.PushFloat(h, warmth)
		ModEvent.PushString(h, "id=" + snapshotId + " reason=" + reason + " warmth=" + warmth)
		ModEvent.Send(h)
	endif

	if DebugLog
		Log("id=" + snapshotId + " reason=" + reason + " warmth=" + warmth)
	endif
EndEvent