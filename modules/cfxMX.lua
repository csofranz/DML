cfxMX = {}
cfxMX.version = "3.0.1"
cfxMX.verbose = false 
--[[--
 Mission data decoder. Access to ME-built mission structures
 
 Copyright (c) 2022, 2023 by Christian Franz and cf/x AG
 
 Version History
   1.2.6 - cfxMX.allTrainsByName
		 - train carve-outs for vehicles
   2.0.0 - clean-up 
         - harmonized with cfxGroups 
   2.0.1 - groupHotByName
   2.0.2 - partOfGroupDataInZone(), allGroupsInZoneByData() from milHelo
   2.0.3 - allGroupsInZoneByData supports type filtering 
   2.1.0 - support for dynamically spawning player unit detection 
		 - new isDynamicPlayer()
		 - new isMEPlayer() 
		 - new isMEPlayerGroup()
   2.2.0 - new groupCatByName[]
   3.0.0 - patch coalition.addGroup() to build unit table for wasUnit
         - pre-populate spawnedUnits coa, cat from MX 
		 - spawnedUnitGroupNameByName
   3.0.1 - new getClosestUnitToPoint()
   4.0.0 - support for DCS persistence API (start)
   
--]]--

cfxMX.spawnedUnitCoaByName = {} -- reverse lookup for coas to reconstruct after kill
cfxMX.spawnedUnitCatByName = {} -- reverse lookup for cat to recon after kill 
cfxMX.spawnedUnitGroupNameByName = {}

cfxMX.groupNamesByID = {}
cfxMX.groupIDbyName = {}
cfxMX.unitIDbyName = {}
cfxMX.groupCatByName = {}
cfxMX.groupDataByName = {} -- includes static groups!
cfxMX.groupTypeByName = {} -- category of group: "helicopter", "plane", "ship"...
cfxMX.groupCoalitionByName = {}
cfxMX.groupHotByName = {}
cfxMX.countryByName ={} -- county of group named 
cfxMX.linkByName = {}
cfxMX.allFixedByName = {}
cfxMX.allHeloByName = {}
cfxMX.allGroundByName = {}
cfxMX.allSeaByName = {}
cfxMX.allStaticByName = {}
cfxMX.allTrainsByName = {}

cfxMX.playerGroupByName = {} -- returns data only if a player is in group 
cfxMX.playerUnitByName = {} -- returns data only if this is a player unit 
cfxMX.playerUnit2Group = {} -- returns a group data for player units.

cfxMX.groups = {} -- all groups indexed by name, cfxGroups folded into cfxMX 

