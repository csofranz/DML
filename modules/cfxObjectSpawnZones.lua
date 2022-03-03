cfxObjectSpawnZones = {}
cfxObjectSpawnZones.version = "1.2.0"
cfxObjectSpawnZones.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	             -- pretty stupid to check for this since we 
				 -- need common to invoke the check, but anyway
	"cfxZones", -- Zones, of course. MUST HAVE RUN
}
cfxObjectSpawnZones.ups = 1

--
-- Zones that conform with this requirements spawn toops automatically
--   *** DOES NOT EXTEND ZONES *** 
-- 
-- version history
--   1.0.0 - based on 1.4.6 version from cfxSpawnZones
--   1.1.0 - uses linkedUnit, so spawnming can occur on ships 
--           make sure you also enable useOffset to place the 
--           statics away from the center of the ship 
--   1.1.1 - also processes paused flag 
--         - despawnRemaining(spawner) 
--   1.1.2 - autoRemove option re-installed 
--         - added possibility to autoUnlink
--   1.1.3 - ME-triggered flag via f? and triggerFlag 
--   1.1.4 - activate?, pause? attributes 
--   1.1.5 - spawn?, spawnObjects? synonyms
--   1.2.0 - DML flag upgrade 
 
-- respawn currently happens after theSpawns is deleted and cooldown seconds have passed 
cfxObjectSpawnZones.allSpawners = {}
cfxObjectSpawnZones.callbacks = {} -- signature: cb(reason, group, spawner)
 

--
-- C A L L B A C K S 
-- 
function cfxObjectSpawnZones.addCallback(theCallback)
	table.insert(cfxObjectSpawnZones.callbacks, theCallback)
end

function cfxObjectSpawnZones.invokeCallbacksFor(reason, theSpawns, theSpawner)
	for idx, theCB in pairs (cfxObjectSpawnZones.callbacks) do 
		theCB(reason, theSpawns, theSpawner)
	end
end


