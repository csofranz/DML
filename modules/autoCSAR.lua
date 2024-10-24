autoCSAR = {}
autoCSAR.version = "2.2.1" 
autoCSAR.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
autoCSAR.killDelay = 2 * 60 
autoCSAR.counter = 31 -- any number is good, to kick-off counting
autoCSAR.trackedEjects = {} -- we start tracking on eject 

--[[--
	VERSION HISTORY
	1.0.0 - Initial Version
	1.1.0 - allow open water CSAR, fake pilot with GRG Soldier 
		  - can be disabled by seaCSAR = false 
	2.0.0 - OOP, code clean-up
	2.0.1 - fix for coalition change when ejected player changes coas or is forced to neutral 
	      - GC 
	2.1.0 - persistence support 
	2.2.0 - new noExploit option in config 
		  - no csar mission if pilot lands too close to airbase or farp 
		    and noExploit is on
	2.2.1 - DCS hardening for isExist
--]]--
autoCSAR.forbidden = {} -- indexed by name, contains point 
autoCSAR.killDist = 2100 -- meters from center of forbidden 

function autoCSAR.collectForbiddenZones()
	local allYourBase = world.getAirbases()
	for idx, aBase in pairs(allYourBase) do 
		-- collect airbases and farps, ignore ships 
		local desc = aBase:getDesc() 
		local cat = desc.category 
		if cat == 0 or cat == 1 then 
			local name = aBase:getName() 
			local p = aBase:getPoint()
			autoCSAR.forbidden[name] = p 
		end 
	end 
end 

function autoCSAR.removeGuy(args)
	local theGuy = args.theGuy
	if theGuy and theGuy:isExist() then  
		Unit.destroy(theGuy)
	end
end 

function autoCSAR.isOverWater(theUnit)
	local pPoint = theUnit:getPoint()
	pPoint.y = pPoint.z -- make it getSurfaceType compatible 
	local surf = land.getSurfaceType(pPoint)
	return surf == 2 or surf == 3
end

function autoCSAR.createNewCSAR(theUnit, coa)
	if not csarManager then 
		trigger.action.outText("+++aCSAR: CSAR Manager not loaded, aborting", 30)
	end	
	-- enter with unit from landing_after_eject event
	-- unit has no group 
	if not coa then 
		trigger.action.outText("+++autoCSAR: unresolved coalition, assumed neutral", 30)
		coa = 0 
	end 
	if coa == 0 then -- neutral
		trigger.action.outText("Neutral Pilot made it safely to ground.", 30)
		return 
	end
	if coa == 1 and not autoCSAR.redCSAR then 
		return -- we don't do red
	end
	if coa == 2 and not autoCSAR.blueCSAR then 
		return -- no blue rescue
	end
	-- noExploit burnup 
	if autoCSAR.noExploit then 
		local p = theUnit:getPoint()
		local burned = false 
		for name, aPoint in pairs(autoCSAR.forbidden) do
			local d = dcsCommon.distFlat(p, aPoint) 
			if  d < autoCSAR.killDist then 
				if autoCSAR.verbose then 
					trigger.action.outText("+++aCSAR: BURNED ejection touchdown: too close to <" .. name .. ">", 30)
				end
				burned = true
			end
		end 
		if burned then 
			trigger.action.outText("Pilot made it safely to ground, and was taken into custody immediately", 30)
			-- try and remove the guy now 
			Unit.destroy(theUnit)
			return 
		end 
	end	
	
	-- end burnup code 
	
	-- for later expansion
	local theGroup = theUnit:getGroup()
	
	-- if theUnit is over open water, it is killed instantly by DCS
	-- and must therefore be replaced with a stand-in 
	local pPoint = theUnit:getPoint()
	pPoint.y = pPoint.z -- make it getSurfaceType compatible 
	local surf = land.getSurfaceType(pPoint)
	local splashdown = false 
	
	if surf == 2 or surf == 3 then 
		trigger.action.outTextForCoalition(coa, "Parachute splashdown over open water reported!", 30)
		splashdown = true 
		-- create a replacement unit since pilot will be killed 
		local theBoyGroup = dcsCommon.createSingleUnitGroup(
			"Xray-" .. autoCSAR.counter, 
			"Soldier M4 GRG", -- "Soldier M4 GRG",
			pPoint.x, 
			pPoint.z, 
			0)
		local theSideCJTF = dcsCommon.coalition2county(coa) -- get the correct county CJTF 
		local theGroup = coalition.addGroup(theSideCJTF, Group.Category.GROUND, theBoyGroup)
		-- now access replacement unit 
		local allUnits = theGroup:getUnits()
		theUnit = allUnits[1] -- get first (and only) unit
	end
	-- create a CSAR mission now
	csarManager.createCSARForParachutist(theUnit, "Xray-" .. autoCSAR.counter, coa)
	autoCSAR.counter = autoCSAR.counter + 1
	
	-- schedule removal of pilot
	local args = {}
	args.theGuy = theUnit 
	if splashdown then
		timer.scheduleFunction(autoCSAR.removeGuy, args, timer.getTime() + 1) -- in one second
	else
		timer.scheduleFunction(autoCSAR.removeGuy, args, timer.getTime() + autoCSAR.killDelay)
	end 
end

