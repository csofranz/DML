guardianAngel = {}
guardianAngel.version = "2.0.2"
guardianAngel.ups = 10
guardianAngel.launchWarning = true -- detect launches and warn pilot 
guardianAngel.intervention = true -- remove missiles just before hitting
guardianAngel.explosion = -1 -- small poof when missile explodes. -1 = off. 
guardianAngel.verbose = false -- debug info 
guardianAngel.announcer = true -- angel talks to you 
guardianAngel.private = false -- angel only talks to group 
guardianAngel.autoAddPlayers = true 

guardianAngel.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}

--[[--
  Version History 
     1.0.0 - Initial version 
	 2.0.0 - autoAddPlayer 
	       - verbose 
		   - lib check
		   - config zone 
		   - sneaky detection logic 
		   - god intervention 100m
		   - detect re-acquisition
		   - addUnitToWatch supports string names
		   - detect non-miss 
		   - announcer
		   - intervene optional 
		   - launch warning optional 
	 2.0.1 - warnings go to group 
	       - invokeCallbacks added to module 
		   - reworked CB structure
		   - private option 
     2.0.2 - poof! explosion option to show explosion on intervention
           - can be dangerous	 


This script detects missiles launched against protected aircraft an 
removes them when they are about to hit
	 
--]]--

guardianAngel.minMissileDist = 50 -- m. below this distance the missile is killed by god, not the angel :) 
guardianAngel.myEvents = {1, 15, 20, 21, 23} -- 1 - shot, 15 - birth, 20 - enter unit, 21 - player leave unit, 23 - start shooting 
guardianAngel.safetyFactor = 1.8 -- for calculating dealloc range 
guardianAngel.unitsToWatchOver = {} -- I'll watch over these

guardianAngel.missilesInTheAir = {} -- missiles in the air

guardianAngel.callBacks = {} -- callbacks
-- callback signature: callBack(reason, targetUnitName, weaponName)
-- reasons (string): "launch", "miss", "reacquire", "trackloss", "disappear", "intervention"

function guardianAngel.addCallback(theCallback)
	if theCallback then 
		table.insert(guardianAngel.callBacks, theCallback)
	end
end

function guardianAngel.invokeCallbacks(reason, targetName, weaponName) 
	for idx, theCB in pairs(guardianAngel.callBacks) do
		theCB(reason, targetName, weaponName)
	end
end

--
-- units to watch 
--
function guardianAngel.addUnitToWatch(aUnit)
	if type(aUnit) == "string" then 
		aUnit = Unit.getByName(aUnit)
	end
	if not aUnit then return end 
	local unitName = aUnit:getName()
	guardianAngel.unitsToWatchOver[unitName] = aUnit
	if guardianAngel.verbose then 
		trigger.action.outText("+++gA: now watching unit " .. aUnit:getName(), 30)
	end
end

function guardianAngel.removeUnitToWatch(aUnit)
	if type(aUnit) == "string" then 
		aUnit = Unit.getByName(aUnit)
	end
	if not aUnit then return end 
	local unitName = aUnit:getName()
	if not unitName then return end 
	guardianAngel.unitsToWatchOver[unitName] = nil
	if guardianAngel.verbose then 
		trigger.action.outText("+++gA: no longer watching " .. aUnit:getName(), 30)
	end 
end

function guardianAngel.getWatchedUnitByName(aName)
	if not aName then return nil end 
	return guardianAngel.unitsToWatchOver[aName]
end

--
-- watch q items
--
function guardianAngel.createQItem(theWeapon, theTarget, detectProbability)
	if not theWeapon then return nil end 
	if not theTarget then return nil end 
	if not theTarget:isExist() then return nil end 
	if not detectProbability then detectProbability = 1.0 end 
	local theItem = {}
	theItem.theWeapon = theWeapon
	theItem.wP = theWeapon:getPoint() -- save location
	theItem.weaponName = theWeapon:getName()
	theItem.theTarget = theTarget
	theItem.tGroup = theTarget:getGroup()
	theItem.tID = theItem.tGroup:getID()
	
	theItem.targetName = theTarget:getName()
	theItem.launchTimeStamp = timer.getTime()
	theItem.lastCheckTimeStamp = -1000
	theItem.lastDistance = math.huge 
	theItem.detected = false 
	theItem.lostTrack = false -- so we can detect sneakies!
	theItem.missed = false -- just keep watching for re-ack
	return theItem 
