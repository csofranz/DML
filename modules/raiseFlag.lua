raiseFlag = {}
raiseFlag.version = "3.0.0"
raiseFlag.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
raiseFlag.flags = {} -- my minions 
--[[--
	(c) 2022-23 by Christian Franz and cf/x AG
	
Version History
 3.0.0 - switched to polling
	   - remains# attribute 
	   - support for persistence
	   - zone-individual verbosity
	   - code cleanup, removed deprecated attributes 
--]]--

function raiseFlag.addRaiseFlag(theZone)
	raiseFlag.flags[theZone.name] = theZone
end
--
-- read attributes
--
function raiseFlag.createRaiseFlagWithZone(theZone)
	theZone.raiseFlag = theZone:getStringFromZoneProperty("raiseFlag!", "<none>") -- the flag to raise 
	theZone.flagValue = theZone:getStringFromZoneProperty("method", "inc")
	theZone.flagValue = theZone.flagValue:lower()
	theZone.minAfterTime, theZone.maxAfterTime = theZone:getPositiveRangeFromZoneProperty("afterTime", -1)
	theZone.raiseTriggerMethod = theZone:getStringFromZoneProperty( "triggerMethod", "change")
	if theZone:hasProperty("raiseTriggerMethod") then 
		theZone.raiseTriggerMethod = theZone:getStringFromZoneProperty("raiseTriggerMethod", "change")
	end
	if theZone:hasProperty("stopFlag?") then 
		theZone.triggerStopFlag = theZone:getStringFromZoneProperty( "stopFlag?", "none")
		theZone.lastTriggerStopValue = theZone:getFlagValue(theZone.triggerStopFlag) -- save last value
	end
	if theZone:hasProperty("timeLeft#") then 
		theZone.timeLeft = theZone:getStringFromZoneProperty("timeLeft#", "none")
	end
	theZone.raiseStopped = false 
	-- now simply schedule for invocation
	if theZone.minAfterTime < 1 then 
		theZone.deadLine = -1 -- will always trigger 
	else
		local delay = cfxZones.randomDelayFromPositiveRange(theZone.minAfterTime, theZone.maxAfterTime)		
		theZone.deadLine = timer.getTime() + delay
	end
end

function raiseFlag.triggered(theZone)
	if theZone.raiseStopped then return end -- should be filtered
	local command = theZone.flagValue
	theZone:pollFlag(theZone.raiseFlag, command)
	if raiseFlag.verbose or theZone.verbose then 
		trigger.action.outText("+++rFlg - raising <" .. theZone.raiseFlag .. "> with method '" .. command .. "'" .. " for zone <" .. theZone.name .. ">" ,30)
	end
end
--
-- update 
--
function raiseFlag.update(firstUpdate)
	local now = timer.getTime()
	timer.scheduleFunction(raiseFlag.update, false, now + 1) -- we always beat on .5 offset!
	local filtered = {}
	for zName, theZone in pairs(raiseFlag.flags) do
		-- see if this timer has run out 
		if theZone.deadLine < now then 
			if theZone.verbose then 
				trigger.action.outText("+++rFlg: will raise flag <" .. theZone.name .. ">", 30)
			end
			raiseFlag.triggered(theZone)
			if theZone.timeLeft then theZone:setFlagValue(theZone.timeLeft, 0) end
			theZone.raiseStopped = true -- will filter 
		elseif theZone.timeLeft then 
			local rem = theZone.deadLine - now 
			theZone:setFlagValue(theZone.timeLeft, rem)
			if theZone.verbose then 
				trigger.action.outText("+++rFlg: time left on <" .. theZone.name .. ">:" .. math.floor(rem)  .. " secs", 30)
			end
		end

		if theZone:testZoneFlag(theZone.triggerStopFlag, theZone.raiseTriggerMethod, "lastTriggerStopValue") then
			theZone.raiseStopped = true -- filter
		end
		
		if not theZone.raiseStopped then 
			filtered[theZone.name] = theZone
		end 
	end
	raiseFlag.flags = filtered 
end
--
-- load / save (game data)
--
function raiseFlag.saveData()
	local theData = {}
	local theFlags = {}
	local now = timer.getTime()
	for name, theZone in pairs (raiseFlag.flags) do  
		-- note: we only process existing!
		theFlags[name] = theZone.deadLine - now 
	end 
	-- save current deadlines 
	theData.theFlags = theFlags
	return theData, raiseFlag.sharedData -- second val currently nil  
end

function raiseFlag.loadData()
	if not persistence then return end 
	local shared = nil 
	local theData = persistence.getSavedDataForModule("raiseFlag")
	if (not theData) then 
		if raiseFlag.verbose then 
			trigger.action.outText("+++rFlg: no save date received, skipping.", 30)
		end
		return
	end
	local theFlags = theData.theFlags
	-- filter and reset timers 
	local filtered = {}
	local now = timer.getTime()
	for name, deadLine in pairs(theFlags) do 
		local theZone = raiseFlag.flags[name]
		if theZone then 
			theZone.deadLine = now + deadLine
			filtered[name] = theZone
			if theZone.verbose then 
				trigger.action.outText("+++rFlg: (persistence) reset zone <" .. name .. "> to <" .. theZone.deadLine .. "> (<" .. deadLine .. ">)", 30)
			end
		else 
			trigger.action.outText("+++rFlag: (persistence) filtered <" .. name .. ">, does not exist in miz.", 30)
		end 
	end 
	for name, theZone in pairs(raiseFlag.flags) do 
		if not filtered[name] and theZone.verbose then 
			trigger.action.outText("+++rFlg: (persistence) filtered spent/non-saved <" .. name .. ">.", 30)
		end
	end 
	raiseFlag.flags = filtered 
end
--
-- config & go!
--
function raiseFlag.readConfigZone()
	local theZone = cfxZones.getZoneByName("raiseFlagConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("raiseFlagConfig")
	end 
	raiseFlag.verbose = theZone.verbose
	if raiseFlag.verbose then 
		trigger.action.outText("+++rFlg: read config", 30)
	end 
end

function raiseFlag.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx raise flag requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Raise Flag", raiseFlag.requiredLibs)then return false end
	raiseFlag.readConfigZone()
	attrZones = cfxZones.getZonesWithAttributeNamed("raiseFlag!")
	for k, aZone in pairs(attrZones) do 
		raiseFlag.createRaiseFlagWithZone(aZone) -- process attributes
		raiseFlag.addRaiseFlag(aZone) -- add to list
	end
	if persistence then 
		callbacks = {}
		callbacks.persistData = raiseFlag.saveData
		persistence.registerModule("raiseFlag", callbacks)
		-- now load my data 
		raiseFlag.loadData()
	end
	-- start update at 0.5 secs mark
	timer.scheduleFunction(raiseFlag.update, true, timer.getTime() + 0.5)
	trigger.action.outText("cfx raiseFlag v" .. raiseFlag.version .. " started.", 30)
	return true 
end

if not raiseFlag.start() then 
	trigger.action.outText("cfx Raise Flag aborted: missing libraries", 30)
	raiseFlag = nil 
end
