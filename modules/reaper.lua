reaper = {}
reaper.version = "1.3.1"
reaper.requiredLibs = {
	"dcsCommon",
	"cfxZones",  
}
--[[--
VERSION HISTORY

 1.0.0 - Initial Version 
 1.1.0 - Individual status 
	   - cycle target method
	   - cycle? attribute 
	   - restructured menus
	   - added cycle target 
	   - single status reprots full group 
	   - drones have AFAC task instead of Reconnaissance
	   - Setting enroute task for group once target spotted 
	   - compatible with Kiowa's L2MUM 
	   - (undocumented) freq attribute for drones (in MHz)
	   - completely rewrote scanning method (performance)  
	   - added FAC task 
	   - split task generation from wp generation 
	   - updated reaper naming, uniqueN	ames attribute (undocumented)
 1.2.0 - support twn when present 
 1.3.0 - new invisible option for drone zone 
 1.3.1 - slightly decreased verbosity 
 
--]]--

reaper.zones = {}-- all zones 
reaper.scanning = {} -- zones that are scanning (looking for tgt). by zone name
reaper.tracking = {} -- zones that are tracking tgt. by zone name
reaper.scanInterval = 10 -- seconds 
reaper.trackInterval = 0.3 -- seconds 
reaper.uuidCnt = 0

function reaper.uuid(instring)
	reaper.uuidCnt = reaper.uuidCnt + 1
	return instring .. "-R" .. reaper.uuidCnt
end

-- reading reaper zones 
function reaper.readReaperZone(theZone)
	theZone.myType = string.lower(theZone:getStringFromZoneProperty("reaper", "reaper"))
	if dcsCommon.stringStartsWith(theZone.myType, "pre") then theZone.myType = "RQ-1A Predator" else theZone.myType = "MQ-9 Reaper" end 
	if theZone.myType == "MQ-9 Reaper" then 
		theZone.alt = 9500 
	else theZone.alt = 7500 end theZone.alt = theZone:getNumberFromZoneProperty("alt", theZone.alt)
	theZone.freq = theZone:getNumberFromZoneProperty("freq", 133) * 1000000 -- in MHz 
	theZone.coa = theZone:getCoalitionFromZoneProperty("coalition", 2)
	if theZone.coa == 0 then 
		trigger.action.outText("+++Reap: Zone <" .. theZone.name .. "> is of coalition NEUTRAL. Switched to BLUE", 30)
		theZone.coa = 2
	end 
	theZone.enemy = dcsCommon.getEnemyCoalitionFor(theZone.coa)
	theZone.onStart = theZone:getBoolFromZoneProperty("onStart", true)
	theZone.code = theZone:getNumberFromZoneProperty("code", 1688)
	theZone.theTarget = nil 
	theZone.theSpot = nil 
	theZone.theUav = nil 
	theZone.theGroup = nil 
	theZone.doSmoke = theZone:getBoolFromZoneProperty("doSmoke", false)
	theZone.smokeColor = theZone:getSmokeColorStringFromZoneProperty("smokeColor", "red")
	theZone.smokeColor = dcsCommon.smokeColor2Num(theZone.smokeColor)
	theZone.cost = theZone:getNumberFromZoneProperty("cost", 700) -- for bank integration 
	theZone.autoRespawn = theZone:getBoolFromZoneProperty("autoRespawn", false) 
	theZone.launchUI = theZone:getBoolFromZoneProperty("launchUI", true)
	theZone.statusUI = theZone:getBoolFromZoneProperty("statusUI", true)
	theZone.uniqueNames = theZone:getBoolFromZoneProperty("uniqueNames", true) -- undocumented, leave true 
	if theZone:hasProperty("launch?") then 
		theZone.launch = theZone:getStringFromZoneProperty("launch?", "<none>")
		theZone.launchVal = theZone:getFlagValue(theZone.launch)
	end 
	if theZone:hasProperty("status?") then 
		theZone.status = theZone:getStringFromZoneProperty("status?", "<none>")
		theZone.statusVal = theZone:getFlagValue(theZone.status)
	end
	if theZone:hasProperty("cycle?") then 
		theZone.cycle = theZone:getStringFromZoneProperty("cycle?", "<none>")
		theZone.cycleVal = theZone:getFlagValue(theZone.cycle)
	end 
	theZone.invisible = theZone:getBoolFromZoneProperty("invisible", false)
	
	theZone.hasSpawned = false 
	
	if theZone.onStart then 
		reaper.spawnForZone(theZone)
	end
