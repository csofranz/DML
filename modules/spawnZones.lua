cfxSpawnZones = {}
cfxSpawnZones.version = "2.0.2"
cfxSpawnZones.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	             -- pretty stupid to check for this since we 
				 -- need common to invoke the check, but anyway
	"cfxZones", -- Zones, of course 
	"cfxCommander", -- to make troops do stuff
	"cfxGroundTroops", -- for ordering then around 
}
cfxSpawnZones.ups = 1
cfxSpawnZones.verbose = false 

-- persistence: all groups we ever spawned. 
-- is regularly GC'd

cfxSpawnZones.spawnedGroups = {}

--
-- Zones that conform with this requirements spawn toops automatically
--   *** DOES NOT EXTEND ZONES *** LINKED OWNER via masterOwner ***
-- 
--[[--
-- version history 
   2.0.0 - dmlZones
		 - moved "types" to spawner 
		 - baseName defaults to zone name, as it is safe for naming
         - spawnWithSpawner direct link in spawner to spawnZones
   2.0.1 - fix in verifySpawnOwnership() when not master zone found 
   2.0.2 - new "moveFormation" attribute 
   
  --]]--
  
cfxSpawnZones.allSpawners = {}
cfxSpawnZones.callbacks = {} -- signature: cb(reason, group, spawner)
 
--
-- C A L L B A C K S 
-- 
function cfxSpawnZones.addCallback(theCallback)
	table.insert(cfxSpawnZones.callbacks, theCallback)
end

function cfxSpawnZones.invokeCallbacksFor(reason, theGroup, theSpawner)
	for idx, theCB in pairs (cfxSpawnZones.callbacks) do 
		theCB(reason, theGroup, theSpawner)
	end
end


