asw = {}
asw.version = "1.0.1"
asw.verbose = false 
asw.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
asw.ups = 0.1 -- = once every 10 seconds
asw.buoys = {} -- all buoys, by name
asw.torpedoes = {} -- all torpedoes in the water. 
asw.thumpers = {} -- all current sonar amplifiers/booms that are active
asw.fixes = {} -- all subs that we have a fix on. indexed by sub name 
-- fixname encodes the coalition of the fix in "/<coanum>"

--[[--
	Version History
	1.0.0 - initial version 
	1.0.1 - integration with playerScore 
	1.0.2 - new useSmoke attribute 
	
--]]--

--
--  :::WARNING:::
--  CURRENTLY NOT CHECKING FOR COALITIONS 
--

function asw.createTorpedo()
	local t = {}
	t.lifeTimer = timer.getTime() + asw.torpedoLife
	t.speed = asw.torpedoSpeed
	t.state = 0; -- not yet released. FSM 
	t.name = dcsCommon.uuid("asw.t")
	return t
end

function asw.createTorpedoForUnit(theUnit)
	local t = asw.createTorpedo()
	t.coalition = theUnit:getCoalition()
	t.point = theUnit:getPoint()
	t.droppedBy = theUnit 
	if theUnit.getPlayerName and theUnit:getPlayerName() ~= nil then 
		t.playerName = theUnit:getPlayerName()
	end
	return t 
end

function asw.createTorpedoForZone(theZone)
	local t = asw.createTorpedo()
	t.coalition = theZone.coalition
	t.point = cfxZones.getPoint(theZone)
	return t 
end

function asw.createBuoy() 
	local b = {}
	b.markID = dcsCommon.numberUUID() -- buoy mark
	b.coalition = 0
	b.point = nil 
	b.smokeTimer = timer.getTime() + 5 * 60 -- for refresh
	b.smokeColor = nil -- 
	b.lifeTimer = timer.getTime() + asw.buoyLife 
	b.contacts = {} -- detected contacts in range. by unit name 
	b.timeStamps = {}
	b.bearing = {} -- bearing to contact
	b.lines = {} -- line art for contact (wedges)
	b.lastContactNum = 0 
	b.lastReportedIn = 0 -- time of last report
	return b
end

function asw.createBuoyForUnit(theUnit)
	-- theUnit drops buoy, making it belong to the same coalition 
	-- as the dropping unit 
	local b = asw.createBuoy()
	b.point = theUnit:getPoint()
	b.point.y = 0 
	b.coalition = theUnit:getCoalition()
	b.smokeColor = asw.smokeColor -- needs to be done later 
	b.name = dcsCommon.uuid("asw-b." .. theUnit:getName()) 
	return b 
end