end

-- spawn a drone from a zone 
function reaper.spawnForZone(theZone, ack)
	-- delete any group with the same name 
	if not theZone.uniqueNames then 
		local exister = Group.getByName(theZone.name)
		if exister then Group.destroy(exister) end 
	end 
	
	-- create spawn data
	local rName
	if theZone.uniqueNames then 
		rName = reaper.uuid(theZone.name)
	else 
		rName = theZone.name
	end 
	
	local gdata = dcsCommon.createEmptyGroundGroupData (rName) -- warning: non-unique unit names, will replace previous 
	gdata.task = "AFAC"
	gdata.route = {} 
	
	-- calculate left and right 
	local p = theZone:getPoint() 
	local left, right 
	-- use dml zone bounds to get upper left and lower right 
	if theZone.isPoly then 
		left = dcsCommon.clone(theZone.bounds.ll) -- tried ll
		right = dcsCommon.clone(theZone.bounds.ur) --  
	else 
		left = dcsCommon.clone(theZone.bounds.ul)
		right = dcsCommon.clone(theZone.bounds.lr)
	end 
	gdata.x = left.x 
	gdata.y = left.z 
	gdata.frequency = theZone.freq 

	-- build the unit data
	local unit = {}
	unit.name = rName -- same as group 
	unit.x = left.x 
	unit.y = left.z 
	unit.type = theZone.myType 
	unit.skill = "High"
	if theZone.myType == "MQ-9 Reaper" then 
		unit.speed = 55
	else 
		unit.speed = 33 
	end 
	unit.alt = theZone.alt 
	
	if theZone.uniqueNames then
	else 
		if theZone.reaperGID and theZone.reaperUID then -- also re-use groupID
			gdata.groupId = theZone.reaperGID
			unit.unitId = theZone.reaperUID 
			trigger.action.outText("re-using data from old <" .. theZone.name .. ">", 30)
		end
	end 
	
	-- add to group 
	gdata.units[1] = unit 

	-- now create and add waypoints to route 
	gdata.route.points = {}
	local wp1 = reaper.createInitialWP(left, unit.alt, unit.speed, theZone.invisible)
	gdata.route.points[1] = wp1 
	local wp2 = dcsCommon.createSimpleRoutePointData(right, unit.alt, unit.speed)
	gdata.route.points[2] = wp2 
	
	-- spawn the group 
	local cty = dcsCommon.getACountryForCoalition(theZone.coa)
	local theGroup = coalition.addGroup(cty, 0, gdata)
	if not theGroup then 
		trigger.action.outText("+++Reap: failed to spawn for zone <" .. theZone.name .. ">", 30)
		return 
	end  
	theZone.reaperGID = theGroup:getID()
	theZone.reaperUID = theGroup:getUnit(1):getID() 
	if theZone.verbose or reaper.verbose then 
		trigger.action.outText("+++reap: Spawned <" .. theGroup:getName() .. "> reaper", 30)
	end
	if ack then 
		trigger.action.outTextForCoalition(theZone.coa, "Drone <" .. theZone.name .. "> on station", 30)
		trigger.action.outSoundForCoalition(theZone.coa, reaper.actionSound)
	end 
	
	reaper.cleanUp(theZone) -- dealloc anything still there
	
	theZone.theGroup = theGroup 
	local uavs = theGroup:getUnits()
	theZone.theUav = uavs[1]
	theZone.theTarget = nil 
	theZone.theSpot = nil 
	theZone.hasSpawned = true 
	reaper.scanning[theZone.name] = theZone
end

function reaper.cleanUp(theZone)
	if theZone.theUav and Unit.isExist(theZone.theUav) then 
		Unit.destroy(theZone.theUav)
	end 
	theZone.theUav = nil 
	theZone.theTarget = nil 
	theZone.theGroup = nil 
	if theZone.theSpot then 
		Spot.destroy(theZone.theSpot)
	end 
	theZone.theSpot = nil 
end

