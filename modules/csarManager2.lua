csarManager = {}
csarManager.version = "2.0.3"
--[[-- VERSION HISTORY
 - 1.0.0 initial version 
 - 1.0.1 - smoke optional 
	     - airframeCrashed method for airframe manager 
		 - removed '(downed )' when re-picked up 
		 - fixed oclock
 - 1.0.2 - hover retrieval 
 - 1.0.3 - corrected a bug in oclock during hovering 
 - 1.0.4 - now correctly allocates pilot to coalition via dcscommon.coalition2county
 - 1.1.0 - pilot adds weight to unit 
         - module check 
 - 2.0.0 - weight managed via cargoSuper
 - 2.0.1 - getCSARBaseforZone()
         - check if zone landed in has owner attribute 
		   to provide compatibility with owned zones, 
		   FARPZones etc that keep zone.owner up to date 
 - 2.0.2 - use parametric csarManager.hoverAlt
		 - use hoverDuration
 - 2.0.3 - corrected bug in hoverDuration
 - 2.0.4 - guard in createCSARMission for cfxCommander 
 
--]]--
-- modules that need to be loaded BEFORE I run 
csarManager.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	"cfxZones", -- zones management foc CSAR and CSAR Mission zones
	"cfxPlayer", -- player monitoring and group monitoring 
	"nameStats", -- generic data module for weight 
	"cargoSuper",
--	"cfxCommander", -- needed if you want to hand-create CSAR missions
}

-- *** DOES NOT EXTEND ZONES *** BUT USES OWN STRUCT 

--[[--
	CSAR MANAGER
	============

 This module can create and manage CSAR missions, i.e. 
 create a unit on the ground, mark it on the map, handle
 if the unit is killed, create enemies in the vicinity 
 
 It will install a menu in any troop helicopter as
 determined by dcsCommon.isTroopCarrier() with the 
 option to list available csar mission. for each created mission
 it will give range and frequency for ADF
 When a helicopter is in range, it will set smoke to better 
 visually identify the location. 
 
 When the helicopter lands close enough to a downed pilot,
 the pilot is picket up automatically. Their weight is added
 to the unit, so it may overload!
 
 When the helicopter than lands in a CSARBASE Zone, the mission is 
 a success and a success callback is invoked automatically for 
 all picked up groups. All zones that have the CSARBASE property are
 CSAR Bases, but their coalition must be either neutral or match the 
 one of the unit that landed
 
 On start, it scans all zones for a CSAR property, and creates
 a CSAR mission with data taken from the properties in the 
 zone so you can easily create CSAR missions in ME
 
 WARNING: ASSUMES SINGLE UNIT PLAYER GROUPS
 ==========================================

 Main Interface
 - createCSARMission(location, side, numCrew, mark, clearing, timeout)
   creates a csar mission that can be tracked. 
   location is the position on the map
   side is the side the unit is on (neutal is for any side)
   numCrew the number of people (1-4)
   mark true if marked on map 
   clearing will create a clearing 
   timeout - time in seconds until pilots die. timer stops on pickup
   RETURNS true, "ok" --  false, "fail reason" (string)

 - createCSARAdversaries(location, side, numEnemies, radius, maxRadius)
   creates some random infantery randomized on a circle around the location 
   location - center, usually where the downed pilot is
   side - side of the enemy red/blue
   numEnemies - number of infantry 
   radius[, maxRadius] distance of the enemy troops

 - in ME, create at least one zone with a property named "CSARBASE" for 
   each side that supports csar missions. This is where the players 
   can drop off pilots that they rescued. If you have no CSARBASE zone 
   defined, you'll receive a warning for that side when you attempt a 
   rescue
   
 - in ME you can place zones with a CSAR attribute that will generate 
   a scar mission. Further attributes are "coalition" (red/blue), "name" (any name you like) and "freq" (for elt ADR, leave empty for random)
   
   NOTE:
     CSARBASE is compatible with the FARP Attribute of 
	 FARP Zones 
	 
   
--]]--
--
-- OPTIONS
--
csarManager.useSmoke = false -- smoke is a performance killer, so you can turn it off 


-- unitConfigs contain the config data for any helicopter
-- currently in the game. The Array is indexed by unit name 
csarManager.unitConfigs = {}
csarManager.myEvents = {3, 4, 5} -- 3 = take off, 4 = land, 5 = crash

--
-- CASR MISSION
--
csarManager.openMissions = {} -- all currently available missions
csarManager.csarBases = {} -- all bases where we can drop off rescued pilots

csarManager.missionID = 1 -- to create uuid
csarManager.rescueRadius = 70 -- must land within 50m to rescue
csarManager.hoverRadius = 30 -- must hover within 10m of unit 
csarManager.hoverAlt = 40 -- must hover below this alt 
csarManager.hoverDuration = 20 -- must hover for this duration
csarManager.rescueTriggerRange = 2000 -- when the unit pops smoke and radios
csarManager.beaconSound = "Radio_beacon_of_distress_on_121,5_MHz.ogg"
csarManager.pilotWeight = 120 -- kg for the rescued person. added to the unit's weight
--
-- callbacks
-- 
csarManager.csarCompleteCB = {}

