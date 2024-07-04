milHelo = {}
milHelo.version = "1.0.2"
milHelo.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
	"cfxMX",
}
milHelo.zones = {}
milHelo.targetKeywords = {
	"milTarget", -- my own zone
	"camp", -- camps 
	"airfield", -- airfields
	"FARP", -- FARPzones 
	}
	
milHelo.targets = {}
milHelo.flights = {} -- all currently active mil helo flights 
milHelo.ups = 1 
milHelo.missionTypes = {
	"cas", -- standard cas 
	"patrol", -- orbit over zone for duration 
	"insert", -- insert one of the ground groups in the src zone after landing
	"casz", -- engage in zone for target zone's radius 	
	-- missing csar
}

function milHelo.addMilHeloZone(theZone)
	milHelo.zones[theZone.name] = theZone
end 

function milHelo.addMilTargetZone(theZone)
	milHelo.targets[theZone.name] = theZone -- overwrite if duplicate
end
--[[--
function milHelo.partOfGroupDataInZone(theZone, theUnits) -- move to mx?
	--local zP --= cfxZones.getPoint(theZone)
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

function milHelo.allGroupsInZoneByData(theZone) -- move to MX?
	local theGroupsInZone = {}
	local count = 0
	for groupName, groupData in pairs(cfxMX.groupDataByName) do 
		if groupData.units then 
			if milHelo.partOfGroupDataInZone(theZone, groupData.units) then 
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
--]]--

function milHelo.readMilHeloZone(theZone) -- process attributes
	-- get mission type. part of milHelo 
	theZone.msnType = string.lower(theZone:getStringFromZoneProperty("milHelo", "cas")) 
	if dcsCommon.arrayContainsString(milHelo.missionTypes, theZone.msnType) then 
		-- great, mission type is known
	else 
		trigger.action.outText("+++milH: zone <" .. theZone.name .. ">: unknown mission type <" .. theZone.msnType .. ">, defaulting to 'CAS'", 30)
		theZone.msnType = "cas"
	end 
	
	-- see if our ownership is tied to a master
	-- adds dynamic coalition capability
	if theZone:hasProperty("masterOwner") then 
		local mo = theZone:getStringFromZoneProperty("masterOwner")
		local mz = cfxZones.getZoneByName(mo)
		if not mz then 
			trigger.action.outText("+++milH: WARNING: Master Owner <" .. mo .. "> for zone <" .. theZone.name .. "> does not exist!", 30)
		else 
			theZone.masterOwner = mz 
		end
		theZone.isDynamic = theZone:getBoolFromZoneProperty("dynamic", true)
	end
	
	-- get all groups inside me	
	local myGroups, count = cfxMX.allGroupsInZoneByData(theZone) 
	theZone.myGroups = myGroups 
	theZone.groupCount = count 
	theZone.hGroups = {}
	theZone.hCount = 0 
	theZone.gGroups = {}
	theZone.gCount = 0 
	theZone.fGroups = {}
	theZone.fCount = 0 
	-- sort into ground, helo and fixed 
	for groupName, data in pairs(myGroups) do 
		local catRaw = cfxMX.groupTypeByName[groupName]
		if theZone.verbose then 
			trigger.action.outText("Proccing zone <" .. theZone.name .. ">: group <" .. groupName .. "> - type <" .. catRaw .. ">", 30)
		end 
		if catRaw == "helicopter" then 
			theZone.hGroups[groupName] = data
			theZone.hCount = theZone.hCount + 1
		elseif catRaw == "plane" then 
			theZone.fGroups[groupName] = data 
			theZone.fCount = theZone.fCount +  1
		elseif catRaw == "vehicle" then 
			theZone.gGroups[groupName] = data 
			theZone.gCount = theZone.gCount + 1
		else 
			trigger.action.outText("+++milH: ignored group <" .. groupName .. ">: unknown type <" .. catRaw .. ">", 30)
		end 
	end 
	theZone.coa = theZone:getCoalitionFromZoneProperty("coalition", 0)
	theZone.hot = theZone:getBoolFromZoneProperty("hot", false) 
	theZone.speed = theZone:getNumberFromZoneProperty("speed", 50) -- 110 mph
	theZone.alt = theZone:getNumberFromZoneProperty("alt", 100) -- we are always radar alt 
	theZone.loiter = theZone:getNumberFromZoneProperty("loiter", 3600) -- 1 hour loiter default 
	-- wipe all existing 
	for groupName, data in pairs(myGroups) do 
		local g = Group.getByName(groupName) 
		if g then 
			Group.destroy(g)
		end 
	end 
	if theZone.verbose or milHelo.verbose then 
		trigger.action.outText("+++milH: processed milHelo zone <" .. theZone.name .. ">", 30)
	end
