valet = {}
valet.version = "2.0.0"
valet.verbose = false 
valet.requiredLibs = {
	"dcsCommon", 
	"cfxZones", 
}
--[[--
	Version History
	2.0.0 - groundOnly attribute 
		  - dml migration
		  - clean up 
--]]--
valet.valets = {} -- all my zones 
function valet.addValet(theZone)
	valet.valets[theZone.name] = theZone
end
function valet.getValetByName(aName) 
	local v = valet.valets[aName]
	if valet.verbose and not v then trigger.action.outText("+++valet: no valet with name <" .. aName ..">", 30) end 
	return v
end
--
-- read attributes
--
function valet.createValetWithZone(theZone)
	-- start val - a range
	theZone.inSoundFile = theZone:getStringFromZoneProperty("inSoundFile", "<none>")
	if theZone:hasProperty("firstInSoundFile") then 
		theZone.firstInSoundFile = theZone:getStringFromZoneProperty("firstInSoundFile", "<none>")
	end 
	theZone.outSoundFile = theZone:getStringFromZoneProperty("outSoundFile", theZone.inSoundFile)

	-- greeting/first greeting, handle if "" = no text out 
	if theZone:hasProperty("firstGreeting") then 
		theZone.firstGreeting = theZone:getStringFromZoneProperty("firstGreeting", "")
	end 
	theZone.greeting = theZone:getStringFromZoneProperty("greeting", "")
	theZone.greetSpawns = theZone:getBoolFromZoneProperty("greetSpawns", false)
	
	-- goodbye 
	theZone.goodbye = theZone:getStringFromZoneProperty("goodbye", "")
	theZone.duration = theZone:getNumberFromZoneProperty("duration", 30) -- warning: crossover from messenger. Intentional 
	
	-- others
	theZone.groundOnly = theZone:getBoolFromZoneProperty("groundOnly", false)
	
	-- valetMethod for outputs
	theZone.valetMethod = theZone:getStringFromZoneProperty("method", "inc")
	if theZone:hasProperty("valetMethod") then 
		theZone.valetMethod = theZone:getStringFromZoneProperty("valetMethod", "inc")
	end 
	
	-- outputs 
	if theZone:hasProperty("hi!") then 
		theZone.valetHi = theZone:getStringFromZoneProperty("hi!", "*<none>")
	end
	if theZone:hasProperty("bye!") then 
		theZone.valetBye = theZone:getStringFromZoneProperty("bye!", "*<none>")
	end
	
	-- reveiver: coalition, group, unit 
	if theZone:hasProperty("coalition") then 
		theZone.valetCoalition = theZone:getCoalitionFromZoneProperty("coalition", 0)
	elseif theZone:hasProperty("valetCoalition") then 
		theZone.valetCoalition = theZone:getCoalitionFromZoneProperty("valetCoalition", 0)
	end 
	
	if theZone:hasProperty("types") then 
		local types = theZone:getStringFromZoneProperty("types", "")
		theZone.valetTypes = dcsCommon.string2Array(types, ",")
	elseif theZone:hasProperty("valetTypes") then 
		local types = theZone:getStringFromZoneProperty(theZone, "valetTypes", "")
		theZone.valetTypes = dcsCommon.string2Array(groups, ",")
	end
	
	if theZone:hasProperty("groups") then 
		local groups = theZone:getStringFromZoneProperty("groups", "<none>")
		theZone.valetGroups = dcsCommon.string2Array(groups, ",")
	elseif theZone:hasProperty("valetGroups") then 
		local groups = theZone:getStringFromZoneProperty("valetGroups", "<none>")
		theZone.valetGroups = dcsCommon.string2Array(groups, ",")
	end
	
	if theZone:hasProperty("units") then 
		local units = theZone:getStringFromZoneProperty("units", "<none>")
		theZone.valetUnits = dcsCommon.string2Array(units, ",")
	elseif theZone:hasProperty("valetUnits") then 
		local units = theZone:getStringFromZoneProperty("valetUnits", "<none>")
		theZone.valetUnits = dcsCommon.string2Array(units, ",")
	end
	
	if (theZone.valetGroups and theZone.valetUnits) or 
	   (theZone.valetGroups and theZone.valetCoalition) or
	   (theZone.valetUnits and theZone.valetCoalition)
	then 
		trigger.action.outText("+++valet: WARNING - valet in <" .. theZone.name .. "> may have a coalition, group OR unit. Use only one.", 30)
	end
	
	theZone.imperialUnits = theZone:getBoolFromZoneProperty("imperial", false)
	if theZone:hasProperty("imperialUnits") then 
		theZone.imperialUnits = theZone:getBoolFromZoneProperty("imperialUnits", false)
	end
	theZone.valetTimeFormat = theZone:getStringFromZoneProperty("timeFormat", "<:h>:<:m>:<:s>")
	-- collect all players currently in-zone.
	-- since we start the game, there is no player in-game, can skip
	theZone.playersInZone = {}
