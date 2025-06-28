# altitudeEngagementZones Module

Controls AAA/SAM units to engage aircraft only when above minimum altitude and inside specific zones. Supports both red AA engaging blue aircraft and blue AA engaging red aircraft.

## Setup

1. **Create zones** in the Mission Editor with these properties:
   - `altitudeEngagementZones`: Identifies this zone for this module. Value is ignored.
   - `minAltitude` (number): Minimum AGL altitude for engagement (default: 100m)
   - `targetCoalition` (number): Target coalition (1=red, 2=blue, default: 2)
   - `aaGroupPattern` (string): Pattern to match unit group names (default: "AA_Group")
   - `missileWarning` (boolean): Send missile launch warnings (default: false)
   - `active?` (boolean/flag): Zone active state (default: true) which can be set with a flag

2. **Place AA groups** inside zones with names matching the pattern (e.g., "AA_Group_1", "AA_Group_Zone2")

## Example Zone Properties

```
altitudeEngagementZones = "" -- Identifier
minAltitude = 150        -- Engage only above 150m AGL
targetCoalition = 2      -- Target blue coalition (red AA engages blue)
aaGroupPattern = "SAM"   -- Match groups starting with "SAM"
missileWarning = true    -- Send missile warnings
active? = makeActiveFlag -- Zone is active if `makeActiveFlag` is larger than 0
```

## Coalition Configuration

### Red AA Engaging Blue Aircraft (Default)
```
targetCoalition = 2  -- Target blue coalition
```
- Red AA groups engage blue aircraft above minimum altitude
- Blue AA groups are ignored

### Blue AA Engaging Red Aircraft
```
targetCoalition = 1  -- Target red coalition
```
- Blue AA groups engage red aircraft above minimum altitude
- Red AA groups are ignored

## Features

- **Altitude Control**: AA units only engage aircraft above minimum altitude
- **Zone-Based**: Engagement only occurs inside designated zones
- **Auto Discovery**: Finds AA groups by pattern and zone location
- **Weapons Hold**: Automatically sets AA to weapons hold when no valid targets
- **Dynamic Control**: Zones can be activated/deactivated via flags
- **Missile Warnings**: Optional missile launch notifications to target coalition
- **Multi-Target Support**: Handles multiple aircraft in zones correctly
- **State Management**: Tracks valid and invalid targets for each zone

## Behavior

- AA groups inside zones engage target coalition aircraft above minimum altitude
- When aircraft are below altitude or outside zones, AA units hold fire
- Module automatically manages ROE (Rules of Engagement) for AA groups
- Supports multiple zones with different settings
- If any aircraft in zone meets altitude criteria, AA engages all valid targets

## Helper Functions

The module provides helper functions to check engagement status:

```lua
-- Check if zone has valid targets
if altitudeEngagementZones.hasValidTargets(myZone) then
    -- Zone has targets above minimum altitude
end

-- Get engagement status
if altitudeEngagementZones.isEngaging(myZone) then
    -- AA units are currently engaging targets
end

-- Get target counts
local validCount = altitudeEngagementZones.getValidTargetCount(myZone)
local invalidCount = altitudeEngagementZones.getInvalidTargetCount(myZone)

-- Get target lists
local validTargets = altitudeEngagementZones.getValidTargets(myZone)
local invalidTargets = altitudeEngagementZones.getInvalidTargets(myZone)
```

## Target Object Structure

Each target in the valid/invalid target lists contains:
- `name`: Unit name
- `unit`: Unit object reference  
- `agl`: Altitude above ground level in meters

## Zone State Properties

Each zone maintains these state properties (updated each cycle):
- `validTargets`: Array of valid targets above minimum altitude
- `invalidTargets`: Array of invalid targets below minimum altitude
- `isActive`: Current active state of the zone 