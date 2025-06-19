cfxPlayerScore = {}
cfxPlayerScore.version = "5.3.2"
cfxPlayerScore.name = "cfxPlayerScore" -- compatibility with flag bangers
cfxPlayerScore.firstSave = true -- to force overwrite 
--[[-- VERSION HISTORY
	4.0.0 - own event handling, disco from dcsCommon 
		  - early landing detection (unitSpawnTime)
	5.0.0 - resolve killed units via cfxMX to patch DCS error 
		  - reworked unit2score to use MX 
	      - code cleanup 
	5.0.1 - code hardening against name, type nilling 
	5.1.0 - deferred update: CA ground units override deferred and 
			score immediately. deferred --> deferredScore,
		  - new isDeferred(playerName) method
		  - improved wildcard support
		  - event 20 for CA also supported 
		  - "threading the needle" -- support for hit event and unit traceback
	5.2.0 - PlayerScoreTable supports wildcards, e.g. "Batumi*" 
	5.2.1 - Event 20 (CA join) corrected typo 	  
		  - wiping score on enter and birth 
		  - more robust initscore 
	5.2.2 - fixed typo in feat zone 
	5.2.3 - resolved nil vicCat 
	5.3.0 - callbacks 
		  - updateScoreForPlayer() supports reason and data 
		  - invokeCB when scoring 
	5.3.1 - DCS bug hardening 
	5.3.1 - more DCS bug hardening 
	
	TODO: Kill event no longer invoked for map objetcs, attribute 
	      to faction now, reverse invocation direction with PlayerScore
	TODO: better wildcard support for kill events 
--]]--

cfxPlayerScore.requiredLibs = {
	"dcsCommon", -- this is doing score keeping
	"cfxZones", -- zones for config 
	"cfxMX", -- DCS bug prevention 
}

cfxPlayerScore.damaged = {} -- used for hit event to collect contributing players. Only last hit will score.
cfxPlayerScore.callbacks = {}

cfxPlayerScore.playerScore = {} -- indexed by unit name - threading needle
cfxPlayerScore.coalitionScore = {} -- score per coalition
cfxPlayerScore.coalitionScore[1] = 0 -- init red
cfxPlayerScore.coalitionScore[2] = 0 -- init blue
cfxPlayerScore.deferredScore = false -- on deferred, we only award after landing, and erase on any form of re-slot
cfxPlayerScore.delayAfterLanding = 10 -- seconds after landing 
cfxPlayerScore.safeZones = {} -- safe zones to land in  
cfxPlayerScore.featZones = {} -- zones that define feats 
cfxPlayerScore.killZones = {} -- when set, kills only count here 

-- typeScore: dictionary sorted by typeString for score 
-- extend to add more types. It is used by unitType2score to 
-- determine the base unit score  
cfxPlayerScore.typeScore = {} -- ALL UPPERCASE
cfxPlayerScore.wildTypes = {} -- ALL UPPERCASE
cfxPlayerScore.lastPlayerLanding = {} -- timestamp, by player name  
cfxPlayerScore.delayBetweenLandings = 30 -- seconds to count as separate landings, also set during take-off to prevent janky t/o to count. 
cfxPlayerScore.aircraft = 50 
cfxPlayerScore.helo = 40 
cfxPlayerScore.ground = 10
cfxPlayerScore.ship = 80 
cfxPlayerScore.train = 5 
cfxPlayerScore.landing = 0 -- if > 0 it scores as feat

cfxPlayerScore.unit2player = {} -- lookup and reverse look-up 
cfxPlayerScore.unitSpawnTime = {} -- lookup by unit name to prevent early landing 

-- signature: theCB(name, score, reason) with 
--    name: (string) name of player 
--   score: a number, can be negative. effective score awarded
-- reason : string, describes why score is changed, can be nil
--        : "EVAC"   - CSAR successful
--        : "CRASH"  - player plane lost 
--        : "FRAT"   - Fratricide - killed a friendly 
--        : "NONE"   - No reason given (default)
--        : "KILL"   - an AI unit was killed
--		  : "PVP"    - an enemy player-controlled unit was killed 
--        : "LAND"   - player landed aircraft inside landing feat zone 
--        : "INSERT" - player inserted troops into combat zone feat 
--        : may have other reasons defined later 
function cfxPlayerScore.registerScoreCallBack(theCB)
	table.insert(cfxPlayerScore.callbacks, theCB)
end

function cfxPlayerScore.invokeCB(playerName, score, reason)
	-- invoke all callbacks 
	for idx, cb in pairs(cfxPlayerScore.callbacks) do 
		cb(playerName, score, reason)
	end 
end

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
	theZone.featNum = theZone:getNumberFromZoneProperty("awardLimit", -1) -- how many times this can be awarded, -1 is infinite 
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
		if theZone.featNum == 0 then canAward = false end 
		if theZone.featType ~= featType then canAward = false end
		if not (theZone.coalition == 0 or theZone.coalition == coa) then canAward = false end			
		if featType == "PVP" then 
			-- make sure kill is pvp kill 
			if not victim then canAward = false 
			elseif not victim.getPlayerName then 
				canAward = false 
			elseif not victim:getPlayerName() then
				canAward = false 
			end
		end
		if not cfxZones.pointInZone(loc, theZone) then canAward = false end
		if theZone.ppOnce then 
			if theZone.awardedTo[name] then canAward = false end
		end
		if canAward then table.insert(theFeats, theZone) end 
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
		-- std proc for <u>, <p>, <typ>, <c>, <e>, <twn>, ...
		theMsg = dcsCommon.processStringWildcardsForUnit(theMsg, aUnit)
	end
	theMsg = theMsg:gsub("<player>", pName)
	if aVictim then 
		-- if player killed, get killed player's name else use unknown AI
		if aVictim.getPlayerName then 
			pkName = aVictim:getPlayerName()
			if pkName then theMsg = theMsg:gsub("<kplayer>", pkName)
			else theMsg = theMsg:gsub("<kplayer>", "unknown AI")
			end
		end
		if aVictim.getName then theMsg = theMsg:gsub("<unit>", aVictim:getName())
		else theMsg = theMsg:gsub("<unit>", "*?*") -- dcs oddity 
		end 
		theMsg = theMsg:gsub("<type>", aVictim:getTypeName())
		-- victim may not have group. guard against that 
		-- happens if unit 'cooks off'
		local aGroup = nil 
		if aVictim.getGroup then aVictim:getGroup() end 
		if aGroup and aGroup.getName then theMsg = theMsg:gsub("<group>", aGroup:getName())
		else theMsg = theMsg:gsub("<group>", "(Unknown)")
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
	if theZone.featNum > 0 then theZone.featNum = theZone.featNum -1 end
	-- mark this feat awarded to player, only relevant for ppOnce 
	theZone.awardedTo[name] = true 
	return msg 
