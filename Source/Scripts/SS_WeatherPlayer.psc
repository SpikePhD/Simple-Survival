Scriptname SS_WeatherPlayer extends Quest

Import JsonUtil
Import StringUtil
Import Math
Import SS_JsonHelpers

String Property CFG_PATH = "Data\\SKSE\\Plugins\\SS\\config.json" Auto
String   _configPath = "Data/SKSE/Plugins/SS/config.json"

Float Property LastPlayerWarmth Auto

Bool gearNameCacheValid = False
Int  gearNameCacheCount = 0
String[] gearNameMatchCache
Float[]  gearNameBonusCache
Bool  gearNameCaseInsensitive = True
Float gearNameBonusClamp = 0.0

Bool Property DebugEnabled Auto

Function ApplyConfigDefaults()
  Float f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.slots.body", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.slots.body", 50.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.slots.head", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.slots.head", 25.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.slots.hands", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.slots.hands", 25.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.slots.feet", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.slots.feet", 25.0)
  endif

  f = JsonUtil.GetPathFloatValue(CFG_PATH, "weather.cold.slots.cloak", -9999.0)
  if f == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "weather.cold.slots.cloak", 30.0)
  endif

  Int i = JsonUtil.GetPathIntValue(CFG_PATH, "gear.nameMatchCaseInsensitive", -9999)
  if i == -9999
    JsonUtil.SetPathIntValue(CFG_PATH, "gear.nameMatchCaseInsensitive", 1)
  endif

  Float clampValue = JsonUtil.GetPathFloatValue(CFG_PATH, "gear.nameBonusMaxPerItem", -9999.0)
  if clampValue == -9999.0
    JsonUtil.SetPathFloatValue(CFG_PATH, "gear.nameBonusMaxPerItem", 60.0)
  endif

  Int gearBonusCount = JsonUtil.PathCount(CFG_PATH, "gear.nameBonuses")
  if gearBonusCount == -1
    JsonUtil.SetPathStringValue(CFG_PATH, "gear.nameBonuses[0].match", "fur")
    JsonUtil.SetPathFloatValue(CFG_PATH, "gear.nameBonuses[0].bonus", 20.0)
    JsonUtil.SetPathStringValue(CFG_PATH, "gear.nameBonuses[1].match", "wool")
    JsonUtil.SetPathFloatValue(CFG_PATH, "gear.nameBonuses[1].bonus", 15.0)
    JsonUtil.SetPathStringValue(CFG_PATH, "gear.nameBonuses[2].match", "bear")
    JsonUtil.SetPathFloatValue(CFG_PATH, "gear.nameBonuses[2].bonus", 30.0)
    JsonUtil.SetPathStringValue(CFG_PATH, "gear.nameBonuses[3].match", "wolf")
    JsonUtil.SetPathFloatValue(CFG_PATH, "gear.nameBonuses[3].bonus", 25.0)
  endif

  JsonUtil.Save(CFG_PATH)
  InvalidateNameBonusCache()
EndFunction

Float Function GetPlayerWarmth()
  return LastPlayerWarmth
EndFunction

Float Function RefreshPlayerWarmth(String source = "Player")
  Actor p = Game.GetPlayer()
  if p == None
    UpdateWarmth(0.0, source)
    return 0.0
  endif

  EnsureNameBonusCache(ShouldForceNameBonusReload(source))

  Float bodyWarmth  = GetSlotWarmth("weather.cold.slots.body", 50.0)
  Float headWarmth  = GetSlotWarmth("weather.cold.slots.head", 25.0)
  Float handsWarmth = GetSlotWarmth("weather.cold.slots.hands", 25.0)
  Float feetWarmth  = GetSlotWarmth("weather.cold.slots.feet", 25.0)
  Float cloakWarmth = GetSlotWarmth("weather.cold.slots.cloak", 30.0)

  Float total = 0.0
  total += ComputePieceWarmth(p, 0x00000004, bodyWarmth)
  total += ComputePieceWarmth(p, 0x00000001, headWarmth, GetHeadGear(p))
  total += ComputePieceWarmth(p, 0x00000008, handsWarmth)
  total += ComputePieceWarmth(p, 0x00000080, feetWarmth)
  total += ComputePieceWarmth(p, 0x00010000, cloakWarmth)
  total += GetTorchWarmthBonus(p)

  Float perPiece = GetF("weather.cold.autoWarmthPerPiece", 100.0)
  if perPiece > 0.0 && perPiece != 100.0
    total *= (perPiece / 100.0)
  endif

  if p.IsSwimming()
    Float swimMalus = GetF("weather.cold.swimWarmthMalus", 0.0)
    if swimMalus > 0.0
      swimMalus = 0.0
    elseif swimMalus < -500.0
      swimMalus = -500.0
    endif
    total += swimMalus
  endif

  return UpdateWarmth(total, source)
