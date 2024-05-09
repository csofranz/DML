cfxPlayerScore = {}
cfxPlayerScore.version = "3.2.0"
cfxPlayerScore.name = "cfxPlayerScore" -- compatibility with flag bangers
cfxPlayerScore.badSound = "Death BRASS.wav"
cfxPlayerScore.scoreSound = "Quest Snare 3.wav"
cfxPlayerScore.announcer = true 
cfxPlayerScore.firstSave = true -- to force overwrite 
--[[-- VERSION HISTORY
	3.0.0 - dmlFlags OOP
		  - redScore#
		  - blueScore#
		  - sceneryObject detection improvements 
		  - DCS 2.9 safe 
	3.0.1 - cleanup
	3.0.2 - interface with ObjectDestructDetector for scoring scenery objects
	3.1.0 - shared data for persistence
	3.2.0 - integration with bank 
--]]--

cfxPlayerScore.requiredLibs = {
	"dcsCommon", -- this is doing score keeping
	"cfxZones", -- zones for config 
}
cfxPlayerScore.playerScore = {} -- indexed by playerName
cfxPlayerScore.coalitionScore = {} -- score per coalition
cfxPlayerScore.coalitionScore[1] = 0 -- init red
cfxPlayerScore.coalitionScore[2] = 0 -- init blue
cfxPlayerScore.deferred = false -- on deferred, we only award after landing, and erase on any form of re-slot
cfxPlayerScore.delayAfterLanding = 10 -- seconds after landing 
cfxPlayerScore.safeZones = {} -- safe zones to land in  
cfxPlayerScore.featZones = {} -- zones that define feats 
cfxPlayerScore.killZones = {} -- when set, kills only count here 

-- typeScore: dictionary sorted by typeString for score 
-- extend to add more types. It is used by unitType2score to 
-- determine the base unit score  
cfxPlayerScore.typeScore = {}
cfxPlayerScore.lastPlayerLanding = {} -- timestamp, by player name  
cfxPlayerScore.delayBetweenLandings = 30 -- seconds to count as separate landings, also set during take-off to prevent janky t/o to count. 
cfxPlayerScore.aircraft = 50 
cfxPlayerScore.helo = 40 
cfxPlayerScore.ground = 10
cfxPlayerScore.ship = 80 
cfxPlayerScore.train = 5 
cfxPlayerScore.landing = 0 -- if > 0 it scores as feat

cfxPlayerScore.unit2player = {} -- lookup and reverse look-up 

function cfxPlayerScore.addSafeZone(theZone)
	theZone.scoreSafe = theZone:getCoalitionFromZoneProperty("scoreSafe", 0)
	table.insert(cfxPlayerScore.safeZones, theZone)
end

function cfxPlayerScore.addKillZone(theZone)
	theZone.killZone = theZone:getCoalitionFromZoneProperty("killZone", 0) -- value currently ignored 
	theZone.duet = theZone:getBoolFromZoneProperty("duet", false) -- does killer have to be in zone? 
	table.insert(cfxPlayerScore.killZones, theZone)
end

function cfxPlayerScore.addFeatZone(theZone)
	theZone.coalition = theZone:getCoalitionFromZoneProperty("feat", 0) -- who can earn, 0 for all sides 
	theZone.featType = theZone:getStringFromZoneProperty("featType", "kill")
	theZone.featType = string.upper(theZone.featType)
	if theZone.featType == "LAND" then theZone.featType = "LANDING" end 
	if theZone.featType ~= "KILL" and 
	   theZone.featType ~= "LANDING" and 
	   theZone.featType ~= "PVP"
	then
		theZone.featType = "KILL"
	end	
	theZone.featDesc = theZone:getStringFromZoneProperty("description", "(some feat)")
	theZone.featNum = ctheZone:getNumberFromZoneProperty("awardLimit", -1) -- how many times this can be awarded, -1 is infinite 
	theZone.ppOnce = theZone:getBoolFromZoneProperty("awardOnce", false)
	theZone.awardedTo = {} -- by player name: true/false 
	table.insert(cfxPlayerScore.featZones, theZone)
	if cfxPlayerScore.verbose or theZone.verbose then 
		trigger.action.outText("+++ feat zone <" .. theZone.name .. "> read: [" .. theZone.featDesc .. "] for <" .. theZone.featType .. ">", 30)
	end 
end

function cfxPlayerScore.getFeatByName(name)
	for idx, theZone in pairs(cfxPlayerScore.featZones) do 
		if name == theZone.name then return theZone end 
	end
	return nil 
end

function cfxPlayerScore.featsForLocation(name, loc, coa, featType, killer, victim)
	if not loc then return {} end 
	-- loc is location of landing unit for landing 
	-- and location of victim for kill 
	-- coa is coalition of landing unit 
	-- and coalition of killer for kill 

	if not coa then coa = 0 end 
	if not featType then featType = "KILL" end 
	featType = string.upper(featType)
	local theFeats = {}
	for idx, theZone in pairs(cfxPlayerScore.featZones) do 
		local canAward = true 
				   
		-- check if it can be awarded 
		if theZone.featNum == 0 then 
			canAward = false 
		end 
		
		if theZone.featType ~= featType then 
			canAward = false
		end
		
		if not (theZone.coalition == 0 or theZone.coalition == coa) then 
			canAward = false 
		end			
		
		if featType == "PVP" then 
			-- make sure kill is pvp kill 
			if not victim then canAward = false 
			elseif not victim.getPlayerName then 
				canAward = false 
			elseif not victim:getPlayerName() then
				canAward = false 
			end
		end
		
		if not cfxZones.pointInZone(loc, theZone) then 
			canAward = false 
		end
		
		if theZone.ppOnce then 
			if theZone.awardedTo[name] then 
				canAward = false
			end
		end
		
		if canAward then 
			table.insert(theFeats, theZone) -- jupp, add it
		else 
		end 

	end
	return theFeats
end

function cfxPlayerScore.preprocessWildcards(inMsg, aUnit, aVictim)
	local theMsg = inMsg
	if not aVictim then aVictim = aUnit end 
	local pName = "Unknown"
	if aUnit then 
		if aUnit.getPlayerName then 
			pN = aUnit:getPlayerName()
			if pN then pName = pN end 
		end
		theMsg = theMsg:gsub("<punit>", aUnit:getName())
		theMsg = theMsg:gsub("<ptype>", aUnit:getTypeName())
		theMsg = theMsg:gsub("<pgroup>", aUnit:getGroup():getName())
	end
	theMsg = theMsg:gsub("<player>", pName)
	if aVictim then 
		-- if player killed, get killed player's name else use unknown AI
		if aVictim.getPlayerName then 
			pkName = aVictim:getPlayerName()
			if pkName then 
				theMsg = theMsg:gsub("<kplayer>", pkName)
			else 
				theMsg = theMsg:gsub("<kplayer>", "unknown AI")
			end
		end
		theMsg = theMsg:gsub("<unit>", aVictim:getName())
		theMsg = theMsg:gsub("<type>", aVictim:getTypeName())
		-- victim may not have group. guard against that 
		-- happens if unit 'cooks off'
		local aGroup = nil 
		if aVictim.getGroup then 
			aVictim:getGroup()
		end 
		if aGroup and aGroup.getName then 
			theMsg = theMsg:gsub("<group>", aGroup:getName())
		else 
			theMsg = theMsg:gsub("<group>", "(Unknown)")
		end 
	end 
	return theMsg
