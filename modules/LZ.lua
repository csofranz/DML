LZ = {}
LZ.version = "1.2.1"
LZ.verbose = false 
LZ.ups = 1 
LZ.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
LZ.LZs = {}

--[[--
	LZ - module to generate flag events when a unit lands to takes off inside 
	the zone. 
	
	Version History 
	1.0.0 - initial version 
	1.1.0 - persistence 
	1.2.0 - dcs 2024-07-11 and dcs 2024-07-22 updates (new events)
	1.2.1 - theZone --> aZone typo at input management 
--]]--

function LZ.addLZ(theZone)
	table.insert(LZ.LZs, theZone)
end

function LZ.getLZByName(aName) 
	for idx, aZone in pairs(LZ.LZs) do 
		if aName == aZone.name then return aZone end 
	end
	if LZ.verbose then 
		trigger.action.outText("+++LZ: no LZ with name <" .. aName ..">", 30)
	end 
	
end

--
-- read zone 
-- 
function LZ.createLZWithZone(theZone)
	if cfxZones.hasProperty(theZone, "landed!") then
		theZone.lzLanded = cfxZones.getStringFromZoneProperty(theZone, "landed!", "*<none>")
	end 

	if cfxZones.hasProperty(theZone, "departed!") then
		theZone.lzDeparted = cfxZones.getStringFromZoneProperty(theZone, "departed!", "*<none>")
	end
	
	-- who to look for 
	theZone.coalition = cfxZones.getCoalitionFromZoneProperty(theZone, "coalition", 0)
	-- units / groups / types 
	if cfxZones.hasProperty(theZone, "group") then 
		theZone.lzGroups = cfxZones.getStringFromZoneProperty(theZone, "group", "<none>")
		theZone.lzGroups = dcsCommon.string2Array(theZone.lzGroups, ",", true)
	elseif cfxZones.hasProperty(theZone, "groups") then 
		theZone.lzGroups = cfxZones.getStringFromZoneProperty(theZone, "groups", "<none>")
		theZone.lzGroups = dcsCommon.string2Array(theZone.lzGroups, ",", true)
	elseif cfxZones.hasProperty(theZone, "type") then 
		theZone.lzTypes = cfxZones.getStringFromZoneProperty(theZone, "type", "ALL")
		theZone.lzTypes = dcsCommon.string2Array(theZone.lzTypes, ",", true)
	elseif cfxZones.hasProperty(theZone, "types") then
		theZone.lzTypes = cfxZones.getStringFromZoneProperty(theZone, "types", "ALL")
		theZone.lzTypes = dcsCommon.string2Array(theZone.lzTypes, ",", true)
	elseif cfxZones.hasProperty(theZone, "unit") then 
		theZone.lzUnits = cfxZones.getStringFromZoneProperty(theZone, "unit", "none")
		theZone.lzUnits = dcsCommon.string2Array(theZone.lzUnits, ",", true)
	elseif cfxZones.hasProperty(theZone, "units") then
		theZone.lzUnits = cfxZones.getStringFromZoneProperty(theZone, "units", "none")
		theZone.lzUnits = dcsCommon.string2Array(theZone.lzUnits, ",", true)
	end	

	theZone.lzPlayerOnly = cfxZones.getBoolFromZoneProperty(theZone, "playerOnly", false)

	-- output method
	theZone.lzMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "outputMethod") then 
		theZone.lzMethod = cfxZones.getStringFromZoneProperty(theZone, "outputMethod", "inc")
	end 
	
	-- trigger method
	theZone.lzTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "lzTriggerMethod", "change")
	if cfxZones.hasProperty(theZone, "triggerMethod") then 
		theZone.lzTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	end 
	
	
	-- pause / unpause 
	theZone.lzIsPaused = cfxZones.getBoolFromZoneProperty(theZone, "isPaused", false)
	
	if cfxZones.hasProperty(theZone, "pause?") then 
		theZone.lzPause = cfxZones.getStringFromZoneProperty(theZone, "pause?", "*<none>")
		theZone.lzLastPause = cfxZones.getFlagValue(theZone.lzPause, theZone)
	end
	
	if cfxZones.hasProperty(theZone, "continue?") then 
		theZone.lzContinue = cfxZones.getStringFromZoneProperty(theZone, "continue?", "*<none>")
		theZone.lzLastContinue = cfxZones.getFlagValue(theZone.lzContinue, theZone)
	end
	
	if LZ.verbose or theZone.verbose then 
		trigger.action.outText("+++LZ: new LZ <".. theZone.name ..">", 30)
	end

	trigger.action.outText("zone <" .. theZone.name .. "> type of radius is <" .. type(theZone.radius) .. ">, val = " .. tonumber(theZone.radius), 30)
end

