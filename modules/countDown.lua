countDown = {}
countDown.version = "1.2.0"
countDown.verbose = true 
countDown.ups = 1 
countDown.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}

--[[--
	count down on flags to generate new signal on out 
	Copyright (c) 2022 by Christian Franz and cf/x AG
	
	Version History
	1.0.0 - initial version 
	1.1.0 - Lua interface: callbacks 
	      - corrected verbose (erroneously always suppressed)
		  - triggerFlag --> triggerCountFlag 
	1.1.1 - corrected bug in invokeCallback 
	1.2.0 - DML Flags 
		  - counterOut!
		  - ups config 
	
--]]--

countDown.counters = {}
countDown.callbacks = {}

--
-- add/remove zones
--
function countDown.addCountDown(theZone)
	table.insert(countDown.counters, theZone)
end

function countDown.getCountDownZoneByName(aName) 
	for idx, aZone in pairs(countDown.counters) do 
		if aName == aZone.name then return aZone end 
	end
	if countDown.verbose then 
		trigger.action.outText("+++cntD: no count down with name <" .. aName ..">", 30)
	end 
	
	return nil 
end


--
-- callbacks 
--
function countDown.addCallback(theCallback)
	if not theCallback then return end 
	table.insert(countDown.callbacks, theCallback)
end

function countDown.invokeCallbacks(theZone, val, tminus, zero, belowZero, looping)
	if not val then val = 1 end 
	if not tminus then tminus = false end 
	if not zero then zero = false end 
	if not belowZero then belowZero = false end 
	
	-- invoke anyone who wants to know that a group 
	-- of people was rescued.
	for idx, cb in pairs(countDown.callbacks) do 
		cb(theZone, val, tminus, zero, belowZero, looping)
	end
end
--
-- read attributes
--
function countDown.createCountDownWithZone(theZone)
	-- start val - a range
	theZone.startMinVal, theZone.startMaxVal = cfxZones.getPositiveRangeFromZoneProperty(theZone, "countDown", 1) -- we know this exists
	theZone.currVal = dcsCommon.randomBetween(theZone.startMinVal, theZone.startMaxVal)
	
	if countDown.verbose then 
		trigger.action.outText("+++cntD: initing count down <" .. theZone.name .. "> with " .. theZone.currVal, 30)
	end
	
	
	-- loop 
	theZone.loop = cfxZones.getBoolFromZoneProperty(theZone, "loop", false)

	-- extend after zero
	theZone.belowZero = cfxZones.getBoolFromZoneProperty(theZone, "belowZero", false)
	
	-- method 
	theZone.method = cfxZones.getStringFromZoneProperty(theZone, "method", "flip")
	
	-- trigger flag "count" / "start?"
	if cfxZones.hasProperty(theZone, "count?") then 
		theZone.triggerCountFlag = cfxZones.getStringFromZoneProperty(theZone, "count?", "<none>")
	end

	
	-- can also use in? for counting. we always use triggerCountFlag 
	if cfxZones.hasProperty(theZone, "in?") then 
		theZone.triggerCountFlag = cfxZones.getStringFromZoneProperty(theZone, "in?", "<none>")
	end
	
	if theZone.triggerCountFlag then 
		theZone.lastCountTriggerValue = cfxZones.getFlagValue(theZone.triggerCountFlag, theZone) -- trigger.misc.getUserFlag(theZone.triggerCountFlag) -- save last value
	end
	
	-- zero! bang 
	if cfxZones.hasProperty(theZone, "zero!") then 
		theZone.zeroFlag = cfxZones.getStringFromZoneProperty(theZone, "zero!", "<none>")
	end
	
	if cfxZones.hasProperty(theZone, "out!") then 
		theZone.zeroFlag = cfxZones.getStringFromZoneProperty(theZone, "out!", "<none>")
	end
	
	-- TMinus! bang 
	if cfxZones.hasProperty(theZone, "tMinus!") then 
		theZone.tMinusFlag = cfxZones.getStringFromZoneProperty(theZone, "tMinus!", "<none>")
	end
	
	-- counterOut val 
	if cfxZones.hasProperty(theZone, "counterOut!") then 
		theZone.counterOut = cfxZones.getStringFromZoneProperty(theZone, "counterOut!", "<none>")
	end
