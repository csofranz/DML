delayFlag = {}
delayFlag.version = "1.3.0"
delayFlag.verbose = false  
delayFlag.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
delayFlag.flags = {}

--[[--
	delay flags - simple flag switch & delay, allows for randomize
	and dead man switching 
	
	Copyright (c) 2022 by Christian Franz and cf/x AG
	
	Version History
	1.0.0 - Initial Version 
	1.0.1 - message attribute 
	1.0.2 - slight spelling correction 
		  - using cfxZones for polling 
		  - removed pollFlag 
	1.0.3 - bug fix for config zone name
		  - removed message attribute, moved to own module 
		  - triggerFlag --> triggerDelayFlag
	1.0.4 - startDelay
	1.1.0 - DML flag upgrade 
		  - removed onStart. use local raiseFlag instead 
		  - delayDone! synonym
		  - pauseDelay?
		  - unpauseDelay?
	1.2.0 - Watchflags 
	1.2.1 - method goes to dlyMethod
	      - delay done is correctly inited 
	1.2.2 - delayMethod defaults to inc 
		  - zone-local verbosity
		  - code clean-up 
	1.2.3 - pauseDelay
	      - continueDelay 
		  - delayLeft
	1.3.0 - persistence
	
--]]--

function delayFlag.addDelayZone(theZone)
	table.insert(delayFlag.flags, theZone)
end

function delayFlag.getDelayZoneByName(aName) 
	for idx, aZone in pairs(delayFlag.flags) do 
		if aName == aZone.name then return aZone end 
	end
	if delayFlag.verbose then 
		trigger.action.outText("+++dlyF: no delay flag with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read attributes 
-- 
--
-- create rnd gen from zone 
--
function delayFlag.createTimerWithZone(theZone)
	-- delay
	theZone.delayMin, theZone.delayMax = cfxZones.getPositiveRangeFromZoneProperty(theZone, "timeDelay", 1) -- same as zone signature 
	if delayFlag.verbose or theZone.verbose then 
		trigger.action.outText("+++dlyF: time delay is <" .. theZone.delayMin .. ", " .. theZone.delayMax .. "> seconds", 30)
	end

	-- watchflags:
	-- triggerMethod
	theZone.delayTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")

	if cfxZones.hasProperty(theZone, "delayTriggerMethod") then 
		theZone.delayTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "delayTriggerMethod", "change")
	end

	-- trigger flag 
	if cfxZones.hasProperty(theZone, "f?") then 
		theZone.triggerDelayFlag = cfxZones.getStringFromZoneProperty(theZone, "f?", "none")
	end
	
	if cfxZones.hasProperty(theZone, "in?") then 
		theZone.triggerDelayFlag = cfxZones.getStringFromZoneProperty(theZone, "in?", "none")
	end
	
	if cfxZones.hasProperty(theZone, "startDelay?") then 
		theZone.triggerDelayFlag = cfxZones.getStringFromZoneProperty(theZone, "startDelay?", "none")
	end
	
	if theZone.triggerDelayFlag then 
		theZone.lastDelayTriggerValue = cfxZones.getFlagValue(theZone.triggerDelayFlag, theZone) -- trigger.misc.getUserFlag(theZone.triggerDelayFlag) -- save last value
	end
	
	
	theZone.delayMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	
	if cfxZones.hasProperty(theZone, "delayMethod") then
		theZone.delayMethod = cfxZones.getStringFromZoneProperty(theZone, "delayMethod", "inc")
	end
	
	-- out flag 
	theZone.delayDoneFlag = cfxZones.getStringFromZoneProperty(theZone, "out!", "*<none>")

	
	if cfxZones.hasProperty(theZone, "delayDone!") then 
		theZone.delayDoneFlag = cfxZones.getStringFromZoneProperty(theZone, "delayDone!", "*<none>")
	end

	-- stop the press!
	if cfxZones.hasProperty(theZone, "stopDelay?") then 
		theZone.triggerStopDelay = cfxZones.getStringFromZoneProperty(theZone, "stopDelay?", "none")
		theZone.lastTriggerStopValue = cfxZones.getFlagValue(theZone.triggerStopDelay, theZone)
	end
	
	-- pause and continue
	if cfxZones.hasProperty(theZone, "pauseDelay?") then 
		theZone.triggerPauseDelay = cfxZones.getStringFromZoneProperty(theZone, "pauseDelay?", "none")
		theZone.lastTriggerPauseValue = cfxZones.getFlagValue(theZone.triggerPauseDelay, theZone)
	end
	
	if cfxZones.hasProperty(theZone, "continueDelay?") then 
		theZone.triggerContinueDelay = cfxZones.getStringFromZoneProperty(theZone, "continueDelay?", "none")
		theZone.lastTriggerContinueValue = cfxZones.getFlagValue(theZone.triggerContinueDelay, theZone)
	end
	
	-- timeInfo 
	theZone.delayTimeLeft = cfxZones.getStringFromZoneProperty(theZone, "delayLeft", "*cfxIgnored")

	-- init 
	theZone.delayRunning = false 
	theZone.delayPaused = false 
	theZone.timeLimit = -1 -- current trigger time as calculated relative to getTime()
	theZone.timeLeft = -1 -- in seconds, always kept up to date 
	                      -- but not really used 

	cfxZones.setFlagValue(theZone.delayTimeLeft, -1, theZone)
