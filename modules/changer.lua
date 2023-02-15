changer = {}
changer.version = "1.0.5"
changer.verbose = false 
changer.ups = 1 
changer.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
changer.changers = {}
--[[--
	Version History
	1.0.0 - Initial version 
	1.0.1 - Better guards in config to avoid <none> Zone getter warning 
	1.0.2 - on/off: verbosity 
	1.0.3 - NOT on/off
	1.0.4 - a little bit more conversation
	1.0.5 - fixed a bug in verbosity 
	
	Transmogrify an incoming signal to an output signal
	- not 
	- bool
	- value
	- min, max as separate params
	
		
--]]--

function changer.addChanger(theZone)
	table.insert(changer.changers, theZone)
end

function changer.getChangerByName(aName) 
	for idx, aZone in pairs(changer.changers) do 
		if aName == aZone.name then return aZone end 
	end
	if changer.verbose then 
		trigger.action.outText("+++chgr: no changer with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read zone 
-- 
function changer.createChangerWithZone(theZone)
	theZone.changerInputFlag = cfxZones.getStringFromZoneProperty(theZone, "change?", "*<none>")
--	if theZone.changerInputFlag then 
	theZone.lastTriggerChangeValue = cfxZones.getFlagValue(theZone.changerInputFlag, theZone)
--	end
	
	-- triggerChangerMethod
	theZone.triggerChangerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "triggerChangeMethod") then 
		theZone.triggerChangerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerChangeMethod", "change")
	end 
	
	theZone.inEval = cfxZones.getBoolFromZoneProperty(theZone, "inEval", false) -- yes/no to pre-process, default is no, we read value 
	

	theZone.changeTo = cfxZones.getStringFromZoneProperty(theZone, "to", "val") -- val, not, bool
	if cfxZones.hasProperty(theZone, "changeTo") then 
		theZone.changerTo = cfxZones.getStringFromZoneProperty(theZone, "changeTo", "val")
	end
	theZone.changeTo = string.lower(theZone.changeTo)
	theZone.changeTo = dcsCommon.trim(theZone.changeTo)
	
	theZone.changeOut = cfxZones.getStringFromZoneProperty(theZone, "out!", "*none")
	if cfxZones.hasProperty(theZone, "changeOut!") then 
		theZone.changeOut = cfxZones.getStringFromZoneProperty(theZone, "changeOut!", "*none")
	end
	
	-- pause / on / off commands
	theZone.changerPaused = cfxZones.getBoolFromZoneProperty(theZone, "paused", false) -- we default to unpaused
	if cfxZones.hasProperty(theZone, "changePaused") then 
		theZone.changerPaused = cfxZones.getBoolFromZoneProperty(theZone, "changePaused", false)
	end
	
	if theZone.changerPaused and (changer.verbose or theZone.verbose) then 
		trigger.action.outText("+++chgr: <" .. theZone.name .. "> starts paused", 30)
	end
	
	if cfxZones.hasProperty(theZone, "on?") then 
		theZone.changerOn = cfxZones.getStringFromZoneProperty(theZone, "on?", "*<none>")
		theZone.lastChangerOnValue = cfxZones.getFlagValue(theZone.changerOn, theZone)
	elseif cfxZones.hasProperty(theZone, "changeOn?") then 
		theZone.changerOn = cfxZones.getStringFromZoneProperty(theZone, "changeOn?", "*<none>")
		theZone.lastChangerOnValue = cfxZones.getFlagValue(theZone.changerOn, theZone)
	end
	
	if cfxZones.hasProperty(theZone, "off?") then 
		theZone.changerOff = cfxZones.getStringFromZoneProperty(theZone, "off?", "*<none>")
		theZone.lastChangerOffValue = cfxZones.getFlagValue(theZone.changerOff, theZone)
	elseif cfxZones.hasProperty(theZone, "changeOff?") then 
		theZone.changerOff = cfxZones.getStringFromZoneProperty(theZone, "changeOff?", "*<none>")
		theZone.lastChangerOffValue = cfxZones.getFlagValue(theZone.changerOff, theZone)
	end
	
	
	if changer.verbose or theZone.verbose then 
		trigger.action.outText("+++chgr: new changer zone <".. theZone.name ..">", 30)
	end
	
	if cfxZones.hasProperty(theZone, "min") then 
		theZone.changeMin = cfxZones.getNumberFromZoneProperty(theZone, "min", 0)
	end
	if cfxZones.hasProperty(theZone, "max") then 
		theZone.changeMax = cfxZones.getNumberFromZoneProperty(theZone, "max", 1)
	end
	
	if cfxZones.hasProperty(theZone, "On/Off?") then 
		theZone.changerOnOff = cfxZones.getStringFromZoneProperty(theZone, "On/Off?", "*<none>", 1)
	end
	if cfxZones.hasProperty(theZone, "changeOn/Off?") then 
		theZone.changerOnOff = cfxZones.getStringFromZoneProperty(theZone, "changeOn/Off?", "*<none>", 1)
	end
	if cfxZones.hasProperty(theZone, "NOT On/Off?") then 
		theZone.changerOnOffINV = cfxZones.getStringFromZoneProperty(theZone, "NOT On/Off?", "*<none>", 1)
	end
	if cfxZones.hasProperty(theZone, "NOT changeOn/Off?") then 
		theZone.changerOnOffINV = cfxZones.getStringFromZoneProperty(theZone, "NOT changeOn/Off?", "*<none>", 1)
	end
end

