williePete = {}
williePete.version = "1.0.0"
williePete.ups = 10 -- we update at 10 fps, so accuracy of a 
-- mach two missile is within 33 meters, with interpolation even less

williePete.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"cfxMX",
}

williePete.willies = {}
williePete.wpZones = {}
williePete.playerGUIs = {} -- used for unit guis 

williePete.smokeWeapons = {"HYDRA_70_M274","HYDRA_70_MK61","HYDRA_70_MK1","HYDRA_70_WTU1B","BDU_45B","BDU_33","BDU_45","BDU_45LGB","BDU_50HD","BDU_50LD","BDU_50LGB","C_8CM"}

function williePete.addWillie(theWillie)
	table.insert(williePete.willies, theWillie)
end

function williePete.addWPZone(theZone)
	table.insert(williePete.wpZones, theZone)
end

function williePete.closestCheckInTgtZoneForCoa(point, coa)
	-- returns the closest zone that point is inside. 
	-- first tries directly, then, if none found, 
	-- with added check-in radius
	local lPoint = {x=point.x, y=0, z=point.z}
	local currDelta = math.huge 
	local closestZone = nil
	-- first, we try if outright inside 
	for zName, zData in pairs(williePete.wpZones) do 
		if zData.coalition == coa then 
			-- local zPoint = cfxZones.getPoint(zData)
			local inZone, delta = cfxZones.isPointInsideZone(lPoint, zData)
			if inZone and (delta < currDelta) then 
				currDelta = delta
				closestZone = zData
			end
		end
	end
	-- if we got one, we return that zone 
	if closestZone then return closestZone, currDelta end 
	
	for zName, zData in pairs(williePete.wpZones) do 
		if zData.coalition == coa then 
			-- local zPoint = cfxZones.getPoint(zData)
			local inZone, delta = cfxZones.isPointInsideZone(lPoint, zData, zData.checkInRange)
			if inZone and (delta < currDelta) then 
				currDelta = delta
				closestZone = zData
			end
		end
	end
	if closestZone then return closestZone, currDelta end
	
	return nil, -1
	
end

function williePete.getClosestZoneForCoa(point, coa)
	local lPoint = {x=point.x, y=0, z=point.z}
	local currDelta = math.huge 
	local closestZone = nil
	for zName, zData in pairs(williePete.wpZones) do 
		if zData.coalition == coa then 
			local zPoint = cfxZones.getPoint(zData)
			local delta = dcsCommon.dist(lPoint, zPoint) -- emulate flag compare 
			if (delta < currDelta) then 
				currDelta = delta
				closestZone = zData
			end
		else 
--			trigger.outText("Zone <" .. zData.name .. ">, coa <" .. zData.coalition .. "> does not match <" .. coa .. ">", 30)
		end
	end
	return closestZone, currDelta 
end


function williePete.createWPZone(aZone)
	aZone.coalition = cfxZones.getCoalitionFromZoneProperty(aZone, "wpTarget", 0) -- side that marks it on map, and who fires arty
	aZone.shellStrength = cfxZones.getNumberFromZoneProperty(aZone, "shellStrength", 500) -- power of shells (strength)
	aZone.shellNum = cfxZones.getNumberFromZoneProperty(aZone, "shellNum", 17) -- number of shells in bombardment
	aZone.transitionTime = cfxZones.getNumberFromZoneProperty(aZone, "transitionTime", 20) -- average time of travel for projectiles 
	aZone.coolDown = cfxZones.getNumberFromZoneProperty(aZone, "coolDown", 180) -- cooldown after arty fire, used to set readyTime
	aZone.baseAccuracy = cfxZones.getNumberFromZoneProperty(aZone, "baseAccuracy", 50) 
	
	aZone.readyTime = 0 -- if readyTime > now we are not ready
	aZone.trackingPlayer = nil -- name player's unit who is being tracked for wp. may not be neccessary
	aZone.checkedIn = {} -- dict of all planes currently checked in
	aZone.trackingEndsTime = 0 -- if now > trackingends, we remove player and send a message
	
	aZone.wpTriggerMethod = cfxZones.getStringFromZoneProperty(aZone, "wpTriggerMethod", "change")

	aZone.FACTypes = cfxZones.getStringFromZoneProperty(aZone, "facTypes", "all")
	
	aZone.checkInRange = cfxZones.getNumberFromZoneProperty(aZone, "checkInRange", williePete.checkInRange) -- default to my default
	
	aZone.ackSound = cfxZones.getStringFromZoneProperty(aZone, "ackSound", williePete.ackSound)
	aZone.guiSound = cfxZones.getStringFromZoneProperty(aZone, "guiSound", williePete.guiSound)
	
	if cfxZones.hasProperty(aZone, "triggerMethod") then 
		aZone.wpTriggerMethod = cfxZones.getStringFromZoneProperty(aZone, "triggerMethod", "change")
	end
	
	if aZone.verbose then 
		trigger.action.outText("Added wpTarget zone <" .. aZone.name .. ">", 30)
	end
