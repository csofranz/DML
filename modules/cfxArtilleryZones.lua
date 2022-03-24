cfxArtilleryZones = {}
cfxArtilleryZones.version = "2.2.0" 
cfxArtilleryZones.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
cfxArtilleryZones.verbose = false 
--[[--
	Version History
 1.0.0 - initial version
 1.0.1 - simSmokeZone
 2.0.0 - zone attributes for shellNum, shellVariance,
         cooldown, addMark, transitionTime
	   - doFireAt method
	   - simFireAt now calls doFireAt 
	   - added all params to crteateArtilleryTarget
	   - createArtillerTarget replaced createArtilleryZone 
	   - addMark now used so arty zones can be hidden on map
	   - added triggerFlag attribute 
	   - update now fires every time when flag changes 
 2.0.1 - added verbose setting 
	   - base accuracy now derived from radius 
	   - added coalition check for ZonesInRange
	   - att transition time to zone info mark
	   - made compatible with linked zones 
	   - added silent attribute 
	   - added transition time to arty command chatter 
 2.0.2 - boom?, arty? synonyms 
 2.1.0 - DML Flag Support 
	   - code cleanup
 2.2.0 - DML Watchflag integration 
 
	Artillery Target Zones *** EXTENDS ZONES ***
	Target Zones for artillery. Can determine which zones are in range and visible and then handle artillery barrage to this zone 
	Copyright (c) 2021, 2022 by Christian Franz and cf/x AG

	USAGE
	Via ME: Add the relevant attributes to the zone 
	Via Script: Use createArtilleryTarget() 


    Callbacks
	when fire at target is invoked, a callback can be 
	invoked so your code knows that fire control has been 
	given a command or that projectiles are impacting.
	Signature
	callback(rason, zone, data), with 
	reason: 'firing' - fire command given for zone 
	        'impact' a projectile has hit
	zone:   artilleryZone
	data:   empty on 'fire' 
			.point where impact point
			.strength power of explosion 
	
--]]--
cfxArtilleryZones.artilleryZones = {}
cfxArtilleryZones.updateDelay = 1 -- every second 


--
-- C A L L B A C K S 
-- 
cfxArtilleryZones.callbacks = {}
function cfxArtilleryZones.addCallback(theCallback)
	table.insert(cfxArtilleryZones.callbacks, theCallback)
end

function cfxArtilleryZones.invokeCallbacksFor(reason, zone, data)
	for idx, theCB in pairs (cfxArtilleryZones.callbacks) do 
		theCB(reason, zone, data)
	end
end

function cfxArtilleryZones.demoCallback(reason, zone, data)
	-- reason: 'fire' or 'impact'
	-- fire has no data, impact has data.point and data.strength 
end

function cfxArtilleryZones.createArtilleryTarget(name, point, coalition, spotRange, transitionTime, baseAccuracy, shellNum, shellStrength, shellVariance, triggerFlag, addMark, cooldown, silent, autoAdd) -- was: createArtilleryZone, changed params list 
	if not point then return end 
	if not autoAdd then autoAdd = false end 
	if not coalition then coalition = 0 end 
	if not spotRange then spotRange = 3000 end 
	if not shellStrength then shellStrength = 500 end 
	if not transitionTime then transitionTime = 20 end 
	if not shellNum then shellNum = 17 end 
	if not addMark then addMark = false end 
	if not name then name = "dftZName" end 
	if not shellVariance then shellVariance = 0.2 end 
	if not cooldown then cooldown = 120 end 
	if not baseAccuracy then baseAccuracy = 100 end 
	if not silent then silent = false end 
	
	name = cfxZones.createUniqueZoneName(name)
	
	local newZone = cfxZones.createSimpleZone(name,
		point, 
		100, 
		autoAdd)
	newZone.spotRange = spotRange
	newZone.coalition = coalition
	newZone.landHeight = land.getHeight({x = newZone.point.x, y= newZone.point.z})
	newZone.transitionTime = transitionTime
	newZone.shellNum = shellNum 
	newZone.shellStrength = shellStrength
	newZone.triggerFlag = triggerFlag -- can be nil 
	if triggerFlag then 
		newZone.lastTriggerValue = trigger.misc.getUserFlag(triggerFlag) -- save last value
	end 
	newZone.addMark = addMark
	if autoAdd then cfxArtilleryZones.addArtilleryZone(newZone) end 
	newZone.shellVariance = shellVariance
	newZone.cooldown = cooldown
	newZone.silent = silent 
