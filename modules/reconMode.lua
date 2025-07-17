cfxReconMode = {}
cfxReconMode.version = "2.5.1"
cfxReconMode.verbose = false -- set to true for debug info  
cfxReconMode.reconSound = "UI_SCI-FI_Tone_Bright_Dry_20_stereo.wav" -- to be played when somethiong discovered

cfxReconMode.prioList = {} -- group names that are high prio and generate special event
cfxReconMode.blackList = {} -- group names that are NEVER detected. Comma separated strings, e.g. {"Always Hidden", "Invisible Group"}
cfxReconMode.dynamics = {} -- if a group name is dynamic
cfxReconMode.zoneInfo = {} -- additional zone info 

cfxReconMode.scoutZones = {} -- zones that define aircraft. used for late eval of players 
cfxReconMode.allowedScouts = {} -- when not using autoscouts 
cfxReconMode.blindScouts = {} -- to exclude aircraft from being scouts 
cfxReconMode.removeWhenDestroyed = true 
cfxReconMode.activeMarks = {} -- all marks and their groups, indexed by groupName 

cfxReconMode.objects = {} -- objects that can be scouted 
cfxReconMode.reconZones = {} -- all "recon" zones, used for clone zones to add statics 

cfxReconMode.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
cfxReconMode.name = "cfxReconMode" -- to be compatible with test flags 

