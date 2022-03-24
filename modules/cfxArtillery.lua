cfxArtilleryDemon = {}
cfxArtilleryDemon.version = "1.0.3"
-- based on cfx stage demon v 1.0.2
--[[--
	Version History
	1.0.2 - taken from stageDemon
	1.0.3 - corrected 'messageOut' bug 
	
--]]--
cfxArtilleryDemon.messageToAll = true -- set to false if messages should be sent only to the group that set the mark
cfxArtilleryDemon.messageTime = 30 -- how long a message stays on the sceeen

-- cfxArtillery hooks into DCS's mark system to intercept user 
-- transactions with the mark system and uses that for arty targeting
-- used to interactively add ArtilleryZones during gameplay 

-- Copyright (c) 2021 by Christian Franz and cf/x AG

cfxArtilleryDemon.autostart = true -- start automatically

-- whenever you begin a Mark with the string below, it will be taken as a command
-- and run through the command parser, stripping the mark, and then splitting
-- by blanks
cfxArtilleryDemon.markOfDemon = "-" -- all commands must start with this sequence
cfxArtilleryDemon.splitDelimiter = " " 

cfxArtilleryDemon.unitFilterMethod = nil -- optional user filtering redirection. currently
								  -- set to allow all users use cfxArtillery
cfxArtilleryDemon.processCommandMethod = nil -- optional initial command processing redirection
								      -- currently set to cfxArtillery's own processor
cfxArtilleryDemon.commandTable = {} -- key, value pair for command processing per keyword
							 -- all commands cfxArtillery understands are used as keys and
							 -- the functions that process them are used as values
							 -- making the parser a trivial table :)

cfxArtilleryDemon.demonID = nil -- used only for suspending the event callback
						   
-- unit authorization. You return false to disallow this unit access
-- to commands
-- simple authorization checks would be to allow only players
-- on neutral side, or players in range of location with Lino of sight 
-- to that point 
--
function cfxArtilleryDemon.authorizeAllUnits(event) 
	-- units/groups that are allowed to give a command can be filtered.
	-- return true if the unit/group may give commands
	-- cfxArtillery allows anyone to give it commands
	return true
end

function cfxArtilleryDemon.hasMark(theString) 
	-- check if the string begins with the sequece to identify commands 
	if not theString then return false end
	return theString:find(cfxArtilleryDemon.markOfDemon) == 1
end

function cfxArtilleryDemon.splitString(inputstr, sep) 
    if sep == nil then
        sep = "%s"
    end
	if inputstr == nil then 
		inputstr = ""
	end
	
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
		table.insert(t, str)
    end
	return t
end

function cfxArtilleryDemon.str2num(inVal, default) 
	if not default then default = 0 end
	if not inVal then return default end
	if type(inVal) == "number" then return inVal end 				
	local num = nil
	if type(inVal) == "string" then num = tonumber(inVal) end
	if not num then return default end
	return num
end

-- 
-- output method. can be customized, so we have a central place where we
-- can control how output is handled. Is currently outText and outTextToGroup
-- 
function cfxArtilleryDemon.outMessage(theMessage, args)
	if not args then 
		args = {}
	end
	local toAll = args.toAll -- will only be true if defined and set to true
		
	if not args.group then 
		toAll = true
	else 
		if not args.group:isExist() then 
			toAll = true
		end
	end
	toAll = toAll or cfxArtilleryDemon.messageToAll
	if not toAll then 
		trigger.action.outTextToGroup(args.group, theMessage, cfxArtilleryDemon.messageTime)
	else 
		trigger.action.outText(theMessage, cfxArtilleryDemon.messageTime)
	end
end

