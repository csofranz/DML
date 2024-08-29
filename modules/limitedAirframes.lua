limitedAirframes = {}
limitedAirframes.version = "1.7.0"

limitedAirframes.warningSound = "Quest Snare 3.wav"
limitedAirframes.loseSound = "Death PIANO.wav"
limitedAirframes.winSound = "Triumphant Victory.wav"

limitedAirframes.requiredLibs = {
	"dcsCommon", 
	"cfxZones", 
}

--[[-- VERSION HISTORY
 - 1.5.0 - persistence support 
 - 1.5.1 - new "announcer" attribute
 - 1.5.2 - integration with autoCSAR: prevent limitedAF from creating csar 
           when autoCSAR is active 
 - 1.5.3 - ... but do allow it if not coming from 'ejected' so ditching 
           a plane will again create CSAR missions
   1.5.4 - red# and blue# instead of #red and #blue 
   1.6.0 - dmlZones 
		 - new hasUI attribute
		 - minor clean-up
		 - set numRed and numBlue on startup
   1.7.0 - dcs jul-11, jul-22 bug prevention 
		 - some cleanup 
		   
--]]--


limitedAirframes.safeZones = {} -- safezones are zones where a crash or change plane does not

limitedAirframes.myEvents = {5, 9, 30, 6, 20, 21, 15 } -- 5 = crash, 9 - dead, 30 - unit lost, 6 - eject, 20 - enter unit, 21 - leave unit, 15 - birth

-- guarantee a minimum of 2 seconds between events
-- for this we save last event per player 
limitedAirframes.lastEvents = {}
-- each time a plane crashes or is abandoned check 
-- that it's a player unit 
-- inside a crash free zone 
-- update the side's airframe credit 

limitedAirframes.currRed = 0
limitedAirframes.currBlue = 0

-- we record all unit names that contain a player 
-- so that we can check against these when we receive
-- an ejection event. We also keep a list of players
-- for good measure and their status
limitedAirframes.playerUnits = {}
limitedAirframes.players = {}
limitedAirframes.unitFlownByPlayer = {} -- to detect dead after 
		-- 21 (player left unit) we store on 15 (birth)
		-- which unit a player occupies. if player 
		-- then levaes and dead has a mismatch, we resolve 
		-- by not calling dead. 
		-- works if eject does not call player left unit 
		-- unit[unitname] = playername. if nil, no longer 
		-- occupied by player.
		
limitedAirframes.theCommand = nil 

