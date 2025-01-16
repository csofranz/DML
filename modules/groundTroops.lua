cfxGroundTroops = {}
cfxGroundTroops.version = "3.0.0"
cfxGroundTroops.ups = 0.25 -- every 4 seconds 
cfxGroundTroops.verbose = false 
cfxGroundTroops.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	             -- pretty stupid to check for this since we 
				 -- need common to invoke the check, but anyway
	"cfxCommander", -- generic data module for weight 
	-- cfxOwnedZones is optional 
}
-- ground troops: a module to manage ground toops. makes groups of ground troops
-- patrol and engage enemies and signal idle
-- understands cfxOwnedZones orders 'attackOwnedZone' and will re-direct
-- troops when a zone was captured by interacting with cfxOwnedZones to 
-- find the nearest non-owned zone and direct the group there 

-- USAGE
-- Allocate a group in game and issue them marching orders towars a goal 
-- then createGroundTroops to allocate a structure used by this 
-- module and addTroopsToPool to have them then managed by this 
-- module 

cfxGroundTroops.deployedTroops = {} -- indexed by group name 
cfxGroundTroops.jtacCB = {} -- jtac callbacks, to be implemented 

--[[--
 version history
   3.0.0 - support for troop-individual laser codes 
         - support for isDrivable CA troop spawns 

  an entry into the deployed troop table has the following attributes
  - group - the group 
  - orders: "guard" - will guard the spot and look for enemies in range
            "patrol" - will walk between way points back and forth 
            "laze" - will stay in place and try to laze visible vehicles in range
			"attackOwnedZone" - interface to cfxOwnedZones module, seeks out
			  enemy zones to attack and capture them
			"captureandhold" - interface to ownedZones, seeks out nearest enemy 
			  or neutral owned zone. once captured, it stays there 
            "wait-<some other orders>" do nothing. the "wait" prefix will be removed some time and <some other order> then revealed. Used at least by heloTroops
            "train" - target dummies. ROE=HOLD, no ground loop 
            "attack" - transition to destination, once there, stop and 
            switch to guard. requires destination zone be set to a valid cfxZone
  - coalition - the coalition from the group
  - enemy - if set, the group this group it is engaging. this means the group is fighting and not idle
  - name - name of group, dan be freely changed
  - signature - "cfx" to tell apart from dcs groups 
  - range = range to look for enemies. default is 300m. In "laze" orders, range to laze
  - lazeTarget - target currently lazing
  - ??lazeCode?? - laser code. default is 1688
  - moving - has been given orders to move somewhere already. used for first movement order with attack orders 
  - code - laser code 
  - canDrive - for spawning if CA supported
  -- reduced ups to 0.24, updating troops every 4 seconds is fast enough 

 
 usage:
 take a dcs group of ground troops and create a cfx ground troop record with 
  createGroundTroops()
 then add this to the manager with 
  addGroundTroopsToPool()
 
 you can control what the group is to do by changing the cfx troop attribute orders 
 you can install a callback that will notify you if a troop reached a goal or
 was killed with addTroopsCallback() which will also give a reason
 callback pattern is myCallback(reason, theGroup, orders, data) with troop being the 
 group, and orders the original orders, and reason a string containing why the 
 callback was invoked. Currently defined reasons are
   - "dead" - entire group was killed 
   - "arrived" - at least a part of group arrived at destination (only with some orders)
--]]--

--
-- UPDATE MODELS
-- standard is update all every time: fastest, but may cause 
-- performance issues
-- queued will work one every pass (except for lazed), distributing the load much better 
-- schedueld installs a callback for each group separately and thus distributes the load over time much better 

function cfxGroundTroops.invokeCallbacks(ID, jtac, tgt, data)
	-- IS is aqui, lost, dead, jtac died. jtac is group, tgt is unit, data is rest 
	for idx, cb in pairs(cfxGroundTroops.jtacCB) do 
		cb(ID, jtac, tgt, data)
	end
end

function cfxGroundTroops.addJtacCB(theCB)
	table.insert(cfxGroundTroops.jtacCB, theCB)
end

cfxGroundTroops.troopQueue = {} -- FIFO stack 
-- return the best tracking interval for this type of orders 