--
-- CREATING A CSAR 
--
function csarManager.createDownedPilot(theMission)
	if not cfxCommander then 
		trigger.action.outText("+++CSAR: can't create mission, module cfxCommander is missing.", 30)
		return 
	end
	
	local aLocation = {}
	local aHeading = 0 -- in rads
	local newTargetZone = theMission.zone
	aLocation, aHeading = dcsCommon.randomPointOnPerimeter(newTargetZone.radius / 2 + 3, newTargetZone.point.x, newTargetZone.point.z) 

	local theBoyGroup = dcsCommon.createSingleUnitGroup(theMission.name, 
							"Soldier M4 GRG", -- "Soldier M4 GRG",
							aLocation.x, 
							aLocation.z, 
							-aHeading + 1.5) -- + 1.5 to turn inwards
	
	-- WARNING:
	-- coalition.addGroup takes the COUNTRY of the group, and derives the 
	-- coalition from that. So if mission.sie is 0, we use UN, if it is 1 (red) it
	-- is joint red, if 2 it is joint blue 
	local theSideCJTF = dcsCommon.coalition2county(theMission.side) -- get the correct county CJTF 
	theMission.group = coalition.addGroup(theSideCJTF, 
										  Group.Category.GROUND, 
										  theBoyGroup)
	
	if theBoyGroup then 
--		trigger.action.outText("+++csar: created csar!", 30)
	else 
		trigger.action.outText("+++csar: FAILED to create csar!", 30)
	end
	
	
	-- we now use commands to send radio transmissions
	local ADF = 20 + math.random(90)
	if theMission.freq then ADF = theMission.freq else theMission.freq = ADF end 
	local theCommands = cfxCommander.createCommandDataTableFor(theMission.group)
	local cmd = cfxCommander.createSetFrequencyCommand(ADF) -- freq in 10000 Hz
	cfxCommander.addCommand(theCommands, cmd)
	cmd = cfxCommander.createTransmissionCommand(csarManager.beaconSound)
	cfxCommander.addCommand(theCommands, cmd)
	cfxCommander.scheduleCommands(theCommands, 2) -- in 2 seconds, so unit has time to percolate through DCS
end

function csarManager.createCSARMissionData(point, theSide, freq, name, numCrew, timeLimit, mapMarker)
	-- create a type 
	if not timeLimit then timeLimit = -1 end
	if not point then return nil end 
	local newMission = {}
	newMission.side = theSide
	if dcsCommon.stringStartsWith(name, "(downed) ") then 
		-- remove "downed" - it will be added again later
		name = dcsCommon.removePrefix(name, "(downed) ")
	end
	
	newMission.name = "(downed) " .. name .. "-" .. csarManager.missionID -- make it uuid-capable
	newMission.zone = cfxZones.createSimpleZone(newMission.name, point, csarManager.rescueRadius)
	newMission.marker = mapMarker -- so it can be removed later
	newMission.isHot = false -- creating adversaries will make it hot, or when units are near. maybe implement a search later?
	-- detection and load stuff
	newMission.lastSmokeTime = -1000 -- so it will smoke immediately 
	newMission.messagedUnits = {} -- so we remember whom the unit radioed
	newMission.hoveringUnits = {} -- used when hovering 
	newMission.freq = freq -- if nil will make random 
			
	-- allocate units
	csarManager.createDownedPilot(newMission)
	
	-- update counter and return
	csarManager.missionID = csarManager.missionID + 1
	return newMission
end

function csarManager.addMission(theMission)
	table.insert(csarManager.openMissions, theMission)
end

function csarManager.removeMission(theMission)
	if not theMission then return end 
	local newMissions = {}
	for idx, aMission in pairs (csarManager.openMissions) do
		if aMission ~= theMission then 
			table.insert(newMissions, aMission)
		else 
		end
	end
	csarManager.openMissions = newMissions -- this is the new batch
end

function csarManager.removeMissionForGroup(theDownedGroup)
	if not theDownedGroup then return end 
	local newMissions = {}
	for idx, aMission in pairs (csarManager.openMissions) do
		if aMission.group ~= theDownedGroup then 
			table.insert(newMissions, aMission)
		else 
		end
	end
	csarManager.openMissions = newMissions -- this is the new batch
end
--
-- UNIT CONFIG 
--
function csarManager.resetConfig(conf)
	-- reset only ovberwrites mission-relevant data
	conf.troopsOnBoard = {} -- number of rescued missions
	local myName = conf.name
	cargoSuper.removeAllMassForCargo(myName, "Evacuees") -- will allocate new empty table 
	conf.currentState = -1 -- indetermined, 0 = landed 1 = airborne
	conf.timeStamp = timer.getTime()
end

function csarManager.createDefaultConfig(theUnit)
	local conf = {}
	conf.theUnit = theUnit 
	conf.name = theUnit:getName()
	csarManager.resetConfig(conf)
	--conf.unit = {} -- the unit this is linked to
	conf.myMainMenu = nil -- this is the main menu for group
	conf.myCommands = nil -- all commands in sub menu
	conf.id = theUnit:getID()
	return conf 
end


function csarManager.getUnitConfig(theUnit) -- will create new config if not existing
	if not theUnit then
		trigger.action.outText("+++csar: nil unit in get config!", 30)
		return nil 
	end
	local uName = theUnit:getName()
	local c = csarManager.getConfigForUnitNamed(uName)
	if not c then 
		c = csarManager.createDefaultConfig(theUnit)
		csarManager.unitConfigs[uName] = c 
	end
	return c 
end

function csarManager.getConfigForUnitNamed(aName)
	return csarManager.unitConfigs[aName]
end


function csarManager.removeConfigForUnitNamed(aName) 
	if not aName then return end 
	if csarManager.unitConfigs[aName] then csarManager.unitConfigs[aName] = nil end
