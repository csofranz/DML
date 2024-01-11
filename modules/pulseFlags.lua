pulseFlags = {}
pulseFlags.version = "2.0.1"
pulseFlags.verbose = false 
pulseFlags.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
	Pulse Flags: DML module to regularly change a flag 
	
	Copyright 2022 by Christian Franz and cf/x 
	
	Version History
	- 2.0.0 dmlZones / OOP
	        using method on all outputs
	- 2.0.1 activateZoneFlag now works correctly
	
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
	if theZone:hasProperty("pulse") then 
		theZone.pulseFlag = theZone:getStringFromZoneProperty("pulse", "*none") -- the flag to pulse 
		trigger.action.outText("Warning: pulser in zone <" .. theZone.name .. "> uses deprecated attribuet 'pulse'.", 30)
	elseif theZone:hasProperty("pulse!") then 
		theZone.pulseFlag = theZone:getStringFromZoneProperty("pulse!", "*none") -- the flag to pulse 
	end
	
	-- time can be number, or number-number range
	theZone.minTime = 1
	theZone.time = 1
	if theZone:hasProperty("time") then 
		theZone.minTime, theZone.time = theZone:getPositiveRangeFromZoneProperty("time", 1)
	elseif theZone:hasProperty("pulseInterval") then 
		theZone.minTime, theZone.time = theZone:getPositiveRangeFromZoneProperty("pulseInterval", 1)
	end
	if pulseFlags.verbose or theZone.verbose then 
		trigger.action.outText("+++pulF: zone <" .. theZone.name .. "> time is <".. theZone.minTime ..", " .. theZone.time .. "!", 30)
	end 
	
	
	theZone.pulses = -1 -- set to infinite 
	if theZone:hasProperty("pulses") then 
		local minP, maxP = theZone:getPositiveRangeFromZoneProperty("pulses", 1)
		if minP == maxP then theZone.pulses = minP 
		else 
			theZone.pulses = cfxZones.randomInRange(minP, maxP)
		end
	end
	if pulseFlags.verbose or theZone.verbose then 
		trigger.action.outText("+++pulF: zone <" .. theZone.name .. "> set to <" .. theZone.pulses .. "> pulses", 30)
	end

	theZone.pulsesLeft = 0 -- will start new cycle 

	theZone.pulseTriggerMethod = theZone:getStringFromZoneProperty( "triggerMethod", "change")

	if theZone:hasProperty("pulseTriggerMethod") then 
		theZone.pulseTriggerMethod = theZone:getStringFromZoneProperty("pulseTriggerMethod", "change")
	end
	
	-- trigger flags 
	if theZone:hasProperty("activate?") then 
		theZone.activatePulseFlag = theZone:getStringFromZoneProperty("activate?", "none")
		theZone.lastActivateValue = theZone:getFlagValue(theZone.activatePulseFlag) 
	end
	
	if theZone:hasProperty("startPulse?") then 
		theZone.activatePulseFlag = theZone:getStringFromZoneProperty("startPulse?", "none")
		theZone.lastActivateValue = theZone:getFlagValue(theZone.activatePulseFlag) 
	end
	
	if theZone:hasProperty("pause?") then 
		theZone.pausePulseFlag = theZone:getStringFromZoneProperty("pause?", "*none")
		theZone.lastPauseValue = theZone:getFlagValue(theZone.pausePulseFlag)
	end
	
	if theZone:hasProperty("pausePulse?") then 
		theZone.pausePulseFlag = theZone:getStringFromZoneProperty( "pausePulse?", "*none")
		theZone.lastPauseValue = theZone:getFlagValue(theZone.pausePulseFlag)
	end
	
	-- harmonizing on onStart, and converting to old pulsePaused
	local onStart = theZone:getBoolFromZoneProperty("onStart", true)
	theZone.pulsePaused = not (onStart) 
	
	theZone.pulseMethod = theZone:getStringFromZoneProperty("method", "inc")
		
	if theZone:hasProperty("outputMethod") then
		theZone.pulseMethod = theZone:getStringFromZoneProperty( "outputMethod", "inc")
	end
	-- done flag 
	if theZone:hasProperty("pulsesDone!") then 
		theZone.pulseDoneFlag = theZone:getStringFromZoneProperty("pulsesDone!", "*none")
	end
	if theZone:hasProperty("done!") then 
		theZone.pulseDoneFlag = theZone:getStringFromZoneProperty("done!", "*none")
	end
	theZone.pulsing = false -- not running 
	theZone.hasPulsed = false 
	theZone.zeroPulse = theZone:getBoolFromZoneProperty("zeroPulse", true)
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
			trigger.action.outText("+++pulF: will bang " .. theZone.pulseFlag .. " for <" .. theZone.name .. ">", 30);
		end
		
		theZone:pollFlag(theZone.pulseFlag, theZone.pulseMethod) 
		-- decrease count
		if theZone.pulses > 0 then
			-- only do this if ending
			theZone.pulsesLeft = theZone.pulsesLeft - 1
			
			-- see if we are done 
			if theZone.pulsesLeft < 1 then 
				-- increment done flag if set 
				if theZone.pulseDoneFlag then 
					theZone:pollFlag(theZone.pulseDoneFlag, theZone.pulseMethod) 
				end
				if pulseFlags.verbose or theZone.verbose then 
					trigger.action.outText("+++pulF: pulse <" .. theZone.name .. "> ended.", 30)
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
	timer.scheduleFunction(pulseFlags.update, {}, timer.getTime() + 1)
	
	for idx, aZone in pairs(pulseFlags.pulses) do
		-- see if pulse is running 
		if aZone.pulsing then 
			-- this zone has a pulse and has scheduled 
			-- a new pulse, nothing to do
		else 
			if aZone.pulsePaused then 
				-- ok, zone is paused. all clear 
			else 
				-- zone isn't paused. we need to start the zone 
				pulseFlags.startNewPulse(aZone)
			end
		end
		
		-- see if we got a pause or activate command
		-- activatePulseFlag
		if aZone:testZoneFlag(aZone.activatePulseFlag, aZone.pulseTriggerMethod, "lastActivateValue") then
			if pulseFlags.verbose or aZone.verbose then 
					trigger.action.outText("+++pulF: activating <" .. aZone.name .. ">", 30)
				end 
			aZone.pulsePaused = false -- will start anew 
		end
				
		-- pausePulseFlag
		if aZone:testZoneFlag(aZone.pausePulseFlag, aZone.pulseTriggerMethod, "lastPauseValue") then
			if pulseFlags.verbose or aZone.verbose then 
				trigger.action.outText("+++pulF: pausing <" .. aZone.name .. ">", 30)
			end 
			aZone.pulsePaused = true  -- prevents new start 
			aZone.pulsing = false -- we are stopped 
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
		theZone = cfxZones.createSimpleZone("pulseFlagsConfig") 
	end 
	pulseFlags.verbose = theZone.verbose 
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
	
	-- process "pulse" Zones - deprecated!! 
	local attrZones = cfxZones.getZonesWithAttributeNamed("pulse")
	for k, aZone in pairs(attrZones) do 
		pulseFlags.createPulseWithZone(aZone)
		pulseFlags.addPulse(aZone)
	end
	
	attrZones = cfxZones.getZonesWithAttributeNamed("pulse!")
	a = dcsCommon.getSizeOfTable(attrZones)
	trigger.action.outText("pulse! zones: " .. a, 30)
	for k, aZone in pairs(attrZones) do 
		pulseFlags.createPulseWithZone(aZone)
		pulseFlags.addPulse(aZone)
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
	timer.scheduleFunction(pulseFlags.update, {}, timer.getTime() + 1)
	
	trigger.action.outText("cfx Pulse Flags v" .. pulseFlags.version .. " started.", 30)
	return true 
end

-- let's go!
if not pulseFlags.start() then 
	trigger.action.outText("cf/x Pulse Flags aborted: missing libraries", 30)
	pulseFlags = nil 
end