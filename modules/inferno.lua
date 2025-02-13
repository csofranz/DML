inferno = {}
inferno.version = "1.0.1"
inferno.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
}

--[[-- Version History
	1.0.0 - Initial version 
	1.0.1 - cleanup 
--]]--
--
-- Inferno models fires inside inferno zones. Fires can spread and 
-- be extinguished by aircraft from the airtank module 
-- (c) 2024 by Christian "cfrag" Franz 
--
inferno.zones = {}
inferno.maxStages = 10 -- tied to fuel consumption, 1 burns small, maxStages at max size. A burning fire untended increases in stage by one each tick until it reaches maxStages
inferno.threshold = 4.9 -- when fire spreads to another field 
inferno.fireExtinguishedCB = {} -- CB for other modules / scripts  

--
-- CB 
--
function inferno.installExtinguishedCB(theCB)
	table.insert(inferno.fireExtinguishedCB, theCB)
end

function inferno.invokeFireExtinguishedCB(theZone)
	for idx, cb in pairs(inferno.fireExtinguishedCB) do 
		cb(theZone, theZone.heroes)
	end
end

--
-- Reading zones 
--
function inferno.addZone(theZone)
	inferno.zones[theZone.name] = theZone
end

function inferno.buildGrid(theZone)
	-- default for circular zone 
	local radius = theZone.radius
	local side = radius * 2
	local p = theZone:getPoint()
	local minx = p.x - radius
	local minz = p.z - radius
	local xside = side 
	local zside = side 
	local xradius = radius 
	local zradius = radius 
	if theZone.isPoly then 
		-- build the params for a (rectangular) zone from a 
		-- quad zone, makes area an AABB (axis-aligned bounding box)
		minx = theZone.bounds.ll.x 
		minz = theZone.bounds.ll.z 
		xside = theZone.bounds.ur.x - theZone.bounds.ll.x
		zside = theZone.bounds.ur.z - theZone.bounds.ll.z		
	end
	local cellx = theZone.cellSize -- square cells assumed 
	local cellz = theZone.cellSize 
	local numX = math.floor(xside / cellx)
	if numX < 1 then numX = 1 end 
	if numX > 100 then 
		trigger.action.outText("***inferno: limited x from <" .. numX .. "> to 100", 30)
		numX = 100
	end 
	
	local numZ = math.floor(zside / cellz)
	if numX > 100 then 
		trigger.action.outText("***inferno: limited z from <" .. numZ .. "> to 100", 30)
		numZ = 100
	end 
	if numZ < 1 then numZ = 1 end 
	if theZone.verbose then 
		trigger.action.outText("infernal zone <" .. theZone.name .. ">: cellSize <" .. theZone.cellSize .. "> --> x <" .. numX .. ">, z <" .. numZ .. ">", 30)
	end
	local grid = {}
	local goodCells = {}
	-- Remember that in DCS 
	-- X is North/South, with positive X being North/South
	-- and Z is East/West with positve Z being EAST
	local fCount = 0
	theZone.burning = false 
	for x=1, numX do -- "up/down"
		grid[x] = {}
		for z=1, numZ do -- "left/right"
			local ele = {}
			-- calculate center for each cell
			local xc = minx + (x-1) * cellx + cellx/2
			local zc = minz + (z-1) * cellz + cellz/2 
			local xf = xc 
			local zf = zc 

			local lp = {x=xc, y=zc}
			local yc = land.getHeight(lp)
			ele.center = {x=xc, y=yc, z=zc}
			ele.fxpos = {x=xf, y=yc, z=zf}
			ele.myType = land.getSurfaceType(lp) -- LAND=1, SHALLOW_WATER=2, WATER=3, ROAD=4, RUNWAY=5
			-- we do not burn if a cell has shallow or deep water, or roads or runways 
			ele.inside = theZone:pointInZone(ele.center)
			if theZone.freeBorder then 
				if x == 1 or x == numX then ele.inside = false end
				if z == 1 or z == numZ then ele.inside = false end 
			end
			ele.myStage = 0 -- not burning 
			if ele.inside and ele.myType == 1 then -- land only 
				-- create a position for the fire -- visual only 
				if theZone.stagger then
					repeat 
						xf = xc + (0.5 - math.random()) * cellx 
						zf = zc + (0.5 - math.random()) * cellz 
						lp = {x=xf, y=zf}
					until land.getSurfaceType(lp) == 1 
					ele.fxpos = {x=xf, y=yc, z=zf}
				end
				local sparkable = {x=x, z=z}
				table.insert(goodCells, sparkable)
				fCount = fCount + 1 
			else 
				ele.inside = false -- optim: not in poly or burnable
			end
			ele.fuel = theZone.fuel -- use rnd?  
			ele.eternal = theZone.eternal -- unlimited fuel 
			grid[x][z] = ele
		end -- for z 
	end -- for x 
	if theZone.verbose then 
		trigger.action.outText("inferno: zone <" .. theZone.name .. "> has <" .. fCount .. "> hot spots", 30)
	end 
	if fCount < 1 then 
		trigger.action.outText("WARNING: <" .. theZone.name .. "> has no good burn cells!", 30)
	end
	theZone.numX = numX
	theZone.numZ = numZ 
	theZone.minx = minx 
	theZone.minz = minz 
	theZone.xside = xside 
	theZone.grid = grid 
	theZone.goodCells = goodCells
	
	-- find bestCell from goodCells closest to center 
	local bestdist = math.huge 
	local bestCell = nil 
	for idx, aCell in pairs(goodCells) do 
		local x = aCell.x 
		local z = aCell.z 
		local ele = grid[x][z]
		local cp = ele.center 
		local d = dcsCommon.dist(cp, p)
		if d < bestdist then 
			bestCell = aCell
			bestdist = d 
		end
	end
	theZone.bestCell = bestCell
