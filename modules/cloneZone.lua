cloneZones = {}
cloneZones.version = "2.0.1"
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
	Copyright (c) 2022-2024 by Christian Franz and cf/x AG
	
	Version History
	1.9.0 - minor clean-up for synonyms
		  - spawnWithSpawner alias for HeloTroops etc requestable SPAWN
		  - requestable attribute 
		  - cooldown attribute 
		  - cloner collects all types used 
		  - groupScheme attribute
	1.9.1 - useAI attribute 
	2.0.0 - clean-up 
	2.0.1 - improved empty! logic to account for deferred spawn 
		    when pre-wipe is active 
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

--
-- reading zones
--
function cloneZones.partOfGroupDataInZone(theZone, theUnits)
	local zP = cfxZones.getPoint(theZone)
	zP = theZone:getDCSOrigin() -- don't use getPoint now.
	zP.y = 0
	
	for idx, aUnit in pairs(theUnits) do 
		local uP = {}
		uP.x = aUnit.x 
		uP.y = 0
		uP.z = aUnit.y -- !! y-z
		--local dist = dcsCommon.dist(uP, zP)
		--if dist <= theZone.radius then return true  end 
		if theZone:pointInZone(uP) then return true end 
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
	theZone.spawnWithSpawner = cloneZones.spawnWithSpawner
	theZone.myUniqueCounter = cloneZones.lclUniqueCounter -- init local counter
	
	local localZones = cloneZones.allGroupsInZoneByData(theZone)  
	local localObjects = theZone:allStaticsInZone(true) -- true = use DCS origin, not moved zone
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
	-- use getDCSOrigin instead 
	theZone.origin = theZone:getDCSOrigin() 
	
	-- source tells us which template to use. it can be the following:
	-- nothing (no attribute) - then we use whatever groups are in zone to 
	-- spawn as template 
	-- name of another spawner that provides the template 
	-- we can't simply use a group name as we lack the reference 
	-- location for delta 
	if theZone:hasProperty("source") then 
		theZone.source = theZone:getStringFromZoneProperty("source", "<none>")
		if theZone.source == "<none>" then theZone.source = nil end 
	end 
	theZone.allTypes = {} -- names of all types
	
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
				-- iterate all units and save their individual types
				for idy, aUnit in pairs(rawData.units) do 
					local theType = aUnit.type 
					if not theZone.allTypes[theType] then 
						theZone.allTypes[theType] = 1 -- first one
					else 
						theZone.allTypes[theType] = theZone.allTypes[theType] + 1 -- increment
					end 
				end 
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
	
	-- declutter 
	theZone.declutter = theZone:getBoolFromZoneProperty("declutter", false)
	
	-- watchflags
	theZone.cloneTriggerMethod = theZone:getStringFromZoneProperty("triggerMethod", "change")

	if theZone:hasProperty("cloneTriggerMethod") then 
		theZone.cloneTriggerMethod = theZone:getStringFromZoneProperty("cloneTriggerMethod", "change")
	end
	
	-- f? and spawn? and other synonyms map to the same 
	if theZone:hasProperty("f?") then 
		theZone.spawnFlag = theZone:getStringFromZoneProperty("f?", "none")
	elseif theZone:hasProperty("in?") then 
		theZone.spawnFlag = theZone:getStringFromZoneProperty("in?", "none")
	elseif theZone:hasProperty("spawn?") then 
		theZone.spawnFlag = theZone:getStringFromZoneProperty("spawn?", "none")
	elseif theZone:hasProperty("clone?") then 
		theZone.spawnFlag = theZone:getStringFromZoneProperty("clone?", "none")
	end
	
	if theZone.spawnFlag then 
		theZone.lastSpawnValue = theZone:getFlagValue(theZone.spawnFlag)
	end
	
	-- deSpawn?
	if theZone:hasProperty("deSpawn?") then 
		theZone.deSpawnFlag = theZone:getStringFromZoneProperty( "deSpawn?", "none")
	elseif theZone:hasProperty("deClone?") then 
		theZone.deSpawnFlag = theZone:getStringFromZoneProperty( "deClone?", "none")
	elseif theZone:hasProperty("wipe?") then 
		theZone.deSpawnFlag = theZone:getStringFromZoneProperty("wipe?", "none")
	end
	
	if theZone.deSpawnFlag then 
		theZone.lastDeSpawnValue = theZone:getFlagValue(theZone.deSpawnFlag)
	end
	
	theZone.cooldown = theZone:getNumberFromZoneProperty("cooldown", -1) -- anything > 0 activates cd 
	theZone.lastSpawnTimeStamp = -10000
	theZone.onStart = theZone:getBoolFromZoneProperty("onStart", false)
	theZone.moveRoute = theZone:getBoolFromZoneProperty("moveRoute", false)
	theZone.preWipe = theZone:getBoolFromZoneProperty("preWipe", false)
		
	if theZone:hasProperty("empty!") then 
		theZone.emptyBangFlag = theZone:getStringFromZoneProperty("empty!", "<None>") -- note string on number default
	end
	
	theZone.cloneMethod = theZone:getStringFromZoneProperty("cloneMethod", "inc")
	if theZone:hasProperty("method") then 
		theZone.cloneMethod = theZone:getStringFromZoneProperty("method", "inc") -- note string on number default
	end
	
	if theZone:hasProperty("masterOwner") then 
		theZone.masterOwner = theZone:getStringFromZoneProperty( "masterOwner", "*")
		theZone.masterOwner = dcsCommon.trim(theZone.masterOwner)
		if theZone.masterOwner == "*" then 
			theZone.masterOwner = theZone.name 
			if theZone.verbose then 
				trigger.action.outText("+++clnZ: masterOwner for <" .. theZone.name .. "> set successfully to to itself, currently owned by faction <" .. theZone.owner .. ">", 30)
			end
		end
		if theZone.verbose or cloneZones.verbose then 
			trigger.action.outText("+++clnZ: ownership of <" .. theZone.name .. "> tied to zone <" .. theZone.masterOwner .. ">", 30)
		end
		-- check that the zone exists in DCS 
		local theMaster = cfxZones.getZoneByName(theZone.masterOwner)
		if not theMaster then 
			trigger.action.outText("clnZ: WARNING: cloner's <" .. theZone.name .. "> master owner named <" .. theZone.masterOwner .. "> does not exist!", 30)
		end
	end
	
	theZone.turn = theZone:getNumberFromZoneProperty("turn", 0)
	
	-- interface to groupTracker 
	if theZone:hasProperty("trackWith:") then 
		theZone.trackWith = theZone:getStringFromZoneProperty( "trackWith:", "<None>")
	end

	-- interface to delicates
	if theZone:hasProperty("useDelicates") then 
		theZone.delicateName = dcsCommon.trim(theZone:getStringFromZoneProperty("useDelicates", "<none>"))
		if theZone.delicateName == "*" then theZone.delicateName = theZone.name end 
		if theZone.verbose then 
			trigger.action.outText("+++clnZ: cloner <" .. theZone.name .."> hands off delicates to <" .. theZone.delicateName .. ">", 30)
		end
	end

	-- interface to requestable, must be unsourced!
	if theZone:hasProperty("requestable") then 
		theZone.requestable = theZone:getBoolFromZoneProperty( "requestable", false)
		theZone.baseName = theZone.name -- backward compatibility with HeloTroops 
		if theZone.source then 
			trigger.action.outText("WARNING: cloner <" .. theZone.name .. "> has 'source' attribute and is marked 'requestable' - this can result in unrequestable clones", 30)
		end
	end

	-- randomized locations on spawn 
	theZone.rndLoc = theZone:getBoolFromZoneProperty("randomizedLoc", false)
	if theZone:hasProperty("rndLoc") then 
		theZone.rndLoc = theZone:getBoolFromZoneProperty("rndLoc", false)
	end 
	theZone.centerOnly = theZone:getBoolFromZoneProperty("centerOnly", false)
	if theZone:hasProperty("wholeGroups") then 
		theZone.centerOnly = theZone:getBoolFromZoneProperty( "wholeGroups", false)
	end
	if theZone:hasProperty("inBuiltup") then 
		theZone.inBuiltup = theZone:getNumberFromZoneProperty("inBuiltup", 10) -- 10 meter radius must be free -- small houses
	end 
	theZone.rndHeading = theZone:getBoolFromZoneProperty("rndHeading", false)
	
	theZone.onRoad = theZone:getBoolFromZoneProperty("onRoad", false)
	theZone.onPerimeter = theZone:getBoolFromZoneProperty("onPerimeter", false)

	-- check for name scheme and / or identical 
	if theZone:hasProperty("identical") then
		theZone.identical = theZone:getBoolFromZoneProperty("identical", false)
		if theZone.identical == false then theZone.identical = nil end 
	end 
	
	if theZone:hasProperty("nameScheme") then 
		theZone.nameScheme = theZone:getStringFromZoneProperty( "nameScheme", "<o>-<uid>") -- default to [<original name> "-" <uuid>] 
	end
	
	if theZone:hasProperty("groupScheme") then 
		theZone.groupScheme = theZone:getStringFromZoneProperty("groupScheme", "<o>-<uid>")
	end 
	
	if theZone.identical and theZone.nameScheme then
		trigger.action.outText("+++clnZ: WARNING - clone zone <" .. theZone.name .. "> has both IDENTICAL and NAMESCHEME/GROUPSCHEME attributes. nameScheme is ignored.", 30)
		theZone.nameScheme = nil
		theZone.groupScheme = nil 
	end
	
	theZone.useAI = theZone:getBoolFromZoneProperty("useAI", true)
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
	
	return outName, iter
