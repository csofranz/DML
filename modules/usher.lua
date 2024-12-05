usher = {}
usher.version = "1.0.0"
usher.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
usher.players = {} -- dicts by name, holds a number 
usher.types = {}
usher.units = {}
usher.groups = {}
usher.coas = {}
usher.lastPNum = 0 

function usher.incFlag(name)
	cfxZones.pollFlag(name, "inc", usher) -- support multiple flags and local
	local v = trigger.misc.getUserFlag(name)
	if usher.verbose then 
		trigger.action.outText("+++Ush: banged <" .. name .. "> with <" .. v .. ">", 30)
	end 
end 

-- wildcard proccing
function usher.processStringWildcardsForUnit(inMsg, theUnit)
	return dcsCommon.processStringWildcards(inMsg, theUnit)
	--[[--
	local msg = dcsCommon.processStringWildcards(inMsg)
	local uName = theUnit:getName()
	msg = msg:gsub("<u>", uName)
	pName = "!AI!"
	if dcsCommon.isPlayerUnit(theUnit) then 
		pName = theUnit:getPlayerName()
	else 
		return 
	end
	msg = msg:gsub("<p>", pName)
	msg = msg:gsub("<t>", theUnit:getTypeName())
	local theGroup = theUnit:getGroup()
	local gName = theGroup:getName()
	msg = msg:gsub("<g>", gName)
	local coa = "NEUTRAL"; local e = "NOBODY"
	local c = theGroup:getCoalition()
	if c == 1 then coa = "RED"; e = "BLUE" end 
	if c == 2 then coa = "BLUE"; e = "RED" end 
	msg = msg:gsub("<C>", coa)
	msg = msg:gsub ("<E>", e)
	coa = coa:lower()
	e = e:lower()
	msg = msg:gsub("<c>", coa)
	msg = msg:gsub ("<e>", e)
	return msg
	--]]--
end

-- event handler 
function usher:onEvent(theEvent)
	if not theEvent then return end 
	if theEvent.id == 15 then 
		local theUnit = theEvent.initiator 
		if not theUnit then return end 
		if not theUnit.getGroup then return end  
		if not theUnit.getName then return end 
		if not theUnit.getPlayerName then return end
		local pName = theUnit:getPlayerName()
		if not pName then return end
		-- when we get here, we have a player 
		local uName = theUnit:getName()
		local theGroup = theUnit:getGroup()
		local gID = theGroup:getID()
		local uID = theUnit:getID()
		local gName = theGroup:getName()
		local uType = theUnit:getTypeName()
		local coa = theGroup:getCoalition()
		local f 
		-- now see what events to generate if set up that way 
		
		if usher.coas[coa] then usher.coas[coa] = usher.coas[coa] + 1
		else usher.coas[coa] = 1 end
		-- separation for future expansion 
		if usher.coaEvent and usher.coas[coa] == 1 then -- only first
			-- bang that flag, but only first time
			f = usher.coaNeutralFlag
			if coa == 1 then f = usher.coaRedFlag elseif coa == 2 then f = coaBlueFlag end
			local msg = usher.processStringWildcardsForUnit(usher.coaMsg, theUnit)
			usher.incFlag(f)
			if #msg > 9 then -- empty message will suppress entirely
				trigger.action.outTextForCoalition(coa, msg, 30)
			end 
		end 
		
		if usher.players[pName] then usher.players[pName] = usher.players[pName] + 1 else usher.players[pName] = 1 end 
		if usher.playerEvent and usher.players[pName] == 1 then 
			local msg = usher.processStringWildcardsForUnit(usher.playerMsg, theUnit)
			if #msg > 0 then 
				trigger.action.outTextForUnit(uID, msg, 30)
			end 
			f = usher.prefix .. pName
			usher.incFlag(f)
			usher.incFlag(usher.playerCommand)
			trigger.action.outSoundForUnit(uID, usher.playerSound)
		end
		
		
		if usher.units[uName] then usher.units[uName] = usher.units[uName] + 1 else usher.units[uName] = 1 end
		if usher.unitEvent and usher.units[uName] == 1 then 
			local msg = usher.processStringWildcardsForUnit(usher.unitMsg, theUnit)
			if #msg>0 then 
				trigger.action.outTextForUnit(uID, msg, 30)
			end 
			f = usher.prefix .. uName
			usher.incFlag(f)
		end 
		
		if usher.groups[gName] then usher.groups[gName] = usher.groups[gName] + 1 else usher.groups[gName] = 1 end 
		if usher.groupEvent and usher.groups[gName] == 1 then 
			local msg = usher.processStringWildcardsForUnit(usher.groupMsg, theUnit)
			if #msg > 0 then 
				trigger.action.outTextForGroup(gID, msg, 30)
			end 
			f = usher.prefix .. gName
			usher.incFlag(f)
		end 
		
		if usher.types[uType] then usher.types[uType] = usher.types[uType] + 1 else usher.types[uType] = 1 end
		if usher.typeEvent and usher.types[uType] == 1 then 
			local msg = usher.processStringWildcardsForUnit(usher.typeMsg, theUnit)
			if #msg > 0 then 
				trigger.action.outTextForCoalition(coa, msg, 30)
			end 
			f = usher.prefix .. uType
			usher.incFlag(f)
		end 		
	end
