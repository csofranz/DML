aswGUI = {}
aswGUI.version = "1.0.2"
aswGUI.verbose = false 
aswGUI.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"asw", -- needs asw module 
	"aswZones", -- also needs the asw zones 
}

--[[--
	Version History
	1.0.0 - initial version 
	1.0.1 - env.info clean-up, verbosity clean-up 
	1.0.2 - late start capability
	
--]]--

aswGUI.ups = 1 -- = once every second
aswGUI.aswCraft = {}

--[[--
::::::::::::::::: ASSUMES SINGLE-UNIT GROUPS ::::::::::::::::::
--]]--


function aswGUI.resetConf(asc)
	if asc.rootMenu then 
		missionCommands.removeItemForGroup(asc.groupID, asc.rootMenu)
	end 
	asc.rootMenu = missionCommands.addSubMenuForGroup(asc.groupID, "ASW")
	asc.buoyNum = 0 
	asc.torpedoNum = 0
	asc.coolDown = 0 -- used when waiting, currently not used 
end

-- we use lazy init whenever player enters 
function aswGUI.initUnit(unitName) -- now this unit exists 
	local theUnit = Unit.getByName(unitName)
	if not theUnit then 
		trigger.action.outText("+++aswGUI: <" .. unitName .. "> not a unit, aborting initUnit", 30)
		return nil
	end 
	
	local theGroup = theUnit:getGroup()
	local asc = {} -- set up player craft config block
	asc.groupName = theGroup:getName() -- groupData.name
	asc.name = unitName
	asc.groupID = theGroup:getID() -- groupData.groupId
	aswGUI.resetConf(asc)
	return asc
end


function aswGUI.processWeightFor(conf)
	-- make total weight and handle all 
	-- cargo for this unit 
	
	-- hand off to DML cargo manager if implemented 
	if cargosuper then 
		trigger.action.outText("CargoSuper handling regquired, using none", 30)
		return
	end

	local totalWeight = conf.buoyNum * aswGUI.buoyWeight
	totalWeight = totalWeight + conf.torpedoNum * aswGUI.torpedoWeight

	-- set cargo weight 
	trigger.action.setUnitInternalCargo(conf.name, totalWeight)
	local theUnit = Unit.getByName(conf.name)
	trigger.action.outTextForGroup(conf.groupID, "Total asw weight: " .. totalWeight .. "kg (" .. math.floor(totalWeight * 2.20462) .. "lbs)", 30)
	return totalWeight 
end

--
-- build unit menu 
--
function aswGUI.getBuoyCapa(conf) -- returns capa per slot 
	-- warning: assumes two "slots" maximum 
	if conf.torpedoNum > aswGUI.torpedoesPerSlot then return 0 end -- both slots are filled with torpedoes 
	if conf.torpedoNum > 0 then -- one slot is taken up by torpedoes 
		return aswGUI.buoysPerSlot - conf.buoyNum 
	end
	if conf.buoyNum >= aswGUI.buoysPerSlot then 
		return 2 * aswGUI.buoysPerSlot - conf.buoyNum
	end 
	return aswGUI.buoysPerSlot - conf.buoyNum
end

function aswGUI.getTorpedoCapa(conf)
	if conf.buoyNum > aswGUI.buoysPerSlot then return 0 end -- both slots are filled with buoys 
	if conf.buoyNum > 0 then -- one slot is taken up by torpedoes 
		return aswGUI.torpedoesPerSlot - conf.torpedoNum 
	end
	if conf.torpedoNum >= aswGUI.torpedoesPerSlot then 
		return 2 * aswGUI.torpedoesPerSlot - conf.torpedoNum
	end 
	return aswGUI.torpedoesPerSlot - conf.torpedoNum
end

