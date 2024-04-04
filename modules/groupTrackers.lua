groupTracker = {}
groupTracker.version = "2.0.1"
groupTracker.verbose = false 
groupTracker.ups = 1 
groupTracker.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
groupTracker.trackers = {}
 
--[[--
	Version History 
	2.0.0 - dmlZones, OOP, clean-up, legacy support
	2.0.1 - fix to verbosity, better verbosity 
	
--]]--

-- 'limbo'
-- is a special storage in tracker indexed by name that is used
-- to temporarily suspend a groups tracking while it's not in 
-- the mission, e.g. because it's being transported by heloTroops
-- in limbo, only the number of units is preserved
-- addGroup will automatically move a group back from limbo 
-- to move into limbo, you must use moveGroupToLimboForTracker
-- to remove a group in limbo, use removeGroupNamedFromTracker
--

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
-- addGroupToTracker will automatically also move a group from 
-- limbo to tracker if it already existed in limbo 
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

	local exists = false 
	local theName = theGroup:getName()
	
	for idx, aGroup in pairs(theTracker.trackedGroups) do 
		if Group.isExist(aGroup) then 
			gName = aGroup:getName()
			if gName == theName then exists = true end 
		end
	end
		
	
	if not exists then 
		table.insert(theTracker.trackedGroups, theGroup) 
		
		-- see if we merely transfer group back from limbo 
		-- to tracked
		if theTracker.limbo[theName] then 
			-- group of that name is in limbo
			if theTracker.verbose then 
				trigger.action.outText("+++gTrk: moving shelved group <" .. theName .. "> back to normal tracking for <" .. theTracker.name .. ">", 30)
			end
			theTracker.limbo[theName] = nil -- remove from limbo
		else 
			-- now bang/invoke addGroup!
			if theTracker.tAddGroup then 
				cfxZones.pollFlag(theTracker.tAddGroup, "inc", theTracker)
			end
		end
	end
	
	-- now set numGroups
	if theTracker.tNumGroups then 
		cfxZones.setFlagValue(theTracker.tNumGroups, dcsCommon.getSizeOfTable(theTracker.limbo) + #theTracker.trackedGroups, theTracker)
	end
	
	-- count all units
	local totalUnits = 0 	
	for idx, aGroup in pairs(theTracker.trackedGroups) do 
		if Group.isExist(aGroup) then 
			totalUnits = totalUnits + aGroup:getSize()
		end
	end
	for idx, limboNum in pairs(theTracker.limbo) do 
		totalUnits = totalUnits + limboNum
	end 
	
	-- update unit count 
	if theTracker.tNumUnits then 
		cfxZones.setFlagValue(theTracker.tNumUnits, totalUnits, theTracker)
	end
	-- invoke callbacks
end


function groupTracker.addGroupToTrackerNamed(theGroup, trackerName)
	if not trackerName then 
		trigger.action.outText("+++gTrk: nil tracker in addGroupToTrackerNamed", 30)
		return 
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

function groupTracker.moveGroupToLimboForTracker(theGroup, theTracker)
	if not theGroup then return end 
	if not theTracker then return end 
	if not Group.isExist(theGroup) then return end 
	
	local gName = theGroup:getName()
	local filtered = {}
	if theTracker.trackedGroups then 
		for idx, aGroup in pairs(theTracker.trackedGroups) do 
			if Group.isExist(aGroup) and aGroup:getName() == gName then 
				-- move this to limbo 
				theTracker.limbo[gName] = aGroup:getSize()
				if theTracker.verbose then 
					trigger.action.outText("+++gTrk: moved group <" .. gName .. "> to limbo for <" .. theTracker.name .. ">", 30)
				end
				-- filtered 
			else 
				table.insert(filtered, aGroup)
			end
		end
		theTracker.trackedGroups = filtered
	end
end

function groupTracker.removeGroupNamedFromTracker(gName, theTracker)
	if not gName then return end 
	if not theTracker then return end 
	
	local filteredGroups = {}
	local foundOne = false 
	local totalUnits = 0
	if not theTracker.trackedGroups then theTracker.trackedGroups = {} end 
	for idx, aGroup in pairs(theTracker.trackedGroups) do 
		if Group.isExist(aGroup) and aGroup:getName() == gName then 
			-- skip and remember 
			foundOne = true 
		else 
			table.insert(filteredGroups, aGroup)
			if Group.isExist(aGroup) then 
				totalUnits = totalUnits + aGroup:getSize()
			end
		end
	end
	-- also check limbo 
	for limboName, limboNum in pairs (theTracker.limbo) do 
		if gName == limboName then 
			-- don't count, but remember that it existed
			foundOne = true 
			if theTracker.verbose then 
				trigger.action.outText("+++gTrk: removed group <" .. gName .. "> from limbo for <" .. theTracker.name .. ">", 30)
			end
		else 
			totalUnits = totalUnits + limboNum
		end		
	end 
	-- remove from limbo 
	theTracker.limbo[gName] = nil 
	
	if (not foundOne) and (theTracker.verbose or groupTracker.verbose) then 
		trigger.action.outText("+++gTrk: Removal Request Note: group <" .. gName .. "> wasn't tracked by <" .. theTracker.name .. ">", 30)
	end 
	
	-- remember the new, cleanded set
	theTracker.trackedGroups = filteredGroups
	
	-- update number of tracked units. do it in any case 
	if theTracker.tNumUnits then 
		cfxZones.setFlagValue(theTracker.tNumUnits, totalUnits, theTracker)
	end
	
	if foundOne then 
		if theTracker.verbose or groupTracker.verbose then 
			trigger.action.outText("+++gTrk: removed group <" .. gName .. "> from tracker <" .. theTracker.name .. ">", 30)
		end 
		
		-- now bang/invoke removeGroup!
		if theTracker.tRemoveGroup then 
			cfxZones.pollFlag(theTracker.tRemoveGroup, "inc", theTracker)
		end
	
		-- now set numGroups
		if theTracker.tNumGroups then 
			cfxZones.setFlagValue(theTracker.tNumGroups, dcsCommon.getSizeOfTable(theTracker.limbo) + #theTracker.trackedGroups, theTracker)
		end
	end 
end

function groupTracker.removeGroupNamedFromTrackerNamed(gName, trackerName)
	local theTracker = groupTracker.getTrackerByName(trackerName)
	if not theTracker then return end 
	if not gName then 
		trigger.action.outText("+++gTrk: <nil> group name in removeGroupNameFromTrackerNamed <" .. trackerName .. ">", 30)
		return 
	end 
	
	groupTracker.removeGroupNamedFromTracker(gName, theTracker)

end

-- groupTrackedBy - return trackers that track group theGroup  
-- returns 3 values: true/false (is tracking), number of trackers, array of trackers 
function groupTracker.groupNameTrackedBy(theName) 
	local isTracking = false 
	
	-- now iterate all trackers 
	local tracking = {}
	for idx, aTracker in pairs(groupTracker.trackers) do 
		-- only look at tracked groups if that tracker has an 
		-- initialized tracker (lazy init)
		if aTracker.trackedGroups then 
			for idy, aGroup in pairs (aTracker.trackedGroups) do 
				if Group.isExist(aGroup) and aGroup:getName() == theName then 
					table.insert(tracking, aTracker)
					isTracking = true 
				end
			end
		end
		
		for aName, aNum in pairs(aTracker.limbo) do 
			if aName == theName then 
				table.insert(tracking, aTracker)
				isTracking = true
			end
		end
	end 
	
	return isTracking, #tracking, tracking
end

function groupTracker.groupTrackedBy(theGroup)
	if not theGroup then return false,0, nil end
	if not Group.isExist(theGroup) then return false, 0, nil end 
	local theName = theGroup:getName()
	local isTracking, numTracks, trackers = groupTracker.groupNameTrackedBy(theName)
	return isTracking, numTracks, trackers 

end

--
-- read zone 
--
function groupTracker.createTrackerWithZone(theZone)
	-- init group tracking set 
	theZone.trackedGroups = {}
	theZone.limbo = {} -- name based, for groups that are tracked 
	                   -- although technically off the map (helo etc)

	theZone.trackerMethod = theZone:getStringFromZoneProperty("method", "inc")
	if theZone:hasProperty("trackerMethod") then 
		theZone.trackerMethod = theZone:getStringFromZoneProperty( "trackerMethod", "inc")
	end

	theZone.trackerTriggerMethod = theZone:getStringFromZoneProperty("triggerMethod", "change")

	if theZone:hasProperty("trackerTriggerMethod") then 
		theZone.trackerTriggerMethod = theZone:getStringFromZoneProperty("trackerTriggerMethod", "change")
	end

	if theZone:hasProperty("numGroups") then 
		theZone.tNumGroups = theZone:getStringFromZoneProperty("numGroups", "*<none>") -- legacy support 
	elseif theZone:hasProperty("numGroups#") then 
		theZone.tNumGroups = theZone:getStringFromZoneProperty( "numGroups#", "*<none>") 
	end 
	
	if theZone:hasProperty("numUnits") then
		theZone.tNumUnits = theZOne:getStringFromZoneProperty("numUnits", "*<none>") -- legacy support
	elseif theZone:hasProperty("numUnits#") then 
		theZone.tNumUnits = theZone:getStringFromZoneProperty("numUnits#", "*<none>")
	end
	
	if theZone:hasProperty("addGroup") then 
		theZone.tAddGroup = theZone:getStringFromZoneProperty("addGroup", "*<none>") -- legacy support
	elseif theZone:hasProperty("addGroup!") then 
		theZone.tAddGroup = theZone:getStringFromZoneProperty("addGroup!", "*<none>") 
	end
		
	if theZone:hasProperty("removeGroup") then 
		theZone.tRemoveGroup = theZone:getStringFromZoneProperty( "removeGroup", "*<none>") -- legacy support
	elseif theZone:hasProperty("removeGroup!") then 
		theZone.tRemoveGroup = theZone:getStringFromZoneProperty( "removeGroup!", "*<none>") 
	end
		
	if theZone:hasProperty("groupFilter") then 
		local filterString = theZone:getStringFromZoneProperty( "groupFilter", "2") -- ground 
		theZone.groupFilter = dcsCommon.string2GroupCat(filterString)
		if groupTracker.verbose or theZone.verbose then 
			trigger.action.outText("+++gTrck: filtering " .. theZone.groupFilter .. " in " .. theZone.name, 30)
		end 
	end	
	
	if theZone:hasProperty("destroy?") then 
		theZone.destroyFlag = theZone:getStringFromZoneProperty(theZone, "destroy?", "*<none>")
		theZone.lastDestroyValue = cfxZones.getFlagValue(theZone.destroyFlag, theZone)
	end
	
	if theZone:hasProperty("allGone!") then 
		theZone.allGoneFlag = theZone:getStringFromZoneProperty("allGone!", "<None>") -- note string on number default
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
	for aName, aNum in pairs(theZone.limbo) do 
		theZone.limbo[aName] = 0 -- <1 is special for 'remove me and detect kill on next checkGroups'
	end
	
	-- we keep all groups in trackedGroups so we 
	-- generate a host of destroy events when we run through 
	-- checkGroups next 
end

function groupTracker.checkGroups(theZone)
	local filteredGroups = {}
	local totalUnits = 0
	if not theZone.trackedGroups then theZone.trackedGroups = {} end
	for idx, theGroup in pairs(theZone.trackedGroups) do 
		-- see if this group can be transferred
		local isDead = false 

		if Group.isExist(theGroup) and theGroup:getSize() > 0 then
			totalUnits = totalUnits + theGroup:getSize()
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
	
	local newLimbo = {}
	for aName, aNum in pairs (theZone.limbo) do 
		if aNum < 1 then
			if groupTracker.verbose or theZone.verbose then 
				trigger.action.outText("+++gTrk: dead group <" .. aName .. "> detected in LIMBO for " .. theZone.name .. ", removing.", 30)
			end 
		else 
			newLimbo[aName] = aNum
			totalUnits = totalUnits + aNum 
		end 
	end 
	theZone.limbo = newLimbo
	
	-- now exchange filtered for current
	theZone.trackedGroups = filteredGroups
	--set new group value 
	-- now set numGroups if defined
	if theZone.tNumGroups then 
		cfxZones.setFlagValue(theZone.tNumGroups, dcsCommon.getSizeOfTable(theZone.limbo) + #filteredGroups, theZone)
	end
	
	-- and update unit count if defined 
	if theZone.tNumUnits then 
		cfxZones.setFlagValue(theZone.tNumUnits, totalUnits, theZone)
	end
end
 
function groupTracker.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(groupTracker.update, {}, timer.getTime() + 1/groupTracker.ups)
		
	for idx, theZone in pairs(groupTracker.trackers) do
		-- first see if any groups need to be silently 
		-- added by name ("late bind"). Used by Persistence, can be used
		-- by anyone to silently (no add event) add groups
		if not theZone.trackedGroups then theZone.trackedGroups = {} end
		if theZone.silentAdd then 
			for idx, gName in pairs (theZone.silentAdd) do 
				local theGroup = Group.getByName(gName)
				if theGroup and Group.isExist(theGroup) then
					-- make sure that we don't accidentally 
					-- add the same group twice 
					local isPresent = false 
					for idy, aGroup in pairs(theZone.trackedGroups) do 
						if Group.isExit(aGroup) and aGroup:getName(aGroup) == gName then 
							isPresent = true 
						end
					end
					if not isPresent then 
						table.insert(theZone.trackedGroups, theGroup)
					else
						if groupTracker.verbose or theZone.verbose then 
							trigger.action.outText("+++gTrk: late bind: group <" .. gName .. "> succesful during update", 30)
						end
					end
				else 
					if groupTracker.verbose or theZone.verbose then 
						trigger.action.outText("+++gTrk: silent add: Group <" .. gName .. "> not found or dead", 30)
					end
				end
			end
			theZone.silentAdd = nil
		end
		
		if theZone.destroyFlag and cfxZones.testZoneFlag(theZone, theZone.destroyFlag, theZone.trackerTriggerMethod, "lastDestroyValue") then 
			groupTracker.destroyAllInZone(theZone)
			if groupTracker.verbose or theZone.verbose then 
				trigger.action.outText("+++gTrk: destroying all groups tracked with <" .. theZone.name .. ">", 30)
			end 
		end
		
		groupTracker.checkGroups(theZone)
		
		-- see if we need to bang on empty!
		local currCount = #theZone.trackedGroups + dcsCommon.getSizeOfTable(theZone.limbo)
		if theZone.allGoneFlag and currCount == 0 and currCount ~= theZone.lastGroupCount then 
			if theZone.verbose or groupTracker.verbose then 
				trigger.action.outText("+++gTrk: all groups for tracker <" .. theZone.name .. "> gone, polling <" .. theZone.allGoneFlag .. ">", 30)
			end 
			cfxZones.pollFlag(theZone.allGoneFlag, theZone.trackerMethod, theZone)
		end 
		theZone.lastGroupCount = currCount
	end
end

--
-- Load and Save 
--
function groupTracker.saveData()
	local theData = {}
	local allTrackerData = {}
	for idx, aTracker in pairs(groupTracker.trackers) do 
		local theName = aTracker.name 
		local trackerData = {}
		local trackedGroups = {}
		for idx, aGroup in pairs (aTracker.trackedGroups) do 
			if Group.isExist(aGroup) and aGroup:getSize() > 0 then 
				local gName = aGroup:getName()
				table.insert(trackedGroups, gName)
			end
		end
		trackerData.trackedGroups = trackedGroups
		-- we may also want to save flag values butz it 
		-- would be better to have this done externally, globally
		allTrackerData[theName] = trackerData
	end
	
	theData.trackerData = allTrackerData
	return theData
end

function groupTracker.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("groupTracker")
	if not theData then 
		if groupTracker.verbose then 
			trigger.action.outText("+++gTrk: no save date received, skipping.", 30)
		end
		return
	end
	
	local allTrackerData = theData.trackerData
	for tName, tData in pairs (allTrackerData) do 
		local theTracker = groupTracker.getTrackerByName(tName)
		if theTracker then 
			-- pass to silentAdd, will be added during next update
			-- we do this for a late bind, one second down the road
			-- to give all modules time to load and spawn the 
			-- groups
			theTracker.silentAdd = tData.trackedGroups
		else 
			trigger.action.outText("+++gTrk - persistence: unable to synch tracker <" .. tName .. ">: not found", 30)
		end
	end
end

--
-- Config & Start
--

function groupTracker.trackGroupsInZone(theZone)

	local trackerName = cfxZones.getStringFromZoneProperty(theZone, "addToTracker:", "<none>")
	
	local theGroups = cfxZones.allGroupsInZone(theZone, nil)
--[[--	trigger.action.outText("Groups in zone <" .. theZone.name .. ">:", 30)
	local msg = "  :: "
	for idx, aGroup in pairs (theGroups) do 
		msg = msg .. " <" .. aGroup:getName() .. ">"
	end 
	trigger.action.outText(msg, 30)
--]]--
	
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
					trigger.action.outText("+++gTrk-TW: added " .. aGroup:getName() .. " to tracker " .. theName, 30)
				end
			end
		end 
	end 
	
end


function groupTracker.readConfigZone()
	local theZone = cfxZones.getZoneByName("groupTrackerConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("groupTrackerConfig")
	end 
	
	groupTracker.verbose = theZoneverbose
	
	groupTracker.ups = theZone:getNumberFromZoneProperty("ups", 1)
	
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
	
	-- verbose debugging:
	-- show who's tracking who 
	for idx, theZone in pairs(groupTracker.trackers) do 
		if groupTracker.verbose or theZone.verbose then 
			local msg = " - Tracker <" .. theZone.name .. ">: "
			for idx, theGroup in pairs(theZone.trackedGroups) do 
				msg = msg .. "<" .. theGroup:getName() .. "> "
			end
			trigger.action.outText(msg, 30)
		end 
	end 
	
	-- update all cloners and spawned clones from file 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = groupTracker.saveData
		persistence.registerModule("groupTracker", callbacks)
		-- now load my data 
		groupTracker.loadData() -- add to late link
		-- update in one second so all can load 
		-- before we link late 
		timer.scheduleFunction(groupTracker.update, {}, timer.getTime() + 1/groupTracker.ups)
	else 
		-- start update immediately
		groupTracker.update()
	end

	trigger.action.outText("cfx Group Tracker v" .. groupTracker.version .. " started.", 30)
	return true 
end

-- let's go!
if not groupTracker.start() then 
	trigger.action.outText("cfx Group Tracker aborted: missing libraries", 30)
	messenger = nil 
end