end

--
-- Update 
--
function countDown.isTriggered(theZone)
	-- this module has triggered 
	local val = theZone.currVal - 1 -- decrease counter 
	if countDown.verbose then 
		trigger.action.outText("+++cntD: enter triggered: val now: " .. val, 30)
	end
	local tMinus = false 
	local zero = false 
	local belowZero = false 
	local looping = false 
	
	if theZone.counterOut then 
		cfxZones.setFlagValue(theZone.counterOut, val, theZone)
	end
	
	if val > 0 then 
		tMinus = true 
		-- see if we need to bang Tminus 
		if theZone.tMinusFlag then 
			if countDown.verbose then 
				trigger.action.outText("+++cntD: TMINUTS", 30)
			end
			cfxZones.pollFlag(theZone.tMinusFlag, theZone.method, theZone)
		end
		
	elseif val == 0 then 
		-- reached zero 
		zero = true 
		if theZone.zeroFlag then 
			if countDown.verbose then 
				trigger.action.outText("+++cntD: ZERO", 30)
			end
			cfxZones.pollFlag(theZone.zeroFlag, theZone.method, theZone)
		end
		
		if theZone.loop then 
			-- restart time
			looping = true 
			if countDown.verbose then 
				trigger.action.outText("+++cntD: Looping", 30)
			end
			val = dcsCommon.randomBetween(theZone.startMinVal, theZone.startMaxVal)
		end 
		
	else 
		-- below zero
		belowZero = true 
		if theZone.belowZero and theZone.zeroFlag then
			if countDown.verbose then 
				trigger.action.outText("+++cntD: Below Zero", 30)
			end
			cfxZones.pollFlag(theZone.zeroFlag, theZone.method, theZone)
		end 
		
	end
	
	-- callbacks 
	countDown.invokeCallbacks(theZone, val, tMinus, zero, belowZero, looping)
	
	-- update & return 
	theZone.currVal = val 
	
end

function countDown.update()
	-- call me in a second/ups to poll triggers
	timer.scheduleFunction(countDown.update, {}, timer.getTime() + 1/countDown.ups)
		
	for idx, aZone in pairs(countDown.counters) do
		-- make sure to re-start before reading time limit
		if aZone.triggerCountFlag then 
			local currTriggerVal = cfxZones.getFlagValue(aZone.triggerCountFlag, aZone) -- trigger.misc.getUserFlag(aZone.triggerCountFlag)
			if currTriggerVal ~= aZone.lastCountTriggerValue
			then 
				if countDown.verbose then 
					trigger.action.outText("+++cntD: triggered on in?", 30)
				end
				countDown.isTriggered(aZone)
				aZone.lastCountTriggerValue = cfxZones.getFlagValue(aZone.triggerCountFlag, aZone) -- trigger.misc.getUserFlag(aZone.triggerCountFlag) -- save last value
			end
		end
	end
end

--
-- Config & Start
--
function countDown.readConfigZone()
	local theZone = cfxZones.getZoneByName("countDownConfig") 
	if not theZone then 
		if countDown.verbose then 
			trigger.action.outText("+++cntD: NO config zone!", 30)
		end 
		return 
	end 
	
	countDown.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 1)
	-- slowest is once avery 1000 seconds = 17 minutes, doesn't make much sense slower than 1/second anyway 
	
	if countDown.ups < 0.001 then countDown.ups = 0.001 end 
	
	countDown.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if countDown.verbose then 
		trigger.action.outText("+++cntD: read config", 30)
	end 
end

function countDown.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Count Down requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Count Down", countDown.requiredLibs) then
		return false 
	end
	
	-- read config 
	countDown.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("countDown")
	for k, aZone in pairs(attrZones) do 
		countDown.createCountDownWithZone(aZone) -- process attributes
		countDown.addCountDown(aZone) -- add to list
	end
	
	
	-- start update 
	countDown.update()
	
	trigger.action.outText("cfx Count Down v" .. countDown.version .. " started.", 30)
	return true 
end

-- let's go!
if not countDown.start() then 
	trigger.action.outText("cfx Count Down aborted: missing libraries", 30)
	countDown = nil 
end

-- additions: range for start value to randomize 