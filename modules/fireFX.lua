fireFX = {}
fireFX.version = "1.1.0"
fireFX.verbose = false 
fireFX.ups = 1 
fireFX.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
fireFX.fx = {}

--[[--
	Version History 
	1.0.0 - Initial version 
	1.1.0 - persistence
	1.1.1 - agl attribute 

--]]--

function fireFX.addFX(theZone)
	table.insert(fireFX.fx, theZone)
end

function fireFX.getFXByName(aName) 
	for idx, aZone in pairs(fireFX.fx) do 
		if aName == aZone.name then return aZone end 
	end
	if fireFX.verbose then 
		trigger.action.outText("+++ffx: no fire FX with name <" .. aName ..">", 30)
	end 
	
end

--
-- read zone 
-- 
function fireFX.createFXWithZone(theZone)
	-- decode size and fire
	local theSize = cfxZones.getStringFromZoneProperty(theZone, "fireFX", "none")
	theSize = dcsCommon.trim(theSize)
	theSize = string.upper(theSize)
	local fxCode = 1
	if theSize == "S" or theSize == "SMALL" then fxCode = 1 end 
	if theSize == "M" or theSize == "MEDIUM" then fxCode = 2 end 
	if theSize == "L" or theSize == "LARGE" then fxCode = 3 end 
	if theSize == "H" or theSize == "HUGE" then fxCode = 4 end
	if theSize == "XL" then fxCode = 4 end 	
	
	local theFire = cfxZones.getBoolFromZoneProperty(theZone, "flames", true)
	
	
	if theFire then 
		-- code stays as it is
	else 
		-- smoke only 
		fxCode = fxCode + 4
	end
	theZone.fxCode = fxCode
	if theZone.verbose or fireFX.verbose then 
		trigger.action.outText("+++ffx: new FX with code = <" .. fxCode .. ">", 30)
	end

	theZone.density = cfxZones.getNumberFromZoneProperty(theZone, "density", 0.5)

	theZone.agl = cfxZones.getNumberFromZoneProperty(theZone, "AGL", 0)
	

	if cfxZones.hasProperty(theZone, "start?") then 
		theZone.fxStart = cfxZones.getStringFromZoneProperty(theZone, "start?", "*<none>")
		theZone.fxLastStart = cfxZones.getFlagValue(theZone.fxStart, theZone)
	end

	if cfxZones.hasProperty(theZone, "stop?") then 
		theZone.fxStop = cfxZones.getStringFromZoneProperty(theZone, "stop?", "*<none>")
		theZone.fxLastStop = cfxZones.getFlagValue(theZone.fxStop, theZone)
	end

	theZone.fxOnStart = cfxZones.getBoolFromZoneProperty(theZone, "onStart", false)
	theZone.burning = false 

	if not theZone.fxOnStart and not theZone.fxStart then 
		trigger.action.outText("+++ffx: WARNING - fireFX Zone <" .. theZone.name .. "> can't be started, neither onStart nor 'start?' defined", 30)
	end
	
	-- output method (not needed)
	
	-- trigger method
	theZone.fxTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "fxTriggerMethod", "change")
	if cfxZones.hasProperty(theZone, "triggerMethod") then 
		theZone.fxTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	end 
	
	if fireFX.verbose or theZone.verbose then 
		trigger.action.outText("+++ffx: new FX <".. theZone.name ..">", 30)
	end
end

--
-- Update 
--
function fireFX.startTheFire(theZone)
	if not theZone.burning then 
		local p = cfxZones.getPoint(theZone)
		p.y = land.getHeight({x = p.x, y = p.z}) + theZone.agl 
		local preset = theZone.fxCode
		local density = theZone.density
		trigger.action.effectSmokeBig(p, preset, density, theZone.name)
		theZone.burning = true 
	end
end

function fireFX.extinguishFire(theZone)
	if theZone.burning then 
		trigger.action.effectSmokeStop(theZone.name)
		theZone.burning = false 
	end
end

function fireFX.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(fireFX.update, {}, timer.getTime() + 1/fireFX.ups)
		
	for idx, aZone in pairs(fireFX.fx) do
		-- see if we are being paused or unpaused 
		if cfxZones.testZoneFlag(aZone, aZone.fxStop, aZone.fxTriggerMethod, "fxLastStop") then 
			if fireFX.verbose or aZone.verbose then 
				trigger.action.outText("+++ffx: triggered 'stop?' for <".. aZone.name ..">", 30)
			end
			fireFX.extinguishFire(aZone)
		end 

		if cfxZones.testZoneFlag(aZone, aZone.fxStart, aZone.fxTriggerMethod, "fxLastStart") then 
			if fireFX.verbose or aZone.verbose then 
				trigger.action.outText("+++ffx: triggered 'start?' for <".. aZone.name ..">", 30)
			end
			fireFX.startTheFire(aZone)
		end 
	end
	
end

--
-- LOAD / SAVE 
-- 
function fireFX.saveData()
	local theData = {}
	local allFX = {}
	for idx, theFX in pairs(fireFX.fx) do 
		local theName = theFX.name 
		local FXData = {}
 		FXData.burning = theFX.burning
		
		allFX[theName] = FXData 
	end
	theData.allFX = allFX
	return theData
end

function fireFX.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("fireFX")
	if not theData then 
		if fireFX.verbose then 
			trigger.action.outText("+++ffx persistence: no save data received, skipping.", 30)
		end
		return
	end
	
	local allFX = theData.allFX
	if not allFX then 
		if fireFX.verbose then 
			trigger.action.outText("+++ffx persistence: no fire FX data, skipping", 30)
		end		
		return
	end
	
	for theName, theData in pairs(allFX) do 
		local theFX = fireFX.getFXByName(theName)
		if theFX then 
			if theData.burning then 
				fireFX.startTheFire(theFX)
			end
			theFX.inited = true -- ensure no onStart overwrite 
		else 
			trigger.action.outText("+++ffx: persistence: cannot synch fire FX <" .. theName .. ">, skipping", 40)
		end
	end
end


--
-- Config & Start
--
function fireFX.readConfigZone()
	local theZone = cfxZones.getZoneByName("fireFXConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("fireFX")
		if fireFX.verbose then 
			trigger.action.outText("+++ffx: NO config zone!", 30)
		end 
	end 
		
	if fireFX.verbose then 
		trigger.action.outText("+++ffx: read config", 30)
	end 
end

function fireFX.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx fire FX requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx fire FX", fireFX.requiredLibs) then
		return false 
	end
	
	-- read config 
	fireFX.readConfigZone()
	
	-- process fireFX Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("fireFX")
	for k, aZone in pairs(attrZones) do 
		fireFX.createFXWithZone(aZone) -- process attributes
		fireFX.addFX(aZone) -- add to list
	end
	
	-- load any saved data 
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = fireFX.saveData
		persistence.registerModule("fireFX", callbacks)
		-- now load my data 
		fireFX.loadData()
	end
	
	-- handle onStart 
	for idx, theZone in pairs(fireFX.fx) do
		if (not theZone.inited) and (theZone.fxOnStart) then
			-- only if we did not init them with loaded data 
			fireFX.startTheFire(theZone)
		end
	end
	
	-- start update 
	fireFX.update()
	
	trigger.action.outText("cfx fire FX v" .. fireFX.version .. " started.", 30)
	return true 
end

-- let's go!
if not fireFX.start() then 
	trigger.action.outText("cfx fireFX aborted: missing libraries", 30)
	fireFX = nil 
end