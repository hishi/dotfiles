local wezterm = require("wezterm")
local mux = wezterm.mux

local M = {}

local state_dir = wezterm.home_dir .. "/.local/state/wezterm"
local state_file = state_dir .. "/session.json"

local function cwd_to_path(cwd)
	if not cwd then
		return nil
	end
	if type(cwd) == "string" then
		return cwd:gsub("^file://[^/]*", "")
	end
	return cwd.file_path
end

local function active_pane_of(tab)
	for _, info in ipairs(tab:panes_with_info()) do
		if info.is_active then
			return info.pane
		end
	end
	return tab:panes()[1]
end

function M.save_state()
	local workspaces = {}

	for _, window in ipairs(mux.all_windows()) do
		local ws_name = window:get_workspace()
		workspaces[ws_name] = workspaces[ws_name] or { windows = {} }

		local tabs = {}
		for _, tab in ipairs(window:tabs()) do
			local pane = active_pane_of(tab)
			table.insert(tabs, { cwd = cwd_to_path(pane:get_current_working_dir()) })
		end
		table.insert(workspaces[ws_name].windows, { tabs = tabs })
	end

	os.execute("mkdir -p " .. state_dir)
	local f = io.open(state_file, "w")
	if not f then
		return
	end
	f:write(wezterm.json_encode({
		active_workspace = mux.get_active_workspace(),
		workspaces = workspaces,
	}))
	f:close()
end

local function load_state()
	local f = io.open(state_file, "r")
	if not f then
		return nil
	end
	local contents = f:read("*a")
	f:close()

	local ok, data = pcall(wezterm.json_parse, contents)
	if not ok then
		return nil
	end
	return data
end

wezterm.on("gui-startup", function(cmd)
	if cmd and cmd.args then
		return
	end

	local data = load_state()
	if not data or not data.workspaces then
		return
	end

	for ws_name, ws_data in pairs(data.workspaces) do
		for _, win_data in ipairs(ws_data.windows) do
			local first_tab = win_data.tabs[1]
			local _, _, window = mux.spawn_window({
				workspace = ws_name,
				cwd = first_tab and first_tab.cwd or nil,
			})
			for i = 2, #win_data.tabs do
				window:spawn_tab({ cwd = win_data.tabs[i].cwd })
			end
		end
	end

	if data.active_workspace then
		mux.set_active_workspace(data.active_workspace)
	end
end)

return M
