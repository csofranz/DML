camp = {}
camp.ups = 1
camp.version = "0.0.0"
camp.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"cfxMX",
	"bank"
}

--
-- CURRENTLY REQUIRES SINGLE-UNIT PLAYER GROUPS
--
camp.camps = {} -- all camps on the map 
camp.roots = {} -- all player group comms roots 

function camp.addCamp(theZone)
	camp.camps[theZone.name] = theZone
end

function camp.getMyCurrentCamp(theUnit) -- returns first hit plaayer is in
	local p = theUnit:getPoint()
	for idx, theCamp in pairs(camp.camps) do 
		if theCamp:pointInZone(p) then 
			return theCamp
		end 
	end
	return nil 
end 

function camp.createCampWithZone(theZone)
	-- look for all cloners inside my zone 
	if theZone.verbose or camp.verbose then 
		trigger.action.outText("+++camp: processing <" .. theZone.name .. ">, owner is <" .. theZone.owner .. ">", 30)
	end 
	
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
			if not aZone:hasProperty("blueOnly") then 
				table.insert(redCloners, aZone)
			end
			if not aZone:hasProperty("redOnly") then 
				table.insert(blueCloners, aZone)
			end
			if theZone.verbose or camp.verbose then 
				trigger.action.outText("Cloner <" .. aZone.name .. "> is part of camp <" .. theZone.name .. ">", 30)
			end 
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
end

--
-- update and event 
--
function camp.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(camp.update, {}, timer.getTime() + 1/camp.ups)
end 

function camp:onEvent(theEvent)

end 

--
-- Comms 
--	
function camp.processPlayers() 
	-- install coms stump for all players. they will be switched in/out 
	-- whenever it is apropriate 
	for idx, gData in pairs(cfxMX.playerGroupByName) do 
		gID = gData.groupId
		gName = gData.name 
		local theRoot = missionCommands.addSubMenuForGroup(gID, "Ground Repairs / Upgrades")
		camp.roots[gName] = theRoot 
		local c00 = missionCommands.addCommandForGroup(gID, "Theatre Overview", theRoot, camp.redirectTFunds, {gName, gID, "tfunds"})
		local c0 = missionCommands.addCommandForGroup(gID, "Local Funds & Status Overview", theRoot, camp.redirectFunds, {gName, gID, "funds"})
		local c1 = missionCommands.addCommandForGroup(gID, "REPAIRS: Purchase local repairs", theRoot, camp.redirectRepairs, {gName, gID, "repair"})
		local c2 = missionCommands.addCommandForGroup(gID, "UPGRADE: Purchase local upgrades", theRoot, camp.redirectUpgrades, {gName, gID, "upgrade"})
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

	-- now iterate all camps that are on my side
	for idx, theZone in pairs(camp.camps) do 
		if theZone.owner == coa then 
			msg = msg .. "\n  - <" .. theZone.name .. ">"

			if theZone.repairable and theZone.upgradable then 
				msg = msg .. " (§" .. theZone.repairCost .. "/§" .. theZone.upgradeCost .. ")"
				if camp.zoneNeedsRepairs(theZone, coa) then
					msg = msg .. " requests repairs and"
				else
					msg = msg .. " is running and"
				end 
				
				if camp.zoneNeedsUpgrades(theZone, coa) then
					msg = msg .. " can be upgraded"
				else
					msg = msg .. " is fully upgraded"
				end
				
			elseif theZone.repairable then 
				if camp.zoneNeedsRepairs(theZone, coa) then
					msg = msg .. " needs repairs (§" .. theZone.repairCost .. ")"
				else 
					msg = msg .. " is fully operational"
				end
				
			elseif theZone.upgradable then 
				if camp.zoneNeedsUpgrades(theZone, coa) then
					msg = msg .. " can be upgraded (§" .. theZone.upgradeCost .. ")"
				else 
					msg = msg .. " is fully upgraded"
				end			
			else 
				-- can be neither repaired nor upgraded
				msg = msg .. " is owned"
			end
		end
	end
	msg = msg .. "\n"
	trigger.action.outTextForGroup(gID, msg, 30)
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
		return 
	end
	local theZone = camp.getMyCurrentCamp(theUnit)
	if not theZone or (not theZone.repairable) or theZone.owner ~= theUnit:getCoalition() then 
		trigger.action.outTextForGroup(gID, msg, 30)
		return
	end 
	
	if camp.zoneNeedsRepairs(theZone, coa) then 
		msg = msg .. "\nZone <" .. theZone.name .. "> needs repairs (§" .. theZone.repairCost .. " per repair)\n"
	elseif theZone.repairable then 
		msg = msg .. "\nZone <" .. theZone.name .. "> has no outstanding repairs.\n"
	else 
		-- say nothing
	end 
	if camp.zoneNeedsUpgrades(theZone, coa) then 
		msg = msg .. "\nZone <" .. theZone.name .. "> can be upgraded (§" .. theZone.upgradeCost .. " per upgrade)\n"
	elseif theZone.upgradable then 
		msg = msg .. "\nZone <" .. theZone.name .. "> is fully upgraded.\n" 
	end 	
	trigger.action.outTextForGroup(gID, msg, 30)
end

