tacan = {}
tacan.version = "1.1.0"
--[[--
Version History
 1.0.0 - initial version 
 1.1.0 - OOP cfxZones 
 
--]]--
tacan.verbose = false  
tacan.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
tacan.tacanZones = {}


function tacan.createTacanZone(theZone)
	theZone.onStart = theZone:getBoolFromZoneProperty("onStart", true)
	local channels = theZone:getStringFromZoneProperty("channel", "1")
	theZone.channels = dcsCommon.numberArrayFromString(channels, 1)
	if theZone.verbose or tacan.verbose then 
		trigger.action.outText("+++tcn: new tacan <" .. theZone.name .. "> for channels [" .. dcsCommon.array2string(theZone.channels, ", ") .. "]", 30)
	end
	
	local mode = theZone:getStringFromZoneProperty("mode", "X")
	mode = string.upper(mode)
	theZone.modes = dcsCommon.flagArrayFromString(mode) 
	if theZone.verbose or tacan.verbose then 
		trigger.action.outText("+++tcn: modes [" .. dcsCommon.array2string(theZone.modes, ", ") .. "]", 30)
	end
	theZone.coa = theZone:getCoalitionFromZoneProperty("tacan", 0)
	theZone.heading = theZone:getNumberFromZoneProperty("heading", 0) 
	theZone.heading = theZone.heading * 0.0174533 -- convert to rads 
	local callsign = theZone:getStringFromZoneProperty("callsign", "TXN")
	callsign = string.upper(callsign)
	theZone.callsigns = dcsCommon.flagArrayFromString(callsign)
	if theZone.verbose or tacan.verbose then 
		trigger.action.outText("+++tcn: callsigns [" .. dcsCommon.array2string(theZone.callsigns) .. "]", 30)
	end
	theZone.rndLoc = theZone:getBoolFromZoneProperty("rndLoc", false)
	theZone.triggerMethod = theZone:getStringFromZoneProperty( "triggerMethod", "change")
	if theZone:hasProperty("deploy?") then 
		theZone.deployFlag = theZone:getStringFromZoneProperty("deploy?", "<none>")
		theZone.lastDeployFlagValue = theZone:getFlagValue(theZone.deployFlag)
	end
	if (not theZone.deployFlag) and (not theZone.onStart) then 
		trigger.action.outText("+++tacan: WARNING: tacan zone <> is late activation and has no activation flag, will never activate.", 30)
	end	
	
	theZone.spawnedTACANS = {} -- for GC and List
	theZone.preWipe = theZone:getBoolFromZoneProperty("preWipe", true)
	
	if theZone:hasProperty("destroy?") then 
		theZone.destroyFlag = theZone:getStringFromZoneProperty( "destroy?", "<none>")
		theZone.lastDestroyFlagValue = theZone:getFlagValue(theZone.destroyFlag)	
	end
	
	if theZone:hasProperty("c#") then 
		theZone.channelOut = theZone:getStringFromZoneProperty("C#", "<none>")
	end
	
	theZone.announcer = theZone:getBoolFromZoneProperty("announcer", false)
	
	-- interface to groupTracker 
	if theZone:hasProperty("trackWith:") then 
		theZone.trackWith = theZone:getStringFromZoneProperty( "trackWith:", "<None>")
	end
	
	-- see if we need to deploy now 
	if theZone.onStart then 
		tacan.TacanFromZone(theZone, true) -- true = silent
	end 
end

-- hand off to tracker 
-- from cloneZones
function tacan.handoffTracking(theGroup, theZone)
	if not groupTracker then 
		trigger.action.outText("+++tacan: <" .. theZone.name .. "> attribute 'trackWith:' requires groupTracker module", 30) 
		return 
	end
	local trackerName = theZone.trackWith
	-- now assemble a list of all trackers
	if tacan.verbose or theZone.verbose then 
		trigger.action.outText("+++tacan: tacan tracked with: " .. trackerName, 30)
	end 
	
	local trackerNames = {}
	if dcsCommon.containsString(trackerName, ',') then
		trackerNames = dcsCommon.splitString(trackerName, ',')
	else 
		table.insert(trackerNames, trackerName)
	end
	for idx, aTrk in pairs(trackerNames) do 
		local theName = dcsCommon.trim(aTrk)
		if theName == "*" then theName = theZone.name end 
		local theTracker = groupTracker.getTrackerByName(theName)
		if not theTracker then 
			trigger.action.outText("+++tacan: <" .. theZone.name .. ">: cannot find tracker named <".. theName .. ">", 30) 
		else 
			groupTracker.addGroupToTracker(theGroup, theTracker)
			 if tacan.verbose or theZone.verbose then 
				trigger.action.outText("+++tacan: added " .. theGroup:getName() .. " to tracker " .. theName, 30)
			 end
		end 
	end 
end

