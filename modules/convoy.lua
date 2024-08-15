convoy = {}
convoy.version = "1.1.0"
convoy.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
	"cfxMX",
}
convoy.zones = {}
convoy.convoys = {} -- running convoys 
convoy.ups = 1

convoy.convoyWPReached = {} 
convoy.convoyAttacked = {}
convoy.convoyDestroyed = {}
convoy.convoyArrived = {}
convoy.roots = {} -- group comms 
convoy.uuidNum = 1

--[[--
A DML module (C) 2024 by Christian Franz 

VERSION HISTORY
1.0.0 - Initial version 
1.1.0 - MUCH better reporting for all coalitions 
	  - remaining unit count on successful attack in reports 
	  - warning when arriving at penultimate 
	  - corrected method for polling when dead etc.
	  - anon name for reporting
	  - anon uuid 
	  - actionSound
	  - support for attachTo: 
	  - warning when not onStart and no start?
	  - say hi 
	  - removed destination attribute 
	  
--]]--

--[[-- CONVOY Structure
	.name  (uuid) name of convoy 
	.dest destination string, defaulted from theZone.destinations
	.destObject destination object from theZone.destobject 
	.waypoints array of vec3 points, one for each wp 
	.currWP -- index of last WP reached, inited to 1 on start 
	.origin zone where convoy spawned 
	.groups array groups (only one element) that this convoy consists of, ground only
	.helos array if defined, helicopters escorting.0 One group only 
	.groupSizes dict by groupname of group size to detect loss, updated 
	.lastAttackReport in time seconds since last report to enable pauses between reports 
	.coa coalition this convay belongs to  
	.reached indexed by waypoint. true if we reached that wp. 
	.distance = total length of route 
	.oName = original name of gorup 
	.desc = name, from, to as text 
	.wasAttacked true after first successful attack, for remain count 
--]]--

--
-- Misc
--
function convoy.uuid()
	convoy.uuidNum = convoy.uuidNum + 1 
	return convoy.uuidNum
end
--
-- callbacks
--
function convoy.installWPCallback(theCB)
	table.insert(convoy.convoyWPReached, theCB)
end

function convoy.invokeWPCallbacks(theConvoy, wp, wpnum)
	for idx, cb in pairs(convoy.convoyWPReached) do 
		cb(theConvoy, wp, wpnum)
	end
end


function convoy.installAttackCallback(theCB)
	table.insert(convoy.convoyAttacked, theCB)
end

function convoy.invokeAttackedCallbacks(theConvoy)
	for idx, cb in pairs(convoy.convoyAttacked) do 
		cb(theConvoy)
	end
end


function convoy.installDestroyed(theCB)
	table.insert(convoy.convoyDestroyed, theCB)
end

function convoy.invokeDestroyedCallbacks(theConvoy)
	for idx, cb in pairs(convoy.convoyDestroyed) do 
		cb(theConvoy)
	end
end

function convoy.installArrived(theCB)
	table.insert(convoy.convoyArrived, theCB)
end
function convoy.invokeArrivedCallbacks(theConvoy)
	for idx, cb in pairs(convoy.convoyArrived) do 
		cb(theConvoy)
	end
end
--
-- Reading Zones 
--
function convoy.addConvoyZone(theZone)
	convoy.zones[theZone.name] = theZone
end 

function convoy.thereCanOnlyBeOne(theDict)
	for key, value in pairs (theDict) do 
		local ret = {}
		ret[key] = value 
		return ret
	end
end 


