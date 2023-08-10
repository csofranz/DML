guardianAngel = {}
guardianAngel.version = "3.0.5"
guardianAngel.ups = 10
guardianAngel.name = "Guardian Angel" -- just in case someone accesses .name  
guardianAngel.launchWarning = true -- detect launches and warn pilot 
guardianAngel.intervention = true -- remove missiles just before hitting
guardianAngel.explosion = -1 -- small poof when missile explodes. -1 = off. 
guardianAngel.verbose = false -- debug info 
guardianAngel.announcer = true -- angel talks to you 
guardianAngel.private = false -- angel only talks to group 
guardianAngel.autoAddPlayers = true 

guardianAngel.active = true -- can be turned on / off 

guardianAngel.angelicZones = {} 

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
	 2.0.3 - fxDistance 
	       - mea cupa capability 
	 3.0.0 - on/off and switch monitoring
		   - active flag 
		   - zones to designate protected aircraft 
		   - zones to designate unprotected aircraft 
		   - improved gA logging
		   - missilesAndTargets log 
		   - re-targeting detection 
		   - removed bubble check 
		   - retarget Item code 
		   - hardened missile disappear code 
		   - all missiles are now tracked regardless whom they aim for 
		   - removed item.wp
	 3.0.1 - corrected error on collateral (missing delay)
	       - Supporst cloned units 
		   - removed legacy code 
	 3.0.2 - added guardianAngel.name for those who use local flags on activate
	 3.0.3 - monitorItem() guards against loss of target (nil)
	 3.0.4 - launchSound attribute 
		   - interventionSound attribute 
	 3.0.5 - better missiole names, their object IDs seem to have disappeared, also storing launcher name
		   - msgTime to control how long warnings remain on the screen
		   - disappear message now only on verbose 
		   - dmlZones 
		   

This script detects missiles launched against protected aircraft an 
removes them when they are about to hit
	 
--]]--

guardianAngel.minMissileDist = 50 -- m. below this distance the missile is killed by god, not the angel :) 
guardianAngel.myEvents = {1, 15, 20, 21, 23, 2} -- 1 - shot, 15 - birth, 20 - enter unit, 21 - player leave unit, 23 - start shooting 
-- added 2 (hit) event to see if angel was defeated
guardianAngel.safetyFactor = 1.8 -- for calculating dealloc range 
guardianAngel.unitsToWatchOver = {} -- I'll watch over these

guardianAngel.missilesInTheAir = {} -- missiles in the air
guardianAngel.missilesAndTargets = {} -- permanent log which missile was aimed at whom 
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
	local isNew = guardianAngel.unitsToWatchOver[unitName] == nil 
	guardianAngel.unitsToWatchOver[unitName] = aUnit
	if guardianAngel.verbose then 
		if isNew then 
			trigger.action.outText("+++gA: now watching unit " .. unitName, 30)
		else 
			trigger.action.outText("+++gA: updating unit " .. unitName, 30)
		end
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
function guardianAngel.createQItem(theWeapon, theTarget, threat, launcher)
	if not theWeapon then return nil end 
	if not theTarget then return nil end 
	if not theTarget:isExist() then return nil end 
	if not threat then threat = false end 
	-- if an item is not a 'threat' it means that we merely 
	-- watch it for re-targeting purposes 

	local theItem = {}
	local oName = tostring(theWeapon:getName())
	if not oName or #oName < 1 then oName = dcsCommon.numberUUID() end 
	local wName = ""
	if theWeapon.getDisplayName then 
		wName = theWeapon:getDisplayName() -- does this even exist any more?
	elseif theWeapon.getTypeName then 
		wName = theWeapon:getTypeName()
	else 
		wName = "<Generic>" 
	end 
	wName = wName .. "-" .. oName
	local launcherName = launcher:getTypeName() .. " " .. launcher:getName()
	
	theItem.theWeapon = theWeapon -- weapon that we are tracking 
	theItem.weaponName = wName -- theWeapon:getName()
	-- usually weapons have no 'name' except an ID, so let's get the 
	-- type or display name. Weapons often have no display name.
	if guardianAngel.verbose then 
		trigger.action.outText("gA: tracking missile <" .. wName .. "> launched by <" .. launcherName .. ">", guardianAngel.msgTime)
	end 
	theItem.theTarget = theTarget
	theItem.tGroup = theTarget:getGroup()
	theItem.tID = theItem.tGroup:getID()
	
	theItem.targetName = theTarget:getName()
	theItem.launchTimeStamp = timer.getTime()
	theItem.lastDistance = math.huge 
	theItem.detected = false 
	theItem.missed = false -- just keep watching for re-ack
	theItem.threat = threat 
	theItem.lastDesc = "(new)"
	theItem.timeStamp = timer.getTime() 
	theItem.launcher = launcherName
	return theItem 
