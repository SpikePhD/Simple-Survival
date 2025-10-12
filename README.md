Simple Survival - Skyrim Survival Mod
=====================================

This repository contains the Papyrus sources, compiled scripts, and plugin data for the Simple Survival mod.

## Configuration
* Configuration lives at `Data/SKSE/Plugins/SS/config.json` and is read/written via PapyrusUtil's `JsonUtil` helper.
* No external custom DLLs are required; the mod relies only on Papyrus, SKSE64, PapyrusUtil, and powerofthree's Papyrus Extender.

---

## 🧭 Overview

**Simple Survival** is a modular **survival overhaul** for *Skyrim Anniversary Edition* written purely in **Papyrus**.
It focuses on realism through systems for **weather exposure**, **hunger**, and (in the future) **rest**, while minimizing overhead and heartbeat loops.

Each subsystem is self-contained and exposes a simple **tier output (0–5)** that represents the player’s comfort or condition. These tiers will later drive a unified **penalty/bonus system** through an ability controller.

---

## ⚙️ Core Script Roles

### **SS_Controller.psc**

* The **central coordinator**.
* Initializes the mod and registers the three major subsystems:

  * `SS_Weather` – handles cold exposure.
  * `SS_Hunger` – manages food depletion and hunger.
  * `SS_Rest` – (to come later) for sleep/fatigue tracking.
* Manages **mod events** like QuickTick (equip/unequip, interior changes, fast travel).
* Provides the single interface for the **MCM menu** to query and display subsystem values.
* Communicates with `SS_AbilityDriver` for applying penalties or bonuses once all systems report valid tiers .

---

### **SS_Weather.psc**

* Governs **environmental exposure and player warmth**.
* Uses SKSE’s `PO3` functions (`FindWeather`, `GetCurrentWeather`) to determine the current weather type.
* Calculates **PlayerWarmth / EnvironmentalWarmth** → normalizes this into a **comfort percentage**.
* Maps that percentage to a **tier**:

  * Tier 0: Comfortable (≥100%)
  * Tier 5: Frozen (0%)
* Reads warmth bonuses dynamically from **JSON config files**, allowing keyword-based detection of armor names (e.g., “fur”, “bear”, “heavy”) without CK FormLists.
* Caches these name bonuses safely (via `SS_JsonHelpers`) and recalculates only on **QuickTicks** — not per-frame — ensuring negligible VM load.
* Emits a mod event when the tier changes so that the controller can react (for example, triggering a penalty evaluation)  .

---

### **SS_Hunger.psc**

* Handles the **hunger timer** and food consumption tracking.
* Maintains a **Hunger Points (0–100)** counter:

  * Eating food adds points.
  * Every in-game hour, points decay according to rules in `LoadHungerConfig()`.
* Determines hunger **tier** based on current percentage (Peckish → Starving).
* Similar to `SS_Weather`, it reports its tier via mod event to the controller.
* Now includes guards against missing JSON data (`None → Keyword[]` issues fixed) and better config counters for food keywords .

---

### **SS_AbilityDriver.psc**

* Not yet finalized but conceptually acts as the **effect manager**.
* Listens for tier change events from Weather, Hunger, and Rest.
* Calculates a **combined comfort score** (or worst-of tier) and applies or removes the appropriate **hidden ability** on the player.
* These abilities use **constant-effect Magic Effects** (Value/Peak Value Modifiers) to alter max Health/Stamina/Magicka and rates, rather than using `SetAV`, avoiding damage-state confusion and heartbeat polling .

---

### **SS_MCM.psc**

* The **Mod Configuration Menu** controller.
* Queries the controller for current subsystem data.
* Displays the tier values (`0–5`) or “--” when invalid/uninitialized.
* You recently fixed null safety here; once Weather/Hunger successfully evaluate once, MCM immediately updates from “--” to the correct values .

---

### **SS_JsonHelpers.psc**

* Utility library (Hidden script).
* Provides safe array accessors:

  * `GetStringArraySafe()`
  * `GetFloatArraySafe()`
* Guarantees that even if JSON data is missing, these functions return empty arrays rather than `None`, preventing casting errors during initialization .

---

## 🧩 How the Systems Connect

1. **Event Sources**

   * Game actions (equip/unequip, weather change, entering/exiting, fast travel) trigger a **QuickTick** event.
   * Hourly in-game updates trigger Hunger (and later Rest) decay.

2. **Subsystems Process**

   * `SS_Weather` and `SS_Hunger` evaluate independently, each determining their tier.
   * Each emits a “tier changed” event if the new value differs from the last.

3. **Controller Reacts**

   * `SS_Controller` listens to these events.
   * When any tier changes, it triggers a one-shot **aggregate update** via the `SS_AbilityDriver`.

4. **AbilityDriver Applies Effects**

   * Combines subsystem tiers → decides overall player state.
   * Applies the appropriate **ability** (for penalties or bonuses).

5. **MCM Displays**

   * MCM polls the controller or receives updates for display.
   * Shows `WeatherTier` / `HungerTier` numerically or as “--” if uninitialized.

# Simple Survival – Wiring Overview

## Scripts:
  - `SS_Controller.psc`
  - `SS_Weather.psc`
  - `SS_AbilityDriver.psc`
  - `SS_Hunger.psc`
  - `SS_JSonHelpers.psc`
  - `SS_MCM.psc`
  - `SS_PlayerEvents.psc`


## Quests
### SS_Controller (QUST)
- **Scripts**
  - `SS_Controller.psc`
  - `SS_Weather.psc`
  - `SS_Hunger.psc`

- **Aliases to SS_Controller (QUST)**
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
