civAir = {}
civAir.version = "2.0.0"
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
	1.5.0 process zones as in all other modules
	      verbose is part of config zone 
		  reading type array from config corrected
		  massive simplifications: always between zoned airfieds
		  exclude list and include list 
	1.5.1 added depart only and arrive only options for airfields 
	1.5.2 fixed bugs inb verbosity 
	2.0.0 dmlZones 
		  inbound zones 
		  outbound zones 
		  on start location is randomizes 30-70% of the way
		  guarded 'no longer exist' warning for verbosity 
		  changed unit naming from -civA to -GA
		  strenghtened guard on testing against free slots for other units
		  flights are now of random neutral countries 
		  maxFlights synonym for maxTraffic
	
--]]--

civAir.ups = 0.05 -- updates per second. 0.05  = once every 20 seconds 
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


civAir.trafficCenters = {} 
-- place zones on the map and add a "civAir" attribute. 
-- If the attribute's value is anything
-- but "exclude", the closest airfield to the zone 
-- is added to trafficCenters
-- if you leave this list empty, and do not add airfields
-- by zones, the list is automatically populated with all
-- airfields in the map 
-- if name starts with "***" then it is not an airfield, but zone
		  
civAir.excludeAirfields = {}
-- list all airfields that must NOT be included in 
-- civilian activities. Will be used for neither landing 
-- nor departure. overrides any airfield that was included 
-- in trafficCenters. 
-- can be populated by zone on the map that have the 
-- 'civAir' attribute with value "exclude"

civAir.departOnly = {} -- use only to start from 
civAir.landingOnly = {} -- use only to land at 
civAir.inoutZones = {} -- off-map connector zones 

civAir.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	"cfxZones", -- zones management foc CSAR and CSAR Mission zones
}

civAir.activePlanes = {}
civAir.idlePlanes = {}
civAir.outboundFlights = {} -- only flights that are enroute to an outbound zone

function civAir.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("civAirConfig") 
	if not theZone then 
		trigger.action.outText("***civA: NO config zone!", 30) 
		theZone = cfxZones.createSimpleZone("civAirConfig") 
	end 
		
	-- ok, for each property, load it if it exists
	if theZone:hasProperty("aircraftTypes")  then 
		local theTypes = theZone:getStringFromZoneProperty( "aircraftTypes", civAir.aircraftTypes) -- "Yak-40")
		local typeArray = dcsCommon.splitString(theTypes, ",")
		typeArray = dcsCommon.trimArray(typeArray)
		civAir.aircraftTypes = typeArray 
	end
	
--	if theZone:hasProperty("ups")  then 
		civAir.ups = theZone:getNumberFromZoneProperty("ups", 0.05)
		if civAir.ups < .0001 then civAir.ups = 0.05 end
--	end
	
	if theZone:hasProperty("maxTraffic")  then 
		civAir.maxTraffic = theZone:getNumberFromZoneProperty( "maxTraffic", 10)
	elseif theZone:hasProperty("maxFlights") then 
		civAir.maxTraffic = theZone:getNumberFromZoneProperty( "maxFlights", 10)
	end
	
--	if theZone:hasProperty("maxIdle")  then 
		civAir.maxIdle = theZone:getNumberFromZoneProperty("maxIdle", 8 * 60)
--	end
	
--	if theZone:hasProperty("initialAirSpawns")  then 
		civAir.initialAirSpawns = theZone:getBoolFromZoneProperty( "initialAirSpawns", true) 
--	end
	
	civAir.verbose = theZone.verbose 
end

function civAir.processZone(theZone)
	local value = theZone:getStringFromZoneProperty("civAir", "")
	local af = dcsCommon.getClosestAirbaseTo(theZone.point, 0) -- 0 = only airfields, not farp or ships 
	local inoutName = "***" .. theZone:getName() 
	
	if af then 
		local afName = af:getName()
		value = value:lower()
		if value == "exclude" or value == "closed" then 
			table.insert(civAir.excludeAirfields, afName)
		elseif dcsCommon.stringStartsWith(value, "depart") or dcsCommon.stringStartsWith(value, "start") or dcsCommon.stringStartsWith(value, "take") then 
			table.insert(civAir.departOnly, afName)
		elseif dcsCommon.stringStartsWith(value, "land") or dcsCommon.stringStartsWith(value, "arriv") then
			table.insert(civAir.landingOnly, afName)
		elseif dcsCommon.stringStartsWith(value, "inb") then 
			table.insert(civAir.departOnly, inoutName) -- start in inbound zone
			civAir.inoutZones[inoutName] = theZone
