airtank = {}
airtank.version = "1.0.0"
-- Module to extinguish fires controlled by the 'inferno' module.
-- For 'airtank' fire extinguisher aircraft modules. 
airtank.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
}
airtank.tanks = {} -- player data by GROUP name, will break with multi-unit groups 
-- tank attributes 
-- pumpArmed -- for hovering fills. 
-- armed -- for triggering drops below trigger alt-
-- dropping -- if drop has triggered 
-- carrying -- how mach retardant / fluid am I carrying?
-- capacity -- how much can I carry 

-- uName
-- pName 
-- theUnit 
-- gID 
-- lastDeparture -- timestamp to avoid double notifications 
-- lastLanding -- timestamp to avoid double dip 

airtank.zones = {} -- come here to refill your tanks 

airtank.roots = {} -- roots for player by group name 
airtank.mainMenu = nil -- handles attachTo:

airtank.types = {"Mi-8MT", "UH-1H", "Mi-24P", "OH58D", "CH-47Fbl1"} -- which helicopters/planes can firefight and get menu. can be amended with config and zone 
airtank.capacities = {
["UH-1H"] = 1200,
["Mi-8MT"] = 4000,
["Mi-24P"] = 2400,
["CH-47Fbl1"] = 9000,
["OH58D"] = 500,
} -- how much each helo can carry. default is 500kg, can be amended with zone 
airtank.pumpSpeed = 100 -- liters/kg per second, for all helos same 
airtank.dropSpeed = 1000 -- liters per second, for all helos same 
airtank.releaseAlt = 100 -- m = 90 ft
airtank.pumpAlt = 10 -- m = 30 feet  
--
-- airtank zones - land inside to refill. can have limited capa 
--
function airtank.addZone(theZone)
	airtank.zones[theZone.name] = theZone
end

function airtank.readZone(theZone)
	theZone.capacity = theZone:getNumberFromZoneProperty("airtank", 99999999) -- should be enough 
	theZone.amount = theZone:getNumberFromZoneProperty("amount", theZone.capacity)
end

function airtank.refillWithZone(theZone, data)
	local theUnit = data.theUnit
	local wanted = data.capacity - data.carrying
	if theZone.amount > wanted then 
		theZone.amount = theZone.amount - wanted 
		data.carrying = data.capacity 
		trigger.action.outTextForGroup(data.gID, "Roger, " .. data.uName .. ", topped up tanks, you now carry " .. data.carrying .. "kg of flame retardant.", 30)
		trigger.action.outSoundForGroup(data.gID, airtank.actionSound)
		trigger.action.setUnitInternalCargo(data.uName, data.carrying + 10)
		return true
	end
	trigger.action.outTextForGroup(data.gID, "Negative, " .. data.uName .. ", out of flame retardant.", 30)
	return false 
end

