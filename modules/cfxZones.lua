cfxZones = {}
cfxZones.version = "4.0.9"

-- cf/x zone management module
-- reads dcs zones and makes them accessible and mutable 
-- by scripting.
--
-- Copyright (c) 2021 - 2023 by Christian Franz and cf/x AG
--

--[[-- VERSION HISTORY
- 3.0.0   - support for DCS 2.8 linkUnit attribute, integration with 
            linedUnit and warning.
		  - initZoneVerbosity()
- 3.0.1   - updateMovingZones() better tracks linked units by name
- 3.0.2   - maxRadius for all zones, only differs from radius in polyZones 
          - re-factoring zone-base string processing from messenger module
		  - new processStringWildcards() that does almost all that messenger can 
- 3.0.3   - new getLinkedUnit()
- 3.0.4   - new createRandomPointOnZoneBoundary()
- 3.0.5   - getPositiveRangeFromZoneProperty() now also supports upper bound (optional)
- 3.0.6   - new createSimplePolyZone()
		  - new createSimpleQuadZone()
- 3.0.7   - getPoint() can also get land y when passing true as second param
- 3.0.8   - new cfxZones.pointInOneOfZones(thePoint, zoneArray, useOrig) 
- 3.0.9   - new getFlareColorStringFromZoneProperty()
- 3.1.0	  - new getRGBVectorFromZoneProperty()
			new getRGBAVectorFromZoneProperty()
- 3.1.1   - getRGBAVectorFromZoneProperty now supports #RRGGBBAA and #RRGGBB format 
          - owner for all, default 0 
- 3.1.2   - getAllZoneProperties has numbersOnly option 
- 3.1.3   - new numberArrayFromString()
		  - new declutterZone()
		  - new getZoneVolume()
		  - offsetZone also updates zone bounds when moving zones 
		  - corrected bug in calculateZoneBounds()
- 4.0.0   - dmlZone OOP API started 
		  - code revision / refactoring 
		  - moved createPoint and copxPoint to dcsCommon, added bridging code 
		  - re-routed all createPoint() invocations to dcsCommon 
		  - removed anyPlayerInZone() because of cfxPlayer dependency
		  - numberArrayFromString() moved to dcsCommon, bridged 
		  - flagArrayFromString() moved to dcsCommon, bridged 
		  - doPollFlag() can differentiate between number method and string method 
		    to enable passing an immediate negative value 
		  - getNumberFromZoneProperty() enforces number return even on default
		  - immediate method switched to preceeding '#', to resolve conflict witzh 
		    negative numbers, backwards compatibility with old (dysfunctional) method 
- 4.0.1   - dmlZone:getName()
- 4.0.2   - removed verbosity from declutterZone (both versions)
- 4.0.3   - new processDynamicVZU()
	      - wildcard uses processDynamicVZU
- 4.0.4   - setFlagValue now supports multiple flags (OOP and classic)
		  - doSetFlagValue optimizations 
- 4.0.5   - dynamicAB wildcard 
		  - processDynamicValueVU
- 4.0.6   - hash mark forgotten QoL
- 4.0.7   - drawZone()
- 4.0.8   - markZoneWithObjects()
		  - cleanup 
		  - markCenterWithObject
		  - markPointWithObject
- 4.0.9   - createPolyZone now correctly returns new zone 
		  - createSimplePolyZone correctly passes location to createPolyZone 
		  - createPolyZone now correctly sets zone.point
		  - createPolyZone now correctly inits dcsOrigin
		  - createCircleZone noew correctly inits dcsOrigin
--]]--

--
-- ====================
-- OOP dmlZone API HERE
-- ====================
--

dmlZone = {}
function dmlZone:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	self.name = "dmlZone raw"
	self.isCircle = false
	self.isPoly = false
	self.radius = 0
	self.poly = {}
	self.bounds = {}
	self.properties = {}
	return o 
end 

--
-- CLASSIC INTERFACE
--
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
			local newZone = dmlZone:new(nil) -- WAS: {} -- OOP introduction July 2023
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
			-- WARNING: zones locs are 2D (x,y) pairs, while y in DCS is altitude.
			--          so we need to change (x,y) into (x, 0, z). Since Zones have no
			--          altitude (they are an infinite cylinder) this works. Remember to 
			--          drop y from zone calculations to see if inside. 
			-- WARNING: ME linked zones have a relative x any y 
			--          to the linked unit 
			if dcsZone.linkUnit then 
				-- calculate the zone's real position by accessing the unit's MX data 
				-- as precached by dcsCommon
				local ux, uy = dcsCommon.getUnitStartPosByID(dcsZone.linkUnit)
				newZone.point = dcsCommon.createPoint(ux + dcsZone.x, 0, uy + dcsZone.y)
				newZone.dcsOrigin = dcsCommon.createPoint(ux + dcsZone.x, 0, uy + dcsZone.y)
			else 
				newZone.point = dcsCommon.createPoint(dcsZone.x, 0, dcsZone.y)
				newZone.dcsOrigin = dcsCommon.createPoint(dcsZone.x, 0, dcsZone.y)
			end

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
				newZone.maxRadius = newZone.radius -- same for circular
	
			elseif zoneType == 2 then
				-- polyZone
				newZone.isPoly = true 
				newZone.radius = dcsZone.radius -- radius is still written in DCS, may change later. The radius has no meaning and is the last radius written before zone changed to poly.
				-- note that newZone.point is only inside the tone for 
				-- convex polys, and DML only correctly works with convex polys
				-- now transfer all point in the poly
				-- note: DCS in 2.7 misspells vertices as 'verticies'
				-- correct for this 
				newZone.maxRadius = 0
				local verts = {}
				if dcsZone.verticies then verts = dcsZone.verticies 
				else 
					-- in later versions, this was corrected
					verts = dcsZone.vertices -- see if this is ever called
				end
				
				for v=1, #verts do
					local dcsPoint = verts[v]
					local polyPoint = cfxZones.createPointFromDCSPoint(dcsPoint) -- (x, y) --> (x, 0, y-->z)
					newZone.poly[v] = polyPoint
					-- measure distance from zone's point, and store maxRadius 
					-- dcs always saves a point with the poly zone 
					local dist = dcsCommon.dist(newZone.point, polyPoint)
					if dist > newZone.maxRadius then newZone.maxRadius = dist end 
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
		bounds.ul = dcsCommon.createPoint(center.x - radius, 0, center.z - radius)
		bounds.ur = dcsCommon.createPoint(center.x + radius, 0, center.z - radius)
		bounds.ll = dcsCommon.createPoint(center.x - radius, 0, center.z + radius)
		bounds.lr = dcsCommon.createPoint(center.x + radius, 0, center.z + radius)
		
	elseif theZone.isPoly then
		local poly = theZone.poly -- ref copy!
		-- create the four points
		local ll = cfxZones.createPointFromPoint(poly[1])
		local lr = cfxZones.createPointFromPoint(poly[1])
		local ul = cfxZones.createPointFromPoint(poly[1])
		local ur = cfxZones.createPointFromPoint(poly[1])
		
		local pRad = dcsCommon.dist(theZone.point, poly[1]) -- rRad is radius for polygon from theZone.point 
		
		-- now iterate through all points and adjust bounds accordingly 
		for v=2, #poly do 
			local vertex = poly[v]
			if (vertex.x < ll.x) then ll.x = vertex.x; ul.x = vertex.x end 
			if (vertex.x > lr.x) then lr.x = vertex.x; ur.x = vertex.x end 
			if (vertex.z < ul.z) then ul.z = vertex.z; ur.z = vertex.z end
			--if (vertex.z > ll.z) then ll.z = vertex.z; lr.z = vertex.z end
			if (vertex.z > ur.z) then ur.z = vertex.z; ul.z = vertex.z end 			
			local dp = dcsCommon.dist(theZone.point, vertex)
			if dp > pRad then pRad = dp end -- find largst distance to vertex
		end
		
		-- now keep the new point references
		-- and store them in the zone's bounds
		bounds.ll = ll
		bounds.lr = lr
		bounds.ul = ul
		bounds.ur = ur 
		-- we may need to ascertain why we need ul, ur, ll, lr instead of just ll and ur 
		-- store pRad 
		theZone.pRad = pRad -- not sure we'll ever need that, but at least we have it

	else 
		-- huston, we have a problem
		if cfxZones.verbose then 
			trigger.action.outText("cf/x zones: calc bounds: zone " .. theZone.name .. " has unknown type", 30)
		end
	end
	
end

function dmlZone:calculateZoneBounds()
	cfxZones.calculateZoneBounds(self)
end 

function cfxZones.createPoint(x, y, z)  -- bridge to dcsCommon, backward comp.
	return dcsCommon.createPoint(x, y, z) 
end

function cfxZones.copyPoint(inPoint) -- bridge to dcsCommon, backward comp.
	return dcsCommon.copyPoint(inPoint)
end

function cfxZones.createHeightCorrectedPoint(inPoint) -- this should be in dcsCommon
	local cP = dcsCommon.createPoint(inPoint.x, land.getHeight({x=inPoint.x, y=inPoint.z}),inPoint.z)
	return cP
end

function cfxZones.getHeightCorrectedZonePoint(theZone)
	local thePoint = cfxZone.getPoint(theZone)
	return cfxZones.createHeightCorrectedPoint(thePoint)
end

function dmlZone:getHeightCorrectedZonePoint()
	local thePoint = self:getPoint()
	return dcsCommon.createPoint(thePoint.x, land.getHeight({x=thePoint.x, y=thePoint.z}),thePoint.z)
end

function cfxZones.createPointFromPoint(inPoint)
	return cfxZones.copyPoint(inPoint)
end

function cfxZones.createPointFromDCSPoint(inPoint) 
	return dcsCommon.createPoint(inPoint.x, 0, inPoint.y)
end