end

function cfxPlayerScore.cat2BaseScore(inCat)
	if not inCat then 
		trigger.action.outText("+++scr cat2BaseScore: nil inCat, returning 1", 30)
		return 1
	end
	if inCat == 0 then return cfxPlayerScore.aircraft end -- airplane
	if inCat == 1 then return cfxPlayerScore.helo end -- helo 
	if inCat == 2 then return cfxPlayerScore.ground end -- ground 
	if inCat == 3 then return cfxPlayerScore.ship end -- ship 
	if inCat == 4 then return cfxPlayerScore.train end -- train 
	trigger.action.outText("+++scr c2bs: unknown category for lookup: <" .. inCat .. ">, returning 1", 30)
	return 1 
end
function cfxPlayerScore.wildMatch(inName)
	-- if inName starts the same as any wildcard, return score  
	for wName, wScore in pairs (cfxPlayerScore.wildTypes) do 
		if dcsCommon.stringStartsWith(inName, wName, true) then 
			if cfxPlayerScore.verbose then trigger.action.outText("+++PScr: wildmatch <" .. inName .. "> to <" .. wName .. ">, score <" .. wScore .. ">", 30) end 
			return wScore 
		end 
	end
	return nil
end

function cfxPlayerScore.object2score(inVictim, killSide) -- does not have group, go by type 
	if not inVictim then return 0 end
	if not killSide then killSide = -1 end 
	local inName 
	if inVictim.getName then inName = inVictim:getName() else inName = "*?*" end -- dcs oddity 
	if cfxPlayerScore.verbose then 
		trigger.action.outText("+++PScr: ob2sc entry to resolve name <" .. inName .. ">", 30)
	end 
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
	if type(inName) == "number" then inName = tostring(inName) end
	if cfxPlayerScore.verbose then trigger.action.outText("+++PScr: stage II inName: <" .. inName .. ">", 30) end

	-- since 2.7x DCS turns units into static objects for 
	-- cooking off, so first thing we need to do is do a name check 
	local objectScore = cfxPlayerScore.typeScore[inName:upper()]
	if not objectScore then 
		-- try the type desc 
		local theType = inVictim:getTypeName()
		if theType then objectScore = cfxPlayerScore.typeScore[theType:upper()] end 
		if not objectScore then objectScore = cfxPlayerScore.wildMatch(theType) end 
	end
	if type(objectScore) == "string" then objectScore = tonumber(objectScore)end
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

function cfxPlayerScore.isDeferred(playerName)
	if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: enter isDeferred for <" .. playerName .. ">", 30) end 
	if not cfxPlayerScore.deferredScore then 
		if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: Not global defer. EXIT", 30) end 
		return false 
	end 
	-- coalition.getPlayers() does NOT return CA units, so we 
	-- use cfxPlayerScore.currentEventUnit to find out what unit TYPE
	local theUnit = cfxPlayerScore.currentEventUnit
	if not theUnit then 
		if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: No event unit. EXIT", 30) end
		return false 
	end
	local theGroup = theUnit:getGroup()
	local cat = Group.getCategory(theGroup) -- getCat may still be borked
	if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: player <" .. playerName .. "> group cat is <" .. cat .. ">.", 30) end 
	if cat == 2 then 
		if cfxPlayerScore.verbose then 
			local uName = theUnit:getName()
			trigger.action.outText("+++pScr: CA player <" .. playerName .. "> in unit <" .. uName .. ">, immediate score oRide.", 30)
		end 
		return false
	end 
	return true 
end

function cfxPlayerScore.unit2score(inUnit)
	local vicName = "*?*"
	if inUnit.getName then vicName = inUnit:getName() end
	--	local vicGroup = inUnit:getGroup()
	local vicCat = cfxMX.spawnedUnitCatByName[vicName] -- now using MX 
	local vicType = inUnit:getTypeName()
	if type(vicName) == "number" then vicName = tostring(vicName) end 
	-- simply extend by adding items to the typescore table.concat
	-- we first try by unit name. This allows individual
	-- named hi-value targets to have individual scores 
	local uScore = nil 
	if vicName then 
		uScore = cfxPlayerScore.typeScore[vicName:upper()]
		if not uScore then uScore = cfxPlayerScore.wildMatch(vicName) end 
	end 
	-- see if all members of group score 
	if (not uScore) then -- and vicGroup then 
		local grpName = cfxMX.spawnedUnitGroupNameByName[vicName]--vicGroup:getName()
		if grpName then 
			uScore = cfxPlayerScore.typeScore[grpName:upper()]
			if not uScore then uScore = cfxPlayerScore.wildMatch(grpName) end
		end 
	end
	if not uScore then 
		-- WE NOW TRY TO ACCESS BY VICTIM'S TYPE STRING	
		if vicType then 
			uScore = cfxPlayerScore.typeScore[vicType:upper()] 	
			if not uScore then uScore = cfxPlayerScore.wildMatch(vicType) end
		end 
	end 
	if type(uScore) == "string" then uScore = tonumber(uScore) end
	if not uScore then uScore = 0 end 
	if uScore > 0 then return uScore end 
	-- only apply base scores when the lookup did not give a result
	uScore = cfxPlayerScore.cat2BaseScore(vicCat)
	return uScore 
end

function cfxPlayerScore.getPlayerScore(playerName)
	local thePlayerScore = cfxPlayerScore.playerScore[playerName]
	if not thePlayerScore then 
		thePlayerScore = cfxPlayerScore.createNewPlayerScore(playerName)
