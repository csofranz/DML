fireCtrl = {}
fireCtrl.version = "1.2.0"
fireCtrl.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
	"airtank",
	"inferno",
}

fireCtrl.heroes = {} -- dict by pname: score 
fireCtrl.checkins = {} -- dict by pname: checked in if we persist
fireCtrl.roots = {} 
--[[--
	Version History 
	1.0.0 - Initial version (unreleased)
	1.1.0 - Added attachTo:
		  - Added checkIn 
		  - center name 
		  - newFire sound 
		  - bail out if not enough fires 
		  - re-liting with sparks
		  - sparks attribute 
		  - various sound attributes, default to action sound 
		  - notifications attribute 
		  - cleanup 
		  - UI attribute 
	1.2.0 - onStart attribute 
			ctrOn? attribute 
			ctrOff? attribute
--]]--

function fireCtrl.checkinPlayer(pName, gName, uName, uType)
	local theGroup = Group.getByName(gName)
	if not theGroup then return end 
	gID = theGroup:getID() 
	local msg = ""
	if not fireCtrl.checkins[pName] then 
		msg = "\nWelcome "
		if fireCtrl.heroes[pName] then 
			msg = msg .. "back "
		else 
			fireCtrl.heroes[pName] = 0 
		end 
		msg = msg .. "to " .. dcsCommon.getMapName() .. ", " .. pName .. ", your " .. uType .. " is ready.\nGood luck and godspeed!\n"
		fireCtrl.checkins[pName] = timer.getTime()
	else 
		msg = "\n" .. pName .. ", your " .. uType .. " is ready.\n"
	end
	if fireCtrl.checkIn then 
		trigger.action.outTextForGroup(gID, msg, 30, true)
		trigger.action.outSoundForGroup(gID, fireCtrl.actionSound)
	end 
end

function fireCtrl:onEvent(theEvent)
	-- catch birth events of helos 
	if not theEvent then return end 
	local theUnit = theEvent.initiator 
	if not theUnit then return end 
	if not theUnit.getPlayerName then return end 
	local pName = theUnit:getPlayerName()
	if not pName then return end 
	-- we have a player unit 
	if not dcsCommon.unitIsOfLegalType(theUnit, airtank.types) then 
		if fireCtrl.verbose then 
			trigger.action.outText("fireCtrl: unit <" .. theUnit:getName() .. ">, type <" .. theUnit:getTypeName() .. "> not an airtank.", 30)
		end 
		return 
	end 	
	local uName = theUnit:getName()
	local uType = theUnit:getTypeName()
	local theGroup = theUnit:getGroup()
	local gName = theGroup:getName() 
	if theEvent.id == 15 then -- birth
		-- make sure this aircraft is legit 
		fireCtrl.installMenusForUnit(theUnit)
		if fireCtrl.verbose then 
			trigger.action.outText("+++fCtl: new player airtank <" .. uName .. "> type <" .. uType .. "> for <" .. pName .. ">", 30)
		end 
		fireCtrl.checkinPlayer(pName, gName, uName, uType)
		return 
	end
end

function fireCtrl.installMenusForUnit(theUnit) -- assumes all unit types are weeded out
	if not fireCtrl.UI then return end 
	
	-- if already exists, remove old
	if not theUnit then return end 
	if not Unit.isExist(theUnit) then return end 
	local theGroup = theUnit:getGroup() 
	local uName = theUnit:getName()
	local uType = theUnit:getTypeName()
	local pName = theUnit:getPlayerName()
	local gName = theGroup:getName()
	local gID = theGroup:getID()
	local pRoot = fireCtrl.roots[gName]
	if pRoot then 
		missionCommands.removeItemForGroup(gID, pRoot)
		pRoot = nil
	end
	-- handle main menu 
	local mainMenu = nil 
	if fireCtrl.mainMenu then 
		mainMenu = radioMenu.getMainMenuFor(fireCtrl.mainMenu) 
	end 
	-- now add fireCtrl menu 
	pRoot = missionCommands.addSubMenuForGroup(gID, fireCtrl.menuName, mainMenu) 
	fireCtrl.roots[gName] = pRoot -- save for later 
	local args = {gName, uName, gID, uType, pName}
	-- menus: 
	-- report - all current open fires 
	-- action - scoreboard 
	-- arm release -- get ready to drop. auto-release when alt is below 30m 
	local m1 = missionCommands.addCommandForGroup(gID , "Fire Report" , pRoot, fireCtrl.redirectStatus, args)
	local mx2 = missionCommands.addCommandForGroup(gID , "Action Report" , pRoot, fireCtrl.redirectAction, args)
