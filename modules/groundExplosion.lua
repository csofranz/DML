groundExplosion = {}
groundExplosion.version = "1.1.0"
groundExplosion.requiredLibs = {
	"dcsCommon", 
	"cfxZones", 
}
groundExplosion.zones = {}

--[[--
Version History
	1.0.0 - Initial version 
	1.0.1 - fixed lib check for objectDestructDetector 
	1.1.0 - new flares attribute
	
--]]--


function groundExplosion.addExplosion(theZone)
	theZone.powerMin, theZone.powerMax = theZone:getPositiveRangeFromZoneProperty("explosion", 1, 1)
	theZone.triggerMethod = theZone:getStringFromZoneProperty("tiggerMethod", "change")
	if theZone:hasProperty("boom?") then 
		theZone.boom = theZone:getStringFromZoneProperty("boom?", "none")
		theZone.lastBoom = theZone:getFlagValue(theZone.boom)
	end 
	theZone.numMin, theZone.numMax = theZone:getPositiveRangeFromZoneProperty("num", 1, 1)
	theZone.rndLoc = theZone:getBoolFromZoneProperty("rndLoc", false) 
	if (theZone.numMax > 1) then 
		theZone.rndLoc = true 
		theZone.multi = true 
	end 
	theZone.duration = theZone:getNumberFromZoneProperty("duration", 0)
	theZone.aglMin, theZone.aglMax = theZone:getPositiveRangeFromZoneProperty("AGL", 1,1)
	if theZone:hasProperty("flares") then 
		theZone.flareMin, theZone.flareMax = theZone:getPositiveRangeFromZoneProperty("flares", 0-3)
	end 
end

--
-- go boom
--
function groundExplosion.doBoom(args)
	local loc = args[1]
	local power = args[2]
	local theZone = args[3]
	trigger.action.explosion(loc, power)
	if theZone.flareMin then 
		local flareNum = cfxZones.randomInRange(theZone.flareMin, theZone.flareMax)
		if flareNum > 0 then 
			for i=1, flareNum do 
				local azimuth = math.random(360)
				azimuth = azimuth * 0.0174533 -- in rads
				trigger.action.signalFlare(loc, 2, azimuth) -- 2 = white
			end
		end 
	end
end

function groundExplosion.startBoom(theZone)
	local now = timer.getTime()
	local num = cfxZones.randomInRange(theZone.numMin, theZone.numMax)
	local i = 1 
	while i <= num do 
		local loc 
		if theZone.rndLoc then
			loc = theZone:randomPointInZone()
		else 
			loc = theZone:getPoint()
		end 
		local h = land.getHeight({x = loc.x, y = loc.z})
		local agl = cfxZones.randomInRange(theZone.aglMin, theZone.aglMax)
		loc.y = h + agl 
		local power = cfxZones.randomInRange(theZone.powerMin, theZone.powerMax)
		if theZone.duration > 0 then -- deferred
			local tplus = (i-1) * theZone.duration / num
			timer.scheduleFunction(groundExplosion.doBoom, {loc, power, theZone}, now + tplus + 0.1)
		else -- immediate 
			trigger.action.explosion(loc, power)
		end 
		i = i + 1
	end 
end

--
-- Update
--
function groundExplosion.update()
	for idx, theZone in pairs(groundExplosion.zones) do 
		
		if theZone.boom then 
			if theZone:testZoneFlag(theZone.boom, theZone.triggerMethod, "lastBoom") then 
				groundExplosion.startBoom(theZone)
			end
		end
	end
	timer.scheduleFunction(groundExplosion.update, {}, timer.getTime() + 1)
end

function groundExplosion.start()
	if not dcsCommon.libCheck("cfx groundExplosion", 
		groundExplosion.requiredLibs) then
		return false 
	end
	
	-- collect all zones with 'OBJECT ID' attribute 
	local attrZones = cfxZones.getZonesWithAttributeNamed("explosion")
	for k, aZone in pairs(attrZones) do 
		groundExplosion.addExplosion(aZone) 
		table.insert(groundExplosion.zones, aZone)
	end
	
	-- start update 
	timer.scheduleFunction(groundExplosion.update, {}, timer.getTime() + 1)
	return true 
end

-- let's go 
if not groundExplosion.start() then 
	trigger.action.outText("cf/x groundExplosion aborted: missing libraries", 30)
	groundExplosion = nil 
end