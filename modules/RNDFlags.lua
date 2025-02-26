rndFlags = {}
rndFlags.version = "2.0.1"
rndFlags.verbose = false 
rndFlags.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[
	Random Flags: DML module to select flags at random
	and then change them
	
	Copyright 2022-2025 by Christian Franz and cf/x 
	
	Version History

	2.0.0 - dmlZones, OOP
	2.0.1 - a little less verbosity 
	
--]]

rndFlags.rndGen = {}

function rndFlags.addRNDZone(aZone)
	table.insert(rndFlags.rndGen, aZone)
end

function rndFlags.getRNDByName(aName)
	for idx, theRND in pairs(rndFlags.rndGen) do 
		if theRND.name == aName then return theRND end 
	end
	return nil
end

function rndFlags.flagArrayFromString(inString)
	return dcsCommon.flagArrayFromString(inString, rndFlags.verbose)
	
end

--
-- create rnd gen from zone 
--
function rndFlags.createRNDWithZone(theZone)
	local flags = ""
	if theZone:hasProperty("RND!") then 
		flags = theZone:getStringFromZoneProperty("RND!", "")
	elseif theZone:hasProperty("flags!") then
		trigger.action.outText("+++RND: warning - zone <" .. theZone.name .. ">: deprecated 'flags!' usage, use 'RND!' instead.", 30)
		flags = theZone:getStringFromZoneProperty("flags!", "")
	elseif theZone:hasProperty("flags") then
		trigger.action.outText("+++RND: warning - zone <" .. theZone.name .. ">: deprecated 'flags' (no bang) usage, use 'RND!' instead.", 30)
		flags = theZone:getStringFromZoneProperty("flags", "")
	else 
		trigger.action.outText("+++RND: warning - zone <" .. theZone.name .. ">: no flags defined!", 30)
	end 
	
	-- now build the flag array from strings
	local theFlags = rndFlags.flagArrayFromString(flags)
	theZone.myFlags = theFlags
	if rndFlags.verbose or theZone.verbose then 
		trigger.action.outText("+++RND: output set for <" .. theZone.name .. "> is <" .. flags .. ">",30)
	end

	theZone.pollSizeMin, theZone.pollSize = theZone:getPositiveRangeFromZoneProperty("pollSize", 1)
	if rndFlags.verbose or theZone.verbose then 
		trigger.action.outText("+++RND: pollSize is <" .. theZone.pollSizeMin .. ", " .. theZone.pollSize .. ">", 30)
	end
			 
	theZone.remove = theZone:getBoolFromZoneProperty("remove", false)
	theZone.rndTriggerMethod = theZone:getStringFromZoneProperty( "triggerMethod", "change")

	if theZone:hasProperty("rndTriggerMethod") then 
		theZone.rndTriggerMethod = theZone:getStringFromZoneProperty("rndTriggerMethod", "change")
	end

	-- trigger flag 
	if theZone:hasProperty("f?") then 
		theZone.triggerFlag = theZone:getStringFromZoneProperty("f?", "none")
	elseif theZone:hasProperty("in?") then 
		theZone.triggerFlag = theZone:getStringFromZoneProperty("in?", "none")
	elseif theZone:hasProperty("rndPoll?") then 
		theZone.triggerFlag = theZone:getStringFromZoneProperty("rndPoll?", "none")
	end
	
	if theZone.triggerFlag then 
		theZone.lastTriggerValue = theZone:getFlagValue(theZone.triggerFlag) 
		if rndFlags.verbose or theZone.verbose then 
			trigger.action.outText("+++RND: randomizer in <" .. theZone:getName() .. "> triggers on flag <" .. theZone.triggerFlag .. ">", 30)
		end
	end
	
	theZone.onStart = theZone:getBoolFromZoneProperty("onStart", false)
	
	if not theZone.onStart and not theZone.triggerFlag then 
		trigger.action.outText("+++RND - WARNING: no triggers and no onStart, RND in <" .. theZone.name .. "> can't be triggered.", 30)
	end
	
	theZone.rndMethod = theZone:getStringFromZoneProperty("method", "inc")
	if theZone:hasProperty("rndMethod") then 
		theZone.rndMethod = theZone:getStringFromZoneProperty("rndMethod", "inc")
	end
	
	theZone.reshuffle = theZone:getBoolFromZoneProperty("reshuffle", false)
	if theZone.reshuffle then 
		-- create a backup copy we can reshuffle from 
		theZone.flagStore = dcsCommon.copyArray(theFlags)
	end
	
	-- done flag OLD, to be deprecated
	if theZone:hasProperty("done+1") then 
		theZone.doneFlag = theZone:getStringFromZoneProperty("done+1", "<none>")
		trigger.action.outText("Warning: RND zone <" .. theZone.name .. "> uses depreceated 'done+1'.", 30)

	-- now NEW replacements
	elseif theZone:hasProperty("done!") then 
		theZone.doneFlag = theZone:getStringFromZoneProperty("done!", "<none>")
	elseif theZone:hasProperty("rndDone!") then 
		theZone.doneFlag = theZone.getStringFromZoneProperty("rndDone!", "<none>")
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