function cfxZones.createRandomPointInsideBounds(bounds)
	-- warning: bounds do not move woth zone! may have to be updated
	local x = math.random(bounds.ll.x, ur.x)
	local z = math.random(bounds.ll.z, ur.z)
	return dcsCommon.createPoint(x, 0, z)
end

function cfxZones.createRandomPointOnZoneBoundary(theZone)
	if not theZone then return nil end 
	if theZone.isPoly then 
		local loc, dx, dy = cfxZones.createRandomPointInPolyZone(theZone, true)
		return loc, dx, dy 
	else 
		local loc, dx, dy = cfxZones.createRandomPointInCircleZone(theZone, true)
		return loc, dx, dy 
	end
end

function dmlZone:createRandomPointOnZoneBoundary()
	return cfxZones.createRandomPointOnZoneBoundary(self)
end 

function cfxZones.createRandomPointInZone(theZone)
	if not theZone then return nil end 
	if theZone.isPoly then 
		local loc, dx, dy = cfxZones.createRandomPointInPolyZone(theZone)
		return loc, dx, dy 
	else 
		local loc, dx, dy = cfxZones.createRandomPointInCircleZone(theZone)
		return loc, dx, dy 
	end
end

function dmlZone:createRandomPointInZone()
	local loc, dx, dy = cfxZones.createRandomPointInZone(self)
	return loc, dx, dy
end 


function cfxZones.randomPointInZone(theZone)
	local loc, dx, dy =  cfxZones.createRandomPointInZone(theZone)
	return loc, dx, dy 
end

function dmlZone:randomPointInZone()
	local loc, dx, dy =  cfxZones.createRandomPointInZone(self)
	return loc, dx, dy 
end

function cfxZones.createRandomPointInCircleZone(theZone, onEdge)
	if not theZone.isCircle then 
		trigger.action.outText("+++Zones: warning - createRandomPointInCircleZone called for non-circle zone <" .. theZone.name .. ">", 30)
		return {x=theZone.point.x, y=0, z=theZone.point.z}
	end
	
	-- ok, let's first create a random percentage value for the new radius
	-- now lets get a random degree
	local degrees = math.random() * 2 * 3.14152 -- radiants. 
	local r = theZone.radius 
	if not onEdge then 
		r = r * math.random()
	end 
	local p = cfxZones.getPoint(theZone) -- force update of zone if linked
	local dx = r * math.cos(degrees)
	local dz = r * math.sin(degrees)
	local px = p.x + dx -- r * math.cos(degrees)
	local pz = p.z + dz -- r * math.sin(degrees)
	return {x=px, y=0, z = pz}, dx, dz -- returns loc and offsets to theZone.point
end

function dmlZone:createRandomPointInCircleZone(theZone, onEdge)
	local p, dx, dz = cfxZones.createRandomPointInCircleZone(self, onEdge)
	return p, dx, dz 
end 

