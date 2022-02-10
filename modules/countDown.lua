countDown = {}
countDown.version = "1.0.0"
countDown.verbose = true 
countDown.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}

--[[--
	count down on flags to generate new signal on out 
	Copyright (c) 2022 by Christian Franz and cf/x AG
	
	Version History
	1.0.0 - initial version 
	
--]]--

countDown.counters = {}


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
		theZone.triggerFlag = cfxZones.getStringFromZoneProperty(theZone, "count?", "none")
	end

	
	-- can also use in? for counting. we always use triggerflag 
	if cfxZones.hasProperty(theZone, "in?") then 
		theZone.triggerFlag = cfxZones.getStringFromZoneProperty(theZone, "in?", "none")
	end
	
	if theZone.triggerFlag then 
		theZone.lastTriggerValue = trigger.misc.getUserFlag(theZone.triggerFlag) -- save last value
	end
	
	-- zero! bang 
	if cfxZones.hasProperty(theZone, "zero!") then 
		theZone.zeroFlag = cfxZones.getNumberFromZoneProperty(theZone, "zero!", -1)
	end
	
	if cfxZones.hasProperty(theZone, "out!") then 
		theZone.zeroFlag = cfxZones.getNumberFromZoneProperty(theZone, "out!", -1)
	end
	
	-- TMinus! bang 
	if cfxZones.hasProperty(theZone, "tMinus!") then 
		theZone.tMinusFlag = cfxZones.getNumberFromZoneProperty(theZone, "tMinus!", -1)
	end
	
end

--
-- Update 
--
function countDown.isTriggered(theZone)
	-- this module has triggered 
	local val = theZone.currVal - 1 -- decrease counter 
	if theZone.verbose then 
		trigger.action.outText("+++cntD: enter triggered: val now: " .. val, 30)
	end
	if val > 0 then 

		-- see if we need to bang Tminus 
		if theZone.tMinusFlag then 
			if theZone.verbose then 
				trigger.action.outText("+++cntD: TMINUTS", 30)
			end
			cfxZones.pollFlag(theZone.tMinusFlag, theZone.method)
		end
		
	elseif val == 0 then 
		-- reached zero 
		if theZone.zeroFlag then 
			if theZone.verbose then 
				trigger.action.outText("+++cntD: ZERO", 30)
			end
			cfxZones.pollFlag(theZone.zeroFlag, theZone.method)
		end
		
		if theZone.loop then 
			-- restart time
			if theZone.verbose then 
				trigger.action.outText("+++cntD: Looping", 30)
			end
			val = dcsCommon.randomBetween(theZone.startMinVal, theZone.startMaxVal)
		end 
		
	else 
		-- below zero
		if theZone.belowZero and theZone.zeroFlag then
			if theZone.verbose then 
				trigger.action.outText("+++cntD: Below Zero", 30)
			end
			cfxZones.pollFlag(theZone.zeroFlag, theZone.method)
		end 
		
	end
	
	theZone.currVal = val 
	
end

function countDown.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(countDown.update, {}, timer.getTime() + 1)
		
	for idx, aZone in pairs(countDown.counters) do
		-- make sure to re-start before reading time limit
		if aZone.triggerFlag then 
			local currTriggerVal = trigger.misc.getUserFlag(aZone.triggerFlag)
			if currTriggerVal ~= aZone.lastTriggerValue
			then 
				if aZone.verbose then 
					trigger.action.outText("+++cntD: triggered on in?", 30)
				end
				countDown.isTriggered(aZone)
				aZone.lastTriggerValue = trigger.misc.getUserFlag(aZone.triggerFlag) -- save last value
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