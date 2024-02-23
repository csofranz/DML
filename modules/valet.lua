valet = {}
valet.version = "1.0.3"
valet.verbose = false 
valet.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
valet.valets = {}

--[[--
	Version History
	1.0.0 - initial version 
	1.0.1 - typos in verbosity corrected
	1.0.2 - also scan birth events 
	1.0.3 - outSoundFile now working correctly 
	
--]]--

function valet.addValet(theZone)
	table.insert(valet.valets, theZone)
end

function valet.getValetByName(aName) 
	for idx, aZone in pairs(valet.valets) do 
		if aName == aZone.name then return aZone end 
	end
	if valet.verbose then 
		trigger.action.outText("+++valet: no valet with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read attributes
--
function valet.createValetWithZone(theZone)
	-- start val - a range
	
	theZone.inSoundFile = cfxZones.getStringFromZoneProperty(theZone, "inSoundFile", "<none>")
	if cfxZones.hasProperty(theZone, "firstInSoundFile") then 
		theZone.firstInSoundFile = cfxZones.getStringFromZoneProperty(theZone, "firstInSoundFile", "<none>")
	end 
	
	theZone.outSoundFile = cfxZones.getStringFromZoneProperty(theZone, "outSoundFile", theZone.inSoundFile)

	-- greeting/first greeting, handle if "" = no text out 
	if cfxZones.hasProperty(theZone, "firstGreeting") then 
		theZone.firstGreeting = cfxZones.getStringFromZoneProperty(theZone, "firstGreeting", "")
	end 
	theZone.greeting = cfxZones.getStringFromZoneProperty(theZone, "greeting", "")
	
	theZone.greetSpawns = cfxZones.getBoolFromZoneProperty(theZone, "greetSpawns", false)
	
	-- goodbye 
	theZone.goodbye = cfxZones.getStringFromZoneProperty(theZone, "goodbye", "")
	
	theZone.duration = cfxZones.getNumberFromZoneProperty(theZone, "duration", 30) -- warning: crossover from messenger. Intentional 
	
	-- valetMethod for outputs
	theZone.valetMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "valetMethod") then 
		theZone.valetMethod = cfxZones.getStringFromZoneProperty(theZone, "valetMethod", "inc")
	end 
	
	-- outputs 
	if cfxZones.hasProperty(theZone, "hi!") then 
		theZone.valetHi = cfxZones.getStringFromZoneProperty(theZone, "hi!", "*<none>")
	end
	
	if cfxZones.hasProperty(theZone, "bye!") then 
		theZone.valetBye = cfxZones.getStringFromZoneProperty(theZone, "bye!", "*<none>")
	end
	
	-- reveiver: coalition, group, unit 
	if cfxZones.hasProperty(theZone, "coalition") then 
		theZone.valetCoalition = cfxZones.getCoalitionFromZoneProperty(theZone, "coalition", 0)
	elseif cfxZones.hasProperty(theZone, "valetCoalition") then 
		theZone.valetCoalition = cfxZones.getCoalitionFromZoneProperty(theZone, "valetCoalition", 0)
	end 
	
	if cfxZones.hasProperty(theZone, "types") then 
		local types = cfxZones.getStringFromZoneProperty(theZone, "types", "")
		theZone.valetTypes = dcsCommon.string2Array(types, ",")
	elseif cfxZones.hasProperty(theZone, "valetTypes") then 
		local types = cfxZones.getStringFromZoneProperty(theZone, "valetTypes", "")
		theZone.valetTypes = dcsCommon.string2Array(groups, ",")
	end
	
	if cfxZones.hasProperty(theZone, "groups") then 
		local groups = cfxZones.getStringFromZoneProperty(theZone, "groups", "<none>")
		theZone.valetGroups = dcsCommon.string2Array(groups, ",")
	elseif cfxZones.hasProperty(theZone, "valetGroups") then 
		local groups = cfxZones.getStringFromZoneProperty(theZone, "valetGroups", "<none>")
		theZone.valetGroups = dcsCommon.string2Array(groups, ",")
	end
	
	if cfxZones.hasProperty(theZone, "units") then 
		local units = cfxZones.getStringFromZoneProperty(theZone, "units", "<none>")
		theZone.valetUnits = dcsCommon.string2Array(units, ",")
	elseif cfxZones.hasProperty(theZone, "valetUnits") then 
		local units = cfxZones.getStringFromZoneProperty(theZone, "valetUnits", "<none>")
		theZone.valetUnits = dcsCommon.string2Array(units, ",")
	end
	
	if (theZone.valetGroups and theZone.valetUnits) or 
	   (theZone.valetGroups and theZone.valetCoalition) or
	   (theZone.valetUnits and theZone.valetCoalition)
	then 
		trigger.action.outText("+++valet: WARNING - valet in <" .. theZone.name .. "> may have coalition, group or unit. Use only one.", 30)
	end
	
	theZone.imperialUnits = cfxZones.getBoolFromZoneProperty(theZone, "imperial", false)
	if cfxZones.hasProperty(theZone, "imperialUnits") then 
		theZone.imperialUnits = cfxZones.getBoolFromZoneProperty(theZone, "imperialUnits", false)
	end
	
	theZone.valetTimeFormat = cfxZones.getStringFromZoneProperty(theZone, "timeFormat", "<:h>:<:m>:<:s>")
	
	-- collect all players currently in-zone.
	-- since we start the game, there is no player in-game, can skip
	theZone.playersInZone = {}
