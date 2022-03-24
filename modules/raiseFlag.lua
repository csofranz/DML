raiseFlag = {}
raiseFlag.version = "1.2.0"
raiseFlag.verbose = false 
raiseFlag.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
raiseFlag.flags = {} 
--[[--
	Raise A Flag module -- (c) 2022 by Christian Franz and cf/x AG
	
	Version History
	1.0.0 - initial release 
	1.0.1 - synonym "raiseFlag!"
	1.1.0 - DML update
	1.2.0 - Watchflag update 
	
--]]--
function raiseFlag.addRaiseFlag(theZone)
	table.insert(raiseFlag.flags, theZone)
end

function raiseFlag.getRaiseFlagByName(aName) 
	for idx, aZone in pairs(raiseFlag.flags) do 
		if aName == aZone.name then return aZone end 
	end
	if raiseFlag.verbose then 
		trigger.action.outText("+++rFlg: no raiseFlag with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read attributes
--
function raiseFlag.createRaiseFlagWithZone(theZone)
	-- get flag from faiseFlag itself
	if cfxZones.hasProperty(theZone, "raiseFlag") then
		theZone.raiseFlag = cfxZones.getStringFromZoneProperty(theZone, "raiseFlag", "<none>") -- the flag to raise 
	else 
		theZone.raiseFlag = cfxZones.getStringFromZoneProperty(theZone, "raiseFlag!", "<none>") -- the flag to raise 
	end 
	
	theZone.flagValue = cfxZones.getNumberFromZoneProperty(theZone, "value", 1) -- value to set to

	theZone.minAfterTime, theZone.maxAfterTime = cfxZones.getPositiveRangeFromZoneProperty(theZone, "afterTime", -1)

	-- method for triggering 
	-- watchflag:
	-- triggerMethod
	theZone.raiseTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "raiseTriggerMethod") then 
		theZone.raiseTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "raiseTriggerMethod", "change")
	end

	if cfxZones.hasProperty(theZone, "stopFlag?") then 
		theZone.triggerStopFlag = cfxZones.getStringFromZoneProperty(theZone, "stopFlag?", "none")
		theZone.lastTriggerStopValue = cfxZones.getFlagValue(theZone.triggerStopFlag, theZone) -- save last value
	end
	
	theZone.scheduleID = nil 
	theZone.raiseStopped = false 
	
	-- now simply schedule for invocation
	local args = {}
	args.theZone = theZone
	if theZone.minAfterTime < 1 then 
		timer.scheduleFunction(raiseFlag.triggered, args, timer.getTime() + 0.5)
	else
		local delay = cfxZones.randomDelayFromPositiveRange(theZone.minAfterTime, theZone.maxAfterTime)		
		timer.scheduleFunction(raiseFlag.triggered, args, timer.getTime() + delay)
	end
end

function raiseFlag.triggered(args)
	local theZone = args.theZone 
	if theZone.raiseStopped then return end 
	-- if we get here, we aren't stopped and do the flag pull
	cfxZones.setFlagValue(theZone.raiseFlag, theZone.flagValue, theZone)
end

--
-- update 
--
function raiseFlag.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(raiseFlag.update, {}, timer.getTime() + 1)
		
	for idx, aZone in pairs(raiseFlag.flags) do
		-- make sure to re-start before reading time limit
		if cfxZones.testZoneFlag(aZone, aZone.triggerStopFlag, aZone.raiseTriggerMethod, "lastTriggerStopValue") then
			theZone.raiseStopped = true -- we are done, no flag! 
		end
		
		-- old code 
		--[[--
		if aZone.triggerStopFlag then 
			local currTriggerVal = cfxZones.getFlagValue(aZone.triggerStopFlag, theZone)
			if currTriggerVal ~= aZone.lastTriggerStopValue
			then 
				theZone.raiseStopped = true -- we are done, no flag! 
			end
		end
		--]]--
	end
end

--
-- config & go!
--

function raiseFlag.readConfigZone()
	local theZone = cfxZones.getZoneByName("raiseFlagConfig") 
	if not theZone then 
		if raiseFlag.verbose then 
			trigger.action.outText("+++rFlg: NO config zone!", 30)
		end 
		return 
	end 
	
	raiseFlag.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if raiseFlag.verbose then 
		trigger.action.outText("+++rFlg: read config", 30)
	end 
end

function raiseFlag.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx raise flag requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Raise Flag", raiseFlag.requiredLibs) then
		return false 
	end
	
	-- read config 
	raiseFlag.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("raiseFlag")
	for k, aZone in pairs(attrZones) do 
		raiseFlag.createRaiseFlagWithZone(aZone) -- process attributes
		raiseFlag.addRaiseFlag(aZone) -- add to list
	end
	-- try synonym
	attrZones = cfxZones.getZonesWithAttributeNamed("raiseFlag!")
	for k, aZone in pairs(attrZones) do 
		raiseFlag.createRaiseFlagWithZone(aZone) -- process attributes
		raiseFlag.addRaiseFlag(aZone) -- add to list
	end
	
	-- start update 
	raiseFlag.update()
	
	trigger.action.outText("cfx raiseFlag v" .. raiseFlag.version .. " started.", 30)
	return true 
end

-- let's go!
if not raiseFlag.start() then 
	trigger.action.outText("cfx Raise Flag aborted: missing libraries", 30)
	raiseFlag = nil 
end