--
-- creating a spawner
--
function cfxSpawnZones.createSpawner(inZone)
	local theSpawner = {}
	theSpawner.zone = inZone
	theSpawner.name = inZone.name 
	theSpawner.spawnWithSpawner = cfxSpawnZones.spawnWithSpawner
	-- interface to groupTracker 
	-- WARNING: attaches to ZONE, not spawner object
	if inZone:hasProperty("trackWith:") then 
		inZone.trackWith = inZone:getStringFromZoneProperty("trackWith:", "<None>")
	end
	
	-- interface to delicates 
	if inZone:hasProperty("useDelicates") then 
		theSpawner.delicateName = dcsCommon.trim(inZone:getStringFromZoneProperty("useDelicates", "<none>"))
		if theSpawner.delicateName == "*" then theSpawner.delicateName = inZone.name end 
	end
	
	-- connect with ME if a trigger flag is given 
	if inZone:hasProperty("f?") then 
		theSpawner.triggerFlag = inZone:getStringFromZoneProperty("f?", "none")
		theSpawner.lastTriggerValue = trigger.misc.getUserFlag(theSpawner.triggerFlag)
	elseif inZone:hasProperty("spawn?") then 
		theSpawner.triggerFlag = inZone:getStringFromZoneProperty("spawn?", "none")
		theSpawner.lastTriggerValue = trigger.misc.getUserFlag(theSpawner.triggerFlag)
	elseif inZone:hasProperty("spawnUnits?") then 
		theSpawner.triggerFlag = inZone:getStringFromZoneProperty( "spawnObject?", "none")
		theSpawner.lastTriggerValue = trigger.misc.getUserFlag(theSpawner.triggerFlag)
	end
	
	if inZone:hasProperty("activate?") then 
		theSpawner.activateFlag = inZone:getStringFromZoneProperty( "activate?", "none")
		theSpawner.lastActivateValue = trigger.misc.getUserFlag(theSpawner.activateFlag)
	end
	
	if inZone:hasProperty("pause?") then 
		theSpawner.pauseFlag = inZone:getStringFromZoneProperty("pause?", "none")
		theSpawner.lastPauseValue = trigger.misc.getUserFlag(theSpawner.pauseFlag)
	end
	
	if inZone:hasProperty("types") then 
		theSpawner.types = inZone:getStringFromZoneProperty("types", "Soldier M4")
	else 
		theSpawner.types = inZone:getStringFromZoneProperty("spawner", "Soldier M4")
	end
	-- synthesize types * typeMult
	if inZone:hasProperty("typeMult") then 
		local n = inZone:getNumberFromZoneProperty("typeMult", 1)
		local repeater = ""
		if n < 1 then n = 1 end 
		while n > 1 do 
			repeater = repeater .. "," .. theSpawner.types
			n = n - 1
		end
		theSpawner.types = theSpawner.types .. repeater 
	end
	
	theSpawner.country = inZone:getNumberFromZoneProperty("country", 0)
	if inZone:hasProperty("masterOwner") then 
		theSpawner.masterZoneName = inZone:getStringFromZoneProperty("masterOwner", "")
		if theSpawner.masterZoneName == "" then theSpawner.masterZoneName = nil end 
	end 
	
	theSpawner.rawOwner = coalition.getCountryCoalition(theSpawner.country)
	-- theSpawner.baseName = inZone:getStringFromZoneProperty("baseName", dcsCommon.uuid("SpwnDflt"))
	theSpawner.baseName = inZone:getStringFromZoneProperty("baseName", "*")
	theSpawner.baseName = dcsCommon.trim(theSpawner.baseName)
	if theSpawner.baseName == "*" then 
		theSpawner.baseName = inZone.name -- convenience shortcut
	end
	
	theSpawner.cooldown = inZone:getNumberFromZoneProperty("cooldown", 60)
	theSpawner.autoRemove = inZone:getBoolFromZoneProperty("autoRemove", false)
	theSpawner.lastSpawnTimeStamp = -10000 -- init so it will always work
	theSpawner.heading = inZone:getNumberFromZoneProperty("heading", 0)	
	theSpawner.cdTimer = 0 -- used for cooldown. if timer.getTime < this value, don't spawn
	theSpawner.cdStarted = false -- used to initiate cooldown when theSpawn disappears
	theSpawner.count = 1 -- used to create names, and count how many groups created
	theSpawner.theSpawn = nil -- link to last spawned group
	theSpawner.formation = inZone:getStringFromZoneProperty("formation", "circle_out")
	theSpawner.moveFormation = inZone:getStringFromZoneProperty("moveFormation", "Custom")
	
	if theSpawner.moveFormation == "Custom" or theSpawner.moveFormation == "EchelonR" or theSpawner.moveFormation == "EchelonL" or theSpawner.moveFormation == "Diamond" or theSpawner.moveFormation == "Vee" or theSpawner.moveFormation == "Cone" or  theSpawner.moveFormation == "Rank" then -- all fine, do nothing
	else 
		trigger.action.outText("+++SpwZ: unknown moveFormation <" .. theSpawner.moveFormation .. "> in spawn zone <" .. inZone.name .. ">, defaulting to 'Custom'", 30)
		theSpawner.moveFormation = "Custom"
	end 
	theSpawner.paused = inZone:getBoolFromZoneProperty("paused", false)
	-- orders are always converted to all lower case 
	theSpawner.orders = inZone:getStringFromZoneProperty("orders", "guard"):lower() 
	-- used to assign orders, default is 'guard', use "laze" to make them laze targets. can be 'wait-' which may auto-convert to 'guard' after pick-up by helo, to be handled outside.
	-- use "train" to tell them to HOLD WEAPONS, don't move and don't participate in loop, so we have in effect target dummies
	-- can also use order 'dummy' or 'dummies' to switch to train
	if theSpawner.orders:lower() == "dummy" or theSpawner.orders:lower() == "dummies" then theSpawner.orders = "train" end 
	if theSpawner.orders:lower() == "training" then theSpawner.orders = "train" end 
	
	theSpawner.range = inZone:getNumberFromZoneProperty("range", 300) -- if we have a range, for example enemy detection for Lasing or engage range
	theSpawner.maxSpawns = inZone:getNumberFromZoneProperty("maxSpawns", -1) -- if there is a limit on how many troops can spawn. -1 = endless spawns
	theSpawner.requestable = inZone:getBoolFromZoneProperty( "requestable", false)
	if theSpawner.requestable then 
		theSpawner.paused = true 
		if inZone.verbose or cfxSpawnZones.verbose then 
			trigger.action.outText("+++spwn: spawner <" .. inZone.name .. "> paused: requestable enabled", 30)
		end
	end
	if inZone:hasProperty("target") then 
		theSpawner.target = inZone:getStringFromZoneProperty("target", "")
		if theSpawner.target == "" then -- this is the defaut case 
			theSpawner.target = nil 
		end
	end 
	
	if cfxSpawnZones.verbose or inZone.verbose then 
		trigger.action.outText("+++spwn: created spawner for <" .. inZone.name .. ">", 30)
	end	
	
	return theSpawner