end

function cfxPlayerScore.evalFeatDescription(name, theZone, playerUnit, victim) 
	local msg = theZone.featDesc 
	if not victim then victim = playerUnit end 
	-- eval wildcards 
	msg = cfxPlayerScore.preprocessWildcards(msg, playerUnit, victim)
	msg = cfxZones.processStringWildcards(msg, theZone) -- nil time format, nil imperial, nil responses
		
	-- update featNum since it's been 'used' 
	if theZone.featNum > 0 then 
		theZone.featNum = theZone.featNum -1 
	end
	-- mark this feat awarded to player, only relevant for ppOnce 
	theZone.awardedTo[name] = true 
	return msg 
end

function cfxPlayerScore.cat2BaseScore(inCat)
	if inCat == 0 then return cfxPlayerScore.aircraft end -- airplane
	if inCat == 1 then return cfxPlayerScore.helo end -- helo 
	if inCat == 2 then return cfxPlayerScore.ground end -- ground 
	if inCat == 3 then return cfxPlayerScore.ship end -- ship 
	if inCat == 4 then return cfxPlayerScore.train end -- train 
	
	trigger.action.outText("+++scr c2bs: unknown category for lookup: <" .. inCat .. ">, returning 1", 30)
	
	return 1 
end

function cfxPlayerScore.object2score(inVictim, killSide) -- does not have group
	if not inVictim then return 0 end
	if not killSide then killSide = -1 end 
	local inName = inVictim:getName()
	if dcsCommon.isSceneryObject(inVictim) then 
		local desc = inVictim:getDesc() 
		if not desc then return 0 end 
		-- same as object destruct detector to 
		-- avoid ID changes 
		inName = desc.typeName 
		if cfxObjectDestructDetector then 
			-- ask ODD if it knows the object and what score was 
			-- awarded for a kill from that side 
			local objectScore = cfxObjectDestructDetector.playerScoreForKill(inVictim, killSide)
			if objectScore then return objectScore end 
		end
	end
	if not inName then return 0 end 
	if type(inName) == "number" then 
		inName = tostring(inName)
	end
	
	-- since 2.7x DCS turns units into static objects for 
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
	local vicCat = vicGroup:getCategory()-- group cat, not 2.9 affected
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
		thePlayerScore.scoreaccu = 0 -- for deferred 
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

-- will never defer 
function cfxPlayerScore.updateScoreForPlayerImmediate(playerName, score)
	local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)
	thePlayerScore.score = thePlayerScore.score + score
	cfxPlayerScore.setPlayerScore(playerName, thePlayerScore)
	-- if coalitionScore is active, trace player back to their current 
	-- coalition and add points to that coalition if positive 
	-- or always if noGrief is true 
	local pFaction = dcsCommon.playerName2Coalition(playerName)
	if cfxPlayerScore.noGrief then  
		-- only on positive score
		if (score > 0) and pFaction > 0 then 
			cfxPlayerScore.coalitionScore[pFaction] = cfxPlayerScore.coalitionScore[pFaction] + score 
			if bank and bank.addFunds then 
				bank.addFunds(pFaction, cfxPlayerScore.score2finance * score)
			end
		end
	else 
		if pFaction > 0 then 
			cfxPlayerScore.coalitionScore[pFaction] = cfxPlayerScore.coalitionScore[pFaction] + score 
			if bank and bank.addFunds then 
				bank.addFunds(pFaction, cfxPlayerScore.score2finance * score)
			end		
		end
	end
	return thePlayerScore.score 
end

function cfxPlayerScore.updateScoreForPlayer(playerName, score)
	-- main update score 
	if cfxPlayerScore.deferred then -- just queue it
		local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName) 
		thePlayerScore.scoreaccu = thePlayerScore.scoreaccu + score
		cfxPlayerScore.setPlayerScore(playerName, thePlayerScore) -- write-through. why? because it may be a new entry.
		return thePlayerScore.score -- this is the old score!!! 
	end
	-- now write immediately 
	return cfxPlayerScore.updateScoreForPlayerImmediate(playerName, score)
end

function cfxPlayerScore.doLogTypeKill(playerName, thePlayerScore, theType)
	local killCount = thePlayerScore.killTypes[theType]	
	if killCount == nil then 
		killCount = 0
	end
	killCount = killCount + 1
	thePlayerScore.totalKills = thePlayerScore.totalKills + 1
	thePlayerScore.killTypes[theType] = killCount
	
	cfxPlayerScore.setPlayerScore(playerName, thePlayerScore)
end 

function cfxPlayerScore.logKillForPlayer(playerName, theUnit)
	-- main kill type /total count logging, can be deferred 
	-- no score change here 
	if not theUnit then return end
	if not playerName then return end 
	local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)	
	local theType = theUnit:getTypeName()
	
	if cfxPlayerScore.deferred then 
		-- just queue it 
		table.insert(thePlayerScore.killQueue, theType)
		cfxPlayerScore.setPlayerScore(playerName, thePlayerScore) -- write-through. why? because it may be a new entry.
		return 
	end
	
	cfxPlayerScore.doLogTypeKill(playerName, thePlayerScore, theType)
end

function cfxPlayerScore.doLogFeat(playerName, thePlayerScore, theFeat)
	if not thePlayerScore.featTypes then thePlayerScore.featTypes = {} end
	local featCount = thePlayerScore.featTypes[theFeat]
	if featCount == nil then 
		featCount = 0
	end
	featCount = featCount + 1
	thePlayerScore.totalFeats = thePlayerScore.totalFeats + 1
	thePlayerScore.featTypes[theFeat] = featCount
	
	cfxPlayerScore.setPlayerScore(playerName, thePlayerScore)

end

function cfxPlayerScore.logFeatForPlayer(playerName, theFeat, coa)
	-- usually called externally with theFeat being a string. no 
	-- scoring is passed 
	if not theFeat then return end
	if not playerName then return end 
	-- access player's record. will alloc if new by itself

	if coa then 
		local disclaim = ""
		if cfxPlayerScore.deferred then disclaim = " (award pending)" end 
		trigger.action.outTextForCoalition(coa, playerName .. " achieved " .. theFeat .. disclaim, 30)
		trigger.action.outSoundForCoalition(coa, cfxPlayerScore.scoreSound)
	end
	
	local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)
	if cfxPlayerScore.deferred then 
		table.insert(thePlayerScore.featQueue, theFeat)
		cfxPlayerScore.setPlayerScore(playerName, thePlayerScore)
		return 
	end
	
	cfxPlayerScore.doLogFeat(playerName, thePlayerScore, theFeat)
end

