cfxObjectDestructDetector = {}
cfxObjectDestructDetector.version = "1.3.0" 
cfxObjectDestructDetector.verbose = false 
cfxObjectDestructDetector.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
   VERSION HISTORY 
   1.0.0 initial version, based on parashoo, arty zones  
   1.0.1 fixed bug: trigger.MISC.getUserFlag()
   1.1.0 added support for method, f! and destroyed! 
   1.2.0 DML / Watchflag support 
   1.3.0 Persistence support 
   
   
   Detect when an object with OBJECT ID as assigned in ME dies 
   *** EXTENDS ZONES 
   
--]]--

cfxObjectDestructDetector.objectZones = {}

--
-- C A L L B A C K S 
-- 
cfxObjectDestructDetector.callbacks = {}
function cfxObjectDestructDetector.addCallback(theCallback)
	table.insert(cfxObjectDestructDetector.callbacks, theCallback)
end

function cfxObjectDestructDetector.invokeCallbacksFor(zone)
	for idx, theCB in pairs (cfxObjectDestructDetector.callbacks) do 
		theCB(zone, zone.ID, zone.name)
	end
end

--
-- zone handling
--
function cfxObjectDestructDetector.addObjectDetectZone(aZone)
	-- add landHeight to this zone 
	table.insert(cfxObjectDestructDetector.objectZones, aZone)
end

function cfxObjectDestructDetector.getObjectDetectZoneByName(aName)
	for idx, aZone in pairs(cfxObjectDestructDetector.objectZones) do 
		if aZone.name == aName then return aZone end 
	end
	-- add landHeight to this zone 
	return nil
end

--
-- processing of zones 
--
function cfxObjectDestructDetector.processObjectDestructZone(aZone)
	aZone.name = cfxZones.getStringFromZoneProperty(aZone, "NAME", aZone.name)
