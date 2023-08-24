noGapGUI = {}
noGapGUI.version = "1.0.0"
noGapGUI.fVal = 1 -- tell noGap to remove static 
noGapGUI.verbose = false 
--
-- Server Plug-In for noGap mission script, only required for server
-- Put into (main DCS save folder)/Scripts/Hooks/ and restart DCS
--
function noGapGUI.onPlayerTryChangeSlot(playerID, side, slotID)
	if not slotID then return end 
	if slotID == "" then return end 
	if not DCS.isServer() then return end 
	if not DCS.isMultiplayer() then return end 

	local uName = DCS.getUnitProperty(slotID, DCS.UNIT_NAME)
	if not uName then return end 
	local ngName = "NG" .. uName 
	-- tell all clients to remove this unit's static if they are deployed
	net.dostring_in("server", " trigger.action.setUserFlag(\""..ngName.."\", " .. noGapGUI.fVal .. "); ")
	if noGapGUI.verbose then 
		net.send_chat("+++NG: readying unit <" .. ngName .. "> for slotting")
	else 
		net.log("+++noGapGUI: readying unit <" .. ngName .. "> for slotting")
	end 
end   
 
function noGapGUI.onSimulationStart() 
	net.dostring_in("server", " trigger.action.setUserFlag(\"noGapGUI\", 0); ")
	if not DCS.isServer() then return end 
	if not DCS.isMultiplayer() then return end 
	net.dostring_in("server", " trigger.action.setUserFlag(\"noGapGUI\", 200); ") -- tells client that MP is active
end

DCS.setUserCallbacks(noGapGUI)
net.log("noGapGUI v." .. noGapGUI.version .. " started.")