--
-- REPAIRS
--
function camp.zoneNeedsRepairs(theZone, coa)
	-- return true if this zone needs repairs, i.e. it has cloners that have a damaged clone set 
	local myCloners = theZone.cloners 
	
	if not coa then 
		trigger.action.outText("+++camp: warning: no coa on zoneNeedsRepair for zone <" .. theZone.name .. ">", 30)	
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
		return 
	end
	if  dcsCommon.getUnitSpeed(theUnit) > 1 then 
		trigger.action.outTextForGroup(gID, "\nYou must come to a complete stop before being able to order repairs\n", 30)
		return 
	end
	local theZone = camp.getMyCurrentCamp(theUnit)
	if not theZone or not theZone.repairable then 
		trigger.action.outTextForGroup(gID, "\nYou are not inside a zone that can be repaired.\n", 30)
		return 
	end
	if theZone.owner ~= theUnit:getCoalition() then 
		trigger.action.outTextForGroup(gID, "\nYou currently do not own zone <" .. theZone.name .. ">. Capture it first.\n", 30)
		return
	end 
	
	-- if we get here, we are inside a zone that can be repaired. see if it needs repair and then get repair cost and see if we have enough fund to repair 
	if not camp.zoneNeedsRepairs(theZone, coa) then
		local msg = "\nZone <" .. theZone.name .. "> is already fully repaired.\n"
		if camp.zoneNeedsUpgrades(theZone, coa) then 
			msg = msg .. "\nZone <" .. theZone.name .. "> can be upgraded.\n"
		end 
		trigger.action.outTextForGroup(gID, msg, 30)
		return	
	end 
	
	-- see if we have enough funds 
	local hasBalance, amount = bank.getBalance(coa)
	if not hasBalance then 
		trigger.action.outText("+++camp: no balance for upgrade!", 30)
		return 
	end 
	
	if amount < theZone.repairCost then 
		trigger.action.outTextForGroup(gID, "\nYou curently cannot afford repairs here\n", 30)
		return 
	end 
	
	-- finally, let's repair
	camp.repairZone(theZone, coa)
--	theCloner = camp.zoneNeedsRepairs(theZone)
--	cloneZones.despawnAll(theCloner)
--	cloneZones.spawnWithCloner(theCloner)
	bank.withdawFunds(coa, theZone.repairCost)
	local ignore, remain = bank.getBalance(coa)
	trigger.action.outTextForCoalition(coa, "\nZone <" .. theZone.name .. "> was repaired by <" .. pName .. 
	"> for §" .. theZone.repairCost .. ".\nFaction has §" .. remain .. " remaining funds.\n", 30)
end

function camp.repairZone(theZone, coa)
	theCloner = camp.zoneNeedsRepairs(theZone, coa)
	if not theCloner then return end 
	cloneZones.despawnAll(theCloner)
	cloneZones.spawnWithCloner(theCloner)
end 
--
-- UPGRADES
--

function camp.zoneNeedsUpgrades(theZone, coa)
	-- return true if this zone can be upgraded, i.e. it has cloners that have an empty clone set  
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
		return 
	end
	if dcsCommon.getUnitSpeed(theUnit) > 1 then 
		trigger.action.outTextForGroup(gID, "\nYou must come to a complete stop before being able to order upgrades\n", 30)
		return 
	end
	local theZone = camp.getMyCurrentCamp(theUnit)
	if not theZone or not theZone.upgradable then 
		trigger.action.outTextForGroup(gID, "\nYou are not inside a zone that can be upgraded.\n", 30)
		return 
	end
	if theZone.owner ~= theUnit:getCoalition() then 
		trigger.action.outTextForGroup(gID, "\nYou currently do not own zone <" .. theZone.name .. ">. Capture it first.\n", 30)
		return
	end 
	
	if camp.zoneNeedsRepairs(theZone, coa) then 
		trigger.action.outTextForGroup(gID, "\nZone <" .. theZone.name .. "> requires repairs before it can be upgraded.\n", 30)
		return 
	end 
	
	-- if we get here, we are inside a zone that can be upgraded. see if it needs upgrades and then get upgrade cost and see if we have enough fund to do it  
	if not camp.zoneNeedsUpgrades(theZone, coa) then 
		trigger.action.outTextForGroup(gID, "\nZone <" .. theZone.name .. "> has been fully upgraded.\n", 30)
		return 
	end
	
	-- see if we have enough funds 
	local hasBalance, amount = bank.getBalance(coa)
	if not hasBalance then 
		trigger.action.outText("+++camp: no balance for upgrade!", 30)
		return 
	end 
	
	if amount < theZone.upgradeCost then 
		trigger.action.outTextForGroup(gID, "\nYou curently cannot afford an upgrade here\n", 30)
		return 
	end 
	
	-- finally, let's upgrade
	--theCloner = camp.zoneNeedsUpgrades(theZone)
	--cloneZones.spawnWithCloner(theCloner)
	camp.upgradeZone(theZone, coa)
	-- bill it to side 
	bank.withdawFunds(coa, theZone.upgradeCost)
	local ignore, remain = bank.getBalance(coa)
	trigger.action.outTextForCoalition(coa, "\nZone <" .. theZone.name .. "> was upgraded by <" .. pName .. 
	"> for §" .. theZone.upgradeCost .. ".\nFaction has §" .. remain .. " remaining funds.\n", 30)
end

-- can be called externally
function camp.upgradeZone(theZone, coa)
	theCloner = camp.zoneNeedsUpgrades(theZone, coa)
	if not theCloner then return end 
	cloneZones.spawnWithCloner(theCloner)
end
--
-- Config & Go
--

function camp.readConfigZone()
	local theZone = cfxZones.getZoneByName("campConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("campConfig") 
	end 
	
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