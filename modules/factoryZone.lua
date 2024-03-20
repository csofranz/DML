factoryZone = {}
factoryZone.version = "3.1.1"
factoryZone.verbose = false 
factoryZone.name = "factoryZone" 

--[[-- VERSION HISTORY

2.0.0 - refactored production part from cfxOwnedZones 1.xpcall
	  - "production" and "defenders" simplification 
	  - now optional specification for red/blue 
	  - use maxRadius from zone for spawning to support quad zones 
3.0.0 - support for liveries via "factoryLiveries" zone 
      - OOP dmlZones
3.1.0 - redD!, blueD!
	  - redP!, blueP! 
	  - method 
	  - productionTime config synonyme
	  - defendMe? attribute 
	  - triggered 'shocked' mode via defendMe 
3.1.1 - fixed a big with persistence 

--]]--
factoryZone.requiredLibs = {
	"dcsCommon",
	"cfxZones",  
	"cfxCommander", -- to make troops do stuff
	"cfxGroundTroops", -- all produced troops rely on this 
	"cfxOwnedZones", 
}

factoryZone.zones = {} -- my factory zones 
factoryZone.liveries = {} -- indexed by type name 
factoryZone.ups = 1
factoryZone.initialized = false 
factoryZone.defendingTime = 100 -- seconds until new defenders are produced
factoryZone.attackingTime = 300 -- seconds until new attackers are produced 
factoryZone.shockTime = 200 -- 'shocked' period of inactivity
factoryZone.repairTime = 200 -- time until we raplace one lost unit, also repairs all other units to 100%  

-- persistence: all attackers we ever sent out.
-- is regularly verified and cut to size via GC
factoryZone.spawnedAttackers = {}

