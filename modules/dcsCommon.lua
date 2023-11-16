dcsCommon = {}
dcsCommon.version = "2.9.6"
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
       - coalition2county also understands 'red' and 'blue'
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
 2.5.7 - point2text(p) 
 2.5.8 - string2GroupCat()
 2.5.9 - string2ObjectCat()
 2.6.0 - unified uuid, removed uuIdent
 2.6.1 - removed bug in rotateUnitData: cy --> cz param passing  
 2.6.2 - new combineTables()
 2.6.3 - new tacan2freq()
 2.6.4 - new processHMS()
 2.6.5 - new bearing2compass()
       - new bearingdegrees2compass()
	   - new latLon2Text() - based on mist 
 2.6.6 - new nowString() 
       - new str2num()
	   - new stringRemainsStartingWith()
       - new stripLF()
	   - new removeBlanks()
 2.6.7 - new menu2text()
 2.6.8 - new getMissionName()
       - new flagArrayFromString()
 2.6.9 - new getSceneryObjectsInZone()
       - new getSceneryObjectInZoneByName()
 2.7.0 - new synchGroupData()
         clone, topClone and copyArray now all nil-trap 
 2.7.1 - new isPlayerUnit() -- moved from cfxPlayer
         new getAllExistingPlayerUnitsRaw - from cfxPlayer
		 new typeIsInfantry()
 2.7.2 - new rangeArrayFromString()
         fixed leading blank bug in flagArrayFromString
		 new incFlag()
		 new decFlag()
		 nil trap in stringStartsWith()
		 new getClosestFreeSlotForCatInAirbaseTo()
 2.7.3 - new string2Array()
       - additional guard for isPlayerUnit
 2.7.4 - new array2string()
 2.7.5 - new bitAND32()
       - new LSR()
	   - new num2bin()
 2.7.6 - new getObjectsForCatAtPointWithRadius()
 2.7.7 - clone() has new stripMeta option. pass true to remove all meta tables 
	   - dumpVar2Str detects meta tables 
	   - rotateGroupData kills unit's psi value if it existed since it messes with heading 
	   - rotateGroupData - changes psi to -heading if it exists rather than nilling
 2.7.8 - new getGeneralDirection()
	   - new getNauticalDirection()
	   - more robust guards for getUnitSpeed
 2.7.9 - new bool2Num(theBool)
	   - new aspectByDirection()
	   - createGroundGroupWithUnits corrected spelling of minDist, crashed scattered formation
	   - randomPointInCircle fixed erroneous local for x, z 
	   - "scattered" formation repaired
 2.7.10- semaphore groundwork 
 2.8.0 - new collectMissionIDs at start-up  
	   - new getUnitNameByID
	   - new getGroupNameByID
	   - bool2YesNo alsco can return NIL
	   - new getUnitStartPosByID
 2.8.1 - arrayContainsString: type checking for theArray and warning
	   - processStringWildcards()
	   - new wildArrayContainsString() 
	   - fix for stringStartsWith oddity with aircraft types 
 2.8.2 - better fixes for string.find() in stringStartsWith and containsString
       - dcsCommon.isTroopCarrier(theUnit, carriers) new carriers optional param
	   - better guards for getUnitAlt and getUnitAGL
	   - new newPointAtDegreesRange()
	   - new newPointAtAngleRange()
	   - new isTroopCarrierType()
	   - stringStartsWith now supports case insensitive match 
	   - isTroopCarrier() supports 'any' and 'all'
	   - made getEnemyCoalitionFor() more resilient 
	   - fix to smallRandom for negative numbers
	   - isTroopCarrierType uses wildArrayContainsString
 2.8.3 - small optimizations in bearingFromAtoB()
       - new whichSideOfMine()
 2.8.4 - new rotatePointAroundOriginRad()
	   - new rotatePointAroundPointDeg()
	   - new rotatePointAroundPointRad()
	   - getClosestAirbaseTo() now supports passing list of air bases
 2.8.5 - better guard in getGroupUnit()
 2.8.6 - phonetic helpers 
		 new spellString()
 2.8.7 - new flareColor2Num()
       - new flareColor2Text()
       - new iteratePlayers()
 2.8.8 - new hexString2RGBA()
       - new playerName2Coalition()
	   - new coalition2Text()
 2.8.9 - vAdd supports xy and xyz 
       - vSub supports xy and xyz 
	   - vMultScalar supports xy and xyz 
2.8.10 - tacan2freq now integrated with module (blush) 
       - array2string cosmetic default 
	   - vMultScalar corrected bug in accessing b.z 
	   - new randomLetter()
	   - new getPlayerUnit()
	   - new getMapName()
	   - new getMagDeclForPoint()
2.9.0  - createPoint() moved from cfxZones
	   - copyPoint() moved from cfxZones
	   - numberArrayFromString() moved from cfxZones
2.9.1  - new createSimpleRoutePointData()
	   - createOverheadAirdromeRoutPintData corrected and legacy support added 
	   - new bearingFromAtoBusingXY()
	   - corrected verbosity for bearingFromAtoB
	   - new getCountriesForCoalition()
2.9.2  - updated event2text
2.9.3  - getAirbasesWhoseNameContains now supports category tables for filtering 
2.9.4  - new bearing2degrees()
2.9.5  - distanceOfPointPToLineXZ(p, p1, p2)
2.9.6  - new addToTableIfNew()

