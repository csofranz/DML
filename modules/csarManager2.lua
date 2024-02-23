csarManager = {}
csarManager.version = "3.2.0"
csarManager.ups = 1 

--[[-- VERSION HISTORY

 - 2.3.0 - dmlZones 
		 - onRoad attribute for CSAR mission Zones
		 - rndLoc support 
		 - triggerMethod support 
 - 2.3.1 - addPrefix option 
         - delay asynch OK (message only)
		 - offset zone on randomized soldier 
		 - smokeDist 
 - 2.3.2 - DCS 2.9 getCategory() fix 
 - 3.0.0 - moved mission creation out of update loop into own 
		 - removed cfxPlayer dependency
		 - new event manager 
		 - no longer single-proccing pilots 
		 - can also handle aircraft - isTroopCarrier 
- 3.1.0  - integration with scribe 
		 - expanded internal API: newMissionCB, invoked at addMission 
		 - expanded internal API: removedMissionCB
		 - added *rnd as option for csarName (requires "names")
		 - missions are sorted by distance 
		 - mission timeLimit range implemented 
		 - update handles time limit (pickup only)
		 - inflight status reflects time limit but will not time out 
		 - pickupSound option 
		 - lostSound option 
- 3.1.1  - birth clears troopsOnBoard
- 3.2.0  - inPopulated csar option 
		 - clearance csar attribute 
		 - maxTries csar attribute 

	INTEGRATES AUTOMATICALLY WITH playerScore 
	INTEGRATES WITH LIMITED AIRFRAMES 
	INTEGRATES AUTOMATICALLY WITH SCRIBE 
		 
--]]--
-- modules that need to be loaded BEFORE I run 
csarManager.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	"cfxZones", -- zones management for CSAR and CSAR Mission zones
	"nameStats", -- generic data module for weight 
	"cargoSuper",
}

-- unitConfigs contain the config data for any helicopter
-- currently in the game. The Array is indexed by unit name 
csarManager.unitConfigs = {}

--
-- CASR MISSION
--
csarManager.openMissions = {} -- all currently available missions
csarManager.csarBases = {} -- all bases where we can drop off rescued pilots. NOT a zone!
csarManager.csarZones = {} -- zones for spawning 

csarManager.missionID = 1 -- to create uuid
csarManager.rescueRadius = 70 -- must land within 50m to rescue
csarManager.hoverRadius = 30 -- must hover within 10m of unit 
csarManager.hoverAlt = 40 -- must hover below this alt 
csarManager.hoverDuration = 20 -- must hover for this duration
csarManager.rescueTriggerRange = 2000 -- when the unit pops smoke and radios
csarManager.beaconSound = "Radio_beacon_of_distress_on_121,5_MHz.ogg"
csarManager.pilotWeight = 120 -- kg for the rescued person. added to the unit's weight
csarManager.vectoring = true -- provide bearing and range 
--
-- callbacks
-- 
csarManager.csarCompleteCB = {}
csarManager.csarCreatedCB = {}
csarManager.csarRemoveCB = {}
csarManager.csarPickupCB = {}
--
-- CREATING A CSAR 
--
function csarManager.createDownedPilot(theMission, existingUnit)
	
	if not cfxCommander then 
		trigger.action.outText("+++CSAR: can't create mission, module cfxCommander is missing.", 30)
		return 
	end
	
	if not existingUnit then 
		local aLocation = {}
		local aHeading = 0 -- in rads
		local newTargetZone = theMission.zone
		-- if mission.radius is < 1 we do not randomize location 
		-- else location is somewhere in the middle of zone 
		-- csar mission zones randomize by themselves, and pass 
		-- a radius of <1, this is only for ejecting pilots 
		if newTargetZone.radius > 1 then 
			aLocation, aHeading = dcsCommon.randomPointOnPerimeter(newTargetZone.radius / 2 + 3, newTargetZone.point.x, newTargetZone.point.z) 
			-- we now move the entire zone so it centers on unit 
			newTargetZone.point.x = aLocation.x 
			newTargetZone.point.z = aLocation.z
		else 
			aLocation.x = newTargetZone.point.x
			aLocation.z = newTargetZone.point.z
			aHeading = math.random(360)/360 * 2 * 3.1415 
		end
		theMission.locations = {}
		local theBoyGroup = dcsCommon.createSingleUnitGroup(theMission.name, 
								"Soldier M4 GRG", -- "Soldier M4 GRG",
								aLocation.x, 
								aLocation.z, 
								-aHeading + 1.5) -- + 1.5 to turn inwards

		local theSideCJTF = dcsCommon.getACountryForCoalition(theMission.side)
		theMission.group = coalition.addGroup(theSideCJTF, 
											  Group.Category.GROUND, 
											  theBoyGroup)
		if theBoyGroup then 
			table.insert(theMission.locations, aLocation)
		else 
			trigger.action.outText("+++csar: FAILED to create csar!", 30)
		end
	else 
		theMission.group = existingUnit:getGroup()
		local allUnits = theMission.group:getUnits()
		for idx, aUnit in pairs(allUnits) do
			local loc = aUnit:getPoint() -- warning: won't work if group newly allocated!
			table.insert(theMission.locations, loc)
		end 
	end
	
	-- we now use commands to send radio transmissions
	local ADF = 20 + math.random(150) -- create a random number between 20 and 110 --> 200'000 .. 1'700'000 KHz = 200KHz .. 1'700 KHz 
	if theMission.freq then ADF = theMission.freq else theMission.freq = ADF end 
	local theCommands = cfxCommander.createCommandDataTableFor(theMission.group)
	local cmd = cfxCommander.createSetFrequencyCommand(ADF) -- freq in 10'000 Hz
	cfxCommander.addCommand(theCommands, cmd)
	cmd = cfxCommander.createTransmissionCommand(csarManager.beaconSound)
	cfxCommander.addCommand(theCommands, cmd)
	cfxCommander.scheduleCommands(theCommands, 2) -- in 2 seconds, so unit has time to percolate through DCS
end

function csarManager.createCSARMissionData(point, theSide, freq, name, numCrew, timeLimit, mapMarker, inRadius, parashootUnit) -- if parashootUnit is set, will not allocate new
	-- create a type 
