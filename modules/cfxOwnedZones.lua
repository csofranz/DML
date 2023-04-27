cfxOwnedZones = {}
cfxOwnedZones.version = "2.0.0"
cfxOwnedZones.verbose = false 
cfxOwnedZones.announcer = true 
cfxOwnedZones.name = "cfxOwnedZones" 
--[[-- VERSION HISTORY

2.0.0 - factored from cfxOwnedZones 1.x, separating out production

--]]--
cfxOwnedZones.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	             -- pretty stupid to check for this since we 
				 -- need common to invoke the check, but anyway
	"cfxZones", -- Zones, of course 
}

cfxOwnedZones.zones = {}
cfxOwnedZones.ups = 1
cfxOwnedZones.initialized = false 
--[[--
 owned zones is a module that managers conquerable zones and keeps a record
 of who owns the zone based on rules  

 
 *** EXTENTDS ZONES ***, so compatible with cfxZones, pilotSafe (limited airframes), may conflict with FARPZones 


 owned zones are identified by the 'owner' property. It can be initially set to nothing (default), NEUTRAL, RED or BLUE

 when a zone changes hands, a callback can be installed to be told of that fact
 callback has the format (zone, newOwner, formerOwner) with zone being the Zone, and new owner and former owners
 --]]--
 
cfxOwnedZones.conqueredCallbacks = {}

--
-- callback handling
--

function cfxOwnedZones.addCallBack(conqCallback)
	local cb = {}
	cb.callback = conqCallback -- we use this so we can add more data later
	cfxOwnedZones.conqueredCallbacks[conqCallback] = cb
	
end

function cfxOwnedZones.invokeConqueredCallbacks(aZone, newOwner, lastOwner)
	for key, cb in pairs (cfxOwnedZones.conqueredCallbacks) do 
		cb.aZone = aZone -- set these up for if we need them later
		cb.newOwner = newOwner
		cb.lastOwner = lastOwner
		-- invoke callback
		cb.callback(aZone, newOwner, lastOwner)
	end
end

function cfxOwnedZones.side2name(theSide)
	if theSide == 1 then return "REDFORCE" end
	if theSide == 2 then return "BLUEFORCE" end
	return "Neutral"
end

function cfxOwnedZones.conqTemplate(aZone, newOwner, lastOwner) 
	if true then return end -- do not output

	if lastOwner == 0 then 
		trigger.action.outText(cfxOwnedZones.side2name(newOwner) .. " have taken possession zone " .. aZone.name, 30)
		return 
	end
	
	trigger.action.outText("Zone " .. aZone.name .. " was taken by ".. cfxOwnedZones.side2name(newOwner) .. " from " .. cfxOwnedZones.side2name(lastOwner), 30)
end

--
-- M I S C
--

function cfxOwnedZones.drawZoneInMap(aZone)
	-- will save markID in zone's markID
	if aZone.markID then 
		trigger.action.removeMark(aZone.markID)
	end 
	if aZone.hidden then return end 
	
	local lineColor = {1.0, 0, 0, 1.0} -- red 
	local fillColor = {1.0, 0, 0, 0.2} -- red 
	local owner = aZone.owner -- cfxOwnedZones.getOwnerForZone(aZone)
	if owner == 2 then 
		lineColor = {0.0, 0, 1.0, 1.0}
		fillColor = {0.0, 0, 1.0, 0.2}
	elseif owner == 0 then 
		lineColor = {0.8, 0.8, 0.8, 1.0}
		fillColor = {0.8, 0.8, 0.8, 0.2}
	end
	
	local theShape = 2 -- circle
	local markID = dcsCommon.numberUUID()

	trigger.action.circleToAll(-1, markID, aZone.point, aZone.radius, lineColor, fillColor, 1, true, "")
	aZone.markID = markID 
	
end

function cfxOwnedZones.getOwnedZoneByName(zName)
	for zKey, theZone in pairs (cfxOwnedZones.zones) do 
		if theZone.name == zName then return theZone end 
	end
	return nil
end

