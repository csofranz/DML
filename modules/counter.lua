counter = {}
counter.version = "1.0.0"

counter.verbose = false 
counter.ups = 1 
counter.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
counter.counters = {}
--[[--
	Version History
	1.0.0 - Initial version 
		
--]]--

function counter.addCounter(theZone)
	table.insert(counter.counters, theZone)
end

function counter.getCounterByName(aName) 
	for idx, aZone in pairs(counter.counters) do 
		if aName == aZone.name then return aZone end 
	end
	if counter.verbose then 
		trigger.action.outText("+++ctr: no counter with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

function counter.createCounterWithZone(theZone)
	theZone.counterInputFlag = cfxZones.getStringFromZoneProperty(theZone, "count?", "*<none>")
	theZone.lastCounterInputFlag = cfxZones.getFlagValue(theZone.counterInputFlag, theZone)
	
	-- triggerCounterMethod
	theZone.triggerCounterMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "triggerCountMethod") then 
		theZone.triggerCounterMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerChangeMethod", "change")
	end 
	
	theZone.countMethod = cfxZones.getStringFromZoneProperty(theZone, "countMethod", "+1")
	if cfxZones.hasProperty(theZone, "method") then 
		theZone.countMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "+1")
	end

	theZone.countOut = cfxZones.getStringFromZoneProperty(theZone, "out!", "<none>")
	if cfxZones.hasProperty(theZone, "countOut!") then 
		theZone.countOut = cfxZones.getStringFromZoneProperty(theZone, "countOut!", "<none>")
	end
end

--
-- Update 
--
function counter.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(counter.update, {}, timer.getTime() + 1/counter.ups)
		
	for idx, aZone in pairs(counter.counters) do
		if cfxZones.testZoneFlag(aZone, aZone.counterInputFlag, aZone.triggerCounterMethod, "lastCounterInputFlag") then 
			cfxZones.pollFlag(aZone.countOut, aZone.countMethod, aZone) 
		end

	end
end


--
-- Config & Start
--
function counter.readConfigZone()
	local theZone = cfxZones.getZoneByName("counterConfig") 
	if not theZone then 
		if counter.verbose then 
			trigger.action.outText("+++ctr: NO config zone!", 30)
		end 
		theZone = cfxZones.createSimpleZone("counterConfig") -- temp only
	end 
	
	counter.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	counter.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 1)
		
	if counter.verbose then 
		trigger.action.outText("+++ctr: read config", 30)
	end 
end

function counter.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx counter requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx counter", counter.requiredLibs) then
		return false 
	end
	
	-- read config 
	counter.readConfigZone()
	
	-- process counter Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("count?")
	for k, aZone in pairs(attrZones) do 
		counter.createCounterWithZone(aZone) -- process attributes
		counter.addCounter(aZone) -- add to list
	end
	
	-- start update 
	counter.update()
	
	trigger.action.outText("cfx counter v" .. counter.version .. " started.", 30)
	return true 
end

-- let's go!
if not counter.start() then 
	trigger.action.outText("cfx counter aborted: missing libraries", 30)
	counter = nil 
end