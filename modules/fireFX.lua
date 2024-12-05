fireFX = {}
fireFX.version = "2.1.0"
fireFX.verbose = false 
fireFX.ups = 1 
fireFX.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
fireFX.fx = {} -- the fx zones 

--[[--
	Version History 
	1.0.0 - Initial version 
	1.1.0 - persistence
	1.1.1 - agl attribute 
    2.0.0 - dmlZones OOP 
		  - rndLoc 
	2.0.1 - fixed rndLoc determination
	2.1.0 - supports rnd as fire size 
		  - rewrote save, backwards compatible to old 
		  - simplified zone access
--]]--

function fireFX.addFX(theZone)
--	table.insert(fireFX.fx, theZone)
	fireFX.fx[theZone.name] = theZone
end

function fireFX.getFXByName(aName) 
	return fireFX.fx[aName]
--	for idx, aZone in pairs(fireFX.fx) do 
--		if aName == aZone.name then return aZone end 
--	end
--	if fireFX.verbose then 
--		trigger.action.outText("+++ffx: no fire FX with name <" .. aName ..">", 30)
--	end 
end

--
-- read zone 
-- 
function fireFX.createFXWithZone(theZone)
	-- decode size and fire
	local theSize = theZone:getStringFromZoneProperty("fireFX", "none")
	theSize = dcsCommon.trim(theSize)
	theSize = string.upper(theSize)
	local fxCode = 1
	if theSize == "S" or theSize == "SMALL" then fxCode = 1 end 
	if theSize == "M" or theSize == "MEDIUM" then fxCode = 2 end 
	if theSize == "L" or theSize == "LARGE" then fxCode = 3 end 
	if theSize == "H" or theSize == "HUGE" then fxCode = 4 end
	if theSize == "XL" then fxCode = 4 end 	
	if theSize == "RND" then fxCode = -1 end -- randomized
	
	theZone.fxCode = fxCode -- raw, without flame code 
	if theZone.verbose or fireFX.verbose then 
		trigger.action.outText("+++ffx: new FX with code = <" .. fxCode .. ">", 30)
	end
	theZone.fxData = {} -- used when created 
	theZone.density = theZone:getNumberFromZoneProperty("density", 0.5)
	theZone.agl = theZone:getNumberFromZoneProperty("AGL", 0)
	theZone.min, theZone.max = theZone:getPositiveRangeFromZoneProperty("num", 1, 1)
	if theZone:hasProperty("start?") then 
		theZone.fxStart = theZone:getStringFromZoneProperty("start?", "*<none>")
		theZone.fxLastStart = theZone:getFlagValue(theZone.fxStart)
	end
	if theZone:hasProperty("stop?") then 
		theZone.fxStop = theZone:getStringFromZoneProperty("stop?", "*<none>")
		theZone.fxLastStop = theZone:getFlagValue(theZone.fxStop)
	end
	theZone.fxOnStart = theZone:getBoolFromZoneProperty("onStart", false)
	theZone.burning = false 
	if not theZone.fxOnStart and not theZone.fxStart then 
		trigger.action.outText("+++ffx: WARNING - fireFX Zone <" .. theZone.name .. "> can't be started, neither onStart nor 'start?' defined", 30)
	end
		
	theZone.fxTriggerMethod = theZone:getStringFromZoneProperty( "fxTriggerMethod", "change")
	if theZone:hasProperty("triggerMethod") then 
		theZone.fxTriggerMethod = theZone:getStringFromZoneProperty( "triggerMethod", "change")
	end 	
	theZone.rndLoc = theZone:getBoolFromZoneProperty("rndLoc", false)
	if theZone.max > 1 and (not theZone.rndLoc) then 
		if theZone.verbose or fireFX.verbose then 
			trigger.action.outText("+++ffx: more than 1 fires, will set to random loc", 30)
		end 
		theZone.rndLoc = true 
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
		theZone.fireNames = {}
		theZone.fxData = {}
		local num = cfxZones.randomInRange(theZone.min, theZone.max)
		for i = 1, num do 
			local p = theZone:getPoint()
			if theZone.rndLoc then 
				p = theZone:randomPointInZone()
			end
			p.y = land.getHeight({x = p.x, y = p.z}) + theZone.agl 
			local preset = theZone.fxCode
			-- process randomization
			if preset < 1 then 
				preset = math.random(4) -- 1..4 
			end 
			if theZone:getBoolFromZoneProperty("flames", true) then 
				--preset = preset
				--trigger.action.outText("fire <" .. i .. "> with flame: <" .. preset .. ">", 30)
			else 
				preset = preset + 4 -- smoke only 
				--trigger.action.outText("no flames for fire <" .. i .. ">: <" .. preset .. ">", 30)
			end -- support for 'rnd' as bool 
			local density = theZone.density
			local fireName = dcsCommon.uuid(theZone.name)
			trigger.action.effectSmokeBig(p, preset, density, fireName)
			theZone.fireNames[i] = fireName 
			theZone.fxData[i] = {p, preset, density, fireName}
		end
		theZone.burning = true 
	end
end

function fireFX.extinguishFire(theZone)
	if theZone.burning then 
		for idx, aFireName in pairs(theZone.fireNames) do 
			trigger.action.effectSmokeStop(aFireName)
		end
		theZone.burning = false 
		theZone.fireNames = {}
		theZone.fxData = {}
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
		fxData.data = theFX.fxData
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
		local theFX = fireFX.getFXByName(theName) -- get fx zone
		if theFX then 
			if theData.burning then 
				if theData.data then
					-- we have new save data, replicate flame fx
					theZone.fireNames = {}
					theZone.fxData = {}
					for idx, fxData in pairs(theData.data) do 
						local p = fxData[1]
						local preset = fxData[2]
						local density = fxData[3]
						local fireName = dcsCommon.uuid(theZone.name)
						trigger.action.effectSmokeBig(p, preset, density, fireName)
						theZone.fireNames[idx] = fireName 
						theZone.fxData[idx] = {p, preset, density, fireName}
					end 
				else
					fireFX.startTheFire(theFX) -- old save data
				end 
			else 
				theZone.fireNames = {}
				theZone.fxData = {}
				theZone.burning = false 
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