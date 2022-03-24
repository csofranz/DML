cfxCargoReceiver = {}
cfxCargoReceiver.version = "1.2.1" 
cfxCargoReceiver.ups = 1 -- once a second 
cfxCargoReceiver.maxDirectionRange = 500 -- in m. distance when cargo manager starts talking to pilots who are carrying that cargo
cfxCargoReceiver.requiredLibs = {
	"dcsCommon", -- always
	"cfxPlayer", -- for directions 
	"cfxZones", -- Zones, of course 
	"cfxCargoManager", -- will notify me on a cargo event
}
--[[--
  Version history 
  - 1.0.0 initial vbersion
  - 1.1.0 added flag manipulation options
          no negative agl on announcement 
          silent attribute		
  - 1.2.0 method
		  f!, cargoReceived!
  - 1.2.1 cargoMethod 
  
  
  CargoReceiver is a zone enhancement you use to be automatically 
  notified if a cargo was delivered inside the zone. 
  It also provides BRA when in range to a cargo receiver 
  
  *** EXTENDS ZONES 
  
  Callback signature: 
  cb(event, obj, name, zone) with 
    - event being string, currently defined: 'deliver'
	- obj being the cargo object 
	- name being cargo object name 
	- zone in which cargo was dropped (if dropped)
	
--]]--
cfxCargoReceiver.receiverZones = {}
function cfxCargoReceiver.processReceiverZone(aZone) -- process attribute and add to zone
	-- since the attribute is there, simply set the zones
	-- isCargoReceiver flag and we are good
	aZone.isCargoReceiver = true 
	-- we can add additional processing here 
	aZone.autoRemove = cfxZones.getBoolFromZoneProperty(aZone, "autoRemove", false) -- maybe add a removedelay
	
	aZone.silent = cfxZones.getBoolFromZoneProperty(aZone, "silent", false)
	
	--trigger.action.outText("+++rcv: recognized receiver zone: " .. aZone.name , 30)
	
	-- same integration as object destruct detector for flags
	if cfxZones.hasProperty(aZone, "setFlag") then 
		aZone.setFlag = cfxZones.getStringFromZoneProperty(aZone, "setFlag", "999")
	end
	if cfxZones.hasProperty(aZone, "f=1") then 
		aZone.setFlag = cfxZones.getStringFromZoneProperty(aZone, "f=1", "999")
	end
	if cfxZones.hasProperty(aZone, "clearFlag") then 
		aZone.clearFlag = cfxZones.getStringFromZoneProperty(aZone, "clearFlag", "999")
	end
	if cfxZones.hasProperty(aZone, "f=0") then 
		aZone.clearFlag = cfxZones.getStringFromZoneProperty(aZone, "f=0", "999")
	end
	if cfxZones.hasProperty(aZone, "increaseFlag") then 
		aZone.increaseFlag = cfxZones.getStringFromZoneProperty(aZone, "increaseFlag", "999")
	end
	if cfxZones.hasProperty(aZone, "f+1") then 
		aZone.increaseFlag = cfxZones.getStringFromZoneProperty(aZone, "f+1", "999")
	end
	if cfxZones.hasProperty(aZone, "decreaseFlag") then 
		aZone.decreaseFlag = cfxZones.getStringFromZoneProperty(aZone, "decreaseFlag", "999")
	end
	if cfxZones.hasProperty(aZone, "f-1") then 
		aZone.decreaseFlag = cfxZones.getStringFromZoneProperty(aZone, "f-1", "999")
	end
	
	-- new method support
	aZone.cargoMethod = cfxZones.getStringFromZoneProperty(aZone, "method", "inc")
	if cfxZones.hasProperty(aZone, "cargoMethod") then 
		aZone.cargoMethod = cfxZones.getStringFromZoneProperty(aZone, "cargoMethod", "inc")
	end
	
	if cfxZones.hasProperty(aZone, "f!") then 
		aZone.outReceiveFlag = cfxZones.getStringFromZoneProperty(aZone, "f!", "*<none>")
	end

	if cfxZones.hasProperty(aZone, "cargoReceived!") then 
		aZone.outReceiveFlag = cfxZones.getStringFromZoneProperty(aZone, "cargoReceived!", "*<none>")
	end
	
end

function cfxCargoReceiver.addReceiverZone(aZone)
	if not aZone then return end 
	cfxCargoReceiver.receiverZones[aZone.name] = aZone 
end


-- callback handling
cfxCargoReceiver.callbacks = {}
function cfxCargoReceiver.addCallback(cb)
	table.insert(cfxCargoReceiver.callbacks, cb)
end

function cfxCargoReceiver.invokeCallback(event, obj, name, zone)
	for idx, cb in pairs(cfxCargoReceiver.callbacks) do
		cb(event, obj, name, zone)
	end	
end

function cfxCargoReceiver.standardCallback(event, object, name, zone) 
	trigger.action.outText("Cargo received event <" .. event .. "> for " .. name .. " in " .. zone.name , 30)
end

