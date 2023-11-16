bombRange = {}
bombRange.version = "1.1.0"
bombRange.dh = 1 -- meters above ground level burst 

bombRange.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
VERSION HISTORY
1.0.0 - Initial version 
1.1.0 - collector logic for collating hits 
        *after* impact on high-resolution scans (30fps)
		set resolution to 30 ups by default 
		order of events: check kills against dropping projectiles 
		collecd dead, and compare against missing erdnance while they are fresh
		GC 
		interpolate hits on dead when looking at kills and projectile does 
		not exist
		also sampling kill events 
		
--]]--
bombRange.bombs = {} -- live tracking
bombRange.collector = {} -- post-impact collections for 0.5 secs
bombRange.ranges = {} -- all bomb ranges
bombRange.playerData = {} -- player accumulated data 
bombRange.unitComms = {} -- command interface per unit 
bombRange.tracking = false -- if true, we are tracking projectiles 
bombRange.myStatics = {} -- indexed by id 
bombRange.killDist = 20 -- meters, if caught within that of kill event, this weapon was the culprit 
bombRange.freshKills = {} -- at max 1 second old? 

function bombRange.addBomb(theBomb)
	table.insert(bombRange.bombs, theBomb)
end

function bombRange.addRange(theZone)
	table.insert(bombRange.ranges, theZone)
end

function bombRange.markRange(theZone)
	local newObjects = theZone:markZoneWithObjects(theZone.markType, theZone.markNum, false)
	for idx, aStatic in pairs(newObjects) do 
		local theID = tonumber(aStatic:getID())
		bombRange.myStatics[theID] = aStatic
	end
end

function bombRange.markCenter(theZone)
	local theObject = theZone:markCenterWithObject(theZone.centerType)
	--table.insert(bombRange.myStatics, theObject)
	local theID = tonumber(theObject:getID())
	bombRange.myStatics[theID] = theObject
end

function bombRange.createRange(theZone) -- has bombRange attribte to mark it 
	theZone.usePercentage = theZone:getBoolFromZoneProperty("percentage", theZone.isCircle)
	if theZone.usePercentage and theZone.isPoly then 
		trigger.action.outText("+++bRng: WARNING: zone <" .. theZone.name .. "> is not a circular zone but wants to use percentage scoring!", 30)
	end 
	theZone.details = theZone:getBoolFromZoneProperty("details", false)
	theZone.reporter = theZone:getBoolFromZoneProperty("reporter", true)
	theZone.reportName = theZone:getBoolFromZoneProperty("reportName", false)
	theZone.smokeHits = theZone:getBoolFromZoneProperty("smokeHits", false)
	theZone.smokeColor = theZone:getSmokeColorStringFromZoneProperty("smokeColor", "blue")
	theZone.flagHits = theZone:getBoolFromZoneProperty("flagHits", false)
	theZone.flagType = theZone:getStringFromZoneProperty("flagType", "Red_Flag")
	theZone.clipDist = theZone:getNumberFromZoneProperty("clipDist", 2000) -- when further way, the drop will be disregarded
	
	theZone.method = theZone:getStringFromZoneProperty("method", "inc")
	if theZone:hasProperty("hit!") then 
		theZone.hitOut = theZone:getStringFromZoneProperty("hit!", "<none>")
	end 
	
	theZone.markType = theZone:getStringFromZoneProperty("markType", "Black_Tyre_RF")
	theZone.markBoundary = theZone:getBoolFromZoneProperty("markBoundary", false)
	theZone.markNum = theZone:getNumberFromZoneProperty("markNum", 3) -- per quarter
	theZone.markCenter = theZone:getBoolFromZoneProperty("markCenter", false)
	theZone.centerType = theZone:getStringFromZoneProperty("centerType", "house2arm")
	theZone.markOnMap = theZone:getBoolFromZoneProperty("markOnMap", false)
	theZone.mapColor = theZone:getRGBAVectorFromZoneProperty("mapColor", {0.8, 0.8, 0.8, 1.0})
	theZone.mapFillColor = theZone:getRGBAVectorFromZoneProperty("mapFillColor", {0.8, 0.8, 0.8, 0.2})
	if theZone.markBoundary then bombRange.markRange(theZone) end 
	if theZone.markCenter then bombRange.markCenter(theZone) end 
	if theZone.markOnMap then 
		local markID = theZone:drawZone(theZone.mapColor, theZone.mapFillColor)
	end
