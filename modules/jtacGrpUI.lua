jtacGrpUI = {}
jtacGrpUI.version = "3.1.0"
jtacGrpUI.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", 
	"cfxGroundTroops", 
}
--[[-- VERSION HISTORY
 - 2.0.0 - dmlZones 
         - sanity checks upon load 
		 - eliminated cfxPlayer dependence 
		 - clean-up 
		 - jtacSound 
   3.0.0 - support for attachTo: 
   3.1.0 - support for DCS 2.0.6 dynamic player spwans 
   
--]]--
-- find & command cfxGroundTroops-based jtacs
-- UI installed via OTHER for all groups with players
-- module based on xxxGrpUI
 
jtacGrpUI.groupConfig = {} -- all inited group private config data, indexed by group name. 
jtacGrpUI.simpleCommands = true -- if true, f10 other invokes directly

function jtacGrpUI.resetConfig(conf)
end

function jtacGrpUI.createDefaultConfig(theGroup)
	if not theGroup then return nil end 
	if not Group.isExist(theGroup) then return end 
	
	local conf = {}
	conf.theGroup = theGroup
	conf.name = theGroup:getName()
	conf.id = theGroup:getID()
	conf.coalition = theGroup:getCoalition() 
	
	jtacGrpUI.resetConfig(conf)

	conf.mainMenu = nil; -- root
	conf.myCommands = nil; -- commands branch 
	
	return conf
end

-- getConfigFor group will allocate if doesn't exist in DB
-- and add to it
function jtacGrpUI.getConfigForGroup(theGroup)
	if not theGroup or (not Group.isExist(theGroup))then 
		trigger.action.outText("+++WARNING: jtacGrpUI nil group in getConfigForGroup!", 30)
		return nil 
	end
	local theName = theGroup:getName()
	local c = jtacGrpUI.getConfigByGroupName(theName) 
	if not c then 
		c = jtacGrpUI.createDefaultConfig(theGroup)
		jtacGrpUI.groupConfig[theName] = c 
	end
	return c 
end

function jtacGrpUI.getConfigByGroupName(theName) -- DOES NOT allocate when not exist
	if not theName then return nil end 
	return jtacGrpUI.groupConfig[theName]
end


function jtacGrpUI.getConfigForUnit(theUnit)
	-- simple one-off step by accessing the group 
	if not theUnit then 
		trigger.action.outText("+++WARNING: jtacGrpUI nil unit in getConfigForUnit!", 30)
		return nil 
	end
	local theGroup = theUnit:getGroup()
	return getConfigForGroup(theGroup)
end

--
-- M E N U   H A N D L I N G 
-- =========================
--
 function jtacGrpUI.clearCommsSubmenus(conf)
	if conf.myCommands then 
		for i=1, #conf.myCommands do
			missionCommands.removeItemForGroup(conf.id, conf.myCommands[i])
		end
	end
	conf.myCommands = {}
end

function jtacGrpUI.removeCommsFromConfig(conf)
	jtacGrpUI.clearCommsSubmenus(conf)
	
	if conf.myMainMenu then 
		missionCommands.removeItemForGroup(conf.id, conf.myMainMenu) 
		conf.myMainMenu = nil
	end
end

-- this only works in single-unit player groups. 
function jtacGrpUI.removeCommsForUnit(theUnit)
	if not theUnit then return end
	if not theUnit:isExist() then return end 	
	-- perhaps add code: check if group is empty
	local conf = jtacGrpUI.getConfigForUnit(theUnit)
	jtacGrpUI.removeCommsFromConfig(conf)
end

function jtacGrpUI.removeCommsForGroup(theGroup)
	if not theGroup then return end
	if not theGroup:isExist() then return end 	
	local conf = jtacGrpUI.getConfigForGroup(theGroup)
	jtacGrpUI.removeCommsFromConfig(conf)
end

function jtacGrpUI.isEligibleForMenu(theGroup)
	if jtacGrpUI.jtacTypes == "all" or 
	   jtacGrpUI.jtacTypes == "any" then return true end 
	if dcsCommon.stringStartsWith(jtacGrpUI.jtacTypes, "hel", true) then 
		local cat = theGroup:getCategory()
		return cat == 1
	end
	if dcsCommon.stringStartsWith(jtacGrpUI.jtacTypes, "plan", true) then 
		local cat = theGroup:getCategory()
		return cat == 0
	end
	if jtacGrpUI.verbose then 
		trigger.action.outText("+++jGUI: unknown jtacTypes <" .. jtacGrpUI.jtacTypes .. "> -- allowing access to group <" .. theGroup:getName() ..">", 30)
	end 
	return true -- for later expansion 
end

