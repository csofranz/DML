radioTrigger = {}
radioTrigger.version = "1.0.0"
radioTrigger.verbose = false 
radioTrigger.ups = 1 
radioTrigger.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
radioTrigger.radioTriggers = {}

--[[--
	Version History 
	1.0.0 - initial version
	
--]]--

function radioTrigger.addRadioTrigger(theZone)
	table.insert(radioTrigger.radioTriggers, theZone)
end

function radioTrigger.getRadioTriggerByName(aName) 
	for idx, aZone in pairs(radioTrigger.radioTriggers) do 
		if aName == aZone.name then return aZone end 
	end
	if radioTrigger.verbose then 
		trigger.action.outText("+++radioTrigger: no radioTrigger with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read zone 
-- 
function radioTrigger.createRadioTriggerWithZone(theZone)
	-- read main trigger
	theZone.triggerRadioFlag = cfxZones.getStringFromZoneProperty(theZone, "radio?", "*<none>")
	theZone.lastRadioTriggerValue = cfxZones.getFlagValue(theZone.triggerRadioFlag, theZone)
	
	-- TriggerMethod: common and specific synonym
	theZone.radioTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "radioTriggerMethod") then 
		theZone.radioTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "radioTriggerMethod", "change")
	end 
	
	-- out method 
	theZone.rtMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "rtMethod") then 
		theZone.rtMethod = cfxZones.getStringFromZoneProperty(theZone, "rtMethod", "inc")
	end
	
	-- out flag 
	theZone.rtOutFlag = cfxZones.getStringFromZoneProperty(theZone, "out!", "*<none>")
	if cfxZones.hasProperty(theZone, "rtOut!") then 
		theZone.rtOutFlag = cfxZones.getStringFromZoneProperty(theZone, "rtOut!", "*<none>") 
	end
	
	if radioTrigger.verbose or theZone.verbose then 
		trigger.action.outText("+++rTrg: new radioTrigger zone <".. theZone.name ..">", 30)
	end
	
end

--
-- MAIN ACTION
--
function radioTrigger.process(theZone)
	-- we are triggered, simply poll the out flag 
	cfxZones.pollFlag(theZone.rtOutFlag, theZone.rtMethod, theZone)
	
end

--
-- Update 
--

function radioTrigger.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(radioTrigger.update, {}, timer.getTime() + 1/radioTrigger.ups)
		
	for idx, aZone in pairs(radioTrigger.radioTriggers) do
		-- see if we are triggered 
		local origSave = aZone.lastRadioTriggerValue
		if cfxZones.testZoneFlag(aZone, 				aZone.triggerRadioFlag, aZone.radioTriggerMethod, 			"lastRadioTriggerValue") then 
			if radioTrigger.verbose or aZone.verbose then 
				trigger.action.outText("+++rTrg: triggered on radio? for <".. aZone.name ..">", 30)
			end
			radioTrigger.process(aZone)
			-- now RESET both trigger and last trigger
			-- so radio can be used again
			cfxZones.setFlagValue(aZone.triggerRadioFlag, origSave, aZone)
			aZone.lastRadioTriggerValue = origSave
		end 
	end
end

--
-- Config & Start
--
function radioTrigger.readConfigZone()
	local theZone = cfxZones.getZoneByName("radioTriggerConfig") 
	if not theZone then 
		if radioTrigger.verbose then 
			trigger.action.outText("+++radioTrigger: NO config zone!", 30)
		end 
		return 
	end 
	
	radioTrigger.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if radioTrigger.verbose then 
		trigger.action.outText("+++radioTrigger: read config", 30)
	end 
end

function radioTrigger.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx radioTrigger requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx radioTrigger", radioTrigger.requiredLibs) then
		return false 
	end
	
	-- read config 
	radioTrigger.readConfigZone()
	
	-- process radioTrigger Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("radio?")
	for k, aZone in pairs(attrZones) do 
		radioTrigger.createRadioTriggerWithZone(aZone) -- process attributes
		radioTrigger.addRadioTrigger(aZone) -- add to list
	end
	
	-- start update 
	radioTrigger.update()
	
	trigger.action.outText("cfx radioTrigger v" .. radioTrigger.version .. " started.", 30)
	return true 
end

-- let's go!
if not radioTrigger.start() then 
	trigger.action.outText("cfx radioTrigger aborted: missing libraries", 30)
	radioTrigger = nil 
end