--
-- event handling 
--
function airtank:onEvent(theEvent)
	-- catch birth events of helos 
	if not theEvent then return end 
	local theUnit = theEvent.initiator 
	if not theUnit then return end 
	if not theUnit.getPlayerName then return end 
	local pName = theUnit:getPlayerName()
	if not pName then return end 
	-- we have a player unit 
	if not dcsCommon.unitIsOfLegalType(theUnit, airtank.types) then 
		if airtank.verbose then 
			trigger.action.outText("aTnk: unit <" .. theUnit:getName() .. ">, type <" .. theUnit:getTypeName() .. "> not an airtank.", 30)
		end 
		return 
	end 	

	local uName = theUnit:getName()
	local uType = theUnit:getTypeName()
	local theGroup = theUnit:getGroup()
	local gName = theGroup:getName() 
	
	if theEvent.id == 15 then -- birth
		-- make sure this aircraft is legit 
		airtank.installMenusForUnit(theUnit)
		local theData = airtank.newData(theUnit)
		theData.pName = pName
		airtank.tanks[gName] = theData 
		if airtank.verbose then 
			trigger.action.outText("+++aTnk: new player airtank <" .. uName .. "> type <" .. uType .. "> for <" .. pName .. ">", 30)
		end 
		return 
	end
	
	if theEvent.id == 4 or -- land
	   theEvent.id == 55 -- runway touch 
	then 
		-- see if landed inside a refill zone and 
		-- automatically top off if pumpArmed
		local data = airtank.tanks[gName]
		if data and data.lastLanding then return end -- no double dip 
		if data and data.pumpArmed then
			data.lastLanding = timer.getTime() 
			data.lastDeparture = nil 
			local p = theUnit:getPoint() 
			for idx, theZone in pairs (airtank.zones) do 
				if theZone:pointInZone(p) then 
					if airtank.refillWithZone(theZone, data) then 
						data.armed = false 
						data.pumpArmed = false
						return 
					end -- if refill received
				end -- if in zone
			end -- for zones 
		elseif data then 
			data.lastLanding = timer.getTime() 
			data.lastDeparture = nil 
			local p = theUnit:getPoint() 
			for idx, theZone in pairs (airtank.zones) do 
				if theZone:pointInZone(p) then 
					trigger.action.outTextForGroup(data.gID, "Welcome to " .. theZone.name .. ", " .. pName .. ", firefighting services are available.", 30)
					return 
				end 
			end
		end
		return 
	end
	
	if theEvent.id == 3 or  -- takeoff
	   theEvent.id == 54 -- runway takeoff
	then 
		local data = airtank.tanks[gName]
		local now = timer.getTime() 
		if data then
			data.lastLanding = nil 
			-- suppress double take-off notifications for 20 seconds
			if data.lastDeparture then -- and data.lastDeparture + 60 < now then 
				return 
			end 
			data.lastDeparture = now 
			if data.carrying < data.capacity * 0.5 then 
				trigger.action.outTextForGroup(data.gID, "Good luck, " .. pName .. ", remember to top off your tanks before going in.", 30)
			else
				trigger.action.outTextForGroup(data.gID, "Good luck and godspeed, " .. pName .. "!", 30)
			end
			trigger.action.outSoundForGroup(data.gID, airtank.actionSound)
		end
		return
	end
end

function airtank.newData(theUnit)
	local theType = theUnit:getTypeName()
	local data = {}
	local capa = airtank.capacities[theType]
	if not capa then capa = 500 end -- default capa.
	data.capacity = capa 
	data.carrying = 0 
	data.pumpArmed = false 
	data.armed = false 
	data.dropping = false 
	data.uName = theUnit:getName()
	data.pName = theUnit:getPlayerName()
	data.theUnit = theUnit 
	local theGroup = theUnit:getGroup()
	data.gID = theGroup:getID()
	trigger.action.setUnitInternalCargo(data.uName, data.carrying + 10)
	return data 
end
--
-- comms 
--
function airtank.installMenusForUnit(theUnit) -- assumes all unfit types are weeded out
	-- if already exists, remove old
	if not theUnit then return end 
	if not Unit.isExist(theUnit) then return end 
	local theGroup = theUnit:getGroup() 
	local uName = theUnit:getName()
	local uType = theUnit:getTypeName()
	local pName = theUnit:getPlayerName()
	local gName = theGroup:getName()
	local gID = theGroup:getID()
	local pRoot = airtank.roots[gName]
	if pRoot then 
		missionCommands.removeItemForGroup(gID, pRoot)
	end
	-- now add the airtank menu 
	pRoot = missionCommands.addSubMenuForGroup(gID, airtank.menuName, airtank.mainMenu) 
	airtank.roots[gName] = pRoot -- save for later 
	local args = {gName, uName, gID, uType, pName}
	-- menus: 
	-- status: loaded, capa, armed etc 
	-- ready pump -- turn off drop system and start sucking, if landing in zone will fully charge, else suck in water when hovering over water when low enough (below 10m)
	-- arm release -- get ready to drop. auto-release when alt is below 30m 
	local m1 = missionCommands.addCommandForGroup(gID , "Tank Status" , pRoot, airtank.redirectStatus, args)
	local mx2 = missionCommands.addCommandForGroup(gID , "MANUAL RELEASE" , pRoot, airtank.redirectManDrop, args)
	local m2 = missionCommands.addCommandForGroup(gID , "*Arm*AUTODROP*trigger" , pRoot, airtank.redirectArmDrop, args)
	local m3 = missionCommands.addCommandForGroup(gID , "Activate/Ready intake" , pRoot, airtank.redirectArmPump, args)
	local m4 = missionCommands.addCommandForGroup(gID , "Secure ship" , pRoot, airtank.redirectSecure, args)
