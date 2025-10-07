Scriptname SS_Controller extends Quest

Quest Property WeatherQuest Auto
Spell Property SS_PlayerAbility Auto

SS_Weather WeatherModule
Bool bInitialized = False

Event OnInit()
  InitializeWeatherModule()
  if WeatherModule != None
    WeatherModule.ConfigureModule(SS_PlayerAbility)
  endif
  bInitialized = True
EndEvent

Event OnPlayerLoadGame()
  InitializeWeatherModule()
  if WeatherModule != None
    WeatherModule.ConfigureModule(SS_PlayerAbility)
  endif
EndEvent

Function InitializeWeatherModule()
  if WeatherQuest == None
    WeatherQuest = Self
  endif
  if WeatherQuest != None
    WeatherModule = WeatherQuest as SS_Weather
  else
    WeatherModule = None
  endif
EndFunction

Float Property LastWarmth Hidden
  Float Function Get()
    if WeatherModule != None
      return WeatherModule.GetLastWarmth()
    endif
    return 0.0
  EndFunction
EndProperty

Float Property LastSafeRequirement Hidden
  Float Function Get()
    if WeatherModule != None
      return WeatherModule.GetLastSafeRequirement()
    endif
    return 0.0
  EndFunction
EndProperty

Float Property LastWeatherBonus Hidden
  Float Function Get()
    if WeatherModule != None
      return WeatherModule.GetLastWeatherBonus()
    endif
    return 0.0
  EndFunction
EndProperty

Float Property LastBaseRequirement Hidden
  Float Function Get()
    if WeatherModule != None
      return WeatherModule.LastBaseRequirement
    endif
    return 0.0
  EndFunction
EndProperty

Int Property LastHealthPenalty Hidden
  Int Function Get()
    if WeatherModule != None
      return WeatherModule.LastHealthPenalty
    endif
    return 0
  EndFunction
EndProperty

Int Property LastStaminaPenalty Hidden
  Int Function Get()
    if WeatherModule != None
      return WeatherModule.LastStaminaPenalty
    endif
    return 0
  EndFunction
EndProperty

Int Property LastMagickaPenalty Hidden
  Int Function Get()
    if WeatherModule != None
      return WeatherModule.LastMagickaPenalty
    endif
    return 0
  EndFunction
EndProperty

Int Property LastSpeedPenalty Hidden
  Int Function Get()
    if WeatherModule != None
      return WeatherModule.LastSpeedPenalty
    endif
    return 0
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

Function ConfigureWeatherModule(SS_Weather module)
  WeatherModule = module
  if WeatherModule != None && bInitialized
    WeatherModule.ConfigureModule(SS_PlayerAbility)
  endif
EndFunction

Function ApplyDebugFlags()
  if WeatherModule != None
    WeatherModule.ApplyDebugFlags()
  endif
EndFunction

Function RequestRefresh()
  if WeatherModule != None
    WeatherModule.RequestFastTick()
  endif
EndFunction

Function NotifySleepComplete(Float hoursSlept)
  ; placeholder for future hunger/fatigue integration
  RequestRefresh()
EndFunction
