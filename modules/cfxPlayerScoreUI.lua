cfxPlayerScoreUI = {}
cfxPlayerScoreUI.version = "1.0.3"
--[[-- VERSION HISTORY
 - 1.0.2 - initial version 
 - 1.0.3 - module check
		 
--]]--

-- WARNING: REQUIRES cfxPlayerScore to work. 
-- WARNING: ASSUMES SINGLE_PLAYER GROUPS!
cfxPlayerScoreUI.requiredLibs = {
	"cfxPlayerScore", -- this is doing score keeping
	"cfxPlayer", -- player events, comms 
}
-- find & command cfxGroundTroops-based jtacs
-- UI installed via OTHER for all groups with players
-- module based on xxxGrpUI and jtacUI
 
cfxPlayerScoreUI.groupConfig = {} -- all inited group private config data 
cfxPlayerScoreUI.simpleCommands = true -- if true, f10 other invokes directly

--
-- C O N F I G   H A N D L I N G 
-- =============================
--
-- Each group has their own config block that can be used to 
-- store group-private data and configuration items.
--

function cfxPlayerScoreUI.resetConfig(conf)
end

function cfxPlayerScoreUI.createDefaultConfig(theGroup)
	local conf = {}
	conf.theGroup = theGroup
	conf.name = theGroup:getName()
	conf.id = theGroup:getID()
	conf.coalition = theGroup:getCoalition() 
	
	cfxPlayerScoreUI.resetConfig(conf)

	conf.mainMenu = nil; -- this is where we store the main menu if we branch
	conf.myCommands = nil; -- this is where we store the commands if we branch 
	
	return conf
end

-- getConfigFor group will allocate if doesn't exist in DB
-- and add to it
function cfxPlayerScoreUI.getConfigForGroup(theGroup)
	if not theGroup then 
		trigger.action.outText("+++WARNING: cfxPlayerScoreUI nil group in getConfigForGroup!", 30)
		return nil 
	end
	local theName = theGroup:getName()
	local c = cfxPlayerScoreUI.getConfigByGroupName(theName) -- we use central accessor
	if not c then 
		c = cfxPlayerScoreUI.createDefaultConfig(theGroup)
		cfxPlayerScoreUI.groupConfig[theName] = c -- should use central accessor...
	end
	return c 
end

function cfxPlayerScoreUI.getConfigByGroupName(theName) -- DOES NOT allocate when not exist
	if not theName then return nil end 
	return cfxPlayerScoreUI.groupConfig[theName]
end


function cfxPlayerScoreUI.getConfigForUnit(theUnit)
	-- simple one-off step by accessing the group 
	if not theUnit then 
		trigger.action.outText("+++WARNING: cfxPlayerScoreUI nil unit in getConfigForUnit!", 30)
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
 function cfxPlayerScoreUI.clearCommsSubmenus(conf)
	if conf.myCommands then 
		for i=1, #conf.myCommands do
			missionCommands.removeItemForGroup(conf.id, conf.myCommands[i])
		end
	end
	conf.myCommands = {}
end

function cfxPlayerScoreUI.removeCommsFromConfig(conf)
	cfxPlayerScoreUI.clearCommsSubmenus(conf)
	
	if conf.myMainMenu then 
		missionCommands.removeItemForGroup(conf.id, conf.myMainMenu) 
		conf.myMainMenu = nil
	end
end

-- this only works in single-unit groups. may want to check if group 
-- has disappeared
function cfxPlayerScoreUI.removeCommsForUnit(theUnit)
	if not theUnit then return end
	if not theUnit:isExist() then return end 	
	-- perhaps add code: check if group is empty
	local conf = cfxPlayerScoreUI.getConfigForUnit(theUnit)
	cfxPlayerScoreUI.removeCommsFromConfig(conf)
end

function cfxPlayerScoreUI.removeCommsForGroup(theGroup)
	if not theGroup then return end
	if not theGroup:isExist() then return end 	
	local conf = cfxPlayerScoreUI.getConfigForGroup(theGroup)
	cfxPlayerScoreUI.removeCommsFromConfig(conf)
end

--
-- set main root in F10 Other. All sub menus click into this 
--
--function cfxPlayerScoreUI.isEligibleForMenu(theGroup)
--	return true
--end

function cfxPlayerScoreUI.setCommsMenuForUnit(theUnit)
	if not theUnit then 
		trigger.action.outText("+++WARNING: cfxPlayerScoreUI nil UNIT in setCommsMenuForUnit!", 30)
		return
	end
	if not theUnit:isExist() then return end 
	
	local theGroup = theUnit:getGroup()
	cfxPlayerScoreUI.setCommsMenu(theGroup)
end

