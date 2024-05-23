income = {}
income.version = "0.0.0"
income.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"bank"
}

income.sources = {}


function income.addIncomeZone(theZone)
	income.sources[theZone.name] = theZone
end

function income.createIncomeWithZone(theZone)
	theZone.income = theZone:getNumberFromZoneProperty("income")
	-- we may add enablers and prohibitors and shared income 
	-- for example a building or upgrade must exist in order
	-- to provide income 
end

function income.getIncomeForZoneAndCoa(theZone, coa)
	-- process this zone's status (see which upgrades exist)
	-- and return the amount of income for this zone and coa 
	-- currently very primitive: own it, get it 
	if theZone.owner == coa then 
		return theZone.income 
	else 
		return 0
	end
end

function income.update()
	-- schedule next round 
	timer.scheduleFunction(income.update, {}, timer.getTime() + income.interval)
	
	local neuI, redI, blueI = income.neutral, income.red, income.blue
	-- base income 
--	bank.addFunds(0, income.neutral)
--	bank.addFunds(1, income.red)
--	bank.addFunds(2, income.blue)
	
	
	for idx, theZone in pairs(income.sources) do 
		local ni = income.getIncomeForZoneAndCoa(theZone, 0)
		local ri = income.getIncomeForZoneAndCoa(theZone, 1)
		local bi = income.getIncomeForZoneAndCoa(theZone, 2)
		redI = redI + ri 
		blueI = blueI + bi 
		neuI = neuI + ni 		
	end

	bank.addFunds(0, neuI)
	bank.addFunds(1, redI)
	bank.addFunds(2, blueI)

	
	if income.announceTicks then
--		trigger.action.outText(income.tickMessage, 30)
		local has, balance = bank.getBalance(0)
		local tick = string.gsub(income.tickMessage, "<i>", neuI)
		trigger.action.outTextForCoalition(0, "\n" .. tick .. "\nNew balance: §" .. balance .. "\n", 30)
		
		has, balance = bank.getBalance(1)
		tick = string.gsub(income.tickMessage, "<i>", redI)
		trigger.action.outTextForCoalition(1, "\n" .. tick .. "\nNew balance: §" .. balance .. "\n", 30)
		trigger.action.outSoundForCoalition(1, income.reportSound)
		
		has, balance = bank.getBalance(2)
		tick = string.gsub(income.tickMessage, "<i>", blueI)
		trigger.action.outTextForCoalition(2, "\n" .. tick .. "\nNew balance: §" .. balance .. "\n", 30)
		trigger.action.outSoundForCoalition(2, income.reportSound)
	end 
	
end 


function income.readConfigZone()
	local theZone = cfxZones.getZoneByName("incomeConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("incomeConfig") 
	end 
	
	income.base = theZone:getNumberFromZoneProperty ("base", 10)
	income.red = theZone:getNumberFromZoneProperty ("red", income.base)
	income.blue = theZone:getNumberFromZoneProperty ("blue", income.base)
	income.neutral = theZone:getNumberFromZoneProperty ("neutral", income.base)
	
	income.interval = theZone:getNumberFromZoneProperty("interval", 10 * 60) -- every 10 minutes 
	income.tickMessage = theZone:getStringFromZoneProperty("tickMessage", "New funds from income available: §<i>")
	income.announceTicks = theZone:getBoolFromZoneProperty("announceTicks", true)
	income.reportSound = theZone:getStringFromZoneProperty("reportSound", "<none>")
	
	income.verbose = theZone.verbose
end


function income.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("income requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("income", income.requiredLibs) then
		return false 
	end
	
	-- read config 
	income.readConfigZone()
	
	-- read income zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("income")
	for k, aZone in pairs(attrZones) do 
		income.createIncomeWithZone(aZone) -- process attributes
		income.addIncomeZone(aZone) -- add to list
	end
		 
	-- schedule first tick 
	timer.scheduleFunction(income.update, {}, timer.getTime() + income.interval)
	
	trigger.action.outText("income v" .. income.version .. " started.", 30)
	return true 
end

if not income.start() then 
	trigger.action.outText("income aborted: missing libraries", 30)
	income = nil 
end