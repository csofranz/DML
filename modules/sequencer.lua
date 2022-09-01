sequencer = {}
sequencer.version = "1.0.0"
sequencer.verbose = false 
sequencer.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
--[[--
	Sequencer: pull flags in a sequence with oodles of features
	
	Copyright (c) 2022 by Christian Franz
--]]--

sequencer.sequencers = {}

function sequencer.addSequencer(theZone)
	if not theZone then return end 
	table.insert(sequencer.sequencers, theZone)
end

function sequencer.getSequenceByName(aName) 
	if not aName then return nil end 
	for idx, aZone in pairs(sequencer.sequencers) do 
		if aZone.name == aName then return aZone end 
	end
	return nil 
end

--
-- read from ME 
--

function sequencer.createSequenceWithZone(theZone)
	local seqRaw = cfxZones.getStringFromZoneProperty(theZone, "sequence!", "none")
	local theFlags = dcsCommon.flagArrayFromString(seqRaw)
	theZone.sequence = theFlags
	local interRaw = cfxZones.getStringFromZoneProperty(theZone, "intervals", "86400")
	if cfxZones.hasProperty(theZone, "interval") then 
		interRaw = cfxZones.getStringFromZoneProperty(theZone, "interval", "86400") -- = 24 * 3600 = 24 hours default interval 
	end
	
	local theIntervals = dcsCommon.rangeArrayFromString(interRaw, false)
	theZone.intervals = theIntervals
	
	theZone.seqIndex = 1 -- we start at one 
	theZone.intervalIndex = 1 -- here too
	
	theZone.onStart = cfxZones.getBoolFromZoneProperty(theZone, "onStart", false)
	theZone.zeroSequence = cfxZones.getBoolFromZoneProperty(theZone, "zeroSequence", true)
	
	theZone.seqLoop = cfxZones.getBoolFromZoneProperty(theZone, "loop", false)
	
	theZone.seqRunning = false 
	theZone.seqComplete = false 
	theZone.seqStarted = false 
	
	theZone.timeLimit = 0 -- will be set to when we expire 
	if cfxZones.hasProperty(theZone, "done!") then 
		theZone.seqDone = cfxZones.getStringFromZoneProperty(theZone, "done!", "<none>")
	elseif cfxZones.hasProperty(theZone, "seqDone!") then 
		theZone.seqDone = cfxZones.getStringFromZoneProperty(theZone, "seqDone!", "<none>")
	end
	
	if cfxZones.hasProperty(theZone, "next?") then 
		theZone.nextSeq = cfxZones.getStringFromZoneProperty(theZone, "next?", "<none>")
		theZone.lastNextSeq = cfxZones.getFlagValue(theZone.nextSeq, theZone)
	end
	
	if cfxZones.hasProperty(theZone, "startSeq?") then 
		theZone.startSeq = cfxZones.getStringFromZoneProperty(theZone, "startSeq?", "<none>")
		theZone.lastStartSeq = cfxZones.getFlagValue(theZone.startSeq, theZone)
		--trigger.action.outText("read as " .. theZone.startSeq, 30)
	end
	
	if cfxZones.hasProperty(theZone, "stopSeq?") then 
		theZone.stopSeq = cfxZones.getStringFromZoneProperty(theZone, "stopSeq?", "<none>")
		theZone.lastStopSeq = cfxZones.getFlagValue(theZone.stopSeq, theZone)
	end
	
	if cfxZones.hasProperty(theZone, "resetSeq?") then 
		theZone.resetSeq = cfxZones.getStringFromZoneProperty(theZone, "resetSeq?", "<none>")
		theZone.lastResetSeq = cfxZones.getFlagValue(theZone.resetSeq, theZone)
	end
	
	
	-- methods
	theZone.seqMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "seqMethod") then 
		theZone.seqMethod = cfxZones.getStringFromZoneProperty(theZone, "seqMethod", "inc")
	end
	
	theZone.seqTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "seqTriggerMethod") then 
		theZone.seqTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "seqTriggerMethod", "change")
	end
	
	if (not theZone.onStart) and not (theZone.startSeq) then 
		trigger.action.outText("+++seq: WARNING - sequence <" .. theZone.name .. "> cannot be started: no startSeq? and onStart is false", 30)
	end
end

function sequencer.fire(theZone)
	-- time's up. poll flag at index
	local theFlag = theZone.sequence[theZone.seqIndex]
	if theFlag then 
		cfxZones.pollFlag(theFlag, theZone.seqMethod, theZone)
		if theZone.verbose or sequencer.verbose then 
			trigger.action.outText("+++seq: triggering flag <" .. theFlag .. "> for index <" .. theZone.seqIndex .. "> in sequence <" .. theZone.name .. ">", 30)
		end
	else 
		trigger.action.outText("+++seq: ran out of sequences for <" .. theZone.name .. "> on index <" .. theZone.seqIndex .. ">", 30)
	end
end

function sequencer.advanceInterval(theZone)
	theZone.intervalIndex = theZone.intervalIndex + 1
	if theZone.intervalIndex > #theZone.intervals then 
		theZone.intervalIndex = 1 -- always loops 
	end
end

