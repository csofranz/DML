tdz = {}
tdz.version = "1.1.0"
tdz.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
VERSION HISTORY 
 1.0.0 - Initial version 
 1.0.1 - visible 
		 rwFill, rwFrame 
		 tdzFill, tdzFrame 
		 extend, expand 
		 left, right 
		 multiple zone support
		 hops detection improvement
		 helo attribute 
 1.0.2 - manual placement option 
         filters FARPs 
 1.0.3 - "manual" now defaults to false 
 1.1.0 - now supports event 55 (runway touch) 
 
--]]--

tdz.allTdz = {}
tdz.watchlist = {}
tdz.watching = false 
tdz.timeoutAfter = 120 -- seconds.
-- 
-- rwy draw procs
--
function tdz.rotateXZPolyInRads(thePoly, rads)
	local c = math.cos(rads)
	local s = math.sin(rads)
	for idx, p in pairs(thePoly) do 	
		local nx = p.x * c - p.z * s
		local nz = p.x * s + p.z * c
		p.x = nx
		p.z = nz 
	end 
end

function tdz.rotateXZPolyAroundCenterInRads(thePoly, center, rads)
	local negCtr = {x = -center.x, y = -center.y, z = -center.z}
	tdz.translatePoly(thePoly, negCtr)
	tdz.rotateXZPolyInRads(thePoly, rads)
	tdz.translatePoly(thePoly, center)
end

--function tdz.rotateXZPolyAroundCenterInDegrees(thePoly, center, degrees)
--	tdz.rotateXZPolyAroundCenterInRads(thePoly, center, degrees * 0.0174533)
--end

function tdz.translatePoly(thePoly, v) -- straight rot, translate to 0 first
	for idx, aPoint in pairs(thePoly) do 
		aPoint.x = aPoint.x + v.x 
		if aPoint.y then aPoint.y = aPoint.y + v.y end 
		if aPoint.z then aPoint.z = aPoint.z + v.z end  
	end
end

function tdz.calcTDZone(name, center, length, width, rads, a, b)
	if not a then a = 0 end 
	if not b then b = 1 end 
	-- create a 0-rotated centered poly 
	local poly = {}
	local half = length / 2
	local leftEdge = -half
	poly[1] = { x = leftEdge + a * length, z = width / 2, y = 0}
	poly[2] = { x = leftEdge + b * length, z = width / 2, y = 0}
	poly[3] = { x = leftEdge + b * length, z = -width / 2, y = 0}
	poly[4] = { x = leftEdge + a * length, z = -width / 2, y = 0}
	-- move it to center in map 
	tdz.translatePoly(poly, center)	
	-- rotate it 
	tdz.rotateXZPolyAroundCenterInRads(poly, center, rads)
	-- make it a dml zone 
	local theNewZone = cfxZones.createSimplePolyZone(name, center, poly)
	return theNewZone
end

