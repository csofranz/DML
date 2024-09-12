sittingDucks = {}
sittingDucks.verbose = false 
sittingDucks.version = "1.0.1"
sittingDucks.ssbDisabled = 100 -- must match the setting of SSB, usually 100
sittingDucks.resupplyTime = -1 -- seconds until "reinforcements" reopen the slot, set to -1 to turn off, 3600 is one hour
sittingDucks.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
	"stopGap",
}

--[[
Version History 

1.0.0 Initial Version 
1.0.1 DCS releases 2024-jul-11 and 2024-jul-22 bugs hardening 

--]]--

--
-- Destroying a client stand-in on an airfield will block that 
-- Slot for players. Multiplayer only 
-- WARNING: ENTIRE GROUP will be blocked when one aircraft is destroyed 
--
-- MULTIPLAYER-ONLY. REQUIRES (on the server):
--  1) SSB running on the server AND 
--  2) set SSB.kickReset = false 
--

function sittingDucks:onEvent(event)
	if not event then return end 
	if not event.id then return end 
	if not event.initiator then return end 

	if not sittingDucks.enabled then return end -- olny look if we are turned on 
	
	-- home in on the kill event 
	if event.id == 8 then -- dead event 
		local theUnit = event.initiator
		if not theUnit.getName then return end -- dcs jul-11 and jul-22 bugs
		local deadName = theUnit:getName()
		if not deadName then return end 
		-- look at stopGap's collection of stand-ins
		for gName, staticGroup in pairs (stopGap.standInGroups) do 
			for uName, aStatic in pairs(staticGroup) do 
				if uName == deadName then -- yup, a stand-in. block	 entire group
					local blockState = sittingDucks.ssbDisabled
					trigger.action.setUserFlag(gName, blockState)
					-- tell cfxSSBClient as well - if it's loaded
					if cfxSSBClient and cfxSSBClient.slotState then 
						cfxSSBClient.slotState[gName] = blockState
					end
					if sittingDucks.verbose then 
						trigger.action.outText("SittingDucks: in group <" .. gName .. "> unit <" .. uName .. "> was destroyed on the ground, group blocked.", 30)
					end
					if sittingDucks.resupplyTime > 0 then 
						timer.scheduleFunction(sittingDucks.resupply, gName, timer.getTime() + sittingDucks.resupplyTime)
					end
					return 
				end
			end 
		end
	end
	
end

-- re-supply: enable slots after some time
function sittingDucks.resupply(args)
	local gName = args
	trigger.action.setUserFlag(gName, 0)
	if cfxSSBClient and cfxSSBClient.slotState then 
		cfxSSBClient.slotState[gName] = 0
	end
	if stopGap.standInGroups[gName] then -- should not happen, just in case
		stopGap.removeStaticGapGroupNamed(gName)  
	end 
	if sittingDucks.verbose then 
		trigger.action.outText("SittingDucks: group <" .. gName .. "> re-supplied, slots reopened.", 30)
	end
end

--
-- Update 
--
--
function sittingDucks.update()
	-- check every second. 
	timer.scheduleFunction(sittingDucks.update, {}, timer.getTime() + 1)
	
	-- check if signal for on? or off? 
	if sittingDucks.turnOn and cfxZones.testZoneFlag(sittingDucks, sittingDucks.turnOnFlag, sittingDucks.triggerMethod, "lastTurnOnFlag") then
		sittingDucks.enabled = true 
	end
	
	if sittingDucks.turnOff and cfxZones.testZoneFlag(sittingDucks, sittingDucks.turnOffFlag, sittingDucks.triggerMethod, "lastTurnOffFlag") then
		sittingDucks.enabled = false 
	end

end

--
-- Read Config & start
--
sittingDucks.name = "sittingDucksConfig" -- cfxZones compatibility here 
function sittingDucks.readConfigZone(theZone)
	-- currently nothing to do 
	sittingDucks.verbose = theZone.verbose 
	sittingDucks.resupplyTime = cfxZones.getNumberFromZoneProperty(theZone, "resupplyTime", -1)
	sittingDucks.enabled = cfxZones.getBoolFromZoneProperty(theZone, "onStart", true)
	sittingDucks.triggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "on?") then 
		sittingDucks.turnOnFlag = cfxZones.getStringFromZoneProperty(theZone, "on?", "*<none>")
		sittingDucks.lastTurnOnFlag = trigger.misc.getUserFlag(sittingDucks.turnOnFlag)
	end
	if cfxZones.hasProperty(theZone, "off?") then 
		sittingDucks.turnOffFlag = cfxZones.getStringFromZoneProperty(theZone, "off?", "*<none>")
		sittingDucks.lastTurnOffFlag = trigger.misc.getUserFlag(sittingDucks.turnOffFlag)
	end
	
	if sittingDucks.verbose then 
		trigger.action.outText("+++sitD: config read, verbose = YES", 30)
		if sittingDucks.enabled then 
			trigger.action.outText("+++sitD: enabled", 30)
		else 
			trigger.action.outText("+++sitD: turned off", 30)		
		end 
	end
end


function sittingDucks.start()
	if not dcsCommon.libCheck("cfx Sitting Ducks", 
							  stopGap.requiredLibs) 
	then return false end
	
	local theZone = cfxZones.getZoneByName("sittingDucksConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("sittingDucksConfig")
	end
	sittingDucks.readConfigZone(theZone)
	
	-- turn on SSB
	trigger.action.setUserFlag("SSB",100)
	
	-- let's get set up
	world.addEventHandler(sittingDucks) -- event handler in place 
	timer.scheduleFunction(sittingDucks.update, {}, timer.getTime() + 1)
	
	trigger.action.outText("Sitting Ducks v" .. sittingDucks.version .. " running, SSB enabled", 30)
	return true 	
end

if not sittingDucks.start() then  
	trigger.action.outText("Sitting Ducks failed to start up.", 30)
	sittingDucks = {}
end