function cfxPlayerScore.playerScore2text(thePlayerScore, scoreOnly)
	if not scoreOnly then scoreOnly = false end 
	local desc = thePlayerScore.name .. " statistics:\n"

	if cfxPlayerScore.reportScore then 	
		desc = desc .. " - score: ".. thePlayerScore.score .. " - total kills: " .. thePlayerScore.totalKills .. "\n"
		if scoreOnly then 
			return desc 
		end 
		
		-- now go through all kills
		desc = desc .. "\nKills by type:\n"
		if dcsCommon.getSizeOfTable(thePlayerScore.killTypes)  < 1 then 
			desc = desc .. "    - NONE -\n"
		end
		for theType, quantity in pairs(thePlayerScore.killTypes) do 
			desc = desc .. "  - " .. theType .. ": " .. quantity .. "\n"
		end
	end 
	
	-- now enumerate all feats
	if not thePlayerScore.featTypes then thePlayerScore.featTypes = {} end
	if cfxPlayerScore.reportFeats then 
		desc = desc .. "\n Accomplishments:\n"
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
	end 
	
	if cfxPlayerScore.reportScore and thePlayerScore.scoreaccu > 0 then 
		desc = desc .. "\n - unclaimed score: " .. thePlayerScore.scoreaccu .."\n"
	end
	
	local featCount = dcsCommon.getSizeOfTable(thePlayerScore.featQueue)
	if cfxPlayerScore.reportFeats and featCount > 0 then 
		desc = desc .. " - unclaimed feats: " .. featCount .."\n"
	end
	
	return desc
end

function cfxPlayerScore.scoreTextForPlayerNamed(playerName)
	local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)
	return cfxPlayerScore.playerScore2text(thePlayerScore)
end

function cfxPlayerScore.scoreSummaryForPlayersOfCoalition(side)
	-- only list players who are in the coalition RIGHT NOW
	-- only list their score 
	if not side then side = -1 end 
	local desc = "\nCurrent score for players in " .. dcsCommon.coalition2Text(side) .." coalition:\n"
	local count = 0 
	for pName, pScore in pairs(cfxPlayerScore.playerScore) do 
		local coa = dcsCommon.playerName2Coalition(pName)
		if coa == side then 
			desc = desc .. pName ..": " .. pScore.score .. "\n"
			count = count + 1
		end
	end
	if count < 1 then 
		desc = desc .. "  (No score yet)"
	end
	
	desc = desc .. "\n"
	return desc
end

function cfxPlayerScore.scoreTextForAllPlayers(ranked) 
	if not ranked then ranked = false end 
	local theText = ""
	local isFirst = true 
	local theScores = cfxPlayerScore.playerScore
	if cfxPlayerScore.verbose then 
		trigger.action.outText("+++pScr: Generating score - <" .. dcsCommon.getSizeOfTable(theScores) .. "> entries.", 30)
	end 
	if ranked then 
		table.sort(theScores, function(left, right) return left.score < right.score end )
	end
	local rank = 1
	for name, score in pairs(theScores) do 
		if not isFirst then 
			theText = theText .. "\n"
		end
		if ranked then 
			if rank < 10 then theText = theText .. " " end
			theText = theText .. rank .. ". "
		end
		theText = theText .. cfxPlayerScore.playerScore2text(score, cfxPlayerScore.scoreOnly)  
		isFirst = false
		rank = rank + 1
	end
	
	if dcsCommon.getSizeOfTable(theScores) < 1 then 
		theText = theText .. "  (No score yet)\n"
	end
	
	if cfxPlayerScore.reportCoalition then 
		--theText = theText .. "\n"
		theText = theText .. "\nRED  total: " .. cfxPlayerScore.coalitionScore[1]
		theText = theText .. "\nBLUE total: " .. cfxPlayerScore.coalitionScore[2]
	end
	
	return theText
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
	local playerScore 
	if theScore < 0 then 
		playerScore = cfxPlayerScore.updateScoreForPlayerImmediate(killerName, theScore)
	else 
		playerScore = cfxPlayerScore.updateScoreForPlayer(killerName, theScore)
	end
	
	if not cfxPlayerScore.reportScore then return end 
	
	if cfxPlayerScore.announcer then
		if (theScore > 0) and cfxPlayerScore.deferred then 
			thePlayerRecord = cfxPlayerScore.getPlayerScore(killerName) -- re-read after write
			trigger.action.outTextForCoalition(killSide, "Killscore:  " .. theScore .. ", now " .. thePlayerRecord.scoreaccu .. " waiting for " .. killerName .. ", awarded after landing", 30)
		else -- negative score or not deferred 
			trigger.action.outTextForCoalition(killSide, "Killscore:  " .. theScore .. " for a total of " .. playerScore .. " for " .. killerName, 30)
			
			if cfxPlayerScore.reportCoalition then 
				trigger.action.outTextForCoalition(killSide, "\nCoalition Total:  " .. cfxPlayerScore.coalitionScore[killSide], 30)
			end 
		end
	end 
end

--
-- EVENT HANDLING
--
function cfxPlayerScore.linkUnitWithPlayer(theUnit)
	-- create the entries for lookup and reverseLooup tables
	local uName = theUnit:getName()
	local pName = theUnit:getPlayerName()
	cfxPlayerScore.unit2player[uName] = pName 
end

function cfxPlayerScore.unlinkUnit(theUnit)
	local uName = theUnit:getName()
	cfxPlayerScore.unit2player[uName] = nil 	
end