function cfxOwnedZones.addOwnedZone(aZone)
	local owner = aZone.owner --cfxZones.getCoalitionFromZoneProperty(aZone, "owner", 0) -- is already readm read it again
	
	if cfxZones.hasProperty(aZone, "conquered!") then 
		aZone.conqueredFlag = cfxZones.getStringFromZoneProperty(aZone, "conquered!", "*<cfxnone>")
	end
	if cfxZones.hasProperty(aZone, "redCap!") then 
		aZone.redCap = cfxZones.getStringFromZoneProperty(aZone, "redCap!", "none")
	end
	if cfxZones.hasProperty(aZone, "redLost!") then 
		aZone.redLost = cfxZones.getStringFromZoneProperty(aZone, "redLost!", "none")
	end
	if cfxZones.hasProperty(aZone, "blueCap!") then 
		aZone.blueCap = cfxZones.getStringFromZoneProperty(aZone, "blueCap!", "none")
	end
	if cfxZones.hasProperty(aZone, "blueLost!") then 
		aZone.blueLost = cfxZones.getStringFromZoneProperty(aZone, "blueLost!", "none")
	end
	if cfxZones.hasProperty(aZone, "neutral!") then 
		aZone.neutralCap = cfxZones.getStringFromZoneProperty(aZone, "neutral!", "none")
	end
	if cfxZones.hasProperty(aZone, "ownedBy") then 
		aZone.ownedBy = cfxZones.getStringFromZoneProperty(aZone, "ownedBy", "none")
	end

	aZone.ownedTriggerMethod = cfxZones.getStringFromZoneProperty(aZone, "triggerMethod", "change")
	if cfxZones.hasProperty(aZone, "ownedTriggerMethod") then 
		aZone.ownedTriggerMethod = cfxZones.getStringFromZoneProperty(aZone, "ownedTriggerMethod", "change")
	end
		
	aZone.unbeatable = cfxZones.getBoolFromZoneProperty(aZone, "unbeatable", false)
	
	aZone.hidden = cfxZones.getBoolFromZoneProperty(aZone, "hidden", false)
	cfxOwnedZones.zones[aZone] = aZone 
	cfxOwnedZones.drawZoneInMap(aZone)
end

--
-- U P D A T E 
--

function cfxOwnedZones.bangNeutral(value)
	if not cfxOwnedZones.neutralTriggerFlag then return end 
	local newVal = trigger.misc.getUserFlag(cfxOwnedZones.neutralTriggerFlag) + value 
	trigger.action.setUserFlag(cfxOwnedZones.neutralTriggerFlag, newVal)
end

function cfxOwnedZones.bangRed(value)
	if not cfxOwnedZones.redTriggerFlag then return end 
	local newVal = trigger.misc.getUserFlag(cfxOwnedZones.redTriggerFlag) + value 
	trigger.action.setUserFlag(cfxOwnedZones.redTriggerFlag, newVal)
end

function cfxOwnedZones.bangBlue(value)
	if not cfxOwnedZones.blueTriggerFlag then return end 
	local newVal = trigger.misc.getUserFlag(cfxOwnedZones.blueTriggerFlag) + value 
	trigger.action.setUserFlag(cfxOwnedZones.blueTriggerFlag, newVal)
end

function cfxOwnedZones.bangSide(theSide, value)
	if theSide == 2 then 
		cfxOwnedZones.bangBlue(value)
		return 
	end 
	if theSide == 1 then 
		cfxOwnedZones.bangRed(value)
		return 
	end 
	cfxOwnedZones.bangNeutral(value)
end