--[[--		thePlayerScore = {}
		thePlayerScore.name = playerName
		thePlayerScore.score = 0 -- score
		thePlayerScore.scoreaccu = 0 -- for deferred 
		thePlayerScore.killTypes = {} -- the type strings killed, dict <typename> <numkilla>
		thePlayerScore.killQueue = {} -- when using deferred
		thePlayerScore.totalKills = 0 -- number of kills total 
		thePlayerScore.featTypes = {} -- dict <featname> <number> of other things player did 
		thePlayerScore.featQueue = {} -- when using deferred 
		thePlayerScore.totalFeats = 0	
--]]--		
	end
	return thePlayerScore
end

function cfxPlayerScore.createNewPlayerScore(playerName)
	local thePlayerScore = {}
	thePlayerScore.name = playerName
	thePlayerScore.score = 0 -- score
	thePlayerScore.scoreaccu = 0 -- for deferred 
	thePlayerScore.killTypes = {} -- the type strings killed, dict <typename> <numkilla>
	thePlayerScore.killQueue = {} -- when using deferred
	thePlayerScore.totalKills = 0 -- number of kills total 
	thePlayerScore.featTypes = {} -- dict <featname> <number> of other things player did 
	thePlayerScore.featQueue = {} -- when using deferred 
	thePlayerScore.totalFeats = 0
	return thePlayerScore
end

function cfxPlayerScore.wipeScore(playerName) 
	if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: enter wipe score for player <" .. playerName .. ">", 30) end 
	if not cfxPlayerScore.playerScore[playerName] then return end 
	thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)
	local loss = false 
	if thePlayerScore.scoreaccu > 0 then loss = true end 
	if dcsCommon.getSizeOfTable(thePlayerScore.featQueue) > 0 then loss = true end 
	if dcsCommon.getSizeOfTable(thePlayerScore.killQueue) > 0 then loss = true end 
	thePlayerScore.scoreaccu = 0
	thePlayerScore.killQueue = {}
	thePlayerScore.featQueue = {}
	cfxPlayerScore.setPlayerScore(playerName, thePlayerScore) -- write back 
	if loss then 
		trigger.action.outText("Player " .. playerName .. " lost score.", 30) -- everyone sees this
	end 
end

function cfxPlayerScore.setPlayerScore(playerName, thePlayerScore)
	cfxPlayerScore.playerScore[playerName] = thePlayerScore
end

-- will never defer 
function cfxPlayerScore.updateScoreForPlayerImmediate(playerName, score, reason, data)
	if not reason then reason = "NONE" end 
	cfxPlayerScore.invokeCB(playerName, score, reason)
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
			if bank and bank.addFunds then bank.addFunds(pFaction, cfxPlayerScore.score2finance * score) end
		end
	else 
		if pFaction > 0 then 
			cfxPlayerScore.coalitionScore[pFaction] = cfxPlayerScore.coalitionScore[pFaction] + score 
			if bank and bank.addFunds then bank.addFunds(pFaction, cfxPlayerScore.score2finance * score) end		
		end
	end
	return thePlayerScore.score 
end

function cfxPlayerScore.updateScoreForPlayer(playerName, score, reason, data)
	-- main update score 
	if cfxPlayerScore.isDeferred(playerName) then -- just queue it
		local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName) 
		thePlayerScore.scoreaccu = thePlayerScore.scoreaccu + score
		cfxPlayerScore.setPlayerScore(playerName, thePlayerScore) -- write-through. why? because it may be a new entry.
		return thePlayerScore.score -- this is the old score!!! 
	end
	-- when we get here write immediately 
	return cfxPlayerScore.updateScoreForPlayerImmediate(playerName, score, reason, data)
end

function cfxPlayerScore.doLogTypeKill(playerName, thePlayerScore, theType)
	local killCount = thePlayerScore.killTypes[theType]	
	if killCount == nil then killCount = 0 end
	killCount = killCount + 1
	thePlayerScore.totalKills = thePlayerScore.totalKills + 1
	thePlayerScore.killTypes[theType] = killCount
	cfxPlayerScore.setPlayerScore(playerName, thePlayerScore)
end 

function cfxPlayerScore.logKillForPlayer(playerName, theUnit)
	-- main kill type /total count logging, can be deferred 
	-- no score change here 
	if not theUnit then 
		trigger.action.outText("logKillForPlayer <" .. playerName .. "> : NIL theUnit", 30) 
		return 
	end
	if not playerName then return end 
	local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)	
	local theType = theUnit:getTypeName()
	if cfxPlayerScore.isDeferred(playerName) then 
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
	if featCount == nil then featCount = 0 end
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
		if cfxPlayerScore.isDeferred(playerName) then disclaim = " (award pending)" end 
		trigger.action.outTextForCoalition(coa, playerName .. " achieved " .. theFeat .. disclaim, 30)
		trigger.action.outSoundForCoalition(coa, cfxPlayerScore.scoreSound)
	end
	local thePlayerScore = cfxPlayerScore.getPlayerScore(playerName)
	if cfxPlayerScore.isDeferred(playerName) then 
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
		if scoreOnly then return desc end 
		-- now go through all kills
		desc = desc .. "\nKills by type:\n"
		if dcsCommon.getSizeOfTable(thePlayerScore.killTypes)  < 1 then desc = desc .. "    - NONE -\n" end
		for theType, quantity in pairs(thePlayerScore.killTypes) do 
			desc = desc .. "  - " .. theType .. ": " .. quantity .. "\n"
		end
	end 
	
	-- now enumerate all feats
	if not thePlayerScore.featTypes then thePlayerScore.featTypes = {} end
	if cfxPlayerScore.reportFeats then 
		desc = desc .. "\n Accomplishments:\n"
		if dcsCommon.getSizeOfTable(thePlayerScore.featTypes) < 1 then 	desc = desc .. "    - NONE -\n" end
		for theFeat, quantity in pairs(thePlayerScore.featTypes) do 
			desc = desc .. "  - " .. theFeat
			if quantity > 1 then desc = desc .. " (x" .. quantity .. ")" end 
			desc = desc .. "\n"
		end
	end 
	if cfxPlayerScore.reportScore and thePlayerScore.scoreaccu > 0 then desc = desc .. "\n - unclaimed score: " .. thePlayerScore.scoreaccu .."\n" end
	local featCount = dcsCommon.getSizeOfTable(thePlayerScore.featQueue)
	if cfxPlayerScore.reportFeats and featCount > 0 then desc = desc .. " - unclaimed feats: " .. featCount .."\n" end
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
	if count < 1 then desc = desc .. "  (No score yet)" end
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
		if not isFirst then theText = theText .. "\n" end
		if ranked then 
			if rank < 10 then theText = theText .. " " end
			theText = theText .. rank .. ". "
		end
		theText = theText .. cfxPlayerScore.playerScore2text(score, cfxPlayerScore.scoreOnly)  
		isFirst = false
		rank = rank + 1
	end
	if dcsCommon.getSizeOfTable(theScores) < 1 then theText = theText .. "  (No score yet)\n" end
	if cfxPlayerScore.reportCoalition then 
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
	else 
		-- WARNING: NO EXIST CHECK DONE!
		-- after kill, unit is dead, so will no longer exist!
		if theUnit.getName then theName = theUnit:getName()
		else theName = "*?*"
		end 
		if not theName then return false end 
	end
	if cfxPlayerScore.typeScore[theName:upper()] then return true end
	if cfxPlayerScore.wildMatch(theName) then return true end 
	return false 
