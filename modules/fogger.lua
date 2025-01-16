fogger = {}
fogger.version = "1.1.0" 
fogger.requiredLibs = {
	"dcsCommon",
	"cfxZones",
}
fogger.zones = {}

--[[-- Version history
  A DML module (c) 2024-25 by Christian FRanz 

- 1.0.0 - Initial version
- 1.1.0 - added lcl attribute  
		- added onStart
--]]--

function fogger.createFogZone(theZone)
	theZone.fogger =  theZone:getStringFromZoneProperty("fog?", "<none>")
	theZone.lastFogger = trigger.misc.getUserFlag(theZone.fogger)
	fogger.triggerMethod = theZone:getStringFromZoneProperty("triggerMethod", "change")
	if theZone:hasProperty("visibility") then 
		theZone.visMin, theZone.visMax =  theZone:getPositiveRangeFromZoneProperty("visibility", 0, 0)
	end 
	if theZone:hasProperty("thickness") then 
		theZone.thickMin, theZone.thickMax = theZone:getPositiveRangeFromZoneProperty("thickness", 0,0)
	end 
	theZone.lcl = theZone:getBoolFromZoneProperty("lcl", false)
	theZone.durMin, theZone.durMax = theZone:getPositiveRangeFromZoneProperty ("duration", 1, 1)
	if theZone:hasProperty("onStart") then 
		theZone.onStart = theZone:getBoolFromZoneProperty("onStart", false)
		if theZone.onStart then 
			if theZone.verbose then 
				trigger.action.outText("+++fog: will schedule onStart fog in zone <" .. theZone.name .. ">", 30)
			end
			timer.scheduleFunction(fogger.doFog, theZone, timer.getTime() + 0.5)
		end 
	end 
	if theZone.verbose then 
		trigger.action.outText("+++fog: zone <" .. theZone.name .. "> processed.", 30)
	end
end 

function fogger.doFog(theZone)
	local vis = world.weather.getFogVisibilityDistance()
	if theZone.visMin then vis = dcsCommon.randomBetween(theZone.visMin, theZone.visMax) end
	if vis < 100 then vis = 0 end 
	local thick = world.weather.getFogThickness()
	if theZone.thickMin then thick = dcsCommon.randomBetween(theZone.thickMin, theZone.thickMax) end 
	if thick < 100 then thick = 0 
	elseif theZone.lcl then 
		local p = theZone:getPoint()
		thick = thick + land.getHeight({x = p.x, y = p.z})
	end 
	local dur = dcsCommon.randomBetween(theZone.durMin, theZone.durMax)
	if theZone.verbose or fogger.verbose then 
		trigger.action.outText("+++fog: will set fog vis = <" .. vis .. ">, thick = <" .. thick .. ">, transition <" .. dur .. "> secs", 30)
	end 
	world.weather.setFogAnimation({{dur, vis, thick}})
end 

-- update 
function fogger.update()
	timer.scheduleFunction(fogger.update, nil, timer.getTime() + 1/fogger.ups)
	for idx, theZone in pairs(fogger.zones) do 
		if theZone:testZoneFlag(theZone.fogger, theZone.triggerMethod, "lastFogger") then fogger.doFog(theZone) end
	end
end 

-- config
function fogger.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("foggerConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("foggerConfig") 
	end 
	fogger.ups = theZone:getNumberFromZoneProperty("ups", 1)
	fogger.name = "fogger" 
	fogger.verbose = theZone.verbose 
end

-- go go go 
function fogger.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("fogger requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("fogger", fogger.requiredLibs) then
		return false 
	end	
	-- read config 
	fogger.readConfigZone()
	-- process "fog?" Zones  
	local attrZones = cfxZones.getZonesWithAttributeNamed("fog?")
	for k, aZone in pairs(attrZones) do 
		fogger.createFogZone(aZone)
		fogger.zones[aZone.name] = aZone
	end
	-- invoke update 
	fogger.update()
	trigger.action.outText("Fogger v" .. fogger.version .. " started.", 30)
	return true 
end

-- let's go!
if not fogger.start() then 
	trigger.action.outText("fogger aborted: error on start", 30)
	fogger = nil 
end
