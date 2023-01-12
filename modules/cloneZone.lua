cloneZones = {}
cloneZones.version = "1.7.0"
cloneZones.verbose = false  
cloneZones.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"cfxMX", 
}
cloneZones.minSep = 10 -- minimal separation for onRoad auto-pos
cloneZones.maxIter = 100 -- maximum number of attempts to resolve 
						-- a too-close separation 
						
-- groupTracker is OPTIONAL! and required only with trackWith attribute

cloneZones.cloners = {}
cloneZones.callbacks = {}
cloneZones.unitXlate = {}
cloneZones.groupXlate = {} -- used to translate original groupID to cloned. only holds last spawned group id 
cloneZones.uniqueCounter = 9200000 -- we start group numbering here 
cloneZones.lclUniqueCounter = 1 -- zone-local init value, can be config'dHeading
cloneZones.globalCounter = 1 -- module-global count 

cloneZones.allClones = {} -- all clones spawned, regularly GC'd 
cloneZones.allCObjects = {} -- all clones objects

cloneZones.respawnOnGroupID = true 

--[[--
	Clones Groups from ME mission data
	Copyright (c) 2022 by Christian Franz and cf/x AG
	
	Version History
	1.0.0 - initial version 
	1.0.1 - preWipe attribute
	1.1.0 - support for static objects
		  - despawn? attribute 
	1.1.1 - despawnAll: isExist guard 
		  - map in? to f? 
	1.2.0 - Lua API integration: callbacks 
		  - groupXlate struct
		  - unitXlate struct 
		  - resolveReferences 
		  - getGroupsInZone rewritten for data 
		  - static resolve 
		  - linkUnit resolve 
		  - clone? synonym
		  - empty! and method attributes
	1.3.0 - DML flag upgrade 
	1.3.1 - groupTracker interface 
		  - trackWith: attribute
	1.4.0 - Watchflags 
	1.4.1 - trackWith: accepts list of trackers 
	1.4.2 - onstart delays for 0.1 s to prevent static stacking
		  - turn bug for statics (bug in dcsCommon, resolved)
	1.4.3 - embark/disembark now works with cloners 
	1.4.4 - removed some debugging verbosity 
	1.4.5 - randomizeLoc, rndLoc keyword
		  - cargo manager integration - pass cargo objects when present
	1.4.6 - removed some verbosity for spawned aircraft with airfields on their routes
	1.4.7 - DML watchflag and DML Flag polish, method-->cloneMethod
	1.4.8 - added 'wipe?' synonym 
	1.4.9 - onRoad option 
	      - rndHeading option 
	1.5.0 - persistence 
	1.5.1 - fixed static data cloning bug (load & save)
	1.5.2 - fixed bug in trackWith: referencing wrong cloner 
	1.5.3 - centerOnly/wholeGroups attribute for rndLoc, rndHeading and onRoad
	1.5.4 - parking for aircraft processing when cloning from template 
	1.5.5 - removed some verbosity 
	1.6.0 - fixed issues with cloning for zones with linked units
		  - cloning with useHeading 
		  - major declutter 
	1.6.1 - removed some verbosity when not rotating routes
		  - updateTaskLocations ()
		  - cloning groups now also adjusts tasks like search and engage in zone
		  - cloning with rndLoc supports polygons
		  - corrected rndLoc without centerOnly to not include individual offsets
		  - ensure support of recovery tanker resolve cloned group 
	1.6.2 - optimization to hasLiveUnits()
	1.6.3 - removed verbosity bug with rndLoc 
	        uniqueNameGroupData has provisions for naming scheme 
			new uniqueNameStaticData() for naming scheme
	1.6.4 - uniqueCounter is now configurable via config zone 
			new lclUniqueCounter config, also added to persistence 
			new globalCount
	1.7.0 - wildcard "*" for masterOwner 
		  - identical attribute: makes identical ID and name for unit and group as template
		  - new sameIDUnitData()
		  - nameScheme attribute: allow parametric names  
		  - <o>, <z>, <s> wildcards
		  - <uid>, <lcl>, <i>, <g> wildcards 
		  - identical=true overrides nameScheme
		  - masterOwner "*" convenience shortcut
	
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
-- callbacks 
--

function cloneZones.addCallback(theCallback)
	if not theCallback then return end 
	table.insert(cloneZones.callbacks, theCallback)
end

-- reasons for callback 
-- "will despawn group" - args is the group about to be despawned
-- "did spawn group" -- args is group that was spawned
-- "will despawn static"
-- "did spawn static"
-- "spawned" -- completed spawn cycle. args contains .groups and .statics spawned 
-- "empty" -- all spawns have been killed, args is empty 
-- "wiped" -- preWipe executed 
-- "<none" -- something went wrong 

function cloneZones.invokeCallbacks(theZone, reason, args)
	if not theZone then return end 
	if not reason then reason = "<none>" end 
	if not args then args = {} end 
	
	-- invoke anyone who wants to know that a group 
	-- of people was rescued.
	for idx, cb in pairs(cloneZones.callbacks) do 
		cb(theZone, reason, args)
	end
end

-- group translation orig id 

--
-- reading zones
--
function cloneZones.partOfGroupDataInZone(theZone, theUnits)
	local zP = cfxZones.getPoint(theZone)
	zP = cfxZones.getDCSOrigin(theZone) -- don't use getPoint now.
	zP.y = 0
	
	for idx, aUnit in pairs(theUnits) do 
		local uP = {}
		uP.x = aUnit.x 
		uP.y = 0
		uP.z = aUnit.y -- !! y-z
		local dist = dcsCommon.dist(uP, zP)
		if dist <= theZone.radius then return true  end 
	end 
	return false 
end

function cloneZones.allGroupsInZoneByData(theZone) 
	local theGroupsInZone = {}
	local radius = theZone.radius 
	for groupName, groupData in pairs(cfxMX.groupDataByName) do 
		if groupData.units then 
			if cloneZones.partOfGroupDataInZone(theZone, groupData.units) then 
				theGroup = Group.getByName(groupName)
				table.insert(theGroupsInZone, theGroup)
			end
		end
	end
	return theGroupsInZone
end


function cloneZones.createClonerWithZone(theZone) -- has "Cloner"
	if cloneZones.verbose or theZone.verbose then 
		trigger.action.outText("+++clnZ: new cloner <" .. theZone.name ..">", 30)
	end
	
	theZone.myUniqueCounter = cloneZones.lclUniqueCounter -- init local counter
	
	local localZones = cloneZones.allGroupsInZoneByData(theZone)  
	local localObjects = cfxZones.allStaticsInZone(theZone, true) -- true = use DCS origin, not moved zone
	if theZone.verbose then 
		trigger.action.outText("+++clnZ: building cloner <" .. theZone.name .. "> TMPL: >>>", 30)
		for idx, theGroup in pairs (localZones) do 
			trigger.action.outText("Zone <" .. theZone.name .. ">: group <" .. theGroup:getName() .. "> in template", 30)
		end
		for idx, theObj in pairs(localObjects) do 
			trigger.action.outText("Zone <" .. theZone.name .. ">: static object <" .. theObj:getName() .. "> in template", 30)
		end
		trigger.action.outText("END cloner <" .. theZone.name .. "> TMPL: <<<", 30)
	end
	theZone.cloner = true -- this is a cloner zoner 
	theZone.mySpawns = {}
	theZone.myStatics = {} 
	-- update: getPoint is bad if it's a moving zone. 
	-- use getDCSOrigin instead 
	theZone.origin = cfxZones.getDCSOrigin(theZone) 
	
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
				-- now get group data and save a lookup for 
				-- resolving internal references 
				local rawData, cat, ctry = cfxMX.getGroupFromDCSbyName(gName)
				local origID = rawData.groupId
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
	
	-- watchflags
	theZone.cloneTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")

	if cfxZones.hasProperty(theZone, "cloneTriggerMethod") then 
		theZone.cloneTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "cloneTriggerMethod", "change")
	end
	
	-- f? and spawn? and other synonyms map to the same 
	if cfxZones.hasProperty(theZone, "f?") then 
		theZone.spawnFlag = cfxZones.getStringFromZoneProperty(theZone, "f?", "none")
	end
	
	if cfxZones.hasProperty(theZone, "in?") then 
		theZone.spawnFlag = cfxZones.getStringFromZoneProperty(theZone, "in?", "none")
	end
	
	if cfxZones.hasProperty(theZone, "spawn?") then 
		theZone.spawnFlag = cfxZones.getStringFromZoneProperty(theZone, "spawn?", "none")
	end
	
	if cfxZones.hasProperty(theZone, "clone?") then 
		theZone.spawnFlag = cfxZones.getStringFromZoneProperty(theZone, "clone?", "none")
	end
	
	if theZone.spawnFlag then 
		theZone.lastSpawnValue = cfxZones.getFlagValue(theZone.spawnFlag, theZone)
	end
	
	-- deSpawn?
	if cfxZones.hasProperty(theZone, "deSpawn?") then 
		theZone.deSpawnFlag = cfxZones.getStringFromZoneProperty(theZone, "deSpawn?", "none")
	end
	
	if cfxZones.hasProperty(theZone, "deClone?") then 
		theZone.deSpawnFlag = cfxZones.getStringFromZoneProperty(theZone, "deClone?", "none")
	end
	
	if cfxZones.hasProperty(theZone, "wipe?") then 
		theZone.deSpawnFlag = cfxZones.getStringFromZoneProperty(theZone, "wipe?", "none")
	end
	
	if theZone.deSpawnFlag then 
		theZone.lastDeSpawnValue = cfxZones.getFlagValue(theZone.deSpawnFlag, theZone)
	end
	
	theZone.onStart = cfxZones.getBoolFromZoneProperty(theZone, "onStart", false)
	
	theZone.moveRoute = cfxZones.getBoolFromZoneProperty(theZone, "moveRoute", false)
	
	theZone.preWipe = cfxZones.getBoolFromZoneProperty(theZone, "preWipe", false)
	
	-- to be deprecated
	if cfxZones.hasProperty(theZone, "empty+1") then 
		theZone.emptyFlag = cfxZones.getStringFromZoneProperty(theZone, "empty+1", "<None>") -- note string on number default
	end
	
	if cfxZones.hasProperty(theZone, "empty!") then 
		theZone.emptyBangFlag = cfxZones.getStringFromZoneProperty(theZone, "empty!", "<None>") -- note string on number default
	end
	
	theZone.cloneMethod = cfxZones.getStringFromZoneProperty(theZone, "cloneMethod", "inc")
	if cfxZones.hasProperty(theZone, "method") then 
		theZone.cloneMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc") -- note string on number default
	end
	
	if cfxZones.hasProperty(theZone, "masterOwner") then 
		theZone.masterOwner = cfxZones.getStringFromZoneProperty(theZone, "masterOwner", "*")
		theZone.masterOwner = dcsCommon.trim(theZone.masterOwner)
		if theZone.masterOwner == "*" then 
			theZone.masterOwner = theZone.name 
			if theZone.verbose then 
				trigger.action.outText("+++clnZ: masterOwner for <" .. theZone.name .. "> successfully to to itself, currently owned by faction <" .. theZone.owner .. ">", 30)
			end
		end
	end
	
	theZone.turn = cfxZones.getNumberFromZoneProperty(theZone, "turn", 0)
	
	-- interface to groupTracker 
	if cfxZones.hasProperty(theZone, "trackWith:") then 
		theZone.trackWith = cfxZones.getStringFromZoneProperty(theZone, "trackWith:", "<None>")
		--trigger.action.outText("trackwith: " .. theZone.trackWith, 30)
	end

	-- randomized locations on spawn 
	theZone.rndLoc = cfxZones.getBoolFromZoneProperty(theZone, "randomizedLoc", false)
	if cfxZones.hasProperty(theZone, "rndLoc") then 
		theZone.rndLoc = cfxZones.getBoolFromZoneProperty(theZone, "rndLoc", false)
	end 
	theZone.centerOnly = cfxZones.getBoolFromZoneProperty(theZone, "centerOnly", false)
	if cfxZones.hasProperty(theZone, "wholeGroups") then 
		theZone.centerOnly = cfxZones.getBoolFromZoneProperty(theZone, "wholeGroups", false)
	end
	
	theZone.rndHeading = cfxZones.getBoolFromZoneProperty(theZone, "rndHeading", false)
	
	theZone.onRoad = cfxZones.getBoolFromZoneProperty(theZone, "onRoad", false)

	-- check for name scheme and / or identical 
	if cfxZones.hasProperty(theZone, "identical") then
		theZone.identical = cfxZones.getBoolFromZoneProperty(theZone, "identical", false)
		if theZone.identical == false then theZone.identical = nil end 
	end 
	
	if cfxZones.hasProperty(theZone, "nameScheme") then 
		theZone.nameScheme = cfxZones.getStringFromZoneProperty(theZone, "nameScheme", "<o>-<uid>") -- default to [<original name> "-" <uuid>] 
	end
	
	if theZone.identical and theZone.nameScheme then
		trigger.action.outText("+++clnZ: WARNING - clone zone <" .. theZone.name .. "> has both IDENTICAL and NAMESCHEME attributes. nameScheme is ignored.", 30)
		theZone.nameScheme = nil 
	end
	-- we end with clear plate 
end

-- 
-- spawning, despawning
--

function cloneZones.despawnAll(theZone) 
	if cloneZones.verbose or theZone.verbose then 
		trigger.action.outText("+++clnZ: despawn all - wiping zone <" .. theZone.name .. ">", 30)
	end 
	for idx, aGroup in pairs(theZone.mySpawns) do 
		--trigger.action.outText("++clnZ: despawn all " .. aGroup.name, 30)
		
		if aGroup:isExist() then 
			if theZone.verbose then 
				trigger.action.outText("+++clnZ: will destroy <" .. aGroup:getName() .. ">", 30)
			end
			cloneZones.invokeCallbacks(theZone, "will despawn group", aGroup)
			Group.destroy(aGroup)
		end 
	end
	for idx, aStatic in pairs(theZone.myStatics) do 
		-- warning! may be mismatch because we are looking at groups
		-- not objects. let's see
		if aStatic:isExist() then 
			if cloneZones.verbose or theZone.verbose then 
				trigger.action.outText("Destroying static <" .. aStatic:getName() .. ">", 30)
			end 
			cloneZones.invokeCallbacks(theZone, "will despawn static", aStatic)
			Object.destroy(aStatic) -- we don't aStatio:destroy() to find out what it is
		end 
	end
	theZone.mySpawns = {}
	theZone.myStatics = {}
end

function cloneZones.assignClosestParking(theData)
	-- on enter: theData has units with updated x, y 
	-- and waypoint 1 action is From Parking 
	-- and it has at least one unit 
	
	-- let's get the airbase 
	local theRoute = theData.route  -- we know it exists
	local thePoints = theRoute.points 
	local firstPoint = thePoints[1]
	local loc = {}
	loc.x = firstPoint.x
	loc.y = 0
	loc.z = firstPoint.y 
	local theAirbase = dcsCommon.getClosestAirbaseTo(loc)
	-- now let's assign free slots closest to unit 
	local slotsTaken = {}
	local units = theData.units
	local cat = cfxMX.groupTypeByName[theData.name] 
	for idx, theUnit in pairs(units) do 
		local newSlot = dcsCommon.getClosestFreeSlotForCatInAirbaseTo(cat, theUnit.x, theUnit.y, theAirbase, slotsTaken)
		if newSlot then 
			local slotNo = newSlot.Term_Index

			theUnit.parking_id = nil -- !! or you b screwed
			theUnit.parking = slotNo -- !! screw parking_ID, they don't match
			theUnit.x = newSlot.vTerminalPos.x 
			theUnit.y = newSlot.vTerminalPos.z -- !!!
			table.insert(slotsTaken, slotNo)
		end
	end
end

function cloneZones.rotateWPAroundCenter(thePoint, center, angle)
	-- angle in rads
	-- move to center 
	thePoint.x = thePoint.x - center.x 
	thePoint.y = thePoint.y - center.z -- !! 
	-- rotate 
	local c = math.cos(angle)
	local s = math.sin(angle)
	local px = thePoint.x * c - thePoint.y * s
	local py = thePoint.x * s + thePoint.y * c
	
	-- apply and move back 
	thePoint.x = px + center.x 
	thePoint.y = py + center.z -- !!
end

function cloneZones.updateTaskLocations(thePoint, zoneDelta)
	-- parse tasks for x and y and update them by zoneDelta
	if thePoint and thePoint.task and thePoint.task.params and thePoint.task.params.tasks then 
		local theTasks = thePoint.task.params.tasks
		for idx, aTask in pairs(theTasks) do 
			-- EngageTargetsInZone task has x & y in params
			if aTask.params and aTask.params.x and aTask.params.y then 
				aTask.params.x = aTask.params.x + zoneDelta.x 
				aTask.params.y = aTask.params.y + zoneDelta.z --!!
--				trigger.action.outText("moved search & engage zone", 30)
			end
		end
	end
end

function cloneZones.updateLocationsInGroupData(theData, zoneDelta, adjustAllWaypoints, center, angle)
	-- enter with theData being group's data block 
	-- remember that zoneDelta's [z] modifies theData's y!!
	local units = theData.units 
	local departFromAerodrome = false 
	local fromParking = false 
	for idx, aUnit in pairs(units) do 
		aUnit.x = aUnit.x + zoneDelta.x 
		aUnit.y = aUnit.y + zoneDelta.z -- again!!!!
	end
	-- now modifiy waypoints. we ALWAYS adjust the  
	-- first waypoint, all others only if asked 
	-- to by moveRoute attribute (adjustAllWaypoints)
	local theRoute = theData.route 
	if theRoute then 
		local thePoints = theRoute.points 
		if thePoints and #thePoints > 0 then 
			if adjustAllWaypoints then  
				for i=1, #thePoints do 
					thePoints[i].x = thePoints[i].x + zoneDelta.x 
					thePoints[i].y = thePoints[i].y + zoneDelta.z -- (!!)
					-- rotate around center by angle if given
					if center and angle then 
						cloneZones.rotateWPAroundCenter(thePoints[i], center, angle)
					else 
--						trigger.action.outText("not rotating route", 30)
					end
					cloneZones.updateTaskLocations(thePoints[i], zoneDelta)
				end
			else 
				-- only first point 
				thePoints[1].x = thePoints[1].x + zoneDelta.x 
				thePoints[1].y = thePoints[1].y + zoneDelta.z -- (!!)
				if center and angle then 
					cloneZones.rotateWPAroundCenter(thePoints[1], center, angle)
				end
				cloneZones.updateTaskLocations(thePoints[i], zoneDelta)
			end 
			
			-- if there is an airodrome id given in first waypoint, 
			-- adjust for closest location 
			local firstPoint = thePoints[1]
			if firstPoint.airdromeId then 
				local loc = {}
				loc.x = firstPoint.x
				loc.y = 0
				loc.z = firstPoint.y 
				local bestAirbase = dcsCommon.getClosestAirbaseTo(loc)
				--departingAerodrome = bestAirbase
				firstPoint.airdromeId = bestAirbase:getID()
				departFromAerodrome = true  
				fromParking = dcsCommon.stringStartsWith(firstPoint.action, "From Parking")
			end
			
			-- adjust last point (landing)
			if #thePoints > 1 then 
				local lastPoint = thePoints[#thePoints]
				if firstPoint.airdromeId then 
					local loc = {}
					loc.x = lastPoint.x
					loc.y = 0
					loc.z = lastPoint.y 
					local bestAirbase = dcsCommon.getClosestAirbaseTo(loc)
					lastPoint.airdromeId = bestAirbase:getID()
				end
			
			end
		end -- if points in route 
	end -- if route 
	
	-- now process departing slot if given 
	if departFromAerodrome then 
		-- we may need alt from land to add here, maybe later 
	
		-- now process parking slots, and choose closest slot 
		-- per unit's location 
		if fromParking then 
			cloneZones.assignClosestParking(theData)
		end
	end
end


function cloneZones.nameFromSchema(schema, inName, theZone, sourceName, i)
	-- default schema (classic) is "<o>-<uid>"
	local outName = schema
	local iter = i 

	-- replace all occurences of <o> with original name
	outName = outName:gsub("<o>", inName)

	-- replace all occurences of <z> with zone name 
	outName = outName:gsub("<z>", theZone.name)
	-- replace all occurences of <s> with source zone name 
	outName = outName:gsub("<s>", sourceName)
	
	-- uid (uuid) with auto-increment
	local pos = string.find(outName, "<uid>")
	while (pos and pos > 0) do 
		local uid = tostring(dcsCommon.numberUUID())
		outName = outName:gsub("<uid>", uid, 1) -- only first substitution
		pos = string.find(outName, "<uid>")
	end
	
	-- i (iter) with increment 
	pos = string.find(outName, "<i>")
	while (pos and pos > 0) do 
		local uid = tostring(iter)
		outName = outName:gsub("<i>", uid, 1) -- only first substitution
		iter = iter + 1
		pos = string.find(outName, "<i>")
	end
	
	-- lcl local (zonal) count with increment
	pos = string.find(outName, "<lcl>")
	while (pos and pos > 0) do 
		local uid = tostring(theZone.myUniqueCounter)
		outName = outName:gsub("<lcl>", uid, 1) -- only first substitution
		theZone.myUniqueCounter = theZone.myUniqueCounter + 1
		pos = string.find(outName, "<lcl>")
	end
	
	-- g global (module) count with increment 
	pos = string.find(outName, "<g>")
	while (pos and pos > 0) do 
		local uid = tostring(cloneZones.globalCounter)
		outName = outName:gsub("<g>", uid, 1) -- only first substitution
		cloneZones.globalCounter = cloneZones.globalCounter + 1
		pos = string.find(outName, "<g>")
	end
	
	--if theZone.verbose then 
	--	trigger.action.outText("+++cln: schema [" .. schema .. "] for unit <" .. inName .. "> in zone <" .. theZone.name .. "> returns <" .. outName .. ">, iter = " .. iter, 30)
	--end
	return outName, iter
end

function cloneZones.uniqueID()
	local uid = cloneZones.uniqueCounter
	cloneZones.uniqueCounter = cloneZones.uniqueCounter + 1
	return uid 
end

function cloneZones.uniqueNameGroupData(theData, theCloneZone, sourceName)
	if not sourceName then sourceName = theCloneZone.name end 
	theData.name = dcsCommon.uuid(theData.name)
	local units = theData.units 
	local iterCount = 1 
	local newName = "none"
	local allNames = {} -- enforce unique names inside group
	for idx, aUnit in pairs(units) do 
		if theCloneZone and theCloneZone.nameScheme then
			local schema = theCloneZone.nameScheme
			newName, iterCount = cloneZones.nameFromSchema(schema, aUnit.name, theCloneZone, sourceName, iterCount)
			
			-- make sure that this name is has not been generated yet
			-- inside the same group
			local hasChanged = false 
			local schemeName = newName 
			while dcsCommon.arrayContainsString(allNames, newName) do 
				newName = newName .. "x"
				hasChanged = true
			end
			if theCloneZone.verbose and hasChanged then 
				trigger.action.outText("cnlz: nameScheme [" .. theCloneZone.nameScheme .. "] failsafe: changed <" .. schemeName .. "> to <" .. newName .. ">", 30)
			end
			
			table.insert(allNames, newName)
			
			if theCloneZone.verbose then 
				trigger.action.outText("clnZ: zone <" .. theCloneZone.name .. "> unit schema <" .. schema .. ">: <" .. aUnit.name .. "> --> <" .. newName .. ">", 30)
			end
			
			aUnit.name = newName -- dcsCommon.uuid(aUnit.name)
		else
			-- default naming scheme: <name>-<uuid>
			aUnit.name = dcsCommon.uuid(aUnit.name)
		end
	end 
end 

function cloneZones.uniqueNameStaticData(theData, theCloneZone, sourcename)
	if not sourceName then sourceName = theCloneZone.name end 

	-- WARNING: unlike GroupData enters with UNIT data 
	local iterCount = 1 
	local newName = "none"
	if theCloneZone and theCloneZone.nameScheme then
		local schema = theCloneZone.nameScheme
		newName, iterCount = cloneZones.nameFromSchema(schema, theData.name, theCloneZone, sourceName, iterCount)
		
		if theCloneZone.verbose then 
			trigger.action.outText("clnZ: zone <" .. theCloneZone.name .. "> static schema <" .. schema .. ">: <" .. theData.name .. "> --> <" .. newName .. ">", 30)
		end
		
		theData.name = newName -- dcsCommon.uuid(theData.name)
	else
		-- default naming scheme: <name>-<uuid>
		theData.name = dcsCommon.uuid(theData.name)
	end
end

function cloneZones.uniqueIDGroupData(theData)
	theData.groupId = cloneZones.uniqueID()
end

function cloneZones.uniqueIDUnitData(theData)
	if not theData then return end 
	if not theData.units then return end 
	local units = theData.units 
	for idx, aUnit in pairs(units) do 
		aUnit.CZorigID = aUnit.unitId 
		aUnit.unitId = cloneZones.uniqueID()
		aUnit.CZTargetID = aUnit.unitId
	end 
end

function cloneZones.sameIDUnitData(theData)
	if not theData then return end 
	if not theData.units then return end
	local units = theData.units 
	for idx, aUnit in pairs(units) do 
		aUnit.CZorigID = aUnit.unitId 
		aUnit.CZTargetID = aUnit.unitId
	end 
end

function cloneZones.resolveOwnership(spawnZone, ctry)
	if not spawnZone.masterOwner then return ctry end 
	local masterZone = cfxZones.getZoneByName(spawnZone.masterOwner)
	if not masterZone then 
		trigger.action.outText("+++clnZ: cloner " .. spawnZone.name .. " could not find master owner <" .. spawnZone.masterOwner .. ">", 30)
		return ctry 
	end
	
	if not masterZone.owner then 
		return ctry 
	end
	
	ctry = dcsCommon.getACountryForCoalition(masterZone.owner)
	return ctry 
end

--
-- resolve external group references 
-- 
function cloneZones.resolveGroupID(gID, rawData, dataTable, reason)
	if not reason then reason = "<default>" end 
	
	local resolvedID = gID
	local myOName = rawData.CZorigName
	local groupName = cfxMX.groupNamesByID[gID]
	
	-- first, check if this an internal reference, i.e. inside the same 
	-- zone template 
	for idx, otherData in pairs(dataTable) do
		-- look in own data table 
		if otherData.CZorigName == groupName then 
			-- using cfxMX for clarity only (name access)
			resolvedID = otherData.CZTargetID
			return resolvedID
		end
	end
	
	-- now check if we have spawned this before 
	local lastClone = cloneZones.groupXlate[gID]
	if lastClone then 
		resolvedID = lastClone
		return resolvedID	
	end
	
	-- if we get here, reference is not to a cloned item 
	return resolvedID
end 

function cloneZones.resolveUnitID(uID, rawData, dataTable, reason)
-- also resolves statics as they share ID with units 
	local resolvedID = uID	
	-- first, check if this an internal reference, i.e. inside the same 
	-- zone template 
	for idx, otherData in pairs(dataTable) do
		-- iterate all units
		for idy, aUnit in pairs(otherData.units) do 
			if aUnit.CZorigID == uID then 
				resolvedID = aUnit.CZTargetID
				return resolvedID
			end
		end		

	end
	
	-- now check if we have spawned this before 
	local lastClone = cloneZones.unitXlate[uID]
	if lastClone then 
		resolvedID = lastClone
		return resolvedID	
	end
	
	-- if we get here, reference is not to a cloned item 
	return resolvedID
end 

function cloneZones.resolveStaticLinkUnit(uID)
	local resolvedID = uID
	local lastClone = cloneZones.unitXlate[uID]
	if lastClone then 
		resolvedID = lastClone
		return resolvedID	
	end
	return resolvedID
end

function cloneZones.resolveWPReferences(rawData, theZone, dataTable)
-- check to see if we really need data table, as we have theZone 
-- perform a check of route for group or unit references 
	if not rawData then return end 
	local myOName = rawData.CZorigName 

	if rawData.route and rawData.route.points then 
		local points = rawData.route.points 
		for idx, aPoint in pairs(points) do 
			-- check if there is a link unit here and resolve 
			if aPoint.linkUnit then 
				local gID = aPoint.linkUnit
				local resolvedID = cloneZones.resolveUnitID(gID, rawData, dataTable, "linkUnit")
				aPoint.linkUnit = resolvedID
			end
			
			-- iterate all tasks assigned to point
			local task = aPoint.task
			if task and task.params and task.params.tasks then
				local tasks = task.params.tasks 
				-- iterate all tasks for this waypoint 
				for idy, taskData in pairs(tasks) do
					-- resolve group references in TASKS
					-- also covers recovery tanke etc
					if taskData.id and taskData.params and taskData.params.groupId
					then 
						-- we resolve group reference 
						local gID = taskData.params.groupId
						local resolvedID = cloneZones.resolveGroupID(gID, rawData, dataTable, taskData.id)
						taskData.params.groupId = resolvedID
						
					end
					
					-- resolve EMBARK/DISEMBARK group references 
					if taskData.id and taskData.params and taskData.params.groupsForEmbarking
					then 
						-- build new groupsForEmbarking
						local embarkers = taskData.params.groupsForEmbarking
						local newEmbarkers = {}
						for grpIdx, gID in pairs(embarkers) do 
							local resolvedID = cloneZones.resolveGroupID(gID, rawData, dataTable, "embark")
							table.insert(newEmbarkers, resolvedID)
							--trigger.action.outText("+++clnZ: resolved embark group id <" .. gID .. "> to <" .. resolvedID .. ">", 30)
						end
						-- replace old with new table
						taskData.params.groupsForEmbarking = newEmbarkers
					end
					
					-- resolve DISTRIBUTION (embark) unit/group refs 
					if taskData.id and taskData.params and taskData.params.distribution then 
						local newDist = {} -- will replace old 
						for aUnit, aList in pairs(taskData.params.distribution) do 
							-- first, translate this unit's number 
							local newUnit = cloneZones.resolveUnitID(aUnit, rawData, dataTable, "transportID")
							local embarkers = aList 
							local newEmbarkers = {}
							for grpIdx, gID in pairs(embarkers) do 
								-- translate old to new 
								local resolvedID = cloneZones.resolveGroupID(gID, rawData, dataTable, "embark")
								table.insert(newEmbarkers, resolvedID)
								--trigger.action.outText("+++clnZ: resolved distribute unit/group id <" .. aUnit .. "/" .. gID .. "> to <".. newUnit .. "/" .. resolvedID .. ">", 30)
							end
							-- store this as new group for 
							-- translated transportID
							newDist[newUnit] = newEmbarkers
						end
						-- replace old distribution with new 
						taskData.params.distribution = newDist 
						--trigger.action.outText("+++clnZ: rebuilt distribution", 30)
					end
					
					-- resolve selectedTransport unit reference 
					if taskData.id and taskData.params and taskData.params.selectedTransportt then
						local tID = taskData.params.selectedTransport
						local newTID = cloneZones.resolveUnitID(tID, rawData, dataTable, "transportID")
						taskData.params.selectedTransport = newTID
						--trigger.action.outText("+++clnZ: resolved selected transport <" .. tID .. "> to <" .. newTID .. ">", 30)
					end
					
					-- note: we may need to process x and y as well
					
					-- resolve UNIT references in TASKS
					if taskData.id and taskData.params and taskData.params.unitId
					then 
						-- we don't look for keywords, we simply resolve 
						local uID = taskData.params.unitId 
						local resolvedID = cloneZones.resolveUnitID(uID, rawData, dataTable, taskData.id)
						taskData.params.unitId = resolvedID
					end
					
					-- resolve unit references in ACTIONS
					-- for example TACAN
					if taskData.params and taskData.params.action and 
					taskData.params.action.params and taskData.params.action.params.unitId then 
						local uID = taskData.params.action.params.unitId 
						local resolvedID = cloneZones.resolveUnitID(uID, rawData, dataTable, "Action")
						taskData.params.action.params.unitId = resolvedID
					end
				end	
			end
		end
	end 
end 

function cloneZones.resolveReferences(theZone, dataTable) 
	-- when an action refers to another group, we check if 
	-- the group referred to is also a clone, and update 
	-- the reference to the newest incardnation 
	
	for idx, rawData in pairs(dataTable) do 
		-- resolve references in waypoints
		cloneZones.resolveWPReferences(rawData, theZone, dataTable)
	end
end


function cloneZones.handoffTracking(theGroup, theZone)
	if not groupTracker then 
		trigger.action.outText("+++clnZ: <" .. theZone.name .. "> trackWith requires groupTracker module", 30) 
		return 
	end
	local trackerName = theZone.trackWith
	--if trackerName == "*" then trackerName = theZone.name end 
	-- now assemble a list of all trackers
	if cloneZones.verbose or theZone.verbose then 
		trigger.action.outText("+++clnZ: clone pass-off: " .. trackerName, 30)
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
			trigger.action.outText("+++clnZ: <" .. theZone.name .. ">: cannot find tracker named <".. theName .. ">", 30) 
		else 
			groupTracker.addGroupToTracker(theGroup, theTracker)
			 if cloneZones.verbose or theZone.verbose then 
				trigger.action.outText("+++clnZ: added " .. theGroup:getName() .. " to tracker " .. theName, 30)
			 end
		end 
	end 
end

function cloneZones.validateSpawnUnitData(aUnit, theZone, unitNames)
	-- entry with unit data construct
	-- also used for static objects!
	if not aUnit then return end 
	if not theZone then return end 
	-- we only verify replacement if identical or name sheme attribute 
	if not (theZone.identical or theZone.nameScheme) then 
		return 
	end
	
	if unitNames[aUnit.name] then 
		trigger.action.outText("clnZ: <" .. theZone.name .. "> validation warning - Unit/Object name <" .. aUnit.name .. ">: duplicate name within spawn cycle, will be repaced", 30)
	else 
		unitNames[aUnit.name] = true 
	end		
	
	local theUnit = Unit.getByName(aUnit.name) 
	if theUnit and Unit.isExist(theUnit) then 
		if cloneZones.verbose or theZone.verbose then 
			trigger.action.outText("+++clnZ: cloner <" .. theZone.name .. "> will replace existing UNIT <" .. aUnit.name .. ">", 30)
		end
		-- since we are about to replace a unit, we also steal the ID
		local stolenID = theUnit:getID()
		aUnit.unitId = stolenID
	else 
		-- now check if we are about to grab an MX data ID 
		-- and ned to steal that	
		local stolenID = cfxMX.unitIDbyName[aUnit.name]
		if stolenID then 
			if cloneZones.verbose or theZone.verbose then 
				trigger.action.outText("+++clnZ: cloner <" .. theZone.name .. "> will replace MX UNIT ID <" .. aUnit.name .. "> by appropriating ID <" .. stolenID .. ">", 30)
			end
			aUnit.unitId = stolenID
		end
	end	
	
 
	-- check against static objects. 
	local theStatic = StaticObject.getByName(aUnit.name)	
	if theStatic and StaticObject.isExist(theStatic) then 
		trigger.action.outText("+++clnZ: cloner <" .. theZone.name .. "> will replace existing STATIC <" .. aUnit.name .. ">", 30)
	end	
	
end

function cloneZones.validateSpawnGroupData(theData, theZone, groupNames, unitNames)
	-- entry with group construct
	if not theData then return end 
	if not theZone then return end 
	-- we only verify replacement if identical or name sheme attribute 
	if not (theZone.identical or theZone.nameScheme) then 
		return 
	end
	
	if groupNames[theData.name] then 
		trigger.action.outText("clnZ: <" .. theZone.name .. "> validation warning - group name <" .. theData.name .. ">: duplicate within spawn, previous spawn will be removed", 30)
	else 
		groupNames[theData.name] = true 
	end
	
	local theGroup = Group.getByName(theData.name)
	if theGroup and Group.isExist(theGroup) and theGroup:getSize() > 0 then 
		trigger.action.outText("+++clnZ: cloner <" .. theZone.name .. "> will replace existing GROUP <" .. theData.name .. ">", 30)
	end
	
	if not theData.units then return end 
	local units = theData.units 
	for idx, aUnit in pairs(units) do 
		cloneZones.validateSpawnUnitData(aUnit, theZone, unitNames)	
	end 
end

function cloneZones.forcedRespawn(args)
	local theData = args[1]
	local spawnedGroups = args[2]
	local pos = args[3]
	local verbose = args[4]
	local rawData = dcsCommon.clone(theData)
	if verbose then 
		trigger.action.outText("clnZ: enter forced respawn of <" .. theData.name .. "> to meet ID " .. theData.CZTargetID .. " (currently set for <" .. theData.groupId .. ">)", 30)
	end
	-- we now try to spawn again, with hopes of receiving the 
	-- correct id 
	local theGroup = coalition.addGroup(rawData.CZctry, rawData.CZtheCat, rawData)
	
	-- make sure that this time the id matches 
	local newGroupID = theGroup:getID()
	if newGroupID == theData.CZTargetID then 
		if verbose then 
			trigger.action.outText("GOOD REPLACEMENT new ID <" .. newGroupID .. "> matches target <" .. theData.CZTargetID .. "> for <" .. theData.name .. ">", 30)
		-- we can now remove the former group 
		-- and replace it with the new one 
			trigger.action.outText("will replace table entry at <" .. pos .. "> with new group", 30)
		end
		spawnedGroups[pos] = theGroup
	else 
		-- we need to try again in one second
		if verbose then 
			trigger.action.outText("FAIL: new ID <" .. newGroupID .. "> does not match target <" .. theData.CZTargetID .. "> for <" .. theData.name .. ">. Will re-try in 1s", 30)
		end
		spawnedGroups[pos] = theGroup -- replace so we don't fail checks
		timer.scheduleFunction(cloneZones.forcedRespawn, args, timer.getTime() + 1)
	end
end

function cloneZones.spawnWithTemplateForZone(theZone, spawnZone)
	if cloneZones.verbose or spawnZone.verbose then 
		trigger.action.outText("+++clnZ: spawning with template <" .. theZone.name .. "> for spawner <" .. spawnZone.name .. ">", 30)
	end
	-- theZone is the cloner with the TEMPLATE (source)
	-- spawnZone is the spawner with SETTINGS and DESTINATION (target location)
	local newCenter = cfxZones.getPoint(spawnZone) -- includes zone following updates
	local oCenter = cfxZones.getDCSOrigin(theZone) -- get original coords on map for cloning offsets 
	-- calculate zoneDelta, is added to all vectors 
	local zoneDelta = dcsCommon.vSub(newCenter, theZone.origin) -- oCenter) --theZone.origin)
	
	-- precalc turn value for linked rotation
	local dHeading = 0 -- for linked zones 
	local rotCenter = nil 
	if spawnZone.linkedUnit and spawnZone.uHdg and spawnZone.useHeading and Unit.isExist(spawnZone.linkedUnit) then 
		local theUnit = spawnZone.linkedUnit
		local currHeading = dcsCommon.getUnitHeading(theUnit)
		dHeading = currHeading - spawnZone.uHdg
		rotCenter = cfxZones.getPoint(spawnZone)
	end 
	
	local spawnedGroups = {}
	local spawnedStatics = {}
	local dataToSpawn = {} -- temp save so we can connect in-group references
	
	for idx, aGroupName in pairs(theZone.cloneNames) do 
		local rawData, cat, ctry = cfxMX.getGroupFromDCSbyName(aGroupName)
		rawData.CZorigName = rawData.name -- save original group name
		local origID = rawData.groupId -- save original group ID 
		rawData.CZorigID = origID 
		if spawnZone.identical then 
			cloneZones.sameIDUnitData(rawData) -- set up CZTargetID for units to be same as in template
		else
			-- only assign new ids when 'identical' flag is not active
			cloneZones.uniqueIDGroupData(rawData) -- assign unique ID we know 
			cloneZones.uniqueIDUnitData(rawData) -- assign unique ID for units -- saves old unitId as CZorigID		
		end
		
		rawData.CZTargetID = rawData.groupId -- save 
		if rawData.name ~= aGroupName then 
			trigger.action.outText("Clone: FAILED name check", 30)
		end
		
		local theCat = cfxMX.catText2ID(cat)
		rawData.CZtheCat = theCat -- save category 
		
		-- update their position if not spawning to exact same location
		if cloneZones.verbose or theZone.verbose or spawnZone.verbose then 	
			--trigger.action.outText("+++clnZ: tmpl delta x = <" .. math.floor(zoneDelta.x) .. ">, y = <" .. math.floor(zoneDelta.z) .. "> for tmpl <" .. theZone.name  .. "> to cloner <" .. spawnZone.name .. ">", 30)
		end
		-- update routes when not spawning same location 
		cloneZones.updateLocationsInGroupData(rawData, zoneDelta, spawnZone.moveRoute, rotCenter, spawnZone.turn / 57.2958 +
		dHeading)
		
		-- apply randomizer if selected 
		if spawnZone.rndLoc then 
			-- calculate the entire group's displacement
			local units = rawData.units

			local loc, dx, dy = cfxZones.createRandomPointInZone(spawnZone) -- also supports polygonal zones 
			
			for idx, aUnit in pairs(units) do 
				if not spawnZone.centerOnly then 
					-- *every unit's displacement is randomized
					loc, dx, dy = cfxZones.createRandomPointInZone(spawnZone)
					aUnit.x = loc.x 
					aUnit.y = loc.z 
				else 
					aUnit.x = aUnit.x + dx
					aUnit.y = aUnit.y + dy 
				end
				if spawnZone.verbose or cloneZones.verbose then 
					trigger.action.outText("+++clnZ: <" .. spawnZone.name .. "> R = " .. spawnZone.radius .. ":G<" .. rawData.name .. "/" .. aUnit.name .. "> - rndLoc: dx = " .. dx .. ", dy= " .. dy .. ".", 30)
				end

			end
		end
		
		if spawnZone.rndHeading then 
			local units = rawData.units
			if spawnZone.centerOnly and units and units[1] then 
				-- rotate entire group around unit 1
				local cx = units[1].x 
				local cy = units[1].y 
				local degrees = 360 * math.random() -- rotateGroupData uses degrees
				dcsCommon.rotateGroupData(rawData, degrees, cx, cy)
			else
				for idx, aUnit in pairs(units) do 
					local phi = 6.2831 * math.random() -- that's 2Pi, folx 
					aUnit.heading = phi
				end
			end
		end

		-- apply onRoad option if selected 			
		if spawnZone.onRoad then 
			local units = rawData.units
			if spawnZone.centerOnly then 
				-- only place the first unit in group on roads
				-- and displace all other with the same offset 
				local hasOffset = false 
				local dx, dy, cx, cy
				for idx, aUnit in pairs(units) do 
					cx = aUnit.x
					cy = aUnit.y 
					if not hasOffset then 
						local nx, ny =  land.getClosestPointOnRoads("roads", cx, cy)
						dx = nx - cx 
						dy = ny - cy
						hasOffset = true
					end
					aUnit.x = cx + dx 
					aUnit.y = cy + dy
				end
			else
				local iterCount = 0
				local otherLocs = {} -- resolved locs
				for idx, aUnit in pairs(units) do 
					local cx = aUnit.x
					local cy = aUnit.y 
					-- we now iterate until there is enough separation or too many iters
					local tooClose
					local np, nx, ny					
					repeat 
						nx, ny =  land.getClosestPointOnRoads("roads", cx, cy)
						-- compare this with all other locs
						np = {x=nx, y=ny}
						tooClose = false
						for idc, op in pairs(otherLocs) do 
							local d = dcsCommon.dist(np, op)
							if d < cloneZones.minSep then 
								tooClose = true 
								cx = cx + cloneZones.minSep
								cy = cy + cloneZones.minSep
								iterCount = iterCount + 1
							end
						end						
					until (iterCount > cloneZones.maxIter) or (not tooClose)

					table.insert(otherLocs, np)
					aUnit.x = nx
					aUnit.y = ny 
				end
			end -- else centerOnly
		end
		
		
		-- apply turning 
		dcsCommon.rotateGroupData(rawData, spawnZone.turn + 57.2958 *dHeading, newCenter.x, newCenter.z)

		-- make sure unit and group names are unique unless
		-- we have identical active 
		if not spawnZone.identical then 
			cloneZones.uniqueNameGroupData(rawData, spawnZone, theZone.name)
		end 
		
		-- see what country we spawn for
		ctry = cloneZones.resolveOwnership(spawnZone, ctry)
		rawData.CZctry = ctry -- save ctry 
		table.insert(dataToSpawn, rawData)
	end 
	
	-- now resolve references to other cloned units for all raw data
	-- we must do this BEFORE we spawn
	cloneZones.resolveReferences(theZone, dataToSpawn)
	
	-- now spawn all raw data 
	local groupCollector = {} -- to detect cross-group conflicts
	local unitCollector = {} -- to detect cross-group conflicts 
	for idx, rawData in pairs (dataToSpawn) do 
		-- now spawn and save to clones
		-- first norm and clone data for later save
		rawData.cty = rawData.CZctry 
		rawData.cat = rawData.CZtheCat
				
		-- make group, unit[1] and route point [1] all match up
		if rawData.route and rawData.units[1] then 
			-- trigger.action.outText("matching route point 1 and group with unit 1", 30)
			rawData.route.points[1].x = rawData.units[1].x
			rawData.route.points[1].y = rawData.units[1].y
			rawData.x = rawData.units[1].x
			rawData.y = rawData.units[1].y
		end
		
		-- clone for persistence
		local theData = dcsCommon.clone(rawData)
		cloneZones.allClones[rawData.name] = theData 
		
		if cloneZones.verbose or spawnZone.verbose then 
			-- optional spawn validation report before we spawn 
			cloneZones.validateSpawnGroupData(rawData, spawnZone, groupCollector, unitCollector)
		end
		
		-- SPAWN NOW!!!!
		local theGroup = coalition.addGroup(rawData.CZctry, rawData.CZtheCat, rawData)
		table.insert(spawnedGroups, theGroup)
				
		-- update groupXlate table from spawned group
		-- so we can later reference them with other clones
		local newGroupID = theGroup:getID() -- new ID assigned by DCS
		local origID = rawData.CZorigID -- before we materialized
		cloneZones.groupXlate[origID] = newGroupID
		-- now also save all units for references 	
		-- and verify assigned vs target ID 
		for idx, aUnit in pairs(rawData.units) do 
			-- access the proposed name 
			local uName = aUnit.name 
			local gUnit = Unit.getByName(uName)
			if gUnit then 
				-- unit exists. compare planned and assigned ID
				local uID = tonumber(gUnit:getID())
				if uID == aUnit.CZTargetID then 
					-- all good 
				else 
					-- mismatch. may happen when namingScheme causes 
					-- unit to be reallocated to existing unit.
					if spawnZone.verbose then 
						if spawnZone.nameScheme then
							trigger.action.outText("clnZ: nameScheme - unit <" .. uName .. ">: ÎD mapped to existing: " .. uID , 30)
						else
							trigger.action.outText("clnZ: post-clone verification failed for unit <" .. uName .. ">: ÎD mismatch: " .. uID .. " -- " .. aUnit.CZTargetID, 30)
						end
					end 
				end 
				cloneZones.unitXlate[aUnit.CZorigID] = uID 
			else 
				trigger.action.outText("clnZ: post-clone verifiaction failed for unit <" .. uName .. ">: not found", 30) 
			end 
		end
		
		-- check if our assigned ID matches the handed out by 
		-- DCS. Mismatches can happen, and are only noted 
		if newGroupID == rawData.CZTargetID then 
			-- we are good
		else 
			if cloneZones.verbose or spawnZone.verbose then 
				trigger.action.outText("clnZ: Note: GROUP ID spawn changed for <" .. rawData.name .. ">: target ID " .. rawData.CZTargetID .. " (target) returns " .. newGroupID .. " (actual) in <" .. spawnZone.name .. ">", 30)
				--trigger.action.outText("Note: theData.groupId is <" .. theData.groupId .. ">", 30)
				--if spawnZone.identical then 
				--	trigger.action.outText("(Identical = true detected for this zone)", 30)
				--end
			end
			
			if cloneZones.respawnOnGroupID then 
				-- remove last entry in table, will be added later
				local pos = #spawnedGroups
				
				timer.scheduleFunction(cloneZones.forcedRespawn, {theData, spawnedGroups, pos, spawnZone.verbose}, timer.getTime() + 2) -- initial gap: 2 seconds for DCS to sort itself out
			else 
				-- we note it in the spawn data for the group so
				-- persistence works fine 
				theData.groupId = newGroupID
			end
		end 

		cloneZones.invokeCallbacks(spawnZone, "did spawn group", theGroup)
		-- interface to groupTracker 
		if spawnZone.trackWith then 
			cloneZones.handoffTracking(theGroup, spawnZone) 
		end
	end
	
	-- static spawns 
	for idx, aStaticName in pairs(theZone.staticNames) do 
		local rawData, cat, ctry, parent = cfxMX.getStaticFromDCSbyName(aStaticName) -- returns a UNIT data block
		
		if not rawData then
			trigger.action.outText("Static Clone: no such group <"..aStaticName .. ">", 30)			
		elseif rawData.name == aStaticName then 
			-- all good
		else 
			trigger.action.outText("Static Clone: FAILED name check for <" .. aStaticName .. ">", 30)
		end
		local origID = rawData.unitId -- save original unit ID
		rawData.CZorigID = origID 					
		rawData.x = rawData.x + zoneDelta.x 
		rawData.y = rawData.y + zoneDelta.z -- !!!
			
		-- randomize if enabled
		if spawnZone.rndLoc then 

			local loc, dx, dy = cfxZones.createRandomPointInZone(spawnZone) -- also supports polygonal zones 
			rawData.x = rawData.x + dx
			rawData.y = rawData.y + dy 
		end
		
		if spawnZone.rndHeading then 
			local phi = 6.2831 * math.random() -- that's 2Pi, folx 
			rawData.heading = phi
		end
		
		if spawnZone.onRoad then 
			local cx = rawData.x
			local cy = rawData.y 
			local nx, ny =  land.getClosestPointOnRoads("roads", cx, cy)
			rawData.x = nx
			rawData.y = ny 
		end
		
		-- apply turning 
		dcsCommon.rotateUnitData(rawData, spawnZone.turn + 57.2958 * dHeading, newCenter.x, newCenter.z)
		
		if not spawnZone.identical then
			-- make sure static name is unique and remember original 
			cloneZones.uniqueNameStaticData(rawData, spawnZone, theZone.name)
			--rawData.name = dcsCommon.uuid(rawData.name)
			rawData.unitId = cloneZones.uniqueID()
		end 
		rawData.CZTargetID = rawData.unitId 
		
		-- see what country we spawn for
		ctry = cloneZones.resolveOwnership(spawnZone, ctry)
		
		-- handle linkUnit if provided  
		if false and rawData.linkUnit then 
			local lU = cloneZones.resolveStaticLinkUnit(rawData.linkUnit)
			rawData.linkUnit = lU 
			if not rawData.offsets then 
				rawData.offsets = {}
				rawData.offsets.angle = 0
				rawData.offsets.x = 0
				rawData.offsets.y = 0
			end 
			rawData.offsets.y = rawData.offsets.y - zoneDelta.z 
			rawData.offsets.x = rawData.offsets.x - zoneDelta.x 
			rawData.offsets.angle = rawData.offsets.angle + spawnZone.turn
			rawData.linkOffset = true 
		end
		
		local isCargo = rawData.canCargo 
		rawData.cty = ctry 
		-- save for persistence 
		local theData = dcsCommon.clone(rawData)
		cloneZones.allCObjects[rawData.name] = theData 
		
		if cloneZones.verbose or spawnZone.verbose then 
			-- optional spawn validation report before we spawn 
			cloneZones.validateSpawnUnitData(rawData, spawnZone, unitCollector)
		end
		
		local theStatic = coalition.addStaticObject(ctry, rawData)
		local newStaticID = tonumber(theStatic:getID()) 
		table.insert(spawnedStatics, theStatic)
		-- we don't mix groups with units, so no lookup tables for 
		-- statics 
		if newStaticID == rawData.CZTargetID then 
		else 
			if cloneZones.verbose or spawnZone.verbose then 
				trigger.action.outText("Static ID mismatch: " .. newStaticID .. " vs (target) " .. rawData.CZTargetID .. " for " .. rawData.name, 30)
			end
		end
		cloneZones.unitXlate[origID] = newStaticID -- same as units 
		
		cloneZones.invokeCallbacks(theZone, "did spawn static", theStatic)
		
		if cloneZones.verbose or spawnZone.verbose then 
			trigger.action.outText("Static spawn: spawned " .. aStaticName, 30)
		end 
		-- processing for cargoManager 
		if isCargo then 
			if cfxCargoManager then 
				cfxCargoManager.addCargo(theStatic)
				if cloneZones.verbose or spawnZone.verbose then 
					trigger.action.outText("+++clnZ: added CARGO " .. theStatic:getName() .. " to cargo manager ", 30)
				end
			else 
				if cloneZones.verbose or spawnZone.verbose then 
					trigger.action.outText("+++clnZ: CARGO " .. theStatic:getName() .. " detected, not managerd", 30)
				end
			end
		end
	end	
	local args = {}
	args.groups = spawnedGroups
	args.statics = spawnedStatics
	cloneZones.invokeCallbacks(theZone, "spawned", args)
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
			if cloneZones.verbose or theZone.verbose then 
				trigger.action.outText("+++clnZ: picked random template <" .. templateName .."> for from <" .. allNames .. "> for cloner " .. theZone.name, 30)
			end 
		end
		if cloneZones.verbose or theZone.verbose then 
			trigger.action.outText("+++clnZ: spawning - picked <" .. templateName .. "> as template", 30)
		end
		
		local newTemplate = cloneZones.getCloneZoneByName(templateName)
		if not newTemplate then 
			if cloneZones.verbose or theZone.verbose then 
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
		cloneZones.invokeCallbacks(theZone, "wiped", {})
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
				-- an easier/faster method would be to invoke 
				-- aGroup:getSize()
				local uNum = aGroup:getSize()
				if uNum > 0 then return true end 
				--[[
				local allUnits = aGroup:getUnits()
				for idy, aUnit in pairs(allUnits) do 
					if aUnit:isExist() and aUnit:getLife() >= 1 then 
						return true
					end
				end
				--]]--
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

