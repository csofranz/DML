cfxReconGUI = {}
cfxReconGUI.version = "1.0.0"
--[[-- VERSION HISTORY
 - 1.0.0 - initial version 
		 
--]]--
-- find & command cfxGroundTroops-based jtacs
-- UI installed via OTHER for all groups with players
-- module based on xxxGrpUI
 
cfxReconGUI.groupConfig = {} -- all inited group private config data 
cfxReconGUI.simpleCommands = true -- if true, f10 other invokes directly

--
-- C O N F I G   H A N D L I N G 
-- =============================
--
-- Each group has their own config block that can be used to 
-- store group-private data and configuration items.
--

function cfxReconGUI.resetConfig(conf)
	if conf.scouting then 
		-- after a crash or other, reset
		cfxReconMode.removeScout(conf.unit)
		trigger.action.outTextForGroup(conf.id, "Lost contact to scout...", 30)
	end
	conf.scouting = false -- if true, we are currently scouting.
end

function cfxReconGUI.createDefaultConfig(theGroup)
	local conf = {}
	conf.theGroup = theGroup
	conf.name = theGroup:getName()
	conf.id = theGroup:getID()
	conf.coalition = theGroup:getCoalition() 
	
	local groupUnits = theGroup:getUnits()
	conf.unit = groupUnits[1] -- WARNING: ASSUMES ONE-UNIT GROUPS
	cfxReconGUI.resetConfig(conf)

	conf.mainMenu = nil; -- this is where we store the main menu if we branch
	conf.myCommands = nil; -- this is where we store the commands if we branch 
	
	return conf
end

-- getConfigFor group will allocate if doesn't exist in DB
-- and add to it
function cfxReconGUI.getConfigForGroup(theGroup)
	if not theGroup then 
		trigger.action.outText("+++WARNING: cfxReconGUI nil group in getConfigForGroup!", 30)
		return nil 
	end
	local theName = theGroup:getName()
	local c = cfxReconGUI.getConfigByGroupName(theName) -- we use central accessor
	if not c then 
		c = cfxReconGUI.createDefaultConfig(theGroup)
		cfxReconGUI.groupConfig[theName] = c -- should use central accessor...
	end
	return c 
end

function cfxReconGUI.getConfigByGroupName(theName) -- DOES NOT allocate when not exist
	if not theName then return nil end 
	return cfxReconGUI.groupConfig[theName]
end


function cfxReconGUI.getConfigForUnit(theUnit)
	-- simple one-off step by accessing the group 
	if not theUnit then 
		trigger.action.outText("+++WARNING: cfxReconGUI nil unit in getConfigForUnit!", 30)
		return nil 
	end
	
	local theGroup = theUnit:getGroup()
	local conf = getConfigForGroup(theGroup)
	conf.unit = theUnit 
	return conf 
end

--
--
-- M E N U   H A N D L I N G 
-- =========================
--
--
 function cfxReconGUI.clearCommsSubmenus(conf)
	if conf.myCommands then 
		for i=1, #conf.myCommands do
			missionCommands.removeItemForGroup(conf.id, conf.myCommands[i])
		end
	end
	conf.myCommands = {}
end

function cfxReconGUI.removeCommsFromConfig(conf)
	cfxReconGUI.clearCommsSubmenus(conf)
	
	if conf.myMainMenu then 
		missionCommands.removeItemForGroup(conf.id, conf.myMainMenu) 
		conf.myMainMenu = nil
	end
end

-- this only works in single-unit groups. may want to check if group 
-- has disappeared
function cfxReconGUI.removeCommsForUnit(theUnit)
	if not theUnit then return end
	if not theUnit:isExist() then return end 	
	-- perhaps add code: check if group is empty
	local conf = cfxReconGUI.getConfigForUnit(theUnit)
	cfxReconGUI.removeCommsFromConfig(conf)
end

function cfxReconGUI.removeCommsForGroup(theGroup)
	if not theGroup then return end
	if not theGroup:isExist() then return end 	
	local conf = cfxReconGUI.getConfigForGroup(theGroup)
	cfxReconGUI.removeCommsFromConfig(conf)