--			theZone.inbound = true 
		elseif dcsCommon.stringStartsWith(value, "outb") then 
			table.insert(civAir.landingOnly, inoutName)
			civAir.inoutZones[inoutName] = theZone
--			theZone.outbound = true
		elseif dcsCommon.stringStartsWith(value, "in/out") then 
			table.insert(civAir.trafficCenters, inoutName)
			civAir.inoutZones[inoutName] = theZone
--			theZone.inbound = true
--			theZone.outbound = true 
		else 
			table.insert(civAir.trafficCenters, afName) -- note that adding the same twice makes it more likely to be picked 
		end
	else 
		trigger.action.outText("+++civA: unable to resolve airfield for <" .. theZone.name .. ">", 30)
	end
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
		civAir.activePlanes[aName] = nil
	else 
		if civAir.verbose then 
			trigger.action.outText("civA: warning - ".. aName .." remove req but not found", 30) 
		end 
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


function civAir.filterAirfields(inAll, inFilter)
	local outList = {}
	for idx, anItem in pairs(inAll) do 
		if dcsCommon.arrayContainsString(inFilter, anItem) then 
			-- filtered, do nothing.
		else
			-- not filtered
			table.insert(outList, anItem)
		end
	end
	return outList
end

function civAir.getTwoAirbases()
	local fAB -- first airbase to depart
	local sAB -- second airbase to fly to 
	
	local departAB = dcsCommon.combineTables(civAir.trafficCenters, civAir.departOnly)
	-- remove all currently excluded air bases from departure 
	local filteredAB = civAir.filterAirfields(departAB, civAir.excludeAirfields)
	-- if none left, error
	if #filteredAB < 1 then 
		trigger.action.outText("+++civA: too few departure airfields", 30)
		return nil, nil 
	end
	
	-- now pick the departure airfield
	fAB = dcsCommon.pickRandom(filteredAB)

	-- now generate list of landing airfields 
	local arriveAB = dcsCommon.combineTables(civAir.trafficCenters, civAir.landingOnly)
	-- remove all currently excluded air bases from arrival 
	filteredAB = civAir.filterAirfields(arriveAB, civAir.excludeAirfields)
	
	-- if one left use it twice, boring flight.
	if #filteredAB < 1 then 
		trigger.action.outText("+++civA: too few arrival airfields", 30)
		return nil, nil
	end
	
	-- pick any second that are not the same 
	local tries = 0
	repeat 
		sAB = dcsCommon.pickRandom(filteredAB)
		tries = tries + 1 -- only try 10 times
	until fAB ~= sAB or tries > 10
	
	
	local civA = {}
	if not (dcsCommon.stringStartsWith(fAB, '***')) then 
		civA.AB = dcsCommon.getFirstAirbaseWhoseNameContains(fAB, 0) 
		civA.name = civA.AB:getName()
	else 
		civA.zone = civAir.inoutZones[fAB]
		civA.name = civA.zone:getName()
	end 
	local civB = {}
	if not (dcsCommon.stringStartsWith(sAB, '***')) then 
		civB.AB = dcsCommon.getFirstAirbaseWhoseNameContains(sAB, 0) 
		civB.name = civB.AB:getName()
	else 
		civB.zone = civAir.inoutZones[sAB]
		civB.name = civB.zone:getName() 
	end 

	return civA, civB -- fAB, sAB	
end

