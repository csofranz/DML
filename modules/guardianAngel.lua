guardianAngel = {}
guardianAngel.version = "4.0.0"
guardianAngel.ups = 10 -- hard-coded!! missile track
guardianAngel.name = "Guardian Angel" -- just in case someone accesses .name  
guardianAngel.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
-- Guardian Angel DML script (c) 2021-2025 by Charistian Franz
--[[--
  Version History 
	 4.0.0 - code cleanup 
	       - DCS bug hardening 
		   - guardianAngel.autoAddPlayer implemented 
		   - removed preProcessor
		   - removed postproc 
		   - removed isInterestingEvent
		   - wired directly to onEvent
		   - removed event id 20 (player enter)
		   - mild performance tuning 
		   - new sanctuary zones 
		   - sancturay zones have floor and ceiling 
		   - once per second sanctuary calc 
		   - expanded getWatchedUnitByName to include inSanctuary 
		   - sanctuary zones use coalition 
--]]--

guardianAngel.active = true -- can be turned on / off 
guardianAngel.angelicZones = {} -- angels be active here
guardianAngel.sanctums = {} -- and here, but only as temps 
guardianAngel.minMissileDist = 50 -- m. below this distance the missile removed 
guardianAngel.safetyFactor = 1.8 -- for calculating dealloc range 
guardianAngel.unitsToWatchOver = {} -- I'll watch over these units
guardianAngel.inSanctuary = {} -- temporarily protected 
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
-- units to watch (permanent protection list)
--
function guardianAngel.addUnitToWatch(aUnit)
	if not aUnit then return end 
	local unitName = aUnit:getName()
	local isNew = guardianAngel.unitsToWatchOver[unitName] == nil 
	guardianAngel.unitsToWatchOver[unitName] = aUnit
	if guardianAngel.verbose then 
		if isNew then trigger.action.outText("+++gA: now guarding unit " .. unitName, 30)
		else trigger.action.outText("+++gA: updating unit " .. unitName, 30) 
		end
	end
end

function guardianAngel.removeUnitToWatch(aUnit)
	if not aUnit then return end 
	local unitName = aUnit:getName()
	if not unitName then return end 
	guardianAngel.unitsToWatchOver[unitName] = nil
	if guardianAngel.verbose then trigger.action.outText("+++gA: no longer watching " .. aUnit:getName(), 30) end 
end

function guardianAngel.getWatchedUnitByName(aName)
	if not aName then return nil end 
	local u = guardianAngel.unitsToWatchOver[aName]
	if u then return u end -- always protected 
	return guardianAngel.inSanctuary[aName] -- returns unit or nil 
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
	elseif theWeapon.getTypeName then wName = theWeapon:getTypeName()
	else wName = "<Generic>" end 
	wName = wName .. "-" .. oName
	local launcherName = launcher:getTypeName() .. " " .. launcher:getName()
	
	theItem.theWeapon = theWeapon -- weapon that we are tracking 
	theItem.weaponName = wName -- theWeapon:getName()
	-- usually weapons have no 'name' except an ID, so let's get
	-- type/display name. Weapons often have no display name.
	if guardianAngel.verbose then trigger.action.outText("gA: tracking missile <" .. wName .. "> launched by <" .. launcherName .. ">", guardianAngel.msgTime) end 
	theItem.theTarget = theTarget
	if theTarget.getGroup then -- some targets may not have a group
		theItem.tGroup = theTarget:getGroup()
		theItem.tID = theItem.tGroup:getID()
	else 
		theItem.tGroup = nil 
		theItem.tID = nil 
	end 
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
		end
	else
		theItem.tGroup = theTarget:getGroup()
		theItem.tID = theItem.tGroup:getID()
	end 
	theItem.targetName = theTarget:getName()
	theItem.lastDistance = math.huge 
	theItem.missed = false
	theItem.lastDesc = "(retarget)"
end

function guardianAngel.getQItemForWeaponNamed(theName)
	for idx, theItem in pairs (guardianAngel.missilesInTheAir) do 
		if theItem.weaponName == theName then return theItem end 
	end
	return nil 
