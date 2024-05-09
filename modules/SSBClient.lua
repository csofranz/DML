cfxSSBClient = {}
cfxSSBClient.version = "4.0.0"
cfxSSBClient.verbose = false 
cfxSSBClient.singleUse = false -- set to true to block crashed planes
-- NOTE: singleUse (true) requires SSB to disable immediate respawn after kick
cfxSSBClient.reUseAfter = -1 -- seconds for re-use delay
  -- only when singleUse is in effect. -1 means never 
  
cfxSSBClient.requiredLibs = {
	"dcsCommon", -- always
	"cfxMX", --"cfxGroups", -- for slot access
	"cfxZones", -- Zones, of course 
}

--[[--
Version History
  4.0.0 - dmlZones 
		- cfxMX instead of cfxGroups 
--]]--

cfxSSBClient.enabledFlagValue = 0 -- DO NOT CHANGE, MUST MATCH SSB 
cfxSSBClient.disabledFlagValue = cfxSSBClient.enabledFlagValue + 100 -- DO NOT CHANGE
cfxSSBClient.allowNeutralFields = false -- set to FALSE if players can't spawn on neutral airfields 
cfxSSBClient.maxAirfieldRange = 3000 -- meters to airfield before group is no longer associated with airfield 
-- actions to home in on when a player plane is detected and a slot may 
-- be blocked. Currently, homing in on airfield, but not fly over 
cfxSSBClient.slotActions = {
	"From Runway",
	"From Parking Area",
	"From Parking Area Hot",
	"From Ground Area",
	"From Ground Area Hot",
}
cfxSSBClient.keepInAirGroups = false -- if false we only look at planes starting on the ground 
-- setting this to true only makes sense if you plan to bind in-air starts to airfields 

cfxSSBClient.playerGroups = {}
cfxSSBClient.closedAirfields = {} -- list that closes airfields for any aircrafts
cfxSSBClient.playerPlanes = {} -- names of units that a player is flying
cfxSSBClient.crashedGroups = {} -- names of groups to block after crash of their player-flown plane 
cfxSSBClient.slotState = {} -- keeps a record of which slot has which value. For persistence and debugging 
cfxSSBClient.occupiedUnits = {} -- by unit name if occupied to prevent kicking. clears after crash or leaving plane 
-- will not be persisted because on start all planes are empty 

-- dml zone interface for open/close interface
cfxSSBClient.clientZones = {}

function cfxSSBClient.addClientZone(theZone)
	table.insert(cfxSSBClient.clientZones, theZone)
end

function cfxSSBClient.getClientZoneByName(aName) 
	for idx, aZone in pairs(cfxSSBClient.clientZones) do 
		if aName == aZone.name then return aZone end 
	end
	if cfxSSBClient.verbose then 
		trigger.action.outText("+++ssbc: no client zone with name <" .. aName ..">", 30)
	end 

	return nil 
end

--
-- read client zones 
--
function cfxSSBClient.createClientZone(theZone)
	local thePoint = theZone:getPoint()
	local theAF = cfxSSBClient.getClosestAirbaseTo(thePoint)
	local afName = theAF:getName()
	if cfxSSBClient.verbose or theZone.verbose then 
		trigger.action.outText("+++ssbc: zone <" .. theZone.name .. "> linked to AF/FARP <" .. afName .. ">", 30)
	end
	theZone.afName = afName
	theZone.ssbTriggerMethod = theZone:getStringFromZoneProperty( "ssbTriggerMethod", "change")
	
	if theZone:hasProperty("open?") then 
		theZone.ssbOpen = theZone:getStringFromZoneProperty("open?", "none")
		theZone.lastSsbOpen = cfxZones.getFlagValue(theZone.ssbOpen, theZone)
	end
	
	if theZone:hasProperty("close?") then 
		theZone.ssbClose = theZone:getStringFromZoneProperty("close?", "none")
		theZone.lastSsbClose = cfxZones.getFlagValue(theZone.ssbClose, theZone)
	end
	
	theZone.ssbOpenOnStart = theZone:getBoolFromZoneProperty( "openOnStart", true)
	if not theZone.ssbOpenOnStart then 
		cfxSSBClient.closeAirfieldNamed(theZone.afName)
	end
end

