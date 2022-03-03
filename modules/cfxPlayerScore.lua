cfxPlayerScore = {}
cfxPlayerScore.version = "1.3.0"
cfxPlayerScore.badSound = "Death BRASS.wav"
cfxPlayerScore.scoreSound = "Quest Snare 3.wav"
cfxPlayerScore.announcer = true 
--[[-- VERSION HISTORY
    1.0.1 - bug fixes to killDetected 
	1.0.2 - messaging clean-up, less verbose 
	1.1.0 - integrated score base system
	      - accepts configZones 
		  - module validation 
		  - isNamedUnit(theUnit)
		  - notify if named unit killed 
		  - kill weapon reported 
	1.2.0 - score table 
		  - announcer attribute 
		  - badSound name 
		  - scoreSound name 
	1.3.0 - object2score 
		  - static objects also can score 
		  - can now also score members of group by adding group name 
		  - scenery objects are now supported. use the 
		    number that is given under OBJECT ID when 
			using assign as...
	
		  
--]]--
cfxPlayerScore.requiredLibs = {
	"dcsCommon", -- this is doing score keeping
	"cfxPlayer", -- player events, comms 
	"cfxZones", -- zones for config 
}
cfxPlayerScore.playerScore = {} -- init to empty

-- typeScore: dictionary sorted by typeString for score 
-- extend to add more types. It is used by unitType2score to 
-- determine the base unit score  
cfxPlayerScore.typeScore = {}
 
--
-- we subscribe to the kill event. each time a unit 
-- is killed, we check if it was killed by a player
-- and if so, that player record is updated and the side
-- whom the player belongs to is informed
--
cfxPlayerScore.aircraft = 50 
cfxPlayerScore.helo = 40 
cfxPlayer.ground = 10
cfxPlayerScore.ship = 80 
cfxPlayerScore.train = 5 

function cfxPlayerScore.cat2BaseScore(inCat)
	if inCat == 0 then return cfxPlayerScore.aircraft end -- airplane
	if inCat == 1 then return cfxPlayerScore.helo end -- helo 
	if inCat == 2 then return cfxPlayer.ground end -- ground 
	if inCat == 3 then return cfxPlayerScore.ship end -- ship 
	if inCat == 4 then return cfxPlayerScore.train end -- train 
	
	trigger.action.outText("+++scr c2bs: unknown category for lookup: <" .. inCat .. ">, returning 1", 30)
	
	return 1 
end

function cfxPlayerScore.object2score(inVictim) -- does not have group
	if not inVictim then return end 
	local inName = inVictim:getName()
	if not inName then return 0 end 
	if type(inName) == "number" then 
		inName = tostring(inName)
	end
		
	local objectScore = cfxPlayerScore.typeScore[inName]
	if not objectScore then 
		-- try the type desc 
		local theType = inVictim:getTypeName()
		objectScore = cfxPlayerScore.typeScore[theType]
	end
	
	if type(objectScore) == "string" then 
		objectScore = tonumber(objectScore)
	end
	if not objectScore then return 0 end 
	return objectScore 
end

function cfxPlayerScore.unit2score(inUnit)
	local vicGroup = inUnit:getGroup()
	local vicCat = vicGroup:getCategory()
	local vicType = inUnit:getTypeName()
	local vicName = inUnit:getName() 
	if type(vicName) == "number" then vicName = tostring(vicName) end 
	
	-- simply extend by adding items to the typescore table.concat
	-- we first try by unit name. This allows individual
	-- named hi-value targets to have individual scores 
	local uScore = cfxPlayerScore.typeScore[vicName]

	-- see if all members of group score 
	if not uScore then 
		local grpName = vicGroup:getName()
		uScore = cfxPlayerScore.typeScore[grpName]
	end
	
	if uScore == nil then 
		-- WE NOW TRY TO ACCESS BY VICTIM'S TYPE STRING		
		uScore = cfxPlayerScore.typeScore[vicType]
	else 

	end 
	if type(uScore) == "string" then 
		-- convert string to number 
		uScore = tonumber(uScore)
	end

	if uScore == nil then uScore = 0 end 
	if uScore > 0 then return uScore end 
	
	-- only apply base scores when the lookup did not give a result
	uScore = cfxPlayerScore.cat2BaseScore(vicCat)
	return uScore 
end

function cfxPlayerScore.getPlayerScore(playerName)
	local thePlayerScore = cfxPlayerScore.playerScore[playerName]
	if thePlayerScore == nil then 
		thePlayerScore = {}
		thePlayerScore.name = playerName
		thePlayerScore.score = 0 -- score
		thePlayerScore.killTypes = {} -- the type strings killed
		thePlayerScore.totalKills = 0 -- number of kills total 
	end
	return thePlayerScore
end

function cfxPlayerScore.setPlayerScore(playerName, thePlayerScore)
	cfxPlayerScore.playerScore[playerName] = thePlayerScore
end

