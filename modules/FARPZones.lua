FARPZones = {}
FARPZones.version = "2.1.1"
FARPZones.verbose = false 
--[[--
  Version History
  1.0.0 - Initial Version
  1.0.1 - support "none" as defender types
        - default types for defenders to none
  1.0.2 - hiddenRed, hiddenBlue, hiddenGrey
  1.1.0 - config zone 
		- rFormation attribute added 
		- verbose flag 
		- verbose cleanup ("FZ: something happened")
  1.2.0 - persistence 
        - handles contested state
  1.2.1 - now gracefully handles a FARP Zone that does not 
          contain a FARP, but is placed beside it
  2.0.0 - dmlZones 
  2.0.1 - locking up FARPS for the first five seconds 
		  loadMission handles lockup 
		  FARPs now can show their name
		  showTitle attribute 
		  refresh attribute (config)
  2.0.2 - clean-up 
		  verbosity enhancements 
  2.1.0 - integration with camp: needs repairs, produceResourceVehicles()
  2.1.1 - loading a farp from data respaws all defenders and resource vehicles 		  
  
--]]--

FARPZones.requiredLibs = {
	"dcsCommon", 
	"cfxZones", -- Zones, of course 
}
FARPZones.lockup = {} -- for the first 5 seconds of the game, released later

-- *** DOES NOT EXTEND ZONES, USES OWN STRUCT ***
-- *** SETS ZONE.OWNER IF PRESENT, POSSIBLE CONFLICT 
-- *** WITH OWNED ZONES 
-- *** DOES NOT WORK WITH AIRFIELDS! 
-- *** USE OWNED ZONES AND SPAWNZONES FOR AIRFIELDS 

--[[--
    Functioning, capturable FARPS with all services. To use, 
	place a FARP on a map, an a Zone that contains the FARP,
	then add the following attributes 
	
	Z O N E   A T T R I B U T E S 
	
	- FARP <anything>: indicate that this is a FARP ZONE. Must
	  contain at least one FARP inside the zone. The first FARP 
	  found will become main FARP to determine ownership
	- rPhiHDef - r, phi, heading separated by coma, eg 
	  <120, 245, 0> that defines radius and Phi (in degrees) for
	  the center position, and heading for the group of defenders
	  for this FARP. r, phi relative to ZONE center, not FARP
	- redDefenders - Type Strings for defender vehicles, coma
	  separated. e.g. "BTR-80,BTR-80" will create two BTR-80
	  vehicles when owned by RED
	- blueDefenders - Type Strings for defender vehicles, coma 
	  separated when owned by blue 
	- formation - formation for defenders, e.g. "grid".
	  optional, defaults to "circle-out". Span raidus is 100m
	- rPhiHRes - r, phi and H separated by coma to determine
      the location and heading of FARP Resopurces (services). 
	  They always auto-gen all vehicles for all services. They 
	  always spawn as "line_V" through center with radius 50 meters
	  Optional. Will spawn around zone center else. Remember that
	  all these vehicles MUST be within 150m of FARP Center
	- hidden - if true, no circle on map, else (default) visible
	  to all with owner color 
	  
--]]--

FARPZones.resourceTypes = {
	"M978 HEMTT Tanker", -- BLUE fuel 
	"M 818", -- BLUE ammo
	"M 818", -- Blue Power (repair???)
	"Hummer", -- BLUE ATC
	
	"ATMZ-5", -- RED refuel
	"KAMAZ Truck", -- rearming 
	"SKP-11", -- communication
	"ZiL-131 APA-80", -- Power
}

FARPZones.spinUpDelay = 30 -- seconds until FARP becomes operational after capture


FARPZones.allFARPZones = {} -- indexed by zone, returns dmlFARP struct 
FARPZones.startingUp = false -- not needed / read anywhere

-- FARP ZONE ACCESS
function FARPZones.addFARPZone(aFARP) -- entry with dmlFARP struct 
	FARPZones.allFARPZones[aFARP.zone] = aFARP
end

function FARPZones.removeFARPZone(aFARP)
	FARPZones.allFARPZones[aFARP.zone] = nil
end

function FARPZones.getFARPForZone(aZone) -- enter with zone 
	return FARPZones.allFARPZones[aZone] -- returns dmlFARP