function sequencer.advanceSeq(theZone)
	-- get the next index for the sequence
	theZone.seqIndex = theZone.seqIndex + 1
	
	-- loop if over and enabled
	if theZone.seqIndex > #theZone.sequence then 
		if theZone.seqLoop then 
			theZone.seqIndex = 1
		else 
			return false
		end
	end
	-- returns true if success
	return true
end

function sequencer.startWaitCycle(theZone)
	if theZone.seqComplete then return end 
	local bounds = theZone.intervals[theZone.intervalIndex]
	local newInterval = dcsCommon.randomBetween(bounds[1], bounds[2])
	theZone.timeLimit = timer.getTime() + newInterval
	if theZone.verbose or sequencer.verbose then 
		trigger.action.outText("+++seq: start wait for <" .. newInterval .. "> in sequence <" .. theZone.name .. ">", 30)
	end
end

function sequencer.pause(theZone)
	if theZone.seqComplete then return end 
	if not theZone.seqRunning then return end 
	local now = timer.getTime()
	theZone.timeRemaining = theZone.timeLimit - now 
	theZone.seqRunning = false 
end

function sequencer.continue(theZone)
	if theZone.seqComplete then return end -- Frankie says: no more 
	if theZone.seqRunning then return end -- we are already running 
	
	-- reset any lingering 'next' flags so they don't 
	-- trigger a newly started sequence 
	if theZone.nextSeq then 
		theZone.lastNextSeq = cfxZones.getFlagValue(theZone.nextSeq, theZone)
	end 
	
	if not theZone.seqStarted then 
		-- this is the very first time we are running.
		if theZone.zeroSequence then 
			-- start with a bang 
			sequencer.fire(theZone)
			sequencer.advanceSeq(theZone)
		end
		theZone.seqRunning = true 
		theZone.seqStarted = true 
		sequencer.startWaitCycle(theZone)
		return 
	end 

	-- we are continuing a paused sequencer 
	local now = timer.getTime()
	if not theZone.timeRemaining then theZone.timeRemaining = 1 end 
	theZone.timeLimit = now + theZone.timeRemaining
	theZone.seqRunning = true 
end

function sequencer.reset(theZone)
	theZone.seqComplete = false 
	theZone.seqRunning = false 
	theZone.seqIndex = 1 -- we start at one 
	theZone.intervalIndex = 1 -- here too
	theZone.seqStarted = false 
	if theZone.onStart then 
		theZone.continue(theZone)
	end
end

---
--- update 
---
function sequencer.update()
	-- call me in a second to poll triggers
	local now = timer.getTime()
	timer.scheduleFunction(sequencer.update, {}, now + 1)
	
	for idx, theZone in pairs(sequencer.sequencers) do
		-- see if reset was pulled
		if theZone.resetSeq and cfxZones.testZoneFlag(theZone, theZone.resetSeq, theZone.seqTriggerMethod, "lastResetSeq") then
			sequencer.reset(theZone)
		end
		
		--trigger.action.outText("have as " .. theZone.startSeq, 30)
		-- first, check if we need to pause or continue
		if (not theZone.seqRunning) and theZone.startSeq and
		cfxZones.testZoneFlag(theZone, theZone.startSeq, theZone.seqTriggerMethod, "lastStartSeq") then 
			sequencer.continue(theZone)
			if theZone.verbose or sequencer.verbose then
				trigger.action.outText("+++seq: continuing sequencer <" .. theZone.name .. ">", 30)
			end
		else 
			-- synch the start flag so we don't immediately trigger 
			-- when it starts
			if theZone.startSeq then 
				theZone.lastStartSeq = cfxZones.getFlagValue(theZone.startSeq, theZone)
			end
		end
	
		if theZone.seqRunning and theZone.stopSeq and
		cfxZones.testZoneFlag(theZone, theZone.stopSeq, theZone.seqTriggerMethod, "lastStopSeq") then 
			sequencer.pause(theZone)
			if theZone.verbose or sequencer.verbose then
				trigger.action.outText("+++seq: pausing sequencer <" .. theZone.name .. ">", 30)
			end
		else 
			if theZone.stopSeq then 
				theZone.lastStopSeq = cfxZones.getFlagValue(theZone.stopSeq, theZone)
			end
		end
	
		-- if we are running, see if we timed out 
		if theZone.seqRunning then 
			-- check if we have received a 'next' signal 
			local doNext = false 
			if theZone.nextSeq then 
				doNext = cfxZones.testZoneFlag(theZone, theZone.nextSeq, theZone.seqTriggerMethod, "lastNextSeq") 
				if doNext and (sequencer.verbose or theZone.verbose) then 
					trigger.action.outText("+++seq: 'next' command received for sequencer <" .. theZone.name .. "> on <" .. theZone.nextSeq .. ">", 30)
				end
			end 
			
			-- check if we are over time limit
			if doNext or (theZone.timeLimit < now) then 
				-- we are timed out or triggered!
				if theZone.nextSeq then
					theZone.lastNextSeq = cfxZones.getFlagValue(theZone.nextSeq, theZone)
				end 
				sequencer.fire(theZone)
				sequencer.advanceInterval(theZone)
				if sequencer.advanceSeq(theZone) then 
					-- start next round
					sequencer.startWaitCycle(theZone)
				else 
					if theZone.seqDone then 
						cfxZones.pollFlag(theZone.seqDone, theZone.seqMethod, theZone)
						if theZone.verbose or sequencer.verbose then 
							trigger.action.outText("+++seq: banging done! flag <" .. theZone.seqDone .. "> for sequence <" .. theZone.name .. ">", 30)
						end
					end
					theZone.seqRunning = false 
					theZone.seqComplete = true -- can't be restarted unless reset
				end -- else no advance
			end -- if time limit 
		end -- if running 
	end -- for all sequencers 