function cfxGroundTroops.readConfigZone()
	local theZone = cfxZones.getZoneByName("groundTroopsConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("groundTroopsConfig") 
	end 
		
	cfxGroundTroops.queuedUpdates = theZone:getBoolFromZoneProperty("queuedUpdates", false)
	cfxGroundTroops.scheduledUpdates = theZone:getBoolFromZoneProperty("scheduledUpdates", false)
	cfxGroundTroops.maxManagedTroops = theZone:getNumberFromZoneProperty("maxManagedTroops", 67)
	cfxGroundTroops.monitorNumbers = theZone:getBoolFromZoneProperty("monitorNumbers", false)
	cfxGroundTroops.standardScheduleInterval = theZone:getNumberFromZoneProperty("standardScheduleInterval", 30)	
	cfxGroundTroops.guardUpdateInterval = theZone:getNumberFromZoneProperty("guardUpdateInterval", 30)
	cfxGroundTroops.trackingUpdateInterval = theZone:getNumberFromZoneProperty("trackingUpdateInterval", 0.5)

	cfxGroundTroops.jtacSound = theZone:getStringFromZoneProperty("jtacSound", "UI_SCI-FI_Tone_Bright_Dry_20_stereo.wav")
	cfxGroundTroops.jtacVerbose = theZone:getBoolFromZoneProperty("jtacVerbose", true)
	cfxGroundTroops.laseCode = theZone:getNumberFromZoneProperty("jtacLaserCode", 1688)
	if theZone:hasProperty("lazeCode") then 
		cfxGroundTroops.laseCode = theZone:getNumberFromZoneProperty("lazeCode", 1688)
	end 
	if theZone:hasProperty("laseCode") then 
		cfxGroundTroops.laseCode = theZone:getNumberFromZoneProperty("laseCode", 1688)
	end 
	if theZone:hasProperty("laserCode") then 
		cfxGroundTroops.laseCode = theZone:getNumberFromZoneProperty("laserCode", 1688)
	end 
	cfxGroundTroops.verbose = theZone.verbose 

	if cfxGroundTroops.verbose then 
		trigger.action.outText("+++gndT: read config zone!", 30) 
	end
end


-- 
-- Callback handling
--

cfxGroundTroops.troopsCallback = {}

function cfxGroundTroops.addTroopsCallback(theCallback)
	table.insert(cfxGroundTroops.troopsCallback, theCallback)
end

function cfxGroundTroops.invokeCallbacksFor(reason, troops, data)
	if not data then data = {} end
	data.troops = troops 
	for idx, theCB in pairs (cfxGroundTroops.troopsCallback) do 
		theCB(reason, troops.group, troops.orders, data)
	end
end

function cfxGroundTroops.getScheduleInterval(orders)
	if orders == "laze" then 
		return cfxGroundTroops.trackingUpdateInterval
	end
	return cfxGroundTroops.standardScheduleInterval
end

-- create controller commands to attack a group "enemies"
-- enemies are an attribute of the troop structure
-- usually called from a group on guard when idling 
function cfxGroundTroops.makeTroopsEngageEnemies(troop)
	local group = troop.group
	if not Group.isExist(group) then 
		trigger.action.outText("+++gndT: troup don't exist, dropping", 30)
		return 
	end
	
	local enemies = troop.enemy
	local from = dcsCommon.getGroupLocation(group)
	if not from then return end -- the commandos died
	local there = dcsCommon.getGroupLocation(enemies)
	if not there then return end
	
	-- we lerp to 2/3 of enemy location
	there = dcsCommon.vLerp(from, there, 0.66) 
	local moveFormation = troop.moveFormation
	local speed = 10 -- m/s = 10 km/h -- wait. 10 m/s is 36 km/h 
	cfxCommander.makeGroupGoThere(group, there, speed, moveFormation)
	local attask = cfxCommander.createAttackGroupCommand(enemies)
	cfxCommander.scheduleTaskForGroup(group, attask, 0.5)
	troop.moving = true 
end

-- make the troops engage a cfxZone passed in the destination 
-- attribute 
function cfxGroundTroops.makeTroopsEngageZone(troop)
	local group = troop.group
	if not group:isExist() then 
		trigger.action.outText("+++gndT: make troops engage zone: troops do not exist, exiting", 30)
		return 
	end
	
	local enemyZone = troop.destination -- must be cfxZone 
	local from = dcsCommon.getGroupLocation(group)
	if not from then return end -- the group died
	local there = enemyZone:getPoint() -- access zone position
	if not there then return end
		
	local speed = 14 -- m/s; 10 m/s = 36 km/h
	
	-- make troops stop in 1 second, then start in 5 seconds to give AI respite 
	cfxCommander.makeGroupHalt(group, 1) -- 1 second delay
	if troop.orders == "captureandhold" then 
		-- direct capture never uses roads 
		cfxCommander.makeGroupGoThere(group, there, speed, troop.moveFormation, 5)
	else 
		-- when we attack any owned zone, we prefer roads 
		cfxCommander.makeGroupGoTherePreferringRoads(group, there, speed, 5, troop.moveFormation)
	end
	-- remember that we have issued a move order 
	troop.moving = true 	
end

function cfxGroundTroops.switchToOffroad(troops)
	-- we may need to test if we already did this, 
	-- but not for now 
	
	-- this is called when troops are stuck 
	-- on their route for longer than allowed
	-- we now force a direct approach 
	local group = troops.group
	if not group:isExist() then 
		return
	end 
	
	local enemies = troops.destination
	local from = dcsCommon.getGroupLocation(group)
	if not from then return end -- the commandos died
	local there = enemies.point
	if not there then return end
		
	local speed = 14 -- m/s; 10 m/s = 36 km/h
	
	cfxCommander.makeGroupHalt(group, 0) -- no delay, halt now
	cfxCommander.makeGroupGoThere(group, there, speed, "Off Road", 5)
	
	troops.lastOrderDate = timer.getTime()
	troops.speedWarning = 0
end

--
-- update loop for troops that have 'attackOwnedZones' as 
-- their orders
-- if they have no destination zone, or the zone they are 
-- are heading for is already owned by their side, then look for 
-- the closest enemy zone, and cut attack orders to move there 
function cfxGroundTroops.getClosestEnemyZone(troop)
	if not cfxOwnedZones then 
		trigger.action.outText("+++groundT: WARNING! ownedZones is not loaded, which is required.", 30)
		return nil 
	end 
	local p = dcsCommon.getGroupLocation(troop.group)
	local tempZone = cfxZones.createSimpleZone("tz", p, 100)
	tempZone.owner = troop.side
	local newTarget = cfxOwnedZones.getNearestEnemyOwnedZone(tempZone, true) -- 'true' will also target neutral zones 
	return newTarget
end

function cfxGroundTroops.updateZoneAttackers(troop)
	if not troop then return end 
	if not cfxOwnedZones then 
		trigger.action.outText("+++gndT: update zone attackers requires ownedZones", 30)
		return 
	end
	troop.insideDestination = false -- mark as not inside 

	-- we *have* a destination, but not yet isued move orders,
	-- meaning that we just spawned, probably  from helo.
	-- do not look for new location, issue move orders instead 
	if not troop.hasMovedOrders and troop.destination then 
		troop.hasMovedOrders = true 
		cfxGroundTroops.makeTroopsEngageZone(troop)
		troop.lastOrderDate = timer.getTime()
		troop.speedWarning = 0
		return
	end 
	
	local newTargetZone = cfxGroundTroops.getClosestEnemyZone(troop)
	if not newTargetZone then
		-- all target zones are friendly, go to guard mode
		troop.orders = "guard"
		return 
	end
	
	if newTargetZone ~= troop.destination then 
		if troop.destination and troop.orders == "captureandhold" then 
			troop.lastOrderDate = timer.getTime() -- we may even dismiss them 
			-- from troop array. But orders should remain when picked up by helo 
			-- we never change target. Stay.
			return 
		end 
		troop.destination = newTargetZone 
		cfxGroundTroops.makeTroopsEngageZone(troop)
		troop.lastOrderDate = timer.getTime()
		troop.speedWarning = 0
		return
	end
	
	-- if we get here, we should be under way to our nearest enemy zone
	if not troop.moving then 
		cfxGroundTroops.makeTroopsEngageZone(troop)
		return 
	end 
	
	-- if we get here, we are under way to troop.destination
	-- check if we are inside the zone, and if so, set variable to true 
	local p = dcsCommon.getGroupLocation(troop.group)
	troop.insideDestination = cfxZones.isPointInsideZone(p, troop.destination)
	
    -- if we get here, we need no change 
	
end

-- attackers simply travel to their destination (zone), and then switch to 
-- guard orders once they arrive 
function cfxGroundTroops.updateAttackers(troop) 
	if not troop then return end 
	if not troop.destination then return end 
	if not troop.group:isExist() then return end 
	
	-- if we are not moving, we need to issue move oders now
	-- this can happen if previously, there was a 'wait' command 
	-- and this now was removed so we end up in the method 
	if not troop.moving then 
		cfxGroundTroops.makeTroopsEngageZone(troop)
		return 
	end 
	
	
	if cfxZones.isGroupPartiallyInZone(troop.group, troop.destination) then
		-- we have arrived
		-- we could now also initiate a general callback with reason
		cfxGroundTroops.invokeCallbacksFor("arrived", troop)
		troop.orders = "guard"
		return 
	end
		
--	if we get here, we need no change 
end

-- update loop for a group that has "guard" orders.
-- basically it stands around and looks for enemies 
-- until it finds a group, and then engages the enemy
-- when engaged, it is not looking for other enemies
-- 'engaged' means that the troop.enemy attribute is set
 
function cfxGroundTroops.updateGuards(troop)
	if not troop.group:isExist() then 
		return 
	end 
	
	local theEnemy = troop.enemy
	if theEnemy then 
		-- see if enemy is dead 
		if not dcsCommon.isGroupAlive(theEnemy) then 
			troop.enemy = nil
			-- yup, zed's dead. next time around, we won't be checking this again
			trigger.action.outText(troop.name .. " has neutralized enemy forces", 30)
			--DONE: invoke callback for defeating troops
			local data = {}
			data.enemy = theEnemy
			cfxGroundTroops.invokeCallbacksFor("neutralized", troop, data)
			return
		end
		-- yes, we are still engaged
		return 
	end
	
	-- we are currently unengaged. look for an enemy
	if not troop.range then troop.range = 300 end
	troop.coalition = troop.group:getCoalition()
	local enemyCoal = dcsCommon.getEnemyCoalitionFor(troop.coalition)
	local cat = Group.Category.GROUND
	local p = dcsCommon.getGroupLocation(troop.group)
	local enemies, enemyDist = dcsCommon.getClosestLivingGroupToPoint(p, enemyCoal, cat) 
	local maxRange = troop.range -- meters 
	-- if we have enemies then schedule a path to go there
	if enemies and (enemyDist < maxRange) then 
		troop.enemy = enemies
		--timer.scheduleFunction(cfxGroundTroops.makeGroupEngageEnemies, troop, timer.getTime() + 1.0)
		cfxGroundTroops.makeTroopsEngageEnemies(troop)
		trigger.action.outText(troop.name .. " is engaging enemy forces at range " .. math.floor(enemyDist) .. "meters", 30)
		--DONE: invoke callback for engaging troops, pass data 
		local data = {}
		data.enemy = enemies
		cfxGroundTroops.invokeCallbacksFor("engaging", troop, data)
	elseif enemies then 
		--trigger.action.outText(troop.name .. " enemiy out of range: " .. math.floor(enemyDist) .. "meters", 30)
	else 
		--trigger.action.outText(troop.name .. " no enemies", 30)
	end
end

--
-- update loop for units that laze targets.
-- they can only laze if they are alive, but update 
-- will take care of that, so when we are here, there 
-- is at least one of them alive
-- 

function cfxGroundTroops.findLazeTarget(troop)
	local here = troop.group:getUnit(1):getPoint()
	troop.coalition = troop.group:getCoalition()
	local enemyCoal = dcsCommon.getEnemyCoalitionFor(troop.coalition)
	--local enemySide = dcsCommon.getEnemyCoalitionFor(troop.side)
	local cat = Group.Category.GROUND
	local enemyGroups = dcsCommon.getLivingGroupsAndDistInRangeToPoint(here, troop.range, enemyCoal, cat) 
	-- we now have a list of possible targets in range
	if #enemyGroups < 1 then 	
		-- no targets in range
		return nil 
	end

    here = {x = here.x, y = here.y + 2.0, z = here.z} -- raise by 2.0m
	
	-- iterate through the list until we find the first target 
	-- that fits the bill and return it

	for i=1, #enemyGroups do	
		-- get all units for this group 
		local aGroup = enemyGroups[i].group -- remember, they are in a {dist, group} tuple
		local theUnits = aGroup:getUnits()
		-- iterate all units 
		for udx, aUnit in pairs(theUnits) do 
			if (aUnit:isExist() and aUnit:getLife() > 1) then 
				-- unit lives 
				-- now, we need to filter infantry. we do this by 
				-- pre-fetching the typeString
				-- and checking if the name contains some infantry-
				-- typical strings. Idea taken from JTAC script 
				local isInfantry =  dcsCommon.unitIsInfantry(theUnit)
				if not isInfantry then 
					-- this is a vehicle, is it in line of sight?
					-- raise the point 2m above ground for both points
					-- as done in jtac script
					local there = aUnit:getPoint()  
					there = {x = there.x, y = there.y + 2.0, z = there.z}
                   
					if land.isVisible(here, there) then 
						-- we found a visible vehicle in 
						-- the nearest group to us in range 
						-- that is visible!
						return aUnit
					end -- if visible
				end -- if infantry 
			end -- if alive 
		end -- for all units
	end -- for all enemy groups
	return nil -- no unit found 
end

function cfxGroundTroops.lazerOff(troop)
	if troop.lazerPointer then 
		troop.lazerPointer:destroy()
	end
	troop.lazerPointer = nil 
	troop.lazingUnit = nil 
end

function cfxGroundTroops.trackLazer(troop)
	-- the only thing that must be set when entering here is
	-- lazeTarget. We set up the rest
	if not troop.lazingUnit then 
		troop.lazingUnit = troop.group:getUnit(1) -- get first unit
		if troop.lazingUnit:getLife() < 1 then 
			trigger.action.outText("+++ LazingUnit is dead, getUnit works differently from what docs say, need to filter for lively units", 30)
		end
	end
	
	if not troop.lazerPointer then
		local code = troop.code
		if not code then code = cfxGroundTroops.laseCode end -- default
		local there = troop.lazeTarget:getPoint()
		troop.lazerPointer = Spot.createLaser(troop.lazingUnit,{x = 0, y = 2, z = 0}, there, code)
		troop.lazeTargetType = troop.lazeTarget:getTypeName()
		if cfxGroundTroops.jtacVerbose then 
			trigger.action.outTextForCoalition(troop.side, troop.name .. " tally target - lasing " .. troop.lazeTargetType .. ", code " .. code .. "!", 30)
			trigger.action.outSoundForCoalition(troop.side, cfxGroundTroops.jtacSound) -- "UI_SCI-FI_Tone_Bright_Dry_20_stereo.wav")
		end 
		troop.lastLazerSpot = there -- remember last spot
		local data = {}
		data.enemy = troop.lazeTarget
		data.tracker = troop.lazingUnit
		cfxGroundTroops.invokeCallbacksFor("lase:tracking", troop, data)
		return
	end
		
	-- if we get here, we update the lazerPointer
	local there = troop.lazeTarget:getPoint()
	-- we may only want to update the laser spot when dist > trigger
	troop.lazerPointer:setPoint(there)
	-- we may want to report dist
	troop.lastLazerSpot = there
