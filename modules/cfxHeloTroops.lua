cfxHeloTroops = {}
cfxHeloTroops.version = "2.3.0"
cfxHeloTroops.verbose = false 
cfxHeloTroops.autoDrop = true 
cfxHeloTroops.autoPickup = false 
cfxHeloTroops.pickupRange = 100 -- meters 
--
--
-- VERSION HISTORY
-- 1.1.3 -- repaired forgetting 'wait-' when loading/disembarking
-- 1.1.4 -- corrected coalition bug in deployTroopsFromHelicopter 
-- 2.0.0 -- added weight change when troops enter and leave the helicopter 
		 -- idividual troop capa max per helicopter 
-- 2.0.1 -- lib loader verification
--       -- uses dcsCommon.isTroopCarrier(theUnit)
-- 2.0.2 -- can now deploy from spawners with "requestable" attribute
-- 2.1.0 -- supports config zones
--       -- check spawner legality by types  
--       -- updated types to include 2.7.6 additions to infantry
--       -- updated types to include stinger/manpads 
-- 2.2.0 -- minor maintenance (dcsCommon)
--       -- (re?) connected readConfigZone (wtf?)
--       -- persistence support
--       -- made legalTroops entrirely optional and defer to dcsComon else
-- 2.3.0 -- interface with owned zones and playerScore when 
--       -- combat-dropping troops into non-owned owned zone.
--       -- prevent auto-load from pre-empting loading csar troops 
--
-- cfxHeloTroops -- a module to pick up and drop infantry. Can be used with any helo,
-- might be used to configure to only certain
-- currently only supports a single helicopter per group 
-- only helicopters that can transport troops will have this feature
-- Copyright (c) 2021, 2022 by Christian Franz and cf/x AG
--


cfxHeloTroops.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	             -- pretty stupid to check for this since we 
				 -- need common to invoke the check, but anyway
	"cfxZones", -- Zones, of course 
	"cfxPlayer", -- player events
	"cfxCommander", -- to make troops do stuff
	"cfxGroundTroops", -- generic when dropping troops
}

cfxHeloTroops.unitConfigs = {} -- all configs are stored by unit's name 
cfxHeloTroops.myEvents = {3, 4, 5} --  3- takeoff, 4 - land, 5 - crash 

-- legalTroops now optional, else check against dcsCommon.typeIsInfantry
--cfxHeloTroops.legalTroops = {"Soldier AK", "Infantry AK", "Infantry AK ver2", "Infantry AK ver3", "Infantry AK Ins", "Soldier M249", "Soldier M4 GRG", "Soldier M4", "Soldier RPG", "Paratrooper AKS-74", "Paratrooper RPG-16", "Stinger comm dsr", "Stinger comm", "Soldier stinger", "SA-18 Igla-S comm", "SA-18 Igla-S manpad", "Igla manpad INS", "SA-18 Igla comm", "SA-18 Igla manpad",}

cfxHeloTroops.troopWeight = 100 -- kg average weight per trooper 

-- persistence support 
cfxHeloTroops.deployedTroops = {}

function cfxHeloTroops.resetConfig(conf)
	conf.autoDrop = cfxHeloTroops.autoDrop --if true, will drop troops on-board upon touchdown
	conf.autoPickup = cfxHeloTroops.autoPickup -- if true will load nearest troops upon touchdown
	conf.pickupRange = cfxHeloTroops.pickupRange --meters, maybe make per helo?
	-- maybe set up max seats by type
	conf.currentState = -1 -- 0 = landed, 1 = airborne, -1 undetermined
	conf.troopsOnBoardNum = 0 -- if not 0, we have troops and can spawnm/drop
	conf.troopCapacity = 8 -- should be depending on airframe 
	conf.troopsOnBoard = {} -- table with the following
	

	conf.troopsOnBoard.name = "***reset***"
	conf.dropFormation = "circle_out" -- may be chosen later?
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

function cfxHeloTroops.removeConfigForUnitNamed(aName) 
	if cfxHeloTroops.unitConfigs[aName] then cfxHeloTroops.unitConfigs[aName] = nil end
