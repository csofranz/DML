flareZone = {}
flareZone.version = "1.0.0"
flareZone.verbose = false 
flareZone.name = "flareZone" 

--[[-- VERSION HISTORY
	1.0.0 - initial version
--]]--
flareZone.requiredLibs = {
	"dcsCommon", 
	"cfxZones",  
}
flareZone.flares = {} -- all flare zones 
 
function flareZone.addFlareZone(theZone)
	theZone.flareColor = cfxZones.getFlareColorStringFromZoneProperty(theZone, "flare", "green")
	theZone.flareColor = dcsCommon.flareColor2Num(theZone.flareColor)
	if cfxZones.hasProperty(theZone, "f?") then 
		cfxZones.theZone.doFlare = cfxZones.getStringFromZoneProperty(theZone, "f?", "<none>")
	elseif cfxZones.hasProperty(theZone, "launchFlare?") then
		theZone.doFlare = cfxZones.getStringFromZoneProperty(theZone, "launchFlare?", "<none>")
	else 
		theZone.doFlare = cfxZones.getStringFromZoneProperty(theZone, "launch?", "<none>")
	end
	theZone.lastDoFlare = trigger.misc.getUserFlag(theZone.doFlare)
	-- triggerMethod
	theZone.flareTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "flareTriggerMethod") then 
		theZone.flareTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "flareTriggerMethod", "change")
	end
	
	theZone.azimuthL, theZone.azimuthH = cfxZones.getPositiveRangeFromZoneProperty(theZone, "direction", 90) -- in degrees
	-- in DCS documentation, the parameter is incorrectly called 'azimuth'
	if cfxZones.hasProperty(theZone, "azimuth") then 
		theZone.azimuthL, theZone.azimuthH = cfxZones.getPositiveRangeFromZoneProperty(theZone, "azimuth", 90) -- in degrees 
	end
--	theZone.azimuth = theZone.azimuth * 0.0174533 -- rads 
	theZone.flareAlt = cfxZones.getNumberFromZoneProperty(theZone, "altitude", 1)
	if cfxZones.hasProperty(theZone, "alt") then 
		theZone.flareAlt = cfxZones.getNumberFromZoneProperty(theZone, "alt", 1)
	elseif cfxZones.hasProperty(theZone, "flareAlt") then 
		theZone.flareAlt = cfxZones.getNumberFromZoneProperty(theZone, "flareAlt", 1)
	elseif cfxZones.hasProperty(theZone, "agl") then 
		theZone.flareAlt = cfxZones.getNumberFromZoneProperty(theZone, "agl", 1)
	end
	
	theZone.salvoSizeL, theZone.salvoSizeH = cfxZones.getPositiveRangeFromZoneProperty(theZone, "salvo", 1)
	
	theZone.salvoDurationL, theZone.salvoDurationH = cfxZones.getPositiveRangeFromZoneProperty(theZone, "duration", 1)
	
	if theZone.verbose or flareZone.verbose then 
		trigger.action.outText("+++flrZ: new flare <" .. theZone.name .. ">, color (" .. theZone.flareColor .. ")", 30)
	end
	table.insert(flareZone.flares, theZone)
end 

function flareZone.launch(theZone)
	local color = theZone.flareColor
	if color < 0 then color = math.random(4) - 1 end 
	if flareZone.verbose or theZone.verbose then 
		trigger.action.outText("+++flrZ: launching <" .. theZone.name .. ">, c = " .. color .. " (" .. dcsCommon.flareColor2Text(color) .. ")", 30)
	end
	local loc = cfxZones.getPoint(theZone, true) -- with height 
	loc.y = loc.y + theZone.flareAlt
	-- calculate azimuth 
	local azimuth = cfxZones.randomInRange(theZone.azimuthL, theZone.azimuthH) * 0.0174533 -- in rads 
	trigger.action.signalFlare(loc, color, azimuth)
end

function flareZone.update()
	-- call me again in a second
	timer.scheduleFunction(flareZone.update, {}, timer.getTime() + 1)

	-- launch if flag banged
	for idx, theZone in pairs(flareZone.flares) do 
		if cfxZones.testZoneFlag(theZone, theZone.doFlare, theZone.flareTriggerMethod, "lastDoFlare") then 
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