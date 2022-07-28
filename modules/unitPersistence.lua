unitPersistence = {}
unitPersistence.version = '1.0.0'
unitPersistence.verbose = false 
unitPersistence.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"persistence",
	"cfxMX",
}
--[[--
	Version History 
	1.0.0 - initial version
	
	REQUIRES PERSISTENCE AND MX

	Persist ME-placed ground units
	
--]]--
unitPersistence.groundTroops = {} -- local buffered copy that we 
								  -- maintain from save to save
unitPersistence.statics = {} -- locally unpacked and buffered static objects 

--
-- Save -- Callback 
--
function unitPersistence.saveData()
	local theData = {}
	if unitPersistence.verbose then 
		trigger.action.outText("+++unitPersistence: enter saveData", 30)
	end
	
	-- theData contains last save 
	-- we save GROUND units placed by ME on. we access a copy of MX data 
	-- for ground troups, iterate through all groups, and create 
	-- a replacement group here and now that is used to replace the one 
	-- that is there when it was spawned
	for groupName, groupData in pairs(unitPersistence.groundTroops) do
		-- we update this record live and save it to file
		if not groupData.isDead then 
			local gotALiveOne = false 
			local allUnits = groupData.units
			for idx, theUnitData in pairs(allUnits) do
				if not theUnitData.isDead then 
					local uName = theUnitData.name 
					local gUnit = Unit.getByName(uName)
					if gUnit and gUnit:isExist() then 
						-- got a live one!
						gotALiveOne = true 
						-- update x and y and heading 
						theUnitData.heading = dcsCommon.getUnitHeading(gUnit)
						pos = gUnit:getPoint()
						theUnitData.x = pos.x
						theUnitData.y = pos.z -- (!!)
						-- ground units do not use alt
					else 
						theUnitData.isDead = true
					end -- is alive and exists?
				end	-- unit not dead 
			end -- iterate units in group 
			groupData.isDead = not gotALiveOne
		end -- if group is not dead 
		if unitPersistence.verbose then 
			trigger.action.outText("unitPersistence: save - processed group <" .. groupName .. ">.", 30)
		end
	end
	
	-- process all static objects placed with ME 
	for oName, oData in pairs(unitPersistence.statics) do 
		if not oData.isDead then 
			-- fetch the object and see if it's still alive
			local theObject = StaticObject.getByName(oName)
			if theObject and theObject:isExist() then
				oData.heading = dcsCommon.getUnitHeading(theObject)
				pos = theObject:getPoint()
				oData.x = pos.x
				oData.y = pos.z -- (!!)
				oData.isDead = theObject:getLife() < 1
--				trigger.action.outText("deadcheck: " .. oName .. " has health=" .. theObject:getLife(), 30)
				oData.dead = oData.isDead
			else 
				oData.isDead = true
				oData.dead = true 
--				trigger.action.outText("deadcheck: " .. oName .. " certified dead", 30)
			end
		end
		if unitPersistence.verbose then 
			local note = "(ok)"
			if oData.isDead then note = "(dead)" end 
			trigger.action.outText("unitPersistence: save - processed group <" .. oName .. ">. " .. note, 30)
		end
	end
	
	theData.version = unitPersistence.version
	theData.ground = unitPersistence.groundTroops
	theData.statics = unitPersistence.statics
	return theData
end