end

--
-- player data 
--
function bombRange.getPlayerData(name)
	local theData = bombRange.playerData[name]
	if not theData then 
		theData = {}
		theData.aircraft = {} -- by typeDesc contains all drops per weapon type
		theData.totalDrops = 0 
		theData.totalHits = 0
		theData.totalPercentage = 0 -- sum, must be divided by drops 
		bombRange.playerData[name] = theData
--		trigger.action.outText("created new player data for " .. name, 30)
	end
	return theData
end

function bombRange.addImpactForWeapon(weapon, isInside, percentage)
	if not percentage then percentage = 0 end 
	if type(percentage) == "string" then percentage = 1 end -- handle poly
	
	local theData = bombRange.getPlayerData(weapon.pName)
	local uType = weapon.uType 
	local uData = theData.aircraft[uType]
	if not uData then 
		uData = {}
		uData.wTypes = {}
		theData.aircraft[uType] = uData
	end
	wType = weapon.type 
	local wData = uData.wTypes[wType]
	if not wData then 
		wData = {shots = 0, hits = 0, percentage = 0}
		uData.wTypes[wType] = wData
	end
	
	wData.shots = wData.shots + 1
	if isInside then 
		wData.hits = wData.hits + 1
		wData.percentage = wData.percentage + percentage 
	else 
	end
	theData.totalDrops = theData.totalDrops + 1
	if isInside then 
		theData.totalHits = theData.totalHits + 1
		theData.totalPercentage = theData.totalPercentage + percentage
	end

end

function bombRange.showStatsForPlayer(pName, gID, unitName)
	local theData = bombRange.getPlayerData(pName)
	local msg = "\nWeapons Range Statistics for " .. pName .. "\n"
	local lineCount = 0
	for aType, aircraft in pairs(theData.aircraft) do 
		if aircraft.wTypes then 
			if lineCount < 1 then 
				msg = msg .. "  Aircraft / Munition : Drops / Hits / Quality\n"
			end 
			for wName, wData in pairs(aircraft.wTypes) do 
				local pct = wData.percentage / wData.shots
				pct = math.floor(pct * 10) / 10 
				msg = msg .. "  " .. aType .. " / " .. wName .. ": " .. wData.shots .. " / " .. wData.hits .. " / " .. pct .. "%\n"
				lineCount = lineCount + 1				
			end			
		end -- if weapon per aircraft
	end
	
	if lineCount < 1 then 
		msg = msg .. "\n NO DATA\n\n"
	else 
		msg = msg .. "\n  Total ordnance drops: " .. theData.totalDrops
		msg = msg .. "\n  Total on target: " .. theData.totalHits
		local q = math.floor(theData.totalPercentage / theData.totalDrops * 10) / 10 
		msg = msg .. "\n  Total Quality: " .. q .. "%\n"
	end

	if bombRange.mustCheckIn then 
		local comms = bombRange.unitComms[unitName]
		if comms.checkedIn then 
			msg = msg .. "\nYou are checked in with weapons range command.\n"
		else 
			msg = msg .. "\nPLEASE CHECK IN with weapons range command.\n"
		end
	end 
	trigger.action.outTextForGroup(gID, msg, 30)
	
	
end
--
-- unit UI
--

function bombRange.initCommsForUnit(theUnit)
	local uName = theUnit:getName() 
	local pName = theUnit:getPlayerName()
	local theGroup = theUnit:getGroup()
	local gID = theGroup:getID()
	local comms = bombRange.unitComms[uName]
	if comms then 
		if bombRange.mustCheckIn then 
			missionCommands.removeItemForGroup(gID, comms.checkin)
		end
		missionCommands.removeItemForGroup(gID, comms.reset)
		missionCommands.removeItemForGroup(gID, comms.getStat)
		missionCommands.removeItemForGroup(gID, comms.root)
	end 
	comms = {}
	comms.checkedIn = false 
	comms.root = missionCommands.addSubMenuForGroup(gID, bombRange.menuTitle)
	comms.getStat = missionCommands.addCommandForGroup(gID, "Get statistics for " .. pName, comms.root, bombRange.redirectComms, {"getStat", uName, pName, gID})
	comms.reset = missionCommands.addCommandForGroup(gID, "RESET statistics for " .. pName, comms.root, bombRange.redirectComms, {"reset", uName, pName, gID})
	if bombRange.mustCheckIn then 
		comms.checkin = missionCommands.addCommandForGroup(gID, "Check in with range", comms.root, bombRange.redirectComms, {"check", uName, pName, gID})
	end 
	bombRange.unitComms[uName] = comms
