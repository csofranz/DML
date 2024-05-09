wingTaskHelper = {}

-- WP 1 Task for a CAS flight
wingTaskHelper.casTOTask = {
	["id"] = "ComboTask",
	["params"] = 
	{
		["tasks"] = 
		{
			[1] = 
			{
				["enabled"] = true,
				["auto"] = true,
				["id"] = "EngageTargets",
				["number"] = 1,
				["key"] = "CAS",
				["params"] = 
				{
					["targetTypes"] = 
					{
						[1] = "Helicopters",
						[2] = "Ground Units",
						[3] = "Light armed ships",
					}, -- end of ["targetTypes"]
					["priority"] = 0,
				}, -- end of ["params"]
			}, -- end of [1]
			[2] = 
			{
				["number"] = 2,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = 2,
							["name"] = 1,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [2]
			[3] = 
			{
				["number"] = 3,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = 1,
							["name"] = 3,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [3]
			[4] = 
			{
				["number"] = 4,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["variantIndex"] = 2,
							["name"] = 5,
							["formationIndex"] = 2,
							["value"] = 131074, -- trail formation 
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [4]
			[5] = 
			{
				["number"] = 5,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = true,
							["name"] = 15,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [5]
			[6] = 
			{
				["number"] = 6,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["targetTypes"] = 
							{
							}, -- end of ["targetTypes"]
							["name"] = 21,
							["value"] = "none;",
							["noTargetTypes"] = 
							{
								[1] = "Fighters",
								[2] = "Multirole fighters",
								[3] = "Bombers",
								[4] = "Helicopters",
								[5] = "Infantry",
								[6] = "Fortifications",
								[7] = "Tanks",
								[8] = "IFV",
								[9] = "APC",
								[10] = "Artillery",
								[11] = "Unarmed vehicles",
								[12] = "AAA",
								[13] = "SR SAM",
								[14] = "MR SAM",
								[15] = "LR SAM",
								[16] = "Aircraft Carriers",
								[17] = "Cruisers",
								[18] = "Destroyers",
								[19] = "Frigates",
								[20] = "Corvettes",
								[21] = "Light armed ships",
								[22] = "Unarmed ships",
								[23] = "Submarines",
								[24] = "Cruise missiles",
								[25] = "Antiship Missiles",
								[26] = "AA Missiles",
								[27] = "AG Missiles",
								[28] = "SA Missiles",
								[29] = "UAVs",
							}, -- end of ["noTargetTypes"]
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [6]
			[7] = 
			{
				["number"] = 7,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = true,
							["name"] = 19,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [7]
			[8] = 
			{
				["number"] = 8,
				["auto"] = false,
				["id"] = "EngageTargetsInZone",
				["enabled"] = true,
				["params"] = 
				{
					["targetTypes"] = 
					{
						[1] = "All",
					}, -- end of ["targetTypes"]
					["x"] = 19632.860434462,
					["y"] = 323453.87978006,
					["value"] = "All;",
					["noTargetTypes"] = 
					{
					}, -- end of ["noTargetTypes"]
					["priority"] = 0,
					["zoneRadius"] = 76200,
				}, -- end of ["params"]
			}, -- end of [8]
		}, -- end of ["tasks"]
	}, -- end of ["params"]
} -- end of ["task"]

wingTaskHelper.capTOTask = {
	["id"] = "ComboTask",
	["params"] = 
	{
		["tasks"] = 
		{
			[1] = 
			{
				["number"] = 1,
				["key"] = "CAP",
				["id"] = "EngageTargets",
				["enabled"] = true,
				["auto"] = true,
				["params"] = 
				{
					["targetTypes"] = 
					{
						[1] = "Air",
					}, -- end of ["targetTypes"]
					["priority"] = 0,
				}, -- end of ["params"]
			}, -- end of [1]
			[2] = 
			{
				["number"] = 2,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = true,
							["name"] = 17, -- restrict ground attack 
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [2]
			[3] = 
			{
				["number"] = 3,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = 0,
							["name"] = 18, -- max range launch 
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [3]
			[4] = 
			{
				["number"] = 4,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = true,
							["name"] = 19, -- no reporting 
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [4]
			[5] = 
			{
				["number"] = 5,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["targetTypes"] = 
							{
							}, -- end of ["targetTypes"]
							["name"] = 21,
							["value"] = "none;",
							["noTargetTypes"] = 
							{
								[1] = "Fighters",
								[2] = "Multirole fighters",
								[3] = "Bombers",
								[4] = "Helicopters",
								[5] = "Infantry",
								[6] = "Fortifications",
								[7] = "Tanks",
								[8] = "IFV",
								[9] = "APC",
								[10] = "Artillery",
								[11] = "Unarmed vehicles",
								[12] = "AAA",
								[13] = "SR SAM",
								[14] = "MR SAM",
								[15] = "LR SAM",
								[16] = "Aircraft Carriers",
								[17] = "Cruisers",
								[18] = "Destroyers",
								[19] = "Frigates",
								[20] = "Corvettes",
								[21] = "Light armed ships",
								[22] = "Unarmed ships",
								[23] = "Submarines",
								[24] = "Cruise missiles",
								[25] = "Antiship Missiles",
								[26] = "AA Missiles",
								[27] = "AG Missiles",
								[28] = "SA Missiles",
								[29] = "UAVs",
							}, -- end of ["noTargetTypes"]
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [5]
			[6] = 
			{
				["number"] = 6,
				["auto"] = false,
				["id"] = "EngageTargetsInZone",
				["enabled"] = true,
				["params"] = 
				{
					["targetTypes"] = 
					{
						[1] = "Planes",
					}, -- end of ["targetTypes"]
					["x"] = -1421.6419952991,
					["y"] = 311601.25461373,
					["value"] = "Planes;",
					["noTargetTypes"] = 
					{
					}, -- end of ["noTargetTypes"]
					["priority"] = 0,
					["zoneRadius"] = 76200,
				}, -- end of ["params"]
			}, -- end of [6]
		}, -- end of ["tasks"]
	}, -- end of ["params"]
} -- end of ["task"]

wingTaskHelper.seadTOTask = {
	["id"] = "ComboTask",
	["params"] = 
	{
		["tasks"] = 
		{
			[1] = 
			{
				["number"] = 1,
				["key"] = "SEAD",
				["id"] = "EngageTargets",
				["enabled"] = true,
				["auto"] = true,
				["params"] = 
				{
					["targetTypes"] = 
					{
						[1] = "Air Defence",
					}, -- end of ["targetTypes"]
					["priority"] = 0,
				}, -- end of ["params"]
			}, -- end of [1]
			[2] = 
			{
				["number"] = 2,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = 2,
							["name"] = 1,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [2]
			[3] = 
			{
				["number"] = 3,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = 2,
							["name"] = 13,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [3]
			[4] = 
			{
				["number"] = 4,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = true,
							["name"] = 19,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [4]
			[5] = 
			{
				["number"] = 5,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["targetTypes"] = 
							{
								[1] = "Air Defence",
							}, -- end of ["targetTypes"]
							["name"] = 21,
							["value"] = "Air Defence;",
							["noTargetTypes"] = 
							{
								[1] = "Fighters",
								[2] = "Multirole fighters",
								[3] = "Bombers",
								[4] = "Helicopters",
								[5] = "Infantry",
								[6] = "Fortifications",
								[7] = "Tanks",
								[8] = "IFV",
								[9] = "APC",
								[10] = "Artillery",
								[11] = "Unarmed vehicles",
								[12] = "Aircraft Carriers",
								[13] = "Cruisers",
								[14] = "Destroyers",
								[15] = "Frigates",
								[16] = "Corvettes",
								[17] = "Light armed ships",
								[18] = "Unarmed ships",
								[19] = "Submarines",
								[20] = "Cruise missiles",
								[21] = "Antiship Missiles",
								[22] = "AA Missiles",
								[23] = "AG Missiles",
								[24] = "SA Missiles",
								[25] = "UAVs",
							}, -- end of ["noTargetTypes"]
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [5]
			[6] = 
			{
				["number"] = 6,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "EPLRS",
						["params"] = 
						{
							["value"] = true,
							["groupId"] = 2,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [6]
			[7] = 
			{
				["number"] = 7,
				["auto"] = false,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = true,
							["name"] = 15,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [7]
		}, -- end of ["tasks"]
	}, -- end of ["params"]
} -- end of ["task"]

wingTaskHelper.bombTOTask = {
	["id"] = "ComboTask",
	["params"] = 
	{
		["tasks"] = 
		{
			[1] = 
			{
				["number"] = 1,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = 2,
							["name"] = 1,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [1]
			[2] = 
			{
				["number"] = 2,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "Option",
						["params"] = 
						{
							["value"] = true,
							["name"] = 15,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [2]
			[3] = 
			{
				["number"] = 3,
				["auto"] = true,
				["id"] = "WrappedAction",
				["enabled"] = true,
				["params"] = 
				{
					["action"] = 
					{
						["id"] = "EPLRS",
						["params"] = 
						{
							["value"] = true,
							["groupId"] = 3,
						}, -- end of ["params"]
					}, -- end of ["action"]
				}, -- end of ["params"]
			}, -- end of [3]
		}, -- end of ["tasks"]
	}, -- end of ["params"]
} -- end of ["task"]

wingTaskHelper.bombActionTask = {
	["id"] = "ComboTask",
	["params"] = 
	{
		["tasks"] = 
		{
			[1] = 
			{
				["number"] = 1,
				["auto"] = false,
				["id"] = "CarpetBombing",
				["enabled"] = true,
				["params"] = 
				{
					["attackType"] = "Carpet",
					["attackQtyLimit"] = false,
					["attackQty"] = 1,
					["expend"] = "All", -- yay!
					["altitude"] = 7620,
					["x"] = -7222.3894291577,
					["carpetLength"] = 500,
					["y"] = 294267.9527197,
					["altitudeEnabled"] = false,
					["weaponType"] = 9663676414,
					["groupAttack"] = false,
				}, -- end of ["params"]
			}, -- end of [1]
		}, -- end of ["tasks"]
	}, -- end of ["params"]
} -- end of ["task"]