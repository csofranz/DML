missionRestart = {}
missionRestart.version = "1.0.1" 
missionRestart.restarting = false 
-- 
-- Restart this mission, irrespective of its name
-- Only works if run as multiplayer (sends commands to the server)
--
function missionRestart.restart()
	if missionRestart.restarting then return end 
	
	trigger.action.outText("Server: Mission restarting...", 30)
    local res = net.dostring_in("gui", "mn = DCS.getMissionFilename(); success = net.load_mission(mn); return success")
	
	missionRestart.restarting = true 
	
end

function missionRestart.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(missionRestart.update, {}, timer.getTime() + 30)
	
	if trigger.misc.getUserFlag("simpleMissionRestart") > 0 then 
		missionRestart.restart()
	end

end

missionRestart.update() 