--
-- READ CONFIG ZONE TO OVERRIDE SETTING
--
function limitedAirframes.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("limitedAirframesConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("limitedAirframesConfig") 
	end 
	limitedAirframes.config = theZone 
	limitedAirframes.name = "limitedAirframes" -- so we can call cfxZones with ourself as param 
	
	limitedAirframes.verbose = theZone.verbose
	if limitedAirframes.verbose then 
		trigger.action.outText("+++limA: found config zone!", 30) 
	end
	
	-- ok, for each property, load it if it exists
	limitedAirframes.enabled = theZone:getBoolFromZoneProperty("enabled", true)

	limitedAirframes.userCanToggle = theZone:getBoolFromZoneProperty( "userCanToggle", true)
	limitedAirframes.hasUI = theZone:getBoolFromZoneProperty("hasUI", true)
	limitedAirframes.maxRed = theZone:getNumberFromZoneProperty("maxRed", -1)
	
	limitedAirframes.maxBlue = theZone:getNumberFromZoneProperty("maxBlue", -1)
	limitedAirframes.currRed = limitedAirframes.maxRed
	limitedAirframes.currBlue = limitedAirframes.maxBlue

	if theZone:hasProperty("#red") then 
		limitedAirframes.numRed = theZone:getStringFromZoneProperty("#red", "*none")
	else 
		limitedAirframes.numRed = theZone:getStringFromZoneProperty("red#", "*none")
	end 
	if theZone:hasProperty("#blue") then 
		limitedAirframes.numBlue = theZone:getStringFromZoneProperty("#blue", "*none")
	else 
		limitedAirframes.numBlue = theZone:getStringFromZoneProperty("blue#", "*none")	
	end
	
	limitedAirframes.redWinsFlag = theZone:getStringFromZoneProperty("redWins!", "*none")

	if theZone:hasProperty("redWinsFlag!")  then 
		limitedAirframes.redWinsFlag = theZone:getStringFromZoneProperty("redWinsFlag!", "*none")
	end
	
	limitedAirframes.blueWinsFlag = theZone:getStringFromZoneProperty("blueWins!", "*none")
	if theZone:hasProperty("blueWinsFlag!")  then 
		limitedAirframes.blueWinsFlag = theZone:getStringFromZoneProperty("blueWinsFlag!", "*none")
	end
	
	limitedAirframes.method = theZone:getStringFromZoneProperty("method", "inc")
	
	if theZone:hasProperty("warningSound")  then 
		limitedAirframes.warningSound = theZone:getStringFromZoneProperty("warningSound", "none")
	end

	if theZone:hasProperty("winSound")  then 
		limitedAirframes.winSound = theZone:getStringFromZoneProperty("winSound", "none")
	end
	
	if theZone:hasProperty("loseSound")  then 
		limitedAirframes.loseSound = theZone:getStringFromZoneProperty("loseSound", "none")
	end	
	
	if limitedAirframes.numRed then 
		cfxZones.setFlagValue(limitedAirframes.numRed, limitedAirframes.currRed, limitedAirframes)
	end
	
	if limitedAirframes.numBlue then 
		cfxZones.setFlagValue(limitedAirframes.numBlue, limitedAirframes.currBlue, limitedAirframes)
	end
	limitedAirframes.announcer = theZone:getBoolFromZoneProperty( "announcer", true)
end

--
-- UNIT AND PLAYER HANDLING
--
function limitedAirframes.isKnownUnitName(uName)
	if limitedAirframes.playerUnits[uName] then return true end
	return false 
end

function limitedAirframes.getKnownUnitPilotByUnitName(uName)
	if limitedAirframes.isKnownUnitName(uName) then 
		return limitedAirframes.playerUnits[uName]
	end
	trigger.action.outText("+++lim: WARNING: " .. uName .. " is unknown!", 30)
	return "***Error"
end

function limitedAirframes.getKnownUnitPilotByUnit(theUnit)
	return limitedAirframes.getKnownUnitPilotByUnitName(theUnit:getName())
end

-- addPlayerUnit adds a unit as a known player unit 
-- and also adds the player if unknown
function limitedAirframes.addPlayerUnit(theUnit)
	local theSide = theUnit:getCoalition()
	local uName = "**XXXX**"
	if theUnit.getName then 
		uName = theUnit:getName()
	end 
--	if not uName then uName = "**XXXX**" end 
	local pName = "**????**" 
	if theUnit.getPlayerName then 
		pName = theUnit:getPlayerName()
	end 
--	if not pName then pName = "**????**" end 
	limitedAirframes.updatePlayer(pName, "alive")
	
	local desc = "unit <" .. uName .. "> controlled by <" .. pName .. ">"
	if not(limitedAirframes.isKnownUnitName(uName)) then 

	else 
		if limitedAirframes.playerUnits[uName] == pName then 
			desc = "player unit <".. uName .. "> controlled by <".. limitedAirframes.playerUnits[uName].."> re-seated"
		else 
			desc = "Updated player unit <".. uName .. "> from <".. limitedAirframes.playerUnits[uName].."> to <" .. pName ..">"
		end 
	end 
	limitedAirframes.playerUnits[uName] = pName 
	if limitedAirframes.announcer then 
		trigger.action.outTextForCoalition(theSide, desc, 30)
	end
end

function limitedAirframes.killPlayer(pName)
	limitedAirframes.updatePlayer(pName, "dead")

end

function limitedAirframes.killPlayerInUnit(theUnit)
	limitedAirframes.updatePlayerInUnit(theUnit, "dead")
end

function limitedAirframes.updatePlayerInUnit(theUnit, status)
	local uName = theUnit:getName()
	if not limitedAirframes.isKnownUnitName(uName) then 
		trigger.action.outText("+++lim: WARNING: updatePlayerInUnit to " .. status .. " with unknown pilot for plane", 30)
		return 
	end
	local pName = limitedAirframes.getKnownUnitPilotByUnitName(uName)
	limitedAirframes.updatePlayer(pName, status)
end

function limitedAirframes.updatePlayer(pName, status)
	if not pName then 
		trigger.action.outText("+++limA: WARNING - NIL pName in updatePlayer for status " .. status, 30)
		return
	end 
	local desc = ""
	if not limitedAirframes.players[pName] then 
		desc = "+++limA: NEW player " .. pName .. ": " .. status
	else 
		if limitedAirframes.players[pName] ~= status then 
			desc = "+++limA: CHANGE player " .. pName .. " " .. limitedAirframes.players[pName] .. " -> " .. status
		else 
			desc = "+++limA: player " .. pName .. " no change (" .. status .. ")"
		end
	end
	
	limitedAirframes.players[pName] = status 
end

function limitedAirframes.getStatusOfPlayerInUnit(theUnit)
	local uName = theUnit:getName()
	if not limitedAirframes.isKnownUnitName(uName) then 
		trigger.action.outText("+++lim: WARNING get player status for unknown pilot in plane " .. uName, 30)
		return nil
	end
	local pName = limitedAirframes.getKnownUnitPilotByUnitName(uName)
	return limitedAirframes.getStatusOfPlayerNamed(pName)
end

function limitedAirframes.getStatusOfPlayerNamed(pName)
	return limitedAirframes.players[pName]
end

--
-- E V E N T   H A N D L I N G 
-- 
--[[--
function limitedAirframes.XXXisKnownPlayerUnit(theUnit) 
	if not theUnit then return false end 
	local aName = theUnit:getName()
	if limitedAirframes.playerUnitNames[aName] ~= nil then 
		return true
	end
	return false 
end
--]]--

function limitedAirframes.isInteresting(eventID) 
	-- return true if we are interested in this event, false else 
	for key, evType in pairs(limitedAirframes.myEvents) do 
		if evType == eventID then return true end
	end
	return false 
end

function limitedAirframes.preProcessor(event)
	-- make sure it has an initiator
	if not event.initiator then return false end -- no initiator 
	local theUnit = event.initiator
	if not theUnit.getName then return false end -- DCS Jul-22 bug 
	local uName = theUnit:getName()
	

	if event.id == 6 then -- Eject, plane already divorced from player
		if limitedAirframes.isKnownUnitName(uName) then 
			return true
		end
		return false -- no longer of interest 
	end
	
	if event.id == 5 then -- crash, plane no longer attached to player
		if limitedAirframes.isKnownUnitName(uName) then
			return true
		end
		return false -- no longer of interest 
	end
	
	if not dcsCommon.isPlayerUnit(theUnit) then 
		-- not a player unit. Events 5 and 6 have been
		-- handled before, so we can safely ignore
		return false 
	end  

	-- exclude all ground units
	local theGroup = theUnit:getGroup() 
	local cat = theGroup:getCategory()
	if cat == Group.Category.GROUND then 
		return false 
	end

	-- only return true if defined as interesting 
	return limitedAirframes.isInteresting(event.id) 
end

function limitedAirframes.postProcessor(event)
	-- don't do anything
end

function limitedAirframes.somethingHappened(event)
	-- when this is invoked, the preprocessor guarantees that
	-- we have:
	-- * an interesting event
	-- * unit is valid and was a player's unit
	
	-- the events that are relevant for pilot loss are:
	-- * player entered: set pilot 'alive' state, maybe add new 
	--   unit and pilot to db of players and units 
	-- * pilot died - decrease pilot count, set 'dead' state
	-- * eject - decrease pilot count, 'MIA' state, csar possible
	-- * player left - when pilot status 'alive' - check safe zone 
	--               - outside safe zone, csar possible, set 'MIA'
	--               - when pilot anything but 'alive' - ignore
	
	if not event.initiator then 
		trigger.action.outText("limAir: ***WARNING: event (" .. ID .. "): no initiator, should not have been procced", 30)
		return 
	end
	
	local theUnit = event.initiator
	if not theUnit.getName then return end 
	local unitName = theUnit:getName()
	local ID = event.id
	local myType = theUnit:getTypeName()
	
	
	if ID == 20 then -- 20 ENTER UNIT
--		local pName = limitedAirframes.getKnownUnitPilotByUnit(theUnit)
--		if not pName then pName = "***UNKNOWN***" end 
		return 
	end
	
	if ID == 15 then -- birth - this one is called in network, 20 is too unreliable
		-- can set where birthed: runway, parking, air etc.
		limitedAirframes.addPlayerUnit(theUnit) -- will also update player and player status to 'alive'
		-- now procc a 'cheater' since we entered a new airframe/pilot
		limitedAirframes.checkPlayerFrameAvailability(event)
		local playerName = theUnit:getPlayerName()
		limitedAirframes.unitFlownByPlayer[unitName] = playerName
		-- TODO: make sure this is the ONLY plane the player
		-- is registered under, and mark mismatches
		if limitedAirframes.verbose then 
			trigger.action.outText("limAir: 15 -- player " .. playerName .. " now in " .. unitName, 30)
		end 
		return 
	end
	
	-- make sure unit's player pilot is known
	if not limitedAirframes.getKnownUnitPilotByUnitName(unitName) then
		trigger.action.outText("limAir: ***WARNING: Ignored player event (" .. ID .. "): unable to retrieve player name for " .. unitName, 30)
		return  -- plane no longer of interest cant retrieve pilot -- BUG!!!
	end
		
	-- event 6 - eject - plane divorced but player pilot is known
	if ID == 6 then -- eject
		limitedAirframes.pilotEjected(event)			
		return
	end
	
	-- event 5 - crash - plane divorced but player pilot is known 
	-- if pilot is still alive, this should now cause a pilot lost event if we are a helicopter 
	
	if ID == 5 then -- crash
		-- as of new processing, no longer relevant
		-- limitedAirframes.airFrameCrashed(event) 
		-- helicopters do not call died when helo
		-- crashes. so check if we are still seated=alive 
		-- and call pilot dead then 
		-- for some reason, pilot died also may not be called 
		-- so if pilot is still alive and not MIA, he's now dead.
		-- forget the helo check, this now applies to all 

		local pStatus = limitedAirframes.getStatusOfPlayerInUnit(theUnit)
		if pStatus == "alive" then 
			-- this frame was carrrying a live player 
			limitedAirframes.pilotDied(theUnit)
			return 
		else 
			if limitedAirframes.verbose then 
				trigger.action.outText("limAir: Crash of airframe detected - but player status wasn't alive (" .. pStatus .. ")", 30)
			end
			return 
		end 
	end 

-- removed dual 21 detection here 
	
	if ID == 21 then -- player left unit 
		-- remove pilot name from unit name 
		limitedAirframes.unitFlownByPlayer[unitName] = nil

		if limitedAirframes.verbose then 
			trigger.action.outText("limAir: 21 (player left) for unit " .. unitName , 30)
		end 
		-- player left unit. Happens twice
		-- check if player alive, else we have a ditch.
		limitedAirframes.handlePlayerLeftUnit(event)
		return 
	end
	
	
	if ID == 9 then -- died 
		local thePilot = limitedAirframes.unitFlownByPlayer[unitName]
		if not thePilot then 
			if limitedAirframes.verbose then 
				trigger.action.outText("+++limAir: 9 O'RIDE -- unit " .. unitName .. " was legally vacated before!", 30)
			end
			return 
		end
		limitedAirframes.pilotDied(theUnit)
		return 
	end
	
	if ID == 30 then -- unit lost
		return 
	end
	
	trigger.action.outText("limAir: WARNING unhandled: " .. ID .. " for player unit " .. theUnit:getName() .. " of type " .. myType, 30)
end

--
-- HANDLE VARIOUS SITUATIONS
--

function limitedAirframes.handlePlayerLeftUnit(event)
	local theUnit = event.initiator
	-- make sure the pilot is alive
	if limitedAirframes.getStatusOfPlayerInUnit(theUnit) ~= "alive" then 
		-- was already handled. simply exit
		local pName = limitedAirframes.getKnownUnitPilotByUnitName(theUnit:getName())
		local pStatus = limitedAirframes.getStatusOfPlayerInUnit(theUnit)
		-- player was already dead and has been accounted for 
		return 
	end
	
	-- check if the unit was inside a safe zone
	-- if so, graceful exit 
	local uPos = theUnit:getPoint() 
	local meInside = cfxZones.getZonesContainingPoint(uPos, limitedAirframes.safeZones)
	local mySide = theUnit:getCoalition()
	-- we now check the inAir 
	local isInAir = theUnit:inAir()

	for i=1, #meInside do 
		-- I'm inside all these zones. We look for the first
		-- that saves me 
		local theSafeZone = meInside[i]
		local isSafe = false
		if mySide == 1 then 
			isSafe = theSafeZone.redSafe 
		elseif mySide == 2 then 
			isSafe = theSafeZone.blueSafe
		else 
			isSafe = true 
		end
		
		if theSafeZone.owner then
			-- owned zone. olny allow in neutral or owned by same side 
			isSafe = isSafe and (mySide == theSafeZone.owner or theSafeZone.owner == 0)
			if limitedAirframes.verbose then 
				trigger.action.outText("+++limA: " .. theSafeZone.name .. " ownership: myside = " .. mySide .. " zone owner is " .. theSafeZone.owner, 30)
			end 
		end
		
		if isInAir then isSafe = false end 
		
		if isSafe then 
			return;
		end
	end
	
	-- ditched outside safe harbour
	if limitedAirframes.announcer then 
		trigger.action.outTextForCoalition(mySide, "Pilot " .. theUnit:getPlayerName() .. " DITCHED unit " .. theUnit:getName() .. " -- PILOT is considered MIA", 30)
	end 
	
	limitedAirframes.pilotLost(theUnit)
	if csarManager and csarManager.airframeDitched then 
		csarManager.airframeDitched(theUnit)
	end
	
	limitedAirframes.updatePlayerInUnit(theUnit, "MIA") -- cosmetic only
	limitedAirframes.createCSAR(theUnit, true) -- will never be 31 event, must force now 
end



function limitedAirframes.pilotEjected(event)
	local theUnit = event.initiator
	-- do we want to check location?
	-- no. if the user ejects, plane is done for
	local theSide = theUnit:getCoalition()
	local pilot = limitedAirframes.getKnownUnitPilotByUnit(theUnit)
	local uName = theUnit:getName()
	if limitedAirframes.announcer then 
		trigger.action.outTextForCoalition(theSide, "Pilot <" .. pilot .. "> ejected from " .. uName .. ", now MIA", 30)
	end 
	
	local hasLostTheWar = limitedAirframes.pilotLost(theUnit)
	
	limitedAirframes.updatePlayerInUnit(theUnit, "MIA") -- cosmetic only
	-- create CSAR if applicable
	if not hasLostTheWar then 
		limitedAirframes.createCSAR(theUnit) -- not forced, autoCSAR can hande
	end 
end

function limitedAirframes.pilotDied(theUnit)
	local theSide = theUnit:getCoalition()
	local pilot = limitedAirframes.getKnownUnitPilotByUnit(theUnit)
	local uName = theUnit:getName()
	if limitedAirframes.announcer then 
		trigger.action.outTextForCoalition(theSide, "Pilot <" .. pilot .. "> is confirmed KIA while controlling " .. uName, 30)
	end 
	limitedAirframes.pilotLost(theUnit)
end

function limitedAirframes.pilotLost(theUnit)
	-- returns true if lost the war 
	-- MUST NOT MESSAGE PILOT STATUS AS MIA CAN ALSO BE SET
	-- first DELETE THE UNIT FROM player-owned unit table
	-- so an empty crash after eject/death will not be counted as two losses
	limitedAirframes.killPlayerInUnit(theUnit)

	-- now see if we are enabled to limit airframes 
	if not limitedAirframes.enabled then return false end 
	
	-- find out which side lost the airframe and message side
	local theSide = theUnit:getCoalition()
	local pilot = limitedAirframes.getKnownUnitPilotByUnit(theUnit)
	local uName = theUnit:getName()

	
	if theSide == 1 then -- red 
		theOtherSide = 2 
		if 	limitedAirframes.maxRed < 0 then return false end -- disabled/infinite
		
		limitedAirframes.currRed = limitedAirframes.currRed - 1
		-- pass it along
		cfxZones.setFlagValueMult(limitedAirframes.numRed, limitedAirframes.currRed, limitedAirframes.config)
		
		if limitedAirframes.currRed == 0 then
			trigger.action.outTextForCoalition(theSide, "\nYou have lost almost all of your pilots.\n\nWARNING: Losing any more pilots WILL FAIL THE MISSION\n", 30)
			trigger.action.outSoundForCoalition(theSide, limitedAirframes.warningSound)
			return false  
		end
		
		if limitedAirframes.currRed < 0 then 
			-- red have lost all airframes 
			trigger.action.outText("\nREDFORCE has lost all of their pilots.\n\nBLUEFORCE WINS!\n", 30)
			trigger.action.outSoundForCoalition(theSide, limitedAirframes.loseSound) 
			trigger.action.outSoundForCoalition(theOtherSide, limitedAirframes.winSound)

			cfxZones.pollFlag(limitedAirframes.blueWinsFlag, limitedAirframes.method, limitedAirframes.config)
			return true 
		end
		
		
	elseif theSide == 2 then -- blue 
		theOtherSide = 1
		if 	limitedAirframes.maxBlue < 0 then return false end -- disabled/infinite
		limitedAirframes.currBlue = limitedAirframes.currBlue - 1
		-- pass it along
		cfxZones.setFlagValueMult(limitedAirframes.numBlue, limitedAirframes.currBlue, limitedAirframes.config)
		
		if limitedAirframes.currBlue == 0 then
			trigger.action.outTextForCoalition(theSide, "\nYou have lost almost all of your pilots.\n\nWARNING: Losing any more pilots WILL FAIL THE MISSION\n", 30)
			trigger.action.outSoundForCoalition(theSide, limitedAirframes.warningSound)
			return false 
		end
		if limitedAirframes.currBlue < 0 then 
			-- red have lost all airframes 
			trigger.action.outText("\nBLUEFORCE has lost all of their pilots.\n\nREDFORCE WINS!\n", 30)

			cfxZones.pollFlag(limitedAirframes.redWinsFlag, limitedAirframes.method, limitedAirframes.config) 
			trigger.action.outSoundForCoalition(theSide, limitedAirframes.loseSound)
			trigger.action.outSoundForCoalition(theOtherSide, limitedAirframes.winSound)
			return true 
		end
		trigger.action.outSoundForCoalition(theSide, limitedAirframes.warningSound)
			trigger.action.outTextForCoalition(theSide, "You have lost a pilot! Remaining: " .. limitedAirframes.currBlue, 30)
	end
	return false 
end

function limitedAirframes.checkPlayerFrameAvailability(event)
	local theUnit = event.initiator
	local theSide = theUnit:getCoalition()
	if theSide == 1 then -- red 
		if 	limitedAirframes.maxRed < 0 then return end -- disabled/infinite
		if limitedAirframes.currRed < 0 then 
			-- red have lost all airframes 
			trigger.action.outText("\nREDFORCE is a CHEATER!\n", 30)
			return 
		end
	elseif theSide == 2 then -- blue 
		if 	limitedAirframes.maxBlue < 0 then return end -- disabled/infinite
		if limitedAirframes.currBlue < 0 then 
			-- red have lost all airframes 
			trigger.action.outText("\nBLUEFORCE is a CHEATER!\n", 30)
			return 
		end
	end
end


function limitedAirframes.createCSAR(theUnit, forced)
	if not forced then forced = false end 
	
	-- override if autoCSAR is installed
	-- and let autoCSAR handle creation of CSAR when pilot's 
	-- seat hits ground, event 31
	if (not forced) and autoCSAR then
		-- csar is going to be created with parachute hitting the ground
		if limitedAirframes.verbose then 
			trigger.action.outText("+++limA: aborting CSAR creation: autoCSAR active", 30)
		end
		return 
	end 
	
	-- only do this if we have installed CSAR Manager
	if csarManager and csarManager.createCSARforUnit then 
		csarManager.createCSARforUnit(theUnit, 
			limitedAirframes.getKnownUnitPilotByUnit(theUnit),
			100)
	end
end

-- start up

function limitedAirframes.addSafeZone(aZone)
	if not aZone then 
		trigger.action.outText("WARNING: NIL Zone in addSafeZone", 30)
		return 
	end
	
	-- add zone to my list
	limitedAirframes.safeZones[aZone] = aZone 

	-- deprecated old code. new code contains 'red, blue' in value for pilotsafe 
	local safeSides = aZone:getStringFromZoneProperty("pilotsafe", "")
	safeSides = safeSides:lower()
	if dcsCommon.containsString(safeSides, "red") or dcsCommon.containsString(safeSides, "blue") then 
		aZone.redSafe = dcsCommon.containsString(safeSides, "red")
		aZone.blueSafe = dcsCommon.containsString(safeSides, "blue")
	else 
		aZone.redSafe = aZone:getBoolFromZoneProperty("redSafe", true)
		aZone.blueSafe = aZone:getBoolFromZoneProperty("blueSafe", true)
	end 
	
	if limitedAirframes.verbose or aZone.verbose then 
		if aZone.redSafe then 
			trigger.action.outText("+++limA: <" .. aZone.name .. "> is safe for RED pilots", 30)
		end 
		if aZone.blueSafe then 
			trigger.action.outText("+++limA: <" .. aZone.name .. "> is safe for BLUE pilots", 30)
		end
		trigger.action.outText("+++limA: added safeZone " .. aZone.name, 30)
	end	
end

--
-- COMMAND & CONFIGURATION
--
function limitedAirframes.setCommsMenu()
	local desc = "Pilot Count (Currently ON)"
	local desc2 = "Turn OFF Pilot Count (Cheat)?"
	if not limitedAirframes.enabled then 
		desc = "Pilot Count (Currently OFF)"
		desc2 = "ENABLE Pilot Count"
	end
	if not limitedAirframes.userCanToggle then desc = "Pilot Count" end 
	-- remove previous version
	if limitedAirframes.rootMenu then 
		missionCommands.removeItem(limitedAirframes.theScore) -- frames left
		if limitedAirframes.userCanToggle then 
			missionCommands.removeItem(limitedAirframes.theCommand) -- toggle on/off
		end
		missionCommands.removeItem(limitedAirframes.rootMenu)
	end
	limitedAirframes.theCommand = nil
	limitedAirframes.rootMenu = nil 
	
	-- add current version menu and command
	limitedAirframes.rootMenu = missionCommands.addSubMenu(desc, nil)
	
	limitedAirframes.theScore = missionCommands.addCommand("How many airframes left?" , limitedAirframes.rootMenu, limitedAirframes.redirectAirframeScore, {"none"})
	
	if limitedAirframes.userCanToggle then 
		limitedAirframes.theCommand = missionCommands.addCommand(desc2 , limitedAirframes.rootMenu, limitedAirframes.redirectToggleAirFrames, {"none"})
	end 
	
end

function limitedAirframes.redirectAirframeScore(args)
	timer.scheduleFunction(limitedAirframes.doAirframeScore, args, timer.getTime() + 0.1)
end

function limitedAirframes.doAirframeScore(args)
	local redRemaining = "unlimited"
	if limitedAirframes.maxRed >= 0 then 
		redRemaining = limitedAirframes.currRed .. " of " .. limitedAirframes.maxRed
		if limitedAirframes.currRed < 1 then 
			redRemaining = "no"
		end
	end
	
	local blueRemaining = "unlimited"
	if limitedAirframes.maxBlue >= 0 then 
		blueRemaining = limitedAirframes.currBlue .. " of " .. limitedAirframes.maxBlue
		if limitedAirframes.currBlue < 1 then 
			blueRemaining = "no"
		end
	end
	
	local msg = "\nRED has " .. redRemaining .. " pilots left,\nBLUE has " .. blueRemaining .. " pilots left\n"
	trigger.action.outText(msg, 30, true)
	trigger.action.outSound(limitedAirframes.warningSound)--"Quest Snare 3.wav")