end 

function milHelo.readMilTargetZone(theZone)
	-- can also be "camp", "farp", "airfield"
	theZone.casRadius = theZone:getNumberFromZoneProperty("casRadius", theZone.radius)
	if (not theZone.isCircle) and not theZone:hasProperty("casRadius") then
		-- often when we have a camp there is no cas radius, use 10km 
		-- and zone is ploygonal 
		if theZone.verbose then 
			trigger.action.outText("+++milH: Warning - milH target zone <" .. theZone.name .. "> is polygonal and has no CAS radius attribute. Defaulting to 10km", 30)
		end 
		theZone.casRadius = 10000
	end 
	if theZone.verbose or milHelo.verbose then 
		trigger.action.outText("+++milH: processed milHelo TARGET zone <" .. theZone.name .. ">", 30)
	end
end 

--
-- Spawning for a zone
--

function milHelo.createCASTask(num, auto)
	if not auto then auto = false end 
	if not num then num = 1 end 
	local task = {}
	task.number = num 
	task.key = "CAS"
	task.id = "EngageTargets"
	task.enabled = true 
	task.auto = auto 
	local params = {}
	params.priority = 0 
	local targetTypes = {[1] = "Helicopters", [2] = "Ground Units", [3] = "Light armed ships",}
	params.targetTypes = targetTypes
	
	task.params = params 
	return task 
end

function milHelo.createROETask(num, roe)
	if not num then num = 1 end 
	if not roe then roe = 0 end 
	local task = {}
	task.number = num 
	task.enabled = true 
	task.auto = false 
	task.id = "WrappedAction"
	local params = {}
	local action = {}
	action.id = "Option"
	local p2 = {}
	p2.value = roe -- 0 = Weapons free 
	p2.name = 0 -- name 0 = ROE 
	action.params = p2 
	params.action = action 
	task.params = params
	return task 
end 

function milHelo.createEngageIZTask(num, theZone)
--	trigger.action.outText("Creating engage in zone task for zone <" .. theZone.name .. ">, marking on map", 30)
--	theZone:drawZone()
--	theZone:drawText("casz - " .. theZone.name, 20)
	local p = theZone:getPoint()
	if not num then num = 1 end 
	local task = {}
		task.number = num 
		task.enabled = true 
		task.auto = false 
		task.id = "EngageTargetsInZone"
		local params = {}
			targetTypes = {}
				targetTypes[1] = "All"
			params.targetTypes = targetTypes
			params.x = p.x 
			params.y = p.z -- !!!!
			params.value = "All;"
			params.noTargetTypes = {}
			params.priority = 0
			local radius = theZone.casRadius
			params.zoneRadius = radius 
		task.params = params 
	return task
end

function milHelo.createOrbitTask(num, duration, theZone)
	if not num then num = 1 end 
	local task = {}
	task.number = num 
	task.auto = false 
	task.id = "ControlledTask"
	task.enabled = true 
		local params = {}
			local t2 = {}
			t2.id = "Orbit"
			local p2 = {}
				p2.altitude = theZone.alt 
				p2.pattern = "Circle"
				p2.speed = theZone.speed 
				p2.altitudeEdited = true 
			t2.params = p2 
		params.task = t2 
		params.stopCondition = {}
		params.stopCondition.duration = duration
	task.params = params
	return task 