--
-- UPDATE
--
function cloneZones.update()
	timer.scheduleFunction(cloneZones.update, {}, timer.getTime() + 1)
	
	for idx, aZone in pairs(cloneZones.cloners) do
		-- see if deSpawn was pulled. Must run before spawn
		if aZone.deSpawnFlag then 
			local currTriggerVal = cfxZones.getFlagValue(aZone.deSpawnFlag, aZone) -- trigger.misc.getUserFlag(aZone.deSpawnFlag)
			if currTriggerVal ~= aZone.lastDeSpawnValue then 
				if cloneZones.verbose or aZone.verbose then 
					trigger.action.outText("+++clnZ: DEspawn triggered for <" .. aZone.name .. ">", 30)
				end 
				cloneZones.despawnAll(aZone)
				aZone.lastDeSpawnValue = currTriggerVal
			end
		end
		
		-- see if we got spawn? command
		if cfxZones.testZoneFlag(aZone, aZone.spawnFlag, aZone.cloneTriggerMethod, "lastSpawnValue") then
			if cloneZones.verbose then 
				trigger.action.outText("+++clnZ: spawn triggered for <" .. aZone.name .. ">", 30)
			end 
			cloneZones.spawnWithCloner(aZone)
		end
		
		-- empty handling 
		local isEmpty = cloneZones.countLiveUnits(aZone) < 1 and aZone.hasClones		
		if isEmpty then 
			-- see if we need to bang a flag 
			if aZone.emptyFlag then 
				--cloneZones.pollFlag(aZone.emptyFlag)
				cfxZones.pollFlag(aZone.emptyFlag, 'inc', aZone)
			end 
			
			if aZone.emptyBangFlag then 
				cfxZones.pollFlag(aZone.emptyBangFlag, aZone.cloneMethod, aZone)
				if cloneZones.verbose then 
					trigger.action.outText("+++clnZ: bang! on " .. aZone.emptyBangFlag, 30)
				end
			end
			-- invoke callbacks 
			cloneZones.invokeCallbacks(aZone, "empty", {}) 
			
			-- prevent isEmpty next pass
			aZone.hasClones = false 
		end
		
	end