function convoy.readConvoyZone(theZone)
	theZone.coa = theZone:getCoalitionFromZoneProperty("coalition", 0)
	theZone.isDynamic = theZone:getBoolFromZoneProperty("dynamic", false)
	-- get groups inside me. 
	local myGroups, count = cfxMX.allGroupsInZoneByData(theZone, {"vehicle"})
	local myHelos = {} -- for spawning only. 
	local myHelos, hcount = cfxMX.allGroupsInZoneByData(theZone, {"helicopter"})

	if count < 1 then
		trigger.action.outText("cnvy: WARNING: convoy zone <" .. theZone.name .. "> has no vehicles.", 30)
	end
	
	-- process destinations for each vehicle group 
	local destinations = {}
	local destObjects = {}
	local distances = {}
	--local froms = {}
	for gName, gData in pairs (myGroups) do 
		local dest, destObj = convoy.getDestinationForData(gData)
		destinations[gName] = dest
		destObjects[gName] = destObj -- nearest DCS/DML objects 
		distances[gName] = convoy.getDistanceForData(gData)
		--froms[gName] = convoy.getSourceForData(theZone)
	end 
	
	theZone.myGroups = myGroups -- vehicles only. only one chosen per spawn
								-- detination calc'd on-demand if nil  
								-- dict by name 
	theZone.destinations = destinations 
	theZone.destObjects = destObjects 
	theZone.distances = distances
	theZone.froms = convoy.getSourceForData(theZone)
	
	theZone.myHelos = myHelos -- helos can only escort, don't count  
							  -- helos wonky with multi-groups because dcs 
							  -- linking to groups 
	theZone.identical = theZone:getBoolFromZoneProperty("identical", false)
	theZone.unique = not theZone.identical
	theZone.preWipe = theZone:getBoolFromZoneProperty("preWipe", false) or theZone.identical  
	theZone.endWipe = theZone:getBoolFromZoneProperty("endWipe", true)
	theZone.killWipeDelay = theZone:getNumberFromZoneProperty("killWipeDelay", 300) -- leave helos as angry hornets for a while (5 Min = 300s)
	
	theZone.pEscort = theZone:getNumberFromZoneProperty("pEscort", 100) -- in percent (= * 100)
	theZone.onStart = theZone:getBoolFromZoneProperty("onStart", false)
	theZone.wpUpdates = theZone:getBoolFromZoneProperty("wpUpdates", true)
	theZone.attackWarnings = theZone:getBoolFromZoneProperty("attackWarnings", true)
	if theZone:hasProperty("spawn?") then 
		theZone.spawnFlag = theZone:getStringFromZoneProperty("spawn?", "none")
		theZone.lastSpawnFlag = trigger.misc.getUserFlag(theZone.spawnFlag)
	else 
		if not theZone.onStart then 
			trigger.action.outText("+++CVY: Warning: Convoy zone <" .. theZone.name .. "> has disabled 'onStart' and has no 'spawn?' input. This convoy zone can't send out any convoys,", 30)
		end
	end
	--[[--
	if theZone:hasProperty("destination") then -- remove me
		theZone.destination = theZone:getStringFromZoneProperty("destination", "none")
	end 
	--]]--
	if theZone:hasProperty("dead!") then 
		theZone.deadOut = theZone:getStringFromZoneProperty("dead!", "none")
	end
	if theZone:hasProperty("attacked!") then 
		theZone.attackedOut = theZone:getStringFromZoneProperty("attacked!", "none")
	end
	if theZone:hasProperty("arrived!") then 
		theZone.arrivedOut = theZone:getStringFromZoneProperty("arrived!", "none")
	end
	-- wipe all existing vehicle and helos 
	for groupName, data in pairs(myGroups) do 
		local g = Group.getByName(groupName) 
		if g then 
			Group.destroy(g)
		end 
	end
	for groupName, data in pairs(myHelos) do 
		local g = Group.getByName(groupName) 
		if g then 
			Group.destroy(g)
		end 
	end 	
end

function convoy.getDistanceForData(theData)
	local total = 0
	if not theData then return 0 end 
	local route = theData.route
	local points = route.points 			
	local wpNum = #points 
	if wpNum < 2 then return 0 end 
	local i = 1 
	local t = points[1]
	local last = {x=t.x, y = 0, z = t.y}
	while i < wpNum do 
		i = i + 1
		local t = points[i]
		local now = {x=t.x, y = 0, z = t.y}
		total = total + dcsCommon.dist(last, now)
		last = now
	end 
	return total 
end

function convoy.getLocName(p) -- returns a string and bool (success)
	local msg = ""
	local success = false 
	if twn and towns then 
		local name, data, dist = twn.closestTownTo(p)
		local mdist= dist * 0.539957
		dist = math.floor(dist/100) / 10
		mdist = math.floor(mdist/100) / 10		
		local bear = dcsCommon.compassPositionOfARelativeToB(p, data.p)
		msg = dist .. "km/" .. mdist .."nm " .. bear .. " of " .. name
		success = true 
	end
	return msg, success
end

function convoy.getSourceForData(theZone)
	if twn and towns then 
		local currPoint = theZone:getPoint()
		local name, data, dist = twn.closestTownTo(currPoint)
		local mdist= dist * 0.539957
		dist = math.floor(dist/100) / 10 
		mdist = math.floor(mdist/100) / 10
		local bear = dcsCommon.compassPositionOfARelativeToB(currPoint, data.p)
		return dist .. "km/" .. mdist .. "nm " .. bear .. " of " .. name
	end
	return theZone.name
end

function convoy.getDestinationForData(theData)
	-- dest is filled with town data if available
	-- destObject is nearest dmlZone or airfield, whatever closest 
	local dest = "unknown"
	local destObj
	local destType
	if theData then 
		-- access route points 
		local route = theData.route
		local points = route.points 			
		local wpnum = #points 
		local lastWP = points[wpnum]
		local thePoint = {x=lastWP.x, y=0, z=lastWP.y} -- !!!
		local hasTwn = false 
		dest, hasTwn = convoy.getLocName(thePoint) 
		local clsZ, zDelta = cfxZones.getClosestZone(thePoint)
		local clsA, aDelta = dcsCommon.getClosestAirbaseTo(thePoint, 0)
		local dist = zDelta
		destType = "dmlZone"
		destObj = clsZ
		if aDelta < dist then -- airfield is closer than closest zone
			dist = aDelta
			destType = "airfield"
			destObj = clsA
		end 
		if convoy.verbose then 
			trigger.action.outText(theData.name .. " has destination object " .. destObj:getName(), 30)
		end 
		if not hasTwn then 
			-- use nearest dmlZone or airfield to name destination 
			dest = destObj:getName() 
			if dist < 10000 then 
			elseif dist < 20000 then 
				dest = dest .. " area" 
			else 
				dest = "greater " .. dest .. " area"
			end 
		end 
	else 
		dest = "NO GROUP DATA"
	end
	return dest, destObj, destType
