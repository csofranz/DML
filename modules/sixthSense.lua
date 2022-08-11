sixthSense = {}
sixthSense.version = "1.0.0"
-- sniff out dead events and log them 
function sixthSense:onEvent(event)
	if event.id == 8 then -- S_EVENT_DEAD
		if event.initiator then 
			local theObject = event.initiator
			trigger.action.outText("DEAD event: " .. theObject:getName(), 30)
			
		else
			trigger.action.outText("DEAD event, no initiator", 30)
		end
	end
end

-- add event handler
world.addEventHandler(sixthSense)
trigger.action.outText("sixthSense v" .. sixthSense.version .. " loaded.", 30)
