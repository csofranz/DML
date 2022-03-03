unGrief = {}
unGrief.version = "1.0.0"
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
	
--]]--

unGrief.griefers = {} -- offenders are stored here 

-- event proccer 
function unGrief:onEvent(theEvent)
	if not theEvent then return end
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
	
	-- get the two coalitions involved
	local killSide = killer:getCoalition()
	local stiffSide = stiff:getCoalition()
	
	if killSide ~= stiffSide then return end -- fair & square
	
	-- if we get here, we have a problem.
	local previousKills = unGrief.griefers[playerName]
	if not previousKills then previousKills = 0 end 
	
	previousKills = previousKills + 1
	unGrief.griefers[playerName] = previousKills
	
	if previousKills <= unGrief.graceKills then 
		-- ok, let them off with a warning 
		trigger.action.outText(playerName .. " has killed one of their own. YOU ARE ON NOTICE!", 30)
		return 
	end
	
	-- ok, time to get serious 
	trigger.action.outText(playerName .. " is killing their own. ".. previousKills .. " kills recorded so far. We disaprove", 30)

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
		return 
	end 
	
	unGrief.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	unGrief.graceKills = cfxZones.getNumberFromZoneProperty(theZone, "graceKills", 1)
	unGrief.retaliation = cfxZones.getStringFromZoneProperty(theZone, "retaliation", "boom") -- other possible methods: ssb 
	if unGrief.verbose then 
		trigger.action.outText("+++uGrf: read config", 30)
	end 
end

function unGrief.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx unGrief requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx unGrief", unGrief.requiredLibs) then
		return false 
	end
	
	-- read config 
	unGrief.readConfigZone()
	
	-- connect event proccer 
	world.addEventHandler(unGrief)
	
	trigger.action.outText("cfx unGrief v" .. unGrief.version .. " started.", 30)
	return true 
end

-- let's go!
if not unGrief.start() then 
	trigger.action.outText("cfx unGrief aborted: missing libraries", 30)
	unGrief = nil 
end