end 

function convoy.startConvoy(theZone, groupIdent)
	-- groupIdent overrides random selection and pickes exactly that group 
	-- make sure my coa is set up correctly 
	-- groupIdent is a string (group name) 
	if theZone.isDynamic then
		theZone.coa = theZone:getCoalition() -- auto-resolves masterowner 
	end
	
	-- pre-wipe existing convoys if they exist, will NOT cause
	-- failed event!
	if theZone.preWipe then 
		local groupCollector = {}
		local filtered = {}
		for cName, entry in pairs(convoy.convoys) do 
			if entry.origin == theZone then 
				for gName, theGroup in pairs(entry.groups) do -- vehicles
					if Group.isExist(theGroup) then 
						table.insert(groupCollector, theGroup)
					end
				end
				for gName, theGroup in pairs(entry.helos) do -- helicopters
					if Group.isExist(theGroup) then 
						table.insert(groupCollector, theGroup)
					end
				end
				-- do not pass on 
			else 
				filtered[cName] = entry -- pass on 
			end
		end
		
		-- delete the groups that are still alive 
		for idx, theGroup in pairs(groupCollector) do 
			trigger.action.outText("cnvy: prewipe - removing group <" .. theGroup:getName() .. ">", 30)
			Group.destroy(theGroup)
		end
		convoy.convoys = filtered
	end
	
	-- iterate all groups and spawn them 
	local spawns = {} -- vehicle groups -- DICT
	local helos = {}
	local spawnSizes = {} -- overkill, just one group in here 
	local theConvoy = {} -- data carrier 
	theConvoy.name = dcsCommon.uuid(theZone.name)
	theConvoy.anon = "CVY-" .. convoy.uuid() 
	-- choose a vehicle group from all available 
	local gOrig 
	if groupIdent then gOrig = theZone.myGroups[groupIdent]
	else 
		local allGroups = dcsCommon.enumerateTable(theZone.myGroups)
		gOrig = dcsCommon.pickRandom(allGroups) 
	end 
	local gName = gOrig.name 
	local gData = dcsCommon.clone(gOrig)
	-- make unique names for group and units if desired 
	if theZone.unique then 
		gData.name = dcsCommon.uuid(gOrig.name)
		gData.groupId = nil 
		for idx, theUnit in pairs (gData.units) do 
			theUnit.name = dcsCommon.uuid(theUnit.name)
			theUnit.unitId = nil 
		end 
	end

	-- retrieve destination from zone 
	local dest = theZone.destination
	if not dest then 
		dest = theZone.destinations[gName]
	end
	local from = theZone.froms -- they are all the same...
    theConvoy.dest = dest 
	theConvoy.destObject = theZone.destObjects[gName]
	theConvoy.desc = theConvoy.name .. " from " .. from .. " to " .. dest 
	
	-- spawn one vehicle group and add it to my spawns and spawnSizes 
	gCat = Group.Category.GROUND
	local waypoints = convoy.amendVehicleData(theZone, gData, theConvoy.name) -- add actions to route, return waypoint locations
	theConvoy.waypoints = waypoints
	local cty = dcsCommon.getACountryForCoalition(theZone.coa)
	local theSpawnedGroup = coalition.addGroup(cty, gCat, gData)
	spawns[gData.name] = theSpawnedGroup
	spawnSizes[gData.name] = theSpawnedGroup:getSize()
	theConvoy.distance = theZone.distances[gOrig.name]
	theConvoy.oName = gOrig.name 
	
	-- now spawn one helo group and make them escort the group that was 
	-- just spawned 
	local rnd = math.random(1,100)
	if (rnd <= theZone.pEscort) and dcsCommon.getSizeOfTable(theZone.myHelos) > 0 then 
		gCat = Group.Category.HELICOPTER -- allow escort helos 
		allGroups = dcsCommon.enumerateTable(theZone.myHelos)
		gOrig = dcsCommon.pickRandom(allGroups)
		gData = dcsCommon.clone(gOrig)
		-- make group unique 
		if theZone.unique then 
			gData.name = dcsCommon.uuid(gOrig.name)
			gData.groupId = nil
			for idx, theUnit in pairs (gData.units) do 
				theUnit.name = dcsCommon.uuid(theUnit.name)
				theUnit.unitId = nil 
			end 
		end
		convoy.makeHeloDataEscortGroup(gData, theSpawnedGroup)
		local theSpawnedHelos = coalition.addGroup(cty, gCat, gData)
		helos[gData.name] = theSpawnedHelos
	end 
	
	theConvoy.origin = theZone 
	theConvoy.groups = spawns -- contains only one group 
	theConvoy.helos = helos -- all helos spawned
	theConvoy.groupSizes = spawnSizes -- vehicle group size by name 
	theConvoy.lastAttackReport = -1000
	theConvoy.coa = theZone.coa
	theConvoy.reached = {} -- waypoints reached message remember 
	-- add to convoys 
	convoy.convoys[theConvoy.name] = theConvoy 
	-- return the convoy entry 
	return theConvoy