function aswGUI.setGroundMenu(conf, theUnit)
	-- build menu for load stores 
	local loc = theUnit:getPoint()
	local closestAswZone = aswZones.getClosestASWZoneTo(loc)
	local inZone = cfxZones.pointInZone(loc, closestAswZone)
	local bStore = 0 -- available buoys
	local tStore = 0 -- available torpedoes
	-- ... but only if we are in an asw zone 
	-- calculate how much is available 
	if inZone then 
		bStore = closestAswZone.buoyNum
		if bStore < 0 then bStore = aswGUI.buoysPerSlot end
		tStore = closestAswZone.torpedoNum
		if tStore < 0 then tStore = aswGUI.torpedoesPerSlot end
	end

	if bStore > 0 then 
		local bCapa = aswGUI.getBuoyCapa(conf)
		if bCapa > 0 then 
			missionCommands.addCommandForGroup(conf.groupID, "Load <" .. bCapa .."> ASW Buoys", conf.rootMenu, aswGUI.xHandleLoadBuoys, conf)
		else 
			missionCommands.addCommandForGroup(conf.groupID, "(No free Buoy stores)", conf.rootMenu, aswGUI.xHandleGeneric, conf)
		end
	else
		missionCommands.addCommandForGroup(conf.groupID, "(Can't load ASW Buoys, no supplies in range)", conf.rootMenu, aswGUI.xHandleGeneric, conf)
	end
	
	if conf.buoyNum > 0 then 
		local toUnload = conf.buoyNum
		if toUnload > aswGUI.buoysPerSlot then toUnload = aswGUI.buoysPerSlot end 
		missionCommands.addCommandForGroup(conf.groupID, "Unload <" .. toUnload .. "> ASW Buoys (" .. conf.buoyNum .. " on board)", conf.rootMenu, aswGUI.xHandleUnloadBuoys, conf)
	end 
	
	-- torpedo proccing 
	
	if tStore > 0 then 
		local tCapa = aswGUI.getTorpedoCapa(conf)
		if tCapa > 0 then 
			tCapa = 1 -- one at a time 
			missionCommands.addCommandForGroup(conf.groupID, "Load <" .. tCapa .."> ASW Torpedoes", conf.rootMenu, aswGUI.xHandleLoadTorpedoes, conf)
		else 
			missionCommands.addCommandForGroup(conf.groupID, "All stores filled to capacity", conf.rootMenu, aswGUI.xHandleGeneric, conf)
		end
	else
		missionCommands.addCommandForGroup(conf.groupID, "(Can't load ASW Torpedoes, no supplies in range)", conf.rootMenu, aswGUI.xHandleGeneric, conf)
	end
	
	if conf.torpedoNum > 0 then 
		local toUnload = conf.torpedoNum
		if toUnload > aswGUI.torpedoesPerSlot then toUnload = aswGUI.buoysPerSlot end 
		missionCommands.addCommandForGroup(conf.groupID, "Unload <" .. toUnload .. "> ASW Torpedoes (" .. conf.torpedoNum .. " on board)", conf.rootMenu, aswGUI.xHandleUnloadTorpedoes, conf)
	end 
	missionCommands.addCommandForGroup(conf.groupID, "[Stores: <" .. conf.buoyNum .. "> Buoys | <" .. conf.torpedoNum .. "> Torpedoes]", conf.rootMenu, aswGUI.xHandleGeneric, conf)
end

function aswGUI.setAirMenu(conf, theUnit)
	-- build menu for load stores 
	local bStore = conf.buoyNum -- available buoys
	local tStore = conf.torpedoNum -- available torpedoes

	if bStore < 1 and tStore < 1 then 
		missionCommands.addCommandForGroup(conf.groupID, "No ASW munitions on board", conf.rootMenu, aswGUI.xHandleGeneric, conf)
		return 
	end 
	
	if bStore > 0 then 
		missionCommands.addCommandForGroup(conf.groupID, "BUOY - Drop an ASW Buoy", conf.rootMenu, aswGUI.xHandleBuoyDropoff, conf)
	else 
		missionCommands.addCommandForGroup(conf.groupID, "No ASW Buoys on board", conf.rootMenu, aswGUI.xHandleGeneric, conf)
	end

	if tStore > 0 then 
		missionCommands.addCommandForGroup(conf.groupID, "TORP - Drop an ASW Torpedo", conf.rootMenu, aswGUI.xHandleTorpedoDropoff, conf)
	else 
		missionCommands.addCommandForGroup(conf.groupID, "No ASW Torpedoes on board", conf.rootMenu, aswGUI.xHandleGeneric, conf)
	end

	missionCommands.addCommandForGroup(conf.groupID, "[Stores: <" .. conf.buoyNum .. "> Buoys | <" .. conf.torpedoNum .. "> Torpedoes]", conf.rootMenu, aswGUI.xHandleGeneric, conf)
