-- theDebugger 
debugger = {}
debugger.version = "1.1.1"
debugDemon = {}
debugDemon.version = "1.1.1"

debugger.verbose = false 
debugger.ups = 4 -- every 0.25 second  
debugger.name = "DML Debugger" -- for compliance with cfxZones 

debugger.log = ""

--[[--
	Version History
	1.0.0 - Initial version
	1.0.1 - made ups available to config zone 
	      - changed 'on' to 'active' in config zone 
		  - merged debugger and debugDemon
		  - QoL check for 'debug' attribute (no '?')
	1.1.0 - logging 
	      - trigger.action --> debugger for outText 
		  - persistence of logs
		  - save <name>
	1.1.1 - warning when trying to set a flag to a non-int
		  
 
--]]--

debugger.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
-- note: saving logs requires persistence module 
-- will auto-abort saving if not present 


debugger.debugZones = {}
debugger.debugUnits = {}
debugger.debugGroups = {}
debugger.debugObjects = {}

--
-- Logging & saving 
--

function debugger.outText(message, seconds, cls)
	if not message then message = "" end 
	if not seconds then seconds = 20 end 
	if not cls then cls = false end 
	
	-- append message to log, and add a lf
	if not debugger.log then debugger.log = "" end 
	debugger.log = debugger.log .. message .. "\n"
	
	-- now hand up to trigger 
	trigger.action.outText(message, seconds, cls)
end

function debugger.saveLog(name)
	if not _G["persistence"] then 
		debugger.outText("+++debug: persistence module required to save log")
		return
	end
	
	if not persistence.active then 
		debugger.outText("+++debug: persistence module can't write. ensur you desanitize lfs and io")
		return 
	end
	
	if persistence.saveText(debugger.log, name) then 
		debugger.outText("+++debug: log saved to <" .. persistence.missionDir .. name .. ">")
	else 
		debugger.outText("+++debug: unable to save log to <" .. persistence.missionDir .. name .. ">")
	end
end


--
-- tracking flags 
--

function debugger.addDebugger(theZone)
	table.insert(debugger.debugZones, theZone)
end

function debugger.getDebuggerByName(aName) 
	for idx, aZone in pairs(debugger.debugZones) do 
		if aName == aZone.name then return aZone end 
	end
	if debugger.verbose then 
		debugger.outText("+++debug: no debug zone with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

function debugger.removeDebugger(theZone)
	local filtered = {}
	for idx, dZone in pairs(debugger.debugZones) do 
		if dZone == theZone then 
		else 
			table.insert(filtered, dZone)
		end
	end
	debugger.debugZones = filtered
end
--
-- read zone 
-- 
function debugger.createDebuggerWithZone(theZone)
	-- watchflag input trigger
	theZone.debugInputMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "debugTriggerMethod") then 
		theZone.debugInputMethod = cfxZones.getStringFromZoneProperty(theZone, "debugTriggerMethod", "change")
	elseif cfxZones.hasProperty(theZone, "inputMethod") then 
		theZone.debugInputMethod = cfxZones.getStringFromZoneProperty(theZone, "inputMethod", "change")
	elseif cfxZones.hasProperty(theZone, "sayWhen") then 
		theZone.debugInputMethod = cfxZones.getStringFromZoneProperty(theZone, "sayWhen", "change")
	end
	
	-- say who we are and what we are monitoring
	if debugger.verbose or theZone.verbose then 
		debugger.outText("---debug: adding zone <".. theZone.name .."> to look for <value " .. theZone.debugInputMethod .. "> in flag(s):", 30)
	end
	
	-- read main debug array
	local theFlags = cfxZones.getStringFromZoneProperty(theZone, "debug?", "<none>")
	-- now, create an array from that
	local flagArray = cfxZones.flagArrayFromString(theFlags)
	local valueArray = {}
	-- now establish current values 
	for idx, aFlag in pairs(flagArray) do 
		local fVal = cfxZones.getFlagValue(aFlag, theZone)
		if debugger.verbose or theZone.verbose then 
			debugger.outText("    monitoring flag <" .. aFlag .. ">, inital value is <" .. fVal .. ">", 30)
		end
		valueArray[aFlag] = fVal
	end
	theZone.flagArray = flagArray
	theZone.valueArray = valueArray 
	

	
	-- DML output method
	theZone.debugOutputMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "outputMethod") then 
		theZone.debugOutputMethod = cfxZones.getStringFromZoneProperty(theZone, "outputMethod", "inc")
	end
	if cfxZones.hasProperty(theZone, "debugMethod") then 
		theZone.debugOutputMethod = cfxZones.getStringFromZoneProperty(theZone, "debugMethod", "inc")
	end
	
	-- notify!
	if cfxZones.hasProperty(theZone, "notify!") then 
		theZone.debugNotify = cfxZones.getStringFromZoneProperty(theZone, "notify!", "<none>")
	end
	
	-- debug message, can use all messenger vals plus <f> for flag name 
	-- we use out own default
	-- with <f> meaning flag name, <p> previous value, <c> current value 
	theZone.debugMsg = cfxZones.getStringFromZoneProperty(theZone, "debugMsg", "---debug: <t> -- Flag <f> changed from <p> to <c> [<z>]")
	
	
end

--
-- Misc
--
function debugger.addFlagToObserver(flagName, theZone)
	table.insert(theZone.flagArray, flagName)
	local fVal = cfxZones.getFlagValue(flagName, theZone)
	theZone.valueArray[flagName] = fVal