end

function FARPZones.getFARPZoneByName(aName)
	for aZone, aFarp in pairs(FARPZones.allFARPZones) do
		if aZone.name == aName then return aFarp end
		-- we assume zone.name == farp.name 
	end
	trigger.action.outText("Unable to find FARP <" .. aName .. ">", 30)
	return nil 
end

function FARPZones.getFARPZoneForFARP(aFarp) 
	-- find the first FARP zone that associates with 
	-- aFARP (an airField)
	for idx, aFarpZone in pairs(FARPZones.allFARPZones) do 
		local associatedFarps = aFarpZone.myFarps 
		for itoo, assocF in pairs(associatedFarps) do
			if assocF == aFarp then return aFarpZone end
		end
	end
	
	return nil 
end

function FARPZones.createFARPFromZone(aZone)
	-- WARNING: WILL SET ZONE.OWNER 
	local theFarp = {}
	theFarp.zone = aZone 
	theFarp.name = aZone.name 
	theFarp.point = aZone:getPoint() -- failsafe 
	-- find the FARPS that belong to this zone
	local thePoint = aZone:getPoint()
	local mapFarps = dcsCommon.getAirbasesInRangeOfPoint(
		thePoint, 
		aZone.radius, 
		1 -- FARPS = Helipads
		)
	-- only #1 is significant for owner
	theFarp.myFarps = mapFarps 
	theFarp.owner = 0 -- start with neutral
	aZone.owner = 0 
	if #mapFarps == 0 then
		if aZone.verbose or FARPZones.verbose then 
			trigger.action.outText("***Farp Zones: no FARP found inside zone " .. aZone.name .. ", associating closest FARP", 30)
		end
		local closest = dcsCommon.getClosestAirbaseTo(thePoint, 1)
		if not closest then 
			trigger.action.outText("***FARP Zones: unable to find a FARP to associate zone <" .. aZone.name .. "> with.", 30)
			return 
		else
			if aZone.verbose or FARPZones.verbose then 
				trigger.action.outText("associated FARP <" .. closest:getName() .. "> with zone <" .. aZone.name .. ">", 30)
			end
		end
		mapFarps[1] = closest
	end 

		
	theFarp.mainFarp = theFarp.myFarps[1]
	theFarp.point = theFarp.mainFarp:getPoint() -- this is FARP, not zone!!!
	theFarp.owner = theFarp.mainFarp:getCoalition()
	aZone.owner = theFarp.owner
	-- lock up the faction until release in a few seconds after mission start
	theFarp.mainFarp:autoCapture(false)
	table.insert(FARPZones.lockup, theFarp.mainFarp) -- will be released in 5 seconds 
	if aZone.verbose then 
		trigger.action.outText("FARPzone <" .. aZone.name .. "> currently has owner <" .. aZone.owner .. ">", 30)
	end
	
	-- get r and phi for defenders 
	local rPhi = aZone:getVectorFromZoneProperty("rPhiHDef",3)

	-- get r and phi for facilities
	-- create a new defenderzone for this 
	local r = rPhi[1]
	local phi = rPhi[2] * 0.0174533 -- 1 degree = 0.0174533 rad
	local dx = aZone.point.x + r * math.cos(phi)
	local dz = aZone.point.z + r * math.sin(phi)
	local formRad = aZone:getNumberFromZoneProperty("rFormation", 100)
	
	theFarp.defZone = cfxZones.createSimpleZone(aZone.name .. "-Def", {x=dx, y = 0, z=dz}, formRad)
	theFarp.defHeading = rPhi[3]
	
	rPhi = {}
	rPhi = aZone:getVectorFromZoneProperty("rPhiHRes", 3)  

	r = rPhi[1]
	phi = rPhi[2] * 0.0174533 -- 1 degree = 0.0174533 rad
	dx = aZone.point.x + r * math.cos(phi)
	dz = aZone.point.z + r * math.sin(phi)
	
	theFarp.resZone = cfxZones.createSimpleZone(aZone.name .. "-Res", {x=dx, y = 0, z=dz}, 50)
	theFarp.resHeading = rPhi[3]
	
	-- get redDefenders - defenders produced when red owned 
	theFarp.redDefenders = aZone:getStringFromZoneProperty( "redDefenders", "none")
	-- get blueDefenders - defenders produced when blue owned
	theFarp.blueDefenders = aZone:getStringFromZoneProperty( "blueDefenders", "none")	
	-- get formation for defenders 
	theFarp.formation = aZone:getStringFromZoneProperty("formation", "circle_out")
	theFarp.count = 0 -- for uniqueness 
	theFarp.hideRed = aZone:getBoolFromZoneProperty("hideRed", false)
	theFarp.hideBlue = aZone:getBoolFromZoneProperty("hideBlue", false)
	theFarp.hideGrey = aZone:getBoolFromZoneProperty("hideGrey", false)
	theFarp.hidden = aZone:getBoolFromZoneProperty("hidden", false)
	theFarp.showTitle = aZone:getBoolFromZoneProperty("showTitle", true)
	theFarp.neutralProduction = aZone:getBoolFromZoneProperty("neutralProduction", false)
	return theFarp 
