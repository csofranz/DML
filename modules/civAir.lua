civAir = {}
civAir.version = "1.4.0"
--[[--
	1.0.0 initial version
	1.1.0 exclude list for airfields 
	1.1.1 bug fixes with remove flight 
	      and betweenHubs 
		  check if slot is really free before spawning
		  add overhead waypoint
	1.1.2 inAir start possible
	1.2.0 civAir can use own config file
	1.2.1 slight update to config file (moved active/idle)
	1.3.0 add ability to use zones to add closest airfield to 
	      trafficCenters or excludeAirfields
	1.4.0 ability to load config from zone to override 
	      all configs it finds 
		  module check 
		  removed obsolete civAirConfig module
		  
	
--]]--

civAir.ups = 0.05 -- updates per second
civAir.initialAirSpawns = true -- when true has population spawn in-air at start
civAir.verbose = false 

-- aircraftTypes contains the type names for the neutral air traffic
-- each entry has the same chance to be chose, so to make an 
-- aircraft more probably to appear, add its type multiple times
-- like here with the Yak-40 
civAir.aircraftTypes = {"Yak-40", "Yak-40",  "C-130", "C-17A", "IL-76MD", "An-30M", "An-26B"} -- civilian planes type strings as described here https://github.com/mrSkortch/DCS-miscScripts/tree/master/ObjectDB

-- maxTraffic is the number of neutral flights that are 
-- concurrently under way 
civAir.maxTraffic = 10 -- number of flights at the same time
civAir.maxIdle = 8 * 60 -- seconds of ide time before it is removed after landing 
civAir.trafficAirbases = {
		randomized = 0, -- between any on map 
		localHubs = 1, -- between any two airfields inside the same random hub listed in trafficCenters
		betweenHubs = 2 -- between any in random hub 1 to any in random hub 2
	}

civAir.trafficRange = 100 -- 120000 -- defines hub size, in meters. Make it 100 to make it only that airfield
-- ABPickmethod determines how airfields are picked 
-- for air traffic 
civAir.ABPickMethod = civAir.trafficAirbases.betweenHubs
civAir.trafficCenters = {
	--"batu", 
	--"kobul",
	--"senaki",
	--"kutai",
	} -- trafficCenters is used with hubs. Each entry defines a hub 
	  -- where we collect airdromes etc based on range 
	  -- simply add a string to identify the hub center 
	  -- e.g. "senak" to define "Senaki Kolkhi"
	  -- to have planes only fly between airfields in 100 km range 
	  -- around senaki kolkhi, enter only senaki as traffic center, set
	  -- trafficRange to 100000 and ABPickMethod to localHubs
	  -- to have traffic only between any airfields listed 
	  -- in trafficCenters, set trafficRange to a small value 
	  -- like 100 meters and set ABPickMethod to betweenHubs
	  -- to have flights that always cross the map with multiple 
	  -- airfields, choose two or three hubs that are 300 km apart,
	  -- then set trafficRange to 150000 and ABPickMethod to betweenHubs
	  -- you can also place zones on the map and add a 
	  -- civAir attribute. If the attribute value is anything
	  -- but "exclude", the closest airfield to the zone 
	  -- is added to trafficCenters
	  -- if you leave this list empty, and do not add airfields
	  -- by zones, the list is automatically populated by all
	  -- airfields in the map 
		  
civAir.excludeAirfields = {
	--"senaki",
	}
	-- list all airfields that must NOT be included in 
	-- civilian activities. Will be used for neither landing 
	-- nor departure. overrides any airfield that was included 
	-- in trafficCenters. Here, Senaki is off limits for 
	-- civilian air traffic
	-- can be populated by zone on the map that have the 
	-- 'civAir' attribute with value "exclude"

civAir.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	"cfxZones", -- zones management foc CSAR and CSAR Mission zones
}

civAir.activePlanes = {}
civAir.idlePlanes = {}

