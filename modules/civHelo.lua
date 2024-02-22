civHelo = {}
civHelo.version = "1.0.0"
civHelo.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", 
}
--[[--
Version History
	1.0.0 - Initial version 
	
--]]--

civHelo.flights = {} -- currently active flights 
civHelo.ports = {} -- civHelo zones where flight can take off and land 
civHelo.maxDist = 600000 -- 60 km 
civHelo.minDist = 1000 -- 1 km 
-- helos and liveries 
civHelo.types = {"CH-47D", "CH-53E", "Ka-27", "Mi-24V", "Mi-26", "Mi-28N", "Mi-8MT","OH-58D", "SA342L", "SH-60B", "UH-1H", "UH-60A",} -- default set

civHelo.liveries = {
["CH-47D"] = {"Australia RAAF", "ch-47_green neth", "ch-47_green spain", "ch-47_green uk", "Greek Army", "standard", }, 
["CH-53E"] = {"standard",},
["Ka-27"] = {"China PLANAF", "standard", "ukraine camo 1",},
["Mi-24V"] = {"Abkhazia", "Algerian AF Black", "Algerian AF New Desert", "Algerian AF Old Desert", "Russia_FSB", "Russia_MVD", "South Ossetia", "standard", "standard 1", "standard 2 (faded and sun-bleached)", "ukraine", "Ukraine UN", },
["Mi-26"] = {"7th Separate Brigade of AA (Kalinov)", "Algerian Air Force SL-22", "China Flying Dragon Aviation", "RF Air Force", "Russia_FSB", "Russia_MVD", "United Nations", },
["Mi-28N"] = {"AAF SC-11", "AAF SC-12", "night", "standard", }, 
["Mi-8MT"] = {"China UN", "IR Iranian Special Police Forces", "Russia_Gazprom", "Russia_PF_Ambulance", "Russia_Police", "Russia_UN", "Russia_UTair", "Russia_Aeroflot", "Russia_KazanVZ", "Russia_LII_Gromov RA-25546", "Russia_Vertolety_Russia", "Russia_Vertolety_Russia_2", "Russia_Naryan-Mar", }, 
--["OH-58D"] = {"",},
--["SA342L"] = {"",},
["SH-60B"] = {"Hellenic Navy", "standard", },
["UH-1H"] = {"[Civilian] Medical", "[Civilian] NASA", "[Civilian] Standard", "[Civilian] VIP", "Greek Army Aviation Medic", "Italy 15B Stormo S.A.R -Soccorso", "Norwegian Coast Guard (235)", "Norwegian UN", "Spanish UN", "USA UN", }, 
["UH-60A"] = {"ISRAIL_UN", }
}
--
-- process civHelo zone 
--
function civHelo.readCivHeloZone(theZone)
	-- process properties 
	theZone.canLand = theZone:getBoolFromZoneProperty("land", true)
	theZone.canStart = theZone:getBoolFromZoneProperty("start", true)
	theZone.hotStart = theZone:getBoolFromZoneProperty("hot", true)
	
	if theZone:hasProperty("types") then 
		local hTypes = theZone:getStringFromZoneProperty("types", "xxx")
		local typeArray = dcsCommon.splitString(hTypes, ",")
		typeArray = dcsCommon.trimArray(typeArray)
		theZone.types = typeArray 
	end
	-- set active flag 
	theZone.inUse = nil -- if true zone is in use for a flight
end

function civHelo.addCivHeloZone(theZone)
	table.insert(civHelo.ports, theZone)
end

function civHelo.getPortNamed(name)
	for idx, theZone in pairs(civHelo.ports) do 
		if theZone.name == name then return theZone end 
	end
	if civHelo.verbose then 
		trigger.action.outText("+++civH: cannot find port <" .. name .. ">", 30)
	end 
	return nil 
end 

function civHelo.getFreePort(source, dest, anchor)
	collector = {}
	local a 
	if anchor then a = anchor:getPoint() end -- for dist calc  
	for idx, theZone in pairs(civHelo.ports) do 
		if theZone.inUse then 
		else
			if (source and theZone.canStart) or 
               (dest and theZone.canLand) then 	
				if anchor then 
					-- must be at least minDist and at most maxDist away 
					local p = theZone:getPoint()
					local d = dcsCommon.dist(a, p)
					if d > civHelo.minDist and d < civHelo.maxDist then 
						table.insert(collector, theZone)
					else 