--
-- Open / Close Airfield API 
--
function cfxSSBClient.closeAirfieldNamed(name)
	if not name then return end 
	cfxSSBClient.closedAirfields[name] = true 
	cfxSSBClient.setSlotAccessByAirfieldOwner()
	if cfxSSBClient.verbose then 
		trigger.action.outText("+++SSB: Airfield " .. name .. " now closed", 30) 
	end
end

function cfxSSBClient.openAirFieldNamed(name)
	cfxSSBClient.closedAirfields[name] = nil 
	cfxSSBClient.setSlotAccessByAirfieldOwner()
	if cfxSSBClient.verbose then 
		trigger.action.outText("+++SSB: Airfield " .. name .. " just opened", 30) 
	end
end

function cfxSSBClient.unbindGroup(groupName)
	cfxSSBClient.bindGroupToAirfield(groupName, nil)
end

function cfxSSBClient.bindGroupToAirfield(groupName, airfieldName)
	if not groupName then return end 
	local airfield = nil
	if airfieldName then airfield = Airbase.getByName(airfieldName) end 
	for idx, theGroup in pairs(cfxSSBClient.playerGroups) do
		if theGroup.name == groupName then 
			if cfxSSBClient.verbose then
				local newBind = "NIL"
				if airfield then newBind = airfieldName end 
				trigger.action.outText("+++SSB: Group " .. theGroup.name .. " changed binding to " .. newBind, 30) 
			end
			theGroup.airfield = airfield
			return
		end
	end
	if not airfieldName then airfieldName = "<NIL>" end 
	trigger.action.outText("+++SSB: Binding Group " .. groupName .. " to " .. airfieldName .. " failed.", 30) 
end


function cfxSSBClient.getClosestAirbaseTo(thePoint)
	local delta = math.huge
	local allYourBase = world.getAirbases() -- get em all
	local closestBase = nil 
	for idx, aBase in pairs(allYourBase) do
		-- iterate them all 
		local abPoint = aBase:getPoint()
		newDelta = dcsCommon.dist(thePoint, {x=abPoint.x, y = 0, z=abPoint.z})
		if newDelta < delta then 
			delta = newDelta
			closestBase = aBase
		end
	end
	return closestBase, delta 
end

function cfxSSBClient.setSlotAccessForGroup(theGroup)
	if not theGroup then return end 
	-- WARNING: theGroup is cfxGroup record  
	local theName = theGroup.name 
	
	-- we now check if any plane of that group is still 
	-- existing and in the air. if so, we skip this check
	-- to prevent players being kicked for losing their 
	-- originating airfield 
	
	-- we now iterate all playerUnits in theGroup.
	-- theGroup is cfxGroup 
	for idx, playerData in pairs (theGroup.playerUnits) do 
		local uName = playerData.name 
		if cfxSSBClient.occupiedUnits[uName] then 
			if cfxSSBClient.verbose then 
				trigger.action.outText("+++ssbc: unit <" .. uName .. "> of group <" .. theName .. "> is occupied, no airfield check", 30)
			end
			return 
		end
	end
	
	-- when we get here, no unit in the entire group is occupied 
	local theMatchingAirfield = theGroup.airfield 
	-- airfield was attached at startup to group 
	if cfxSSBClient.singleUse and cfxSSBClient.crashedGroups[theName] then 
	   -- we don't check, as we know it's blocked after crash 
	   -- and leave it as it is. Nothing to do at all now
		   
	elseif theMatchingAirfield ~= nil then 
		local blockState = cfxSSBClient.enabledFlagValue -- we default to ALLOW the block
		local comment = "available"
		-- we have found a plane that is tied to an airfield 
		-- so this group will receive a block/unblock
		-- we always set all block/unblock every time

		-- see if airfield currently exist (might be dead or late activate)
		if not Object.isExist(theMatchingAirfield) then
			-- airfield does not exits yet/any more 
			blockState = cfxSSBClient.disabledFlagValue
			comment = "!inactive airfield!"
		else 
			local airFieldSide = theMatchingAirfield:getCoalition()
			local groupCoalition = theGroup.coaNum
			
			-- see if airfield is closed 
			local afName = theMatchingAirfield:getName()
			if cfxSSBClient.closedAirfields[afName] then 
				-- airfield is closed. no take-offs 
				blockState = cfxSSBClient.disabledFlagValue
				comment = "!closed airfield!"
			end
				
			-- on top of that, check coalitions
			if groupCoalition ~= airFieldSide then 
				-- we have a problem. sides don't match 
				if airFieldSide == 3 
				or (cfxSSBClient.allowNeutralFields and airFieldSide == 0)
				then 
					-- all is well, airfield is contested or neutral and 
					-- we allow this plane to spawn here
				else 
					-- DISALLOWED!!!!
					blockState = cfxSSBClient.disabledFlagValue
					comment = "!!!BLOCKED!!!"
				end
			end 
		end 
		
		-- now set the ssb flag for this group so the server can see it
		if cfxSSBClient.verbose then 
			local lastState = trigger.misc.getUserFlag(theName)
			if lastState ~= blockState then 
				trigger.action.outText("+++ssbc: <" .. theName .. "> changes from <" .. lastState .. "> to <" .. blockState .. ">", 30)
				trigger.action.outText("+++SSB: group ".. theName .. ": " .. comment, 30)
			end
		end
		trigger.action.setUserFlag(theName, blockState)
		cfxSSBClient.slotState[theName] = blockState
		--if cfxSSBClient.verbose then 
		--end 
	else 
		if cfxSSBClient.verbose then 
			trigger.action.outText("+++SSB: group ".. theName .. " no bound airfield: available", 30)
		end
	end