end

function airtank.redirectStatus(args)
	timer.scheduleFunction(airtank.doStatus, args, timer.getTime() + 0.1)
end

function airtank.doStatus(args)
	local gName = args[1]
	local uName = args[2]
	local gID = args[3]
	local uType = args[4]
	local pName = args[5]
	local ralm = airtank.releaseAlt
	local ralf = math.floor(ralm * 3.28084)
	local data = airtank.tanks[gName]
	local remains = data.capacity - data.carrying
	local msg = "\nAirtank <" .. uName .. "> (" .. uType .. "), commanded by " .. pName .. "\n  capacity: " .. data.capacity .. "kg, carrying " .. data.carrying .. "kg (free " .. remains .. "kg)"
	-- add info to nearest refuel zone?
	if data.armed then msg = msg .. "\n\n  *** RELEASE TRIGGER ARMED (" .. ralm .. "m/" .. ralf .. "ft AGL)***" end
	ralm = airtank.pumpAlt
	ralf = math.floor(ralm * 3.28084)	
	if data.pumpArmed then msg = msg .. "\n\n  --- intake pumps ready (below " .. ralm .. "m/" .. ralf .. "ft AGL)" end 
	msg = msg .. "\n"
	trigger.action.outTextForGroup(gID, msg, 30)
end


function airtank.redirectManDrop(args)
	timer.scheduleFunction(airtank.doManDrop, args, timer.getTime() + 0.1)
end

function airtank.doManDrop(args)
	local gName = args[1]
	local uName = args[2]
	local theUnit = Unit.getByName(uName)
	local gID = args[3]
	local uType = args[4]
	local pName = args[5]
	local data = airtank.tanks[gName]
	local remains = data.capacity - data.carrying
	local alt = dcsCommon.getUnitAGL(theUnit)
	local ralm = math.floor(alt)
	local ralf = math.floor(ralm * 3.28084)
	local msg = ""
	local agl = dcsCommon.getUnitAGL(theUnit)
	if not theUnit:inAir() then 
		trigger.action.outTextForGroup(data.gID, "Please get into the air before releasing flame retardant.", 30)
		trigger.action.outSoundForGroup(data.gID, airtank.actionSound)
		return 
	end
	if data.carrying < 1 then 
		msg = "\nRetard tanks empty. Your " .. uType .. " can carry up to " .. data.capacity .. "kg.\n"
		data.armed = false 
		data.dropping = false 
		data.pumpArmed = false
	elseif data.carrying < 100 then 
		msg = "\nTanks empty (" .. data.carrying .. "kg left), safeties are engaged.\n"
		data.armed = false 
		data.dropping = false 
		data.pumpArmed = false 
	else 
		msg = "\n  *** Opened drop valve at " .. ralm .. "m/" .. ralf .. "ft RALT.\n"
		data.armed = false 
		data.pumpArmed = false
		data.dropResults = {}
		data.dropping = true 
		trigger.action.outTextForGroup(gID, msg, 30)
		trigger.action.outSoundForGroup(gID, airtank.actionSound)
		airtank.dropFor(data)
		return 
	end 
	trigger.action.outTextForGroup(gID, msg, 30)
	trigger.action.outSoundForGroup(gID, airtank.actionSound)
end


function airtank.redirectArmDrop(args)
	timer.scheduleFunction(airtank.doArmDrop, args, timer.getTime() + 0.1)
end