--						trigger.action.outText("+++civH: disregarded dest zone <" .. theZone.name .. ">: dist <" .. math.floor(d) / 1000 .. " km> out of bounds", 30)
					end
				else 
					table.insert(collector, theZone)
				end
			end 
		end
	end
	if #collector < 1 then return nil end 
	local theZone = dcsCommon.pickRandom(collector)
	return theZone
end

function civHelo.getSourceAndDest()
	local source = civHelo.getFreePort(true, false)
	if not source then return nil, nil end 
	source.inUse = true 
	local dest = civHelo.getFreePort(false, true, source)
	if not dest then 
		source.inUse = nil 
		return nil, nil
	end 
	dest.inUse = true 
	return source, dest 
end


function civHelo.createCommandTask(theCommand, num) 
	if not num then num = 1 end 
	local t = {}
	t.enabled = true 
	t.auto = false 
	t.id = "WrappedAction"
	t.number = num 
	local params = {}
	t.params = params 
	local action = {}
	params.action = action 
	action.id = "Script"
	local p2 = {}
	action.params = p2 
	p2.command = theCommand 
	return t 
end

function civHelo.createLandTask(p, duration, num) 
	if not num then num = 1 end 
	local t = {}
	t.enabled = true 
	t.auto = false 
	t.id = "ControlledTask"
	t.number = num 
	local params = {}
	t.params = params 
	
	local ptsk = {}
	params.task = ptsk 
	ptsk.id = "Land"
	local ptp = {}
	ptsk.params = ptp
	ptp.x = p.x 
	ptp.y = p.z 
	ptp.duration = "300" -- not sure why 
	ptp.durationFlag = false -- off anyway 
	local stopCon = {}
	stopCon.duration = duration
	params.stopCondition = stopCon 
	
	return t 
end

function civHelo.createFlight(name, theType, fromZone, toZone) --, inAir)
	if not fromZone then return nil end 
	if not toZone then return nil end 
--	if not inAir then inAir = false end 
	
	local theGroup = dcsCommon.createEmptyAircraftGroupData (name)
	local theHUnit = dcsCommon.createAircraftUnitData(name .. "-H", theType, false)
	if fromZone.hdg then 
		
	end 
	-- add livery capability for this aircraft 
	--civHelo.processLiveriesFor(theHUnit, theType)
	civHelo.getLiveryForType(theType, theHUnit)
	
	-- enforce civ attribute 
	theHUnit.civil_plane = true 
	
	theHUnit.payload.fuel = 5000 -- 5t of fuel 
	dcsCommon.addUnitToGroupData(theHUnit, theGroup)

	local A = fromZone:getPoint()
	local B = toZone:getPoint()
	
	-- unit is done, let's do the route
	-- WP 1: take off 
	local fromWP, omwWP 
	fromWP = dcsCommon.createTakeOffFromGroundRoutePointData(fromZone:getPoint(true), fromZone.hotStart) -- last true = hot  
	fromWP.alt_type = "RADIO" -- AGL instead of MSL
	theHUnit.alt = fromWP.alt
	-- WP2: signal that we are 1km away so source can be freed from flight 
	local dir = dcsCommon.bearingFromAtoB(A, B) -- x0z coords
	local omw = dcsCommon.pointInDirectionOfPointXYY(dir, 1000, A)
	omwWP = dcsCommon.createSimpleRoutePointData(omw, civHelo.alt, civHelo.speed)
	omwWP.alt_type = "RADIO"
	-- create a command waypoint
	local task = {}
	task.id = "ComboTask"
	task.params = {}
	local ttsk = {} 
	local command = "civHelo.departedCB('" .. name .. "', '" .. fromZone:getName() .. "')"
	ttsk[1] = civHelo.createCommandTask(command,1)
	task.params.tasks = ttsk
	omwWP.task = task 	

	-- now set up destination point: land
	-- at destination and add a small script 
	local toWP 
	-- add destination WP. this is common to both 
	toWP = dcsCommon.createSimpleRoutePointData(toZone:getPoint(), civHelo.alt, civHelo.speed)
	toWP.alt_type = "RADIO"

	local task = {}
	task.id = "ComboTask"
	task.params = {}
	local ttsk = {} 
	local p = toZone:getPoint()
	ttsk[1] = civHelo.createLandTask(p, civHelo.landingDuration, 1)
	local command = "civHelo.landedCB('" .. name .. "', '" .. toZone:getName() .. "')"
	ttsk[2] = civHelo.createCommandTask(command,2)
	task.params.tasks = ttsk
	toWP.task = task 	
	
	-- move group to WP1 and add WP1 and WP2 to route 
	dcsCommon.moveGroupDataTo(theGroup, 
							  fromWP.x, 
							  fromWP.y)
	dcsCommon.addRoutePointForGroupData(theGroup, fromWP)
	if not inAir then 
		dcsCommon.addRoutePointForGroupData(theGroup, omwWP)
	end
	dcsCommon.addRoutePointForGroupData(theGroup, toWP)
	
	-- spawn 
	local groupCat = Group.Category.HELICOPTER
	local theSpawnedGroup = coalition.addGroup(civHelo.owner, groupCat, theGroup)
	
	return theSpawnedGroup	
