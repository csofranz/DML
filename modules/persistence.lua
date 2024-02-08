persistence = {}
persistence.version = "2.0.0"
persistence.ups = 1 -- once every 1 seconds 
persistence.verbose = false 
persistence.active = false 
persistence.saveFileName = nil -- "mission data.txt"
persistence.sharedDir = nil -- not yet implemented
persistence.missionDir = nil -- set at start 
persistence.saveDir = nil -- set at start 
persistence.name = "persistence" -- for cfxZones 
persistence.missionData = {} -- loaded from file 
persistence.requiredLibs = {
	"dcsCommon", 
	"cfxZones",  
}
--[[--
	Version History 
	2.0.0 - dml zones, OOP
			cleanup
	
	PROVIDES LOAD/SAVE ABILITY TO MODULES
	PROVIDES STANDALONE/HOSTED SERVER COMPATIBILITY
--]]--

-- in order to work, HOST MUST DESANITIZE lfs and io 

--
-- flags to save. can be added to by saveFlags attribute 
--
persistence.flagsToSave = {} -- simple table 
persistence.callbacks = {} -- cbblocks, dictionary by name

--
-- modules register here
--
function persistence.registerModule(name, callbacks)
	-- callbacks is a table with the following entries
	-- callbacks.persistData - method that returns a table
	-- note that name is also what the data is saved under
	-- and must be the one given when you retrieve it later
	persistence.callbacks[name] = callbacks
	if persistence.verbose then 
		trigger.action.outText("+++persistence: module <" .. name .. "> registered itself", 30)
	end
end

function persistence.registerFlagsToSave(flagNames, theZone)
	-- name can be single flag name or anything that 
	-- a zone definition has to offer, including local 
	-- flags. 
    -- flags can be passed like this: "a, 4-19, 99, kills, *lcl"
	-- if you pass a local flag, you must pass the zone 
	-- or "persisTEMP" will be used 
	
	if not theZone then theZone = cfxZones.createSimpleZone("persisTEMP") end 
	local newFlags = dcsCommon.flagArrayFromString(flagNames, persistence.verbose)
	
	-- mow process all new flags and add them to the list of flags 
	-- to save 
	for idx, flagName in pairs(newFlags) do 
		if dcsCommon.stringStartsWith(flagName, "*") then 
			flagName = theZone.name .. flagName 
		end
		table.insert(persistence.flagsToSave, flagName)
	end
end
--
-- registered modules call this to get their data 
--
function persistence.getSavedDataForModule(name)
	if not persistence.active then return nil end 
	if not persistence.hasData then return nil end 
	if not persistence.missionData then return end 
	
	return persistence.missionData[name] -- simply get the modules data block
end

--
-- Shared Data API 
--
function persistence.getSharedDataFor(name, item) -- not yet finalized
end

function persistence.putSharedDataFor(data, name, item) -- not yet finalized
end

--
-- helper meths
--

function persistence.hasFile(path) --check if file exists at path
-- will also return true for a directory, follow up with isDir 

    local attr = lfs.attributes(path) 
	if attr then
		return true, attr.mode
	end 
	
	if persistence.verbose then 
		trigger.action.outText("isFile: attributes not found for <" .. path .. ">", 30)
	end 
	
	return false, "<err>"
end

function persistence.isDir(path) -- check if path is a directory
	local success, mode = persistence.hasFile(path)
	if success then 
		success = (mode == "directory")
	end
	return success
end

--
-- Main save meths
--
function persistence.saveText(theString, fileName, shared, append)
	if not persistence.active then return false end 
	if not fileName then 
		trigger.action.outText("+++persistence: saveText without fileName", 30)
		return false 
	end 
	if not shared then shared = flase end 
	if not theString then theString = "" end 
	
	local path = persistence.missionDir .. fileName
	if shared then 
		-- we would now change the path
		trigger.action.outText("+++persistence: NYI: shared", 30)
		return 
	end

	local theFile = nil 
	
	if append then 
		theFile = io.open(path, "a")
	else 
		theFile = io.open(path, "w")
	end

	if not theFile then 
		trigger.action.outText("+++persistence: saveText - unable to open " .. path, 30)
		return false 
	end
	
	theFile:write(theString)
	
	theFile:close()
	
	return true 
end

