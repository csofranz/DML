xFlags = {}
xFlags.version = "1.2.0"
xFlags.verbose = false 
xFlags.ups = 1 -- overwritten in get config when configZone is present
xFlags.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
	xFlags - flag array transmogrifier
	
	Version History 
	1.0.0 - Initial version 
	1.0.1 - allow flags names for ops as well 
	1.1.0 - Watchflags harmonization 
	1.2.0 - xDirect flag, 
	      - direct array support  
	
--]]--
xFlags.xFlagZones = {}

function xFlags.addxFlags(theZone)
	table.insert(xFlags.xFlagZones, theZone)
end
--
-- create xFlag 
--
function xFlags.reset()
	for i = 1, #theZone.flagNames do 
		-- since the checksum is order dependent, 
		-- we must preserve the order of the array
		local flagName = theZone.flagNames[i]
		theZone.startFlagValues[i] = cfxZones.getFlagValue(flagName, theZone)
		theZone.flagResults[i] = false 
		theZone.flagChecksum = theZone.flagChecksum .. "0"
		trigger.action.outText("+++xF: flag " .. flagName, 30)
	end
	theZone.xHasFired = false 
end

function xFlags.createXFlagsWithZone(theZone)
	local theArray = ""
	if cfxZones.hasProperty(theZone, "xFlags") then  
		theArray = cfxZones.getStringFromZoneProperty(theZone, "xFlags", "<none>")
	else 
		theArray = cfxZones.getStringFromZoneProperty(theZone, "xFlags?", "<none>")
	end
	
	-- now process the array and create the value arrays
	theZone.flagNames = cfxZones.flagArrayFromString(theArray)
	theZone.startFlagValues = {} -- reference/reset time we read these 
	theZone.flagResults = {} -- individual flag check result
	theZone.flagChecksum = "" -- to detect change. is either '0' or 'X'
	
	for i = 1, #theZone.flagNames do 
		-- since the checksum is order dependent, 
		-- we must preserve the order of the array
		local flagName = theZone.flagNames[i]
		theZone.startFlagValues[i] = cfxZones.getFlagValue(flagName, theZone)
		theZone.flagResults[i] = false 
		theZone.flagChecksum = theZone.flagChecksum .. "0"
		trigger.action.outText("+++xF: flag " .. flagName, 30)
	end
	theZone.xHasFired = false 
	
	theZone.xSuccess = cfxZones.getStringFromZoneProperty(theZone, "xSuccess!", "<none>")
	
	if cfxZones.hasProperty(theZone, "out!") then
		theZone.xSuccess = cfxZones.getStringFromZoneProperty(theZone, "out!", "*<none>")
	end
	
	if cfxZones.hasProperty(theZone, "xChange!") then 
		theZone.xChange = cfxZones.getStringFromZoneProperty(theZone, "xChange!", "*<none>")
	end 
	
	theZone.xDirect = cfxZones.getStringFromZoneProperty(theZone, "xDirect!", "*<none>") 
	
	theZone.inspect = cfxZones.getStringFromZoneProperty(theZone, "require", "or") -- same as any 
	-- supported any/or, all/and, moreThan, atLeast, exactly 
	theZone.inspect = string.lower(theZone.inspect)
	theZone.inspect = dcsCommon.trim(theZone.inspect)
	
	theZone.matchNum = cfxZones.getNumberFromZoneProperty(theZone, "#hits", 0)
	
	theZone.xTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "xTriggerMethod", "change") -- (<>=[number or reference flag], off, on, yes, no, true, false, change
	if cfxZones.hasProperty(theZone, "xTrigger") then 
		theZone.xTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "xTrigger", "change")
	end 
	
	theZone.xTriggerMethod = string.lower(theZone.xTriggerMethod)
	theZone.xTriggerMethod = dcsCommon.trim(theZone.xTriggerMethod)
	
	if cfxZones.hasProperty(theZone, "xReset?") then 
		theZone.xReset = cfxZones.getStringFromZoneProperty(theZone, "xReset?", "<none>")
		theZone.xLastReset = cfxZones.getFlagValue(theZone.xReset, theZone)
	end 
	
	theZone.xMethod = cfxZones.getStringFromZoneProperty(theZone, "xMethod", "inc")
	if cfxZones.hasProperty(theZone, "method") then 
		theZone.xMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	end
	
	theZone.xOneShot = cfxZones.getBoolFromZoneProperty(theZone, "oneShot", true)
	
	
	
