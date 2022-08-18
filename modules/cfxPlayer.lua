-- cfx player handler for DCS Missions by cf/x AG
-- 
-- a module that provides easy access to a mission's player data
-- multi-player only
--

cfxPlayer = {}
						   -- a call to cfxPlayer.start()
cfxPlayer.version = "3.0.1"
--[[-- VERSION HISTORY

- 2.2.3 - fixed isPlayerUnit() wrong return of true instead of nil
- 2.2.4 - getFirstGroupPlayer
- 2.3.0 - added event filtering for monitors
        - limited code clean-up
		- removed XXXmatchUnitToPlayer
		- corrected isPlayerUnit once more
		- removed autostart option
		- removed detectPlayersLeaving option 
- 3.0.0 - added detection of network players 
        - added new events newPlayer, changePlayer 
		- and leavePlayer (never called)
- 3.0.1 - isPlayerUnit guard against scenery object or map object 
--]]--

cfxPlayer.verbose = false;
cfxPlayer.running = false 
cfxPlayer.ups = 1 -- updates per second: how often do we query the players 
				  -- a good value is 1
cfxPlayer.playerDB = {} -- the list of all player UNITS
		-- attributes
			-- name - name of unit occupied by player
			-- unit - unit this player is controlling
			-- unitName - same as name
			-- group - group this unit belongs to. can't change without also changing unit
			-- groupName - name of group
			-- coalition
cfxPlayerGroups = {} -- GLOBAL VAR 
-- list of all current groups that have players in them 
-- can call out to handlers if group is added or removed
-- use this in MP games to organise messaging and keep score
-- by default, groupinfo merely contains the .group reference 
-- and is accessed by name as key which is also accessible by .name
			
cfxPlayer.netPlayers = {} -- new for version 3: real player detection
-- a dict sorted by player name that containts the unit name for last pass 

cfxPlayer.updateSchedule = 0 -- ID used for scheduling update
cfxPlayer.coalitionSides = {0, 1, 2} -- we currently have neutral, red, blue

cfxPlayer.monitors = {} -- callbacks for events

---
-- structure of playerInfo
--   - name - player's unit name
--   - unit - the unit the player is occupying. Multi-Crew: many people can be in same unit
--   - unitName same as name 

--   - coalition - the side the unit is on, as a number 
function cfxPlayer.dumpRawPlayers()
	trigger.action.outText("+++ debug: raw player dump ---", 30)
	for i=1, #cfxPlayer.coalitionSides do 
		local theSide = cfxPlayer.coalitionSides[i] 
		-- get all players for this side
		local thePlayers = coalition.getPlayers(theSide) 
		for p=1, #thePlayers do 
			aPlayerUnit = thePlayers[p] -- docs say this is a unit table, not a person table!
			trigger.action.outText(i .. "-" .. p ..": unit: " .. aPlayerUnit:getName() .. " controlled by " .. aPlayerUnit:getPlayerName() , 30)
		end
	end
	trigger.action.outText("+++ debug: END DUMP ----", 30)
end


function cfxPlayer.getAllPlayers()
	return cfxPlayer.playerDB -- get entire db. make sure not to screw around with it
end


function cfxPlayer.getPlayerInfoByName(theUnitName) -- note: UNIT name
	thePlayer = cfxPlayer.playerDB[theUnitName] -- access the entry, not we are accessing by unit name
	return thePlayer
end

