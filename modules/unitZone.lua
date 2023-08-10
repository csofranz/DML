unitZone={}
unitZone.version = "1.2.5"
unitZone.verbose = false 
unitZone.ups = 1 
unitZone.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
	Version History 
	1.0.0 - Initial Version
	1.1.0 - DML flag integration 
		  - method/uzMethod 
	1.2.0 - uzOn?, uzOff?, triggerMethod
	1.2.1 - uzDirect
	1.2.2 - uzDirectInv 
	1.2.3 - better guards for enterZone!, exitZone!, changeZone!
		  - better guards for uzOn? and uzOff?
	1.2.4 - more verbosity on uzDirect 
	1.2.5 - reading config improvement
		  
--]]--

unitZone.unitZones = {}

function unitZone.addUnitZone(theZone)
	table.insert(unitZone.unitZones, theZone)
end

function unitZone.getUnitZoneByName(aName) 
	for idx, aZone in pairs(unitZone.unitZones) do 
		if aName == aZone.name then return aZone end 
	end
	if unitZone.verbose then 
		trigger.action.outText("+++uZne: no unitZone with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

function unitZone.string2cat(filterString)

	if not filterString then return 2 end -- default ground 
	filterString = filterString:lower()
	filterString = dcsCommon.trim(filterString)

	local catNum = tonumber(filterString)
	if catNum then 
		if catNum < 0 then catNum = 0 end 
		if catNum > 4 then catNum = 4 end 
		return catNum 
	end
	
	catNum = 2 -- ground default 
	if dcsCommon.stringStartsWith(filterString, "grou") then catNum = 2 end 
	if dcsCommon.stringStartsWith(filterString, "air") then catNum = 0 end
	if dcsCommon.stringStartsWith(filterString, "hel") then catNum = 1 end
	if dcsCommon.stringStartsWith(filterString, "shi") then catNum = 3 end
	if dcsCommon.stringStartsWith(filterString, "trai") then catNum = 4 end

	return catNum
end

function unitZone.createUnitZone(theZone)
	-- start val - a range
	theZone.lookFor = cfxZones.getStringFromZoneProperty(theZone, "lookFor", "cfx no unit supplied") 
	if dcsCommon.stringEndsWith(theZone.lookFor, "*") then 
		theZone.lookForBeginsWith = true 
		theZone.lookFor = dcsCommon.removeEnding(theZone.lookFor, "*") 
	end
	
	theZone.matching = cfxZones.getStringFromZoneProperty(theZone, "matching", "group") -- group, player [, name, type]
	theZone.matching = dcsCommon.trim(theZone.matching:lower())
	if theZone.matching == "groups" then theZone.matching = "group" end -- some simplification 
	if theZone.matching == "players" then theZone.matching = "player" end -- some simplification 

	-- coalition 
	theZone.uzCoalition = cfxZones.getCoalitionFromZoneProperty(theZone, "coalition", 0) -- 0 = all
	if cfxZones.hasProperty(theZone, "uzCoalition") then 
		theZone.uzCoalition = cfxZones.getCoalitionFromZoneProperty(theZone, "uzCoalition", 0)
	end
	
	if unitZone.verbose or theZone.verbose then 
		trigger.action.outText("+++uZne: set coa " .. theZone.uzCoalition .. " for <" .. theZone.name .. ">", 30)
	end

	-- DML Method 
	theZone.uzMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "uzMethod") then 
		theZone.uzMethod = cfxZones.getStringFromZoneProperty(theZone, "uzMethod", "inc")
	end

	if cfxZones.hasProperty(theZone, "enterZone!") then 
		theZone.enterZone = cfxZones.getStringFromZoneProperty(theZone, "enterZone!", "*<none>")
	end 
	if cfxZones.hasProperty(theZone, "exitZone!") then 
		theZone.exitZone = cfxZones.getStringFromZoneProperty(theZone, "exitZone!", "*<none>")
	end 
	
	if cfxZones.hasProperty(theZone, "changeZone!") then 
		theZone.changeZone = cfxZones.getStringFromZoneProperty(theZone, "changeZone!", "*<none>")
	end 
	
	if cfxZones.hasProperty(theZone, "filterFor") then 
		local filterString = cfxZones.getStringFromZoneProperty(theZone, "filterFor", "1") -- ground 
		theZone.filterFor = unitZone.string2cat(filterString)
		if unitZone.verbose or theZone.verbose then 
			trigger.action.outText("+++uZne: filtering " .. theZone.filterFor .. " in " .. theZone.name, 30)
		end 
	end	
	
	-- uzDirect
	if cfxZones.hasProperty(theZone, "uzDirect") then
		theZone.uzDirect = cfxZones.getStringFromZoneProperty(theZone, "uzDirect", "*<none>")
	end 
	if cfxZones.hasProperty(theZone, "uzDirectInv") then
		theZone.uzDirectInv = cfxZones.getStringFromZoneProperty(theZone, "uzDirectInv", "*<none>")
	end 
	
	-- on/off flags
	theZone.uzPaused = false -- we are turned on 
	if cfxZones.hasProperty(theZone, "uzOn?") then 
		theZone.triggerOnFlag = cfxZones.getStringFromZoneProperty(theZone, "uzOn?", "*<none1>")
		theZone.lastTriggerOnValue = cfxZones.getFlagValue(theZone.triggerOnFlag, theZone)
	end 
	
	if cfxZones.hasProperty(theZone, "uzOff?") then 
		theZone.triggerOffFlag = cfxZones.getStringFromZoneProperty(theZone, "uzOff?", "*<none2>")
		theZone.lastTriggerOffValue = cfxZones.getFlagValue(theZone.triggerOffFlag, theZone)
	end 
	
	theZone.uzTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "uzTriggerMethod") then 
		theZone.uzTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "uzTriggerMethod", "change")
	end 
	
	-- now get initial zone status ?
	theZone.lastStatus = unitZone.checkZoneStatus(theZone)
	if unitZone.verbose or theZone.verbose then 
		trigger.action.outText("+++uZne: processsed unit zone " .. theZone.name, 30)
	end
	