function persistence.saveTable(theTable, fileName, shared, append)
	if not persistence.active then return false end 
	if not fileName then return false end
	if not theTable then return false end 
	if not shared then shared = false end 
	
	local theString = net.lua2json(theTable)
	
	if not theString then theString = "" end 
	
	local path = persistence.missionDir .. fileName
	if shared then 
		-- we would now change the path
		trigger.action.outText("+++persistence: NYI: shared", 30)
		return 
	end
	
	local theFile = nil 
	
	if append then 
		theFile = io.open(path, "a")
	else 
		theFile = io.open(path, "w")
	end

	if not theFile then 
		return false 
	end
	
	theFile:write(theString)
	
	theFile:close()
	
	return true 
end

function persistence.loadText(fileName) -- load file as text
	if not persistence.active then return nil end 
	if not fileName then return nil end
	
	local path = persistence.missionDir .. fileName
	local theFile = io.open(path, "r") 
	if not theFile then return nil end
	
	local t = theFile:read("*a")
	
	theFile:close()
	
	return t
end

function persistence.loadTable(fileName) -- load file as table 
	if not persistence.active then return nil end 
	if not fileName then return nil end

	local t = persistence.loadText(fileName)
	
	if not t then return nil end 
	
	local tab = net.json2lua(t)

	return tab
end

--
-- Data Load on Start
--
function persistence.initFlagsFromData(theFlags)
	-- assumes that theFlags is a dictionary containing 
	-- flag names 
	local flagLog = ""
	local flagCount = 0
	for flagName, value in pairs(theFlags) do 
		local val = tonumber(value) -- ensure number 
		if not val then val = 0 end 
		trigger.action.setUserFlag(flagName, val)
		if flagLog ~= "" then 
			flagLog = flagLog .. ", " .. flagName .. "=" .. val 
		else 
			flagLog = flagName .. "=" .. val 
		end
		flagCount = flagCount + 1
	end 
	if persistence.verbose and flagCount > 0 then 
		trigger.action.outText("+++persistence: loaded " .. flagCount .. " flags from storage:\n" .. flagLog .. "", 30)
	elseif persistence.verbose then
		trigger.action.outText("+++persistence: no flags loaded, commencing mission data load", 30)
	end	
	
end

function persistence.missionStartDataLoad()
	-- check one: see if we have mission data 
	local theData = persistence.loadTable(persistence.saveFileName)
	
	if not theData then 
		if persistence.verbose then 
			trigger.action.outText("+++persistence: no saved data, fresh start.", 30)
		end
		return 
	end -- there was no data to load
	
	if theData["freshMaker"] then 
		if persistence.verbose then 
			trigger.action.outText("+++persistence: detected fresh start.", 30)
		end
		return 
	end
	
	-- when we get here, we got at least some data. check it 
	if theData["versionID"] or persistence.versionID then 
		local vid = theData.versionID -- note: either may be nil!
		if vid ~= persistence.versionID then 
			-- we pretend load never happened.
			-- simply return
			if persistence.verbose then 
				local curvid = persistence.versionID
				if not curvid then curvid = "<NIL>" end 
				if not vid then vid = "<NIL>" end 
				trigger.action.outText("+++persistence: version mismatch\n(saved = <" .. vid .. "> vs current = <" .. curvid .. ">) - fresh start.", 30)
			end
			return 
		end
	end
	
	-- we have valid data, and modules, after signing up 
	-- can init from by data 
	persistence.missionData = theData
	persistence.hasData = true 
	trigger.action.setUserFlag("cfxPersistenceHasData", 1)
	
	-- init my flags from last save 
	local theFlags = theData["persistence.flagData"]
	if theFlags then 
		persistence.initFlagsFromData(theFlags)
	end
	
	-- we are done for now. modules check in 
	-- after persistence and load their own data 
	-- when they detect that there is data to load 

	trigger.action.outText("+++persistence: successfully read mission save data", 30)

end

--
-- MAIN DATA WRITE
--
function persistence.collectFlagData()
	local flagData = {}
	for idx, flagName in pairs (persistence.flagsToSave) do 
		local theNum = trigger.misc.getUserFlag(flagName)
		flagData[flagName] = theNum

	end
	return flagData
end

function persistence.saveMissionData()
	local myData = {}

	-- first, handle versionID and freshMaker
	if persistence.freshMaker then 
		myData["freshMaker"] = true 
	end
	
	if persistence.versionID then 
		myData["versionID"] = persistence.versionID 
	end
		
	-- now handle flags 
	myData["persistence.flagData"] = persistence.collectFlagData()
	
	-- now handle all other modules 
	for moduleName, callbacks in pairs(persistence.callbacks) do
		local moduleData = callbacks.persistData()
		if moduleData then 
			myData[moduleName] = moduleData
			if persistence.verbose then 
				trigger.action.outText("+++persistence: gathered data from <" .. moduleName .. ">", 30)
			end
		else 
			if persistence.verbose then 
				trigger.action.outText("+++persistence: NO DATA gathered data from <" .. moduleName .. ">, module returned NIL", 30)
			end
		end 
	end
	
	-- now save data to file 
	persistence.saveTable(myData, persistence.saveFileName)
