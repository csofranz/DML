cfxOwnedZones = {}
cfxOwnedZones.version = "2.3.1"
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
2.1.0 - dmlZones 
	  - full support for multiple out flags 
	  - "Neutral (C)" returned for ownership if contested owner
	  - corrected some typos in output text 
	  - method support for individual owned zones 
	  - method support for global (config) output 
	  - moved drawZone to cfxZones
2.2.0 - excludedTypes option in config 
2.3.0 - include airfield zones (module) in collectZones()
      - if airfield is defined.
	  - allManagedOwnedZones
	  - gatherAllManagedOwnedZones()
	  - commented out unused (?) methods 
	  - optmized getNearestEnemyOwnedZone
	  - collectZones now uses gatherAllManagedOwnedZones
	  - sideOwnsAll can use allManagedOwnedZones
	  - per-zone local numCap 
	  - per-zone local numkeep 
	  - title attribute 
	  - code clean-up
2.3.1 - restored getNearestOwnedZoneToPoint 
--]]--
cfxOwnedZones.requiredLibs = {
	"dcsCommon", 
	"cfxZones",  
}

cfxOwnedZones.zones = {} -- ownedZones FROM THIS module
cfxOwnedZones.allManagedOwnedZones = {} -- superset, indexed by name 
cfxOwnedZones.ups = 1
cfxOwnedZones.initialized = false 

-- *** EXTENTDS ZONES *** --
 
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
	if theSide == 3 then return "Neutral (C)" end 
	return "Neutral"
end

function cfxOwnedZones.conqTemplate(aZone, newOwner, lastOwner) 
	if true then return end -- do not output

	if lastOwner == 0 then 
		trigger.action.outText(cfxOwnedZones.side2name(newOwner) .. " have taken possession of zone " .. aZone.name, 30)
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
	if aZone.titleID then 
		trigger.action.removeMark(aZone.titleID)
	end 
	
	local lineColor = aZone.redLine -- {1.0, 0, 0, 1.0} -- red  
	local fillColor = aZone.redFill -- {1.0, 0, 0, 0.2} -- red 
	local owner = aZone.owner 
	if owner == 2 then 
		lineColor = aZone.blueLine -- {0.0, 0, 1.0, 1.0}
		fillColor = aZone.blueFill -- {0.0, 0, 1.0, 0.2}
	elseif owner == 0 then 
		lineColor = aZone.neutralLine -- {0.8, 0.8, 0.8, 1.0}
		fillColor = aZone.neutralFill -- {0.8, 0.8, 0.8, 0.2}
	end
	
	if aZone.title then 
		aZone.titleID = aZone:drawText(aZone.title, 18, lineColor, {0, 0, 0, 0})
	end 
	
	if aZone.hidden then return end 	
	aZone.markID = aZone:drawZone(lineColor, fillColor) -- markID 
end

function cfxOwnedZones.getOwnedZoneByName(zName)
	for zKey, theZone in pairs (cfxOwnedZones.zones) do 
		if theZone.name == zName then return theZone end 
	end
	return nil
end

