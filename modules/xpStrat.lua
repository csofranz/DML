xpStrat = {}
-- AI strategy module for expansion.
xpStrat.version = "0.0.0"
xpStrat.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
	"milHelo", -- for helo attack and capture missions 
}
xpStrat.zones = {} -- all the zones that interest me 
xpStrat.AI = {} -- red, blue -- if true, that side has pure ai 

function xpStrat.addXPZone(theZone)
	xpStrat.zones[theZone.name] = theZone
end

--
-- Strategy 
--
function xpStrat.fullAIStrategy(coa, cname)
	if xpStrat.verbose then
		trigger.action.outText("FULL AI Strategy for (" .. coa .. "/" .. cname .. ")", 30)
	end 
end

function xpStrat.getMilHSource(coa, msnType, nearZone)
	if not msnType then 
		msnType = dcsCommon.pickRandom(milHelo.missionTypes)
	elseif msnType == "*" then 
		msnType = nil -- get all.
	end
	
	-- get all sources for coa and msnTypes
	local sources = milHelo.getMilSources(coa, msnType)
	if #sources < 1 then 
		trigger.action.outText("Strat: no sources found for <" .. msnType .. "> helo mission", 30)
		return nil 
	end 
	
	local theSource = nil 
	if nearZone then 
		theSource = nearZone:getClosestZone(sources)
	else
		-- pick one by random
		theSource = dcsCommon.pickRandom(sources)
	end 
	return theSource 
end

function xpStrat.createHeloMission(coa, msnType, theSource, theTarget) -- msnType = "*" means any, nil means pick random 
	if not theSource then 
		theSource = xpStrat.getMilHSource(coa, msnType)
	end 
	if not theSource then 
		trigger.action.outText("Strat: cannot find coa <" .. coa .. "> source for <" .. msnType .. "> mission", 30)
		return nil 
	end 
	msnType = theSource.msnType 
	
	-- now gather all destinations 
	if not theTarget then 
		local targets = milHelo.getMilTargets(coa)
		if #targets < 1 then 
			trigger.action.outText("Strat: no destinations for side " .. side, 30)
			return nil 
		end 
		
		-- TODO: choose nearest target to source  
		-- and prefer neutral 
		theTarget = theSource:getClosestZone(targets)--targets[1]
	end 
	
	-- if we get here, we have a source and target 
	
	trigger.action.outText("Strat: identified Coa <" .. coa .. "> - Starting <" .. msnType .. "> mission from <" .. theSource.name .. "> to <" .. theTarget.name .. ">)", 30)
	
	return theSource, theTarget, msnType
end

function xpStrat.playerAIStrategy(coa, cname)
	if xpStrat.verbose then
		trigger.action.outText("Player-assisted AI Strategy for (" .. coa .. "/" .. cname .. ")", 30)
	end 
	
	-- strategy in general (ha!, pun) 
	-- check which missions are done first 
	-- select one mission unless still running and initiate own support flights
	-- select one aggressive flight and start it, no matter what 
end

function xpStrat.update()
	-- schedule next round 
	timer.scheduleFunction(xpStrat.update, {}, timer.getTime() + xpStrat.interval)
	
	local sides = {"red", "blue"}
	for idx, sideName in pairs(sides) do 
		local coa = 1
		if sideName == "blue" then coa = 2 end 
	
		if xpStrat.AI[sideName] then 
			xpStrat.fullAIStrategy(coa, sideName)
		else 
			xpStrat.playerAIStrategy(coa, sideName)
		end
	end
end



function xpStrat.readConfigZone()
	local theZone = cfxZones.getZoneByName("expansionConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("expansionConfig") 
	end
	xpStrat.redAI = theZone:getBoolFromZoneProperty("redAI", true) -- is red player or AI?
	xpStrat.AI["red"] = xpStrat.redAI
	xpStrat.blueAI = theZone:getBoolFromZoneProperty("blueAI", true) -- is red player or AI?
	xpStrat.AI["blue"] = xpStrat.blueAI

	xpStrat.interval = theZone:getNumberFromZoneProperty("interval", 600)
	xpStrat.difficulty = theZone:getNumberFromZoneProperty("difficulty", 1)
	
	xpStrat.verbose = theZone.verbose 
end


function xpStrat.init()
	-- gather data etc

	trigger.action.outText("'Expansion' Core v" .. xpStrat.version .. "  (" .. dcsCommon.getMapName() .. ") started.", 30)
	local msg = ""
	if xpStrat.redAI then msg = msg .. "\nRed side controlled by AI General" 
	else msg = msg .. "\nRed side controlled by Player-Assisted General" end
	if xpStrat.blueAI then msg = msg .. "\nBlue side controlled by AI General" 
	else msg = msg .. "\nBlue side controlled by Player-Assisted General" end
	msg = msg .. "\ndifficulty level set to " .. xpStrat.difficulty
	msg = msg .. "\n"
	trigger.action.outText(msg, 30)
	
	-- schedule first round of AI in 10 seconds 
	timer.scheduleFunction(xpStrat.update, {}, timer.getTime() + 10)
end

function xpStrat.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("xpStrat requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("xpStrat", xpStrat.requiredLibs) then
		return false 
	end
	
	-- read config 
	xpStrat.readConfigZone()
	
	-- read income zones 
--[[--	local attrZones = cfxZones.getZonesWithAttributeNamed("income")
	for k, aZone in pairs(attrZones) do 
		income.createIncomeWithZone(aZone) -- process attributes
		income.addIncomeZone(aZone) -- add to list
	end
--]]--		 
	-- schedule init for 5 seconds after mission start
	timer.scheduleFunction(xpStrat.init, {}, timer.getTime() + 5)
	
	trigger.action.outText("xpStrat v" .. xpStrat.version .. " started.", 30)
	return true 
end

if not xpStrat.start() then 
	trigger.action.outText("xpStrat aborted: missing libraries", 30)
	xpStrat = nil 
end