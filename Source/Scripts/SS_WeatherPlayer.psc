Scriptname SS_WeatherPlayer extends Quest

Bool   Property DebugLog = False Auto
String Property ConfigPath = "Data/SKSE/Plugins/SS_WeatherConfig.json" Auto

; ---------- Build/Version Tag + Debug ----------
bool   property SS_DEBUG    auto
string property SS_BUILD_TAG auto

Function Log(String s)
	if DebugLog
		Debug.Trace("[SS_WeatherPlayer] " + s)
	endif
EndFunction

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

Float Function GetWeightClassBonus(Armor a)
	if !a
		return 0.0
	endif

	Bool isCloth = a.IsClothingHead() || a.IsClothingBody() || a.IsClothingHands() || a.IsClothingFeet()
	if isCloth
		return ReadCfgFloat("player.weightClass.clothing", 0.0)
	endif

	Int wc = a.GetWeightClass()
	if wc == 0
		return ReadCfgFloat("player.weightClass.light", 0.0)
	elseif wc == 1
		return ReadCfgFloat("player.weightClass.heavy", 0.0)
	endif
	return 0.0
EndFunction

Float Function SumMaskBonuses(Actor p)
	if !p
		return 0.0
	endif

	Float total = 0.0
	Bool enabled = JsonUtil.GetFloatValue(ConfigPath, "player.maskBonuses.enabled", 0.0) >= 0.5
	if !enabled
		return total
	endif

	Int n = ReadCfgInt("player.maskBonuses.len", 0)
	if n <= 0
		return total
	endif

	Bool dedupe = JsonUtil.GetFloatValue(ConfigPath, "player.maskBonuses.dedupeSameForm", 1.0) >= 0.5
	Form[] seen = None
	Int seenCount = 0
	if dedupe
		seen = new Form[64]
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
						total += ReadCfgFloat(base + ".bonus", 0.0)
					endif
				else
					total += ReadCfgFloat(base + ".bonus", 0.0)
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

Armor Function GetWornArmorByMask(Actor p, Int mask)
	if mask <= 0
		return None
	endif
	Form f = p.GetWornForm(mask)
	if !f
		return None
	endif
	return f as Armor
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
	Float total = slotBonus + GetWeightClassBonus(a) + GetKeywordBonuses(a)
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
		if k && a.HasKeyword(k)
			total += ReadCfgFloat("player.keywordBonuses." + i + ".bonus", 0.0)
		endif
		i = i + 1
	endwhile
	return total
EndFunction

Event OnInit()
	RegisterForModEvent("SS_Tick3", "OnTick3")
	RegisterForModEvent("SS_Tick4", "OnTick4")
	if SS_BUILD_TAG == ""
		SS_BUILD_TAG = "Player 2025-10-15.b"
	endif
	Debug.Trace("[SS_WeatherPlayer] OnInit build=" + SS_BUILD_TAG)
	if DebugLog
		Log("OnInit")
	endif
EndEvent

Event OnPlayerLoadGame()
	if DebugLog
		Log("OnPlayerLoadGame")
	endif
EndEvent

; 3-arg tick: (string, float, form)
Event OnTick3(String eventName, String reason, Float numArg, Form sender)
	HandleTick(numArg, sender)
EndEvent

; 4-arg tick: (string, string, float, form)
Event OnTick4(String eventName, Float numArg, Form sender)
	HandleTick(numArg, sender)
EndEvent

Function HandleTick(Float numArg, Form sender)
	if SS_DEBUG
		Debug.Trace("[SS_WeatherPlayer] HandleTick numArg=" + numArg + " sender=" + sender)
	endif
	Actor p = Game.GetPlayer()
	if !p
		Log("No player")
		return
	endif
	Int snapshotId = numArg as Int
	Float warmth = SumMaskBonuses(p)
	Armor[] worn = new Armor[64]
	Int count = CollectWornArmorsFromMaskList(p, worn)
	Int k = 0
	while k < count
		warmth += GetKeywordBonuses(worn[k])
		k = k + 1
	endwhile

	; ==== Emit on split channels: 4-arg + 3-arg fallback ====
	string sid = "" + snapshotId
	int h = ModEvent.Create("SS_WeatherPlayerResult4")
	bool okS  = ModEvent.PushString(h, sid)
	bool okF  = ModEvent.PushFloat(h, warmth)
	bool okFm = ModEvent.PushForm(h, Game.GetPlayer() as Form)
	bool sent4 = ModEvent.Send(h)
	(Game.GetPlayer() as Form).SendModEvent("SS_WeatherPlayerResult3", "", warmth)
	if SS_DEBUG
		Debug.Trace("[SS_WeatherPlayer] Emit " + SS_BUILD_TAG + " id=" + sid + " warmth=" + warmth + " sent4=" + sent4 + " (also sent PlayerResult3 fallback)")
	endif
EndFunction