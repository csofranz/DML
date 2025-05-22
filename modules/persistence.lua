persistence = {}
persistence.version = "3.1.0"
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
	3.0.0 - shared data 
	3.0.1 - shared data validations/fallback  
	        API cleanup 
			shared text data "flase" typo corrected (no impact)
			code cleanup 
	3.0.2 - more logging 
	        vardump to log possible 
	3.1.0 - validFor attribute -- timed gc 
		  - persistence deallocs data after validFor seconds 
			
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
function persistence.count(theTable)
	if not theTable then return 0 end 
	local c = 0
	for idx, val in pairs(theTable) do 
		c = c + 1
	end
	return c
end 

function persistence.filter(name) -- debugging 
	--if true then return false end  
	--if name == "WHpersistence" then return true end 
	--if name == "unitPersistence" then return true end 
	--if name == "cfxPlayerScore" then return true end 
	--if name == "cfxSSBClient" then return true end 	
	--if name == "cfxSpawnZones" then return true end
	--if name == "cfxHeloTroops" then return true end
	--if name == "rndFlags" then return true end
	--if name == "cfxOwnedZones" then return true end
	--if name == "cloneZones" then return true end --*
	--if name == "cfxObjectDestructDetector" then return true end
	return false 
end 

function persistence.getSavedDataForModule(name, sharedDataName)
--	if persistence.verbose then 
--		trigger.action.outText("+++persistence: enter load for <" .. name .. ">", 30)
--	end 
	if not persistence.active then return nil end 
	if not persistence.hasData then return nil end 
	if not persistence.missionData then return nil end 
	if not sharedDataName then sharedDataName = nil end 
	
	if persistence.filter(name) then 
		trigger.action.outText("FILTERED persistence for <" .. name .. ">", 30)
		return nil 
	end 
	if sharedDataName then 
		-- we read from shared data and only revert to 
		-- common if we find nothing
		local shFile =  persistence.sharedDir .. sharedDataName .. ".txt"
		if persistence.verbose then 
			trigger.action.outText("persistence: will try to load shared data from <" .. shFile .. ">", 30)
		end 
		local theData = persistence.loadTable(shFile, true)
		if theData then 
			if theData[name] then 
				trigger.action.outText("+++persistence: returning SHARED for <" .. name .. ">", 30)
				return theData[name]
			end 
			if persistence.verbose then 
				trigger.action.outText("persistence: shared data file <" .. sharedDataName .. "> exists but currently holds no data for <" .. name .. ">, reverting to main", 30)
			end 
		else 
			if persistence.verbose then 
				trigger.action.outText("persistence: shared data file <" .. sharedDataName
				.. "> does not yet exist, reverting to main", 30)
			end 
		end
	end
	if persistence.verbose then 
		trigger.action.outText("+++persistence: returning data (" .. persistence.count(persistence.missionData[name]) .. " records) for <" .. name .. ">", 30)
	end
	return persistence.missionData[name] -- simply get the modules data block
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
	if not shared then shared = false end 
	if not theString then theString = "" end 
	
	local path = persistence.missionDir .. fileName
	if shared then 
		-- we would now change the path
		trigger.action.outText("+++persistence: NYI: shared", 30)
		return false 
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
	net.log("persistence: enter saveTable")

	if not persistence.active then return false end 
	if not fileName then return false end
	if not theTable then return false end 
	if not shared then shared = false end 

	net.log("persistence: before json conversion")
	local theString = net.lua2json(theTable) -- WARNING! does not handle arrays with [0]! 
	net.log("persistence: json conversion complete")

	if not theString then theString = "" end 
	local path = persistence.missionDir .. fileName
	if shared then 
		-- we change the path to shared 
		path = persistence.sharedDir .. fileName .. ".txt" 
	end
	
	net.log("persistence: will now open file at path <" .. path .. ">")
	local theFile = nil 
	if append then 
		theFile = io.open(path, "a")
	else 
		theFile = io.open(path, "w")
	end
	if not theFile then 
		return false 
	end
	net.log("persistence: will now write file")
	theFile:write(theString)
	net.log("persistence: will now close file")
	theFile:close()
	net.log("persistence: will now exit saveTable")
	return true 
end