end

function cfxSpawnZones.addSpawner(aSpawner)
	cfxSpawnZones.allSpawners[aSpawner.zone] = aSpawner
end

function cfxSpawnZones.removeSpawner(aSpawner)
	cfxSpawnZones.allSpawners[aSpawner.zone] = nil
end

function cfxSpawnZones.getSpawnerForZone(aZone)
	return cfxSpawnZones.allSpawners[aZone]
end

function cfxSpawnZones.getSpawnerForZoneNamed(aName)
	local aZone = cfxZones.getZoneByName(aName) 
	if not aZone then return nil end 
	return cfxSpawnZones.getSpawnerForZone(aZone)
end


function cfxSpawnZones.getRequestableSpawnersInRange(aPoint, aRange, aSide)
	-- trigger.action.outText("enter requestable spawners for side " .. aSide , 30)
	if not aSide then aSide = 0 end  
	if not aRange then aRange = 200 end 
	if not aPoint then return {} end 

	local theSpawners = {}
	for aZone, aSpawner in pairs(cfxSpawnZones.allSpawners) do 
		-- iterate all zones and collect those that match 
		local hasMatch = true 
		local delta = dcsCommon.distFlat(aPoint, cfxZones.getPoint(aZone))
		if delta>aRange then hasMatch = false end 
		if aSide ~= 0 then 
			-- check if side is correct for owned zone 
			if not cfxSpawnZones.verifySpawnOwnership(aSpawner) then 
				-- failed ownership test. owner of master 
				-- is not my own zone 
				hasMatch = false 
			end
		end
		
		if aSide ~= aSpawner.rawOwner then 
			-- only return spawners with this side
			-- note: this will NOT work with neutral players 
			hasMatch = false 
		end
		
		if not aSpawner.requestable then 
			hasMatch = false 
		end
		
		if hasMatch then 
			table.insert(theSpawners, aSpawner)
		end
	end
	
	return theSpawners
end
--
-- spawn troops 
-- 
function cfxSpawnZones.verifySpawnOwnership(spawner)
	-- returns false ONLY if masterSpawn disagrees
	if not spawner.masterZoneName then 
		--trigger.action.outText("spawner " .. spawner.name .. " no master, go!", 30)
		return true 
	end -- no master owner, all ok
	local myCoalition = spawner.rawOwner
	local masterZone = cfxZones.getZoneByName(spawner.masterZoneName)
	if not masterZone then 
		trigger.action.outText("spawner " .. spawner.name .. " DID NOT FIND MASTER ZONE <" .. spawner.masterZoneName .. ">", 30)
		return false 
	end
	
	if not masterZone.owner then 
		--trigger.action.outText("spawner " .. spawner.name .. " - masterZone " .. masterZone.name .. " HAS NO OWNER????", 30)
		return true 
	end
	
	if (myCoalition ~= masterZone.owner) then 
		-- can't spawn, surrounding area owned by enemy
		return false 
	end

	return true
end