end

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
		if guardianAngel.verbose then
			trigger.action.outText("+++gA: missile disappeared: <" .. theItem.weaponName .. ">, aimed at <" .. theItem.targetName .. ">",30)
		end
		guardianAngel.invokeCallbacks("disappear", theItem.targetName, theItem.weaponName)
		return false 
	end 
	
	local t = theItem.theTarget
	local currentTarget = w:getTarget()
	-- Re-target check. did missile pick a new target?
	local ctName = "***guardianAngel.not.set" 
	if currentTarget and Object.isExist(currentTarget) then ctName = currentTarget:getName() end 
	if ctName ~= theItem.targetName then 
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
				if guardianAngel.private and ID then 
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
	end
	
	-- we only progress here is the missile is a threat.
	-- if not, we keep it and check next time if it has 
	-- retargeted a protegee 
	if not theItem.threat then return true end 	
	local A = w:getPoint() -- A is new point of weapon	
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
		-- calculate lethal distance: vcc is in meters per second
		-- we sample ups times per second
		-- making the missile move vcc / ups meters per 
		-- timer interval. If it now is closer than that, we destroy msl
		local lethalRange = math.abs(vcc / guardianAngel.ups) * guardianAngel.safetyFactor
		desc = desc .. ", LR= " .. math.floor(lethalRange) .. "m"
		theItem.lastDesc = desc 
		theItem.timeStamp = timer.getTime()		
		if guardianAngel.intervention and 
		   d <= lethalRange + 10 
		then 
			desc = desc .. " ANGEL INTERVENTION"
			if guardianAngel.announcer and ID then 
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
			-- now add some showy explosion so the missile doesn't just disappear 
			if guardianAngel.explosion > 0 then 
				local xP = guardianAngel.calcSafeExplosionPoint(A,B, guardianAngel.fxDistance)
				trigger.action.explosion(xP, guardianAngel.explosion)
			end
			return false -- remove from list 
		end
		
		if guardianAngel.intervention and d <= guardianAngel.minMissileDist then -- god's override 
			desc = desc .. " GOD INTERVENTION"			
			if guardianAngel.announcer and ID then 
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
	end
	return true -- keep in list 
end

function guardianAngel.monitorMissiles()
	local newArray = {} -- monitor existing msl
	for idx, anItem in pairs (guardianAngel.missilesInTheAir) do 
		-- see if the weapon is still in existence
		local stillAlive = guardianAngel.monitorItem(anItem)
		if stillAlive then table.insert(newArray, anItem) end 
	end
	guardianAngel.missilesInTheAir = newArray
end

function guardianAngel.filterItem(theItem)
	local w = theItem.theWeapon
	if not w then return false end
	if not w:isExist() then return false end 
	return true -- missile still alive 
end

function guardianAngel.filterMissiles()
	local newArray = {} -- filter msl 
	for idx, anItem in pairs (guardianAngel.missilesInTheAir) do 
		-- see if the weapon is still in existence
		local stillAlive = guardianAngel.filterItem(anItem)
		if stillAlive then table.insert(newArray, anItem) end 
	end
	guardianAngel.missilesInTheAir = newArray
end
--
-- E V E N T   P R O C E S S I N G
-- 
function guardianAngel.getAngelicZoneForUnit(theUnit)
	for idx, theZone in pairs(guardianAngel.angelicZones) do 
		if cfxZones.unitInZone(theUnit, theZone) then return theZone end
	end
	return nil
end

