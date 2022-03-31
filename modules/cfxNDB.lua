cfxNDB = {}
cfxNDB.version = "1.2.0"

--[[--
	cfxNDB:
	Copyright (c) 2021, 2022 by Christian Franz and cf/x AG
	
	Zone enhancement that simulates an NDB for a zone.
	If zone is linked, the NDB's location is updated 
	regularly.
	Currently, the individual refresh is only respected 
	correctly if it's longer than the module's refresh and 
	an even multiple of module's refresh, else it will be
	refreshed at the next module update cycle 
	
	VERSION HISTORY
	1.0.0 - initial version 
	1.1.0 - on? flag 
	      - off? flag 
		  - ups at 1, decoupled update from refresh 
		  - paused flag, paused handling 
		  - startNDB() can accept string 
		  - stopNDB() can accept string
	1.2.0 - DML full integration 
		  
--]]--

cfxNDB.verbose = false 
cfxNDB.ups = 1 -- once every 1 second 
cfxNDB.requiredLibs = {
	"dcsCommon", 
	"cfxZones",  
}
cfxNDB.refresh = 10 -- for moving ndb: interval in secs between refresh  
cfxNDB.power = 100 

cfxNDB.ndbs = {} -- all ndbs 

--
-- NDB zone - *** EXTENDS ZONES ***
--

function cfxNDB.startNDB(theNDB)
	if type(theNDB) == "string" then 
		theNDB = cfxZones.getZoneByName(theNDB) 
	end
	
	if not theNDB.freq then 
		-- this zone is not an NDB. Exit 
		if cfxNDB.verbose then 
			trigger.action.outText("+++ndb: start() -- " .. theNDB.name .. " is not a cfxNDB.", 30) 
		end
		return 
	end
	
	theNDB.ndbRefreshTime = timer.getTime() + theNDB.ndbRefresh -- only used in linkedUnit, but set up anyway
	-- generate new ID 
	theNDB.ndbID = dcsCommon.uuid("ndb")
	local fileName = "l10n/DEFAULT/" .. theNDB.ndbSound -- need to prepend the resource string
	local modulation = 0
	if theNDB.fm then modulation = 1 end 
	
	local loc = cfxZones.getPoint(theNDB)
	trigger.action.radioTransmission(fileName, loc, modulation, true, theNDB.freq, theNDB.power, theNDB.ndbID)
	
	if cfxNDB.verbose then 
		local dsc = ""
		if theNDB.linkedUnit then 
			dsc = " (linked to ".. theNDB.linkedUnit:getName() .. "!, r=" .. theNDB.ndbRefresh .. ") "
		end 
		trigger.action.outText("+++ndb: started " .. theNDB.name .. dsc .. " at " .. theNDB.freq/1000000 .. "mod " .. modulation .. " with w=" .. theNDB.power .. " s=<" .. fileName .. ">", 30)
	end
	theNDB.paused = false 
	
	if cfxNDB.verbose then 
		trigger.action.outText("+++ndb: " .. theNDB.name .. " started", 30) 
	end
end

function cfxNDB.stopNDB(theNDB)
	if type(theNDB) == "string" then 
		theNDB = cfxZones.getZoneByName(theNDB) 
	end
	
	if not theNDB.freq then 
		-- this zone is not an NDB. Exit 
		if cfxNDB.verbose then 
			trigger.action.outText("+++ndb: stop() -- " .. theNDB.name .. " is not a cfxNDB.", 30) 
		end
		return 
	end
	
	trigger.action.stopRadioTransmission(theNDB.ndbID)
	theNDB.paused = true 
	if cfxNDB.verbose then 
		trigger.action.outText("+++ndb: " .. theNDB.name .. " stopped", 30) 
	end
end