--
-- create a tdz
--
function tdz.createTDZ(theZone)
	local p = theZone:getPoint()
	local theBase = dcsCommon.getClosestAirbaseTo(p, 0) -- never get FARPS
	theZone.base = theBase 
	theZone.baseName = theBase:getName()
	theZone.helos = false 
	
	local nearestRwy = nil 
	-- see if this is a manually placed runway 
	if theZone:getBoolFromZoneProperty("manual", false) then
		-- construct runway from trigger zone attributes 
		if theZone.verbose or tdz.verbose then 
			trigger.action.outText("+++TDZ: runway for <" .. theZone.name .. "> is manually placed", 30)
		end 
		nearestRwy = {}
		nearestRwy.length = theZone:getNumberFromZoneProperty("length", 2500)
		nearestRwy.width = theZone:getNumberFromZoneProperty("width", 60)
		local hdgRaw = theZone:getNumberFromZoneProperty("course", 0) -- in degrees 
		hdgRaw = hdgRaw * 0.0174533 -- rads 
		nearestRwy.course = hdgRaw * (-1) -- why? because DCS.
		nearestRwy.position = theZone:getPoint(true)
		theZone.baseName = theZone.name .. "(manual placement)"
	else 
		-- get closest runway to TDZ
		-- may get a bit hairy, so let's find a good way 
		local allRwys = theBase:getRunways()
		
		local minDist = math.huge
		for idx, aRwy in pairs(allRwys) do 
			local rp = aRwy.position
			local dist = dcsCommon.distFlat(p, rp)
			if dist < minDist then 
				nearestRwy = aRwy 
				minDist = dist
			end
		end
	end 
	local bearing = nearestRwy.course * (-1)
	if bearing < 0 then bearing = bearing + math.pi * 2 end 
	theZone.bearing = bearing 
	rwname = math.floor(dcsCommon.bearing2degrees(bearing)/10 + 0.5) -- nice number
	degrees = math.floor(dcsCommon.bearing2degrees(bearing) * 10) / 10
	if degrees < 0 then degrees = degrees + 360 end 
	if degrees > 360 then degrees = degrees - 360 end 
	if rwname < 0 then rwname = rwname + 36 end 
	if rwname > 36 then rwname = rwname - 36 end 
	
	if tdz.verbose or theZone.verbose then 
		trigger.action.outText("TDZ: <" .. theZone.name .. "> attached to airfield " .. theZone.baseName .. " RW main (LEFT) is " .. rwname .. "0", 30)
	end 
	
	local opName = rwname + 18 
	if opName > 36 then opName = opName - 36 end 
	if rwname < 10 then rwname = "0"..rwname end 
	if opName < 10 then opName = "0" .. opName end  
	theZone.rwName = rwname .. "/" .. opName	
	theZone.opName = opName .. "/" .. rwname
	local rwLen = nearestRwy.length
	rwLen = rwLen + 2 * theZone:getNumberFromZoneProperty("extend", 0)
	local rwWid = nearestRwy.width 
	rwWid = rwWid + 2 * theZone:getNumberFromZoneProperty("expand", 0)
	local pos = nearestRwy.position
	-- p1 is for distance to centerline calculation, defining a point 
	-- length away in direction bearing, setting up the line
	-- theZone.rwCenter, theZone.p1
	theZone.rwCenter = pos 
	local p1 = {x = pos.x + math.cos(bearing) * rwLen, y = 0, z = pos.z + math.sin(bearing) * rwLen}
	theZone.visible = theZone:getBoolFromZoneProperty("visible", true)
	theZone.rwP1 = p1 
	theZone.starts = theZone:getNumberFromZoneProperty("starts", 0)
	theZone.ends = theZone:getNumberFromZoneProperty("ends", 610) -- m = 2000 ft
	theZone.left = theZone:getBoolFromZoneProperty("left", true)
	theZone.right = theZone:getBoolFromZoneProperty("right", true)

	theZone.runwayZone = tdz.calcTDZone(theZone.name .. "-" .. rwname .. "main", pos, rwLen, rwWid, bearing)
	theZone.rwFrame = theZone:getRGBAVectorFromZoneProperty("rwFrame", {0, 0, 0, 1}) -- black
	theZone.rwFill = theZone:getRGBAVectorFromZoneProperty("rwFill", {0, 0, 0, 0}) -- nothing
	if theZone.visible then 
		theZone.runwayZone:drawZone(theZone.rwFrame, theZone.rwFill)
	end 
	local theTDZone = tdz.calcTDZone(theZone.name .. "-" .. rwname, pos, rwLen, rwWid, bearing, theZone.starts / rwLen, theZone.ends/rwLen)

	theZone.tdzFrame = theZone:getRGBAVectorFromZoneProperty("tdzFrame", {0, 1, 0, 1}) -- green 100%
	theZone.tdzFill = theZone:getRGBAVectorFromZoneProperty("tdzFill", {0, 1, 0, 0.25}) -- 25% green
	if theZone.visible and theZone.left then 
		theTDZone:drawZone(theZone.tdzFrame, theZone.tdzFill)
	end 
	
	theZone.normTDZone = theTDZone
	theTDZone = tdz.calcTDZone(theZone.name .. "-" .. opName, pos, rwLen, rwWid, bearing + math.pi, theZone.starts / rwLen, theZone.ends/rwLen)
	if theZone.visible and theZone.right then 
		theTDZone:drawZone(theZone.tdzFrame, theZone.tdzFill)
	end 
	theZone.opTDZone = theTDZone
	theZone.opBearing = bearing + math.pi
	if theZone.opBearing > 2 * math.pi then theZone.opBearing = theZone.opBearing - math.pi * 2 end 

	if theZone:hasProperty("landed!") then 
		theZone.landedFlag = theZone:getStringFromZoneProperty("landed!", "none")
	end
	if theZone:hasProperty("touchdown!") then 
		theZone.touchDownFlag = theZone:getStringFromZoneProperty("touchDown!", "none")
	end
	if theZone:hasProperty("fail!") then 
		theZone.failFlag = theZone:getStringFromZoneProperty("fail!", "none")
	end

	theZone.method = theZone:getStringFromZoneProperty("method", "inc")
end

--
-- event handler
--