--
-- get all player groups - since there is no getGroupByIndex in DCS (yet)
-- we simply collect all player groups (since only palyers can place marks)
-- and try to match their group ID to the one given by mark
function cfxArtilleryDemon.getAllPayerGroups()
	local coalitionSides = {0, 1, 2} -- we currently have neutral, red, blue
	local playerGroups = {}
	for i=1, #coalitionSides do 
		local theSide = coalitionSides[i] 
		-- get all players for this side
		local thePlayers = coalition.getPlayers(theSide) 
		for p=1, #thePlayers do 
			aPlayerUnit = thePlayers[p] -- docs say this is a unit table, not a person!
			if aPlayerUnit:isExist() then 
				local theGroup = aPlayerUnit:getGroup()
				if theGroup:isExist() then
					local gID = theGroup:getID()
					playerGroups[gID] = theGroup -- multiple players per group results in one group
				end
			end
		end
	end
	return playerGroups
end

function cfxArtilleryDemon.retrieveGroupFromEvent(theEvent)
-- DEBUG CODE
	if theEvent.initiator then 
		trigger.action.outText("EVENT: initiator set to " .. theEvent.initiator:getName(), 30)
	else 
		trigger.action.outText("EVENT: NO INITIATOR", 30)
	end

	trigger.action.outText("EVENT: groupID = " .. theEvent.groupID, 30)

	-- trivial case: initiator is set, and we can access the group
	if theEvent.initiator then 
		if theEvent.initiator:isExist() then 
			return theEvent.initiator:getGroup()
		end
	end
	
	-- ok, bad news: initiator wasn't filled. let's try the fallback: event.groupID
	if theEvent.groupID  and theEvent.groupID > 0 then 
		local playerGroups = cfxArtilleryDemon.getAllPayerGroups()
		if playerGroups[theEvent.groupID] then 
			return palyerGroups[theEvent.groupID] 
		end
	end
	
	-- nope, return nil
	return nil
end

-- main hook into DCS. Called whenever a Mark-related event happens
-- very simple: look if text begins with special sequence, and if so, 
-- call the command processor. Note that you can hook your own command
-- processor in by changing the value of processCommandMethod
function cfxArtilleryDemon:onEvent(theEvent)
	-- while we can hook into any of the three events, 
	-- we curently only utilize CHANGE Mark
	if not (theEvent.id == world.event.S_EVENT_MARK_ADDED) and
	   not (theEvent.id == world.event.S_EVENT_MARK_CHANGE) and 
	   not (theEvent.id == world.event.S_EVENT_MARK_REMOVED) then 
		-- not of interest for us, bye bye
		return 
	end

	-- build the messageOut() arg table
	local args = {}
	args.toAll = cfxArtilleryDemon.toAll
--
--	
	args.toAll = false -- FORCE GROUPS FOR DEBUGGING OF NEW CODE
--
--	
	if not args.toAll then 
		-- we want group-targeted messaging 
		-- so we need to retrieve the group 
		local theGroup = cfxArtilleryDemon.retrieveGroupFromEvent(theEvent)
		if not theGroup then 
			args.toAll = true
			trigger.action.outText("*** WARNING: cfxArtilleryDemon can't find group for command", 30)
		else 
			args.group = theGroup
		end
	end
	cfxArtilleryDemon.args = args -- copy reference so we can easily use it in messageOut
						   
	-- when we get here, we have a mark event
	-- see if the unit filter lets it pass
	if not cfxArtilleryDemon.unitFilterMethod(theEvent) then 
		return -- unit is not allowed to give demon orders. bye bye
	end
	
    if theEvent.id == world.event.S_EVENT_MARK_ADDED then
		-- add mark is quite useless for us as we are called when the user clicks, with no 
		-- text in the description yet. Later abilities may want to use it though		
	end
    
    if theEvent.id == world.event.S_EVENT_MARK_CHANGE then
		-- when changed, the mark's text is examined for a command
		-- if it starts with the 'mark' string ("*" by  default) it is processed
		-- by the command processor
		-- if it is processed succesfully, the mark is immediately removed
		-- else an error is displayed and the mark remains.
		if cfxArtilleryDemon.hasMark(theEvent.text) then 
			-- strip the mark 
			local commandString = theEvent.text:sub(1+cfxArtilleryDemon.markOfDemon:len())
			-- break remainder apart into <command> <arg1> ... <argn>
			local commands = cfxArtilleryDemon.splitString(commandString, cfxArtilleryDemon.splitDelimiter)

			-- this is a command. process it and then remove it if it was executed successfully
			local success = cfxArtilleryDemon.processCommandMethod(commands, theEvent)
						
			-- remove this mark after successful execution
			if success then 
				trigger.action.removeMark(theEvent.idx) 
				cfxArtilleryDemon.outMessage("executed command <" .. commandString .. "> from unit" .. theEvent.initiator:getName(), args)
			else 
				-- we could play some error sound
			end
		end 
    end 
	
	if theEvent.id == world.event.S_EVENT_MARK_REMOVED then
    end
