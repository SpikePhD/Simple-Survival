Scriptname SS_Controller extends Quest

Quest Property WeatherQuest Auto
Quest Property WeatherPlayerQuest Auto
Quest Property WeatherTierQuest Auto
Quest Property HungerQuest Auto
Spell Property SS_PlayerAbility Auto

SS_WeatherEnvironment WeatherEnvironmentModule
SS_WeatherPlayer WeatherPlayerModule
SS_WeatherTiers WeatherTierModule
SS_Hunger HungerModule
Bool bInitialized = False

Bool Property DebugEnabled Hidden
  Bool Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.DebugEnabled
    endif
    if WeatherPlayerModule != None
      return WeatherPlayerModule.DebugEnabled
    endif
    if HungerModule != None
      return HungerModule.DebugEnabled
    endif
    return False
  EndFunction
EndProperty

Event OnInit()
  InitializeWeatherModules()
  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.ConfigureModule(SS_PlayerAbility)
  elseif WeatherPlayerModule != None
    WeatherPlayerModule.ApplyConfigDefaults()
  endif
  InitializeHungerModule()
  bInitialized = True
EndEvent

Event OnPlayerLoadGame()
  InitializeWeatherModules()
  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.ConfigureModule(SS_PlayerAbility)
  elseif WeatherPlayerModule != None
    WeatherPlayerModule.ApplyConfigDefaults()
  endif
  InitializeHungerModule()
EndEvent

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

  if WeatherTierQuest == None
    WeatherTierQuest = WeatherQuest
  endif
  if WeatherTierQuest != None
    WeatherTierModule = WeatherTierQuest as SS_WeatherTiers
  endif

  if WeatherEnvironmentModule != None
    if WeatherPlayerModule != None && WeatherEnvironmentModule.PlayerModule == None
      WeatherEnvironmentModule.PlayerModule = WeatherPlayerModule
    endif
    if WeatherTierModule != None && WeatherEnvironmentModule.TierModule == None
      WeatherEnvironmentModule.TierModule = WeatherTierModule
    endif
  endif
EndFunction

Float Property LastWarmth Hidden
  Float Function Get()
    if WeatherPlayerModule != None
      return WeatherPlayerModule.GetPlayerWarmth()
    endif
    return 0.0
  EndFunction
EndProperty

Float Property LastSafeRequirement Hidden
  Float Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.GetEnvironmentalWarmth()
    endif
    return 0.0
  EndFunction
EndProperty

Float Property LastWeatherBonus Hidden
  Float Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.LastWeatherBonus
    endif
    return 0.0
  EndFunction
EndProperty

Float Property LastBaseRequirement Hidden
  Float Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.LastBaseRequirement
    endif
    return 0.0
  EndFunction
EndProperty

Int Property LastHealthPenalty Hidden
  Int Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.LastHealthPenalty
    endif
    return 0
  EndFunction
EndProperty

Int Property LastStaminaPenalty Hidden
  Int Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.LastStaminaPenalty
    endif
    return 0
  EndFunction
EndProperty

Int Property LastMagickaPenalty Hidden
  Int Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.LastMagickaPenalty
    endif
    return 0
  EndFunction
EndProperty

Int Property LastSpeedPenalty Hidden
  Int Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.LastSpeedPenalty
    endif
    return 0
  EndFunction
EndProperty

Int Property LastRegionClass Hidden
  Int Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.GetLastRegionClass()
    endif
    return -1
  EndFunction
EndProperty

Int Property LastWeatherClass Hidden
  Int Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.GetLastWeatherClass()
    endif
    return -1
  EndFunction
EndProperty

Bool Property LastInteriorState Hidden
  Bool Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.GetLastInteriorState()
    endif
    return False
  EndFunction
EndProperty

Int Property LastPreparednessTier Hidden
  Int Function Get()
    if WeatherEnvironmentModule != None
      return WeatherEnvironmentModule.LastPreparednessTier
    endif
    if WeatherTierModule != None
      return WeatherTierModule.GetTier()
    endif
    return -1
  EndFunction
EndProperty

Int Property LastHungerValue Hidden
  Int Function Get()
    if HungerModule == None
      InitializeHungerModule()
      if HungerModule == None
        return 0
      endif
    endif
    return HungerModule.GetLastHungerValue()
  EndFunction