end

--
-- set main root in F10 Other. All sub menus click into this 
--
function cfxReconGUI.isEligibleForMenu(theGroup)
	return true
end

function cfxReconGUI.setCommsMenuForUnit(theUnit)
	if not theUnit then 
		trigger.action.outText("+++WARNING: cfxReconGUI nil UNIT in setCommsMenuForUnit!", 30)
		return
	end
	if not theUnit:isExist() then 
		trigger.action.outText("+++WARNING: cfxReconGUI unit:ISEXIST() failed in setCommsMenuForUnit!", 30)
		return 
	end 
	
	local theGroup = theUnit:getGroup()
	cfxReconGUI.setCommsMenu(theGroup)
end

function cfxReconGUI.setCommsMenu(theGroup)
	-- depending on own load state, we set the command structure
	-- it begins at 10-other, and has 'jtac' as main menu with submenus
	-- as required 
	if not theGroup then return end
	if not theGroup:isExist() then return end 
	
	-- we test here if this group qualifies for 
	-- the menu. if not, exit 
	if not cfxReconGUI.isEligibleForMenu(theGroup) then return end
	
	local conf = cfxReconGUI.getConfigForGroup(theGroup) 
	conf.id = theGroup:getID(); -- we do this ALWAYS so it is current even after a crash 
--	trigger.action.outText("+++ setting group <".. conf.theGroup:getName() .. "> jtac command", 30)
	
	if cfxReconGUI.simpleCommands then 
		-- we install directly in F-10 other 
		if not conf.myMainMenu then 
			local commandTxt = "Recon: "
			local unitName = "bogus"
			if conf.unit and conf.unit:isExist() then
				unitName = conf.unit:getName()
			elseif conf.unit then 
				trigger.action.outText("+++Recon: ISEXIST failed for unit in comms setup!", 30)
				commandTxt = commandTxt .. "***"
			else
				trigger.action.outText("+++Recon: NIL unit in comms setup!", 30)
				commandTxt = commandTxt .. "***"
			end
	
			if conf.scouting then 
				commandTxt = commandTxt .. " Stop Reporting"
			else 
				commandTxt = commandTxt .. " Commence Reports"
			end
			local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				nil,
				cfxReconGUI.redirectCommandX, 
				{conf, "recon", unitName}
				)
			conf.myMainMenu = theCommand
		end
		
		return 
	end
	
	
	-- ok, first, if we don't have an F-10 menu, create one 
	if not (conf.myMainMenu) then 
		conf.myMainMenu = missionCommands.addSubMenuForGroup(conf.id, 'Recon') 
	end
	
	-- clear out existing commands
	cfxReconGUI.clearCommsSubmenus(conf)
	
	-- now we have a menu without submenus. 
	-- add our own submenus
	cfxReconGUI.addSubMenus(conf)
	
end

function cfxReconGUI.addSubMenus(conf)
	-- add menu items to choose from after 
	-- user clickedf on MAIN MENU. In this implementation
	-- they all result invoked methods
	
	local commandTxt = "Recon"
	local unitName = "bogus"
	if conf.unit and conf.unit:getName()then
		unitName = conf.unit:getName()
	else 
		trigger.action.outTextForCoalition("+++Recon: no unit in comms setup!", message, 30)
		commandTxt = commandTxt .. "***"
	end
	
	local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				cfxReconGUI.redirectCommandX, 
				{conf, "recon", unitName}
				)
	table.insert(conf.myCommands, theCommand)
--[[--
	commandTxt = "This is another important command"
	theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				cfxReconGUI.redirectCommandX, 
				{conf, "Sub2"}
				)
	table.insert(conf.myCommands, theCommand)
--]]--
end

--
-- each menu item has a redirect and timed invoke to divorce from the
-- no-debug zone in the menu invocation. Delay is .1 seconds
--

function cfxReconGUI.redirectCommandX(args)
	timer.scheduleFunction(cfxReconGUI.doCommandX, args, timer.getTime() + 0.1)
