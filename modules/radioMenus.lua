radioMenu = {}
radioMenu.version = "4.1.0"
radioMenu.verbose = false 
radioMenu.ups = 1 
radioMenu.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"cfxMX",
}
-- note: cfxMX is optional unless using types or groups attributes 
radioMenu.menus = {}
radioMenu.mainMenus = {} -- dict 
radioMenu.lateGroups = {} -- dict by ID 

--[[--
	Version History 
	3.0.0 - new radioMainMenu and attachTo: mechanics 
			cascading radioMainMenu support 
			detect cyclic references
	4.0.0 - added infrastructure for dynamic players (DCS 2.9.6)
		  - added dynamic player support 
	4.0.1 - MX no longer optional, so ask for it
	4.0.2 - ackSnd now also broadcasts to all if no group 
	4.1.0 - outX --> valX verification. putting back in optional outX  
--]]--

function radioMenu.addRadioMenu(theZone)
	table.insert(radioMenu.menus, theZone)
end

function radioMenu.addRadioMainMenu(theZone)
	radioMenu.mainMenus[theZone.name] = theZone 
end 

function radioMenu.getRadioMenuByName(aName) 
	for idx, aZone in pairs(radioMenu.menus) do 
		if aName == aZone.name then return aZone end 
	end
	if radioMenu.verbose then 
		trigger.action.outText("+++radioMenu: no radioMenu with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

function radioMenu.getRadioMainMenuByName(theName)
	return radioMenu.mainMenus[theName]
end

--
-- read zone 
-- 
function radioMenu.lateFilterPlayerForType(theUnit, theZone)
	-- returns true if theUnit matches zone's group criterium 
	-- false otherwise 
	if not theUnit then return false end 
	local theGroup = theUnit:getGroup() 
	local theCat = theGroup:getCategory() -- 0 == aircraft 1 = plance 
	local lateGroupName = theGroup:getName()
	local lateType = theUnit:getTypeName() 
	local allTypes = theZone.menuTypes -- {}
	for idx, aType in pairs(allTypes) do 
		local lowerType = string.lower(aType)
		if dcsCommon.stringStartsWith(lowerType, "helo") or dcsCommon.stringStartsWith(lowerType, "heli") or 
		aType == "helicopter" then 
			if theCat == 1 then return true end 
		elseif lowerType == "plane" or lowerType == "planes" then 
			if theCat == 0 then return true end 
		else 
			if aType == lateType then return true end 
		end 
	end
	return false 
end

function radioMenu.filterPlayerIDForType(theZone)
	-- note: we currently ignore coalition 
	local theIDs = {}
	local allTypes = theZone.menuTypes -- {}
	
	-- now iterate all types, and include any player that matches
	-- note that players may match twice, so we use a dict  
	
	for idx, aType in pairs(allTypes) do 
		local theType = dcsCommon.trim(aType)
		local lowerType = string.lower(theType)
		
		for gName, gData in pairs(cfxMX.playerGroupByName) do 
			-- get coalition of group 
			local coa = cfxMX.groupCoalitionByName[gName]
			if (theZone.coalition == 0 or theZone.coalition == coa) then 
				-- do special types first 
				if dcsCommon.stringStartsWith(lowerType, "helo") or dcsCommon.stringStartsWith(lowerType, "heli") then 
					-- we look for all helicoperts
					if cfxMX.groupTypeByName[gName] == "helicopter" then 
						theIDs[gName] = gData.groupId
						if theZone.verbose or radioMenu.verbose then 
							trigger.action.outText("+++menu: Player Group <" .. gName .. "> matches gen-type helicopter", 30)
						end
					end
				elseif lowerType == "plane" or lowerType == "planes" then 
					-- we look for all planes 
					if cfxMX.groupTypeByName[gName] == "plane" then 
						theIDs[gName] = gData.groupId
						if theZone.verbose or radioMenu.verbose then 
							trigger.action.outText("+++menu: Player Group <" .. gName .. "> matches gen-type plane", 30)
						end
					end
				else
					-- we are looking for a particular type, e.g. A-10A
					-- since groups do not carry the type, but all player
					-- groups are of the same type, we access the first 
					-- unit. Note that this may later break if ED implement 
					-- player groups of mixed type 
					if gData.units and gData.units[1] and gData.units[1].type == theType then 
						theIDs[gName] = gData.groupId
						if theZone.verbose or radioMenu.verbose then 
							trigger.action.outText("+++menu: Player Group <" .. gName .. "> matches type <" .. theType .. ">", 30)
						end
					else 
						
					end
				end
			else 
				if theZone.verbose or radioMenu.verbose then 
					trigger.action.outText("+++menu: type check failed coalition for <" .. gName .. ">", 30)
				end
			end
		end
	end
	return theIDs
end

function radioMenu.lateFilterPlayerForGroup(theUnit, theZone) 
	-- returns true if theUnit matches zone's group criterium 
	-- false otherwise. NO COA CHECK 
	if not theUnit then return false end 
	local theGroup = theUnit:getGroup() 
	local lateGroupName = theGroup:getName()
	for idx, gName in pairs(theZone.menuGroup) do 
		if dcsCommon.stringEndsWith(gName, "*") then 
			-- we must check all group names if they start with the 
			-- the same root. WARNING: CASE-SENSITIVE!!!! 
			gName = dcsCommon.removeEnding(gName, "*")
			if dcsCommon.stringStartsWith(lateGroupName, gName) then 
				-- group match, install menu 
				if theZone.verbose or radioMenu.verbose then 
					trigger.action.outText("+++menu: WILDCARD Player Group <" .. gName .. "*> matched with <" .. mxName .. ">: gID = <" .. gID .. ">", 30)
				end
				return true 
			end
		else 
			if lateGroupName == gName then 
				if theZone.verbose or radioMenu.verbose then 
					trigger.action.outText("+++menu: Player Group <" .. gName .. "> found: <" .. gID .. ">", 30)
				end
				return true 
			end
		end 
	end
	return false 
end

function radioMenu.lateFilterCoaForUnit(theUnit, theZone) 
	if theZone.coalition == 0 then return true end 
	if theZone.coalition == theUnit:getCoalition() then return true end 
	return false
end 

function radioMenu.filterPlayerIDForGroup(theZone)
	-- create an iterable list of groups, separated by commas 
	-- note that we could introduce wildcards for groups later
	local theIDs = {}
	local allGroups = theZone.menuGroup

	for idx, gName in pairs(allGroups) do 
		-- if gName ends in wildcard "*" we process differently 
		gName = dcsCommon.trim(gName)
		if dcsCommon.stringEndsWith(gName, "*") then 
			-- we must check all group names if they start with the 
			-- the same root. WARNING: CASE-SENSITIVE!!!! 
			gName = dcsCommon.removeEnding(gName, "*")
			for mxName, theGroupData in pairs(cfxMX.playerGroupByName) do 
				if dcsCommon.stringStartsWith(mxName, gName) then 
					-- group match, install menu 
					local gID = theGroupData.groupId
					table.insert(theIDs, gID)
					if theZone.verbose or radioMenu.verbose then 
						trigger.action.outText("+++menu: WILDCARD Player Group <" .. gName .. "*> matched with <" .. mxName .. ">: gID = <" .. gID .. ">", 30)
					end
				else
				end
			end
		else 
			local theGroup = cfxMX.playerGroupByName[gName]
			if theGroup then 
				local gID = theGroup.groupId
				table.insert(theIDs, gID)
				if theZone.verbose or radioMenu.verbose then 
					trigger.action.outText("+++menu: Player Group <" .. gName .. "> found: <" .. gID .. ">", 30)
				end
			else 
				trigger.action.outText("+++menu: Player Group <" .. gName .. "> does not exist", 30)
			end
		end 
	end

	return theIDs
end

function radioMenu.lateInstallMenu(theUnit, theZone)
	-- we only add the group-individual menus (type/group).
	-- all higher-level menus have been installed already 
	local theGroup = theUnit:getGroup()
	local grp = theGroup:getID()
	local gName = theGroup:getName()
	radioMenu.lateGroups[grp] = gName 
	if not theZone.rootMenu then theZone.rootMenu = {} end 
	if theZone.attachTo then 
		local mainMenu = theZone.attachTo
		theZone.mainRoot = radioMenu.getMainMenuFor(mainMenu, theZone, grp)
	end 
	if theZone.menuGroup or theZone.menuTypes then
		-- install menu, drop through to below 
	else 
		--trigger.action.outText("late-skipped menu for <" .. theZone.name .. ">, no group or type dependency", 30)
		return 
	end 
	local aRoot = missionCommands.addSubMenuForGroup(grp, theZone.rootName, theZone.mainRoot) 
	theZone.rootMenu[grp] = aRoot
	theZone.mcdA[grp] = 0
	theZone.mcdB[grp] = 0
	theZone.mcdC[grp] = 0
	theZone.mcdD[grp] = 0
	if theZone.itemA then 
		theZone.menuA[grp] = missionCommands.addCommandForGroup(grp, theZone.itemA, theZone.rootMenu[grp], radioMenu.redirectMenuX, {theZone, "A", grp})
	end
	if theZone.itemB then 
		theZone.menuB[grp] = missionCommands.addCommandForGroup(grp, theZone.itemB, theZone.rootMenu[grp], radioMenu.redirectMenuX, {theZone, "B", grp})
	end 
	if theZone.itemC then 
		theZone.menuC[grp] = missionCommands.addCommandForGroup(grp, theZone.itemC, theZone.rootMenu[grp], radioMenu.redirectMenuX, {theZone, "C", grp})
	end 
	if theZone.itemD then 
		theZone.menuD[grp] = missionCommands.addCommandForGroup(grp, theZone.itemD, theZone.rootMenu[grp], radioMenu.redirectMenuX, {theZone, "D", grp})
	end 
	--trigger.action.outText("completed late-add menu for <" .. theZone.name .. "> to <" .. theUnit:getName() .. ">", 30)
end 

function radioMenu.installMenu(theZone)
	local gID = nil 
	if theZone.menuGroup then 
		if not cfxMX then 
			trigger.action.outText("WARNING: radioMenu's group attribute requires the 'cfxMX' module", 30)
			return 
		end
		-- access cfxMX player info for group ID
		gID = radioMenu.filterPlayerIDForGroup(theZone)
	elseif theZone.menuTypes then 
		if not cfxMX then 
			trigger.action.outText("WARNING: radioMenu's type attribute requires the 'cfxMX' module", 30)
			return 
		end
		-- access cxfMX player infor with type match for ID
		gID = radioMenu.filterPlayerIDForType(theZone)
	end
	
	theZone.rootMenu = {}
	theZone.mainRoot = nil -- can be altered with attachTo
	-- see if this menu has an attachTo attribute 
	
	theZone.mcdA = {}
	theZone.mcdB = {}
	theZone.mcdC = {}
	theZone.mcdD = {}
	theZone.mcdA[0] = 0
	theZone.mcdB[0] = 0
	theZone.mcdC[0] = 0
	theZone.mcdD[0] = 0
		
	if theZone.menuGroup or theZone.menuTypes then 
		for idx, grp in pairs(gID) do  
			if theZone.attachTo then 
				local mainMenu = theZone.attachTo
				theZone.mainRoot = radioMenu.getMainMenuFor(mainMenu, theZone, grp)
			end 
			local aRoot = missionCommands.addSubMenuForGroup(grp, theZone.rootName, theZone.mainRoot) 
			theZone.rootMenu[grp] = aRoot
			theZone.mcdA[grp] = 0
			theZone.mcdB[grp] = 0
			theZone.mcdC[grp] = 0
			theZone.mcdD[grp] = 0
		end
	elseif theZone.coalition == 0 then 
		if theZone.attachTo then 
			local mainMenu = theZone.attachTo
			theZone.mainRoot = radioMenu.getMainMenuFor(mainMenu, theZone, 0)
		end 
		theZone.rootMenu[0] = missionCommands.addSubMenu(theZone.rootName, theZone.mainRoot) 
	else 
		if theZone.attachTo then 
			local mainMenu = theZone.attachTo
			theZone.mainRoot = radioMenu.getMainMenuFor(mainMenu, theZone, 0)
		end
		theZone.rootMenu[0] = missionCommands.addSubMenuForCoalition(theZone.coalition, theZone.rootName, theZone.mainRoot)		
	end
	
	if theZone.itemA then -- :hasProperty("itemA") then 
		local menuA = theZone.itemA -- theZone:getStringFromZoneProperty("itemA", "<no A submenu>")
		if theZone.menuGroup or theZone.menuTypes then
			theZone.menuA = {}
			for idx, grp in  pairs(gID) do  
				theZone.menuA[grp] = missionCommands.addCommandForGroup(grp, menuA, theZone.rootMenu[grp], radioMenu.redirectMenuX, {theZone, "A", grp}) 
			end
		elseif theZone.coalition == 0 then 
			theZone.menuA = missionCommands.addCommand(menuA, theZone.rootMenu[0], radioMenu.redirectMenuX, {theZone, "A"})
		else 
			theZone.menuA = missionCommands.addCommandForCoalition(theZone.coalition, menuA, theZone.rootMenu[0], radioMenu.redirectMenuX, {theZone, "A"})
		end 
	end 
	
	if theZone.itemB then --:hasProperty("itemB") then 
		local menuB = theZone.itemB -- :getStringFromZoneProperty("itemB", "<no B submenu>")
		if theZone.menuGroup or theZone.menuTypes then 
			theZone.menuB = {}
			for idx, grp in  pairs(gID) do 
				theZone.menuB[grp] = missionCommands.addCommandForGroup(grp, menuB, theZone.rootMenu[grp], radioMenu.redirectMenuX, {theZone, "B", grp}) 
			end
		elseif theZone.coalition == 0 then 
			theZone.menuB = missionCommands.addCommand(menuB, theZone.rootMenu[0], radioMenu.redirectMenuX, {theZone, "B"})
		else 
			theZone.menuB = missionCommands.addCommandForCoalition(theZone.coalition, menuB, theZone.rootMenu[0], radioMenu.redirectMenuX, {theZone, "B"})
		end
	end

	if theZone.itemC then --:hasProperty("itemC") then 
		local menuC = theZone.itemC -- :getStringFromZoneProperty("itemC", "<no C submenu>")
		if theZone.menuGroup or theZone.menuTypes then 
			theZone.menuC = {}
			for idx, grp in  pairs(gID) do 
				theZone.menuC[grp] = missionCommands.addCommandForGroup(grp, menuC, theZone.rootMenu[grp], radioMenu.redirectMenuX, {theZone, "C", grp}) 
			end
		elseif theZone.coalition == 0 then 
			theZone.menuC = missionCommands.addCommand(menuC, theZone.rootMenu[0], radioMenu.redirectMenuX, {theZone, "C"})
		else 
			theZone.menuC = missionCommands.addCommandForCoalition(theZone.coalition, menuC, theZone.rootMenu[0], radioMenu.redirectMenuX, {theZone, "C"})
		end
	end
	
	if theZone.itemD then  -- :hasProperty("itemD") then 
		local menuD = theZone.itemD -- :getStringFromZoneProperty("itemD", "<no D submenu>")
		if theZone.menuGroup or theZone.menuTypes then 
			theZone.menuD = {}
			for idx, grp in  pairs(gID) do 
				theZone.menuD[grp] = missionCommands.addCommandForGroup(grp, menuD, theZone.rootMenu[grp], radioMenu.redirectMenuX, {theZone, "D", grp}) 
			end
		elseif theZone.coalition == 0 then 
			theZone.menuD = missionCommands.addCommand(menuD, theZone.rootMenu[0], radioMenu.redirectMenuX, {theZone, "D"})
		else 
			theZone.menuD = missionCommands.addCommandForCoalition(theZone.coalition, menuD, theZone.rootMenu[0], radioMenu.redirectMenuX, {theZone, "D"})
		end
	end
end

function radioMenu.createRadioMenuWithZone(theZone)
	theZone.rootName = theZone:getStringFromZoneProperty("radioMenu", "<No Name>")
	
	if theZone:hasProperty("attachTo:") then 
		local attachTo = theZone:getStringFromZoneProperty("attachTo:", "<none>")
		if radioMenu.verbose or theZone.verbose then 
			trigger.action.outText("Menu <" .. theZone.name .. "> will attach to <" .. attachTo .. ">", 30)
		end 
		if not radioMenu.mainMenus[attachTo] then 
			trigger.action.outText("+++rdoM: menu <" .. theZone.name .. "> tries to attachTo unknown radioMainMenu <" .. attachTo .. "> - cancelled.", 30)
		else 
			theZone.attachTo = radioMenu.mainMenus[attachTo]
		end
	end 
	
	-- read items and their stuff 
	if theZone:hasProperty("itemA") then 
		theZone.itemA = theZone:getStringFromZoneProperty("itemA")
	end 
	if theZone:hasProperty("itemB") then 
		theZone.itemB = theZone:getStringFromZoneProperty("itemB")
	end
	if theZone:hasProperty("itemC") then 
		theZone.itemC = theZone:getStringFromZoneProperty("itemC")
	end
	if theZone:hasProperty("itemD") then 
		theZone.itemD = theZone:getStringFromZoneProperty("itemD")
	end
	
	theZone.coalition = theZone:getCoalitionFromZoneProperty("coalition", 0)
	-- groups / types 
	if theZone:hasProperty("group") then 
		theZone.menuGroup = theZone:getStringFromZoneProperty("group", "<none>")
		theZone.menuGroup = dcsCommon.trim(theZone.menuGroup)
	elseif theZone:hasProperty("groups") then 
		theZone.menuGroup = theZone:getStringFromZoneProperty("groups", "<none>")
		theZone.menuGroup = dcsCommon.trim(theZone.menuGroup)
	elseif theZone:hasProperty("type") then 
		theZone.menuTypes = theZone:getStringFromZoneProperty("type", "none")
	elseif theZone:hasProperty("types") then
		theZone.menuTypes = theZone:getStringFromZoneProperty("types", "none")
	end	
	
	-- now process menugroups and create sets to improve later speed 
	if theZone.menuGroup then 
		if dcsCommon.containsString(theZone.menuGroup, ",") then 
			local allGroups = dcsCommon.splitString(theZone.menuGroup, ",")
			allGroups = dcsCommon.trimArray(allGroups)
			theZone.menuGroup = allGroups
		else 
			theZone.menuGroup = {theZone.menuGroup} --table.insert(allGroups, theZone.menuGroup)
		end
	end
	
	if theZone.menuTypes then 
		if dcsCommon.containsString(theZone.menuTypes, ",") then 
			local allTypes = dcsCommon.splitString(theZone.menuTypes, ",")
			allTypes = dcsCommon.trimArray(allTypes)
			theZone.menuTypes = allTypes
		else 
			theZone.menuTypes = {theZone.menuTypes}
		end
	end
	
	theZone.menuVisible = theZone:getBoolFromZoneProperty("menuVisible", true)
	
	-- install menu if not hidden
	if theZone.menuVisible then 
		radioMenu.installMenu(theZone)
	end

	-- get the triggers & methods here 
	theZone.radioMethod = theZone:getStringFromZoneProperty("method", "inc")
	if theZone:hasProperty("radioMethod") then 
		theZone.radioMethod = theZone:getStringFromZoneProperty( "radioMethod", "inc")
	end
	-- note: outX currently overridden with valX 
	theZone.outMethA = theZone:getStringFromZoneProperty("outA", theZone.radioMethod)
	theZone.outMethB = theZone:getStringFromZoneProperty("outB", theZone.radioMethod)
	theZone.outMethC = theZone:getStringFromZoneProperty("outC", theZone.radioMethod)
	theZone.outMethD = theZone:getStringFromZoneProperty("outD", theZone.radioMethod)
	
	theZone.radioTriggerMethod = theZone:getStringFromZoneProperty("radioTriggerMethod", "change")
	
	-- A! to D!
	theZone.itemAChosen = theZone:getStringFromZoneProperty("A!", "*<none>")
	theZone.cooldownA = theZone:getNumberFromZoneProperty("cooldownA", 0)
	theZone.busyA = theZone:getStringFromZoneProperty("busyA", "Please stand by (<s> seconds)")
	if theZone:hasProperty("valA") then 
		theZone.outValA = theZone:getStringFromZoneProperty("valA", 1)
	end
	if theZone:hasProperty("ackA") then 
		theZone.ackA = theZone:getStringFromZoneProperty("ackA", "Acknowledged: A")
	end
	if theZone:hasProperty("ackASnd") then 
		theZone.ackASnd = theZone:getStringFromZoneProperty("ackASnd", "<none>")
	end
	
	theZone.itemBChosen = theZone:getStringFromZoneProperty("B!", "*<none>")
	theZone.cooldownB = theZone:getNumberFromZoneProperty("cooldownB", 0)
	theZone.busyB = theZone:getStringFromZoneProperty("busyB", "Please stand by (<s> seconds)")
	if theZone:hasProperty("valB") then 
		theZone.outValB = theZone:getStringFromZoneProperty("valB", 1)
	end
	if theZone:hasProperty("ackB") then 
		theZone.ackB = theZone:getStringFromZoneProperty("ackB", "Acknowledged: B")
	end
	if theZone:hasProperty("ackBSnd") then 
		theZone.ackBSnd = theZone:getStringFromZoneProperty("ackBSnd", "<none>")
	end
	
	theZone.itemCChosen = theZone:getStringFromZoneProperty("C!", "*<none>")
	theZone.cooldownC = theZone:getNumberFromZoneProperty("cooldownC", 0)
	theZone.busyC = theZone:getStringFromZoneProperty("busyC", "Please stand by (<s> seconds)")
	if theZone:hasProperty("valC") then 
		theZone.outValC = theZone:getStringFromZoneProperty("valC", 1)
	end
	if theZone:hasProperty("ackC") then 
		theZone.ackC = theZone:getStringFromZoneProperty("ackC", "Acknowledged: C")
	end
	if theZone:hasProperty("ackCSnd") then 
		theZone.ackCSnd = theZone:getStringFromZoneProperty("ackCSnd", "<none>")
	end
	
	theZone.itemDChosen = theZone:getStringFromZoneProperty("D!", "*<none>")
	theZone.cooldownD = theZone:getNumberFromZoneProperty("cooldownD", 0)
	theZone.busyD = theZone:getStringFromZoneProperty("busyD", "Please stand by (<s> seconds)")
	if theZone:hasProperty("valD") then 
		theZone.outValD = theZone:getStringFromZoneProperty("valD", 1)
	end	
	if theZone:hasProperty("ackD") then 
		theZone.ackD = theZone:getStringFromZoneProperty("ackD", "Acknowledged: D")
	end
	if theZone:hasProperty("ackDSnd") then 
		theZone.ackDSnd = theZone:getStringFromZoneProperty("ackDSnd", "<none>")
	end
	
	if theZone:hasProperty("removeMenu?") then 
		theZone.removeMenu = theZone:getStringFromZoneProperty( "removeMenu?", "*<none>")
		theZone.lastRemoveMenu = theZone:getFlagValue(theZone.removeMenu)
	end
	
	if theZone:hasProperty("addMenu?") then 
		theZone.addMenu = theZone:getStringFromZoneProperty("addMenu?", "*<none>")
		theZone.lastAddMenu = theZone:getFlagValue(theZone.addMenu)
	end
	
	if radioMenu.verbose or theZone.verbose then 
		trigger.action.outText("+++radioMenu: new radioMenu zone <".. theZone.name ..">", 30)
	end
	
end
function radioMenu.getMainMenuFor(mainMenu, theZone, idx)
	if not idx then idx = 0 end 
	if not mainMenu.rootMenu[idx] then 
		return mainMenu.rootMenu[0] 
	end 
	return mainMenu.rootMenu[idx]
end

function radioMenu.lateInstallMainMenu(theUnit, theZone)
	local theGroup = theUnit:getGroup() 
	local grp = theGroup:getID() 
	local mainRoot = nil 
	if not theZone.rootMenu then theZone.rootMenu = {} end
	if theZone.attachTo then 
		local mainMenu = theZone.attachTo
		mainRoot = radioMenu.getMainMenuFor(mainMenu, theZone, grp)
	end 
	local aRoot = missionCommands.addSubMenuForGroup(grp, theZone.rootName, mainRoot) 
	theZone.rootMenu[grp] = aRoot 
	--trigger.action.outText("menu: late-attached main menu <" .. theZone.name .. "> for unit <" .. theUnit:getName() .. ">", 30)
end

function radioMenu.installMainMenu(theZone)
	local gID = nil -- set of all groups this menu applies to 
	if theZone.menuGroup then 
		if not cfxMX then 
			trigger.action.outText("WARNING: radioMenu's group attribute requires the 'cfxMX' module", 30)
			return 
		end
		-- access cfxMX player info for group ID
		gID = radioMenu.filterPlayerIDForGroup(theZone)
	elseif theZone.menuTypes then 
		if not cfxMX then 
			trigger.action.outText("WARNING: radioMenu's type attribute requires the 'cfxMX' module", 30)
			return 
		end
		-- access cxfMX player infor with type match for ID
		gID = radioMenu.filterPlayerIDForType(theZone)
	end
	
	theZone.rootMenu = {} -- roots by many different things
	local mainRoot = nil 
			
	if theZone.menuGroup or theZone.menuTypes then 
		for idx, grp in pairs(gID) do 
			if theZone.attachTo then 
				local mainMenu = theZone.attachTo
				mainRoot = radioMenu.getMainMenuFor(mainMenu, theZone, grp)
			end 
			local aRoot = missionCommands.addSubMenuForGroup(grp, theZone.rootName, mainRoot) 
			theZone.rootMenu[grp] = aRoot
		end
	elseif theZone.coalition == 0 then 
		if theZone.attachTo then 
			local mainMenu = theZone.attachTo
			mainRoot = radioMenu.getMainMenuFor(mainMenu, theZone, grp)
		end 
		theZone.rootMenu[0] = missionCommands.addSubMenu(theZone.rootName, mainRoot) 
	else 
		if theZone.attachTo then 
			local mainMenu = theZone.attachTo
			mainRoot = radioMenu.getMainMenuFor(mainMenu, theZone, grp)
		end 
		theZone.rootMenu[0] = missionCommands.addSubMenuForCoalition(theZone.coalition, theZone.rootName, mainRoot)		
	end
	
end 

function radioMenu.createRadioMainMenuWithZone(theZone)
	theZone.rootName = theZone:getStringFromZoneProperty("radioMainMenu", "<No Name>")

	if theZone:hasProperty("radioMenu") then 
		trigger.action.outText("+++radM: ERROR: main menu <" .. theZone.name .. "> also has conflicting 'radioMenu' entry", 30)
	end 
	
	-- CASCADING SUPPORT. LOOP DETECTION
	if theZone:hasProperty("attachTo:") then 
		local attachTo = theZone:getStringFromZoneProperty("attachTo:", "<none>")
		if radioMenu.verbose or theZone.verbose then 
			trigger.action.outText("MAIN Menu <" .. theZone.name .. "> wants to attach to <" .. attachTo .. ">", 30)
		end 
		if not radioMenu.mainMenus[attachTo] then
			trigger.action.outText("+++radioMM: MAIN menu <" .. theZone.name .. "> tries to 'attachTo:' unknown radioMainMenu <" .. attachTo .. "> - cancelled.", 30)
		else 
			-- make sure that this zone has been processed 
			local super = radioMenu.mainMenus[attachTo]
			if super.mainDone then 
				theZone.attachTo = super
			else 
				-- we need other zones to be processed before 
				if radioMenu.verbose or theZone.verbose then 
					trigger.action.outText("Main menu <" .. theZone.name .. "> refers to unprocessed zone <" .. attachTo .. ">, deferring.", 30)
				end 
				return false 
			end 
		end
	end 
	
	-- we now create the ROOT menu that all other menu 
	-- items attach to that have this as main menu 
	theZone.coalition = theZone:getCoalitionFromZoneProperty("coalition", 0)
	-- groups / types 
	if theZone:hasProperty("group") then 
		theZone.menuGroup = theZone:getStringFromZoneProperty("group", "<none>")
		theZone.menuGroup = dcsCommon.trim(theZone.menuGroup)
	elseif theZone:hasProperty("groups") then 
		theZone.menuGroup = theZone:getStringFromZoneProperty("groups", "<none>")
		theZone.menuGroup = dcsCommon.trim(theZone.menuGroup)
	elseif theZone:hasProperty("type") then 
		theZone.menuTypes = theZone:getStringFromZoneProperty("type", "none")
	elseif theZone:hasProperty("types") then
		theZone.menuTypes = theZone:getStringFromZoneProperty("types", "none")
	end	

	-- now process menugroups and create sets to improve later speed 
	if theZone.menuGroup then 
		if dcsCommon.containsString(theZone.menuGroup, ",") then 
			local allGroups = dcsCommon.splitString(theZone.menuGroup, ",")
			allGroups = dcsCommon.trimArray(allGroups)
			theZone.menuGroup = allGroups
		else 
			theZone.menuGroup = {theZone.menuGroup} --table.insert(allGroups, theZone.menuGroup)
		end
	end
	
	if theZone.menuTypes then 
		if dcsCommon.containsString(theZone.menuTypes, ",") then 
			local allTypes = dcsCommon.splitString(theZone.menuTypes, ",")
			allTypes = dcsCommon.trimArray(allTypes)
			theZone.menuTypes = allTypes
		else 
			theZone.menuTypes = {theZone.menuTypes}
		end
	end
	
	-- always install this one 
	radioMenu.installMainMenu(theZone)
	theZone.mainDone = true 
	if radioMenu.verbose or theZone.verbose then 
		trigger.action.outText("Main menu <" .. theZone.name .. "> processed", 30)
	end 
	return true 
end 

--
-- Output processing 
--
function radioMenu.radioOutMessage(theMessage, theZone)
	if not theZone then return end 
	c = theZone.coalition
	if c > 0 then 
		trigger.action.outTextForCoalition(c, theMessage, 30)
	else
		trigger.action.outText(theMessage, 30)
	end
end

function radioMenu.processHMS(msg, delta)
	-- moved to dcsCommon 
	return dcsCommon.processHMS(msg, delta)
end

function radioMenu.radioOutMsg(ack, gid, theZone)
	-- group processing. only if gid>0 and cfxMX 
	local theMsg = ack
	if (gid > 0) and cfxMX then 
		local gName = cfxMX.groupNamesByID[gid]
		if not gName then gName = radioMenu.lateGroups[gid] end 
		if not gName then gName = "?*?*?" end 
		theMsg = theMsg:gsub("<group>", gName)
	end

	-- for the time being, we can't support many wildcards 
	-- leave them in, and simply proceed 
	-- note that theZone is the radio Menu zone!
	theMsg = cfxZones.processStringWildcards(theMsg, theZone)
	c = theZone.coalition
	
	if gid > 0 then 
		trigger.action.outTextForGroup(gid, theMsg, 30)
	elseif c > 0 then
		trigger.action.outTextForCoalition(c, theMsg, 30)	
	else 
		trigger.action.outText(theMsg, 30)
	end
end

--
-- Menu Branching
--
function radioMenu.redirectMenuX(args)
	-- we use indirection to be able to debug code better
	timer.scheduleFunction(radioMenu.doMenuX, args, timer.getTime() + 0.1)
end

function radioMenu.cdByGID(cd, theZone, gID)
	if not gID then gID = 0 end 
	--if not gID then return cd[0] end 
	return cd[gID]
end

function radioMenu.setCDByGID(cd, theZone, gID, newVal)
	if not gID then gID = 0 end
		--theZone[cd] = newVal 
		-- 
	--end
	local allCD = theZone[cd]
	allCD[gID] = newVal
	theZone[cd] = allCD
end

function radioMenu.doMenuX(args)
	local theZone = args[1]
	local theItemIndex = args[2] -- A, B , C .. ?
	local theGroup = args[3] -- can be nil or groupID 
	if not theGroup then theGroup = 0 end 
	
	local cd = radioMenu.cdByGID(theZone.mcdA, theZone, theGroup) --theZone.mcdA
	local busy = theZone.busyA 
	local theFlag = theZone.itemAChosen
	local outVal = theZone.outValA
	local ack = theZone.ackA 
	local ackSnd = theZone.ackASnd
	local meth = theZone.outMethA -- currently not used 
	
	-- decode A..X
	if theItemIndex == "B"then 
		cd = radioMenu.cdByGID(theZone.mcdB, theZone, theGroup) -- theZone.mcdB
		busy = theZone.busyB 
		theFlag = theZone.itemBChosen
		outVal = theZone.outValB
		ack = theZone.ackB 
		ackSnd = theZone.ackBSnd
		meth = theZone.outMethB
	elseif theItemIndex == "C" then 
		cd = radioMenu.cdByGID(theZone.mcdC, theZone, theGroup) -- theZone.mcdC
		busy = theZone.busyC 
		theFlag = theZone.itemCChosen
		outVal = theZone.outValC
		ack = theZone.ackC 
		ackSnd = theZone.ackCSnd
		meth = theZone.outMethC
	elseif theItemIndex == "D" then 
		cd = radioMenu.cdByGID(theZone.mcdD, theZone, theGroup) -- theZone.mcdD
		busy = theZone.busyD 
		theFlag = theZone.itemDChosen
		outVal = theZone.outValD
		ack = theZone.ackD
		ackSnd = theZone.ackDSnd
		meth = theZone.outMethD
	end
	
	-- see if we are on cooldown 
	local now = timer.getTime()
	if now < cd then 
		-- we are on cooldown.
		local msg = radioMenu.processHMS(busy, cd - now)
		radioMenu.radioOutMsg(msg, theGroup, theZone)
		--radioMenu.radioOutMessage(msg, theZone)
		return 
	else
		-- see if we have an acknowledge
		local gid = theGroup 
		if ack then 
			radioMenu.radioOutMsg(ack, gid, theZone)
		end
		if ackSnd then 
			if (not gid) or gid == 0 then 
				trigger.action.outSound(ackSnd)
			else 
				trigger.action.outSoundForGroup(gid, ackSnd)
			end
		end 
	end
	
	-- set new cooldown -- needs own decoder A..X
	if theItemIndex == "A" then
		radioMenu.setCDByGID("mcdA", theZone, theGroup, now + theZone.cooldownA)
	elseif theItemIndex == "B" then
		radioMenu.setCDByGID("mcdB", theZone, theGroup, now + theZone.cooldownB)
	elseif theItemIndex == "C" then 
		radioMenu.setCDByGID("mcdC", theZone, theGroup, now + theZone.cooldownC)
	else 
		radioMenu.setCDByGID("mcdD", theZone, theGroup, now + theZone.cooldownD)
	end
	
	-- poll flag, override with outVal if set 
	if outVal then 
		--outVal = "#"..outVal -- we force immediate mode
		-- now replaced by 'valX' attribute 
		theZone:pollFlag(theFlag, outVal)
		if theZone.verbose or radioMenu.verbose then 
			trigger.action.outText("+++menu: overriding index " .. theItemIndex .. " output method <" .. theZone.radioMethod .. "> with immediate value <" .. outVal .. ">", 30)
		end
	else 
		theZone:pollFlag(theFlag, theZone.radioMethod)
		if theZone.verbose or radioMenu.verbose then 
			trigger.action.outText("+++menu: banging with <" .. theZone.radioMethod .. "> on <" .. theFlag .. "> for " .. theZone.name, 30)
		end
	end 
	
end

--
-- Update -- required when we can enable/disable a zone's menu
--
function radioMenu.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(radioMenu.update, {}, timer.getTime() + 1/radioMenu.ups)
	
	-- iterate all menus
	for idx, theZone in pairs(radioMenu.menus) do 
		if theZone.removeMenu 
		and theZone:testZoneFlag(theZone.removeMenu, theZone.radioTriggerMethod, "lastRemoveMenu") 
		and theZone.menuVisible
		then 			
			if theZone.menuGroup or theZone.menuTypes then 
				for gID, aRoot in pairs(theZone.rootMenu) do 
					missionCommands.removeItemForGroup(gID, aRoot) 
				end
			elseif theZone.coalition == 0 then 
				missionCommands.removeItem(theZone.rootMenu[0]) 
			else 
				missionCommands.removeItemForCoalition(theZone.coalition, theZone.rootMenu[0]) 
			end
			
			theZone.menuVisible = false 
		end
		
		if theZone.addMenu 
		and theZone:testZoneFlag(theZone.addMenu, theZone.radioTriggerMethod, "lastAddMenu") 
		and (not theZone.menuVisible)
		then 
			if theZone.verbose or radioMenu.verbose then 
				trigger.action.outText("+++menu: adding menu from <" .. theZone.name .. ">", 30)
			end 
			
			radioMenu.installMenu(theZone) -- auto-handles coalition
			theZone.menuVisible = true 
		end
	end
end

--
-- onEvent - late dynamic spawns
--
function radioMenu.lateMenuAddForUnit(theUnit)
	-- iterate all menu zones and determine if this menu is to 
	-- install 
	local uName = theUnit:getName()
	for zName, theZone in pairs(radioMenu.mainMenus) do 
		-- determine if this applies to us, and if so, install 
		-- for unit. only do this if menuGroups or menuTypes present
		-- all others are set on coa level or higher 
		--trigger.action.outText("late-proccing MAIN menu <" .. zName ..">", 30)
		if theZone.menuGroup then 
			if radioMenu.lateFilterCoaForUnit(theUnit, theZone) and 
			radioMenu.lateFilterPlayerForGroup(theUnit, theZone) then 
				radioMenu.lateInstallMainMenu(theUnit, theZone)
			else 
				--trigger.action.outText("menu: skipped GROUP main menu <" .. zName .. "> add for <" .. uName .. ">", 30)
			end
		elseif theZone.menuTypes then 
			if radioMenu.lateFilterCoaForUnit(theUnit, theZone) and 
			radioMenu.lateFilterPlayerForType(theUnit, theZone) then 
				radioMenu.lateInstallMainMenu(theUnit, theZone)
			else 
				--trigger.action.outText("menu: skipped TYPE main menu <" .. zName .. "> add for <" .. uName .. ">", 30)
			end 
		else 
			-- nothing to do, was attached for coalition or higher 
			--trigger.action.outText("menu: did not late-install main menu <" .. zName .. ">, no group or type restrictions", 30)
		end
	end 
	
	for idx, theZone in pairs(radioMenu.menus) do 
		-- again, does this apply to us?
		--trigger.action.outText("late-proccing menu <" .. theZone.name ..">", 30)
		if theZone.menuGroup then 
			if radioMenu.lateFilterCoaForUnit(theUnit, theZone) and 
			radioMenu.lateFilterPlayerForGroup(theUnit, theZone) then 
				radioMenu.lateInstallMenu(theUnit, theZone)
			else 
				--trigger.action.outText("menu: skipped GROUP main menu <" .. theZone.name .. "> add for <" .. uName .. ">", 30)
			end
		elseif theZone.menuTypes then 
			if radioMenu.lateFilterCoaForUnit(theUnit, theZone) and 
			radioMenu.lateFilterPlayerForType(theUnit, theZone) then 
				radioMenu.lateInstallMenu(theUnit, theZone)
			else 
				--trigger.action.outText("menu: skipped TYPE main menu <" .. theZone.name .. "> add for <" .. uName .. ">", 30)
			end 
		else 
			-- nothing to do, was attached for coalition or higher 
			--trigger.action.outText("menu: did not late-install STD menu <" .. theZone.name .. ">, no group or type restrictions", 30)
		end
	end 
end 


function radioMenu:onEvent(event)
	if not event then return end 
	if not event.initiator then return end 
	local theUnit = event.initiator
	if event.id == 15 then 
		if not cfxMX.isDynamicPlayer(theUnit) then return end 
		-- we have a dynamic unit spawn 
		--trigger.action.outText("menu: detected dynamic spawn <" .. theUnit:getName() .. ">", 30)
		radioMenu.lateMenuAddForUnit(theUnit)
	end
end

--
-- Config & Start
--
function radioMenu.readConfigZone()
	local theZone = cfxZones.getZoneByName("radioMenuConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("radioMenuConfig") 
	end 
	radioMenu.verbose = theZone:getBoolFromZoneProperty("verbose", false)
end

function radioMenu.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx radioMenu requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx radioMenu", radioMenu.requiredLibs) then
		return false 
	end
	
	-- read config 
	radioMenu.readConfigZone()
	
	-- process radioMainMenu top-level zones 
	--local filtered = {}
	local tries = 0 
	local attrZones = cfxZones.getZonesWithAttributeNamed("radioMainMenu")
	-- set up all zones so they can 'reach up' even if not yet procced 
	for k, aZone in pairs (attrZones) do 
		radioMenu.addRadioMainMenu(aZone)
	end 
	
	-- now process, and detect/break cyclic references 
	repeat 
		local filtered = {}
		for k, aZone in pairs(attrZones) do 
			radioMenu.createRadioMainMenuWithZone(aZone) -- process attributes
			if aZone.mainDone then 
				-- all good
			else 
				-- wait for next round 
				table.insert(filtered, aZone)
			end 
		end
		done = dcsCommon.getSizeOfTable(filtered) < 1 
		tries = tries + 1 
		attrZones = filtered
	until done or tries > 20
	if tries > 20 then 
		local msg = "+++radioMenu: ERROR: Cyclic references in menu structure, can't fully process main menus. Unresolved main menus are:\n "
		local c = 0
		for idx, theZone in pairs(attrZones) do 
			if c > 0 then msg = msg .. ", " else c = 1 end
			msg = msg .. theZone.name 
		end 
		trigger.action.outText(msg .. ".", 30)
	end 
		
	-- process radioMenu Zones 
	-- old style
	local rmZones = cfxZones.getZonesWithAttributeNamed("radioMenu")	
	for k, aZone in pairs(rmZones) do 
		radioMenu.createRadioMenuWithZone(aZone) -- process attributes
		radioMenu.addRadioMenu(aZone) -- add to list
	end
	
	-- install late spawn detector 
	world.addEventHandler(radioMenu) 
	
	-- start update 
	radioMenu.update()
	
	trigger.action.outText("cfx radioMenu v" .. radioMenu.version .. " started.", 30)
	return true 
end

-- let's go!
if not radioMenu.start() then 
	trigger.action.outText("cfx radioMenu aborted: missing libraries", 30)
	radioMenu = nil 
end

--[[--
	check CD/standby code for multiple groups 

	add/remove for mainmenu 
	visible/invisible for main menus 
	
--]]--