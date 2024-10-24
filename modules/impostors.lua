impostors={}

impostors.version = "1.2.0"
impostors.verbose = false  
impostors.ups = 1
impostors.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"cfxMX", 
}

impostors.impostorZones = {}
--impostors.impostors = {} -- these are sorted by name of the orig group and contain the units by name of the impostors
impostors.callbacks = {}
impostors.uniqueCounter = 8200000 -- clones start at 9200000

--[[--
	Version History
	1.0.0 - initial version
	1.0.1 - added some verbosity 
	1.1.0 - filtered dead units during spawns 
			cleanup
			some performance boost for mx lookup 
	1.2.0 - filters dead groups entirely 
  LIMITATIONS:
  must be on ground (or would be very silly
  does not work with any units deployed on ships
  Positioning AI Planed (ME shortcoming): add a waypoint so it orients itself.
  
--]]--

--
-- adding / removing from list 
--
function impostors.addImpostorZone(theZone)
	table.insert(impostors.impostorZones, theZone)
end

function impostors.getCloneZoneByName(aName) 
	for idx, aZone in pairs(impostors.impostorZones) do 
		if aName == aZone.name then return aZone end 
	end
	if impostors.verbose then 
		trigger.action.outText("+++ipst: no impostor with name <" .. aName ..">", 30)
	end 
	return nil 
end

--
-- spawn impostors from data 
--
function impostors.uniqueID()
	local uid = impostors.uniqueCounter
	impostors.uniqueCounter = impostors.uniqueCounter + 1
	return uid 
end

function impostors.spawnImpostorsFromData(rawData, cat, ctry) 
	local theImpostors = {}
		-- we iterate a group's raw data unit by unit and create 
		-- a static for each unit, named exactly as the original unit 
		-- modifies rawData for use later
		for idx, unitData in pairs(rawData.units) do 
			-- build impostor record 
			local ir = {}
			ir.heading = unitData.heading
			ir.type = unitData.type
			ir.name = rawData.name .. "-" .. tostring(impostors.uniqueID())
			ir.groupID = impostors.uniqueID()
			ir.unitId = impostors.uniqueID()
			theImpostors[unitData.name] = ir.name -- for lookup later 
			ir.x = unitData.x
			ir.y = unitData.y 
			ir.livery_id = unitData.livery_id
			
			if impostors.verbose then 
				trigger.action.outText("+++impostoring unit <" .. unitData.name .. ">: name <" .. ir.name .. ">, x <" .. ir.x .. ">, y <" .. ir.y .. ">, heading <" .. ir.heading .. ">, type <" .. ir.type .. "> ", 30)
			end 
			local linkedZones = unitData.linkedZones
			-- spawn the impostor 
			local theImp = coalition.addStaticObject(ctry, ir)
			-- relink linked zones to this 
			if #linkedZones > 0 then 
				for idx, theZone in pairs(linkedZones) do 
					theZone.linkedUnit = theImp
					if theZone.verbose then 
						trigger.action.outText("+++ipst: imp-linked zone <" .. theZone.name .. "> to imp <" .. theImp:getName() .. ">", 30)
					end
				end
			end 
		end
	return theImpostors
end
--
-- read impostor zone 
--

function impostors.getRawDataFromGroupNamed(gName)
	if gName then 
		theGroup = Group.getByName(gName)
		if not theGroup then 
			trigger.action.outText("+++ipst: getRawDataFromGroupName cant find group <" .. gName .. ">", 30)
			return nil, nil, nil
		end
	else 
		trigger.action.outText("+++ipst: getRawDataFromGroupName has no name to look up", 30)
		return nil, nil, nil 
	end 
	local groupName = gName
	local cat = theGroup:getCategory()
	-- access mxdata for livery because getDesc does not return the livery 	
	local liveries = {} 
--	local mxData = cfxMX.getGroupFromDCSbyName(gName)
	local mxData = cfxMX.groupDataByName[gName] -- performance 
	if mxData then mxData = dcsCommon.clone(mxData) end 
	for idx, theUnit in pairs (mxData.units) do 
		liveries[theUnit.name] = theUnit.livery_id
	end 
	
	local ctry
	local gID = theGroup:getID()
	local allUnits = theGroup:getUnits()
	local rawGroup = {}
	rawGroup.name = groupName
	local rawUnits = {}
	for idx, theUnit in pairs(allUnits) do 
		local ir = {}
		local unitData = theUnit:getDesc()
		-- build record 
		ir.heading = dcsCommon.getUnitHeading(theUnit)
		ir.name = theUnit:getName()
		ir.type = unitData.typeName -- warning: fields are called differently! typename vs type
		ir.livery_id = liveries[ir.name] -- getDesc does not return livery
		ir.groupId = gID
		ir.unitId = theUnit:getID()
		local up = theUnit:getPoint()
		ir.x = up.x
		ir.y = up.z -- !!! warning! 
		-- see if any zones are linked to this unit 
		ir.linkedZones = cfxZones.zonesLinkedToUnit(theUnit)
		if theUnit:getLife() > 1 then 
			table.insert(rawUnits, ir)
		end
		ctry = theUnit:getCountry()
	end
	rawGroup.ctry = ctry 
	rawGroup.cat = cat 
	rawGroup.units = rawUnits 
	return rawGroup, cat, ctry
end


function impostors.createImpostorWithZone(theZone) -- has "impostor?"
	if impostors.verbose or theZone.verbose then 
		trigger.action.outText("+++ipst: new impostor " .. theZone.name, 30)
	end

	-- the impostor? is the flag. we always have it.
	-- must match aZone.impostorFlag, aZone.impostorTriggerMethod, "lastImpostorValue"
	theZone.impostorFlag = cfxZones.getStringFromZoneProperty(theZone, "impostor?", "*<none>")
	theZone.lastImpostorValue = cfxZones.getFlagValue(theZone.impostorFlag, theZone)
	
	if cfxZones.hasProperty(theZone, "reanimate?") then 
		theZone.reanimateFlag = cfxZones.getStringFromZoneProperty(theZone, "reanimate?", "*<none>")
		theZone.lastReanimateValue = cfxZones.getFlagValue(theZone.reanimateFlag, theZone)
	end 
	theZone.impostorTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "impostorTriggerMethod") then 
		theZone.impostorTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "impostorTriggerMethod", "change")
	end
 
	theZone.groupNames = cfxZones.allGroupNamesInZone(theZone)
	theZone.impostor = false -- we have not yet turned units into impostors
	theZone.myImpostors = {} 
	theZone.origin = cfxZones.getPoint(theZone) -- save reference point for all groupVectors 
	theZone.onStart = cfxZones.getBoolFromZoneProperty(theZone, "onStart", false) 
	
	-- blinking
	theZone.blinkTime = cfxZones.getNumberFromZoneProperty(theZone, "blink", -1)
	theZone.blinkCount = 0 
	
	-- interface to groupTracker tbc 
	if cfxZones.hasProperty(theZone, "trackWith:") then 
		theZone.trackWith = cfxZones.getStringFromZoneProperty(theZone, "trackWith:", "<None>")
	end
	
	-- check onStart, and act accordingly
	if theZone.onStart then
		impostors.turnZoneIntoImpostors(theZone)
	end 
	
	-- all dead
	if cfxZones.hasProperty(theZone, "allDead!") then 
		theZone.allDead = cfxZones.getStringFromZoneProperty(theZone, "allDead", "<None>")
	end
	
	theZone.impostorMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "impostorMethod") then 
		theZone.impostorMethod = cfxZones.getStringFromZoneProperty(theZone, "impostorMethod", "inc")
	end
	
	-- declare all units as alive 
	theZone.allImpsDead = false 
	-- we end with group replaced by impostors 