end

function debugger.removeFlagFromObserver(flagName, theZone)
	local filtered = {}
	for idy, aName in pairs(theZone.flagArray) do 
		if aName == flagName then
		else
			table.insert(filtered, aName)
		end 
	end
	theZone.flagArray = filtered 
	-- no need to clean up values, they are name-indexed. do it anyway
	theZone.valueArray[flagName] = nil
end

function debugger.isObservingWithObserver(flagName, theZone)
	for idy, aName in pairs(theZone.flagArray) do 
		if aName == flagName then
			local val = theZone.valueArray[flagName]
			return true, val 
		end 	
	end	
end

function debugger.isObserving(flagName)
	-- scan all zones for flag, and return 
	-- zone, and flag value if observing
	local observers = {}
	for idx, theZone in pairs(debugger.debugZones) do 
		for idy, aName in pairs(theZone.flagArray) do 
			if aName == flagName then
				table.insert(observers, theZone)
			end 
		end
	end

	return observers 
end

--
-- Update 
--
function debugger.processDebugMsg(inMsg, theZone, theFlag, oldVal, currVal)
	if not inMsg then return "<nil inMsg>" end
	if not oldVal then oldVal = "<no val!>" else oldVal = tostring(oldVal) end 
	if not currVal then currVal = "<no val!>" else currVal = tostring(currVal) end 
	if not theFlag then theFlag = "<no flag!>" end 
	
	local formerType = type(inMsg)
	if formerType ~= "string" then inMsg = tostring(inMsg) end  
	if not inMsg then inMsg = "<inMsg is incompatible type " .. formerType .. ">" end 
	
	-- build message by relacing wildcards
	local outMsg = ""
	
	-- replace line feeds 
	outMsg = inMsg:gsub("<n>", "\n")
	if theZone then 
		outMsg = outMsg:gsub("<z>", theZone.name)
	end
	
	-- replace <C>, <p>, <f> with currVal, oldVal, flag
	outMsg = outMsg:gsub("<c>", currVal)
	outMsg = outMsg:gsub("<p>", oldVal)
	outMsg = outMsg:gsub("<o>", oldVal) -- just for QoL
	outMsg = outMsg:gsub("<f>", theFlag)
	
	-- replace <t> with current mission time HMS
	local absSecs = timer.getAbsTime()-- + env.mission.start_time
	while absSecs > 86400 do 
		absSecs = absSecs - 86400 -- subtract out all days 
	end
	local timeString  = dcsCommon.processHMS("<:h>:<:m>:<:s>", absSecs)
	outMsg = outMsg:gsub("<t>", timeString)
	
	-- replace <lat> with lat of zone point and <lon> with lon of zone point 
	-- and <mgrs> with mgrs coords of zone point 
	if theZone then 
		local currPoint = cfxZones.getPoint(theZone)
		local lat, lon, alt = coord.LOtoLL(currPoint)
		lat, lon = dcsCommon.latLon2Text(lat, lon)
		outMsg = outMsg:gsub("<lat>", lat)
		outMsg = outMsg:gsub("<lon>", lon)
		currPoint = cfxZones.getPoint(theZone)
		local grid = coord.LLtoMGRS(coord.LOtoLL(currPoint))
		local mgrs = grid.UTMZone .. ' ' .. grid.MGRSDigraph .. ' ' .. grid.Easting .. ' ' .. grid.Northing
		outMsg = outMsg:gsub("<mgrs>", mgrs)
	end 
	
	return outMsg
end

function debugger.debugZone(theZone)
	-- check every flag of this zone 
	for idx, aFlag in pairs(theZone.flagArray) do 
		local oldVal = theZone.valueArray[aFlag]
		local oldVal = theZone.valueArray[aFlag]
		theZone.debugLastVal = oldVal
		local hasChanged, newValue = cfxZones.testZoneFlag(
			theZone,
			aFlag, 
			theZone.debugInputMethod,
 			"debugLastVal")
		-- we ALWAYS transfer latch back
		theZone.valueArray[aFlag] = newValue
		
		if hasChanged then 
			-- we are triggered 
			-- generate the ouput message
			local msg = theZone.debugMsg
			msg = debugger.processDebugMsg(msg, theZone, aFlag, oldVal, newValue)
			debugger.outText(msg, 30)
		end
	end

end

--
-- reset debugger
--
function debugger.resetObserver(theZone)
	for idf, aFlag in pairs(theZone.flagArray) do 
		local fVal = cfxZones.getFlagValue(aFlag, theZone)
		if debugger.verbose or theZone.verbose then 
			debugger.outText("---debug: resetting flag <" .. aFlag .. ">, to <" .. fVal .. "> for zone <" .. theZone.name .. ">", 30)
		end
		theZone.valueArray[aFlag] = fVal
	end	
end

function debugger.reset()
	for idx, theZone in pairs(debugger.debugZones) do
		-- reset this zone 
		debugger.resetObserver(theZone)
	end
end

function debugger.showObserverState(theZone)
	for idf, aFlag in pairs(theZone.flagArray) do 
		local fVal = cfxZones.getFlagValue(aFlag, theZone)
		if debugger.verbose or theZone.verbose then 
			debugger.outText("     state of flag <" .. aFlag .. ">: <" .. theZone.valueArray[aFlag] .. ">", 30)
		end
		theZone.valueArray[aFlag] = fVal
	end
end

