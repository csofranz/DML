cfxArtilleryUI = {}
cfxArtilleryUI.version = "1.1.0"
cfxArtilleryUI.requiredLibs = {
	"dcsCommon", -- always
	"cfxPlayer", -- get all players
	"cfxZones", -- Zones, of course 
	"cfxArtilleryZones", -- this is where we get zones from 	
}
--
-- UI for ArtilleryZones module, implements LOS, Observer, SMOKE
-- Copyright (c) 2021, 2022 by Christian Franz and cf/x AG

--[[-- VERSION HISTORY
 - 1.0.0 - based on jtacGrpUI
 - 1.0.1 - tgtCheckSum 
         - smokeCheckSum
         - ability to smoke target zone in range
 - 1.1.0 - config zone
         - allowPlanes flag  
		 - config smoke color 
		 - collect zones recognizes moving zones, updates landHeight
		 - allSeeing god mode attribute: always observing.
		 - allRanging god mode attribute: always in range.
		 
 
--]]--
cfxArtilleryUI.allowPlanes = false -- if false, heli only  
cfxArtilleryUI.smokeColor = "red" -- for smoking target zone 

-- find artiller zones, command fire
cfxArtilleryUI.updateDelay = 1 -- seconds until we update target list  
cfxArtilleryUI.groupConfig = {} -- all inited group private config data 
cfxArtilleryUI.updateSound = "UI_SCI-FI_Tone_Bright_Dry_20_stereo.wav"
cfxArtilleryUI.maxSmokeDist = 30000 -- in meters. Distance to target to populate smoke menu 
--
-- C O N F I G   H A N D L I N G 
-- =============================
--
-- Each group has their own config block that can be used to 
-- store group-private data and configuration items.
--

function cfxArtilleryUI.resetConfig(conf)
	conf.tgtCheckSum = nil -- used to determine if we need to update target menu
	conf.smokeCheckSum = nil -- used to determine if we need to update smoke menu 
end

function cfxArtilleryUI.createDefaultConfig(theGroup)
	local conf = {}
	conf.theGroup = theGroup
	conf.name = theGroup:getName()
	conf.id = theGroup:getID()
	conf.coalition = theGroup:getCoalition() 
	
	cfxArtilleryUI.resetConfig(conf)

	conf.mainMenu = nil; -- this is where we store the main menu if we branch
	conf.myCommands = nil; -- this is where we store the commands if we branch 
	
	return conf
end

-- getConfigFor group will allocate if doesn't exist in DB
-- and add to it
function cfxArtilleryUI.getConfigForGroup(theGroup)
	if not theGroup then 
		trigger.action.outText("+++WARNING: cfxArtilleryUI nil group in getConfigForGroup!", 30)
		return nil 
	end
	local theName = theGroup:getName()
	local c = cfxArtilleryUI.getConfigByGroupName(theName) -- we use central accessor
	if not c then 
		c = cfxArtilleryUI.createDefaultConfig(theGroup)
		cfxArtilleryUI.groupConfig[theName] = c -- should use central accessor...
	end
	return c 
end

function cfxArtilleryUI.getConfigByGroupName(theName) -- DOES NOT allocate when not exist
	if not theName then return nil end 
	return cfxArtilleryUI.groupConfig[theName]
end


function cfxArtilleryUI.getConfigForUnit(theUnit)
	-- simple one-off step by accessing the group 
	if not theUnit then 
		trigger.action.outText("+++WARNING: cfxArtilleryUI nil unit in getConfigForUnit!", 30)
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
function cfxArtilleryUI.clearCommsTargets(conf)
	if conf.myTargets then 
		for i=1, #conf.myTargets do
			missionCommands.removeItemForGroup(conf.id, conf.myTargets[i])
		end	
	end
	conf.myTargets={}
	conf.tgtCheckSum = nil 
end

function cfxArtilleryUI.clearCommsSmokes(conf)
	if conf.mySmokes then 
		for i=1, #conf.mySmokes do
			missionCommands.removeItemForGroup(conf.id, conf.mySmokes[i])
		end	
	end
	conf.mySmokes={}
	conf.smokeCheckSum = nil 
end


