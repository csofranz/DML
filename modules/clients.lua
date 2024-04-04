clients = {} 
clients.version = "0.0.0"
clients.ups = 1
clients.verbose = false 
clients.netlog = true 
clients.players = {}
-- player entry: indexed by name 
--   playerName - name of player, same as index
--   uName = unit name 
--   coa = coalition 
-- 	 connected = true/false is currently ingame  

function clients.out(msg)
	-- do some preprocessing?
	if clients.verbose then 
		trigger.action.outText(msg, 30)
	end 
	-- add to own log?
	if clients.netlog then 
		env.info(msg)
	end
end 

--[[--
Event ID:
	1 = player enters mission for first time  
	2 = player enters unit 
	3 = player leaves unit 
	4 = player changes unit
	5 = player changes coalition 
	
	
Sequence of events 
	Player enters mission first time 
		- player enters mission (new player) ID = 1
		- player enters unit ID = 2
		
	Player is no longer active (their unit is gone)
		- player leaves unit ID = 3

	Player enters unit after having already been in the mission 
		- (player changes coalition) if unit belongs to different coa 
		- (player changes unit if unit different than before) 
		- player enters unit 
	
--]]--
--
-- client events 
-- 
clients.cb = {} -- profile = (id, this, last)
function clients.invokeCallbacks(ID, this, last)
	for idx, cb in pairs(clients.cb) do 
		cb(ID, this, last)
	end
end

function clients.addCallback(theCB)
	table.insert(clients.cb, theCB)
end 


function clients.playerEnteredMission(thisTime)
	clients.out("clients: Player <" .. thisTime.playerName .. "> enters mission for the first time")
	clients.invokeCallbacks(1, thisTime)
end

function clients.playerEnteredUnit(thisTime)
	-- called when player enters a unit
	clients.out("clients: Player <" .. thisTime.playerName .. "> enters Unit <" .. thisTime.uName .. ">.")
	clients.invokeCallbacks(2, thisTime)
end 

function clients.playerLeavesUnit(lastTime)
	-- called when player leaves a unit
	clients.out("clients: Player <" .. lastTime.playerName .. "> leaves Unit <" .. lastTime.uName .. ">.")
	clients.invokeCallbacks(3, lastTime)
end

function clients.playerChangedUnits(thisTime, lastTime)
	-- called when player enters a different unit
	clients.out("clients: Player <" .. thisTime.playerName .. "> changes from Unit <" .. lastTime.uName .. "> to NEW unit <" .. thisTime.uName .. ">.")
	clients.invokeCallbacks(4, thisTime, lastTime)
end

function clients.playerChangedCoalition(thisTime, lastTime)
	-- called when player enters a different unit
	clients.out("clients: Player <" .. thisTime.playerName .. "> changes from coalition <" .. lastTime.coa .. "> to NEW coalition <" .. thisTime.coa .. ">.")
	clients.invokeCallbacks(4, thisTime, lastTime)
end

-- check all connected player units 
function clients.compareStatus(thisTime, lastTime)
	if lastTime then
		-- they were known last time I checked. see if they were in-game 
		if thisTime.connected == lastTime.connected then 
			-- status is the same as before
		else 
			-- player entered or left mission, and was known last time
			if thisTime.connected then 
				-- player connected but was known, do nothing 
			else 
				-- player left mission. do we want to record this?
			end 
		end 
		-- check if they have the same unit name
		-- if not, check if they have changed coas 
		if lastTime.uName == thisTime.uName then
			-- same unit, all is fine 
		else 
			-- new unit. check if same side 
			if lastTime.coa == thisTime.coa then 
				-- player stayed in same coa 
			else 
				-- player changed coalition 
				clients.playerChangedCoalition(thisTime, lastTime)
			end 
			clients.playerEnteredUnit(thisTime)
			clients.playerChangedUnits(thisTime, lastTime)
		end
	else 
		-- player is new to mission 
		clients.playerEnteredMission(thisTime)
		clients.playerEnteredUnit(thisTime)
	end 
end 

function clients.checkPlayers()
	local connectedNow = {} -- players that are connected now 
	local allCoas = {0, 1, 2}
	-- collect all currently connected players 
	for idx, coa in pairs(allCoas) do 
		local cPlayers = coalition.getPlayers(coa) -- gets UNITS!
		for idy, aPlayerUnit in pairs(cPlayers) do 
			if aPlayerUnit and Unit.isExist(aPlayerUnit) then 
				local entry = {}
				local playerName = aPlayerUnit:getPlayerName()
				entry.playerName = playerName 
				entry.uName = aPlayerUnit:getName()
				entry.coa = coa 
				entry.connected = true 
				connectedNow[playerName] = entry 
				
				-- see if they were connected last time we checked 
				local lastTime = clients.players[playerName]
				clients.compareStatus(entry, lastTime)
			end
		end
	end 
	
	-- now find players who are no longer represented and 
	-- event them 
	for aPlayerName, lastTime in pairs(clients.players) do 
		local thisTime = connectedNow[aPlayerName]
		if thisTime then 
			-- is also present now. skip 
		else 
			-- no longer active, see if they were active last time 
			if lastTime.connected then 
				-- they were active, generate disco event 
				clients.playerLeavesUnit(lastTime)
			end 
			lastTime.connected = false 
			-- keep on roster
			connectedNow[aPlayerName] = lastTime
		end 
	end 
	
	clients.players = connectedNow
end

function clients.update()
	timer.scheduleFunction(clients.update, {}, timer.getTime() + 1)
	clients.checkPlayers()	
end 

--
-- Event handling
--
function clients:onEvent(theEvent)
	if not theEvent then return end 
	local theUnit = theEvent.initiator
	if not theUnit then return end 
	if not theUnit.getPlayerName or not theUnit:getPlayerName() then return end 
	
	-- we have a player birth. Simply invoke checkplayers 
	clients.out("clients: detected player birth event.")
	clients.checkPlayers()	
end 

--
-- Start 
--
function clients.start()
	world.addEventHandler(clients)
	timer.scheduleFunction(clients.update, {}, timer.getTime() + 1)
	trigger.action.outText("clients v" .. clients.version .. " running.", 30)
end 

clients.start()