dmlMain = {}
--
-- DML-based mission skeleton with event loop
--
dmlMain.ups = 1 -- 1 update per second
-- minimal libraries required
dmlMain.requiredLibs = {
	"dcsCommon", -- minimal module for all
	"cfxZones", -- Zones, of course 
	"cfxPlayer", -- player events
}

dmlMain.config = {} -- for reading config zones

--
-- world event handling
--
function dmlMain.wPreProc(event)
	return true -- true means invoke worldEventHanlder()
	-- filter here and return false if the event is to be ignored
end

function dmlMain.worldEventHandler(event)
	-- now analyse table <event> and do stuff
	trigger.action.outText("DCS World Event " .. event.id .. " (" .. dcsCommon.event2text(event.id) .. ") received", 30)
end

--
-- player event handling
--
function dmlMain.playerEventHandler (evType, description, info, data)
	trigger.action.outText("DML Player Event " .. evType .. " received", 30)
end


--
-- update loop
--
function dmlMain.update() 
	-- schedule myself in 1/ups seconds
	timer.scheduleFunction(dmlMain.update, {}, timer.getTime() + 1/dmlMain.ups)
	
	-- perform any regular checks here in your main loop
	
end

--
-- read configuration from zone 'dmlMainConfig'
-- 

function dmlMain.readConfiguration()
	local theZone = cfxZones.getZoneByName("dmlMainConfig")
	if not theZone then return end 
	dmlMain.config = cfxZones.getAllZoneProperties(theZone)
	-- demo: dump all name/value pairs returned
	trigger.action.outText("DML config read from config zone:", 30)
	for name, value in pairs(dmlMain.config) do
		trigger.action.outText(name .. ":" .. value, 30)
	end
	trigger.action.outText("---- (end of list)", 30)

end

--
-- start
-- 
function dmlMain.start()
	-- ensure that all modules have loaded
	if not dcsCommon.libCheck("DML Main", 
		dmlMain.requiredLibs) then
		return false 
	end
	
	-- read any configuration values placed in a config zone on the map
	dmlMain.readConfiguration()
	
	-- subscribe to world events 
	dcsCommon.addEventHandler(dmlMain.worldEventHandler, 
							  dmlMain.wPreProc) -- no post nor rejected
	
	-- subscribe to player events 
	cfxPlayer.addMonitor(dmlMain.playerEventHandler)
	
	
	-- start the event loop. it will sustain itself 
	dmlMain.update()
	
	-- say hi!
	trigger.action.outText("DML Main mission running!", 30)
	return true 
end

-- start main
if not dmlMain.start() then 
	trigger.action.outText("Main mission failed to run", 30)
	dmlMain = nil
end