function cfxArtilleryUI.clearCommsSubmenus(conf)
	if conf.myCommands then 
		for i=1, #conf.myCommands do
			missionCommands.removeItemForGroup(conf.id, conf.myCommands[i])
		end
	end
	conf.myCommands = {}
	
	-- now clear target menu 
	cfxArtilleryUI.clearCommsTargets(conf)
	if conf.myTargetMenu then 
		missionCommands.removeItemForGroup(conf.id, conf.myTargetMenu) 
		conf.myTargetMenu = nil
	end
	
	-- now clear smoke menu
	cfxArtilleryUI.clearCommsSmokes(conf)
	if conf.mySmokeMenu then 
		missionCommands.removeItemForGroup(conf.id, conf.mySmokeMenu) 
		conf.mySmokeMenu = nil
	end
	
end

function cfxArtilleryUI.removeCommsFromConfig(conf)
	cfxArtilleryUI.clearCommsSubmenus(conf)
	
	if conf.myMainMenu then 
		missionCommands.removeItemForGroup(conf.id, conf.myMainMenu) 
		conf.myMainMenu = nil
	end
end

-- this only works in single-unit groups. may want to check if group 
-- has disappeared
function cfxArtilleryUI.removeCommsForUnit(theUnit)
	if not theUnit then return end
	if not theUnit:isExist() then return end 	
	-- perhaps add code: check if group is empty
	local conf = cfxArtilleryUI.getConfigForUnit(theUnit)
	cfxArtilleryUI.removeCommsFromConfig(conf)
end

function cfxArtilleryUI.removeCommsForGroup(theGroup)
	if not theGroup then return end
	if not theGroup:isExist() then return end 	
	local conf = cfxArtilleryUI.getConfigForGroup(theGroup)
	cfxArtilleryUI.removeCommsFromConfig(conf)
end

--
-- set main root in F10 Other. All sub menus click into this 
--
function cfxArtilleryUI.isEligibleForMenu(theGroup)
	if cfxArtilleryUI.allowPlanes then return true end 
	
	-- only allow helicopters for Forward Observervation
	local cat = theGroup:getCategory()
	if cat ~= Group.Category.HELICOPTER then return false end
	return true
end

function cfxArtilleryUI.setCommsMenuForUnit(theUnit)
	if not theUnit then 
		trigger.action.outText("+++WARNING: cfxArtilleryUI nil UNIT in setCommsMenuForUnit!", 30)
		return
	end
	if not theUnit:isExist() then return end 
	
	local theGroup = theUnit:getGroup()
	cfxArtilleryUI.setCommsMenu(theGroup)
end

function cfxArtilleryUI.setCommsMenu(theGroup)
	-- depending on own load state, we set the command structure
	-- it begins at 10-other, and has 'jtac' as main menu with submenus
	-- as required 
	if not theGroup then return end
	if not theGroup:isExist() then return end 
	
	-- we test here if this group qualifies for 
	-- the menu. if not, exit 
	if not cfxArtilleryUI.isEligibleForMenu(theGroup) then return end
	
	local conf = cfxArtilleryUI.getConfigForGroup(theGroup) 
	conf.id = theGroup:getID(); -- we do this ALWAYS so it is current even after a crash 
	
	-- ok, first, if we don't have an F-10 menu, create one 
	if not (conf.myMainMenu) then 
		conf.myMainMenu = missionCommands.addSubMenuForGroup(conf.id, 'Forward Observer') 
		
	end
	
	-- clear out existing commands
	cfxArtilleryUI.clearCommsSubmenus(conf)
	
	-- now we have a menu without submenus. 
	-- add our own submenus
	cfxArtilleryUI.addSubMenus(conf)
	
end


function cfxArtilleryUI.addSubMenus(conf)
	-- add menu items to choose from after 
	-- user clickedf on MAIN MENU. In this implementation
	-- they all result invoked methods
	
	local commandTxt = "List Artillery Targets"
	local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				cfxArtilleryUI.redirectCommandListTargets, 
				{conf, "arty list"}
				)
	table.insert(conf.myCommands, theCommand)

	-- add a targets menu. this will be regularly set (every x seconds) 
	conf.myTargetMenu = missionCommands.addSubMenuForGroup(conf.id, 'Artillery Fire Control', conf.myMainMenu) 
		
	-- populate this target menu with commands 
	-- creates a tgtCheckSum to very each time 
	cfxArtilleryUI.populateTargetMenu(conf)
	
	conf.mySmokeMenu = missionCommands.addSubMenuForGroup(conf.id, 'Mark Artillery Target', conf.myMainMenu)
	cfxArtilleryUI.populateSmokeMenu(conf)

