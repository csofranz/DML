stopGap = {}
stopGap.version = "1.1.1 STANDALONE"
stopGap.verbose = false 
stopGap.ssbEnabled = true 
stopGap.ignoreMe = "-sg"
stopGap.spIgnore = "-sp" -- only single-player ignored 
stopGap.isMP = false 
stopGap.running = true 
stopGap.refreshInterval = -1 -- seconds to refresh all statics. -1 = never, 3600 = once every hour 
stopGap.kickTheDead = true -- kick players to spectators on death to prevent re-entry issues

--[[--
	Written and (c) 2023 by Christian Franz 

	Replace all player units with static aircraft until the first time 
	that a player slots into that plane. Static is then replaced with live 
	player unit. For Multiplayer the small (server-only) script "StopGapGUI" is required
	
	For aircraft/helo carriers, no player planes are replaced with statics

	STRONGLY RECOMMENDED:
	- Use single-unit player groups.
	- Use 'start from ground hot/cold' to be able to control initial aircraft orientation

	To selectively exempt player units from stopGap, add a '-sg' to their name 

	Version History
	1.0.0 - Initial version
    1.0.1 - update / replace statics after slots become free 
	1.0.3 - server plug-in logic for SSB, sgGUI
	1.0.4 - player units or groups that end in '-sg' are not stop-gapped
	1.0.5 - (DML-only additions)
	1.0.6 - can detect stopGapGUI active on server
		  - supports "-sp" for single-player only suppress
	1.0.7 - (DML-only internal cool stuff)
	1.0.8 - added refreshInterval option as requested 
	1.0.9 - optimization when turning on stopgap
	1.1.0 - kickTheDead option 
	1.1.1 - filter "from runway" clients
	
--]]--

stopGap.standInGroups ={}
stopGap.myGroups = {} -- for fast look-up of mx orig data 
--
-- one-time start-up processing
--
-- in DCS, a group with one or more players only allocates when 
-- the first player in the group enters the game. 
--
cfxMX = {} -- local copy of cfxMX mission data cross reference tool 
cfxMX.playerGroupByName = {} -- returns data only if a player is in group 
cfxMX.countryByName ={} -- county of group named 

