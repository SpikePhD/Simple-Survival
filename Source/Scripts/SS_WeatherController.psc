Scriptname SS_WeatherController extends Quest

Import Math

Quest Property WeatherQuest Auto
Quest Property WeatherPlayerQuest Auto
Spell Property SS_PlayerAbility Auto

SS_WeatherEnvironment WeatherEnvironmentModule
SS_WeatherPlayer       WeatherPlayerModule

Bool bInitialized = False
Bool bWeatherEventsRegistered = False
Float cachedEnvWarmth = 0.0
Float cachedPlayerWarmth = 0.0
Float Property LastCoveragePercent Auto
Int   Property LastTier Auto

Bool Property DebugEnabled Hidden
  Bool Function Get()
    if WeatherEnvironmentModule != None
      if WeatherEnvironmentModule.DebugEnabled
        return True
      endif
    endif
    if WeatherPlayerModule != None
      if WeatherPlayerModule.DebugEnabled
        return True
      endif
    endif
    return False
  EndFunction
EndProperty

Event OnInit()
  InitializeWeatherModules()
  ConfigureAbility(SS_PlayerAbility)
  ApplyConfigDefaults()
  RegisterWeatherEvents()
  SyncCachedWeatherValues()
  RefreshPlayerWarmth("WeatherControllerInit")
  UpdateWeatherTier("WeatherControllerInit")
  bInitialized = True
EndEvent

Event OnPlayerLoadGame()
  InitializeWeatherModules()
  ConfigureAbility(SS_PlayerAbility)
  ApplyConfigDefaults()
  RegisterWeatherEvents()
  SyncCachedWeatherValues()
  RefreshPlayerWarmth("WeatherControllerLoadGame")
  UpdateWeatherTier("WeatherControllerLoadGame")
EndEvent

Function ConfigureAbility(Spell ability)
  InitializeWeatherModules()
  if ability != None
    SS_PlayerAbility = ability
  endif
  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.ConfigureModule(SS_PlayerAbility)
  endif
EndFunction

Function ApplyConfigDefaults()
  InitializeWeatherModules()
  if WeatherPlayerModule != None
    WeatherPlayerModule.ApplyConfigDefaults()
  endif
  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.ApplyDebugFlags()
  endif
EndFunction

Function InitializeWeatherModules()
  if WeatherQuest == None
    WeatherQuest = Self
  endif
  if WeatherQuest != None
    WeatherEnvironmentModule = WeatherQuest as SS_WeatherEnvironment
  endif

  if WeatherPlayerQuest == None
    WeatherPlayerQuest = WeatherQuest
  endif
  if WeatherPlayerQuest != None
    WeatherPlayerModule = WeatherPlayerQuest as SS_WeatherPlayer
  endif
EndFunction

Function RegisterWeatherEvents()
  if bWeatherEventsRegistered
    return
  endif
  RegisterForModEvent("SS_Evt_EnvChanged", "OnEnvironmentChanged")
  RegisterForModEvent("SS_Evt_PlayerWarmthChanged", "OnPlayerWarmthChanged")
  bWeatherEventsRegistered = True
EndFunction

Function SyncCachedWeatherValues()
  if WeatherEnvironmentModule != None
    cachedEnvWarmth = WeatherEnvironmentModule.GetEnvironmentalWarmth()
  else
    cachedEnvWarmth = 0.0
  endif
  if WeatherPlayerModule != None
    cachedPlayerWarmth = WeatherPlayerModule.GetPlayerWarmth()
  else
    cachedPlayerWarmth = 0.0
  endif
EndFunction

Float Function RefreshPlayerWarmth(String source = "WeatherController")
  InitializeWeatherModules()
  if WeatherPlayerModule == None
    return 0.0
  endif
  cachedPlayerWarmth = WeatherPlayerModule.RefreshPlayerWarmth(source)
  return cachedPlayerWarmth
EndFunction

Function RequestFastTick(String source = "RequestFastTick")
  InitializeWeatherModules()
  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.RequestFastTick(source)
  endif
EndFunction

Function RequestEnvironmentEvaluate(String source = "EnvironmentChange", Bool forceImmediate = True)
  InitializeWeatherModules()
  if WeatherEnvironmentModule == None
    return
  endif
  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.RequestEvaluate(source, forceImmediate)
  endif
EndFunction

Function NotifyFastTravelOrigin()
  InitializeWeatherModules()
  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.RecordFastTravelOrigin()
  endif
EndFunction