function airtank.doArmDrop(args)
	local gName = args[1]
	local uName = args[2]
	local theUnit = Unit.getByName(uName)
	local gID = args[3]
	local uType = args[4]
	local pName = args[5]
	local data = airtank.tanks[gName]
	local remains = data.capacity - data.carrying
	local ralm = airtank.releaseAlt
	local ralf = math.floor(ralm * 3.28084)
	local msg = ""
	local agl = dcsCommon.getUnitAGL(theUnit)
	if data.carrying < 1 then 
		msg = "\nRetard tanks empty. Your " .. uType .. " can carry up to " .. data.capacity .. "kg.\n"
		data.armed = false 
		data.dropping = false 
		data.pumpArmed = false
	elseif agl < airtank.releaseAlt then 
		msg = "Get above " .. ralm .. "m/" .. ralf .. "ft ALG (radar) to arm trigger."
	elseif data.carrying < 100 then 
		msg = "\nTank empty (" .. data.carrying .. "kg left), safeties are engaged.\n"
		data.armed = false 
		data.dropping = false 
		data.pumpArmed = false 
	else 
		msg = "\n  *** Release valve primed to trigger below " .. ralm .. "m/" .. ralf .. "ft RALT.\n\nRelease starts automatically at or below trigger altitude.\n"
		data.armed = true 
		data.dropping = false 
		data.pumpArmed = false
	end 
	trigger.action.outTextForGroup(gID, msg, 30)
	trigger.action.outSoundForGroup(gID, airtank.actionSound)
end

function airtank.redirectArmPump(args)
	timer.scheduleFunction(airtank.doArmPump, args, timer.getTime() + 0.1)
end

function airtank.doArmPump(args)
	local gName = args[1]
	local uName = args[2]
	local theUnit = Unit.getByName(uName)
	local gID = args[3]
	local uType = args[4]
	local pName = args[5]
	local data = airtank.tanks[gName]
	local remains = data.capacity - data.carrying
	local ralm = airtank.pumpAlt
	local ralf = math.floor(ralm * 3.28084)
	local msg = ""
	-- if we are on the ground, check if we are inside a 
	-- zone that can refill us 
	if not theUnit:inAir() then
		local p = theUnit:getPoint() 
		for idx, theZone in pairs (airtank.zones) do 
			if theZone:pointInZone(p) then 
				if airtank.refillWithZone(theZone, data) then 
					data.armed = false 
					data.pumpArmed = false
					data.dropping = false 
					return 
				end
			end 
		end
	end

	msg = "\n  *** Intake valves ready, descend to  " .. ralm .. "m/" .. ralf .. "ft RALT over water, or land at a firefighting supply base.\n"
	data.armed = false 
	data.dropping = false 
	data.pumpArmed = true

	trigger.action.outTextForGroup(gID, msg, 30)
	trigger.action.outSoundForGroup(gID, airtank.actionSound)
end

function airtank.redirectSecure(args)
	timer.scheduleFunction(airtank.doSecure, args, timer.getTime() + 0.1)
end

function airtank.doSecure(args)
	local gName = args[1]
	local gID = args[3]
	local data = airtank.tanks[gName]
	local msg = ""
	msg = "\n  All valves secure and stored for cruise operation\n"
	data.armed = false 
	data.dropping = false 
	data.pumpArmed = false
	trigger.action.outTextForGroup(gID, msg, 30)
	trigger.action.outSoundForGroup(gID, airtank.actionSound)
end

--
-- update 
--
function airtank.dropFor(theData) -- drop onto ground/fire
	local theUnit = theData.theUnit
	local qty = airtank.dropSpeed
	if qty > theData.carrying then qty = math.floor(theData.carrying) end 
	-- calculate position where it will hit 
	local alt = dcsCommon.getUnitAGL(theUnit)
	if alt < 0 then alt = 0 end 
	local vel = theUnit:getVelocity() -- vec 3, we only need x and z to project the point where the water will impact (we ignore vel.z)
	-- calculation: agl=height, no downward vel, will accelerate at G= 10 m/ss
	-- i.e. t = sqrt(2*agl/10)
	local agl = dcsCommon.getUnitAGL(theUnit)
	local t = math.sqrt(0.2*agl) 
	local p = theUnit:getPoint()
	local impact = {x = p.x + t * vel.x, y = 0, z = p.z + t * vel.z}
	
	-- tell inferno about it, get some feedback 
	if inferno.waterDropped then 
		local diag = inferno.waterDropped(impact, qty, theData)
		if diag then table.insert(theData.dropResults, diag) end 
	else 
		trigger.action.outText("WARNING: airtank can't find 'inferno' module.", 30)
		return 
	end
	
	-- update what we have left in tank 
	theData.carrying = theData.carrying - qty 
	if theData.carrying < 0 then theData.carrying = 0 end 
	local ralm = math.floor(agl)
	local ralf = math.floor(ralm * 3.28084)
	
	local msg = "Dropping " .. qty .. "kg at RALT " .. ralm .. "m/" .. ralf .. "ft, " .. theData.carrying .. " kg remaining"
	local snd = airtank.releaseSound
	
	-- close vent if empty 
	if theData.carrying < 100 then 
		-- close hatch
		theData.dropping = false 
		theData.armed = false 
		msg = msg .. ", CLOSING VENTS\n\n"
		snd = airtank.actionSound
		-- add all drop diagnoses 
		if #theData.dropResults < 1 then 
			msg = msg .. "No discernible results.\n"
		else 
			msg = msg .. "Good delivey:\n"
			for idx, res in pairs(theData.dropResults) do 
				msg = msg .. " - " .. res .. "\n"
			end 
		end
	end
	-- set internal cargo 
	trigger.action.setUnitInternalCargo(theData.uName, theData.carrying + 10)
	-- say how much we dropped and (if so) what we are over 
	trigger.action.outTextForGroup(theData.gID, msg, 30, true)
	trigger.action.outSoundForGroup(theData.gID, snd)