end

function milHelo.createLandTask(p, duration, num) 
	if not num then num = 1 end 
	local t = {}
	t.enabled = true 
	t.auto = false 
	t.id = "ControlledTask"
	t.number = num 
	local params = {}
	t.params = params 
	local ptsk = {}
	params.task = ptsk 
	ptsk.id = "Land"
	local ptp = {}
	ptsk.params = ptp
	ptp.x = p.x 
	ptp.y = p.z 
	ptp.duration = "300" -- not sure why 
	ptp.durationFlag = false -- off anyway 
	local stopCon = {}
	stopCon.duration = duration
	params.stopCondition = stopCon 
	return t 
end

function milHelo.createCommandTask(theCommand, num) 
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

function milHelo.createTakeOffWP(theZone, engageInZone, engageZone, ROE)
	if not ROE then ROE = 0 end -- wepons free 
	local WP = {}
	WP.alt = 500 -- theZone.alt 
	WP.alt_type = "BARO" 
	WP.properties = {}
	WP.properties.addopt = {}
	WP.action = "From Ground Area"
	if theZone.hot then WP.action = "From Ground Area Hot" end 
	WP.speed = 0 -- theZone.speed 
	WP.task = {}
	WP.task.id = "ComboTask"
	WP.task.params = {}
	local tasks = {}
	local casTask = milHelo.createCASTask(1)
	tasks[1] = casTask 
	local roeTask = milHelo.createROETask(2,ROE) -- 0 = weapons free, 4 = weapon hold 
	tasks[2] = roeTask 
	if engageInZone then 
		if not engageZone then 
			trigger.action.outText("+++milH: Warning - caz task with no engage zone!", 30)
		end 
		local eiz = milHelo.createEngageIZTask(3, engageZone)
		tasks[3] = eiz 
	end
	WP.task.params.tasks = tasks 
	--
	WP.type = "TakeOffGround"
	if theZone.hot then WP.type = "TakeOffGroundHot" end 
	p = theZone:getPoint()
	WP.x = p.x 
	WP.y = p.z 
	WP.ETA = 0 
	WP.ETA_locked = true 
	WP.speed_locked = true 
	WP.formation_template = ""
	return WP
end



function milHelo.createOrbitWP(theZone, targetPoint)
	local WP = {}
	WP.alt = theZone.alt 
	WP.alt_type = "RADIO"
	WP.properties = {}
	WP.properties.addopt = {}
	WP.action = "Turning Point"
	WP.speed = theZone.speed 
	WP.task = {}
	WP.task.id = "ComboTask"
	WP.task.params = {}
	-- start params construct 
	local tasks = {}
	local casTask = milHelo.createCASTask(1)
	tasks[1] = casTask 
	local oTask = milHelo.createOrbitTask(2, theZone.loiter, theZone)
	tasks[2] = oTask 
	WP.task.params.tasks = tasks 
	WP.type = "Turning Point"

	WP.x = targetPoint.x 
	WP.y = targetPoint.z 
	WP.ETA = 0 
	WP.ETA_locked = false 
	WP.speed_locked = true 
	WP.formation_template = ""
	return WP
end

function milHelo.createLandWP(gName, theZone, targetZone)
	local toWP 
	toWP = dcsCommon.createSimpleRoutePointData(targetZone:getPoint(), theZone.alt, theZone.speed)
	toWP.alt_type = "RADIO"

	local task = {}
	task.id = "ComboTask"
	task.params = {}
	local ttsk = {} 
	local p = targetZone:getPoint()
	ttsk[1] = milHelo.createLandTask(p, milHelo.landingDuration, 1)
	local command = "milHelo.landedCB('" .. gName .. "', '" .. targetZone:getName() .. "', '" .. theZone:getName() .. "')"
	ttsk[2] = milHelo.createCommandTask(command,2)
	task.params.tasks = ttsk
	toWP.task = task 	
	return toWP 