function debugger.showState()
	debugger.outText("---debug: CURRENT STATE <" .. dcsCommon.nowString() .. "> --- ", 30)
	for idx, theZone in pairs(debugger.debugZones) do
		-- show this zone's state
		if #theZone.flagArray > 0 then 
			debugger.outText("   state of observer <" .. theZone.name .. "> looking for <value " .. theZone.debugInputMethod .. ">:", 30)
			debugger.showObserverState(theZone)
		else 
			if theZone.verbose or debugger.verbose then 
				debugger.outText("   (empty observer <" .. theZone.name .. ">)", 30)
			end
		end
	end
	debugger.outText("---debug: end of state --- ", 30)
end

function debugger.doActivate()
	debugger.active = true
	if debugger.verbose or true then 
		debugger.outText("+++ DM Debugger is now active", 30)
	end 
end

function debugger.doDeactivate()
	debugger.active = false
	if debugger.verbose or true then 
		debugger.outText("+++ debugger deactivated", 30)
	end 
end

function debugger.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(debugger.update, {}, timer.getTime() + 1/debugger.ups)
	
	-- first check for switch on or off
	if debugger.onFlag then 
		if cfxZones.testZoneFlag(debugger, debugger.onFlag, "change","lastOn") then
			debugger.doActivate()
		end
	end
	
	if debugger.offFlag then 
		if cfxZones.testZoneFlag(debugger, debugger.offFlag, "change","lastOff") then
			debugger.doDeactivate()
		end
	end
	
	-- ALWAYS check for reset & state. 
	if debugger.resetFlag then 
		if cfxZones.testZoneFlag(debugger, debugger.resetFlag, "change","lastReset") then
			debugger.reset()
		end
	end
	
	if debugger.stateFlag then 
		if cfxZones.testZoneFlag(debugger, debugger.stateFlag, "change","lastState") then
			debugger.showState()
		end
	end
	
	-- only progress if we are on
	if not debugger.active then return end 
	
	for idx, aZone in pairs(debugger.debugZones) do
		-- see if we are triggered 
		debugger.debugZone(aZone)
	end
end


--
-- Config & Start
--
function debugger.readConfigZone()
	local theZone = cfxZones.getZoneByName("debuggerConfig") 
	if not theZone then 
		if debugger.verbose then 
			debugger.outText("+++debug: NO config zone!", 30)
		end 
		theZone = cfxZones.createSimpleZone("debuggerConfig") 
	end 
	debugger.configZone = theZone 
	
	debugger.active = cfxZones.getBoolFromZoneProperty(theZone, "active", true)
	debugger.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if cfxZones.hasProperty(theZone, "on?") then 
		debugger.onFlag = cfxZones.getStringFromZoneProperty(theZone, "on?", "<none>")
		debugger.lastOn = cfxZones.getFlagValue(debugger.onFlag, theZone)
	end 

	if cfxZones.hasProperty(theZone, "off?") then 
		debugger.offFlag = cfxZones.getStringFromZoneProperty(theZone, "off?", "<none>")
		debugger.lastOff = cfxZones.getFlagValue(debugger.offFlag, theZone)
	end 

	if cfxZones.hasProperty(theZone, "reset?") then 
		debugger.resetFlag = cfxZones.getStringFromZoneProperty(theZone, "reset?", "<none>")
		debugger.lastReset = cfxZones.getFlagValue(debugger.resetFlag, theZone)
	end
	
	if cfxZones.hasProperty(theZone, "state?") then 
		debugger.stateFlag = cfxZones.getStringFromZoneProperty(theZone, "state?", "<none>")
		debugger.lastState = cfxZones.getFlagValue(debugger.stateFlag, theZone)
	end
	
	debugger.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 4)
	
	if debugger.verbose then 
		debugger.outText("+++debug: read config", 30)
	end 
end

function debugger.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx debugger requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx debugger", debugger.requiredLibs) then
		return false 
	end
	
	-- read config 
	debugger.readConfigZone()
	
	-- process debugger Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("debug?")
	for k, aZone in pairs(attrZones) do 
		debugger.createDebuggerWithZone(aZone) -- process attributes
		debugger.addDebugger(aZone) -- add to list
	end
	
	local attrZones = cfxZones.getZonesWithAttributeNamed("debug")
	for k, aZone in pairs(attrZones) do 
		debugger.outText("***Warning: Zone <" .. aZone.name .. "> has a 'debug' flag. Are you perhaps missing a '?'", 30)
	end
	
	-- say if we are active
	if debugger.verbose then 
		if debugger.active then 
			debugger.outText("+++debugger loaded and active", 30)
		else 
			debugger.outText("+++ debugger: standing by for activation", 30)
		end
	end
	
	-- start update 
	debugger.update()
	
	debugger.outText("cfx debugger v" .. debugger.version .. " started.", 30)
	return true 
end

-- let's go!
if not debugger.start() then 
	trigger.action.outText("cfx debugger aborted: missing libraries", 30)
	debugger = nil 
end

--[[--
	debug on and off. globally, not per zone 
	
--]]--


--
-- DEBUG DEMON 
--

debugDemon.myObserverName = "+DML Debugger+"
-- interactive interface for DML debugger 

debugDemon.verbose = false 
-- based on cfx stage demon
--[[--
	Version History
	1.0.0 - initial version 
	1.1.0 - save command, requires persistence
	
--]]--

