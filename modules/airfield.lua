airfield = {}
airfield.version = "2.3.0"
airfield.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
}
airfield.myAirfields = {} -- indexed by af name, zone that links to it 
airfield.gracePeriod = 3
airfield.allAirfields = {} -- inexed by af name, db entries: base, cat  

--[[--
	This module generates signals when the nearest airfield changes hands, 
	can force the coalition of an airfield, and always provides the 
	current owner as a value
	
	Version History
	2.0.0 - show all airfields option
		  - fully reworked show options
		  - unmanaged airfields are automatically updated 
		  - full color support
		  -- support for FARPS as well
	2.1.0 - added support for makeNeutral? 
	2.1.1 - bug fixing for DCS 2.9x airfield retrofit 
	2.2.0 - dmlZone:getCoalition() / masterowner adaptation for owner 
	2.3.0 - increased verbosity on persistence 
		  - airfield delayed release after data load 
		  - locked owner on start 
		  - release after start
		  - redrawing airfields when releasing
          - cleanup 		  
--]]--

-- init all airfields DB
function airfield.collectAll()
	local allBases = world.getAirbases() -- get all 
	local count = 0 
	local dropped = 0 
	for idx, aBase in pairs(allBases) do 
		local entry = {}
		-- ho! dcs 2.9.x retrofit screwed with Airfield.getCategory.
		local cat = aBase:getDesc().category
		-- cats: 0 = airfield, 1 = farp, 2 = ship 
		if (cat == 0) or (cat == 1) then 	
			local name = aBase:getName()
			entry.base = aBase 
			entry.cat = cat 
			-- entry.linkedTo holds zone if linked to. that how we know
			airfield.allAirfields[name] = entry
			count = count + 1
		else 
			dropped = dropped + 1
		end
	end
	if airfield.verbose then 
		trigger.action.outText("+++airF: init - count = <" .. count .. ">, dropped = <" .. dropped .. ">", 30)
	end 
end
--
-- setting up airfield
--
airfield.collector = {}
function airfield.createAirFieldFromZone(theZone)
	theZone.farps = theZone:getBoolFromZoneProperty("farps", false)
	local filterCat = 0
	if (theZone.farps) then filterCat = {0, 1} end -- bases and farps
	local p = theZone:getPoint()
	local theBase = dcsCommon.getClosestAirbaseTo(p, filterCat)
	theZone.airfield = theBase
	theZone.afName = theBase:getName() 
	
	-- set zone's owner 
	theZone.owner = theBase:getCoalition()
	theZone.mismatchCount = airfield.gracePeriod
	if theZone.verbose or airfield.verbose then 
		trigger.action.outText("+++airF: airfield zone <" .. theZone.name .. "> associates with <" .. theZone.afName .. ">, current owner is <" .. theZone.owner .. ">", 30)
	end
	
	theZone.method = theZone:getStringFromZoneProperty("method", "inc")
	theZone.triggerMethod = theZone:getStringFromZoneProperty("triggerMethod", "change")		
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
	if theZone:hasProperty("makeNeutral?") then 
		theZone.makeNeutral = theZone:getStringFromZoneProperty("makeNeutral?", "<none>")
		theZone.lastMakeNeutral = trigger.misc.getUserFlag(theZone.makeNeutral)
	end
	if theZone:hasProperty("autoCap?") then 
		theZone.autoCap = theZone:getStringFromZoneProperty("autoCap?", "<none>")
		theZone.lastAutoCap = trigger.misc.getUserFlag(theZone.autoCap)
	end
	
	theZone.directControl = theZone:getBoolFromZoneProperty("directControl", false)
	if theZone.directControl then 
		airfield.assumeControl(theZone)
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
	
	if theZone:hasProperty("ownedBy#") then 
		theZone.ownedBy = theZone:getStringFromZoneProperty("ownedBy#", "<none>")
		trigger.action.setUserFlag(theZone.ownedBy, theZone.owner)
	end
	
	-- index by name, and warn if duplicate associate 
	if airfield.myAirfields[theZone.afName] then 
		trigger.action.outText("+++airF: WARNING - zone <" .. theZone.name .. "> redefines airfield <" .. theZone.afName .. ">, discarded!", 30)
	else 
		airfield.myAirfields[theZone.afName] = theZone
	end
	
	theZone.show = theZone:getBoolFromZoneProperty("show", false)
	theZone.ownerMark = nil 
	
	-- individual colors, else default from config 
	theZone.redLine = theZone:getRGBAVectorFromZoneProperty("redLine", airfield.redLine)
	theZone.redFill = theZone:getRGBAVectorFromZoneProperty("redFill", airfield.redFill)
	theZone.blueLine = theZone:getRGBAVectorFromZoneProperty("blueLine", airfield.blueLine)
	theZone.blueFill = theZone:getRGBAVectorFromZoneProperty("blueFill", airfield.blueFill)
	theZone.neutralLine = theZone:getRGBAVectorFromZoneProperty("neutralLine", airfield.neutralLine)
	theZone.neutralFill = theZone:getRGBAVectorFromZoneProperty("neutralFill", airfield.neutralFill)
	
	airfield.showAirfield(theZone)

	theBase:autoCapture(false) -- lock down owner to avoid contested at beginning 	
	-- set up collector to free ownership later 
	if theZone:hasProperty("fixed") then 
		airfield.collector[theBase] = false -- autocap off after delay
	else 
		airfield.collector[theBase] = true 
	end 

	-- now mark this zone as handled 
	local entry = airfield.allAirfields[theZone.afName]
	if not entry then 
		trigger.action.outText("+++airF: WARNING - unlinked airfield <" .. theZone.afName .. "> for zone <" .. theZone.name .. ">", 30)
	else 
		entry.linkedTo = theZone -- only remember last, but that's enough.
	end