function tdz.playerLanded(theUnit, playerName)
	if tdz.watchlist[playerName] then 
		-- this is not a new landing, for now ignore, increment bump count 
		-- make sure unit names match?
		local entry = tdz.watchlist[playerName]
		entry.hops = entry.hops + 1 -- uh oh. 
		return 
	end 
	
	-- we may want to filter helicopters
	
	-- see if we touched down inside of one of our watched zones 
	-- and the directionality (left = landing dir, right = opDir)
	-- matches
	local p = theUnit:getPoint()
	local theGroup = theUnit:getGroup()
	local cat = theGroup:getCategory() -- DCS 2.9: no issues with groups...
	local gID = theGroup:getID()
	local hdg = dcsCommon.getUnitHeading(theUnit)	
	local msg = ""
	local theZone = nil 
	local opposite = false 
	local dHdg, dOpHdg
	for idx, aRunway in pairs(tdz.allTdz) do 
		local theRunway = aRunway.runwayZone 
		local allowUnit = (cat ~= 1) or aRunway.helos -- 1 = helos
		if allowUnit and theRunway:pointInZone(p) then -- touched down
			dHdg = math.abs(aRunway.bearing - hdg) -- 0..Pi
			dOpHdg = math.abs(aRunway.opBearing - hdg)
			opposite = false 
			if tdz.verbose or aRunway.verbose then 
				trigger.action.outText("TDZ: landing inside <" .. aRunway.name .. ">, myHdg = <" .. math.floor(hdg  * 57.2958) .. ">, dHdg = <" .. dHdg * 57.29 .. ">, dOpHdg = <" .. dOpHdg * 57.29 .. ">, rw = <" .. math.floor(aRunway.bearing  * 57.2958) .. ">, rwOp = <" .. math.floor(aRunway.opBearing  * 57.2958) .. ">", 30)
			end

			if dOpHdg < dHdg then 
				opposite = true 
				dHdg = dOpHdg
				if tdz.verbose or aRunway.verbose then 
					trigger.action.outText("TDZ: landing inside <" .. aRunway.name .. ">, *OPPOSING*", 30)
				end
			else 
				if tdz.verbose or aRunway.verbose then 
					trigger.action.outText("TDZ: landing inside <" .. aRunway.name .. ">, ---INLINE---", 30)
				end
			end 
			-- see if directionality matches 
			if ((opposite == false) and aRunway.left) or 
			   ((opposite == true) and aRunway.right) 
			then 
				theZone = aRunway -- FOUND!
				if theZone.touchDownFlag then 
					theZone.pollFlag(theZone.touchDownFlag, theZone.method)
				end
				trigger.action.outTextForGroup(gID, "Touchdown! Come to a FULL STOP for evaluation", 30)
			else 
				if aRunway.verbose or tdz.verbose then 
					trigger.action.outText("TDZ: ignored touchdown in runway for zone <" .. aRunway.name .. ">, directionality filtered.", 30)
				end
			end
		end 
	end
	if not theZone then 
		if tdz.verbose then 
			trigger.action.outText("TDZ: no touchdown inside zones registered", 30)
		end
		return 
	end -- no landing eval zone hit 
	-- Warning: finds the LAST that matches inZone and left/right 
	
	-- start a new watchlist entry 
	local entry = {}
	entry.msg = ""
	entry.playerName = playerName 
	entry.unitName = theUnit:getName()
	entry.theType = theUnit:getTypeName()
	entry.gID = gID 
	entry.theTime = timer.getTime() 
	entry.tdPoint = p 
	entry.tdVel = theUnit:getVelocity() -- vector 
	entry.hops = 1
	entry.theZone = theZone
	
	-- see if we are in main or opposite direction 
	if dHdg > math.pi * 1.5 then -- > 270+ 
		dHdg = dHdg - math.pi * 1.5
	elseif dHdg > math.pi / 2 then -- > 90+ 
		dHdg = dHdg - math.pi / 2 
	end
	dHdg = math.floor(dHdg * 572.958) / 10 -- in degrees
	local lHdg = math.floor(hdg * 572.958) / 10 -- also in deg 
	-- now see how far off centerline. 
	local offcenter = dcsCommon.distanceOfPointPToLineXZ(p, theZone.rwCenter, theZone.rwP1)
	offcenter = math.floor(offcenter * 10)/10 
	local vel = dcsCommon.vMag(entry.tdVel)
	local vkm = math.floor(vel * 36) / 10 
	local kkm = math.floor(vel * 19.4383) / 10
	entry.msg = entry.msg .. "\nLanded heading " .. lHdg .. "°, diverging by " .. dHdg .. "° from runway heading, velocity at touchdown " .. vkm .. " kmh/" .. kkm .. " kts, touchdown " .. offcenter ..  " m off centerline\n"
	
	-- inside TDZ? Directionality was already checked
	local tdZone = theZone.normTDZone
	if opposite then 
		tdZone = theZone.opTDZone
	end 
	
	if tdZone:pointInZone(p) then 
		-- yes, how far behind threshold
		-- project point onto line to see how far inside 
		local distBehind = dcsCommon.distanceOfPointPToLineXZ(p, tdZone.poly[1], tdZone.poly[4])
		local zonelen = math.abs(theZone.starts-theZone.ends)
		local percentile = math.floor(distBehind / zonelen * 100)
		local rating = ""
		if percentile < 5 or percentile > 90 then rating = "marginal"
		elseif percentile < 15 or percentile > 80 then rating = "pass"
		elseif percentile < 25 or percentile > 60 then rating = "good"
		else rating = "excellent" end 
		entry.msg = entry.msg .. "Touchdown inside TD-Zone, <" .. math.floor(distBehind) .. " m> behind threshold, rating = " .. rating .. "\n"	
	end
	
	tdz.watchlist[playerName] = entry 
	if not tdz.watching then 
		tdz.watching = true 
		timer.scheduleFunction(tdz.watchLandings, {}, timer.getTime() + 0.2)
	end