function persistence.loadText(fileName, hasPath) -- load file as text
	if not persistence.active then return nil end 
	if not fileName then return nil end
	local path 
	if hasPath then 
		path = fileName 
	else 
		path = persistence.missionDir .. fileName
	end 
	if persistence.verbose then 
		trigger.action.outText("persistence: will load text file <" .. path .. ">", 30)
	end 
	local theFile = io.open(path, "r") 
	if not theFile then return nil end
	local t = theFile:read("*a")
	theFile:close()
	return t
end

function persistence.loadTable(fileName, hasPath) -- load file as table 
	if not persistence.active then return nil end 
	if not fileName then return nil end
	if not hasPath then hasPath = false end 
	local t = persistence.loadText(fileName, hasPath)
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

function persistence.freshStart()
	persistence.missionData = {}
	persistence.hasData = true 
	trigger.action.setUserFlag("cfxPersistenceHasData", 1)
end

function persistence.missionStartDataLoad()
	-- check one: see if we have mission data 
	local theData = persistence.loadTable(persistence.saveFileName)
	
	if not theData then 
		if persistence.verbose then 
			trigger.action.outText("+++persistence: no saved data, fresh start.", 30)
		end
		persistence.freshStart()
		return 
	end -- there was no data to load
	
	if theData["freshMaker"] then 
		if persistence.verbose then 
			trigger.action.outText("+++persistence: detected fresh start.", 30)
		end
		persistence.freshStart()
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
-- logging data
--
function persistence.logTable(key, value, prefix, inrecursion)
	local comma = ""
	if inrecursion then 
		if tonumber(key) then key = '[' .. key .. ']' else key = '["' .. key .. '"]' end
		comma = ","
	end 
	if not value then value = false end -- not NIL!
	if not prefix then prefix = "" else prefix = "\t" .. prefix end
	if type(value) == "table" then -- recursively write a table
		net.log(prefix .. key .. " = \n" .. prefix .. "{\n")
		for k,v in pairs (value) do -- iterate all kvp
			persistence.logTable(k, v, prefix, true)
		end
		net.log(prefix .. "}" .. comma .. " -- end of " .. key .. "\n")
	elseif type(value) == "boolean" then 
		local b = "false"
		if value then b = "true" end
		net.log(prefix .. key .. " = " .. b .. comma .. "\n")
	elseif type(value) == "string" then -- quoted string, WITH proccing
		value = string.gsub(value, "\\", "\\\\") -- escape "\" to "\\", others ignored, possibly conflict with \n
		value = string.gsub(value, string.char(10), "\\" .. string.char(10)) -- 0A --> "\"0A
		net.log(prefix .. key .. ' = "' .. value .. '"' .. comma .. "\n")
	else -- simple var, show contents, ends recursion
		net.log(prefix .. key .. " = " .. value .. comma .. "\n")
	end
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

function persistence.saveSharedData()
	trigger.action.outText("WARNING: Persistence's saveSharedData invoked!", 30)
end

function persistence.saveMissionData()
	local myData = {}
	local allSharedData = {} -- organized by 'shared' name returned  
	
	-- first, handle versionID and freshMaker
	if persistence.freshMaker then 
		myData["freshMaker"] = true 
	end
	
	if persistence.versionID then 
		myData["versionID"] = persistence.versionID 
	end
		
	-- now handle flags 
	myData["persistence.flagData"] = persistence.collectFlagData()
	net.log("persistence: --- START of module-individual save")
	-- now handle all other modules 
	for moduleName, callbacks in pairs(persistence.callbacks) do
		net.log("persistence: invoking save for module " .. moduleName)
		local moduleData, sharedName = callbacks.persistData()
		if moduleData then 
			if sharedName then -- save into shared bucket
				-- allshared[specificShared[moduleName]]
				local specificShared = allSharedData[sharedName]
				if not specificShared then specificShared = {} end
				specificShared[moduleName] = moduleData
				allSharedData[sharedName] = specificShared -- write back 
			end -- !NO ELSE! WE ALSO STORE IN MAIN DATA FOR REDUNDANCY
			myData[moduleName] = moduleData
			if persistence.verbose then 
				trigger.action.outText("+++persistence: gathered data from <" .. moduleName .. ">", 30)
			end
			net.log("persistence: got data for module: " .. moduleName)
			--persistence.logTable(moduleName, moduleData)
			--net.log("persistence: performing json conversion test for myData")
			--local theString = net.lua2json(myData)
			--net.log("persistence: json conversion success!")
		else 
			if persistence.verbose then 
				trigger.action.outText("+++persistence: NO DATA gathered data from <" .. moduleName .. ">, module returned NIL", 30)
			end
		end 
		net.log("persistence: completed save for module " .. moduleName)
	end
	net.log("persistence: --- END of module-individual save")
	
	-- now save data to file 
	net.log("persistence: will now invoke main saveTable")
	persistence.saveTable(myData, persistence.saveFileName)
	net.log("persistence: returned from main save table")

	-- now save all shared name data as separate files 
	net.log("persistence: will  now iterate shares")
	for shareName, data in pairs (allSharedData) do 
		net.log("persistence: share " .. shareName)

		-- save into shared folder, by name that was returned from callback
		-- read what was saved, and replace changed key/values from data
		local shFile =  persistence.sharedDir .. shareName .. ".txt"
		local theData = persistence.loadTable(shFile, true) -- hasPath
		if theData then 
			for k, v in pairs(data) do 
				theData[k] = v
			end 
		else 
			theData = data 
		end
		
		persistence.saveTable(theData, shareName, true) -- true --> shared
	end 
	net.log("persistence: done iterating shares")

