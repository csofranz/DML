-- cfxCommander - issue dcs commands to groups etc
--
-- supports scheduling
-- *** EXTENDS ZONES: 'pathing' attribute 
--
cfxCommander = {}
cfxCommander.version = "1.1.3"
--[[-- VERSION HISTORY
 - 1.0.5 - createWPListForGroupToPointViaRoads: detect no road found 
 - 1.0.6 - build in more group checks in assign wp list 
         - added sanity checks for doScheduledTask
		 - assignWPListToGroup now can schedule tasks 
		 - makeGroupGoThere supports scheduling
		 - makeGroupGoTherePreferringRoads supports scheduling 
		 - scheduleTaskForGroup supports immediate execution
		 - makeGroupHalt
 - 1.0.7 - warning if road shorter than direct
         - forceOffRoad option
		 - noRoadsAtAll option 
 - 1.1.0 - load libs 
		 - pathing zones. Currently only supports 
		 - offroad to override road-usage
		 - pathing zones are overridden by noRoadsAtAll
		 - CommanderConfig zones 
 - 1.1.1 - default pathing for pathing zone is normal, not offroad 
 - 1.1.2 - makeGroupTransmit 
         - makeGroupStopTransmitting
		 - verbose check before path warning
		 - added delay defaulting for most scheduling functions 
 - 1.1.3 - isExist() guard improvements for multiple methods
         - cleaned up comments
 
--]]--

cfxCommander.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	"cfxZones", -- zones management for pathing zones 
}

cfxCommander.verbose = false 
cfxCommander.forceOffRoad = true -- if true, vehicles path follow roads, but may drive offroad (they follow vertex points from path but not the road as they are still commanded 'offroad')
cfxCommander.noRoadsAtAll = true  -- if true, always go direct, overrides forceOffRoad when true. Always a two-point path. Here, there, bang! 
cfxCommander.pathZones = {} -- zones that can override road settings

--
-- path zone
--
function cfxCommander.processPathingZone(aZone) -- process attribute and add to zone
	local pathing = cfxZones.getStringFromZoneProperty(aZone, "pathing", "normal") -- must be "offroad" to force offroad
	pathing = pathing:lower()
	-- currently no validation of attribute 
	aZone.pathing = pathing
end 

function cfxCommander.addPathingZone(aZone)
	table.insert(cfxCommander.pathZones, aZone)
end 

function cfxCommander.hasPathZoneFor(here, there)
	for idx, aZone in pairs(cfxCommander.pathZones) do 
		if cfxZones.pointInZone(here, aZone) then return aZone end 
		if cfxZones.pointInZone(there, aZone) then return aZone end
	end
	return nil
end

--
-- Config Zone Reading if present 
--
function cfxCommander.readConfigZone()
	-- note: must match exactly!!!!
	local theZone = cfxZones.getZoneByName("CommanderConfig") 
	if not theZone then 
		trigger.action.outText("+++cmdr: no config zone!", 30) 
		return 
	end 
	
	trigger.action.outText("+++cmdr: found config zone!", 30) 
	
	cfxCommander.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	cfxCommander.forceOffRoad = cfxZones.getBoolFromZoneProperty(theZone, "forceOffRoad", false) -- if true, vehicles path follow roads, but may drive offroad
	cfxCommander.noRoadsAtAll = cfxZones.getBoolFromZoneProperty(theZone, "noRoadsAtAll", false)

end

--
-- Options are key, value pairs. Scheduler when you are creating groups
-- 

function cfxCommander.doOption(data) 
	if cfxCommander.verbose then 
		trigger.action.outText("Commander: setting option " .. data.key .. " --> " .. data.value, 30)
	end

	local theController = data.group:getController()
	theController:setOption(data.key, data.value)
end

function cfxCommander.scheduleOptionForGroup(group, key, value, delay) 
	local data = {}
	if not delay then delay = 0.1 end 
	data.group = group
	data.key = key
	data.value = value 
	timer.scheduleFunction(cfxCommander.doOption, data, timer.getTime() + delay)
end

--
-- performCommand is a special version of issuing a command
-- that can be easily schduled by pushing the commandData on 
-- the stack with scheduling it 
-- group or name must be filled to get the group,
-- and the command table is what is going to be passed to the setCommand
-- commands are given in an array, so you can stack commands 
function cfxCommander.performCommands(commandData)
	-- see if we have a group
	if not commandData.group then 
		commandData.group = Group.getByName(commandData.name) -- better be inited!
	end
	-- get the AI
	local theController = commandData.group:getController()
	for i=1, #commandData.commands do
		if cfxCommander.verbose then 
			trigger.action.outText("Commander: performing " .. commandData.commands[i].id, 30)
		end
		theController:setCommand(commandData.commands[i])
	end
	
	return nil -- a timer called us, so we return no desire to be rescheduled
