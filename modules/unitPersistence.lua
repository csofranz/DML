unitPersistence = {}
unitPersistence.version = '2.0.0'
unitPersistence.verbose = false 
unitPersistence.updateTime = 60 -- seconds. Once every minute check statics
unitPersistence.requiredLibs = {
	"dcsCommon",
	"cfxZones",  
	"persistence",
	"cfxMX",
}
--[[--
	Version History 
	1.0.0 - initial version
	1.0.1 - handles late activation 
	      - handles linked static objects 
		  - does no longer mess with heliports 
		  - update statics once a minute, not second 
	1.0.2 - fixes coalition bug for static objects 
	1.1.0 - added air and sea units - for filtering destroyed units
	1.1.1 - fixed static link (again)
	      - fixed air spawn (fixed wing)
	2.0.0 - dmlZones, OOP
			cleanup 
	
	REQUIRES PERSISTENCE AND MX

	Persist ME-placed ground units
	
--]]--
unitPersistence.groundTroops = {} -- local buffered copy that we 
								  -- maintain from save to save
unitPersistence.fixedWing = {}
unitPersistence.rotorWing = {}
unitPersistence.ships = {}

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
						if gUnit:isActive() then 
							theUnitData.isDead = gUnit:getLife() < 1
							if not theUnitData.isDead then 
								-- got a live one!
								gotALiveOne = true 
								-- update x, y and heading 
								theUnitData.heading = dcsCommon.getUnitHeading(gUnit)
								pos = gUnit:getPoint()
								theUnitData.x = pos.x
								theUnitData.y = pos.z -- (!!)
							end 
						else 
							gotALiveOne = true -- not yet activated 
						end
					else 
						theUnitData.isDead = true
					end -- is alive and exists?
				end	-- unit maybe not dead 
			end -- iterate units in group 
			groupData.isDead = not gotALiveOne
		end -- if group is not dead 
		if unitPersistence.verbose then 
			trigger.action.outText("unitPersistence: save - processed group <" .. groupName .. ">.", 30)
		end
	end
	
	-- aircraft 
	for groupName, groupData in pairs(unitPersistence.fixedWing) do
		-- we update this record live and save it to file
		if not groupData.isDead then 
			local gotALiveOne = false 
			local allUnits = groupData.units
			for idx, theUnitData in pairs(allUnits) do
				if not theUnitData.isDead then 
					local uName = theUnitData.name 
					local gUnit = Unit.getByName(uName)
					if gUnit and gUnit:isExist() then 
						-- update x and y and heading if active and alive
						if gUnit:isActive() then -- only overwrite if active
							theUnitData.isDead = gUnit:getLife() < 1
							if not theUnitData.isDead then 
								gotALiveOne = true -- this group is still alive
								theUnitData.heading = dcsCommon.getUnitHeading(gUnit)
								pos = gUnit:getPoint()
								theUnitData.x = pos.x
								theUnitData.y = pos.z -- (!!)
								theUnitData.alt = pos.y 
								theUnitData.alt_type = "BARO"
								theUnitData.speed = dcsCommon.vMag(gUnit:getVelocity())
								-- we now could get fancy and do some proccing of the 
								-- waypoints and make the one it's nearest to its
								-- current waypoint, curtailing all others, but that 
								-- may easily mess with waypoint actions, so we don't
							end
						else 
							gotALiveOne = true -- has not yet been activated, live
						end
					else 
						theUnitData.isDead = true
						-- trigger.action.outText("+++unitPersistence - unit <" .. uName .. "> of group <" .. groupName .. "> is dead or non-existant", 30)
					end -- is alive and exists?
				end	-- unit maybe not dead 
			end -- iterate units in group 
			groupData.isDead = not gotALiveOne
		end -- if group is not dead 
		if unitPersistence.verbose then 
			trigger.action.outText("unitPersistence: save - processed air group <" .. groupName .. ">.", 30)
		end
	end

	-- helos 
	for groupName, groupData in pairs(unitPersistence.rotorWing) do
		-- we update this record live and save it to file
		if not groupData.isDead then 
			local gotALiveOne = false 
			local allUnits = groupData.units
			for idx, theUnitData in pairs(allUnits) do
				if not theUnitData.isDead then 
					local uName = theUnitData.name 
					local gUnit = Unit.getByName(uName)
					if gUnit and gUnit:isExist() then 
						-- update x and y and heading if active and alive
						if gUnit:isActive() then -- only overwrite if active
							theUnitData.isDead = gUnit:getLife() < 1
							if not theUnitData.isDead then 
								gotALiveOne = true -- this group is still alive
								theUnitData.heading = dcsCommon.getUnitHeading(gUnit)
								pos = gUnit:getPoint()
								theUnitData.x = pos.x
								theUnitData.y = pos.z -- (!!)
								theUnitData.alt = pos.y 
								theUnitData.alt_type = "BARO"
								theUnitData.speed = dcsCommon.vMag(gUnit:getVelocity())
								-- we now could get fancy and do some proccing of the 
								-- waypoints and make the one it's nearest to its
								-- current waypoint, curtailing all others, but that 
								-- may easily mess with waypoint actions, so we don't
							end
						else 
							gotALiveOne = true -- has not yet been activated, live
						end
					else 
						theUnitData.isDead = true
						trigger.action.outText("+++unitPersistence - unit <" .. uName .. "> of group <" .. groupName .. "> is dead or non-existant", 30)
					end -- is alive and exists?
				end	-- unit maybe not dead 
			end -- iterate units in group 
			groupData.isDead = not gotALiveOne
		end -- if group is not dead 
		if unitPersistence.verbose then 
			trigger.action.outText("unitPersistence: save - processed helo group <" .. groupName .. ">.", 30)
		end
	end

	-- ships 
	for groupName, groupData in pairs(unitPersistence.ships) do
		-- we update this record live and save it to file
		if not groupData.isDead then 
			local gotALiveOne = false 
			local allUnits = groupData.units
			for idx, theUnitData in pairs(allUnits) do
				if not theUnitData.isDead then 
					local uName = theUnitData.name 
					local gUnit = Unit.getByName(uName)
					if gUnit and gUnit:isExist() then 
						-- update x and y and heading if active and alive
						if gUnit:isActive() then -- only overwrite if active
							theUnitData.isDead = gUnit:getLife() < 1
							if not theUnitData.isDead then 
								gotALiveOne = true -- this group is still alive
								theUnitData.heading = dcsCommon.getUnitHeading(gUnit)
								pos = gUnit:getPoint()
								theUnitData.x = pos.x
								theUnitData.y = pos.z -- (!!)
								-- we only filter dead ships and don't mess with others
								-- during load, so we are doing this solely for possible
								-- later expansions
							end
						else 
							gotALiveOne = true -- has not yet been activated, live
						end
					else 
						theUnitData.isDead = true
						if unitPersistence.verbose then 
							trigger.action.outText("+++unitPersistence - unit <" .. uName .. "> of group <" .. groupName .. "> is dead or non-existant", 30)
						end 
					end -- is alive and exists?
				end	-- unit maybe not dead 
			end -- iterate units in group 
			groupData.isDead = not gotALiveOne
		end -- if group is not dead 
		if unitPersistence.verbose then 
			trigger.action.outText("unitPersistence: save - processed ship group <" .. groupName .. ">.", 30)
		end
	end
	
	-- process all static objects placed with ME 
	for oName, oData in pairs(unitPersistence.statics) do 
		if not oData.isDead or oData.lateActivation then 
			-- fetch the object and see if it's still alive
			local theObject = StaticObject.getByName(oName)
			if theObject and theObject:isExist() then
				oData.heading = dcsCommon.getUnitHeading(theObject)
				pos = theObject:getPoint()
				oData.x = pos.x
				oData.y = pos.z -- (!!)
				oData.isDead = theObject:getLife() < 1
				oData.dead = oData.isDead
			else 
				oData.isDead = true
				oData.dead = true 
			end
		end
		if unitPersistence.verbose then 
			local note = "(ok)"
			if oData.isDead then note = "(dead)" end 
			if oData.lateActivation then note = "(late active)" end 
			trigger.action.outText("unitPersistence: save - processed group <" .. oName .. ">. " .. note, 30)
		end
	end
	
	theData.version = unitPersistence.version
	theData.ground = unitPersistence.groundTroops
	theData.fixedWing = unitPersistence.fixedWing
	theData.rotorWing = unitPersistence.rotorWing
	theData.ships = unitPersistence.ships
	
	theData.statics = unitPersistence.statics
	return theData