function reaper.createReaperTask(alt, speed, target, theZone, invisible)
	if not invisible then invisible = false end 
	local task = {
		["id"] = "ComboTask",
		["params"] = {
			["tasks"] = {
				[1] = {
					["number"] = 1,
					["auto"] = false,
					["id"] = "WrappedAction",
					["name"] = "INV",
					["enabled"] = true,
					["params"] = {
						["action"] = {
							["id"] = "SetInvisible",
							["params"] = {
								["value"] = invisible,
							}, -- end of ["params"]
						}, -- end of ["action"]
					}, -- end of ["params"]
				}, -- end of [1]

				[2] = {
					["enabled"] = true,
					["auto"] = true,
					["id"] = "FAC",
					["number"] = 2,
					["params"] = 
					{}, -- end of ["params"]
				}, -- end of [2]
				[3] = {
					["enabled"] = true,
					["auto"] = true,
					["id"] = "WrappedAction",
					["number"] = 3,
					["params"] = {
						["action"] = {
							["id"] = "EPLRS",
							["params"] = {
								["value"] = true,
								["groupId"] = 1, -- <- looks bad
							}, -- end of ["params"]
						}, -- end of ["action"]
					}, -- end of ["params"]
				}, -- end of [3]
				[4] = {
					["enabled"] = true,
					["auto"] = false,
					["id"] = "Orbit",
					["number"] = 4,
					["params"] = {
						["altitude"] = alt,
						["pattern"] = "Race-Track",
						["speed"] = speed,
					}, -- end of ["params"]
				}, -- end of [4]
			}, -- end of ["tasks"]
		}, -- end of ["params"]
	} -- end of ["task"]
	if theTarget and theZone then 
		local gID = theTarget:getID() -- NOTE: theTarget is a GROUP!!!!
		local task4 = { -- now task5 after we added invisibility
			["enabled"] = true,
			["auto"] = false,
			["id"] = "FAC_AttackGroup",
			["number"] = 5,
			["params"] = 
			{
				["number"] = 5,
				["designation"] = "No",
				["modulation"] = 0,
				["groupId"] = gID,
				["weaponType"] = 0, -- 9663676414,
				["frequency"] = theZone.freq, -- 133000000,
			}, -- end of ["params"]
		} -- end of [5]
		task.params.tasks[5] = task4 
	end 
	return task 
end

function reaper.createInitialWP(p, alt, speed, invisible) -- warning: target must be a GROUP 
	if not invisible then invisible = false end 
	local wp = {
		["alt"] = alt,
		["action"] = "Turning Point",
		["alt_type"] = "BARO",
		["properties"] = {
			["addopt"] = {}, -- end of ["addopt"]
		}, -- end of ["properties"]
		["speed"] = speed,
		["task"] = {}, -- will construct later 
		["type"] = "Turning Point",
		["ETA"] = 0,
		["ETA_locked"] = true,
		["y"] = p.z,
		["x"] = p.x,
		["speed_locked"] = true,
		["formation_template"] = "",
	} -- end of wp

	wp.task = reaper.createReaperTask(alt, speed, nil, nil, invisible) -- no zone, no target 
	return wp 
end

function reaper.setTarget(theZone, theTarget, cycled)
-- add a laser tracker to this unit 
	local lp = theTarget:getPoint()
	local lat, lon, alt = coord.LOtoLL(lp)
	lat, lon = dcsCommon.latLon2Text(lat, lon)
	local twnLoc = ""
	if twn and towns then 
		local name, data, dist = twn.closestTownTo(lp)
		local mdist= dist * 0.539957
		dist = math.floor(dist/100) / 10
		mdist = math.floor(mdist/100) / 10		
		local bear = dcsCommon.compassPositionOfARelativeToB(lp, data.p)
		twnLoc = " (" ..dist .. "km/" .. mdist .."nm " .. bear .. " of " .. name .. ")"
	end
	
	local theSpot = Spot.createLaser(theZone.theUav, {0, 2, 0}, lp, theZone.code)
	if theZone.doSmoke then 
		trigger.action.smoke(lp , theZone.smokeColor )
	end 
	trigger.action.outTextForCoalition(theZone.coa, "Drone <" .. theZone.name .. "> is tracking a <" .. theTarget:getTypeName() .. "> at " .. lat .. " " .. lon .. twnLoc ..", code " .. theZone.code, 30)
	trigger.action.outSoundForCoalition(theZone.coa, reaper.actionSound)
	theZone.theTarget = theTarget
	if theZone.theSpot then 
		theZone.theSpot:destroy()
	end
	theZone.theSpot = theSpot
	-- put me in track mode 
	reaper.tracking[theZone.name] = theZone		

	if cycled then return end -- cycling inside group, no new tasking 
	
	-- now make tracking the group the drone's task 
	local theGroup = theTarget:getGroup()
	local theTask = reaper.createReaperTask(theZone.alt, theZone.speed, theGroup, theZone, theZone.invisible) -- create full FAC task with orbit and group engage
	local theController = theZone.theUav:getController()
	if not theController then 
		trigger.action.outText("+++Rpr: UAV has no controller, getting group")
		return 
	end 
	theController:setTask(theTask) -- replace with longer task  
