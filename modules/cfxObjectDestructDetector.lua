cfxObjectDestructDetector = {}
cfxObjectDestructDetector.version = "1.2.0" 
cfxObjectDestructDetector.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
cfxObjectDestructDetector.verbose = false 
--[[--
   VERSION HISTORY 
   1.0.0 initial version, based on parashoo, arty zones  
   1.0.1 fixed bug: trigger.MISC.getUserFlag()
   1.1.0 added support for method, f! and destroyed! 
   1.2.0 DML / Watchflag support 
   
   
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

--
-- processing of zones 
--
function cfxObjectDestructDetector.processObjectDestructZone(aZone)
	aZone.name = cfxZones.getStringFromZoneProperty(aZone, "NAME", aZone.name)
--	aZone.coalition = cfxZones.getCoalitionFromZoneProperty(aZone, "coalition", 0)
	aZone.ID = cfxZones.getNumberFromZoneProperty(aZone, "OBJECT ID", 1)  -- THIS!
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
	
	-- new method support
	aZone.oddMethod = cfxZones.getStringFromZoneProperty(aZone, "method", "flip")
	if cfxZones.hasProperty(aZone, "oddMethod") then 
		aZone.oddMethod = cfxZones.getStringFromZoneProperty(aZone, "oddMethod", "flip")
	end
	
	
	if cfxZones.hasProperty(aZone, "f!") then 
		aZone.outDestroyFlag = cfxZones.getStringFromZoneProperty(aZone, "f!", "*none")
	end
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
			if aZone.ID == id then 
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
				if cfxObjectDestructDetector.verbose then 
					trigger.action.outText("OBJECT KILL: " .. id, 30)
				end

				-- we could now remove the object from the list 
				-- for better performance since it cant
				-- die twice 
				
				return 
			end
		end
		
    end
	
end
-- add event handler


function cfxObjectDestructDetector.start()
	if not dcsCommon.libCheck("cfx Object Destruct Detector", 
		cfxObjectDestructDetector.requiredLibs) then
		return false 
	end
	
	-- collect all zones with 'smoke' attribute 
	-- collect all spawn zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("OBJECT ID")
	
	-- now create a spawner for all, add them to the spawner updater, and spawn for all zones that are not
	-- paused 
	for k, aZone in pairs(attrZones) do 
		cfxObjectDestructDetector.processObjectDestructZone(aZone) -- process attribute and add to zone properties (extend zone)
		cfxObjectDestructDetector.addObjectDetectZone(aZone) -- remember it so we can smoke it
	end

	-- add myself as event handler
	world.addEventHandler(cfxObjectDestructDetector)
	
	-- say hi
	trigger.action.outText("cfx Object Destruct Zones v" .. cfxObjectDestructDetector.version .. " started.", 30)
	return true 
end

-- let's go 
if not cfxObjectDestructDetector.start() then 
	trigger.action.outText("cf/x Object Destruct Zones aborted: missing libraries", 30)
	cfxObjectDestructDetector = nil 
end