--	if not timeLimit then timeLimit = -1 end
	if not point then return nil end 
	local newMission = {}
	newMission.side = theSide
	-- if "names" module active, allow random names if name 
	-- equals "*rnd"
	if names and names.uniqueFullName and name == "*rnd" then 
		name = names.uniqueFullName()
	elseif name == "*rnd" then 
		trigger.action.outText("+++scar: '*rnd' name requires the 'name' module for randomization. Using 'John Smith'", 30)
		name = "John Smith"
	end 
	
	if dcsCommon.stringStartsWith(name, "downed ") then 
		-- remove "downed" - it will be added again later
		name = dcsCommon.removePrefix(name, "downed ")
		if csarManager.verbose then 
			trigger.action.outText("+++csar: 'downed' procced for <" .. name .. ">", 30)
		end
	end
	if not inRadius then inRadius = csarManager.rescueRadius end 
	newMission.name = name .. " (ID#" .. csarManager.missionID .. ")" -- make it uuid-capable
	if csarManager.addPrefix then 
		newMission.name = "downed " .. newMission.name
	end
	newMission.zone = cfxZones.createSimpleZone(newMission.name, point, inRadius) --csarManager.rescueRadius)
	newMission.marker = mapMarker -- so it can be removed later
	newMission.isHot = false -- creating adversaries will make it hot, or when units are near. maybe implement a search later?
	-- detection and load stuff
	newMission.lastSmokeTime = -1000 -- so it will smoke immediately 
	newMission.messagedUnits = {} -- so we remember whom the unit radioed
	newMission.hoveringUnits = {} -- used when hovering 
	newMission.freq = freq -- if nil will make random 
			
	-- allocate units
	csarManager.createDownedPilot(newMission, parashootUnit)
	
	newMission.timeStamp = timer.getTime() -- now 
	
	-- set timeLimit if enabled 
	if timeLimit then 
		local theLimit = cfxZones.randomDelayFromPositiveRange(timeLimit[1], timeLimit[2]) * 60
--		trigger.action.outText("set time limit for mission to "..theLimit, 30)
		newMission.expires = timer.getTime() + theLimit 
	end 

	-- update counter and return
	csarManager.missionID = csarManager.missionID + 1

	return newMission
end

function csarManager.addMission(theMission)
--	trigger.action.outText("enter addMission", 30)
	table.insert(csarManager.openMissions, theMission)
	csarManager.invokeNewMissionCallbacks(theMission)
end

function csarManager.removeMission(theMission, pickup)
	if not pickup then pickup = false end 
	-- invoked when evacuee is PICKED UP!
	if not theMission then return end 
	local newMissions = {}
	for idx, aMission in pairs (csarManager.openMissions) do
		if aMission ~= theMission then 
			table.insert(newMissions, aMission)
		else 
--			csarManager.invokeRemovedMissionCallbacks(theMission)
			if pickup then 
				csarManager.invokePickUpCallbacks(theMission)
			end 
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

function csarManager.isCSARTarget(theGroup) 
	for idx, theMission in pairs(csarManager.openMissions) do
		if theMission.group == theGroup then return true end
	end 
	return false
end
--
-- UNIT CONFIG 
--
function csarManager.resetConfig(conf)
	-- reset only overwrites mission-relevant data
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
	if csarManager.unitConfigs[aName] then 
		csarManager.unitConfigs[aName] = nil 
	end
end

--
-- E V E N T   H A N D L I N G 
-- 
function csarManager:onEvent(event)
	-- make sure it has an initiator
	if not event.initiator then return end  
	local theUnit = event.initiator 
		
	if not dcsCommon.isPlayerUnit(theUnit) then return end -- not a player unit

	-- only proceed if troop carrier (no more helo checks, all troop carriers, so osprey and harrier can be used if so desired)
	if not dcsCommon.isTroopCarrier(theUnit, csarManager.troopCarriers) then return end 

	local ID = event.id
	if ID == 4 then  -- landed
		csarManager.heloLanded(theUnit)
	end
	
	if ID == 3 or ID == 55 then -- take off, postponed take-off 
		csarManager.heloDeparted(theUnit)
	end
	
	if ID == 5 then -- crash 
		csarManager.heloCrashed(theUnit)
		-- note: maybe not called in network missions.
		-- correction: is called in 2.9
	end	
	
	if ID == 15 then -- player helicopter birth 
		-- we need to set up comms for this unit 
		csarManager.setCommsMenu(theUnit)
		-- we also need to make sure that there are no 
		-- more troopsOnBoard

		local conf = csarManager.getUnitConfig(theUnit)
		conf.unit = theUnit
		conf.troopsOnBoard = {}

	end
	
end

--
-- CSAR LANDED
--
function csarManager.successMission(who, where, theMission)
	-- who is 
	-- where is 
	-- theMission is mission table 
	
	-- playerScore integration
	if cfxPlayerScore then 
		local theScore = theMission.score 
		if not theScore then theScore = csarManager.rescueScore end
		
		local theUnit = Unit.getByName(who)
		if theUnit and theUnit.getPlayerName then 
			local pName = theUnit:getPlayerName()
			if pName then 
				cfxPlayerScore.updateScoreForPlayer(pName, theScore)
				cfxPlayerScore.logFeatForPlayer(pName, "Evacuated " .. theMission.name)
			end
		end
	end
	
	-- scribe.integration 
	if scribe then 
		local theUnit = Unit.getByName(who)
		if theUnit and theUnit.getPlayerName then 
			local pName = theUnit:getPlayerName()
			scribe.playerRescueComplete(pName)
		end 
	end 
	
	trigger.action.outTextForCoalition(theMission.side,
		who .. " successfully evacuated " .. theMission.name .. " to " .. where .. "!", 
		30)
	
	-- now call callback for coalition side 
	-- callback has format callback(coalition, success true/false, numberSaved, descriptionText, theMission)
	csarManager.invokeCallbacks(theMission.side, true, 1, "success", theMission)

	trigger.action.outSoundForCoalition(theMission.side, csarManager.successSound)
	
	if csarManager.csarRedDelivered and theMission.side == 1 then 
		cfxZones.pollFlag(csarManager.csarRedDelivered, "inc", csarManager.configZone)
	end
	
	if csarManager.csarBlueDelivered and theMission.side == 2 then 
		cfxZones.pollFlag(csarManager.csarBlueDelivered, "inc", csarManager.configZone)
	end
	
	if csarManager.csarDelivered then 
		cfxZones.pollFlag(csarManager.csarDelivered, "inc", csarManager.configZone)
		if csarManager.verbose then 
			trigger.action.outText("+++csar: banging csarDelivered: <" .. csarManager.csarDelivered .. ">", 30)
		end 
	end
end