end 

function civHelo.openPort(where)
	local thePort = civHelo.getPortNamed(where)
	if thePort then 
		thePort.inUse = nil 
	end
	if civHelo.verbose then trigger.action.outText("+++civH: opening port <" .. where .. ">", 30) end 
end 

function civHelo.openPortUsedBy(name)
	for idx, theZone in pairs(civHelo.ports) do 
		if theZone.inUse == name then 
			theZone.inUse = nil 
			if civHelo.verbose then 
				trigger.action.outText("+++civH: clearing port <" .. theZone.name .. "> from flight <" .. name .. ">", 30)
			end 
		end 
	end
end

function civHelo.departedCB(who, where)
	-- free the port that we just took off from
	civHelo.openPort(where)
end

function civHelo.landedCB(who, where)
	-- step 1: remove the flight
	local theGroup = Group.getByName(who)
	if theGroup then 
		if Group.isExist(theGroup) then 
			Group.destroy(theGroup)
		end 
	else 
		trigger.action.outText("+++civH: cannot find group <" .. who .. ">", 30)
	end 
	civHelo.flights[who] = nil 
	
	-- step 2: schedule opening the port
	-- do it immediately first 
	civHelo.openPort(where)
end

--
-- new flight
--
function civHelo.getType(theZone)
	local types = civHelo.types -- load default 
	if theZone.types then types = theZone.types end 
	local hType = dcsCommon.pickRandom(types)
	return hType
end

function civHelo.getLiveryForType(theType, theData)
	if civHelo.liveries[theType] then 
		local available = civHelo.liveries[theType]
		local chosen = dcsCommon.pickRandom(available)		
		theData.livery_id = chosen
	end
end

function civHelo.newFlight()
	local source, dest = civHelo.getSourceAndDest()
	if source and dest then 
		-- source and dest "inUse" already have been marked inUse 
		-- but still need the name of the flight 
		local theType = civHelo.getType(source)
		local name = source:getName() .. "-" .. dest:getName()
		local theFlight = civHelo.createFlight(name, theType, source, dest)
		if theFlight then 
			civHelo.flights[name] = theFlight 
			source.inUse = name 
			dest.inUse = name 
			if civHelo.verbose then 
				trigger.action.outText("+++civH: created new flight <" .. name .. ">", 30)
			end
		else 
			trigger.action.outText("+++civH: cant create flight <" .. name .. ">", 30)
			source.inUse = nil 
			dest.inUse = nil 
		end
	else 
		if civHelo.verbose then 
			trigger.action.outText("+++civH: no ports available, can't create new flight. Numflights = <" .. dcsCommon.getSizeOfTable(civHelo.flights) .. ">", 30)
		end 
	end 
end

--
-- event handler 
--
function civHelo:onEvent(theEvent) 
--	trigger.action.outText("event", 30)
	if not theEvent.initiator then return end 
	local theUnit = theEvent.initiator 
	if not theUnit.getGroup then return end 
	local theGroup = theUnit:getGroup() 
	if not theGroup then return end 
	local gName = theGroup:getName()
	
	-- see if it's an event for one of mine 
	local mine = false 
	for name, aGroup in pairs(civHelo.flights) do 
		if name == gName then mine = true end
	end
	if not mine then 
		return 
	end 
	
	local id = theEvent.id 
	if id == 9 or -- pilot dead 
	   id == 30 or -- unit lost 
	   id == 5 -- crash 
	then  
		if civHelo.verbose then 
			trigger.action.outText("+++civH: cancelling flight <" .. gName .. ">: mishap", 30)
		end 
		civHelo.openPortUsedBy(gName)
		civHelo.flights[gName] = nil 
	end 
