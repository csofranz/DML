xFlags = {}
xFlags.version = "2.0.0"
xFlags.verbose = false 
xFlags.hiVerbose = false 
xFlags.ups = 1 -- overwritten in get config when configZone is present
xFlags.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
	xFlags - flag array transmogrifier
	
	Version History 
	2.0.0 - dmlZones
		  - OOP 
		  - xDirect#
		  - xCount#
		  - cleanup 
--]]--
xFlags.xFlagZones = {}

function xFlags.addxFlags(theZone)
	table.insert(xFlags.xFlagZones, theZone)
end
--
-- create xFlag 
--
function xFlags.reset(theZone)
	theZone.flagChecksum = "" -- reset checksum
	for i = 1, #theZone.flagNames do 
		-- since the checksum is order dependent, 
		-- we must preserve the order of the array
		local flagName = theZone.flagNames[i]
		theZone.startFlagValues[i] = cfxZones.getFlagValue(flagName, theZone)
		theZone.flagResults[i] = false 
		theZone.flagChecksum = theZone.flagChecksum .. "0"
		if xFlags.verbose or theZone.verbose then 
			trigger.action.outText("+++xF: zone <" .. theZone.name  .. "> flag " .. flagName, 30)
		end 
	end
	theZone.xHasFired = false 
end

function xFlags.createXFlagsWithZone(theZone)
	local theArray = ""
	theArray = theZone:getStringFromZoneProperty("xFlags?", "<none>")
	
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
		if xFlags.verbose or theZone.verbose then 
			trigger.action.outText("+++xFlag: <" .. theZone.name .. "> monitors flag " .. flagName, 30)
		end 
	end
	theZone.xHasFired = false 
	if theZone:hasProperty("xSuccess!") then
		theZone.xSuccess = theZone:getStringFromZoneProperty("xSuccess!", "<none>")
	elseif theZone:hasProperty("out!") then
		theZone.xSuccess = theZone:getStringFromZoneProperty("out!", "*<none>")
	end
	
	if not theZone.xSuccess then 
		theZone.xSuccess = "*<none>" 
	end 
	
	if theZone:hasProperty("xChange!") then 
		theZone.xChange = theZone:getStringFromZoneProperty("xChange!", "*<none>")
	end 
	
	if theZone:hasProperty("xDirect#") then 
		theZone.xDirect = theZone:getStringFromZoneProperty("xDirect#", "*<none>") 
	end 
	
	if theZone:hasProperty("xCount#") then 
		theZone.xCount = theZone:getStringFromZoneProperty("xCount#", "*<none>") 
	end 
	
	theZone.inspect = theZone:getStringFromZoneProperty("require", "or") -- same as any 
	-- supported any/or, all/and, moreThan, atLeast, exactly 
	theZone.inspect = string.lower(theZone.inspect)
	theZone.inspect = dcsCommon.trim(theZone.inspect)
	
	theZone.matchNum = theZone:getStringFromZoneProperty("#hits", "1") -- string because can also be a flag ref 
	
	theZone.xTriggerMethod = theZone:getStringFromZoneProperty( "xFlagMethod", "change") 
		
	theZone.xTriggerMethod = string.lower(theZone.xTriggerMethod)
	theZone.xTriggerMethod = dcsCommon.trim(theZone.xTriggerMethod)
	
	if theZone:hasProperty("xReset?") then 
		theZone.xReset = theZone:getStringFromZoneProperty("xReset?", "<none>")
		theZone.xLastReset = theZone:getFlagValue(theZone.xReset)
	end 
	
	theZone.xMethod = theZone:getStringFromZoneProperty("xMethod", "inc")
	if theZone:hasProperty("method") then 
		theZone.xMethod = theZone:getStringFromZoneProperty("method", "inc")
	end
	
	theZone.xOneShot = theZone:getBoolFromZoneProperty("oneShot", true)
	
	-- on / off commands
	-- on/off flags
	theZone.xSuspended = theZone:getBoolFromZoneProperty("xSuspended", false) -- we are turned on 
	if theZone.xSuspended and (xFlags.verbose or theZone.verbose) then 
		trigger.action.outText("+++xFlg: <" .. theZone.name .. "> starts suspended", 30)
	end
	
	if theZone:hasProperty("xOn?") then 
		theZone.xtriggerOnFlag = theZone:getStringFromZoneProperty("xOn?", "*<none1>")
		theZone.xlastTriggerOnValue = theZone:getFlagValue(theZone.xtriggerOnFlag)
	end
	if theZone:hasProperty("xOff?") then 
		theZone.xtriggerOffFlag = theZone:getStringFromZoneProperty( "xOff?", "*<none2>")
		theZone.xlastTriggerOffValue = theZone:getFlagValue(theZone.xtriggerOffFlag)
	end
