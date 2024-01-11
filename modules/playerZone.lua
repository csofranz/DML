playerZone = {}
playerZone.version = "2.0.0"
playerZone.requiredLibs = {
	"dcsCommon", 
	"cfxZones", 
}
playerZone.playerZones = {}
--[[--
	Version History
	1.0.0 - Initial version 
	1.0.1 - pNum --> pNum# 
	2.0.0 - dmlZones
	        red#, blue#, total#
	
--]]--

function playerZone.createPlayerZone(theZone)
	-- start val - a range
	theZone.pzCoalition = theZone:getCoalitionFromZoneProperty( "playerZone", 0)
	-- Method for outputs
	
	theZone.pzMethod = theZone:getStringFromZoneProperty("method", "inc")
	if theZone:hasProperty("pzMethod") then 
		theZone.pzMethod = theZone:getStringFromZoneProperty("pwMethod", "inc")
	end 
	
	if theZone:hasProperty("pNum#") then 
		theZone.pNum = theZone:getStringFromZoneProperty("pNum#", "none")
	end 
	
	if theZone:hasProperty("added!") then 
		theZone.pAdd = theZone:getStringFromZoneProperty("added!", "none")
	end
	
	if theZone:hasProperty("gone!") then 
		theZone.pRemove = theZone:getStringFromZoneProperty("gone!", "none")
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
				if theZone:pointInZone(loc) then 
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
		theZone:setFlagValue(theZone.pNum, newCount)
	end
	
	if theZone.pAdd and hasNew then 
		if theZone.verbose or playerZone.verbose then 
			trigger.action.outText("+++pZone: banging <" .. theZone.name .. ">'s 'added!' flags <" .. theZone.pAdd .. ">", 30)
		end
		theZone:pollFlag(theZone.pAdd, theZone.pzMethod)
	end
	
	if theZone.pRemove and hasGone then 
		if theZone.verbose or playerZone.verbose then 
			trigger.action.outText("+++pZone: banging <" .. theZone.name .. ">'s 'gone' flags <" .. theZone.pRemove .. ">", 30)
		end
		theZone:pollFlag(theZone.pAdd, theZone.pzMethod)
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
		local neutrals = coalition.getPlayers(0)
		local neutralNum = #neutrals 
		local reds = coalition.getPlayers(1)
		local redNum = #reds 
		local blues = coalition.getPlayers(2)
		local blueNum = #blues	
		local totalNum = neutralNum + redNum + blueNum 
		if playerZone.neutralNum then 
			cfxZones.setFlagValue(playerZone.neutralNum, neutralNum, playerZone)
		end 
		if playerZone.redNum then 
			cfxZones.setFlagValue(playerZone.redNum, redNum, playerZone)
		end 
		if playerZone.blueNum then 
			cfxZones.setFlagValue(playerZone.blueNum, blueNum, playerZone)
		end 
		if playerZone.totalNum then 
			cfxZones.setFlagValue(playerZone.totalNum, totalNum, playerZone)
		end 
		playerZone.processZone(theZone)
	end
end

--
-- Read Config Zone
--
function playerZone.readConfigZone(theZone)
	playerZone.name = "playerZoneConfig" -- cfxZones compat 
	-- currently nothing to do 
	if theZone:hasProperty("red#") then 
		playerZone.redNum = theZone:getStringFromZoneProperty("red#", "none")
	end
	if theZone:hasProperty("blue#") then 
		playerZone.blueNum = theZone:getStringFromZoneProperty("blue#", "none")
	end
	if theZone:hasProperty("neutral#") then 
		playerZone.neutralNum = theZone:getStringFromZoneProperty("neutral#", "none")
	end
	if theZone:hasProperty("total#") then 
		playerZone.totalNum = theZone:getStringFromZoneProperty("total#", "none")
	end
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