end

function cloneZones.uniqueID()
	local uid = cloneZones.uniqueCounter
	cloneZones.uniqueCounter = cloneZones.uniqueCounter + 1
	return uid 
end

function cloneZones.uniqueNameGroupData(theData, theCloneZone, sourceName)
	if not sourceName then sourceName = theCloneZone.name end 
	if not theCloneZone.groupScheme then 
		theData.name = dcsCommon.uuid(theData.name)
	else 
		theData.name = cloneZones.nameFromSchema(theCloneZone.groupScheme, theData.name, theCloneZone, sourceName, 1)
	end 
	
	local schema = theCloneZone.nameScheme	
	local units = theData.units 
	local iterCount = 1 
	local newName = "none"
	local allNames = {} -- enforce unique names inside group
	for idx, aUnit in pairs(units) do 
		if theCloneZone and theCloneZone.nameScheme then
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
							end
							-- store this as new group for 
							-- translated transportID
							newDist[newUnit] = newEmbarkers
						end
						-- replace old distribution with new 
						taskData.params.distribution = newDist 
					end
					
					-- resolve selectedTransport unit reference 
					if taskData.id and taskData.params and taskData.params.selectedTransportt then
						local tID = taskData.params.selectedTransport
						local newTID = cloneZones.resolveUnitID(tID, rawData, dataTable, "transportID")
						taskData.params.selectedTransport = newTID
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