end

function cloneZones.doOnStart()
	for idx, theZone in pairs(cloneZones.cloners) do 
		if theZone.onStart then 
			if theZone.isStarted then 
				if cloneZones.verbose or theZone.verbose then 
					trigger.action.outText("+++clnZ: onStart pre-empted for <" .. theZone.name .. "> by persistence", 30)
				end
			else 
				if cloneZones.verbose or theZone.verbose then 
					trigger.action.outText("+++clnZ: onStart spawing for <"..theZone.name .. ">", 30)
				end
				cloneZones.spawnWithCloner(theZone) 
			end
		end 
	end
end

--
-- Regular GC and housekeeping
--
function cloneZones.GC()
	-- GC run. remove all my dead remembered troops
	local filteredAttackers = {}
	for gName, gData in pairs (cloneZones.allClones) do 
		-- all we need to do is get the group of that name
		-- and if it still returns units we are fine 
		local gameGroup = Group.getByName(gName)
		if gameGroup and gameGroup:isExist() and gameGroup:getSize() > 0 then 
			-- we now filter for categories. we currently only let 
			-- ground units pass 
			-- better make this configurabele by option later 
			if gData.cat == 0 and false then -- block aircraft  
			elseif gData.cat == 1 and false then -- block helos
			elseif gData.cat == 2 and false then -- block ground
			elseif gData.cat == 3 and false then -- block ship
			elseif gData.cat == 4 and false then -- block trains
			else
				-- not filtered, persist 
				filteredAttackers[gName] = gData
			end 
		end
	end
	cloneZones.allClones = filteredAttackers
	
	filteredAttackers = {}
	for gName, gData in pairs (cloneZones.allCObjects) do 
		-- all we need to do is get the group of that name
		-- and if it still returns units we are fine 
		local theObject = StaticObject.getByName(gName)
		if theObject and theObject:isExist() then 
			filteredAttackers[gName] = gData
			if theObject:getLife() < 1 then 
				gData.dead = true 
			end 
		end
	end
	cloneZones.allCObjects = filteredAttackers