end

--
-- UPDATE 
--
function persistence.doSaveMission()
	-- main save entry, also from API 
	if persistence.verbose then 
		trigger.action.outText("+++persistence: starting save", 30)
	end
	
	if persistence.active then 
		persistence.saveMissionData()
	else 
		if persistence.verbose then 
			trigger.action.outText("+++persistence: not actice. skipping save", 30)
		end
		return 
	end 
	
	if persistence.saveNotification then 
		trigger.action.outText("+++persistence: mission saved to\n" .. persistence.missionDir .. persistence.saveFileName, 30)
	end
end

function persistence.noteCleanRestart()
	persistence.freshMaker = true 
	persistence.doSaveMission()
	trigger.action.outText("\n\nYou can re-start the mission for a fresh start.\n\n",30)
	
end

function persistence.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(persistence.update, {}, timer.getTime() + 1/persistence.ups)
	
	-- check my trigger flag 
	if persistence.saveMission and cfxZones.testZoneFlag(persistence, persistence.saveMission, "change", "lastSaveMission") then 
		persistence.doSaveMission()
	end
	
	if persistence.cleanRestart and cfxZones.testZoneFlag(persistence, persistence.cleanRestart, "change", "lastCleanRestart") then 
		persistence.noteCleanRestart()
	end
	
	-- check my timer 
	if persistence.saveTime and persistence.saveTime < timer.getTime() then 
		persistence.doSaveMission()
		-- start next cycle 
		persistence.saveTime = persistence.saveInterval * 60 + timer.getTime()
	end
end
--
-- config & start 
--
function persistence.collectFlagsFromZone(theZone)
	local theFlags = theZone:getStringFromZoneProperty("saveFlags", "*dummy")
	persistence.registerFlagsToSave(theFlags, theZone)
end

function persistence.readConfigZone()
	if not _G["lfs"] then 
		trigger.action.outText("+++persistence: DCS currently not 'desanitized'. Persistence disabled", 30)
		return 
	end
	
	local theZone = cfxZones.getZoneByName("persistenceConfig") 
	local hasConfig = true
	if not theZone then 
		hasConfig = false 
		theZone = cfxZones.createSimpleZone("persistenceConfig")
	end 
	
	-- serverDir is the path from the server save directory, usually "Missions/".
    -- will be added to lfs.writedir() unless given a root attribute 
	if theZone:hasProperty("root") then 
		-- we split this to enable further processing down the 
		-- line if neccessary
		persistence.root = theZone:getStringFromZoneProperty("root", lfs.writedir()) -- safe default
		if not dcsCommon.stringEndsWith(persistence.root, "\\") then 
			persistence.root = persistence.root .. "\\"
		end
		if theZone.verbose then 
			trigger.action.outText("+++persistence: setting root to <" .. persistence.root .. ">", 30)
		end
	else 
		persistence.root = lfs.writedir() -- safe defaulting
		if theZone.verbose then 
			trigger.action.outText("+++persistence: defaulting root to <" .. persistence.root .. ">", 30)
		end
	end
	
	persistence.serverDir = theZone:getStringFromZoneProperty("serverDir", "Missions\\")

	if hasConfig then 
		if theZone:hasProperty("saveDir") then 
			persistence.saveDir = theZone:getStringFromZoneProperty("saveDir", "")
		else 
			-- local missname = net.dostring_in("gui", "return DCS.getMissionName()") .. " (data)"
			persistence.saveDir = dcsCommon.getMissionName() .. " (data)"
		end
	else 
		persistence.saveDir = "" -- save dir is to main mission 
		-- so that when no config is present (standalone debugger)
		-- this will not cause a separate save folder 
	end
	
	if persistence.saveDir == "" and persistence.verbose then 
		trigger.action.outText("*** WARNING: persistence is set to write to main mission directory!", 30)
	end
	
	if theZone:hasProperty("saveFileName") then 
		persistence.saveFileName = theZone:getStringFromZoneProperty("saveFileName", dcsCommon.getMissionName() .. " Data.txt")
	end
	
	if theZone:hasProperty("versionID") then
		persistence.versionID = theZone:getStringFromZoneProperty("versionID", "") -- to check for full restart 
	end 
	
	persistence.saveInterval = theZone:getNumberFromZoneProperty("saveInterval", -1) -- default to manual save
	if persistence.saveInterval > 0 then 
		persistence.saveTime = persistence.saveInterval * 60 + timer.getTime()
	end
	
	if theZone:hasProperty("cleanRestart?") then 
		persistence.cleanRestart = theZone:getStringFromZoneProperty("cleanRestart?", "*<none>")
		persistence.lastCleanRestart = theZone:getFlagValue(persistence.cleanRestart)
	end
	
	if theZone:hasProperty("saveMission?") then 
		persistence.saveMission = theZone:getStringFromZoneProperty("saveMission?", "*<none>")
		persistence.lastSaveMission = theZone:getFlagValue(persistence.saveMission)
	end
	
	persistence.verbose = theZone.verbose
	
	persistence.saveNotification = theZone:getBoolFromZoneProperty("saveNotification", true)
	
	if persistence.verbose then 
		trigger.action.outText("+++persistence: read config", 30)
	end 
	
