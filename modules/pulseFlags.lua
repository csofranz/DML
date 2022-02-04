pulseFlags = {}
pulseFlags.version = "1.0.0"
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
	
--]]--

pulseFlags.pulses = {}

function pulseFlags.addPulse(aZone)
	table.insert(pulseFlags.pulses, aZone)
end

--
-- create a pulse 
--

function pulseFlags.createPulseWithZone(theZone)
	theZone.flag = cfxZones.getNumberFromZoneProperty(theZone, "flag!", -1) -- the flag to pulse 

	-- time can be number, or number-number range
	theZone.minTime, theZone.time = cfxZones.getPositiveRangeFromZoneProperty(theZone, "time", 1)
	if pulseFlags.verbose then 
		trigger.action.outText("***PulF: zone <" .. theZone.name .. "> time is <".. theZone.minTime ..", " .. theZone.time .. "!", 30)
	end 
	
	theZone.pulses = cfxZones.getNumberFromZoneProperty(theZone, "pulses", -1)
	theZone.pulsesLeft = 0 -- will start new cycle 
		
	-- trigger flags 
	if cfxZones.hasProperty(theZone, "activate?") then 
		theZone.activateFlag = cfxZones.getStringFromZoneProperty(theZone, "activate?", "none")
		theZone.lastActivateValue = trigger.misc.getUserFlag(theZone.activateFlag) -- save last value
	end
	
	if cfxZones.hasProperty(theZone, "pause?") then 
		theZone.pauseFlag = cfxZones.getStringFromZoneProperty(theZone, "pause?", "none")
		theZone.lastPauseValue = trigger.misc.getUserFlag(theZone.pauseFlag) -- save last value
	end
	
	theZone.paused = cfxZones.getBoolFromZoneProperty(theZone, "paused", false)
	
	theZone.method = cfxZones.getStringFromZoneProperty(theZone, "method", "flip")
	
	-- done flag 
	if cfxZones.hasProperty(theZone, "done+1") then 
		theZone.doneFlag = cfxZones.getStringFromZoneProperty(theZone, "done+1", "none")
	end

	theZone.pulsing = false -- not running 
	
end

--
-- update 
-- 
function pulseFlags.pollFlag(theFlag, method) 
	if pulseFlags.verbose then 
		trigger.action.outText("+++PulF: polling flag " .. theFlag .. " with " .. method, 30)
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
			trigger.action.outText("+++PulF: unknown method <" .. method .. "> - using 'on'", 30)
		end
		-- default: on.
		trigger.action.setUserFlag(theFlag, 1)
	end
	
	local newVal = trigger.misc.getUserFlag(theFlag)
	if pulseFlags.verbose then 
		trigger.action.outText("+++PulF: flag <" .. theFlag .. "> changed from " .. currVal .. " to " .. newVal, 30)
	end 
end


function pulseFlags.doPulse(args) 
	local theZone = args[1]
	-- check if we have been paused. if so, simply 
	-- exit with no new schedule 
	if theZone.paused then 
		theZone.pulsing = false 
		return 
	end 
	
	-- do a poll on flags 
	pulseFlags.pollFlag(theZone.flag, theZone.method) 
	
	-- decrease count
	if theZone.pulses > 0 then
		-- only do this if ending
		theZone.pulsesLeft = theZone.pulsesLeft - 1
		
		-- see if we are done 
		if theZone.pulsesLeft < 1 then 
			-- increment done flag if set 
			if theZone.doneFlag then 
				local currVal = trigger.misc.getUserFlag(theZone.doneFlag)
				trigger.action.setUserFlag(theZone.doneFlag, currVal + 1)
			end
			if pulseFlags.verbose then 
				trigger.action.outText("***PulF: pulse <" .. theZone.name .. "> ended!", 30)
			end 
			theZone.pulsing = false 
			theZone.paused = true 
			return 
		end
	end
	
	-- if we get here, we'll do another one soon
	-- refresh pulse
	local delay = theZone.time
	if theZone.minTime > 0 and theZone.minTime < delay then 
		-- we want a randomized from time from minTime .. delay
		local varPart = delay - theZone.minTime + 1
		varPart = dcsCommon.smallRandom(varPart) - 1
		delay = theZone.minTime + varPart
	end
	
	--trigger.action.outText("***PulF: pulse <" .. theZone.name .. "> scheduled in ".. delay .."!", 30)
	
	-- schedule in delay time 
	timer.scheduleFunction(pulseFlags.doPulse, args, timer.getTime() + delay)
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
			if aZone.paused then 
				-- ok, zone is paused. all clear 
			else 
				-- zone isn't paused. we need to start the zone 
				pulseFlags.startNewPulse(aZone)
			end
		end
		
		-- see if we got a pause or activate command
		if aZone.activateFlag then 
			local currTriggerVal = trigger.misc.getUserFlag(aZone.activateFlag)
			if currTriggerVal ~= aZone.lastActivateValue
			then 
				trigger.action.outText("+++PulF: activating <" .. aZone.name .. ">", 30)
				aZone.lastActivateValue = currTriggerVal
				theZone.paused = false -- will start anew 
			end
		end
		
		if aZone.pauseFlag then 
			local currTriggerVal = trigger.misc.getUserFlag(aZone.pauseFlag)
			if currTriggerVal ~= aZone.lastPauseValue
			then 
				trigger.action.outText("+++PulF: pausing <" .. aZone.name .. ">", 30)
				aZone.lastPauseValue = currTriggerVal
				theZone.paused = true  -- will start anew 
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