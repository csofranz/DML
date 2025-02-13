WHpersistence = {}
WHpersistence.version = "1.1.0"
WHpersistence.requiredLibs = {
	"dcsCommon",
	"cfxZones",
	"persistence",
}

--[[--
	Version History 
	1.0.0 - Initial version 
	1.1.0 - fixed an issue with net.lua2json 
		  - enable dynamic spawns can ferry to other airfields
			
--]]--

--
-- Update & monitor 
--
WHpersistence.lastState = nil 

function WHpersistence.update()
	timer.scheduleFunction(WHpersistence.update, nil, timer.getTime() + 1/WHpersistence.ups)
	trigger.action.outText("+++WHp: start update", 30)
	local newState = WHpersistence.getCurrentState()
	-- now look for discrepacies to last state 
	local oldState = WHpersistence.lastState
	-- iterate all bases 
	local hasChange = false
	for name, inv in pairs(newState) do 
		local oldBaseInv = oldState[name]
		-- WH has three entries: liquids, weapon and aircraft 
		-- compare iarcraft stats 
		if not inv.aircraft then 
			trigger.action.outText("+++WHp: NEW STATE: no aircraft data for <" .. name .. ">", 30)
		else 
			for ref, num in pairs(inv.aircraft) do 
				oldNum = oldBaseInv.aircraft[ref]
				trigger.action.outText("AF <" .. name .. ">, AC: <" .. ref .. "> -- " .. num .. ".", 30)
				if oldNum ~= num then
					if not oldNum then oldNum = "NIL" end 
					trigger.action.outText("+++WHp: WH <" .. name .. ">: aircraft type <" .. ref .. "> old num <" .. num .. ">, new <" .. oldNum .. ">", 30)
					hasChange = true 
				end 
			end
		end
	end
	-- reverse: has a plane left?
	for name, inv in pairs(oldState) do 
		local oldBaseInv = newState[name]
		-- WH has three entries: liquids, weapon and aircraft 
		-- compare iarcraft stats 
		if not inv.aircraft then 
			trigger.action.outText("+++WHp: OLD STATE: no aircraft data for <" .. name .. ">", 30)
		else 
			for ref, num in pairs(inv.aircraft) do 
				oldNum = oldBaseInv.aircraft[ref]
				if not oldNum then
					trigger.action.outText("+++WHp: WH <" .. name .. ">: aircraft type <" .. ref .. "> REMOVED ENTIRELY", 30)
					hasChange = true 
				end 
			end
		end
	end
	
	if hasChange then 
		trigger.action.outText("+++WHp: has change", 30)
	end 
	WHpersistence.lastState = newState
end

function WHpersistence.getCurrentState()
	local theWH = {}
	-- generate all WH data from all my airfields 
	local allMyBase = world:getAirbases()
	for idx, theBase in pairs(allMyBase) do 
		local name = theBase:getName()
		local WH = theBase:getWarehouse()
		local inv = WH:getInventory()
		-- transcribe for bug in lua2json
		local l0 = 0; local l1 = 0; local l2 = 0; local l3 = 0 
		if inv.liquids[0] then l0 = inv.liquids[0] end 
		if inv.liquids[1] then l1 = inv.liquids[1] end
		if inv.liquids[2] then l2 = inv.liquids[2] end
		if inv.liquids[3] then l3 = inv.liquids[3] end
		bLiq = {["A"] = l0, -- lua2json can't handle a[0]
				["B"] = l1,
				["C"] = l2,
				["D"] = l3,}
		inv.bLiq = bLiq
		theWH[name] = inv
	end 
	trigger.action.outText("+++WHp: read state", 30)
	return theWH
end

--
-- load / save (game data)
--
function WHpersistence.saveData()
	local theData = {}
	local theWH = {}
	theData.theWH = WHpersistence.getCurrentState() -- theWH
	if WHpersistence.verbose then 
		trigger.action.outText("+++WHp: saving data", 30)
	end 
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
	if WHpersistence.verbose then 
		trigger.action.outText("+++WHp: restoring from file", 30)
	end 
	local origState = WHpersistence.getCurrentState()
	-- set up all warehouses from data loaded
	-- WARNING: if original was set, but saved emptpy,
	-- we must now erase the original!
	for name, inv in pairs(theData.theWH) do 
--		trigger.action.outText("+++restoring WH <" .. name .. ">", 30)
		local theBase = Airbase.getByName(name)
		if theBase then 
			local theWH = theBase:getWarehouse()
			if theWH then 
				-- we go through weapon, liquids and aircraft
				-- do liqids "manually" 
				if inv.bLiq then 
					theWH:setLiquidAmount(0, inv.bLiq["A"])
					theWH:setLiquidAmount(1, inv.bLiq["B"])
					theWH:setLiquidAmount(2, inv.bLiq["C"])
					theWH:setLiquidAmount(3, inv.bLiq["D"])
				else 
					trigger.action.outText("+++WHPersistence: WARNING - legacy save data, will not set liquids for <" .. name .. ">", 30)
				end 
				
				for ref, num in pairs(inv.weapon) do 
					theWH:setItem(ref, num)
				end
				for ref, num in pairs(inv.aircraft) do 
					theWH:setItem(ref, num)
					if WHpersistence.verbose then trigger.action.outText(name .. ": Setting # of Aircraft <" .. ref .. "> to <" .. num .. ">", 30) end 
				end
			else 
				trigger.action.outText(name .. ": no warehouse")
			end
		else 
			trigger.action.outText(name .. ": no airbase")
		end
	end 
	local newInv = theData.theWH 
	for name, inv in pairs(origState) do 
		local bInv = newInv[name] -- from file!
		local theBase = Airbase.getByName(name)
		local theWH = theBase:getWarehouse() -- in case we neet to change 
		if theWH then 
			for ref, num in pairs(inv.weapon) do 
				if not bInv.weapon[ref] then 
					theWH:setItem(ref, 0)
					if WHpersistence.verbose then  trigger.action.outText(name .. ": Weapon <" .. ref .. "> : REMOVED", 30) end 
				end
			end
			for ref, num in pairs(inv.aircraft) do 
				if not bInv.aircraft[ref] then 
					theWH:setItem(ref, 0)
					if WHpersistence.verbose then  trigger.action.outText(name .. ": Aircraft <" .. ref .. "> removed", 30) end 
				end 
			end
		else 
			trigger.action.outText(name .. " can't access this airbase", 30)
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
	WHpersistence.monitor = theZone:getBoolFromZoneProperty("monitor", false)
	WHpersistence.ups = theZone:getNumberFromZoneProperty("ups", 0.1) -- every 10 seconds 
end
--
-- GO
--
function WHpersistence.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx WHpersistence requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx WH Persistence", WHpersistence.requiredLibs)then return false end
	WHpersistence.readConfigZone()
	if persistence then 
		callbacks = {}
		callbacks.persistData = WHpersistence.saveData
		persistence.registerModule("WHpersistence", callbacks)
		-- now load my data 
		WHpersistence.loadData()
	end
	
	if WHpersistence.monitor then 
		WHpersistence.lastState = WHpersistence.getCurrentState()
		timer.scheduleFunction(WHpersistence.update, nil, timer.getTime() + 1/WHpersistence.ups)
	end
	trigger.action.outText("cfx WHpersistence v" .. WHpersistence.version .. " started.", 30)
	return true 
end

if not WHpersistence.start() then 
	trigger.action.outText("cfx WHpersistence aborted: missing libraries", 30)
	WHpersistence = nil 
end