airfield = {}
airfield.version = "1.1.0"
airfield.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
}
airfield.verbose = false 
airfield.myAirfields = {} -- indexed by name 
airfield.farps = false 

--[[--
	This module generates signals when the nearest airfield changes hands, 
	can force the coalition of an airfield, and always provides the 
	current owner as a value
	
	Version History
	1.0.0 - initial release 
	1.1.0 - added 'fixed' attribute
		  - added 'farps' attribute to individual zones 
		  - allow zone.local farps designation 
	      - always checks farp cap events 
		  - added verbosity
--]]--

--
-- setting up airfield
--
function airfield.createAirFieldFromZone(theZone)
	theZone.farps = theZone:getBoolFromZoneProperty("farps", false)

	local filterCat = 0
	if (airfield.farps or theZone.farps) then filterCat = {0, 1} end -- bases and farps
	local p = theZone:getPoint()
	local theBase = dcsCommon.getClosestAirbaseTo(p, filterCat)
	theZone.airfield = theBase
	theZone.afName = theBase:getName() 
	if airfield.verbose then 
		trigger.action.outText("+++airF: zone <" .. theZone:getName() .. "> associates with <" .. theZone.afName .. ">", 30)
	end
	
	-- methods 
	theZone.method = theZone:getStringFromZoneProperty("method", "inc")
	theZone.triggerMethod = theZone:getStringFromZoneProperty("triggerMethod", "change")
	
	-- set zone's owner 
	theZone.owner = theBase:getCoalition()
	
	if theZone:hasProperty("red!") then 
		theZone.redCap = theZone:getStringFromZoneProperty("red!")
	end
	if theZone:hasProperty("blue!") then 
		theZone.blueCap = theZone:getStringFromZoneProperty("blue!")
	end
	
	-- controlled capture?
	if theZone:hasProperty("makeRed?") then 
		theZone.makeRed = theZone:getStringFromZoneProperty("makeRed?", "<none>")
		theZone.lastMakeRed = trigger.misc.getUserFlag(theZone.makeRed)
	end
	if theZone:hasProperty("makeBlue?") then 
		theZone.makeBlue = theZone:getStringFromZoneProperty("makeBlue?", "<none>")
		theZone.lastMakeBlue = trigger.misc.getUserFlag(theZone.makeBlue)
	end
	
	if theZone:hasProperty("autoCap?") then 
		theZone.autoCap = theZone:getStringFromZoneProperty("autoCap?", "<none>")
		theZone.lastAutoCap = trigger.misc.getUserFlag(theZone.autoCap)
	end
	
	theZone.directControl = theZone:getBoolFromZoneProperty("directControl", false)
	
	if theZone.directControl then 
		airfield.assumeControl(theZone)
	end
	
	if theZone:hasProperty("ownedBy#") then 
		theZone.ownedBy = theZone:getStringFromZoneProperty("ownedBy#", "<none>")
		trigger.action.setUserFlag(theZone.ownedBy, theZone.owner)
	end
	
	-- if fixed attribute, we switch to that color and keep it fixed.
	-- can be overridden by either makeXX or autoCap.
	if theZone:hasProperty("fixed") then 
		local theFixed = theZone:getCoalitionFromZoneProperty("fixed")
		local theAirfield = theZone.airfield
		airfield.assumeControl(theZone) -- turn off capturable 
		theAirfield:setCoalition(theFixed)
		theZone.owner = theFixed
	end
	
	-- index by name, and warn if duplicate associate 
	if airfield.myAirfields[theZone.afName] then 
		trigger.action.outText("+++airF: WARNING - zone <" .. theZone:getName() .. "> redefines airfield <" .. theZone.afName .. ">, discarded!", 30)
	else 
		airfield.myAirfields[theZone.afName] = theZone
	end
	
	if theZone.verbose or airfield.verbose then 
		trigger.action.outText("+++airF: airfield zone <" .. theZone.name .. "> associates with <" .. theZone.afName .. ">, current owner is <" .. theZone.owner .. ">", 30)
	end
end

function airfield.assumeControl(theZone)
	theBase = theZone.airfield
	if airfield.verbose or theZone.verbose then 
		trigger.action.outText("+++airF: assuming direct control and turning off auto-capture for <" .. theZone.afName .. ">, now controlled by zone <" .. theZone:getName() .. ">", 30)
	end
	theBase:autoCapture(false) -- turn off autocap 
end

function airfield.relinquishControl(theZone)
	theBase = theZone.airfield
	if airfield.verbose or theZone.verbose then 
		trigger.action.outText("+++airF: zone <" .. theZone:getName() .. "> relinquishing ownership control over <" .. theZone.afName .. ">, can be captured normally", 30)
	end
	theBase:autoCapture(true) -- turn off autocap 
end

--
-- event handling
--

function airfield.airfieldCaptured(theBase)
	-- retrieve the zone that controls this airfield 
	local bName = theBase:getName()
	local theZone = airfield.myAirfields[bName]
	if not theZone then return end -- not handled 
	local newCoa = theBase:getCoalition()
	theZone.owner = newCoa 
	
	if theZone.verbose or airfield.verbose then 
		trigger.action.outText("+++airF: handling capture event/command for airfield <" .. bName .. "> with zone <" .. theZone:getName() .. ">", 30)
	end

	-- outputs
	if theZone.ownedBy then 
		trigger.action.setUserFlag(theZone.ownedBy, theZone.owner)
	end 
	if theZone.redCap and newCoa == 1 then 
		theZone:pollFlag(theZone.redCap, theZone.method)
	end
	if theZone.blueCap and newCoa == 2 then 
		theZone:pollFlag(theZone.blueCap, theZone.method)
	end
	
end

