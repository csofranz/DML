groupTracker = {}
groupTracker.version = "1.0.0"
groupTracker.verbose = false 
groupTracker.ups = 1 
groupTracker.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
groupTracker.trackers = {}
 
--[[--
	Version History 
	1.0.0 - Initial version 
	
--]]--

function groupTracker.addTracker(theZone)
	table.insert(groupTracker.trackers, theZone)
end

function groupTracker.getTrackerByName(aName) 
	for idx, aZone in pairs(groupTracker.trackers) do 
		if aName == aZone.name then return aZone end 
	end
	if groupTracker.verbose then 
		trigger.action.outText("+++msgr: no tracker with name <" .. aName ..">", 30)
	end 

	return nil 
end

--
-- read attributes 
--

--
-- adding a group to a tracker - called by other modules and API
-- 
function groupTracker.addGroupToTracker(theGroup, theTracker)
	if groupTracker.verbose then 
		trigger.action.outText("+++gTrk: will add group <" .. theGroup:getName() .. "> to tracker " .. theTracker.name, 30)
	end 
	
	-- we have the tracker, add the group 
	if not theTracker.trackedGroups then theTracker.trackedGroups = {} end 
	table.insert(theTracker.trackedGroups, theGroup)

	-- now bang/invoke addGroup!
	if theTracker.tAddGroup then 
		cfxZones.pollFlag(theTracker.tAddGroup, "inc", theTracker)
	end
	
	-- now set numGroups
	if theTracker.tNumGroups then 
		cfxZones.setFlagValue(theTracker.tNumGroups, #theTracker.trackedGroups, theTracker)
	end
	
	-- invoke callbacks
end

function groupTracker.addGroupToTrackerNamed(theGroup, trackerName)
	if not trackerName then 
		trigger.action.outText("+++gTrk: nil tracker in addGroupToTrackerNamed", 30)
	end 
	if not theGroup then 
		trigger.action.outText("+++gTrk: no group in addGroupToTrackerNamed <" .. trackerName .. ">", 30)
		return 
	end
	
	if not theGroup:isExist() then 
		trigger.action.outText("+++gTrk: group does not exist in when adding to tracker <" .. trackerName .. ">", 30)
		return 
	end 
	
	
	groupTracker.addGroupToTracker(theGroup, theTracker)
end

-- read zone 
function groupTracker.createTrackerWithZone(theZone)
	-- init group tracking set 
	theZone.trackedGroups = {}

	if cfxZones.hasProperty(theZone, "numGroups!") then 
		theZone.tNumGroups = cfxZones.getStringFromZoneProperty(theZone, "numGroups!", "<none>") 
		-- we may need to zero this flag 
	end 
	
	if cfxZones.hasProperty(theZone, "addGroup!") then 
		theZone.tAddGroup = cfxZones.getStringFromZoneProperty(theZone, "addGroup!", "<none>") 
		-- we may need to zero this flag 
	end
	
	if cfxZones.hasProperty(theZone, "removeGroup!") then 
		theZone.tRemoveGroup = cfxZones.getStringFromZoneProperty(theZone, "removeGroup!", "<none>") 
		-- we may need to zero this flag 
	end
	
end

--
-- update
--
function groupTracker.checkGroups(theZone)
	local filteredGroups = {}
	for idx, theGroup in pairs(theZone.trackedGroups) do 
		-- see if this group can be transferred
		local isDead = false 
		if theGroup:isExist() then 
			local allUnits = theGroup:getUnits()
			isDead = true 
			for idy, aUnit in pairs(allUnits) do 
				if aUnit:getLife() > 1 then 
					isDead = false -- at least one living unit
					break
				end
			end
		else 
			isDead = true -- no longer exists 
		end
		
		if isDead then 
			-- bang deceased
			if groupTracker.verbose then 
				trigger.action.outText("+++gTrk: dead group detected in " .. theZone.name .. ", discarding.", 30)
			end
			if theZone.tRemoveGroup then 
				cfxZones.pollFlag(theZone.tRemoveGroup, "inc", theZone)
			end
		else
			-- transfer alive group
			table.insert(filteredGroups, theGroup)
		end
		
	end
	-- now exchange filtered for current
	theZone.trackedGroups = filteredGroups
	--set new group value 
	-- now set numGroups if defined
	if theZone.tNumGroups then 
		cfxZones.setFlagValue(theZone.tNumGroups, #filteredGroups, theZone)
	end
end
 
function groupTracker.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(groupTracker.update, {}, timer.getTime() + 1/groupTracker.ups)
		
	for idx, theZone in pairs(groupTracker.trackers) do
		groupTracker.checkGroups(theZone)
	end
end

--
-- Config & Start
--
function groupTracker.trackGroupsInZone(theZone)

	local trackerName = cfxZones.getStringFromZoneProperty(theZone, "addToTracker:", "<none>")
	if trackerName == "*" then trackerName = theZone.name end 
	
	local theTracker = groupTracker.getTrackerByName(trackerName)
	if not theTracker then 
		trigger.action.outText("+++gTrk: trackGroupsInZone - no zone named <" .. trackerName .. ">", 30 )
		return
	end
	
	local theGroups = cfxZones.allGroupsInZone(theZone, nil)
	for idx, aGroup in pairs(theGroups) do 
		if groupTracker.verbose then 
			trigger.action.outText("+++gTrk: <" .. theZone.name .. "> passed off group <" .. aGroup:getName() .. "> to <" .. trackerName .. ">", 30)		
		end
		groupTracker.addGroupToTracker(aGroup, theTracker)
	end
	
end


function groupTracker.readConfigZone()
	local theZone = cfxZones.getZoneByName("groupTrackerConfig") 
	if not theZone then 
		if groupTracker.verbose then 
			trigger.action.outText("+++gTrk: NO config zone!", 30)
		end 
		return 
	end 
	
	groupTracker.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	groupTracker.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 1)
	
	if groupTracker.verbose then 
		trigger.action.outText("+++gTrk: read config", 30)
	end 
end

function groupTracker.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Group Tracker requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Group Tracker", groupTracker.requiredLibs) then
		return false 
	end
	
	-- read config 
	groupTracker.readConfigZone()
	
	-- process tracker Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("tracker")
	for k, aZone in pairs(attrZones) do 
		groupTracker.createTrackerWithZone(aZone) -- process attributes
		groupTracker.addTracker(aZone) -- add to list
	end
	
	-- find and process all zones that want me to immediately add
	-- units to the tracker 
	local attrZones = cfxZones.getZonesWithAttributeNamed("addToTracker:")
	for k, aZone in pairs(attrZones) do 
		groupTracker.trackGroupsInZone(aZone) -- process attributes
	end
	
	-- start update 
	groupTracker.update()
	
	trigger.action.outText("cfx Group Tracker v" .. groupTracker.version .. " started.", 30)
	return true 
end

-- let's go!
if not groupTracker.start() then 
	trigger.action.outText("cfx Group Tracker aborted: missing libraries", 30)
	messenger = nil 
end

--[[--
	add a pass to immediately add units in zones with 'addToTracker' 
	after zone pass 
	
	add an output flag for the total number of units it watches, so when that changes, a change is instigated automatically 
--]]--