end

--
-- Update 
--
function valet.preprocessWildcards(inMsg, aUnit, theDesc)
	local theMsg = inMsg
	local pName = "Unknown"
	if aUnit.getPlayerName then 
		pN = aUnit:getPlayerName()
		if pN then pName = pN end 
	end
	theMsg = theMsg:gsub("<player>", pName)
	theMsg = theMsg:gsub("<unit>", aUnit:getName())
	theMsg = theMsg:gsub("<type>", aUnit:getTypeName())
	theMsg = theMsg:gsub("<group>", aUnit:getGroup():getName())
	theMsg = theMsg:gsub("<in>", tostring(theDesc.greets + 1) )
	theMsg = theMsg:gsub("<out>", tostring(theDesc.byes + 1))
	return theMsg
end

function valet.greetPlayer(playerName, aPlayerUnit, theZone, theDesc)
	--trigger.action.outText("valet.greetPlayer <" .. theZone.name .. "> enter", 30)
	-- player has just entred zone
	local msg = theZone.greeting
	local dur = theZone.duration
	local fileName = "l10n/DEFAULT/" .. theZone.inSoundFile
	local ID = aPlayerUnit:getID()

	-- see if this was the first time, and if so, if we have a special first message
	if theDesc.greets < 1 then
		if theZone.firstGreeting then 
			msg = theZone.firstGreeting
		end 
		if theZone.firstInSoundFile then 
			fileName = "l10n/DEFAULT/" .. theZone.firstInSoundFile
		end 
	end
	
	if msg == "<none>" then msg = "" end 
	if not msg then msg = "" end 
	
	-- an empty string suppresses message/sound 
	if msg ~= "" then 
		if theZone.verbose then 
			trigger.action.outText("+++valet: <" .. theZone.name .. "> - 'greet' triggers for player <" .. playerName .. "> in <" .. aPlayerUnit:getName() .. ">", 30)
		end
	
		-- process and say meessage 
		msg = valet.preprocessWildcards(msg, aPlayerUnit, theDesc)
		msg = cfxZones.processStringWildcards(msg, theZone, theZone.valetTimeFormat, theZone.imperialUnits) -- nil responses
		
		-- now always output only to the player 
		trigger.action.outTextForUnit(ID, msg, dur)
	end	
	
	-- always play, if no sound file found it will have no effect
	trigger.action.outSoundForUnit(ID, fileName)
	
	-- update desc 
	theDesc.currentlyIn = true 
	theDesc.greets = theDesc.greets + 1

	-- bang output 
	if theZone.valetHi then 
		cfxZones.pollFlag(theZone.valetHi, theZone.valetMethod, theZone)
		if theZone.verbose or valet.verbose then 
			trigger.action.outText("+++valet: banging output 'hi!' with <" .. theZone.valetMethod .. "> on <" .. theZone.valetHi .. "> for zone " .. theZone.name, 30)
		end
	end