function csarManager.heloLanded(theUnit)
	-- when we have landed, 
	if not dcsCommon.isTroopCarrier(theUnit, csarManager.troopCarriers) then return end
	local conf = csarManager.getUnitConfig(theUnit)
	conf.unit = theUnit
	local theGroup = theUnit:getGroup()
	conf.id = theGroup:getID()
	conf.currentState = 0
	local thePoint = theUnit:getPoint()
	local mySide = theUnit:getCoalition()
	local myName = theUnit:getName()	

	-- first, check if we have landed in a CSAR dropoff zone 
	-- if so, drop off all loaded csar troops and award the 
	-- points or airframes 
	local allEvacuees = cargoSuper.getManifestFor(myName, "Evacuees") -- returns unlinked array 
											
	if csarManager.verbose then 
		trigger.action.outText("+++csar: helo <" .. myName .. "> landed with <" .. #allEvacuees .. "> evacuees on board.",30)
	end 
											
	if #allEvacuees > 0 then -- wasif #conf.troopsOnBoard > 0 then
		if csarManager.verbose then 
			trigger.action.outText("+++csar: checking bases:", 30)
		end
		
		for idx, base in pairs(csarManager.csarBases) do
			if csarManager.verbose then 
				trigger.action.outText("+++csar: base <" .. base.zone.name .. ">", 30)
			end
			-- check if the attached zone has changed hands
			-- this can happen if zone has its own owner 
			-- attribute and is conquered by another side 
			local currentBaseSide = base.side
			
			if base.zone.owner then 
				-- this zone is shared with capturable (owned)
				-- zone extensions like owned zone, FARP etc.
				-- use current owner
				currentBaseSide = base.zone.owner 
			end
			
			if currentBaseSide == mySide or 
			   currentBaseSide == 0 
			then  -- can always land in neutral
				if cfxZones.pointInZone(thePoint, base.zone) then 
					if csarManager.verbose or base.zone.verbose then 
						trigger.action.outText("+++csar: <" .. myName .. "> touch down in CSAR drop-off zone <" .. base.zone.name .. ">", 30)
					end 
					
					for idx, msn in pairs(conf.troopsOnBoard) do 
						-- each troopsOnBoard is actually the 
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

					end					
					-- reset weight 
					local totalMass = cargoSuper.calculateTotalMassFor(myName)
					trigger.action.setUnitInternalCargo(myName, totalMass) -- super recalcs
					conf.troopsOnBoard = {} -- empty out troops on board 
					-- we do *not* return so we can pick up troops on 
					-- a CSARBASE if they were dropped there
				else
					if csarManager.verbose or base.zone.verbose then 
						trigger.action.outText("+++csar: touchdown of <" .. myName .. "> occured outside of csar zone <" .. base.zone.name .. ">", 30)
					end
				end
			else -- not on my side 
				if csarManager.verbose or base.zone.verbose then 
					trigger.action.outText("+++csar: base <" .. base.zone.name .. "> is on side <" .. currentBaseSide .. ">, which is not on my side <" .. mySide .. ">.", 30)
				end 
			end -- my side?
		end -- for all bases 
		if csarManager.verbose then 
			trigger.action.outText("+++csar: complete bases check", 30)
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
				-- pick up this mission and remove it from the 
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
		
		local args = {}
		args.theName = theMission.name 
		args.mySide = mySide 
		args.unitName = myName 
		timer.scheduleFunction(csarManager.asynchSuccess, args, timer.getTime() + 3)
		
		csarManager.removeMission(theMission, true) -- picked up
		table.insert(conf.troopsOnBoard, theMission)
		theMission.group:destroy() -- will shut up radio as well
		theMission.group = nil
		-- now adapt for cargoSuper 
		local theMassObject = cargoSuper.createMassObject(
				csarManager.pilotWeight, 
				theMission.name, 
				theMission)
		cargoSuper.addMassObjectTo(
				myName, 
				"Evacuees", 
				theMassObject)
	end
	if didPickup then 
		local args = {}
		args.mySide = mySide 
		timer.scheduleFunction(csarManager.asynchSound, args, timer.getTime() + 3)
	end
	-- reset unit's weight based on people on board
	local totalMass = cargoSuper.calculateTotalMassFor(myName)
	trigger.action.setUnitInternalCargo(myName, totalMass) -- 10 kg as empty + per-unit time people 
	
end

function csarManager.asynchSuccess(args)
	-- currently, we always say "OK", will check for fail later 
	trigger.action.outTextForCoalition(args.mySide, args.unitName .. " has loaded " .. args.theName .. "!", 30)
end

function csarManager.asynchSound(args)
	trigger.action.outSoundForCoalition(args.mySide, csarManager.pickupSound)
end
--
--
-- Helo took off
--
--
function csarManager.heloDeparted(theUnit)
	if not dcsCommon.isTroopCarrier(theUnit, csarManager.troopCarriers) then return end
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
	if not dcsCommon.isTroopCarrier(theUnit, csarManager.troopCarriers) then return end
	-- problem: this isn't called on network games. 
	
	-- clean up 
	local conf = csarManager.getUnitConfig(theUnit)
	conf.unit = theUnit 
	local theGroup = theUnit:getGroup()
	conf.id = theGroup:getID()
	conf.currentState = -1 -- (we don't know)
	
	conf.troopsOnBoard = {}
	local myName = conf.name
	cargoSuper.removeAllMassForCargo(myName, "Evacuees") -- will allocate new empty table 
	csarManager.removeComms(conf.unit)
end

function csarManager.airframeCrashed(theUnit)
	-- called from airframe manager 
	if not dcsCommon.isTroopCarrier(theUnit, csarManager.troopCarriers) then return end
	local conf = csarManager.getUnitConfig(theUnit)
	conf.unit = theUnit 
	local theGroup = theUnit:getGroup()
	conf.id = theGroup:getID()
	-- may want to do something, for now just nothing
	
end

function csarManager.airframeDitched(theUnit)
	-- called from airframe manager 
	if not dcsCommon.isTroopCarrier(theUnit, csarManager.troopCarriers) then return end
	
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
	if not dcsCommon.isTroopCarrier(theUnit, csarManager.troopCarriers) then return end
	
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
	
	commandTxt = "Direction to nearest safe zone"
	theCommand =  missionCommands.addCommandForGroup(
				conf.id, 
				commandTxt,
				conf.myMainMenu,
				csarManager.redirectDirections, 
				{conf, "redirect"}
				)
	table.insert(conf.myCommands, theCommand)
end


function csarManager.redirectListCSARRequests(args)
	timer.scheduleFunction(csarManager.doListCSARRequests, args, timer.getTime() + 0.1)
end

function csarManager.openMissionsForSide(theSide)
	local theMissions = {}
	for idx, aMission in pairs(csarManager.openMissions) do 
		if aMission.side == theSide or aMission.side == 0 then 
			table.insert(theMissions, aMission)
		end
	end
	return theMissions
end

function csarManager.doListCSARRequests(args) 
	local now = timer.getTime()
	local conf = args[1]
	local param = args[2]
	local theUnit = conf.unit 
	local point = theUnit:getPoint()
	local theSide = theUnit:getCoalition() 
	
	local report = "\nCrews requesting evacuation\n"
	local openMissions = csarManager.openMissionsForSide(theSide)
	
	if #openMissions < 1 then 
		report = report .. "\nNo requests, all crew are safe."
	else 
		-- iterate through all missions and calc distance 
		for idx, mission in pairs(openMissions) do 
			local d = dcsCommon.distFlat(point, mission.zone.point) * 0.000539957
			d = math.floor(d * 10) / 10
			mission.dist = d
		end 
		-- sort openMissions by dist 
		table.sort(openMissions, 
				function (e1, e2) return e1.dist < e2.dist end 
			  )
		
		-- we may want to limit to n nearest missions
		local maxM = #openMissions
		if maxM > csarManager.maxMissions then maxM = csarManager.maxMissions end 
		for i=1,maxM do --in pairs(openMissions) do
			local mission = openMissions[i]
			local b = dcsCommon.bearingInDegreesFromAtoB(point, mission.zone.point)
			local status = "alive"
			if mission.expires then
				delta = math.floor ((mission.expires - now) / 60) 
				if delta < 10 then status = "+deteriorating+" end 
				if delta < 5 then status = "*critical*" end  
				if csarManager.verbose then 
					status = status .. "[" .. delta .. "]" -- remove me 
				end 
			end 
			if csarManager.vectoring then 
				report = report .. "\n".. mission.name .. ", bearing " .. b .. ", " ..mission.dist .."nm, " .. " ADF " .. mission.freq * 10 .. " kHz - " .. status
			else 
				-- leave out vectoring 
				report = report .. "\n".. mission.name .. " ADF " .. mission.freq * 10 .. " kHz - " .. status
			end
		end
	end
	local myBases = csarManager.getCSARBasesForSide(theSide) 
	if #myBases < 1 then 
		report = report .. "\n\nWARNING: NO CSAR BASES TO DELIVER EVACUEES TO"
	end
	report = report .. "\n"
	
	trigger.action.outTextForGroup(conf.id, report, 30)
	trigger.action.outSoundForGroup(conf.id, csarManager.actionSound)
end

function csarManager.redirectStatusCarrying(args)
	timer.scheduleFunction(csarManager.doStatusCarrying, args, timer.getTime() + 0.1)
end

function csarManager.doStatusCarrying(args) 
	local conf = args[1]
	local param = args[2]
	local theUnit = conf.unit 
	local now = timer.getTime()
	
	-- build status report
	local report = "\nCrew Rescue Status:\n"
	if #conf.troopsOnBoard < 1 then 
		report = report .. "\nWe have no evacuees on board"
	else 
		-- iterate through all troops onboard to get their status
		for i=1, #conf.troopsOnBoard do 
			local evacMission = conf.troopsOnBoard[i]
			report = report .. "\n".. i .. ") " .. evacMission.name 
			if evacMission.expires then 
				delta = math.floor ((evacMission.expires - now) / 60)
				if delta > 20 then
					report = report .. " is hurt but stable"
				elseif delta > 10 then
					report = report .. " is badly hurt"
				else 
					report = report .. " is in critical condition" -- or 'beat up, but will live'
				end
			else 
				report = report .. " is stable" -- or 'beat up, but will live'
			end 
		end
		
		report = report .. "\n\nTotal added weigth: " .. 10 + #conf.troopsOnBoard * csarManager.pilotWeight .. "kg" 
	end
	
	
	report = report .. "\n"
	
	trigger.action.outTextForGroup(conf.id, report, 30)
	trigger.action.outSoundForGroup(conf.id, csarManager.actionSound)
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
		report = "STRONGLY recommend we land first, sir!"
		trigger.action.outTextForGroup(conf.id, report, 30)
		trigger.action.outSoundForGroup(conf.id, csarManager.actionSound) -- "Quest Snare 3.wav")
		return 
	end
	
	if #conf.troopsOnBoard < 1 then
		report = "No evacuees on board."
		trigger.action.outTextForGroup(conf.id, report, 30)
		trigger.action.outSoundForGroup(conf.id, csarManager.actionSound) -- "Quest Snare 3.wav")
		
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
		--TODO: remove weight for this pilot!
		
		trigger.action.outTextForCoalition(theSide, myName .. " has aborted evacuating " .. msn.name .. ". New CSAR available.", 30)
		trigger.action.outSoundForCoalition(theSide, csarManager.actionSound) -- "Quest Snare 3.wav")
		
		-- recalc weight
		trigger.action.setUnitInternalCargo(myName, 10 + #conf.troopsOnBoard * csarManager.pilotWeight) -- 10 kg as empty + per-unit time people 
	end
	
end

function csarManager.redirectDirections(args)
	timer.scheduleFunction(csarManager.directions, args, timer.getTime() + 0.1)
end

function csarManager.directions(args)
	local conf = args[1]
	local param = args[2]
	local theUnit = conf.unit 
	local myName = theUnit:getName() 
	local theSide = theUnit:getCoalition()
	local report = "Nothing to report."
	
	-- get all safe zones 
	local myBases = csarManager.getCSARBasesForSide(theSide) 
	if #myBases < 1 then 
		report = "\n\nWARNING: NO CSAR BASES TO DELIVER EVACUEES TO"
	else
		-- find nearest zone 
		local p = theUnit:getPoint()
		p.y = 0 
		local dMin = math.huge 
		local theBase = nil 
		local dP = nil
		for idx, aBase in pairs(myBases) do 
			local z = aBase.zone 
			local zp = cfxZones.getPoint(z) 
			zp.y = 0 
			local d = dcsCommon.dist(p, zp)
			if d < dMin then 
				theBase = aBase
				dP = zp
				dMin = d
			end 
		end
		
		-- see if we are inside 
		if cfxZones.isPointInsideZone(p, theBase.zone) then 
			report = "\nYou are inside safe zone " .. theBase.name .. "."
		else 
		-- get bearing and distance 
			dMin = dMin / 1000 * 0.539957 -- in nm 
			
			dMin = math.floor(dMin * 10) / 10 
			local bearing = dcsCommon.bearingInDegreesFromAtoB(p, dP)
			report = "\nClosest safe zone for " .. myName .. " is " .. theBase.name ..", bearing " .. bearing .. " at " .. dMin .. "nm"
		end 
	end
	
	report = report .. "\n"
	trigger.action.outTextForGroup(conf.id, report, 30)
	trigger.action.outSoundForGroup(conf.id, csarManager.actionSound)	
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
	-- CSARBASE carries the coalition in the CSARBASE attribute
	csarBase.side = aZone:getCoalitionFromZoneProperty("CSARBASE", 0) 
	-- backward-compatibility to older versions. 
	-- will be deprecated 
	if aZone:hasProperty("coalition") then 
		csarBase.side = aZone:getCoalitionFromZoneProperty("CSARBASE", 0)
	end
	
	-- see if we have provided a name field, default zone name  
	csarBase.name = aZone:getStringFromZoneProperty("name", aZone.name) 
		
	table.insert(csarManager.csarBases, csarBase)
	
	if csarManager.verbose or aZone.verbose then 
		trigger.action.outText("+++csar: zone <" .. csarBase.name .. "> safe for side " .. csarBase.side, 30)
	end
end

function csarManager.getCSARBaseforZone(aZone)
	for idx, aCsarBase in pairs(csarManager.csarBases) do 
		if aCsarBase.zone == aZone then 
			return aCsarBase 
		end
	end
	return nil
end

function csarManager.getCSARBasesForSide(theSide) 
	local bases = {}
	for idx, aBase in pairs(csarManager.csarBases) do 
		if aBase.side == 0 or aBase.side == theSide then 
			table.insert(bases, aBase)
		end
	end
	return bases
end

--
-- U P D A T E 
-- ===========
-- 

--
-- updateCSARMissions: make sure evacuees are still alive 
--
function csarManager.updateCSARMissions()
	local newMissions = {}
	local now = timer.getTime()
	for idx, aMission in pairs (csarManager.openMissions) do
		-- see if mission timed out 
		local now = timer.getTime()
		local stillRunning = true  
		if aMission.expires then stillRunning = aMission.expires > now end
		local stillAlive = dcsCommon.isGroupAlive(aMission.group)

		-- if dead, set stillAlive to false 
		if stillRunning and stillAlive then 
			table.insert(newMissions, aMission)
		elseif stillAlive then 
			local msg = aMission.name .. " is no longer responding. Abort rescue."
			trigger.action.outTextForCoalition(aMission.side, msg, 30)
			trigger.action.outSoundForCoalition(aMission.side, csarManager.lostSound)
			csarManager.invokeCallbacks(aMission.side, false, 1, "lost", aMission)
			if aMission.group and Group.isExist(aMission.group) then 
--				trigger.action.outText("removing group", 30)
				Group.destroy(aMission.group)
			end 
		else 
			local msg = aMission.name .. " confirmed KIA, repeat KIA. Abort CSAR."	
			trigger.action.outTextForCoalition(aMission.side, msg, 30)
			trigger.action.outSoundForCoalition(aMission.side, csarManager.actionSound)
			csarManager.invokeCallbacks(aMission.side, false, 1, "KIA", aMission)
		end
	end
	csarManager.openMissions = newMissions -- this is the new batch
end

function csarManager.launchFlare(args)
	local color = args.color
	if color < 0 then color = math.random(4) - 1 end 
	local loc = args.loc -- with height 
	if csarManager.verbose then 
		trigger.action.outText("+++csarM: launching flare, c = " .. color .. " (" .. dcsCommon.flareColor2Text(color) .. ")", 30)
	end
	trigger.action.outTextForGroup(args.uID, "Launching flare!", 30)
	loc.y = loc.y + 3 -- launch 3 meters above ground 
	trigger.action.signalFlare(loc, color, 0)
end


-- WE ASSUME MISSIONS AREN'T TOO CLOSE TOGETHER TO 
-- MESS UP MESSAGING OR PICKUP 
-- if they are less than 2d apart, they can crosstalk each other 
function csarManager.update() -- every second
	-- schedule next invocation
	timer.scheduleFunction(csarManager.update, {}, timer.getTime() + 1/csarManager.ups)

	-- first, check the health of all csar misions and update the table of live units
	csarManager.updateCSARMissions()

	-- now scan through all helo groups and see if they are close to a 
	-- CSAR zone and initiate the help sequence 

	local allPlayerUnits = dcsCommon.getAllExistingPlayersAndUnits() -- indexed by player name

	for pname, aUnit in pairs(allPlayerUnits) do 
		if aUnit:inAir() and 
		  dcsCommon.isTroopCarrier(aUnit, csarManager.troopCarriers)
		  then -- troop carrier and is flying 
			local uPoint = aUnit:getPoint()
			local uName = aUnit:getName()
			local uGroup = aUnit:getGroup()
			local uID = uGroup:getID()
			local uSide = aUnit:getCoalition()
			local agl = dcsCommon.getUnitAGL(aUnit)
			local needsGC = false 
--			local hasMessaged = false 
			for idx, csarMission in pairs (csarManager.openMissions) do
				-- check if we are inside trigger range on the same side
				local mp = cfxZones.getPoint(csarMission.zone, true)
				local d = dcsCommon.distFlat(uPoint, mp)
				if ((uSide == csarMission.side) or (csarMission.side == 0) )
				and (d < csarManager.rescueTriggerRange) then 
					-- we are in trigger distance. if we did not notify before
					-- do it now, we ever only do this once for a unit for any mission 
					if not dcsCommon.arrayContainsString(csarMission.messagedUnits, uName) then 
						-- radio this unit with oclock and tell it they are in 2k range 
						-- also note if LZ is hot 
						local ownHeading = dcsCommon.getUnitHeadingDegrees(aUnit)
						local oclock = dcsCommon.clockPositionOfARelativeToB(csarMission.zone.point, uPoint, ownHeading) .. " o'clock"
						local msg = "\n" .. uName ..", " .. csarMission.name .. ". We can hear you, check your " .. oclock 
						if csarManager.useSmoke then msg = msg .. " - popping smoke" end
						if csarManager.useFlare then 
							if csarManager.useSmoke then 
								msg = msg .. " and will launch flare in a few seconds"
							else 
								msg = msg .. " - preparing flare"
							end
							-- schedule flare launch in 5-10 seconds
							local args = {}
							args.loc = mp 
							args.color = csarManager.flareColor
							args.uID = uID
							timer.scheduleFunction(csarManager.launchFlare, args, timer.getTime() + math.random(5))
						end
						msg = msg .. "."

						if csarMission.isHot then 
							msg = msg .. " Be advised: LZ is hot."
						end
						msg = msg .. "\n"
						trigger.action.outTextForGroup(uID, msg, 30)
						trigger.action.outSoundForGroup(uID, csarManager.actionSound) -- "Quest Snare 3.wav")
						table.insert(csarMission.messagedUnits, uName) -- remember that we messaged them so we don't do again
					end
					
					-- also pop smoke if not popped already, or more than 5 minutes ago
					if csarManager.useSmoke and  (timer.getTime() - csarMission.lastSmokeTime) >= 5 * 60 then 
						local smokePoint = dcsCommon.randomPointOnPerimeter(
							csarManager.smokeDist, csarMission.zone.point.x, csarMission.zone.point.z) 
						dcsCommon.markPointWithSmoke(smokePoint, csarManager.smokeColor)
						csarMission.lastSmokeTime = timer.getTime()
					end
					
					-- now check if we are inside hover range and alt 
					-- in order to simultate winch ops 
					-- if competition picked up, we skip this loop 
					local evacuee = nil 
					if csarMission.group then evacuee = csarMission.group:getUnit(1) end 
					if evacuee then 
						local ep = evacuee:getPoint()
						d = dcsCommon.distFlat(uPoint, ep)
						d = math.floor(d * 10) / 10
						if d < csarManager.rescueTriggerRange * 0.5 then 
							local ownHeading = dcsCommon.getUnitHeadingDegrees(aUnit)
							local oclock = dcsCommon.clockPositionOfARelativeToB(ep, uPoint, ownHeading) .. " o'clock"
							-- log distance 
							local hoverMsg = "Closing on " .. csarMission.name .. ", " .. d * 1 .. "m on your " .. oclock .. " o'clock"

							if d < csarManager.hoverRadius then 
								if (agl <= csarManager.hoverAlt) and (agl > 3) then 
									local hoverTime = csarMission.hoveringUnits[uName]
									if not hoverTime then 
										-- create new entry
										hoverTime = timer.getTime()
										csarMission.hoveringUnits[uName] = timer.getTime() 
									end
									hoverTime = timer.getTime() - hoverTime -- calculate number of seconds 
									local remainder = math.floor(csarManager.hoverDuration - hoverTime)
									if remainder < 1 then remainder = 1 end 
									hoverMsg = "Steady... " .. d * 1 .. "m to your " .. oclock .. " o'clock, winching... (" .. remainder .. ")" 
									if hoverTime > csarManager.hoverDuration then 
										-- we rescued the guy!
										hoverMsg = "We have " .. csarMission.name .. " safely on board!"
										local conf = csarManager.getUnitConfig(aUnit)
										-- mission now GC's after iteration csarManager.removeMission(csarMission)
										table.insert(conf.troopsOnBoard, csarMission)
										csarMission.group:destroy() -- will shut up radio as well
										csarMission.group = nil -- no more evacuees 
										needsGC = true -- need filtering missions 
										
										-- now handle weight using cargoSuper 
										local theMassObject = cargoSuper.createMassObject(
											csarManager.pilotWeight, 
											csarMission.name, 
											csarMission)
										cargoSuper.addMassObjectTo(
											uName, 
											"Evacuees", 
											theMassObject)
										local totalMass = cargoSuper.calculateTotalMassFor(uName)
										trigger.action.setUnitInternalCargo(uName, totalMass)
										
										if csarManager.verbose then 
											local allEvacuees = cargoSuper.getManifestFor(myName, "Evacuees") -- returns unlinked array 
											trigger.action.outText("+++csar: <" .. uName .. "> now has <" .. #allEvacuees .. "> groups of evacuees on board, totalling " .. totalMass .. "kg", 30)
										end
										
										--trigger.action.outTextForGroup(uID, hoverMsg, 30, true)
										trigger.action.outSoundForGroup(uID, csarManager.pickupSound) 

										--return -- we only ever rescue one 
									end -- hovered long enough 
									--trigger.action.outTextForGroup(uID, hoverMsg, 30, true)
									-- return -- only ever one winch op
								else -- too high for hover 
									hoverMsg = "Evacuee " .. d * 1 .. "m on your " .. oclock .. " o'clock; land or descend to between 10 and 90 AGL for winching"
									csarMission.hoveringUnits[uName] = nil -- reset timer 
								end
							else -- not inside hover dist
								-- remove the hover indicator for this 
								csarMission.hoveringUnits[uName] = nil 
							end 
							trigger.action.outTextForGroup(uID, hoverMsg, 30, true)
							--return -- only ever one winch op
						else 
							-- remove the hover indicator for this unit
							csarMission.hoveringUnits[uName] = nil
						end -- inside 2 * hover dist?
					else 
						-- somebody snatched the evacuee 
					end -- if has evacuee 
				end -- if in range
			end -- for all missions 
			-- now GC all missions if we lifted a pilot up (we no longer return after first succesful)
			if needsGC then 
				local filtered = {}
				for idx, csarMission in pairs(csarManager.openMissions) do 
					if csarMission.group then 
						table.insert(filtered, csarMission)
					end
				end
				csarManager.openMissions = filtered 
			end 
		end -- if in Air 
	end -- for all player units  
	
	-- now see and check if we need to spawn from a csar zone
	-- that has been told to spawn 
	for idx, theZone in pairs(csarManager.csarZones) do 
		-- check if their flag value has changed
		if theZone.startCSAR then 
			-- this should always be true, but you never know
--			local currVal = theZone:getFlagValue(theZone.startCSAR)
--			if currVal ~= theZone.lastCSARVal then 
			if theZone:testZoneFlag(theZone.startCSAR, theZone.triggerMethod, "lastCSARVal") then 
				local theMission = csarManager.createCSARMissionFromZone(theZone)
				csarManager.addMission(theMission)
				--theZone.lastCSARVal = currVal
				if csarManager.verbose or theZone.verbose then 
					trigger.action.outText("+++csar: started CSAR mission for <" .. theZone.csarName .. ">", 30)
				end
			end
		end
	end
end

function csarManager.createCSARMissionFromZone(theZone)
	-- set up random point in zone 
	local mPoint = theZone:getPoint()
	if theZone.rndLoc then mPoint = theZone:createRandomPointInZone() end 
	if theZone.onRoad then 
		mPoint.x, mPoint.z =  land.getClosestPointOnRoads('roads',mPoint.x, mPoint.z)
	elseif theZone.inPopulated then 
			local aPoint = theZone:createRandomPointInPopulatedZone(theZone.clearance, theZone.maxTries)
			mPoint = aPoint -- safety in case we need to mod aPoint 
	end 
	local theMission = csarManager.createCSARMissionData(
			mPoint, 
			theZone.csarSide, -- theSide
			theZone.csarFreq, -- freq
			theZone.csarName, -- name 
			theZone.numCrew, -- numCrew
			theZone.timeLimit, -- timeLimit
			theZone.csarMapMarker, -- mapMarker
			0.1, --theZone.radius) -- radius
			nil) -- parashoo unit 
	theMission.inPopulated = theZone.inPopulated -- transfer for csarFX
	return theMission
