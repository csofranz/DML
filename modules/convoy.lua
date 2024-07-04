convoy = {}
convoy.version = "0.0.0"
convoy.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
	"cfxMX",
}
convoy.zones = {}
convoy.running = {}
convoy.ups = 1

function convoy.addConvoyZone(theZone)
	convoy.zones[theZone.name] = theZone
end 

function convoy.readConvoyZone(theZone)
	theZone.coa = theZone:getCoalitionFromZoneProperty("coalition", 0)
	if theZone:hasProperty("masterOwner") then 
		local mo = theZone:getStringFromZoneProperty("masterOwner")
		local mz = cfxZones.getZoneByName(mo)
		if not mz then 
			trigger.action.outText("+++cvoy: WARNING: Master Owner <" .. mo .. "> for zone <" .. theZone.name .. "> does not exist!", 30)
		else 
			theZone.masterOwner = mz 
		end
		theZone.isDynamic = theZone:getBoolFromZoneProperty("dynamic", true)
	end
	-- get groups inside me. 
	local myGroups, count = cfxMX.allGroupsInZoneByData(theZone)
	trigger.action.outText("zone <" .. theZone.name .. ">: <" .. count .. "> convoy groups", 30)
	theZone.myGroups = myGroups
	theZone.unique = theZone:getBoolFromZoneProperty("unique", true)
	theZone.preWipe = theZone:getBoolFromZoneProperty("preWipe", true) or theZone.unique 
	theZone.onStart = theZone:getBoolFromZoneProperty("onStart", false)
	
	-- wipe all existing 
	for groupName, data in pairs(myGroups) do 
		local g = Group.getByName(groupName) 
		if g then 
			Group.destroy(g)
		end 
	end 
end

function convoy.startConvoy(theZone)
	-- make sure my coa is set up correctly 
	local mo = theZone.masterOwner
	if mo then 
		theZone.owner = mo.owner
		if theZone.isDynamic then
			theZone.coa = mo.owner 
		end 
	end
	
	-- iterate all groups 
	local spawns = {}
	for gName, gOrig in pairs(theZone.myGroups) do 
		trigger.action.outText("convoy: startting group <" .. gName .. "> for zone <" .. theZone.name .. ">", 30)
		local gData = dcsCommon.clone(gOrig)
		-- make unique names for group and units if desired 
		if theZone.unique then 
			gData.name = dcsCommon.uuid(gOrig.name)
			for idx, theUnit in pairs (gData.units) do 
				theUnit.name = dcsCommon.uuid(theUnit.name)
			end 
		end
		convoy.amendData(theZone, gData) -- add actions to route 
		-- wipe existing if requested 
		if theZone.preWipe then 
			
		end 
		local catRaw = cfxMX.groupTypeByName[gName]
		local gCat = Group.Category.GROUND
		if catRaw == "helicopter" then 
			gCat = Group.Category.HELICOPTER
		elseif catRaw == "plane" then 
			gCat = Group.Category.AIRPLANE
		elseif catRaw == "vehicle" then 
			gCat = Group.Category.GROUND
		else -- missing so far: ship
			trigger.action.outText("+++milH: ignored group <" .. gName .. ">: unknown type <" .. catRaw .. ">", 30)
		end 
		local cty = dcsCommon.getACountryForCoalition(theZone.coa)
		local theSpawnedGroup = coalition.addGroup(cty, gCat, gData)
		spawns[gData.name] = theSpawnedGroup
		trigger.action.outText("convoy <" .. theSpawnedGroup:getName() .. "> spawned for <" .. theZone.name .. ">", 30)
	end 
end 	

function convoy.amendData(theZone, theData)
	-- place a callback action for each waypoint 
	-- in data block 
	if not theData.route then return end 
	local route = theData.route 
	if not route.points then return end 
	local points = route.points
	local np = #points 
	if np < 1 then return end 
	trigger.action.outText("convoy: group <" .. theData.name .. ">, zone <" .. theZone.name .. ">, points=<" .. np .. ">", 30)

--	for i=1, np do 
	local newPoints = {}
	for idx, aPoint in pairs(points) do 
		local wp = dcsCommon.clone(aPoint) -- points[i]
		local tasks = wp.task.params.tasks
		--local i = idx 
--		if not tasks then tasks = {} end 
--		if tasks then 
--		dcsCommon.dumpVar2Str("RAW tasks 1bc " .. idx, tasks)
		local tnew = #tasks + 1 -- new number for this task 
		local t = {
			["number"] = tnew,
			["auto"] = false,
			["id"] = "WrappedAction",
			["enabled"] = true,
			["params"] = {
				["action"] = {
					["id"] = "Script",
					["params"] = {
						["command"] = "trigger.action.outText(\"convoy reached WP Index " .. idx .." = WP(" .. idx-1 .. ") of " .. np .. "\", 30)",
					}, -- end of ["params"]
				}, -- end of ["action"]
			}, -- end of ["params"]
		} -- end of task 
		-- add t to tasks 
		table.insert(tasks, t)
--		tasks[tnew] = t 
--		dcsCommon.dumpVar2Str("tasks for modded 1bc " .. idx, tasks)
		newPoints[idx] = wp
		trigger.action.outText("convoy: added wp task to wp <" .. idx .. ">", 30)
	--	end 
--		dcsCommon.dumpVar2Str("modded point 1BC WP" .. idx, wp)
		newPoints[idx] = wp
	end 
	route.points = newPoints 
--	dcsCommon.dumpVar2Str("points", points)
	
end 

--
-- UPDATE
--
function convoy.update()
	timer.scheduleFunction(convoy.update, {}, timer.getTime() + 1/convoy.ups)
	-- update all master owners 
	for idx, theZone in pairs (convoy.zones) do 
--[[--		local mo = theZone.masterOwner
		if mo then 
			theZone.owner = mo.owner
			if theZone.isDynamic then
				theZone.coa = mo.owner 
			end 
		end --]]--	
	end
end

--
-- START
--

function convoy.readConfigZone()
	local theZone = cfxZones.getZoneByName("convoyConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("convoyConfig") 
	end 
	convoy.verbose = theZone.verbose
	convoy.ups = theZone:getNumberFromZoneProperty("ups", 1)
end

function convoy.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx convoy requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx convoy", convoy.requiredLibs) then
		return false 
	end
	
	-- read config 
	convoy.readConfigZone()

	-- process convoy Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("convoy")
	for k, aZone in pairs(attrZones) do 
		convoy.readConvoyZone(aZone) -- process attributes
		convoy.addConvoyZone(aZone) -- add to list
	end
	
	-- start update 
	timer.scheduleFunction(convoy.update, {}, timer.getTime() + 1/convoy.ups)
	
	-- start all zones that have onstart 
	for gName, theZone in pairs(convoy.zones) do 
		if theZone.onStart then 
			convoy.startConvoy(theZone)
		end
	end 
	return true 
end

if not convoy.start() then 
	trigger.action.outText("convoy failed to start up")
	convoy = nil 
end 

--[[--
convoy module
place over a fully configured group, will clone on command (start?)
reportWaypoint option. Add small script to each and every waypoint, will create report 
destinationReached! -- adds script to last waypoint to hit this signal, also inits cb
dead! signal and cb. only applies to ground troops? can they disembark troops when hit?
attacked signal each time a unit is destroyed
importantType - type that must survive=
coalition / masterOwner 
isActive# 0/1 
can only have one active convoy 
can it have helicopters? 

--]]--