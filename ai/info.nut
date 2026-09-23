/*
 * This file is part of JevTTD.
 *
 * JevTTD is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * JevTTD is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 */

/** @file info.nut AIInfo registration for JevTTD. */

class JevTTDInfo extends AIInfo {
	function GetAuthor()        { return "adhikasp"; }
	function GetName()          { return "JevTTD"; }
	function GetShortName()     { return "JEVT"; }
	function GetDescription()   { return "Plays for the story, not the spreadsheet: picks among good options by how fun they are, not just which one scores highest."; }
	function GetVersion()       { return 1; }
	function MinVersionToLoad() { return 1; }
	function GetDate()          { return "2026-09-23"; }
	function CreateInstance()   { return "JevTTD"; }
	function GetAPIVersion()    { return "16"; }

	function GetSettings() {
		AddSetting({name = "use_busses", description = "Enable busses", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = CONFIG_BOOLEAN});
		AddSetting({name = "use_trucks", description = "Enable trucks", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = CONFIG_BOOLEAN});
		AddSetting({name = "use_trains", description = "Enable trains", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = CONFIG_BOOLEAN});
		AddSetting({name = "use_planes", description = "Enable aircraft", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = CONFIG_BOOLEAN});
		AddSetting({name = "showmanship", description = "How much to favor spectacle over efficiency (0 = play it safe, 100 = maximum drama)", easy_value = 60, medium_value = 50, hard_value = 40, custom_value = 50, min_value = 0, max_value = 100, step_size = 10, flags = CONFIG_INGAME});
		AddSetting({name = "use_remote_brain", description = "[experimental] Delegate some decisions to an external typed-decision service. Requires a patched client with the ScriptHTTP API; silently ignored on vanilla OpenTTD or in networked games.", easy_value = 0, medium_value = 0, hard_value = 0, custom_value = 0, flags = CONFIG_BOOLEAN});
	}
};

RegisterAI(JevTTDInfo());