end


--
-- update 
-- 

function delayFlag.startDelay(theZone) 
	-- refresh timer 
	theZone.delayRunning = true
	
	-- set new expiry date 
	local delayMax = theZone.delayMax
	local delayMin = theZone.delayMin
	local delay = delayMax 
	
	if delayMin ~= delayMax then 
		-- pick random in range , say 3-7 --> 5 s!
		local delayDiff = (delayMax - delayMin) + 1 -- 7-3 + 1
		delay = dcsCommon.smallRandom(delayDiff) - 1 --> 0-4
		delay = delay + delayMin 
		if delay > theZone.delayMax then delay = theZone.delayMax end 
		if delay < 1 then delay = 1 end 
		
		if delayFlag.verbose or theZone.verbose then 
			trigger.action.outText("+++dlyF: delay " .. theZone.name .. " range " .. delayMin .. "-" .. delayMax .. ": selected " .. delay, 30)
		end
	end
	
	theZone.timeLimit = timer.getTime() + delay 
	cfxZones.setFlagValue(theZone.delayTimeLeft, delay, theZone)
end

function delayFlag.pauseDelay(theZone)
	-- we stop delay now, and calculate remaining time for 
	-- continue 
	theZone.remainingTime = theZone.timeLimit - timer.getTime()
	theZone.delayPaused = true 
end

function delayFlag.continueDelay(theZone)
	theZone.timeLimit = timer.getTime() + theZone.remainingTime
	theZone.delayPaused = false 
end

function delayFlag.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(delayFlag.update, {}, timer.getTime() + 1)
	
	local now = timer.getTime() 
	
	for idx, aZone in pairs(delayFlag.flags) do
		-- calculate remaining time on the timer 
		local remaining = aZone.timeLimit - now
		if remaining < 0 then remaining = -1 end 
		
		-- see if we need to stop 
		if cfxZones.testZoneFlag(aZone, aZone.triggerStopDelay, aZone.delayTriggerMethod, "lastTriggerStopValue") then
			aZone.delayRunning = false -- simply stop.
			if delayFlag.verbose or aZone.verbose then 
				trigger.action.outText("+++dlyF: stopped delay " .. aZone.name, 30)
			end 
		end

		
		if cfxZones.testZoneFlag(aZone, aZone.triggerDelayFlag, aZone.delayTriggerMethod, "lastDelayTriggerValue") then
			if delayFlag.verbose or aZone.verbose then 
				if aZone.delayRunning then 
					trigger.action.outText("+++dlyF: re-starting timer " .. aZone.name, 30)	
				else 
					trigger.action.outText("+++dlyF: start timer for " .. aZone.name, 30)
				end
			end 
			delayFlag.startDelay(aZone) -- we restart even if running 
			remaining = aZone.timeLimit - now -- recalc remaining
		end

		if not aZone.delayPaused then 

			if aZone.delayRunning and cfxZones.testZoneFlag(aZone, aZone.triggerPauseDelay, aZone.delayTriggerMethod, "lastTriggerPauseValue") then
				if delayFlag.verbose or aZone.verbose then 
					trigger.action.outText("+++dlyF: pausing timer <" .. aZone.name .. "> with <" .. remaining .. "> remaining", 30)	
				end 
				delayFlag.pauseDelay(aZone)
			end
			
			if aZone.delayRunning then 
				-- check expiry 
				if remaining < 0 then --now > aZone.timeLimit then 
					-- end timer 
					aZone.delayRunning = false 
					-- poll flag 
					if delayFlag.verbose or aZone.verbose then 
						trigger.action.outText("+++dlyF: banging on " .. aZone.delayDoneFlag, 30)
					end
					cfxZones.pollFlag(aZone.delayDoneFlag, aZone.delayMethod, aZone)
				end
			end
			
			cfxZones.setFlagValue(aZone.delayTimeLeft, remaining, aZone)
		else 
			-- we are paused. Check for 'continue'
			if aZone.delayRunning and cfxZones.testZoneFlag(aZone, aZone.triggerContinueDelay, aZone.delayTriggerMethod, "lastTriggerContinueValue") then
				if delayFlag.verbose or aZone.verbose then 
					trigger.action.outText("+++dlyF: continuing timer <" .. aZone.name .. "> with <" .. aZone.remainingTime .. "> seconds remaining", 30)	
				end 
				delayFlag.continueDelay(aZone)
			end
		end
		
	end
