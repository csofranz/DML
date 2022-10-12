autoCSAR = {}
autoCSAR.version = "1.0.0" 
autoCSAR.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
autoCSAR.killDelay = 2 * 60 
autoCSAR.counter = 31 -- any nuber is good, to kick-off counting
--[[--
	VERSION HISTORY
	1.0.0 - Initial Version
--]]--

function autoCSAR.removeGuy(args)
	local theGuy = args.theGuy
	if theGuy and theGuy:isExist() then  
		Unit.destroy(theGuy)
	end
end 

function autoCSAR.createNewCSAR(theUnit)
	if not csarManager then 
		trigger.action.outText("+++aCSAR: CSAR Manager not loaded, aborting", 30)
		-- return
	end	
	-- enter with unit from landing_after_eject event
	-- unit has no group 
	local coa = theUnit:getCoalition()
	if coa == 0 then -- neutral
		trigger.action.outText("Neutral Pilot made it safely to ground.", 30)
		return 
	end
	if coa == 1 and not autoCSAR.redCSAR then 
		return -- we don't do red
	end
	if coa == 2 and not autoCSAR.blueCSAR then 
		return -- no blue rescue
	end
	
	-- for later expansion
	local theGroup = theUnit:getGroup()
	if theGroup then 
		trigger.action.outText("We have a group for <" .. theUnit:getName() .. ">", 30)
	end
	
	-- create a CSAR mission now
	csarManager.createCSARForParachutist(theUnit, "Xray-" .. autoCSAR.counter)
	autoCSAR.counter = autoCSAR.counter + 1
	
	-- schedule removal of pilot 
	local args = {}
	args.theGuy = theUnit 			
	timer.scheduleFunction(autoCSAR.removeGuy, args, timer.getTime() + autoCSAR.killDelay)
end

function autoCSAR:onEvent(event)
	if event.id == 31 then -- landing_after_eject
		if event.initiator then 
			autoCSAR.createNewCSAR(event.initiator)
		end
	end
end

function autoCSAR.readConfigZone()
	local theZone = cfxZones.getZoneByName("autoCSARConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("autoCSARConfig")
		if autoCSAR.verbose then 
			trigger.action.outText("+++aCSAR: NO config zone!", 30)
		end 
	end 

	autoCSAR.redCSAR = cfxZones.getBoolFromZoneProperty(theZone, "red", true)
	if cfxZones.hasProperty(theZone, "redCSAR") then 
		autoCSAR.redCSAR = cfxZones.getBoolFromZoneProperty(theZone, "redCSAR", true)
	end
	
	autoCSAR.blueCSAR = cfxZones.getBoolFromZoneProperty(theZone, "blue", true)
	if cfxZones.hasProperty(theZone, "blueCSAR") then 
		autoCSAR.blueCSAR = cfxZones.getBoolFromZoneProperty(theZone, "blueCSAR", true)
	end

	if autoCSAR.verbose then 
		trigger.action.outText("+++aCSAR: read config", 30)
	end 
end

function autoCSAR.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx autoCSAR requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx autoCSAR", autoCSAR.requiredLibs) then
		return false 
	end
	
	-- read config 
	autoCSAR.readConfigZone()
	
	-- connect event handler
	world.addEventHandler(autoCSAR)
	
	trigger.action.outText("cfx autoCSAR v" .. autoCSAR.version .. " started.", 30)
	return true 
end

-- let's go!
if not autoCSAR.start() then 
	trigger.action.outText("cfx autoCSAR aborted: missing libraries", 30)
	autoCSAR = nil 
end
