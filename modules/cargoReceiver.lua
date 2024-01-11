cfxCargoReceiver = {}
cfxCargoReceiver.version = "2.0.0" 
cfxCargoReceiver.ups = 1 -- once a second 
cfxCargoReceiver.maxDirectionRange = 500 -- in m. distance when cargo manager starts talking to pilots who are carrying that cargo
cfxCargoReceiver.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"cfxCargoManager", -- will notify me on a cargo event
}
--[[--
  Version history 
  - 2.0.0 no more cfxPlayer Dependency 
          dmlZones, OOP
		  clean-up
  
  
  CargoReceiver is a zone enhancement you use to be automatically 
  notified if a cargo was delivered inside the zone. 
  It also provides BRA when in range to a cargo receiver 
  
  *** EXTENDS ZONES 
  	
--]]--
cfxCargoReceiver.receiverZones = {}
function cfxCargoReceiver.processReceiverZone(aZone) -- process attribute and add to zone
	-- since the attribute is there, simply set the zones
	-- isCargoReceiver flag and we are good
	aZone.isCargoReceiver = true 
	-- we can add additional processing here 
	aZone.autoRemove = aZone:getBoolFromZoneProperty("autoRemove", false) -- maybe add a removeDelay
	aZone.removeDelay = aZone:getNumberFromZoneProperty("removeDelay", 1)
	if aZone.removeDelay < 1 then aZone.removeDelay = 1 end 
	aZone.silent = aZone:getBoolFromZoneProperty("silent", false)
	
	
	-- new method support
	aZone.cargoMethod = aZone:getStringFromZoneProperty("method", "inc")
	if aZone:hasProperty("cargoMethod") then 
		aZone.cargoMethod = aZone:getStringFromZoneProperty("cargoMethod", "inc")
	end
	
	if aZone:hasProperty("f!") then 
		aZone.outReceiveFlag = aZone:getStringFromZoneProperty("f!", "*<none>")
	elseif aZone:hasProperty("cargoReceived!") then 
		aZone.outReceiveFlag = aZone:getStringFromZoneProperty( "cargoReceived!", "*<none>")
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
function cfxCargoReceiver.removeCargo(args)
	-- asynch call
	if not args then return end 
	local theObject = args.theObject 
	local theZone = args.theZone 
	if not theObject then return end 
	if not theObject:isExist() then 
		-- maybe blew up? anyway, we are done 
		return
	end 
	if args.theZone.verbose or cfxCargoReceiver.verbose then 
		trigger.action.outText("+++crgR: removed object <" .. theObject.getName() .. "> from cargo zone <" .. theZone.name .. ">", 30)
	end 
	
	theObject:destroy()
end

function cfxCargoReceiver.cargoEvent(event, object, name) 
	-- usually called from cargomanager 

	if not event then return end 
	if event == "grounded" then 
		-- this is actually the only one that interests us 
		if not object then 
			return 
		end 
		if not Object.isExist(object) then 
			return 
		end 
		loc = object:getPoint()
		
		-- now invoke callbacks for all zones 
		-- this is in 
		for name, aZone in pairs(cfxCargoReceiver.receiverZones) do
			if cfxZones.pointInZone(loc, aZone) then 
				cfxCargoReceiver.invokeCallback("deliver", object, name, aZone)
				
				-- set flags as indicated
				if aZone.outReceiveFlag then 
					cfxZones.pollFlag(aZone.outReceiveFlag, aZone.cargoMethod, aZone)
				end
				
				if aZone.autoRemove then 
					-- schedule this for in a few seconds?
					local args = {}
					args.theObject = object 
					args.theZone = aZone 
					timer.scheduleFunction(cfxCargoReceiver.removeCargo, args, timer.getTime() + aZone.removeDelay)
					--object:destroy()
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
		local receiver = cfxZones.getClosestZone(
			thePoint,
			cfxCargoReceiver.receiverZones -- must be indexed by name
			)
		-- we now check if we are in 'speaking range' and receiver can talk 
		-- modify delta by distance to boundary, not 
		-- center
		local delta = dcsCommon.distFlat(thePoint, cfxZones.getPoint(receiver))
		delta = delta - receiver.radius
		
		if (receiver.silent == false) and 
		   (delta < cfxCargoReceiver.maxDirectionRange) then 
			-- this cargo can be talked down. 
			-- find the player unit that is closest to in in hopes 
			-- that that is the one carrying it
			local allPlayers = dcsCommon.getAllExistingPlayersAndUnits() -- idx by name
			for pname, theUnit in pairs(allPlayers) do 
				-- iterate all player units
				local closestUnit = nil
				local minDelta = math.huge 
				--local theUnit = info.unit
				if theUnit:isExist() then 
					local uPoint = theUnit:getPoint()
					local currDelta = dcsCommon.distFlat(thePoint, uPoint)
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
						message = receiver.name .. " (r=" .. receiver.radius .. "m) is " .. math.floor(delta) .. "m at your " .. oclock
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
-- detect all pilots in zone (not clear: are all detected or only one)