end

function cfxSSBClient.setSlotAccessForUnit(theUnit) -- calls setSlotAccessForGroup
	if not theUnit then return end 
	local theGroup = theUnit:getGroup()
	if not theGroup then return end 
	local gName = theGroup:getName()
	if not gName then return end 
	local pGroup = cfxSSBClient.getPlayerGroupForGroupNamed(gName)
	if pGroup then   
		cfxSSBClient.setSlotAccessForGroup(pGroup) 
	end
end

function cfxSSBClient.getPlayerGroupForGroupNamed(aName)
	local pGroups = cfxSSBClient.playerGroups
	for idx, theGroup in pairs(pGroups) do
		if theGroup.name == aName then return theGroup end 
	end
	return nil 
end

function cfxSSBClient.setSlotAccessByAirfieldOwner()
	-- get all groups that have a player-controlled aircraft
	-- now uses cached, reduced set of player planes
	local pGroups = cfxSSBClient.playerGroups 
	for idx, theGroup in pairs(pGroups) do
		cfxSSBClient.setSlotAccessForGroup(theGroup)
	end
end

function cfxSSBClient.reOpenSlotForGroupNamed(args)
	-- this is merely the timer shell for opening the crashed slot
	gName = args[1]
	cfxSSBClient.openSlotForCrashedGroupNamed(gName)
end

function cfxSSBClient.openSlotForCrashedGroupNamed(gName)
	if not gName then return end
	local pGroup = cfxSSBClient.getPlayerGroupForGroupNamed(gName)
	if not pGroup then return end 
	cfxSSBClient.crashedGroups[gName] = nil -- set to nil to forget this happened 
	cfxSSBClient.setSlotAccessForGroup(pGroup) -- set by current occupation status 
	if cfxSSBClient.verbose then 
		trigger.action.outText("+++SSBC:SU: re-opened slot for group <" .. gName .. ">", 30)
	end 
end

function cfxSSBClient:onEvent(event) 
	if event.id == 21 then -- S_EVENT_PLAYER_LEAVE_UNIT
		local theUnit = event.initiator
		if not theUnit then
			if cfxSSBClient.verbose then
				trigger.action.outText("+++SSB: No unit left, abort", 30)
			end
			return 
		end 
		local curH = theUnit:getLife()
		local maxH = theUnit:getLife0()
		local uName = theUnit:getName()
		if cfxSSBClient.verbose then 
			trigger.action.outText("+++SSB: Player leaves unit <" .. uName .. ">", 30)
			trigger.action.outText("+++SSB: unit health check: " .. curH .. " of " .. maxH, 30)
		end
		
		cfxSSBClient.occupiedUnits[uName] = nil -- forget I was occupied
		cfxSSBClient.setSlotAccessForUnit(theUnit) -- prevent re-slotting if airfield lost
		return 
	end
	
	if event.id == 10 then -- S_EVENT_BASE_CAPTURED
		if cfxSSBClient.verbose then
			local place = event.place 
			
			trigger.action.outText("+++SSB: CAPTURE EVENT: <" .. place:getName() .. "> now owned by <" .. place:getCoalition() .. "> -- RESETTING SLOTS", 30)
		end
		cfxSSBClient.setSlotAccessByAirfieldOwner()
	end