end

-- 
-- Spawning
--

-- REAL --> IMP
function impostors.turnGroupsIntoImpostors(theZone)
--	can be handed an array of strings or groups.
-- returns a dict of impostors, indexed by group names
	local theGroupNames = theZone.groupNames
	local myImpostors = {}
	for idx, aGroupName in pairs(theGroupNames) do
		local gName = aGroupName
		if type(gName) == "table" then -- this is a group. get its name 
			trigger.action.outText("+++ipst: converting table gName to string in turnGroupsIntoImpostors",30)
			gName = gName:getName()
		end 
		if not gName then 
			trigger.action.outText("+++ipst: nil group name in turnGroupsIntoImpostors",30)
			return nil 
		end 
		local aGroup = Group.getByName(gName)
		if aGroup and gName then 
			if theZone.verbose then 
				trigger.action.outText("impostoring group <" .. gName .. ">", 30)
			end 
			-- record unit data to create impostors
			local rawData, cat, ctry = impostors.getRawDataFromGroupNamed(gName)
			-- if we are tracking the group, remove it from tracker 
			if theZone.trackWith and groupTracker.removeGroupNamedFromTrackerNamed then 
				groupTracker.removeGroupNamedFromTrackerNamed(gName, theZone.trackWith)
			end
			
			-- despawn the group. we'll spawn statics now
			-- we may do some book-keeping first for the 
			-- names. we'll see later 
			Group.destroy(aGroup)
			-- now spawn impostors based on the rawData, 
			-- and return impostorGroup
			local impostorGroup = impostors.spawnImpostorsFromData(rawData, cat, ctry) 
			myImpostors[gName] = impostorGroup
		end 	
	end
	return myImpostors