function cfxOwnedZones.zoneConquered(aZone, theSide, formerOwner) -- 0 = neutral 1 = RED 2 = BLUE 
	local who = "REDFORCE"
	if theSide == 2 then who = "BLUEFORCE" 
	elseif theSide == 0 then who = "NEUTRAL" end
	
	if cfxOwnedZones.announcer then 
		if theSide == 0 then 
			trigger.action.outText(aZone.name .. " has become NEUTRAL", 30)
		else 
			trigger.action.outText(who .. " have secured zone " .. aZone.name, 30)
		end
		aZone.owner = theSide -- just to be sure 
		-- play different sounds depending on who's won
		if theSide == 1 then 
			trigger.action.outSoundForCoalition(1, cfxOwnedZones.winSound)
			trigger.action.outSoundForCoalition(2, cfxOwnedZones.loseSound)
		elseif theSide == 2 then  
			trigger.action.outSoundForCoalition(2, cfxOwnedZones.winSound)
			trigger.action.outSoundForCoalition(1, cfxOwnedZones.loseSound)
		else 
			-- no sound played, new owner is neutral 
		end
	end 

	if aZone.conqueredFlag then 
		cfxZones.pollFlag(aZone.conqueredFlag, "inc", aZone)
	end 
	
	if theSide == 1 and aZone.redCap then 
		cfxZones.pollFlag(aZone.redCap, "inc", aZone)
	end
	
	if formerOwner == 1 and aZone.redLost then 
		cfxZones.pollFlag(aZone.redLost, "inc", aZone)
	end
	
	if theSide == 2 and aZone.blueCap then 
		cfxZones.pollFlag(aZone.blueCap, "inc", aZone)
	end
	
	if formerOwner == 2 and aZone.blueLost then 
		cfxZones.pollFlag(aZone.blueLost, "inc", aZone)
	end
	
	if theSide == 0 and aZone.neutralCap then 
		cfxZones.pollFlag(aZone.neutralCap, "inc", aZone)
	end
	
	-- invoke callbacks now
	cfxOwnedZones.invokeConqueredCallbacks(aZone, theSide, formerOwner)
	
	-- bang! flag support 
	cfxOwnedZones.bangSide(theSide, 1) -- winner 
	cfxOwnedZones.bangSide(formerOwner, -1) -- loser 
	
	-- update map
	cfxOwnedZones.drawZoneInMap(aZone) -- update status in map. will erase previous version 

end

function cfxOwnedZones.update()
	-- to speed this up we might only want to check the first unit 
	-- in group, and if inside, count the entire group as inside 
	-- new. unit counting update 
	cfxOwnedZones.updateSchedule = timer.scheduleFunction(cfxOwnedZones.update, {}, timer.getTime() + 1/cfxOwnedZones.ups)
	-- iterate all groups and their units to count how many 
	-- units are in each zone 
	for idz, theZone in pairs(cfxOwnedZones.zones) do 
		theZone.numRed = 0
		theZone.numBlue = 0 
		-- count red units
		local allRed = coalition.getGroups(1, Group.Category.GROUND)
		for idx, aGroup in pairs(allRed) do 
			if Group.isExist(aGroup) then 
				if cfxOwnedZones.fastEval then 
					-- we only check first unit that is alive
					local theUnit = dcsCommon.getGroupUnit(aGroup)
					if theUnit and cfxZones.unitInZone(theUnit, theZone) then
						theZone.numRed = theZone.numRed + aGroup:getSize()
					end
				else 
					local allUnits = aGroup:getUnits() 
					for idy, theUnit in pairs(allUnits) do 
						if cfxZones.unitInZone(theUnit, theZone) then 
							theZone.numRed = theZone.numRed + 1
						end
					end
				end
			end
		end
		-- count blue units 
		local allBlue = coalition.getGroups(2, Group.Category.GROUND)
		for idx, aGroup in pairs(allBlue) do 
			if Group.isExist(aGroup) then 
				if cfxOwnedZones.fastEval then 
					-- we only check first unit that is alive
					local theUnit = dcsCommon.getGroupUnit(aGroup)
					if theUnit and cfxZones.unitInZone(theUnit, theZone) then
						theZone.numBlue = theZone.numBlue + aGroup:getSize()
					end
				else 
					local allUnits = aGroup:getUnits() 
					for idy, theUnit in pairs(allUnits) do 
						if cfxZones.unitInZone(theUnit, theZone) then
							theZone.numBlue = theZone.numBlue + 1
						end
					end
				end
			end
		end
		-- trigger.action.outText(theZone.name .. " blue: " .. theZone.numBlue .. " red " .. theZone.numRed, 30)
		local lastOwner = theZone.owner
		local newOwner = 0 -- neutral is default 
		if theZone.unbeatable then -- Parker Lewis can't lose. Neither this zone.
			newOwner = lastOwner 
		end
		
		-- determine new owner 
		if theZone.unbeatable then 
			-- we do nothing 
		elseif theZone.numRed < 1 and theZone.numBlue < 1 then 
			-- no troops here. Become neutral?
			if cfxOwnedZones.numKeep < 1 then 
				newOwner = lastOwner -- keep it, else turns neutral
			else 
				-- noone here, zone becomes neutral
				newOwner = 0 -- not strictly required. to be explicit 
			end
		elseif theZone.numRed < 1 then 
			-- only blue here. enough to keep? 
			if theZone.numBlue >= cfxOwnedZones.numCap then 
				newOwner = 2 -- blue owns it
			elseif lastOwner == 2 and theZone.numBlue >= cfxOwnedZones.numKeep then 
				-- enough to keep if owned before
				newOwner = 2
			else 
				newOwner = 0 -- just to make it explicit
			end 
		elseif theZone.numBlue < 1 then 
			-- only red here. enough to keep?
			if theZone.numRed >= cfxOwnedZones.numCap then 
				newOwner = 1 
			elseif lastOwner == 1 and theZone.numRed >= cfxOwnedZones.numKeep then 
				newOwner = 1 
			else 
				newOwner = 0 
			end 				
		else 
			-- blue and red units here.
			-- owner keeps hanging on only they have enough 
			-- units left
			if cfxOwnedZones.easyContest then 
				-- this zone is immediately contested
				newOwner = 0 -- just to be explicit 
			elseif cfxOwnedZones.numKeep < 1 then 
				-- old owner keeps it until none left 
				newOwner = lastOwner
			else
				if lastOwner == 1 then 
					-- red can keep it as long as enough units here 
					if theZone.numRed >= cfxOwnedZones.numKeep then 
						newOwner = 1
					end -- else 0
				elseif lastOwner == 2 then
					-- blue can keep it if enough units here
					if theZone.numBlue >= cfxOwnedZones.numKeep then 
						newOwner = 2
					end -- else 0 
				else -- stay 0 
				end
			end
		end
	
		-- now see if owner changed, and react accordingly 
		if newOwner == lastOwner then 
			-- nothing happened, do nothing 
		else 
			trigger.action.outText(theZone.name .. " change hands from  " .. lastOwner .. " to " .. newOwner, 30)
			if newOwner == 0 then -- zone turned neutral 
				cfxOwnedZones.zoneConquered(theZone, newOwner, lastOwner)
			else
				cfxOwnedZones.zoneConquered(theZone, newOwner, lastOwner)
			end
		end
		theZone.owner = newOwner
		
		-- update ownership flag if exists
		if theZone.ownedBy then 
			cfxZones.setFlagValue(theZone.ownedBy, theZone.owner, theZone)
		end
		
	end -- iterating all zones 

