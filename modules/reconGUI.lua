cfxReconGUI = {}
cfxReconGUI.version = "2.0.0"
--[[-- VERSION HISTORY
 - 1.0.0 - initial version 
 - 2.0.0 - removed dependence on cfxPlayer 
         - compatible with dynamically spawning players 
		 - cleanup
--]]--

cfxReconGUI.groupConfig = {} -- all inited group private config data 
cfxReconGUI.simpleCommands = true -- if true, f10 other invokes directly
cfxReconGUI.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
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
-- M E N U   H A N D L I N G 
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

-- this only works in single-unit groups
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
	-- it begins at F10-Other, and has 'Recon' as main menu with submenus
	-- as required 
	if not theGroup then return end
	if not theGroup:isExist() then return end 
	
	-- we test here if this group qualifies for 
	-- the menu. if not, exit 
	if not cfxReconGUI.isEligibleForMenu(theGroup) then return end
	
	local conf = cfxReconGUI.getConfigForGroup(theGroup) 
	conf.id = theGroup:getID(); -- we ALWAYSdo this 
	
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
	
	-- if we don't have an F-10 menu, create one 
	if not (conf.myMainMenu) then 
		conf.myMainMenu = missionCommands.addSubMenuForGroup(conf.id, 'Recon') 
	end
	-- clear out existing commands
	cfxReconGUI.clearCommsSubmenus(conf)
	-- add our own submenus
	cfxReconGUI.addSubMenus(conf)	
end

function cfxReconGUI.addSubMenus(conf)
	local commandTxt = "Recon"
	local unitName = "bogus"
	if conf.unit and conf.unit:getName()then
		unitName = conf.unit:getName()
	else 
		trigger.action.outTextForCoalition("+++Recon: no unit in comms setup!", message, 30)
		commandTxt = commandTxt .. "***"
	end
	
	local theCommand =  missionCommands.addCommandForGroup(conf.id, commandTxt, conf.myMainMenu, cfxReconGUI.redirectCommandX, {conf, "recon", unitName})
	table.insert(conf.myCommands, theCommand)
end

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
	-- when we get here, we toggle the recon mode
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

function cfxReconGUI:onEvent(theEvent)
	if not theEvent then return end 
	if not theEvent.initiator then return end 
	local theUnit = theEvent.initiator 
	if not Unit.isExist(theUnit) then return end 
	if not theUnit.getName then return end 
	if not theUnit.getGroup then return end 
	if not theUnit.getPlayerName then return end 
	if not theUnit:getPlayerName() then return end 
	local theGroup = theUnit:getGroup() 
	if theEvent.id == 15 then 
		-- BIRTH EVENT PLAYER 
		local conf = cfxReconGUI.getConfigForGroup(theGroup)
		conf.unit = theUnit --data.primeUnit
		conf.unitName = theUnit:getName()
		cfxReconGUI.setCommsMenu(theGroup)
	end
end

--
-- Start 
--
function cfxReconGUI.start()
	-- lib check 
	if not dcsCommon.libCheck("cfx Recon Mode", 
		cfxReconMode.requiredLibs) then
		return false 
	end
	
	-- iterate existing groups so we have a start situation
	local allPlayerUnits = dcsCommon.getAllExistingPlayerUnitsRaw()
	for idx, theUnit in pairs(allPlayerUnits) do 
		cfxReconGUI.setCommsMenuForUnit(theUnit) 
	end 

	world.addEventHandler(cfxReconGUI)
	
	trigger.action.outText("cf/x cfxReconGUI v" .. cfxReconGUI.version .. " started", 30)
	return true 
end

--
-- GO GO GO 
--
if not cfxReconMode then 
	trigger.action.outText("cf/x cfxReconGUI REQUIRES cfxReconMode to work.", 30)
else 
	cfxReconGUI.start()
end