-- write down player names and planes
	if event.id == 15 then -- birth
		if not event.initiator then return end 
		local theUnit = event.initiator -- we know this exists
		local uName = theUnit:getName()
		if not uName then return end 
		-- player entered unit? 
		-- check if this is a cloned impostor
		if not theUnit.getPlayerName then 
			if cfxSSBClient.verbose then 
				trigger.action.outText("+++SSBC: non-player 'client' " .. uName .. " detected, ignoring.", 30)
			end
			return
		end
		local playerName = theUnit:getPlayerName()
		if not playerName then 
			return -- NPC plane
		end 
		-- remember this unit as player controlled plane
		-- because player and plane can easily disconnect
		cfxSSBClient.playerPlanes[uName] = playerName
		if cfxSSBClient.verbose then 
			trigger.action.outText("+++SSBC:SU: noted " .. playerName .. " piloting player unit " .. uName, 30)
		end 
		-- mark it as occupied to player won't get kicked until they
		-- leave the unit 
		cfxSSBClient.occupiedUnits[uName] = playerName
		return 
	end
	
	if event.id == 5 then -- crash PRE-processing 
		if not event.initiator then return end
		local theUnit = event.initiator 
		local uName = theUnit:getName()
		cfxSSBClient.occupiedUnits[uName] = nil -- no longer occupied
		cfxSSBClient.setSlotAccessForUnit(theUnit) -- prevent re-slotting if airfield lost
	end

	if cfxSSBClient.singleUse and event.id == 5 then -- crash
		--if not event.initiator then return end 
		local theUnit = event.initiator 
		local uName = theUnit:getName()
		if not uName then return end
		local theGroup = theUnit:getGroup()
		if not theGroup then return end 
		-- see if a player plane
		local thePilot = cfxSSBClient.playerPlanes[uName]
		if not thePilot then 
			-- ignore. not a player plane
			if cfxSSBClient.verbose then 
				trigger.action.outText("+++SSBC:SU: ignored crash for NPC unit <" .. uName .. ">", 30)
			end 
			return 
		end
		-- if we get here, a player-owned plane has crashed 
		local gName = theGroup:getName()
		if not gName then return end 
		
		-- block this slot. 
		trigger.action.setUserFlag(gName, cfxSSBClient.disabledFlagValue)
		cfxSSBClient.slotState[gName] = cfxSSBClient.disabledFlagValue
		-- remember this plane to not re-enable if 
		-- airfield changes hands later 
		cfxSSBClient.crashedGroups[gName] = thePilot -- set to crash pilot 
		if cfxSSBClient.verbose then 
			trigger.action.outText("+++SSBC:SU: Blocked slot for group <" .. gName .. ">", 30)
		end 
		
		if cfxSSBClient.reUseAfter > 0 then 
			-- schedule re-opening this slot in <x> seconds
			timer.scheduleFunction(
				cfxSSBClient.reOpenSlotForGroupNamed, 
				{gName}, 
				timer.getTime() + cfxSSBClient.reUseAfter
				)
		end
	end
end

function cfxSSBClient.update()
	-- first, re-schedule me in one minute 
	timer.scheduleFunction(cfxSSBClient.update, {}, timer.getTime() + 60)
	
	-- now establish all slot blocks 
	cfxSSBClient.setSlotAccessByAirfieldOwner()
	
	-- show occupied planes
	if cfxSSBClient.verbose then 
		for uName, pName in pairs (cfxSSBClient.occupiedUnits) do 
			trigger.action.outText("+++ssbc: <" .. uName .. "> occupied by <" .. pName .. ">", 30)
		end
	end
end

