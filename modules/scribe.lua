scribe = {}
scribe.version = "1.0.1"
scribe.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"cfxMX",
}

--[[--
Player statistics package
VERSION HISTORY 
	1.0.0 Initial Version 
	1.0.1 postponed land, postponed takeoff, unit_lost 
--]]--
scribe.verbose = true 
scribe.db = {} -- indexed by player name 
scribe.playerUnits = {} -- indexed by unit name. for crash detection 

--[[--
	unitEntry:
		ttime -- total time in seconds 
		airTime -- total air time 
		landings -- number of landings 
		lastLanding -- time of last landing OR DEPARTURE.  
		departures -- toital take-offs 
		crashes -- number of total crashes, deaths etc 
--]]--

function scribe.createUnitEntry()
	local theEntry = {}
	theEntry.ttime = 0
	theEntry.lastTime = 99999999 -- NOT math.huge because json
	theEntry.landings = 0 
	theEntry.lastLanding = 99999999 -- not math.huge -- in the future 
	theEntry.departures = 0 
	theEntry.crashes = 0
	theEntry.startUps = 0 
	theEntry.rescues = 0 
	return theEntry
end

--[[--
	playerEntry: 
		units[] -- by type name indexed types the player has flown 
				-- each entry has 
		lastUnitName -- name of the unit player was last seen in
					 -- used to determine if player is still in-game 
		lastUnitType
		isActive -- used to detect if player has left and close down record
--]]--

function scribe.createPlayerEntry(name)
	local theEntry = {}
	theEntry.playerName = name -- for easy access 
	local theUnit = dcsCommon.getPlayerUnit(name)
	local theType = theUnit:getTypeName()
	local unitName = theUnit:getName()
	theEntry.units = {}
	theEntry.lastUnitName = "cfxNone" -- don't ever use that name 
	theEntry.lastUnitType = "none"
	theEntry.isActive = false -- is player in game?
	return theEntry 
end

function scribe.getPlayerNamed(name) -- lazy allocation
	local theEntry = scribe.db[name]
	if not theEntry then 
		theEntry = scribe.createPlayerEntry(name)
		scribe.db[name] = theEntry
	end
	return theEntry 
end

function scribe.sumPlayerEntry(theEntry, theField)
	local sum = 0 
	for idx, aUnit in pairs(theEntry.units) do 
		if aUnit[theField] then sum = sum + aUnit[theField] end
	end	
	return sum 
end

function scribe.tickEntry(theEntry)
	if not theEntry then return 0 end 
	local now = timer.getTime()
	local uEntry = theEntry.units[theEntry.lastUnitType]
	if not uEntry then return 0 end -- can happen on idling server that has reloaded. all last players have invalid last units 
	local delta = now - uEntry.lastTime
	if delta < 0 then delta = 0 end 
	uEntry.lastTime = now 
	uEntry.ttime = uEntry.ttime + delta 
	return delta 
end


function scribe.finalizeEntry(theEntry)
	-- player no longer in game. finalize last entry 
	-- and make it inactive 
	theEntry.isActive = false 
	local delta = scribe.tickEntry(theEntry) -- on LAST flown aircraft
	local uEntry = theEntry.units[theEntry.lastUnitType]
	if uEntry then 
		uEntry.lastTime = 99999999 -- NOT math.huge 
		
		local deltaTime = dcsCommon.processHMS("<:h>:<:m>:<:s>", delta)
		local fullTime = dcsCommon.processHMS("<:h>:<:m>:<:s>", uEntry.ttime)
		if scribe.byePlayer then 
			trigger.action.outText("Player " .. theEntry.playerName .. " left " .. theEntry.lastUnitName .. " (a " .. theEntry.lastUnitType .. "), total time in aircraft " .. fullTime ..".", 30)
		end 
	end 
end 

