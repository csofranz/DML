radioMenu = {}
radioMenu.version = "2.0.1"
radioMenu.verbose = false 
radioMenu.ups = 1 
radioMenu.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
radioMenu.menus = {}

--[[--
	Version History 
	1.0.0 Initial version 
	1.0.1 spelling corrections
	1.1.0 removeMenu 
	      addMenu 
		  menuVisible 
	2.0.0 redesign: handles multiple receivers
		  optional MX module 
		  group option
	      type option
		  multiple group names 
		  multiple types 
		  gereric helo type 
		  generic plane type 
		  type works with coalition 
	2.0.1 corrections to installMenu(), as suggested by GumidekCZ

	
--]]--

function radioMenu.addRadioMenu(theZone)
	table.insert(radioMenu.menus, theZone)
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

--
-- read zone 
-- 
function radioMenu.filterPlayerIDForType(theZone)
	-- note: we currently ignore coalition 
	local theIDs = {}
	local allTypes = {}
	if dcsCommon.containsString(theZone.menuTypes, ",") then 
		allTypes = dcsCommon.splitString(theZone.menuTypes, ",")
	else 
		table.insert(allTypes, theZone.menuTypes)
	end
	
	-- now iterate all types, and include any player that matches
	-- note that a player may match twice, so we use a dict instead of an 
	-- array. Since we later iterate ID by idx, that's not an issue
	
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

function radioMenu.filterPlayerIDForGroup(theZone)
	-- create an iterable list of groups, separated by commas 
	-- note that we could introduce wildcards for groups later
	local theIDs = {}
	local allGroups = {}
	if dcsCommon.containsString(theZone.menuGroup, ",") then 
		allGroups = dcsCommon.splitString(theZone.menuGroup, ",")
	else 
		table.insert(allGroups, theZone.menuGroup)
	end

	for idx, gName in pairs(allGroups) do 
		gName = dcsCommon.trim(gName)
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

	return theIDs
end