Function ApplyDebugFlags()
  InitializeWeatherModules()
  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.ApplyDebugFlags()
  endif
  if WeatherPlayerModule != None
    WeatherPlayerModule.ApplyConfigDefaults()
  endif
EndFunction

String Function BuildTierSourceLabel(String prefix, String source)
  if prefix == ""
    return source
  endif
  if source == ""
    return prefix
  endif
  return prefix + "|" + source
EndFunction

Event OnEnvironmentChanged(Float envWarmth, String source)
  cachedEnvWarmth = envWarmth
  String tierSource = BuildTierSourceLabel("EnvChanged", source)
  RefreshPlayerWarmth(tierSource)
  UpdateWeatherTier(tierSource)
EndEvent

Event OnPlayerWarmthChanged(Float playerWarmth, String source)
  cachedPlayerWarmth = playerWarmth
  UpdateWeatherTier(source)
EndEvent

Function UpdateWeatherTier(String source)
  ComputeTier(cachedPlayerWarmth, cachedEnvWarmth, source)
EndFunction

Int Function ComputeTier(Float playerWarmth, Float envWarmth, String source = "WeatherTier")
  Float coverage = ComputeCoveragePercent(playerWarmth, envWarmth)
  Int tier = DetermineCoverageTier(coverage)

  Bool tierChanged = (tier != LastTier)
  Bool coverageChanged = Math.Abs(coverage - LastCoveragePercent) > 0.1

  LastCoveragePercent = coverage
  LastTier = tier

  if tierChanged || coverageChanged
    int evt = ModEvent.Create("SS_Evt_WeatherTierChanged")
    if evt
      ModEvent.PushInt(evt, tier)
      ModEvent.PushFloat(evt, coverage)
      ModEvent.Send(evt)
    endif
  endif

  return tier
EndFunction

Float Function ComputeCoveragePercent(Float playerWarmth, Float environmentRequirement)
  Float coverage = 100.0
  Float requirement = environmentRequirement

  if requirement < 0.0
    requirement = 0.0
  endif

  if requirement > 0.001
    coverage = 0.0
    if playerWarmth > 0.0
      coverage = (playerWarmth / requirement) * 100.0
    endif
  endif

  if coverage < 0.0
    coverage = 0.0
  elseif coverage > 100.0
    coverage = 100.0
  endif

  return coverage
EndFunction

Int Function DetermineCoverageTier(Float coveragePercent)
  Float normalized = coveragePercent
  if normalized < 0.0
    normalized = 0.0
  elseif normalized > 100.0
    normalized = 100.0
  endif

  if normalized >= 100.0
    return 0
  elseif normalized >= 75.0
    return 1
  elseif normalized >= 50.0
    return 2
  elseif normalized >= 25.0
    return 3
  elseif normalized >= 1.0
    return 4
  endif
  return 5
EndFunction

Float Function GetPlayerWarmth()
  return cachedPlayerWarmth
EndFunction

Float Function GetEnvironmentalWarmth()
  return cachedEnvWarmth
EndFunction

Float Function GetLastSafeRequirement()
  if WeatherEnvironmentModule != None
    return WeatherEnvironmentModule.GetLastSafeRequirement()
  endif
  return 0.0
EndFunction

Float Function GetLastBaseRequirement()
  if WeatherEnvironmentModule != None
    return WeatherEnvironmentModule.LastBaseRequirement
  endif
  return 0.0
EndFunction

Float Function GetLastWeatherBonus()
  if WeatherEnvironmentModule != None
    return WeatherEnvironmentModule.LastWeatherBonus
  endif
  return 0.0
EndFunction

String Function GetLastEnvSnapshot()
  if WeatherEnvironmentModule != None
    return WeatherEnvironmentModule.GetLastEnvSnapshot()
  endif
  return ""
EndFunction

Int Function GetLastRegionClass()
  if WeatherEnvironmentModule != None
    return WeatherEnvironmentModule.GetLastRegionClass()
  endif
  return -1
EndFunction

Int Function GetLastWeatherClass()
  if WeatherEnvironmentModule != None
    return WeatherEnvironmentModule.GetLastWeatherClass()
  endif
  return -1
EndFunction

Bool Function GetLastInteriorState()
  if WeatherEnvironmentModule != None
    return WeatherEnvironmentModule.GetLastInteriorState()
  endif
  return False
EndFunction

Float Function GetCoveragePercent()
  return LastCoveragePercent
EndFunction

Int Function GetTier()
  return LastTier
EndFunction

EndScript
