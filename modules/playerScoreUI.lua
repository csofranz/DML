cfxPlayerScoreUI = {}
cfxPlayerScoreUI.version = "3.1.0"

--[[-- VERSION HISTORY
 - 3.0.0 - compatible with dynamic groups/units in DCS 2.9.6 
 - 3.0.1 - more hardening 
 - 3.1.0 - CA support
		 - playerScoreUI correct ion for some methods 
		 - config zone support, attributes allowAll, soundFile, ranked  
		 - attachTo: support 
--]]--
cfxPlayerScoreUI.requiredLibs = {
	"dcsCommon", -- this is doing score keeping
	"cfxZones", -- zones for config 
	"cfxPlayerScore",
}
cfxPlayerScoreUI.rootCommands = {} -- by unit's GROUP name, for player aircraft. stores command roots 

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
	if what == "score" then desc = cfxPlayerScore.scoreTextForPlayerNamed(playerName)
	elseif what == "allMySide" then desc = cfxPlayerScore.scoreSummaryForPlayersOfCoalition(coa)
	elseif what == "all" then 
		desc = "Score Table For All Players:\n" .. cfxPlayerScore.scoreTextForAllPlayers(cfxPlayerScoreUI.ranked) 
	else desc = "PlayerScore UI: unknown command <" .. what .. ">"
	end 
	trigger.action.outTextForGroup(gid, desc, 30)
	trigger.action.outSoundForGroup(gid, cfxPlayerScoreUI.soundFile)
end

--
-- event handling: we are only interested in birth events
-- for player aircraft 
--
function cfxPlayerScoreUI.processPlayerUnit(theUnit)
	if not theUnit.getPlayerName then return end -- no player name, bye!
	local playerName = theUnit:getPlayerName()
	if not playerName then return end 
	-- now we know it's a player unit. get group name 
	local theGroup = theUnit:getGroup()
	local groupName = theGroup:getName() 
	local gid = theGroup:getID()
	-- handle main menu 
	local mainMenu = nil 
	if cfxPlayerScoreUI.mainMenu then 
		mainMenu = radioMenu.getMainMenuFor(cfxPlayerScoreUI.mainMenu) 
	end 
	-- see if this group already has a score command 
	if cfxPlayerScoreUI.rootCommands[groupName] then 
		-- need re-init to store new pilot name 
		if cfxPlayerScoreUI.verbose then trigger.action.outText("++pSGui: group <" .. groupName .. "> already has score menu, removing.", 30) end
		missionCommands.removeItemForGroup(gid, cfxPlayerScoreUI.rootCommands[groupName]) 
		cfxPlayerScoreUI.rootCommands[groupName] = nil 
	end
	-- we install a group menu item for scores. 
	local commandTxt = "Show Score / Kills"
	local theMenu = missionCommands.addSubMenuForGroup(gid, cfxPlayerScoreUI.menuName, mainMenu)
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
	if event.id ~= 20 and -- S_EVENT_PLAYER_ENTER_UNIT -- CA support
	   event.id ~= 15 then return end -- birth 
	if not event.initiator then return end -- no initiator, no joy 
	local theUnit = event.initiator 
	cfxPlayerScoreUI.processPlayerUnit(theUnit)
end

function cfxPlayerScoreUI.readConfig()
	cfxPlayerScoreUI.name = "playerScoreUIConfig"
	local theZone = cfxZones.getZoneByName("playerScoreUIConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("playerScoreUIConfig") 
	end 
	if theZone:hasProperty("attachTo:") then 
		local attachTo = theZone:getStringFromZoneProperty("attachTo:", "<none>")
		if radioMenu then -- requires optional radio menu to have loaded 
			local mainMenu = radioMenu.mainMenus[attachTo]
			if mainMenu then cfxPlayerScoreUI.mainMenu = mainMenu 
			else trigger.action.outText("+++PlayerScoreUI: cannot find super menu <" .. attachTo .. ">", 30) end
		else 
			trigger.action.outText("+++PlayerScoreUI: REQUIRES radioMenu to run before PlayerScoreUI. 'AttachTo:' ignored.", 30)
		end 
	end 
	cfxPlayerScoreUI.menuName = theZone:getStringFromZoneProperty("menuName", "Show Score")
	cfxPlayerScoreUI.soundFile = theZone:getStringFromZoneProperty("SoundFile", "Quest Snare 3.wav")
	cfxPlayerScoreUI.allowAll = theZone:getBoolFromZoneProperty("allowAll", true) 
	cfxPlayerScoreUI.ranked = theZone:getBoolFromZoneProperty("ranked", true) 
	cfxPlayerScoreUI.verbose = theZone.verbose 
end
--
-- Start 
--
function cfxPlayerScoreUI.start()	
	if not dcsCommon.libCheck("cfx Player Score UI", 						  cfxPlayerScoreUI.requiredLibs) then return false end
	-- install event handler for new player planes and CA 
	world.addEventHandler(cfxPlayerScoreUI)
	cfxPlayerScoreUI.readConfig()
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
