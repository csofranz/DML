cfxPlayerScore = {}
cfxPlayerScore.version = "1.5.1"
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
	1.3.1 - isStaticObject() to better detect buildings after Match 22 patch
	1.3.2 - corrected ground default score 
	      - removed dependency to cfxPlayer 
	1.4.0 - persistence support 
	      - better unit-->static switch support for generic type kill
	1.5.0 - added feats to score
	      - feats API 
		  - logFeatForPlayer(playerName, theFeat, coa)
	1.5.1 - init feats before reading 
		  
--]]--

cfxPlayerScore.requiredLibs = {
	"dcsCommon", -- this is doing score keeping
	"cfxZones", -- zones for config 
}
cfxPlayerScore.playerScore = {} -- init to empty
cfxPlayerScore.deferred = false -- on deferred, we only award after landing, and erase on any form of re-slot
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
cfxPlayerScore.ground = 10
cfxPlayerScore.ship = 80 
cfxPlayerScore.train = 5 


function cfxPlayerScore.cat2BaseScore(inCat)
	if inCat == 0 then return cfxPlayerScore.aircraft end -- airplane
	if inCat == 1 then return cfxPlayerScore.helo end -- helo 
	if inCat == 2 then return cfxPlayerScore.ground end -- ground 
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
	
	-- now, since 2.7x DCS turns units into static objects for 
	-- cooking off, so first thing we need to do is do a name check 
	
	local objectScore = cfxPlayerScore.typeScore[inName]
	if not objectScore then 
		-- try the type desc 
		local theType = inVictim:getTypeName()
		objectScore = cfxPlayerScore.typeScore[theType]
	end
	
	if type(objectScore) == "string" then 
		objectScore = tonumber(objectScore)
	end
	
	if objectScore then return objectScore end
	
	-- we now try and get the general type of the killed object
	local desc = inVictim:getDesc() -- Object.getDesc(inVictim)
	local attributes = desc.attributes 
	if attributes then 
		if attributes["Vehicles"] or attributes["Ground vehicles"] or attributes["Ground Units"] then return cfxPlayerScore.ground end 
		if attributes["Helicopters"] then return cfxPlayerScore.helo end
		if attributes["Planes"] then return cfxPlayerScore.aircraft end 
		if attributes["Ships"] then return cfxPlayerScore.ship end 
		-- trains can't be detected
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
		thePlayerScore.killTypes = {} -- the type strings killed, dict <typename> <numkilla>
		thePlayerScore.killQueue = {} -- when using deferred
		thePlayerScore.totalKills = 0 -- number of kills total 
		thePlayerScore.featTypes = {} -- dict <featname> <number> of other things player did 
		thePlayerScore.featQueue = {} -- when using deferred 
		thePlayerScore.totalFeats = 0		
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

function cfxPlayerScore.logFeatForPlayer(playerName, theFeat, coa)
	if not theFeat then return end
	if not playerName then return end 
	-- access player's record. will alloc if new by itself
	local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)
	if not thePlayerScore.featTypes then thePlayerScore.featTypes = {} end
	local featCount = thePlayerScore.featTypes[theFeat]
	if featCount == nil then 
		featCount = 0
	end
	featCount = featCount + 1
	thePlayerScore.totalFeats = thePlayerScore.totalFeats + 1
	thePlayerScore.featTypes[theFeat] = featCount
	
	if coa then 
		trigger.action.outTextForCoalition(coa, playerName .. " achieved " .. theFeat, 30)
		trigger.action.outSoundForCoalition(coa, cfxPlayerScore.scoreSound)
	end
	cfxPlayerScore.setPlayerScore(playerName, thePlayerScore)
end

function cfxPlayerScore.playerScore2text(thePlayerScore)
	local desc = thePlayerScore.name .. " - score: ".. thePlayerScore.score .. " - kills: " .. thePlayerScore.totalKills .. "\n"
	-- now go through all killSide
	if dcsCommon.getSizeOfTable(thePlayerScore.killTypes)  < 1 then 
		desc = desc .. "    - NONE -\n"
	end
	for theType, quantity in pairs(thePlayerScore.killTypes) do 
		desc = desc .. "  - " .. theType .. ": " .. quantity .. "\n"
	end
	
	-- now enumerate all feats
	if not thePlayerScore.featTypes then thePlayerScore.featTypes = {} end
	
	desc = desc .. "\nOther Accomplishments:\n"
	if dcsCommon.getSizeOfTable(thePlayerScore.featTypes) < 1 then 
		desc = desc .. "    - NONE -\n"
	end
	for theFeat, quantity in pairs(thePlayerScore.featTypes) do 
		desc = desc .. "  - " .. theFeat
		if quantity > 1 then 
			desc = desc .. " (x" .. quantity .. ")"
		end 
		desc = desc .. "\n"
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
		
		local wasPlayer = dcsCommon.isPlayerUnit(killer)
		return wasPlayer
	end
	return false 
