limitedAirframes = {}
limitedAirframes.version = "1.3.0"
limitedAirframes.enabled = true -- can be turned off
limitedAirframes.userCanToggle = true -- F-10 menu?
limitedAirframes.maxRed = -1 -- -1 == infinite
limitedAirframes.maxBlue = 6 -- -1 = infinite
limitedAirframes.redWinsFlag = "999"
limitedAirframes.blueWinsFlag = "998" 
 
limitedAirframes.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	             -- pretty stupid to check for this since we 
				 -- need common to invoke the check, but anyway
	"cfxZones", -- Zones, of course for safe landings
	"cfxPlayer", -- callbacks 
--	"cfxGroundTroops", -- generic data module for weight 
}

--[[-- VERSION HISTORY
 - 1.0.0 - initial version 
 - 1.0.1 - out text to coalition for switch
         - less verbose
		 - win/lose sound by coalition
 - 1.0.2 - corrected some to to-->for Groups typos
 - 1.0.3 - renamed to 'pilot' instead of airframe:
           pilotSafe attribute 
		 - fixed MP bug, switched to EventMonII code
 - 1.0.4 - added CSAR integration: create CSAR and callback
         - safe ditch only at less than 7 kmh and 10m agl 
 - 1.0.5 - replaced 5 (crash) check for helos only 
 - 1.0.6 - changed alt and speed tests to inAir
           reduced verbosity 
		   made reporting of new units for coalition side only 
 - 1.0.7 - if unlimited pilots it says so when you return one 
           to base
 - 1.0.8 - now can query remaining pilots 
 - 1.0.9 - better formatted remaining pilots 
 - 1.1.0 - module manager 
         - separated out settings 
		 - hand change in pilotsafe zones that can be landed in 
 - 1.2.0 - limitedAirframesConfig zone 
 - 1.3.0 - added network dead override logic via unitFlownByPlayer
 
--]]--

-- limitedAirframes manages the number of available player airframes
-- per scenario and side. Each time a player crashes the plane
-- outside of safe zones, the number is decreased for that side
-- when the number reaches -1 or smaller, other side wins
-- !!!Only affects player planes!!

-- *** EXTENDS ZONES ***
-- safe zones must have a property "pilotSafe"
--   - pilotSafe - this is a zone to safely change airframes in
--   - redSafe (optional, defaults to true)
--   - blueSafe (optional, defaults to true)
--     set to "false" or "no" to disallow that side to change 
--	   airframes even when safer
--   if zone can change ownership, player's coalition 
--   is checked against current zone ownership 
--   zone owner. 

-- when red wins due to blue frame loss, flag 999 is set to true
-- when blue wins due to red frame loss, flag 998 is set to true
-- set a mission trigger to end mission if you want to end mission
-- or simply keep running, and a CHEATER! message will flash 
-- every time the losing side enters a new aircraft 

limitedAirframes.safeZones = {} -- safezones are zones where a crash or change plane does not
-- these zones are created by adding an 'pilotSafe' attribute

limitedAirframes.myEvents = {5, 9, 30, 6, 20, 21, 15 } -- 5 = crash, 9 - dead, 30 - unit lost, 6 - eject, 20 - enter unit, 21 - leave unit, 15 - birth

-- guarantee a min of 2 seconds between events
-- for this we save last event per player 
limitedAirframes.lastEvents = {}
-- each time a plane crashes or is abandoned check 
-- that it's a player unit 
-- inside a crash free zone 
-- update the side's airframe credit 

