csarFX = {}
csarFX.version = "2.0.5"

--[[--
VERSION HISTORY 
 2.0.5 Initial Version 

csarFX - makes better SAR and can turn SAR into CSAR 
Copyright (c) 2024-2025 by Christian Franz 
 
WARNING: 
csarFX must run AFTER csarManager to install its callbacks, so
any csar mission that runs earlier does NOT receive any csarFX adornments

--]]--

csarFX.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course
	"csarManager", 
}
-- static object type strings to add as debris csar missions placed on a road
csarFX.roadDebbies = {"VAZ Car", "IKARUS Bus", "LAZ Bus", "LiAZ Bus", "GAZ-3307", "ZIL-131 KUNG", "MAZ-6303", "ZIL-4331", "Ural-375", "GAZ-3307"
, "ZIL-131 KUNG", "MAZ-6303", "ZIL-4331", "Ural-375", "GAZ-3307",
"VAZ Car",
-- Massun's stuff 
"P20_01", "TugHarlan", "r11_volvo_drivable", }
csarFX.landDebbies = {"Hummer", }
csarFX.seaDebbies = {"speedboat","ZWEZDNY", "speedboat", --2x prob speed 
}
csarFX.seaSpecials = {"Orca",}

--[[--
theMission Data Structure:
- zone: a trigger zone. 	
- locations : {} array of locations for units in zone 
- name - mission name 
- group - all evacuees 
- side: coalition 
- missionID - id 
- timeStamp - when it was created 
- inPopulated - passed by csarManager zone creation 
--]]--

function csarFX.addRoadDebris(theMission, center) -- in vec2
	local cty = dcsCommon.getACountryForCoalition(0)
	local theStatic, x, z = dcsCommon.createStaticObjectForCoalitionInRandomRing(cty, dcsCommon.pickRandom(csarFX.roadDebbies), center.x, center.y, 5, 7, nil, true) 
	table.insert(theMission.debris, theStatic)
	if math.random(1000) > 500 then 
		-- two-car crash, high probability for fire
		local otherStatic =  dcsCommon.createStaticObjectForCoalitionInRandomRing(cty, dcsCommon.pickRandom(csarFX.roadDebbies), x, z, 2, 4, nil, true)
		table.insert(theMission.debris, otherStatic)
		if math.random(1000) > 400 then 
			local smokeType = 1 
			if math.random(1000) > 500 then smokeType = 5 end
			local smokePoint = {x=x, y=land.getHeight({x=x, y=z}), z=z}
			trigger.action.effectSmokeBig(smokePoint, smokeType , 0.1 , theMission.name)
			table.insert(theMission.fires, theMission.name)
		end 
	else
		if math.random(1000) > 800 then 
			local smokeType = 1 
			if math.random(1000) > 500 then smokeType = 5 end 
			local smokePoint = {x=x, y=land.getHeight({x=x, y=z}), z=z}
			trigger.action.effectSmokeBig(smokePoint , smokeType , 0.1 , theMission.name)
			table.insert(theMission.fires, theMission.name)
		end 
	end 
end

function csarFX.addWaterDebris(theMission, center) -- in vec2
	local cty = dcsCommon.getACountryForCoalition(0)
	if math.random(1000) > 500 then  -- 50% chance 
		local theStatic, x, z = dcsCommon.createStaticObjectForCoalitionInRandomRing(cty, dcsCommon.pickRandom(csarFX.seaDebbies), center.x, center.y, 100, 200, nil, true) 
		table.insert(theMission.debris, theStatic)
	end 
	-- add an orca (very rare)
	if math.random(1000) < 10 then -- 1% chance for water
		local theStatic, x, z = dcsCommon.createStaticObjectForCoalitionInRandomRing(cty, dcsCommon.pickRandom(csarFX.seaSpecials), center.x, center.y, 30, 50, nil, true) 
		table.insert(theMission.debris, theStatic)
	end 
end

