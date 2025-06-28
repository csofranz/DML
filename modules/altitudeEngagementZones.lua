altitudeEngagementZones = {}
altitudeEngagementZones.version = "1.0.0"
altitudeEngagementZones.verbose = false 
altitudeEngagementZones.ups = 1 -- updates per second
altitudeEngagementZones.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"cfxCommander", -- for setting group options
}

--[[--
	Version History 
	1.0.0 - Initial version - controls AAA/SAM engagement based on aircraft altitude
	
	This module controls AAA/SAM units to only engage aircraft when they are 
	above a minimum altitude (default 100m AGL) and inside specific zones. AA groups 
	are discovered by matching a pattern (default "AA_Group") and checking if they are 
	physically located inside the engagement zones. When no valid targets are present, 
	AA units are automatically set to weapons hold.
	
	The module supports both scenarios:
	- Red AA engaging blue aircraft (targetCoalition = 2, default)
	- Blue AA engaging red aircraft (targetCoalition = 1)
	
	Zone Properties:
	- minAltitude: Minimum altitude for engagement (default 100m AGL)
	- targetCoalition: Target coalition (1=red, 2=blue, default 2)
	- aaGroupPattern: Pattern to match AA group names (default "AA_Group")
	- missileWarning: Enable missile launch warnings (default false)
	- active?: Zone active state (static boolean or flag name, default true)
	
	Zone State Properties (updated each cycle):
	- validTargets: Array of valid targets above minimum altitude
	- invalidTargets: Array of invalid targets below minimum altitude
	- isActive: Current active state of the zone
	
	Helper Functions:
	- hasValidTargets(zone): Check if zone has valid targets
	- getValidTargetCount(zone): Get number of valid targets
	- getInvalidTargetCount(zone): Get number of invalid targets
	- getValidTargets(zone): Get array of valid targets
	- getInvalidTargets(zone): Get array of invalid targets
	- isEngaging(zone): Check if AA is currently engaging
	
	Target Object Structure:
	- name: Unit name
	- unit: Unit object reference
	- agl: Altitude above ground level in meters
--]]--

altitudeEngagementZones.zones = {} -- all altitude engagement zones
altitudeEngagementZones.aaGroups = {} -- track AA groups for missile detection

function altitudeEngagementZones.addZone(theZone)
	-- Minimum altitude for engagement (default 100m AGL)
	theZone.minAltitude = theZone:getNumberFromZoneProperty("minAltitude", 100)
	
	-- Target coalition (default blue = 2, red = 1)
	-- If targetCoalition is blue (2), red AA will engage blue aircraft
	-- If targetCoalition is red (1), blue AA will engage red aircraft
	theZone.targetCoalition = theZone:getNumberFromZoneProperty("targetCoalition", 2)
	
	-- Calculate AA coalition once at zone creation (static value)
	-- AA coalition is always the opposite of target coalition
	theZone.aaCoalition = (theZone.targetCoalition == 2) and 1 or 2
	
	-- Calculate coalition names once at zone creation (static values)
	theZone.targetCoalitionName = (theZone.targetCoalition == 2) and "BLUE" or "RED"
	theZone.aaCoalitionName = (theZone.aaCoalition == 1) and "RED" or "BLUE"
	
	-- AA Group pattern (default "AA_Group")
	theZone.aaGroupPattern = theZone:getStringFromZoneProperty("aaGroupPattern", "AA_Group")
	
	-- Missile warning flag (default false)
	theZone.missileWarning = theZone:getBoolFromZoneProperty("missileWarning", false)
	
	-- Zone active control - can be a static value or a flag name
	if theZone:hasProperty("active?") then
		theZone.activeFlag = theZone:getStringFromZoneProperty("active?", "")
		if theZone.activeFlag and theZone.activeFlag ~= "" then
			-- It's a flag name, get initial value
			theZone.isActive = (cfxZones.getFlagValue(theZone.activeFlag, theZone) > 0)
		else
			-- It's a static boolean value
			theZone.isActive = theZone:getBoolFromZoneProperty("active?", true)
		end
	else
		-- No active property specified, default to true
		theZone.isActive = true
	end
	
	if altitudeEngagementZones.verbose or theZone.verbose then 
		local activeInfo = theZone.activeFlag and theZone.activeFlag ~= "" and ("flag: " .. theZone.activeFlag) or ("static: " .. tostring(theZone.isActive))
		trigger.action.outText("+++altitudeEngagementZones: new zone <".. theZone.name .."> - min alt: " .. theZone.minAltitude .. "m, target coalition: " .. theZone.targetCoalition .. " (" .. theZone.targetCoalitionName .. "), AA coalition: " .. theZone.aaCoalition .. " (" .. theZone.aaCoalitionName .. "), AA pattern: " .. theZone.aaGroupPattern .. ", missile warning: " .. tostring(theZone.missileWarning) .. ", active: " .. activeInfo, 5)
	end
	
