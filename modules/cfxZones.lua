-- cf/x zone management module
-- reads dcs zones and makes them accessible and mutable 
-- by scripting.
--
-- Copyright (c) 2021, 2022 by Christian Franz and cf/x AG
--

cfxZones = {}
cfxZones.version = "2.5.1"
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
 
--]]--
cfxZones.verbose = true
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

	-- we only retrive the data we need. At this point it is name, location and radius
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

function cfxZones.isPointInsideZone(thePoint, theZone)
	local p = {x=thePoint.x, y = 0, z = thePoint.z} -- zones have no altitude
	if (theZone.isCircle) then 
		local d = dcsCommon.dist(p, theZone.point)
		return d < theZone.radius
	end 
	
	if (theZone.isPoly) then 
		return (cfxZones.isPointInsidePoly(p, theZone.poly))
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
function cfxZones.groupsOfCoalitionPartiallyInZone(coal, theZone, categ) -- categ is optional
	local groupsInZone = {}
	local allGroups = coalition.getGroups(coal, categ)
	for key, group in pairs(allGroups) do -- iterate all groups
		if group:isExist() then
			
			
			if cfxZones.isGroupPartiallyInZone(group, theZone) then
				
				table.insert(groupsInZone, group)
			else 
				
			
			end
		end
	end
	return groupsInZone
end

function cfxZones.isGroupPartiallyInZone(aGroup, aZone)
	if not aGroup then return false end 
	if not aZone then return false end 
	
	
	-- needs to be implemented
	if not aGroup:isExist() then return false end 
	local allUnits = aGroup:getUnits()
	for uk, aUnit in pairs (allUnits) do 
		if aUnit:isExist() and aUnit:getLife() > 1 then 
		
			local p = aUnit:getPoint()
--			p.y = 0 -- zones have no altitude
			-- modification of isPointInsideZone now takes care of this
			if cfxZones.isPointInsideZone(p, aZone) then 			
				return true
			else 
						
			end 
		end
	end
	return false
end

function cfxZones.isEntireGroupInZone(aGroup, aZone)
	if not aGroup then return false end 
	if not aZone then return false end 
	-- needs to be implemented
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
	local currDelta = math.huge 
	local closestZone = nil
	for zName, zData in pairs(theZones) do 
		local zPoint = cfxZones.getPoint(zData)
		local delta = dcsCommon.dist(point, zPoint)
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
function cfxZones.pointInZone(thePoint, theZone)
	if not (theZone) then return false, 0, 0 end
		
	local pflat = {x = thePoint.x, y = 0, z = thePoint.z}
	
	local zpoint = cfxZones.getPoint(theZone) -- updates zone if linked 
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
	return coalition.addGroup(theSideCJTF, Group.Category.GROUND, theGroup)

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
--	make lower case conversion if not case sensitive
	if not cfxZones.caseSensitiveProperties then 
		theKey = string.lower(theKey)
	end

-- iterate all keys and compare to what we are looking for 	
	for i=1, #theProperties do
		local theP = theProperties[i]
		local existingKey = theP.key 
		if not cfxZones.caseSensitiveProperties then 
			existingKey = string.lower(existingKey)
		end
		if existingKey == theKey then 
			return theP.value
		end
	end
	return nil 
end

function cfxZones.getZoneProperty(cZone, theKey)
	if not cZone then 
		trigger.action.outText("+++zone: no zone in getZoneProperty", 30)
		return nil
	end 
	if not theKey then 
		trigger.action.outText("+++zone: no property key in getZoneProperty for zone " .. cZone.name, 30)
		breakme.here = 1
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

function cfxZones.hasProperty(theZone, theProperty) 
	return cfxZones.getZoneProperty(theZone, theProperty) ~= nil 
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
function cfxZones.getPoint(aZone) -- always works, wven linked, point can be reused 
	if aZone.linkedUnit then 
		local theUnit = aZone.linkedUnit
		-- has a link. is link existing?
		if theUnit:isExist() then 
			-- updates zone position 
			cfxZones.centerZoneOnUnit(aZone, theUnit)
			cfxZones.offsetZone(aZone, aZone.dx, aZone.dy)
		end
	end
	local thePos = {}
	thePos.x = aZone.point.x
	thePos.y = 0 -- aZone.y 
	thePos.z = aZone.point.z
	return thePos 
end

function cfxZones.linkUnitToZone(theUnit, theZone, dx, dy) -- note: dy is really Z, don't get confused!!!!
	theZone.linkedUnit = theUnit
	if not dx then dx = 0 end
	if not dy then dy = 0 end 
	theZone.dx = dx
	theZone.dy = dy 
end

function cfxZones.updateMovingZones()
	cfxZones.updateSchedule = timer.scheduleFunction(cfxZones.updateMovingZones, {}, timer.getTime() + 1/cfxZones.ups)
	-- simply scan all cfx zones for the linkedUnit property and if there
	-- update the zone's points
	for aName,aZone in pairs(cfxZones.zones) do
		if aZone.linkedUnit then 
			local theUnit = aZone.linkedUnit
			-- has a link. is link existing?
			if theUnit:isExist() then 
				cfxZones.centerZoneOnUnit(aZone, theUnit)
				cfxZones.offsetZone(aZone, aZone.dx, aZone.dy)
				--trigger.action.outText("cf/x zones update " .. aZone.name, 30)
			end
		end
	end
end

function cfxZones.startMovingZones()
	-- read all zoness, and look for a property called 'linkedUnit'
	-- which will make them a linked zone if there is a unit that exists
	for aName,aZone in pairs(cfxZones.zones) do
		local lU = cfxZones.getZoneProperty(aZone, "linkedUnit")
		if lU then 
			-- this zone is linked to a unit
			theUnit = Unit.getByName(lU)
			local useOffset = cfxZones.getBoolFromZoneProperty(aZone, "useOffset", false)
			if useOffset then aZone.useOffset = true end
			if theUnit then
				local dx = 0
				local dz = 0
				if useOffset then 
					local delta = dcsCommon.vSub(aZone.point,theUnit:getPoint()) -- delta = B - A 
					dx = delta.x 
					dz = delta.z
				end
				cfxZones.linkUnitToZone(theUnit, aZone, dx, dz)
				--trigger.action.outText("cf/x zones: linked " .. aZone.name .. " to " .. theUnit:getName(), 30)
				if useOffset then 
					--trigger.action.outText("and dx = " .. dx .. " dz = " .. dz, 30)
				end
			end
 
		end
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
	local pZones = cfxZones.zonesWithProperty("owner")
	for n, aZone in pairs(pZones) do
		aZone.owner = cfxZones.getCoalitionFromZoneProperty(aZone, "owner", 0)
	end
		
	
	-- now initialize moving zones
	cfxZones.startMovingZones()
	cfxZones.updateMovingZones() -- will auto-repeat
	
	trigger.action.outText("cf/x Zones v".. cfxZones.version .. ": loaded", 10)
end

-- get everything rolling
cfxZones.init()