-- create a tacan
function tacan.createTacanInZone(theZone, channel, mode, callsign)
	local point = cfxZones.getPoint(theZone)
	local name = theZone.name
	local heading = theZone.heading 
	local unitID = dcsCommon.numberUUID()
	if theZone.rndLoc then 
		point = cfxZones.createRandomPointInZone(theZone)
	end
	local data = tacan.buildTacanData(name, channel, mode, callsign, point, unitID, heading)
	if theZone.verbose or tacan.verbose then 
		trigger.action.outText("+++tcn: new TACAN for <" .. theZone.name .. ">: ch<" .. channel .. ">, mode <" .. mode .. ">, call <" .. callsign .. ">", 30)
	end
	data.thePoint = point -- save location 
	--local s = dcsCommon.dumpVar2Str("data", data)
	local coa = theZone.coa -- neutral
	local cty = dcsCommon.getACountryForCoalition(coa)
	local theCopy = dcsCommon.clone(data)
	local theGroup = coalition.addGroup(cty, Group.Category.GROUND, data)
	
	-- handoff for tracking
	if theZone.trackWith then 
		tacan.handoffTracking(theGroup, theZone) 
	end
	
	-- add to my spawns for GC to watch over 
	local t = {}
	t.activeMode = mode 
	t.activeCallsign = callsign
	t.activeChan = channel 
	t.theGroup = theGroup 
	t.theData = theCopy 
	table.insert(theZone.spawnedTACANS, t)
	
	-- run a GC cycle 
	tacan.GC(true)
	return theGroup, theCopy
end

function tacan.TacanFromZone(theZone, silent)
	local channel = tonumber(dcsCommon.pickRandom(theZone.channels))
	local mode = dcsCommon.pickRandom(theZone.modes)
	local callsign = dcsCommon.pickRandom(theZone.callsigns)
	
	if theZone.preWipe and theZone.activeTacan then 
		Group.destroy(theZone.activeTacan)
		theZone.activeTacan = nil 
	end
	
	local theGroup, data = tacan.createTacanInZone(theZone, channel, mode, callsign)
	theZone.activeTacan = theGroup 
	theZone.activeChan = channel 
	if theZone.channelOut then 
		trigger.action.setUserFlag(theZone.channelOut, channel)
	end
		
	theZone.activeMode = mode 
	theZone.activeCallsign = callsign
	theZone.activeName = data.name 
	if theGroup then 
		if theZone.verbose or tacan.verbose then 
			trigger.action.outText("+++tcn: created tacan <" .. data.name ..">", 30)
		end
	end
	
	if (not silent) and theZone.announcer then 
		local str = "NOTAM: Deployed new TACAN " .. theZone.name .. " <" .. callsign .. ">, channel " .. channel .. mode .. ", active now"
		if theZone.coa == 0 then 
			trigger.action.outText(str, 30)
		else 
			trigger.action.outTextForCoalition(theZone.coa, str, 30)
		end
	end
end

function tacan.destroyTacan(theZone, announce)
	if theZone.activeTacan then 
		Group.destroy(theZone.activeTacan) -- only destroys last allocated
		theZone.activeTacan = nil 
		
	if announce then 
		local coa = theZone.coa 
		local str = "NOTAM: TACAN " .. theZone.name .. " <" .. theZone.activeCallsign .. "> deactivated"
		if coa == 0 then 
			trigger.action.outText(str, 30)
		else 
			trigger.action.outTextForCoalition(coa, str, 30)
		end
	end
		
	end
	if theZone.channelOut then 
		trigger.action.setUserFlag(theZone.channelOut, 0)
	end
end

-- create a TACAN group for the requested TACAN 
function tacan.buildTacanData(name, channel, mode, callsign, point, unitID, heading) -- point = (xyz)!
	if not heading then heading = 0 end 
	if not mode then mode = "X" end 
	mode = string.upper(mode)
	local x = point.x 
	local y = point.z 
	local alt = land.getHeight({x = x, y = y})
	local g = {} -- group 
	g.name = name .. dcsCommon.numberUUID()
	g.x = x 
	g.y = y 
	g.tasks = {}
	g.task = "Ground Nothing"
	local r = {} -- group.route 
	g.route = r 
	local p = {} -- group.route.points 
	r.points = p -- 
	local p1 = {} -- group.route.points[1] 
	p[1] = p1
	p1.alt = alt + 3 
	p1.x = x 
	p1.y = y 
	local t = {} -- group.route.points[1].task 
	p1.task = t 
	t.id = "ComboTask"
	local params = {} -- group.route.points[1].task.params 
	t.params = params
	local tasks = {} --  group.route.points[1].task.params.tasks
	params.tasks = tasks
	local t1 = {} --  group.route.points[1].task.params.tasks[1]
	tasks[1] = t1
	
	t1.enabled = true 
	t1.auto = false 
	t1.id = "WrappedAction"
	t1.number = 1 
	local pm = {} --  group.route.points[1].task.params.tasks[1].params
	t1.params  = pm 
	local a = {} --  group.route.points[1].task.params.tasks[1].params.action 
	pm.action = a 
	a.id = "ActivateBeacon"
	local ps = {} -- group.route.points[1].task.params.tasks[1].params.action.params 
	a.params = ps 
	ps.type = 4 
	ps.AA = false 
	ps.unitID = unitID
	ps.modeChannel = mode 
	ps.channel = channel
	ps.system = 18 -- mysterious 
	ps.callsign = callsign
	ps.bearing = true 
	ps.frequency = dcsCommon.tacan2freq(channel, mode)
	if tacan.verbose then 
		trigger.action.outText("tacan channel <" .. channel .. "> = freq <" .. ps.frequency .. ">", 30)
	end 
	
	-- now build unit 
	local u = {}
	g.units = u 
	local u1 = {}
	u[1] = u1 
	u1.skill = "High" 
	u1.type = "TACAN_beacon"
	u1.x = x 
	u1.y = y 
	u1.name = "u_" .. g.name 
	u1.unitId = unitID
	
	return g -- return data block 
