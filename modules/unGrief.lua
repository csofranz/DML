unGrief = {}
unGrief.version = "2.0.2"
unGrief.verbose = false 
unGrief.ups = 1
unGrief.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}

unGrief.enabledFlagValue = 0 -- DO NOT CHANGE, MUST MATCH SSB 
unGrief.disabledFlagValue = unGrief.enabledFlagValue + 100 -- DO NOT CHANGE
--[[--
	unGrief - allow only so many friendly kills.
	
	Version History
	1.0.0 - initial release 
	1.1.0 - wrathful option 
		  - pve option 
		  - ignoreAI option 
	1.2.0 - allow PVP zones 
	      - strict rules
		  - warnings on enter/exit
		  - warnings optional
	2.0.0 - dmlZones 
		  - also trigger on birth event, more wrathful 
		  - auto-turn on ssb when retaliation is SSB 
		  - re-open slot after kick in 15 seconds 
	2.0.1 - DCS bug hardening
	2.0.2 - corrected typo in config 
		  

--]]--

unGrief.griefers = {} -- offenders are stored here 

-- PVP stuff here
unGrief.pvpZones = {}
unGrief.playerPilotZone = {} -- for messaging when leaving/entering pvp zones 


function unGrief.addPvpZone(theZone)
	table.insert(unGrief.pvpZones, theZone)
end