end

function airtank.updateDataFor(theData)
	local theUnit = theData.theUnit 
	-- see if we are dropping 
	if theData.dropping then 
		-- valve is open 
		airtank.dropFor(theData) -- drop contents of tank, sets weight
	elseif theData.armed then 
		-- see if we are below 10*trigger 
		local alt = dcsCommon.getUnitAGL(theUnit)
		if alt < 10 * airtank.releaseAlt then 
			-- see if we trigger 
			if alt <= airtank.releaseAlt then 
				-- !! trigger flow 
				theData.dropResults = {}
				theData.dropping = true 
--				trigger.action.outText("allocated dropResults", 30)
				theData.armed = false 
				airtank.dropFor(theData) -- sets weight 
				trigger.action.outSoundForGroup(theData.gID, airtank.releaseSound)
			else 
				-- flash current alt and say when we will trigger 
				local calm = math.floor(alt)
				local calf = math.floor(calm * 3.28084)
				local ralm = airtank.releaseAlt
				local ralf = math.floor(ralm * 3.28084)
				trigger.action.outTextForGroup(theData.gID, "Current RALT " .. calm .. "m/" .. calf .. "ft, will release at " .. ralm .. "m/" .. ralf .. "ft", 30, true) -- erase all
				trigger.action.outSoundForGroup(theData.gID, airtank.blipSound)
			end
		end
	-- see if the intake valve is open
	elseif theData.pumpArmed then 
		p = theUnit:getPoint()
		local sType = land.getSurfaceType({x=p.x, y=p.z})
		if sType ~= 2 and sType ~= 3 then -- not over water
			return 
		end 
		local alt = dcsCommon.getUnitAGL(theUnit)
		local calm = math.floor(alt)
		local calf = math.floor(calm * 3.28084)
		if alt < 5 * airtank.pumpAlt then 
			local msg = "RALT " .. calm .. "m/" .. calf .. "ft, "  
			if alt <= airtank.pumpAlt then -- in pump range
				theData.carrying = theData.carrying + airtank.pumpSpeed
				if theData.carrying > theData.capacity then theData.carrying = theData.capacity end
				trigger.action.setUnitInternalCargo(theData.uName, theData.carrying + 10)
			end
			msg = msg .. theData.carrying .. "/" .. theData.capacity .. "kg"
			if theData.carrying >= theData.capacity - 50 then 
				theData.pumpArmed = false 
				msg = msg .. " PUMP DISENGAGED"
			end
			trigger.action.outTextForGroup(theData.gID, msg, 30, true)
			trigger.action.outSoundForGroup(theData.gID, airtank.pumpSound)
		end 
	end	
end

function airtank.update() -- update all firefighters
	timer.scheduleFunction(airtank.update, {}, timer.getTime() + airtank.ups) -- next time 
	local filtered = {} -- filter existing only 
	for gName, data in pairs(airtank.tanks) do 
		local theUnit = data.theUnit 
		if Unit.isExist(theUnit) then 
			if theUnit:inAir() then 
				airtank.updateDataFor(data)
			end 
			filtered[gName] = data 
		end
	end
	airtank.tanks = filtered