end

function cfxCommander.scheduleCommands(data, delay)
	if not delay then delay = 1 end 
	timer.scheduleFunction(cfxCommander.performCommands, data, timer.getTime() + delay)
end

function cfxCommander.scheduleSingleCommand(group, command, delay) 
	if not delay then delay = 1 end 
	local data = createCommandDataTableFor(group)
	cfxCommander.addCommand(data, command)
	cfxCommander.scheduleCommands(data, delay)
end


function cfxCommander.createCommandDataTableFor(group, name)
	local cD = {}
	if not group then 
		cD.name = name
	else
		cD.group = group
	end
	cD.commands={}
	return cD
end

function cfxCommander.addCommand(theCD, theCommand)
	if not theCD then return end 
	if not theCommand then return end 
	
	table.insert(theCD.commands, theCommand)
end

function cfxCommander.createSetFrequencyCommand(freq, modulator)
	local theCmd = {}
	if not freq then freq = 100 end 
	if not modulator then modulator = 0 end -- AM = 0, default
	theCmd.id = 'SetFrequency'
	theCmd.params = {}
	theCmd.params.frequency = freq * 10000 -- 88 --> 880000. 124 --> 1.24 MHz
	theCmd.params.modulation = modulator
	return theCmd
end

-- oneShot is optional. if present and anything but false, will cause message to 
-- me sent only once, no loops
function cfxCommander.createTransmissionCommand(filename, oneShot)
	local looping = true
	if not filename then filename = "dummy" end 
	if oneShot then looping = false end
	local theCmd = {}
	theCmd.id = 'TransmitMessage'
	theCmd.params = {}
	theCmd.params.loop = looping
	theCmd.params.file = "l10n/DEFAULT/" .. filename -- need to prepend the resource string
	return theCmd
end

function cfxCommander.createStopTransmissionCommand()
	local theCmd = {}
	theCmd.id = 'stopTransmission'
	theCmd.params = {}
	return theCmd
end

--
-- tasks
-- 

function cfxCommander.doScheduledTask(data) 
	if cfxCommander.verbose then 
		trigger.action.outText("Commander: setting task " .. data.task.id .. " for group " .. data.group:getName(), 30)
	end
	local theGroup = data.group 
	if not theGroup then return end 
	if not Group.isExist(theGroup) then return end 
--	if not theGroup.isExist then return end
	
	local theController = theGroup:getController()
	theController:pushTask(data.task)
end

function cfxCommander.scheduleTaskForGroup(group, task, delay)
	if not delay then delay = 0 end 
	local data = {}
	data.group = group
	data.task = task
	if delay < 0.001 then 
		cfxCommander.doScheduledTask(data) -- immediate execution
		return 
	end
	timer.scheduleFunction(cfxCommander.doScheduledTask, data, timer.getTime() + delay)
end

function cfxCommander.createAttackGroupCommand(theGroupToAttack)
	local task = {}
	task.id = 'AttackGroup'
	task.params = {}
	task.params.groupID = theGroupToAttack:getID()
	return task
end

function cfxCommander.createEngageGroupCommand(theGroupToAttack)
	local task = {}
	task.id = 'EngageGroup'
	task.params = {}
	task.params.groupID = theGroupToAttack:getID()
	return task
end

--
-- waypoints, routes etc 
--

-- basic waypoint is for ground units. point can be xyz or xy 
function cfxCommander.createBasicWaypoint(point, speed, formation)
	local wp = {}
	wp.x = point.x
	-- support xyz and xy format
	if point.z then 
		wp.y = point.z
	else
		wp.y = point.y
	end
	
	if not speed then speed = 6 end -- 6 m/s = 20 kph
	wp.speed = speed 
	
	if cfxCommander.forceOffRoad then 
		formation = "Off Road"
	end
	
	if not formation then formation = "Off Road" end
	-- legal formations:
	-- Off road
	-- On Road -- second letter upper case?
	-- Cone 
	-- Rank
	-- Diamond
	-- Vee
	-- EchelonR
	-- EchelonL
	wp.action = formation -- silly name, but that's how ME does it
	wp.type = 'Turning Point'
	return wp

end