end
--[[--
function guardianAngel.detectItem(theItem)
	if theItem.detected then return end 
	-- perform detection calculations here 
	
end
--]]--

-- calculate a point in direction from plane (pln) to weapon (wpn), dist meters 
function guardianAngel.calcSafeExplosionPoint(wpn, pln, dist)
	local dirToWpn = dcsCommon.vSub(wpn, pln) -- vector to weapon.
	local v = dcsCommon.vNorm(dirToWpn) -- |v| = 1
	local v = dcsCommon.vMultScalar(v, dist) -- |v| = dist 
	local newPoint = dcsCommon.vAdd(pln, v)
	return newPoint
end

function guardianAngel.monitorItem(theItem)
	local w = theItem.theWeapon
	local ID = theItem.tID
	if not w then return false end
	if not w:isExist() then 
		if (not theItem.missed) and (not theItem.lostTrack) then 
			local desc  = theItem.weaponName .. ": DISAPPEARED"
			if guardianAngel.announcer then 
				if guardianAngel.private then 
					trigger.action.outTextForGroup(ID, desc, 30) 
				else 
					trigger.action.outText(desc, 30) 
				end
			end 
			guardianAngel.invokeCallbacks("disappear", theItem.targetName, theItem.weaponName)
		end 
		return false 
	end 
	
	local t = theItem.theTarget
	local currentTarget = w:getTarget()
	local oldWPos = theItem.wP
	local A = w:getPoint() -- A is new point of weapon
	theItem.wp = A -- update new position, old is in oldWPos
	local B 
	if currentTarget then B = currentTarget:getPoint() else B = A end 
	
	local d = math.floor(dcsCommon.dist(A, B))
	local desc = theItem.weaponName .. ": "
	if t == currentTarget then 
		desc = desc .. "tracking " .. theItem.targetName .. ", d = " .. d .. "m"
		local vcc = dcsCommon.getClosingVelocity(t, w)
		desc = desc .. ", Vcc = " .. math.floor(vcc) .. "m/s"
	   
		-- now calculate lethal distance: vcc is in meters per second
		-- and we sample ups times per second
		-- making the missile cover vcc / ups meters in the next 
		-- timer interval. If it now is closer than that, we have to 
		-- destroy the missile
		local lethalRange = math.abs(vcc / guardianAngel.ups) * guardianAngel.safetyFactor
		desc = desc .. ", LR= " .. math.floor(lethalRange) .. "m"
		if guardianAngel.intervention and 
		   d <= lethalRange + 10 
		then 
			desc = desc .. " ANGEL INTERVENTION"
			if theItem.lostTrack then desc = desc .. " (little sneak!)" end 
			if theItem.missed then desc = desc .. " (missed you!)" end 
			
			
			if guardianAngel.announcer then 
				if guardianAngel.private then 
					trigger.action.outTextForGroup(ID, desc, 30) 
				else 
					trigger.action.outText(desc, 30) 
				end
			end
			guardianAngel.invokeCallbacks("intervention", theItem.targetName, theItem.weaponName)
			w:destroy()
			
			-- now add some showy explosion so the missile
			-- doesn't just disappear 
			if guardianAngel.explosion > 0 then 
				local xP = guardianAngel.calcSafeExplosionPoint(A,B, 500)
				trigger.action.explosion(xP, guardianAngel.explosion)
			end
			
			return false -- remove from list 
		end
		
		if guardianAngel.intervention and 
		   d <= guardianAngel.minMissileDist -- god's override 
		then 
			desc = desc .. " GOD INTERVENTION"
			if theItem.lostTrack then desc = desc .. " (little sneak!)" end 
			if theItem.missed then desc = desc .. " (missed you!)" end 
			
			if guardianAngel.announcer then 
				if guardianAngel.private then 
					trigger.action.outTextForGroup(ID, desc, 30) 
				else 
					trigger.action.outText(desc, 30) 
				end
			end
			guardianAngel.invokeCallbacks("intervention", theItem.targetName, theItem.weaponName)
			w:destroy()
			if guardianAngel.explosion > 0 then 
				local xP = guardianAngel.calcSafeExplosionPoint(A,B, 500)
				trigger.action.explosion(xP, guardianAngel.explosion) 
			end
			return false -- remove from list 
		end
	else 
		if not theItem.lostTrack then 
			desc = desc .. "Missile LOST TRACK"
			
			if guardianAngel.announcer then
				if guardianAngel.private then 
					trigger.action.outTextForGroup(ID, desc, 30) 
				else 
					trigger.action.outText(desc, 30) 
				end			 
			end
			guardianAngel.invokeCallbacks("trackloss", theItem.targetName, theItem.weaponName)
			theItem.lostTrack = true 
		end 
		theItem.lastDistance = d 
	    return true -- true because they can re-acquire! 
	end
	
	if d > theItem.lastDistance then
		-- this can be wrong because if a missile is launched 
		-- at an angle, it can initially look as if it missed 
		if not theItem.missed then 
			desc = desc .. " Missile MISSED!"
			
			if guardianAngel.announcer then 
				if guardianAngel.private then 
					trigger.action.outTextForGroup(ID, desc, 30) 
				else 
					trigger.action.outText(desc, 30) 
				end
			end
			guardianAngel.invokeCallbacks("miss", theItem.targetName, theItem.weaponName)
			theItem.missed = true 
		end 
		theItem.lastDistance = d 
		return true -- better not disregard - they can re-acquire!
	end
	
	if theItem.missed and d < theItem.lastDistance then 
		desc = desc .. " Missile RE-ACQUIRED!"
		
		if guardianAngel.announcer then 
			if guardianAngel.private then 
				trigger.action.outTextForGroup(ID, desc, 30) 
			else 
				trigger.action.outText(desc, 30) 
			end
		end
		theItem.missed = false  
		guardianAngel.invokeCallbacks("reacquire", theItem.targetName, theItem.weaponName)
	end
	
	theItem.lastDistance = d 
	
	return true 
