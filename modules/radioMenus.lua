radioMenu = {}
radioMenu.version = "1.0.1"
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
function radioMenu.createRadioMenuWithZone(theZone)
	local rootName = cfxZones.getStringFromZoneProperty(theZone, "radioMenu", "<No Name>")
	
	theZone.coalition = cfxZones.getCoalitionFromZoneProperty(theZone, "coalition", 0)
	
	if theZone.coalition == 0 then 
		theZone.rootMenu = missionCommands.addSubMenu(rootName, nil) 
	else 
		theZone.rootMenu = missionCommands.addSubMenuForCoalition(theZone.coalition, rootName, nil) 
	end
	
	-- now do the two options
	local menuA = cfxZones.getStringFromZoneProperty(theZone, "itemA", "<no A submenu>")
	if theZone.coalition == 0 then 
		theZone.menuA = missionCommands.addCommand(menuA, theZone.rootMenu, radioMenu.redirectMenuX, {theZone, "A"})
	else 
		theZone.menuA = missionCommands.addCommandForCoalition(theZone.coalition, menuA, theZone.rootMenu, radioMenu.redirectMenuX, {theZone, "A"})
	end 
	
	if cfxZones.hasProperty(theZone, "itemB") then 
		local menuB = cfxZones.getStringFromZoneProperty(theZone, "itemB", "<no B submenu>")
		if theZone.coalition == 0 then 
			theZone.menuB = missionCommands.addCommand(menuB, theZone.rootMenu, radioMenu.redirectMenuX, {theZone, "B"})
		else 
			theZone.menuB = missionCommands.addCommandForCoalition(theZone.coalition, menuB, theZone.rootMenu, radioMenu.redirectMenuX, {theZone, "B"})
		end
	end

	if cfxZones.hasProperty(theZone, "itemC") then 
		local menuC = cfxZones.getStringFromZoneProperty(theZone, "itemC", "<no C submenu>")
		if theZone.coalition == 0 then 
			theZone.menuC = missionCommands.addCommand(menuC, theZone.rootMenu, radioMenu.redirectMenuX, {theZone, "C"})
		else 
			theZone.menuC = missionCommands.addCommandForCoalition(theZone.coalition, menuC, theZone.rootMenu, radioMenu.redirectMenuX, {theZone, "C"})
		end
	end
	
	if cfxZones.hasProperty(theZone, "itemD") then 
		local menuD = cfxZones.getStringFromZoneProperty(theZone, "itemD", "<no D submenu>")
		if theZone.coalition == 0 then 
			theZone.menuD = missionCommands.addCommand(menuD, theZone.rootMenu, radioMenu.redirectMenuX, {theZone, "D"})
		else 
			theZone.menuD = missionCommands.addCommandForCoalition(theZone.coalition, menuD, theZone.rootMenu, radioMenu.redirectMenuX, {theZone, "D"})
		end
	end
	
	
	-- get the triggers & methods here 
	theZone.radioMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "radioMethod") then 
		theZone.radioMethod = cfxZones.getStringFromZoneProperty(theZone, "radioMethod", "inc")
	end
	
	theZone.itemAChosen = cfxZones.getStringFromZoneProperty(theZone, "A!", "*<none>")
	theZone.cooldownA = cfxZones.getNumberFromZoneProperty(theZone, "cooldownA", 0)
	theZone.mcdA = 0
	theZone.busyA = cfxZones.getStringFromZoneProperty(theZone, "busyA", "Please stand by (<s> seconds)")
	
	theZone.itemBChosen = cfxZones.getStringFromZoneProperty(theZone, "B!", "*<none>")
	theZone.cooldownB = cfxZones.getNumberFromZoneProperty(theZone, "cooldownB", 0)
	theZone.mcdB = 0
	theZone.busyB = cfxZones.getStringFromZoneProperty(theZone, "busyB", "Please stand by (<s> seconds)")
	
	theZone.itemCChosen = cfxZones.getStringFromZoneProperty(theZone, "C!", "*<none>")
	theZone.cooldownC = cfxZones.getNumberFromZoneProperty(theZone, "cooldownC", 0)
	theZone.mcdC = 0
	theZone.busyC = cfxZones.getStringFromZoneProperty(theZone, "busyC", "Please stand by (<s> seconds)")

	theZone.itemDChosen = cfxZones.getStringFromZoneProperty(theZone, "D!", "*<none>")
	theZone.cooldownD = cfxZones.getNumberFromZoneProperty(theZone, "cooldownD", 0)
	theZone.mcdD = 0
	theZone.busyD = cfxZones.getStringFromZoneProperty(theZone, "busyD", "Please stand by (<s> seconds)")
	
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

function radioMenu.doMenuX(args)
	theZone = args[1]
	theItemIndex = args[2] -- A, B , C .. ?
	local cd = theZone.mcdA
	local busy = theZone.busyA 
	local theFlag = theZone.itemAChosen
	
	-- decode A..X
	if theItemIndex == "B"then 
		cd = theZone.mcdB
		busy = theZone.busyB 
		theFlag = theZone.itemBChosen
	elseif theItemIndex == "C" then 
		cd = theZone.mcdC
		busy = theZone.busyC 
		theFlag = theZone.itemCChosen
	elseif theItemIndex == "D" then 
		cd = theZone.mcdD
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
		theZone.mcdA = now + theZone.cooldownA
	elseif theItemIndex == "B" then
		theZone.mcdB = now + theZone.cooldownB
	elseif theItemIndex == "C" then 
		theZone.mcdC = now + theZone.cooldownC
	else 
		theZone.mcdD = now + theZone.cooldownD
	end
	
	cfxZones.pollFlag(theFlag, theZone.radioMethod, theZone)
	if theZone.verbose or radioMenu.verbose then 
		trigger.action.outText("+++menu: banging with <" .. theZone.radioMethod .. "> on <" .. theFlag .. "> for " .. theZone.name, 30)
	end

end
--
-- Update -- required when we can enable/disable a zone's menu
--
--[[--
function radioMenu.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(radioMenu.update, {}, timer.getTime() + 1/radioMenu.ups)
		
end
--]]--

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
	--radioMenu.update()
	
	trigger.action.outText("cfx radioMenu v" .. radioMenu.version .. " started.", 30)
	return true 
end

-- let's go!
if not radioMenu.start() then 
	trigger.action.outText("cfx radioMenu aborted: missing libraries", 30)
	radioMenu = nil 
end

--[[--
	to do: turn on/off via flags
	callbacks for the menus 
	one-shot items 
--]]--