end

--
-- player management
--
function williePete.startPlayerGUI()
	-- scan all mx players 
	-- note: currently assumes single-player groups
	-- in preparation of single-player 'commandForUnit'
	for uName, uData in pairs(cfxMX.playerUnitByName) do 
		local unitInfo = {}
		-- try and access each unit even if we know that the 
		-- unit does not exist in-game right now 
		local gData = cfxMX.playerUnit2Group[uName]
		local gName = gData.name 
		local coa = cfxMX.groupCoalitionByName[gName]
		local theType = uData.type

		if williePete.verbose then 
			trigger.action.outText("unit <" .. uName .. ">: type <" .. theType .. "> coa <" .. coa .. ">, group <" .. gName .. ">", 30)
		end 
		
		unitInfo.name = uName -- needed for reverse-lookup 
		unitInfo.coa = coa 
		unitInfo.gID = gData.groupId
		unitInfo.uID = uData.unitId
		unitInfo.theType = theType
		unitInfo.cat = cfxMX.groupTypeByName[gName]
		-- now check type against willie pete config for allowable types 
		local pass = false 
		for idx, aType in pairs(williePete.facTypes) do 
			if aType == "ALL" then pass = true end 
			if aType == "ANY" then pass = true end 
			if aType == theType then pass = true end 
			if dcsCommon.stringStartsWith(aType, "HEL") and unitInfo.cat == "helicopter" then pass = true end 
			if dcsCommon.stringStartsWith(aType, "PLAN") and unitInfo.cat == "plane" then pass = true end 
		end
		
		if pass then -- we install a menu for this group 
			-- we may not want check in stuff, but it could be cool
			unitInfo.root = missionCommands.addSubMenuForGroup(unitInfo.gID, "FAC")
			unitInfo.checkIn = missionCommands.addCommandForGroup(unitInfo.gID, "Check In", unitInfo.root, williePete.redirectCheckIn, unitInfo)
		end 
		
		-- store it 
		williePete.playerGUIs[uName] = unitInfo
	end
end

--
-- BOOM
--

--
-- BOOM command
--
function williePete.doBoom(args)
	trigger.action.explosion(args.point, args.strength)
	data = {}
	data.point = args.point 
	data.strength = args.strength 
--	cfxArtilleryZones.invokeCallbacksFor('impact', args.zone, data)
end

