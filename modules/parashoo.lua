parashoo = {}
parashoo.version = "1.1.0" 
--[[--
   VERSION HISTORY 
   - 1.0.0 initial version 
   - 1.1.0 wait 3 minutes before destroying para 
           guy, else KIA reported when player still
		   in pilot
   
--]]--
parashoo.killDelay = 3 * 60 -- 3 minutes delay

function parashoo.removeGuy(args)
	local theGuy = args.theGuy
	if theGuy and theGuy:isExist() then  
		Unit.destroy(theGuy)
	end
end 


-- remove parachuted pilots after landing
function parashoo:onEvent(event)
	if event.id == 31 then -- landing_after_eject
		if event.initiator then 
			
			local args = {}
			args.theGuy = event.initiator 			
			timer.scheduleFunction(parashoo.removeGuy, args, timer.getTime() + parashoo.killDelay)
			--Unit.destroy(event.initiator) -- old direct remove
		end
	end
end

-- add event handler
world.addEventHandler(parashoo)
trigger.action.outText("parashoo v" .. parashoo.version .. " loaded.", 30)