function cfxPlayerScore.updateScoreForPlayer(playerName, score)
	local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)
	
	thePlayerScore.score = thePlayerScore.score + score
	cfxPlayerScore.setPlayerScore(playerName, thePlayerScore)
	return thePlayerScore.score 
end

function cfxPlayerScore.logKillForPlayer(playerName, theUnit)
	if not theUnit then return end
	if not playerName then return end 
	
	local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)
	
	local theType = theUnit:getTypeName()
	local killCount = thePlayerScore.killTypes[theType]
	if killCount == nil then 
		killCount = 0
	end
	killCount = killCount + 1
	thePlayerScore.totalKills = thePlayerScore.totalKills + 1
	thePlayerScore.killTypes[theType] = killCount
	
	cfxPlayerScore.setPlayerScore(playerName, thePlayerScore)
end

function cfxPlayerScore.playerScore2text(thePlayerScore)
	local desc = thePlayerScore.name .. " - score: ".. thePlayerScore.score .. " - kills: " .. thePlayerScore.totalKills .. "\n"
	-- now go through all killSide
	for theType, quantity in pairs(thePlayerScore.killTypes) do 
		desc = desc .. "  - " .. theType .. ": " .. quantity .. "\n"
	end
	return desc
end

function cfxPlayerScore.scoreTextForPlayerNamed(playerName)
	local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)
	return cfxPlayerScore.playerScore2text(thePlayerScore)
end

function cfxPlayerScore.isNamedUnit(theUnit) 
	if not theUnit then return false end 
	local theName = "(cfx_none)"
	if type(theUnit) == "string" then 
		theName = theUnit -- direct name assignment
		-- WARNING: NO EXIST CHECK DONE!
	else 
		-- after kill, unit is dead, so will no longer exist!
		theName = theUnit:getName() 
		if not theName then return false end 
	end
	if cfxPlayerScore.typeScore[theName] then 
		return true
	end
	return false 
end

function cfxPlayerScore.awardScoreTo(killSide, theScore, killerName)
	local playerScore = cfxPlayerScore.updateScoreForPlayer(killerName, theScore)
	
	if cfxPlayerScore.announcer then 
		trigger.action.outTextForCoalition(killSide, "Killscore:  " .. theScore .. " for a total of " .. playerScore .. " for " .. killerName, 30)
	end 
end
--
-- EVENT HANDLING
--
function cfxPlayerScore.preProcessor(theEvent)
	-- return true if the event should be processed
	-- by us
	
	if theEvent.id == 28 then
		-- we only are interested in kill events where 
		-- there is an initiator, and the initiator is 
		-- a player 
		if theEvent.initiator  == nil then 
			return false 
		end 
		
		local killer = theEvent.initiator 
		if theEvent.target == nil then 
			if cfxPlayerScore.verbose then 
				trigger.action.outText("+++scr pre: nil TARGET", 30) 
			end 
			return false 
		end 
		
		local wasPlayer = cfxPlayer.isPlayerUnit(killer)
		return wasPlayer
	end
	return false 
end

function cfxPlayerScore.postProcessor(theEvent)
	-- don't do anything
end

