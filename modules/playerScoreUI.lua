cfxPlayerScoreUI = {}
cfxPlayerScoreUI.version = "3.0.1"
cfxPlayerScoreUI.verbose = false 

--[[-- VERSION HISTORY
 - 1.0.2 - initial version 
 - 1.0.3 - module check
 - 2.0.0 - removed cfxPlayer dependency, handles own commands
 - 2.0.1 - late start capability 
 - 2.1.0 - soundfile cleanup 
         - score summary for side 
		 - allowAll
 - 2.1.1 - minor cleanup 
 - 3.0.0 - compatible with dynamic groups/units in DCS 2.9.6 
 - 3.0.1 - more hardening 
		 
--]]--
cfxPlayerScoreUI.requiredLibs = {
	"dcsCommon", -- this is doing score keeping
	"cfxZones", -- zones for config 
	"cfxPlayerScore",
}
cfxPlayerScoreUI.soundFile = "Quest Snare 3.wav"
cfxPlayerScoreUI.rootCommands = {} -- by unit's GROUP name, for player aircraft. stores command roots 
cfxPlayerScoreUI.allowAll = true 
cfxPlayerScoreUI.ranked = true 

-- redirect: avoid the debug environ of missionCommands
function cfxPlayerScoreUI.redirectCommandX(args)
	timer.scheduleFunction(cfxPlayerScoreUI.doCommandX, args, timer.getTime() + 0.1)
end

function cfxPlayerScoreUI.doCommandX(args)
	local groupName = args[1] 
	local playerName = args[2]
	local what = args[3] -- "score" or other commands
	local theGroup = Group.getByName(groupName)
	if not theGroup then return end -- should not happen 
	local gid = theGroup:getID()
	local coa = theGroup:getCoalition()
	
	if not cfxPlayerScore.scoreTextForPlayerNamed then 
		trigger.action.outText("***pSGUI: CANNOT FIND PlayerScore MODULE", 30)
		return 
	end
	local desc = ""
	if what == "score" then 
		desc = cfxPlayerScore.scoreTextForPlayerNamed(playerName)
	elseif what == "allMySide" then 
		desc = cfxPlayerScore.scoreSummaryForPlayersOfCoalition(coa)
	elseif what == "all" then 
		desc = "Score Table For All Players:\n" .. cfxPlayerScore.scoreTextForAllPlayers(cfxPlayerScoreUI.ranked) 
	else 
		desc = "PlayerScore UI: unknown command <" .. what .. ">"
	end 
	trigger.action.outTextForGroup(gid, desc, 30)
	trigger.action.outSoundForGroup(gid, cfxPlayerScoreUI.soundFile)
end

--
-- event handling: we are only interested in birth events
-- for player aircraft 
--
function cfxPlayerScore.processPlayerUnit(theUnit)
	if not theUnit.getPlayerName then return end -- no player name, bye!
	local playerName = theUnit:getPlayerName()
	if not playerName then return end 
	
	-- so now we know it's a player plane. get group name 
	local theGroup = theUnit:getGroup()
	local groupName = theGroup:getName() 
	local gid = theGroup:getID()
	
	-- see if this group already has a score command 
	if cfxPlayerScoreUI.rootCommands[groupName] then 
		-- need re-init to store new pilot name 
		if cfxPlayerScoreUI.verbose then 
			trigger.action.outText("++pSGui: group <" .. groupName .. "> already has score menu, removing.", 30)
		end
		missionCommands.removeItemForGroup(gid, cfxPlayerScoreUI.rootCommands[groupName]) 
		cfxPlayerScoreUI.rootCommands[groupName] = nil 
	end
	
	-- we need to install a group menu item for scores. 
	-- will persist through death
	local commandTxt = "Show Score / Kills"
	local theMenu = missionCommands.addSubMenuForGroup(gid, "Show Score", nil)
	local theCommand =  missionCommands.addCommandForGroup(gid, commandTxt, theMenu, cfxPlayerScoreUI.redirectCommandX,	{groupName, playerName, "score"})
	
	commandTxt = "Show my Side Score / Kills"
	theCommand =  missionCommands.addCommandForGroup(gid, commandTxt, theMenu, cfxPlayerScoreUI.redirectCommandX, {groupName, playerName, "allMySide"})

	if cfxPlayerScoreUI.allowAll then 
		commandTxt = "Show All Player Scores"
		theCommand =  missionCommands.addCommandForGroup(gid, commandTxt, theMenu, cfxPlayerScoreUI.redirectCommandX, {groupName, playerName, "all"})
	end

	cfxPlayerScoreUI.rootCommands[groupName] = theMenu 
	
	if cfxPlayerScoreUI.verbose then 
		trigger.action.outText("++pSGui: installed player score menu for group <" .. groupName .. ">", 30)
	end
end

function cfxPlayerScoreUI:onEvent(event)
	if event.id ~= 15 then return end -- only birth 
	if not event.initiator then return end -- no initiator, no joy 
	local theUnit = event.initiator 
	cfxPlayerScore.processPlayerUnit(theUnit)
end

--
-- Start 
--
function cfxPlayerScoreUI.start()	
	if not dcsCommon.libCheck("cfx Player Score UI", 
							  cfxPlayerScoreUI.requiredLibs) 
	then return false end
	-- install the event handler for new player planes
	world.addEventHandler(cfxPlayerScoreUI)
	-- process all existing players (late start)
	dcsCommon.iteratePlayers(cfxPlayerScore.processPlayerUnit)
	trigger.action.outText("cf/x PlayerScoreUI v" .. cfxPlayerScoreUI.version .. " started", 30)
	return true 
end

--
-- GO GO GO 
--
if not cfxPlayerScoreUI.start() then 
	cfxPlayerScoreUI = nil
	trigger.action.outText("cf/x PlayerScore UI aborted: missing libraries", 30)
end