end 

function milHelo.createOMWCallbackWP(gName, number, pt, alt, speed, action, ROE) -- name is group name
	if not action then action = "none" end 
	local omwWP = dcsCommon.createSimpleRoutePointData(pt, alt, speed)
	omwWP.alt_type = "RADIO"
	-- create a command waypoint
	local task = {}
	task.id = "ComboTask"
	task.params = {}
	local ttsk = {} 
	local command = "milHelo.reachedWP('" .. gName .. "', '" .. number .. "', '" .. action .."')"
	ttsk[1] = milHelo.createCommandTask(command,1)
	if ROE then 
		ttsk[2] = milHelo.createROETask(2, ROE)
	end 
	task.params.tasks = ttsk
	omwWP.task = task 	
	return omwWP
end

	
function milHelo.spawnForZone(theZone, targetZone)
	-- note that each zone only has a single msnType, so zone 
	-- defines msn type 
	local n = dcsCommon.randomBetween(1, theZone.hCount)
	local theRawData = dcsCommon.getNthItem(theZone.hGroups, n)
	local gData = dcsCommon.clone(theRawData)
	local oName = gData.name 
	gData.lateActivation = false
	
	-- pre-process gData: names, id etc
	gData.name = dcsCommon.uuid(gData.name)
	local gName = gData.name 
	for idx, uData in pairs(gData.units) do 
		uData.name = dcsCommon.uuid(uData.name)
		uData.alt = 10
		uData.alt_type = "RADIO"
		uData.speed = 0 
		uData.unitId = nil 
	end
	gData.groupId = nil 
	
	-- change task according to missionType in Zone
	-- we currently use CAS for all 
	gData.task = "CAS"
	
	-- create and process route 
	local route = {}
	route.points = {}
	gData.route = route 
	-- create take-off waypoint 
	local casInZone = theZone.msnType == "casz"
	if theZone.verbose and casInZone then 
		trigger.action.outText("Setting up casZ for <" .. theZone.name .. "> to <" .. targetZone.name .. ">", 30)
	end 
	
	local wpTOff = milHelo.createTakeOffWP(theZone, casInZone, targetZone) -- no ROE = weapons free

	-- depending on mission, create an orbit or land WP 
	local dest = targetZone:getPoint()
	local B = dest 
	local A = theZone:getPoint() 
	if theZone.msnType == "cas" or theZone.msnType == "patrol" then 
		-- patrol and cas go straight to the target, they do not 
		-- have an ingress. Meaning: they have the same route 
		-- profile as 'insert' 
		wpTOff = milHelo.createTakeOffWP(theZone, casInZone, targetZone, 4) -- 4 = weapons HOLD		
		dcsCommon.addRoutePointForGroupData(gData, wpTOff) -- wp 1
		
		-- on approach, 70% at target, go weapons hot 
		local apr = dcsCommon.vLerp(A, B, 0.75)
		local omw2 = milHelo.createOMWCallbackWP(gName, 2, apr, theZone.alt, theZone.speed, "weapons free", 0) -- wp 2
		dcsCommon.addRoutePointForGroupData(gData, omw2)
		
		-- possible expandion: if cas, we have an ingress point? 
		local wpDest = milHelo.createOrbitWP(theZone, dest)
		dcsCommon.addRoutePointForGroupData(gData, wpDest) -- wp 3
		--local retPt = milHelo.createLandWP(gName, theZone, theZone)
		--dcsCommon.addRoutePointForGroupData(gData, retPt)
		local retpt = theZone:getPoint()
		local omw4 = milHelo.createOMWCallbackWP(gName, 4, retpt, theZone.alt, theZone.speed, "remove")
		dcsCommon.addRoutePointForGroupData(gData, omw4) -- wp 4
	elseif theZone.msnType == "casz" then 
		wpTOff = milHelo.createTakeOffWP(theZone, casInZone, targetZone, 4) -- 4 = ROE weapons hold 
		dcsCommon.addRoutePointForGroupData(gData, wpTOff) -- wp 1
		-- go to CAS destination with Engage in Zone active 
		-- we may want to make ingress and egress wp before heading to 
		-- the 'real' CASZ point 
		-- make ingress point, in direction of target, 30 degrees to the right, half distance.
		local ingress = dcsCommon.pointXpercentYdegOffAB(A, B, math.random(50,80), math.random(20,50))
		--local pt = targetZone:getPoint()
		local omw1 = milHelo.createOMWCallbackWP(gName, 2, ingress, theZone.alt, theZone.speed, "weapons free", 0) -- wp 2
		dcsCommon.addRoutePointForGroupData(gData, omw1)
		local omw2 = milHelo.createOMWCallbackWP(gName, 3, B, theZone.alt, theZone.speed, "none")
		dcsCommon.addRoutePointForGroupData(gData, omw2) -- wp 3
		-- egress point 
		local egress = dcsCommon.pointXpercentYdegOffAB(B, A, math.random(20, 50), math.random(20,50))
		local omw3 = milHelo.createOMWCallbackWP(gName, 4, egress, theZone.alt, theZone.speed, "none")
		dcsCommon.addRoutePointForGroupData(gData, omw3) -- wp 4
		-- return to aerodrome, deallocate 
		local retpt = theZone:getPoint()
		local omw4 = milHelo.createOMWCallbackWP(gName, 5, retpt, theZone.alt, theZone.speed, "remove")
		dcsCommon.addRoutePointForGroupData(gData, omw4) -- wp 5

	elseif theZone.msnType == "insert" then 
		local wpDest = milHelo.createLandWP(gName, theZone, targetZone)
		dcsCommon.addRoutePointForGroupData(gData, wpTOff) -- wp 1
		dcsCommon.addRoutePointForGroupData(gData, wpDest) -- wp 2
		-- will land and dealloc there after spawning troops
	end 
	
	-- make coa a cty 
	if theZone.coa == 0 then 
		trigger.action.outText("+++milH: WARNING - zone <" .. theZone.name .. "> is NEUTRAL", 30)
	end 
	local cty = dcsCommon.getACountryForCoalition(theZone.coa)
	-- spawn 
	local groupCat = Group.Category.HELICOPTER
	local theSpawnedGroup = coalition.addGroup(cty, groupCat, gData)
	local theFlight = {}
	theFlight.oName = oName 
	theFlight.spawn = theSpawnedGroup
	theFlight.origin = theZone 
	theFlight.destination = targetZone
	milHelo.flights[gName] = theFlight --theSpawnedGroup
	return theSpawnedGroup, gData 