end

function cfxGroundTroops.updateLaze(troop)
	-- check if we have a laze target. 
	-- check if lazing unit was killed, and therefore lost target
	if troop.lazingUnit then 
		-- check that unit still alive
		if troop.lazingUnit:isExist() and 
		troop.lazingUnit:getLife() >= 1 then
		else 
			cfxGroundTroops.lazerOff(troop)
			troop.lazeTarget = nil
			if cfxGroundTroops.jtacVerbose then 
				trigger.action.outTextForCoalition(troop.side, troop.name .. " reports lasing " .. troop.lazeTargetType .. " interrupted. Re-acquiring.", 30)
				trigger.action.outSoundForCoalition(troop.side, cfxGroundTroops.jtacSound) -- "UI_SCI-FI_Tone_Bright_Dry_20_stereo.wav")
			end 
			troop.lazingUnit = nil 
			cfxGroundTroops.invokeCallbacksFor("lase:stop", troop)
			return -- we'll re-acquire through a new unit next round
		end
	end
	
	-- if we get here, a lazing unit 	
	if troop.lazeTarget then 
		-- check if that target is alive and in range
		if troop.lazeTarget:isExist() and troop.lazeTarget:getLife() >= 1 then
			-- note: when we laze a target, we know that we have a lazing unit
			local here = troop.lazingUnit:getPoint()
			-- check if it has moved out of range 
			local there = troop.lazeTarget:getPoint()
			if dcsCommon.dist(here, there) > troop.range then 
				-- troop out of range
				if cfxGroundTroops.jtacVerbose then 
					trigger.action.outTextForCoalition(troop.side, troop.name .. " lost sight of lazed target " .. troop.lazeTargetType, 30)
					trigger.action.outSoundForCoalition(troop.side, cfxGroundTroops.jtacSound) -- "UI_SCI-FI_Tone_Bright_Dry_20_stereo.wav")
				end 
				troop.lazeTarget = nil
				cfxGroundTroops.lazerOff(troop)
				troop.lazingUnit = nil
				cfxGroundTroops.invokeCallbacksFor("lase:stop", troop)
				return 
			end
			
			-- if we get here, we need to update the target point 
			cfxGroundTroops.trackLazer(troop)
			return
		else
			-- target died
			if cfxGroundTroops.jtacVerbose then 
				trigger.action.outTextForCoalition(troop.side, troop.name .. " confirms kill for " .. troop.lazeTargetType, 30)
				trigger.action.outSoundForCoalition(troop.side, cfxGroundTroops.jtacSound) -- "UI_SCI-FI_Tone_Bright_Dry_20_stereo.wav")
			end 
			troop.lazeTarget = nil
			cfxGroundTroops.lazerOff(troop)
			troop.lazingUnit = nil
			cfxGroundTroops.invokeCallbacksFor("lase:stop", troop)
			return
		end		
	end
	
	-- if we get here, we must look for a laze target 
	troop.lazeTarget = cfxGroundTroops.findLazeTarget(troop)
	if troop.lazeTarget then 
		cfxGroundTroops.trackLazer(troop) -- will also set up lazing unit 
	end