end

--
-- Update 
--
function valet.preprocessWildcards(inMsg, aUnit, theDesc) -- note: most of this procced already 
	local theMsg = inMsg
	local pName = "Unknown"
	if aUnit.getPlayerName then 
		pN = aUnit:getPlayerName()
		if pN then pName = pN end 
	end
	theMsg = theMsg:gsub("<player>", pName)
	theMsg = theMsg:gsub("<p>", pName)
	theMsg = theMsg:gsub("<unit>", aUnit:getName())
	theMsg = theMsg:gsub("<u>", aUnit:getName())
	theMsg = theMsg:gsub("<type>", aUnit:getTypeName())
	--theMsg = theMsg:gsub("<t>", aUnit:getTypeName())
	theMsg = theMsg:gsub("<group>", aUnit:getGroup():getName())
	theMsg = theMsg:gsub("<g>", aUnit:getGroup():getName())
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
		theZone:pollFlag(theZone.valetBye, theZone.valetMethod)
		if theZone.verbose or valet.verbose then 
			trigger.action.outText("+++valet: banging output 'bye!' with <" .. theZone.valetMethod .. "> on <" .. theZone.valetBye .. "> for zone " .. theZone.name, 30)
		end
	end
end

function valet.checkZoneAgainstPlayers(theZone, allPlayers)
	-- check status of all players if they are inside or 
	-- outside the zone (done during update)
	-- when a change happens, react to it 
	local p = theZone:getPoint()
	p.y = 0 -- sanity first
	--local maxRad = theZone.maxRadius
	-- set up hysteresis 
	-- new hysteresis: 10 seconds outside time
	local now = timer.getTime()
	--local outside = maxRad * 1.2 
	for playerName, aPlayerUnit in pairs (allPlayers) do 
		local unitName = aPlayerUnit:getName()
		local uP = aPlayerUnit:getPoint()
		local uCoa = aPlayerUnit:getCoalition() 
		local uGroup = aPlayerUnit:getGroup()
		local groupName = uGroup:getName() 
		if theZone.verbose then trigger.action.outText("valet <" .. theZone.name .. ">, player <" .. playerName .. "> unit <" .. unitName .. ">:", 30) end 
		--local cat = aPlayerUnit:getDesc().category -- note indirection!
		local uType = aPlayerUnit:getTypeName()
		
		if theZone.valetCoalition and theZone.valetCoalition ~= uCoa then 
			-- coalition mismatch -- no checks required 
			if theZone.verbose then trigger.action.outText("coalition mismatch.", 30) end 
		elseif theZone.groundOnly and aPlayerUnit:inAir() then 
			-- only react if unit on the ground -- skip checks 
			if theZone.verbose then trigger.action.outText("Unit in air, filtered", 30) end 
		elseif theZone.valetGroups and not dcsCommon.wildArrayContainsString(theZone.valetGroups, groupName) then
			-- group name mismatch, skip checks
			if theZone.verbose then trigger.action.outText("GROUP name mismatch", 30) end
		elseif theZone.valetUnits and not dcsCommon.wildArrayContainsString(theZone.valetUnits, unitName) then 
			-- unit name mismatch, skip checks
			if theZone.verbose then trigger.action.outText("UNIT name mismatch", 30) end
		elseif theZone.valetTypes and not dcsCommon.wildArrayContainsString(theZone.valetTypes, uType) then
			-- types dont match, skip 
			if theZone.verbose then trigger.action.outText("unit TYPE mismatch", 30) end
		else
			--  unit is relevant for zone 
			local theDesc = theZone.playersInZone[playerName] -- may be nil
			uP.y = 0 -- mask out y 
			--local dist = dcsCommon.dist(p, uP) -- get distance 
			if theZone:pointInZone(uP) then 
				-- the unit is inside the zone. see if it was inside last time 
				-- if new player, create new record, start as outside
				if not theDesc then -- player wasn't in last time 
					theDesc = {}
					theDesc.currentlyIn = false 
					theDesc.lastTimeIn = nil -- reset
					theDesc.greets = 0 
					theDesc.byes = 0 
					theDesc.unitName = unitName
					theZone.playersInZone[playerName] = theDesc
				else 
					if theDesc.unitName == unitName then 
					else
						-- ha!!! player changed planes!
						theDesc.currentlyIn = false 
						theDesc.lastTimeIn = nil -- reset 
						theDesc.greets = 0 
						theDesc.byes = 0 
						theDesc.unitName = unitName
					end
				end
				if not theDesc.currentlyIn then 
					-- we detect a change. Need to greet 
					if theZone.verbose then trigger.action.outText("change: -->IN", 30) end
					valet.greetPlayer(playerName, aPlayerUnit, theZone, theDesc)
				else
					if theZone.verbose then trigger.action.outText("already inside", 30) end
				end
				theDesc.lastTimeIn = now 
				
			-- below here: unit is NOT inside zone 
			elseif theDesc and theDesc.lastTimeIn and (now > theDesc.lastTimeIn + 10) then 
				-- hysteresis timed out 
				if theDesc.unitName == unitName then 
				else
					-- ha!!! player changed planes!
					theDesc.currentlyIn = false 
					theDesc.lastTimeIn = nil -- reset
					theDesc.greets = 0 
					theDesc.byes = 0 
					theDesc.unitName = unitName
				end
				if theDesc.currentlyIn then 
					-- unit is definitely outside and was inside before
					-- (there's a record in this zone's playersInZone 
					-- and hysteresis has timed out 
					if theZone.verbose then trigger.action.outText("change: --> OUT", 30) end
					valet.sendOffPlayer(playerName, aPlayerUnit, theZone, theDesc)
				else 
					-- was outside before
					if theZone.verbose then trigger.action.outText("already out", 30) end
				end 
				theDesc.lastTimeIn = nil -- wasn't in 
				theDesc.currentlyIn = false 
			elseif theDesc and not theDesc.lastTimeIn then 
				-- outside, no hysteresis timer running 
				if theZone.verbose then trigger.action.outText("outside", 30) end
			else 
				-- we are in the twilight zone (hysteresis running). Do nothing.
				-- no message while hysteresis is active!
				if theZone.verbose then 
					local h = now - theDesc.lastTimeIn
					trigger.action.outText("hysteresis active: " .. h, 30) 
				end
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
	if not theUnit.getName then return end 
	local pos = theUnit:getPoint()
	--trigger.action.outText("+++valet: spawn event", 30)
	for idx, theZone in pairs(valet.valets) do
		-- erase any old records 
		theZone.playersInZone[playerName] = nil
		-- create new if in that valet zone 
		if theZone:pointInZone(pos) then 
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
		theZone =  cfxZones.createSimpleZone("valetConfig")
	end 
	valet.verbose = theZone.verbose 
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