end
--
-- comms
--
function fireCtrl.redirectStatus (args)
	timer.scheduleFunction(fireCtrl.doStatus, args, timer.getTime() + 0.1)
end

function fireCtrl.redirectAction (args)
	timer.scheduleFunction(fireCtrl.doAction, args, timer.getTime() + 0.1)
end

function fireCtrl.doStatus(args)
	local gName = args[1]
	local uName = args[2]
	local gID = args[3]
	local uType = args[4]
	local pName = args[5]
	local theUnit = Unit.getByName(uName)
	if not theUnit then return end 
	local up = theUnit:getPoint()
	up.y = 0 
	local msg = "\nFire emergencies requesting aerial support:\n"
	local count = 0 
	for name, theZone in pairs(inferno.zones) do 
		if theZone.burning then 
			local p = theZone:getPoint()
			local level = theZone.maxSpread
			if level > 1000 or level < 0 then level = 1 end 
			count = count + 1
			if count < 10 then msg = msg .. " " end 
			msg = msg .. count .. ". Type " .. level .. " "
			if twn and towns then 
				local name, data, dist = twn.closestTownTo(p)
				local mdist= dist * 0.539957
				dist = math.floor(dist/100) / 10
				mdist = math.floor(mdist/100) / 10		
				local bear = dcsCommon.compassPositionOfARelativeToB(p, data.p)
				msg = msg .. dist .. "km/" .. mdist .."nm " .. bear .. " of " .. name
				success = true 
			else 
				msg = msg .. "***TWN ERR***"
			end
			local b = dcsCommon.bearingInDegreesFromAtoB(up, p)
			local d = dcsCommon.distFlat(up, p) * 0.000539957
			d = math.floor(d * 10) / 10
			msg = msg .. ", bearing " .. b .. ", " .. d .. "nm\n" 
		end 
	end
	if count < 1 then 
		msg = msg .. "\n    All is well, blue skies, no fires.\n"
	end 
	msg = msg .. "\n"
	trigger.action.outTextForGroup(gID, msg, 30)
	trigger.action.outSoundForGroup(gID, fireCtrl.listSound)
end

function fireCtrl.doAction(args)
	-- sort heroes by their points, and rank them 
	local h = {} 
	for name, num in pairs(fireCtrl.heroes) do 
		local ele = {}
		ele.name = name 
		ele.num = num 
		ele.rank = fireCtrl.num2rank(num)
		table.insert(h, ele)
	end 
	-- table.sort(table, function (e1, e2) return e1.atr < e2.atr end )
	table.sort(h, function (e1, e2) return e1.num > e2.num end)
	-- now create the top twenty
	local msg = "\nThe Book Of Embers recognizes:\n"
	local count = 0 
	for idx, ele in pairs(h) do 
		count = count + 1
		if count < 21 then 		
			if count < 10 then msg = msg .. " " end 
			msg = msg .. count .. ". " .. ele.rank .. " " .. ele.name .. " (" .. ele.num .. ")\n" 
		end 
	end 	
	if count < 1 then 
		msg = msg .. "\n   *** The Book Is Empty ***\n"
	end 
	trigger.action.outTextForGroup(gID, msg, 30)
	trigger.action.outSoundForGroup(gID, fireCtrl.scoreSound)
end

function fireCtrl.num2rank(num)
	if num < 10 then return "Probie" end 
	if num < 25 then return "Firefighter" end 
	if num < 50 then return "Elltee" end 
	if num < 100 then return "Chief" end 
	if num < 200 then return "Local Hero" end 
	if num < 1000 then return "Fire Hero of " .. dcsCommon.getMapName() .. "(" .. math.floor (num/200) .. ")" end 
	return "Avatar of Hephaestus" 
end
--
-- update
--
function fireCtrl.pickUnlit()
	local linearTable = dcsCommon.enumerateTable(inferno.zones)
	local theZone
	local tries = 0
	repeat 
		theZone = dcsCommon.pickRandom(linearTable)
		tries = tries + 1 
	until (not theZone.burning) or (tries > 100) 
	if tries > 100 then 
		trigger.action.outText("fireCtrl: no unlit zones available", 30)
		return nil
	end 
	return theZone