function williePete.doParametricFireAt(aPoint, accuracy, shellNum, shellBaseStrength, shellVariance, transitionTime)
	if williePete.verbose then 
		trigger.action.outText("fire with accuracy <" .. accuracy .. "> shellNum <" .. shellNum .. "> baseStren <" .. shellBaseStrength .. "> variance <" .. shellVariance .. ">, ttime <" .. transitionTime .. ">", 30)
	end 
	
	-- accuracy is meters from center 
	if not aPoint then return end 
	if not accuracy then accuracy = 100 end 
	if not shellNum then shellNum = 17 end 
	if not shellBaseStrength then shellBaseStrength = 500 end 
	if not shellVariance then shellVariance = 0.2 end 
	if not transitionTime then transitionTime = 17 end 
	
	local alt = land.getHeight({x=aPoint.x, y=aPoint.z})
	local center = {x=aPoint.x, y=alt, z=aPoint.z}
	
	for i=1, shellNum do
		local thePoint = dcsCommon.randomPointInCircle(accuracy, 0, center.x, center.z)
		thePoint.y = land.getHeight({x=thePoint.x, y=thePoint.z})
		local boomArgs = {}
		local strVar = shellBaseStrength * shellVariance
		strVar = strVar * (2 * dcsCommon.randomPercent() - 1.0) -- go from -1 to 1
		
		boomArgs.strength = shellBaseStrength + strVar
		thePoint.y = land.getHeight({x = thePoint.x, y = thePoint.z}) + 1  -- elevate to ground height + 1
		boomArgs.point = thePoint
		boomArgs.zone = aZone
		local timeVar = 5 * (2 * dcsCommon.randomPercent() - 1.0) -- +/- 1.5 seconds
		if timeVar < 0 then timeVar = -timeVar end 

		timer.scheduleFunction(williePete.doBoom, boomArgs, timer.getTime() + transitionTime + timeVar)
	end
end

--
-- COMMS
--

function williePete.redirectCheckIn(unitInfo)
	timer.scheduleFunction(williePete.doCheckIn, unitInfo, timer.getTime() + 0.1)
end

function williePete.doCheckIn(unitInfo)
	--trigger.action.outText("check-in received", 30)
	local theUnit = Unit.getByName(unitInfo.name)
	local p = theUnit:getPoint()
	local theZone, dist = williePete.closestCheckInTgtZoneForCoa(p, unitInfo.coa)

	if not theZone then 
		theZone, dist = williePete.getClosestZoneForCoa(p, unitInfo.coa)
		if not theZone then 
			trigger.action.outTextForGroup(unitInfo.gID, "No target zone in range.", 30)
			trigger.action.outSoundForGroup(unitInfo.gID, williePete.guiSound)
			return 
		end
	 
		trigger.action.outTextForGroup(unitInfo.gID, "Too far from target zone, closest target zone is " .. theZone.name, 30)
		trigger.action.outSoundForGroup(unitInfo.gID, theZone.guiSound)
		return 
	end
	
	-- we are now checked in to zone -- unless we are already checked in
	if theZone.checkedIn[unitInfo.name] then 
		trigger.action.outTextForGroup(unitInfo.gID, unitInfo.name .. ", " .. theZone.name .. ", we heard you the first time, proceed.", 30)
		trigger.action.outSoundForGroup(unitInfo.gID, theZone.guiSound)
		return 
	end
	
	-- we now check in 
	theZone.checkedIn[unitInfo.name] = unitInfo
	
	-- add the 'Target marked' menu 
	unitInfo.targetMarked = missionCommands.addCommandForGroup(unitInfo.gID, "Target Marked", unitInfo.root, williePete.redirectTargetMarked, unitInfo)
	-- remove 'check in'
	missionCommands.removeItemForGroup(unitInfo.gID, unitInfo.checkIn)
	unitInfo.checkIn = nil 
	-- add 'check out'
	unitInfo.checkOut = missionCommands.addCommandForGroup(unitInfo.gID, "Check Out", unitInfo.root, williePete.redirectCheckOut, unitInfo)
	
	trigger.action.outTextForGroup(unitInfo.gID, "Roger " .. unitInfo.name .. ", " .. theZone.name .. " tracks you, standing by for target data.", 30)
	trigger.action.outSoundForGroup(unitInfo.gID, theZone.guiSound)
end

