tcli = {}
tcli.version = "1.1.0"

--[[--
	Tickle - a tiny DCS admin CLI (c) 2024 by Christian "CFrag" Franz 
	
	Version History
	1.1.0 	- endTime init to very, very late 
			- more mission begin load logging 
			- stronger guards for onXXX
			- "-shuffle" and "-sequence" commands 
			- better -? response
			- drove sample time up to 50 seconds between scans
			- "-cycle" command
--]]--

tcli.myConfig = lfs.writedir() .. "Missions\\" .. "tcli.config"
tcli.serverCfgPath = lfs.writedir() .. "Config\\" .. "serverSettings.lua"
tcli.lastTime = -1 
local config = {}
config.mark = "-"
config.admins = {} -- who is allowed to command
config.cycleTime = -1 -- no cycles, auto miz change off 
table.insert(config.admins, "xk76hkl@01") -- some silly user names.  
table.insert(config.admins, "%tgJsgRG1<") -- change to your own in the config file that is created in Missions AFTER DCS starts up
tcli.config = config
	
-- utils
function tcli.hasFile(path) --check if file exists at path
    local attr = lfs.attributes(path) 
	if attr then return true, attr.mode	end 	
	return false
end

function tcli.loadFile(path)
	if not path then return nil end
	local theFile = io.open(path, "r") 
	if not theFile then return nil end
	local t = theFile:read("*a")
	theFile:close()
	return t 
end 

function tcli.loadData(path) -- load file as lua table, full path in fileName
	local t = tcli.loadFile(path)
	if not t then return nil end 
	local d = net.json2lua(t)
	return d
end

function tcli.saveData(path, theData) -- save theData (table) as json text file
	if not theData then return false end 
	local theString = net.lua2json(theData)
	if not theString then theString = "" end 	
	local theFile = nil 
	theFile = io.open(path, "w") -- overwrite 
	if not theFile then return false end
	theFile:write(theString)
	theFile:close()
	return true 
end

function tcli.nameInTable(name, T)
	for idx, aName in pairs(T) do 
		if name == aName then return true end
	end
	return false 
end

-- save a lua table to file 
function tcli.saveLuaTable(path, theTable, theName)
	local theFile = nil 
	theFile = io.open(path, "w") -- overwrite
	tcli.writeTable(theFile, theName, theTable)
	theFile:write("\n-- tickled by tcli")
	theFile:close()
end

function tcli.writeTable(theFile, key, value, prefix, inrecursion)
	local comma = ""
	if inrecursion then 
		if tonumber(key) then key = '[' .. key .. ']' else key = '["' .. key .. '"]' end
		comma = ","
	end 
	if not value then value = false end -- not NIL!
	if not prefix then prefix = "" else prefix = "\t" .. prefix end
	if type(value) == "table" then -- recursively write a table
		theFile:write(prefix .. key .. " = \n" .. prefix .. "{\n")
		for k,v in pairs (value) do -- iterate all kvp
			tcli.writeTable(theFile, k, v, prefix, true)
		end
		theFile:write(prefix .. "}" .. comma .. " -- end of " .. key .. "\n")
	elseif type(value) == "boolean" then 
		local b = "false"
		if value then b = "true" end
		theFile:write(prefix .. key .. " = " .. b .. comma .. "\n")
	elseif type(value) == "string" then -- quoted string, WITH proccing
		value = string.gsub(value, "\\", "\\\\") -- escape "\" to "\\", others ignored, possibly conflict with \n
		value = string.gsub(value, string.char(10), "\\" .. string.char(10)) -- 0A --> "\"0A
		theFile:write(prefix .. key .. ' = "' .. value .. '"' .. comma .. "\n")
	else -- simple var, show contents, ends recursion
		theFile:write(prefix .. key .. " = " .. value .. comma .. "\n")
	end
end
	
-- CLI for admins --
function tcli.adminCall(playerID, line) -- returns string
	-- break line into space-delimited commands 
	local cmd = {}
	local sep = " "
    for str in string.gmatch(line, "([^"..sep.."]+)") do
		table.insert(cmd, str)
    end
	if #cmd < 1 then return "adm: input error" end 
	local c = cmd[1]
	if c then c = string.upper(c) end 
	if c == "?" then return tcli.help() end 
	if c == "NEXT" then return tcli.nextMission() end 
	if c == "PREV" or c == "PREVIOUS" then return tcli.previousMission() end
	if c == "RANDOM" then return tcli.randomMission() end 
	if c == "RESTART" then return tcli.restartMission() end 
	if c == "PAUSE" then return tcli.pauseMission(true) end 
	if c == "PLAY" then return tcli.pauseMission(false) end 
	if c == "CYCLETIME" then return tcli.cycleTime(cmd[2]) end 
	if c == "SHUFFLE" then return tcli.shuffle() end 
	if c == "SEQ" or c == "SEQUENCE" then return tcli.unshuffle() end 
	if c == "CYCLE" then return tcli.cycleNow() end  
	return "cli: unknown command <" .. c .. ">"