--
-- creating a spawner
--
function cfxObjectSpawnZones.createSpawner(inZone)
	local theSpawner = {}
	theSpawner.zone = inZone
	theSpawner.name = inZone.name 
	
	-- connect with ME if a trigger flag is given 
	if cfxZones.hasProperty(inZone, "f?") then 
		theSpawner.triggerFlag = cfxZones.getStringFromZoneProperty(inZone, "f?", "none")
	end
	
	if cfxZones.hasProperty(inZone, "spawn?") then 
		theSpawner.triggerFlag = cfxZones.getStringFromZoneProperty(inZone, "spawn?", "none")
	end
	
	if cfxZones.hasProperty(inZone, "spawnObjects?") then 
		theSpawner.triggerFlag = cfxZones.getStringFromZoneProperty(inZone, "spawnObjects?", "none")
	end
	
	if theSpawner.triggerFlag then 
		theSpawner.lastTriggerValue = cfxZones.getFlagValue(theSpawner.triggerFlag, theSpawner) -- trigger.misc.getUserFlag(theSpawner.triggerFlag)
	end
	
	
	if cfxZones.hasProperty(inZone, "activate?") then 
		theSpawner.activateFlag = cfxZones.getStringFromZoneProperty(inZone, "activate?", "none")
		theSpawner.lastActivateValue = cfxZones.getFlagValue(theSpawner.activateFlag, theSpawner)   --trigger.misc.getUserFlag(theSpawner.activateFlag)
	end
	
	if cfxZones.hasProperty(inZone, "pause?") then 
		theSpawner.pauseFlag = cfxZones.getStringFromZoneProperty(inZone, "pause?", "none")
		theSpawner.lastPauseValue = cfxZones.getFlagValue(theSpawner.lastPauseValue, theSpawner) -- trigger.misc.getUserFlag(theSpawner.pauseFlag)
	end
	
	theSpawner.types = cfxZones.getStringFromZoneProperty(inZone, "types", "White_Tyre")
	local n = cfxZones.getNumberFromZoneProperty(inZone, "count", 1) -- DO NOT CONFUSE WITH OWN PROPERTY COUNT for unique names!!!
	if n < 1 then n = 1 end -- sanity check. 
	
	theSpawner.numObj = n 
	
	theSpawner.country = cfxZones.getNumberFromZoneProperty(inZone, "country", 2) -- coalition2county(theSpawner.owner)
	
	theSpawner.rawOwner = coalition.getCountryCoalition(theSpawner.country)
	theSpawner.baseName = cfxZones.getStringFromZoneProperty(inZone, "baseName", dcsCommon.uuid("objSpwn"))
	--cfxZones.getZoneProperty(inZone, "baseName")
	theSpawner.cooldown = cfxZones.getNumberFromZoneProperty(inZone, "cooldown", 60)
	theSpawner.lastSpawnTimeStamp = -10000 -- just init so it will always work
	theSpawner.autoRemove = cfxZones.getBoolFromZoneProperty(inZone, "autoRemove", false)
	theSpawner.autoLink = cfxZones.getBoolFromZoneProperty(inZone, "autoLink", true)

	theSpawner.heading = cfxZones.getNumberFromZoneProperty(inZone, "heading", 0)
	theSpawner.weight = cfxZones.getNumberFromZoneProperty(inZone, "weight", 0)
	if theSpawner.weight < 0 then theSpawner.weight = 0 end 
	
	theSpawner.isCargo = cfxZones.getBoolFromZoneProperty(inZone, "isCargo", false)
	if theSpawner.isCargo == true and theSpawner.weight < 100 then theSpawner.weight = 100 end 
	theSpawner.managed = cfxZones.getBoolFromZoneProperty(inZone, "managed", true) -- defaults to managed cargo
	
	theSpawner.cdTimer = 0 -- used for cooldown. if timer.getTime < this value, don't spawn
	-- theSpawner.cdStarted = false -- used to initiate cooldown when all items in theSpawns disappear
	theSpawner.count = 1 -- used to create names, and count how many groups created
	theSpawner.theSpawns = {} -- all items that are spawned. re-spawn happens if they are all out
	theSpawner.maxSpawns = cfxZones.getNumberFromZoneProperty(inZone, "maxSpawns", 1)
	theSpawner.paused = cfxZones.getBoolFromZoneProperty(inZone, "paused", false)
	theSpawner.requestable = cfxZones.getBoolFromZoneProperty(inZone, "requestable", false)
	if theSpawner.requestable then theSpawner.paused = true end
	
	-- see if it is linked to a ship to set realtive orig headiong
	
	if inZone.linkedUnit  then
		local shipUnit = inZone.linkedUnit
		theSpawner.linkedUnit = shipUnit
		
		local origHeading = dcsCommon.getUnitHeadingDegrees(shipUnit)
		
		-- calculate initial delta 
		local delta = dcsCommon.vSub(inZone.point,shipUnit:getPoint()) -- delta = B - A 
		theSpawner.dx = delta.x 
		theSpawner.dy = delta.z
		
		theSpawner.origHeading = origHeading
	end
	return theSpawner
end

function cfxObjectSpawnZones.addSpawner(aSpawner)
	cfxObjectSpawnZones.allSpawners[aSpawner.zone] = aSpawner
end

function cfxObjectSpawnZones.removeSpawner(aSpawner)
	cfxObjectSpawnZones.allSpawners[aSpawner.zone] = nil
end

function cfxObjectSpawnZones.getSpawnerForZone(aZone)
	return cfxObjectSpawnZones.allSpawners[aZone]
end

function cfxObjectSpawnZones.getSpawnerForZoneNamed(aName)
	local aZone = cfxZones.getZoneByName(aName) 
	return cfxObjectSpawnZones.getSpawnerForZone(aZone)
end