end

function reaper.selectFromDetectedTargets(visTargets, theZone)
	-- use (permanent?) detectedTargetList 
	for idx, tData in pairs(visTargets) do 
		if tData then
			local theTarget = tData.object 
			local nn = theTarget:getName()
			if not nn or nn == "" then
				if reapoer.verbose then 
					trigger.action.outText("+++reaper: shortcut on startup", 30)
				end 
				return nil 
			end  
			if theTarget and theTarget.getGroup then -- it's not a group or static object
				local d = theTarget:getDesc() 
				if d.category == 2 then 
					if theZone.verbose then 
						trigger.action.outText("+++reap: identified <" .. tData.object:getName() .. "> as target for <" .. theZone.name .. ">")
					end 
					return tData.object
				end
			end
		end
	end
	
	return nil 
end

function reaper.scanALT() -- alternative, more efficient (?) method using unit's controller 
	timer.scheduleFunction(reaper.scanALT, {}, timer.getTime() + reaper.scanInterval)
	local filtered = {}
	for name, theZone in pairs(reaper.scanning) do 
		local theUAV = theZone.theUav
		if Unit.isExist(theUAV) then 
			-- get the controller 
			local theController = theUAV:getController()
			local visTargets = theController:getDetectedTargets(1, 2) 
			local theTarget = reaper.selectFromDetectedTargets(visTargets, theZone)
			if theTarget then 
				-- add a laser tracker to this unit 
				reaper.setTarget(theZone, theTarget)
			else 
				-- will scan again next round 
				filtered[name] = theZone 
			end 
		else 
			-- does not remain
			if theZone.verbose or reaper.verbose then 
				trigger.action.outText("+++reap: drone from <" .. theZone.name .. "> no longer exists", 30)
			end 
			trigger.action.outTextForCoalition(theZone.coa, "Drone <" .. theZone.name .. "> lost.", 30)
			trigger.action.outSoundForCoalition(theZone.coa, reaper.actionSound)
			theZone.theUav = nil 
			theZone.theSpot = nil 
			theZone.theTarget = nil 
			theZone.theGroup = nil 
		end
	end 
	reaper.scanning = filtered 
end


function reaper.track()
	local filtered = {}
	for name, theZone in pairs(reaper.tracking) do 
		-- check if uav still alive 
		if Unit.isExist(theZone.theUav) then 
			if Unit.isExist(theZone.theTarget) then 
				-- update stop 
				local d = theZone.theTarget:getPoint()
				theZone.theSpot:setPoint(d)
				filtered[name] = theZone
			else 
				trigger.action.outTextForCoalition(theZone.coa, "Drone <" .. theZone.name .. "> searching for new targets", 30)
				trigger.action.outSoundForCoalition(theZone.coa, reaper.actionSound)
				if theZone.theSpot then 
					theZone.theSpot:destroy()
				end 
				theZone.theSpot = nil 
				reaper.scanning[name] = theZone -- back to scanning 
			end 
		else 
			trigger.action.outTextForCoalition(theZone.coa, "Drone <" .. theZone.name .. "> lost", 30)
			trigger.action.outSoundForCoalition(theZone.coa, reaper.actionSound)
			if theZone.theSpot then 
				theZone.theSpot:destroy()
			end 
			theZone.theSpot = nil 
			theZone.theUav = nil 
			theZone.theGroup = nil 
		end 
	end
	reaper.tracking = filtered 
	timer.scheduleFunction(reaper.track, {}, timer.getTime() + reaper.trackInterval)
end 

