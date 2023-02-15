pulseFlags = {}
pulseFlags.version = "1.3.2"
pulseFlags.verbose = false 
pulseFlags.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
	Pulse Flags: DML module to regularly change a flag 
	
	Copyright 2022 by Christian Franz and cf/x 
	
	Version History
	- 1.0.0 Initial version 
	- 1.0.1 pause behavior debugged 
	- 1.0.2 zero pulse optional initial pulse suppress
	- 1.0.3 pollFlag switched to cfxZones 
			uses randomDelayFromPositiveRange
			flag! now is string 
			WARNING: still needs full alphaNum flag upgrade 
	- 1.1.0 Full DML flag integration 
	        removed zone!
			made pulse and pulse! the out flag carrier
			done!
			pulsesDone! synonym
			pausePulse? synonym
			pulseMethod synonym
			startPulse? synonym 
			pulseStopped synonym
	- 1.2.0 DML Watchflag integration 
	        corrected bug in loading last pulse value for paused
	- 1.2.1 pulseInterval synonym for time 
			pulses now supports range 
			zone-local verbosity
	- 1.2.2 outputMethod synonym
	- 1.2.3 deprecated paused/pulsePaused 
	        returned onStart, defaulting to true
	- 1.3.0 persistence
	- 1.3.1 typos corrected
	- 1.3.2 removed last pulse's timeID upon entry in doPulse
	
--]]--

pulseFlags.pulses = {}

function pulseFlags.addPulse(aZone)
	table.insert(pulseFlags.pulses, aZone)
end

function pulseFlags.getPulseByName(theName)
	for idx, theZone in pairs (pulseFlags.pulses) do 
		if theZone.name == theName then return theZone end 
	end
	return nil 
end
--
-- create a pulse 
--

