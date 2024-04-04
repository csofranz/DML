milHelo = {}
milHelo.version = "0.0.0"
milHelo.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
	"cfxMX",
}
milHelo.zones = {}
milHelo.targets = {}
milHelo.ups = 1 

function milHelo.addMilHeloZone(theZone)
	milHelo.zones[theZone.name] = theZone
end 

function milHelo.addMilTargetZone(theZone)
	milHelo.targets[theZone.name] = theZone 
end

function milHelo.partOfGroupDataInZone(theZone, theUnits) -- move to mx?
	local zP = cfxZones.getPoint(theZone)
	zP = theZone:getDCSOrigin() -- don't use getPoint now.
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

function milHelo.readMilHeloZone(theZone) -- process attributes
	-- get mission type. part of milHelo 
	theZone.msnType = string.lower(theZone:getStringFromZoneProperty("milHelo", "cas"))
	-- get all groups inside me	
	local myGroups, count = milHelo.allGroupsInZoneByData(theZone) 
	theZone.myGroups = myGroups 
	theZone.groupCount = count 
	theZone.coa = theZone:getCoalitionFromZoneProperty("coalition", 0)
	theZone.hot = theZone:getBoolFromZoneProperty("hot", true) 
	theZone.speed = theZone:getNumberFromZoneProperty("speed", 50) -- 110 mph
	theZone.alt = theZone:getNumberFromZoneProperty("alt", 100) -- we are always radar alt 
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

	if theZone.verbose or milHelo.verbose then 
		trigger.action.outText("+++milH: processed TARGET zone <" .. theZone.name .. ">", 30)
	end
end 

--
-- Spawning for a zone
--
--[[--
function milHelo.getNthItem(theSet, n)
	local count = 1 
	for key, value in pairs(theSet) do
		if count == n then return value end 
		count = count + 1 
	end
	return nil 
end
--]]--

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
--	params.targetTypes = {"Helicopters", "Ground Units", "Light armed ships"}
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

function milHelo.createTakeOffWP(theZone)
	local WP = {}
	WP.alt = theZone.alt 
	WP.alt_type = "RADIO" 
	WP.properties = {}
	WP.properties.addopt = {}
	WP.action = "From Ground Area"
	if theZone.hot then WP.action = "From Ground Area Hot" end 
	WP.speed = theZone.speed 
	WP.task = {}
	WP.task.id = "ComboTask"
	WP.task.params = {}
	local tasks = {}
--	local casTask = milHelo.createCASTask(1)
--	tasks[1] = casTask 
	local roeTask = milHelo.createROETask(1,0) -- 0 = weapons free 
	tasks[1] = roeTask 
	WP.task.params.tasks = tasks 
	--
	WP.type = "TakeOffGround"
	if theZone.hot then WP.type = "TakeOffGroundHot" end 
	p = theZone:getPoint()
	WP.x = p.x 
	WP.y = p.z 
	WP.ETA = 0 
	WP.ETA_locked = false 
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
	local casTask = milHelo.createCASTask(1, false)
	tasks[1] = casTask 
	local oTask = milHelo.createOrbitTask(2, 3600, theZone)
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

function milHelo.spawnForZone(theZone, targetZone)
	local theRawData = dcsCommon.getNthItem(theZone.myGroups, 1)
	local gData = dcsCommon.clone(theRawData)
--[[--	
	-- pre-process gData: names, id etc
	gData.name = dcsCommon.uuid(gData.name)
	for idx, uData in pairs(gData.units) do 
		uData.name = dcsCommon.uuid(uData.name)
	end
	gData.groupId = nil 
	
	-- change task according to missionType in Zone
	gData.task = "CAS"
	
	-- create and process route 
	local route = {}
	route.points = {}
--	gData.route = route 
	-- create take-off waypoint 
	local wpTOff = milHelo.createTakeOffWP(theZone)
	-- depending on mission, create an orbit or land WP 
	local dest = targetZone:getPoint()
	local wpDest = milHelo.createOrbitWP(theZone, dest)
	-- move group to WP1 and add WP1 and WP2 to route 
--	dcsCommon.moveGroupDataTo(theGroup, 
--							  fromWP.x, 
--							  fromWP.y)

----
	dcsCommon.addRoutePointForGroupData(gData, wpTOff)
	dcsCommon.addRoutePointForGroupData(gData, wpDest)
--]]--	
	dcsCommon.dumpVar2Str("route", gData.route)
	
	-- make it a cty 
	if theZone.coa == 0 then 
		trigger.action.outText("+++milH: WARNING - zone <" .. theZone.name .. "> is NEUTRAL", 30)
	end 
	local cty = dcsCommon.getACountryForCoalition(theZone.coa)
	-- spawn 
	local groupCat = Group.Category.HELICOPTER
	local theSpawnedGroup = coalition.addGroup(cty, groupCat, gData)
	
	return theSpawnedGroup, gData 
end
--
-- update and event 
--
function milHelo.update()
	timer.scheduleFunction(milHelo.update, {}, timer.getTime() + 1)
end

function milHelo.onEvent(theEvent)

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
end

		
function milHelo.start()
-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx civ helo requires dcsCommon", 30)
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
	
	attrZones = cfxZones.getZonesWithAttributeNamed("milTarget")
	for k, aZone in pairs(attrZones) do 
		milHelo.readMilTargetZone(aZone) -- process attributes
		milHelo.addMilTargetZone(aZone) -- add to list
	end
	
	-- start update in 5 seconds
	timer.scheduleFunction(milHelo.update, {}, timer.getTime() + 1/milHelo.ups)
	
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

-- do some one-time stuff 
local theZone = dcsCommon.getFirstItem(milHelo.zones)
local targetZone = dcsCommon.getFirstItem(milHelo.targets)
milHelo.spawnForZone(theZone, targetZone)
