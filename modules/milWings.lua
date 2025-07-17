milWings = {}
milWings.version = "0.9.8"
milWings.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
	"cfxMX",
	"wingTaskHelper",
}
milWings.zones = {} -- mil wings zones for flights. can have master owner 
milWings.targetKeywords = { -- same as mil helo plus x
	"wingTarget", -- my own zone
	"milTarget", -- milH zones 
	"camp", -- camps 
	"airfield", -- airfields
	"FARP", -- FARPzones 
	}
	
milWings.targets = {} -- targets for mil wings. can have master owner
-- includes wingTarget and other keywors 
milWings.pureTargets = {} -- targets with wingTarget keyword 
milWings.seadTargets = {}
milWings.flights = {} -- all currently active mil helo flights 
milWings.ups = 1 
milWings.missionTypes = {
	"cas", -- standard cas 
	"cap", -- orbit over zone for duration 
	"sead", -- engage in zone for target zone's radius 	
	"bomb",
}

function milWings.addMilWingsZone(theZone)
	milWings.zones[theZone.name] = theZone
end 

function milWings.addMilWingsTargetZone(theZone)
	milWings.targets[theZone.name] = theZone -- overwrite if duplicate
	if theZone:hasProperty("SEAD") then 
		milWings.seadTargets[theZone.name] = theZone 
	end 
	if theZone:hasProperty("wingTarget") then 
		milWings.pureTargets[theZone.name] = theZone 
		theZone.wingTargetName = theZone:getStringFromZoneProperty("wingTarget", "<*" .. theZone.name .. ">")
	end 
	
end

--
-- Reading / Processing milWings Zones 
--
function milWings.partOfGroupDataInZone(theZone, theUnits) -- move to mx?
	local zP = theZone:getDCSOrigin() -- don't use getPoint now.
	zP.y = 0
	for idx, aUnit in pairs(theUnits) do 
		local uP = {}
		uP.x = aUnit.x 
		uP.y = 0
		uP.z = aUnit.y -- !! y-z
		if theZone:pointInZone(uP) then return true end 
	end 
	return false 
end

function milWings.allGroupsInZoneByData(theZone) -- move to MX?
	local theGroupsInZone = {}
	local count = 0
	for groupName, groupData in pairs(cfxMX.groupDataByName) do 
		if groupData.units then 
			if milWings.partOfGroupDataInZone(theZone, groupData.units) then 
				theGroupsInZone[groupName] = groupData -- DATA! work on clones!
				count = count + 1 
				if theZone.verbose then 
					trigger.action.outText("+++milH: added group <" .. groupName .. "> for zone <" .. theZone.name .. ">", 30)
				end 
			end
		end
	end
	return theGroupsInZone, count 
end

function milWings.readMilWingsZone(theZone) -- process attributes
	theZone.msnType = string.lower(theZone:getStringFromZoneProperty("milWings", "cas")) 
	if dcsCommon.arrayContainsString(milWings.missionTypes, theZone.msnType) then 
		-- great, mission type is known
	else 
		trigger.action.outText("+++milW: zone <" .. theZone.name .. ">: unknown wing mission type <" .. theZone.msnType .. ">, defaulting to 'CAS'", 30)
		theZone.msnType = "cas"
	end 
	
	-- see if our ownership is tied to a master
	-- this adds dynamic coalition capability 	
	if theZone:hasProperty("masterOwner") then 
		local mo = theZone:getStringFromZoneProperty("masterOwner")
		local mz = cfxZones.getZoneByName(mo)
		if not mz then 
			trigger.action.outText("+++milW: WARNING: Master Owner <" .. mo .. "> for zone <" .. theZone.name .. "> does not exist!", 30)
		else 
			theZone.masterOwner = mz 
		end
		theZone.isDynamic = theZone:getBoolFromZoneProperty("dynamic", true)
		if theZone.verbose then 
			trigger.action.outText("milwing target <" .. theZone.name .. "> has masterOwner <" .. theZone.mz.name .. ">", 30)
			if theZone.isDynamic then 
				trigger.action.outText("and coa is dynamically linked to owner.", 30)
			end
		end
	end

	-- get all groups inside me	
	local myGroups, count = milWings.allGroupsInZoneByData(theZone) 
	theZone.fGroups = {}
	theZone.fCount = 0 
	-- sort into ground, helo and fixed 
	for groupName, data in pairs(myGroups) do 
		local catRaw = cfxMX.groupTypeByName[groupName]
		if theZone.verbose then 
			trigger.action.outText("Proccing zone <" .. theZone.name .. ">: group <" .. groupName .. "> - type <" .. catRaw .. ">", 30)
		end 
		if catRaw == "plane" then 
			theZone.fGroups[groupName] = data 
			theZone.fCount = theZone.fCount +  1
		else 
			trigger.action.outText("+++milH: ignored group <" .. groupName .. ">: wrong type <" .. catRaw .. ">", 30)
		end 
	end 
	theZone.coa = theZone:getCoalitionFromZoneProperty("coalition", 0)
	theZone.hot = theZone:getBoolFromZoneProperty("hot", false) 
	theZone.inAir = theZone:getBoolFromZoneProperty("inAir", false)
	theZone.speed = theZone:getNumberFromZoneProperty("speed", 220) -- 800 kmh
	theZone.alt = theZone:getNumberFromZoneProperty("alt", 6000) -- we are always radar alt 
	theZone.loiter = theZone:getNumberFromZoneProperty("loiter", 3600) -- 1 hour loiter default 

	-- wipe all existing 
	for groupName, data in pairs(theZone.fGroups) do 
		local g = Group.getByName(groupName) 
		if g then 
			Group.destroy(g)
		end 
	end 
	if theZone.verbose or milWings.verbose then 
		trigger.action.outText("+++milW: processed milWings zone <" .. theZone.name .. ">", 30)
	end