function radioMenu.installMenu(theZone)
--	local theGroup = 0 -- was: nil
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
			local aRoot = missionCommands.addSubMenuForGroup(grp, theZone.rootName, nil) 
			theZone.rootMenu[grp] = aRoot
			theZone.mcdA[grp] = 0
			theZone.mcdB[grp] = 0
			theZone.mcdC[grp] = 0
			theZone.mcdD[grp] = 0
		end
	elseif theZone.coalition == 0 then 
		theZone.rootMenu[0] = missionCommands.addSubMenu(theZone.rootName, nil) 
	else 
		theZone.rootMenu[0] = missionCommands.addSubMenuForCoalition(theZone.coalition, theZone.rootName, nil)		
	end
	
	if cfxZones.hasProperty(theZone, "itemA") then 
		local menuA = cfxZones.getStringFromZoneProperty(theZone, "itemA", "<no A submenu>")
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
	
	if cfxZones.hasProperty(theZone, "itemB") then 
		local menuB = cfxZones.getStringFromZoneProperty(theZone, "itemB", "<no B submenu>")
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

	if cfxZones.hasProperty(theZone, "itemC") then 
		local menuC = cfxZones.getStringFromZoneProperty(theZone, "itemC", "<no C submenu>")
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
	
	if cfxZones.hasProperty(theZone, "itemD") then 
		local menuD = cfxZones.getStringFromZoneProperty(theZone, "itemD", "<no D submenu>")
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
	theZone.rootName = cfxZones.getStringFromZoneProperty(theZone, "radioMenu", "<No Name>")
	
	theZone.coalition = cfxZones.getCoalitionFromZoneProperty(theZone, "coalition", 0)
	-- groups / types 
	if cfxZones.hasProperty(theZone, "group") then 
		theZone.menuGroup = cfxZones.getStringFromZoneProperty(theZone, "group", "<none>")
		theZone.menuGroup = dcsCommon.trim(theZone.menuGroup)
	elseif cfxZones.hasProperty(theZone, "groups") then 
		theZone.menuGroup = cfxZones.getStringFromZoneProperty(theZone, "groups", "<none>")
		theZone.menuGroup = dcsCommon.trim(theZone.menuGroup)
	elseif cfxZones.hasProperty(theZone, "type") then 
		theZone.menuTypes = cfxZones.getStringFromZoneProperty(theZone, "type", "none")
	elseif cfxZones.hasProperty(theZone, "types") then
		theZone.menuTypes = cfxZones.getStringFromZoneProperty(theZone, "types", "none")
	end	
	
	theZone.menuVisible = cfxZones.getBoolFromZoneProperty(theZone, "menuVisible", true)
	
	-- install menu if not hidden
	if theZone.menuVisible then 
		radioMenu.installMenu(theZone)
	end

	-- get the triggers & methods here 
	theZone.radioMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "radioMethod") then 
		theZone.radioMethod = cfxZones.getStringFromZoneProperty(theZone, "radioMethod", "inc")
	end
	
	theZone.radioTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "radioTriggerMethod", "change")
	
	theZone.itemAChosen = cfxZones.getStringFromZoneProperty(theZone, "A!", "*<none>")
	theZone.cooldownA = cfxZones.getNumberFromZoneProperty(theZone, "cooldownA", 0)
	--theZone.mcdA = 0
	theZone.busyA = cfxZones.getStringFromZoneProperty(theZone, "busyA", "Please stand by (<s> seconds)")
	
	theZone.itemBChosen = cfxZones.getStringFromZoneProperty(theZone, "B!", "*<none>")
	theZone.cooldownB = cfxZones.getNumberFromZoneProperty(theZone, "cooldownB", 0)
	--theZone.mcdB = 0
	theZone.busyB = cfxZones.getStringFromZoneProperty(theZone, "busyB", "Please stand by (<s> seconds)")
	
	theZone.itemCChosen = cfxZones.getStringFromZoneProperty(theZone, "C!", "*<none>")
	theZone.cooldownC = cfxZones.getNumberFromZoneProperty(theZone, "cooldownC", 0)
	--theZone.mcdC = 0
	theZone.busyC = cfxZones.getStringFromZoneProperty(theZone, "busyC", "Please stand by (<s> seconds)")

	theZone.itemDChosen = cfxZones.getStringFromZoneProperty(theZone, "D!", "*<none>")
	theZone.cooldownD = cfxZones.getNumberFromZoneProperty(theZone, "cooldownD", 0)
	--theZone.mcdD = 0
	theZone.busyD = cfxZones.getStringFromZoneProperty(theZone, "busyD", "Please stand by (<s> seconds)")
	
	if cfxZones.hasProperty(theZone, "removeMenu?") then 
		theZone.removeMenu = cfxZones.getStringFromZoneProperty(theZone, "removeMenu?", "*<none>")
		theZone.lastRemoveMenu = cfxZones.getFlagValue(theZone.removeMenu, theZone)
	end
	
	if cfxZones.hasProperty(theZone, "addMenu?") then 
		theZone.addMenu = cfxZones.getStringFromZoneProperty(theZone, "addMenu?", "*<none>")
		theZone.lastAddMenu = cfxZones.getFlagValue(theZone.addMenu, theZone)
	end
	
	if radioMenu.verbose or theZone.verbose then 
		trigger.action.outText("+++radioMenu: new radioMenu zone <".. theZone.name ..">", 30)
	end
	
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
	theZone = args[1]
	theItemIndex = args[2] -- A, B , C .. ?
	theGroup = args[3] -- can be nil or groupID 
	if not theGroup then theGroup = 0 end 
	
	local cd = radioMenu.cdByGID(theZone.mcdA, theZone, theGroup) --theZone.mcdA
	local busy = theZone.busyA 
	local theFlag = theZone.itemAChosen
	
	-- decode A..X
	if theItemIndex == "B"then 
		cd = radioMenu.cdByGID(theZone.mcdB, theZone, theGroup) -- theZone.mcdB
		busy = theZone.busyB 
		theFlag = theZone.itemBChosen
	elseif theItemIndex == "C" then 
		cd = radioMenu.cdByGID(theZone.mcdC, theZone, theGroup) -- theZone.mcdC
		busy = theZone.busyC 
		theFlag = theZone.itemCChosen
	elseif theItemIndex == "D" then 
		cd = radioMenu.cdByGID(theZone.mcdD, theZone, theGroup) -- theZone.mcdD
		busy = theZone.busyD 
		theFlag = theZone.itemDChosen
	end
	
	-- see if we are on cooldown 
	local now = timer.getTime()
	if now < cd then 
		-- we are on cooldown.
		local msg = radioMenu.processHMS(busy, cd - now)
		radioMenu.radioOutMessage(msg, theZone)
		return 
	end
	
	-- set new cooldown -- needs own decoder A..X
	if theItemIndex == "A" then
		radioMenu.setCDByGID("mcdA", theZone, theGroup, now + theZone.cooldownA)
	elseif theItemIndex == "B" then
		radioMenu.setCDByGID("mcdB", theZone, theGroup, now + theZone.cooldownB)
	elseif theItemIndex == "C" then 
		radioMenu.setCDByGID("mcdC", theZone, theGroup, now + theZone.cooldownC)
	else 
		radioMenu.setCDByGID("mcdC", theZone, theGroup, now + theZone.cooldownC)
	end
	
	cfxZones.pollFlag(theFlag, theZone.radioMethod, theZone)
	if theZone.verbose or radioMenu.verbose then 
		trigger.action.outText("+++menu: banging with <" .. theZone.radioMethod .. "> on <" .. theFlag .. "> for " .. theZone.name, 30)
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
		and cfxZones.testZoneFlag(theZone, theZone.removeMenu, theZone.radioTriggerMethod, "lastRemoveMenu") 
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
		and cfxZones.testZoneFlag(theZone, theZone.addMenu, theZone.radioTriggerMethod, "lastAddMenu") 
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
-- Config & Start
--
function radioMenu.readConfigZone()
	local theZone = cfxZones.getZoneByName("radioMenuConfig") 
	if not theZone then 
		if radioMenu.verbose then 
			trigger.action.outText("+++radioMenu: NO config zone!", 30)
		end 
		return 
	end 
	
	radioMenu.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if radioMenu.verbose then 
		trigger.action.outText("+++radioMenu: read config", 30)
	end 
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
	
	-- process radioMenu Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("radioMenu")
	for k, aZone in pairs(attrZones) do 
		radioMenu.createRadioMenuWithZone(aZone) -- process attributes
		radioMenu.addRadioMenu(aZone) -- add to list
	end
	
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
	callbacks for the menus  
	check CD/standby code for multiple groups 
--]]--