function civAir.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("CivAirConfig") 
	if not theZone then 
		trigger.action.outText("***civA: NO config zone!", 30) 
		return 
	end 
	
	trigger.action.outText("civA: found config zone!", 30) 
	
	-- ok, for each property, load it if it exists
	if cfxZones.hasProperty(theZone, "aircraftTypes")  then 
		civAir.aircraftTypes = cfxZones.getStringFromZoneProperty(theZone, "aircraftTypes", "Yak-40")
	end
	
	if cfxZones.hasProperty(theZone, "ups")  then 
		civAir.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 0.05)
		if civAir.ups < .0001 then civAir.ups = 0.05 end
	end
	
	if cfxZones.hasProperty(theZone, "maxTraffic")  then 
		civAir.maxTraffic = cfxZones.getNumberFromZoneProperty(theZone, "maxTraffic", 10)
	end
	
	if cfxZones.hasProperty(theZone, "maxIdle")  then 
		civAir.maxIdle = cfxZones.getNumberFromZoneProperty(theZone, "maxIdle", 8 * 60)
	end
	
	if cfxZones.hasProperty(theZone, "trafficRange")  then 
		civAir.trafficRange = cfxZones.getNumberFromZoneProperty(theZone, "trafficRange", 120000) -- 120 km 
	end
	
	if cfxZones.hasProperty(theZone, "ABPickMethod")  then 
		civAir.ABPickMethod = cfxZones.getNumberFromZoneProperty(theZone, "ABPickMethod", 0) -- randomized any
	end

	if cfxZones.hasProperty(theZone, "initialAirSpawns")  then 
		civAir.initialAirSpawns = cfxZones.getBoolFromZoneProperty(theZone, "initialAirSpawns", true) 
end



function civAir.addPlane(thePlaneUnit) -- warning: is actually a group 
	if not thePlaneUnit then return end 
	civAir.activePlanes[thePlaneUnit:getName()] = thePlaneUnit
end

function civAir.removePlaneGroupByName(aName)
	if not aName then 
		return 
	end 
	if civAir.activePlanes[aName] then 
		--trigger.action.outText("civA: REMOVING " .. aName .. " ***", 30) 
		civAir.activePlanes[aName] = nil
	else 
		trigger.action.outText("civA: warning - ".. aName .." remove req but not found", 30) 
	end
end

function civAir.removePlane(thePlaneUnit) -- warning: is actually a group 
	if not thePlaneUnit then return end
	if not thePlaneUnit:isExist() then return end 
	civAir.activePlanes[thePlaneUnit:getName()] = nil 
end

function civAir.getPlane(aName) -- warning: returns GROUP!
	return civAir.activePlanes[aName]
end

-- get an air base, may exclude an airbase from choice 
-- method is dependent on 
function civAir.getAnAirbase(excludeThisOne) 
	-- different methods to select a base 
	-- purely random from current list 
	local theAB;
	if civAir.ABPickMethod == civAir.trafficAirbases.randomized then
		repeat 
			local allAB = dcsCommon.getAirbasesWhoseNameContains("*", 0) -- all airfields, no Ships nor FABS
			theAB = dcsCommon.pickRandom(allAB)
		until theAB ~= excludeThisOne
		return theAB
	end
	
	if civAir.ABPickMethod == civAir.trafficAirbases.localHubs then
		-- first, pick a hub name
	end
	
	trigger.action.outText("civA: warning - unknown method <" .. civAir.ABPickMethod .. ">", 30) 
	return nil 
end

function civAir.excludeAirbases(inList, excludeList)
	if not inList then return {} end
	if not excludeList then return inList end 
	if #excludeList < 1 then return inList end 
	
	local theDict = {}
	-- build dict 
	for idx, aBase in pairs(inList) do 
		theDict[aBase:getName()] = aBase
	end
	
	-- now iterate through all excludes and remove them from dics
	for idx, aName in pairs (excludeList) do 
		local allOfflimitAB = dcsCommon.getAirbasesWhoseNameContains(aName, 0)
		for idx2, illegalBase in pairs (allOfflimitAB) do 
			theDict[illegalBase:getName()] = nil 
		end
	end
	-- now linearise (make array) from dict 
	local theArray = dcsCommon.enumerateTable(theDict)
	return theArray
end