function LZ.nameMatchForArray(theName, theArray, wildcard)
	theName = dcsCommon.trim(theName)
	if not theName then return false end 
	if not theArray then return false end
	theName = string.upper(theName) -- case insensitive 
	
	-- trigger.action.outText("enter name match with <" .. theName .. "> look for match in <" .. dcsCommon.array2string(theArray) .. "> and wc <" .. wildcard .. ">", 30)
	for idx, entry in pairs(theArray) do
		
		if wildcard and dcsCommon.stringEndsWith(entry, wildcard) then 
			entry = dcsCommon.removeEnding(entry, wildcard)
			-- trigger.action.outText("trying to WC-match <" .. theName .. "> with <" .. entry .. ">", 30)
			if dcsCommon.stringStartsWith(theName, entry) then 
				-- theName "hi there" matches wildcarded entry "hi*"
				return true 
			end
		else 
			-- trigger.action.outText("trying to simple-match <" .. theName .. "> with <" .. entry .. ">", 30)
			if theName == entry then 
				return true 
			end
		end
	end
--	trigger.action.outText ("no match for <" .. theName .. ">", 30)
	return false 
end

--
-- Misc Processing
--
function LZ.unitIsInterestingForZone(theUnit, theZone)
	
	-- see if zone is interested in this unit.
	if theZone.isPaused then 
		return false 
	end 

	if theZone.lzPlayerOnly then 
		if not dcsCommon.isPlayerUnit(theUnit) then 
			if theZone.verbose or LZ.verbose then
				trigger.action.outText("+++LZ: unit <" .. theUnit:getName() .. "> arriving/departing <" .. theZone.name .. "> is not a player unit", 30)
			end
			return false 
		else 
			-- trigger.action.outText("player match!", 30)
		end
	end
	
	if theZone.coalition > 0 then 
		local theGroup = theUnit:getGroup()
		local coa = theGroup:getCoalition()
		if coa ~= theZone.coalition then
			if theZone.verbose or LZ.verbose then
				trigger.action.outText("+++LZ: unit <" .. theUnit:getName() .. "> arriving/departing <" .. theZone.name .. "> does not match coa <" .. theZone.coalition .. ">", 30)
			end
			return false 
		end 
	end
	-- if we get here, we are filtered for coa and player 
	if theZone.lzUnits then 
		local theName = theUnit:getName()
		return LZ.nameMatchForArray(theName, theZone.lzUnits, "*")
		
	elseif theZone.lzGroups then
		local theGroup = theUnit:getGroup()
		local theName = theGroup:getName()
		return LZ.nameMatchForArray(theName, theZone.lzGroups, "*")
		
	elseif theZone.lzTypes then 
		local theType = theUnit:getTypeName()
		local theGroup = theUnit:getGroup()
		local cat = theGroup:getCategory() -- can't trust unit:getCategory
		local coa = theGroup:getCoalition() 
		for idx, aType in pairs (theZone.lzTypes) do 

			if aType == "ANY" or aType == "ALL" then 
				return true
			
			elseif aType == "HELO" or aType == "HELICOPTER" or aType == "HELICOPTERS" or aType == "HELOS" then 
				if cat == 1 then 
					return true  
				end
			elseif aType == "PLANE" or aType == "PLANES" then 
				if cat == 0 then 
					return true 
				end
			else 
				if theType == aType then 
					return true 
				end 
			end
		end -- for all types 

		return false -- not a single match
	else 
		-- we can return true since player and coa mismatch 
		-- have already been filtered 

		return true -- theZone.coalition == coa end
	end
	
	trigger.action.outText("+++LZ: unknown attribute check for <" .. theZone.name .. ">", 30)
	return false
end


