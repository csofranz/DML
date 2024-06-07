launchPlatform = {}
launchPlatform.version = "0.5.0"
launchPlatform.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
}
launchPlatform.zones = {}
launchPlatform.redLaunchers = {}
launchPlatform.blueLaunchers = {}

-- weapon types currently known 
-- 52613349374 = tomahawk 

function launchPlatform.addLaunchPlatform(theZone)
	launchPlatform.zones[theZone.name] = theZone
	if theZone.coa == 1 or theZone.coa == 0 then 
		launchPlatform.redLaunchers[theZone.name] = theZone
	end 
	if theZone.coa == 2 or theZone.coa == 0 then 
		launchPlatform.blueLaunchers[theZone.name] = theZone 
	end 
	
end

function launchPlatform.readLaunchPlatform(theZone)
	theZone.coa = theZone:getCoalitionFromZoneProperty("coalition", 0)
	theZone.impactRadius = theZone:getNumberFromZoneProperty("radius", 1000)
	if theZone:hasProperty("salvos") then 
		theZone.num = theZone:getNumberFromZoneProperty("salvos", 1)
	end 
	if theZone:hasProperty("salvo") then 
		theZone.num = theZone:getNumberFromZoneProperty("salvo", 1)
	end 
	-- possible extensions: missile. currently tomahawk launched from a missile cruiser that beams in and vanishes later 
	-- later versions could support SCUDS and some long-range arty, 
	-- perhaps even aircraft 

end

-- note - the tomahawks don't care who they belong to, we do not 
-- need them to belong to anyone, it may be a visibility thing though 

function launchPlatform.launchForPlatform(coa, theZone, tgtPoint, tgtZone)
	local launchPoint = theZone:createRandomPointInZone()
	local gData = launchPlatform.createData(launchPoint, tgtPoint, tgtZone, theZone.impactRadius, theZone.name, theZone.num)
	return gData 
end

function launchPlatform.launchAtTargetZone(coa, tgtZone, theType) -- gets closest platform for target 
	-- type currently not supported 
	local platforms = launchPlatform.redLaunchers
	if coa == 2 then platforms = launchPlatform.blueLaunchers end 
	local cty = dcsCommon.getACountryForCoalition(coa)
	
	-- get closest launcher for target
	local tgtPoint = tgtZone:getPoint() 
	local src, dist = cfxZones.getClosestZone(tgtPoint, platforms)
	if launchPlatform.verbose then 
		trigger.action.outText("+++LP: chosen <" .. src.name .. "> as launch platform", 30)
	end 
	
	local theLauncher = launchPlatform.launchForPlatform(coa, src, tgtPoint, tgtZone)
	if not theLauncher then 
		trigger.action.outText("NO LAUNCHER", 30)
		return nil 
	end 
	-- if type is tomahawk, the platform is ship = 3
	local theGroup = coalition.addGroup(cty, 3, theLauncher)
	if not theGroup then 
		trigger.action.outText("!!!!!!!!!!!!!NOPE", 30)
		return
	end 
	-- we remove the group in some time 
	local now = timer.getTime()
	timer.scheduleFunction(launchPlatform.asynchRemovePlatform, theGroup:getName(), now + 300)
end 

function launchPlatform.asynchRemovePlatform(args)
	if launchPlatform.verbose then 
		trigger.action.outText("+++LP: asynch remove for group <" .. args .. ">", 30)
	end 
	local theGroup = Group.getByName(args)
	if not theGroup then return end 
	Group.destroy(theGroup)
end 