--	aZone.coalition = cfxZones.getCoalitionFromZoneProperty(aZone, "coalition", 0)
	aZone.ID = cfxZones.getNumberFromZoneProperty(aZone, "OBJECT ID", 1)  -- THIS!
	-- persistence interface
	aZone.isDestroyed = false 
	
	--[[-- old code, to be decom'd --]]--
	if cfxZones.hasProperty(aZone, "setFlag") then 
		aZone.setFlag = cfxZones.getStringFromZoneProperty(aZone, "setFlag", "999")
	end
	if cfxZones.hasProperty(aZone, "f=1") then 
		aZone.setFlag = cfxZones.getStringFromZoneProperty(aZone, "f=1", "999")
	end
	if cfxZones.hasProperty(aZone, "clearFlag") then 
		aZone.clearFlag = cfxZones.getStringFromZoneProperty(aZone, "clearFlag", "999")
	end
	if cfxZones.hasProperty(aZone, "f=0") then 
		aZone.clearFlag = cfxZones.getStringFromZoneProperty(aZone, "f=0", "999")
	end
	if cfxZones.hasProperty(aZone, "increaseFlag") then 
		aZone.increaseFlag = cfxZones.getStringFromZoneProperty(aZone, "increaseFlag", "999")
	end
	if cfxZones.hasProperty(aZone, "f+1") then 
		aZone.increaseFlag = cfxZones.getStringFromZoneProperty(aZone, "f+1", "999")
	end
	if cfxZones.hasProperty(aZone, "decreaseFlag") then 
		aZone.decreaseFlag = cfxZones.getStringFromZoneProperty(aZone, "decreaseFlag", "999")
	end
	if cfxZones.hasProperty(aZone, "f-1") then 
		aZone.decreaseFlag = cfxZones.getStringFromZoneProperty(aZone, "f-1", "999")
	end
	
	-- DML method support
	aZone.oddMethod = cfxZones.getStringFromZoneProperty(aZone, "method", "inc")
	if cfxZones.hasProperty(aZone, "oddMethod") then 
		aZone.oddMethod = cfxZones.getStringFromZoneProperty(aZone, "oddMethod", "inc")
	end
	
	
	-- we now always have that property
	aZone.outDestroyFlag = cfxZones.getStringFromZoneProperty(aZone, "f!", "*none")

	if cfxZones.hasProperty(aZone, "destroyed!") then 
		aZone.outDestroyFlag = cfxZones.getStringFromZoneProperty(aZone, "destroyed!", "*none")
	end

	if cfxZones.hasProperty(aZone, "objectDestroyed!") then 
		aZone.outDestroyFlag = cfxZones.getStringFromZoneProperty(aZone, "objectDestroyed!", "*none")
	end
end
--
-- MAIN DETECTOR
--
-- invoke callbacks when an object was destroyed
function cfxObjectDestructDetector:onEvent(event)
	if event.id == world.event.S_EVENT_DEAD then
		if not event.initiator then return end 
		local id = event.initiator:getName()
		if not id then return end 
		
		for idx, aZone in pairs(cfxObjectDestructDetector.objectZones) do 
			if (not aZone.isDestroyed) and aZone.ID == id then 
				-- flag manipulation 
				-- OLD FLAG SUPPORT, SOON TO BE REMOVED
				if aZone.setFlag then 
					trigger.action.setUserFlag(aZone.setFlag, 1)
				end
				if aZone.clearFlag then 
					trigger.action.setUserFlag(aZone.clearFlag, 0)
				end
				if aZone.increaseFlag then 
					local val = trigger.misc.getUserFlag(aZone.increaseFlag) + 1
					trigger.action.setUserFlag(aZone.increaseFlag, val)
				end
				if aZone.decreaseFlag then 
					local val = trigger.misc.getUserFlag(aZone.decreaseFlag) - 1
					trigger.action.setUserFlag(aZone.decreaseFlag, val)
				end
				-- END OF OLD CODE, TO BE REMOVED 
				
				-- support for banging 
				if aZone.outDestroyFlag then 
					cfxZones.pollFlag(aZone.outDestroyFlag, aZone.oddMethod, aZone)
				end
				
				-- invoke callbacks 
				cfxObjectDestructDetector.invokeCallbacksFor(aZone)
				if aZone.verbose or cfxObjectDestructDetector.verbose then 
					trigger.action.outText("OBJECT KILL: " .. id, 30)
				end

				-- we could now remove the object from the list 
				-- for better performance since it cant
				-- die twice 
				
				-- save state for persistence
				aZone.isDestroyed = true 
				
				return 
			end
		end
		
    end
	
end

--
-- persistence: save and load data 
--
function cfxObjectDestructDetector.saveData() -- invoked by persistence
	local theData = {}
	local zoneInfo = {}
	for idx, aZone in pairs(cfxObjectDestructDetector.objectZones) do
		-- save all pertinent info. in our case, it's just 
		-- the isDestroyed and flag info info
		info = {}
		info.isDestroyed = aZone.isDestroyed
		info.outDestroyVal = cfxZones.getFlagValue(aZone.outDestroyFlag, aZone)
		zoneInfo[aZone.name] = info
	end
	-- expasion proof: assign as own field
	theData.zoneInfo = zoneInfo
	return theData
end

function cfxObjectDestructDetector.loadMission()
	if cfxObjectDestructDetector.verbose then 
		trigger.action.outText("+++oDDet: persistence - loading data", 30)
	end
	
	local theData = persistence.getSavedDataForModule("cfxObjectDestructDetector")
	if not theData then 
		return 
	end
	
	-- iterate the data, and fail graciously if 
	-- we can't find a zone. it's probably beed edited out
	local zoneInfo = theData.zoneInfo
	if not zoneInfo then return end 
	if cfxObjectDestructDetector.verbose then 
		trigger.action.outText("+++oDDet: persistence - processing data", 30)
	end	
	
	for zName, info in pairs (zoneInfo) do 
		local theZone = cfxObjectDestructDetector.getObjectDetectZoneByName(zName)
		if theZone then 
			theZone.isDestroyed = info.isDestroyed
			cfxZones.setFlagValue(theZone.outDestroyFlag, info.outDestroyVal, theZone)
			if cfxObjectDestructDetector.verbose or theZone.verbose then 
				trigger.action.outText("+++oDDet: persistence setting flag <" .. theZone.outDestroyFlag .. "> to <" .. info.outDestroyVal .. ">",30)
			end
			local theName = tostring(theZone.ID)
			if info.isDestroyed then 
				-- We now get the scenery object in that zone 
				-- and remove it
				-- note that dcsCommon methods use DCS zones, not cfx
				local theObject = dcsCommon.getSceneryObjectInZoneByName(theName, theZone.dcsZone)
				if theObject then 
					if cfxObjectDestructDetector.verbose or theZone.verbose then 
						trigger.action.outText("+++oDDet: persistence removing dead scenery object <" .. theName .. ">",30)
					end
					theObject:destroy()
				else 
					if cfxObjectDestructDetector.verbose or theZone.verbose then 
						trigger.action.outText("+++oDDet: persistence - can't find scenery objects <" .. theName .. ">, skipped destruction",30)
					end
				end
			else 
				if cfxObjectDestructDetector.verbose or theZone.verbose then 
					trigger.action.outText("+++oDDet: persistence - scenery objects <" .. theName .. "> is healthy",30)
				end
			end
		else 
			trigger.action.outText("+++oDDet: persistence - can't find detector <" .. zName .. "> on load. skipping", 30)
		end
	end
	if cfxObjectDestructDetector.verbose then 
		trigger.action.outText("+++oDDet: persistence - processing complete", 30)
	end	
end

--
-- start
--

function cfxObjectDestructDetector.start()
	if not dcsCommon.libCheck("cfx Object Destruct Detector", 
		cfxObjectDestructDetector.requiredLibs) then
		return false 
	end
	
	-- collect all zones with 'OBJECT id' attribute 
	-- collect all spawn zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("OBJECT ID")
	

	for k, aZone in pairs(attrZones) do 
		cfxObjectDestructDetector.processObjectDestructZone(aZone) -- process attribute and add to zone properties (extend zone)
		cfxObjectDestructDetector.addObjectDetectZone(aZone)
	end

	-- add myself as event handler
	world.addEventHandler(cfxObjectDestructDetector)
	
	-- persistence: see if we have any data to process 
	-- for all our zones, and sign up for data saving 
	if persistence and persistence.active then 
		-- sign up for saves 
		callbacks = {}
		callbacks.persistData = cfxObjectDestructDetector.saveData
		persistence.registerModule("cfxObjectDestructDetector", callbacks)
		
		if persistence.hasData then
			cfxObjectDestructDetector.loadMission()
		end
	else 
		if cfxObjectDestructDetector.verbose then 
			trigger.action.outText("no persistence for cfxObjectDestructDetector", 30)
		end
	end
	
	
	
	-- say hi
	trigger.action.outText("cfx Object Destruct Zones v" .. cfxObjectDestructDetector.version .. " started.", 30)
	return true 
end

-- let's go 
if not cfxObjectDestructDetector.start() then 
	trigger.action.outText("cf/x Object Destruct Zones aborted: missing libraries", 30)
	cfxObjectDestructDetector = nil 
end