function cfxOwnedZones.addOwnedZone(aZone)
	local owner = aZone.owner 
	
	if aZone:hasProperty("conquered!") then 
		aZone.conqueredFlag = aZone:getStringFromZoneProperty("conquered!", "*<cfxnone>")
	end
	if aZone:hasProperty("redCap!") then 
		aZone.redCap = aZone:getStringFromZoneProperty("redCap!", "none")
	end
	if aZone:hasProperty("redLost!") then 
		aZone.redLost = aZone:getStringFromZoneProperty("redLost!", "none")
	end
	if aZone:hasProperty("blueCap!") then 
		aZone.blueCap = aZone:getStringFromZoneProperty("blueCap!", "none")
	end
	if aZone:hasProperty("blueLost!") then 
		aZone.blueLost = aZone:getStringFromZoneProperty("blueLost!", "none")
	end
	if aZone:hasProperty("neutral!") then 
		aZone.neutralCap = aZone:getStringFromZoneProperty("neutral!", "none")
	end
	if aZone:hasProperty("ownedBy#") then 
		aZone.ownedBy = aZone:getStringFromZoneProperty("ownedBy#", "none")
	elseif aZone:hasProperty("ownedBy") then 
		aZone.ownedBy = aZone:getStringFromZoneProperty("ownedBy", "none")
	end
		
	aZone.unbeatable = aZone:getBoolFromZoneProperty("unbeatable", false)
	aZone.untargetable = aZone:getBoolFromZoneProperty("untargetable", false)
	
	aZone.hidden = aZone:getBoolFromZoneProperty("hidden", false)
	-- numCap, numKeep
	aZone.numCap = aZone:getNumberFromZoneProperty("numCap", cfxOwnedZones.numCap)
	aZone.numKeep = aZone:getNumberFromZoneProperty("numKeep", cfxOwnedZones.numKeep)
	
	-- individual colors, else default from config 
	aZone.redLine = aZone:getRGBAVectorFromZoneProperty("redLine", cfxOwnedZones.redLine)
	aZone.redFill = aZone:getRGBAVectorFromZoneProperty("redFill", cfxOwnedZones.redFill)
	aZone.blueLine = aZone:getRGBAVectorFromZoneProperty("blueLine", cfxOwnedZones.blueLine)
	aZone.blueFill = aZone:getRGBAVectorFromZoneProperty("blueFill", cfxOwnedZones.blueFill)
	aZone.neutralLine = aZone:getRGBAVectorFromZoneProperty("neutralLine", cfxOwnedZones.neutralLine)
	aZone.neutralFill = aZone:getRGBAVectorFromZoneProperty("neutralFill", cfxOwnedZones.neutralFill)
	
	-- masterOwner 
	if aZone:hasProperty("masterOwner") then 
		local masterZone = aZone:getStringFromZoneProperty("masterOwner", "cfxNoneErr")
		local theMaster = cfxZones.getZoneByName(masterZone)
		if not theMaster then 
			trigger.action.outText("+++owdZ: WARNING: owned zone <" .. aZone.name .. ">'s masterOwner <" .. masterZone .. "> does not exist, not connecting!", 30)
		else 
			aZone.masterOwner = theMaster 
			aZone.owner = theMaster.owner 
			if aZone.verbose or cfxOwnedZones.verbose then 
				trigger.action.outText("+++OwdZ: owned zone <" .. aZone.name .. "> inherits ownership from master zone <" .. masterZone .. ">", 30)
			end
		end
	end
	
	aZone.announcer = aZone:getBoolFromZoneProperty("announcer", cfxZones.announcer)
	if aZone:hasProperty("announce") then 
		aZone.announcer = aZone:getBoolFromZoneProperty("announce", cfxZones.announcer)
	end 
	
	-- title 
	if aZone:hasProperty("title") then 
		aZone.title = aZone:getStringFromZoneProperty("title")
		if aZone.title == "*" then aZone.title = aZone.name end 
	end
	aZone.method = aZone:getStringFromZoneProperty("method", "inc")
	
	cfxOwnedZones.zones[aZone] = aZone 
	cfxOwnedZones.drawZoneInMap(aZone)
	if aZone.verbose or cfxOwnedZones.verbose then  
		trigger.action.outText("+++owdZ: detected zone <" .. aZone.name .. ">", 30)
	end
end

--
-- U P D A T E 
--

function cfxOwnedZones.bangNeutral(value)
	if not cfxOwnedZones.neutralTriggerFlag then return end 
	cfxZones.pollFlag(cfxOwnedZones.neutralTriggerFlag, cfxOwnedZones.method, cfxOwnedZones)
end