end

--
-- create a CSAR Mission for a unit 
-- 
function csarManager.createCSARforUnit(theUnit, pilotName, radius, silent, score) -- invoked with aircraft as theUnit, usually still in air
	if not silent then silent = false end 
	if not radius then radius = 1000 end 
	if not pilotName then pilotName = "Eddie" end 
	
	local point = theUnit:getPoint()
	local coal = theUnit:getCoalition() 
	
	local csarPoint = dcsCommon.randomPointInCircle(radius, radius/2, point.x, point.z) 
		
	csarPoint.y = csarPoint.z 
	local surf = land.getSurfaceType(csarPoint)	
	csarPoint.y = land.getHeight(csarPoint)
	
	-- when we get here, the terrain is ok, so let's drop the pilot 
	local theMission = csarManager.createCSARMissionData(
		csarPoint, -- point
		coal, -- side
		nil, -- freq 
		pilotName, -- name 
		1, -- num crew 
		nil, -- time limit 
		nil) -- map mark, inRadius, parashooUnit 
	theMission.score = score 
	csarManager.addMission(theMission)
	if not silent then 
		trigger.action.outTextForCoalition(coal, "MAYDAY MAYDAY MAYDAY! ".. pilotName .. " in " .. theUnit:getTypeName() .. " ejected, report good chute. Prepare CSAR!", 30)
		trigger.action.outSoundForGroup(coal, csarManager.actionSound) -- "Quest Snare 3.wav")
	end 