end

function tcli.help()
	local cycleStatus = "Disabled automatic mission change"
	if not tcli.config.cycleTime then tcli.config.cycleTime = -1 end 
	if	tcli.config.cycleTime >= 1 then
		local now = DCS.getModelTime()
		if not tcli.endTime then tcli.endTime = 99999999 end 
		local remains = tcli.endTime - now  	
		cycleStatus = "AUTOMATIC MISSION CHANGE EVERY " .. tcli.config.cycleTime .. " MINUTES, " .. tcli.num2ms(remains) .. " MMM:SS remaining"		
	end 
	if tcli.cfg.listShuffle then cycleStatus = cycleStatus .. ", shuffle ON" else cycleStatus = cycleStatus .. ", NO shuffle" end 
	local s = "CLI v" .. tcli.version .. ": -? (help), -next, -previous, -restart, -random, -cycle, -pause, -play, -cycleTime, -shuffle, -sequence"
	s = s .. "                                                       " .. cycleStatus
	return s
end

function tcli.getMsnIndex()
	local curr = DCS.getMissionFilename( ) -- gets full path
	for x, msn in pairs(tcli.cfg.missionList) do 
		if msn == curr then return x end
	end
	return 1
end

function tcli.nextMission() -- automatically loops if on last 
	if #tcli.cfg.missionList < 2 then 
		return xli.restartMission() 
	end
	local idx = tcli.getMsnIndex() + 1 
	if idx > #tcli.cfg.missionList then idx = 1 end 
	local new = tcli.cfg.missionList[idx]
	tcli.cfg.listStartIndex = idx
	tcli.cfg.lastSelectedMission = new
	tcli.saveLuaTable(tcli.serverCfgPath, tcli.cfg, "cfg")
	net.log("tcli: Starting next mission in sequence: <" .. new .. ">.")
	net.load_mission(new)
	return "Loading next mission (" .. new .. ")."
end 

function tcli.previousMission() -- automatically loops if on first 
	if #tcli.cfg.missionList < 2 then 
		return xli.restartMission() 
	end
	local idx = tcli.getMsnIndex() - 1 
	if idx < 1 then idx = #tcli.cfg.missionList end 
	local new = tcli.cfg.missionList[idx]
	tcli.cfg.listStartIndex = idx
	tcli.cfg.lastSelectedMission = new
	tcli.saveLuaTable(tcli.serverCfgPath, tcli.cfg, "cfg")
	net.log("tcli: Starting previous mission in sequence: <" .. new .. ">.")
	net.load_mission(new)
	return "Loading previous mission (" .. new .. ")."
end 

function tcli.restartMission()
	local curr = DCS.getMissionFilename()
	net.load_mission(curr)
	return "re-starting mission (" .. curr .. ")"
end