function cfxMX.createCrossReferences()
	-- tip o' hat to Mist for scanning mission struct. 
	for coa_name_miz, coa_data in pairs(env.mission.coalition) do -- iterate all coalitions
		local coa_name = coa_name_miz
		if string.lower(coa_name_miz) == 'neutrals' then -- remove 's' at neutralS
			coa_name = 'neutral'
		end
		-- directly convert coalition into number for easier access later
		local coaNum = 0
		if coa_name == "red" then coaNum = 1 end 
		if coa_name == "blue" then coaNum = 2 end 
		
		if type(coa_data) == 'table' then -- coalition = {bullseye, nav_points, name, county}, 
										  -- with county being an array 
			if coa_data.country then -- make sure there a country table for this coalition
				for cntry_id, cntry_data in pairs(coa_data.country) do -- iterate all countries for this 
					-- per country = {id, name, vehicle, helicopter, plane, ship, static}
					local countryName = string.lower(cntry_data.name)
					local countryID = cntry_data.id 
					if type(cntry_data) == 'table' then	-- filter strings .id and .name 
						for obj_type_name, obj_type_data in pairs(cntry_data) do
							if obj_type_name == "helicopter" or 
							   obj_type_name == "ship" or 
							   obj_type_name == "plane" or 
							   obj_type_name == "vehicle" or 
							   obj_type_name == "static" -- what about "cargo"?
							then -- (so it's not id or name)
								local category = obj_type_name
								if ((type(obj_type_data) == 'table') and obj_type_data.group and (type(obj_type_data.group) == 'table') and (#obj_type_data.group > 0)) then	--there's at least one group!
									for group_num, group_data in pairs(obj_type_data.group) do
										
										local aName = group_data.name
										cfxMX.countryByName[aName] = countryID
										-- now iterate all units in this group 
										-- for player info and ID
										for unit_num, unit_data in pairs(group_data.units) do
											if unit_data.skill then 
												if unit_data.skill == "Client" or  unit_data.skill == "Player" then
													cfxMX.playerGroupByName[aName] = group_data -- inefficient, but works
												end -- if unit skill client
											end -- if is player/client skill 
										end -- for all units
									end -- for all groups 
								end --if has category data 
							end --if plane, helo etc... category
						end --for all objects in country 
					end --if has country data 
				end --for all countries in coalition
			end --if coalition has country table 
		end -- if there is coalition data  
	end --for all coalitions in mission 
end

function stopGap.staticMXFromUnitMX(theGroup, theUnit)
	-- enter with MX data blocks
	-- build a static object from mx unit data 
	local theStatic = {}
	theStatic.x = theUnit.x 
	theStatic.y = theUnit.y 
	theStatic.livery_id = theUnit.livery_id -- if exists 
	theStatic.heading = theUnit.heading -- may need some attention
	theStatic.type = theUnit.type 
	theStatic.name = theUnit.name  -- will magically be replaced with player unit 
	theStatic.cty = cfxMX.countryByName[theGroup.name]
	
	return theStatic 
end

function stopGap.isGroundStart(theGroup)
	-- look at route 
	if not theGroup.route then return false end 
	local route = theGroup.route 
	local points = route.points 
	if not points then return false end
	local ip = points[1]
	if not ip then return false end 
	local action = ip.action 
	if action == "Fly Over Point" then return false end 
	if action == "Turning Point" then return false end 	
	if action == "Landing" then return false end 	
	if action == "From Runway" then return false end 
	-- looks like aircraft is on the ground
	-- but is it in water (carrier)? 
	local u1 = theGroup.units[1]
	local sType = land.getSurfaceType(u1) -- has fields x and y
	if sType == 3 then return false end 
	
	if false then 
		trigger.action.outText("Player Group <" .. theGroup.name .. "> GROUND BASED: " .. action .. " land type " .. sType, 30)
	end 
	return true
end

function stopGap.createStandInsForMXGroup(group)
	local allUnits = group.units
	if group.name:sub(-#stopGap.ignoreMe) == stopGap.ignoreMe then 
		if stopGap.verbose then 
			trigger.action.outText("<< '-sg' skipping group " .. group.name .. ">>", 30)
		end
		return nil 
	end
	if (not stopGap.isMP) and group.name:sub(-#stopGap.spIgnore) == stopGap.spIgnore then 
		if stopGap.verbose then 
			trigger.action.outText("<<'-sp' !SP! skipping group " .. group.name .. ">>", 30)
		end
		return nil 
	end
	local theStaticGroup = {}
	for idx, theUnit in pairs (allUnits) do 
		local sgMatch = theUnit.name:sub(-#stopGap.ignoreMe) == stopGap.ignoreMe
		local spMatch = theUnit.name:sub(-#stopGap.spIgnore) == stopGap.spIgnore
		if stopGap.isMP then spMatch = false end -- only single-player
		if (theUnit.skill == "Client" or theUnit.skill == "Player") 
		   and (not sgMatch)
		   and (not spMatch)
		then 
			local theStaticMX = stopGap.staticMXFromUnitMX(group, theUnit)
			local theStatic = coalition.addStaticObject(theStaticMX.cty, theStaticMX)
			theStaticGroup[theUnit.name] = theStatic -- remember me
			if stopGap.verbose then 
				trigger.action.outText("Stop-gap-ing <" .. theUnit.name .. ">", 30)
			end
		else 
			if stopGap.verbose then 
				trigger.action.outText("<<skipping unit " .. theUnit.name .. ">>", 30)
			end
		end 
	end
	return theStaticGroup
end

function stopGap.initGaps()
	-- when we enter, all slots are emptry 
	-- and we populate all empty slots 
	-- with their static representations 
	for name, group in pairs (cfxMX.playerGroupByName) do 
		-- check to see if this group is on the ground at parking 
		-- by looking at the first waypoint 
		if stopGap.isGroundStart(group) then 
			-- this is one of ours!
			group.sgName = "SG"..group.name -- flag name for MP
			trigger.action.setUserFlag(group.sgName, 0) -- mark unengaged
			stopGap.myGroups[name] = group
			
			-- see if this group exists in-game already 
			local existing = Group.getByName(name)
			if existing and Group.isExist(existing) then 
				if stopGap.verbose then 
					trigger.action.outText("+++stopG: group <" .. name .. "> already slotted, skipping", 30)
				end
			else 
				-- replace all groups entirely with static objects 
				local theStaticGroup = stopGap.createStandInsForMXGroup(group)
				-- remember this static group by its real name 
				stopGap.standInGroups[group.name] = theStaticGroup
			end
		end -- if groundtstart
	end
end

function stopGap.turnOff()
	-- remove all stand-ins
	for gName, standIn in pairs (stopGap.standInGroups) do 
		for name, theStatic in pairs(standIn) do 
			StaticObject.destroy(theStatic)
		end
	end
	stopGap.standInGroups = {}
	stopGap.running = false 
end

function stopGap.turnOn()
	-- populate all empty (un-occupied) slots with stand-ins
	stopGap.initGaps()
	stopGap.running = true 
end

function stopGap.refreshAll() -- restore all statics 
	if stopGap.refreshInterval > 0 then 
		-- re-schedule invocation 
		timer.scheduleFunction(stopGap.refreshAll, {}, timer.getTime() + stopGap.refreshInterval)
		if stopGap.running then 
			stopGap.turnOff() -- kill all statics 
			-- turn back on in half a second 
			timer.scheduleFunction(stopGap.turnOn, {}, timer.getTime() + 0.5)
		end
		if stopGap.verbose then 
			trigger.action.outText("+++stopG: refreshing all static", 30)
		end
	end
end
-- 
-- event handling 
--
function stopGap.removeStaticGapGroupNamed(gName)
	for name, theStatic in pairs(stopGap.standInGroups[gName]) do 
		StaticObject.destroy(theStatic)
	end
	stopGap.standInGroups[gName] = nil
end

function stopGap:onEvent(event)
	if not event then return end 
	if not event.id then return end 
	if not event.initiator then return end 
	local theUnit = event.initiator 
	if (not theUnit.getPlayerName) or (not theUnit:getPlayerName()) then 
		return 
	end -- no player unit.
	local id = event.id
	if id == 15 then 
		local uName = theUnit:getName()
		local theGroup = theUnit:getGroup() 
		local gName = theGroup:getName()
		
		if stopGap.myGroups[gName] then
			-- in case there were more than one units in this group, 
			-- also clear out the others. better safe than sorry
			if stopGap.standInGroups[gName] then 
				stopGap.removeStaticGapGroupNamed(gName)
			end
		end
		-- erase stopGapGUI flag, no longer required, unit 
		-- is now slotted into 
		trigger.action.setUserFlag("SG"..gName, 0)
	end
	if 	(id == 9) or (id == 30) or (id == 5) then -- dead, lost, crash 
		local pName = theUnit:getPlayerName()
		timer.scheduleFunction(stopGap.kickplayer, pName, timer.getTime() + 1)
	end
end

stopGap.kicks = {}
function stopGap.kickplayer(args)
	if not stopGap.kickTheDead then return end 
	local pName = args 
	for i,slot in pairs(net.get_player_list()) do
		local nn = net.get_name(slot)
		if nn == pName then
			if stopGap.kicks[nn] then 
				if timer.getTime() < stopGap.kicks[nn] then return end 
			end 
			net.force_player_slot(slot, 0, '')
			stopGap.kicks[nn] = timer.getTime() + 5 -- avoid too many kicks in 5 seconds
		end
	end
end
--
-- update 
--
function stopGap.update()
	-- check every 1 second
	timer.scheduleFunction(stopGap.update, {}, timer.getTime() + 1)
	
	if not stopGap.isMP then 
		local sgDetect = trigger.misc.getUserFlag("stopGapGUI")
		if sgDetect > 0 then 
			trigger.action.outText("stopGap: MP activated <" .. sgDetect .. ">, will re-init", 30) 
			stopGap.turnOff()
			stopGap.isMP = true 
			stopGap.turnOn()
			return
		end 
	end
	
	-- check if slots can be refilled or need to be vacated (MP) 
	for name, theGroup in pairs(stopGap.myGroups) do 
		if not stopGap.standInGroups[name] then 
			-- if there is no stand-in group, that group was slotted
			-- or removed for ssb
			local busy = true 
			local pGroup = Group.getByName(name)
			if pGroup then 
				if Group.isExist(pGroup) then 
				else
					busy = false -- no longer exists
				end
			else 
				busy = false -- nil group 
			end 
			
			-- now conduct ssb checks if enabled 
			if stopGap.ssbEnabled then 
				local ssbState = trigger.misc.getUserFlag(name)
				if ssbState > 0 then 
					busy = true -- keep busy 
				end
			end
			
			-- check if StopGapGUI wants a word 
			local sgState = trigger.misc.getUserFlag(theGroup.sgName)
			if sgState < 0 then 
				busy = true 
				-- count up for auto-release after n seconds
				trigger.action.setUserFlag(theGroup.sgName, sgState + 1)
				if stopGap.verbose then 
					trigger.action.outText("+++StopG: [cooldown] cooldown for group <" .. name .. ">, val now is <" .. sgState .. ">.", 30)
				end 	
			end
			
			if busy then 
				-- players active in this group 
			else 
				local theStaticGroup = stopGap.createStandInsForMXGroup(theGroup)
				stopGap.standInGroups[name] = theStaticGroup
				if stopGap.verbose then 
					trigger.action.outText("+++StopG: [server command] placing static stand-in for group <" .. name .. ">.", 30)
				end 	
			end	
		else 
			-- plane is currently static and visible
			-- check if this needs to change			
			local removeMe = false 
			if stopGap.ssbEnabled then 
				local ssbState = trigger.misc.getUserFlag(name)
				if ssbState > 0 then removeMe = true end 
			end
			local sgState = trigger.misc.getUserFlag(theGroup.sgName)
			if sgState < 0 then removeMe = true end 
			if removeMe then 
				stopGap.removeStaticGapGroupNamed(name) -- also nils entry
				if stopGap.verbose then 
					trigger.action.outText("+++StopG: [server command] remove static group <" .. name .. "> for SSB/SG server", 30)
				end 				
			end
		end
	end
end

--
-- get going 
--
function stopGap.start()
	-- check MP status, usually client is not synched to 
	-- server, yet so it will initially fail, and re-init in update() 
	local sgDetect = trigger.misc.getUserFlag("stopGapGUI")
	stopGap.isMP = sgDetect > 0 
	
	-- run a cross reference on all mission data for palyer info
	cfxMX.createCrossReferences()
	-- fill player slots with static objects 
	stopGap.initGaps()
		
	-- connect event handler
	world.addEventHandler(stopGap)
	
	-- start update in 1 second 
	timer.scheduleFunction(stopGap.update, {}, timer.getTime() + 1)
	
	-- start refresh cycle if refresh (>0)
	if stopGap.refreshInterval > 0 then 
		timer.scheduleFunction(stopGap.refreshAll, {}, timer.getTime() + stopGap.refreshInterval)
	end
	
	-- say hi!
	local mp = " (SP - <" .. sgDetect .. ">)"
	if sgDetect > 0 then mp = " -- MP GUI Detected (" .. sgDetect .. ")!" end
	trigger.action.outText("stopGap v" .. stopGap.version .. "  running" .. mp, 30)	
	return true 
end

if not stopGap.start() then 
	trigger.action.outText("+++ aborted stopGap v" .. stopGap.version .. "  -- start failed", 30)
	stopGap = nil 
end