EndFunction

Float Function UpdateWarmth(Float newWarmth, String source)
  Float previous = LastPlayerWarmth
  LastPlayerWarmth = newWarmth
  if Math.Abs(newWarmth - previous) > 0.1
    int evt = ModEvent.Create("SS_Evt_PlayerWarmthChanged")
    if evt
      ModEvent.PushFloat(evt, newWarmth)
      ModEvent.PushString(evt, source)
      ModEvent.Send(evt)
    endif
  endif
  return newWarmth
EndFunction

Float Function GetSlotWarmth(String path, Float fallback)
  return JsonUtil.GetPathFloatValue(CFG_PATH, path, fallback)
EndFunction

Float Function GetTorchWarmthBonus(Actor wearer)
  if wearer == None
    return 0.0
  endif

  Float torchBonus = GetF("weather.cold.torchWarmthBonus", 0.0)
  if torchBonus <= 0.0
    return 0.0
  endif

  Int leftHandType = wearer.GetEquippedItemType(1)
  Int rightHandType = wearer.GetEquippedItemType(0)

  if leftHandType == 11 || rightHandType == 11
    return torchBonus
  endif

  return 0.0
EndFunction

Armor Function GetHeadGear(Actor wearer)
  if wearer == None
    return None
  endif

  Armor gear = wearer.GetWornForm(0x00000001) as Armor
  if gear != None
    return gear
  endif

  gear = wearer.GetWornForm(0x00000002) as Armor
  if gear != None
    return gear
  endif

  return wearer.GetWornForm(0x00001000) as Armor
EndFunction

Float Function ComputePieceWarmth(Actor wearer, Int slotMask, Float baseWarmth, Armor preFetched = None)
  if wearer == None
    return 0.0
  endif

  Armor a = preFetched
  if a == None
    a = wearer.GetWornForm(slotMask) as Armor
  endif
  if a == None
    return 0.0
  endif

  Float warmth = baseWarmth
  Float nameBonus = ComputeNameWarmthBonus(a)
  warmth += nameBonus

  if warmth < 0.0
    warmth = 0.0
  endif
  return warmth
EndFunction

Float Function ComputeNameWarmthBonus(Armor a)
  if a == None
    return 0.0
  endif

  if !gearNameCacheValid
    return 0.0
  endif

  String displayName = a.GetName()
  if displayName == ""
    return 0.0
  endif

  String nameLower = NormalizeWarmthName(displayName)
  if nameLower == ""
    return 0.0
  endif

  Float totalBonus = 0.0
  Int idx = 0
  while idx < gearNameCacheCount
    String pattern = gearNameMatchCache[idx]
    if pattern != ""
      String patLower = NormalizeWarmthName(pattern)
      if patLower != ""
        if MatchPattern(nameLower, patLower)
          totalBonus += gearNameBonusCache[idx]
        endif
      endif
    endif
    idx += 1
  endwhile

  Float clampVal = gearNameBonusClamp
  if clampVal > 0.0 && totalBonus > clampVal
    totalBonus = clampVal
  endif

  return totalBonus
EndFunction

Bool Function MatchPattern(String target, String pattern)
  if target == "" || pattern == ""
    return False
  endif

  String normalizedTarget = target
  String normalizedPattern = pattern

  if gearNameCaseInsensitive
    normalizedTarget = ToLowerAscii(target)
    normalizedPattern = ToLowerAscii(pattern)
  endif

  return StringUtil.Find(normalizedTarget, normalizedPattern) >= 0
EndFunction

String Function ToLowerAscii(String value)
  if value == ""
    return ""
  endif

  Int totalLength = StringUtil.GetLength(value)
  if totalLength <= 0
    return ""
  endif

  String uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  String lowercase = "abcdefghijklmnopqrstuvwxyz"
  String result = ""
  Int idx = 0
  while idx < totalLength
    String ch = StringUtil.GetNthChar(value, idx)
    Int upperIndex = StringUtil.Find(uppercase, ch)
    if upperIndex >= 0
      result += StringUtil.GetNthChar(lowercase, upperIndex)
    else
      result += ch
    endif
    idx += 1
  endwhile

  return result
