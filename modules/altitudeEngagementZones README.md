# altitudeEngagementZones Module

Controls red AAA/SAM units to engage blue aircraft only when above minimum altitude and inside specific zones.

## Setup

1. **Create zones** in the Mission Editor with these properties:
   - `altitudeEngagementZones`: Identifies this zone for this module. Value is ignored.
   - `minAltitude` (number): Minimum AGL altitude for engagement (default: 100m)
   - `targetCoalition` (number): Target coalition (default: 2 = blue)
   - `aaGroupPattern` (string): Pattern to match unit group names (default: "AA_Group")
   - `missileWarning` (boolean): Send missile launch warnings (default: false)
   - `active?` (boolean/flag): Zone active state (default: true) which can be set with a flag

2. **Place AA groups** inside zones with names matching the pattern (e.g., "AA_Group_1", "AA_Group_Zone2")

## Example Zone Properties

```
altitudeEngagementZones = "" -- Identifier
minAltitude = 150        -- Engage only above 150m AGL
targetCoalition = 2      -- Target blue coalition
aaGroupPattern = "SAM"   -- Match groups starting with "SAM"
missileWarning = true    -- Send missile warnings
active? = makeActiveFlag -- Zone is active if `makeActiveFlag` is larger than 0
```

## Features

- **Altitude Control**: AA units only engage aircraft above minimum altitude
- **Zone-Based**: Engagement only occurs inside designated zones
- **Auto Discovery**: Finds AA groups by pattern and zone location
- **Weapons Hold**: Automatically sets AA to weapons hold when no valid targets
- **Dynamic Control**: Zones can be activated/deactivated via flags
- **Missile Warnings**: Optional missile launch notifications to target coalition

## Behavior

- AA groups inside zones engage blue aircraft above minimum altitude
- When aircraft are below altitude or outside zones, AA units hold fire
- Module automatically manages ROE (Rules of Engagement) for AA groups
- Supports multiple zones with different settings 