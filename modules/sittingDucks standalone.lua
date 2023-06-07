sittingDucks = {}
sittingDucks.verbose = false 
sittingDucks.version = "1.0.0"
sittingDucks.ssbDisabled = 100 -- must match the setting of SSB, usually 100
sittingDucks.resupplyTime = -1 -- seconds until "reinforcements" reopen the slot, set to -1 to turn off, 3600 is one hour

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

	-- home in on the kill event 
	if event.id == 8 then -- dead event 
		local theUnit = event.initiator
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
						trigger.action.outText("SittingDuck: in group <" .. gName .. "> unit <" .. uName .. "> was destroyed on the ground, group blocked.", 30)
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
		trigger.action.outText("SittingDuck: group <" .. gName .. "> re-supplied, slots reopened.", 30)
	end
end

-- make sure stopGap is available
if stopGap and stopGap.start then 
	trigger.action.setUserFlag("SSB",100)
	world.addEventHandler(sittingDucks)
	trigger.action.outText("Sitting Ducks v" .. sittingDucks.version .. " running, SSB enabled", 30)
else 
	trigger.action.outText("Sitting Ducks requires stopGap to run", 30)
end