end

	
function FARPZones.drawFARPCircleInMap(theFarp)
	if not theFarp then return end 
	
	if theFarp.zone and theFarp.zone.markID then 
		-- remove previous mark
		trigger.action.removeMark(theFarp.zone.markID)
		theFarp.zone.markID = nil 
	end 
	
	if theFarp.zone and theFarp.zone.titleID then 
		-- remove previous mark
		trigger.action.removeMark(theFarp.zone.titleID)
		theFarp.zone.titleID = nil 
	end 
	
	if theFarp.hideRed and 
  	   theFarp.owner == 1 then 
		-- hide only when red 
		return 
	end 
	
	if theFarp.hideBlue and 
  	   theFarp.owner == 2 then 
		-- hide only when blue 
		return 
	end
	
	if theFarp.hideGrey and 
  	   theFarp.owner == 0 then 
		-- hide only when grey  
		return 
	end
	
	if theFarp.hidden then  
		return 
	end
	-- owner is 0 = neutral, 1 = red, 2 = blue 
	-- will save markID in zone's markID
	-- should be able to only show owned 
	-- draws 2km radius circle around main (first) FARP
	local aZone = theFarp.zone
	local thePoint = theFarp.point 
	local owner = theFarp.owner 
	
	local lineColor = {1.0, 0, 0, 1.0} -- red 
	local fillColor = {1.0, 0, 0, 0.2} -- red 
	
	if owner == 2 then 
		lineColor = {0.0, 0, 1.0, 1.0}
		fillColor = {0.0, 0, 1.0, 0.2}
	elseif owner == 0 then 
		lineColor = {0.8, 0.8, 0.8, 1.0}
		fillColor = {0.8, 0.8, 0.8, 0.2}
	end
	
	local theShape = 2 -- circle
	local markID = dcsCommon.numberUUID()

	trigger.action.circleToAll(-1, markID, thePoint, 2000, lineColor, fillColor, 1, true, "")
	aZone.markID = markID 
	if theFarp.showTitle then 
		aZone.titleID = aZone:drawText(aZone.name, 16, lineColor, {0.8, 0.8, 0.8, 0.0})
	end
	
end


function FARPZones.scheduedProduction(args)
	-- args contain [aFarp, owner]
	-- make sure that owner is still the same 
	-- and if so, branch to produce vehicles 
	-- ***write-though to zone.owner 
	
	local theFarp = args[1]
	local owner = args[2]
	
	-- make sure the farp wasn't conquered in the meantime
	if owner == theFarp.mainFarp:getCoalition() then 
		-- ok, still same owner , go ahead and spawn
		theFarp.owner = owner
		theFarp.zone.owner = owner 
		FARPZones.produceVehicles(theFarp)
		trigger.action.outTextForCoalition(theFarp.owner, "FARP " .. theFarp.name .. " has become operational!", 30)
		trigger.action.outSoundForCoalition(theFarp.owner, "Quest Snare 3.wav")
		
	end
end

function FARPZones.serviceNeedsRepair(theFarp) 
	if theFarp.owner == 0 then return false end 
	if not theFarp.resources then return false end -- no group yet 
	if not Group.isExist(theFarp.resources) then return true end 
	if theFarp.resources:getSize() < #FARPZones.resourceTypes then 
		return true 
	end 
	return false 
end

