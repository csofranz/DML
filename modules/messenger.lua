messenger = {}
messenger.version = "2.1.0"
messenger.verbose = false 
messenger.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
messenger.messengers = {} 
--[[--
	Version History
	1.0.0 - initial version 
	1.0.1 - messageOut? synonym
	      - spelling types in about 
	1.1.0 - DML flag support 
		  - clearScreen option
		  - inValue?
		  - message preprocessor 
	1.1.1 - firewalled coalition to msgCoalition
		  - messageOn?
		  - messageOff?
	1.2.0 - msgTriggerMethod (original Watchflag integration) 
	1.2.1 - qoL: <n> = newline, <z> = zone name, <v> = value
	1.3.0 - messenger? saves messageOut? attribute 
	1.3.1 - message now can interpret value as time with <h> <m> <s> <:h> <:m> <:s>
	1.3.2 - message interprets <t> as time in HH:MM:SS of current time 
		  - can interpret <lat>, <lon>, <mgrs>
		  - zone-local verbosity
	1.3.3 - mute/messageMute option to start messenger in mute 
	2.0.0 - re-engineered message wildcards
		  - corrected dynamic content for time and latlon (classic)
	      - new timeFormat attribute 
		  - <v: flagname>
		  - <t: flagname>
		  - added <ele> 
		  - added imperial 
		  - <lat: unit/zone>
		  - <lon: unit/zone>
		  - <ele: unit/zone>
		  - <mgrs: unit/zone>
		  - <latlon: unit/zone>
		  - <lle: unit/zone>
		  - messageError 
		  - unit 
		  - group 
	2.0.1 - config optimization
	2.1.0 - unit only: dynamicUnitProcessing for 
			- <bae: u/z> bearing to unit/zone
			- <rbae u/z> response mapped by unit's heading
			- <clk: u/z> bearing in clock position to unit/zone 
			- <rng: u/z> range to unit/zone 
			- <hnd: u/z> bearing in left/right/ahead/behind
			- <sde: u/z> bearing in starboard/port/ahead/aft 
			- added dynamicGroupProcessing to select unit 1
			- responses attribute
			- <rsp: flag>
			- <rrnd> response randomized
			- <rhdg: u/z> respons mapped by unit's heading
			- <cls unit> closing speed 
			- <vel unit> velocity (speed) 
			- <asp unit> aspect 
		    - fix to messageMute
			- <type: unit> 
			
	
--]]--

function messenger.addMessenger(theZone)
	table.insert(messenger.messengers, theZone)
end