end

function aswGUI.setMenuForUnit(theUnit)
	if not theUnit then return end 
	if not Unit.isExist(theUnit) then return end 
	local uName = theUnit:getName()
	
	-- if we get here, the unit exists. fetch unit config 
	local conf = aswGUI.aswCraft[uName]
	-- delete old, and create new root menu
	missionCommands.removeItemForGroup(conf.groupID, conf.rootMenu)
	conf.rootMenu = missionCommands.addSubMenuForGroup(conf.groupID, "ASW")
	
	-- if we are in the air, we add menus to drop buoys or torpedoes
	if theUnit:inAir() then 
		aswGUI.setAirMenu(conf, theUnit)
	else 
		aswGUI.setGroundMenu(conf, theUnit)
	end
end

--
-- comms callback handling 
--
--
-- LOADING / UNLOADING
--
function aswGUI.xHandleGeneric(args)
	timer.scheduleFunction(aswGUI.handleGeneric, args, timer.getTime() + 0.1)
end

function aswGUI.handleGeneric(args)
	if not args then args = "*EMPTY*" end 
	-- do nothing
end

function aswGUI.xHandleLoadBuoys(args)
	timer.scheduleFunction(aswGUI.handleLoadBuoys, args, timer.getTime() + 0.1)	
end


function aswGUI.handleLoadBuoys(args) 
	local conf = args 
	local theUnit = Unit.getByName(conf.name)
	if not theUnit then 
		trigger.action.outText("+++aswG: (load buoys) can't find unit <" .. conf.name .. ">", 30)
		return
	end
	local loc = theUnit:getPoint()
	local theZone = aswZones.getClosestASWZoneTo(loc)
	local inZone = cfxZones.pointInZone(loc, theZone)
	local bStore = 0 -- available buoys
	if inZone then 
		bStore = theZone.buoyNum
		if bStore < 0 then bStore = aswGUI.buoysPerSlot end
	else
		trigger.action.outTextForGroup(conf.groupID, "Nothing loaded. Return to ASW loading zone.", 30)
		aswGUI.setMenuForUnit(theUnit)
		return
	end
	
	if bStore < 1 then 
		trigger.action.outTextForGroup(conf.groupID, "ASW Buoy stock has run out. Sorry.", 30)
		aswGUI.setMenuForUnit(theUnit)
		return
	end 
	
	local capa = aswGUI.getBuoyCapa(conf)
	conf.buoyNum=conf.buoyNum + capa 
	
	if theZone.buoyNum >= 0 then 
		theZone.buoyNum = theZone.buoyNum - capa 
		if theZone.buoyNum < 0 then theZone.buoyNum = 0 end 
		-- proc new weight 
	end
	
	aswGUI.processWeightFor(conf)
	trigger.action.outTextForGroup(conf.groupID, "Loaded <" .. capa .. "> ASW Buoys.", 30)
	aswGUI.setMenuForUnit(theUnit)
end

function aswGUI.xHandleUnloadBuoys(args)
	timer.scheduleFunction(aswGUI.handleUnloadBuoys, args, timer.getTime() + 0.1)
end