function cfxZones.createRandomPointInPolyZone(theZone, onEdge)
	if not theZone.isPoly then 
		trigger.action.outText("+++Zones: warning - createRandomPointInPolyZone called for non-poly zone <" .. theZone.name .. ">", 30)
		return dcsCommon.createPoint(theZone.point.x, 0, theZone.point.z)
	end
	-- force update of all points 
	local p = cfxZones.getPoint(theZone)
	
	-- point in convex poly: choose two different lines from that polygon 
	local lineIdxA = dcsCommon.smallRandom(#theZone.poly)
	repeat lineIdxB = dcsCommon.smallRandom(#theZone.poly) until (lineIdxA ~= lineIdxB)
	
	-- we now have two different lines. pick a random point on each. 
	-- we use lerp to pick any point between a and b 
	local a = theZone.poly[lineIdxA]
	lineIdxA = lineIdxA + 1 -- get next point in poly and wrap around
	if lineIdxA > #theZone.poly then lineIdxA = 1 end 
	local b = theZone.poly[lineIdxA] 
	local randompercent = math.random()
	local sourceA = dcsCommon.vLerp (a, b, randompercent)
	-- if all we want is a point on an edge, we are done 
	if onEdge then 
		local polyPoint = sourceA
		return polyPoint, polyPoint.x - p.x, polyPoint.z - p.z -- return loc, dx, dz 
	end 
	
	-- now get point on second line 
	a = theZone.poly[lineIdxB]
	lineIdxB = lineIdxB + 1 -- get next point in poly and wrap around
	if lineIdxB > #theZone.poly then lineIdxB = 1 end 
	b = theZone.poly[lineIdxB] 
	randompercent = math.random()
	local sourceB = dcsCommon.vLerp (a, b, randompercent)
	
	-- now take a random point on that line that entirely 
	-- runs through the poly 
	randompercent = math.random()
	local polyPoint = dcsCommon.vLerp (sourceA, sourceB, randompercent)
	return polyPoint, polyPoint.x - p.x, polyPoint.z - p.z -- return loc, dx, dz 
end

function dmlZone:createRandomPointInPolyZone(onEdge)
	local p, dx, dz = cfxZones.createRandomPointInPolyZone(self, onEdge)
	return p, dx, dz 
end 

function cfxZones.addZoneToManagedZones(theZone)
	local upperName = string.upper(theZone.name) -- newZone.name:upper()
	cfxZones.zones[upperName] = theZone
end

function dmlZone:addZoneToManagedZones()
	local upperName = string.upper(self.name) -- newZone.name:upper()
	cfxZones.zones[upperName] = self
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
	local newZone = dmlZone:new(nil) -- {} OOP compatibility 
	newZone.isCircle = true
	newZone.isPoly = false
	newZone.poly = {}
	newZone.bounds = {}
			
	newZone.name = name
	newZone.radius = radius
	newZone.point = dcsCommon.createPoint(x, 0, z)
 	newZone.dcsOrigin = dcsCommon.createPoint(x, 0, z)

	-- props 
	newZone.properties = {}
	
	-- calculate my bounds
	cfxZones.calculateZoneBounds(newZone)
	
	return newZone
end

function cfxZones.createSimplePolyZone(name, location, points, addToManaged)
	if not addToManaged then addToManaged = false end 
	if not location then 
		location = {}
	end
	if not location.x then location.x = 0 end 
	if not location.z then location.z = 0 end 
	if not location.y then location.y = 0 end 

	local newZone = cfxZones.createPolyZone(name, points, location)
	
	if addToManaged then 
		cfxZones.addZoneToManagedZones(newZone)
	end
	return newZone
end

function cfxZones.createSimpleQuadZone(name, location, points, addToManaged)
	if not location then 
		location = {}
	end
	if not location.x then location.x = 0 end 
	if not location.z then location.z = 0 end 
		
	-- synthesize 4 points if they don't exist
	-- remember: in DCS positive x is up, positive z is right 
	if not points then 
		points = {} 
	end
	if not points[1] then 
		-- upper left 
		points[1] = {x = location.x-1, y = 0, z = location.z-1}
	end
	if not points[2] then 
		-- upper right 
		points[2] = {x = location.x-1, y = 0, z = location.z+1}
	end
	if not points[3] then 
		-- lower right 
		points[3] = {x = location.x+1, y = 0, z = location.z+1}
	end
	if not points[4] then 
		-- lower left 
		points[4] = {x = location.x+1, y = 0, z = location.z-1}
	end
	
	return cfxZones.createSimplePolyZone(name, location, points, addToManaged)
end

function cfxZones.createPolyZone(name, poly, location) -- poly must be array of point type
	local newZone = dmlZone:new(nil) -- {} OOP compatibility 
	if not location then location = {x=0, y=0, z=0} end 
	newZone.point = dcsCommon.createPoint(location.x, 0, location.z)
	newZone.dcsOrigin = dcsCommon.createPoint(location.x, 0, location.z)
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
	return newZone 
end

function cfxZones.createRandomZoneInZone(name, inZone, targetRadius, entirelyInside)
	-- create a new circular zone with center placed inside inZone
	-- if entirelyInside is false, only the zone's center is guaranteed to be inside
	-- inZone.
	-- entirelyInside is not guaranteed for polyzones
	
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
		local newPoint = cfxZones.createRandomPointInPolyZone(inZone)
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

function dmlZone:isPointInsideZone(thePoint, radiusIncrease) -- warning: param order!
	return cfxZones.isPointInsideZone(thePoint, self, radiusIncrease)
end 

-- isZoneInZone returns true if center of innerZone is inside  outerZone
function cfxZones.isZoneInsideZone(innerZone, outerZone) 
	local p = cfxZones.getPoint(innerZone)
	return cfxZones.isPointInsideZone(p, outerZone)	
end

function dmlZone:isZoneInsideZone(outerZone) 
	return cfxZones.isPointInsideZone(self:getPoint(), outerZone)	
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

function dmlZone:getAllZonesInsideZone(testZones)
	return cfxZones.getAllZonesInsideZone(self, testZones)
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
-- zone volume management
--

function cfxZones.getZoneVolume(theZone)
	if not theZone then return nil end 
	
	if (theZone.isCircle) then 
		-- create a sphere volume
		local p = cfxZones.getPoint(theZone)
		p.y = land.getHeight({x = p.x, y = p.z})
		local r = theZone.radius
		if r < 10 then r = 10 end 
		local vol = {
			id = world.VolumeType.SPHERE,
			params = {
				point = p,
				radius = r
			}
		}
		return vol 
	elseif (theZone.isPoly) then 
		-- build the box volume, using the zone's bounds ll and ur points 
		local lowerLeft = {}
		-- we build x = westerm y = southern, Z = alt 
		local alt = land.getHeight({x=theZone.bounds.ll.x, y = theZone.bounds.ll.z}) - 10
		lowerLeft.x = theZone.bounds.ll.x 
		lowerLeft.z = theZone.bounds.ll.z 
		lowerLeft.y = alt -- we go lower 
		
		local upperRight = {}
		alt = land.getHeight({x=theZone.bounds.ur.x, y = theZone.bounds.ur.z}) + 10
		upperRight.x = theZone.bounds.ur.x 
		upperRight.z = theZone.bounds.ur.z 
		upperRight.y = alt -- we go higher 
		
		-- construct volume 
		local vol = {
			id = world.VolumeType.BOX,
			params = {
				min = lowerLeft,
				max = upperRight
			}
		}
		return vol 
	else 
		trigger.action.outText("zne: unknown zone type for <" .. theZone.name .. ">", 30)
	end
end

function dmlZone:getZoneVolume()
	return cfxZones.getZoneVolume(self)
end 


function cfxZones.declutterZone(theZone)
	if not theZone then return end 
	local theVol = cfxZones.getZoneVolume(theZone)
	world.removeJunk(theVol)
end

function dmlZone:declutterZone()
	local theVol = cfxZones.getZoneVolume(self)
	world.removeJunk(theVol)
end

--
-- units / groups in zone
--
function cfxZones.allGroupsInZone(theZone, categ) -- categ is optional, must be code 
	-- warning: does not check for existing!
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

function dmlZone:allGroupsInZone(categ)
	return cfxZones.allGroupsInZone(self, categ)
end

function cfxZones.allGroupNamesInZone(theZone, categ) -- categ is optional, must be code 
	-- warning: does not check for existing!
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

function dmlZone:allGroupNamesInZone(categ)
	return cfxZones.allGroupNamesInZone(self, categ)
end

function cfxZones.allStaticsInZone(theZone, useOrigin) -- categ is optional, must be code 
	-- warning: does not check for existing!
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

function dmlZone:allStaticsInZone(useOrigin)
	return cfxZones.allStaticsInZone(self, useOrigin)
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
			if inzone then		
				return true
			end 
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

function dmlZone:isEntireGroupInZone(aGroup)
	return cfxZones.isEntireGroupInZone(aGroup, self)
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
	
	-- update zone bounds 
	theZone.bounds.ll.x = theZone.bounds.ll.x + dx 
	theZone.bounds.lr.x = theZone.bounds.lr.x + dx
	theZone.bounds.ul.x = theZone.bounds.ul.x + dx 
	theZone.bounds.ur.x = theZone.bounds.ur.x + dx

	theZone.bounds.ll.z = theZone.bounds.ll.z + dz 
	theZone.bounds.lr.z = theZone.bounds.lr.z + dz
	theZone.bounds.ul.z = theZone.bounds.ul.z + dz 
	theZone.bounds.ur.z = theZone.bounds.ur.z + dz
	
end

function dmlZone:offsetZone(dx, dz)
	cfxZones.offsetZone(self, dx, dz)
end


function cfxZones.moveZoneTo(theZone, x, z)
	local dx = x - theZone.point.x
	local dz = z - theZone.point.z 
	cfxZones.offsetZone(theZone, dx, dz)
end;

function dmlZone:moveZoneTo(x, z)
	cfxZones.moveZoneTo(self, x, z)
end

function cfxZones.centerZoneOnUnit(theZone, theUnit) 
	local thePoint = theUnit:getPoint()
	cfxZones.moveZoneTo(theZone, thePoint.x, thePoint.z)
end

function dmlZone:centerZoneOnUnit(theUnit) 
	local thePoint = theUnit:getPoint()
	self:moveZoneTo(thePoint.x, thePoint.z)
end


function cfxZones.dumpZones(zoneTable)
	if not zoneTable then zoneTable = cfxZones.zones end 
	
	trigger.action.outText("Zones START", 10)
	for i, zone in pairs(zoneTable) do 
		local myType = "unknown"
		if zone.isCircle then myType = "Circle" end
		if zone.isPoly then myType = "Poly" end 
		
		trigger.action.outText("#".. i .. ": " .. zone.name .. " of type " .. myType, 10)
	end
	trigger.action.outText("Zones end", 10)
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
	local prefixZones = {}
	prefix = prefix:upper() -- all zones have UPPERCASE NAMES! THEY SCREAM AT YOU
	for name, zone in pairs(searchSet) do
		if dcsCommon.stringStartsWith(name:upper(), prefix) then
			prefixZones[name] = zone -- note: ref copy!
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

function dmlZone:markZoneWithSmoke(dx, dz, smokeColor, alt)
	cfxZones.markZoneWithSmoke(self, dx, dz, smokeColor, alt)
end

-- place a smoke marker in center of zone, offset by radius and degrees 
function cfxZones.markZoneWithSmokePolar(theZone, radius, degrees, smokeColor, alt)
	local rads = degrees * math.pi / 180
	local dx = radius * math.sin(rads)
	local dz = radius * math.cos(rads)
	cfxZones.markZoneWithSmoke(theZone, dx, dz, smokeColor, alt)
end

function dmlZone:markZoneWithSmokePolar(radius, degrees, smokeColor, alt)
	cfxZones.markZoneWithSmokePolar(self, radius, degrees, smokeColor, alt)
end

-- place a smoke marker in center of zone, offset by radius and randomized degrees 
function cfxZones.markZoneWithSmokePolarRandom(theZone, radius, smokeColor)
	local degrees = math.random(360)
	cfxZones.markZoneWithSmokePolar(theZone, radius, degrees, smokeColor)
end

function dmlZone:markZoneWithSmokePolarRandom(radius, smokeColor)
	local degrees = math.random(360)
	self:markZoneWithSmokePolar(radius, degrees, smokeColor)
end

function cfxZones.pointInOneOfZones(thePoint, zoneArray, useOrig) 
	if not zoneArray then zoneArray = cfxZones.zones end 
	for idx, theZone in pairs(zoneArray) do 
		local isIn, percent, dist = cfxZones.pointInZone(thePoint, theZone, useOrig)
		if isIn then return isIn, percent, dist, theZone end 
	end
	return false, 0, 0, nil 
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

function dmlZone:pointInZone(thePoint, useOrig)
	return cfxZones.pointInZone(thePoint, self, useOrig)
end


function cfxZones.unitInZone(theUnit, theZone)
	if not (theUnit) then return false, 0, 0 end
	if not (theUnit:isExist()) then return false, 0, 0 end
	-- force zone update if it is linked to another zone 
	-- pointInZone does update
	local thePoint = theUnit:getPoint()
	return cfxZones.pointInZone(thePoint, theZone)
end

function dmlZone:unitInZone(theUnit)
	if not (theUnit) then return false, 0, 0 end
	if not (theUnit:isExist()) then return false, 0, 0 end
	-- force zone update if it is linked to another zone 
	-- pointInZone does update
	local thePoint = theUnit:getPoint()
	return self:pointInZone(thePoint)
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

function dmlZone:unitsInZone(theUnits)
	if not theUnits then return {} end
	local zoneUnits = {}
	for index, aUnit in pairs(theUnits) do 
		if self:unitInZone(aUnit) then 
			table.insert(zoneUnits, aUnit)
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
	local zP = cfxZones.getPoint(theZone)
	local smallestDist = math.huge
	for i=2, #theUnits do
		local aUnit = theUnits[i]
		local currDist = dcsCommon.dist(zP, aUnit:getPoint())
		if smallestDist > currDelta then 
			closestUnit = aUnit
			smallestDist = currDist
		end
	end
	return closestUnit
end

function dmlZone:closestUnitToZoneCenter(theUnits)
	return cfxZones.closestUnitToZoneCenter(theUnits, self)
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

--
-- ===============
-- FLAG PROCESSING 
-- ===============
--

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

function dmlZone:pulseFlag(theFlag, method)
	cfxZones.pulseFlag(theFlag, method, self)
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

function cfxZones.evalRemainder(remainder)
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
	return rNum
end

function cfxZones.doPollFlag(theFlag, method, theZone) -- no OOP equivalent
	-- WARNING: 
	-- if method is a number string, it will be interpreted as follows:
	-- positive number: set immediate 
	-- negative: decrement by amouint
	if not theZone then 
		trigger.action.outText("+++zones: nil theZone on pollFlag", 30)
	end

	local mt = type(method)
	if mt == "number" then 
		method = "#" .. method -- convert to immediate 
		mt = "string"
	elseif mt ~= "string" then 
		trigger.action.outText("+++zne: warning: zone <" .. theZone.name .. "> method type <" .. mt .. "> received. Ignoring", 30)
		return 
	end

	local val = nil
	method = method:lower()
	method = dcsCommon.trim(method)
	val = tonumber(method) -- see if val can be directly converted 
	if dcsCommon.stringStartsWith(method, "+") or 
	   dcsCommon.stringStartsWith(method, "-") 
	then 
		-- skip this processing, a legal method can start with "+" or "-"
		-- and we interpret it as a method to increase or decrease by amount
	elseif (val ~= nil) then 
		-- provision to handle direct (positive) numbers (legacy support)
		-- method can be converted to number but does not start with - or +
		-- since all negative numbers start with '-' above guard will skip, positive will end up here
		cfxZones.setFlagValue(theFlag, val, theZone)
		if cfxZones.verbose or theZone.verbose then
			trigger.action.outText("+++zones: flag <" .. theFlag .. "> changed to #" .. val, 30)
		end 
		return
	else 
	end

	if dcsCommon.stringStartsWith(method, "#") then 
		-- immediate value command. remove # and eval remainder 
		local remainder = dcsCommon.removePrefix(method, "#")
		val = cfxZones.evalRemainder(remainder) -- always returens a number
		cfxZones.setFlagValue(theFlag, val, theZone)
		if theZone.verbose then 
			trigger.action.outText("+++zones: poll setting immediate <" .. theFlag .. "> in <" .. theZone.name .. "> to <" .. val .. ">", 30)
		end
		return 
	end
	
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
		
	elseif dcsCommon.stringStartsWith(method, "+") then 
		-- we add whatever is to the right 
		local remainder = dcsCommon.removePrefix(method, "+")
		local adder = cfxZones.evalRemainder(remainder)
		cfxZones.setFlagValue(theFlag, currVal+adder, theZone)
		if theZone.verbose then 
			trigger.action.outText("+++zones: (poll) updating with '+' flag <" .. theFlag .. "> in <" .. theZone.name .. "> by <" .. adder .. "> to <" .. adder + currVal .. ">", 30)
		end
		
	elseif dcsCommon.stringStartsWith(method, "-") then 
		-- we subtract whatever is to the right 
		local remainder = dcsCommon.removePrefix(method, "-")
		local adder = cfxZones.evalRemainder(remainder)
		cfxZones.setFlagValue(theFlag, currVal-adder, theZone)

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

function dmlZone:pollFlag(theFlag, method)
	cfxZones.pollFlag(theFlag, method, self)
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

function dmlZone:setFlagValue(theFlag, theValue)
	cfxZones.setFlagValueMult(theFlag, theValue, self)
end

function cfxZones.setFlagValue(theFlag, theValue, theZone)
	cfxZones.setFlagValueMult(theFlag, theValue, theZone)
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
		cfxZones.doSetFlagValue(aFlag, theValue, theZone)
	end 
end

function cfxZones.doSetFlagValue(theFlag, theValue, theZone)
	local zoneName = "<dummy>"
	if not theZone then 
		trigger.action.outText("+++Zne: no zone on setFlagValue", 30) -- mod me for detector
	else 
		zoneName = theZone.name -- for flag wildcards
	end
	
	if type(theFlag) == "number" then 
		-- straight set, oldschool ME flag 
		trigger.action.setUserFlag(theFlag, theValue)
		return 
	end
	
	-- we assume it's a string now
	theFlag = dcsCommon.trim(theFlag) -- clear leading/trailing spaces	
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

function dmlZone:getFlagValue(theFlag)
	return cfxZones.getFlagValue(theFlag, self)
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

function dmlZone:verifyMethod(theMethod)
	return cfxZones.verifyMethod(theMethod, self)
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

function dmlZone:evalFlagMethodImmediate(currVal, theMethod, theZone)
	return cfxZones.evalFlagMethodImmediate(currVal, theMethod, self)
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

-- WARNING: testZoneFlag must also support non-dmlZone!!!
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
	
	local testResult = cfxZones.testFlagByMethodForZone(currVal, lastVal, theMethod, theZone)

	-- update latch by method
	theZone[latchName] = currVal 

	-- return result
	return testResult, currVal
end

function dmlZone:testZoneFlag(theFlagName, theMethod, latchName)
	local r, v = cfxZones.testZoneFlag(self, theFlagName, theMethod, latchName)
	return r, v 
end

function cfxZones.numberArrayFromString(inString, default) -- bridge
	return dcsCommon.numberArrayFromString(inString, default)
end
 

function cfxZones.flagArrayFromString(inString) -- dcsCommon bridge 
	return dcsCommon.flagArrayFromString(inString)
end


--
-- Drawing a Zone
--

function cfxZones.drawZone(theZone, lineColor, fillColor, markID)
	if not theZone then return 0 end 
	if not lineColor then lineColor = {0.8, 0.8, 0.8, 1.0} end
	if not fillColor then fillColor = {0.8, 0.8, 0.8, 0.2} end 
	if not markID then markID = dcsCommon.numberUUID() end 
	
	if theZone.isCircle then 
		trigger.action.circleToAll(-1, markID, theZone.point, theZone.radius, lineColor, fillColor, 1, true, "")
	else 
		local poly = theZone.poly
		trigger.action.quadToAll(-1, markID, poly[4], poly[3], poly[2], poly[1], lineColor, fillColor, 1, true, "") -- note: left winding to get fill color
	end
	
	return markID
end

function dmlZone:drawZone(lineColor, fillColor, markID)
	return cfxZones.drawZone(self, lineColor, fillColor, markID)
end

--
-- ===================
-- PROPERTY PROCESSING
-- =================== 
--

function cfxZones.getAllZoneProperties(theZone, caseInsensitive, numbersOnly) -- return as dict 
	if not caseInsensitive then caseInsensitive = false end 
	if not numbersOnly then numbersOnly = false end 
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
		local v = theProp.value 
		if numbersOnly then 
			v = tonumber(v)
			if not v then v = 0 end 
		end
		props[theKey] = v
	end
	return props 
end

function dmlZone:getAllZoneProperties(caseInsensitive, numbersOnly)
	return cfxZones.getAllZoneProperties(self, caseInsensitive, numbersOnly)
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
		return nil
	end 
	if not theKey then 
		trigger.action.outText("+++zone: no property key in getZoneProperty for zone " .. cZone.name, 30)
		return 
	end	

	local props = cZone.properties
	local theVal = cfxZones.extractPropertyFromDCS(theKey, props)
	return theVal
end

function dmlZone:getZoneProperty(theKey)
	if not theKey then 
		trigger.action.outText("+++zone: no property key in OOP getZoneProperty for zone " .. self.name, 30)
		return nil  
	end	
	local props = self.properties
	local theVal = cfxZones.extractPropertyFromDCS(theKey, props)
	return theVal
end


function cfxZones.getStringFromZoneProperty(theZone, theProperty, default)
	if not default then default = "" end
-- OOP heavy duty test here
	local p = theZone:getZoneProperty(theProperty)
	if not p then return default end
	if type(p) == "string" then 
		p = dcsCommon.trim(p)
		if p == "" then p = default end 
		return p
	end
	return default -- warning. what if it was a number first?
end

function dmlZone:getStringFromZoneProperty(theProperty, default)
	if not default then default = "" end
	local p = self:getZoneProperty(theProperty)
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

function dmlZone:getMinMaxFromZoneProperty(theProperty)
	local p = self:getZoneProperty(theProperty)
	local theNumbers = dcsCommon.splitString(p, " ")
	return tonumber(theNumbers[1]), tonumber(theNumbers[2])
end

function cfxZones.randomInRange(minVal, maxVal) -- should be moved to dcsCommon
	if maxVal < minVal then 
		local t = minVal
		minVal = maxVal 
		maxVal = t
	end
	return cfxZones.randomDelayFromPositiveRange(minVal, maxVal)
end

function cfxZones.randomDelayFromPositiveRange(minVal, maxVal) -- should be moved to dcsCommon 
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

function cfxZones.getPositiveRangeFromZoneProperty(theZone, theProperty, default, defaultmax)
	-- reads property as string, and interprets as range 'a-b'. 
	-- if not a range but single number, returns both for upper and lower 
	--trigger.action.outText("***Zne: enter with <" .. theZone.name .. ">: range for property <" .. theProperty .. ">!", 30)
	if not default then default = 0 end 
	if not defaultmax then defaultmax = default end 
	
	local lowerBound = default
	local upperBound = defaultmax 
	
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

		else
			-- bounds illegal
			trigger.action.outText("+++Zne: illegal range  <" .. rangeString .. ">, using " .. default .. "-" .. defaultmax, 30)
			lowerBound = default
			upperBound = defaultmax 
		end
	else 
		upperBound = cfxZones.getNumberFromZoneProperty(theZone, theProperty, defaultmax) -- between pulses 
		lowerBound = upperBound
	end

	return lowerBound, upperBound
end

function dmlZone:getPositiveRangeFromZoneProperty(theProperty, default, defaultmax)
	local lo, up = cfxZones.getPositiveRangeFromZoneProperty(self, theProperty, default, defaultmax)
	return lo, up 
end


function cfxZones.hasProperty(theZone, theProperty) 
	if not theProperty then 
		trigger.action.outText("+++zne: WARNING - hasProperty called with nil theProperty for zone <" .. theZone.name .. ">", 30)
		return false 
	end 
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
		
		if string.sub(theProperty, -1) == "#" then 
			local lessOp = theProperty:sub(1,-2)
			if cfxZones.getZoneProperty(theZone, lessOp) ~= nil then 
				trigger.action.outText("*** NOTE: " .. theZone.name .. "'s property <" .. lessOp .. "> may be missing a hash mark ('#') at end", 30)
			end
			return false 
		end
		
		return false 
	end
	return true 
end

function dmlZone:hasProperty(theProperty) 
	if not theProperty then 
		trigger.action.outText("+++zne: WARNING - hasProperty called with nil theProperty for zone <" .. self.name .. ">", 30)
		return false 
	end 
	local foundIt = self:getZoneProperty(theProperty)
	if not foundIt then 
		-- check for possible forgotten or exchanged IO flags 
		if string.sub(theProperty, -1) == "?" then
			local lessOp = theProperty:sub(1,-2)
			if self:getZoneProperty(lessOp) ~= nil then 
				trigger.action.outText("*** NOTE: " .. self.name .. "'s property <" .. lessOp .. "> may be missing a Query ('?') symbol", 30)
			end
			local lessPlus = lessOp .. "!"
			if self:getZoneProperty(lessPlus) ~= nil then 
				trigger.action.outText("*** NOTE: " .. self.name .. "'s property <" .. lessOp .. "> may be using '!' instead of '?' for input", 30)
			end
			return false 
		end
		
		if string.sub(theProperty, -1) == "!" then 
			local lessOp = theProperty:sub(1,-2)
			if self:getZoneProperty(lessOp) ~= nil then 
				trigger.action.outText("*** NOTE: " .. self.name .. "'s property <" .. lessOp .. "> may be missing a Bang! ('!') symbol", 30)
			end
			local lessPlus = lessOp .. "?"
			if self:getZoneProperty(lessPlus) ~= nil then 
				trigger.action.outText("*** NOTE: " .. self.name .. "'s property <" .. lessOp .. "> may be using '!' instead of '?' for input", 30)
			end
			return false 
		end
		
		if string.sub(theProperty, -1) == ":" then 
			local lessOp = theProperty:sub(1,-2)
			if self:getZoneProperty(lessOp) ~= nil then 
				trigger.action.outText("*** NOTE: " .. self.name .. "'s property <" .. lessOp .. "> may be missing a colon (':') at end", 30)
			end
			return false 
		end
		
		return false 
	end
	return true 
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

function dmlZone:getBoolFromZoneProperty(theProperty, defaultVal)
	if not defaultVal then defaultVal = false end 
	if type(defaultVal) ~= "boolean" then 
		defaultVal = false 
	end

	local p = self:getZoneProperty(theProperty)
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

function dmlZone:getCoalitionFromZoneProperty(theProperty, default)
	if not default then default = 0 end
	local p = self:getZoneProperty(theProperty)
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
	if not default then default = 0 end
	default = tonumber(default)
	if not default then default = 0 end -- enforce default numbner as well 
	local p = cfxZones.getZoneProperty(theZone, theProperty)
	p = tonumber(p)
	if not p then p = default end 
	return p
end

function dmlZone:getNumberFromZoneProperty(theProperty, default) 
	if not default then default = 0 end
	default = tonumber(default)
	if not default then default = 0 end -- enforce default numbner as well 
	local p = self:getZoneProperty(theProperty)
	p = tonumber(p)
	if not p then p = default end 
	return p
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

function dmlZone:getVectorFromZoneProperty(theProperty, minDims, defaultVal)
	if not minDims then minDims = 0 end 
	if not defaultVal then defaultVal = 0 end 
	local s = self:getStringFromZoneProperty(theProperty, "")
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

function cfxZones.getRGBVectorFromZoneProperty(theZone, theProperty, defaultVal)
	if not defaultVal then defaultVal = {1.0, 1.0, 1.0} end 
	if #defaultVal ~=3 then defaultVal = {1.0, 1.0, 1.0} end
	local s = cfxZones.getStringFromZoneProperty(theZone, theProperty, "")
	local sVec = dcsCommon.splitString(s, ",")
	local nVec = {}
	for i = 1, 3 do 
		n = sVec[i]
		if n then n = tonumber(n) end 
		if not n then n = defaultVal[i] end 
		if n > 1.0 then n = 1.0 end
		if n < 0 then n = 0 end 
		nVec[i] = n
	end
	return nVec 
end

function dmlZone:getRGBVectorFromZoneProperty(theProperty, defaultVal)
	if not defaultVal then defaultVal = {1.0, 1.0, 1.0} end 
	if #defaultVal ~=3 then defaultVal = {1.0, 1.0, 1.0} end
	local s = self:getStringFromZoneProperty(theProperty, "")
	local sVec = dcsCommon.splitString(s, ",")
	local nVec = {}
	for i = 1, 3 do 
		n = sVec[i]
		if n then n = tonumber(n) end 
		if not n then n = defaultVal[i] end 
		if n > 1.0 then n = 1.0 end
		if n < 0 then n = 0 end 
		nVec[i] = n
	end
	return nVec 
end


function cfxZones.getRGBAVectorFromZoneProperty(theZone, theProperty, defaultVal)
	if not defaultVal then defaultVal = {1.0, 1.0, 1.0, 1.0} end 
	if #defaultVal ~=4 then defaultVal = {1.0, 1.0, 1.0, 1.0} end
	local s = cfxZones.getStringFromZoneProperty(theZone, theProperty, "")
	s = dcsCommon.trim(s)
	if s:sub(1,1) == "#" then 
		-- it's probably a "#RRGGBBAA" format hex string 
		local hVec = dcsCommon.hexString2RGBA(s)
		if hVec then return hVec end 
	end

	local sVec = dcsCommon.splitString(s, ",")
	local nVec = {}
	for i = 1, 4 do 
		n = sVec[i]
		if n then n = tonumber(n) end 
		if not n then n = defaultVal[i] end 
		if n > 1.0 then n = 1.0 end
		if n < 0 then n = 0 end 
		nVec[i] = n
	end
		
	return nVec 
end

function dmlZone:getRGBAVectorFromZoneProperty(theProperty, defaultVal)
	if not defaultVal then defaultVal = {1.0, 1.0, 1.0, 1.0} end 
	if #defaultVal ~=4 then defaultVal = {1.0, 1.0, 1.0, 1.0} end
	local s = self:getStringFromZoneProperty(theProperty, "")
	s = dcsCommon.trim(s)
	if s:sub(1,1) == "#" then 
		-- it's probably a "#RRGGBBAA" format hex string 
		local hVec = dcsCommon.hexString2RGBA(s)
		if hVec then return hVec end 
	end

	local sVec = dcsCommon.splitString(s, ",")
	local nVec = {}
	for i = 1, 4 do 
		n = sVec[i]
		if n then n = tonumber(n) end 
		if not n then n = defaultVal[i] end 
		if n > 1.0 then n = 1.0 end
		if n < 0 then n = 0 end 
		nVec[i] = n
	end
		
	return nVec 
end

function cfxZones.getRGBFromZoneProperty(theZone, theProperty, default)
	--if not default then default = {1.0, 1.0, 1.0} end -- white 
	local rawRGB = cfxZones.getVectorFromZoneProperty(theZone, theProperty, 3, 1.0)
	local retVal = {}
	for i = 1, 3 do 
		local cp = rawRGB[i]
		if cp > 1.0 then cp = 1.0 end
		if cp < 0 then cp = 0 end 
		retVal[i] = cp
	end
	return retVal
end

function dmlZone:getRGBFromZoneProperty(theProperty, default)
	--if not default then default = {1.0, 1.0, 1.0} end -- white 
	local rawRGB = self:getVectorFromZoneProperty(theProperty, 3, 1.0)
	local retVal = {}
	for i = 1, 3 do 
		local cp = rawRGB[i]
		if cp > 1.0 then cp = 1.0 end
		if cp < 0 then cp = 0 end 
		retVal[i] = cp
	end
	return retVal
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

function dmlZone:getSmokeColorStringFromZoneProperty(theProperty, default) -- smoke as 'red', 'green', or 1..5
	if not default then default = "red" end 
	local s = self:getStringFromZoneProperty(theProperty, default)
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

function cfxZones.getFlareColorStringFromZoneProperty(theZone, theProperty, default) -- smoke as 'red', 'green', or 1..5
	if not default then default = "red" end 
	local s = cfxZones.getStringFromZoneProperty(theZone, theProperty, default)
	s = s:lower()
	s = dcsCommon.trim(s)
	-- check numbers 
	if (s == "rnd") then return "random" end 
	if (s == "0") then return "green" end
	if (s == "1") then return "red" end
	if (s == "2") then return "white" end
	if (s == "3") then return "yellow" end
	if (s == "-1") then return "random" end  
	
	if s == "green" or
	   s == "red" or
	   s == "white" or
	   s == "yellow" or 
	   s == "random" then
	return s end

	return default 
end

function dmlZone:getFlareColorStringFromZoneProperty(theProperty, default) -- smoke as 'red', 'green', or 1..5
	if not default then default = "red" end 
	local s = self:getStringFromZoneProperty(theProperty, default)
	s = s:lower()
	s = dcsCommon.trim(s)
	-- check numbers 
	if (s == "rnd") then return "random" end 
	if (s == "0") then return "green" end
	if (s == "1") then return "red" end
	if (s == "2") then return "white" end
	if (s == "3") then return "yellow" end
	if (s == "-1") then return "random" end  
	
	if s == "green" or
	   s == "red" or
	   s == "white" or
	   s == "yellow" or 
	   s == "random" then
	return s end

	return default 
end

--
-- Zone-based wildcard processing
-- 

-- process <z>
function cfxZones.processZoneStatics(inMsg, theZone)
	if theZone then 
		inMsg = inMsg:gsub("<z>", theZone.name)
	end
	return inMsg 
end

function dmlZone:processZoneStatics(inMsg, theZone)
	inMsg = inMsg:gsub("<z>", self.name)
	return inMsg 
end

-- process <t>, <lat>, <lon>, <ele>, <mgrs> 
function cfxZones.processSimpleZoneDynamics(inMsg, theZone, timeFormat, imperialUnits)
	if not inMsg then return "<nil inMsg>" end
	-- replace <t> with current mission time HMS
	local absSecs = timer.getAbsTime()-- + env.mission.start_time
	while absSecs > 86400 do 
		absSecs = absSecs - 86400 -- subtract out all days 
	end
	if not timeFormat then timeFormat = "<:h>:<:m>:<:s>" end 
	local timeString  = dcsCommon.processHMS(timeFormat, absSecs)
	local outMsg = inMsg:gsub("<t>", timeString)
	
	-- replace <lat> with lat of zone point and <lon> with lon of zone point 
	-- and <mgrs> with mgrs coords of zone point 
	local currPoint = cfxZones.getPoint(theZone)
	local lat, lon = coord.LOtoLL(currPoint)
	lat, lon = dcsCommon.latLon2Text(lat, lon)
	local alt = land.getHeight({x = currPoint.x, y = currPoint.z})
	if imperialUnits then 
		alt = math.floor(alt * 3.28084) -- feet 
	else 
		alt = math.floor(alt) -- meters 
	end 
	outMsg = outMsg:gsub("<lat>", lat)
	outMsg = outMsg:gsub("<lon>", lon)
	outMsg = outMsg:gsub("<ele>", alt)
	local grid = coord.LLtoMGRS(coord.LOtoLL(currPoint))
	local mgrs = grid.UTMZone .. ' ' .. grid.MGRSDigraph .. ' ' .. grid.Easting .. ' ' .. grid.Northing
	outMsg = outMsg:gsub("<mgrs>", mgrs)
	return outMsg
end 

-- process <v: flag>, <rsp: flag> <rrnd>
function cfxZones.processDynamicValues(inMsg, theZone, msgResponses)
	-- replace all occurences of <v: flagName> with their values 
	local pattern = "<v:%s*[%s%w%*%d%.%-_]+>" -- no list allowed but blanks and * and . and - and _ --> we fail on the other specials to keep this simple 
	local outMsg = inMsg
	repeat -- iterate all patterns one by one 
		local startLoc, endLoc = string.find(outMsg, pattern)
		if startLoc then 
			local theValParam = string.sub(outMsg, startLoc, endLoc)
			-- strip lead and trailer 
			local param = string.gsub(theValParam, "<v:%s*", "")
			param = string.gsub(param, ">","")
			-- param = dcsCommon.trim(param) -- trim is called anyway
			-- access flag
			local val = cfxZones.getFlagValue(param, theZone)
			val = tostring(val)
			if not val then val = "NULL" end 
			-- replace pattern in original with new val 
			outMsg = string.gsub(outMsg, pattern, val, 1) -- only one sub!
		end
	until not startLoc
	
	-- now process rsp 
	pattern = "<rsp:%s*[%s%w%*%d%.%-_]+>" -- no list allowed but blanks and * and . and - and _ --> we fail on the other specials to keep this simple 

	if msgResponses and (#msgResponses > 0) then -- only if this zone has an array
		--trigger.action.outText("enter response proccing", 30)
		repeat -- iterate all patterns one by one 
			local startLoc, endLoc = string.find(outMsg, pattern)
			if startLoc then 
				local theValParam = string.sub(outMsg, startLoc, endLoc)
				-- strip lead and trailer 
				local param = string.gsub(theValParam, "<rsp:%s*", "")
				param = string.gsub(param, ">","")
				
				-- access flag
				local val = cfxZones.getFlagValue(param, theZone)
				if not val or (val < 1) then val = 1 end 
				if val > msgResponses then val = msgResponses end 
				
				val = msgResponses[val]
				val = dcsCommon.trim(val)
				-- replace pattern in original with new val 
				outMsg = string.gsub(outMsg, pattern, val, 1) -- only one sub!
			end
		until not startLoc
		
		-- rnd response 
		local rndRsp = dcsCommon.pickRandom(msgResponses)
		outMsg = outMsg:gsub ("<rrnd>", rndRsp)
	end
	
	return outMsg
end

-- process <t: flag>
function cfxZones.processDynamicTime(inMsg, theZone, timeFormat)
	if not timeFormat then timeFormat = "<:h>:<:m>:<:s>" end
	-- replace all occurences of <t: flagName> with their values 
	local pattern = "<t:%s*[%s%w%*%d%.%-_]+>" -- no list allowed but blanks and * and . and - and _ --> we fail on the other specials to keep this simple 
	local outMsg = inMsg
	repeat -- iterate all patterns one by one 
		local startLoc, endLoc = string.find(outMsg, pattern)
		if startLoc then 
			local theValParam = string.sub(outMsg, startLoc, endLoc)
			-- strip lead and trailer 
			local param = string.gsub(theValParam, "<t:%s*", "")
			param = string.gsub(param, ">","")
			-- access flag
			local val = cfxZones.getFlagValue(param, theZone)
			-- use this to process as time value 
			--trigger.action.outText("time: accessing <" .. param .. "> and received <" .. val .. ">", 30)
			local timeString  = dcsCommon.processHMS(timeFormat, val)
			
			if not timeString then timeString = "NULL" end 
			-- replace pattern in original with new val 
			outMsg = string.gsub(outMsg, pattern, timeString, 1) -- only one sub!
		end
	until not startLoc
	return outMsg
end

-- process <lat/lon/ele/mgrs/lle/latlon/alt/vel/hdg/rhdg/type/player: zone/unit>
function cfxZones.processDynamicLoc(inMsg, imperialUnits, responses)
	local locales = {"lat", "lon", "ele", "mgrs", "lle", "latlon", "alt", "vel", "hdg", "rhdg", "type", "player"}
	local outMsg = inMsg
	local uHead = 0
	for idx, aLocale in pairs(locales) do 
		local pattern = "<" .. aLocale .. ":%s*[%s%w%*%d%.%-_]+>"
		repeat -- iterate all patterns one by one 
			local startLoc, endLoc = string.find(outMsg, pattern)
			if startLoc then
				local theValParam = string.sub(outMsg, startLoc, endLoc)
				-- strip lead and trailer 
				local param = string.gsub(theValParam, "<" .. aLocale .. ":%s*", "")
				param = string.gsub(param, ">","")
				-- find zone or unit
				param = dcsCommon.trim(param)
				local thePoint = nil 
				local tZone = cfxZones.getZoneByName(param)
				local tUnit = Unit.getByName(param)
				local spd = 0
				local angels = 0 
				local theType = "<errType>"
				local playerName = "Unknown"
				if tZone then
					theType = "Zone"
					playerName = "?zone?"
					thePoint = cfxZones.getPoint(tZone)
					if tZone.linkedUnit and Unit.isExist(tZone.linkedUnit) then 
						local lU = tZone.linkedUnit
						local masterPoint = lU:getPoint()
						thePoint.y = masterPoint.y 
						spd = dcsCommon.getUnitSpeed(lU)
						spd = math.floor(spd * 3.6)
						uHead = math.floor(dcsCommon.getUnitHeading(tUnit) * 57.2958) -- to degrees.
					else 
						-- since zones always have elevation of 0, 
						-- now get the elevation from the map 
						thePoint.y = land.getHeight({x = thePoint.x, y = thePoint.z})
					end
				elseif tUnit then 
					if Unit.isExist(tUnit) then
						theType = tUnit:getTypeName()
						if tUnit.getPlayerName and tUnit:getPlayerName() then
							playerName = tUnit:getPlayerName()
						end
						thePoint = tUnit:getPoint()
						spd = dcsCommon.getUnitSpeed(tUnit)
						-- convert m/s to km/h 
						spd = math.floor(spd * 3.6)
						uHead = math.floor(dcsCommon.getUnitHeading(tUnit) * 57.2958) -- to degrees. 
					end
				else 
					-- nothing to do, remove me.
				end

				local locString = "err"
				if thePoint then 
					-- now that we have a point, we can do locale-specific
					-- processing. return result in locString
					local lat, lon, alt = coord.LOtoLL(thePoint)
					lat, lon = dcsCommon.latLon2Text(lat, lon)
					angels = math.floor(thePoint.y) 
					if imperialUnits then 
						alt = math.floor(alt * 3.28084) -- feet
						spd = math.floor(spd * 0.539957) -- km/h to knots	
						angels = math.floor(angels * 3.28084)
					else 
						alt = math.floor(alt) -- meters 
					end 
					
					if angels > 1000 then 
						angels = math.floor(angels / 100) * 100 
					end
					
					if aLocale == "lat" then locString = lat 
					elseif aLocale == "lon" then locString = lon 
					elseif aLocale == "ele" then locString = tostring(alt)
					elseif aLocale == "lle" then locString = lat .. " " .. lon .. " ele " .. tostring(alt) 
					elseif aLocale == "latlon" then locString = lat .. " " .. lon 
					elseif aLocale == "alt" then locString = tostring(angels) -- don't confuse alt and angels, bad var naming here
					elseif aLocale == "vel" then locString = tostring(spd)
					elseif aLocale == "hdg" then locString = tostring(uHead)
					elseif aLocale == "type" then locString = theType 
					elseif aLocale == "player" then locString = playerName 
					elseif aLocale == "rhdg" and (responses) then 
						local offset = cfxZones.rspMapper360(uHead, #responses)
						locString = dcsCommon.trim(responses[offset])
					else 
						-- we have mgrs
						local grid = coord.LLtoMGRS(coord.LOtoLL(thePoint))
						locString = grid.UTMZone .. ' ' .. grid.MGRSDigraph .. ' ' .. grid.Easting .. ' ' .. grid.Northing
					end
				end
				-- replace pattern in original with new val 
				outMsg = string.gsub(outMsg, pattern, locString, 1) -- only one sub!
			end -- if startloc
		until not startLoc
	end -- for all locales 
	return outMsg
end

-- process reference that can be flag, Zone, or unit.
-- i.e. <coa: xyz>
function cfxZones.processDynamicVZU(inMsg)
local locales = {"coa",}
	local outMsg = inMsg
	local uHead = 0
	for idx, aLocale in pairs(locales) do 
		local pattern = "<" .. aLocale .. ":%s*[%s%w%*%d%.%-_]+>" -- e.g. "<coa: flag Name>
		repeat -- iterate all patterns one by one 
			local startLoc, endLoc = string.find(outMsg, pattern)
			if startLoc then
				local theValParam = string.sub(outMsg, startLoc, endLoc)
				-- strip lead and trailer 
				local param = string.gsub(theValParam, "<" .. aLocale .. ":%s*", "") -- remove "<coa:"
				param = string.gsub(param, ">","") -- remove trailing ">"
				-- find zone or unit
				param = dcsCommon.trim(param) -- param = "flag Name"
				local tZone = cfxZones.getZoneByName(param)
				local tUnit = Unit.getByName(param)

				local locString = "err"
				if aLocale == "coa" then
					coa = trigger.misc.getUserFlag(param)
					if tZone then coa = tZone.owner end 
					if tUnit and Unit:isExist(tUnit) then coa = tUnit:getCoalition() end 
					locString = dcsCommon.coalition2Text(coa)
				end

				outMsg = string.gsub(outMsg, pattern, locString, 1) -- only one sub!
			end -- if startloc
		until not startLoc
	end -- for all locales 
	return outMsg
end

-- process two-value vars that can be flag or unit and return interpreted value
-- i.e. <alive: Aerial-1-1>
function cfxZones.processDynamicValueVU(inMsg)
local locales = {"yes", "true", "alive", "in"}
	local outMsg = inMsg
	local uHead = 0
	for idx, aLocale in pairs(locales) do 
		local pattern = "<" .. aLocale .. ":%s*[%s%w%*%d%.%-_]+>" -- e.g. "<yes: flagOrUnitName>
		repeat -- iterate all patterns one by one 
			local startLoc, endLoc = string.find(outMsg, pattern)
			if startLoc then
				local theValParam = string.sub(outMsg, startLoc, endLoc)
				-- strip lead and trailer 
				local param = string.gsub(theValParam, "<" .. aLocale .. ":%s*", "") -- remove "<alive:"
				param = string.gsub(param, ">","") -- remove trailing ">"
				-- find zone or unit
				param = dcsCommon.trim(param) -- param = "flagOrUnitName"
				local tUnit = Unit.getByName(param)
				local yesNo = trigger.misc.getUserFlag(param) ~= 0
				if tUnit then yesNo = Unit.isExist(tUnit) end
				local locString = "err"
				if aLocale == "yes" then					
					if yesNo then locString = "yes" else locString = "no" end
				elseif aLocale == "true" then 
					if yesNo then locString = "true" else locString = "false" end 
				elseif aLocale == "alive" then 
					if yesNo then locString = "alive" else locString = "dead" end
				elseif aLocale == "in" then 
					if yesNo then locString = "in" else locString = "out" end
				end

				outMsg = string.gsub(outMsg, pattern, locString, 1) -- only one sub!
			end -- if startloc
		until not startLoc
	end -- for all locales 
	return outMsg
end

function cfxZones.processDynamicAB(inMsg, locale)
	local outMsg = inMsg
	if not locale then locale = "A/B" end 
	
	-- <A/B: flagOrUnitName [val A | val B]>
	local replacerValPattern = "<".. locale .. ":%s*[%s%w%*%d%.%-_]+" .. "%[[%s%w]+|[%s%w]+%]"..">"
	repeat 
		local startLoc, endLoc = string.find(outMsg, replacerValPattern)
		if startLoc then 
			local rp = string.sub(outMsg, startLoc, endLoc)
			-- get val/unit name 
			local valA, valB = string.find(rp, ":%s*[%s%w%*%d%.%-_]+%[")
			local val = string.sub(rp, valA+1, valB-1)
			val = dcsCommon.trim(val)
			-- get left and right 
			local leftA, leftB = string.find(rp, "%[[%s%w]+|" ) -- from "[" to "|"
			local rightA, rightB = string.find(rp, "|[%s%w]+%]") -- from "|" to "]"
			left = string.sub(rp, leftA+1, leftB-1)
			left = dcsCommon.trim(left)
			right = string.sub(rp, rightA+1, rightB-1)
			right = dcsCommon.trim(right)		
			local yesno = false
			-- see if unit exists
			local theUnit = Unit.getByName(val)
			if theUnit then 
				yesno = Unit:isExist(theUnit)
			else 
				yesno = trigger.misc.getUserFlag(val) ~= 0
			end

			local locString = left 
			if yesno then locString = right end 
			outMsg = string.gsub(outMsg, replacerValPattern, locString, 1)
		end
	until not startLoc 
	return outMsg
end

function cfxZones.rspMapper360(directionInDegrees, numResponses)
	-- maps responses around a clock. Clock has 12 'responses' (12, 1, .., 11), 
	-- with the first (12) also mapping to the last half arc 
	-- this method dynamically 'winds' the responses around 
	-- a clock and returns the index of the message to display 
	if numResponses < 1 then numResponses = 1 end 
	directionInDegrees = math.floor(directionInDegrees) 
	while directionInDegrees < 0 do directionInDegrees = directionInDegrees + 360 end 
	while directionInDegrees >= 360 do directionInDegrees = directionInDegrees - 360 end 
	-- now we have 0..360 
	-- calculate arc per item 
	local arcPerItem = 360 / numResponses
	local halfArc = arcPerItem / 2

	-- we now map 0..360 to (0-halfArc..360-halfArc) by shifting 
	-- direction by half-arc and clipping back 0..360
	-- and now we can directly derive the index of the response 
	directionInDegrees = directionInDegrees + halfArc
	if directionInDegrees >= 360 then directionInDegrees = directionInDegrees - 360 end 
	
	local index = math.floor(directionInDegrees / arcPerItem) + 1 -- 1 .. numResponses 
	
	return index 
end

-- replaces dcsCommon with same name 
-- timeFormat is optional, default is "<:h>:<:m>:<:s>"
-- imperialUnits is optional, defaults to meters 
-- responses is an array of string, defaults to {}
function cfxZones.processStringWildcards(inMsg, theZone, timeFormat, imperialUnits, responses)
	if not inMsg then return "<nil inMsg>" end
	local formerType = type(inMsg)
	if formerType ~= "string" then inMsg = tostring(inMsg) end
	if not inMsg then inMsg = "<inMsg is incompatible type " .. formerType .. ">" end
	local theMsg = inMsg
	-- process common DCS stuff like /n 
	theMsg = dcsCommon.processStringWildcards(theMsg) -- call old inherited
	-- process <z>
	theMsg = cfxZones.processZoneStatics(theMsg, theZone)
	-- process <t>, <lat>, <lon>, <ele>, <mgrs>
	theMsg = cfxZones.processSimpleZoneDynamics(theMsg, theZone, timeFormat, imperialUnits)
	-- process <v: flag>, <rsp: flag> <rrnd>
	theMsg = cfxZones.processDynamicValues(theMsg, theZone, responses)
	-- process <t: flag>
	theMsg = cfxZones.processDynamicTime(theMsg, theZone, timeFormat)
	-- process <lat/lon/ele/mgrs/lle/latlon/alt/vel/hdg/rhdg/type/player: zone/unit>
	theMsg = cfxZones.processDynamicLoc(theMsg, imperialUnits, responses)
    -- process values that can be derived from flag (default), zone or unit 
	theMsg = cfxZones.processDynamicVZU(theMsg)
	theMsg = cfxZones.processDynamicAB(theMsg)
	theMsg = cfxZones.processDynamicValueVU(theMsg)
	return theMsg
end

--
-- ============
-- MOVING ZONES 
-- ============ 
-- 
-- Moving zones contain a link to their unit
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

function dmlZone:getDCSOrigin()
	local o = {}
	if not self.dcsOrigin then 
		trigger.action.outText("dmlZone (OOP): no dcsOrigin defined for zone <" .. self.name .. ">", 30)
		o.x = 0
		o.y = 0
		o.z = 0
	else
		o.x = self.dcsOrigin.x
		o.y = 0
		o.z = self.dcsOrigin.z 
	end 
	return o
end

function cfxZones.getLinkedUnit(theZone)
	if not theZone then return nil end 
	if not theZone.linkedUnit then return nil end 
	if not Unit.isExist(theZone.linkedUnit) then return nil end 
	return theZone.linkedUnit 
end

function dmlZone:getLinkedUnit()
	if not self.linkedUnit then return nil end 
	if not Unit.isExist(self.linkedUnit) then return nil end 
	return self.linkedUnit 
end

function cfxZones.getPoint(aZone, getHeight) -- always works, even linked, returned point can be reused
-- returned y (when using getHeight) is that of the land, else 0 
	if not getHeight then getHeight = false end 
	if aZone.linkedUnit then 
		local theUnit = aZone.linkedUnit
		-- has a link. is link existing?
		if Unit.isExist(theUnit) then 
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
	thePos.z = aZone.point.z
	if not getHeight then 
		thePos.y = 0 -- aZone.y 
	else 
		thePos.y = land.getHeight({x = thePos.x, y = thePos.z})
	end
	
	return thePos 
end

function dmlZone:getPoint(getHeight)
	if not getHeight then getHeight = false end 
	if self.linkedUnit then 
		local theUnit = self.linkedUnit
		-- has a link. is link existing?
		if Unit.isExist(theUnit) then 
			-- updates zone position 
			self:centerZoneOnUnit(theUnit)
			local dx = self.dx
			local dy = self.dy
			if self.useHeading then 
				dx, dy = self:calcHeadingOffset(theUnit)
			end
			self:offsetZone(dx, dy)
		end
	end
	local thePos = {}
	thePos.x = self.point.x
	thePos.z = self.point.z
	if not getHeight then 
		thePos.y = 0 -- aZone.y 
	else 
		thePos.y = land.getHeight({x = thePos.x, y = thePos.z})
	end
	
	return thePos 
end

function dmlZone:getName() -- no cfxZones.bridge!
	return self.name 
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

	local dPhi = bearingOffset - unitHeading
	if dPhi < 0 then dPhi = dPhi + 2 * 3.141592 end
	if (theZone.verbose and theZone.useHeading) then 
		trigger.action.outText("Zone is at <" .. math.floor(57.2958 * dPhi) .. "> relative to unit heading", 30)
	end
	theZone.dPhi = dPhi -- constant delta between unit heading and 
	-- direction to zone 
	theZone.uHdg = unitHeading -- original unit heading to turn other 
	-- units if need be 
end

function dmlZone:linkUnitToZone(theUnit, dx, dy) -- note: dy is really Z, don't get confused!!!!
	self.linkedUnit = theUnit
	if not dx then dx = 0 end
	if not dy then dy = 0 end 
	self.dx = dx
	self.dy = dy 
	self.rxy = math.sqrt(dx * dx + dy * dy) -- radius 
	local unitHeading = dcsCommon.getUnitHeading(theUnit)
	local bearingOffset = math.atan2(dy, dx) -- rads 
	if bearingOffset < 0 then bearingOffset = bearingOffset + 2 * 3.141592 end 

	local dPhi = bearingOffset - unitHeading
	if dPhi < 0 then dPhi = dPhi + 2 * 3.141592 end
	if (self.verbose and self.useHeading) then 
		trigger.action.outText("Zone <" .. self.name .. "> is at <" .. math.floor(57.2958 * dPhi) .. "> relative to unit heading", 30)
	end
	self.dPhi = dPhi -- constant delta between unit heading and 
	-- direction to zone 
	self.uHdg = unitHeading -- original unit heading to turn other 
	-- units if need be 
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
	return dx, -dy -- note: dy is z coord!!!!
end

function dmlZone:calcHeadingOffset(theUnit)
	local unitHeading = dcsCommon.getUnitHeading(theUnit)
	local zoneBearing = unitHeading + self.dPhi 
	if zoneBearing > 2 * 3.141592 then zoneBearing = zoneBearing - 2 * 3.141592 end 
	-- in DCS, positive x is north (wtf?) and positive z is east 
	local dy = (-self.rxy) * math.sin(zoneBearing)
	local dx = self.rxy * math.cos(zoneBearing)
	return dx, -dy -- note: dy is z coord!!!!
end


function cfxZones.updateMovingZones()
	cfxZones.updateSchedule = timer.scheduleFunction(cfxZones.updateMovingZones, {}, timer.getTime() + 1/cfxZones.ups)
	-- simply scan all cfx zones for the linkName property, and if present
	-- update the zone's points
	for aName,aZone in pairs(cfxZones.zones) do
		-- only do this if ther is a linkName property, 
		-- else this zone isn't linked. link name is harmonized from 
        -- both linkUnit non-DML and linedUnit DML		
		if aZone.linkName then 
			if aZone.linkBroken then 
				-- try to relink 
				cfxZones.initLink(aZone)
			else --if aZone.linkName then  
				-- always re-acquire linkedUnit via Unit.getByName()
				-- this way we gloss over any replacements via spawns
				aZone.linkedUnit = Unit.getByName(aZone.linkName)
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
					-- we lost link (track level)
					aZone.linkBroken = true 
					aZone.linkedUnit = nil 
				end
			else 
				-- we lost link (top level)
				aZone.linkBroken = true 
				aZone.linkedUnit = nil 
			end
		else 
			-- this zone isn't linked
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
			local A = cfxZones.getDCSOrigin(theZone)
			local B = theUnit:getPoint()
			local delta = dcsCommon.vSub(A,B) 
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

function dmlZone:initLink()
	self.linkBroken = true 
	self.linkedUnit = nil 
	theUnit = Unit.getByName(self.linkName)
	if theUnit then

		local dx = 0
		local dz = 0
		if self.useOffset or self.useHeading then 
			local A = self:getDCSOrigin()
			local B = theUnit:getPoint()
			local delta = dcsCommon.vSub(A,B) 
			dx = delta.x 
			dz = delta.z
		end
		self:linkUnitToZone(theUnit, dx, dz) -- also sets theZone.linkedUnit

		if self.verbose then 
			trigger.action.outText("Link established for zone <" .. self.name .. "> to unit <" .. self.linkName .. ">: dx=<" .. math.floor(dx) .. ">, dz=<" .. math.floor(dz) .. "> dist = <" .. math.floor(math.sqrt(dx * dx + dz * dz)) .. ">" , 30)
		end 
		self.linkBroken = nil 

	else 
		if self.verbose then 
			trigger.action.outText("Linked unit: no unit <" .. self.linkName .. "> to link <" .. self.name .. "> to", 30)
		end
	end
end

function cfxZones.startMovingZones()
	-- read all zones, and look for a property called 'linkedUnit'
	-- which will make them a linked zone if there is a unit that exists
	-- also suppors 'useOffset' and 'useHeading'
	for aName,aZone in pairs(cfxZones.zones) do
		
		local lU = nil 
		-- check if DCS zone has the linkUnit new attribute introduced in 
		-- late 2022 with 2.8
		if aZone.dcsZone.linkUnit then 
			local theID = aZone.dcsZone.linkUnit 
			lU = dcsCommon.getUnitNameByID(theID)
			if not lU then 
				trigger.action.outText("WARNING: Zone <" .. aZone.name .. ">: cannot resolve linked unit ID <" .. theID .. ">", 30)
				lU = "***DML link err***"
			end
		elseif cfxZones.hasProperty(aZone, "linkedUnit") then 
			lU = cfxZones.getZoneProperty(aZone, "linkedUnit")
		end
		
		-- sanity check 
		if aZone.dcsZone.linkUnit and cfxZones.hasProperty(aZone, "linkedUnit") then 
			trigger.action.outText("WARNING: Zone <" .. aZone.name .. "> has dual unit link definition. Will use link to unit <" .. lU .. ">", 30)
		end
		
		if lU then 
			aZone.linkName = lU
			aZone.useOffset = cfxZones.getBoolFromZoneProperty(aZone, "useOffset", false)
			aZone.useHeading = cfxZones.getBoolFromZoneProperty(aZone, "useHeading", false)
			
			cfxZones.initLink(aZone)

		end
		
	end
end

--
-- marking zones 
--

function cfxZones.spreadNObjectsOverLine(theZone, n, objType, left, right, cty) -- leaves last position free 
	trigger.action.outText("left = " .. dcsCommon.point2text(left) .. ", right = " .. dcsCommon.point2text(right),30)
	
	local a = {x=left.x, y=left.z}
	local b = {x=right.x, y=right.z}
	local dir = dcsCommon.vSub(b,a) -- vector from left to right
	local dirInc = dcsCommon.vMultScalar(dir, 1/n) 
	local count = 0 
	local p = {x=left.x, y = left.z}
	local baseName = dcsCommon.uuid(theZone.name)
	while count < n do 
		local theStaticData = dcsCommon.createStaticObjectData(dcsCommon.uuid(theZone.name), objType)
		dcsCommon.moveStaticDataTo(theStaticData, p.x, p.y)
		local theObject = coalition.addStaticObject(cty, theStaticData)
		p = dcsCommon.vAdd(p, dirInc) 
		count = count + 1
	end
end

function cfxZones.markZoneWithObjects(theZone, objType, qtrNum, markCenter, cty) -- returns set 
	if not objType then objType = "Black_Tyre_RF" end 
	if not qtrNum then qtrNum = 3 end -- +1 for number of marks per quarter 
	if not cty then cty = dcsCommon.getACountryForCoalition(0) end -- some neutral county
	local p = theZone:getPoint()
	local newObjects = {}
	
	if theZone.isPoly then 
		-- we place 4 * (qtrnum + 1) objects around the edge of the zone 
		-- we mark each poly along v-->v+1, placing ip and qtrNum additional points 
		local o = cfxZones.spreadNObjectsOverLine(theZone, qtrNum + 1, objType, theZone.poly[1], theZone.poly[2], cty)
		local p = cfxZones.spreadNObjectsOverLine(theZone, qtrNum + 1, objType, theZone.poly[2], theZone.poly[3], cty)
		local q = cfxZones.spreadNObjectsOverLine(theZone, qtrNum + 1, objType, theZone.poly[3], theZone.poly[4], cty)
		local r = cfxZones.spreadNObjectsOverLine(theZone, qtrNum + 1, objType, theZone.poly[4], theZone.poly[1], cty)
		o = dcsCommon.combineTables(o,p)
		p = dcsCommon.combineTables(q,r)
		newObjects = dcsCommon.combineTables(o,p)
		
	else 
		local numObjects = (qtrNum + 1) * 4
		local degrees = 3.14157 / 180
		local degreeIncrement = (360 / numObjects) * degrees
		local currDegree = 0
		local radius = theZone.radius
		for i=1, numObjects do 
			local ox = p.x + math.cos(currDegree) * radius
			local oy = p.z + math.sin(currDegree) * radius -- note: z!
			local theStaticData = dcsCommon.createStaticObjectData(dcsCommon.uuid(theZone.name), objType)
			dcsCommon.moveStaticDataTo(theStaticData, ox, oy)
			local theObject = coalition.addStaticObject(cty, theStaticData)
			table.insert(newObjects, theObject)
			currDegree = currDegree + degreeIncrement
		end
	end
	
	if markCenter then 
		-- also mark the center 
		local theObject = cfxZones.markPointWithObject(p, objType, cty)
		table.insert(newObjects, theObject)
	end 	
	
	return newObjects
end

function dmlZone:markZoneWithObjects(objType, qtrNum, markCenter, cty) -- returns set 
	return cfxZones.markZoneWithObjects(self, objType, qtrNum, markCenter)
end

function cfxZones.markCenterWithObject(theZone, objType, cty) -- returns object
	local p = cfxZones.getPoint(theZone)
	local theObject = cfxZones.markPointWithObject(theZone, p, objType, cty)
	return theObject
end

function dmlZone:markCenterWithObject(objType, cty) -- returns object 
	return cfxZones.markCenterWithObject(self, objType, cty)
end

function cfxZones.markPointWithObject(theZone, p, theType, cty) -- returns object 
	if not cty then cty = dcsCommon.getACountryForCoalition(0) end
	local ox = p.x
	local oy = p.y 	
	if p.z then oy = p.z end -- support vec 2 and vec 3 
	local theStaticData = dcsCommon.createStaticObjectData(dcsCommon.uuid(theZone.name), theType)
	dcsCommon.moveStaticDataTo(theStaticData, ox, oy)
	local theObject = coalition.addStaticObject(cty, theStaticData)
	return theObject
end

function dmlZone:markPointWithObject(p, theType, cty) -- returns object 
	return cfxZones.markPointWithObject(self, p, theType, cty)
end
--
-- ===========
-- INIT MODULE
-- ===========
--

function cfxZones.initZoneVerbosity()
	for aName,aZone in pairs(cfxZones.zones) do
		-- support for zone-local verbose flag 
		aZone.verbose = cfxZones.getBoolFromZoneProperty(aZone, "verbose", false)
	end
end

function cfxZones.init()
	-- read all zones into my own db
	cfxZones.readFromDCS(true) -- true: erase old

	-- pre-read zone owner for all zones
	-- much like verbose, all zones have owner
--	local pZones = cfxZones.zonesWithProperty("owner")
--	for n, aZone in pairs(pZones) do
    for n, aZone in pairs(cfxZones.zones) do
		aZone.owner = cfxZones.getCoalitionFromZoneProperty(aZone, "owner", 0)
	end
		
	-- enable all zone's verbose flags if present
	-- must be done BEFORE we start the moving zones 
	cfxZones.initZoneVerbosity()
	
	-- now initialize moving zones
	cfxZones.startMovingZones()
	cfxZones.updateMovingZones() -- will auto-repeat
	
	trigger.action.outText("cf/x Zones v".. cfxZones.version .. ": loaded, zones:" .. dcsCommon.getSizeOfTable(cfxZones.zones), 30)

end

-- get everything rolling
cfxZones.init()