function cfxOwnedZones.bangRed(value, theZone)
	if not cfxOwnedZones.redTriggerFlag then return end 
	cfxZones.pollFlag(cfxOwnedZones.redTriggerFlag, cfxOwnedZones.method, cfxOwnedZones)
end

function cfxOwnedZones.bangBlue(value, theZone)
	if not cfxOwnedZones.blueTriggerFlag then return end 
	local newVal = trigger.misc.getUserFlag(cfxOwnedZones.blueTriggerFlag) + value 
	cfxZones.pollFlag(cfxOwnedZones.blueTriggerFlag, cfxOwnedZones.method, cfxOwnedZones)
end

function cfxOwnedZones.bangSide(theSide, value, theZone)
	if theSide == 2 then 
		cfxOwnedZones.bangBlue(value, theZone)
		return 
	end 
	if theSide == 1 then 
		cfxOwnedZones.bangRed(value, theZone)
		return 
	end 
	cfxOwnedZones.bangNeutral(value, theZone)
end

function cfxOwnedZones.zoneConquered(aZone, theSide, formerOwner) -- 0 = neutral 1 = RED 2 = BLUE 
	local who = "REDFORCE"
	if theSide == 2 then who = "BLUEFORCE" 
	elseif theSide == 0 then who = "NEUTRAL" end
	aZone.owner = theSide -- just to be sure 
	
	if cfxOwnedZones.announcer or aZone.announcer then 
		if theSide == 0 then 
			trigger.action.outText(aZone.name .. " has become NEUTRAL", 30)
		else 
			trigger.action.outText(who .. " have secured zone " .. aZone.name, 30)
		end
		
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
		aZone:pollFlag(aZone.conqueredFlag, aZone.method)
	end 
	
	if theSide == 1 and aZone.redCap then 
		aZone:pollFlag(aZone.redCap, aZone.method)
	end
	
	if formerOwner == 1 and aZone.redLost then 
		aZone:pollFlag(aZone.redLost, aZone.method)
	end
	
	if theSide == 2 and aZone.blueCap then 
		aZone:pollFlag(aZone.blueCap, aZone.method)
	end
	
	if formerOwner == 2 and aZone.blueLost then 
		aZone:pollFlag(aZone.blueLost, aZone.method)
	end
	
	if theSide == 0 and aZone.neutralCap then 
		aZone:pollFlag(aZone.neutralCap, aZone.method)
	end
	
	-- invoke callbacks now
	cfxOwnedZones.invokeConqueredCallbacks(aZone, theSide, formerOwner)
	
	-- bang! flag support 
	cfxOwnedZones.bangSide(theSide, 1, aZone) -- winner 
	cfxOwnedZones.bangSide(formerOwner, -1, aZone) -- loser 
	
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
	
	-- WARNING: we only proc ownedZones, NOT airfield nor FARP or other
	for idz, theZone in pairs(cfxOwnedZones.zones) do 
		theZone.numRed = 0
		theZone.numBlue = 0 
		local lastOwner = theZone.owner
		if not lastOwner then 
			trigger.action.outText("+++owdZ: WARNING - zone <" .. theZone.name .. "> has NIL owner", 30)
			return 
		end 
		if theZone.verbose then 
			trigger.action.outText("Zone <" .. theZone.name .. "> lastOwner is <" .. lastOwner .. ">", 30)
		end 
		local newOwner = 0 -- neutral is default 
		-- count red units in zone 
		if not theZone.masterOwner then 
			for idx, aGroup in pairs(allRed) do 
				if Group.isExist(aGroup) then 
					if cfxOwnedZones.fastEval then 
						-- we only check first unit that is alive
						local theUnit = dcsCommon.getGroupUnit(aGroup)
						if theUnit and (not theUnit:inAir()) and theZone:unitInZone(theUnit) then
							if cfxOwnedZones.excludedTypes then
								-- special carve-out for exclduding some 
								-- unit types to prevent them from capping
								local uType = theUnit:getTypeName()
								local forbidden = false 
								for idx, aType in pairs(cfxOwnedZones.excludedTypes) do 
									if uType == aType then 
										forbidden = true 
									else 
									end
								end
								if not forbidden then 
									theZone.numRed = theZone.numRed + aGroup:getSize()
								end
							else 
								theZone.numRed = theZone.numRed + aGroup:getSize()
							end
						end
					else -- full eval
						local allUnits = aGroup:getUnits() 
						for idy, theUnit in pairs(allUnits) do 
							if (not theUnit:inAir()) and theZone:unitInZone(theUnit) then 
								if cfxOwnedZones.excludedTypes then
									-- special carve-out for exclduding some 
									-- unit types to prevent them from capping
									local uType = theUnit:getTypeName()
									local forbidden = false 
									for idx, aType in pairs(cfxOwnedZones.excludedTypes) do 
										if uType == aType then forbidden = true end
									end
									if not forbidden then 
										theZone.numRed = theZone.numRed + aGroup:getSize()
									end
								else 
									theZone.numRed = theZone.numRed + aGroup:getSize()
								end
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
						if theUnit and (not theUnit:inAir()) and theZone:unitInZone(theUnit) then
							if cfxOwnedZones.excludedTypes then
								-- special carve-out for exclduding some 
								-- unit types to prevent them from capping
								local uType = theUnit:getTypeName()
								local forbidden = false 
								for idx, aType in pairs(cfxOwnedZones.excludedTypes) do 
									if uType == aType then 
										forbidden = true 
									else 
									end
								end
								if not forbidden then 
									theZone.numBlue = theZone.numBlue + aGroup:getSize()
								end
							else 
								theZone.numBlue = theZone.numBlue + aGroup:getSize()
							end
						end
					else 
						local allUnits = aGroup:getUnits() 
						for idy, theUnit in pairs(allUnits) do 
							if (not theUnit:inAir()) and theZone:unitInZone(theUnit) then
								if cfxOwnedZones.excludedTypes then
									-- special carve-out for exclduding some 
									-- unit types to prevent them from capping
									local uType = theUnit:getTypeName()
									local forbidden = false 
									for idx, aType in pairs(cfxOwnedZones.excludedTypes) do 
										if uType == aType then forbidden = true end
									end
									if not forbidden then 
										theZone.numBlue = theZone.numBlue + aGroup:getSize()
									end
								else 
									theZone.numBlue = theZone.numBlue + aGroup:getSize()
								end
							end
						end
					end
				end
			end
			
			if theZone.verbose then 
				trigger.action.outText("+++owdZ: zone <" .. theZone.name .. ">: red inside: <" .. theZone.numRed .. ">, blue inside: <>" .. theZone.numBlue, 30)
			end
		else 
			-- zone has master owner, no counting done 
		end 
		
		if theZone.unbeatable then -- Parker Lewis can't lose. Neither this zone.
			newOwner = lastOwner 
		end
		
		-- determine new owner 
		if theZone.unbeatable then 
			-- we do nothing
		elseif theZone.masterOwner then 
			-- inherit from my master 
			newOwner = theZone.masterOwner.owner
		elseif theZone.numRed < 1 and theZone.numBlue < 1 then 
			-- no troops here. Become neutral?
			if theZone.numKeep < 1 then 
				newOwner = lastOwner -- keep it, else turns neutral
			else 
				-- noone here, zone becomes neutral
				newOwner = 0 -- not strictly required. to be explicit 
			end
		elseif theZone.numRed < 1 then 
			-- only blue here. enough to keep? 
			if theZone.numBlue >= theZone.numCap then 
				newOwner = 2 -- blue owns it
			elseif lastOwner == 2 and theZone.numBlue >= theZone.numKeep then 
				-- enough to keep if owned before
				newOwner = 2
			else 
				newOwner = 0 -- just to make it explicit
			end 
		elseif theZone.numBlue < 1 then 
			-- only red here. enough to keep?
			if theZone.numRed >= theZone.numCap then 
				newOwner = 1 
			elseif lastOwner == 1 and theZone.numRed >= theZone.numKeep then 
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
			elseif theZone.numKeep < 1 then 
				-- old owner keeps it until none left 
				newOwner = lastOwner
			else
				if lastOwner == 1 then 
					-- red can keep it as long as enough units here 
					if theZone.numRed >= theZone.numKeep then 
						newOwner = 1
					end -- else 0
				elseif lastOwner == 2 then
					-- blue can keep it if enough units here
					if theZone.numBlue >= theZone.numKeep then 
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
			theZone:setFlagValue(theZone.ownedBy, theZone.owner)
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
		cfxZones.setFlagValue(cfxOwnedZones.redOwned, redZoneNum, cfxOwnedZones)
	end
	if cfxOwnedZones.blueOwned then 
		cfxZones.setFlagValue(cfxOwnedZones.blueOwned, blueZoneNum, cfxOwnedZones)
	end
	if cfxOwnedZones.neutralOwned then 
		cfxZones.setFlagValue(cfxOwnedZones.neutralOwned, greyZoneNum, cfxOwnedZones)
	end
	
	if cfxOwnedZones.totalOwnedZones then 
		cfxZones.setFlagValue(cfxOwnedZones.totalOwnedZones, totalZoneNum, cfxOwnedZones)
	end

	-- see if one side owns all and bang the flags if requiredLibs
	if cfxOwnedZones.allBlue and not cfxOwnedZones.hasAllBlue then
		if cfxOwnedZones.sideOwnsAll(2) then -- ignores other owner-managed zones
			cfxZones.pollFlag(cfxOwnedZones.allBlue, cfxOwnedZones.method, cfxOwnedZones)
			cfxOwnedZones.hasAllBlue = true 
		end
	end

	if cfxOwnedZones.allRed and not cfxOwnedZones.hasAllRed then
		if cfxOwnedZones.sideOwnsAll(1) then -- ignores other managed owner zones
			cfxZones.pollFlag(cfxOwnedZones.allRed, cfxOwnedZones.method, cfxOwnedZones)
			cfxOwnedZones.hasAllRed = true 
		end
	end
	