end

function cfxOwnedZones.sideOwnsAll(theSide) 
	for key, aZone in pairs(cfxOwnedZones.zones) do 
		if aZone.owner ~= theSide then 
			return false
		end
	end
	-- if we get here, all your base are belong to us 
	return true
end

function cfxOwnedZones.hasOwnedZones() 
	for idx, zone in pairs (cfxOwnedZones.zones) do
		return true -- even the first returns true
	end
	-- no owned zones
	return false 
end


--
-- load / save data 
--

function cfxOwnedZones.saveData()
	-- this is called from persistence when it's time to 
	-- save data. returns a table with all my data 
	local theData = {}
	local allZoneData = {}
	-- iterate all my zones and create data 
	for idx, theZone in pairs(cfxOwnedZones.zones) do
		local zoneData = {}

		if theZone.conqueredFlag then 
			zoneData.conquered = cfxZones.getFlagValue(theZone.conqueredFlag, theZone)
		end 

		zoneData.owner = theZone.owner 
		allZoneData[theZone.name] = zoneData
	end
	
	-- now iterate all attack groups that we have spawned and that 
	-- (maybe) are still alive 
	-- now write the info for the flags that we output for #red, etc
	local flagInfo = {}
	flagInfo.neutral = cfxZones.getFlagValue(cfxOwnedZones.neutralTriggerFlag, cfxOwnedZones)
	flagInfo.red = cfxZones.getFlagValue(cfxOwnedZones.redTriggerFlag, cfxOwnedZones)
	flagInfo.blue = cfxZones.getFlagValue(cfxOwnedZones.blueTriggerFlag, cfxOwnedZones)
	-- assemble the data 
	theData.zoneData = allZoneData
	theData.flagInfo = flagInfo
	
	-- return it 
	return theData
end