function messenger.getMessengerByName(aName) 
	for idx, aZone in pairs(messenger.messengers) do 
		if aName == aZone.name then return aZone end 
	end
	if messenger.verbose then 
		trigger.action.outText("+++msgr: no messenger with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read attributes
--
function messenger.preProcMessage(inMsg, theZone)
	-- Replace STATIC bits of message like CR and zone name 
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
	return outMsg 
end

-- Old-school processing to replace wildcards
-- repalce <t> with current time 
-- replace <lat> with zone's current lonlat
-- replace <mgrs> with zone's current mgrs 
function messenger.dynamicProcessClassic(inMsg, theZone)

	if not inMsg then return "<nil inMsg>" end
	-- replace <t> with current mission time HMS
	local absSecs = timer.getAbsTime()-- + env.mission.start_time
	while absSecs > 86400 do 
		absSecs = absSecs - 86400 -- subtract out all days 
	end
	local timeString  = dcsCommon.processHMS(theZone.msgTimeFormat, absSecs)
	local outMsg = inMsg:gsub("<t>", timeString)
	
	-- replace <lat> with lat of zone point and <lon> with lon of zone point 
	-- and <mgrs> with mgrs coords of zone point 
	local currPoint = cfxZones.getPoint(theZone)
	local lat, lon = coord.LOtoLL(currPoint)
	lat, lon = dcsCommon.latLon2Text(lat, lon)
	local alt = land.getHeight({x = currPoint.x, y = currPoint.z})
	if theZone.imperialUnits then 
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

--
-- new dynamic flag processing 
-- 
function messenger.processDynamicValues(inMsg, theZone)
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

	if theZone.msgResponses and (#theZone.msgResponses > 0) then -- only if this zone has an array
		--trigger.action.outText("enter response proccing", 30)
		repeat -- iterate all patterns one by one 
			local startLoc, endLoc = string.find(outMsg, pattern)
			if startLoc then 
				--trigger.action.outText("response: found an occurence", 30)
				local theValParam = string.sub(outMsg, startLoc, endLoc)
				-- strip lead and trailer 
				local param = string.gsub(theValParam, "<rsp:%s*", "")
				param = string.gsub(param, ">","")
				
				-- access flag
				local val = cfxZones.getFlagValue(param, theZone)
				if not val or (val < 1) then val = 1 end 
				if val > #theZone.msgResponses then val = #theZone.msgResponses end 
				
				val = theZone.msgResponses[val]
				val = dcsCommon.trim(val)
				-- replace pattern in original with new val 
				outMsg = string.gsub(outMsg, pattern, val, 1) -- only one sub!
			end
		until not startLoc
		
		-- rnd response 
		local rndRsp = dcsCommon.pickRandom(theZone.msgResponses)
		outMsg = outMsg:gsub ("<rrnd>", rndRsp)
	end
	
	return outMsg
end

function messenger.processDynamicTime(inMsg, theZone)
	-- replace all occurences of <v: flagName> with their values 
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
			local timeString  = dcsCommon.processHMS(theZone.msgTimeFormat, val)
			
			if not timeString then timeString = "NULL" end 
			-- replace pattern in original with new val 
			outMsg = string.gsub(outMsg, pattern, timeString, 1) -- only one sub!
		end
	until not startLoc
	return outMsg
end

function messenger.processDynamicLoc(inMsg, theZone)
	-- replace all occurences of <lat/lon/ele/mgrs: flagName> with their values 
-- agl = angels 
-- vel = velocity (speed) 
-- hdg = heading 
-- rhdg = heading, response-mapped
	local locales = {"lat", "lon", "ele", "mgrs", "lle", "latlon", "alt", "vel", "hdg", "rhdg", "type"}
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
				if tZone then
					theType = "Zone"
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
						thePoint = tUnit:getPoint()
						spd = dcsCommon.getUnitSpeed(tUnit)
						-- convert m/s to km/h 
						spd = math.floor(spd * 3.6)
						uHead = math.floor(dcsCommon.getUnitHeading(tUnit) * 57.2958) -- to degrees. 
					end
				else 
					-- nothing to do, remove me.
				end

				local locString = theZone.errString
				if thePoint then 
					-- now that we have a point, we can do locale-specific
					-- processing. return result in locString
					local lat, lon, alt = coord.LOtoLL(thePoint)
					lat, lon = dcsCommon.latLon2Text(lat, lon)
					angels = math.floor(thePoint.y) 
					if theZone.imperialUnits then 
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
					elseif aLocale == "rhdg" and (theZone.msgResponses) then 
						local offset = messenger.rspMapper360(uHead, #theZone.msgResponses)
						locString = dcsCommon.trim(theZone.msgResponses[offset])
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



function messenger.rspMapper360(directionInDegrees, numResponses)
	-- maps responses like clock. Clock has 12 'responses' (12, 1, .., 11), 
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


function messenger.dynamicGroupProcessing(msg, theZone, theGroup)
	if not theGroup then return msg end 
	-- access first unit 
	local theUnit = theGroup:getUnit(1) 
	if not theUnit then return msg end 
	if not Unit.isExist(theUnit) then return msg end 
	-- we always use unit 1 as reference 
	return messenger.dynamicUnitProcessing(msg, theZone, theUnit)
end

function messenger.dynamicUnitProcessing(inMsg, theZone, theUnit)
-- replace all occurences of <bae/rng/asp/cls/clk: unit/zone> with their values 
-- bae = bearingInDegreesFromAtoB
-- rng = range 

-- asp = aspect (not yet implemented)
-- cls = closing velocity (not yet implemented) 
-- clk = o'clock 
-- hnd = handedness (left/right/ahead/behind
-- sde = side (starboard / port / ahead / aft)
-- rbea = responses mapped to bearing. maps all responses like clock, with "12" being the first response. requires msgResponses set

	local here = theUnit:getPoint()
	local uHead = dcsCommon.getUnitHeading(theUnit) * 57.2958 -- to degrees. 
	local locales = {"bea", "rng", "clk", "hnd", "sde", "rbea", "cls", "pcls", "asp"}
	local outMsg = inMsg
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
				local cls = 0 
				local aspct = 0
				local tZone = cfxZones.getZoneByName(param)
				local tUnit = Unit.getByName(param)
				local aspect = 0
				local tHead = 0
				
				if tZone then 
					thePoint = cfxZones.getPoint(tZone)
					-- if this zone follows a unit, get the master units elevaltion
					if tZone.linkedUnit and Unit.isExist(tZone.linkedUnit) then 
						local lU = tZone.linkedUnit
						local masterPoint = lU:getPoint()
						thePoint.y = masterPoint.y 
						cls = -dcsCommon.getClosingVelocity(theUnit, lU)
						tHead = dcsCommon.getUnitHeading(lU) * 57.2958
					else 
						-- since zones always have elevation of 0, 
						-- now get the elevation from the map 
						thePoint.y = land.getHeight({x = thePoint.x, y = thePoint.z})
					end
				elseif tUnit then 
					if Unit.isExist(tUnit) then 
						thePoint = tUnit:getPoint()
						cls = -dcsCommon.getClosingVelocity(theUnit, tUnit)
						tHead = dcsCommon.getUnitHeading(tUnit) * 57.2958
					end
				else 
					-- nothing to do, remove me.
				end

				local locString = theZone.errString
				if thePoint then 
					-- now that we have a point, we can do locale-specific
					-- processing. return result in locString
					local pcls = cls
					local r = dcsCommon.dist(here, thePoint)
					--local alt = thePoint.y
					local uSize = "m"
					if theZone.imperialUnits then 
						r = math.floor(r * 3.28084) -- feet 
						uSize = "ft"
						if r > 1000 then 
						-- convert to nautical mile
							r = math.floor(r * 10 / 6076.12) / 10
							uSize = "nm"
						end
						cls = math.floor(cls * 1.9438452) -- m/s to knots
						pcls = math.floor(pcls * 32.8084) / 10 -- ft/s
					else 
						r = math.floor(r) -- meters 
						if r > 1000 then  
							r = math.floor (r /	100) / 10
							uSize = "km"
						end
						cls = math.floor(cls * 3.6) -- m/s to km/h
						pcls = math.floor(pcls * 10) / 10 -- m/s
					end 

					local bea = dcsCommon.bearingInDegreesFromAtoB(here, thePoint)
					local beaInv = 360 - bea -- from tUnit to player
					local direction = bea - uHead  -- tUnit as seen from player heading uHead
					if direction < 0 then direction = direction + 360 end 
					aspect = beaInv - tHead 
					-- set up locale exchange string
					if aLocale == "bea" then locString = tostring(bea)
					elseif aLocale == "asp" then locString = dcsCommon.aspectByDirection(aspect)
					elseif aLocale == "clk" then 
						locString = tostring(dcsCommon.getClockDirection(direction))
					elseif aLocale == "rng" then locString = tostring(r)..uSize
					elseif aLocale == "cls" then locString = tostring(cls)
					elseif aLocale == "pcls" then locString = tostring(pcls)
					elseif aLocale == "hnd" then locString = dcsCommon.getGeneralDirection(direction)
					elseif aLocale == "sde" then locString = dcsCommon.getNauticalDirection(direction) 
					elseif aLocale == "rbea" and (theZone.msgResponses) then 
						local offset = messenger.rspMapper360(direction, #theZone.msgResponses)
						locString = dcsCommon.trim(theZone.msgResponses[offset])
					else locString = "<locale " .. aLocale .. " err: undefined params>"
					end
				end
				-- replace pattern in original with new val 
				outMsg = string.gsub(outMsg, pattern, locString, 1) -- only one sub!
			end -- if startloc
		until not startLoc
	end -- for all locales 
	return outMsg
end


function messenger.dynamicFlagProcessing(inMsg, theZone)
	if not inMsg then return "No in message" end 
	if not theZone then return "Nil zone" end 
	
	-- process <v: xxx> 
	local msg = messenger.processDynamicValues(inMsg, theZone)
	
	-- process <t: xxx>
	msg = messenger.processDynamicTime(msg, theZone)
	
	-- process lat / lon / ele / mgrs
	msg = messenger.processDynamicLoc(msg, theZone)
	
	return msg 
end

function messenger.createMessengerWithZone(theZone)
	-- start val - a range
	
	local aMessage = cfxZones.getStringFromZoneProperty(theZone, "message", "") 
	theZone.message = messenger.preProcMessage(aMessage, theZone)

	theZone.spaceBefore = cfxZones.getBoolFromZoneProperty(theZone, "spaceBefore", false)
	theZone.spaceAfter = cfxZones.getBoolFromZoneProperty(theZone, "spaceAfter", false)

	theZone.soundFile = cfxZones.getStringFromZoneProperty(theZone, "soundFile", "<none>") 

	theZone.clearScreen = cfxZones.getBoolFromZoneProperty(theZone, "clearScreen", false)
	
	theZone.duration = cfxZones.getNumberFromZoneProperty(theZone, "duration", 30)
	if cfxZones.hasProperty(theZone, "messageDuration") then 
		theZone.duration = cfxZones.getNumberFromZoneProperty(theZone, "messageDuration", 30)
	end 
	
	-- msgTriggerMethod
	theZone.msgTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "msgTriggerMethod") then 
		theZone.msgTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "msgTriggerMethod", "change")
	end 
	
	-- trigger flag f? in? messageOut?, add messenger?
	
	if cfxZones.hasProperty(theZone, "f?") then 
		theZone.triggerMessagerFlag = cfxZones.getStringFromZoneProperty(theZone, "f?", "none")	
		-- may want to add deprecated note later
	end 

	
	-- can also use in? for counting. we always use triggerMessagerFlag 
	if cfxZones.hasProperty(theZone, "in?") then 
		theZone.triggerMessagerFlag = cfxZones.getStringFromZoneProperty(theZone, "in?", "none")
	end
	
	if cfxZones.hasProperty(theZone, "messageOut?") then 
		theZone.triggerMessagerFlag = cfxZones.getStringFromZoneProperty(theZone, "messageOut?", "none")
	end
	
	-- try default only if no other is set 
	if not theZone.triggerMessagerFlag then 
		if not cfxZones.hasProperty(theZone, "messenger?") then 
			trigger.action.outText("*** Note: messenger in <" .. theZone.name .. "> can't be triggered", 30)
		end
		theZone.triggerMessagerFlag = cfxZones.getStringFromZoneProperty(theZone, "messenger?", "none")
	end 
		
--	if theZone.triggerMessagerFlag then 
	theZone.lastMessageTriggerValue = cfxZones.getFlagValue(theZone.triggerMessagerFlag, theZone)-- save last value	
--	end

	theZone.messageOff = cfxZones.getBoolFromZoneProperty(theZone, "mute", false) --false 
	if cfxZones.hasProperty(theZone, "messageMute") then
		theZone.messageOff = cfxZones.getBoolFromZoneProperty(theZone, "messageMute", false)
	end
	
	-- advisory: messageOff, messageOffFlag and lastMessageOff are all distinct 
	
	if cfxZones.hasProperty(theZone, "messageOff?") then 
		theZone.messageOffFlag = cfxZones.getStringFromZoneProperty(theZone, "messageOff?", "*none")
		theZone.lastMessageOff = cfxZones.getFlagValue(theZone.messageOffFlag, theZone)
	end
	
	if cfxZones.hasProperty(theZone, "messageOn?") then 
		theZone.messageOnFlag = cfxZones.getStringFromZoneProperty(theZone, "messageOn?", "*none")
		theZone.lastMessageOn = cfxZones.getFlagValue(theZone.messageOnFlag, theZone)
	end
	
	-- reveiver: coalition, group, unit 
	if cfxZones.hasProperty(theZone, "coalition") then 
		theZone.msgCoalition = cfxZones.getCoalitionFromZoneProperty(theZone, "coalition", 0)
	elseif cfxZones.hasProperty(theZone, "msgCoalition") then 
		theZone.msgCoalition = cfxZones.getCoalitionFromZoneProperty(theZone, "msgCoalition", 0)
	end 
	
	if cfxZones.hasProperty(theZone, "group") then 
		theZone.msgGroup = cfxZones.getStringFromZoneProperty(theZone, "group", "<none>")
	elseif cfxZones.hasProperty(theZone, "msgGroup") then 
		theZone.msgGroup = cfxZones.getStringFromZoneProperty(theZone, "msgGroup", "<none>")
	end
	
	if cfxZones.hasProperty(theZone, "unit") then 
		theZone.msgUnit = cfxZones.getStringFromZoneProperty(theZone, "unit", "<none>")
	elseif cfxZones.hasProperty(theZone, "msgUnit") then 
		theZone.msgUnit = cfxZones.getStringFromZoneProperty(theZone, "msgUnit", "<none>")
	end
	
	if (theZone.msgGroup and theZone.msgUnit) or 
	   (theZone.msgGroup and theZone.msgCoalition) or
	   (theZone.msgUnit and theZone.msgCoalition)
	then 
		trigger.action.outText("+++msg: WARNING - messenger in <" .. theZone.name .. "> has conflicting coalition, group and unit, use only one.", 30)
	end
	
	-- flag whose value can be read: to be deprecated
	if cfxZones.hasProperty(theZone, "messageValue?") then 
		theZone.messageValue = cfxZones.getStringFromZoneProperty(theZone, "messageValue?", "<none>") 
	end
	
	-- time format for new <t: flagname>
	theZone.msgTimeFormat = cfxZones.getStringFromZoneProperty(theZone, "timeFormat", "<:h>:<:m>:<:s>")
	
	theZone.imperialUnits = cfxZones.getBoolFromZoneProperty(theZone, "imperial", false)
	if cfxZones.hasProperty(theZone, "imperialUnits") then 
		theZone.imperialUnits = cfxZones.getBoolFromZoneProperty(theZone, "imperialUnits", false)
	end
	
	theZone.errString = cfxZones.getStringFromZoneProperty(theZone, "error", "")
	if cfxZones.hasProperty(theZone, "messageError") then 
		theZone.errString = cfxZones.getStringFromZoneProperty(theZone, "messageError", "")
	end
	
	-- possible responses for mapping
	if cfxZones.hasProperty(theZone, "responses") then 
		local resp = cfxZones.getStringFromZoneProperty(theZone, "responses", "none")
		theZone.msgResponses = dcsCommon.string2Array(resp, ",")
	end
	
	if messenger.verbose or theZone.verbose then 
		trigger.action.outText("+++Msg: new zone <".. theZone.name .."> will say <".. theZone.message .. ">", 30)
	end
end

--
-- Update 
--
function messenger.getMessage(theZone)
	local msg = theZone.message
	-- see if it has a "$val" in there 
	local zName = theZone.name 
	if not zName then zName = "<strange!>" end 
	local zVal = "<n/a>"
	if theZone.messageValue then 
		zVal = cfxZones.getFlagValue(theZone.messageValue, theZone)
		zVal = tostring(zVal)
		if not zVal then zVal = "<err>" end 
	end 
	
	
	-- replace *zone and *value wildcards 
	--msg = string.gsub(msg, "*name", zName)-- deprecated
	--msg = string.gsub(msg, "*value", zVal) -- deprecated
	-- old-school <v> to provide value from messageValue
	msg = string.gsub(msg, "<v>", zVal) 
	local z = tonumber(zVal)
	if not z then z = 0 end  
	msg = dcsCommon.processHMS(msg, z)
	
	-- process <t> [classic format], <latlon> and <mrgs>
	msg = messenger.dynamicProcessClassic(msg, theZone)
	
	-- now add new processing of <x: flagname> access
	msg = messenger.dynamicFlagProcessing(msg, theZone)
	
	-- now add new processinf of <lat: flagname> 
	-- also handles <lon:x>, <ele:x>, <mgrs:x>
	return msg 
end

function messenger.isTriggered(theZone)
	-- this module has triggered 
	if theZone.messageOff then 
		if messenger.verbose or theZone.verbose then 
			trigger.action.outFlag("msg: message for <".. theZone.name .."> is OFF",30)
		end
		return 
	end
	
	local fileName = "l10n/DEFAULT/" .. theZone.soundFile
	local msg = messenger.getMessage(theZone)
	if messenger.verbose or theZone.verbose then 
		trigger.action.outText("+++Msg: <".. theZone.name .."> will say <".. msg .. ">", 30)
	end
	
	if theZone.spaceBefore then msg = "\n"..msg end 
	if theZone.spaceAfter then msg = msg .. "\n" end 
	
	if theZone.msgCoalition then 
		trigger.action.outTextForCoalition(theZone.msgCoalition, msg, theZone.duration, theZone.clearScreen)
		trigger.action.outSoundForCoalition(theZone.msgCoalition, fileName)
	elseif theZone.msgGroup then 
		local theGroup = Group.getByName(theZone.msgGroup)
		if theGroup and Group.isExist(theGroup) then 
			local ID = theGroup:getID()
			msg = messenger.dynamicGroupProcessing(msg, theZone, theGroup)
			trigger.action.outTextForGroup(ID, msg, theZone.duration, theZone.clearScreen)
			trigger.action.outSoundForGroup(ID, fileName)
		end
	elseif theZone.msgUnit then 
		local theUnit = Unit.getByName(theZone.msgUnit)
		if theUnit and Unit.isExist(theUnit) then 
			local ID = theUnit:getID()
			msg = messenger.dynamicUnitProcessing(msg, theZone, theUnit)
			trigger.action.outTextForUnit(ID, msg, theZone.duration, theZone.clearScreen)
			trigger.action.outSoundForUnit(ID, fileName)
		end
	else 
		-- out to all 
		trigger.action.outText(msg, theZone.duration, theZone.clearScreen)
		trigger.action.outSound(fileName)
	end
end

function messenger.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(messenger.update, {}, timer.getTime() + 1)
		
	for idx, aZone in pairs(messenger.messengers) do
		-- make sure to re-start before reading time limit
		-- new trigger code 
		if cfxZones.testZoneFlag(aZone, aZone.triggerMessagerFlag, aZone.msgTriggerMethod, 			"lastMessageTriggerValue") then 
			if messenger.verbose or aZone.verbose then 
					trigger.action.outText("+++msgr: triggered on in? for <".. aZone.name ..">", 30)
				end
			messenger.isTriggered(aZone)
		end 
		
		-- old trigger code 		
		if cfxZones.testZoneFlag(aZone, aZone.messageOffFlag, aZone.msgTriggerMethod, "lastMessageOff") then 
			aZone.messageOff = true
			if messenger.verbose or aZone.verbose then 
				trigger.action.outText("+++msg: messenger <" .. aZone.name .. "> turned ***OFF***", 30)
			end 
		end
		
		if cfxZones.testZoneFlag(aZone, 				aZone.messageOnFlag, aZone.msgTriggerMethod, "lastMessageOn") then 
			aZone.messageOff = false
			if messenger.verbose or aZone.verbose then 
				trigger.action.outText("+++msg: messenger <" .. aZone.name .. "> turned ON", 30)
			end
		end
	end
end

--
-- Config & Start
--
function messenger.readConfigZone()
	local theZone = cfxZones.getZoneByName("messengerConfig") 
	if not theZone then 
		if messenger.verbose then 
			trigger.action.outText("+++msgr: NO config zone!", 30)
		end 
		theZone =  cfxZones.createSimpleZone("messengerConfig")
	end 
	
	messenger.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if messenger.verbose then 
		trigger.action.outText("+++msgr: read config", 30)
	end 
end

function messenger.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Messenger requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Messenger", messenger.requiredLibs) then
		return false 
	end
	
	-- read config 
	messenger.readConfigZone()
	
	-- process messenger Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("messenger")
	for k, aZone in pairs(attrZones) do 
		messenger.createMessengerWithZone(aZone) -- process attributes
		messenger.addMessenger(aZone) -- add to list
	end
	
	-- new style that saves messageOut? flag by reading flags
	attrZones = cfxZones.getZonesWithAttributeNamed("messenger?")
	for k, aZone in pairs(attrZones) do 
		messenger.createMessengerWithZone(aZone) -- process attributes
		messenger.addMessenger(aZone) -- add to list
	end
	
	-- start update 
	messenger.update()
	
	trigger.action.outText("cfx Messenger v" .. messenger.version .. " started.", 30)
	return true 
end

-- let's go!
if not messenger.start() then 
	trigger.action.outText("cfx Messenger aborted: missing libraries", 30)
	messenger = nil 
end

--[[--

  
--]]--