function cfxSSBClient.dmlUpdate()
	-- first, re-schedule me in one second 
	timer.scheduleFunction(cfxSSBClient.dmlUpdate, {}, timer.getTime() + 1)
	
	for idx, theZone in pairs (cfxSSBClient.clientZones) do 
		-- see if we received any signals on out inputs
		if theZone.ssbOpen and cfxZones.testZoneFlag(theZone, theZone.ssbOpen, theZone.ssbTriggerMethod, "lastSsbOpen") then 
			if theZone.verbose then 
				trigger.action.outText("+++ssbc: <" .. theZone.name .. "> open input triggered for <" .. theZone.afName .. ">", 30)
			end
			cfxSSBClient.openAirFieldNamed(theZone.afName)
		end
		
		if theZone.ssbClose and cfxZones.testZoneFlag(theZone, theZone.ssbClose, theZone.ssbTriggerMethod, "lastSsbClose") then 
			if theZone.verbose then 
				trigger.action.outText("+++ssbc: <" .. theZone.name .. "> close input triggered for <" .. theZone.afName .. ">", 30)
			end
			cfxSSBClient.closeAirfieldNamed(theZone.afName)
		end
	end
end


-- pre-process static player data to minimize 
-- processor load on checks
function cfxSSBClient.processPlayerData()
	cfxSSBClient.playerGroups = cfxMX.getPlayerGroup()
	local pGroups = cfxSSBClient.playerGroups
	local filteredPlayers = {}
	for idx, theGroup in pairs(pGroups) do
		if theGroup.airfield ~= nil or cfxSSBClient.keepInAirGroups or 
		cfxSSBClient.singleUse then 
			-- only transfer groups that have airfields (or also keepInAirGroups or when single-use)
			-- attached. Ignore the rest as they are 
			-- always fine
			table.insert(filteredPlayers, theGroup)
		end
	end
	cfxSSBClient.playerGroups = filteredPlayers
end

-- add airfield information to each player group
function cfxSSBClient.processGroupData()
	local pGroups = cfxMX.getPlayerGroup() -- we want the group.name attribute
	for idx, theGroup in pairs(pGroups) do
		-- we always use the first player's plane as referenced
		local playerData = theGroup.playerUnits[1]
		local theAirfield = nil
		local delta = -1
		local action = playerData.action 
		if not action then action = "<NIL>" end 
		-- see if the data has any of the slot-interesting actions
		if dcsCommon.arrayContainsString(cfxSSBClient.slotActions, action ) then 
			-- yes, fetch the closest airfield 
			theAirfield, delta = cfxSSBClient.getClosestAirbaseTo(playerData.point)
			local afName = theAirfield:getName()
			if cfxSSBClient.verbose then 
				trigger.action.outText("+++SSB: group: " .. theGroup.name .. " closest to AF " .. afName .. ": " .. math.floor(delta) .. "m" , 30)
			end 
			if delta > cfxSSBClient.maxAirfieldRange then 
				-- forget airfield
				 theAirfield = nil
				if cfxSSBClient.verbose then 
					trigger.action.outText("+++SSB: group: " .. theGroup.name .. " unlinked - too far from airfield" , 30)
				end 
			end
			theGroup.airfield = theAirfield
		else 
			if cfxSSBClient.verbose then 
				trigger.action.outText("+++SSB: group: " .. theGroup.name .. " start option " .. action .. " does not concern SSB", 30)
			end 
		end
	end
end

--
-- read config zone
--
function cfxSSBClient.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("SSBClientConfig") 
	if not theZone then 
		trigger.action.outText("+++SSBC: no config zone!", 30) 
		return 
	end 
	
	trigger.action.outText("+++SSBC: found config zone!", 30) 
	
	cfxSSBClient.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	-- single-use
	cfxSSBClient.singleUse = cfxZones.getBoolFromZoneProperty(theZone, "singleUse", false) -- use airframes only once? respawn after kick must be disabled in ssb
	cfxSSBClient.reUseAfter = cfxZones.getNumberFromZoneProperty(theZone, "reUseAfter", -1)
	
	-- airfield availability 
	cfxSSBClient.allowNeutralFields = cfxZones.getBoolFromZoneProperty(theZone, "allowNeutralFields", false)
	
	cfxSSBClient.maxAirfieldRange = cfxZones.getNumberFromZoneProperty(theZone, "maxAirfieldRange", 3000) -- meters, to find attached airfield

	-- optimization 
	
	cfxSSBClient.keepInAirGroups = cfxZones.getBoolFromZoneProperty(theZone, "keepInAirGroups", false)
	
	-- SSB direct control. 
	-- USE ONLY WHEN YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
	
	cfxSSBClient.enabledFlagValue = cfxZones.getNumberFromZoneProperty(theZone, "enabledFlagValue", 0)
	
	cfxSSBClient.disabledFlagValue = cfxZones.getNumberFromZoneProperty(theZone, "disabledFlagValue", cfxSSBClient.enabledFlagValue + 100)