end

function impostors.turnZoneIntoImpostors(theZone)
	if theZone.verbose then 
		trigger.action.outText("+++ipst: creating impostors for zone <" .. theZone.name ..">", 30)
	end
	theZone.myImpostors = impostors.turnGroupsIntoImpostors(theZone)
	if theZone.myImpostors then 
		theZone.impostor = true 
	else 
		if theZone.verbose or impostors.verbose then 
			trigger.action.outText("+++ipst: groups to impostors failed for <" .. theZone.name .. ">",30)
		end 
	end
end

-- IMP --> REAL
function impostors.relinkZonesForGroup(relinkZones, newGroup)
	-- may be called sync and async!
	local allUnits = newGroup:getUnits()
	for idx, theUnit in pairs(allUnits) do 
		local unitName = theUnit:getName()
		local linkedZones = relinkZones[unitName]
		if linkedZones and #linkedZones > 0 then 
			for idy, theZone in pairs(linkedZones) do 
				theZone.linkedUnit = theUnit
				if theZone.verbose then 
					trigger.action.outText("+++ipst: re-linked zone <" .. theZone.name .. "> to unit <" .. unitName .. ">", 30)
				end 
			end
		end 
	end
end

function impostors.spawnGroupsFromImpostor(theZone)
	-- turn zone's impostors (static objects) into units
	if theZone.verbose or impostors.verbose then 
		trigger.action.outText("+++ipst: spawning for impostor <" .. theZone.name .. ">", 30)
	end
	
	if not theZone.impostor then 
		if theZone.verbose or impostors.verbose then 
			trigger.action.outText("+++ipst: <> groups are not impostors.", 30)
		end
		return 
	end
	
	local deadUnits = {} -- collect all dead units for immediate delete 
						 -- after spawning 
	local filtered = {} 
	for idx, groupName in pairs(theZone.groupNames) do 
		-- get my group data from MX based on my name 
		-- we get from MX so we get all path and order info 