end

--
-- E V E N T   H A N D L I N G 
-- 
function csarManager.isInteresting(eventID) 
	-- return true if we are interested in this event, false else 
	for key, evType in pairs(csarManager.myEvents) do 
		if evType == eventID then return true end
	end
	return false 
end

function csarManager.preProcessor(event)
	-- make sure it has an initiator
	if not event.initiator then return false end -- no initiator 
	local theUnit = event.initiator 
	local cat = theUnit:getCategory()
	if cat ~= Unit.Category.HELICOPTER then 
		return false 
	end
	
	--trigger.action.outText("+++csar: event " .. event.id .. " for cat = " .. cat .. " (helicopter?)  unit " .. theUnit:getName(), 30)
	
	if not cfxPlayer.isPlayerUnit(theUnit) then 
		--trigger.action.outText("+++csar: rejected event: " .. theUnit:getName() .. " not a player helo", 30)
		return false 
	end -- not a player unit
	return csarManager.isInteresting(event.id) 
end

function csarManager.postProcessor(event)
	-- don't do anything for now
end

function csarManager.somethingHappened(event)
	-- when this is invoked, the preprocessor guarantees that
	-- it's an interesting event
	-- unit is valid and player 
	-- airframe category is helicopter 
	local theUnit = event.initiator
	local ID = event.id
	
	local myType = theUnit:getTypeName()
--	trigger.action.outText("+++csar: event " .. ID .. " for player unit " .. theUnit:getName() .. " of type " .. myType, 30)
	
	if ID == 4 then  -- landed
		csarManager.heloLanded(theUnit)
	end
	
	if ID == 3 then -- take off
		csarManager.heloDeparted(theUnit)
	end
	
	if ID == 5 then -- crash 
		csarManager.heloCrashed(theUnit)
	end
	
	csarManager.setCommsMenu(theUnit)
end

--
--
-- CSAR LANDED
--
--

function csarManager.successMission(who, where, theMission)
	trigger.action.outTextForCoalition(theMission.side,
		who .. " successfully evacuated " .. theMission.name .. " to " .. where .. "!", 
		30)
	
	-- now call callback for coalition side 
	-- callback has format callback(coalition, success true/false, numberSaved, descriptionText)
	
	for idx, callback in pairs(csarManager.csarCompleteCB) do 
		callback(theMission.side, true, 1, "test")
	end
	trigger.action.outSoundForCoalition(theMission.side, "Quest Snare 3.wav")
end

function csarManager.heloLanded(theUnit)
	-- when we have landed, 
	if not dcsCommon.isTroopCarrier(theUnit) then return end
	local conf = csarManager.getUnitConfig(theUnit)
	conf.unit = theUnit
	local theGroup = theUnit:getGroup()
	conf.id = theGroup:getID()
	--conf.id = theUnit:getID()
	conf.currentState = 0
	local thePoint = theUnit:getPoint()
	local mySide = theUnit:getCoalition()
	local myName = theUnit:getName()	

	-- first, check if we have landed in a CSAR dropoff zone 
	-- if so, drop off all loaded csar troops and award the 
	-- points or airframes 
	local allEvacuees = cargoSuper.getManifestFor(myName, "Evacuees") -- returns unlinked array 
											
	if #allEvacuees > 0 then -- wasif #conf.troopsOnBoard > 0 then
		for idx, base in pairs(csarManager.csarBases) do
			-- check if the attached zone has changed hands
			-- this can happen if zone has its own owner 
			-- attribute and is conquered by another side 
			local currentBaseSide = base.side
			
			if base.zone.owner then 
				-- this zone is shared with capturable 
				-- zone extensions like owned zone, FARP etc.
				-- use current owner
				currentBaseSide = base.zone.owner 
--				trigger.action.outText("+++csar: overriding base.side with zone owner = " .. currentBaseSide .. " for csarB " .. base.name .. ", requiring " .. mySide .. " or 0 to land", 30)
			else 
--				trigger.action.outText("+++csar: base " .. base.name .. " has no owner - proceeding with side = " .. base.side .. " looking for " .. mySide, 30)
			end
			
			if currentBaseSide == mySide or 
			   currentBaseSide == 0 
			then  -- can always land in neutral
				if cfxZones.pointInZone(thePoint, base.zone) then 
					for idx, msn in pairs(conf.troopsOnBoard) do 
						-- each troopsOnboard is actually the 
						-- csar mission that I picked up 
						csarManager.successMission(myName, base.name, msn)
					end
					-- now use cargoSuper to retrieve all evacuees 
					-- and deliver them to safety 
					
					for idx, theMassObject in pairs(allEvacuees) do
						cargoSuper.removeMassObjectFrom(
											myName, 
											"Evacuees", 
											theMassObject)
						msn = theMassObject.ref 
						-- csarManager.successMission(myName, base.name, msn)
						-- to be done when we remove troopsOnBoard
					end					
					-- reset weight 
					local totalMass = cargoSuper.calculateTotalMassFor(myName)
					trigger.action.setUnitInternalCargo(myName, totalMass) -- super recalcs
--					trigger.action.outText("+++csar: delivered - set internal weight for " .. myName .. " to " .. totalMass, 30)
	