function reaper.cycleTarget(theZone)
	local coa = theZone.coa 
	-- try and advance to the next target 
	if not theZone.theUav or not Unit.isExist(theZone.theUav) then 
		trigger.action.outTextForCoalition(coa, "Reaper <" .. theZone.name .. "> not on station, requries launch first", 30)
		trigger.action.outSoundForCoalition(theZone.coa, reaper.actionSound)
		return 
	end 
	if not theZone.theSpot or 
	   not theZone.theUav or 
	   not theZone.theTarget then 
		trigger.action.outTextForCoalition(coa, "Reaper <" .. theZone.name .. "> is not tracking a target", 30)
		trigger.action.outSoundForCoalition(theZone.coa, reaper.actionSound)
		return 
	end 
	--when we get here, the reaper is tracking a target. get it's group 
	local theUnit = theZone.theTarget
	if not theUnit.getGroup then return end -- safety first 
	local theGroup = theUnit:getGroup() 
	local allTargets = theGroup:getUnits()
	local filtered = {}
	local i = 1
	local tIndex = 1
	-- filter and find the target with it's index 
	for idx, aTgt in pairs(allTargets) do 
		if Unit.isExist(aTgt) then 
			if theUnit == aTgt then 
				if theZone.verbose then 
					trigger.action.outText("+++ reaper <" .. theZone.target .. ">: target index found : <" .. i .. ">", 30)
				end
				tIndex = i
			end 
			table.insert(filtered, aTgt)
			i = i + 1
		end 
	end 
	
	local num = #filtered
	if num < 2 then 
		-- nothing to do, simply ack 
		trigger.action.outTextForCoalition(coa, "<" .. theZone.name .. ">: Only one target left.", 30)
		trigger.action.outSoundForCoalition(theZone.coa, reaper.actionSound)
		return 
	end 	
	
	-- increase tIndex 
	tIndex = tIndex + 1
	if tIndex > #filtered then tIndex = 1 end 
	local newTarget = filtered[tIndex]
	-- tell zone to target this new target 
	reaper.setTarget(theZone, newTarget, true) -- also outputs text and action sound, true = cycled  
end

function reaper.update()
	timer.scheduleFunction(reaper.update, {}, timer.getTime() + 1)

	-- go through all my zones, and respawn those that have no 
	-- uav but have autoRespawn active 
	for name, theZone in pairs(reaper.zones) do 
		if theZone.autoRespawn and not theZone.theUav and theZone.hasSpawned then 
			-- auto-respawn needs to kick in
			reaper.scanning[name] = nil 
			reaper.tracking[name] = nil 
			reaper.spawnForZone(theZone)
		end 
		
		if theZone.status and theZone:testZoneFlag(theZone.status, "change", "statusVal") then 
			reaper.doSingleDroneStatus(theZone)
		end 
		
		if theZone.launch and theZone:testZoneFlag(theZone.launch, "change", "launchVal") then 
			args = {}
			args[1] = theZone.coa -- = args[1]
			args[2] = name -- = args[2] 
			reaper.doLaunch(args)
		end 
		
		if theZone.cycle and theZone:testZoneFlag(theZone.cycle, "change", "cycleVal") then 
			reaper.cycleTarget(theZone)
		end 
	end
	
	-- now poll my (global) status flags 
	if reaper.blueStatus and cfxZones.testZoneFlag(reaper, reaper.blueStatus, "change", "blueStatusVal") then
		reaper.doDroneStatusBlue()
	end 
	if reaper.redStatus and cfxZones.testZoneFlag(reaper, reaper.redStatus, "change", "redStatusVal") then
		reaper.doDroneStatusRed()
	end
end 

--
-- UI
--
function reaper.installFullUIForCoa(coa)
	-- install "Drone Control" as root for red and blue 
	local mainMenu = nil 
	if reaper.mainMenu then 
		mainMenu = radioMenu.getMainMenuFor(reaper.mainMenu) -- nilling both next params will return menus[0]
	end 
	local root = missionCommands.addSubMenuForCoalition(coa, reaper.menuName, mainMenu)
	-- now install submenus 
	reaper.installDCForCoa(coa, root)
end

function reaper.installDCForCoa(coa, root)
	local filtered = {}
	for name, theZone in pairs(reaper.zones) do 
		if theZone.coa == coa and (theZone.statusUI or theZone.launchUI) then  
			filtered[name] = theZone 
		end 
	end 
	local n = dcsCommon.getSizeOfTable(filtered)
	if n > 10 then 
		trigger.action.outText("+++reap: WARNING too many (" .. n .. ") drones for coa <" .. coa .. ">", 30)
		return 
	end 
	
	for name, theZone in pairs(filtered) do 
		local mnu = theZone.name .. ": " .. theZone.myType 
		-- install menu for this drone
		local r1 = missionCommands.addSubMenuForCoalition(coa, mnu, root)
		-- install status and cycle target commands for this drone
		local args = {coa, name, }
		if theZone.launchUI then 
			mnu = "Launch " .. theZone.myType 
			if bank and reaper.useCost then 
				-- requires bank module
				mnu = mnu .. " (§" .. theZone.cost .. ")" 
			end
			local r3 = missionCommands.addCommandForCoalition(coa, mnu, r1, reaper.redirectLaunch, args)
		end 
		if theZone.statusUI then 
			local r2 = missionCommands.addCommandForCoalition(coa, "Status Update", r1, reaper.redirectSingleStatus, args)
		end 
		local r2 = missionCommands.addCommandForCoalition(coa, "Cycle target", r1, reaper.redirectCycleTarget, args)
	end