-- factoryZone is a module that manages production of units
-- inside zones and can switch production based on who owns the 
-- zone. Zone ownership can by dynamic (by using OwnedZones or 
-- using scripts to change the 'owner' flag
--
-- *** EXTENTDS ZONES ***
--

function factoryZone.getFactoryZoneByName(zName)
	for zKey, theZone in pairs (factoryZone.zones) do 
		if theZone.name == zName then return theZone end 
	end
	return nil
end

function factoryZone.addFactoryZone(aZone)
	aZone.state = "init"
	aZone.timeStamp = timer.getTime()
	
	-- set up production default 
	local factory = aZone:getStringFromZoneProperty("factory", "none")
	
	local production = aZone:getStringFromZoneProperty("production", factory)
	
	local defenders = aZone:getStringFromZoneProperty("defenders", factory)
		
	if aZone:hasProperty("attackersRED") then 
		-- legacy support
		aZone.attackersRED = aZone:getStringFromZoneProperty( "attackersRED", production)
	else
		aZone.attackersRED = aZone:getStringFromZoneProperty( "productionRED", production)
	end
	
	if aZone:hasProperty("attackersBLUE") then 	
		-- legacy support 
		aZone.attackersBLUE = aZone:getStringFromZoneProperty( "attackersBLUE", production)
	else 
		aZone.attackersBLUE = aZone:getStringFromZoneProperty( "productionBLUE", production)
	end
	
	-- set up defenders default, or use production / factory 
	aZone.defendersRED = aZone:getStringFromZoneProperty("defendersRED", defenders)
	aZone.defendersBLUE = aZone:getStringFromZoneProperty("defendersBLUE", defenders)
	
	aZone.formation = aZone:getStringFromZoneProperty("formation", "circle_out")
	aZone.attackFormation = aZone:getStringFromZoneProperty( "attackFormation", "circle_out") -- cfxZones.getZoneProperty(aZone, "attackFormation")
	aZone.spawnRadius = aZone:getNumberFromZoneProperty("spawnRadius", aZone.maxRadius-5) -- "-5" so they remaininside radius 
	aZone.attackRadius = aZone:getNumberFromZoneProperty("attackRadius", aZone.maxRadius)
	aZone.attackDelta = aZone:getNumberFromZoneProperty("attackDelta", 10) -- aZone.radius)
	aZone.attackPhi = aZone:getNumberFromZoneProperty("attackPhi", 0)
	
	aZone.paused = aZone:getBoolFromZoneProperty("paused", false)
	aZone.factoryOwner = aZone.owner -- copy so we can compare next round
	
	-- pause? and activate?
	if aZone:hasProperty("pause?") then 
		aZone.pauseFlag = aZone:getStringFromZoneProperty("pause?", "none")
		aZone.lastPauseValue = trigger.misc.getUserFlag(aZone.pauseFlag)
	end
	
	if aZone:hasProperty("activate?") then 
		aZone.activateFlag = aZone:getStringFromZoneProperty("activate?", "none")
		aZone.lastActivateValue = trigger.misc.getUserFlag(aZone.activateFlag)
	end
	
	aZone.factoryTriggerMethod = aZone:getStringFromZoneProperty( "triggerMethod", "change")
	if aZone:hasProperty("factoryTriggerMethod") then 
		aZone.factoryTriggerMethod = aZone:getStringFromZoneProperty( "factoryTriggerMethod", "change")
	end
	
	aZone.factoryMethod = aZone:getStringFromZoneProperty("factoryMethod", "inc")
	if aZone:hasProperty("method") then 
		aZone.factoryMethod = aZone:getStringFromZoneProperty("method", "inc")
	end 
	
	if aZone:hasProperty("redP!") then 
		aZone.redP = aZone:getStringFromZoneProperty("redP!", "none")
	end 
	if aZone.redP and aZone.attackersRED ~= "none" then 
		trigger.action.outText("***WARNING: factory <" .. aZone.name .. "> has RED production and uses 'redP!'", 30)
	end

	if aZone:hasProperty("blueP!") then 
		aZone.blueP = aZone:getStringFromZoneProperty("blueP!", "none")
	end
	if aZone.blueP and aZone.attackersBLUE ~= "none" then 
		trigger.action.outText("***WARNING: factory <" .. aZone.name .. "> has BLUE production and uses 'blueP!'", 30)
	end
	
	if aZone:hasProperty("redD!") then 
		aZone.redD = aZone:getStringFromZoneProperty("redD!", "none")
	end
	if aZone.redD and aZone.defendersRED ~= "none" then 
		trigger.action.outText("***WARNING: factory <" .. aZone.name .. "> has RED defenders and uses 'redD!'", 30)
	end 
	
	
	if aZone:hasProperty("blueD!") then 
		aZone.blueD = aZone:getStringFromZoneProperty("blueD!", "none")
	end
	if aZone.blueD and aZone.defendersBLUE ~= "none" then 
		trigger.action.outText("***WARNING: factory <" .. aZone.name .. "> has BLUE defenders and uses 'blueD!'", 30)
	end
	
	if aZone:hasProperty("defendMe?") then 
		aZone.defendMe = aZone:getStringFromZoneProperty("defendMe?", "none")
		aZone.lastDefendMeValue = trigger.misc.getUserFlag(aZone.defendMe)
	end 
	
	factoryZone.zones[aZone.name] = aZone 
	factoryZone.verifyZone(aZone)
end

function factoryZone.verifyZone(aZone)
	-- do some sanity checks
--	if not cfxGroundTroops and (aZone.attackersRED ~= "none" or aZone.attackersBLUE ~= "none") then 
	-- now can also bang on flags, no more verification 
	-- unless we want to beef them up 
--	end
end

function factoryZone.spawnAttackTroops(theTypes, aZone, aCoalition, aFormation)
	local unitTypes = {} -- build type names
	-- split theTypes into an array of types
	unitTypes = dcsCommon.splitString(theTypes, ",")
	if #unitTypes < 1 then 
		table.insert(unitTypes, "Soldier M4") -- make it one m4 trooper as fallback
		-- simply exit, no troops specified 
		if factoryZone.verbose then 
			trigger.action.outText("+++factZ: no attackers for " .. aZone.name .. ". exiting", 30)
		end
		return
	end
	
	if factoryZone.verbose then 
		trigger.action.outText("+++factZ: spawning attackers for " .. aZone.name, 30)
	end
			
	local spawnPoint = {x = aZone.point.x, y = aZone.point.y, z = aZone.point.z} -- copy struct 
	
	local rads = aZone.attackPhi * 0.01745
	spawnPoint.x = spawnPoint.x + math.cos(aZone.attackPhi) * aZone.attackDelta
	spawnPoint.y = spawnPoint.y + math.sin(aZone.attackPhi) * aZone.attackDelta 
	
	local spawnZone = cfxZones.createSimpleZone("attkSpawnZone", spawnPoint, aZone.attackRadius)
	
	local theGroup, theData = cfxZones.createGroundUnitsInZoneForCoalition (
				aCoalition, -- theCountry,							
				aZone.name .. " (A) " .. dcsCommon.numberUUID(),
				spawnZone,				
				unitTypes, 									
				aFormation, -- outward facing
				0,
				factoryZone.liveries)
	return theGroup, theData