function guardianAngel:onEvent(event)
	if not event.initiator then return end 
	local ID = event.id
	local theUnit = event.initiator	
	local playerName = nil 
	if theUnit.getPlayerName then playerName = theUnit:getPlayerName() end 
	local mustProtect = false 

	if ID == 15 then 
		-- AI/player spawn. check if it is an aircraft and in an angelic zone 
		-- docs say that initiator is object. so let's see if when we 
		-- get cat, this returns 1 for unit (as it should, so we can get 
		-- group, or if it's really a unit, which returns 0 for aircraft 
		if not theUnit.getCategory then return end 
		local theGroup = theUnit:getGroup()
		if not theGroup then return end 
		local gCat = theGroup:getCategory()
		if gCat ~= 0 and gCat ~= 1 then return end 	-- only fixed and rotor wing 	
		theZone = guardianAngel.getAngelicZoneForUnit(theUnit)
		if theZone then 
			mustProtect = theZone.angelic 
			if theZone.verbose or guardianAngel.verbose then 
				trigger.action.outText("+++gA: angelic zone <" .. theZone.name .."> contains unit <" .. theUnit:getName() .. ">, protect it: " .. dcsCommon.bool2YesNo(mustProtect) .. ".", 30)
			end 
		end
		if playerName and guardianAngel.autoAddPlayer then mustProtect = true end 
		if mustProtect then guardianAngel.addUnitToWatch(theUnit) end
		return 
	end

	if ID == 21 and playerName then -- player leave unit 
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
		else return end 
		if not theTarget then return end 
		if not theTarget:isExist() then return end 
		
		-- if we get here, we have weapon aimed at a target 
		local targetName = theTarget:getName()
		local watchedUnit = guardianAngel.getWatchedUnitByName(targetName)
		local launcher = theUnit 
		guardianAngel.missilesAndTargets[theWeapon:getName()] = targetName
		if not watchedUnit then 
			-- can be re-targeted
			if guardianAngel.verbose then trigger.action.outText("+++gA: missile <" .. theWeapon:getName() .. "> targeting <" .. targetName .. ">, not a threat", 30) end
			-- add it as no threat 
			local theQItem = guardianAngel.createQItem(theWeapon, theTarget, false, launcher) -- this is not a threat, simply watch for re-target
			table.insert(guardianAngel.missilesInTheAir, theQItem)
			return -- fired at some other poor sucker, we don't care
		end 
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
		if guardianAngel.verbose then vbInfo = ", <" .. theWeapon:getName() .. "> targeting <" .. targetName .. ">" end
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
	
	if ID == 2 then -- hit 
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
				if tName == aProt:getName() then theProtegee = aProt end
			else 
				if guardianAngel.verbose then trigger.action.outText("+++gA: Whoops. Looks like I lost a wing there... sorry", 30) end
			end 
		end
		if not theProtegee then return end 
		
		-- one of our protegees was hit 	
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
				if wpnTgtName ~= tName then trigger.action.outText("+++gA: COLLATERAL DAMAGE!", 30) end
			end
		else 
			trigger.action.outText("***gA: no missile in the air for <" .. wName .. ">!!!!", 30)
		end
		-- let's see if the victim was in our list of protected units 
		local thePerp = nil 
		for idx, anItem in pairs(guardianAngel.missilesInTheAir) do 
			if anItem.weaponName == wName then thePerp = anItem end
		end

		if not thePerp then return end 
		
		-- stats only: do target and intended target match?
		local theWTarget = theWeapon:getTarget()
		if not theWTarget then return end -- no target no interest
		local wtName = theWTarget:getName()
		if wtName == tName then trigger.action.outText("+++gA: perp's ill intent confirmed", 30)
		else trigger.action.outText("+++gA: UNINTENDED CONSEQUENCES", 30)
		end

		-- if we should have protected: mea maxima culpa 
		trigger.action.outText("[+++gA: Angel hangs her head in shame. Mea Culpa, " .. tName.."]", 30)
		-- see if we can find the q item 
		local missedItem = guardianAngel.getQItemForWeaponNamed(wName)
		if not missedItem then trigger.action.outText("Cannot retrieve item for <" .. wName .. ">", 30)
		else 
			local now = timer.getTime()
			local delta = now - missedItem.timeStamp
			local wasThreat = dcsCommon.bool2YesNo(missedItem.threat)
			trigger.action.outText("postmortem: target was <" .. missedItem.targetName .. "> with last dist <" .. missedItem.lastDistance .. "> for weapon <" .. missedItem.weaponName .. ">, with dast desc = <" .. missedItem.lastDesc .. ">, <" .. delta .. "> s ago, Threat:(" .. wasThreat .. ")", 30)
		end
		return 
	end
	
	if guardianAngel.verbose then 
		local myType = theUnit:getTypeName()
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
	if guardianAngel.verbose or guardianAngel.announcer then trigger.action.outText("Guardian Angel has activated", 30)	end 
end

function guardianAngel.doDeActivate()
	guardianAngel.active = false 
	if guardianAngel.verbose or guardianAngel.announcer then trigger.action.outText("Guardian Angel NO LONGER ACTIVE", 30) end
end

function guardianAngel.flagUpdate()
	timer.scheduleFunction(guardianAngel.flagUpdate, {}, timer.getTime() + 1) -- once every second 
	
	if guardianAngel.activate then 
		if cfxZones.testZoneFlag(guardianAngel, guardianAngel.activate, "change","lastActivate") then
			guardianAngel.doActivate()
		end
	end
	
	if guardianAngel.deactivate then 
		if cfxZones.testZoneFlag(guardianAngel, guardianAngel.deactivate, "change","lastDeActivate") then
			guardianAngel.doDeActivate()
		end
	end
	
	if #guardianAngel.sanctums > 0 then 
		-- scan all planes against sanctums 
		local filtered = {}
		for idx, theZone in pairs(guardianAngel.sanctums) do 
			local f = theZone.floor 
			local c = theZone.ceiling 
			for coa=1, 2 do 
				for cat=0, 1 do 
					if theZone.coalition == 0 or theZone.coalition == coa then 
						local allGroups = coalition.getGroups(coa, cat)
						for igp, aGroup in pairs(allGroups) do 
							local allUnits = aGroup:getUnits()
							for iun, theUnit in pairs(allUnits) do 
								local p = theUnit:getPoint()
								if f <= p.y and c >= p.y then 
									if theZone:isPointInsideZone(p) then 
										local name = theUnit:getName()
										filtered[name] = theUnit
										if theZone.verbose or guardianAngel.verbose then 
											if filtered[name] ~= guardianAngel.inSanctuary[name] then
												if filtered[name] then 
													trigger.action.outText("+++gA: <" .. name .. "> now in sanctuary <" .. theZone.name .. ">", 30)
												else 
													trigger.action.outText("+++gA: <" .. name .. "> left sanctum <" .. theZone.name .. ">", 30)
													if guardianAngel.unitsToWatchOver[name] then
														trigger.action.outText("(still protected, though)", 30)
													end
												end
											end 
										end
									end
								end 
							end 
						end 
					end -- zone coa match 
				end -- cat loop
			end -- coa loop 
		end 
		guardianAngel.inSanctuary = filtered 
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
			if guardianAngel.autoAddPlayer then mustProtect = true end
		
			theZone = guardianAngel.getAngelicZoneForUnit(theUnit)
			if theZone then 
				mustProtect = theZone.angelic 
				if theZone.verbose or guardianAngel.verbose then 
					trigger.action.outText("+++gA: angelic zone " .. theZone.name .." contains player unit <" .. theUnit:getName() .. "> -- protect: (" .. dcsCommon.bool2YesNo(mustProtect) .. ")", 30)
				end 
			end
			if mustProtect then guardianAngel.addUnitToWatch(theUnit) end
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
					if mustProtect then guardianAngel.addUnitToWatch(theUnit) end
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
	guardianAngel.verbose = theZone.verbose
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
	
	if theZone:hasProperty("launchSound") then guardianAngel.launchSound = theZone:getStringFromZoneProperty("launchSound", "nosound") end
	
	if theZone:hasProperty("interventionSound") then 	guardianAngel.interventionSound = theZone:getStringFromZoneProperty("interventionSound", "nosound") end
	
	guardianAngel.configZone = theZone 
end
-- 
-- guardian/sanctuary zones 
--
function guardianAngel.processGuardianZone(theZone)
	theZone.angelic = true -- theZone:getBoolFromZoneProperty("guardian", true)
	if theZone.verbose or guardianAngel.verbose then 
		trigger.action.outText("+++gA: processed 'guardian' zone <" .. theZone.name .. ">", 30)
	end
	-- add it to my angelicZones
	table.insert(guardianAngel.angelicZones, theZone)
end

function guardianAngel.readGuardianZones()
	local attrZones = cfxZones.getZonesWithAttributeNamed("guardian")
	for k, aZone in pairs(attrZones) do guardianAngel.processGuardianZone(aZone) end
end

function guardianAngel.processSanctuaryZone(theZone)
	theZone.floor = theZone:getNumberFromZoneProperty("floor", -1000)
	theZone.ceiling = theZone:getNumberFromZoneProperty("ceiling", 100000)
	theZone.coalition = theZone:getCoalitionFromZoneProperty("sanctuary", 0)
	if theZone.verbose or guardianAngel.verbose then 
		trigger.action.outText("+++gA: processed 'sanctuary' zone <" .. theZone.name .. ">", 30)
	end
	-- add it to my sanctuaries
	table.insert(guardianAngel.sanctums, theZone)
end

function guardianAngel.readSantuaryZones()
	local attrZones = cfxZones.getZonesWithAttributeNamed("sanctuary")
	for k, aZone in pairs(attrZones) do guardianAngel.processSanctuaryZone(aZone) end
end
--
-- start 
--
function guardianAngel.start()
	-- lib check 
	if not dcsCommon.libCheck("cfx Guardian Angel", guardianAngel.requiredLibs) then return false end
	-- read config 
	guardianAngel.readConfigZone()
	-- read guarded zones 
	guardianAngel.readGuardianZones() 
	guardianAngel.readSantuaryZones()
	-- insert into evet loop 
	world.addEventHandler(guardianAngel)
	-- collect all units that are already in the game at this point
	guardianAngel.collectPlayerUnits(guardianAngel)
	guardianAngel.collectAIUnits()
	-- start update for missiles 
	guardianAngel.update()
	-- start flag/sanctuary checks 
	guardianAngel.flagUpdate()	
	trigger.action.outText("Guardian Angel v" .. guardianAngel.version .. " running", 30)
	return true 
end

-- go go go 
if not guardianAngel.start() then 
	trigger.action.outText("Loading Guardian Angel failed.", 30)
	guardianAngel = nil 
end

-- test callback
--guardianAngel.addCallback(guardianAngel.testCB)
--guardianAngel.invokeCallbacks("A", "B", "C")
--function guardianAngel.testCB(reason, targetName, weaponName)
--	trigger.action.outText("gA - CB for ".. reason .. ": " .. targetName .. " w: " .. weaponName, guardianAngel.msgTime)
--end

