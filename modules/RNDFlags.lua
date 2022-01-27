rndFlags = {}
rndFlags.version = "1.0.0"
rndFlags.verbose = false 
rndFlags.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[
	Random Flags: DML module to select flags at random
	and then change them
	
	Copyright 2022 by Christian Franz and cf/x 
	
	Version History
	1.0.0 - Initial Version 

--]]
rndFlags.rndGen = {}

function rndFlags.addRNDZone(aZone)
	table.insert(rndFlags.rndGen, aZone)
end

function rndFlags.flagArrayFromString(inString)
	if string.len(inString) < 1 then 
		trigger.action.outText("+++RND: empty flags", 30)
		return {} 
	end
	if rndFlags.verbose then 
		trigger.action.outText("+++RND: processing <" .. inString .. ">", 30)
	end 
	
	local flags = {}
	local rawElements = dcsCommon.splitString(inString, ",")

	for idx, anElement in pairs(rawElements) do 
		if dcsCommon.containsString(anElement, "-") then 
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
					table.insert(flags, f)
					--trigger.action.outText("+++RND: added <" .. f .. "> (range)", 30)
				end
			else
				-- bounds illegal
				trigger.action.outText("+++RND: ignored range <" .. anElement .. "> (range)", 30)
			end
		else
			-- single number
			f = tonumber(anElement)
			if f then 
				table.insert(flags, f)
				--trigger.action.outText("+++RND: added <" .. f .. "> (single)", 30)
			else 
				trigger.action.outText("+++RND: ignored element <" .. anElement .. "> (single)", 30)
			end
		end
	end
	if rndFlags.verbose then 
		trigger.action.outText("+++RND: <" .. #flags .. "> flags total", 30)
	end 
	return flags
end

--
-- create rnd gen from zone 
--
function rndFlags.createRNDWithZone(theZone)
	local flags = cfxZones.getStringFromZoneProperty(theZone, "flags!", "")
	if flags == "" then 
		-- let's try alternate spelling without "!"
		flags = cfxZones.getStringFromZoneProperty(theZone, "flags", "") 
	end 
	-- now build the flag array from strings
	local theFlags = rndFlags.flagArrayFromString(flags)
	theZone.myFlags = theFlags


	theZone.pollSizeMin, theZone.pollSize = cfxZones.getPositiveRangeFromZoneProperty(theZone, "pollSize", 1)
	if rndFlags.verbose then 
		trigger.action.outText("+++RND: pollSize is <" .. theZone.pollSizeMin .. ", " .. theZone.pollSize .. ">", 30)
	end
			 
	
	theZone.remove = cfxZones.getBoolFromZoneProperty(theZone, "remove", false)

	-- trigger flag 
	if cfxZones.hasProperty(theZone, "f?") then 
		theZone.triggerFlag = cfxZones.getStringFromZoneProperty(theZone, "f?", "none")
	end
	
	if theZone.triggerFlag then 
		theZone.lastTriggerValue = trigger.misc.getUserFlag(theZone.triggerFlag) -- save last value
	end
	
	theZone.onStart = cfxZones.getBoolFromZoneProperty(theZone, "onStart", false)
	
	if not theZone.onStart and not theZone.triggerFlag then 
		theZone.onStart = true 
	end
	
	theZone.method = cfxZones.getStringFromZoneProperty(theZone, "method", "on")
	
	theZone.reshuffle = cfxZones.getBoolFromZoneProperty(theZone, "reshuffle", false)
	if theZone.reshuffle then 
		-- create a backup copy we can reshuffle from 
		theZone.flagStore = dcsCommon.copyArray(theFlags)
	end
	
	--theZone.rndPollSize = cfxZones.getBoolFromZoneProperty(theZone, "rndPollSize", false)
	
	-- done flag 
	if cfxZones.hasProperty(theZone, "done+1") then 
		theZone.doneFlag = cfxZones.getStringFromZoneProperty(theZone, "done+1", "none")
	end
end

function rndFlags.reshuffle(theZone)
	if rndFlags.verbose then 
		trigger.action.outText("+++RND: reshuffling zone " .. theZone.name, 30)
	end
	theZone.myFlags = dcsCommon.copyArray(theZone.flagStore)
end

--
-- fire RND
-- 
function rndFlags.pollFlag(theFlag, method) 
	if rndFlags.verbose then 
		trigger.action.outText("+++RND: polling flag " .. theFlag .. " with " .. method, 30)
	end 
	
	method = method:lower()
	local currVal = trigger.misc.getUserFlag(theFlag)
	if method == "inc" or method == "f+1" then 
		trigger.action.setUserFlag(theFlag, currVal + 1)
		
	elseif method == "dec" or method == "f-1" then 
		trigger.action.setUserFlag(theFlag, currVal - 1)
		
	elseif method == "off" or method == "f=0" then 
		trigger.action.setUserFlag(theFlag, 0)
		
	elseif method == "flip" or method == "xor" then 
		if currVal ~= 0 then 
			trigger.action.setUserFlag(theFlag, 0)
		else 
			trigger.action.setUserFlag(theFlag, 1)
		end
		
	else 
		if method ~= "on" and method ~= "f=1" then 
			trigger.action.outText("+++RND: unknown method <" .. method .. "> - using 'on'", 30)
		end
		-- default: on.
		trigger.action.setUserFlag(theFlag, 1)
	end
	
	local newVal = trigger.misc.getUserFlag(theFlag)
	if rndFlags.verbose then
		trigger.action.outText("+++RND: flag <" .. theFlag .. "> changed from " .. currVal .. " to " .. newVal, 30)
	end 
end

function rndFlags.fire(theZone) 
	-- fire this rnd 
	-- create a local copy of all flags 
	if theZone.reshuffle and #theZone.myFlags < 1 then 
		rndFlags.reshuffle(theZone)
	end
	
	local availableFlags = dcsCommon.copyArray(theZone.myFlags)--{}
--	for idx, aFlag in pairs(theZone.myFlags) do 
--		table.insert(availableFlags, aFlag)
--	end
	
	-- do this pollSize times 
	local pollSize = theZone.pollSize
	local pollSizeMin = theZone.pollSizeMin
	
	if pollSize ~= pollSizeMin then 
		-- pick random in range , say 3-7 --> 5 items!
		pollSize = (pollSize - pollSizeMin) + 1 -- 7-3 + 1
		pollSize = dcsCommon.smallRandom(pollSize) - 1 --> 0-4
--		trigger.action.outText("+++RND: RAW pollsize " ..  pollSize, 30)
		pollSize = pollSize + pollSizeMin 
--		trigger.action.outText("+++RND: adj pollsize " ..  pollSize, 30)
		if pollSize > theZone.pollSize then pollSize = theZone.pollSize end 
		if pollSize < 1 then pollSize = 1 end 
		
		if rndFlags.verbose then 
			trigger.action.outText("+++RND: RND " .. theZone.name .. " range " .. pollSizeMin .. "-" .. theZone.pollSize .. ": selected " .. pollSize, 30)
		end
	end
	
	if #availableFlags < 1 then 
		if rndFlags.verbose then 
			trigger.action.outText("+++RND: RND " .. theZone.name .. " ran out of flags. aborting fire", 30)
		end
		
		if theZone.doneFlag then 
			local currVal = trigger.misc.getUserFlag(theZone.doneFlag)
			trigger.action.setUserFlag(theZone.doneFlag, currVal + 1)
		end
		
		return 
	end
	
	if rndFlags.verbose then 
		trigger.action.outText("+++RND: firing RND " .. theZone.name .. " with pollsize " .. pollSize .. " on " .. #availableFlags .. " set size", 30)
	end
	
	for i=1, pollSize do 
		-- check there are still flags left 
		if #availableFlags < 1 then 
			trigger.action.outText("+++RND: no flags left in " .. theZone.name .. " in index " .. i, 30)
			theZone.myFlags = {} 
			if theZone.reshuffle then 
				rndFlags.reshuffle(theZone)
			end
			return 
		end
		
		-- select a flag, enforce uniqueness
		local theFlagIndex = dcsCommon.smallRandom(#availableFlags)
		
		-- poll this flag and remove from available
		local theFlag = table.remove(availableFlags,theFlagIndex)
		
		rndFlags.pollFlag(theFlag, theZone.method)
		 
	end
	
	-- remove if requested
	if theZone.remove then 
		theZone.myFlags = availableFlags
	end
end

--
-- update 
--
function rndFlags.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(rndFlags.update, {}, timer.getTime() + 1)
	
	for idx, aZone in pairs(rndFlags.rndGen) do
		if aZone.triggerFlag then 
			local currTriggerVal = trigger.misc.getUserFlag(aZone.triggerFlag)
			if currTriggerVal ~= aZone.lastTriggerValue
			then 
				if rndFlags.verbose then 
					trigger.action.outText("+++RND: triggering " .. aZone.name, 30)
				end 
				rndFlags.fire(aZone)
				aZone.lastTriggerValue = currTriggerVal
			end

		end
	end
end

--
-- start cycle: force all onStart to fire 
--
function rndFlags.startCycle()
	for idx, theZone in pairs(rndFlags.rndGen) do
		if theZone.onStart then 
			trigger.action.outText("+++RND: starting " .. theZone.name, 30)
			rndFlags.fire(theZone)
		end
	end
end


--
-- start module and read config 
--
function rndFlags.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("rndFlagsConfig") 
	if not theZone then 
		if rndFlags.verbose then 
			trigger.action.outText("***RND: NO config zone!", 30)
		end 
		return 
	end 
	
	rndFlags.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if rndFlags.verbose then 
		trigger.action.outText("***RND: read config", 30)
	end 
end

function rndFlags.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("RNDFlags requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Random Flags", 
		rndFlags.requiredLibs) then
		return false 
	end
	
	-- read config 
	rndFlags.readConfigZone()
	
	-- process RND Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("RND")
	
	-- now create an rnd gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		rndFlags.createRNDWithZone(aZone) -- process attribute and add to zone
		rndFlags.addRNDZone(aZone) -- remember it so we can smoke it
	end
	
	-- start cycle 
	timer.scheduleFunction(rndFlags.startCycle, {}, timer.getTime() + 0.25)
	
	-- start update 
	timer.scheduleFunction(rndFlags.update, {}, timer.getTime() + 1)
	
	trigger.action.outText("cfx random Flags v" .. rndFlags.version .. " started.", 30)
	return true 
end

-- let's go!
if not rndFlags.start() then 
	trigger.action.outText("cf/x RND Flags aborted: missing libraries", 30)
	rndFlags = nil 
end

--[[
pulser / repeat until  
--]]