end

function cfxPlayerScore.awardScoreTo(killSide, theScore, killerName, pk)
	local playerScore 
	if theScore < 0 then playerScore = cfxPlayerScore.updateScoreForPlayerImmediate(killerName, theScore, "FRAT", nil) -- fratricide 
	else 
		if pk then
			playerScore = cfxPlayerScore.updateScoreForPlayer(killerName, theScore, "PVP", nil)
		else 
			playerScore = cfxPlayerScore.updateScoreForPlayer(killerName, theScore, "KILL", nil)
		end 
	end
	if not cfxPlayerScore.reportScore then return end 
	if cfxPlayerScore.announcer then
		if (theScore > 0) and cfxPlayerScore.isDeferred(killerName) then 
			thePlayerRecord = cfxPlayerScore.getPlayerScore(killerName) -- re-read after write
			trigger.action.outTextForCoalition(killSide, "Killscore:  " .. theScore .. ", now " .. thePlayerRecord.scoreaccu .. " waiting for " .. killerName .. ", awarded after landing", 30)
		else -- negative score or not deferred 
			trigger.action.outTextForCoalition(killSide, "Killscore:  " .. theScore .. " for a total of " .. playerScore .. " for " .. killerName, 30)
			
			if cfxPlayerScore.reportCoalition then trigger.action.outTextForCoalition(killSide, "\nCoalition Total:  " .. cfxPlayerScore.coalitionScore[killSide], 30) end 
		end
	end 
end

--
-- EVENT PROCESSING / HANDLING
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


function cfxPlayerScore.isStaticObject(theUnit) 
	if not theUnit.getGroup then 
		if cfxPlayerScore.verbose then trigger.action.outText("isStatic: no <getGroup>", 30) end 
		return true 
	end 
	local aGroup = theUnit:getGroup()
	if aGroup then 
		if cfxPlayerScore.verbose then trigger.action.outText("isStatic: returned group, all fine", 30) end 
		return false 
	end 
	-- now check if this WAS a unit, but has been turned to 
	-- a non-grouped static by DCS 
	if theUnit.getName and theUnit:getName() then 
		local uName = theUnit:getName()
		if cfxMX.spawnedUnitCoaByName[uName] then 
			if cfxPlayerScore.verbose then trigger.action.outText("MX resolve for former unit, now static!", 30) end 
			return false
		end
	end 
	
	if cfxPlayerScore.verbose then trigger.action.outText("has getGroup method, returned none", 30) end 
	if cfxPlayerScore.verbose and theUnit.getName and theUnit:getName() then  trigger.action.outText("unit <" .. theUnit:getName() .. "> has getGroup method, returned none", 30) end 
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
		if cfxPlayerScore.verbose then trigger.action.outText("Kill feat awarded/queued for <" .. name .. ">", 30) end
	end
end

function cfxPlayerScore.killDetected(theEvent)
	-- we are only getting called when and if 
	-- a kill occured and killer was a player 
	-- and target exists
	if cfxPlayerScore.verbose then trigger.action.outText("+++PScr: enter kill detected", 30) 	end 
	local killer = theEvent.initiator
	local victim = theEvent.target
	cfxPlayerScore.processKill(killer, victim) 
end

