dcsCommon = {}
dcsCommon.version = "2.5.6"
--[[-- VERSION HISTORY
 2.2.6 - compassPositionOfARelativeToB
	   - clockPositionOfARelativeToB
 2.2.7 - isTroopCarrier 
       - distFlat
 2.2.8 - fixed event2text 
 2.2.9 - getUnitAGL
       - getUnitAlt
	   - getUnitSpeed 
	   - getUnitHeading
	   - getUnitHeadingDegrees
	   - mag
	   - clockPositionOfARelativeToB with own heading 
 2.3.0 - unitIsInfantry
 2.3.1 - bool2YesNo
       - bool2Text
 2.3.2 - getGroupAvgSpeed
       - getGroupMaxSpeed
 2.3.3 - getSizeOfTable
 2.3.4 - isSceneryObject
         coalition2county
 2.3.5 - smallRandom
         pickRandom uses smallRandom
		 airfield handling, parking 
		 flight waypoint handling
		 landing waypoint creation
		 take-off waypoint creation
 2.3.6 - createOverheadAirdromeRoutPintData(aerodrome)
 2.3.7 - coalition2county - warning when creating UN 
 2.3.8 - improved headingOfBInDegrees, new getClockDirection
 2.3.9 - getClosingVelocity
       - dot product 
	   - magSquare
	   - vMag
 2.4.0 - libCheck
 2.4.1 - grid/square/rect formation 
       - arrangeGroupInNColumns formation 
	   - 2Columns formation deep and wide formation
 2.4.2 - getAirbasesInRangeOfPoint
 2.4.3 - lerp 
 2.4.4 - getClosestAirbaseTo
       - fixed bug in containsString when strings equal
 2.4.5 - added cargo and mass options to createStaticObjectData
 2.4.6 - fixed randompercent 
 2.4.7 - smokeColor2Num(smokeColor)
 2.4.8 - linkStaticDataToUnit()
 2.4.9 - trim functions 
       - createGroundUnitData uses trim function to remove leading/trailing blanks
	     so now we can use blanks after comma to separate types 
       - dcsCommon.trimArray(
	   - createStaticObjectData uses trim for type 
	   - getEnemyCoalitionFor understands strings, still returns number
       - coalition2county also undertsands 'red' and 'blue'
 2.5.0 - "Line" formation with one unit places unit at center 	
 2.5.1 - vNorm(a)  
 2.5.1 - added SA-18 Igla manpad to unitIsInfantry()
 2.5.2 - added copyArray method
	   - corrected heading in createStaticObjectData
 2.5.3 - corrected rotateGroupData bug for cz 
	   - removed forced error in failed pickRandom
 2.5.4 - rotateUnitData()
       - randomBetween()
 2.5.5 - stringStartsWithDigit()
       - stringStartsWithLetter()
	   - stringIsPositiveNumber()
 2.5.6 - corrected stringEndsWith() bug with str
	   
--]]--

	-- dcsCommon is a library of common lua functions 
	-- for easy access and simple mission programming
	-- (c) 2021, 2022 by Chritian Franz and cf/x AG

	dcsCommon.verbose = false -- set to true to see debug messages. Lots of them
	dcsCommon.uuidStr = "uuid-"

	-- globals
	dcsCommon.cbID = 0 -- callback id for simple callback scheduling
	dcsCommon.troopCarriers = {"Mi-8MT", "UH-1H", "Mi-24P"} -- Ka-50 and Gazelle can't carry troops

	-- verify that a module is loaded. obviously not required
	-- for dcsCommon, but all higher-order modules
	function dcsCommon.libCheck(testingFor, requiredLibs)
		local canRun = true 
		for idx, libName in pairs(requiredLibs) do 
			if not _G[libName] then 
				trigger.action.outText("*** " .. testingFor .. " requires " .. libName, 30)
				canRun = false 
			end
		end
		return canRun
	end

	-- returns only positive values, lo must be >0 and <= hi 
	function dcsCommon.randomBetween(loBound, hiBound)
		if not loBound then loBound = 1 end 
		if not hiBound then hiBound = 1 end 
		if loBound == hiBound then return loBound end 

		local delayMin = loBound
		local delayMax = hiBound 
		local delay = delayMax 
	
		if delayMin ~= delayMax then 
			-- pick random in range , say 3-7 --> 5 s!
			local delayDiff = (delayMax - delayMin) + 1 -- 7-3 + 1
			delay = dcsCommon.smallRandom(delayDiff) - 1 --> 0-4
			delay = delay + delayMin 
			if delay > delayMax then delay = delayMax end 
			if delay < 1 then delay = 1 end 
		
			if dcsCommon.verbose then 
				trigger.action.outText("+++dcsC: delay range " .. delayMin .. "-" .. delayMax .. ": selected " .. delay, 30)
			end
		end
		
		return delay
	end
	

	-- taken inspiration from mist, as dcs lua has issues with
	-- random numbers smaller than 50. Given a range of x numbers 1..x, it is 
	-- repeated a number of times until it fills an array of at least 
	-- 50 items (usually some more), and only then one itemis picked from 
	-- that array with a random number that is from a greater range (0..50+)
	function dcsCommon.smallRandom(theNum) -- adapted from mist, only support ints
		if theNum >= 50 then return math.random(theNum) end
		
		-- for small randoms (<50) 
		local lowNum, highNum
		highNum = theNum
		lowNum = 1
		local total = 1
		if math.abs(highNum - lowNum + 1) < 50 then -- if total values is less than 50
			total = math.modf(50/math.abs(highNum - lowNum + 1)) -- number of times to repeat whole range to get above 50. e.g. 11 would be 5 times 1 .. 11, giving us 55 items total 
		end
		local choices = {}
		for i = 1, total do -- iterate required number of times
			for x = lowNum, highNum do -- iterate between the range
				choices[#choices +1] = x -- add each entry to a table
			end
		end
		local rtnVal; -- = math.random(#choices) -- will now do a math.random of at least 50 choices
		for i = 1, 15 do
			rtnVal = math.random(#choices) -- iterate 15 times for randomization
		end
		return choices[rtnVal] -- return indexed
	end
	

	function dcsCommon.getSizeOfTable(theTable)
		local count = 0
		for _ in pairs(theTable) do count = count + 1 end
		return count
	end

	function dcsCommon.findAndRemoveFromTable(theTable, theElement) -- assumes array 
		if not theElement then return false end 
		if not theTable then return false end 
		for i=1, #theTable do 
			if theTable[i] == theElement then 
				-- this element found. remove from table 
				table.remove(theTable, i)
				return true 
			end
		end
	end

	function dcsCommon.pickRandom(theTable)
		if not theTable then 
			trigger.action.outText("*** warning: nil table in pick random", 30)
		end
		
		if #theTable < 1 then 
			trigger.action.outText("*** warning: zero choice in pick random", 30)
			--local k = i.ll 
			return nil
		end
		if #theTable == 1 then return theTable[1] end
		r = dcsCommon.smallRandom(#theTable) --r = math.random(#theTable)
		return theTable[r]
	end

	-- enumerateTable - make an array out of a table for indexed access
	function dcsCommon.enumerateTable(theTable)
		if not theTable then theTable = {} end
		local array = {}
		for key, value in pairs(theTable) do 
			table.insert(array, value)
		end
		return array
	end

-- 
-- A I R F I E L D S  A N D  F A R P S  
--

	-- airfield management 
	function dcsCommon.getAirbaseCat(aBase)
		if not aBase then return nil end 
		
		local airDesc = aBase:getDesc()
		if not airDesc then return nil end 
		
		local airCat = airDesc.category
		return airCat 
	end

	-- get free parking slot. optional parkingType can be used to 
	-- filter for a scpecific type, e.g. 104 = open field
	function dcsCommon.getFirstFreeParkingSlot(aerodrome, parkingType) 
		if not aerodrome then return nil end 
		local freeSlots = aerodrome:getParking(true)
		
		for idx, theSlot in pairs(freeSlots) do 
			if not parkingType then 
				-- simply return the first we come across
				return theSlot
			end		
			
			if theSlot.Term_Type == parkingType then 
				return theSlot 
			end
		end
		
		return nil 
	end

	-- getAirbasesInRangeOfPoint: get airbases that are in range of point 
	function dcsCommon.getAirbasesInRangeOfPoint(center, range, filterCat, filterCoalition)
		if not center then return {} end 
		if not range then range = 500 end -- 500m default 
		local basesInRange = {}
		
		local allAB = dcsCommon.getAirbasesWhoseNameContains("*", filterCat, filterCoalition)
		for idx, aBase in pairs(allAB) do 			
			local delta = dcsCommon.dist(center, aBase:getPoint())
			if delta <= range then 
				table.insert(basesInRange, aBase)
			end
		end
		return basesInRange
	end

	-- getAirbasesInRangeOfAirbase returns all airbases that 
	-- are in range of the given airbase 
	function dcsCommon.getAirbasesInRangeOfAirbase(airbase, includeCenter, range, filterCat, filterCoalition)
		if not airbase then return {} end
		if not range then range = 150000 end 
		local center = airbase:getPoint() 
		local centerName = airbase:getName() 
		
		local ABinRange = {}
		local allAB = dcsCommon.getAirbasesWhoseNameContains("*", filterCat, filterCoalition)
		
		for idx, aBase in pairs(allAB) do 
			if aBase:getName() ~= centerName then 
				local delta = dcsCommon.dist(center, aBase:getPoint())
				if delta <= range then 
					table.insert(ABinRange, aBase)
				end
			end		
		end
		
		if includeCenter then 
			table.insert(ABinRange, airbase)
		end
		
		return ABinRange
	end

	function dcsCommon.getAirbasesInRangeOfAirbaseList(theCenterList, includeList, range, filterCat, filterCoalition)
		local collectorDict = {}
		for idx, aCenter in pairs(theCenterList) do 
			-- get all surrounding airbases. returns list of airfields 
			local surroundingAB = dcsCommon.getAirbasesInRangeOfAirbase(airbase, includeList, range, filterCat, filterCoalition)
			
			for idx2, theAirField in pairs (surroundingAB) do 
				collectorDict[airField] = theAirField 
			end
		end
		
		-- make result an array
		local theABList = dcsCommon.enumerateTable(collectorDict)
		return theABList
	end

	-- getAirbasesWhoseNameContains - get all airbases containing 
	-- a name. filterCat is optional and can be aerodrome (0), farp (1), ship (2)
	-- filterCoalition is optional and can be 0 (neutral), 1 (red), 2 (blue) 
	-- if no name given or aName = "*", then all bases are returned prior to filtering 
	function dcsCommon.getAirbasesWhoseNameContains(aName, filterCat, filterCoalition)
		--trigger.action.outText("getAB(name): enter with " .. aName, 30)
		if not aName then aName = "*" end 
		local allYourBase = world.getAirbases() -- get em all 
		local areBelongToUs = {}
		-- now iterate all bases
		for idx, aBase in pairs(allYourBase) do
			local airBaseName = aBase:getName() -- get display name
			if aName == "*" or dcsCommon.containsString(airBaseName, aName) then 
				-- containsString is case insesitive unless told otherwise
				--if aName ~= "*" then 
				--	trigger.action.outText("getAB(name): matched " .. airBaseName, 30)
				--end 
				local doAdd = true 
				if filterCat then 
					-- make sure the airbase is of that category 
					local airCat = dcsCommon.getAirbaseCat(aBase)
					doAdd = doAdd and airCat == filterCat 
				end
				
				if filterCoalition then 
					doAdd = doAdd and filterCoalition == aBase:getCoalition()
				end
				
				if doAdd then 
					-- all good, add to table
					table.insert(areBelongToUs, aBase)
				end			
			end
		end
		return areBelongToUs
	end

	function dcsCommon.getFirstAirbaseWhoseNameContains(aName, filterCat, filterCoalition)
		local allBases = dcsCommon.getAirbasesWhoseNameContains(aName, filterCat, filterCoalition)
		for idx, aBase in pairs (allBases) do 
			-- simply return first 
			return aBase
		end
		return nil 
	end	

	function dcsCommon.getClosestAirbaseTo(thePoint, filterCat, filterCoalition)
		local delta = math.huge
		local allYourBase = dcsCommon.getAirbasesWhoseNameContains("*", filterCat, filterCoalition) -- get em all and filter
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

-- 
-- U N I T S   M A N A G E M E N T 
--

	-- number of living units in group
	function dcsCommon.livingUnitsInGroup(group)
		local living = 0
		local allUnits = group:getUnits()
		for key, aUnit in pairs(allUnits) do 
			if aUnit:isExist() and aUnit:getLife() >= 1 then 
				living = living + 1
			end
		end
		return living
	end

	-- closest living unit in group to a point
	function dcsCommon.getClosestLivingUnitToPoint(group, p)
		if not p then return nil end
		if not group then return nil end
		local closestUnit = nil
		local closestDist = math.huge
		local allUnits = group:getUnits()
		for key, aUnit in pairs(allUnits) do 
			if aUnit:isExist() and aUnit:getLife() >= 1 then 
				local thisDist = dcsCommon.dist(p, aUnit:getPoint())
				if thisDist < closestDist then 
					closestDist = thisDist
					closestUnit = aUnit 
				end
			end
		end
		return closestUnit, closestDist
	end
	
	-- closest living group to a point - cat can be nil or one of Group.Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3, TRAIN = 4}
	function dcsCommon.getClosestLivingGroupToPoint(p, coal, cat) 
		if not cat then cat = 2 end -- ground is default 
		local closestGroup = nil;
		local closestGroupDist = math.huge
		local allGroups =  coalition.getGroups(coal, cat) -- get all groups from this coalition, perhaps filtered by cat 
		for key, grp in pairs(allGroups) do
			local closestUnit, dist = dcsCommon.getClosestLivingUnitToPoint(grp, p)
			if closestUnit then 
				if dist < closestGroupDist then 
					closestGroup = grp
					closestGroupDist = dist
				end
			end			
		end
		return closestGroup, closestGroupDist
	end

	function dcsCommon.getLivingGroupsAndDistInRangeToPoint(p, range, coal, cat) 
		if not cat then cat = 2 end -- ground is default 
		local groupsInRange = {};
		local allGroups = coalition.getGroups(coal, cat) -- get all groups from this coalition, perhaps filtered by cat 
		for key, grp in pairs(allGroups) do
			local closestUnit, dist = dcsCommon.getClosestLivingUnitToPoint(grp, p)
			if closestUnit then 
				if dist < range then 
					table.insert(groupsInRange, {group = grp, dist = dist}) -- array
				end
			end			
		end
		-- sort the groups by distance
		table.sort(groupsInRange, function (left, right) return left.dist < right.dist end )
		return groupsInRange
	end

	-- distFlat ignores y, input must be xyz points, NOT xy points  
	function dcsCommon.distFlat(p1, p2) 
		local point1 = {x = p1.x, y = 0, z=p1.z}
		local point2 = {x = p2.x, y = 0, z=p2.z}
		return dcsCommon.dist(point1, point2)
	end
	
	-- distance between points
	function dcsCommon.dist(point1, point2)	 -- returns distance between two points
	  -- supports xyz and xy notations
	  if not point1 then 
		trigger.action.outText("+++ warning: nil point1 in common:dist", 30)
		point1 = {x=0, y=0, z=0}
	  end

	  if not point2 then 
		trigger.action.outText("+++ warning: nil point2 in common:dist", 30)
		point2 = {x=0, y=0, z=0}
		stop.here.now = 1
	  end
	  
	  local p1 = {x = point1.x, y = point1.y}
	  if not point1.z then 
		p1.z = p1.y
		p1.y = 0
	  else 
		p1.z = point1.z
	  end
	  
	  local p2 = {x = point2.x, y = point2.y}
	  if not point2.z then 
		p2.z = p2.y
		p2.y = 0
	  else 
		p2.z = point2.z
	  end
	  
	  local x = p1.x - p2.x
	  local y = p1.y - p2.y 
	  local z = p1.z - p2.z
	  
	  return (x*x + y*y + z*z)^0.5
	end

	function dcsCommon.delta(name1, name2) -- returns distance (in meters) of two named objects
	  local n1Pos = Unit.getByName(name1):getPosition().p
	  local n2Pos = Unit.getByName(name2):getPosition().p
	  return dcsCommon.dist(n1Pos, n2Pos)
	end

	-- lerp between a and b, x being 0..1 (percentage), clipped to [0..1]
	function dcsCommon.lerp(a, b, x) 
		if not a then return 0 end
		if not b then return 0 end
		if not x then return a end
		if x < 0 then x = 0 end 
		if x > 1 then x = 1 end 
		return a + (b - a ) * x
	end

	function dcsCommon.bearingFromAtoB(A, B) -- coords in x, z 
		dx = B.x - A.x
		dz = B.z - A.z
		bearing = math.atan2(dz, dx) -- in radiants
		return bearing
	end

	function dcsCommon.bearingInDegreesFromAtoB(A, B)
		local bearing = dcsCommon.bearingFromAtoB(A, B) -- in rads 
		bearing = math.floor(bearing / math.pi * 180)
		if bearing < 0 then bearing = bearing + 360 end
		if bearing > 360 then bearing = bearing - 360 end
		return bearing
	end
	
	function dcsCommon.compassPositionOfARelativeToB(A, B)
		-- warning: is REVERSE in order for bearing, returns a string like 'Sorth', 'Southwest'
		if not A then return "***error:A***" end
		if not B then return "***error:B***" end
		local bearing = dcsCommon.bearingInDegreesFromAtoB(B, A) -- returns 0..360
		if bearing < 23 then return "North" end 
		if bearing < 68 then return "NE" end
		if bearing < 112 then return "East" end 
		if bearing < 158 then return "SE" end 
		if bearing < 202 then return "South" end 
		if bearing < 248 then return "SW" end 
		if bearing < 292 then return "West" end
		if bearing < 338 then return "NW" end 
		return "North"
	end
	
	function dcsCommon.clockPositionOfARelativeToB(A, B, headingOfBInDegrees)
		-- o'clock notation 
		if not A then return "***error:A***" end
		if not B then return "***error:B***" end
		if not headingOfBInDegrees then headingOfBInDegrees = 0 end 
		
		local bearing = dcsCommon.bearingInDegreesFromAtoB(B, A) -- returns 0..360
--		trigger.action.outText("+++comm: oclock - bearing = " .. bearing .. " and inHeading = " .. headingOfBInDegrees, 30) 
		bearing = bearing - headingOfBInDegrees
		return dcsCommon.getClockDirection(bearing)
		
	end 
	
	-- given a heading, return clock with 0 being 12, 180 being 6 etc.
	function dcsCommon.getClockDirection(direction) -- inspired by cws, improvements my own
		if not direction then return 0 end
		direction = math.fmod (direction, 360)
		while direction < 0 do 
			direction = direction + 360
		end
		
		if direction < 15 then -- special case 12 o'clock past 12 o'clock
			return 12
		end
	
		direction = direction + 15 -- add offset so we get all other times correct
		return math.floor(direction/30)
	
	end

	
	function dcsCommon.randomDegrees()
		local degrees = math.random(360) * 3.14152 / 180
		return degrees
	end

	function dcsCommon.randomPercent()
		local percent = math.random(100)/100
		return percent
	end

	function dcsCommon.randomPointOnPerimeter(sourceRadius, x, z) 
		return dcsCommon.randomPointInCircle(sourceRadius, sourceRadius-1, x, z)
	end

	function dcsCommon.randomPointInCircle(sourceRadius, innerRadius, x, z)
		if not x then x = 0 end
		--local y = 0
		if not innerRadius then innerRadius = 0 end		
		if innerRadius < 0 then innerRadius = 0 end
		
		local percent = dcsCommon.randomPercent() -- 1 / math.random(100)
		-- now lets get a random degree
		local degrees = dcsCommon.randomDegrees() -- math.random(360) * 3.14152 / 180 -- ok, it's actually radiants. 
		local r = (sourceRadius-innerRadius) * percent 
		local x = x + (innerRadius + r) * math.cos(degrees)
		local z = z + (innerRadius + r) * math.sin(degrees)
	
		local thePoint = {}
		thePoint.x = x
		thePoint.y = 0
		thePoint.z = z 
		
		return thePoint, degrees
	end

	-- get group location: get the group's location by 
	-- accessing the fist existing, alive member of the group that it finds
	function dcsCommon.getGroupLocation(group)
		-- nifty trick from mist: make this work with group and group name
		if type(group) == 'string' then -- group name
			group = Group.getByName(group)
		end
		
		-- get all units
		local allUnits = group:getUnits()

		-- iterate through all members of group until one is alive and exists
		for index, theUnit in pairs(allUnits) do 
			if (theUnit:isExist() and theUnit:getLife() > 0) then 
				return theUnit:getPosition().p 
			end;
		end

		-- if we get here, there was no live unit 
		--trigger.action.outText("+++cmn: A group has no live units. returning nil", 10)
		return nil 
		
	end

	-- get the group's first Unit that exists and is 
	-- alive 
	function dcsCommon.getGroupUnit(group)
		if not group then return nil  end
		
		-- nifty trick from mist: make this work with group and group name
		if type(group) == 'string' then -- group name
			group = Group.getByName(group)
		end
		
		if not group:isExist() then return nil end 
		
		-- get all units
		local allUnits = group:getUnits()

		-- iterate through all members of group until one is alive and exists
		for index, theUnit in pairs(allUnits) do 
			if (theUnit:isExist() and theUnit:getLife() > 0) then 
				return theUnit
			end;
		end

		-- if we get here, there was no live unit 
		--trigger.action.outText("+++cmn A group has no live units. returning nil", 10)
		return nil 
		
	end

	-- and here the alias
	function dcsCommon.getFirstLivingUnit(group)
		return dcsCommon.getGroupUnit(group)
	end
	
	-- isGroupAlive returns true if there is at least one unit in the group that isn't dead
	function dcsCommon.isGroupAlive(group)
		return (dcsCommon.getGroupUnit(group) ~= nil) 
	end

	function dcsCommon.getLiveGroupUnits(group)
		-- nifty trick from mist: make this work with group and group name
		if type(group) == 'string' then -- group name
			group = Group.getByName(group)
		end
		
		local liveUnits = {}
		-- get all units
		local allUnits = group:getUnits()

		-- iterate through all members of group until one is alive and exists
		for index, theUnit in pairs(allUnits) do 
			if (theUnit:isExist() and theUnit:getLife() > 0) then 
				table.insert(liveUnits, theUnit) 
			end;
		end

		-- if we get here, there was no live unit 
		return liveUnits
	end

	function dcsCommon.getGroupTypeString(group) -- convert into comma separated types 
		if not group then 
			trigger.action.outText("+++cmn getGroupTypeString: nil group", 30)
			return "" 
		end
		if not dcsCommon.isGroupAlive(group) then 
			trigger.action.outText("+++cmn getGroupTypeString: dead group", 30)
			return "" 
		end 
		local theTypes = ""
		local liveUnits = dcsCommon.getLiveGroupUnits(group)
		for i=1, #liveUnits do 
			if i > 1 then theTypes = theTypes .. "," end
			theTypes = theTypes .. liveUnits[i]:getTypeName()
		end
		return theTypes
	end

	function dcsCommon.getGroupTypes(group) 
		if not group then 
			trigger.action.outText("+++cmn getGroupTypes: nil group", 30)
			return {}
		end
		if not dcsCommon.isGroupAlive(group) then 
			trigger.action.outText("+++cmn getGroupTypes: dead group", 30)
			return {}
		end 
		local liveUnits = dcsCommon.getLiveGroupUnits(group)
		local unitTypes = {}
		for i=1, #liveUnits do 
			table.insert(unitTypes, liveUnits[i]:getTypeName())
		end
		return unitTypes
	end

	function dcsCommon.getEnemyCoalitionFor(aCoalition)
		if aCoalition == 1 then return 2 end
		if aCoalition == 2 then return 1 end
		if type(aCoalition) == "string" then 
			aCoalition = aCoalition:lower()
			if aCoalition == "red" then return 2 end
			if aCoalition == "blue" then return 1 end
		end
		return nil
	end

	function dcsCommon.getACountryForCoalition(aCoalition)
		-- scan the table of countries and get the first country that is part of aCoalition
		-- this is useful if you want to create troops for a coalition but don't know the
		-- coalition's countries 
		-- we start with id=0 (Russia), go to id=85 (Slovenia), but skip id = 14
		local i = 0
		while i < 86 do 
			if i ~= 14 then 
				if (coalition.getCountryCoalition(i) == aCoalition) then return i end
			end
			i = i + 1
		end
		
		return nil
	end
--
--
-- C A L L B A C K   H A N D L E R 
--
--

	-- installing callbacks
	-- based on mist, with optional additional hooks for pre- and post-
	-- processing of the event
	-- when filtering occurs in pre, an alternative 'rejected' handler can be called 
	function dcsCommon.addEventHandler(f, pre, post, rejected) -- returns ID 
		local handler = {} -- build a wrapper and connect the onEvent
		--dcsCommon.cbID = dcsCommon.cbID + 1 -- increment unique count
		handler.id = dcsCommon.uuid("eventHandler")
		handler.f = f -- the callback itself
		if (rejected) then handler.rejected = rejected end
		-- now set up pre- and post-processors. defaults are set in place
		-- so pre and post are optional. If pre returns false, the callback will
		-- not be invoked
		if (pre) then handler.pre = pre else handler.pre = dcsCommon.preCall end
		if (post) then handler.post = post else handler.post = dcsCommon.postCall end
		function handler:onEvent(event)
			if not self.pre(event) then 
				if dcsCommon.verbose then
--					trigger.action.outText("event " .. event.id .. " discarded by pre-processor", 10)
				end
				if (self.rejected) then self.rejected(event) end 
				return
			end
			self.f(event) -- call the handler
			self.post(event) -- do post-processing
		end
		world.addEventHandler(handler)
		return handler.id
	end

	function dcsCommon.preCall(e)
		-- we can filter here
		-- if we return false, the call is abortet
		if dcsCommon.verbose then
			trigger.action.outText("event " .. e.id .. " received: PRE-PROCESSING", 10)
		end
		return true;
	end;

	function dcsCommon.postCall(e)
		-- we do pos proccing here 
		if dcsCommon.verbose then
			trigger.action.outText("event " .. e.id .. " received: post proc", 10)
		end
	end
	
	-- highly specific eventhandler for one event only
	-- based on above, with direct filtering built in; skips pre
	-- but does post
	function dcsCommon.addEventHandlerForEventTypes(f, evTypes, post, rejected) -- returns ID 
		local handler = {} -- build a wrapper and connect the onEvent
		dcsCommon.cbID = dcsCommon.cbID + 1 -- increment unique count
		handler.id = dcsCommon.cbID
		handler.what = evTypes
		if (rejected) then handler.rejected = rejected end 
		
		handler.f = f -- set the callback itself
		-- now set up post-processor. pre is hard-coded to match evType
		-- post is optional. If event.id is not in evTypes, the callback will
		-- not be invoked
		if (post) then handler.post = post else handler.post = dcsCommon.postCall end
		function handler:onEvent(event)
			hasMatch = false;
			for key, evType in pairs(self.what) do
				if evType == event.id then
					hasMatch = true;
					break;
				end;
			end;
			if not hasMatch then 
				if dcsCommon.verbose then
					trigger.action.outText("event " .. e.id .. " discarded - not in whitelist evTypes", 10)
				end
				if (self.rejected) then self.rejected(event) end 
				return;
			end;
			
			self.f(event) -- call the actual handler as passed to us
			self.post(event) -- do post-processing 
		end
		world.addEventHandler(handler) -- add to event handlers
		return handler.id
	end
	
	
	
	-- remove event handler / callback, identical to Mist 
	-- note we don't call world.removeEventHandler, but rather directly 
	-- access world.eventHandlers directly and remove kvp directly.
	function dcsCommon.removeEventHandler(id)
		for key, handler in pairs(world.eventHandlers) do
			if handler.id and handler.id == id then
				world.eventHandlers[key] = nil
				return true
			end
		end
		return false
	end

--
--
-- C L O N I N G 
--
--
	-- topClone is a shallow clone of orig, only top level is iterated,
	-- all values are ref-copied
	function dcsCommon.topClone(orig)
		local orig_type = type(orig)
		local copy
		if orig_type == 'table' then
			copy = {}
			for orig_key, orig_value in pairs(orig) do
				copy[orig_key] = orig_value
			end
		else -- number, string, boolean, etc
			copy = orig
		end
		return copy
	end

	-- clone is a recursive clone which will also clone
	-- deeper levels, as used in units 
	function dcsCommon.clone(orig)
		local orig_type = type(orig)
		local copy
		if orig_type == 'table' then
			copy = {}
			for orig_key, orig_value in next, orig, nil do
				copy[dcsCommon.clone(orig_key)] = dcsCommon.clone(orig_value)
			end
			setmetatable(copy, dcsCommon.clone(getmetatable(orig)))
		else -- number, string, boolean, etc
			copy = orig
		end
		return copy
	end

	function dcsCommon.copyArray(inArray)
		-- warning: this is a ref copy!
		local theCopy = {}
		for idx, element in pairs(inArray) do 
			table.insert(theCopy, element)
		end
		return theCopy 
	end
--
-- 
-- S P A W N I N G 
-- 
-- 

	function dcsCommon.createEmptyGroundGroupData (name)
		local theGroup = {} -- empty group
		theGroup.visible = false
		theGroup.taskSelected = true
		-- theGroup.route = {}
		-- theGroup.groupId = id
		theGroup.tasks = {}
		-- theGroup.hidden = false -- hidden on f10?

		theGroup.units = { } -- insert units here! -- use addUnitToGroupData

		theGroup.x = 0
		theGroup.y = 0
		theGroup.name = name
		-- theGroup.start_time = 0
		theGroup.task = "Ground Nothing"
		
		return theGroup
	end;

	function dcsCommon.createEmptyAircraftGroupData (name)
		local theGroup = dcsCommon.createEmptyGroundGroupData(name)--{} -- empty group

		theGroup.task = "Nothing" -- can be others, like Transport, CAS, etc
		-- returns with empty route
		theGroup.route = dcsCommon.createEmptyAircraftRouteData() -- we can add points here 
		return theGroup
	end;

	function dcsCommon.createAircraftRoutePointData(x, z, altitudeInFeet, knots, altType, action)
		local rp = {}
		rp.x = x
		rp.y = z
		rp.action = "Turning Point"
		rp.type = "Turning Point"
		if action then rp.action = action; rp.type = action end -- warning: may not be correct, need to verify later
		rp.alt = altitudeInFeet * 0.3048
		rp.speed = knots * 0.514444 -- we use 
		rp.alt_type = "BARO"
		if (altType) then rp.alt_type = altType end 
		return rp
	end

	function dcsCommon.addRoutePointDataToRouteData(inRoute, x, z, altitudeInFeet, knots, altType, action)
		local p = dcsCommon.createAircraftRoutePointData(x, z, altitudeInFeet, knots, altType, action)
		local thePoints = inRoute.points 
		table.insert(thePoints, p)
	end
	
	function dcsCommon.addRoutePointDataToGroupData(group, x, z, altitudeInFeet, knots, altType, action)
		if not group.route then group.route = dcsCommon.createEmptyAircraftRouteData() end
		local theRoute = group.route 
		dcsCommon.addRoutePointDataToRouteData(theRoute, x, z, altitudeInFeet, knots, altType, action)
	end

	function dcsCommon.addRoutePointForGroupData(theGroup, theRP)
		if not theGroup then return end 
		if not theGroup.route then theGroup.route = dcsCommon.createEmptyAircraftRouteData() end
		
		local theRoute = theGroup.route 
		local thePoints = theRoute.points 
		table.insert(thePoints, theRP)
	end
	
	function dcsCommon.createEmptyAircraftRouteData()
		local route = {}
		route.points = {}
		return route
	end

	function dcsCommon.createTakeOffFromParkingRoutePointData(aerodrome)
		if not aerodrome then return nil end 
			
		local rp = {}	
		local freeParkingSlot = dcsCommon.getFirstFreeParkingSlot(aerodrome, 104) -- get big slot first 
		if not freeParkingSlot then 
			freeParkingSlot = dcsCommon.getFirstFreeParkingSlot(aerodrome) -- try any size
		end
			
		if not freeParkingSlot then 
			trigger.action.outText("civA: no free parking at " .. aerodrome:getName(), 30)
			return nil 
		end
			
		local p = freeParkingSlot.vTerminalPos
			
		rp.airdromeId = aerodrome:getID() 
		rp.x = p.x
		rp.y = p.z
		rp.alt = p.y 
		rp.action = "From Parking Area"
		rp.type = "TakeOffParking"
			
		rp.speed = 100; -- in m/s? If so, that's 360 km/h 
		rp.alt_type = "BARO"
		return rp
	end

	function dcsCommon.createOverheadAirdromeRoutPintData(aerodrome)
		if not aerodrome then return nil end 
		local rp = {}			
		local p = aerodrome:getPoint()
		rp.x = p.x
		rp.y = p.z
		rp.alt = p.y + 2000 -- 6000 ft overhead
		rp.action = "Turning Point"
		rp.type = "Turning Point"
			
		rp.speed = 133; -- in m/s? If so, that's 360 km/h 
		rp.alt_type = "BARO"
		return rp
	end
	

	function dcsCommon.createLandAtAerodromeRoutePointData(aerodrome)
		if not aerodrome then return nil end 
			
		local rp = {}			
		local p = aerodrome:getPoint()
		rp.airdromeId = aerodrome:getID() 
		rp.x = p.x
		rp.y = p.z
		rp.alt = p.y 
		rp.action = "Landing"
		rp.type = "Land"
			
		rp.speed = 100; -- in m/s? If so, that's 360 km/h 
		rp.alt_type = "BARO"
		return rp
	end

	
	function dcsCommon.createRPFormationData(findex) -- must be added as "task" to an RP. use 4 for Echelon right
		local task = {}
		task.id = "ComboTask"
		local params = {}
		task.params = params
		local tasks = {}
		params.tasks = tasks
		local t1 = {}
		tasks[1] = t1
		t1.number = 1
		t1.auto = false 
		t1.id = "WrappedAction"
		t1.enabled = true
		local t1p = {}
		t1.params = t1p
		local action = {}
		t1p.action = action 
		action.id = "Option"
		local ap = {}
		action.params = ap
		ap.variantIndex = 3
		ap.name = 5 -- AI.Option.Air.ID 5 = Formation 
		ap.formationIndex = findex -- 4 is echelon_right
		ap.value = 262147
		
		return task 
	end

	function dcsCommon.addTaskDataToRP(theTask, theGroup, rpIndex)
		local theRoute = theGroup.route
		local thePoints = theRoute.points
		local rp = thePoints[rpIndex]
		rp.task = theTask
	end
	
	-- create a minimal payload table that is compatible with creating 
	-- a unit. you may need to alter this before adding the unit to
	-- the mission. all params optional 
	function dcsCommon.createPayload(fuel, flare, chaff, gun) 
		local payload = {}
		payload.pylons = {}
		if not fuel then fuel = 1000 end -- in kg. check against fuelMassMax in type desc
		if not flare then flare = 0 end
		if not chaff then chaff = 0 end
		if not gun then gun = 0 end
		return payload 
		
	end

	function dcsCommon.createCallsign(cs) 
		local callsign = {}
		callsign[1] = 1
		callsign[2] = 1
		callsign[3] = 1
		if not cs then cs = "Enfield11" end
		callsign.name = cs
		return callsign
	end
	

	-- create the data table required to spawn a unit.
	-- unit types are defined in https://github.com/mrSkortch/DCS-miscScripts/tree/master/ObjectDB
	function dcsCommon.createGroundUnitData(name, unitType, transportable)
		local theUnit = {}
		unitType = dcsCommon.trim(unitType)
		theUnit.type = unitType -- e.g. "LAV-25",
		if not transportable then transportable = false end -- elaborate, not requried code
		theUnit.transportable = {["randomTransportable"] = transportable} 
		-- theUnit.unitId = id 
		theUnit.skill = "Average" -- always average 
		theUnit.x = 0 -- make it zero, zero!
		theUnit.y = 0
		theUnit.name = name
		theUnit.playerCanDrive = false
		theUnit.heading = 0
		return theUnit
	end 

	function dcsCommon.createAircraftUnitData(name, unitType, transportable, altitude, speed, heading)
		local theAirUnit = dcsCommon.createGroundUnitData(name, unitType, transportable)
		theAirUnit.alt = 100 -- make it 100m
		if altitude then theAirUnit.alt = altitude end 
		theAirUnit.alt_type = "RADIO" -- AGL
		theAirUnit.speed = 77 -- m/s --> 150 knots
		if speed then theAirUnit.speed = speed end 
		if heading then theAirUnit.heading = heading end 
		theAirUnit.payload = dcsCommon.createPayload()
		theAirUnit.callsign = dcsCommon.createCallsign()
		return theAirUnit
	end
	

	function dcsCommon.addUnitToGroupData(theUnit, theGroup, dx, dy, heading)
		-- add a unit to a group, and place it at dx, dy of group's position,
		-- taking into account unit's own current location
		if not dx then dx = 0 end
		if not dy then dy = 0 end
		if not heading then heading = 0 end
		theUnit.x = theUnit.x + dx + theGroup.x
		theUnit.y = theUnit.y + dy + theGroup.y 
		theUnit.heading = heading
		table.insert(theGroup.units, theUnit)
	end;

	function dcsCommon.createSingleUnitGroup(name, theUnitType, x, z, heading) 
		-- create the container 
		local theNewGroup = dcsCommon.createEmptyGroundGroupData(name)
		local aUnit = {}
		aUnit = dcsCommon.createGroundUnitData(name .. "-1", theUnitType, false)
--		trigger.action.outText("dcsCommon - unit name retval " .. aUnit.name, 30)
		dcsCommon.addUnitToGroupData(aUnit, theNewGroup, x, z, heading)
		return theNewGroup
	end
	

	function dcsCommon.arrangeGroupDataIntoFormation(theNewGroup, radius, minDist, formation, innerRadius)
		-- formations:
		--    (default) "line" (left to right along x) -- that is Y direction
		--    "line_v" a line top to bottom -- that is X direction
		--    "chevron" - left to right middle too top
		--    "scattered", "random" -- random, innerRadius used to clear area in center
		-- 	  "circle", "circle_forward" -- circle, forward facing
		--    "circle_in" -- circle, inwarf facing
		--    "circle_out" -- circle, outward facing
		--    "grid", "square", "rect" -- optimal rectangle
		--    "2cols", "2deep" -- 2 columns, n deep 
		--    "2wide" -- 2 columns wide, 2 deep 

		local num = #theNewGroup.units 
		
		-- now do the formation stuff
		-- make sure that they keep minimum  distance 
--		trigger.action.outText("dcsCommon - processing formation " .. formation .. " with radius = " .. radius, 30)
		if formation == "LINE_V" then 
			-- top to bottom in zone (heding 0). -- will run through x-coordinate 
			-- use entire radius top to bottom 
			local currX = -radius
			local increment = radius * 2/(num - 1) -- MUST NOT TRY WITH 1 UNIT!
			for i=1, num do
			
				local u = theNewGroup.units[i]
--				trigger.action.outText("formation unit " .. u.name .. " currX = " .. currX, 30)
				u.x = currX
				currX = currX + increment
			end
		
		elseif formation == "LINE" then 
			-- left to right in zone. runs through Y
			-- left and right are y because at heading 0, forward is x (not y as expected)
			-- if only one, place in middle of circle and be done 
			if num == 1 then 
				-- nothing. just stay in the middle 
			else 
				local currY = -radius
				local increment = radius * 2/(num - 1) -- MUST NOT TRY WITH 1 UNIT!
				for i=1, num do
					local u = theNewGroup.units[i]
--					trigger.action.outText("formation unit " .. u.name .. " currX = " .. currY, 30)
					u.y = currY
					currY = currY + increment
				end	
			end 
			
		elseif formation == "CHEVRON" then 
			-- left to right in zone. runs through Y
			-- left and right are y because at heading 0, forward is x (not y as expected)
			local currY = -radius
			local currX = 0
			local incrementY = radius * 2/(num - 1) -- MUST NOT TRY WITH 1 UNIT!
			local incrementX = radius * 2/(num - 1) -- MUST NOT TRY WITH 1 UNIT!
			for i=1, num do
				local u = theNewGroup.units[i]
--				trigger.action.outText("formation unit " .. u.name .. " currX = " .. currX .. " currY = " .. currY, 30)
				u.x = currX
				u.y = currY
				-- calc coords for NEXT iteration
				currY = currY + incrementY -- march left to right
				if i < num / 2 then -- march up
					currX = currX + incrementX 
				elseif i == num / 2 then -- even number, keep height
					currX = currX + 0 
				else 
					currX = currX - incrementX -- march down 
				end 
				-- note: when unit number even, the wedge is sloped. may need an odd/even test for better looks
			end	

		elseif formation == "SCATTERED" or formation == "RANDOM" then 
			-- use randomPointInCircle and tehn iterate over all vehicles for mindelta
			processedUnits = {}
			for i=1, num do
				local emergencyBreak = 1 -- prevent endless loop
				local lowDist = 10000
				local uPoint = {}
				local thePoint = {}
				repeat 	-- get random point intil mindistance to all is kept or emergencybreak
					for idx, rUnit in pairs(processedUnits) do -- get min dist to all positioned units
						thePoint = dcsCommon.randomPointInCircle(radius, innerRadius) -- returns x, 0, z
						uPoint.x = rUnit.x
						uPoint.y = 0
						uPoint.z = rUnit.y 
						local dist = dcsCommon.dist(thePoint, uPoint) -- measure distance to unit
						if (dist < lowDist) then lowDist = dist end
					end
					emergencyBreak = emergencyBreak + 1
				until (emergencyBreak > 20) or (lowDist > minDist)
				-- we have random x, y 
				local u = theNewGroup.units[i] -- get unit to position
				u.x = thePoint.x
				u.y = thePoint.z -- z --> y mapping! 
				-- now add the unit to the 'processed' set 
				table.insert(processedUnits, u)
			end	

		elseif dcsCommon.stringStartsWith(formation, "CIRCLE") then
			-- units are arranged on perimeter of circle defined by radius 
--			trigger.action.outText("formation circle detected", 30)
			local currAngle = 0
			local angleInc = 2 * 3.14157 / num -- increase per spoke 
			for i=1, num do
				local u = theNewGroup.units[i] -- get unit 
				u.x = radius * math.cos(currAngle)
				u.y = radius * math.sin(currAngle)
				
				-- now baldower out heading 
				-- circle, circle_forward no modifier of heading
				if dcsCommon.stringStartsWith(formation, "CIRCLE_IN") then 
					-- make the heading inward faceing - that's angle + pi
					u.heading = u.heading + currAngle + 3.14157
				elseif dcsCommon.stringStartsWith(formation, "CIRCLE_OUT") then 
					u.heading = u.heading + currAngle + 0
				end

				currAngle = currAngle + angleInc
			end
		elseif formation == "GRID" or formation == "SQUARE" or formation == "RECT" then 
			if num < 2 then return end 
			-- arrange units in an w x h grid
			-- e-g- 12 units = 4 x 3. 
			-- calculate w 
			local w = math.floor(num^(0.5) + 0.5)
			dcsCommon.arrangeGroupInNColumns(theNewGroup, w, radius)
			--[[--
			local h = math.floor(num / w)
			--trigger.action.outText("AdcsC: num=" .. num .. " w=" .. w .. "h=" .. h .. " -- num%w=" .. num%w, 30)
			if (num % w) > 0 then 
				h = h + 1
			end
			
			--trigger.action.outText("BdcsC: num=" .. num .. " w=" .. w .. "h=" .. h, 30)
			
			-- now w * h always >= num and num items fir in that grid
			-- w is width, h is height, of course :) 
			-- now calculat xInc and yInc
			local i = 1
			local xInc = 0 
			if w > 1 then xInc = 2 * radius / (w-1) end
			local yInc = 0
			if h > 1 then yInc = 2 * radius / (h-1) end 
			local currY = radius 
			if h < 2 then currY = 0 end -- special:_ place in Y middle if only one row)
			while h > 0 do 
				local currX = radius 
				local wCnt = w 
				while wCnt > 0 and (i <= num) do 
					local u = theNewGroup.units[i] -- get unit 
					u.x = currX
					u.y = currY
					currX = currX - xInc
					wCnt = wCnt - 1
					i = i + 1
				end
				currY = currY - yInc 
				h = h - 1
			end
			--]]--
		elseif formation == "2DEEP" or formation == "2COLS" then
			if num < 2 then return end 
			-- arrange units in an 2 x h grid
			local w = 2
			dcsCommon.arrangeGroupInNColumnsDeep(theNewGroup, w, radius)

		elseif formation == "2WIDE" then
			if num < 2 then return end 
			-- arrange units in an 2 x h grid
			local w = 2
			dcsCommon.arrangeGroupInNColumns(theNewGroup, w, radius)
		else 
			trigger.action.outText("dcsCommon - unknown formation: " .. formation, 30)
		end
	
	end
	
	function dcsCommon.arrangeGroupInNColumns(theNewGroup, w, radius)
		local num = #theNewGroup.units
		local h = math.floor(num / w)
		if (num % w) > 0 then 
			h = h + 1
		end
		local i = 1
		local xInc = 0 
		if w > 1 then xInc = 2 * radius / (w-1) end
		local yInc = 0
		if h > 1 then yInc = 2 * radius / (h-1) end 
		local currY = radius 
		if h < 2 then currY = 0 end -- special:_ place in Y middle if only one row)
		while h > 0 do 
			local currX = radius 
			local wCnt = w 
			while wCnt > 0 and (i <= num) do 
				local u = theNewGroup.units[i] -- get unit 
				u.x = currX
				u.y = currY
				currX = currX - xInc
				wCnt = wCnt - 1
				i = i + 1
			end
			currY = currY - yInc 
			h = h - 1
		end
	end
	
	function dcsCommon.arrangeGroupInNColumnsDeep(theNewGroup, w, radius)
		local num = #theNewGroup.units
		local h = math.floor(num / w)
		if (num % w) > 0 then 
			h = h + 1
		end
		local i = 1
		local yInc = 0 
		if w > 1 then yInc = 2 * radius / (w-1) end
		local xInc = 0
		if h > 1 then xInc = 2 * radius / (h-1) end 
		local currX = radius 
		if h < 2 then currX = 0 end -- special:_ place in Y middle if only one row)
		while h > 0 do 
			local currY = radius 
			local wCnt = w 
			while wCnt > 0 and (i <= num) do 
				local u = theNewGroup.units[i] -- get unit 
				u.x = currX
				u.y = currY
				currY = currY - yInc
				wCnt = wCnt - 1
				i = i + 1
			end
			currX = currX - xInc 
			h = h - 1
		end
	end
	
	
	function dcsCommon.createGroundGroupWithUnits(name, theUnitTypes, radius, minDist, formation, innerRadius)
		if not minDist then mindist = 4 end -- meters
		if not formation then formation = "line" end 
		if not radius then radius = 30 end -- meters 
		if not innerRadius then innerRadius = 0 end
		formation = formation:upper()
		-- theUnitTypes can be either a single string or a table of strings
		-- see here for TypeName https://github.com/mrSkortch/DCS-miscScripts/tree/master/ObjectDB
		-- formation defines how the units are going to be arranged in the
		-- formation specified. 
		-- formations:
		--    (default) "line" (left to right along x) -- that is Y direction
		--    "line_V" a line top to bottom -- that is X direction
		--    "chevron" - left to right middle too top
		--    "scattered", "random" -- random, innerRadius used to clear area in center
		-- 	  "circle", "circle_forward" -- circle, forward facing
		--    "circle_in" -- circle, inwarf facing
		--    "circle_out" -- circle, outward facing

		-- first, we create a group
		local theNewGroup = dcsCommon.createEmptyGroundGroupData(name)
		
		-- now add a single unit or multiple units
		if type(theUnitTypes) ~= "table" then 
