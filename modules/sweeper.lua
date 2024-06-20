sweeper = {}
sweeper.version = "1.0.1" 
sweeper.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
}
-- remove all units that are detected twice in a row in the same 
-- zone after a time interval. Used to remove deadlocked units.
--[[--
	VERSION HISTORY
	1.0.1 - Initial version 
	
--]]--

sweeper.zones = {}
sweeper.interval = 5 * 60 -- 5 mins (max 10 mins) in zone will kill you
sweeper.verbose = false 
sweeper.flights = {}

function sweeper.addSweeperZone(theZone)
	sweeper.zones[theZone.name] = theZone
end 

function sweeper.readSweeperZone(theZone)
	theZone.aircraft = theZone:getBoolFromZoneProperty("aircraft", true)
	theZone.helos = theZone:getBoolFromZoneProperty("helos", true)
end

function sweeper.update()
	timer.scheduleFunction(sweeper.update, {}, timer.getTime() + sweeper.interval)
	local toKill = {}
	local newFlights = {}
	for idx, theZone in pairs(sweeper.zones) do 
		for i= 0, 2 do 
			local allGroups = coalition.getGroups(i, 2) -- get all ground 
			for idy, theGroup in pairs(allGroups) do 
				local allUnits = theGroup:getUnits()
				for idz, theUnit in pairs(allUnits) do 
					if theZone:unitInZone(theUnit) then 
						table.insert(toKill, theUnit)
					end
				end
			end
			if theZone.aircraft then 
				local allGroups = coalition.getGroups(i, 0) -- get all planes 
				for idy, theGroup in pairs(allGroups) do 
					local allUnits = theGroup:getUnits()
					for idz, theUnit in pairs(allUnits) do 
						if theZone:unitInZone(theUnit) then 
							-- see if this was was already noted 
							uName = theUnit:getName()
							if sweeper.flights[uName] then
								table.insert(toKill, theUnit)
								if sweeper.verbose then 
									trigger.action.outText("Sweeping aircraft <" .. uName .. "> off zone for obstruction", 30)
								end 
							else 
								newFlights[uName] = true 
								if sweeper.verbose then 
									trigger.action.outText("sweep: aircraft <" .. uName .. "> on notice", 30)
								end 
							end
						end
					end
				end
			end 

			if theZone.helos then 
				local allGroups = coalition.getGroups(i, 1) -- get all helos 
				for idy, theGroup in pairs(allGroups) do 
					local allUnits = theGroup:getUnits()
					for idz, theUnit in pairs(allUnits) do 
						if theZone:unitInZone(theUnit) then 
							-- see if this was was already noted 
							uName = theUnit:getName()
							if sweeper.flights[uName] then
								table.insert(toKill, theUnit)
								if sweeper.verbose then 
									trigger.action.outText("Sweeping helicopter <" .. uName .. "> off zone for obstruction", 30)
								end 
							else 
								newFlights[uName] = true 
								if sweeper.verbose then 
									trigger.action.outText("sweep: helicopter <" .. uName .. "> on notice", 30)
								end 
							end
						end
					end
				end
			end 
		end
	end
	
	-- remove all units in my kill list 
	for idx, theUnit in pairs(toKill) do 
		if theUnit.getPlayerName and theUnit:getPlayerName() then 
			-- we do not sweep players
		else 
			if sweeper.verbose then 
				trigger.action.outText("*** sweeper: sweeping <" .. theUnit:getName() .. ">", 30)
			end
			if Unit.isExist(theUnit) then Unit.destroy(theUnit) end 
		end
	end
	
	-- remember new list, forget old 
	sweeper.flights = newFlights
end

function sweeper.readConfig()
	local theZone = cfxZones.getZoneByName("sweeperConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("sweeperConfig") 
	end 
	sweeper.name = "sweeperConfig" -- zones comaptibility 
	sweeper.interval = theZone:getNumberFromZoneProperty("interval", 5 * 60)
	sewwper.verbose = theZone.verbose 
end

function sweeper.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx sweeper requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx sweeper", sweeper.requiredLibs) then
		return false 
	end
	
	sweeper.readConfig()
	
	-- process sweeper Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("sweeper")
	for k, aZone in pairs(attrZones) do 
		sweeper.readSweeperZone(aZone) -- process attributes
		sweeper.addSweeperZone(aZone) -- add to list
	end
		
	-- start update in (interval)
	timer.scheduleFunction(sweeper.update, {}, timer.getTime() + sweeper.interval)
		
	-- say hi 
	trigger.action.outText("sweeper v" .. sweeper.version .. " started.", 30)
	return true 
end

if not sweeper.start() then 
	trigger.action.outText("sweeper failed to start.", 30)
	sweeper = nil 
end