function pulseFlags.createPulseWithZone(theZone)
	if cfxZones.hasProperty(theZone, "pulse") then 
		theZone.pulseFlag = cfxZones.getStringFromZoneProperty(theZone, "pulse", "*none") -- the flag to pulse 
	end

	if cfxZones.hasProperty(theZone, "pulse!") then 
		theZone.pulseFlag = cfxZones.getStringFromZoneProperty(theZone, "pulse!", "*none") -- the flag to pulse 
	end
	
	-- time can be number, or number-number range
	theZone.minTime, theZone.time = cfxZones.getPositiveRangeFromZoneProperty(theZone, "time", 1)
	if cfxZones.hasProperty(theZone, "pulseInterval") then 
		theZone.minTime, theZone.time = cfxZones.getPositiveRangeFromZoneProperty(theZone, "pulseInterval", 1)
	end
	
	if pulseFlags.verbose or theZone.verbose then 
		trigger.action.outText("+++pulF: zone <" .. theZone.name .. "> time is <".. theZone.minTime ..", " .. theZone.time .. "!", 30)
	end 
	
	
	theZone.pulses = -1 -- set to infinite 
	if cfxZones.hasProperty(theZone, "pulses") then 
		local minP
		local maxP 
		minP, maxP = cfxZones.getPositiveRangeFromZoneProperty(theZone, "pulses", 1)
		if minP == maxP then theZone.pulses = minP 
		else 
			theZone.pulses = cfxZones.randomInRange(minP, maxP)
		end
	end
	
	if pulseFlags.verbose or theZone.verbose then 
		trigger.action.outText("+++pulF: zone <" .. theZone.name .. "> set to <" .. theZone.pulses .. "> pulses", 30)
	end
	
	theZone.pulsesLeft = 0 -- will start new cycle 

	-- watchflag:
	-- triggerMethod
	theZone.pulseTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")

	if cfxZones.hasProperty(theZone, "pulseTriggerMethod") then 
		theZone.pulseTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "pulseTriggerMethod", "change")
	end
	
	-- trigger flags 
	if cfxZones.hasProperty(theZone, "activate?") then 
		theZone.activatePulseFlag = cfxZones.getStringFromZoneProperty(theZone, "activate?", "none")
		theZone.lastActivateValue = cfxZones.getFlagValue(theZone.activatePulseFlag, theZone) -- trigger.misc.getUserFlag(theZone.activatePulseFlag) -- save last value
	end
	
	if cfxZones.hasProperty(theZone, "startPulse?") then 
		theZone.activatePulseFlag = cfxZones.getStringFromZoneProperty(theZone, "startPulse?", "none")
		theZone.lastActivateValue = cfxZones.getFlagValue(theZone.activatePulseFlag, theZone) -- trigger.misc.getUserFlag(theZone.activatePulseFlag) -- save last value
	end
	
	if cfxZones.hasProperty(theZone, "pause?") then 
		theZone.pausePulseFlag = cfxZones.getStringFromZoneProperty(theZone, "pause?", "*none")
		theZone.lastPauseValue = cfxZones.getFlagValue(theZone.pausePulseFlag, theZone)-- trigger.misc.getUserFlag(theZone.pausePulseFlag) -- save last value
	end
	
	if cfxZones.hasProperty(theZone, "pausePulse?") then 
		theZone.pausePulseFlag = cfxZones.getStringFromZoneProperty(theZone, "pausePulse?", "*none")
		theZone.lastPauseValue = cfxZones.getFlagValue(theZone.pausePulseFlag, theZone)-- trigger.misc.getUserFlag(theZone.pausePulseFlag) -- save last value
	end
	
	-- harmonizing on onStart, and converting to old pulsePaused
	local onStart = cfxZones.getBoolFromZoneProperty(theZone, "onStart", true)
	theZone.pulsePaused = not (onStart) 
	-- old code, to be deprecated 
	if cfxZones.hasProperty(theZone, "paused") then
		theZone.pulsePaused = cfxZones.getBoolFromZoneProperty(theZone, "paused", false)
	
	elseif cfxZones.hasProperty(theZone, "pulseStopped") then 
		theZone.pulsePaused = cfxZones.getBoolFromZoneProperty(theZone, "pulseStopped", false)
	end
	--]]--
	
	theZone.pulseMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "flip")
	
	if cfxZones.hasProperty(theZone, "pulseMethod") then
		theZone.pulseMethod = cfxZones.getStringFromZoneProperty(theZone, "pulseMethod", "flip")
	end
	
	if cfxZones.hasProperty(theZone, "outputMethod") then
		theZone.pulseMethod = cfxZones.getStringFromZoneProperty(theZone, "outputMethod", "flip")
	end
	-- done flag 
	if cfxZones.hasProperty(theZone, "done+1") then 
		theZone.pulseDoneFlag = cfxZones.getStringFromZoneProperty(theZone, "done+1", "*none")
	end
	if cfxZones.hasProperty(theZone, "pulsesDone!") then 
		theZone.pulseDoneFlag = cfxZones.getStringFromZoneProperty(theZone, "pulsesDone!", "*none")
	end
	if cfxZones.hasProperty(theZone, "done!") then 
		theZone.pulseDoneFlag = cfxZones.getStringFromZoneProperty(theZone, "done!", "*none")
	end

	theZone.pulsing = false -- not running 
	theZone.hasPulsed = false 
	theZone.zeroPulse = cfxZones.getBoolFromZoneProperty(theZone, "zeroPulse", true)
end

--
-- update 
-- 


