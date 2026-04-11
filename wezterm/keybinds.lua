local wezterm = require("wezterm")
local act = wezterm.action

-- Show which key table is active in the status area
wezterm.on("update-right-status", function(window, pane)
	local name = window:active_key_table()
	if name then
		name = "TABLE: " .. name
	end
	window:set_right_status(name or "")
end)

return {
	keys = {
    ---------------------------------------------------------------------------------------------
    -- LEADER
    ---------------------------------------------------------------------------------------------
		-- workspaceの切り替え
		{ mods = "LEADER", key = "w", action = act.ShowLauncherArgs({ flags = "WORKSPACES", title = "Select workspace" }), },
		--workspaceの名前変更
    { mods = "LEADER", key = "$", action = act.PromptInputLine({ description = "(wezterm) Set workspace title:", action = wezterm.action_callback(function(win, pane, line) if line then wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line) end end), }), },
		{ mods = "LEADER|SHIFT", key = "W", action = act.PromptInputLine({ description = "(wezterm) Create new workspace:", action = wezterm.action_callback(function(window, pane, line) if line then window:perform_action( act.SwitchToWorkspace({ name = line, }), pane) end end), }), },
		-- Tab入れ替え
		{ mods = "LEADER", key = "{", action = act({ MoveTabRelative = -1 }) },
		{ mods = "LEADER", key = "}", action = act({ MoveTabRelative = 1 }) },

		-- コピーモード
		{ mods = "LEADER", key = "[",  action = act.ActivateCopyMode },

		-- Pane作成 leader + r or d
		{ mods = "LEADER", key = "d", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
		{ mods = "LEADER", key = "r", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
		-- Paneを閉じる leader + x
		{ mods = "LEADER", key = "x", action = act({ CloseCurrentPane = { confirm = true } }) },
		-- Pane移動 leader + hlkj
		{ mods = "LEADER", key = "h", action = act.ActivatePaneDirection("Left") },
		{ mods = "LEADER", key = "l", action = act.ActivatePaneDirection("Right") },
		{ mods = "LEADER", key = "k", action = act.ActivatePaneDirection("Up") },
		{ mods = "LEADER", key = "j", action = act.ActivatePaneDirection("Down") },
		-- 選択中のPaneのみ表示
		{ mods = "LEADER", key = "z", action = act.TogglePaneZoomState },
		-- キーテーブル用
		{ mods = "LEADER", key = "s", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
		{ mods = "LEADER", key = "a", action = act.ActivateKeyTable({ name = "activate_pane", timeout_milliseconds = 1000 }), },

    ---------------------------------------------------------------------------------------------
    -- SUPER
    ---------------------------------------------------------------------------------------------
		-- コマンドパレット表示
		{ mods = "SUPER", key = "p", action = act.ActivateCommandPalette },
		-- Tab新規作成
		{ mods = "SUPER", key = "t", action = act({ SpawnTab = "CurrentPaneDomain" }) },
		-- Tabを閉じる
		{ mods = "SUPER", key = "w", action = act({ CloseCurrentTab = { confirm = true } }) },
		-- コピー
		{ mods = "SUPER", key = "c", action = act.CopyTo("Clipboard") },
		-- 貼り付け
		{ mods = "SUPER", key = "v", action = act.PasteFrom("Clipboard") },

		{ mods = "SUPER", key = "n", action = act.SpawnCommandInNewTab { cwd = wezterm.home_dir .. "/Dev" },},

		{ mods = "SUPER", key = "q", action = act.QuitApplication },

		{ mods = "SUPER", key = "j", action = act.ShowLauncherArgs { flags = 'TABS' } },
		-- タブ切替 Cmd + 数字
		{ mods = "SUPER", key = "h", action = act.ActivateTabRelative(-1) },
		{ mods = "SUPER", key = "l", action = act.ActivateTabRelative(1) },
		{ mods = "SUPER", key = "1", action = act.ActivateTab(0) },
		{ mods = "SUPER", key = "2", action = act.ActivateTab(1) },
		{ mods = "SUPER", key = "3", action = act.ActivateTab(2) },
		{ mods = "SUPER", key = "4", action = act.ActivateTab(3) },
		{ mods = "SUPER", key = "5", action = act.ActivateTab(4) },
		{ mods = "SUPER", key = "6", action = act.ActivateTab(5) },
		{ mods = "SUPER", key = "7", action = act.ActivateTab(6) },
		{ mods = "SUPER", key = "8", action = act.ActivateTab(7) },
		{ mods = "SUPER", key = "9", action = act.ActivateTab(-1) },


    ---------------------------------------------------------------------------------------------
    -- CTRL
    ---------------------------------------------------------------------------------------------
		-- Tab移動
		{ mods = "CTRL", key = "Tab", action = act.ActivateTabRelative(1) },
		{ mods = "CTRL|SHIFT", key = "Tab", action = act.ActivateTabRelative(-1) },
		-- Pane選択
		{ mods = "CTRL|SHIFT", key = "[", action = act.PaneSelect },
		-- フォントサイズ切替
		{ mods = "CTRL", key = "+", action = act.IncreaseFontSize },
		{ mods = "CTRL", key = "-", action = act.DecreaseFontSize },
		-- フォントサイズのリセット
		{ mods = "CTRL", key = "0", action = act.ResetFontSize },
		-- コマンドパレット
		{ mods = "CTRL|SHIFT", key = "p", action = act.ActivateCommandPalette },
		-- 設定再読み込み
		{ mods = "CTRL|SHIFT", key = "r", action = act.ReloadConfiguration },

    ---------------------------------------------------------------------------------------------
    -- ALT
    ---------------------------------------------------------------------------------------------

    ---------------------------------------------------------------------------------------------
    -- NONE
    ---------------------------------------------------------------------------------------------
	},
	-- キーテーブル
	-- https://wezfurlong.org/wezterm/config/key-tables.html
	key_tables = {
		-- Paneサイズ調整 leader + s
		resize_pane = {
			{ key = "h", action = act.AdjustPaneSize({ "Left", 1 }) },
			{ key = "l", action = act.AdjustPaneSize({ "Right", 1 }) },
			{ key = "k", action = act.AdjustPaneSize({ "Up", 1 }) },
			{ key = "j", action = act.AdjustPaneSize({ "Down", 1 }) },

			-- Cancel the mode by pressing escape
			{ key = "Enter", action = "PopKeyTable" },
		},
		activate_pane = {
			{ key = "h", action = act.ActivatePaneDirection("Left") },
			{ key = "l", action = act.ActivatePaneDirection("Right") },
			{ key = "k", action = act.ActivatePaneDirection("Up") },
			{ key = "j", action = act.ActivatePaneDirection("Down") },
		},
		-- copyモード leader + [
		copy_mode = {
			-- 移動
			{ mods = "NONE", key = "h", action = act.CopyMode("MoveLeft") },
			{ mods = "NONE", key = "j", action = act.CopyMode("MoveDown") },
			{ mods = "NONE", key = "k", action = act.CopyMode("MoveUp") },
			{ mods = "NONE", key = "l", action = act.CopyMode("MoveRight") },
			-- 最初と最後に移動
			{ mods = "NONE", key = "^", action = act.CopyMode("MoveToStartOfLineContent") },
			{ mods = "NONE", key = "$", action = act.CopyMode("MoveToEndOfLineContent") },
			-- 左端に移動
			{ mods = "NONE", key = "0", action = act.CopyMode("MoveToStartOfLine") },
			{ mods = "NONE", key = "o", action = act.CopyMode("MoveToSelectionOtherEnd") },
			{ mods = "NONE", key = "O", action = act.CopyMode("MoveToSelectionOtherEndHoriz") },
			--
			{ mods = "NONE", key = ";", action = act.CopyMode("JumpAgain") },
			-- 単語ごと移動
			{ mods = "NONE", key = "w", action = act.CopyMode("MoveForwardWord") },
			{ mods = "NONE", key = "b", action = act.CopyMode("MoveBackwardWord") },
			{ mods = "NONE", key = "e", action = act.CopyMode("MoveForwardWordEnd") },
			-- ジャンプ機能 t f
			{ mods = "NONE", key = "t", action = act.CopyMode({ JumpForward = { prev_char = true } }) },
			{ mods = "NONE", key = "f", action = act.CopyMode({ JumpForward = { prev_char = false } }) },
			{ mods = "NONE", key = "T", action = act.CopyMode({ JumpBackward = { prev_char = true } }) },
			{ mods = "NONE", key = "F", action = act.CopyMode({ JumpBackward = { prev_char = false } }) },
			-- 一番下へ
			{ mods = "NONE", key = "G", action = act.CopyMode("MoveToScrollbackBottom") },
			-- 一番上へ
			{ mods = "NONE", key = "g", action = act.CopyMode("MoveToScrollbackTop") },
			-- viweport
			{ mods = "NONE", key = "H", action = act.CopyMode("MoveToViewportTop") },
			{ mods = "NONE", key = "L", action = act.CopyMode("MoveToViewportBottom") },
			{ mods = "NONE", key = "M", action = act.CopyMode("MoveToViewportMiddle") },
			-- スクロール
			{ mods = "CTRL", key = "b", action = act.CopyMode("PageUp") },
			{ mods = "CTRL", key = "f", action = act.CopyMode("PageDown") },
			{ mods = "CTRL", key = "d", action = act.CopyMode({ MoveByPage = 0.5 }) },
			{ mods = "CTRL", key = "u", action = act.CopyMode({ MoveByPage = -0.5 }) },
			-- 範囲選択モード
			{ mods = "NONE", key = "v", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
			{ mods = "CTRL", key = "v", action = act.CopyMode({ SetSelectionMode = "Block" }) },
			{ mods = "NONE", key = "V", action = act.CopyMode({ SetSelectionMode = "Line" }) },
			-- コピー
			{ mods = "NONE", key = "y", action = act.CopyTo("Clipboard") },

			-- コピーモードを終了
			{ mods = "NONE", key = "Enter", action = act.Multiple({ { CopyTo = "ClipboardAndPrimarySelection" }, { CopyMode = "Close" } }), },
			{ mods = "NONE", key = "Escape", action = act.CopyMode("Close") },
			{ mods = "CTRL", key = "c", action = act.CopyMode("Close") },
			{ mods = "NONE", key = "q", action = act.CopyMode("Close") },
		},
	},
}
