cfxMapMarkers = {}
cfxMapMarkers.version = "1.0.2"
cfxMapMarkers.autostart = true 
--[[--
Version History
 - 1.0.1 - initial version
 - 1.0.2 - coalition property processing cleanup 
 
--]]--
-- cfxMapMarkers places Annotations for players on the F10 map
-- Annotations are derived from Zones, and their properties control who can see them
-- Any Zone with the Property "mapMarker" will put the property's content on the Map
-- Markers are shown to everyone, except when
--  - an additional Property 'coalition' is present, the Map Marker is only shown to that coalition. Possible coalition values are "ALL" (default), "RED", "BLUE", "NEUTRAL"
--  - an additional Property 'group' is present, the Map Marker is shown to the group with that name. Note that  
-- 'coalition' and 'group' are mutually exclusive. Group overrides Coalition
-- you can access map markers by their zones, turn them on and off individually 
-- if autostart is on, all zones are scanned for map markers and displayed according to their properties

-- NOTE: when placing a mark, this will add the 'markID' attribute to the zone table to identify the mark

--cfxMapMarkers.simpleUUID = 76543 -- a number to start. as good as any
--function cfxMapMarkers.uuid()
--	cfxMapMarkers.simpleUUID = cfxMapMarkers.simpleUUID + 1
--	return cfxMapMarkers.simpleUUID
--end

function cfxMapMarkers.addMapMarkerForZone(theZone) 
	local markText = cfxZones.getZoneProperty(theZone, "mapMarker")
	if not markText then return end
	if markText == "" then markText = "I am empty of content, devoid of meaning" end
	
	-- if there is a map marker already, remove it 
	cfxMapMarkers.removeMapMarkerForZone(theZone)
	
	-- get a new map marker ID
	local markID = dcsCommon.numberUUID()
	
	-- see if there is a group or coalition target
	local coal = cfxZones.getStringFromZoneProperty(theZone, "coalition", "ALL")
	if coal == "1" then coal = "RED" end
	if coal == "2" then coal = "BLUE" end 
	
	coal = coal:upper()
	--coal = string.upper(coal)
	
	local toGroup = cfxZones.getZoneProperty(theZone, "group")
	if toGroup then toGroup = Group.getByName(toGroup) end 
	if toGroup then 
		-- mark to group
		local groupID = toGroup:getID()
		trigger.action.markToGroup(markID, markText, theZone.point, groupID, true, "")
		theZone.markID = markID
		return 
	end
	
	-- make sure we have a legal coalition
	if coal ~= "BLUE" and coal ~= "RED" and coal ~= "NEUTRAL" then 
		coal = "ALL"
	end
	
	if coal == "ALL" then 
		-- place the map marker to ALL coalitions		
		trigger.action.markToAll(markID, markText, theZone.point, true, "")
		theZone.markID = markID
		return 
	end
	
	-- if we get here. we should mark by coalition
	local theSide = 0 -- neutral (default)
	if coal == "RED" then
		theSide = 1
	end
	if coal == "BLUE" then 
		theSide = 2
	end
	trigger.action.markToCoalition(markID, markText, theZone.point, theSide, true, "")
	theZone.markID = markID
end

function cfxMapMarkers.removeMapMarkerForZone(theZone)
	if theZone.markID then 
		trigger.action.removeMark(theZone.markID)
	end
end

function cfxMapMarkers.start()
	-- collect all zones that have the 'MapMarker" Attribute 
	local attrZones = cfxZones.getZonesWithAttributeNamed("mapMarker")
	
	-- process every zone  
	for k, aZone in pairs(attrZones) do 
		cfxMapMarkers.addMapMarkerForZone(aZone)
	end
end

if cfxMapMarkers.autostart then cfxMapMarkers.start() end

trigger.action.outText("cfx Map Markers v" .. cfxMapMarkers.version .. " started.", 30)