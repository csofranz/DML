delicates = {}
delicates.version = "1.1.0"
delicates.verbose = false 
delicates.ups = 1 
delicates.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
delicates.theDelicates = {}
delicates.inventory = {}

--[[--
	Version History 
	1.0.0 - initial version 
	1.1.0 - better synonym handling for f! and out!
	      - addStaticObjectInventoryForZone
		  - blowAll?
		  - safetyMargin - safety margin. defaults to 10%
	
	
--]]--
function delicates.adddDelicates(theZone)
	table.insert(delicates.theDelicates, theZone)
end

function delicates.getDelicatesByName(aName) 
	for idx, aZone in pairs(delicates.theDelicates) do 
		if aName == aZone.name then return aZone end 
	end
	if delicates.verbose then 
		trigger.action.outText("+++deli: no delicates with name <" .. aName ..">", 30)
	end 
	
	return nil 
end

--
-- read zone 
-- 
function delicates.objectHandler(theObject, theCollector)
	table.insert(theCollector, theObject)
	return true 
end

function delicates.makeZoneInventory(theZone) 

	local allCats = {1, 3, 6}
	-- Object.Category UNIT=1, WEAPON=2, STATIC=3, BASE=4, SCENERY=5, Cargo=6

	for idx, aCat in pairs(allCats) do 
		local p = cfxZones.getPoint(theZone)
		local lp = {x = p.x, y = p.z}
		p.y = land.getHeight(lp)
		local collector = {}
	
		-- now build the search argument 
		local args = {
				id = world.VolumeType.SPHERE,
				params = {
					point = p,
					radius = theZone.radius
				}
			}
	
		-- now call search
		world.searchObjects(aCat, args, delicates.objectHandler, collector)
		-- process results
		if #collector > 0 then 
			if theZone.verbose or delicates.verbose then 
				trigger.action.outText("+++deli: zone " .. theZone.name, 30)
			end 
			
			for idy, anObject in pairs(collector) do
				local oName = anObject:getName()
				if type(oName) == 'number' then oName = tostring(oName) end
				local oLife = anObject:getLife() - anObject:getLife() * theZone.safetyMargin
				if theZone.verbose or delicates.verbose then
					trigger.action.outText("+++deli: cat=".. aCat .. ":<" .. oName .. "> Life=" .. oLife, 30)
				end 
				local uP = anObject:getPoint()
				if cfxZones.isPointInsideZone(uP, theZone) then 

					local desc = {}
					desc.cat = aCat
					desc.oLife = oLife 
					desc.theZone = theZone 
					desc.oName = oName 
					delicates.inventory[oName] = desc
				else 
					if theZone.verbose or delicates.verbose then
						trigger.action.outText("+++deli: (dropped)", 30)
					end 
				end 
			end
		end 
	end
end

function delicates.addStaticObjectToInventoryForZone(theZone, theStatic)
	if not theZone then return end 
	if not theStatic then return end 
	
	local desc = {}
	desc.cat = theStatic:getCategory()
	desc.oLife = theStatic:getLife() - theStatic:getLife() * theZone.safetyMargin
	if desc.oLife < 0 then desc.oLife = 0 end 
	desc.theZone = theZone 
	desc.oName = theStatic:getName() 
	delicates.inventory[desc.oName] = desc
	
	if theZone.verbose or delicates.verbose then 
		trigger.action.outText("+++deli: added static <" .. desc.oName .. "> to <" .. theZone.name .. "> with minimal life = <" .. desc.oLife .. "/" .. theStatic:getLife() .. "> = safety margin of " .. theZone.safetyMargin * 100 .. "%", 30)
	end 
end 