end

function cfxArtilleryZones.processArtilleryZone(aZone)
	aZone.artilleryTarget = cfxZones.getStringFromZoneProperty(aZone, "artilleryTarget", aZone.name)
	aZone.coalition = cfxZones.getCoalitionFromZoneProperty(aZone, "coalition", 0) -- side that marks it on map, and who fires arty
	aZone.spotRange = cfxZones.getNumberFromZoneProperty(aZone, "spotRange", 3000) -- FO max range to direct fire
	aZone.shellStrength = cfxZones.getNumberFromZoneProperty(aZone, "shellStrength", 500) -- power of shells (strength)

	aZone.shellNum = cfxZones.getNumberFromZoneProperty(aZone, "shellNum", 17) -- number of shells in bombardment
	aZone.transitionTime = cfxZones.getNumberFromZoneProperty(aZone, "transitionTime", 20) -- average time of travel for projectiles 
	aZone.addMark = cfxZones.getBoolFromZoneProperty(aZone, "addMark", true) -- note: defaults to true 
	aZone.shellVariance = cfxZones.getNumberFromZoneProperty(aZone, "shellVariance", 0.2) -- strength of explosion can vary by +/- this amount
	
	-- watchflag:
	-- triggerMethod
	aZone.artyTriggerMethod = cfxZones.getStringFromZoneProperty(aZone, "artyTriggerMethod", "change")

	if cfxZones.hasProperty(aZone, "triggerMethod") then 
		aZone.artyTriggerMethod = cfxZones.getStringFromZoneProperty(aZone, "triggerMethod", "change")
	end
	
	if cfxZones.hasProperty(aZone, "f?") then 
		aZone.artyTriggerFlag = cfxZones.getStringFromZoneProperty(aZone, "f?", "none")
	end
	--[[--
	if cfxZones.hasProperty(aZone, "triggerFlag") then 
		aZone.artyTriggerFlag = cfxZones.getStringFromZoneProperty(aZone, "triggerFlag", "none")
	end
	--]]--
	if cfxZones.hasProperty(aZone, "artillery?") then 
		aZone.artyTriggerFlag = cfxZones.getStringFromZoneProperty(aZone, "artillery?", "none")
	end
	if cfxZones.hasProperty(aZone, "in?") then 
		aZone.artyTriggerFlag = cfxZones.getStringFromZoneProperty(aZone, "in?", "none")
	end
	
	if aZone.artyTriggerFlag then 
		aZone.lastTriggerValue = trigger.misc.getUserFlag(aZone.artyTriggerFlag) -- save last value
	end
	aZone.cooldown =cfxZones.getNumberFromZoneProperty(aZone, "cooldown", 120) -- seconds 
	aZone.baseAccuracy = cfxZones.getNumberFromZoneProperty(aZone, "baseAccuracy", aZone.radius) -- meters from center radius shell impact
	-- use zone radius as mase accuracy for simple placement
	aZone.silent = cfxZones.getBoolFromZoneProperty(aZone, "silent", false)
end

function cfxArtilleryZones.addArtilleryZone(aZone)
	-- add landHeight to this zone 
	aZone.landHeight = land.getHeight({x = aZone.point.x, y= aZone.point.z})
	-- mark it on the map 
	aZone.artyCooldownTimer = -1000 
	cfxArtilleryZones.placeMarkForSide(aZone.point, aZone.coalition, aZone.name .. ", FO=" .. aZone.spotRange .. "m" .. ", tt=" .. aZone.transitionTime)
	table.insert(cfxArtilleryZones.artilleryZones, aZone)
end

function cfxArtilleryZones.findArtilleryZoneNamed(aName)
	aZone = cfxZones.getZoneByName(aName) 
	if not aZone then return nil end 
	-- check if it is an arty zone 
	if not aZone.artilleryTarget then return nil end 
	-- all is well
	return aZone 
end

function cfxArtilleryZones.removeArtilleryZone(aZone)
	if type(aZone) == "string" then 
		aZone = cfxArtilleryZones.findArtilleryZoneNamed(aZone) 
	end
	if not aZone then return end 
	
	-- now create new table 
	local filtered = {}
	for idx, theZone in pairs(cfxArtilleryZones.artilleryZones) do 
		if theZone ~= aZone then 
			table.insert(filtered, theZone)
		end 
	end
	cfxArtilleryZones.artilleryZones = filtered 