function cfxPlayer.getPlayerInfoByIndex(theIndex) 
	local enumeratedInfo = dcsCommon.enumerateTable(cfxPlayer.playerDB)
	if (theIndex > #enumeratedInfo) then
		trigger.action.outText("WARNING: player index " .. theIndex .. " out of bounds - max = " .. #enumeratedInfo, 30)
		return nil end
	if (theIndex < 1) then return nil end
	
	return enumeratedInfo[theIndex]
end

-- this is now a true/false function that returns true if unit is player 
function cfxPlayer.XXXmatchUnitToPlayer(theUnit) -- what's difference to getPlayerInfo? GetPlayerInfo ALLOCATES if not exists 

	if not (theUnit) then return false end
	if not (theUnit:isExist()) then return false end 
	
	-- PATCH: if theUnit:getPlayerName() returns anything but nil
	-- this is a player unit
    -- unfortunately, this can sometimes fail
	-- so make sure the function existst
	-- it failed because the next level up function 
	-- returned true if i returned anything but nil, and I return 
	-- true or false, both not nil 
	-- this proc works 
	if not theUnit.getPlayerName then return false end 
	
	local pName = theUnit:getPlayerName()
	if pName ~= nil then 
		-- trigger.action.outText("+++matchUnit: player name " .. pName .. " for unit " .. theUnit:getName(), 30)
		return true 
	end 
	
	if (true) then 
		return false
	end 
	
	-- ignmore old code below

	for pname, pInfo in pairs(cfxPlayer.playerDB) do 
		if (pInfo.unit == theUnit) then 
			return pInfo
		end
	end
	return nil
end

function cfxPlayer.XXXisPlayerUnitAlt(theUnit)
	for pname, pInfo in pairs(cfxPlayer.playerDB) do 
		if (pInfo.unit == theUnit) then 
			return true
		end
	end
	return false
end

function cfxPlayer.isPlayerUnit(theUnit)
	-- new patch. simply check if getPlayerName returns something
	if not theUnit then return false end 
	if not theUnit.getPlayerName then return false end -- map/static object 
	local pName = theUnit:getPlayerName()
	if pName then return true end 
	return false 
	--
	-- fixed, erroneously expected a nil from matchUnitToPlayer 
	--return (cfxPlayer.matchUnitToPlayer(theUnit)) -- was: ~=nil, wrong because match returns true/false
end



function cfxPlayer.getPlayerUnitType(thePlayerInfo) -- 
	if (thePlayerInfo) then 
		theUnit = thePlayerInfo.unit
		if (theUnit) and (theUnit:isExist()) then 
			return theUnit:getTypeName()
		end
	end
	return nil 
end


-- get player's unit info
-- accesses player DB and returns the player's info record for the
-- player's Unit. If record does not exist in db, a new record is allocated
-- returns true if verification succeeeds: player unit existed before, and
-- false otherwise. in the latter case, A NEW playerInfo object is returned
function cfxPlayer.getPlayerInfo(theUnit)
	local playerName = theUnit:getPlayerName() -- retrieve the name 
	--- PATCH!!!!!!!
	--- on multi-crew, we only have the pilot as getPlayerName. 
	--- we now switch to the unit's name instead 
	playerName = theUnit:getName() 
	
	-- trigger.action.outText("Player: ".. playerName, 10)

    local existingPlayer = cfxPlayer.getPlayerInfoByName(playerName) -- try and access DB
	if existingPlayer then
		-- this player exists in the db. return the record
		return true, existingPlayer;

	else
		-- this is a new player.
		-- set up a new playerinfo record for this name
		local newPlayerInfo = {}
		newPlayerInfo.name = playerName
		newPlayerInfo.unit = theUnit
		newPlayerInfo.unitName = theUnit:getName()
		newPlayerInfo.group = theUnit:getGroup()
		newPlayerInfo.groupName = newPlayerInfo.group:getName()
		newPlayerInfo.coalition = theUnit:getCoalition() -- seems to work when first param is class self
		-- note that this record did not exist, and return record
		return false, newPlayerInfo
	end
	
end;

function cfxPlayer.getSinglePlayerAirframe()
	-- ALWAYS return a string! This is for debugging purposes
	local thePlayers = {}
	local count = 0
	local theAirframe = "(none)"
	for pname, pinfo in pairs(cfxPlayer.playerDB) do 
		count = count + 1
		theAirframe = pinfo.unit:getTypeName()
	end
	if count < 2 then return theAirframe end -- also returns if count == 0
	return "<Multiplayer Not Yet Supported>"
end

function cfxPlayer.getAnyPlayerAirframe()
	-- use this for debugging, in single-player missions, or where it 
	-- is unimportant which player, just a player
	-- assumes that all players use the same airframe or are in the 
	-- same group / unit 
	for pname, pinfo in pairs(cfxPlayer.playerDB) do 
		if (pinfo.unit:isExist()) then 
			-- player may just have crashed or left
			local theAirframe = pinfo.unit:getTypeName()
			return theAirframe -- we simply stop after first successfuly access
		end
	end
	return "error: no player"
end

function cfxPlayer.getFirstGroupPlayerName(theGroup)
 -- get the name of player of the first 
 -- player-controlled unit I come across in 
 -- this group 
	local allGroupUnits = theGroup:getUnits()
	for ukey, uvalue in pairs(allGroupUnits) do 
		-- iterate units in group
		if (uvalue:isExist())  then -- and cfxPlayer.isPlayerUnit(uvalue)) 
			-- player may just have crashed or left
			-- but all units in the same group have the same type when they are aircraft
			if cfxPlayer.isPlayerUnit(uvalue) then 
				return uvalue:getPlayerName(), uvalue 
			end
		end
	end
	return nil 
end

function cfxPlayer.getAnyGroupPlayerAirframe(theGroup)
	-- get the first player-driven unit in the group
	-- and pass back the airframe that is being used 
	local allGroupUnits = theGroup:getUnits()
	for ukey, uvalue in pairs(allGroupUnits) do 
		
		if (uvalue:isExist())  then -- and cfxPlayer.isPlayerUnit(uvalue)) 
			-- player may just have crashed or left
			-- but all units in the same group have the same type when they are aircraft
			local theAirframe = uvalue:getTypeName()
			return theAirframe -- we simply stop after first successfuly access
		end
	end
	return "error: no live player in group "
