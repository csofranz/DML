cfxSSBSingleUse = {}
cfxSSBSingleUse.version = "1.1.0"

--[[--
Version History
	1.0.0 - Initial version
	1.1.0 - importing dcsCommon, cfxGroup for simplicity
	      - save unit name on player enter unit as look-up
		  - determining ground-start
          - place wreck in slot 
	1.1.1 - guarding against nil playerName	  
	      - using 15 (birth) instead of 20 (player enter)
WHAT IT IS
SSB Single Use is a script that blocks a player slot
after that plane crashes. 


--]]--

cfxSSBSingleUse.enabledFlagValue = 0 -- DO NOT CHANGE, MUST MATCH SSB 
cfxSSBSingleUse.disabledFlagValue = cfxSSBSingleUse.enabledFlagValue + 100 -- DO NOT CHANGE


cfxSSBSingleUse.playerUnits = {}
cfxSSBSingleUse.slotGroundActions = {
--	"From Runway", -- NOT RUNWAY, as that would litter runway
	"From Parking Area",
	"From Parking Area Hot",
	"From Ground Area",
	"From Ground Area Hot",
}

cfxSSBSingleUse.groundSlots = {} -- players that start on the ground 

function cfxSSBSingleUse:onEvent(event)
	
	if not event then return end 
	if not event.id then return end 
	if not event.initiator then return end 
	-- if we get here, initiator is set
	local theUnit = event.initiator -- we know this exists
	
	
	-- write down player names and planes
	if event.id == 15 then
		local uName = theUnit:getName()
		if not uName then return end 
		-- player entered unit
		local playerName = theUnit:getPlayerName()
		if not playerName then 
			return -- NPC plane
		end  
		-- remember this unit as player unit
		cfxSSBSingleUse.playerUnits[uName] = playerName
		trigger.action.outText("+++singleUse: noted " .. playerName .. " piloting player unit " .. uName, 30)
		return 
	end

	-- check for a crash
	if event.id == 5 then -- S_EVENT_CRASH
		local uName = theUnit:getName()
		if not uName then return end 
	
		local theGroup = theUnit:getGroup()
		if not theGroup then return end 
		
		-- see if a player plane
		local thePilot = cfxSSBSingleUse.playerUnits[uName]
		
		if not thePilot then 
			-- ignore. not a player plane
			trigger.action.outText("+++singleUse: ignored crash for NPC unit <" .. uName .. ">", 30)
			return 
		end
		
		local gName = theGroup:getName()
		if not gName then return end 
		
		-- see if it was a ground slot 
		local theGroundSlot = cfxSSBSingleUse.groundSlots[gName]
		if theGroundSlot then 
			local unitType = theUnit:getTypeName()
			trigger.action.outText("+++singleUse: <" .. uName .. "> starts on Ground. Will place debris for " .. unitType .. " NOW!!!", 30)
			cfxSSBSingleUse.placeDebris(unitType, theGroundSlot)
		end
		
		-- block this slot. 
		trigger.action.setUserFlag(gName, cfxSSBSingleUse.disabledFlagValue)
		
		trigger.action.outText("+++singleUse: blocked <" .. gName .. "> after " .. thePilot  .. " crashed it.", 30)
	end
end

function cfxSSBSingleUse.placeDebris(unitType, theGroundSlot)
	if not unitType then return end 
	-- access location one, we assume single-unit groups
	-- or at least that the player sits in unit one 
	local playerData = theGroundSlot.playerUnits
	local theSlotData = playerData[1]
	local wreckData = {}
	wreckData.heading = 0
	wreckData.name = dcsCommon.uuid("singleUseWreck"..theSlotData.name)
	wreckData.x = tonumber(theSlotData.point.x) 
	wreckData.y = tonumber(theSlotData.point.z)
	wreckData.dead = true 
	wreckData.type = unitType
	
	coalition.addStaticObject(theGroundSlot.coaNum, wreckData )
	trigger.action.outText("+++singleUse: wreck <" .. unitType .. "> at " .. wreckData.x  .. ", " .. wreckData.y .. " for " .. wreckData.name, 30)
end


function cfxSSBSingleUse.populateAirfieldSlots()
	local pGroups = cfxGroups.getPlayerGroup() 
	local groundStarters = {}
	for idx, theGroup in pairs(pGroups) do
		-- we always use the first player's plane as referenced
		local playerData = theGroup.playerUnits[1]
		local action = playerData.action 
		if not action then action = "<NIL>" end 
		-- see if the data has any of the slot-interesting actions
		if dcsCommon.arrayContainsString(cfxSSBSingleUse.slotGroundActions, action ) then 
			-- ground starter, not from runway
			groundStarters[theGroup.name] = theGroup
			trigger.action.outText("+++singleUse: <" .. theGroup.name .. "> is ground starter", 30)
		end 
	end
	cfxSSBSingleUse.groundSlots = groundStarters
end

function cfxSSBSingleUse.start()
	-- install event monitor 
	world.addEventHandler(cfxSSBSingleUse)
	
	-- get all groups and process them to find 
	-- all planes that are on the ground for 
	-- eye candy 
	cfxSSBSingleUse.populateAirfieldSlots()
	
	-- turn on ssb 
	trigger.action.setUserFlag("SSB",100)
	
	trigger.action.outText("SSB Single use v" .. cfxSSBSingleUse.version .. " running", 30)
end

-- let's go!
cfxSSBSingleUse.start()

--[[--
Additional features (later):
- place a wreck in slot when blocking for eye candy
- record player when they enter a unit and only block player planes

--]]--