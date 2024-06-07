reaper = {}
reaper.version = "1.0.0"
reaper.requiredLibs = {
	"dcsCommon",
	"cfxZones",  
}
--[[--
VERSION HISTORY

 1.0.0 - Initial Version 
 

--]]--

reaper.zones = {}-- all zones 
reaper.scanning = {} -- zones that are scanning (looking for tgt). by zone name
reaper.tracking = {} -- zones that are tracking tgt. by zone name
reaper.scanInterval = 10 -- seconds 
reaper.trackInterval = 0.3 -- seconds 

-- reading reaper zones 
function reaper.readReaperZone(theZone)
	theZone.myType = string.lower(theZone:getStringFromZoneProperty("reaper", "reaper"))
	if dcsCommon.stringStartsWith(theZone.myType, "pre") then theZone.myType = "RQ-1A Predator" else theZone.myType = "MQ-9 Reaper" end 
	if theZone.myType == "MQ-9 Reaper" then 
		theZone.alt = 9500 
	else theZone.alt = 7500 end theZone.alt = theZone:getNumberFromZoneProperty("alt", theZone.alt)
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
	if theZone:hasProperty("launch?") then 
		theZone.launch = theZone:getStringFromZoneProperty("launch?", "<none>")
		theZone.launchVal = theZone:getFlagValue(theZone.launch)
	end 
	if theZone:hasProperty("status?") then 
		theZone.status = theZone:getStringFromZoneProperty("status?", "<none>")
		theZone.statusVal = theZone:getFlagValue(theZone.status)
	end 
	theZone.hasSpawned = false 
	
	if theZone.onStart then 
		reaper.spawnForZone(theZone)
	end
end

-- spawn a drone from a zone 
function reaper.spawnForZone(theZone, ack)
	-- create spawn data
	local gdata = dcsCommon.createEmptyGroundGroupData (dcsCommon.uuid(theZone.name))
	gdata.task = "Reconnaissance"
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

	-- build the unit data
	local unit = {}
	unit.name = dcsCommon.uuid(theZone.name)
	unit.x = left.x 
	unit.y = left.z 
	unit.type = theZone.myType 
	unit.skill = "High"
	if theZone.myType == "MQ-9 Reaper" then 
		unit.speed = 55
--		unit.alt = 9500 
	else 
--		unit.alt = 7500
		unit.speed = 33 
	end 
	unit.alt = theZone.alt 
	
	-- add to group 
	gdata.units[1] = unit 

	-- now create and add waypoints to route 
	gdata.route.points = {}
	local wp1 = reaper.createInitialWP(left, unit.alt, unit.speed)
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

function reaper.createInitialWP(p, alt, speed)
	local wp = {
		["alt"] = alt,
		["action"] = "Turning Point",
		["alt_type"] = "BARO",
		["properties"] = {
			["addopt"] = {}, -- end of ["addopt"]
		}, -- end of ["properties"]
		["speed"] = speed,
		["task"] = {
			["id"] = "ComboTask",
			["params"] = {
				["tasks"] = {
					[1] = {
						["enabled"] = true,
						["auto"] = true,
						["id"] = "WrappedAction",
						["number"] = 1,
						["params"] = {
							["action"] = {
								["id"] = "EPLRS",
								["params"] = {
									["value"] = true,
									["groupId"] = 1,
								}, -- end of ["params"]
							}, -- end of ["action"]
						}, -- end of ["params"]
					}, -- end of [1]
					[2] = {
						["enabled"] = true,
						["auto"] = false,
						["id"] = "Orbit",
						["number"] = 2,
						["params"] = {
							["altitude"] = alt,
							["pattern"] = "Race-Track",
							["speed"] = speed,
						}, -- end of ["params"]
					}, -- end of [2]
				}, -- end of ["tasks"]
			}, -- end of ["params"]
		}, -- end of ["task"]
		["type"] = "Turning Point",
		["ETA"] = 0,
		["ETA_locked"] = true,
		["y"] = p.z,
		["x"] = p.x,
		["speed_locked"] = true,
		["formation_template"] = "",
	} -- end of wp
	return wp 
end

-- scanning & tracking 
-- scanning looks for vehicles to track, and exectues much less often
-- tracking tracks a single vehicle and places a pointer on it 
function reaper.findFirstEnemyUnitVisible(enemies, theZone)
	local p = theZone.theUav:getPoint()
	-- we assume a flat altitude of 7000m 
	local visRange = theZone.alt * 1 -- based on tan(45) = 1 --> range = alt 
	for idx, aGroup in pairs(enemies) do 
		local theUnits = aGroup:getUnits()
		-- optimization: only scan the first vehicle in group if it's in range	local theUnit = theUnits[1]
		local theUnit = theUnits[1]
		if theUnit and Unit.isExist(theUnit) then 
			up = theUnit:getPoint()
			d = dcsCommon.distFlat(up, p)
			if d < visRange then 
				-- try each unit if it is visible from drone 
				for idy, aUnit in pairs(theUnits) do 
					local up = aUnit:getPoint()
					up.y = up.y + 2 
					if land.isVisible(p, up) then return aUnit end 
				end 
			end
		end
	end
end

