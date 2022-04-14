tmpl = {}
tmpl.version = "0.0.0"
tmpl.verbose = false 
tmpl.ups = 1 
tmpl.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
tmpl.tmpls = {}

--[[--
	Version History 
	
--]]--
function tmpl.addTmpl(theZone)
	table.insert(tmpl.tmpls, theZone)
end

function tmpl.getTmplByName(aName) 
	for idx, aZone in pairs(tmpl.tmpls) do 
		if aName == aZone.name then return aZone end 
	end
	if tmpl.verbose then 
		trigger.action.outText("+++tmpl: no tmpl with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read zone 
-- 
function tmpl.createTmplWithZone(theZone)
	-- read main trigger
	theZone.triggerTmplFlag = cfxZones.getStringFromZoneProperty(theZone, "tmpl?", "*<none>")
	theZone.lastTriggerTmplValue = cfxZones.getFlagValue(theZone.triggerTmplFlag, theZone)
	
	-- TriggerMethod: common and specific synonym
	theZone.tmplTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "tmplTriggerMethod") then 
		theZone.tmplTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "tmplTriggerMethod", "change")
	end 
	
	if tmpl.verbose or theZone.verbose then 
		trigger.action.outText("+++tmpl: new tmpl zone <".. theZone.name ..">", 30)
	end
	
end

--
-- MAIN ACTION
--
function tmpl.process(theZone)
	
end

--
-- Update 
--

function tmpl.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(tmpl.update, {}, timer.getTime() + 1/tmpl.ups)
		
	for idx, aZone in pairs(tmpl.tmpls) do
		-- see if we are triggered 
		if cfxZones.testZoneFlag(aZone, 				aZone.triggerTmplFlag, aZone.tmplTriggerMethod, 			"lastTriggerTmplValue") then 
			if tmpl.verbose or theZone.verbose then 
				trigger.action.outText("+++tmpl: triggered on main? for <".. aZone.name ..">", 30)
			end
			tmpl.process(aZone)
		end 
	end
end

--
-- Config & Start
--
function tmpl.readConfigZone()
	local theZone = cfxZones.getZoneByName("tmplConfig") 
	if not theZone then 
		if tmpl.verbose then 
			trigger.action.outText("+++tmpl: NO config zone!", 30)
		end 
		return 
	end 
	
	tmpl.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if tmpl.verbose then 
		trigger.action.outText("+++tmpl: read config", 30)
	end 
end

function tmpl.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx tmpl requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx tmpl", tmpl.requiredLibs) then
		return false 
	end
	
	-- read config 
	tmpl.readConfigZone()
	
	-- process tmpl Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("tmpl")
	for k, aZone in pairs(attrZones) do 
		tmpl.createTmplWithZone(aZone) -- process attributes
		tmpl.addTmpl(aZone) -- add to list
	end
	
	-- start update 
	tmpl.update()
	
	trigger.action.outText("cfx tmpl v" .. tmpl.version .. " started.", 30)
	return true 
end

-- let's go!
if not tmpl.start() then 
	trigger.action.outText("cfx tmpl aborted: missing libraries", 30)
	tmpl = nil 
end