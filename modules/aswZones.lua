aswZones = {}
aswZones.version = "1.0.0"
aswZones.verbose = false 
aswZones.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"asw", -- needs asw module 
}
--[[--
	Version History
	1.0.0 - initial version 
	
--]]--

aswZones.ups = 1 -- = once every second
aswZones.zones = {} -- all zones, by name

function aswZones.addZone(theZone)
	if not theZone then
		trigger.action.outText("aswZ: nil zone in addZone", 30)
		return 
	end
	aswZones.zones[theZone.name] = theZone
end

function aswZones.getZoneNamed(theName)
	if not theName then return nil end 
	return aswZones[theName] 
end

function aswZones.getClosestASWZoneTo(loc)
	local closestZone = nil
	local loDist = math.huge 
	for name, theZone in pairs(aswZones.zones) do 
		local zp = cfxZones.getPoint(theZone)
		local d = dcsCommon.distFlat(zp, loc)
		if d < loDist then 
			loDist = d
			closestZone = theZone
		end
	end
	return closestZone, loDist
end

function aswZones.createASWZone(theZone)
	-- get inventory of buoys 
	theZone.buoyNum = cfxZones.getNumberFromZoneProperty(theZone, "buoyS", -1) -- also used as supply for helos if they land in zone
	theZone.torpedoNum = cfxZones.getNumberFromZoneProperty(theZone, "torpedoes", -1) -- also used as supply for helos if they land in zone

	theZone.coalition = cfxZones.getCoalitionFromZoneProperty(theZone, "coalition", 0) 
	
	-- trigger method
	theZone.aswTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "aswTriggerMethod") then 
		theZone.aswTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "aswTriggerMethod", "change")
	end
	
	if cfxZones.hasProperty(theZone, "buoy?") then 
		theZone.buoyFlag = cfxZones.getStringFromZoneProperty(theZone, "buoy?", "none")
		theZone.lastBuoyValue = cfxZones.getFlagValue(theZone.buoyFlag, theZone)
	end
	
	if cfxZones.hasProperty(theZone, "torpedo?") then 
		theZone.torpedoFlag = cfxZones.getStringFromZoneProperty(theZone, "torpedo?", "none")
		theZone.lastTorpedoValue = cfxZones.getFlagValue(theZone.torpedoFlag, theZone)
	end
	
	if theZone.verbose or aswZones.verbose then 
		trigger.action.outText("+++aswZ: new asw zone <" .. theZone.name .. ">", 30)
		trigger.action.outText("has coalition " .. theZone.coalition, 30)
	end
end

--
-- responding to triggers
--
function aswZones.dropBuoy(theZone)
	if theZone.buoyNum == 0 then 
		-- we are fresh out. no launch 
		if theZone.verbose or aswZones.verbose then 
			trigger.action.outText("+++aswZ: zone <" .. theZone.name .. "> is out of buoys, can't drop", 30)
		end
		return 
	end 
	
	local theBuoy = asw.dropBuoyFromZone(theZone)
	if theZone.buoyNum > 0 then 
		theZone.buoyNum = theZone.buoyNum - 1 
	end
end

function aswZones.dropTorpedo(theZone)
	if theZone.torpedoNum == 0 then 
		-- we are fresh out. no launch 
		if theZone.verbose or aswZones.verbose then 
			trigger.action.outText("+++aswZ: zone <" .. theZone.name .. "> is out of torpedoes, can't drop", 30)
		end
		return 
	end 
	
	local theTorpedo = asw.dropTorpedoFromZone(theZone)
	if theZone.torpedoNum > 0 then 
		theZone.torpedoNum = theZone.torpedoNum - 1 
	end
end
--
-- Update
--
function aswZones.update()
	--env.info("-->Enter asw ZONES update")
	-- first, schedule next invocation 
	timer.scheduleFunction(aswZones.update, {}, timer.getTime() + 1/aswZones.ups)
	
	for zName, theZone in pairs(aswZones.zones) do 
		if theZone.buoyFlag and cfxZones.testZoneFlag(theZone, theZone.buoyFlag, theZone.aswTriggerMethod, "lastBuoyValue") then
			trigger.action.outText("zone <" .. theZone.name .. "> will now drop a buoy", 30)
			aswZones.dropBuoy(theZone)
		end
		
		if theZone.torpedoFlag and cfxZones.testZoneFlag(theZone, theZone.torpedoFlag, theZone.aswTriggerMethod, "lastTorpedoValue") then
			trigger.action.outText("zone <" .. theZone.name .. "> will now drop a TORPEDO", 30)
			aswZones.dropTorpedo(theZone)
		end
	end
	
	--env.info("<--Leave asw ZONES update")
end

--
-- Config & start 
--
function aswZones.readConfigZone()
	local theZone = cfxZones.getZoneByName("aswZonesConfig") 
	if not theZone then 
		if aswZones.verbose then 
			trigger.action.outText("+++aswZ: no config zone!", 30)
		end 
		theZone =  cfxZones.createSimpleZone("aswZonesConfig")
	end 
	aswZones.verbose = theZone.verbose 
	
	-- set defaults, later do the reading 
	
	
	if aswZones.verbose then 
		trigger.action.outText("+++aswZ: read config", 30)
	end 
end

function aswZones.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx aswZones requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx aswZones", aswZones.requiredLibs) then
		return false 
	end
	
	-- read config 
	aswZones.readConfigZone()
	
	-- read zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("asw")
	
	-- collect my zones 
	for k, aZone in pairs(attrZones) do 
		aswZones.createASWZone(aZone) -- process attributes
		aswZones.addZone(aZone) -- add to inventory
	end
	
	-- start update 
	aswZones.update()
	
	-- say hi
	trigger.action.outText("cfx aswZones v" .. aswZones.version .. " started.", 30)
	
	return true 
end

--
-- start up aswZones
--
if not aswZones.start() then 
	trigger.action.outText("cfx aswZones aborted: missing libraries", 30)
	aswZones = nil 
end

-- add asw.helper with zones that can 
-- drop torps 
-- have inventory per zone or -1 as infinite 
-- have an event when a buoy finds something 
-- hav an event when a buoy times out 
-- have buoyOut! and torpedoOut! events 