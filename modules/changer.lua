changer = {}
changer.version = "1.0.0"
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
	
	Transmogrify an incoming signal to an output signal
	- not 
	- bool
	- value
		
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
	theZone.triggerChangerFlag = cfxZones.getStringFromZoneProperty(theZone, "change?", "*<none>")
--	if theZone.triggerChangerFlag then 
	theZone.lastTriggerChangeValue = cfxZones.getFlagValue(theZone.triggerChangerFlag, theZone)
--	end
	
	-- triggerChangerMethod
	theZone.triggerChangerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "triggerChangeMethod") then 
		theZone.triggerChangerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerChangeMethod", "change")
	end 
	
	theZone.inEval = cfxZones.getBoolFromZoneProperty(theZone, "inEval", true) -- yes/no to pre-process, default is yes 
	

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
	
	theZone.changerOn = cfxZones.getStringFromZoneProperty(theZone, "on?", "*<none>")
	if cfxZones.hasProperty(theZone, "changeOn?") then 
		theZone.changerOn = cfxZones.getStringFromZoneProperty(theZone, "changeOn?", "*<none>")
	end
	theZone.lastChangerOnValue = cfxZones.getFlagValue(theZone.changerOn, theZone)
	
	theZone.changerOff = cfxZones.getStringFromZoneProperty(theZone, "off?", "*<none>")
	if cfxZones.hasProperty(theZone, "changeOff?") then 
		theZone.changerOff = cfxZones.getStringFromZoneProperty(theZone, "changeOff?", "*<none>")
	end
	theZone.lastChangerOffValue = cfxZones.getFlagValue(theZone.changerOff, theZone)
	
	if changer.verbose or theZone.verbose then 
		trigger.action.outText("+++chgr: new changer zone <".. theZone.name ..">", 30)
	end
	
end

--
-- MAIN ACTION
--
function changer.process(theZone)
	-- read the line 
	local inVal = cfxZones.getFlagValue(theZone.triggerChangerFlag, theZone)
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
	elseif op == "not" then 
		if currVal == 0 then res = 1 else res = 0 end
	elseif op == "val" or op == "direct" then 
		-- do nothing
	else 
		trigger.action.outText("+++chgr: unsupported changeTo operation <" ..  .. "> in zone <" ..  .. ">, using 'val'", 30)
	end
	-- illegal ops drop through after warning, functioning as 'val'
	
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
		if cfxZones.testZoneFlag(theZone, theZone.changerOn, "change", "lastChangerOnValue") then 
			if changer.verbose or theZone.verbose then 
				trigger.action.outText("+++chgr: enabling " .. theZone.name, 30)
			end 
			theZone.changerPaused = false 
		end
		
		if cfxZones.testZoneFlag(theZone, theZone.changerOff, "change", "lastChangerOffValue") then 
			if changer.verbose or theZone.verbose then 
				trigger.action.outText("+++chgr: DISabling " .. theZone.name, 30)
			end 
			theZone.changerPaused = true 
		end
		
		-- do processing if not paused
		if not aZone.changerPaused then 
			changer.process(aZone)
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
	
	-- process cloner Zones 
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
	- min, max minmax 2,3, cap to left right values, 

--]]--