limitedAirframes.currRed = 0
limitedAirframes.currRed = 0

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
		trigger.action.outText("***LimA: NO config zone!", 30) 
		return 
	end 
	
	trigger.action.outText("LimA: found config zone!", 30) 
	
	-- ok, for each property, load it if it exists
	if cfxZones.hasProperty(theZone, "enabled")  then 
		limitedAirframes.enabled = cfxZones.getBoolFromZoneProperty(theZone, "enabled", true)
	end
	
	if cfxZones.hasProperty(theZone, "userCanToggle")  then 
		limitedAirframes.userCanToggle = cfxZones.getBoolFromZoneProperty(theZone, "userCanToggle", true)
	end
	
	
	if cfxZones.hasProperty(theZone, "maxRed")  then 
		limitedAirframes.maxRed = cfxZones.getNumberFromZoneProperty(theZone, "maxRed", -1)
	end
	
	if cfxZones.hasProperty(theZone, "maxBlue")  then 
		limitedAirframes.maxBlue = cfxZones.getNumberFromZoneProperty(theZone, "maxBlue", -1)
	end
	
	
	if cfxZones.hasProperty(theZone, "redWinsFlag")  then 
		limitedAirframes.redWinsFlag = cfxZones.getStringFromZoneProperty(theZone, "redWinsFlag", "999")
	end
	
	if cfxZones.hasProperty(theZone, "blueWinsFlag")  then 
		limitedAirframes.blueWinsFlag = cfxZones.getStringFromZoneProperty(theZone, "blueWinsFlag", "998")
	end
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
	local uName = theUnit:getName()
	if not uName then uName = "**XXXX**" end 
	local pName = theUnit:getPlayerName()
	if not pName then pName = "**????**" end 
	limitedAirframes.updatePlayer(pName, "alive")
	
	local desc = "unit <" .. uName .. "> controlled by <" .. pName .. ">"
	if not(limitedAirframes.isKnownUnitName(uName)) then 
		--desc = "+++lim: added ".. desc .. " to list of known player units"
	else 
		if limitedAirframes.playerUnits[uName] == pName then 
			desc = "player unit <".. uName .. "> controlled by <".. limitedAirframes.playerUnits[uName].."> re-seated"
		else 
			desc = "Updated player unit <".. uName .. "> from <".. limitedAirframes.playerUnits[uName].."> to <" .. pName ..">"
		end 
	end 
	limitedAirframes.playerUnits[uName] = pName 
	trigger.action.outTextForCoalition(theSide, desc, 30)
end

function limitedAirframes.killPlayer(pName)
	limitedAirframes.updatePlayer(pName, "dead")
	--trigger.action.outText("+++lim: PILOT LOST: " .. pName .. ", NO CSAR", 30)
end

function limitedAirframes.killPlayerInUnit(theUnit)
	limitedAirframes.updatePlayerInUnit(theUnit, "dead")
	--trigger.action.outText("+++lim: PILOT LOST, NO CSAR", 30)
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
		trigger.action.outText("+++lim: WARNING - NIL pName in updatePlayer for status " .. status, 30)
		return
	end 
	local desc = ""
	if not limitedAirframes.players[pName] then 
		desc = "+++lim: NEW player " .. pName .. ": " .. status
	else 
		if limitedAirframes.players[pName] ~= status then 
			desc = "+++lim: CHANGE player " .. pName .. " " .. limitedAirframes.players[pName] .. " -> " .. status
		else 
			desc = "+++: player " .. pName .. " no change (" .. status .. ")"
		end
	end
	
	limitedAirframes.players[pName] = status 
	-- if desc then trigger.action.outText(desc, 30) end 
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
function limitedAirframes.XXXisKnownPlayerUnit(theUnit) 
	if not theUnit then return false end 
	local aName = theUnit:getName()
	if limitedAirframes.playerUnitNames[aName] ~= nil then 
		return true
	end
	return false 
end

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
	local uName = theUnit:getName()
	

	if event.id == 6 then -- Eject, plane already divorced from player
		if limitedAirframes.isKnownUnitName(uName) then 
			--trigger.action.outText("limAir: detected EJECT for player unit " .. uName .. " player " .. limitedAirframes.getKnownUnitPilotByUnitName(uName), 30)
			return true
		end
		return false -- no longer of interest 
	end
	
	if event.id == 5 then -- crash, plane no longer attached to player
		
		if limitedAirframes.isKnownUnitName(uName) then
			--trigger.action.outText("limAir: detected CRASH for player unit " .. uName .. " player " .. limitedAirframes.getKnownUnitPilotByUnitName(uName), 30)
			return true
		end
		return false -- no longer of interest 
	end
	
	
	if not cfxPlayer.isPlayerUnit(theUnit) then 
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
	local unitName = theUnit:getName()
	local ID = event.id
	local myType = theUnit:getTypeName()
	
	-- "20" event (player enter): always processed 
