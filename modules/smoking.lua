smoking = {}
smoking.version = "1.0.0"
smoking.requiredLibs = { -- a DML module (c) 2025 by Christian Franz
	"dcsCommon",
	"cfxZones",
}
smoking.zones = {}
smoking.roots = {} -- groups that have already been inited 

--[[-- VERSION HISTORY
 - 1.0.0 initial version

--]]--

-- FOR NOW REQUIRES SINGLE-UNIT PLAYER GROUPS
function smoking.createSmokingZone(theZone)
	theZone.smColor = theZone:getSmokeColorNumberFromZoneProperty("smoking", "white")
	if theZone.smColor > 0 then theZone.smColor = theZone.smColor + 1 end
	theZone.smAlt = theZone:getNumberFromZoneProperty("alt", 0)
end

-- event handler 
function smoking:onEvent(theEvent)
	if not theEvent then return end 
	if not theEvent.initiator then return end 
	local theUnit = theEvent.initiator
	if not theUnit.getName then return end 
	if not theUnit.getPlayerName then return end 
	if not theUnit:getPlayerName() then return end 
	if not theUnit.getGroup then return end 
	local theGroup = theUnit:getGroup()
	if not theGroup then return end 
	if theEvent.id == 15 and smoking.hasGUI then -- birth and gui on 
		local theColor = nil 
		local theAlt = smoking.smAlt -- default to global 
		-- see if we even want to install a menu 
		if dcsCommon.getSizeOfTable(smoking.zones) > 0 then 
			p = theUnit:getPoint()
			for idx, theZone in pairs(smoking.zones) do 
				if theZone:pointInZone(p) then 
					theColor = theZone.smColor
					theAlt = theZone.smAlt
				end 
			end 
			if not theColor then return	end
		else 
			theColor = smoking.color -- use global color 
		end 
		if theColor < 1 then theColor = math.random(1, 5) end 
		local gName = theGroup:getName()
		if smoking.roots[gName] then return end -- already inited 
		local uName = theUnit:getName()
		local gID = theGroup:getID()

		-- remove old group menu 
		if smoking.roots[gName] then  
			missionCommands.removeItemForGroup(gID, smoking.roots[gName])
		end 
		
		-- handle main menu 
		local mainMenu = nil 
		if smoking.mainMenu then 
			mainMenu = radioMenu.getMainMenuFor(smoking.mainMenu) 
		end 
		
		local root = missionCommands.addSubMenuForGroup(gID, smoking.menuName, mainMenu) 
		smoking.roots[gName] = root 
		
		local args = {}
		args.theUnit = theUnit 
		args.uName = uName 
		args.gID = gID 
		args.gName = gName 
		args.coa = theGroup:getCoalition()
		args.smAlt = theAlt
		args.smColor = theColor 
		-- now add the submenus for convoys 
		local m = missionCommands.addCommandForGroup(gID, "Smoke ON", root, smoking.redirectSmoke, args)
		args = {} -- create new!! ref 
		args.theUnit = theUnit 
		args.uName = uName 
		args.gID = gID 
		args.gName = gName 
		args.coa = theGroup:getCoalition()
		args.smAlt = 0 
		args.smColor = 0 -- color 0 = turn off 
		m = missionCommands.addCommandForGroup(gID, "Turn OFF smoke", root, smoking.redirectSmoke, args)
	end -- if birth
end

function smoking.redirectSmoke(args) -- escape debug confines 
	timer.scheduleFunction(smoking.doSmoke, args, timer.getTime() + 0.1)
end 

function smoking.doSmoke(args)
	local uName = args.uName
	local theColor = args.smColor
	local theAlt = args.smAlt 
	trigger.action.ctfColorTag(uName, theColor, 0) -- , theAlt)
	if smoking.verbose then 
		trigger.action.outText("+++smk: turning smoke trail for <" .. uName .. "> to <" .. theColor .. ">", 30)
	end 
end


-- config
function smoking.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("smokingConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("smokingConfig") 
	end 
	smoking.ups = theZone:getNumberFromZoneProperty("ups", 1)
	smoking.name = "smoking" 
	smoking.verbose = theZone.verbose
	smoking.color = theZone:getSmokeColorNumberFromZoneProperty("color", "white" )  
	if smoking.color >= 0 then smoking.color = smoking.color + 1 end -- yeah, ctf aircraft smoke and ground smoke are NOT the same, ctf is gnd + 1. huzzah!
	smoking.smAlt = theZone:getNumberFromZoneProperty("alt", 0)
	smoking.menuName = theZone:getStringFromZoneProperty("menuName", "Smoke Trail")
	smoking.hasGUI = theZone:getBoolFromZoneProperty("GUI", true)
	if theZone:hasProperty("attachTo:") then 
		local attachTo = theZone:getStringFromZoneProperty("attachTo:", "<none>")
		if radioMenu then -- requires optional radio menu to have loaded 
			local mainMenu = radioMenu.mainMenus[attachTo]
			if mainMenu then 
				smoking.mainMenu = mainMenu 
			else 
				trigger.action.outText("+++smoking: cannot find super menu <" .. attachTo .. ">", 30)
			end
		else 
			trigger.action.outText("+++smoking: REQUIRES radioMenu to run before smoking. 'AttachTo:' ignored.", 30)
		end 
	end 
end


-- go go go 
function smoking.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("smoking requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("smoking", smoking.requiredLibs) then
		return false 
	end	
	-- read config 
	smoking.readConfigZone()
	-- process "fog?" Zones  
	local attrZones = cfxZones.getZonesWithAttributeNamed("smoking")
	for k, aZone in pairs(attrZones) do 
		smoking.createSmokingZone(aZone)
		smoking.zones[aZone.name] = aZone
	end
	-- hook into events 
	world.addEventHandler(smoking)
	
	trigger.action.outText("smoking v" .. smoking.version .. " started.", 30)
	return true 
end

-- let's go!
if not smoking.start() then 
	trigger.action.outText("smoking aborted: error on start", 30)
	smoking = nil 
end

--[[--
	To Do: 
		- smoking zones where aircraft automatically turn on/off their smoke
		- different smoke colors for red and blue in autosmoke zones  
--]]--