end

function csarManager.createCSARForParachutist(theUnit, name) -- invoked with parachute guy on ground as theUnit
	local coa = theUnit:getCoalition()
	local pos = theUnit:getPoint()
	-- unit DOES NOT HAVE GROUP!!! (unless water splashdown)
	-- create a CSAR mission now
	local theMission = csarManager.createCSARMissionData(pos, coa, nil, name, nil, nil, nil, 0.1, nil)
	csarManager.addMission(theMission)
	trigger.action.outTextForCoalition(coa, "MAYDAY MAYDAY MAYDAY! ".. name ..  " requesting extraction after eject!", 30)
	trigger.action.outSoundForGroup(coa, csarManager.actionSound)
end

--
-- csar (mission) zones 
-- 

function csarManager.processCSARBASE()
	local csarBases = cfxZones.zonesWithProperty("CSARBASE")
	-- now add all zones to my zones table, and init additional info
	-- from properties
	for k, aZone in pairs(csarBases) do
		csarManager.addCSARBase(aZone)
	end
end

function csarManager.addCSARZone(theZone)
	table.insert(csarManager.csarZones, theZone)
end

function csarManager.readCSARZone(theZone)
	-- zones have attribute "CSAR" 
	-- gather data, and then create a mission from this
	local mName = theZone:getStringFromZoneProperty("CSAR", theZone.name)