function cfxPlayerScoreUI.setCommsMenu(theGroup)
	-- depending on own load state, we set the command structure
	-- it begins at 10-other, and has 'grpUI' as main menu with submenus
	-- as required 
	if not theGroup then return end
	if not theGroup:isExist() then return end 
	
	-- we test here if this group qualifies for 
	-- the menu. if not, exit 
	--if not cfxPlayerScoreUI.isEligibleForMenu(theGroup) then return end
	
	local conf = cfxPlayerScoreUI.getConfigForGroup(theGroup) 
	conf.id = theGroup:getID(); -- we do this ALWAYS so it is current even after a crash 

	
	if cfxPlayerScoreUI.simpleCommands then 
		-- we install directly in F-10 other 
		if not conf.myMainMenu then 
			local commandTxt = "Score / Kills"
			local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				nil,
				cfxPlayerScoreUI.redirectCommandX, 
				{conf, "score"}
				)
			conf.myMainMenu = theCommand
		end
		
		return 
	end
	
	
	-- ok, first, if we don't have an F-10 menu, create one 
	if not (conf.myMainMenu) then 
		conf.myMainMenu = missionCommands.addSubMenuForGroup(conf.id, 'Score / Kills') 
	end
	
	-- clear out existing commands
	cfxPlayerScoreUI.clearCommsSubmenus(conf)
	
	-- now we have a menu without submenus. 
	-- add our own submenus
	cfxPlayerScoreUI.addSubMenus(conf)
	
end

function cfxPlayerScoreUI.addSubMenus(conf)
	-- add menu items to choose from after 
	-- user clickedf on MAIN MENU. In this implementation
	-- they all result invoked methods
	
	local commandTxt = "Show Score / Kills"
	local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				cfxPlayerScoreUI.redirectCommandX, 
				{conf, "score"}
				)
	table.insert(conf.myCommands, theCommand)

end

--
-- each menu item has a redirect and timed invoke to divorce from the
-- no-debug zone in the menu invocation. Delay is .1 seconds
--

function cfxPlayerScoreUI.redirectCommandX(args)
	timer.scheduleFunction(cfxPlayerScoreUI.doCommandX, args, timer.getTime() + 0.1)
end

function cfxPlayerScoreUI.doCommandX(args)
	local conf = args[1] -- < conf in here
	local what = args[2] -- < second argument in here
	local theGroup = conf.theGroup
	-- now fetch the first player that drives a unit in this group
	-- a simpler method would be to access conf.primeUnit 
	
	local playerName, playerUnit = cfxPlayer.getFirstGroupPlayerName(theGroup)
	if playerName == nil or playerUnit == nil then 
		trigger.action.outText("scoreUI: nil player name or unit for group " .. theGroup:getName(), 30)
		return 
	end
	
	
	local desc = cfxPlayerScore.scoreTextForPlayerNamed(playerName)
	
	trigger.action.outTextForGroup(conf.id, desc, 30)
	trigger.action.outSoundForGroup(conf.id, "Quest Snare 3.wav")

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
function cfxPlayerScoreUI.playerChangeEvent(evType, description, player, data)

	if evType == "newGroup" then 

		cfxPlayerScoreUI.setCommsMenu(data.group)

		return 
	end
	
	if evType == "removeGroup" then 

		-- we must remove the comms menu for this group else we try to add another one to this group later
		local conf = cfxPlayerScoreUI.getConfigByGroupName(data.name)
		
		if conf then 
			cfxPlayerScoreUI.removeCommsFromConfig(conf) -- remove menus 
			cfxPlayerScoreUI.resetConfig(conf) -- re-init this group for when it re-appears
		else 
			trigger.action.outText("+++ scoreUI: can't retrieve group <" .. data.name .. "> config: not found!", 30)
		end
		
		return
	end
	
end

--
-- Start 
--

function cfxPlayerScoreUI.start()
	if not dcsCommon.libCheck("cfx PlayerScoreUI", 
							  cfxPlayerScoreUI.requiredLibs) 
	then 
		return false 
	end
	-- iterate existing groups so we have a start situation
	-- now iterate through all player groups and install the Assault Troop Menu
	allPlayerGroups = cfxPlayerGroups -- cfxPlayerGroups is a global, don't fuck with it! 
	-- contains per group player record. Does not resolve on unit level!
	for gname, pgroup in pairs(allPlayerGroups) do 
		local theUnit = pgroup.primeUnit -- get any unit of that group
		cfxPlayerScoreUI.setCommsMenuForUnit(theUnit) -- set up
	end
	-- now install the new group notifier to install Assault Troops menu
	
	cfxPlayer.addMonitor(cfxPlayerScoreUI.playerChangeEvent)
	trigger.action.outText("cf/x cfxPlayerScoreUI v" .. cfxPlayerScoreUI.version .. " started", 30)
	return true 
end

--
-- GO GO GO 
--
 
if not cfxPlayerScoreUI.start() then 
	cfxPlayerScoreUI = nil
	trigger.action.outText("cf/x PlayerScore UI aborted: missing libraries", 30)
end