function FARPZones.produceResourceVehicles(theFarp, coa) 
	if theFarp.resources and Group.isExist(theFarp.resources) then --theFarp.resources:isExist() then 
		Group.destroy(theFarp.resources) --theFarp.resources:destroy()
		theFarp.resources = nil 
	end
	local unitTypes = FARPZones.resourceTypes -- an array 
	local theGroup, theData = cfxZones.createGroundUnitsInZoneForCoalition (
			coa, 
			theFarp.name .. "-R" .. theFarp.count, -- must be unique 
			theFarp.resZone,
			unitTypes,
			"line_v",
			theFarp.resHeading)
	theFarp.resources = theGroup 
	theFarp.resourceData = theData 		
	-- update unique counter
	theFarp.count = theFarp.count + 1
end 

function FARPZones.produceVehicles(theFarp)
	local theZone = theFarp.zone 
--	trigger.action.outText("entering veh prod run for farp zone <" .. theZone.name .. ">, owner is <" .. theFarp.owner .. ">", 30)
	--end
	
	-- abort production if farp is owned by neutral and 
	-- neutralproduction is false 
	if theFarp.owner == 0 and not theFarp.neutralProduction then 
		return 
	end 
	
	-- first, remove anything that may still be there 
	if theFarp.defenders and theFarp.defenders:isExist() then 
		theFarp.defenders:destroy()
	end
	
	if theFarp.resources and theFarp.resources:isExist() then 
		theFarp.resources:destroy()
	end
	
	theFarp.defenders = nil
	theFarp.resources = nil 

	-- spawn defenders 
	local owner = theFarp.owner -- coalition 
	local theTypes = theFarp.redDefenders
	if owner == 2 then theTypes = theFarp.blueDefenders end 
	local unitTypes = dcsCommon.splitString(theTypes, ",")
	if #unitTypes < 1 then 
		table.insert(unitTypes, "Soldier M4") -- make it one m4 trooper as fallback
	end
	
	if FARPZones.verbose then 
		trigger.action.outText("*** ENTER produce DEF vehicles, will produce " .. theTypes , 30)
	end 
	
	local theCoalition = theFarp.owner 
	
	if theTypes ~= "none" then 
		local theGroup, theData = cfxZones.createGroundUnitsInZoneForCoalition (
			theCoalition, 
			theFarp.name .. "-D" .. theFarp.count, -- must be unique 
			theFarp.defZone,
			unitTypes,
			theFarp.formation,
			theFarp.defHeading)
		-- we do not add these troops to ground troop management 
		theFarp.defenders = theGroup -- but we retain a handle just in case
		theFarp.defenderData = theData 
	end 
	
	-- spawn resource vehicles 
	FARPZones.produceResourceVehicles(theFarp, theCoalition) 
--[[--
	unitTypes = FARPZones.resourceTypes
	local theGroup, theData = cfxZones.createGroundUnitsInZoneForCoalition (
			theCoalition, 
			theFarp.name .. "-R" .. theFarp.count, -- must be unique 
			theFarp.resZone,
			unitTypes,
			"line_v",
			theFarp.resHeading)
	theFarp.resources = theGroup 
	theFarp.resourceData = theData
--]]--	
	-- update unique counter
	theFarp.count = theFarp.count + 1
end

--
-- EVENT PROCESSING
--
FARPZones.myEvents = {10, } --  10: S_EVENT_BASE_CAPTURED 
function FARPZones.isInteresting(eventID) 
	-- return true if we are interested in this event, false else 
	for key, evType in pairs(FARPZones.myEvents) do 
		if evType == eventID then return true end
	end
	return false 
end

function FARPZones.preProcessor(event)
	if not event then return false end 
	if not event.place then return false end 

	return FARPZones.isInteresting(event.id) 
end

function FARPZones.postProcessor(event)
	-- don't do anything
end