end
--
-- mil helo landed callback (insertion)
--
function milHelo.insertTroops(theUnit, targetZone, srcZone)
	local theZone = srcZone 
	local n = dcsCommon.randomBetween(1, theZone.gCount)
	local theRawData = dcsCommon.getNthItem(theZone.gGroups, n)
--	local theRawData = dcsCommon.getNthItem(srcZone.gGroups, 1)
	if not theRawData then 
		trigger.action.outText("+++milH: WARNING: no troops to insert for zone <" .. srcZone.name .. ">", 30)
		return 
	end
	
	local gData = dcsCommon.clone(theRawData)
	gData.lateActivation = false -- force false 
	-- deploy in ring formation 
	-- remove all routes 
	-- mayhaps prepare for orders and formation 
	
	local p = theUnit:getPoint() 
	gData.route = nil -- no more route. stand in place 
	gData.name = dcsCommon.uuid(gData.name)
	local gName = gData.name 
	for idx, uData in pairs(gData.units) do 
		uData.name = dcsCommon.uuid(uData.name)
		uData.speed = 0 
		uData.heading = 0 
		uData.unitId = nil 
	end
	gData.groupId = nil 
	dcsCommon.moveGroupDataTo(gData, 0, 0) -- move to origin so we can arrange them 
	
	dcsCommon.arrangeGroupDataIntoFormation(gData, 20, nil, "CIRCLE_OUT")
	
	dcsCommon.moveGroupDataTo(gData, p.x, p.z) -- move arranged group to helo
	
	-- make coa a cty 
	if theZone.coa == 0 then 
		trigger.action.outText("+++milH: WARNING - zone <" .. theZone.name .. "> is NEUTRAL", 30)
	end 
	local cty = dcsCommon.getACountryForCoalition(theZone.coa)
	-- spawn 
	local groupCat = Group.Category.GROUND
	local theSpawnedGroup = coalition.addGroup(cty, groupCat, gData)
		
	--trigger.action.outText("Inserted troops <" .. gName .. ">", 30)
	
	return theSpawnedGroup, gData 