end

function limitedAirframes.redirectToggleAirFrames(args)
	timer.scheduleFunction(limitedAirframes.doToggleAirFrames, args, timer.getTime() + 0.1)
end

function limitedAirframes.doToggleAirFrames(args)
	limitedAirframes.enabled = not limitedAirframes.enabled
	limitedAirframes.setCommsMenu()
	local desc = "\n\nPilot Count rule NOW IN EFFECT\n\n"
	
	if limitedAirframes.enabled then 
		trigger.action.outSound(limitedAirframes.warningSound)--"Quest Snare 3.wav")
	else
		desc = "\n\nYou cowardly disabled Pilot Count\n\n"
		trigger.action.outSound(limitedAirframes.loseSound)--"Death PIANO.wav")
	end
	trigger.action.outText(desc, 30)
	limitedAirframes.setCommsMenu()
end

--
-- CSAR CALLBACK (called by CSAR Manager)
--

function limitedAirframes.pilotsRescued(theCoalition, success, numRescued, notes)
	local availablePilots = 0
	if theCoalition == 1 then -- red 
		limitedAirframes.currRed = limitedAirframes.currRed + numRescued
		-- pass it along
		cfxZones.setFlagValueMult(limitedAirframes.numRed, limitedAirframes.currRed, limitedAirframes.config)
		
		if limitedAirframes.currRed > limitedAirframes.maxRed then 
			limitedAirframes.currRed = limitedAirframes.maxRed 
		end
		availablePilots = limitedAirframes.currRed
		if limitedAirframes.maxRed < 0 then 
			availablePilots = "unlimited"
		end 
	end
	
	if theCoalition == 2 then -- blue 
		limitedAirframes.currBlue = limitedAirframes.currBlue + numRescued
		-- pass it along
		cfxZones.setFlagValueMult(limitedAirframes.numBlue, limitedAirframes.currBlue, limitedAirframes.config)
		
		
		if limitedAirframes.currBlue > limitedAirframes.maxBlue then 
			limitedAirframes.currBlue = limitedAirframes.maxBlue 
		end
		availablePilots = limitedAirframes.currBlue
		if limitedAirframes.maxBlue < 0 then 
			availablePilots = "unlimited"
		end 
	end
	trigger.action.outTextForCoalition(theCoalition, "\nPilots returned to flight line, you now have " .. availablePilots..".\n", 30)
	trigger.action.outSoundForCoalition(theCoalition, limitedAirframes.warningSound)--"Quest Snare 3.wav")
