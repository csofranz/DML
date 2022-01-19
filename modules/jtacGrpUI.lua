jtacGrpUI = {}
jtacGrpUI.version = "1.0.2"
--[[-- VERSION HISTORY
 - 1.0.2 - also include idling JTACS
         - add positional info when using owned zones 
		 
--]]--
-- find & command cfxGroundTroops-based jtacs
-- UI installed via OTHER for all groups with players
-- module based on xxxGrpUI
 
jtacGrpUI.groupConfig = {} -- all inited group private config data 
jtacGrpUI.simpleCommands = true -- if true, f10 other invokes directly

--
-- C O N F I G   H A N D L I N G 
-- =============================
--
-- Each group has their own config block that can be used to 
-- store group-private data and configuration items.
--

function jtacGrpUI.resetConfig(conf)
end

function jtacGrpUI.createDefaultConfig(theGroup)
	local conf = {}
	conf.theGroup = theGroup
	conf.name = theGroup:getName()
	conf.id = theGroup:getID()
	conf.coalition = theGroup:getCoalition() 
	
	jtacGrpUI.resetConfig(conf)

	conf.mainMenu = nil; -- this is where we store the main menu if we branch
	conf.myCommands = nil; -- this is where we store the commands if we branch 
	
	return conf
end

-- getConfigFor group will allocate if doesn't exist in DB
-- and add to it
function jtacGrpUI.getConfigForGroup(theGroup)
	if not theGroup then 
		trigger.action.outText("+++WARNING: jtacGrpUI nil group in getConfigForGroup!", 30)
		return nil 
	end
	local theName = theGroup:getName()
	local c = jtacGrpUI.getConfigByGroupName(theName) -- we use central accessor
	if not c then 
		c = jtacGrpUI.createDefaultConfig(theGroup)
		jtacGrpUI.groupConfig[theName] = c -- should use central accessor...
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
--
-- M E N U   H A N D L I N G 
-- =========================
--
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

-- this only works in single-unit groups. may want to check if group 
-- has disappeared
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

--
-- set main root in F10 Other. All sub menus click into this 
--
function jtacGrpUI.isEligibleForMenu(theGroup)
	return true
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
	-- depending on own load state, we set the command structure
	-- it begins at 10-other, and has 'jtac' as main menu with submenus
	-- as required 
	if not theGroup then return end
	if not theGroup:isExist() then return end 
	
	-- we test here if this group qualifies for 
	-- the menu. if not, exit 
	if not jtacGrpUI.isEligibleForMenu(theGroup) then return end
	
	local conf = jtacGrpUI.getConfigForGroup(theGroup) 
	conf.id = theGroup:getID(); -- we do this ALWAYS so it is current even after a crash 
--	trigger.action.outText("+++ setting group <".. conf.theGroup:getName() .. "> jtac command", 30)
	
	if jtacGrpUI.simpleCommands then 
		-- we install directly in F-10 other 
		if not conf.myMainMenu then 
			local commandTxt = "jtac Lasing Report"
			local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				nil,
				jtacGrpUI.redirectCommandX, 
				{conf, "lasing report"}
				)
			conf.myMainMenu = theCommand
		end
		
		return 
	end
	
	
	-- ok, first, if we don't have an F-10 menu, create one 
	if not (conf.myMainMenu) then 
		conf.myMainMenu = missionCommands.addSubMenuForGroup(conf.id, 'jtac') 
	end
	
	-- clear out existing commands
	jtacGrpUI.clearCommsSubmenus(conf)
	
	-- now we have a menu without submenus. 
	-- add our own submenus
	jtacGrpUI.addSubMenus(conf)
	
end

function jtacGrpUI.addSubMenus(conf)
	-- add menu items to choose from after 
	-- user clickedf on MAIN MENU. In this implementation
	-- they all result invoked methods
	
	
	
	local commandTxt = "jtac Lasing Report"
	local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				jtacGrpUI.redirectCommandX, 
				{conf, "lasing report"}
				)
	table.insert(conf.myCommands, theCommand)
--[[--
	commandTxt = "This is another important command"
	theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				jtacGrpUI.redirectCommandX, 
				{conf, "Sub2"}
				)
	table.insert(conf.myCommands, theCommand)
--]]--
end

--
-- each menu item has a redirect and timed invoke to divorce from the
-- no-debug zone in the menu invocation. Delay is .1 seconds
--