function cfxObjectSpawnZones.getRequestableSpawnersInRange(aPoint, aRange, aSide)
	-- trigger.action.outText("enter requestable spawners for side " .. aSide , 30)
	if not aSide then aSide = 0 end 
-- currently, WE FORCE A  SIDE MATCH
	aSide = 0
	
	if not aRange then aRange = 200 end 
	if not aPoint then return {} end 

	local theSpawners = {}
	for aZone, aSpawner in pairs(cfxObjectSpawnZones.allSpawners) do 
		-- iterate all zones and collect those that match 
		local hasMatch = true 
		-- update the zone's point if it is linked to a ship, i.e. 
		local delta = dcsCommon.dist(aPoint, cfxZones.getPoint(aZone))
		if delta>aRange then hasMatch = false end 
		if aSide ~= 0 then 

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

function cfxObjectSpawnZones.verifySpawnOwnership(spawner)
	return true
end

function cfxObjectSpawnZones.spawnObjectNTimes(aSpawner, theType, n, container) 
	if not aSpawner then return end
	if not container then container = {} end 
	if not n then n = 1 end
	if not theType then return end 
	local aZone = aSpawner.zone 
	if not aZone then return end 
	if n < 1 then return end 

	local center = cfxZones.getPoint(aZone) -- magically works with moving zones and offset 
	
	if n == 1 then 
		-- spawn in the middle, only a single object
		local ox = center.x
		local oy = center.z
		local theStaticData = dcsCommon.createStaticObjectData(
			aSpawner.baseName .. "-" .. aSpawner.count, 
			theType,
			aSpawner.heading,
			false, -- dead?
			aSpawner.isCargo,
			aSpawner.weight)
		aSpawner.count = aSpawner.count + 1
		
		-- more to global position
		dcsCommon.moveStaticDataTo(theStaticData, ox, oy)
		
		-- if linked, relative-link instead to ship 
		-- NOTE: it is possible that we have to re-calc heading
		-- if ship turns relative to original designation position.
		if aZone.linkedUnit and aZone.autoLink then
			dcsCommon.linkStaticDataToUnit(
				theStaticData, 
				aZone.linkedUnit, 
				aSpawner.dx, 
				aSpawner.dy, 
				aSpawner.origHeading)
		end 
		
		-- spawn in dcs
		local theObject = coalition.addStaticObject(aSpawner.rawOwner, theStaticData) -- create in dcs
		table.insert(container, theObject) -- add to collection
		if aSpawner.isCargo and aSpawner.managed then 
			if cfxCargoManager then 
				cfxCargoManager.addCargo(theObject)
			end
		end
		
		return 
	end 
	
	local numObjects = n 
	local degrees = 3.14157 / 180
	local degreeIncrement = (360 / numObjects) * degrees
	local currDegree = 0
	local missionObjects = {}
	for i=1, numObjects do 
		local rx = math.cos(currDegree) * aZone.radius
		local ry = math.sin(currDegree) * aZone.radius
		local ox = center.x + rx 
		local oy = center.z + ry -- note: z!
		
		local theStaticData = dcsCommon.createStaticObjectData(
			aSpawner.baseName .. "-" .. aSpawner.count, 
			theType,
			aSpawner.heading,
			false, -- dead?
			aSpawner.isCargo,
			aSpawner.weight)

		theStaticData.canCargo = aSpawner.isCargo -- should be false, but you never know
		if theStaticData.canCargo then 