--		local rawData, cat, ctry = cfxMX.getGroupFromDCSbyName(groupName)
		local rawData = cfxMX.groupDataByName[groupName]
		if rawData then rawData = dcsCommon.clone(rawData) end 
		local cat = cfxMX.groupCatByName[groupName]
		local ctry = cfxMX.countryByName[groupName]
		local impostorGroup = theZone.myImpostors[groupName]
		if impostorGroup then 
			table.insert(filtered, groupName)
			local relinkZones = {}
			-- now iterate all units in that group, and remove their impostors
			for idy, theUnit in pairs(rawData.units) do 
				if theUnit and theUnit.name then 
					local impName = impostorGroup[theUnit.name]
					if not impName then 
						if theZone.verbose then 
							trigger.action.outText("group <" .. groupName .. ">: no impostor for <" .. theUnit.name .. ">", 30)
						end 
					else 
						local impStat = StaticObject.getByName(impName)
						if impStat and impStat:isExist() and impStat:getLife() > 1 then 
							-- still alive. read x, y and heading 
							local sp = impStat:getPoint()
							theUnit.x = sp.x 
							theUnit.y = sp.z -- !!!
							theUnit.heading = dcsCommon.getUnitHeading(impStat) -- should also work for statics
							-- should automatically handle ["livery_id"]
							relinkZones[theUnit.name] = cfxZones.zonesLinkedToUnit(impStat)
						else 
							-- dead 
							table.insert(deadUnits, theUnit.name)
						end
						-- destroy imp
						if impStat and impStat:isExist() then 
							impStat:destroy()
						end
					end
				end
			end
			
			-- destroy impostor info 
			theZone.myImpostors[groupName] = nil 
			theZone.impostor = false -- is this good?
			
			-- now create the group 
			if theZone.blinkTime <= 0 then 
				-- immediate spawn
				--local newGroup = coalition.addGroup(ctry, cfxMX.catText2ID(cat), rawData)
				local newGroup = coalition.addGroup(ctry, cat, rawData)
				impostors.relinkZonesForGroup(relinkZones, newGroup)
				if theZone.trackWith and groupTracker.addGroupToTrackerNamed then 
					-- add these groups to the group tracker 
					if theZone.verbose or impostors.verbose then 
						trigger.action.outText("+++ipst: attempting to add group <" .. newGroup:getName() .. "> to tracker <" .. theZone.trackWith .. ">", 30)
					end 
					groupTracker.addGroupToTrackerNamed(newGroup, theZone.trackWith)
				end
			else 
				-- scheduled spawn 
				theZone.blinkCount = theZone.blinkCount + 1 -- so healthcheck avoids false positives
				local args = {}
				args.ctry = ctry 
				args.cat = cat -- cfxMX.catText2ID(cat)
				args.rawData = rawData
				args.theZone = theZone 
				args.relinkZones = relinkZones
				timer.scheduleFunction(impostors.delayedSpawn, args, timer.getTime() + theZone.blinkTime)
			end
		else 
			if theZone.verbose or impostors.verbose then 
				trigger.action.outText("No impostor group named <" .. groupName .. "> any more, skipped.", 30)
			end 
--			theZone.myImpostors[groupName] = nil 
		end
	end
	theZone.groupNames = filtered -- filter out non-existing 
	-- now remove all dead units 
	if theZone.blinkTime <= 0 then 
		for idx, unitName in pairs(deadUnits) do 
			local theUnit = Unit.getByName(unitName)
			if theUnit then 
				theUnit:destroy() -- BAD BAD BAD!!!! do some guarding, mon!
			end 
		end
	else 
		-- schedule removal of all dead units for later 
		timer.scheduleFunction(impostors.delayedCleanup, deadUnits, timer.getTime() + theZone.blinkTime + 0.1)
	end 
	theZone.myImpostors = nil 
end 

function impostors.delayedSpawn(args) 
	local rawData = args.rawData 
	local cat = args.cat 
	local ctry = args.ctry 
	local theZone = args.theZone 
	local relinkZones = args.relinkZones
	if theZone.verbose or impostors.verbose then 
		trigger.action.outText("+++ipst: delayed spawn for group <" .. rawData.name .. "> of zone <" .. theZone.name .. ">", 30)
	end 
	local newGroup = coalition.addGroup(ctry, cat, rawData)
	impostors.relinkZonesForGroup(relinkZones, newGroup)

	if theZone.trackWith and groupTracker.addGroupToTrackerNamed then 
		-- add these groups to the group tracker 
		if theZone.verbose or impostors.verbose then 
			trigger.action.outText("+++ipst: attempting to add group <" .. newGroup:getName() .. "> to tracker <" .. theZone.trackWith .. ">", 30)
		end 
		groupTracker.addGroupToTrackerNamed(newGroup, theZone.trackWith)
	end
	-- close TRX bracket for blinking, health check can proceed 
	theZone.blinkCount = theZone.blinkCount - 1 
end

function impostors.delayedCleanup(deadUnits)
	for idx, unitName in pairs(deadUnits) do 
		local theUnit = Unit.getByName(unitName)
		if theUnit then 
			theUnit:destroy() -- BAD BAD BAD!!!! do some guarding, mon!
		end 
	end