end

function cfxArtilleryUI.populateTargetMenu(conf)
	local targetList = cfxArtilleryUI.collectArtyTargets(conf)
	-- iterate the list
	
	-- we use a control string to know if we have to change 
	local tgtCheckSum = ""
	-- now filter target list 
	local filteredTargets = {}
	for idx, aTarget in pairs(targetList) do 
		local inRange = cfxArtilleryUI.allRanging or aTarget.range * 1000 < aTarget.spotRange 
		if inRange then 
			isVisible = cfxArtilleryUI.allSeeing or land.isVisible(aTarget.here, aTarget.there)
			if isVisible then 
				table.insert(filteredTargets, aTarget)
				tgtCheckSum = tgtCheckSum .. aTarget.name
			end
		end
	end
	
	-- now compare old control string with new, and only 
	-- re-populate if the old is different 
	if tgtCheckSum == conf.tgtCheckSum then 
--		trigger.action.outText("*** yeah old targets", 30)
		return 
	elseif not conf.tgtCheckSum then 
--		trigger.action.outText("+++ new target menu", 30)
	else 
		trigger.action.outTextForGroup(conf.id, "Artillery target updates", 30)
		trigger.action.outSoundForGroup(conf.id, cfxArtilleryUI.updateSound)
--		trigger.action.outText("!!! target update ", 30)	
	end
	
	-- we need to re-populate. erase old values 
	cfxArtilleryUI.clearCommsTargets(conf)
	conf.tgtCheckSum = tgtCheckSum -- remember for last time 
	--trigger.action.outText("new targets", 30)
	
	if #filteredTargets < 1 then 
		-- simply put one-line dummy in there 
		local commandTxt = "(No unobscured target areas)"
		local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myTargetMenu,
				cfxArtilleryUI.dummyCommand, 
				{conf, "nix is"}
				)
		table.insert(conf.myTargets, theCommand)
		return 
	end
	
	-- now populate target menu, max 8 items
	local numTargets = #filteredTargets
	if numTargets > 8 then numTargets = 8 end 
	for i=1, numTargets do 
		-- make a target command for each 
		local aTarget = filteredTargets[i]
	
		commandTxt = "Fire at: <" .. aTarget.name .. ">"
		theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myTargetMenu,
				cfxArtilleryUI.redirectFireCommand, 
				{conf, aTarget}
				)
		table.insert(conf.myTargets, theCommand)
	end
end

function cfxArtilleryUI.populateSmokeMenu(conf)
	local targetList = cfxArtilleryUI.collectArtyTargets(conf) -- we can use target gathering 
	
	-- now iterate the reulting list
	-- we use a control string to know if we have to change 
	local smokeCheckSum = ""
	-- now filter target list 
	local filteredTargets = {}
	for idx, aTarget in pairs(targetList) do 
		local inRange = cfxArtilleryUI.allRanging or aTarget.range * 1000 < cfxArtilleryUI.maxSmokeDist
		if inRange then 
			table.insert(filteredTargets, aTarget)
			smokeCheckSum = smokeCheckSum .. aTarget.name
		end
	end
	
	-- now compare old control string with new, and only 
	-- re-populate if the old is different 
	if smokeCheckSum == conf.smokeCheckSum then 
		-- nothing changed since last time, do nothing and return immediately
		return 
	end
	
	-- we need to re-populate. erase old values 
	cfxArtilleryUI.clearCommsSmokes(conf)
	conf.smokeCheckSum = smokeCheckSum -- remember for last time 
	
	if #filteredTargets < 1 then 
		-- simply put one-line dummy in there 
		local commandTxt = "(No targets in range)"
		local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.mySmokeMenu,
				cfxArtilleryUI.dummyCommand, -- the "nix is" command
				{conf, "nix is"}
				)
		table.insert(conf.mySmokes, theCommand)
		return 
	end
	
	-- now populate target menu, max 8 items
	local numTargets = #filteredTargets
	if numTargets > 10 then numTargets = 10 end 
	for i=1, numTargets do 
		-- make a target command for each 
		local aTarget = filteredTargets[i]
	
		commandTxt = "Smoke <" .. aTarget.name .. ">"
		theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.mySmokeMenu,
				cfxArtilleryUI.redirectSmokeCommand, 
				{conf, aTarget}
				)
		table.insert(conf.mySmokes, theCommand)
	end