function cfxPlayerScore.processKill(killer, victim)
	if cfxPlayerScore.verbose then trigger.action.outText("+++PScr: enter process kill", 30) end 
	local killerName = killer:getPlayerName()
	if not killerName then killerName = "<nil>" end
	local killSide = killer:getCoalition()
	local killVehicle = killer:getTypeName()
	if not killVehicle then killVehicle = "<nil>" end 

	-- was it a player kill?
	local pk = dcsCommon.isPlayerUnit(victim)
	-- was it a scenery object? 
	local wasBuilding = dcsCommon.isSceneryObject(victim)
	if wasBuilding then 
		if cfxPlayerScore.verbose then trigger.action.outText("+++PScr: killed object was a map/scenery object", 30) end 
		-- these objects have no coalition; we simply award the score if 
		-- it exists in look-up table. 
		local staticScore = cfxPlayerScore.object2score(victim, killSide)
		if staticScore > 0 then 
			trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.scoreSound)
			cfxPlayerScore.awardScoreTo(killSide, staticScore, killerName, nil)
			cfxPlayerScore.checkKillFeat(killerName, killer, victim, false)
		end
		if victim.getName and victim:getName() then cfxPlayerScore.damaged[victim:getName()] = nil end
		return 
	end
	-- was it fratricide?
	-- if we get here, it CANT be a scenery object 
	-- but can be a static object, and stO have a coalition
	local vicSide = victim:getCoalition()
	local fraternicide = (killSide == vicSide)
	local neutralKill = (vicSide == 0) -- neutral is 0
	if cfxPlayerScore.verbose then 
		if fraternicide then trigger.action.outText("Fratricide detected.", 30) end
		if neutralKill then trigger.action.outText("NEUTRAL KILL detected.", 30) end
	end 
	local vicDesc = victim:getTypeName()
	local scoreMod = 1 -- start at one 

	-- see what kind of unit (category) we killed
    -- and look up base score 
	local isStO = cfxPlayerScore.isStaticObject(victim) 
	--if not victim.getGroup then
	if isStO then 
		if cfxPlayerScore.verbose then trigger.action.outText("Static object detected.", 30) end 
		-- static objects have no group 		
		local staticName 
		if victim.getName then staticName = victim:getName() -- on statics, this returns 
		else staticName = "*?*" end 
		-- name as entered in TOP LINE
		local staticScore = cfxPlayerScore.object2score(victim, killSide)

		if staticScore > 0 then 
			-- this was a named static, return the score - unless our own
			-- we IGNORE neutral object kills here
			if fraternicide then 
				scoreMod = cfxPlayerScore.ffMod * scoreMod -- blue on blue static kill
				trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.badSound)
			else 
				trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.scoreSound)
			end
			staticScore = scoreMod * staticScore
			cfxPlayerScore.logKillForPlayer(killerName, victim)
			cfxPlayerScore.awardScoreTo(killSide, staticScore, killerName, nil)
		else 
			-- no score, no mentions
		end
		if not fraternicide then cfxPlayerScore.checkKillFeat(killerName, killer, victim, false) end 		
		if victim.getName and victim:getName() then cfxPlayerScore.damaged[victim:getName()] = nil end
		return 
	end 
	
	local vicGroup = nil 
	local vicCat = nil
	if victim.getGroup then vicGroup = victim:getGroup() end 
	if not vicGroup and victim.getName and victim:getName() then 
		vicCat = cfxMX.spawnedUnitCatByName[victim:getName()]
		if cfxPlayerScore.verbose then trigger.action.outText("re-constitued cat for group", 30) end 
	else 
		if vicGroup.getCategory then vicCat = vicGroup:getCategory() end 
	end
	if not vicCat then 
		trigger.action.outText("+++scr: strange stuff:group, outta here", 30)
		return 
	end 

	local unitScore = cfxPlayerScore.unit2score(victim)	
	if pk then -- player kill - add player's name 
		vicDesc = victim:getPlayerName() .. " in " .. vicDesc 
		scoreMod = scoreMod * cfxPlayerScore.pkMod
	end 
	
	-- if fratricide, times ffMod (friedlyFire) 
	if fraternicide then
		scoreMod = scoreMod * cfxPlayerScore.ffMod 
		if cfxPlayerScore.announcer then 
			trigger.action.outTextForCoalition(killSide, killerName .. " in " .. killVehicle .. " killed FRIENDLY " .. vicDesc .. "!", 30)
			trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.badSound)
		end 
	elseif neutralKill then 
		if cfxPlayerScore.verbose then trigger.action.outText("Will apply neutral mod: " .. cfxPlayerScore.nMod, 30) end
		scoreMod = scoreMod * cfxPlayerScore.nMod -- neutral mod
		local neuStat = ""
		if cfxPlayerScore.nMod < 1 then neuStat = " ILLEGALLY" end
		if cfxPlayerScore.announcer then 
			trigger.action.outTextForCoalition(killSide, killerName .. " in " .. killVehicle .. neuStat.. " killed NEUTRAL " .. vicDesc .. "!", 30)
			trigger.action.outSoundForCoalition(killSide, cfxPlayerScore.badSound)
			-- no individual logging of kill
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
		if cfxPlayerScore.announcer then trigger.action.outTextForCoalition(killSide, killerName .. " reports killing strategic unit '" .. victim:getName() .. "'", 30) end 
	end
	local totalScore = unitScore * scoreMod
	-- if the score is negative, awardScoreTo will automatically
	-- make it immediate, else depending on deferred 
	cfxPlayerScore.awardScoreTo(killSide, totalScore, killerName, pk)
	if not fraternicide or neutralKill then 
		-- only award kill feats for kills of the enemy
		cfxPlayerScore.checkKillFeat(killerName, killer, victim, false)
	end 
	
	-- erase damaged if present 
	if victim.getName and victim:getName() then cfxPlayerScore.damaged[victim:getName()] = nil end
end

function cfxPlayerScore.handlePlayerLanding(theEvent)
	local thePlayerUnit = theEvent.initiator
	local theLoc = thePlayerUnit:getPoint() 	
	local playerSide = thePlayerUnit:getCoalition()
	local playerName = thePlayerUnit:getPlayerName()
	if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: Player <" .. playerName .. "> landed", 30) end
	local theScore = cfxPlayerScore.getPlayerScore(playerName)
	-- see if a feat is available for this landing 
	local landingFeats = cfxPlayerScore.featsForLocation(playerName, theLoc, playerSide,"LANDING")	
	-- check if landing is awardable
	if cfxPlayerScore.landing > 0 or #landingFeats > 0 then 
		-- yes, landings are awarded a score. do it
		desc = "Landed"
		if #landingFeats > 0 then 
			-- use the feat description
			-- we may want to use closest, currently simply the first 
			theFeatZone = landingFeats[1]
			desc = cfxPlayerScore.evalFeatDescription(playerName, theFeatZone, thePlayerUnit) -- nil victim, defaults to player 
		else 
			if theEvent.place then desc = desc .. " successfully (" .. theEvent.place:getName() .. ")"
			else desc = desc .. " aircraft"
			end
		end 
		cfxPlayerScore.updateScoreForPlayer(playerName, cfxPlayerScore.landing, "LAND", nil)
		cfxPlayerScore.logFeatForPlayer(playerName, desc, playerSide)
		theScore = cfxPlayerScore.getPlayerScore(playerName) -- re-read after write
		if cfxPlayerScore.verbose then trigger.action.outText("Landing feat awarded/queued for <" .. playerName .. ">", 30) end
	end
	-- see if we are using deferred scoring, else can end right now 
	if not cfxPlayerScore.isDeferred(playerName) then return end
	-- only continue if there is anything to award 
	local killSize = dcsCommon.getSizeOfTable(theScore.killQueue)
	local featSize = dcsCommon.getSizeOfTable(theScore.featQueue)
	if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: prepping deferred score for <" .. playerName ..">", 30) end
	
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
					if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: Zone <" .. theZone.name .. ">: owner=<" .. theZone.owner .. ">, my coa=<" .. coa .. ">, LANDED SAFELY", 30) end
				end
			else 
				if cfxPlayerScore.verbose and cfxZones.pointInZone(loc, theZone) then trigger.action.outText("+++pScr: Zone <" .. theZone.name .. ">: owner=<" .. theZone.owner .. ">, player unit <" .. theUnit:getName() .. ">, my coa=<" .. coa .. ">, no owner match", 30) end
			end
		end 
	end
	if not isSafe then 
		if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: deferred, but not inside score safe zone.", 30) end
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
	if not theUnit or (not Unit.isExist(theUnit)) then 
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
			if cfxZones.pointInZone(loc, theZone) then isSafe = true end
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
		-- player changed planes or there was nothing to award 
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
	if cfxPlayerScore.verbose then trigger.action.outText("Iterating kill q <" .. dcsCommon.getSizeOfTable(theScore.killQueue) .. "> and feat q <" .. dcsCommon.getSizeOfTable(theScore.featQueue) .. ">", 30) end
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
	if cfxPlayerScore.reportCoalition then desc = desc .. "\nCoalition Total: " .. cfxPlayerScore.coalitionScore[playerSide] end
	-- output score 
	desc = desc .. "\n"
	if hasAward then trigger.action.outTextForCoalition(coa, desc, 30) end 
	-- do NOT kill the entire record, or accu kills and feats are gone too