--	if mName == "" then mName = theZone.name end 
	local theSide = theZone:getCoalitionFromZoneProperty("coalition", 0)
	theZone.csarSide = theSide 
	theZone.csarName = mName -- now deprecating name attributes
	if theZone:hasProperty("name") then 
		theZone.csarName = theZone:getStringFromZoneProperty("name", "<none>")
	elseif theZone:hasProperty("csarName") then 
		theZone.csarName = theZone:getStringFromZoneProperty("csarName", "<none>")
	elseif theZone:hasProperty("pilotName") then 
		theZone.csarName = theZone:getStringFromZoneProperty("pilotName", "<none>")
	elseif theZone:hasProperty("victimName") then 
		theZone.csarName = theZone:getStringFromZoneProperty("victimName", "<none>")
	end
	
	theZone.csarFreq = theZone:getNumberFromZoneProperty("freq", 0)
	-- since freqs are set in 10kHz multiplier by DML
	-- we have to divide the feq given here by 10 
	theZone.csarFreq = theZone.csarFreq / 10
	if theZone.csarFreq < 0.01 then theZone.csarFreq = nil end 
	theZone.numCrew = 1 
	theZone.csarMapMarker = nil 
	if theZone:hasProperty("timeLimit") then
		local tmin, tmax = theZone:getPositiveRangeFromZoneProperty("timeLimit", 1)