end

function bombRange.redirectComms(args)
	timer.scheduleFunction(bombRange.commsRequest, args, timer.getTime() + 0.1)
end

function bombRange.commsRequest(args)
	local command = args[1] -- getStat, check,
	local uName = args[2]
	local pName = args[3]
	local theUnit = Unit.getByName(uName)
	local theGroup = theUnit:getGroup() 
	local gID = theGroup:getID()

	if command == "getStat" then 
		bombRange.showStatsForPlayer(pName, gID, uName)
	end
	
	if command == "reset" then 
		bombRange.playerData[pName] = nil 
		trigger.action.outTextForGroup(gID, "Clean slate, " .. uName .. ", all existing records have been deleted.", 30)
	end
	
	if command == "check" then 
		comms = bombRange.unitComms[uName]
		if comms.checkedIn then 
			comms.checkedIn = false -- we are now checked out
			missionCommands.removeItemForGroup(gID, comms.checkin)
			comms.checkin = missionCommands.addCommandForGroup(gID, "Check in with range", comms.root, bombRange.redirectComms, {"check", uName, pName, gID})
			
			trigger.action.outTextForGroup(gID, "Roger, " .. uName .. ", terminating range advisory. Have a good day!", 30)
			if bombRange.signOut then 
				cfxZones.pollFlag(bombRange.signOut, bombRange.method, bombRange)
			end
		else 
			comms.checkedIn = true 
			missionCommands.removeItemForGroup(gID, comms.checkin)
			comms.checkin = missionCommands.addCommandForGroup(gID, "Check OUT " .. uName .. " from range", comms.root, bombRange.redirectComms, {"check", uName, pName, gID})trigger.action.outTextForGroup(gID, uName .. ", you are go for weapons deployment, observers standing by.", 30)
			if bombRange.signIn then 
				cfxZones.pollFlag(bombRange.signIn, bombRange.method, bombRange)
			end
		end
	end
	
end

--
-- Event Proccing
--
function bombRange.suspectedHit(weapon, target)
	local wType = weapon:getTypeName()
	if not target then return end 
	if target:getCategory() == 5 then -- scenery
		return  
	end 

	local theDesc = target:getDesc()
	local theType = theDesc.typeName -- getTypeName gets display name
-- filter statics that we want to ignore 
	for idx, aType in pairs(bombRange.filterTypes) do 
		if theType == aType then 
			return	
		end
	end 
	
	-- try and match target to my known statics, exit if match
	if target.getID then  -- units have no getID, so skip for those
		local theID = tonumber(target:getID())
		if bombRange.myStatics[theID] then 
			return
		end 
	end 
	
	-- look through the collector (recent impacted) first 
	local hasfound = false 
	local theID
	for idx, b in pairs(bombRange.collector) do 
		if  b.weapon == weapon then
			b.pos = target:getPoint()
			bombRange.impacted(b, target) -- use this for impact
			theID = b.ID 
			hasfound = true 
--			trigger.action.outText("susHit: filtering COLLECTED b <" .. b.name .. ">", 30)
		end
	end
	if hasfound then 
		bombRange.collector[theID] = nil -- remove from collector
		return
	end
	
	-- look through the tracked weapons for a match next
	if not bombRange.tracking then
		return 
	end
	local filtered = {}
	for idx, b in pairs (bombRange.bombs) do
		if b.weapon == weapon then 
			hasfound = true 
			-- update b to current position and velocity 
			b.pos = weapon:getPoint()
			b.v = weapon:getVelocity()
			bombRange.impacted(b, target)
			