end 
	
function milWings.readMilWingsTargetZone(theZone)
	-- can also be "camp", "farp", "airfield"
	theZone.wingRadius = theZone:getNumberFromZoneProperty("wingRadius", theZone.radius)
	if (not theZone.isCircle) and (not theZone:hasProperty("wingRadius")) then
		-- often when we have a camp there is no cas radius, use 60km 
		-- and zone is ploygonal 
		if theZone.verbose then 
			trigger.action.outText("+++milH: Warning - milH target zone <" .. theZone.name .. "> is polygonal and has no CAS radius attribute. Defaulting to 80km", 30)
		end 
--		theZone.casRadius = 80000
		theZone.wingRadius = 80000
	end 
	
	if theZone:hasProperty("wingTypes") then -- if present, else all good 
		theZone.wingTypes = theZone:getListFromZoneProperty("wingTypes", "empty")
	end 
	
	if theZone.verbose or milWings.verbose then 
		trigger.action.outText("+++milH: processed milWings TARGET zone <" .. theZone.name .. ">", 30)
	end
	
	if theZone:hasProperty("masterOwner") then 
		local mo = theZone:getStringFromZoneProperty("masterOwner")
		local mz = cfxZones.getZoneByName(mo)
		if not mz then 
			trigger.action.outText("+++milW: WARNING: Master Owner <" .. mo .. "> for zone <" .. theZone.name .. "> does not exist!", 30)
		else 
			theZone.masterOwner = mz 
		end
	end
end 


--
-- creating flights
--
function milWings.createTakeOffWayPoint(theZone, targetZone)
	local wp = {}
	wp.alt = theZone.alt 
	wp.action = "Turning Point" -- default. overrides hot 
	wp.type = "Turning Point"
	if not theZone.inAir then 
		if theZone.hot then 
			wp.action = "From Parking Area Hot"
			wp.type = "TakeOffParkingHot"
		else 
			wp.action = "From Parking Area"
			wp.type = "TakeOffParking"
		end 
		wp.alt = 0 
		wp.speed = 0 
		local af = dcsCommon.getClosestAirbaseTo(theZone:getPoint(), 0)
--		trigger.action.outText("closest airfield for this flight is <" .. af:getName() .. ">", 30)
		wp.airdromeId = af:getID()
	end
--	trigger.action.outText("flight has action <" .. wp.action .. "> and type <" .. wp.type .. ">", 30)

	wp.speed = theZone.speed 
	local p = theZone:getPoint()
	wp.x = p.x 
	wp.y = p.z 
	wp.formation_template= ""
	if theZone.msnType == "cas" then 
		wp.task = dcsCommon.clone(wingTaskHelper.casTOTask)
		-- now simply change some bits from the template 
		p = targetZone:getPoint()
		wp.task.params.tasks[8].params.x = p.x 
		wp.task.params.tasks[8].params.y = p.z
		if targetZone.wingRadius then -- should ALWAYS be true 
			wp.task.params.tasks[8].params.zoneRadius = targetZone.wingRadius
		else 
			wp.task.params.tasks[8].params.zoneRadius = 80000
			trigger.action.outText("WARNING: creating CAS flight <" .. theZone.name .. "> with no radius for target zone <" .. targetZone.name .. ">", 30)
		end 
	elseif theZone.msnType == "cap" then 
		wp.task = dcsCommon.clone(wingTaskHelper.capTOTask)
		p = targetZone:getPoint()
		wp.task.params.tasks[6].params.x = p.x 
		wp.task.params.tasks[6].params.y = p.z