--		trigger.action.outText("Read time limit for <" .. theZone.name .. ">: <" .. tmin .. ">, <" .. tmax .. ">", 30)
		theZone.timeLimit = {tmin, tmax}
	else 
		theZone.timeLimit = nil 
	end
--	theZone.timeLimit = theZone:getNumberFromZoneProperty("timeLimit", 0)
--	if theZone.timeLimit == 0 then theZone.timeLimit = nil else theZone.timeLimit = timeLimit * 60 end 
	
	local deferred = theZone:getBoolFromZoneProperty("deferred", false)
	
	if theZone:hasProperty("in?") then
		theZone.startCSAR = theZone:getStringFromZoneProperty("in?", "*none")
		theZone.lastCSARVal = theZone:getFlagValue(theZone.startCSAR)
	elseif theZone:hasProperty("start?") then
		theZone.startCSAR = theZone:getStringFromZoneProperty("start?", "*none")
		theZone.lastCSARVal = theZone:getFlagValue(theZone.startCSAR)
	elseif theZone:hasProperty("startCSAR?") then
		theZone.startCSAR = theZone:getStringFromZoneProperty("startCSAR?", "*none")
		theZone.lastCSARVal = theZone:getFlagValue(theZone.startCSAR)
	end 
	
	if theZone:hasProperty("score") then 
		theZone.score = theZone:getNumberFromZoneProperty("score", 100)
	end
	
	theZone.triggerMethod = theZone:getStringFromZoneProperty("triggerMethod", "change")
	theZone.rndLoc = theZone:getBoolFromZoneProperty("rndLoc", true)
	theZone.onRoad = theZone:getBoolFromZoneProperty("onRoad", false)
	theZone.inPopulated = theZone:getBoolFromZoneProperty("inPopulated", false)
	theZone.clearance = theZone:getNumberFromZoneProperty("clearance", 10)
	theZone.maxTries = theZone:getNumberFromZoneProperty("maxTries", 20)
	
	if theZone.onRoad and theZone.inPopulated then 
		trigger.action.outText("warning: competing 'onRoad' and 'inPopulated' attributes in zone <" .. theZone.name .. ">. Using 'onRoad'.", 30)
	end 

	if (not deferred) then 
		local mPoint = theZone:getPoint()
		if theZone.rndLoc then mPoint = theZone:createRandomPointInZone() end
		if theZone.onRoad then 
			mPoint.x, mPoint.z =  land.getClosestPointOnRoads('roads',mPoint.x, mPoint.z)
		elseif theZone.inPopulated then 
			local aPoint = theZone:createRandomPointInPopulatedZone(theZone.clearance, theZone.maxTries)
			mPoint = aPoint -- safety in case we need to mod aPoint 
		end 
		local theMission = csarManager.createCSARMissionData(
			mPoint, 
			theZone.csarSide, 
			theZone.csarFreq, 
			theZone.csarName, 
			theZone.numCrew, 
			theZone.timeLimit, 
			theZone.csarMapMarker,
			0.1, -- theZone.radius,
			nil) -- parashoo unit 
		csarManager.addMission(theMission)
	end

	-- add to list of startable csar
	if theZone.startCSAR then 
		csarManager.addCSARZone(theZone)
--		trigger.action.outText("csar: added <".. theZone.name .."> to deferred csar missions", 30)
	end 
	
	if deferred and not theZone.startCSAR then 
		trigger.action.outText("+++csar: warning - CSAR Mission in Zone <" .. theZone.name .. "> can't be started", 30)
	end
end

function csarManager.processCSARZones()
	local csarBases = cfxZones.zonesWithProperty("CSAR")
	-- now add all zones to my zones table, and init additional info
	-- from properties
	for k, aZone in pairs(csarBases) do
		csarManager.readCSARZone(aZone)
	end
end

--
-- Init & Start 
--

-- mission complete cs(coalition, success, numberRescued, notes, data)
function csarManager.invokeCallbacks(theCoalition, success, numRescued, notes, theMission)
	-- invoke anyone who wants to know that a group 
	-- of people was rescued.
	for idx, cb in pairs(csarManager.csarCompleteCB) do 
		cb(theCoalition, success, numRescued, notes, theMission)
	end
end