--			trigger.action.outText("dcsCommon - i am here", 30)
--			trigger.action.outText("dcsCommon - name " .. name, 30)
--			trigger.action.outText("dcsCommon - unit type " .. theUnitTypes, 30)
			
			local aUnit = {}
			aUnit = dcsCommon.createGroundUnitData(name .. "-1", theUnitTypes, false)
--			trigger.action.outText("dcsCommon - unit name retval " .. aUnit.name, 30)
			dcsCommon.addUnitToGroupData(aUnit, theNewGroup, 0, 0) -- create with data at location (0,0)
			return theNewGroup
		end 

		-- if we get here, theUnitTypes is a table
		-- now loop and create a unit for each table
		local num = 1
		for key, theType in pairs(theUnitTypes) do 
			-- trigger.action.outText("+++dcsC: creating unit " .. name .. "-" .. num .. ": " .. theType, 30)
			local aUnit = dcsCommon.createGroundUnitData(name .. "-"..num, theType, false)
			dcsCommon.addUnitToGroupData(aUnit, theNewGroup, 0, 0)
			num = num + 1
		end
		
		dcsCommon.arrangeGroupDataIntoFormation(theNewGroup, radius, minDist, formation, innerRadius)
		return theNewGroup

	
	end

-- create a new group, based on group in mission. Groups coords are 0,0 for group and all
-- x,y and heading
	function dcsCommon.createGroupDataFromLiveGroup(name, newName) 
		if not newName then newName = dcsCommon.uuid("uniqName") end
		-- get access to the group
		local liveGroup = Group.getByName(name)
		if not liveGroup then return nil end
		-- get the categorty
		local cat = liveGroup:getCategory()
		local theNewGroup = {}
		
		-- create a new empty group at (0,0) 
		if cat == Group.Category.AIRPLANE or cat == Group.Category.HELICOPTER then 
			theNewGroup = dcsCommon.createEmptyAircraftGroupData(newName)
		elseif cat == Group.Category.GROUND then
			theNewGroup = dcsCommon.createEmptyGroudGroupData(newName)
		else 
			trigger.action.outText("dcsCommon - unknown category: " .. cat, 30)
			return nil
		end
		

		-- now get all units from live group and create data units
		-- note that unit data for group has x=0, y=0
		liveUnits = liveGroup:getUnits()
		
		for index, theUnit in pairs(liveUnits) do 
			-- for each unit we get the desc 
			local desc = theUnit:getDesc() -- of interest is only typename 
			local newUnit = dcsCommon.createGroundUnitData(dcsCommon.uuid(newName),
														   desc.typeName,
														   false)
			-- we now basically have a ground unit at (0,0) 
			-- add mandatory fields by type
			if cat == Group.Category.AIRPLANE or cat == Group.Category.HELICOPTER then 
				newUnit.alt = 100 -- make it 100m
				newUnit.alt_type = "RADIO" -- AGL
				newUnit.speed = 77 -- m/s --> 150 knots
				newUnit.payload = dcsCommon.createPayload() -- empty payload
				newUnit.callsign = dcsCommon.createCallsign() -- 'enfield11'
				
			elseif cat == Group.Category.GROUND then
				-- we got all we need
			else 
				-- trigger.action.outText("dcsCommon - unknown category: " .. cat, 30)
				-- return nil
				-- we also got all we need
			end			
			
		end
	
	end;
	

	function dcsCommon.rotatePointAroundOrigin(inX, inY, angle) -- angle in degrees
		local degrees =  3.14152 / 180 -- ok, it's actually radiants. 
		angle = angle * degrees -- turns into rads
		local c = math.cos(angle)
		local s = math.sin(angle)
		local px
		local py 
		px = inX * c - inY * s
		py = inX * s + inY * c
		return px, py		
	end

	function dcsCommon.rotateUnitData(theUnit, degrees, cx, cy)
		if not cx then cx = 0 end
		if not cz then cz = 0 end
		local cy = cz 
		--trigger.action.outText("+++dcsC:rotGrp cy,cy = "..cx .. "," .. cy, 30)
		
		local rads = degrees *  3.14152 / 180
		do
			theUnit.x = theUnit.x - cx -- MOVE TO ORIGIN OF ROTATION
			theUnit.y = theUnit.y - cy 				
			theUnit.x, theUnit.y = dcsCommon.rotatePointAroundOrigin(theUnit.x, theUnit.y, degrees)
			theUnit.x = theUnit.x + cx -- MOVE BACK 
			theUnit.y = theUnit.y + cy 				

			-- may also want to increase heading by degreess
			theUnit.heading = theUnit.heading + rads 
		end
	end
	

	function dcsCommon.rotateGroupData(theGroup, degrees, cx, cz)
		if not cx then cx = 0 end
		if not cz then cz = 0 end
		local cy = cz 
		--trigger.action.outText("+++dcsC:rotGrp cy,cy = "..cx .. "," .. cy, 30)
		
		local rads = degrees *  3.14152 / 180
		-- turns all units in group around the group's center by degrees.
		-- may also need to turn individual units by same amount
		for i, theUnit in pairs (theGroup.units) do
			theUnit.x = theUnit.x - cx -- MOVE TO ORIGIN OF ROTATION
			theUnit.y = theUnit.y - cy 				
			theUnit.x, theUnit.y = dcsCommon.rotatePointAroundOrigin(theUnit.x, theUnit.y, degrees)
			theUnit.x = theUnit.x + cx -- MOVE BACK 
			theUnit.y = theUnit.y + cy 				

			-- may also want to increase heading by degreess
			theUnit.heading = theUnit.heading + rads 
		end
	end

	function dcsCommon.offsetGroupData(theGroup, dx, dy)
		-- add dx and dy to group's and all unit's coords
		for i, theUnit in pairs (theGroup.units) do 
			theUnit.x = theUnit.x + dx
			theUnit.y = theUnit.y + dy
		end
		
		theGroup.x = theGroup.x + dx
		theGroup.y = theGroup.y + dy 
	end
	
	function dcsCommon.moveGroupDataTo(theGroup, xAbs, yAbs)
		local dx = xAbs-theGroup.x
		local dy = yAbs-theGroup.y
		dcsCommon.offsetGroupData(theGroup, dx, dy)
	end
	
	-- static objectr shapes and types are defined here
	-- https://github.com/mrSkortch/DCS-miscScripts/tree/master/ObjectDB/Statics
	
	function dcsCommon.createStaticObjectData(name, objType, heading, dead, cargo, mass)
		local staticObj = {}
		if not heading then heading = 0 end 
		if not dead then dead = false end 
		if not cargo then cargo = false end 
		objType = dcsCommon.trim(objType) 
		
		staticObj.heading = heading
		-- staticObj.groupId = 0
		-- staticObj.shape_name = shape -- e.g. H-Windsock_RW
		staticObj.type = objType  -- e.g. Windsock
		-- ["unitId"] = 3,
		staticObj.rate = 1 -- score when killed
		staticObj.name = name
		-- staticObj.category = "Fortifications",
		staticObj.y = 0
		staticObj.x = 0
		staticObj.dead = dead
		staticObj.canCargo = cargo -- to cargo
		if cargo then 
			if not mass then mass = 1234 end 
			staticObj.mass = mass -- to cargo
		end
		return staticObj
	end
	
	function dcsCommon.createStaticObjectDataAt(loc, name, objType, heading, dead)
		local theData = dcsCommon.createStaticObjectData(name, objType, heading, dead)
		theData.x = loc.x
		theData.y = loc.z 
		return theData
	end
	
	function dcsCommon.createStaticObjectForCoalitionAtLocation(theCoalition, loc, name, objType, heading, dead) 
		if not heading then heading = math.random(360) * 3.1415 / 180 end
		local theData = dcsCommon.createStaticObjectDataAt(loc, name, objType, heading, dead)
		local theStatic = coalition.addStaticObject(theCoalition, theData)
		return theStatic
	end
	
	function dcsCommon.createStaticObjectForCoalitionInRandomRing(theCoalition, objType, x, z, innerRadius, outerRadius, heading, alive) 
		if not outerRadius then outerRadius = innerRadius end
		if not heading then heading = math.random(360) * 3.1415 / 180 end
		local dead = not alive
		local p = dcsCommon.randomPointInCircle(outerRadius, innerRadius, x, z)
		local theData = dcsCommon.createStaticObjectData(dcsCommon.uuid("static"), objType, heading, dead)
		theData.x = p.x
		theData.y = p.z 
		
		local theStatic = coalition.addStaticObject(theCoalition, theData)
		return theStatic
	end
	
	
	
	function dcsCommon.linkStaticDataToUnit(theStatic, theUnit, dx, dy, heading)
		if not theStatic then 
			trigger.action.OutText("+++dcsC: NIL theStatic on linkStatic!", 30)
			return 
		end
		-- NOTE: we may get current heading and subtract/add 
		-- to original heading 
		local rotX, rotY = dcsCommon.rotatePointAroundOrigin(dx, dy, -heading)
		
		if not theUnit then return end
		if not theUnit:isExist() then return end 
		theStatic.linkOffset = true 
		theStatic.linkUnit = theUnit:getID()
		local unitPos = theUnit:getPoint()
		local offsets = {}
		offsets.x = rotX  
		offsets.y = rotY 
		offsets.angle = 0
		theStatic.offsets = offsets
	end
	
	function dcsCommon.offsetStaticData(theStatic, dx, dy)
		theStatic.x = theStatic.x + dx
		theStatic.y = theStatic.y + dy
		-- now check if thre is a route (for linked objects)
		if theStatic.route then 
			-- access points[1] x and y and copy from main
			theStatic.route.points[1].x = theStatic.x
			theStatic.route.points[1].y = theStatic.y
		end
	end
	
	function dcsCommon.moveStaticDataTo(theStatic, x, y)
		theStatic.x = x
		theStatic.y = y
		-- now check if thre is a route (for linked objects)
		if theStatic.route then 
			-- access points[1] x and y and copy from main
			theStatic.route.points[1].x = theStatic.x
			theStatic.route.points[1].y = theStatic.y
		end

	end
	