--			trigger.action.outText("susHit: filtering live b <" .. b.name .. ">", 30)
		else 
			table.insert(filtered, b)
		end
	end
	if hasfound then 
		bombRange.bombs = filtered
	end
end

function bombRange.suspectedKill(target)
	-- some unit got killed, let's see if our munitions in the collector 
	-- phase are close by, i.e. they have disappeared 
	if not target then return end  

	local theDesc = target:getDesc()
	local theType = theDesc.typeName -- getTypeName gets display name
	-- filter statics that we want to ignore 
	for idx, aType in pairs(bombRange.filterTypes) do 
		if theType == aType then return	end
	end 
	
	local hasfound = nil 
	local theID
	local pk = target:getPoint()
	local now = timer.getTime()
	
	-- first, search all currently running projectiles, and check for proximity 
	local filtered = {}
	for idx, b in pairs(bombRange.bombs) do 
		local wp 
		if Weapon.isExist(b.weapon) then 
			wp = b.weapon:getPoint()
		else 
			local td = now - b.t -- time delta 
			-- calculate current loc from last velocity and 
			-- time 
			local moveV = dcsCommon.vMultScalar(b.v, td)
			wp = dcsCommon.vAdd(b.pos, moveV)
		end
		local delta = dcsCommon.dist(wp, pk)
		-- now use the line wp-wp+v and calculate distance 
		-- of pk to that line. 
		local wp2 = dcsCommon.vAdd(b.pos, b.v)
		local delta2 = dcsCommon.distanceOfPointPToLineXZ(pk, b.pos, wp2)
		
		if delta < bombRange.killDist or delta2 < bombRange.killDist then 
			b.pos = pk
			bombRange.impacted(b, target)
			hasfound = true 
--			trigger.action.outText("filtering b: <" .. b.name .. ">", 30)
		else 
			table.insert(filtered, b)
		end
	end
	bombRange.bombs = filtered 
	if hasfound then 
--		trigger.action.outText("protocol: removed LIVING weapon from roster  after impacted() invocation for non-nil target in suspectedKill", 30)
		return 
	end 

	-- now check the projectiles that have already impacted 
	for idx, b in pairs(bombRange.collector) do 
		local dist = dcsCommon.dist(b.pos, pk)
		local wp2 = dcsCommon.vAdd(b.pos, b.v)
		local delta2 = dcsCommon.distanceOfPointPToLineXZ(pk, b.pos, wp2)

		if dist < bombRange.killDist or delta2 < bombRange.killDist then
			-- yeah, *you* killed them!
			b.pos = pk
			bombRange.impacted(b, target) -- use this for impact
			theID = b.ID 
			hasfound = true 
		end
	end
	if hasfound then -- remove from collector, hit attributed 
		bombRange.collector[theID] = nil -- remove from collector
--		trigger.action.outText("protocol: removed COLL weapon from roster  after impacted() invocation for non-nil target in suspectedKill", 30)
		return
	end
end