function cfxPlayerScore.preProcessor(theEvent)
	-- return true if the event should be processed
	-- by us
	if theEvent.initiator  == nil then 
		return false 
	end 

	-- check if this was FORMERLY a player plane 
	local theUnit = theEvent.initiator 
	local uName = theUnit:getName()
	if cfxPlayerScore.unit2player[uName] then 
		-- this requires special IMMEDIATE handling when event is
		-- one of the below 		
		if theEvent.id == 5 or -- crash 
		   theEvent.id == 8 or -- dead 
	       theEvent.id == 9 or -- pilot_dead
		   theEvent.id == 30 or -- unit loss 
	       theEvent.id == 6 then -- eject 
			-- these can lead to a pilot demerit
			--trigger.action.outText("PREPROC plane player extra event - possible death", 30)
			-- event does NOT have a player
			cfxPlayerScore.handlePlayerDeath(theEvent)
			return false 
	    end 
	end
	
	-- initiator must be player 
	if not theUnit.getPlayerName or  
	   not theUnit:getPlayerName() then 
	   return false 
	end 
	
	if theEvent.id == 28 then
		-- we only are interested in kill events where 
		-- there is a target  
		local killer = theEvent.initiator 
		if theEvent.target == nil then 
			if cfxPlayerScore.verbose then 
				trigger.action.outText("+++scr pre: nil TARGET", 30) 
			end 
			return false 
		end 
		
		-- if there are kill zones, we filter all kills that happen outside of kill zones 
		if #cfxPlayerScore.killZones > 0 then
			local pLoc = theUnit:getPoint() 
			local tLoc = theEvent.target:getPoint()
			local isIn, percent, dist, theZone = cfxZones.pointInOneOfZones(tLoc, cfxPlayerScore.killZones)
		
			if not isIn then 
				if cfxPlayerScore.verbose then 
					trigger.action.outText("+++pScr: kill detected, but target <" .. theEvent.target:getName() .. "> was outside of any kill zones", 30)
				end
				return false 
			end
		
			if theZone.duet and not cfxZones.pointInZone(pLoc, theZone) then 
				-- player must be in same zone but was not
				if cfxPlayerScore.verbose then 
					trigger.action.outText("+++pScr: kill detected, but player <" .. theUnit:getPlayerName() .. "> was outside of kill zone <" .. theZone.name .. ">", 30)
				end
				return false
			end			
		end
		return true 
	end
	
	-- birth event for players initializes score if 
	-- not existed, and nils the queue 
	if theEvent.id == 15 then 
		-- player birth
		-- link player and unit
		cfxPlayerScore.linkUnitWithPlayer(theUnit)
		return true 
	end
	
	-- take off. overwrites timestamp for last landing 
	-- so a blipping t/o does nor count. Pre-proc only 
	if theEvent.id == 3 then 
		local now = timer.getTime()
		local playerName = theUnit:getPlayerName() 
		cfxPlayerScore.lastPlayerLanding[playerName] = now -- overwrite 
		return false 
	end
	
	-- landing can score. but only the first landing in x seconds
	-- landing in safe zone promotes any queued scores to 
	-- permanent if enabled, then nils queue
	if theEvent.id == 4 then 
		-- player landed. filter multiple landed events
		local now = timer.getTime()
		local playerName = theUnit:getPlayerName() 
		local lastLanding = cfxPlayerScore.lastPlayerLanding[playerName]
		cfxPlayerScore.lastPlayerLanding[playerName] = now -- overwrite 
		if lastLanding and lastLanding + cfxPlayerScore.delayBetweenLandings > now then 
			if cfxPlayerScore.verbose then 
				trigger.action.outText("+++pScr: Player <" .. playerName .. "> touch-down ignored: too soon.", 30)
				trigger.action.outText("now is <" .. now .. ">, between is <" .. cfxPlayerScore.delayBetweenLandings .. ">, last + between is <" .. lastLanding + cfxPlayerScore.delayBetweenLandings .. ">", 30)
			end 
			-- filter this event 
			return false 
		end
		return true 
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

function cfxPlayerScore.checkKillFeat(name, killer, victim, fratricide)
	if not fratricide then fratricide = false end 
	local theLoc = victim:getPoint() -- vic's loc is relevant for zone check
	local coa = killer:getCoalition() 
	
	local killFeats = cfxPlayerScore.featsForLocation(name, theLoc, coa,"KILL", killer, victim)
	
	if (not fratricide) and #killFeats > 0 then 
		-- use the feat description
		-- we may want to use closest, currently simply the first 
		theFeatZone = killFeats[1]
		local desc = cfxPlayerScore.evalFeatDescription(name, theFeatZone, killer, victim)  -- updates awardedTo
					
		cfxPlayerScore.logFeatForPlayer(name, desc, playerSide)
		theScore = cfxPlayerScore.getPlayerScore(name) -- re-read after write
		
		if cfxPlayerScore.verbose then 
			trigger.action.outText("Kill feat awarded/queued for <" .. name .. ">", 30)
		end
	end

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
	local pk = dcsCommon.isPlayerUnit(victim)

	-- was it a scenery object? 
	local wasBuilding = dcsCommon.isSceneryObject(victim)
	if wasBuilding then 
		-- these objects have no coalition; we simply award the score if 
		-- it exists in look-up table. 
		local staticScore = cfxPlayerScore.object2score(victim, killSide)
		if staticScore > 0 then 
			trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.scoreSound)
			cfxPlayerScore.awardScoreTo(killSide, staticScore, killerName)
			cfxPlayerScore.checkKillFeat(killerName, killer, victim, false)
		end
		return 
	end

	-- was it fratricide?
	-- if we get here, it CANT be a scenery object 
	-- but can be a static object, and stO have a coalition
	local vicSide = victim:getCoalition()
	local fraternicide = (killSide == vicSide)
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
		local staticScore = cfxPlayerScore.object2score(victim, killSide)

		if staticScore > 0 then 
			-- this was a named static, return the score - unless our own
			if fraternicide then 
				scoreMod = cfxPlayerScore.ffMod * scoreMod -- blue on blue static kill
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
		
		if not fraternicide then 
			cfxPlayerScore.checkKillFeat(killerName, killer, victim, false)
		end 		
		return 
	end 
	
	local vicGroup = victim:getGroup()
	if not vicGroup then 
		trigger.action.outText("+++scr: strange stuff:group, outta here", 30)
		return 
	end 
	local vicCat = vicGroup:getCategory() -- group cat is DCS 2.9 safe
		if not vicCat then 
		trigger.action.outText("+++scr: strange stuff:cat, outta here", 30)
		return 
	end
	local unitScore = cfxPlayerScore.unit2score(victim)

	-- see which weapon was used. gun kills score 2x 
--	local killMeth = "" -- meth is currently not defined 
--	local killWeap = theEvent.weapon -- not supported either
	
	if pk then -- player kill - add player's name 
		vicDesc = victim:getPlayerName() .. " in " .. vicDesc 
		scoreMod = scoreMod * cfxPlayerScore.pkMod
	end 
	
	-- if fratricide, times ffMod (friedlyFire) 
	if fraternicide then
		scoreMod = scoreMod * cfxPlayerScore.ffMod ---2
		if cfxPlayerScore.announcer then 
			trigger.action.outTextForCoalition(killSide, killerName .. " in " .. killVehicle .. " killed FRIENDLY " .. vicDesc .. "!", 30)
			trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.badSound)
		end 
	else 
		if cfxPlayerScore.announcer then 
			trigger.action.outText(killerName .. " in " .. killVehicle .." killed " .. vicDesc .. "!", 30)
			trigger.action.outSoundForCoalition(vicSide, cfxPlayerScore.badSound)
			trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.scoreSound)
		 end 
		 -- since not fraticide, log this kill
		 -- logging kills does not impact score
		 cfxPlayerScore.logKillForPlayer(killerName, victim)
	end
	
	-- see if it was a named target 
	if cfxPlayerScore.isNamedUnit(victim) then 
		if cfxPlayerScore.announcer then 
			trigger.action.outTextForCoalition(killSide, killerName .. " reports killing strategic unit '" .. victim:getName() .. "'", 30)
		end 
	end
	
	local totalScore = unitScore * scoreMod
	-- if the score is negative, awardScoreTo will automatically
	-- make it immediate, else depending on deferred 
	cfxPlayerScore.awardScoreTo(killSide, totalScore, killerName)

	if not fraternicide then 
		-- only award kill feats for kills of the enemy
		cfxPlayerScore.checkKillFeat(killerName, killer, victim, false)
	end 

end