function williePete.redirectCheckOut(unitInfo)
	timer.scheduleFunction(williePete.doCheckOut, unitInfo, timer.getTime() + 0.1)
end

function williePete.doCheckOut(unitInfo)
	--trigger.action.outText("check-out received", 30)
	
	-- check out of all zones 
	local wasCheckedIn = false 
	local fromZone = ""
	for idx, theZone in pairs(williePete.wpZones) do 
		if theZone.checkedIn[unitInfo.name] then 
			wasCheckedIn = true 
			fromZone = theZone.name
		end 
		theZone.checkedIn[unitInfo.name] = nil 
	end
	if not wasCheckedIn then 
		trigger.action.outTextForGroup(unitInfo.gID, unitInfo.name .. ", roger cecked-out. Good hunting!", 30)
		trigger.action.outSoundForGroup(unitInfo.gID, williePete.guiSound)
	else 
		trigger.action.outTextForGroup(unitInfo.gID, unitInfo.name .. "has checked out of " .. fromZone ..".", 30)
		trigger.action.outSoundForGroup(unitInfo.gID, williePete.guiSound)
	end
	
	-- remove checkOut and targetMarked 
	missionCommands.removeItemForGroup(unitInfo.gID, unitInfo.checkOut)
	unitInfo.checkOut = nil
	missionCommands.removeItemForGroup(unitInfo.gID, unitInfo.targetMarked)
	unitInfo.targetMarked = nil
	
	-- add check in 
	unitInfo.checkIn = missionCommands.addCommandForGroup(unitInfo.gID, "Check In", unitInfo.root, williePete.redirectCheckIn, unitInfo)
end


function williePete.redirectTargetMarked(unitInfo)
	timer.scheduleFunction(williePete.doTargetMarked, unitInfo, timer.getTime() + 0.1)
end

function williePete.rogerDodger(args)
	local unitInfo = args[1]
	local theZone = args[2]
	
	trigger.action.outTextForCoalition(unitInfo.coa, "Roger " .. unitInfo.name .. ", good copy, firing.", 30)
	trigger.action.outSoundForCoalition(unitInfo.coa, theZone.ackSound)
end

function williePete.doTargetMarked(unitInfo)
	--trigger.action.outText("mark received", 30)
	-- first, check if we are past the time-out
	local now = timer.getTime()
	
	-- now check if zone matches check-in 
	if not unitInfo.expiryTime or unitInfo.expiryTime < now then 
		trigger.action.outTextForGroup(unitInfo.gID, "Target mark stale or ambiguous, set fresh mark", 30)
		trigger.action.outSoundForGroup(unitInfo.gID, williePete.guiSound)
		return
	end
	
	-- now, check if the zone is ready to receive 
	if not unitInfo.wpInZone or not unitInfo.pos then 
		-- should not happen, but better safe than sorry
		trigger.action.outTextForGroup(unitInfo.gID, "Lost sight of target location, set new mark", 30)
		trigger.action.outSoundForGroup(unitInfo.gID, williePete.guiSound)
		return 
	end
	
	local tgtZone = unitInfo.wpInZone 
	-- see if we are checked into that zone 
	if not tgtZone.checkedIn[unitInfo.name] then 
		-- zones don't match
		trigger.action.outTextForGroup(unitInfo.gID, "Say again " .. unitInfo.name .. ", we have crosstalk. Try and reset coms", 30)
		trigger.action.outSoundForGroup(unitInfo.gID, williePete.guiSound)
		return
	end
	
	-- see if zone is ready to receive 
	local timeRemaining = math.floor(tgtZone.readyTime - now)
	if timeRemaining > 0 then 
		-- zone not ready
		trigger.action.outTextForGroup(unitInfo.gID, "Stand by " .. unitInfo.name .. ", artillery not ready. Expect " .. timeRemaining + math.random(1, 5) .. " seconds.", 30)
		trigger.action.outSoundForGroup(unitInfo.gID, tgtZone.guiSound)
		return
	end
	
	-- if we get here, we are fire at mark 
	local alt = math.floor(land.getHeight({x = unitInfo.pos.x, y = unitInfo.pos.z}))
	local grid = coord.LLtoMGRS(coord.LOtoLL(unitInfo.pos))
	local mgrs = grid.UTMZone .. ' ' .. grid.MGRSDigraph .. ' ' .. grid.Easting .. ' ' .. grid.Northing
	local theLoc = mgrs 
	trigger.action.outTextForCoalition(unitInfo.coa, tgtZone.name ..", " .. unitInfo.name .." is transmitting target location. Fire at " .. theLoc .. ", elevation " .. alt .. " meters, target marked.", 30)
	trigger.action.outSoundForCoalition(unitInfo.coa, tgtZone.guiSound)
	timer.scheduleFunction(williePete.rogerDodger, {unitInfo, tgtZone},timer.getTime() + math.random(2, 5))
	
	-- collect zone's fire params & fire
	local shellStrength = tgtZone.shellStrength
	local shellNum = tgtZone.shellNum 
	local transitionTime = tgtZone.transitionTime
	local accuracy = tgtZone.baseAccuracy 
	
	williePete.doParametricFireAt(unitInfo.pos, accuracy, shellNum, shellStrength, 0.2, transitionTime)
	
	-- set zone's cooldown
	tgtZone.readyTime = now + tgtZone.coolDown
	-- erase player's wp mark
	unitInfo.wpInZone = nil
	unitInfo.pos = nil 
