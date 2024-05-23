-- theDebugger 2.x
debugger = {}
debugger.version = "2.1.1"
debugDemon = {}
debugDemon.version = "2.1.0"

debugger.verbose = false 
debugger.ups = 4 -- every 0.25 second  
debugger.name = "DML Debugger" -- for compliance with cfxZones 

debugger.log = ""

--[[--
	Version History
	2.0.0 - dmlZones OOP 
	      - eventmon command 
		  - eventmon all, off, event #
		  - standard events 
		  - adding events via #
		  - events? attribute from any zone 
		  - eventmon last command 
		  - q - query MSE Lua variables 
		  - w - write/overwrite MSE Lua variables 
		  - a - analyse Lua tables / variables 
		  - smoke
		  - spawn system with predefines
		  - spawn coalition
		  - spawn number 
		  - spawn heading
		  - spawn types 
		  - spawn aircraft: add waypoints 
		  - spawn "?"
		  - debuggerSpawnTypes zone 
		  - reading debuggerSpawnTypes 
		  - removed some silly bugs / inconsistencies
	2.1.0 - debugging code is now invoked deferred to avoid 
	        DCS crash after exiting. Debug code now executes 
			outside of the event code's bracket.
			debug invocation on clone of data structure 
			readback verification of flag set 
			fixed getProperty() in debugger with zone 
	2.1.1 - removed bug that skipped events? when zone not verbose 
			
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
debugger.showEvents = {}
debugger.lastEvent = nil 

debugDemon.eventList = {
  ["0"] = "S_EVENT_INVALID = 0",
  ["1"] = "S_EVENT_SHOT = 1",
  ["2"] = "S_EVENT_HIT = 2",
  ["3"] = "S_EVENT_TAKEOFF = 3",
  ["4"] = "S_EVENT_LAND = 4",
  ["5"] = "S_EVENT_CRASH = 5",
  ["6"] = "S_EVENT_EJECTION = 6",
  ["7"] = "S_EVENT_REFUELING = 7",
  ["8"] = "S_EVENT_DEAD = 8",
  ["9"] = "S_EVENT_PILOT_DEAD = 9",
  ["10"] = "S_EVENT_BASE_CAPTURED = 10",
  ["11"] = "S_EVENT_MISSION_START = 11",
  ["12"] = "S_EVENT_MISSION_END = 12",
  ["13"] = "S_EVENT_TOOK_CONTROL = 13",
  ["14"] = "S_EVENT_REFUELING_STOP = 14",
  ["15"] = "S_EVENT_BIRTH = 15",
  ["16"] = "S_EVENT_HUMAN_FAILURE = 16",
  ["17"] = "S_EVENT_DETAILED_FAILURE = 17",
  ["18"] = "S_EVENT_ENGINE_STARTUP = 18",
  ["19"] = "S_EVENT_ENGINE_SHUTDOWN = 19",
  ["20"] = "S_EVENT_PLAYER_ENTER_UNIT = 20",
  ["21"] = "S_EVENT_PLAYER_LEAVE_UNIT = 21",
  ["22"] = "S_EVENT_PLAYER_COMMENT = 22",
  ["23"] = "S_EVENT_SHOOTING_START = 23",
  ["24"] = "S_EVENT_SHOOTING_END = 24",
  ["25"] = "S_EVENT_MARK_ADDED  = 25", 
  ["26"] = "S_EVENT_MARK_CHANGE = 26",
  ["27"] = "S_EVENT_MARK_REMOVED = 27",
  ["28"] = "S_EVENT_KILL = 28",
  ["29"] = "S_EVENT_SCORE = 29",
  ["30"] = "S_EVENT_UNIT_LOST = 30",
  ["31"] = "S_EVENT_LANDING_AFTER_EJECTION = 31",
  ["32"] = "S_EVENT_PARATROOPER_LENDING = 32",
  ["33"] = "S_EVENT_DISCARD_CHAIR_AFTER_EJECTION = 33", 
  ["34"] = "S_EVENT_WEAPON_ADD = 34",
  ["35"] = "S_EVENT_TRIGGER_ZONE = 35",
  ["36"] = "S_EVENT_LANDING_QUALITY_MARK = 36",
  ["37"] = "S_EVENT_BDA = 37", 
  ["38"] = "S_EVENT_AI_ABORT_MISSION = 38", 
  ["39"] = "S_EVENT_DAYNIGHT = 39", 
  ["40"] = "S_EVENT_FLIGHT_TIME = 40", 
  ["41"] = "S_EVENT_PLAYER_SELF_KILL_PILOT = 41", 
  ["42"] = "S_EVENT_PLAYER_CAPTURE_AIRFIELD = 42", 
  ["43"] = "S_EVENT_EMERGENCY_LANDING = 43",
  ["44"] = "S_EVENT_UNIT_CREATE_TASK = 44",
  ["45"] = "S_EVENT_UNIT_DELETE_TASK = 45",
  ["46"] = "S_EVENT_SIMULATION_START = 46",
  ["47"] = "S_EVENT_WEAPON_REARM = 47",
  ["48"] = "S_EVENT_WEAPON_DROP = 48",
  ["49"] = "S_EVENT_UNIT_TASK_TIMEOUT = 49",
  ["50"] = "S_EVENT_UNIT_TASK_STAGE = 50",
  ["51"] = "S_EVENT_MAC_SUBTASK_SCORE = 51", 
  ["52"] = "S_EVENT_MAC_EXTRA_SCORE = 52",
  ["53"] = "S_EVENT_MISSION_RESTART = 53",
  ["54"] = "S_EVENT_MISSION_WINNER = 54", 
  ["55"] = "S_EVENT_POSTPONED_TAKEOFF = 55", 
  ["56"] = "S_EVENT_POSTPONED_LAND = 56", 
  ["57"] = "S_EVENT_MAX = 57",
}

debugger.spawnTypes = {
 ["inf"] = "Soldier M4",
 ["ifv"] = "BTR-80",
 ["tank"] = "T-90",
 ["ship"] = "PERRY",
 ["helo"] = "AH-1W",
 ["jet"] = "MiG-21Bis",
 ["awacs"] = "A-50",
 ["ww2"] = "SpitfireLFMkIX",
 ["bomber"] = "B-52H",
 ["cargo"] = "ammo_cargo",
 ["sam"] = "Roland ADS",
 ["aaa"] = "ZSU-23-4 Shilka",
 ["arty"] = "M-109",
 ["truck"] = "KAMAZ Truck",
 ["drone"] = "MQ-9 Reaper",
 ["manpad"] = "Soldier stinger",
 ["obj"] = "house2arm"
}
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
	theZone.debugInputMethod = theZone:getStringFromZoneProperty( "triggerMethod", "change")
	if theZone:hasProperty("debugTriggerMethod") then 
		theZone.debugInputMethod = theZone:getStringFromZoneProperty("debugTriggerMethod", "change")
	elseif theZone:hasProperty("inputMethod") then 
		theZone.debugInputMethod = theZone:getStringFromZoneProperty(theZone, "inputMethod", "change")
	elseif theZone:hasProperty("sayWhen") then 
		theZone.debugInputMethod = theZone:getStringFromZoneProperty("sayWhen", "change")
	end
	
	-- say who we are and what we are monitoring
	if debugger.verbose or theZone.verbose then 
		debugger.outText("---debug: adding zone <".. theZone.name .."> to look for <value " .. theZone.debugInputMethod .. "> in flag(s):", 30)
	end
	
	-- read main debug array
	local theFlags = theZone:getStringFromZoneProperty("debug?", "<none>")
	-- now, create an array from that
	local flagArray = cfxZones.flagArrayFromString(theFlags)
	local valueArray = {}
	-- now establish current values 
	for idx, aFlag in pairs(flagArray) do 
		local fVal = theZone:getFlagValue(aFlag)
		if debugger.verbose or theZone.verbose then 
			debugger.outText("    monitoring flag <" .. aFlag .. ">, inital value is <" .. fVal .. ">", 30)
		end
		valueArray[aFlag] = fVal
	end
	theZone.flagArray = flagArray
	theZone.valueArray = valueArray 
	
	-- DML output method
	theZone.debugOutputMethod = theZone:getStringFromZoneProperty("method", "inc")
	if theZone:hasProperty("outputMethod") then 
		theZone.debugOutputMethod = theZone:getStringFromZoneProperty("outputMethod", "inc")
	end
	if theZone:hasProperty("debugMethod") then 
		theZone.debugOutputMethod = theZone:getStringFromZoneProperty("debugMethod", "inc")
	end
	
	-- notify!
	if theZone:hasProperty("notify!") then 
		theZone.debugNotify = theZone:getStringFromZoneProperty("notify!", "<none>")
	end
	
	-- debug message, can use all messenger vals plus <f> for flag name 
	-- we use out own default
	-- with <f> meaning flag name, <p> previous value, <c> current value 
	theZone.debugMsg = theZone:getStringFromZoneProperty("debugMsg", "---debug: <t> -- Flag <f> changed from <p> to <c> [<z>]")
end

function debugger.createEventMonWithZone(theZone)
	local theFlags = theZone:getStringFromZoneProperty("events?", "<none>")
	local flagArray = cfxZones.flagArrayFromString(theFlags)
	local valueArray = {}
	-- now establish current values 
	if debugger.verbose or theZone.verbose then 
		debugger.outText("*** monitoring events defined in <" .. theZone.name .. ">:", 30)
	end
	for idx, aFlag in pairs(flagArray) do 
		local evt = tonumber(aFlag) 		
		if evt then 
			if evt < 0 then evt = 0 end 
			if evt > 57 then evt = 57 end 
			debugger.showEvents[evt] = debugDemon.eventList[tostring(evt)]
			if (debugger.verbose or theZone.verbose) then 
				debugger.outText("    monitoring event <" .. debugger.showEvents[evt] .. ">", 30)
			end
		end
	end
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
		theZone = cfxZones.createSimpleZone("debuggerConfig") 
	end 
	debugger.configZone = theZone 
	
	debugger.active = theZone:getBoolFromZoneProperty("active", true)
	debugger.verbose = theZone.verbose 
	
	if theZone:hasProperty("on?") then 
		debugger.onFlag = theZone:getStringFromZoneProperty("on?", "<none>")
		debugger.lastOn = cfxZones.getFlagValue(debugger.onFlag, theZone)
	end 

	if theZone:hasProperty("off?") then 
		debugger.offFlag = theZone:getStringFromZoneProperty("off?", "<none>")
		debugger.lastOff = cfxZones.getFlagValue(debugger.offFlag, theZone)
	end 

	if theZone:hasProperty("reset?") then 
		debugger.resetFlag = theZone:getStringFromZoneProperty("reset?", "<none>")
		debugger.lastReset = cfxZones.getFlagValue(debugger.resetFlag, theZone)
	end
	
	if theZone:hasProperty("state?") then 
		debugger.stateFlag = theZone:getStringFromZoneProperty("state?", "<none>")
		debugger.lastState = cfxZones.getFlagValue(debugger.stateFlag, theZone)
	end
	
	debugger.ups = theZone:getNumberFromZoneProperty("ups", 4)
end

function debugger.readSpawnTypeZone()
	local theZone = cfxZones.getZoneByName("debuggerSpawnTypes") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("debuggerSpawnTypes") 
	end 
	local allAttribuites = theZone:getAllZoneProperties()
	for attrName, aValue in pairs(allAttribuites) do 
		local theLow = string.lower(attrName)
		local before = debugger.spawnTypes[theLow]
		if before then 
			debugger.spawnTypes[theLow] = aValue
			if theZone.verbose or debugger.verbose then 
				trigger.action.outText("+++debug: changed generic '" .. theLow .. "' from <" .. before .. "> to <" .. aValue .. ">", 30)
			end
		else 
			if theZone.verbose or debugger.verbose then
				if theLow == "verbose" then -- filtered 
				else 
					trigger.action.outText("+++debug: generic '" .. theLow .. "' unknown, not replaced.", 30)
				end
			end 
		end 
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
	
	-- read spawn types 
	debugger.readSpawnTypeZone() 
	
	-- process debugger Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("debug?")
	for k, aZone in pairs(attrZones) do 
		debugger.createDebuggerWithZone(aZone) -- process attributes
		debugger.addDebugger(aZone) -- add to list
	end
	
	local attrZones = cfxZones.getZonesWithAttributeNamed("debug")
	for k, aZone in pairs(attrZones) do 
		debugger.outText("***Warning: Zone <" .. aZone.name .. "> has a 'debug' attribute. Are you perhaps missing a '?'", 30)
	end
	
	local attrZones = cfxZones.getZonesWithAttributeNamed("events?")
	for k, aZone in pairs(attrZones) do 
		debugger.createEventMonWithZone(aZone) -- process attributes
	end
	
	local attrZones = cfxZones.getZonesWithAttributeNamed("events")
	for k, aZone in pairs(attrZones) do 
		debugger.outText("***Warning: Zone <" .. aZone.name .. "> has an 'events' attribute. Are you perhaps missing a '?'", 30)
	end
	-- events 
	
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
	2.0.0 - eventmon 
	      - dml zones OOP 
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
debugDemon.activeIdx = -1 -- to detect if a window was close 
						  -- and prevent execution of debugger 
function debugDemon.hasMark(theString) 
	-- check if the string begins with the sequece to identify commands 
	if not theString then return false end
	return theString:find(debugDemon.markOfDemon) == 1
end


-- main hook into DCS. Called whenever a Mark-related event happens
-- very simple: look if text begins with special sequence, and if so, 
-- call the command processor. 
function debugDemon:onEvent(theEvent)
	-- first order of business: call the event monitor 
	debugDemon.doEventMon(theEvent)
	
	-- now process our own 
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
--		trigger.action.outText("debugger: Mark Change event received", 30)
		-- when changed, the mark's text is examined for a command
		-- if it starts with the 'mark' string ("-" by  default) it is processed
		-- by the command processor
		-- if it is processed succesfully, the mark is immediately removed
		-- else an error is displayed and the mark remains.
		if debugDemon.hasMark(theEvent.text) then 
			-- strip the mark 
			local cCommand = dcsCommon.clone(theEvent.text, true)
			local commandString = cCommand:sub(1+debugDemon.markOfDemon:len())
			-- break remainder apart into <command> <arg1> ... <argn>
			local commands = dcsCommon.splitString(commandString, debugDemon.splitDelimiter)

			-- this is a command. process it and then remove it if it was executed successfully
			local cTheEvent = dcsCommon.clone(theEvent, true) -- strip meta tables
			local args = {commands, cTheEvent}	
			-- defer execution for 0.1s to get out of trx bracked
			timer.scheduleFunction(debugDemon.deferredDebug, args, timer.getTime() + 0.1)
			debugDemon.activeIdx = cTheEvent.idx 
			--[[--
			local success = debugDemon.executeCommand(commands, cTheEvent) -- execute on a clone, not original 
						
			-- remove this mark after successful execution
			if success then 
				trigger.action.removeMark(theEvent.idx) 
			else 
				-- we could play some error sound
			end
			--]]--
		end 
    end 
	
	if theEvent.id == world.event.S_EVENT_MARK_REMOVED then
--		trigger.action.outText("Mark Remove received, removing idx <" .. theEvent.idx .. ">.", 30)
		debugDemon.activeIdx = nil 
    end
end

function debugDemon.deferredDebug(args)
--	trigger.action.outText("enter deferred debug command", 30)
--	if not debugDemon.activeIdx then 
--		trigger.action.outText("Debugger: window was closed, debug command ignored.", 30)
--		return 
--	end 
	local commands = args[1]
	local cTheEvent = args[2]
	local success = debugDemon.executeCommand(commands, cTheEvent) -- execute on a clone, not original 
				
	-- remove this mark after successful execution
	if success then 
		trigger.action.removeMark(cTheEvent.idx) 
		debugDemon.activeIdx = nil 
	else 
		-- we could play some error sound
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
-- debug demon's main command interpreter. 
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
	"\n  " .. debugDemon.markOfDemon .. "update <observername> [to] <condition> -- change observer's condition" ..
	"\n  " .. debugDemon.markOfDemon .. "drop <observername> -- remove observer from debugger" ..
	"\n  " .. debugDemon.markOfDemon .. "list [<match>] -- list observers [name contains <match>]" ..
	"\n  " .. debugDemon.markOfDemon .. "who <flagname> -- all who observe <flagname>" ..
	"\n  " .. debugDemon.markOfDemon .. "reset [<observername>] -- reset all or only the named observer" ..

	"\n\n  " .. debugDemon.markOfDemon .. "snap [<observername>] -- create new snapshot of flags" ..
	"\n  " .. debugDemon.markOfDemon .. "compare -- compare snapshot flag values with current" ..
	"\n  " .. debugDemon.markOfDemon .. "note <your note> -- add <your note> to the text log" ..
	"\n\n  " .. debugDemon.markOfDemon .. "spawn [<number>] [<coalition>] <type> [heading=<number>] | [?] -- spawn" .. 
	"\n               units/aircraft/objects (? for help)" ..
	"\n  " .. debugDemon.markOfDemon .. "remove <group/unit/object name> -- remove named item from mission" ..
	"\n  " .. debugDemon.markOfDemon .. "smoke <color> -- place colored smoke on the ground" ..
	"\n  " .. debugDemon.markOfDemon .. "boom <number> -- place explosion of strenght <number> on the ground" ..
	
	"\n\n  " .. debugDemon.markOfDemon .. "eventmon [all | off | <number> | ?] -- show events for all | none | event <number> | list" ..
	"\n  " .. debugDemon.markOfDemon .. "eventmon last -- analyse last reported event" ..
	"\n\n  " .. debugDemon.markOfDemon .. "q <Lua Var> -- Query value of Lua variable <Lua Var>" ..
	"\n  " .. debugDemon.markOfDemon .. "a <Lua Var> -- Analyse structure of Lua variable <Lua Var>" ..
	"\n  " .. debugDemon.markOfDemon .. "w <Lua Var> [=] <Lua Value> -- Write <Lua Value> to variable <Lua Var>" ..
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
	-- syntax update <observername> [to] <condition>
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
	local snapshot = debugDemon.createSnapshot(allObservers) 
	
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
	
	local newVal = trigger.misc.getUserFlag(theName)
	if theVal ~= newVal then 
		debugger.outText("*** [" .. dcsCommon.nowString() .. "] debug: readback failure for flag <" .. theName .. ">: expected <" .. theVal .. ">, got <" .. newVal .. "!", 30)
	end 
	
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

function debugDemon.processRemoveCommand(args, event)
	-- remove a group, unit or object 
	-- try group first 
	local aName = event.remainder
	if not aName or aName:len() < 1 then 
		debugger.outText("*** remove: no remove target", 30)
		return false
	end
	
	aName = dcsCommon.trim(aName)
	local theGroup = Group.getByName(aName)
	if theGroup and theGroup:isExist() then 
		theGroup:destroy()
		debugger.outText("*** remove: removed group <" .. aName .. ">", 30)
		return true
	end
	
	local theUnit = Unit.getByName(aName)
	if theUnit and theUnit:isExist() then 
		theUnit:destroy()
		debugger.outText("*** remove: removed unit <" .. aName .. ">", 30)
		return true
	end
	
	local theStatic = StaticObject.getByName(aName)
	if theStatic and theStatic:isExist() then 
		theStatic:destroy()
		debugger.outText("*** remove: removed static object <" .. aName .. ">", 30)
		return true
	end
	debugger.outText("*** remove: did not find anything called <" .. aName .. "> to remove", 30)
		return true
end

function debugDemon.doEventMon(theEvent)
	if not theEvent then return end 
	if not debugger.active then return end 
	local ID = theEvent.id 
	if debugger.showEvents[ID] then
		-- we show this event 
		m = "*** event <" .. debugger.showEvents[ID] .. ">"
		-- see if we have initiator
		if theEvent.initiator then 
			local theUnit = theEvent.initiator
			if Unit.isExist(theUnit) then 
				m = m .. " for "
				if theUnit.getPlayerName and theUnit:getPlayerName() then 
					m = m .. "player = " .. theUnit:getPlayerName() .. " in "
				end
				m = m .. "unit <" .. theUnit:getName() .. ">"
			end 
		end 
		debugger.outText(m, 30)
		-- save it to lastevent so we can analyse 
		debugger.lastEvent = theEvent 
	end
end 

debugDemon.m = ""
-- dumpVar2m, invoke externally dumpVar2m(varname, var)
function debugDemon.dumpVar2m(key, value, prefix, inrecursion)
	-- based on common's dumpVar, appends to var "m" 
	if not inrecursion then 
		-- start, init m
		debugDemon.m = "analysis of <" .. key .. ">\n==="
	end
	if not value then value = "nil" end
	if not prefix then prefix = "" end
	prefix = " " .. prefix
	if type(value) == "table" then 
		debugDemon.m = debugDemon.m .. "\n" .. prefix .. key .. ": [ "
		-- iterate through all kvp
		for k,v in pairs (value) do
			debugDemon.dumpVar2m(k, v, prefix, true)
		end
		debugDemon.m = debugDemon.m .. "\n" .. prefix .. " ] - end " .. key
		
	elseif type(value) == "boolean" then 
		local b = "false"
		if value then b = "true" end
		debugDemon.m = debugDemon.m .. "\n" .. prefix .. key .. ": " .. b

	else -- simple var, show contents, ends recursion
		debugDemon.m = debugDemon.m .. "\n" .. prefix .. key .. ": " .. value
	end
	
	if not inrecursion then 
		-- output a marker to find in the log / screen
		debugDemon.m = debugDemon.m .. "\n" .. "=== analysis end\n"
	end
end

function debugDemon.processEventMonCommand(args, event)
	-- turn event monitor all/off/?/last  
	-- syntax: -eventmon  on|off 
	local aParam = dcsCommon.trim(event.remainder)
	if not aParam or aParam:len() < 1 then 
		aParam = "all"
	end
	aParam = string.upper(aParam)
	evtNum = tonumber(aParam)
	if aParam == "ON" or aParam == "ALL" then 
		debugger.outText("*** eventmon: turned ON, showing ALL events", 30)
		local events = {}
		for idx,evt in pairs(debugDemon.eventList) do 
			events[tonumber(idx)] = evt
		end 
		debugger.showEvents = events 
	elseif evtNum then -- add the numbered to 
		debugger.eventmon = false 
		if evtNum <= 0 then evtNum = 0 end 
		if evtNum >= 57 then evtNum = 35 end 
		debugger.showEvents[evtNum] = debugDemon.eventList[tostring(evtNum)] 
		debugger.outText("*** eventmon: added event <" .. debugger.showEvents[evtNum] .. ">", 30)
	elseif aParam == "OFF" then 
		debugger.showEvents = {}
		debugger.outText("*** eventmon: removed all events from monitor list", 30)
	elseif aParam == "?" then 
		local m = "*** eventmon: currently tracking these events:"
		for idx, evt in pairs(debugger.showEvents) do 
			m = m .. "\n" ..  evt 
		end			
		debugger.outText(m .. "\n*** end of list", 30)
	elseif aParam == "LAST" then 
		if debugger.lastEvent then 
			debugDemon.dumpVar2m("event", debugger.lastEvent)
			debugger.outText(debugDemon.m, 39)
		else 
			debugger.outText("*** eventmon: no event on record", 39)
		end
	else 
		debugger.outText("*** eventmon: unknown parameter <" .. event.remainder .. ">", 30)
	end
	return true 
end 

--
-- read and write directly to Lua tables
--

function debugDemon.processQueryCommand(args, event)
	-- syntax -q <name> with name a (qualified) Lua table reference 
	local theName = args[1]

	if not theName then 
		debugger.outText("*** q: missing Lua table/element name.", 30)
		return false -- allows correction 
	end
	theName = dcsCommon.stringRemainsStartingWith(event.remainder, theName)

	-- put this into a string, and execute it 
	local exec = "return " .. theName 
	local f = loadstring(exec) 
	local res
	if pcall(f) then 
		res = f()
		if type(res) == "boolean" then 
			res = "[BOOL FALSE]"
			if res then res = "[BOOL TRUE]" end 
		elseif type(res) == "table" then res = "[Lua Table]"
		elseif type(res) == "nil" then res = "[NIL]"
		elseif type(res) == "function" then res = "[Lua Function]"
		elseif type(res) == "number" or type(res) == "string" then 
			res = res .. " (a " .. type(res) .. ")"
		else res = "[Lua " .. type(res) .. "]"
		end
	else 
		res = "[Lua error]"
	end 
	
	debugger.outText("[" .. dcsCommon.nowString() .. "] <" .. theName .. "> = ".. res, 30)
	
	return true 
end

function debugDemon.processAnalyzeCommand(args, event)
	-- syntax -a <name> with name a (qualified) Lua table reference 
	local theName = args[1]

	if not theName then 
		debugger.outText("*** a: missing Lua table/element name.", 30)
		return false -- allows correction 
	end
	theName = dcsCommon.stringRemainsStartingWith(event.remainder, theName)

	-- put this into a string, and execute it 
	local exec = "return " .. theName 
	local f = loadstring(exec) 
	local res
	if pcall(f) then 
		res = f()
		debugDemon.dumpVar2m(theName, res)
		res = debugDemon.m
	else 
		res = "[Lua error]"
	end 
	
	debugger.outText("[" .. dcsCommon.nowString() .. "] <" .. theName .. "> = ".. res, 30)
	
	return true 
end

function debugDemon.processWriteCommand(args, event)
	-- syntax -w <name> <value> with name a (qualified) Lua table reference and value a Lua value (including strings, with quotes of course). {} means an empty set etc. you CAN call into DCS MSE with this, and create a lot of havoc.
	-- also, allow "=" semantic, -w p = {x=1, y=2}
	
	local theName = args[1]
	if not theName then 
		debugger.outText("*** w: missing Lua table/element name.", 30)
		return false -- allows correction 
	end
	local param = args [2]
	if param == "=" then param = args[3] end 
	if not param then 
		debugger.outText("*** w: missing value to set to")
		return false 
	end 

	param = dcsCommon.stringRemainsStartingWith(event.remainder, param)

	-- put this into a string, and execute it 
	local exec = theName .. " = " .. param 
	local f = loadstring(exec) 
	local res
	if pcall(f) then 
		res = "<" .. theName .. "> set to <" .. param .. ">"
	else 
		res = "[Unable to set - Lua error]"
	end 
	
	debugger.outText("[" .. dcsCommon.nowString() .. "] " .. res, 30)
	
	return true 
end

--
-- smoke & boom 
-- 

function debugDemon.processSmokeCommand(args, event)
	-- syntax -color 
	local color = 0 -- green default 
	local colorCom = args[1]
	if colorCom then 
		colorCom = colorCom:lower()
		if colorCom == "red" or colorCom == "1" then color = 1
		elseif colorCom == "white" or colorCom == "2" then color = 2 
		elseif colorCom == "orange" or colorCom == "3" then color = 3 
		elseif colorCom == "blue" or colorCom == "4" then color = 4
		elseif colorCom == "green" or colorCom == "0" then color = 0
		else 
			debugger.outText("*** smoke: unknown color <" .. colorCom .. ">, using green.", 30)
		end 
		local pos = event.pos 
		local h = land.getHeight({x = pos.x, y = pos.z}) + 1
		local p = { x = event.pos.x, y = h, z = event.pos.z} 
		trigger.action.smoke(p, color)
		debugger.outText("*** smoke: placed smoke at <" .. dcsCommon.point2text(p, true) .. ">.", 30)
	end 
end 

function debugDemon.processBoomCommand(args, event)
	-- syntax -color 
	local power = 1 -- boom default 
	local powerCom = args[1]
	if powerCom then 
		powerCom = tonumber(powerCom)
		if powerCom then
			power = powerCom
		end 
	end
	local pos = event.pos 
	local h = land.getHeight({x = pos.x, y = pos.z}) + 1
	local p = { x = event.pos.x, y = h, z = event.pos.z} 
	trigger.action.explosion(p, power)
	debugger.outText("*** boom: placed <" .. power .. "> explosion at <" .. dcsCommon.point2text(p, true) .. ">.", 30) 
end 

--
-- spawning units at the location of the mark 
--

function debugDemon.getCoaFromCommand(args)
	for i=1, #args do
		local aParam = args[i]
		if dcsCommon.stringStartsWith(aParam, "red", true) then return 1, i end
		if dcsCommon.stringStartsWith(aParam, "blu", true) then return 2, i end
		if dcsCommon.stringStartsWith(aParam, "neu", true) then return 0, i end
	end
	return 0, nil  
end 

function debugDemon.getAirFromCommand(args)
	for i=1, #args do
		local aParam = args[i]
		if aParam:lower() == "inair" then return true, i end
		if aParam:lower() == "air" then return true, i end
	end
	return false, nil  
end 

function debugDemon.getHeadingFromCommand(args)
	for i=1, #args do
		local aParam = args[i]
		if dcsCommon.stringStartsWith(aParam, "heading=", true) then 
			local parts = dcsCommon.splitString(aParam, "=")
			local num = parts[2]
			if num and tonumber(num) then 
				return tonumber(num), i
			end 
		end
	end
	return 0, nil  
end

function debugDemon.getNumFromCommand(args)
	for i=1, #args do
		local aParam = args[i]
		local num = tonumber(aParam)
		if num then return num, i end
	end
	return 1, nil  
end 

function debugDemon.processSpawnCommand(args, event)
	-- complex syntax: 
	-- spawn [red|blue|neutral] [number] <type> [heading=<number>] | "?"
	local params = dcsCommon.clone(args)
--	for i=1, #params do 
--		trigger.action.outText("arg[" .. i .."] = <" .. params[i] .. ">", 30)
--	end
	
	-- get coalition from input 
	
	local coa, idx = debugDemon.getCoaFromCommand(params)
	if idx then table.remove(params, idx) end 
	local inAir, idy = debugDemon.getAirFromCommand(params)
	if idy then table.remove(params, idy) end
	local num, idz = debugDemon.getNumFromCommand(params)
	if idz then table.remove(params, idz) end 
	local heading, idk = debugDemon.getHeadingFromCommand(params)
	if idk then table.remove(params, idk) end 
	
	local class = params[1]
	if not class then 
		debugger.outText("*** spawn: missing keyword (what to spawn).", 30)
		return 
	end 
	
	class = class:lower() 
	
	-- when we are here, we have reduced all params, so class is [1]
--	trigger.action.outText("spawn with class <" .. class .. ">, num <" .. num .. ">, inAir <" .. dcsCommon.bool2Text(inAir) .. ">, coa <" .. coa .. ">, hdg <" .. heading .. ">", 30)
	heading = heading  * 0.0174533 -- in rad 
	
	local pos = event.pos 
	local h = land.getHeight({x = pos.x, y = pos.z}) + 1
	local p = { x = event.pos.x, y = h, z = event.pos.z} 
		
	if class == "tank" or class == "tanks" then 
		-- spawn the 'tank' class 
		local theType = debugger.spawnTypes["tank"]
		return debugDemon.spawnTypeWithCat(theType, coa, num, p,  nil,heading)
	elseif class == "man" or class == "soldier" or class == "men" then 
		local theType = debugger.spawnTypes["inf"]
		return debugDemon.spawnTypeWithCat(theType, coa, num, p,  nil,heading)
	
	elseif class == "inf" or class == "ifv" or class == "sam" or 
	       class == "arty" or class == "aaa" then 
		local theType = debugger.spawnTypes[class]
		return debugDemon.spawnTypeWithCat(theType, coa, num, p,  nil,heading)
	elseif class == "truck" or class == "trucks" then 
		local theType = debugger.spawnTypes["truck"]
		return debugDemon.spawnTypeWithCat(theType, coa, num, p,  nil,heading)	
	elseif class == "manpad" or class == "manpads" or class == "pad" or class == "pads" then 
		local theType = debugger.spawnTypes["manpad"]
		return debugDemon.spawnTypeWithCat(theType, coa, num, p,  nil,heading)

	elseif class == "ship" or class == "ships" then 
		local theType = debugger.spawnTypes["ship"]
		return debugDemon.spawnTypeWithCat(theType, coa, num, p, Group.Category.SHIP, heading)

	elseif class == "jet" or class == "jets" then 
		local theType = debugger.spawnTypes["jet"]
		return debugDemon.spawnAirWIthCat(theType, coa, num, p, nil, 1000, 160, heading)

	elseif class == "ww2" then 
		local theType = debugger.spawnTypes[class]
		return debugDemon.spawnAirWIthCat(theType, coa, num, p, nil, 1000, 100, heading)

	elseif class == "bomber" or class == "awacs" then 
		local theType = debugger.spawnTypes[class]
		return debugDemon.spawnAirWIthCat(theType, coa, num, p, nil, 8000, 200, heading)
		
	elseif class == "drone" then 
		local theType = debugger.spawnTypes[class]
		return debugDemon.spawnAirWIthCat(theType, coa, num, p, nil, 3000, 77, heading)
	
	elseif class == "helo" or class == "helos" then 
		local theType = debugger.spawnTypes["helo"]
		return debugDemon.spawnAirWIthCat(theType, coa, num, p, Group.Category.HELICOPTER, 200, 40, heading)
		
	elseif class == "cargo" or class == "obj" then 
		local isCargo = (class == "cargo") 
		local theType = debugger.spawnTypes[class]
		return debugDemon.spawnObjects(theType, coa, num, p, isCargo, heading)
	
	elseif class == "?" then 
		local m = " spawn: invoke '-spawn [number] [coalition] <type> [heading]' with \n" ..
		" number = any number, default is 1\n" ..
		" coalition = 'red' | 'blue' | 'neutral', default is neutral\n" ..
		" heading = 'heading=<number>' - direction to face, in degrees, no blanks\n" ..
		" <type> = what to spawn, any of the following pre-defined (no quotes)\n" ..
		"   'tank' - a tank " .. debugDemon.tellType("tank") .. "\n" ..
		"   'ifv' - an IFV " .. debugDemon.tellType("ifv") .. "\n" ..
		"   'inf' - an infantry soldier " .. debugDemon.tellType("inf") .. "\n" ..
		"   'sam' - a SAM vehicle " .. debugDemon.tellType("sam") .. "\n" .. 
		"   'aaa' - a AAA vehicle " .. debugDemon.tellType("aaa") .. "\n" ..
		"   'arty' - artillery vehicle " .. debugDemon.tellType("arty") .. "\n" ..
		"   'manpad' - a soldier with SAM " .. debugDemon.tellType("manpad") .. "\n" ..
		"   'truck' - a truck " .. debugDemon.tellType("truck") .. "\n\n" ..
		"   'jet' - a fast aircraft " .. debugDemon.tellType("jet") .. "\n" ..
		"   'ww2' - a warbird " .. debugDemon.tellType("ww2") .. "\n" ..
		"   'bomber' - a heavy bomber " .. debugDemon.tellType("bomber") .. "\n" ..
		"   'awacs' - an AWACS plane " .. debugDemon.tellType("awacs") .. "\n" ..
		"   'drone' - a drone " .. debugDemon.tellType("drone") .. "\n" ..
		"   'helo' - a helicopter " .. debugDemon.tellType("helo") .. "\n\n" ..
		"   'ship' - a naval unit" .. debugDemon.tellType("ship") .. "\n\n" ..
		"   'cargo' - some helicopter cargo " .. debugDemon.tellType("cargo") .. "\n" ..
		"   'obj' - a static object " .. debugDemon.tellType("obj") .. "\n" 
		
		debugger.outText(m, 30)
		return true 
	else 
		debugger.outText("*** spawn: unknown kind <" .. class .. ">.", 30)
		return false 
	end 
end

function debugDemon.tellType(theType)
	return " [" .. debugger.spawnTypes[theType] .. "]"
end 

function debugDemon.spawnTypeWithCat(theType, coa, num, p, cat, heading)
	trigger.action.outText("heading is <" .. heading .. ">", 30)
	if not cat then cat = Group.Category.GROUND end 
	if not heading then heading = 0 end 
	
	local xOff = 0
	local yOff = 0
	-- build group 
	local groupName = dcsCommon.uuid(theType)
	local gData = dcsCommon.createEmptyGroundGroupData(groupName)
	for i=1, num do 
		local aUnit = {}
		aUnit = dcsCommon.createGroundUnitData(groupName .. "-" .. i, theType)
		--aUnit.heading = heading 
		dcsCommon.addUnitToGroupData(aUnit, gData, xOff, yOff, heading)
		xOff = xOff + 10 
		yOff = yOff + 10
	end 
	
	-- arrange in a grid formation
	local radius = math.floor(math.sqrt(num) * 10)
	if cat == Group.Category.SHIP then 
		radius = math.floor(math.sqrt(num) * 100)
	end 
	
	dcsCommon.arrangeGroupDataIntoFormation(gData, radius, 10, "GRID")
	
	-- move to destination 
	dcsCommon.moveGroupDataTo(gData, p.x, p.z)

	-- spawn 
	local cty = dcsCommon.getACountryForCoalition(coa)
	local theGroup = coalition.addGroup(cty, cat, gData)
	if theGroup then 
		debugger.outText("[" .. dcsCommon.nowString() .. "] created units at " .. dcsCommon.point2text(p, true), 30)
		return true
	else 
		debugger.outText("[" .. dcsCommon.nowString() .. "] failed to created units", 30)
		return false
	end 
	return false
end 

function debugDemon.spawnAirWIthCat(theType, coa, num, p, cat, alt, speed, heading)
	if not cat then cat = Group.Category.AIRPLANE end 
	local xOff = 0
	local yOff = 0
	-- build group 
	local groupName = dcsCommon.uuid(theType)
	local gData = dcsCommon.createEmptyAircraftGroupData(groupName)
	for i=1, num do 
		local aUnit = {}
		aUnit = dcsCommon.createAircraftUnitData(groupName .. "-" .. i, theType, false, alt, speed)
		--aUnit.heading = heading 
		dcsCommon.addUnitToGroupData(aUnit, gData, xOff, yOff, heading)
		xOff = xOff + 30 
		yOff = yOff + 30
	end 
	-- move to destination 
	dcsCommon.moveGroupDataTo(gData, p.x, p.z)

	-- make waypoints: initial point and 200 km away in direction heading
	local p2 = dcsCommon.pointInDirectionOfPointXYY(heading, 200000, p)
	local wp1 = dcsCommon.createSimpleRoutePointData(p, alt, speed)
	local wp2 = dcsCommon.createSimpleRoutePointData(p2, alt, speed)
	-- add waypoints 
	dcsCommon.addRoutePointForGroupData(gData, wp1)
	dcsCommon.addRoutePointForGroupData(gData, wp2)
	
	-- spawn 
	local cty = dcsCommon.getACountryForCoalition(coa)
	local theGroup = coalition.addGroup(cty, cat, gData)
	if theGroup then 
		debugger.outText("[" .. dcsCommon.nowString() .. "] created air units at " .. dcsCommon.point2text(p, true), 30)
		return true
	else 
		debugger.outText("[" .. dcsCommon.nowString() .. "] failed to created air units", 30)
		return false
	end 
end

function debugDemon.spawnObjects(theType, coa, num, p, cargo, heading)
	if not cargo then cargo = false end 
	local cty = dcsCommon.getACountryForCoalition(coa)
	local xOff = 0
	local yOff = 0
	local success = false 
	-- build static objects and spawn individually
	for i=1, num do 
		local groupName = dcsCommon.uuid(theType)
		local gData = dcsCommon.createStaticObjectData(groupName, theType, 0, false, cargo, 1000)
		gData.x = xOff + p.x 
		gData.y = yOff + p.z 
		gData.heading = heading
		local theGroup = coalition.addStaticObject(cty, gData)
		success = theGroup
		xOff = xOff + 10 -- stagger by 10m, 10m 
		yOff = yOff + 10
	end 
	
	-- was it worth it?
	if success then 
		debugger.outText("[" .. dcsCommon.nowString() .. "] created objects at " .. dcsCommon.point2text(p, true), 30)
		return true
	else 
		debugger.outText("[" .. dcsCommon.nowString() .. "] failed to create objects", 30)
		return false
	end 
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

	debugDemon.addCommndProcessor("remove", debugDemon.processRemoveCommand)
	debugDemon.addCommndProcessor("spawn", debugDemon.processSpawnCommand)
	debugDemon.addCommndProcessor("add", debugDemon.processSpawnCommand)

	debugDemon.addCommndProcessor("eventmon", debugDemon.processEventMonCommand)
	debugDemon.addCommndProcessor("q", debugDemon.processQueryCommand)
	debugDemon.addCommndProcessor("w", debugDemon.processWriteCommand)
	debugDemon.addCommndProcessor("a", debugDemon.processAnalyzeCommand)
	debugDemon.addCommndProcessor("smoke", debugDemon.processSmokeCommand)
	debugDemon.addCommndProcessor("boom", debugDemon.processBoomCommand)
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
	trigger.action.outText("*** interactive debugger failed to initialize.", 30)
	debugDemon = {}
end

--[[--
	- track units/groups/objects: health changes 
	- track players: unit change, enter, exit 
	- inspect objects, dumping category, life, if it's tasking, latLon, alt, speed, direction 
	
	- exec files. save all commands and then run them from script 
	
	- xref: which zones/attributes reference a flag, g.g. '-xref go'
		
	- track lua vars for change in value
	
--]]--