end

function cfxArtilleryZones.artilleryZonesInRangeOfUnit(theUnit)
	if not theUnit then return {} end 
	if not theUnit:isExist() then return {} end
	local myCoalition = theUnit:getCoalition()
	local zonesInRange = {}
	local p = theUnit:getPoint()
	
	for idx, aZone in pairs(cfxArtilleryZones.artilleryZones) do 
		-- is it one of mine?
		if aZone.coalition == myCoalition then
			-- is it close enough?
			local zP = cfxZones.getPoint(aZone)
			aZone.landHeight = land.getHeight({x = zP.x, y= zP.z})
			local zonePoint = {x = zP.x, y = aZone.landHeight, z = zP.z}
			local d = dcsCommon.dist(p,zonePoint)
			if d < aZone.spotRange then 
				-- LOS check 
				if land.isVisible(p, zonePoint) then 
					-- yeah, add to list 
					table.insert(zonesInRange, aZone)
				end
			end
		end 
	end
	return zonesInRange
end


--
-- MARK ON MAP
--
cfxArtilleryZones.uuidCount = 0
function cfxArtilleryZones.uuid()
	cfxArtilleryZones.uuidCount = cfxArtilleryZones.uuidCount + 1
	return cfxArtilleryZones.uuidCount
end

function cfxArtilleryZones.placeMarkForSide(location, theSide, theDesc) 
	local theID = cfxArtilleryZones.uuid()
	local theDesc = "ARTY: ".. theDesc
	trigger.action.markToCoalition(
					theID, 
					theDesc, 
					location, 
					theSide, 
					false, 
					nil)
	return theID
end

function cfxArtilleryZones.removeMarkForArgs(args)
	local theID = args[1]	
	trigger.action.removeMark(theID)
end 

--
-- FIRE AT A ZONE
-- 

--
-- BOOM command
--
function cfxArtilleryZones.doBoom(args)
	trigger.action.explosion(args.point, args.strength)
	data = {}
	data.point = args.point 
	data.strength = args.strength 
	cfxArtilleryZones.invokeCallbacksFor('impact', args.zone, data)
end

function cfxArtilleryZones.doFireAt(aZone, maxDistFromCenter)
	if type(aZone) == "string" then 
		local mZone = cfxArtilleryZones.findArtilleryZoneNamed(aZone)
		aZone = mZone
	end
	if not aZone then return end 

	if not maxDistFromCenter then maxDistFromCenter = aZone.baseAccuracy end 
	
	local accuracy = maxDistFromCenter 
	local zP = cfxZones.getPoint(aZone)
	aZone.landHeight = land.getHeight({x = zP.x, y= zP.z}) 
	local center = {x=zP.x, y=aZone.landHeight, z=zP.z} -- center of where shells hit 
	local shellNum = aZone.shellNum
	local shellBaseStrength = aZone.shellStrength
	local shellVariance = aZone.shellVariance  
	local transitionTime = aZone.transitionTime
	
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

		timer.scheduleFunction(cfxArtilleryZones.doBoom, boomArgs, timer.getTime() + transitionTime + timeVar)
	end
	
	-- invoke callbacks 
	cfxArtilleryZones.invokeCallbacksFor('fire', aZone, {})
end

function cfxArtilleryZones.simFireAtZone(aZone, aGroup, dist)
	
	if not dist then dist = aZone.spotRange end 
	local shellBaseStrength = aZone.shellStrength 

	local maxAccuracy = 100 -- m radius when close
	local minAccuracy = 500 -- m radius whan at max sport dist 
	local currAccuracy = minAccuracy 
	if dist <= 1000 then 
		currAccuracy = maxAccuracy 
	else 
		local percent = (dist-1000) / (aZone.spotRange-1000)
		currAccuracy = dcsCommon.lerp(maxAccuracy, minAccuracy, percent)
	end
	currAccuracy = math.floor(currAccuracy)
	cfxArtilleryZones.doFireAt(aZone, currAccuracy) 

	aZone.artyCooldownTimer = timer.getTime() + aZone.cooldown -- 120 -- 2 minutes reload
	if not aZone.silent then 
		local addInfo = " with d=" .. dist .. ", var = " .. currAccuracy .. " pB=" .. shellBaseStrength .. " tt=" .. aZone.transitionTime
	
		trigger.action.outTextForCoalition(aGroup:getCoalition(), "Artillery firing on ".. aZone.name .. addInfo, 30)
	end 
	--trigger.action.smoke(center, 2) -- mark location visually