-- forcedRespan respawns a group when the previous spawn of a 
-- group did not match the ID that it was supposed to match 
function cloneZones.forcedRespawn(args)
	local theData = args[1]
	local spawnedGroups = args[2]
	local pos = args[3]
	local theZone = args[4]
	local verbose = theZone.verbose
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
			trigger.action.outText("will replace table entry at <" .. pos .. "> with new group", 30)
		end
		spawnedGroups[pos] = theGroup
		
		-- since we are now successful, check if we need to apply 
		-- delicate status 
		if theZone.delicateName and delicates then 
			-- pass this object to the delicate zone mentioned 
			local theDeli = delicates.getDelicatesByName(theZone.delicateName)
			if theDeli then 
				delicates.addGroupToInventoryForZone(theDeli, theGroup)
			else 
				trigger.action.outText("+++clnZ: spawner <" .. theZone.name .. "> can't find delicates zone <" .. theZone.delicateName .. ">", 30)
			end
		elseif theZone.delicateName then 
			trigger.action.outText("+++clnZ: WARNING - cloner <> requires 'Delicates' module.", 30)
		end
		
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
	-- spawnZone is the spawner with SETTINGS and DESTINATION (target location) where the clones are poofed into existence 
	local newCenter = spawnZone:getPoint() -- includes zone following updates
	local oCenter = theZone:getDCSOrigin() -- get original coords on map for cloning offsets 
	-- calculate zoneDelta, is added to all vectors 
	local zoneDelta = dcsCommon.vSub(newCenter, theZone.origin) 
	
	-- precalc turn value for linked rotation
	local dHeading = 0 -- for linked zones 
	local rotCenter = nil 
	if spawnZone.linkedUnit and spawnZone.uHdg and spawnZone.useHeading and Unit.isExist(spawnZone.linkedUnit) then 
		local theUnit = spawnZone.linkedUnit
		local currHeading = dcsCommon.getUnitHeading(theUnit)
		dHeading = currHeading - spawnZone.uHdg
		rotCenter = spawnZone:getPoint()
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
		
		-- update routes when not spawning same location 
		cloneZones.updateLocationsInGroupData(rawData, zoneDelta, spawnZone.moveRoute, rotCenter, spawnZone.turn / 57.2958 +
		dHeading)
		
		-- apply randomizer if selected 
		if spawnZone.rndLoc then 
			-- calculate the entire group's displacement
			local units = rawData.units

			local loc, dx, dy 
			if spawnZone.onPerimeter then 
				loc, dx, dy = spawnZone:createRandomPointOnZoneBoundary()
			elseif spawnZone.inBuiltup then 
				loc, dx, dy = spawnZone:createRandomPointInPopulatedZone(spawnZone.inBuiltup)
			else 
				loc, dx, dy = spawnZone:createRandomPointInZone() -- also supports polygonal zones 
			end 
			
			for idx, aUnit in pairs(units) do 
				if not spawnZone.centerOnly then 
					-- *every unit's displacement is randomized
					if spawnZone.onPerimeter then 
						loc, dx, dy = spawnZone:createRandomPointOnZoneBoundary()
					elseif spawnZone.inBuiltup then 
						loc, dx, dy = spawnZone:createRandomPointInPopulatedZone(spawnZone.inBuiltup)
					else	
						loc, dx, dy = spawnZone:createRandomPointInZone()
					end 
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
		-- set AI on or off 
		rawData.useAI = spawnZone.useAI 
		table.insert(dataToSpawn, rawData)
	end 
	
	-- now resolve references to other cloned units for all raw data
	-- we must do this BEFORE we spawn
	cloneZones.resolveReferences(theZone, dataToSpawn)
	
	-- now spawn all raw data 
	local groupCollector = {} -- to detect cross-group conflicts
	local unitCollector = {} -- to detect cross-group conflicts 
	local theGroup = nil -- init to empty, on this level 
	for idx, rawData in pairs (dataToSpawn) do 
		-- now spawn and save to clones
		-- first norm and clone data for later save
		rawData.cty = rawData.CZctry 
		rawData.cat = rawData.CZtheCat
				
		-- make group, unit[1] and route point [1] all match up
		if rawData.route and rawData.units[1] then 
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
		theGroup = coalition.addGroup(rawData.CZctry, rawData.CZtheCat, rawData)
		table.insert(spawnedGroups, theGroup)
				
		-- turn off AI if disabled 
		if not rawData.useAI then 
			cloneZones.turnOffAI({theGroup})
		end 
		
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
		
		-- check if our assigned ID matches the one handed out by 
		-- DCS. Mismatches can happen, and are only noted 
		if newGroupID == rawData.CZTargetID then 
			-- we are good, all processing correct 
			-- add to delicates if set 
			if spawnZone.delicateName and delicates then 
				-- pass this object to the delicate zone mentioned 
				local theDeli = delicates.getDelicatesByName(spawnZone.delicateName)
				if theDeli then 
					delicates.addGroupToInventoryForZone(theDeli, theGroup)
				else 
					trigger.action.outText("+++clnZ: spawner <" .. spawnZone.name .. "> can't find delicates zone <" .. spawnZone.delicateName .. ">", 30)
				end
			end
		else 
			if cloneZones.verbose or spawnZone.verbose then 
				trigger.action.outText("clnZ: Note: GROUP ID spawn changed for <" .. rawData.name .. ">: target ID " .. rawData.CZTargetID .. " (target) returns " .. newGroupID .. " (actual) in <" .. spawnZone.name .. ">", 30)
				
			end
			
			if cloneZones.respawnOnGroupID then 
				-- remember pos in table, will be changed after
				-- respawn 
				local pos = #spawnedGroups
				
				timer.scheduleFunction(cloneZones.forcedRespawn, {theData, spawnedGroups, pos, spawnZone}, timer.getTime() + 2) -- initial gap: 2 seconds for DCS to sort itself out
				-- note that this can in extreme cases result in 
				-- unitID mismatches, but his is extremely unlikely 
			else 
				-- we note it in the spawn data for the group so
				-- persistence works fine 
				theData.groupId = newGroupID
				-- since we keep these, we make them brittle if required
				if spawnZone.delicateName and delicates then 
					-- pass this object to the delicate zone mentioned 
					local theDeli = delicates.getDelicatesByName(spawnZone.delicateName)
					if theDeli then 
						delicates.addGroupToInventoryForZone(theDeli, theGroup)
					else 
						trigger.action.outText("+++clnZ: spawner <" .. spawnZone.name .. "> can't find delicates zone <" .. spawnZone.delicateName .. ">", 30)
					end
				end
		
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

			local loc, dx, dy 
			if spawnZone.onPerimeter then 
				loc, dx, dy = spawnZone:createRandomPointOnZoneBoundary()
			elseif spawnZone.inBuiltup then 
				loc, dx, dy = spawnZone:createRandomPointInPopulatedZone(spawnZone.inBuiltup)
			else 
				loc, dx, dy = spawnZone:createRandomPointInZone() -- also supports polygonal zones 
			end
			rawData.x = rawData.x + dx -- might want to use loc 
			rawData.y = rawData.y + dy -- directly
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
			trigger.action.outText("+++clnZ: new Static clone " .. aStaticName, 30)
		end 
		
		-- processing for delicates 
		if spawnZone.delicateName and delicates then 
			-- pass this object to the delicate zone mentioned 
			local theDeli = delicates.getDelicatesByName(spawnZone.delicateName)
			if theDeli then 
				delicates.addStaticObjectToInventoryForZone(theDeli, theStatic)
			else 
				trigger.action.outText("+++cnlZ: cloner <" .. aZone.name .. "> can't find delicates <" .. spawnZone.delicateName .. ">", 30)
			end
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

