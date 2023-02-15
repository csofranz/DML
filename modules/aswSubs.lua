aswSubs = {}
aswSubs.version = "1.0.0"
aswSubs.verbose = false 
aswSubs.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}

--[[--
	Version History
	1.0.0 - initial version 
	
--]]--
 
aswSubs.groupsToWatch = {} -- subs attack any group in here if they are of a different coalition and not neutral
aswSubs.unitsHit = {} -- the goners

function aswSubs.addWatchgroup(name)
	if Group.getByName(name) then 
		aswSubs.groupsToWatch[name] = name 
	else 
		trigger.action.outText("+++aswSubs: no group named <" .. name .. "> to watch over", 30)
	end 	
end

function aswSubs.gatherSubs()
	local allCoas = {0, 1, 2}
	local subs = {}
	for idx, coa in pairs(allCoas) do 
		local allGroups = coalition.getGroups(coa, 3) -- ships only
		for idy, aGroup in pairs(allGroups) do 
			allUnits = aGroup:getUnits()
			for idz, aUnit in pairs(allUnits) do 
				-- see if this unit is a sub 
				if aUnit and Unit.isExist(aUnit) then 
					if (dcsCommon.getUnitAGL(aUnit) < -5) then	-- submerged contact.
						local contact = {}
						contact.theUnit = aUnit
						contact.coalition = coa 
						contact.name = aUnit:getName()
						contact.loc = aUnit:getPoint()
						subs[contact.name] = contact 
					end 
				end
			end
		end
	end
	return subs 
end

function aswSubs.boom(args)
	
	local uName = args.name 
	local loc = args.loc 
	local theUnit = Unit.getByName(uName)
	if theUnit and theUnit.isExist(theUnit) then 
		loc = theUnit:getPoint()
	end
	
	trigger.action.explosion(loc, aswSubs.explosionDamage)
end

function aswSubs.alert(theUnit, theContact)
	-- note: we dont need theContact right now
	if not theUnit or not Unit.isExist(theUnit) then 
		return 
	end 
	
	-- see if this was hit before 
	local uName = theUnit:getName()
	if aswSubs.unitsHit[uName] then return end 
	
	-- mark it as hit 
	aswSubs.unitsHit[uName] = theContact.name 
	
	-- schedule a few explosions
	local args = {}
	args.name = uName
	args.loc = theUnit:getPoint()
	local salvoSize = tonumber(aswSubs.salvoMin) 
	local varPart = tonumber(aswSubs.salvoMax) - tonumber(aswSubs.salvoMin)
	if varPart > 0 then 
		varPart = dcsCommon.smallRandom(varPart)
		salvoSize = salvoSize + varPart
	end
	
	for i=1, tonumber(salvoSize) do 
		timer.scheduleFunction(aswSubs.boom, args, timer.getTime() + i*2 + 4)
	end 
	
	-- theContact has come within crit dist of theUnit
	local coa = theUnit:getCoalition()
	trigger.action.outTextForCoalition(coa, theUnit:getName() .. " reports " .. salvoSize .. " incoming torpedoes!", 30)
end

function aswSubs.update()
	--env.info("-->Enter asw Subs update")
	timer.scheduleFunction(aswSubs.update, {}, timer.getTime() + 1)

	-- get all current subs 
	local allSubs = aswSubs.gatherSubs()
	
	-- now iterate all watch groups 
	for idx, name in pairs(aswSubs.groupsToWatch) do 
		local theGroup = Group.getByName(name)
		if theGroup and Group.isExist(theGroup) then 
			local groupCoa = theGroup:getCoalition()
			if theGroup and Group.isExist(theGroup) then 
				allUnits = theGroup:getUnits()
				for idx, aUnit in pairs(allUnits) do 
					-- check against all subs
					if aUnit and Unit.isExist(aUnit) then 
						local loc = aUnit:getPoint()
						for cName, contact in pairs(allSubs) do 
							-- attack other side but not neutral 
							if groupCoa ~= contact.coalition and groupCoa ~= 0 then 
								-- ok, go check 
								local dist = dcsCommon.dist(loc, contact.loc)
								if dist < aswSubs.critDist then 
									aswSubs.alert(aUnit, contact)
								end
							end
						end
					end
				end
			end
		end
	end
	--env.info("<--Levae asw Subs update")
end


--
-- Config & start 
--
function aswSubs.readConfigZone()
	local theZone = cfxZones.getZoneByName("aswSubsConfig") 
	if not theZone then 
		if aswSubs.verbose then 
			trigger.action.outText("+++aswSubs: no config zone!", 30)
		end 
		theZone =  cfxZones.createSimpleZone("aswSubsConfig")
	end 
	
	-- read & set defaults
	aswSubs.critDist = 4000
	aswSubs.critDist = cfxZones.getNumberFromZoneProperty(theZone, "critDist", aswSubs.critDist)
	aswSubs.explosionDamage = 1000
	aswSubs.explosionDamage = cfxZones.getNumberFromZoneProperty(theZone, "explosionDamage", aswSubs.explosionDamage)
	
	aswSubs.salvoMin, aswSubs.salvoMax = cfxZones.getPositiveRangeFromZoneProperty(theZone, "salvoSize", 4, 4)
	--trigger.action.outText("salvo: min <" .. aswSubs.salvoMin .. ">, max <" .. aswSubs.salvoMax .. ">", 30)
	local targets = cfxZones.getStringFromZoneProperty(theZone, "targets", "")
	local t2 = dcsCommon.string2Array(targets, ",")
	for idx, targetName in pairs (t2) do 
		aswSubs.addWatchgroup(targetName)
	end
	
	if aswSubs.verbose then 
		trigger.action.outText("+++aswSubs: read config", 30)
	end 
end

function aswSubs.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx aswSubs requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx aswSubs", aswSubs.requiredLibs) then
		return false 
	end
	
	-- read config
	aswSubs.readConfigZone()
	
	-- start the script
	aswSubs.update()

	-- all is good 
	trigger.action.outText("cfx ASW Subs v" .. aswGUI.version .. " started.", 30)
	
	return true 
end

--
-- start up aswSubs
--
if not aswSubs.start() then 
	trigger.action.outText("cfx aswSubs aborted: missing libraries", 30)
	aswSubs = nil 
end