-- we backtrack the pilot to their seat to their plane if they have ejector seat  
autoCSAR.pilotInfo = {}
function autoCSAR:onEvent(event)
	if not event.initiator then return end 
	local initiator = event.initiator 
	if event.id == 31 then -- landing_after_eject, does not happen at sea
		-- to prevent double invocations for same process
		-- check that we are still tracking this ejection 
		local uid = tonumber(initiator:getID())
		if autoCSAR.trackedEjects[uid] then
			trigger.action.outText("aCSAR: filtered double sea csar (player) event for uid = <" .. uid .. ">", 30)
			autoCSAR.trackedEjects[uid] = nil -- reset 
			return 
		end
		-- now get the coalition of the pilot.
		-- if pilot had an ejection seat, we need to get the seat's coa 
		local coa = initiator:getCoalition()
		for idx, info in pairs(autoCSAR.pilotInfo) do 
			if info.pilot == initiator then 
				coa = info.coa 
				info.matched = true -- for GC
			end
		end 
		autoCSAR.createNewCSAR(initiator, coa)	
	end

	if event.id == 33 then -- discard chair, connect pilot with seat 
		for idx, info in pairs(autoCSAR.pilotInfo) do 
			if info.seat == event.target then 
				info.pilot = initiator
			end
		end 
	end 

	if event.id == 6 then -- eject, start tracking, remember coa 
		local coa = event.initiator:getCoalition()
		-- see if pilot has ejector seat and prepare to connect one with the other 
		local info = nil 
		if event.target 
		and event.target.isExist 
		and event.target:isExist() then -- DCS hardening 
			info = {}
			info.coa = coa
			info.seat = event.target
			table.insert(autoCSAR.pilotInfo, info)
		end

		local uid = tonumber(event.initiator:getID())
		autoCSAR.trackedEjects[uid] = nil -- set to not handled (yet)
		
		if autoCSAR.seaCSAR then
			-- see if this happened over open water and immediately 
		    -- create a seaCSAR immediately
			if autoCSAR.isOverWater(initiator) then 
				autoCSAR.createNewCSAR(initiator, initiator:getCoalition())
				-- mark this one as completed 
				autoCSAR.trackedEjects[uid] = "processed" -- remember, so to not proc again 
				if info then info.matched = true end -- discard this one too in next GC 
			end
		end
	end

end

function autoCSAR.readConfigZone()
	local theZone = cfxZones.getZoneByName("autoCSARConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("autoCSARConfig") 
	end 
	autoCSAR.verbose = theZone.verbose 
	autoCSAR.redCSAR = theZone:getBoolFromZoneProperty("red", true)
	if theZone:hasProperty("redCSAR") then 
		autoCSAR.redCSAR = theZone:getBoolFromZoneProperty("redCSAR", true)
	end
	
	autoCSAR.blueCSAR = theZone:getBoolFromZoneProperty("blue", true)
	if theZone:hasProperty("blueCSAR") then 
		autoCSAR.blueCSAR = theZone:getBoolFromZoneProperty("blueCSAR", true)
	end

	autoCSAR.seaCSAR = theZone:getBoolFromZoneProperty("seaCSAR", true)

	autoCSAR.noExploit = theZone:getBoolFromZoneProperty("noExploit", false)
	autoCSAR.killDist = theZone:getNumberFromZoneProperty("killDist", 2100)
	
	if autoCSAR.verbose then 
		trigger.action.outText("+++aCSAR: read config", 30)
	end 
end

function autoCSAR.GC()
	timer.scheduleFunction(autoCSAR.GC, {}, timer.getTime() + 30 * 60) -- once every half hour
	local filtered = {}
	for idx, info in pairs(autoCSAR.pilotInfo) do 
		if info.matched then 
			-- skip it for next round
		else 
			table.insert(filtered, info)
		end 
	end 
	autoCSAR.pilotInfo = filtered
end

--
-- load/save
--

function autoCSAR.saveData()
	local theData = {}
	theData.counter = autoCSAR.counter 
	return theData, autoCSAR.sharedData
end

function autoCSAR.loadData()
	if not persistence then return end 
	local theData = persistence.getSavedDataForModule("autoCSAR", autoCSAR.sharedData)
	if not theData then 
		if autoCSAR.verbose then 
			trigger.action.outText("+++autoCSAR: no save data received, skipping.", 30)
		end
		return
	end
	if theData.counter then 
		autoCSAR.counter = theData.counter 
	end 
end

--
-- GO!
--
function autoCSAR.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx autoCSAR requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx autoCSAR", autoCSAR.requiredLibs) then
		return false 
	end
	
	-- read config 
	autoCSAR.readConfigZone()
	
	-- connect event handler
	world.addEventHandler(autoCSAR)
	
	-- do persistence
	if persistence then 
		-- sign up for persistence 
		callbacks = {}
		callbacks.persistData = autoCSAR.saveData
		persistence.registerModule("autoCSAR", callbacks)
		-- now load my data 
		autoCSAR.loadData()
	end
	
	-- collect forbidden zones if noExploit is active 
	autoCSAR.collectForbiddenZones()
	
	-- start GC
	timer.scheduleFunction(autoCSAR.GC, {}, timer.getTime() + 1)
	
	trigger.action.outText("cfx autoCSAR v" .. autoCSAR.version .. " started.", 30)
	return true 
end

-- let's go!
if not autoCSAR.start() then 
	trigger.action.outText("cfx autoCSAR aborted: missing libraries", 30)
	autoCSAR = nil 
end
