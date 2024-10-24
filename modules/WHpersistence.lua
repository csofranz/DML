WHpersistence = {}
WHpersistence.version = "1.0.0"
WHpersistence.requiredLibs = {
	"dcsCommon",
	"cfxZones",
	"persistence",
}
--
-- load / save (game data)
--
function WHpersistence.saveData()
	local theData = {}
	local theWH = {}
	-- generate all WH data from all my airfields 
	local allMyBase = world:getAirbases()
	for idx, theBase in pairs(allMyBase) do 
		local name = theBase:getName()
		local WH = theBase:getWarehouse()
		local inv = WH:getInventory()
		theWH[name] = inv
	end 
	theData.theWH = theWH
	return theData, WHpersistence.sharedData -- second val currently nil  
end

function WHpersistence.loadData()
	if not persistence then return end 
	local shared = nil 
	local theData = persistence.getSavedDataForModule("WHpersistence")
	if (not theData) or not (theData.theWH) then 
		if WHpersistence.verbose then 
			trigger.action.outText("+++WHp: no save date received, skipping.", 30)
		end
		return
	end	
	-- set up all warehouses from data loaded
	for name, inv in pairs(theData.theWH) do 
		trigger.action.outText("+++restoring <" .. name .. ">", 30)
		local theBase = Airbase.getByName(name)
		if theBase then 
			local theWH = theBase:getWarehouse()
			if theWH then 
				-- we go through weapon, liquids and aircraft
				for idx, liq in pairs(inv.liquids) do 
					theWH:setLiquidAmount(idx, liq)
					trigger.action.outText(name .. ": Liq <" .. idx .. "> : <" .. liq .. ">", 30)
				end
				for ref, num in pairs(inv.weapon) do 
					theWH:setItem(ref, num)
				end
				for ref, num in pairs(inv.aircraft) do 
					theWH:setItem(ref, num)
				end
			else 
				trigger.action.outText(name .. ": no warehouse")
			end
		else 
			trigger.action.outText(name .. ": no airbase")
		end
	end 
end
--
-- config
--
function WHpersistence.readConfigZone()
	local theZone = cfxZones.getZoneByName("WHpersistenceConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("WHpersistenceConfig")
	end 
	WHpersistence.verbose = theZone.verbose
end
--
-- GO
--
function WHpersistence.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx WHpersistence requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Raise Flag", WHpersistence.requiredLibs)then return false end
	WHpersistence.readConfigZone()
	if persistence then 
		callbacks = {}
		callbacks.persistData = WHpersistence.saveData
		persistence.registerModule("WHpersistence", callbacks)
		-- now load my data 
		WHpersistence.loadData()
	end
	trigger.action.outText("cfx WHpersistence v" .. WHpersistence.version .. " started.", 30)
	return true 
end

if not WHpersistence.start() then 
	trigger.action.outText("cfx WHpersistence aborted: missing libraries", 30)
	WHpersistence = nil 
end