function cfxPlayerScore.killDetected(theEvent)
	-- we are only getting called when and if 
	-- a kill occured and killer was a player 
	-- and target exists
	
	local killer = theEvent.initiator
	local killerName = killer:getPlayerName()
	if not killerName then killerName = "<nil>" end
	local killSide = killer:getCoalition()
	local killVehicle = killer:getTypeName()
	if not killVehicle then killVehicle = "<nil>" end 
	local victim = theEvent.target

	-- was it a player kill?
	local pk = cfxPlayer.isPlayerUnit(victim)

	-- was it a scenery object? 
	local wasBuilding = dcsCommon.isSceneryObject(victim)
	if wasBuilding then 
		-- these objects have no coalition; we simply award the score if 
		-- it exists in look-up table. 
		local staticScore = cfxPlayerScore.object2score(victim)
		if staticScore > 0 then 
			trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.scoreSound)
			cfxPlayerScore.awardScoreTo(killSide, staticScore, killerName)
		end
		return 
	end

	-- was it fraternicide?
	local vicSide = victim:getCoalition()
	local fraternicide = killSide == vicSide
	local vicDesc = victim:getTypeName()
	local scoreMod = 1 -- start at one 

	-- see what kind of unit (category) we killed
    -- and look up base score 
	if not victim.getGroup then
		-- static objects have no group 

		local staticName = victim:getName() -- on statics, this returns 
		                                    -- name as entered in TOP LINE
		local staticScore = cfxPlayerScore.object2score(victim)
		if staticScore > 0 then 
			-- this was a named static, return the score - unless our own
			if fraternicide then 
				scoreMod = -2 * scoreMod 
				trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.badSound)
			else 
				trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.scoreSound)
			end
			staticScore = scoreMod * staticScore
			cfxPlayerScore.awardScoreTo(killSide, staticScore, killerName)
		else 
			-- no score, no mentions
		end
		
		return 
	end 
	
	local vicGroup = victim:getGroup()
	local vicCat = vicGroup:getCategory()
	local unitScore = cfxPlayerScore.unit2score(victim)

	-- see which weapon was used. gun kills score 2x 
	local killMeth = ""
	local killWeap = theEvent.weapon
	if killWeap then 
		local killWeapType = killWeap:getCategory()
		if killWeapType == 0 then 
			killMeth = " with GUNS" 
			scoreMod = scoreMod * 2
		else 
			local kWeapon = killWeap:getTypeName()
			killMeth = " with " .. kWeapon
		end
	else 
		
	end
	
	if pk then 
		vicDesc = victim:getPlayerName() .. " in " .. vicDesc 
		scoreMod = scoreMod * 10
	end 
	
	if fraternicide then
		scoreMod = scoreMod * -2
		if cfxPlayerScore.announcer then 
			trigger.action.outTextForCoalition(killSide, killerName .. " in " .. killVehicle .. " killed FRIENDLY " .. vicDesc .. killMeth .. "!", 30)
			trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.badSound)
		end 
	else 
		if cfxPlayerScore.announcer then 
			trigger.action.outText(killerName .. " in " .. killVehicle .." killed " .. vicDesc .. killMeth .."!", 30)
			trigger.action.outSoundForCoalition(vicSide, cfxPlayerScore.badSound)
			trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.scoreSound)
		 end 
		 -- since not fraticide, log this kill
		 -- logging kills does not impct score
		 cfxPlayerScore.logKillForPlayer(killerName, victim)
	end
	
	-- see if it was a named target 
	if cfxPlayerScore.isNamedUnit(victim) then 
		if cfxPlayerScore.announcer then 
			trigger.action.outTextForCoalition(killSide, killerName .. " reports killing strategic unit '" .. victim:getName() .. "'", 30)
		end 
	end
	
	local totalScore = unitScore * scoreMod
	cfxPlayerScore.awardScoreTo(killSide, totalScore, killerName)

end

function cfxPlayerScore.readConfigZone(theZone)
	cfxPlayerScore.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	-- default scores 
	cfxPlayerScore.aircraft = cfxZones.getNumberFromZoneProperty(theZone, "aircraft", 50) 
	cfxPlayerScore.helo = cfxZones.getNumberFromZoneProperty(theZone, "helo", 40)  
	cfxPlayer.ground = cfxZones.getNumberFromZoneProperty(theZone, "ground", 10)  
	cfxPlayerScore.ship = cfxZones.getNumberFromZoneProperty(theZone, "ship", 80)   
	cfxPlayerScore.train = cfxZones.getNumberFromZoneProperty(theZone, "train", 5)
	
	cfxPlayerScore.announcer = cfxZones.getBoolFromZoneProperty(theZone, "announcer", true)
	
	if cfxZones.hasProperty(theZone, "badSound") then 
		cfxReconMode.badSound = cfxZones.getStringFromZoneProperty(theZone, "badSound", "<nosound>")
	end
	if cfxZones.hasProperty(theZone, "scoreSound") then 
		cfxReconMode.scoreSound = cfxZones.getStringFromZoneProperty(theZone, "scoreSound", "<nosound>")
	end
end

function cfxPlayerScore.start()
	if not dcsCommon.libCheck("cfx Player Score", 
							  cfxPlayerScore.requiredLibs) 
	then 
		return false 
	end
	
	-- read my score table 
	-- identify and process a score table zones
	local theZone = cfxZones.getZoneByName("playerScoreTable") 
	if not theZone then 
		trigger.action.outText("+++scr: no score table!", 30) 
	else 
		-- read all into my types registry, replacing whatever is there
		cfxPlayerScore.typeScore = cfxZones.getAllZoneProperties(theZone)
		trigger.action.outText("+++scr: read score table", 30) 
	end 
	
	-- now read my config zone 
	local theZone = cfxZones.getZoneByName("playerScoreConfig") 
	if not theZone then 
		trigger.action.outText("+++scr: no config!", 30) 
	else 
		cfxPlayerScore.readConfigZone(theZone)
		trigger.action.outText("+++scr: read config", 30) 
	end 
	
	-- subscribe to events and use dcsCommon's handler structure
	dcsCommon.addEventHandler(cfxPlayerScore.killDetected,
							  cfxPlayerScore.preProcessor,
							  cfxPlayerScore.postProcessor)
	trigger.action.outText("cfxPlayerScore v" .. cfxPlayerScore.version .. " started", 30)
	return true 
end


if not cfxPlayerScore.start() then 
	trigger.action.outText("+++ aborted cfxPlayerScore v" .. cfxPlayerScore.version .. "  -- libcheck failed", 30)
	cfxPlayerScore = nil 
end

-- TODO: score mod for weapons type 
-- TODO: player kill score 
 