end

function xFlags.evaluateNumOrFlag(theAttribute, theZone)

	return cfxZones.evalRemainder(theAttribute, theZone)
end

function xFlags.evaluateFlags(theZone)
	local currVals = {}
	-- read new values 
	for i = 1, #theZone.flagNames do 
		-- since the checksum is order dependent, 
		-- we must preserve the order of the array
		local flagName = theZone.flagNames[i]
		currVals[i] = theZone:getFlagValue(flagName)
	end
	
	-- now perform comparison flag by flag 
	local op = theZone.xTriggerMethod
	local hits = 0
	local checkSum = ""
	local firstChar = string.sub(op, 1, 1) 
	local remainder = string.sub(op, 2)
	remainder = dcsCommon.trim(remainder) -- remove all leading and trailing spaces

	local rNum = theZone:evalRemainder(remainder)
	
	-- the following mimics cfxZones.testFlagByMethodForZone method (and is 
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
		elseif op == "on" or op == "yes" or op == "true" or op == "1" then 
			if currVals[i] ~= 0 then 
				hits = hits + 1 
				checkSum = checkSum .. "X"
			else 
				checkSum = checkSum .. "0"
			end 
		elseif op == "off" or op == "no" or op == "false" or op == "0"
		then 
			if currVals[i] == 0 then 
				hits = hits + 1 
				checkSum = checkSum .. "X"
			else 
				checkSum = checkSum .. "0"
			end
		
		elseif op == "inc" or op == "+1" then 
			if currVals[i] == theZone.startFlagValues[i] + 1 then 
				hits = hits + 1 
				checkSum = checkSum .. "X"
			else 
				checkSum = checkSum .. "0"
			end 
		
		elseif op == "dec" or op == "-1" then 
			if currVals[i] == theZone.startFlagValues[i] - 1 then 
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
			trigger.action.outText("+++xF: unknown xFlagMethod: <" .. op .. ">", 30)
			return 0, ""
		end
		if xFlags.verbose and lastHits ~= hits then 
		end 
	end
	return hits, checkSum
end

function xFlags.evaluateZone(theZone)
	
	-- short circuit if we are done 
	if theZone.xHasFired and theZone.xOneShot then return end 
	-- calculate matchNum
	local matchNum = xFlags.evaluateNumOrFlag(theZone.matchNum, theZone) -- convert or fetch
	
	local hits, checkSum = xFlags.evaluateFlags(theZone)
	-- depending on inspect see what the outcome is 
	-- supported any/or, all/and, moreThan, atLeast, exactly
	-- if require = "never", we never trigger 
	local op = theZone.inspect
	local evalResult = false 
	if (op == "or" or op == "any" or op == "some") then 
		if hits > 0 then evalResult = true end  
	elseif (op == "and" or op == "all") then 
		if hits == #theZone.flagNames then evalResult = true end 
		
	elseif (op == "morethan" or op == "more than") then 
		if hits > matchNum then evalResult = true end 
		
	elseif (op == "atleast" or op == "at least") then 
		if hits >= matchNum then evalResult = true end 
		
	elseif op == "exactly" then 
		if hits == matchNum then evalResult = true end 
		
	elseif (op == "none" or op == "nor") then 
		if hits == 0 then evalResult = true end 
		
	elseif (op == "not all" or op == "notall" or op == "nand") then 
		if hits < #theZone.flagNames then evalResult = true end 
		
	elseif (op == "most") then 
		if hits > (#theZone.flagNames / 2) then evalResult = true end 
		
	elseif (op == "half" or op == "at least half" or op == "half or more") then 
		if hits >= (#theZone.flagNames / 2) then 
			-- warning: 'half' means really 'at least half"
			evalResult = true 
		end 
		
	elseif op == "never" then 
		evalResult = false -- not required, just to be explicit 
	else 
		trigger.action.outText("+++xFlg: WARNING: <" .. theZone.name .. "> has unknown requirement: <" .. op .. ">", 30)
	end

		-- add "most" to more than 50% of flagnum 

		-- now check if changed and if result true 	
	if checkSum ~= theZone.flagChecksum then 
		if xFlags.verbose or theZone.verbose then 
			trigger.action.outText("+++xFlag: change detected for " .. theZone.name .. ": " .. theZone.flagChecksum .. "-->" ..checkSum, 30)
		end
		
		if theZone.xChange then 
			theZone:pollFlag(theZone.xChange, theZone.xMethod)
			if xFlags.verbose then 
				trigger.action.outText("+++xFlag: change bang! on " .. theZone.xChange .. " for " .. theZone.name, 30)
			end
		end
		theZone.flagChecksum = checkSum
	else 
		if xFlags.hiVerbose and (xFlags.verbose or theZone.verbose) then 
			trigger.action.outText("+++xFlag: no change, checksum is |" .. checkSum .. "| for <" .. theZone.name .. ">", 10)
		end
	end
	
	-- now directly set the value of evalResult (0 = false, 1 = true) 
	-- to "xDirect". Always sets output to current result of evaluation
	-- true (1)/false(0), no matter if changed or not  
	if theZone.xDirect then 
		if evalResult then 
			theZone:setFlagValue(theZone.xDirect, 1)
		else 
			theZone:setFlagValue(theZone.xDirect, 0)
		end 
	end
	
	-- directly set the xCount flag 
	if theZone.xCount then 
		theZone:setFlagValueMult(theZone.xCount, hits)
	end
	
	-- now see if we bang the output according to method 
	if evalResult then 
		if xFlags.verbose or theZone.verbose then 
			trigger.action.outText("+++xFlag: success bang! on <" .. theZone.xSuccess .. "> for <" .. theZone.name .. "> with method <" .. theZone.xMethod .. ">", 30)
		end
		theZone:pollFlag(theZone.xSuccess, theZone.xMethod)
		theZone.xHasFired = true 
	end
end

--
-- Update 
--
function xFlags.update()
	timer.scheduleFunction(xFlags.update, {}, timer.getTime() + 1/xFlags.ups)
	
	for idx, theZone in pairs (xFlags.xFlagZones) do 
		-- see if we should suspend 
		if theZone.xtriggerOnFlag and theZone:testZoneFlag( theZone.xtriggerOnFlag, "change", "xlastTriggerOnValue") then 
			if xFlags.verbose or theZone.verbose then 
				trigger.action.outText("+++xFlg: enabling " .. theZone.name, 30)
			end 
			theZone.xSuspended = false 
		end
		
		if theZone.xtriggerOffFlag and theZone:testZoneFlag( theZone.xtriggerOffFlag, "change", "xlastTriggerOffValue") then 
			if xFlags.verbose or theZone.verbose then 
				trigger.action.outText("+++xFlg: DISabling " .. theZone.name, 30)
			end 
			theZone.xSuspended = true 
		end
		
		-- see if they should fire 
		if not theZone.xSuspended then 
			xFlags.evaluateZone(theZone)
		end
		
		-- see if they should reset 
		if theZone.xReset then 
			local currVal = theZone:getFlagValue(theZone.xReset)
			if currVal ~= theZone.xLastReset then 
				theZone.xLastReset = currVal
				if xFlags.verbose or theZone.verbose then 
					trigger.action.outText("+++xFlag: reset command for " .. theZone.name, 30)
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
		theZone = cfxZones.createSimpleZone("xFlagsConfig") 
	end 
	
	xFlags.verbose = theZone.verbose 
	xFlags.ups = theZone:getNumberFromZoneProperty("ups", 1)
	
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

--[[--
	Additional features:
	- make #hits compatible to flags and numbers 
	- autoReset -- can be done by short-circuiting xsuccess! into xReset?
--]]--