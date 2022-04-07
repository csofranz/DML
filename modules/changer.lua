changer = {}
changer.version = "0.0.0"
changer.verbose = false 
changer.ups = 1 
changer.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
changer.changers = {}
--[[--
	Version History
	1.0.0 - Initial version 
	
--]]--

function changer.addChanger(theZone)
	table.insert(changer.changers, theZone)
end

function changer.getChangerByName(aName) 
	for idx, aZone in pairs(changer.changers) do 
		if aName == aZone.name then return aZone end 
	end
	if changer.verbose then 
		trigger.action.outText("+++chgr: no changer with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read zone 
-- 
function wiper.createWiperWithZone(theZone)
	theZone.triggerWiperFlag = cfxZones.getStringFromZoneProperty(theZone, "wipe?", "*<none>")
	
	-- triggerWiperMethod
	theZone.triggerWiperMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "triggerWiperMethod") then 
		theZone.triggerWiperMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerWiperMethod", "change")
	end 
	
	if theZone.triggerWiperFlag then 
		theZone.lastTriggerWiperValue = cfxZones.getFlagValue(theZone.triggerWiperFlag, theZone)
	end

	local theCat = cfxZones.getStringFromZoneProperty(theZone, "category", "static")
	if cfxZones.hasProperty(theZone, "wipeCategory") then 
		theCat = cfxZones.getStringFromZoneProperty(theZone, "wipeCategory", "static")
	end
	if cfxZones.hasProperty(theZone, "wipeCat") then 
		theCat = cfxZones.getStringFromZoneProperty(theZone, "wipeCat", "static")
	end
	
	theZone.wipeCategory = dcsCommon.string2ObjectCat(theCat)
	
	if cfxZones.hasProperty(theZone, "wipeNamed") then 
		theZone.wipeNamed = cfxZones.getStringFromZoneProperty(theZone, "wipeNamed", "<no name given>")
		 
		if dcsCommon.stringEndsWith(theZone.wipeNamed, "*") then 
			theZone.wipeNamedBeginsWith = true 
			theZone.wipeNamed = dcsCommon.removeEnding(theZone.wipeNamed, "*") 
		end
	end 
	
	theZone.wipeInventory = cfxZones.getBoolFromZoneProperty(theZone, "wipeInventory", false)
	
	if wiper.verbose or theZone.verbose then 
		trigger.action.outText("+++wpr: new wiper zone <".. theZone.name ..">", 30)
	end
end

--
-- MAIN ACTION
--
function changer.isTriggered(theZone)
	
end


--
-- Update 
--

function changer.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(changer.update, {}, timer.getTime() + 1/changer.ups)
		
	for idx, aZone in pairs(changer.changers) do
		
		
	end
end


--
-- Config & Start
--
function changer.readConfigZone()
	local theZone = cfxZones.getZoneByName("changerConfig") 
	if not theZone then 
		if changer.verbose then 
			trigger.action.outText("+++chgr: NO config zone!", 30)
		end 
		theZone = cfxZones.createSimpleZone("changerConfig") -- temp only
	end 
	
	changer.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	changer.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 1)
		
	if changer.verbose then 
		trigger.action.outText("+++chgr: read config", 30)
	end 
end

function wiper.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Wiper requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Wiper", wiper.requiredLibs) then
		return false 
	end
	
	-- read config 
	wiper.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("wipe?")
	for k, aZone in pairs(attrZones) do 
		wiper.createWiperWithZone(aZone) -- process attributes
		wiper.addWiper(aZone) -- add to list
	end
	
	-- start update 
	wiper.update()
	
	trigger.action.outText("cfx Wiper v" .. wiper.version .. " started.", 30)
	return true 
end

-- let's go!
if not wiper.start() then 
	trigger.action.outText("cfx Wiper aborted: missing libraries", 30)
	wiper = nil 
end