end

function altitudeEngagementZones.getAAGroupsInZone(theZone)
	-- Get AA groups from the opposite coalition of the target (using static value)
	local aaGroups = {}
	local coalitionGroups = coalition.getGroups(theZone.aaCoalition)
	
	for idx, theGroup in pairs(coalitionGroups) do
		if Group.isExist(theGroup) then
			local groupName = theGroup:getName()
			
			-- Check if the group matches the AA pattern
			if string.find(groupName, "^" .. theZone.aaGroupPattern) then
				local units = theGroup:getUnits()
				local groupInZone = false
				
				-- Check if any unit in the group is inside the zone
				for unitIdx, theUnit in pairs(units) do
					if Unit.isExist(theUnit) then
						local unitPos = theUnit:getPoint()
						if theZone:pointInZone(unitPos) then
							groupInZone = true
							break
						end
					end
				end
				
				-- If group matches pattern AND is in zone, add it to AA groups
				if groupInZone then
					aaGroups[groupName] = theGroup
					if altitudeEngagementZones.verbose or theZone.verbose then
						trigger.action.outText("+++altitudeEngagementZones: Found AA group '" .. groupName .. "' in zone <" .. theZone.name .. ">", 2)
					end
				end
			end
		end
	end
	
	return aaGroups
end

function altitudeEngagementZones.getTargetAircraftInZone(theZone)
	-- Get all aircraft from the target coalition in the target zone
	local targetAircraft = {}
	local targetGroups = coalition.getGroups(theZone.targetCoalition)
	
	for idx, theGroup in pairs(targetGroups) do
		if Group.isExist(theGroup) then
			local cat = theGroup:getCategory()
			-- Check if it's an aircraft (airplane = 0, helicopter = 1)
			if cat == 0 or cat == 1 then
				local units = theGroup:getUnits()
				for unitIdx, theUnit in pairs(units) do
					if Unit.isExist(theUnit) and theUnit:inAir() then
						local unitPos = theUnit:getPoint()
						if theZone:pointInZone(unitPos) then
							targetAircraft[theUnit:getName()] = theUnit
							if altitudeEngagementZones.verbose or theZone.verbose then
								trigger.action.outText("+++altitudeEngagementZones: Found " .. theZone.targetCoalitionName .. " aircraft '" .. theUnit:getName() .. "' in zone <" .. theZone.name .. ">", 2)
							end
						end
					end
				end
			end
		end
	end
	
	return targetAircraft
end