function aswGUI.handleUnloadBuoys(args) 
	local conf = args 
	local theUnit = Unit.getByName(conf.name)
	if not theUnit then 
		trigger.action.outText("+++aswG: (unload buoys) can't find unit <" .. conf.name .. ">", 30)
		return
	end
	local loc = theUnit:getPoint()
	local theZone = aswZones.getClosestASWZoneTo(loc)
	local inZone = cfxZones.pointInZone(loc, theZone)

	local amount = conf.buoyNum
	while amount > aswGUI.buoysPerSlot do -- future proof, any # of slots
		amount = amount - aswGUI.buoysPerSlot 
	end 
	conf.buoyNum = conf.buoyNum - amount 
	
	if inZone then 
		if theZone.buoyNum >= 0 then theZone.buoyNum = theZone.buoyNum + amount end 
		trigger.action.outTextForGroup(conf.groupID, "Returned <" .. amount .. "> ASW Buoys to storage.", 30)
	else
		-- simply drop them, irrecoverable 
		trigger.action.outTextForGroup(conf.groupID, "Discarded <" .. amount .. "> ASW Buoys.", 30)
	end
	aswGUI.processWeightFor(conf)
	aswGUI.setMenuForUnit(theUnit)
end

function aswGUI.xHandleLoadTorpedoes(args)
	timer.scheduleFunction(aswGUI.handleLoadTorpedoes, args, timer.getTime() + 0.1)
end

function aswGUI.handleLoadTorpedoes(args)
	local conf = args 
	local theUnit = Unit.getByName(conf.name)
	if not theUnit then 
		trigger.action.outText("+++aswG: (load torps) can't find unit <" .. conf.name .. ">", 30)
		return
	end
	local loc = theUnit:getPoint()
	local theZone = aswZones.getClosestASWZoneTo(loc)
	local inZone = cfxZones.pointInZone(loc, theZone)
	local tStore = 0 -- available torpedoes
	if inZone then 
		tStore = theZone.torpedoNum
		if tStore < 0 then tStore = aswGUI.torpedoesPerSlot end
	else
		trigger.action.outTextForGroup(conf.groupID, "Nothing loaded. Return to ASW loading zone.", 30)
		aswGUI.setMenuForUnit(theUnit)
		return
	end
	
	if tStore < 1 then 
		trigger.action.outTextForGroup(conf.groupID, "ASW Torpedo stock has run out. Sorry.", 30)
		aswGUI.setMenuForUnit(theUnit)
		return
	end 
	
	local capa = aswGUI.getTorpedoCapa(conf)
	capa = 1 -- load one at a time 
	conf.torpedoNum=conf.torpedoNum + capa 
	if theZone.torpedoNum >= 0 then 
		theZone.torpedoNum = theZone.torpedoNum - capa 
		if theZone.torpedoNum < 0 then theZone.torpedoNum = 0 end 
	end
	
	aswGUI.processWeightFor(conf)
	
	trigger.action.outTextForGroup(conf.groupID, "Loaded <" .. capa .. "> asw Torpedoes.", 30)
	aswGUI.setMenuForUnit(theUnit)
end

function aswGUI.xHandleUnloadTorpedoes(args)
	timer.scheduleFunction(aswGUI.handleUnloadTorpedoes, args, timer.getTime() + 0.1)
end

function aswGUI.handleUnloadTorpedoes(args) 
	local conf = args 
	local theUnit = Unit.getByName(conf.name)
	if not theUnit then 
		trigger.action.outText("+++aswG: (unload torpedoes) can't find unit <" .. conf.name .. ">", 30)
		return
	end
	local loc = theUnit:getPoint()
	local theZone = aswZones.getClosestASWZoneTo(loc)
	local inZone = cfxZones.pointInZone(loc, theZone)

	local amount = conf.torpedoNum
	while amount > aswGUI.torpedoesPerSlot do -- future proof, any # of slots
		amount = amount - aswGUI.torpedoesPerSlot 
	end 
	conf.torpedoNum = conf.torpedoNum - amount 
	
	if inZone then 
		if theZone.torpedoNum >= 0 then theZone.torpedoNum = theZone.torpedoNum + amount end 
		trigger.action.outTextForGroup(conf.groupID, "Returned <" .. amount .. "> ASW Torpedoes to storage.", 30)
	else
		-- simply drop them, irrecoverable 
		trigger.action.outTextForGroup(conf.groupID, "Discarded <" .. amount .. "> ASW Torpedoes.", 30)
	end
	aswGUI.processWeightFor(conf)
	aswGUI.setMenuForUnit(theUnit)