end

function milHelo.replaceUnitsWithStatics(gName)

end

function milHelo.getRawDataFromGroupNamed(gName, oName)
	local theGroup = Group.getByName(gName)
	local groupName = gName
	local cat = theGroup:getCategory()
	-- access mxdata for livery because getDesc does not return the livery 	
	local liveries = {} 
	local mxData = cfxMX.getGroupFromDCSbyName(oName)
	for idx, theUnit in pairs (mxData.units) do 
		liveries[theUnit.name] = theUnit.livery_id
	end 
	
	local ctry
	local gID = theGroup:getID()
	local allUnits = theGroup:getUnits()
	local rawGroup = {}
	rawGroup.name = groupName
	local rawUnits = {}
	for idx, theUnit in pairs(allUnits) do 
		local ir = {}
		local unitData = theUnit:getDesc()
		-- build record 
		ir.heading = dcsCommon.getUnitHeading(theUnit)
		ir.name = theUnit:getName()
		ir.type = unitData.typeName -- warning: fields are called differently! typename vs type
		ir.livery_id = liveries[ir.name] -- getDesc does not return livery
		ir.groupId = gID
		ir.unitId = theUnit:getID()
		local up = theUnit:getPoint()
		ir.x = up.x
		ir.y = up.z -- !!! warning! 
		-- see if any zones are linked to this unit 
		ir.linkedZones = cfxZones.zonesLinkedToUnit(theUnit)
		
		table.insert(rawUnits, ir)
		ctry = theUnit:getCountry()
	end
	rawGroup.ctry = ctry 
	rawGroup.cat = cat 
	rawGroup.units = rawUnits 
	return rawGroup, cat, ctry
end

function milHelo.spawnImpostorsFromData(rawData, cat, ctry) 
	for idx, unitData in pairs(rawData.units) do 
		-- build impostor record 
		local ir = {}
		ir.heading = unitData.heading
		ir.type = unitData.type
		ir.name = dcsCommon.uuid(rawData.name) -- .. "-" .. tostring(impostors.uniqueID())
		ir.groupID = nil -- impostors.uniqueID()
		ir.unitId = nil -- impostors.uniqueID()
		ir.x = unitData.x
		ir.y = unitData.y 
		ir.livery_id = unitData.livery_id		
		-- spawn the impostor 
		local theImp = coalition.addStaticObject(ctry, ir)
	end
end

function milHelo.reachedWP(gName, wpNum, action)
	if not action then action = "NIL" end 
	if milHelo.verbose then 
		trigger.action.outText("MilH group  <" .. gName .. " reached wp #" .. wpNum .. " with action <" .. action .. ">.", 30)
	end 
	if action == "remove" then 
		theGroup = Group.getByName(gName)
		if theGroup and Group.isExist(theGroup) then 
			if milHelo.verbose then 
				trigger.action.outText("%%%%%%%%%% removing mil hel <" .. gName .. ">", 30)
			end 
			Group.destroy(theGroup)
		end 
	end

end 

