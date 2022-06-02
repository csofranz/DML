cfxSpawnZones = {}
cfxSpawnZones.version = "1.6.0"
cfxSpawnZones.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	             -- pretty stupid to check for this since we 
				 -- need common to invoke the check, but anyway
	"cfxZones", -- Zones, of course 
	"cfxCommander", -- to make troops do stuff
	"cfxGroundTroops", -- generic data module for weight 
}
cfxSpawnZones.ups = 1
cfxSpawnZones.verbose = false 
--
-- Zones that conform with this requirements spawn toops automatically
--   *** DOES NOT EXTEND ZONES *** LINKED OWNER via masterOwner ***
-- 

-- version history
--   1.3.0 
--         - maxSpawn
--         - orders
--         - range
--   1.3.1 - spawnWithSpawner correct translation of country to coalition 
--         - createSpawner - corrected reading from properties
--   1.3.2 - createSpawner - correct reading 'owner' from properties, now 
--           directly reads coalition
--   1.4.0 - checks modules 
--         - orders 'train' or 'training' - will make the 
--           ground troops be issued HOLD WEAPS and 
--           not added to any queue. 'Training' troops 
--           are target dummies.
--         - optional heading attribute 
--         - typeMult: repeate type this many time (can produce army in one call)
--   1.4.1 - 'requestable' attribute. will automatically set zone to 
--         - paused, so troops can be produced on call
--         - getRequestableSpawnersInRange 
--   1.4.2 - target attribute. used for
--         - orders: attackZone 
--         - spawner internally copies name from cfxZone used for spawning (convenience only)
--   1.4.3 - can subscribe to callbacks. currently called when spawnForSpawner is invoked, reason is "spawned"
--         - masterOwner to link ownership to other zone 
--   1.4.4 - autoRemove flag to instantly start CD and respawn 
--   1.4.5 - verify that maxSpawns ~= 0 on initial spawn on start-up 
--   1.4.6 - getSpawnerForZoneNamed(aName)
--         - nil-trapping orders before testing for 'training'
--   1.4.7 - defaulting orders to 'guard'
--         - also accept 'dummy' and 'dummies' as substitute for training 
--   1.4.8 - spawnWithSpawner uses getPoint to support linked spawn zones 
--         - update spawn count on initial spawn
--   1.5.0 - f? support to trigger spawn 
--         - spawnWithSpawner made string compatible
--   1.5.1 - relaxed baseName and default to dcsCommon.uuid()
--         - verbose 
--   1.5.2 - activate?, pause? flag 
--   1.5.3 - spawn?, spawnUnits? flags 
--   1.6.0 - trackwith interface for group tracker
--
-- new version requires cfxGroundTroops, where they are 
--
-- How do we recognize a spawn zone?
-- contains a "spawner" attribute
-- a spawner must also have the following attributes
--  - spawner - anything, must be present to signal. put in 'ground' to be able to expand to other types  
--  - types    - type strings, comma separated 
-- see here: https://github.com/mrSkortch/DCS-miscScripts/tree/master/ObjectDB
--  - typeMult - repeat types n times to create really LOT of troops. optional, defaults to 1
--  - country  - defaults to 2 (usa) -- see here https://wiki.hoggitworld.com/view/DCS_enum_country
--    some important: 0 = Russia, 2 = US, 82 = UN neutral
--    country is converted to coalition and then assigned to
--    Joint Task Force <side> upon spawn
--  - masterOwner - optional name of master cfxZone used to determine whom the surrounding 
--    territory belongs to. Spwaner will only spawn if the owner coalition is the 
--    the same as the coalition my own county belongs to.
--    if not given, spawner spawns even if inside a zone owned by opposing force 
--  - baseName - for naming spawned groups - MUST BE UNIQUE!!!!
--  
-- the following attributes are optional 
--  - cooldown, defaults to 60 (seconds) after troops are removed from zone,
--    then the next group spawns. This means troops will only spawn after 
--    troops are removed and cooldown timed out 
--  - autoRemove - instantly removes spwaned troops, will spawn again 
--    again after colldown 
--  - formation - default is  circle_out; other formations are 
--		- line - left lo right (west-east) facing north
--      - line_V - vertical line, facing north
--      - chevron - west-east, point growing to north 
--      - scattered, random
--      - circle, circle_forward (all fact north)
--		- circle-in (all face in)
--      - circle-out (all face out)
--      - grid, square, rect arrayed in optimal grid
--      - 2deep, 2cols two columns, deep 
--      - 2wide 2 columns wide (2 deep) 
--  - heading in DEGREES (deafult 0 = north ) direction entire group is facing 
--  - destination - zone name to go to, no destination = stay where you are 
--  - paused - defaults to false. If present true, spawning will not happen
--    you can then manually invoke cfxSpawnZones.spawnWithSpawner(spawner) to 
--    spawn the troops as they are described in the spawner 
--  - orders - tell them what to do. "train" makes them dummies, "guard" 
--    "laze", "wait-laze" etc 
--    other orders are as defined by cfxGroundTroops, at least 
--      guard - hold and defend (default)
--      laze - laze targets 
--      wait-xxx for helo troops, stand by until dropped from helo 
--      attackOwnedZone - seek nearest owned zone and attack
--      attackZone - move towards the named cfxZone. will generate error if zone not found 
--      name of zone to attack is in 'target' attribute
--  - target - names a target cfxZone, used for orders. Troops will immediately
--    start moving towards that zone if defined and such a zone exists
--  - maxSpawns - limit number of spawn cycles. omit or -1 is unlimited
--  - requestable - used with heloTroops to determine if spawning can be ordered by 
--    comms when in range
-- respawn currently happens after theSpawn is deleted and cooldown seconds have passed 
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
	
	-- interface to groupTracker 
	-- WARNING: attaches to ZONE, not spawner object
	if cfxZones.hasProperty(inZone, "trackWith:") then 
		inZone.trackWith = cfxZones.getStringFromZoneProperty(inZone, "trackWith:", "<None>")
	end
		
	-- connect with ME if a trigger flag is given 
	if cfxZones.hasProperty(inZone, "f?") then 
		theSpawner.triggerFlag = cfxZones.getStringFromZoneProperty(inZone, "f?", "none")
		theSpawner.lastTriggerValue = trigger.misc.getUserFlag(theSpawner.triggerFlag)
	end
	
	-- synonyms spawn? and spawnObject?
	if cfxZones.hasProperty(inZone, "spawn?") then 
		theSpawner.triggerFlag = cfxZones.getStringFromZoneProperty(inZone, "spawn?", "none")
		theSpawner.lastTriggerValue = trigger.misc.getUserFlag(theSpawner.triggerFlag)
	end
	
	if cfxZones.hasProperty(inZone, "spawnUnits?") then 
		theSpawner.triggerFlag = cfxZones.getStringFromZoneProperty(inZone, "spawnObject?", "none")
		theSpawner.lastTriggerValue = trigger.misc.getUserFlag(theSpawner.triggerFlag)
	end
	
	if cfxZones.hasProperty(inZone, "activate?") then 
		theSpawner.activateFlag = cfxZones.getStringFromZoneProperty(inZone, "activate?", "none")
		theSpawner.lastActivateValue = trigger.misc.getUserFlag(theSpawner.activateFlag)
	end
	
	if cfxZones.hasProperty(inZone, "pause?") then 
		theSpawner.pauseFlag = cfxZones.getStringFromZoneProperty(inZone, "pause?", "none")
		theSpawner.lastPauseValue = trigger.misc.getUserFlag(theSpawner.pauseFlag)
	end
	
	theSpawner.types = cfxZones.getZoneProperty(inZone, "types")
	--theSpawner.owner = cfxZones.getCoalitionFromZoneProperty(inZone, "owner", 0)
	-- synthesize types * typeMult
	local n = cfxZones.getNumberFromZoneProperty(inZone, "typeMult", 1)
	local repeater = ""
	if n < 1 then n = 1 end 
	while n > 1 do 
		repeater = repeater .. "," .. theSpawner.types
		n = n - 1
	end
	theSpawner.types = theSpawner.types .. repeater 
	
	theSpawner.country = cfxZones.getNumberFromZoneProperty(inZone, "country", 0) -- coalition2county(theSpawner.owner)
	theSpawner.masterZoneName = cfxZones.getStringFromZoneProperty(inZone, "masterOwner", "")
	if theSpawner.masterZoneName == "" then theSpawner.masterZoneName = nil end 
	
	theSpawner.rawOwner = coalition.getCountryCoalition(theSpawner.country)
	--theSpawner.baseName = cfxZones.getZoneProperty(inZone, "baseName")
	theSpawner.baseName = cfxZones.getStringFromZoneProperty(inZone, "baseName", dcsCommon.uuid("SpwnDflt"))
	
	theSpawner.cooldown = cfxZones.getNumberFromZoneProperty(inZone, "cooldown", 60)
	theSpawner.autoRemove = cfxZones.getBoolFromZoneProperty(inZone, "autoRemove", false)
	theSpawner.lastSpawnTimeStamp = -10000 -- just init so it will always work
	theSpawner.heading = cfxZones.getNumberFromZoneProperty(inZone, "heading", 0)
	--trigger.action.outText("+++spwn: zone " .. inZone.name .. " owner " .. theSpawner.owner " --> ctry " .. theSpawner.country, 30)
	
	theSpawner.cdTimer = 0 -- used for cooldown. if timer.getTime < this value, don't spawn
	theSpawner.cdStarted = false -- used to initiate cooldown when theSpawn disappears
	theSpawner.count = 1 -- used to create names, and count how many groups created
	theSpawner.theSpawn = nil -- link to last spawned group
	theSpawner.formation = "circle_out"
	theSpawner.formation = cfxZones.getStringFromZoneProperty(inZone, "formation", "circle_out")
	theSpawner.paused = cfxZones.getBoolFromZoneProperty(inZone, "paused", false)
	theSpawner.orders = cfxZones.getStringFromZoneProperty(inZone, "orders", "guard")
	--theSpawner.orders = cfxZones.getZoneProperty(inZone, "orders")
	-- used to assign special orders, default is 'guard', use "laze" to make them laze targets. can be 'wait-' which may auto-convert to 'guard' after pick-up by helo, to be handled outside.
	-- use "train" to tell them to HOLD WEAPONS, don't move and don't participate in loop, so we have in effect target dummies
	-- can also use order 'dummy' or 'dummies' to switch to train
	if theSpawner.orders:lower() == "dummy" or theSpawner.orders:lower() == "dummies" then theSpawner.orders = "train" end 
	
	theSpawner.range = cfxZones.getNumberFromZoneProperty(inZone, "range", 300) -- if we have a range, for example enemy detection for Lasing or engage range
	theSpawner.maxSpawns = cfxZones.getNumberFromZoneProperty(inZone, "maxSpawns", -1) -- if there is a limit on how many troops can spawn. -1 = endless spawns
	theSpawner.requestable = cfxZones.getBoolFromZoneProperty(inZone, "requestable", false)
	if theSpawner.requestable then 
		theSpawner.paused = true 
	end
	theSpawner.target = cfxZones.getStringFromZoneProperty(inZone, "target", "")
	if theSpawner.target == "" then -- this is the defaut case 
		theSpawner.target = nil 
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
		local delta = dcsCommon.dist(aPoint, aZone.point)
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
	end
	
	if not masterZone.owner then 
		--trigger.action.outText("spawner " .. spawner.name .. " - masterZone " .. masterZone.name .. " HAS NO OWNER????", 30)
		return true 
	end
	
	if (myCoalition ~= masterZone.owner) then 
		-- can't spawn, surrounding area owned by enemy
		--trigger.action.outText("spawner " .. spawner.name .. " - spawn suppressed: area not owned: " .. " master owner is " .. masterZone.owner .. ", we are " .. myCoalition, 30)
		return false 
	end
	--trigger.action.outText("spawner " .. spawner.name .. " good to go: ", 30)
	return true