function csarFX.localDebris(debris, center, dist, theZone, theMission)
	local cty = dcsCommon.getACountryForCoalition(theZone.csarSide)
	local theStatic, x, z = dcsCommon.createStaticObjectForCoalitionInRandomRing(cty, dcsCommon.pickRandom(debris), center.x, center.y, dist, 2*dist, nil, false) -- zed is ded 
	table.insert(theMission.debris, theStatic)
	
	local smokeType = 1 
	if math.random(1000) > 500 then smokeType = 5 end 
	local smokePoint = {x=x, y=land.getHeight({x=x, y=z}), z=z}
	trigger.action.effectSmokeBig(smokePoint, smokeType, 0.1 , theMission.name)
	table.insert(theMission.fires, theMission.name)
end 

function csarFX.addLandDebris(theMission, center) -- in vec2
	local cty = dcsCommon.getACountryForCoalition(0)
	if math.random(1000) > 500 then  -- 50% chance 
		local theStatic, x, z = dcsCommon.createStaticObjectForCoalitionInRandomRing(cty, dcsCommon.pickRandom(csarFX.landDebbies), center.x, center.y, 10, 15, nil, false) -- zed is ded 
		table.insert(theMission.debris, theStatic)
		
		if math.random(1000) > 500 then 
			local smokeType = 1 
			if math.random(1000) > 500 then smokeType = 5 end 
			local smokePoint = {x=x, y=land.getHeight({x=x, y=z}), z=z}
			trigger.action.effectSmokeBig(smokePoint, smokeType, 0.1 , theMission.name)
			table.insert(theMission.fires, theMission.name)
		end 
	end 
end

function csarFX.addPopulatedDebris(theMission, center)
	if math.random(1000) > 500 then 
		local rp = dcsCommon.randomPointOnPerimeter(5, center.x, center.z) 
		local smokeType = 1 
		if math.random(1000) > 500 then smokeType = 5 end 
		local smokePoint = {x=rp.x, y=land.getHeight({x=rp.x, y=rp.z}), z=rp.z}
		trigger.action.effectSmokeBig(smokePoint, smokeType, 0.1 , theMission.name)
		table.insert(theMission.fires, theMission.name)
	end 
end
--
-- mission created callback
--
function csarFX.missionCreatedCB(theMission, theZone)
	-- get location of first (usually only) evacuee
	local loc = {}
	loc.x = theMission.locations[1].x 
	loc.y = 0 
	loc.z = theMission.locations[1].z 
	
	loc.y = loc.z -- loc is now vec2!
	theMission.debris = {}
	theMission.fires = {}
	theMission.enemies = {}
	theMission.enemyNames = {}
	if theZone then 
		if theZone.enemies then 			
			-- generate enemies 
			local coa = dcsCommon.getEnemyCoalitionFor(theZone.csarSide)
			local cty = dcsCommon.getACountryForCoalition(coa)
			local numEnemies = dcsCommon.randomBetween(theZone.emin, theZone.emax)
			for i=1, numEnemies do 			
				local gName = dcsCommon.uuid("cesar")
				local gData = dcsCommon.createEmptyGroundGroupData (gName)
				local theType = dcsCommon.pickRandom(theZone.enemies)
				local range = dcsCommon.randomBetween(theZone.rmin, theZone.rmax)
				local p = dcsCommon.randomPointOnPerimeter(range, 0, 0)local uData = dcsCommon.createGroundUnitData(gName .. "-e", theType, false)
				local heading = math.random(360) * 0.0174533
				dcsCommon.addUnitToGroupData(uData, gData, 0, 0, heading)
				dcsCommon.moveGroupDataTo(gData, loc.x + p.x, loc.z + p.z)
				local theEnemies = coalition.addGroup(cty, Group.Category.GROUND, gData)
				if theEnemies then 
					table.insert(theMission.enemies, theEnemies) 
					local gNameS = theEnemies:getName()
					table.insert(theMission.enemyNames, gNameS)	
				end 
			end
			-- add a nasty if defined 
			if theZone.nasties then 
				local gName = dcsCommon.uuid("cesar-n")
				local gData = dcsCommon.createEmptyGroundGroupData (gName)
				local theType = dcsCommon.pickRandom(theZone.nasties)
				local range = dcsCommon.randomBetween(theZone.rmin, theZone.rmax)
				local p = dcsCommon.randomPointOnPerimeter(range, 0, 0)local uData = dcsCommon.createGroundUnitData(gName .. "-n", theType, false)
				local heading = math.random(360) * 0.0174533
				dcsCommon.addUnitToGroupData(uData, gData, 0, 0, heading)
				dcsCommon.moveGroupDataTo(gData, loc.x + p.x, loc.z + p.z)
				local theEnemies = coalition.addGroup(cty, Group.Category.GROUND, gData)
				if theEnemies then 
					table.insert(theMission.enemies, theEnemies) 
					local gNameS = theEnemies:getName()
					table.insert(theMission.enemyNames, gNameS)	
				end
			end
			-- generate debris
			if theZone.debris then -- theZone:hasProperty("debris") then 
				csarFX.localDebris(theZone.debris, loc, 1000, theZone, theMission)
			end 
			return -- no further adornments
		end
	end 
	-- see if this is a land or sea mission? 
	-- access first unit's location 	
	local landType = land.getSurfaceType(loc)
	-- init debris and fires for house cleaning
	if theMission.inPopulated then 
		-- theMission calls for in populated. create some marker 
		-- directly next to the guy 
		csarFX.addPopulatedDebris(theMission, loc)
	elseif landType == 3 then -- deep water
		csarFX.addWaterDebris(theMission, loc)
	elseif landType == 4 then -- road 
		csarFX.addRoadDebris(theMission, loc)
	else -- anywhere else. Includes shallow water 
		csarFX.addLandDebris(theMission, loc)
	end