end

--
-- Load / Save
--
function limitedAirframes.saveData()
	local theData = {}
	theData.currRed = limitedAirframes.currRed
	theData.currBlue = limitedAirframes.currBlue
	return theData
end

function limitedAirframes.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("limitedAirframes")
	if not theData then 
		if limitedAirframes.verbose then 
			trigger.action.outText("+++limA: no save date received, skipping.", 30)
		end
		return
	end

	if theData.currRed then 
		limitedAirframes.currRed = theData.currRed
	end

	if theData.currBlue then 
		limitedAirframes.currBlue = theData.currBlue
	end
	
end


--
-- START 
--

function limitedAirframes.start()
	if not dcsCommon.libCheck("cfx Limited Airframes", 
		limitedAirframes.requiredLibs) then
		return false 
	end
	
	-- override config settings if defined as zone
	limitedAirframes.readConfigZone()
	
	-- set output flags 
--	cfxZones.setFlagValue(limitedAirframes.numBlue, limitedAirframes.currBlue, limitedAirframes.config)
--	cfxZones.setFlagValue(limitedAirframes.numRed, limitedAirframes.currRed, limitedAirframes.config)
	
	-- collect all zones that are airframe safe 
	local afsZones = cfxZones.zonesWithProperty("pilotSafe")
	
	-- now add all zones to my zones table, and init additional info
	-- from properties
	for k, aZone in pairs(afsZones) do
		limitedAirframes.addSafeZone(aZone)
	end
	
	-- check that sides with limited airframes also have at least one 
	-- pilotsafe zone 
	if limitedAirframes.maxRed > 0 then 
		local safeAndSound = false 
		for idx, theZone in pairs(limitedAirframes.safeZones) do 
			if theZone.redSafe then safeAndSound = true end 
		end
		if not safeAndSound then 
			trigger.action.outText("+++limA: WARNING - RED has no safe zone to change air frames", 30)
		end
	end
	if limitedAirframes.maxBlue > 0 then 
		local safeAndSound = false 
		for idx, theZone in pairs(limitedAirframes.safeZones) do 
			if theZone.blueSafe then safeAndSound = true end 
		end
		if not safeAndSound then 
			trigger.action.outText("+++limA: WARNING - BLUE has no safe zone to change air frames", 30)
		end
	end
	
	-- connect player callback 
	-- install callbacks for airframe-related events
	dcsCommon.addEventHandler(limitedAirframes.somethingHappened, limitedAirframes.preProcessor, limitedAirframes.postProcessor)
	
	
	-- set current values
