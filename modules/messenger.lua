messenger = {}
messenger.version = "1.0.0"
messenger.verbose = false 
messenger.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
messenger.messengers = {} 
--[[--
	Version History
	1.0.0 - initial version 
	
--]]--

function messenger.addMessenger(theZone)
	table.insert(messenger.messengers, theZone)
end

function messenger.getMessengerByName(aName) 
	for idx, aZone in pairs(messenger.messengers) do 
		if aName == aZone.name then return aZone end 
	end
	if messenger.verbose then 
		trigger.action.outText("+++msgr: no messenger with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read attributes
--
function messenger.createMessengerDownWithZone(theZone)
	-- start val - a range
	theZone.message = cfxZones.getStringFromZoneProperty(theZone, "message", "") 

	theZone.spaceBefore = cfxZones.getBoolFromZoneProperty(theZone, "spaceBefore", false)
	theZone.spaceAfter = cfxZones.getBoolFromZoneProperty(theZone, "spaceAfter", false)

	theZone.soundFile = cfxZones.getStringFromZoneProperty(theZone, "soundFile", "<none>") 

	-- alternate version: messages: list of messages, need string parser first
	
	theZone.duration = cfxZones.getNumberFromZoneProperty(theZone, "duration", 30)
	
	-- trigger flag "count" / "start?"
	if cfxZones.hasProperty(theZone, "f?") then 
		theZone.triggerMessagerFlag = cfxZones.getStringFromZoneProperty(theZone, "f?", "none")
	end
	
	-- can also use in? for counting. we always use triggerMessagerFlag 
	if cfxZones.hasProperty(theZone, "in?") then 
		theZone.triggerMessagerFlag = cfxZones.getStringFromZoneProperty(theZone, "in?", "none")
	end
	
	if theZone.triggerMessagerFlag then 
		theZone.lastMessageTriggerValue = trigger.misc.getUserFlag(theZone.triggerMessagerFlag) -- save last value
	end
	
	if cfxZones.hasProperty(theZone, "coalition") then 
		theZone.coalition = cfxZones.getCoalitionFromZoneProperty(theZone, "coalition", 0)
	end 
	
end

--
-- Update 
--
function messenger.isTriggered(theZone)
	-- this module has triggered 
	local fileName = "l10n/DEFAULT/" .. theZone.soundFile
	local msg = theZone.message 
	if theZone.spaceBefore then msg = "\n"..msg end 
	if theZone.spaceAfter then msg = msg .. "\n" end 
	
	if theZone.coalition then 
		trigger.action.outTextForCoalition(theZone.coalition, msg, theZone.duration)
		trigger.action.outSoundForCoalition(theZone.coalition, fileName)
	else 
		-- out to all 
		trigger.action.outText(msg, theZone.duration)
		trigger.action.outSound(fileName)
	end
end

function messenger.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(messenger.update, {}, timer.getTime() + 1)
		
	for idx, aZone in pairs(messenger.messengers) do
		-- make sure to re-start before reading time limit
		if aZone.triggerMessagerFlag then 
			local currTriggerVal = trigger.misc.getUserFlag(aZone.triggerMessagerFlag)
			if currTriggerVal ~= aZone.lastMessageTriggerValue
			then 
				if messenger.verbose then 
					trigger.action.outText("+++msgr: triggered on in?", 30)
				end
				messenger.isTriggered(aZone)
				aZone.lastMessageTriggerValue = trigger.misc.getUserFlag(aZone.triggerMessagerFlag) -- save last value
			end
		end
	end
end

--
-- Config & Start
--
function messenger.readConfigZone()
	local theZone = cfxZones.getZoneByName("messengerConfig") 
	if not theZone then 
		if messenger.verbose then 
			trigger.action.outText("+++msgr: NO config zone!", 30)
		end 
		return 
	end 
	
	messenger.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if messenger.verbose then 
		trigger.action.outText("+++msgr: read config", 30)
	end 
end

function messenger.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Count Down requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Count Down", messenger.requiredLibs) then
		return false 
	end
	
	-- read config 
	messenger.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("messenger")
	for k, aZone in pairs(attrZones) do 
		messenger.createMessengerDownWithZone(aZone) -- process attributes
		messenger.addMessenger(aZone) -- add to list
	end
	
	-- start update 
	messenger.update()
	
	trigger.action.outText("cfx Messenger v" .. messenger.version .. " started.", 30)
	return true 
end

-- let's go!
if not messenger.start() then 
	trigger.action.outText("cfx Messenger aborted: missing libraries", 30)
	messenger = nil 
end