debugDemon.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"debugger",
}
debugDemon.markOfDemon = "-" -- all commands must start with this sequence
debugDemon.splitDelimiter = " " 
debugDemon.commandTable = {} -- key, value pair for command processing per keyword
debugDemon.keepOpen = false -- keep mark open after a successful command
debugDemon.snapshot = {}

function debugDemon.hasMark(theString) 
	-- check if the string begins with the sequece to identify commands 
	if not theString then return false end
	return theString:find(debugDemon.markOfDemon) == 1
end


-- main hook into DCS. Called whenever a Mark-related event happens
-- very simple: look if text begins with special sequence, and if so, 
-- call the command processor. 
function debugDemon:onEvent(theEvent)
	-- while we can hook into any of the three events, 
	-- we curently only utilize CHANGE Mark
	if not (theEvent.id == world.event.S_EVENT_MARK_ADDED) and
	   not (theEvent.id == world.event.S_EVENT_MARK_CHANGE) and 
	   not (theEvent.id == world.event.S_EVENT_MARK_REMOVED) then 
		-- not of interest for us, bye bye
		return 
	end
						   
	-- when we get here, we have a mark event
	
    if theEvent.id == world.event.S_EVENT_MARK_ADDED then
		-- add mark is quite useless		
	end
    
    if theEvent.id == world.event.S_EVENT_MARK_CHANGE then
		-- when changed, the mark's text is examined for a command
		-- if it starts with the 'mark' string ("-" by  default) it is processed
		-- by the command processor
		-- if it is processed succesfully, the mark is immediately removed
		-- else an error is displayed and the mark remains.
		if debugDemon.hasMark(theEvent.text) then 
			-- strip the mark 
			local commandString = theEvent.text:sub(1+debugDemon.markOfDemon:len())
			-- break remainder apart into <command> <arg1> ... <argn>
			local commands = dcsCommon.splitString(commandString, debugDemon.splitDelimiter)

			-- this is a command. process it and then remove it if it was executed successfully
			local success = debugDemon.executeCommand(commands, theEvent)
						
			-- remove this mark after successful execution
			if success then 
				trigger.action.removeMark(theEvent.idx) 
			else 
				-- we could play some error sound
			end
		end 
    end 
	
	if theEvent.id == world.event.S_EVENT_MARK_REMOVED then
    end
end

--
-- add / remove commands to/from vocabulary
-- 
function debugDemon.addCommndProcessor(command, processor)
	debugDemon.commandTable[command:upper()] = processor 
end

function debugDemon.removeCommandProcessor(command)
	debugDemon.commandTable[command:upper()] = nil 
end

--
-- process input arguments. Here we simply move them 
-- up by one.
--
function debugDemon.getArgs(theCommands) 
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
function debugDemon.executeCommand(theCommands, event)
	local cmd = theCommands[1]
	local arguments = debugDemon.getArgs(theCommands)
	if not cmd then return false end
	
	-- since we have a command in cmd, we remove this from
	-- the string, and pass the remainder back 
	local remainder = event.text:sub(1 + debugDemon.markOfDemon:len())
	remainder = dcsCommon.stripLF(remainder)
	remainder = dcsCommon.trim(remainder)
	remainder = remainder:sub(1+cmd:len())
	remainder = dcsCommon.trim(remainder) 

	event.remainder = remainder
	-- use the command as index into the table of functions
	-- that handle them.
	if debugDemon.commandTable[cmd:upper()] then 
		local theInvoker = debugDemon.commandTable[cmd:upper()]
		local success = theInvoker(arguments, event)
		return success
	else 
		debugger.outText("***error: unknown command <".. cmd .. ">", 30)
		return false
	end
	
	return true
end

--
-- Helpers 
--
--[[--
function debugDemon.isObserving(flagName)
	-- for now, we simply scan out own 
	for idx, aName in pairs(debugDemon.observer.flagArray) do 
		if aName == flagName then return true end 
	end
	return false 
end
--]]--

function debugDemon.createObserver(aName)
	local observer = cfxZones.createSimpleZone(aName)
	observer.verbose = debugDemon.verbose 
	observer.debugInputMethod = "change"
	observer.flagArray = {}
	observer.valueArray = {}
	observer.debugMsg = "---debug: <t> -- Flag <f> changed from <p> to <c> [<z>]"
	return observer