function milHelo.landedCB(who, where, from) -- who group name, where a zone
--	trigger.action.outText("milhelo landed CB for group <" .. who .. ">", 30)
	-- step 1: remove the flight
	local theGroup = Group.getByName(who)
	if theGroup then 
		if Group.isExist(theGroup) then 
			Group.destroy(theGroup)
		end 
	else 
		trigger.action.outText("+++milH: cannot find group <" .. who .. ">", 30)
	end 
		
	-- step 3: replace with static helo 
	local aGroup = theGroup
	local theFlight = milHelo.flights[who]
	local oName = theFlight.oName 
	local theZone = theFlight.origin
	-- note: "insertion" is probably wrong, remove in line below  
	if theZone.msnType == "insertion" or theZone.msnType == "insert" then 
		-- create a static stand-in for scenery 
		local rawData, cat, ctry = milHelo.getRawDataFromGroupNamed(who, oName)
		Group.destroy(aGroup)
		milHelo.spawnImpostorsFromData(rawData, cat, ctry) 
	else 
		-- remove group 
		Group.destroy(aGroup)	
	end
	
	-- remove flight from list of active flights 
	milHelo.flights[who] = nil 
end

--
-- update and event 
--
function milHelo.update()
	timer.scheduleFunction(milHelo.update, {}, timer.getTime() + 1/milHelo.ups)
	-- update all master owners 
	for idx, theZone in pairs (milHelo.zones) do 
		local mo = theZone.masterOwner
		if mo then 
			theZone.owner = mo.owner
			if theZone.isDynamic then
				theZone.coa = mo.owner 
			end 
		end
	end
	
end

function milHelo.GCcollected(gName)
	-- do some housekeeping?
	if milHelo.verbose then 
		trigger.action.outText("removed flight <" .. gName .. ">", 30)
	end 
end

function milHelo.GC()
	timer.scheduleFunction(milHelo.GC, {}, timer.getTime() + 1)
	local filtered = {}
	for gName, theFlight in pairs(milHelo.flights) do 
		local theGroup = Group.getByName(gName)
		if theGroup and Group.isExist(theGroup) then 
			-- all fine, keep it
			filtered[gName] = theFlight
		else 
			milHelo.GCcollected(gName)
		end 
	end
	milHelo.flights = filtered
end

function milHelo:onEvent(theEvent)
	if not theEvent then return end 
	if not theEvent.initiator then return end 
	local theUnit = theEvent.initiator 
	if not theUnit.getGroup then return end 
	local theGroup = theUnit:getGroup()
	if not theGroup then 
--		trigger.action.outText("event <" .. theEvent.id .. ">: group shenenigans for unit detected", 30)
		return 
	end
	local gName = theGroup:getName()
	local theFlight = milHelo.flights[gName]
	if not theFlight then return end 

	local id = theEvent.id 
	if id == 4 then 
		-- flight landed
		-- did it land in target zone? 
		local p = theUnit:getPoint()
		local srcZone = theFlight.origin
		local tgtZone = theFlight.destination 
		if tgtZone:pointInZone(p) then 
			trigger.action.outText("Flight <" .. gName .. "> originating from <" .. srcZone.name .. "> landed in zone <" .. tgtZone.name .. ">", 30) 
			if srcZone.msnType == "insert" then 
				trigger.action.outText("Commencing Troop Insertion", 30)
				milHelo.insertTroops(theUnit, tgtZone, srcZone)
			end
		else
			-- maybe its a return flight 
			if srcZone:pointInZone(p) then 
--				trigger.action.outText("Flight <" .. gName .. "> originating from <" .. srcZone.name .. "> landed back home", 30) 
			else 
--				trigger.action.outText("Flight <" .. gName .. "> originating from <" .. srcZone.name .. "> landed OUTSIDE of src or target zone <" .. tgtZone.name .. ">, clearing.", 30) 
			end
				-- remove it now
			local theGroup = Group.getByName(gName)
			if theGroup and Group.isExist(theGroup) then 
				Group.destroy(theGroup)
			end
					
		end 
	end 
	