function cfxCommander.buildTaskFromWPList(wpList)
	-- build the task that will make a group follow the WP list
	-- we do this by creating a "Mission" task around the WP List
	-- WP list is consumed by this action
	local missionTask = {}
	missionTask.id = "Mission"
	missionTask.params = {}
	missionTask.params.route = {}
	missionTask.params.route.points=wpList
	return missionTask
end

function cfxCommander.assignWPListToGroup(group, wpList, delay)
	if not delay then delay = 0 end 
	if not group then return end 
	if type(group) == 'string' then -- group name, nice mist trick 
		group = Group.getByName(group)
	end
	if not group then return end 
	if not Group.isExist(group) then return end 
	
	local theTask = cfxCommander.buildTaskFromWPList(wpList)
	local ctrl = group:getController()

--[[--
	if delay < 0.001 then -- immediate action
		if ctrl then
			ctrl:setTask(theTask)
		end
	else 
		-- delay execution of this command by the specified amount 
		-- of seconds 
		cfxCommander.scheduleTaskForGroup(group, theTask, delay)
	end
--]]--
	cfxCommander.scheduleTaskForGroup(group, theTask, delay)
end

function cfxCommander.createWPListForGroupToPoint(group, point, speed, formation)
	if type(group) == 'string' then -- group name
		group = Group.getByName(group)
	end

	local wpList = {}
	-- here we are, and we want to go there. In DCS, this means that
	-- we need to create a wp list consisting of here and there
	local here = dcsCommon.getGroupLocation(group)
	local wpHere = cfxCommander.createBasicWaypoint(here, speed, formation)
	local wpThere = cfxCommander.createBasicWaypoint(point, speed, formation)
	wpList[1] = wpHere
	wpList[2] = wpThere
	return wpList
end

-- make a ground units group head to a waypoint by replacing the entire mission
-- with a two-waypoint lsit from (here) to there at speed and formation. formation
-- default is 'off road'
function cfxCommander.makeGroupGoThere(group, there, speed, formation, delay)
	if not delay then delay = 0 end 
	if type(group) == 'string' then -- group name
		group = Group.getByName(group)
	end
	local wp = cfxCommander.createWPListForGroupToPoint(group, there, speed, formation)
	
	cfxCommander.assignWPListToGroup(group, wp, delay)
end

function cfxCommander.calculatePathLength(roadPoints)
	local totalLen = 0
	if #roadPoints < 2 then return 0 end
	for i=1, #roadPoints-1 do
		totalLen = totalLen + dcsCommon.dist(roadPoints[i], roadPoints[i+1])
	end
	return totalLen
end