end

function cfxHeloTroops.setState(theUnit, isLanded)
	-- called to set the current state of the helicopter (group)
	-- currently one helicopter per group max
end



--
-- E V E N T   H A N D L I N G 
-- 
function cfxHeloTroops.isInteresting(eventID) 
	-- return true if we are interested in this event, false else 
	for key, evType in pairs(cfxHeloTroops.myEvents) do 
		if evType == eventID then return true end
	end
	return false 
end

function cfxHeloTroops.preProcessor(event)
	-- make sure it has an initiator
	if not event.initiator then return false end -- no initiator 
	local theUnit = event.initiator
	if not dcsCommon.isPlayerUnit(theUnit) then return false end -- not a player unit 
	local cat = theUnit:getCategory()
	if cat ~= Group.Category.HELICOPTER then return false end

	return cfxHeloTroops.isInteresting(event.id) 
end

function cfxHeloTroops.postProcessor(event)
	-- don't do anything
end

function cfxHeloTroops.somethingHappened(event)
	-- when this is invoked, the preprocessor guarantees that
	-- it's an interesting event
	-- unit is valid and player 
	-- airframe category is helicopter 
	
	local theUnit = event.initiator
	local ID = event.id
	
	
	local myType = theUnit:getTypeName()
	
	if ID == 4 then 
		cfxHeloTroops.heloLanded(theUnit)
	end
	
	if ID == 3 then 
		cfxHeloTroops.heloDeparted(theUnit)
	end
	
	if ID == 5 then 
		cfxHeloTroops.heloCrashed(theUnit)
	end
	
	cfxHeloTroops.setCommsMenu(theUnit)
end

--
--
-- LANDED
--
--
function cfxHeloTroops.loadClosestGroup(conf)
	local p = conf.unit:getPosition().p
	local cat = Group.Category.GROUND
	local unitsToLoad = dcsCommon.getLivingGroupsAndDistInRangeToPoint(p, conf.pickupRange, conf.unit:getCoalition(), cat) 
	
	-- now, the groups may contain units that are not for transport.
	-- later we can filter this by weight, or other cool stuff
	-- for now we simply only troopy with legal type strings 
	unitsToLoad = cfxHeloTroops.filterTroopsByType(unitsToLoad)

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
	if not dcsCommon.isTroopCarrier(theUnit) then return end
	
	local conf = cfxHeloTroops.getUnitConfig(theUnit)
	conf.unit = theUnit
	conf.currentState = 0
	
	-- we look if we auto-unload
	if conf.autoDrop then 
		if conf.troopsOnBoardNum > 0 then 
			cfxHeloTroops.doDeployTroops({conf, "autodrop"})
			-- already called set menu, can exit directly
			return
		end
		-- when we get here, we have no troops to drop on board 
		-- so nothing to do really except look if we can pick up troops
		-- set menu will do that for us	
	end
	
	if conf.autoPickup then 
		if conf.troopsOnBoardNum < 1 then
			-- load the closest group
			if cfxHeloTroops.loadClosestGroup(conf) then 
				return
			end
		end		
	end
	
	-- when we get here, we simply set the newest menus and are done 
	-- reset menu 
	cfxHeloTroops.removeComms(conf.unit)
	cfxHeloTroops.setCommsMenu(conf.unit)
end


--
--
-- Helo took off
--
--

function cfxHeloTroops.heloDeparted(theUnit)
	if not dcsCommon.isTroopCarrier(theUnit) then return end
	
	-- when we take off, all that needs to be done is to change the state 
	-- to airborne, and then set the status flag 
	local conf = cfxHeloTroops.getUnitConfig(theUnit)
	conf.currentState = 1 -- in the air 
	
	cfxHeloTroops.removeComms(conf.unit)
	cfxHeloTroops.setCommsMenu(conf.unit)
	
end