function cloneZones.turnOffAI(args)
	local theGroup = args[1]
	local theController = theGroup:getController()
	theController:setOnOff(false)
end 

-- retro-fit for helo troops and others to provide 'requestable' support 
function cloneZones.spawnWithSpawner(theZone)
	-- analog to cfxSpawnZones.spawnWithSpawner(theSpawner)
	-- glue code for helo troops and other modules 
	
	-- we may want to check if cloner isn't emtpy first 
	
	cloneZones.spawnWithCloner(theZone)
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
	
	-- see if we are on cooldown. If so, exit 
	if theZone.cooldown > 0 then 
		local now = timer.getTime() 
		if now < theZone.lastSpawnTimeStamp + theZone.cooldown then 
			if theZone.verbose or cloneZones.verbose then 
				trigger.action.outText("+++clnZ: cloner <" .. theZone.name .. "> still on cool-down, no clone cycle", 30)
			end 
			return
		else 
			theZone.lastSpawnTimeStamp = now 
		end 
	end 
	
	-- force spawn with this spawner 
	local templateZone = theZone
	if theZone.source then 
		-- we use a different zone for templates
		-- source can be a comma separated list
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
	local didPrewipe = false 
	if theZone.preWipe then 
		cloneZones.despawnAll(theZone)
		cloneZones.invokeCallbacks(theZone, "wiped", {})
		didPrewipe = true 
	end
	
	-- declutter?
	if theZone.declutter then 
		theZone:declutterZone()
		if theZone.verbose then 
			trigger.action.outText("+++clnZ: cloner <" .. theZone.name .. "> declutter complete.", 30)
		end
	end
	
	local args = {theZone = theZone, templateZone = templateZone}
	if didPrewipe then -- delay spawning to allow revoval to take place
		timer.scheduleFunction(cloneZones.doClone, args, timer.getTime() + 0.5)
	else -- can do immediately 
		cloneZones.doClone(args)
	end