end



function cfxPlayer.getAnyPlayerPosition()
	-- use this for debugging, in single-player missions, or where it 
	-- is unimportant which player, just a player
	-- will cause issues when you derive location info or group info 
	-- from that player
	for pname, pinfo in pairs(cfxPlayer.playerDB) do
		if (pinfo.unit:isExist()) then 
			local thePoint = pinfo.unit:getPoint()
			return thePoint -- we simply stop after first successfuly access
		end
	end
	return nil
end

function cfxPlayer.getAnyGroupPlayerPosition(theGroup)
	-- enter with dcs group to search for player units within
	-- step one: get all units that belong to that group
	local allGroupUnits = theGroup:getUnits()
	-- we now iterate all returned units and look for 
	-- a unit that is a player unit.
	for ukey, uvalue in pairs(allGroupUnits) do 
		-- we currently assume single-unit groups for players
		if (uvalue:isExist()) then -- and cfxPlayer.isPlayerUnit(uvalue))
			-- player may just have crashed or left
			local thePoint = uvalue:getPoint()
			return thePoint -- we simply stop after first successfuly access
		end
	
	end
	return nil
end

function cfxPlayer.getAnyGroupPlayerInfo(theGroup)
	for pname, pinfo in pairs(cfxPlayer.playerDB) do 
		if (pinfo.unit:isExist() and pinfo.group == theGroup) then 
			return pinfo -- we simply stop after first successfuly access
		end
	end
	return "error: no player"
end


function cfxPlayer.getAllPlayerGroups()
	-- merely accessot. better would be returning a copy 
	return cfxPlayerGroups	
end

function cfxPlayer.getGroupDataForGroupNamed(name)
	if not name then return nil end 
	return cfxPlayerGroups[name]
end

function cfxPlayer.getPlayersInGroup(theGroup)
	if not theGroup then return {} end
	if not theGroup:isExist() then return {} end 
	local gName = theGroup:getName()
	local thePlayers = {}
	
	for pname, pinfo in pairs(cfxPlayer.playerDB) do 		
		local pgName = ""
		if pinfo.group:isExist() then pgName = pinfo.group:getName() end 
		if (gName == pgName) then 
			table.insert(thePlayers, pinfo)
		end
	end
	return thePlayers
end

-- update() is called regularly to check up on the players
-- when a mismatch to last player state is found, callbacks 
-- can be invoked