end

--
-- add / remove commands to/from cfxArtillerys vocabulary
-- 
function cfxArtilleryDemon.addCommndProcessor(command, processor)
	cfxArtilleryDemon.commandTable[command:upper()] = processor 
end

function cfxArtilleryDemon.removeCommandProcessor(command)
	cfxArtilleryDemon.commandTable[command:upper()] = nil 
end

--
-- process input arguments. Here we simply move them 
-- up by one.
--
function cfxArtilleryDemon.getArgs(theCommands) 
	local args = {}
	for i=2, #theCommands do 
		table.insert(args, theCommands[i])
	end
	return args
end

--
-- stage demon's main command interpreter. 
-- magic lies in using the keywords as keys into a 
-- function table that holds all processing functions
-- I wish we had that back in the Oberon days. 
--
function cfxArtilleryDemon.executeCommand(theCommands, event)
--	trigger.action.outText("executor: *" .. theCommands[1] .. "*", 30)
	-- see if theCommands[1] exists in the command table
	local cmd = theCommands[1]
	local arguments = cfxArtilleryDemon.getArgs(theCommands)
	if not cmd then return false end
	
	-- use the command as index into the table of functions
	-- that handle them.
	if cfxArtilleryDemon.commandTable[cmd:upper()] then 
		local theInvoker = cfxArtilleryDemon.commandTable[cmd:upper()]
		local success = theInvoker(arguments, event)
		return success
	else 
		trigger.action.outText("***error: unknown command <".. cmd .. ">", 30)
		return false
	end
	
	return true
end

--
-- SMOKE COMMAND
--

-- known commands and their processors
function cfxArtilleryDemon.smokeColor2Index (theColor)
	local color = theColor:lower()
	if color == "red" then return 1 end
	if color == "white" then return 2 end 
	if color == "orange" then return 3 end 
	if color == "blue" then return 4 end
	return 0
end

-- this is the command processing template for your own commands 
-- when you add a command processor via addCommndProcessor()
-- smoke command syntax: '-smoke <color>' with optional color, color being red, green, blue, white or orange
function cfxArtilleryDemon.processSmokeCommand(args, event)
	if not args[1] then args[1] = "red" end -- default to red color
	local thePoint = event.pos
	thePoint.y = land.getHeight({x = thePoint.x, y = thePoint.z}) +3  -- elevate to ground height
	trigger.action.smoke(thePoint, cfxArtilleryDemon.smokeColor2Index(args[1])) 
	return true
end

--
-- BOOM command
--
function cfxArtilleryDemon.doBoom(args)
	--trigger.action.outText("sim shell str=" .. args.strength .. " x=" .. args.point.x .. " z = " .. args.point.z .. " Tdelta = " .. args.tDelta, 30)
--	trigger.action.smoke(args.point, 2) 
	trigger.action.explosion(args.point, args.strength)

end