--					trigger.action.setUnitInternalCargo(myName, 10) -- 10 kg as empty 
					conf.troopsOnBoard = {} -- empty out troops on board 
					-- we do *not* return so we can pick up troops on 
					-- a CSARBASE if they were dropped there
					
				end
			end -- my side?
		end
	end -- check only if I'm carrying evacuees

	-- if not in a csar dropoff zone, check if we are 
	-- landed in a csar pickup zone, and start loading 
	
	local pickups = {}
	for idx, mission in pairs(csarManager.openMissions) do 
		if mySide == mission.side then 
			-- see if we are inside the mission's rescue range 
			local d = dcsCommon.distFlat(thePoint, mission.zone.point)
			if d < csarManager.rescueRadius then 
				-- pick up this mission an remove it from the 
				table.insert(pickups, mission)
			end
		end
	end
	
	-- now process the missions that I've picked up, transfer them to troopsOnBoard, and remove the dudes
	local didPickup = false 
	for idx, theMission in pairs(pickups) do
		trigger.action.outTextForCoalition(mySide,
		myName .. " is extracting " .. theMission.name .. "!", 
		30)
		didPickup = true;
		
		csarManager.removeMission(theMission)
		table.insert(conf.troopsOnBoard, theMission)
		theMission.group:destroy() -- will shut up radio as well
		theMission.group = nil
		-- now adapt for cargoSuper 
		theMassObject = cargoSuper.createMassObject(
				csarManager.pilotWeight, 
				theMission.name, 
				theMission)
		cargoSuper.addMassObjectTo(
				myName, 
				"Evacuees", 
				theMassObject)
	end
	if didPickup then 
		trigger.action.outSoundForCoalition(mySide, "Quest Snare 3.wav")
	end
	-- reset unit's weight based on people on board
	local totalMass = cargoSuper.calculateTotalMassFor(myName)
	-- WAS: trigger.action.setUnitInternalCargo(myName, 10 + #conf.troopsOnBoard * csarManager.pilotWeight) -- 10 kg as empty + per-unit time people 
	trigger.action.setUnitInternalCargo(myName, totalMass) -- 10 kg as empty + per-unit time people 
--	trigger.action.outText("+++csar: set internal weight for " .. myName .. " to " .. totalMass, 30)
	
end

--
--
-- Helo took off
--
--
function csarManager.heloDeparted(theUnit)
	if not dcsCommon.isTroopCarrier(theUnit) then return end
	-- if we have timed extractions (i.e. not instantaneous),
	-- then we need to check if we take off after the timer runs out 
	
	
	-- when we take off, all that needs to be done is to change the state 
	-- to airborne, and then set the status flag 
	local conf = csarManager.getUnitConfig(theUnit)
	conf.unit = theUnit
	local theGroup = theUnit:getGroup()
	conf.id = theGroup:getID()
	conf.currentState = 1 -- in the air 
	
	
end

--
-- 
-- Helo Crashed 
--
--

function csarManager.heloCrashed(theUnit)
	if not dcsCommon.isTroopCarrier(theUnit) then return end
	-- problem: this isn't called on network games. 
	
	-- clean up 
	local conf = csarManager.getUnitConfig(theUnit)
	conf.unit = theUnit 
	local theGroup = theUnit:getGroup()
	conf.id = theGroup:getID()
	conf.currentState = -1 -- (we don't know)
	--[[--
	if #conf.troopsOnBoard > 0 then 
		-- this is where we can create a new CSAR mission
		trigger.action.outSoundForCoalition(conf.id, theUnit:getName() .. " crashed while evacuating " .. #conf.troopsOnBoard .. " pilots. Survivors possible.", 30)
		trigger.action.outSoundForCoalition(conf.id, "Quest Snare 3.wav")
		for i=1, #conf.troopsOnBoard do 
			local msn = conf.troopsOnBoard[i] -- picked up unit(s)
			local theRescuedPilot = msn.name 
			-- create x new missions in 50m radius
			-- except for pilot, that will be called 
			-- from limitedAirframes
			csarManager.createCSARforUnit(theUnit, theRescuedPilot, 50, true)
		end
	end
	--]]--
	conf.troopsOnBoard = {}
	local myName = conf.name
	cargoSuper.removeAllMassForCargo(myName, "Evacuees") -- will allocate new empty table 
	csarManager.removeComms(conf.unit)
end

function csarManager.airframeCrashed(theUnit)
	-- called from airframe manager 
	if not dcsCommon.isTroopCarrier(theUnit) then return end
	local conf = csarManager.getUnitConfig(theUnit)
	conf.unit = theUnit 
	local theGroup = theUnit:getGroup()
	conf.id = theGroup:getID()
	-- may want to do something, for now just nothing
	
end

function csarManager.airframeDitched(theUnit)
	-- called from airframe manager 
	if not dcsCommon.isTroopCarrier(theUnit) then return end
	
	local conf = csarManager.getUnitConfig(theUnit)
	conf.unit = theUnit 
	local theGroup = theUnit:getGroup()
	conf.id = theGroup:getID()
	local theSide = theUnit:getCoalition()
	if #conf.troopsOnBoard > 0 then 
		-- this is where we can create a new CSAR mission
		trigger.action.outTextForCoalition(theSide, theUnit:getName() .. " abandoned while evacuating " .. #conf.troopsOnBoard .. " pilots. There many be survivors.", 30)
--		trigger.action.outSoundForCoalition(conf.id, "Quest Snare 3.wav")
		for i=1, #conf.troopsOnBoard do 
			local msn = conf.troopsOnBoard[i] -- picked up unit(s)
			local theRescuedPilot = msn.name 
			-- create x new missions in 50m radius
			-- except for pilot, that will be called 
			-- from limitedAirframes
			csarManager.createCSARforUnit(theUnit, theRescuedPilot, 50, true)
		end
	end
	-- NYI: re-populate from cargo 
	local myName = conf.name
	cargoSuper.removeAllMassForCargo(myName, "Evacuees") -- will allocate new empty table 
end

--
--
-- M E N U   H A N D L I N G   &   R E S P O N S E 
-- 
-- 
function csarManager.clearCommsSubmenus(conf)
	if conf.myCommands then 
		for i=1, #conf.myCommands do
			missionCommands.removeItemForGroup(conf.id, conf.myCommands[i])
		end
	end
	conf.myCommands = {}
end

function csarManager.removeCommsFromConfig(conf)
	csarManager.clearCommsSubmenus(conf)
	
	if conf.myMainMenu then 
		missionCommands.removeItemForGroup(conf.id, conf.myMainMenu) 
		conf.myMainMenu = nil
	end
end

function csarManager.removeComms(theUnit)
	if not theUnit then return end
	if not theUnit:isExist() then return end 
	
	local group = theUnit:getGroup() 
	local id = group:getID()
	local conf = csarManager.getUnitConfig(theUnit)
	conf.id = id
	conf.unit = theUnit 
	
	csarManager.removeCommsFromConfig(conf)
end


function csarManager.setCommsMenu(theUnit)
	if not theUnit then return end
	if not theUnit:isExist() then return end 
	
	-- we only add this menu to helicopter troop carriers
	-- will also filter out all non-helicopters as nice side effect
	if not dcsCommon.isTroopCarrier(theUnit) then return end
	
	local group = theUnit:getGroup() 
	local id = group:getID()
	local conf = csarManager.getUnitConfig(theUnit) -- will allocate if new. This is important since a group event can call this as well
	conf.id = id; -- we do this ALWAYS to it is current even after a crash 
	conf.unit = theUnit -- link back
	
	-- reset all coms now
	csarManager.removeCommsFromConfig(conf)
	
	-- ok, first, if we don't have an F-10 menu, create one 
	conf.myMainMenu = missionCommands.addSubMenuForGroup(id, 'CSAR Missions') 
	
	-- now we have a menu without submenus. 
	-- add our own submenus
	local commandTxt = "List active CSAR requests"
	local theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				csarManager.redirectListCSARRequests, 
				{conf, "hi there"}
				)
	table.insert(conf.myCommands, theCommand)
	commandTxt = "Status of rescued crew aboard"
	theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				csarManager.redirectStatusCarrying, 
				{conf, "hi there"}
				)
	table.insert(conf.myCommands, theCommand)
	
	commandTxt = "Unload one evacuee here (rescue later)"
	theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				csarManager.redirectUnloadOne, 
				{conf, "unload one"}
				)
	table.insert(conf.myCommands, theCommand)
end


function csarManager.redirectListCSARRequests(args)
	timer.scheduleFunction(csarManager.doListCSARRequests, args, timer.getTime() + 0.1)
end

function csarManager.doListCSARRequests(args) 
	local conf = args[1]
	local param = args[2]
	local theUnit = conf.unit 
	local point = theUnit:getPoint()
	
	--trigger.action.outText("+++csar: ".. theUnit:getName() .."  issued csar status request", 30)
	local report = "\nCrews requesting evacuation\n"
	if #csarManager.openMissions < 1 then 
		report = report .. "\nNo requests, all crew are safe."
	else 
		-- iterate through all troops onboard to get their status
		for idx, mission in pairs(csarManager.openMissions) do 
			local d = dcsCommon.distFlat(point, mission.zone.point) * 0.000539957
			d = math.floor(d * 10) / 10
			local b = dcsCommon.bearingInDegreesFromAtoB(point, mission.zone.point)
			local status = "alive"
			report = report .. "\n".. mission.name .. ", bearing " .. b .. ", " ..d .."nm, " .. " ADF " .. mission.freq .. "0 kHz - " .. status 
		end
	end
	
	if #csarManager.csarBases < 1 then 
		report = report .. "\n\nWARNING: NO CSAR BASES TO DELIVER EVACUEES"
	end
	
	report = report .. "\n"
	
	trigger.action.outTextForGroup(conf.id, report, 30)
	trigger.action.outSoundForGroup(conf.id, "Quest Snare 3.wav")
end

function csarManager.redirectStatusCarrying(args)
	timer.scheduleFunction(csarManager.doStatusCarrying, args, timer.getTime() + 0.1)
end

function csarManager.doStatusCarrying(args) 
	local conf = args[1]
	local param = args[2]
	local theUnit = conf.unit 
	
	--trigger.action.outText("+++csar: ".. theUnit:getName() .."  wants to know how their rescued troops are doing", 30)
	
	-- build status report
	local report = "\nCrew Rescue Status:\n"
	if #conf.troopsOnBoard < 1 then 
		report = report .. "\nWe have no evacuees on board"
	else 
		-- iterate through all troops onboard to get their status
		for i=1, #conf.troopsOnBoard do 
			local evacMission = conf.troopsOnBoard[i]
			report = report .. "\n".. i .. ") " .. evacMission.name 
			report = report .. " is stable" -- or 'beat up, but will live'
		end
		
		report = report .. "\n\nTotal added weigth: " .. 10 + #conf.troopsOnBoard * csarManager.pilotWeight .. "kg" 
	end
	
	
	report = report .. "\n"
	
	trigger.action.outTextForGroup(conf.id, report, 30)
	trigger.action.outSoundForGroup(conf.id, "Quest Snare 3.wav")
end

function csarManager.redirectUnloadOne(args)
	timer.scheduleFunction(csarManager.unloadOne, args, timer.getTime() + 0.1)
end

function csarManager.unloadOne(args)
	local conf = args[1]
	local param = args[2]
	local theUnit = conf.unit 
	local myName = theUnit:getName() 
	
	local report = "NYI: unload one"
	
	if theUnit:inAir() then 
		report = "STRONGLY recommend we land first, Sir!"
		trigger.action.outTextForGroup(conf.id, report, 30)
		trigger.action.outSoundForGroup(conf.id, "Quest Snare 3.wav")
		return 
	end
	
	if #conf.troopsOnBoard < 1 then
		report = "No evacuees on board."
		trigger.action.outTextForGroup(conf.id, report, 30)
		trigger.action.outSoundForGroup(conf.id, "Quest Snare 3.wav")
		
	else 
		-- simulate a crash but for one unit 
		local theSide = theUnit:getCoalition()
		-- this is where we can create a new CSAR mission
		i= #conf.troopsOnBoard 
		local msn = conf.troopsOnBoard[i] -- picked up unit(s)
		local theRescuedPilot = msn.name 
		-- create a new missions in 50m radius
		csarManager.createCSARforUnit(theUnit, theRescuedPilot, 50, true)
		conf.troopsOnBoard[i] = nil -- remove this mission
		trigger.action.outTextForCoalition(theSide, myName .. " has aborted evacuating " .. msn.name .. ". New CSAR available.", 30)
		trigger.action.outSoundForCoalition(theSide, "Quest Snare 3.wav")
		
		-- recalc weight
		trigger.action.setUnitInternalCargo(myName, 10 + #conf.troopsOnBoard * csarManager.pilotWeight) -- 10 kg as empty + per-unit time people 
	end
	
end
--
-- Player event callbacks
--
function csarManager.playerChangeEvent(evType, description, player, data)
	if evType == "newGroup" then 
		local theUnit = data.primeUnit
		if not dcsCommon.isTroopCarrier(theUnit) then return end 
		
		csarManager.setCommsMenu(theUnit) -- allocates new config
--		trigger.action.outText("+++csar: added " .. theUnit:getName() .. " to comms menu", 30)
		return 
	end
	
	if evType == "removeGroup" then 
--		trigger.action.outText("+++csar: a group disappeared", 30)
		local conf = csarManager.getConfigForUnitNamed(data.primeUnitName)
		if conf then 
			csarManager.removeCommsFromConfig(conf)
		end
		return
	end
	
	if evType == "leave" then 
		local conf = csarManager.getConfigForUnitNamed(player.unitName)
		if conf then 
			csarManager.resetConfig(conf)
		end
	end
	
	if evType == "unit" then 
		-- player changed units. almost never in MP, but possible in solo
		-- because of 1 seconds timing loop 
		-- will result in a new group appearing and a group disappearing, so we are good,
		-- except we need to reset the conf so no troops are carried any longer
		local conf = csarManager.getConfigForUnitNamed(data.oldUnitName) 
		if conf then 
			csarManager.resetConfig(conf)
		end
	end
end

--
-- CSAR Bases
--
-- properties: 
--  - zone : the zone 
--  - side : coalition 
--  - name : name of base, can be overriden with property

function csarManager.addCSARBase(aZone)
	local csarBase = {}
	csarBase.zone = aZone 
	local bName = cfxZones.getStringFromZoneProperty(aZone, "CSARBASE", "XXX")
	if bName == "XXX" then bName = aZone.name end 
	csarBase.name =  cfxZones.getStringFromZoneProperty(aZone, "name", bName) 
	
	-- read further properties like facilities that may 
	-- need to be matched 
	csarBase.side = cfxZones.getCoalitionFromZoneProperty(aZone, "coalition", 0) 
	
	table.insert(csarManager.csarBases, csarBase)
--	trigger.action.outText("+++csar: found base " .. csarBase.name .. " for side " .. csarBase.side, 30)	
end

function csarManager.getCSARBaseforZone(aZone)
	for idx, aCsarBase in pairs(csarManager.csarBases) do 
		if aCsarBase.zone == aZone then 
			return aCsarBase 
		end
	end
	return nil
end

--
--
-- U P D A T E 
-- ===========
-- 
-- 


--
-- updateCSARMissions: make sure evacuees are still alive 
--
function csarManager.updateCSARMissions()
	local newMissions = {}
	for idx, aMission in pairs (csarManager.openMissions) do
		local stillAlive = dcsCommon.isGroupAlive(aMission.group)
		-- now check if a timer was running to rescue this group
		-- if dead, set stillAlive to false 
		if stillAlive then 
			table.insert(newMissions, aMission)
		else 
			local msg = aMission.name .. " confirmed KIA, repeat KIA. Abort CSAR."	
			trigger.action.outTextForCoalition(aMission.side, msg, 30)
			trigger.action.outSoundForCoalition(aMission.side, "Quest Snare 3.wav")
		end
	end
	csarManager.openMissions = newMissions -- this is the new batch
end

function csarManager.update() -- every second
	-- schedule next invocation
	timer.scheduleFunction(csarManager.update, {}, timer.getTime() + 1)

	-- first, check the health of all csar misions and update the table of live units
	csarManager.updateCSARMissions()

	-- now scan through all helo groups and see if they are close to a 
	-- CSAR zone and initiate the help sequence 
	local allPlayerGroups = cfxPlayerGroups -- cfxPlayerGroups is a global, don't fuck with it! 
	-- contains per group a player record, use prime unit to access player's unit 
	for gname, pgroup in pairs(allPlayerGroups) do 
		local aUnit = pgroup.primeUnit --		get prime unit of that group
		if aUnit:isExist() and aUnit:inAir() then -- exists and is flying 
			local uPoint = aUnit:getPoint()
			local uName = aUnit:getName()
			local uGroup = aUnit:getGroup()
			local uID = uGroup:getID()
			local uSide = aUnit:getCoalition()
			local agl = dcsCommon.getUnitAGL(aUnit)
			if dcsCommon.isTroopCarrier(aUnit) then 
				-- scan through all available csar missions to see if we are close 
				-- enough to trigger comms 
				for idx, csarMission in pairs (csarManager.openMissions) do
					-- check if we are inside trigger range on the same side
					local d = dcsCommon.distFlat(uPoint, csarMission.zone.point)
					if (uSide == csarMission.side) and (d < csarManager.rescueTriggerRange) then 
						-- we are in trigger distance. if we did not notify before
						-- do it now 
						if not dcsCommon.arrayContainsString(csarMission.messagedUnits, uName) then 
							-- radio this unit with oclock and tell it they are in 2k range 
							-- also note if LZ is hot 
							local ownHeading = dcsCommon.getUnitHeadingDegrees(aUnit)
							local oclock = dcsCommon.clockPositionOfARelativeToB(csarMission.zone.point, uPoint, ownHeading) .. " o'clock"
							local msg = "\n" .. uName ..", " .. csarMission.name .. ". We can hear you, check your " .. oclock 
							if csarManager.useSmoke then msg = msg .. " - popping smoke" end
							msg = msg .. "."
							if csarMission.isHot then 
								msg = msg .. " Be advised: LZ is hot."
							end
							msg = msg .. "\n"
							trigger.action.outTextForGroup(uID, msg, 30)
							trigger.action.outSoundForGroup(uID, "Quest Snare 3.wav")
							table.insert(csarMission.messagedUnits, uName) -- remember that we messaged them so we don't do again
						end
						-- also pop smoke if not popped already, or more than 3 minutes ago
						if csarManager.useSmoke and  timer.getTime() - csarMission.lastSmokeTime > 179 then 
							local smokePoint = cfxZones.createHeightCorrectedPoint(csarMission.zone.point)
							trigger.action.smoke(smokePoint, 4 )
						end
						
						-- now check if we are inside hover range and alt 
						-- in order to simultate winch ops 
						-- WARNING: WE ALWAYS ONLY CHECK A SINGLE UNIT - the first alive
						local evacuee = csarMission.group:getUnit(1)
						if evacuee then 
							ep = evacuee:getPoint()
							d = dcsCommon.distFlat(uPoint, ep)
							d = math.floor(d * 10) / 10
							if d < csarManager.hoverRadius * 2 then
								local ownHeading = dcsCommon.getUnitHeadingDegrees(aUnit)
								local oclock = dcsCommon.clockPositionOfARelativeToB(ep, uPoint, ownHeading) .. " o'clock"
								-- log distance 
								local hoverMsg = "Closing on " .. csarMission.name .. ", " .. d * 3 .. "ft on your " .. oclock .. " o'clock"

								if d < csarManager.hoverRadius then 
									if (agl <= csarManager.hoverAlt) and (agl > 3) then 
										local hoverTime = csarMission.hoveringUnits[uName]
										if not hoverTime then 
											-- create new entry
											hoverTime = timer.getTime()
											csarMission.hoveringUnits[uName] = timer.getTime() 
										end
										hoverTime = timer.getTime() - hoverTime -- calculate number of seconds 
										remainder = math.floor(csarManager.hoverDuration - hoverTime)
										if remainder < 1 then remainder = 1 end 
										hoverMsg = "Steady... " .. d * 3 .. "ft to your " .. oclock .. " o'clock, winching... (" .. remainder .. ")" 
										if hoverTime > csarManager.hoverDuration then 
											-- we rescued the guy!
											hoverMsg = "We have " .. csarMission.name .. " safely on board!"
											local conf = csarManager.getUnitConfig(aUnit)
											csarManager.removeMission(csarMission)
											table.insert(conf.troopsOnBoard, csarMission)
											csarMission.group:destroy() -- will shut up radio as well
											csarMission.group = nil
											trigger.action.outTextForGroup(uID, hoverMsg, 30, true)
											trigger.action.outSoundForGroup(uID, "Quest Snare 3.wav")

											return -- we only ever rescue one 
										end -- hovered long enough 
										trigger.action.outTextForGroup(uID, hoverMsg, 30, true)
										return -- only ever one winch op
									else -- too high for hover 
										hoverMsg = "Evacuee " .. d * 3 .. "ft on your " .. oclock .. " o'clock; land or descend to between 10 and 90 AGL for winching"
										csarMission.hoveringUnits[uName] = nil -- reset timer 
									end
								else -- not inside hover dist
									-- remove the hover indicator for this 
									csarMission.hoveringUnits[uName] = nil 
								end 
								trigger.action.outTextForGroup(uID, hoverMsg, 30, true)
								return -- only ever one winch op
							else 
								-- remove the hover indicator for this unit
								csarMission.hoveringUnits[uName] = nil
							end -- inside 2 * hover dist?
							
						end -- has evacuee 
					end -- if in range
				end -- for all missions 
			end -- if troop carrier 
		end -- if exists 
	end -- for all players 
end

--
-- create a CSAR Mission for a unit 
-- 
function csarManager.createCSARforUnit(theUnit, pilotName, radius, silent)
	if not silent then silent = false end 
	if not radius then radius = 1000 end 
	if not pilotName then pilotName = "Eddie" end 
	
	local point = theUnit:getPoint()
	local coal = theUnit:getCoalition() 
	
	local csarPoint = dcsCommon.randomPointInCircle(radius, radius/2, point.x, point.z) 
	
	-- check the ground- water will kill the pilot 
	csarPoint.y = csarPoint.z 
	local surf = land.getSurfaceType(csarPoint)
	
	if surf == 2 or surf == 3 then 
		if not silent then 
			trigger.action.outTextForCoalition(coal, "Bad chute! Bad chute! ".. pilotName .. " did not survive ejection out of their " .. theUnit:getTypeName(), 30)
			trigger.action.outSoundForGroup(coal, "Quest Snare 3.wav")
		end
		return 
	end
	
	csarPoint.y = land.getHeight(csarPoint)
	
	-- when we get here, the terrain is ok, so let's drop the pilot 
	local theMission = csarManager.createCSARMissionData(
		csarPoint, 
		coal, 
		nil, 
		pilotName, 
		1, 
		nil, 
		nil)
	csarManager.addMission(theMission)
	if not silent then 
		trigger.action.outTextForCoalition(coal, "MAYDAY MAYDAY MAYDAY! ".. pilotName .. " in " .. theUnit:getTypeName() .. " ejected, report good chute. Prepare CSAR!", 30)
		trigger.action.outSoundForGroup(coal, "Quest Snare 3.wav")
	end 
end



--
-- Init & Start 
--

function csarManager.processCSARBASE()
	local csarBases = cfxZones.zonesWithProperty("CSARBASE")
	
	-- now add all zones to my zones table, and init additional info
	-- from properties
	for k, aZone in pairs(csarBases) do
		csarManager.addCSARBase(aZone)
	end
end

function csarManager.processCASRZones()
	local csarBases = cfxZones.zonesWithProperty("CSAR")
	
	-- now add all zones to my zones table, and init additional info
	-- from properties
	for k, aZone in pairs(csarBases) do
		-- gather data, and then create a mission from this
		local theSide = cfxZones.getCoalitionFromZoneProperty(aZone, "coalition", 0)
		local name = cfxZones.getZoneProperty(aZone, "name")
		local freq = cfxZones.getNumberFromZoneProperty(aZone, "freq", 0)
		if freq == 0 then freq = nil end 
		local numCrew = 1 
		local mapMarker = nil 
		local timeLimit = cfxZones.getNumberFromZoneProperty(aZone, "timeLimit", 0)
		if timeLimit == 0 then timeLimit = nil else timeLimit = timeLimit * 60 end 
		
		local theMission = csarManager.createCSARMissionData(aZone.point, 
			theSide, 
			freq, 
			name, 
			numCrew, 
			timeLimit, 
			mapMarker)
		csarManager.addMission(theMission)
	end
end


function csarManager.invokeCallbacks(theCoalition, success, numRescued, notes)
	-- invoke anyone who wants to know that a group 
	-- of people was rescued.
	for idx, cb in pairs(csarManager.csarCompleteCB) do 
		cb(theCoalition, success, numRescued, notes)
	end
end

function csarManager.installCallback(theCB)
	table.insert(csarManager.csarCompleteCB, theCB)
end


function csarManager.start()
	-- make sure we have loaded all relevant libraries 
	if not dcsCommon.libCheck("cfx CSAR", csarManager.requiredLibs) then 
		trigger.action.outText("cf/x CSAR aborted: missing libraries", 30)
		return false 
	end

	-- install callbacks for helo-relevant events
	dcsCommon.addEventHandler(csarManager.somethingHappened, csarManager.preProcessor, csarManager.postProcessor)

	-- now iterate through all player groups and install the CSAR Menu
	
	local allPlayerGroups = cfxPlayerGroups -- cfxPlayerGroups is a global, don't fuck with it! 
	-- contains per group a player record, use prime unit to access player's unit 
	for gname, pgroup in pairs(allPlayerGroups) do 
		local aUnit = pgroup.primeUnit -- get prime unit of that group
		csarManager.setCommsMenu(aUnit)
	end
	-- now install the new group notifier for new groups so we can remove and add CSAR menus 
	cfxPlayer.addMonitor(csarManager.playerChangeEvent)

	-- now scan all zones that are CSAR drop-off for quick access
	csarManager.processCSARBASE()
	
	-- now scan all zones to create ME-placed CSAR missions
	-- and populate the available mission.
	csarManager.processCASRZones()
	
	-- now call update so we can monitor progress of all helos, and alert them
	-- when they are close to a CSAR
	csarManager.update()

	-- say hi!
	trigger.action.outText("cf/x CSAR v" .. csarManager.version .. " started", 30)
	return true 
end

-- let's get rolling
if not csarManager.start() then 
	csarManager = nil
end


--[[--
	improvements
	- need to stay on ground for x seconds to load troops 
	- hot lz
	- hover recover 
	- limit on troops aboard for transport
	- delay for drop-off 
	
	- csar when: always, only on eject, 
	
	- repair o'clock 
	
	- nearest csarBase
	- red/blue csarbases 
	- weight 
	
	- compatibility: side/owner - make sure it is compatible 
	  with FARP, and landing on a FARP with opposition ownership 
	  will not disembark
	
--]]--