function rndFlags.fire(theZone) 
	-- fire this rnd 
	-- create a local copy of all flags 
	if theZone.reshuffle and #theZone.myFlags < 1 then 
		rndFlags.reshuffle(theZone)
	end
	
	local availableFlags = dcsCommon.copyArray(theZone.myFlags) 
	
	-- do this pollSize times 
	local pollSize = dcsCommon.randomBetween(theZone.pollSizeMin, theZone.pollSize)

	
	if #availableFlags < 1 then 
		if rndFlags.verbose or theZone.verbose then 
			trigger.action.outText("+++RND: RND " .. theZone.name .. " ran out of flags. Will fire 'done' instead ", 30)
		end
		if theZone.doneFlag then
			cfxZones.pollFlag(theZone.doneFlag, theZone.rndMethod, theZone)
		end
		
		return 
	end
	
	if rndFlags.verbose or theZone.verbose then 
		trigger.action.outText("+++RND: firing RND " .. theZone.name .. " with pollsize " .. pollSize .. " on " .. #availableFlags .. " set size", 30)
	end
	
	for i=1, pollSize do 
		-- check there are still flags left 
		if #availableFlags < 1 then 
			if rndFlags.verbose or theZone.verbose then 
				trigger.action.outText("+++RND: no flags left in <" .. theZone.name .. "> in index " .. i, 30)
			end 
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
		
		--rndFlags.pollFlag(theFlag, theZone.rndMethod)
		if rndFlags.verbose or theZone.verbose then 
			trigger.action.outText("+++RND: polling <" .. theFlag .. "> with " .. theZone.rndMethod, 30)
		end
		
		theZone:pollFlag(theFlag, theZone.rndMethod) 
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
		if cfxZones.testZoneFlag(aZone, aZone.triggerFlag, aZone.rndTriggerMethod, "lastTriggerValue") then
			if rndFlags.verbose or aZone.verbose then 
				trigger.action.outText("+++RND: triggering " .. aZone.name, 30)
			end 
			rndFlags.fire(aZone)
		end

	end
end

--
-- start cycle: force all onStart to fire 
--
function rndFlags.startCycle()
	for idx, theZone in pairs(rndFlags.rndGen) do
		if theZone.onStart then 
			if theZone.isStarted then 
				-- suppressed by persistence 
			else 
				if rndFlags.verbose or theZone.verbose then 
					trigger.action.outText("+++RND: starting " .. theZone.name, 30)
				end 
				rndFlags.fire(theZone)
			end 
		end
	end
end

--
-- Load / Save data 
--

function rndFlags.saveData()
	local theData = {}
	local allRND = {}
	for idx, theRND in pairs(rndFlags.rndGen) do 
		local theName = theRND.name 
		local rndData = {}
		-- save data for this RND 
		rndData.myFlags = dcsCommon.clone(theRND.myFlags)
		allRND[theName] = rndData
	end
	theData.allRND = allRND

	return theData
end

function rndFlags.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("rndFlags")
	if not theData then 
		if rndFlags.verbose then 
			trigger.action.outText("+++RND Persistence: no save date received, skipping.", 30)
		end
		return
	end
	
	local allRND = theData.allRND
	if not allRND then
		if rndFlags.verbose then 
			trigger.action.outText("+++RND Persistence - no data, skipping", 30)
		end
		return 
	end -- no data, no proccing 
	
	for theName, rData in pairs(allRND) do 
		local theRND = rndFlags.getRNDByName(theName)
		if theRND then 
			-- get current myFlags 
			local myFlags = dcsCommon.clone(rData.myFlags)
			theRND.myFlags = myFlags
			theRND.isStarted = true -- we are initted, NO ON START 
		else 
			trigger.action.outText("+++RND persistecne: can't synch RND <" .. theName .. ">", 30)
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
	rndFlags.verbose = theZone.verbose 
	if rndFlags.verbose then 
		trigger.action.outText("***RND: read config", 30)
	end 
end

function rndFlags.start()
	-- lib check
	if not dcsCommon then 
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
	local attrZones = cfxZones.getZonesWithAttributeNamed("RND!")
	if rndFlags.verbose then 
		local a = dcsCommon.getSizeOfTable(attrZones)
		trigger.action.outText("RND! zones: " .. a, 30)
	end 
	
	-- now create an rnd gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		rndFlags.createRNDWithZone(aZone)
		rndFlags.addRNDZone(aZone)
	end

	-- obsolete here
	attrZones = cfxZones.getZonesWithAttributeNamed("RND")
	for k, aZone in pairs(attrZones) do 
		rndFlags.createRNDWithZone(aZone) 
		rndFlags.addRNDZone(aZone)
	end
	
	-- persistence
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = rndFlags.saveData
		persistence.registerModule("rndFlags", callbacks)
		-- now load my data 
		rndFlags.loadData()
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