end

function airfield.markAirfieldOnMap(theAirfield, lineColor, fillColor)
	local markID = dcsCommon.numberUUID()
	local radius = 2000 -- meters 
	local p = theAirfield:getPoint()
	-- if there are runways, we center on first runway 
	local rws = theAirfield:getRunways()
	if rws then -- all airfields and farps have runways defined, but that array isnt filled for FARPS
		local rw1 = rws[1]
		if rw1 then 
			p.x = rw1.position.x 
			p.z = rw1.position.z
		end 
	end 
	p.y = 0 
	trigger.action.circleToAll(-1, markID, p, radius, lineColor, fillColor, 1, true, "")
	return markID 
end

function airfield.showAirfield(theZone)
	if not theZone then return end  
	if theZone.ownerMark then 
		-- remove previous mark 
		trigger.action.removeMark(theZone.ownerMark)
		theZone.ownerMark = nil 
	end 
	if not theZone.show then return end -- we don't show in map
	local lineColor = theZone.redLine -- {1.0, 0, 0, 1.0} -- red  
	local fillColor = theZone.redFill -- {1.0, 0, 0, 0.2} -- red 
	local owner = theZone:getCoalition() -- .owner
	if owner == 2 then 
		lineColor = theZone.blueLine -- {0.0, 0, 1.0, 1.0}
		fillColor = theZone.blueFill -- {0.0, 0, 1.0, 0.2}
	elseif owner == 0 or owner == 3 then 
		lineColor = theZone.neutralLine -- {0.8, 0.8, 0.8, 1.0}
		fillColor = theZone.neutralFill -- {0.8, 0.8, 0.8, 0.2}
	end
	theZone.ownerMark = airfield.markAirfieldOnMap(theZone.airfield, lineColor, fillColor)
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
function airfield.untendedCapture(theName, theBase) 
	if airfield.showAll and airfield.allAirfields[theName] then 
		-- we draw and handle all airfields, even those 
		-- without an attached handler zone 
		local theEntry = airfield.allAirfields[theName]
		if not theEntry.linkedTo then -- merely safety 
			if theEntry.ownerMark then 
				-- remove previous mark 
				trigger.action.removeMark(theEntry.ownerMark)
				theEntry.ownerMark = nil 
			end 
			local owner = theBase:getCoalition()
			local lineColor = airfield.redLine  
			local fillColor = airfield.redFill  
			if owner == 2 then 
				lineColor = airfield.blueLine 
				fillColor = airfield.blueFill 
			elseif owner == 0 or owner == 3 then 
				lineColor = airfield.neutralLine 
				fillColor = airfield.neutralFill 
			end
			theEntry.ownerMark = airfield.markAirfieldOnMap(theBase, lineColor, fillColor)
		end
	end
