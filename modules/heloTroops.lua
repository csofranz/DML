cfxHeloTroops = {}
cfxHeloTroops.version = "4.2.0"
cfxHeloTroops.verbose = false 
cfxHeloTroops.autoDrop = true 
cfxHeloTroops.autoPickup = false 
cfxHeloTroops.pickupRange = 100 -- meters 
cfxHeloTroops.requestRange = 500 -- meters
--
--[[--
 VERSION HISTORY
 4.0.0 - added dropZones
	   - enforceDropZones
	   - coalition for drop zones 
 4.1.0 - troops dropped in dropZones with active autodespawn are 
         filtered from load menu 
	   - updated eventhandler to new events and unitLost 
	   - timeStamp to avoid double-dipping 
	   - auto-pickup restricted as well 
	   - code cleanup
 4.2.0 - support for individual lase codes 
       - support for drivable 
	   
--]]--
cfxHeloTroops.minTime = 3 -- seconds beween tandings

cfxHeloTroops.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	"cfxZones", -- Zones, of course 
	"cfxCommander", -- to make troops do stuff
	"cfxGroundTroops", -- generic when dropping troops
}

cfxHeloTroops.unitConfigs = {} -- all configs are stored by unit's name 
cfxHeloTroops.troopWeight = 100 -- kg average weight per trooper 
cfxHeloTroops.dropZones = {} -- dict

-- persistence support 
cfxHeloTroops.deployedTroops = {}

--
-- drop zones 
--
function cfxHeloTroops.processDropZone(theZone)
	theZone.droppedFlag = theZone:getStringFromZoneProperty("dropZone!", "cfxNone")
	theZone.dropMethod = theZone:getStringFromZoneProperty("dropMethod", "inc")
	theZone.dropCoa = theZone:getCoalitionFromZoneProperty("coalition", 0)
	theZone.autoDespawn = theZone:getNumberFromZoneProperty("autoDespawn", -1)
end

--
-- comms
--
function cfxHeloTroops.resetConfig(conf)
	conf.autoDrop = cfxHeloTroops.autoDrop --if true, will drop troops on-board upon touchdown
	conf.autoPickup = cfxHeloTroops.autoPickup -- if true will load nearest troops upon touchdown
	conf.pickupRange = cfxHeloTroops.pickupRange --meters, maybe make per helo?
	conf.currentState = -1 -- 0 = landed, 1 = airborne, -1 undetermined
	conf.troopsOnBoardNum = 0 -- if not 0, we have troops and can spawnm/drop
	conf.troopCapacity = 8 -- should be depending on airframe 
	-- troopsOnBoard.name contains name of group
	-- the other fields info for troops picked up 
	conf.troopsOnBoard = {} -- table with the following
	conf.troopsOnBoard.name = "***reset***"
	conf.dropFormation = "circle_out" -- may be chosen later?
	conf.timeStamp = timer.getTime() -- to avoid double-dipping 
end

function cfxHeloTroops.createDefaultConfig(theUnit)
	local conf = {}
	cfxHeloTroops.resetConfig(conf)
	conf.myMainMenu = nil -- this is where the main menu for group will be stored
	conf.myCommands = nil -- this is where we put all teh commands in 
	return conf 
end

function cfxHeloTroops.getUnitConfig(theUnit) -- will create new config if not existing
	if not theUnit then
		trigger.action.outText("+++WARNING: nil unit in get config!", 30)
		return nil 
	end
	local c = cfxHeloTroops.unitConfigs[theUnit:getName()]
	if not c then 
		c = cfxHeloTroops.createDefaultConfig(theUnit)
		cfxHeloTroops.unitConfigs[theUnit:getName()] = c 
	end
	return c 
end

function cfxHeloTroops.getConfigForUnitNamed(aName)
	return cfxHeloTroops.unitConfigs[aName]
end

--
-- LANDED
--

function cfxHeloTroops.loadClosestGroup(conf)
	local p = conf.unit:getPosition().p
	local cat = Group.Category.GROUND
	local unitsToLoad = dcsCommon.getLivingGroupsAndDistInRangeToPoint(p, conf.pickupRange, conf.unit:getCoalition(), cat) 
	
	-- groups may contain units that are not for transport.
	-- for now we only load troops with legal type strings 
	unitsToLoad = cfxHeloTroops.filterTroopsByType(unitsToLoad)

	-- filter all groups that are inside a dropZone with a 
	-- positive autoDespawn attribute
	local mySide = conf.unit:getCoalition() 
	unitsToLoad = cfxHeloTroops.filterTroopsFromDropZones(unitsToLoad, mySide)
	
	-- now limit the options to the five closest legal groups
	local numUnits = #unitsToLoad
	if numUnits < 1 then return false end -- on false will drop through 
	
	local aTeam = unitsToLoad[1] -- get first (closest) entry
	local dist = aTeam.dist 
	local group = aTeam.group 
	cfxHeloTroops.doLoadGroup({conf, group})
	return true -- will have loaded and reset menu
end