end

function cfxReconGUI.doCommandX(args)
	local conf = args[1] -- < conf in here
	local what = args[2] -- < second argument in here
	local unitName = args[3]
	if not unitName then 
		trigger.action.outText("+++ reconUI: doCommand: UNDEF unitName!", 30)
		return 
	elseif unitName == "bogus" then 
		trigger.action.outText("+++ reconUI: doCommand: BOGUS unitName!", 30)
	end
	
	local theGroup = conf.theGroup
--	trigger.action.outTextForGroup(conf.id, "+++ groupUI: processing comms menu for <" .. what .. ">", 30)
	
	-- whenever we get here, we toggle the recon mode
	local theUnit = conf.unit 
	local message = "Scout ".. unitName .. " has stopped reporting."
	local theSide = conf.coalition
	if conf.scouting then 
		-- end recon 
		cfxReconMode.removeScoutByName(unitName)
		if theUnit:isExist() then 
			message = theUnit:getName() .. " folds map, recon terminated."
		end
		conf.scouting = false 
	else 
		-- start recon
		if theUnit and theUnit:isExist() then 
			cfxReconMode.addScout(theUnit)
			message = theUnit:getName() .. " reports bright eyes, commencing recon."
			conf.scouting = true 
		else 
			message = "+++ reconGUI: " .. unitName .. " has invalid unit"
		end 
	end
	trigger.action.outTextForCoalition(theSide, message, 30)

	-- reset comms 
	cfxReconGUI.removeCommsForGroup(theGroup)
	cfxReconGUI.setCommsMenu(theGroup)
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
function cfxReconGUI.playerChangeEvent(evType, description, player, data)
	--trigger.action.outText("+++ groupUI: received <".. evType .. "> Event", 30)
	if evType == "newGroup" then 
		-- initialized attributes are in data as follows
		--   .group - new group 
		--   .name - new group's name 
		--   .primeUnit - the unit that trigggered new group appearing 
		--   .primeUnitName - name of prime unit 
		--   .id group ID 
		--theUnit = data.primeUnit
		-- ensure group data exists and is updated
		local conf = cfxReconGUI.getConfigForGroup(data.group)
		conf.unit = data.primeUnit
		conf.unitName = conf.unit:getName() -- will break if no exist
		
		cfxReconGUI.setCommsMenu(data.group)
--		trigger.action.outText("+++ groupUI: added " .. theUnit:getName() .. " to comms menu", 30)
		return 
	end
	
	if evType == "removeGroup" then 
		-- data is the player record that no longer exists. it consists of
		--  .name 
		-- we must remove the comms menu for this group else we try to add another one to this group later
		local conf = cfxReconGUI.getConfigByGroupName(data.name)
		
		if conf then 
			cfxReconGUI.removeCommsFromConfig(conf) -- remove menus 
			cfxReconGUI.resetConfig(conf) -- re-init this group for when it re-appears
		else 
			trigger.action.outText("+++ reconUI: can't retrieve group <" .. data.name .. "> config: not found!", 30)
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
function cfxReconGUI.start()

	-- iterate existing groups so we have a start situation
	-- now iterate through all player groups and install the Assault Troop Menu
	allPlayerGroups = cfxPlayerGroups -- cfxPlayerGroups is a global, don't fuck with it! 
	-- contains per group player record. Does not resolve on unit level!
	for gname, pgroup in pairs(allPlayerGroups) do 
		local theUnit = pgroup.primeUnit -- get any unit of that group
		cfxReconGUI.setCommsMenuForUnit(theUnit) -- set up
	end
	-- now install the new group notifier to install Assault Troops menu
	
	cfxPlayer.addMonitor(cfxReconGUI.playerChangeEvent)
	trigger.action.outText("cf/x cfxReconGUI v" .. cfxReconGUI.version .. " started", 30)
	
end

--
-- GO GO GO 
--
if not cfxReconMode then 
	trigger.action.outText("cf/x cfxReconGUI REQUIRES cfxReconMode to work.", 30)
else 
	cfxReconGUI.start()
end