end 

function tdz:onEvent(event)
	if not event.initiator then return end 
	local theUnit = event.initiator 
	if not theUnit.getPlayerName then return end 
	local playerName = theUnit:getPlayerName() 
	if not playerName then return end 
	if event.id == 4 or event.id == 55 then 
		-- player landed 
		tdz.playerLanded(theUnit, playerName) 
	end
end

--
-- Monitor landings in progress
--
function tdz.watchLandings() 
	local filtered = {}
	local count = 0
	local transfer = false
	local success = false	
	local now = timer.getTime() 
	for playerName, aLanding in pairs (tdz.watchlist) do 
		-- see if landing timed out 
		local tdiff = now - aLanding.theTime 
		if tdiff < tdz.timeoutAfter then 
			local theUnit = Unit.getByName(aLanding.unitName)
			if theUnit and Unit.isExist(theUnit) then 
				local vel = theUnit:getVelocity()
				local vel = dcsCommon.vMag(vel)
				local p = theUnit:getPoint() 
				if aLanding.theZone.runwayZone:pointInZone(p) then 	
					-- we must slow down to below 3.6 km/h 
					if vel < 1 then 
						-- make sure that we are still inside the runway 
						success = true 
					else 
						transfer = true 
					end
				else 
					trigger.action.outTextForGroup(aLanding.gID, "Ran off runway.", 30)
				end
			end 
		end 
		if transfer then 
			count = count + 1
			filtered[playerName] = aLanding
		else 
			local theZone = aLanding.theZone
			if success then
				local theUnit = Unit.getByName(aLanding.unitName)
				local p = theUnit:getPoint()
				local tdist = math.floor(dcsCommon.distFlat(p, aLanding.tdPoint))
				aLanding.msg = aLanding.msg .."\nSuccessful landing for " .. aLanding.playerName .." in a " .. aLanding.theType .. ". Landing run = <" .. tdist .. " m>, <" .. math.floor(tdiff*10)/10 .. "> seconds from touch-down to standstill."

				if aLanding.hops > 1 then 
					aLanding.msg = aLanding.msg .. "\nNumber of hops: " .. aLanding.hops
				end 
				if theZone.landedFlag then 
					theZone:pollFlag(theZone.landedFlag, theZone.method)
				end
				aLanding.msg = aLanding.msg .."\n"
				trigger.action.outTextForGroup(aLanding.gID, aLanding.msg, 30)
			else 
				if theZone.failFlag then 
					theZone:pollFlag(theZone.failFlag, theZone.method)
				end
				trigger.action.outTextForGroup(aLanding.gID, "Landing for " .. aLanding.playerName .." incomplete.", 30)
			end 
		end
	end
	
	tdz.watchlist = filtered
	
	if count > 0 then 
		timer.scheduleFunction(tdz.watchLandings, {}, timer.getTime() + 0.2)
	else 
		tdz.watching = false
	end
end
--
-- Start
--
function tdz.readConfigZone()
	local theZone = cfxZones.getZoneByName("tdzConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("tdzConfig") 
	end 
	tdz.verbose = theZone.verbose 
end 

function tdz.start()
	if not dcsCommon.libCheck("cfx TDZ", 
		tdz.requiredLibs) then
		return false 
	end
	
	-- read config 
	tdz.readConfigZone()

	-- collect all wp target zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("TDZ")
	
	for k, aZone in pairs(attrZones) do 
		tdz.createTDZ(aZone) -- process attribute and add to zone
		table.insert(tdz.allTdz, aZone) -- remember it so we can smoke it
	end
		
	-- add event handler
	world.addEventHandler(tdz)

	trigger.action.outText("cf/x TDZ version " .. tdz.version .. " running", 30)
	return true 
end 

if not tdz.start() then 
	trigger.action.outText("cf/x TDZ aborted: missing libraries", 30)
	tdz = nil 
end