end

function guardianAngel.monitorMissiles()
	local newArray = {} -- we collect all still existing missiles here 
	                    -- and replace missilesInTheAir with that for next round
	for idx, anItem in pairs (guardianAngel.missilesInTheAir) do 
		-- we now have an item 
		-- see about detection 
		-- guardianAngel.detectItem(anItem)
		
		-- see if the weapon is still in existence
		stillAlive = guardianAngel.monitorItem(anItem)
		if stillAlive then 
			table.insert(newArray, anItem) 
		end 
	end
	guardianAngel.missilesInTheAir = newArray
end

--
-- E V E N T   P R O C E S S I N G
-- 
function guardianAngel.isInteresting(eventID) 
	-- return true if we are interested in this event, false else 
	for key, evType in pairs(guardianAngel.myEvents) do 
		if evType == eventID then return true end
	end
	return false 
end

-- event pre-proc: only return true if we need to process this event
function guardianAngel.preProcessor(event)
	-- all events must have initiator set
	if not event.initiator then return false end	
	-- see if the event ID is interesting for us 
	local interesting = guardianAngel.isInteresting(event.id) 
	return interesting  
end

function guardianAngel.postProcessor(event)
	-- don't do anything for now
end

-- event callback from dcsCommon event handler. preProcessor has returned true 
function guardianAngel.somethingHappened(event)
	-- when this is invoked, the preprocessor guarantees that
	-- it's an interesting event and has initiator 
	local ID = event.id
	local theUnit = event.initiator
	local playerName = theUnit:getPlayerName() -- nil if not a player
	
	if ID == 15 and playerName then 
		-- this is a player created unit 
		if guardianAngel.verbose then 
			trigger.action.outText("+++gA: unit born " .. theUnit:getName(), 30)
		end 
		if guardianAngel.autoAddPlayers then 
			guardianAngel.addUnitToWatch(theUnit)
		end 
		return 
	end
	
	if ID == 20 and playerName then 
		-- this is a player entered unit 
		if guardianAngel.verbose then 
			trigger.action.outText("+++gA: player seated in unit " .. theUnit:getName(), 30)
		end 
		if guardianAngel.autoAddPlayers then 
			guardianAngel.addUnitToWatch(theUnit)
		end
		return 
	end
	
	if ID == 21 and playerName then
		guardianAngel.removeUnitToWatch(theUnit)
		return
	end

	if ID == 15 or ID == 20 or ID == 21 then 
		-- non-player events of same type, disregard
		return 
	end

	
	if ID == 1 then 
		-- someone shot something. see if it is fire directed at me 
		local theWeapon = event.weapon 
		local theTarget 
		if theWeapon then 
			theTarget = theWeapon:getTarget() 
		else
			return 
		end 
		if not theTarget then  
			return
		end 
		if not theTarget:isExist() then return end 
		
		-- if we get here, we have weapon aimed at a target 
		local targetName = theTarget:getName()
		local watchedUnit = guardianAngel.getWatchedUnitByName(targetName)
		if not watchedUnit then return end -- fired at some other poor sucker, we don't care
		
		-- if we get here, someone fired a guided weapon at my watched units
		-- create a new item for my queue
		local theQItem = guardianAngel.createQItem(theWeapon, theTarget) -- prob 100
		table.insert(guardianAngel.missilesInTheAir, theQItem)
		guardianAngel.invokeCallbacks("launch", theQItem.targetName, theQItem.weaponName)
		
		local unitHeading = dcsCommon.getUnitHeadingDegrees(theTarget)
		local A = theWeapon:getPoint()
		local B = theTarget:getPoint()
		local oclock = dcsCommon.clockPositionOfARelativeToB(A, B, unitHeading)

		local grpID = theTarget:getGroup():getID()
		if guardianAngel.launchWarning then 
			-- currently, we always detect immediately 
			-- can be moved to update()
			if guardianAngel.private then 
				trigger.action.outTextForGroup(grpID, "Missile, missile, missile, " .. oclock .. " o clock", 30)
			else 
				trigger.action.outText("Missile, missile, missile, " .. oclock .. " o clock", 30)
			end
			
			theQItem.detected = true -- remember: we detected and warned already
		end 
		return
	end
	
	local myType = theUnit:getTypeName()
	if guardianAngel.verbose then 
		trigger.action.outText("+++gA: event " .. ID .. " for unit " .. theUnit:getName() .. " of type " .. myType, 30)
	end