--[[--
VERSION HISTORY
 2.0.0 - DML integration prio+-->prio! detect+ --> detect! 
         and method
	   - changed access to prio and blacklist to hash
	   - dynamic option for prio and black 
	   - trigger zones for designating prio and blacklist 
	   - reworked stringInList to also include dynamics 
	   - Report in SALT format: size, action, loc, time.
	   - Marks add size, action info
	   - LatLon or MGRS
	   - MGRS option in config 
	   - filter onEvent for helo and aircraft 
	   - allowedScouts and blind 
	   - stronger scout filtering at startup 
	   - better filtering on startup when autorecon and playeronly
	   - player lazy late checking, zone saving 
	   - correct checks when not autorecon 
	   - ability to add special flags to recon prio group 
	   - event guard in onEvent
	   - <t> wildcard 
	   - <lat>, <lon>, <mgrs> wildcards 
 2.0.1 - getGroup() guard for onEvent(). Objects now seem to birth. 
 2.1.0 - processZoneMessage uses group's position, not zone
       - silent attribute for priority targets 
	   - activate / deactivate by flags 
 2.1.1 - Lat Lon and MGRS also give Elevation
       - cfxReconMode.reportTime
 2.1.2 - imperialUnits for elevation
       - <ele> wildcard in message format 
	   - fix for mgrs bug in message (zone coords, not unit)
 2.1.3 - added cfxReconMode.name to allow direct acces with test zone flag 
 2.1.4 - canDetect() also checks if unit has been activated
         canDetect has strenghtened isExist() guard 
 2.2.0 - new marksLocked config attribute, defaults to false
	   - new marksFadeAfter config attribute to control mark time 
	   - dmlZones OOP upgrade 
 2.2.1 - fixed "cfxReconSMode" typo 
 2.2.2 - added groupNames attribute 
       - clean-up
 2.3.0 - support for towns/twn when present 
 2.3.1 - simplified reading config 
 2.4.0 - added "ground" and "naval" attributes 
	   - SALT diffs between vehicles and vessels 
	   - SALT "s" for plural if > 1 vehicle/vessel 
	   - de-optimized naval visibility check 
	   - optimization for group check if seen before 
	   - new bearing and distance callout from pilot 
2.5.0  - recon zones also collect static objects 
	   - reconMessage keyword 
	   - recognize values other than black* and prio* 
	   - SALT etc for isStatic 
2.5.1  - staticWasCloned()
	   - filtering statics 
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
cfxReconMode.method = "inc"
cfxReconMode.applyMarks = true 
cfxReconMode.mgrs = false 

cfxReconMode.ups = 1 -- updates per second.
cfxReconMode.scouts = {} -- units that are performing scouting.
cfxReconMode.processedScouts = {} -- for managing performance: queue
cfxReconMode.detectedGroups = {} -- so we know which have been detected
	-- also used for static objects!
cfxReconMode.marksFadeAfter = 30*60 -- after detection, marks disappear after
                     -- this amount of seconds. -1 means no fade
					 -- 60 is one minute

cfxReconMode.callbacks = {} -- sig: cb(reason, side, scout, group)
cfxReconMode.uuidCount = 0 -- for unique marks 

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
function cfxReconMode.addToPrioList(aGroup, dynamic)
	if not dynamic then dynamic = false end 
	if not aGroup then return end 
	if type(aGroup) == "table" and aGroup.getName then 
		aGroup = aGroup:getName()
	end
	if type(aGroup) == "string" then 
		cfxReconMode.prioList[aGroup] = aGroup
		cfxReconMode.dynamics[aGroup] = dynamic 
	end
end

function cfxReconMode.addToBlackList(aGroup, dynamic)
	if not dynamic then dynamic = false end 
	if not aGroup then return end 
	if type(aGroup) == "table" and aGroup.getName then 
		aGroup = aGroup:getName()
	end
	if type(aGroup) == "string" then 
		cfxReconMode.blackList[aGroup] = aGroup
		cfxReconMode.dynamics[aGroup] = dynamic
	end
end

function cfxReconMode.addToAllowedScoutList(aGroup, dynamic)
	if not dynamic then dynamic = false end 
	if not aGroup then return end 
	if type(aGroup) == "table" and aGroup.getName then 
		aGroup = aGroup:getName()
	end
	if type(aGroup) == "string" then 
		cfxReconMode.allowedScouts[aGroup] = aGroup
		cfxReconMode.dynamics[aGroup] = dynamic
	end
end

function cfxReconMode.addToBlindScoutList(aGroup, dynamic)
	if not dynamic then dynamic = false end 
	if not aGroup then return end 
	if type(aGroup) == "table" and aGroup.getName then 
		aGroup = aGroup:getName()
	end
	if type(aGroup) == "string" then 
		cfxReconMode.blindScouts[aGroup] = aGroup
		cfxReconMode.dynamics[aGroup] = dynamic
	end
end

function cfxReconMode.isStringInList(theString, theList)
	-- returns two values: inList, and original group name (if exist)
	if not theString then return false, nil end 
	if type(theString) ~= "string" then return false, nil end
	if not theList then return false, nil end 
	
	-- first, try a direct look-up. if this produces a hit
	-- we directly return true 
	if theList[theString] then return true, theString end 
	
	-- now try the more involved retrieval with string starts with 
	for idx, aName in pairs(theList) do 
		if dcsCommon.stringStartsWith(theString, aName) then 
			-- they start the same. are dynamics allowed?
			if cfxReconMode.dynamics[aName] then 
				return true, aName 
			end
		end
	end
	
	return false, nil
end


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
		trigger.action.outText("+++rcn: WARNING - nil Unit on remove", 30)
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


function cfxReconMode.canDetectObject(scoutPos, theObj, visRange) 
	if Object.isExist(theObj) and theObj:getLife() >= 1 then 
		local oPos = theObj:getPoint()
		oPos.y = oPos.y + 10 -- raise my 10 meters -- for LOS calc
		local d = math.floor(dcsCommon.distFlat(scoutPos, oPos)) 
		if d < visRange then 
			-- is in visual range. do we have LOS?
			if land.isVisible(scoutPos, oPos) then 
				-- group is visible, stop here, return true
				return true, oPos
			end
		end
	end
	return false, nil 
end

function cfxReconMode.canDetect(scoutPos, theGroup, visRange)
	-- determine if a member of theGroup can be seen from 
	-- scoutPos at visRange 
	-- returns true and pos when detected
	local cat = theGroup:getCategory()
	local allUnits = theGroup:getUnits()
	for idx, aUnit in pairs(allUnits) do
		if Unit.isExist(aUnit) and aUnit:isActive() and aUnit:getLife() >= 1 then 
			local uPos = aUnit:getPoint()
			uPos.y = uPos.y + 3 -- raise my 3 meters
			local d = math.floor(dcsCommon.distFlat(scoutPos, uPos)) 
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
				-- only for land units, not naval since they are 
				-- usually dispersed
				if cat == 2 then 
					return false, nil
				end 
			end
		end		
	end
	return false, nil -- nothing visible
end

function cfxReconMode.placeMarkForUnit(location, theSide, theGroup, isStatic) 
	local theID = cfxReconMode.uuid()
	local theDesc = "Contact" 
	if cfxReconMode.groupNames then theDesc = theDesc .. ": " ..theGroup:getName() end 
	if cfxReconMode.reportNumbers then 
		if isStatic then 
			theDesc = theDesc .. " - " .. cfxReconMode.getSit(theGroup, isStatic) .. "."
		else 
			theDesc = theDesc .. " - " .. cfxReconMode.getSit(theGroup, isStatic) .. ", " .. cfxReconMode.getAction(theGroup) .. "."
		end 
	end
	trigger.action.markToCoalition(
					theID, 
					theDesc, 
					location, 
					theSide, 
					cfxReconMode.marksLocked, -- readOnly -- false, 
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

function cfxReconMode.getSit(theGroup, isStatic)
	local cat = theGroup:getCategory()
	local msg = ""
	if isStatic then 
		-- static objects have very limited info 
		
	else 
		-- analyse the group we just discovered. We know it's a ground troop, so simply differentiate between vehicles and infantry 
		local theUnits = theGroup:getUnits()
		local numInf = 0 
		local numVehicles = 0 
		for idx, aUnit in pairs(theUnits) do 
			if dcsCommon.unitIsInfantry(aUnit) then 
				numInf = numInf + 1
			else 
				numVehicles = numVehicles + 1
			end 
		end
		if numInf > 0 and numVehicles > 0 then 
			-- mixed infantry and vehicles 
			msg = numInf .. " infantry and " .. numVehicles 
			if cat == 2 then msg = msg .. " vehicles" else msg = msg .. " vessels" end  
		elseif numInf > 0 then
			-- only infantry
			msg = numInf .. " infantry"
		else 
			-- only vehicles
			msg = numVehicles --.. " vehicles"
			if cat == 2 then msg = msg .. " vehicle" else msg = msg .. " vessel" end
			if numVehicles > 1 then msg = msg .. "s" end 
		end 
	end
	return msg
end

function cfxReconMode.getAction(theGroup) 
	local msg = ""
	-- simply get the first unit and get velocity vector. 
	-- if it's smaller than 1 m/s (= 3.6 kmh), it's "Guarding", if it's faster, it's 
	-- moving with direction
	local theUnit = theGroup:getUnit(1)
	local vvel = theUnit:getVelocity()
	local vel = dcsCommon.vMag(vvel)
	if vel < 1 then 
		msg = "apparently guarding"
	else
		local speed = ""
		if vel < 3 then speed = "slowly"
		elseif vel < 6 then speed = "deliberately"
		else speed = "briskly" end 
		local heading = dcsCommon.getUnitHeading(theUnit) -- in rad 
		msg = speed .. " moving " .. dcsCommon.bearing2compass(heading)
	end
	return msg
end

function cfxReconMode.getLocation(theGroup, isStatic)
	local msg = ""
	local currPoint
	if isStatic then 
		currPoint = theGroup:getPoint() -- is a static
	else 
		local theUnit = theGroup:getUnit(1)
		currPoint = theUnit:getPoint()
	end
	local ele = math.floor(land.getHeight({x = currPoint.x, y = currPoint.z}))
	local units = "m"
	if cfxReconMode.imperialUnits then 
		ele = math.floor(ele * 3.28084) -- feet 
		units = "ft"
	else 
		ele = math.floor(ele) -- meters 
	end 
	
	if cfxReconMode.mgrs then 
		local grid = coord.LLtoMGRS(coord.LOtoLL(currPoint))
		msg = grid.UTMZone .. ' ' .. grid.MGRSDigraph .. ' ' .. grid.Easting .. ' ' .. grid.Northing .. " Ele " .. ele .. units
	else 
		local lat, lon, alt = coord.LOtoLL(currPoint)
		lat, lon = dcsCommon.latLon2Text(lat, lon)
		msg = "Lat " .. lat .. " Lon " .. lon .. " Ele " .. ele ..units
	end
	
	if twn and towns then 
		units = "km"
		local village, data, dist = twn.closestTownTo(currPoint)
		if cfxReconMode.imperialUnits then 
			dist = dist * 0.539957 -- nm conversion 
			units = "nm"
		end 
		dist = math.floor(dist/100) / 10 
		local bear = dcsCommon.compassPositionOfARelativeToB(currPoint, data.p)
		msg = msg .. ", " .. dist .. units .. " " .. bear .. " of " .. village
	end 
	return msg
end

function cfxReconMode.getTimeData()
	local msg = ""
	local absSecs = timer.getAbsTime()-- + env.mission.start_time
	while absSecs > 86400 do 
		absSecs = absSecs - 86400 -- subtract out all days 
	end
	msg = dcsCommon.processHMS("<:h>:<:m>:<:s>", absSecs)
	return "at " .. msg
end

function cfxReconMode.generateSALT(theScout, theGroup, isStatic)
	local cat = theGroup:getCategory() -- 2 (gnd) or 3 (naval)
	local msg = theScout:getName() .. " reports new "
	if isStatic then msg = theScout:getName() .. " reports eyes on"
	elseif cat == 2 then msg = msg .. "ground contact" 
	else msg = msg .. "surface contact" end  
	if cfxReconMode.groupNames or isStatic then msg = msg .. " " .. theGroup:getName() end 
	-- at bearing and dist 
	local p = theScout:getPoint()
	local up 
	if isStatic then 
		up = theGroup:getPoint() -- group is a static
	else 
		local theUnit = dcsCommon.getFirstLivingUnit(theGroup)
		up = theUnit:getPoint()
	end
--	local d = math.floor(dcsCommon.dist(p, up)/1000)
	local dg = math.floor(dcsCommon.distFlat(p, up)/1000)
	local b = dcsCommon.bearingInDegreesFromAtoB(p, up)
	msg = msg .. ", bearing " .. b .. "°, " .. dg .. "km.\n"
--	msg = msg .. ":\n"
-- SALT: S = Situation or number of units A = action they are doing L = Location T = Time 
	
	if isStatic then
--		msg = msg .. cfxReconMode.getSit(theGroup, isStatic) .. -- S
		-- no individual Action report
		msg = msg .. "Installation appears mostly intact. "
	else
		msg = msg .. cfxReconMode.getSit(theGroup, isStatic) .. ", "-- S
		msg = msg .. cfxReconMode.getAction(theGroup) .. ", " -- A 
	end
	msg = msg .. cfxReconMode.getLocation(theGroup, isStatic) .. ", " -- L 
	msg = msg .. cfxReconMode.getTimeData() -- T

	return msg
end

function cfxReconMode.processZoneMessage(inMsg, theZone, theGroup) 
	if not inMsg then return "<nil inMsg>" end
	local formerType = type(inMsg)
	if formerType ~= "string" then inMsg = tostring(inMsg) end  
	if not inMsg then inMsg = "<inMsg is incompatible type " .. formerType .. ">" end 
	local outMsg = ""
	-- replace line feeds 
	outMsg = inMsg:gsub("<n>", "\n")
	if theZone then 
		outMsg = outMsg:gsub("<z>", theZone.name)
	end
	-- replace <t> with current mission time HMS
	local absSecs = timer.getAbsTime()-- + env.mission.start_time
	while absSecs > 86400 do 
		absSecs = absSecs - 86400 -- subtract out all days 
	end
	local timeString  = dcsCommon.processHMS("<:h>:<:m>:<:s>", absSecs)
	outMsg = outMsg:gsub("<t>", timeString)
	
	-- replace <lat> with lat of zone point and <lon> with lon of zone point 
	-- and <mgrs> with mgrs coords of zone point 
	local currPoint = theZone:getPoint()
	if theGroup and theGroup:isExist() then 
		-- only use group's point when group exists and alive 
		local theUnit = dcsCommon.getFirstLivingUnit(theGroup)
		currPoint = theUnit:getPoint()
	end
	local ele = math.floor(land.getHeight({x = currPoint.x, y = currPoint.z}))
	local units = "m"
	if cfxReconMode.imperialUnits then 
		ele = math.floor(ele * 3.28084) -- feet 
		units = "ft"
	else 
		ele = math.floor(ele) -- meters 
	end 
	
	local lat, lon, alt = coord.LOtoLL(currPoint)
	lat, lon = dcsCommon.latLon2Text(lat, lon)
	outMsg = outMsg:gsub("<lat>", lat)
	outMsg = outMsg:gsub("<lon>", lon)
	outMsg = outMsg:gsub("<ele>", ele..units)
	--currPoint = cfxZones.getPoint(theZone)
	local grid = coord.LLtoMGRS(coord.LOtoLL(currPoint))
	local mgrs = grid.UTMZone .. ' ' .. grid.MGRSDigraph .. ' ' .. grid.Easting .. ' ' .. grid.Northing
	outMsg = outMsg:gsub("<mgrs>", mgrs)
	return outMsg
end

function cfxReconMode.detectedObject(mySide, theScout, theObj, theLoc)
	cfxReconMode.detectedGroup(mySide, theScout, theObj, theLoc, true)
end

function cfxReconMode.detectedGroup(mySide, theScout, theGroup, theLoc, isStatic)
	-- see if it was a prio target and gather info 
	local inList, gName = cfxReconMode.isStringInList(theGroup:getName(), cfxReconMode.prioList)
	local silent = false 
	local isPrio = false 
	if gName and cfxReconMode.zoneInfo[gName] then 
		local zInfo = cfxReconMode.zoneInfo[gName] -- connected for statics as well
		silent = zInfo.silent
		isPrio = zInfo.isPrio
	end

	-- put a mark on the map 
	if (not silent) and cfxReconMode.applyMarks then 
		local theID = cfxReconMode.placeMarkForUnit(theLoc, mySide, theGroup, isStatic)
		local gName = theGroup:getName()
		local args = {mySide, theScout, theGroup, theID, gName, isStatic}
		cfxReconMode.activeMarks[gName] = args
		-- schedule removal if desired 
		if cfxReconMode.marksFadeAfter > 0 then 	
			timer.scheduleFunction(cfxReconMode.removeMarkForArgs, args, timer.getTime() + cfxReconMode.marksFadeAfter)
		end
	end 
	
	-- say something
	if (not silent) and cfxReconMode.announcer then 
		local msg = cfxReconMode.generateSALT(theScout, theGroup, isStatic)
		trigger.action.outTextForCoalition(mySide, msg, cfxReconMode.reportTime)
		if cfxReconMode.verbose then 
			trigger.action.outText("+++rcn: announced for side " .. mySide, 30)
		end 
		-- play a sound 
		trigger.action.outSoundForCoalition(mySide, cfxReconMode.reconSound)
	else 
	end 
	
	-- see if it was a prio target 
	if inList or isStatic then
		if cfxReconMode.verbose then 
			trigger.action.outText("+++rcn: Priority/static target spotted",	30)
		end 
		if isPrio then 
			-- invoke callbacks
			cfxReconMode.invokeCallbacks("priority", mySide, theScout, theGroup, theGroup:getName())
			
			-- update prio flag 
			if cfxReconMode.prioFlag then 
				cfxReconMode.theZone:pollFlag(cfxReconMode.prioFlag, cfxReconMode.method )
			end
		end
		
		-- see if we were passed additional info in zInfo 
		if gName and cfxReconMode.zoneInfo[gName] then 
			local zInfo = cfxReconMode.zoneInfo[gName]
			if zInfo.prioMessage then 
				-- prio message displays even when announcer is off
				-- AND EVEN WHEN SILENT!!!
				local msg = zInfo.prioMessage
				msg = cfxReconMode.processZoneMessage(msg, zInfo.theZone, theGroup) 
				trigger.action.outTextForCoalition(mySide, msg, cfxReconMode.reportTime)
				if cfxReconMode.verbose or zInfo.theZone.verbose then 
					trigger.action.outText("+++rcn: prio message sent for prio target zone <" .. zInfo.theZone.name .. ">",30)
				end
			end
			
			if zInfo.theFlag then 
				zInfo.theZone:pollFlag(zInfo.theFlag, cfxReconMode.method)
				if cfxReconMode.verbose or zInfo.theZone.verbose then 
					trigger.action.outText("+++rcn: banging <" .. zInfo.theFlag .. "> for prio target zone <" .. zInfo.theZone.name .. ">",30)
				end
			end 
		end
	else 
		-- invoke callbacks
		cfxReconMode.invokeCallbacks("detected", mySide, theScout, theGroup, theGroup:getName())
	
		-- increase normal flag 
		if cfxReconMode.detectFlag then 
			cfxReconMode.theZone:pollFlag(cfxReconMode.detectFlag, cfxReconMode.method)
		end
	end
end

function cfxReconMode.staticWasCloned(theStatic)
	-- check if that static is in any of my recon zones 
	local loc = theStatic:getPoint()
	local sName = theStatic:getName()
	for zname, theZone in pairs(cfxReconMode.reconZones) do 
		if theZone:pointInZone(loc) then 
			if cfxReconMode.verbose or theZone.verbose then 
				trigger.action.outText("+++rcn: cloner spawned static <" .. sName .. "> in recon zone <" .. theZone.name .. ">. proccing.", 30)
			end
			cfxReconMode.objects[sName] = theStatic
		end 
	end
end

function cfxReconMode.performReconForUnit(theScout)
	if not theScout then return end 
	if not theScout:isExist() then return end -- will be gc'd soon
	-- get altitude above ground to calculate visual range 
	local alt = math.floor(dcsCommon.getUnitAGL(theScout))
	local visRange = math.floor(dcsCommon.lerp(cfxReconMode.detectionMinRange, cfxReconMode.detectionMaxRange, alt/cfxReconMode.maxAlt))
	local scoutPos = theScout:getPoint()
	-- figure out which groups we are looking for
	local myCoal = theScout:getCoalition()
	local enemyCoal = 1 
	if myCoal == 1 then enemyCoal = 2 end 

	-- first, scan all static objects for a match 
	local filtered = {}
	for objName, obj in pairs(cfxReconMode.objects) do 
		local existing = StaticObject.getByName(objName)
		if existing and Object.isExist(existing) then 
			if not cfxReconMode.detectedGroups[objName] then 
--				trigger.action.outText("reconning named <" .. objName .. ">", 30)
				local oCoa = obj:getCoalition() 
				if oCoa ~= myCoal then 
					local visible, location = cfxReconMode.canDetectObject(scoutPos, obj, visRange)
					if visible then 
						-- blacklist check
						-- visible, not yet seen, not blacklisted 
						-- perhaps add some percent chance now 
						-- remember that we know this group 
						cfxReconMode.detectedGroups[objName] = obj
						cfxReconMode.detectedObject(myCoal, theScout, obj, location)
						return -- stop, as we only detect one item per pass
					end				
				end 
			end
			filtered[objName] = existing
		else 
			-- static object named objName does NOT exist any more.
			if cfxReconMode.verbose then 
				trigger.action.outText("+++rcn: object <" .. objName .. "> does not exist in performReconForUnit().", 30)
			end 
		end
	end 
	cfxReconMode.objects = filtered -- only when fully completed pass 
	-- iterate all enemy units until we find one 
	-- and then stop this iteration (can only detect one 
	-- group per pass)
	local enemyGroups = coalition.getGroups(enemyCoal)
	for idx, theGroup in pairs (enemyGroups) do 
		-- make sure it's a ground unit 
		local cat = theGroup:getCategory()
		local isGround = cfxReconMode.rGround and cat == 2
		local isNaval = cfxReconMode.rNaval and cat == 3 
		local found = isGround or isNaval
		local groupName = theGroup:getName()
		found = found and (not cfxReconMode.detectedGroups[groupName]) -- optimization: skip if already detected 
		if found then 
			local visible, location = cfxReconMode.canDetect(scoutPos, theGroup, visRange)
			if visible then 
				-- blacklist check
				local inList, gName = cfxReconMode.isStringInList(groupName, cfxReconMode.blackList) 
				if not inList then 
					-- visible, not yet seen, not blacklisted 
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

function cfxReconMode.doActivate()
	cfxReconMode.active = true 
	if cfxReconMode.verbose then 
		trigger.action.outText("Recon Mode has activated", 30)
	end 
end

function cfxReconMode.doDeActivate()
	cfxReconMode.active = false 
	if cfxReconMode.verbose then 
		trigger.action.outText("Recon Mode is OFF", 30)
	end
end

function cfxReconMode.updateQueues()
	-- schedule next call 
	timer.scheduleFunction(cfxReconMode.updateQueues, {}, timer.getTime() + 1/cfxReconMode.ups)
	
	-- check to turn on or off
	-- check the flags for on/off
	if cfxReconMode.activate then 
		if cfxZones.testZoneFlag(cfxReconMode, 				cfxReconMode.activate, "change","lastActivate") then
			cfxReconMode.doActivate()
		end
	end
	
	if cfxReconMode.deactivate then 
		if cfxZones.testZoneFlag(cfxReconMode, 				cfxReconMode.deactivate, "change","lastDeActivate") then
			cfxReconMode.doDeActivate()
		end
	end
	
	-- check if we are active 
	if not cfxReconMode.active then return end 
	
	
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
	local theStatic = StaticObject.getByName(gName)
	if theStatic and theStatic:getLife() >= 1 then return true end 
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
--	timer.scheduleFunction(cfxReconMode.autoRemove, {}, timer.getTime() + 1/cfxReconMode.ups)
	timer.scheduleFunction(cfxReconMode.autoRemove, {}, timer.getTime() + 10) -- every 10 seconds
	
	local toRemove = {}
	-- scan all marked groups, and when they no longer exist, remove them 
	for idx, args in pairs (cfxReconMode.activeMarks) do
		local gName = args[5]
		if not cfxReconMode.isGroupStillAlive(gName) then 
			-- remove mark, remove group from set 
			table.insert(toRemove, args)
		end
	end 
	
	for idx, args in pairs(toRemove) do 
		cfxReconMode.removeMarkForArgs(args)
--		trigger.action.outText("+++recn: removed mark: " .. args[5], 30)
	end
end

-- late eval player 
function cfxReconMode.lateEvalPlayerUnit(theUnit)
	-- check if a player is inside one of the scout zones 
	-- first: quick check if the player is already in a list 
	local aGroup = theUnit:getGroup() 
	local gName = aGroup:getName()
	if cfxReconMode.allowedScouts[gName] then return end 
	if cfxReconMode.blindScouts[gName] then return end 

	-- get location 
	local p = theUnit:getPoint()
	
	-- iterate all scoutZones
	for idx, theZone in pairs (cfxReconMode.scoutZones) do 
		local isScout = theZone.isScout
		local dynamic = theZone.dynamic
		local inZone = theZone:pointInZone(p)
		if inZone then 
			if isScout then 
				cfxReconMode.addToAllowedScoutList(aGroup, dynamic)
				if cfxReconMode.verbose or theZone.verbose then 
					if dynamic then 
						trigger.action.outText("+++rcn: added LATE DYNAMIC PLAYER" .. gName .. " to allowed scouts", 30)
					else 
						trigger.action.outText("+++rcn: added LATE PLAYER " .. gName .. " to allowed scouts", 30) 
					end
				end 
			else 
				cfxReconMode.addToBlindScoutList(aGroup, dynamic)
				if cfxReconMode.verbose or theZone.verbose then 
					if dynamic then 
						trigger.action.outText("+++rcn: added LATE DYNAMIC PLAYER" .. gName .. " to BLIND scouts list", 30)
					else 
						trigger.action.outText("+++rcn: added LATE PLAYER " .. gName .. " to BLIND scouts list", 30)
					end
				end
			end
			return -- we stop after first found 
		end
	end
end

-- event handler 
function cfxReconMode:onEvent(event) 
	if not event then return end 
	if not event.initiator then return end 
	if not (event.id == 15 or event.id == 3) then return end 
	
	local theUnit = event.initiator 
	if not theUnit:isExist() then return end 
	if not theUnit.getGroup then 
		-- strange, but seemingly can happen
		return 
	end 
	local theGroup = theUnit:getGroup() 

	if not theGroup then return end 
	local gCat = theGroup:getCategory()
	-- only continue if cat = 0 (aircraft) or 1 (helo)
	if gCat > 1 then return end 
	
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
		
		local isPlayer = theUnit:getPlayerName()
		if isPlayer then  
			-- since players wake up late, we lazy-eval their group
			-- and add it to the blind/scout lists
			cfxReconMode.lateEvalPlayerUnit(theUnit)
			if cfxReconMode.verbose then 
				trigger.action.outText("+++rcn: late player check complete for <" .. theUnit:getName() .. ">", 30)
			end
		else 
			isPlayer = false -- safer than sorry
		end 
		
		if cfxReconMode.autoRecon then 
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
				if not isPlayer then 
					if cfxReconMode.verbose then 
						trigger.action.outText("+++rcn: <" .. theUnit:getName() .. "> filtered: no player unit", 30)
					end 
					return -- only players can do recon. this unit is AI
				end
			end
		end 
		
		-- check if cfxReconMode.autoRecon is enabled
		-- otherwise, abort the aircraft is not in 
		-- scourlist 
		local gName = theGroup:getName()
		if not cfxReconMode.autoRecon then 
			-- no auto-recon. plane must be in scouts list 
			local inList, ignored = cfxReconMode.isStringInList(gName, cfxReconMode.allowedScouts)
			if not inList then 
				if cfxReconMode.verbose then 
					trigger.action.outText("+++rcn: <" .. theUnit:getName() .. "> filtered: not in scout list", 30)
				end
				return 
			end
		end
		
		-- check if aircraft is in blindlist 
		-- abort if so 
		local inList, ignored = cfxReconMode.isStringInList(gName, cfxReconMode.blindScouts)
		if inList then 
			if cfxReconMode.verbose then 
				trigger.action.outText("+++rcn: <" .. theUnit:getName() .. "> filtered: unit cannot scout", 30)
			end
			return 
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
			-- see if we want to add these aircraft to the 
			-- active scout list 
			
			local gName = aGroup:getName()
			local isBlind, ignored = cfxReconMode.isStringInList(gName, cfxReconMode.blindScouts)
			local isScout, ignored = cfxReconMode.isStringInList(gName, cfxReconMode.allowedScouts)
			
			local doAdd = cfxReconMode.autoRecon
			if cfxReconMode.autoRecon then 
				local theSide = aGroup:getCoalition()
				if theSide == 0 and not cfxReconMode.greyScouts then
					doAdd = false 
				elseif theSide == 1 and not cfxReconMode.redScouts then 
					doAdd = false 
				elseif theSide == 2 and not cfxReconMode.blueScouts then 
					doAdd = false 
				end 
			end
			
			if isBlind then doAdd = false end 
			if isScout then doAdd = true end -- overrides all 
			
			if doAdd then 
				local allUnits = Group.getUnits(aGroup)
				for idy, aUnit in pairs (allUnits) do 
					if aUnit:isExist() then 
						if cfxReconMode.autoRecon and cfxReconMode.playerOnlyRecon and (aUnit:getPlayerName() == nil)
						then
							if cfxReconMode.verbose then
								trigger.action.outText("+++rcn: skipped unit " ..aUnit:getName() .. " because not player unit", 30)
							end
						else
							cfxReconMode.addScout(aUnit)
							if cfxReconMode.verbose then
								trigger.action.outText("+++rcn: added unit " ..aUnit:getName() .. " to pool at startup", 30)
							end
						end
					end
				end
			else 
				if cfxReconMode.verbose then 
					trigger.action.outText("+++rcn: filtered group " .. gName .. " from being entered into scout pool at startup", 30)
				end
			end 
		end
	end
end

function cfxReconMode.initScouts()
	-- get all groups of aircraft. Unrolled loop 0..2 
	-- added helicopters, removed check for grey/red/bluescouts,
	-- as that happens in processScoutGroups 
	local theAirGroups = {}  
	theAirGroups = coalition.getGroups(0, 0) -- 0 = aircraft
	cfxReconMode.processScoutGroups(theAirGroups)
	theAirGroups = coalition.getGroups(0, 1) -- 1 = helicopter
	cfxReconMode.processScoutGroups(theAirGroups)

	theAirGroups = coalition.getGroups(1, 0) -- 0 = aircraft
	cfxReconMode.processScoutGroups(theAirGroups)
	theAirGroups = coalition.getGroups(1, 1) -- 1 = helicopter
	cfxReconMode.processScoutGroups(theAirGroups)

	theAirGroups = coalition.getGroups(2, 0) -- 0 = aircraft
	cfxReconMode.processScoutGroups(theAirGroups)
	theAirGroups = coalition.getGroups(2, 1) -- 1 = helicopter
	cfxReconMode.processScoutGroups(theAirGroups)
end

--
-- read config 
--
function cfxReconMode.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("reconModeConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("reconModeConfig")
	end 
	
	cfxReconMode.verbose = theZone.verbose --cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)

	cfxReconMode.autoRecon = theZone:getBoolFromZoneProperty("autoRecon", true)
	cfxReconMode.redScouts = theZone:getBoolFromZoneProperty("redScouts", false)
	cfxReconMode.blueScouts = theZone:getBoolFromZoneProperty( "blueScouts", true)	
	cfxReconMode.greyScouts = theZone:getBoolFromZoneProperty( "greyScouts", false)
	cfxReconMode.playerOnlyRecon = theZone:getBoolFromZoneProperty("playerOnlyRecon", false)
	cfxReconMode.reportNumbers = theZone:getBoolFromZoneProperty( "reportNumbers", true)
	cfxReconMode.reportTime = theZone:getNumberFromZoneProperty( "reportTime", 30)
	
	cfxReconMode.detectionMinRange = theZone:getNumberFromZoneProperty("detectionMinRange", 3000)
	cfxReconMode.detectionMaxRange = theZone:getNumberFromZoneProperty("detectionMaxRange", 12000)
	cfxReconMode.maxAlt = theZone:getNumberFromZoneProperty("maxAlt", 9000)
	
	if theZone:hasProperty("prio+") then -- deprecated. remove next update 
		cfxReconMode.prioFlag = theZone:getStringFromZoneProperty("prio+", "none")
	elseif theZone:hasProperty("prio!") then 
		cfxReconMode.prioFlag = theZone:getStringFromZoneProperty("prio!", "*<none>")
	end
	
	if theZone:hasProperty("detect+") then -- deprecated 
		cfxReconMode.detectFlag = theZone:getStringFromZoneProperty("detect+", "none")
	elseif theZone:hasProperty("detect!") then 
		cfxReconMode.detectFlag = theZone:getStringFromZoneProperty("detect!", "*<none>")
	end
	
	cfxReconMode.method = theZone:getStringFromZoneProperty("method", "inc")
	if theZone:hasProperty("reconMethod") then 
		cfxReconMode.method = theZone:getStringFromZoneProperty("reconMethod", "inc")
	end
	
	cfxReconMode.applyMarks = theZone:getBoolFromZoneProperty( "applyMarks", true)
	cfxReconMode.marksFadeAfter = theZone:getNumberFromZoneProperty("marksFadeAfter", 30*60) -- 30 minutes default 
	cfxReconMode.marksLocked = theZone:getBoolFromZoneProperty("marksLocked", false) -- if true, players cannot remove the marks
	cfxReconMode.announcer = theZone:getBoolFromZoneProperty( "announcer", true)

	if theZone:hasProperty("reconSound") then 
		cfxReconMode.reconSound = theZone:getStringFromZoneProperty("reconSound", "<nosound>")
	end
	
	cfxReconMode.removeWhenDestroyed = theZone:getBoolFromZoneProperty("autoRemove", true)
	
	cfxReconMode.mgrs = theZone:getBoolFromZoneProperty("mgrs", false)
	
	cfxReconMode.active = theZone:getBoolFromZoneProperty("active", true)
	if theZone:hasProperty("activate?") then 
		cfxReconMode.activate = theZone:getStringFromZoneProperty("activate?", "*<none>")
		cfxReconMode.lastActivate = theZone:getFlagValue(cfxReconMode.activate)
	elseif theZone:hasProperty("on?") then 
		cfxReconMode.activate = theZone:getStringFromZoneProperty("on?", "*<none>") 
		cfxReconMode.lastActivate = theZone:getFlagValue(cfxReconMode.activate)
	end
	
	if theZone:hasProperty("deactivate?") then 
		cfxReconMode.deactivate = theZone:getStringFromZoneProperty("deactivate?", "*<none>")
		cfxReconMode.lastDeActivate = theZone:getFlagValue(cfxReconMode.deactivate)
	elseif theZone:hasProperty("off?") then 
		cfxReconMode.deactivate = theZone:getStringFromZoneProperty("off?", "*<none>") 
		cfxReconMode.lastDeActivate = theZone:getFlagValue(cfxReconMode.deactivate)
	end
	
	cfxReconMode.imperialUnits = theZone:getBoolFromZoneProperty("imperial", false)
	if theZone:hasProperty("imperialUnits") then 
		cfxReconMode.imperialUnits = theZone:getBoolFromZoneProperty( "imperialUnits", false)
	end
	cfxReconMode.groupNames = theZone:getBoolFromZoneProperty( "groupNames", true)
	cfxReconMode.rGround = theZone:getBoolFromZoneProperty("ground", true)
	cfxReconMode.rNaval = theZone:getBoolFromZoneProperty("naval", false)
	cfxReconMode.theZone = theZone -- save this zone 
end

--
-- read blackList and prio list groups
--


function cfxReconMode.processReconZone(theZone) 
	local theList = theZone:getStringFromZoneProperty("recon", "prio")
	theList = string.upper(theList)
	local isBlack = dcsCommon.stringStartsWith(theList, "BLACK")
	local isPrio = dcsCommon.stringStartsWith(theList, "PRIO")
	local zInfo = {}
	zInfo.theZone = theZone
	zInfo.isBlack = isBlack		
	zInfo.silent = theZone:getBoolFromZoneProperty("silent", false)
	zInfo.isPrio = isPrio
	if cfxReconMode.verbose or theZone.verbose then 
		trigger.action.outText("+++rcn: recon zone <" .. theZone.name .. ">: prio=<" .. dcsCommon.bool2Text(isPrio)  .. ">, black = <" .. dcsCommon.bool2Text(isBlack)  .. ">", 30)
	end
	-- now collect all objects in zone unless it is a blacklist
	-- because objects arent detected otherwise anyway
	if not isBlack then 
		local allObjects = theZone:allObjectsInZone() -- collect static objects in zone
		for idx, theObj in pairs(allObjects) do 
			local theName = theObj:getName()
			cfxReconMode.objects[theName] = theObj 
			cfxReconMode.zoneInfo[theName] = zInfo -- connect zinfo
			if theZone.verbose or cfxReconMode.verbose then 
				trigger.action.outText("+++recon: added static <" .. theName .. "> in zone <" .. theZone.name .. ">", 30)
			end 
		end 
	end 
	
	if theZone:hasProperty("prioMessage") then 
		zInfo.prioMessage = theZone:getStringFromZoneProperty("prioMessage", "<none>")
	elseif theZone:hasProperty("reconMessage") then
		zInfo.prioMessage = theZone:getStringFromZoneProperty("reconMessage", "<none>")
	end
	
	if theZone:hasProperty("spotted!") then 
		zInfo.theFlag = theZone:getStringFromZoneProperty("spotted!", "*<none>")
		if isBlack then 
			trigger.action.outText("+++rcn: WARNING: recon zone <> is blacklisted, but also supplies a 'spotted!' attribute. Blacklisted units/objects will never trigger a spotted output.", 30)
		end
	end
	
	local dynamic = theZone:getBoolFromZoneProperty("dynamic", false)
	zInfo.dynamic = dynamic 
	local categ = 2 -- ground troops only
	local allGroups = cfxZones.allGroupsInZone(theZone, categ)
	for idx, aGroup in pairs(allGroups) do 
		local gName = aGroup:getName()
		cfxReconMode.zoneInfo[gName] = zInfo 
		if isBlack then 
			cfxReconMode.addToBlackList(aGroup, dynamic)
			if cfxReconMode.verbose or theZone.verbose then 
				if dynamic then trigger.action.outText("+++rcn: added DYNAMIC " .. aGroup:getName() .. " to blacklist", 30)
				else trigger.action.outText("+++rcn: added " .. aGroup:getName() .. " to blacklist", 30) 
				end
			end 
		else 
			if isPrio then 
				cfxReconMode.addToPrioList(aGroup, dynamic)
				if cfxReconMode.verbose or theZone.verbose then 
					if dynamic then trigger.action.outText("+++rcn: added DYNAMIC " .. aGroup:getName() .. " to priority target list", 30) 
					else trigger.action.outText("+++rcn: added " .. aGroup:getName() .. " to priority target list", 30)
					end
				end
			else 
				if cfxReconMode.verbose or theZone.verbose then 
					if dynamic then trigger.action.outText("+++rcn: procced DYNAMIC " .. aGroup:getName() .. " without priority", 30) 
					else trigger.action.outText("+++rcn: procced " .. aGroup:getName() .. " without priority", 30)
					end
				end
			end
		end
	end
end

function cfxReconMode.processScoutZone(theZone) 
	local isScout = theZone:getBoolFromZoneProperty("scout", true)
	local dynamic = theZone:getBoolFromZoneProperty("dynamic")
	theZone.dynamic = dynamic
	theZone.isScout = isScout
	
	local categ = 0 -- aircraft
	local allFixed = theZone:allGroupsInZone(categ)
	local categ = 1 -- helos
	local allRotor = theZone:allGroupsInZone(categ)
	local allGroups = dcsCommon.combineTables(allFixed, allRotor)
	for idx, aGroup in pairs(allGroups) do 
		if isScout then 
			cfxReconMode.addToAllowedScoutList(aGroup, dynamic)
			if cfxReconMode.verbose or theZone.verbose then 
				if dynamic then trigger.action.outText("+++rcn: added DYNAMIC " .. aGroup:getName() .. " to allowed scouts", 30)
				else trigger.action.outText("+++rcn: added " .. aGroup:getName() .. " to allowed scouts", 30) 
				end
			end 
		else 
			cfxReconMode.addToBlindScoutList(aGroup, dynamic)
			if cfxReconMode.verbose or theZone.verbose then 
				if dynamic then trigger.action.outText("+++rcn: added DYNAMIC " .. aGroup:getName() .. " to BLIND scouts list", 30)
				else trigger.action.outText("+++rcn: added " .. aGroup:getName() .. " to BLIND scouts list", 30)
				end
			end
		end
	end
	
	table.insert(cfxReconMode.scoutZones, theZone)
end

function cfxReconMode.readReconGroups()
	local attrZones = cfxZones.getZonesWithAttributeNamed("recon")
	for k, aZone in pairs(attrZones) do 
		cfxReconMode.processReconZone(aZone)
		cfxReconMode.reconZones[aZone.name] = aZone 
	end
end

function cfxReconMode.readScoutGroups()
	local attrZones = cfxZones.getZonesWithAttributeNamed("scout")
	for k, aZone in pairs(attrZones) do 
		cfxReconMode.processScoutZone(aZone)
	end
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
	
	-- gather prio and blacklist groups 
	cfxReconMode.readReconGroups() 
	
	-- gather allowed and forbidden scouts 
	cfxReconMode.readScoutGroups()
	
	-- gather exiting planes 
	cfxReconMode.initScouts()
	
	-- start update cycle
	cfxReconMode.updateQueues()
	
	-- if dead groups are removed from map,
	-- schedule housekeeping 
	if cfxReconMode.removeWhenDestroyed then 
		cfxReconMode.autoRemove()
	end
	
	if true or cfxReconMode.autoRecon then 
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


--[[--

ideas:
 
- renew lease. when already sighted, simply renew lease, maybe update location.
- update marks and renew lease 
TODO: red+ and blue+ - flags to increase when a plane of the other side is detected
 
--]]--


 
 