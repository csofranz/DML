shallows = {}
-- script to remove dead naval hulls that failed to sink
-- once dead, smoke is put over the hull for 5 minutes 
-- and if still in game later, the hull is removed 

shallows.version = "1.0.0"
shallows.removeAfter = 5 -- minutes after kill event 
shallows.verbose = false 
shallows.uuid = 1

-- uuid
function shallows.getUuid() 
	shallows.uuid = shallows.uuid + 1
	return shallows.uuid
end 

-- remove hull
function shallows.removeHull(args)
	if shallows.verbose then 
		trigger.action.outText("enter remove hull for <" .. args.name .. ">", 30)
	end

	-- remove smoke and whatever's left of ship 
	trigger.action.effectSmokeStop(args.sName)
	Object.destroy(args.theUnit)
	if shallows.verbose then 
		trigger.action.outText("Shallows: Removed <" .. args.name .. ">", 30)
	end
end

-- watch the world turn and ships get killed
function shallows:onEvent(event)
	if event.id ~= 28 then return end -- only kill events
	if not event.target then return end 
	-- must be a ship
	local theUnit = event.target
	if not theUnit.getGroup or not theUnit:getGroup() then return end 
	local theGroup = theUnit:getGroup()
	local cat = theGroup:getCategory()
	if cat ~= 3 then return end  -- not a ship 
	
	if shallows.verbose then 
		trigger.action.outText("Shallows: marking <" .. theUnit:getName() .. "> for deep-sixing", 30)
	end
	
	-- mark it with smoke and fire 
	local pos = theUnit:getPoint()
	local sName = theUnit:getName() .. shallows.getUuid()
	trigger.action.effectSmokeBig(pos, 2, 0.5, sName)
	
	-- set timer to re-visit later 
	local args = {}
	args.name = theUnit:getName()
	args.sName = sName 
	args.theUnit = theUnit 
	timer.scheduleFunction(shallows.removeHull, args, timer.getTime() + shallows.removeAfter * 60)
end

-- start
world.addEventHandler(shallows)
trigger.action.outText("shallows " .. shallows.version .. " started", 30)