function altitudeEngagementZones.checkEngagementConditions(theZone)
	-- Skip processing if zone is paused
	if not theZone.isActive then
		-- Even when paused, ensure AA groups are set to weapons hold
		local aaGroups = altitudeEngagementZones.getAAGroupsInZone(theZone)
		altitudeEngagementZones.setAAEngagement(aaGroups, false)
		-- Clear target lists when zone is inactive
		theZone.validTargets = {}
		theZone.invalidTargets = {}
		return
	end
	
	-- Get all AA groups using the zone's pattern
	local aaGroups = altitudeEngagementZones.getAAGroupsInZone(theZone)
	
	-- Get all target aircraft in the zone
	local targetAircraft = altitudeEngagementZones.getTargetAircraftInZone(theZone)

	-- Initialize target lists as zone properties
	theZone.validTargets = {}
	theZone.invalidTargets = {}
	
	-- Check each target aircraft's altitude and categorize them
	for unitName, theUnit in pairs(targetAircraft) do
		if Unit.isExist(theUnit) then
			local agl = dcsCommon.getUnitAGL(theUnit)
			
			if agl >= theZone.minAltitude then
				-- Aircraft is above minimum altitude - valid target
				table.insert(theZone.validTargets, {name = unitName, unit = theUnit, agl = agl})
				if altitudeEngagementZones.verbose or theZone.verbose then
					trigger.action.outText("+++altitudeEngagementZones: Valid target '" .. unitName .. "' (" .. theZone.targetCoalitionName .. ") at AGL " .. agl .. "m in zone <" .. theZone.name .. ">", 2)
				end
			else
				-- Aircraft is below minimum altitude - invalid target
				table.insert(theZone.invalidTargets, {name = unitName, unit = theUnit, agl = agl})
				if altitudeEngagementZones.verbose or theZone.verbose then
					trigger.action.outText("+++altitudeEngagementZones: Invalid target '" .. unitName .. "' (" .. theZone.targetCoalitionName .. ") at AGL " .. agl .. "m (below " .. theZone.minAltitude .. "m) in zone <" .. theZone.name .. ">", 2)
				end
			end
		end
	end

	-- Set AA engagement based on whether ANY valid targets exist
	if #theZone.validTargets > 0 then
		-- At least one valid target exists - allow engagement
		altitudeEngagementZones.setAAEngagement(aaGroups, true)
		if altitudeEngagementZones.verbose or theZone.verbose then
			local targetList = ""
			for i, target in ipairs(theZone.validTargets) do
				if i > 1 then targetList = targetList .. ", " end
				targetList = targetList .. target.name .. "(" .. target.agl .. "m)"
			end
			trigger.action.outText("+++altitudeEngagementZones: AA engaging " .. #theZone.validTargets .. " valid target(s) in zone <" .. theZone.name .. ">: " .. targetList, 2)
		end
	else
		-- No valid targets - set to weapons hold
		altitudeEngagementZones.setAAEngagement(aaGroups, false)
		if altitudeEngagementZones.verbose or theZone.verbose then
			if #theZone.invalidTargets > 0 then
				local targetList = ""
				for i, target in ipairs(theZone.invalidTargets) do
					if i > 1 then targetList = targetList .. ", " end
					targetList = targetList .. target.name .. "(" .. target.agl .. "m)"
				end
				trigger.action.outText("+++altitudeEngagementZones: AA NOT engaging " .. #theZone.invalidTargets .. " invalid target(s) in zone <" .. theZone.name .. ">: " .. targetList, 2)
			else
				trigger.action.outText("+++altitudeEngagementZones: No targets in zone <" .. theZone.name .. ">, AA set to weapons hold", 2)
			end
		end
	end
end

function altitudeEngagementZones.setAAEngagement(aaGroups, allowEngagement)
	-- Set engagement rules for all AA groups
	for groupName, theGroup in pairs(aaGroups) do
		if Group.isExist(theGroup) then
			if allowEngagement then
				-- Set to weapons free (0)
				cfxCommander.scheduleOptionForGroup(theGroup, 0, 0) -- ROE = 0 = weapons free
			else
				-- Set to weapons hold (4)
				cfxCommander.scheduleOptionForGroup(theGroup, 0, 4) -- ROE = 4 = weapons hold
			end
		end
	end
end

-- Helper functions to check engagement conditions
function altitudeEngagementZones.hasValidTargets(theZone)
	-- Check if the zone has any valid targets for engagement
	return theZone.validTargets and #theZone.validTargets > 0
end

function altitudeEngagementZones.getValidTargetCount(theZone)
	-- Get the number of valid targets in the zone
	return theZone.validTargets and #theZone.validTargets or 0
end

function altitudeEngagementZones.getInvalidTargetCount(theZone)
	-- Get the number of invalid targets in the zone
	return theZone.invalidTargets and #theZone.invalidTargets or 0
end

function altitudeEngagementZones.getValidTargets(theZone)
	-- Get the list of valid targets in the zone
	return theZone.validTargets or {}
end

function altitudeEngagementZones.getInvalidTargets(theZone)
	-- Get the list of invalid targets in the zone
	return theZone.invalidTargets or {}
end

function altitudeEngagementZones.isEngaging(theZone)
	-- Check if AA units in this zone are currently engaging targets
	return altitudeEngagementZones.hasValidTargets(theZone) and theZone.isActive
end

-- Event handler for missile launches
function altitudeEngagementZones:onEvent(event)
	if not event then return end
	
	-- Check if this is a shot event (missile launch)
	if event.id == 1 then -- S_EVENT_SHOT
		local theUnit = event.initiator
		if not theUnit then return end
		
		-- Check if the shooter is one of our AA groups
		local theGroup = theUnit:getGroup()
		if not theGroup then return end
		
		local groupName = theGroup:getName()
		if not groupName then return end
		
		-- Check if this group is inside any of our zones and matches the AA pattern
		for zoneName, theZone in pairs(altitudeEngagementZones.zones) do
			-- Only process missile warnings for active (non-paused) zones
			if theZone.isActive and theZone.missileWarning then
				-- Check if the group matches the AA pattern
				if string.find(groupName, "^" .. theZone.aaGroupPattern) then
					-- Check if the shooting unit is inside this zone
					local unitPos = theUnit:getPoint()
					if theZone:pointInZone(unitPos) then
						-- Send simple warning to target coalition
						trigger.action.outTextForCoalition(theZone.targetCoalition, "MISSILE LAUNCH! MISSILE LAUNCH!", 5)
						
						if altitudeEngagementZones.verbose or theZone.verbose then
							trigger.action.outText("+++altitudeEngagementZones: Missile warning sent for " .. groupName .. " in zone <" .. theZone.name .. ">", 2)
						end
						break
					end
				end
			end
		end
	end
end

--
-- MAIN ACTION
--
function altitudeEngagementZones.process(theZone)
	altitudeEngagementZones.checkEngagementConditions(theZone)
end

--
-- Update 
--
function altitudeEngagementZones.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(altitudeEngagementZones.update, {}, timer.getTime() + 1/altitudeEngagementZones.ups)
		
	for idx, aZone in pairs(altitudeEngagementZones.zones) do
		-- check if active flag has changed
		if aZone.activeFlag and aZone.activeFlag ~= "" then
			local currentValue = cfxZones.getFlagValue(aZone.activeFlag, aZone)
			local wasActive = aZone.isActive
			aZone.isActive = (currentValue > 0)
			
			if wasActive ~= aZone.isActive then
				if altitudeEngagementZones.verbose or aZone.verbose then 
					if aZone.isActive then
						trigger.action.outText("+++altitudeEngagementZones: turning " .. aZone.name .. " ON (flag value: " .. currentValue .. ")", 2)
					else
						trigger.action.outText("+++altitudeEngagementZones: turning " .. aZone.name .. " OFF (flag value: " .. currentValue .. ")", 2)
					end
				end
			end
		end
		
		-- Always check engagement conditions for active zones
		altitudeEngagementZones.checkEngagementConditions(aZone)
	end
end

function altitudeEngagementZones.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("altitudeEngagementZones requires dcsCommon", 10)
		return false 
	end 
	if not dcsCommon.libCheck("altitudeEngagementZones", altitudeEngagementZones.requiredLibs) then
		return false 
	end
	
	-- process altitudeEngagementZones Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("altitudeEngagementZones")
	for k, aZone in pairs(attrZones) do 
		altitudeEngagementZones.addZone(aZone) -- process attributes
		table.insert(altitudeEngagementZones.zones, aZone) -- add to list
		
		-- Check if any zone has verbose enabled to set global verbose
		if aZone.verbose then
			altitudeEngagementZones.verbose = true
		end
	end
	
	-- Initialize all AA groups to weapons hold
	if altitudeEngagementZones.verbose then
		trigger.action.outText("+++altitudeEngagementZones: Initializing all AA groups to WEAPONS HOLD", 10)
	end
	
	-- Set all AA groups in all zones to weapons hold initially
	for idx, aZone in pairs(altitudeEngagementZones.zones) do
		local aaGroups = altitudeEngagementZones.getAAGroupsInZone(aZone)
		altitudeEngagementZones.setAAEngagement(aaGroups, false)
	end
	
	-- Register event handler for missile launches
	world.addEventHandler(altitudeEngagementZones)
	
	-- start update 
	altitudeEngagementZones.update()
	
	trigger.action.outText("altitudeEngagementZones v" .. altitudeEngagementZones.version .. " started.", 10)
	return true 
end

-- let's go!
if not altitudeEngagementZones.start() then 
	trigger.action.outText("altitudeEngagementZones aborted: missing libraries", 10)
	altitudeEngagementZones = nil 
end 