-- make ground units go from here (group location) to there, using roads if possible
function cfxCommander.createWPListForGroupToPointViaRoads(group, point, speed)
	if type(group) == 'string' then -- group name
		group = Group.getByName(group)
	end

	local wpList = {}
	-- here we are, and we want to go there. In DCS, this means that
	-- we need to create a wp list consisting of here and there
	-- when going via roads, we add to more wayoints:
	-- go on-roads and leaveRoads. 
	-- only if we can get these two additional points, we do that, else we 
	-- fall back to direct route 
	
	local here = dcsCommon.getGroupLocation(group)

	-- now generate a list of all points from here to there that uses roads
	local rawRoadPoints = land.findPathOnRoads('roads', here.x, here.z, point.x, point.z)
	-- this is the entire path. calculate the length and make 
	-- sure that path on-road isn't more than twice as long 
	-- that can happen if a bridge is out or we need to go around a hill
	if not rawRoadPoints or #rawRoadPoints<3 then 
		trigger.action.outText("+++ no roads leading there. Taking direct approach", 30)
		return cfxCommander.createWPListForGroupToPoint(group, point, speed)
	end
	
	local pathLength = cfxCommander.calculatePathLength(rawRoadPoints)
	local direct = dcsCommon.dist(here, point)
	if pathLength < direct and cfxCommander.verbose then 
		trigger.action.outText("+++dcsC: WARNING road path (" .. pathLength .. ") shorter than direct route(" .. direct .. "), will not path correctly", 30)
	end
	
	if pathLength > (2 * direct) then 
		-- road takes too long, take direct approach
		--trigger.action.outText("+++ road path (" .. pathLength .. ") > twice direct route(" .. direct .. "), commencing direct off-road", 30)
		return cfxCommander.createWPListForGroupToPoint(group, point, speed)
	end
	
	--trigger.action.outText("+++ ".. group:getName() .. ": choosing road path l=" .. pathLength .. " over direct route d=" .. direct, 30)
	
	-- if we are here, the road trip is valid 
	for idx, wp in pairs(rawRoadPoints) do 
		-- createBasic... supports w.xy format
		local theNewWP = cfxCommander.createBasicWaypoint(wp, speed, "On Road") -- force off road for better compatibility?
		table.insert(wpList, theNewWP)
	end
	
	
	
	-- now make first and last entry OFF Road
	local wpc = wpList[1]
	wpc.action = "Off Road"
	wpc = wpList[#wpList]
	wpc.action = "Off Road"

	return wpList
end

function cfxCommander.makeGroupGoTherePreferringRoads(group, there, speed, delay)
	if type(group) == 'string' then -- group name
		group = Group.getByName(group)
	end
	if not delay then delay = 0 end 


	if cfxCommander.noRoadsAtAll then 
		-- we don't even follow roads, completely forced off
		cfxCommander.makeGroupGoThere(group, there, speed, "Off Road", delay)
		return 
	end

	-- see if we have an override situation 
	-- for one of the two points where a pathing Zone 
	-- overrides the roads setting 
	if #cfxCommander.pathZones > 0 then  
		local here = dcsCommon.getGroupLocation(group)
		local oRide = cfxCommander.hasPathZoneFor(here, there)
		if oRide and oRide.pathing == "offroad" then 
			-- yup, override road preference
			cfxCommander.makeGroupGoThere(group, there, speed, "Off Road", delay)
			return 
		end
	end

	-- viaRoads will only use roads if the road trip isn't more than twice 
	-- as long as the direct route 
	local wp = cfxCommander.createWPListForGroupToPointViaRoads(group, there, speed)
	cfxCommander.assignWPListToGroup(group, wp, delay)
end


function cfxCommander.makeGroupHalt(group, delay)
	if not group then return end 
	if not Group.isExist(group) then return end 
	if not delay then delay = 0 end 
	local theTask = {id = 'Hold', params = {}}
	cfxCommander.scheduleTaskForGroup(group, theTask, delay)
end

function cfxCommander.makeGroupTransmit(group, tenKHz, filename, oneShot, delay)
	if not group then return end 
	if not tenKHz then tenKHz = 20 end -- default to 200KHz
	if not delay then delay = 1.0 end 
	if not filename then return end 
	if not oneShot then oneShot = false end 
	
	-- now build the transmission command
	local theCommands = cfxCommander.createCommandDataTableFor(group)
	local cmd = cfxCommander.createSetFrequencyCommand(tenKHz) -- freq in 10000 Hz
	cfxCommander.addCommand(theCommands, cmd)
	cmd = cfxCommander.createTransmissionCommand(filename, oneShot)
	cfxCommander.addCommand(theCommands, cmd)
	cfxCommander.scheduleCommands(theCommands, delay)
end 

function cfxCommander.makeGroupStopTransmitting(group, delay)
	if not delay then delay = 1 end 
	if not group then return end 
	local theCommands = cfxCommander.createCommandDataTableFor(group)
	local cmd = cfxCommander.createStopTransmissionCommand()
	cfxCommander.addCommand(theCommands, cmd)
	cfxCommander.scheduleCommands(theCommands, delay)
end


function cfxCommander.start()
	-- make sure we have loaded all relevant libraries 
	if not dcsCommon.libCheck("cfx Commander", cfxCommander.requiredLibs) then 
		trigger.action.outText("cf/x Commander aborted: missing libraries", 30)
		return false 
	end
	
	-- identify and process all 'pathing' zones
	local pathZones = cfxZones.getZonesWithAttributeNamed("pathing")
	
	-- now create a spawner for all, add them to the spawner updater, and spawn for all zones that are not
	-- paused 
	for k, aZone in pairs(pathZones) do 
		cfxCommander.processPathingZone(aZone) -- process attribute and add to zone
		cfxCommander.addPathingZone(aZone) -- remember it so we can smoke it
	end
	
	-- read config overides 
	cfxCommander.readConfigZone()
	
	return true
end

if cfxCommander.start() then 
	trigger.action.outText("cfxCommander v" .. cfxCommander.version .. " loaded", 30)
else 
	trigger.action.outText("+++cfxCommander load FAILED", 30)
	cfxCommander = nil
end

--[[-- known issues

- troops remain motionless until all are repaired or produced after cature
- long roads / roads not taken in persia 
- all troops red and blue become motionless when one zone is occupied
- after capture, the troop capturing remains, all others can go on. one will always remain there 
- rethink the factor to add to road, and simply add 100m 

 TODO: break long distances into smaller paths, and gravitate towards pathing zones if they have a 'gravitate' or similar attribute 
--]]--
