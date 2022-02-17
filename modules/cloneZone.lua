cloneZones = {}
cloneZones.version = "1.1.1"
cloneZones.verbose = false  
cloneZones.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"cfxMX", 
}
cloneZones.cloners = {}

--[[--
	Clones Groups from ME mission data
	Copyright (c) 2022 by Christian Franz and cf/x AG
	
	Version History
	1.0.0 - initial version 
	1.0.1 - preWipe attribute
	1.1.0 - support for static objects
	      - despawn? attribute 
	1.1.1 - despawnAll: isExist guard 
	
--]]--

--
-- adding / removing from list 
--
function cloneZones.addCloneZone(theZone)
	table.insert(cloneZones.cloners, theZone)
end

function cloneZones.getCloneZoneByName(aName) 
	for idx, aZone in pairs(cloneZones.cloners) do 
		if aName == aZone.name then return aZone end 
	end
	if cloneZones.verbose then 
		trigger.action.outText("+++clnZ: no clone with name <" .. aName ..">", 30)
	end 
	
	return nil 
end
--
-- reading zones
--


function cloneZones.createClonerWithZone(theZone) -- has "Cloner"
	local localZones = cfxZones.allGroupsInZone(theZone)
	local localObjects = cfxZones.allStaticsInZone(theZone)
	theZone.cloner = true -- this is a cloner zoner 
	theZone.mySpawns = {}
	theZone.myStatics = {}
	--theZone.groupVectors = {}
	theZone.origin = cfxZones.getPoint(theZone) -- save reference point for all groupVectors 
	
	-- source tells us which template to use. it can be the following:
	-- nothing (no attribute) - then we use whatever groups are in zone to 
	-- spawn as template 
	-- name of another spawner that provides the template 
	-- we can't simply use a group name as we lack the reference 
	-- location for delta 
	if cfxZones.hasProperty(theZone, "source") then 
		theZone.source = cfxZones.getStringFromZoneProperty(theZone, "source", "<none>")
		if theZone.source == "<none>" then theZone.source = nil end 
	end 
	
	if not theZone.source then 
		theZone.cloneNames = {} -- names of the groups. only present in template spawners
		theZone.staticNames = {} -- names of all statics. only present in templates
		
		for idx, aGroup in pairs(localZones) do
			local gName = aGroup:getName()
			if gName then 
				table.insert(theZone.cloneNames, gName)
				table.insert(theZone.mySpawns, aGroup) -- collect them for initial despawn
			end 	
		end
		for idx, aStatic in pairs (localObjects) do 
			local sName = aStatic:getName()
			if sName then 
				table.insert(theZone.staticNames, sName)
				table.insert(theZone.myStatics, aStatic)
			end
		end
		
		cloneZones.despawnAll(theZone) 
		if (#theZone.cloneNames + #theZone.staticNames)	< 1 then 
			if cloneZones.verbose then 
				trigger.action.outText("+++clnZ: WARNING - Template in clone zone <" .. theZone.name .. "> is empty", 30)
			end 
			theZone.cloneNames = nil
			theZone.staticNames = nil 
		end
		if cloneZones.verbose then 
			trigger.action.outText(theZone.name .. " clone template saved", 30)
		end
	end
	
	-- f? and spawn? map to the same 
	if cfxZones.hasProperty(theZone, "f?") then 
		theZone.spawnFlag = cfxZones.getStringFromZoneProperty(theZone, "f?", "none")
		theZone.lastSpawnValue = trigger.misc.getUserFlag(theZone.spawnFlag) -- save last value
	end
	
	if cfxZones.hasProperty(theZone, "in?") then 
		theZone.spawnFlag = cfxZones.getStringFromZoneProperty(theZone, "in?", "none")
		theZone.lastSpawnValue = trigger.misc.getUserFlag(theZone.spawnFlag) -- save last value
	end
	
	if cfxZones.hasProperty(theZone, "spawn?") then 
		theZone.spawnFlag = cfxZones.getStringFromZoneProperty(theZone, "spawn?", "none")
		theZone.lastSpawnValue = trigger.misc.getUserFlag(theZone.spawnFlag) -- save last value
	end
	
	-- deSpawn?
	if cfxZones.hasProperty(theZone, "deSpawn?") then 
		theZone.deSpawnFlag = cfxZones.getStringFromZoneProperty(theZone, "deSpawn?", "none")
		theZone.lastDeSpawnValue = trigger.misc.getUserFlag(theZone.deSpawnFlag) -- save last value
	end
	
	theZone.onStart = cfxZones.getBoolFromZoneProperty(theZone, "onStart", false)
	
	theZone.moveRoute = cfxZones.getBoolFromZoneProperty(theZone, "moveRoute", false)
	
	theZone.preWipe = cfxZones.getBoolFromZoneProperty(theZone, "preWipe", false)
	
	if cfxZones.hasProperty(theZone, "empty+1") then 
		theZone.emptyFlag = cfxZones.getNumberFromZoneProperty(theZone, "empty+1", "<None>") -- note string on number default
	end
	
	if cfxZones.hasProperty(theZone, "masterOwner") then 
		theZone.masterOwner = cfxZones.getStringFromZoneProperty(theZone, "masterOwner", "<none>")
	end
	
	--cloneZones.spawnWithCloner(theZone)
	theZone.turn = cfxZones.getNumberFromZoneProperty(theZone, "turn", 0)
	
	-- make sure we spawn at least once 
	-- bad idea, since we may want to simply create a template
	-- if not theZone.spawnFlag then theZone.onStart = true end 
end

-- 
-- spawning, despawning
--

function cloneZones.despawnAll(theZone) 
	if cloneZones.verbose then 
		trigger.action.outText("wiping <" .. theZone.name .. ">", 30)
	end 
	for idx, aGroup in pairs(theZone.mySpawns) do 
		if aGroup:isExist() then 
			Group.destroy(aGroup)
		end 
	end
	for idx, aStatic in pairs(theZone.myStatics) do 
		-- warning! may be mismatch because we are looking at groups
		-- not objects. let's see
		if aStatic:isExist() then 
			trigger.action.outText("Destroying static <" .. aStatic:getName() .. ">", 30)
			Object.destroy(aStatic) -- we don't aStatio:destroy() to find out what it is
		end 
	end
	theZone.mySpawns = {}
	theZone.myStatics = {}
end

function cloneZones.updateLocationsInGroupData(theData, zoneDelta, adjustAllWaypoints)
	--trigger.action.outText("Update loc - zone delta: [" .. zoneDelta.x .. "," .. zoneDelta.z .. "]", 30)
	-- remember that zoneDelta's [z] modifies theData's y!!
	theData.x = theData.x + zoneDelta.x 
	theData.y = theData.y + zoneDelta.z -- !!!
	local units = theData.units 
	for idx, aUnit in pairs(units) do 
		aUnit.x = aUnit.x + zoneDelta.x 
		aUnit.y = aUnit.y + zoneDelta.z -- again!!!!
	end
	-- now modifiy waypoints. we ALWAYS adjust the  
	-- first waypoint, but only all others if asked 
	-- to 
	local theRoute = theData.route 
	-- TODO: vehicles can have 'spans' - may need to program for 
	-- those as well. we currently only go for points 
	if theRoute then 
		local thePoints = theRoute.points 
		if thePoints and #thePoints > 0 then 
			if adjustAllWaypoints then  
				for i=1, #thePoints do 
					thePoints[i].x = thePoints[i].x + zoneDelta.x 
					thePoints[i].y = thePoints[i].y + zoneDelta.z -- (!!)

				end
			else 
				-- only first point 
				thePoints[1].x = thePoints[1].x + zoneDelta.x 
				thePoints[1].y = thePoints[1].y + zoneDelta.z -- (!!)
			end 
			
			-- if there is an airodrome id given in first waypoint, 
			-- adjust for closest location 
			local firstPoint = thePoints[1]
			if firstPoint.airdromeId then 
				trigger.action.outText("first: airdrome adjust for " .. theData.name .. " now is " .. firstPoint.airdromeId, 30)
				local loc = {}
				loc.x = firstPoint.x
				loc.y = 0
				loc.z = firstPoint.y 
				local bestAirbase = dcsCommon.getClosestAirbaseTo(loc)
				firstPoint.airdromeId = bestAirbase:getID()
				trigger.action.outText("first: adjusted to " .. firstPoint.airdromeId, 30)
			end
			
			-- adjust last point (landing)
			if #thePoints > 1 then 
				local lastPoint = thePoints[#thePoints]
				if firstPoint.airdromeId then 
					trigger.action.outText("last: airdrome adjust for " .. theData.name .. " now is " .. lastPoint.airdromeId, 30)
					local loc = {}
					loc.x = lastPoint.x
					loc.y = 0
					loc.z = lastPoint.y 
					local bestAirbase = dcsCommon.getClosestAirbaseTo(loc)
					lastPoint.airdromeId = bestAirbase:getID()
					trigger.action.outText("last: adjusted to " .. lastPoint.airdromeId, 30)
				end
			
			end
		end
	end
end

function cloneZones.uniqueNameGroupData(theData) 
	theData.name = dcsCommon.uuid(theData.name)
	local units = theData.units 
	for idx, aUnit in pairs(units) do 
		aUnit.name = dcsCommon.uuid(aUnit.name)
	end 
end 


function cloneZones.resolveOwnership(spawnZone, ctry)
	if not spawnZone.masterOwner then return ctry end 

	local masterZone = cfxZones.getZoneByName(spawnZone.masterOwner)
	if not masterZone then 
		trigger.action.outText("+++clnZ: cloner " .. spawnZone.name .. " could not fine master owner <" .. spawnZone.masterOwner .. ">", 30)
		return ctry 
	end
	
	if not masterZone.owner then 
		return ctry 
	end
	
	ctry = dcsCommon.getACountryForCoalition(masterZone.owner)
	return ctry 
end

function cloneZones.spawnWithTemplateForZone(theZone, spawnZone)
	--trigger.action.outText("ENTER: Spawn with template " .. theZone.name .. " for spawnZone " .. spawnZone.name, 30)
	-- theZone is the zoner with the template
	-- spawnZone is the spawner with settings 
	--if not spawnZone then spawnZone = theZone end 
	local newCenter = cfxZones.getPoint(spawnZone) 
	-- calculate zoneDelta, is added to all vectors 
	local zoneDelta = dcsCommon.vSub(newCenter, theZone.origin)
	
	local spawnedGroups = {}
	local spawnedStatics = {}
	
	for idx, aGroupName in pairs(theZone.cloneNames) do 
		local rawData, cat, ctry = cfxMX.getGroupFromDCSbyName(aGroupName)

		if rawData.name == aGroupName then 
		else 
			trigger.action.outText("Clone: FAILED name check", 30)
		end
		
		-- now use raw data to spawn and see if it works outabox
		local theCat = cfxMX.catText2ID(cat)
		
		-- update their position if not spawning to exact same location 
		cloneZones.updateLocationsInGroupData(rawData, zoneDelta, spawnZone.moveRoute)
		
		-- apply turning 
		dcsCommon.rotateGroupData(rawData, spawnZone.turn, newCenter.x, newCenter.z)
		
		-- make sure unit and group names are unique 
		cloneZones.uniqueNameGroupData(rawData)
		
		-- see waht country we spawn for
		ctry = cloneZones.resolveOwnership(spawnZone, ctry)
		
		local theGroup = coalition.addGroup(ctry, theCat, rawData)
		table.insert(spawnedGroups, theGroup)
	end

	-- static spawns 
	for idx, aStaticName in pairs(theZone.staticNames) do 
		local rawData, cat, ctry, parent = cfxMX.getStaticFromDCSbyName(aStaticName)
		
		if not rawData then
			trigger.action.outText("Static Clone: no such group <"..aStaticName .. ">", 30)
			
		elseif rawData.name == aStaticName then 
			trigger.action.outText("Static Clone: suxess!!! <".. aStaticName ..">", 30)

		else 
			trigger.action.outText("Static Clone: FAILED name check for <" .. aStaticName .. ">", 30)
		end
		
		-- now use raw data to spawn and see if it works outabox
		local theCat = cfxMX.catText2ID(cat) -- will be "static"
		
		-- move origin 
		rawData.x = rawData.x + zoneDelta.x 
		rawData.y = rawData.y + zoneDelta.z -- !!!
	
		-- apply turning 
		dcsCommon.rotateUnitData(rawData, spawnZone.turn, newCenter.x, newCenter.z)
		
		-- make sure static name is unique 
--		cloneZones.uniqueNameGroupData(rawData)
		rawData.name = dcsCommon.uuid(rawData.name)
		rawData.unitID = nil -- simply forget, will be newly issued 
		
		-- see waht country we spawn for
		ctry = cloneZones.resolveOwnership(spawnZone, ctry)
		
		local theStatic = coalition.addStaticObject(ctry, rawData)
		table.insert(spawnedStatics, theStatic)
		--]]--
		trigger.action.outText("Static spawn: spawned " .. aStaticName, 30)
	end	

	return spawnedGroups, spawnedStatics 