function cfxHeloTroops.heloLanded(theUnit)
	-- when we have landed, 
	if not dcsCommon.isTroopCarrier(theUnit, cfxHeloTroops.troopCarriers) then return end
	local conf = cfxHeloTroops.getUnitConfig(theUnit)
	-- prevent double-dipping on land and depart
	local now = timer.getTime()
	local diff = now - conf.timeStamp
	if diff < cfxHeloTroops.minTime then 
		if cfxHeloTroops.verbose then 
			trigger.action.outText("+++heloT-heloLanded: filtered for time restraint <" .. diff .. ">", 30)
		end
		return
	end
	if cfxHeloTroops.verbose then 
		trigger.action.outText("+++heloT-heloLanded: resetting timeStamp for delta <" .. diff .. ">", 30)
	end
	conf.timeStamp = now 
	
	conf.unit = theUnit
	conf.currentState = 0
	-- auto-unload
	if conf.autoDrop then 
		if conf.troopsOnBoardNum > 0 then 
			cfxHeloTroops.doDeployTroops({conf, "autodrop"})
			-- doDeployTroops() invokes set menu and empties troopsOnBoard
			return
		end
		-- no troops to drop on board 
	end
	if conf.autoPickup then 
		if conf.troopsOnBoardNum < 1 then
			-- load the closest group
			if cfxHeloTroops.loadClosestGroup(conf) then 
				return
			end
		end		
	end
	-- reset menu 
	cfxHeloTroops.removeComms(conf.unit)
	cfxHeloTroops.setCommsMenu(conf.unit)
end

--
-- Helo took off
--

function cfxHeloTroops.heloDeparted(theUnit)
	if not dcsCommon.isTroopCarrier(theUnit, cfxHeloTroops.troopCarriers) then return end
	-- change the state to airborne, and update menus 
	local conf = cfxHeloTroops.getUnitConfig(theUnit)
	-- prevent double-dipping on land and depart
	local now = timer.getTime()
	local diff = now - conf.timeStamp
	if cfxHeloTroops.verbose then 
		trigger.action.outText("+++heloT-heloDeparted: resetting timeStamp for delta <" .. diff .. ">", 30)
	end
	conf.timeStamp = now 
	conf.currentState = 1 -- in the air 
	cfxHeloTroops.removeComms(conf.unit)
	cfxHeloTroops.setCommsMenu(conf.unit)
end

-- 
-- Helo Crashed 
--

function cfxHeloTroops.cleanHelo(theUnit)
	-- clean up 
	local conf = cfxHeloTroops.getUnitConfig(theUnit)
	conf.unit = theUnit 
	conf.troopsOnBoardNum = 0 -- all dead 
	conf.currentState = -1 -- (we don't know)
	-- check if we need to interface with groupTracker 
	if conf.troopsOnBoard.name and groupTracker then 
		local theName = conf.troopsOnBoard.name
		-- there was (possibly) a group on board. see if it was tracked
		local isTracking, numTracking, trackers = groupTracker.groupNameTrackedBy(theName)
		-- if so, remove it from limbo 
		if isTracking then 
			for idx, theTracker in pairs(trackers) do 
				groupTracker.removeGroupNamedFromTracker(theName, theTracker)
				if cfxHeloTroops.verbose then 
					trigger.action.outText("+++Helo: removed group <" .. theName .. "> from tracker <" .. theTracker.name .. ">", 30)
				end 
			end 
		end
	end
	conf.troopsOnBoard = {}
end

function cfxHeloTroops.heloCrashed(theUnit)
	if not dcsCommon.isTroopCarrier(theUnit, cfxHeloTroops.troopCarriers) then return 
	end
	-- clean up 
	cfxHeloTroops.cleanHelo(theUnit)
end

--
-- M E N U   H A N D L I N G   &   R E S P O N S E 
-- 
 
function cfxHeloTroops.clearCommsSubmenus(conf)
	if conf.myCommands then 
		for i=1, #conf.myCommands do
			missionCommands.removeItemForGroup(conf.id, conf.myCommands[i])
		end
	end
	conf.myCommands = {}
end

function cfxHeloTroops.removeCommsFromConfig(conf)
	cfxHeloTroops.clearCommsSubmenus(conf)
	if conf.myMainMenu then 
		missionCommands.removeItemForGroup(conf.id, conf.myMainMenu) 
		conf.myMainMenu = nil
	end
end

function cfxHeloTroops.removeComms(theUnit)
	if not theUnit then return end
	if not theUnit:isExist() then return end 
	local group = theUnit:getGroup() 
	local id = group:getID()
	local conf = cfxHeloTroops.getUnitConfig(theUnit)
	conf.id = id
	conf.unit = theUnit 
	cfxHeloTroops.removeCommsFromConfig(conf)
end

function cfxHeloTroops.addConfigMenu(conf)
	-- we add a menu showing current configs 
	local onOff = "OFF"
	if conf.autoDrop then onOff = "ON" end 
	local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				'Auto-Drop: ' .. onOff .. ' - Select to change',
				conf.myMainMenu,
				cfxHeloTroops.redirectToggleConfig, 
				{conf, "drop"}
				)
	table.insert(conf.myCommands, theCommand)
	onOff = "OFF"
	if conf.autoPickup then onOff = "ON" end 
	theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				'Auto-Pickup: ' .. onOff .. ' - Select to change',
				conf.myMainMenu,
				cfxHeloTroops.redirectToggleConfig, 
				{conf, "pickup"}
				)
	table.insert(conf.myCommands, theCommand)
end

