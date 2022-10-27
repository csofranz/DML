cfxZones = {}
cfxZones.version = "2.9.0"

-- cf/x zone management module
-- reads dcs zones and makes them accessible and mutable 
-- by scripting.
--
-- Copyright (c) 2021, 2022 by Christian Franz and cf/x AG
--

--[[-- VERSION HISTORY
 - 2.2.4 - getCoalitionFromZoneProperty
         - getStringFromZoneProperty
 - 2.2.5 - createGroundUnitsInZoneForCoalition corrected coalition --> country 
 - 2.2.6 - getVectorFromZoneProperty(theZone, theProperty, defaultVal)
 - 2.2.7 - allow 'yes' as 'true' for boolean attribute 
 - 2.2.8 - getBoolFromZoneProperty supports default 
		 - cfxZones.hasProperty
 - 2.3.0 - property names are case insensitive 
 - 2.3.1 - getCoalitionFromZoneProperty allows 0, 1, 2 also
 - 2.4.0 - all zones look for owner attribute, and set it to 0 (neutral) if not present 
 - 2.4.1 - getBoolFromZoneProperty upgraded by expected bool 
         - markZoneWithSmoke raised by 3 meters
 - 2.4.2 - getClosestZone also returns delta 
 - 2.4.3 - getCoalitionFromZoneProperty() accepts 'all' as neutral 
		   createUniqueZoneName()
		   getStringFromZoneProperty returns default if property value = ""
		   corrected bug in addZoneToManagedZones
 - 2.4.4 - getPoint(aZone) returns uip-to-date pos for linked and normal zones
         - linkUnit can use "useOffset" property to keep relative position
 - 2.4.5 - updated various methods to support getPoint when referencing 
           zone.point  
 - 2.4.6 - corrected spelling in markZoneWithSmoke
 - 2.4.7 - copy reference to dcs zone into cfx zone 
 - 2.4.8 - getAllZoneProperties
 - 2.4.9 - createSimpleZone no longer requires location 
         - parse dcs adds empty .properties = {} if none tehre 
		 - createCircleZone adds empty properties 
		 - createPolyZone adds empty properties 
 - 2.4.10 - pickRandomZoneFrom now defaults to all cfxZones.zones
	      - getBoolFromZoneProperty also recognizes 0, 1
		  - removed autostart
 - 2.4.11 - removed typo in get closest zone 
 - 2.4.12 - getStringFromZoneProperty
 - 2.5.0  - harden getZoneProperty and all getPropertyXXXX
 - 2.5.1  - markZoneWithSmoke supports alt attribute 
 - 2.5.2  - getPoint also writes through to zone itself for optimization
          - new method getPositiveRangeFromZoneProperty(theZone, theProperty, default)
 - 2.5.3  - new getAllGroupsInZone()
 - 2.5.4  - cleaned up getZoneProperty break on no properties 
		  - extractPropertyFromDCS trims key and property 
 - 2.5.5  - pollFlag() centralized for banging 
          - allStaticsInZone
 - 2.5.6  - flag accessor setFlagValue(), getFlagValue()  
		  - pollFlag supports theZone as final parameter
		  - randomDelayFromPositiveRange
		  - isMEFlag
 - 2.5.7  - pollFlag supports dml flags
 - 2.5.8  - flagArrayFromString
		  - getFlagNumber invokes tonumber() before returning result 
 - 2.5.9  - removed pass-back flag in getPoint() 
 - 2.6.0  - testZoneFlag() method based flag testing
 - 2.6.1  - Watchflag parsing of zone condition for number-named flags
          - case insensitive
		  - verbose for zone-local accepted (but not acted upon)
		  - hasProperty now offers active information when looking for '*?' and '*!'
 - 2.7.0  - doPollFlag - fully support multiple flags per bang!
 - 2.7.1  - setFlagValueMult()
 - 2.7.2  - '261 repair'
 - 2.7.3  - testZoneFlag returns mathodResult, lastVal
          - evalFlagMethodImmediate()
 - 2.7.4  - doPollFlag supports immediate number setting 
 - 2.7.5  - more QoL checks when mixing up ? and ! for attributes
 - 2.7.6  - trim for getBoolFromZoneProperty and getStringFromZoneProperty
 - 2.7.7  - randomInRange()
          - show number of zones 
 - 2.7.8  - inc method now triggers if curr value > last value 
          - dec method noew triggers when curr value < last value 
		  - testFlagByMethodForZone supports lohi, hilo transitions 
		  - doPollFlag supports 'pulse'
		  - pulseFlag
		  - unpulse 
- 2.7.9   - getFlagValue QoL for <none>
          - setFlagValue QoL for <none>
- 2.8.0	  - new allGroupNamesInZone()
- 2.8.1   - new zonesLinkedToUnit()  
- 2.8.2   - flagArrayFromString trims elements before range check 
- 2.8.3   - new verifyMethod()
          - changed extractPropertyFromDCS() to also match attributes with blanks like "the Attr" to "theAttr"
		  - new expandFlagName()
- 2.8.4   - fixed bug in setFlagValue()
- 2.8.5   - createGroundUnitsInZoneForCoalition() now always passes back a copy of the group data 
          - data also contains cty = country and cat = category for easy spawn
          - getFlagValue additional zone name guards 
- 2.8.6   - fix in getFlagValue for missing delay 
- 2.8.7   - update isPointInsideZone(thePoint, theZone, radiusIncrease) - new radiusIncrease
          - isPointInsideZone() returns delta as well
- 2.9.0   - linked zones can useOffset and useHeading 
		  - getPoint update 
		  - new getOrigin()
		  - pointInZone understands useOrig
		  - allStaticsInZone supports useOrig 
		  - dPhi for zones with useHeading 
		  - uHdg for zones with useHading, contains linked unit's original heading
		  - Late-linking implemented:
		  - linkUnit works for late-activating units 
		  - linkUnit now also works for player / clients, dynamic (re-)linking 
		  - linkUnit uses zone's origin for all calculations 

--]]--
cfxZones.verbose = false
cfxZones.caseSensitiveProperties = false -- set to true to make property names case sensitive 
cfxZones.ups = 1 -- updates per second. updates moving zones

cfxZones.zones = {} -- these are the zone as retrieved from the mission.
					-- ALWAYS USE THESE, NEVER DCS's ZONES!!!!

-- a zone has the following attributes
-- x, z -- coordinate of center. note they have correct x, 0, z coordinates so no y-->z mapping
-- radius (zero if quad zone)
-- isCircle (true if quad zone)
-- poly the quad coords are in the poly attribute and are a 
-- 1..n, wound counter-clockwise as (currently) in DCS:
-- lower left, lower right upper left, upper right, all coords are x, 0, z 
-- bounds - contain the AABB coords for the zone: ul (upper left), ur, ll (lower left), lr 
--          for both circle and poly, all (x, 0, z)

-- zones can carry information in their names that can get processed into attributes
-- use 
-- zones can also carry information in their 'properties' tag that ME allows to 
-- edit. cfxZones provides an easy method to access these properties 
--  - getZoneProperty (returns as string)
--  - getMinMaxFromZoneProperty
--  - getBoolFromZoneProperty
--  - getNumberFromZoneProperty