function delicates.createDelicatesWithZone(theZone)
	theZone.power = cfxZones.getNumberFromZoneProperty(theZone, "power", 10)
	
	if cfxZones.hasProperty(theZone, "delicatesHit!") then
		theZone.delicateHit = cfxZones.getStringFromZoneProperty(theZone, "delicatesHit!", "*<none>")
	elseif cfxZones.hasProperty(theZone, "f!") then
		theZone.delicateHit = cfxZones.getStringFromZoneProperty(theZone, "f!", "*<none>")
	elseif cfxZones.hasProperty(theZone, "out!") then
		theZone.delicateHit = cfxZones.getStringFromZoneProperty(theZone, "out!", "*<none>")
	end
	
	-- safety margin
	theZone.safetyMargin = cfxZones.getNumberFromZoneProperty(theZone, "safetyMargin", 0)
	
	-- DML Method 
	theZone.delicateHitMethod = cfxZones.getStringFromZoneProperty(theZone, "method", "inc")
	if cfxZones.hasProperty(theZone, "delicateMethod") then 
		theZone.delicateHitMethod = cfxZones.getStringFromZoneProperty(theZone, "delicatesMethod", "inc")
	end
	
	theZone.delicateTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "thriggerMethod", "change")
	if cfxZones.hasProperty(theZone, "delicateTriggerMethod") then 
		theZone.delicateTriggerMethod = cfxZones.getStringFromZoneProperty(theZone, "delicatesMethod", "change")
	end
	
	theZone.delicateRemove = cfxZones.getBoolFromZoneProperty(theZone, "remove", true)
	
	-- read objects for this zone
	-- may want to filter by objects, can be passed in delicates
	delicates.makeZoneInventory(theZone) 
	
	if cfxZones.hasProperty(theZone, "blowAll?") then 
		theZone.blowAll = cfxZones.getStringFromZoneProperty(theZone, "blowAll?", "*<none>")
		theZone.lastBlowAll = cfxZones.getFlagValue(theZone.blowAll, theZone)
	end
	
	if delicates.verbose or theZone.verbose then 
		trigger.action.outText("+++deli: new delicates zone <".. theZone.name ..">", 30)
	end
	
end

--
-- blow me!
--
function delicates.scheduledBlow(args)
	local desc = args.desc 
	if not desc then return end 
	local oName = desc.oName 
	
	local theObject = nil 
	-- UNIT=1, WEAPON=2, STATIC=3, BASE=4, SCENERY=5, Cargo=6
	if desc.cat == 1 then 
		theObject = Unit.getByName(oName)
		if not theObject then 
			theObject = StaticObject.getByName(oName)
		end
	elseif desc.cat == 3 or desc.cat == 6 then 
		theObject = StaticObject.getByName(oName) 
	else
		-- can't handle at the moment
	end 
	
	local theZone = desc.theZone 
	local p = theObject:getPoint()
	local power = desc.theZone.power
	if desc.theZone.delicateRemove then 
		theObject:destroy()
	end
	
	trigger.action.explosion(p, power)
	
	-- bang out!
	if theZone.delicateHit then 
		cfxZones.pollFlag(theZone.delicateHit, theZone.delicateHitMethod, theZone)
		if delicates.verbose or theZone.verbose then 
			trigger.action.outText("+++deli: banging delicateHit! with <" .. theZone.delicateHitMethod .. "> on <" .. theZone.delicateHit .. "> for " .. theZone.name, 30)
		end
	end 
end

function delicates.blowUpObject(desc, delay)
	if not delay then delay = 0.5 end 
	if not desc then return end 
	local args = {}
	args.desc = desc 
	timer.scheduleFunction(delicates.scheduledBlow, args, timer.getTime() + delay)
	
end


--
-- event handler 
--
function delicates:onEvent(theEvent)
--	trigger.action.outText("yup", 30)
	if not theEvent then return end 
	local theObj = theEvent.target
	if not theObj then return end
	if theEvent.id ~= 2 and theEvent.id ~= 23 then return end -- only hit and shooting start events 
 
	local oName = theObj:getName()
	local desc = delicates.inventory[oName]
	if desc then 
		-- see if damage exceeds maximum 
		local cLife = theObj:getLife()
		if cLife < desc.oLife then
			if desc.theZone.verbose or delicates.verbose then 
				trigger.action.outText("+++deli: BRITTLE TRIGGER: life <" .. cLife .. "> below safety margin <" .. oDesc.oLife .. ">", 30)
			end
			delicates.blowUpObject(desc)
			-- remove it from further searches
			delicates.inventory[oName] = nil
		else 
			if desc.theZone.verbose or delicates.verbose then 
				trigger.action.outText("+++deli: CLOSE CALL, but life <" .. cLife .. "> within safety margin <" .. oDesc.oLife .. ">", 30)
			end
		end
	end
		