end 

function reaper.redirectDroneStatus(args)
	timer.scheduleFunction(reaper.doDroneStatus, args, timer.getTime() + 0.1)
end 

function reaper.redirectLaunch(args)
	timer.scheduleFunction(reaper.doLaunch, args, timer.getTime() + 0.1)
end 

function reaper.redirectSingleStatus(args)
	timer.scheduleFunction(reaper.doSingleStatusM, args, timer.getTime() + 0.1)
end

function reaper.redirectCycleTarget(args)
	timer.scheduleFunction(reaper.doCylcleTarget, args, timer.getTime() + 0.1)
end  
--
-- DML API for UI
--
function reaper.doDroneStatusRed()
	 reaper.doDroneStatus({1,})
end 

function reaper.doDroneStatusBlue()
	 reaper.doDroneStatus({2,})
end 

function reaper.doDroneStatus(args)
	local coa = args[1]
--	trigger.action.outText("enter do drone status for coa " .. coa, 30)
	local done = {}
	local msg = ""
	local filtered = {}
	for name, theZone in pairs(reaper.tracking) do 
		if theZone.coa == coa and theZone.statusUI then 
			filtered[name] = theZone 
		end 
	end 
	local n = dcsCommon.getSizeOfTable(filtered)
	-- collect tracking drones 
	if n > 0 then 
		msg = msg .. "\nThe following drones are tracking targets:"
		for name, theZone in pairs(filtered) do 
			msg = msg .. "\n  <" .. name .. ">: "
			local theTarget = theZone.theTarget 
			if theTarget and Unit.isExist(theTarget) then 
				local lp = theTarget:getPoint()
				local lat, lon, alt = coord.LOtoLL(lp)
				lat, lon = dcsCommon.latLon2Text(lat, lon)
				local ut = theTarget:getTypeName()
				local twnLoc = ""
				if twn and towns then 
					local tname, data, dist = twn.closestTownTo(lp)
					local mdist= dist * 0.539957
					dist = math.floor(dist/100) / 10
					mdist = math.floor(mdist/100) / 10		
					local bear = dcsCommon.compassPositionOfARelativeToB(lp, data.p)
					twnLoc = " (" ..dist .. "km/" .. mdist .."nm " .. bear .. " of " .. tname .. ") "
				end
				msg = msg .. ut .. " at " .. lat .. ", " .. lon .. twnLoc .. " code " .. theZone.code 
			else 
				msg = msg .. "<signal failure, please try later>"
			end
			done[name] = true 
		end
	else 
		msg = msg .. "\n(No drones are tracking targets)\n"
	end
	
	-- collect loitering drones 
	filtered = {}
	for name, theZone in pairs(reaper.scanning) do 
		if theZone.coa == coa and theZone.statusUI then filtered[name] = theZone end 
	end 
	n = dcsCommon.getSizeOfTable(filtered)
	if n > 0 then 
		msg = msg .. "\n\nThe following drones are loitering on-station"
		for name, theZone in pairs(filtered) do 
			msg = msg .. "\n  <" .. name .. ">: (" .. theZone.myType .. ")"
			done[name] = true 
		end
	else 
		msg = msg .. "\n\n(No drones are loitering)\n"
	end 

	filtered = {}
	for name, theZone in pairs(reaper.zones) do 
		if theZone.coa == coa and theZone.statusUI and not done[name] then 
			filtered[name] = theZone
		end
	end
	n = dcsCommon.getSizeOfTable(filtered)
	if n > 0 then 
		msg = msg .. "\n\nThe following drones are ready to launch"
		for name, theZone in pairs(filtered) do 
			msg = msg .. "\n  <" .. name .. ">: " .. theZone.myType .. " "
			if bank and reaper.useCost then 
				msg = msg .. "(§" .. theZone.cost .. ")"
			end
		end
		msg = msg .. "\n"
	else
		msg = msg .. "\n\n(All drones have launched)\n"
	end 
	trigger.action.outTextForCoalition(coa, msg, 30)
	trigger.action.outSoundForCoalition(coa, reaper.actionSound)
end

