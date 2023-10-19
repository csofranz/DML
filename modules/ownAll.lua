ownAll = {}
ownAll.version = "1.0.0"
ownAll.verbose = false 
ownAll.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}

--[[--
VERSION HISTORY
 - 1.0.0 - Initial version 
 
--]]--

ownAll.zones = {}

function ownAll.ownAllForZone(theZone)
	local allZones = theZone:getStringFromZoneProperty("ownAll", "")
	local zVec = dcsCommon.splitString(allZones, ",")
	zVec = dcsCommon.trimArray(zVec)
	local filtered = {}
	for idx, aName in pairs (zVec) do 
		local found = cfxZones.getZoneByName(aName)
		if not found then 
			trigger.action.outText("+++oAll: <" .. theZone.name .. ">: zone <" .. aName .. "> does not exist.", 30)
		else 
			table.insert(filtered, found)
		end
	end
	if #filtered < 2 then 
		trigger.action.outText("+++oAll: WARNING - <" .. theZone.name .. "> has only <" .. #filtered .. "> zones", 30)
	end
	theZone.zones = filtered 
	theZone.ownState = -1 -- not all owned by one 
	if theZone:hasProperty("red!") then 
		theZone.allRed = theZone:getStringFromZoneProperty("red!", "none")
	end
	if theZone:hasProperty("red#") then 
		theZone.redNum = theZone:getStringFromZoneProperty("red#", "none")
	end
	if theZone:hasProperty("blue!") then 
		theZone.allBlue = theZone:getStringFromZoneProperty("blue!", "none")
	end
	if theZone:hasProperty("blue#") then 
		theZone.blueNum = theZone:getStringFromZoneProperty("blue#", "none")
	end
	theZone.method = theZone:getStringFromZoneProperty("method", "inc")
	
	if theZone:hasProperty("total#") then
		theZone.totalNum = theZone:getStringFromZoneProperty("total#", "none")
		theZone:setFlagValue(theZone.totalNum, #filtered)
	end 
	
	theZone.ownershipUplink = theZone:getBoolFromZoneProperty("uplink", true)
	
	local redNum, blueNum
	theZone.state, redNum, blueNum = ownAll.calcState(theZone)
	if theZone.redNum then 
		theZone:setFlagValue(theZone.redNum, redNum)
	end 
	if theZone.blueNum then
		theZone:setFlagValue(theZone.blueNum, blueNum)
	end
	
end

function ownAll.calcState(theZone)
	local redNum = 0 
	local blueNum = 0
	local allSame = true 
	if #theZone.zones < 1 then return -1, 0, 0 end 
	local s = theZone.zones[1].owner
	if not s then 
		trigger.action.outText("+++oAll: zone <" .. theZone.zones[1].name .."> has no owner (?)", 30)
		s = -1
	end
	for idx, aZone in pairs (theZone.zones) do 
		local s2 = aZone.owner
		if not s2 then 
			trigger.action.outText("+++oAll: zone <" .. aZone.name .."> has no owner (?)", 30)
			s2 = -1
		elseif s2 == 1 then 
			redNum = redNum + 1
		elseif s2 == 2 then 
			blueNum = blueNum + 1 
		end -- note: no separate counting for neutral or contested
		if s ~= s2 then allSame = false end 
	end
	local res = s 
	if not allSame then s = -1 end 
	return s, redNum, blueNum
end

function ownAll.update()
	timer.scheduleFunction(ownAll.update, {}, timer.getTime() + 1)
		
	for idx, theZone in pairs(ownAll.zones) do
		local newState, redNum, blueNum = ownAll.calcState(theZone)
		if newState ~= theZone.state then 
			-- all are owned by a different than last time 
			if newState == 1 and theZone.allRed then 
				theZone:pollFlag(theZone.allRed, theZone.method)
			elseif newState == 2 and theZone.allBlue then 
				theZone:pollFlag(theZone.allBlue, theZone.method)
			end
			if theZone.verbose then 
				trigger.action.outText("+++oAll: zone <" .. theZone.name .. "> status changed to <" .. newState .. ">", 30)
			end
			theZone.state = newState
		end
		
		if theZone.ownershipUplink then 
			if theZone.state == 1 or theZone.state == 2 then 
				theZone.owner = theZone.state
			else 
				theZone.owner = 0
			end
		end
		
		if theZone.redNum then 
			theZone:setFlagValue(theZone.redNum, redNum)
		end 
		if theZone.blueNum then
			theZone:setFlagValue(theZone.blueNum, blueNum)
		end
	end
end

function ownAll.readConfigZone()
	local theZone = cfxZones.getZoneByName("ownAllConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("ownAllConfig")
	end 
end

function ownAll.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx ownAlll requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx ownAll", ownAll.requiredLibs) then
		return false 
	end
	
	-- read config 
	ownAll.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("ownAll")
	for k, aZone in pairs(attrZones) do 
		ownAll.ownAllForZone(aZone) -- process attributes
		table.insert(ownAll.zones, aZone) -- add to list
	end
	
	-- start update 
	timer.scheduleFunction(ownAll.update, {}, timer.getTime() + 1)
	
	trigger.action.outText("cfx ownAll v" .. ownAll.version .. " started.", 30)
	return true 
end

-- let's go!
if not ownAll.start() then 
	trigger.action.outText("cfx ownAll aborted: missing libraries", 30)
	ownAll = nil 
end