function cfxNDB.createNDBWithZone(theZone)
	theZone.freq = cfxZones.getNumberFromZoneProperty(theZone, "NDB", 124) -- in MHz
	-- convert MHz to Hz
	theZone.freq = theZone.freq * 1000000 -- Hz
	theZone.fm = cfxZones.getBoolFromZoneProperty(theZone, "fm", false) 
	theZone.ndbSound = cfxZones.getStringFromZoneProperty(theZone, "soundFile", "<none>")
	theZone.power = cfxZones.getNumberFromZoneProperty(theZone, "watts", cfxNDB.power)
	theZone.loop = true -- always. NDB always loops
	-- UNSUPPORTED refresh. Although read individually, it only works 
	-- when LARGER than module's refresh.
	theZone.ndbRefresh = cfxZones.getNumberFromZoneProperty(theZone, "ndbRefresh", cfxNDB.refresh) -- only used if linked
	theZone.ndbRefreshTime = timer.getTime() + theZone.ndbRefresh -- only used with linkedUnit, but set up nonetheless
	
	-- paused 
	theZone.paused = cfxZones.getBoolFromZoneProperty(theZone, "paused", false) 
	
	-- watchflags 
	theZone.ndbTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "ndbTriggerMethod") then 
		theZone.ndbTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "ndbTriggerMethod", "change")
	end 
	
	-- on/offf query flags 
	if cfxZones.hasProperty(theZone, "on?") then 
		theZone.onFlag = cfxZones.getStringFromZoneProperty(theZone, "on?", "none")
	end
	
	if theZone.onFlag then 
		theZone.onFlagVal = cfxZones.getFlagValue(theZone.onFlag, theZone) -- trigger.misc.getUserFlag(theZone.onFlag) -- save last value
	end
	
	if cfxZones.hasProperty(theZone, "off?") then 
		theZone.offFlag = cfxZones.getStringFromZoneProperty(theZone, "off?", "none")
	end
	
	if theZone.offFlag then 
		theZone.offFlagVal = cfxZones.getFlagValue(theZone.offFlag, theZone) --trigger.misc.getUserFlag(theZone.offFlag) -- save last value
	end
	
	-- start it 
	if not theZone.paused then 
		cfxNDB.startNDB(theZone)
	end
	
	-- add it to my watchlist 
	table.insert(cfxNDB.ndbs, theZone)
end

--
-- update 
--
function cfxNDB.update()
	timer.scheduleFunction(cfxNDB.update, {}, timer.getTime() + 1/cfxNDB.ups)
	local now = timer.getTime()
	-- walk through all NDB and see if they need a refresh
	for idx, theNDB in pairs (cfxNDB.ndbs) do 
		-- see if this ndb is linked, meaning it's potentially 
		-- moving with the linked unit 
		if theNDB.linkedUnit then 
			-- yupp, need to update
			if (not theNDB.paused) and 
			(now > theNDB.ndbRefreshTime) then 
				cfxNDB.stopNDB(theNDB) -- also pauses
				cfxNDB.startNDB(theNDB) -- turns off pause 
			end
		end
		
		-- now check triggers to start/stop 
		if cfxZones.testZoneFlag(theNDB, theNDB.onFlag, theNDB.ndbTriggerMethod, "onFlagVal") then
			-- yupp, trigger start 
			cfxNDB.startNDB(theNDB)
		end
		
		
		if cfxZones.testZoneFlag(theNDB, theNDB.offFlag, theNDB.ndbTriggerMethod, "offFlagVal") then
			-- yupp, trigger start 
			cfxNDB.stopNDB(theNDB)
		end 
		
	end
end

--
-- start up
--
function cfxNDB.readConfig()
	local theZone = cfxZones.getZoneByName("ndbConfig") 
	if not theZone then 
		if cfxNDB.verbose then 
			trigger.action.outText("***ndb: NO config zone!", 30) 
		end
		return 
	end 
	
	cfxNDB.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false) 	
	cfxNDB.ndbRefresh = cfxZones.getNumberFromZoneProperty(theZone, "ndbRefresh", 10)
	
	if cfxNDB.verbose then 
		trigger.action.outText("***ndb: read config", 30) 
	end
end

function cfxNDB.start()
	-- lib check 
	if not dcsCommon.libCheck("cfx NDB", 
		cfxNDB.requiredLibs) then
		return false 
	end
	
	-- config 
	cfxNDB.readConfig()
	
	-- read zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("NDB")
	for idx, aZone in pairs(attrZones) do 
		cfxNDB.createNDBWithZone(aZone)
	end
	
	-- start update 
	cfxNDB.update()
	
	return true 
end

if not cfxNDB.start() then 
	trigger.action.outText("cf/x NDB aborted: missing libraries", 30)
	cfxNDB = nil 
end