--			theStaticData.mass = aSpawner.weight
			trigger.action.outText("+++ obSpw is cargo with w=" .. theStaticData.mass .. " for " .. theStaticData.name, 30)
		end
		
		aSpawner.count = aSpawner.count + 1
		dcsCommon.moveStaticDataTo(theStaticData, ox, oy)

		if aZone.linkedUnit and aZone.autoLink then
			dcsCommon.linkStaticDataToUnit(theStaticData, aZone.linkedUnit, aSpawner.dx + rx, aSpawner.dy + ry, aSpawner.origHeading)
		end
		
		-- spawn in dcs
		local theObject = coalition.addStaticObject(aSpawner.rawOwner, theStaticData) -- this will generate an event!
		table.insert(container, theObject)
		-- see if it is managed cargo 
		if aSpawner.isCargo and aSpawner.managed then 
			if cfxCargoManager then 
				cfxCargoManager.addCargo(theObject)
			end
		end
		-- update rotation
		currDegree = currDegree + degreeIncrement
	end
end

function cfxObjectSpawnZones.spawnWithSpawner(aSpawner)
	
	if type(aSpawner) == "string" then -- return spawner for zone of that name
		aSpawner = cfxObjectSpawnZones.getSpawnerForZoneNamed(aName)
	end
	if not aSpawner then return end 
	
	-- will NOT check if conditions are met. This forces a spawn
	local unitTypes = {} -- build type names
	local p = cfxZones.getPoint(aSpawner.zone) -- aSpawner.zone.point  
		
	-- split the conf.troopsOnBoardTypes into an array of types
	unitTypes = dcsCommon.splitString(aSpawner.types, ",")
	if #unitTypes < 1 then 
		table.insert(unitTypes, "White_Flag") -- make it one m4 trooper as fallback
	end
	
	-- now iterate through all types and create objects for each name
	-- overlaying them all n times 
	aSpawner.theSpawns = {} -- forget whatever there was before.
	for idx, typeName in pairs(unitTypes) do
		 cfxObjectSpawnZones.spawnObjectNTimes(
				aSpawner, 
				typeName, 
				aSpawner.numObj, 
				aSpawner.theSpawns)
	end
	
	-- reset cooldown (forced) 
	if true then -- or not spawner.cdStarted then -- forced on 
		-- no, start cooldown
		--spawner.cdStarted = true 
		aSpawner.cdTimer = timer.getTime() + aSpawner.cooldown
	end
	
	-- callback to all who want to know 
	cfxObjectSpawnZones.invokeCallbacksFor("spawned", aSpawner.theSpawns, aSpawner)
	
	-- timestamp so we can check against cooldown on manual spawn
	aSpawner.lastSpawnTimeStamp = timer.getTime()
	-- make sure a requestable spawner is always paused 
	if aSpawner.requestable then 
		aSpawner.paused = true 
	end
	
	if aSpawner.autoRemove then 
		-- simply remove the group 
		aSpawner.theSpawns = {} -- empty group -- forget all
	end
end

function cfxObjectSpawnZones.despawnRemaining(spawner) 
	for idx, anObject in pairs (spawner.theSpawns) do
		if anObject and anObject:isExist() then 
			anObject:destroy()
		end		
	end
end

--
-- U P D A T E 
--
function cfxObjectSpawnZones.needsSpawning(spawner)
		if spawner.paused then return false end 
		if spawner.requestable then return false end 
		if spawner.maxSpawns == 0 then return false end 
		if #spawner.theSpawns > 0 then return false end 
		if timer.getTime() < spawner.cdTimer then return false end 
		
		return cfxObjectSpawnZones.verifySpawnOwnership(spawner)
end

function cfxObjectSpawnZones.update()
	cfxObjectSpawnZones.updateSchedule = timer.scheduleFunction(cfxObjectSpawnZones.update, {}, timer.getTime() + 1/cfxObjectSpawnZones.ups)
	
	for key, spawner in pairs (cfxObjectSpawnZones.allSpawners) do 
		-- see if the spawn is dead or was removed
		-- forget all dead spawns
		local objectsToKeep = {}
--		if not spawner.requestable then 
		for idx, anObject in pairs (spawner.theSpawns) do 
			if not anObject:isExist() then
				--trigger.action.outText("+++ obSpwn: INEXIST removing object in zone " .. spawner.zone.name, 30)
			elseif anObject:getLife() < 1 then 
				--trigger.action.outText("+++ obSpwn: dead. removing object ".. anObject:getName() .." in zone " .. spawner.zone.name, 30)
			else 
				table.insert(objectsToKeep, anObject)			
			end
		end