end

function inferno.readZone(theZone)
	theZone.cellSize = theZone:getNumberFromZoneProperty("cellSize", inferno.cellSize)
	-- FUEL: amount of fuel to burn PER CELL. when at zero, fire goes out
	-- expansion: make it a random range 
	theZone.fuel = theZone:getNumberFromZoneProperty("fuel", 100)
	theZone.rndLoc = theZone:getBoolFromZoneProperty("rndLoc", false)
	theZone.freeBorder = theZone:getBoolFromZoneProperty("freeBorder", true) -- ring zone with non-burning zones
	theZone.eternal = theZone:getBoolFromZoneProperty("eternal", true)
	theZone.stagger = theZone:getBoolFromZoneProperty("stagger", true) -- randomize inside cell
--	theZone.fullBlaze = theZone:getBoolFromZoneProperty("fullBlaze", false )
	theZone.canSpread = theZone:getBoolFromZoneProperty("canSpread", true)
	theZone.maxSpread = theZone:getNumberFromZoneProperty("maxSpread", 999999)
	theZone.impactSmoke = theZone:getBoolFromZoneProperty("impactSmoke", inferno.impactSmoke)
	theZone.markCell = theZone:getBoolFromZoneProperty("markCell", false)
	inferno.buildGrid(theZone)
	theZone.heroes = {} -- remembers all who dropped into zone 
	theZone.onStart = theZone:getBoolFromZoneProperty("onStart", false)
	if theZone:hasProperty("ignite?") then 
		theZone.ignite = theZone:getStringFromZoneProperty("ignite?", "none")
		theZone.lastIgnite = trigger.misc.getUserFlag(theZone.ignite)
	end 
	if theZone:hasProperty("douse?") then 
		theZone.douse = theZone:getStringFromZoneProperty("douse?", "none")
		theZone.lastDouse = trigger.misc.getUserFlag(theZone.douse)
	end 
	if theZone:hasProperty("extinguished!") then 
		theZone.extinguished = theZone:getStringFromZoneProperty("extinguished", "none")
	end
	