--]]--

	-- dcsCommon is a library of common lua functions 
	-- for easy access and simple mission programming
	-- (c) 2021 - 2023 by Chritian Franz and cf/x AG

	dcsCommon.verbose = false -- set to true to see debug messages. Lots of them
	dcsCommon.uuidStr = "uuid-"
	dcsCommon.simpleUUID = 76543 -- a number to start. as good as any
	
	-- globals
	dcsCommon.cbID = 0 -- callback id for simple callback scheduling
	dcsCommon.troopCarriers = {"Mi-8MT", "UH-1H", "Mi-24P"} -- Ka-50, Apache and Gazelle can't carry troops
	dcsCommon.coalitionSides = {0, 1, 2}
	dcsCommon.maxCountry = 86 -- number of countries defined in total 
	
	-- lookup tables
	dcsCommon.groupID2Name = {}
	dcsCommon.unitID2Name = {}
	dcsCommon.unitID2X = {}
	dcsCommon.unitID2Y = {}

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

	-- read all groups and units from miz and build a reference table
	function dcsCommon.collectMissionIDs()
	-- create cross reference tables to be able to get a group or
	-- unit's name by ID
		for coa_name_miz, coa_data in pairs(env.mission.coalition) do -- iterate all coalitions
			local coa_name = coa_name_miz
			if string.lower(coa_name_miz) == 'neutrals' then -- remove 's' at neutralS
				coa_name = 'neutral'
			end
			-- directly convert coalition into number for easier access later
			local coaNum = 0
			if coa_name == "red" then coaNum = 1 end 
			if coa_name == "blue" then coaNum = 2 end 
			
			if type(coa_data) == 'table' then -- coalition = {bullseye, nav_points, name, county}, 
											  -- with county being an array 
				if coa_data.country then -- make sure there a country table for this coalition
					for cntry_id, cntry_data in pairs(coa_data.country) do -- iterate all countries for this 
						-- per country = {id, name, vehicle, helicopter, plane, ship, static}
						local countryName = string.lower(cntry_data.name)
						local countryID = cntry_data.id 
						if type(cntry_data) == 'table' then	-- filter strings .id and .name 
							for obj_type_name, obj_type_data in pairs(cntry_data) do
								-- only look at helos, ships, planes and vehicles
								if obj_type_name == "helicopter" or 
								   obj_type_name == "ship" or 
								   obj_type_name == "plane" or 
								   obj_type_name == "vehicle" or 
								   obj_type_name == "static" -- what about "cargo"?
								then -- (so it's not id or name)
									local category = obj_type_name
									if ((type(obj_type_data) == 'table') and obj_type_data.group and (type(obj_type_data.group) == 'table') and (#obj_type_data.group > 0)) then	--there's at least one group!
										for group_num, group_data in pairs(obj_type_data.group) do
											
											local aName = group_data.name 
											local aID = group_data.groupId
											-- store this reference 
											dcsCommon.groupID2Name[aID] = aName 
											
											-- now iterate all units in this group 
											-- for player into 
											for unit_num, unit_data in pairs(group_data.units) do
												if unit_data.name and unit_data.unitId then 
													-- store this reference 
													dcsCommon.unitID2Name[unit_data.unitId] = unit_data.name
													dcsCommon.unitID2X[unit_data.unitId] = unit_data.x
													dcsCommon.unitID2Y[unit_data.unitId] = unit_data.y
												end
											end -- for all units
										end -- for all groups 
									end --if has category data 
								end --if plane, helo etc... category
							end --for all objects in country 
						end --if has country data 
					end --for all countries in coalition
				end --if coalition has country table 
			end -- if there is coalition data  
		end --for all coalitions in mission 
	end

	function dcsCommon.getUnitNameByID(theID)
		-- accessor function for later expansion
		return dcsCommon.unitID2Name[theID]
	end
	
	function dcsCommon.getGroupNameByID(theID)
		-- accessor function for later expansion 
		return dcsCommon.groupID2Name[theID]
	end

	function dcsCommon.getUnitStartPosByID(theID)
		local x = dcsCommon.unitID2X[theID]
		local y = dcsCommon.unitID2Y[theID]
		return x, y
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
		theNum = math.floor(theNum)
		if theNum >= 50 then return math.random(theNum) end
		if theNum < 1 then
			trigger.action.outText("smallRandom: invoke with argument < 1 (" .. theNum .. "), using 1", 30)
			theNum = 1 
		end 
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

	-- combine table. creates new 
	function dcsCommon.combineTables(inOne, inTwo)
		local outTable = {}
		for idx, element in pairs(inOne) do 
			table.insert(outTable, element)
		end
		for idx, element in pairs(inTwo) do 
			table.insert(outTable, element)
		end
		return outTable
	end
	
	function dcsCommon.addToTableIfNew(theTable, theElement)
		for idx, anElement in pairs(theTable) do 
			if anElement == theElement then return end 
		end
		table.insert(theTable, theElement)
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
	-- filterCoalition is optional and can be 0 (neutral), 1 (red), 2 (blue) or 
	-- a table containing categories, e.g. {0, 2} = airfields and ships but not farps 
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
					local aCat = dcsCommon.getAirbaseCat(aBase)
					if type(filterCat) == "table" then 
						local hit = false
						for idx, fCat in pairs(filterCat) do 
							if fCat == aCat then hit = true end
						end
						doAdd = doAdd and hit 
					else 
						-- make sure the airbase is of that category 
						local airCat = aCat
						doAdd = doAdd and airCat == filterCat 
					end
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

	function dcsCommon.getClosestAirbaseTo(thePoint, filterCat, filterCoalition, allYourBase)
		local delta = math.huge
		if not allYourBase then 
			allYourBase = dcsCommon.getAirbasesWhoseNameContains("*", filterCat, filterCoalition) -- get em all and filter
		end 
		
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

	function dcsCommon.getClosestFreeSlotForCatInAirbaseTo(cat, x, y, theAirbase, ignore)
		if not theAirbase then return nil end 
		if not ignore then ignore = {} end 
		if not cat then return nil end 
		if (not cat == "helicopter") and (not cat == "plane") then 
			trigger.action.outText("+++common-getslotforcat: wrong cat <" .. cat .. ">", 30)
			return nil 
		end
		local allFree = theAirbase:getParking(true) --  only free slots
		local filterFreeByType = {}
		for idx, aSlot in pairs(allFree) do 
			local termT = aSlot.Term_Type
			if termT == 104 or 
			(termT == 72 and cat == "plane") or 
			(termT == 68 and cat == "plane") or 
			(termT == 40 and cat == "helicopter") then 
				table.insert(filterFreeByType, aSlot)
			else 
				-- we skip this slot, not good for type 
			end
		end
		
		if #filterFreeByType == 0 then 
			return nil
		end 
		
		local reallyFree = {}
		for idx, aSlot in pairs(filterFreeByType) do 
			local slotNum = aSlot.Term_Index
			isTaken = false 
			for idy, taken in pairs(ignore) do 
				if taken == slotNum then isTaken = true end 
			end
			if not isTaken then 
				table.insert(reallyFree, aSlot)
			end
		end
		
		if #reallyFree < 1 then 
			reallyFree = filterFreeByType
		end
		
		local closestDist = math.huge 
		local closestSlot = nil 
		local p = {x = x, y = 0, z = y} -- !!
		for idx, aSlot in pairs(reallyFree) do 
			local sp = {x = aSlot.vTerminalPos.x, y = 0, z = aSlot.vTerminalPos.z}
			local currDist = dcsCommon.distFlat(p, sp)
			--trigger.action.outText("slot <" .. aSlot.Term_Index .. "> has dist " .. math.floor(currDist) .. " and _0 of <" .. aSlot.Term_Index_0 .. ">", 30)
			if currDist < closestDist then 
				closestSlot = aSlot 
				closestDist = currDist 
			end
		end
		--trigger.action.outText("slot <" .. closestSlot.Term_Index .. "> has closest dist <" .. math.floor(closestDist) .. ">", 30)
		return closestSlot
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
		if not A then 
			trigger.action.outText("WARNING: no 'A' in bearingFromAtoB", 30)
			return 0
		end
		if not B then
			trigger.action.outText("WARNING: no 'B' in bearingFromAtoB", 30)
			return 0
		end
		if not A.x then 
			trigger.action.outText("WARNING: no 'A.x' (type A =<" .. type(A) .. ">)in bearingFromAtoB", 30)
			return 0
		end
		if not A.z then 
			trigger.action.outText("WARNING: no 'A.z' (type A =<" .. type(A) .. ">)in bearingFromAtoB", 30)
			return 0
		end
		if not B.x then 
			trigger.action.outText("WARNING: no 'B.x' (type B =<" .. type(B) .. ">)in bearingFromAtoB", 30)
			return 0
		end
		if not B.z then 
			trigger.action.outText("WARNING: no 'B.z' (type B =<" .. type(B) .. ">)in bearingFromAtoB", 30)
			return 0
		end
		
		local dx = B.x - A.x
		local dz = B.z - A.z
		local bearing = math.atan2(dz, dx) -- in radiants
		return bearing
	end

	function dcsCommon.bearingFromAtoBusingXY(A, B) -- coords in x, y 
		if not A then 
			trigger.action.outText("WARNING: no 'A' in bearingFromAtoBXY", 30)
			return 0
		end
		if not B then
			trigger.action.outText("WARNING: no 'B' in bearingFromAtoBXY", 30)
			return 0
		end
		if not A.x then 
			trigger.action.outText("WARNING: no 'A.x' (type A =<" .. type(A) .. ">)in bearingFromAtoBXY", 30)
			return 0
		end
		if not A.y then 
			trigger.action.outText("WARNING: no 'A.y' (type A =<" .. type(A) .. ">)in bearingFromAtoBXY", 30)
			return 0
		end
		if not B.x then 
			trigger.action.outText("WARNING: no 'B.x' (type B =<" .. type(B) .. ">)in bearingFromAtoBXY", 30)
			return 0
		end
		if not B.y then 
			trigger.action.outText("WARNING: no 'B.y' (type B =<" .. type(B) .. ">)in bearingFromAtoBXY", 30)
			return 0
		end
		
		local dx = B.x - A.x
		local dz = B.y - A.y
		local bearing = math.atan2(dz, dx) -- in radiants
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
	
	function dcsCommon.bearing2degrees(inRad)
		local degrees = inRad / math.pi * 180
		if degrees < 0 then degrees = degrees + 360 end 
		if degrees > 360 then degrees = degrees - 360 end 
		return degrees 
	end
	
	function dcsCommon.bearing2compass(inrad)
		local bearing = math.floor(inrad / math.pi * 180)
		if bearing < 0 then bearing = bearing + 360 end
		if bearing > 360 then bearing = bearing - 360 end
		return dcsCommon.bearingdegrees2compass(bearing)
	end
	
	function dcsCommon.bearingdegrees2compass(bearing)
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
		while direction >= 360 do 
			direction = direction - 360
		end
		if direction < 15 then -- special case 12 o'clock past 12 o'clock
			return 12
		end
	
		direction = direction + 15 -- add offset so we get all other times correct
		return math.floor(direction/30)
	
	end

	function dcsCommon.getGeneralDirection(direction) -- inspired by cws, improvements my own
		if not direction then return "unkown" end
		direction = math.fmod (direction, 360)
		while direction < 0 do 
			direction = direction + 360
		end
		while direction >= 360 do 
			direction = direction - 360
		end
		if direction < 45 then return "ahead" end	
		if direction < 135 then return "right" end
		if direction < 225 then return "behind" end
		if direction < 315 then return "left" end 
		return "ahead"
	end
	
	function dcsCommon.getNauticalDirection(direction) -- inspired by cws, improvements my own
		if not direction then return "unkown" end
		direction = math.fmod (direction, 360)
		while direction < 0 do 
			direction = direction + 360
		end
		while direction >= 360 do 
			direction = direction - 360
		end
		if direction < 45 then return "ahead" end	
		if direction < 135 then return "starboard" end
		if direction < 225 then return "aft" end
		if direction < 315 then return "port" end 
		return "ahead"
	end

	function dcsCommon.aspectByDirection(direction) -- inspired by cws, improvements my own
		if not direction then return "unkown" end
		direction = math.fmod (direction, 360)
		while direction < 0 do 
			direction = direction + 360
		end
		while direction >= 360 do 
			direction = direction - 360
		end
		
		if direction < 45 then return "hot" end	
		if direction < 135 then return "beam" end
		if direction < 225 then return "drag" end
		if direction < 315 then return "beam" end 
		return "hot"
	end
	
	function dcsCommon.whichSideOfMine(theUnit, target) -- returs two values: -1/1 = left/right and "left"/"right" 
		if not theUnit then return nil end 
		if not target then return nil end 
		local uDOF = theUnit:getPosition() -- returns p, x, y, z Vec3
		-- with x, y, z being the normalised vectors for right, up, forward 
		local heading = math.atan2(uDOF.x.z, uDOF.x.x) -- returns rads
		if heading < 0 then
			heading = heading + 2 * math.pi	-- put heading in range of 0 to 2*pi
		end
		-- heading now runs from 0 through 2Pi
		local A = uDOF.p
		local B = target:getPoint() 
		 
		-- now get bearing from theUnit to target  
		local dx = B.x - A.x
		local dz = B.z - A.z
		local bearing = math.atan2(dz, dx) -- in rads
		if bearing < 0 then
			bearing = bearing + 2 * math.pi	-- make bearing 0 to 2*pi
		end

		-- we now have bearing to B, and own heading. 
		-- subtract own heading from bearing to see at what 
		-- bearing target would be if we 'turned the world' so
		-- that theUnit is heading 0
		local dBearing = bearing - heading
		-- if result < 0 or > Pi (=180°), target is left from us
		if dBearing < 0 or dBearing > math.pi then return -1, "left" end
		return 1, "right"
		-- note: no separate case for straight in front or behind
	end
	
	-- Distance of point p to line defined by p1,p2 
	-- only on XZ map 
	function dcsCommon.distanceOfPointPToLineXZ(p, p1, p2)
		local x21 = p2.x - p1.x 
		local y10 = p1.z - p.z 
		local x10 = p1.x - p.x 
		local y21 = p2.z - p1.z 
		local numer = math.abs((x21*y10) - (x10 * y21))
		local denom = math.sqrt(x21 * x21 + y21 * y21)
		local dist = numer/denom 
		return dist 
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
		if not z then z = 0 end 
		
		--local y = 0
		if not innerRadius then innerRadius = 0 end		
		if innerRadius < 0 then innerRadius = 0 end
		
		local percent = dcsCommon.randomPercent() -- 1 / math.random(100)
		-- now lets get a random degree
		local degrees = dcsCommon.randomDegrees() -- math.random(360) * 3.14152 / 180 -- ok, it's actually radiants. 
		local r = (sourceRadius-innerRadius) * percent 
		x = x + (innerRadius + r) * math.cos(degrees)
		z = z + (innerRadius + r) * math.sin(degrees)
	
		local thePoint = {}
		thePoint.x = x
		thePoint.y = 0
		thePoint.z = z 
		
		return thePoint, degrees
	end

	function dcsCommon.newPointAtDegreesRange(p1, degrees, radius)
		local rads = degrees * 3.14152 / 180
		local p2 = dcsCommon.newPointAtAngleRange(p1, rads, radius)
		return p2 
	end
	
	function dcsCommon.newPointAtAngleRange(p1, angle, radius)
		local p2 = {}
		p2.x = p1.x + radius * math.cos(angle)
		p2.y = p1.y 
		p2.z = p1.z + radius * math.sin(angle)
		return p2 
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
			if Unit.isExist(theUnit) and theUnit:getLife() > 0 then 
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
		if type(aCoalition) == "string" then 
			aCoalition = aCoalition:lower()
			if aCoalition == "red" then return 2 end
			if aCoalition == "blue" then return 1 end
			return nil 
		end
		if aCoalition == 1 then return 2 end
		if aCoalition == 2 then return 1 end
		return nil
	end

	function dcsCommon.getACountryForCoalition(aCoalition)
		-- scan the table of countries and get the first country that is part of aCoalition
		-- this is useful if you want to create troops for a coalition but don't know the
		-- coalition's countries 
		-- we start with id=0 (Russia), go to id=85 (Slovenia), but skip id = 14
		local i = 0
		while i < dcsCommon.maxCountry do -- 86 do 
			if i ~= 14 then 
				if (coalition.getCountryCoalition(i) == aCoalition) then return i end
			end
			i = i + 1
		end
		
		return nil
	end
	
	function dcsCommon.getCountriesForCoalition(aCoalition)
		if not aCoalition then aCoalition = 0 end 
		local allCty = {}
		
		local i = 0
		while i < dcsCommon.maxCountry do 
			if i ~= 14 then -- there is no county 14
				if (coalition.getCountryCoalition(i) == aCoalition) then 
					table.insert(allCty, i) 
				end
			end
			i = i + 1
		end
		return allCty
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
		if not orig then return nil end 
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
	function dcsCommon.clone(orig, stripMeta)
		if not orig then return nil end 
		local orig_type = type(orig)
		local copy
		if orig_type == 'table' then
			copy = {}
			for orig_key, orig_value in next, orig, nil do
				copy[dcsCommon.clone(orig_key)] = dcsCommon.clone(orig_value)
			end
			if not stripMeta then 
				-- also connect meta data
				setmetatable(copy, dcsCommon.clone(getmetatable(orig)))
			else 
				-- strip all except string, and for strings use a fresh string 
				if type(copy) == "string" then 
					local tmp = ""
					tmp = tmp .. copy -- will get rid of any foreign metas for string 
					copy = tmp 
				end
			end
		else -- number, string, boolean, etc
			copy = orig
		end
		return copy
	end

	function dcsCommon.copyArray(inArray)
		if not inArray then return nil end 
		
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

	function dcsCommon.createOverheadAirdromeRoutePointData(aerodrome)
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
	function dcsCommon.createOverheadAirdromeRoutPintData(aerodrome) -- backwards-compat to typo 
		return dcsCommon.createOverheadAirdromeRoutePointData(aerodrome)
	end 
	

	function dcsCommon.createLandAtAerodromeRoutePointData(aerodrome)
		if not aerodrome then return nil end 
			
		local rp = {}			
		local p = aerodrome:getPoint()
		rp.airdromeId = aerodrome:getID() 
		rp.x = p.x
		rp.y = p.z
		rp.alt = land.getHeight({x=p.x, y=p.z}) --p.y 
		rp.action = "Landing"
		rp.type = "Land"
			
		rp.speed = 100; -- in m/s? If so, that's 360 km/h 
		rp.alt_type = "BARO"
		return rp
	end

	function dcsCommon.createSimpleRoutePointData(p, alt)
		if not alt then alt = 8000 end -- 24'000 feet 
		local rp = {}
		rp.x = p.x
		rp.y = p.z
		rp.alt = alt
		rp.action = "Turning Point"
		rp.type = "Turning Point"
			
		rp.speed = 133; -- in m/s? If so, that's 360 km/h 
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
				repeat 	-- get random point until mindistance to all is kept or emergencybreak
					thePoint = dcsCommon.randomPointInCircle(radius, innerRadius) -- returns x, 0, z
					-- check if too close to others
					for idx, rUnit in pairs(processedUnits) do -- get min dist to all positioned units
						--trigger.action.outText("rPnt: thePoint =  " .. dcsCommon.point2text(thePoint), 30)
						uPoint.x = rUnit.x
						uPoint.y = 0
						uPoint.z = rUnit.y 
						--trigger.action.outText("rPnt: uPoint =  " .. dcsCommon.point2text(uPoint), 30)
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
		if not minDist then minDist = 4 end -- meters
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
	
	function dcsCommon.rotatePointAroundOriginRad(inX, inY, angle) -- angle in degrees
		local c = math.cos(angle)
		local s = math.sin(angle)
		local px
		local py 
		px = inX * c - inY * s
		py = inX * s + inY * c
		return px, py		
	end
	
	function dcsCommon.rotatePointAroundOrigin(inX, inY, angle) -- angle in degrees
		local rads =  3.14152 / 180 -- convert to radiants. 
		angle = angle * rads -- turns into rads
		local px, py = dcsCommon.rotatePointAroundOriginRad(inX, inY, angle)
		return px, py		
	end
	
	function dcsCommon.rotatePointAroundPointRad(x, y, px, py, angle)
		x = x - px 
		y = y - py
		x, y = dcsCommon.rotatePointAroundOriginRad(x, y, angle)
		x = x + px 
		y = y + py 
		return x, y
	end

	function dcsCommon.rotatePointAroundPointDeg(x, y, px, py, degrees)
		x, y = dcsCommon.rotatePointAroundPointRad(x, y, px, py, degrees * 3.14152 / 180)
		return x, y
	end

	-- rotates a Vec3-base inPoly on XZ pane around inPoint on XZ pane
 	function dcsCommon.rotatePoly3AroundVec3Rad(inPoly, inPoint, rads)
		local outPoly = {}
		for idx, aVertex in pairs(inPoly) do 
			local x, z = dcsCommon.rotatePointAroundPointRad(aVertex.x, aVertex.z, inPoint.x, inPoint.z, rads)		
			local v3 = {x = x, y = aVertex.y, z = z}
			outPoly[idx] = v3
		end 
		return outPoly 
	end

	function dcsCommon.rotateUnitData(theUnit, degrees, cx, cz)
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

			-- may also want to increase heading by degrees
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

			-- may also want to increase heading by degrees
			theUnit.heading = theUnit.heading + rads 
			-- now kill psi if it existed before 
			-- theUnit.psi = nil
			-- better code: psi is always -heading. Nobody knows what psi is, though
			if theUnit.psi then 
				theUnit.psi = -theUnit.heading 
			end
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

function dcsCommon.synchGroupData(inGroupData) -- update group data block by 
-- comparing it to spawned group and update units by x, y, heding and isExist 
-- modifies inGroupData!
	if not inGroupData then return end 
	-- groupdata from game, NOT MX DATA!
	-- we synch the units and their coords 
	local livingUnits = {}
	for idx, unitData in pairs(inGroupData.units) do 
		local theUnit = Unit.getByName(unitData.name)
		if theUnit and theUnit:isExist() and theUnit:getLife()>1 then 
			-- update x and y and heading
			local pos = theUnit:getPoint()
			unitData.unitId = theUnit:getID()
			unitData.x = pos.x 
			unitData.y = pos.z -- !!!!
			unitData.heading = dcsCommon.getUnitHeading(gUnit)
			table.insert(livingUnits, unitData)
		end
	end
	inGroupData.units = livingUnits 
end

--
--
-- M I S C   M E T H O D S 
--
--

-- as arrayContainsString, except it includes wildcard matches if EITHER 
-- ends on "*"
	function dcsCommon.wildArrayContainsString(theArray, theString, caseSensitive) 
		if not theArray then return false end
		if not theString then return false end
		if not caseSensitive then caseSensitive = false end 
		if type(theArray) ~= "table" then 
			trigger.action.outText("***arrayContainsString: theArray is not type table but <" .. type(theArray) .. ">", 30)
		end
		if not caseSensitive then theString = string.upper(theString) end 
		
		--trigger.action.outText("wildACS: theString = <" .. theString .. ">, theArray contains <" .. #theArray .. "> elements", 30)
		local wildIn = dcsCommon.stringEndsWith(theString, "*")
		if wildIn then dcsCommon.removeEnding(theString, "*") end 
		for idx, theElement in pairs(theArray) do -- i = 1, #theArray do 
			--local theElement = theArray[i]
			--trigger.action.outText("test e <" .. theElement .. "> against s <" .. theString .. ">", 30)
			if not caseSensitive then theElement = string.upper(theElement) end 
			local wildEle = dcsCommon.stringEndsWith(theElement, "*")
			if wildEle then theElement = dcsCommon.removeEnding(theElement, "*") end 
			--trigger.action.outText("matching s=<" .. theString .. "> with e=<" .. theElement .. ">", 30)
			if wildEle and wildIn then 
				-- both end on wildcards, partial match for both
				if dcsCommon.stringStartsWith(theElement, theString) then return true end 
				if dcsCommon.stringStartsWith(theString, theElement) then return true end 
				--trigger.action.outText("match e* with s* failed.", 30)
			elseif wildEle then 
				-- Element is a wildcard, partial match 
				if dcsCommon.stringStartsWith(theString, theElement) then return true end
				--trigger.action.outText("startswith - match e* <" .. theElement .. "> with s <" .. theString .. "> failed.", 30)
			elseif wildIn then
				-- theString is a wildcard. partial match 
				if dcsCommon.stringStartsWith(theElement, theString) then return true end
				--trigger.action.outText("match e with s* failed.", 30)
			else
				-- standard: no wildcards, full match
				if theElement == theString then return true end 
				--trigger.action.outText("match e with s (straight) failed.", 30)
			end
			
		end
		return false 
	end


	function dcsCommon.arrayContainsString(theArray, theString) 
		if not theArray then return false end
		if not theString then return false end
		if type(theArray) ~= "table" then 
			trigger.action.outText("***arrayContainsString: theArray is not type table but <" .. type(theArray) .. ">", 30)
		end
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
	
	function dcsCommon.string2Array(inString, deli, uCase)
		if not inString then return {} end 
		if not deli then return {} end 
		if not uCase then uCase = false end
		if uCase then inString = string.upper(inString) end
		inString = dcsCommon.trim(inString)
		if dcsCommon.containsString(inString, deli) then 
			local a = dcsCommon.splitString(inString, deli)
			a = dcsCommon.trimArray(a)
			return a 
		else 
			return {inString}
		end
	end
	
	function dcsCommon.array2string(inArray, deli)
		if not deli then deli = ", " end
		if type(inArray) ~= "table" then return "<err in array2string: not an array>" end
		local s = ""
		local count = 0
		for idx, ele in pairs(inArray) do
			if count > 0 then s = s .. deli .. " " end
			s = s .. ele
			count = count + 1
		end
		return s
	end
	
	function dcsCommon.stripLF(theString)
		return theString:gsub("[\r\n]", "")
	end
	
	function dcsCommon.removeBlanks(theString)
		return theString:gsub("%s", "")
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
	
	function dcsCommon.stringStartsWith(theString, thePrefix, caseInsensitive)
		if not theString then return false end 
		if not thePrefix then return false end 
		if not caseInsensitive then caseInsensitive = false end 
		
		if caseInsensitive then 
			theString = string.upper(theString)
			thePrefix = string.upper(theString)
		end
		-- superseded: string.find (s, pattern [, init [, plain]]) solves the problem  
		local i, j = string.find(theString, thePrefix, 1, true)
		return (i == 1)
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
		return string.find(inString, what, 1, true) -- 1, true means start at 1, plaintext
	end
	
	function dcsCommon.bool2Text(theBool) 
		if not theBool then theBool = false end 
		if theBool then return "true" end 
		return "false"
	end
	
	function dcsCommon.bool2YesNo(theBool)
		if not theBool then 
			theBool = false
			return "NIL"
		end 
		if theBool then return "yes" end 
		return "no"
	end
	
	function dcsCommon.bool2Num(theBool)
		if not theBool then theBool = false end 
		if theBool then return 1 end 
		return 0
	end

	function dcsCommon.point2text(p) 
		if not p then return "<!NIL!>" end 
		local t = "[x="
		if p.x then t = t .. p.x .. ", " else t = t .. "<nil>, " end 
		if p.y then t = t .. "y=" .. p.y .. ", " else t = t .. "y=<nil>, " end 
		if p.z then t = t .. "z=" .. p.z .. "]" else t = t .. "z=<nil>]" end 
		return t 
	end

	function dcsCommon.string2GroupCat(inString)

		if not inString then return 2 end -- default ground 
		inString = inString:lower()
		inString = dcsCommon.trim(inString)

		local catNum = tonumber(inString)
		if catNum then 
			if catNum < 0 then catNum = 0 end 
			if catNum > 4 then catNum = 4 end 
			return catNum 
		end
	
		catNum = 2 -- ground default 
		if dcsCommon.stringStartsWith(inString, "grou") then catNum = 2 end 
		if dcsCommon.stringStartsWith(inString, "air") then catNum = 0 end
		if dcsCommon.stringStartsWith(inString, "hel") then catNum = 1 end
		if dcsCommon.stringStartsWith(inString, "shi") then catNum = 3 end
		if dcsCommon.stringStartsWith(inString, "trai") then catNum = 4 end

		return catNum
	end

	function dcsCommon.string2ObjectCat(inString)

		if not inString then return 3 end -- default static 
		inString = inString:lower()
		inString = dcsCommon.trim(inString)

		local catNum = tonumber(inString)
		if catNum then 
			if catNum < 0 then catNum = 0 end 
			if catNum > 6 then catNum = 6 end 
			return catNum 
		end
	
		catNum = 3 -- static default 
		if dcsCommon.stringStartsWith(inString, "uni") then catNum = 1 end 
		if dcsCommon.stringStartsWith(inString, "wea") then catNum = 2 end
		if dcsCommon.stringStartsWith(inString, "bas") then catNum = 4 end
		if dcsCommon.stringStartsWith(inString, "sce") then catNum = 5 end
		if dcsCommon.stringStartsWith(inString, "car") then catNum = 6 end

		return catNum
	end

	function dcsCommon.menu2text(inMenu)
		if not inMenu then return "<nil>" end
		local s = ""
		for n, v in pairs(inMenu) do 
			if type(v) == "string" then 
				if s == "" then s = "[" .. v .. "]"  else 
					s = s .. " | [" .. type(v) .. "]" end
			else 
				if s == "" then s = "[<" .. type(v) .. ">]"  else
					s = s .. " | [<" .. type(v) .. ">]" end
			end
		end
		return s
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
			trigger.action.outText("=== dcsCommon vardump end", 30)
			env.info("=== dcsCommon vardump end")
		end
	end
	
	function dcsCommon.dumpVar2Str(key, value, prefix, inrecursion)
		-- dumps to screen, not string 
		if not inrecursion then 
			-- output a marker to find in the log / screen
			trigger.action.outText("*** dcsCommon vardump START",30)
		end
		if not value then value = "nil" end
		if not prefix then prefix = "" end
		prefix = " " .. prefix
		if getmetatable(value) then 
			if type(value) == "string" then 
			else 
				trigger.action.outText(prefix .. key (" .. type(value) .. ") .. " HAS META", 30)
			end
		end
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
			trigger.action.outText("=== dcsCommon vardump end", 30)
			--env.info("=== dcsCommon vardump end")
		end
	end
		
	function dcsCommon.numberUUID()
		dcsCommon.simpleUUID = dcsCommon.simpleUUID + 1
		return dcsCommon.simpleUUID
	end

	function dcsCommon.uuid(prefix)
		--dcsCommon.uuIdent = dcsCommon.uuIdent + 1
		if not prefix then prefix = dcsCommon.uuidStr end
		return prefix .. "-" .. dcsCommon.numberUUID() -- dcsCommon.uuIdent
	end
	
	function dcsCommon.event2text(id) 
		if not id then return "error" end
		if id == 0 then return "invalid" end
		-- translate the event id to text
		local events = {"shot", "hit", "takeoff", "land",
						"crash", "eject", "refuel", "dead", -- 8
						"pilot dead", "base captured", "mission start", "mission end", -- 12
						"took control", "refuel stop", "birth", "human failure", -- 16 
						"det. failure", "engine start", "engine stop", "player enter unit", -- 20
						"player leave unit", "player comment", "start shoot", "end shoot", -- 24
						"mark add", "mark changed", "mark removed", "kill", -- 28 
						"score", "unit lost", "land after eject", "Paratrooper land", -- 32 
						"chair discard after eject", "weapon add", "trigger zone", "landing quality mark", -- 36
						"BDA", "AI Abort Mission", "DayNight", "Flight Time", -- 40
						"Pilot Suicide", "player cap airfield", "emergency landing", "unit create task", -- 44
						"unit delete task", "Simulation start", "weapon rearm", "weapon drop", -- 48
						"unit task timeout", "unit task stage", 
						"max"}
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
	
	function dcsCommon.flareColor2Text(flareColor)
		if (flareColor == 0) then return "Green" end
		if (flareColor == 1) then return "Red" end
		if (flareColor == 2) then return "White" end
		if (flareColor == 3) then return "Yellow" end
		if (flareColor < 0) then return "Random" end 
		return ("unknown: " .. flareColor)
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

	function dcsCommon.flareColor2Num(flareColor)
		if not flareColor then flareColor = "green" end 
		if type(flareColor) ~= "string" then return 0 end 
		flareColor = flareColor:lower()
		if (flareColor == "green") then return 0 end 
		if (flareColor == "red") then return 1 end 
		if (flareColor == "white") then return 2 end 
		if (flareColor == "yellow") then return 3 end 
		if (flareColor == "random") then return -1 end 
		if (flareColor == "rnd") then return -1 end 
		return 0
	end

	
	function dcsCommon.markPointWithSmoke(p, smokeColor)
		if not smokeColor then smokeColor = 0 end 
		local x = p.x 
		local z = p.z -- do NOT change the point directly
		-- height-correct
		local y = land.getHeight({x = x, y = z})
		local newPoint= {x = x, y = y + 2, z = z}
		trigger.action.smoke(newPoint, smokeColor)
	end

-- based on buzzer1977's idea, channel is number, eg in 74X, channel is 74, mode is "X"
	function dcsCommon.tacan2freq(channel, mode)	
		if not mode then mode = "X" end 
		if not channel then channel = 1 end 
		if type(mode) ~= "string" then mode = "X" end 
		mode = mode:upper()
		local offset = 1000000 * channel
		if channel < 64 then 
			if mode == "Y" then
				return 1087000000 + offset
			end
			return 961000000 + offset -- mode x
		end
	
		if mode == "Y" then
			return 961000000 + offset
		end
		return 1087000000 + offset -- mode x
	end
	
	function dcsCommon.processHMS(msg, delta)
		local rS = math.floor(delta)
		local remainS = tostring(rS)
		local rM = math.floor(delta/60)
		local remainM = tostring(rM)
		local rH = math.floor(delta/3600)
		local remainH = tostring(rH)
		local hmsH = remainH 
		if rH < 10 then hmsH = "0" .. hmsH end 
		
		local hmsCount = delta - (rH * 3600) -- mins left 
		local mins = math.floor (hmsCount / 60)
		local hmsM = tostring(mins)
		if mins < 10 then hmsM = "0" .. hmsM end 
		
		hmsCount = hmsCount - (mins * 60) 
		local secs = math.floor(hmsCount)
		local hmsS = tostring(secs)
		if secs < 10 then hmsS = "0" .. hmsS end 
		
		msg = string.gsub(msg, "<s>", remainS)
		msg = string.gsub(msg, "<m>", remainM)
		msg = string.gsub(msg, "<h>", remainH)
		
		msg = string.gsub(msg, "<:s>", hmsS)
		msg = string.gsub(msg, "<:m>", hmsM)
		msg = string.gsub(msg, "<:h>", hmsH)
		
		return msg 
	end
	
	function dcsCommon.nowString()
		local absSecs = timer.getAbsTime()-- + env.mission.start_time
		while absSecs > 86400 do 
			absSecs = absSecs - 86400 -- subtract out all days 
		end
		return dcsCommon.processHMS("<:h>:<:m>:<:s>", absSecs)
	end
	
	function dcsCommon.str2num(inVal, default) 
		if not default then default = 0 end
		if not inVal then return default end
		if type(inVal) == "number" then return inVal end 				
		local num = nil
		if type(inVal) == "string" then num = tonumber(inVal) end
		if not num then return default end
		return num
	end
	
	function dcsCommon.stringRemainsStartingWith(theString, startingWith)
		-- find the first position where startingWith starts 
		local pos = theString:find(startingWith)
		if not pos then return theString end 
		-- now return the entire remainder of the string from pos 
		local nums = theString:len() - pos + 1
		return theString:sub(-nums)
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
	if a.z and b.z then 
		r.z = a.z + b.z 
	end 
	return r 
end

function dcsCommon.vSub(a, b) 
	local r = {}
	if not a then a = {x = 0, y = 0, z = 0} end
	if not b then b = {x = 0, y = 0, z = 0} end
	r.x = a.x - b.x 
	r.y = a.y - b.y 
	if a.z and b.z then 
		r.z = a.z - b.z 
	end 
	return r 
end

function dcsCommon.vMultScalar(a, f) 
	local r = {}
	if not a then a = {x = 0, y = 0, z = 0} end
	if not f then f = 0 end
	r.x = a.x * f 
	r.y = a.y * f 
	if a.z then 
		r.z = a.z * f
    end		
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

function dcsCommon.isTroopCarrierType(theType, carriers)
	if not theType then return false end 
	if not carriers then carriers = dcsCommon.troopCarriers 
	end 
	-- remember that arrayContainsString is case INsensitive by default 
	if dcsCommon.wildArrayContainsString(carriers, theType) then 
		-- may add additional tests before returning true
		return true
	end
	
	-- see if user wanted 'any' or 'all' supported
	if dcsCommon.arrayContainsString(carriers, "any") then 
		return true 
	end 
	
	if dcsCommon.arrayContainsString(carriers, "all") then 
		return true 
	end 
	
	return false
end

function dcsCommon.isTroopCarrier(theUnit, carriers)
	-- return true if conf can carry troups
	if not theUnit then return false end 
	local uType = theUnit:getTypeName()
	return dcsCommon.isTroopCarrierType(uType, carriers) 
end


function dcsCommon.getAllExistingPlayerUnitsRaw()
	local apu = {}
	for idx, theSide in pairs(dcsCommon.coalitionSides) do
		local thePlayers = coalition.getPlayers(theSide) 
		for idy, theUnit in pairs (thePlayers) do 
			if theUnit and theUnit:isExist() then 
				table.insert(apu, theUnit)
			end
		end
	end
	return apu 
end

function dcsCommon.getUnitAlt(theUnit)
	if not theUnit then return 0 end
	if not Unit.isExist(theUnit) then return 0 end -- safer 
	local p = theUnit:getPoint()
	return p.y 
end

function dcsCommon.getUnitAGL(theUnit)
	if not theUnit then return 0 end
	if not Unit.isExist(theUnit) then return 0 end -- safe fix
	local p = theUnit:getPoint()
	local alt = p.y 
	local loc = {x = p.x, y = p.z}
	local landElev = land.getHeight(loc)
	return alt - landElev
end 

function dcsCommon.getUnitSpeed(theUnit)
	if not theUnit then return 0 end
	if not Unit.isExist(theUnit) then return 0 end 
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
	-- make sure positive only, add 360 degrees
	if heading < 0 then
		heading = heading + 2 * math.pi	-- put heading in range of 0 to 2*pi
	end
	return heading 
end

function dcsCommon.getUnitHeadingDegrees(theUnit)
	local heading = dcsCommon.getUnitHeading(theUnit)
	return heading * 57.2958 -- 180 / math.pi 
end

function dcsCommon.typeIsInfantry(theType)
	local isInfantry =  
				dcsCommon.containsString(theType, "infantry", false) or 
				dcsCommon.containsString(theType, "paratrooper", false) or
				dcsCommon.containsString(theType, "stinger", false) or
				dcsCommon.containsString(theType, "manpad", false) or
				dcsCommon.containsString(theType, "soldier", false) or 
				dcsCommon.containsString(theType, "SA-18 Igla", false)
	return isInfantry
end

function dcsCommon.unitIsInfantry(theUnit)
	if not theUnit then return false end 
	if not theUnit:isExist() then return end
	local theType = theUnit:getTypeName()
--[[--
	local isInfantry =  
				dcsCommon.containsString(theType, "infantry", false) or 
				dcsCommon.containsString(theType, "paratrooper", false) or
				dcsCommon.containsString(theType, "stinger", false) or
				dcsCommon.containsString(theType, "manpad", false) or
				dcsCommon.containsString(theType, "soldier", false) or 
				dcsCommon.containsString(theType, "SA-18 Igla", false)
	return isInfantry
--]]--
	return dcsCommon.typeIsInfantry(theType)
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

function dcsCommon.coalition2Text(coa)
	if not coa then return "!nil!" end 
	if coa == 0 then return "NEUTRAL" end 
	if coa == 1 then return "RED" end 
	if coa == 2 then return "BLUE" end 
	return "?UNKNOWN?"
end

function dcsCommon.latLon2Text(lat, lon)
	-- inspired by mist, thanks Grimes!
	-- returns two strings: lat and lon 
	
	-- determine hemispheres by sign
	local latHemi, lonHemi
	if lat > 0 then latHemi = 'N' else latHemi = 'S' end
	if lon > 0 then lonHemi = 'E' else lonHemi = 'W' end

	-- remove sign since we have hemi
	lat = math.abs(lat)
	lon = math.abs(lon)

	-- calc deg / mins 
	local latDeg = math.floor(lat)
	local latMin = (lat - latDeg) * 60
	local lonDeg = math.floor(lon)
	local lonMin = (lon - lonDeg) * 60

	-- calc seconds 
	local rawLatMin = latMin
	latMin = math.floor(latMin)
	local latSec = (rawLatMin - latMin) * 60
	local rawLonMin = lonMin
	lonMin = math.floor(lonMin)
	local lonSec = (rawLonMin - lonMin) * 60

	-- correct for rounding errors 
	if latSec >= 60 then
		latSec = latSec - 60
		latMin = latMin + 1
	end
	if lonSec >= 60 then
		lonSec = lonSec - 60
		lonMin = lonMin + 1
	end

	-- prepare string output 
	local secFrmtStr = '%06.3f'
	local lat = string.format('%02d', latDeg) .. '°' .. string.format('%02d', latMin) .. "'" .. string.format(secFrmtStr, latSec) .. '"' .. latHemi
	local lon = string.format('%02d', lonDeg) .. '°' .. string.format('%02d', lonMin) .. "'" .. string.format(secFrmtStr, lonSec) .. '"' .. lonHemi
	return lat, lon  
end

-- get mission name. If mission file name without ".miz"
function dcsCommon.getMissionName()
	local mn = net.dostring_in("gui", "return DCS.getMissionName()")
	return mn
end

function dcsCommon.numberArrayFromString(inString, default) -- moved from cfxZones
	if not default then default = 0 end 
	if string.len(inString) < 1 then 
		trigger.action.outText("+++dcsCommon: empty numbers", 30)
		return {default, } 
	end
	
	local flags = {}
	local rawElements = dcsCommon.splitString(inString, ",")
	-- go over all elements 
	for idx, anElement in pairs(rawElements) do 
		anElement = dcsCommon.trim(anElement)
		if dcsCommon.stringStartsWithDigit(anElement) and dcsCommon.containsString(anElement, "-") then 
			-- interpret this as a range
			local theRange = dcsCommon.splitString(anElement, "-")
			local lowerBound = theRange[1]
			lowerBound = tonumber(lowerBound)
			local upperBound = theRange[2]
			upperBound = tonumber(upperBound)
			if lowerBound and upperBound then
				-- swap if wrong order
				if lowerBound > upperBound then 
					local temp = upperBound
					upperBound = lowerBound
					lowerBound = temp 
				end
				-- now add add numbers to flags
				for f=lowerBound, upperBound do 
					table.insert(flags, tostring(f))
				end
			else
				-- bounds illegal
				trigger.action.outText("+++dcsCommon: ignored range <" .. anElement .. "> (range)", 30)
			end
		else
			-- single number
			f = dcsCommon.trim(anElement)
			f = tonumber(f)
			if f then 
				table.insert(flags, f)
			end
		end
	end
	if #flags < 1 then flags = {default, } end 
	return flags
end 

function dcsCommon.flagArrayFromString(inString, verbose)
	if not verbose then verbose = false end 
	
	if verbose then 
		trigger.action.outText("+++flagArray: processing <" .. inString .. ">", 30)
	end 

	if string.len(inString) < 1 then 
		trigger.action.outText("+++flagArray: empty flags", 30)
		return {} 
	end
	
	
	local flags = {}
	local rawElements = dcsCommon.splitString(inString, ",")
	-- go over all elements 
	for idx, anElement in pairs(rawElements) do 
		anElement = dcsCommon.trim(anElement)
		if dcsCommon.stringStartsWithDigit(anElement) and  dcsCommon.containsString(anElement, "-") then 
			-- interpret this as a range
			local theRange = dcsCommon.splitString(anElement, "-")
			local lowerBound = theRange[1]
			lowerBound = tonumber(lowerBound)
			local upperBound = theRange[2]
			upperBound = tonumber(upperBound)
			if lowerBound and upperBound then
				-- swap if wrong order
				if lowerBound > upperBound then 
					local temp = upperBound
					upperBound = lowerBound
					lowerBound = temp 
				end
				-- now add add numbers to flags
				for f=lowerBound, upperBound do 
					table.insert(flags, f)

				end
			else
				-- bounds illegal
				trigger.action.outText("+++flagArray: ignored range <" .. anElement .. "> (range)", 30)
			end
		else
			-- single number
			local f = dcsCommon.trim(anElement) -- DML flag upgrade: accept strings tonumber(anElement)
			if f then 
				table.insert(flags, f)

			else 
				trigger.action.outText("+++flagArray: ignored element <" .. anElement .. "> (single)", 30)
			end
		end
	end
	if verbose then 
		trigger.action.outText("+++flagArray: <" .. #flags .. "> flags total", 30)
	end 
	return flags
end

function dcsCommon.rangeArrayFromString(inString, verbose)
	if not verbose then verbose = false end 
	
	if verbose then 
		trigger.action.outText("+++rangeArray: processing <" .. inString .. ">", 30)
	end 

	if string.len(inString) < 1 then 
		trigger.action.outText("+++rangeArray: empty ranges", 30)
		return {} 
	end
	
	local ranges = {}
	local rawElements = dcsCommon.splitString(inString, ",")
	-- go over all elements 
	for idx, anElement in pairs(rawElements) do 
		anElement = dcsCommon.trim(anElement)
		local outRange = {}
		if dcsCommon.stringStartsWithDigit(anElement) and  dcsCommon.containsString(anElement, "-") then 
			-- interpret this as a range
			local theRange = dcsCommon.splitString(anElement, "-")
			local lowerBound = theRange[1]
			lowerBound = tonumber(lowerBound)
			local upperBound = theRange[2]
			upperBound = tonumber(upperBound)
			if lowerBound and upperBound then
				-- swap if wrong order
				if lowerBound > upperBound then 
					local temp = upperBound
					upperBound = lowerBound
					lowerBound = temp 
				end
				-- now add to ranges
				outRange[1] = lowerBound
				outRange[2] = upperBound
				table.insert(ranges, outRange)
				if verbose then 
					trigger.action.outText("+++rangeArray: new range <" .. lowerBound .. "> to <" .. upperBound .. ">", 30)
				end
			else
				-- bounds illegal
				trigger.action.outText("+++rangeArray: ignored range <" .. anElement .. "> (range)", 30)
			end
		else
			-- single number
			local f = dcsCommon.trim(anElement) 
			f = tonumber(f)
			if f then 
				outRange[1] = f
				outRange[2] = f
				table.insert(ranges, outRange)
				if verbose then 
					trigger.action.outText("+++rangeArray: new (single-val) range <" .. f .. "> to <" .. f .. ">", 30)
				end
			else 
				trigger.action.outText("+++rangeArray: ignored element <" .. anElement .. "> (single)", 30)
			end
		end
	end
	if verbose then 
		trigger.action.outText("+++rangeArray: <" .. #ranges .. "> ranges total", 30)
	end 
	return ranges
end

function dcsCommon.incFlag(flagName)
	local v = trigger.misc.getUserFlag(flagName)
	trigger.action.setUserFlag(flagName, v + 1)
end

function dcsCommon.decFlag(flagName)
	local v = trigger.misc.getUserFlag(flagName)
	trigger.action.setUserFlag(flagName, v - 1)
end

function dcsCommon.objectHandler(theObject, theCollector)
	table.insert(theCollector, theObject)
	return true 
end

function dcsCommon.getObjectsForCatAtPointWithRadius(aCat, thePoint, theRadius)
	if not aCat then aCat = Object.Category.UNIT end 
	local p = {x=thePoint.x, y=thePoint.y, z=thePoint.z}
	local collector = {}
	
	-- now build the search argument 
	local args = {
			id = world.VolumeType.SPHERE,
			params = {
				point = p,
				radius = theRadius
			}
		}
	
	-- now call search
	world.searchObjects(aCat, args, dcsCommon.objectHandler, collector)
	return collector
end

function dcsCommon.getSceneryObjectsInZone(theZone) -- DCS ZONE!!! 
	local aCat = 5 -- scenery
	-- WARNING: WE ARE USING DCS ZONES, NOT CFX!!!
	local p = {x=theZone.x, y=0, z=theZone.y}
	local lp = {x = p.x, y = p.z}
	p.y = land.getHeight(lp)
	local collector = {}
	
	-- now build the search argument 
	local args = {
			id = world.VolumeType.SPHERE,
			params = {
				point = p,
				radius = theZone.radius
			}
		}
	
	-- now call search
	world.searchObjects(aCat, args, dcsCommon.objectHandler, collector)
	return collector
end

function dcsCommon.getSceneryObjectInZoneByName(theName, theZone) -- DCS ZONE!!!
	local allObs = dcsCommon.getSceneryObjectsInZone(theZone)
	for idx, anObject in pairs(allObs) do 
		if tostring(anObject:getName()) == theName then return anObject end 
	end
	return nil 
end

--
-- bitwise operators
--
function dcsCommon.bitAND32(a, b)
	if not a then a = 0 end 
	if not b then b = 0 end 
	local z = 0
	local e = 1
	for i = 0, 31 do 
		local a1 = a % 2 -- 0 or 1
		local b1 = b % 2 -- 0 or 1
		if a1 == 1 and b1 == 1 then 
			a = a - 1 -- remove bit 
			b = b - 1 
			z = z + e
		else
			if a1 == 1 then a = a - 1 end -- remove bit 
			if b1 == 1 then b = b - 1 end 
		end
		a = a / 2 -- shift right
		b = b / 2		
		e = e * 2 -- raise e by 1 
	end
	return z
end

function dcsCommon.num2bin(a)
	if not a then a = 0 end 
	local z = ""
	for i = 0, 31 do 
		local a1 = a % 2 -- 0 or 1
		if a1 == 1 then 
			a = a - 1 -- remove bit 
			z = "1"..z
		else
			z = "0"..z
		end
		a = a / 2 -- shift right
	end
	return z
end

function dcsCommon.LSR(a, num)
	if not a then a = 0 end 
	if not num then num = 16 end 
	for i = 1, num do 
		local a1 = a % 2 -- 0 or 1
		if a1 == 1 then 
			a = a - 1 -- remove bit 
		end
		a = a / 2 -- shift right
	end
	return a
end

--
-- string wildcards 
--
function dcsCommon.processStringWildcards(inMsg)
	-- Replace STATIC bits of message like CR and zone name 
	if not inMsg then return "<nil inMsg>" end
	local formerType = type(inMsg)
	if formerType ~= "string" then inMsg = tostring(inMsg) end  
	if not inMsg then inMsg = "<inMsg is incompatible type " .. formerType .. ">" end 
	local outMsg = ""
	-- replace line feeds 
	outMsg = inMsg:gsub("<n>", "\n")

	return outMsg 
end

--
-- phonetic alphabet 
--
dcsCommon.alphabet = {
    a = "alpha",
    b = "bravo",
    c = "charlie",
    d = "delta",
    e = "echo",
    f = "foxtrot",
    g = "golf",
    h = "hotel",
    i = "india",
    j = "juliet",
    k = "kilo",
    l = "lima",
    m = "mike",
    n = "november",
    o = "oscar",
    p = "papa",
    q = "quebec",
    r = "romeo",
    s = "sierra",
    t = "tango",
    u = "uniform",
    v = "victor",
    w = "whiskey",
    x = "x-ray",
    y = "yankee",
    z = "zulu",
["0"] = "zero",
["1"] = "wun",
["2"] = "too",
["3"] = "tree",
["4"] = "fower",
["5"] = "fife" ,
["6"] = "six",
["7"] = "seven",
["8"] = "att",
["9"] = "niner",
[" "] = "break",
}

function dcsCommon.letter(inChar)
	local theChar = ""
	if type(inChar == "string") then 
		if #inChar < 1 then return "#ERROR0#" end
		inChar = string.lower(inChar)
		theChar = string.sub(inChar, 1, 1)
	elseif type(inChar == "number") then 
		if inChar > 255 then return "#ERROR>#" end 
		if inChar < 0 then return "#ERROR<#" end 
		theChar = char(inChar)
	else 
		return "#ERRORT#"
	end
--	trigger.action.outText("doing <" .. theChar .. ">", 30)
	local a = dcsCommon.alphabet[theChar]
	if a == nil then a = "#ERROR?#" end 
	return a 
end

function dcsCommon.spellString(inString)
	local res = ""
	local first = true 
	for i = 1, #inString do
		local c = inString:sub(i,i)
		if first then 
			res = dcsCommon.letter(c)
			first = false 
		else 
			res = res .. " " .. dcsCommon.letter(c)
		end
	end
	return res 
end

dcsCommon.letters = {"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", 
"O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", }
function dcsCommon.randomLetter(lowercase)
	local theLetter = dcsCommon.pickRandom(dcsCommon.letters)
	if lowercase then theLetter = string.lower(theLetter) end 
	return theLetter
end

--
-- RGBA from hex
--
function dcsCommon.hexString2RGBA(inString) 
	-- enter with "#FF0020" (RGB) or "#FF00AB99" RGBA
	-- check if it starts with #
	if not inString then return nil end 
	if #inString ~= 7 and #inString ~=9 then return nil end 
	if inString:sub(1, 1) ~= "#" then return nil end 
	inString = inString:lower()
	local red = tonumber("0x" .. inString:sub(2,3)) 
	if not red then red = 0 end 
	local green = tonumber("0x" .. inString:sub(4,5))
	if not green then green = 0 end 
	local blue = tonumber("0x" .. inString:sub(6,7))
	if not blue then blue = 0 end 
	local alpha = 255 
	if #inString == 9 then 
		alpha = tonumber("0x" .. inString:sub(8,9))
	end
	if not alpha then alpha = 0 end
	return {red/255, green/255, blue/255, alpha/255}
end


--
-- Player handling 
--
function dcsCommon.playerName2Coalition(playerName)
	if not playerName then return 0 end 
	local factions = {1,2}
	for idx, theFaction in pairs(factions) do 
		local players = coalition.getPlayers(theFaction)
		for idy, theUnit in pairs(players) do 
			local upName = theUnit:getPlayerName()
			if upName == playerName then return theFaction end
		end
	end
	return 0
end

function dcsCommon.isPlayerUnit(theUnit)
	-- new patch. simply check if getPlayerName returns something
	if not theUnit then return false end 
	if not Unit.isExist(theUnit) then return end 
	if not theUnit.getPlayerName then return false end -- map/static object 
	local pName = theUnit:getPlayerName()
	if pName then return true end 
	return false 
end

function dcsCommon.getPlayerUnit(name)
	for coa = 1, 2 do 
		local players = coalition.getPlayers(coa)
		for idx, theUnit in pairs(players) do 
			if theUnit:getPlayerName() == name then return theUnit end
		end
	end
	return nil 
end

--
-- theater and theater-related stuff 
--
function dcsCommon.getMapName()
	return env.mission.theatre
end

dcsCommon.magDecls = {Caucasus = 6.5,
					  MarianaIslands = 1,
					  Nevada = 12,
					  PersianGulf = 2,
					  Syria = 4,
					  Normandy = -12 -- 1944, -1 in 2016 
					  -- SinaiMap still missing 
					  -- Falklands still missing, big differences 
					  }
					  
function dcsCommon.getMagDeclForPoint(point) 
	-- WARNING! Approximations only, map-wide, not adjusted for year nor location!
	-- serves as a stub for the day when DCS provides correct info 
	local map = dcsCommon.getMapName()
	local decl = dcsCommon.magDecls[map]
	if not decl then 
		trigger.action.outText("+++dcsC: unknown map <" .. map .. ">, using dclenation 0", 30)
		decl = 0
	end
	return decl 
end 

--
-- iterators
--
-- iteratePlayers - call callback for all player units
-- callback is of signature callback(playerUnit)
--

function dcsCommon.iteratePlayers(callBack)
	local factions = {0, 1, 2}
	for idx, theFaction in pairs(factions) do 
		local players = coalition.getPlayers(theFaction)
		for idy, theUnit in pairs(players) do 
			callBack(theUnit)
		end
	end
end


--
-- MISC POINT CREATION
--
function dcsCommon.createPoint(x, y, z)
	local newPoint = {}
	newPoint.x = x
	newPoint.y = y
	newPoint.z = z -- works even if Z == nil
	return newPoint
end

function dcsCommon.copyPoint(inPoint) 
	local newPoint = {}
	newPoint.x = inPoint.x
	newPoint.y = inPoint.y
	-- handle xz only 
	if inPoint.z then 
		newPoint.z = inPoint.z 
	else 
		newPoint.z = inPoint.y 
	end
	return newPoint	
end

--
-- SEMAPHORES
--
dcsCommon.semaphores = {}

-- replacement for trigger.misc.getUserFlag
function dcsCommon.getUserFlag(flagName)
	if dcsCommon.semaphores[flagName] then 
		return dcsCommon.semaphores[flagName]
	end
	
	return trigger.misc.getUserFlag(flagName)
end

-- replacement for trigger.action.setUserFlag 
function dcsCommon.setUserFlag(flagName, theValue)
	-- not yet connected: semaphores
	
	-- forget semaphore content if new value is old-school 
	if type(theValue) == "number" then 
		dcsCommon.semaphores[theValue] = nil --return to old-school 
	end
	trigger.action.setUserFlag(flagName, theValue)
end

--
--
-- INIT
--
--
	-- init any variables, tables etc that the lib requires internally
	function dcsCommon.init()
		cbID = 0
		-- create ID tables
		dcsCommon.collectMissionIDs()
		
		--dcsCommon.uuIdent = 0
		if (dcsCommon.verbose) or true then
		  trigger.action.outText("dcsCommon v" .. dcsCommon.version .. " loaded", 10)
		end
	end

	
-- do init. 
dcsCommon.init()