function civAir.getTwoAirbases()
	local fAB 
	local sAB
	-- get any two airbases on the map 
	if civAir.ABPickMethod == civAir.trafficAirbases.randomized then
		local allAB = dcsCommon.getAirbasesWhoseNameContains("*", 0) -- all airfields, no Ships nor FABS, all coalitions 
		-- remove illegal source/dest airfields 
		allAB = civAir.excludeAirbases(allAB, civAir.excludeAirfields)

		fAB = dcsCommon.pickRandom(allAB)
		repeat 
			sAB = dcsCommon.pickRandom(allAB) 
		until fAB ~= sAB or (#allAB < 2)
		return fAB, sAB
	end
	
	-- pick a hub, and then selct any two different airbases in the hub 
	if civAir.ABPickMethod == civAir.trafficAirbases.localHubs then
		local hubName = dcsCommon.pickRandom(civAir.trafficCenters)
		-- get the airfield that is identified by this 
		local theHub = dcsCommon.getFirstAirbaseWhoseNameContains(hubName, 0) -- only airfields, all coalitions
		-- get all airbases that surround in range 
		local allAB = dcsCommon.getAirbasesInRangeOfAirbase(
				theHub, -- centered on this base 
				true, -- include hub itself
				civAir.trafficRange, -- hub size in meters 
				0 -- only airfields
				)		
		allAB = civAir.excludeAirbases(allAB, civAir.excludeAirfields)
		fAB = dcsCommon.pickRandom(allAB)
		repeat 
			sAB = dcsCommon.pickRandom(allAB) 
		until fAB ~= sAB or (#allAB < 2)
		return fAB, sAB
	end
	
	-- pick two hubs: one for source, one for destination airfields, 
    -- then pick an airfield from each hub 	
	if civAir.ABPickMethod == civAir.trafficAirbases.betweenHubs then
		--trigger.action.outText("between", 30)
		local sourceHubName = dcsCommon.pickRandom(civAir.trafficCenters)
		--trigger.action.outText("picked " .. sourceHubName, 30)
		local sourceHub = dcsCommon.getFirstAirbaseWhoseNameContains(sourceHubName, 0)
		--trigger.action.outText("sourceHub " .. sourceHub:getName(), 30)

		local destHub 
		repeat destHubName = dcsCommon.pickRandom(civAir.trafficCenters) 
		until destHubName ~= sourceHubName or #civAir.trafficCenters < 2
		destHub = dcsCommon.getFirstAirbaseWhoseNameContains(destHubName, 0)
				--trigger.action.outText("destHub " .. destHub:getName(), 30)
		local allAB = dcsCommon.getAirbasesInRangeOfAirbase(
				sourceHub, -- centered on this base 
				true, -- include hub itself
				civAir.trafficRange, -- hub size in meters 
				0 -- only airfields
				)
		allAB = civAir.excludeAirbases(allAB, civAir.excludeAirfields)
		fAB = dcsCommon.pickRandom(allAB)
		allAB = dcsCommon.getAirbasesInRangeOfAirbase(
				destHub, -- centered on this base 
				true, -- include hub itself
				civAir.trafficRange, -- hub size in meters 
				0 -- only airfields
				)
		allAB = civAir.excludeAirbases(allAB, civAir.excludeAirfields)
		sAB = dcsCommon.pickRandom(allAB)
		return fAB, sAB
	end
	
	 
	trigger.action.outText("civA: warning - unknown method <" .. civAir.ABPickMethod .. "> in getTwoAirbases()", 30) 
end

function civAir.parkingIsFree(fromWP) 
	-- iterate over all currently registres flights and make 
	-- sure that their location isn't closer than 10m to my new parking 
	local loc = {}
	loc.x = fromWP.x 
	loc.y = fromWP.alt 
	loc.z = fromWP.z 
	
	for name, aPlaneGroup in pairs(civAir.activePlanes) do
		if aPlaneGroup:isExist() then 
			local aPlane = aPlaneGroup:getUnit(1)			
			if aPlane:isExist() then
				pos = aPlane:getPoint()
				local delta = dcsCommon.dist(loc, pos)
				if delta < 21 then 
					-- way too close 
					trigger.action.outText("civA: too close for comfort - " .. aPlane:getName() .. " occupies my slot", 30) 
					return false
				end
			end
		end
	end
	
	return true 
end

civAir.airStartSeparation = 0
function civAir.createFlight(name, theTypeString, fromAirfield, toAirfield, inAirStart)
	if not fromAirfield then 
		trigger.action.outText("civA: NIL fromAirfield", 30)
		return nil 
	end 
	
	if not toAirfield then 
		trigger.action.outText("civA: NIL toAirfield", 30)
		return nil 
	end 
	
	local theGroup = dcsCommon.createEmptyAircraftGroupData (name)
	local theAUnit = dcsCommon.createAircraftUnitData(name .. "-civA", theTypeString, false)
	theAUnit.payload.fuel = 100000
	dcsCommon.addUnitToGroupData(theAUnit, theGroup)
	
	local fromWP = dcsCommon.createTakeOffFromParkingRoutePointData(fromAirfield)
	if not fromWP then 
		trigger.action.outText("civA: fromWP create failed", 30)
		return nil 
	end 
	if inAirStart then 
		-- modify WP into an in-air point 
		fromWP.alt = fromWP.alt + 3000 + civAir.airStartSeparation -- 9000 ft overhead + separation
		fromWP.action = "Turning Point"
		fromWP.type = "Turning Point"
			
		fromWP.speed = 150;
		fromWP.airdromeId = nil 
		
		theAUnit.alt = fromWP.alt
		theAUnit.speed = fromWP.speed 
	end
	-- sometimes, when landing kicks in too early, the plane lands 
	-- at the wrong airfield. AI sucks. 
	-- so we force overflight of target airfield 
	local overheadWP = dcsCommon.createOverheadAirdromeRoutPintData(toAirfield)
	local toWP = dcsCommon.createLandAtAerodromeRoutePointData(toAirfield)
	if not toWP then 
		trigger.action.outText("civA: toWP create failed", 30)
		return nil 
	end 
	
	if not civAir.parkingIsFree(fromWP) then 
		trigger.action.outText("civA: failed free parking check for flight " .. name, 30)
		return nil 
	end
	
	dcsCommon.moveGroupDataTo(theGroup, 
							  fromWP.x, 
							  fromWP.y)
	dcsCommon.addRoutePointForGroupData(theGroup, fromWP)
	dcsCommon.addRoutePointForGroupData(theGroup, overheadWP)
	dcsCommon.addRoutePointForGroupData(theGroup, toWP)
	
	-- spawn
	local groupCat = Group.Category.AIRPLANE
	local theSpawnedGroup = coalition.addGroup(82, groupCat, theGroup) -- 82 is UN peacekeepers
	return theSpawnedGroup
end

-- flightCount is a global that holds the number of flights we track
civAir.flightCount = 0 
function civAir.createNewFlight(inAirStart)
	
	civAir.flightCount = civAir.flightCount + 1
	local fAB, sAB = civAir.getTwoAirbases()  -- from AB

	local name = fAB:getName() .. "-" .. sAB:getName().. "/" .. civAir.flightCount
	local TypeString = dcsCommon.pickRandom(civAir.aircraftTypes)
	local theFlight = civAir.createFlight(name, TypeString, fAB, sAB, inAirStart)
	
	if not theFlight then 
		-- flight was not able to spawn.
		trigger.action.outText("civA: aborted civ spawn on fAB:" .. fAB:getName(), 30)
		return 
	end
	
	civAir.addPlane(theFlight)  -- track it
	
	if civAir.verbose then 
		trigger.action.outText("civA: created flight from <" .. fAB:getName() .. "> to <" .. sAB:getName() .. ">", 30) 
	end 
end

function civAir.airStartPopulation()
	local numAirStarts = civAir.maxTraffic / 2
	civAir.airStartSeparation = 0
	while numAirStarts > 0 do 
		numAirStarts = numAirStarts - 1 
		civAir.airStartSeparation = civAir.airStartSeparation + 200
		civAir.createNewFlight(true)
	end
end

-- 
-- U P D A T E   L O O P 
--

function civAir.update()
	-- reschedule me in the future. ups = updates per second. 
	timer.scheduleFunction(civAir.update, {}, timer.getTime() + 1/civAir.ups)
	
	-- clean-up first:
	-- any group that no longer exits will be removed from the array 
	local removeMe = {}
	for name, group in pairs (civAir.activePlanes) do 
		if not group:isExist() then 
			table.insert(removeMe, name) -- mark for deletion
			--Group.destroy(group) -- may break 
		end
	end
	
	for idx, name in pairs(removeMe) do 
		civAir.activePlanes[name] = nil
		trigger.action.outText("civA: warning - removed " .. name .. " from active roster, no longer exists", 30)
	end 
	
	
	-- now, run through all existing flights and update their 
	-- idle times. also count how many planes there are 
	local planeNum = 0
	local overduePlanes = {}
	local now = timer.getTime()
	for name, aPlaneGroup in pairs(civAir.activePlanes) do
		local speed = 0
		if aPlaneGroup:isExist() then 
			local aPlane = aPlaneGroup:getUnit(1)
			
			if aPlane and aPlane:isExist() and aPlane:getLife() >= 1 then 
				planeNum = planeNum + 1
				local vel = aPlane:getVelocity()
				speed = dcsCommon.mag(vel.x, vel.y, vel.z)		
			else 
				-- force removal of group 
				civAir.idlePlanes[name] = -1000
				speed = 0
			end
		else 
			-- force removal
			civAir.idlePlanes[name] = -1000
			speed = 0			
		end 
		
		if speed < 0.5 then 
			if not civAir.idlePlanes[name] then 
				civAir.idlePlanes[name] = now
			end
			local idleTime = now - civAir.idlePlanes[name]
			--trigger.action.outText("civA: Idling <" .. name .. "> for t=" .. idleTime, 30) 
			if idleTime > civAir.maxIdle then 
				table.insert(overduePlanes, name)
			end
		else 
			-- zero out idle plane
			civAir.idlePlanes[name] = nil			
		end
		--]]--
	end
	
	-- see if we have less than max flights running
	if planeNum < civAir.maxTraffic then 
		-- spawn a new plane. just one per pass
		civAir.createNewFlight()
	end
	
	-- now remove all planes that are overdue
	for idx, aName in pairs(overduePlanes) do 		
		local aFlight = civAir.getPlane(aName) -- returns a group
		civAir.removePlaneGroupByName(aName) -- remove from roster
		if aFlight and aFlight:isExist() then 
			-- destroy can only work if group isexist!
			Group.destroy(aFlight) -- remember: flights are groups!
		end 
	end