end

function cfxPlayerScore.handlePlayerDeath(theEvent)
	-- multiple of these events can occur per player 
	-- so we use the unit2player link to see player 
	-- is affected, and if so, erase the link so it 
	-- only counts once 
	local theUnit = theEvent.initiator 
	local uName = theUnit:getName()
	if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: LOA/player death handler entry for <" .. uName .. ">", 30) end
	local pName = cfxPlayerScore.unit2player[uName] 
	if pName then 
		-- this was a player name with link still live.
		-- cancel all scores accumulated 
		cfxPlayerScore.wipeScore(pName)
		
		if cfxPlayerScore.planeLoss ~= 0 then 
			-- plane loss has IMMEDIATE consequences 
			cfxPlayerScore.updateScoreForPlayerImmediate(pName, cfxPlayerScore.planeLoss, "CRASH", nil)
			if cfxPlayerScore.announcer then 
				local uid = theUnit:getID()
				local thePlayerRecord = cfxPlayerScore.getPlayerScore(pName)
				trigger.action.outTextForUnit(uid, "Loss of aircraft detected: " .. cfxPlayerScore.planeLoss .. " awarded immediately, for new total of " .. thePlayerRecord.score, 30)
			end
		end
		-- always clear the link.
		cfxPlayerScore.unit2player[uName] = nil
	else 
		if cfxPlayerScore.verbose then trigger.action.outText("+++pScr - no action for LOA", 30) end
	end
end