function cfxArtilleryDemon.processBoomCommand(args, event)
	if not args[1] then args[1] = "750" end -- default to 750 strength
	local transitionTime = 20 -- seconds until shells hit
	local shellNum = 17 
	local shellBaseStrength = 500
	local shellvariance = 0.2 -- 10% 
	local center = event.pos -- center of where shells hit 
	center.y = land.getHeight({x = center.x, y = center.z}) + 3
	-- we now can 'dirty' the position by something. not yet
	for i=1, shellNum do
		local thePoint = dcsCommon.randomPointInCircle(100, 0, center.x, center.z)
		local boomArgs = {}
		local strVar = shellBaseStrength * shellvariance
		strVar = strVar * (2 * dcsCommon.randomPercent() - 1.0) -- go from -1 to 1
		
		boomArgs.strength = shellBaseStrength + strVar
		thePoint.y = land.getHeight({x = thePoint.x, y = thePoint.z}) + 1  -- elevate to ground height + 1
		boomArgs.point = thePoint
		local timeVar = 5 * (2 * dcsCommon.randomPercent() - 1.0) -- +/- 1.5 seconds
		boomArgs.tDelta = timeVar 
		timer.scheduleFunction(cfxArtilleryDemon.doBoom, boomArgs, timer.getTime() + transitionTime + timeVar)
	end
	trigger.action.outText("Fire command confirmed. Artillery is firing at your designated co-ordinates.", 30)
	trigger.action.smoke(center, 2) -- mark location visually
	return true
end

--
-- cfxArtilleryZones interface
--

function cfxArtilleryDemon.processTargetCommand(args, event)
	-- get position 
	local center = event.pos -- center of where shells hit 
	center.y = land.getHeight({x = center.x, y = center.z})
	
	if not event.initiator then 
		trigger.action.outText("Target entry aborted: no initiator.", 30)
		return true 
	end
	local theUnit = event.initiator
	local theGroup = theUnit:getGroup()
	local coalition = theGroup:getCoalition()
	local spotRange = 3000
	local autoAdd = true 
	local params = ""
	
	for idx, param in pairs(args) do 
		if params == "" then params = ": " 
		else params = params .. " " 
		end 
		params = params .. param
	end
		
	local name = "TgtData".. params .. " (" .. theUnit:getName() .. ")@T+" .. math.floor(timer.getTime())
	-- feed into arty zones
	cfxArtilleryZones.createArtilleryZone(name, center, coalition, spotRange, 500, autoAdd) -- 500 is base strength 
	
	trigger.action.outTextForCoalition(coalition, "New ARTY coordinates received from " .. theUnit:getName() .. ", standing by", 30)
	return true 
end

--
-- cfxArtillery init and start
--

function cfxArtilleryDemon.init()
	cfxArtilleryDemon.unitFilterMethod = cfxArtilleryDemon.authorizeAllUnits
	cfxArtilleryDemon.processCommandMethod = cfxArtilleryDemon.executeCommand
	
	-- now add known commands to interpreter. Add your own commands the same way
	cfxArtilleryDemon.addCommndProcessor("smoke", cfxArtilleryDemon.processSmokeCommand)
	
	cfxArtilleryDemon.addCommndProcessor("bumm", cfxArtilleryDemon.processBoomCommand)
	
	cfxArtilleryDemon.addCommndProcessor("tgt",
	cfxArtilleryDemon.processTargetCommand)
	
	-- you can add and remove command the same way
	trigger.action.outText("cf/x cfx Artillery Demon v" .. cfxArtilleryDemon.version .. " loaded", 30)
end

function cfxArtilleryDemon.start()
	cfxArtilleryDemon.demonID = world.addEventHandler(cfxArtilleryDemon)
	trigger.action.outText("cf/x cfxArtilleryDemon v" .. cfxArtilleryDemon.version .. " started", 30)
end

cfxArtilleryDemon.init()
if cfxArtilleryDemon.autostart then 
	cfxArtilleryDemon.start()
end