end

function airfield.airfieldCaptured(theBase)
	-- retrieve the zone that controls this airfield 
	local bName = theBase:getName()
	local theZone = airfield.myAirfields[bName]
	if not theZone then 
		airfield.untendedCapture(bName, theBase)
		return 
	end -- not attached to a zone 
	if theZone.verbose or airfield.verbose then 
		trigger.action.outText("+++airF: capturing <" .. bName .. "> for zone <" .. theZone.name .. ">", 30)
	end
	local newCoa = theBase:getCoalition()
	theZone.owner = newCoa 
	
	if theZone.verbose or airfield.verbose then 
		trigger.action.outText("+++airF: handling capture event/command for airfield <" .. bName .. "> with zone <" .. theZone:getName() .. ">", 30)
	end

	airfield.showAirfield(theZone) -- show if enabled

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
		local cat = desc.category -- never get cat directly! DCS 2.0 safe

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
			theZone.owner = 1 
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
			theZone.owner = 2 
		end

		if theZone.makeNeutral and theZone:testZoneFlag(theZone.makeNeutral, theZone.triggerMethod, "lastMakeNeutral") then 
			if theZone.verbose or airfield.verbose then 
				trigger.action.outText("+++airF: 'makeNeutral' triggered for airfield <" .. afName .. "> in zone <" .. theZone:getName() .. ">", 30)
			end
			if theAirfield:autoCaptureIsOn() then 
				-- turn off autoCap 
				airfield.assumeControl(theZone)
			end
			theAirfield:setCoalition(0) -- make it blue 
			if theZone.owner ~= 0 then -- only send cap event when capped
				airfield.airfieldCaptured(theAirfield) -- 0 cap will not cause any signals, but we do this anyway
			end 
			theZone.owner = 0
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


function airfield.GC()
	timer.scheduleFunction(airfield.GC, {}, timer.getTime() + 2)
	for afName, theZone in pairs(airfield.myAirfields) do 
		local theAirfield = theZone.airfield
		local afOwner = theAirfield:getCoalition()
		if afOwner == theZone.owner then 
			theZone.mismatchCount = airfield.gracePeriod
			-- all quiet
		elseif  afOwner == 3 then
			-- contested
			if theZone.verbose or airfield.verbose then 
				trigger.action.outText("+++airF: airfield <" .. theZone.name .. ">: ownership is contested.", 30)
			end
		else 
			if theZone.mismatchCount > 0 then 
				if theZone.verbose or airfield.verbose then 
					trigger.action.outText("we have a problem with owner for <" .. theZone.name .. ">: afO = <" .. afOwner .. ">, zo = <" .. theZone.owner .. ">, grace count = <" ..  theZone.mismatchCount..">", 30)
				end
				theZone.mismatchCount = theZone.mismatchCount - 1
			else 
				airfield.airfieldCaptured(theAirfield)
				theZone.mismatchCount = airfield.gracePeriod
				if theZone.verbose or airfield.verbose then 
					trigger.action.outText("+++airF: corrected ownership after grace period", 30)
				end
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

function airfield.releaseFields(releaseMe)
	for theAF, rel in pairs(releaseMe) do 
		theAF:autoCapture(rel)
		if airfield.verbose then 	
			trigger.action.outText("+++airF: releasing AF <" .. theAF:getName() .. "> to saved cap state <" .. dcsCommon.bool2Text(rel) .. ">", 30)
		end 
	end
	for name, theZone in pairs(airfield.myAirfields) do 
		airfield.showAirfield(theZone)
		if airfield.verbose or theZone.verbose then 
			trigger.action.outText("+++airF: redrawing <" .. theZone.name .. ">", 30)
		end
	end 
end