end 	

function convoy.amendVehicleData(theZone, theData, convoyName)
	-- place a callback action for each waypoint 
	-- in data block 
	if not theData.route then return nil end 
	local route = theData.route 
	if not route.points then return nil end 
	local points = route.points
	local np = #points 
	if np < 1 then return nil end 

	local newPoints = {}
	local waypoints = {}
	for idx=1, np do 
		local wp = points[idx]
		local tasks = wp.task.params.tasks
		local tnew = #tasks + 1 -- new number for this task 
		local t = {
			["number"] = tnew,
			["auto"] = false,
			["id"] = "WrappedAction",
			["enabled"] = true,
			["params"] = {
				["action"] = {
					["id"] = "Script",
					["params"] = {
						["command"] = "convoy.wpReached(\"" .. theData.name .."\", \"" .. convoyName .. "\", \"" .. idx .. "\", \"" .. np .. "\")",  
					}, -- end of ["params"]
				}, -- end of ["action"]
			}, -- end of ["params"]
		} -- end of task 
		-- add t to tasks 
		table.insert(tasks, t)

		newPoints[idx] = wp
		local thePoint = {x=wp.x, y=0, z=wp.y}
		waypoints[idx] = thePoint
	end 
	route.points = newPoints 
	return waypoints
end 

function convoy.makeHeloDataEscortGroup(theData, theGroup)
	-- overwrite entire route with new escort mission for theGroup 
	local gID = theGroup:getID() 
	-- set group's main task to CAS
	theData.tasks = {}
	theData.task = "CAS"
	local nuPoints = {}
	local oldPoints = theData.route.points
	local wp1 = dcsCommon.clone(oldPoints[1]) -- clone old
	wp1.alt = 100 -- overwrite key data 
	wp1.action = "Turning Point"
	wp1.alt_type = "RADIO"
	wp1.speed = 28
	wp1.task = {
		["id"] = "ComboTask",
		["params"] = {
			["tasks"] = {
				[1] = {
					["enabled"] = true,
					["key"] = "CAS",
					["id"] = "EngageTargets",
					["number"] = 1,
					["auto"] = true,
					["params"] = {
						["targetTypes"] = 
						{
							[1] = "Helicopters",
							[2] = "Ground Units",
							[3] = "Light armed ships",
						}, -- end of ["targetTypes"]
						["priority"] = 0,
					}, -- end of ["params"]
				}, -- end of [1]
				[2] = {
					["enabled"] = true,
					["auto"] = false,
					["id"] = "GroundEscort",
					["number"] = 2,
					["params"] = {
						["targetTypes"] = {
							[1] = "Helicopters",
							[2] = "Ground Units",
						}, -- end of ["targetTypes"]
						["groupId"] = gID, -- ESCORT THIS! 
						["lastWptIndex"] = 2,
						["engagementDistMax"] = 500,
						["lastWptIndexFlag"] = false,
						["lastWptIndexFlagChangedManually"] = false,
					}, -- end of ["params"]
				}, -- end of [2]
			}, -- end of ["tasks"]
		}, -- end of ["params"]
	} -- end of ["task"]
	wp1.type = "Turning Point"
	nuPoints[1] = wp1 
	theData.route.points = nuPoints
end 