--[[--	if ID == 20 or ID == 15 then -- player entered unit
		limitedAirframes.addPlayerUnit(theUnit) -- will also update player and player status to 'alive'
		-- now procc a 'cheater' since we entered a new airframe/pilot
		limitedAirframes.checkPlayerFrameAvailability(event)
		return 
	end
--]]--
	
	if ID == 20 then -- 20 ENTER UNIT
		local pName = limitedAirframes.getKnownUnitPilotByUnit(theUnit)
		if not pName then pName = "***UNKNOWN***" end 
		--trigger.action.outText("limAir: Received ENTER UNIT (20) for " .. pName .. " in " .. unitName , 30)
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
		trigger.action.outText("limAir: 15 -- player " .. playerName .. " now in " .. unitName, 30)
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
			trigger.action.outText("limAir: Crash of airframe detected - but player status wasn't alive (" .. pStatus .. ")", 30)
			return 
		end 
	end 

-- removed dual 21 detection here 
	
	if ID == 21 then 
		-- remove pilot name from unit name 
		limitedAirframes.unitFlownByPlayer[unitName] = nil
		--trigger.action.outText("limAir: 21 -- unit " .. unitName .. " unoccupied", 30)
		
		trigger.action.outText("limAir: 21 (player left) for unit " .. unitName , 30)
		-- player left unit. Happens twice
		-- check if player alive, else we have a ditch.
		limitedAirframes.handlePlayerLeftUnit(event)
		return 
	end
	
	
	if ID == 9 then -- died 
		--trigger.action.outText("limAir: 9 (PILOT DEAD) for unit " .. unitName , 30)
		local thePilot = limitedAirframes.unitFlownByPlayer[unitName]
		if not thePilot then 
			trigger.action.outText("+++limAir: 9 O'RIDE -- unit " .. unitName .. " was legally vacated before!", 30)
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
		--trigger.action.outText("limAir: Change Plane for player <" .. pName .. "> with status <" .. pStatus .. "> procced.", 30)
		return 
	end
	
	-- check if the unit was inside a safe zone
	-- if so, graceful exit 
	local uPos = theUnit:getPoint() 
	local meInside = cfxZones.getZonesContainingPoint(uPos, limitedAirframes.safeZones)
	local mySide = theUnit:getCoalition()
	--local speed = dcsCommon.getUnitSpeed(theUnit) -- this can cause problems with carriers, so check if below 
	--local agl = dcsCommon.getUnitAGL(theUnit) -- this will cause problems with FARP and carriers. 
	-- we now check the inAir 
	local isInAir = theUnit:inAir()
	--trigger.action.outTextForCoalition(mySide, "limAir: safe check for Pilot " .. theUnit:getPlayerName() .. ": agl=" .. agl .. ", speed = " .. speed .. ", air status = " .. dcsCommon.bool2YesNo(isInAir), 30)

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
			trigger.action.outText("+++: Lim - " .. theSafeZone.name .. " ownership: myside = " .. mySide .. " zone owner is " .. theSafeZone.owner, 30)
		else 
			-- trigger.action.outText("+++: Zone " .. theSafeZone.name .. " has no ownership, skipping check", 30)
		end
		
		-- check we are at rest below 10m height. agl may give 
		-- misreadings on carriers and FARPs, while speed may read
		-- wrongly on carriers (tbd). we now use isInAir to determine if
		-- we ditched while in flight 
		--if speed > 2 or agl > 10 then isSafe = false end 
		--if not isInAir then return false end -- why *not* isInAir??? 
		
		-- for matter of fact, why did we return ANYTHING???
		-- there may be a bug here 
		-- maybe it should be "if isInAir then isSafe = false"??
		if isInAir then isSafe = false end 
		
		if isSafe then 
			trigger.action.outTextForCoalition(mySide, "limAir: Pilot " .. theUnit:getPlayerName() .. " left unit " .. theUnit:getName() .. " legally in zone " .. theSafeZone.name, 30)
			-- remove from known player planes
			-- no more limitedAirframes.removePlayerUnit(theUnit)
			return;
		end
	end
	
	-- ditched outside safe harbour
	trigger.action.outTextForCoalition(mySide, "Pilot " .. theUnit:getPlayerName() .. " DITCHED unit " .. theUnit:getName() .. " -- PILOT LOSS (MIA)", 30)
	limitedAirframes.pilotLost(theUnit)
	if csarManager and csarManager.airframeDitched then 
		csarManager.airframeDitched(theUnit)
	end
	
	limitedAirframes.updatePlayerInUnit(theUnit, "MIA") -- cosmetic only
	limitedAirframes.createCSAR(theUnit)
end



