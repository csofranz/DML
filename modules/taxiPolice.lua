taxiPolice = {}
taxiPolice.version = "1.0.0"
taxiPolice.verbose = true 
taxiPolice.ups = 1 -- checks per second 
taxiPolice.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
  Version History
  1.0.0 - Initial version 
 
--]]--

taxiPolice.speedLimit = 14 -- m/s . 14 m/s = 50 km/h, 10 m/s = 36 kmh 
taxiPolice.triggerTime = 3 -- seconds until we register a speeding violation 
taxiPolice.rwyLeeway = 5 -- meters on each side
taxiPolice.rwyExtend = 500 -- meters in front and at end 
taxiPolice.airfieldMaxDist = 3000 -- radius around airfield in which we operate
taxiPolice.runways = {} -- indexed by airbase name, then by rwName
                        -- if nil, that base is not policed 
taxiPolice.suspects = {} -- units that are currently behaving naughty 
taxiPolice.tickets = {} -- number of warnings per player 
taxiPolice.maxTickets = 3 -- number of tickes without retribution
taxiPolice.lastMessageTo = {} -- used to suppress messages if too soon
function taxiPolice.buildRunways()
	local bases = world.getAirbases()
	local mId = 0
	for idb, aBase in pairs (bases) do -- i = 1, #base do
	   local name = aBase:getName()
	   local rny = aBase:getRunways()
	   -- Note that Airbase.Category values are not obtained by calling airbase:getCategory() - that calls Object.getCategory(airbase) and will always return the value Object.Category.BASE. Instead you need to use airbase:getDesc().category to obtain the Airbase.Category!
	   local cat = aBase:getDesc().category
	   
	   if rny and (cat == 0) then 
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
				-- mark center of airbase in a red 200x200 square
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
		else 
			if taxiPolice.verbose then 
				trigger.action.outText("No runways proccing for base <" .. name .. ">, cat = <" .. cat .. ">", 30)
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
	local theGroup = theUnit:getGroup() 
	local cat = theGroup:getCategory()
	if cat ~= 0 then return end -- not a fixed wing, disregard 
	
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
		-- this base is not policed 
		taxiPolice.suspects[player] = nil 
		return 
	end
	
	for rwName, aRunway in pairs(myRunways) do 
		if cfxZones.isPointInsidePoly(p, aRunway) then 
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

function taxiPolice.update() -- every second/ups
	-- schedule next invocation
	timer.scheduleFunction(taxiPolice.update, {}, timer.getTime() + 1/taxiPolice.ups)
	
	--trigger.action.outText("onpatrol flag is " .. taxiPolice.onPatrol .. " with val = " .. trigger.misc.getUserFlag(taxiPolice.onPatrol), 30)
	-- see if this has been turned on or offDuty
	if taxiPolice.onPatrol and 
	   cfxZones.testZoneFlag(taxiPolice, taxiPolice.onPatrol, "change", "lastOnPatrol") then  
		taxiPolice.active = true
		local knots = math.floor(taxiPolice.speedLimit * 1.94384)
		local kmh = math.floor(taxiPolice.speedLimit * 3.6)
		trigger.action.outText("NOTAM:\ntarmac and taxiway speed limit of " .. knots .. " knots/" .. kmh .. " km/h is enforced on all air fields!", 30)
	end 
	
	if taxiPolice.offDuty and 
	   cfxZones.testZoneFlag(taxiPolice, taxiPolice.offDuty, "change", "lastOffDuty") then  
		taxiPolice.active = false
		trigger.action.outText("NOTAM:\ntarmac and taxiway speed limit rescinded. Taxi responsibly!", 30)
	end 
	
	if not taxiPolice.active then return end 
	
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
-- ONEVENT
--