--		wp.task.params.tasks[6].params.zoneRadius = theZone.capRadius
		if targetZone.wingRadius then -- should ALWAYS be true 
			wp.task.params.tasks[6].params.zoneRadius = targetZone.wingRadius
		else 
			wp.task.params.tasks[6].params.zoneRadius = 80000
--			trigger.action.outText("WARNING: creating CAP flight <" .. theZone.name .. "> with no radius for target zone <" .. targetZone.name .. ">", 30)
		end
	elseif theZone.msnType == "sead" then
		wp.task = dcsCommon.clone(wingTaskHelper.seadTOTask)
	elseif theZone.msnType == "bomb" then 
		wp.task = dcsCommon.clone(wingTaskHelper.bombTOTask)
	else 
		trigger.action.outText("milW: unknown msnType <" .. theZone.msnType .. "> in zone <" .. theZone.name .. ">", 30)
	end 
	
	return wp 
end

function milWings.createActionWaypoint(theZone, targetZone)
	local p = targetZone:getPoint()
	local wp = dcsCommon.createSimpleRoutePointData(p, theZone.alt, theZone.speed)
	if theZone.msnType == "bomb" then 
		local task = dcsCommon.clone(wingTaskHelper.bombActionTask)
		task.params.tasks[1].params.x = p.x 
		task.params.tasks[1].params.y = p.z 
		task.params.tasks[1].params.altitude = theZone.alt 
		task.params.tasks[1].params.speed = theZone.speed 
		wp.task = task
	end
	return wp 
end

function milWings.createCommandTask(theCommand, num) 
	if not num then num = 1 end 
	local t = {}
	t.enabled = true 
	t.auto = false 
	t.id = "WrappedAction"
	t.number = num 
	local params = {}
	t.params = params 
	local action = {}
	params.action = action 
	action.id = "Script"
	local p2 = {}
	action.params = p2 
	p2.command = theCommand 
	return t 
end

function milWings.createCallbackWP(gName, number, pt, alt, speed, action) -- name is group name
	if not action then action = "none" end 
	local omwWP = dcsCommon.createSimpleRoutePointData(pt, alt, speed)
	omwWP.alt_type = "BARO"
	-- create a command waypoint
	local task = {}
	task.id = "ComboTask"
	task.params = {}
	local ttsk = {} 
	local command = "milWings.inFlightCB('" .. gName .. "', '" .. number .. "', '" .. action .."')"
	ttsk[1] = milWings.createCommandTask(command,1)
	task.params.tasks = ttsk
	omwWP.task = task 	
	return omwWP
end

function milWings.spawnForZone(theZone, targetZone, diffMod) -- fiffMod is difficulty modificator
	if not diffMod then diffMod = 1 end -- default to 1
	--[[--
		difficulties:
			1 = normal, do not modify
			0 = set to rookie
			2 or more set to ace
		note that skill levels are named very different in the mission
	--]]--
	-- pick one of the flight groups 
	if not theZone.fCount or theZone.fCount < 1 then 
		trigger.action.outText("+++milW: WARNING - no f-groups in zone <" .. theZone.name .. "> at spawnForZone", 30)
		return nil, nil 
	end 	
	local n = dcsCommon.randomBetween(1, theZone.fCount)
	local theRawData = dcsCommon.getNthItem(theZone.fGroups, n)
	local gData = dcsCommon.clone(theRawData)
	if not gData then 
		trigger.action.outText("+++milW: WARNING: NIL gData in spawnForZone for <" .. theZone.name .. ">", 30)
		return nil, nil 
	end 
	gData.lateActivation = false 
	
	local oName = gData.name 

	-- pre-process gData: names, id etc
	gData.name = dcsCommon.uuid(gData.name)
	local gName = gData.name 
	for idx, uData in pairs(gData.units) do 
		uData.name = dcsCommon.uuid(uData.name)
		uData.alt = theZone.alt
		if diffMod < 1 then -- set to rookie 
			uData.skill = "Average" -- that's rookie!
		elseif diffMod > 1 then -- set to ace 
			uData.skill = "Excellent" -- 'Ace'
		else
			-- keep unchanged 
		end 
		uData.alt_type = "BARO"
		uData.speed = theZone.speed 
		uData.unitId = nil 
	end
	gData.groupId = nil 
	
	-- set task for group 
	gData.task = "CAS" -- default 
	if theZone.msnType == "cap" then 
		gData.task = "CAP"
	elseif theZone.msnType == "sead" then 
		gData.task = "SEAD"
	elseif theZone.msnType == "bomb" then
		gData.task = "Ground Attack"
	end 
