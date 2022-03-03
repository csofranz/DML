pulseFlags = {}
pulseFlags.version = "1.1.0"
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
	
--]]--

pulseFlags.pulses = {}

function pulseFlags.addPulse(aZone)
	table.insert(pulseFlags.pulses, aZone)
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
	if pulseFlags.verbose then 
		trigger.action.outText("***PulF: zone <" .. theZone.name .. "> time is <".. theZone.minTime ..", " .. theZone.time .. "!", 30)
	end 
	
	theZone.pulses = cfxZones.getNumberFromZoneProperty(theZone, "pulses", -1)
	theZone.pulsesLeft = 0 -- will start new cycle 
		
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
		theZone.lastPauseValue = cfxZones.getFlagValue(theZone.lastPauseValue, theZone)-- trigger.misc.getUserFlag(theZone.pausePulseFlag) -- save last value
	end
	
	if cfxZones.hasProperty(theZone, "pausePulse?") then 
		theZone.pausePulseFlag = cfxZones.getStringFromZoneProperty(theZone, "pausePulse?", "*none")
		theZone.lastPauseValue = cfxZones.getFlagValue(theZone.lastPauseValue, theZone)-- trigger.misc.getUserFlag(theZone.pausePulseFlag) -- save last value
	end
	
	theZone.pulsePaused = cfxZones.getBoolFromZoneProperty(theZone, "paused", false)
	
	if cfxZones.hasProperty(theZone, "pulseStopped") then 
		theZone.pulsePaused = cfxZones.getBoolFromZoneProperty(theZone, "pulseStopped", false)
	end
	
	theZone.method = cfxZones.getStringFromZoneProperty(theZone, "method", "flip")
	
	if cfxZones.hasProperty(theZone, "pulseMethod") then
		theZone.method = cfxZones.getStringFromZoneProperty(theZone, "pulseMethod", "flip")
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
	
	-- do a poll on flags
	-- first, we only do an initial pulse if zeroPulse is set
	if theZone.hasPulsed or theZone.zeroPulse then 
		if pulseFlags.verbose then 
			trigger.action.outText("+++pulF: will bang " .. theZone.pulseFlag, 30);
		end
		
		cfxZones.pollFlag(theZone.pulseFlag, theZone.method, theZone) 
	
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
				if pulseFlags.verbose then 
					trigger.action.outText("***PulF: pulse <" .. theZone.name .. "> ended!", 30)
				end 
				theZone.pulsing = false 
				theZone.pulsePaused = true 
				return 
			end
		end
	else 
		if pulseFlags.verbose then 
			trigger.action.outText("***PulF: pulse <" .. theZone.name .. "> delaying zero pulse!", 30)
		end
	end
	
	theZone.hasPulsed = true -- we are past initial pulse
	
	-- if we get here, schedule next pulse
	local delay = cfxZones.randomDelayFromPositiveRange(theZone.minTime, theZone.time)
	
	
	-- schedule in delay time 
	theZone.timerID = timer.scheduleFunction(pulseFlags.doPulse, args, timer.getTime() + delay)
	if pulseFlags.verbose then 
		trigger.action.outText("+++PulF: pulse <" .. theZone.name .. "> rescheduled in " .. delay, 30)
	end 
end
 

-- start new pulse, will reset 
function pulseFlags.startNewPulse(theZone)
	theZone.pulsesLeft = theZone.pulses
	local args = {theZone}
	theZone.pulsing = true 
	if pulseFlags.verbose then 
		trigger.action.outText("+++PulF: starting pulse <" .. theZone.name .. ">", 30)
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
		if aZone.activatePulseFlag then 
			local currTriggerVal = cfxZones.getFlagValue(aZone.activatePulseFlag, aZone) -- trigger.misc.getUserFlag(aZone.activatePulseFlag)
			if currTriggerVal ~= aZone.lastActivateValue
			then 
				if pulseFlags.verbose then 
					trigger.action.outText("+++PulF: activating <" .. aZone.name .. ">", 30)
				end 
				aZone.lastActivateValue = currTriggerVal
				aZone.pulsePaused = false -- will start anew 
				
			end
		end
		
		if aZone.pausePulseFlag then 
			local currTriggerVal = cfxZones.getFlagValue(aZone.pausePulseFlag, aZone)-- trigger.misc.getUserFlag(aZone.pausePulseFlag)
			if currTriggerVal ~= aZone.lastPauseValue
			then 
				if pulseFlags.verbose then 
					trigger.action.outText("+++PulF: pausing <" .. aZone.name .. ">", 30)
				end 
				aZone.lastPauseValue = currTriggerVal
				aZone.pulsePaused = true  -- prevents new start 
				if aZone.timerID then 
					 timer.removeFunction(aZone.timerID)
					 aZone.timerID = nil 
				end 
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
			trigger.action.outText("+++PulF: NO config zone!", 30)
		end 
		return 
	end 
	
	pulseFlags.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if pulseFlags.verbose then 
		trigger.action.outText("+++PulF: read config", 30)
	end 
end

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
	
	-- now create a pulse gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		pulseFlags.createPulseWithZone(aZone) -- process attribute and add to zone
		pulseFlags.addPulse(aZone) -- remember it so we can pulse it
	end
	
	local attrZones = cfxZones.getZonesWithAttributeNamed("pulse!")
	
	-- now create a pulse gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		pulseFlags.createPulseWithZone(aZone) -- process attribute and add to zone
		pulseFlags.addPulse(aZone) -- remember it so we can pulse it
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