end

--
-- start cycle: force all onStart to fire 
--
function sequencer.startCycle()
	for idx, theZone in pairs(sequencer.sequencers) do
		-- a sequence can be already running when persistence
		-- loaded a sequencer
		if theZone.onStart then 
			if theZone.seqStarted then 
				-- suppressed by persistence 
			else 
				if sequencer.verbose or theZone.verbose then 
					trigger.action.outText("+++seq: starting sequencer " .. theZone.name, 30)
				end 
				sequencer.continue(theZone)
			end 
		end
	end
end

--
-- LOAD / SAVE 
--
function sequencer.saveData()
	local theData = {}
	local allSequencers = {}
	local now = timer.getTime()
	for idx, theSeq in pairs(sequencer.sequencers) do 
		local theName = theSeq.name 
		local seqData = {}
 		seqData.seqComplete = theSeq.seqComplete
		seqData.seqRunning = theSeq.seqRunning
		seqData.seqIndex = theSeq.seqIndex 
		seqData.intervalIndex = theSeq.intervalIndex 
		seqData.seqStarted = theSeq.seqStarted
		seqData.timeRemaining = theSeq.timeRemaining
		if theSeq.seqRunning then 
			seqData.timeRemaining = theSeq.timeLimit - now 
		end
			
		allSequencers[theName] = seqData 
	end
	theData.allSequencers = allSequencers
	return theData
end

function sequencer.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("sequencer")
	if not theData then 
		if sequencer.verbose then 
			trigger.action.outText("+++seq Persistence: no save date received, skipping.", 30)
		end
		return
	end
	
	local allSequencers = theData.allSequencers
	if not allSequencers then 
		if sequencer.verbose then 
			trigger.action.outText("+++seq Persistence: no sequencer data, skipping", 30)
		end		
		return
	end
	
	local now = timer.getTime()
	for theName, seqData in pairs(allSequencers) do 
		local theSeq = sequencer.getSequenceByName(theName)
		if theSeq then 
			theSeq.seqComplete = seqData.seqComplete
			theSeq.seqIndex = seqData.seqIndex
			theSeq.intervalIndex = seqData.intervalIndex
			theSeq.seqStarted = seqData.seqStarted
			theSeq.seqRunning = seqData.seqRunning
			theSeq.timeRemaining = seqData.timeRemaining
			if theSeq.seqRunning then
				theSeq.timeLimit = now + theSeq.timeRemaining
			end
			
		else 
			trigger.action.outText("+++seq: persistence: cannot synch sequencer <" .. theName .. ">, skipping", 40)
		end
	end
end

--
-- start module and read config 
--
function sequencer.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("sequencerConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("sequencerConfig")
		if sequencer.verbose then 
			trigger.action.outText("***RND: NO config zone!", 30)
		end 
	end 
	
	sequencer.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if sequencer.verbose then 
		trigger.action.outText("***RND: read config", 30)
	end 
end

function sequencer.start()
	-- lib check
	if not dcsCommon then 
		trigger.action.outText("sequencer requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Sequencer", 
		sequencer.requiredLibs) then
		return false 
	end
	
	-- read config 
	sequencer.readConfigZone()
	
	-- process RND Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("sequence!")
	
	if sequencer.verbose then 
		local a = dcsCommon.getSizeOfTable(attrZones)
		trigger.action.outText("sequencers: " .. a, 30)
	end 
	
	-- now create an rnd gen for each one and add them
	-- to our watchlist 
	for k, aZone in pairs(attrZones) do 
		sequencer.createSequenceWithZone(aZone) -- process attribute and add to zone
		sequencer.addSequencer(aZone) -- remember it so we can smoke it
	end

	
	-- persistence
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = sequencer.saveData
		persistence.registerModule("sequencer", callbacks)
		-- now load my data 
		sequencer.loadData()
	end
		
	-- schedule start cycle 
	timer.scheduleFunction(sequencer.startCycle, {}, timer.getTime() + 0.25)

	-- start update 
	timer.scheduleFunction(sequencer.update, {}, timer.getTime() + 1)
	
	trigger.action.outText("cfx Sequencer v" .. sequencer.version .. " started.", 30)
	return true 
end

-- let's go!
if not sequencer.start() then 
	trigger.action.outText("cf/x Sequencer aborted: missing libraries", 30)
	sequencer = nil 
end

--[[--
	to do: 
	- currSeq always returns current sequence number 
	- timeLeft returns current time limit in seconds 
--]]--