end
--
-- API for water droppers 
--
function inferno.surroundDelta(theZone, p, x, z) 
	if x < 1 then return math.huge end 
	if z < 1 then return math.huge end 
	if x > theZone.numX then return math.huge end 
	if z > theZone.numZ then return math.huge end 
	local ele = theZone.grid[x][z]
	if not ele then return math.huge end 
	if not ele.inside then return math.huge end 
	if not ele.sparked then return math.huge end 
	if ele.myStage < 1 then return math.huge end 
	return dcsCommon.dist(p, ele.fxpos)
end 

function inferno.waterInZone(theZone, p, amount)
	-- water dropped (as point source) into a inferno zone. 
	-- find the cell that it was dropped in 
	local x = p.x - theZone.minx 
	local z = p.z - theZone.minz 
	local xc = math.floor(x / theZone.cellSize) + 1 -- square cells!
	if xc > theZone.numX then return nil end -- xc = theZone.numX end -- was cut off, 
	local zc = math.floor(z / theZone.cellSize) + 1
	if zc > theZone.numZ then return nil end -- zc = theZone.numZ end 
	local row = theZone.grid[xc]
	if not row then 
		trigger.action.outText("inferno.waterinZone: cannot access row for xc = " .. xc .. ", x = " .. x .. ", numX = " .. theZone.numX .. " in " .. theZone.name, 30)
		return "NIL row for xc " .. xc .. ", zc " .. zc .. " in " .. theZone.name 
	end 
	local ele = row[zc]
	
	if not ele then 
		trigger.action.outText("Inferno: no ele for <" .. theZone.name .. ">: x<" .. x .. ">z<" .. z .. ">", 30)
		trigger.action.outText("with xc = " .. xc .. ", numX 0 " .. theZone.numX .. ", zc = " .. zc .. ", numZ=" .. theZone.numZ, 30)
		return "NIL ele for x" .. xc .. ",z" .. zc .. " in " .. theZone.name 
	end 
	
	-- empty ele pre-proccing: 
	-- if not burning, see if we find a better burning cell nearby  
	if (not ele.sparked) or ele.extinguished then  -- not burning, note that we do NOT test inside here!
		local hitDelta = math.sqrt(2) * theZone.cellSize -- dcsCommon.dist(p, ele.center) + 0.5 * theZone.cellSize -- give others a chance
		local bestDelta = hitDelta 
		local ofx = 0
		local ofz = 0 
		for dx = -1, 1 do 
			for dz = -1, 1 do 
				if dx == 0 and dz == 0 then -- skip this one
				else 
					local newDelta = inferno.surroundDelta(theZone, p, xc + dx, zc + dz)
					if newDelta < bestDelta then 
						bestDelta = newDelta
						ofx = dx
						ofz = dz
					end
				end
			end	
		end 
		xc = xc + ofx 
		zc = zc + ofz 
		ele = theZone.grid[xc][zc]
	end 
	if theZone.impactSmoke then 
		if inferno.verbose then 
			trigger.action.smoke(ele.center, 1) -- red is ele center
		end
		trigger.action.smoke(p, 4) -- blue is actual impact 
	end
	
	-- inside?	
	if ele.inside then 
		-- force this cell's eternal to OFF, now it consumes fuel 
		ele.eternal = false -- from now on, this cell burns own fuel 

		if not ele.sparked then 
			-- not burning. remove all fuel, make it 
			-- extinguished so it won't catch fire in the future 
			ele.extinguished = true -- will now negatively contribute 
			ele.fuel = 0 
			return "Good peripheral delivery, will prevent spread."
		end 
		
		-- calculate dispersal of water. the higher, the more dispersed 
		-- and less fuel on the ground is 'removed' 	
		local dispAmount = amount -- currently no dispersal, full amount hits ground
		ele.fuel = ele.fuel - dispAmount
		
		-- we can restage fx to smaller fire and reset stage 
		-- so fire consumes less fuel ?
		-- NYI, later.
		return "Direct delivery into fire cell!" 
	end 

	-- not inside or a water tile 
	return nil 