function reaper.scan()
	-- how far can the drone see? we calculate with a 120 degree opening 
	-- camera lens, making half angle = 45 --> tan(45) = 1
	-- so the radius of the visible circle on the ground is 1 * altidude
	timer.scheduleFunction(reaper.scan, {}, timer.getTime() + reaper.scanInterval)
	filtered = {}
	local redEnemies = coalition.getGroups(2, 2) -- blue ground vehicles 
	local blueEnemeis = coalition.getGroups(1, 2) -- get ground vehicles 
	for name, theZone in pairs(reaper.scanning) do 
		local enemies = redEnemies 
		if theZone.coa == 2 then enemies = blueEnemeis end 
		if Unit.isExist(theZone.theUav) then 
			local theTarget = reaper.findFirstEnemyUnitVisible(enemies, theZone)
			if theTarget then 
				-- add a laser tracker to this unit 
				local lp = theTarget:getPoint()
				local lat, lon, alt = coord.LOtoLL(lp)
				lat, lon = dcsCommon.latLon2Text(lat, lon)
				
				local theSpot = Spot.createLaser(theZone.theUav, {0, 2, 0}, lp, theZone.code)
				if theZone.doSmoke then 
					trigger.action.smoke(lp , theZone.smokeColor )
				end 
				trigger.action.outTextForCoalition(theZone.coa, "Drone <" .. theZone.name .. "> is tracking a <" .. theTarget:getTypeName() .. "> at " .. lat .. " " .. lon .. ", code " .. theZone.code, 30)
				trigger.action.outSoundForCoalition(theZone.coa, reaper.actionSound)
				theZone.theTarget = theTarget
				if theZone.theSpot then 
					theZone.theSpot:destroy()
				end
				theZone.theSpot = theSpot
				-- put me in track mode 
				reaper.tracking[name] = theZone				
			else 
				-- will scan again 
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

function reaper.update()
	timer.scheduleFunction(reaper.update, {}, timer.getTime() + 1)

	-- go through all my zones, and respawn those that have no 
	-- uav but have autoRespawn active 
	
	for name, theZone in pairs(reaper.zones) do 
		if theZone.autoRespawn and not theZone.theUav and theZone.hasSpawned then 
			-- auto-respawn needs to kick in
			reaper.scanning[name] = nil 
			reaper.tracking[name] = nil 
			if reaper.verbose or theZone.verbose then 
				trigger.action.outText("+++reap: respawning for <" .. name .. ">", 30)
			end 
			reaper.spawnForZone(theZone)
		end 
		
		if theZone.status and theZone:testZoneFlag(theZone.status, "change", "statusVal") then 
			if theZone.verbose then 
				trigger.action.outText("+++reap: Triggered status for zone <" .. name .. "> on <" .. theZone.status .. ">", 30)
			end 
			reaper.doSingleDroneStatus(theZone)
		end 
		
		if theZone.launch and theZone:testZoneFlag(theZone.launch, "change", "launchVal") then 
			args = {}
			args[1] = theZone.coa -- = args[1]
			args[2] = name -- = args[2] 
			reaper.doLaunch(args)
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
		local c1 = missionCommands.addCommandForCoalition(coa, "Drone Status", root, reaper.redirectDroneStatus, {coa,})
		local r2 = missionCommands.addSubMenuForCoalition(coa, "Launch Drones", root)
		reaper.installLaunchersForCoa(coa, r2)
end

function reaper.installLaunchersForCoa(coa, root)
	-- WARNING: we currently install commands, may overflow!
--	trigger.action.outText("enter launchers builder", 30)
	local filtered = {}
	for name, theZone in pairs(reaper.zones) do 
		if theZone.coa == coa and theZone.launchUI then 
			filtered[name] = theZone 
		end 
	end 
	local n = dcsCommon.getSizeOfTable(filtered)
	if n > 10 then 
		trigger.action.outText("+++reap: WARNING too many (" .. n .. ") launchers for coa <" .. coa .. ">", 30)
		return 
	end 
	
	for name, theZone in pairs(filtered) do 
--		trigger.action.outText("proccing " .. name, 30)
		mnu = theZone.name .. ": " .. theZone.myType 
		if bank and reaper.useCost then 
			-- requires bank module
			mnu = mnu .. "(§" .. theZone.cost .. ")" 
		end 
		local args = {coa, name, }
		local r3 = missionCommands.addCommandForCoalition(coa, mnu, root, reaper.redirectLaunch, args)
	end
end

function reaper.redirectDroneStatus(args)
	timer.scheduleFunction(reaper.doDroneStatus, args, timer.getTime() + 0.1)
end 

function reaper.redirectLaunch(args)
	timer.scheduleFunction(reaper.doLaunch, args, timer.getTime() + 0.1)
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
				msg = msg .. ut .. " at " .. lat .. ", " .. lon .. " code " .. theZone.code 
			else 
				msg = msg .. "<signal failure, please try later>"
			end
			done[name] = true 
		end
	else 
		msg = msg .. "\n(No drones are tracking a target)\n"
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
--	trigger.action.outText("enter SINGLE drone status for coa " .. coa, 30)
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
			msg = msg .. ut .. " at " .. lat .. ", " .. lon .. " code " .. theZone.code 
		else 
			msg = msg .. "[signal failure, please try later]"
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

function reaper.doLaunch(args)
	coa = args[1]
	name = args[2] 
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
	reaper.UI = theZone:getBoolFromZoneProperty("UI", true)
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
	if reaper.UI then 
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
	timer.scheduleFunction(reaper.scan, {}, timer.getTime() + 1)
	timer.scheduleFunction(reaper.track, {}, timer.getTime() + 1) 
	
	trigger.action.outText("reaper v " .. reaper.version .. " running.", 30)
	return true 
end

if not reaper.start() then 
	trigger.action.outText("Reaper failed to start", 30)
end 

--[[--
	Idea: mobile launch vehicle, zone follows apc around. Can even be hauled along with hook
	idea: prioritizing targets in a group 
	fix quad zone waypoints 
	filter targets for lasing by list?
--]]--