end 

function cfxArtilleryZones.simSmokeZone(aZone, aGroup, aColor)
	-- this is simsmoke: transition time is fixed, and we do not
	-- use arty units. all very simple. we merely place smoke on
	-- ground 
	if not aColor then aColor = "red" end 
	if type(aColor) == "string" then 
		aColor = dcsCommon.smokeColor2Num(aColor)
	end
	local zP = cfxZones.getPoint(aZone)
	aZone.landHeight = land.getHeight({x = zP.x, y= zP.z})
	
	local transitionTime = aZone.transitionTime --17 -- seconds until phosphor lands
	local center = {x = zP.x, 
					y =aZone.landHeight + 3, 
					z = zP.z
				   } -- center of where shells hit 
	-- we now can 'dirty' the position by something. not yet
	local currAccuracy = 200

	local thePoint = dcsCommon.randomPointInCircle(currAccuracy, 50, center.x, center.z)
	
	timer.scheduleFunction(cfxArtilleryZones.doSmoke, {thePoint, aColor}, timer.getTime() + transitionTime)
	
	if not aGroup then return end 
	if aZone.silent then return end 
	
	trigger.action.outTextForCoalition(aGroup:getCoalition(), "Artillery firing single phosphor round at ".. aZone.name, 30)
end 

function cfxArtilleryZones.doSmoke(args) 
	local thePoint = args[1]
	local aColor = args[2]
	dcsCommon.markPointWithSmoke(thePoint, aColor)
end

--
-- UPDATE
--

function cfxArtilleryZones.update()
	-- call me in a couple of minutes to 'rekindle'
	timer.scheduleFunction(cfxArtilleryZones.update, {}, timer.getTime() + cfxArtilleryZones.updateDelay)
	
	-- iterate all zones to see if a trigger has changed 
	for idx, aZone in pairs(cfxArtilleryZones.artilleryZones) do 
		if cfxZones.testZoneFlag(aZone, aZone.artyTriggerFlag, aZone.artyTriggerMethod, "lastTriggerValue") then
			-- a triggered release!
			cfxArtilleryZones.doFireAt(aZone) -- all from zone vars!	
			if cfxArtilleryZones.verbose then 
				local addInfo = " with var = " .. aZone.baseAccuracy .. " pB=" .. aZone.shellStrength
				trigger.action.outText("Artillery T-Firing on ".. aZone.name .. addInfo, 30)
			end 
		end
		
	
		-- old code
		if aZone.artyTriggerFlag then 
			local currTriggerVal = cfxZones.getFlagValue(aZone.artyTriggerFlag, aZone) -- trigger.misc.getUserFlag(aZone.artyTriggerFlag)
			if currTriggerVal ~= aZone.lastTriggerValue
			then 
				-- a triggered release!
				cfxArtilleryZones.doFireAt(aZone) -- all from zone vars!
				
				if cfxArtilleryZones.verbose then 
					local addInfo = " with var = " .. aZone.baseAccuracy .. " pB=" .. aZone.shellStrength
					trigger.action.outText("Artillery T-Firing on ".. aZone.name .. addInfo, 30)
				end 
				aZone.lastTriggerValue = currTriggerVal
			end

		end
	end
end

--
-- START 
--

function cfxArtilleryZones.start()
	if not dcsCommon.libCheck("cfx Artillery Zones", 
		cfxArtilleryZones.requiredLibs) then
		return false 
	end
	
	-- collect all spawn zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("artilleryTarget")
	
	-- now create a spawner for all, add them to the spawner updater, and spawn for all zones that are not
	-- paused 
	for k, aZone in pairs(attrZones) do 
		cfxArtilleryZones.processArtilleryZone(aZone) -- process attribute and add to zone
		cfxArtilleryZones.addArtilleryZone(aZone) -- remember it so we can smoke it
	end

	-- start update loop
	cfxArtilleryZones.update()
	
	-- say hi
	trigger.action.outText("cfx Artillery Zones v" .. cfxArtilleryZones.version .. " started.", 30)
	return true 
end

-- let's go 
if not cfxArtilleryZones.start() then 
	trigger.action.outText("cf/x Artillery Zones aborted: missing libraries", 30)
	cfxArtilleryZones = nil 
end