end



function civAir.doDebug(any)
	trigger.action.outText("cf/x civTraffic debugger.", 30)
	local desc = "Active Planes:"
	local now = timer.getTime()
	for name, group in pairs (civAir.activePlanes) do
		desc = desc .. "\n" .. name 
		if civAir.idlePlanes[name] then 
			delay = now - civAir.idlePlanes[name]
			desc = desc .. " (idle for " .. delay .. ")"
		end
	end
	trigger.action.outText(desc, 30)
end

function civAir.collectHubs()
	local pZones = cfxZones.zonesWithProperty("civAir")
	
	for k, aZone in pairs(pZones) do
		local value = cfxZones.getStringFromZoneProperty(aZone, "civAir", "")
		local af = dcsCommon.getClosestAirbaseTo(aZone.point, 0) -- 0 = only airfields, not farp or ships 
		if af then 
			local afName = af:getName()
			if value:lower() == "exclude" then 
				table.insert(civAir.excludeAirfields, afName)
			else 
				table.insert(civAir.trafficCenters, afName)
			end
		end
		
	end
end

function civAir.listTrafficCenters()
	trigger.action.outText("Traffic Centers", 30)
	for idx, aName in pairs(civAir.trafficCenters) do
		trigger.action.outText(aName, 30)
	end
