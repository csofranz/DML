playerZone = {}
playerZone.version = "1.0.0"
playerZone.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
playerZone.playerZones = {}
--[[--
	Version History
	1.0.0 - Initial version 
	1.0.1 - pNum --> pNum# 
	
--]]--

function playerZone.createPlayerZone(theZone)
	-- start val - a range
	theZone.pzCoalition = cfxZones.getCoalitionFromZoneProperty(theZone, "playerZone", 0)
	

	-- Method for outputs
	theZone.pzMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "pzMethod") then 
		theZone.pzMethod = cfxZones.getStringFromZoneProperty(theZone, "pwMethod", "inc")
	end 
	
	if cfxZones.hasProperty(theZone, "pNum#") then 
		theZone.pNum = cfxZones.getStringFromZoneProperty(theZone, "pNum#", "none")
	elseif cfxZones.hasProperty(theZone, "pNum") then 
		theZone.pNum = cfxZones.getStringFromZoneProperty(theZone, "pNum", "none") 
	end 
	
	if cfxZones.hasProperty(theZone, "added!") then 
		theZone.pAdd = cfxZones.getStringFromZoneProperty(theZone, "added!", "none")
	end
	
	if cfxZones.hasProperty(theZone, "gone!") then 
		theZone.pRemove = cfxZones.getStringFromZoneProperty(theZone, "gone!", "none")
	end
	
	theZone.playersInZone = {} -- indexed by unit name 
end


function playerZone.collectPlayersForZone(theZone)
	local factions = {0, 1, 2}
	local zonePlayers = {}
	for idx, f in pairs (factions) do 
		if theZone.pzCoalition == 0 or f == theZone.pzCoalition then 
			local allPlayers = coalition.getPlayers(f)
			for idy, theUnit in pairs (allPlayers) do 
				local loc = theUnit:getPoint()
				if cfxZones.pointInZone(loc, theZone) then 
					zonePlayers[theUnit:getName()] = theUnit
				end
			end
		end
	end
	return zonePlayers
end

function playerZone.processZone(theZone)
	local nowInZone = playerZone.collectPlayersForZone(theZone)
	-- find new players in zone 
	local hasNew = false 
	local newCount = 0
	for name, theUnit in pairs(nowInZone) do 
		if not theZone.playersInZone[name] then 
			-- this unit was not here last time 
			hasNew = true 
			if playerZone.verbose or theZone.verbose then 
				trigger.action.outText("+++pZone: new player unit <" .. name .. "> in zone <" .. theZone.name .. ">", 30)
			end
		end
		newCount = newCount + 1
	end	
	-- find if players have left the zone
	local hasGone = false 
	for name, theUnit in pairs(theZone.playersInZone) do 
		if not nowInZone[name] then 
			hasGone = true 
			if playerZone.verbose or theZone.verbose then 
				trigger.action.outText("+++pZone: player unit <" .. name .. "> disappeared from <" .. theZone.name .. ">", 30)
			end
		end
	end
	
	-- flag handling and banging
	if theZone.pNum then 
		cfxZones.setFlagValueMult(theZone.pNum, newCount, theZone)
	end
	
	if theZone.pAdd and hasNew then 
		if theZone.verbose or playerZone.verbose then 
			trigger.action.outText("+++pZone: banging <" .. theZone.name .. ">'s 'added!' flags <" .. theZone.pAdd .. ">", 30)
		end
		cfxZones.pollFlag(theZone.pAdd, theZone.pzMethod, theZone)
	end
	
	if theZone.pRemove and hasGone then 
		if theZone.verbose or playerZone.verbose then 
			trigger.action.outText("+++pZone: banging <" .. theZone.name .. ">'s 'gone' flags <" .. theZone.pRemove .. ">", 30)
		end
		cfxZones.pollFlag(theZone.pAdd, theZone.pzMethod, theZone)
	end
end

--
-- Update 
--
function playerZone.update()
	-- re-invoke in 1 second
	timer.scheduleFunction(playerZone.update, {}, timer.getTime() + 1)
	
	-- iterate all zones and check them
	for idx, theZone in pairs(playerZone.playerZones) do 
		playerZone.processZone(theZone)
	end
end

--
-- Read Config Zone
--
function playerZone.readConfigZone(theZone)
	-- currently nothing to do 
end

--
-- Start
--
function playerZone.start()
	if not dcsCommon.libCheck("cfx Player Zone", 
							  playerZone.requiredLibs) 
	then return false end
	
	local theZone = cfxZones.getZoneByName("playerZoneConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("playerZoneConfig")
	end 
	playerZone.readConfigZone(theZone)
	
	local pZones = cfxZones.zonesWithProperty("playerZone")
	for k, aZone in pairs(pZones) do
		playerZone.createPlayerZone(aZone)
		playerZone.playerZones[aZone.name] = aZone
	end
	
	-- start update cycle 
	playerZone.update()
	return true 
end

if not playerZone.start() then 
	trigger.action.outText("+++ aborted playerZone v" .. playerZone.version .. "  -- start failed", 30)
	playerZone = nil 
end

--[[--
	additional features: 
	- filter by type 
	- filter by cat 
--]]--