--	trigger.action.outText("main task is " .. gData.task, 30)
	
	-- create route 
	local route = {}
	route.routeRelativeTOT = true 
	route.points = {}
	gData.route = route 
	
	-- create take-off waypoint for this flight 
	local wpTOff = milWings.createTakeOffWayPoint(theZone, targetZone)
	dcsCommon.addRoutePointForGroupData(gData, wpTOff)
	
	-- ingress point 
	local dest = targetZone:getPoint()
	local B = dest 
	local A = theZone:getPoint() 
	local ingress = dcsCommon.pointXpercentYdegOffAB(A, B, math.random(50,80), math.random(20,50))
	local omwWP = dcsCommon.createSimpleRoutePointData(ingress, theZone.alt, theZone.speed)
	dcsCommon.addRoutePointForGroupData(gData, omwWP)
	
	-- action waypoint
	local awp = milWings.createActionWaypoint(theZone, targetZone)
	dcsCommon.addRoutePointForGroupData(gData, awp)
	
	-- egress 
	local egress = dcsCommon.pointXpercentYdegOffAB(B, A, math.random(20, 50), math.random(20,50))
	local egWP = dcsCommon.createSimpleRoutePointData(egress, theZone.alt, theZone.speed)
	dcsCommon.addRoutePointForGroupData(gData, egWP)
	
	-- maybe add another to safety and then dealloc?
	local final = milWings.createCallbackWP(gData.name, 4, theZone:getPoint(), theZone.alt, theZone.speed, "delete")
	dcsCommon.addRoutePointForGroupData(gData, final)
	
	-- spawn and return 
	local cty = dcsCommon.getACountryForCoalition(theZone.coa)
	-- spawn 
	local groupCat = Group.Category.AIRPLANE
	local theSpawnedGroup = coalition.addGroup(cty, groupCat, gData)
	local theFlight = {}
	theFlight.oName = oName 
	theFlight.spawn = theSpawnedGroup
	theFlight.origin = theZone 
	theFlight.destination = targetZone
	milWings.flights[gName] = theFlight --theSpawnedGroup
	return theSpawnedGroup, gData 
end 

--
-- Update
--
function milWings.update()
	timer.scheduleFunction(milWings.update, {}, timer.getTime() + 1)
	-- update all master owners 
	for idx, theZone in pairs (milWings.zones) do 
		local mo = theZone.masterOwner
		if mo then 
			theZone.owner = mo.owner
			if theZone.isDynamic then
				theZone.coa = mo.owner 
			end 
			if theZone.verbose then 
				trigger.action.outText("Copied master onwer <" .. mo.owner .. "> from <" .. mo.name .. "> to <" .. theZone.name .. ">", 30)
			end 
		end
	end
	
	for idx, theZone in pairs (milWings.targets) do 
		local mo = theZone.masterOwner
		if mo then 
			theZone.owner = mo.owner
			if theZone.verbose then 
				trigger.action.outText("Copied master onwer <" .. mo.owner .. "> from <" .. mo.name .. "> to <" .. theZone.name .. ">", 30)
			end 
		end
	end
	
end

--
-- Event Handler
--
function milWings:onEvent(theEvent)
	if not theEvent then return end 
	if not theEvent.initiator then return end 
	local theUnit = theEvent.initiator 
	if not theUnit.getGroup then return end 
	local theGroup = theUnit:getGroup()
	if not theGroup then return	end
	local gName = theGroup:getName()
	if not gName then return end 
	local theFlight = milWings.flights[gName]
	if not theFlight then return end -- none of ours 
	
	local id = theEvent.id 
	if id == 4 then 
		-- flight landed -- milFlights currently do not land
		-- except later transport flights -- we'll deal with those 
		-- later 
	
