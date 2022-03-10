unitZone={}
unitZone.version = "1.0.0"
unitZone.verbose = false 
unitZone.ups = 1 
unitZone.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
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
		cfxZones.uzCoalition = cfxZones.getCoalitionFromZoneProperty(theZone, "uzCoalition", 0)
	end

	theZone.enterZone = cfxZones.getStringFromZoneProperty(theZone, "enterZone!", "<none>")
	theZone.exitZone = cfxZones.getStringFromZoneProperty(theZone, "exitZone!", "<none>")	
	theZone.changeZone = cfxZones.getStringFromZoneProperty(theZone, "changeZone!", "<none>")
	
	if cfxZones.hasProperty(theZone, "filterFor") then 
		local filterString = cfxZones.getStringFromZoneProperty(theZone, "filterFor", "1") -- ground 
		theZone.filterFor = unitZone.string2cat(filterString)
		if unitZone.verbose then 
			trigger.action.outText("+++uZne: filtering " .. theZone.filterFor .. " in " .. theZone.name, 30)
		end 
	end	
	
	-- now get initial zone status ?
	theZone.lastStatus = unitZone.checkZoneStatus(theZone)
	if unitZone.verbose then 
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
		for idx, pUnit in pairs(theGroups) do 
			local puName=pUnit:getName()
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
		-- we perform group cehck 
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
	
	cfxZones.pollFlag(theZone.changeZone, "inc", theZone)
	if newState then 
		cfxZones.pollFlag(theZone.enterZone, "inc", theZone)
		if unitZone.verbose then 
			trigger.action.outText("+++uZone: banging enter!  on <" .. theZone.enterZone .. "> for " .. theZone.name, 30)
		end 
	else 
		cfxZones.pollFlag(theZone.exitZone, "inc", theZone)
		if unitZone.verbose then 
			trigger.action.outText("+++uZone: banging exit! on <" .. theZone.exitZone .. "> for " .. theZone.name, 30)
		end
	end
end

function unitZone.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(unitZone.update, {}, timer.getTime() + 1/unitZone.ups)
		
	for idx, aZone in pairs(unitZone.unitZones) do
		-- scan all zones 
		local newState = unitZone.checkZoneStatus(aZone)

		if newState ~= aZone.lastStatus then 
			-- bang on change! 
			unitZone.bangState(aZone, newState)
			aZone.lastStatus = newState 
		end
	end
end

--
-- Config & Start
--
function unitZone.readConfigZone()
	local theZone = cfxZones.getZoneByName("unitZoneConfig") 
	if not theZone then 
		if unitZone.verbose then 
			trigger.action.outText("+++uZne: NO config zone!", 30)
		end 
		return 
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

--ToDo: add 'neutral' support and add 'both' option 
--ToDo: add API 