end

function fireCtrl.startFire()
	local theZone = fireCtrl.pickUnlit()
	if not theZone then return end 
	inferno.ignite(theZone)
	if fireCtrl.verbose or theZone.verbose then 
		trigger.action.outText("+++fCtl: started fire in <" .. theZone.name .. ">", 30)
	end 
end

function fireCtrl.update()
	timer.scheduleFunction(fireCtrl.update, {}, timer.getTime() + 1/fireCtrl.ups)
	
	-- see if on/off 
	if fireCtrl.ctrOn and cfxZones.testZoneFlag(fireCtrl, fireCtrl.ctrOn, fireCtrl.method, "lastCtrOn") then 
		fireCtrl.enabled = true 
		if fireCtrl.verbose then 
			trigger.action.outText("+++fCtrl: turning fire control on.", 30)
		end 
	end 
	
	if fireCtrl.ctrOff and cfxZones.testZoneFlag(fireCtrl, fireCtrl.ctrOff, fireCtrl.method, "lastCtrOff") then 
		fireCtrl.enabled = false 
		if fireCtrl.verbose then 
			trigger.action.outText("+++fCtrl: turning fire control OFF.", 30)
		end 
	end 
	
	-- are we on?
	if not fireCtrl.enabled then return end 
	
	-- check the numbers of fires burning 
	local f = 0 
	local cells = 0 
	for idx, theZone in pairs(inferno.zones) do 
		if theZone.burning then f = f + 1 end
		if theZone.maxSpread > 1000 then 
			cells = cells + #theZone.goodCells
		else 
			cells = cells + theZone.maxSpread + 1
		end
	end 
	
	if f < fireCtrl.minFires then -- start 3!!!! fires 
		fireCtrl.startFire() -- start at least one fire
		if fireCtrl.sparks > 1 then 
			for i=1, fireCtrl.sparks-1 do 
				if math.random(100) > 50 then fireCtrl.startFire() end 
			end
		end 
		if fireCtrl.notifications then 
			trigger.action.outText("\nAll stations, " .. fireCtrl.centerName .. " One. Local fire dispatch have reported a large fire cell and are requesting aerial support. Please check in with " .. fireCtrl.centerName .. " for details.\n", 30)
			trigger.action.outSound(fireCtrl.newFire)
		end
	end	
end
--
-- callbacks
--
function fireCtrl.extCB(theZone)
	local p = theZone:getPoint()
	local name = "<" .. theZone.name .. ">"
	if twn and towns then 
		name = twn.closestTownTo(p)
	end 
	local msg = "\nInferno at " .. name .. " has been extinguished. Our thanks go to\n"
	local heroes = theZone.heroes 
	local hasOne = false 
	if heroes then 
		local awarded = theZone.maxSpread
		if awarded < 1 or awarded > 9999 then 
			awarded = 1
		end
		for name, count in pairs(heroes) do 
			hasOne = true
			msg = msg .. " - " .. name .. " (" .. count .. " successful drops)\n"
			-- award everyone points based on maxSprad 
			if not fireCtrl.heroes[name] then 
				fireCtrl.heroes[name] = awarded 
			else 
				fireCtrl.heroes[name] = fireCtrl.heroes[name] + awarded 
			end
		end 
	end
	if not hasOne then msg = msg .. "\n(no one)\n" end 
	trigger.action.outText(msg, 30)
	trigger.action.outSound(fireCtrl.actionSound)
end

--
-- load / save (game data)
--
function fireCtrl.saveData()
	local theData = {}
	-- save current heroes. simple clone 
	local theHeroes = dcsCommon.clone(fireCtrl.heroes)
	theData.theHeroes = theHeroes
	theData.hasEnabled = true 
	theData.enabled = fireCtrl.enabled
	return theData, fireCtrl.sharedData -- second val only if shared 
end

function fireCtrl.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("fireCtrl", fireCtrl.sharedData) 
	if not theData then 
		if fireCtrl.verbose then 
			trigger.action.outText("+++fireCtrl: no save date received, skipping.", 30)
		end
		return
	end
	local theHeroes = theData.theHeroes
	fireCtrl.heroes = theHeroes 
	if theData.hasEnabled then 
		fireCtrl.enabled = theData.enabled
	end 
end