function FARPZones.somethingHappened(event)	
	-- *** writes to zone.owner
	local theUnit = event.initiator
	local ID = event.id
	
	--trigger.action.outText("FZ: something happened", 30) 
	local aFarp = event.place
	local zonedFarp = FARPZones.getFARPZoneForFARP(aFarp) 

	if not zonedFarp then
		if FARPZones.verbose then 
			trigger.action.outText("Hand change, NOT INTERESTING", 30)
		end 
		return 
	end 

	local newOwner = aFarp:getCoalition()	
	-- now, because we can load from file, we may get a notice 
	-- that a newly loaded state disagrees with new game state
	-- if so, we simply wink and exit 
	if newOwner == zonedFarp.owner then 
		trigger.action.outText("FARP <" .. zonedFarp.name .. "> aligned with persisted data", 30)
		return
	end
	
	-- let's ignore the owner = 3 (contested). Usually does not
	-- happen with an event, but let's be prepared 
	if newOwner == 3 then 
		if FARPZones.verbose then 
			trigger.action.outText("FARP <" .. zonedFarp.name .. "> has become contested", 30)
		end 
		return 
	end
	
	local blueRed = "Red" 
	if newOwner == 2 then blueRed = "Blue" end 
	trigger.action.outText("FARP " .. zonedFarp.zone.name .. " captured by " .. blueRed .."!", 30)
	trigger.action.outSound("Quest Snare 3.wav")
	zonedFarp.owner = newOwner
	zonedFarp.zone.owner = newOwner 
	-- update color in map 
	FARPZones.drawFARPCircleInMap(zonedFarp)
	
	-- remove all existing resources immediately, 
	-- no more service available 
	if zonedFarp.resources and zonedFarp.resources:isExist() then 
		zonedFarp.resources:destroy()
		zonedFarp.resources = nil 
	end
	
	-- now schedule operational after spin-up delay 
	timer.scheduleFunction(
		FARPZones.scheduedProduction,
		{zonedFarp, newOwner}, -- pass farp struct and current owner
		timer.getTime() + FARPZones.spinUpDelay
		)
	
end

--
-- Update / Refresh
--

function FARPZones.refreshMap()
	timer.scheduleFunction(FARPZones.refreshMap, {}, timer.getTime() + FARPZones.refresh)
	if FARPZones.verbose then 
		trigger.action.outText("+++Farp map refresh started", 30)
	end 
	
	for idx, theFARP in pairs(FARPZones.allFARPZones) do 
		FARPZones.drawFARPCircleInMap(theFARP)
	end
end

--
-- LOAD / SAVE 
--
function FARPZones.saveData()
	local theData = {}
	if FARPZones.verbose then 
		trigger.action.outText("+++frpZ: enter saveData", 30)
	end
	
	local farps = {}
	-- iterate all farp data and put them into a container each
	for theZone, theFARP in pairs(FARPZones.allFARPZones) do 
		fName = theZone.name 
		--trigger.action.outText("frpZ persistence: processing FARP <" .. fName .. ">", 30)
		local fData = {}
		fData.owner = theFARP.owner 
		fData.defenderData = dcsCommon.clone(theFARP.defenderData)
		fData.resourceData = dcsCommon.clone(theFARP.resourceData)
		dcsCommon.synchGroupData(fData.defenderData)
		if fData.defenderData and #fData.defenderData.units<1 then 
			fData.defenderData = nil 
		end
		dcsCommon.synchGroupData(fData.resourceData)
		if fData.resourceData and #fData.resourceData.units<1 then 
			fData.resourceData = nil 
		end
		farps[fName] = fData 
	end
	
	theData.farps = farps 
	return theData 
end

function FARPZones.loadMission()
	local theData = persistence.getSavedDataForModule("FARPZones")
	if not theData then 
		if FARPZones.verbose then 
			trigger.action.outText("frpZ: no save date received, skipping.", 30)
		end
		return
	end
	
	local farps = theData.farps 
	if farps then 
		for fName, fData in pairs(farps) do 
			local theFARP = FARPZones.getFARPZoneByName(fName)
			if theFARP then 
				theFARP.owner = fData.owner 
				theFARP.zone.owner = fData.owner 
				local theAB = theFARP.mainFarp
				theAB:setCoalition(theFARP.owner) -- FARP is in lockup.
				theFARP.defenderData = dcsCommon.clone(fData.defenderData)

				--[[--
				local groupData = fData.defenderData
				if groupData and #groupData.units > 0 then 
					local cty = groupData.cty 
					local cat = groupData.cat 
					theFARP.defenders = coalition.addGroup(cty, cat, groupData)
				end 
				
				groupData = fData.resourceData
				if groupData and #groupData.units > 0 then 
					local cty = groupData.cty 
					local cat = groupData.cat
					theFARP.resources = coalition.addGroup(cty, cat, groupData)
				end 
				--]]--
				FARPZones.produceVehicles(theFARP) -- do full defender and resource cycle 
				FARPZones.drawFARPCircleInMap(theFARP) -- mark in map