end

function factoryZone.spawnDefensiveTroops(theTypes, aZone, aCoalition, aFormation)
	local unitTypes = {} -- build type names
	-- split theTypes into an array of types
	unitTypes = dcsCommon.splitString(theTypes, ",")
	if #unitTypes < 1 then 
		table.insert(unitTypes, "Soldier M4") -- make it one m4 trooper as fallback
		-- simply exit, no troops specified 
		if factoryZone.verbose then 
			trigger.action.outText("+++factZ: no defenders for " .. aZone.name .. ". exiting", 30)
		end
		return
	end
	
	--local theCountry = dcsCommon.coalition2county(aCoalition) 
	local spawnZone = cfxZones.createSimpleZone("spawnZone", aZone.point, aZone.spawnRadius)
	local theGroup, theData = cfxZones.createGroundUnitsInZoneForCoalition (
				aCoalition, --theCountry,				
				aZone.name .. " (D) " .. dcsCommon.numberUUID(),
				spawnZone, 										
				unitTypes,
				aFormation, -- outward facing
				0, 
				factoryZone.liveries)
	return theGroup, theData
end

--
-- U P D A T E 
--

function factoryZone.sendOutAttackers(aZone)

	-- sanity check: never done for neutral zones 
	if aZone.owner == 0 then 
		if aZone.verbose or factoryZone.verbose then 
			trigger.action.outText("+++factZ: SendAttackers invoked for NEUTRAL zone <" .. aZone.name .. ">", 30)
		end
		return 
	end
	
	-- only spawn if there are zones to attack
	if not cfxOwnedZones.enemiesRemaining(aZone) then 
		if aZone.verbose or factoryZone.verbose then 
			trigger.action.outText("+++factZ - no enemies, resting ".. aZone.name, 30)
		end
		return 
	end

	if factoryZone.verbose or aZone.verbose then 
		trigger.action.outText("+++factZ - attack cycle for ".. aZone.name, 30)
	end

	-- bang on xxxP!
	if aZone.owner == 1 and aZone.redP then 
		if aZone.verbose or factoryZone.verbose then
			trigger.action.outText("+++factZ: polling redP! <" .. aZone.redP .. "> for factrory <" .. aZone.name .. ">")
		end 
		aZone:pollFlag(aZone.redP, aZone.factoryMethod)
	end

	if aZone.owner == 2 and aZone.blueP then 
		if aZone.verbose or factoryZone.verbose then
			trigger.action.outText("+++factZ: polling blueP! <" .. aZone.blueP .. "> for factrory <" .. aZone.name .. ">")
		end 
		aZone:pollFlag(aZone.blueP, aZone.factoryMethod)
	end
	
	-- step one: get the attackers 
	local attackers = aZone.attackersRED;
	if (aZone.owner == 2) then attackers = aZone.attackersBLUE end

	if attackers == "none" then return end 

	local theGroup, theData = factoryZone.spawnAttackTroops(attackers, aZone, aZone.owner, aZone.attackFormation)
	
	local troopData = {}
	troopData.groupData = theData
	troopData.orders = "attackOwnedZone" -- lazy coding! 
	troopData.side = aZone.owner
	factoryZone.spawnedAttackers[theData.name] = troopData 
	
	-- submit them to ground troops handler as zoneseekers 
	-- and our groundTroops module will handle the rest 
	if cfxGroundTroops then 
		local troops = cfxGroundTroops.createGroundTroops(theGroup)
		troops.orders = "attackOwnedZone"
		troops.side = aZone.owner
		cfxGroundTroops.addGroundTroopsToPool(troops) -- hand off to ground troops
	else 
		if factoryZone.verbose then 
			trigger.action.outText("+++ Owned Zones: no ground troops module on send out attackers", 30)
		end 
	end
end