function cfxHeloTroops.setCommsMenu(theUnit)
	-- compatible with DCS 2.9.6 dynamic spawns 
	if cfxHeloTroops.verbose then 
		trigger.action.outText("+++heloT: setComms for player unit <" .. theUnit:getName() .. ">: ENTER.", 30)
	end

	if not theUnit then return end
	if not theUnit:isExist() then return end 	
	-- we only add this menu to troop carriers 
	if not dcsCommon.isTroopCarrier(theUnit, cfxHeloTroops.troopCarriers) then
		if cfxHeloTroops.verbose then 
			trigger.action.outText("+++heloT - player unit <" .. theUnit:getName() .. "> type <" .. theUnit:getTypeName() .. "> is not legal troop carrier.", 30)
		end
		return 
	end
	
	local group = theUnit:getGroup() 
	local id = group:getID()
	local conf = cfxHeloTroops.getUnitConfig(theUnit)
	-- set time stamp to avoid double-dipping later 
	--conf.timeStamp = timer.getTime() -- to avoid double-dipping 
	conf.id = id; -- we ALWAYS do this so it is current even after a crash 
	conf.unit = theUnit -- link back
	-- if we don't have an F-10 menu, create one 
	if not (conf.myMainMenu) then 
		conf.myMainMenu = missionCommands.addSubMenuForGroup(id, 'Airlift Troops') 
	end
	-- clear out existing commands, add new
	cfxHeloTroops.clearCommsSubmenus(conf)
	cfxHeloTroops.addConfigMenu(conf)
	
	-- now see if we are on the ground or in the air
	-- or unknown
	if conf.currentState < 0 then 
		conf.currentState = 0 -- landed
		if theUnit:inAir() then 
			conf.currentState = 1
		end
	end
	if conf.currentState == 0 then 
		cfxHeloTroops.addGroundMenu(conf)
	else 
		cfxHeloTroops.addAirborneMenu(conf)
	end	
end

function cfxHeloTroops.addAirborneMenu(conf)
	-- while airborne, add a status menu
	local commandTxt = "(To load troops, land in proximity to them)"
	if conf.troopsOnBoardNum > 0 then 
		commandTxt = "(You are carrying " .. conf.troopsOnBoardNum .. " Infantry. Land to deploy them)"
	end
	local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				cfxHeloTroops.redirectNoAction, 
				{conf, "none"}
				)
	table.insert(conf.myCommands, theCommand)
end

function cfxHeloTroops.redirectNoAction(args)
	-- we do not redirect since there is nothing to do
end

function cfxHeloTroops.addGroundMenu(conf)
	-- Player can deploy troops when loaded
	-- or load troops when they are in proximity
	if cfxHeloTroops.verbose then 
		trigger.action.outText("+++heloT: ENTER addGroundMenu for unit <" .. conf.unit:getName() .. "> with <" .. conf.troopsOnBoardNum .. "> troops on board", 30)
	end 
	
	-- case 1: troops aboard 
	if conf.troopsOnBoardNum > 0 then 
		if cfxHeloTroops.verbose then 
			trigger.action.outText("+++heloT: unit <" .. conf.unit:getName() .. "> has <" .. conf.troopsOnBoardNum .. "> troops on board", 30)
		end 
		local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				"Deploy Team <" .. conf.troopsOnBoard.name .. ">",
				conf.myMainMenu,
				cfxHeloTroops.redirectDeployTroops, 
				{conf, "deploy"}
				)
		table.insert(conf.myCommands, theCommand)
		return -- no loading
	end
	
	-- case 2A: no troops aboard. requestable spawners/cloners in range? 
	local p = conf.unit:getPosition().p
	local mySide = conf.unit:getCoalition() 

	-- collect available spawn zones 
	local availableSpawners = {}
	if cfxSpawnZones then -- only if SpawnZones is implemented 
		local availableSpawnersRaw = cfxSpawnZones.getRequestableSpawnersInRange(p, cfxHeloTroops.requestRange, mySide)
		
		for idx, aSpawner in pairs(availableSpawnersRaw) do 
			-- filter all spawners that spawn "illegal" troops
			local theTypes = aSpawner.types
			local typeArray = dcsCommon.splitString(theTypes, ',')
			typeArray = dcsCommon.trimArray(typeArray)
			local allLegal = true 
			-- check agianst default (dcsCommon) or own definition (if exists)
			for idy, aType in pairs(typeArray) do 
				if cfxHeloTroops.legalTroops then 
					if not dcsCommon.arrayContainsString(cfxHeloTroops.legalTroops, aType) then 
						allLegal = false 
--						trigger.action.outText("spawner <" .. aSpawner.name .. ">: troop type <" .. aType .. "> is illegal", 30)
					end
				else 
					if not dcsCommon.typeIsInfantry(aType) then 
						allLegal = false 