end

function valet.sendOffPlayer(playerName, aPlayerUnit, theZone, theDesc)
	-- player has left the area
	local msg = theZone.goodbye or ""
	local dur = theZone.duration
	local fileName = "l10n/DEFAULT/" .. theZone.outSoundFile
	local ID = aPlayerUnit:getID()
	
	if msg == "<none>" then msg = "" end
	
	-- an empty string suppresses message/sound 
	if msg ~= "" then 
		-- process and say meessage 
		msg = valet.preprocessWildcards(msg, aPlayerUnit, theDesc)
		msg = cfxZones.processStringWildcards(msg, theZone, theZone.valetTimeFormat, theZone.imperialUnits) -- nil responses
		
		trigger.action.outTextForUnit(ID, msg, dur)
		
	end	
	
	-- always play sound 
	trigger.action.outSoundForUnit(ID, fileName)
	
	-- update desc 
	theDesc.currentlyIn = false 
	theDesc.byes = theDesc.byes + 1

	-- bang output 
	if theZone.valetBye then 
		cfxZones.pollFlag(theZone.valetBye, theZone.valetMethod, theZone)
		if theZone.verbose or valet.verbose then 
			trigger.action.outText("+++valet: banging output 'bye!' with <" .. theZone.valetMethod .. "> on <" .. theZone.valetBye .. "> for zone " .. theZone.name, 30)
		end
	end
	
end

