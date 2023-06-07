cfxOwnedZones = {}
cfxOwnedZones.version = "2.0.1"
cfxOwnedZones.verbose = false 
cfxOwnedZones.announcer = true 
cfxOwnedZones.name = "cfxOwnedZones" 
--[[-- VERSION HISTORY

2.0.0 - factored from cfxOwnedZones 1.x, separating out production
	  - moved to flag# semantic
	  - xxxOwned# for all
	  - ownedBy# supports multFlag
	  - xxxOwned#
	  - redLine, blueLine
	  - redFill, blueFill
	  - neutralLine, neutralFill 
	  - global and per-zone colors 
	  - auto-defaulting colors from config 
	  - supports poly zone 
	  - groundCap option 
	  - navalCap option 
	  - heloCap option 
	  - fixWingCap option 
	  - filter water owned zones for groundTroops 
2.0.1 - RGBA colors can be entered hex style #ff340799

--]]--
cfxOwnedZones.requiredLibs = {
	"dcsCommon", 
	"cfxZones",  
}

cfxOwnedZones.zones = {}
cfxOwnedZones.ups = 1
cfxOwnedZones.initialized = false 
--[[--
 owned zones is a module that manages conquerable zones and keeps a record
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
	
	local lineColor = aZone.redLine -- {1.0, 0, 0, 1.0} -- red  
	local fillColor = aZone.redFill -- {1.0, 0, 0, 0.2} -- red 
	local owner = aZone.owner -- cfxOwnedZones.getOwnerForZone(aZone)
	if owner == 2 then 
		lineColor = aZone.blueLine -- {0.0, 0, 1.0, 1.0}
		fillColor = aZone.blueFill -- {0.0, 0, 1.0, 0.2}
	elseif owner == 0 then 
		lineColor = aZone.neutralLine -- {0.8, 0.8, 0.8, 1.0}
		fillColor = aZone.neutralFill -- {0.8, 0.8, 0.8, 0.2}
	end
	
--	local theShape = 2 -- circle
	local markID = dcsCommon.numberUUID()

	if aZone.isCircle then 
		trigger.action.circleToAll(-1, markID, aZone.point, aZone.radius, lineColor, fillColor, 1, true, "")
	else 
		local poly = aZone.poly
		trigger.action.quadToAll(-1, markID, poly[4], poly[3], poly[2], poly[1], lineColor, fillColor, 1, true, "") -- note: left winding to get fill color
	end 
	
	aZone.markID = markID 
end

function cfxOwnedZones.getOwnedZoneByName(zName)
	for zKey, theZone in pairs (cfxOwnedZones.zones) do 
		if theZone.name == zName then return theZone end 
	end
	return nil
end

function cfxOwnedZones.addOwnedZone(aZone)
	local owner = aZone.owner --cfxZones.getCoalitionFromZoneProperty(aZone, "owner", 0) -- is already read
	
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
	if cfxZones.hasProperty(aZone, "ownedBy#") then 
		aZone.ownedBy = cfxZones.getStringFromZoneProperty(aZone, "ownedBy#", "none")
	elseif cfxZones.hasProperty(aZone, "ownedBy") then 
		aZone.ownedBy = cfxZones.getStringFromZoneProperty(aZone, "ownedBy", "none")
	end
		
	aZone.unbeatable = cfxZones.getBoolFromZoneProperty(aZone, "unbeatable", false)
	aZone.untargetable = cfxZones.getBoolFromZoneProperty(aZone, "untargetable", false)
	
	aZone.hidden = cfxZones.getBoolFromZoneProperty(aZone, "hidden", false)
	
	-- individual colors, else default from config 
	aZone.redLine = cfxZones.getRGBAVectorFromZoneProperty(aZone, "redLine", cfxOwnedZones.redLine)
	aZone.redFill = cfxZones.getRGBAVectorFromZoneProperty(aZone, "redFill", cfxOwnedZones.redFill)
	aZone.blueLine = cfxZones.getRGBAVectorFromZoneProperty(aZone, "blueLine", cfxOwnedZones.blueLine)
	aZone.blueFill = cfxZones.getRGBAVectorFromZoneProperty(aZone, "blueFill", cfxOwnedZones.blueFill)
	aZone.neutralLine = cfxZones.getRGBAVectorFromZoneProperty(aZone, "neutralLine", cfxOwnedZones.neutralLine)
	aZone.neutralFill = cfxZones.getRGBAVectorFromZoneProperty(aZone, "neutralFill", cfxOwnedZones.neutralFill)
	
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
	-- units are in each zone, also count how many zones each side has
	local totalZoneNum = 0
	local blueZoneNum = 0
	local redZoneNum = 0 
	local greyZoneNum = 0 
	
	-- assemble all units in allRed and allBlue according to 
	-- cap options (boots, ships, rotors, wings) 
	local allRed = {}
	if cfxOwnedZones.groundCap then allRed = coalition.getGroups(1, Group.Category.GROUND) end 
	if cfxOwnedZones.navalCap then 
		allRed = dcsCommon.combineTables(allRed, coalition.getGroups(1, Group.Category.SHIP)) 
	end 
	if cfxOwnedZones.heloCap then 
		allRed = dcsCommon.combineTables(allRed, coalition.getGroups(1, Group.Category.HELICOPTER)) 
	end
	if cfxOwnedZones.fixWingCap then 
		allRed = dcsCommon.combineTables(allRed, coalition.getGroups(1, Group.Category.AIRPLANE)) 
	end
	
	local allBlue = {}
	if cfxOwnedZones.groundCap then allBlue = coalition.getGroups(2, Group.Category.GROUND) end 
	if cfxOwnedZones.navalCap then 
		allBlue = dcsCommon.combineTables(allBlue, coalition.getGroups(2, Group.Category.SHIP)) 
	end 
	if cfxOwnedZones.heloCap then 
		allBlue = dcsCommon.combineTables(allBlue, coalition.getGroups(2, Group.Category.HELICOPTER)) 
	end
	if cfxOwnedZones.fixWingCap then 
		allBlue = dcsCommon.combineTables(allBlue, coalition.getGroups(2, Group.Category.AIRPLANE)) 
	end
		
	for idz, theZone in pairs(cfxOwnedZones.zones) do 
		theZone.numRed = 0
		theZone.numBlue = 0 
		-- count red units in zone 
		for idx, aGroup in pairs(allRed) do 
			if Group.isExist(aGroup) then 
				if cfxOwnedZones.fastEval then 
					-- we only check first unit that is alive
					local theUnit = dcsCommon.getGroupUnit(aGroup)
					if theUnit and (not theUnit:inAir()) and cfxZones.unitInZone(theUnit, theZone) then
						theZone.numRed = theZone.numRed + aGroup:getSize()
					end
				else 
					local allUnits = aGroup:getUnits() 
					for idy, theUnit in pairs(allUnits) do 
						if (not theUnit:inAir()) and cfxZones.unitInZone(theUnit, theZone) then 
							theZone.numRed = theZone.numRed + 1
						end
					end
				end
			end
		end
		-- count blue units 
		for idx, aGroup in pairs(allBlue) do 
			if Group.isExist(aGroup) then 
				if cfxOwnedZones.fastEval then 
					-- we only check first unit that is alive
					local theUnit = dcsCommon.getGroupUnit(aGroup)
					if theUnit and (not theUnit:inAir()) and cfxZones.unitInZone(theUnit, theZone) then
						theZone.numBlue = theZone.numBlue + aGroup:getSize()
					end
				else 
					local allUnits = aGroup:getUnits() 
					for idy, theUnit in pairs(allUnits) do 
						if (not theUnit:inAir()) and cfxZones.unitInZone(theUnit, theZone) then
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
			cfxZones.setFlagValueMult(theZone.ownedBy, theZone.owner, theZone)
		end
		
		-- now add this zone to relevant side 
		totalZoneNum = totalZoneNum + 1
		if newOwner == 0 then 
			greyZoneNum = greyZoneNum + 1
		elseif newOwner == 1 then 
			redZoneNum = redZoneNum + 1
		else 
			blueZoneNum = blueZoneNum + 1
		end
		
	end -- iterating all zones 
	
	-- update totals 
	if cfxOwnedZones.redOwned then 
		cfxZones.setFlagValueMult(cfxOwnedZones.redOwned, redZoneNum, cfxOwnedZones)
	end
	if cfxOwnedZones.blueOwned then 
		cfxZones.setFlagValueMult(cfxOwnedZones.blueOwned, blueZoneNum, cfxOwnedZones)
	end
	if cfxOwnedZones.neutralOwned then 
		cfxZones.setFlagValueMult(cfxOwnedZones.neutralOwned, greyZoneNum, cfxOwnedZones)
	end
	
	if cfxOwnedZones.totalOwnedZones then 
		cfxZones.setFlagValueMult(cfxOwnedZones.totalOwnedZones, totalZoneNum, cfxOwnedZones)
	end

	-- see if one side owns all and bang the flags if requiredLibs
	if cfxOwnedZones.allBlue and not cfxOwnedZones.hasAllBlue then
		if cfxOwnedZones.sideOwnsAll(2) then 
			cfxZones.pollFlag(cfxOwnedZones.allBlue, "inc", cfxOwnedZones)
			cfxOwnedZones.hasAllBlue = true 
		end
	end

	if cfxOwnedZones.allRed and not cfxOwnedZones.hasAllRed then
		if cfxOwnedZones.sideOwnsAll(1) then 
			cfxZones.pollFlag(cfxOwnedZones.allRed, "inc", cfxOwnedZones)
			cfxOwnedZones.hasAllRed = true 
		end
	end
	
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

-- getting closest owned zones etc
-- required for groundTroops and factory attackers 
-- methods provided only for other modules (e.g. cfxGroundTroops or 
-- factoryZone 
--

-- collect zones can filter owned zones. 
-- by default it filters all zones that are in water 
function cfxOwnedZones.collectZones(mode)
	if not mode then mode = "land" end 
	if mode == "land" then 
		local landZones = {}
		for idx, theZone in pairs(cfxOwnedZones.zones) do 
			p = cfxZones.getPoint(theZone)
			p.y = p.z 
			local surfType = land.getSurfaceType(p)
			if surfType == 3 then 
			else 
				table.insert(landZones, theZone)
			end
		end
		return landZones
	end
	
	-- return all zones 
	return cfxOwnedZones.zones 
	--if not mode then mode = "OWNED" end 
	-- Note: since cfxGroundTroops currently simply uses owner flag
	-- we cannot migrate to a differentiation between factory and 
	-- owned. All produced attackers always attack owned zones.
end

function cfxOwnedZones.getEnemyZonesFor(aCoalition) 
	local enemyZones = {}
	local allZones = cfxOwnedZones.collectZones()  
	local ourEnemy = dcsCommon.getEnemyCoalitionFor(aCoalition)
	for zKey, aZone in pairs(allZones) do 
		if aZone.owner == ourEnemy then -- only check enemy owned zones
			-- note: will include untargetable zones 
			table.insert(enemyZones, aZone)			
		end
	end
	return enemyZones
end

function cfxOwnedZones.getNearestOwnedZoneToPoint(aPoint)
	local shortestDist = math.huge
	local closestZone = nil
	local allZones = cfxOwnedZones.collectZones() 
	
	for zKey, aZone in pairs(allZones) do 
		local zPoint = cfxZones.getPoint(aZone) 
		currDist = dcsCommon.dist(zPoint, aPoint)
		if aZone.untargetable ~= true and 
		   currDist < shortestDist then 
			shortestDist = currDist
			closestZone = aZone
		end
	end
	
	return closestZone, shortestDist
end

function cfxOwnedZones.getNearestOwnedZone(theZone)
	local shortestDist = math.huge
	local closestZone = nil
	local aPoint = cfxZones.getPoint(theZone)
	local allZones = cfxOwnedZones.collectZones()
	for zKey, aZone in pairs(allZones) do
		local zPoint = cfxZones.getPoint(aZone) 
		currDist = dcsCommon.dist(zPoint, aPoint)
		if aZone.untargetable ~= true and currDist < shortestDist then 
			shortestDist = currDist
			closestZone = aZone
		end
	end
	
	return closestZone, shortestDist
end

function cfxOwnedZones.getNearestEnemyOwnedZone(theZone, targetNeutral)
	if not targetNeutral then targetNeutral = false else targetNeutral = true end
	local shortestDist = math.huge
	local closestZone = nil
	local allZones = cfxOwnedZones.collectZones()
	local ourEnemy = dcsCommon.getEnemyCoalitionFor(theZone.owner)
	if not ourEnemy then return nil end -- we called for a neutral zone. they have no enemies 
	local zPoint = cfxZones.getPoint(theZone)
	
	for zKey, aZone in pairs(allZones) do 
		if targetNeutral then 
			-- return all zones that do not belong to us
			if aZone.owner ~= theZone.owner then 
				local aPoint = cfxZones.getPoint(aZone)
				currDist = dcsCommon.dist(aPoint, zPoint)
				if aZone.untargetable ~= true and currDist < shortestDist then 
					shortestDist = currDist
					closestZone = aZone
				end
			end
		else 
			-- return zones that are taken by the Enenmy
			if aZone.owner == ourEnemy then -- only check own zones
				local aPoint = cfxZones.getPoint(aZone)
				currDist = dcsCommon.dist(zPoint, aPoint)
				if aZone.untargetable ~= true and currDist < shortestDist then 
					shortestDist = currDist
					closestZone = aZone
				end
			end
		end 
	end
	
	return closestZone, shortestDist
end

function cfxOwnedZones.getNearestFriendlyZone(theZone, targetNeutral)
	if not targetNeutral then targetNeutral = false else targetNeutral = true end
	local shortestDist = math.huge
	local closestZone = nil
	local ourEnemy = dcsCommon.getEnemyCoalitionFor(theZone.owner)
	if not ourEnemy then return nil end -- we called for a neutral zone. they have no enemies nor friends, all zones would be legal.
	local zPoint = cfxZones.getPoint(theZone)
	local allZones = cfxOwnedZones.collectZones() 

	for zKey, aZone in pairs(allZones) do 
		if targetNeutral then 
			-- target all zones that do not belong to the enemy
			if aZone.owner ~= ourEnemy then
				local aPoint = cfxZones.getPoint(aZone)
				currDist = dcsCommon.dist(zPoint, aPoint)
				if aZone.untargetable ~= true and currDist < shortestDist then 
					shortestDist = currDist
					closestZone = aZone
				end
			end
		else 
			-- only target zones that are taken by us
			if aZone.owner == theZone.owner then -- only check own zones
				local aPoint = cfxZones.getPoint(aZone)
				currDist = dcsCommon.dist(zPoint, aPoint)
				if aZone.untargetable ~= true and currDist < shortestDist then 
					shortestDist = currDist
					closestZone = aZone
				end
			end
		end 
	end
	
	return closestZone, shortestDist
end

function cfxOwnedZones.enemiesRemaining(aZone)
	if cfxOwnedZones.getNearestEnemyOwnedZone(aZone) then return true end
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
	
	if cfxZones.hasProperty(theZone, "r!") then 
		cfxOwnedZones.redTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "r!", "*<cfxnone>")
	else 
		cfxOwnedZones.redTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "r#", "*<cfxnone>")
	end
	if cfxZones.hasProperty(theZone, "b!") then 
		cfxOwnedZones.redTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "b!", "*<cfxnone>")
	else
		cfxOwnedZones.blueTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "b#", "*<cfxnone>")
	end 
	
	if cfxZones.hasProperty(theZone, "n!") then 
		cfxOwnedZones.redTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "n!", "*<cfxnone>")
	else
		cfxOwnedZones.neutralTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "n#", "*<cfxnone>")
	end
	
	-- allXXX flags
	if cfxZones.hasProperty(theZone, "allBlue!") then 
		cfxOwnedZones.allBlue = cfxZones.getStringFromZoneProperty(theZone, "allBlue!", "*<cfxnone>")
		cfxOwnedZones.hasAllBlue = nil 
	end 
	
	if cfxZones.hasProperty(theZone, "allRed!") then 
		cfxOwnedZones.allRed = cfxZones.getStringFromZoneProperty(theZone, "allRed!", "*<cfxnone>")
		cfxOwnedZones.hasAllRed = nil 
	end
	
	if cfxZones.hasProperty(theZone, "redOwned#") then 
		cfxOwnedZones.redOwned = cfxZones.getStringFromZoneProperty(theZone, "redOwned#", "*<cfxnone>")
	end
	if cfxZones.hasProperty(theZone, "blueOwned#") then 
		cfxOwnedZones.blueOwned = cfxZones.getStringFromZoneProperty(theZone, "blueOwned#", "*<cfxnone>")
	end
	if cfxZones.hasProperty(theZone, "neutralOwned#") then 
		cfxOwnedZones.neutralOwned = cfxZones.getStringFromZoneProperty(theZone, "neutralOwned#", "*<cfxnone>")
	end
	if cfxZones.hasProperty(theZone, "totalZones#") then 
		cfxOwnedZones.totalOwnedZones = cfxZones.getStringFromZoneProperty(theZone, "totalZones#", "*<cfxnone>")
	end
	-- numKeep, numCap, fastEval, easyContest
	cfxOwnedZones.numCap = cfxZones.getNumberFromZoneProperty(theZone, "numCap", 1) -- minimal number of units required to cap zone 
	cfxOwnedZones.numKeep = cfxZones.getNumberFromZoneProperty(theZone, "numKeep", 0) -- number required to keep zone 
	cfxOwnedZones.fastEval = cfxZones.getBoolFromZoneProperty(theZone, "fastEval", true)
	cfxOwnedZones.easyContest = cfxZones.getBoolFromZoneProperty(theZone, "easyContest", false)
	-- winSound, loseSound 
	cfxOwnedZones.winSound = cfxZones.getStringFromZoneProperty(theZone, "winSound", "Quest Snare 3.wav" )
	cfxOwnedZones.loseSound = cfxZones.getStringFromZoneProperty(theZone, "loseSound", "Death BRASS.wav")

	-- capture options
	cfxOwnedZones.groundCap = cfxZones.getBoolFromZoneProperty(theZone, "groundCap", true)
	cfxOwnedZones.navalCap = cfxZones.getBoolFromZoneProperty(theZone, "navalCap", false)
	cfxOwnedZones.heloCap = cfxZones.getBoolFromZoneProperty(theZone, "heloCap")
	cfxOwnedZones.fixWingCap = cfxZones.getBoolFromZoneProperty(theZone, "fixWingCap")
	
	-- colors for line and fill 
	cfxOwnedZones.redLine = cfxZones.getRGBAVectorFromZoneProperty(theZone, "redLine", {1.0, 0, 0, 1.0})
	cfxOwnedZones.redFill = cfxZones.getRGBAVectorFromZoneProperty(theZone, "redFill", {1.0, 0, 0, 0.2})
	cfxOwnedZones.blueLine = cfxZones.getRGBAVectorFromZoneProperty(theZone, "blueLine", {0.0, 0, 1.0, 1.0})
	cfxOwnedZones.blueFill = cfxZones.getRGBAVectorFromZoneProperty(theZone, "blueFill", {0.0, 0, 1.0, 0.2})
	cfxOwnedZones.neutralLine = cfxZones.getRGBAVectorFromZoneProperty(theZone, "neutralLine", {0.8, 0.8, 0.8, 1.0})
	cfxOwnedZones.neutralFill = cfxZones.getRGBAVectorFromZoneProperty(theZone, "neutralFill", {0.8, 0.8, 0.8, 0.2})
	
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

--[[--
	masterOwner input for zones, overrides all else when not neutral 
	
	dont count zones that cant be conquered for allBlue/allRed
		
--]]--