end

function csarFX.makeEnemiesCongregate(theMission)
	if not theMission.enemies then return end 
	for idx, theEnemyName in pairs(theMission.enemyNames) do 
		local theEnemy = Group.getByName(theEnemyName)
		if theEnemy then 
			local loc = theMission.locations[1]
			if not loc then return end 
			local p = {}
			p.x = loc.x
			p.y = 0
			p.z = loc.z
			if Group.isExist(theEnemy) then 
				local here = dcsCommon.getGroupLocation(theEnemy, true, theEnemyName)
				if not here then 
					trigger.action.outText("+++csFx: no (here) for <" .. theEnemyName .. ">, skipping.", 30)
				else
					cfxCommander.makeGroupGoThere(theEnemy, p, 4, nil, 5) -- 5 m/s = 18 kmh, NIL FORMATION, 5 seconds in the future
				end 
			end 
		else -- enemy gone 
		end
	end 
end

function csarFX.smokeStartedCB(theMission, uName)
	if not csarFX.congregateOnSmoke then return end 
	-- start congregation of units 
	if theMission.enemies then 
		csarFX.makeEnemiesCongregate(theMission)
	end 
end
--
-- evacuee picked up callback 
--
function csarFX.PickUpCB(theMission)
end 
--
-- Mission completed callback
--
function csarFX.missionCompleteCB(theCoalition, success, numRescued, notes, theMission)
	if not success then 
		-- schedule cleanup in the future 
		timer.scheduleFunction(csarFX.doCleanUpMission, theMission, timer.getTime() + csarFX.cleanupDelay)
		return
	end 
	csarFX.doCleanUpMission(theMission) -- clean up now.
end
-- synch/asynch call for cleaning up after Mission
-- if mission isn't successful, we wait some time before
-- we remove smoke, debris, enemies 
function csarFX.doCleanUpMission(theMission)
	-- deallocate scenery fx 
	if theMission.debris then 
		for idx, theDeb in pairs(theMission.debris) do
			if theDeb and Object.isExist(theDeb) then 
				Object.destroy(theDeb)
			end 
		end 
	end 
	if theMission.fires then 
		for idx, theFlame in pairs(theMission.fires) do 
			trigger.action.effectSmokeStop(theFlame)
		end
	end 
	if theMission.enemies then 
		for idx, theGroup in pairs(theMission.enemies) do 
			if theGroup and Group.isExist(theGroup) then 
				Group.destroy(theGroup)
			end
		end
	end 
