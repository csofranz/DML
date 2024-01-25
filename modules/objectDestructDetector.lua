cfxObjectDestructDetector = {}
cfxObjectDestructDetector.version = "2.0.2" 
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
   2.0.0 dmlZone OOP support 
		 clean-up 
         re-wrote object determination to not be affected by 
		 ID changes (happens with map updates)
		 fail addZone when name property is missing 
   2.0.1 check that the object is within the zone onEvent 
   2.0.2 redScore and bluescore attributes 
         API for PlayerScore to pass back redScore/blueScore 
		 if objects was killed by player 
		 verbosity bug fixed after kill (ref to old ID)
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
		theCB(zone, zone.ID, zone.name, zone.objName)
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
	if aZone:hasProperty("name") then 
		aZone.objName = string.upper(aZone:getStringFromZoneProperty("NAME", "default"))
	else 
		trigger.action.outText("+++OOD: Zone <" .. aZone.name .. "> lacks name attribute, ignored for destruct detection.")
		return false
	end 
	
	-- persistence interface
	aZone.isDestroyed = false 
	
	aZone.oddMethod = aZone:getStringFromZoneProperty("method", "inc")
	if aZone:hasProperty("oddMethod") then 
		aZone.oddMethod = aZone:getStringFromZoneProperty("oddMethod", "inc")
	end
	
	if aZone:hasProperty("f!") then 
		aZone.outDestroyFlag = aZone:getStringFromZoneProperty("f!", "*none")
	elseif aZone:hasProperty("destroyed!") then 
		aZone.outDestroyFlag = aZone:getStringFromZoneProperty("destroyed!", "*none")
	elseif aZone:hasProperty("objectDestroyed!") then 
		aZone.outDestroyFlag = aZone:getStringFromZoneProperty( "objectDestroyed!", "*none")
	end
	
	--PlayerScore interface (data)
	if aZone:hasProperty("redScore") then 
		aZone.redScore = aZone:getNumberFromZoneProperty("redScore", 0)
--		if aZone.verbose then 
--			trigger.action.outText("")
--		end
	end 
	
	if aZone:hasProperty("blueScore") then 
		aZone.blueScore = aZone:getNumberFromZoneProperty("blueScore", 0)
	end 
	
	return true 
end

--
-- Interface with PlayerScore
-- ==========================
-- PlayerScore invokes us when it finds a scenery object was killed
-- we check if it is one of ours, and if so, if a score is attached 
-- for that side
function cfxObjectDestructDetector.playerScoreForKill(theObject, killSide)
	if not theObject then return nil end 
	if not killSide then return nil end 
	local pos = theObject:getPoint() 
	local desc = theObject:getDesc()
	if not desc then return nil end 
	desc = desc.typeName -- deref type name to match zone objName 
	if not desc then return end 
	for idx, theZone in pairs (cfxObjectDestructDetector.objectZones) do 
		-- see if we can find a matching ODD 
		if (not theZone.isDestroyed) -- make sure it's not a dupe
		    and theZone.objName == desc 
			and theZone:pointInZone(pos) 
		then 
			-- yes, ODD tracks this object 
			if cfxObjectDestructDetector.verbose or theZone.verbose then 
				trigger.action.outText("OOD: score invocation for hit scenery object <" .. desc .. ">, tracked with <" .. theZone.name .. ">", 30)				
			end
			if killSide == 1 then return theZone.redScore end -- can be nil!
			if killSide == 2 then return theZone.blueScore end 
			-- if we get here, the object is tracked, but has no 
			-- playerScore attached. simply exist with nil
				if cfxObjectDestructDetector.verbose or theZone.verbose then 
					trigger.action.outText("OOD: scenery object <" .. desc .. ">, tracked but no player score defined for coa <" .. killSide .. ">.", 30)				
				end			
			return nil 
		end
	end
	return nil 
end

--
-- ON EVENT
--
function cfxObjectDestructDetector:onEvent(event)
	if event.id == world.event.S_EVENT_DEAD then
		if not event.initiator then return end 
		local theObject = event.initiator
		-- check location 
		local pos = theObject:getPoint() 
		local desc = theObject:getDesc() 
		if not desc then return end 
		local matchMe = desc.typeName -- we home in on object's typeName 
		if not matchMe then return end 
		matchMe = string.upper(matchMe)
		
		for idx, aZone in pairs(cfxObjectDestructDetector.objectZones) do 
			if (not aZone.isDestroyed) 
			    and aZone.objName == matchMe 
				and aZone:pointInZone(pos) -- make sure it's not a dupe
			then 
				if aZone.outDestroyFlag then 
					aZone:pollFlag(aZone.outDestroyFlag, aZone.oddMethod)
				end
				-- invoke callbacks 
				cfxObjectDestructDetector.invokeCallbacksFor(aZone)
				if aZone.verbose or cfxObjectDestructDetector.verbose then 
					trigger.action.outText("OBJECT KILL: " .. matchMe .. " for odd <" .. aZone.name .. ">", 30)
				end
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
		info.outDestroyVal = aZone:getFlagValue(aZone.outDestroyFlag)
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
			theZone:setFlagValue(theZone.outDestroyFlag, info.outDestroyVal)
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
	
	-- collect all zones with 'OBJECT ID' attribute 
	local attrZones = cfxZones.getZonesWithAttributeNamed("OBJECT ID")
	

	for k, aZone in pairs(attrZones) do 
		if cfxObjectDestructDetector.processObjectDestructZone(aZone) then 
			cfxObjectDestructDetector.addObjectDetectZone(aZone)
		end
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