function cfxPlayerScore.handlePlayerLanding(theEvent)
	local thePlayerUnit = theEvent.initiator
	local theLoc = thePlayerUnit:getPoint() 	
	local playerSide = thePlayerUnit:getCoalition()
	local playerName = thePlayerUnit:getPlayerName()
	if cfxPlayerScore.verbose then 
		trigger.action.outText("+++pScr: Player <" .. playerName .. "> landed", 30)
	end
	
	local theScore = cfxPlayerScore.getPlayerScore(playerName)
	
	-- see if a feat is available for this landing 
	local landingFeats = cfxPlayerScore.featsForLocation(playerName, theLoc, playerSide,"LANDING")
	
	-- first, scheck if landing is awardable, and if so, 
	-- award the landing 
	if cfxPlayerScore.landing > 0 or #landingFeats > 0 then 
		-- yes, landings are awarded a score. do before 
		-- resolving any queues 
		desc = "Landed"
		if #landingFeats > 0 then 
			-- use the feat description
			-- we may want to use closest, currently simply the first 
			theFeatZone = landingFeats[1]
			desc = cfxPlayerScore.evalFeatDescription(playerName, theFeatZone, thePlayerUnit) -- nil victim, defaults to player 
		else 
			if theEvent.place then 
				desc = desc .. " successfully (" .. theEvent.place:getName() .. ")"
			else 
				desc = desc .. " aircraft"
			end
		end 
		
		cfxPlayerScore.updateScoreForPlayer(playerName, cfxPlayerScore.landing)
		cfxPlayerScore.logFeatForPlayer(playerName, desc, playerSide)
		theScore = cfxPlayerScore.getPlayerScore(playerName) -- re-read after write
		if cfxPlayerScore.verbose then 
			trigger.action.outText("Landing feat awarded/queued for <" .. playerName .. ">", 30)
		end
	end
	
	-- see if we are using deferred scoring, else can end right now 
	if not cfxPlayerScore.deferred then 
		return 
	end
	-- only continue if there is anything to award 
	local killSize = dcsCommon.getSizeOfTable(theScore.killQueue)
	local featSize = dcsCommon.getSizeOfTable(theScore.featQueue)
	
	if cfxPlayerScore.verbose then 
		trigger.action.outText("+++pScr: prepping deferred score for <" .. playerName ..">", 30)
	end
	
	-- see if player landed in a scoreSafe zone 
	local theUnit = thePlayerUnit
	local loc = theUnit:getPoint()
	local uid = theUnit:getID()
	local coa = theUnit:getCoalition()
	local isSafe = false 
	for idx, theZone in pairs(cfxPlayerScore.safeZones) do 
		if theZone.scoreSafe == 0 or theZone.scoreSafe == coa then 
			-- make sure that this zone doesn't belong to the 
			-- wrong faction (if owned zone) 
			if (theZone.owner == coa) or (theZone.owner == 0) or (theZone.owner == nil) then 
				if cfxZones.pointInZone(loc, theZone) then 
					isSafe = true
				end
			else 
				if cfxPlayerScore.verbose then 
					trigger.action.outText("+++pSc: Zone <" .. theZone.name .. ">: owner=<" .. theZone.owner .. ">, my coa=<" .. coa .. ">, no owner match")
				end
			end
		end 
	end
	
	if not isSafe then 
		if cfxPlayerScore.verbose then 
			trigger.action.outText("+++pScr: deferred, but not inside score safe zone.", 30)
		end
		return 
	end 
	
	trigger.action.outTextForUnit(uid, playerName .. ", please wait in safe zone to claim pending score/feats (" .. cfxPlayerScore.delayAfterLanding .. " seconds).", 30)

	local unitName = theUnit:getName()
	local args = {playerName, unitName}
	timer.scheduleFunction(cfxPlayerScore.scheduledAward, args, timer.getTime() + cfxPlayerScore.delayAfterLanding)
end

function cfxPlayerScore.scheduledAward(args)
	-- called with player name and unit name in args 
	local playerName = args[1]
	local unitName = args[2]
	
	local theUnit = Unit.getByName(unitName)
	if not theUnit or 
	   not Unit.isExist(theUnit) 
	then 
		-- unit is gone
		trigger.action.outText("Player <" .. playerName .. "> lost score.", 30)
		return 
	end
	
	local uid = theUnit:getID()
	if theUnit:inAir() then 
		trigger.action.outTextForUnit(uid, "Can't award score to <" .. playerName .. ">: unit not on the ground.", 30)
		return 
	end
	
	if theUnit:getLife() < 1 then 
		trigger.action.outTextForUnit(uid, "Can't award score to <" .. playerName .. ">: unit did not survive landing.", 30)
		return  -- needs to reslot, don't have to nil player score
	end
	
	-- see if player is *still* within a scoreSafe zone 
	local loc = theUnit:getPoint()
	local coa = theUnit:getCoalition()
	local isSafe = false 
	for idx, theZone in pairs(cfxPlayerScore.safeZones) do 
		if theZone.scoreSafe == 0 or theZone.scoreSafe == coa then
			-- we no longer check ownership of zone, we did that when we landed
			if cfxZones.pointInZone(loc, theZone) then 
				isSafe = true
			end
		end 
	end
	
	if not isSafe then 
		trigger.action.outTextForUnit(uid, "Can't award score for <" .. playerName .. ">, not in safe zone.", 30)
		return 
	end 
		
	local theScore = cfxPlayerScore.getPlayerScore(playerName)
	local playerSide = dcsCommon.playerName2Coalition(playerName)
	if playerSide < 1 then
		trigger.action.outText("+++pScr: WARNING - unaffiliated player <" .. playerName .. ">, score award ignored", 30)
		return 
	end 
	if dcsCommon.getSizeOfTable(theScore.killQueue) < 1 and 
	   dcsCommon.getSizeOfTable(theScore.featQueue) < 1 and 
	   theScore.scoreaccu < 1 then 
		-- player changed planes or 
		-- there was nothing to award 
		trigger.action.outTextForUnit(uid, "Thank you, " .. playerName .. ", no scores or feats pending.", 30)
		return 
	end
	
	local hasAward = false 
	
	-- when we get here we award all scores, kills, and feats 
	local desc = "\nPlayer " .. playerName .. " is awarded:\n"
	-- score and total score 
	if theScore.scoreaccu > 0 then -- remember: negatives are immediate 
		theScore.score = theScore.score + theScore.scoreaccu
		desc = desc .. "  score: " .. theScore.scoreaccu .. " for a new total of " .. theScore.score .. "\n"
		cfxPlayerScore.coalitionScore[playerSide] = cfxPlayerScore.coalitionScore[playerSide] + theScore.scoreaccu
		if bank and bank.addFunds then 
			bank.addFunds(playerSide, cfxPlayerScore.score2finance * theScore.scoreaccu)
			desc = desc .. "(transferred §" .. cfxPlayerScore.score2finance * theScore.scoreaccu .. " to funding)\n"
		end
		theScore.scoreaccu = 0 
		hasAward = true 
	end 
	
	if cfxPlayerScore.verbose then 
		trigger.action.outText("Iterating kill q <" .. dcsCommon.getSizeOfTable(theScore.killQueue) .. "> and feat q <" .. dcsCommon.getSizeOfTable(theScore.featQueue) .. ">", 30)
	end
	-- iterate kill type list 
	if dcsCommon.getSizeOfTable(theScore.killQueue) > 0 then 
		desc = desc .. "  confirmed kills in order:\n"
		for idx, theType in pairs(theScore.killQueue) do 
			desc = desc .. "    " .. theType .. "\n"
			cfxPlayerScore.doLogTypeKill(playerName, theScore, theType)
		end
		hasAward = true 
	end
	theScore.killQueue = {}
	
	-- iterate feats 
	if dcsCommon.getSizeOfTable(theScore.featQueue) > 0 then 
		desc = desc .. "  confirmed feats:\n"
		for idx, theFeat in pairs(theScore.featQueue) do 
			desc = desc .. "    " .. theFeat .. "\n"
			cfxPlayerScore.doLogFeat(playerName, theScore, theFeat)
		end
		hasAward = true 
	end
	theScore.featQueue = {}
	
	if cfxPlayerScore.reportCoalition then 
		desc = desc .. "\nCoalition Total: " .. cfxPlayerScore.coalitionScore[playerSide]
	end
	
	-- output score 
	desc = desc .. "\n"
	if hasAward then 
		trigger.action.outTextForCoalition(coa, desc, 30)
	end 