end

function cloneZones.spawnWithCloner(theZone) 
	if not theZone then 
		trigger.action.outText("+++clnZ: nil zone on spawnWithCloner", 30)
		return 
	end
	if not theZone.cloner then 
		trigger.action.outText("+++clnZ: spawnWithCloner invoked with non-cloner <" .. theZone.name .. ">", 30)
		return 
	end 
	
	-- force spawn with this spawner 
	local templateZone = theZone
	if theZone.source then 
		-- we use a different zone for templates
		-- souce can be a comma separated list
		local templateName = theZone.source
		if dcsCommon.containsString(templateName, ",") then 
			local allNames = templateName 
			local templates = dcsCommon.splitString(templateName, ",")
			templateName = dcsCommon.pickRandom(templates)
			templateName = dcsCommon.trim(templateName) 
			if cloneZones.verbose then 
				trigger.action.outText("+++clnZ: picked random template <" .. templateName .."> for from <" .. allNames .. "> for cloner " .. theZone.name, 30)
			end 
		end
		
		local newTemplate = cloneZones.getCloneZoneByName(templateName)
		if not newTemplate then 
			if cloneZones.verbose then 
				trigger.action.outText("+++clnZ: no clone source with name <" .. templateName .."> for cloner " .. theZone.name, 30)
			end  
			return 
		end
		templateZone = newTemplate 
	end
	
	-- make sure our template is filled 
	if not templateZone.cloneNames then 
		if cloneZones.verbose then 
			trigger.action.outText("+++clnZ: clone source template <".. templateZone.name .. "> for clone zone <" .. theZone.name .."> is empty", 30)
		end 
		return 
	end

	-- pre-Wipe?
	if theZone.preWipe then 
		cloneZones.despawnAll(theZone)
	end
	

	local theClones, theStatics = cloneZones.spawnWithTemplateForZone(templateZone, theZone)
	-- reset hasClones so we know our spawns are full and we can 
	-- detect complete destruction
	if (theClones and #theClones > 0) or 
	   (theStatics and #theStatics > 0)
	then 
		theZone.hasClones = true 
		theZone.mySpawns = theClones 
		theZone.myStatics = theStatics 
	else 
		theZone.hasClones = false 
		theZone.mySpawns = {}
		theZone.myStatics = {}
	end
end

function cloneZones.countLiveUnits(theZone)
	if not theZone then return 0 end 
	local count = 0
	-- count units 
	if theZone.mySpawns then 
		for idx, aGroup in pairs(theZone.mySpawns) do 
			if aGroup:isExist() then 
				local allUnits = aGroup:getUnits()
				for idy, aUnit in pairs(allUnits) do 
					if aUnit:isExist() and aUnit:getLife() >= 1 then 
						count = count + 1
					end
				end
			end
		end
	end
	
	-- count statics 
	if theZone.myStatics then 
		for idx, aStatic in pairs(theZone.myStatics) do 
			if aStatic:isExist() and aStatic:getLife() >= 1 then 
				count = count + 1
			end
		end
	end
	return count 
end

function cloneZones.hasLiveUnits(theZone)
	if not theZone then return 0 end 
	if theZone.mySpawns then 
		for idx, aGroup in pairs(theZone.mySpawns) do 
			if aGroup:isExist() then 
				local allUnits = aGroup:getUnits()
				for idy, aUnit in pairs(allUnits) do 
					if aUnit:isExist() and aUnit:getLife() >= 1 then 
						return true
					end
				end
			end
		end
	end 
	
	if theZone.myStatics then 
		for idx, aStatic in pairs(theZone.myStatics) do 
			if aStatic:isExist() and aStatic.getLife() >= 1 then 
				return true 
			end 
		end
	end
	
	return false
end

function cloneZones.pollFlag(flagNum, method)
	-- we currently ignore method 
	local num = trigger.misc.getUserFlag(flagNum)
	trigger.action.setUserFlag(flagNum, num+1)
end
--
-- UPDATE
--
function cloneZones.update()
	timer.scheduleFunction(cloneZones.update, {}, timer.getTime() + 1)
	
	for idx, aZone in pairs(cloneZones.cloners) do
		-- see if deSpawn was pulled. Must run before spawn
		if aZone.deSpawnFlag then 
			local currTriggerVal = trigger.misc.getUserFlag(aZone.deSpawnFlag)
			if currTriggerVal ~= aZone.lastDeSpawnValue then 
				if cloneZones.verbose then 
					trigger.action.outText("+++clnZ: DEspawn triggered for <" .. aZone.name .. ">", 30)
				end 
				cloneZones.despawnAll(aZone)
				aZone.lastDeSpawnValue = currTriggerVal
			end
		end
		
		-- see if we got spawn? command
		if aZone.spawnFlag then 
			local currTriggerVal = trigger.misc.getUserFlag(aZone.spawnFlag)
			if currTriggerVal ~= aZone.lastSpawnValue
			then 
				if cloneZones.verbose then 
					trigger.action.outText("+++clnZ: spawn triggered for <" .. aZone.name .. ">", 30)
				end 
				cloneZones.spawnWithCloner(aZone)
				aZone.lastSpawnValue = currTriggerVal
			end
		end
		
		-- see if we are empty and should signal
		if aZone.emptyFlag and aZone.hasClones then 
			if cloneZones.countLiveUnits(aZone) < 1 then 
				-- we are depleted. poll flag once, then remember we have 
				-- polled 
				cloneZones.pollFlag(aZone.emptyFlag)
				aZone.hasClones = false 
			end
		end
		
		
	end
end

function cloneZones.onStart()
	--trigger.action.outText("+++clnZ: Enter atStart", 30)
	for idx, theZone in pairs(cloneZones.cloners) do 
		if theZone.onStart then 
			if cloneZones.verbose then 
				trigger.action.outText("+++clnZ: atStart will spawn for <"..theZone.name .. ">", 30)
			end
			cloneZones.spawnWithCloner(theZone) 
			
		end 
	end
end

--
-- START 
--
function cloneZones.readConfigZone()
	local theZone = cfxZones.getZoneByName("cloneZonesConfig") 
	if not theZone then 
		if cloneZones.verbose then 
			trigger.action.outText("+++clnZ: NO config zone!", 30)
		end 
		return 
	end 
	
	cloneZones.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if cloneZones.verbose then 
		trigger.action.outText("+++clnZ: read config", 30)
	end 
end

function cloneZones.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Clone Zones requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Clone Zones", 
		cloneZones.requiredLibs) then
		return false 
	end
	
	-- read config 
	cloneZones.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("cloner")
	
	-- now create an rnd gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		cloneZones.createClonerWithZone(aZone) -- process attribute and add to zone
		cloneZones.addCloneZone(aZone) -- remember it so we can smoke it
	end
	
	-- run through onStart 
	cloneZones.onStart() 
	
	-- start update 
	cloneZones.update()
	
	trigger.action.outText("cfx Clone Zones v" .. cloneZones.version .. " started.", 30)
	return true 
end

-- let's go!
if not cloneZones.start() then 
	trigger.action.outText("cf/x Clone Zones aborted: missing libraries", 30)
	cloneZones = nil 
end