end

--
-- load / save 
--
function cfxSSBClient.saveData()
	local theData = {}
	local states = dcsCommon.clone(cfxSSBClient.slotState)
	local crashed = dcsCommon.clone(cfxSSBClient.crashedGroups)
	local closed = dcsCommon.clone(cfxSSBClient.closedAirfields)
	theData.states = states
	theData.crashed = crashed 
	theData.closed = closed 
	return theData
end

function cfxSSBClient.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("cfxSSBClient")
	if not theData then 
		if cfxSSBClient.verbose then 
			trigger.action.outText("+++cfxSSB: no save date received, skipping.", 30)
		end
		return
	end
	
	cfxSSBClient.slotState = theData.states
	if not cfxSSBClient.slotState then
		trigger.action.outText("SSBClient: nil slot state on load", 30)
		cfxSSBClient.slotState = {} 
	end
	for slot, state in pairs (cfxSSBClient.slotState) do 
		trigger.action.setUserFlag(slot, state)
		if state > 0 and cfxSSBClient.verbose then 
			trigger.action.outText("SSB: blocked <" .. slot .. "> on load", 30)
		end
	end
	if theData.crashed then 
		cfxSSBClient.crashedGroups = theData.crashed 
		if not cfxSSBClient.crashedGroups then 
			cfxSSBClient.crashedGroups = {} 		
			trigger.action.outText("SSBClient: nil crashers on load", 30)
		end
	end

	if theData.closed then 
		cfxSSBClient.closedAirfields = theData.closed 
	end
	
end

--
-- start
--
function cfxSSBClient.start()
	-- verify modules loaded 
	if not dcsCommon.libCheck("cfx SSB Client", 
		cfxSSBClient.requiredLibs) then
		return false 
	end
	
	-- read config zone if present 
	cfxSSBClient.readConfigZone()
	
	-- install callback for events in DCS
	world.addEventHandler(cfxSSBClient)
	
	-- process group data to attach airfields 
	cfxSSBClient.processGroupData()
	
	-- process player data to minimize effort and build cache
	-- into cfxSSBClient.playerGroups
	cfxSSBClient.processPlayerData()
	
	-- process ssbc zones 
	-- for in-mission DML interface
	local attrZones = cfxZones.getZonesWithAttributeNamed("ssbClient")
	for k, theZone in pairs(attrZones) do 
		cfxSSBClient.createClientZone(theZone) -- process attributes
		cfxSSBClient.addClientZone(theZone) -- add to list
	end
	
	-- install a timed update just to make sure
	-- and start NOW
	timer.scheduleFunction(cfxSSBClient.update, {}, timer.getTime() + 1)
	
	-- start dml update (on a different timer
	cfxSSBClient.dmlUpdate()
	 
	-- now turn on ssb 
	trigger.action.setUserFlag("SSB",100)
	
	-- persistence: load states 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = cfxSSBClient.saveData
		persistence.registerModule("cfxSSBClient", callbacks)
		-- now load my data 
		cfxSSBClient.loadData()
	end
	
	-- say hi!
	trigger.action.outText("cfxSSBClient v".. cfxSSBClient.version .. " running, SBB enabled", 30)
	
	
	return true 
end

if not cfxSSBClient.start() then 
	trigger.action.outText("cfxSSBClient v".. cfxSSBClient.version .. " FAILED loading.", 30)
	cfxSSBClient = nil
end

--[[--
  possible improvements: 
	- use explicitBlockList that with API. planes on that list are always blocked. Use this for special effects, such as allowing a slot only to open from scripts, e.g. when a condition is met like money or goals reached
   
-]]--