end

--
-- each menu item has a redirect and timed invoke to divorce from the
-- no-debug zone in the menu invocation. Delay is .1 seconds
--
function cfxArtilleryUI.dummyCommand(args)
	-- do nothing, dummy!
end

function cfxArtilleryUI.redirectFireCommand(args)
	timer.scheduleFunction(cfxArtilleryUI.doFireCommand, args, timer.getTime() + 0.1)
end

function cfxArtilleryUI.doFireCommand(args)
	local conf = args[1] -- < conf in here
	local aTarget = args[2] -- < second argument in here
	local theGroup = conf.theGroup
	local now = timer.getTime()
	-- recalc range since it may be 10 seconds old
	local here = dcsCommon.getGroupLocation(theGroup)
	local there = aTarget.there 
	local lRange = dcsCommon.dist(here, there)
	aTarget.range = lRange/1000
	aTarget.range = math.floor(aTarget.range * 10) / 10
	local inTime = cfxArtilleryUI.allTiming or now > aTarget.zone.artyCooldownTimer	
	if inTime then 
		-- invoke fire command for artyZone 
		trigger.action.outTextForGroup(conf.id, "Roger, " .. theGroup:getName() .. ", firing at " .. aTarget.name, 30)
		if cfxArtilleryUI.allRanging then lRange = 1 end -- max accuracy
		cfxArtilleryZones.simFireAtZone(aTarget.zone, theGroup, lRange)
	else
		-- way want to stay silent and simply iterate?
		trigger.action.outTextForGroup(conf.id, "Artillery is reloading", 30)
	end		
end

--
-- SMOKE EM
--

function cfxArtilleryUI.redirectSmokeCommand(args)
	timer.scheduleFunction(cfxArtilleryUI.doSmokeCommand, args, timer.getTime() + 0.1)
end

function cfxArtilleryUI.doSmokeCommand(args)
	local conf = args[1] -- < conf in here
	local aTarget = args[2] -- < second argument in here
	local theGroup = conf.theGroup
	-- invoke smoke command for artyZone 
	trigger.action.outTextForGroup(conf.id, "Roger, " .. theGroup:getName() .. ", marking " .. aTarget.name, 30)
	cfxArtilleryZones.simSmokeZone(aTarget.zone, theGroup, cfxArtilleryUI.smokeColor)
end

--
--
--

function cfxArtilleryUI.redirectCommandListTargets(args)
	timer.scheduleFunction(cfxArtilleryUI.doCommandListTargets, args, timer.getTime() + 0.1)
end

function cfxArtilleryUI.doCommandListTargets(args)
	local conf = args[1] -- < conf in here
	local what = args[2] -- < second argument in here
	local theGroup = conf.theGroup
--	trigger.action.outTextForGroup(conf.id, "+++ groupUI: processing comms menu for <" .. what .. ">", 30)
	local targetList = cfxArtilleryUI.collectArtyTargets(conf)
	-- iterate the list
	if #targetList < 1 then 
		trigger.action.outTextForGroup(conf.id, "\nArtillery Targets:\nNo active artillery targets\n", 30)
		return 
	end
	
	local desc = "Artillery Targets:\n"
--	trigger.action.outTextForGroup(conf.id, "Target Report:", 30)
	for i=1, #targetList do 
		local aTarget = targetList[i]
		local inRange = cfxArtilleryUI.allRanging or aTarget.range * 1000 < aTarget.spotRange 
		if inRange then 
			isVisible = cfxArtilleryUI.allSeeing or land.isVisible(aTarget.here, aTarget.there)
			if isVisible then 
				desc = desc .. "\n" .. aTarget.name .. " - OBSERVING"
			else 
				desc = desc .. "\n" .. aTarget.name .. " - TARGET OBSCURED"
			end
		else 
			desc = desc .. "\n" .. aTarget.name .. " [" .. aTarget.range .. "km at " .. aTarget.bearing .. "°]"
		end
		
	end
	trigger.action.outTextForGroup(conf.id, desc .. "\n", 30, true)
end