function cfxSpawnZones.spawnWithSpawner(aSpawner)
	if type(aSpawner) == "string" then -- return spawner for zone of that name
		aSpawner = cfxSpawnZones.getSpawnerForZoneNamed(aName)
	end
	if not aSpawner then return end 
	local theZone = aSpawner.zone -- retrieve the zone that defined me 
	
	if cfxSpawnZones.verbose or theZone.verbose then 
		trigger.action.outText("+++spwn: started spawn with spawner for <" .. theZone.name .. ">", 30)
	end
	
	-- will NOT check if conditions are met. This forces a spawn
	local unitTypes = {} -- build type names
	--local p = aSpawner.zone.point  
	local p = cfxZones.getPoint(theZone) -- aSpawner.zone.point
		
	-- split the conf.troopsOnBoardTypes into an array of types
	unitTypes = dcsCommon.splitString(aSpawner.types, ",")
	if #unitTypes < 1 then 
		table.insert(unitTypes, "Soldier M4") -- make it one m4 trooper as fallback
	end
	
	local theCountry = aSpawner.country  
	local theCoalition = coalition.getCountryCoalition(theCountry)
	
	local theGroup, theData = cfxZones.createGroundUnitsInZoneForCoalition (
				theCoalition, 
				aSpawner.baseName .. "-" .. aSpawner.count, -- must be unique 
				aSpawner.zone, 											
				unitTypes, 
				aSpawner.formation,
				aSpawner.heading)
	if cfxSpawnZones.verbose or theZone.verbose then 
		-- check created group size versus requested size 
		trigger.action.outText("+++spwn: created <" .. theGroup:getSize() .. "> units, requested <" .. #unitTypes .. "> units, formation <" .. aSpawner.formation .. ">", 30)
		trigger.action.outText("+++spwn: zone <" .. theZone.name .. ">center at <" .. dcsCommon.point2text(p) .. ">", 30)
		local allUnits = theGroup:getUnits()
		for idx, myUnit in pairs (allUnits) do 
			local pos = myUnit:getPoint()
			trigger.action.outText("unit <" .. myUnit:getName() .. "> at " .. dcsCommon.point2text(pos), 30)
		end
	end
	
	aSpawner.theSpawn = theGroup
	aSpawner.count = aSpawner.count + 1 

	-- insert into collector for persistence
	local troopData = {}
	troopData.groupData = theData
	troopData.orders = aSpawner.orders -- always set 
	troopData.side = theCoalition
	troopData.moveFormation = aSpawner.moveFormation 
	troopData.target = aSpawner.target -- can be nil!
	troopData.tracker = theZone.trackWith -- taken from ZONE!!, can be nil
	troopData.range = aSpawner.range
	cfxSpawnZones.spawnedGroups[theData.name] = troopData 
	
	-- remember: orders are always lower case only 
	if aSpawner.orders and (
	   aSpawner.orders:lower() == "training" or 
	   aSpawner.orders:lower() == "train" )
	then 
		-- make them ROE "HOLD"
		-- remember to do this in persistence as well!
		-- they aren't fed to cfxGroundTroops.
		-- we should update groundTroops to simply 
		-- drop those with 'train' or 'training'
		cfxCommander.scheduleOptionForGroup(
			theGroup, 
			AI.Option.Ground.id.ROE, 
			AI.Option.Ground.val.ROE.WEAPON_HOLD, 
			1.0)
	else 
		local newTroops = cfxGroundTroops.createGroundTroops(theGroup, aSpawner.range, aSpawner.orders, aSpawner.moveFormation) 
		cfxGroundTroops.addGroundTroopsToPool(newTroops)
		
		-- see if we have defined a target zone as destination
		-- and set it accordingly 
		if aSpawner.target then 
			local destZone = cfxZones.getZoneByName(aSpawner.target)
			if destZone then
				newTroops.destination = destZone 
			else 
				trigger.action.outText("+++ spawner " .. aSpawner.name .. " has illegal (unknown) target zone <" .. aSpawner.target .. ">. Pausing.", 30)
				aSpawner.paused = true 
			end
		elseif aSpawner.orders == "attackzone" then 
			-- attackZone command but no zone given
			trigger.action.outText("+++ spawner " .. aSpawner.name .. " has no target but attackZone command. Pausing.", 30)
				aSpawner.paused = true 		
		end 
		
	end
	
	-- hand off to delicates 
	if aSpawner.delicateName and delicates then 
	-- pass this object to the delicate zone mentioned 
		local theDeli = delicates.getDelicatesByName(aSpawner.delicateName)
		if theDeli then 
			delicates.addGroupToInventoryForZone(theDeli, newTroops)
		else 
			trigger.action.outText("+++Spwn: spawner <" .. aZone.name .. "> can't find delicates <" .. aSpawner.delicateName .. ">", 30)
		end
	end
	
	-- track this if we are have a trackwith attribute 
	-- note that we retrieve trackwith from ZONE, not spawner 
	if theZone.trackWith then 
		cfxSpawnZones.handoffTracking(theGroup, theZone) 
	end
			
	-- callback to all who want to know 
	cfxSpawnZones.invokeCallbacksFor("spawned", theGroup, aSpawner)
	
	-- timestamp so we can check against cooldown on manual spawn
	aSpawner.lastSpawnTimeStamp = timer.getTime()
	-- make sure a requestable spawner is always paused 
	if aSpawner.requestable then 
		aSpawner.paused = true 
	end
	
	if aSpawner.autoRemove then 
		-- simply remove the group 
		aSpawner.theSpawn = nil
	end
end

function cfxSpawnZones.handoffTracking(theGroup, theZone)
-- note that this method works on theZone, not Spawner object
	if not groupTracker then 
		trigger.action.outText("+++spawner: <" .. theZone.name .. "> trackWith requires groupTracker module", 30) 
		return 
	end
	local trackerName = theZone.trackWith

	-- now assemble a list of all trackers
	if cfxSpawnZones.verbose or theZone.verbose then 
		trigger.action.outText("+++spawner: spawn pass-off: " .. trackerName, 30)
	end 
	
	local trackerNames = {}
	if dcsCommon.containsString(trackerName, ',') then
		trackerNames = dcsCommon.splitString(trackerName, ',')
	else 
		table.insert(trackerNames, trackerName)
	end
	for idx, aTrk in pairs(trackerNames) do 
		local theName = dcsCommon.trim(aTrk)
		if theName == "*" then theName = theZone.name end 
		local theTracker = groupTracker.getTrackerByName(theName)
		if not theTracker then 
			trigger.action.outText("+++spawner: <" .. theZone.name .. ">: cannot find tracker named <".. theName .. ">", 30) 
		else 
			groupTracker.addGroupToTracker(theGroup, theTracker)
			 if cfxSpawnZones.verbose or theZone.verbose then 
				trigger.action.outText("+++spawner: added " .. theGroup:getName() .. " to tracker " .. theName, 30)
			 end
		end 
	end 
end

--
-- U P D A T E 
--
function cfxSpawnZones.GC()
	-- GC run. remove all my dead remembered troops
	local filteredAttackers = {}
	local before = #cfxSpawnZones.spawnedGroups
	for gName, gData in pairs (cfxSpawnZones.spawnedGroups) do 
		-- all we need to do is get the group of that name
		-- and if it still returns units we are fine 
		local gameGroup = Group.getByName(gName)
		if gameGroup and gameGroup:isExist() and gameGroup:getSize() > 0 then 
			filteredAttackers[gName] = gData
		end
	end
	cfxSpawnZones.spawnedGroups = filteredAttackers
	if cfxSpawnZones.verbose then 
		trigger.action.outText("spawn zones GC ran: before <" .. before .. ">, after <" .. #cfxSpawnZones.spawnedGroups .. ">", 30)
	end
end

function cfxSpawnZones.update()
	cfxSpawnZones.updateSchedule = timer.scheduleFunction(cfxSpawnZones.update, {}, timer.getTime() + 1/cfxSpawnZones.ups)
	
	for key, spawner in pairs (cfxSpawnZones.allSpawners) do 
		-- see if the spawn is dead or was removed
		local needsSpawn = true 
		if spawner.theSpawn then 
			local group = spawner.theSpawn
			if group:isExist() then 
				-- see how many members of this group are still alive
				local liveUnits = group:getSize() --dcsCommon.getLiveGroupUnits(group)
				-- spawn is still alive, will not spawn
				if liveUnits > 1 then 
					-- we may want to check if this member is still inside
					-- of spawn location. currently we don't do that
					needsSpawn = false 
				end
			end
		end
	
		if spawner.paused then needsSpawn = false end 
		
		-- see if we spawned maximum number of times already
		-- or have -1 as maxspawn, indicating endless
		if needsSpawn and spawner.maxSpawns > -1 then 
			needsSpawn = spawner.maxSpawns > 0
		end
		
		if needsSpawn then 
			-- is this the first time? 
			if not spawner.cdStarted then 
				-- no, start cooldown
				spawner.cdStarted = true 
				spawner.cdTimer = timer.getTime() + spawner.cooldown
			end
		end

		-- still on cooldown?
		if timer.getTime() < spawner.cdTimer then needsSpawn = false end 
		
		-- is master zone still alinged with me?
		needsSpawn = needsSpawn and cfxSpawnZones.verifySpawnOwnership(spawner)

		-- check if perhaps our watchtriggers causes spawn
		if spawner.pauseFlag then 
			local currTriggerVal = trigger.misc.getUserFlag(spawner.pauseFlag)
			if currTriggerVal ~= spawner.lastPauseValue then
				spawner.paused = true  
				needsSpawn = false
				spawner.lastPauseValue = currTriggerVal
			end
		end
		
		if spawner.triggerFlag then 
			local currTriggerVal = trigger.misc.getUserFlag(spawner.triggerFlag)
			if currTriggerVal ~= spawner.lastTriggerValue then
				needsSpawn = true 
				spawner.lastTriggerValue = currTriggerVal
			end
		end
		
		if spawner.activateFlag then 
			local currTriggerVal = trigger.misc.getUserFlag(spawner.activateFlag)
			if currTriggerVal ~= spawner.lastActivateValue then
				spawner.paused = false  
				spawner.lastActivateValue = currTriggerVal
			end
		end

		
				
		-- if we get here, and needsSpawn is still set, we go ahead and spawn
		if needsSpawn then 
---			trigger.action.outText("+++ spawning for zone " .. spawner.zone.name, 30)
			cfxSpawnZones.spawnWithSpawner(spawner)
			spawner.cdStarted = false -- reset spawner cd signal 
			if spawner.maxSpawns > 0 then 
				spawner.maxSpawns = spawner.maxSpawns - 1
			end
			if spawner.maxSpawns == 0 then 
				spawner.paused = true 
				if cfxSpawnZones.verbose then 
					trigger.action.outText("+++ maxspawn -- turning off  zone " .. spawner.zone.name, 30)
				end 
			end
		else 
			-- trigger.action.outText("+++ NOSPAWN for zone " .. spawner.zone.name, 30)
		end
	end
end

function cfxSpawnZones.houseKeeping()
	timer.scheduleFunction(cfxSpawnZones.houseKeeping, {}, timer.getTime() + 5 * 60) -- every 5 minutes 
	cfxSpawnZones.GC()
end

--
-- LOAD/SAVE
--
function cfxSpawnZones.saveData()
	local theData = {}
	local allSpawnerData = {}
	-- now iterate all spawners and collect their data
	for theZone, theSpawner in pairs(cfxSpawnZones.allSpawners) do 
		local zName = theZone.name 
		local spawnData = {}
		if theSpawner.spawn and theSpawner.spawn:isExist() then 
			spawnData.spawn = theSpawner.spawn:getName()
		end
		spawnData.count = theSpawner.count
		spawnData.paused = theSpawner.paused 
		spawnData.cdStarted = theSpawner.cdStarted
		spawnData.cdTimer = theSpawner.cdTimer - timer.getTime() -- what remains of the cooldown time 
		
		allSpawnerData[zName] = spawnData
	end
	
	-- run a GC
	cfxSpawnZones.GC()
	-- now collect all living groups
	-- no longer required to check if group is lively
	local allLivingTroopData = {}
	for gName, gData in pairs(cfxSpawnZones.spawnedGroups) do 
		local sData = dcsCommon.clone(gData)
		dcsCommon.synchGroupData(sData.groupData)
		allLivingTroopData[gName] = sData
	end
	
	theData.spawnerData = allSpawnerData
	theData.troopData = allLivingTroopData
	return theData
end

function cfxSpawnZones.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("cfxSpawnZones")
	if not theData then 
		if cfxSpawnZones.verbose then 
			trigger.action.outText("+++spwn: no save date received, skipping.", 30)
		end
		return
	end
	
	-- we begin by re-spawning all spawned groups so that the 
	-- spwners can then later link to them 
	local allTroopData = theData.troopData
	for gName, gdTroop in pairs (allTroopData) do 
		local gData = gdTroop.groupData 
		local orders = gdTroop.orders 
		local moveFormation = gdTroop.moveFormation 
		local target = gdTroop.target
		local tracker = gdTroop.tracker 
		local side = gdTroop.side 
		local range = gdTroop.range
		local cty = gData.cty 
		local cat = gData.cat  
		
		-- now spawn, but first 
		-- add to my own attacker queue so we can save later 
		local gdClone = dcsCommon.clone(gdTroop)
		cfxSpawnZones.spawnedGroups[gName] = gdClone 
		local theGroup = coalition.addGroup(cty, cat, gData)
		-- post-proccing for 'train' orders
		if orders and (orders == "train" ) then 
			-- make them ROE "HOLD"
			cfxCommander.scheduleOptionForGroup(
				theGroup, 
				AI.Option.Ground.id.ROE, 
				AI.Option.Ground.val.ROE.WEAPON_HOLD, 
				1.0)
		else 
			-- add to groundTroops 
			local newTroops = cfxGroundTroops.createGroundTroops(theGroup, range, orders, moveFormation) 
			cfxGroundTroops.addGroundTroopsToPool(newTroops)
			-- engage a target zone 
			if target then 
				local destZone = cfxZones.getZoneByName(target)
				if destZone then
					newTroops.destination = destZone
					cfxGroundTroops.makeTroopsEngageZone(newTroops)
				end 
			end
		end 
				
		-- post-proccing for trackwith [may not be needed when we]
		-- have persistence in the tracking module. that module 
		-- simply schedules re-connecting after one second 
	end
	
	-- now set up all spawners with save data 
	local allSpawnerData = theData.spawnerData
	for zName, sData in pairs (allSpawnerData) do 
		local theZone = cfxZones.getZoneByName(zName)
		if theZone then 
			local theSpawner = cfxSpawnZones.getSpawnerForZone(theZone)
			if theSpawner then 
				theSpawner.inited = true -- inited by persistence
				theSpawner.count = sData.count 
				theSpawner.paused = sData.paused
				theSpawner.cdStarted = sData.cdStarted
				if theSpawner.cdStarted then 
					theSpawner.cdTimer = timer.getTime() + sData.cdTimer
				else 
					theSpawner.cdTimer = -1
				end
				if sData.spawn then 
					local theGroup = Group.getByName(sData.spawn)
					if theGroup then 
						theSpawner.spawn = theGroup
					else 
						trigger.action.outText("+++spwn (persistence): can't re-connect spawner <" .. zName .. "> with group <" .. sData.spawn .. ">, skipping", 30)
					end
				end
			else 
				trigger.action.outText("+++spwn (persistence): can't find spawner for zone <" .. zName .. ">, skipping", 30)
			end
		else 
			trigger.action.outText("+++spwn (persistence): can't find zone <" .. zName .. "> for spawner, skipping", 30)
		end
	end
	
end

--
-- START 
--
function cfxSpawnZones.initialSpawnCheck(aSpawner)
	if not aSpawner.paused 
	and cfxSpawnZones.verifySpawnOwnership(aSpawner) 
	and aSpawner.maxSpawns ~= 0 
	and not aSpawner.inited 
	then 
		cfxSpawnZones.spawnWithSpawner(aSpawner)
		-- update spawn count and make sure we haven't spawned the one and only 
		if aSpawner.maxSpawns > 0 then 
			aSpawner.maxSpawns = aSpawner.maxSpawns - 1
		end
		if aSpawner.maxSpawns == 0 then 
			aSpawner.paused = true 
			trigger.action.outText("+++ maxspawn -- turning off  zone " .. aSpawner.zone.name, 30)
		end
	end
end

function cfxSpawnZones.start()
	if not dcsCommon.libCheck("cfx Spawn Zones", 
		cfxSpawnZones.requiredLibs) then
		return false 
	end
	
	-- collect all spawn zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("spawner")
	
	-- now create a spawner for all, add them to the spawner updater, and spawn for all zones that are not
	-- paused 
	for k, aZone in pairs(attrZones) do 
		local aSpawner = cfxSpawnZones.createSpawner(aZone)
		cfxSpawnZones.addSpawner(aSpawner)
	end
	
	-- we now do persistence
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = cfxSpawnZones.saveData
		persistence.registerModule("cfxSpawnZones", callbacks)
		-- now load my data 
		cfxSpawnZones.loadData()
	end
	
	-- we now spawn if not taken care of by load / save 
	for theZone, aSpawner in pairs(cfxSpawnZones.allSpawners) do
		cfxSpawnZones.initialSpawnCheck(aSpawner)
	end
	
	-- and start the regular update calls
	cfxSpawnZones.update()
	
	-- start housekeeping 
	cfxSpawnZones.houseKeeping()
	
	trigger.action.outText("cfx Spawn Zones v" .. cfxSpawnZones.version .. " started.", 30)
	return true
end

if not cfxSpawnZones.start() then 
	trigger.action.outText("cf/x Spawn Zones aborted: missing libraries", 30)
	cfxSpawnZones = nil 
end

--[[--
IMPROVEMENTS
 'notMasterOwner' a flag to invert ownership, so we can spawn blue if masterOwner is red
  
  take apart owned zone and spawner, so we have a more canonical behaviour
  
  'repair' flag - have repair logic for units that are spawned just like now the owned zones do
--]]--