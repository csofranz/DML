nameStats = {}
nameStats.version = "1.1.0"
--[[--
  package that allows generic and global access to data, stored by 
  name and path. Can be used to manage score, cargo, statistics etc.
  provides its own root by default, but modules can provide their own 
  private roots to be managed the same way.
  
  Uses a path metaphor to access fine grained levels
  
	version history 
	1.0.0 - initial release 
	1.1.0 - added table to leaf for more general 
	      - added ability to use arbitrary roots
		  - setValue 
		  - reset
		  - getAllPathes
	1.1.1 - simplified strings to a single string 
	      - left old logic intact for log extensions
		  - setString()
	
--]]--
-- statistics container. everything is in here
 
nameStats.stats = {}

--[[--
	to access data, there are the following principles:
	- name: uniquely defines a branch where all data for this name 
	        is stored. MANDATORY, MUST NEVER BE nil
			this is usually a unit's name 
	- path: in each branch you can have a path (string) to the data 
	        to more precisely define. for example, you can have separate 
			paths 'score' and 'weight' under the same name 
			There currently is no logic attached to a path except that
			it must be unique inside the same branch
	        OPTIONAL. if omittted, a default data set is returned
	- rootNode: OPTIONAL storage (table) you can pass to create your own 
	        pricate storage space that can't be accessed unless the 
			invoking method also passes the same rootNode 
	
	Data 
		Data is stored in a "leaf node" that has three properties
		- value: a numerical value that can be set and changed
		- string: a strings that can be set and added to 
		- table: a table that you can treat as you like and that     
		         is never looked into nor changed by this module 
				 
--]]--

function nameStats.getAllNames(theRootNode) -- root node is optional
	if not theRootNode then theRootNode = nameStats.stats end  
	local allNames = {}
	for name, entry in pairs(theRootNode) do 
		table.insert(allNames, name)
	end
	return allNames
end

function nameStats.getAllPathes(name, theRootNode)
	if not theRootNode then theRootNode = nameStats.stats end 
	local allPathes = {}
	local theEntry = theRootNode[name]
	if not theEntry then 
		return allPathes 
	end
	
	for pathName, data in pairs(theEntry.data) do 
		table.insert(allPathes, pathName)
	end
	
	return allPathes
end

-- change the numerical value by delta. use negative numbers to decrease
function nameStats.changeValue(name, delta, path, rootNode)
	if not name then return nil end 
	local theLeaf = nameStats.getLeaf(name, path, rootNode)
	theLeaf.value = theLeaf.value + delta
	return theLeaf.value 
end

-- set to a specific value 
function nameStats.setValue(name, newVal, path, rootNode)
	if not name then return nil end 
	local theLeaf = nameStats.getLeaf(name, path, rootNode)
	theLeaf.value = newVal
	return theLeaf.value 
end

-- add a string to the log
function nameStats.addString(name, aString, path, rootNode)
	if not name then return nil end 
	if not aString then return nil end 
	local theLeaf = nameStats.getLeaf(name, path, rootNode)
	--table.insert(theLeaf.strings, aString)
	theLeaf.strings = theLeaf.strings .. aString
--	return aString
end

-- reset the log
function nameStats.removeAllString(name, path, rootNode)
	if not name then return nil end 
	local theLeaf = nameStats.getLeaf(name, path, rootNode)
--	theLeaf.strings = {}
	theLeaf.strings = ""
end

function nameStats.setString(name, aString, path, rootNode)
	if not name then return nil end 
	local theLeaf = nameStats.getLeaf(name, path, rootNode)
	theLeaf.strings = aString
end

-- set the table variable
function nameStats.setTable(name, path, aTable, rootNode)
	if not name then return end 
	local theLeaf = nameStats.getLeaf(name, path, rootNode)
	theLeaf.theTable = aTable
end

-- get the numerical value associated with name, path 
function nameStats.getValue(name, path, rootNode) -- allocate if not exist
	if not name then return nil end 
	local theLeaf = nameStats.getLeaf(name, path, rootNode)
	return theLeaf.value
end

-- get the log associated with name, path 
function nameStats.getStrings(name, path, rootNode)
	if not name then return nil end 
	local theLeaf = nameStats.getLeaf(name, path, rootNode)
	return theLeaf.strings
end

-- alias for compatibility reasons
function nameStats.getString(name, path, rootNode)
	return nameStats.getStrings(name, path, rootNode)
end

-- get the table stored under name, path.
function nameStats.getTable(name, path, rootNode)
	if not name then return nil end 
	local theLeaf = nameStats.getLeaf(name, path, rootNode)
	return theLeaf.theTable
end

-- reset whatever is stored under name, path
-- WARNING: passing nil path will entirely reset the whole name 
function nameStats.reset(name, path, rootNode)
	if not name then return nil end 
	if not rootNode then rootNode = nameStats.stats end 
	local theEntry = rootNode[name]
	if not theEntry then 
		-- does not yet exist, create a root entry
		theEntry = nameStats.createRoot(name)
		rootNode[name] = theEntry
		nameStats.getLeaf(name, path, rootNode) -- will alloc an empty leaf
		return -- done
	end
	if not path then -- will delete everything!!!
		theEntry = nameStats.createRoot(name)
		rootNode[name] = theEntry
		return  
	end 
	-- create new leaf and replace existing
	theLeaf = nameStats.createLeaf()
	theEntry.data[path] = theLeaf
		
end

--
--
-- private function 
--
--
function nameStats.getLeaf(name, path, rootNode) 
	if not name then return nil end 
	if not rootNode then rootNode = nameStats.stats end 
	-- will allocate if not existlocal theEntry = nameStats.stats[name]
	local theEntry = rootNode[name]
	if not theEntry then 
		-- does not yet exist, create a root entry
		theEntry = nameStats.createRoot(name)
		rootNode[name] = theEntry
	end
	-- from here on, the entry exists 
	if not path then return theEntry.defaultLeaf end 
	
	-- access via path 
	local theLeaf = theEntry.data[path]
	if not theLeaf then 
		theLeaf = nameStats.createLeaf()
		theEntry.data[path] = theLeaf
	end
	return theLeaf
end

function nameStats.createLeaf()
	local theLeaf = {}
	theLeaf.value = 0
	theLeaf.strings = ""
	theLeaf.log = {} -- was strings
	theLeaf.theTable = {}
	return theLeaf
end

-- for each entry in stats, this is the root container
function nameStats.createRoot(name)
	local theRoot = {} -- all nodes are in here
	theRoot.name = name 
	theRoot.data = {} -- dict by path for leafs
	theRoot.defaultLeaf = nameStats.createLeaf()
	return theRoot
end

-- say hi!
trigger.action.outText("cf/x NameStats v" .. nameStats.version .. " loaded", 30)
