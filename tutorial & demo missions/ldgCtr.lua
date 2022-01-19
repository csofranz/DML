ldgCtr = {}
--
-- DML-based mission that counts the number of
-- successful missions for all players. MP-capable
--

ldgCtr.ups = 1 -- 1 update per second
-- minimal libraries required
ldgCtr.requiredLibs = {
	"dcsCommon", -- minimal module for all
	"cfxZones", -- Zones, of course 
	"cfxPlayer", -- player events
}

ldgCtr.config = {} -- for reading config zones
ldgCtr.landings = {} -- set all landings to 0
--
-- world event handling
--
function ldgCtr.wPreProc(event)
	return event.id == 4 -- look for 'landing event'
end

function ldgCtr.worldEventHandler(event)
	-- wPreProc filters all events EXCEPT landing
	local theUnit = event.initiator
	local uName = theUnit:getName()
	local playerName = theUnit:getPlayerName()
	trigger.action.outText(uName .. " has landed.", 30)
	if playerName then 
		-- if a player landed, count their landing 
		local numLandings = ldgCtr.landings[playerName]
		if not numLandings then numLandings = 0 end 
		numLandings = numLandings + 1
		ldgCtr.landings[playerName] = numLandings
		trigger.action.outText("Player " .. playerName .. " completed ".. numLandings .." landings.", 30)
	end
end

--
-- player event handling
--
function ldgCtr.playerEventHandler (evType, description, info, data)
	-- not needed
end


--
-- update loop
--
function ldgCtr.update() 
	-- schedule myself in 1/ups seconds
	timer.scheduleFunction(ldgCtr.update, {}, timer.getTime() + 1/ldgCtr.ups)
	
	-- no regular checks needed
end

--
-- read configuration from zone 'ldgCtrConfig'
-- 

function ldgCtr.readConfiguration()
	local theZone = cfxZones.getZoneByName("ldgCtrConfig")
	if not theZone then return end 
	ldgCtr.config = cfxZones.getAllZoneProperties(theZone)
end

--
-- start
-- 
function ldgCtr.start()
	-- ensure that all modules have loaded
	if not dcsCommon.libCheck("Landing Counter", 
		ldgCtr.requiredLibs) then
		return false 
	end
	
	-- read any configuration values placed in a config zone on the map
	ldgCtr.readConfiguration()
	
	-- init variables & state 
	ldgCtr.landings = {}
	
	-- subscribe to world events 
	dcsCommon.addEventHandler(ldgCtr.worldEventHandler, 
							  ldgCtr.wPreProc) -- no post nor rejected
	
	-- subscribe to player events 
	cfxPlayer.addMonitor(ldgCtr.playerEventHandler)
	
	
	-- start the event loop. it will sustain itself 
	ldgCtr.update()
	
	-- say hi!
	trigger.action.outText("Landing Counter mission running!", 30)
	return true 
end

-- start main
if not ldgCtr.start() then 
	trigger.action.outText("Landing Counter failed to run", 30)
	ldgCtr = nil
end
