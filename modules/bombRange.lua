bombRange = {}
bombRange.version = "1.0.0"
bombRange.dh = 1 -- meters above ground level burst 

bombRange.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}

bombRange.bombs = {} -- live tracking
bombRange.ranges = {} -- all bomb ranges
bombRange.playerData = {} -- player accumulated data 
bombRange.unitComms = {} -- command interface per unit 
bombRange.tracking = false -- if true, we are tracking projectiles 
bombRange.myStatics = {} -- indexed by id 

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
	theZone.reportName = theZone:getBoolFromZoneProperty("reportName", true)
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
	if not bombRange.tracking then
		return 
	end
	if not target then return end 
	local theType = target:getTypeName()
	
	for idx, aType in pairs(bombRange.filterTypes) do 
		if theType == aType then return	end
	end 
	
	-- try and match target to my known statics, exit if match
	if not target.getID then return end -- units have no getID!
	local theID = tonumber(target:getID())
	if bombRange.myStatics[theID] then 
		return
	end 
	
	-- look through the tracked weapons for a match
	local filtered = {}
	local hasfound = false 
	for idx, b in pairs (bombRange.bombs) do
		if b.weapon == weapon then 
			hasfound = true 
			-- update b to current position and velocity 
			b.pos = weapon:getPoint()
			b.v = weapon:getVelocity()
			bombRange.impacted(b, target)
		else 
			table.insert(filtered, b)
		end
	end
	if hasfound then 
		bombRange.bombs = filtered
	end
end

function bombRange:onEvent(event)
	if not event.initiator then return end 
	local theUnit = event.initiator
	
	if event.id == 2 then -- hit
		if not event.weapon then return end 
		bombRange.suspectedHit(event.weapon, event.target)
		return 
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
function bombRange.impacted(weapon, target)
	local targetName = nil 	
	local ipos = weapon.pos -- default to weapon location 
	if target then
		ipos = target:getPoint()
		targetName = target:getDesc()
		if targetName then targetName = targetName.displayName end 
		if not targetName then targetName = target:getTypeName() end
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
	
	if theRange.smokeHits then 
		trigger.action.smoke(ipos, theRange.smokeColor) 
	end

	if (not target) and theRange.flagHits then -- only ground imparts are flagged
		local cty = dcsCommon.getACountryForCoalition(0) -- some neutral county
		local p = {x=ipos.x, y=ipos.z}
		local theStaticData = dcsCommon.createStaticObjectData(dcsCommon.uuid(weapon.type .. " impact"), theRange.flagType)
		dcsCommon.moveStaticDataTo(theStaticData, p.x, p.y)
		local theObject = coalition.addStaticObject(cty, theStaticData)
	end
	
	if theRange.reporter and theRange.details then 
		local t = math.floor((timer.getTime() - weapon.released) * 10) / 10
		local v = math.floor(dcsCommon.vMag(weapon.v)) 
		local tDist = dcsCommon.dist(ipos, weapon.relPos)/1000
		tDist = math.floor(tDist*100) /100
		trigger.action.outTextForGroup(weapon.gID, "impact of " .. weapon.type .. " released by " .. weapon.pName .. " from " .. weapon.uType .. " after traveling " .. tDist .. " km in " .. t .. " sec, impact velocity at impact is " .. v .. " m/s!", 30)
	end
	
	local msg = ""
	if theRange:pointInZone(ipos) then
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
		if theRange.reportName then msg = msg .. " " .. theRange.name end
		if theRange.details then msg = msg .. "(off-center by " .. math.floor(minDist *10)/10 .. " m)" end 
		msg = msg .. ", no hit."
		bombRange.addImpactForWeapon(weapon, false, 0)
	end 
	if theRange.reporter then 
		trigger.action.outTextForGroup(weapon.gID,msg , 30)
	end
	
end

function bombRange.updateBombs()
	
	local filtered = {} 
	for idx, theWeapon in pairs(bombRange.bombs) do 
		if Weapon.isExist(theWeapon.weapon) then 
			-- update pos and vel
			theWeapon.pos = theWeapon.weapon:getPoint()
			theWeapon.v = theWeapon.weapon:getVelocity()
			table.insert(filtered, theWeapon)
		else 
			-- interpolate the impact position from last position 
			bombRange.impacted(theWeapon)
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
	bombRange.ups = theZone:getNumberFromZoneProperty("ups", 20)
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

	return true 
end 

if not bombRange.start() then 
	trigger.action.outText("cf/x Bomb Range aborted: missing libraries", 30)
	bombRange = nil 
end

--
-- add persistence 
--