end
--
-- COMMANDS
--
function debugDemon.processHelpCommand(args, event)
debugger.outText("*** debugger: commands are:" ..
	"\n  " .. debugDemon.markOfDemon .. "show <flagname/observername> -- show current values for flag or observer" ..
	"\n  " .. debugDemon.markOfDemon .. "set <flagname> <number> -- set flag to value <number>" ..
	"\n  " .. debugDemon.markOfDemon .. "inc <flagname> -- increase flag by 1, changing it" ..
	"\n  " .. debugDemon.markOfDemon .. "flip <flagname> -- when flag's value is 0, set it to 1, else to 0" ..	

	"\n\n  " .. debugDemon.markOfDemon .. "observe <flagname> [with <observername>] -- observe a flag for change" ..
	"\n  " .. debugDemon.markOfDemon .. "o <flagname> [with <observername>] -- observe a flag for change" ..
	"\n  " .. debugDemon.markOfDemon .. "forget <flagname> [with <observername>] -- stop observing a flag" ..
	"\n  " .. debugDemon.markOfDemon .. "new <observername> [[for] <condition>] -- create observer for flags" ..
	"\n  " .. debugDemon.markOfDemon .. "update <observername> [[to] <condition>] -- change observer's condition" ..
	"\n  " .. debugDemon.markOfDemon .. "drop <observername> -- remove observer from debugger" ..
	"\n  " .. debugDemon.markOfDemon .. "list [<match>] -- list observers [name contains <match>]" ..
	"\n  " .. debugDemon.markOfDemon .. "who <flagname> -- all who observe <flagname>" ..
	"\n  " .. debugDemon.markOfDemon .. "reset [<observername>] -- reset all or only the named observer" ..

	"\n\n  " .. debugDemon.markOfDemon .. "snap [<observername>] -- create new snapshot of flags" ..
	"\n  " .. debugDemon.markOfDemon .. "compare -- compare snapshot flag values with current" ..
	"\n  " .. debugDemon.markOfDemon .. "note <your note> -- add <your note> to the text log" ..
	"\n\n  " .. debugDemon.markOfDemon .. "start -- starts debugger" ..
	"\n  " .. debugDemon.markOfDemon .. "stop -- stop debugger" ..

	"\n\n  " .. debugDemon.markOfDemon .. "save [<filename>] -- saves debugger log to storage" ..

	"\n\n  " .. debugDemon.markOfDemon .. "? or -help  -- this text", 30)
	return true 
end

function debugDemon.processNewCommand(args, event)
	-- syntax new <observername> [[for] <condition>]
	local observerName = args[1]
	if not observerName then 
		debugger.outText("*** new: missing observer name.", 30)
		return false -- allows correction 
	end
	
	-- see if this observer already existst
	local theObserver = debugger.getDebuggerByName(observerName)
	if theObserver then 
		debugger.outText("*** new: observer <" .. observerName .. "> already exists.", 30)
		return false -- allows correction 
	end
	
	-- little pitfall: what if the name contains blanks?
	-- also check against remainder!
	local remainderName = event.remainder
	local rObserver = debugger.getDebuggerByName(remainderName)
	if rObserver then 
		debugger.outText("*** new: observer <" .. remainderName .. "> already exists.", 30)
		return false -- allows correction 
	end
	
	local theZone = nil
	local condition = args[2] -- may need remainder instead
	if condition == "for" then 
		-- we use arg[2]
	else 
		observerName = remainderName -- we use entire rest of line 
	end

	theZone = debugDemon.createObserver(observerName)

	if condition == "for" then condition = args[3] end 
	if condition then 
		if not cfxZones.verifyMethod(condition, theZone) then 
			debugger.outText("*** new: illegal trigger condition <" .. condition .. "> for observer <" .. observerName .. ">", 30)
			return false 
		end
		theZone.debugInputMethod = condition
	end
	
	debugger.addDebugger(theZone)
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debugger: new observer <" .. observerName .. "> for <" .. theZone.debugInputMethod .. ">", 30)
	return true 
end

function debugDemon.processUpdateCommand(args, event)
	-- syntax update <observername> [[to] <condition>]
	local observerName = args[1]
	if not observerName then 
		debugger.outText("*** update: missing observer name.", 30)
		return false -- allows correction 
	end
	
	-- see if this observer already existst
	local theZone = debugger.getDebuggerByName(observerName)
	if not theZone then 
		debugger.outText("*** update: observer <" .. observerName .. "> does not exist exists.", 30)
		return false -- allows correction 
	end
		
	local condition = args[2] -- may need remainder instead
	if condition == "to" then condition = args[3] end 
	if condition then 
		if not cfxZones.verifyMethod(condition, theZone) then 
			debugger.outText("*** update: illegal trigger condition <" .. condition .. "> for observer <" .. observerName .. ">", 30)
			return false 
		end
		theZone.debugInputMethod = condition
	end
	
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debugger: updated observer <" .. observerName .. "> to <" .. theZone.debugInputMethod .. ">", 30)
	return true 
end

function debugDemon.processDropCommand(args, event)
	-- syntax drop <observername>
	local observerName = event.remainder -- remainder
	if not observerName then 
		debugger.outText("*** drop: missing observer name.", 30)
		return false -- allows correction 
	end
	
	-- see if this observer already existst
	local theZone = debugger.getDebuggerByName(observerName)
	if not theZone then 
		debugger.outText("*** drop: observer <" .. observerName .. "> does not exist exists.", 30)
		return false -- allows correction 
	end
	
	-- now simply and irrevocable remove the observer, unless it's home, 
	-- in which case it's simply reset 
	if theZone == debugDemon.observer then 
		debugger.outText("*** drop: <" .. observerName .. "> is MY PRECIOUS and WILL NOT be dropped.", 30)
		-- can't really happen since it contains blanks, but
		-- we've seen stranger things
		return false -- allows correction 
	end 
	
	debugger.removeDebugger(theZone)
	
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debugger: dropped observer <" .. observerName .. ">", 30)
	return true 
end
-- observe command: add a new flag to observe
function debugDemon.processObserveCommand(args, event)
	-- syntax: observe <flagname> [with <observername>]
	-- args[1] is the name of the flag 
	local flagName = args[1]
	if not flagName then 
		debugger.outText("*** observe: missing flag name.", 30)
		return false -- allows correction 
	end
	
	local withTracker = nil 
	if args[2] == "with" then 
		local aName = args[3]
		if not aName then 
			debugger.outText("*** observe: missing <observer name> after 'with'.", 30)
			return false -- allows correction 
		end
		aName = dcsCommon.stringRemainsStartingWith(event.remainder, aName)
		withTracker = debugger.getDebuggerByName(aName)
		if not withTracker then 
