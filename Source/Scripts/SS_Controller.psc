Scriptname SS_Controller extends Quest

Quest Property WeatherControllerQuest Auto
Quest Property HungerQuest Auto
Spell Property SS_PlayerAbility Auto

SS_WeatherController WeatherControllerModule
SS_Hunger HungerModule

Bool Property DebugEnabled Hidden
  Bool Function Get()
    InitializeWeatherController()
    if WeatherControllerModule != None
      if WeatherControllerModule.DebugEnabled
        return True
      endif
    endif
    if HungerModule != None
      return HungerModule.DebugEnabled
    endif
    return False
  EndFunction
EndProperty

Event OnInit()
  InitializeWeatherController()
  if WeatherControllerModule != None
    WeatherControllerModule.ConfigureAbility(SS_PlayerAbility)
    WeatherControllerModule.RefreshPlayerWarmth("ControllerInit")
    WeatherControllerModule.UpdateWeatherTier("ControllerInit")
  endif
  InitializeHungerModule()
EndEvent

Event OnPlayerLoadGame()
  InitializeWeatherController()
  if WeatherControllerModule != None
    WeatherControllerModule.ConfigureAbility(SS_PlayerAbility)
    WeatherControllerModule.RefreshPlayerWarmth("OnPlayerLoadGame")
    WeatherControllerModule.UpdateWeatherTier("OnPlayerLoadGame")
  endif
  InitializeHungerModule()
EndEvent

Function InitializeWeatherController()
  if WeatherControllerModule != None
    return
  endif
  if WeatherControllerQuest == None
    WeatherControllerQuest = Self
  endif
  if WeatherControllerQuest != None
    WeatherControllerModule = WeatherControllerQuest as SS_WeatherController
  endif
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

Float Property LastWarmth Hidden
  Float Function Get()
    InitializeWeatherController()
    if WeatherControllerModule != None
      return WeatherControllerModule.GetPlayerWarmth()
    endif
    return 0.0
  EndFunction
EndProperty

Float Property LastSafeRequirement Hidden
  Float Function Get()
    InitializeWeatherController()
    if WeatherControllerModule != None
      return WeatherControllerModule.GetLastSafeRequirement()
    endif
    return 0.0
  EndFunction
EndProperty

Float Property LastWeatherBonus Hidden
  Float Function Get()
    InitializeWeatherController()
    if WeatherControllerModule != None
      return WeatherControllerModule.GetLastWeatherBonus()
    endif
    return 0.0
  EndFunction
EndProperty

Float Property LastBaseRequirement Hidden
  Float Function Get()
    InitializeWeatherController()
    if WeatherControllerModule != None
      return WeatherControllerModule.GetLastBaseRequirement()
    endif
    return 0.0
  EndFunction
EndProperty

Int Property LastHealthPenalty Hidden
  Int Function Get()
    return 0
  EndFunction
EndProperty

Int Property LastStaminaPenalty Hidden
  Int Function Get()
    return 0
  EndFunction
EndProperty

Int Property LastMagickaPenalty Hidden
  Int Function Get()
    return 0
  EndFunction
EndProperty

Int Property LastSpeedPenalty Hidden
  Int Function Get()
    return 0
  EndFunction
EndProperty

Int Property LastRegionClass Hidden
  Int Function Get()
    InitializeWeatherController()
    if WeatherControllerModule != None
      return WeatherControllerModule.GetLastRegionClass()
    endif
    return -1
  EndFunction
EndProperty

Int Property LastWeatherClass Hidden
  Int Function Get()
    InitializeWeatherController()
    if WeatherControllerModule != None
      return WeatherControllerModule.GetLastWeatherClass()
    endif
    return -1
  EndFunction
EndProperty

Bool Property LastInteriorState Hidden
  Bool Function Get()
    InitializeWeatherController()
    if WeatherControllerModule != None
      return WeatherControllerModule.GetLastInteriorState()
    endif
    return False
  EndFunction
EndProperty

Int Property LastPreparednessTier Hidden
  Int Function Get()
    InitializeWeatherController()
    if WeatherControllerModule != None
      return WeatherControllerModule.GetTier()
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
  InitializeWeatherController()
  if WeatherControllerModule != None
    WeatherControllerModule.InitializeWeatherModules()
    WeatherControllerModule.ConfigureAbility(SS_PlayerAbility)
  endif
EndFunction

Function ConfigureWeatherPlayerModule(SS_WeatherPlayer module)
  InitializeWeatherController()
  if WeatherControllerModule != None
    WeatherControllerModule.InitializeWeatherModules()
    WeatherControllerModule.ApplyConfigDefaults()
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
  InitializeWeatherController()
  if WeatherControllerModule != None
    WeatherControllerModule.ApplyDebugFlags()
  endif
EndFunction

Function RequestRefresh(String source = "RequestRefresh")
  if HungerModule == None
    InitializeHungerModule()
  endif

  if HungerModule != None
    HungerModule.UpdateFromGameTime(False)
  endif

  InitializeWeatherController()
  if WeatherControllerModule != None
    WeatherControllerModule.RequestFastTick(source)
  endif
EndFunction

Function RequestEnvironmentEvaluate(String source = "EnvironmentChange")
  if HungerModule == None
    InitializeHungerModule()
  endif

  if HungerModule != None
    HungerModule.UpdateFromGameTime(False)
  endif

  InitializeWeatherController()
  if WeatherControllerModule != None
    WeatherControllerModule.RequestEnvironmentEvaluate(source, True)
  endif
EndFunction

Function NotifyFastTravelOrigin()
  InitializeWeatherController()
  if WeatherControllerModule != None
    WeatherControllerModule.NotifyFastTravelOrigin()
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

EndScript