end

-- deferrable clone method.
function cloneZones.doClone(args)
	local theZone = args.theZone
	local templateZone = args.templateZone
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
				local uNum = aGroup:getSize()
				if uNum > 0 then return true end 
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

function cloneZones.resolveOwningCoalition(theZone)
	if not theZone.masterOwner then return theZone.owner end 
	local masterZone = cfxZones.getZoneByName(theZone.masterOwner)
	if not masterZone then 
		trigger.action.outText("+++clnZ: cloner " .. theZone.name .. " could not find master owner <" .. theZone.masterOwner .. ">", 30)
		return theZone.owner 
	end
	return masterZone.owner 
end

function cloneZones.getRequestableClonersInRange(aPoint, aRange, aSide)
	if not aSide then aSide = 0 end  
	if not aRange then aRange = 200 end 
	if not aPoint then return {} end 

	local theSpawners = {}
	for idx, aZone in pairs(cloneZones.cloners) do 
		-- iterate all zones and collect those that match 
		local hasMatch = true 
		local delta = dcsCommon.distFlat(aPoint, aZone:getPoint())
		if delta > aRange then hasMatch = false end 
		if aSide ~= 0 then 
			-- check if side is correct for owned zone 
			local resolved = cloneZones.resolveOwningCoalition(aZone)
			if resolved == 0 or resolved ~= aSide then			
				-- failed ownership test. must match and not be zero
				hasMatch = false
			end
		end
				
		if not aZone.requestable then 
			hasMatch = false 
		end
		
		if hasMatch then 
			table.insert(theSpawners, aZone)
		end
	end
	
	return theSpawners