end


function cfxGroundTroops.updateWait(troop)
	-- currently nothing to do	
end

function cfxGroundTroops.updateTroops(troop)
	if cfxGroundTroops.verbose then 
		trigger.action.outText("+++GTroop: enter updateTroopps for <" .. troop.name .. ">", 30)
	end 
	
	-- if orders start with "wait-" then the troops 
	-- simply do nothing
	if dcsCommon.stringStartsWith(troop.orders, "wait-") then
		-- the troops are waiting to be picked update
		-- when they are dropped again, thre prefix to 
		-- their order is removed, and the 'real' orders 
		-- are revealed. For now, do nothing
		cfxGroundTroops.updateWait(troop)
	--REMEMBER: LOWER CASE ONLY!
	elseif troop.orders == "guard" then 
		cfxGroundTroops.updateGuards(troop)
	
	elseif troop.orders == "attackownedzone" then 
		cfxGroundTroops.updateZoneAttackers(troop)

	elseif troop.orders == "captureandhold" then 
		cfxGroundTroops.updateZoneAttackers(troop) 
		
	elseif troop.orders == "laze" then 
		cfxGroundTroops.updateLaze(troop)
	
	elseif troop.orders == "attackzone" then 
		cfxGroundTroops.updateAttackers(troop)
		
	else 
		trigger.action.outText("+++ updated troops " .. troop.name .. " have unknown orders " .. troop.orders, 30)
	end
	