--[[-- group objects are 
{
	name= "", 
	coalition = "" (red, blue, neutral), 
	coanum = # (0, 1, 2 for neutral, red, blue)
	category = "" (helicopter, ship, plane, vehicle, static),
	hasPlayer = true/false,
	playerUnits = {} (for each player unit in group: name, point, action)
}
--]]--
function cfxMX.getGroupFromDCSbyName(aName, fetchOriginal)
	if not fetchOriginal then fetchOriginal = false end 
		
	for coa_name_miz, coa_data in pairs(env.mission.coalition) do -- iterate all coalitions
		local coa_name = coa_name_miz
		if string.lower(coa_name_miz) == 'neutrals' then -- remove 's' at neutralS
			coa_name = 'neutral'
		end
		-- directly convert coalition into number for easier access later
		local coaNum = 0
		if coa_name == "red" then coaNum = 1 end 
		if coa_name == "blue" then coaNum = 2 end 
		
		if type(coa_data) == 'table' then -- coalition = {bullseye, nav_points, name, county}, 
										  -- with county being an array 
			if coa_data.country then -- make sure there a country table for this coalition
				for cntry_id, cntry_data in pairs(coa_data.country) do -- iterate all countries for this 
					-- per country = {id, name, vehicle, helicopter, plane, ship, static}
					local countryName = string.lower(cntry_data.name)
					local countryID = cntry_data.id 
					if type(cntry_data) == 'table' then	-- filter strings .id and .name 
						for obj_type_name, obj_type_data in pairs(cntry_data) do
							if obj_type_name == "helicopter" or 
							   obj_type_name == "ship" or 
							   obj_type_name == "plane" or 
							   obj_type_name == "vehicle" or 
							   obj_type_name == "static" 
							   -- note: trains are 'vehicle' here
							then -- (so it's not id or name)
								local category = obj_type_name
								if ((type(obj_type_data) == 'table') and obj_type_data.group and (type(obj_type_data.group) == 'table') and (#obj_type_data.group > 0)) then	--there's at least one group!
									for group_num, group_data in pairs(obj_type_data.group) do
										if group_data.name == aName then 
											local theGroup = group_data
											-- usually we return a copy of this 
											if not fetchOriginal then 
												theGroup = dcsCommon.clone(group_data)
											end
											-- train carve-out: if first unit's type == "Train", change
											-- category to "train"
											if group_data.units[1] and group_data.units[1].type == "Train" then category = "train" end 
											return theGroup, category, countryID  
										end
									end
								end --if has category data 
							end --if plane, helo etc... category
						end --for all objects in country 
					end --if has country data 
				end --for all countries in coalition
			end --if coalition has country table 
		end -- if there is coalition data  
	end --for all coalitions in mission 
	return nil, "none", "none"
end

function cfxMX.getStaticFromDCSbyName(aName, fetchOriginal)
	if not fetchOriginal then fetchOriginal = false end 
	-- fetch the static description for static named aName (if exists)
	-- returned structure must be parsed for useful information 
	-- returns data, category, countyID and parent group name 
	-- unless fetchOriginal is true, creates a deep clone of 
	-- static data structure 
		
	for coa_name_miz, coa_data in pairs(env.mission.coalition) do -- iterate all coalitions
		local coa_name = coa_name_miz
		if string.lower(coa_name_miz) == 'neutrals' then -- remove 's' at neutralS
			coa_name = 'neutral'
		end
		-- directly convert coalition into number for easier access later
		local coaNum = 0
		if coa_name == "red" then coaNum = 1 end 
		if coa_name == "blue" then coaNum = 2 end 
		
		if type(coa_data) == 'table' then -- coalition = {bullseye, nav_points, name, county}, 
										  -- with county being an array 
			if coa_data.country then -- make sure there a country table for this coalition
				for cntry_id, cntry_data in pairs(coa_data.country) do -- iterate all countries for this 
					-- per country = {id, name, vehicle, helicopter, plane, ship, static}
					local countryName = string.lower(cntry_data.name)
					local countryID = cntry_data.id 
					if type(cntry_data) == 'table' then	-- filter strings .id and .name 
						for obj_type_name, obj_type_data in pairs(cntry_data) do
							if obj_type_name == "static"
							then -- (only look at statics)
								local category = obj_type_name
								if ((type(obj_type_data) == 'table') and obj_type_data.group and (type(obj_type_data.group) == 'table') and (#obj_type_data.group > 0)) then	--there's at least one static in group!
									for group_num, group_data in pairs(obj_type_data.group) do
										-- get linkUnit info if it exists
										local linkUnit = nil 
										if group_data and group_data.route and group_data.route and group_data.route.points[1] then 
											linkUnit = group_data.route.points[1].linkUnit
											if linkUnit then 

											end 
										end 
										
										if group_data and group_data.units and type(group_data.units) == 'table' 
										then --make sure - again - that this is a valid group
											for unit_num, unit_data in pairs(group_data.units) do -- iterate units
												if unit_data.name == aName then 
													local groupName = group_data.name
													local theStatic = unit_data
													if not fetchOriginal then 
														theStatic = dcsCommon.clone(unit_data)
														-- copy group ID from group above
														theStatic.groupId = group_data.groupId  
														-- copy linked unit data 
														theStatic.linkUnit = linkUnit
													end
													return theStatic, category, countryID, groupName  
												end -- if name match
											end -- for all units 
										end -- has groups 
									end -- is a static 
								end --if has category data 
							end --if plane, helo etc... category
						end --for all objects in country 
					end --if has country data 
				end --for all countries in coalition
			end --if coalition has country table 
		end -- if there is coalition data  
	end --for all coalitions in mission 
	return nil, "<none>", "<none>", "<no group name>"
end

function cfxMX.createCrossReferences()
	for coa_name_miz, coa_data in pairs(env.mission.coalition) do -- iterate all coalitions
		local coa_name = coa_name_miz
		if string.lower(coa_name_miz) == 'neutrals' then -- remove 's' at neutralS
			coa_name = 'neutral'
		end
		-- directly convert coalition into number for easier access later
		local coaNum = 0
		if coa_name == "red" then coaNum = 1 end 
		if coa_name == "blue" then coaNum = 2 end 
		
		if type(coa_data) == 'table' then -- coalition = {bullseye, nav_points, name, county}, 
										  -- with county being an array 
			if coa_data.country then -- make sure there a country table for this coalition
				for cntry_id, cntry_data in pairs(coa_data.country) do -- iterate all countries for this 
					-- per country = {id, name, vehicle, helicopter, plane, ship, static}
					local countryName = string.lower(cntry_data.name)
					local countryID = cntry_data.id 
					if type(cntry_data) == 'table' then	-- filter strings .id and .name 
						for obj_type_name, obj_type_data in pairs(cntry_data) do
							local gCat = -1 -- "illegal" 
							if obj_type_name == "helicopter" then gCat = 1  
							elseif obj_type_name == "ship" then gCat = 3  
							elseif obj_type_name == "plane" then gCat = 0 
							elseif obj_type_name == "vehicle" then gCat = 2
							else -- if obj_type_name == "static" -- what about "cargo"?
								gCat = -1 -- just for safety. no cat for static, train, cargo
							end 
							
							if obj_type_name == "helicopter" or 
							   obj_type_name == "ship" or 
							   obj_type_name == "plane" or 
							   obj_type_name == "vehicle" or 
							   obj_type_name == "static" -- what about "cargo"?
							   -- note that trains appear as 'vehicle'
							then -- (so it's not id or name)
								local category = obj_type_name
								if ((type(obj_type_data) == 'table') and obj_type_data.group and (type(obj_type_data.group) == 'table') and (#obj_type_data.group > 0)) then	--there's at least one group!
									for group_num, group_data in pairs(obj_type_data.group) do
										
										local aName = group_data.name 
										local aID = group_data.groupId
										-- get linkUnit info if it exists
										local linkUnit = nil 
										local isHot = false 
										if group_data and group_data.route and group_data.route and group_data.route.points[1] then 
											linkUnit = group_data.route.points[1].linkUnit
											cfxMX.linkByName[aName] = linkUnit
											local action = group_data.route.points[1].action
											if action then 
												isHot = dcsCommon.stringEndsWith(action, "Hot")
											end 
										end 
										
										cfxMX.groupHotByName[aName] = isHot
										if group_data.units[1] and group_data.units[1].type == "Train" then 
											category = "train" 
											obj_type_name = "train"
										end 
										cfxMX.groupTypeByName[aName] = category
										cfxMX.groupNamesByID[aID] = aName
										cfxMX.groupIDbyName[aName] = aID
										cfxMX.groupDataByName[aName] = group_data
										cfxMX.countryByName[aName] = countryID -- !!! was cntry_id
										cfxMX.groupCoalitionByName[aName] = coaNum

										-- now make the type-specific xrefs
										if obj_type_name == "helicopter" then 
											cfxMX.allHeloByName[aName] = group_data 
											cfxMX.groupCatByName[aName] = 1
										elseif obj_type_name == "ship" then 
											cfxMX.allSeaByName[aName] = group_data
											cfxMX.groupCatByName[aName] = 3
										elseif obj_type_name == "plane" then 
											cfxMX.allFixedByName[aName] = group_data
											cfxMX.groupCatByName[aName] = 0
										elseif obj_type_name == "vehicle" then 
											cfxMX.allGroundByName[aName] = group_data
											cfxMX.groupCatByName[aName] = 2
										elseif obj_type_name == "static" then 
											cfxMX.allStaticByName[aName] = group_data
--											cfxMX.groupCatByName[aName] = -1 -- not covered
										elseif obj_type_name == "train" then 
											cfxMX.allTrainsByName[aName] = group_data
											cfxMX.groupCatByName[aName] = 4
										else 
											-- should be impossible, but still
											trigger.action.outText("+++MX: <" .. obj_type_name .. "> unknown type for <" .. aName .. ">", 30)
										end
										-- now iterate all units in this group 
										-- for unit xref like player info and ID
										local hasPlayer = false 
										local playerUnits = {}
										local groupName = group_data.name
										if env.mission.version > 7 then -- translate raw to actual 
											groupName = env.getValueDictByKey(groupName)
										end
										for unit_num, unit_data in pairs(group_data.units) do
											if unit_data.skill then 
												if unit_data.skill == "Client" or  unit_data.skill == "Player" then
													-- player unit 
													cfxMX.playerUnitByName[unit_data.name] = unit_data
													cfxMX.playerGroupByName[aName] = group_data -- inefficient, but works
													cfxMX.playerUnit2Group[unit_data.name] = group_data
													
													hasPlayer = true 
													local playerData = {}
													playerData.name = unit_data.name
													playerData.point = {}
													playerData.point.x = unit_data.x
													playerData.point.y = 0
													playerData.point.z = unit_data.y
													playerData.action = "none" -- default 
													
													-- access initial waypoint data by 'reaching up'
													-- into group data and extract route.points[1]
													if group_data.route and group_data.route.points and (#group_data.route.points > 0) then 
														playerData.action = group_data.route.points[1].action
													end
													table.insert(playerUnits, playerData)
													
												end -- if unit skill client
											end -- if has skill
											cfxMX.unitIDbyName[unit_data.name] = unit_data.unitId 
											
											if gCat >= 0 then -- pre-populate table 
												cfxMX.spawnedUnitCoaByName[unit_data.name] = coaNum 
												cfxMX.spawnedUnitCatByName[unit_data.name] = gCat
											end
											cfxMX.spawnedUnitGroupNameByName[unit_data.name] = groupName
										end -- for all units
										
										local entry = {}
										entry.name = groupName
										entry.coalition = coa_name
										entry.coaNum = coaNum 
										entry.category  = category
										entry.hasPlayer = hasPlayer 
										entry.playerUnits = playerUnits
										-- add to db
										cfxMX.groups[groupName] = entry
											
									end -- for all groups 
								end --if has category data 
							end --if plane, helo etc... category
						end --for all objects in country 
					end --if has country data 
				end --for all countries in coalition
			end --if coalition has country table 
		end -- if there is coalition data  
	end --for all coalitions in mission 
end


-- return all groups that can have players in them
-- includes groups that currently are not or not anymore alive
function cfxMX.getPlayerGroup()
	local playerGroups = {}
	for gName, gData in pairs (cfxMX.groups) do 
		if gData.hasPlayer then
			table.insert(playerGroups, gData)
		end
	end
	return playerGroups 
end

-- return all group names that can have players in them
-- includes groups that currently are not or not anymore alive
function cfxMX.getPlayerGroupNames()
	local playerGroups = {}
	for gName, gData in pairs (cfxMX.groups) do 
		if gData.hasPlayer then
			table.insert(playerGroups, gName)
		end
	end
	return playerGroups 
end

function cfxMX.catText2ID(inText) 
	local outCat = 0 -- airplane 
	local c = inText:lower()
	if c == "helicopter" then outCat = 1 end 
	if c == "ship" then outCat = 3 end 
	if c == "plane" then outCat = 0 end -- redundant 
	if c == "vehicle" then outCat = 2 end 
	if c == "train" then outCat = 4 end 
	if c == "static" then outCat = -1 end 

	return outCat
end

function cfxMX.partOfGroupDataInZone(theZone, theUnits) -- move to mx?
	--local zP --= cfxZones.getPoint(theZone)
	local zP = theZone:getDCSOrigin() -- don't use getPoint now.
	zP.y = 0
	
	for idx, aUnit in pairs(theUnits) do 
		local uP = {}
		uP.x = aUnit.x 
		uP.y = 0
		uP.z = aUnit.y -- !! y-z
		if theZone:pointInZone(uP) then return true end 
	end 
	return false 
end

function cfxMX.allGroupsInZoneByData(theZone, cat) -- returns groups indexed by name and count 
	if not cat then cat = {"helicopter", "ship", "plane", "vehicle" } end 
	if type(cat) == "string" then cat = {cat} end 
	local theGroupsInZone = {}
	local count = 0
	for groupName, groupData in pairs(cfxMX.groupDataByName) do 
		local gType = cfxMX.groupTypeByName[groupName]
		if dcsCommon.arrayContainsString(cat, gType) and groupData.units then 
			if cfxMX.partOfGroupDataInZone(theZone, groupData.units) then 
				theGroupsInZone[groupName] = groupData -- DATA! work on clones!
				count = count + 1 
				if theZone.verbose then 
					trigger.action.outText("+++cfxMX: added group <" .. groupName .. "> for zone <" .. theZone.name .. ">", 30)
				end 
			end
		end
	end
	return theGroupsInZone, count 
end

function cfxMX.getClosestUnitToPoint(A, filter) -- uses MX!
	if not A then return nil end 
	if not filter then filter = "all" end 
	local theUnit = nil
	local uIdx = nil 
	local theGroup = nil 
	local ax = A.x 
	local az = A.z 
	local closest = math.huge 
	for name, gData in pairs(cfxMX.groupDataByName) do 
		if filter == "all" or filter == cfxMX.groupTypeByName[name] then 
			for idx, uData in pairs(gData.units) do 
				-- use square delta, immediate 
				local dx = ax - uData.x
				local dz = az - uData.y -- !!
				local d = dx * dx + dz * dz 
				if d < closest then 
					theUnit = uData
					theGroup = gData
					closest = d 
					uIdx = idx 
				end 
			end 
		end
	end
	return theUnit, theGroup, uIdx, closest^0.5 
end

function cfxMX.isDynamicPlayer(theUnit)
	if not theUnit then return false end 
	if not theUnit.getName then return false end 
	if not theUnit.getPlayerName then return false end 
	if not theUnit:getPlayerName() then return false end 
	local uName = theUnit:getName()
	if cfxMX.playerUnitByName[uName] then return false end 
	return true 
end

function cfxMX.isMEPlayer(theUnit) 
	if not theUnit then return false end 
	if not theUnit.getName then return false end 
	if not theUnit.getPlayerName then return false end 
	if not theUnit:getPlayerName() then return false end 
	local uName = theUnit:getName()
	if cfxMX.playerUnitByName[uName] then return true end 
	return false 
end

function cfxMX.isMEPlayerGroup(theUnit) 
	if not theUnit then return false end 
	if not theUnit.getName then return end 
	if not theUnit.getPlayerName then return end 
	local uName = theUnit:getName()
	if cfxMX.playerUnitByName[uName] then return true end 
	return false 
end

function cfxMX.start()
	cfxMX.createCrossReferences()
	if cfxMX.verbose then 
		trigger.action.outText("cfxMX: "..#cfxMX.groupNamesByID .. " groups processed successfully", 30)
	end
	trigger.action.outText("cfxMX v." .. cfxMX.version .. " started.", 30)
end

--
-- patch coalition.addGroup so we can record all units by name for their coalition
--
coalition.mxAddGroup = coalition.addGroup -- save old 

function coalition.addGroup(cty, cat, data) -- patch addGroup to note all spawned units for DCS static switch-a-roo 
    local g = coalition.mxAddGroup(cty, cat, data)
    if not g then return nil end
	local coa = coalition.getCountryCoalition(cty)
	local units = g:getUnits()
	local gName = g:getName() 
	for idx, u in pairs(units) do 
		uName = u:getName()
		cfxMX.spawnedUnitCoaByName[uName] = coa
		cfxMX.spawnedUnitCatByName[uName] = cat
		cfxMX.spawnedUnitGroupNameByName[uName] = gName 
--		trigger.action.outText("MX: Unit <" .. uName .. "> spawned for coa <" .. coa .. ">", 30)
	end 
    return g
end

-- start 
cfxMX.start()