function scribe.entry2text(uEntry, totals)
	-- validate uEntry, lazy init of missing fields 
	if not uEntry then uEntry = {} end 
	if not uEntry.ttime then uEntry.ttime = 0 end
	if not uEntry.departures then uEntry.departures = 0 end 
	if not uEntry.landings then uEntry.landings = 0 end 
	if not uEntry.crashes then uEntry.crashes = 0 end 
	if not uEntry.startups then uEntry.startups = 0 end 
	if not uEntry.rescues then uEntry.rescues = 0 end 
	
	local t = ""
	if not totals.ttime then totals.ttime = 0 end 
	t = t .. scribe.lTime .. " " .. dcsCommon.processHMS("<:h>:<:m>:<:s>", uEntry.ttime) .. " hrs" 
	totals.ttime = totals.ttime + uEntry.ttime
	if scribe.departures then 
		t = t .. ", " .. scribe.lDeparture .. " " .. uEntry.departures
		if not totals.departures then totals.departures = 0 end 
		totals.departures = totals.departures + uEntry.departures
	end 
	if scribe.landings then 
		t = t .. ", " .. scribe.lLanding .. " " .. uEntry.landings
		if not totals.landings then totals.landings = 0 end 
		totals.landings = totals.landings + uEntry.landings
	end
	if scribe.crashes then 
		t = t .. ", " .. scribe.lCrash .. " " .. uEntry.crashes
		if not totals.crashes then totals.crashes = 0 end 
		totals.crashes = totals.crashes + uEntry.crashes 
	end 
	if scribe.startUps then 
		t = t .. ", " .. scribe.lStartUp .. " " .. uEntry.startUps
		if not totals.startUps then totals.startUps = 0 end 
		totals.startUps = totals.startUps + uEntry.startUps 
	end 
	if scribe.rescues then 
		t = t .. ", " .. scribe.lRescue .. " " .. uEntry.rescues
		if not totals.rescues then totals.rescues = 0 end 
		totals.rescues = totals.rescues + uEntry.rescues 
	end
	return t 
end

--
-- Event handling 
--
function scribe.playerBirthedIn(playerName, theUnit)
	-- access db 
	local theEntry = scribe.getPlayerNamed(playerName) -- can be new
	local myType = theUnit:getTypeName() 
	local uName = theUnit:getName() 
	local theGroup = theUnit:getGroup() 
	local gID = theGroup:getID()
	-- check if this player is still active
	if theEntry.isActive then 
		-- do something to remedy this 
		scribe.finalizeEntry(theEntry)
	end 
	
	-- check if player switched airframes 
	if theEntry.lastUnitName == uName  and scribe.verbose then 
		trigger.action.outText("+++scb: player <" .. playerName .. "> reappeard in same unit <" .. uName .. ">", 30)
	else 

	end 
	theEntry.lastUnitName = uName 
	theEntry.lastUnitType = myType 
	theEntry.isActive = true -- activate player 
	
	-- set us up to track this player in this unit 
	local myTypeEntry = theEntry.units[myType]
	if not myTypeEntry then 
		myTypeEntry = scribe.createUnitEntry()
		local uGroup = theUnit:getGroup()
		local gName = uGroup:getName()
		myTypeEntry.gName = gName 
		theEntry.units[myType] = myTypeEntry
	end 
	
	myTypeEntry.lastTime = timer.getTime()
	
	if scribe.verbose then 
		trigger.action.outText("+++scb: player <" .. playerName .. "> entered aircraft <" .. uName .. "> (a " .. myType .. ")", 30)
	end 
	
	if scribe.greetPlayer then 
		local msg = "\nWelcome " .. theEntry.playerName .. " to your " .. myType .. ". Your stats currently are:\n\n"
		msg = msg .. scribe.entry2data(theEntry) .. "\n"
		trigger.action.outTextForGroup(gID, msg, 30)
	end 
	
end

function scribe.playerCrashed(playerName)
	if scribe.verbose then 
		trigger.action.outText("+++scb: enter crash for <" .. playerName .. ">", 30)
	end 

	local theEntry = scribe.getPlayerNamed(playerName) 
	if not theEntry.isActive then 
		if scribe.verbose then 
			trigger.action.outText("+++scb: player <" .. playerName .. "> CRASH event ignored: player not active", 30)
		end 
		return
	end 
	local uEntry = theEntry.units[theEntry.lastUnitType]
	uEntry.crashes = uEntry.crashes + 1
	scribe.finalizeEntry(theEntry)
end

function scribe.playerEjected(playerName)
	if scribe.verbose then 
		trigger.action.outText("+++scb: enter eject for <" .. playerName .. ">, handing off to crash", 30)
	end 
	-- counts as a crash 
	local theEntry = scribe.getPlayerNamed(playerName) 
	if not theEntry.isActive then 
		if scribe.verbose then 
			trigger.action.outText("+++scb: player <" .. playerName .. "> EJECT event ignored: player not active", 30)
		end 
		return
	end 
	
	scribe.playerCrashed(playerName)
end

function scribe.playerDied(playerName)
	if scribe.verbose then 
		trigger.action.outText("+++scb: player <" .. playerName .. "> DEAD event, handing off to crashS", 30)
	end -- counts as a crash 
	local theEntry = scribe.getPlayerNamed(playerName) 
	if not theEntry.isActive then 
		if scribe.verbose then 
			trigger.action.outText("+++scb: player <" .. playerName .. "> DEAD event ignored: player not active", 30)
		end 
		return
	end 
	
	scribe.playerCrashed(playerName)
