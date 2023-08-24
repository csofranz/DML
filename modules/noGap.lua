noGap = {}
noGap.version = "1.0.0"

noGap.verbose = false 
noGap.ignoreMe = "-ng" -- ignore altogether
noGap.spIgnore = "-sp" -- only single-player ignored 
noGap.isMP = false 
noGap.enabled = true 
noGap.timeOut = 0 -- in seconds, after that static restores, set to 0 to disable 

noGap.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
	"cfxMX",
}
--[[--
	Written and (c) 2023 by Christian Franz 

	Based on stopGap. Unlike stopGap, noGap 
	works on unit-level (stop-Gap works on group level)
	Advantage: multiple-ship player groups look better, less code
	Disadvantage: incompatibe with SSB/slotBlock
	
	What it does:
	Replace all player units with static aircraft until the first time 
	that a player slots into that plane. Static is then replaced with live player unit. 
	
	DOES NOT SUPPORT SHIP-BASED AIRCRAFT 
	
	For multiplayer, NoGapGUI must run on the server (only server)

	STRONGLY RECOMMENDED FOR MISSION DESIGNERS:
	- Use 'start from ground hot/cold' to be able to control initial aircraft orientation

	To selectively exempt player units from noGap, add a '-ng' to their name. To exclude them from singleplayer only, use '-sp' 
	Alternatively, use noGap zones (DML only)
	
	Version History
	1.0.0 - Initial version
    
--]]--

noGap.standInUnits = {} -- static replacement, if filled; indexed by name
noGap.liveUnits = {} -- live in-game units, checked regularly
noGap.allPlayerUnits = {} -- for update check to get server notification 
noGap.noGapZones = {} -- DML only 

function noGap.staticMXFromUnitMX(theGroup, theUnit)
	-- enter with MX data blocks
	-- build a static object from mx unit data 
	local theStatic = {}
	theStatic.x = theUnit.x 
	theStatic.y = theUnit.y 
	theStatic.livery_id = theUnit.livery_id -- if exists 
	theStatic.heading = theUnit.heading -- may need some attention
	theStatic.type = theUnit.type 
	theStatic.name = theUnit.name  -- same as ME unit 
	theStatic.cty = cfxMX.countryByName[theGroup.name]
	return theStatic 
end

function noGap.staticMXFromUnitName(uName)
	local theGroup = cfxMX.playerUnit2Group[uName]
	local theUnit = cfxMX.playerUnitByName[uName]
	if theGroup and theUnit then 
		return noGap.staticMXFromUnitMX(theGroup, theUnit)
	end
	trigger.action.outText("+++noG: ERROR: can't find MX data for unit <" .. uName .. ">", 30)
end

function noGap.isGroundStart(theGroup)
	-- look at route 
	if not theGroup.route then return false end 
	local route = theGroup.route 
	local points = route.points 
	if not points then return false end
	local ip = points[1]
	if not ip then return false end 
	local action = ip.action 
	if action == "Fly Over Point" then return false end 
	if action == "Turning Point" then return false end 	
	if action == "Landing" then return false end 	
	-- aircraft is on the ground - but is it in water (carrier)? 
	local u1 = theGroup.units[1]
	local sType = land.getSurfaceType(u1) -- has fields x and y
	if sType == 3 then return false	end 
	if noGap.verbose then 
		trigger.action.outText("noG: Player Group <" .. theGroup.name .. "> GROUND BASED: " .. action .. ", land type " .. sType, 30)
	end 
	return true
end

function noGap.ignoreMXUnit(theUnit) -- DML-only 
	local p = {x=theUnit.x, y=0, z=theUnit.y}
	for idx, theZone in pairs(noGap.noGapZones) do 
		if theZone.ngIgnore and cfxZones.pointInZone(p, theZone) then 
			return true
		end
		-- only single-player: exclude units in spIgnore zones 
		if (not noGap.isMP) and
			theZone.spIgnore and cfxZones.pointInZone(p, theZone) then 
			return true
		end
	end
	return false
end