end

function guardianAngel.retargetItem(theItem, theTarget, threat)
	theItem.theTarget = nil -- may cause trouble 
	if not theTarget or not theTarget:isExist() then 
		theItem.threat = false
		theItem.timeStamp = timer.getTime() 
		theItem.target = nil 
		theItem.targetName = "(substitute)"
		theItem.lastDistance = math.huge 
		theItem.missed = false
		theItem.lastDesc = "(retarget)"
		return 
	end 
	if not threat then threat = false end
	theItem.timeStamp = timer.getTime() 
	theItem.threat = threat 
	
	theItem.theTarget = theTarget
	if not theTarget.getGroup then 
		local theCat = theTarget:getCategory()
		if theCat ~= 2 then 
			-- not a weapon / flare
			trigger.action.outText("*** gA: WARNING: <" .. theTarget:getName() .. "> has no getGroup and is of category <" .. theCat .. ">!!!", 30)
		
		else 
			-- target is a weapon (flare/chaff/decoy), all is well
		end
	else
		theItem.tGroup = theTarget:getGroup()
		theItem.tID = theItem.tGroup:getID()
	end 
	theItem.targetName = theTarget:getName()
	theItem.lastDistance = math.huge 
	--theItem.lostTrack = false
	theItem.missed = false
	theItem.lastDesc = "(retarget)"
end

function guardianAngel.getQItemForWeaponNamed(theName)
	for idx, theItem in pairs (guardianAngel.missilesInTheAir) do 
		if theItem.weaponName == theName then 
			return theItem
		end 
	end
	return nil 
end

-- calculate a point in direction from plane (pln) to weapon (wpn), dist meters 
function guardianAngel.calcSafeExplosionPoint(wpn, pln, dist)
	local dirToWpn = dcsCommon.vSub(wpn, pln) -- vector to weapon.
	local v = dcsCommon.vNorm(dirToWpn) -- |v| = 1
	local v = dcsCommon.vMultScalar(v, dist) -- |v| = dist 
	local newPoint = dcsCommon.vAdd(pln, v)
	--trigger.action.outText("+++ gA: safe dist is ".. dist, 30)
	return newPoint
end