end


--
-- LOAD / SAVE
--
function delayFlag.saveData()
	local theData = {}
	local allTimers = {}
	local now = timer.getTime()
	for idx, theDelay in pairs(delayFlag.flags) do 
		local theName = theDelay.name 
		local timerData = {}
		timerData.delayRunning = theDelay.delayRunning
		timerData.delayPaused = theDelay.delayPaused 
		timerData.delayRemaining = theDelay.timeLimit - now
		if timerData.delayRemaining < 0 then timerData.delayRemaining = -1 end  		
		allTimers[theName] = timerData 
	end
	theData.allTimers = allTimers

	return theData
end

function delayFlag.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("delayFlag")
	if not theData then 
		if delayFlag.verbose then 
			trigger.action.outText("+++dlyF Persistence: no save date received, skipping.", 30)
		end
		return
	end
	
	local allTimers = theData.allTimers
	if not allTimers then 
		if delayFlag.verbose then 
			trigger.action.outText("+++dlyF Persistence: no timer data, skipping", 30)
		end		
		return
	end
	
	local now = timer.getTime()
	for theName, theData in pairs(allTimers) do 
		local theTimer = delayFlag.getDelayZoneByName(theName)
		if theTimer then 
			theTimer.delayRunning = theData.delayRunning
			theTimer.delayPaused = theData.delayPaused
			theTimer.timeLimit = now + theData.delayRemaining
			theTimer.timeLeft = theData.delayRemaining
			if theTimer.verbose then 
				trigger.action.outText("+++dlyF loading: timer <" .. theName .. "> has time left <" .. theData.delayRemaining .. ">s, is running <" .. dcsCommon.bool2Text(theData.delayRunning)  .. ">, is paused <" .. dcsCommon.bool2Text(theData.delayPaused)  .. ">.", 30)
			end
		else 
			trigger.action.outText("+++dlyF: persistence: cannot synch delay <" .. theName .. ">, skipping", 40)
		end
	end
end
--
-- START 
--
function delayFlag.readConfigZone()
	local theZone = cfxZones.getZoneByName("delayFlagsConfig") 
	if not theZone then 
		if delayFlag.verbose then 
			trigger.action.outText("+++dlyF: NO config zone!", 30)
		end 
		return 
	end 
	
	delayFlag.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if delayFlag.verbose then 
		trigger.action.outText("+++dlyF: read config", 30)
	end 
end



function delayFlag.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Delay Flags requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Delay Flags", 
		delayFlag.requiredLibs) then
		return false 
	end
	
	-- read config 
	delayFlag.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("timeDelay")
	for k, aZone in pairs(attrZones) do 
		delayFlag.createTimerWithZone(aZone) -- process attributes
		delayFlag.addDelayZone(aZone) -- add to list
	end
	
	-- load any saved data 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = delayFlag.saveData
		persistence.registerModule("delayFlag", callbacks)
		-- now load my data 
		delayFlag.loadData()
	end
	
	-- start update 
	delayFlag.update()
	
	trigger.action.outText("cfx Delay Flag v" .. delayFlag.version .. " started.", 30)
	return true 
end

-- let's go!
if not delayFlag.start() then 
	trigger.action.outText("cfx Delay Flag aborted: missing libraries", 30)
	delayFlag = nil 
end