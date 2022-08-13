cfxmon = {}
cfxmon.version = "1.0.0"
cfxmon.delay = 30 -- seconds for display 
--[[--
	Version History 
	1.0.0 - initial version
	
cfxmon is a monitor for all cfx events and callbacks
use monConfig to tell cfxmon which events and callbacks
to monitor. a Property with "no" or "false" will turn 
that monitor OFF, else it will stay on

supported modules if loaded
   dcsCommon
   cfxPlayer
   cfxGroundTroops
   cfxObjectDestructDetector
   cfxSpawnZones
   
--]]--

--
-- CALLBACKS
--
-- dcsCommon Callbacks 
function cfxmon.pre(event) 
	trigger.action.outText("***mon - dcsPre: " .. event.id .. " (" .. dcsCommon.event2text(event.id) .. ")", cfxmon.delay)
	return true 
end

function cfxmon.post(event) 
	trigger.action.outText("***mon - dcsPost: " .. event.id .. " (" .. dcsCommon.event2text(event.id) .. ")", cfxmon.delay)
end

function cfxmon.rejected(event) 
	trigger.action.outText("***mon - dcsReject: " .. event.id .. " (" .. dcsCommon.event2text(event.id) .. ")", cfxmon.delay)
end

function cfxmon.dcsCB(event)
	local initiatorStat = ""
	if event.initiator then
		local theUnit = event.initiator
		local theGroup = theUnit:getGroup()
		
		local theGroupName = "<none>"
		if theGroup then theGroupName = theGroup:getName() end 
		
		initiatorStat = ", for " .. theUnit:getName()
		initiatorStat = initiatorStat .. " of " .. theGroupName 
	else 
		initiatorStat = ", NO Initiator" 
	end 
	trigger.action.outText("***mon - dcsMAIN: " .. event.id .. " (" .. dcsCommon.event2text(event.id) .. ")" .. initiatorStat, cfxmon.delay)
end

-- cfxPlayer callback
function cfxmon.playerEventCB(evType, description, info, data)
	trigger.action.outText("***mon - cfxPlayer: ".. evType ..": <" .. description .. ">", cfxmon.delay)
end

-- cfxGroundTroops callback
function cfxmon.groundTroopsCB(reason, theGroup, orders, data)
	trigger.action.outText("***mon - groundTroops: ".. reason ..": for group <" .. theGroup:getName() .. "> with orders " .. orders, cfxmon.delay)
end

-- object destruct callbacks
function cfxmon.oDestructCB(zone, ObjectID, name)
	trigger.action.outText("***mon - object destroyed: ".. ObjectID .." named <" .. name .. "> in zone " .. zone.name, cfxmon.delay)
end

-- spawner callback 
function cfxmon.spawnZoneCB(reason, theGroup, theSpawner)
	local gName = "<nil>"
	if theGroup then gName = theGroup:getName() end 
	trigger.action.outText("***mon - Spawner: ".. reason .." group <" .. gName .. "> in zone " .. theSpawner.name, cfxmon.delay)
end

-- READ CONFIG AND SUBSCRIBE
function cfxmon.start ()
	local theZone = cfxZones.getZoneByName("monConfig") 
	if not theZone then 
		trigger.action.outText("***mon: WARNING: NO config, defaulting", cfxmon.delay)
		theZone = cfxZones.createSimpleZone("MONCONFIG")
	end
	
	-- own config
	cfxmon.delay = cfxZones.getNumberFromZoneProperty(theZone, "delay", 30)
	trigger.action.outText("!!!mon: Delay is set to: " .. cfxmon.delay .. "seconds", 50)
	
	-- dcsCommon
	if cfxZones.getBoolFromZoneProperty(theZone, "dcsCommon", true) then 
		-- subscribe to dcs event handlers 
		-- note we have all, but only connect the main
		dcsCommon.addEventHandler(cfxmon.dcsCB) -- we only connect one
		trigger.action.outText("!!!mon: +dcsCommon", cfxmon.delay)
	else 
		trigger.action.outText("***mon: -dcsCommon", cfxmon.delay)
	end
	
	-- cfxPlayer 
	if cfxPlayer and cfxZones.getBoolFromZoneProperty(theZone, "cfxPlayer", true) then 
		cfxPlayer.addMonitor(cfxmon.playerEventCB)
		trigger.action.outText("!!!mon: +cfxPlayer", cfxmon.delay)
	else 
		trigger.action.outText("***mon: -cfxPlayer", cfxmon.delay)
	end
	
	-- cfxGroundTroops
	if cfxGroundTroops and cfxZones.getBoolFromZoneProperty(theZone, "cfxGroundTroops", true) then 
		cfxGroundTroops.addTroopsCallback(cfxmon.groundTroopsCB)
		trigger.action.outText("!!!mon: +cfxGroundTroops", cfxmon.delay)
	else 
		trigger.action.outText("***mon: -cfxGroundTroops", cfxmon.delay)
	end
	
	-- objectDestructZones
	if cfxObjectDestructDetector and cfxZones.getBoolFromZoneProperty(theZone, "cfxObjectDestructDetector", true) then 
		cfxObjectDestructDetector.addCallback(cfxmon.oDestructCB)
		trigger.action.outText("!!!mon: +cfxObjectDestructDetector", cfxmon.delay)
	else 
		trigger.action.outText("***mon: -cfxObjectDestructDetector", cfxmon.delay)
	end
	
	-- spawnZones 
	if cfxSpawnZones and cfxZones.getBoolFromZoneProperty(theZone, "cfxSpawnZones", true) then 
		cfxSpawnZones.addCallback(cfxmon.spawnZoneCB)
		trigger.action.outText("!!!mon: +cfxSpawnZones", cfxmon.delay)
	else 
		trigger.action.outText("***mon: -cfxSpawnZones", cfxmon.delay)
	end
end

cfxmon.start()