function noGap.createStandInForMXData(group, theUnit) -- group, theUnit are MX data blocks
	local sgMatch = theUnit.name:sub(-#noGap.ignoreMe) == noGap.ignoreMe or group.name:sub(-#noGap.ignoreMe) == noGap.ignoreMe
	local spMatch = theUnit.name:sub(-#noGap.spIgnore) == noGap.spIgnore or group.name:sub(-#noGap.spIgnore) == noGap.spIgnore
	local zoneIgnore = noGap.ignoreMXUnit(theUnit)
	local inGameUnit = Unit.getByName(theUnit.name)
	if (theUnit.skill == "Client" or theUnit.skill == "Player") 
	   and (not sgMatch)
	   and (not spMatch)
	   and (not zoneIgnore)
	then
		-- remember this unit as one to check regularly 
		noGap.allPlayerUnits[theUnit.name] = "NG" .. theUnit.name
		-- replace this unit with stand-in if not already in game 
		if inGameUnit and Unit.isExist(inGameUnit) then 
			-- already exists, do NOT allocate, and erase 
			-- any lingering data 
			noGap.standInUnits[theUnit.name] = nil -- forget static
			noGap.liveUnits[theUnit.name] = inGameUnit -- remember live
			if noGap.verbose then 
				trigger.action.outText("+++noG: skipped - unit <" .. theUnit.name  .. "> of <" .. group.name .. ">", 30)
			end
		else 
			-- create a stand-in
			-- and remember 
			local theStaticMX = noGap.staticMXFromUnitMX(group, theUnit)
			local theStatic = coalition.addStaticObject(theStaticMX.cty, theStaticMX)
			noGap.standInUnits[theUnit.name] = theStatic -- remember me
			if noGap.verbose then 
				trigger.action.outText("+++noG: unit <" .. theUnit.name  .. "> of <" .. group.name .. "> nogapped", 30)
			end
		end
	end
	
end

function noGap.fillGaps()
	-- turn on. May turn on any time, even during game 
	-- when we enter, all slots should be emptry 
	-- and we populate all slots. If slot in use, don't populate
	-- with their static representations 
	-- a 'slot' is a player aircraft 
	-- iterate all groups that have at least one player and groundstart
	-- as filtered by cfxMX
	-- we need to access group because that contains start info 
	for gName, groupData in pairs (cfxMX.playerGroupByName) do 
		-- check to see if this group is on the ground at parking 
		-- by looking at the first waypoint 
		if noGap.isGroundStart(groupData) then 
			-- this is one of ours!
			-- iterate all player units in this group, 
			-- and replace those units that are player units
			local allUnits = groupData.units
			for idx, unitData in pairs(allUnits) do 
				noGap.createStandInForMXData(groupData, unitData)
			end
		end -- if groundtstart
	end
end

function noGap.turnOff()
	if noGap.verbose then 
		trigger.action.outText("+++noG: Turning OFF", 30)
	end
	-- remove all stand-ins
	for uName, standIn in pairs (noGap.standInUnits) do 
		StaticObject.destroy(standIn)
	end
	noGap.standInUnits = {}
end

function noGap.turnOn()
	if noGap.verbose then 
		trigger.action.outText("+++noG: Turning on", 30)
	end
	-- populate all empty (non-taken) slots with stand-ins
	noGap.fillGaps()
end

-- 
-- event handling 
--
function noGap:onEvent(event)
	if not event then return end 
	if not event.id then return end 
	if not event.initiator then return end 
	local theUnit = event.initiator 

	if event.id == 15 then -- we act on player unit birth 
		if (not theUnit.getPlayerName) or (not theUnit:getPlayerName()) then 
			return 
		end -- no player unit.
		local uName = theUnit:getName()
		
		if noGap.standInUnits[uName] then
			-- remove static
			StaticObject.destroy(noGap.standInUnits[uName])
			noGap.standInUnits[uName] = nil 
			if noGap.verbose then 
				trigger.action.outText("+++noG: removed static for <" ..uName  .. ">, player inbound", 30)
			end
		end
		noGap.liveUnits[uName] = theUnit
		-- reset noGapGUI flag, it has done its job. Unit is live   
		-- we can reset it for next iteration 
		trigger.action.setUserFlag("NG"..uName, 0)
	end
end

--
-- update, includes MP client check code
--
function noGap.update()
	-- check every second. 
	timer.scheduleFunction(noGap.update, {}, timer.getTime() + 1)

	if not noGap.isMP then 
		local ngDetect = trigger.misc.getUserFlag("noGapGUI")
		if ngDetect > 0 then 
			trigger.action.outText("noGap: MP activated <" .. ngDetect .. ">, will re-init", 30) 
			noGap.turnOff()
			noGap.isMP = true 
			if noGap.enabled then 
				noGap.turnOn()
			end
			return 
		end  
	end

	-- check if client signals for on? or off? 
	if noGap.turnOn and cfxZones.testZoneFlag(noGap, noGap.turnOnFlag, noGap.triggerMethod, "lastTurnOnFlag") -- warning: noGap is NOT a dmlZone, requires cfxZone invocation 
	then
		if not noGap.enabled then 
			noGap.turnOn()
		else 
			if noGap.verbose then 
				trigger.action.outText("+++noG: ignored tun ON event, already active", 30)
			end
		end
		noGap.enabled = true 
	end
	
	if noGap.turnOff and cfxZones.testZoneFlag(noGap, noGap.turnOffFlag, noGap.triggerMethod, "lastTurnOffFlag") then
		if noGap.enabled then 
			noGap.turnOff()
		end
		noGap.enabled = false 
	end
	
	if not noGap.enabled then return end 
	
	-- check if activeUnit has disappeared an returns to slot 
	local filtered = {}
	for name, theUnit in pairs(noGap.liveUnits) do 
		if Unit.isExist(theUnit) then 
			-- unit still alive
			filtered[name] = theUnit
		else 
			-- unit disappeared, make static show up in slot 
			-- no copy to filtered 
			local theStaticMX = noGap.staticMXFromUnitName(name)
			local theStatic = coalition.addStaticObject(theStaticMX.cty, theStaticMX)
			noGap.standInUnits[name] = theStatic -- remember me
			if noGap.verbose then 
				trigger.action.outText("+++noG: unit <" .. name  .. "> nogapped", 30)
			end
		end
	end
	noGap.liveUnits = filtered 
	
	-- check if noGapGUI signals slot interest by player 
	for name, ngName in pairs (noGap.allPlayerUnits) do 
		local ngFlag = trigger.misc.getUserFlag(ngName)
		if ngFlag > 0 then 
			if noGap.standInUnits[name] then 
				-- static needs to be removed, server wants to occupy
				StaticObject.destroy(noGap.standInUnits[name])
				noGap.standInUnits[name] = nil 
				if noGap.verbose then 
					trigger.action.outText("+++noG: removing static <" .. name .. "> for server request", 30)
				end
				-- set flag-based timer 
				if noGap.timeOut > 0 then 
					trigger.action.setUserFlag(ngName,-noGap.timeOut)
				end
			end
		elseif ngFlag < 0 then 
			-- timer is running, count up to 0  
			ngFlag = ngFlag + 1
			if ngFlag > -1 then 
				-- timeout. restore static. this may cause if crash if 
				-- player waited too long without actually slotting in.
				ngFlag = 0
				local theStaticMX = noGap.staticMXFromUnitName(name)
				local theStatic = coalition.addStaticObject(theStaticMX.cty, theStaticMX)
				noGap.standInUnits[name] = theStatic -- remember me
				if noGap.verbose then 
					trigger.action.outText("+++noG: unit <" .. name  .. "> restored after timeout", 30)
				end
			end 
			trigger.action.setUserFlag(ngName, ngFlag)
		end
	end	
end

-- 
-- read stopGapZone (DML only)
--
function noGap.createNoGapZone(theZone)
	local ng = theZone:getBoolFromZoneProperty("noGap", true)
	if ng then theZone.ngIgnore = false else theZone.sgIgnore = true end 
end

function noGap.createNoGapSPZone(theZone)
	local sp = theZone:getBoolFromZoneProperty("noGapSP", true)
	if sp then theZone.spIgnore = false else theZone.spIgnore = true end 
end

--
-- Read Config Zone
--
noGap.name = "noGapConfig" -- cfxZones compatibility here 
function noGap.readConfigZone(theZone)
	-- currently nothing to do 
	noGap.verbose = theZone.verbose 
	noGap.enabled = theZone:getBoolFromZoneProperty("onStart", true)
	noGap.timeOut = theZone:getNumberFromZoneProperty("timeOut", 0) -- default to off 
	if theZone:hasProperty("on?") then 
		noGap.turnOnFlag = theZone:getStringFromZoneProperty("on?", "*<none>")
		noGap.lastTurnOnFlag = trigger.misc.getUserFlag(noGap.turnOnFlag)
	end
	if theZone:hasProperty("off?") then 
		noGap.turnOffFlag = theZone:getStringFromZoneProperty("off?", "*<none>")
		noGap.lastTurnOffFlag = trigger.misc.getUserFlag(noGap.turnOffFlag)
	end
	noGap.triggerMethod = theZone:getStringFromZoneProperty( "triggerMethod", "change")
	if noGap.verbose then 
		trigger.action.outText("+++no: config read, verbose = YES", 30)
		if noGap.enabled then 
			trigger.action.outText("+++noG: enabled", 30)
		else 
			trigger.action.outText("+++noG: turned off", 30)		
		end 
	end
end

--
-- get going 
--
function noGap.start()
	if not dcsCommon.libCheck("cfx noGap", 
							  noGap.requiredLibs) 
	then return false end
	
	local sgDetect = trigger.misc.getUserFlag("noGapGUI")
	noGap.isMP = sgDetect > 0 
	
	local theZone = cfxZones.getZoneByName("noGapConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("noGapConfig")
	end
	noGap.readConfigZone(theZone)
	
	-- collect exclusion zones
	local pZones = cfxZones.zonesWithProperty("noGap")
	for k, aZone in pairs(pZones) do
		noGap.createNoGapZone(aZone)
		noGap.noGapZones[aZone.name] = aZone
	end
	
	-- collect single-player exclusion zones
	local pZones = cfxZones.zonesWithProperty("noGapSP")
	for k, aZone in pairs(pZones) do
		noGap.createNoGapSPZone(aZone)
		noGap.noGapZones[aZone.name] = aZone
	end
	
	-- fill player slots with static objects 
	if noGap.enabled then 
		noGap.fillGaps()
	end 
	
	-- connect event handler
	world.addEventHandler(noGap)
	
	-- start update in 10 seconds 
	timer.scheduleFunction(noGap.update, {}, timer.getTime() + 1)
	
	-- say hi!
	local mp = " (SP - <" .. sgDetect .. ">)"
	if sgDetect > 0 then mp = " -- MP GUI Detected (" .. sgDetect .. ")!" end
	trigger.action.outText("noGap v" .. noGap.version .. "  running" .. mp, 30)	

	return true 
end

if not noGap.start() then 
	trigger.action.outText("+++ aborted noGap v" .. noGap.version .. "  -- startup failed", 30)
	noGap = nil 
end