function cfxPlayer.update()
	
	-- first, re-schedule my next invocation
	cfxPlayer.updateSchedule = timer.scheduleFunction(cfxPlayer.update, {}, timer.getTime() + 1/cfxPlayer.ups)
	
	-- now scan the coalitions for all players
	local currCount = 0 -- number of players found this pass
	local currDB = {} -- db of player units this pass
    local currPlayerUnitsByNames = {}	
	-- iterate over all colaitions 
	for i=1, #cfxPlayer.coalitionSides do 
		local theSide = cfxPlayer.coalitionSides[i] 
		-- get all player units for this side
		local thePlayers = coalition.getPlayers(theSide) -- returns UNITs!!!

		for p=1, #thePlayers do 
			-- we now iterate the Units and compare what we find
			local thePlayerUnit = thePlayers[p]
			local isExistingPlayerUnit, theInfo = cfxPlayer.getPlayerInfo(thePlayerUnit)
			
			if (not isExistingPlayerUnit) then 
				-- add Unit (not player!) to db
				cfxPlayer.playerDB [theInfo.name] = theInfo
				cfxPlayer.invokeMonitorsForEvent("new", "Player Unit " .. theInfo.name .. " entered mission", theInfo, {})

			else
				-- player's unit existed last time around
				-- see if something changed:
	
-- currently, we track units, not players. side changes for units can't happen AT ALL 
				
				if theInfo.coalition ~= thePlayerUnit:getCoalition() then	
					local theData = {}
					theData.old = theInfo.coalition
					theData.new = thePlayerUnit:getCoalition()

					-- we invoke a callback
					cfxPlayer.invokeMonitorsForEvent("side", "Player " .. theInfo.name .. " switched sides to " .. thePlayerUnit:getCoalition(), theInfo, theData)

				end;

-- we now check if the player has changed groups
-- sinced we track units, this CANT HAPPEN AT ALL 

				if theInfo.group ~= thePlayerUnit:getGroup() then 
					local theData = {}
					theData.old = theInfo.group
					theData.new = thePlayerUnit:getGroup()
					cfxPlayer.invokeMonitorsForEvent("group", "Player changed group to " .. thePlayerUnit:getGroup():getName(), theInfo, theData)
					trigger.action.outText("+++ debug: Player " .. theInfo.name .. " changed GROUP to: " .. thePlayerUnit:getGroup():getName(), 30)
				end

				-- we should now check if the player has changed units