function unGrief.getPvpZoneByName(aName) 
	for idx, aZone in pairs(unGrief.pvpZones) do 
		if aName == aZone.name then return aZone end 
	end
	if unGrief.verbose then 
		trigger.action.outText("+++unGrief: no pvpZone with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read pvp zone 
-- 
function unGrief.createPvpWithZone(theZone)
	-- read pvp data - there's currently really nothing to do 
	if theZone.verbose or unGrief.verbose then 
		trigger.action.outText("+++uGrf: <" .. theZone.name .. "> is designated as PVP legal", 30)
	end
	
	theZone.strictPVP = theZone:getBoolFromZoneProperty("strict", false)
	
end

-- vengeance: if player killed before, they are no longer welcome 
function unGrief.reconcile(groupName)
	-- re-open slot after player was kicked 
	trigger.action.setUserFlag(groupName, unGrief.enabledFlagValue)
	trigger.action.outText("Group <" .. groupName .. "> now available again after pest control action", 30)
end

function unGrief.exactVengance(theEvent) 
	if theEvent.id == 20 or -- S_EVENT_PLAYER_ENTER_UNIT 
	   theEvent.id == 15 then -- Birth 
		if not theEvent.initiator then return end 
		local theUnit = theEvent.initiator
		if not theUnit.getPlayerName then return end -- wierd stuff happening here
		local playerName = theUnit:getPlayerName()
		if not playerName then return end 
		local unitName = theUnit:getName()		
		if unGrief.verbose then 
			trigger.action.outText("+++uGrf: player <" .. playerName .. "> entered <" .. unitName .. ">", 30)
		end 
		
		local causedGrief = unGrief.griefers[playerName]
		if not causedGrief then 
			if unGrief.verbose then 
				trigger.action.outText("+++uGrf: player <" .. playerName .. "> is welcome here", 30)
			end
			return
		end
		
		if causedGrief < unGrief.graceKills + 2 then
			trigger.action.outText("Player <" .. playerName .. "> in <" .. unitName .. "> is on probation", 30)
			return
		end
		
		-- you are done here, buster!
		if unGrief.retaliation == "ssb" then 
		-- use ssb to kick/block the entire group 
			local theGroup = theUnit:getGroup()
			if not theGroup then return end -- you got lucky!
			local groupName = theGroup:getName()
			-- tell ssb to kick now:
			trigger.action.setUserFlag(groupName, unGrief.disabledFlagValue)
			trigger.action.outText("Player <" .. playerName .. "> is not welcome here. Shoo! Shoo!", 30)
			timer.scheduleFunction(unGrief.reconcile, groupName, timer.getTime() + 15)
			return 
		end
		
		-- add some weight for good measure
		-- set them up the bomb
		-- tell them off
		trigger.action.outText("Player <" .. playerName .. "> is not welcome here. Shoo! Shoo!", 30)
		trigger.action.setUnitInternalCargo(unitName, 100000 ) -- 100 tons
		local p = theUnit:getPoint() 
		trigger.action.explosion(p, 10)
	end
end

-- event proccer 
function unGrief:onEvent(theEvent)
	if not theEvent then return end
	if unGrief.wrathful then unGrief.exactVengance(theEvent) end 
	
	if theEvent.id ~= 28 then return end -- only S_EVENT_KILL events allowed
	if not theEvent.initiator then return end -- no initiator, no interest 
	if not theEvent.target then return end -- wtf happened here? begone!
	local killer = theEvent.initiator 
	if not killer or (not Unit.isExist(killer)) then return end -- may have exited already 
	local stiff = theEvent.target 
	if not killer.getPlayerName then return end -- wierd stuff happening here 
	local playerName = killer:getPlayerName()
	if not playerName then return end -- AI kill, not interesting 
	
	-- map (scenery) objects don't have coalition, so check this first
	if not stiff.getCoalition then return end 
	
	local pvpTransgression = false 
	if unGrief.pve and stiff.getPlayerName and stiff:getPlayerName() then
		pvpTransgression = true 
		if pvpTransgression then 
			-- check if this happened in a pvp zone. 
			local crimeScene = stiff:getPoint()
			for idx, theZone in pairs (unGrief.pvpZones) do 
				-- if the VIC is in a pvp zone, that was legal
				if cfxZones.isPointInsideZone(crimeScene, theZone) then 
					-- see if strict rules apply
					if theZone.strictPVP then 
						-- also check killer 
						crimeScene = killer:getPoint()
						if cfxZones.isPointInsideZone(crimeScene, theZone) then 
							pvpTransgression = false 
						end
					else 
						-- relaxed pvp 
						pvpTransgression = false 
					end
					
					if (not pvpTransgression) and 
						(unGrief.verbose or theZone.verbose) then 
						trigger.action.outText("+++uGrf: legal PVP kill of <" .. stiff:getName() .. "> in <" .. theZone.name .. ">", 30)
					end
				end
			end
		end
	end
	
	if unGrief.ignoreAI then 
		if not stiff.getPlayerName then return end -- killed AI, don't care
		if not stiff:getPlayerName() then return end -- killed AI, don't care
	end 
	
	-- get the two coalitions involved
	local killSide = killer:getCoalition()
	local stiffSide = stiff:getCoalition()
	
	if (not pvpTransgression) and (killSide ~= stiffSide) then return end -- fair & square
	
	-- if we get here, we have a problem.
	local previousKills = unGrief.griefers[playerName]
	if not previousKills then previousKills = 0 end 
	
	previousKills = previousKills + 1
	unGrief.griefers[playerName] = previousKills
	
	if previousKills <= unGrief.graceKills then 
		-- ok, let them off with a warning 
		if not pvpTransgression then 
			trigger.action.outText(playerName .. " has killed one of their own. YOU ARE ON NOTICE!", 30)
		else 
			trigger.action.outText(playerName .. " has illegally killed a fellow Player. YOU ARE ON NOTICE!", 30)
		end
		return 
	end
	
	-- ok, time to get serious 
	if not pvpTransgression then 
		trigger.action.outText(playerName .. " is killing their own. ".. previousKills .. " illegal kills recorded so far. We disaprove", 30)
	else 
		trigger.action.outText(playerName .. " is killing other players. ".. previousKills .. " illegal kills recorded so far. We disaprove", 30)
	end

	-- lets set them up the bomb	
	local p = killer:getPoint()
	
	if unGrief.retaliation == "ssb" then 
		-- use ssb to kick/block the entire group 
		local theGroup = killer:getGroup()
		if not theGroup then return end -- you got lucky!
		local groupName = theGroup:getName()
		-- tell ssb to kick now:
		trigger.action.setUserFlag(groupName, unGrief.disabledFlagValue)
		timer.scheduleFunction(unGrief.reconcile, groupName, timer.getTime() + 15)
		return 
	end
	-- aaand all your base are belong to us!
	trigger.action.explosion(p, 100)
	trigger.action.outText("Have a nice day, " .. playerName, 30)
	-- (or kick via SSB or do some other stuff. be creative to boot this idiot)
end

function unGrief.update()
	timer.scheduleFunction(unGrief.update, {}, timer.getTime() + 1/unGrief.ups)
	-- iterate all players 
	for side = 1, 2 do 
		local playersOnThisSide = coalition.getPlayers(side)
		for idx, p in pairs (playersOnThisSide) do 
			local pName = p:getPlayerName()
			if pName then 
				local pLoc = p:getPoint()
				local lastZone =  unGrief.playerPilotZone[pName]
				local currZone = nil 
				local isStrict = false 
				for idy, theZone in pairs(unGrief.pvpZones) do 
					if cfxZones.isPointInsideZone(pLoc, theZone) then 
						currZone = theZone
						isStrict = theZone.strictPVP
					end
				end
				if currZone ~= lastZone then 
					local pG = p:getGroup()
					local gID = pG:getID()
					if currZone then 
						local strictness = ""
						if isStrict then 
							strictness = " STRICT PvP rules apply!"
						end
						
						trigger.action.outTextForGroup(gID, "WARNING: you are entering a PVP zone!" .. strictness, 30)
					else 
						-- left a pvp zone
						trigger.action.outTextForGroup(gID, "NOTE: you are leaving a PVP area!", 30)
					end
					unGrief.playerPilotZone[pName] = currZone
				end 	
			end
		end
	end
end

function unGrief.readConfigZone()
	local theZone = cfxZones.getZoneByName("unGriefConfig") 
	if not theZone then 
		if unGrief.verbose then 
			trigger.action.outText("+++uGrf: NO config zone!", 30)
		end 
		theZone = cfxZones.createSimpleZone("unGriefConfig")
	end 
	
	unGrief.verbose = theZone.verbose 
	
	unGrief.graceKills = theZone:getNumberFromZoneProperty("graceKills", 1)
	unGrief.retaliation = theZone:getStringFromZoneProperty("retaliation", "boom") -- other possible methods: ssb 
	unGrief.retaliation = dcsCommon.trim(unGrief.retaliation:lower())
	if unGrief.retaliation == "ssb" then 
		-- now turn on ssb 
		trigger.action.setUserFlag("SSB",100)
		trigger.action.outText("unGrief: SSB enabled for retaliation.", 30)
	end
	
	unGrief.wrathful = theZone:getBoolFromZoneProperty("wrathful", false)
	
	unGrief.pve = theZone:getBoolFromZoneProperty("pve", false)
	if theZone:hasProperty("pveOnly") then 
		unGrief.pve = theZone:getBoolFromZoneProperty("pveOnly", false)
	end
	
	unGrief.ignoreAI = theZone:getBoolFromZoneProperty("ignoreAI", false)
	
	unGrief.PVPwarnings = theZone:getBoolFromZoneProperty("warnings", true)
	
	if unGrief.verbose then 
		trigger.action.outText("+++uGrf: read config", 30)
	end 
end

function unGrief.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cf/x unGrief requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cf/x unGrief", unGrief.requiredLibs) then
		return false 
	end
	
	-- read config 
	unGrief.readConfigZone()
	
	-- read pvp zones if pve is enabled 
	if unGrief.pve then 
		if unGrief.verbose then 
			trigger.action.outText("PVE mode - scanning for PVP zones", 30)
		end
		local attrZones = cfxZones.getZonesWithAttributeNamed("pvp")
		for k, aZone in pairs(attrZones) do 
			unGrief.createPvpWithZone(aZone) -- process attributes
			unGrief.addPvpZone(aZone) -- add to list
		end
		
		if unGrief.PVPwarnings then 
			unGrief.update() -- start update tracking for player warnings
		end 
	end
	
	-- connect event proccer 
	world.addEventHandler(unGrief)
	
	trigger.action.outText("cf/x unGrief v" .. unGrief.version .. " started.", 30)
	return true 
end

-- let's go!
if not unGrief.start() then 
	trigger.action.outText("cf/x unGrief aborted: missing libraries", 30)
	unGrief = nil 
end