function asw.createBuoyForZone(theZone)
	-- theZone drops buoy (if zone isn't linked to unit) 
	-- making it belong to the same coalition 
	-- as the dropping unit 
	local theUnit = cfxZones.getLinkedUnit(theZone)
	if theUnit then 
		b = asw.createBuoyForUnit(theUnit)
		return b 
	end 
	
	local b = asw.createBuoy()
	b.point = cfxZones.getPoint(theZone)
	b.point.y = 0 
	b.coalition = theZone.coalition
	b.smokeColor = asw.smokeColor -- needs to be done later 
	b.name = dcsCommon.uuid("asw-b." .. theZone.name) 
	return b 
end

-- uid generation for this module.
asw.ccounter = 0 -- init to preferred value 
asw.ccinc = 1 -- init to preferred increment
function asw.contactCount()
	asw.ccounter = asw.ccounter + asw.ccinc
	return asw.ccounter
end

function asw.createFixForSub(theUnit, theCoalition) 
	if not theCoalition then
		trigger.action.outText("+++ASW: createFix without coalition, assuming BLUE", 30)
		theCoalition = 2 
	end
	
	local now = timer.getTime()
	local f = {}
	f.coalition = theCoalition
	f.theUnit = theUnit 
	if theCoalition == theUnit:getCoalition() then 
		trigger.action.outText("+++ASW: createFix - theUnit <" .. theUnit:getName() .. "> has same coalition than detection side (" .. theCoalition .. ")", 30)
	end 
	
	f.name = theUnit:getName()
	f.typeName = theUnit:getTypeName()
	f.desig = "SC-" .. asw.contactCount()
	f.lifeTimer = now + asw.fixLife -- will be renewed whenever we hit enough signal strength 
	f.lines = 0 
	return f 
end

--
-- dropping buoys, torpedos and thumpers 
--

function asw.dropBuoyFrom(theUnit)
	if not theUnit or not Unit.isExist(theUnit) then return end 
	-- make sure we do not drop over land 
	local p3 = theUnit:getPoint()
	local p2 = {x=p3.x, y=p3.z}
	local lType = land.getSurfaceType(p2)
	if lType ~= 3 then
		if asw.verbose then 
			trigger.action.outText("+++aswZ: ASW counter-measures must be dropped over open water, not <" .. lType .. ">. Aborting deployment for <" .. theUnit:getName() .. "> failed, counter-measure lost", 30)
		end 
		return nil 
	end 

	local now = timer.getTime()
	-- create buoy
	local theBuoy = asw.createBuoyForUnit(theUnit)
	
	-- mark point 
	if asw.useSmoke then 
		dcsCommon.markPointWithSmoke(theBuoy.point, theBuoy.smokeColor)
	end 
	theBuoy.smokeTimer = now + 5 * 60
	
	-- add buoy to my inventory 
	asw.buoys[theBuoy.name] = theBuoy
	
	-- mark on map 
	local info = "Buoy dropped by " .. theUnit:getName() .. " at " .. dcsCommon.nowString()
	trigger.action.markToCoalition(theBuoy.markID, info, theUnit:getPoint(), theBuoy.coalition, true, "")
	if asw.verbose then 
		trigger.action.outText("Dropping buoy " .. theBuoy.name, 30)
	end 
	return theBuoy
end

function asw.dropBuoyFromZone(theZone)
--	trigger.action.outText("enter asw.dropBuoyFromZone <" .. theZone.name .. ">", 30)
	local theUnit = cfxZones.getLinkedUnit(theZone)
	if theUnit and Unit.isExist(theUnit)then 
		return asw.dropBuoyFrom(theUnit)
	end 

	-- try and set the zone's coalition by the unit that 
	-- it is following
	local coa = cfxZones.getLinkedUnit(theZone)
	if coa then 
		theZone.coalition = coa 
	end 
	
	if not theZone.coalition or theZone.coalition == 0 then 
		trigger.action.outText("+++aswZ: 0 coalition for aswZone <" .. theZone.name .. ">, aborting buoy drop.", 30)
		return nil 
	end

	-- make sure we do not drop over land 
	local p3 = cfxZones.getPoint(theZone)
	local p2 = {x=p3.x, y=p3.z}
	local lType = land.getSurfaceType(p2)
	if lType ~= 3 then
		if asw.verbose then 
			trigger.action.outText("+++aswZ: asw measures must be dropped over open water, not <" .. lType .. ">. Aborting deployment for <" .. theZone.name .. ">", 30)
		end 
		return nil 
	end 
	

	local now = timer.getTime()
	-- create buoy
	local theBuoy = asw.createBuoyForZone(theZone)
	
	-- mark point 
	if asw.useSmoke then 
		dcsCommon.markPointWithSmoke(theBuoy.point, theBuoy.smokeColor)
	end 
	theBuoy.smokeTimer = now + 5 * 60
	
	-- add buoy to my inventory 
	asw.buoys[theBuoy.name] = theBuoy
	
	-- mark on map 
	local info = "Buoy dropped by " .. theZone.name .. " at " .. dcsCommon.nowString()
	local pos = cfxZones.getPoint(theZone)
	trigger.action.markToCoalition(theBuoy.markID, info, pos, theBuoy.coalition, true, "")
	if asw.verbose then 
		trigger.action.outText("Dropping buoy " .. theBuoy.name, 30)
	end 
	return theBuoy
end 

function asw.dropTorpedoFrom(theUnit)
	if not theUnit or not Unit.isExist(theUnit) then 
		return nil 
	end
	local p3 = theUnit:getPoint()
	local p2 = {x=p3.x, y=p3.z}
	local lType = land.getSurfaceType(p2)
	if lType ~= 3 then 
		if asw.verbose then 
			trigger.action.outText("+++aswZ: sub counter-measures must be dropped over open water, not <" .. lType .. ">. Aborting deployment for <" .. theUnit:getName() .. "> failed, counter-measure lost", 30)
		end 
		return nil 
	end 
	
	local t = asw.createTorpedoForUnit(theUnit)
	-- add to inventory
	asw.torpedoes[t.name] = t 
	if asw.verbose then 
		trigger.action.outText("Launching torpedo " .. t.name, 30)
	end 
	return t 
end

function asw.dropTorpedoFromZone(theZone)
	local theUnit = cfxZones.getLinkedUnit(theZone)
	if theUnit then 
		return asw.dropTorpedoFrom(theUnit)
	end 
	
	-- try and set the zone's coalition by the unit that 
	-- it is following
	local coa = cfxZones.getLinkedUnit(theZone)
	if coa then 
		theZone.coalition = coa 
	end 
	
	if not theZone.coalition or theZone.coalition == 0 then 
		trigger.action.outText("+++aswZ: 0 coalition for aswZone <" .. theZone.name .. ">, aborting torpedo drop.", 30)
		return nil 
	end
	
	-- make sure we do not drop over land 
	local p3 = cfxZones.getPoint(theZone)
	local p2 = {x=p3.x, y=p3.z}
	local lType = land.getSurfaceType(p2)
	if lType ~= 3 then  
		if asw.verbose then 
			trigger.action.outText("+++aswZ: asw measures must be dropped over open water, not <" .. lType .. ">. Aborting deployment for <" .. theZone.name .. ">", 30)
		end 
		return nil 
	end 
	
	local t = asw.createTorpedoForZone(theZone)
	-- add to inventory
	asw.torpedoes[t.name] = t 
	if asw.verbose then 
		trigger.action.outText("Launching torpedo for zone", 30)
	end 
	return t
end

--
-- UPDATE 
--
function asw.getClosestFixTo(loc, coalition)
	local dist = math.huge
	local closestFix = nil 
	for fixName, theFix in pairs(asw.fixes) do
		if theFix.coalition == coalition then 
			local theUnit = theFix.theUnit
			if Unit.isExist(theUnit) then 
				pos = theUnit:getPoint()
				d = dcsCommon.distFlat(loc, pos)
				if d < dist then 
					dist = d
					closestFix = theFix
				end 
			end
		end
	end	
	return closestFix, dist
end

function asw.getClosestSubToLoc(loc, allSubs)
	local dist = math.huge
	local closestSub = nil
	for cName, contact in pairs(allSubs) do 
		if Unit.isExist(contact.theUnit) then 
			d = dcsCommon.distFlat(loc, contact.theUnit:getPoint())
			if d < dist then 
				closestSub = contact.theUnit
				dist = d 
			end 
		end
	end
	return closestSub, dist 
end

function asw.wedgeForBuoyAndContact(theBuoy, aName, p)
	--env.info("   >enter wedge for buoy/contact: <" .. theBuoy.name .. ">/< .. aName .. >, p= " .. p)
	if p > 1 then p = 1 end  
	theBuoy.lines[aName] = dcsCommon.numberUUID()
	local shape = theBuoy.lines[aName]
	local p1 = theBuoy.point 
	local deviant = asw.maxDeviation * (1-p) -- get percentage of max dev 
	local minDev = math.floor(5 + (deviant * 0.2)) -- one fifth + 5 is fixed 
	local varDev = math.floor(deviant * 0.8) -- four fifth is variable 
	--env.info("   |will now calculate leftD and rightD")
	local leftD = math.floor(minDev + varDev * math.random()) -- dcsCommon.smallRandom(varDev) -- varDev * math.random() 
	local rightD = math.floor(minDev + varDev * math.random()) -- dcsCommon.smallRandom(varDev) -- varDev * math.random() 
	--env.info("   |will now calculate p2 and p3")
	local p2 = dcsCommon.newPointAtDegreesRange(p1, theBuoy.bearing[aName] - leftD, asw.maxDetectionRange)
	local p3 = dcsCommon.newPointAtDegreesRange(p1, theBuoy.bearing[aName] + rightD, asw.maxDetectionRange)
	--env.info("   |will now create wedge <" .. shape .. "> ")
	trigger.action.markupToAll(7, theBuoy.coalition, shape, p1, p2, p3, p1, {1, 0, 0, 0.25}, {1, 0, 0, 0.05}, 4, true, "Contact " .. tonumber(shape))
	--env.info("   <complete, leaving wedge for buoy/contact: <" .. theBuoy.name .. ">/< .. aName .. >")
end

function asw.updateBuoy(theBuoy, allSubs)
	--env.info("  >>enter update buoy for " .. theBuoy.name)
	-- note: buoys never see subs of their own side since it is 
	-- assumed that their location is known and filtered 
	if not theBuoy then return false end 
	
	-- allSubs are all possible contacts 
	local now = timer.getTime()
	if now > theBuoy.lifeTimer then 
		--env.info("  lifetime ran out")
		-- buoy timed out: remove mark 
		if asw.verbose then 
			trigger.action.outText("+++ASW: removing mark <" .. theBuoy.markID .. "> for buoy <" .. theBuoy.name .. ">", 30)
		end 
		--env.info("  - will remove mark " .. theBuoy.markID)
		trigger.action.removeMark(theBuoy.markID)
		--env.info("  - removed mark")
		-- now also remove all wedges 
		for name, wedge in pairs(theBuoy.lines) do 
			if asw.verbose then 
				trigger.action.outText("+++ASW: removing wedge mark <" .. wedge .. "> for sub <" .. name .. ">", 30)
			end 
			--env.info("  - will remove wedge " .. wedge)
			trigger.action.removeMark(wedge)
		end 
		--env.info("  <<updateBuoy, returning false")
		return false
	end
	
	-- buoy is alive!
	-- see if we need to resmoke 
	if now > theBuoy.smokeTimer then 
		--env.info("  resmoking buoy, continue")
		if asw.useSmoke then 
			dcsCommon.markPointWithSmoke(theBuoy.point, theBuoy.smokeColor)
		end 
		theBuoy.smokeTimer = now + 5 * 60
		--env.info("  resmoke done, continue")
	end
	
	-- check all contacts, skip own coalition subs
	-- check signal strength to all subs 
	local newContacts = {} -- as opposed to already in theBuoy.contacts
	--env.info("  :iterating allSubs for contacts")
	for contactName, contact in pairs (allSubs) do 
		if contact.coalition ~= theBuoy.coalition then -- not on our side
			local theSub = contact.theUnit 
			local theSubLoc = theSub:getPoint()
			local theSubName = contact.name 
			local p = 0 -- detection probability 
			local canDetect = false 
			local sureDetect = false 
			local depth = -dcsCommon.getUnitAGL(theSub) -- NOTE: INVERTED!!
			if depth > 5 and depth < asw.maxDetectionDepth then 			
				-- distance. probability recedes by square of distance 
				local dist = dcsCommon.distFlat(theBuoy.point, theSubLoc)
				if dist > asw.maxDetectionRange then 
					-- will not detect 
				elseif dist < asw.sureDetectionRange then 
					canDetect = true 
					sureDetect = true
					p = 1
					theBuoy.bearing[theSubName] = dcsCommon.bearingInDegreesFromAtoB(theBuoy.point, theSubLoc)
				else
					canDetect = true 
					p = 1 - (dist - asw.sureDetectionRange) / asw.maxDetectionRange -- percentage 
					p = p * p * p -- cubed, in 3D
					theBuoy.bearing[theSubName] = dcsCommon.bearingInDegreesFromAtoB(theBuoy.point, theSubLoc)
				end
			end
			if canDetect then 
				if sureDetect or math.random() < p then 
					-- we have detected sub this round!
					newContacts[theSubName] = p -- remember for buoy
					contact.trackedBy[theBuoy.name] = p -- remember for sub
				else 
					-- didn't detect, do nothing
					-- contact.trackedBy[theBuoy.name] = nil -- probably not required, contact is new each pass 
				end
			else 
				-- contact.trackedBy[theBuoy.name] = nil -- probably not required 
			end
		end -- if not the same coalition
	end -- for all contacts 
	--env.info("  :iterating allSubs done")
	-- now compare old contacts with new contacts
	-- if contact lost, remove wedge
	--env.info("  >start iterating buoy.contacts to find which contacts we lost")
	for aName, aP in pairs(theBuoy.contacts) do 
		if newContacts[aName] then 
			-- exists, therefore old contact. Keep it
			--[[-- code to update wedge removed
			if theBuoy.timeStamps[aName] + 60 * 2 < now then 
				-- update map: remove wedge 
				local shape = theBuoy.lines[aName]
				trigger.action.removeMark(shape)
				-- draw a new one 
				local pc = newContacts[aName] -- new probability 
				asw.wedgeForBuoyAndContact(theBuoy, aName, pc)
			end
			--]]--
		else 
			-- contact lost. remove wedge 
			local shape = theBuoy.lines[aName]
			if asw.verbose then 
				trigger.action.outText("+++ASW: will remove wedge <" .. shape .. ">", 30)
			end
			--env.info("  >removing wedge #" .. shape)
			trigger.action.removeMark(shape)
			--env.info("  >done removing wedge")
			-- delete this line entry 
			theBuoy.lines[aName] = nil 
		end
	end
	--env.info("  <iterating buoy.contacts for lost contact done")
	-- check if contact is new and add wedge if so 
	--env.info("  >start iterating newContacts for new contacts")
	for aName, aP in pairs(newContacts) do 
		if theBuoy.contacts[aName] then 
			-- exists, is old contact, do nothing 
		else 
			-- new contact, draw wedge  
			theBuoy.timeStamps[aName] = now 
			theBuoy.lines[aName] = dcsCommon.numberUUID() -- new shape ID
			asw.wedgeForBuoyAndContact(theBuoy, aName, aP)
			-- sound, but suppress ping if we have a fix for that sub 
			-- fixes are indexed by <subname>"/"<coalition>
			if theBuoy.coalition == 1 then -- and (not asw.fixes[aName .. "/" .. "1"])then 
				asw.newRedBuoyContact = true 
			elseif theBuoy.coalition == 2 then --and (not asw.fixes[aName .. "/" .. "2"]) then
				asw.newBlueBuoyContact = true 
			end
		end
	end
	--env.info("  >iterating newContacts for new contacts done")
	-- we may want to suppress beep if the sub is already in a fix 
	
	-- now save the new contacts and overwrite old 
	theBuoy.contacts = newContacts
	--env.info("  <<done update buoy for " .. theBuoy.name .. ", returning true")
	return true -- true = keep uoy alive 
end

function asw.hasFix(contact)
	-- determine if this sub can be fixed by the buoys 
	-- run down all buoys that currently see me 
	-- sub is only seen by opposing buoys.
	
	local bNum = 0
	local pTotal = 0
	local deltaB = 0
	local bearings = {}
	local subName = contact.name 
	for bName, p in pairs(contact.trackedBy) do 
		local theBuoy = asw.buoys[bName]
		-- CHECK FOR COALITION 
		-- make bnum to bnumred and bnumblue 
		if theBuoy.coalition == contact.coalition then 
			trigger.action.outText("+++Warning: same coa for buoy <" .. theBuoy.name .. "> and sub contact <" .. contact.name .. "> ", 30)
		end 
		bNum = bNum + 1 -- count number of tracking buoys 
		pTotal = pTotal + p 
		bearings[bName] = theBuoy.bearing[subName] - 180
		if bearings[bName] < 0 then bearings[bName] = bearings[bName] + 360 end 
	end
	
	local best90 = 0
	local above30 = 0 
	for bName, aBearing in pairs (bearings) do 
		for bbName, bBearing in pairs(bearings) do 
			local a = aBearing 
			if a > 180 then a = a - 180 end 
			local b = bBearing
			if b > 180 then b = b - 180 end 
			local d = math.abs(a - b) -- 0..180
			if d > 90 then d = 90 - (d-90) end -- d = 0..90
			local this90 = d 
			if this90 > 30 then above30 = above30 + 1 end 
			if this90 > best90 then best90 = this90 end 
		end
	end
	above30 = above30 / 2 -- number of buoys that have more than 30° angle to contact, by 2 because each counts twice.
	local solver = above30 * best90/90 * pTotal 
	if solver >= 2.0 then -- we have a fix
		return true
	end
	return false
end

function asw.updateFixes(allSubs)
	-- in order to create or maintain a fix, we need at least x 
	-- buoys with a confidence level of xx for that sub 
	-- and their azimuth must make at least 45 degrees so we 
	-- can make a fix 
	-- remember that buoys can only see subs of *opposing* side 
	local now = timer.getTime()
	
	for subName, contact in pairs(allSubs) do 
		-- calculate if we have a fix on this sub 
		local coa = dcsCommon.getEnemyCoalitionFor(contact.coalition) 
		-- if coa is nil, it's a neutral sub, and we skip 
		if coa and asw.hasFix(contact) then 
			-- if new fix? Access existing ones via fix name scheme
			-- fix naming scheme is to allow (later) detection of 
			-- same-side subs with buoys and not create a fix name 
			-- collision. Currently overkill 
			local theFix = asw.fixes[subName .. "/" .. tonumber(coa)]
			if theFix then
				-- exists, nothing to do
			else 
				-- create a new fix  
				theFix = asw.createFixForSub(contact.theUnit, coa)
				local theUnit = theFix.theUnit 
				local pos = theUnit:getPoint()
				local lat, lon, dep =  coord.LOtoLL(pos)
				local lla, llb = dcsCommon.latLon2Text(lat, lon)
				trigger.action.outTextForCoalition(coa, "NEW FIX " .. theFix.desig .. ": submerged contact, class <" .. theFix.typeName .. ">, location " .. lla .. ", " .. llb .. ", tracking.", 30)
				if coa == 1 then asw.newRedFix = true 
				elseif coa == 2 then asw.newBlueFix = true 
				end
				-- add fix to list of fixes 
				asw.fixes[subName .. "/" .. tonumber(coa)] = theFix 
			end 
			-- update life timer for all fixes 
			theFix.lifeTimer = now + asw.fixLife 
			trigger.action.outTextForCoalition(coa, "contact fix " .. theFix.desig .. " confirmed.", 30)
			if asw.verbose then 
				trigger.action.outText("renewed lease for fix " .. subName .. "/" .. tonumber(coa), 30)
			end 
		else 
			-- no new fix, 
		end
	end
	
	-- now iterate all fixes and update them, or time out
	local filtered = {}
	for fixName, theFix in pairs(asw.fixes) do 
		if now < theFix.lifeTimer and Unit.isExist(theFix.theUnit) then 
			-- update the location 
			if theFix.lines and theFix.lines > 0 then 
				-- remove old
				trigger.action.removeMark(theFix.lines)
			end
			-- allocate new fix id. we always need new fix id 
			theFix.lines = dcsCommon.numberUUID()
			-- mark on map for coalition 
			local theUnit = theFix.theUnit 
			local pos = theUnit:getPoint()
			-- assemble sub info 
			local vel = math.floor(1.94384 * dcsCommon.getUnitSpeed(theUnit))
			local heading = math.floor(dcsCommon.getUnitHeadingDegrees(theUnit))
			local delta = asw.fixLife - (theFix.lifeTimer - now) 
			local timeAgo = dcsCommon.processHMS("<m>:<:s>", delta)
			local info = "Submerged contact, identified as '" .. theFix.theUnit:getTypeName() .. "' class, moving at " .. vel .. " kts, heading " .. heading .. ", last fix " .. timeAgo .. " minutes ago."
			-- note: neet to change to markToCoalition! 
			trigger.action.markToCoalition(theFix.lines, info, pos, theFix.coalition, true, "")
			
			-- add to filtered
			filtered[fixName] = theFix
		else 
			-- do not add to filtered, timed out or unit destroyed  
			trigger.action.outTextForCoalition(theFix.coalition, "Lost fix for contact", 30)
			-- remove mark 
			if theFix.lines and theFix.lines > 0 then 
				trigger.action.removeMark(theFix.lines)
			end 
		end
	end
	
	asw.fixes = filtered 
end

function markTorpedo(theTorpedo)
	theTorpedo.markID = dcsCommon.numberUUID()
	trigger.action.markToCoalition(theTorpedo.markID, "Torpedo " .. theTorpedo.name, theTorpedo.point, theTorpedo.coalition, true, "")
end

function asw.updateTorpedo(theTorpedo, allSubs)
	-- homes in on closest torpedo, but only if it can detect it 
	-- else it simply runs in a random direction 
	
	-- remove old mark 
	if theTorpedo.markID then 
		trigger.action.removeMark(theTorpedo.markID)
	end 

	-- outside of lethal range, torp can randomly fail and never 
	-- re-aquire (lostTrack is true) unless it accidentally 
	-- gets into lethal range 

	-- see if it timed out 
	local now = timer.getTime()
	if now > theTorpedo.lifeTimer then 
		trigger.action.outTextForCoalition(theTorpedo.coalition, "Torpedo " .. theTorpedo.name .. " ran out", 30)
		return false
	end
	
	-- redraw mark for torpedo. give it a new 
	-- uuid every time 
	-- during update, it gets near and if it can get close 
	-- enough, it will set them up the bomb and create an explosion 
	-- near the sub it detected. 
	-- uses FSM 
	-- state 0 = dropped into water 
	if theTorpedo.state == 0 then 
		-- state 0: dropping in the water 
		trigger.action.outTextForCoalition(theTorpedo.coalition, "Torpedo " .. theTorpedo.name .. " in the water!", 30)
		theTorpedo.state = 1
		markTorpedo(theTorpedo)
		return true 
		
	elseif theTorpedo.state == 1 then 	
		-- seeking. get closest fix. if we have a fix in range 
		-- we go to stage homing, and it's a race between time and 
		-- and sub
		trigger.action.outTextForCoalition(theTorpedo.coalition, "Torpedo " .. theTorpedo.name .. " is seeking contact...", 30)
		
		-- select closest fix from same side as torpedo 
		local theFix, dist = asw.getClosestFixTo(theTorpedo.point, theTorpedo.coalition)
		
		if theFix and dist > asw.maxDetectionRange / 2 then 
			-- too far, forget it existed
			theFix = nil 
		end 
		
		if not theFix then 
			if asw.verbose then 
				trigger.action.outText("stage1: No fix/distance found for " .. theTorpedo.name, 30)
			end 
		else 
			if asw.verbose then 
				trigger.action.outText("stage1: found fix <" .. theFix.name .. "> at dist <" .. dist .. "> for " .. theTorpedo.name, 30)
			end 
		end
		
		if theFix and dist < 1700 then 
			-- have seeker, go to homing mode 
			theTorpedo.target = theFix.theUnit
			if asw.verbose then 
				trigger.action.outText("+++asw: target found: <" .. theTorpedo.target:getName() .. ">", 30)
			end 
			theTorpedo.state = 20 -- homing
			
		elseif theFix then 
			local B = theFix.theUnit:getPoint()
			theTorpedo.course = dcsCommon.bearingFromAtoB(theTorpedo.point, B)
			if asw.verbose then 
				trigger.action.outText("+++asw: unguided heading for <" .. theFix.theUnit:getName() .. ">", 30)
			end 
			theTorpedo.state = 10 -- directed run 
		else 
			-- no fix anywhere in range,
			-- simply pick a course and run
			-- maybe we get lucky 
			theTorpedo.course = 2 * 3.1415 * math.random()
			if asw.verbose then 
				trigger.action.outText("+++asw: random heading", 30)
			end
			theTorpedo.state = 10 -- random run 
		end
		
		markTorpedo(theTorpedo)
		return true 
		
	elseif theTorpedo.state == 10 then -- moving, not homing
		-- move torpedo and see if it's close enough to a sub 
		-- to track or blow up 
		local displacement = asw.torpedoSpeed * 1/asw.ups -- meters travelled
		if not theTorpedo.course then 
			theTorpedo.course = 0
			trigger.action.outText("+++ASW: Torpedo <" .. theTorpedo.name .. "> stage (10) with undefined course, setting 0", 30)
		end 
		
		theTorpedo.point.x = theTorpedo.point.x + displacement * math.cos(theTorpedo.course)
		theTorpedo.point.z = theTorpedo.point.z + displacement * math.sin(theTorpedo.course) 

		-- seeking ANY sub now. 
		-- warning: may go after our own subs as well, torpedo don't care!
		local theSub, dist = asw.getClosestSubToLoc(theTorpedo.point, allSubs)
		if dist < 1200 then 
			-- we lock on to this sub 
			theTorpedo.target = theSub
			theTorpedo.state = 20 -- switch to homing 
			trigger.action.outTextForCoalition(theTorpedo.coalition, "Torpedo " .. theTorpedo.name .. " is going active!", 30)
		end
		
		if dist < 1.2 * displacement then 
			theTorpedo.target = theSub
			theTorpedo.state = 99 -- go boom
		end
		markTorpedo(theTorpedo)
		return true 
		
	elseif theTorpedo.state == 20 then -- HOMING!
		if not Unit.isExist(theTorpedo.target) then 
			-- target was destroyed?
			if asw.verbose then 
				trigger.action.outText("+++asw: target lost", 30)
			end 
			theTorpedo.course = 2 * 3.1415 * math.random()
			theTorpedo.state = 10 -- switch to run free
			theTorpedo.target = nil 
			trigger.action.outTextForCoalition(theTorpedo.coalition, "Torpedo " .. theTorpedo.name .. " lost track, searching...", 30)
			return 
		end 
		
		if not theTorpedo.target then 
			-- sanity check
			theTorpedo.course = 2 * 3.1415 * math.random()
			theTorpedo.state = 10 -- switch to run free
			return 
		end

		-- we know that isExist(target)
		local B = theTorpedo.target:getPoint()
		theTorpedo.course = dcsCommon.bearingFromAtoB(theTorpedo.point, B)
		local displacement = asw.torpedoSpeed * 1/asw.ups -- meters travelled
		theTorpedo.point.x = theTorpedo.point.x + displacement * math.cos(theTorpedo.course)
		theTorpedo.point.z = theTorpedo.point.z + displacement * math.sin(theTorpedo.course) 
		local dist = dcsCommon.distFlat(theTorpedo.point, B)
		if dist < displacement then 
			theTorpedo.state = 99 -- boom, babe!
		else 
			local hdg = math.floor(57.2958 * theTorpedo.course)
			if hdg < 0 then hdg = hdg + 360 end 
			trigger.action.outTextForCoalition(theTorpedo.coalition, "Torpedo " .. theTorpedo.name .. " is homing, course " .. hdg .. ", " .. math.floor(dist) .. "m to impact", 30)
		end
		-- move to this torpedo and blow up 
		-- when close enough 
		markTorpedo(theTorpedo)
		
		return true 
	elseif theTorpedo.state == 99 then -- go boom 
		if Unit.isExist(theTorpedo.target) then 
			if asw.verbose then 
				trigger.action.outText("99 torpedoes have target", 30)
			end
			
			-- interface to playerScore 
			if cfxPlayerScore then 
				asw.doScore(theTorpedo)
			else 
				if asw.verbose then 
					trigger.action.outText("No playerScore present", 30)
				end
			end
			Unit.destroy(theTorpedo.target)
		else 
			if asw.verbose then 
				trigger.action.outText("t99 no target exist", 30)
			end
		end
		-- impact!
		trigger.action.outTextForCoalition(theTorpedo.coalition, "Impact for " .. theTorpedo.name .. "! We have confirmed hit on submerged contact!", 30)
		if theTorpedo.coalition == 1 then 
			if asw.redKill then 
				cfxZones.pollFlag(asw.redKill, asw.method, asw) 
			end
		elseif theTorpedo.coalition == 2 then 
			if asw.blueKill then 
				cfxZones.pollFlag(asw.blueKill, asw.method, asw) 
			end
		end
		
		-- make surface explosion 
		-- choose point 1m under water 
		local loc = theTorpedo.point
		local alt = land.getHeight({x = loc.x, y = loc.z})
		loc.y = alt-1
		trigger.action.explosion(loc, 3000)
		
		-- we are done 
		return false 

	else 
		-- we somehow ran into an unknown state
		trigger.action.outText("unknown torpedo state <" .. theTorpedo.state .. "> for <" .. theTorpedo.name .. ">", 20)
		return false
	end
	
	-- return true if it should be kept in array
	return true 
end

-- PlayerScore interface 
function processFeat(inMsg, playerUnit, victim, timeFormat)
	if not inMsg then return "<nil inMsg>" end
	-- replace <t> with current mission time HMS
	local absSecs = timer.getAbsTime()-- + env.mission.start_time
	while absSecs > 86400 do 
		absSecs = absSecs - 86400 -- subtract out all days 
	end
	if not timeFormat then timeFormat = "<:h>:<:m>:<:s>" end 
	-- <t>
	local timeString  = dcsCommon.processHMS(timeFormat, absSecs)
	local outMsg = inMsg:gsub("<t>", timeString)
	-- <n>
	outMsg = dcsCommon.processStringWildcards(outMsg) -- <n>
	-- <unit, type, player etc>
	outMsg = cfxPlayerScore.preprocessWildcards(outMsg, playerUnit, victim)
	return outMsg
end

function asw.doScore(theTorpedo)
	if asw.verbose then 
		trigger.action.outText("asw: enter doScore", 30)
	end
	-- make sure that this is a player-dropped torpedo 
	if not theTorpedo then 
		if asw.verbose then 
			trigger.action.outText("no torpedo", 30)
		end 
		return 
	end 
	local theUnit = theTorpedo.target
	if not theTorpedo.playerName then 
		if asw.verbose then 
			trigger.action.outText("no torpedo", 30)
		end 
		return 
	end 
	local pName = theTorpedo.playerName 
	-- make sure that the player's original unit still exists 
	if not (theTorpedo.droppedBy and Unit.isExist(theTorpedo.droppedBy)) then 
		if asw.verbose then 
			trigger.action.outText("torpedo dropper dead", 30)
		end 
		return -- torpedo-dropping unit did not survive 
	end 
	
	local fratricide = (theTorpedo.coalition == theUnit:getCoalition())
	if fratricide then 
		if asw.verbose then 
			trigger.action.outText("+++asw: fratricide detected", 30)
		end
	end
	
	if asw.killScore > 0 then 
		-- award score 
		local score = asw.killScore
		if fratricide then score = -1 * score end 
		cfxPlayerScore.logKillForPlayer(pName, theUnit)
		cfxPlayerScore.awardScoreTo(theTorpedo.coalition, score, pName)
		if asw.verbose then 
			trigger.action.outText("updated score (" .. score .. ") for player <" .. pName .. ">", 30)
		end 
	else 
		if asw.verbose then 
			trigger.action.outText("no score num defined", 30)
		end 
	end 
	
	if asw.killFeat and (not fratricide) then 
		-- we treat killFeat as boolean 
		local theFeat = "Killed type <type> submerged vessel <unit> at <t>"
		theFeat = processFeat(theFeat, theTorpedo.droppedBy, theUnit)
		cfxPlayerScore.logFeatForPlayer(pName, theFeat)
	else 
		if asw.verbose then 
			trigger.action.outText("no feat defined or fratricide", 30)
		end 
	end
end

--
-- MAIN UPDATE
--
-- does not find subs that have surfaced 
-- returns a list of 'contacts' - ready made tables 
-- to track the sub: who sees them (trackedBy) and misc
-- info.
-- contacts is indexed by unit name 
function asw.gatherSubs()
	local allCoas = {0, 1, 2}
	local subs = {}
	for idx, coa in pairs(allCoas) do 
		local allGroups = coalition.getGroups(coa, 3) -- ships only
		for idy, aGroup in pairs(allGroups) do 
			allUnits = aGroup:getUnits()
			for idz, aUnit in pairs(allUnits) do 
				-- see if this unit is a sub 
				if aUnit and Unit.isExist(aUnit) and 
				   (dcsCommon.getUnitAGL(aUnit) < -5) then	-- yes, submerged contact.
					local contact = {}
					contact.theUnit = aUnit
					contact.trackedBy = {} -- buoys that have a ping
					contact.name = aUnit:getName()
					contact.coalition = aUnit:getCoalition()
					subs[contact.name] = contact 
				end
			end
		end
	end
	return subs 
end

function asw.update()
	--env.info("-->Enter asw update")
	-- first, schedule next invocation 
	timer.scheduleFunction(asw.update, {}, timer.getTime() + 1/asw.ups)
	
	local subs = asw.gatherSubs() -- ALL contacts/subs
	
	asw.newRedBuoyContact = false 
	asw.newBlueBuoyContact = false 
	
	-- refresh all buoy detections
	-- if #asw.buoys > 0 then 
	--env.info("Before buoy proc")
	local filtered = {}
	for bName, theBuoy in pairs(asw.buoys) do 
		if asw.updateBuoy(theBuoy, subs) then 
			filtered[bName] = theBuoy
		end
	end
	asw.buoys = filtered
	--env.info("Complete buoy proc")
	
	if asw.newRedBuoyContact then 
		trigger.action.outSoundForCoalition(1, asw.sonarSound)
	end
	if asw.newBlueBuoyContact then 
		trigger.action.outSoundForCoalition(2, asw.sonarSound)
	end	
	
	
	-- update fixes: create if they don't exist
	asw.newBlueFix = false 
	asw.newRedFix = false 
	
	--env.info("Before fixes")
	asw.updateFixes(subs)
	--env.info("Complete fixes")
	
	if asw.newBlueFix then 
		trigger.action.outSoundForCoalition(2, asw.fixSound)
	end
	
	if asw.newRedFix then 
		trigger.action.outSoundForCoalition(1, asw.fixSound)
	end
		
	-- see if there are any torpedoes in the water 
	--if #asw.torpedoes > 0 then 
	--env.info("Before torpedoes")
	local filtered = {}
	for tName, theTorpedo in pairs(asw.torpedoes) do 
		if asw.updateTorpedo(theTorpedo, subs) then 
			filtered[tName] = theTorpedo
		end
	end
	asw.torpedoes = filtered

	--env.info("Complete torpedoes")

	--end
	--env.info("<--Leave asw update")
end

--
-- CONFIG & START
--
function asw.readConfigZone()
	local theZone = cfxZones.getZoneByName("aswConfig") 
	if not theZone then 
		if asw.verbose then 
			trigger.action.outText("+++asw: no config zone!", 30)
		end 
		theZone =  cfxZones.createSimpleZone("aswConfig")
	end 
	asw.verbose = theZone.verbose 
	asw.name = "aswConfig" -- make compatible with cfxZones 
	
	-- set defaults, later do the reading 
	asw.buoyLife = 30 * 60 -- 30 minutes life time 
	asw.buoyLife = cfxZones.getNumberFromZoneProperty(theZone, "buoyLife", asw.buoyLife)
	if asw.buoyLife < 1 then asw.buoyLife = 999999 end -- very, very long time 
	
	asw.maxDetectionRange = 12000 -- 12 km 
	asw.maxDetectionRange = cfxZones.getNumberFromZoneProperty(theZone, "detectionRange", 12000)
	asw.sureDetectionRange = 1000 -- inside 1 km will always detect sub
	asw.sureDetectionRange = cfxZones.getNumberFromZoneProperty(theZone, "sureDetect", 1000)
	asw.torpedoLife =  7 * 60 + 30 -- 7.5 minutes, will reach max range in that time  
	asw.torpedoSpeed = 28.3 -- speed in m/s -- 55 knots
	asw.maxDetectionDepth = 500 -- in meters. deeper than that, no detection. 
	asw.maxDetectionDepth = cfxZones.getNumberFromZoneProperty(theZone, "detectionDepth", 500)
	asw.fixLife = 3 * 60 -- a sub "fix" lives 3 minutes past last renew
	asw.fixLife = cfxZones.getNumberFromZoneProperty(theZone, "fixLife", asw.fixLife)
	if asw.fixLife < 1 then asw.fixLife = 999999 end -- a long time
	
	asw.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	asw.maxDeviation = 40 -- 40 degrees + 5 = 45 degrees left and right max deviation makes a worst-case 90 degree left/right wedge 
	asw.fixSound = "submarine ping.ogg"
	asw.fixSound = cfxZones.getStringFromZoneProperty(theZone, "fixSound", asw.fixSound)
	asw.sonarSound = "beacon beep-beep.ogg"
	asw.sonarSound = cfxZones.getStringFromZoneProperty(theZone, "sonarSound", asw.sonarSound)
	if cfxZones.hasProperty(theZone, "redKill!") then 
		asw.redKill = cfxZones.getStringFromZoneProperty(theZone, "redKill!", "none")
	end 
	if cfxZones.hasProperty(theZone, "blueKill!") then 
		asw.blueKill = cfxZones.getStringFromZoneProperty(theZone, "blueKill!", "none")
	end 
	
	asw.method = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	
	asw.smokeColor = cfxZones.getSmokeColorStringFromZoneProperty(theZone, "smokeColor", "red")
	asw.smokeColor = dcsCommon.smokeColor2Num(asw.smokeColor)
	asw.useSmoke = theZone:getBoolFromZoneProperty("useSmoke", true)
	
	asw.killScore = cfxZones.getNumberFromZoneProperty(theZone, "killScore", 0)
	
	if cfxZones.hasProperty(theZone, "killFeat") then 
		asw.killFeat = cfxZones.getStringFromZoneProperty(theZone, "killFeat", "Sub Kill")
	end	
	
	if asw.verbose then 
		trigger.action.outText("+++asw: read config", 30)
	end 

end

function asw.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx asw requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx asw", asw.requiredLibs) then
		return false 
	end
	
	-- read config 
	asw.readConfigZone()
	
	-- start update 
	asw.update()
	
	trigger.action.outText("cfx ASW v" .. asw.version .. " started.", 30)
	return true 
end

--
-- start up asw
--
if not asw.start() then 
	trigger.action.outText("cfx asw aborted: missing libraries", 30)
	asw = nil 
end

--[[--
	Ideas/to do
	- false positives for detections
	- triangle mark for fixes, color red 
	- squares for torps, color yellow
	- remove torpedoes when they run aground 
	
--]]--