function launchPlatform.createData(thePoint, theTarget, targetZone, radius, name, num, wType)
	-- if present, we can use targetZone with some intelligence 
	if not thePoint then 
		trigger.action.outText("+++LP: NO POINT", 30)
		return nil 
	end 
	if not theTarget then 
		trigger.action.outText("+++LP: NO TARGET", 30)
		return nil 
	end 
	
	if not wType then wType = 52613349374 end 
	if not radius then radius = 1000 end 
	local useQty = true 
	if not num then num = 15 end 
	if num > 30 then num = 30 end -- max 30 missiles 
	
	if not name then name = "launcherDML" end 
	local gData = {
		["visible"] = false,
		["tasks"] = {},
		["uncontrollable"] = false,
		["route"] = {
			["points"] = {
				[1] = {
					["alt"] = 0,
					["type"] = "Turning Point",
					["ETA"] = 0,
					["alt_type"] = "BARO",
					["formation_template"] = "",
					["y"] = thePoint.z,
					["x"] = thePoint.x, 
					["ETA_locked"] = true,
					["speed"] = 0,
					["action"] = "Turning Point",
					["task"] = {
						["id"] = "ComboTask",
						["params"] = {
							["tasks"] = {
								[1] = {
									["number"] = 1,
									["auto"] = false,
									["id"] = "FireAtPoint",
									["enabled"] = true,
									["params"] = {
										["y"] = theTarget.z, 
										["x"] = theTarget.x, 
										["expendQtyEnabled"] = true,
										["alt_type"] = 1,
										["templateId"] = "",
										["expendQty"] = 2,
										["weaponType"] = wType,
										["zoneRadius"] = radius,
									}, -- end of ["params"]
								}, -- end of [1]
							}, -- end of ["tasks"]
						}, -- end of ["params"]
					}, -- end of ["task"]
					["speed_locked"] = true,
				}, -- end of [1]
			}, -- end of ["points"]
		}, -- end of ["route"]
		["hidden"] = false,
		["units"] = {
			[1] =  {
				["modulation"] = 0,
				["skill"] = "Average",
				["type"] = "USS_Arleigh_Burke_IIa",
				["y"] = thePoint.z, 
				["x"] = thePoint.x, 
				["name"] = dcsCommon.uuid(name),
				["heading"] = 2.2925180610373,
				["frequency"] = 127500000,
			}, -- end of [1]
		}, -- end of ["units"]
		["y"] = thePoint.z, 
		["x"] = thePoint.x, 
		["name"] = dcsCommon.uuid(name),
		["start_time"] = 0,
	}
	
	-- now create the tasks block replacements
	-- create random target locations inside 
	-- target point with radius and launch 2 per salvo 
	-- perhaps add some inteligence to target resource points 
	-- if inside camp 
	local hiPrioTargets
	if targetZone and targetZone.cloners and #targetZone.cloners > 0 then 
		if launchPlatform.verbose then 
			trigger.action.outText("+++LP: detected <" .. targetZone.name .. "> is camp with <" .. #targetZone.cloners .. "> res-points, re-targeting hi-prio", 30)
		end 
		hiPrioTargets = targetZone.cloners 
		radius = radius / 10 -- much smaller error 
	end 
	local tasks = {}
	for i=1, num do 
		local dp = dcsCommon.randomPointInCircle(radius, 0)
		if hiPrioTargets then 
			-- choose one of the 
			local thisCloner = dcsCommon.pickRandom(hiPrioTargets)
			local tp = thisCloner:getPoint()
			dp.x = dp.x + tp.x 
			dp.z = dp.z + tp.z 

		else 
			dp.x = dp.x + theTarget.x 
			dp.z = dp.z + theTarget.z 
		end 
		local telem = {
			["number"] = i,
			["auto"] = false,
			["id"] = "FireAtPoint",
			["enabled"] = true,
			["params"] = {
				["y"] = dp.z, 
				["x"] = dp.x, 
				["expendQtyEnabled"] = true,
				["alt_type"] = 1,
				["templateId"] = "",
				["expendQty"] = 1,
				["weaponType"] = wType,
				["zoneRadius"] = radius,
			}, -- end of ["params"]
		} -- end of [1]
		-- table.insert(tasks, telem)
		tasks[i] = telem
	end 
	
	-- now replace old task with new 
	gData.route.points[1].task.params.tasks = tasks 
	return gData
end

--
-- start up 
--
function launchPlatform.readConfigZone()
	local theZone = cfxZones.getZoneByName("launchPlatformConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("launchPlatformConfig") 
	end 
	launchPlatform.verbose = theZone.verbose 
end

		
function launchPlatform.start()
-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx launchPlatform requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx launchPlatform", launchPlatform.requiredLibs) then
		return false 
	end
	
	-- read config 
	launchPlatform.readConfigZone()
	
	-- process launchPlatform Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("launchPlatform")
	for k, aZone in pairs(attrZones) do 
		launchPlatform.readLaunchPlatform(aZone) -- process attributes
		launchPlatform.addLaunchPlatform(aZone) -- add to list
	end
		
	-- say hi 
	trigger.action.outText("launchPlatform v" .. launchPlatform.version .. " started.", 30)
	return true 
end

if not launchPlatform.start() then 
	trigger.action.outText("launchPlatform failed to start.", 30)
	launchPlatform = nil 
end 