EndProperty

Float Property LastHungerHit100Time Hidden
  Float Function Get()
    if HungerModule == None
      InitializeHungerModule()
      if HungerModule == None
        return 0.0
      endif
    endif
    return HungerModule.GetLastHit100GameTime()
  EndFunction
EndProperty

Float Property LastHungerDecayCheck Hidden
  Float Function Get()
    if HungerModule == None
      InitializeHungerModule()
      if HungerModule == None
        return 0.0
      endif
    endif
    return HungerModule.GetLastDecayCheckGameTime()
  EndFunction
EndProperty

Int Property LastHungerTierValue Hidden
  Int Function Get()
    if HungerModule == None
      InitializeHungerModule()
      if HungerModule == None
        return 0
      endif
    endif
    return HungerModule.GetLastHungerTier()
  EndFunction
EndProperty

Float Function GetLastWarmth()
  return LastWarmth
EndFunction

Float Function GetLastSafeRequirement()
  return LastSafeRequirement
EndFunction

Float Function GetLastWeatherBonus()
  return LastWeatherBonus
EndFunction

Function InitializeHungerModule()
  if HungerQuest == None
    HungerModule = None
    return
  endif

  if HungerModule == None
    HungerModule = HungerQuest as SS_Hunger
  endif

  if HungerModule != None
    HungerModule.InitializeModule()
  endif
EndFunction

Int Function GetLastRegionClass()
  return LastRegionClass
EndFunction

Int Function GetLastWeatherClass()
  return LastWeatherClass
EndFunction

Bool Function WasLastInterior()
  return LastInteriorState
EndFunction

Int Function GetLastPreparednessTier()
  return LastPreparednessTier
EndFunction

Function ConfigureWeatherModule(SS_WeatherEnvironment module)
  WeatherEnvironmentModule = module
  if WeatherEnvironmentModule != None && bInitialized
    WeatherEnvironmentModule.ConfigureModule(SS_PlayerAbility)
  endif
EndFunction

Function ConfigureWeatherPlayerModule(SS_WeatherPlayer module)
  WeatherPlayerModule = module
  if WeatherPlayerModule != None && bInitialized
    WeatherPlayerModule.ApplyConfigDefaults()
  endif
EndFunction

Function ConfigureHungerModule(SS_Hunger module)
  HungerModule = module
  if HungerModule != None
    HungerModule.InitializeModule()
  endif
EndFunction

Function NotifyFoodConsumed(Potion foodItem)
  if foodItem == None
    return
  endif

  if HungerModule == None
    InitializeHungerModule()
    if HungerModule == None
      return
    endif
  endif

  HungerModule.HandleFoodConsumed(foodItem)
EndFunction

Function ApplyDebugFlags()
  if HungerModule != None
    HungerModule.ApplyDebugFlags()
  endif
  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.ApplyDebugFlags()
  endif
  if WeatherPlayerModule != None
    WeatherPlayerModule.ApplyConfigDefaults()
  endif
EndFunction

Function RequestRefresh(String source = "RequestRefresh")
  if HungerModule == None
    InitializeHungerModule()
  endif

  if HungerModule != None
    HungerModule.UpdateFromGameTime(False)
  endif

  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.RequestFastTick(source)
  endif
EndFunction

Function RequestEnvironmentEvaluate(String source = "EnvironmentChange")
  if HungerModule == None
    InitializeHungerModule()
  endif

  if HungerModule != None
    HungerModule.UpdateFromGameTime(False)
  endif

  if WeatherEnvironmentModule == None
    InitializeWeatherModules()
  endif

  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.RequestEvaluate(source, True)
  endif
EndFunction

Function NotifyFastTravelOrigin()
  if WeatherEnvironmentModule != None
    WeatherEnvironmentModule.RecordFastTravelOrigin()
  endif
EndFunction

Function NotifySleepComplete(Float hoursSlept)
  if HungerModule == None
    InitializeHungerModule()
  endif

  if HungerModule != None
    HungerModule.UpdateFromGameTime(True)
  endif

  RequestRefresh("SleepComplete")
EndFunction