end

function scribe.engineStarted(playerName)
	local theEntry = scribe.getPlayerNamed(playerName) 
	if not theEntry.isActive then 
		if scribe.verbose then 
			trigger.action.outText("+++scb: player <" .. playerName .. "> STARTUP event ignored: player not active", 30)
		end 
		return
	end
	
	local uEntry = theEntry.units[theEntry.lastUnitType]
	uEntry.startUps = uEntry.startUps + 1
	
	if scribe.verbose then 
		trigger.action.outText("+++scb: startup registered for <" .. playerName .. ">.", 30)
	end 	
end

function scribe.playerLanded(playerName)
	local theEntry = scribe.getPlayerNamed(playerName) 
	if not theEntry.isActive then 
		if scribe.verbose then 
			trigger.action.outText("+++scb: player <" .. playerName .. "> landing event ignored: player not active", 30)
		end 
		return
	end
	
	local uEntry = theEntry.units[theEntry.lastUnitType]
	-- see if last landing is at least xx seconds old 
	local now = timer.getTime()
	delta = now - uEntry.lastLanding
	if delta > scribe.landingCD or delta < 0 then 
		uEntry.landings = uEntry.landings + 1 
	else 
		if scribe.verbose then 
			trigger.action.outText("+++scb: landing ignored: cooldown active", 30)
		end 
	end
	uEntry.lastLanding = now 

end

function scribe.playerDeparted(playerName)
	local theEntry = scribe.getPlayerNamed(playerName) 
	if not theEntry.isActive then 
		if scribe.verbose then 
			trigger.action.outText("+++scb: player <" .. playerName .. "> take-off event ignored: player not active", 30)
		end 
		return
	end
	
	local uEntry = theEntry.units[theEntry.lastUnitType]
	-- see if last landing is at least xx seconds old 
	local now = timer.getTime()
	delta = now - uEntry.lastLanding -- we use laastLanding for BOTH!
	if delta > scribe.landingCD or delta < 0 then 
		uEntry.departures = uEntry.departures + 1 
	else 
		if scribe.verbose then 
			trigger.action.outText("+++scb: departure ignored: cooldown active", 30)
		end 
	end
	uEntry.lastLanding = now -- also for Departures!

end

--
-- API
--
-- invoked from other modules 
function scribe.playerRescueComplete(playerName)
	local theEntry = scribe.getPlayerNamed(playerName) 
	if not theEntry.isActive then 
		if scribe.verbose then 
			trigger.action.outText("+++scb: player <" .. playerName .. "> rescue complete event ignored: player not active", 30)
		end 
		return
	end
	local uEntry = theEntry.units[theEntry.lastUnitType]
	if not uEntry then 
		-- this should not happen 
		trigger.action.outText("+scb: unknown unit for player <" .. playerName .. "> in recue complete. Ignored", 30)
		return 
	end
	if not uEntry.rescues then uEntry.rescues = 0 end 
	uEntry.rescues = uEntry.rescues + 1 
end

function scribe:onEvent(theEvent)
	if not theEvent.initiator then return end 
	local theUnit = theEvent.initiator
	if not theUnit then return end 
	local uName = theUnit:getName()
	if scribe.playerUnits[uName]  and scribe.verbose then 
		trigger.action.outText("+++scb: event <" .. theEvent.id .. " = " .. dcsCommon.event2text(theEvent.id)  .. ">, concerns player unit named <" .. uName .. ">.", 30)
	end 
	
	if not theUnit.getPlayerName then
		if scribe.playerUnits[uName] and scribe.verbose then 
			trigger.action.outText("+++scb no more a player unit (case A: getPlanerName not implemented), event = <" .. theEvent.id .. ">, unit named <" .. uName .. ">", 30)
		end 
		return 
	end 
	
	local playerName = theUnit:getPlayerName() 
	if not playerName then 
		if scribe.playerUnits[uName] and scribe.verbose then 
			trigger.action.outText("+++scb no more a player unit (case B: nilplayer name), event = <" .. theEvent.id .. ">, unit named <" .. uName .. ">", 30)
		end 
		return 
	end 
	-- when we get here we have a player event 
	
	-- players can only ever activate by birth event 
	if theEvent.id == 15 then -- birth 
		scribe.playerBirthedIn(playerName, theUnit) 
		scribe.playerUnits[uName] = playerName -- for crash helo detection 
	end 
	
	if theEvent.id == 8 or 
	   theEvent.id == 9 or 
	   theEvent.id == 30 then -- dead, pilot_dead, unit_lost 
		scribe.playerDied(playerName)
	end 
	
	if theEvent.id == 6 then -- ejected 
		scribe.playerEjected(playerName)
	end
	
	if theEvent.id == 5 then -- crash, maybe not called in MP 
		scribe.playerCrashed(playerName)
	end 
	
	if theEvent.id == 4 or -- landed 
	   theEvent.id == 56 then 
		scribe.playerLanded(playerName)
	end 
	
	if theEvent.id == 3 or -- take-off
	   theEvent.id == 55 then -- postponed take-off
		scribe.playerDeparted(playerName)