--	trigger.action.outText("Event <" .. theEvent.id .. "> for milHelo flight <" .. gName .. ">", 30)
end

--
-- API
--
function milHelo.getMilSources(side, msnType) -- msnType is optional
	if side == "red" then side = 1 end -- better safe...
	if side == "blue" then side = 2 end 
	local sources = {}
	for idx, theZone in pairs(milHelo.zones) do 
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

function milHelo.getMilTargets(side, ignoreNeutral) -- gets mil targets that DO NOT belong to side 
	if side == "red" then side = 1 end -- better safe...
	if side == "blue" then side = 2 end 
	local tgt = {}
	for idx, theZone in pairs(milHelo.targets) do 
		-- we use OWNER, not COA here!
		if theZone.owner ~= side then -- must NOT be owned by same side 
			if ignoreNeutral and theZone.owner == 0 then
			else
				table.insert(tgt, theZone)
				--trigger.action.outText("zone <" .. theZone.name .. "> owned by <" .. theZone.owner .. "> is possible target for coa <" .. side .. ">", 30)
			end 
		end
	end
	return tgt
end
--
-- Config & start 
--
function milHelo.readConfigZone()
	local theZone = cfxZones.getZoneByName("milHeloConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("milHeloConfig") 
	end 
	milHelo.verbose = theZone.verbose 
	milHelo.landingDuration = theZone:getNumberFromZoneProperty("landingDuration", 180) -- seconds = 3 minutes
	milHelo.ups = theZone:getNumberFromZoneProperty("ups", 1)
end

		
function milHelo.start()
-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx mil helo requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx mil helo", milHelo.requiredLibs) then
		return false 
	end
	
	-- read config 
	milHelo.readConfigZone()
	
	-- process milHelo Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("milHelo")
	for k, aZone in pairs(attrZones) do 
		milHelo.readMilHeloZone(aZone) -- process attributes
		milHelo.addMilHeloZone(aZone) -- add to list
	end
	
	for idx, keyWord in pairs(milHelo.targetKeywords) do 
		attrZones = cfxZones.getZonesWithAttributeNamed(keyWord)
		for k, aZone in pairs(attrZones) do 
			milHelo.readMilTargetZone(aZone) -- process attributes
			milHelo.addMilTargetZone(aZone) -- add to list
		end
	end 
	
	-- start update in 5 seconds
	timer.scheduleFunction(milHelo.update, {}, timer.getTime() + 1/milHelo.ups)
	
	-- start GC 
	milHelo.GC()
	 
	-- install event handler 
	world.addEventHandler(milHelo)
	
	-- say hi 
	trigger.action.outText("milHelo v" .. milHelo.version .. " started.", 30)
	return true 
end

if not milHelo.start() then 
	trigger.action.outText("milHelo failed to start.", 30)
	milHelo = nil 
end 

--[[
function milHelo.latestuff()
	trigger.action.outText("doing stuff", 30)
	local theZone = cfxZones.getZoneByName("milCAS") --dcsCommon.getFirstItem(milHelo.zones)
	local targetZone = cfxZones.getZoneByName("mh Target")  -- dcsCommon.getFirstItem(milHelo.targets)
	milHelo.spawnForZone(theZone, targetZone)
	theZone = cfxZones.getZoneByName("milInsert")  --dcsCommon.getNthItem(milHelo.zones, 2)
	milHelo.spawnForZone(theZone, targetZone)
	theZone = cfxZones.getZoneByName("doCASZ") 
	targetZone = cfxZones.getZoneByName("milTarget Z")
	if not theZone then trigger.action.outText("Not theZone", 30) end 
	if not targetZone then trigger.action.OutText("Not targetZone", 30) end 
	milHelo.spawnForZone(theZone, targetZone)
end

-- do some one-time stuff 
timer.scheduleFunction(milHelo.latestuff, {}, timer.getTime() + 1)
--]]--
