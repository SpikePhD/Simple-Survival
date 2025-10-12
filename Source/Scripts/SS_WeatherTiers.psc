Scriptname SS_WeatherTiers extends Quest

Import Math

Float Property LastCoveragePercent Auto
Int   Property LastTier Auto

Int Function ComputeTier(Float playerWarmth, Float envWarmth, String source = "Tier")
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

Float Function GetCoveragePercent()
  return LastCoveragePercent
EndFunction

Int Function GetTier()
  return LastTier
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