EndFunction

String Function NormalizeWarmthName(String value)
  if value == None
    return ""
  endif

  String trimmed = TrimWhitespace(value)
  if trimmed == ""
    return ""
  endif

  String lower = ToLowerAscii(trimmed)
  Int totalLength = StringUtil.GetLength(lower)
  if totalLength <= 0
    return ""
  endif

  String uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  String lowercase = "abcdefghijklmnopqrstuvwxyz"
  String normalized = ""
  Bool lastWasSpace = False
  Int idx = 0
  while idx < totalLength
    String ch = StringUtil.GetNthChar(trimmed, idx)
    Int upperIndex = StringUtil.Find(uppercase, ch)
    String lowered = ch
    if upperIndex >= 0
      lowered = StringUtil.GetNthChar(lowercase, upperIndex)
    endif

    if IsWhitespaceChar(lowered)
      if !lastWasSpace
        normalized += " "
        lastWasSpace = True
      endif
    else
      normalized += lowered
      lastWasSpace = False
    endif
    idx += 1
  endwhile

  return normalized
EndFunction

String Function TrimWhitespace(String value)
  if value == ""
    return ""
  endif

  Int startIndex = 0
  Int endIndex = StringUtil.GetLength(value) - 1
  while startIndex <= endIndex && IsWhitespaceChar(StringUtil.GetNthChar(value, startIndex))
    startIndex += 1
  endwhile

  while endIndex >= startIndex && IsWhitespaceChar(StringUtil.GetNthChar(value, endIndex))
    endIndex -= 1
  endwhile

  if endIndex < startIndex
    return ""
  endif

  return StringUtil.Substring(value, startIndex, endIndex - startIndex + 1)
EndFunction

Bool Function IsWhitespaceChar(String ch)
  if ch == " "
    return True
  elseif ch == "\t"
    return True
  elseif ch == "\r"
    return True
  elseif ch == "\n"
    return True
  endif
  return False
EndFunction

Bool Function SourceIncludes(String sources, String token)
  if sources == "" || token == ""
    return False
  endif
  return StringUtil.Find(sources, token) >= 0
EndFunction

Bool Function ShouldForceNameBonusReload(String source)
  if source == ""
    return False
  endif

  if SourceIncludes(source, "MCM")
    return True
  endif
  if SourceIncludes(source, "Refresh")
    return True
  endif
  if SourceIncludes(source, "Init")
    return True
  endif
  if SourceIncludes(source, "LoadGame")
    return True
  endif
  if SourceIncludes(source, "QuickTick")
    return True
  endif
  if SourceIncludes(source, "FastTick")
    return True
  endif

  return False
EndFunction

Function InvalidateNameBonusCache()
  gearNameCacheValid = False
  gearNameCacheCount = 0
  gearNameMatchCache = None
  gearNameBonusCache = None
EndFunction

Function EnsureNameBonusCache(Bool forceReload = False)
  if gearNameCacheValid && !forceReload
    return
  endif

  Int insensitive = JsonUtil.GetPathIntValue(CFG_PATH, "gear.nameMatchCaseInsensitive", 1)
  gearNameCaseInsensitive = insensitive > 0
  gearNameBonusClamp = JsonUtil.GetPathFloatValue(CFG_PATH, "gear.nameBonusMaxPerItem", 0.0)

  String[] nbMatches = SS_JsonHelpers.GetStringArraySafe(_configPath, ".gear.nameBonuses.matches")
  Float[]  nbValues  = SS_JsonHelpers.GetFloatArraySafe(_configPath,  ".gear.nameBonuses.values")

  if nbMatches.Length == 0 || nbValues.Length == 0
    InvalidateNameBonusCache()
    return
  endif

  if nbMatches.Length != nbValues.Length
    Debug.Trace("[SS] NameBonus: length mismatch; disabling cache")
    InvalidateNameBonusCache()
    return
  endif

  gearNameCacheCount = nbMatches.Length
  gearNameMatchCache = Utility.CreateStringArray(gearNameCacheCount)
  gearNameBonusCache = Utility.CreateFloatArray(gearNameCacheCount)

  int i = 0
  while i < gearNameCacheCount
    gearNameMatchCache[i] = nbMatches[i]
    gearNameBonusCache[i] = nbValues[i]
    i += 1
  endwhile

  gearNameCacheValid = True
EndFunction

Float Function GetF(String path, Float fallback = 0.0)
  return JsonUtil.GetPathFloatValue(CFG_PATH, path, fallback)
EndFunction