end

function inferno.waterDropped(p, amount, data) -- if returns non-nil, has hit a cell 
	-- p is (x, 0, z) of where the water hits the ground
	for name, theZone in pairs(inferno.zones) do 
		if theZone:pointInZone(p) then 
			if inferno.verbose then 
				trigger.action.outText("inferno: INSIDE <" .. theZone.name .. ">", 30)
			end
			-- if available, remember and increase the number of drops in 
			-- zone for player 
			if data and data.pName then 
				if not theZone.heroes then theZone.heroes = {} end 
				if theZone.heroes[data.pName] then 
					theZone.heroes[data.pName] = theZone.heroes[data.pName] + 1
				else 
					theZone.heroes[data.pName] = 1
				end

			end 
			return inferno.waterInZone(theZone, p, amount)
		end
	end
	if inferno.impactSmoke then 
		-- mark the position with a blue smoke 
		trigger.action.smoke(p, 4)
	end
	if inferno.verbose then 
		trigger.action.outText("water drop outside any inferno zone", 30)
	end
	return nil 
end
--
-- IGNITE & DOUSE 
--
function inferno.sparkCell(theZone, x, z)
	local ele = theZone.grid[x][z]
	if not ele.inside then 
		if theZone.verbose then trigger.action.outText("ele x<" .. x .. ">z<" .. z .. "> is outside, no spark!", 30) end 
		return 
	false end 
	ele.fxname = dcsCommon.uuid(theZone.name)
	trigger.action.effectSmokeBig(ele.fxpos, 1, 0.5 , ele.fxname)
	ele.myStage = 1 
	ele.fxsize = 1
	ele.sparked = true 
	return true 	
end 