--	limitedAirframes.currRed = limitedAirframes.maxRed
--	limitedAirframes.currBlue = limitedAirframes.maxBlue
	
	-- collect active player unit names 
	local allPlayerUnits = dcsCommon.getAllExistingPlayerUnitsRaw()
	for i=1, #allPlayerUnits do 
		local aUnit = allPlayerUnits[i]
		limitedAirframes.addPlayerUnit(aUnit)
	end
	
	
	-- allow configuration menu 
	--if limitedAirframes.userCanToggle then 	
	if limitedAirframes.hasUI then 	
		limitedAirframes.setCommsMenu()
	end
	
	-- connect to csarManager if present 
	if csarManager and csarManager.installCallback then 
		csarManager.installCallback(limitedAirframes.pilotsRescued)
		trigger.action.outText("+++limA: connected to csar manager", 30)
	else 
		trigger.action.outText("+++limA: NO CSAR integration", 30)
	end

	-- persistence: load states 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = limitedAirframes.saveData
		persistence.registerModule("limitedAirframes", callbacks)
		-- now load my data 
		limitedAirframes.loadData()
	end
	
	-- say hi
	trigger.action.outText("cf/x Limited Airframes v" .. limitedAirframes.version .. " started: R:".. limitedAirframes.maxRed .. "/B:" .. limitedAirframes.maxBlue, 30)
	return true 
end

if not limitedAirframes.start() then 
	limitedAirframes = nil
	trigger.action.outText("cf/x Limited Airframes aborted: missing libraries", 30)
end



--[[--
   safe ditch: check airspeed and altitude. ditch only counts if less than 10m and 2 kts 
   report number of airframes left via second instance in switch off menu
   so it can report only one side 
--]]--