end
-- return true if a zone is actively tracking theUnit to place 
-- a wp 

function williePete.zoneIsTracking(theUnit)
	local uName = theUnit:getName()
	for idx, theZone in pairs(williePete.wpZones) do
		if theZone.checkedIn[uName] then return true end
	end	
	return false
end

function williePete.isWP(theWeapon) 
	local theDesc = theWeapon:getTypeName()
	for idx, wpw in pairs(williePete.smokeWeapons) do 
		if theDesc == wpw then return true end 
	end
	return false 
end

function williePete:onEvent(event)
	if not event.initiator then 
		--trigger.action.outText("onEvent - " .. event.id .. ": no initiator",30)
		return 
	end 
	if not event.weapon then 
		--trigger.action.outText("onEvent - " .. event.id .. ": no WEAPON",30)
		return 
	end 
	
	local theUnit = event.initiator
	local pType = "(AI)"
	if theUnit.getPlayerName then pType = "(" .. theUnit:getName() .. ")" end
		
	if event.id == 1 then -- S_EVENT_SHOT
		-- initiator is who fired. maybe want to test if player  
		
		--trigger.action.outText(theUnit:getName() .. " " .. pType .. " fired " .. event.weapon:getTypeName() .. ".", 30)
		
		if not williePete.isWP(event.weapon) then 
			--trigger.action.outText("<" .. event.weapon:getTypeName() .. "> not a smoke weapon", 30)
			return  
		end
		
		-- make sure that whoever fired it is being tracked by 
		-- a zone 
		if not williePete.zoneIsTracking(theUnit) then 
			--trigger.action.outText("<" .. event.weapon:getTypeName() .. "> fired while not being tracked by zone", 30)
			return  
		end
		
		-- assuming it's a willie, let's track it 
		local theWillie = {}
		theWillie.firedBy = theUnit:getName()
		theWillie.theUnit = theUnit 
		theWillie.weapon = event.weapon
		theWillie.wt = theWillie.weapon:getTypeName()
		theWillie.pos = theWillie.weapon:getPoint()
		theWillie.v = theWillie.weapon:getVelocity()
		
		williePete.addWillie(theWillie)
	end

	if event.id == 2 then -- hit 
		local what = "something"
		if event.target then what = event.target:getName() end 
		--trigger.action.outText("Weapon " .. event.weapon:getTypeName() .. " fired by unit ".. theUnit:getName() .. " " .. pType .. " hit " .. what, 30)
		-- may need to remove willie from willies
	end
	
