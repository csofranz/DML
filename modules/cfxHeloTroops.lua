cfxHeloTroops = {}
cfxHeloTroops.version = "2.4.1"
cfxHeloTroops.verbose = false 
cfxHeloTroops.autoDrop = true 
cfxHeloTroops.autoPickup = false 
cfxHeloTroops.pickupRange = 100 -- meters 
--
--[[--
 VERSION HISTORY
 1.1.3 - repaired forgetting 'wait-' when loading/disembarking
 1.1.4 - corrected coalition bug in deployTroopsFromHelicopter 
 2.0.0 - added weight change when troops enter and leave the helicopter 
       - idividual troop capa max per helicopter 
 2.0.1 - lib loader verification
       - uses dcsCommon.isTroopCarrier(theUnit)
 2.0.2 - can now deploy from spawners with "requestable" attribute
 2.1.0 - supports config zones
       - check spawner legality by types  
       - updated types to include 2.7.6 additions to infantry
       - updated types to include stinger/manpads 
 2.2.0 - minor maintenance (dcsCommon)
       - (re?) connected readConfigZone (wtf?)
       - persistence support
       - made legalTroops entrirely optional and defer to dcsComon else
 2.3.0 - interface with owned zones and playerScore when 
       - combat-dropping troops into non-owned owned zone.
       - prevent auto-load from pre-empting loading csar troops 
 2.3.1 - added ability to self-define troopCarriers via config
 2.4.0 - added missing support for attackZone orders (destination)
	   - eliminated cfxPlayer module import and all dependencies
	   - added support for groupTracker / limbo 
	   - removed restriction to only apply to helicopters in anticipation of the C-130 Hercules appearing in the game
 2.4.1 - new actionSound attribute, sound plays to group whenever 
         troops have boarded or disembarked

--]]--
--
-- cfxHeloTroops -- a module to pick up and drop infantry. 
-- Can be used with ANY aircraft, configured by default to be 
-- restricted to troop-carrying helicopters.
-- might be configure to apply to any type you want using the 
-- configuration zone.


cfxHeloTroops.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	             -- pretty stupid to check for this since we 
				 -- need common to invoke the check, but anyway
	"cfxZones", -- Zones, of course 
	"cfxCommander", -- to make troops do stuff
	"cfxGroundTroops", -- generic when dropping troops
}

cfxHeloTroops.unitConfigs = {} -- all configs are stored by unit's name 
cfxHeloTroops.troopWeight = 100 -- kg average weight per trooper 