--						trigger.action.outText("spawner <" .. aSpawner.name .. ">: troop type <" .. aType .. "> is not infantry", 30)
					end
				end
			end
			if allLegal then 
				table.insert(availableSpawners, aSpawner)
			end
		end
	end 
	
	-- collect available clone zones 
	if cloneZones then 
		local availableSpawnersRaw = cloneZones.getRequestableClonersInRange(p, cfxHeloTroops.requestRange, mySide)
		for idx, aSpawner in pairs(availableSpawnersRaw) do 
			-- filter all spawners that spawn "illegal" troops or have none
			local theTypes = aSpawner.allTypes
			local allLegal = true
			local numTypes = dcsCommon.getSizeOfTable(theTypes)
			if numTypes > 0 then 
				for aType, cnt in pairs(theTypes) do
					if cfxHeloTroops.legalTroops then 
						if not dcsCommon.arrayContainsString(cfxHeloTroops.legalTroops, aType) then 
							allLegal = false 
						end
					else 
						if not dcsCommon.typeIsInfantry(aType) then 
							allLegal = false 
						end
					end
				end
			else 
				allegal = false 
			end
			
			if allLegal then 
				table.insert(availableSpawners, aSpawner)
			end
		end
	end
	
	local numSpawners = #availableSpawners
	if numSpawners > 5 then numSpawners = 5 end 
	while numSpawners > 0 do
		-- for each spawner in range, create a menu item
		local spawner = availableSpawners[numSpawners]
		local theName = spawner.baseName 
		local comm = "Request <" .. theName .. "> troops for transport"
		local theCommand =  missionCommands.addCommandForGroup(
			conf.id, 
			comm,
			conf.myMainMenu,
			cfxHeloTroops.redirectSpawnGroup, 
			{conf, spawner}
			)
		table.insert(conf.myCommands, theCommand)
		numSpawners = numSpawners - 1
	end
	
	-- Collect troops in range that we can load up 
	local cat = Group.Category.GROUND
	local unitsToLoad = dcsCommon.getLivingGroupsAndDistInRangeToPoint(p, conf.pickupRange, conf.unit:getCoalition(), cat) 
	
	-- the groups may contain units that are not for transport.
	-- later we can filter this by weight, or other cool stuff
	-- for now we simply only troopy with legal type strings 
	-- TODO: add weight filtering 
	unitsToLoad = cfxHeloTroops.filterTroopsByType(unitsToLoad)

	-- filter all groups that are inside a dropZone with a 
	-- positive autoDespawn attribute
	unitsToLoad = cfxHeloTroops.filterTroopsFromDropZones(unitsToLoad, mySide)
	
	-- now limit the options to the five closest legal groups
	local numUnits = #unitsToLoad
	if numUnits > 5 then numUnits = 5 end
	if numUnits < 1 then 
		local theCommand = missionCommands.addCommandForGroup(
				conf.id, 
				"(No units in range)",
				conf.myMainMenu,
				cfxHeloTroops.redirectNoAction, 
				{conf, "none"}
				)
		table.insert(conf.myCommands, theCommand)
		return
	end
	
	-- add an entry for each group in units to load 
	for i=1, numUnits do 
		local aTeam = unitsToLoad[i]
		local dist = aTeam.dist 
		local group = aTeam.group 
		local tNum = group:getSize()
		local comm = "Load <" .. group:getName() .. "> " .. tNum .. " Members" 
		local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				comm,
				conf.myMainMenu,
				cfxHeloTroops.redirectLoadGroup, 
				{conf, group}
				)
		table.insert(conf.myCommands, theCommand)
	end
end

function cfxHeloTroops.filterTroopsByType(unitsToLoad)
	local filteredGroups = {}
	for idx, aTeam in pairs(unitsToLoad) do 
		local group = aTeam.group
		local theTypes = dcsCommon.getGroupTypeString(group)

		local aT = dcsCommon.splitString(theTypes, ",")
		local pass = true 
		for iT, sT in pairs(aT) do 
			-- check if this is a valid type 
			if cfxHeloTroops.legalTroops then 
				if not dcsCommon.arrayContainsString(cfxHeloTroops.legalTroops, sT) then 
					pass = false
					break 
				end
			else 
				if not dcsCommon.typeIsInfantry(sT) then 
					pass = false
					break 
				end
			end
		end 
		-- check if we are about to pre-empt a CSAR mission
		if csarManager then 
			if csarManager.isCSARTarget(group) then 
				-- this one is managed by csarManager,
				-- don't load it for helo troops
				pass = false 
			end
		end
			
		if pass then 
			table.insert(filteredGroups, aTeam)
		end
	end
	return filteredGroups
end

function cfxHeloTroops.filterTroopsFromDropZones(allTroops, mySide)
	-- quick-out: no dropZones 
	if dcsCommon.getSizeOfTable(cfxHeloTroops.dropZones) < 1 then return allTroops end
	local filtered = {}
	for idx, theTeam in pairs(allTroops) do 
		-- theTeam is a table {group, dist}
		local theGroup = theTeam.group 
		local firstUnit = theGroup:getUnit(1)
		local include = true 
		if firstUnit and Unit.isExist(firstUnit) then 
			local p = firstUnit:getPoint()
			for idy, theZone in pairs(cfxHeloTroops.dropZones) do 
				if theZone.autoDespawn > 0 and 
				(theZone:getCoalition() == 0 or theZone:getCoalition() == mySide) 
				then 
					-- see if the unit is inside this zone 
					if theZone:isPointInsideZone(p) then 
						include = false -- filter out 
						if theZone.verbose then 
							trigger.action.outText("+++helo: filtered group <" .. theGroup:getName() .. "> from 'load' menu. Reason: autoDespawn active in deploy zone <" .. theZone.name .. ">", 30)
						end 
					end
				end
			end
		end
		if include then table.insert(filtered, theTeam) end 
	end
	return filtered 
end 
--
-- T O G G L E S 
--
function cfxHeloTroops.redirectToggleConfig(args)
	timer.scheduleFunction(cfxHeloTroops.doToggleConfig, args, timer.getTime() + 0.1)
end

function cfxHeloTroops.doToggleConfig(args)
	local conf = args[1]
	local what = args[2]
	if what == "drop" then 
		conf.autoDrop = not conf.autoDrop
		if conf.autoDrop then 
			trigger.action.outTextForGroup(conf.id, "Now deploying troops immediately after landing", 30)
		else 
			trigger.action.outTextForGroup(conf.id, "Troops will now only deploy when told to", 30)		
		end
	else 
		conf.autoPickup = not conf.autoPickup
		if conf.autoPickup then 
			trigger.action.outTextForGroup(conf.id, "Nearest troops will now automatically board after landing", 30)
		else
			trigger.action.outTextForGroup(conf.id, "Troops will now board only after being ordered to do so", 30)
		end
	end
	cfxHeloTroops.setCommsMenu(conf.unit)
end

--
-- Deploying Troops
--
function cfxHeloTroops.redirectDeployTroops(args)
	timer.scheduleFunction(cfxHeloTroops.doDeployTroops, args, timer.getTime() + 0.1)