end
-- start and hook into csarManager
function csarFX.readConfig()
	local theZone = cfxZones.getZoneByName("csarFXConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("csarFXConfig") 
	end 	
	csarFX.verbose = theZone.verbose
	--csarFX.landDebris = theZone:getBoolFromZoneProperty("landDebris", true)
	--csarFX.seaDebris = theZone:getBoolFromZoneProperty("seaDebris", true)
	--csarFX.roadDebris = theZone:getBoolFromZoneProperty("roadDebris", true)
	csarFX.congregateOnSmoke = theZone:getBoolFromZoneProperty("congregate", true)
	csarFX.cleanupDelay = theZone:getNumberFromZoneProperty("cleanupDelay", 10 * 60)
	if theZone:hasProperty("landTypes") then 
		local hTypes = theZone:getStringFromZoneProperty("landTypes", "xxx")
		local typeArray = dcsCommon.splitString(hTypes, ",")
		typeArray = dcsCommon.trimArray(typeArray)
		csarFX.landDebbies = typeArray 
	end 
	if theZone:hasProperty("roadTypes") then 
		local hTypes = theZone:getStringFromZoneProperty("roadTypes", "xxx")
		local typeArray = dcsCommon.splitString(hTypes, ",")
		typeArray = dcsCommon.trimArray(typeArray)
		csarFX.roadDebbies = typeArray 
	end	
	if theZone:hasProperty("seaTypes") then 
		local hTypes = theZone:getStringFromZoneProperty("seaTypes", "xxx")
		local typeArray = dcsCommon.splitString(hTypes, ",")
		typeArray = dcsCommon.trimArray(typeArray)
		csarFX.seaDebbies = typeArray 
	end	
end 

function csarFX.amendCSARZones()
	-- process csar zones and amend the attributes 
	local csarBases = cfxZones.zonesWithProperty("CSAR")
	-- now add all zones to my zones table, and init additional info
	-- from properties
	for k, theZone in pairs(csarBases) do
		if theZone:hasProperty("enemies") then 
			local hTypes = theZone:getStringFromZoneProperty("enemies", "xxx")
			local typeArray = dcsCommon.splitString(hTypes, ",")
			typeArray = dcsCommon.trimArray(typeArray)
			theZone.enemies = typeArray 
		end
 		if theZone:hasProperty("nasties") then 
			local hTypes = theZone:getStringFromZoneProperty("nasties", "xxx")
			local typeArray = dcsCommon.splitString(hTypes, ",")
			typeArray = dcsCommon.trimArray(typeArray)
			theZone.nasties = typeArray 
		end
		local dmin, dmax = theZone:getPositiveRangeFromZoneProperty("range", 1) -- range of enemies 
		theZone.rmin = dmin * 1000 
		theZone.rmax = dmax * 1000
		local emin, emax = theZone:getPositiveRangeFromZoneProperty("strength", 1) -- number of enemies 
		theZone.emin = emin 
		theZone.emax = emax
		if theZone:hasProperty("debris") then 
			local hTypes = theZone:getStringFromZoneProperty("debris", "xxx")
			local typeArray = dcsCommon.splitString(hTypes, ",")
			typeArray = dcsCommon.trimArray(typeArray)
			theZone.debris = typeArray 
		end 
	end
end

function csarFX.start()
		if not dcsCommon.libCheck("cfx CSAR FX", csarFX.requiredLibs) then
		trigger.action.outText("cf/x CSAR FX aborted: missing libraries", 30)
		return
	end
	-- read config 
	csarFX.readConfig()
	-- amend csarZones 
	csarFX.amendCSARZones()
	-- install callbacks 
	csarManager.installNewMissionCallback(csarFX.missionCreatedCB)
	csarManager.installPickupCallback(csarFX.PickUpCB)
	csarManager.installCallback(csarFX.missionCompleteCB)
	csarManager.installSmokeCallback(csarFX.smokeStartedCB)
	trigger.action.outText("csarFX v" .. csarFX.version .. " started", 30)
end 

csarFX.start()

--[[--
	to do: integrate with autoCSAR so if a plane gets shot down over a CSAR zone, that zone is triggered, and csarFX gets invoked as well.
--]]--