--		trigger.action.outText("+++milW: flight <> landed (and removed)", 30)
		if Group.isExist(theGroup) then 
			-- maybe schedule in a few seconds?
			Group.destroy(theGroup)
		end 
	end -- if landed 
end
--
-- callback from the flight 
--
function milWings.inFlightCB(gName)
--	trigger.action.outText("*****===***** callback in-flight for group <" .. gName .. ">", 30)
	local theGroup = Group.getByName(gName)
	if theGroup and Group.isExist(theGroup) then Group.destroy(theGroup) end 
 end

--
-- GC
--
function milWings.GCcollected(gName)
	-- do some housekeeping?
	if milWings.verbose then 
		trigger.action.outText("removed MIL flight <" .. gName .. ">", 30)
	end 
end

function milWings.GC()
	timer.scheduleFunction(milWings.GC, {}, timer.getTime() + 5)
	local filtered = {}
	for gName, theFlight in pairs(milWings.flights) do 
		local theGroup = Group.getByName(gName)
		if theGroup and Group.isExist(theGroup) then 
			-- all fine, keep it
			filtered[gName] = theFlight
		else 
			milWings.GCcollected(gName)
		end 
	end
	milWings.flights = filtered
end

--
-- API
--
function milWings.getMilWingSources(side, msnType) -- msnType is optional
	if side == "red" then side = 1 end -- better safe...
	if side == "blue" then side = 2 end 
	local sources = {}
	for idx, theZone in pairs(milWings.zones) do 
		if theZone.coa == side then -- coa must be same side, use masterOwner for dynamism
			if msnType then 
				if theZone.msnType == msnType then 
					table.insert(sources, theZone)
				end
			else 
				table.insert(sources, theZone)
			end
		end
	end
	return sources -- an array, NOT dict so we can pickrandom
end

function milWings.getMilWingTargets(side, msnType, ignoreNeutral, pure) -- gets mil targets that DO NOT belong to side 
-- enter with side = -1 to get all 
	local source = milWings.targets
	if pure then source = milWings.pureTargets end 
	if side == "red" then side = 1 end -- better safe...
	if side == "blue" then side = 2 end 
	local tgt = {}
	for idx, theZone in pairs(source) do 
		if theZone.owner ~= side then -- must NOT be owned by same side 
			if ignoreNeutral and theZone.owner == 0 then
				-- neutral ignored
			else
				-- now see if we need to filter by zone's msnType 
				if msnType then
					if theZone.wingTypes and dcsCommon.arrayContainsStringCaseInsensitive(theZone.wingTypes, msnType) then 
						table.insert(tgt, theZone)
					end 
				else 
					table.insert(tgt, theZone)
				end 
			end 
		end
	end
	return tgt
end

--
-- config 
--
function milWings.readConfigZone()
	local theZone = cfxZones.getZoneByName("milWingsConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("milWingsConfig") 
	end 
	milWings.verbose = theZone.verbose 

end

--
-- Start 
--
function milWings.start()
-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx mil wings requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx mil wings", milWings.requiredLibs) then
		return false 
	end
	
	-- read config 
	milWings.readConfigZone()
	
	-- process milWings Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("milWings")
	for k, aZone in pairs(attrZones) do 
		milWings.readMilWingsZone(aZone) -- process attributes
		milWings.addMilWingsZone(aZone) -- add to list
	end
	
	for idx, keyWord in pairs(milWings.targetKeywords) do 
		attrZones = cfxZones.getZonesWithAttributeNamed(keyWord)
		for k, aZone in pairs(attrZones) do 
			milWings.readMilWingsTargetZone(aZone) -- process attributes
			milWings.addMilWingsTargetZone(aZone) -- add to list
		end
	end 
	
	-- start update in 5 seconds
	timer.scheduleFunction(milWings.update, {}, timer.getTime() + 1/milWings.ups)
	
	timer.scheduleFunction(milWings.GC, {}, timer.getTime() + 1/milWings.ups * 5)
	-- install event handler 
	world.addEventHandler(milWings)
	
	-- say hi 
	trigger.action.outText("milWings v" .. milWings.version .. " started.", 30)
	return true 
end

if not milWings.start() then 
	trigger.action.outText("milWings failed to start.", 30)
	milWings = nil 
end 