function reaper.doSingleDroneStatus(theZone)
	local coa = theZone.coa 
	local msg = ""
	local name = theZone.name 
	-- see if drone is tracking 
	if reaper.tracking[name] and theZone.theTarget then 
		msg = "<" .. name .. ">: "
		local theTarget = theZone.theTarget 
		if theTarget and Unit.isExist(theTarget) then 
			local lp = theTarget:getPoint()
			local lat, lon, alt = coord.LOtoLL(lp)
			lat, lon = dcsCommon.latLon2Text(lat, lon)
			local ut = theTarget:getTypeName()
			local twnLoc = ""
			if twn and towns then 
				local tname, data, dist = twn.closestTownTo(lp)
				local mdist= dist * 0.539957
				dist = math.floor(dist/100) / 10
				mdist = math.floor(mdist/100) / 10		
				local bear = dcsCommon.compassPositionOfARelativeToB(lp, data.p)
				twnLoc = " (" ..dist .. "km/" .. mdist .."nm " .. bear .. " of " .. tname .. ") "
			end
			msg = msg .. ut .. " at " .. lat .. ", " .. lon .. twnLoc .. " code " .. theZone.code 

			-- now add full group intelligence 
			local collector = {}
			local theGroup = theTarget:getGroup() 
			local allTargets = theGroup:getUnits()
			for idx, aTgt in pairs(allTargets) do 
				if Unit.isExist(aTgt) then 
					local tn = aTgt:getTypeName()
					if collector[tn] then collector[tn] = collector[tn] + 1 
					else collector[tn] = 1 end 
				end 
			end 
			msg = msg .."\nGroup consists of: "
			local i = 1
			for name, count in pairs(collector) do 
				if i > 1 then msg = msg .. ", " end 
				msg = msg .. name 
				if count > 1 then msg = msg .. " (x" .. count .. ")" end
				i = 2 
			end
			msg = msg .. ".\n"
		else 
			msg = msg .. "[signal failure, please try again later]"
		end
		
		trigger.action.outTextForCoalition(coa, msg, 30)
		trigger.action.outSoundForCoalition(coa, reaper.actionSound)
		return 
	end
	
	-- see if drone is loitering 
	if reaper.scanning[name] then 
		msg = "<" .. name .. ">: (" .. theZone.myType .. ") loitering, scanning for targets"
		trigger.action.outTextForCoalition(coa, msg, 30)
		trigger.action.outSoundForCoalition(coa, reaper.actionSound)
		return 
	end 
 
	msg = "<" .. name .. ">: " .. theZone.myType .. " "
	if bank and reaper.useCost then 
		msg = msg .. "(§" .. theZone.cost .. ") "
	end
	msg = msg .. "ready to launch"
	trigger.action.outTextForCoalition(coa, msg, 30)
	trigger.action.outSoundForCoalition(coa, reaper.actionSound)
end

function reaper.doSingleStatusM(args)
	local coa = args[1]
	local name = args[2] 
	local theZone = reaper.zones[name]
	if not theZone then end return 
	reaper.doSingleDroneStatus(theZone)
end

function reaper.doCylcleTarget(args)
	local coa = args[1]
	local name = args[2] 
	local theZone = reaper.zones[name]
	if not theZone then end return 
	reaper.cycleTarget(theZone)
end 

function reaper.doLaunch(args)
	local coa = args[1]
	local name = args[2] 
	-- check if we can launch 
	local theZone = reaper.zones[name] 
	if not theZone then 
		trigger.action.outText("+++reap: something strange happened with launcher <" .. name .. ">", 30)
		return 
	end 
	
	if theZone.theUav and Unit.isExist(theZone.theUav) then 
		trigger.action.outTextForCoalition(coa, "Drone <" .. name .. "> is already on-station", 30)
		trigger.action.outSoundForCoalition(coa, reaper.actionSound)
		return 
	end 
	local hasBalance, amount = 0, 0
	-- money check if enabled 
	if bank and reaper.useCost then 
		hasBalance, amount = bank.getBalance(coa)
		if not hasBalance then 
			amount = 0
		end
		
		if amount < theZone.cost then 
			trigger.action.outTextForCoalition(coa, "Insufficient funds (§" .. theZone.cost .. " required, you have §" .. amount, 30)
			trigger.action.outSoundForCoalition(coa, reaper.actionSound)
			return
		end 
	end 
	
	-- ok, go for launch 
	reaper.spawnForZone(theZone)
	
	-- subtract funds 
	if bank and reaper.useCost then 
		trigger.action.outTextForCoalition(coa, "Launching <" .. theZone.myType .. "> drone for §" .. theZone.cost .. ", §" .. amount - theZone.cost .. " remaining.", 30)
		bank.withdawFunds(coa, theZone.cost)
	else 
		trigger.action.outTextForCoalition(coa, "Launching <" .. theZone.myType .. "> drone.", 30)
	end 
	trigger.action.outSoundForCoalition(coa, reaper.actionSound)