end 

-- test if a projectile hit ground inside a wp zone 
function williePete.isInside(theWillie)
	local thePoint = theWillie.pos 
	local theUnitName = theWillie.firedBy -- may be dead already, but who cares
	local theUnit = Unit.getByName(theUnitName) 
	if not theUnit then return false end -- unit dead 
	if not Unit.isExist(theUnit) then return false end -- dito 
	
	local thePlayer = williePete.playerGUIs[theUnitName]
	if not thePlayer then return nil end 
	for idx, theZone in pairs(williePete.wpZones) do
		if cfxZones.pointInZone(thePoint, theZone) then 
			-- we are inside. but is this the right coalition?
			if thePlayer.coa == theZone.coalition then 
				--trigger.action.outText("Willie in " .. theZone.name, 30)
				return theZone
			else 
				--trigger.action.outText("Willie wrong coa", 30)
			end
			-- if we want to allow neutral zones (doens't make sense)
			-- add another guard below 
		else 
			--trigger.action.outText("willie outside " .. theZone.name, 30)
		end
	end
	return nil
end


-- update 

function williePete.projectileHit(theWillie) 
	-- interpolate pos: half time between updates times last velocity 
	local vmod = dcsCommon.vMultScalar(theWillie.v, 0.5 / williePete.ups)
	theWillie.pos = dcsCommon.vAdd(theWillie.pos, vmod) 
	--trigger.action.outText("Willie " .. theWillie.wt .. " expired at " .. dcsCommon.point2text(theWillie.pos) .. " interpolated.", 30)
	
	-- reset last mark for player
	local thePlayer = williePete.playerGUIs[theWillie.firedBy]
	thePlayer.pos = nil
	thePlayer.wpInZone = nil 
	
	-- check if this is within a wpZones 
	local theZone = williePete.isInside(theWillie)
	if not theZone then 
		if williePete.verbose then 
			trigger.action.outText("+++wp: wp expired outside zone", 30)
		end
		return 
	end 
	
	-- if we receive a zone, we know that the player's 
	-- coalition matches the one of the zone 
	thePlayer.expiryTime = timer.getTime() + williePete.wpMaxTime -- set timeout in which player can give fire command 
	thePlayer.pos = theWillie.pos -- remember the loc
	thePlayer.wpInZone = theZone -- remember the zone 
	
	-- mark point with smoke blue 
	--dcsCommon.markPointWithSmoke(theWillie.pos, 4)
	
	if cfxArtilleryZones then 
		--cfxArtilleryZones.doParametricFireAt(theWillie.pos, 50, 10)
	else 
		-- mark point with smoke blue 
		--dcsCommon.markPointWithSmoke(theWillie.pos, 4)
	end
end

function williePete.updateWP()
	timer.scheduleFunction(williePete.updateWP, {}, timer.getTime() + 1/williePete.ups)
	
	local nextPete = {}
	for idx, theWillie in pairs(williePete.willies) do 
		-- check if it still exists
		if Weapon.isExist(theWillie.weapon) then 
			-- update loc, proceed to next round 
			theWillie.pos = theWillie.weapon:getPoint()
			theWillie.v = theWillie.weapon:getVelocity()
			table.insert(nextPete, theWillie)
		else 
			-- weapon disappeared: it has hit something
			-- but unguided rockets do not create an event for that 
			williePete.projectileHit(theWillie)
			-- no longer propagates to next round
		end
	end
	williePete.willies = nextPete
end

function williePete.playerUpdate() 
	timer.scheduleFunction(williePete.playerUpdate, {}, timer.getTime() + 2) -- check 30 times a minute
	-- zone still checked in updates for zones 
	for idx, theZone in pairs(williePete.wpZones) do 
		-- make sure any unit checked in is still inside 
		-- the zone that they checked in, or they are checked out 
		--local zp = cfxZones.getPoint(theZone)
		for idy, unitInfo in pairs(theZone.checkedIn) do 
			-- make sure unit still exists
			local dropUnit = true 
			local theUnit = Unit.getByName(unitInfo.name)
			if theUnit and Unit.isExist(theUnit) then 
				local up = theUnit:getPoint()
				up.y = 0
				local isInside, dist = cfxZones.isPointInsideZone(up, theZone, theZone.checkInRange)
				 
				if isInside then 
					dropUnit = false
				end
			end
			if dropUnit then 
				-- remove from zone check-in 
				-- williePete.doCheckOut(unitInfo)
				timer.scheduleFunction(williePete.doCheckOut, unitInfo, timer.getTime() + 0.1) -- to not muck up iteration
			end
		end
	end
	
	-- menu updates for all players 
end

--
-- Config & Start
--
function williePete.readConfigZone()
	local theZone = cfxZones.getZoneByName("wpConfig") 
	if not theZone then 
		if williePete.verbose then 
			trigger.action.outText("+++wp: NO config zone!", 30)
		end 
		theZone = cfxZones.createSimpleZone("wpConfig") 
	end 
	
	local facTypes = cfxZones.getStringFromZoneProperty(theZone, "facTypes", "all")
	facTypes = string.upper(facTypes)
	
	-- make this an array 
	local allTypes = {}
	if dcsCommon.containsString(facTypes, ",") then 
		allTypes = dcsCommon.splitString(facTypes, ",")
	else 
		table.insert(allTypes, facTypes) 
	end
	williePete.facTypes = dcsCommon.trimArray(allTypes)
	
	-- how long a wp is active. must not be more than 5 minutes
	williePete.wpMaxTime = cfxZones.getNumberFromZoneProperty(theZone, "wpMaxTime", 3 * 60)
	
	-- default check-in range, added to target zone's range and used 
	-- for auto-check-out 
	williePete.checkInRange = cfxZones.getNumberFromZoneProperty(theZone, "checkInRange", 10000) -- 10 km outside
	
	williePete.ackSound = cfxZones.getStringFromZoneProperty(theZone, "ackSound", "some")
	williePete.guiSound = cfxZones.getStringFromZoneProperty(theZone, "guiSound", "some")
	
	williePete.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if williePete.verbose then 
		trigger.action.outText("+++msgr: read config", 30)
	end 
end

function williePete.start()
	if not dcsCommon.libCheck("cfx williePete", 
		williePete.requiredLibs) then
		return false 
	end
	
	-- read config 
	williePete.readConfigZone()
	
	-- collect all wp target zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("wpTarget")
	
	for k, aZone in pairs(attrZones) do 
		williePete.createWPZone(aZone) -- process attribute and add to zone
		williePete.addWPZone(aZone) -- remember it so we can smoke it
	end
	
	-- add event handler
	world.addEventHandler(williePete)

	-- initialize all players from MX
	williePete.startPlayerGUI()

	-- start updates 
	williePete.updateWP() -- for tracking wp, at ups
	williePete.playerUpdate() -- for tracking players, at 1/s 

	
	trigger.action.outText("williePete v" .. williePete.version .. " loaded.", 30)

	return true
end

-- let's go 
if not williePete.start() then 
	trigger.action.outText("cf/x Willie Pete aborted: missing libraries", 30)
	williePete = nil 
end

--[[--
	Mechanics:
		- unit checks in with arty zone. if not in range of arty zone + safe dist, error 'not in range' is returned, else <artillery zone: status> is sent. <status can be ready, firing, or reloading>. Zone will advise on status change when checked in.
		- if unit leaves arty zone + safe dist, <leaving zone> is displayed and <checkout> is invoked
		- unit can check out any time
		- when checked in, any wp hitting the ground is remembered if still inside target zone 
		- player then gives 'target marked'
		- if artillery on cooldown, or wp not inside zone error, else fire sequence starts, and cooldown starts for entire zone 

--]]--