--			withTracker = debugDemon.createObserver(aName)
--			debugger.addDebugger(withTracker)
			debugger.outText("*** observe: no observer <" .. aName .. "> exists", 30)
			return false -- allows correction
		end 
	else -- not with as arg 2 
		if #args > 1 then 
			debugger.outText("*** observe: unknown command after flag name '" .. flagName .. "'.", 30)
			return false -- allows correction 
		end
		-- use own observer  
		withTracker = debugDemon.observer
	end
	
	if debugger.isObservingWithObserver(flagName, withTracker) then 
		debugger.outText("*** observe: already observing " .. flagName .. " with <" .. withTracker.name .. ">" , 30)
		return true
	end
	
	-- we add flag to tracker and init value
	debugger.addFlagToObserver(flagName, withTracker)
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debugger: now observing <" .. flagName .. "> for value " .. withTracker.debugInputMethod .. " with <" .. withTracker.name .. ">.", 30)
	return true
end

function debugDemon.processShowCommand(args, event)
	-- syntax -show <name> with name either flag or observer
	-- observer has precendce over flag 
	local theName = args[1]
	if not theName then 
		debugger.outText("*** show: missing observer/flag name.", 30)
		return false -- allows correction 
	end
	
	-- now see if we have an observer 
	theName = dcsCommon.stringRemainsStartingWith(event.remainder, theName)
	local theObserver = debugger.getDebuggerByName(theName)
	
	if not theObserver then 
		-- we directly use trigger.misc
		local fVal = trigger.misc.getUserFlag(theName)
		debugger.outText("[" .. dcsCommon.nowString() .. "] flag <" .. theName .. "> : value <".. fVal .. ">", 30)
		return true 
	end
	
	-- if we get here, we want to show an entire observer 
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] flags observed by <" .. theName .. "> looking for <value ".. theObserver.debugInputMethod .. ">:", 30)
	local flags = theObserver.flagArray
	local values = theObserver.valueArray
	for idx, flagName in pairs(flags) do 
		local lastVal = values[flagName]
		local fVal = cfxZones.getFlagValue(flagName, theObserver)
		-- add code to detect if it would trigger here 
		local hit = cfxZones.testFlagByMethodForZone(fVal, lastVal, theObserver.debugInputMethod, theObserver)
		local theMark = "   "
		local trailer = ""
		if hit then 
			theMark = " ! "
			trailer = ", HIT!"
		end 
		debugger.outText(theMark .. "f:<" .. flagName .. "> = <".. fVal .. "> [current, state = <" .. values[flagName] .. ">" .. trailer .. "]", 30)
	end 
	
	return true 
end

function debugDemon.createSnapshot(allObservers)
	if not allObservers then allObservers = {debugDemon.observer} end
	local snapshot = {}
	for idx, theZone in pairs(allObservers) do 

		-- iterate each observer 
		for idy, flagName in pairs (theZone.flagArray) do 
			local fullName = cfxZones.expandFlagName(flagName, theZone)
			local fVal = trigger.misc.getUserFlag(fullName)
			snapshot[fullName] = fVal
		end
	end
	return snapshot
end

function debugDemon.processSnapCommand(args, event)
-- syntax snap [<observername>]
	local allObservers = debugger.debugZones -- default: all zones
	local theObserver = nil 
	
	local theName = args[1]
	if theName then 
		-- now see if we have an observer 
		theName = dcsCommon.stringRemainsStartingWith(event.remainder, theName)
		theObserver = debugger.getDebuggerByName(theName)
		if not theObserver then 
			debugger.outText("*** snap: unknown observer name <" .. theName .. ">.", 30)
			return false -- allows correction
		end
	end 
	
	if theObserver then 
		allObservers = {}
		table.insert(allObservers, theObserver)
	end
	
	-- set up snapshot 
	local snapshot = debugDemon.createSnapshot(allObservers) --{}
	--[[--
	for idx, theZone in pairs(allObservers) do 
		-- iterate each observer 
		for idy, flagName in pairs (theZone.flagArray) do 
			local fullName = cfxZones.expandFlagName(flagName, theZone)
			local fVal = trigger.misc.getUserFlag(fullName)
			snapshot[fullName] = fVal
		end
	end
	--]]--
	
	local sz = dcsCommon.getSizeOfTable(snapshot)
	debugDemon.snapshot = snapshot
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debug: new snapshot created, " .. sz .. " flags.", 30)
	
	return true 
end

function debugDemon.processCompareCommand(args, event)
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debug: comparing snapshot with current flag values", 30)
	for flagName, val in pairs (debugDemon.snapshot) do 
		local cVal = trigger.misc.getUserFlag(flagName)
		local mark = '   '
		if cVal ~= val then mark = ' ! ' end
		debugger.outText(mark .. "<" .. flagName .. "> snap = <" .. val .. ">, now = <" .. cVal .. "> " .. mark, 30)
	end
	debugger.outText("*** END", 30)
	return true 
end

function debugDemon.processNoteCommand(args, event)
	local n = event.remainder
	debugger.outText("*** [" .. dcsCommon.nowString() .. "]: " .. n, 30)
	return true
end