function civAir.parkingIsFree(fromWP) 
	-- iterate over all currently registres flights and make 
	-- sure that their location isn't closer than 10m to my new parking 
	local loc = {}
	loc.x = fromWP.x 
	loc.y = fromWP.alt 
	loc.z = fromWP.z 
	
	for name, aPlaneGroup in pairs(civAir.activePlanes) do
		if Group.isExist(aPlaneGroup) then 
			local aPlane = aPlaneGroup:getUnit(1)			
			if aPlane and Unit.isExist(aPlane) then
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
		trigger.action.outText("civA: NIL source", 30)
		return nil 
	end 
	
	if not toAirfield then 
		trigger.action.outText("civA: NIL destination", 30)
		return nil 
	end 
	
	local randomizeLoc = inAirStart
	
	local theGroup = dcsCommon.createEmptyAircraftGroupData (name)
	local theAUnit = dcsCommon.createAircraftUnitData(name .. "-GA", theTypeString, false)
	theAUnit.payload.fuel = 100000
	dcsCommon.addUnitToGroupData(theAUnit, theGroup)
	
	local fromWP 
	if fromAirfield.AB then 
		fromWP = dcsCommon.createTakeOffFromParkingRoutePointData(fromAirfield.AB) 
	else 
		-- we start in air from inside inbound zone 
		local p = fromAirfield.zone:createRandomPointInZone()
		local alt = fromAirfield.zone:getNumberFromZoneProperty("alt", 8000)
		fromWP = dcsCommon.createSimpleRoutePointData(p, alt)
		theAUnit.alt = fromWP.alt
		theAUnit.speed = fromWP.speed 
		inAirStart = false -- it already is, no separation shenigans
	end
	
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
	
	-- now look at destination: airfield or zone?
	local zoneApproach = toAirfield.zone 
	local toWP 
	local overheadWP
	if zoneApproach then 
		-- we fly this plane to a zone, and then disappear it 
		local p = zoneApproach:getPoint()
		local alt = zoneApproach:getNumberFromZoneProperty("alt", 8000)
		toWP = dcsCommon.createSimpleRoutePointData(p, alt)
	else 
		-- sometimes, when landing kicks in too early, the plane lands 
		-- at the wrong airfield. AI sucks. 
		-- so we force overflight of target airfield	
		overheadWP = dcsCommon.createOverheadAirdromeRoutPintData(toAirfield.AB)
		toWP = dcsCommon.createLandAtAerodromeRoutePointData(toAirfield.AB)
		if not toWP then 
			trigger.action.outText("civA: toWP create failed", 30)
			return nil 
		end 
	
		if not civAir.parkingIsFree(fromWP) then 
			trigger.action.outText("civA: failed free parking check for flight " .. name, 30)
			return nil 
		end
	end
	
	if randomizeLoc then 
		-- make first wp to somewhere 30-70 towards toWP
		local percent = (math.random(40) + 30) / 100
		local mx = dcsCommon.lerp(fromWP.x, toWP.x, percent)
		local my = dcsCommon.lerp(fromWP.y, toWP.y, percent)
		fromWP.x = mx 
		fromWP.y = my 
		fromWP.speed = 150
		fromWP.alt = 8000
		theAUnit.alt = fromWP.alt
		theAUnit.speed = fromWP.speed 
	end
	
	if (not fromAirfield.AB) or randomizedLoc or inAirStart then 
		-- set current heading correct towards toWP
		local hdg = dcsCommon.bearingFromAtoBusingXY(fromWP, toWP)
		theAUnit.heading = hdg 
		theAUnit.psi = -hdg 
	end
	
	dcsCommon.moveGroupDataTo(theGroup, 
							  fromWP.x, 
							  fromWP.y)
	dcsCommon.addRoutePointForGroupData(theGroup, fromWP)
	if not zoneApproach then 
		dcsCommon.addRoutePointForGroupData(theGroup, overheadWP)
	end
	dcsCommon.addRoutePointForGroupData(theGroup, toWP)
	
	-- spawn
	local groupCat = Group.Category.AIRPLANE
	local allNeutral = dcsCommon.getCountriesForCoalition(0)
	local aRandomNeutral = dcsCommon.pickRandom(allNeutral)
	if not aRandomNeutral then 
		trigger.action.outText("+++civA: WARNING: no neutral countries exist, flight is not neutral.", 30)
	end
	local theSpawnedGroup = coalition.addGroup(aRandomNeutral, groupCat, theGroup) -- 82 is UN peacekeepers
	if zoneApproach then 
		-- track this flight to target zone 
		civAir.outboundFlights[name] = zoneApproach
	end
	return theSpawnedGroup
end

-- flightCount is a global that holds the number of flights we track
civAir.flightCount = 0 
function civAir.createNewFlight(inAirStart)
	
	civAir.flightCount = civAir.flightCount + 1
	local fAB, sAB = civAir.getTwoAirbases()  -- from AB
	if not fAB or not sAB then 
		trigger.action.outText("+++civA: cannot create flight, no source or destination", 30)
		return 
	end

	-- fAB and sAB are tables that have either .base or AB set

	local name = fAB.name .. "-" .. sAB.name.. "/" .. civAir.flightCount
	local TypeString = dcsCommon.pickRandom(civAir.aircraftTypes)
	local theFlight = civAir.createFlight(name, TypeString, fAB, sAB, inAirStart)
	
	if not theFlight then 
		-- flight was not able to spawn.
		trigger.action.outText("civA: aborted civ spawn on fAB:" .. fAB:getName(), 30)
		return 
	end
	
	civAir.addPlane(theFlight)  -- track it
	
	if civAir.verbose then 
		trigger.action.outText("civA: created flight from <" .. fAB.name .. "> to <" .. sAB.name .. ">", 30) 
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
-- U P D A T E   L O O P S
--