function inferno.ignite(theZone)
	if theZone.burning then
		-- later expansion: add more fires 
		-- will give error when fullblaze is set 
		trigger.action.outText("Zone <" .. theZone.name .. "> already burning", 30)
		return 
	end
	if theZone.verbose then 
		trigger.action.outText("igniting <" .. theZone.name .. ">", 30)
	end 
		
	local midNum = math.floor((#theZone.goodCells + 1)/ 2)
	if midNum < 1 then midNum = 1 end
	local midCell = theZone.bestCell
	if not midCell then midCell = theZone.goodCells[midNum] end 
	if theZone.rndLoc then midCell = dcsCommon.pickRandom(theZone.goodCells) end 
	local x = midCell.x 
	local z = midCell.z 
	
	if inferno.sparkCell(theZone, x, z) then 
		if theZone.verbose then 
			trigger.action.outText("Sparking cell x<" .. x .. ">z<" .. z .. "> for <" .. theZone.name .. ">", 30)
		end
	else 
		trigger.action.outText("Inferno: fire in <" .. theZone.name .. "> @ center x<" .. x .. ">z<" .. z .. "> didin't catch", 30)
	end
	theZone.hasSpread = 0 -- how many times we have spread 
	theZone.burning = true 
end

function inferno.startFire(theZone)
	if theZone.burning then return end
	inferno.ignite(theZone)
end

function inferno.douseFire(theZone)
	-- walk the grid, and kill all flames, set all eles 
	-- to end state 
	for x=1, theZone.numX do
		for z=1, theZone.numZ do
			local ele = theZone.grid[x][z]
			if ele.inside then 
				if ele.fxname then 
					trigger.action.effectSmokeStop(ele.fxname)
				end 
			end
		end
	end 
	inferno.buildGrid(theZone) -- prep next fire in here 
	theZone.heroes = {}
	theZone.burning = false 
end

--
-- Fire Tick: progress/grow fire, burn fuel, expand conflagration etc. 
--
function inferno.fireUpdate() -- update all burning fires 
--[[--	
	every tick, we progress the fire status of all cells 
	fire stages (per cell):
	< 1 : not burning, perhaps dying
	0 : not burning, not smoking 
	-1..-5 : smoking. the closer to 0, less smoke 
	1..10 : burning, number = flame size, contib. heat and fuel consumption
--]]-- 
	timer.scheduleFunction(inferno.fireUpdate, {}, timer.getTime() + inferno.fireTick) -- next time 
	for zName, theZone in pairs(inferno.zones) do 
		if theZone.fullBlaze then 
			-- do nothing, just testing layout
		elseif theZone.burning then 
			inferno.burnOneTick(theZone) -- expand fuel, see if it spreads 
		end
	end
end 

function inferno.burnOneTick(theZone)
	-- iterate all cells and see if the fire spreads 
	local isBurning = false 
	local grid = theZone.grid
	local newStage = {} -- new states 
	local numX = theZone.numX
	local numZ = theZone.numZ
	-- pass 1:
	-- calculate new stages 
	for x = 1, numX do -- up 
		newStage[x] = {}
		for z = 1, numZ do 
			local ele = grid[x][z]
			if ele.inside then
				local stage = ele.myStage
				-- we will only continue burning if we have fuel 
				if ele.extinguished then 
					-- we are drenched and can't re-ignite 
					newStage[x][z] = 0 
				elseif ele.fuel > 0 then -- we have fuel
					if stage > 0 then -- it's already burning
						if not ele.eternal then 
							ele.fuel = ele.fuel - stage -- consume fuel if burning and not eternal 
							if theZone.verbose then 
								trigger.action.outText(stage .. " fuel consumed. remain: "..ele.fuel, 30)
							end 
						end 
						stage = stage + 1
						if stage > inferno.maxStages then 
							stage = inferno.maxStages
						end 
						newStage[x][z] = stage -- fire is growing 
					elseif stage < 0 then 
						-- fire is dying, can't be here if fuel > 0 
						newStage[x][z] = stage 
					else -- not burning. see if the surrounding sides are contributing 
						if theZone.canSpread and (theZone.hasSpread < theZone.maxSpread) then 
							local accu = 0 
							-- now do all surrounding 8 fields 
							-- NOTE: use wind direction to modify below if we use wind 	- NYI						
							accu = accu + inferno.contribute(x-1, z-1, theZone)
							accu = accu + inferno.contribute(x, z-1, theZone)
							accu = accu + inferno.contribute(x+1, z-1, theZone)
							accu = accu + inferno.contribute(x-1, z, theZone)
							accu = accu + inferno.contribute(x+1, z, theZone)
							accu = accu + inferno.contribute(x-1, z+1, theZone)
							accu = accu + inferno.contribute(x, z+1, theZone)
							accu = accu + inferno.contribute(x+1, z+1, theZone)
							accu = accu / 2 -- half intensity 
							-- 10% chance to spread when above threshold
							if accu > inferno.threshold and math.random() < 0.1 then 
								stage = 1 -- start small fire  
								theZone.hasSpread = theZone.hasSpread + 1 
							end 
						end 
						newStage[x][z] = stage 
					end 
				else -- fuel is spent let flames die down if they exist 
					if stage == 0 then -- wasn't burning before
						newStage[x][z] = 0
					else 
						if stage > 0 then 
							newStage[x][z] = stage - 1
							if newStage[x][z] == 0 then 
								newStage[x][z] = - 5
							end 
						else 
							newStage[x][z] = stage + 1
						end
					end 
				end 
			else 
				newStage[x][z] = 0 -- outside, will always be 0
			end 
		end -- for z
	end -- for x 
	-- pass 2:
	-- see what changed and handle accordingly  
	for x = 1, numX do -- up 
		for z = 1, numZ do
			local ele = grid[x][z]
			if ele.inside then 
				local stage = ele.myStage
				
				local ns = newStage[x][z]
				if not ns then ns = 0 end 
				if theZone.verbose and ele.sparked then 
					trigger.action.outText("x<" .. x .. ">z<" .. z .. "> - next stage is " .. ns, 30)
				end
				if ns ~= stage then 
					-- fire has changed: spread or dying down
					if stage == 0 then -- fire has spread!
						if theZone.verbose then 
							trigger.action.outText("Fire in <" .. theZone.name .. "> has spread to x<" .. x .. ">z<" .. z .. ">", 30)
						end
						ele.sparked = true 
					elseif ns == 0 then -- fire has died down fully 
						if theZone.verbose then 
							trigger.action.outText("Fire in <" .. theZone.name .. "> at x<" .. x .. ">z<" .. z .. "> has been extinguished", 30)
						end
					end
			
					-- handle fire fx 
					-- determine fx number 
					local fx = 0 
					if stage > 0 then 
						fx = math.floor(stage / 2) -- 1..10--> 1..4
						if fx < 1 then fx = 1 end 
						if fx > 4 then fx = 4 end 
						isBurning = true 
					elseif stage < 0 then 
						fx = 4-stage  -- -5 .. -1 --> 6..10 
						if fx < 5 then fx = 5 end 
						if fx > 8 then fx = 8 end 
						isBurning = true -- keep as 'burning'
					end
					if fx ~= ele.fxsize then 
						if ele.fxname then 
							if theZone.verbose then 
								trigger.action.outText("removing old fx <" .. ele.fxsize .. "> [" .. ele.fxname .. "] for <" .. fx .. "> in <" .. theZone.name .. "> x<" .. x .. ">z<" .. z .. ">", 30)
							end
							-- remove old fx 
							trigger.action.effectSmokeStop(ele.fxname)
						end 
						 -- start new 
						if fx > 0 then 
							ele.fxname = dcsCommon.uuid(theZone.name)
							trigger.action.effectSmokeBig(ele.fxpos, fx, 0.5 , ele.fxname)
						else 
							if theZone.verbose then 
								trigger.action.outText("expiring <" .. theZone.name .. "> x<" .. x .. ">z<" .. z .. ">", 30)
							end
						end 
						ele.fxsize = fx 
					end
					-- save new stage
					ele.myStage = ns
				else 
					if not ele.sparked then 
						-- not yet ignited, ignore 
					elseif ele.extinguished then 
						-- ignore, we are already off 
					elseif stage ~= 0 then 
						-- still burning bright 
						isBurning = true 
					else 
						-- remove last fx 
						trigger.action.effectSmokeStop(ele.fxname)
						-- clear this zone or add debris now?
						ele.extinguished = true -- now can't re-ignite 
					end
				end -- if ns <> stage
			end -- if inside 
		end -- for z 
	end -- for x 
	if not isBurning then 
		trigger.action.outText("inferno in <" .. theZone.name .. "> has been fully extinguished", 30)
		theZone.burning = false 
		if theZone.extinguished then 
			theZone:pollFlag(theZone.extinguished, "inc")
		end 
		inferno.invokeFireExtinguishedCB(theZone)
		-- also fully douse this one, so we can restart it later 
		inferno.douseFire(theZone)
	end 
end

function inferno.contribute(x, z, theZone)
-- a cell starts burning if there is fuel 
-- and the total contribution of all surrounding cells is 
-- 10 or more, meaning that a 10 fire will ignite all surrounding 
-- fields 
	-- bounds check 
	if x < 1 then return 0 end 
	if z < 1 then return 0 end 
	local numX = theZone.numX
	if x > numX then return 0 end 
	local numZ = theZone.numZ
	if z > numZ then return 0 end
	local ele = theZone.grid[x][z]
	if not ele.inside then return 0 end 
	if not ele.sparked then return 0 end -- not burning 
	if ele.extinguished then return -2 end -- water spill dampens  
	-- return stage that we are in if > 0 
	if ele.myStage >= 0 then 
		return ele.myStage -- mystage is positive int, "heat" 1..10
	end 
		
	return 0
end
--
-- UPDATE
--
function inferno.update() -- for flag polling etc 
	timer.scheduleFunction(inferno.update, {}, timer.getTime() + 1/inferno.ups)
	local fireNum = 0
	for idx, theZone in pairs (inferno.zones) do 
		if theZone.ignite and 
		theZone:testZoneFlag(theZone.ignite, "change", "lastIgnite") then
			inferno.startFire(theZone)
		end
		
		if theZone.douse and theZone:testZoneFlag(theZone.douse, "change", "lastDouse") then 
			inferno.douseFire(theZone)
		end
		if theZone.burning then 
			fireNum = fireNum + 1 
		end
	end
	if inferno.fireNum then 
		 trigger.action.setUserFlag(inferno.fireNum, fireNum)
	end
end

--
-- CONFIG & START
--
function inferno.readConfigZone()
	inferno.name = "infernoConfig" -- make compatible with dml zones 
	local theZone = cfxZones.getZoneByName("infernoConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("infernoConfig") 
	end 
	
	inferno.verbose = theZone.verbose
	inferno.ups = theZone:getNumberFromZoneProperty("ups", 1)
	inferno.fireTick = theZone:getNumberFromZoneProperty("fireTick", 10)
	inferno.cellSize = theZone:getNumberFromZoneProperty("cellSize", 100)

	if theZone:hasProperty("fire#") then 
		inferno.fireNum = theZone:getStringFromZoneProperty("fire#", "none")
	end 

end

function inferno.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx inferno requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx inferno", inferno.requiredLibs) then
		return false 
	end
	
	-- read config 
	inferno.readConfigZone()

	-- process inferno Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("inferno")
	for k, aZone in pairs(attrZones) do 
		inferno.readZone(aZone) -- process attributes
		inferno.addZone(aZone) -- add to list
	end
		
	-- start update (DML)
	timer.scheduleFunction(inferno.update, {}, timer.getTime() + 1/inferno.ups)
	
	-- start fire tick update 
	timer.scheduleFunction(inferno.fireUpdate, {}, timer.getTime() + inferno.fireTick)
	
	-- start all zones that have onstart 
	for gName, theZone in pairs(inferno.zones) do 
		if theZone.onStart then 
			inferno.ignite(theZone)
		end
	end 
	-- say Hi!
	trigger.action.outText("cf/x inferno v" .. inferno.version .. " started.", 30)
	return true 
end

if not inferno.start() then 
	trigger.action.outText("inferno failed to start up")
	inferno = nil 
end 

--[[--
	"ele" structure in grid 
	- fuel amount of fuel to burn. when < 0 the fire starves over the next cycles. By dumping water helicopters/planes reduce amount of available fuel 
	- extinguished if true, can't re-ignite 
	- myStage -- FSM for flames: >0 == burning, consumes fuel, <0 is starved of fuel and get smaller each tick 
	- fxname to reference flame fx 
	- eternal if true does not consume fuel. goes false when the first drop of water enters the cell from players 
	
	- center point of center 
	- fxpos - point in cell that has the fx 
	- mytype land type. only 1 burns 
	- inside is it inside the zone and can burn? true if so. used to make cells unburnable
	- sparked if false this isn't burning 
	

to do: 
OK - callback for extinguis 
OK - remember who contributes dropped inside successful and then receives ack when zone fully doused 
	
Possible enhancements
- random range fuel 
- wind for contribute (can precalc into table)
- boom in ignite 
- clear after burn out 
- leave debris after burn out, mabe place in ignite 
--]]--