end
 
-- start 
function civAir.start()
	-- module check 
	if not dcsCommon.libCheck("cfx civAir", civAir.requiredLibs) then 
		return false 
	end
	
	-- see if there is a config zone and load it
	civAir.readConfigZone()

	-- look for zones to add to air fields list
	civAir.collectHubs()
	
	-- make sure there is something in trafficCenters
	if #civAir.trafficCenters < 1 then 
		trigger.action.outText("+++civTraffic: auto-populating", 30)
		-- simply add airfields on the map
		local allBases = dcsCommon.getAirbasesWhoseNameContains("*", 0)
		for idx, aBase in pairs(allBases) do 
			local afName = aBase:getName()
			--trigger.action.outText("+++civTraffic: adding " .. afName, 30)
			table.insert(civAir.trafficCenters, afName)
		end
	end
	
	civAir.listTrafficCenters()
	
	-- air-start half population if allowed
	if civAir.initialAirSpawns then 
		civAir.airStartPopulation()
	end
	
	-- start the update loop
	civAir.update()
		
	-- say hi!
	trigger.action.outText("cf/x civTraffic v" .. civAir.version .. " started.", 30)
	return true 
end

if not civAir.start() then 
	trigger.action.outText("cf/x civAir aborted: missing libraries", 30)
	civAir = nil 
end
 
 --[[--
  Additional ideas
  source to target method 
 --]]--