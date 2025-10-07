# Simple Survival – Wiring Overview

## Quests
### SS_Controller (QUST)
- **Scripts**
  - `SS_Controller.psc`
  - `SS_Weather.psc`
- **Aliases**
  - `PlayerAlias`
    - Forced reference → `PlayerRef (00000014)`
    - Script → `SS_PlayerEvents.psc`

### SS_MCM (QUST)
- **Scripts**
  - `SS_MCM.psc` (SkyUI config script)

---

## Abilities
### SS_PlayerAbility (SPEL)
- Type: Ability  
- Casting: Constant Effect  
- Delivery: Self  

**Effects**
1. `SS_HealthRegenMult` (MGEF)
2. `SS_MagRegenMult` (MGEF)
3. `SS_StamRegenMult` (MGEF)
4. `SS_SpeedMult` (MGEF) → *Driver script attached*

---

## Magic Effects
### SS_HealthRegenMult (MGEF)
- Constant Effect, Self  
- No script

### SS_MagRegenMult (MGEF)
- Constant Effect, Self  
- No script

### SS_StamRegenMult (MGEF)
- Constant Effect, Self  
- No script

### SS_SpeedMult (MGEF)
- Constant Effect, Self, Hidden  
- Script → `SS_AbilityDriver.psc`

---

## Script summary

| Script | Attached To | Role |
|---------|--------------|------|
| **SS_Controller.psc** | Quest `SS_Controller` | Core controller; applies player ability; reload safety |
| **SS_Weather.psc** | Quest `SS_Controller` | Weather system logic (environment handling) |
| **SS_PlayerEvents.psc** | Quest Alias `PlayerAlias` | Push events (location, sleep, fast travel) |
| **SS_AbilityDriver.psc** | MGEF `SS_SpeedMult` | Active effect driver; responds to po3 weather & alias nudges |
| **SS_MCM.psc** | Quest `SS_MCM` | SkyUI configuration page |

---

## Runtime hierarchy

```text
Quest SS_Controller
 ├─ Scripts: SS_Controller, SS_Weather
 └─ PlayerAlias (forced to Player)
     └─ Script: SS_PlayerEvents
         └─ Calls → SS_AbilityDriver.TriggerEnvChanged()

Ability SS_PlayerAbility
 ├─ SS_HealthRegenMult (no script)
 ├─ SS_MagRegenMult (no script)
 ├─ SS_StamRegenMult (no script)
 └─ SS_SpeedMult → Script: SS_AbilityDriver
        └─ Listens for po3 weather changes
        └─ Handles environment logic, Hunger/Rest hooks

Quest SS_MCM
 └─ Script: SS_MCM (SkyUI)