function factoryZone.repairDefenders(aZone)
	-- sanity check: never done for non-neutral zones 
	if aZone.owner == 0 then 
		if aZone.verbose or factoryZone.verbose then 
			trigger.action.outText("+++factZ: repairDefenders invoked for NEUTRAL zone <" .. aZone.name .. ">", 30)
		end
		return 
	end
	
	-- find a unit that is missing from my typestring and replace it 
	-- one by one until we are back to full strength
	-- step one: get the defenders and create a type array 
	local defenders = aZone.defendersRED;
	if (aZone.owner == 2) then defenders = aZone.defendersBLUE end
	local unitTypes = {} -- build type names
	
	-- if none, we are done, save for the outputs 
	if (not defenders) or (defenders == "none") then 
		if aZone.owner == 1 and aZone.redD then 
			if aZone.verbose or factoryZone.verbose then
				trigger.action.outText("+++factZ: polling redD! <" .. aZone.redD .. "> for repair factory <" .. aZone.name .. ">", 30)
			end 
			aZone:pollFlag(aZone.redD, aZone.factoryMethod)
		end
		
		if aZone.owner == 2 and aZone.blueD then 
			if aZone.verbose or factoryZone.verbose then
				trigger.action.outText("+++factZ: polling blueD! <" .. aZone.blueD .. "> for repair factory <" .. aZone.name .. ">", 30)
			end 
			aZone:pollFlag(aZone.blueD, aZone.factoryMethod)
		end
		return 
	end 

	-- split theTypes into an array of types	
	allTypes = dcsCommon.trimArray(
			dcsCommon.splitString(defenders, ",")
		)
	local livingTypes = {} -- init to emtpy, so we can add to it if none are alive
	if (aZone.defenders) then 
		-- some remain. add one of the killed
		livingTypes = dcsCommon.getGroupTypes(aZone.defenders)
		-- we now iterate over the living types, and remove their 
		-- counterparts from the allTypes. We then take the first that 
		-- is left
		
		if #livingTypes > 0 then 
			for key, aType in pairs (livingTypes) do 
				if not dcsCommon.findAndRemoveFromTable(allTypes, aType) then 
					trigger.action.outText("+++factZ WARNING: found unmatched type <" .. aType .. "> while trying to repair defenders for ".. aZone.name, 30)
				else 
					-- all good
				end 
			end
		end 
	end
	
	-- when we get here, allTypes is reduced to those that have been killed 
	if #allTypes < 1 then 
		trigger.action.outText("+++factZ: WARNING: all types exist when repairing defenders for ".. aZone.name, 30)
	else 
		table.insert(livingTypes, allTypes[1]) -- we simply use the first that we find
	end
	-- remove the old defenders
	if aZone.defenders then 
		aZone.defenders:destroy()
	end
	
	-- now livingTypes holds the full array of units we need to spawn 
	local theCountry = dcsCommon.getACountryForCoalition(aZone.owner) 
	local spawnZone = cfxZones.createSimpleZone("spawnZone", aZone.point, aZone.spawnRadius)
	local theGroup, theData = cfxZones.createGroundUnitsInZoneForCoalition (
				aZone.owner, -- was wrongly: theCountry		
				aZone.name .. dcsCommon.numberUUID(), -- must be unique 
				spawnZone, 											
				livingTypes, 
				
				aZone.formation, -- outward facing
				0,
				factoryZone.liveries)
	aZone.defenders = theGroup
	aZone.lastDefenders = theGroup:getSize()
end

function factoryZone.inShock(aZone)
	-- a unit was destroyed, everyone else is in shock, no rerpairs 
	-- group can re-shock when another unit is destroyed 
end

