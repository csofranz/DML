cfxNDB = {}
cfxNDB.version = "1.3.1"

--[[--
	cfxNDB:
	Copyright (c) 2021 - 2025 by Christian Franz and cf/x AG
	
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
	1.2.1 - height correction for NDB on creation 
	      - update only when moving and delta > maxDelta 
		  - zone-local verbosity support
		  - better config defaulting 
	1.3.0 - dmlZones 
	1.3.1 - better guarding non-started and paused NDB against repeated pauses
	      - reworked ndb reading for on? and off? 
		  - added code to preven multi-start of an NDB
		  - code cleanup 
		  
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
	if theNDB.verbose then 
		trigger.action.outText("+++ndb: invoking START for NDB <" .. theNDB.name .. ">.", 30)
	end
	
	if not theNDB.paused then -- NDB is already running, do not start another one!
		if theNDB.verbose or cfxNDB.verbose then 
			trigger.action.outText("+++ndb: attempt to start a running ndb <" .. theNDB.name .. ">. aborted", 30)
		end 		
		return
	end 	
	
	theNDB.ndbRefreshTime = timer.getTime() + theNDB.ndbRefresh -- only used in linkedUnit, but set up anyway
	-- generate new ID 
	theNDB.ndbID = dcsCommon.uuid("ndb")
	local fileName = "l10n/DEFAULT/" .. theNDB.ndbSound -- need to prepend the resource string
	local modulation = 0
	if theNDB.fm then modulation = 1 end 
	
	local loc = cfxZones.getPoint(theNDB) -- y === 0
	loc.y = land.getHeight({x = loc.x, y = loc.z}) -- get y from land 
	trigger.action.radioTransmission(fileName, loc, modulation, true, theNDB.freq, theNDB.power, theNDB.ndbID)
	theNDB.lastLoc = loc -- save for delta comparison
	
	if cfxNDB.verbose or theNDB.verbose then 
		local dsc = ""
		if theNDB.linkedUnit then 
			dsc = " (linked to ".. theNDB.linkedUnit:getName() .. "!, r=" .. theNDB.ndbRefresh .. ") "
		end 
		trigger.action.outText("+++ndb: started <" .. theNDB.name ..">" .. dsc .. " at " .. theNDB.freq/1000000 .. "mod " .. modulation .. " with w=" .. theNDB.power .. " s=<" .. fileName .. ">", 30)
	end
	theNDB.paused = false 
	if cfxNDB.verbose or theNDB.verbose then 
		trigger.action.outText("+++ndb: " .. theNDB.name .. " started", 30) 
	end
end

function cfxNDB.stopNDB(theNDB)	
	if theNDB.verbose then 
		trigger.action.outText("+++ndb: invoking stopNDB for " .. theNDB.name .. ".", 30)
	end
	if theNDB.paused then return end -- already paused, nothing to do 
	if not theNDB.ndbID then 
		if cfxNDB.verbose or theNDB.verbose then 
			trigger.action.outText("+++ndb: stop() -- " .. theNDB.name .. " has no ndbID, perhaps not properly started.", 30) 
		end
		return 
	end 
	
	trigger.action.stopRadioTransmission(theNDB.ndbID)
	theNDB.paused = true 
	if cfxNDB.verbose or theNDB.verbose then 
		trigger.action.outText("+++ndb: " .. theNDB.name .. " stopped", 30) 
	end
end

function cfxNDB.createNDBWithZone(theZone)
	theZone.freq = theZone:getNumberFromZoneProperty("NDB", 124) -- in MHz
	-- convert MHz to Hz
	theZone.freq = theZone.freq * 1000000 -- Hz
	theZone.fm = theZone:getBoolFromZoneProperty("fm", false) 
	theZone.ndbSound = theZone:getStringFromZoneProperty("soundFile", "<none>")
	theZone.power = theZone:getNumberFromZoneProperty("watts", cfxNDB.power)
	theZone.loop = true -- always. NDB always loops
	-- UNSUPPORTED refresh. Although read individually, it only works 
	-- when LARGER than module's refresh.
	theZone.ndbRefresh = theZone:getNumberFromZoneProperty("ndbRefresh", cfxNDB.refresh) -- only used if linked
	theZone.ndbRefreshTime = timer.getTime() + theZone.ndbRefresh -- only used with linkedUnit, but set up nonetheless
	
	-- paused 
	theZone.paused = theZone:getBoolFromZoneProperty("paused", false) 
	
	-- watchflags 
	theZone.ndbTriggerMethod = theZone:getStringFromZoneProperty( "triggerMethod", "change")
	if theZone:hasProperty("ndbTriggerMethod") then 
		theZone.ndbTriggerMethod = theZone:getStringFromZoneProperty("ndbTriggerMethod", "change")
	end 
	
	theZone.onFlag = theZone:getStringFromZoneProperty("on?", "cfxnone")
	theZone.onFlagVal = theZone:getFlagValue(theZone.onFlag) -- save last value
	theZone.offFlag = theZone:getStringFromZoneProperty("off?", "cfxnone")
	theZone.offFlagVal = theZone:getFlagValue(theZone.offFlag) -- save last value
		
	-- start it 
	if not theZone.paused then 
		if theZone.verbose then trigger.action.outText("+++nbd: initial invoke start unpaused", 30) end
		theZone.paused = true -- force a (mocked) pause, so we will start NDB 
		cfxNDB.startNDB(theZone)
		if theZone.verbose then trigger.action.outText("+++nbd: initial return unpaused", 30) end
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
		-- see if this ndb is linked, meaning it's potentially moving with the linked unit 
		if theNDB.linkedUnit then 
			-- yupp, need to update
			if (not theNDB.paused) and 
			   (now > theNDB.ndbRefreshTime) then 
				-- optimization: check that it moved far enough to merit update.
				if not theNDB.lastLoc then 
					cfxNDB.startNDB(theNDB) -- never was started 
				else 
					local loc = theNDB:getPoint()
					loc.y = land.getHeight({x = loc.x, y = loc.z}) -- get y from land
					local delta = dcsCommon.dist(loc, theNDB.lastLoc)
					if delta > cfxNDB.maxDist then 
						cfxNDB.stopNDB(theNDB) 
						cfxNDB.startNDB(theNDB) 
					end
				end
			end
		end
		
		-- now check triggers to start/stop 
		if theNDB:testZoneFlag(theNDB.onFlag, theNDB.ndbTriggerMethod, "onFlagVal") then
			-- yupp, trigger start 
			cfxNDB.startNDB(theNDB)
		end
		
		if theNDB:testZoneFlag(theNDB.offFlag, theNDB.ndbTriggerMethod, "offFlagVal") then
			-- yupp, trigger stop 
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
		theZone = cfxZones.createSimpleZone("ndbConfig")
	end 
	
	cfxNDB.verbose = theZone.verbose 
	cfxNDB.ndbRefresh = theZone:getNumberFromZoneProperty("ndbRefresh", 10)
	
	cfxNDB.maxDist = theZone:getNumberFromZoneProperty("maxDist", 50) -- max 50m error for movement
	
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
	
	trigger.action.outText("cf/x NDB version " .. cfxNDB.version .. " started", 30)
	return true 
end

if not cfxNDB.start() then 
	trigger.action.outText("cf/x NDB aborted: missing libraries", 30)
	cfxNDB = nil 
end