end

function cfxHeloTroops.scoreWhenCapturing(theUnit)
	if theUnit and Unit.isExist(theUnit) and theUnit.getPlayerName then 
		-- see if we are inside a non-alinged zone (incl. neutral)
		local coa = theUnit:getCoalition()
		local p = theUnit:getPoint()
		local theGroup = theUnit:getGroup()
		local ID = theGroup:getID()
		local nearestZone, dist = cfxOwnedZones.getNearestOwnedZoneToPoint(p)
		if nearestZone and nearestZone:pointInZone(p) then  
			-- we are inside an owned zone!
			if nearestZone.owner ~= coa then 
				-- yup, combat drop!
				local theScore = cfxHeloTroops.combatDropScore
				local pName = theUnit:getPlayerName()
				if pName then 
					cfxPlayerScore.updateScoreForPlayer(pName, theScore)
					cfxPlayerScore.logFeatForPlayer(pName, "Combat Troop Insertion at " .. nearestZone.name, coa)
				end
			end
		end
	end
end

function cfxHeloTroops.isInsideDropZone(theUnit)
	local p = theUnit:getPoint()
	for idx, theZone in pairs (cfxHeloTroops.dropZones) do 
		if theZone:isPointInsideZone(p) then return true end 
	end
	return false 
end

function cfxHeloTroops.doDeployTroops(args)
	local conf = args[1]
	local what = args[2]
	local theUnit = conf.unit
	local theGroup = theUnit:getGroup()
	local gid = theGroup:getID()
	local inside = cfxHeloTroops.isInsideDropZone(theUnit)
	if (not inside) and cfxHeloTroops.enforceDropZones then 
		trigger.action.outTextForGroup(gid, "You are outside an disembark/drop zone.", 30)
		return 
	end 
	
	-- deploy the troops I have on board
	cfxHeloTroops.deployTroopsFromHelicopter(conf)
	-- interface with playerscore if we dropped 
	-- inside an enemy-owned zone 
	if cfxPlayerScore and cfxOwnedZones then 
		--local theUnit = conf.unit
		cfxHeloTroops.scoreWhenCapturing(theUnit)
	end
	
	-- set own troops to 0 and erase type string 
	conf.troopsOnBoardNum = 0
	conf.troopsOnBoard = {}
	conf.troopsOnBoard.name = "***wasdeployed***"
	cfxHeloTroops.unitConfigs[theUnit:getName()] = conf -- forced write-back (strange...)
	if cfxHeloTroops.verbose then 
		trigger.action.outText("+++heloT: doDeployTroops unit <" .. conf.unit:getName() .. "> reset to <" .. conf.troopsOnBoardNum .. "> troops on board", 30)
	end 
	-- reset menu 
	cfxHeloTroops.removeComms(conf.unit)
	cfxHeloTroops.setCommsMenu(conf.unit)
end


function cfxHeloTroops.deployTroopsFromHelicopter(conf)
	local unitTypes = {} -- build type names
	local theUnit = conf.unit 
	local p = theUnit:getPoint() 
	-- split the conf.troopsOnBoardTypes into an array of types
	unitTypes = dcsCommon.splitString(conf.troopsOnBoard.types, ",")
	if #unitTypes < 1 then 
		table.insert(unitTypes, "Soldier M4") -- fallback
	end
	
	local range = conf.troopsOnBoard.range
	local orders = conf.troopsOnBoard.orders 
	local dest = conf.troopsOnBoard.destination
	local theName = conf.troopsOnBoard.name 
	local moveFormation = conf.troopsOnBoard.moveFormation 
	local code = conf.troopsOnBoard.code 
	local canDrive = conf.troopsOnBoard.canDrive 
	
	if not orders then orders = "guard" end
	orders = string.lower(orders) 
	
	-- order processing: if the orders were pre-pended with "wait-"
	-- we now remove that, so after dropping they do what their 
	-- orders where AFTER being picked up
	if dcsCommon.stringStartsWith(orders, "wait-") then 
		orders = dcsCommon.removePrefix(orders, "wait-")
		trigger.action.outTextForGroup(conf.id, "+++ <" .. conf.troopsOnBoard.name .. "> revoke 'wait' orders, proceed with <".. orders .. ">", 30)
	end
	
	local chopperZone = cfxZones.createSimpleZone("choppa", p, 12) -- 12 m radius around choppa
	local theCoalition = theUnit:getGroup():getCoalition() -- make it chopper's COALITION
	local theGroup, theData = cfxZones.createGroundUnitsInZoneForCoalition (
				theCoalition, 											
				theName, -- group name, may be tracked 
				chopperZone, 											
				unitTypes, 												
				conf.dropFormation,
				90,
				nil, -- liveries not yet supported 
				canDrive)
	-- persistence management 
	local troopData = {}
	troopData.groupData = theData
	troopData.orders = orders -- always set  
	troopData.side = theCoalition
	troopData.range = range
	troopData.destination = dest -- only for attackzone orders 
	cfxHeloTroops.deployedTroops[theData.name] = troopData 
	
	local troop = cfxGroundTroops.createGroundTroops(theGroup, range, orders, moveFormation, code, canDrive) 
	if orders == "captureandhold" then 
		-- we get the target zone NOW!!! before we flip the zone and 
		-- and make them run to the wrong zone 
		dest = cfxGroundTroops.getClosestEnemyZone(troop)
		troopData.destination = dest
		if dest then 
			trigger.action.outText("Inserting troops to capture zone <" .. dest.name .. ">", 30)
		else 
			trigger.action.outText("+++heloT: WARNING: cap&hold: can't find a zone to cap.", 30)
		end
	end 
	
	troop.destination = dest -- transfer target zone for attackzone oders
	cfxGroundTroops.addGroundTroopsToPool(troop) -- will schedule move orders
	trigger.action.outTextForGroup(conf.id, "<" .. theGroup:getName() .. "> have deployed to the ground with orders " .. orders .. "!", 30)
	trigger.action.outSoundForGroup(conf.id, cfxHeloTroops.disembarkSound) 
	-- if tracked by a tracker, and pass them back for un-limbo 
	if groupTracker then 
		local isTracking, numTracking, trackers = groupTracker.groupNameTrackedBy(theName)
		if isTracking then 
			for idx, theTracker in pairs (trackers) do 
				groupTracker.addGroupToTracker(theGroup, theTracker)
				if cfxHeloTroops.verbose then 
					trigger.action.outText("+++Helo: un-limbo and tracking group <" .. theName .. "> with tracker <" .. theTracker.name .. ">", 30)
				end
			end
		end
	end
	
	-- bang on dropZones
	for name, theZone in pairs(cfxHeloTroops.dropZones) do 
		-- can employ coalition test here as well, maybe later? 
		if theZone:isPointInsideZone(p) then 
			if theZone.dropCoa == 0 or theCoalition == theZone.dropCoa then 
				if cfxHeloTroops.verbose or theZone.verbose then 
					trigger.action.outText("+++Helo: will bang! on dropZone <" .. theZone.name .. "> output dropZone! <" .. theZone.droppedFlag .. "> with method <" .. theZone.dropMethod .. ">", 30)
				end 
				theZone:pollFlag(theZone.droppedFlag, theZone.dropMethod)
			end 
			if theZone.autoDespawn and theZone.autoDespawn > 0 then 
				args = {}
				args.theZone = theZone 
				args.theGroup = theGroup
				timer.scheduleFunction(cfxHeloTroops.autoDespawn, args, timer.getTime() + theZone.autoDespawn)
			end
		end
	end 