function debugDemon.processSetCommand(args, event)
	-- syntax set <flagname> <value>
	local theName = args[1]
	if not theName then 
		debugger.outText("*** set: missing flag name.", 30)
		return false -- allows correction 
	end
	
	local theVal = args[2]
	if theVal and type(theVal) == "string" then 
		theVal = theVal:upper()
		if theVal == "YES" or theVal == "TRUE" then theVal = "1" end
		if theVal == "NO" or theVal == "FALSE" then theVal = "0" end
	end
	
	if not theVal or not (tonumber(theVal)) then 
		debugger.outText("*** set: missing or illegal value for flag <" .. theName .. ">.", 30)
		return false -- allows correction
	end 
	
	theVal = tonumber(theVal) 
	trigger.action.setUserFlag(theName, theVal)
	-- we set directly, no cfxZones proccing
	local note =""
	-- flags are ints only?
	if theVal ~= math.floor(theVal) then 
		note = " [int! " .. math.floor(theVal) .. "]"
	end
	
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debug: set flag <" .. theName .. "> to <" .. theVal .. ">" .. note, 30)
	
	return true 
end

function debugDemon.processIncCommand(args, event)
	-- syntax inc <flagname>
	local theName = args[1]
	if not theName then 
		debugger.outText("*** inc: missing flag name.", 30)
		return false -- allows correction 
	end
	
	local cVal = trigger.misc.getUserFlag(theName)
	local nVal = cVal + 1 
	
	-- we set directly, no cfxZones procing
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debug: inc flag <" .. theName .. "> from <" .. cVal .. "> to <" .. nVal .. ">", 30)
	trigger.action.setUserFlag(theName, nVal)
	return true 
end

function debugDemon.processFlipCommand(args, event)
	-- syntax flip <flagname> 
	local theName = args[1]
	if not theName then 
		debugger.outText("*** flip: missing flag name.", 30)
		return false -- allows correction 
	end
	
	local cVal = trigger.misc.getUserFlag(theName)
	if cVal == 0 then nVal = 1 else nVal = 0 end 
	
	-- we set directly, no cfxZones procing
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debug: flipped flag <" .. theName .. "> from <" .. cVal .. "> to <" .. nVal .. ">", 30)
	trigger.action.setUserFlag(theName, nVal)
	return true 
end

