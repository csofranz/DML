taxiPolice = {}
taxiPolice.version = "0.0.0"
taxiPolice.verbose = true 
taxiPolice.ups = 1 -- checks per second 
taxiPolice.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
-- ensure that a player doesn't overspeed on taxiways. uses speedLimit and violateDuration to determine if to fine 

-- create runway polys here: https://wiki.hoggitworld.com/view/DCS_func_getRunways

-- works as follows: 
-- when a player's plane is not inAir, they are monitored. 
-- when on a runway or too far from airfield (only airfields are monitored) monitoring ends 
-- when monitored and overspeeding, they first receive a warning, and after n warnings they receive retribution 
--]]--
taxiPolice.speedLimit = 14 -- m/s . 14 m/s = 50 km/h, 10 m/s = 36 kmh 
taxiPolice.triggerTime = 3 -- seconds until we register a speeding violation 
taxiPolice.rwyLeeway = 5 -- meters on each side
taxiPolice.rwyExtend = 500 -- meters in front and at end 
taxiPolice.airfieldMaxDist = 3000 -- radius around airfield in which we operate
taxiPolice.runways = {} -- indexed by airbase name, then by rwName
taxiPolice.suspects = {} -- units that are currently behaving naughty 
taxiPolice.tickets = {} -- number of warnings per player 
taxiPolice.maxTickets = 3 -- number of tickes without retribution

function taxiPolice.buildRunways()
	local bases = world.getAirbases()
	local mId = 0
	for idb, aBase in pairs (bases) do -- i = 1, #base do
	   local name = aBase:getName()
	   local rny = aBase:getRunways()
	   if rny then 
			local runways = {}
			for idx, rwy in pairs(rny) do -- j = 1, #rny do
				-- calcualte quad that encloses taxiway 
				local points = {} -- quad
				local init = rwy.position
				local bearing = rwy.course * -1 -- "*-1 to make meaningful"
				local rwName = bearing * 57.2958 -- rads to degree 
				if rwName < 0 then rwName = rwName + 360 end 
				rwName = math.floor(rwName / 10)
				rwName = tostring(rwName)
				-- calculate start and end point of RWY, "heading 0"
				local radius = rwy.length/2 + taxiPolice.rwyExtend
				local pStart = {y=0, x = init.x + radius, z = init.z }
				local pEnd = {y=0, x = init.x - radius, z = init.z} 
				-- Build runway with width; at 0 heading (trivial case)
				local width = rwy.width/2 + taxiPolice.rwyLeeway
				local dz1 = width 
				local dz2 = - width				
				points[1] = {y = 0, x = pStart.x, z = pStart.z + dz1}
				points[2] = {y = 0, x = pStart.x, z = pStart.z + dz2}
				points[3] = {y = 0, x = pEnd.x, z = pEnd.z + dz2}
				points[4] = {y = 0, x = pEnd.x, z = pEnd.z + dz1}
				-- rotate RWY "0" to RW "bearing" 
				local poly = dcsCommon.rotatePoly3AroundVec3Rad(points, init, bearing)

				mId = mId + 1
				-- draw on map
				if taxiPolice.verbose then 
					trigger.action.quadToAll(-1, mId, poly[1], poly[2], poly[3], poly[4], {0, 0, 0, 1}, {0, 0, 0, .5}, 3)
				end 
				-- save runway under name 
				runways[rwName] = poly 
				
				-- build a 100x100 quad to show base's center
		    end
			
			taxiPolice.runways[name] = runways
			if taxiPolice.verbose then
				local points = {}
				local pStart = aBase:getPoint()
				local pEnd = aBase:getPoint()
				local dx1 = 100 
				local dz1 = 100 
				local dx2 = -100 
				local dz2 = -100				
				points[1] = {y = 0, x = pStart.x + dx1, z = pStart.z + dz1}
				points[2] = {y = 0, x = pStart.x + dx2, z = pStart.z + dz1}
				points[3] = {y = 0, x = pEnd.x + dx2, z = pEnd.z + dz2}
				points[4] = {y = 0, x = pEnd.x + dx1, z = pEnd.z + dz2}
				mId = mId + 1
				trigger.action.quadToAll(-1, mId, points[1], points[2], points[3], points[4], {1, 0, 0, 1}, {1, 0, 0, .5}, 3)
			end 
		end
	end
end


--
-- Checking and Policing
-- 
function taxiPolice.retributeAgainst(theUnit)  
	-- player did not learn. 
	local player = theUnit:getPlayerName() 
	trigger.action.outText("Player <" .. player .. "> behaves reckless and is being reprimanded", 30)
	
	-- do some harsh stuff
	local pGrp = theUnit:getGroup()
	local gID = pGrp:getID() 
	trigger.action.outTextForGroup(gID, "We don't appreciate your behavior. Stop it NOW. Here's something to think about...", 30)
	
	 trigger.action.setUnitInternalCargo(theUnit:getName() , 1000000 ) -- add 1000t
end