end

function persistence.start()
	-- lib check 
	if not dcsCommon.libCheck then 
		trigger.action.outText("persistence requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("persistence", persistence.requiredLibs) then
		return false 
	end
		
	-- read config 
	persistence.saveFileName = dcsCommon.getMissionName() .. " Data.txt"
	persistence.readConfigZone()
	
	-- let's see it lfs and io are online 
	persistence.active = false 
	if (not _G["lfs"]) or (not lfs) then 
		if persistence.verbose then 
			trigger.action.outText("+++persistence requires 'lfs'", 30)
		end
		return false
	end
	if not _G["io"] then 
		if persistence.verbose then 
			trigger.action.outText("+++persistence requires 'io'", 30)
		end
		return false
	end
	
	local mainDir = persistence.root .. persistence.serverDir 
	if not dcsCommon.stringEndsWith(mainDir, "\\") then 
		mainDir = mainDir .. "\\"
	end

	-- lets see if we can access the server's mission directory and 
	-- save directory 	
	if persistence.isDir(mainDir) then 
		if persistence.verbose then 
			trigger.action.outText("persistence: main dir is <" .. mainDir .. ">", 30)
		end
	else 
		if persistence.verbose then 
			trigger.action.outText("+++persistence: Main directory <" .. mainDir .. "> not found or not a directory", 30)
		end 
		return false 
	end	
	persistence.mainDir = mainDir

	local missionDir = mainDir .. persistence.saveDir
	if not dcsCommon.stringEndsWith(missionDir, "\\") then 
		missionDir = missionDir .. "\\"
	end
	
	-- check if mission dir exists already 
	local success, mode = persistence.hasFile(missionDir)
	if success and mode == "directory" then 
		-- has been allocated, and is dir
		if persistence.verbose then 
			trigger.action.outText("+++persistence: saving mission data to <" .. missionDir .. ">", 30)
		end
	elseif success then 
		if persistence.verbose then 
			trigger.action.outText("+++persistence: <" .. missionDir .. "> is not a directory", 30)
		end
		return false 
	else 
		-- does not exist, try to allocate it
		if persistence.verbose then 
			trigger.action.outText("+++persistence: will now create <" .. missionDir .. ">", 30)
		end		
		local ok, mkErr = lfs.mkdir(missionDir)
		if not ok then 
			if persistence.verbose then 
				trigger.action.outText("+++persistence: unable to create <" .. missionDir .. ">: <" .. mkErr .. ">", 30)
			end
			return false
		end
		if persistence.verbose then 
			trigger.action.outText("+++persistence: created <" .. missionDir .. "> successfully, will save mission data here", 30)
		end 
	end
	
	-- missionDir is root + serverDir + saveDir 
	persistence.missionDir = missionDir
	
	persistence.active = true -- we can load and save data 
	trigger.action.setUserFlag("cfxPersistence", 1)
    persistence.hasData = false -- we do not have save data 
	
	-- from here on we can read and write files in the missionDir 	
	-- read persistence attributes from all zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("saveFlags")
	for k, aZone in pairs(attrZones) do 
		persistence.collectFlagsFromZone(aZone) -- process attributes
		-- we do not retain the zone, it's job is done
	end

	if persistence.verbose then 
		trigger.action.outText("+++persistence is active", 30)
	end	
	
	-- we now see if we can and need load data 
	persistence.missionStartDataLoad()
	
	-- and start updating 
	persistence.update()
	
	return persistence.active 
end

--
-- go!
--

if not persistence.start() then 
	if persistence.verbose then 
		trigger.action.outText("+++ persistence not available", 30)
	end
	-- we do NOT remove the methods so we don't crash 
end