function guardianAngel.monitorItem(theItem)
	local w = theItem.theWeapon
	local ID = theItem.tID
	if not w then return false end
	if not w:isExist() then 
		--if (not theItem.missed) and (not theItem.lostTrack) then 
			
			--[[--
			if guardianAngel.announcer and theItem.threat then 
				local desc  = theItem.weaponName .. ": DISAPPEARED"
				if guardianAngel.private then 
					trigger.action.outTextForGroup(ID, desc, guardianAngel.msgTime) 
				else 
					trigger.action.outText(desc, guardianAngel.msgTime) 
				end
			end 
			--]]--
			if guardianAngel.verbose then
				trigger.action.outText("+++gA: missile disappeared: <" .. theItem.weaponName .. ">, aimed at <" .. theItem.targetName .. ">",30)
			end
			
			guardianAngel.invokeCallbacks("disappear", theItem.targetName, theItem.weaponName)
		-- end 
		return false 
	end 
	
	local t = theItem.theTarget
	local currentTarget = w:getTarget()
	
	-- Re-target check. did missile pick a new target?
	-- this can happen with any missile, even threat missiles, 
	-- so do this always!
	local ctName = nil 
	if currentTarget and Object.isExist(currentTarget) then 
		-- get current name to check against last target name 
		ctName = currentTarget:getName() 
	else 
		-- currentTarget has disappeared, kill the 'threat flag'
		-- theItem.threat = false 
		ctName = "***guardianangel.not.set"
	end 
	
	if ctName and ctName ~= theItem.targetName then 
		if guardianAngel.verbose then 
			--trigger.action.outText("+++gA: RETARGETING for <" .. theItem.weaponName .. ">: from <" .. theItem.targetName .. "> to <" .. ctName .. ">", 30)
		end 
		
		-- see if it's a threat to us now 
		local watchedUnit = guardianAngel.getWatchedUnitByName(ctName)
		
		-- update the db who's seeking who 
		guardianAngel.missilesAndTargets[theItem.weaponName] = ctName
		
		-- should now update theItem to new target info 
		isThreat = false 
		if guardianAngel.getWatchedUnitByName(ctName) then 
			isThreat = true
			if guardianAngel.verbose then 
				trigger.action.outText("+++gA: <" .. theItem.weaponName .. "> now targeting protected <" .. ctName .. ">!", 30)
			end
			
			if isThreat and guardianAngel.announcer and guardianAngel.active then 
				local desc = "Missile, missile, missile - now heading for " .. ctName .. "!"
				if guardianAngel.private then 
					trigger.action.outTextForGroup(ID, desc, guardianAngel.msgTime) 
					if guardianAngel.launchSound then 
						local fileName = "l10n/DEFAULT/" .. guardianAngel.launchSound
						trigger.action.outSoundForGroup(ID, fileName)
					end
				else 
					trigger.action.outText(desc, guardianAngel.msgTime)
					if guardianAngel.launchSound then 
						local fileName = "l10n/DEFAULT/" .. guardianAngel.launchSound
						trigger.action.outSound(fileName)
					end
				end
			end
		end
		
		guardianAngel.retargetItem(theItem, currentTarget, isThreat)
		t = currentTarget
	else
		-- not ctName, or name as before. 
		-- go on.
	end
	
	-- we only progress here is the missile is a threat.
	-- if not, we keep it and check next time if it has 
	-- retargeted a protegee 
	if not theItem.threat then return true end 
	
	-- local oldWPos = theItem.wP
	local A = w:getPoint() -- A is new point of weapon
	-- theItem.wp = A -- update new position, old is in oldWPos
	
	-- new code: safety check with ALL protected wings
	-- local bubbleThreat = guardianAngel.bubbleCheck(A, w)
	-- safety check removed, no benefit after new code 
	
	local B 
	if currentTarget then B = currentTarget:getPoint() else B = A end 
	
	local d = math.floor(dcsCommon.dist(A, B))
	theItem.lastDistance = d -- save it for post mortem 
	local desc = theItem.weaponName .. ": "
	if true or t == currentTarget then 
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
		theItem.lastDesc = desc 
		theItem.timeStamp = timer.getTime()
		
		if guardianAngel.intervention and 
		   d <= lethalRange + 10 
		then 
			desc = desc .. " ANGEL INTERVENTION"
			
			if guardianAngel.announcer then 
				if guardianAngel.private then 
					trigger.action.outTextForGroup(ID, desc, guardianAngel.msgTime) 
					if guardianAngel.interventionSound then 
						local fileName = "l10n/DEFAULT/" .. guardianAngel.interventionSound
						trigger.action.outSoundForGroup(ID, fileName)
					end
				else 
					trigger.action.outText(desc, guardianAngel.msgTime) 
					if guardianAngel.interventionSound then 
						local fileName = "l10n/DEFAULT/" .. guardianAngel.interventionSound
						trigger.action.outSound(fileName)
					end
				end
			end
			guardianAngel.invokeCallbacks("intervention", theItem.targetName, theItem.weaponName)
			w:destroy()
			
			-- now add some showy explosion so the missile
			-- doesn't just disappear 
			if guardianAngel.explosion > 0 then 
				local xP = guardianAngel.calcSafeExplosionPoint(A,B, guardianAngel.fxDistance)
				trigger.action.explosion(xP, guardianAngel.explosion)
			end
			
			return false -- remove from list 
		end
		
		if guardianAngel.intervention and 
		   d <= guardianAngel.minMissileDist -- god's override 
		then 
			desc = desc .. " GOD INTERVENTION"
			--if theItem.lostTrack then desc = desc .. " (little sneak!)" end 
			--if theItem.missed then desc = desc .. " (missed you!)" end 
			
			if guardianAngel.announcer then 
				if guardianAngel.private then 
					trigger.action.outTextForGroup(ID, desc, guardianAngel.msgTime) 
				else 
					trigger.action.outText(desc, guardianAngel.msgTime) 
				end
			end
			guardianAngel.invokeCallbacks("intervention", theItem.targetName, theItem.weaponName)
			w:destroy()
			if guardianAngel.explosion > 0 then 
				local xP = guardianAngel.calcSafeExplosionPoint(A,B, guardianAngel.fxDistance)
				trigger.action.explosion(xP, guardianAngel.explosion) 
			end
			return false -- remove from list 
		end
	else 

	end
	
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
		local stillAlive = guardianAngel.monitorItem(anItem)
		if stillAlive then 
			table.insert(newArray, anItem) 
		end 
	end
	guardianAngel.missilesInTheAir = newArray