--
-- 
-- Helo Crashed 
--
--
function cfxHeloTroops.heloCrashed(theUnit)
	if not dcsCommon.isTroopCarrier(theUnit) then return end
	
	-- clean up 
	local conf = cfxHeloTroops.getUnitConfig(theUnit)
	conf.unit = theUnit 
	conf.troopsOnBoardNum = 0 -- all dead 
	conf.currentState = -1 -- (we don't know)
	-- conf.troopsOnBoardTypes = "" -- no troops, remember?
	conf.troopsOnBoard = {}
	cfxHeloTroops.removeComms(conf.unit)
end

--
--
-- M E N U   H A N D L I N G   &   R E S P O N S E 
-- 
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
	-- we add the a menu showing current state 
	-- and the option to change fro auto drop 
	-- and auto pickup 
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
	-- depending on own load state, we set the command structure
	-- it begins at 10-other, and has 'Assault Troops' as main menu with submenus
	-- as required 
	if not theUnit then return end
	if not theUnit:isExist() then return end 
	
	-- we only add this menu to troop carriers 
	if not dcsCommon.isTroopCarrier(theUnit) then return end
	
	local group = theUnit:getGroup() 
	local id = group:getID()
	local conf = cfxHeloTroops.getUnitConfig(theUnit) --cfxHeloTroops.unitConfigs[theUnit:getName()]
	conf.id = id; -- we do this ALWAYS to it is current even after a crash 
	conf.unit = theUnit -- link back
	
	--local conf = cfxHeloTroops.getUnitConfig(theUnit)
	-- ok, first, if we don't have an F-10 menu, create one 
	if not (conf.myMainMenu) then 
		conf.myMainMenu = missionCommands.addSubMenuForGroup(id, 'Airlift Troops') 
	end
	
	-- clear out existing commands
	cfxHeloTroops.clearCommsSubmenus(conf)
	
	-- now we have a menu without submenus. 
	-- add our own submenus
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
	-- while we are airborne, there isn't much to do except add a status menu that does nothing
	-- but we can add some instructions
	-- let's begin by assuming no troops aboard
	local commandTxt = "(To load troops, land in proximity to them)"
	if conf.troopsOnBoardNum > 0 then 
		commandTxt = "(You are carrying " .. conf.troopsOnBoardNum .. " Assault Troops. Land to deploy them"
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
	-- actually, we do not redirect since there is nothing to do
end

function cfxHeloTroops.addGroundMenu(conf)
	-- this is the most complex menu. Player can deploy troops when loaded
	-- and load troops when they are in proximity
	
	-- case 1: troops aboard 
	if conf.troopsOnBoardNum > 0 then 
		local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				"Deploy Team <" .. conf.troopsOnBoard.name .. ">",
				conf.myMainMenu,
				cfxHeloTroops.redirectDeployTroops, 
				{conf, "deploy"}
				)
		table.insert(conf.myCommands, theCommand)
		return
	end
	
	-- case 2A: no troops aboard, and spawners in range 
	--          that are requestable 
	local p = conf.unit:getPosition().p
	local mySide = conf.unit:getCoalition() 
	
	if cfxSpawnZones then 
		-- only if SpawnZones is implemented 
		local availableSpawnersRaw = cfxSpawnZones.getRequestableSpawnersInRange(p, 500, mySide)
		-- DONE: requestable spawners must check for troop compatibility 
		local availableSpawners = {}
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
					end
				else 
					if not dcsCommon.typeIsInfantry(aType) then 
						allLegal = false 
					end
				end
			end
			if allLegal then 
				table.insert(availableSpawners, aSpawner)
			end
		end
		
		local numSpawners = #availableSpawners
		if numSpawners > 5 then numSpawners = 5 end 
		while numSpawners > 0 do
			-- for each spawner in range, create a 
			-- spawn menu item
			local spawner = availableSpawners[numSpawners]
			local theName = spawner.baseName 
			local comm = "Request <" .. theName .. "> troops for transport" -- .. math.floor(aTeam.dist) .. "m away"
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
	
	end
	
	-- case 2B: no troops aboard. see if there are troops around 
	-- that we can load up 
	
	local cat = Group.Category.GROUND
	local unitsToLoad = dcsCommon.getLivingGroupsAndDistInRangeToPoint(p, conf.pickupRange, conf.unit:getCoalition(), cat) 
	
	-- now, the groups may contain units that are not for transport.
	-- later we can filter this by weight, or other cool stuff
	-- for now we simply only troopy with legal type strings 
	-- TODO: add weight filtering 
	unitsToLoad = cfxHeloTroops.filterTroopsByType(unitsToLoad)

	-- now limit the options to the five closest legal groups
	local numUnits = #unitsToLoad
	if numUnits > 5 then numUnits = 5 end
	
	if numUnits < 1 then 
		local theCommand =  missionCommands.addCommandForGroup(
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
		local comm = "Load <" .. group:getName() .. "> " .. tNum .. " Members" -- .. math.floor(aTeam.dist) .. "m away"
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
		-- see if wer are inside a non-alinged zone
		-- and this includes a neutral zone 
		local coa = theUnit:getCoalition()
		local p = theUnit:getPoint()
		local theGroup = theUnit:getGroup()
		local ID = theGroup:getID()
		local nearestZone, dist = cfxOwnedZones.getNearestOwnedZoneToPoint(p)
		if nearestZone and dist < nearestZone.radius then 
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

function cfxHeloTroops.doDeployTroops(args)
	local conf = args[1]
	local what = args[2]
	-- deploy the troops I have on board in formation
	cfxHeloTroops.deployTroopsFromHelicopter(conf)
	
	-- interface with playerscore if we dropped 
	-- inside an enemy-owned zone 
	if cfxPlayerScore and cfxOwnedZones then 
		local theUnit = conf.unit
		cfxHeloTroops.scoreWhenCapturing(theUnit)
	end
	
	-- set own troops to 0 and erase type string 
	conf.troopsOnBoardNum = 0
	conf.troopsOnBoard = {}
--	conf.troopsOnBoardTypes = ""
	conf.troopsOnBoard.name = "***wasdeployed***"
	
	-- reset menu 
	cfxHeloTroops.removeComms(conf.unit)
	cfxHeloTroops.setCommsMenu(conf.unit)
end


function cfxHeloTroops.deployTroopsFromHelicopter(conf)
-- we have troops, drop them now
	local unitTypes = {} -- build type names
	local theUnit = conf.unit 
	local p = theUnit:getPoint() 
	
	--for i=1, scenario.troopSize[theUnit:getName()] do 
	--	table.insert(unitTypes, "Soldier M4")
	--end
	
	-- split the conf.troopsOnBoardTypes into an array of types
	unitTypes = dcsCommon.splitString(conf.troopsOnBoard.types, ",")
	if #unitTypes < 1 then 
		table.insert(unitTypes, "Soldier M4") -- make it one m4 trooper as fallback
	end
	
	local range = conf.troopsOnBoard.range
	local orders = conf.troopsOnBoard.orders 
	if not orders then orders = "guard" end
	
	-- order processing: if the orders were pre-pended with "wait-"
	-- we now remove that, so after dropping they do what their 
	-- orders where AFTER being picked up
	if dcsCommon.stringStartsWith(orders, "wait-") then 
		orders = dcsCommon.removePrefix(orders, "wait-")
		trigger.action.outTextForGroup(conf.id, "+++ <" .. conf.troopsOnBoard.name .. "> revoke 'wait' orders, proceed with <".. orders .. ">", 30)
	end
	
	local chopperZone = cfxZones.createSimpleZone("choppa", p, 12) -- 12 m ratius around choppa
	--local theCoalition = theUnit:getCountry() -- make it choppers country
	local theCoalition = theUnit:getGroup():getCoalition() -- make it choppers COALITION
	local theGroup, theData = cfxZones.createGroundUnitsInZoneForCoalition (
				theCoalition, 												
				conf.troopsOnBoard.name, -- dcsCommon.uuid("Assault"), -- maybe use config name as loaded from the group 
				chopperZone, 											
				unitTypes, 													
				conf.dropFormation,
				90)
	-- persistence management 
	local troopData = {}
	troopData.groupData = theData
	troopData.orders = orders -- always set  
	troopData.side = theCoalition
	troopData.range = range
	cfxHeloTroops.deployedTroops[theData.name] = troopData 
	
	local troop = cfxGroundTroops.createGroundTroops(theGroup, range, orders) -- use default range and orders
	-- instead of scheduling tasking in one second, we add to 
	-- ground troops pool, and the troop pool manager will assign some enemies
	cfxGroundTroops.addGroundTroopsToPool(troop)
	trigger.action.outTextForGroup(conf.id, "<" .. theGroup:getName() .. "> have deployed to the ground with orders " .. orders .. "!", 30)
	
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
	conf.troopsOnBoard = {}
	-- all we need to do is disassemble the group into type 
	conf.troopsOnBoard.types = dcsCommon.getGroupTypeString(group)
	-- get the size 
	conf.troopsOnBoardNum = group:getSize()
	-- and name 
	conf.troopsOnBoard.name = group:getName()
	-- and put it all into the helicopter config 
	
	-- now we need to destroy the group. First, remove it from the pool
	local pooledGroup = cfxGroundTroops.getGroundTroopsForGroup(group)
	if pooledGroup then 
		-- copy some important info from the troops 
		-- if they are set 
		conf.troopsOnBoard.orders = pooledGroup.orders
		conf.troopsOnBoard.range = pooledGroup.range
		
		cfxGroundTroops.removeTroopsFromPool(pooledGroup)
		trigger.action.outTextForGroup(conf.id, "Team '".. conf.troopsOnBoard.name .."' loaded and has orders <" .. conf.troopsOnBoard.orders .. ">", 30)
	else 
		--trigger.action.outTextForGroup(conf.id, "Team '".. conf.troopsOnBoard.name .."' loaded!", 30)
		if cfxHeloTroops.verbose then 
			trigger.action.outText("+++heloT: ".. conf.troopsOnBoard.name .." was not committed to ground troops", 30)
		end
	end
		
	-- now simply destroy the group
	-- we'll re-assemble it when we deploy it 
	-- we currently can't change the weight of the helicopter
	-- TODO: add weight changing code 
	-- TODO: ensure compatibility with CSAR module 
	group:destroy()
	
	-- now immediately run a GC so this group is removed 
	-- from any save data
	cfxHeloTroops.GC()
	
	-- say so 
	trigger.action.outTextForGroup(conf.id, "Team '".. conf.troopsOnBoard.name .."' aboard, ready to go!", 30)

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
	
	-- make sure cooldown on spawner has timed out, else 
	-- notify that you have to wait 
	local now = timer.getTime()
	if now < (theSpawner.lastSpawnTimeStamp + theSpawner.cooldown) then 
		local delta = math.floor(theSpawner.lastSpawnTimeStamp + theSpawner.cooldown - now)
		trigger.action.outTextForGroup(conf.id, "Still redeploying (" .. delta .. " seconds left)", 30)
		return 
	end
	
	cfxSpawnZones.spawnWithSpawner(theSpawner)
	trigger.action.outTextForGroup(conf.id, "Deploying <" .. theSpawner.baseName .. "> now...", 30)
	
	-- reset all comms so we can include new troops 
	-- into load menu 
	timer.scheduleFunction(cfxHeloTroops.delayedCommsResetForUnit, {conf.unit, "ignore"}, now + 1.0)
	
end


--
-- Player event callbacks
--
function cfxHeloTroops.playerChangeEvent(evType, description, player, data)
	if evType == "newGroup" then 
		theUnit = data.primeUnit
		cfxHeloTroops.setCommsMenu(theUnit)

		return 
	end
	
	if evType == "removeGroup" then 
--		trigger.action.outText("+++Helo Troops: a group disappeared", 30)
		-- data.name contains the name of the group. nil the entry in config list, so all
		-- troops that group was carrying are gone 
		-- we must remove the comms menu for this group else we try to add another one to this group later
		-- we assume a one-unit group structure, else the following may fail
		local conf = cfxHeloTroops.getConfigForUnitNamed(data.primeUnitName)
		if conf then 
			cfxHeloTroops.removeCommsFromConfig(conf)
		end
		return
	end
	
	if evType == "leave" then 
		local conf = cfxHeloTroops.getConfigForUnitNamed(player.unitName)
		if conf then 
			cfxHeloTroops.resetConfig(conf)
		end
	end
	
	if evType == "unit" then 
		-- player changed units. almost never in MP, but possible in solo
		-- we need to reset the conf so no troops are carried any longer
		local conf = cfxHeloTroops.getConfigForUnitNamed(data.oldUnitName) 
		if conf then 
			cfxHeloTroops.resetConfig(conf)
		end
	end
	
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
		trigger.action.outText("+++heloT: no config zone!", 30) 
		theZone = cfxZones.createSimpleZone("heloTroopsConfig")
	end 

	cfxHeloTroops.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if cfxZones.hasProperty(theZone, "legalTroops") then 
		local theTypesString = cfxZones.getStringFromZoneProperty(theZone, "legalTroops", "")
		local unitTypes = dcsCommon.splitString(aSpawner.types, ",")
		if #unitTypes < 1 then 
			unitTypes = {"Soldier AK", "Infantry AK", "Infantry AK ver2", "Infantry AK ver3", "Infantry AK Ins", "Soldier M249", "Soldier M4 GRG", "Soldier M4", "Soldier RPG", "Paratrooper AKS-74", "Paratrooper RPG-16", "Stinger comm dsr", "Stinger comm", "Soldier stinger", "SA-18 Igla-S comm", "SA-18 Igla-S manpad", "Igla manpad INS", "SA-18 Igla comm", "SA-18 Igla manpad",} -- default 
		else
			unitTypes = dcsCommon.trimArray(unitTypes)
		end
		cfxHeloTroops.legalTroops = unitTypes
	end	
	
	cfxHeloTroops.troopWeight = cfxZones.getNumberFromZoneProperty(theZone, "troopWeight", 100) -- kg average weight per trooper 
	
	cfxHeloTroops.autoDrop = cfxZones.getBoolFromZoneProperty(theZone, "autoDrop", false)	
	cfxHeloTroops.autoPickup = cfxZones.getBoolFromZoneProperty(theZone, "autoPickup", false)
	cfxHeloTroops.pickupRange = cfxZones.getNumberFromZoneProperty(theZone, "pickupRange", 100)
	cfxHeloTroops.combatDropScore = cfxZones.getNumberFromZoneProperty(theZone, "combatDropScore", 200)
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
		
		-- now spawn, but first 
		-- add to my own deployed queue so we can save later 
		local gdClone = dcsCommon.clone(gdTroop)
		cfxHeloTroops.deployedTroops[gName] = gdClone 
		local theGroup = coalition.addGroup(cty, cat, gData)
		-- post-proccing for cfxGroundTroops

		-- add to groundTroops 
		local newTroops = cfxGroundTroops.createGroundTroops(theGroup, range, orders) 
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
	
	-- start housekeeping 
	cfxHeloTroops.houseKeeping()
	
	-- install callbacks for helo-relevant events
	dcsCommon.addEventHandler(cfxHeloTroops.somethingHappened, cfxHeloTroops.preProcessor, cfxHeloTroops.postProcessor)

	-- now iterate through all player groups and install the Assault Troop Menu
	allPlayerGroups = cfxPlayerGroups -- cfxPlayerGroups is a global, don't fuck with it! 
			-- contains per group a player record, use prime unit to access player's unit 
	for gname, pgroup in pairs(allPlayerGroups) do 
		local aUnit = pgroup.primeUnit -- get any unit of that group
		cfxHeloTroops.setCommsMenu(aUnit)
	end
	-- now install the new group notifier to install Assault Troops menu
	
	cfxPlayer.addMonitor(cfxHeloTroops.playerChangeEvent)
	trigger.action.outText("cf/x Helo Troops v" .. cfxHeloTroops.version .. " started", 30)
	
	-- now load all save data and populate map with troops that
	-- we deployed last save. 
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

--[[--
	- interface with spawnable: request troops via comms menu if 
		- spawnZones defined 
		- spawners in range and 
	    - spawner auf 'paused' und 'requestable'
	  
--]]--
-- TODO: weight when loading troops 