end

function cfxHeloTroops.autoDespawn(args)
	if not args then return end 
	local theZone = args.theZone 
	local theGroup = args.theGroup 
	if theZone.verbose then 
		trigger.action.outText("+++Helo: auto-despawning drop in drop zone <" .. theZone.name .. ">", 30)
	end 
	if not theGroup then return end 
	if Group.isExist(theGroup) then 
		Group.destroy(theGroup)
	end
end
--
-- Loading Troops
--
function cfxHeloTroops.redirectLoadGroup(args)
	timer.scheduleFunction(cfxHeloTroops.doLoadGroup, args, timer.getTime() + 0.1)
end

function cfxHeloTroops.doLoadGroup(args) 
	local conf = args[1]
	local group = args[2]
	if not group then return end 
	if not Group.isExist(group) then return end -- edge case: group died in the past 0.1 seconds
	conf.troopsOnBoard = {}
	-- all we need to do is disassemble the group into type 
	conf.troopsOnBoard.types = dcsCommon.getGroupTypeString(group)
	-- get the size 
	conf.troopsOnBoardNum = group:getSize()
	-- and name 
	local gName = group:getName()
	conf.troopsOnBoard.name = gName
	-- and put it all into the helicopter config 
	
	-- destroy the group:
	-- if it was tracked, tell tracker to move it to limbo 
	-- to remember it 
	if groupTracker then
		-- only if groupTracker is active
		local isTracking, numTracking, trackers = groupTracker.groupTrackedBy(group)
		if isTracking then 
			-- we need to put them in limbo for every tracker 
			for idx, aTracker in pairs(trackers) do 
				if cfxHeloTroops.verbose then 
					trigger.action.outText("+++Helo: moving group <" .. gName .. "> to limbo for tracker <" .. aTracker.name .. ">", 30)
				end 
				groupTracker.moveGroupToLimboForTracker(group, aTracker)
			end
		end
	end 
	
	-- then, remove it from the pool
	local pooledGroup = cfxGroundTroops.getGroundTroopsForGroup(group)
	if pooledGroup then 
		-- copy important info from the troops 
		-- if they are set 
		conf.troopsOnBoard.orders = pooledGroup.orders
		conf.troopsOnBoard.range = pooledGroup.range
		conf.troopsOnBoard.destination = pooledGroup.destination -- may be nil 
		conf.troopsOnBoard.moveFormation = pooledGroup.moveFormation
		if pooledGroup.orders and pooledGroup.orders == "captureandhold" then 
			conf.troopsOnBoard.destination = nil -- forget last destination so they can be helo-redeployed
		end 
		conf.troopsOnBoard.code = pooledGroup.code 
		conf.troopsOnBoard.canDrive = pooledGroup.canDrive 
		
		cfxGroundTroops.removeTroopsFromPool(pooledGroup)
		trigger.action.outTextForGroup(conf.id, "Team '".. conf.troopsOnBoard.name .."' loaded and has orders <" .. conf.troopsOnBoard.orders .. ">", 30)
	else 
		if cfxHeloTroops.verbose then 
			trigger.action.outText("+++heloT: ".. conf.troopsOnBoard.name .." was not committed to ground troops", 30)
		end
	end
		
	-- TODO: add weight changing code 
	-- TODO: ensure compatibility with CSAR module
	group:destroy()	
	-- now immediately run a GC so this group is removed 
	-- from any save data
	cfxHeloTroops.GC()
	-- say so 
	trigger.action.outTextForGroup(conf.id, "Team '".. conf.troopsOnBoard.name .."' aboard, ready to go!", 30)
	trigger.action.outSoundForGroup(conf.id, cfxHeloTroops.loadSound)

	-- reset menu 
	cfxHeloTroops.removeComms(conf.unit)
	cfxHeloTroops.setCommsMenu(conf.unit)
