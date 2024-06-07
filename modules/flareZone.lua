flareZone = {}
flareZone.version = "1.2.0"
flareZone.verbose = false 
flareZone.name = "flareZone" 

--[[-- VERSION HISTORY
	1.0.0 - initial version
	1.1.0 - improvements to verbosity 
	      - OOP 
		  - small bugfix in doFlare assignment 
	1.2.0 - new rndLoc attribute 
--]]--
flareZone.requiredLibs = {
	"dcsCommon", 
	"cfxZones",  
}
flareZone.flares = {} -- all flare zones 
 
function flareZone.addFlareZone(theZone)
	theZone.flareColor = theZone:getFlareColorStringFromZoneProperty("flare", "green")
	theZone.flareColor = dcsCommon.flareColor2Num(theZone.flareColor)
	if theZone:hasProperty("f?") then 
		theZone.doFlare = theZone:getStringFromZoneProperty("f?", "<none>")
	elseif theZone:hasProperty("launchFlare?") then
		theZone.doFlare = theZone:getStringFromZoneProperty( "launchFlare?", "<none>")
	else 
		theZone.doFlare = theZone:getStringFromZoneProperty("launch?", "<none>")
	end
	theZone.lastDoFlare = trigger.misc.getUserFlag(theZone.doFlare)
	-- triggerMethod
	theZone.flareTriggerMethod = theZone:getStringFromZoneProperty("triggerMethod", "change")
	if theZone:hasProperty("flareTriggerMethod") then 
		theZone.flareTriggerMethod = theZone:getStringFromZoneProperty("flareTriggerMethod", "change")
	end
	
	theZone.azimuthL, theZone.azimuthH = theZone:getPositiveRangeFromZoneProperty("direction", 90) -- in degrees
	-- in DCS documentation, the parameter is incorrectly called 'azimuth'
	if theZone:hasProperty("azimuth") then 
		theZone.azimuthL, theZone.azimuthH = theZone:getPositiveRangeFromZoneProperty("azimuth", 90) -- in degrees 
	end
	theZone.flareAlt = theZone:getNumberFromZoneProperty("altitude", 1)
	if theZone:hasProperty("alt") then 
		theZone.flareAlt = theZone:getNumberFromZoneProperty("alt", 1)
	elseif theZone:hasProperty("flareAlt") then 
		theZone.flareAlt = theZone:getNumberFromZoneProperty("flareAlt", 1)
	elseif theZone:hasProperty("agl") then 
		theZone.flareAlt = theZone:getNumberFromZoneProperty("agl", 1)
	end
	
	theZone.salvoSizeL, theZone.salvoSizeH = theZone:getPositiveRangeFromZoneProperty("salvo", 1)
	
	theZone.salvoDurationL, theZone.salvoDurationH = theZone:getPositiveRangeFromZoneProperty("duration", 1)
	
	theZone.rndLoc = theZone:getBoolFromZoneProperty("rndLoc", flase)
	
	if theZone.verbose or flareZone.verbose then 
		trigger.action.outText("+++flrZ: new flare <" .. theZone.name .. ">, color (" .. theZone.flareColor .. ")", 30)
	end
	table.insert(flareZone.flares, theZone)
end 

function flareZone.launch(theZone)
	local color = theZone.flareColor
	if color < 0 then color = math.random(4) - 1 end 
	local loc 
	if theZone.rndLoc then 
		locFlat = theZone:randomPointInZone()
		loc = {x = locFlat.x, y = land.getHeight({x = locFlat.x, y = locFlat.z}), z = locFlat.z}
	else 
		loc = cfxZones.getPoint(theZone, true) -- with height 
	end
	loc.y = loc.y + theZone.flareAlt
	-- calculate azimuth 
	local azimuth = cfxZones.randomInRange(theZone.azimuthL, theZone.azimuthH)  -- in deg 

--	if flareZone.verbose or theZone.verbose then 
--		trigger.action.outText("+++flrZ: launching <" .. theZone.name .. ">, c = " .. color .. " (" .. dcsCommon.flareColor2Text(color) .. "), azi <" .. azimuth .. "> [" .. theZone.azimuthL .. "-" .. theZone.azimuthH .. "]", 30)
--	end
	azimuth = azimuth * 0.0174533 -- in rads
	
	trigger.action.signalFlare(loc, color, azimuth)
end

function flareZone.update()
	-- call me again in a second
	timer.scheduleFunction(flareZone.update, {}, timer.getTime() + 1)

	-- launch if flag banged
	for idx, theZone in pairs(flareZone.flares) do 
		if cfxZones.testZoneFlag(theZone, theZone.doFlare, theZone.flareTriggerMethod, "lastDoFlare") then 
			if flareZone.verbose or theZone.verbose then 
				trigger.action.outText("+++flr: triggerd flares for <" .. theZone.name .. "> on input? <" .. theZone.doFlare .. ">", 30)
			end
			local salvo = cfxZones.randomInRange(theZone.salvoSizeL, theZone.salvoSizeH)
			if salvo < 2 then 
				-- one-shot
				flareZone.launch(theZone)
			else 
				-- pick a duration from range 
				local duration = cfxZones.randomInRange(theZone.salvoDurationL, theZone.salvoDurationH)
				local duration = duration / salvo 
				local d = 0
				for l=1, salvo do 
					timer.scheduleFunction(flareZone.launch, theZone, timer.getTime() + d + 0.1)
					d = d + duration
				end
			end
		end
	end
end

function flareZone.start()
	if not dcsCommon.libCheck("cfx Flare Zones", flareZone.requiredLibs) then return false end
	
	-- collect all flares 
	local attrZones = cfxZones.getZonesWithAttributeNamed("flare")	
	for k, theZone in pairs(attrZones) do 
		flareZone.addFlareZone(theZone) -- process attribute and add to zone
	end

	-- start update
	flareZone.update() -- also starts all unpaused 
		
	-- say hi
	trigger.action.outText("cfx Flare Zone v" .. flareZone.version .. " started.", 30)
	return true 
end

-- let's go 
if not flareZone.start() then 
	trigger.action.outText("cf/x Flare Zones aborted: missing libraries", 30)
	cfxSmokeZone = nil 
end