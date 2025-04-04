camp = {}
camp.ups = 1
camp.version = "1.1.0"
camp.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"cfxMX",
	"bank"
}
-- AUTOMATICALLY INTEGRATES WITH income MODULE IF PRESENT
-- REQUIRES CLONEZONES TO RUN (BUT NOT TO START) 
--[[--
VERSION HISTORY 
	1.0.0 - initial version 
	1.0.1 - changed "Ground Repairs / Upgrades" to "Funds / Repairs / Upgrades"
		  - provided income info for camp if it exists 
		  - provide income total if exists
		  - actionSound 
		  - output sound with communications 
	1.0.2 - integration with FARPZones 
	1.1.0 - support for DCS 2.9.6 dynamic spawns 
--]]--
--
-- CURRENTLY REQUIRES SINGLE-UNIT PLAYER GROUPS
-- REQUIRES CLONEZONES MODULE 
--
camp.camps = {} -- all camps on the map 
camp.roots = {} -- all player group comms roots 

function camp.addCamp(theZone)
	camp.camps[theZone.name] = theZone
end

function camp.getMyCurrentCamp(theUnit) -- returns first hit player is in
	local coa = theUnit:getCoalition()
	local p = theUnit:getPoint()
	for idx, theCamp in pairs(camp.camps) do 
		if theCamp.owner == coa and theCamp:pointInZone(p) then return theCamp end 
	end
	return nil 
end 

function camp.getCampsForCoa(coa)
	local myCamps = {}
	for idx, theCamp in pairs(camp.camps) do 
		if theCamp.owner == coa then table.insert(myCamps, theCamp) end 
	end
	return myCamps 
end