--
-- Load Mission Data
--
function unitPersistence.loadMission()
	local theData = persistence.getSavedDataForModule("unitPersistence")
	if not theData then 
		if unitPersistence.verbose then 
			trigger.action.outText("unitPersistence: no save date received, skipping.", 30)
		end
		return
	end
	
	if theData.version ~= unitPersistence.version then 
		trigger.action.outText("\nWARNING!\nUnit data was saved with a different (older) version!\nProceed with caution, fresh start is recommended.\n", 30)
	end
	
	-- we just loaded an updated version of unitPersistence.groundTroops	
	-- now iterate all groups, update their positions and 
	-- delete all dead groups or units
	-- because they currently should exist is the game 
	-- note: if they don't exist in-game that is because mission was 
	-- edited after last save 
	local mismatchWarning = false 
	if theData.ground then 
		for groupName, groupData in pairs(theData.ground) do
			local theGroup = Group.getByName(groupName)
			if not theGroup then 
				mismatchWarning = true 
			elseif groupData.isDead then
				theGroup:destroy()
			else 
				local newGroup = dcsCommon.clone(groupData)
				local newUnits = {}
				for idx, theUnitData in pairs(groupData.units) do 
					-- filter all dead groups 
					if theUnitData.isDead then 
						-- skip it
						
					else 
						-- add it to new group
						table.insert(newUnits, theUnitData)
					end
				end
				-- replace old unit setup with new 
				newGroup.units = newUnits

				local cty = groupData.cty 
				local cat = groupData.cat 
				
				-- destroy the old group 
				--theGroup:destroy() -- will be replaced 
				
				-- spawn new one 
				theGroup = coalition.addGroup(cty, cat, newGroup)
				if not theGroup then 
					trigger.action.outText("+++ failed to add modified group <" .. groupName .. ">")
				end
				if unitPersistence.verbose then 
					trigger.action.outText("+++unitPersistence: updated group <" .. groupName .. "> of cat <" .. cat .. "> for cty <" .. cty .. ">", 30)
				end 
			end 
		end
	else 
		if unitPersistence.verbose then 
			trigger.action.outText("+++unitPersistence: no ground unit data.", 30)
		end
	end
	
	-- and now the same for static objects 
	if theData.statics then 
		for name, staticData in pairs(theData.statics) do
			local theStatic = StaticObject.getByName(name)
			if not theStatic then 
				mismatchWarning = true 
			else
				local newStatic = dcsCommon.clone(staticData)
				local cty = staticData.cty 
				local cat = staticData.cat
				-- spawn new one, replacing same.named old, dead if required 
				gStatic =  coalition.addStaticObject(cty, newStatic)
				if not gStatic then 
					trigger.action.outText("+++ failed to add modified static <" .. name .. ">")
				end
				if unitPersistence.verbose then 
					local note = ""
					if newStatic.dead then note = " (dead)" end 
					trigger.action.outText("+++unitPersistence: updated static <" .. name .. "> for cty <" .. cty .. ">" .. note, 30)
				end 
			end
		end
	end
	
	if mismatchWarning then 
		trigger.action.outText("\n+++WARNING: \nSaved data does not match mission. You should re-start from scratch\n", 30)
	end
	-- set mission according to data received from last save 
	if unitPersistence.verbose then 
		trigger.action.outText("unitPersistence: units set from save data.", 30)
	end
end

--
-- Start
--
function unitPersistence.start()
	-- lib check 
	if (not dcsCommon) or (not dcsCommon.libCheck) then 
		trigger.action.outText("unit persistence requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("unit persistence", unitPersistence.requiredLibs) then
		return false 
	end

	-- see if we even need to persist 
	if not persistence.active then 
		return true -- WARNING: true, but not really
	end	
	
	-- sign up for save callback 
	callbacks = {}
	callbacks.persistData = unitPersistence.saveData
	persistence.registerModule("unitPersistence", callbacks)
	
	-- create a local copy of the entire groundForces data that 
	-- we maintain internally. It's fixed, and we work on our 
	-- own copy for speed
	for gname, data in pairs(cfxMX.allGroundByName) do
		local gd = dcsCommon.clone(data) -- copy the record
		gd.isDead = false -- init new field to alive
		-- coalition and country 
		gd.cat = cfxMX.catText2ID("vehicle")
		local gGroup = Group.getByName(gname)
		if not gGroup then 
			trigger.action.outText("+++warning: group <" .. gname .. "> does not exist in-game!?", 30)
		else
			local firstUnit = gGroup:getUnit(1)
			gd.cty = firstUnit:getCountry()
			unitPersistence.groundTroops[gname] = gd
		end
	end
	
	-- make local copies of all static MX objects 
	-- that we also maintain internally, and convert them to game 
	-- spawnable objects 
	for name, mxData in pairs(cfxMX.allStaticByName) do
		-- statics in MX are built like groups, so we have to strip 
		-- the outer shell and extract all 'units' which are actually 
		-- objects. And there is usually only one 
		for idx, staticData in pairs(mxData.units) do 
			local theStatic = dcsCommon.clone(staticData)
			theStatic.isDead = false 
			theStatic.groupId = mxData.groupId
			theStatic.cat = cfxMX.catText2ID("static")
			local gameOb = StaticObject.getByName(theStatic.name)
			if not gameOb then 
				trigger.action.outText("+++warning: static object <" .. theStatic.name .. "> does not exist in-game!?", 30)
			else 
				theStatic.cty = gameOb:getCountry()
				unitPersistence.statics[theStatic.name] = theStatic
			end
		end
	end
	
	-- when we run, persistence has run and may have data ready for us
	if persistence.hasData then
		unitPersistence.loadMission()
	end
	
	return true 
end

if not unitPersistence.start() then 
	if unitPersistence.verbose then 
		trigger.action.outText("+++ unit persistence not available", 30)
	end
	unitPersistence = nil 
end