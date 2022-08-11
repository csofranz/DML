groupTracker = {}
groupTracker.version = "1.1.4"
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
	1.1.0 - filtering  added 
	      - array support for trackers 
	      - array support for trackers 
	1.1.1 - corrected clone zone reference bug
	1.1.2 - corrected naming (removed bang from flags), deprecated old
		  - more zone-local verbosity
	1.1.3 - spellings
		  - addGroupToTrackerNamed bug removed accessing tracker 
		  - new removeGroupNamedFromTrackerNamed()
	1.1.4 - destroy? input 
		  - allGone! output 
		  - triggerMethod
		  - method 
		  - isDead optimization 
	
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
	-- check if filtering is enabled for this tracker
	if theTracker.groupFilter then 
		cat = theGroup:getCategory()
		if not cat then return end -- strange, but better safe than sorry
		if cat ~= theTracker.groupFilter then 
			if groupTracker.verbose then 
				trigger.action.outText("+++gTrk: Tracker <" .. theTracker.name .. "> rejected <" .. theGroup:getName() .. "> for class mismatch. Expect: " .. theTracker.groupFilter .. " received: " .. cat , 30)
			end
			return 
		end 
	end

	if groupTracker.verbose or theTracker.verbose then 
		trigger.action.outText("+++gTrk: adding group <" .. theGroup:getName() .. "> to tracker " .. theTracker.name, 30)
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
	
	if not Group.isExist(theGroup) then 
		trigger.action.outText("+++gTrk: group does not exist when adding to tracker <" .. trackerName .. ">", 30)
		return 
	end 
	
	local theTracker = groupTracker.getTrackerByName(trackerName)
	if not theTracker then return end 
	
	groupTracker.addGroupToTracker(theGroup, theTracker)
end

function groupTracker.removeGroupNamedFromTrackerNamed(gName, trackerName)
	local theTracker = groupTracker.getTrackerByName(trackerName)
	if not theTracker then return end 
	if not gName then 
		trigger.action.outText("+++gTrk: <nil> group name in removeGroupNameFromTrackerNamed <" .. trackerName .. ">", 30)
		return 
	end 
	
	local filteredGroups = {}
	local foundOne = false 
	for idx, aGroup in pairs(theTracker.trackedGroups) do 
		if aGroup:getName() == gName then 
			-- skip and remember 
			foundOne = true 
		else 
			table.insert(filteredGroups, aGroup)
		end
	end
	if (not foundOne) and (theTracker.verbose or groupTracker.verbose) then 
		trigger.action.outText("+++gTrk: Removal Request Note: group <" .. gName .. "> wasn't tracked by <" .. trackerName .. ">", 30)
	end 
	
	-- remember the new, cleanded set
	theTracker.trackedGroups = filteredGroups
	
	
	if foundOne then 
		if theTracker.verbose or groupTracker.verbose then 
			trigger.action.outText("+++gTrk: removed group <" .. gName .. "> from tracker <" .. trackerName .. ">", 30)
		end 
		
		-- now bang/invoke addGroup!
		if theTracker.tRemoveGroup then 
			cfxZones.pollFlag(theTracker.tRemoveGroup, "inc", theTracker)
		end
	
		-- now set numGroups
		if theTracker.tNumGroups then 
			cfxZones.setFlagValue(theTracker.tNumGroups, #theTracker.trackedGroups, theTracker)
		end
	end 
end

-- read zone 
function groupTracker.createTrackerWithZone(theZone)
	-- init group tracking set 
	theZone.trackedGroups = {}


	theZone.trackerMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "trackerMethod") then 
		theZone.trackerMethod = cfxZones.getStringFromZoneProperty(theZone, "trackerMethod", "inc")
	end

	theZone.trackerTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")

	if cfxZones.hasProperty(theZone, "trackerTriggerMethod") then 
		theZone.trackerTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "trackerTriggerMethod", "change")
	end

	if cfxZones.hasProperty(theZone, "numGroups") then 
		theZone.tNumGroups = cfxZones.getStringFromZoneProperty(theZone, "numGroups", "*<none>") 
		-- we may need to zero this flag 
	elseif  cfxZones.hasProperty(theZone, "numGroups!") then -- DEPRECATED!
		theZone.tNumGroups = cfxZones.getStringFromZoneProperty(theZone, "numGroups!", "*<none>") 
		-- we may need to zero this flag 
	end 
		
	if cfxZones.hasProperty(theZone, "addGroup") then 
		theZone.tAddGroup = cfxZones.getStringFromZoneProperty(theZone, "addGroup", "*<none>") 
		-- we may need to zero this flag 
	elseif cfxZones.hasProperty(theZone, "addGroup!") then -- DEPRECATED
		theZone.tAddGroup = cfxZones.getStringFromZoneProperty(theZone, "addGroup!", "*<none>") 
		-- we may need to zero this flag 
	end
		
	if cfxZones.hasProperty(theZone, "removeGroup") then 
		theZone.tRemoveGroup = cfxZones.getStringFromZoneProperty(theZone, "removeGroup", "*<none>") 
		-- we may need to zero this flag 
	elseif cfxZones.hasProperty(theZone, "removeGroup!") then -- DEPRECATED!
		theZone.tRemoveGroup = cfxZones.getStringFromZoneProperty(theZone, "removeGroup!", "*<none>") 
		-- we may need to zero this flag 
	end
	
	
	
	if cfxZones.hasProperty(theZone, "groupFilter") then 
		local filterString = cfxZones.getStringFromZoneProperty(theZone, "groupFilter", "2") -- ground 
		theZone.groupFilter = dcsCommon.string2GroupCat(filterString)
		if groupTracker.verbose or theZone.verbose then 
			trigger.action.outText("+++gTrck: filtering " .. theZone.groupFilter .. " in " .. theZone.name, 30)
		end 
	end	
	
	if cfxZones.hasProperty(theZone, "destroy?") then 
		theZone.destroyFlag = cfxZones.getStringFromZoneProperty(theZone, "destroy?", "*<none>")
		theZone.lastDestroyValue = cfxZones.getFlagValue(theZone.destroyFlag, theZone)
	end
	
	if cfxZones.hasProperty(theZone, "allGone!") then 
		theZone.allGoneFlag = cfxZones.getStringFromZoneProperty(theZone, "allGone!", "<None>") -- note string on number default
	end
	theZone.lastGroupCount = 0 
	
	if theZone.verbose or groupTracker.verbose then 
		trigger.action.outText("gTrck: processed <" .. theZone.name .. ">", 30)
	end 