--		trigger.action.outText("departure detected", 30)
	end 
	
	if theEvent.id == 18 then -- engine start 
		-- make sure group isn't on hotstart 
		local theGroup = theUnit:getGroup()
		local gName = theGroup:getName()
		if cfxMX.groupHotByName[gName] then 
			if scribe.verbose then 
				trigger.action.outText("scb: ignored engine start: hot start for <" .. playerName .. ">", 30)
			end 
		else 
			if scribe.verbose then 
				trigger.action.outText("scb: engine start for <" .. playerName .. ">", 30)
			end 
			scribe.engineStarted(playerName)
		end 
	end
end 

--
-- GUI
--
function scribe.redirectCheckData(args)
	timer.scheduleFunction(scribe.doCheckData, args, timer.getTime() + 0.1)
end

function scribe.doCheckData(unitInfo)
	local unitName = unitInfo.uName 

	-- we now try and match player to the unit by rummaning through db
	local thePlayerEntry = nil 
	for pName, theEntry in pairs(scribe.db) do
		if unitName == theEntry.lastUnitName and theEntry.isActive then 
			thePlayerEntry = theEntry 
		end
	end 
	
	if (not thePlayerEntry) then 
		if scribe.verbose then 
			trigger.action.outText("+++scb: cannot retrieve player for unit <" .. unitName .. ">", 30)
		end
		return 
	end	
		
	-- tick over so we have updated time 
	scribe.tickEntry(thePlayerEntry)
	local msg = "Player " .. thePlayerEntry.playerName .. ":\n"
	msg = msg .. scribe.entry2data(thePlayerEntry)
	trigger.action.outTextForGroup(unitInfo.gID, msg, 30)
end

function scribe.entry2data(thePlayerEntry)
	local msg = ""
	local totals = {}
	for aType, uEntry in pairs (thePlayerEntry.units) do 
		msg = msg .. aType .. " -- " .. scribe.entry2text(uEntry, totals) .. "\n"
	end
	if dcsCommon.getSizeOfTable(thePlayerEntry.units) > 1 then 
		local dummy = {}
		msg = msg .. "\nTotals -- " .. scribe.entry2text(totals, dummy) .. "\n"
	end 
	return msg
end

--
-- GC -- detect player leaving 
-- 
function scribe.GC()
	timer.scheduleFunction(scribe.GC, {}, timer.getTime() + 1)
	-- iterate through all players in DB and see if they 
	-- are still on-line. 
	for pName, theEntry in pairs(scribe.db) do 
		if theEntry.isActive then 
			-- this player is on the books as in the game 
			local theUnit = Unit.getByName(theEntry.lastUnitName)
			if theUnit and Unit.isExist(theUnit) and theUnit:getLife() >= 1 then 
				-- all is fine, go on 
			else 
				-- this unit no longer exists and we finalize player 
				if scribe.verbose then 
					trigger.action.outText("+++scb: player <" .. pName .. "> left <" .. theEntry.lastUnitName .. "> unit, finalizing", 30)
				end 
				scribe.finalizeEntry(theEntry)
			end
		end
	end
end


--
-- start
-- 
function scribe.startPlayerGUI()
	-- scan all mx players 
	-- note: currently assumes single-player groups
	-- in preparation of single-player 'commandForUnit'
	-- ASSUMES SINGLE-UNIT PLAYER GROUPS!
	for uName, uData in pairs(cfxMX.playerUnitByName) do 
		local unitInfo = {}
		-- try and access each unit even if we know that the 
		-- unit does not exist in-game right now 
		local gData = cfxMX.playerUnit2Group[uName]
		local gName = gData.name 
		local coa = cfxMX.groupCoalitionByName[gName]
		local theType = uData.type

		if scribe.verbose then 
			trigger.action.outText("unit <" .. uName .. ">: type <" .. theType .. "> coa <" .. coa .. ">, group <" .. gName .. ">", 30)
		end 
		
		unitInfo.uName = uName -- needed for reverse-lookup 
		unitInfo.gName = gName -- also needed for reverse lookup 
		unitInfo.coa = coa 
		unitInfo.gID = gData.groupId
		unitInfo.uID = uData.unitId
		unitInfo.theType = theType
		unitInfo.cat = cfxMX.groupTypeByName[gName]
		unitInfo.root = missionCommands.addSubMenuForGroup(unitInfo.gID, scribe.uiMenu)
		unitInfo.checkData = missionCommands.addCommandForGroup(unitInfo.gID, "Get Pilot's Statistics", unitInfo.root, scribe.redirectCheckData, unitInfo)
	end
