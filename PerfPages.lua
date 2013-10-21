
-- PerfPages.lua

-- Implements the performance-pages in the WebAdmin
-- This file is self-enclosed, it doesn't need any other Lua file to function
--   so it can be dropped into other plugins (together with the JS files)




-- Settings: --
---------------
g_Minutes = 5;  -- Number of minutes of history to keep





function ReadJSFiles()
	local FileName = g_Plugin:GetLocalFolder() .. "/jquery.js";
	local f = io.open(FileName, "rb");
	if (f == nil) then
		LOGWARNING("PerfPages: Cannot read file \"" .. FileName .. "\", page will not be available");
		return false;
	end
	g_JS = f:read("*all");
	f:close();
	
	FileName = g_Plugin:GetLocalFolder() .. "/jquery.flot.js";
	f = io.open(FileName, "rb");
	if (f == nil) then
		LOGWARNING("PerfPages: Cannot read file \"" .. FileName .. "\", page will not be available");
		return false;
	end
	g_JS = g_JS .. f:read("*all");
	f:close();
	return true;
end





--- Initializes the given table to contain g_MaxValues zeroes in the array part
function InitializeArrayNum(a_Var, a_Count)
	for i = 1, a_Count do
		a_Var[i] = 0;
	end
end





--- Initializes the given table to contain g_MaxValues empty strings in the array part
function InitializeArrayStr(a_Var, a_Count)
	for i = 1, a_Count do
		a_Var[i] = "";
	end
end





g_CurValue = 0;
g_MaxValues = g_Minutes * 60;
g_RamPhys = {};
g_RamVirt = {};
g_NumChunks = {};
g_CurTick = 0;
g_MaxTicks = g_Minutes * 60 * 20;
g_WorldTick = {};  -- Dictionary of per-world tick durations and the current tick positions
g_Workspace = {};  -- Pre-allocated array used for concats (GetSeries()) to avoid reallocation in each tick

InitializeArrayNum(g_RamPhys, g_MaxValues);
InitializeArrayNum(g_RamVirt, g_MaxValues);
InitializeArrayNum(g_NumChunks, g_MaxValues);
InitializeArrayStr(g_Workspace, 2 * g_MaxTicks);

function HandleHttpRequest(Request)
	local Contents = [[
<style>
.graph
{
	width: 700px;
	height: 300px;
}
</style>

<p>
Memory usage / MiB (left/yellow) and the number of loaded chunks (right/red):
<div id="ramgraph" class="graph"></div>
</p>
<p>
World tick duration (msec):
<div id="tickgraph" class="graph"></div>
</p>

<script language="javascript" type="text/javascript">
]];

	--- Returns the string representing the given series; uses and trashes g_Workspace for optimizing the concats
	local function GetSeries(a_Series, a_CurValue, a_MaxValues)
		local idx = -a_MaxValues;
		local idx2 = 1;
		local Data = g_Workspace;  -- using a global buffer for the concats - don't want to allocate a new table on each call
		local fmt = string.format;
		for i = a_CurValue + 1, a_MaxValues do
			Data[idx2] = fmt("[%d, %d]", idx, a_Series[i]);
			idx2 = idx2 + 1;
			idx = idx + 1;
		end
		for i = 1, a_CurValue - 1 do
			Data[idx2] = fmt("[%d, %d]", idx, a_Series[i]);
			idx2 = idx2 + 1;
			idx = idx + 1;
		end
		return table.concat(Data, ",\n", 1, a_MaxValues - 1);
	end
	
	local Data = "var ramphysdata =\n[\n" .. GetSeries(g_RamPhys, g_CurValue, g_MaxValues);
	Data = Data .. "];\n\n\nvar ramvirtdata =\n[\n" .. GetSeries(g_RamVirt, g_CurValue, g_MaxValues);
	Data = Data .. "];\n\n\nvar chunkdata =\n[\n" .. GetSeries(g_NumChunks, g_CurValue, g_MaxValues);
	
	Data = Data .. "];\n\n\nvar tickseries = [\n";
	for WorldName, WorldData in pairs(g_WorldTick) do
		Data = Data .. "\t{\n\t\tdata:\n\t\t[\n" .. GetSeries(WorldData, WorldData.CurTick, g_MaxTicks) .. "\t\t]\n\t},\n";
	end

	Contents = Contents .. Data .. "];\n\n" .. [[

$.plot(
	$("#ramgraph"),
	[
		{ data: ramphysdata, yaxis: 1},
		{ data: ramvirtdata, yaxis: 1},
		{ data: chunkdata, yaxis: 2 },
	],
	{
		lines: { show: true},
		yaxes: [
			{min: 0, },
			{min: 0, position: "right"},
		]
	}
);

$.plot(
	$("#tickgraph"),
	tickseries,
	{
		lines: { show: true},
	}
);

// Reload each 5 seconds:
setTimeout("location.reload(true)", 5000);
</script>
]];

	return "<script language=\"javascript\" type=\"text/javascript\">\n" .. g_JS .. "\n</script>\n" .. Contents;
end





g_CurrentServerTickNum = 0;

function OnServerTick(a_Dt)
	if (g_CurrentServerTickNum < 20) then
		-- Only measure the RAM once every 20 ticks (1 second)
		g_CurrentServerTickNum = g_CurrentServerTickNum + 1;
		return;
	end
	g_CurrentServerTickNum = 1;
	g_RamPhys[g_CurValue] = cRoot:GetPhysicalRAMUsage() / 1024;  -- KiB -> MiB
	g_RamVirt[g_CurValue] = cRoot:GetVirtualRAMUsage()  / 1024;  -- KiB -> MiB
	
	-- Rather than querying cRoot for the total number of chunks (which could deadlock),
	-- use the values that have been cached in OnWorldTick()
	local NumChunks = 0;
	for WorldName, WorldData in pairs(g_WorldTick) do
		NumChunks = NumChunks + WorldData.NumChunks;
	end
	g_NumChunks[g_CurValue] = NumChunks;
	
	g_CurValue = g_CurValue + 1;
	if (g_CurValue > g_MaxValues) then
		g_CurValue = 1;
	end
end





function OnWorldTick(a_World, a_Dt)
	local WorldTick = g_WorldTick[a_World:GetName()];
	if (WorldTick == nil) then
		-- The world data doesn't exist yet, create anew, initialize to all zeroes:
		WorldTick = {};
		InitializeArrayNum(WorldTick, g_MaxTicks);
		g_WorldTick[a_World:GetName()] = WorldTick;
		WorldTick.CurTick = 1;
	end
	WorldTick[WorldTick.CurTick] = a_Dt;
	WorldTick.NumChunks = a_World:GetNumChunks();
	WorldTick.CurTick = WorldTick.CurTick + 1;
	if (WorldTick.CurTick > g_MaxTicks) then
		WorldTick.CurTick = 1;
	end
end





-- Globals - will be executed as soon as the plugin is loaded.
-- This trick should allow us to use an empty Initialize function, and thus make this
-- plugin combinable with other plugins.
if (ReadJSFiles()) then
	g_Plugin:AddWebTab("Performance graphs", HandleHttpRequest);
	cPluginManager.AddHook(cPluginManager.HOOK_TICK, OnServerTick);
	cPluginManager.AddHook(cPluginManager.HOOK_WORLD_TICK, OnWorldTick);
end