function valet.checkZoneAgainstPlayers(theZone, allPlayers)
	-- check status of all players if they are inside or 
	-- outside the zone (done during update)
	-- when a change happens, react to it 
	local p = cfxZones.getPoint(theZone)
	p.y = 0 -- sanity first
	local maxRad = theZone.maxRadius
	-- set up hysteresis 
	local outside = maxRad * 1.2 
	for playerName, aPlayerUnit in pairs (allPlayers) do 
		local unitName = aPlayerUnit:getName()
		local uP = aPlayerUnit:getPoint()
		local uCoa = aPlayerUnit:getCoalition() 
		local uGroup = aPlayerUnit:getGroup()
		local groupName = uGroup:getName() 
		--local cat = aPlayerUnit:getDesc().category -- note indirection!
		local uType = aPlayerUnit:getTypeName()
		
		if theZone.valetCoalition and theZone.valetCoalition ~= uCoa then 
			-- coalition mismatch -- no checks required 
			
		elseif theZone.valetGroups and not dcsCommon.wildArrayContainsString(theZone.valetGroups, groupName) then
			-- group name mismatch, skip checks
			 
		elseif theZone.valetUnits and not dcsCommon.wildArrayContainsString(theZone.valetUnits, unitName) then 
			-- unit name mismatch, skip checks
			 
		elseif theZone.valetTypes and not dcsCommon.wildArrayContainsString(theZone.valetTypes, uType) then
			-- types dont match 
		
		else
			local theDesc = theZone.playersInZone[playerName] -- may be nil
			uP.y = 0 -- mask out y 
			local dist = dcsCommon.dist(p, uP) -- get distance 
			if cfxZones.pointInZone(uP, theZone) then 
				-- the unit is inside the zone. 
				-- see if it was inside last time 
				-- if new player, create new record, start as outside
				if not theDesc then 
					theDesc = {}
					theDesc.currentlyIn = false 
					theDesc.greets = 0 
					theDesc.byes = 0 
					theDesc.unitName = unitName
					theZone.playersInZone[playerName] = theDesc
				else 
					if theDesc.unitName == unitName then 
					else
						-- ha!!! player changed planes!
						theDesc.currentlyIn = false 
						theDesc.greets = 0 
						theDesc.byes = 0 
						theDesc.unitName = unitName
					end
				end
				
				if not theDesc.currentlyIn then 
					-- we detect a change. Need to greet 
					valet.greetPlayer(playerName, aPlayerUnit, theZone, theDesc)
				end
				
			elseif (dist > outside) and theDesc then 
				if theDesc.unitName == unitName then 
				else
					-- ha!!! player changed planes!
					theDesc.currentlyIn = false 
					theDesc.greets = 0 
					theDesc.byes = 0 
					theDesc.unitName = unitName
				end
					
				if theDesc.currentlyIn then 
					-- unit is definitely outside and was inside before
					-- (there's a record in this zone's playersInZone 
					valet.sendOffPlayer(playerName, aPlayerUnit, theZone, theDesc)
				else 
					-- was outside before
				end 
			else 
				-- we are in the twilight zone (hysteresis). Do nothing.
			end 
		end -- else do checks 
	end
end

function valet.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(valet.update, {}, timer.getTime() + 1)

	-- collect all players 
	local allPlayers = {}
	
	-- single-player first 
	local sp = world.getPlayer() -- returns unit 
	if sp then 
		local playerName = sp:getPlayerName()
		if playerName then 
			allPlayers[playerName] = sp
		end 
	end
	
	-- now clients 
	local coalitions = {0, 1, 2}
	for isx, aCoa in pairs (coalitions) do 
		local coaClients = coalition.getPlayers(aCoa)
		for idy, aUnit in pairs (coaClients) do 
			if aUnit.getPlayerName and aUnit:getPlayerName() then 
				allPlayers[aUnit:getPlayerName()] = aUnit  
			end
		end
	end
	
	for idx, theZone in pairs(valet.valets) do
		valet.checkZoneAgainstPlayers(theZone, allPlayers)
	end
end

--
-- OnEvent - detecting player enter unit 
--

function valet.checkPlayerSpawn(playerName, theUnit)
	-- see if player spawned in a valet zone
	if not playerName then return end
	if not theUnit then return end
	
	local pos = theUnit:getPoint()
	--trigger.action.outText("+++valet: spawn event", 30)
	for idx, theZone in pairs(valet.valets) do
		-- erase any old records 
		theZone.playersInZone[playerName] = nil
		-- create new if in that valet zone 
		if cfxZones.pointInZone(pos, theZone) then 
			theDesc = {}
			theDesc.currentlyIn = true -- suppress messages
			if theZone.greetSpawns then 
				theDesc.currentlyIn = false 
			end
			theDesc.greets = 0 
			theDesc.byes = 0 
			theDesc.unitName = theUnit:getName()
			theZone.playersInZone[playerName] = theDesc
			if theZone.verbose then 
				trigger.action.outText("+++valet: spawning player <" .. playerName .. "> / <" .. theUnit:getName() .. "> in valet <" .. theZone.name .. ">", 40)
			end
		end
	end
end

function valet:onEvent(event)
	if (event.id == 20) or (event.id == 15) then 
		if not event.initiator then return end 
		local theUnit = event.initiator
		if not theUnit.getPlayerName then
			if event.id == 20 then 
				trigger.action.outText("+++valet: non player event 20(?)", 30)
			end -- 15 (birth can happen to all)
			return 
		end 
		local pName = theUnit:getPlayerName()
		if not pName then 
			if event.id == 20 then 
				trigger.action.outText("+++valet: nil player name on event 20 (!)", 30)
			end 
			return 
		end
		
		valet.checkPlayerSpawn(pName, theUnit)
	end
end

--
-- Config & Start
--
function valet.readConfigZone()
	local theZone = cfxZones.getZoneByName("valetConfig") 
	if not theZone then 
		if valet.verbose then 
			trigger.action.outText("+++valet: NO config zone!", 30)
		end 
		theZone =  cfxZones.createSimpleZone("valetConfig")
	end 
	
	valet.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if valet.verbose then 
		trigger.action.outText("+++valet: read config", 30)
	end 
end

function valet.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx valet requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx valet", valet.requiredLibs) then
		return false 
	end
	
	-- read config 
	valet.readConfigZone()
	
	-- process valet Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("valet")
	for k, aZone in pairs(attrZones) do 
		valet.createValetWithZone(aZone) -- process attributes
		valet.addValet(aZone) -- add to list
	end
	
	-- register event handler 
	world.addEventHandler(valet)
	
	-- start update 
	timer.scheduleFunction(valet.update, {}, timer.getTime() + 1)
	
	trigger.action.outText("cfx valet v" .. valet.version .. " started.", 30)
	return true 
end

-- let's go!
if not valet.start() then 
	trigger.action.outText("cfx valet aborted: missing libraries", 30)
	valet = nil 
end