-- since we track units, this cant happen at all
				if theInfo.unit ~= thePlayerUnit then
					-- player changed unit 
					local theData = {}
					theData.old = theInfo.unit
					-- the old unit's name is still available in theInfo.unitName 
					theData.oldUnitName = theInfo.unitName 
					theData.new = thePlayerUnit
					-- update Player Info
					cfxPlayer.invokeMonitorsForEvent("unit", "Player changed unit to " .. thePlayerUnit:getName(), theInfo, theData)
					
				end
				-- update the playerEntry. always done
				theInfo.unit = thePlayerUnit
				theInfo.unitName = thePlayerUnit:getName()
				theInfo.coalition = thePlayerUnit:getCoalition()
				theInfo.group = thePlayerUnit:getGroup()		
			end;
			
			-- add this entry to current pass db so we can detect
			-- any discrepancies to last pass
			currDB[theInfo.name] = theInfo 
			
			-- now update current network player name db
			local playerUnitName = thePlayerUnit:getName()
			if not thePlayerUnit:isExist() then playerUnitName = "<none>" end 
			currPlayerUnitsByNames[thePlayerUnit:getPlayerName()] = playerUnitName
		end -- for all player units of this side
	end -- for all sides
	
	-- we can now check if a player unit has disappeared	
	-- we do this by checking that all old entries from cfxPlayer.playerDB
	-- have an existing counterpart in new currDB
	for name, info in pairs(cfxPlayer.playerDB) do
		local matchingEntry = currDB[name]
		if matchingEntry then 
			-- allright nothing to do
		else
			-- whoa, this record is missing!
			-- do we care?
			if true then -- (cfxPlayer.detectPlayersLeaving) then
				-- yes! trigger an event
				cfxPlayer.invokeMonitorsForEvent("leave", "Player left mission", info, {})
				-- we don't need to destroy entry, as we simply replace the
				-- playerDB with currDB at end of update
			else 
				-- no, just copy old data over. They'll be back
				currDB[name] = info
			end
		end 
	end;
	
	-- we now perform a group check and update all groups for players 
	local currPlayerGroups = {}
	for pName, pInfo in pairs(currDB) do 
		-- retrieve player unit and make sure it still exists
		local theUnit = pInfo.unit
		if theUnit:isExist() then 
			-- yeah, it exists allright. let's get to the group
			local theGroup = theUnit:getGroup()
			local gName = theGroup:getName()
			-- see if this group is new
			local thePGroup = cfxPlayerGroups[gName]
			if not thePGroup then 
				-- allocate new group
				thePGroup = {}
				thePGroup.group = theGroup
				thePGroup.name = gName 
				thePGroup.primeUnit = theUnit -- may be used as fallback
				thePGroup.primeUnitName = theUnit:getName() -- also fallback only
				thePGroup.id = theGroup:getID()
				cfxPlayer.invokeMonitorsForEvent("newGroup", "New Player Group " .. gName .. " appeared", nil, thePGroup)
			end
			currPlayerGroups[gName] = thePGroup -- update group table
		end
	end

	-- now check if a player group has disappeared
	for gkey, gval in pairs(cfxPlayerGroups) do 
		if not currPlayerGroups[gkey] then 
			cfxPlayer.invokeMonitorsForEvent("removeGroup", "A Player Group " .. gkey .. " vanished", nil, gval) -- gval is OLD set, contains group 
		end
	end
	
	-- version 3 addion: track network players
	-- see if a new player has appeared 
	for aPlayerName, aPlayerUnitName in pairs(currPlayerUnitsByNames) do 
		-- see if this name was already in last 
		if cfxPlayer.netPlayers[aPlayerName] then 
			-- yes. but was it the same unit?
			if cfxPlayer.netPlayers[aPlayerName] == currPlayerUnitsByNames[aPlayerName] then 
				-- all is well, no change 
			else 
				-- player has changed units 
				-- since they can't disappear, 
				-- this event can happen 
				local data = {}
				data.oldUnitName = cfxPlayer.netPlayers[aPlayerName]
				data.newUnitName = aPlayerUnitName
				data.playerName = aPlayerName
				if aPlayerUnitName == "" then aPlayerUnitName = "<none>" end 
				if aPlayerUnitName == "<none>" then 
					-- unit no longer exists, player probably dead,
					-- parachuting or spectating. Maybe even left game
					-- resgisters as 'change' -- is 'left unit'
					cfxPlayer.invokeMonitorsForEvent("changePlayer", "A Player left unit " .. data.oldUnitName, nil, data)
				else 
					-- changed to new unit
					cfxPlayer.invokeMonitorsForEvent("changePlayer", "A Player changed to unit " .. aPlayerUnitName, nil, data)
				end 
			end
		else 
			-- this is a new player
			local data = {}
			data.playerName = aPlayerName
			data.newUnitName = aPlayerUnitName
			cfxPlayer.invokeMonitorsForEvent("newPlayer", "New Player appeared " .. aPlayerName .. " in unit " .. aPlayerUnitName, nil, data)
		end
	end

	-- version 3: detect if a player left 
	for oldPlayerName, oldUnitName in pairs(cfxPlayer.netPlayers) do 
		if not currPlayerUnitsByNames[oldPlayerName] then 
			--local data = {}
			--data.playerName = oldPlayerName
			--data.oldUnitName = oldUnitName
			--cfxPlayer.invokeMonitorsForEvent("leavePlayer", "Player " .. oldPlayerName .. " disappeared from unit " .. oldUnitName, nil, data)
			--
			-- we keep the player in the db by copying 
			-- it over and set the unit name to ""
			-- will cause at least once 'change' event later 
			-- probably two in MP
			currPlayerUnitsByNames[oldPlayerName] = "<none>"
		end
	end
	
	-- update playerGroups for this cycle
	cfxPlayerGroups = currPlayerGroups
	
	-- update network player for this c<cle 
	cfxPlayer.netPlayers = currPlayerUnitsByNames
	
	-- finally, we simply replace the old db with the new one
	cfxPlayer.playerDB = currDB;