end
-- 
-- healthCheck
--
function impostors.healthCheck(theZone)
	-- make sure there is at least one living unit left 
	-- if not, bang!
	if theZone.allImpsDead then return end -- we are already dead 
	
	if theZone.impostor then 
		-- we have impostors. Check until you find the first live ones 
		for gName, impNames in pairs (theZone.myImpostors) do 
			-- impNames are the names of all the static objects 
			-- in this group 
			for idx, theImpName in pairs (impNames) do 
				local theImp = StaticObject.getByName(theImpName)
				if theImp and theImp:isExist() then 
					local life = theImp:getLife()
					if life > 1 then 
						-- all is well, at least one imp alive 
						return 
					end 
				end
			end 
		end 
		-- when we get here, all imps are dead, 
		-- drop through 
		if theZone.verbose or impostors.verbose then 
			trigger.action.outText("+++ipst: Zone <" .. theZone.name .. "> - all impostors destroyed. Removing.", 30)
		end
	else 
		-- we have real groups. Let's iterate
		if theZone.blinkCount > 0 then return end -- blinking, no healtch check 
		theZone.BlinkCount = 0 -- just in case it went negative 
		
		for idx, groupName in pairs(theZone.groupNames) do 
			local theGroup =  Group.getByName(groupName)
			if theGroup and theGroup:isExist() then 
				local allUnits = theGroup:getUnits()
				for idy, aUnit in pairs (allUnits) do 
					if aUnit:isExist() then 
						local life = aUnit:getLife()
						if life > 1 then 
							return -- all is well
						end
					end 
				end 
			end
		end
		-- if we get here, all units ded
		if theZone.verbose or impostors.verbose then 
			trigger.action.outText("+++ipst: Zone <" .. theZone.name .. "> - all active units destroyed. Removing.", 30)
		end
	end
	
	-- when we get here , all are ded
	theZone.allImpsDead = true 
	if theZone.allDead then 
		cfxZones.pollFlag(theZone.allDead, theZone.impostorMethod, theZone) 
	end
end

--
-- Update
--
function impostors.update()
	timer.scheduleFunction(impostors.update, {}, timer.getTime() + 1/impostors.ups)
	
	for idx, aZone in pairs(impostors.impostorZones) do
		-- first perform health check on all zones 
		impostors.healthCheck(aZone)
		
		-- now see if we received signals 
		if not aZone.allImpsDead then 
			-- see if we got impostor? command
			if cfxZones.testZoneFlag(aZone, aZone.impostorFlag, aZone.impostorTriggerMethod, "lastImpostorValue") then
				if impostors.verbose or aZone.verbose then 
					trigger.action.outText("+++ipst: turn group to impostors triggered for <" .. aZone.name .. "> on <" .. aZone.impostorFlag .. ">", 30)
				end
				impostors.turnZoneIntoImpostors(aZone)			
			end
			
			if aZone.reanimateFlag and cfxZones.testZoneFlag(aZone, aZone.reanimateFlag, aZone.impostorTriggerMethod, "lastReanimateValue") then
				if impostors.verbose or aZone.verbose then 
					trigger.action.outText("+++ipst: impostor to live groups spawn triggered for <" .. aZone.name .. "> on <" .. aZone.impostorFlag .. ">", 30)
				end
				impostors.spawnGroupsFromImpostor(aZone)
			end
		else 
			-- nothing to do, all dead 
		end
	end
end
--
-- start 
-- 
function impostors.readConfigZone()
	local theZone = cfxZones.getZoneByName("impostorsConfig") 
	if not theZone then 
		if impostors.verbose then 
			trigger.action.outText("+++ipst: NO config zone!", 30)
		end 
		theZone = cfxZones.createSimpleZone("impostorsConfig")
	end 
	
	impostors.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 1)
	
	impostors.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if impostors.verbose then 
		trigger.action.outText("+++ipst: read config", 30)
	end 
end

function impostors.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Impostors requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Impostors", 
		impostors.requiredLibs) then
		return false 
	end
	
	-- read config 
	impostors.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("impostor?")
	
	-- now create an rnd gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		impostors.createImpostorWithZone(aZone) -- process attribute and add to zone
		impostors.addImpostorZone(aZone) -- remember it so we can smoke it
	end
	
	-- start update 
	impostors.update()
	
	trigger.action.outText("cfx Impostors v" .. impostors.version .. " started.", 30)
	return true 
end

-- let's go!
if not impostors.start() then 
	trigger.action.outText("cf/x Impostors aborted: missing libraries", 30)
	impostors = nil 
end

--[[--
To do
- reset? flag: will reset all to MX locationS
- add a zone's follow ability to impostors by allowing linkedUnit to work with impostors 
- impostor on idle option. when task of group goes to idle, the group turns into impostors 
--]]--