end

--
-- spawning troops 
--
function cfxHeloTroops.redirectSpawnGroup(args)
	timer.scheduleFunction(cfxHeloTroops.doSpawnGroup, args, timer.getTime() + 0.1)
end

function cfxHeloTroops.delayedCommsResetForUnit(args)
	local theUnit = args[1]
	cfxHeloTroops.removeComms(theUnit)
	cfxHeloTroops.setCommsMenu(theUnit)
end

function cfxHeloTroops.doSpawnGroup(args)
	local conf = args[1]
	local theSpawner = args[2]
	-- theSpawner can be of type cfxSpawnZone !!!OR!!! cfxCloneZones
	-- make sure cooldown on spawner has timed out, else notify that you have to wait 
	local now = timer.getTime()
	if now < (theSpawner.lastSpawnTimeStamp + theSpawner.cooldown) then 
		local delta = math.floor(theSpawner.lastSpawnTimeStamp + theSpawner.cooldown - now)
		trigger.action.outTextForGroup(conf.id, "Still redeploying (" .. delta .. " seconds left)", 30)
		return 
	end
	
	theSpawner.spawnWithSpawner(theSpawner) -- can be both spawner and cloner (Lua "polymorphism"
	trigger.action.outTextForGroup(conf.id, "Deploying <" .. theSpawner.baseName .. "> now...", 30)
	
	-- reset all comms so we can include new troops 
	-- into load menu 
	timer.scheduleFunction(cfxHeloTroops.delayedCommsResetForUnit, {conf.unit, "ignore"}, now + 1.0)
end
-- 
-- handle events 
-- 
function cfxHeloTroops:onEvent(theEvent)
	local theID = theEvent.id
	local initiator = theEvent.initiator 
	if not initiator then return end -- not interested 
	local theUnit = initiator 
	-- see if this is a player aircraft 
	if not theUnit.getPlayerName then return end -- not a player 
	if not theUnit:getPlayerName() then return end -- not a player 
	local name = theUnit:getName() -- moved to a later 
		
	-- only for troop carriers (not just helos any more)
	if not dcsCommon.isTroopCarrier(theUnit, cfxHeloTroops.troopCarriers) then 
		return 
	end
	
	if theID == 4 or theID == 55 then -- land 
		cfxHeloTroops.heloLanded(theUnit)
	end
	
	if theID == 3 or theID == 54 then -- take off 
		cfxHeloTroops.heloDeparted(theUnit)
	end
	
	if theID == 5 or theID == 30 then -- crash or unitLost
		cfxHeloTroops.heloCrashed(theUnit)
	end
	
	if theID == 20 or  -- player enter 
	   theID == 15 then -- birth
	   cfxHeloTroops.cleanHelo(theUnit)
	end
	
	if theID == 21 then -- player leave 
		cfxHeloTroops.cleanHelo(theUnit)
		local conf = cfxHeloTroops.getConfigForUnitNamed(name)
		if conf then 
			cfxHeloTroops.removeCommsFromConfig(conf)
		end
		return 
	end

	cfxHeloTroops.setCommsMenu(theUnit)	
end

--
-- Regular GC and housekeeping
--
function cfxHeloTroops.GC()
	-- GC run. remove all my dead remembered troops
	local filteredAttackers = {}
	local before = #cfxHeloTroops.deployedTroops
	for gName, gData in pairs (cfxHeloTroops.deployedTroops) do 
		-- all we need to do is get the group of that name
		-- and if it still returns units we are fine 
		local gameGroup = Group.getByName(gName)
		if gameGroup and gameGroup:isExist() and gameGroup:getSize() > 0 then 
			filteredAttackers[gName] = gData
		end
	end
	cfxHeloTroops.deployedTroops = filteredAttackers

	if cfxHeloTroops.verbose then 
		trigger.action.outText("helo troops GC ran: before <" .. before .. ">, after <" .. #cfxHeloTroops.deployedTroops .. ">", 30)
	end 
end

function cfxHeloTroops.houseKeeping()
	timer.scheduleFunction(cfxHeloTroops.houseKeeping, {}, timer.getTime() + 5 * 60) -- every 5 minutes 
	cfxHeloTroops.GC()
end

--
-- read config zone
--
function cfxHeloTroops.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("heloTroopsConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("heloTroopsConfig")
	end 

	cfxHeloTroops.verbose = theZone.verbose
	
	if theZone:hasProperty("legalTroops") then 
		local theTypesString = theZone:getStringFromZoneProperty("legalTroops", "")
		local unitTypes = dcsCommon.splitString(theTypesString, ",")
		if #unitTypes < 1 then 
			unitTypes = {"Soldier AK", "Infantry AK", "Infantry AK ver2", "Infantry AK ver3", "Infantry AK Ins", "Soldier M249", "Soldier M4 GRG", "Soldier M4", "Soldier RPG", "Paratrooper AKS-74", "Paratrooper RPG-16", "Stinger comm dsr", "Stinger comm", "Soldier stinger", "SA-18 Igla-S comm", "SA-18 Igla-S manpad", "Igla manpad INS", "SA-18 Igla comm", "SA-18 Igla manpad",} -- default 
		else
			unitTypes = dcsCommon.trimArray(unitTypes)
		end
		cfxHeloTroops.legalTroops = unitTypes
	end	
	
	cfxHeloTroops.troopWeight = theZone:getNumberFromZoneProperty("troopWeight", 100) -- kg average weight per trooper 
	
	cfxHeloTroops.autoDrop = theZone:getBoolFromZoneProperty("autoDrop", false)	
	cfxHeloTroops.autoPickup = theZone:getBoolFromZoneProperty("autoPickup", false)
	cfxHeloTroops.pickupRange = theZone:getNumberFromZoneProperty("pickupRange", 100)
	cfxHeloTroops.combatDropScore = theZone:getNumberFromZoneProperty( "combatDropScore", 200)
	
	cfxHeloTroops.actionSound = theZone:getStringFromZoneProperty("actionSound", "Quest Snare 3.wav")
	cfxHeloTroops.loadSound = theZone:getStringFromZoneProperty("loadSound", cfxHeloTroops.actionSound)
	cfxHeloTroops.disembarkSound = theZone:getStringFromZoneProperty("disembarkSound", cfxHeloTroops.actionSound)
	
	cfxHeloTroops.requestRange = theZone:getNumberFromZoneProperty("requestRange", 500)
	cfxHeloTroops.enforceDropZones = theZone:getBoolFromZoneProperty("enforceDropZones", false)
	-- add own troop carriers 
	if theZone:hasProperty("troopCarriers") then 
		local tc = theZone:getStringFromZoneProperty("troopCarriers", "UH-1D")
		tc = dcsCommon.splitString(tc, ",")
		cfxHeloTroops.troopCarriers = dcsCommon.trimArray(tc)
	end
end

--
-- Load / Save data 
--
function cfxHeloTroops.saveData()
	local theData = {}
	local allTroopData = {}
	-- run a GC pre-emptively 
	cfxHeloTroops.GC()
	-- now simply iterate and save all deployed troops 
	for gName, gData in pairs(cfxHeloTroops.deployedTroops) do 
		local sData = dcsCommon.clone(gData)
		dcsCommon.synchGroupData(sData.groupData)
		if sData.destination then
			if type(sData.destination) == "table" and (sData.destination.name) then
				net.log("cfxHeloTroops: decycling troop 'destination' for <" .. sData.destination.name .. ">")
				sData.destination = sData.destination.name
			else 
				sData.destination = nil 
				net.log("cfxHeloTroops: decycling deployed troops 'destination' nilling for safety")
			end
		end 
		allTroopData[gName] = sData
	end
	theData.troops = allTroopData
	return theData
end

function cfxHeloTroops.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("cfxHeloTroops")
	if not theData then 
		if cfxHeloTroops.verbose then 
			trigger.action.outText("+++heloT: no save date received, skipping.", 30)
		end
		return
	end
	
	-- simply spawn all troops that we have carried around and 
	-- were still alive when we saved. Troops that were picked 
	-- up by helos never made it to the save file 
	local allTroopData = theData.troops
	for gName, gdTroop in pairs (allTroopData) do 
		local gData = gdTroop.groupData 
		local orders = gdTroop.orders 
		local side = gdTroop.side 
		local range = gdTroop.range
		local cty = gData.cty 
		local cat = gData.cat  
		local dest = nil 
		local code = gdTroop.code 
		local canDrive = gdTroop.canDrive
		local formation = gdTroop.moveFormation
		local code = gdTroop.code 
		local canDrive = gdTroop.canDrive
		
		if canDrive then -- restore canDrive to all units 
			local units = gData.units 
			for idx, theUnit in pairs(units) do 
				theUnit.playerCanDrive = drivable
			end
		end 
		
		-- synch destination from name to real zone 
		if gdTroop.destination then 
			dest = cfxZones.getZoneByName(gdTroop.destination)
			net.log("cfxHeloTroops: attempting to restore troop destination zone <" .. gdTroop.destination .. ">")
		end 
		
		-- now spawn, but first 
		-- add to my own deployed queue so we can save later 
		local gdClone = dcsCommon.clone(gdTroop)
		cfxHeloTroops.deployedTroops[gName] = gdClone 
		local theGroup = coalition.addGroup(cty, cat, gData)
		-- post-proccing for cfxGroundTroops

		-- add to groundTroops 
		local newTroops = cfxGroundTroops.createGroundTroops(theGroup, range, orders, moveFormation, code, canDrive) 
		newTroops.destination = dest 
		cfxGroundTroops.addGroundTroopsToPool(newTroops)
	end
end


--
-- Start 
--
function cfxHeloTroops.start()
	-- check libs
	if not dcsCommon.libCheck("cfx Helo Troops", 
		cfxHeloTroops.requiredLibs) then
		return false 
	end
	
	-- read config zone
	cfxHeloTroops.readConfigZone()
	
	-- read drop zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("dropZone!")
	for k, aZone in pairs(attrZones) do 
		cfxHeloTroops.processDropZone(aZone)
		cfxHeloTroops.dropZones[aZone.name] = aZone 
	end
	
	-- start housekeeping 
	cfxHeloTroops.houseKeeping()
	
	world.addEventHandler(cfxHeloTroops)
	trigger.action.outText("cf/x Helo Troops v" .. cfxHeloTroops.version .. " started", 30)
	
	-- persistence:
	-- load all save data and populate map with troops that
	-- we deployed when we last saved. 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = cfxHeloTroops.saveData
		persistence.registerModule("cfxHeloTroops", callbacks)
		-- now load my data 
		cfxHeloTroops.loadData()
	end
	
	return true 
end

-- let's get rolling
if not cfxHeloTroops.start() then 
	trigger.action.outText("cf/x Helo Troops aborted: missing libraries", 30)
	cfxHeloTroops = nil 
end


-- TODO: weight when loading troops 