cfxReconMode = {}
cfxReconMode.version = "1.5.0"
cfxReconMode.verbose = false -- set to true for debug info  
cfxReconMode.reconSound = "UI_SCI-FI_Tone_Bright_Dry_20_stereo.wav" -- to be played when somethiong discovered

cfxReconMode.prioList = {} -- group names that are high prio and generate special event
cfxReconMode.blackList = {} -- group names that are NEVER detected. Comma separated strings, e.g. {"Always Hidden", "Invisible Group"}

cfxReconMode.removeWhenDestroyed = true 
cfxReconMode.activeMarks = {} -- all marks and their groups, indexed by groupName 

cfxReconMode.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}

--[[--
VERSION HISTORY
 1.0.0 - initial version 
 1.0.1 - removeScoutByName()
 1.0.2 - garbage collection 
 1.1.0 - autoRecon - any aircraft taking off immediately
         signs up, no message when signing up or closing down
		 standalone - copied common procs lerp, agl, dist, distflat
		 from dcsCommon
		 report numbers 
		 verbose flag 
 1.2.0 - queued recons. One scout per second for more even
         performance
		 removed gc since it's now integrated into 
		 update queue
		 removeScout optimization when directly passing name
		 playerOnlyRecon for autoRecon 
		 red, blue, grey side filtering on auto scout
 1.2.1 - parametrized report sound 
 1.3.0 - added black list, prio list functionality 
 1.3.1 - callbacks now also push name, as group can be dead
       - removed bug when removing dead groups from map
 1.4.0 - import dcsCommon, cfxZones etc 
       - added lib check 
	   - config zone 
	   - prio+
	   - detect+
 1.4.1 - invocation no longer happen twice for prio. 
	   - recon sound 
	   - read all flight groups at start to get rid of the 
	   - late activation work-around 
 1.5.0 - removeWhenDestroyed()
	   - autoRemove()
	   - readConfigZone creates default config zone so we get correct defaulting 
 
 cfxReconMode is a script that allows units to perform reconnaissance
 missions and, after detecting units, marks them on the map with 
 markers for their coalition and some text 
 Also, a callback is initiated for scouts as follows
   signature: (reason, theSide, theSout, theGroup) with  
   reason a string 
	 'detected' a group was detected
     'removed' a mark for a group timed out
	 'priority' a member of prio group was detected 
	 'start' a scout started scouting
	 'end' a scout stopped scouting
	 'dead' a scout has died and was removed from pool 
   theSide - side of the SCOUT that detected units
   theScout - the scout that detected the group 
   theGroup - the group that is detected  
   theName - the group's name    
--]]--