function cfxArtilleryUI.collectArtyTargets(conf)
	-- iterate all target zones, for those that are on my side
	-- calculate range, bearing, and then order by distance 
	
	local theTargets = {}
	for idx, aZone in pairs(cfxArtilleryZones.artilleryZones) do 
		if aZone.coalition == conf.coalition then 
			table.insert(theTargets, aZone)
		end
	end
	
	-- we now have a list of all Arty target Zones
	-- get bearing and range to targets, and sort them accordingly
	-- WARNING: aTarget.range is in KILOmeters!
	local targetList = {}
	local here = dcsCommon.getGroupLocation(conf.theGroup) -- this is me
	
	for idx, aZone in pairs (theTargets) do
		local aTarget = {}
		-- establish our location 
		aTarget.zone = aZone 
		aTarget.name = aZone.name 
		aTarget.here = here 
		--aTarget.targetName = aZone.name 
		aTarget.spotRange = aZone.spotRange
		-- get the target we are lazing 
		local zP = cfxZones.getPoint(aZone) -- zone can move!
		aZone.landHeight = land.getHeight({x = zP.x, y= zP.z})
		local there = {x = zP.x, y = aZone.landHeight + 1, z=zP.z}
		aTarget.there = there 
		aTarget.range = dcsCommon.dist(here, there) / 1000 -- (in km)
		
		aTarget.range = math.floor(aTarget.range * 10) / 10
		aTarget.bearing = dcsCommon.bearingInDegreesFromAtoB(here, there)
		--aTarget.jtacName = troop.name 
		table.insert(targetList, aTarget)
	end
	
	-- now sort by range 
	table.sort(targetList, function (left, right) return left.range < right.range end )
	
	-- return list sorted by distance
	return targetList
end




function cfxArtilleryUI.redirectCommandFire(args)
	timer.scheduleFunction(cfxArtilleryUI.doCommandFire, args, timer.getTime() + 0.1)
end

function cfxArtilleryUI.doCommandFire(args)
	local conf = args[1] -- < conf in here
	local what = args[2] -- < second argument in here
	local theGroup = conf.theGroup
	
	-- sort all arty groups by distance 
	local targetList = cfxArtilleryUI.collectArtyTargets(conf, true)
	
	if #targetList < 1 then 
		trigger.action.outTextForGroup(conf.id, "You are currently not observing a target zone. Move closer.", 30)
		return 
	end
	local now = timer.getTime()
	-- for all that we are in range, that are visible and that can fire
	for idx, aTarget in pairs(targetList) do 
		local inRange = (aTarget.range * 1000 < aTarget.spotRange) or cfxArtilleryUI.allRanging
		local inTime = cfxArtilleryUI.allTiming or now > aTarget.zone.artyCooldownTimer
		if inRange then 
			isVisible = cfxArtilleryUI.allSeeing or land.isVisible(aTarget.here, aTarget.there)
			if isVisible then 
				if inTime then 
					-- invoke fire command for artyZone 
					cfxArtilleryZones.simFireAtZone(aTarget.zone, theGroup, aTarget.range)
					-- return -- we only fire one zone
				else
					-- way want to stay silent and simply iterate?
					trigger.action.outTextForGroup(conf.id, "Artillery reloading", 30)
				end
			end
			return -- after the first in range we stop, no matter what
		else 
			-- not interesting
		end
	end

	-- issue a fire command 
	
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
function cfxArtilleryUI.playerChangeEvent(evType, description, player, data)
	--trigger.action.outText("+++ groupUI: received <".. evType .. "> Event", 30)
	if evType == "newGroup" then 
		-- initialized attributes are in data as follows
		--   .group - new group 
		--   .name - new group's name 
		--   .primeUnit - the unit that trigggered new group appearing 
		--   .primeUnitName - name of prime unit 
		--   .id group ID 
		--theUnit = data.primeUnit
		cfxArtilleryUI.setCommsMenu(data.group)

		return 
	end
	
	if evType == "removeGroup" then 
		-- data is the player record that no longer exists. it consists of
		--  .name 
		-- we must remove the comms menu for this group else we try to add another one to this group later
		local conf = cfxArtilleryUI.getConfigByGroupName(data.name)
		
		if conf then 
			cfxArtilleryUI.removeCommsFromConfig(conf) -- remove menus 
			cfxArtilleryUI.resetConfig(conf) -- re-init this group for when it re-appears
		else 
			trigger.action.outText("+++ jtacUI: can't retrieve group <" .. data.name .. "> config: not found!", 30)
		end
		
		return
	end
	
	if evType == "leave" then
		-- player unit left.  
	end
	
	if evType == "unit" then 
		-- player changed units.
	end
	