function bombRange:onEvent(event)
	if not event.initiator then return end 
	local theUnit = event.initiator
	
	if event.id == 2 then -- hit: weapon still exists
		if not event.weapon then return end 
		bombRange.suspectedHit(event.weapon, event.target)
		return 
	end
	
	if event.id == 28 then -- kill: similar to hit, but due to new mechanics not reliable
		if not event.weapon then return end 
		bombRange.suspectedHit(event.weapon, event.target)
		return 
	end
	
	
	if event.id == 8 then -- dead 
		-- these events can come *before* weapon disappears
		local killDat = {}
		killDat.victim = event.initiator
		killDat.p = event.initiator:getPoint()
		killDat.when = timer.getTime() 
		killDat.name = dcsCommon.uuid("vic")
		bombRange.freshKills[killDat.name] = killDat
		bombRange.suspectedKill(event.initiator)
	end
	
	local uName = nil 	
	local pName = nil 
	if theUnit.getPlayerName and theUnit:getPlayerName() ~= nil then 
		uName = theUnit:getName()
		pName = theUnit:getPlayerName()
	else return end 
	
	if event.id == 1 then -- shot event, from player
		if not event.weapon then return end 
		local uComms = bombRange.unitComms[uName]
		if bombRange.mustCheckIn and (not uComms.checkedIn) then 
			if bombRange.verbose then 
				trigger.action.outText("+++bRng: Player <" .. pName .. "> not checked in.", 30)
			end
			return 
		end
		local w = event.weapon
		local b = {}
		local bName = w:getName()
		b.name = bName 
		b.type = w:getTypeName()
		-- may need to verify type: how do we handle clusters or flares?
		b.pos = w:getPoint()  
		b.v = w:getVelocity()
		b.pName = pName 
		b.uName = uName
		b.uType = theUnit:getTypeName() 
		b.gID = theUnit:getGroup():getID()
		b.weapon = w 
		b.released = timer.getTime()
		b.relPos = b.pos 
		b.ID = dcsCommon.uuid("bomb")		
		table.insert(bombRange.bombs, b)
		if not bombRange.tracking then 
			timer.scheduleFunction(bombRange.updateBombs, {}, timer.getTime() + 1/bombRange.ups)
			bombRange.tracking = true 
			if bombRange.verbose then 
				trigger.action.outText("+++bRng: start tracking.", 30)
			end
		end
		if bombRange.verbose then 
			trigger.action.outText("+++bRng: Player <" .. pName .. "> fired a <" .. b.type  .. ">, named <" .. b.name .. ">", 30)
		end
	end
	
	if event.id == 15 then 
		bombRange.initCommsForUnit(theUnit)
	end
	
end

--
-- Update 
--
function bombRange.impacted(weapon, target, finalPass)	
	local targetName = nil 	
	if target then 
		targetName = target:getDesc()
		if targetName then targetName = targetName.displayName end 
		if not targetName then targetName = target:getTypeName() end
	end 
	
--	local s = "Entering impacted() with weapon = <" .. weapon.name .. ">"
--	if target then 
--		s = s .. " AND target = <" .. targetName .. ">"
--	end 
	
-- when we enter, weapon has ipacted target - if target is non-nil 
-- what we need to determine is if that target is inside a zone 
	
	local ipos = weapon.pos -- default to weapon location 
	if target then
		ipos = target:getPoint() -- we make the target loc the impact point
	else 
		-- not an object hit, interpolate the impact point on ground: 
		-- calculate impact point. we use the linear equation
		-- pos.y + t*velocity.y - height = 1 (height above gnd) and solve for t  
		local h = land.getHeight({x=weapon.pos.x, y=weapon.pos.z}) - bombRange.dh -- dh m above gnd
		local t = (h-weapon.pos.y) / weapon.v.y 
		-- having t, we project location using pos and vel
		-- impactpos = pos + t * velocity 
		local imod = dcsCommon.vMultScalar(weapon.v, t)
		ipos = dcsCommon.vAdd(weapon.pos, imod) -- calculated impact point 
	end 
	
	-- see if inside a range 
	if #bombRange.ranges < 1 then 
		trigger.action.outText("+++bRng: No Bomb Ranges detected!")
		return -- no need to update anything
	end
	local minDist = math.huge 
	local theRange = nil 
	for idx, theZone in pairs(bombRange.ranges) do 
		local p = theZone:getPoint()
		local dist = dcsCommon.distFlat(p, ipos)
		if dist < minDist then 
			minDist = dist 
			theRange = theZone
		end
	end
	if not theRange then 
		trigger.action.outText("+++bRng: nil <theRange> on eval. skipping.", 30)
		return 
	end
		
	if minDist > theRange.clipDist then 
		-- no taget zone inside clip dist. disregard this one, too far off 
		if bombRange.reportLongMisses then 
			trigger.action.outTextForGroup(weapon.gID, "Impact of <" .. weapon.type .. "> released by <" .. weapon.pName .. "> outside bomb range and disregarded.", 30)
		end
		return 
	end 
	
	if (not target) and theRange.smokeHits then 
		trigger.action.smoke(ipos, theRange.smokeColor) 
	end

	if (not target) and theRange.flagHits then -- only ground impacts are flagged
		local cty = dcsCommon.getACountryForCoalition(0) -- some neutral county
		local p = {x=ipos.x, y=ipos.z}
		local theStaticData = dcsCommon.createStaticObjectData(dcsCommon.uuid(weapon.type .. " impact"), theRange.flagType)
		dcsCommon.moveStaticDataTo(theStaticData, p.x, p.y)
		local theObject = coalition.addStaticObject(cty, theStaticData)
	end
	
	local impactInside = theRange:pointInZone(ipos)