end

function guardianAngel.filterItem(theItem)
	local w = theItem.theWeapon
	if not w then return false end
	if not w:isExist() then 
		return false 
	end 
	return true -- missile still alive 
end

function guardianAngel.filterMissiles()
	local newArray = {} -- we collect all still existing missiles here 
	                    -- and replace missilesInTheAir with that for next round
	for idx, anItem in pairs (guardianAngel.missilesInTheAir) do 
		-- we now have an item 
		-- see about detection 
		-- guardianAngel.detectItem(anItem)
		
		-- see if the weapon is still in existence
		local stillAlive = guardianAngel.filterItem(anItem)
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

function guardianAngel.getAngelicZoneForUnit(theUnit)
	for idx, theZone in pairs(guardianAngel.angelicZones) do 
		if cfxZones.unitInZone(theUnit, theZone) then 
			return theZone
		end
	end
	return nil
end

-- event callback from dcsCommon event handler. preProcessor has returned true 
function guardianAngel.somethingHappened(event)
	-- when this is invoked, the preprocessor guarantees that
	-- it's an interesting event and has initiator 
	local ID = event.id
	local theUnit = event.initiator
	-- make sure that this is a cat 0 or cat 1 
	
	local playerName = nil 
	if theUnit.getPlayerName then 
		playerName = theUnit:getPlayerName() -- nil if not a player
	end 
	
	local mustProtect = false 
	if ID == 15 and playerName then 
		-- this is a player created unit 
		if guardianAngel.verbose then 
			trigger.action.outText("+++gA: player unit born " .. theUnit:getName(), 30)
		end 
		if guardianAngel.autoAddPlayers then 
			 mustProtect = true
		end
		
		theZone = guardianAngel.getAngelicZoneForUnit(theUnit)
		if theZone then 
			mustProtect = theZone.angelic 
			if theZone.verbose or guardianAngel.verbose then 
				trigger.action.outText("+++gA: angelic zone " .. theZone.name .." -- protect: (" .. dcsCommon.bool2YesNo(mustProtect) .. ")", 30)
			end 
		end
		
		if mustProtect then 
			guardianAngel.addUnitToWatch(theUnit)
		end
		
		return 
	elseif ID == 15 then 
		-- AI spawn. check if it is an aircraft and in an angelic zone 
		-- docs say that initiator is object. so let's see if when we 
		-- get cat, this returns 1 for unit (as it should, so we can get 
		-- group, or if it's really a unit, which returns 0 for aircraft 
		local cat = theUnit:getCategory()
		--trigger.action.outText("birth event for " .. theUnit:getName() .. " with cat = " .. cat, 30)
		if cat ~= 1 then 
			-- not a unit, bye bye 
			return 
		end
		local theGroup = theUnit:getGroup()
		local gCat = theGroup:getCategory()
		if gCat == 0 or gCat == 1 then 
			--trigger.action.outText("is aircraft cat " .. gCat, 30)
			
			theZone = guardianAngel.getAngelicZoneForUnit(theUnit)
			if theZone then 
				mustProtect = theZone.angelic 
				if theZone.verbose or guardianAngel.verbose then 
					trigger.action.outText("+++gA: angelic zone <" .. theZone.name .."> contains unit <" .. theUnit:getName() .. ">, protect it: " .. dcsCommon.bool2YesNo(mustProtect) .. ".", 30)
				end 
			end
			
			if mustProtect then 
				guardianAngel.addUnitToWatch(theUnit)
			end
		end
		return 
	end
	
	if ID == 20 and playerName then 
		-- this is a player entered unit 
		if guardianAngel.verbose then 
			trigger.action.outText("+++gA: player seated in unit " .. theUnit:getName(), 30)
		end 
		
		if guardianAngel.autoAddPlayers then 
			 mustProtect = true
		end
		
		theZone = guardianAngel.getAngelicZoneForUnit(theUnit)
		if theZone then 
			mustProtect = theZone.angelic 
			if theZone.verbose or guardianAngel.verbose then 
				trigger.action.outText("+++gA: angelic zone " .. theZone.name .." -- protect: (" .. dcsCommon.bool2YesNo(mustProtect) .. ")", 30)
			end 
		end
		
		if mustProtect then 
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
		-- even if not active, we collect missile data 
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
		local launcher = theUnit 
		guardianAngel.missilesAndTargets[theWeapon:getName()] = targetName
		if not watchedUnit then 
			-- we may still want to watch this if the missile 
			-- can be re-targeted
			if guardianAngel.verbose then 
				trigger.action.outText("+++gA: missile <" .. theWeapon:getName() .. "> targeting <" .. targetName .. ">, not a threat", 30)
			end
			-- add it as no threat 
			local theQItem = guardianAngel.createQItem(theWeapon, theTarget, false, launcher) -- this is not a threat, simply watch for re-target
			table.insert(guardianAngel.missilesInTheAir, theQItem)
			return 
		end -- fired at some other poor sucker, we don't care
		
		-- if we get here, someone fired a guided weapon at my watched units
		-- create a new item for my queue
		local theQItem = guardianAngel.createQItem(theWeapon, theTarget, true, launcher) -- this is watched
		table.insert(guardianAngel.missilesInTheAir, theQItem)
		guardianAngel.invokeCallbacks("launch", theQItem.targetName, theQItem.weaponName)
		
		local unitHeading = dcsCommon.getUnitHeadingDegrees(theTarget)
		local A = theWeapon:getPoint()
		local B = theTarget:getPoint()
		local oclock = dcsCommon.clockPositionOfARelativeToB(A, B, unitHeading)

		local grpID = theTarget:getGroup():getID()
		local vbInfo = ""
		if guardianAngel.verbose then 
			vbInfo = ", <" .. theWeapon:getName() .. "> targeting <" .. targetName .. ">"
		end
		if guardianAngel.launchWarning and guardianAngel.active then 
			-- currently, we always detect immediately 
			-- can be moved to update()
			if guardianAngel.private then 
				trigger.action.outTextForGroup(grpID, "Missile, missile, missile, " .. oclock .. " o clock" .. vbInfo, guardianAngel.msgTime)
				if guardianAngel.launchSound then 
					local fileName = "l10n/DEFAULT/" .. guardianAngel.launchSound
					trigger.action.outSoundForGroup(grpID, fileName)
				end
			else 
				trigger.action.outText("Missile, missile, missile, " .. oclock .. " o clock" .. vbInfo, guardianAngel.msgTime)
				if guardianAngel.launchSound then 
					local fileName = "l10n/DEFAULT/" .. guardianAngel.launchSound
					trigger.action.outSound(fileName)
				end
			end
			
			theQItem.detected = true -- remember: we detected and warned already
		end 
		return
	end
	
	if ID == 2 then 
		if not guardianAngel.active then return end -- we aren't on watch.
		if not guardianAngel.intervention then return end -- we don't intervene 
		if not event.weapon then return end -- no weapon, no interest 
		local theWeapon = event.weapon
		local wName = theWeapon:getName()
		local theTarget = event.target 	
		if not theTarget then return end -- should not happen, better safe then dead
		local tName = theTarget:getName()
		
		local theProtegee = nil
		for idx, aProt in pairs(guardianAngel.unitsToWatchOver) do 
			if aProt:isExist() then 
				if tName == aProt:getName() then 
					theProtegee = aProt 
				end
			else 
				if guardianAngel.verbose then 
					trigger.action.outText("+++gA: whoops. Looks like I lost a wing there... sorry", 30)
				end
			end 
		end
		if not theProtegee then return end 
		
		-- one of our protegees was hit 
		--trigger.action.outText("+++gA: Protegee " .. tName .. " was hit", 30)		
		trigger.action.outText("+++gA: I:" .. theUnit:getName() .. " hit " .. tName .. " with " .. wName, 30) -- note: theUnit is the LAUNCHER or the weapon!!!
		if guardianAngel.missilesAndTargets[wName] and guardianAngel.verbose then 
			trigger.action.outText("+++gA: <" .. wName .. "> was originally aimed at <" .. guardianAngel.missilesAndTargets[wName] .. ">", 30)
			local qName = guardianAngel.missilesAndTargets[wName]
			if qName ~= tName then 
				trigger.action.outText("+++gA: RETARGET DETECTED", 30)
				local wpnTgt = theWeapon:getTarget()
				local wpnTgtName = "(none???)"
				if wpnTgt then wpnTgtName = wpnTgt:getName() end 
				trigger.action.outText("+++gA: *current* weapon's target is <" .. wpnTgtName .. ">", 30)
				if wpnTgtName ~= tName then 
					trigger.action.outText("+++gA: COLLATERAL DAMAGE!", 30)
				end
			end
		else 
			trigger.action.outText("***gA: no missile in the air for <" .. wName .. ">!!!!", 30)
		end
		-- let's see if the victim was in our list of protected 
		-- units 
		local thePerp = nil 
		for idx, anItem in pairs(guardianAngel.missilesInTheAir) do 
			if anItem.weaponName == wName then 
				thePerp = anItem
			end
		end

		if not thePerp then return end 
		--trigger.action.outText("+++gA: offender was known to gA: " .. wName, 30)
		
		-- stats only: do target and intended target match?
		local theWTarget = theWeapon:getTarget()
		if not theWTarget then return end -- no target no interest
		local wtName = theWTarget:getName()
		if wtName == tName then 
			trigger.action.outText("+++gA: perp's ill intent confirmed", 30)
		else 
			trigger.action.outText("+++gA: UNINTENDED CONSEQUENCES", 30)
		end

		-- if we should have protected: mea maxima culpa 
		trigger.action.outText("[+++gA: Angel hangs her head in shame. Mea Culpa, " .. tName.."]", 30)
		-- see if we can find the q item 
		local missedItem = guardianAngel.getQItemForWeaponNamed(wName)
		if not missedItem then 
			trigger.action.outText("Cannot retrieve item for <" .. wName .. ">", 30)
		else 
			local now = timer.getTime()
			local delta = now - missedItem.timeStamp
			local wasThreat = dcsCommon.bool2YesNo(missedItem.threat)
			
			trigger.action.outText("post: target was <" .. missedItem.targetName .. "> with last dist <" .. missedItem.lastDistance .. "> for weapon <" .. missedItem.weaponName .. ">, with dast desc = <" .. missedItem.lastDesc .. ">, <" .. delta .. "> s ago, Threat:(" .. wasThreat .. ")", 30)
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
	-- and break off if nothing to do 
	if not guardianAngel.active then 
		guardianAngel.filterMissiles()
		return 
	end 
	
	guardianAngel.monitorMissiles()
end

function guardianAngel.doActivate()
	guardianAngel.active = true 
	if guardianAngel.verbose or guardianAngel.announcer then 
		trigger.action.outText("Guardian Angel has activated", 30)
	end 
end

function guardianAngel.doDeActivate()
	guardianAngel.active = false 
	if guardianAngel.verbose or guardianAngel.announcer then 
		trigger.action.outText("Guardian Angel NO LONGER ACTIVE", 30)
	end
end

function guardianAngel.flagUpdate()
	timer.scheduleFunction(guardianAngel.flagUpdate, {}, timer.getTime() + 1) -- once every second 
	
	-- check the flags for on/off
	if guardianAngel.activate then 
		if cfxZones.testZoneFlag(guardianAngel, 				guardianAngel.activate, "change","lastActivate") then
			guardianAngel.doActivate()
		end
	end
	
	if guardianAngel.deactivate then 
		if cfxZones.testZoneFlag(guardianAngel, 				guardianAngel.deactivate, "change","lastDeActivate") then
			guardianAngel.doDeActivate()
		end
	end
end

function guardianAngel.collectPlayerUnits()
	-- make sure we have all existing player units 
	-- at start of game 
	
	for i=1, 2 do 
		-- currently only two factions in dcs 
		local factionUnits = coalition.getPlayers(i)
		for idx, theUnit in pairs(factionUnits) do 
			local mustProtect = false 
			if guardianAngel.autoAddPlayers then 
				mustProtect = true
			end
		
			theZone = guardianAngel.getAngelicZoneForUnit(theUnit)
			if theZone then 
				mustProtect = theZone.angelic 
				if theZone.verbose or guardianAngel.verbose then 
					trigger.action.outText("+++gA: angelic zone " .. theZone.name .." contains player unit <" .. theUnit:getName() .. "> -- protect: (" .. dcsCommon.bool2YesNo(mustProtect) .. ")", 30)
				end 
			end
		
			if mustProtect then 
				guardianAngel.addUnitToWatch(theUnit)
			end
		
		end
	end
end

function guardianAngel.collectAIUnits()
	-- make sure we have all existing AI units 
	-- at start of game 
	for i=1, 2 do 
		-- currently only two factions in dcs 
		local factionGroups = coalition.getGroups(i)
		for idg, aGroup in pairs(factionGroups) do 
			local factionUnits = aGroup:getUnits()
			for idx, theUnit in pairs(factionUnits) do 
				local mustProtect = false 
		
				local gCat = aGroup:getCategory()
				if gCat == 0 or gCat == 1 then 			
					theZone = guardianAngel.getAngelicZoneForUnit(theUnit)
					if theZone then 
						mustProtect = theZone.angelic 
						if theZone.verbose or guardianAngel.verbose then 
							trigger.action.outText("+++gA: angelic zone <" .. theZone.name .."> contains AI unit <" .. theUnit:getName() .. ">, protect it: " .. dcsCommon.bool2YesNo(mustProtect) .. ".", 30)
						end 
					end
			
					if mustProtect then 
						guardianAngel.addUnitToWatch(theUnit)
					end
				end
			end
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
		theZone = cfxZones.createSimpleZone("guardianAngelConfig")
	end 
	
	
	guardianAngel.verbose = theZone:getBoolFromZoneProperty("verbose", false)
	
	guardianAngel.autoAddPlayer = theZone:getBoolFromZoneProperty("autoAddPlayer", true)
	guardianAngel.launchWarning = theZone:getBoolFromZoneProperty("launchWarning", true)
	guardianAngel.intervention = theZone:getBoolFromZoneProperty("intervention", true)
	guardianAngel.announcer = theZone:getBoolFromZoneProperty( "announcer", true)
	guardianAngel.private = theZone:getBoolFromZoneProperty("private", false)
	guardianAngel.explosion = theZone:getNumberFromZoneProperty("explosion", -1)
	guardianAngel.fxDistance = theZone:getNumberFromZoneProperty( "fxDistance", 500) 
	
	guardianAngel.active = theZone:getBoolFromZoneProperty("active", true)
	
	guardianAngel.msgTime = theZone:getNumberFromZoneProperty("msgTime", 30)
	
	if theZone:hasProperty("activate?") then 
		guardianAngel.activate = theZone:getStringFromZoneProperty("activate?", "*<none>")
		guardianAngel.lastActivate = theZone:getFlagValue(guardianAngel.activate)
	elseif theZone:hasProperty("on?") then 
		guardianAngel.activate = theZone:getStringFromZoneProperty("on?", "*<none>") 
		guardianAngel.lastActivate = theZone:getFlagValue(guardianAngel.activate)
	end
	
	if theZone:hasProperty("deactivate?") then 
		guardianAngel.deactivate = theZone:getStringFromZoneProperty("deactivate?", "*<none>")
		guardianAngel.lastDeActivate = theZone:getFlagValue(guardianAngel.deactivate)
	elseif theZone:hasProperty("off?") then 
		guardianAngel.deactivate = theZone:getStringFromZoneProperty("off?", "*<none>") 
		guardianAngel.lastDeActivate = theZone:getFlagValue(guardianAngel.deactivate)
	end
	
	if theZone:hasProperty("launchSound") then 
		guardianAngel.launchSound = theZone:getStringFromZoneProperty("launchSound", "nosound")
	end
	
	if theZone:hasProperty("interventionSound") then 
		guardianAngel.interventionSound = theZone:getStringFromZoneProperty("interventionSound", "nosound")
	end
	
	guardianAngel.configZone = theZone 
	if guardianAngel.verbose then 
		trigger.action.outText("+++gA: processed config zone", 30)
	end 
end

-- 
-- guardian zones 
--

function guardianAngel.processGuardianZone(theZone)
	theZone.angelic = theZone:getBoolFromZoneProperty("guardian", true)
	
	
	if theZone.verbose or guardianAngel.verbose then 
		trigger.action.outText("+++gA: processed 'guardian' zone <" .. theZone.name .. ">", 30)
	end
	-- add it to my angelicZones
	table.insert(guardianAngel.angelicZones, theZone)
end

function guardianAngel.readGuardianZones()
	local attrZones = cfxZones.getZonesWithAttributeNamed("guardian")
	for k, aZone in pairs(attrZones) do 
		guardianAngel.processGuardianZone(aZone)
	end
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
	
	-- read guarded zones 
	guardianAngel.readGuardianZones() 
	
	-- install event monitor 
	dcsCommon.addEventHandler(guardianAngel.somethingHappened,
							  guardianAngel.preProcessor,
							  guardianAngel.postProcessor)
	
	-- collect all units that are already in the game at this point
	guardianAngel.collectPlayerUnits()
	guardianAngel.collectAIUnits()
	
	-- start update 
	guardianAngel.update()
	
	-- start flag check 
	guardianAngel.flagUpdate()
	
	trigger.action.outText("Guardian Angel v" .. guardianAngel.version .. " running", 30)
	return true 
end

function guardianAngel.testCB(reason, targetName, weaponName)
	trigger.action.outText("gA - CB for ".. reason .. ": " .. targetName .. " w: " .. weaponName, guardianAngel.msgTime)
end

-- go go go 
if not guardianAngel.start() then 
	trigger.action.outText("Loading Guardian Angel failed.", 30)
	guardianAngel = nil 
end

-- test callback
--guardianAngel.addCallback(guardianAngel.testCB)
--guardianAngel.invokeCallbacks("A", "B", "C")