end

function cloneZones.houseKeeping()
	timer.scheduleFunction(cloneZones.houseKeeping, {}, timer.getTime() + 5 * 60) -- every 5 minutes 
	cloneZones.GC()
end


--
-- LOAD / SAVE 
--
function cloneZones.synchGroupMXData(theData)
	-- we iterate the group's units one by one and update them 
	local newUnits = {}
	local allUnits = theData.units 
	for idx, unitData in pairs(allUnits) do 
		local uName = unitData.name 
		local gUnit = Unit.getByName(uName)
		if gUnit and gUnit:isExist() then 
			unitData.heading = dcsCommon.getUnitHeading(gUnit)
			pos = gUnit:getPoint()
			unitData.x = pos.x
			unitData.y = pos.z -- (!!)
			-- add aircraft handling here (alt, speed etc)
			-- perhaps even curtail route 
			table.insert(newUnits, unitData)
		end
	end
	theData.units = newUnits 
end

function cloneZones.synchMXObjData(theData)
	local oName = theData.name 
	local theObject = StaticObject.getByName(oName)
	theData.heading = dcsCommon.getUnitHeading(theObject)
	pos = theObject:getPoint()
	theData.x = pos.x
	theData.y = pos.z -- (!!)
	theData.isDead = theObject:getLife() < 1
	theData.dead = theData.isDead