--
-- MAIN ACTION
--
function changer.process(theZone)
	-- read the line 
	local inVal = cfxZones.getFlagValue(theZone.changerInputFlag, theZone)
	currVal = inVal
	if theZone.inEval then 
		currVal = cfxZones.evalFlagMethodImmediate(currVal, theZone.triggerChangerMethod, theZone)
	end
	
	if type(currVal) == "boolean" then 
		if currVal then currVal = 1 else currVal = 0 end 
	end
		
	local res = currVal
	local op = theZone.changeTo
	-- process and write outflag
	if op == "bool" then 
		if currVal == 0 then res = 0 else res = 1 end		
	
	elseif op == "val" or op == "direct" then 
		-- do nothing
		
	elseif op == "not" then 
		if currVal == 0 then res = 1 else res = 0 end
		
	elseif op == "sign" or op == "sgn" then
		if currVal < 0 then res = -1 else res = 1 end 
		
	elseif op == "inv" or op == "invert" or op == "neg" or op == "negative" then 
		res = -res
		
	elseif op == "abs" then 
		res = math.abs(res)
		
	else 
		trigger.action.outText("+++chgr: unsupported changeTo operation <" .. op .. "> in zone <" .. theZone.name  .. ">, using 'val' instead", 30)
	end
	-- illegal ops drop through after warning, functioning as 'val'
	
	-- min / max handling 
	if theZone.changeMin then 
		if theZone.verbose then 
			trigger.action.outText("+++chgr: applying min " .. theZone.changeMin .. " to curr val: " .. res, 30)
		end 
		if res < theZone.changeMin then res = theZone.changeMin end 
	end
	
	if theZone.changeMax then 
		if theZone.verbose then 
			trigger.action.outText("+++chgr: applying max " .. theZone.changeMax .. " to curr val: " .. res, 30)
		end 
		if res > theZone.changeMax then res = theZone.changeMax end 
	end
	
	-- write out 
	cfxZones.setFlagValueMult(theZone.changeOut, res, theZone)
	if changer.verbose or theZone.verbose then 
		trigger.action.outText("+++chgr: changed <" .. inVal .. "> via op=(" .. op .. ") to <" .. res .. "> for <" .. theZone.name .. ">", 10)
	end
	
	-- remember last value in case we need it 
	theZone.lastTriggerChangeValue = currVal -- we should never need to use this, but leave it in for now. note we save currVal, not res...
end


--
-- Update 
--

function changer.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(changer.update, {}, timer.getTime() + 1/changer.ups)
		
	for idx, aZone in pairs(changer.changers) do
		
		-- process the pause/unpause flags 
		-- see if we should suspend 
		if cfxZones.testZoneFlag(aZone, aZone.changerOn, "change", "lastChangerOnValue") then 
			if changer.verbose or aZone.verbose then 
				trigger.action.outText("+++chgr: enabling " .. aZone.name, 30)
			end 
			aZone.changerPaused = false 
		end
		
		if cfxZones.testZoneFlag(aZone, aZone.changerOff, "change", "lastChangerOffValue") then 
			if changer.verbose or aZone.verbose then 
				trigger.action.outText("+++chgr: DISabling " .. aZone.name, 30)
			end 
			aZone.changerPaused = true 
		end
		
		-- do processing if not paused
		if aZone.changerOnOff and aZone.changerOnOffINV then 
			trigger.action.outText("+++chgr: WARNING - zone <" .. aZone.name .. "> has conflicting change On/off inputs, disregating inverted input (NOT changeOn/off?)", 30)
		end
		
		if not aZone.changerPaused then
			if aZone.changerOnOff then 
				if cfxZones.getFlagValue(aZone.changerOnOff, aZone) > 0 then
					changer.process(aZone)
				else 
					if changer.verbose or aZone.verbose then 
						trigger.action.outText("+++chgr: " .. aZone.name .. " gate closed [flag <" .. aZone.changerOnOff .. "> is 0].", 30)
					end 
				end
			elseif aZone.changerOnOffINV then 
				if cfxZones.getFlagValue(aZone.changerOnOffINV, aZone) == 0 then
					changer.process(aZone)
				else 
					if changer.verbose or aZone.verbose then 
						trigger.action.outText("+++chgr: " .. aZone.name .. " gate closed [INVflag <" .. aZone.changerOnOffINV .. "> is 1].", 30)
					end 
				end
			else
				changer.process(aZone)
			end
		else 
			if aZone.verbose then 
				trigger.action.outText("+++chgr: <" .. aZone.name .. "> is paused.", 30)
			end	
		end 
	end
end


--
-- Config & Start
--
function changer.readConfigZone()
	local theZone = cfxZones.getZoneByName("changerConfig") 
	if not theZone then 
		if changer.verbose then 
			trigger.action.outText("+++chgr: NO config zone!", 30)
		end 
		theZone = cfxZones.createSimpleZone("changerConfig") -- temp only
	end 
	
	changer.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	changer.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 1)
		
	if changer.verbose then 
		trigger.action.outText("+++chgr: read config", 30)
	end 
end

function changer.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx changer requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx changer", changer.requiredLibs) then
		return false 
	end
	
	-- read config 
	changer.readConfigZone()
	
	-- process changer Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("change?")
	for k, aZone in pairs(attrZones) do 
		changer.createChangerWithZone(aZone) -- process attributes
		changer.addChanger(aZone) -- add to list
	end
	
	-- start update 
	changer.update()
	
	trigger.action.outText("cfx Changer v" .. changer.version .. " started.", 30)
	return true 
end

-- let's go!
if not changer.start() then 
	trigger.action.outText("cfx changer aborted: missing libraries", 30)
	changer = nil 
end

--[[--
 Possible expansions
 	- rnd

--]]--