--				if (not theFARP.defenders) and (not theFARP.resources) then 
					-- we instigate a resource and defender drop 
--					FARPZones.produceVehicles(theFARP)
--				end
			else 
				trigger.action.outText("frpZ: persistence: FARP <" .. fName .. "> no longer exists in mission, skipping", 30)
			end
		end
	end
end

--
-- Start 
--
function FARPZones.releaseFARPS()
--	trigger.action.outText("Releasing hold on FARPS", 30)
	for idx, aFarp in pairs(FARPZones.lockup) do 
		aFarp:autoCapture(true)
--		trigger.action.outText("releasing farp <" .. aFarp:getName() .. ">", 30)
	end 
end

function FARPZones.readConfig()
	local theZone = cfxZones.getZoneByName("farpZonesConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("farpZonesConfig")
	end 
	
	FARPZones.verbose = theZone.verbose 
 	
	FARPZones.spinUpDelay = theZone:getNumberFromZoneProperty( "spinUpDelay", 30)
	
	FARPZones.refresh = theZone:getNumberFromZoneProperty("refresh", -1)
	
end


function FARPZones.start()
	-- check libs
	if not dcsCommon.libCheck("cfx FARP Zones", 
		FARPZones.requiredLibs) then
		return false 
	end
	
	FARPZones.startingUp = true -- not needed / read anywhere
	
	-- read config zone 
	FARPZones.readConfig()
	
	-- install callbacks for FARP-relevant events
	dcsCommon.addEventHandler(FARPZones.somethingHappened,
							  FARPZones.preProcessor,
							  FARPZones.postProcessor)

	-- set up persistence BEFORE we read zones, so weh know the 
	-- score during init phase
	local hasSaveData = false 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = FARPZones.saveData
		persistence.registerModule("FARPZones", callbacks)
		hasSaveData = persistence.hasData
	end
	
	-- collect all FARP Zones
	local theZones = cfxZones.getZonesWithAttributeNamed("FARP")
	for k, aZone in pairs(theZones) do 
		local aFARP = FARPZones.createFARPFromZone(aZone) -- read attributes from DCS
		FARPZones.addFARPZone(aFARP) -- add to managed zones 
		-- moved FARPZones.drawFARPCircleInMap(aFARP) -- mark in map 
		-- moved FARPZones.produceVehicles(aFARP) -- allocate initial vehicles
		if FARPZones.verbose then 
			trigger.action.outText("processed FARP <" .. aZone.name .. "> now owned by " .. aZone.owner, 30)
		end 
	end

	-- now produce all vehicles - whether from 
	-- save, or clean from start 
	if hasSaveData then 
		FARPZones.loadMission()
	else 
		for idx, aFARP in pairs (FARPZones.allFARPZones) do 
			FARPZones.drawFARPCircleInMap(aFARP) -- mark in map
			FARPZones.produceVehicles(aFARP) -- allocate initial vehicles
		end
	end 
	
	FARPZones.startingUp = false -- not needed / read anywhere
	
	timer.scheduleFunction(FARPZones.releaseFARPS, {}, timer.getTime() + 5)
	
	if FARPZones.refresh > 0 then 
		timer.scheduleFunction(FARPZones.refreshMap, {}, timer.getTime() + FARPZones.refresh)
	end 
	
	trigger.action.outText("cf/x FARP Zones v" .. FARPZones.version .. " started", 30)
	return true 
end


-- let's get rolling
if not FARPZones.start() then 
	trigger.action.outText("cf/x FARP Zones aborted: missing libraries", 30)
	FARPZones = nil 
end

--[[--
Improvements:
  per FARP/Helipad in zone: create resources (i.e. support multi 4-Pad FARPS out of the box
  
  make hidden farps only appear for owning side 
  
  make farps repair their service vehicles after a time, or simply refresh them every x minutes, to make the algo simpler 
 
 allow for ownership control via the airfield module?
--]]--