end

--
-- Load Mission Data
--
function unitPersistence.delayedSpawn(args)
	local cat = args.cat
	local cty = args.cty
	local newGroup = args.newGroup
	local theGroup = coalition.addGroup(cty, cat, newGroup)
end

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
								
				-- spawn new one, replaces old one  
				theGroup = coalition.addGroup(cty, cat, newGroup)
				if not theGroup then 
					trigger.action.outText("+++ failed to add modified group <" .. groupName .. ">", 30)
				end 
			end 
		end
		unitPersistence.groundTroops = theData.ground 
	else 
		if unitPersistence.verbose then 
			trigger.action.outText("+++unitPersistence: no ground unit data.", 30)
		end
	end
	
	if theData.fixedWing then 
		for groupName, groupData in pairs(theData.fixedWing) do
			--trigger.action.outText("+++ start loading group <" .. groupName .. ">", 30)
			local theGroup = Group.getByName(groupName)
			if not theGroup then 
				mismatchWarning = true 
			elseif groupData.isDead then
				theGroup:destroy()
			elseif groupData.isPlayer then 
				-- skip it
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
				-- replace old unit setup with (delayed) new 
				newGroup.units = newUnits
				local cty = groupData.cty 
				local cat = groupData.cat 
				
				-- spawn new one, replaces old one 
				theGroup:destroy()
				local args = {}
				args.cty = cty 
				args.cat = cat 
				args.newGroup = newGroup
				-- since DCS can't replace a group directly (none will appear), we introduce a brief interval for things to settle 
				timer.scheduleFunction(unitPersistence.delayedSpawn, args, timer.getTime()+0.5)
 
			end 
		end
		unitPersistence.fixedWing = theData.fixedWing
	else 
		if unitPersistence.verbose then 
			trigger.action.outText("+++unitPersistence: no aircraft (fixed wing) unit data.", 30)
		end
	end

	if theData.rotorWing then 
		for groupName, groupData in pairs(theData.rotorWing) do
			local theGroup = Group.getByName(groupName)
			if not theGroup then 
				mismatchWarning = true 
			elseif groupData.isDead then
				theGroup:destroy()
			elseif groupData.isPlayer then 
				-- skip it
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

				-- spawn new one, replaces old one  
				theGroup = coalition.addGroup(cty, cat, newGroup)
				if not theGroup then 
					trigger.action.outText("+++ failed to add modified group <" .. groupName .. ">", 30)
				end 
			end 
		end
		unitPersistence.rotorWing = theData.rotorWing
	else 
		if unitPersistence.verbose then 
			trigger.action.outText("+++unitPersistence: no rotor wing unit data.", 30)
		end
	end	

	if theData.ships then 
		for groupName, groupData in pairs(theData.ships) do
			local theGroup = Group.getByName(groupName)
			if not theGroup then 
				mismatchWarning = true 
			elseif groupData.isDead then
				-- when entire group is destroyed, we will also 
				-- destroy group. Else all survive
				-- we currently don't dick around with carrieres unless they are dead
				theGroup:destroy()
			else 
				-- do nothing 
			end 
		end
		unitPersistence.ships = theData.ships 
	else 
		if unitPersistence.verbose then 
			trigger.action.outText("+++unitPersistence: no rotor wing unit data.", 30)
		end
	end	
	
	-- and now the same for static objects 
	if theData.statics then 
		for name, staticData in pairs(theData.statics) do
			--local theStatic = StaticObject.getByName(name)
			if staticData.lateActivation then 
				-- this one will not be in the game now, skip
				if unitPersistence.verbose then
					trigger.action.outText("+++unitPersistence: static <" .. name .. "> is late activate, no update", 30)
				end
			elseif staticData.category == "Heliports" then 
				-- FARPS are static objects that HATE to be 
				-- messed with, so we don't 
				if unitPersistence.verbose then
					trigger.action.outText("+++unitPersistence: static <" .. name .. "> is Heliport, no update", 30)
				end
			else
				local newStatic = dcsCommon.clone(staticData)
				-- add link info if it exists
				newStatic.linkUnit = cfxMX.linkByName[staticData.groupName]
				if newStatic.linkUnit and unitPersistence.verbose then 
					trigger.action.outText("+++unitPersistence: linked static <" .. name .. "> to unit <" .. newStatic.linkUnit .. ">", 30)
				end
				local cty = staticData.cty 
				local cat = staticData.cat
				-- spawn new one, replacing same.named old, dead if required 
				gStatic =  coalition.addStaticObject(cty, newStatic)
				if not gStatic then 
					trigger.action.outText("+++ failed to add modified static <" .. name .. ">", 30)
				end
				if unitPersistence.verbose then 
					local note = ""
					if newStatic.dead then note = " (dead)" end 
					trigger.action.outText("+++unitPersistence: updated static <" .. name .. "> for cty <" .. cty .. ">" .. note, 30)
				end 
			end
		end
		unitPersistence.statics = theData.statics 
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
-- Update
--
function unitPersistence.update()
	-- we check every minute
	timer.scheduleFunction(unitPersistence.update, {}, timer.getTime() + unitPersistence.updateTime)
	-- do a quick scan for all late activated static objects and if they 
	-- are suddently visible, remove their late activate state 
	--for groupName, groupdata in pairs(unitPersistence.groundTroops) do 
		-- currently not needed
	--end
	
	for objName, objData in pairs(unitPersistence.statics) do 
		if objData.lateActivation then 
			local theStatic = StaticObject.getByName(objData.name)
			if theStatic then 
				objData.lateActivation = false 
				if unitPersistence.verbose then 
					trigger.action.outText("+++unitPersistence: <" ..  objData.name .. "> has activated", 30)
				end	
			end
		end
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
	unitPersistence.groundTroops = {}
	for gname, data in pairs(cfxMX.allGroundByName) do
		local gd = dcsCommon.clone(data) -- copy the record
		gd.isDead = false -- init new field to alive
		-- coalition and country 
		gd.cat = cfxMX.catText2ID("vehicle")
		local gGroup = Group.getByName(gname)
		if not gGroup then 
			trigger.action.outText("+++warning: ground group <" .. gname .. "> does not exist in-game!?", 30)
		else
			gd.cty = cfxMX.countryByName[gname]
			unitPersistence.groundTroops[gname] = gd
		end
	end
	
	-- now add all aircraft
	unitPersistence.fixedWing = {}	
	for gname, data in pairs(cfxMX.allFixedByName) do
		local gd = dcsCommon.clone(data) -- copy the record
		gd.isDead = false -- init new field to alive
		gd.isPlayer = (cfxMX.playerGroupByName[gname] ~= nil) 
		-- coalition and country 
		gd.cat = cfxMX.catText2ID("plane") -- 0 
		gd.cty = cfxMX.countryByName[gname]
		local gGroup = Group.getByName(gname)
		if gd.isPlayer then 
			-- skip 
		elseif not gGroup then 
			trigger.action.outText("+++warning: fixed-wing group <" .. gname .. "> does not exist in-game!?", 30)
		else
			unitPersistence.fixedWing[gname] = gd
		end
	end
	
	-- and helicopters 
	unitPersistence.rotorWing = {}	
	for gname, data in pairs(cfxMX.allHeloByName) do
		local gd = dcsCommon.clone(data) -- copy the record
		gd.isDead = false -- init new field to alive
		gd.isPlayer = (cfxMX.playerGroupByName[gname] ~= nil) 
		-- coalition and country 
		gd.cat = cfxMX.catText2ID("helicopter") -- 1 
		gd.cty = cfxMX.countryByName[gname]
		local gGroup = Group.getByName(gname)
		if gd.isPlayer then 
			-- skip
		elseif not gGroup then 
			trigger.action.outText("+++warning: helo group <" .. gname .. "> does not exist in-game!?", 30)
		else
			unitPersistence.rotorWing[gname] = gd
		end
	end
	
	-- finally ships 
	-- we only do ships to remove them when they are dead because
	-- messing with ships can give problems: aircraft carriers.
	unitPersistence.ships = {}	
	for gname, data in pairs(cfxMX.allSeaByName) do
		local gd = dcsCommon.clone(data) -- copy the record
		gd.isDead = false -- init new field to alive
		-- coalition and country 
		gd.cat = cfxMX.catText2ID("ship") -- 3 
		gd.cty = cfxMX.countryByName[gname] 
		local gGroup = Group.getByName(gname)
		if gd.isPlayer then 
			-- skip
		elseif not gGroup then 
			trigger.action.outText("+++warning: ship group <" .. gname .. "> does not exist in-game!?", 30)
		else
			unitPersistence.ships[gname] = gd
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
			theStatic.groupName = name -- save top-level name
			theStatic.cat = cfxMX.catText2ID("static")
			theStatic.cty = cfxMX.countryByName[name]
			--trigger.action.outText("Processed MX static group <" .. name .. ">, object <" .. name .. "> with cty <" .. theStatic.cty .. ">",30)
			local gameOb = StaticObject.getByName(theStatic.name)
			if not gameOb then 
				if unitPersistence.verbose then 
					trigger.action.outText("+++unitPersistence: static object <" .. theStatic.name .. "> has late activation", 30)
				end 
				theStatic.lateActivation = true 
			end
			unitPersistence.statics[theStatic.name] = theStatic -- HERE WE CHANGE FROM GROUP NAME TO STATIC NAME!!! 
		end
	end
		
	-- when we run, persistence has run and may have data ready for us
	if persistence.hasData then
		unitPersistence.loadMission()
	end
	
	-- start update 
	unitPersistence.update()
	
	return true 
end

if not unitPersistence.start() then 
	if unitPersistence.verbose then 
		trigger.action.outText("+++ unit persistence not available", 30)
	end
	unitPersistence = nil 
end
--[[--
	- waypoint analysis for aircraft so 
	  - whan they have take off as Inital WP and they are moving 
	    then we change the first WP to 'turning point'
	  - waypoint analysis to match waypoint to position. very difficult if waypoints describe a circle.
	- group analysis for carriers to be able to process groups that do 
	  not contain carriers 

--]]--
