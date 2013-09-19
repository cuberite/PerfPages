
-- main.lua

-- Contains the main plugin entrypoint, the Initialize() function





function Initialize(a_Plugin)
	-- Funny thing is, we don't need this function at all.
	-- Everything is done in the PerfPages.lua file, including automatic registration
	
	-- This allows this plugin to be integrated within another plugin, just by copying
	-- over the PerfPages.lua file and the JS files.
	
	return true;
end