end

function cfxPlayer.getAllNetPlayerNames ()
	local themAll = {}
	for aName, aUnitName in cfxPlayer.netPlayers do 
		table.insert(themAll, aName)
	end
	return themAll
end

function cfxPlayer.getPlayerUnitName(aPlayerName) 
	if not aPlayerName then return nil end 
	return cfxPlayer.netPlayers[aPlayerName]
end

function cfxPlayer.isPlayerSeated(aPlayerName)
	local unitName = cfxPlayer.getPlayerUnitName(aPlayerName)
	if not unitName then return false end 
	if unitName == "" or unitName == "<none>" then return false end 
	return true 
end

-- add a monitor to be notified of player events
-- may provide a whitelist of events as array of strings
function cfxPlayer.addMonitor(callback, events)
	local newMonitor = {}
	newMonitor.callback = callback
	newMonitor.events = events 
	cfxPlayer.monitors[callback] = newMonitor
end;

function cfxPlayer.removeMonitor(callback) 
	if (cfxMonitos[callback]) then 
		cfxMonitos[callback] = nil 
	end
end

function cfxPlayer.invokeMonitorsForEvent(evType, description, player, data)
	for callback, monitor in pairs(cfxPlayer.monitors) do
		-- should filter if evType is in monitor.events
		if monitor.events and #monitor.events > 0 then 
			-- only invoke if this event is listed
			if dcsCommon.arrayContainsString(monitor.events, evType) then 
				monitor.callback(evType, description, player, data)
			end
		else 
			monitor.callback(evType, description, player, data)
		end
	end
end

function cfxPlayer.getAllExistingPlayerUnitsRaw()
	local apu = {}
	for i=1, #cfxPlayer.coalitionSides do 
		local theSide = cfxPlayer.coalitionSides[i] 
		-- get all players for this side
		local thePlayers = coalition.getPlayers(theSide) 
		for p=1, #thePlayers do 
			local aUnit = thePlayers[p]
			if aUnit and aUnit:isExist() then 
				table.insert(apu, aUnit)
			end
		end
	end
	return apu 
end

-- evType that can actually happen are 'new', 'leave' for units,
-- 'newGroup' and 'removeGroup' for groups     
function cfxPlayer.defaultMonitor(evType, description, info, data)
	if cfxPlayer.verbose then
		trigger.action.outText("+++Plr - evt '".. evType .."': <" .. description .. ">", 30)
		if (info) then 
			trigger.action.outText("+++Plr: for unit named: " .. info.name, 30) 
		else 
			--trigger.action.outText("+++Plr: no player data", 30)
		end
		--trigger.action.outText("+++Plr: desc: '".. evType .."'<" .. description .. ">", 30)
		-- we ignore the data block
	end
end

function cfxPlayer.start()
	trigger.action.outText("cf/x player v".. cfxPlayer.version .. ": started", 10)
	cfxPlayer.running = true
	cfxPlayer.update()	
end

function cfxPlayer.stop()
	if cfxPlayer.verbose then 
		trigger.action.outText("cf/x player v".. cfxPlayer.version .. ": stopped", 10)
	end
	timer.removeFunction(cfxPlayer.updateSchedule) -- will require another start() to resume
	cfxPlayer.running = false
end

function cfxPlayer.init()
	--trigger.action.outText("cf/x player v".. cfxPlayer.version .. ": loaded", 10)
	-- when verbose, we also add a monitor to display player event
	if cfxPlayer.verbose then 
		cfxPlayer.addMonitor(cfxPlayer.defaultMonitor, {})
		trigger.action.outText("cf/x player is verbose", 10)
	end
	
	cfxPlayer.start()
end

-- get everything rolling, but will only start if autostart is true
cfxPlayer.init()

--TODO: player status: ground, air, dead, none 
-- TODO: event when status changes ground/air/...