--[[--
	if target and (not impactInside) then 
		trigger.action.outText("Hit on target <" .. targetName .. "> outside of zone <" .. theRange.name .. ">. should exit unless final impact", 30)
		-- find closest range to object that was hit 
		local closest = nil 
		local shortest = math.huge 
		local tp = target:getPoint()
		for idx, aRange in pairs(bombRange.ranges) do 
			local zp = aRange:getPoint()
			local zDist = dcsCommon.distFlat(zp, tp)
			if zDist < shortest then 
				shortest = zDist 
				closest = aRange 
			end	
		end 
		
		trigger.action.outText("re-check: closest range to target now is <" .. closest.name ..">", 30)
		if closest:pointInZone(tp) then 
			trigger.action.outText("target <" .. targetName .. "> is INSIDE this range, d = <" .. math.floor(shortest) .. ">", 30)
		else 
			trigger.action.outText("targed indeed outside, d = <" .. math.floor(shortest) .. ">", 30)
		end
		
		if finalPass then trigger.action.outText("IS final pass.", 30) end 
	end
--]]--	
	if theRange.reporter and theRange.details then 
		local ipc = weapon.impacted
		if not ipc then ipc = timer.getTime() end
		local t = math.floor((ipc - weapon.released) * 10) / 10
		local v = math.floor(dcsCommon.vMag(weapon.v)) 
		local tDist = dcsCommon.dist(ipos, weapon.relPos)/1000
		tDist = math.floor(tDist*100) /100
		trigger.action.outTextForGroup(weapon.gID, "impact of " .. weapon.type .. " released by " .. weapon.pName .. " from " .. weapon.uType .. " after traveling " .. tDist .. " km in " .. t .. " sec, impact velocity at impact is " .. v .. " m/s!", 30)
	end
	
	local msg = ""
	if impactInside then
		local percentage = 0 
		if theRange.isPoly then 
			percentage = 100
		else 
			percentage = 1 - (minDist / theRange.radius)
			percentage = math.floor(percentage * 100)
		end
		msg = "INSIDE target area"
		if theRange.reportName then msg = msg .. " " .. theRange.name end 
		if (not targetName) and theRange.details then msg = msg .. ", off-center by " .. math.floor(minDist *10)/10 .. " m" end
		if targetName then msg = msg .. ", hit on " .. targetName end 
			
		if not theRange.usePercentage then 
			percentage = 100 
		else  
			msg = msg .. " (Quality " .. percentage .."%)"
		end 
		
		if theRange.hitOut then 
			theZone:pollFlag(theRange.hitOut, theRange.method)
		end

		bombRange.addImpactForWeapon(weapon, true, percentage)		
	else 
		msg = "Outside target area"
--		if target then msg = msg .. " (EVEN THOUGH TGT = " .. target:getName() .. ")" end 
		if theRange.reportName then msg = msg .. " " .. theRange.name end
		if theRange.details then msg = msg .. " (off-center by " .. math.floor(minDist *10)/10 .. " m)" end 
		msg = msg .. ", no hit."
		bombRange.addImpactForWeapon(weapon, false, 0)
	end 
	if theRange.reporter then 
		trigger.action.outTextForGroup(weapon.gID,msg , 30)
	end
end

function bombRange.uncollect(theID)
	-- if this is still here, no hit was registered against the weapon
	-- and we simply use the impact 
	local b = bombRange.collector[theID]
	if b then 
		bombRange.collector[theID] = nil 
		bombRange.impacted(b, nil, true) -- final pass
--		trigger.action.outText("(final impact)", 30)
	end
end