end 

--
-- start and config 
-- 
function airtank.readConfigZone()
	airtank.name = "airtankConfig" -- make compatible with dml zones 
	local theZone = cfxZones.getZoneByName("airtankConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("airtankConfig") 
	end 
	
	airtank.verbose = theZone.verbose
	airtank.ups = theZone:getNumberFromZoneProperty("ups", 1)
	airtank.menuName = theZone:getStringFromZoneProperty("menuName", "Firefighting")

	airtank.actionSound = theZone:getStringFromZoneProperty("actionSound", "none")
	airtank.blipSound = theZone:getStringFromZoneProperty("blipSound", airtank.actionSound)
	airtank.releaseSound = theZone:getStringFromZoneProperty("releaseSound", airtank.actionSound)
	airtank.pumpSound = theZone:getStringFromZoneProperty("pumpSound", airtank.actionSound)
	
	if theZone:hasProperty("attachTo:") then 
		local attachTo = theZone:getStringFromZoneProperty("attachTo:", "<none>")
		if radioMenu then -- requires optional radio menu to have loaded 
			local mainMenu = radioMenu.mainMenus[attachTo]
			if mainMenu then 
				airtank.mainMenu = mainMenu 
			else 
				trigger.action.outText("+++airtank: cannot find super menu <" .. attachTo .. ">", 30)
			end
		else 
			trigger.action.outText("+++airtank: REQUIRES radioMenu to run before inferno. 'AttachTo:' ignored.", 30)
		end 
	end 

	-- add own troop carriers 
	if theZone:hasProperty("airtanks") then 
		local tc = theZone:getStringFromZoneProperty("airtanks", "UH-1D")
		tc = dcsCommon.splitString(tc, ",")
		airtank.types = dcsCommon.trimArray(tc)
		if airtank.verbose then 
			trigger.action.outText("+++aTnk: redefined air tanks to types:", 30)
			for idx, aType in pairs(airtank.types) do 
				trigger.action.outText(aType, 30)
			end
		end
	end
	
	-- add capacities and types from airTankSpecs zone  
	local capaZone = cfxZones.getZoneByName("airTankSpecs") 
	if capaZone then 
		if airtank.verbose then 
			trigger.action.outText("aTnk: found and processing 'airTankSpecs' zone data.", 30)
		end 
		-- read all into my types registry, replacing whatever is there
		local rawCapa = cfxZones.getAllZoneProperties(capaZone)
		local newCapas = airtank.processCapas(rawCapa)
		-- now types to existing types if not already there 
		for aType, aCapa in pairs(newCapas) do 
			airtank.capacities[aType] = aCapa
			dcsCommon.addToTableIfNew(airtank.types, aType)
			if civAir.verbose then 
				trigger.action.outText("+++aTnk: processed aircraft <" .. aType .. "> for capacity <" .. aCapa .. ">", 30)
			end
		end
	end  
end

function airtank.processCapas(rawIn)
	local newCapas = {}
	-- now iterate the input table, and generate new types and 
	-- liveries from it 
	for theType, capa in pairs (rawIn) do 
		if airtank.verbose then 
			trigger.action.outText("+++aTnk: processing type <" .. theType .. ">:<" .. capa .. ">", 30)
		end
		local pcapa = tonumber(capa)
		if not pcapa then capa = 0 end 
		newCapas[theType] = pcapa
	end
	
	return newCapas
end


function airtank.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx airtank requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx airtank", airtank.requiredLibs) then
		return false 
	end
	
	-- read config 
	airtank.readConfigZone()

	-- process airtank Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("airtank")
	for k, aZone in pairs(attrZones) do 
		airtank.readZone(aZone) -- process attributes
		airtank.addZone(aZone) -- add to list
	end
	
	-- connect event handler 
	world.addEventHandler(airtank)
	
	-- start update 
	timer.scheduleFunction(airtank.update, {}, timer.getTime() + 1/airtank.ups)

	-- say Hi!
	trigger.action.outText("cf/x airtank v" .. airtank.version .. " started.", 30)
	return true 
end

if not airtank.start() then 
	trigger.action.outText("airtank failed to start up")
	airtank = nil 
end 

