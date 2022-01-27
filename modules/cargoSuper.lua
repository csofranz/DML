cargoSuper = {}
cargoSuper.version = "1.1.1"
--[[--
version history
	1.0.0 - initial version
	1.1.0 - removeMassObjectFrom supports name directly for mass object 
		  - cargoSuper tracks all mass objects 
		  - deleteMassObject() 
		  - removeMassObjectFrom supports forget option
		  - createMassObject supports auto-gen UUID name 
		  - removeAllMassForCargo renamed to removeAllMassForCategory
		  - category default "cSup!DefCat"
		  - getAllCategoriesFor alias for getAllCargos 
		  - getManifestForCategory alias for getManifestFor
		  - removeAllMassFor()
	1.1.1 - deleteMassObject corrected index bug 
	
CargoSuper manages weigth for a logical named unit. Weight can be added 
to arbitrary categories like 'passengers', 'cargo' or "whatever". In order 
to add weight to a unit, first create a massObject through createMassObject
and then add that mass object to the unit via addMassTo, with a category name
you can get access to massobjects via getMassObjects  
When done, you can remove the mass object via removeMassObject or 
removeAll

To get a unit's total weight, use getTotalMass() 

IMPORTANT:
This module does ***N*O*T*** call  trigger.action.setUnitInternalCargo
you must do that yourself

--]]--
cargoSuper.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	             -- pretty stupid to check for this since we 
				 -- need common to invoke the check, but anyway
	"nameStats", -- generic data module for weight 
}

cargoSuper.cargos = {}
cargoSuper.massObjects = {}

-- create a massObject. reference object can be used to store 
-- anything that links an associated object:getSampleRate()
-- massName can be anything but must be unique as it is used to store. pass nil for UUID-created name 
function cargoSuper.createMassObject(massInKg, massName, referenceObject)
	local theObject = {}
	theObject.mass = massInKg
	theObject.name = massName 
	theObject.ref = referenceObject
	
	if not massName then 
		massName = dcsCommon.uuid("cSup!N")
	end
	
	local existingMO = cargoSuper.massObjects[massName]
	if existingMO then 
		trigger.action.outText("+++cSuper: WARNING - " .. massName .. " exists already, overwritten!", 30)
	end
	cargoSuper.massObjects[massName] = theObject
	return theObject
end 

function cargoSuper.deleteMassObject(massObject) 
	if not massObject then return end 
	local theName = "" 
	if type(massObject) == "string" then 
		theName = massObject 
	else 
		theName = massObject.name 
	end 
	cargoSuper.massObjects[theName] = nil -- 1.1.1 corrected to theName from massName 
end

function cargoSuper.addMassObjectTo(name, category, theMassObject)
	if not theMassObject then return end
	if not category then category = "cSup!DefCat" end 
	-- use nameStats to access private data table
	local theMassTable = nameStats.getTable(name, category, cargoSuper.cargos)
	theMassTable[theMassObject.name] = theMassObject
end

function cargoSuper.removeMassObjectFrom(name, category, theMassObject, forget)
	if not theMassObject then return end
	if not category then category = "cSup!DefCat" end 
	if not forget then forget = true end 
	-- use nameStats to access private data table
	-- return the data table stored under category. category *can* be nil 
	-- v1.0.1 can also provide mass object name 
	-- instead of mass object itself. no check!!
	local moName = ""
	if type(theMassObject) == "string" then
		moName = theMassObject
	else 
		moName = theMassObject.name 
	end
	local theMassTable = nameStats.getTable(name, category, cargoSuper.cargos)
	theMassTable[moName] = nil
	if forget then 
		cargoSuper.deleteMassObject(theMassObject)
	end
end

-- DO NOT PUBLISH. Provided only for backwards compatibility
function cargoSuper.removeAllMassForCargo(name, catergory)
	if not category then category = "cSup!DefCat" end 
	nameStats.reset(name, category, cargoSuper.cargos)
end

-- alias for removeAllMassForCargo
function cargoSuper.removeAllMassForCategory(name, catergory)
	cargoSuper.removeAllMassForCargo(name, catergory)
end

function cargoSuper.removeAllMassFor(name)
	if not name then return end 
	local categories = nameStats.getAllPathes(name, cargoSuper.cargos)
	for idx, cat in pairs(categories) do
		cargoSuper.removeAllMassForCategory(name, cat)
	end
end

-- returns all cargo categories for name 
-- DO NOT PUBLISH. BAD NAMING
function cargoSuper.getAllCargosFor(name)
	local categories = nameStats.getAllPathes(name, cargoSuper.cargos)
	return categories
end

-- alias for badly named method above
function cargoSuper.getAllCategoriesFor(name)
	cargoSuper.getAllCargosFor(name)
end

-- return all mass objects that are in name, category as table
-- that can be accessed as *array*
-- DO NOT PUBLISH. NAMING IS BAD
function cargoSuper.getManifestFor(name, category)
	if not category then category = "cSup!DefCat" end 
	local theMassTable = nameStats.getTable(name, category, cargoSuper.cargos)
	return dcsCommon.enumerateTable(theMassTable)
end

-- alias for badly named method above
function cargoSuper.getManifestForCategory(name, category)
	cargoSuper.getManifestFor(name, category)
end

function getManifestTextFor(name, category, includeTotal)
	if not category then category = "cSup!DefCat" end 
	local theMassTable = cargoSuper.getManifestFor(name, category)
	local desc = ""
	local totalMass = 0
	local isFirst = true
	for idx, massObject in pairs(theMassTable) do 
		if not isFirst then 
			desc = desc .. "\n"
		end
		totalMass = totalMass + massObject.mass
		desc = desc .. massObject.name .. " (" .. massObject.mass .. "kg)"
		isFirst = false
	end	
	if includeTotal and (isFirst == false) then 
		-- we only do this if we have at least one (isFirst is false)
		desc = desc .. "\nTotal Weight: " .. totalMass .. "kg"
	end
	return desc
end

function cargoSuper.calculateTotalMassForCategory(name, category)
	if not category then category = "cSup!DefCat" end 
	theMasses = cargoSuper.getManifestFor(name, category)
	local totalMass = 0
	for massName, massObject in pairs(theMasses) do
		totalMass = totalMass + massObject.mass
	end
	return totalMass
end

function cargoSuper.calculateTotalMassFor(name)
	local allCategories = cargoSuper.getAllCargosFor(name)
	local totalMass = 0
	for idx, category in pairs(allCategories) do 
		totalMass = totalMass + cargoSuper.calculateTotalMassForCategory(name, category)
	end	
	return totalMass
end

function cargoSuper.start()
	-- make sure we have loaded all relevant libraries 
	if not dcsCommon.libCheck("cfx CargoSuper", cargoSuper.requiredLibs) then 
		trigger.action.outText("cf/x CargoSuper aborted: missing libraries", 30)
		return false 
	end
	
	trigger.action.outText("cf/x CargoSuper v" .. cargoSuper.version .. " loaded", 30)
	return true 
	
end

-- go go go 
if not cargoSuper.start() then 
	cargoSuper = nil
end