unGrief = {}
unGrief.version = "1.1.0"
unGrief.verbose = false 
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
	
--]]--

unGrief.griefers = {} -- offenders are stored here 

-- vengeance: if player killed before, they are no longer welcome 
function unGrief.exactVengance(theEvent) 
	if theEvent.id == 20 then -- S_EVENT_PLAYER_ENTER_UNIT 
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
	if not killer:isExist() then return end -- may have exited already 
	local stiff = theEvent.target 
	if not killer.getPlayerName then return end -- wierd stuff happening here 
	local playerName = killer:getPlayerName()
	if not playerName then return end -- AI kill, not interesting 
	
	-- map (scenery) objects don't have coalition, so check this first
	if not stiff.getCoalition then return end 
	
	local pvpTransgression = false 
	if unGrief.pve and stiff.getPlayerName and stiff:getPlayerName() then
		pvpTransgression = true 
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
			trigger.action.outText(playerName .. " has killed a fellow Player. YOU ARE ON NOTICE!", 30)
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
		return 
	end
	-- aaand all your base are belong to us!
	trigger.action.explosion(p, 100)
	trigger.action.outText("Have a nice day, " .. playerName, 30)
	-- (or kick via SSB or do some other stuff. be creative to boot this idiot)
end

function unGrief.readConfigZone()
	local theZone = cfxZones.getZoneByName("unGriefConfig") 
	if not theZone then 
		if unGrief.verbose then 
			trigger.action.outText("+++uGrf: NO config zone!", 30)
		end 
		theZone = cfxZone.createSimpleZone("unGriefConfig")
	end 
	
	unGrief.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	unGrief.graceKills = cfxZones.getNumberFromZoneProperty(theZone, "graceKills", 1)
	unGrief.retaliation = cfxZones.getStringFromZoneProperty(theZone, "retaliation", "boom") -- other possible methods: ssb 
	unGrief.retaliation = dcsCommon.trim(unGrief.retaliation:lower())
	
	
	unGrief.wrathful = cfxZones.getBoolFromZoneProperty(theZone, "wrathful", false)
	
	unGrief.pve = cfxZones.getBoolFromZoneProperty(theZone, "pve", false)
	if cfxZones.hasProperty(theZone, "pveOnly") then 
		unGrief.pve = cfxZones.getBoolFromZoneProperty(theZone, "pveOnly", false)
	end
	
	unGrief.ignoreAI = cfxZones.getBoolFromZoneProperty(theZone, "ignoreAI", false)
	
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

-- to be developed: 
-- ungrief on and off flags 
-- pvp and pve zones in addition to global attributes 