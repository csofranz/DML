bcn = {}
bcn.version = "1.0.0"
bcn.verbose = false 

-- requires dcsCommon 

--[[--
	Get access to the "beacons" and "Radio" structure that is usually not accessible from within MSE
	Make homers accessible 
	(C) 2025 by Christian Franz

VERSION HISTORY
1.0.0 Initial Version, based on twn

--]]--

--[[--
	beacon types are bit-encoded
	
BEACON_TYPE_VOR = 1 					= 0x0000 0000 0000 0001
BEACON_TYPE_DME = 2 					= 0x0000 0000 0000 0010
BEACON_TYPE_VOR_DME = 3 				= 0x0000 0000 0000 0011
BEACON_TYPE_TACAN = 4					= 0x0000 0000 0000 0100
BEACON_TYPE_VORTAC = 5					= 0x0000 0000 0000 0101
BEACON_TYPE_RSBN = 128					= 0x0000 0001 0000 0000
BEACON_TYPE_BROADCAST_STATION = 1024	= 0x0000 0100 0000 0000

BEACON_TYPE_HOMER = 8					= 0x0000 0000 0001 0000
BEACON_TYPE_AIRPORT_HOMER = 4104        = 0x0001 0000 0000 1000
BEACON_TYPE_AIRPORT_HOMER_WITH_MARKER = 4136
										= 0x0001 0000 0010 1000
BEACON_TYPE_ILS_FAR_HOMER = 16408		= 0x0100 0000 0001 1000
BEACON_TYPE_ILS_NEAR_HOMER = 16424		= 0x0100 0000 0010 1000

BEACON_TYPE_ILS_LOCALIZER = 16640		= 0x0100 0001 0000 0000
BEACON_TYPE_ILS_GLIDESLOPE = 16896		= 0x0100 0010 0000 0000

BEACON_TYPE_PRMG_LOCALIZER = 33024		= 0x1000 0001 0000 0000
BEACON_TYPE_PRMG_GLIDESLOPE = 33280 	= 0x1000 0010 0000 0000

BEACON_TYPE_ICLS_LOCALIZER = 131328		
BEACON_TYPE_ICLS_GLIDESLOPE = 131584

BEACON_TYPE_NAUTICAL_HOMER = 65536

BEACON_TYPE_TACAN_RANGE = 262144	
--]]--


function bcn.start()
	-- get my theater
	local theater = env.mission.theatre 
	-- map naming oddities 
	if theater == "SinaiMap" then theater = "Sinai" end 
	if theater == "GermanyCW" then theater = "GermanyColdWar" end 
	if bcn.verbose then 
		trigger.action.outText("theater is <" .. theater .. ">", 30)
	end 
	local path = "./Mods/terrains/" .. theater .. "/beacons.lua" -- defines "baacons"
	-- assemble command 
	local command = 't = loadfile("' .. path .. '"); if t then t(); return net.lua2json(beacons); else return nil end'
	if bcn.verbose then 
		trigger.action.outText("will run command <" .. command .. ">", 30)
	end 
	local json = net.dostring_in("gui", command)
	
	if json then 
		beacons = {} -- GLOBAL
		homers = {} -- GLOBAL
		local braw = net.json2lua(json)		
		local count = 0 
		local h = 0 
		for name, entry in pairs (braw) do 
			entry.x = entry.position[1]
			entry.y = entry.position[2]
			entry.z = entry.position[3]
			beacons[name] = entry
			local t = tonumber(entry.type) 
			if t == 8 or -- Homer
			   t == 4104 or -- BEACON_TYPE_AIRPORT_HOMER
			   t == 4136 or -- BEACON_TYPE_AIRPORT_HOMER_WITH_MARKER
			   t == 16408 or -- BEACON_TYPE_ILS_FAR_HOMER
			   t == 16424 then -- BEACON_TYPE_ILS_NEAR_HOMER
				homers[name] = entry
				h = h + 1
			end 
			count = count + 1
		end 
		if bcn.verbose then 
			trigger.action.outText("+++bcn: <" .. count .. "> beacons, <" .. h .. "> homers processed", 30)
		end 
	else 
		trigger.action.outText("+++bcn: no beacons accessible for <" .. theater .. ">.", 30)
		return false
	end 
		
	-- now import airfield towers / radio stations 
	path = "./Mods/terrains/" .. theater .. "/radio.lua" -- defines "radio"
	command = 't = loadfile("' .. path .. '"); if t then t(); return net.lua2json(radio); else return nil end'
	if bcn.verbose then 
		trigger.action.outText("will run command <" .. command .. ">", 30)
	end 
	json = net.dostring_in("gui", command)
	if json then 
		radio = {} -- GLOBAL!!!
		local rraw = net.json2lua(json)		
		local count = 0 
		for name, entry in pairs (rraw) do 
			radio[name] = entry
			count = count + 1
		end 
		if bcn.verbose then 
			trigger.action.outText("+++bcn: <" .. count .. "> radios processed", 30)
		end 
	else 
		trigger.action.outText("+++bcn: no radios accessible for <" .. theater .. ">.", 30)
		return false
	end 
	trigger.action.outText("bcn (beacon/radio importer) v " .. bcn.version .. " started.", 30)
	return true
