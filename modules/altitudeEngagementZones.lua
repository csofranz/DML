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
	1.0.0 - Initial version - controls red AAA/SAM engagement based on blue aircraft altitude
	
	This module controls red AAA/SAM units to only engage blue aircraft when they are 
	above a minimum altitude (default 100m AGL) and inside specific zones. AA groups 
	are discovered by matching a pattern (default "AA_Group") and checking if they are 
	physically located inside the engagement zones. When no valid targets are present, 
	AA units are automatically set to weapons hold.
--]]--

altitudeEngagementZones.zones = {} -- all altitude engagement zones
altitudeEngagementZones.aaGroups = {} -- track AA groups for missile detection

function altitudeEngagementZones.addZone(theZone)
	-- Minimum altitude for engagement (default 100m AGL)
	theZone.minAltitude = theZone:getNumberFromZoneProperty("minAltitude", 100)
	
	-- Target coalition (default blue = 2)
	theZone.targetCoalition = theZone:getNumberFromZoneProperty("targetCoalition", 2)
	
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
		trigger.action.outText("+++altitudeEngagementZones: new zone <".. theZone.name .."> - min alt: " .. theZone.minAltitude .. "m, target coalition: " .. theZone.targetCoalition .. ", AA pattern: " .. theZone.aaGroupPattern .. ", missile warning: " .. tostring(theZone.missileWarning) .. ", active: " .. activeInfo, 5)
	end
	
end

function altitudeEngagementZones.getAAGroupsInZone(theZone)
	-- Get all red coalition groups that match the AA pattern AND are inside the zone
	local aaGroups = {}
	local redGroups = coalition.getGroups(1) -- red coalition
	
	for idx, theGroup in pairs(redGroups) do
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

function altitudeEngagementZones.getBlueAircraftInZone(theZone)
	-- Get all blue aircraft in the target zone
	local blueAircraft = {}
	local blueGroups = coalition.getGroups(theZone.targetCoalition)
	
	for idx, theGroup in pairs(blueGroups) do
		if Group.isExist(theGroup) then
			local cat = theGroup:getCategory()
			-- Check if it's an aircraft (airplane = 0, helicopter = 1)
			if cat == 0 or cat == 1 then
				local units = theGroup:getUnits()
				for unitIdx, theUnit in pairs(units) do
					if Unit.isExist(theUnit) and theUnit:inAir() then
						local unitPos = theUnit:getPoint()
						if theZone:pointInZone(unitPos) then
							blueAircraft[theUnit:getName()] = theUnit
							if altitudeEngagementZones.verbose or theZone.verbose then
								trigger.action.outText("+++altitudeEngagementZones: Found blue aircraft '" .. theUnit:getName() .. "' in zone <" .. theZone.name .. ">", 2)
							end
						end
					end
				end
			end
		end
	end
	
	return blueAircraft
end

function altitudeEngagementZones.checkEngagementConditions(theZone)
	-- Skip processing if zone is paused
	if not theZone.isActive then
		-- Even when paused, ensure AA groups are set to weapons hold
		local aaGroups = altitudeEngagementZones.getAAGroupsInZone(theZone)
		altitudeEngagementZones.setAAEngagement(aaGroups, false)
		return
	end
	
	-- Get all AA groups using the zone's pattern
	local aaGroups = altitudeEngagementZones.getAAGroupsInZone(theZone)
	
	-- Get all blue aircraft in the zone
	local blueAircraft = altitudeEngagementZones.getBlueAircraftInZone(theZone)

	local foundValidTarget = false
	-- Check each blue aircraft's altitude
	for unitName, theUnit in pairs(blueAircraft) do
		if Unit.isExist(theUnit) then
			local agl = dcsCommon.getUnitAGL(theUnit)
			
			if agl >= theZone.minAltitude then
				-- Aircraft is above minimum altitude - allow engagement
				altitudeEngagementZones.setAAEngagement(aaGroups, true, unitName, agl)
				if altitudeEngagementZones.verbose or theZone.verbose then
					trigger.action.outText("+++altitudeEngagementZones: AA engaging '" .. unitName .. "' at AGL " .. agl .. "m in zone <" .. theZone.name .. ">", 10)
				end
				foundValidTarget = true
			else
				-- Aircraft is below minimum altitude - prevent engagement
				altitudeEngagementZones.setAAEngagement(aaGroups, false, unitName, agl)
				if altitudeEngagementZones.verbose or theZone.verbose then
					trigger.action.outText("+++altitudeEngagementZones: AA NOT engaging '" .. unitName .. "' at AGL " .. agl .. "m (below " .. theZone.minAltitude .. "m) in zone <" .. theZone.name .. ">", 10)
				end
			end
		end
	end

	-- ALWAYS ensure AA groups are set to weapons hold if no valid targets found
	if not foundValidTarget then
		altitudeEngagementZones.setAAEngagement(aaGroups, false)
		if altitudeEngagementZones.verbose or theZone.verbose then
			trigger.action.outText("+++altitudeEngagementZones: No valid targets in zone <" .. theZone.name .. ">, AA set to weapons hold", 10)
		end
	end
end

function altitudeEngagementZones.setAAEngagement(aaGroups, allowEngagement, targetName, agl)
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