end

-- config
function usher.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("usherConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("usherConfig") 
	end 
	usher.coaMsg = theZone:getStringFromZoneProperty("coaMsg", "Welcome, <p>, your <t> is the first to join <c>.")
	usher.coaEvent = theZone:getBoolFromZoneProperty("coaEvent", false)
	usher.coaRedFlag = theZone:getStringFromZoneProperty("coaRed!", "cfxxx")
	usher.coaBlueFlag = theZone:getStringFromZoneProperty("coaBlue!", "cfxxx")
	usher.coaNeutralFlag = theZone:getStringFromZoneProperty("coaNeutral!", "cfxxx")
	usher.playerEvent = theZone:getBoolFromZoneProperty("playerEvent", true)
	usher.playerMsg = theZone:getStringFromZoneProperty("playerMsg", "Welcome <p>!")
	usher.playerSound = theZone:getStringFromZoneProperty("playerSound", "none")
	usher.playerCommand = theZone:getStringFromZoneProperty("player!", "cfxNone")
	usher.unitEvent = theZone:getBoolFromZoneProperty("unitEvent", false)
	usher.unitMsg = theZone:getStringFromZoneProperty("unitMsg", "Welcome <p>, you are <u>, part of <c> <g> (a flight of <t>).")
	usher.groupEvent = theZone:getBoolFromZoneProperty("groupEvent", false)
	usher.groupMsg = theZone:getStringFromZoneProperty("groupMsg", "Welcome <p>, you are part of <c> <g> (a flight of <t>).")
	usher.typeEvent = theZone:getBoolFromZoneProperty("typeEvent", false)
	usher.typeMsg = theZone:getStringFromZoneProperty("typeMsg", "Welcome to your <t>, <p>!")
	usher.prefix = theZone:getStringFromZoneProperty("prefix", "u:")

	usher.redNum = theZone:getStringFromZoneProperty("red#", "cfxNone")
	usher.blueNum = theZone:getStringFromZoneProperty("blue#", "cfxNone")
	usher.neuNum = theZone:getStringFromZoneProperty("neutral#", "cfxNone")
	usher.pNum = theZone:getStringFromZoneProperty("pNum#", "cfxNone")
	usher.pJoin = theZone:getStringFromZoneProperty("join!", "cfxNone")
	usher.pLeave = theZone:getStringFromZoneProperty("leave!", "cfxNone")
	usher.ups = theZone:getNumberFromZoneProperty("ups", 0.1) -- every 10 secs
	usher.method = theZone:getStringFromZoneProperty("method", "inc")
	usher.verbose = theZone.verbose 
	usher.name = "usherConfig"
end

-- update 
function usher.update()
	timer.scheduleFunction(usher.update, nil, timer.getTime() + 1/usher.ups)
	-- count players per side and set # outputs 
	local numPlayers = coalition.getPlayers(2)
	local total = #numPlayers
	cfxZones.setFlagValue(usher.blueNum, #numPlayers, usher)
	numPlayers = coalition.getPlayers(1)
	total = total + #numPlayers
	cfxZones.setFlagValue(usher.redNum, #numPlayers, usher)	
	numPlayers = coalition.getPlayers(0)
	cfxZones.setFlagValue(usher.neuNum, #numPlayers, usher)
	total = total + #numPlayers
	cfxZones.setFlagValue(usher.pNum, total, usher)
	if total < usher.lastPNum then 
		cfxZones.pollFlag(usher.pLeave, usher.method, usher) 
	elseif total > usher.lastPNum then 
		cfxZones.pollFlag(usher.pJoin, usher.method, usher)
	end 
	usher.lastPNum = total
end 

-- load/save 
function usher.saveData()
	local theData = {}
	theData.players = usher.players
	theData.types = usher.types 
	thaData.units = usher.units 
	theData.groups = usher.groups 
	theData.coas = usher.coas 
	return theData
end

function usher.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("usher")
	if not theData then 
		if usher.verbose then 
			trigger.action.outText("+++ush Persistence: no save data received, skipping.", 30)
		end
		return
	end
	usher.players = theData.players -- dicts by name, holds a number 
	usher.types = theData.types 
	usher.units = theData.units
	usher.groups = theData.groups
	usher.coas = theData.coas
end

-- go go go 

function usher.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("usher requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("usher", usher.requiredLibs) then
		return false 
	end
	
	-- read config 
	usher.readConfigZone()
		
	-- load any saved data 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = usher.saveData
		persistence.registerModule("usher", callbacks)
		-- now load my data 
		usher.loadData()
	end
	
	-- connect event handler 
	world.addEventHandler(usher)
	
	-- invoke update 
	usher.update()
	
	trigger.action.outText("Usher v" .. usher.version .. " started.", 30)
	return true 
end

-- let's go!
if not usher.start() then 
	trigger.action.outText("usher aborted: error on start", 30)
	usher = nil 
end
