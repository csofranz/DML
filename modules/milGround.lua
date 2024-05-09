milGround = {}
milGround.version = "0.0.0"
milGround.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
	"cfxMX",
	"cloneZones",
}
milGround.ups = 0.5 -- every 2 seconds is enough 
milGround.zones = {}

function milGround.addMilGroundZone(theZone)
	milGround.zones[theZone.name] = theZone
end 

--
-- Reading zones 
--
function milGround.readMilGroundZone(theZone)
	-- first, check if this zone is also a cloner 
	if not theZone:hasProperty("cloner") then 
		trigger.action.outText("mGnd: WARNING: milGround zone <" .. theZone.name .. "> has no 'cloner' interface, will fail!", 30)
	end
	-- now get the target zone. it's inside the milGround property
	local tzn = theZone:getStringFromZoneProperty("milGround", "cfxNone")
	local tz = cfxZones.getZoneByName(tzn)
	if not tz then 
		trigger.action.outText("mGnd: target zone <" .. tzn .. "> not found for milGroundZone <" .. theZone.name .. ">, will fail!", 30)
	end
	theZone.targetZone = tz 
	if theZone:hasProperty("coalition") then 
		theZone.owner = theZone:getCoalitionFromZoneProperty("coalition")
	end 
end

--
-- Update
--
function milGround.update()
	timer.scheduleFunction(milGround.update, {}, timer.getTime() + 1/milGround.ups)
	
	for zName, theZone in pairs(milGround.zones) do 
		-- synch owner and coa 
		local mo = theZone.masterowner
		if mo then 
			theZone.owner = mo.owner 
			if theZone.isDynamic then 
				theZone.coa = theZone.owner
			end
		end
	end
end

--
-- config 
--
function milGround.readConfigZone()
	local theZone = cfxZones.getZoneByName("milGroundConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("milGroundConfig") 
	end 
	milGround.verbose = theZone.verbose 
end

--
-- API 
--
function milGround.getAttackersForEnemiesOfCoa(coa, addNeutral)
	-- return all milGround zones that attack zones that belong to 
	-- the enemy of coa 
	local theOtherSide = dcsCommon.getEnemyCoalitionFor(coa)
	local attackers = {}
	for zName, theZone in pairs(milGround.zones) do 
		local tz = theZone.targetZone
		if tz.owner ~= coa then  
			if addNeutral then 
				table.insert(attackers, theZone)
			else 
				if tz.owner == theOtherSide then 
					table.insert(attackers, theZone)
				end
			end
		end
	end 
	return attackers
end

function milGround.startAttackFrom(theZone)
	cloneZones.spawnWithCloner(theZone) -- that's all, folx 
end 

--
-- start up
--
function milGround.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx mil ground requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx mil ground", milGround.requiredLibs) then
		return false 
	end
	
	-- read config 
	milGround.readConfigZone()
	
	-- process milGround Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("milGround")
	for k, aZone in pairs(attrZones) do 
		milGround.readMilGroundZone(aZone) -- process attributes
		milGround.addMilGroundZone(aZone) -- add to list
	end
		
	-- start update in 5 seconds
	timer.scheduleFunction(milGround.update, {}, timer.getTime() + 1/milGround.ups)
	
	-- say hi 
	trigger.action.outText("milGround v" .. milGround.version .. " started.", 30)
	return true 
end

if not milGround.start() then 
	trigger.action.outText("milGround failed to start.", 30)
	milGround = nil 
end