function camp.createCampWithZone(theZone)
	-- look for all cloners inside my zone 
	if theZone.verbose or camp.verbose then trigger.action.outText("+++camp: processing <" .. theZone.name .. ">, owner is <" .. theZone.owner .. ">", 30) end 
	
	local allZones = cfxZones.getAllZonesInsideZone(theZone)
	local cloners = {}
	local redCloners = {}
	local blueCloners = {}
	for idx, aZone in pairs(allZones) do 
		if aZone:hasProperty("nocamp") then 
			-- this zone cannot be part of a camp
		elseif aZone:hasProperty("cloner") then 
			-- this is a clone zone and part of my camp
			table.insert(cloners, aZone)
			if not aZone:hasProperty("blueOnly") then table.insert(redCloners, aZone) end 
			if not aZone:hasProperty("redOnly") then table.insert(blueCloners, aZone) end
			if theZone.verbose or camp.verbose then trigger.action.outText("Cloner <" .. aZone.name .. "> is part of camp <" .. theZone.name .. ">", 30) end 
		end 
	end 
	if #cloners < 1 then 
		trigger.action.outText("+++camp: warning: camp <" .. theZone.name .. "> has no cloners, can't be improved or repaired", 30)
	else 
		if camp.verbose or theZone.verbose then 
			trigger.action.outText("Camp <" .. theZone.name .. ">: <" .. #cloners .. "> reinforcable points, <" .. #redCloners .. "> for red and <" .. #blueCloners .. "> blue", 30)
		end
	end 
	theZone.cloners = cloners 
	theZone.redCloners = redCloners
	theZone.blueCloners = blueCloners
	theZone.repairable = theZone:getBoolFromZoneProperty("repair", true)
	theZone.upgradable = theZone:getBoolFromZoneProperty("upgrade", true)
	theZone.repairCost = theZone:getNumberFromZoneProperty("repairCost", 100)
	theZone.upgradeCost = theZone:getNumberFromZoneProperty("upgradeCost", 3 * theZone.repairCost)
	if theZone:hasProperty("FARP") then 
		theZone.isAlsoFARP = true 
		if theZone.verbose or camp.verbose then trigger.action.outText("+++camp: <" .. theZone.name .. "> has FARP attached", 30) end 
	end 
end

--
-- update and event 
--
function camp.update()
	-- call me in a second to poll triggers
--	timer.scheduleFunction(camp.update, {}, timer.getTime() + 1/camp.ups)
end 

function camp:onEvent(theEvent)
	if not theEvent then return end 
	if not theEvent.initiator then return end
	local theUnit = theEvent.initiator
	if not cfxMX.isDynamicPlayer(theUnit) then return end 
	local id = theEvent.id
	if id == 15 then -- birth 
		camp.lateProcessPlayer(theUnit)
		if camp.verbose then trigger.action.outText("camp: late player processing for <" .. theUnit:getName() .. ">", 30) end 
	end 
end 

--
-- Comms 
--	
function camp.lateProcessPlayer(theUnit)
	if not theUnit then return end 
	if not theUnit.getGroup then return end 
	local theGroup = theUnit:getGroup()
	local gName = theGroup:getName()
	local gID = theGroup:getID()
	camp.installComsFor(gID, gName)
end 

function camp.installComsFor(gID, gName)
	local theRoot = missionCommands.addSubMenuForGroup(gID, "Funds / Repairs / Upgrades")
	camp.roots[gName] = theRoot 
	local c00 = missionCommands.addCommandForGroup(gID, "Theatre Overview", theRoot, camp.redirectTFunds, {gName, gID, "tfunds"})
	local c0 = missionCommands.addCommandForGroup(gID, "Local Funds & Status Overview", theRoot, camp.redirectFunds, {gName, gID, "funds"})
	local c1 = missionCommands.addCommandForGroup(gID, "REPAIRS: Purchase local repairs", theRoot, camp.redirectRepairs, {gName, gID, "repair"})
	local c2 = missionCommands.addCommandForGroup(gID, "UPGRADE: Purchase local upgrades", theRoot, camp.redirectUpgrades, {gName, gID, "upgrade"})
end

function camp.processPlayers() 
	-- install coms stump for all players. they will be switched in/out 
	-- whenever it is apropriate 
	for idx, gData in pairs(cfxMX.playerGroupByName) do 
		gID = gData.groupId
		gName = gData.name 
		camp.installComsFor(gID, gName)
	end
end

function camp.redirectRepairs(args)
	timer.scheduleFunction(camp.doRepairs, args, timer.getTime() + 0.1)
end

function camp.redirectUpgrades(args)
	timer.scheduleFunction(camp.doUpgrades, args, timer.getTime() + 0.1)
end

function camp.redirectTFunds(args)
	timer.scheduleFunction(camp.doTFunds, args, timer.getTime() + 0.1 )
end

function camp.redirectFunds(args)
	timer.scheduleFunction(camp.doFunds, args, timer.getTime() + 0.1 )
end

function camp.doTFunds(args) 
	local gName = args[1]
	local gID = args[2]
	local theGroup = Group.getByName(gName)
	local coa = theGroup:getCoalition()
	local hasBalance, amount = bank.getBalance(coa)
	if not hasBalance then return end 
	local msg = "\nYour faction currently has §" .. amount .. " available for repairs/upgrades.\n"
	local income = 0
	-- now iterate all camps that are on my side
	for idx, theZone in pairs(camp.camps) do 
		if theZone.owner == coa then 
			msg = msg .. "\n  - <" .. theZone.name .. ">"
			if theZone.income then 
				msg = msg .. " Income: §" .. theZone.income 
				income = income + theZone.income 
			end 
			
			if theZone.repairable and theZone.upgradable then 
				msg = msg .. " (§" .. theZone.repairCost .. "/§" .. theZone.upgradeCost .. ")"
				if camp.zoneNeedsRepairs(theZone, coa) then msg = msg .. " requests repairs and" else msg = msg .. " is running and" end 
				
				if camp.zoneNeedsUpgrades(theZone, coa) then msg = msg .. " can be upgraded" else msg = msg .. " is fully upgraded" 	end
				
			elseif theZone.repairable then 
				if camp.zoneNeedsRepairs(theZone, coa) then msg = msg .. " needs repairs (§" .. theZone.repairCost .. ")" else msg = msg .. " is fully operational" end
				
			elseif theZone.upgradable then 
				if camp.zoneNeedsUpgrades(theZone, coa) then msg = msg .. " can be upgraded (§" .. theZone.upgradeCost .. ")" else msg = msg .. " is fully upgraded" end			
			else 
				-- can be neither repaired nor upgraded
				msg = msg .. " is owned"
			end
		end
	end
	if income > 0 then msg = msg .. "\n\nTotal Income: §" .. income end
	msg = msg .. "\n"
	trigger.action.outTextForGroup(gID, msg, 30)
	trigger.action.outSoundForGroup(gID, camp.actionSound)
end

function camp.doFunds(args)
	local gName = args[1]
	local gID = args[2]
	local theGroup = Group.getByName(gName)
	local coa = theGroup:getCoalition()
	local hasBalance, amount = bank.getBalance(coa)
	if not hasBalance then return end 
	local msg = "\nYour faction currently has §" .. amount .. " available for repairs/upgrades.\n"
	
	local allUnits = theGroup:getUnits()
	local theUnit = allUnits[1] -- always first unit until we get playerCommands
	if not Unit.isExist(theUnit) or theUnit:getLife() < 1 or 
		theUnit:inAir() or dcsCommon.getUnitSpeed(theUnit) > 1 then 
		trigger.action.outTextForGroup(gID, msg, 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end
	local theZone = camp.getMyCurrentCamp(theUnit)
	if not theZone or (not theZone.repairable) or theZone.owner ~= theUnit:getCoalition() then 
		trigger.action.outTextForGroup(gID, msg, 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return
	end 
	
	if camp.zoneNeedsRepairs(theZone, coa) then msg = msg .. "\nZone <" .. theZone.name .. "> needs repairs (§" .. theZone.repairCost .. " per repair)\n" 
	elseif theZone.repairable then msg = msg .. "\nZone <" .. theZone.name .. "> has no outstanding repairs.\n" end 
	if camp.zoneNeedsUpgrades(theZone, coa) then 
		msg = msg .. "\nZone <" .. theZone.name .. "> can be upgraded (§" .. theZone.upgradeCost .. " per upgrade)\n"
	elseif theZone.upgradable then 
		msg = msg .. "\nZone <" .. theZone.name .. "> is fully upgraded.\n" 
	end 	
	trigger.action.outTextForGroup(gID, msg, 30)
	trigger.action.outSoundForGroup(gID, camp.actionSound)
end

--
-- REPAIRS
--

function camp.zoneNeedsRepairs(theZone, coa)
	-- return true if this zone needs repairs, i.e. it has cloners that have a damaged clone set or FARP resource vehicles are incomplete
	if theZone.isAlsoFARP and FARPZones then 
		local theFarp = FARPZones.getFARPForZone(theZone)
		if FARPZones.serviceNeedsRepair(theFarp) then 
			if theZone.verbose or camp.verbose then 
				trigger.action.outText("camp: <" .. theZone.name .. "> has FARP service is dinged up...", 30)
			end
			return true 
			-- WARNING: RETURNS BOOLEAN, not a dmlZone!
		end
	end 
	
	local myCloners = theZone.cloners 
	
	if not coa then 
		trigger.action.outText("+++camp: warning: no coa on zoneNeedsRepairs for zone <" .. theZone.name .. ">", 30)	
	elseif coa == 1 then 
		myCloners = theZone.redCloners
	elseif coa == 2 then 
		myCloners = theZone.blueCloners
	end 
	
	if not theZone.repairable then return nil end 
	for idx, theCloner in pairs(myCloners) do 
		if theCloner.oSize and theCloner.oSize > 0 then 
			local currSize = cloneZones.countLiveAIUnits(theCloner)
			if currSize > 0 and currSize < theCloner.oSize then
				if theZone.verbose then 
					trigger.action.outText("+++camp: camp <" .. theZone.name .. "> has point <" .. theCloner.name .. "> that needs repair.", 30)
				end
				return theCloner
			else 
			end 
		end
	end 	
	return nil 
end 

function camp.doRepairs(args)
	local gName = args[1]
	local gID = args[2]
	local theGroup = Group.getByName(gName)
	local coa = theGroup:getCoalition()
	local allUnits = theGroup:getUnits()
	local theUnit = allUnits[1] -- always first unit until we get playerCommands
	if not Unit.isExist(theUnit) then return end 
	local pName = "<Error>"
	if theUnit.getPlayerName then pName = theUnit:getPlayerName() end 
	if not pName then pName = "<Big Err>" end 
	if theUnit:getLife() < 1 then return end 
	if theUnit:inAir() then 
		trigger.action.outTextForGroup(gID, "\nPlease land inside a fortified zone to order repairs\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end
	if  dcsCommon.getUnitSpeed(theUnit) > 1 then 
		trigger.action.outTextForGroup(gID, "\nYou must come to a complete stop before being able to order repairs\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end
	local theZone = camp.getMyCurrentCamp(theUnit)
	if not theZone or not theZone.repairable then 
		trigger.action.outTextForGroup(gID, "\nYou are not inside a zone that can be repaired.\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end
	if theZone.owner ~= theUnit:getCoalition() then 
		trigger.action.outTextForGroup(gID, "\nYou currently do not own zone <" .. theZone.name .. ">. Capture it first.\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return
	end 
	
	-- if we get here, we are inside a zone that can be repaired. see if it needs repair and then get repair cost and see if we have enough fund to repair 
	if not camp.zoneNeedsRepairs(theZone, coa) then
		local msg = "\nZone <" .. theZone.name .. "> is already fully repaired.\n"
		if camp.zoneNeedsUpgrades(theZone, coa) then 
			msg = msg .. "\nZone <" .. theZone.name .. "> can be upgraded.\n"
		end 
		trigger.action.outTextForGroup(gID, msg, 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return	
	end 
	
	-- see if we have enough funds 
	local hasBalance, amount = bank.getBalance(coa)
	if not hasBalance then 
		trigger.action.outText("+++camp: no balance for upgrade!", 30)
		return 
	end 
	
	if amount < theZone.repairCost then 
--		trigger.action.outTextForGroup(gID, "\nYou curently cannot afford repairs here\n", 30)
		trigger.action.outTextForGroup(gID, "\nYou curently cannot afford repairs here (§" .. theZone.repairCost .. " required, you have §" .. amount .. ")\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end 
	
	-- finally, let's repair
	camp.repairZone(theZone, coa)
--	theCloner = camp.zoneNeedsRepairs(theZone)
--	cloneZones.despawnAll(theCloner)
--	cloneZones.spawnWithCloner(theCloner)
	bank.withdawFunds(coa, theZone.repairCost)
	local ignore, remain = bank.getBalance(coa)
	trigger.action.outTextForCoalition(coa, "\nZone <" .. theZone.name .. "> was ordered repaired by <" .. pName .. 
	"> for §" .. theZone.repairCost .. ".\nFaction has §" .. remain .. " remaining funds.\n", 30)
	trigger.action.outSoundForCoalition(coa, camp.actionSound)
end

function camp.repairZone(theZone, coa)
	theCloner = camp.zoneNeedsRepairs(theZone, coa)
	if not theCloner then return end 
	if type(theCloner) == "boolean" then -- at least farp was dinged up 
		local theFarp = FARPZones.getFARPForZone(theZone)
		FARPZones.produceResourceVehicles(theFarp, coa) 
		if theZone.verbose or camp.verbose then 
			trigger.action.outText("+++camp: repaired FARP in camp <" .. theZone.name .. ">", 30)
		end 
	end 
	theCloner = camp.zoneNeedsRepairs(theZone, coa) -- do again to see if other repairs are needed. FARP repairs come free with first fix
	if not theCloner then return end
	cloneZones.despawnAll(theCloner)
	cloneZones.spawnWithCloner(theCloner)
end 
--
-- UPGRADES
--

function camp.zoneNeedsUpgrades(theZone, coa)
	-- returns first cloner in this zone that can be upgraded, i.e. it has cloners that have an empty clone set  
	if not theZone.upgradable then return nil end 
	
	local myCloners = theZone.cloners 
	
	if not coa then 
		trigger.action.outText("+++camp: warning: no coa on zoneNeedsUpgrades for zone <" .. theZone.name .. ">", 30)	
	elseif coa == 1 then 
		myCloners = theZone.redCloners
	elseif coa == 2 then 
		myCloners = theZone.blueCloners
	end 
	
	for idx, theCloner in pairs(myCloners) do 
		local currSize = cloneZones.countLiveAIUnits(theCloner)
		if currSize < 1 then
			if theZone.verbose then 
				trigger.action.outText("+++camp: camp <" .. theZone.name .. "> has point <" .. theCloner.name .. "> that can be  upgraded.", 30)
			end
			return theCloner
		else  
		end
	end 	
	
	return nil
end 

function camp.doUpgrades(args)
	local gName = args[1]
	local gID = args[2]
	local theGroup = Group.getByName(gName)
	local coa = theGroup:getCoalition()
	local allUnits = theGroup:getUnits()
	local theUnit = allUnits[1] -- always first unit until we get playerCommands
	if not Unit.isExist(theUnit) then return end 
	if theUnit:getLife() < 1 then return end 
	local pName = "<Error>"
	if theUnit.getPlayerName then pName = theUnit:getPlayerName() end 
	if not pName then pName = "<Big Err>" end 
	if theUnit:inAir() then 
		trigger.action.outTextForGroup(gID, "\nPlease land inside a fortified zone to order upgrades.\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end
	if dcsCommon.getUnitSpeed(theUnit) > 1 then 
		trigger.action.outTextForGroup(gID, "\nYou must come to a complete stop before being able to order upgrades\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end
	local theZone = camp.getMyCurrentCamp(theUnit)
	if not theZone or not theZone.upgradable then 
		trigger.action.outTextForGroup(gID, "\nYou are not inside a zone that can be upgraded.\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end
	if theZone.owner ~= theUnit:getCoalition() then 
		trigger.action.outTextForGroup(gID, "\nYou currently do not own zone <" .. theZone.name .. ">. Capture it first.\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return
	end 
	
	if camp.zoneNeedsRepairs(theZone, coa) then 
		trigger.action.outTextForGroup(gID, "\nZone <" .. theZone.name .. "> requires repairs before it can be upgraded.\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end 
	
	-- if we get here, we are inside a zone that can be upgraded. see if it needs upgrades and then get upgrade cost and see if we have enough fund to do it  
	if not camp.zoneNeedsUpgrades(theZone, coa) then 
		trigger.action.outTextForGroup(gID, "\nZone <" .. theZone.name .. "> has been fully upgraded.\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end
	
	-- see if we have enough funds 
	local hasBalance, amount = bank.getBalance(coa)
	if not hasBalance then 
		trigger.action.outText("+++camp: no balance for upgrade!", 30)
		return 
	end 
	
	if amount < theZone.upgradeCost then 
		trigger.action.outTextForGroup(gID, "\nYou curently cannot afford an upgrade here (§" .. theZone.upgradeCost .. " required, you have §" .. amount .. ")\n", 30)
		trigger.action.outSoundForGroup(gID, camp.actionSound)
		return 
	end 
	
	-- finally, let's upgrade
	--theCloner = camp.zoneNeedsUpgrades(theZone)
	--cloneZones.spawnWithCloner(theCloner)
	camp.upgradeZone(theZone, coa)
	-- bill it to side 
	bank.withdawFunds(coa, theZone.upgradeCost)
	local ignore, remain = bank.getBalance(coa)
	trigger.action.outTextForCoalition(coa, "\nZone <" .. theZone.name .. "> was ordered upgraded by <" .. pName .. 
	"> for §" .. theZone.upgradeCost .. ".\nFaction has §" .. remain .. " remaining funds.\n", 30)
	trigger.action.outSoundForCoalition(coa, camp.actionSound)
end

-- can be called externally
function camp.upgradeZone(theZone, coa)
	theCloner = camp.zoneNeedsUpgrades(theZone, coa)
	if not theCloner then return end 
	cloneZones.spawnWithCloner(theCloner)
end

--
-- API
--
function camp.campsThatNeedRepairs(coa) -- returns the zones that need repairs
	local repairs = {}
	for idx, theZone in pairs(camp.camps) do 
		if theZone.repairable and theZone.owner == coa and camp.zoneNeedsRepairs(theZone, coa) then 
			table.insert(repairs, theZone)
		end 
	end 

	return repairs 
end 

function camp.campsThatNeedUpgrades(coa) -- returns the zones that can be upgraded
	local repairs = {}
	for idx, theZone in pairs(camp.camps) do 
		if theZone.upgradable and theZone.owner == coa and camp.zoneNeedsUpgrades(theZone, coa) then 
			table.insert(repairs, theZone)
		end 
	end 

	return repairs 
end 

--
-- Config & Go
--

function camp.readConfigZone()
	local theZone = cfxZones.getZoneByName("campConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("campConfig") 
	end 
	camp.actionSound = theZone:getStringFromZoneProperty("actionSound", "Quest Snare 3.wav")
	camp.verbose = theZone.verbose
end

function camp.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("camp requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("camp", camp.requiredLibs) then
		return false 
	end
	
	-- read config 
	camp.readConfigZone()
	
	-- read zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("camp")
	for k, aZone in pairs(attrZones) do 
		camp.createCampWithZone(aZone) -- process attributes
		camp.addCamp(aZone) -- add to list
	end
	
	-- process all players 
	camp.processPlayers() 
	
	-- start update 
	camp.update()
	
	-- connect event handler 
	world.addEventHandler(camp)
	
	trigger.action.outText("camp v" .. camp.version .. " started.", 30)
	return true 
end

if not camp.start() then 
	trigger.action.outText("camp aborted: missing libraries", 30)
	camp = nil 
end

--[[--
	Ideas:
	re-supply: will restore REMAINING units at all points with fresh 
	units so that they can have full mags 
	costs as much as a full upgrade? hald way between upgrade and repair 
--]]--