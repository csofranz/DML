jtacGrpUI = {}
jtacGrpUI.version = "4.0.0"
jtacGrpUI.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", 
	"cfxGroundTroops", 
}
--[[-- VERSION HISTORY
   3.0.0 - support for attachTo: 
   3.1.0 - support for DCS 2.9.6 jul-11 2024 dynamic player spwans 
   3.2.0 - better guarding access to ownedZones in collectJTACtargets()
   4.0.0 - added support for twn when present 
		 - made report more clear that all pos are requestor-relative 
		 - support for CA (event 20 (enter unit) on ground vehicle)
		 - report now supports wildcards
		 - reports inm two parts: why and what 
		 - "no target" for right side when no "what"
		 - comms mechanic simplification 
		 - lase code from spawner support via ground troops 
--]]--
 
jtacGrpUI.groupConfig = {} -- all inited group private config data, indexed by group name. 

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

-- lazy init: allocate if doesn't exist in DB
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


function jtacGrpUI.getConfigForUnit(theUnit) -- lazy alloc
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
	-- note: no option for ground troops now
	if jtacGrpUI.verbose then 
		trigger.action.outText("+++jGUI: unknown jtacTypes <" .. jtacGrpUI.jtacTypes .. "> -- allowing access to group <" .. theGroup:getName() ..">", 30)
	end 
	return true -- for later expansion 
end

function jtacGrpUI.setCommsMenu(theGroup)
	if not theGroup then return end
	if not Group.isExist(theGroup) then return end 
	if not jtacGrpUI.isEligibleForMenu(theGroup) then return end
	local mainMenu = nil 
	if jtacGrpUI.mainMenu then 
		mainMenu = radioMenu.getMainMenuFor(jtacGrpUI.mainMenu) 
	end 
	
	local conf = jtacGrpUI.getConfigForGroup(theGroup) 
	conf.id = theGroup:getID(); -- we always do this
	local commandTxt = jtacGrpUI.menuName -- "jtac Lasing Report"
	local theCommand =  missionCommands.addCommandForGroup(conf.id, commandTxt, mainMenu, jtacGrpUI.redirectCommandX, {conf, "lasing report"})
	conf.myMainMenu = theCommand
end

function jtacGrpUI.addSubMenus(conf)
	local commandTxt = "jtac Lasing Report"
	local theCommand =  missionCommands.addCommandForGroup(conf.id, commandTxt, conf.myMainMenu, jtacGrpUI.redirectCommandX, {conf, "lasing report"})
	table.insert(conf.myCommands, theCommand)
end

function jtacGrpUI.redirectCommandX(args)
	timer.scheduleFunction(jtacGrpUI.doCommandX, args, timer.getTime() + 0.1)
end

function jtacGrpUI.doCommandX(args)
	local conf = args[1] -- conf
	local what = args[2] -- "xyz" -- not used here
	local theGroup = conf.theGroup
	local targetList = jtacGrpUI.collectJTACtargets(conf, true)
	-- iterate the list
	if #targetList < 1 then 
		trigger.action.outTextForGroup(conf.id, "No targets are currently being lased", 30)
		trigger.action.outSoundForGroup(conf.id, jtacGrpUI.jtacSound)
		return 
	end
	local here = dcsCommon.getGroupLocation(conf.theGroup) -- pos of pilot!
	
	local desc = "JTAC Target Report:\nTargets being laser-designated for " .. conf.name .. ":\n"
	for i=1, #targetList do 
		local aTarget = targetList[i]
		local theUnit = aTarget.source -- lazing unit 
		local code = aTarget.code 
		if not Unit.isExist(theUnit) then 
			desc = desc .. "\n" .. aTarget.jtacName .. ": lost contact."
		elseif aTarget.idle then 
			local lWho = jtacGrpUI.who
			lWho = dcsCommon.processStringWildcardsForUnit(lWho, theUnit)
			local there = theUnit:getPoint()
			lWho = dcsCommon.processAtoBWildCards(lWho, here, there)
			lWho = lWho:gsub("<code>", code)
			desc = desc .. "\n" .. lWho ..": no target"
		else 
			local lWho = dcsCommon.processStringWildcardsForUnit(jtacGrpUI.who, theUnit)
			local there = theUnit:getPoint()
			lWho = dcsCommon.processAtoBWildCards(lWho, here, there)
			lWho = lWho:gsub("<code>", code)
			local lWhat = dcsCommon.processStringWildcardsForUnit(jtacGrpUI.what, aTarget.lazeTarget) -- does unit type 
			there = aTarget.lazeTarget:getPoint()
			lWhat = dcsCommon.processTimeLocWildCards(lWhat, there)
			lWhat = dcsCommon.processAtoBWildCards(lWhat, here, there)
			lWhat = lWhat:gsub("<code>", code)
			desc = desc .. "\n" .. lWho .. lWhat 
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
		aTarget.jtacName = troop.name -- group name 
		aTarget.code = troop.code 
		aTarget.source = dcsCommon.getFirstLivingUnit(troop.group)
		-- we may get idlers, catch them now 
		if not troop.lazeTarget then 
			aTarget.idle = true
			aTarget.range = math.huge
		else 
			-- proc target 
			local there = troop.lazeTarget:getPoint()
			aTarget.idle = false
			aTarget.range = dcsCommon.dist(here, there) * 0.000621371 -- meter to miles 
			aTarget.range = math.floor(aTarget.range * 10) / 10
			aTarget.lazeTarget = troop.lazeTarget
		end
		table.insert(targetList, aTarget)
	end
	
	-- now sort by range 
	table.sort(targetList, function (left, right) return left.range < right.range end )
	
	-- return list sorted by distance
	return targetList
end

--
-- event handler
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
	-- maybe collapse event 15 into 20?
	if id == 20 then -- CA player enter event???
		local theGroup = theUnit:getGroup()
		if not theGroup then return end 
		local gName = theGroup:getName()
		if not gName then return end 
		local cat = theGroup:getCategory()
		if cat == 2 then -- ground! we are in a CA unit!
			local pName = theUnit:getPlayerName()
			if jtacGrpUI.verbose then 
				trigger.action.outText("+++jGUI: CA player unit take-over. installing JTAC for <" .. pName .. "> on unit <" .. uName .. ">", 30)
			end 
			local conf = jtacGrpUI.getConfigByGroupName(gName)		
			if conf then 
				jtacGrpUI.removeCommsFromConfig(conf) -- remove menus 
				jtacGrpUI.resetConfig(conf) -- re-init this group for when it re-appears
			end 
			jtacGrpUI.setCommsMenu(theGroup)
		end
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
	jtacGrpUI.menuName = theZone:getStringFromZoneProperty("menuName", "jtac Lasing Report")

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

	jtacGrpUI.who = theZone:getStringFromZoneProperty("who", "<g><twnnm>")
	--jtacGrpUI.what = theZone:getStringFromZoneProperty("what", " - lasing <typ> [<lat>:<lon>], code=<code>")
	jtacGrpUI.what = theZone:getStringFromZoneProperty("what", " - lasing <typ> [<rngnm>nm, bearing <bea>°], code=<code>")
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
	world.addEventHandler(jtacGrpUI)
	trigger.action.outText("cf/x jtacGrpUI v" .. jtacGrpUI.version .. " started", 30)
	return true 
end

-- GO GO GO 
if not jtacGrpUI.start() then 
	trigger.action.outText("JTAC GUI failed to start up.", 30)
	jtacGrpUI = nil 
end