end

--
-- config 
--
function reaper.readConfigZone()
	local theZone = cfxZones.getZoneByName("reaperConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("reaperConfig") 
	end 
	reaper.name = "reaperConfig" -- zones comaptibility 
	reaper.actionSound = theZone:getStringFromZoneProperty("actionSound", "UI_SCI-FI_Tone_Bright_Dry_20_stereo.wav")
	reaper.hasUI = theZone:getBoolFromZoneProperty("UI", true)
	reaper.menuName = theZone:getStringFromZoneProperty("menuName", "Drone Command")
	reaper.useCost = theZone:getBoolFromZoneProperty("useCost", true)
	if theZone:hasProperty("blueStatus?") then 
		reaper.blueStatus = theZone:getStringFromZoneProperty("blueStatus?", "<none>")
		reaper.blueStatusVal = theZone:getFlagValue(reaper.blueStatus) -- save last value
	end 
	if theZone:hasProperty("redStatus?") then 
		reaper.redStatus = theZone:getStringFromZoneProperty("redStatus?", "<none>")
		reaper.redStatusVal = theZone:getFlagValue(reaper.redStatus) -- save last value
	end 
	
	if theZone:hasProperty("attachTo:") then 
		local attachTo = theZone:getStringFromZoneProperty("attachTo:", "<none>")
		if radioMenu then 
			local mainMenu = radioMenu.mainMenus[attachTo]
			if mainMenu then 
				reaper.mainMenu = mainMenu 
			else 
				trigger.action.outText("+++reaper: cannot find super menu <" .. attachTo .. ">", 30)
			end
		else 
			trigger.action.outText("+++reaper: REQUIRES radioMenu to run before reaper. 'AttachTo:' ignored.", 30)
		end 
	end 
	reaper.verbose = theZone.verbose 
end

-- persistence 
 function reaper.saveData()
	local theData = {}
	-- save all non-self-starting, yet running reapers 
	local running = {}
	for name, theZone in pairs (reaper.zones) do 
		if (not theZone.onStart) and (theZone.theUav) 
		and Unit.isExist(theZone.theUav) then 
			running[name] = true 
		end
	end 
	theData.running = running 
		
	return theData, reaper.sharedData
end

function reaper.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("reaper", reaper.sharedData)
	if not theData then 
		if reaper.verbose then 
			trigger.action.outText("+++reaper: no save data received, skipping.", 30)
		end
		return
	end
	local running = theData.running 
	if theData.running then 
		for name, ignore in pairs (running) do 
			local theZone = reaper.zones[name]
			if theZone then 
				reaper.spawnForZone(theZone)
			else 
				trigger.action.outText("+++reaper - persistence: zone <" .. name .. "> does not exist", 30)
			end
		end
	end		
end

-- go go go
function reaper.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx reaper requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx reaper", reaper.requiredLibs) then
		return false 
	end
	
	-- read config 
	reaper.readConfigZone()

	-- read reaper zones 
	local rZones = cfxZones.zonesWithProperty("reaper")
	for k, aZone in pairs(rZones) do
		reaper.readReaperZone(aZone)
		reaper.zones[aZone.name] = aZone
	end

	-- install UI if desired 
	if reaper.hasUI then 
		local coas = {1, 2}
		for idx, coa in pairs(coas) do 
			reaper.installFullUIForCoa(coa)
		end	
	end 

	-- load data if persisted
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = reaper.saveData
		persistence.registerModule("reaper", callbacks)
		-- now load my data 
		reaper.loadData()
	end	
	
	-- schedule first update 
	timer.scheduleFunction(reaper.update, {}, timer.getTime() + 1)
	
	-- schedule scan and track loops 
	timer.scheduleFunction(reaper.scanALT, {}, timer.getTime() + 1)
	timer.scheduleFunction(reaper.track, {}, timer.getTime() + 1) 
	trigger.action.outText("reaper v " .. reaper.version .. " running.", 30)
	return true 
end

if not reaper.start() then 
	trigger.action.outText("Reaper failed to start", 30)
end 

--[[--
	Idea: mobile launch vehicle, zone follows apc around. Can even be hauled along with hook
	
	todo: make reaper invisible by attribute 
--]]--
