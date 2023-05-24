mxObjects = {}

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
