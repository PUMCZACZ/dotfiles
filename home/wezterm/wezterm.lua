-- Adapted from kunchenguid/dotfiles@7505ed63a26272dfa682b19d45e6384f8ffea004.
local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("JetBrainsMono Nerd Font")
config.font_size = 15.0
config.window_background_opacity = 0.8
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"
config.mouse_bindings = {
	{ mods = "CTRL", event = { Down = { streak = 1, button = "Left" } }, action = wezterm.action.OpenLinkAtMouseCursor },
	{ mods = "CTRL|SHIFT", event = { Down = { streak = 1, button = "Left" } }, action = wezterm.action.OpenLinkAtMouseCursor },
}

-- Dim unfocused windows so the focused one is obvious at a glance.
local UNFOCUSED_FOREGROUND_TEXT_HSB = { hue = 1.0, saturation = 0.25, brightness = 0.45 }
local UNFOCUSED_WINDOW_BACKGROUND_OPACITY = 0.62

-- get_config_overrides() hands back a copy, so the current value is never the
-- same table we last stored; compare the fields instead of the identity.
local function same_text_hsb(actual, expected)
	if actual == nil or expected == nil then
		return actual == expected
	end
	return actual.hue == expected.hue
		and actual.saturation == expected.saturation
		and actual.brightness == expected.brightness
end

local function herdr_cwd(executable)
	if not executable:match("^/") then return nil, "Could not locate Herdr; use an absolute file link." end
	local ok, output = wezterm.run_child_process({ executable, "api", "snapshot" })
	if not ok then return nil, "Could not read Herdr layout; use an absolute file link." end
	local decoded, response = pcall(wezterm.json_parse, output)
	local snapshot = decoded and response.result and response.result.snapshot
	if not snapshot then return nil, "Could not identify Herdr session; use an absolute link." end

	local layout
	for _, item in ipairs(snapshot.layouts or {}) do
		if item.workspace_id == snapshot.focused_workspace_id and item.tab_id == snapshot.focused_tab_id then layout = item; break end
	end
	if not layout then return nil, "Could not identify the Herdr layout; use an absolute link." end

	local cwd
	if layout.zoomed then
		for _, item in ipairs(snapshot.panes or {}) do
			if item.pane_id == layout.focused_pane_id then cwd = item.cwd; break end
		end
	else
		local found = 0
		for _, visible in ipairs(layout.panes or {}) do
			for _, item in ipairs(snapshot.panes or {}) do
				if item.pane_id == visible.pane_id then
					if type(item.cwd) ~= "string" or item.cwd:sub(1, 1) ~= "/" then return nil, "Could not determine every Herdr pane folder; zoom a pane or use an absolute link." end
					if cwd and cwd ~= item.cwd then return nil, "Herdr panes have different folders; zoom a pane or use an absolute file link." end
					cwd, found = item.cwd, found + 1
				end
			end
		end
		if found ~= #(layout.panes or {}) then return nil, "Could not identify every Herdr pane; zoom a pane or use an absolute link." end
	end
	if type(cwd) ~= "string" or cwd:sub(1, 1) ~= "/" then return nil, "Could not determine Herdr project folder; use an absolute link." end
	return cwd
end

local function resolve_file(uri, herdr_env, pane_cwd, herdr_executable)
	if not uri:match("^file:") and (uri:match("^[%a][%w+.-]*:") or uri:match("^//")) then return nil, "not-local" end

	local cwd, err
	if not uri:match("^file:") and uri:sub(1, 1) ~= "/" then
		if herdr_env then
			cwd, err = herdr_cwd(herdr_executable)
		else
			cwd = pane_cwd
		end
		if not cwd then return nil, err or "Could not determine this pane's folder; use an absolute file link." end
	end

	if uri:match("^file:") then
		local ok, parsed = pcall(wezterm.url.parse, uri)
		if not ok or not parsed or parsed.scheme ~= "file" or (parsed.host and parsed.host ~= "" and parsed.host ~= "localhost") then return nil, "invalid" end
		local path = parsed.file_path
		if type(path) ~= "string" or path == "" or path:find("%z") then return nil, "invalid" end
		return path
	end
	if uri:sub(1, 1) == "/" then
		if uri:find("%z") then return nil, "invalid" end
		return uri
	end

	local ok, parsed = pcall(wezterm.url.parse, "file://" .. cwd .. "/" .. uri)
	if not ok or not parsed or parsed.host then return nil, "invalid" end
	local path = parsed.file_path
	if type(path) ~= "string" or path == "" or path:find("%z") then return nil, "invalid" end
	return path
end

local function notify(window, message)
	window:toast_notification("Pi file links", message, nil, 5000)
end

local function dotnet_project(path)
	local extension = path:match("%.([^./]+)$")
	if extension and ({ cs = true, fs = true, vb = true })[extension:lower()] then return true end

	local dir = path:match("^(.*)/") or "."
	while dir ~= "" do
		for _, pattern in ipairs({ "*.sln", "*.slnx", "*.csproj", "*.fsproj" }) do
			if next(wezterm.glob(dir .. "/" .. pattern) or {}) then return true end
		end
		local parent = dir:match("^(.*)/[^/]+$")
		if not parent or parent == dir then break end
		dir = parent
	end
	return false
end

local function open_local_file(window, pane, uri)
	if not uri:match("^file:") and (uri:match("^[%a][%w+.-]*:") or uri:match("^//")) then return nil end

	local pane_url = pane:get_current_working_dir()
	local foreground = pane:get_foreground_process_name() or ""
	local herdr_executable = foreground:lower():match("herdr") and foreground
	local path, err = resolve_file(uri, herdr_executable ~= nil, pane_url and pane_url.file_path, herdr_executable)
	if path == nil then
		if err == "not-local" then return nil end
		notify(window, err or "Unsupported local file link.")
		return false
	end

	local exists = wezterm.run_child_process({ "/bin/test", "-f", path })
	if not exists then
		notify(window, "File does not exist: " .. path)
		return false
	end

	local ide = dotnet_project(path) and "Rider" or "PhpStorm"
	local ok = wezterm.run_child_process({ "/usr/bin/open", "-a", ide, path })
	if not ok then notify(window, "Could not open " .. path .. " in " .. ide .. ".") end
	return false
end

wezterm.on("open-uri", function(window, pane, uri)
	return open_local_file(window, pane, uri)
end)

wezterm.on("window-focus-changed", function(window)
	local overrides = window:get_config_overrides() or {}
	local text_hsb, opacity
	if not window:is_focused() then
		text_hsb = UNFOCUSED_FOREGROUND_TEXT_HSB
		opacity = UNFOCUSED_WINDOW_BACKGROUND_OPACITY
	end

	-- Only write when one of the two values we own actually changes; a redundant
	-- set_config_overrides() call would trigger another config reload.
	if same_text_hsb(overrides.foreground_text_hsb, text_hsb) and overrides.window_background_opacity == opacity then
		return
	end

	overrides.foreground_text_hsb = text_hsb
	overrides.window_background_opacity = opacity
	window:set_config_overrides(overrides)
end)

return config