function pulseFlags.doPulse(args) 

	local theZone = args[1]
	-- check if we have been paused. if so, simply 
	-- exit with no new schedule 
	if theZone.pulsePaused then 
		theZone.pulsing = false 
		return 
	end 
	-- erase old timerID, since we completed that
	theZone.timerID = nil
	
	-- do a poll on flags
	-- first, we only do an initial pulse if zeroPulse is set
	if theZone.hasPulsed or theZone.zeroPulse then 
		if pulseFlags.verbose or theZone.verbose then 
			trigger.action.outText("+++pulF: will bang " .. theZone.pulseFlag, 30);
		end
		
		cfxZones.pollFlag(theZone.pulseFlag, theZone.pulseMethod, theZone) 
	
		-- decrease count
		if theZone.pulses > 0 then
			-- only do this if ending
			theZone.pulsesLeft = theZone.pulsesLeft - 1
			
			-- see if we are done 
			if theZone.pulsesLeft < 1 then 
				-- increment done flag if set 
				if theZone.pulseDoneFlag then 
					--local currVal = cfxZones.getFlagValue(theZone.pulseDoneFlag, theZone)-- trigger.misc.getUserFlag(theZone.pulseDoneFlag)
					cfxZones.pollFlag(theZone.pulseDoneFlag, "inc", theZone) -- trigger.action.setUserFlag(theZone.pulseDoneFlag, currVal + 1)
				end
				if pulseFlags.verbose or theZone.verbose then 
					trigger.action.outText("+++pulF: pulse <" .. theZone.name .. "> ended!", 30)
				end 
				theZone.pulsing = false 
				theZone.pulsePaused = true 
				return 
			end
		end
	else 
		if pulseFlags.verbose or theZone.verbose then 
			trigger.action.outText("+++pulF: pulse <" .. theZone.name .. "> delaying zero pulse!", 30)
		end
	end
	
	theZone.hasPulsed = true -- we are past initial pulse
	
	-- if we get here, schedule next pulse
	local delay = cfxZones.randomDelayFromPositiveRange(theZone.minTime, theZone.time)
	
	
	-- schedule in delay time 
	theZone.scheduledTime = timer.getTime() + delay
	theZone.timerID = timer.scheduleFunction(pulseFlags.doPulse, args, theZone.scheduledTime)

	if pulseFlags.verbose or theZone.verbose then 
		trigger.action.outText("+++pulF: pulse <" .. theZone.name .. "> rescheduled in " .. delay, 30)
	end 
end
 

-- start new pulse, will reset 
function pulseFlags.startNewPulse(theZone)
	theZone.pulsesLeft = theZone.pulses
	local args = {theZone}
	theZone.pulsing = true 
	if pulseFlags.verbose or theZone.verbose then 
		trigger.action.outText("+++pulF: starting pulse <" .. theZone.name .. ">", 30)
	end 
	pulseFlags.doPulse(args) 
end

function pulseFlags.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(pulseFlags.update, {}, timer.getTime() + 1)
	
	for idx, aZone in pairs(pulseFlags.pulses) do
		-- see if pulse is running 
		if aZone.pulsing then 
			-- this zone has a pulse and has scheduled 
			-- a new pulse, nothing to do
		
		else 
			-- this zone has not scheduled a new pulse 
			-- let's see why 
			if aZone.pulsePaused then 
				-- ok, zone is paused. all clear 
			else 
				-- zone isn't paused. we need to start the zone 
				pulseFlags.startNewPulse(aZone)
			end
		end
		
		-- see if we got a pause or activate command
		-- activatePulseFlag
		if cfxZones.testZoneFlag(aZone, aZone.activatePulseFlag, aZone.pulseTriggerMethod, "lastActivateValue") then
			if pulseFlags.verbose or aZone.verbose then 
					trigger.action.outText("+++pulF: activating <" .. aZone.name .. ">", 30)
				end 
			aZone.pulsePaused = false -- will start anew 
		end
				
		-- pausePulseFlag
		if cfxZones.testZoneFlag(aZone, aZone.pausePulseFlag, aZone.pulseTriggerMethod, "lastPauseValue") then
			if pulseFlags.verbose or aZone.verbose then 
				trigger.action.outText("+++pulF: pausing <" .. aZone.name .. ">", 30)
			end 
			aZone.pulsePaused = true  -- prevents new start 
			if aZone.timerID then 
				 timer.removeFunction(aZone.timerID)
				 aZone.timerID = nil 
			end 
		end

	end
end

