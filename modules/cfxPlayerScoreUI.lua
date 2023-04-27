cfxPlayerScoreUI = {}
cfxPlayerScoreUI.version = "2.0.0"
cfxPlayerScoreUI.verbose = false 

--[[-- VERSION HISTORY
 - 1.0.2 - initial version 
 - 1.0.3 - module check
 - 2.0.0 - removed cfxPlayer dependency, handles own commands
--]]--

cfxPlayerScoreUI.rootCommands = {} -- by unit's group name, for player aircraft

-- redirect: avoid the debug environ of missionCommand
function cfxPlayerScoreUI.redirectCommandX(args)
	timer.scheduleFunction(cfxPlayerScoreUI.doCommandX, args, timer.getTime() + 0.1)
end

function cfxPlayerScoreUI.doCommandX(args)
	local groupName = args[1] 
	local playerName = args[2]
	local what = args[3] -- "score" or other commands
	local theGroup = Group.getByName(groupName)
	local gid = theGroup:getID()
	
	if not cfxPlayerScore.scoreTextForPlayerNamed then 
		trigger.action.outText("***pSGui: CANNOT FIND PlayerScore MODULE", 30)
		return 
	end
	local desc = cfxPlayerScore.scoreTextForPlayerNamed(playerName)
	trigger.action.outTextForGroup(gid, desc, 30)
	trigger.action.outSoundForGroup(gid, "Quest Snare 3.wav")
end

--
-- event handling: we are only interested in birth events
-- for player aircraft 
--
function cfxPlayerScoreUI:onEvent(event)
	if event.id ~= 15 then return end -- only birth 
	if not event.initiator then return end -- no initiator, no joy 
	local theUnit = event.initiator 
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
	local theCommand =  missionCommands.addCommandForGroup(
			gid, 
			commandTxt,
			nil, -- root level 
			cfxPlayerScoreUI.redirectCommandX, 
			{groupName, playerName, "score"}
		)
	cfxPlayerScoreUI.rootCommands[groupName] = theCommand 
	
	if cfxPlayerScoreUI.verbose then 
		trigger.action.outText("++pSGui: installed player score menu for group <" .. groupName .. ">", 30)
	end
end

--
-- Start 
--
function cfxPlayerScoreUI.start()	
	-- install the event handler for new player planes
	world.addEventHandler(cfxPlayerScoreUI)
	
	trigger.action.outText("cf/x cfxPlayerScoreUI v" .. cfxPlayerScoreUI.version .. " started", 30)
	return true 
end

--
-- GO GO GO 
--
if not cfxPlayerScoreUI.start() then 
	cfxPlayerScoreUI = nil
	trigger.action.outText("cf/x PlayerScore UI aborted: missing libraries", 30)
end