end

--
-- all at once 
--
function cfxGroundTroops.update()
	cfxGroundTroops.updateSchedule = timer.scheduleFunction(cfxGroundTroops.update, {}, timer.getTime() + 1/cfxGroundTroops.ups)
	-- iterate all my troops and build next 
	-- versions pool
	local liveTroops = {} -- filtered table, indexed by name 
	for idx, troop in pairs(cfxGroundTroops.deployedTroops) do 
		local group = troop.group 
		if not dcsCommon.isGroupAlive(group) then 
			-- group dead. remove from pool
			-- this happens by not copying it into the poos
			cfxGroundTroops.invokeCallbacksFor("dead", troop) -- notify anyone who is interested that we are no longer proccing these 
		else 
			-- work with this groop according to its orders
			cfxGroundTroops.updateTroops(troop)
			-- since group is alive remember it for next loop
			liveTroops[idx] = troop -- do NOT use insert as we have indexed table by name
		end
	end
	-- liveTroops holds all troops that are still alive and will
	-- be revisited next loop
	cfxGroundTroops.deployedTroops = liveTroops
end

--
-- UpdateQueued looks for the first unordered (.receivedOrders == false) group
-- and processes them. if orders are 'laze', it will always be ordered 
--


function cfxGroundTroops.updateQueued()
	cfxGroundTroops.updateSchedule = timer.scheduleFunction(cfxGroundTroops.updateQueued, {}, timer.getTime() + 1/cfxGroundTroops.ups)
	-- iterate all my troops and build next 
	-- versions pool
	local liveTroops = {}
	local hasOrdered = false -- so far, no orders have been given 
	for idx, troop in pairs(cfxGroundTroops.deployedTroops) do 
		local group = troop.group 
		if not dcsCommon.isGroupAlive(group) then 
			-- group dead. remove from pool
			-- this happens by not copying it to liveTroops 
			-- trigger.action.outText("+++ removing ground troops " .. troop.name, 30)
			cfxGroundTroops.invokeCallbacksFor("dead", troop) -- notify anyone who is interested that we are no longer proccing these 
		else 
			-- check if this is a lazer 
			if troop.orders == "laze" then 
				-- lazers are updated each turn 
				cfxGroundTroops.updateLaze(troop)
			else 
				if not hasOrdered and not (troop.receivedOrders) then 
				-- work with this groop according to its orders
				cfxGroundTroops.updateTroops(troop)
				troop.receivedOrders = true -- this one has received orders 
				hasOrdered = true 
				end 
			end
			liveTroops[idx] = troop -- do NOT use insert as we have indexed table
		end
	end
	-- liveTroops holds all troops that are still alive and will
	-- be revisited next loop
	cfxGroundTroops.deployedTroops = liveTroops
	
	-- if no orders have been passed, clear all troop's .receivedOrders flag 
	-- and the loop starts anew next loop 
	if not hasOrdered then 
		for idx, troop in pairs(cfxGroundTroops.deployedTroops) do
			troop.receivedOrders = nil  
		end
	end
end