end

function cloneZones.saveData()
	local theData = {}
	local allCloneData = {}
	local allSOData = {}
	-- run a GC pre-emptively 
	cloneZones.GC()
	
	-- now simply iterate and save all deployed clones 
	for gName, gData in pairs(cloneZones.allClones) do 
		local sData = dcsCommon.clone(gData)
		cloneZones.synchGroupMXData(sData)
		allCloneData[gName] = sData
	end

	-- now simply iterate and save all deployed clones 
	for gName, gData in pairs(cloneZones.allCObjects) do 
		local sData = dcsCommon.clone(gData)
		cloneZones.synchMXObjData(sData)
		allSOData[gName] = sData
	end
	
	-- now save all cloner stati 
	local cloners = {}
	for idx, theCloner in pairs(cloneZones.cloners) do 
		local cData = {}
		local cName = theCloner.name 
		cData.myUniqueCounter = theCloner.myUniqueCounter
		
		-- mySpawns: all groups i'm curently observing for empty!
		-- myStatics: dto for objects 
		local mySpawns = {}
		for idx, aGroup in pairs(theCloner.mySpawns) do 
			if aGroup and aGroup:isExist() and aGroup:getSize() > 0 then 
				table.insert(mySpawns, aGroup:getName())
			end
		end
		cData.mySpawns = mySpawns
		local myStatics = {}
		for idx, aStatic in pairs(theCloner.myStatics) do 
			table.insert(myStatics, aStatic:getName())
		end
		cData.myStatics = myStatics
		cData.isStarted = theCloner.isStarted -- to prevent onStart 
		cloners[cName] = cData
	end 


	-- save globals 
	theData.cuid = cloneZones.uniqueCounter -- replace whatever is larger 
    theData.uuid = dcsCommon.simpleUUID -- replace whatever is larger 
	theData.globalCount = cloneZones.globalCount 
	
	-- save to struct and pass back 
	theData.clones = allCloneData	
	theData.objects = allSOData
	theData.cloneZones = cloners 
	
	return theData