-- SUPPORTED PROPERTIES
-- - "linkedUnit" - zone moves with unit of that name. must be exact match
--   can be combined with other attributes that extend (e.g. scar manager and
--   limited pilots/airframes 
--

--
-- readZonesFromDCS is executed exactly once at the beginning
-- from then on, use only the cfxZones.zones table 
-- WARNING: cfxZones is NOT case-sensitive. All zone names are 
-- indexed by upper case. If you have two zones with same name but 
-- different case, one will be replaced
--

function cfxZones.readFromDCS(clearfirst)
	if (clearfirst) then
		cfxZones.zones = {}
	end
	-- not all missions have triggers or zones
	if not env.mission.triggers then 
		if cfxZones.verbose then 
			trigger.action.outText("cf/x zones: no env.triggers defined", 10)
		end
		return
	end
	
	if not env.mission.triggers.zones then 
		if cfxZones.verbose then 
			trigger.action.outText("cf/x zones: no zones defined", 10)
		end
		return;
	end

	-- we only retrieve the data we need. At this point it is name, location and radius
	-- and put this in our own little  structure. we also convert to all upper case name for index
	-- and assume that the name may also carry meaning, e.g. 'LZ:' defines a landing zone
	-- so we can quickly create other sets from this
	-- zone object. DCS 2.7 introduced quads, so this is supported as well
	--   name - name in upper case
	--   isCircle - true if circular zone 
	--   isPoly - true if zone is defined by convex polygon, e.g. quad 
	--   point - vec3 (x 0 z) - zone's in-world center, used to place the coordinate
	--   radius - number, zero when quad
	--   bounds - aabb with attributes ul, ur, ll, lr (upper left .. lower right) as (x, 0, z)
	--   poly - array 1..n of poly points, wound counter-clockwise 
	
	for i, dcsZone in pairs(env.mission.triggers.zones) do
		if type(dcsZone) == 'table' then -- hint taken from MIST: verify type when reading from dcs
										 -- dcs data is like a box of chocolates...
			local newZone = {}
			-- name, converted to upper is used only for indexing
			-- the original name remains untouched
			newZone.dcsZone = dcsZone
			newZone.name = dcsZone.name
			newZone.isCircle = false
			newZone.isPoly = false
			newZone.radius = 0
			newZone.poly = {}
			newZone.bounds = {}
			newZone.properties = {} -- dcs has this too, copy if present
			if dcsZone.properties then 
				newZone.properties = dcsZone.properties 
			else
				newZone.properties = {}
			end -- WARNING: REF COPY. May need to clone 
			
			local upperName = newZone.name:upper()
			
			-- location as 'point'
			-- WARNING: zones locs are 2D (x,y) pairs, whily y in DCS is altitude.
			--          so we need to change (x,y) into (x, 0, z). Since Zones have no
			--          altitude (they are an infinite cylinder) this works. Remember to 
			--          drop y from zone calculations to see if inside. 
			newZone.point = cfxZones.createPoint(dcsZone.x, 0, dcsZone.y)
			newZone.dcsOrigin = cfxZones.createPoint(dcsZone.x, 0, dcsZone.y)

			-- start type processing. if zone.type exists, we have a mission 
			-- created with 2.7 or above, else earlier 
			local zoneType = 0
			if (dcsZone.type) then 
				zoneType = dcsZone.type 
			end
			
			if zoneType == 0 then 
				-- circular zone 
				newZone.isCircle = true 
				newZone.radius = dcsZone.radius
	
			elseif zoneType == 2 then
				-- polyZone
				newZone.isPoly = true 
				newZone.radius = dcsZone.radius -- radius is still written in DCS, may change later
				-- now transfer all point in the poly
				-- note: DCS in 2.7 misspells vertices as 'verticies'
				-- correct vor this 
				local verts = {}
				if dcsZone.verticies then verts = dcsZone.verticies 
				else 
					-- in later versions, this was corrected
					verts = dcsZone.vertices -- see if this is ever called
				end
				
				for v=1, #verts do
					local dcsPoint = verts[v]
					local polyPoint = cfxZones.createPointFromDCSPoint(dcsPoint) -- (x, y) -- (x, 0, y-->z)
					newZone.poly[v] = polyPoint
				end
			else 
				
				trigger.action.outText("cf/x zones: malformed zone #" .. i .. " unknown type " .. zoneType, 10)
			end
			

			-- calculate bounds
			cfxZones.calculateZoneBounds(newZone) 

			-- add to my table
			cfxZones.zones[upperName] = newZone -- WARNING: UPPER ZONE!!!
			--trigger.action.outText("znd: procced " .. newZone.name .. " with radius " .. newZone.radius, 30)
		else
			if cfxZones.verbose then 
				trigger.action.outText("cf/x zones: malformed zone #" .. i .. " dropped", 10)
			end
		end -- else var not a table
		
	end -- for all zones kvp
end -- readFromDCS

function cfxZones.calculateZoneBounds(theZone)
	if not (theZone) then return 
	end
	
	local bounds = theZone.bounds -- copy ref!
	
	if theZone.isCircle then 
		-- aabb are easy: center +/- radius 
		local center = theZone.point
		local radius = theZone.radius 
		-- dcs uses z+ is down on map
		-- upper left is center - radius 
		bounds.ul = cfxZones.createPoint(center.x - radius, 0, center.z - radius)
		bounds.ur = cfxZones.createPoint(center.x + radius, 0, center.z - radius)
		bounds.ll = cfxZones.createPoint(center.x - radius, 0, center.z + radius)
		bounds.lr = cfxZones.createPoint(center.x + radius, 0, center.z + radius)
		
	elseif theZone.isPoly then
		local poly = theZone.poly -- ref copy!
		-- create the four points
		local ll = cfxZones.createPointFromPoint(poly[1])
		local lr = cfxZones.createPointFromPoint(poly[1])
		local ul = cfxZones.createPointFromPoint(poly[1])
		local ur = cfxZones.createPointFromPoint(poly[1])

		-- now iterate through all points and adjust bounds accordingly 
		for v=2, #poly do 
			 local vertex = poly[v]
			 if (vertex.x < ll.x) then ll.x = vertex.x; ul.x = vertex.x end 
			 if (vertex.x > lr.x) then lr.x = vertex.x; ur.x = vertex.x end 
			 if (vertex.z < ul.z) then ul.z = vertex.z; ur.z = vertex.z end
			 if (vertex.z > ll.z) then ll.z = vertex.z; lr.z = vertex.z end 
			
		end
		
		-- now keep the new point references
		-- and store them in the zone's bounds
		bounds.ll = ll
		bounds.lr = lr
		bounds.ul = ul
		bounds.ur = ur 
	else 
		-- huston, we have a problem
		if cfxZones.verbose then 
			trigger.action.outText("cf/x zones: calc bounds: zone " .. theZone.name .. " has unknown type", 30)
		end
	end
	
end

function cfxZones.createPoint(x, y, z)
	local newPoint = {}
	newPoint.x = x
	newPoint.y = y
	newPoint.z = z 
	return newPoint
end

function cfxZones.copyPoint(inPoint) 
	local newPoint = {}
	newPoint.x = inPoint.x
	newPoint.y = inPoint.y
	newPoint.z = inPoint.z 
	return newPoint	
end

function cfxZones.createHeightCorrectedPoint(inPoint) -- this should be in dcsCommon
	local cP = cfxZones.createPoint(inPoint.x, land.getHeight({x=inPoint.x, y=inPoint.z}),inPoint.z)
	return cP
end

function cfxZones.getHeightCorrectedZonePoint(theZone)
	return cfxZones.createHeightCorrectedPoint(theZone.point)
end

function cfxZones.createPointFromPoint(inPoint)
	return cfxZones.copyPoint(inPoint)
end

function cfxZones.createPointFromDCSPoint(inPoint) 
	return cfxZones.createPoint(inPoint.x, 0, inPoint.y)
end


function cfxZones.createRandomPointInsideBounds(bounds)
	local x = math.random(bounds.ll.x, ur.x)
	local z = math.random(bounds.ll.z, ur.z)
	return cfxZones.createPoint(x, 0, z)
end

function cfxZones.addZoneToManagedZones(theZone)
	local upperName = string.upper(theZone.name) -- newZone.name:upper()
	cfxZones.zones[upperName] = theZone
end

function cfxZones.createUniqueZoneName(inName, searchSet)
	if not inName then return nil end 
	if not searchSet then searchSet = cfxZones.zones end 
	inName = inName:upper()
	while searchSet[inName] ~= nil do 
		inName = inName .. "X"
	end
	return inName
end

function cfxZones.createSimpleZone(name, location, radius, addToManaged)
	if not radius then radius = 10 end
	if not addToManaged then addToManaged = false end 
	if not location then 
		location = {}
	end
	if not location.x then location.x = 0 end 
	if not location.z then location.z = 0 end 
	
	local newZone = cfxZones.createCircleZone(name, location.x, location.z, radius)
	
	if addToManaged then 
		cfxZones.addZoneToManagedZones(newZone)
	end
	return newZone
end

function cfxZones.createCircleZone(name, x, z, radius) 
	local newZone = {}
	newZone.isCircle = true
	newZone.isPoly = false
	newZone.poly = {}
	newZone.bounds = {}
			
	newZone.name = name
	newZone.radius = radius
	newZone.point = cfxZones.createPoint(x, 0, z)
 
	-- props 
	newZone.properties = {}
	
	-- calculate my bounds
	cfxZones.calculateZoneBounds(newZone)
	
	return newZone
end

function cfxZones.createPolyZone(name, poly) -- poly must be array of point type
local newZone = {}
	newZone.isCircle = false
	newZone.isPoly = true
	newZone.poly = {}
	newZone.bounds = {}
			
	newZone.name = name
	newZone.radius = 0
	-- copy poly
	for v=1, #poly do 
		local theVertex = poly[v] 
		newZone.poly[v] = cfxZones.createPointFromPoint(theVertex) 
	end
	
	-- properties 
	newZone.properties = {}
	
	cfxZones.calculateZoneBounds(newZone)
end



function cfxZones.createRandomZoneInZone(name, inZone, targetRadius, entirelyInside)
	-- create a new circular zone with center placed inside inZone
	-- if entirelyInside is false, only the zone's center is guaranteed to be inside
	-- inZone.
	
--	trigger.action.outText("Zones: creating rZiZ with tr = " .. targetRadius .. " for " .. inZone.name .. " that as r = " .. inZone.radius, 10)
	
	if inZone.isCircle then 
		local sourceRadius = inZone.radius
		if entirelyInside and targetRadius > sourceRadius then targetRadius = sourceRadius end
		if entirelyInside then sourceRadius = sourceRadius - targetRadius end
	
		-- ok, let's first create a random percentage value for the new radius
		local percent = 1 / math.random(100)
		-- now lets get a random degree
		local degrees = math.random(360) * 3.14152 / 180 -- ok, it's actually radiants. 
		local r = sourceRadius * percent 
		local x = inZone.point.x + r * math.cos(degrees)
		local z = inZone.point.z + r * math.sin(degrees)
		-- construct new zone
		local newZone = cfxZones.createCircleZone(name, x, z, targetRadius)
		return newZone
	
	elseif inZone.isPoly then 
		-- we have a poly zone. the way we do this is simple:
		-- generate random x, z with ranges of the bounding box 
		-- until the point falls within the polygon.
		local newPoint = {}
		local emergencyBrake = 0
		repeat
			newPoint = cfxZones.createRandomPointInsideBounds(inZone.bounds)
			emergencyBrake = emergencyBrake + 1
			if (emergencyBrake > 100) then 
				newPoint = cfxZones.copyPoint(inZone.Point)
				trigger.action.outText("CreateZoneInZone: mergency brake for inZone" .. inZone.name,  10)
				break
			end
		until cfxZones.isPointInsidePoly(newPoint, inZone.poly)
		
		-- construct new zone
		local newZone = cfxZones.createCircleZone(name, newPoint.x, newPoint.z, targetRadius)
		return newZone
		
	else 
		-- zone type unknown
		trigger.action.outText("CreateZoneInZone: unknown zone type for inZone =" .. inZone.name ,  10)
		return nil 
	end
end

-- polygon inside zone calculations


-- isleft returns true if point P is to the left of line AB 
-- by determining the sign (up or down) of the normal vector of 
-- the two vectors PA and PB in the y coordinate. We arbitrarily define
-- left as being > 0, so right is <= 0. As long as we always use the 
-- same comparison, it does not matter what up or down mean.
-- this is important because we don't know if dcs always winds quads
-- the same way, we must simply assume that they are wound as a polygon 
function cfxZones.isLeftXZ(A, B, P)
	return ((B.x - A.x)*(P.z - A.z) - (B.z - A.z)*(P.x - A.x)) > 0
end

-- returns true/false for inside
function cfxZones.isPointInsideQuad(thePoint, A, B, C, D) 
    -- Inside test (only convex polygons): 
	-- point lies on the same side of each quad's vertex AB, BC, CD, DA
	-- how do we find out which side a point lies on? via the cross product
	-- see isLeft below
	
	-- so all we need to do is make sure all results of isLeft for all
	-- four sides are the same
	mustMatch = isLeftXZ(A, B, thePoint) -- all test results must be the same and we are ok
									   -- they just must be the same side.
	if (cfxZones.isLeftXZ(B, C, thePoint ~= mustMatch)) then return false end -- on other side than all before
	if (cfxZones.isLeftXZ(C, D, thePoint ~= mustMatch)) then return false end 
	if (cfxZones.isLeftXZ(D, A, thePoint ~= mustMatch)) then return false end
	return true
end

-- generalized version of insideQuad, assumes winding of poly, poly convex, poly closed
function cfxZones.isPointInsidePoly(thePoint, poly)
	local mustMatch = cfxZones.isLeftXZ(poly[1], poly[2], thePoint)
	for v=2, #poly-1 do 
		if cfxZones.isLeftXZ(poly[v], poly[v+1], thePoint) ~= mustMatch then return false end
	end
	-- final test
	if cfxZones.isLeftXZ(poly[#poly], poly[1], thePoint) ~= mustMatch then return false end
	
	return true
end;

function cfxZones.isPointInsideZone(thePoint, theZone, radiusIncrease)
	-- radiusIncrease only works for circle zones 
	if not radiusIncrease then radiusIncrease = 0 end 
	local p = {x=thePoint.x, y = 0, z = thePoint.z} -- zones have no altitude
	if (theZone.isCircle) then 
		local zp = cfxZones.getPoint(theZone)
		local d = dcsCommon.dist(p, theZone.point)
		return d < theZone.radius + radiusIncrease, d 
	end 
	
	if (theZone.isPoly) then 
		--trigger.action.outText("zne: isPointInside: " .. theZone.name .. " is Polyzone!", 30)
		return (cfxZones.isPointInsidePoly(p, theZone.poly)), 0 -- always returns delta 0
	end

	trigger.action.outText("isPointInsideZone: Unknown zone type for " .. outerZone.name, 10)
end

-- isZoneInZone returns true if center of innerZone is inside  outerZone
function cfxZones.isZoneInsideZone(innerZone, outerZone) 
	return cfxZones.isPointInsideZone(innerZone.point, outerZone)

	
end

function cfxZones.getZonesContainingPoint(thePoint, testZones) -- return array 
	if not testZones then 
		testZones = cfxZones.zones 
	end 
	
	local containerZones = {}
	for tName, tData in pairs(testZones) do 
		if cfxZones.isPointInsideZone(thePoint, tData) then 
			table.insert(containerZones, tData)
		end
	end

	return containerZones
end

function cfxZones.getFirstZoneContainingPoint(thePoint, testZones)
	if not testZones then 
		testZones = cfxZones.zones 
	end 
	
	for tName, tData in pairs(testZones) do 
		if cfxZones.isPointInsideZone(thePoint, tData) then 
			return tData
		end
	end

	return nil
end

function cfxZones.getAllZonesInsideZone(superZone, testZones) -- returnes array!
	if not testZones then 
		testZones = cfxZones.zones 
	end 
	
	local containedZones = {}
	for zName, zData in pairs(testZones) do
		if cfxZones.isZoneInsideZone(zData, superZone) then 
			if zData ~= superZone then 
				-- we filter superzone because superzone usually resides 
				-- inside itself 
				table.insert(containedZones, zData)
			end
		end
	end
	return containedZones 
end

function cfxZones.getZonesWithAttributeNamed(attributeName, testZones)
	if not testZones then testZones = cfxZones.zones end 

	local attributZones = {}
	for aName,aZone in pairs(testZones) do
		local attr = cfxZones.getZoneProperty(aZone, attributeName)
		if attr then 
			-- this zone has the requested attribute
			table.insert(attributZones, aZone)
		end
	end
	return attributZones
end

--
-- units / groups in zone
--
function cfxZones.allGroupsInZone(theZone, categ) -- categ is optional, must be code 
	-- warning: does not check for exiting!
	--trigger.action.outText("Zone " .. theZone.name .. " radius " .. theZone.radius, 30)
	local inZones = {}
	local coals = {0, 1, 2} -- all coalitions
	for idx, coa in pairs(coals) do 
		local allGroups = coalition.getGroups(coa, categ)
		for key, group in pairs(allGroups) do -- iterate all groups
			if cfxZones.isGroupPartiallyInZone(group, theZone) then
				table.insert(inZones, group)
			end
		end
	end
	return inZones
end

function cfxZones.allGroupNamesInZone(theZone, categ) -- categ is optional, must be code 
	-- warning: does not check for exiting!
	--trigger.action.outText("Zone " .. theZone.name .. " radius " .. theZone.radius, 30)
	local inZones = {}
	local coals = {0, 1, 2} -- all coalitions
	for idx, coa in pairs(coals) do 
		local allGroups = coalition.getGroups(coa, categ)
		for key, group in pairs(allGroups) do -- iterate all groups
			if cfxZones.isGroupPartiallyInZone(group, theZone) then
				table.insert(inZones, group:getName())
			end
		end
	end
	return inZones
end

function cfxZones.allStaticsInZone(theZone, useOrigin) -- categ is optional, must be code 
	-- warning: does not check for exiting!
	local inZones = {}
	local coals = {0, 1, 2} -- all coalitions
	for idx, coa in pairs(coals) do 
		local allStats = coalition.getStaticObjects(coa)
		for key, statO in pairs(allStats) do -- iterate all groups
			local oP = statO:getPoint()
			if useOrigin then 
				if cfxZones.pointInZone(oP, theZone, true) then 
					-- use DCS original coords
					table.insert(inZones, statO)
				end
			elseif cfxZones.pointInZone(oP, theZone) then
				table.insert(inZones, statO)
			end
		end
	end
	return inZones
end

function cfxZones.groupsOfCoalitionPartiallyInZone(coal, theZone, categ) -- categ is optional
	local groupsInZone = {}
	local allGroups = coalition.getGroups(coal, categ)
	for key, group in pairs(allGroups) do -- iterate all groups
		if group:isExist() then
			if cfxZones.isGroupPartiallyInZone(group, theZone) then
				table.insert(groupsInZone, group)			
			end
		end
	end
	return groupsInZone
end

function cfxZones.isGroupPartiallyInZone(aGroup, aZone)
	if not aGroup then return false end 
	if not aZone then return false end 
		
	if not aGroup:isExist() then return false end 
	local allUnits = aGroup:getUnits()
	for uk, aUnit in pairs (allUnits) do 
		if aUnit:isExist() and aUnit:getLife() > 1 then 		
			local p = aUnit:getPoint()
			local inzone, percent, dist = cfxZones.pointInZone(p, aZone)
			if inzone then -- cfxZones.isPointInsideZone(p, aZone) then 			
				--trigger.action.outText("zne: YAY <" .. aUnit:getName() .. "> IS IN " .. aZone.name, 30) 
				return true
			end 
			--trigger.action.outText("zne: <" .. aUnit:getName() .. "> not in " .. aZone.name .. ", dist = " .. dist .. ", rad = ", aZone.radius, 30) 
		end
	end
	return false
end

function cfxZones.isEntireGroupInZone(aGroup, aZone)
	if not aGroup then return false end 
	if not aZone then return false end 
	if not aGroup:isExist() then return false end 
	local allUnits = aGroup:getUnits()
	for uk, aUnit in pairs (allUnits) do 
		if aUnit:isExist() and aUnit:getLife() > 1 then 
			local p = aUnit:getPoint()
			if not cfxZones.isPointInsideZone(p, aZone) then 
				return false
			end
		end
	end
	return true
end


--
-- Zone Manipulation
--

function cfxZones.offsetZone(theZone, dx, dz)
	-- first, update center 
	theZone.point.x = theZone.point.x + dx
	theZone.point.z = theZone.point.z + dz 
	
	-- now process all polygon points - it's empty for circular, so don't worry
	for v=1, #theZone.poly do 
		theZone.poly[v].x = theZone.poly[v].x + dx
		theZone.poly[v].z = theZone.poly[v].z + dz 
	end
end

function cfxZones.moveZoneTo(theZone, x, z)
	local dx = x - theZone.point.x
	local dz = z - theZone.point.z 
	cfxZones.offsetZone(theZone, dx, dz)
end;

function cfxZones.centerZoneOnUnit(theZone, theUnit) 
	local thePoint = theUnit:getPoint()
	cfxZones.moveZoneTo(theZone, thePoint.x, thePoint.z)
end


--[[
-- no longer makes sense with poly zones
function cfxZones.isZoneEntirelyInsideZone(innerZone, outerZone)
	if (innerZone.radius > outerZone.radius) then return false end -- cant fit inside
	local d = dcsCommon.dist(innerZone.point, outerZone.point)
	local reducedR = outerZone.radius - innerZone.radius
	return d < reducedR
end;
--]]

function cfxZones.dumpZones(zoneTable)
	if not zoneTable then zoneTable = cfxZones.zones end 
	
	trigger.action.outText("Zones START", 10)
	for i, zone in pairs(zoneTable) do 
		local myType = "unknown"
		if zone.isCircle then myType = "Circle" end
		if zone.isPoly then myType = "Poly" end 
		
		trigger.action.outText("#".. i .. ": " .. zone.name .. " of type " .. myType, 10)
	end
	trigger.action.outText("Zones END", 10)
end

function cfxZones.stringStartsWith(theString, thePrefix)
	return theString:find(thePrefix) == 1
end

function cfxZones.keysForTable(theTable)
	local keyset={}
	local n=0

	for k,v in pairs(tab) do
		n=n+1
		keyset[n]=k
	end
	return keyset
end


--
-- return all zones that have a specific named property
--
function cfxZones.zonesWithProperty(propertyName, searchSet)
	if not searchSet then searchSet = cfxZones.zones end 
	local theZones = {}
	for k, aZone in pairs(searchSet) do 
		if not aZone then 
			trigger.action.outText("+++zone: nil aZone for " .. k, 30)
		else 
			local lU = cfxZones.getZoneProperty(aZone, propertyName)
			if lU then 
				table.insert(theZones, aZone)
			end
		end
	end	
	return theZones
end

--
-- return all zones from the zone table that begin with string prefix
--
function cfxZones.zonesStartingWithName(prefix, searchSet)
	
	if not searchSet then searchSet = cfxZones.zones end 
	
--	trigger.action.outText("Enter: zonesStartingWithName for " .. prefix , 30)
	local prefixZones = {}
	prefix = prefix:upper() -- all zones have UPPERCASE NAMES! THEY SCREAM AT YOU
	for name, zone in pairs(searchSet) do
--		trigger.action.outText("testing " .. name:upper() .. " starts with " .. prefix , 30)
		if cfxZones.stringStartsWith(name:upper(), prefix) then
			prefixZones[name] = zone -- note: ref copy!
			--trigger.action.outText("zone with prefix <" .. prefix .. "> found: " .. name, 10)
		end
	end
	
	return prefixZones
end

--
-- return all zones from the zone table that begin with the string or set of strings passed in prefix 
-- if you pass 'true' as second (optional) parameter, it will first look for all zones that begin
-- with '+' and return only those. Use during debugging to force finding a specific zone
--
function cfxZones.zonesStartingWith(prefix, searchSet, debugging)
	-- you can force zones by having their name start with "+"
	-- which will force them to return immediately if debugging is true for this call

	if (debugging) then 
		local debugZones = cfxZones.zonesStartingWithName("+", searchSet)
		if not (next(debugZones) == nil) then -- # operator only works on array elements 
			--trigger.action.outText("returning zones with prefix <" .. prefix .. ">", 10)
			return debugZones 
		end 
	end
	
	--trigger.action.outText("#debugZones is  <" .. #debugZones .. ">", 10)

	if (type(prefix) == "string") then 
		return cfxZones.zonesStartingWithName(prefix, searchSet)
	end
	
	local allZones = {}
	for i=1, #prefix do 
		-- iterate through all names in prefix set
		local theName = prefix[i]
		local newZones = cfxZones.zonesStartingWithName(theName, searchSet)
		-- add them all to current table
		for zName, zInfo in pairs(newZones) do 
			allZones[zName] = zInfo -- will also replace doublets
		end
	end
	
	return allZones
end

function cfxZones.getZoneByName(aName, searchSet) 
	if not searchSet then searchSet = cfxZones.zones end 
	aName = aName:upper()
	return searchSet[aName] -- the joys of key value pairs
end

function cfxZones.getZonesContainingString(aString, searchSet) 
	if not searchSet then searchSet = cfxZones.zones end
	aString = string.upper(aString)
	resultSet = {}
	for zName, zData in pairs(searchSet) do 
		if aString == string.upper(zData.name) then 
			resultSet[zName] = zData
		end
	end
	
end;

-- filter zones by range to a point. returns indexed set
function cfxZones.getZonesInRange(point, range, theZones)
	if not theZones then theZones = cfxZones.zones end
	
	local inRangeSet = {}
	for zName, zData in pairs (theZones) do 
		if dcsCommon.dist(point, zData.point) < range then 
			table.insert(inRangeSet, zData)
		end
	end
	return inRangeSet 
end

-- get closest zone returns the zone that is closest to point 
function cfxZones.getClosestZone(point, theZones)
	if not theZones then theZones = cfxZones.zones end
	local lPoint = {x=point.x, y=0, z=point.z}
	local currDelta = math.huge 
	local closestZone = nil
	for zName, zData in pairs(theZones) do 
		local zPoint = cfxZones.getPoint(zData)
		local delta = dcsCommon.dist(lPoint, zPoint) -- emulate flag compare 
		if (delta < currDelta) then 
			currDelta = delta
			closestZone = zData
		end
	end
	return closestZone, currDelta 
end

-- return a random zone from the table passed in zones
function cfxZones.pickRandomZoneFrom(zones)
	if not zones then zones = cfxZones.zones end
	local indexedZones = dcsCommon.enumerateTable(zones)
	local r = math.random(#indexedZones)
	return indexedZones[r]
end

-- return an zone element by index 
function cfxZones.getZoneByIndex(theZones, theIndex) 
	local enumeratedZones = dcsCommon.enumerateTable(theZones)
	if (theIndex > #enumeratedZones) then
		trigger.action.outText("WARNING: zone index " .. theIndex .. " out of bounds - max = " .. #enumeratedZones, 30)
		return nil end
	if (theIndex < 1) then return nil end
	
	return enumeratedZones[theIndex]
end

-- place a smoke marker in center of zone, offset by dx, dy 
function cfxZones.markZoneWithSmoke(theZone, dx, dz, smokeColor, alt)
	if not alt then alt = 5 end 
	local point = cfxZones.getPoint(theZone) --{} -- theZone.point
	point.x = point.x + dx -- getpoint updates and returns copy 
	point.z = point.z + dz 
	-- get height at point 
	point.y = land.getHeight({x = point.x, y = point.z}) + alt
	-- height-correct
	--local newPoint= {x = point.x, y = land.getHeight({x = point.x, y = point.z}) + 3, z= point.z}
	trigger.action.smoke(point, smokeColor)
end

-- place a smoke marker in center of zone, offset by radius and degrees 
function cfxZones.markZoneWithSmokePolar(theZone, radius, degrees, smokeColor, alt)
	local rads = degrees * math.pi / 180
	local dx = radius * math.sin(rads)
	local dz = radius * math.cos(rads)
	cfxZones.markZoneWithSmoke(theZone, dx, dz, smokeColor, alt)
end

-- place a smoke marker in center of zone, offset by radius and randomized degrees 
function cfxZones.markZoneWithSmokePolarRandom(theZone, radius, smokeColor)
	local degrees = math.random(360)
	cfxZones.markZoneWithSmokePolar(theZone, radius, degrees, smokeColor)
end


-- unitInZone returns true if theUnit is inside the zone 
-- the second value returned is the percentage of distance
-- from center to rim, with 100% being entirely in center, 0 = outside
-- the third value returned is the distance to center
function cfxZones.pointInZone(thePoint, theZone, useOrig)

	if not (theZone) then return false, 0, 0 end
		
	local pflat = {x = thePoint.x, y = 0, z = thePoint.z}
	
	local zpoint 
	if useOrig then
		zpoint = cfxZones.getDCSOrigin(theZone)
	else 
		zpoint = cfxZones.getPoint(theZone) -- updates zone if linked 
	end
	local ppoint = thePoint -- xyz
	local pflat = {x = ppoint.x, y = 0, z = ppoint.z}
	local dist = dcsCommon.dist(zpoint, pflat)
	
	if theZone.isCircle then 
		if theZone.radius <= 0 then 
			return false, 0, 0
		end

		local success = dist < theZone.radius
		local percentage = 0
		if (success) then 
			percentage = 1 - dist / theZone.radius 
		end
		return success, percentage, dist 
	
	elseif theZone.isPoly then
		local success = cfxZones.isPointInsidePoly(pflat, theZone.poly)
		return success, 0, dist
	else 
		trigger.action.outText("pointInZone: Unknown zone type for " .. theZone.name, 10)
	end

	return false
end

function cfxZones.unitInZone(theUnit, theZone)
	if not (theUnit) then return false, 0, 0 end
	if not (theUnit:isExist()) then return false, 0, 0 end
	-- force zone update if it is linked to another zone 
	-- pointInZone does update
	local thePoint = theUnit:getPoint()
	return cfxZones.pointInZone(thePoint, theZone)
	
end

-- returns all units of the input set that are inside the zone 
function cfxZones.unitsInZone(theUnits, theZone)
	if not theUnits then return {} end
	if not theZone then return {} end
	
	local zoneUnits = {}
	for index, aUnit in pairs(theUnits) do 
		if cfxZones.unitInZone(aUnit, theZone) then 
			table.insert( zoneUnits, aUnit)
		end
	end
	return zoneUnits
end

function cfxZones.closestUnitToZoneCenter(theUnits, theZone)
	-- does not care if they really are in zone. call unitsInZone first
	-- if you need to have them filtered
	-- theUnits MUST BE ARRAY
	if not theUnits then return nil end
	if #theUnits == 0 then return nil end
	local closestUnit = theUnits[1]
	for i=2, #theUnits do
		local aUnit = theUnits[i]
		if dcsCommon.dist(theZone.point, closestUnit:getPoint()) > dcsCommon.dist(theZone.point, aUnit:getPoint()) then 
			closestUnit = aUnit
		end
	end
	return closestUnit
end

function cfxZones.anyPlayerInZone(theZone) -- returns first player it finds
	for pname, pinfo in pairs(cfxPlayer.playerDB) do
		local playerUnit = pinfo.unit
		if (cfxZones.unitInZone(playerUnit, theZone)) then 
			return true, playerUnit
		end
	end -- for all players 
	return false, nil
end


-- grow zone
function cfxZones.growZone()
	-- circular zones simply increase radius
	-- poly zones: not defined 
	
end


-- creating units in a zone
function cfxZones.createGroundUnitsInZoneForCoalition (theCoalition, groupName, theZone, theUnits, formation, heading) 
	-- theUnits can be string or table of string 
	if not groupName then groupName = "G_"..theZone.name end 
	-- group name will be taken from zone name and prependend with "G_"
	local theGroup = dcsCommon.createGroundGroupWithUnits(groupName, theUnits, theZone.radius, nil, formation)
	
	-- turn the entire formation to heading
	if (not heading) then heading = 0 end
	dcsCommon.rotateGroupData(theGroup, heading) -- currently, group is still at origin, no cx, cy
	
	
	-- now move the group to center of theZone
	dcsCommon.moveGroupDataTo(theGroup, 
						  theZone.point.x, 
						  theZone.point.z) -- watchit: Z!!!


	-- create the group in the world and return it
	-- first we need to translate the coalition to a legal 
	-- country. we use UN for neutral, cjtf for red and blue 
	local theSideCJTF = dcsCommon.coalition2county(theCoalition)
	-- store cty and cat for later access. DCS doesn't need it, but we may 
	
	theGroup.cty = theSideCJTF
	theGroup.cat = Group.Category.GROUND
	
    -- create a copy of the group data for 
	-- later reference 
	local groupDataCopy = dcsCommon.clone(theGroup)

	local newGroup = coalition.addGroup(theSideCJTF, Group.Category.GROUND, theGroup)
	return newGroup, groupDataCopy
end

-- parsing zone names. The first part of the name until the first blank " " 
-- is the prefix and is dropped unless keepPrefix is true. 
-- all others are regarded as key:value pairs and are then added 
-- to the zone 
-- separated by equal sign "=" AND MUST NOT CONTAIN BLANKS
--
-- example usage "followZone unit=rotary-1 dx=30 dy=25 rotateWithHeading=true
--
-- OLD DEPRECATED TECH -- TO BE DECOMMISSIONED SOON, DO NOT USE
-- 
--[[--
function cfxZones.parseZoneNameIntoAttributes(theZone, keepPrefix)
--	trigger.action.outText("Parsing zone:  ".. theZone.name, 30)
	if not keepPrefix then keepPrefix = false end -- simply for clarity
	-- now split the name into space-separated strings
	local attributes = dcsCommon.splitString(theZone.name, " ")
	if not keepPrefix then table.remove(attributes, 1) end -- pop prefix

	-- now parse all substrings and add them as attributes to theZone
	for i=1, #attributes do 
		local a = attributes[i]
		local kvp = dcsCommon.splitString(a, "=")
		if #kvp == 2 then 
			-- we have key value pair
			local theKey = kvp[1]
			local theValue = kvp[2]
			theZone[theKey] = theValue 
--			trigger.action.outText("Zone ".. theZone.name .. " parsed: Key = " .. theKey .. ", Value = " .. theValue, 30)
		else 
--			trigger.action.outText("Zone ".. theZone.name .. ": dropped attribute " .. a, 30)
		end
	end 
end
--]]--
-- OLD DEPRECATED TECH -- TO BE DECOMMISSIONED SOON, DO NOT USE
--[[--
function cfxZones.processCraterZones ()
	local craters = cfxZones.zonesStartingWith("crater")

	

	-- all these zones need to be processed and their name infor placed into attributes
	for cName, cZone in pairs(craters) do
		cfxZones.parseZoneNameIntoAttributes(cZone)
		
		-- blow stuff up at the location of the zone 
		local cPoint = cZone.point
		cPoint.y = land.getHeight({x = cPoint.x, y = cPoint.z})  -- compensate for ground level
		trigger.action.explosion(cPoint, 900)
		 
		-- now interpret and act on the crater info 
		-- to destroy and place fire. 
		
		-- fire has small, medium, large 
		-- eg. fire=large
		
	end
end
--]]--
--
-- Flag Pulling 
--
function cfxZones.pulseFlag(theFlag, method, theZone)
	local args = {}
	args.theFlag = theFlag
	args.method = method
	args.theZone = theZone 
	local delay = 3
	if dcsCommon.containsString(method, ",") then 
		local parts = dcsCommon.splitString(method, ",")
		delay = parts[2]
		if delay then delay = tonumber(delay) end  
	end
	if not delay then delay = 3 end 
	if theZone.verbose then 
		trigger.action.outText("+++zne: RAISING pulse t="..delay.." for flag <" .. theFlag .. "> in zone <" .. theZone.name ..">", 30)
	end 
	local newVal = 1
	cfxZones.setFlagValue(theFlag, newVal, theZone)
	
	-- schedule second half of pulse 
	timer.scheduleFunction(cfxZones.unPulseFlag, args, timer.getTime() + delay)
end

function cfxZones.unPulseFlag(args)
	local theZone = args.theZone
	local method = args.method 
	local theFlag = args.theFlag 
	local newVal = 0
	-- we may later use method to determine pulse direction / newVal
	-- for now, we always go low 
	if theZone.verbose then 
		trigger.action.outText("+++zne: DOWNPULSE pulse for flag <" .. theFlag .. "> in zone <" .. theZone.name ..">", 30)
	end
	cfxZones.setFlagValue(theFlag, newVal, theZone)
end

function cfxZones.doPollFlag(theFlag, method, theZone)
	if cfxZones.verbose then 
		trigger.action.outText("+++zones: polling flag " .. theFlag .. " with " .. method, 30)
	end 
	
	if not theZone then 
		trigger.action.outText("+++zones: nil theZone on pollFlag", 30)
	end
	
	method = method:lower()
	method = dcsCommon.trim(method)
	val = tonumber(method)
	if val then 
		cfxZones.setFlagValue(theFlag, val, theZone)
		if cfxZones.verbose or theZone.verbose then
			trigger.action.outText("+++zones: flag <" .. theFlag .. "> changed to #" .. val, 30)
		end 
		return 
	end 
	
	--trigger.action.outText("+++zones: polling " .. theZone.name .. " method " .. method .. " flag " .. theFlag, 30)
	local currVal = cfxZones.getFlagValue(theFlag, theZone)
	if method == "inc" or method == "f+1" then 
		--trigger.action.setUserFlag(theFlag, currVal + 1)
		cfxZones.setFlagValue(theFlag, currVal+1, theZone)
		
	elseif method == "dec" or method == "f-1" then 
		-- trigger.action.setUserFlag(theFlag, currVal - 1)
		cfxZones.setFlagValue(theFlag, currVal-1, theZone)

	elseif method == "off" or method == "f=0" then 
		-- trigger.action.setUserFlag(theFlag, 0)
		cfxZones.setFlagValue(theFlag, 0, theZone)

	elseif method == "flip" or method == "xor" then 
		if currVal ~= 0 then 
--			trigger.action.setUserFlag(theFlag, 0)
			cfxZones.setFlagValue(theFlag, 0, theZone)

		else 
			--trigger.action.setUserFlag(theFlag, 1)
			cfxZones.setFlagValue(theFlag, 1, theZone)
		end
		
	elseif dcsCommon.stringStartsWith(method, "pulse") then 
		cfxZones.pulseFlag(theFlag, method, theZone)
		
	else 
		if method ~= "on" and method ~= "f=1" then 
			trigger.action.outText("+++zones: unknown method <" .. method .. "> - using 'on'", 30)
		end
		-- default: on.
--		trigger.action.setUserFlag(theFlag, 1)
		cfxZones.setFlagValue(theFlag, 1, theZone)
	end
	
	if cfxZones.verbose then
		local newVal = cfxZones.getFlagValue(theFlag, theZone)
		trigger.action.outText("+++zones: flag <" .. theFlag .. "> changed from " .. currVal .. " to " .. newVal, 30)
	end 
end

function cfxZones.pollFlag(theFlag, method, theZone) 
	local allFlags = {}
	if dcsCommon.containsString(theFlag, ",") then 
		if cfxZones.verbose then 
			trigger.action.outText("+++zones: will poll flag set <" .. theFlag .. "> with " .. method, 30)
		end
		allFlags = dcsCommon.splitString(theFlag, ",")
	else 
		table.insert(allFlags, theFlag)
	end
	
	for idx, aFlag in pairs(allFlags) do 
		aFlag = dcsCommon.trim(aFlag)
		-- note: mey require range preprocessing, but that's not
		-- a priority 
		cfxZones.doPollFlag(aFlag, method, theZone)
	end 
	
end

function cfxZones.expandFlagName(theFlag, theZone) 
	if not theFlag then return "!NIL" end 
	local zoneName = "<dummy>"
	if theZone then 
		zoneName = theZone.name -- for flag wildcards
	end
	
	if type(theFlag) == "number" then 
		-- straight number, return 
		return theFlag
	end
	
	-- we assume it's a string now
	theFlag = dcsCommon.trim(theFlag) -- clear leading/trailing spaces
	local nFlag = tonumber(theFlag) 
	if nFlag then -- a number, legal
		return theFlag
	end
		
	-- now do wildcard processing. we have alphanumeric
	if dcsCommon.stringStartsWith(theFlag, "*") then  
		theFlag = zoneName .. theFlag
	end
	return theFlag
end

function cfxZones.setFlagValueMult(theFlag, theValue, theZone)
	local allFlags = {}
	if dcsCommon.containsString(theFlag, ",") then 
		if cfxZones.verbose then 
			trigger.action.outText("+++zones: will multi-set flags <" .. theFlag .. "> to " .. theValue, 30)
		end
		allFlags = dcsCommon.splitString(theFlag, ",")
	else 
		table.insert(allFlags, theFlag)
	end
	
	for idx, aFlag in pairs(allFlags) do 
		aFlag = dcsCommon.trim(aFlag)
		-- note: mey require range preprocessing, but that's not
		-- a priority 
		cfxZones.setFlagValue(aFlag, theValue, theZone)
	end 
end

function cfxZones.setFlagValue(theFlag, theValue, theZone)
	local zoneName = "<dummy>"
	if not theZone then 
		trigger.action.outText("+++Zne: no zone on setFlagValue", 30) -- mod me for detector
	else 
		zoneName = theZone.name -- for flag wildcards
	end
	
	if type(theFlag) == "number" then 
		-- straight set, ME flag 
		trigger.action.setUserFlag(theFlag, theValue)
		return 
	end
	
	-- we assume it's a string now
	theFlag = dcsCommon.trim(theFlag) -- clear leading/trailing spaces
	local nFlag = tonumber(theFlag) 
	if nFlag then 
		trigger.action.setUserFlag(theFlag, theValue)
		return 
	end
	
	-- some QoL: detect "<none>"
	if dcsCommon.containsString(theFlag, "<none>") then 
		trigger.action.outText("+++Zone: warning - setFlag has '<none>' flag name in zone <" .. zoneName .. ">", 30) -- if error, intended break
	end
	
	-- now do wildcard processing. we have alphanumeric
	if dcsCommon.stringStartsWith(theFlag, "*") then  
		theFlag = zoneName .. theFlag
	end
	trigger.action.setUserFlag(theFlag, theValue)
end 

function cfxZones.getFlagValue(theFlag, theZone)
	local zoneName = "<dummy>"
	if not theZone or not theZone.name then 
		trigger.action.outText("+++Zne: no zone or zone name on getFlagValue", 30)
	else 
		zoneName = theZone.name -- for flag wildcards
	end
	
	if type(theFlag) == "number" then 
		-- straight get, ME flag 
		return tonumber(trigger.misc.getUserFlag(theFlag))
	end
	
	-- we assume it's a string now
	theFlag = dcsCommon.trim(theFlag) -- clear leading/trailing spaces
	local nFlag = tonumber(theFlag) 
	if nFlag then 
		return tonumber(trigger.misc.getUserFlag(theFlag))
	end
	
	-- some QoL: detect "<none>"
	if dcsCommon.containsString(theFlag, "<none>") then 
		trigger.action.outText("+++Zone: warning - getFlag has '<none>' flag name in zone <" .. zoneName .. ">", 30) -- break here
	end
	
	-- now do wildcard processing. we have alphanumeric
	if dcsCommon.stringStartsWith(theFlag, "*") then  
			theFlag = zoneName .. theFlag
	end
	return tonumber(trigger.misc.getUserFlag(theFlag))
end

function cfxZones.isMEFlag(inFlag)
	-- do NOT use me
	trigger.action.outText("+++zne: warning: deprecated isMEFlag", 30)
	return true 
	-- returns true if inFlag is a pure positive number
--	inFlag = dcsCommon.trim(inFlag)
--	return dcsCommon.stringIsPositiveNumber(inFlag)
end

function cfxZones.verifyMethod(theMethod, theZone)
	local lMethod = string.lower(theMethod)
	if lMethod == "#" or lMethod == "change" then 
		return true
	end

	if lMethod == "0" or lMethod == "no" or lMethod == "false" 
	   or lMethod == "off" then 
		return true  
	end
	
	if lMethod == "1" or lMethod == "yes" or lMethod == "true" 
	   or lMethod == "on" then 
	    return true  
	end
	
	if lMethod == "inc" or lMethod == "+1" then 
		return true
	end
	
	if lMethod == "dec" or lMethod == "-1" then 
		return true 
	end 
	
	if lMethod == "lohi" or lMethod == "pulse" then 
		return true
	end
	
	if lMethod == "hilo" then 
		return true
	end
	
	-- number constraints
	-- or flag constraints 	-- ONLY RETURN TRUE IF CHANGE AND CONSTRAINT MET 
	local op = string.sub(theMethod, 1, 1) 
	local remainder = string.sub(theMethod, 2)
	remainder = dcsCommon.trim(remainder) -- remove all leading and trailing spaces
--	local rNum = tonumber(remainder)

	if true then 
		-- we have a comparison = ">", "=", "<" followed by a number 
		-- THEY TRIGGER EACH TIME lastVal <> currVal AND condition IS MET  
		if op == "=" then 
			return true
		end
		
		if op == "#" or op == "~" then 
			return true
		end 
		
		if op == "<" then 
			return true
		end
		
		if op == ">" then 
			return true
		end
	end
	
	return false 
end

-- method-based flag testing 
function cfxZones.evalFlagMethodImmediate(currVal, theMethod, theZone)
	-- immediate eval - does not look at last val. 
	-- return true/false/value based on theMethod's contraints 
	-- simple constraints
	local lMethod = string.lower(theMethod)
	if lMethod == "#" or lMethod == "change" then 
		-- ALWAYS RETURNS TRUE for currval <> 0, flase if currval = 0
		return currVal ~= 0  
	end
	
	if lMethod == "0" or lMethod == "no" or lMethod == "false" 
	   or lMethod == "off" then 
		-- WARNING: ALWAYS RETURNS FALSE
		return false  
	end
	
	if lMethod == "1" or lMethod == "yes" or lMethod == "true" 
	   or lMethod == "on" then 
	    -- WARNING: ALWAYS RETURNS TRUE
		return true  
	end
	
	if lMethod == "inc" or lMethod == "+1" then 
		return currVal+1 -- this may be unexpected
	end
	
	if lMethod == "dec" or lMethod == "-1" then 
		return currVal-1 -- this may be unexpectd
	end 
	
	-- number constraints
	-- or flag constraints 
	-- ONLY RETURN TRUE IF CHANGE AND CONSTRAINT MET 
	local op = string.sub(theMethod, 1, 1) 
	local remainder = string.sub(theMethod, 2)
	remainder = dcsCommon.trim(remainder) -- remove all leading and trailing spaces
	local rNum = tonumber(remainder)
	if not rNum then 
		-- we use remainder as name for flag 
		-- PROCESS ESCAPE SEQUENCES
		local esc = string.sub(remainder, 1, 1)
		local last = string.sub(remainder, -1)
		if esc == "@" then 
			remainder = string.sub(remainder, 2)
			remainder = dcsCommon.trim(remainder)
		end
		
		if esc == "(" and last == ")" and string.len(remainder) > 2 then 
			-- note: iisues with startswith("(") ???
			remainder = string.sub(remainder, 2, -2)
			remainder = dcsCommon.trim(remainder)		
		end
		if esc == "\"" and last == "\"" and string.len(remainder) > 2 then 
			remainder = string.sub(remainder, 2, -2)
			remainder = dcsCommon.trim(remainder)		
		end
		if cfxZones.verbose then 
			trigger.action.outText("+++zne: accessing flag <" .. remainder .. ">", 30)
		end 
		rNum = cfxZones.getFlagValue(remainder, theZone)
	end 
	if rNum then 
		-- we have a comparison = ">", "=", "<" followed by a number  
		if op == "=" then 
			return currVal == rNum
		end
		
		if op == "#" or op == "~" then 
			return currVal ~= rNum 
		end 
		
		if op == "<" then 
			return currVal < rNum
		end
		
		if op == ">" then 
			return currVal > rNum
		end
	end
	
	-- if we get here, we have an error 
	local zoneName = "<NIL>"
	if theZone then zoneName = theZone.name end 
	trigger.action.outText("+++Zne: illegal |" .. theMethod .. "| in eval for zone " .. zoneName, 30 )
	return false 	
end

function cfxZones.testFlagByMethodForZone(currVal, lastVal, theMethod, theZone)
	-- return true/false based on theMethod's contraints 
	-- simple constraints
	-- ONLY RETURN TRUE IF CHANGE AND CONSTRAINT MET 
	local lMethod = string.lower(theMethod)
	if lMethod == "#" or lMethod == "change" then 
		-- check if currVal different from lastVal
		return currVal ~= lastVal  
	end
	
	if lMethod == "0" or lMethod == "no" or lMethod == "false" 
	   or lMethod == "off" then 
		-- WARNING: ONLY RETURNS TRUE IF FALSE AND lastval not zero!
		return currVal == 0 and currVal ~= lastVal  
	end
	
	if lMethod == "1" or lMethod == "yes" or lMethod == "true" 
	   or lMethod == "on" then 
	    -- WARNING: only returns true if lastval was false!!!!
		return (currVal ~= 0 and lastVal == 0)  
	end
	
	if lMethod == "inc" or lMethod == "+1" then 
--		return currVal == lastVal+1 -- better: test for greater than 
		return currVal > lastVal
	end
	
	if lMethod == "dec" or lMethod == "-1" then 
		--return currVal == lastVal-1
		return currVal < lastVal 
	end 
	
	if lMethod == "lohi" or lMethod == "pulse" then 
		return (lastVal <= 0 and currVal > 0)
	end
	
	if lMethod == "hilo" then 
		return (lastVal > 0 and currVal <= 0)
	end
	
	-- number constraints
	-- or flag constraints 
	-- ONLY RETURN TRUE IF CHANGE AND CONSTRAINT MET 
	local op = string.sub(theMethod, 1, 1) 
	local remainder = string.sub(theMethod, 2)
	remainder = dcsCommon.trim(remainder) -- remove all leading and trailing spaces
	local rNum = tonumber(remainder)
	if not rNum then 
		-- we use remainder as name for flag 
		-- PROCESS ESCAPE SEQUENCES
		local esc = string.sub(remainder, 1, 1)
		local last = string.sub(remainder, -1)
		if esc == "@" then 
			remainder = string.sub(remainder, 2)
			remainder = dcsCommon.trim(remainder)
		end
		
		if esc == "(" and last == ")" and string.len(remainder) > 2 then 
			-- note: iisues with startswith("(") ???
			remainder = string.sub(remainder, 2, -2)
			remainder = dcsCommon.trim(remainder)		
		end
		if esc == "\"" and last == "\"" and string.len(remainder) > 2 then 
			remainder = string.sub(remainder, 2, -2)
			remainder = dcsCommon.trim(remainder)		
		end
		if cfxZones.verbose then 
			trigger.action.outText("+++zne: accessing flag <" .. remainder .. ">", 30)
		end 
		rNum = cfxZones.getFlagValue(remainder, theZone)
	end 
	if rNum then 
		-- we have a comparison = ">", "=", "<" followed by a number 
		-- THEY TRIGGER EACH TIME lastVal <> currVal AND condition IS MET  
		if op == "=" then 
			return currVal == rNum and lastVal ~= currVal
		end
		
		if op == "#" or op == "~" then 
			return currVal ~= rNum and lastVal ~= currVal 
		end 
		
		if op == "<" then 
			return currVal < rNum and lastVal ~= currVal
		end
		
		if op == ">" then 
			return currVal > rNum and lastVal ~= currVal
		end
	end
	
	-- if we get here, we have an error 
	local zoneName = "<NIL>"
	if theZone then zoneName = theZone.name end 
	trigger.action.outText("+++Zne: illegal method constraints |" .. theMethod .. "| for zone " .. zoneName, 30 )
	return false 
end


function cfxZones.testZoneFlag(theZone, theFlagName, theMethod, latchName)
	-- returns two values: true/false method result, and curr value
	-- returns true if method constraints are met for flag theFlagName
	-- as defined by theMethod 
	if not theMethod then 
		theMethod = "change"
	end 
	
	-- will read and update theZone[latchName] as appropriate 
	if not theZone then 
		trigger.action.outText("+++Zne: no zone for testZoneFlag", 30)
		return nil, nil 
	end 
	if not theFlagName then 
		-- this is common, no error, only on verbose 
		if cfxZones.verbose then 
			trigger.action.outText("+++Zne: no flagName for zone " .. theZone.name .. " for testZoneFlag", 30)
		end 
		return nil, nil
	end
	if not latchName then 
		trigger.action.outText("+++Zne: no latchName for zone " .. theZone.name .. " for testZoneFlag", 30)
		return nil, nil 
	end
	-- get current value 
	local currVal = cfxZones.getFlagValue(theFlagName, theZone)
	
	-- get last value from latch
	local lastVal = theZone[latchName]
	if not lastVal then 
		trigger.action.outText("+++Zne: latch <" .. latchName .. "> not valid for zone " .. theZone.name, 30) -- intentional break here 
		return nil, nil
	end
	
	-- now, test by method 
	-- we should only test if currVal <> lastVal 
	if currVal == lastVal then
		return false, currVal
	end 
	
	--trigger.action.outText("+++Zne: about to test: c = " .. currVal .. ", l = " .. lastVal, 30)
	local testResult = cfxZones.testFlagByMethodForZone(currVal, lastVal, theMethod, theZone)

	-- update latch by method
	theZone[latchName] = currVal 

	-- return result
	return testResult, currVal
end



function cfxZones.flagArrayFromString(inString)
-- original code from RND flag
	if string.len(inString) < 1 then 
		trigger.action.outText("+++zne: empty flags", 30)
		return {} 
	end
	if cfxZones.verbose then 
		trigger.action.outText("+++zne: processing <" .. inString .. ">", 30)
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
				trigger.action.outText("+++zne: ignored range <" .. anElement .. "> (range)", 30)
			end
		else
			-- single number
			f = dcsCommon.trim(anElement) -- DML flag upgrade: accept strings tonumber(anElement)
			if f then 
				table.insert(flags, f)

			else 
				trigger.action.outText("+++zne: ignored element <" .. anElement .. "> (single)", 30)
			end
		end
	end
	if cfxZones.verbose then 
		trigger.action.outText("+++zne: <" .. #flags .. "> flags total", 30)
	end 
	return flags
end

--
-- PROPERTY PROCESSING 
--

function cfxZones.getAllZoneProperties(theZone, caseInsensitive) -- return as dict 
	if not caseInsensitive then caseInsensitive = false end 
	if not theZone then return {} end 
	
	local dcsProps = theZone.properties -- zone properties in dcs format 
	local props = {}
	-- dcs has all properties as array with values .key and .value 
	-- so convert them into a dictionary 
	for i=1, #dcsProps do 
		local theProp = dcsProps[i]
		local theKey = "dummy"
		if string.len(theProp.key) > 0 then theKey = theProp.key end 
		if caseInsensitive then theKey = theKey:upper() end 
		props[theKey] = theProp.value
	end
	return props 
end

function cfxZones.extractPropertyFromDCS(theKey, theProperties)
-- trim
	theKey = dcsCommon.trim(theKey) 
--	make lower case conversion if not case sensitive
	if not cfxZones.caseSensitiveProperties then 
		theKey = string.lower(theKey)
	end

-- iterate all keys and compare to what we are looking for 	
	for i=1, #theProperties do
		local theP = theProperties[i]
		 
		local existingKey = dcsCommon.trim(theP.key)  
		if not cfxZones.caseSensitiveProperties then 
			existingKey = string.lower(existingKey)
		end
		if existingKey == theKey then 
			return theP.value
		end
		
		-- now check after removing all blanks 
		existingKey = dcsCommon.removeBlanks(existingKey)
		if existingKey == theKey then 
			return theP.value
		end
	end
	return nil 
end

function cfxZones.getZoneProperty(cZone, theKey)
	if not cZone then 
		trigger.action.outText("+++zone: no zone in getZoneProperty", 30)
--		breek.here.noew = 1
		return nil
	end 
	if not theKey then 
		trigger.action.outText("+++zone: no property key in getZoneProperty for zone " .. cZone.name, 30)
--		breakme.here = 1
		return 
	end	

	local props = cZone.properties
	local theVal = cfxZones.extractPropertyFromDCS(theKey, props)
	return theVal
end

function cfxZones.getStringFromZoneProperty(theZone, theProperty, default)
	
	if not default then default = "" end
	local p = cfxZones.getZoneProperty(theZone, theProperty)
	if not p then return default end
	if type(p) == "string" then 
		p = dcsCommon.trim(p)
		if p == "" then p = default end 
		return p
	end
	return default -- warning. what if it was a number first?
end

function cfxZones.getMinMaxFromZoneProperty(theZone, theProperty)
	local p = cfxZones.getZoneProperty(theZone, theProperty)
	local theNumbers = dcsCommon.splitString(p, " ")

	return tonumber(theNumbers[1]), tonumber(theNumbers[2])
	
end

function cfxZones.randomInRange(minVal, maxVal)
	if maxVal < minVal then 
		local t = minVal
		minVal = maxVal 
		maxVal = t
	end
	return cfxZones.randomDelayFromPositiveRange(minVal, maxVal)
end

function cfxZones.randomDelayFromPositiveRange(minVal, maxVal) 
	if not maxVal then return minVal end 
	if not minVal then return maxVal end 
	local delay = maxVal
	if minVal > 0 and minVal < delay then 
		-- we want a randomized from time from minTime .. delay
		local varPart = delay - minVal + 1
		varPart = dcsCommon.smallRandom(varPart) - 1
		delay = minVal + varPart
	end
	return delay 
end

function cfxZones.getPositiveRangeFromZoneProperty(theZone, theProperty, default)
	-- reads property as string, and interprets as range 'a-b'. 
	-- if not a range but single number, returns both for upper and lower 
	--trigger.action.outText("***Zne: enter with <" .. theZone.name .. ">: range for property <" .. theProperty .. ">!", 30)
	if not default then default = 0 end 
	local lowerBound = default
	local upperBound = default 
	
	local rangeString = cfxZones.getStringFromZoneProperty(theZone, theProperty, "")
	if dcsCommon.containsString(rangeString, "-") then 
		local theRange = dcsCommon.splitString(rangeString, "-")
		lowerBound = theRange[1]
		lowerBound = tonumber(lowerBound)
		upperBound = theRange[2]
		upperBound = tonumber(upperBound)
		if lowerBound and upperBound then
			-- swap if wrong order
			if lowerBound > upperBound then 
				local temp = upperBound
				upperBound = lowerBound
				lowerBound = temp 
			end
--			if rndFlags.verbose then 
--			trigger.action.outText("+++Zne: detected range <" .. lowerBound .. ", " .. upperBound .. ">", 30)
--			end
		else
			-- bounds illegal
			trigger.action.outText("+++Zne: illegal range  <" .. rangeString .. ">, using " .. default .. "-" .. default, 30)
			lowerBound = default
			upperBound = default 
		end
	else 
		upperBound = cfxZones.getNumberFromZoneProperty(theZone, theProperty, default) -- between pulses 
		lowerBound = upperBound
	end
--	trigger.action.outText("+++Zne: returning <" .. lowerBound .. ", " .. upperBound .. ">", 30)
	return lowerBound, upperBound
end

function cfxZones.hasProperty(theZone, theProperty) 
	local foundIt = cfxZones.getZoneProperty(theZone, theProperty)
	if not foundIt then 
		-- check for possible forgotten or exchanged IO flags 
		if string.sub(theProperty, -1) == "?" then
			local lessOp = theProperty:sub(1,-2)
			if cfxZones.getZoneProperty(theZone, lessOp) ~= nil then 
				trigger.action.outText("*** NOTE: " .. theZone.name .. "'s property <" .. lessOp .. "> may be missing a Query ('?') symbol", 30)
			end
			local lessPlus = lessOp .. "!"
			if cfxZones.getZoneProperty(theZone, lessPlus) ~= nil then 
				trigger.action.outText("*** NOTE: " .. theZone.name .. "'s property <" .. lessOp .. "> may be using '!' instead of '?' for input", 30)
			end
			return false 
		end
		
		if string.sub(theProperty, -1) == "!" then 
			local lessOp = theProperty:sub(1,-2)
			if cfxZones.getZoneProperty(theZone, lessOp) ~= nil then 
				trigger.action.outText("*** NOTE: " .. theZone.name .. "'s property <" .. lessOp .. "> may be missing a Bang! ('!') symbol", 30)
			end
			local lessPlus = lessOp .. "?"
			if cfxZones.getZoneProperty(theZone, lessPlus) ~= nil then 
				trigger.action.outText("*** NOTE: " .. theZone.name .. "'s property <" .. lessOp .. "> may be using '!' instead of '?' for input", 30)
			end
			return false 
		end
		
		if string.sub(theProperty, -1) == ":" then 
			local lessOp = theProperty:sub(1,-2)
			if cfxZones.getZoneProperty(theZone, lessOp) ~= nil then 
				trigger.action.outText("*** NOTE: " .. theZone.name .. "'s property <" .. lessOp .. "> may be missing a colon (':') at end", 30)
			end
			return false 
		end
		
		return false 
	end
	return true 
--	return foundIt ~= nil 
end

function cfxZones.getBoolFromZoneProperty(theZone, theProperty, defaultVal)
	if not defaultVal then defaultVal = false end 
	if type(defaultVal) ~= "boolean" then 
		defaultVal = false 
	end

	if not theZone then 
		trigger.action.outText("WARNING: NIL Zone in getBoolFromZoneProperty", 30)
		return defaultVal
	end


	local p = cfxZones.getZoneProperty(theZone, theProperty)
	if not p then return defaultVal end

	-- make sure we compare so default always works when 
	-- answer isn't exactly the opposite
	p = p:lower() 
	p = dcsCommon.trim(p) 
	if defaultVal == false then 
		-- only go true if exact match to yes or true 
		theBool = false 
		theBool = (p == 'true') or (p == 'yes') or p == "1"
		return theBool
	end
	
	local theBool = true 
	-- only go false if exactly no or false or "0"
	theBool = (p ~= 'false') and (p ~= 'no') and (p ~= "0") 
	return theBool
end

function cfxZones.getCoalitionFromZoneProperty(theZone, theProperty, default)
	if not default then default = 0 end
	local p = cfxZones.getZoneProperty(theZone, theProperty)
	if not p then return default end  
	if type(p) == "number" then -- can't currently really happen
		if p == 1 then return 1 end 
		if p == 2 then return 2 end 
		return 0
	end
	
	if type(p) == "string" then 
		if p == "1" then return 1 end 
		if p == "2" then return 2 end 
		if p == "0" then return 0 end 
		
		p = p:lower()
		
		if p == "red" then return 1 end 
		if p == "blue" then return 2 end 
		if p == "neutral" then return 0 end
		if p == "all" then return 0 end 
		return default 
	end
	
	return default 
end

function cfxZones.getNumberFromZoneProperty(theZone, theProperty, default)
--TODO: trim string 
	if not default then default = 0 end
	local p = cfxZones.getZoneProperty(theZone, theProperty)
	p = tonumber(p)
	if not p then return default else return p end
end

function cfxZones.getVectorFromZoneProperty(theZone, theProperty, minDims, defaultVal)
	if not minDims then minDims = 0 end 
	if not defaultVal then defaultVal = 0 end 
	local s = cfxZones.getStringFromZoneProperty(theZone, theProperty, "")
	local sVec = dcsCommon.splitString(s, ",")
	local nVec = {}
	for idx, numString in pairs (sVec) do 
		local n = tonumber(numString)
		if not n then n = defaultVal end
		table.insert(nVec, n)
	end
	-- make sure vector contains at least minDims values 
	while #nVec < minDims do 
		table.insert(nVec, defaultVal)
	end
	
	return nVec 
end

function cfxZones.getSmokeColorStringFromZoneProperty(theZone, theProperty, default) -- smoke as 'red', 'green', or 1..5
	if not default then default = "red" end 
	local s = cfxZones.getStringFromZoneProperty(theZone, theProperty, default)
	s = s:lower()
	s = dcsCommon.trim(s)
	-- check numbers 
	if (s == "0") then return "green" end
	if (s == "1") then return "red" end
	if (s == "2") then return "white" end
	if (s == "3") then return "orange" end
	if (s == "4") then return "blue" end
	
	if s == "green" or
	   s == "red" or
	   s == "white" or
	   s == "orange" or
	   s == "blue" then return s end

	return default 
end

--
-- Moving Zones. They contain a link to their unit
-- they are always located at an offset (x,z) or delta, phi 
-- to their master unit. delta phi allows adjustment for heading
-- The cool thing about moving zones in cfx is that they do not
-- require special handling, they are always updated 
-- and work with 'pointinzone' etc automatically

-- Always works on cfx Zones, NEVER on DCS zones.
--
-- requires that readFromDCS has been done
--
function cfxZones.getDCSOrigin(aZone)
	local o = {}
	o.x = aZone.dcsOrigin.x
	o.y = 0
	o.z = aZone.dcsOrigin.z 
	return o
end

function cfxZones.getPoint(aZone) -- always works, even linked, returned point can be reused 
	if aZone.linkedUnit then 
		local theUnit = aZone.linkedUnit
		-- has a link. is link existing?
		if theUnit:isExist() then 
			-- updates zone position 
			cfxZones.centerZoneOnUnit(aZone, theUnit)
			local dx = aZone.dx
			local dy = aZone.dy
			if aZone.useHeading then 
				dx, dy = cfxZones.calcHeadingOffset(aZone, theUnit)
			end
			cfxZones.offsetZone(aZone, dx, dy)
		end
	end
	local thePos = {}
	thePos.x = aZone.point.x
	thePos.y = 0 -- aZone.y 
	thePos.z = aZone.point.z
	--[[--
	if aZone.linkedUnit then 
		trigger.action.outText("GetPoint: LINKED <".. aZone.name .. "> p = " .. dcsCommon.point2text(thePos) .. ", O = " .. dcsCommon.point2text(cfxZones.getDCSOrigin(aZone)), 30  )
	else 
		trigger.action.outText("GetPoint: unlinked <".. aZone.name .. "> p = " .. dcsCommon.point2text(thePos) .. ", O = " .. dcsCommon.point2text(cfxZones.getDCSOrigin(aZone)), 30  )
	end
	--]]--
	return thePos 
end

function cfxZones.linkUnitToZone(theUnit, theZone, dx, dy) -- note: dy is really Z, don't get confused!!!!
	theZone.linkedUnit = theUnit
	if not dx then dx = 0 end
	if not dy then dy = 0 end 
	theZone.dx = dx
	theZone.dy = dy 
	theZone.rxy = math.sqrt(dx * dx + dy * dy) -- radius 
	local unitHeading = dcsCommon.getUnitHeading(theUnit)
	local bearingOffset = math.atan2(dy, dx) -- rads 
	if bearingOffset < 0 then bearingOffset = bearingOffset + 2 * 3.141592 end 
	--trigger.action.outText("zone <" .. theZone.name .. "> is <" .. math.floor(bearingOffset * 57.2958) .. "> degrees from Unit <" .. theUnit:getName() .. ">", 30)
	--trigger.action.outText("Unit <" .. theUnit:getName() .. "> has heading .. <" .. math.floor(57.2958 * unitHeading) .. ">", 30)
	local dPhi = bearingOffset - unitHeading
	if dPhi < 0 then dPhi = dPhi + 2 * 3.141592 end
	if (theZone.verbose and theZone.useHeading) then 
		trigger.action.outText("Zone is at <" .. math.floor(57.2958 * dPhi) .. "> relative to unit heading", 30)
	end
	theZone.dPhi = dPhi -- constant delta between unit heading and 
	-- direction to zone 
	theZone.uHdg = unitHeading -- original unit heading to turn other 
	-- units if need be 
	--trigger.action.outText("Link setup: dx=<" .. dx .. ">, dy=<" .. dy .. "> unit original hdg = <" .. math.floor(57.2958 * unitHeading)  .. ">", 30)
end

function cfxZones.zonesLinkedToUnit(theUnit) -- returns all zones linked to this unit 
	if not theUnit then return {} end 
	local linkedZones = {}
	for idx, theZone in pairs (cfxZones.zones) do 
		if theZone.linkedUnit == theUnit then 
			table.insert(linkedZones, theZone)
		end
	end
	return linkedZones
end

function cfxZones.calcHeadingOffset(aZone, theUnit)
	-- recalc dx and dy based on ry and current heading 
	-- since 0 degrees is [0,1] = [0,r] the calculation of 
	-- rotated coords can be simplified from 
	-- xr = x cos phi - y sin phi = -r sin phi
	-- yr = y cos phi + x sin phi = r cos phi 
	local unitHeading = dcsCommon.getUnitHeading(theUnit)
	-- add heading offset 
	local zoneBearing = unitHeading + aZone.dPhi 
	if zoneBearing > 2 * 3.141592 then zoneBearing = zoneBearing - 2 * 3.141592 end 
					
	-- in DCS, positive x is north (wtf?) and positive z is east 
	local dy = (-aZone.rxy) * math.sin(zoneBearing)
	local dx = aZone.rxy * math.cos(zoneBearing)
	
	--trigger.action.outText("zone bearing is " .. math.floor(zoneBearing * 57.2958) .. " dx = <" .. dx .. "> , dy = <" .. dy .. ">", 30)
	return dx, -dy -- note: dy is z coord!!!!
end

function cfxZones.updateMovingZones()
	cfxZones.updateSchedule = timer.scheduleFunction(cfxZones.updateMovingZones, {}, timer.getTime() + 1/cfxZones.ups)
	-- simply scan all cfx zones for the linkedUnit property and if there
	-- update the zone's points
	for aName,aZone in pairs(cfxZones.zones) do
		if aZone.linkBroken then 
			-- try to relink 
			cfxZones.initLink(aZone)
		end
		if aZone.linkedUnit then 
			local theUnit = aZone.linkedUnit
			-- has a link. is link existing?
			if theUnit:isExist() then 
				cfxZones.centerZoneOnUnit(aZone, theUnit)
				local dx = aZone.dx 
				local dy = aZone.dy -- this is actually z 
				if aZone.useHeading then 
					dx, dy = cfxZones.calcHeadingOffset(aZone, theUnit)
				end
				cfxZones.offsetZone(aZone, dx, dy)
			else 
				-- we lost link 
				aZone.linkBroken = true 
				aZone.linkedUnit = nil 
			end
		end
	end
end

function cfxZones.initLink(theZone)
	theZone.linkBroken = true 
	theZone.linkedUnit = nil 
	theUnit = Unit.getByName(theZone.linkName)
	if theUnit then
		local dx = 0
		local dz = 0
		if theZone.useOffset or theZone.useHeading then 
			local delta = dcsCommon.vSub(cfxZones.getDCSOrigin(theZone),theUnit:getPoint()) -- delta = B - A 
			dx = delta.x 
			dz = delta.z
		end
		cfxZones.linkUnitToZone(theUnit, theZone, dx, dz) -- also sets theZone.linkedUnit
		if theZone.verbose then 
			trigger.action.outText("Link established for zone <" .. theZone.name .. "> to unit <" .. theZone.linkName .. ">: dx=<" .. math.floor(dx) .. ">, dz=<" .. math.floor(dz) .. "> dist = <" .. math.floor(math.sqrt(dx * dx + dz * dz)) .. ">" , 30)
		end 
		theZone.linkBroken = nil 
	else 
		if theZone.verbose then 
			trigger.action.outText("Linked unit: no unit <" .. theZone.linkName .. "> to link <" .. theZone.name .. "> to", 30)
		end
	end
end

function cfxZones.startMovingZones()
	-- read all zoness, and look for a property called 'linkedUnit'
	-- which will make them a linked zone if there is a unit that exists
	-- also suppors 'useOffset' and 'useHeading'
	for aName,aZone in pairs(cfxZones.zones) do
		local lU = nil 
		if cfxZones.hasProperty(aZone, "linkedUnit") then 
			lU = cfxZones.getZoneProperty(aZone, "linkedUnit")
		end
		if lU then 
			aZone.linkName = lU
			aZone.useOffset = cfxZones.getBoolFromZoneProperty(aZone, "useOffset", false)
			aZone.useHeading = cfxZones.getBoolFromZoneProperty(aZone, "useHeading", false)
			
			cfxZones.initLink(aZone)
--[[--			
			-- this zone is linked to a unit
			theUnit = Unit.getByName(lU)
			local useOffset = cfxZones.getBoolFromZoneProperty(aZone, "useOffset", false)
			if useOffset then aZone.useOffset = true end
			local useHeading = cfxZones.getBoolFromZoneProperty(aZone, "useHeading")
			if useHeading then aZone.useHeading = true end 
			if theUnit then
				local dx = 0
				local dz = 0
				if useOffset or useHeading then 
					local delta = dcsCommon.vSub(aZone.point,theUnit:getPoint()) -- delta = B - A 
					dx = delta.x 
					dz = delta.z
				end
				cfxZones.linkUnitToZone(theUnit, aZone, dx, dz)
				--trigger.action.outText("Link setup: dx=<" .. dx .. ">, dz=<" .. dz .. ">", 30)
				if useOffset then 
				end
			else 
				trigger.action.outText("Linked unit: no unit to link <" .. aZone.name .. "> to", 30)
			end
--]]--
		end
		-- support for zone-local verbose flag 
		aZone.verbose = cfxZones.getBoolFromZoneProperty(aZone, "verbose", false)
	end
end

--
-- init
--

function cfxZones.init()
	-- read all zones into my own db
	cfxZones.readFromDCS(true) -- true: erase old
	
	-- now, pre-read zone owner for all zones
	-- note, all zones with this property are by definition owned zones.
	-- and hence will be read anyway. this will merely ensure that the 
	-- ownership is established right away
	-- unless owned zones module is missing, in which case 
	-- ownership is still established 
	local pZones = cfxZones.zonesWithProperty("owner")
	for n, aZone in pairs(pZones) do
		aZone.owner = cfxZones.getCoalitionFromZoneProperty(aZone, "owner", 0)
	end
		
	
	-- now initialize moving zones
	cfxZones.startMovingZones()
	cfxZones.updateMovingZones() -- will auto-repeat
	
	trigger.action.outText("cf/x Zones v".. cfxZones.version .. ": loaded, zones:" .. dcsCommon.getSizeOfTable(cfxZones.zones), 30)

end

-- get everything rolling
cfxZones.init()