end

function cfxPlayerScore.handlePlayerDeath(theEvent)
	-- multiple of these events can occur per player 
	-- so we use the unit2player link to see player 
	-- is affected, and if so, erase the link so it 
	-- only counts once 
	local theUnit = theEvent.initiator 
	local uName = theUnit:getName()
	
	if cfxPlayerScore.verbose then 
		trigger.action.outText("+++pScr: LOA/player death handler entry for <" .. uName .. ">", 30)
	end
	
	local pName = cfxPlayerScore.unit2player[uName] 
	if pName then 
		-- this was a player name with link still live.
		if cfxPlayerScore.planeLoss ~= 0 then 
			-- plane loss has IMMEDIATE consequences 
			cfxPlayerScore.updateScoreForPlayerImmediate(pName, cfxPlayerScore.planeLoss)
			if cfxPlayerScore.announcer then 
				local uid = theUnit:getID()
				local thePlayerRecord = cfxPlayerScore.getPlayerScore(pName)
				trigger.action.outTextForUnit(uid, "Loss of aircraft detected: " .. cfxPlayerScore.planeLoss .. " awarded immediately, for new total of " .. thePlayerRecord.score, 30)
			end
		end
		-- always clear the link.
		cfxPlayerScore.unit2player[uName] = nil
	else 
		if cfxPlayerScore.verbose then 
			trigger.action.outText("+++pScr - no action for LOA", 30)
		end
	end

end

function cfxPlayerScore.handlePlayerEvent(theEvent)
	if theEvent.id == 28 then 
		-- kill from player detected.
		cfxPlayerScore.killDetected(theEvent)	
		
	elseif theEvent.id == 15 then -- birth 
		-- access player score for player. this will 
		-- allocate if doesn't exist. Any player ever 
		-- birthed will be in db
		local thePlayerUnit = theEvent.initiator 
		local playerSide = thePlayerUnit:getCoalition()
		local playerName = thePlayerUnit:getPlayerName()
		local theScore = cfxPlayerScore.getPlayerScore(playerName)
		-- now re-init feat and score queues 
		
		if theScore.scoreaccu and theScore.scoreaccu > 0 then 
			trigger.action.outTextForCoalition(playerSide, "Player " .. playerName .. ", score of <" .. theScore.scoreaccu .. "> points discarded.", 30)
		end 
		theScore.scoreaccu = 0 
		if dcsCommon.getSizeOfTable(theScore.killQueue) > 0 then 
			trigger.action.outTextForCoalition(playerSide, "Player " .. playerName .. ", <" .. dcsCommon.getSizeOfTable(theScore.killQueue) .. "> kills discarded.", 30)
		end
		theScore.killQueue = {}
		if dcsCommon.getSizeOfTable(theScore.featQueue) > 0 then 
			trigger.action.outTextForCoalition(playerSide, "Player " .. playerName .. ", <" .. dcsCommon.getSizeOfTable(theScore.featQueue) .. "> feats discarded.", 30)
		end		
		theScore.featQueue = {}
		-- write back
		cfxPlayerScore.setPlayerScore(playerName, theScore)
		
	elseif theEvent.id == 4 then -- land 
		-- see if plane is still connected to player 
		local theUnit = theEvent.initiator
		local uName = theUnit:getName() 
		if cfxPlayerScore.unit2player[uName] then 
		-- is filtered if too soon after last take-off/landing 
		cfxPlayerScore.handlePlayerLanding(theEvent)
		else 
			if verbose then 
				trigger.action.outText("+++pScr: filtered landing for <" .. uName .. ">: player no longer linked to unit", 30)
			end
		end	

	end
end

function cfxPlayerScore.readConfigZone(theZone)
	cfxPlayerScore.verbose = theZone.verbose 
	-- default scores 
	cfxPlayerScore.aircraft = theZone:getNumberFromZoneProperty("aircraft", 50) 
	cfxPlayerScore.helo = theZone:getNumberFromZoneProperty("helo", 40)  
	cfxPlayerScore.ground = theZone:getNumberFromZoneProperty("ground", 10)  
	cfxPlayerScore.ship = theZone:getNumberFromZoneProperty("ship", 80)   
	cfxPlayerScore.train = theZone:getNumberFromZoneProperty( "train", 5)
	cfxPlayerScore.landing = theZone:getNumberFromZoneProperty("landing", 0) -- if > 0 then feat 
	
	cfxPlayerScore.pkMod = theZone:getNumberFromZoneProperty( "pkMod", 1) -- factor for killing a player
	cfxPlayerScore.ffMod = theZone:getNumberFromZoneProperty( "ffMod", -2) -- factor for friendly fire 
	cfxPlayerScore.planeLoss = theZone:getNumberFromZoneProperty("planeLoss", -10) -- points added when player's plane crashes
	
	cfxPlayerScore.announcer = theZone:getBoolFromZoneProperty("announcer", true)
	
	if theZone:hasProperty("badSound") then 
		cfxPlayerScore.badSound = theZone:getStringFromZoneProperty("badSound", "<nosound>")
	end
	if theZone:hasProperty("scoreSound") then 
		cfxPlayerScore.scoreSound = theZone:getStringFromZoneProperty("scoreSound", "<nosound>")
	end
	
	-- triggering saving scores
	if theZone:hasProperty("saveScore?") then 
		cfxPlayerScore.saveScore = theZone:getStringFromZoneProperty("saveScore?", "none")
		cfxPlayerScore.lastSaveScore = trigger.misc.getUserFlag(cfxPlayerScore.saveScore)
		cfxPlayerScore.incremental = theZone:getBoolFromZoneProperty("incremental", false) -- incremental saves 
	end
	
	-- triggering show all scores
	if theZone:hasProperty("showScore?") then 
		cfxPlayerScore.showScore = theZone:getStringFromZoneProperty("showScore?", "none")
		cfxPlayerScore.lastShowScore = trigger.misc.getUserFlag(cfxPlayerScore.showScore)
	end
	
	cfxPlayerScore.rankPlayers = theZone:getBoolFromZoneProperty("rankPlayers", false)
	
	cfxPlayerScore.scoreOnly = theZone:getBoolFromZoneProperty("scoreOnly", true)
	
	cfxPlayerScore.deferred = theZone:getBoolFromZoneProperty("deferred", false)
	
	cfxPlayerScore.delayAfterLanding = theZone:getNumberFromZoneProperty("delayAfterLanding", 10)
	
	cfxPlayerScore.scoreFileName = theZone:getStringFromZoneProperty("scoreFileName", "Player Scores")

	cfxPlayerScore.reportScore = theZone:getBoolFromZoneProperty("reportScore", true)
	
	cfxPlayerScore.reportFeats = theZone:getBoolFromZoneProperty("reportFeats", true)
	
	cfxPlayerScore.reportCoalition = theZone:getBoolFromZoneProperty("reportCoalition", false) -- also show coalition score 
	
	cfxPlayerScore.noGrief = theZone:getBoolFromZoneProperty( "noGrief", true) -- noGrief = only add positive score 
	
	if theZone:hasProperty("redScore#") then 
		cfxPlayerScore.redScoreOut = theZone:getStringFromZoneProperty("redScore#")
		theZone:setFlagValue(cfxPlayerScore.redScoreOut, cfxPlayerScore.coalitionScore[1])
	end
	
	if theZone:hasProperty("blueScore#") then 
		cfxPlayerScore.blueScoreOut = theZone:getStringFromZoneProperty("blueScore#")
		theZone:setFlagValue(cfxPlayerScore.blueScoreOut, cfxPlayerScore.coalitionScore[2])
	end
	
	if theZone:hasProperty("sharedData") then 
		cfxPlayerScore.sharedData = theZone:getStringFromZoneProperty("sharedData", "cfxNameMissing")
	end 
	
	cfxPlayerScore.score2finance = theZone:getNumberFromZoneProperty("score2finance", 1) -- factor to convert points to bank finance