--
-- cargo event happened. Called by Cargo Manager
--
function cfxCargoReceiver.cargoEvent(event, object, name) 
	--trigger.action.outText("Cargo Receiver: event <" .. event .. "> for " .. name, 30)
	if not event then return end 
	if event == "grounded" then 
		--trigger.action.outText("+++rcv: grounded for " .. name, 30)
		-- this is actually the only one that interests us 
		if not object then 
			--trigger.action.outText("+++rcv: " .. name .. " has null object", 30)
			return 
		end 
		if not object:isExist() then 
			--trigger.action.outText("+++rcv: " .. name .. " no longer exists", 30)
			return 
		end 
		loc = object:getPoint()
		
		-- now invoke callbacks for all zones 
		-- this is in 
		for name, aZone in pairs(cfxCargoReceiver.receiverZones) do
			if cfxZones.pointInZone(loc, aZone) then 
				cfxCargoReceiver.invokeCallback("deliver", object, name, aZone)
				
				-- set flags as indicated
				if aZone.setFlag then 
					trigger.action.setUserFlag(aZone.setFlag, 1)
				end
				if aZone.clearFlag then 
					trigger.action.setUserFlag(aZone.clearFlag, 0)
				end
				if aZone.increaseFlag then 
					local val = trigger.misc.getUserFlag(aZone.increaseFlag) + 1
					trigger.action.setUserFlag(aZone.increaseFlag, val)
				end
				if aZone.decreaseFlag then 
					local val = trigger.misc.getUserFlag(aZone.decreaseFlag) - 1
					trigger.action.setUserFlag(aZone.decreaseFlag, val)
				end
				
				if aZone.outReceiveFlag then 
					cfxZones.pollFlag(aZone.outReceiveFlag, aZone.cargoMethod)
				end
				
				--trigger.action.outText("+++rcv: " .. name .. " delivered in zone " .. aZone.name, 30)
				--trigger.action.outSound("Quest Snare 3.wav")
				if aZone.autoRemove then 
					-- maybe schedule this in a few seconds?
					object:destroy()
				end
			end
		end
	end
end

-- update loop
function cfxCargoReceiver.update()
	-- schedule me in 1/ups 
	timer.scheduleFunction(cfxCargoReceiver.update, {}, timer.getTime() + 1/cfxCargoReceiver.ups)

	-- we now get all cargos that are in the air 
	local liftedCargos = cfxCargoManager.getAllCargo("lifted")
	
	
	-- new we see if any of these are close to a delivery zone 
	for idx, aCargo in pairs(liftedCargos) do 
		local thePoint = aCargo:getPoint()
		local receiver, delta = cfxZones.getClosestZone(
			thePoint,
			cfxCargoReceiver.receiverZones -- must be indexed by name
			)
		-- we now check if we are in 'speaking range' and receiver can talk 
		if (receiver.silent == false) and 
		   (delta < cfxCargoReceiver.maxDirectionRange) then 
			-- this cargo can be talked down. 
			-- find the player unit that is closest to in in hopes 
			-- that that is the one carrying it
			local allPlayers = cfxPlayer.getAllPlayers() -- idx by name
			for pname, info in pairs(allPlayers) do 
				-- iterate all player units
				local closestUnit = nil
				local minDelta = math.huge 
				local theUnit = info.unit
				if theUnit:isExist() then 
					local uPoint = theUnit:getPoint()
					local currDelta = dcsCommon.dist(thePoint, uPoint)
					if currDelta < minDelta then 
						minDelta = currDelta
						closestUnit = theUnit
					end
				end
				
				-- see if we got a player unit close enough
				if closestUnit ~= nil and minDelta < 100 then 
					-- get group and communicate the relevant info 
					local theGroup = closestUnit:getGroup()
					local insideZone = cfxZones.pointInZone(thePoint, receiver)
					local message = aCargo:getName()
					if insideZone then 
						message = message .. " is inside delivery zone " .. receiver.name
					else 
						-- get bra to center 
						local ownHeading = dcsCommon.getUnitHeadingDegrees(closestUnit)
						local oclock = dcsCommon.clockPositionOfARelativeToB(
							receiver.point, 
							thePoint, 
							ownHeading) .. " o'clock"
						message = receiver.name .. " is " .. math.floor(delta) .. "m at your " .. oclock
					end
					-- add agl
					local agl = dcsCommon.getUnitAGL(aCargo)
					if agl < 0 then agl = 0 end 
					message = message .. ". Cargo is " .. math.floor(agl) .. "m AGL."
					-- now say so. 5 second staying power, one second override 
					-- full erase screen
					trigger.action.outTextForGroup(theGroup:getID(),
						message, 5, true)
				else 
					-- cargo in range, no player 
					
				end
			end
		end
	end
end

--
-- GO!
--

function cfxCargoReceiver.start()
	if not dcsCommon.libCheck("cfx Cargo Receiver", 
		cfxCargoReceiver.requiredLibs) then
		return false 
	end

	-- scan all zones for cargoReceiver flag 
	local attrZones = cfxZones.getZonesWithAttributeNamed("cargoReceiver")
	
	-- now create a spawner for all, add them to the spawner updater, and spawn for all zones that are not
	-- paused 
	for k, aZone in pairs(attrZones) do 
		cfxCargoReceiver.processReceiverZone(aZone) -- process attribute and add to zone
		cfxCargoReceiver.addReceiverZone(aZone) -- remember it so we can smoke it
	end

	-- tell cargoManager that I want to be involved
	cfxCargoManager.addCallback(cfxCargoReceiver.cargoEvent)

	-- start update loop
	cfxCargoReceiver.update()
	
	-- say hi
	trigger.action.outText("cfx Cargo Receiver v" .. cfxCargoReceiver.version .. " started.", 30)
	return true 
end

-- let's go 
if not cfxCargoReceiver.start() then 
	trigger.action.outText("cf/x Cargo Receiver aborted: missing libraries", 30)
	cfxCargoReceiver = nil 
end

-- TODO: config zone for talking down pilots
-- TODO: f+/f-/f=1/f=0  