end

--
-- UPDATE 
--
function persistence.doSaveMission()
	net.log("persistence: start doSaveMission")
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
	net.log("persistence: DONE doSaveMission")
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
	persistence.sharedDir = "DML-Shared-Data\\" -- hard-wired!

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
	
	persistence.validFor = theZone:getNumberFromZoneProperty("validFor", 5) -- GC after ... seconds 
	
	if persistence.verbose then 
		trigger.action.outText("+++persistence: read config", 30)
	end 
	
end

function persistence.GC()
	-- destroy loaded mission data
	if persistence.missionData then 
		persistence.missionData = nil 
		if persistence.verbose then 
			trigger.action.outText("+++persistence: relinquished loaded data.", 30)
		end 
	end
	persistence.hasData = false 
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
	
	local mainDir = persistence.root .. persistence.serverDir -- usually DCS/Missions	
	if not dcsCommon.stringEndsWith(mainDir, "\\") then 
		mainDir = mainDir .. "\\"
	end
	local sharedDir = mainDir .. persistence.sharedDir -- ends on \\, hardwired 
	persistence.sharedDir = sharedDir	

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

	-- make sure that SHARED dir exists, create if not 
	local success, mode = persistence.hasFile(sharedDir)
	if success and mode == "directory" then 
		-- has been allocated, and is dir
		if persistence.verbose then 
			trigger.action.outText("+++persistence: saving SHARED data to <" .. sharedDir .. ">", 30)
		end
	elseif success then 
		if persistence.verbose then 
			trigger.action.outText("+++persistence: <" .. sharedDir .. "> is not a directory", 30)
		end
		return false 
	else 
		-- does not exist, try to allocate it
		if persistence.verbose then 
			trigger.action.outText("+++persistence: will now create <" .. sharedDir .. ">", 30)
		end		
		local ok, mkErr = lfs.mkdir(sharedDir)
		if not ok then 
			if persistence.verbose then 
				trigger.action.outText("+++persistence: unable to create <" .. sharedDir .. ">: <" .. mkErr .. ">", 30)
			end
			return false
		end
		if persistence.verbose then 
			trigger.action.outText("+++persistence: created <" .. sharedDir .. "> successfully, will save SHARED data here", 30)
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
--	if persistence.verbose then trigger.action.outText("before data load: Persistence.hasData = " .. dcsCommon.bool2Text(persistence.hasData),30 ) end	
	persistence.missionStartDataLoad()
--	if persistence.verbose then trigger.action.outText("after data load: Persistence.hasData = " .. dcsCommon.bool2Text(persistence.hasData),30 ) end
	timer.scheduleFunction(persistence.GC, nil, timer.getTime() + persistence.validFor) -- destroy loaded data after this interval 
	-- and start updating 
--	if persistence.verbose then trigger.action.outText("before first update: Persistence.hasData = " .. dcsCommon.bool2Text(persistence.hasData),30 ) end 
	persistence.update()
--	if persistence.verbose then trigger.action.outText("after first update: Persistence.hasData = " .. dcsCommon.bool2Text(persistence.hasData),30 ) end
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