--		end
		
		-- see if we killed off all objects and start cd if so
		if #objectsToKeep == 0 and #spawner.theSpawns > 0 then 
			spawner.cdTimer = timer.getTime() + spawner.cooldown
		end
		-- transfer kept items 
		spawner.theSpawns = objectsToKeep 
		
		local needsSpawn = cfxObjectSpawnZones.needsSpawning(spawner)
		-- check if perhaps our watchtrigger causes spawn
		if spawner.pauseFlag then 
			local currTriggerVal = cfxZones.getFlagValue(spawner.pauseFlag, spawner)-- trigger.misc.getUserFlag(spawner.pauseFlag)
			if currTriggerVal ~= spawner.lastPauseValue then
				spawner.paused = true  
				needsSpawn = false 
				spawner.lastPauseValue = currTriggerVal
			end
		end
		
		if spawner.triggerFlag then 
			local currTriggerVal = cfxZones.getFlagValue(spawner.triggerFlag, spawner)-- trigger.misc.getUserFlag(spawner.triggerFlag)
			if currTriggerVal ~= spawner.lastTriggerValue then
				needsSpawn = true 
				spawner.lastTriggerValue = currTriggerVal
			end
		end		
		
		if spawner.activateFlag then 
			local currTriggerVal = spawner.getFlagValue(spawner.activateFlag, spawner) -- trigger.misc.getUserFlag(spawner.activateFlag)
			if currTriggerVal ~= spawner.lastActivateValue then
				spawner.paused = false  
				spawner.lastActivateValue = currTriggerVal
			end
		end

		
		
		
		if needsSpawn then 
			cfxObjectSpawnZones.spawnWithSpawner(spawner)
			if spawner.maxSpawns > 0 then 
				spawner.maxSpawns = spawner.maxSpawns - 1
			end
			if spawner.maxSpawns == 0 then 
				spawner.paused = true 

			end
		else 
			-- trigger.action.outText("+++ NOSPAWN for zone " .. spawner.zone.name, 30)
		end
	end
end

function cfxObjectSpawnZones.start()
	if not dcsCommon.libCheck("cfx Object Spawn Zones", 
		cfxObjectSpawnZones.requiredLibs) then
		return false 
	end
	
	-- collect all spawn zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("objectSpawner")
	
	-- now create a spawner for all, add them to the spawner updater, and spawn for all zones that are not
	-- paused 
	for k, aZone in pairs(attrZones) do 
		local aSpawner = cfxObjectSpawnZones.createSpawner(aZone)
		cfxObjectSpawnZones.addSpawner(aSpawner)
		if (not aSpawner.paused) and 
		   cfxObjectSpawnZones.verifySpawnOwnership(aSpawner) and
		   aSpawner.maxSpawns ~= 0 
		then 
			cfxObjectSpawnZones.spawnWithSpawner(aSpawner)
			-- update spawn count and make sure we haven't spawned the one and only 
			if aSpawner.maxSpawns > 0 then 
				aSpawner.maxSpawns = aSpawner.maxSpawns - 1
			end
			if aSpawner.maxSpawns == 0 then 
				aSpawner.paused = true 
				--trigger.action.outText("+++ maxspawn -- turning off  zone " .. aSpawner.zone.name, 30)
			end
		end
	end
	
	-- and start the regular update calls
	cfxObjectSpawnZones.update()
	
	trigger.action.outText("cfx Object Spawn Zones v" .. cfxObjectSpawnZones.version .. " started.", 30)
	return true
end

if not cfxObjectSpawnZones.start() then 
	trigger.action.outText("cf/x Spawn Zones aborted: missing libraries", 30)
	cfxObjectSpawnZones = nil 
end