end

--
-- blow entire zone 
--
function delicates.blowZone(theZone)
	if not theZone then return end 
	local zName = theZone.name 
	local newInventory = {}
	local delay = 0.7
	for oName, oDesc in pairs (delicates.inventory) do 
		if oDesc.theZone.name == zName then 
			delicates.blowUpObject(oDesc, delay)
			delay = delay + 0.2 -- stagger explosions
		else 
			newInventory[oName] = oDesc
		end
	end

	delicates.inventory = newInventory
end

--
-- Update 
---

function delicates.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(delicates.update, {}, timer.getTime() + 1/delicates.ups)
			
	-- see if any deli was damaged and filter for next iter 
	local newInventory = {}
	for oName, oDesc in pairs(delicates.inventory) do 
		-- access the object 
		local theObj = nil 
		-- UNIT=1, WEAPON=2, STATIC=3, BASE=4, SCENERY=5, Cargo=6
		if oDesc.cat == 1 then 
			theObj = Unit.getByName(oName)
			if not theObj then 
				-- DCS now changes objects to static 
				-- so see if we can get this under statics 
				theObj = StaticObject.getByName(oName) 
				if theObj then 
--					trigger.action.outText("+++deli: Aha! caught smokin'!", 30)
				end
			end 
		elseif oDesc.cat == 3 or oDesc.cat == 6 then 
			theObj = StaticObject.getByName(oName) 
		else
			-- can't handle at the moment
		end 
		
		if theObj then 
			local cLife = theObj:getLife()
			if cLife >= oDesc.oLife then 
				-- all well, transfer to next iter 
				newInventory[oName] = oDesc
			else 
				-- health beneath min. blow stuff up 
				if oDesc.theZone.verbose or delicates.verbose then
					trigger.action.outText(oName .. " was hit, will blow up, current health is <" .. cLife .. ">, min health was " .. oDesc.oLife .. ".", 30)
				end 
				delicates.blowUpObject(oDesc)
			end
		else 
			-- nothing to do, don't transfer
			if oDesc.theZone.verbose or delicates.verbose then
				trigger.action.outText("+++deli: <" .. oName .. "> disappeared.", 30)
			end
		end
	end
	delicates.inventory = newInventory
	
	-- now scan all zones for signals 
	for idx, theZone in pairs(delicates.theDelicates) do 
		if theZone.blowAll and cfxZones.testZoneFlag(theZone, theZone.blowAll, theZone.delicateTriggerMethod, "lastBlowAll") then 
			delicates.blowZone(theZone)
		end
	end
end

--
-- Config & Start
--
function delicates.readConfigZone()
	local theZone = cfxZones.getZoneByName("delicatesConfig") 
	if not theZone then 
		if delicates.verbose then 
			trigger.action.outText("+++deli: NO config zone!", 30)
		end 
		return 
	end 
	
	delicates.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	
	if delicates.verbose then 
		trigger.action.outText("+++deli: read config", 30)
	end 
end

function delicates.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx delicates requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx delicates", delicates.requiredLibs) then
		return false 
	end
	
	-- read config 
	delicates.readConfigZone()
	
	-- process delicates Zones 
	-- old style
	local attrZones = cfxZones.getZonesWithAttributeNamed("delicates")
	for k, aZone in pairs(attrZones) do 
		delicates.createDelicatesWithZone(aZone) -- process attributes
		delicates.adddDelicates(aZone) -- add to list
	end
	
	-- start update 
	delicates.update()
	
	-- listen for events
    world.addEventHandler(delicates)
	
	trigger.action.outText("cfx delicates v" .. delicates.version .. " started.", 30)
	return true 
end

-- let's go!
if not delicates.start() then 
	trigger.action.outText("cfx delicates aborted: missing libraries", 30)
	delicates = nil 
end

-- To Do:
-- integrate with cloners and spawners 