end

--
-- update
--
function civHelo.update()
	-- schedule again 
	timer.scheduleFunction(civHelo.update, {}, timer.getTime() + 1/civHelo.ups )
	
	-- see how many flights are live 
	if dcsCommon.getSizeOfTable(civHelo.flights) < civHelo.maxFlights then
		civHelo.newFlight()
	end
end

--
-- Config 
--
function civHelo.addTypesAndLiveries(rawIn)
	local newTypes = {}
	local newLiveries = {}
	-- now iterate the input table, and generate new types and 
	-- liveries from it 
	for theType, liveries in pairs (rawIn) do 
		if civHelo.verbose then 
			trigger.action.outText("+++civH: processing type <" .. theType .. ">:<" .. liveries .. ">", 30)
		end
		local livA = dcsCommon.splitString(liveries, ',')
		livA = dcsCommon.trimArray(livA)
		table.insert(newTypes, theType)
		newLiveries[theType] = livA
	end
	
	return newTypes, newLiveries
end

function civHelo.readConfigZone()
	local theZone = cfxZones.getZoneByName("civHeloConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("civHeloConfig") 
	end 
	civHelo.verbose = theZone.verbose 
	civHelo.owner = theZone:getNumberFromZoneProperty("country", 82) --82 -- UN peacekeepers
	civHelo.ups = theZone:getNumberFromZoneProperty("ups", 1 / 30)  
	civHelo.maxFlights = theZone:getNumberFromZoneProperty("maxFlights", 5)
	civHelo.landingDuration = theZone:getNumberFromZoneProperty("landingDuration", 180) -- seconds = 3 minutes
	civHelo.alt = theZone:getNumberFromZoneProperty("alt", 100) -- 100 m
	civHelo.speed = theZone:getNumberFromZoneProperty("speed", 30)
	civHelo.maxDist = theZone:getNumberFromZoneProperty("maxDist", 60000)
	civHelo.minDist = theZone:getNumberFromZoneProperty("minDist", 1000)
	if theZone:hasProperty("types") then 
		local hTypes = theZone:getStringFromZoneProperty("types", "xxx")
		local typeArray = dcsCommon.splitString(hTypes, ",")
		typeArray = dcsCommon.trimArray(typeArray)
		civHelo.types = typeArray
	end 
	
	-- now get types and liveries from 'helo_liveries' if present
	local livZone = cfxZones.getZoneByName("helo_liveries") 
	if livZone then 
		if civHelo.verbose then 
			trigger.action.outText("civH: found and processing 'helo_liveries' zone data.", 30)
		end 
		
		-- read all into my types registry, replacing whatever is there
		local rawLiver = cfxZones.getAllZoneProperties(livZone)
		local newTypes, newLiveries = civAir.addTypesAndLiveries(rawLiver)
		-- now types to existing types if not already there 
		for idx, aType in pairs(newTypes) do 
			dcsCommon.addToTableIfNew(civHelo.types, aType)
			if civHelo.verbose then 
				trigger.action.outText("+++civH: processed and added helo <" .. aType .. "> to civHelo", 30)
			end
		end
		-- now replace liveries or add if not already there 
		for aType, liveries in pairs(newLiveries) do 
			civHelo.liveries[aType] = liveries
			if civHelo.verbose then 
				trigger.action.outText("+++civH: replaced/added liveries for helicopter <" .. aType .. ">", 30)
			end
		end 
	end  	
end

--
-- start 
--
function civHelo.start()
-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx civ helo requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx civ helo", civHelo.requiredLibs) then
		return false 
	end
	
	-- read config 
	civHelo.readConfigZone()
	
	-- process civHelo Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("civHelo")
	for k, aZone in pairs(attrZones) do 
		civHelo.readCivHeloZone(aZone) -- process attributes
		civHelo.addCivHeloZone(aZone) -- add to list
	end
	
	-- start update in 5 seconds
	timer.scheduleFunction(civHelo.update, {}, timer.getTime() + 5)
	
	-- install event handler 
	world.addEventHandler(civHelo)
	
	-- say hi 
	trigger.action.outText("civHelo v" .. civHelo.version .. " started.", 30)
	return true 
end

if not civHelo.start() then 
	trigger.action.outText("civHelo failed to start.")
	civHelo = nil 
end 

