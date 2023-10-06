raiseFlag = {}
raiseFlag.version = "1.2.1"
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
	1.2.1 - support for 'inc', 'dec', 'flip'
	2.0.0 - dmlZones
	      - full method support  
		  - full DML upgrade 
		  - method attribute (synonym to 'value' 
	
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
	
	-- pre-method DML raiseFlag is now upgraded to method.
	-- flagValue now carries the method
	if theZone:hasProperty("value") then -- backward compatibility
		theZone.flagValue = theZone:getStringFromZoneProperty("value", "inc") -- value to set to. default is command 'inc'
	else 
		theZone.flagValue = theZone:getStringFromZoneProperty("method", "inc")
	end
	theZone.flagValue = theZone.flagValue:lower()

	theZone.minAfterTime, theZone.maxAfterTime = theZone:getPositiveRangeFromZoneProperty("afterTime", -1)

	-- method for triggering 
	-- watchflag:
	-- triggerMethod
	theZone.raiseTriggerMethod = theZone:getStringFromZoneProperty( "triggerMethod", "change")
	if theZone:hasProperty("raiseTriggerMethod") then 
		theZone.raiseTriggerMethod = theZone:getStringFromZoneProperty("raiseTriggerMethod", "change")
	end

	if theZone:hasProperty("stopFlag?") then 
		theZone.triggerStopFlag = theZone:getStringFromZoneProperty( "stopFlag?", "none")
		theZone.lastTriggerStopValue = theZone:getFlagValue(theZone.triggerStopFlag) -- save last value
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
	local command = theZone.flagValue
	theZone:pollFlag(theZone.raiseFlag, command)
	if raiseFlag.verbose or theZone.verbose then 
		trigger.action.outText("+++rFlg - raising <" .. theZone.raiseFlag .. "> with method '" .. command .. "'" ,30)
	end
		
	--[[--	
	command = dcsCommon.trim(command)
	if command == "inc" or command == "dec" or command == "flip" then 
		cfxZones.pollFlag(theZone.raiseFlag, command, theZone)
		if raiseFlag.verbose or theZone.verbose then 
			trigger.action.outText("+++rFlg - raising <" .. theZone.raiseFlag .. "> with method " .. command ,30)
		end
	else 
		cfxZones.setFlagValue(theZone.raiseFlag, theZone.flagValue, theZone)
		if raiseFlag.verbose or theZone.verbose then 
			trigger.action.outText("+++rFlg - raising <" .. theZone.raiseFlag .. "> to value: " .. theZone.flagValue ,30)
		end
	end
	--]]--
end

--
-- update 
--
function raiseFlag.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(raiseFlag.update, {}, timer.getTime() + 1)
		
	for idx, aZone in pairs(raiseFlag.flags) do
		-- make sure to re-start before reading time limit
		if aZone:testZoneFlag(aZone.triggerStopFlag, aZone.raiseTriggerMethod, "lastTriggerStopValue") then
			theZone.raiseStopped = true -- we are done, no flag! 
		end
		
	end
end

--
-- config & go!
--

function raiseFlag.readConfigZone()
	local theZone = cfxZones.getZoneByName("raiseFlagConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("raiseFlagConfig")
	end 
	
	raiseFlag.verbose = theZone.verbose
	
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