end

function cfxSpawnZones.spawnWithSpawner(aSpawner)
	if type(aSpawner) == "string" then -- return spawner for zone of that name
		aSpawner = cfxSpawnZones.getSpawnerForZoneNamed(aName)
	end
	if not aSpawner then return end 
	local theZone = aSpawner.zone -- retrieve the zone that defined me 
	
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
--	trigger.action.outText("+++ spawn: coal <" .. theCoalition .. "> from country <" .. theCountry .. ">", 30)
	
	local theGroup = cfxZones.createGroundUnitsInZoneForCoalition (
				theCoalition, 
				aSpawner.baseName .. "-" .. aSpawner.count, -- must be unique 
				aSpawner.zone, 											
				unitTypes, 													
				aSpawner.formation,
				aSpawner.heading)
	aSpawner.theSpawn = theGroup
	aSpawner.count = aSpawner.count + 1 
	-- we may also want to add this to auto ground troops pool 
	-- we not only want to, we absolutely need to in order 
	-- to make this work. 
	
	if aSpawner.orders and (
	   aSpawner.orders:lower() == "training" or 
	   aSpawner.orders:lower() == "train" )
	then 
		-- make them ROE "HOLD"
		cfxCommander.scheduleOptionForGroup(
			theGroup, 
			AI.Option.Ground.id.ROE, 
			AI.Option.Ground.val.ROE.WEAPON_HOLD, 
			1.0)
	else 
		local newTroops = cfxGroundTroops.createGroundTroops(theGroup, aSpawner.range, aSpawner.orders) 
		cfxGroundTroops.addGroundTroopsToPool(newTroops)
		
		-- see if we have defined a target zone as destination
		if aSpawner.target then 
			local destZone = cfxZones.getZoneByName(aSpawner.target)
			if destZone then
				newTroops.destination = destZone
				cfxGroundTroops.makeTroopsEngageZone(newTroops)
			else 
				trigger.action.outText("+++ spawner " .. aSpawner.name .. " has illegal target " .. aSpawner.target .. ". Pausing.", 30)
				aSpawner.paused = true 
			end
		elseif aSpawner.orders == "attackZone" then 
			trigger.action.outText("+++ spawner " .. aSpawner.name .. " has no target but attackZone command. Pausing.", 30)
				aSpawner.paused = true 		
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
	--if trackerName == "*" then trackerName = theZone.name end 
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

function cfxSpawnZones.update()
	cfxSpawnZones.updateSchedule = timer.scheduleFunction(cfxSpawnZones.update, {}, timer.getTime() + 1/cfxSpawnZones.ups)
	
	for key, spawner in pairs (cfxSpawnZones.allSpawners) do 
		-- see if the spawn is dead or was removed
		local needsSpawn = true 
		if spawner.theSpawn then 
			local group = spawner.theSpawn
			if group:isExist() then 
				-- see how many members of this group are still alive
				local liveUnits = dcsCommon.getLiveGroupUnits(group)
				-- spawn is still alive, will not spawn
				if #liveUnits > 1 then 
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
		if not aSpawner.paused and cfxSpawnZones.verifySpawnOwnership(aSpawner) and aSpawner.maxSpawns ~= 0 then 
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
	
	-- and start the regular update calls
	cfxSpawnZones.update()
	
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