function bombRange.updateBombs()
	local now = timer.getTime() 
	local filtered = {} 
	for idx, theWeapon in pairs(bombRange.bombs) do 
		if Weapon.isExist(theWeapon.weapon) then 
			-- update pos and vel
			theWeapon.pos = theWeapon.weapon:getPoint()
			theWeapon.v = theWeapon.weapon:getVelocity()
			theWeapon.t = now 
			table.insert(filtered, theWeapon)
		else 
			-- put on collector to time out in 1 seconds to allow
			-- asynch hits to still register for this weapon in MP 
--			bombRange.impacted(theWeapon)
			theWeapon.impacted = timer.getTime()
			bombRange.collector[theWeapon.ID] = theWeapon --
			timer.scheduleFunction(bombRange.uncollect, theWeapon.ID, timer.getTime() + 1)
		end
	end
	
	bombRange.bombs = filtered 
	if #filtered > 0 then 
		timer.scheduleFunction(bombRange.updateBombs, {}, timer.getTime() + 1/bombRange.ups)
		bombRange.tracking = true 
	else 
		bombRange.tracking = false 
		if bombRange.verbose then 
			trigger.action.outText("+++bRng: stopped tracking.", 30)
		end
	end
end

function bombRange.GC()
	local cutOff = timer.getTime()
	local filtered = {}
	for name, killDat in pairs(bombRange.freshKills) do 
		if killDat.when + 2 < cutOff then
			-- keep in set for two seconds after kill.when 
			filtered[name] = killDat
		end
	end
	bombRange.freshKills = filtered 
	timer.scheduleFunction(bombRange.GC, {}, timer.getTime() + 10)
end

--
-- load & save data 
--
function bombRange.saveData()
	local theData = {}
	-- save current score list. simple clone 
	local theStats = dcsCommon.clone(bombRange.playerData)
	theData.theStats = theStats
	return theData 
end

function bombRange.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("bombRange")
	if not theData then 
		if bombRange.verbose then 
			trigger.action.outText("+++bRng: no save date received, skipping.", 30)
		end
		return
	end
	
	local theStats = theData.theStats
	bombRange.playerData = theStats 
end


--
-- Config & Start 
--
function bombRange.readConfigZone()
	bombRange.name = "bombRangeConfig"
	local theZone = cfxZones.getZoneByName("bombRangeConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("bombRangeConfig") 
	end 
	local theSet = theZone:getStringFromZoneProperty("filterTypes", "house2arm, Black_Tyre_RF, Red_Flag")
	theSet = dcsCommon.splitString(theSet, ",")
	bombRange.filterTypes = dcsCommon.trimArray(theSet)	
	bombRange.reportLongMisses = theZone:getBoolFromZoneProperty("reportLongMisses", false)
	bombRange.mustCheckIn = theZone:getBoolFromZoneProperty("mustCheckIn", false)
	bombRange.ups = theZone:getNumberFromZoneProperty("ups", 30)
	bombRange.menuTitle = theZone:getStringFromZoneProperty("menuTitle","Contact BOMB RANGE")
	if theZone:hasProperty("signIn!") then 
		bombRange.signIn = theZone:getStringFromZoneProperty("signIn!", 30)
	end 
	if theZone:hasProperty("signOut!") then 
		bombRange.signOut = theZone:getStringFromZoneProperty("signOut!", 30)
	end 
	bombRange.method = theZone:getStringFromZoneProperty("method", "inc")
	bombRange.verbose = theZone.verbose 
end


function bombRange.start()
	if not dcsCommon.libCheck("cfx bombRange", 
		bombRange.requiredLibs) then
		return false 
	end
	
	-- read config 
	bombRange.readConfigZone()

	-- collect all wp target zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("bombRange")
	
	for k, aZone in pairs(attrZones) do 
		bombRange.createRange(aZone) -- process attribute and add to zone
		bombRange.addRange(aZone) -- remember it so we can smoke it
	end
	
	-- load data 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = bombRange.saveData
		persistence.registerModule("bombRange", callbacks)
		-- now load my data 
		bombRange.loadData()
	end	
	
	-- add event handler
	world.addEventHandler(bombRange)

	-- start GC
	bombRange.GC() 
	
	return true 
end 

if not bombRange.start() then 
	trigger.action.outText("cf/x Bomb Range aborted: missing libraries", 30)
	bombRange = nil 
end

--
-- add persistence 
--