end

--
-- Update 
--
function tacan.update()
	timer.scheduleFunction(tacan.update, {}, timer.getTime() + 1)

	for tName, theZone in pairs(tacan.tacanZones) do 
		-- was start called? 
		if cfxZones.testZoneFlag(theZone, theZone.deployFlag, theZone.triggerMethod, "lastDeployFlagValue") then 
			-- we want to deploy and start the tacan.
			-- first test if one is still up and running 
			if theZone.activeTacan and theZone.preWipe then 
				tacan.destroyTacan(theZone, false)
			end
			tacan.TacanFromZone(theZone)
		end
		
		if cfxZones.testZoneFlag(theZone, theZone.destroyFlag, theZone.triggerMethod, "lastDestroyFlagValue") then 
			tacan.destroyTacan(theZone, theZone.announcer)
		end
	end
	
end


function tacan.GC(singleCall)
	if singleCall then
		if tacan.verbose then 
			trigger.action.outText("+++tacan: single-pass GC invoked", 30)
		end
	else 
		timer.scheduleFunction(tacan.update, nil, timer.getTime() + 60) 
	end 
	for tName, theZone in pairs(tacan.tacanZones) do 
		local filteredTACANS = {}
		for idx, theActive in pairs(theZone.spawnedTACANS) do 
			-- check if this tacan still exists 
			local name = theActive.theData.name -- group name 
			local theGroup = Group.getByName(name)
			if theGroup and Group.isExist(theGroup) then 
				table.insert(filteredTACANS, theActive)
			else 
				if tacan.verbose then 
					trigger.action.outText("+++tacan: filtered <" .. name .. ">: no longer exist", 30)
				end
			end
		end
		theZone.spawnedTACANS = filteredTACANS 
	end
end

--
-- comms: List TACAN radio command 
--
function tacan.installComms()
	tacan.redC = missionCommands.addCommandForCoalition(1, "Available TACAN stations", nil, tacan.listTacan, 1)
	tacan.blueC = missionCommands.addCommandForCoalition(2, "Available TACAN stations", nil, tacan.listTacan, 2)
	
end

function tacan.listTacan(side)
	timer.scheduleFunction(tacan.doListTacan, side, timer.getTime() + 0.1)
end

function tacan.doListTacan(args) 
	tacan.GC(true) -- force GC, once.
	
	-- collect all neutral and same (as in args)-side tacans 
	local theTs = {}
	for name, theZone in pairs(tacan.tacanZones) do 
		if theZone.coa == 0 or theZone.coa == args then 
			for idx, aTacan in pairs(theZone.spawnedTACANS) do  
				table.insert(theTs, aTacan)
			end 
		end
	end
	
	if #theTs < 1 then 
		trigger.action.outTextForCoalition(args, "No active TACAN.", 30)
		return 
	end
	
	local msg = "\nActive TACAN:"

	for idx, aTacan in pairs(theTs) do 
		msg = msg .. "\n  - " .. aTacan.activeCallsign .. ": " .. aTacan.activeChan .. aTacan.activeMode
	end
	msg = msg .. "\n"
	trigger.action.outTextForCoalition(args, msg, 30)
end

--
-- Start up: config etc 
--

function tacan.readConfigZone()
	local theZone = cfxZones.getZoneByName("tacanConfig") 
	if not theZone then theZone = cfxZones.createSimpleZone("tacanConfig") end 
	
	tacan.verbose = theZone.verbose 
	
	tacan.list = cfxZones.getBoolFromZoneProperty(theZone, "list", false)
	if theZone:hasProperty("GUI") then 
		tacan.list = theZone:getBoolFromZoneProperty("GUI", false)
	end
	
	if tacan.verbose then 
		trigger.action.outText("+++tcn: read config", 30)
	end 
end

function tacan.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx Tacan requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx TACAN", 
		tacan.requiredLibs) then
		return false 
	end
	
	-- read config 
	tacan.readConfigZone()
	
	-- set comms 
	if tacan.list then tacan.installComms() end 
	
	-- collect tacan zones
	local tZones = cfxZones.zonesWithProperty("tacan")
	for k, aZone in pairs(tZones) do
		tacan.createTacanZone(aZone)
		tacan.tacanZones[aZone.name] = aZone
	end
	
	-- start update 
	tacan.update()
	
	-- start GC
	tacan.GC() 
	
	-- say Hi!
	trigger.action.outText("cfx Tacan v" .. tacan.version .. " started.",30)
end

tacan.start()

--[[--
	Ideas
	- moving tacan, as in ndb 
--]]--