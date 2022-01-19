cfxGroups = {}
cfxGroups.version = "1.1.0"
--[[--

Module to read Unit data from DCS and make it available to scripts
DOES NOT KEEP TRACK OF MISSION-CREATED GROUPS!!!!
Main use is to access player groups for slot blocking etc since these 
groups can't be allocated dynamically

Version history

 1.0.0 - initial version
 1.1.0 - for each player unit, store point(x, 0, y), and action for first WP, as well as name 
 
--]]--

cfxGroups.groups = {} -- all groups, indexed by name 

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

function cfxGroups.fetchAllGroupsFromDCS()
	-- a mission is a lua table that is loaded by executing the miz. it builds
	-- the environment mission table, accessible as env.mission 
	-- iterate the "coalition" table of the mission (note: NOT coalitionS)
    -- inspired by mist, GIANT tip o'the hat to Grimes!	
	
	for coa_name_miz, coa_data in pairs(env.mission.coalition) do -- iterate all coalitions
		local coa_name = coa_name_miz
		if string.lower(coa_name_miz) == 'neutrals' then -- convert "neutrals" to "neutral", singular
			coa_name = 'neutral'
		end
		-- directly convert coalition into number for easier access later
		local coaNum = 0
		if coa_name == "red" then coaNum = 1 end 
		if coa_name == "blue" then coaNum = 2 end 
		
		if type(coa_data) == 'table' then
			if coa_data.country then -- make sure there a country table for this coalition
				for cntry_id, cntry_data in pairs(coa_data.country) do -- iterate all countries for this 
					local countryName = string.lower(cntry_data.name)
					if type(cntry_data) == 'table' then	--just making sure
						for obj_type_name, obj_type_data in pairs(cntry_data) do
							if obj_type_name == "helicopter" or obj_type_name == "ship" or obj_type_name == "plane" or obj_type_name == "vehicle" or obj_type_name == "static" then --should be an unncessary check
								local category = obj_type_name
								if ((type(obj_type_data) == 'table') and obj_type_data.group and (type(obj_type_data.group) == 'table') and (#obj_type_data.group > 0)) then	--there's a group!

									for group_num, group_data in pairs(obj_type_data.group) do
										if group_data and group_data.units and type(group_data.units) == 'table' then	--making sure again- this is a valid group
											local groupName = group_data.name
											if env.mission.version > 7 then -- translate raw to actual 
												groupName = env.getValueDictByKey(groupName)
											end
											local hasPlayer = false 
											local playerUnits = {}
											for unit_num, unit_data in pairs(group_data.units) do -- iterate units
												-- see if there is at least one player in group 
												if unit_data.skill then 
													if unit_data.skill == "Client" or  unit_data.skill == "Player" then
														-- this is player unit. save it, remember
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
													end														
												end
											end --for all units in group
						
											local entry = {}
											entry.name = groupName
											entry.coalition = coa_name
											entry.coaNum = coaNum 
											entry.category  = category
											entry.hasPlayer = hasPlayer 
											entry.playerUnits = playerUnits
											-- add to db
											cfxGroups.groups[groupName] = entry
											
										end --if has group_data and group_data.units then
									end --for all groups in category 
								end --if has category data 
							end --if plane, helo etc... category
						end --for all objects in country 
					end --if has country data 
				end --for all countries in coalition
			end --if coalition has country table 
		end -- if there is coalition data  
	end --for all coalitions in mission 
end

-- simply dump all groups to the screen
function cfxGroups.showAllGroups()
	for gName, gData in pairs (cfxGroups.groups) do 
		local isP = "(NPC)"
		if gData.hasPlayer then isP = "*PLAYER GROUP (".. #gData.playerUnits ..")*" end
		trigger.action.outText(gData.name.. ": " .. isP .. " - " .. gData.category .. ", F:" .. gData.coalition
		.. " (" .. gData.coaNum .. ")", 30)
	end
end

-- return all cfxGroups that can have players in them
-- includes groups that currently are not or not anymore alive
function cfxGroups.getPlayerGroup()
	local playerGroups = {}
	for gName, gData in pairs (cfxGroups.groups) do 
		if gData.hasPlayer then
			table.insert(playerGroups, gData)
		end
	end
	return playerGroups 
end

-- return all group names that can have players in them
-- includes groups that currently are not or not anymore alive
function cfxGroups.getPlayerGroupNames()
	local playerGroups = {}
	for gName, gData in pairs (cfxGroups.groups) do 
		if gData.hasPlayer then
			table.insert(playerGroups, gName)
		end
	end
	return playerGroups 
end


function cfxGroups.start()
	cfxGroups.fetchAllGroupsFromDCS() -- read all groups from mission. 
--	cfxGroups.showAllGroups()
	
	trigger.action.outText("cfxGroups version " .. cfxGroups.version .. " started", 30)
	return true 
	
end

cfxGroups.start() 

 