function debugDemon.processListCommand(args, event)
	-- syntax list or list <prefix>
	local prefix = nil 
	prefix = args[1]
	if prefix then 
		prefix = event.remainder -- dcsCommon.stringRemainsStartingWith(event.text, prefix)
	end
	if prefix then 
		debugger.outText("*** [" .. dcsCommon.nowString() .. "] listing observers whose name contains <" .. prefix .. ">:", 30)
	else 
		debugger.outText("*** [" .. dcsCommon.nowString() .. "] listing all observers:", 30)
	end
	
	local allObservers = debugger.debugZones
	for idx, theZone in pairs(allObservers) do 
		local theName = theZone.name 
		local doList = true 
		if prefix then 
			doList = dcsCommon.containsString(theName, prefix, false)
		end
		
		if doList then 
			debugger.outText("  <" .. theName .. "> for <value " .. theZone.debugInputMethod .. "> (" .. #theZone.flagArray .. " flags)", 30)
		end
	end
    return true 
end

function debugDemon.processWhoCommand(args, event)
	-- syntax: who <flagname>
	local flagName = event.remainder -- args[1]
	if not flagName or flagName:len()<1 then 
		debugger.outText("*** who: missing flag name.", 30)
		return false -- allows correction 
	end

	local observers = debugger.isObserving(flagName)

	if not observers or #observers < 1 then 
		debugger.outText("*** [" .. dcsCommon.nowString() .. "] flag <" .. flagName .. "> is currently not observed", 30)
		return false
	end 

	debugger.outText("*** [" .. dcsCommon.nowString() .. "] flag <" .. flagName .. "> is currently observed by", 30)
	for idx, theZone in pairs(observers) do 
		debugger.outText("  <" .. theZone.name .. "> looking for <value " .. theZone.debugInputMethod .. ">", 30)
	end
	
	return true
	
end

function debugDemon.processForgetCommand(args, event)
	-- syntax: forget <flagname> [with <observername>]

	local flagName = args[1]
	if not flagName then 
		debugger.outText("*** forget: missing flag name.", 30)
		return false -- allows correction 
	end
	
	local withTracker = nil 
	if args[2] == "with" or args[2] == "from" then -- we also allow 'from'
		local aName = args[3]
		if not aName then 
			debugger.outText("*** forget: missing <observer name> after 'with'.", 30)
			return false -- allows correction 
		end
		
		aName = dcsCommon.stringRemainsStartingWith(event.remainder, aName)
		withTracker = debugger.getDebuggerByName(aName)
		if not withTracker then 
			debugger.outText("*** forget: no observer named <" .. aName .. ">", 30)
			return false
		end 
	else -- not with as arg 2 
		if #args > 1 then 
			debugger.outText("*** forget: unknown command after flag name '" .. flagName .. "'.", 30)
			return false -- allows correction 
		end
		-- use own observer  
		withTracker = debugDemon.observer
	end
	
	if not debugger.isObservingWithObserver(flagName, withTracker) then 
		debugger.outText("*** forget: observer <" .. withTracker.name .. "> does not observe flag <" .. flagName .. ">", 30)
		return false
	end
	
	-- we add flag to tracker and init value
	debugger.removeFlagFromObserver(flagName, withTracker)
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debugger: no longer observing " .. flagName .. " with <" .. withTracker.name .. ">.", 30)
	return true
end


function debugDemon.processStartCommand(args, event)
	debugger.doActivate()
	return true 
end

function debugDemon.processStopCommand(args, event)
	debugger.doDeactivate()
	return true 
end

function debugDemon.processResetCommand(args, event)
	-- supports reset <observer> 
	-- syntax: forget <flagname> [with <observername>]

	local obsName = args[1]
	if not obsName then 
		debugger.reset() -- reset all
		debugger.outText("*** [" .. dcsCommon.nowString() .. "] debug: reset complete.", 30)
		return true -- allows correction 
	end
	
	local withTracker = nil 
	local aName = event.remainder 
	withTracker = debugger.getDebuggerByName(aName)
	if not withTracker then 
		debugger.outText("*** reset: no observer <" .. aName .. ">", 30)
		return false
	end 
	
	debugger.resetObserver(withTracker)
	
	debugger.outText("*** [" .. dcsCommon.nowString() .. "] debugger:reset observer <" .. withTracker.name .. ">", 30)
	return true
end

function debugDemon.processSaveCommand(args, event)
	-- save log to file, requires persistence module 
	-- syntax: -save [<fileName>]
	local aName = event.remainder
	if not aName or aName:len() < 1 then 
		aName = "DML Debugger Log"
	end
	if not dcsCommon.stringEndsWith(aName, ".txt") then 
		aName = aName .. ".txt"
	end
	debugger.saveLog(aName)
	return true 
end
--
-- init and start
--

function debugDemon.readConfigZone()
	local theZone = cfxZones.getZoneByName("debugDemonConfig") 
	if not theZone then 
		if debugDemon.verbose then 
			debugger.outText("+++debug (daemon): NO config zone!", 30)
		end 
		theZone = cfxZones.createSimpleZone("debugDemonConfig") 
	end 
	debugDemon.configZone = theZone 
	
	debugDemon.keepOpen = cfxZones.getBoolFromZoneProperty(theZone, "keepOpen", false)
	
	debugDemon.markOfDemon = cfxZones.getStringFromZoneProperty(theZone,"mark", "-") -- all commands must start with this sequence

	
	debugDemon.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	
	if debugger.verbose then 
		debugger.outText("+++debug (deamon): read config", 30)
	end 
end

function debugDemon.init()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx interactive debugger requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx interactive debugger", debugDemon.requiredLibs) then
		return false 
	end
	
	-- config
	debugDemon.readConfigZone()
	
	-- now add known commands to interpreter. 
	debugDemon.addCommndProcessor("observe", debugDemon.processObserveCommand)
	debugDemon.addCommndProcessor("o", debugDemon.processObserveCommand) -- synonym

	debugDemon.addCommndProcessor("forget", debugDemon.processForgetCommand)

	debugDemon.addCommndProcessor("show", debugDemon.processShowCommand)
	debugDemon.addCommndProcessor("set", debugDemon.processSetCommand)
	debugDemon.addCommndProcessor("inc", debugDemon.processIncCommand)
	debugDemon.addCommndProcessor("flip", debugDemon.processFlipCommand)
    debugDemon.addCommndProcessor("list", debugDemon.processListCommand)
	debugDemon.addCommndProcessor("who", debugDemon.processWhoCommand)
	
	debugDemon.addCommndProcessor("new", debugDemon.processNewCommand)
	debugDemon.addCommndProcessor("update", debugDemon.processUpdateCommand)
	debugDemon.addCommndProcessor("drop", debugDemon.processDropCommand)
	
	debugDemon.addCommndProcessor("snap", debugDemon.processSnapCommand)
	debugDemon.addCommndProcessor("compare", debugDemon.processCompareCommand)
	debugDemon.addCommndProcessor("note", debugDemon.processNoteCommand)
	
	debugDemon.addCommndProcessor("start", debugDemon.processStartCommand)
	debugDemon.addCommndProcessor("stop", debugDemon.processStopCommand)
	debugDemon.addCommndProcessor("reset", debugDemon.processResetCommand)
	
	debugDemon.addCommndProcessor("save", debugDemon.processSaveCommand)

	debugDemon.addCommndProcessor("?", debugDemon.processHelpCommand)
	debugDemon.addCommndProcessor("help", debugDemon.processHelpCommand)

	
	return true 
end

function debugDemon.start()
	-- add my own debug zones to debugger so it can 
	-- track any changes 
	
	local observer = debugDemon.createObserver(debugDemon.myObserverName)
	debugDemon.observer = observer
	debugger.addDebugger(observer)
	
	-- create initial snapshot 
	debugDemon.snapshot = debugDemon.createSnapshot(debugger.debugZones)
	debugDemon.demonID = world.addEventHandler(debugDemon)
		
	debugger.outText("interactive debugDemon v" .. debugDemon.version .. " started" .. "\n  enter " .. debugDemon.markOfDemon .. "? in a map mark for help", 30)
	
	if not _G["persistence"] then 
		debugger.outText("\n  note: '-save' disabled, no persistence module found", 30)
	end
end

if debugDemon.init() then 
	debugDemon.start()
else 
	trigger.action.outText("*** interactive flag debugger failed to initialize.", 30)
	debugDemon = {}
end

--[[--
	- track units/groups/objects: health changes 
	- track players: unit change, enter, exit 
	- inspect objects, dumping category, life, if it's tasking, latLon, alt, speed, direction 
	
	- exec files. save all commands and then run them from script 
	- remove units via delete and explode
	
--]]--
