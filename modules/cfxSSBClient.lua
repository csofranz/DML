cfxSSBClient = {}
cfxSSBClient.version = "2.0.0"
cfxSSBClient.verbose = false 
cfxSSBClient.singleUse = false -- set to true to block crashed planes
-- NOTE: singleUse (true) requires SSB to disable immediate respawn after kick
cfxSSBClient.reUseAfter = -1 -- seconds for re-use delay
  -- only when singleUse is in effect. -1 means never 
  
cfxSSBClient.requiredLibs = {
	"dcsCommon", -- always
	"cfxGroups", -- for slot access
	"cfxZones", -- Zones, of course 
}

--[[--
Version History
  1.0.0 - initial version
  1.1.0 - detect airfield by action and location, not group name
  1.1.1 - performance tuning. only read player groups once 
        - and remove in-air-start groups from scan. this requires
        - ssb (server) be not modified	
  1.2.0 - API to close airfields: invoke openAirfieldNamed() 
          and closeAirfieldNamed() with name as string (exact match required)
		  to block an airfield for any player aircraft.
		  Works for FARPS as well 
		  API to associate a player group with any airfied's status (nil for unbind):
		  cfxSSBClient.bindGroupToAirfield(group, airfieldName)
		  API shortcut to unbind groups: cfxSSBClient.unbindGroup(group) 
		  verbose messages now identify better: "+++SSB:"
		  keepInAirGroups option 
  2.0.0 - include single-use ability: crashed airplanes are blocked from further use
        - single-use can be turned off 
		- getPlayerGroupForGroupNamed()
		- split setSlotAccess to single accessor 
		  and interator
		- reUseAfter option for single-use  
		- dcsCommon, cfxZones import
	
WHAT IT IS
SSB Client is a small script that forms the client-side counterpart to
Ciribob's simple slot block. It will block slots for all client airframes
that are on an airfield that does not belong to the faction that currently
owns the airfield. 

REQUIRES CIRIBOB's SIMPLE SLOT BLOCK (SSB) TO RUN ON THE SERVER

If run without SSB, your planes will not be blocked.

In order to work, a plane that should be blocked when the airfield or 
FARP doesn't belong to the player's faction, the group's first unit
must be within 3000 meters of the airfield and on the ground. 
Previous versions of this script relied on group names. No longer.


WARNING:
If you modified ssb's flag values, this script will not work 

YOU DO NOT NEED TO ACTIVATE SBB, THIS SCRIPT DOES SO AUTOMAGICALLY


--]]--

-- below value for enabled MUST BE THE SAME AS THE VALUE OF THE SAME NAME 
-- IN SSB. DEFAULT IS ZERO, AND THIS WILL WORK

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
--[[--
function cfxSSBClient.dist(point1, point2) -- returns distance between two points	  	  
  local x = point1.x - point2.x
  local y = point1.y - point2.y 
  local z = point1.z - point2.z
  
  return (x*x + y*y + z*z)^0.5
end
--]]--
	
-- see if instring conatins what, defaults to case insensitive
--[[--
function cfxSSBClient.containsString(inString, what, caseSensitive)
	if (not caseSensitive) then 
		inString = string.upper(inString)
		what = string.upper(what)
	end
	return string.find(inString, what)
end
--]]--
--[[--
function cfxSSBClient.arrayContainsString(theArray, theString)
	-- warning: case sensitive!
	if not theArray then return false end
	if not theString then return false end
	for i = 1, #theArray do 
		if theArray[i] == theString then return true end 
	end
	return false 
end
--]]--

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
	local theMatchingAirfield = theGroup.airfield 
	-- airfield was attached at startup to group 
	if cfxSSBClient.singleUse and cfxSSBClient.crashedGroups[theName] then 
	   -- we don't check, as we know it's blocked after crash 
	   -- and leave it as it is. Nothing to do at all now
		   
	elseif theMatchingAirfield ~= nil then 
		-- we have found a plane that is tied to an airfield 
		-- so this group will receive a block/unblock
		-- we always set all block/unblock every time
		-- note: since caching, above guard not needed
		local airFieldSide = theMatchingAirfield:getCoalition()
		local groupCoalition = theGroup.coaNum
		local blockState = cfxSSBClient.enabledFlagValue -- we default to ALLOW the block
		local comment = "available"
			
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
		-- set the ssb flag for this group so the server can see it
		trigger.action.setUserFlag(theName, blockState)
		if cfxSSBClient.verbose then 
			trigger.action.outText("+++SSB: group ".. theName .. ": " .. comment, 30)
		end 
	else 
		if cfxSSBClient.verbose then 
			trigger.action.outText("+++SSB: group ".. theName .. " no bound airfield: available", 30)
		end
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
	local pGroups = cfxSSBClient.playerGroups -- cfxGroups.getPlayerGroup() -- we want the group.name attribute
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
	trigger.action.outText("+++SSBC:SU: re-opened slot for group <" .. gName .. ">", 30)