function taxiPolice:onEvent(theEvent)
	--trigger.action.outText("txP event: <" .. theEvent.id .. ">", 30)
	if not taxiPolice.greetings then return end -- no warnings 
	if not taxiPolice.active then return end -- no policing active 
	
	local ID = theEvent.id 
	if not ID then return end 
	if (ID ~= 15) and (ID ~= 4) then return end -- not birth nor land 
	local theUnit = theEvent.initiator 
	if not theUnit then return end 
	if theUnit:inAir() then return end 
	
	-- make sure it's a plane. Helos are ignored 
	local theGroup = theUnit:getGroup() 
	local cat = theGroup:getCategory()
	if cat ~= 0 then return end 
	
	if not theUnit.getPlayerName then return end 
	local pName = theUnit:getPlayerName()
	if not pName then return end 
	local base, dist = dcsCommon.getClosestAirbaseTo(theUnit:getPoint(), 0)
	local bName = base:getName()
	if dist > taxiPolice.airfieldMaxDist then return end 
	
	local UID = theUnit:getID()
	-- check if this airfield is exempt 
	local rwys = taxiPolice.runways[bName]
	local now = timer.getTime()
	local last = taxiPolice.lastMessageTo[pName] -- remember timestamp
	if not last then last = 0 end 
	local tdiff = now - last 
	-- make sure palyer receives only one such notice within 15 seconds
	-- but always when now = 0 (mission startup)
	if (now ~= 0) and (tdiff < 15) then return end -- to soon 
	taxiPolice.lastMessageTo[pName] = now
	if not rwys then 
		trigger.action.outTextForUnit(UID, "Welcome to " .. bName .. ", " .. pName .. "!\nAlthough a general taxiway speed limit is in effect, it does not apply here.", 30)
		return 
	end
	
	local knots = math.floor(taxiPolice.speedLimit * 1.94384)
	local kmh = math.floor(taxiPolice.speedLimit * 3.6)
	trigger.action.outTextForUnit(UID, "Welcome to " .. bName .. ", " .. pName .. "!\nBe advised: a speed limit of " .. knots .. " knots/" .. kmh .. " km/h is enforced on tarmac and taxiways.", 30)
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
	taxiPolice.name = "taxiPoliceConfig" -- cfxZones compatibility 
	
	taxiPolice.verbose = theZone.verbose 
	
	taxiPolice.speedLimit = cfxZones.getNumberFromZoneProperty(theZone, "speedLimit", 14) -- 14 -- m/s. 14 m/s = 50 km/h, 10 m/s = 36 kmh 
	taxiPolice.triggerTime = cfxZones.getNumberFromZoneProperty(theZone, "triggerTime", 3) --3 -- seconds until we register a speeding violation 
	taxiPolice.rwyLeeway = cfxZones.getNumberFromZoneProperty(theZone, "leeway", 5) -- 5 -- meters on each side
	taxiPolice.rwyExtend = cfxZones.getNumberFromZoneProperty(theZone, "extend", 500) --500 -- meters in front and at end 
	taxiPolice.airfieldMaxDist = cfxZones.getNumberFromZoneProperty(theZone, "radius", 3000) -- 3000 -- radius around airfield in which we operate
	taxiPolice.maxTickets = cfxZones.getNumberFromZoneProperty(theZone, "maxTickets", 3) -- 3
	
	taxiPolice.active = cfxZones.getBoolFromZoneProperty(theZone, "active", true)
	taxiPolice.greetings = cfxZones.getBoolFromZoneProperty(theZone, "greetings", true)
	
	if cfxZones.hasProperty(theZone, "onPatrol") then 
		taxiPolice.onPatrol = cfxZones.getStringFromZoneProperty(theZone, "onPatrol", "<none>")
		taxiPolice.lastOnPatrol = cfxZones.getFlagValue(taxiPolice.onPatrol, taxiPolice)
	end
	
	if cfxZones.hasProperty(theZone, "offDuty") then 
		taxiPolice.offDuty = cfxZones.getStringFromZoneProperty(theZone, "offDuty", "<none>")
		taxiPolice.lastOffDuty = cfxZones.getFlagValue(taxiPolice.offDuty, taxiPolice)
	end
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
	
	-- install envent handler to greet pilots on airfields 
	world.addEventHandler(taxiPolice)
	
	-- say hi!
	trigger.action.outText("cfx taxiPolice v" .. taxiPolice.version .. " started.", 30)
	return true 
end

-- let's go!
if not taxiPolice.start() then 
	trigger.action.outText("cfx taxiPolice aborted: missing libraries", 30)
	taxiPolice = nil 
end

--[[--
	Possible improvements
	- other sanctions on violations like kick, ban etc 
	- call nearest airfield for open rwys (needs 'commandForUnit' first
	- ability to persist offenders
--]]--