end

--
-- U P D A T E   L O O P 
--


function guardianAngel.update()
	timer.scheduleFunction(guardianAngel.update, {}, timer.getTime() + 1/guardianAngel.ups)
	
	guardianAngel.monitorMissiles()
end

function guardianAngel.collectPlayerUnits()
	-- make sure we have all existing player units 
	-- at start of game 
	if not guardianAngel.autoAddPlayer then return end 
	
	for i=1, 2 do 
		-- currently only two factions in dcs 
		factionUnits = coalition.getPlayers(i)
		for idx, aPlayerUnit in pairs(factionUnits) do 
		-- add all existing faction units
			guardianAngel.addUnitToWatch(aPlayerUnit)
		end
	end
end

--
-- config reading
--
function guardianAngel.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("guardianAngelConfig") 
	if not theZone then 
		trigger.action.outText("+++gA: no config zone!", 30) 
		return 
	end 
	if guardianAngel.verbose then 
		trigger.action.outText("+++gA: found config zone!", 30) 
	end 
	
	guardianAngel.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	guardianAngel.autoAddPlayer = cfxZones.getBoolFromZoneProperty(theZone, "autoAddPlayer", true)
	guardianAngel.launchWarning = cfxZones.getBoolFromZoneProperty(theZone, "launchWarning", true)
	guardianAngel.intervention = cfxZones.getBoolFromZoneProperty(theZone, "intervention", true)
	guardianAngel.announcer = cfxZones.getBoolFromZoneProperty(theZone, "announcer", true)
	guardianAngel.private = cfxZones.getBoolFromZoneProperty(theZone, "private", false)
	guardianAngel.explosion = cfxZones.getNumberFromZoneProperty(theZone, "explosion", -1)
end


--
-- start 
--
function guardianAngel.start()
	-- lib check 
	if not dcsCommon.libCheck("cfx Guardian Angel", 
		guardianAngel.requiredLibs) then
		return false 
	end
	
	-- read config 
	guardianAngel.readConfigZone()
	
	-- install event monitor 
	dcsCommon.addEventHandler(guardianAngel.somethingHappened,
							  guardianAngel.preProcessor,
							  guardianAngel.postProcessor)
	
	-- collect all units that are already in the game at this point
	guardianAngel.collectPlayerUnits()
	
	-- start update 
	guardianAngel.update()
	
	trigger.action.outText("Guardian Angel v" .. guardianAngel.version .. " running", 30)
	return true 
end

function guardianAngel.testCB(reason, targetName, weaponName)
	trigger.action.outText("gA - CB for ".. reason .. ": " .. targetName .. " w: " .. weaponName, 30)
end

-- go go go 
if not guardianAngel.start() then 
	trigger.action.outText("Loading Guardian Angel failed.", 30)
	guardianAngel = nil 
end

-- test callback
--guardianAngel.addCallback(guardianAngel.testCB)
--guardianAngel.invokeCallbacks("A", "B", "C")