--
-- WP Callback
--
function convoy.wpReached(gName, convName, idx, wpNum)
	idx = tonumber(idx) 
	wpNum = tonumber(wpNum)
	local theConvoy = convoy.convoys[convName]
	if not theConvoy then 
		trigger.action.outText("convoy <" .. convName .. "> not found, exiting", 30)
		return 
	end 
	local waypoints = theConvoy.waypoints
	theConvoy.currWP = idx 
	local coa = theConvoy.coa 
	local enemy = 1 
	if coa == 1 then enemy = 2 end 
	local theZone = theConvoy.origin 
	if theConvoy.reached[idx] then 
		trigger.action.outText("<" .. convName .. ">: We've been here before...?", 30)
	else 
		convoy.invokeWPCallbacks(theConvoy, idx, wpNum)
		theConvoy.reached[idx] = true -- remember we were reported this 
		if idx == 1 then 
			local distk = math.floor(theConvoy.distance / 1000 + 1.5)
			local distm = math.floor(0.621371 * theConvoy.distance/1000 + 1)

			trigger.action.outTextForCoalition(coa, "Convoy " .. convName .. " has departed from rallying point " .. theZone.froms .. " towards their destination " .. theConvoy.dest .. " (for a total distance of " .. distk .. "km/" .. distm .. "nm).", 30)
			trigger.action.outSoundForCoalition(coa, convoy.actionSound)
			if convoy.listEnemy then 
				local msg = "Intelligence reports new enemy convoy " .. theConvoy.anon .. " enroute to " ..  theConvoy.destObject:getName()
				trigger.action.outTextForCoalition(enemy, msg, 30)
				trigger.action.outSoundForCoalition(enemy, convoy.actionSound)
			end

		elseif idx == wpNum then  
			trigger.action.outTextForCoalition(coa, "Convoy " .. convName .. " has arrived at desitation (" .. theConvoy.dest .. ").", 30)
			trigger.action.outSoundForCoalition(coa, convoy.actionSound)
			if convoy.listEnemy then 
				local msg = "Enemy convoy " .. theConvoy.anon .. " arrived at " ..  theConvoy.destObject:getName()
				trigger.action.outTextForCoalition(enemy, msg, 30)
				trigger.action.outSoundForCoalition(enemy, convoy.actionSound)
			end
			convoy.invokeArrivedCallbacks(theConvoy)
			-- hit the output flag if defined 
			if theZone.arrivedOut then 
				theZone:pollFlag(theZone.arrivedOut, "inc")
			end 
			-- remove convoy from watchlist 
			convoy.convoys[convName] = nil 
			
			-- deallocate convoy if theZone requests is 
			if theZone.endWipe then 
				convoy.wipeConvoy(theConvoy)
			end 
		else 
			if theZone.wpUpdates then 
				local p = waypoints[idx] -- idx is one-based!
				local msg =  "Convoy " .. convName .. ", enroute to destination " .. theConvoy.dest .. ", has reached "
				local locName, hasLoc = convoy.getLocName(p) 
				if hasLoc then 
					msg =  msg .. "checkpoint located at " .. locName .. " (waypoint " .. idx .. " of " .. wpNum .. ")."
				else 
					msg = msg .. "waypoint " ..idx .. " of " .. wpNum .. "."
				end 
				trigger.action.outTextForCoalition(coa, msg, 30)
				trigger.action.outSoundForCoalition(theConvoy.coa, convoy.actionSound)
			end
		end 
	end
end

function convoy.wipeConvoy(theConvoy) -- called async and sync 
	local theZone = theConvoy.origin
	if convoy.verbose or theZone.verbose then 
		trigger.action.outText("+++cnvy: entere wipe for convoy <" .. theConvoy.name .. "> started from <" .. theZone.name .. ">", 30)
	end 
	for gName, theGroup in pairs(theConvoy.groups) do 
		if Group.isExist(theGroup) then 
			Group.destroy(theGroup)
		end 
	end 
	for gName, theGroup in pairs(theConvoy.helos) do 
		if Group.isExist(theGroup) then 
			Group.destroy(theGroup)
		end 
	end
end 

--
-- API
--

function convoy.collectConvoysFor(coa) 
	local collector = {}
	for idx, theZone in pairs(convoy.zones) do 
		if theZone.isDynamic then
			theZone.coa = theZone:getCoalition() 
		end
		-- warning: differentiating between coa and owner!
		if theZone.coa == coa then 
			table.insert(collector, theZone)
		end 
	end 
	return collector 
end

function convoy.sourceAndDestinationForCoa(theList, coa, allowNeutral)
	local solutions = {}
	for idx, theZone in pairs(theList) do 
		-- all destinations have a coalition 
		for gName, theObject in pairs(theZone.destObjects) do
			-- destObjects can be dml zones or airbases 
			local oCoa = theObject:getCoalition() -- dmlZones return Owner and respect masterowner
			if oCoa == coa or (allowNeutral and oCoa == 0) then 
				local aMatch = {theZone=theZone, gName=gName}
				table.insert(solutions, aMatch)
			end 
		end		
	end
	return solutions
end

function convoy.filterConvoysByDistance(theList, maxDist)
	local filtered = {}
	for idx, theEntry in pairs(theList) do
		local theZone = theEntry.theZone 
		local gName = theEntry.gName 
		local cDist = theZone.distances[gName]
		if cDist < maxDist then 
			table.insert(filtered, theEntry)
		end 
	end

	return filtered 
end

function convoy.filterConvoysByRunning(theList)
	-- filters all zones that have a running convoy 
	local filtered = {}
	for idx, theZone in pairs(theList) do -- iterate all zones 
		local pass = true 
		local coa = theZone.coa -- not getCoalition!
		for name, entry in pairs(convoy.convoys) do 
			if entry.coa == coa and entry.origin == theZone then 
				pass = false 
			end
		end 
		if pass then
			table.insert(filtered, theZone) 
		else 

		end 
	end 
	return filtered 
end