-- persistence support 
cfxHeloTroops.deployedTroops = {}

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
--
-- LANDED
--
--
function cfxHeloTroops.loadClosestGroup(conf)
	local p = conf.unit:getPosition().p
	local cat = Group.Category.GROUND
	local unitsToLoad = dcsCommon.getLivingGroupsAndDistInRangeToPoint(p, conf.pickupRange, conf.unit:getCoalition(), cat) 
	
	-- groups may contain units that are not for transport.
	-- for now we only load troops with legal type strings 
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
	if not dcsCommon.isTroopCarrier(theUnit, cfxHeloTroops.troopCarriers) then return end
	
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
	if not dcsCommon.isTroopCarrier(theUnit, cfxHeloTroops.troopCarriers) then return end
	
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
	if not dcsCommon.isTroopCarrier(theUnit, cfxHeloTroops.troopCarriers) then
		if cfxHeloTroops.verbose then 
			trigger.action.outText("+++heloT - player unit <" .. theUnit:getName() .. "> type <" .. theUnit:getTypeName() .. "> is not legal troop carrier.", 30)
		end
		return 
	end
	
	local group = theUnit:getGroup() 
	local id = group:getID()
	local conf = cfxHeloTroops.getUnitConfig(theUnit)
	conf.id = id; -- we do this ALWAYS to it is current even after a crash 
	conf.unit = theUnit -- link back
	
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
		
	-- split the conf.troopsOnBoardTypes into an array of types
	unitTypes = dcsCommon.splitString(conf.troopsOnBoard.types, ",")
	if #unitTypes < 1 then 
		table.insert(unitTypes, "Soldier M4") -- make it one m4 trooper as fallback
	end
	
	local range = conf.troopsOnBoard.range
	local orders = conf.troopsOnBoard.orders 
	local dest = conf.troopsOnBoard.destination
	local theName = conf.troopsOnBoard.name 
	
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
				theName, -- group name, may be tracked 
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
	troopData.destination = dest -- only for attackzone orders 
	cfxHeloTroops.deployedTroops[theData.name] = troopData 
	
	local troop = cfxGroundTroops.createGroundTroops(theGroup, range, orders) 
	troop.destination = dest -- transfer target zone for attackzone oders
	cfxGroundTroops.addGroundTroopsToPool(troop) -- will schedule move orders
	trigger.action.outTextForGroup(conf.id, "<" .. theGroup:getName() .. "> have deployed to the ground with orders " .. orders .. "!", 30)
	trigger.action.outSoundForGroup(conf.id, cfxHeloTroops.actionSound) --  "Quest Snare 3.wav")
	-- see if this is tracked by a tracker, and pass them back so 
	-- they can un-limbo 
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
	local gName = group:getName()
	conf.troopsOnBoard.name = gName
	-- and put it all into the helicopter config 
	
	-- now we need to destroy the group. Let's prepare:
	-- if it was tracked, tell tracker to move it to limbo 
	-- to remember it even if it's destroyed 
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
		-- copy some important info from the troops 
		-- if they are set 
		conf.troopsOnBoard.orders = pooledGroup.orders
		conf.troopsOnBoard.range = pooledGroup.range
		conf.troopsOnBoard.destination = pooledGroup.destination -- may be nil 
		cfxGroundTroops.removeTroopsFromPool(pooledGroup)
		trigger.action.outTextForGroup(conf.id, "Team '".. conf.troopsOnBoard.name .."' loaded and has orders <" .. conf.troopsOnBoard.orders .. ">", 30)
		--trigger.action.outSoundForGroup(conf.id, cfxHeloTroops.actionSound) --  "Quest Snare 3.wav")
	else 
		if cfxHeloTroops.verbose then 
			trigger.action.outText("+++heloT: ".. conf.troopsOnBoard.name .." was not committed to ground troops", 30)
		end
	end
		
	-- now simply destroy the group
	-- we'll re-assemble it when we deploy it 
	-- TODO: add weight changing code 
	-- TODO: ensure compatibility with CSAR module
	group:destroy()
	
	-- now immediately run a GC so this group is removed 
	-- from any save data
	cfxHeloTroops.GC()
	
	-- say so 
	trigger.action.outTextForGroup(conf.id, "Team '".. conf.troopsOnBoard.name .."' aboard, ready to go!", 30)
	trigger.action.outSoundForGroup(conf.id, cfxHeloTroops.actionSound) --  "Quest Snare 3.wav")

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
-- handle events 
-- 
function cfxHeloTroops:onEvent(theEvent)
	local theID = theEvent.id
	local initiator = theEvent.initiator 
	if not initiator then return end -- not interested 
	local theUnit = initiator 
	local name = theUnit:getName() 
	-- see if this is a player aircraft 
	if not theUnit.getPlayerName then return end -- not a player 
	if not theUnit:getPlayerName() then return end -- not a player 
	
	-- only for helicopters -- overridedden by troop carriers
	-- we don't check for cat any more, so any airframe 
	-- can be used as long as it's ok with isTroopCarrier()
	
	-- only for troop carriers
	if not dcsCommon.isTroopCarrier(theUnit, cfxHeloTroops.troopCarriers) then 
		return 
	end
	
	if theID == 4 then -- land 
		cfxHeloTroops.heloLanded(theUnit)
	end
	
	if theID == 3 then -- take off 
		cfxHeloTroops.heloDeparted(theUnit)
	end
	
	if theID == 5 then -- crash
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
	
	cfxHeloTroops.actionSound = cfxZones.getStringFromZoneProperty(theZone, "actionSound", "Quest Snare 3.wav")
	
	-- add own troop carriers 
	if cfxZones.hasProperty(theZone, "troopCarriers") then 
		local tc = cfxZones.getStringFromZoneProperty(theZone, "troopCarriers", "UH-1D")
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