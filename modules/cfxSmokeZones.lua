cfxSmokeZone = {}
cfxSmokeZone.version = "1.1.3" 
cfxSmokeZone.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
	Version History
 1.0.0 - initial version
 1.0.1 - added removeSmokeZone
 1.0.2 - added altitude
 1.0.3 - added paused attribute 
       - added f? attribute --> onFlag 
	   - broke out startSmoke 
 1.0.4 - startSmoke? synonym
	   - alphanum DML flag upgrade 
	   - random color support 
 1.1.0 - Watchflag upgrade 
 1.1.1 - stopSmoke? input 
 1.1.2 - 'agl', 'alt' synonymous for altitude to keep in line with fireFX
 1.1.3 - corrected smokeTriggerMethod in zone definition
 
--]]--
cfxSmokeZone.smokeZones = {}
cfxSmokeZone.updateDelay = 5 * 60 -- every 5 minutes 

function cfxSmokeZone.processSmokeZone(aZone)
	local rawVal = cfxZones.getStringFromZoneProperty(aZone, "smoke", "green")
	rawVal = rawVal:lower()
	local theColor = 0 
	if rawVal == "red" or rawVal == "1" then theColor = 1 end 
	if rawVal == "white" or rawVal == "2" then theColor = 2 end 
	if rawVal == "orange" or rawVal == "3" then theColor = 3 end 
	if rawVal == "blue" or rawVal == "4" then theColor = 4 end 
	if rawVal == "?" or rawVal == "random" or rawVal == "rnd" then 
		theColor = dcsCommon.smallRandom(5) - 1
	end

	aZone.smokeColor = theColor
	aZone.smokeAlt = cfxZones.getNumberFromZoneProperty(aZone, "altitude", 1)
	if cfxZones.hasProperty(aZone, "alt") then 
		aZone.smokeAlt = cfxZones.getNumberFromZoneProperty(aZone, "alt", 1)
	elseif cfxZones.hasProperty(aZone, "agl") then 
		aZone.smokeAlt = cfxZones.getNumberFromZoneProperty(aZone, "agl", 1)
	end
	
	-- paused 
	aZone.paused = cfxZones.getBoolFromZoneProperty(aZone, "paused", false)
	
	-- f? query flags 
	if cfxZones.hasProperty(aZone, "f?") then 
		aZone.onFlag = cfxZones.getStringFromZoneProperty(aZone, "f?", "*<none>")
	elseif cfxZones.hasProperty(aZone, "startSmoke?") then 
		aZone.onFlag = cfxZones.getStringFromZoneProperty(aZone, "startSmoke?", "none")
	end
	
	if aZone.onFlag then 
		aZone.onFlagVal = cfxZones.getFlagValue(aZone.onFlag, aZone) -- save last value
	end
	
	if cfxZones.hasProperty(aZone, "stopSmoke?") then 
		aZone.smkStopFlag = cfxZones.getStringFromZoneProperty(aZone, "stopSmoke?", "<none>")
		aZone.smkLastStopFlag = cfxZones.getFlagValue(aZone.smkStopFlag, aZone)
	end
	
	-- watchflags:
	-- triggerMethod
	aZone.smokeTriggerMethod = cfxZones.getStringFromZoneProperty(aZone, "triggerMethod", "change")

	if cfxZones.hasProperty(aZone, "smokeTriggerMethod") then 
		aZone.smokeTriggerMethod = cfxZones.getStringFromZoneProperty(aZone, "smokeTriggerMethod", "change")
	end
	
end

function cfxSmokeZone.addSmokeZone(aZone)
	table.insert(cfxSmokeZone.smokeZones, aZone)
end

function cfxSmokeZone.addSmokeZoneWithColor(aZone, aColor, anAltitude, paused, onFlag)
	if not aColor then aColor = 0 end -- default green 
	if not anAltitude then anAltitude = 5 end 
	if not aZone then return end 
	if not paused then paused = false end 
	
	aZone.smokeColor = aColor
	aZone.smokeAlt = anAltitude
	aZone.paused = paused 
	
	if onFlag then 
		aZone.onFlag = onFlag 
		aZone.onFlagVal = cfxZones.getFlagValue(aZone.onFlag, aZone) -- trigger.misc.getUserFlag(onFlag)
	end
	
	cfxSmokeZone.addSmokeZone(aZone) -- add to update loop
	if not paused then 
		cfxSmokeZone.startSmoke(aZone)
	end
	
end

function cfxSmokeZone.startSmoke(aZone)
	if type(aZone) == "string" then 
		aZone = cfxZones.getZoneByName(aZone) 
	end
	if not aZone then return end 
	if not aZone.smokeColor then return end 
	aZone.paused = false 
	cfxZones.markZoneWithSmoke(aZone, 0, 0, aZone.smokeColor, aZone.smokeAlt)
end

function cfxSmokeZone.removeSmokeZone(aZone)
	if type(aZone) == "string" then 
		aZone = cfxZones.getZoneByName(aZone) 
	end
	if not aZone then return end 
	
	-- now create new table 
	local filtered = {}
	for idx, theZone in pairs(cfxSmokeZone.smokeZones) do 
		if theZone ~= aZone then 
			table.insert(filtered, theZone)
		end 
	end
	cfxSmokeZone.smokeZones = filtered 
end


function cfxSmokeZone.update()
	-- call me in a couple of minutes to 'rekindle'
	timer.scheduleFunction(cfxSmokeZone.update, {}, timer.getTime() + cfxSmokeZone.updateDelay)
	
	-- re-smoke all zones after delay
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
				aZone.paused = true -- will no longer re-smoke on update
			end
		end
	end
end

function cfxSmokeZone.start()
	if not dcsCommon.libCheck("cfx Smoke Zones", cfxSmokeZone.requiredLibs) then
		return false 
	end
	
	-- collect all zones with 'smoke' attribute 
	-- collect all spawn zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("smoke")
	
	-- now create a smoker for all, add them to updater,
	-- smoke all that aren't paused 
	for k, aZone in pairs(attrZones) do 
		cfxSmokeZone.processSmokeZone(aZone) -- process attribute and add to zone
		cfxSmokeZone.addSmokeZone(aZone) -- remember it so we can smoke it
	end

	-- start update loop
	cfxSmokeZone.update() -- also starts all unpaused 
	
	-- start check loop in one second 
	timer.scheduleFunction(cfxSmokeZone.checkFlags, {}, timer.getTime() + 1)
	
	-- say hi
	trigger.action.outText("cfx Smoke Zones v" .. cfxSmokeZone.version .. " started.", 30)
	return true 
end

-- let's go 
if not cfxSmokeZone.start() then 
	trigger.action.outText("cf/x Smoke Zones aborted: missing libraries", 30)
	cfxSmokeZone = nil 
end