function tcli.randomMission()
	if #tcli.cfg.missionList < 2 then return xli.restartMission() end
	local curr = DCS.getMissionFilename() -- gets full path
	local count = 0 
	local new 
	local pick 
	repeat
		pick = math.random(1, #tcli.cfg.missionList)
		new = tcli.cfg.missionList[pick]
		count = count + 1
	until (count > 20) or (new ~= curr)
	if count > 20 then return "mission picker error" end 
	tcli.cfg.listStartIndex = pick
	tcli.cfg.lastSelectedMission = new
	tcli.saveLuaTable(tcli.serverCfgPath, tcli.cfg, "cfg")
	net.log("tcli: Starting random mission: <" .. new .. ">.")
	net.load_mission(new)
	return "Starting random mission: " .. new 
end

function tcli.pauseMission(doPause) 
	DCS.setPause(doPause)
	if doPause then return "Pausing Mission" end 
	return "Mission continues" 
end

function tcli.num2ms(num)
	mins = math.floor(num / 60)
	sec = math.floor(num%60) 
	return string.format("%03d", mins) .. ":" .. string.format("%02d", sec)
end

function tcli.cycleTime(param)
	if not param then 
		if tcli.config.cycleTime and tcli.config.cycleTime >= 1 then 
			local now = DCS.getModelTime()
		    local remains = tcli.endTime - now 
			return "AUTOMATIC MISSION CHANGE AFTER " .. tcli.config.cycleTime .. " MINUTES -- now scheduled in " .. tcli.num2ms(remains) .. " MMM:SS" 
		end
		return "DIASBLED automatic mission change"
	end
	local num = tonumber(param)
	if not num then num = -1 end 
	tcli.config.cycleTime = num
	tcli.saveData(tcli.myConfig, tcli.config)
	if num >= 1 then tcli.endTime = tcli.config.cycleTime * 60
	else tcli.endTime = 0 end 
	if num >= 1 then return "ENABLED automatic mission change after " .. tcli.config.cycleTime .. " minutes" end 
	return "Turned OFF automatic mission change"
end

function tcli.shuffle()
	tcli.cfg.listShuffle = true 
	tcli.saveLuaTable(tcli.serverCfgPath, tcli.cfg, "cfg")
	return "Mission order is now randomized (shuffled)"
end	

function tcli.unshuffle()
	tcli.cfg.listShuffle = false 
	tcli.saveLuaTable(tcli.serverCfgPath, tcli.cfg, "cfg")
	return "Missions now play in sequence"
end

function tcli.cycleNow()
	if tcli.cfg.listShuffle then -- randomized playlist 
		tcli.randomMission()
		return "Immediately cyling to random mission."
	end  -- next, will loop 
	tcli.nextMission()
	return "Immediately cycling to next mission."
end 
--
-- CLI MAIN ENTRY, command in message 
--
function tcli.onPlayerTrySendChat(playerID, message, all )
	if not DCS.isServer() then return end 
	if not DCS.isMultiplayer() then return end 
	local name = net.get_player_info(playerID, 'name')
	-- check to see if message starts with cli mark 
	local i, j = string.find(message, tcli.config.mark, 1, true)
	if i == 1 then -- line starts with cli prompt
		if tcli.nameInTable(name, tcli.config.admins) then
			message = message:sub(1 + #tcli.config.mark)
			local msg = tcli.adminCall(playerID, message)
			net.send_chat_to(msg, playerID) -- player only 
			return "" -- while line output 
		end 
	end 
end 

function tcli.getServerConfig()
	-- load/update server config into cfg 
	local s = tcli.loadFile(tcli.serverCfgPath)
	net.log("tcli: loaded server config file: " .. s)
	cfg = nil -- nil before loadString 
	f = loadstring(s)
	f() -- define conf so we have access to serverconfig 
	if cfg then tcli.cfg = cfg end 
end

function tcli.onMissionLoadBegin() -- reload to avoid DCS restart
	if not DCS.isServer() then return end 
	if not DCS.isMultiplayer() then return end 
	tcli.getServerConfig() -- update current list of missions 
	tcli.lastTime = 0
	tcli.hasWarned5 = false 
	tcli.hasWarned1 = false 
	tcli.endTime = 99999999 -- very, very late 
	local d  = tcli.loadData(tcli.myConfig) -- update config 
	if d then tcli.config = d end
	if tcli.config.cycleTime and tcli.config.cycleTime >= 1 then
		tcli.endTime = tcli.config.cycleTime * 60 -- in minutes!
	end 
	net.log("tcli: Mission <" ..  DCS.getMissionName() .. ">: Mission Load Begin - Inited tcli.endTime to <" .. tcli.endTime .. ">.")
end

function tcli.update()
	local now = DCS.getModelTime()
	-- if cycle time is enabled, we check if we need to advance the Mission
	if tcli.config.cycleTime and tcli.config.cycleTime >= 1 then 
		local remains = tcli.endTime - now 
		-- warning broadcasts
		if not tcli.hasWarned5 and remains < 5 * 60 then 
			net.send_chat("THIS MISSION ENDS IN 5 MINUTES", true)
			tcli.hasWarned5 = true 
		end
		if not tcli.hasWarned1 and remains < 60 then 
			net.send_chat("THIS MISSION ENDS IN 1 MINUTE", true)
			tcli.hasWarned1 = true 
		end
		if remains < 0 then 
			if tcli.cfg.listShuffle then -- randomized playlist 
				tcli.randomMission()
			else  -- next, will loop 
				tcli.nextMission()
			end 
		end
	end
end

function tcli.onSimulationFrame()
	if not DCS.isServer() then return end 
	if not DCS.isMultiplayer() then return end 
	-- every 50 seconds we do an update. not during pause!
	if tcli.lastTime + 50 < DCS.getModelTime() then
		tcli.update()
		tcli.lastTime = DCS.getModelTime()
	end
end 

-- start up 
if tcli.hasFile(tcli.myConfig) then 
	local d  = tcli.loadData(tcli.myConfig)
	if d then 
		tcli.config = d
		net.log("tcli: successfuly read existing config file") 
	else 
		net.log("tcli: ERROR LOADING CONFIG FILE. DELETE AND TRY AGAIN.")
	end 
else 
	tcli.saveData(tcli.myConfig, tcli.config)
	net.log("tcli: created new tcli config file.")
end 

-- hook into dcs server 
DCS.setUserCallbacks(tcli)
