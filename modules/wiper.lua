wiper = {}
wiper.version = "1.0.0"
wiper.verbose = false 
wiper.ups = 1 
wiper.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
wiper.wipers = {}
--[[--
	Version History
	1.0.0 - Initial Version 

--]]--

function wiper.addWiper(theZone)
	table.insert(wiper.wipers, theZone)
end

function wiper.getWiperByName(aName) 
	for idx, aZone in pairs(wiper.wipers) do 
		if aName == aZone.name then return aZone end 
	end
	if wiper.verbose then 
		trigger.action.outText("+++wpr: no wiper with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read zone 
-- 
function wiper.createWiperWithZone(theZone)
	theZone.triggerWiperFlag = cfxZones.getStringFromZoneProperty(theZone, "wipe?", "*<none>")
	
	-- triggerWiperMethod
	theZone.triggerWiperMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerMethod", "change")
	if cfxZones.hasProperty(theZone, "triggerWiperMethod") then 
		theZone.triggerWiperMethod = cfxZones.getStringFromZoneProperty(theZone, "triggerWiperMethod", "change")
	end 
	
	if theZone.triggerWiperFlag then 
		theZone.lastTriggerWiperValue = cfxZones.getFlagValue(theZone.triggerWiperFlag, theZone)
	end

	local theCat = cfxZones.getStringFromZoneProperty(theZone, "category", "static")
	if cfxZones.hasProperty(theZone, "wipeCategory") then 
		theCat = cfxZones.getStringFromZoneProperty(theZone, "wipeCategory", "static")
	end
	if cfxZones.hasProperty(theZone, "wipeCat") then 
		theCat = cfxZones.getStringFromZoneProperty(theZone, "wipeCat", "static")
	end
	
	theZone.wipeCategory = dcsCommon.string2ObjectCat(theCat)
	
	if cfxZones.hasProperty(theZone, "wipeNamed") then 
		theZone.wipeNamed = cfxZones.getStringFromZoneProperty(theZone, "wipeNamed", "<no name given>")
		theZone.oWipeNamed = theZone.wipeNamed -- save original 
		-- assemble list of all names to wipe, including wildcard
		local allNames = {} 
		if dcsCommon.containsString(theZone.wipeNamed, ",") then 
			allNames = dcsCommon.splitString(theZone.wipeNamed, ",")
			allNames = dcsCommon.trimArray(allNames)
		else 
			allNames = {dcsCommon.trim(theZone.wipeNamed)}
		end
		
		-- assemble dict of all wipeNamed and endswith 
		local theDict = {}
		for idx, aName in pairs(allNames) do 
			local shortName = aName
			local ew = dcsCommon.stringEndsWith(aName, "*")
			if ew then 
				shortName = dcsCommon.removeEnding(aName, "*")
			end
			theDict[shortName] = ew  
			if wiper.verbose or theZone.verbose then 
				trigger.action.outText("+++wpr: dict [".. shortName .."] = " .. dcsCommon.bool2Text(ew),30)
			end 
		end		
		
		theZone.wipeNamed = theDict
		 
	end 
	
	theZone.wipeInventory = cfxZones.getBoolFromZoneProperty(theZone, "wipeInventory", false)
	
	if wiper.verbose or theZone.verbose then 
		trigger.action.outText("+++wpr: new wiper zone <".. theZone.name ..">", 30)
	end
end

--
-- Wiper main action
--
function wiper.objectHandler(theObject, theCollector)
	table.insert(theCollector, theObject)
	return true 
end

wiper.inventory = ""
function wiper.seeZoneInventory(theZone) 
	-- run a diag which objects are in the zone, and which cat they are
	-- set up args
	local allCats = {1, 2, 3, 4, 5, 6}
	wiper.inventory = ""
	for idx, aCat in pairs(allCats) do 
		local p = cfxZones.getPoint(theZone)
		local lp = {x = p.x, y = p.z}
		p.y = land.getHeight(lp)
		local collector = {}
	
		-- now build the search argument 
		local args = {
				id = world.VolumeType.SPHERE,
				params = {
					point = p,
					radius = theZone.radius
				}
			}
	
		-- now call search
		world.searchObjects(aCat, args, wiper.objectHandler, collector)
		wiper.inventory = wiper.inventory .. "Cat = " .. aCat .. ":"
		for idy, anObject in pairs(collector) do 
			wiper.inventory = wiper.inventory .. anObject:getName() .. " "
		end
		wiper.inventory = wiper.inventory .. "\n"
	end
end


function wiper.isTriggered(theZone)
	-- see if we need a diagnostic run
	wiper.inventory = ""	
	if theZone.wipeInventory then 
		wiper.seeZoneInventory(theZone) 
		-- inventory data 
		if theZone.wipeInventory then 
			trigger.action.outText(wiper.inventory, 30)
		end
	end
	
	-- get current location in case theZone is moving 
	local p = cfxZones.getPoint(theZone)
	local lp = {x = p.x, y = p.z}
	p.y = land.getHeight(lp)
	local collector = {}
	
	-- now build the search argument 
	local args = {
			id = world.VolumeType.SPHERE,
			params = {
				point = p,
				radius = theZone.radius
			}
		}
	-- set up remaining arguments
	local cat = theZone.wipeCategory -- Object.Category.STATIC
	
	-- now call search
	world.searchObjects(cat, args, wiper.objectHandler, collector)
	if #collector < 1 and (wiper.verbose or theZone.verbose) then
		trigger.action.outText("+++wpr: world search returned zero elements for <" .. theZone.name .. "> (cat=" .. theZone.wipeCategory .. ")",30)
	end

	-- wipe'em!
	for idx, anObject in pairs(collector) do
		local doWipe = true 

		-- see if we filter to only named objects 
		if theZone.wipeNamed then
			doWipe = false 
			local oName = tostring(anObject:getName()) -- prevent number mismatch 
			for wipeName, beginsWith in pairs(theZone.wipeNamed) do 
				if beginsWith then 
					doWipe = doWipe or dcsCommon.stringStartsWith(oName, wipeName)
				else 
					doWipe = doWipe or oName == wipeName
				end
			end
			
			if wiper.verbose or theZone.verbose then 
				if not doWipe then 
					trigger.action.outText("+++wpr: <"..oName.."> not removed, name restriction <" .. theZone.oWipeNamed .. "> not met.",30)
				end
			end
		end

		if doWipe then 
			if wiper.verbose or theZone.verbose then 
				trigger.action.outText("+++wpr: wiping " .. anObject:getName(), 30)
			end 
			anObject:destroy()
		else 
			if wiper.verbose or theZone.verbose then 
				trigger.action.outText("+++wpr: spared object <" .. anObject:getName() .. ">",30)
			end
		end
	end
	
	
end

--
-- Update 
--
function wiper.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(wiper.update, {}, timer.getTime() + 1/wiper.ups)
		
	for idx, aZone in pairs(wiper.wipers) do
		
		if cfxZones.testZoneFlag(aZone, aZone.triggerWiperFlag, aZone.triggerWiperMethod, "lastTriggerWiperValue") then 
			if wiper.verbose or aZone.verbose then 
				trigger.action.outText("+++wpr: triggered on ".. aZone.triggerWiperFlag .. " for <".. aZone.name ..">", 30)
			end
			wiper.isTriggered(aZone)
		end 
		
	end
end


--
-- Config & Start
--
function wiper.readConfigZone()
	local theZone = cfxZones.getZoneByName("wiperConfig") 
	if not theZone then 
		if wiper.verbose then 
			trigger.action.outText("+++wpr: NO config zone!", 30)
		end 
		theZone = cfxZones.createSimpleZone("wiperConfig") -- temp only
	end 
	
	wiper.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	wiper.ups = cfxZones.getNumberFromZoneProperty(theZone, "ups", 1)
		
	if wiper.verbose then 
		trigger.action.outText("+++wpr: read config", 30)
	end 
end

function wiper.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Wiper requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Wiper", wiper.requiredLibs) then
		return false 
	end
	
	-- read config 
	wiper.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("wipe?")
	for k, aZone in pairs(attrZones) do 
		wiper.createWiperWithZone(aZone) -- process attributes
		wiper.addWiper(aZone) -- add to list
	end
	
	-- start update 
	wiper.update()
	
	trigger.action.outText("cfx Wiper v" .. wiper.version .. " started.", 30)
	return true 
end

-- let's go!
if not wiper.start() then 
	trigger.action.outText("cfx Wiper aborted: missing libraries", 30)
	wiper = nil 
end