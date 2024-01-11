delayFlag = {}
delayFlag.version = "2.0.0"
delayFlag.verbose = false  
delayFlag.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
delayFlag.flags = {}

--[[--
	delay flags - simple flag switch & delay, allows for randomize
	and dead man switching 
	
	Copyright (c) 2022-2024 by Christian Franz and cf/x AG
	
	Version History
	1.4.0 - dmlZones 
		  - delayLeft#
	2.0.0 - clean-up 
	
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
	theZone.delayMin, theZone.delayMax = theZone:getPositiveRangeFromZoneProperty("timeDelay", 1) -- same as zone signature 
	if delayFlag.verbose or theZone.verbose then 
		trigger.action.outText("+++dlyF: time delay is <" .. theZone.delayMin .. ", " .. theZone.delayMax .. "> seconds", 30)
	end

	-- watchflags:
	-- triggerMethod
	theZone.delayTriggerMethod = theZone:getStringFromZoneProperty("triggerMethod", "change")

	if theZone:hasProperty("delayTriggerMethod") then 
		theZone.delayTriggerMethod = theZone:getStringFromZoneProperty("delayTriggerMethod", "change")
	end

	-- trigger flag 
	if theZone:hasProperty("f?") then 
		theZone.triggerDelayFlag = theZone:getStringFromZoneProperty("f?", "none")
	elseif theZone:hasProperty("in?") then 
		theZone.triggerDelayFlag = theZone:getStringFromZoneProperty("in?", "none")
	elseif theZone:hasProperty("startDelay?") then 
		theZone.triggerDelayFlag = theZone:getStringFromZoneProperty("startDelay?", "none")
	end
	
	if theZone.triggerDelayFlag then 
		theZone.lastDelayTriggerValue = theZone:getFlagValue(theZone.triggerDelayFlag)
	end
	
	
	theZone.delayMethod = theZone:getStringFromZoneProperty("method", "inc")
	
	if theZone:hasProperty("delayMethod") then
		theZone.delayMethod = theZone:getStringFromZoneProperty( "delayMethod", "inc")
	end
	
	-- out flag 
	theZone.delayDoneFlag = theZone:getStringFromZoneProperty("out!", "*<none>")

	
	if theZone:hasProperty("delayDone!") then 
		theZone.delayDoneFlag = theZone:getStringFromZoneProperty( "delayDone!", "*<none>")
	end

	-- stop the press!
	if theZone:hasProperty("stopDelay?") then 
		theZone.triggerStopDelay = theZone:getStringFromZoneProperty("stopDelay?", "none")
		theZone.lastTriggerStopValue = theZone:getFlagValue(theZone.triggerStopDelay)
	end
	
	-- pause and continue
	if theZone:hasProperty("pauseDelay?") then 
		theZone.triggerPauseDelay = theZone:getStringFromZoneProperty("pauseDelay?", "none")
		theZone.lastTriggerPauseValue = theZone:getFlagValue(theZone.triggerPauseDelay)
	end
	
	if theZone:hasProperty("continueDelay?") then 
		theZone.triggerContinueDelay = theZone:getStringFromZoneProperty("continueDelay?", "none")
		theZone.lastTriggerContinueValue = theZone:getFlagValue(theZone.triggerContinueDelay)
	end
	
	-- timeInfo 
	if theZone:hasProperty("delayLeft") then 
		theZone.delayTimeLeft = theZone:getStringFromZoneProperty("delayLeft", "*cfxIgnored")
	else 
		theZone.delayTimeLeft = theZone:getStringFromZoneProperty("delayLeft#", "*cfxIgnored")
	end

	-- init 
	theZone.delayRunning = false 
	theZone.delayPaused = false 
	theZone.timeLimit = -1 -- current trigger time as calculated relative to getTime()
	theZone.timeLeft = -1 -- in seconds, always kept up to date 
	                      -- but not really used 

	theZone:setFlagValue(theZone.delayTimeLeft, -1)
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
	theZone:setFlagValue(theZone.delayTimeLeft, delay)
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
		if aZone:testZoneFlag(aZone.triggerStopDelay, aZone.delayTriggerMethod, "lastTriggerStopValue") then
			aZone.delayRunning = false -- simply stop.
			if delayFlag.verbose or aZone.verbose then 
				trigger.action.outText("+++dlyF: stopped delay " .. aZone.name, 30)
			end 
		end

		
		if aZone:testZoneFlag(aZone.triggerDelayFlag, aZone.delayTriggerMethod, "lastDelayTriggerValue") then
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

			if aZone.delayRunning and aZone:testZoneFlag( aZone.triggerPauseDelay, aZone.delayTriggerMethod, "lastTriggerPauseValue") then
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
					aZone:pollFlag(aZone.delayDoneFlag, aZone.delayMethod)
				end
			end
			
			aZone:setFlagValue(aZone.delayTimeLeft, remaining)
		else 
			-- we are paused. Check for 'continue'
			if aZone.delayRunning and aZone:testZoneFlag( aZone.triggerContinueDelay, aZone.delayTriggerMethod, "lastTriggerContinueValue") then
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
		theZone = cfxZones.createSimpleZone("delayFlagsConfig")
	end 
	
	delayFlag.verbose = theZone.verbose 
	
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