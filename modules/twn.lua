twn = {}
twn.version = "1.0.1"
twn.verbose = false 

--[[--
	A DML unicorn - doesn't require any other scripts to function 
	(C) 2024 by Christian Franz 

VERSION HISTORY
1.0.0 - Initial version 
1.0.1 - Sinai // SinaiMap switcharoo 

--]]--

function twn.closestTownTo(p) -- returns name, data, distance
	if not towns then 
		trigger.action.outText("+++twn: Towns undefined", 30)
		return nil, nil, nil  
	end
	local closest = nil 
	local theName = nil 
	local smallest = math.huge
	local x = p.x 
	local z = p.z 
	for name, entry in pairs(towns) do 
		local dx = x - entry.p.x 
		local dz = z - entry.p.z
		local d = dx * dx + dz * dz -- no need to take square root 
		if d < smallest then 
			smallest = d 
			closest = entry 
			theName = name 
		end
	end
	return theName, closest, smallest^0.5  -- root it!
end

function twn.start()
	-- get my theater
	local theater = env.mission.theatre 
	-- map naming oddities 
	if theater == "SinaiMap" then theater = "Sinai" end 
	if twn.verbose then 
		trigger.action.outText("theater is <" .. theater .. ">", 30)
	end 
	local path = "./Mods/terrains/" .. theater .. "/map/towns.lua"
	-- assemble command 
	local command = 't = loadfile("' .. path .. '"); if t then t(); return net.lua2json(towns); else return nil end'
	if twn.verbose then 
		trigger.action.outText("will run command <" .. command .. ">", 30)
	end 
	local json = net.dostring_in("gui", command)
	
	if json then 
		towns = {}
		traw = net.json2lua(json)
		local count = 0 
		for name, entry in pairs (traw) do 
			local p = coord.LLtoLO(entry.latitude, entry.longitude,0)
			entry.p = p 
			towns[name] = entry
			count = count + 1
		end 
		if twn.verbose then 
			trigger.action.outText("+++twn: <" .. count .. "> town records processed", 30)
		end 
	else 
		trigger.action.outText("+++twn: no towns accessible.", 30)
		return false
	end 
	
	trigger.action.outText("twn (towns importer) v " .. twn.version .. " started.", 30)
	return true
end

twn.start()