--
-- start and config 
-- 
function fireCtrl.readConfigZone()
	fireCtrl.name = "fireCtrlConfig" -- make compatible with dml zones 
	local theZone = cfxZones.getZoneByName("fireCtrlConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("fireCtrlConfig") 
	end 
	fireCtrl.verbose = theZone.verbose
	fireCtrl.ups = theZone:getNumberFromZoneProperty("ups", 1/20)
	fireCtrl.actionSound = theZone:getStringFromZoneProperty("actionSound", "none")
	fireCtrl.listSound = theZone:getStringFromZoneProperty("listSound", fireCtrl.actionSound)
	fireCtrl.scoreSound = theZone:getStringFromZoneProperty("scoreSound", fireCtrl.listSound)
	fireCtrl.centerName = theZone:getStringFromZoneProperty("centerName", "Highperch")
	fireCtrl.newFire = theZone:getStringFromZoneProperty("newFire", "firefight new fire alice.ogg")
	fireCtrl.menuName = theZone:getStringFromZoneProperty("menuName", "Contact " .. fireCtrl.centerName)
	fireCtrl.minFires = theZone:getNumberFromZoneProperty("minFires", 3)
	fireCtrl.sparks = theZone:getNumberFromZoneProperty("sparks", 3)
	fireCtrl.notifications = theZone:getBoolFromZoneProperty("notifications", true)
	fireCtrl.UI = theZone:getBoolFromZoneProperty("UI", true)
	
	fireCtrl.enabled = theZone:getBoolFromZoneProperty("onStart", true)
	if theZone:hasProperty("ctrOn?") then 
		fireCtrl.ctrOn = theZone:getStringFromZoneProperty("ctrOn?", "<none>")
		fireCtrl.lastCtrOn = trigger.misc.getUserFlag(fireCtrl.ctrOn)
	end 
	if not fireCtrl.enabled and not fireCtrl.ctrOn then 
		trigger.action.outText("***WARNING: fireCtrl cannot be turned on!", 30)
	end 
	
	if theZone:hasProperty("ctrOff?") then 
		fireCtrl.ctrOff = theZone:getStringFromZoneProperty("ctrOff?", "<none>")
		fireCtrl.lastCtrOff = trigger.misc.getUserFlag(fireCtrl.ctrOff)
	end
	fireCtrl.method = theZone:getStringFromZoneProperty("method", "change")
	
	if theZone:hasProperty("attachTo:") then 
		local attachTo = theZone:getStringFromZoneProperty("attachTo:", "<none>")
		if radioMenu then -- requires optional radio menu to have loaded 
			local mainMenu = radioMenu.mainMenus[attachTo]
			if mainMenu then 
				fireCtrl.mainMenu = mainMenu 
			else 
				trigger.action.outText("+++fireCtrl: cannot find super menu <" .. attachTo .. ">", 30)
			end
		else 
			trigger.action.outText("+++fireCtrl: REQUIRES radioMenu to run before inferno. 'AttachTo:' ignored.", 30)
		end 
	end 
	fireCtrl.checkIn = theZone:getBoolFromZoneProperty("checkIn", true)
	
	-- shared data persistence interface 
	if theZone:hasProperty("sharedData") then 
		fireCtrl.sharedData = theZone:getStringFromZoneProperty("sharedData", "cfxNameMissing")
	end
end

function fireCtrl.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx fireCtrl requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx fireCtrl", fireCtrl.requiredLibs) then
		return false 
	end
		
	-- read config 
	fireCtrl.readConfigZone()
	if dcsCommon.getSizeOfTable(inferno.zones) < fireCtrl.minFires then 
		trigger.action.outText("+++fCtl: too few inferno zones (" .. fireCtrl.minFires .. " required). fireCtrl aborted.", 30)
		return false 
	end 

	-- connect event handler 
	world.addEventHandler(fireCtrl)
	
	-- install inferno extinguished CB 
	inferno.installExtinguishedCB(fireCtrl.extCB)

	-- now load all save data  
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = fireCtrl.saveData
		persistence.registerModule("fireCtrl", callbacks)
		-- now load my data 
		fireCtrl.loadData()
	end
	
	-- start update 
	timer.scheduleFunction(fireCtrl.update, {}, timer.getTime() + 3)

	-- say Hi!
	trigger.action.outText("cf/x fireCtrl v" .. fireCtrl.version .. " started.", 30)
		
	return true 
end

if not fireCtrl.start() then 
	trigger.action.outText("fireCtrl failed to start up", 30)
	fireCtrl = nil 
end 

