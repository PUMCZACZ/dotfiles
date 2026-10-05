local events, launched, notices = {}, {}, {}
local fail_launch = false
local fail_snapshot = false
local snapshot = {
	focused_workspace_id = "w", focused_tab_id = "t",
	panes = {
		{ pane_id = "p1", workspace_id = "w", tab_id = "t", cwd = "/project" },
		{ pane_id = "p2", workspace_id = "w", tab_id = "t", cwd = "/project" },
	},
	layouts = { { workspace_id = "w", tab_id = "t", focused_pane_id = "p1", panes = { { pane_id = "p1" }, { pane_id = "p2" } } } },
}
local wezterm = {
	config_builder = function() return {} end,
	font = function(name) return name end,
	action = { OpenLinkAtMouseCursor = {} },
	on = function(name, callback) events[name] = callback end,
	json_parse = function() return { result = { snapshot = snapshot } } end,
	url = { parse = function(uri)
		local host, path = uri:match("^file://([^/]*)(/.*)$")
		assert(path, "invalid file URI")
		path = path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
		local parts = {}
		for part in path:gmatch("[^/]+") do
			if part == ".." then table.remove(parts) elseif part ~= "." then parts[#parts + 1] = part end
		end
		return { scheme = "file", host = host ~= "" and host or nil, file_path = "/" .. table.concat(parts, "/") }
	end },
	glob = function(path)
		if path == "/project/dotnet/*.sln" then return { "/project/dotnet/App.sln" } end
		if path:find("*.sln", 1, true) or path:find("*.slnx", 1, true) or path:find("*.csproj", 1, true) or path:find("*.fsproj", 1, true) then return {} end
		return {}
	end,
	run_child_process = function(args)
		if args[1] == "/nix/store/herdr/bin/herdr" then return not fail_snapshot, "snapshot", "failed" end
		if args[1] == "/bin/test" then return args[3] ~= "/missing file.md", "", "" end
		if fail_launch and args[1] == "/usr/bin/open" then return false, "", "launch failed" end
		launched[#launched + 1] = args
		return true, "", ""
	end,
}
package.preload.wezterm = function() return wezterm end
local config = dofile("home/wezterm/wezterm.lua")
local binding = config.mouse_bindings[1]
assert(binding.mods == "CTRL" and config.mouse_bindings[2].mods == "CTRL|SHIFT" and binding.mouse_reporting == nil)
assert(next(binding.event) == "Down" and next(config.mouse_bindings[2].event) == "Down")
local callback = assert(events["open-uri"])
local window = { toast_notification = function(_, _, message) notices[#notices + 1] = message end }
local pane = {
	get_foreground_process_name = function() return "/nix/store/herdr/bin/herdr" end,
	get_current_working_dir = function() return { file_path = "/wrong/outer/cwd" } end,
}

assert(callback(window, pane, "https://example.test/a") == nil and #launched == 0)
local before_notices = #notices
assert(callback(window, pane, "file://remotehost/tmp/a.md") == false and #launched == 0 and #notices == before_notices + 1)
assert(callback(window, pane, "core/docs/tasks/contacts/spec.md") == false)
assert(launched[#launched][1] == "/usr/bin/open" and launched[#launched][3] == "PhpStorm")
assert(launched[#launched][4] == "/project/core/docs/tasks/contacts/spec.md")
assert(callback(window, pane, "file:///project/folder%20name/spec.md") == false)
assert(launched[#launched][4] == "/project/folder name/spec.md")
assert(callback(window, pane, "folder%20name/spec.md") == false)
assert(launched[#launched][4] == "/project/folder name/spec.md")
assert(callback(window, pane, "/project/Sample.cs") == false)
assert(launched[#launched][3] == "Rider")
assert(callback(window, pane, "/project/dotnet/README.md") == false)
assert(launched[#launched][3] == "Rider")
before_notices = #notices
local before_launches = #launched
assert(callback(window, pane, "file:///missing%20file.md") == false and #notices == before_notices + 1 and #launched == before_launches)
assert(callback(window, pane, "/project/[odd].md") == false)
assert(launched[#launched][4] == "/project/[odd].md")
assert(callback(window, pane, "/project/percent%name.md") == false)
assert(launched[#launched][4] == "/project/percent%name.md")
before_notices, before_launches = #notices, #launched
assert(callback(window, pane, "file:///project/bad%00name.md") == false and #notices == before_notices + 1 and #launched == before_launches)
fail_launch = true
before_notices, before_launches = #notices, #launched
assert(callback(window, pane, "/project/LaunchFail.cs") == false and #notices == before_notices + 1 and #launched == before_launches)
fail_launch = false

fail_snapshot = true
before_launches = #launched
assert(callback(window, pane, "file:///project/absolute.md") == false and #launched == before_launches + 1)
assert(launched[#launched][4] == "/project/absolute.md")
before_notices, before_launches = #notices, #launched
assert(callback(window, pane, "relative.md") == false and #notices == before_notices + 1 and #launched == before_launches)
fail_snapshot = false
snapshot.panes[2].cwd = "/other-project"
before_notices, before_launches = #notices, #launched
assert(callback(window, pane, "relative.md") == false and #notices == before_notices + 1 and #launched == before_launches)
snapshot.panes[2].cwd = nil
before_notices = #notices
assert(callback(window, pane, "relative.md") == false and #notices == before_notices + 1)
snapshot.layouts[1].zoomed = true
snapshot.panes[2].cwd = "/other-project"
assert(callback(window, pane, "core/docs/tasks/contacts/spec.md") == false)
assert(launched[#launched][4] == "/project/core/docs/tasks/contacts/spec.md")

snapshot.panes[1].cwd, snapshot.panes[2].cwd = "/project/dir", "/project/dir"
assert(callback(window, pane, "./a.md") == false)
assert(launched[#launched][4] == "/project/dir/a.md")
assert(callback(window, pane, "../README.md") == false)
assert(launched[#launched][4] == "/project/README.md")
pane.get_foreground_process_name = function() return "/bin/zsh" end
assert(callback(window, pane, "relative/path.md") == false)
assert(launched[#launched][4] == "/wrong/outer/cwd/relative/path.md")
print("PASS WezTerm local-link resolver fixture")
