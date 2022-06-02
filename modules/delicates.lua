delicates = {}
delicates.version = "0.0.0"
delicates.verbose = false 
delicates.ups = 1 
delicates.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
delicates.theDelicates = {}

--[[--
	Version History 
	
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

function delicates.seeZoneInventory(theZone) 
	-- run a diag which objects are in the zone, and which cat they are
	-- set up args
	local allCats = {1, 2, 3, 4, 5, 6}
	-- Object.Category UNIT=1, WEAPON=2, STATIC=3, BASE=4, SCENERY=5, Cargo=6
	delicates.inventory = ""
	theZone.inventory = {}
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
		if #collector>0 then 
			trigger.action.outText("+++deli: zone " .. theZone.name, 30) 
			for idy, anObject in pairs(collector) do
				local oName = anObject:getName()
				if type(oName) == 'number' then oName = tostring(oName) end
				trigger.action.outText("+++deli: cat=".. aCat .. ":<" .. anObject:getName() .. ">", 30)
				local uP = anObject:getPoint()
				if cfxZones.isPointInsideZone(uP, theZone) then 
					table.insert(theZone.inventory, oName)
				else 
					trigger.action.outText("+++deli: (dropped)", 30)
				end 
			end
		end 
	end
end

function delicates.createDelicatesWithZone(theZone)
	-- read objects for this zone
	-- may want to filter by objects, can be passed in delicates
	delicates.seeZoneInventory(theZone) 


	
	if delicates.verbose or theZone.verbose then 
		trigger.action.outText("+++deli: new delicates zone <".. theZone.name ..">", 30)
	end
	
end

--
-- event handler 
--
function delicates:onEvent(theEvent)
	trigger.action.outText("yup", 30)
	if not theEvent then return end 
	if theEvent.id ~= 2 and theEvent.id ~= 23 then return end -- only hit and shooting start events 
	if not theEvent.target then return end 
	
	trigger.action.outText("+++deli: we hit " .. theEvent.target:getName(), 30)
	
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
	--delicates.update()
	
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