--
-- in updateCheckOnly we simply check the ground queue 
-- if there are troops added that need scheduling (i.e. have 
-- been passed in by addTroops and schedule them 
--
function cfxGroundTroops.updateCheckOnly()
	-- re-schedule myself in 1 second 
	timer.scheduleFunction(cfxGroundTroops.updateCheckOnly, {}, timer.getTime() + 1)
	
	-- iterate through all troops, and 
	-- see if there are any that have not been scheduled 
	-- to schedule them for updates in 1 second
	-- that will be the first time that they are scheduled,
	-- all others will be self-scheduled 
	for idx, troop in pairs(cfxGroundTroops.deployedTroops) do 
		if not troop.hasBeenScheduled then 
			local params = {troop}
			troop.hasBeenScheduled = true 
			troop.updateID = timer.scheduleFunction(cfxGroundTroops.updateSingleScheduled, params, timer.getTime() + 1)
			--trigger.action.outText("+++groundT: scheduling troops <".. troop.group:getName() .."> with orders <" .. troop.orders .. ">", 30)
		end
	end
	-- note that alive checks are now done during the scheduled
	-- update, not every time for all

end

function cfxGroundTroops.updateSingleScheduled(params)
	local troops = params[1]
	troops.updateID = nil -- erase update id 
	if not troops then 
		trigger.action.outText("+++groundT WARNING: nil troop in updateSingle", 30)
		return -- no further action required, no longer updates
	end
	
	local group = troops.group 
	-- see if we have been taken out of the pool or updated
	-- if so, exit 
	
	if not group:isExist() then 
		-- simply never again look at it. 
		return 
	end
	
	if cfxGroundTroops.deployedTroops[troops.group:getName()] ~= troops then 
		-- trigger.action.outText("+++groundT NOTE: troops <".. troops.group:getName() .."> was removed from pool. Cancel Update", 30)
		return -- no further reschedule
	end
	
	-- see if scheduling is turned off
	if not troops.reschedule then 
		trigger.action.outText("+++groundT NOTE: no longer updating <".. troops.group:getName() .."> per reschedule param", 30)
		return 
	end
	
	-- now, check if still alive 
	if not dcsCommon.isGroupAlive(group) then 
		-- group dead, no longer updates 
		cfxGroundTroops.invokeCallbacksFor("dead", troops) -- notify anyone who is interested that we are no longer proccing these 
		cfxGroundTroops.removeTroopsFromPool(troops)
		return -- nothing else to do
	end
	
	-- now, execute the update itself, standard update 
	cfxGroundTroops.updateTroops(troops)
	
	-- check max speed of group. if < 0.1 then note and increase 
	-- speedWarning. if not, reset speed warning 
	if troops.orders == "attackownedzone" and dcsCommon.getGroupMaxSpeed(troops.group) < 0.1 then 
		if not troops.speedWarning then troops.speedWarning = 0 end
		troops.speedWarning = troops.speedWarning + 1
	else
		troops.speedWarning = 0 -- reset
	end
	
	if troops.speedWarning > 5 then -- make me 5
		lastOrder = timer.getTime() - troops.lastOrderDate 
		-- this may be a matter of too many waypoints. 
		-- maybe issue orders to go to their destination directly?
		-- now force an order to go directly.
		if troops.speedWarning > 5 then 
			if troops.isOffroad then 
				-- we already switched to off-road. take me 
				-- out of the managed queue, I'm not going 
				-- anywhere
				cfxGroundTroops.removeTroopsFromPool(troops)
			else 
				cfxGroundTroops.switchToOffroad(troops)
				troops.isOffroad = true -- so we know that we already did that
			end
		end 
	end
	
	-- now reschedule update for my best time 
	local updateTime = cfxGroundTroops.getScheduleInterval(troops.orders)
	troops.updateID = timer.scheduleFunction(cfxGroundTroops.updateSingleScheduled, params, timer.getTime() + updateTime)
end


--
-- PILEUP and TIE BRAKERS
--
-- there may come a situation where troops gather in 
-- one zone because the zone isn't won - some other troops 
-- are there and noone moves. 
-- a tie-break is required
--

-- checkpile up: every so often, we test if we have run into a 
-- pileup-situation. this happens if there are more than n 
-- units with group-attacker order in the same zone, and that 
-- zone is their destination 
-- this can be easily detected by the insideDestination flag 
-- checkPileUp should be run every minute or so 
 
function cfxGroundTroops.checkPileUp()
	-- schedule my next call 
	timer.scheduleFunction(cfxGroundTroops.checkPileUp, {}, timer.getTime() + 60)
	local thePiles = {}
	if not cfxOwnedZones then 
		return 
	end
	
	-- create a list of all piles 
--	for idx, oz in pairs(cfxOwnedZones.zones) do 
	for idx, oz in pairs(cfxOwnedZones.allManagedOwnedZones) do 
		local newPile = {}
		newPile[1] = 0 -- no red inZone here 
		newPile[2] = 0 -- no blue inZone here 
		newPile.zone = oz -- the zone we are looking at 
		thePiles[oz] = newPile 
	end
	
	-- now iterate through all currently alive groups and 
	-- attribute them to their piles 
	for idx, troop in pairs(cfxGroundTroops.deployedTroops) do 
		-- get each group and count them if they are inside
		-- their destination 
		if troop.insideDestination and troop.group:isExist() then
			local side = troop.group:getCoalition()
			local thePile = thePiles[troop.destination]
			local theSide = troop.group:getCoalition()
			thePile[theSide] = thePile[theSide] + 1 -- we count groups, not units  
		end
	end
	
	-- a pileup happens, if there are more than 3 groups in destination zone
	-- with NO other troops present (usually the case)
	-- or when there are 5 groups more than the number for the other side 
	-- so now scan all piles
	for idx, thePile in pairs(thePiles) do 
		-- check red pileup 
		if thePile[1] > 3 and thePile[2] == 0 then 
			-- simple pileup. 3 groups, no others except defenders and 
			-- perhaps transients 
			cfxGroundTroops.breakTie(thePile, 1)
		elseif thePile[1] >= thePile[2] + 5 then 
			-- numerical pileup 
			cfxGroundTroops.breakTie(thePile, 1)
		end
		
		-- check blue loside 
		if thePile[2] >= 3 and thePile[1] == 0 then 
			-- simple pileup. 3 groups, no others except defenders and 
			-- perhaps transients 
			cfxGroundTroops.breakTie(thePile, 2)
		elseif thePile[2] >= thePile[1] + 5 then 
			-- numerical pileup 
			cfxGroundTroops.breakTie(thePile, 2)
		end
	end
end

function cfxGroundTroops.breakTie(thePile, winner)
	trigger.action.outText("+++ groundT: TIEBREAK - winner is " .. winner .. " in zone " .. thePile.zone.name .. ": " .. thePile[1] .. ":" .. thePile[2] , 30)
	-- now add some code to do the actual tie breaking: remove all units that 
	-- are inside the zone and who belong to the other side 
	local loser = 1 -- red default 
	local theZone = thePile.zone 
	if winner == 1 then loser = 2 end 
	-- now get all ground groups for the losing side
	local losingGround = coalition.getGroups(loser, Group.Category.GROUND)
	for idx, theGroup in pairs(losingGround) do 
		-- if alive, check if inside the zone 
		if theGroup:isExist() and dcsCommon.isGroupAlive(theGroup) then 
			-- make sure it's not a transient
			if not isDeployedGroundTroop(theGroup) then 
				local p = dcsCommon.getGroupLocation(theGroup) 
				if cfxZones.isPointInsideZone(p, theZone) then 
					trigger.action.outText("+++ groundT: TIEBREAK - destroying group " .. theGroup:getName() , 30)
					-- we delete this group now
					theGroup:destroy()
				end
			end
		end
	end
end

--
-- sanity checks for rescheduling
--
function cfxGroundTroops.checkSchedules()
	timer.scheduleFunction(cfxGroundTroops.checkSchedules, {}, timer.getTime() + 10)
	for idx, troop in pairs(cfxGroundTroops.deployedTroops) do
		-- check if troop is not scheduled 
		-- if this happens to a group more than a certain times,
		-- it has somehow dropped out of the reschedule 
		-- plan and needs to be scheduled 
		if troop.updateID == nil then 
			troop.unscheduleCount = troop.unscheduleCount + 1
			if (troop.unscheduleCount > 1) and troop.group:isExist() then 
				trigger.action.outText("+++ groundT: unscheduled group  " .. troop.group:getName() .. " cnt=" .. troop.unscheduleCount , 30)
			end 
		end
	end
end

--
-- REPORTING 
--
-- 
-- get a report of troops as string 
-- 
function cfxGroundTroops.getTroopReport(theSide, ignoreInfantry)
	if not ignoreInfantry then ignoreInfantry = false end 
	local report = "GROUND FORCES REPORT"
	for idx, troop in pairs(cfxGroundTroops.deployedTroops) do 
		if troop.side == theSide and troop.group:isExist() then 
			local unitNum = troop.group:getSize()
			report = report .. "\n" .. troop.name .. " (".. unitNum .."): <" .. troop.orders .. ">" 
			if troop.orders == "attackownedzone" then 
				if troop.destination then 	
					report = report .. " move towards " .. troop.destination.name 
				else 
					report = report .. " (selecting destination)"
				end
			end
		end
	end
	report = report .. "\n---END REPORT\n"
	return report 
end

--
-- createGroundTroop
-- use this to create a cfxGroundTroops from a dcs group
--
function cfxGroundTroops.createGroundTroops(inGroup, range, orders, moveFormation, code, canDrive) 
	local newTroops = {}
	if not orders then 
		orders = "guard" 
	end
	if not moveFormation then moveFormation = "Custom" end 
	if orders:lower() == "lase" then 
		orders = "laze" -- we use WRONG spelling here, cause we're cool. yeah, right.
	end
	newTroops.insideDestination = false
	newTroops.unscheduleCount = 0 -- will count up as we aren't scheduled
	newTroops.speedWarning = 0
	newTroops.isOffroad = false -- if true, we switched to direct orders, not roads, after standstill
	newTroops.group = inGroup
	newTroops.orders = orders:lower()
	newTroops.coalition = inGroup:getCoalition()
	newTroops.side = newTroops.coalition -- because we'e been using both.
	newTroops.name = inGroup:getName()
	newTroops.moveFormation = moveFormation
	newTroops.moving = false -- set to not have received move orders yet 
	newTroops.signature = "cfx" -- to verify this is groundTroop group, not dcs groups
	if not range then range = 300 end
	newTroops.range = range
	if not code then code = cfxGroundTroops.laseCode end 
	newTroops.code = code 
	newTroops.canDrive = canDrive
--	trigger.action.outText("createGndT with code = <" .. code .. ">", 30)
	return newTroops
end

function cfxGroundTroops.addGroundTroopsToPool(troops) -- troops MUST be a table that I understand, with 
	if not troops then return end
	if troops.signature ~= "cfx" then 
		trigger.action.outText("+++ adding ground troops with unsupported troop signature", 30)
		return 
	end
	if not troops.orders then troops.orders = "guard" end 
	troops.orders = troops.orders:lower()
	
	--trigger.action.outText("Enter adding group <" .. troops.name .. "> with orders=<" .. troops.orders .. "> to pool", 30)
	
	if not troops.moveFormation then troops.moveFormation = "Custom" end 
	troops.reschedule = true -- in case we use scheduled update 
	-- we now add to internal array. this is worked on by all 
	-- update meths, on scheduled upadtes, it is only used to 
	-- pick up, and do the initial schedule, after that they 
	-- all re-schedule themselves 
	troops.hasBeenScheduled = false -- so far, no updates 
	-- hasBeenScheduled is used by updateCheckOnly when scheduled 
	-- updates are used. 
	
	-- now add to actively managed table or queue it if enabled
	if cfxGroundTroops.maxManagedTroops > 0 and dcsCommon.getSizeOfTable(cfxGroundTroops.deployedTroops) >= cfxGroundTroops.maxManagedTroops then 
		-- we need to queue 
		table.insert(cfxGroundTroops.troopQueue, troops)
	else
		-- add to deployed set
		cfxGroundTroops.deployedTroops[troops.group:getName()] = troops
	end
end

function cfxGroundTroops.removeTroopsFromPool(troops)
	
	if not troops then return end 
	if troops.signature ~= "cfx" then return end

	if not troops.group:isExist() then 
		trigger.action.outText("warning: removeFromPool called with inexistant group", 30)
		return 
	end
	
	if cfxGroundTroops.deployedTroops[troops.group:getName()] then 
		local troop = cfxGroundTroops.deployedTroops[troops.group:getName()]
		troops.reschedule = false -- so a reschedule wont update any more
		cfxGroundTroops.deployedTroops[troops.group:getName()] = nil
		return 
	end
	
	-- if we get here, we need to check if perhaps the troops 
	-- are in the queue
	for i=1, #cfxGroundTroops.troopQueue do 
		if cfxGroundTroops.troopQueue[i] == troops then 
			table.remove(cfxGroundTroops.troopQueue, i)
			return
		end
	end
end

function isDeployedGroundTroop(aGroup) 
	if not aGroup then return false end 
	-- see if its already managed
	if cfxGroundTroops.deployedTroops[aGroup:getName()] ~= nil then 
		return true 
	end 
	
	-- see if it's in the queue 
	for i=1, #cfxGroundTroops.troopQueue do 
		if cfxGroundTroops.troopQueue[i] == troops then 
			return true
		end
	end
	-- if we get here, it's neither managed nor queued
	return false 
--	return cfxGroundTroops.deployedTroops[aGroup:getName()] ~= nil 
end

function cfxGroundTroops.getGroundTroopsForGroup(aGroup) 
	if not (cfxGroundTroops.deployedTroops[aGroup:getName()]) then
		-- see if it's queued 
		for i=1, #cfxGroundTroops.troopQueue do 
			local troops = cfxGroundTroops.troopQueue[i]
			if troops.group == aGroup then 
				return troops
			end
		end
		
		if cfxGroundTroops.verbose then 
			trigger.action.outText("+++gndT - WARNING: cannot find group " .. aGroup:getName() .. " for troop retrieval. Known troops are:", 30)
		end 
		for k,v in pairs(cfxGroundTroops.deployedTroops) do 
			trigger.action.outText("+++ ".. k .. ": has v: " .. v.name, 30)
		end
		return nil
	end
	
	return cfxGroundTroops.deployedTroops[aGroup:getName()]
end

function cfxGroundTroops.monitorQueues()
	timer.scheduleFunction(cfxGroundTroops.monitorQueues, {}, timer.getTime() + 5)
	
	-- calculate the numbers 
	local num = dcsCommon.getSizeOfTable(cfxGroundTroops.deployedTroops)
	
	local msg = "+++ gndT - Groups Managed: <" .. num .. ">"
	-- display the numbers
	if cfxGroundTroops.maxManagedTroops > 0 then 
		msg = msg .. " capped at " .. cfxGroundTroops.maxManagedTroops .. ", q size is <" .. #cfxGroundTroops.troopQueue .. ">"
	end
	trigger.action.outText(msg, 30)
end


-- manageQueue: if depth of deployedTroops is below max and we have 
-- items in queue, pop off first one and put in managed table 
-- checked once every 2 seconds 
function cfxGroundTroops.manageQueues() 
	timer.scheduleFunction(cfxGroundTroops.manageQueues, {}, timer.getTime() + 2)
	if cfxGroundTroops.maxManagedTroops < 1 then return end
	
	-- if we get here, we have a limit on managed 
	-- items 
	if #cfxGroundTroops.troopQueue < 1 then return end 
	
	-- if we here, there are items waiting in the queue
	while dcsCommon.getSizeOfTable(cfxGroundTroops.deployedTroops) < cfxGroundTroops.maxManagedTroops and #cfxGroundTroops.troopQueue > 0 do 
		-- transfer items from the front to the managed queue 
		local theTroops = cfxGroundTroops.troopQueue[1]
		table.remove(cfxGroundTroops.troopQueue, 1)
		if theTroops.group:isExist() then 
			cfxGroundTroops.deployedTroops[theTroops.group:getName()] = theTroops
		end
	end
end


function cfxGroundTroops.start()
	if not dcsCommon.libCheck("cfx Ground Troops",
							  cfxGroundTroops.requiredLibs)
	then 
		trigger.action.outText("cf/x Ground Troops aborted: missing libraries", 30)
		return false 
	end
	
	-- read optional config zone 
	cfxGroundTroops.readConfigZone()
	
	if cfxGroundTroops.scheduledUpdates then 
		cfxGroundTroops.queuedUpdates = false 
		cfxGroundTroops.updateCheckOnly()
		cfxGroundTroops.checkSchedules() -- check regularly if all troops have been updated by checking their ID
	elseif cfxGroundTroops.queuedUpdates then 
		cfxGroundTroops.updateQueued()
	else 	
		cfxGroundTroops.update()
	end 
	-- now install a regular pileup check 
	timer.scheduleFunction(cfxGroundTroops.checkPileUp, {}, timer.getTime() + 60) 
	
	if cfxGroundTroops.monitorNumbers then 
		timer.scheduleFunction(cfxGroundTroops.monitorQueues, {}, timer.getTime() + 5) 
	end
	
	if cfxGroundTroops.maxManagedTroops > 0 then
		timer.scheduleFunction(cfxGroundTroops.manageQueues, {}, timer.getTime() + 1) 
	end 
	
	trigger.action.outText("cf/x Ground Troops v" .. cfxGroundTroops.version .. " started", 30)
	
	if not cfxOwnedZones then 
		--trigger.action.outText("+++groundT: pileUp - owned zones not yet ready", 30)
	end
	return true 
end

if not cfxGroundTroops.start() then 
	cfxGroundTroops = nil 
	trigger.action.outText("cfxGroundTroops aborted load", 30)
end

--[[--
 TO DO 
 
 - implement 'patrol' orders!!! 
   
   when ordering a new route, issue a command to stop in 1 second
 and another with new marching orders in 5 seconds 
 look at setTask() and resetTask() for controller
 - change group logic to set itself up to 'requestOrders' with group as parameter, so they can decide themselves how quickly they want to be re-tasked
 
 - DONE enqueue and dequeue methods with capped ground troops size 
 - named locs have strategic values attached (default = 1), and distance is divided by strat value to get at priority when rerouting 
 
 - difficulty increase: make enemy troops better by raining their spawned level 
 
 - check out simple slot block SSB (pre-moose) to see if we can implement slot blocking for downed pilots 
 
 - new 'wanda' (wander) module to make airports more lively: zone, have individuals/single vehicle wander around. two waypoints (start and stop), that are zones, and whenever they reach one or are at speed 0, they get a new one. may have pause before they go to next. 
 variant on above: selection of zones that are somehow connected, and destinations are made between these for patrolling zone. can force order, loop, and ping-pong. 
--]]--