end

--
-- load / save (game data)
--
function cfxPlayerScore.saveData()
	local theData = {}
	-- save current score list. simple clone 
	local theScore = dcsCommon.clone(cfxPlayerScore.playerScore)
	theData.theScore = theScore
	-- build feat zone list 
	theData.coalitionScore = dcsCommon.clone(cfxPlayerScore.coalitionScore)
	local featZones = {}
	for idx, theZone in pairs(cfxPlayerScore.featZones) do 
		local theFeat = {}
		theFeat.awardedTo = theZone.awardedTo 
		theFeat.featNum = theZone.featNum 
		featZones[theZone.name] = theFeat
	end
	theData.featData = featZones 
	return theData, cfxPlayerScore.sharedData
end

function cfxPlayerScore.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("cfxPlayerScore", cfxPlayerScore.sharedData)
	if not theData then 
		if cfxPlayerScore.verbose then 
			trigger.action.outText("+++playerscore: no save data received, skipping.", 30)
		end
		return
	end
	
	local theScore = theData.theScore
	cfxPlayerScore.playerScore = theScore 
	if theData.coalitionScore then 
		cfxPlayerScore.coalitionScore = theData.coalitionScore
	end
	if cfxPlayerScore.redScoreOut then 
		cfxZones.setFlagValue(cfxPlayerScore.redScoreOut, cfxPlayerScore.coalitionScore[1], cfxPlayerScore)
	end
	if cfxPlayerScore.blueScoreOut then 
		cfxZones.setFlagValue(cfxPlayerScore.blueScoreOut, cfxPlayerScore.coalitionScore[2], cfxPlayerScore)
	end
	
	local featData = theData.featData 
	if featData then 
		for name, data in pairs(featData) do 
			local theZone = cfxPlayerScore.getFeatByName(name)
			if theZone then 
				theZone.awardedTo = data.awardedTo
				theZone.featNum = data.featNum
			end
		end		
	end 
end

--
-- save scores (text file)
--

function cfxPlayerScore.saveScores(theText, name)
	if not _G["persistence"] then 
		trigger.action.outText("+++pScr: persistence module required to save scores. Here are the scores that I would have saved to <" .. name .. ">:\n", 30)
		trigger.action.outText(theText, 30)
		return
	end
	
	if not persistence.active then 
		trigger.action.outText("+++pScr: persistence module can't write. Please ensure that you have desanitized lfs and io for DCS", 30)
		return 
	end
	
	local append = cfxPlayerScore.incremental
	local shared = false -- currently not supported

	if cfxPlayerScore.incremental then 
		if cfxPlayerScore.firstSave then 
			theText = "\n*** NEW MISSION started.\n" .. theText
		end
		
		-- prepend time for score 
		theText = "\n\n====== Mission Time: " .. dcsCommon.nowString() .. "\n" .. theText
	end 
	
	if persistence.saveText(theText, name, shared, append) then 
		if cfxPlayerScore.verbose then 
			trigger.action.outText("+++pScr: scores saved to <" .. persistence.missionDir .. name .. ">", 30)
		end
	else 
		trigger.action.outText("+++pScr: unable to save scores to <" .. persistence.missionDir .. name .. ">")
	end
	
	cfxPlayerScore.firstSave  = false 
end

function cfxPlayerScore.saveScoreToFile()
	-- local built score table 
	local ranked = cfxPlayerScore.rankPlayers
	local theText = cfxPlayerScore.scoreTextForAllPlayers(ranked) 
	
	-- save to disk 
	cfxPlayerScore.saveScores(theText, cfxPlayerScore.scoreFileName)
end

function cfxPlayerScore.showScoreToAll()
	local ranked = cfxPlayerScore.rankPlayers
	local theText = cfxPlayerScore.scoreTextForAllPlayers(ranked) 
	trigger.action.outText(theText, 30)
end