function airfield.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("airfield")
	if not theData then 
		if airfield.verbose then 
			trigger.action.outText("+++airF persistence: no save data received, skipping.", 30)
		end
		timer.scheduleFunction(airfield.releaseFields, airfield.collector, timer.getTime() + 2)
		return
	end
	
	local allAF = theData.allAF
	if not allAF then 
		if airfield.verbose then 
			trigger.action.outText("+++airF persistence: no airfield data, skipping", 30)
		end		
		timer.scheduleFunction(airfield.releaseFields, airfield.collector, timer.getTime() + 2)
		return
	end
	
	airfield.collector = {} -- overwrite existing 

	for theName, AFData in pairs(allAF) do 
		local theZone = airfield.myAirfields[theName]
		if theZone then 
			-- synch airfield ownership, and auto-capture status 
			local theAirfield = theZone.airfield
			-- set current owner 
			theAirfield:autoCapture(false)
			theAirfield:setCoalition(AFData.owner)
			theZone.owner = AFData.owner
			if airfield.verbose or theZone.verbose then 
				trigger.action.outText("+++airF: setting AF Zone <" .. theZone.name .. ">, owner from file to <" .. theZone.owner .. ">", 30)
			end 
			-- set ownedBy#
			if theZone.ownedBy then 
				trigger.action.setUserFlag(theZone.ownedBy, theZone.owner)
			end 
			-- set owning mode: autocap or direct 
			--theAirfield:autoCapture(AFData.autocapActive)
			airfield.collector[theAirfield] = AFData.autocapActive
		else 
			trigger.action.outText("+++airF persistence: cannot synch airfield <" .. theName .. ">, skipping", 40)
		end
	end
	timer.scheduleFunction(airfield.releaseFields, airfield.collector, timer.getTime() + 2)
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
	-- colors for line and fill 
	airfield.redLine = theZone:getRGBAVectorFromZoneProperty("redLine", {1.0, 0, 0, 1.0})
	airfield.redFill = theZone:getRGBAVectorFromZoneProperty("redFill", {1.0, 0, 0, 0.2})
	airfield.blueLine = theZone:getRGBAVectorFromZoneProperty("blueLine", {0.0, 0, 1.0, 1.0})
	airfield.blueFill = theZone:getRGBAVectorFromZoneProperty("blueFill", {0.0, 0, 1.0, 0.2})
	airfield.neutralLine = theZone:getRGBAVectorFromZoneProperty("neutralLine", {0.8, 0.8, 0.8, 1.0})
	airfield.neutralFill = theZone:getRGBAVectorFromZoneProperty("neutralFill", {0.8, 0.8, 0.8, 0.2})
	airfield.showAll = theZone:getBoolFromZoneProperty("show", false)
end

function airfield.showUnlinked() 
	for name, entry in pairs(airfield.allAirfields) do 
		if not entry.linkedTo then 
			airfield.untendedCapture(name, entry.base) 
		end
	end 
end

function airfield.start()
	if not dcsCommon.libCheck("cfx airfield", airfield.requiredLibs) 
	then return false end
	-- set up DB
	airfield.collectAll()
	-- read config
	airfield.readConfig()
	-- read bases 
	local abZones = cfxZones.zonesWithProperty("airfield")
	for idx, aZone in pairs(abZones) do
		airfield.createAirFieldFromZone(aZone)
	end
	
	-- show all unlinked 
	if airfield.showAll then airfield.showUnlinked() end 
	
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
	else 
		timer.scheduleFunction(airfield.releaseFields, airfield.collector, timer.getTime() + 2) -- release airfields when not loaded from storage
	end
	
	-- start update in 1 second 
	timer.scheduleFunction(airfield.update, {}, timer.getTime() + 1)
	
	-- start GC 
	timer.scheduleFunction(airfield.GC, {}, timer.getTime() + 2)
	
	trigger.action.outText("cfx airfield v" .. airfield.version .. " loaded.", 30)
	return true 
end

if not airfield.start() then 
	trigger.action.outText("+++ aborted airfield v" .. airfield.version .. "  -- startup failed", 30)
	airfield = nil 
end