end

--
-- Config
--
function scribe.readConfigZone()
	local theZone = cfxZones.getZoneByName("scribeConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("scribeConfig")
	end 
	scribe.verbose = theZone.verbose 
	scribe.hasGUI = theZone:getBoolFromZoneProperty("hasGUI", true) 
	scribe.uiMenu = theZone:getStringFromZoneProperty("uiMenu", "Mission Logbook")
	scribe.greetPlayer = theZone:getBoolFromZoneProperty("greetPlayer", true)
	scribe.byePlayer = theZone:getBoolFromZoneProperty("byebyePlayer", true) 
	scribe.landings = theZone:getBoolFromZoneProperty("landings", true) 
	scribe.lLanding = theZone:getStringFromZoneProperty("lLandings", "landings:")
	scribe.departures = theZone:getBoolFromZoneProperty("departures", true) 
	scribe.lDeparture = theZone:getStringFromZoneProperty("lDepartures", "take-offs:")
	scribe.startUps = theZone:getBoolFromZoneProperty("startups", true) 
	scribe.lStartUp = theZone:getStringFromZoneProperty("lStartups", "starts:")
	scribe.crashes = theZone:getBoolFromZoneProperty("crashes", true)
	scribe.lCrash = theZone:getStringFromZoneProperty("lCrashes", "crashes:")
	scribe.rescues = theZone:getBoolFromZoneProperty("rescues", false)
	scribe.lRescue = theZone:getStringFromZoneProperty("lRescues", "rescues:")
	scribe.lTime = theZone:getStringFromZoneProperty("lTime", "time:")
	scribe.landingCD = theZone:getNumberFromZoneProperty("landingCD", 60) -- seconds between stake-off, landings, or either
	
end

--
-- load / save (game data)
--
function scribe.saveData()
	local theData = {}
	-- tick over all player entry recors so we can save 
	-- most recent data 
	for planerName, thePlayerEntry in pairs(scribe.db) do 
		if thePlayerEntry then scribe.tickEntry(thePlayerEntry) end 
	end 
	
	-- save current log. simple clone 
	local theLog = dcsCommon.clone(scribe.db)
	theData.theLog = theLog

	return theData
end

function scribe.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("scribe")
	if not theData then 
		if scribe.verbose then 
			trigger.action.outText("+++scb: no save date received, skipping.", 30)
		end
		return
	end
	
	local theLog = theData.theLog
	scribe.db = theLog 
	
	-- post-proc: set all to inactive, no player can be in game at start  
	for pName, theEntry in pairs(scribe.db) do 
		if theEntry.isActive then 
			theEntry.isActive = false 
			theEntry.lastUnitName = "cfxNone"
			theEntry.lastUnitType = "xxx"
			for uName, uEntry in pairs (theEntry.units) do 
				uEntry.lastTime = 99999999 -- NOT math.huge 
				uEntry.lastLanding = 99999999 -- NOT math.huge! 
			end
		end
	end
end

--
-- start
--
function scribe.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx scribe requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx scribe", scribe.requiredLibs) then
		return false 
	end
	
	-- install event handler 
	world.addEventHandler(scribe)
	
	-- get config 
	scribe.readConfigZone()
	
	-- install menus to all player units 
	if scribe.hasGUI then 
		scribe.startPlayerGUI()
	end
	
	-- now load all save data and populate map with troops that
	-- we deployed last save. 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = scribe.saveData
		persistence.registerModule("scribe", callbacks)
		-- now load my data 
		scribe.loadData()
	end
	
	-- start GC 
	timer.scheduleFunction(scribe.GC, {}, timer.getTime() + 1)
	
	-- say hi!
	trigger.action.outText("cfx scribe v" .. scribe.version .. " started.", 30)
	return true 
end

-- let's go 
if not scribe.start() then 
	trigger.action.outText("cfx scribe module failed to launch.", 30)
end
