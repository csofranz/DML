smr = {}
smr.restartFlag = "simpleMissionRestart"
--
-- smr: simple mission restart (server module)
-- in your mission, set flag "simpleMissionRestart" to a value < 0 (zero) 
-- and the server restarts the mission within one second
--
-- Created 20220902 by cfrag  - version 1.0.0
--

-- misc procs
function smr.getServerFlagValue(theFlag)
	-- execute getUserFlag() in server space 
	local val, errNo  = net.dostring_in('server', " return trigger.misc.getUserFlag(\""..theFlag.."\"); ")
	if (not val) and errNo then
		net.log("smr - can't access flag, dostring_in returned <".. errNo .. ">")
		return 0
	else
		-- dostring_in returns a string, so convert to number 
		return tonumber(val)
	end
end

function smr.restartMission()
	local mn = DCS.getMissionFilename( )
	net.log("+++smr: restarting mission: ".. mn)
	net.send_chat("+++smr: restarting mission: ".. mn, true)
	local success = net.load_mission(mn)
	if not success then 
		net.log("+++smr: FAILED to load <" .. mn .. ">")
		net.send_chat("+++smr: FAILED to load <" .. mn .. ">", true)
	end
end

-- main update loop, checked once per secon
local lTime = DCS.getModelTime()
function smr.onSimulationFrame()
	if lTime + 1 < DCS.getModelTime() then
		-- set next time
		lTime = DCS.getModelTime()
		-- check to see if the restartFlag is set 
		if not DCS.isServer() then return end 
		if smr.getServerFlagValue(smr.restartFlag) > 0 then 
			smr.restartMission()
		end
	end 
end

-- install smr in hooks
DCS.setUserCallbacks(smr)