function civAir.trackOutbound()
	timer.scheduleFunction(civAir.trackOutbound, {}, timer.getTime() + 10)
	
	-- iterate all flights that are outbound 
	local filtered = {}
	for gName, theZone in pairs(civAir.outboundFlights) do 
		local theGroup = Group.getByName(gName)
		if theGroup then 
			local theUnit = theGroup:getUnit(1)
			if theUnit and Unit.isExist(theUnit) then 
				local p = theUnit:getPoint()
				local t = theZone:getPoint()
				local d = dcsCommon.distFlat(p, t)
				if d > 3000 then -- works unless plane faster than 300m/s = 1080 km/h 
					-- keep watching 
					filtered[gName] = theZone
				else
					-- we can disappear the group
					if civAir.verbose then 
						trigger.action.outText("+++civA: flight <" .. gName .. "> has reached map outbound zone <" .. theZone:getName() .. "> and is removed", 30)
					end 
					Group.destroy(theGroup)
				end
			else 
				trigger.action.outText("+++civ: lost unit in group <" .. gName .. "> heading for <" .. theZone:getName() .. ">", 30)
			end
		end		
	end
	civAir.outboundFlights = filtered 
end

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
		if civAir.verbose then 
			trigger.action.outText("civA: removed " .. name .. " from active roster, no longer exists", 30)
		end 
	end 
	
	
	-- now, run through all existing flights and update their 
	-- idle times. also count how many planes there are 
	-- so we can respawn if we are below max 
	local planeNum = 0
	local overduePlanes = {}
	local now = timer.getTime()
	for name, aPlaneGroup in pairs(civAir.activePlanes) do
		local speed = 0
		if aPlaneGroup:isExist() then 
			local aPlane = aPlaneGroup:getUnit(1)
			if aPlane and Unit.isExist(aPlane) and aPlane:getLife() >= 1 then
				planeNum = planeNum + 1
				local vel = aPlane:getVelocity()
				speed = dcsCommon.mag(vel.x, vel.y, vel.z)		
			else 
				-- force removal of group, plane no longer exists 
				civAir.idlePlanes[name] = -1000
				speed = 0
			end
		else 
			-- force removal, group no longer exists
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
			-- zero out idle plane, it's moving fast enough
			civAir.idlePlanes[name] = nil			
		end
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
		if aFlight and Unit.isExist(aFlight) then 
			-- destroy can only work if group isexist!
			Group.destroy(aFlight) -- remember: flights are groups!
			if civAir.verbose then 
				trigger.action.outText("+++civA: removed flight <" .. aName .. "> for overtime.", 30)
			end 
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
		civAir.processZone(aZone)
	end
end

function civAir.listTrafficCenters()
	trigger.action.outText("Traffic Centers", 30)
	for idx, aName in pairs(civAir.trafficCenters) do
		trigger.action.outText(aName, 30)
	end
	
	if #civAir.departOnly > 0 then 
		trigger.action.outText("Departure-Only:", 30)
		for idx, aName in pairs(civAir.departOnly) do
			trigger.action.outText(aName, 30)
		end
	end
	
	if #civAir.landingOnly > 0 then 
		trigger.action.outText("Arrival/Landing-Only:", 30)
		for idx, aName in pairs(civAir.landingOnly) do
			trigger.action.outText(aName, 30)
		end
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
	if (#civAir.trafficCenters + #civAir.departOnly < 1) or
	   (#civAir.trafficCenters + #civAir.landingOnly < 1) 
	then 
		trigger.action.outText("+++civA: auto-populating", 30)
		-- simply add airfields on the map
		local allBases = dcsCommon.getAirbasesWhoseNameContains("*", 0)
		for idx, aBase in pairs(allBases) do 
			local afName = aBase:getName()

			table.insert(civAir.trafficCenters, afName)
		end
	end
	
	if civAir.verbose then 
		civAir.listTrafficCenters()
	end 
	
	-- air-start half population if allowed
	if civAir.initialAirSpawns then 
		civAir.airStartPopulation()
	end
	
	-- start the update loop
	civAir.update()
	-- start outbound tracking 
	civAir.trackOutbound()
	
	-- say hi!
	trigger.action.outText("cf/x civAir v" .. civAir.version .. " started.", 30)
	return true 
end

if not civAir.start() then 
	trigger.action.outText("cf/x civAir aborted: missing libraries", 30)
	civAir = nil 
end
 
 --[[--
  Additional ideas
  
  - callbacks for civ spawn / despawn
  - add civkill callback / redCivKill blueCivKill flag bangers
  - Helicopter support
  - add slot checking to see if other planes block it even though DCS claims the slot is free
  - allow list of countries to choose civ air from 
  - ability to force a flight from a source? How do we make a destination? currently not a good idea 
  
 --]]--