function cfxOwnedZones.loadData()
	-- remember to draw in map with new owner 
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("cfxOwnedZones")
	if not theData then 
		if cfxOwnedZones.verbose then 
			trigger.action.outText("owdZ: no save date received, skipping.", 30)
		end
		return
	end
	-- theData contains the following tables:
	--   zoneData: per-zone data 
	--   flagInfo: module-global flags 
	--   attackers: all spawned attackers that we feed to groundTroops
	local allZoneData = theData.zoneData 
	for zName, zData in pairs(allZoneData) do 
		-- access zone 
		local theZone = cfxOwnedZones.getOwnedZoneByName(zName)
		if theZone then 
			theZone.owner = zData.owner 
			if zData.conquered then 
				cfxZones.setFlagValue(theZone.conqueredFlag, zData.conquered, theZone)
			end
			-- update mark in map 
			cfxOwnedZones.drawZoneInMap(theZone)
		else 
			trigger.action.outText("owdZ: load - data mismatch: cannot find zone <" .. zName .. ">, skipping zone.", 30)
		end
	end
	
	-- now process module global flags 
	local flagInfo = theData.flagInfo
	if flagInfo then 
		cfxZones.setFlagValue(cfxOwnedZones.neutralTriggerFlag, flagInfo.neutral, cfxOwnedZones)
		cfxZones.setFlagValue(cfxOwnedZones.redTriggerFlag, flagInfo.red, cfxOwnedZones)
		cfxZones.setFlagValue(cfxOwnedZones.blueTriggerFlag, flagInfo.blue, cfxOwnedZones)
	end
end

 
--
function cfxOwnedZones.readConfigZone(theZone)
	if not theZone then theZone = cfxZones.createSimpleZone("ownedZonesConfig") end 
	
	cfxOwnedZones.name = "cfxOwnedZones" -- just in case, so we can access with cfxZones 
	cfxOwnedZones.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	cfxOwnedZones.announcer = cfxZones.getBoolFromZoneProperty(theZone, "announcer", true)
	
	cfxOwnedZones.redTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "r!", "*<cfxnone>")
	cfxOwnedZones.blueTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "b!", "*<cfxnone>")
	cfxOwnedZones.neutralTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "n!", "*<cfxnone>")

	-- numKeep, numCap, fastEval, easyContest
	cfxOwnedZones.numCap = cfxZones.getNumberFromZoneProperty(theZone, "numCap", 1) -- minimal number of units required to cap zone 
	cfxOwnedZones.numKeep = cfxZones.getNumberFromZoneProperty(theZone, "numKeep", 0) -- number required to keep zone 
	cfxOwnedZones.fastEval = cfxZones.getBoolFromZoneProperty(theZone, "fastEval", true)
	cfxOwnedZones.easyContest = cfxZones.getBoolFromZoneProperty(theZone, "easyContest", false)
	-- winSound, loseSound 
	cfxOwnedZones.winSound = cfxZones.getStringFromZoneProperty(theZone, "winSound", "Quest Snare 3.wav" )
	cfxOwnedZones.loseSound = cfxZones.getStringFromZoneProperty(theZone, "loseSound", "Death BRASS.wav")
end

function cfxOwnedZones.init()
	-- check libs
	if not dcsCommon.libCheck("cfx Owned Zones", 
		cfxOwnedZones.requiredLibs) then
		return false 
	end

	-- read my config zone
	local theZone = cfxZones.getZoneByName("ownedZonesConfig") 
	cfxOwnedZones.readConfigZone(theZone)

	
	-- collect all owned zones by their 'owner' property 
	-- start the process
	local pZones = cfxZones.zonesWithProperty("owner")
	
	-- now add all zones to my zones table, and convert the owner property into 
	-- a proper attribute 
	for k, aZone in pairs(pZones) do
		cfxOwnedZones.addOwnedZone(aZone)
	end
	
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = cfxOwnedZones.saveData
		persistence.registerModule("cfxOwnedZones", callbacks)
		-- now load my data 
		cfxOwnedZones.loadData()
	end
	
	initialized = true 
	cfxOwnedZones.updateSchedule = timer.scheduleFunction(cfxOwnedZones.update, {}, timer.getTime() + 1/cfxOwnedZones.ups)
	
	trigger.action.outText("cx/x owned zones v".. cfxOwnedZones.version .. " started", 30)
	return true 
end

if not cfxOwnedZones.init() then 
	trigger.action.outText("cf/x Owned Zones aborted: missing libraries", 30)
	cfxOwnedZones = nil 
end