cfxReconMode.detectionMinRange = 3000 -- meters at ground level
cfxReconMode.detectionMaxRange = 12000 -- meters at max alt (10'000m)
cfxReconMode.maxAlt = 9000 -- alt for maxrange (9km = 27k feet)

cfxReconMode.autoRecon = true -- add all airborne units, unless 
cfxReconMode.redScouts = false -- set to false to prevent red scouts in auto mode
cfxReconMode.blueScouts = true -- set to false to prevent blue scouts in auto-mode
cfxReconMode.greyScouts = false -- set to false to prevent neutral scouts in auto mode
cfxReconMode.playerOnlyRecon = false -- only players can do recon 
cfxReconMode.reportNumbers = true -- also add unit count in report 
cfxReconMode.prioFlag = nil 
cfxReconMode.detectFlag = nil 
cfxReconMode.applyMarks = true 

cfxReconMode.ups = 1 -- updates per second.
cfxReconMode.scouts = {} -- units that are performing scouting.
cfxReconMode.processedScouts = {} -- for managing performance: queue
cfxReconMode.detectedGroups = {} -- so we know which have been detected
cfxReconMode.marksFadeAfter = 30*60 -- after detection, marks disappear after
                     -- this amount of seconds. -1 means no fade
					 -- 60 is one minute

cfxReconMode.callbacks = {} -- sig: cb(reason, side, scout, group)
cfxReconMode.uuidCount = 0 -- for unique marks 


-- end standalone dcsCommon extract 

function cfxReconMode.uuid()
	cfxReconMode.uuidCount = cfxReconMode.uuidCount + 1
	return cfxReconMode.uuidCount
end

function cfxReconMode.addCallback(theCB)
	table.insert(cfxReconMode.callbacks, theCB)
end

function cfxReconMode.invokeCallbacks(reason, theSide, theScout, theGroup, theName)
	for idx, theCB in pairs(cfxReconMode.callbacks) do 
		theCB(reason, theSide, theScout, theGroup, theName)
	end
end

-- add a priority/blackList group name to prio list 
function cfxReconMode.addToPrioList(aGroup)
	if not aGroup then return end 
	if type(aGroup) == "table" and aGroup.getName then 
		aGroup = aGroup:getName()
	end
	if type(aGroup) == "string" then 
		table.insert(cfxReconMode.prioList, aGroup)
	end
end

function cfxReconMode.addToBlackList(aGroup)
	if not aGroup then return end 
	if type(aGroup) == "table" and aGroup.getName then 
		aGroup = aGroup:getName()
	end
	if type(aGroup) == "string" then 
		table.insert(cfxReconMode.blackList, aGroup)
	end
end


function cfxReconMode.isStringInList(theString, theList)
	if not theString then return false end 
	if not theList then return false end 
	if type(theString) == "string" then 
		for idx,anItem in pairs(theList) do 
			if anItem == theString then return true end
		end
	end
	return false
end

-- addScout directly adds a scout unit. Use from external 
-- to manually add a unit (e.g. via GUI when autoscout isExist
-- off, or to force a scout unit (e.g. when scouts for a side
-- are not allowed but you still want a unit from that side 
-- to scout
-- since we use a queue for scouts, also always check the 
-- processed queue before adding to make sure a scout isn't 
-- entered multiple times 

function cfxReconMode.addScout(theUnit)
	if not theUnit then 
		trigger.action.outText("+++cfxRecon: WARNING - nil Unit on add", 30)
		return
	end
	
	if type(theUnit) == "string" then 
		local u = Unit.getByName(theUnit) 
		theUnit = u
	end 
	
	if not theUnit then 
		trigger.action.outText("+++cfxRecon: WARNING - did not find unit on add", 30)
		return 
	end	
	if not theUnit:isExist() then return end 
	-- find out if this an update or a new scout 
	local thisID = tonumber(theUnit:getID())
	local theName = theUnit:getName() 
	local lastUnit = cfxReconMode.scouts[theName]
	local isProcced = false -- may also be in procced line 
	if not lastUnit then 
		lastUnit = cfxReconMode.processedScouts[theName]
		if lastUnit then isProcced = true end 
	end

	if lastUnit then 
		-- this is merely an overwrite 
		if cfxReconMode.verbose then trigger.action.outText("+++rcn: UPDATE scout " .. theName .. " -- no CB invoke", 30) end 
	else 
		if cfxReconMode.verbose then trigger.action.outText("+++rcn: new scout " .. theName .. " with ID " .. thisID, 30) end 
		-- a new scout! Invoke callbacks
		local scoutGroup = theUnit:getGroup()
		local theSide = scoutGroup:getCoalition()
		cfxReconMode.invokeCallbacks("start", theSide, theUnit, nil, "<none>")
	end 
	
	if isProcced then 
		-- overwrite exiting entry in procced queue
		cfxReconMode.processedScouts[theName] = theUnit
	else 
		-- add / overwrite into normal queue 
		cfxReconMode.scouts[theName] = theUnit
	end 
	
	if cfxReconMode.verbose then
		trigger.action.outText("+++rcn: addded scout " .. theUnit:getName(), 30)
	end
end


function cfxReconMode.removeScout(theUnit)
	if not theUnit then 
		trigger.action.outText("+++cfxRecon: WARNING - nil Unit on remove", 30)
		return 
	end
	
	if type(theUnit) == "string" then 
		cfxReconMode.removeScoutByName(theUnit)
		return 
	end 
	
	if not theUnit then return end	
	if not theUnit:isExist() then return end 
	cfxReconMode.removeScoutByName(theUnit:getName())
	local scoutGroup = theUnit:getGroup()
	local theSide = scoutGroup:getCoalition()
	cfxReconMode.invokeCallbacks("end", theSide, theUnit, nil, "<none>")
end

-- warning: removeScoutByName does NOT invoke callbacks, always
-- use removeScout instead!
function cfxReconMode.removeScoutByName(aName)
	cfxReconMode.scouts[aName] = nil
	cfxReconMode.processedScouts[aName] = nil -- also remove from processed stack 
	if cfxReconMode.verbose then
		trigger.action.outText("+++rcn: removed scout " .. aName, 30)
	end
end


function cfxReconMode.canDetect(scoutPos, theGroup, visRange)
	-- determine if a member of theGroup can be seen from 
	-- scoutPos at visRange 
	-- returns true and pos when detected
	local allUnits = theGroup:getUnits()
	for idx, aUnit in pairs(allUnits) do
		if aUnit:isExist() and aUnit:getLife() >= 1 then 
			local uPos = aUnit:getPoint()
			uPos.y = uPos.y + 3 -- raise my 3 meters
			local d = dcsCommon.distFlat(scoutPos, uPos) 
			if d < visRange then 
				-- is in visual range. do we have LOS?
				if land.isVisible(scoutPos, uPos) then 
					-- group is visible, stop here, return true
					return true, uPos
				end
			else 
				-- OPTIMIZATION: if a unit is outside 
				-- detect range, we assume that entire group 
				-- is, since they are bunched together
				-- edge cases may get lucky tests
				return false, nil 
			end
		end		
	end
	return false, nil -- nothing visible
end

function cfxReconMode.placeMarkForUnit(location, theSide, theGroup) 
	local theID = cfxReconMode.uuid()
	local theDesc = "Contact: "..theGroup:getName()
	if cfxReconMode.reportNumbers then 
		theDesc = theDesc .. " (" .. theGroup:getSize() .. " units)"
	end
	trigger.action.markToCoalition(
					theID, 
					theDesc, 
					location, 
					theSide, 
					false, 
					nil)
	return theID
end

function cfxReconMode.removeMarkForArgs(args)
	local theSide = args[1]
	local theScout = args[2]
	local theGroup = args[3]
	local theID = args[4]
	local theName = args[5]
	
	-- only remove if it wasn't already removed.
	-- this method is called async *and* sync!
	if cfxReconMode.activeMarks[theName] then 
		trigger.action.removeMark(theID)
		-- invoke callbacks
		cfxReconMode.invokeCallbacks("removed", theSide, theScout, theGroup, theName)
		cfxReconMode.activeMarks[theName] = nil -- also remove from list of groups being checked
	end 
	
	cfxReconMode.detectedGroups[theName] = nil -- some housekeeping. 
end 


function cfxReconMode.detectedGroup(mySide, theScout, theGroup, theLoc)
	-- put a mark on the map 
	if cfxReconMode.applyMarks then 
		local theID = cfxReconMode.placeMarkForUnit(theLoc, mySide, theGroup)
		local gName = theGroup:getName()
		local args = {mySide, theScout, theGroup, theID, gName}
		cfxReconMode.activeMarks[gName] = args
		-- schedule removal if desired 
		if cfxReconMode.marksFadeAfter > 0 then 	
			timer.scheduleFunction(cfxReconMode.removeMarkForArgs, args, timer.getTime() + cfxReconMode.marksFadeAfter)
		end
	end 
	
	-- say something
	if cfxReconMode.announcer then 
		trigger.action.outTextForCoalition(mySide, theScout:getName() .. " reports new ground contact " .. theGroup:getName(), 30)
		trigger.action.outText("+++recon: announced for side " .. mySide, 30)
		-- play a sound 
		trigger.action.outSoundForCoalition(mySide, cfxReconMode.reconSound)
	else 
		--trigger.action.outText("+++recon: announcer off", 30)
	end 
	
	-- see if it was a prio target 
	if cfxReconMode.isStringInList(theGroup:getName(), cfxReconMode.prioList) then 
		if cfxReconMode.announcer then 
			trigger.action.outTextForCoalition(mySide, "Priority target confirmed",	30)
		end 
		-- invoke callbacks
		cfxReconMode.invokeCallbacks("priotity", mySide, theScout, theGroup, theGroup:getName())
		
		-- increase prio flag 
		if cfxReconMode.prioFlag then 
			local currVal = trigger.misc.getUserFlag(cfxReconMode.prioFlag)
			trigger.action.setUserFlag(cfxReconMode.prioFlag, currVal + 1)
		end
	else 
		-- invoke callbacks
		cfxReconMode.invokeCallbacks("detected", mySide, theScout, theGroup, theGroup:getName())
	
		-- increase normal flag 
		if cfxReconMode.detectFlag then 
			local currVal = trigger.misc.getUserFlag(cfxReconMode.detectFlag)
			trigger.action.setUserFlag(cfxReconMode.detectFlag, currVal + 1)
		end
	end
end

function cfxReconMode.performReconForUnit(theScout)
	if not theScout then return end 
	if not theScout:isExist() then return end -- will be gc'd soon
	-- get altitude above ground to calculate visual range 
	local alt = dcsCommon.getUnitAGL(theScout)
	local visRange = dcsCommon.lerp(cfxReconMode.detectionMinRange, cfxReconMode.detectionMaxRange, alt/cfxReconMode.maxAlt)
	local scoutPos = theScout:getPoint()
	-- figure out which groups we are looking for
	local myCoal = theScout:getCoalition()
	local enemyCoal = 1 
	if myCoal == 1 then enemyCoal = 2 end 
	
	-- iterate all enemy units until we find one 
	-- and then stop this iteration (can only detect one 
	-- group per pass)
	local enemyGroups = coalition.getGroups(enemyCoal)
	for idx, theGroup in pairs (enemyGroups) do 
		-- make sure it's a ground unit 
		local isGround = theGroup:getCategory() == 2
		if theGroup:isExist() and isGround then 
			local visible, location = cfxReconMode.canDetect(scoutPos, theGroup, visRange)
			if visible then 
				-- see if we already detected this one 
				local groupName = theGroup:getName()
				if cfxReconMode.detectedGroups[groupName] == nil then 
					-- only now check against blackList
					if not cfxReconMode.isStringInList(groupName, cfxReconMode.blackList) then 
						-- visible and not yet seen 
						-- perhaps add some percent chance now 
						-- remember that we know this group 
						cfxReconMode.detectedGroups[groupName] = theGroup
						cfxReconMode.detectedGroup(myCoal, theScout, theGroup, location)
						return -- stop, as we only detect one group per pass
					end 
				end
			end
		end
	end
end



function cfxReconMode.updateQueues()
	-- schedule next call 
	timer.scheduleFunction(cfxReconMode.updateQueues, {}, timer.getTime() + 1/cfxReconMode.ups)
	
	-- we only process the first aircraft in 
	-- the scouts array, move it to processed and then shrink
	-- scouts table until it's empty. When empty, transfer all 
	-- back and start cycle anew

	local theFocusScoutName = nil 
	local procCount = 0 -- no iterations done yet
	for name, scout in pairs(cfxReconMode.scouts) do 
		theFocusScoutName = name -- remember so we can delete
		if not scout:isExist() then 
			-- we ignore the scout, and it's 
			-- forgotten since no longer transferred
			-- i.e. built-in GC
			if cfxReconMode.verbose then
				trigger.action.outText("+++rcn: GC - removing scout " .. name .. " because it no longer exists", 30)
			end
			-- invoke 'end' for this scout  
			cfxReconMode.invokeCallbacks("dead", -1, nil, nil, name)
		else
			-- scan for this scout
			cfxReconMode.performReconForUnit(scout)
			-- move it to processed table
			cfxReconMode.processedScouts[name] = scout
		end
		procCount = 1 -- remember we went through one iteration
		break -- always end after first iteration
	end

	-- remove processed scouts from scouts array
	if procCount > 0 then 
		-- we processed one scout (even if scout itself did not exist)
		-- remove that scout from active scouts table
		cfxReconMode.scouts[theFocusScoutName] = nil
	else 
		-- scouts is empty. copy processed table back to scouts
		-- restart scouts array, contains GC already 
		cfxReconMode.scouts = cfxReconMode.processedScouts
		cfxReconMode.processedScouts = {} -- start new empty processed queue
	end 
end

function cfxReconMode.isGroupStillAlive(gName)
		local theGroup = Group.getByName(gName)
		if not theGroup then return false end 
		if not theGroup:isExist() then return false end 
		local allUnits = theGroup:getUnits()
		for idx, aUnit in pairs (allUnits) do 
			if aUnit:getLife() >= 1 then return true end 
		end
		return false 
end

function cfxReconMode.autoRemove()
	-- schedule next call 
	timer.scheduleFunction(cfxReconMode.autoRemove, {}, timer.getTime() + 1/cfxReconMode.ups)
	
	local toRemove = {}
	-- scan all marked groups, and when they no longer exist, remove them 
	for idx, args in pairs (cfxReconMode.activeMarks) do
		-- args = {mySide, theScout, theGroup, theID, gName}
		local gName = args[5]
		if not cfxReconMode.isGroupStillAlive(gName) then 
			-- remove mark, remove group from set 
			table.insert(toRemove, args)
		end
	end 
	
	for idx, args in pairs(toRemove) do 
		cfxReconMode.removeMarkForArgs(args)
		trigger.action.outText("+++recn: removed mark: " .. args[5], 30)
	end
end

-- event handler 
function cfxReconMode:onEvent(event) 
	if not event then return end 
	if not event.initiator then return end 
	local theUnit = event.initiator 
	
	-- we simply add scouts as they are garbage-collected 
	-- every so often when they do not exist 
	if event.id == 15 or -- birth
	   event.id == 3 -- take-off. should already have been taken 
	                 -- care of by birth, but you never know 
	then
		-- check if a side must not have scouts.
		-- this will prevent player units to auto-
		-- scout when they are on that side. in that case
		-- you must add manually
		local theSide = theUnit:getCoalition()
		if theSide == 0 and not cfxReconMode.greyScouts then 
			return -- grey scouts are not allowed
		end
		if theSide == 1 and not cfxReconMode.redScouts then 
			return -- grey scouts are not allowed
		end
		if theSide == 2 and not cfxReconMode.blueScouts then 
			return -- grey scouts are not allowed
		end
		
		if cfxReconMode.playerOnlyRecon then 
			if not theUnit:getPlayerName() then 
				return -- only players can do recon. this unit is AI
			end
		end
		if cfxReconMode.verbose then 
			trigger.action.outText("+++rcn: event " .. event.id .. " for unit " .. theUnit:getName(), 30)
		end 
		cfxReconMode.addScout(theUnit)
	end
end

--
-- read all existing planes 
-- 
function cfxReconMode.processScoutGroups(theGroups)
	for idx, aGroup in pairs(theGroups) do 
		-- process all planes in that group 
		-- we are very early in the mission, only few groups really 
		-- exist now, the rest of the units come in with 15 event
		if aGroup:isExist() then 
			local allUnits = Group.getUnits(aGroup)
			for idy, aUnit in pairs (allUnits) do 
				if aUnit:isExist() then 
					cfxReconMode.addScout(aUnit)
					if cfxReconMode.verbose then
						trigger.action.outText("+++rcn: added unit " ..aUnit:getName() .. " to pool at startup", 30)
					end 
				end
			end
		end
	end
end

function cfxReconMode.initScouts()
	-- get all groups of aircraft. Unrolled loop 0..2 
	local theAirGroups = {}  
	if cfxReconMode.greyScouts then
		theAirGroups = coalition.getGroups(0, 0) -- 0 = aircraft
		cfxReconMode.processScoutGroups(theAirGroups) 
	end
	if cfxReconMode.redScouts then
		theAirGroups = coalition.getGroups(1, 0) -- 1 = red, 0 = aircraft
		cfxReconMode.processScoutGroups(theAirGroups) 
	end
	
	if cfxReconMode.blueScouts then
		theAirGroups = coalition.getGroups(2, 0) -- 2 = blue, 0 = aircraft
		cfxReconMode.processScoutGroups(theAirGroups) 
	end
end

--
-- read config 
--
function cfxReconMode.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("reconModeConfig") 
	if not theZone then 
		if cfxReconMode.verbose then
			trigger.action.outText("+++rcn: no config zone!", 30) 
		end 
		theZone = cfxZones.createSimpleZone("reconModeConfig")
	else  
		if cfxReconMode.verbose then 
			trigger.action.outText("+++rcn: found config zone!", 30) 
		end 
	end 
	
	cfxReconMode.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)

	cfxReconMode.autoRecon = cfxZones.getBoolFromZoneProperty(theZone, "autoRecon", true)
	cfxReconMode.redScouts = cfxZones.getBoolFromZoneProperty(theZone, "redScouts", false)
	cfxReconMode.blueScouts = cfxZones.getBoolFromZoneProperty(theZone, "blueScouts", true)	
	cfxReconMode.greyScouts = cfxZones.getBoolFromZoneProperty(theZone, "greyScouts", false)
	cfxReconMode.playerOnlyRecon = cfxZones.getBoolFromZoneProperty(theZone, "playerOnlyRecon", false)
	cfxReconMode.reportNumbers = cfxZones.getBoolFromZoneProperty(theZone, "reportNumbers", true)
		
	cfxReconMode.detectionMinRange = cfxZones.getNumberFromZoneProperty(theZone, "detectionMinRange", 3000)
	cfxReconMode.detectionMaxRange = cfxZones.getNumberFromZoneProperty(theZone, "detectionMaxRange", 12000)
	cfxReconMode.maxAlt = cfxZones.getNumberFromZoneProperty(theZone, "maxAlt", 9000)
	
	if cfxZones.hasProperty(theZone, "prio+") then 
		cfxReconMode.prioFlag = cfxZones.getStringFromZoneProperty(theZone, "prio+", "none")
	end
	
	if cfxZones.hasProperty(theZone, "detect+") then 
		cfxReconMode.detectFlag = cfxZones.getStringFromZoneProperty(theZone, "detect+", "none")
	end
	
	
	cfxReconMode.applyMarks = cfxZones.getBoolFromZoneProperty(theZone, "applyMarks", true)
	cfxReconMode.announcer = cfxZones.getBoolFromZoneProperty(theZone, "announcer", true)
	-- trigger.action.outText("recon: announcer is " .. dcsCommon.bool2Text(cfxReconMode.announcer), 30) -- announced
	if cfxZones.hasProperty(theZone, "reconSound") then 
		cfxReconMode.reconSound = cfxZones.getStringFromZoneProperty(theZone, "reconSound", "<nosound>")
	end
	
	cfxReconMode.removeWhenDestroyed = cfxZones.getBoolFromZoneProperty(theZone, "autoRemove", true)
	
end

--
-- start 
--
function cfxReconMode.start()
	-- lib check 
	if not dcsCommon.libCheck("cfx Recon Mode", 
		cfxReconMode.requiredLibs) then
		return false 
	end
	
	-- read config 
	cfxReconMode.readConfigZone()
	
	-- gather exiting planes 
	cfxReconMode.initScouts()
	
	-- start update cycle
	cfxReconMode.updateQueues()
	
	-- if dead groups are removed from map,
	-- schedule housekeeping 
	if cfxReconMode.removeWhenDestroyed then 
		cfxReconMode.autoRemove()
	end
	
	if cfxReconMode.autoRecon then 
		-- install own event handler to detect 
		-- when a unit takes off and add it to scout
		-- roster 
		world.addEventHandler(cfxReconMode)
	end
	
	trigger.action.outText("cfx Recon version " .. cfxReconMode.version .. " started.", 30)
	return true
end

--
-- test callback 
--
function cfxReconMode.demoReconCB(reason, theSide, theScout, theGroup, theName)
	trigger.action.outText("recon CB: " .. reason .. " -- " .. theScout:getName() .. " spotted " .. theName, 30)
end

if not cfxReconMode.start() then 
	cfxReconMode = nil
end

-- debug: wire up my own callback
-- cfxReconMode.addCallback(cfxReconMode.demoReconCB)


--[[--

ideas:
 
- renew lease. when already sighted, simply renew lease, maybe update location.
- update marks and renew lease 
TODO: red+ and blue+ - flags to increase when a plane of the other side is detected

 
--]]--


 
 