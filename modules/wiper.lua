wiper = {}
wiper.version = "1.2.0"
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
	1.1.0 - added zone bounds check before wiping 
	1.2.0 - OOP dmlZones
		  - categories can now be a list 
		  - declutter opetion
		  - if first category is 'none', zone will not wipe at all but may declutter 

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
	theZone.triggerWiperFlag = theZone:getStringFromZoneProperty("wipe?", "*<none>")
	
	-- triggerWiperMethod
	theZone.triggerWiperMethod = theZone:getStringFromZoneProperty("triggerMethod", "change")
	if theZone:hasProperty("triggerWiperMethod") then 
		theZone.triggerWiperMethod = theZone:getStringFromZoneProperty("triggerWiperMethod", "change")
	end 
	
	if theZone.triggerWiperFlag then 
		theZone.lastTriggerWiperValue = theZone:getFlagValue(theZone.triggerWiperFlag)
	end

	local theCat = theZone:getStringFromZoneProperty("category", "none")
	if theZone:hasProperty("wipeCategory") then 
		theCat = theZone:getStringFromZoneProperty("wipeCategory", "none")
	end
	if cfxZones.hasProperty(theZone, "wipeCat") then 
		theCat = theZone:getStringFromZoneProperty("wipeCat", "none")
	end
	local allCats = {} 
	if dcsCommon.containsString(theCat, ",") then 
		allCats = dcsCommon.splitString(theCat, ",")
		allCats = dcsCommon.trimArray(allCats)
	else 
		allCats = {dcsCommon.trim(theCat)}
	end
	-- translate to category for each entry 
	theZone.wipeCategory = {}
	if allCats[1] == "none" then 
--		theZone.wipeCategory = {} -- no category to wipe 
	else
		for idx, aCat in pairs (allCats) do 
			table.insert(theZone.wipeCategory, dcsCommon.string2ObjectCat(aCat))
		end	
	end 
--	theZone.wipeCategory = dcsCommon.string2ObjectCat(theCat)
	
	theZone.declutter = theZone:getBoolFromZoneProperty("declutter", false)
	
	if theZone:hasProperty("wipeNamed") then 
		theZone.wipeNamed = theZone:getStringFromZoneProperty("wipeNamed", "<no name given>")
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
				trigger.action.outText("+++wpr: dict [".. shortName .."], '*' = " .. dcsCommon.bool2Text(ew) .. " for <" .. theZone:getName() .. ">",30)
			end 
		end		
		theZone.wipeNamed = theDict
	end 
	
	theZone.wipeInventory = theZone:getBoolFromZoneProperty("wipeInventory", false)
	
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
					-- now also filter by position in zone 
			local uP = anObject:getPoint()
			if (not cfxZones.isPointInsideZone(uP, theZone)) then 
				wiper.inventory = wiper.inventory .. "{" .. anObject:getName() .. "} "
			else 
				wiper.inventory = wiper.inventory .. anObject:getName() .. " "
			end
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
	-- WARNING: as of version 1.2.0 cat is now a TABLE!!!
	-- world.searchObjects supports cat tables according to https://wiki.hoggitworld.com/view/DCS_func_searchObjects
	
	if #cat > 0 then 
		-- now call search
		world.searchObjects(cat, args, wiper.objectHandler, collector)
		if #collector < 1 and (wiper.verbose or theZone.verbose) then
			trigger.action.outText("+++wpr: world search returned zero elements for <" .. theZone.name .. "> (cat=<" .. dcsCommon.array2string(theZone.wipeCategory) .. ">)",30)
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

			-- now also filter by position in zone 
			local uP = anObject:getPoint()
			if doWipe and (not cfxZones.isPointInsideZone(uP, theZone)) then 
				doWipe = false 
				if wiper.verbose or theZone.verbose then
					trigger.action.outText("+++wpr: <" .. anObject:getName() .."> not removed, outside zone <" .. theZone.name .. "> bounds.",30)
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
	else 
		if theZone.verbose or wiper.verbose then 
			trigger.action.outText("+++wpr: <" .. theZone:getName() .. "> has no categories to remove, skipping", 30)
		end
	end 
	
	-- declutter pass if requested 
	if theZone.declutter then 
		if theZone.verbose or wiper.verbose then 
			trigger.action.outText("+++wpr: decluttering <" .. theZone:getName() .. ">", 30)
		end 
		theZone:declutterZone()
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