function taxiPolice.checkUnit(theUnit, allAirfields)
	if not theUnit.getPlayerName then return end 
	local player = theUnit:getPlayerName() 
	if not player then return end 
	
	local p = theUnit:getPoint()
	p.y = 0
	local base, dist = dcsCommon.getClosestAirbaseTo(p, nil, nil, allAirfields)
	if dist > taxiPolice.airfieldMaxDist then 
		taxiPolice.suspects[player] = nil -- remove watched status 
		return 
	end  -- not interesting 

	local vel = dcsCommon.getUnitSpeed(theUnit)
	
	-- if we get here, player is on the ground, in proximity to airfield 
	if vel < taxiPolice.speedLimit then 
		taxiPolice.suspects[player] = nil -- remove watched status
		return 
	end -- not speeding 
	
	-- if we get here, we also exceed the speed limit 
	-- check if we are on a runway 
	local myRunways = taxiPolice.runways[base:getName()]
	if not myRunways then 
		-- this base is turned off
		--trigger.action.outText("unable to find raunways for <" .. base:getName() .. ">", 30)
		return 
	end
	
	for rwName, aRunway in pairs(myRunways) do 
		if cfxZones.isPointInsidePoly(p, aRunway) then 
			--trigger.action.outText("<" .. theUnit:getName() .. "> is on RWY <" .. rwName .. ">", 30)
			taxiPolice.suspects[player] = nil -- remove watched status
			return 
		end		
	end 
	
	-- if we get here, player is speeding on airfield 
	local speedingSince = taxiPolice.suspects[player] -- time since speeding started 
	
	if not speedingSince then 
		-- we start watching now. At least one second will be grace period 
		taxiPolice.suspects[player] = timer.getTime()
		return
	end 
	
	if timer.getTime() - speedingSince < taxiPolice.triggerTime then 
		-- we are watching, but not acting
		--trigger.action.outText(player .. ", you are being watched: <" .. timer.getTime() - speedingSince .. ">", 30)
		return 		
	end
	
	-- when we get here, player is in violation. 
	-- make sure we will not trigger again by setting future speedingsince to negative
	taxiPolice.suspects[player] = timer.getTime() + 10000 -- 10000 seconds in the future
	
	local vioNum = taxiPolice.tickets[player]
	if not vioNum then vioNum = 0 end 
	vioNum = vioNum + 1 
	taxiPolice.tickets[player] = vioNum
	
	local pGrp = theUnit:getGroup()
	local gID = pGrp:getID() 
	
	if vioNum <= taxiPolice.maxTickets then 
		-- just post a warning 		
		trigger.action.outTextForGroup(gID, player .. ", your taxi speed is reckless. Stop it. Violations registered against you: " .. vioNum, 30)
		return 
	end

	-- we have reached retribution stage 
	taxiPolice.retributeAgainst(theUnit) 
end

---
--- UPDATE
---
function taxiPolice.update() -- every second
	-- schedule next invocation
	timer.scheduleFunction(taxiPolice.update, {}, timer.getTime() + 1/taxiPolice.ups)
	
	local allAirfields = dcsCommon.getAirbasesWhoseNameContains("*", 0) -- all fixed bases, no FARP nor ships. Pre-collect
	
	-- check all player units 
	local playerFactions = {1, 2}
	for idx, aFaction in pairs(playerFactions) do 
		local allPlayers = coalition.getPlayers(aFaction)
		for idy, aPlayer in pairs(allPlayers) do -- returns UNITS!
			if Unit.isActive(aPlayer) and not aPlayer:inAir() then 
				taxiPolice.checkUnit(aPlayer, allAirfields)
			end
		end 
	end
	
end

--
-- START 
--
function taxiPolice.processTaxiZones()
	local taxiZones = cfxZones.zonesWithProperty("taxiPolice")
	local allAirfields = dcsCommon.getAirbasesWhoseNameContains("*", 0)
	
	for idx, theZone in pairs(taxiZones) do
		local isPoliced = cfxZones.getBoolFromZoneProperty(theZone, "taxiPolice", "true")
		if not isPoliced then 
			local p = cfxZones.getPoint(theZone)
			local base, dist = dcsCommon.getClosestAirbaseTo(p, nil, nil, allAirfields)
			local name = base:getName()
			taxiPolice.runways[name] = nil
			if taxiPolice.verbose then 
				trigger.action.outText("txPol: base <" .. name .. "> taxiways not policed.", 30)
			end	
		end
	end
end

function taxiPolice.readConfigZone()
	local theZone = cfxZones.getZoneByName("taxiPoliceConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("taxiPoliceConfig")
		if taxiPolice.verbose then 
			trigger.action.outText("+++txPol: no config zone!", 30)
		end 
	end 
	taxiPolice.verbose = theZone.verbose 
	
	taxiPolice.speedLimit = cfxZones.getNumberFromZoneProperty(theZone, "speedLimit", 14) -- 14 -- m/s. 14 m/s = 50 km/h, 10 m/s = 36 kmh 
	taxiPolice.triggerTime = cfxZones.getNumberFromZoneProperty(theZone, "triggerTime", 3) --3 -- seconds until we register a speeding violation 
	taxiPolice.rwyLeeway = cfxZones.getNumberFromZoneProperty(theZone, "leeway", 5) -- 5 -- meters on each side
	taxiPolice.rwyExtend = cfxZones.getNumberFromZoneProperty(theZone, "extend", 500) --500 -- meters in front and at end 
	taxiPolice.airfieldMaxDist = cfxZones.getNumberFromZoneProperty(theZone, "radius", 3000) -- 3000 -- radius around airfield in which we operate
	taxiPolice.maxTickets = cfxZones.getNumberFromZoneProperty(theZone, "maxTickets", 3) -- 3

end

function taxiPolice.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx taxiPolice requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx taxiPolice", taxiPolice.requiredLibs) then
		return false 
	end
	
	-- read config 
	taxiPolice.readConfigZone()
	
	-- build taxiway db 
	taxiPolice.buildRunways()
	
	-- read taxiPolice attributes 
	taxiPolice.processTaxiZones()
	
	-- start update 
	taxiPolice.update()
	
	-- say hi!
	trigger.action.outText("cfx taxiPolice v" .. taxiPolice.version .. " started.", 30)
	return true 
end

-- let's go!
if not taxiPolice.start() then 
	trigger.action.outText("cfx taxiPolice aborted: missing libraries", 30)
	taxiPolice = nil 
end