--
-- start module and read config 
--
function pulseFlags.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("pulseFlagsConfig") 
	if not theZone then 
		if pulseFlags.verbose then 
			trigger.action.outText("+++pulF: NO config zone!", 30)
		end 
		return 
	end 
	
	pulseFlags.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if pulseFlags.verbose then 
		trigger.action.outText("+++pulF: read config", 30)
	end 
end

--
-- LOAD / SAVE 
--
function pulseFlags.saveData()
	local theData = {}
	local allPulses = {}
	local now = timer.getTime()
	for idx, thePulse in pairs(pulseFlags.pulses) do 
		local theName = thePulse.name 
		local pulseData = {}
 		pulseData.pulsePaused = thePulse.pulsePaused
		pulseData.pulsesLeft = thePulse.pulsesLeft
		pulseData.pulsing = thePulse.pulsing 
		pulseData.scheduledTime = thePulse.scheduledTime - now 
		pulseData.hasPulsed = thePulse.hasPulsed
		
		allPulses[theName] = pulseData 
	end
	theData.allPulses = allPulses
	return theData
end

function pulseFlags.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("pulseFlags")
	if not theData then 
		if pulseFlags.verbose then 
			trigger.action.outText("+++pulF Persistence: no save data received, skipping.", 30)
		end
		return
	end
	
	local allPulses = theData.allPulses
	if not allPulses then 
		if pulseFlags.verbose then 
			trigger.action.outText("+++pulF Persistence: no timer data, skipping", 30)
		end		
		return
	end
	
	local now = timer.getTime()
	for theName, theData in pairs(allPulses) do 
		local thePulse = pulseFlags.getPulseByName(theName)
		if thePulse then 
			thePulse.pulsePaused = theData.pulsePaused
			thePulse.pulsesLeft = theData.pulsesLeft
			thePulse.scheduledTime = now + theData.scheduledTime
			thePulse.hasPulsed = theData.hasPulsed
			if thePulse.scheduledTime < now then thePulse.scheduledTime = now + 0.1 end
			
			thePulse.pulsing = theData.pulsing 
			if thePulse.pulsing then 
				local args = {thePulse}
				thePulse.timerID = timer.scheduleFunction(pulseFlags.doPulse, args, thePulse.scheduledTime)
			end 
		else 
			trigger.action.outText("+++pulF: persistence: cannot synch pulse <" .. theName .. ">, skipping", 40)
		end
	end
end

--
-- START
--

function pulseFlags.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("PulseFlags requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Pulse Flags", 
		pulseFlags.requiredLibs) then
		return false 
	end
	
	-- read config 
	pulseFlags.readConfigZone()
	
	-- process RND Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("pulse")
--	local a = dcsCommon.getSizeOfTable(attrZones)
--	trigger.action.outText("pulse zones: " .. a, 30)
	-- now create a pulse gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		pulseFlags.createPulseWithZone(aZone) -- process attribute and add to zone
		pulseFlags.addPulse(aZone) -- remember it so we can pulse it
	end
	
	attrZones = cfxZones.getZonesWithAttributeNamed("pulse!")
	a = dcsCommon.getSizeOfTable(attrZones)
	trigger.action.outText("pulse! zones: " .. a, 30)
	-- now create a pulse gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		pulseFlags.createPulseWithZone(aZone) -- process attribute and add to zone
		pulseFlags.addPulse(aZone) -- remember it so we can pulse it
	end
	
	-- load any saved data 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = pulseFlags.saveData
		persistence.registerModule("pulseFlags", callbacks)
		-- now load my data 
		pulseFlags.loadData()
	end
	
	-- start update in 1 second 
	--pulseFlags.update()
	timer.scheduleFunction(pulseFlags.update, {}, timer.getTime() + 1)
	
	trigger.action.outText("cfx Pulse Flags v" .. pulseFlags.version .. " started.", 30)
	return true 
end

-- let's go!
if not pulseFlags.start() then 
	trigger.action.outText("cf/x Pulse Flags aborted: missing libraries", 30)
	pulseFlags = nil 
end