end

--
-- update 
-- 

function cfxArtilleryUI.updateGroup(theGroup)
	if not theGroup then return end
	if not theGroup:isExist() then return end 	
	-- we test here if this group qualifies for 
	-- the menu. if not, exit 
	if not cfxArtilleryUI.isEligibleForMenu(theGroup) then return end
	local conf = cfxArtilleryUI.getConfigForGroup(theGroup) 
	conf.id = theGroup:getID(); -- we do this ALWAYS
	-- populateTargetMenu erases old settings by itself 
	cfxArtilleryUI.populateTargetMenu(conf) -- update targets 
	cfxArtilleryUI.populateSmokeMenu(conf) -- update targets 
end

function cfxArtilleryUI.update()
	-- reschedule myself in x seconds 
	timer.scheduleFunction(cfxArtilleryUI.update, {}, timer.getTime() + cfxArtilleryUI.updateDelay)
	
	-- iterate all groups, and rebuild their target menus 
	local allPlayerGroups = cfxPlayerGroups -- cfxPlayerGroups is a global, don't fuck with it! 
	-- contains per group player record. Does not resolve on unit level!
	for gname, pgroup in pairs(allPlayerGroups) do 
		local theUnit = pgroup.primeUnit -- single unit groups!
		local theGroup = theUnit:getGroup()
		cfxArtilleryUI.updateGroup(theGroup)
	end
	
end

--
-- Config Zone
--

function cfxArtilleryUI.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("ArtilleryUIConfig") 
	if not theZone then 
		trigger.action.outText("+++A-UI: no config zone!", 30) 
		return 
	end 
	
	trigger.action.outText("+++A-UI: found config zone!", 30) 
	
	cfxArtilleryUI.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	cfxArtilleryUI.allowPlanes = cfxZones.getBoolFromZoneProperty(theZone, "allowPlanes", false)
	cfxArtilleryUI.smokeColor = cfxZones.getSmokeColorStringFromZoneProperty(theZone, "smokeColor", "red")
	cfxArtilleryUI.allSeeing = cfxZones.getBoolFromZoneProperty(theZone, "allSeeing", false)
	cfxArtilleryUI.allRanging = cfxZones.getBoolFromZoneProperty(theZone, "allRanging", false)
	cfxArtilleryUI.allTiming = cfxZones.getBoolFromZoneProperty(theZone, "allTiming", false)
end

--
-- Start 
--
function cfxArtilleryUI.start()
	if not dcsCommon.libCheck("cfx Artillery UI", 
		cfxArtilleryUI.requiredLibs) then
		return false 
	end

	-- read config 
	cfxArtilleryUI.readConfigZone()

	-- iterate existing groups so we have a start situation
	-- now iterate through all player groups and install the Assault Troop Menu
	local allPlayerGroups = cfxPlayerGroups -- cfxPlayerGroups is a global, don't fuck with it! 
	-- contains per group player record. Does not resolve on unit level!
	for gname, pgroup in pairs(allPlayerGroups) do 
		local theUnit = pgroup.primeUnit -- get any unit of that group
		cfxArtilleryUI.setCommsMenuForUnit(theUnit) -- set up
	end
	
	-- now install the new group notifier to install Assault Troops menu
	cfxPlayer.addMonitor(cfxArtilleryUI.playerChangeEvent)
	
	-- run an update loop for the target menu 
	cfxArtilleryUI.update()
	
	trigger.action.outText("cf/x cfxArtilleryUI v" .. cfxArtilleryUI.version .. " started", 30)
	return true
end

--
-- GO GO GO 
--

if not cfxArtilleryUI.start() then 
	trigger.action.outText("Loading cf/x Artillery UI aborted.", 30)
	cfxArtilleryUI = nil 
end

--[[--
TODO: transition times based on distance - requires real bound arty first
DONE: ui for smoking target zone: list ten closest zones, and provide menu to smoke zone 
--]]--