function factoryZone.spawnDefenders(aZone)
	-- sanity check: never done for non-neutral zones 
	if aZone.verbose or factoryZone.verbose then 
		trigger.action.outText("+++factZ: starting defender cycle for <" .. aZone.name .. ">", 30)
	end

	if aZone.owner == 0 then 
		if aZone.verbose or factoryZone.verbose then 
			trigger.action.outText("+++factZ: spawnDefenders invoked for NEUTRAL zone <" .. aZone.name .. ">", 30)
		end
		return 
	end

	-- bang! on xxxD!	
	local defenders = aZone.defendersRED;
	if aZone.owner == 1 and aZone.redD then 
		if aZone.verbose or factoryZone.verbose then
			trigger.action.outText("+++factZ: polling redD! <" .. aZone.redD .. "> for factrory <" .. aZone.name .. ">", 30)
		end 
		aZone:pollFlag(aZone.redD, aZone.factoryMethod)
	end
	
	if aZone.owner == 2 and aZone.blueD then 
		if aZone.verbose or factoryZone.verbose then
			trigger.action.outText("+++factZ: polling blueD! <" .. aZone.blueD .. "> for factory <" .. aZone.name .. ">", 30)
		end 
		aZone:pollFlag(aZone.blueD, aZone.factoryMethod)
	end
	
	if (aZone.owner == 2) then defenders = aZone.defendersBLUE end
	-- before we spawn new defenders, remove the old ones
	if aZone.defenders then 
		if aZone.defenders:isExist() then 
			aZone.defenders:destroy()
		end
		aZone.defenders = nil
	end
	
	-- if 'none', simply exit
	if defenders == "none" then return end
	
	local theGroup, theData = factoryZone.spawnDefensiveTroops(defenders, aZone, aZone.owner, aZone.formation)
	-- the troops reamin, so no orders to move, no handing off to ground troop manager
	aZone.defenders = theGroup
	aZone.defenderData = theData -- used for persistence 
	if theGroup then 
		aZone.lastDefenders = theGroup:getInitialSize() 
	else 
		trigger.action.outText("+++factZ: WARNING: spawned no defenders for ".. aZone.name, 30)
		aZone.defenderData = nil 
	end 
end

--
-- per-zone update, run down the FSM to determine what to do.
-- FSM uses timeStamp since when state was set. Possible states are 
--	- init -- has just been inited for the first time. will usually immediately produce defenders, 
--    and then transition to defending 
--  - catured -- has just been captured. transition to defending 
--  - defending -- wait until timer has reached goal, then produce defending units and transition to attacking. 
--  - attacking -- wait until timer has reached goal, and then produce attacking units and send them to closest enemy zone.
--                 state is interrupted as soon as a defensive unit is lost. state then goes to defending with timer starting
--  - idle - do nothing, zone's actions are turned off 
--  - shocked -- a unit was destroyed. group is in shock for a time until it starts repairing. If another unit is 
--               destroyed during the shocked period, the timer resets to zero and repairs are delayed
--  - repairing -- as long as we aren't at full strength, units get replaced one by one until at full strength
--                 each time the timer counts down, another missing unit is replaced, and all other unit's health 
--                 is reset to 100%
--  
--  a Zone with the paused attribute set to true will cause it to not do anything 
--
-- check if defenders are specified
function factoryZone.usesDefenders(aZone) 
	if aZone.owner == 0 then return false end 
	local defenders = aZone.defendersRED;	
	if (aZone.owner == 2) then defenders = aZone.defendersBLUE end
	return defenders ~= "none"
end

function factoryZone.usesAttackers(aZone) 
	if aZone.owner == 0 then return false end 
	local attackers = aZone.attackersRED;	
	if (aZone.owner == 2) then defenders = aZone.attackersBLUE end
	return attackers ~= "none"
end