end

function cfxSSBClient:onEvent(event)
	if event.id == 10 then -- S_EVENT_BASE_CAPTURED
		if cfxSSBClient.verbose then 
			trigger.action.outText("+++SSB: CAPTURE EVENT -- RESETTING SLOTS", 30)
		end
		cfxSSBClient.setSlotAccessByAirfieldOwner()
	end

-- write down player names and planes
	if event.id == 15 then
		--trigger.action.outText("+++SSBC:SU: enter event 15", 30)
		if not event.initiator then return end 
		local theUnit = event.initiator -- we know this exists
		local uName = theUnit:getName()
		if not uName then return end 
		-- player entered unit
		local playerName = theUnit:getPlayerName()
		if not playerName then 
			return -- NPC plane
		end 
		-- remember this unit as player controlled plane
		-- because player and plane can easily disconnect
		cfxSSBClient.playerPlanes[uName] = playerName
		trigger.action.outText("+++SSBC:SU: noted " .. playerName .. " piloting player unit " .. uName, 30)
		return 
	end
	

	if cfxSSBClient.singleUse and event.id == 5 then -- crash
		if not event.initiator then return end 
		local theUnit = event.initiator 
		local uName = theUnit:getName()
		if not uName then return end
		local theGroup = theUnit:getGroup()
		if not theGroup then return end 
		-- see if a player plane
		local thePilot = cfxSSBClient.playerPlanes[uName]
		if not thePilot then 
			-- ignore. not a player plane
			trigger.action.outText("+++SSBC:SU: ignored crash for NPC unit <" .. uName .. ">", 30)
			return 
		end
		-- if we get here, a player-owned plane has crashed 
		local gName = theGroup:getName()
		if not gName then return end 
		
		-- block this slot. 
		trigger.action.setUserFlag(gName, cfxSSBClient.disabledFlagValue)
		
		-- remember this plane to not re-enable if 
		-- airfield changes hands later 
		cfxSSBClient.crashedGroups[gName] = thePilot -- set to crash pilot 
		trigger.action.outText("+++SSBC:SU: Blocked slot for group <" .. gName .. ">", 30)
		
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
end

-- pre-process static player data to minimize 
-- processor load on checks
function cfxSSBClient.processPlayerData()
	cfxSSBClient.playerGroups = cfxGroups.getPlayerGroup()
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
	local pGroups = cfxGroups.getPlayerGroup() -- we want the group.name attribute
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
				trigger.action.outText("+++SSB: group: " .. theGroup.name .. " closest to AF " .. afName .. ": " .. delta .. "m" , 30)
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
	
	-- install a timed update just to make sure
	-- and start NOW
	timer.scheduleFunction(cfxSSBClient.update, {}, timer.getTime() + 1)
	 
	-- now turn on ssb 
	trigger.action.setUserFlag("SSB",100)
	
	-- say hi!
	trigger.action.outText("cfxSSBClient v".. cfxSSBClient.version .. " running, SBB enabled", 30)
	
	--cfxSSBClient.allYourBase()
	
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