end

function cloneZones.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("cloneZones")
	if not theData then 
		if cloneZones.verbose then 
			trigger.action.outText("+++clnZ: no save date received, skipping.", 30)
		end
		return
	end
	
	-- spawn all units 
	local allClones = theData.clones
	for gName, gData in pairs (allClones) do 
		local cty = gData.cty 
		local cat = gData.cat  
		
		-- now spawn, but first 
		-- add to my own deployed queue so we can save later 
		local gdClone = dcsCommon.clone(gData)
		cloneZones.allClones[gName] = gdClone 
		local theGroup = coalition.addGroup(cty, cat, gData)
	end
	
	-- spawn all static objects 
	local allObjects = theData.objects 
	for oName, oData in pairs(allObjects) do 
		local newStatic = dcsCommon.clone(oData)
		-- add link info if it exists
		newStatic.linkUnit = cfxMX.linkByName[oName]
		if newStatic.linkUnit and cloneZones.verbose then 
				trigger.action.outText("+++clnZ: linked static <" .. oName .. "> to unit <" .. newStatic.linkUnit .. ">", 30)
		end
		local cty = newStatic.cty 
--		local cat = staticData.cat
		-- spawn new one, replacing same.named old, dead if required 
		gStatic =  coalition.addStaticObject(cty, newStatic)
		
		-- processing for cargoManager 
		if oData.canCargo then 
			if cfxCargoManager then 
				cfxCargoManager.addCargo(gStatic)
			end
		end
		
		-- add the original data block to be remembered
		-- for next save 
		cloneZones.allCObjects[oName] = oData 
	end
	
	-- now update all spawners and reconnect them with their spawns
	local allCloners = theData.cloneZones
	for cName, cData in pairs(allCloners) do 
		local theCloner = cloneZones.getCloneZoneByName(cName)
		if theCloner then 
			theCloner.isStarted = true -- ALWAYS TRUE WHEN WE COME HERE! cData.isStarted
			-- init myUniqueCounter if it exists 
			if cData.myUniqueCounter then 
				theCloner.myUniqueCounter = cData.myUniqueCounter
			end
			
			local mySpawns = {}
			for idx, aName in pairs(cData.mySpawns) do 
				local theGroup = Group.getByName(aName)
				if theGroup then 
					table.insert(mySpawns, theGroup)
				else
					trigger.action.outText("+++clnZ - persistence: can't reconnect cloner <" .. cName .. "> with clone group <".. aName .. ">", 30)
				end
			end
			theCloner.mySpawns = mySpawns
			
			local myStatics = {}
			for idx, aName in pairs(cData.myStatics) do 
				local theStatic = StaticObject.getByName(aName)
				if theStatic then 
					table.insert(myStatics, theStatic)
				else
					trigger.action.outText("+++clnZ - persistence: can't reconnect cloner <" .. cName .. "> with static <".. aName .. ">", 30)
				end
			end
			theCloner.myStatics = myStatics
		else 
			trigger.action.outText("+++clnZ - persistence: cannot synch cloner <" .. cName .. ">, does not exist", 30)
		end
	end
	
	-- finally, synch uid and uuid 
	if theData.cuid and theData.cuid > cloneZones.uniqueCounter then 
		cloneZones.uniqueCounter = theData.cuid
	end
	if theData.uuiD and theData.uuid > dcsCommon.simpleUUID  then 
		dcsCommon.simpleUUID  = theData.uuid 
	end
	if theData.globalCount and theData.globalCount > cloneZones.globalCount then 
		cloneZones.globalCount = theData.globalCount
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
	
	if cfxZones.hasProperty(theZone, "uniqueCount") then 
		cloneZones.uniqueCounter = cfxZones.getNumberFromZoneProperty(theZone, "uniqueCount", cloneZone.uniqueCounter)
	end
	
	if cfxZones.hasProperty(theZone, "localCount") then 
		cloneZones.lclUniqueCounter = cfxZones.getNumberFromZoneProperty(theZone, "localCount", cloneZone.lclUniqueCounter)
	end
	
	if cfxZones.hasProperty(theZone, "globalCount") then 
		cloneZones.globalCounter = cfxZones.getNumberFromZoneProperty(theZone, "globalCount", cloneZone.globalCounter)
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
	
	-- update all cloners and spawned clones from file 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = cloneZones.saveData
		persistence.registerModule("cloneZones", callbacks)
		-- now load my data 
		cloneZones.loadData()
	end
	
	-- schedule onStart, and leave at least a few
	-- cycles to go through object removal
	-- persistencey has loaded isStarted if a cloner was 
	-- already started 
	timer.scheduleFunction(cloneZones.doOnStart, {}, timer.getTime() + 1.0)
	
	-- start update 
	cloneZones.update()
	
	-- start housekeeping 
	cloneZones.houseKeeping()
	
	trigger.action.outText("cfx Clone Zones v" .. cloneZones.version .. " started.", 30)
	return true 
end


-- let's go!
if not cloneZones.start() then 
	trigger.action.outText("cf/x Clone Zones aborted: missing libraries", 30)
	cloneZones = nil 
end


--[[--
	to resolve tasks 

	- AFAC 
		- FAC Assign group 
	- set freq for unit 
	
	-- fixedName: immutable name, no safe renaming. always use ID and name without changing it. very special use case.
	nameTest - optional safety / debug feature that will name-test each unit that is about to be spawned for replacement. Maybe auto turn on when verbose is set?
	identical - make a clone of template and do not touch name nor id. will fully replace 
	make example where transport can be different plane types but have same name 
--]]--