planeGuard = {}
planeGuard.version = "1.0.0"
planeGuard.requiredLibs = {
	"dcsCommon", 
	"cfxZones",  
	"cfxMX"
}
planeGuard.zones = {} -- all zones, indexed by name 

--[[--  
	Version History 
	1.0.0 - Initial version 
	
--]]--

-- read zone 
function planeGuard.createPlaneGuardZone(theZone)
	theZone.hType = theZone:getStringFromZoneProperty("planeGuard", "CH-53E")
	theZone.alt = theZone:getNumberFromZoneProperty("alt", 40)
	theZone.count = 1
	-- immediately create the helo as plane guard 
	planeGuard.createGroupForZone(theZone)
end 

function planeGuard.createGroupForZone(theZone)
	local A = theZone:getPoint()
	local theUnit, theGroup, idx = cfxMX.getClosestUnitToPoint(A, "ship")
	if not theUnit then 
		trigger.action.outText("+++pGuard: can't find naval units for zone <" .. theUnit.name .. ">", 30) 
		return
	end 
	if theZone.verbose or planeGuard.verbose then trigger.action.outText("+++pGuard: attaching guard to unit <" .. theUnit.name .. "> in group <" .. theGroup.name .. "> for zone <" .. theZone.name .. ">", 30) end
	local h = theUnit.heading
	if not h then h = 0 end 
	local ax = A.x 
	local ay = A.z -- !!! 
	local mainUnit = theGroup.units[1]
	-- calc point relative to MAIN unit and project onto 
	-- rotated offsets 
	local pgx = ax - mainUnit.x
	local pgy = ay - mainUnit.y
	pgx, pgy = dcsCommon.rotatePointAroundOriginRad(pgx, pgy, -h)
	local degrees = math.floor(h * 57.2958)
	local theName = theZone.name .. "-" .. theZone.count
	local sx = ax -- start coords
	local sy = ay 
	theZone.count = theZone.count + 1
	local cty = cfxMX.countryByName[theGroup.name]
	local newGroupData = {
		["tasks"] = {},
		["radioSet"] = false,
		["task"] = "Transport",
		["route"] = {
			["points"] = {
				[1] = {
					["alt"] = 40,
					["action"] = "Turning Point",
					["alt_type"] = "BARO",
					["properties"] = {["addopt"] = {},},
					["speed"] = 7,
					["task"] = {
						["id"] = "ComboTask",
						["params"] = {
							["tasks"] =	{
								[1] = {
									["enabled"] = true,
									["auto"] = false,
									["id"] = "WrappedAction",
									["number"] = 1,
									["params"] = {
										["action"] = {
											["id"] = "SetUnlimitedFuel",
											["params"] = { ["value"] = true, }, -- end of ["params"]
										}, -- end of ["action"]
									}, -- end of ["params"]
								}, -- end of [1]
							}, -- end of ["tasks"]
						}, -- end of ["params"]
					}, -- end of ["task"]
					["type"] = "Turning Point",
					["ETA"] = 0,
					["ETA_locked"] = true,
					["y"] = sy + 100, -- start here
					["x"] = sx + 100, -- start here
					["speed_locked"] = true,
				}, -- end of [1]
				[2] = {
					["alt"] = 40,
					["action"] = "Turning Point",
					["alt_type"] = "BARO",
					["properties"] = {["addopt"] = {},}, 
					["speed"] = 7,
					["task"] = {
						["id"] = "ComboTask",
						["params"] = {
							["tasks"] = {
								[1] = {
									["number"] = 1,
									["auto"] = false,
									["id"] = "ControlledTask",
									["enabled"] = true,
									["params"] = {
										["task"] = {
											["id"] = "Follow",
											["params"] = {
												["lastWptIndexFlagChangedManually"] = true,
												["x"] = sx,
												["groupId"] = theGroup.groupId, --1, -- group to follow
												["lastWptIndex"] = 4,
												["lastWptIndexFlag"] = false,
												["y"] = sy,
												["pos"] = {
													["y"] = theZone.alt, -- alt 
													["x"] = pgx, --(up/down)
													["z"] = pgy, --(left/right)
												}, -- end of ["pos"]
											}, -- end of ["params"]
										}, -- end of ["task"]
										["stopCondition"] = {["userFlag"] = "999",}, -- end of ["stopCondition"]
									}, -- end of ["params"]
								}, -- end of [1]
							}, -- end of ["tasks"]
						}, -- end of ["params"]
					}, -- end of ["task"]
					["type"] = "Turning Point",
					["y"] = sy + 100,
					["x"] = sx + 100,
				}, -- end of [2]
			}, -- end of ["points"]
		}, -- end of ["route"]
		["hidden"] = false,
		["units"] = {
			[1] = {
				["alt"] = 40,
				["alt_type"] = "BARO",
				["skill"] = "High",
				["speed"] = 7,
				["type"] = theZone.hType,
				["y"] = sy + 100,
				["x"] = sx + 100,
				["name"] = theName .. "-1",
				["heading"] = 0,
			}, -- end of [1]
		}, -- end of ["units"]
		["y"] = sy + 100,
		["x"] = sx + 100,
		["name"] = theName,
	} -- end of theGroup
	-- allocate the new group. Always helo 
	 local pgGroup = coalition.addGroup(cty, 1, newGroupData)
end

-- config
function planeGuard.readConfigZone()
	local theZone = cfxZones.getZoneByName("planeGuardConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("planeGuardConfig") 
	end 
	planeGuard.verbose = theZone.verbose 
end

-- go go go 
function planeGuard.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("planeGuard requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("planeGuard", planeGuard.requiredLibs) then
		return false 
	end	
	-- read config 
	planeGuard.readConfigZone()
	-- process "planeGuard" Zones  
	local attrZones = cfxZones.getZonesWithAttributeNamed("planeGuard")
	for k, aZone in pairs(attrZones) do 
		planeGuard.createPlaneGuardZone(aZone)
		planeGuard.zones[aZone.name] = aZone
	end
	trigger.action.outText("planeGuard v" .. planeGuard.version .. " started.", 30)
	return true 
end

-- let's go!
if not planeGuard.start() then 
	trigger.action.outText("planeGuard aborted: error on start", 30)
	planeGuard = nil 
end