function jtacGrpUI.redirectCommandX(args)
	timer.scheduleFunction(jtacGrpUI.doCommandX, args, timer.getTime() + 0.1)
end

function jtacGrpUI.doCommandX(args)
	local conf = args[1] -- < conf in here
	local what = args[2] -- < second argument in here
	local theGroup = conf.theGroup
--	trigger.action.outTextForGroup(conf.id, "+++ groupUI: processing comms menu for <" .. what .. ">", 30)
	local targetList = jtacGrpUI.collectJTACtargets(conf, true)
	-- iterate the list
	if #targetList < 1 then 
		trigger.action.outTextForGroup(conf.id, "No targets are currently being lased", 30)
		return 
	end
	
	local desc = "JTAC Target Report:\n"
--	trigger.action.outTextForGroup(conf.id, "Target Report:", 30)
	for i=1, #targetList do 
		local aTarget = targetList[i]
		if aTarget.idle then 
			desc = desc .. "\n" .. aTarget.jtacName .. aTarget.posInfo ..": no target"
		else 
			desc = desc .. "\n" .. aTarget.jtacName .. aTarget.posInfo .." lasing " .. aTarget.lazeTargetType .. " [" .. aTarget.range .. "nm at " .. aTarget.bearing .. "°]"
		end 
	end
	trigger.action.outTextForGroup(conf.id, desc .. "\n", 30)
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
				local ozRange = dcsCommon.dist(jtacLoc, nearestZone.point) * 0.000621371
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
			--aTarget.jtacName = troop.name 
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
-- G R O U P   M A N A G E M E N T 
--
-- Group Management is required to make sure all groups
-- receive a comms menu and that they receive a clean-up 
-- when required 
--
-- Callbacks are provided by cfxPlayer module to which we
-- subscribe during init 
--
function jtacGrpUI.playerChangeEvent(evType, description, player, data)
	--trigger.action.outText("+++ groupUI: received <".. evType .. "> Event", 30)
	if evType == "newGroup" then 
		-- initialized attributes are in data as follows
		--   .group - new group 
		--   .name - new group's name 
		--   .primeUnit - the unit that trigggered new group appearing 
		--   .primeUnitName - name of prime unit 
		--   .id group ID 
		--theUnit = data.primeUnit
		jtacGrpUI.setCommsMenu(data.group)
--		trigger.action.outText("+++ groupUI: added " .. theUnit:getName() .. " to comms menu", 30)
		return 
	end
	
	if evType == "removeGroup" then 
		-- data is the player record that no longer exists. it consists of
		--  .name 
		-- we must remove the comms menu for this group else we try to add another one to this group later
		local conf = jtacGrpUI.getConfigByGroupName(data.name)
		
		if conf then 
			jtacGrpUI.removeCommsFromConfig(conf) -- remove menus 
			jtacGrpUI.resetConfig(conf) -- re-init this group for when it re-appears
		else 
			trigger.action.outText("+++ jtacUI: can't retrieve group <" .. data.name .. "> config: not found!", 30)
		end
		
		return
	end
	
	if evType == "leave" then
		-- player unit left. we don't care since we only work on group level
		-- if they were the only, this is followed up by group disappeared 
		
	end
	
	if evType == "unit" then 
		-- player changed units. almost never in MP, but possible in solo
		-- because of 1 seconds timing loop 
		-- will result in a new group appearing and a group disappearing, so we are good
		-- may need some logic to clean up old configs and/or menu items 

	end
	
end

--
-- Start 
--
function jtacGrpUI.start()

	-- iterate existing groups so we have a start situation
	-- now iterate through all player groups and install the Assault Troop Menu
	allPlayerGroups = cfxPlayerGroups -- cfxPlayerGroups is a global, don't fuck with it! 
	-- contains per group player record. Does not resolve on unit level!
	for gname, pgroup in pairs(allPlayerGroups) do 
		local theUnit = pgroup.primeUnit -- get any unit of that group
		jtacGrpUI.setCommsMenuForUnit(theUnit) -- set up
	end
	-- now install the new group notifier to install Assault Troops menu
	
	cfxPlayer.addMonitor(jtacGrpUI.playerChangeEvent)
	trigger.action.outText("cf/x jtacGrpUI v" .. jtacGrpUI.version .. " started", 30)
	
end

--
-- GO GO GO 
--
if not cfxGroundTroops then 
	trigger.action.outText("cf/x jtacGrpUI REQUIRES cfxGroundTroops to work.", 30)
else 
	jtacGrpUI.start()
end