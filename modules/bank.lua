bank = {}
bank.version = "0.0.0"
bank.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
bank.acts = {}

function bank.addFunds(act, amt)
	if not act then act = "!!NIL!!" end 
	if act == 1 then act = "red" end 
	if act == 2 then act = "blue" end 
	if act == 0 then act = "neutral" end 
	act = string.lower(act)
	
	local curVal = bank.acts[act] 
	if not curVal then 
		trigger.action.outText("+++Bank: no account <" .. act .. "> found. No transaction", 30)
		return false
	end 
	
	bank.acts[act] = curVal + amt 
	return true 
end

function bank.withdawFunds(act, amt)
	if not act then act = "!!NIL!!" end 
	if act == 1 then act = "red" end 
	if act == 2 then act = "blue" end 
	if act == 0 then act = "neutral" end 
	act = string.lower(act)
	
	local curVal = bank.acts[act] 
	if not curVal then 
		trigger.action.outText("+++Bank: no account <" .. act .. "> found. No transaction", 30)
		return false 
	end 
	if amt > curVal then return false end 
	
	bank.acts[act] = curVal - amt
	return true 
end

function bank.getBalance(act)
	if not act then act = "!!NIL!!" end 
	if act == 1 then act = "red" end 
	if act == 2 then act = "blue" end 
	if act == 0 then act = "neutral" end 
	act = string.lower(act)
	
	local curVal = bank.acts[act] 
	if not curVal then 
		trigger.action.outText("+++Bank: no account <" .. act .. "> found. No transaction", 30)
		return false, 0
	end 
	
	return true, curVal
end

function bank.openAccount(act, amount)
	if not amount then amount = 0 end 
	if bank.acts[act] then return false end -- account exists 
	bank.acts[act] = amount 
	return true 
end

function bank.readConfigZone()
	local theZone = cfxZones.getZoneByName("bankConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("bankConfig") 
	end 
	
	-- set initial balances 
	bank.red = theZone:getNumberFromZoneProperty ("red", 1000)
	bank.blue = theZone:getNumberFromZoneProperty ("blue", 1000)
	bank.neutral = theZone:getNumberFromZoneProperty ("neutral", 1000)

	bank.acts["red"] = bank.red 
	bank.acts["blue"] = bank.blue 
	bank.acts["neutral"] = bank.neutral 
	
	bank.verbose = theZone.verbose
end

function bank.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("bank requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("bank", bank.requiredLibs) then
		return false 
	end
	
	-- read config 
	bank.readConfigZone()
		
	trigger.action.outText("bank v" .. bank.version .. " started.", 30)
	return true 
end

if not bank.start() then 
	trigger.action.outText("bank aborted: missing libraries", 30)
	bank = nil 
end