function jtacGrpUI.setCommsMenuForUnit(theUnit)
	if not theUnit then 
		trigger.action.outText("+++WARNING: jtacGrpUI nil UNIT in setCommsMenuForUnit!", 30)
		return
	end
	if not theUnit:isExist() then return end 
	
	local theGroup = theUnit:getGroup()
	jtacGrpUI.setCommsMenu(theGroup)
end

function jtacGrpUI.setCommsMenu(theGroup)
	if not theGroup then return end
	if not Group.isExist(theGroup) then return end 
	if not jtacGrpUI.isEligibleForMenu(theGroup) then return end
	
	local mainMenu = nil 
	if jtacGrpUI.mainMenu then 
		mainMenu = radioMenu.getMainMenuFor(jtacGrpUI.mainMenu) -- nilling both next params will return menus[0]
	end 
	
	local conf = jtacGrpUI.getConfigForGroup(theGroup) 
	conf.id = theGroup:getID(); -- we always do this
	
	if jtacGrpUI.simpleCommands then 
		-- we install directly in F-10 other 
		if not conf.myMainMenu then 
			local commandTxt = "jtac Lasing Report"
			local theCommand =  missionCommands.addCommandForGroup(
				conf.id, commandTxt, mainMenu, jtacGrpUI.redirectCommandX, {conf, "lasing report"})
			conf.myMainMenu = theCommand
		end
		
		return 
	end
		
	-- ok, first, if we don't have an F-10 menu, create one 
	if not (conf.myMainMenu) then 
		conf.myMainMenu = missionCommands.addSubMenuForGroup(conf.id, 'jtac', mainMenu) 
	end
	
	-- clear out existing commands
	jtacGrpUI.clearCommsSubmenus(conf)
	
	-- now we have a menu without submenus. 
	-- add our own submenus
	jtacGrpUI.addSubMenus(conf)
	
end

function jtacGrpUI.addSubMenus(conf)
	local commandTxt = "jtac Lasing Report"
	local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				jtacGrpUI.redirectCommandX, 
				{conf, "lasing report"}
				)
	table.insert(conf.myCommands, theCommand)
end

function jtacGrpUI.redirectCommandX(args)
	timer.scheduleFunction(jtacGrpUI.doCommandX, args, timer.getTime() + 0.1)
end

function jtacGrpUI.doCommandX(args)
	local conf = args[1] -- < conf in here
	local what = args[2] -- < second argument in here
	local theGroup = conf.theGroup
	local targetList = jtacGrpUI.collectJTACtargets(conf, true)
	-- iterate the list
	if #targetList < 1 then 
		trigger.action.outTextForGroup(conf.id, "No targets are currently being lased", 30)
		trigger.action.outSoundForGroup(conf.id, jtacGrpUI.jtacSound)
		return 
	end
	
	local desc = "JTAC Target Report:\n"
	for i=1, #targetList do 
		local aTarget = targetList[i]
		if aTarget.idle then 
			desc = desc .. "\n" .. aTarget.jtacName .. aTarget.posInfo ..": no target"
		else 
			desc = desc .. "\n" .. aTarget.jtacName .. aTarget.posInfo .." lasing " .. aTarget.lazeTargetType .. " [" .. aTarget.range .. "nm at " .. aTarget.bearing .. "°]," .. " code=" .. cfxGroundTroops.laseCode 
		end 
	end
	trigger.action.outTextForGroup(conf.id, desc .. "\n", 30)
	trigger.action.outSoundForGroup(conf.id, jtacGrpUI.jtacSound)
end

function jtacGrpUI.collectJTACtargets(conf, includeIdle)
	-- iterate cfxGroundTroops.deployedTroops to retrieve all 
	-- troops that are lazing. 'Lazing' are all groups that 
	-- have an active (non-nil) lazeTarget and 'laze' orders
	if not includeIdle then includeIdle = false end 
	
	local theJTACS = {}
	for idx, troop in pairs(cfxGroundTroops.deployedTroops) do 
		if troop.coalition == conf.coalition
			and troop.orders == "laze" 
			and troop.lazeTarget 
			and troop.lazeTarget:isExist() 
		then 
			table.insert(theJTACS, troop)
		elseif troop.coalition == conf.coalition 
			and troop.orders == "laze"
			and includeIdle
		then 
			-- we also include idlers
			table.insert(theJTACS, troop)
		end
	end
	
	-- we now have a list of all ground troops that are lazing.
	-- get bearing and range to targets, and sort them accordingly
	local targetList = {}
	local here = dcsCommon.getGroupLocation(conf.theGroup) -- this is me
	
	for idx, troop in pairs (theJTACS) do
		local aTarget = {}
		-- establish our location 
		aTarget.jtacName = troop.name 
		aTarget.posInfo = ""
		if cfxOwnedZones and cfxOwnedZones.hasOwnedZones() then 
			local jtacLoc = dcsCommon.getGroupLocation(troop.group)
			local nearestZone = cfxOwnedZones.getNearestOwnedZoneToPoint(jtacLoc)
			if nearestZone then 
				local ozRange = dcsCommon.dist(jtacLoc, nearestZone.point) * 0.000621371 -- meters to nm 
				ozRange = math.floor(ozRange * 10) / 10
				local relPos = dcsCommon.compassPositionOfARelativeToB(jtacLoc, nearestZone.point)
				aTarget.posInfo = " (" .. ozRange .. "nm " .. relPos .. " of " .. nearestZone.name .. ")"
			end
		end
		-- we may get idlers, catch them now 
		if not troop.lazeTarget then 
			aTarget.idle = true
			aTarget.range = math.huge
		else 
			-- get the target we are lazing 
			local there = troop.lazeTarget:getPoint()
			aTarget.idle = false
			aTarget.range = dcsCommon.dist(here, there)
			aTarget.range = aTarget.range * 0.000621371 -- meter to miles 
			aTarget.range = math.floor(aTarget.range * 10) / 10
			aTarget.bearing = dcsCommon.bearingInDegreesFromAtoB(here, there)
			aTarget.lazeTargetType = troop.lazeTargetType
		end
		table.insert(targetList, aTarget)
	end
	
	-- now sort by range 
	table.sort(targetList, function (left, right) return left.range < right.range end )
	
	-- return list sorted by distance
	return targetList
