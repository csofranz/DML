slotty = {}
slotty.version = "1.1.0"
--[[--
 Single-player slot blocking and slot blocking fallback
 for multiplayer when SSB is not installed on server. 
 Uses SSB's method of marking groups with flags 
 (c) 2024 by Christian Franz 

 Slotty can be disabled by setting the value of the flag named "noSlotty" to
 a value greater than zero 
 
Version history 
1.0.0 - Initial version 
1.1.0 - "noSlotty" global disable flag, anti-mirror SSB flag 

--]]--

function slotty:onEvent(event)
	if not event.initiator then return end 
	local theUnit = event.initiator 
	if not theUnit.getPlayerName then return end 
	local pName = theUnit:getPlayerName() 
	if not pName then return end 
	local uName = theUnit:getName()
	local theGroup = theUnit:getGroup() 
	local gName = theGroup:getName() 
	if event.id == 15 then -- birth 
		if trigger.misc.getUserFlag("noSlotty") > 0 then return end 
		local np = net.get_player_list() -- retruns a list of PID 
		local isSP = false 
		if not np or (#np < 1) then 
			isSP = true -- we are in single-player mode
		end 
		-- now see if that group name is currently blocked 
		local blockstate = false 
		if trigger.misc.getUserFlag(gName) > 0 then 
			trigger.action.outText("Group <" .. gName .. "> is currently blocked and can't be entered", 30)
			blockstate = true 
		end 
	
		if not blockstate then return end -- nothing left to do, all is fine 

		-- interface with SSBClient for compatibility 
		if cfxSSBClient and cfxSSBClient.occupiedUnits then 
			cfxSSBClient.occupiedUnits[uName] = nil 
		end 
	
		if isSP then 
			theUnit:destroy() -- SP kill, works only in Single-player
			return 
		end

		-- we would leave the rest to SSB, but if we get here, SSB is 
		-- not installed on host, so we proceed with invoking netAPI
		for idx,pid in pairs(np) do
			local netName = net.get_name(pid) 
			if netName == pName then
				timer.scheduleFunction(slotty.kick, pid, timer.getTime() + 0.1) 
				return 
			end
		end
	end 
end

function slotty.kick(pid)
	net.force_player_slot(pid, 0, '') -- '', thanks Dz!
end

function slotty.start()
	world.addEventHandler(slotty)
	trigger.action.outText("slotty v " .. slotty.version .. " running.", 30)
end

slotty.start()