--
-- Event Handling
--
function LZ:onEvent(event)
	-- make sure we have an initiator 
	if not event.initiator then return end 
	
    -- only interested in S_EVENT_TAKEOFF and  events
    if event.id ~= world.event.S_EVENT_TAKEOFF and 
	   event.id ~= world.event.S_EVENT_LAND and 
	   event.id ~= world.event.S_EVENT_RUNWAY_TAKEOFF and 
	   event.id ~= world.event.S_EVENT_RUNWAY_TOUCH then
        return
    end
					
	local theUnit = event.initiator
	if not Unit.isExist(theUnit) then return end 
	local p = theUnit:getPoint()

    for idx, aZone in pairs(LZ.LZs) do 
		-- see if inside the zone 
		if LZ.verbose then 
			trigger.action.outText("+++LZ: zone <" .. aZone.name .. "> for unit <" .. theUnit:getName() .. "> proccing", 30)
		end 
		if true then return end 
		local inZone, percent, dist = cfxZones.pointInZone(p, aZone)
		if inZone then 
			-- see if this unit interests us at all 
			if LZ.unitIsInterestingForZone(theUnit, aZone) then 
				-- interesting unit in zone triggered the event 
				if aZone.lzDeparted and 
					(event.id ==  world.event.S_EVENT_TAKEOFF or 
					 event.id == world.event.S_EVENT_RUNWAY_TAKEOFF)
				then 
					if LZ.verbose or aZone.verbose then 
						trigger.action.outText("+++LZ: detected departure from <" .. aZone.name .. ">", 30)
					end
					cfxZones.pollFlag(aZone.lzDeparted, aZone.lzMethod, aZone)
				end
				
				if aZone.lzLanded and 
				   (event.id == world.event.S_EVENT_LAND or 
				    event.id == world.event.S_EVENT_RUNWAY_TOUCH)
				then
					if LZ.verbose or aZone.verbose then 
						trigger.action.outText("+++LZ: detected landing in <" .. aZone.name .. ">", 30)
					end
					cfxZones.pollFlag(aZone.lzLanded, aZone.lzMethod, aZone)
				end
			end -- if interesting
		else 
			if LZ.verbose or aZone.verbose then 
				--trigger.action.outText("+++LZ: unit <" .. theUnit:getName() .. "> not in zone <" .. aZone.name .. ">", 30)
			end
		
		end -- if in zone 
    end -- end for 
end

--
-- Update 
--
function LZ.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(LZ.update, {}, timer.getTime() + 1/LZ.ups)
		
	for idx, aZone in pairs(LZ.LZs) do
		-- see if we are being paused or unpaused 
		if cfxZones.testZoneFlag(aZone, aZone.lzPause, aZone.LZTriggerMethod, "lzLastPause") then 
			if LZ.verbose or aZone.verbose then 
				trigger.action.outText("+++LZ: triggered pause? for <".. aZone.name ..">", 30)
			end
			aZone.isPaused = true 
		end 
		
		if cfxZones.testZoneFlag(aZone, aZone.lzContinue, aZone.LZTriggerMethod, "lzLastContinue") then 
			if LZ.verbose or aZone.verbose then 
				trigger.action.outText("+++LZ: triggered continue? for <".. aZone.name ..">", 30)
			end
			aZone.isPaused = false 
		end 
	end
	
end

--
-- LOAD / SAVE 
-- 
function LZ.saveData()
	local theData = {}
	local allLZ = {}
	for idx, theLZ in pairs(LZ.LZs) do 
		local theName = theLZ.name 
		local LZData = {}
 		LZData.isPaused = theLZ.isPaused
		
		allLZ[theName] = LZData 
	end
	theData.allLZ = allLZ
	return theData
end

function LZ.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("LZ")
	if not theData then 
		if LZ.verbose then 
			trigger.action.outText("+++LZ persistence: no save data received, skipping.", 30)
		end
		return
	end
	
	local allLZ = theData.allLZ
	if not allLZ then 
		if LZ.verbose then 
			trigger.action.outText("+++LZ persistence: no LZ data, skipping", 30)
		end		
		return
	end
	
	for theName, theData in pairs(allLZ) do 
		local theLZ = LZ.getLZByName(theName)
		if theLZ then 
			theLZ.isPaused = theData.isPaused
		else 
			trigger.action.outText("+++LZ: persistence: cannot synch LZ <" .. theName .. ">, skipping", 40)
		end
	end
end

--
-- Config & Start
--
function LZ.readConfigZone()
	local theZone = cfxZones.getZoneByName("LZConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("LZConfig")
		if LZ.verbose then 
			trigger.action.outText("+++LZ: NO config zone!", 30)
		end 
	end 
	
	LZ.lzCooldown = cfxZones.getNumberFromZoneProperty(theZone, "cooldown", 20)
	LZ.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if LZ.verbose then 
		trigger.action.outText("+++LZ: read config", 30)
	end 
end

function LZ.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx LZ requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx LZ", LZ.requiredLibs) then
		return false 
	end
	
	-- read config 
	LZ.readConfigZone()
	
	-- process LZ Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("lz")
	for k, aZone in pairs(attrZones) do 
		LZ.createLZWithZone(aZone) -- process attributes
		LZ.addLZ(aZone) -- add to list
	end
	
	-- connect event handler 
	world.addEventHandler(LZ)
	
	-- load any saved data 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = LZ.saveData
		persistence.registerModule("LZ", callbacks)
		-- now load my data 
		LZ.loadData()
	end
	
	-- start update 
	LZ.update()
	
	trigger.action.outText("cfx LZ v" .. LZ.version .. " started.", 30)
	return true 
end

-- let's go!
if not LZ.start() then 
	trigger.action.outText("cfx LZ aborted: missing libraries", 30)
	LZ = nil 
end