end


--
-- process zone 
--

function unitZone.collectGroups(theZone)
	local collector = {}
	if theZone.matching == "player" then 
		-- collect all players matching coalition
		if theZone.uzCoalition == 1 or theZone.uzCoalition == 0 then 
			local allPlayers = coalition.getPlayers(1)
			for idx, pUnit in pairs(allPlayers) do 
				table.insert(collector, pUnit)
			end
		end 
		if theZone.uzCoalition == 2 or theZone.uzCoalition == 0 then 
			local allPlayers = coalition.getPlayers(2)
			for idx, pUnit in pairs(allPlayers) do 
				table.insert(collector, pUnit)
			end
		end
	elseif theZone.matching == "group" then 
		if theZone.uzCoalition == 1 or theZone.uzCoalition == 0 then 
			local allGroups = coalition.getGroups(1, theZone.filterFor)

			for idx, pUnit in pairs(allGroups) do 
				table.insert(collector, pUnit)
			end
		end 
		if theZone.uzCoalition == 2 or theZone.uzCoalition == 0 then 
			local allGroups = coalition.getGroups(2, theZone.filterFor)

			for idx, pUnit in pairs(allGroups) do 
				table.insert(collector, pUnit)
			end
		end
	else 
		trigger.action.outText("+++uZne: unknown matching: " .. theZone.matching, 30)
		return {}
	end
	
	return collector
end

function unitZone.checkZoneStatus(theZone)
	-- returns true (at least one unit found in zone)
	-- or false (no unit found in zone)
	
	-- collect all groups to inspect 
	local theGroups = unitZone.collectGroups(theZone)
	local lookFor = theZone.lookFor
	-- now see if the groups match name and then check inside status for each 
	local playerCheck = theZone.matching == "player"
	if playerCheck then 
		-- we check the names for players only 
		-- collector holds units, not groups 
		for idx, pUnit in pairs(theGroups) do 
			local puName = pUnit:getName()
			local hasMatch = false 
			if theZone.lookForBeginsWith then 
				hasMatch = dcsCommon.stringStartsWith(puName, lookFor)
			else 
				hasMatch = puName == lookFor 
			end
			if hasMatch then 
				if cfxZones.unitInZone(pUnit, theZone) then 
					return true
				end
			end
		end 
        
	else 
		-- we perform group check 
		for idx, aGroup in pairs(theGroups) do 
			local gName=aGroup:getName()
			local hasMatch = false 
			if theZone.lookForBeginsWith then 
				hasMatch = dcsCommon.stringStartsWith(gName, lookFor)
			else 
				hasMatch = gName == lookFor 
			end
			if hasMatch and aGroup:isExist() then 
				-- check all living units in zone 
				local gUnits = aGroup:getUnits()
				for idy, aUnit in pairs (gUnits) do
					--trigger.action.outText("trying " .. gName,10)
					if cfxZones.unitInZone(aUnit, theZone) then 
						return true
					end
				end
			end
		end
	end
	return false 
