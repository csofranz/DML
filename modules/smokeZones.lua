cfxSmokeZone = {}
cfxSmokeZone.version = "3.0.1" 
cfxSmokeZone.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[-- Copyright (c) 2021-2025 by Christian Franz 
 Version History
 3.0.0 - now supports immediate smoke stop 
	   - supports persistence 
	   - code cleanup 
 3.0.1 - fixed data load error 
--]]--
cfxSmokeZone.smokeZones = {}
cfxSmokeZone.updateDelay = 5 * 60 -- every 5 minutes 

function cfxSmokeZone.processSmokeZone(aZone)
	aZone.smokeColor = aZone:getSmokeColorNumberFromZoneProperty("smoke", "green")--theColor
	aZone.smokeAlt = aZone:getNumberFromZoneProperty("altitude", 1)
	aZone.smokeName = aZone.name .. "-s-" .. dcsCommon.numberUUID()
	if aZone:hasProperty("alt") then 
		aZone.smokeAlt = aZone:getNumberFromZoneProperty("alt", 1)
	elseif aZone:hasProperty("agl") then 
		aZone.smokeAlt = aZone:getNumberFromZoneProperty("agl", 1)
	end
	aZone.paused = aZone:getBoolFromZoneProperty("paused", false)	 
	aZone.onFlag = aZone:getStringFromZoneProperty("startSmoke?", "none")
	if aZone.onFlag then 
		aZone.onFlagVal = aZone:getFlagValue(aZone.onFlag) -- save last value
	end
	if aZone:hasProperty("stopSmoke?") then 
		aZone.smkStopFlag = aZone:getStringFromZoneProperty("stopSmoke?", "<none>")
		aZone.smkLastStopFlag = aZone:getFlagValue(aZone.smkStopFlag)
	end
	aZone.smokeTriggerMethod = aZone:getStringFromZoneProperty( "triggerMethod", "change")
	if aZone:hasProperty("smokeTriggerMethod") then 
		aZone.smokeTriggerMethod = aZone:getStringFromZoneProperty( "smokeTriggerMethod", "change")
	end
end

function cfxSmokeZone.addSmokeZone(aZone)
	table.insert(cfxSmokeZone.smokeZones, aZone)
end

function cfxSmokeZone.getSmokeZoneNamed(aName)
	if not aName then return end 
	local aName = string.upper(aName)
	for idx, theZone in pairs(cfxSmokeZone.smokeZones) do 
		if theZone.name == aName then return theZone end
	end 
	return nil 
end

function cfxSmokeZone.startSmoke(aZone)
	if not aZone then return end 
	if not aZone.smokeColor then return end 
	-- remove old smoke if running 
	if cfxSmokeZone.verbose or aZone.verbose then trigger.action.outText("+++smk: starting zone <" .. aZone.name .. "> smoke with name <" .. aZone.smokeName .. ">", 30) end
	trigger.action.effectSmokeStop(aZone.smokeName)
	aZone.paused = false 
	aZone:markZoneWithSmoke(0, 0, aZone.smokeColor, aZone.smokeAlt, aZone.smokeName)
end

function cfxSmokeZone.stopSmoke(aZone)
	if not aZone then return end 
	if cfxSmokeZone.verbose or aZone.verbose then trigger.action.outText("+++smk: ENDING zone <" .. aZone.name .. ">'s smoke with name <" .. aZone.smokeName .. ">", 30) end
	trigger.action.effectSmokeStop(aZone.smokeName)
	aZone.paused = true 
end 

function cfxSmokeZone.removeSmokeZone(aZone)
	if not aZone then return end 	
	local filtered = {}
	for idx, theZone in pairs(cfxSmokeZone.smokeZones) do 
		if theZone ~= aZone then 
			table.insert(filtered, theZone)
		end 
	end
	cfxSmokeZone.smokeZones = filtered 
end

function cfxSmokeZone.update()
	-- 'rekindle' all smoke after 5 mins
	timer.scheduleFunction(cfxSmokeZone.update, {}, timer.getTime() + cfxSmokeZone.updateDelay)
	for idx, aZone in pairs(cfxSmokeZone.smokeZones) do 
		if not aZone.paused and aZone.smokeColor then 
			cfxSmokeZone.startSmoke(aZone)
		end
	end
end

function cfxSmokeZone.checkFlags()
	timer.scheduleFunction(cfxSmokeZone.checkFlags, {}, timer.getTime() + 1) -- every second 
	for idx, aZone in pairs(cfxSmokeZone.smokeZones) do 
		if aZone.paused and aZone.onFlagVal then 
			-- see if this changed 
			if cfxZones.testZoneFlag(aZone, aZone.onFlag, aZone.smokeTriggerMethod, "onFlagVal") then
				cfxSmokeZone.startSmoke(aZone)
			end 		
		end
		if aZone.smkStopFlag then 
			if cfxZones.testZoneFlag(aZone, aZone.smkStopFlag, aZone.smokeTriggerMethod, "smkLastStopFlag") then 
				cfxSmokeZone.stopSmoke(aZone)
			end
		end
	end
end

function cfxSmokeZone.saveData()
	local theData = {}
	for idx, theZone in pairs(cfxSmokeZone.smokeZones) do 
		local entry = {}
		entry.paused = theZone.paused
		theData[theZone.name] = entry
	end 
	-- save current log. simple clone 
	return theData, cfxSmokeZone.sharedData -- second val only if shared 
end

function cfxSmokeZone.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("smokeZones", cfxSmokeZone.sharedData)
	if not theData then 
		if cfxSmokeZone.verbose then trigger.action.outText("+++smk: no save date received, skipping.", 30) end
		return
	end
	for name, entry in pairs(theData) do 
		local theZone = cfxSmokeZone.getSmokeZoneNamed(name)
		if theZone then 
			theZone.paused = entry.paused
		end
	end
end

function cfxSmokeZone.start()
	if not dcsCommon.libCheck("cfx Smoke Zones", cfxSmokeZone.requiredLibs) then return false end
	local attrZones = cfxZones.getZonesWithAttributeNamed("smoke")
		for k, aZone in pairs(attrZones) do 
		cfxSmokeZone.processSmokeZone(aZone)
		cfxSmokeZone.addSmokeZone(aZone)
	end	
	if persistence then -- sign up for persistence 
		callbacks = {}
		callbacks.persistData = cfxSmokeZone.saveData
		persistence.registerModule("smokeZones", callbacks)
		-- now load my data 
		cfxSmokeZone.loadData() -- will start with update 
	end
	-- start update and checkflag loops 
	cfxSmokeZone.update() -- also starts all unpaused 
	timer.scheduleFunction(cfxSmokeZone.checkFlags, {}, timer.getTime() + 1)
	trigger.action.outText("cfx smoke zones v" .. cfxSmokeZone.version .. " started.", 30)
	return true 
end

-- let's go 
if not cfxSmokeZone.start() then 
	trigger.action.outText("cf/x Smoke Zones failed to start", 30)
	cfxSmokeZone = nil 
end