end

--
-- event handler - simplified, only for player birth
--
function jtacGrpUI:onEvent(theEvent)
	if not theEvent then return end 
	local theUnit = theEvent.initiator
	if not theUnit then return end 
	if not theUnit.getName then return end -- dcs 2.9.6 jul-11 fix 
	local uName = theUnit:getName()
	if not theUnit.getPlayerName then return end 
	if not theUnit:getPlayerName() then return end 
	local id = theEvent.id 
	if id == 15 then 
		-- we now have a player birth event. 
		local pName = theUnit:getPlayerName()
		local theGroup = theUnit:getGroup()
		if not theGroup then return end 
		local gName = theGroup:getName()
		if not gName then return end 
		if jtacGrpUI.verbose then 
			trigger.action.outText("+++jGUI: birth player. installing JTAC for <" .. pName .. "> on unit <" .. uName .. ">", 30)
		end 
		local conf = jtacGrpUI.getConfigByGroupName(gName)		
		if conf then 
			jtacGrpUI.removeCommsFromConfig(conf) -- remove menus 
			jtacGrpUI.resetConfig(conf) -- re-init this group for when it re-appears
		end 
		
		jtacGrpUI.setCommsMenu(theGroup)
	end 
end


--
-- Start 
--
function jtacGrpUI.readConfigZone()
	local theZone = cfxZones.getZoneByName("jtacGrpUIConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("jtacGrpUIConfig") 
	end 
	jtacGrpUI.name = "jtacGrpUI"
	
	jtacGrpUI.jtacTypes = theZone:getStringFromZoneProperty("jtacTypes", "all")
	jtacGrpUI.jtacTypes = string.lower(jtacGrpUI.jtacTypes)
	
	jtacGrpUI.jtacSound = theZone:getStringFromZoneProperty("jtacSound", "UI_SCI-FI_Tone_Bright_Dry_20_stereo.wav")

	if theZone:hasProperty("attachTo:") then 
		local attachTo = theZone:getStringFromZoneProperty("attachTo:", "<none>")
		if radioMenu then 
			local mainMenu = radioMenu.mainMenus[attachTo]
			if mainMenu then 
				jtacGrpUI.mainMenu = mainMenu 
			else 
				trigger.action.outText("+++jtacGrpUI: cannot find super menu <" .. attachTo .. ">", 30)
			end
		else 
			trigger.action.outText("+++jtacGrpUI: REQUIRES radioMenu to run before jtacGrpUI. 'AttachTo:' ignored.", 30)
		end 
	end

	jtacGrpUI.verbose = theZone.verbose 

end

function jtacGrpUI.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx jtac GUI requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx jtac GUI", jtacGrpUI.requiredLibs) then
		return false 
	end
	
	jtacGrpUI.readConfigZone()
	
	local allPlayerUnits = dcsCommon.getAllExistingPlayerUnitsRaw()
	for unitName, theUnit in pairs(allPlayerUnits) do 
		jtacGrpUI.setCommsMenuForUnit(theUnit)
	end
	
	-- now install event handler
	world.addEventHandler(jtacGrpUI)
	trigger.action.outText("cf/x jtacGrpUI v" .. jtacGrpUI.version .. " started", 30)
	return true 
end

-- GO GO GO 
if not jtacGrpUI.start() then 
	trigger.action.outText("JTAC GUI failed to start up.", 30)
	jtacGrpUI = nil 
end

--[[--
	TODO:
		callback into GroundTroops lazing
		what is 'simpleCommand' really for? remove or refine 
--]]--