--
--
-- M I S C   M E T H O D S 
--
--

	function dcsCommon.arrayContainsString(theArray, theString) 
		if not theArray then return false end
		if not theString then return false end
		for i = 1, #theArray do 
			if theArray[i] == theString then return true end 
		end
		return false 
	end
	
	function dcsCommon.splitString(inputstr, sep) 
        if sep == nil then
            sep = "%s"
        end
		if inputstr == nil then 
			inputstr = ""
		end
		
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
			table.insert(t, str)
        end
        return t
	
	end
	
	function dcsCommon.trimFront(inputstr) 
		if not inputstr then return nil end 
		local s = inputstr
		while string.len(s) > 1 and string.sub(s, 1, 1) == " " do 
			local snew = string.sub(s, 2) -- all except first
			s = snew
		end
		return s
	end
	
	function dcsCommon.trimBack(inputstr)
		if not inputstr then return nil end 
		local s = inputstr
		while string.len(s) > 1 and string.sub(s, -1) == " " do 
			local snew = string.sub(s, 1, -2) -- all except last
			s = snew
		end
		return s
	end
	
	function dcsCommon.trim(inputstr) 
		local t1 = dcsCommon.trimFront(inputstr)
		local t2 = dcsCommon.trimBack(t1)
		return t2
	end
	
	function dcsCommon.trimArray(theArray)
		local trimmedArray = {}
		for idx, element in pairs(theArray) do 
			local tel = dcsCommon.trim(element)
			table.insert(trimmedArray, tel)
		end
		return trimmedArray
	end
	
	function dcsCommon.stringIsPositiveNumber(theString)
		-- only full integer positive numbers supported 
		if not theString then return false end 
