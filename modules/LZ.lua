LZ = {}
LZ.version = "0.0.0"
LZ.verbose = false 
LZ.ups = 1 
LZ.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
LZ.LZs = {}

--[[--
	Version History 
	1.0.0 - initial version 
	
	
--]]--

function LZ.addLZ(theZone)
	table.insert(LZ.LZs, theZone)
end

function LZ.getLZByName(aName) 
	for idx, aZone in pairs(LZ.LZs) do 
		if aName == aZone.name then return aZone end 
	end
	if LZ.verbose then 
		trigger.action.outText("+++LZ: no LZ with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read zone 
-- 
function LZ.createLZWithZone(theZone)
	-- read main trigger
	theZone.triggerLZFlag = cfxZones.getStringFromZoneProperty(theZone, "lz!", "*<none>")
	
	-- TriggerMethod: common and specific synonym
	theZone.lzMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	
	if cfxZones.hasProperty(theZone, "lzTriggerMethod") then 
		theZone.lzMethod = cfxZones.getStringFromZoneProperty(theZone, "lzMethod", "change")
	end 
	
	if LZ.verbose or theZone.verbose then 
		trigger.action.outText("+++LZ: new LZ <".. theZone.name ..">", 30)
	end
	
end

--
-- MAIN ACTION
--
function LZ.processUpdate(theZone)
	
end

--
-- Event Handling
--
function LZ:onEvent(event)
    -- only interested in S_EVENT_BASE_CAPTURED events
    if event.id ~= world.event.S_EVENT_BASE_CAPTURED then
        return
    end

    for idx, aZone in pairs(LZ.LZs) do 
		-- check if landed inside and of correct type, colition, name whatever 
		
    end
end

--
-- Update 
--

function LZ.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(LZ.update, {}, timer.getTime() + 1/LZ.ups)
		
	for idx, aZone in pairs(LZ.LZs) do
		-- see if we are triggered 
		if cfxZones.testZoneFlag(aZone, aZone.triggerLZFlag, aZone.LZTriggerMethod, 			"lastTriggerLZValue") then 
			if LZ.verbose or theZone.verbose then 
				trigger.action.outText("+++LZ: triggered on main? for <".. aZone.name ..">", 30)
			end
			LZ.processUpdate(aZone)
		end 
	end
end

--
-- Config & Start
--
function LZ.readConfigZone()
	local theZone = cfxZones.getZoneByName("LZConfig") 
	if not theZone then 
		if LZ.verbose then 
			trigger.action.outText("+++LZ: NO config zone!", 30)
		end 
		return 
	end 
	
	LZ.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if LZ.verbose then 
		trigger.action.outText("+++LZ: read config", 30)
	end 
end

function LZ.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx LZ requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx LZ", LZ.requiredLibs) then
		return false 
	end
	
	-- read config 
	LZ.readConfigZone()
	
	-- process LZ Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("lz!")
	for k, aZone in pairs(attrZones) do 
		LZ.createLZWithZone(aZone) -- process attributes
		LZ.addLZ(aZone) -- add to list
	end
	
	-- start update 
	LZ.update()
	
	trigger.action.outText("cfx LZ v" .. LZ.version .. " started.", 30)
	return true 
end

-- let's go!
if not LZ.start() then 
	trigger.action.outText("cfx LZ aborted: missing libraries", 30)
	LZ = nil 
end