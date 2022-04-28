skel = {}
function skel:onEvent(event) -- event handler
end

function skel.update()
	-- schedule next update invocation
	timer.scheduleFunction(skel.update, {}, timer.getTime() + 1)
	-- your own stuff and checks here
	trigger.action.outText("DCS, this is Lua. Hello. Lua.", 30)
end

world.addEventHandler(skel) -- connect event hander
skel.update() -- start update cycle