--
-- Update
--
function cfxPlayerScore.update()
	-- re-invoke in 1 second
	timer.scheduleFunction(cfxPlayerScore.update, {}, timer.getTime() + 1)
	
	-- see if someone banged on saveScore
	if cfxPlayerScore.saveScore then 
		if cfxZones.testZoneFlag(cfxPlayerScore, cfxPlayerScore.saveScore, "change", "lastSaveScore") then 
			if cfxPlayerScore.verbose then 
				trigger.action.outText("+++pScr: saving scores...", 30)
			end
			cfxPlayerScore.saveScoreToFile()
		end
	end
	
	-- showScore perhaps?
	if cfxPlayerScore.showScore then 
		if cfxZones.testZoneFlag(cfxPlayerScore, cfxPlayerScore.showScore, "change", "lastShowScore") then 
			if cfxPlayerScore.verbose then 
				trigger.action.outText("+++pScr: showing scores...", 30)
			end
			cfxPlayerScore.showScoreToAll()
		end
	end
	
	-- check score flags 
	if cfxPlayerScore.blueTriggerFlags then 
		local coa = 2
		for tName, tVal in pairs(cfxPlayerScore.blueTriggerFlags) do 
			local newVal = trigger.misc.getUserFlag(tName)
			if tVal ~= newVal then 
				-- score!
				cfxPlayerScore.coalitionScore[coa] = cfxPlayerScore.coalitionScore[coa] + cfxPlayerScore.blueTriggerScore[tName]
				cfxPlayerScore.blueTriggerFlags[tName] = newVal
				
				if cfxPlayerScore.announcer then
					trigger.action.outTextForCoalition(coa, "BLUE goal [" .. tName .. "] achieved, new BLUE coalition score is " .. cfxPlayerScore.coalitionScore[coa], 30)
					trigger.action.outSoundForCoalition(coa, cfxPlayerScore.scoreSound)
				end
				
				-- bank it if exists
				local amount 
				if bank and bank.addFunds then 
					amount = cfxPlayerScore.score2finance * cfxPlayerScore.blueTriggerScore[tName]
					bank.addFunds(coa, amount)
					if cfxPlayerScore.announcer then 
						trigger.action.outTextForCoalition(coa, "Transferred §" .. amount .. " to funds.", 30)
					end
				end 
			end
		end
	end
	if cfxPlayerScore.redTriggerFlags then 
		local coa = 1
		for tName, tVal in pairs(cfxPlayerScore.redTriggerFlags) do 
			local newVal = trigger.misc.getUserFlag(tName)
				if tVal ~= newVal then 
				-- score!

				cfxPlayerScore.coalitionScore[coa] = cfxPlayerScore.coalitionScore[coa] + cfxPlayerScore.redTriggerScore[tName]
				cfxPlayerScore.redTriggerFlags[tName] = newVal
				--if bank and bank.addFunds then 
				--	bank.addFunds(coa, cfxPlayerScore.score2finance * cfxPlayerScore.blueTriggerScore[tName])
				--end
				if cfxPlayerScore.announcer then
					trigger.action.outTextForCoalition(coa, "RED goal [" .. tName .. "] achieved, new RED coalition score is " .. cfxPlayerScore.coalitionScore[coa], 30)
					trigger.action.outSoundForCoalition(coa, cfxPlayerScore.scoreSound)
				end
				
				-- bank it if exists
				local amount 
				if bank and bank.addFunds then 
					amount = cfxPlayerScore.score2finance * cfxPlayerScore.redTriggerScore[tName]
					bank.addFunds(coa, amount)
					if cfxPlayerScore.announcer then 
						trigger.action.outTextForCoalition(coa, "Transferred §" .. amount .. " to funds.", 30)
					end
				end 
			end
		end
	end
	-- set output flags if they are set 
	if cfxPlayerScore.redScoreOut then 
		cfxZones.setFlagValue(cfxPlayerScore.redScoreOut, cfxPlayerScore.coalitionScore[1], cfxPlayerScore)
	end
	
	if cfxPlayerScore.blueScoreOut then 
		cfxZones.setFlagValue(cfxPlayerScore.blueScoreOut, cfxPlayerScore.coalitionScore[2], cfxPlayerScore)
	end
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
	if theZone then 
		-- read all into my types registry, replacing whatever is there
		cfxPlayerScore.typeScore = cfxZones.getAllZoneProperties(theZone)
	end 
	
	-- read score tiggers and values
	cfxPlayerScore.redTriggerFlags = nil
	cfxPlayerScore.blueTriggerFlags = nil
	local theZone = cfxZones.getZoneByName("redScoreFlags") 
	if theZone then 
		-- read flags into redTriggerScore
		cfxPlayerScore.redTriggerScore = cfxZones.getAllZoneProperties(theZone, false, true) -- use case, all numbers 
		-- init their flag handlers 
		cfxPlayerScore.redTriggerFlags = {}
		trigger.action.outText("+++pScr: read RED score table", 30)
		for tName, tScore in pairs(cfxPlayerScore.redTriggerScore) do 
			if tScore == 0 then 
				trigger.action.outText("+++pScr: WARNING - RED triggered score <" .. tName .. "> has zero score value!", 30)
			end
			cfxPlayerScore.redTriggerFlags[tName] = trigger.misc.getUserFlag(tName)
		end
	end 
	local theZone = cfxZones.getZoneByName("blueScoreFlags") 
	if theZone then 
		-- read flags into redTriggerScore
		cfxPlayerScore.blueTriggerScore = cfxZones.getAllZoneProperties(theZone, false, true) -- case sensitive, numbers only
		-- init their flag handlers 
		cfxPlayerScore.blueTriggerFlags = {}
		trigger.action.outText("+++pScr: read BLUE score table", 30)
		for tName, tScore in pairs(cfxPlayerScore.blueTriggerScore) do
			if tScore == 0 then 
				trigger.action.outText("+++pScr: WARNING - BLUE triggered score <" .. tName .. "> has zero score value!", 30)
			end		
			cfxPlayerScore.blueTriggerFlags[tName] = trigger.misc.getUserFlag(tName)
		end
	end 
	
	-- now read my config zone 
	local theZone = cfxZones.getZoneByName("playerScoreConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("playerScoreConfig")
	end 
	cfxPlayerScore.readConfigZone(theZone)
	 	
	-- read all scoreSafe zones 
	local safeZones = cfxZones.zonesWithProperty("scoreSafe")
	for k, aZone in pairs(safeZones) do
		cfxPlayerScore.addSafeZone(aZone)
	end
	
	-- read all feat zones 
	local featZones = cfxZones.zonesWithProperty("feat")
	for k, aZone in pairs(featZones) do
		cfxPlayerScore.addFeatZone(aZone)
	end
	
	-- read all kill zones 
	local killZones = cfxZones.zonesWithProperty("killZone")
	for k, aZone in pairs(killZones) do
		cfxPlayerScore.addKillZone(aZone)
	end
	
	-- check that deferred has scoreSafe zones 
	if cfxPlayerScore.deferred and dcsCommon.getSizeOfTable(cfxPlayerScore.safeZones) < 1 then 
		trigger.action.outText("+++pScr: WARNING - deferred scoring active but no 'scoreSafe' zones set!", 30)
	end
	
	-- subscribe to events and use dcsCommon's handler structure
	dcsCommon.addEventHandler(cfxPlayerScore.handlePlayerEvent,
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
	
	-- start update 
	cfxPlayerScore.update()
		
	trigger.action.outText("cfxPlayerScore v" .. cfxPlayerScore.version .. " started", 30)
	return true 
end


if not cfxPlayerScore.start() then 
	trigger.action.outText("+++ aborted cfxPlayerScore v" .. cfxPlayerScore.version .. "  -- libcheck failed", 30)
	cfxPlayerScore = nil 
end

-- TODO: score mod for weapons type 
-- TODO: player kill score 

--[[--

feat zone
"feat" feat type, default is kill, possible other types 
	- landing 
score zones 
	- zones outside of which no scoring counts, but feats are still ok 
	
- add take off feats
- integrate with objectDestructDetector

can be extended with other, standalone feat modules that follow the 
same pattern, e.g. enter a zone, detect someone 

--]]--
 