end

function xFlags.evaluateFlags(theZone)
	local currVals = {}
	-- read new values 
	for i = 1, #theZone.flagNames do 
		-- since the checksum is order dependent, 
		-- we must preserve the order of the array
		local flagName = theZone.flagNames[i]
		currVals[i] = cfxZones.getFlagValue(flagName, theZone)
	end
	
	-- now perform comparison flag by flag 
	local op = theZone.xTriggerMethod
	local hits = 0
	local checkSum = ""
	local firstChar = string.sub(op, 1, 1) 
	local remainder = string.sub(op, 2)
	local rNum = tonumber(remainder)
	if not rNum then 
		-- interpret remainder as flag name 
		-- so we can say >*killMax
		rNum = cfxZones.getFlagValue(remainder, theZone)
	end 
	
	-- this mimics cfxZones.testFlagByMethodForZone method (and is 
    -- that method's genesis), but is different enough not to invoke that 
	-- method 
	for i = 1, #theZone.flagNames do 
		local lastHits = hits 
		if op == "change" then 
			-- look for a change in flag line 
			if currVals[i] ~= theZone.startFlagValues[i] then 
				hits = hits + 1 
				checkSum = checkSum .. "X"
			else 
				checkSum = checkSum .. "0"
			end 
		elseif op == "on" or op == "yes" or op == "true" then 
			if currVals[i] ~= 0 then 
				hits = hits + 1 
				checkSum = checkSum .. "X"
			else 
				checkSum = checkSum .. "0"
			end 
		elseif op == "off" or op == "no" or op == "false" 
		then 
			if currVals[i] == 0 then 
				hits = hits + 1 
				checkSum = checkSum .. "X"
			else 
				checkSum = checkSum .. "0"
			end
		
		elseif firstChar == "<" and rNum then 
			if currVals[i] < rNum then 
				hits = hits + 1 
				checkSum = checkSum .. "X"
			else 
				checkSum = checkSum .. "0"
			end
		
		elseif firstChar == "=" and rNum then 
			if currVals[i] == rNum then 
				hits = hits + 1 
				checkSum = checkSum .. "X"
			else 
				checkSum = checkSum .. "0"
			end

		elseif firstChar == ">" and rNum then 
			if currVals[i] > rNum then 
				hits = hits + 1 
				checkSum = checkSum .. "X"
			else 
				checkSum = checkSum .. "0"
			end

		else 
			trigger.action.outText("+++xF: unknown xTriggerMethod: <" .. op .. ">", 30)
			return 0, ""
		end
		if xFlags.verbose and lastHits ~= hits then 
			--trigger.action.outText("+++xF: hit detected for " .. theZone.flagNames[i] .. " in " .. theZone.name .. "(" .. op .. ")", 30)
		end 
	end
	return hits, checkSum
end

function xFlags.evaluateZone(theZone)
	
	-- short circuit if we are done 
	if theZone.xHasFired and theZone.xOneShot then return end 

	local hits, checkSum = xFlags.evaluateFlags(theZone)
	-- depending on inspect see what the outcome is 
	-- supported any/or, all/and, moreThan, atLeast, exactly
	local op = theZone.inspect
	local evalResult = false 
	if (op == "or" or op == "any" or op == "some") and hits > 0 then 
		evalResult = true 
	elseif (op == "and" or op == "all") and hits == #theZone.flagNames then 
		evalResult = true 
	elseif (op == "morethan" or op == "more than") and hits > theZone.matchNum then 
		evalResult = true 
	elseif (op == "atleast" or op == "at least") and hits >= theZone.matchNum then
		evalResult = true 
	elseif op == "exactly" and hits == theZone.matchNum then 
		evalResult = true 
	elseif (op == "none" or op == "nor") and hits == 0 then 
		evalResult = true 
	elseif (op == "not all" or op == "notall" or op == "nand") and hits < #theZone.flagNames then 
		evalResult = true 
	end

	-- now check if changed and if result true 
	if checkSum ~= theZone.flagChecksum then 
		if xFlags.verbose then 
			trigger.action.outText("+++xFlag: change detected for " .. theZone.name .. ": " .. theZone.flagChecksum .. "-->" ..checkSum, 30)
		end
		
		if theZone.xChange then 
			cfxZones.pollFlag(theZone.xChange, theZone.xMethod, theZone)
			if xFlags.verbose then 
				trigger.action.outText("+++xFlag: change bang! on " .. theZone.xChange .. " for " .. theZone.name, 30)
			end
		end
		theZone.flagChecksum = checkSum
	end
	
	-- now directly set the value of evalResult (0 = false, 1 = true) 
	-- to "xDirect!". Always sets output to current result of evaluation
	-- true (1)/false(0), no matter if changed or not  
	
	if evalResult then 
		cfxZones.setFlagValueMult(theZone.xDirect, 1, theZone)
	else 
		cfxZones.setFlagValueMult(theZone.xDirect, 0, theZone)
	end 
	
	-- now see if we bang the output according to method 
	if evalResult then 
		if xFlags.verbose then 
			trigger.action.outText("+++xFlag: success bang! on " .. theZone.xSuccess .. " for " .. theZone.name, 30)
		end
		cfxZones.pollFlag(theZone.xSuccess, theZone.xMethod, theZone)
		theZone.xHasFired = true 
	end
end

--
-- Update 
--
function xFlags.update()
	timer.scheduleFunction(xFlags.update, {}, timer.getTime() + 1/xFlags.ups)
	
	for idx, theZone in pairs (xFlags.xFlagZones) do 
		-- see if they should fire 
		xFlags.evaluateZone(theZone)
		
		-- see if they should reset 
		if theZone.xReset then 
			local currVal = cfxZones.getFlagValue(theZone.xReset, theZone)
			if currVal ~= theZone.xLastReset then 
				theZone.xLastReset = currVal
				if xFlags.verbose then 
					trigger.action.outText("+++xF: reset command for " .. theZone.name, 30)
				end 
				xFlags.reset(theZone)
			end 
		end
	end
end
--
-- start 
--
function xFlags.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("xFlagsConfig") 
	if not theZone then 
		if xFlags.verbose then 
			trigger.action.outText("***xFlg: NO config zone!", 30)
		end 
		return 
	end 
	
	xFlags.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	xFlags.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 1)
	
	if xFlags.verbose then 
		trigger.action.outText("***xFlg: read config", 30)
	end 
end

function xFlags.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("xFlags requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx xFlags", 
		xFlags.requiredLibs) then
		return false 
	end
	
	-- read config 
	xFlags.readConfigZone()
	
	-- process RND Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("xFlags")
	
	-- now create an rnd gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		xFlags.createXFlagsWithZone(aZone) -- process attribute and add to zone
		xFlags.addxFlags(aZone) -- remember it 
	end
	
	local attrZones = cfxZones.getZonesWithAttributeNamed("xFlags?")
	
	-- now create an rnd gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		xFlags.createXFlagsWithZone(aZone) -- process attribute and add to zone
		xFlags.addxFlags(aZone) -- remember it 
	end
	
	-- start update 
	timer.scheduleFunction(xFlags.update, {}, timer.getTime() + 1/xFlags.ups)
	
	trigger.action.outText("cfx xFlags v" .. xFlags.version .. " started.", 30)
	return true 
end

-- let's go!
if not xFlags.start() then 
	trigger.action.outText("cf/x xFlags aborted: missing libraries", 30)
	xFlags = nil 
end