end

--
-- LIVE DROP
--
function aswGUI.xHandleBuoyDropoff(args)
	timer.scheduleFunction(aswGUI.handleBuoyDropoff, args, timer.getTime() + 0.1)
end

function aswGUI.hasDropoffParams(conf) 
	-- to be added later, can be curtailed for units 
	return true 
end

function aswGUI.handleBuoyDropoff(args)
	local conf = args 
	local theUnit = Unit.getByName(conf.name)
	if not theUnit or not Unit.isExist(theUnit) then 
		trigger.action.outText("+++aswG: (drop buoy) unit <" .. conf.name .. "> does not exits", 30)
		return 
	end

	-- we could now make height and speed checks, but dont really do 
	if not aswGUI.hasDropoffParams(conf) then 
		trigger.action.outTextForGroup(conf.groupID, "You need to be below xxx knots and yyy ft AGL to drop ASW munitions", 30)
		return 
	end

	-- check that we really have some buoys left 
	if conf.buoyNum < 1 then 
		trigger.action.outText("+++aswG: no buoys for <" .. conf.name .. ">.", 30)
		return 
	end
	
	conf.buoyNum = conf.buoyNum - 1
	
	-- do the deed 
	asw.dropBuoyFrom(theUnit)
	trigger.action.outTextForGroup(conf.groupID, "Dropping ASW Buoy...", 30)
	
	-- wrap up 
	aswGUI.processWeightFor(conf)
	aswGUI.setMenuForUnit(theUnit)
end

function aswGUI.xHandleTorpedoDropoff(args)
	timer.scheduleFunction(aswGUI.handleTorpedoDropoff, args, timer.getTime() + 0.1)
end

function aswGUI.handleTorpedoDropoff(args)
local conf = args 
	local theUnit = Unit.getByName(conf.name)
	if not theUnit or not Unit.isExist(theUnit) then 
		trigger.action.outText("+++aswG: (drop torpedo) unit <" .. conf.name .. "> does not exits", 30)
		return 
	end

	-- we could now make height and speed checks, but dont really do 
	if not aswGUI.hasDropoffParams(conf) then 
		trigger.action.outTextForGroup(conf.groupID, "You need to be below xxx knots and yyy ft AGL to drop ASW munitions", 30)
		return 
	end

	-- check that we really have some buoys left 
	if conf.torpedoNum < 1 then 
		trigger.action.outText("+++aswG: no torpedoes for <" .. conf.name .. ">.", 30)
		return 
	end
	
	conf.torpedoNum = conf.torpedoNum - 1
	
	-- do the deed 
	asw.dropTorpedoFrom(theUnit)
	trigger.action.outTextForGroup(conf.groupID, "Dropping ASW Torpedo...", 30)
	
	-- wrap up 
	aswGUI.processWeightFor(conf)
	aswGUI.setMenuForUnit(theUnit)
end