--		if theString == "" then return false end 
		for i = 1, #theString do 
			local c = theString:sub(i,i)
			if c < "0" or c > "9" then return false end 
		end
		return true 
	end
	
	function dcsCommon.stringStartsWithDigit(theString)
		if #theString < 1 then return false end 
		local c = string.sub(theString, 1, 1) 
		return c >= "0" and c <= "9" 
	end
	
	function dcsCommon.stringStartsWithLetter(theString)
		if #theString < 1 then return false end 
		local c = string.sub(theString, 1, 1)
		if c >= "a" and c <= "z" then return true end  
		if c >= "A" and c <= "Z" then return true end 
		return false 
	end
	
	function dcsCommon.stringStartsWith(theString, thePrefix)
		return theString:find(thePrefix) == 1
	end
	
	function dcsCommon.removePrefix(theString, thePrefix)
		if not dcsCommon.stringStartsWith(theString, thePrefix) then 
			return theString
		end;
		return theString:sub(1 + #thePrefix)
	end
	
	function dcsCommon.stringEndsWith(theString, theEnding)
		return theEnding == "" or theString:sub(-#theEnding) == theEnding
	end
	
	function dcsCommon.removeEnding(theString, theEnding) 
		if not dcsCommon.stringEndsWith(theString, theEnding) then 
			return theString
		end
		return theString:sub(1, #theString - #theEnding)
	end
	
	function dcsCommon.containsString(inString, what, caseSensitive)
		if (not caseSensitive) then 
			inString = string.upper(inString)
			what = string.upper(what)
		end
		if inString == what then return true end -- when entire match 
		return string.find(inString, what)
	end
	
	function dcsCommon.bool2Text(theBool) 
		if not theBool then theBool = false end 
		if theBool then return "true" end 
		return "false"
	end
	
	function dcsCommon.bool2YesNo(theBool)
		if not theBool then theBool = false end 
		if theBool then return "yes" end 
		return "no"
	end

	-- recursively show the contents of a variable
	function dcsCommon.dumpVar(key, value, prefix, inrecursion)
		if not inrecursion then 
			-- output a marker to find in the log / screen
			env.info("*** dcsCommon vardump START")
		end
		if not value then value = "nil" end
		if not prefix then prefix = "" end
		prefix = " " .. prefix
		if type(value) == "table" then 
			env.info(prefix .. key .. ": [ ")
			-- iterate through all kvp
			for k,v in pairs (value) do
				dcsCommon.dumpVar(k, v, prefix, true)
			end
			env.info(prefix .. " ] - end " .. key)
			
		elseif type(value) == "boolean" then 
			local b = "false"
			if value then b = "true" end
			env.info(prefix .. key .. ": " .. b)
			
		else -- simple var, show contents, ends recursion
			env.info(prefix .. key .. ": " .. value)
		end
		
		if not inrecursion then 
			-- output a marker to find in the log / screen
			trigger.action.outText("=== dcsCommon vardump END", 30)
			env.info("=== dcsCommon vardump END")
		end
	end
	
	function dcsCommon.dumpVar2Str(key, value, prefix, inrecursion)
		if not inrecursion then 
			-- output a marker to find in the log / screen
			trigger.action.outText("*** dcsCommon vardump START",30)
		end
		if not value then value = "nil" end
		if not prefix then prefix = "" end
		prefix = " " .. prefix
		if type(value) == "table" then 
			trigger.action.outText(prefix .. key .. ": [ ", 30)
			-- iterate through all kvp
			for k,v in pairs (value) do
				dcsCommon.dumpVar2Str(k, v, prefix, true)
			end
			trigger.action.outText(prefix .. " ] - end " .. key, 30)
			
		elseif type(value) == "boolean" then 
			local b = "false"
			if value then b = "true" end
			trigger.action.outText(prefix .. key .. ": " .. b, 30)
			
		else -- simple var, show contents, ends recursion
			trigger.action.outText(prefix .. key .. ": " .. value, 30)
		end
		
		if not inrecursion then 
			-- output a marker to find in the log / screen
			trigger.action.outText("=== dcsCommon vardump END", 30)
			--env.info("=== dcsCommon vardump END")
		end
	end
	

	dcsCommon.simpleUUID = 76543 -- a number to start. as good as any
	function dcsCommon.numberUUID()
		dcsCommon.simpleUUID = dcsCommon.simpleUUID + 1
		return dcsCommon.simpleUUID
	end

	function dcsCommon.uuid(prefix)
		dcsCommon.uuIdent = dcsCommon.uuIdent + 1
		if not prefix then prefix = dcsCommon.uuidStr end
		return prefix .. "-" .. dcsCommon.uuIdent
	end
	
	function dcsCommon.event2text(id) 
		if not id then return "error" end
		if id == 0 then return "invalid" end
		-- translate the event id to text
		local events = {"shot", "hit", "takeoff", "land",
						"crash", "eject", "refuel", "dead",
						"pilot dead", "base captured", "mission start", "mission end", -- 12
						"took control", "refuel stop", "birth", "human failure", 
						"det. failure", "engine start", "engine stop", "player enter unit",
						"player leave unit", "player comment", "start shoot", "end shoot",
						"mark add", "mark changed", "makr removed", "kill", 
						"score", "unit lost", "land after eject", "Paratrooper land", 
						"chair discard after eject", "weapon add", "trigger zone", "landing quality mark",
						"BDA", "max"}
		if id > #events then return "Unknown (ID=" .. id .. ")" end
		return events[id]
	end

	function dcsCommon.smokeColor2Text(smokeColor)
		if (smokeColor == 0) then return "Green" end
		if (smokeColor == 1) then return "Red" end
		if (smokeColor == 2) then return "White" end
		if (smokeColor == 3) then return "Orange" end
		if (smokeColor == 4) then return "Blue" end
		
		return ("unknown: " .. smokeColor)
	end
	
	function dcsCommon.smokeColor2Num(smokeColor)
		if not smokeColor then smokeColor = "green" end 
		if type(smokeColor) ~= "string" then return 0 end 
		smokeColor = smokeColor:lower()
		if (smokeColor == "green") then return 0 end 
		if (smokeColor == "red") then return 1 end 
		if (smokeColor == "white") then return 2 end 
		if (smokeColor == "orange") then return 3 end 
		if (smokeColor == "blue") then return 4 end 
		return 0
	end
	
	function dcsCommon.markPointWithSmoke(p, smokeColor)
		local x = p.x 
		local z = p.z -- do NOT change the point directly
		-- height-correct
		local y = land.getHeight({x = x, y = z})
		local newPoint= {x = x, y = y + 2, z = z}
		trigger.action.smoke(newPoint, smokeColor)
	end

--
--
-- V E C T O R   M A T H 
--
--
function dcsCommon.vAdd(a, b) 
	local r = {}
	if not a then a = {x = 0, y = 0, z = 0} end
	if not b then b = {x = 0, y = 0, z = 0} end
	r.x = a.x + b.x 
	r.y = a.y + b.y 
	r.z = a.z + b.z 
	return r 
end

function dcsCommon.vSub(a, b) 
	local r = {}
	if not a then a = {x = 0, y = 0, z = 0} end
	if not b then b = {x = 0, y = 0, z = 0} end
	r.x = a.x - b.x 
	r.y = a.y - b.y 
	r.z = a.z - b.z 
	return r 
end

function dcsCommon.vMultScalar(a, f) 
	local r = {}
	if not a then a = {x = 0, y = 0, z = 0} end
	if not f then f = 0 end
	r.x = a.x * f 
	r.y = a.y * f 
	r.z = a.z * f 
	return r 
end

function dcsCommon.vLerp (a, b, t)
	if not a then a = {x = 0, y = 0, z = 0} end
	if not b then b = {x = 0, y = 0, z = 0} end
	
	local d = dcsCommon.vSub(b, a)
	local dt = dcsCommon.vMultScalar(d, t)
	local r = dcsCommon.vAdd(a, dt)
	return r
end

function dcsCommon.mag(x, y, z) 
	if not x then x = 0 end
	if not y then y = 0 end 
	if not z then z = 0 end 
	
	return (x * x + y * y + z * z)^0.5
end

function dcsCommon.vMag(a) 
	if not a then return 0 end 
	if not a.x then a.x = 0 end 
	if not a.y then a.y = 0 end 
	if not a.z then a.z = 0 end
	return dcsCommon.mag(a.x, a.y, a.z) 
end

function dcsCommon.magSquare(x, y, z) 
	if not x then x = 0 end
	if not y then y = 0 end 
	if not z then z = 0 end 
	
	return (x * x + y * y + z * z)
end

function dcsCommon.vNorm(a) 
	if not a then return {x = 0, y = 0, z = 0} end 
	m = dcsCommon.vMag(a)
	if m <= 0 then return {x = 0, y = 0, z = 0} end 
	local r = {}
	r.x = a.x / m 
	r.y = a.y / m 
	r.z = a.z / m
	return r 
end

function dcsCommon.dot (a, b) 
	if not a then a = {} end 
	if not a.x then a.x = 0 end 
	if not a.y then a.y = 0 end 
	if not a.z then a.z = 0 end
	if not b then b = {} end 
	if not b.x then b.x = 0 end 
	if not b.y then b.y = 0 end 
	if not b.z then b.z = 0 end 
	
	return a.x * b.x + a.y * b.y + a.z * b.z 
end
--
-- UNIT MISC
-- 
function dcsCommon.isSceneryObject(theUnit)
	if not theUnit then return false end
	return theUnit.getCoalition == nil -- scenery objects do not return a coalition 
end

function dcsCommon.isTroopCarrier(theUnit)
	-- return true if conf can carry troups
	if not theUnit then return false end 
	local uType = theUnit:getTypeName()
	if dcsCommon.arrayContainsString(dcsCommon.troopCarriers, uType) then 
		-- may add additional tests before returning true
		return true
	end
	return false
end

function dcsCommon.getUnitAlt(theUnit)
	if not theUnit then return 0 end
	if not theUnit:isExist() then return 0 end 
	local p = theUnit:getPoint()
	return p.y 
end

function dcsCommon.getUnitAGL(theUnit)
	if not theUnit then return 0 end
	if not theUnit:isExist() then return 0 end 
	local p = theUnit:getPoint()
	local alt = p.y 
	local loc = {x = p.x, y = p.z}
	local landElev = land.getHeight(loc)
	return alt - landElev
end 

function dcsCommon.getUnitSpeed(theUnit)
	if not theUnit then return 0 end
	if not theUnit:isExist() then return 0 end 
	local v = theUnit:getVelocity()
	return dcsCommon.mag(v.x, v.y, v.z)
end

-- closing velocity of u1 and u2, seen from u1
function dcsCommon.getClosingVelocity(u1, u2)
	if not u1 then return 0 end 
	if not u2 then return 0 end 
	if not u1:isExist() then return 0 end 
	if not u2:isExist() then return 0 end 
	local v1 = u1:getVelocity()
	local v2 = u2:getVelocity()
	local dV = dcsCommon.vSub(v1,v2)
	local a = u1:getPoint()
	local b = u2:getPoint() 
	local aMinusB = dcsCommon.vSub(a,b) -- vector from u2 to u1
	local abMag = dcsCommon.vMag(aMinusB) -- distance u1 to u2 
	if abMag < .0001 then return 0 end 
	-- project deltaV onto vector from u2 to u1 
	local vClose = dcsCommon.dot(dV, aMinusB) / abMag 
	return vClose 
end

function dcsCommon.getGroupAvgSpeed(theGroup)
	if not theGroup then return 0 end 
	if not dcsCommon.isGroupAlive(theGroup) then return 0 end 
	local totalSpeed = 0
	local cnt = 0 
	local livingUnits = theGroup:getUnits()
	for idx, theUnit in pairs(livingUnits) do 
		cnt = cnt + 1
		totalSpeed = totalSpeed + dcsCommon.getUnitSpeed(theUnit)
	end 
	if cnt == 0 then return 0 end 
	return totalSpeed / cnt 
end
 
function dcsCommon.getGroupMaxSpeed(theGroup)
	if not theGroup then return 0 end 
	if not dcsCommon.isGroupAlive(theGroup) then return 0 end 
	local maxSpeed = 0
	local livingUnits = theGroup:getUnits()
	for idx, theUnit in pairs(livingUnits) do 
		currSpeed = dcsCommon.getUnitSpeed(theUnit)
		if currSpeed > maxSpeed then maxSpeed = currSpeed end 
	end 
	return maxSpeed
end 

function dcsCommon.getUnitHeading(theUnit)
	if not theUnit then return 0 end 
	if not theUnit:isExist() then return 0 end 
	local pos = theUnit:getPosition() -- returns three vectors, p is location

	local heading = math.atan2(pos.x.z, pos.x.x)
	-- make sure positive only, add 260 degrees
	if heading < 0 then
		heading = heading + 2 * math.pi	-- put heading in range of 0 to 2*pi
	end
	return heading 
end

function dcsCommon.getUnitHeadingDegrees(theUnit)
	local heading = dcsCommon.getUnitHeading(theUnit)
	return heading * 57.2958 -- 180 / math.pi 
end

function dcsCommon.unitIsInfantry(theUnit)
	if not theUnit then return false end 
	if not theUnit:isExist() then return end
	local theType = theUnit:getTypeName()
	local isInfantry =  
				dcsCommon.containsString(theType, "infantry", false) or 
				dcsCommon.containsString(theType, "paratrooper", false) or
				dcsCommon.containsString(theType, "stinger", false) or
				dcsCommon.containsString(theType, "manpad", false) or
				dcsCommon.containsString(theType, "soldier", false) or 
				dcsCommon.containsString(theType, "SA-18 Igla", false)
	return isInfantry
end

function dcsCommon.coalition2county(inCoalition)
	-- simply return UN troops for 0 neutral,
	-- joint red for 1  red
	-- joint blue for 2 blue 
	if inCoalition == 1 then return 81 end -- cjtf red
	if inCoalition == 2 then return 80 end -- blue 
	if type(inCoalition) == "string" then 
			inCoalition = inCoalition:lower()
			if inCoalition == "red" then return 81 end
			if inCoalition == "blue" then return 80 end
	end
		
	trigger.action.outText("+++dcsC: coalition2county in (" .. inCoalition .. ") converts to UN (82)!", 30)
	return 82 -- UN 
	
end

--
--
-- INIT
--
--
	-- init any variables the lib requires internally
	function dcsCommon.init()
		cbID = 0
		dcsCommon.uuIdent = 0
		if (dcsCommon.verbose) or true then
		  trigger.action.outText("dcsCommon v" .. dcsCommon.version .. " loaded", 10)
		end
	end

	
-- do init. 
dcsCommon.init()

--[[--

to do: 
- formation 2Column
- formation 3Column

-]]--