--
-- event detection 
--
function cfxPlayerScore.isScoreEvent(theEvent)
	-- return true if the event results in a score event
	if not theEvent.initiator then return false end 
	if cfxPlayerScore.verbose then 
		trigger.action.outText("Event preproc: " .. theEvent.id .. " (" .. dcsCommon.event2text(theEvent.id) .. ")", 30)
		if theEvent.id == 8 or theEvent.id == 30 then -- dead or lost event 
			local who = theEvent.initiator
			local name = "(nil ini)"
			if who then 
				name = "(inval object)"
				if who.getName then name = who:getName() end 
			end 
			trigger.action.outText("Dead/Lost subject: <" .. name .. ">", 30)
			if cfxPlayerScore.damaged[name] then trigger.action.outText("we have player UNIT <" .. cfxPlayerScore.damaged[name] .. "> signed up for damage", 30) end
		end 
		if theEvent.id == 2 or theEvent.id == 28 then -- hit or kill
			local who = theEvent.initiator
			local name = "(nil ini)"
			if who then 
				name = "(inval initi)"
				if who.getName then name = who:getName() end 
				if not name or (#name < 1) then -- WTF??? could be a weapon 
					name = "!no getName!"
					if who.getTypeName then name = who:getTypeName() end 
					if not name or (#name < 1) then name = "WTFer" end
				end
			end
			
			local hit = theEvent.target -- !! 
			local hname = "(nil ini)"
			if hit then 
				hname = "(inval object)"
				if hit.getName then hname = hit:getName() end 
			end
			trigger.action.outText("o:<" .. name .. "> hit <" .. hname .. ">", 30)
		end
	end 
	
	-- a hit event will save the last player to hit 
	-- so we can attribute with unit lost 
	if theEvent.id == 2 then -- hit processing
		local who = theEvent.initiator
		if not who then return false end -- more hardening 
		if not Unit.isExist(who) then return end -- harder! harder!
		if not who.getPlayerName then return false end -- non-player originator
		local pName = who:getPlayerName() 
		if not pName then return false end -- non-player origin
		local what = theEvent.target
		if not what then return false end 
		if not what.getName then return false end -- safety check 
		local tName = what:getName() 
		if not tName then return false end -- more sanity 
		-- note down last damager 
		cfxPlayerScore.damaged[tName] = who:getName() -- player's unit gets credit via unit name
		if cfxPlayerScore.verbose then trigger.action.outText("player <" .. pName .. "> noted for <" .. tName .. "> hit", 30) end
		return 
	end
	
	-- check if this was FORMERLY a player plane 
	local theUnit = theEvent.initiator 
	if not theUnit.getName then 
--		trigger.action.outText("+++pScr: no unit name, DCS err - abort.", 30)
		return false 
	end -- fix for DCS update bug 
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
			-- event does NOT have a player
			cfxPlayerScore.handlePlayerDeath(theEvent)
			return false -- false = no score event (any more)
	    end 
	end

	-- unit lost, and can't be player because we filtered above
	if theEvent.id == 30 then
--		trigger.action.outText("enter UNIT LOSS preproc", 30)
		-- check if there was a player who damaged this 
		-- unit and award player if there is one in that unit 
		local who = theEvent.initiator 
		if not who then return false end 
		if not who.getName then return false end 
		local unitName = who:getName()
		if not unitName then return false end 
		if not cfxPlayerScore.damaged[unitName] then return false end 
		-- rebuild unit to credit kill to 
		local killingUnitName = cfxPlayerScore.damaged[unitName]
		cfxPlayerScore.damaged[unitName] = nil -- clear entry 
		local theUnit = Unit.getByName(killingUnitName)
		if theUnit and Unit.isExist(theUnit) and theUnit.getPlayerName and theUnit:getPlayerName() then 
			-- credit unit and current person driving that unit
			-- there is a small percentage that this is wrong 
			-- player, but that's an edge case 
			-- if no player inhabits killing unit any more, no score attributed 
			cfxPlayerScore.processKill(theUnit, who)
		end
		return false 
	end
	
	-- from here on, initiator must be player 
	if (not theUnit.getPlayerName) or  
	   (not Unit.isExist(theUnit)) or 
	   (not theUnit:getPlayerName()) then 
	   return false 
	end 
	
	if theEvent.id == 28 then -- kill, but only with target
		local killer = theEvent.initiator 
		if not theEvent.target then 
			if cfxPlayerScore.verbose then trigger.action.outText("+++scr kill nil TARGET", 30) end 
			return false 
		end 
		-- if there are kill zones, we filter all kills that happen outside of kill zones 
		if #cfxPlayerScore.killZones > 0 then
			local pLoc = theUnit:getPoint() 
			local tLoc = theEvent.target:getPoint()
			local isIn, percent, dist, theZone = cfxZones.pointInOneOfZones(tLoc, cfxPlayerScore.killZones)
			if not isIn then 
				if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: kill detected, but target <" .. theEvent.target:getName() .. "> was outside of any kill zones", 30) end
				return false 
			end
			if theZone.duet and not cfxZones.pointInZone(pLoc, theZone) then 
				-- player must be in same zone but was not
				if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: kill detected, but player <" .. theUnit:getPlayerName() .. "> was outside of kill zone <" .. theZone.name .. ">", 30) end
				return false
			end			
		end
		return true -- do post-proccing 
	end
	
	-- enter unit / birth event for players initializes score if 
	-- not existed, and nils the queue. 20 creates compat with CA  
	if theEvent.id == 20 or -- enter unit 
		theEvent.id == 15 then -- player birth
		-- since we get into a new plane, erase all pending score 
		local pName = theUnit:getPlayerName()
		cfxPlayerScore.wipeScore(pName)
		-- link player with their unit
		cfxPlayerScore.linkUnitWithPlayer(theUnit)
		cfxPlayerScore.unitSpawnTime[uName] = timer.getTime() -- to detect 'early landing' 
		return true -- do post-proccing
	end
	
	-- take off. overwrites timestamp for last landing 
	-- so a blipping t/o does nor count. Pre-proc only 
	if theEvent.id == 3 or theEvent.id == 54 then 
		local now = timer.getTime()
		local playerName = theUnit:getPlayerName() 
		cfxPlayerScore.lastPlayerLanding[playerName] = now -- overwrite 
		return false 
	end
	
	-- landing can score. but only the first landing in x seconds
	-- and has spawned more than 10 seconds before 
	-- landing in safe zone promotes any queued scores to 
	-- permanent if enabled, then nils queue
	if theEvent.id == 4 or theEvent.id == 55 then
		-- player landed. filter multiple landed events
		local now = timer.getTime()
		local playerName = theUnit:getPlayerName() 
		-- if player spawns on ground, DCS now can post a 
		-- "landing" event. filter 
		if cfxPlayerScore.unitSpawnTime[uName] and 
			now - cfxPlayerScore.unitSpawnTime[uName] < 10 
		then 
			cfxPlayerScore.lastPlayerLanding[playerName] = now -- just for the sake of it 
			return false 
		end 		
		local lastLanding = cfxPlayerScore.lastPlayerLanding[playerName]
		cfxPlayerScore.lastPlayerLanding[playerName] = now -- overwrite 
		if lastLanding and lastLanding + cfxPlayerScore.delayBetweenLandings > now then 
			if cfxPlayerScore.verbose then 
				trigger.action.outText("+++pScr: Player <" .. playerName .. "> touch-down ignored: too soon after last.", 30)
				trigger.action.outText("now is <" .. now .. ">, between is <" .. cfxPlayerScore.delayBetweenLandings .. ">, last + between is <" .. lastLanding + cfxPlayerScore.delayBetweenLandings .. ">", 30)
			end 
			-- filter this event, too soon 
			return false 
		end
		return true -- why true?
	end
	return false 
end

function cfxPlayerScore:onEvent(theEvent)
	if cfxPlayerScore.isScoreEvent(theEvent) then 
		cfxPlayerScore.handleScoreEvent(theEvent)
	end 
end 

function cfxPlayerScore.handleScoreEvent(theEvent)
	cfxPlayerScore.currentEventUnit = theEvent.initiator 
	if cfxPlayerScore.verbose then trigger.action.outText("Set currentEventUnit to <" .. theEvent.initiator:getName() .. ">", 30) end 
	if theEvent.id == 28 then 
		-- kill from player detected.
		cfxPlayerScore.killDetected(theEvent)	
	elseif theEvent.id == 20 or -- enter unit 
		   theEvent == 15 then -- birth 
		-- access player score for player. this will 
		-- allocate if doesn't exist. Any player ever 
		-- birthed will be in db
		local thePlayerUnit = theEvent.initiator 
		local playerSide = thePlayerUnit:getCoalition()
		local playerName = thePlayerUnit:getPlayerName()
		local theScore = cfxPlayerScore.getPlayerScore(playerName)
		-- now re-init feat and score queues 
		if theScore.scoreaccu and theScore.scoreaccu > 0 then trigger.action.outTextForCoalition(playerSide, "Player " .. playerName .. ", score of <" .. theScore.scoreaccu .. "> points discarded.", 30) end 
		theScore.scoreaccu = 0 
		if dcsCommon.getSizeOfTable(theScore.killQueue) > 0 then trigger.action.outTextForCoalition(playerSide, "Player " .. playerName .. ", <" .. dcsCommon.getSizeOfTable(theScore.killQueue) .. "> kills discarded.", 30) end
		theScore.killQueue = {}
		if dcsCommon.getSizeOfTable(theScore.featQueue) > 0 then trigger.action.outTextForCoalition(playerSide, "Player " .. playerName .. ", <" .. dcsCommon.getSizeOfTable(theScore.featQueue) .. "> feats discarded.", 30) end		
		theScore.featQueue = {}
		-- write back
		cfxPlayerScore.setPlayerScore(playerName, theScore)
		
	elseif theEvent.id == 4 or theEvent.id == 55 then -- land 
		-- see if plane is still connected to player 
		local theUnit = theEvent.initiator
		if not theUnit.getName then return end -- dcs oddity precaution 
		local uName = theUnit:getName() 
		if cfxPlayerScore.unit2player[uName] then 
			-- is filtered if too soon after last take-off/landing 
			cfxPlayerScore.handlePlayerLanding(theEvent)
		else 
			if verbose then trigger.action.outText("+++pScr: filtered landing for <" .. uName .. ">: player no longer linked to unit", 30) end
		end	
	end
end
--
-- Config handling 
--
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
	cfxPlayerScore.nMod = theZone:getNumberFromZoneProperty("nMod", 1) -- factor for neutral kill. Should be -100, defaults to 1
	cfxPlayerScore.planeLoss = theZone:getNumberFromZoneProperty("planeLoss", -10) -- points added when player's plane crashes
	cfxPlayerScore.announcer = theZone:getBoolFromZoneProperty("announcer", true)
	cfxPlayerScore.badSound = theZone:getStringFromZoneProperty("badSound", "Death BRASS.wav")
	cfxPlayerScore.scoreSound = theZone:getStringFromZoneProperty("scoreSound", "Quest Snare 3.wav")
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
	cfxPlayerScore.deferredScore = theZone:getBoolFromZoneProperty("deferred", false)
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
	if theZone:hasProperty("sharedData") then cfxPlayerScore.sharedData = theZone:getStringFromZoneProperty("sharedData", "cfxNameMissing") end 
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
		if cfxPlayerScore.verbose then trigger.action.outText("+++playerscore: no save data received, skipping.", 30) end
		return
	end
	
	local theScore = theData.theScore
	cfxPlayerScore.playerScore = theScore 
	if theData.coalitionScore then cfxPlayerScore.coalitionScore = theData.coalitionScore end
	if cfxPlayerScore.redScoreOut then cfxZones.setFlagValue(cfxPlayerScore.redScoreOut, cfxPlayerScore.coalitionScore[1], cfxPlayerScore) end
	if cfxPlayerScore.blueScoreOut then cfxZones.setFlagValue(cfxPlayerScore.blueScoreOut, cfxPlayerScore.coalitionScore[2], cfxPlayerScore) end
	
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
		if cfxPlayerScore.firstSave then theText = "\n*** NEW MISSION started.\n" .. theText end
		-- prepend time for score 
		theText = "\n\n====== Mission Time: " .. dcsCommon.nowString() .. "\n" .. theText
	end 
	
	if persistence.saveText(theText, name, shared, append) then 
		if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: scores saved to <" .. persistence.missionDir .. name .. ">", 30) end
	else trigger.action.outText("+++pScr: unable to save scores to <" .. persistence.missionDir .. name .. ">") end
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
			if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: saving scores...", 30) end
			cfxPlayerScore.saveScoreToFile()
		end
	end
	-- showScore perhaps?
	if cfxPlayerScore.showScore then 
		if cfxZones.testZoneFlag(cfxPlayerScore, cfxPlayerScore.showScore, "change", "lastShowScore") then 
			if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: showing scores...", 30) end
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
					if cfxPlayerScore.announcer then trigger.action.outTextForCoalition(coa, "Transferred §" .. amount .. " to funds.", 30) end
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
				if cfxPlayerScore.announcer then
					trigger.action.outTextForCoalition(coa, "RED goal [" .. tName .. "] achieved, new RED coalition score is " .. cfxPlayerScore.coalitionScore[coa], 30)
					trigger.action.outSoundForCoalition(coa, cfxPlayerScore.scoreSound)
				end
				-- bank it if exists
				local amount 
				if bank and bank.addFunds then 
					amount = cfxPlayerScore.score2finance * cfxPlayerScore.redTriggerScore[tName]
					bank.addFunds(coa, amount)
					if cfxPlayerScore.announcer then trigger.action.outTextForCoalition(coa, "Transferred §" .. amount .. " to funds.", 30) end
				end 
			end
		end
	end
	-- set output flags if they are set 
	if cfxPlayerScore.redScoreOut then cfxZones.setFlagValue(cfxPlayerScore.redScoreOut, cfxPlayerScore.coalitionScore[1], cfxPlayerScore) end
	if cfxPlayerScore.blueScoreOut then cfxZones.setFlagValue(cfxPlayerScore.blueScoreOut, cfxPlayerScore.coalitionScore[2], cfxPlayerScore) end
end
--
-- start
--
function cfxPlayerScore.start()
	if not dcsCommon.libCheck("cfx Player Score", cfxPlayerScore.requiredLibs) 
	then return false end
	
	-- only read verbose flag 
	-- now read my config zone 
	local theZone = cfxZones.getZoneByName("playerScoreConfig") 
	if theZone then cfxPlayerScore.verbose = theZone.verbose end 
	
	-- read my score table 
	-- identify and process a score table zones
	local theZone = cfxZones.getZoneByName("playerScoreTable") 
	if theZone then 
		if cfxPlayerScore.verbose then trigger.action.outText("+++pScr: has playerSocreTable", 30) end 
		-- read all into my types registry, replacing whatever is there
		cfxPlayerScore.typeScore = theZone:getAllZoneProperties(true) -- true = get all properties in UPPER case 
		-- CASE INSENSITIVE!!!!!
		-- now process all wildcarded types and add them to my wildTypes
		cfxPlayerScore.wildTypes = {}
		for theType, theScore in pairs(cfxPlayerScore.typeScore) do 
			if dcsCommon.stringEndsWith(theType, "*") then 
				local wcType = dcsCommon.removeEnding(theType, "*")
				cfxPlayerScore.wildTypes[wcType] = theScore
				if cfxPlayerScore.verbose then 
					trigger.action.outText("+++PScr: wildcard type/name <" .. wcType .. "> with score <" .. theScore .. "> registered", 30)
				end
			end
		end 
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
			if tScore == 0 then trigger.action.outText("+++pScr: WARNING - BLUE triggered score <" .. tName .. "> has zero score value!", 30) end		
			cfxPlayerScore.blueTriggerFlags[tName] = trigger.misc.getUserFlag(tName)
		end
	end 	
	-- now read my config zone. reading late 
	local theZone = cfxZones.getZoneByName("playerScoreConfig") 
	if not theZone then theZone = cfxZones.createSimpleZone("playerScoreConfig") end 
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
	if cfxPlayerScore.deferredScore and dcsCommon.getSizeOfTable(cfxPlayerScore.safeZones) < 1 then 
		trigger.action.outText("+++pScr: WARNING - deferred scoring active but no 'scoreSafe' zones set!", 30)
	end

	world.addEventHandler(cfxPlayerScore)
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
 