-- 
-- Event handling 
--
function aswGUI:onEvent(theEvent)
	if not theEvent then 
		trigger.action.outText("+++aswGUI: nil theEvent", 30)
		return
	end
	local theID = theEvent.id
	if not theID then 
		trigger.action.outText("+++aswGUI: nil event.ID", 30)
		return
	end 
	local initiator = theEvent.initiator 
	if not initiator then 
		return 
	end -- not interested 
	local theUnit = initiator 
	if not Unit.isExist(theUnit) then 
		if aswGUI.verbose then  
			trigger.action.outText("+++aswGUI: non-unit event filtered.", 30)
		end
		return
	end
	local name = theUnit:getName() 
	if not name then 
		trigger.action.outText("+++aswGUI: unable to access unit name in onEvent, aborting", 30)
		return 
	end
	-- see if this is a player aircraft 
	if not theUnit.getPlayerName then 
		return 
	end -- not a player 
	if not theUnit:getPlayerName() then 
		return 
	end -- not a player 
	-- this is a player unit. Is it ASW carrier?
	local uType = theUnit:getTypeName()
	if not dcsCommon.isTroopCarrierType(uType, aswGUI.aswCarriers) then 
		if aswGUI.verbose then 
			trigger.action.outText("+++aswGUI: Player <" .. theUnit:getPlayerName() .. ">'s unit <" .. name .. "> of type <" .. uType .. "> is not ASW-capable. ASW Types are:", 30)
			for idx, aType in pairs(aswGUI.aswCarriers) do 
				trigger.action.outText(aType,30)
			end
		end
		return 
	end
		
	-- now let's access it if it was 
	-- used before 
	local conf = aswGUI.aswCraft[name]
	if not conf then 
		-- let's init it
		conf = aswGUI.initUnit(name)
		if not conf then 
			-- something went wrong, abort
			return 
		end
		aswGUI.aswCraft[name] = conf 
	end

	-- if we get here, theUnit is an asw craft 
	if theID == 4 or -- land 
	   theID == 3 then -- take off
		aswGUI.setMenuForUnit(theUnit)
		return
	end

	if theID == 20 or   -- player enter
	   theID == 15 then -- birth (server player enter)

		-- reset
		aswGUI.resetConf(conf)
		-- set menus 
		aswGUI.setMenuForUnit(theUnit)
	end 
	
	if theID == 21 then -- player leave 
		aswGUI.resetConf(conf)
	end
end

function aswGUI.processPlayerUnit(theUnit)
	local name = theUnit:getName() 
	local conf = aswGUI.aswCraft[name]
	if not conf then 
		-- let's init it
		conf = aswGUI.initUnit(name)
		aswGUI.aswCraft[name] = conf 
	else 
		aswGUI.resetConf(conf)
	end
	aswGUI.setMenuForUnit(theUnit)
	if aswGUI.verbose then 
		trigger.action.outText("aswG: set up player <" .. theUnit:getPlayerName() .. "> in <" .. name .. ">", 30)
	end
end

--
-- Config & start 
--
function aswGUI.readConfigZone()
	local theZone = cfxZones.getZoneByName("aswGUIConfig") 
	
	if not theZone then 
		if aswGUI.verbose then 
			trigger.action.outText("+++aswGUI: no config zone!", 30)
		end 
		theZone =  cfxZones.createSimpleZone("aswGUIConfig")
	end 
	aswGUI.verbose = theZone.verbose 
	
	-- read & set defaults
	if cfxZones.hasProperty(theZone, "aswCarriers") then 
		local carr = cfxZones.getStringFromZoneProperty(theZone, "aswCarriers", "")
		carr = dcsCommon.splitString(carr, ",")
		aswGUI.aswCarriers = dcsCommon.trimArray(carr)
	end
	
	aswGUI.buoysPerSlot = 10 
	aswGUI.torpedoesPerSlot = 2
	aswGUI.buoyWeight = 50 -- kg, 10x = 500, 20x = 1000
	aswGUI.buoyWeight = cfxZones.getNumberFromZoneProperty(theZone, "buoyWeight", aswGUI.buoyWeight)
	aswGUI.torpedoWeight = 700 -- kg 
	aswGUI.torpedoWeight = cfxZones.getNumberFromZoneProperty(theZone, "torpedoWeight", aswGUI.torpedoWeight)
	
	if aswGUI.verbose then 
		trigger.action.outText("+++aswGUI: read config", 30)
	end 
end

function aswGUI.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx aswGUI requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx aswGUI", aswGUI.requiredLibs) then
		return false 
	end
	
	-- read config 
	aswGUI.readConfigZone()
		
	-- subscribe to world events 
	world.addEventHandler(aswGUI)
	
	-- install menus in all existing players 
	dcsCommon.iteratePlayers(aswGUI.processPlayerUnit)
	
	-- say Hi
	trigger.action.outText("cfx ASW GUI v" .. aswGUI.version .. " started.", 30)
	return true 
end

--
-- start up aswZones
--
if not aswGUI.start() then 
	trigger.action.outText("cfx aswGUI aborted: missing libraries", 30)
	aswGUI = nil 
end