function limitedAirframes.pilotEjected(event)
	local theUnit = event.initiator
	-- do we want to check location?
	-- no. if the user ejects, plane is done for
	local theSide = theUnit:getCoalition()
	local pilot = limitedAirframes.getKnownUnitPilotByUnit(theUnit)
	local uName = theUnit:getName()
	trigger.action.outTextForCoalition(theSide, "Pilot <" .. pilot .. "> ejected from " .. uName .. ", now MIA", 30)
	
	local hasLostTheWar = limitedAirframes.pilotLost(theUnit)
	
	limitedAirframes.updatePlayerInUnit(theUnit, "MIA") -- cosmetic only
	-- create CSAR if applicable
	if not hasLostTheWar then 
		limitedAirframes.createCSAR(theUnit)
	end 
end

function limitedAirframes.pilotDied(theUnit)
	--limitedAirframes.killPlayerInUnit(theUnit)
	local theSide = theUnit:getCoalition()
	local pilot = limitedAirframes.getKnownUnitPilotByUnit(theUnit)
	local uName = theUnit:getName()
	trigger.action.outTextForCoalition(theSide, "Pilot <" .. pilot .. "> is confirmed KIA while controlling " .. uName, 30)
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
	--trigger.action.outTextForCoalition(theSide, "Pilot <" .. pilot .. "> is confirmed KIA while controlling " .. uName, 30)
	
	if theSide == 1 then -- red 
		theOtherSide = 2 
		if 	limitedAirframes.maxRed < 0 then return false end -- disabled/infinite
		
		limitedAirframes.currRed = limitedAirframes.currRed - 1
		
		if limitedAirframes.currRed == 0 then
			trigger.action.outTextForCoalition(theSide, "\nYou have lost almost all of your pilots.\n\nWARNING: Losing any more pilots WILL FAIL THE MISSION\n", 30)
			trigger.action.outSoundForCoalition(theSide, "Quest Snare 3.wav")
			return false  
		end
		
		if limitedAirframes.currRed < 0 then 
			-- red have lost all airframes 
			trigger.action.outText("\nREDFORCE has lost all of their pilots.\n\nBLUEFORCE WINS!\n", 30)
			trigger.action.outSoundForCoalition(theSide, "Death PIANO.wav")
			trigger.action.outSoundForCoalition(theOtherSide, "Triumphant Victory.wav")
			trigger.action.setUserFlag(limitedAirframes.blueWinsFlag, 1 )
			return true 
		end
		
		
	elseif theSide == 2 then -- blue 
		theOtherSide = 1
		if 	limitedAirframes.maxBlue < 0 then return false end -- disabled/infinite
		limitedAirframes.currBlue = limitedAirframes.currBlue - 1
		if limitedAirframes.currBlue == 0 then
			trigger.action.outTextForCoalition(theSide, "\nYou have lost almost all of your pilots.\n\nWARNING: Losing any more pilots WILL FAIL THE MISSION\n", 30)
			trigger.action.outSoundForCoalition(theSide, "Quest Snare 3.wav")
			return false 
		end
		if limitedAirframes.currBlue < 0 then 
			-- red have lost all airframes 
			trigger.action.outText("\nBLUEFORCE has lost all of their pilots.\n\nREDFORCE WINS!\n", 30)
			trigger.action.setUserFlag(limitedAirframes.redWinsFlag, 1 )
			trigger.action.outSoundForCoalition(theSide, "Death PIANO.wav")
			trigger.action.outSoundForCoalition(theOtherSide, "Triumphant Victory.wav")
			return true 
		end
		trigger.action.outSoundForCoalition(theSide, "Quest Snare 3.wav")
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


function limitedAirframes.createCSAR(theUnit)
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

	-- transfer properties if they exist 
	-- blueSafe, redSafe: what side this is safe for, default = yes 
	
	-- add zone to my list
	limitedAirframes.safeZones[aZone] = aZone 
	aZone.redSafe = true
	aZone.redSafe = cfxZones.getBoolFromZoneProperty(aZone, "redSafe", true)
	aZone.blueSafe = true 
	aZone.blueSafe = cfxZones.getBoolFromZoneProperty(aZone, "blueSafe", true)

	trigger.action.outText("limAir: added safeZone " .. aZone.name, 30)
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
	-- remove previous version
	if limitedAirframes.rootMenu then 
		missionCommands.removeItem(limitedAirframes.theScore)
		missionCommands.removeItem(limitedAirframes.theCommand)
		missionCommands.removeItem(limitedAirframes.rootMenu)
	end
	limitedAirframes.theCommand = nil
	limitedAirframes.rootMenu = nil 
	
	-- add current version menu and command
	limitedAirframes.rootMenu = missionCommands.addSubMenu(desc, nil)
	
	limitedAirframes.theScore = missionCommands.addCommand("How many airframes left?" , limitedAirframes.rootMenu, limitedAirframes.redirectAirframeScore, {"none"})
	
	limitedAirframes.theCommand = missionCommands.addCommand(desc2 , limitedAirframes.rootMenu, limitedAirframes.redirectToggleAirFrames, {"none"})
	
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
	trigger.action.outSound("Quest Snare 3.wav")
