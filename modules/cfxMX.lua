cfxMX = {}
cfxMX.version = "1.0.0"
--[[--
 Mission data decoder. Access to ME-built mission structures
 
 Copyright (c) 2022 by Christian Franz and cf/x AG
 
 Version History
   1.0.0 - initial version 
   
 
--]]--

function cfxMX.getGroupFromDCSbyName(aName, fetchOriginal)
	if not fetchOriginal then fetchOriginal = false end 
	-- fetch the group description for goup named aName (if exists)
	-- returned structure must be parsed for useful information 
	-- returns data, category, countyID and coalitionID 
	-- unless fetchOriginal is true, creates a deep clone of 
	-- group data structure 
		
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
 