end

--
-- update 
--
function unitZone.bangState(theZone, newState)
	
	if theZone.changeZone then 
		cfxZones.pollFlag(theZone.changeZone, theZone.uzMethod, theZone)
	end 
	if newState then 
		if theZone.enterZone then 
			cfxZones.pollFlag(theZone.enterZone, theZone.uzMethod, theZone)
			if unitZone.verbose then 
				trigger.action.outText("+++uZone: banging enter! with <" .. theZone.uzMethod .. "> on <" .. theZone.enterZone .. "> for " .. theZone.name, 30)
			end
		end
	else 
		if theZone.exitZone then 
			cfxZones.pollFlag(theZone.exitZone, theZone.uzMethod, theZone)
			if unitZone.verbose then 
				trigger.action.outText("+++uZone: banging exit! with <" .. theZone.uzMethod .. "> on <" .. theZone.exitZone .. "> for " .. theZone.name, 30)
			end
		end 
	end
end

function unitZone.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(unitZone.update, {}, timer.getTime() + 1/unitZone.ups)
		
	for idx, aZone in pairs(unitZone.unitZones) do
		-- check if we need to pause/unpause 
		if aZone.triggerOnFlag and cfxZones.testZoneFlag(aZone, aZone.triggerOnFlag, aZone.uzTriggerMethod, "lastTriggerOnValue") then 
			if unitZone.verbose or aZone.verbose then 
				trigger.action.outText("+++uZone: turning " .. aZone.name .. " on", 30)
			end 
			aZone.uzPaused = false 
		end
		
		if aZone.triggerOffFlag and cfxZones.testZoneFlag(aZone, aZone.triggerOffFlag, aZone.uzTriggerMethod, "lastTriggerOffValue") then 
			if unitZone.verbose or aZone.verbose then 
				trigger.action.outText("+++uZone: turning " .. aZone.name .. " OFF", 30)
			end 
			aZone.uzPaused = true 
		end
		
		-- scan all zones 
		if not aZone.uzPaused then 
			local newState = unitZone.checkZoneStatus(aZone) -- returns true if at least one unit in zone 

			if newState ~= aZone.lastStatus then 
				-- bang on change! 
				unitZone.bangState(aZone, newState)
				aZone.lastStatus = newState 
			end
			
			-- output direct state suite
			if aZone.uzDirect then 
				if aZone.verbose or unitZone.verbose then 
					trigger.action.outText("+++uZone: <" .. aZone.name .. "> setting uzDirect <" .. aZone.uzDirect .. "> to ".. dcsCommon.bool2Num(newState), 30)
				end
				if newState then 
					cfxZones.setFlagValueMult(aZone.uzDirect, 1, aZone)
				else 
					cfxZones.setFlagValueMult(aZone.uzDirect, 0, aZone)
				end
			end
			if aZone.uzDirectInv then 
				local invState = not newState
				if aZone.verbose or unitZone.verbose then 
					trigger.action.outText("+++uZone: <" .. aZone.name .. "> setting INVuzDirect <" .. aZone.uzDirectInv .. "> to ".. dcsCommon.bool2Num(invState), 30)
				end
				if newState then 
					cfxZones.setFlagValueMult(aZone.uzDirectInv, 0, aZone)
				else 
					cfxZones.setFlagValueMult(aZone.uzDirectInv, 1, aZone)
				end
			end
		end 
	end
end

--
-- Config & Start
--
function unitZone.readConfigZone()
	local theZone = cfxZones.getZoneByName("unitZoneConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("unitZoneConfig")
	end 
	
	unitZone.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	unitZone.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 1)
	
	if unitZone.verbose then 
		trigger.action.outText("+++uZne: read config", 30)
	end 
end

function unitZone.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Unit Zone requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Unit Zone", unitZone.requiredLibs) then
		return false 
	end
	
	-- read config 
	unitZone.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("unitZone")
	for k, aZone in pairs(attrZones) do 
		unitZone.createUnitZone(aZone) -- process attributes
		unitZone.addUnitZone(aZone) -- add to list
	end
	
	-- start update 
	unitZone.update()
	
	trigger.action.outText("cfx Unit Zone v" .. unitZone.version .. " started.", 30)
	return true 
end

-- let's go!
if not unitZone.start() then 
	trigger.action.outText("cfx Unit Zone aborted: missing libraries", 30)
	unitZone = nil 
end

--ToDo: matching: name, name wildcard, type  
--ToDo: add 'neutral' support and add 'both' option 
--ToDo: add API 