end

function limitedAirframes.redirectToggleAirFrames(args)
	timer.scheduleFunction(limitedAirframes.doToggleAirFrames, args, timer.getTime() + 0.1)
end

function limitedAirframes.doToggleAirFrames(args)
	limitedAirframes.enabled = not limitedAirframes.enabled
	limitedAirframes.setCommsMenu()
	local desc = "\n\nPilot Count rule NOW IN EFFECT\n\n"
	
	if limitedAirframes.enabled then 
		trigger.action.outSound("Quest Snare 3.wav")
	else
		desc = "\n\nYou cowardly disabled Pilot Count\n\n"
		trigger.action.outSound("Death PIANO.wav")
	end
	trigger.action.outText(desc, 30)
	limitedAirframes.setCommsMenu()
end

--
-- CSAR CALLBACK
--

function limitedAirframes.pilotsRescued(theCoalition, success, numRescued, notes)
	local availablePilots = 0
	if theCoalition == 1 then -- red 
		limitedAirframes.currRed = limitedAirframes.currRed + numRescued
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
		if limitedAirframes.currBlue > limitedAirframes.maxBlue then 
			limitedAirframes.currBlue = limitedAirframes.maxBlue 
		end
		availablePilots = limitedAirframes.currBlue
		if limitedAirframes.maxBlue < 0 then 
			availablePilots = "unlimited"
		end 
	end
	trigger.action.outTextForCoalition(theCoalition, "\nPilots returned to flight line, you now have " .. availablePilots..".\n", 30)
	trigger.action.outSoundForCoalition(theCoalition, "Quest Snare 3.wav")
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
	
	-- collect all zones that are airframe safe 
	local afsZones = cfxZones.zonesWithProperty("pilotSafe")
	
	-- now add all zones to my zones table, and init additional info
	-- from properties
	for k, aZone in pairs(afsZones) do
		limitedAirframes.addSafeZone(aZone)
	end
	
	-- connect player callback 
	-- install callbacks for airframe-related events
	dcsCommon.addEventHandler(limitedAirframes.somethingHappened, limitedAirframes.preProcessor, limitedAirframes.postProcessor)
	
	
	-- set current values
	limitedAirframes.currRed = limitedAirframes.maxRed
	limitedAirframes.currBlue = limitedAirframes.maxBlue
	
	-- collect active player unit names 
	local allPlayerUnits = cfxPlayer.getAllExistingPlayerUnitsRaw()
	for i=1, #allPlayerUnits do 
		local aUnit = allPlayerUnits[i]
		limitedAirframes.addPlayerUnit(aUnit)
--		trigger.action.outText("limAir: detected active player unit " .. aUnit:getName(), 30)
	end
	
	
	-- allow configuration menu 
	if limitedAirframes.userCanToggle then 	
		limitedAirframes.setCommsMenu()
	end
	
	-- connect to csarManager if present 
	if csarManager and csarManager.installCallback then 
		csarManager.installCallback(limitedAirframes.pilotsRescued)
		trigger.action.outText("+++lim: connected to csar manager", 30)
	else 
		trigger.action.outText("+++lim: NO CSAR integration", 30)
	end
	
	-- say hi
	trigger.action.outText("limitedAirframes v" .. limitedAirframes.version .. " started: R:".. limitedAirframes.maxRed .. "/B:" .. limitedAirframes.maxBlue, 30)
	return true 
end

if not limitedAirframes.start() then 
	limitedAirframes = nil
	trigger.action.outText("cf/x Limited Airframes aborted: missing libraries", 30)
end



--[[--
   safe ditch: check airspeed and altitude. ditch only counts if less than 10m and 2 kts 
   report number of airframes left via second instance in switch off menu
--]]--