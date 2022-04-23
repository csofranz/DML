baseCaptured={}
baseCaptured.version = "1.0.1"
baseCaptured.verbose = false
baseCaptured.requiredLibs = {
    "dcsCommon", -- always
    "cfxZones", -- Zones, of course
}
--[[--
    baseCaptured - Detects when the assigned base has been captured

    Properties
    - baseCaptured       Marks this as baseCaptured zone. The value is ignored. 
                         The closest base (airdrome or helipad) is automatically assigned to this zone.
                         (MANDATORY)
    - coalition          The coalition that needs to capture the base. Accepts 0/all, 1/red, 2/blue.
      captureCoalition   Defaults to 0 (all)
    - method             DML Flag method for output. Use only one synonym per zone.
      capturedMethod     Defaults to "flip".
    - f!                 The flag to bang! after the base matching above filter criteria has been captured.
      captured!          Use only one synonym per zone.

    Configuration
    - verbose                 Show debugging information. Default is false.

    Version History
    1.0.0 - Initial version
    1.0.1 - Automatic Closest Base Assignment
--]]--

baseCaptured.zones = {}

function baseCaptured.assignClosestBase(theZone)
	local base = dcsCommon.getClosestAirbaseTo(theZone.point)
	if base then 
        theZone.baseName = base:getName()
        if baseCaptured.verbose or theZone.verbose then
            trigger.action.outText("***basedCaptured: assigned <" .. theZone.name .. "> to base <" .. theZone.baseName .. ">", 30)
        end
	else 
		trigger.action.outText("***basedCaptured: unable to resolve base for <" .. theZone.name .. ">", 30)
	end
end

function baseCaptured.createZone(theZone)
    -- assign closest base
    baseCaptured.assignClosestBase(theZone)

    -- coalition (1=red,2=blue,0=neutral/all)
    theZone.captureCoalition = cfxZones.getCoalitionFromZoneProperty(theZone, "coalition", 0)
    if cfxZones.hasProperty(theZone, "captureCoalition") then
        theZone.captureCoalition = cfxZones.getCoalitionFromZoneProperty(theZone, "captureCoalition", 0)
    end

    if baseCaptured.verbose or theZone.verbose then 
        trigger.action.outText("***basedCaptured: set coalition " .. theZone.captureCoalition .. " for <" .. theZone.name .. ">", 30)
    end

    -- get flag output method
    theZone.capturedMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "flip")
    if cfxZones.hasProperty(theZone, "capturedMethod") then
        theZone.capturedMethod = cfxZones.getStringFromZoneProperty(theZone, "capturedMethod", "flip")
    end

    -- get captured flag
    if cfxZones.hasProperty(theZone, "f!") then
        theZone.capturedFlag = cfxZones.getStringFromZoneProperty(theZone, "f!", "*none")
    end
    if cfxZones.hasProperty(theZone, "captured!") then
        theZone.capturedFlag = cfxZones.getStringFromZoneProperty(theZone, "captured!", "*none")
    end
end

function baseCaptured.addZone(theZone)
    if not theZone.capturedFlag or theZone.capturedFlag == "*none" then
        trigger.action.outText("***baseCaptured NOTE: " .. theZone.name .. " is missing a valid <f!> or <captured!> property", 30)
        return
    end

    table.insert(baseCaptured.zones, theZone)
end

function baseCaptured.triggerZone(theZone)
    cfxZones.pollFlag(theZone.capturedFlag, theZone.capturedMethod, theZone)
    if baseCaptured.verbose then 
        trigger.action.outText("***baseCaptured: banging captured! with <" .. theZone.capturedMethod .. "> on <" .. theZone.capturedFlag .. "> for " .. theZone.baseName, 30)
    end 
end

-- world event callback
function baseCaptured:onEvent(event)
    -- only interested in S_EVENT_BASE_CAPTURED events
    if event.id ~= world.event.S_EVENT_BASE_CAPTURED then
        return
    end

    local baseName = event.place:getName()
    local newCoalition = event.place:getCoalition()

    for idx, aZone in pairs(baseCaptured.zones) do
        local hasName = aZone.baseName == baseName
        local hasCoalition = aZone.captureCoalition == 0 or aZone.captureCoalition == newCoalition
        if hasName and hasCoalition then
            baseCaptured.triggerZone(aZone)
        end
    end
end

function baseCaptured.readConfigZone()
    -- search for configuration zone
    local theZone = cfxZones.getZoneByName("baseCapturedConfig")
    if not theZone then
        return
    end

    baseCaptured.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)

    if baseCaptured.verbose then
        trigger.action.outText("***baseCaptured: read configuration from zone", 30)
    end
end

function baseCaptured.start()
    -- lib check
    if not dcsCommon.libCheck then
        trigger.action.outText("baseCaptured requires dcsCommon", 30)
        return false
    end
    if not dcsCommon.libCheck("baseCaptured", baseCaptured.requiredLibs) then
        return false
    end

    --read configuration
    baseCaptured.readConfigZone()

    -- process all baseCaptured zones
    local zones = cfxZones.getZonesWithAttributeNamed("baseCaptured")
    for k, aZone in pairs(zones) do
        baseCaptured.createZone(aZone) -- process zone attributes
        baseCaptured.addZone(aZone) -- add to list
    end

    -- listen for events
    world.addEventHandler(baseCaptured)

    trigger.action.outText("baseCaptured v" .. baseCaptured.version .. " started.", 30)
    return true
end

-- start module
if not baseCaptured.start() then
    trigger.action.outText("baseCaptured aborted: missing libraries", 30)
    baseCaptured = nil
end