function convoy.getSafeConvoyForCoa(coa, allowNeutral, maxDist)
	local allMyConvoys = convoy.collectConvoysFor(coa) 
	local safeConvoys = convoy.sourceAndDestinationForCoa(allMyConvoys, coa, allowNeutral)
	if convoy.verbose then 
		trigger.action.outText("+++safe convoy scan for <" .. coa .. "> returns <" .. #safeConvoys .. "> hits out of <" .. #allMyConvoys .. "> potentials:", 30)
		for idx, theSol in pairs(safeConvoys) do 
			trigger.action.outText("zone <" .. theSol.theZone.name .. ">, group <" .. theSol.gName .. ">", 30)
		end 
	end 
	
	if maxDist then 
		safeConvoys = convoy.filterConvoysByDistance(safeConvoys, maxDist)
	end 
	
	if #safeConvoys < 1 then 
		return nil 
	end 
	local sol = dcsCommon.pickRandom(safeConvoys)

	return sol.theZone, sol.gName 
end

function convoy.runningForCoa(coa)
	local count = 0 
	for name, entry in pairs(convoy.convoys) do 
		if entry.coa == coa then count = count + 1 end 
	end
	return count 
end

--
-- Event & Comms 
--
function convoy:onEvent(theEvent)
	if not theEvent then return end 
	if not theEvent.initiator then return end 
	local theUnit = theEvent.initiator 
	if not theUnit.getName then return end 
	if not theUnit.getGroup then return end 
	if not theUnit.getPlayerName then return end 
	if not theUnit:getPlayerName() then return end 
	local ID = theEvent.id 
	if ID == 15 then -- birth
		convoy.installComms(theUnit)
	end
end

function convoy.installComms(theUnit)
	if not convoy.hasGUI then return end 
	if not theUnit then return end 
	local theGroup = theUnit:getGroup()
	local gID = theGroup:getID()
	local gName = theGroup:getName() 
	
	-- remove old group menu 
	if convoy.roots[gName] then  
		missionCommands.removeItemForGroup(gID, convoy.roots[gName])
	end 
	
	-- handle main menu 
	local mainMenu = nil 
	if convoy.mainMenu then 
		mainMenu = radioMenu.getMainMenuFor(convoy.mainMenu) 
	end 
	
	local root = missionCommands.addSubMenuForGroup(gID, convoy.menuName, mainMenu) 
	convoy.roots[gName] = root 
	args = {}
	args.theUnit = theUnit 
	args.gID = gID 
	args.gName = gName 
	args.coa = theGroup:getCoalition()
	-- now add the submenus for convoys 
	local m = missionCommands.addCommandForGroup(gID, "List known Convoys", root, convoy.redirectListConvoys, args)
end

function convoy.redirectListConvoys(args)
	timer.scheduleFunction(convoy.doListConvoys, args, timer.getTime() + 0.1)
end

function convoy.doListConvoys(args)
--	trigger.action.outText("enter doListConvoys", 30)
	local mine = {}
	local neutrals = {}
	local enemy = {}
	local mySide = args.coa 
	local gID = args.gID
	
	-- now iterate all convoys, and sort them into bags 
	for convName, theConvoy in pairs (convoy.convoys) do 
		if theConvoy.coa == mySide then 
			table.insert(mine, theConvoy)
		elseif theConvoy.coa == 0 then 
			table.insert(neutrals, theConvoy) -- note: no neutral players
		else 
			table.insert(enemy, theConvoy)
		end
	end
	
	-- we now can count each by entry num 
	-- build report 
	
	local msg = ""
	local hasMsg = false 
	if #mine > 0 then 
		-- report my own convoys with location 
		hasMsg = true 
		msg = msg .. "\nRUNNING ALLIED CONVOYS:\n"
		for idx, theConvoy in pairs(mine) do 
			-- access first group from dict, there is only one  
			local theGroup = dcsCommon.getFirstItem(theConvoy.groups)
			if theGroup and Group.isExist(theGroup) and dcsCommon.getFirstLivingUnit(theGroup) then 
				local theUnit = dcsCommon.getFirstLivingUnit(theGroup)
				msg = msg .. "  " .. theConvoy.name .. " enroute to " .. theConvoy.dest
				local p = theUnit:getPoint()
				local locName, hasLoc = convoy.getLocName(p)
				if hasLoc then 
					msg = msg .. ", now some " .. locName
				end
				msg = msg .. "\n"
			else 
				msg = msg .. "  Lost contact with " .. theConvoy.name .. "\n" 
			end
		end
	end 

	if convoy.listEnemy and #enemy > 0 then 
		hasMsg = true 
		msg = msg .. "\nKNOWN/REPORTED ENEMY CONVOYS:\n"
		-- enemy convoys always show closest destObject as destination!
		for idx, theConvoy in pairs(enemy) do
			local theGroup = dcsCommon.getFirstItem(theConvoy.groups)
			if theGroup and Group.isExist(theGroup) then 
				msg = msg .. "  " .. theConvoy.anon .. " enroute to " .. theConvoy.destObject:getName() 
				if theConvoy.wasAttacked then 
					local remU = theGroup:getUnits()
					msg = msg .. ", " .. #remU .. " units remaining"
				end 
				msg = msg .. ".\n"
				if theConvoy.currWP == #theConvoy.waypoints -1 then 
				msg = msg .. "  -=CLOSE TO DESTINATION=-\n"
				end
			end
		end			
	end
	
	
	if convoy.listNeutral and #neutrals > 0 then 
		hasMsg = true 
		msg = msg .. "\nKNOWN NEUTRAL CONVOYS:\n"
		-- enemy convoys always show closest destObject as destination!
		for idx, theConvoy in pairs(neutrals) do
			local theGroup = dcsCommon.getFirstItem(theConvoy.groups)
			if theGroup and Group.isExist(theGroup) then 
				msg = msg .. "  " .. theConvoy.name .. " enroute to " .. theConvoy.destObject:getName() .. "\n"
			end
		end			
	end
	if not hasMsg then 
		msg = "\nNO CONVOYS.\n"
	end 
	
	trigger.action.outTextForGroup(gID, msg, 30)
	trigger.action.outSoundForGroup(gID, convoy.actionSound)
end

--
-- UPDATE
--
function convoy.update()
	timer.scheduleFunction(convoy.update, {}, timer.getTime() + 1/convoy.ups)
	-- check for flags 
	for idx, theZone in pairs (convoy.zones) do 
		if theZone.spawnFlag and 
		theZone:testZoneFlag(theZone.spawnFlag, "change", "lastSpawnFlag") then
			convoy.startConvoy(theZone)
		end
	end
end

function convoy.statusUpdate() -- every 10 seconds
	timer.scheduleFunction(convoy.statusUpdate, {}, timer.getTime() + 10)
	local redNum = 0
	local blueNum = 0 
	local neutralNum = 0 
	local now = timer.getTime()
	local filtered  = {}
	for convName, theConvoy in pairs (convoy.convoys) do 
		local hasLosses = false 
		local groupDead = false 
		local theZone = theConvoy.origin 
		local damagedGroup = nil 
		for gName, theGroup in pairs(theConvoy.groups) do 
			if Group.isExist(theGroup) then 
				local newNum = theGroup:getSize()
				if newNum < theConvoy.groupSizes[gName] then 
					hasLosses = true 
					damagedGroup = theGroup
					theConvoy.groupSizes[gName] = newNum
				end 
				if newNum < 1 then 
					groupDead = true 
					hasLosses = false 
				end 
			else
				groupDead = true 
			end 
		end

		if hasLosses then 
			theConvoy.wasAttacked = true 
			if (now - theConvoy.lastAttackReport) > 300 then -- min 5 minutes between Alerts 
				if theZone.attackWarnings and damagedGroup then 
					local theUnit = dcsCommon.getFirstLivingUnit(damagedGroup)
					local p = theUnit:getPoint() 
					local locName, hasLoc = convoy.getLocName(p)
					local msg = "Convoy " .. convName .. ", enroute to destination " .. theConvoy.dest .. ", under attack"
					if hasLoc then 
						msg = msg .. " some " .. locName
					end 
					msg = msg .. ", taking losses."
					trigger.action.outTextForCoalition(theConvoy.coa, msg, 30)
					trigger.action.outSoundForCoalition(theConvoy.coa, convoy.actionSound)
				end 
				theConvoy.lastAttackReport = now 
			end
			convoy.invokeAttackedCallbacks(theConvoy)
			theZone = theConvoy.origin 
			if theZone.attackedOut then 
				theZone:pollFlag(theZone.attackedOut, "inc")
			end
		end
		
		if groupDead then 
			-- invoke callback 
			convoy.invokeDestroyedCallbacks(theConvoy)
			theZone = theConvoy.origin 
			if theZone.deadOut then 
				theZone:pollFlag(theZone.deadOut, "inc")
			end
			trigger.action.outTextForCoalition(theConvoy.coa, "Convoy " .. convName .. " enroute to " .. theConvoy.dest .. " was destroyed.", 30)
			trigger.action.outSoundForCoalition(theConvoy.coa, convoy.actionSound)
			if convoy.listEnemy then 
				local enemy = 1 
				if theConvoy.coa == 1 then enemy = 2 end 
				local msg = "Enemy convoy " .. theConvoy.anon .. " to " ..  theConvoy.destObject:getName() .. " destroyed."
				trigger.action.outTextForCoalition(enemy, msg, 30)
				trigger.action.outSoundForCoalition(enemy, convoy.actionSound)
			end
			
			-- we deallocate after a delay, applies to helos 
			timer.scheduleFunction(convoy.wipeConvoy, theConvoy, now + theZone.killWipeDelay)
			--end 
			-- do not propagate to filtered 
			if convoy.verbose then 
				trigger.action.outText("+++cnvy: filtered <" .. convName .. "> from <" .. theConvoy.origin.name .. "> to <" .. theConvoy.dest .. ">: destroyed", 30)
			end 
		else 
			-- transfer for next round 
			if theConvoy.coa == 0 then 
				neutralNum = neutralNum + 1
			elseif theConvoy.coa == 1 then 
				redNum = redNum + 1 
			else 
				blueNum = blueNum + 1
			end
			filtered[convName] = theConvoy
		end 
	end
	convoy.convoys = filtered 
	if convoy.redConvoy then 
		cfxZones.setFlagValue(convoy.redConvoy, redNum, convoy)
	end
	if convoy.blueConvoy then 
		cfxZones.setFlagValue(convoy.blueConvoy, blueNum, convoy)
	end
	if convoy.neutralConvoy then 
		cfxZones.setFlagValue(convoy.neutralConvoy, neutralNum, convoy)
	end
	if convoy.allConvoy then 
		cfxZones.setFlagValue(convoy.neutralConvoy, neutralNum + redNum + blueNum, convoy)
	end
end
--
-- START
--
function convoy.readConfigZone()
	convoy.name = "convoyConfig" -- make compatible with dml zones 
	local theZone = cfxZones.getZoneByName("convoyConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("convoyConfig") 
	end 
	convoy.actionSound = theZone:getStringFromZoneProperty("actionSound", "UI_SCI-FI_Tone_Bright_Dry_25_stereo.wav")
	convoy.verbose = theZone.verbose
	convoy.ups = theZone:getNumberFromZoneProperty("ups", 1)
	
	convoy.menuName = theZone:getStringFromZoneProperty("menuName", "Convoys")
	convoy.hasGUI = theZone:getBoolFromZoneProperty("hasGUI", true)

	convoy.listEnemy = theZone:getBoolFromZoneProperty("listEnemy", true)
	convoy.listNeutral = theZone:getBoolFromZoneProperty("listNeutral", true)
	if theZone:hasProperty("attachTo:") then 
		local attachTo = theZone:getStringFromZoneProperty("attachTo:", "<none>")
		if radioMenu then -- requires optional radio menu to have loaded 
			local mainMenu = radioMenu.mainMenus[attachTo]
			if mainMenu then 
				convoy.mainMenu = mainMenu 
			else 
				trigger.action.outText("+++convoy: cannot find super menu <" .. attachTo .. ">", 30)
			end
		else 
			trigger.action.outText("+++convoy: REQUIRES radioMenu to run before convoy. 'AttachTo:' ignored.", 30)
		end 
	end 
	
	if theZone:hasProperty("redConvoy#") then 
		convoy.redConvoy = theZone:getStringFromZoneProperty("redConvoy#")
	end
	if theZone:hasProperty("blueConvoy#") then 
		convoy.blueConvoy = theZone:getStringFromZoneProperty("blueConvoy#")
	end
	if theZone:hasProperty("neutralConvoy#") then 
		convoy.neutralConvoy = theZone:getStringFromZoneProperty("neutralConvoy#")
	end
	if theZone:hasProperty("allConvoy#") then 
		convoy.allConvoy = theZone:getStringFromZoneProperty("allConvoy#")
	end 
end

function convoy.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx convoy requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx convoy", convoy.requiredLibs) then
		return false 
	end
	
	-- read config 
	convoy.readConfigZone()

	-- process convoy Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("convoy")
	for k, aZone in pairs(attrZones) do 
		convoy.readConvoyZone(aZone) -- process attributes
		convoy.addConvoyZone(aZone) -- add to list
	end
	
	-- connect event handler 
	world.addEventHandler(convoy)
	
	-- start update 
	timer.scheduleFunction(convoy.update, {}, timer.getTime() + 1/convoy.ups)
	convoy.statusUpdate()
	
	-- start all zones that have onstart 
	for gName, theZone in pairs(convoy.zones) do 
		if theZone.onStart then 
			convoy.startConvoy(theZone)
		end
	end 
	-- say Hi!
	trigger.action.outText("cf/x Convoy v" .. convoy.version .. " started.", 30)
	return true 
end

if not convoy.start() then 
	trigger.action.outText("convoy failed to start up")
	convoy = nil 
end 

--[[--
convoy module
place over a fully configured group, will clone on command (start?)
reportWaypoint option. Add small script to each and every waypoint, will create report 
destinationReached! -- adds script to last waypoint to hit this signal, also inits cb
dead! signal and cb. only applies to ground troops? can they disembark troops when hit?
attacked signal each time a unit is destroyed
importantType - type that must survive=
coalition / masterOwner 
isActive# 0/1 
doWipe? to wipe all my convoys? 
tacTypes = desinate units types that must survive. Upon start, ensure that at least one tac type is pressenr 
when arriving, verify that it still is, or fail earlier when all tactypes are destroyed. 
convoy status UI  

do:
when escort engages, send notice 
when escort damaged, send notice 
mark source and dest of convoy on map for same side 
make routes interchangeable between convoys?
make inf units disembark when convoy attacked
--]]--