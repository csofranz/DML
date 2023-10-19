mxObjects = {}
mxObjects.version = "1.0.0"
mxObjects.allObjects = {}
mxObjects.textBoxes = {}
mxObjects.miscObjects = {}
mxObjects.imperial = true 
mxObjects.doubleLine = true 

-- scan mission to set up object DB

function mxObjects.scanMissionData()
	if not env.mission.drawings then 
		trigger.action.outText("+++mxO: Mission has no object layer", 30)
		return 
	end 
	local drawings = env.mission.drawings 
	
	-- all drawings are in drawings[layer]
	local layers = drawings["layers"]
	if not layers then 
		trigger.action.outText("+++mxO: Mission has no layers in objects", 30)
		return
	end
	
	-- each layer has a "name" field that identifies the layer, and 
	-- per layer there are the objects. Let's flatten the structure,
	-- since object names are unique 
	local count = 0
	for idx, aLayer in pairs(layers) do 
		local layerName = aLayer.name 
		local objects = aLayer.objects 
		-- scan objects in this layer
		for idy, theObject in pairs (objects) do 
			local theData = dcsCommon.clone(theObject)
			theData.dist = math.huge -- simply init field 
			-- make theData point-compatible, handle y<>z adapt
			theData.x = theData.mapX -- set up x, y, z
			if not theData.x then theData.x = 0 end
			theData.y = 0 
			theData.z = theData.mapY
			if not theData.z then theData.z = 0 end 
			
			if mxObjects.allObjects[theData.name] then 
				trigger.action.outText("+++mxO: name collision for drawing object named <" .. theData.name .. ">, skipped.", 30)
			else
				mxObjects.allObjects[theData.name] = theData
				count = count + 1
				-- sort into quick-access "type" slots
				if theData.primitiveType == "TextBox" then 
					mxObjects.textBoxes[theData.name] = theData
				else 
					mxObjects.miscObjects[theData.name] = theData
				end
			end
		end
	end
end

function mxObjects.sortObjectsInRelationTo(p, objects)
	if not p then return nil end 
	-- calculate distance to all into new list 
	local disted = {}
	for name, theData in pairs(objects) do 
		theData.dist = dcsCommon.dist(p, theData)
		table.insert(disted, theData)
	end
	table.sort(disted, 
				function (e1, e2) return e1.dist < e2.dist end 
			  )
	return disted 
end


function mxObjects.showNClosestTextObjectsToUnit(n, theUnit, numbered)
	if numbered == nil then numbered = true end 
	local p = theUnit:getPoint()
	local headingInDegrees = dcsCommon.getUnitHeadingDegrees(theUnit)
	local theList = mxObjects.sortObjectsInRelationTo(p, mxObjects.textBoxes)
	local msg = "\n"
	if #theList < 1 then 
		msg = msg .. "  NO OBJECTS "
	else 
		if n > #theList then n = #theList end
		for i = 1, n do 
			theObject = theList[i]
			local dist = theObject.dist
			units = "km"
			if mxObjects.imperial then 
				dist = dist * 3.28084
				dist = math.floor(dist * 0.0016457883895983) -- in 0.1 nautmil 
				units = "nm"
			else
				dist = math.floor(theObject.dist / 100) -- dekameters
			end
			dist = dist / 10
			
			if numbered then 
				if i < 10 and n > 9 then 
					msg = msg .. "0" 
				end
				msg = msg .. i .. ". "
			end 
			-- show text			
			msg = msg .. theObject.text 
			-- bearing 
			local bea = dcsCommon.bearingInDegreesFromAtoB(p, theObject)
			msg = msg .. " bearing " .. bea .. "°,"
			-- get clock position
			local clockPos = dcsCommon.clockPositionOfARelativeToB(theObject, p, headingInDegrees)
			msg = msg .. " your " .. clockPos .. " o'clock, " 
			-- dist 
			msg = msg .. " " .. dist .. units 
			msg = msg .. "\n" -- add line feed 
			if mxObjects.doubleLine then msg = msg .. "\n" end 
		end
	end
	return msg 
	
end

function mxObjects.getClosestTo(p, objects)
	if not p then return nil, nil end 
	local closest = nil 
	local theDist = math.huge
	for oName, theData in pairs (objects) do 
		
	end

end

function mxObjects.getObjectFreePoly(layerName, polyName, rel) -- omit rel to get absolute points, else pass 'true' to get relative to first point.
	if not rel then rel = false end -- relative or absolute
	if not env.mission.drawings then 
		trigger.action.outText("+++mxO: Mission has no drawings.", 30)
		return {}
	end
	
	local drawings = env.mission.drawings
	local layers = drawings["layers"]
	if not layers then 
		trigger.action.outText("+++mxO: Mission has no layers in drawing", 30)
		return {}
	end
	local theLayer = nil
	for idx, aLayer in pairs(layers) do 
		if aLayer.name == layerName then 
			theLayer = aLayer
		end
	end
	if not theLayer then 
		trigger.action.outText("+++mxO: No layer named <" .. layerName .. "> in Mission", 30)
		return {}
	end
	
	local objects = theLayer.objects 
	if not objects then 
		trigger.action.outText("+++mxO: No objects in layer <" .. layerName .. ">", 30)
		return {}
	end
	-- scan objects for a "free" mode poly with name polyName
	for idx, theObject in pairs(objects) do 
		if theObject.polygonMode == "free" and theObject.name == polyName then 
			local poly = {}
			for idp, thePoint in pairs(theObject.points) do 
				local p = {}
				p.x = thePoint.x 
				p.y = thePoint.y
				if not rel then 
					p.x = p.x + theObject.mapX 
					p.y = p.y + theObject.mapY
				end 
				poly[idp] = p
			end
			return poly
		end
	end
	
	trigger.action.outText("+++mxO: no polygon named <" .. polyName .. "> in layer <" ..layerName  .. ">", 30)
	return {}
end

function mxObjects.start()
	mxObjects.scanMissionData()
	trigger.action.outText("mxObjects v" .. mxObjects.version .. " loaded.", 30)

end

mxObjects.start()
--[[--
local theUnit = Unit.getByName("Bannok")
local msg = mxObjects.showNClosestTextObjectsToUnit(8, theUnit, numbered)
trigger.action.outText(msg, 30)
--]]--