end

--
-- UPDATE
--
function cloneZones.update()
	timer.scheduleFunction(cloneZones.update, {}, timer.getTime() + 1)
	
	for idx, aZone in pairs(cloneZones.cloners) do
		-- see if deSpawn was pulled. Must run before spawn
		if aZone.deSpawnFlag then 
			local currTriggerVal = aZone:getFlagValue(aZone.deSpawnFlag) 
			if currTriggerVal ~= aZone.lastDeSpawnValue then 
				if cloneZones.verbose or aZone.verbose then 
					trigger.action.outText("+++clnZ: DEspawn triggered for <" .. aZone.name .. ">", 30)
				end 
				cloneZones.despawnAll(aZone)
				aZone.lastDeSpawnValue = currTriggerVal
			end
		end
		
		-- see if we got spawn? command
		local willSpawn = false -- init to false.
		if aZone:testZoneFlag(aZone.spawnFlag, aZone.cloneTriggerMethod, "lastSpawnValue") then
			if cloneZones.verbose or aZone.verbose then 
				trigger.action.outText("+++clnZ: spawn triggered for <" .. aZone.name .. ">", 30)
			end 
			cloneZones.spawnWithCloner(aZone)
			willSpawn = true -- in case prewipe, we delay
			-- can mess with empty, so we tell empty to skip 
		end
		
		-- empty handling 
		local isEmpty = cloneZones.countLiveUnits(aZone) < 1 and aZone.hasClones		
		if isEmpty and (willSpawn == false) then 
			-- see if we need to bang a flag 			
			if aZone.emptyBangFlag then 
				aZone:pollFlag(aZone.emptyBangFlag, aZone.cloneMethod)
				if cloneZones.verbose or aZone.verbose then 
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
		-- turn off AI if disabled 
		if not gData.useAI then 
			cloneZones.turnOffAI({theGroup})
		end 
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
			theCloner.isStarted = true 
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
		theZone = cfxZones.createSimpleZone("cloneZonesConfig") 
	end 
	
	if theZone:hasProperty("uniqueCount") then 
		cloneZones.uniqueCounter = theZone:getNumberFromZoneProperty("uniqueCount", cloneZone.uniqueCounter)
	end
	
	if theZone:hasProperty("localCount") then 
		cloneZones.lclUniqueCounter = theZone:getNumberFromZoneProperty("localCount", cloneZone.lclUniqueCounter)
	end
	
	if theZone:hasProperty("globalCount") then 
		cloneZones.globalCounter = theZone:getNumberFromZoneProperty("globalCount", cloneZone.globalCounter)
	end
	
	cloneZones.verbose = theZone:getBoolFromZoneProperty("verbose", false)
	
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
	for k, aZone in pairs(attrZones) do 
		cloneZones.createClonerWithZone(aZone) -- process attribute and add to zone
		cloneZones.addCloneZone(aZone) 
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
	
	nameTest - optional safety / debug feature that will name-test each unit that is about to be spawned for replacement. Maybe auto turn on when verbose is set?
	make example where transport can be different plane types but have same name 
--]]--