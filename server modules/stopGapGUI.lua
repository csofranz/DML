stopGapGUI = {}
stopGapGUI.version = "1.0.0"
stopGapGUI.fVal = -300 -- 5 minutes max block
--
-- Server Plug-In for StopGap mission script, only required for server
-- Put into (main DCS save folder)/Scripts/Hooks/ and restart DCS
--
function stopGapGUI.onPlayerTryChangeSlot(playerID, side, slotID)
	if not slotID then return end 
	if slotID == "" then return end 
	if not DCS.isServer() then return end 
	if not DCS.isMultiplayer() then return end 

	local gName = DCS.getUnitProperty(slotID, DCS.UNIT_GROUPNAME)
	if not gName then return end 
	local sgName = "SG" .. gName 
	-- tell all clients to remove this group's statics if they are deployed
	net.dostring_in("server", " trigger.action.setUserFlag(\""..sgName.."\", " .. stopGapGUI.fVal .. "); ")
	net.send_chat("+++SG: readying group <" .. sgName .. "> for slotting")
end   
 
DCS.setUserCallbacks(stopGapGUI)