-- mission created cb(theMission)
function csarManager.invokeNewMissionCallbacks(theMission)
--trigger.action.outText("enter invoke new mission cb", 30)
	-- invoke anyone who wants to know that a new mission was created
	for idx, cb in pairs(csarManager.csarCreatedCB) do 
		cb(theMission)
	end
end

-- mission: picking up the evacuee 
function csarManager.invokePickUpCallbacks(theMission)
	-- invoke anyone who wants to know that a new mission was created
	for idx, cb in pairs(csarManager.csarPickupCB) do 
		cb(theMission)
	end
end

function csarManager.installCallback(theCB)
	table.insert(csarManager.csarCompleteCB, theCB)
end

function csarManager.installNewMissionCallback(theCB)
	table.insert(csarManager.csarCreatedCB, theCB)
end

function csarManager.installPickupCallback(theCB)
	table.insert(csarManager.csarPickupCB, theCB)
end

function csarManager.readConfigZone()
	csarManager.name = "csarManagerConfig" -- compat with cfxZones
	local theZone = cfxZones.getZoneByName("csarManagerConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("csarManagerConfig") 
	end 
	csarManager.configZone = theZone -- save for flag banging compatibility 
	
	csarManager.verbose = theZone.verbose 
	csarManager.ups = theZone:getNumberFromZoneProperty("ups", 1)
	
	csarManager.useSmoke = theZone:getBoolFromZoneProperty("useSmoke", true)
	csarManager.smokeColor = theZone:getSmokeColorStringFromZoneProperty("smokeColor", "blue")
	csarManager.smokeDist = theZone:getNumberFromZoneProperty("smokeDist", 30)
	csarManager.smokeColor = dcsCommon.smokeColor2Num(csarManager.smokeColor)
	
	csarManager.useFlare = theZone:getBoolFromZoneProperty("useFlare", true)
	csarManager.flareColor = theZone:getFlareColorStringFromZoneProperty("flareColor", "red")
	csarManager.flareColor = dcsCommon.flareColor2Num(csarManager.flareColor)
	
	if theZone:hasProperty("csarRedDelivered!") then 
		csarManager.csarRedDelivered = theZone:getStringFromZoneProperty("csarRedDelivered!", "*<none>")
	end
	
	if theZone:hasProperty("csarBlueDelivered!") then 
		csarManager.csarBlueDelivered = theZone:getStringFromZoneProperty("csarBlueDelivered!", "*<none>")
	end
	
	if theZone:hasProperty("csarDelivered!") then 
		csarManager.csarDelivered = theZone:getStringFromZoneProperty("csarDelivered!", "*<none>")
	end
	
	csarManager.rescueRadius = theZone:getNumberFromZoneProperty( "rescueRadius", 70)
	csarManager.hoverRadius = theZone:getNumberFromZoneProperty( "hoverRadius", 30)  
	csarManager.hoverAlt = theZone:getNumberFromZoneProperty("hoverAlt", 40) 
	csarManager.hoverDuration = theZone:getNumberFromZoneProperty( "hoverDuration", 20) 
	csarManager.rescueTriggerRange = theZone:getNumberFromZoneProperty("rescueTriggerRange", 2000)
	csarManager.beaconSound = theZone:getStringFromZoneProperty( "beaconSound", "Radio_beacon_of_distress_on_121,5_MHz.ogg") 
	csarManager.pilotWeight = theZone:getNumberFromZoneProperty("pilotWeight", 120)
	
	csarManager.rescueScore = theZone:getNumberFromZoneProperty( "rescueScore", 100)
	
	csarManager.actionSound = theZone:getStringFromZoneProperty( "actionSound", "Quest Snare 3.wav")
	csarManager.successSound = theZone:getStringFromZoneProperty("successSound", csarManager.actionSound)
	csarManager.pickupSound = theZone:getStringFromZoneProperty("pickupSound", csarManager.actionSound)
	csarManager.vectoring = theZone:getBoolFromZoneProperty("vectoring", true)
	csarManager.lostSound = theZone:getStringFromZoneProperty("lostSound", csarManager.actionSound)
	
	-- add own troop carriers 
	if theZone:hasProperty("troopCarriers") then 
		local tc = theZone:getStringFromZoneProperty("troopCarriers", "UH-1D")
		tc = dcsCommon.splitString(tc, ",")
		csarManager.troopCarriers = dcsCommon.trimArray(tc)
		if csarManager.verbose then 
			trigger.action.outText("+++casr: redefined troop carriers to types:", 30)
			for idx, aType in pairs(csarManager.troopCarriers) do 
				trigger.action.outText(aType, 30)
			end
		end
	end
	
	csarManager.addPrefix = theZone:getBoolFromZoneProperty("addPrefix", true)

	csarManager.maxMissions = theZone:getNumberFromZoneProperty("maxMissions", 15)
	if csarManager.verbose then 
		trigger.action.outText("+++csar: read config", 30)
	end 
end


function csarManager.start()
	-- make sure we have loaded all relevant libraries 
	if not dcsCommon.libCheck("cfx CSAR", csarManager.requiredLibs) then 
		trigger.action.outText("cf/x CSAR aborted: missing libraries", 30)
		return false 
	end

	-- read config
	csarManager.readConfigZone()

	-- now scan all zones that are CSAR drop-off for quick access
	csarManager.processCSARBASE()
	
	-- now scan all zones to create ME-placed CSAR missions
	-- and populate the available mission.
	csarManager.processCSARZones()

	-- install callbacks for helo-relevant events
	--dcsCommon.addEventHandler(csarManager.somethingHappened, csarManager.preProcessor, csarManager.postProcessor)
	world.addEventHandler(csarManager)

	-- now iterate through all player groups and install the CSAR Menu
	local allPlayerUnits = dcsCommon.getAllExistingPlayerUnitsRaw() 
	for pName, aUnit in pairs(allPlayerUnits) do 
		csarManager.setCommsMenu(aUnit)
	end
	
	-- start updating and track all helicopters in the air against missions
	csarManager.update()

	-- say hi!
	trigger.action.outText("cf/x CSAR Manager v" .. csarManager.version .. " started", 30)
	return true 
end

-- let's get rolling
if not csarManager.start() then 
	trigger.action.outText("cf/x CSAR Manager v" .. csarManager.version .. " FAILED to run", 30)
	csarManager = nil
end


--[[--
	improvements
	- need to stay on ground for x seconds to load troops 
	- hot lz
	- limit on troops aboard for transport
	- delay for drop-off 
		
	- repair o'clock 
		
	- compatibility: side/owner - make sure it is compatible 
	  with FARP, and landing on a FARP with opposition ownership 
	  will not disembark
	  	
	- when unloading one by menu, update weight!!!
		
	-- allow any airfied to be csarsafe by default, no longer *requires* csarbase

	-- minFreq, maxFreq settings for config and mission-individual
	
	-- may want to change if time limit was exceeded on return to tell 
	   player that they did not survive the transport 
--]]--