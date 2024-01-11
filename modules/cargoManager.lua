cfxCargoManager = {}
cfxCargoManager.version = "1.0.2"
cfxCargoManager.ups = 1 -- updates per second
--[[--
	Version History
  - 1.0.0 - initial version
  - 1.0.1 - isexist check on remove cargo 
  - 1.0.2 - ability to access a cargo status 
  
  Cargo Manager is a module that watches cargo that is handed for 
  management, and initiates callbacks when a cargo event happens
  Cargo events are (string)
  - lifted (cargo is lifted from ground: ground-->air transition)
  - grounded (cargo was put on the ground: air-->ground transition)
  - disappeared (cargo was deleted): isExits() failed
  - dead (cargo was destroyed) life < 1
  - new (cargo was added to manager) 
  - remove (cargo was removed from manager)

  callback signature
  theCB(event, theCargoObject, cargoName)
--]]--
cfxCargoManager.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}

cfxCargoManager.callbacks = {}
cfxCargoManager.allCargo = {}
cfxCargoManager.cargoStatus = {}
cfxCargoManager.cargoPosition = {}
-- callback management 

cfxCargoManager.monitor = false  

function cfxCargoManager.addCallback(cb)
	table.insert(cfxCargoManager.callbacks, cb)
end

function cfxCargoManager.invokeCallback(event, obj, name)
	for idx, cb in pairs(cfxCargoManager.callbacks) do
		cb(event, obj, name)
	end	
end

function cfxCargoManager.standardCallback(event, object, name) 
	trigger.action.outText("Cargo event <" .. event .. "> for " .. name, 30)
end

-- get cargo status
function cfxCargoManager.getCargoStatusFor(theCargoObject)
	if not theCargoObject then return nil end 
	local cargoName = ""
	if type(theCargoObject) == "string" then 
		cargoName = theCargoObject
	else 
		cargoName = theCargoObject:getName()
	end
	
	if not cargoName then return nil end 
	
	return cargoStatus[cargoName]
	
end
-- add / remove cargo 
function cfxCargoManager.addCargo(theCargoObject) 
	if not theCargoObject then return end 
	if not theCargoObject:isExist() then return end 
	local cargoName = theCargoObject:getName()
	cfxCargoManager.allCargo[cargoName] = theCargoObject
	cfxCargoManager.cargoStatus[cargoName] = "new"
--	cfxCargoManager.cargoStatus[cargoName] = nil
	cfxCargoManager.cargoPosition[cargoName] = theCargoObject:getPoint()
	cfxCargoManager.invokeCallback("new", theCargoObject, cargoName)
end

function cfxCargoManager.removeCargoByName(cargoName)
	if not cargoName then return end 
	local theCargoObject = cfxCargoManager.allCargo[cargoName]
	cfxCargoManager.invokeCallback("remove", theCargoObject, cargoName)
	cfxCargoManager.allCargo[cargoName] = nil
	cfxCargoManager.cargoStatus[cargoName] = nil
	cfxCargoManager.cargoPosition[cargoName] = nil
end

function cfxCargoManager.removeCargo(theCargoObject)
	if not theCargoObject then return end 
	if not theCargoObject:isExist() then return end 
	local cargoName = theCargoObject:getName()
	cfxCargoManager.removeCargoByName(cargoName)
end

-- get all cargo gets all cargos (default) or all cargos 
-- that have a certain state, e.g. lifted
function cfxCargoManager.getAllCargo(filterForState) 
	local theCargo = {}
	for name, cargo in pairs(cfxCargoManager.allCargo) do 
		if (filterForState == nil) or 
		   (filterForState == cfxCargoManager.cargoStatus[name]) 
		then 
			table.insert(theCargo, cargo)
		end
	end
	return theCargo
end

-- update loop 
function cfxCargoManager.determineCargoStatus(cargo)
	if not cargo then return "disappeared" end 
	if not cargo:isExist() then return "disappeared" end 
	-- note that inAir() currently always returns false
	local name = cargo:getName()
	local oldPos = cfxCargoManager.cargoPosition[name]
	local newPos = cargo:getPoint()
	cfxCargoManager.cargoPosition[name] = newPos -- update 
	local delta = dcsCommon.dist(oldPos, newPos)
--	if cargo:inAir() then return "lifted" end -- currentl doesn't work
	if delta > 1 then return "lifted" end -- moving 
	if cargo:getLife() < 1 then return "dead" end 
	local agl = dcsCommon.getUnitAGL(cargo)
	if agl > 5 then return "lifted" end -- not moving but still above ground. good hover!
	
	-- if velocity > 1 m/s this thing is moving 
--	if dcsCommon.vMag(cargo:getVelocity()) > 1 then return "lifted" end -- currently doesn't work
	
	-- this thing simply sits on the ground 
	return "grounded"
end

function cfxCargoManager.update() 
	-- re-schedule in ups 
	timer.scheduleFunction(cfxCargoManager.update, {}, timer.getTime() + 1/cfxCargoManager.ups)
	
	-- iterate all cargos 
	local newCargoManifest = {}
	for name, cargo in pairs(cfxCargoManager.allCargo) do 
		local newStatus = cfxCargoManager.determineCargoStatus(cargo)
		local oldStatus = cfxCargoManager.cargoStatus[name]
		if newStatus ~= oldStatus then
			cfxCargoManager.invokeCallback(newStatus, cargo, name)			
			cfxCargoManager.cargoStatus[name] = newStatus
		end
		if newStatus == "dead" or newStatus == "disappeared" then 
			cfxCargoManager.removeCargoByName(name) -- we are changing what we iterate?
		end
	end
end

-- start up

function cfxCargoManager.start()
	if not dcsCommon.libCheck("cfx Cargo Manager", 
		cfxCargoManager.requiredLibs) then
		return false 
	end

	-- start update loop
	cfxCargoManager.update()
	
	-- say hi
	trigger.action.outText("cfx Cargo Manager v" .. cfxCargoManager.version .. " started.", 30)
	return true 
end

-- let's go 
if not cfxCargoManager.start() then 
	trigger.action.outText("cf/x Cargo Manager aborted: missing libraries", 30)
	cfxCargoManager = nil 
elseif cfxCargoManager.monitor then 
	cfxCargoManager.addCallback(cfxCargoManager.standardCallback)
end