function factoryZone.updateZoneProduction(aZone)
	-- a zone can be paused, causing it to not progress anything
	-- even if zone status is still init, will NOT produce anything
	-- if paused is on.
	if aZone.paused then return end 

	nextState = aZone.state;
	
	-- first, check if my defenders have been attacked and one of them has been killed
	-- if so, we immediately switch to 'shocked' 
	if factoryZone.usesDefenders(aZone) and 
	   aZone.defenders then 
		-- we have defenders
		if aZone.defenders:isExist() then
			-- see if group was damaged 
			if not aZone.lastDefenders then
				-- fresh group, probably from persistence, needs init 
				aZone.lastDefenders = -1 
			end 
			if aZone.defenders:getSize() < aZone.lastDefenders then 
				-- yes, at least one unit destroyed
				aZone.timeStamp = timer.getTime()
				aZone.lastDefenders = aZone.defenders:getSize()
				if aZone.lastDefenders == 0 then 
					aZone.defenders = nil
				end
				aZone.state = "shocked"

				return 
			else 
				aZone.lastDefenders = aZone.defenders:getSize()
			end
			
		else 
			-- group was destroyed. erase link, and go into shock for the last time 
			aZone.state = "shocked"
			aZone.timeStamp = timer.getTime()
			aZone.lastDefenders = 0
			aZone.defenders = nil
			return 
		end
	end
	
	
	if aZone.state == "init" then 
		-- during init we instantly create the defenders since 
		-- we assume the zone existed already 
		if aZone.owner > 0 then 
			factoryZone.spawnDefenders(aZone)
			-- now drop into attacking mode to produce attackers
			nextState = "attacking"
		else 
			nextState = "idle"
		end
		aZone.timeStamp = timer.getTime()
	
	elseif aZone.state == "idle" then
		-- nothing to do, zone is effectively switched off.
		-- used for neutal zones or when forced to turn off
		-- in some special cases 
		
	elseif aZone.state == "captured" then 
		-- start the clock on defenders
		nextState = "defending"
		aZone.timeStamp = timer.getTime()
		if factoryZone.verbose then 
			trigger.action.outText("+++factZ: State " .. aZone.state .. " to " .. nextState .. " for " .. aZone.name, 30)
		end 
	elseif aZone.state == "defending" then 
		if timer.getTime() > aZone.timeStamp + factoryZone.defendingTime then 
			factoryZone.spawnDefenders(aZone)
			-- now drop into attacking mode to produce attackers
			nextState = "attacking"
			aZone.timeStamp = timer.getTime()
			if factoryZone.verbose then 
				trigger.action.outText("+++factZ: State " .. aZone.state .. " to " .. nextState .. " for " .. aZone.name, 30)
			end
		end

	elseif aZone.state == "repairing" then 
		-- we are currently rebuilding defenders unit by unit 
		if timer.getTime() > aZone.timeStamp + factoryZone.repairTime then 
			aZone.timeStamp = timer.getTime()
			-- wait's up, repair one defender, then check if full strength
			factoryZone.repairDefenders(aZone) -- will also bang on redD and blueD if present 
			-- see if we are full strenght and if so go to attack, else set timer to reair the next unit
			if aZone.defenders and aZone.defenders:isExist() and aZone.defenders:getSize() >= aZone.defenders:getInitialSize() then
				-- we are at max size, time to produce some attackers
				-- progress to next state 
				nextState = "attacking"
				aZone.timeStamp = timer.getTime()
				if factoryZone.verbose then 
					trigger.action.outText("+++factZ: State " .. aZone.state .. " to " .. nextState .. " for " .. aZone.name, 30)
				end 
			elseif (aZone.redD or aZone.blueD) then 
				-- we start attacking cycle for out signal 
				nextState = "attacking"
				aZone.timeStamp = timer.getTime()
				if factoryZone.verbose then 
					trigger.action.outText("+++factZ: progessing tate " .. aZone.state .. " to " .. nextState .. " for " .. aZone.name .. " for redD/blueD", 30)
				end 
			end

		end
		
	elseif aZone.state == "shocked" then 
		-- we are currently rebuilding defenders unit by unit 
		if timer.getTime() > aZone.timeStamp + factoryZone.shockTime then 
			nextState = "repairing"
			aZone.timeStamp = timer.getTime()
			if factoryZone.verbose then 
				trigger.action.outText("+++factZ: State " .. aZone.state .. " to " .. nextState .. " for " .. aZone.name, 30)
			end
		end
		
	elseif aZone.state == "attacking" then 
		if timer.getTime() > aZone.timeStamp + factoryZone.attackingTime then 
			factoryZone.sendOutAttackers(aZone)
			-- reset timer
			aZone.timeStamp = timer.getTime()
			if factoryZone.verbose then 
				trigger.action.outText("+++factZ: State " .. aZone.state .. " reset for " .. aZone.name, 30)
			end
		end
	else 
		-- unknown zone state 
	end
	aZone.state = nextState
end