function airfield:onEvent(event)
	if not event then return end
	if event.id == 10 then -- S_EVENT_BASE_CAPTURED
		local theBase = event.place
		if not theBase then 
			trigger.action.outText("+++airF: error: cap event without base", 30)
			return 
		end
		-- get category 
		local desc = theBase:getDesc()
		local bName = theBase:getName()
		local cat = desc.category -- never get cat directly!
--[[--		if cat == 1 then 
			if not airfield.farps then 
				if airfield.verbose then 
					trigger.action.outText("+++airF: ignored cap event for FARP <" .. bName .. ">", 30)
				end
				return
			end
		end --]]
		if airfield.verbose then 
			trigger.action.outText("+++airF: cap event for <" .. bName .. ">, cat = (" .. cat .. ")", 30)
		end
		airfield.airfieldCaptured(theBase)
	end
end

--
-- update 
--

function airfield.update()
	timer.scheduleFunction(airfield.update, {}, timer.getTime() + 1)
	for afName, theZone in pairs(airfield.myAirfields) do 
		local theAirfield = theZone.airfield
		if theZone.makeRed and theZone:testZoneFlag(theZone.makeRed, theZone.triggerMethod, "lastMakeRed") then 
			if theZone.verbose or airfield.verbose then 
				trigger.action.outText("+++airF: 'makeRed' triggered for airfield <" .. afName .. "> in zone <" .. theZone:getName() .. ">", 30)
			end
			if theAirfield:autoCaptureIsOn() then 
				-- turn off autoCap 
				airfield.assumeControl(theZone)
			end
			theAirfield:setCoalition(1) -- make it red, doesn't trigger event
			if theZone.owner ~= 1 then -- only send cap event when capped
				airfield.airfieldCaptured(theAirfield)
			end 
		end
		
		if theZone.makeBlue and theZone:testZoneFlag(theZone.makeBlue, theZone.triggerMethod, "lastMakeBlue") then 
			if theZone.verbose or airfield.verbose then 
				trigger.action.outText("+++airF: 'makeBlue' triggered for airfield <" .. afName .. "> in zone <" .. theZone:getName() .. ">", 30)
			end
			if theAirfield:autoCaptureIsOn() then 
				-- turn off autoCap 
				airfield.assumeControl(theZone)
			end
			theAirfield:setCoalition(2) -- make it blue 
			if theZone.owner ~= 2 then -- only send cap event when capped
				airfield.airfieldCaptured(theAirfield)
			end 
		end
		
		if theZone.autoCap and theZone:testZoneFlag(theZone.autoCap, theZone.triggerMethod, "lastAutoCap") then 
			if theAirfield:autoCaptureIsOn() then 
				-- do nothing 
			else 
				airfield.relinquishControl(theZone)
			end
		end
	end
end

--
-- LOAD / SAVE 
-- 

function airfield.saveData()
	local theData = {}
	local allAF = {}
	for name, theZone in pairs(airfield.myAirfields) do 
		local theName = name 
		local theAirfield = theZone.airfield
		local AFData = {}
		AFData.autocapActive = theAirfield:autoCaptureIsOn()
		AFData.owner = theZone.owner 
		allAF[theName] = AFData 
	end
	theData.allAF = allAF
	return theData
end

function airfield.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("airfield")
	if not theData then 
		if airfield.verbose then 
			trigger.action.outText("+++airF persistence: no save data received, skipping.", 30)
		end
		return
	end
	
	local allAF = theData.allAF
	if not allAF then 
		if airfield.verbose then 
			trigger.action.outText("+++airF persistence: no airfield data, skipping", 30)
		end		
		return
	end
	
	for theName, AFData in pairs(allAF) do 
		local theZone = airfield.myAirfields[theName]
		if theZone then 
			-- synch airfield ownership, and auto-capture status 
			local theAirfield = theZone.airfield
			-- set current owner 
			theAirfield:autoCapture(false)
			theAirfield:setCoalition(AFData.owner)
			theZone.owner = AFData.owner
			-- set ownedBy#
			if theZone.ownedBy then 
				trigger.action.setUserFlag(theZone.ownedBy, theZone.owner)
			end 
			-- set owning mode: autocap or direct 
			theAirfield:autoCapture(AFData.autocapActive)

		else 
			trigger.action.outText("+++airF persistence: cannot synch airfield <" .. theName .. ">, skipping", 40)
		end
	end
end


--
-- start up
--
function airfield.readConfig()
	local theZone = cfxZones.getZoneByName("airfieldConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("airfieldConfig")
	end
	airfield.verbose = theZone.verbose 
	airfield.farps = theZone:getBoolFromZoneProperty("farps", false)
	
end

function airfield.start()
	if not dcsCommon.libCheck("cfx airfield", airfield.requiredLibs) 
	then return false end
	
	-- read config
	airfield.readConfig()
	
	-- read bases 
	local abZones = cfxZones.zonesWithProperty("airfield")
	for idx, aZone in pairs(abZones) do
		airfield.createAirFieldFromZone(aZone)
	end
	
	-- connect event handler
	world.addEventHandler(airfield)
	
	-- load any saved data 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = airfield.saveData
		persistence.registerModule("airfield", callbacks)
		-- now load my data 
		airfield.loadData()
	end
	
	-- start update in 1 second 
	timer.scheduleFunction(airfield.update, {}, timer.getTime() + 1)
	
	trigger.action.outText("cfx airfield v" .. airfield.version .. " loaded.", 30)
	return true 
end

if not airfield.start() then 
	trigger.action.outText("+++ aborted airfield v" .. airfield.version .. "  -- startup failed", 30)
	airfield = nil 
end

--[[--
	ideas: what if we made this airfield movable?
--]]--