end

--[[--
-- Frequency bands IN QUOTES FOR JSON CONVERSION BECAUSE OF 0??? --]]--
HF = "0"
VHF_LOW = "1"
VHF_HI = "2"
UHF = "3"

--[[-- Modulation types --]]--
MODULATIONTYPE_AM = 0
MODULATIONTYPE_FM = 1
MODULATIONTYPE_AMFM = 2
MODULATIONTYPE_DISCARD = -1

--[[-- --]]--

function bcn.getRadioForAirfield(name, role) -- role if multiple same defined 
	-- returns entire radio entry!
	-- since radios file is really bad (e.g. we get "Kolkhi" for Senaki-Kolkhi"
	-- we need to do some tricksy stuff 
	name = name:lower() 
	
	for idx, entry in pairs(radio) do 
		-- we compare and return first hit
		local cs = entry.callsign -- callsign is an array 		
		for idnum, num in pairs(cs) do -- callsign is an array: 1, 2, 3
			for idusg, usage in pairs(num) do -- usage is a dict "nato, common, ..." 
				for idname, aName in pairs(usage) do -- names as array, 1: Anapa, 2: Anapa (...??)
					-- this appears to be a strange json artifact
					local lName = aName:lower()
					if lName == name or string.find(name, lName, 1, true) or string.find(lName, name, 1, true) then 
						if not role then return entry 
						else 
							for idr, aRole in pairs(entry.role) do 
								if aRole == role then return entry 
								else
									if bcn.verbose then 
										trigger.action.outText("+++bcn: airfield <" .. name .. "> role <" .. role .. "> mismatch (has: <" .. aRole .. ">) in idname <" .. idusg .. ">", 30)
									end
								end
							end
						end 
					end
				end 
			end 
		end
	end
	if bcn.verbose then 
		trigger.action.outText("+++bcn: no radio for airfield <" .. name .. "> found.", 30)
	end 
	return nil 
end

function bcn.closestHomerTo(loc)
	local x = loc.x 
	local z = loc.z
	local closest = nil 
	local bestdist = math.huge 
	for idx, entry in pairs(homers) do 
		local dx = x - entry.x 
		local dz = z - entry.z
		local dist = dx * dx + dz * dz -- mag only
		if dist < bestdist then 
			closest = entry 
			bestdist = dist
		end 
	end
	return closest, bestdist^0.5 
end

-- beacon to text 
function bcn.beacon2text(theBeacon) 
	local f = math.floor(theBeacon.frequency / 1000) -- in kHz
	local fBand = "kHz"
	if f > 4000 then 
		f = f / 1000
		fBand = "MHz"
	end
	local msg = theBeacon.display_name .. " ("
	msg = msg .. f .. fBand .. " \"" .. theBeacon.callsign .. "\"" 
	if dcsCommon then 
		msg = msg .. ", Morse: " .. dcsCommon.morseString(theBeacon.callsign) 
	end 
	msg = msg .. ")"
	return msg
end

-- radio freq to text
function bcn.freq2text(freq, sep) -- use sep = ", " for lists, default uses CR
	if not sep then sep = "\n" end 
	local count = 0 
	if not freq then return "Err: no freq in for freq2text" end
	local msg = ""
	if freq[HF] then 
		msg = msg .. "HF: " .. bcn.mod2text(freq[HF]) 
		count = count + 1
--	else 
--		trigger.action.outText("no freq[HF]", 30)
	end 
	
	if freq[VHF_LOW] then
		if count > 0 then msg = msg .. sep end 
		msg = msg .. "VHF: " .. bcn.mod2text(freq[VHF_LOW]) 
		count = count + 1
	end 

	if freq[VHF_HI] then
		if count > 0 then msg = msg .. sep end 
		msg = msg .. "VHF: " .. bcn.mod2text(freq[VHF_HI]) 
		count = count + 1
	end
	
	if freq[UHF] then
		if count > 0 then msg = msg .. sep end 
		msg = msg .. "UHF: " .. bcn.mod2text(freq[UHF]) 
		count = count + 1
	end
	
	return msg
end

-- modulation support
function bcn.mod2text(modu) 
	local r = ""
	-- we assume a simple list a la {modulation, freq}
	local f = modu[2] -- in Hz
	f = math.floor(f/1000) -- no kHz
	if f > 3000 then r = r .. f/1000 .. "MHz " 
	else r = r .. f .. "kHz " end 
	if modu[1] == 0 then r = r .. "AM" 
	else r = r .. "FM" end 
	return r
end

if not bcn.start() then 
	trigger.action.outText("No beacons", 30)
end