function factoryZone.GC()
	-- GC run. remove all my dead remembered troops
	local before = #factoryZone.spawnedAttackers
	local filteredAttackers = {}
	for gName, gData in pairs (factoryZone.spawnedAttackers) do 
		-- all we need to do is get the group of that name
		-- and if it still returns units we are fine 
		local gameGroup = Group.getByName(gName)
		if gameGroup and gameGroup:isExist() and gameGroup:getSize() > 0 then 
			filteredAttackers[gName] = gData
		end
	end
	factoryZone.spawnedAttackers = filteredAttackers
	if factoryZone.verbose then 
		trigger.action.outText("owned zones GC ran: before <" .. before .. ">, after <" .. #factoryZone.spawnedAttackers .. ">", 30)
	end
end

function factoryZone.update()
	factoryZone.updateSchedule = timer.scheduleFunction(factoryZone.update, {}, timer.getTime() + 1/factoryZone.ups)
	-- iterate all zones to see if ownership has 
    -- changed 

	for idz, theZone in pairs(factoryZone.zones) do 
		local lastOwner = theZone.factoryOwner
		local newOwner = theZone.owner 
		if (newOwner ~= lastOwner) then 
			theZone.state = "captured"
			theZone.timeStamp = timer.getTime()
			theZone.factoryOwner = theZone.owner 
			if theZone.verbose or factoryZone.verbose then 
				trigger.action.outText("+++factZ: detected factory <" .. theZone.name .. "> changed ownership from <" .. lastOwner .. "> to <" .. theZone.owner .. ">", 30)
			end
		end
		
		-- see if pause/unpause was issued
		if theZone.pauseFlag and cfxZones.testZoneFlag(theZone, theZone.pauseFlag, theZone.factoryTriggerMethod, "lastPauseValue") then
			theZone.paused = true 
		end
		
		if theZone.activateFlag and cfxZones.testZoneFlag(theZone, theZone.activateFlag, theZone.factoryTriggerMethod, "lastActivateValue") then
			theZone.paused = false 
		end
		
		-- see if zone external defendMe was polled to bring it to 
		-- shoked state 
		if theZone.defendMe and theZone:testZoneFlag(theZone.defendMe, theZone.factoryTriggerMethod, "lastDefendMeValue") then 
			if theZone.verbose or factoryZone.verbose then 
				trigger.action.outText("+++factZ: setting factory <" .. theZone.name .. "> to shocked/produce defender mode", 30)
			end 
			theZone.state = "shocked"
			theZone.timeStamp = timer.getTime()
			theZone.lastDefenders = 0
			theZone.defenders = nil -- nil, but no delete!
		end
		
		-- do production for this zone 
		factoryZone.updateZoneProduction(theZone)
	end -- iterating all zones 
end

function factoryZone.houseKeeping()
	timer.scheduleFunction(factoryZone.houseKeeping, {}, timer.getTime() + 5 * 60) -- every 5 minutes 
	factoryZone.GC()
end


--
-- load / save data 
--

function factoryZone.saveData()
	-- this is called from persistence when it's time to 
	-- save data. returns a table with all my data 
	local theData = {}
	local allZoneData = {}
	-- iterate all my zones and create data 
	for idx, theZone in pairs(factoryZone.zones) do
		local zoneData = {}
		if theZone.defenderData then 
			zoneData.defenderData = dcsCommon.clone(theZone.defenderData)
			dcsCommon.synchGroupData(zoneData.defenderData)
		end 
		zoneData.owner = theZone.owner 
		zoneData.state = theZone.state -- will prevent immediate spawn
			-- since new zones are spawned with 'init'
		allZoneData[theZone.name] = zoneData
	end
	
	-- now iterate all attack groups that we have spawned and that 
	-- (maybe) are still alive 
	factoryZone.GC() -- start with a GC run to remove all dead 
	local livingAttackers = {}
	for gName, gData in pairs (factoryZone.spawnedAttackers) do 
		-- all we need to do is get the group of that name
		-- and if it still returns units we are fine 
		-- spawnedAttackers is a [groupName] table with {.groupData, .orders, .side}
		local gameGroup = Group.getByName(gName)
		if gameGroup and gameGroup:isExist() then 
			if gameGroup:getSize() > 0 then 
				local sData = dcsCommon.clone(gData)
				dcsCommon.synchGroupData(sData.groupData)
				livingAttackers[gName] = sData
			end
		end
	end
	
	-- now write the info for the flags that we output for #red, etc
	local flagInfo = {} -- no longer used 

	-- assemble the data 
	theData.zoneData = allZoneData
	theData.attackers = livingAttackers
	theData.flagInfo = flagInfo
	
	-- return it 
	return theData
end

function factoryZone.loadData()
	-- remember to draw in map with new owner 
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("factoryZone")
	if not theData then 
		if factoryZone.verbose then 
			trigger.action.outText("factZ: no save date received, skipping.", 30)
		end
		return
	end
	-- theData contains the following tables:
	--   zoneData: per-zone data 
	--   flagInfo: module-global flags 
	--   attackers: all spawned attackers that we feed to groundTroops
	local allZoneData = theData.zoneData 
	for zName, zData in pairs(allZoneData) do 
		-- access zone 
		local theZone = factoryZone.getFactoryZoneByName(zName)-- was: factoryZone.getOwnedZoneByName(zName)
		if theZone then 
			if zData.defenderData then 
				if theZone.defenders and theZone.defenders:isExist() then
					-- should not happen, but so be it
					theZone.defenders:destroy()
				end
				local gData = zData.defenderData
				local cty = gData.cty 
				local cat = gData.cat 
				theZone.defenders = coalition.addGroup(cty, cat, gData)
				theZone.defenderData = zData.defenderData
			end
			theZone.owner = zData.owner 
			theZone.factoryOwner = theZone.owner 
			theZone.state = zData.state 

		else 
			trigger.action.outText("factZ: load - data mismatch: cannot find zone <" .. zName .. ">, skipping zone.", 30)
		end
	end
	
	-- now process all attackers 
	local allAttackers = theData.attackers
	for gName, gdTroop in pairs(allAttackers) do 
		-- table is {.groupData, .orders, .side}
		local gData = gdTroop.groupData 
		local orders = gdTroop.orders 
		local side = gdTroop.side 
		local cty = gData.cty 
		local cat = gData.cat 
		-- add to my own attacker queue so we can save later 
		local dClone = dcsCommon.clone(gdTroop)
		factoryZone.spawnedAttackers[gName] = dClone 
		local theGroup = coalition.addGroup(cty, cat, gData)
		if cfxGroundTroops then 
			local troops = cfxGroundTroops.createGroundTroops(theGroup)
			troops.orders = orders
			troops.side = side
			cfxGroundTroops.addGroundTroopsToPool(troops) -- hand off to ground troops
		end 
	end
	
	-- now process module global flags 
	local flagInfo = theData.flagInfo
	if flagInfo then 
	end
end

 
--
function factoryZone.readConfigZone(theZone)
	if not theZone then theZone = cfxZones.createSimpleZone("factoryZoneConfig") end 
	factoryZone.name = "factoryZone" -- just in case, so we can access with cfxZones 
	factoryZone.verbose = theZone.verbose
	factoryZone.defendingTime = theZone:getNumberFromZoneProperty( "defendingTime", 100)
	factoryZone.attackingTime = theZone:getNumberFromZoneProperty( "attackingTime", 300)
	if theZone:hasProperty("productionTime") then 
		factoryZone.attackingTime = theZone:getNumberFromZoneProperty( "productionTime", 300)
	end 
	factoryZone.shockTime = theZone:getNumberFromZoneProperty("shockTime", 200)
	factoryZone.repairTime = theZone:getNumberFromZoneProperty( "repairTime", 200)
	factoryZone.targetZones = "OWNED"

end

function factoryZone.readLiveries()
	theZone = cfxZones.getZoneByName("factoryLiveries") 
	if not theZone then return end 
	factoryZone.liveries = theZone:getAllZoneProperties()
	trigger.action.outText("Custom liveries detected. All factories now use:", 30)
	for aType, aLivery in pairs (factoryZone.liveries) do 
		trigger.action.outText(" type <" .. aType .. "> now uses livery <" .. aLivery .. ">", 30)
	end 
end


function factoryZone.init()
	-- check libs
	if not dcsCommon.libCheck("cfx Factory Zones", 
		factoryZone.requiredLibs) then
		return false 
	end

	-- read my config zone
	local theZone = cfxZones.getZoneByName("factoryZoneConfig") 
	factoryZone.readConfigZone(theZone)

	-- read livery presets for factory production 
	factoryZone.readLiveries()
	
	-- collect all zones by their 'factory' property 
	-- start the process
	local pZones = cfxZones.zonesWithProperty("factory")
	for k, aZone in pairs(pZones) do
		factoryZone.addFactoryZone(aZone)
	end
	
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = factoryZone.saveData
		persistence.registerModule("factoryZone", callbacks)
		-- now load my data 
		factoryZone.loadData()
	end
	
	initialized = true 
	factoryZone.updateSchedule = timer.scheduleFunction(factoryZone.update, {}, timer.getTime() + 1/factoryZone.ups)
	
	-- start housekeeping 
	factoryZone.houseKeeping()
	
	trigger.action.outText("cx/x factory zones v".. factoryZone.version .. " started", 30)
	
	return true 
end

if not factoryZone.init() then 
	trigger.action.outText("cf/x Factory Zones aborted: missing libraries", 30)
	factoryZone = nil 
end


-- add property to factory attribute to restrict production to that side, 
-- eg factory blue will only work for blue, else will work for any side 
-- currently not needed since we have defendersRED/BLUE and productionRED/BLUE