end

function cfxPlayerScore.postProcessor(theEvent)
	-- don't do anything
end

function cfxPlayerScore.isStaticObject(theUnit) 
	if not theUnit.getGroup then return true end 
	local aGroup = theUnit:getGroup()
	if aGroup then return false end 
	return true 
end

function cfxPlayerScore.killDetected(theEvent)
	-- we are only getting called when and if 
	-- a kill occured and killer was a player 
	-- and target exists
--	trigger.action.outText("KILL EVENT", 30)
	local killer = theEvent.initiator
	local killerName = killer:getPlayerName()
	if not killerName then killerName = "<nil>" end
	local killSide = killer:getCoalition()
	local killVehicle = killer:getTypeName()
	if not killVehicle then killVehicle = "<nil>" end 
	local victim = theEvent.target

	-- was it a player kill?
	local pk = dcsCommon.isPlayerUnit(victim)

	-- was it a scenery object? 
	local wasBuilding = dcsCommon.isSceneryObject(victim)
	if wasBuilding then 
		-- these objects have no coalition; we simply award the score if 
		-- it exists in look-up table. 
		--trigger.action.outText("KILL SCENERY", 30)
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
	local isStO = cfxPlayerScore.isStaticObject(victim) 
	--if not victim.getGroup then
	if isStO then 
		-- static objects have no group 
		
		local staticName = victim:getName() -- on statics, this returns 
		                                    -- name as entered in TOP LINE
		local staticScore = cfxPlayerScore.object2score(victim)
--		trigger.action.outText("KILL STATIC with score " .. staticScore, 30)
		if staticScore > 0 then 
			-- this was a named static, return the score - unless our own
			if fraternicide then 
				scoreMod = -1 * scoreMod -- blue on blue static kills award negative
				trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.badSound)
			else 
				trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.scoreSound)
			end
			staticScore = scoreMod * staticScore
			cfxPlayerScore.logKillForPlayer(killerName, victim)
			cfxPlayerScore.awardScoreTo(killSide, staticScore, killerName)
		else 
			-- no score, no mentions
		end
		
		return 
	end 
	
	local vicGroup = victim:getGroup()
	if not vicGroup then 
		trigger.action.outText("+++scr: strange stuff:group, outta here", 30)
		return 
	end 
	local vicCat = vicGroup:getCategory()
		if not vicCat then 
		trigger.action.outText("+++scr: strange stuff:cat, outta here", 30)
		return 
	end
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
	cfxPlayerScore.ground = cfxZones.getNumberFromZoneProperty(theZone, "ground", 10)  
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

--
-- load / save 
--
function cfxPlayerScore.saveData()
	local theData = {}
	local theScore = dcsCommon.clone(cfxPlayerScore.playerScore)
	theData.theScore = theScore
	return theData
end

function cfxPlayerScore.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("cfxPlayerScore")
	if not theData then 
		if cfxPlayerScore.verbose then 
			trigger.action.outText("+++playerscore: no save date received, skipping.", 30)
		end
		return
	end
	
	local theScore = theData.theScore
	cfxPlayerScore.playerScore = theScore 
	
end


--
-- start
--

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
							  
	-- now load all save data and populate map with troops that
	-- we deployed last save. 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = cfxPlayerScore.saveData
		persistence.registerModule("cfxPlayerScore", callbacks)
		-- now load my data 
		cfxPlayerScore.loadData()
	end
							  
	trigger.action.outText("cfxPlayerScore v" .. cfxPlayerScore.version .. " started", 30)
	return true 
end


if not cfxPlayerScore.start() then 
	trigger.action.outText("+++ aborted cfxPlayerScore v" .. cfxPlayerScore.version .. "  -- libcheck failed", 30)
	cfxPlayerScore = nil 
end

-- TODO: score mod for weapons type 
-- TODO: player kill score 
 