end

--
-- update
--
function groupTracker.destroyAllInZone(theZone) 
	for idx, theGroup in pairs(theZone.trackedGroups) do 
		if Group.isExist(theGroup) then 
			theGroup:destroy()
		end
	end
	-- we keep all groups in trackedGroups so we 
	-- generate a host of destroy events when we run through 
	-- checkGroups next 
end

function groupTracker.checkGroups(theZone)
	local filteredGroups = {}
	for idx, theGroup in pairs(theZone.trackedGroups) do 
		-- see if this group can be transferred
		local isDead = false 
--[[		if theGroup.isExist and theGroup:isExist() then 
			local allUnits = theGroup:getUnits()
			isDead = true 
			for idy, aUnit in pairs(allUnits) do 
				if aUnit:getLife() > 1 then 
					isDead = false -- at least one living unit
					break
				end
			end
--]]--
		if Group.isExist(theGroup) and theGroup:getSize() > 0 then
		else 
			isDead = true -- no longer exists 
		end
		
		if isDead then 
			-- bang deceased
			if groupTracker.verbose or theZone.verbose then 
				trigger.action.outText("+++gTrk: dead group detected in " .. theZone.name .. ", removing.", 30)
			end
			if theZone.tRemoveGroup then 
				cfxZones.pollFlag(theZone.tRemoveGroup, "inc", theZone)
				if theZone.verbose then 
					trigger.action.outText("+++gTrk: <" .. theZone.name .. "> incrementing remove flag <" .. theZone.tRemoveGroup .. ">", 30)
				end
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
		
		if theZone.destroyFlag and cfxZones.testZoneFlag(theZone, theZone.destroyFlag, theZone.trackerTriggerMethod, "lastDestroyValue") then 
			groupTracker.destroyAllInZone(theZone)
			if groupTracker.verbose or theZone.verbose then 
				trigger.action.outText("+++gTrk: destroying all groups tracked with <" .. theZone.name .. ">", 30)
			end 
		end
		
		groupTracker.checkGroups(theZone)
		
		-- see if we need to bang on empty!
		local currCount = #theZone.trackedGroups
		if theZone.allGoneFlag and currCount == 0 and currCount ~= theZone.lastGroupCount then 
			cfxZones.pollFlag(aZone.allGoneFlag, aZone.trackerMethod, aZone)
		end 
		theZone.lastGroupCount = currCount
	end
end

--
-- Config & Start
--
function groupTracker.trackGroupsInZone(theZone)

	local trackerName = cfxZones.getStringFromZoneProperty(theZone, "addToTracker:", "<none>")
	
	local theGroups = cfxZones.allGroupsInZone(theZone, nil)
	
	-- now init array processing
	local trackerNames = {}
	if dcsCommon.containsString(trackerName, ',') then
		trackerNames = dcsCommon.splitString(trackerName, ',')
	else 
		table.insert(trackerNames, trackerName)
	end
	
	for idx, aTrk in pairs(trackerNames) do 
		local theName = dcsCommon.trim(aTrk)
		if theName == "*" then theName = theZone.name end 
		local theTracker = groupTracker.getTrackerByName(theName)
		if not theTracker then 
			trigger.action.outText("+++gTrk-TW: <" .. theZone.name .. ">: cannot find tracker named <".. theName .. ">", 30) 
		else 
			for idy, aGroup in pairs(theGroups) do
				groupTracker.addGroupToTracker(aGroup, theTracker)
				if groupTracker.verbose or theZone.verbose then 
					trigger.action.outText("+++gTrk-TW: added " .. theGroup:getName() .. " to tracker " .. theName, 30)
				end
			end
		end 
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
	-- units to the tracker. Must run AFTER we have gathered all trackers
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