end

function cfxOwnedZones.sideOwnsAll(theSide, useAllManaged)
	local themAll = cfxOwnedZones.zones 
	if useAllManaged then themAll = cfxZones.allManagedOwnedZones end 
	for key, aZone in pairs(themAll) do 
		if aZone.owner ~= theSide then 
			return false
		end
	end
	-- if we get here, all your base are belong to us 
	return true
end

-- getting closest owned zones etc
-- required for groundTroops and factory attackers 
-- methods provided only for other modules (e.g. cfxGroundTroops or 
-- factoryZone 
--

function cfxOwnedZones.gatherAllManagedOwnedZones()
	-- we collect all zones with 'owner'
	local all = {}
	local pZones = cfxZones.zonesWithProperty("owner")
	for k, theZone in pairs(pZones) do
		all[theZone.name] = theZone
	end
	
	-- and add all zones with airfield 
	local pZones = cfxZones.zonesWithProperty("airfield")
	for k, theZone in pairs(pZones) do
		all[theZone.name] = theZone
	end	
	-- and all zones with 'FARP' 
	local pZones = cfxZones.zonesWithProperty("FARP")
	for k, theZone in pairs(pZones) do
		all[theZone.name] = theZone
	end	
	
	-- and all with ownAll?
	-- not yet 
	cfxOwnedZones.allManagedOwnedZones = all 
end

-- collect zones can filter owned zones. 
-- by default it filters all zones that are in water 
-- includes all managed-owner zones 
-- called from external sources
function cfxOwnedZones.collectZones(mode)
	if not mode then mode = "land" end 
	if mode == "land" then 
		local landZones = {}
		for idx, theZone in pairs(cfxOwnedZones.allManagedOwnedZones) do 
			p = theZone:getPoint()
			p.y = p.z 
			local surfType = land.getSurfaceType(p)
			if surfType == 3 then 
			else 
				table.insert(landZones, theZone)
			end
		end
		return landZones
	else 
		return cfxOwnedZones.allManagedOwnedZones
	end
end 

-- getNearestOwnedZoneToPoint invoked by heloTroops
function cfxOwnedZones.getNearestOwnedZoneToPoint(p)
	local allZones = cfxOwnedZones.collectZones()
	return cfxZones.getClosestZone(p, allZones)
end

-- getNearestEnemyOwnedZone invoked by cfxGroundTroops
function cfxOwnedZones.getNearestEnemyOwnedZone(theZone, targetNeutral)
	if not targetNeutral then targetNeutral = false else targetNeutral = true end
	local shortestDist = math.huge
	local closestZone = nil
	local allZones = cfxOwnedZones.collectZones()
	local ourEnemy = dcsCommon.getEnemyCoalitionFor(theZone.owner)
	if not ourEnemy then return nil end -- we called for a neutral zone. they have no enemies 
	local zPoint = theZone:getPoint()
	
	for zKey, aZone in pairs(allZones) do 
		if targetNeutral then 
			-- return all zones that do not belong to us
			if aZone.owner ~= theZone.owner and not aZone.untargetable then 
				local aPoint = aZone:getPoint()
				currDist = dcsCommon.dist(aPoint, zPoint)
				if currDist < shortestDist then 
					shortestDist = currDist
					closestZone = aZone
				end
			end
		else 
			-- return zones that are taken by the Enenmy
			if aZone.owner == ourEnemy and not aZone.untargetable then -- only check own zones
				local aPoint = aZone:getPoint()
				currDist = dcsCommon.dist(zPoint, aPoint)
				if currDist < shortestDist then 
					shortestDist = currDist
					closestZone = aZone
				end
			end
		end 
	end
	
	return closestZone, shortestDist
end

-- invoked by factory 
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
			zoneData.conquered = theZone:getFlagValue(theZone.conqueredFlag)
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
				theZone:setFlagValue(theZone.conqueredFlag, zData.conquered)
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
	cfxOwnedZones.verbose = theZone.verbose -- cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	cfxOwnedZones.announcer = theZone:getBoolFromZoneProperty("announcer", true)
	if theZone:hasProperty("announce") then 
		cfxZones.announcer = theZone:getBoolFromZoneProperty("announce", true)
	end 
	
	if theZone:hasProperty("r!") then 
		cfxOwnedZones.redTriggerFlag = theZone:getStringFromZoneProperty("r!", "*<cfxnone>")
	else 
		cfxOwnedZones.redTriggerFlag = theZone:getStringFromZoneProperty("r#", "*<cfxnone>")
	end
	if theZone:hasProperty("b!") then 
		cfxOwnedZones.redTriggerFlag = theZone:getStringFromZoneProperty("b!", "*<cfxnone>")
	else
		cfxOwnedZones.blueTriggerFlag = theZone:getStringFromZoneProperty("b#", "*<cfxnone>")
	end 
	
	if theZone:hasProperty("n!") then 
		cfxOwnedZones.redTriggerFlag = theZone:getStringFromZoneProperty("n!", "*<cfxnone>")
	else
		cfxOwnedZones.neutralTriggerFlag = theZone:getStringFromZoneProperty("n#", "*<cfxnone>")
	end
	
	-- allXXX flags
	if theZone:hasProperty("allBlue!") then 
		cfxOwnedZones.allBlue = theZone:getStringFromZoneProperty( "allBlue!", "*<cfxnone>")
		cfxOwnedZones.hasAllBlue = nil 
	end 
	
	if theZone:hasProperty("allRed!") then 
		cfxOwnedZones.allRed = theZone:getStringFromZoneProperty("allRed!", "*<cfxnone>")
		cfxOwnedZones.hasAllRed = nil 
	end
	
	if theZone:hasProperty("redOwned#") then 
		cfxOwnedZones.redOwned = theZone:getStringFromZoneProperty("redOwned#", "*<cfxnone>")
	end
	if theZone:hasProperty("blueOwned#") then 
		cfxOwnedZones.blueOwned = theZone:getStringFromZoneProperty( "blueOwned#", "*<cfxnone>")
	end
	if theZone:hasProperty("neutralOwned#") then 
		cfxOwnedZones.neutralOwned = theZone:getStringFromZoneProperty("neutralOwned#", "*<cfxnone>")
	end
	if theZone:hasProperty("totalZones#") then 
		cfxOwnedZones.totalOwnedZones = theZone:getStringFromZoneProperty("totalZones#", "*<cfxnone>")
	end
	-- numKeep, numCap, fastEval, easyContest
	cfxOwnedZones.numCap = theZone:getNumberFromZoneProperty("numCap", 1) -- minimal number of units required to cap zone 
	cfxOwnedZones.numKeep = theZone:getNumberFromZoneProperty("numKeep", 0) -- number required to keep zone 
	cfxOwnedZones.fastEval = theZone:getBoolFromZoneProperty("fastEval", true)
	cfxOwnedZones.easyContest = theZone:getBoolFromZoneProperty("easyContest", false)
	-- winSound, loseSound 
	cfxOwnedZones.winSound = theZone:getStringFromZoneProperty("winSound", "Quest Snare 3.wav")
	cfxOwnedZones.loseSound = theZone:getStringFromZoneProperty("loseSound", "Death BRASS.wav")

	-- capture options
	cfxOwnedZones.groundCap = theZone:getBoolFromZoneProperty("groundCap", true)
	cfxOwnedZones.navalCap = theZone:getBoolFromZoneProperty("navalCap", false)
	cfxOwnedZones.heloCap = theZone:getBoolFromZoneProperty("heloCap")
	cfxOwnedZones.fixWingCap = theZone:getBoolFromZoneProperty("fixWingCap")
	
	-- colors for line and fill 
	cfxOwnedZones.redLine = theZone:getRGBAVectorFromZoneProperty("redLine", {1.0, 0, 0, 1.0})
	cfxOwnedZones.redFill = theZone:getRGBAVectorFromZoneProperty("redFill", {1.0, 0, 0, 0.2})
	cfxOwnedZones.blueLine = theZone:getRGBAVectorFromZoneProperty("blueLine", {0.0, 0, 1.0, 1.0})
	cfxOwnedZones.blueFill = theZone:getRGBAVectorFromZoneProperty("blueFill", {0.0, 0, 1.0, 0.2})
	cfxOwnedZones.neutralLine = theZone:getRGBAVectorFromZoneProperty("neutralLine", {0.8, 0.8, 0.8, 1.0})
	cfxOwnedZones.neutralFill = theZone:getRGBAVectorFromZoneProperty("neutralFill", {0.8, 0.8, 0.8, 0.2})
	
	if theZone:hasProperty("excludedTypes") then 
		local theTypes = theZone:getStringFromZoneProperty("excludedTypes", "none")
		local typeArray = dcsCommon.splitString(theTypes, ",")
		typeArray = dcsCommon.trimArray(typeArray)
		cfxOwnedZones.excludedTypes = typeArray
	end 
	
	cfxOwnedZones.method = theZone:getStringFromZoneProperty("method", "inc")
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
	
	-- gather ALL managed owner zones 
	cfxOwnedZones.gatherAllManagedOwnedZones()
	
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
	
	noRed, noBlue options to prevent a zone to become that color 
	
	black color for dead. dead status to be defined. dead can't be capped and do not attact 
	
	
--]]--

