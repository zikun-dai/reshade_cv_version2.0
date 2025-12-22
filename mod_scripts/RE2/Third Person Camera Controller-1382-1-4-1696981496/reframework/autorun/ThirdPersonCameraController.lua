--'Third Person Camera Controller' REFramework script for Resident Evil 4 Remake
--By alphaZomega
--Lets you change third person camera settings
local version = "v1.4" --August 14, 2023

local isRE4 = (reframework:get_game_name() == "re4")
if not isRE4 and not reframework:get_game_name():find("re[23]") then return end

local default_csettings = {
	enabled = true,
	normal = {
		gazedistance_multiplier = 1.0,
		fov_multiplier = 1.0,
		offset = {0,0,0},
	},
	alt = {
		gazedistance_multiplier = 2.0,
		fov_multiplier = 1.0,
		offset = {0,0,0},
	},
	aim = {
		gazedistance_multiplier = 1.0,
		fov_multiplier = 1.0,
		offset = {0,0,0},
	},
	affect_rifles = false,
	disable_action_cam = false,
	walk_to_cam = true,
	increment = 0.05,
	hotkeys = {
		["Modifier (TPCC)"] = "LControl",
		["Lock-on"] = "RStickPush",
		["Change to Alternate Settings"] = "B",
		["Enable Walk-Towards-Cam"] = "N",
		["Increase GazeDistance"] = "NumPad7",
		["Decrease GazeDistance"] = "NumPad1",
		["Increase Cam FOV"] = "Subtract",
		["Decrease Cam FOV"] = "Add",
		["Cam Offset Forward"] = "NumPad8",
		["Cam Offset Backward"] = "NumPad2",
		["Cam Offset Left"] = "NumPad4",
		["Cam Offset Right"] = "NumPad6",
		["Cam Offset Up"] = "NumPad9",
		["Cam Offset Down"] = "NumPad3",
		["Reload Current Preset"] = "NumPad5",
	},
}

local hk = require("Hotkeys/Hotkeys")

local function recurse_def_settings(tbl, defaults_tbl)
	for key, value in pairs(defaults_tbl) do
		if type(tbl[key]) ~= type(value) then 
			if type(value) == "table" then
				tbl[key] = recurse_def_settings({}, value)
			else
				tbl[key] = value
			end
		elseif type(value) == "table" then
			tbl[key] = recurse_def_settings(tbl[key], value)
		end
	end
	return tbl
end

csettings = recurse_def_settings(json.load_file("TPPCameraController.json") or {}, default_csettings)

hk.setup_hotkeys(csettings.hotkeys, default_csettings.hotkeys)

local playermanager = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
local character_manager = sdk.get_managed_singleton(sdk.game_namespace("CharacterManager"))
local game_clock = sdk.get_managed_singleton(sdk.game_namespace("GameClock")) or sdk.get_managed_singleton("share.GameClock")
local player_cam_ctrl
local last_skipped_time = 0
local files_glob -- = fs.glob([[ThirdPersonCameraController\\Presets\\.*.json]])
local is_alt_mode = false
local last_fov
local player_context
local jacked_param_re4
local is_jacked_re2 = false
local player
local params = {}
local param
local hijacked_diff
local changed = false
local wc = false
		
local function set_wc()
	wc = wc or changed
end

local temp_settings = {
	normal = {preset_idx = 1, save_txt=""},
	alt = {preset_idx = 1, save_txt=""},
	aim = {preset_idx = 1, save_txt=""},
}

local re4_rifle_ids = {
	[4400] = true, --SR 1903
    [4401] = true, --CQBR
	[4402] = true, --Stingray 
}

local function tooltip(text)
    if imgui.is_item_hovered() then imgui.set_tooltip(text) end
end

local function get_gametime()
	return game_clock:get_ActualPlayingTime() * 0.000001
end

local function get_localplayer_context_re4()
    return character_manager:call("getPlayerContextRef")
end

local function imgui_table_vec(func, name, value, args)
	args = args or {}
    value = (value[4] and Vector4f.new(value[1], value[2], value[3], value[4])) or (value[3] and Vector3f.new(value[1], value[2], value[3])) or Vector2f.new(value[1], value[2]) --convert to vector
    changed, value = func(name, value, table.unpack(args))
    value = {value.x, value.y, value.z, value.w} --convert back to table
    return changed, value
end     

local function find_node_idx_by_name(tree, node_name, order)
	local nodes = tree:get_nodes()
	local order_ctr, result = 0
	for i=0, nodes:size()-1 do
		if nodes[i]:get_full_name() == node_name then
			if not order or order_ctr == order then
				return i
			end
			result = i
			order_ctr = order_ctr + 1
		end
	end
	return result
end

local function load_preset(preset_idx, key_type)
	wc = true
	if csettings[key_type].preset_idx == 1 then
		csettings[key_type] = hk.recurse_def_settings({}, default_csettings[key_type])
	else
		csettings[key_type] = json.load_file("ThirdPersonCameraController\\Presets\\"..files_glob[csettings[key_type].preset_idx]..".json") or csettings[key_type]
	end
	csettings[key_type].preset_idx = preset_idx
	json.dump_file("TPPCameraController.json", csettings)
end
	
re.on_script_reset(function()
	for obj, tbl in pairs(params) do
		for name, fieldvalue in pairs(tbl) do
			obj[name] = fieldvalue
		end
	end
	if jacked_param_re4 then
		jacked_param_re4.obj._Offset = jacked_param_re4._Offset
		jacked_param_re4.obj._GazeDistance = jacked_param_re4._GazeDistance
		jacked_param_re4.obj._FieldOfView = jacked_param_re4._FieldOfView 
	end
end)

local re4_hold_enums = {[6]=1, [7]=1, [8]=1, [9]=1, [10]=1, [11]=1, [16]=1, [21]=1, [33]=1,}


local function exec_re4()
	
	if not csettings.enabled then return end
	local was_changed = false
	local context = get_localplayer_context_re4()
	local body = context and context:get_BodyGameObject()
	if context and not player_context then
		walk_start_stand_idx, walk_loop_stand_idx = nil
	end
	player_context = context
	
	
	if hk.check_hotkey("Change to Alternate Settings") then
		is_alt_mode = not is_alt_mode
	end
	
	if hk.check_hotkey("Enable Walk-Towards-Cam") then
		csettings.walk_to_cam = not csettings.walk_to_cam
		was_changed = true
	end
	
	if body then
		
		local h_updater = context:get_HeadUpdater()
		local b_updater = context:get_BodyUpdater()
		local camc = h_updater and h_updater:get_CameraController()
		local cam = sdk.get_primary_camera()
		
		if camc and camc._BusyCameraController and camc._BusyCameraController._Param then
			
			local wp_id = h_updater:get_EquipWeaponID()
			param = camc._BusyCameraController._Param._NextInfo._Param
			local state = camc._BusyCameraController._CurrentStateParam and camc._BusyCameraController._CurrentStateParam["<State>k__BackingField"]
			local jacked = h_updater["<IsJacked>k__BackingField"]
			local do_update = wc
			
			if jacked or (state and state ~= 27) then
				
				local is_hold = not not re4_hold_enums[state or 0]
				if not params[param] then 
					do_update = true
					params = {
						[param] = {
							_GazeDistance = param._GazeDistance,
							_FieldOfView = param._FieldOfView,
							_Offset = param._Offset,
						}
					}
				end
				
				if jacked then  --backup jacked camera param:
					hijacked_diff = hijacked_diff or csettings.disable_action_cam and get_gametime()-last_skipped_time < 1.0 and (player_context:get_BodyGameObject():get_Transform():getJointByName("Hip"):get_Position() - player_context:get_Position())
					jacked_param_re4 = jacked_param_re4 or {
						_GazeDistance = param._GazeDistance,
						_FieldOfView = param._FieldOfView,
						_Offset = param._Offset,
						obj = param,
					}
				elseif jacked_param_re4 then --restore jacked camera param to original state:
					jacked_param_re4.obj._Offset = jacked_param_re4._Offset
					jacked_param_re4.obj._GazeDistance = jacked_param_re4._GazeDistance
					jacked_param_re4.obj._FieldOfView = jacked_param_re4._FieldOfView 
					jacked_param_re4, hijacked_diff = nil
				end
				
				local is_aim = false
				local type = (is_alt_mode and "alt") or "normal"
				
				if do_update or hijacked_diff or hk.check_hotkey("Change to Alternate Settings") then
					if hijacked_diff then
						local difference = player_context:get_BodyGameObject():get_Transform():getJointByName("Hip"):get_Position() - player_context:get_Position() - hijacked_diff
						jacked_param_re4.obj._Offset = Vector3f.new(jacked_param_re4._Offset.x + csettings[type].offset[1], jacked_param_re4._Offset.y + csettings[type].offset[2], jacked_param_re4._Offset.z + csettings[type].offset[3]) + difference
					elseif jacked then
						jacked_param_re4.obj._Offset = Vector3f.new(jacked_param_re4._Offset.x + csettings[type].offset[1], jacked_param_re4._Offset.y + csettings[type].offset[2], jacked_param_re4._Offset.z + csettings[type].offset[3])
						jacked_param_re4.obj._GazeDistance = jacked_param_re4._GazeDistance * csettings[type].gazedistance_multiplier
						jacked_param_re4.obj._FieldOfView = jacked_param_re4._FieldOfView * csettings[type].fov_multiplier
					else
						local offs = params[param]._Offset
						if is_hold then
							if csettings.affect_rifles or not re4_rifle_ids[wp_id] then
								param._Offset = Vector3f.new(offs.x + csettings.aim.offset[1], offs.y + csettings.aim.offset[2], offs.z + csettings.aim.offset[3])
								param._GazeDistance = params[param]._GazeDistance * csettings.aim.gazedistance_multiplier
								param._FieldOfView = params[param]._FieldOfView * csettings.aim.fov_multiplier
								cam:set_FOV(last_fov)
								is_aim = true
							end
						else
							param._Offset = Vector3f.new(offs.x + csettings[type].offset[1], offs.y + csettings[type].offset[2], offs.z + csettings[type].offset[3])
							param._GazeDistance = params[param]._GazeDistance * csettings[type].gazedistance_multiplier
							param._FieldOfView = params[param]._FieldOfView * csettings[type].fov_multiplier
						end
					end
				end
				last_type = (is_aim and "aim") or type
			end
			last_fov = cam:get_FOV()
		end
		
		local mfsm2 = csettings.walk_to_cam and body:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
		if mfsm2 then
			local tree = mfsm2:get_Layer():add_ref():get_Item(0):get_tree_object()
			local walk_start_node = tree:get_node_by_name("WalkStart")
			if walk_start_node then
				walk_start_stand_idx = walk_start_stand_idx or find_node_idx_by_name(tree, "Walk.WalkStart.Stand")
				walk_loop_stand_idx = walk_loop_stand_idx or find_node_idx_by_name(tree, "Walk.WalkLoop.Stand", 1)
				local watch_dir = player_context:get_WatchDirection(); watch_dir.y = 0
				local body_dir = body:get_Transform():get_AxisZ()
				is_cam_aligned_with_body = ((watch_dir - body_dir):length() < 1.0) or (((body_dir - player_context:get_MoveDirection()):length() > 1.5))
				walk_start_node:get_data():get_start_states()[1] = (is_cam_aligned_with_body and walk_start_stand_idx) or walk_loop_stand_idx
			end
		end
		
	end
	
	if was_changed then
		json.dump_file("TPPCameraController.json", csettings)
	end
	wc = false
end

local function exec_re2_re3()
	
	player_cam_ctrl = player_cam_ctrl and player_cam_ctrl:get_Valid() and player_cam_ctrl
	player = playermanager:call("get_CurrentPlayer")
	if not csettings.enabled or not player_cam_ctrl or not player then return end
	
	local was_changed = false
	local is_hold = player_cam_ctrl:get_IsHoldWeaponCamera()
	local type = (is_hold and "aim") or (is_alt_mode and "alt") or "normal"
	
	if hk.check_hotkey("Change to Alternate Settings") then
		is_alt_mode = not is_alt_mode
	end
	
	if hk.check_hotkey("Enable Walk-Towards-Cam") then
		csettings.walk_to_cam = not csettings.walk_to_cam
		was_changed = true
	end
	
	if hk.check_hotkey("Reload Current Preset") then
		load_preset(csettings[type].preset_idx, type)
	end
	
	if player then
		
		local cam = sdk.get_primary_camera()
		param = player_cam_ctrl["<Param>k__BackingField"]["<NextInfo>k__BackingField"]._Param._Param
		player_cam_ctrl["<OverwriteParam>k__BackingField"] = nil
		
		local do_update = wc
		local was_jacked = is_jacked_re2
		
		if not params[param] then 
			do_update = true
			params = {
				[param] = {
					_GazeDistance = param._GazeDistance,
					_FieldOfView = param._FieldOfView,
					_Offset = param._Offset,
				}
			}
			is_jacked_re2 = (player_cam_ctrl["<NowKind>k__BackingField"] == 4)
		end
		
		is_jacked_re2 = (player_cam_ctrl["<NowKind>k__BackingField"] == 4) and (is_jacked_re2 or ((get_gametime() - last_skipped_time) < 1.0))
		local offs = params[param]._Offset
		
		if is_jacked_re2 then --and not do_update then
			param._OffsetBasing = 2
			offs = (player:get_Transform():getJointByName("spine_2"):get_Position() - player:get_Transform():getJointByName("root"):get_Position())
			do_update = true
		elseif was_jacked then
			param._OffsetBasing = 1
		end
		
		if do_update or hk.check_hotkey("Change to Alternate Settings") then
			param._Offset = Vector3f.new(offs.x + csettings[type].offset[1], offs.y + csettings[type].offset[2], offs.z + csettings[type].offset[3])
			param._GazeDistance = params[param]._GazeDistance * csettings[type].gazedistance_multiplier
			param._FieldOfView = params[param]._FieldOfView * csettings[type].fov_multiplier
			last_type = type
		end
		last_fov = cam:get_FOV()
	end
	
	if was_changed then
		json.dump_file("TPPCameraController.json", csettings)
	end
	wc = false
end

re.on_pre_application_entry("PrepareRendering", function()
	if dump_fn then 
		dump_fn()
	end
	
	if freeze_fn then
		freeze_fn()
	end
	
	if hk.hotkeys["Modifier (TPCC)"] == "[Not Bound]" or hk.chk_down("Modifier (TPCC)") then
		local inc = csettings.increment
		local fov_diff = (hk.chk_down("Increase Cam FOV") and inc * 0.2) or (hk.chk_down("Decrease Cam FOV") and -inc * 0.2) or 0.0
		local gaze_diff = (hk.chk_down("Increase GazeDistance") and inc) or (hk.chk_down("Decrease GazeDistance") and -inc) or 0.0
		local x_diff = (hk.chk_down("Cam Offset Left") and -inc) or (hk.chk_down("Cam Offset Right") and inc) or 0.0
		local y_diff = (hk.chk_down("Cam Offset Up") and inc) or (hk.chk_down("Cam Offset Down") and -inc) or 0.0
		local z_diff = (hk.chk_down("Cam Offset Forward") and -inc) or (hk.chk_down("Cam Offset Backward") and inc) or 0.0
		if gaze_diff ~= 0.0 or fov_diff ~= 0.0 or x_diff ~= 0.0 or y_diff ~= 0.0 or z_diff ~= 0.0 then
			local offs = csettings[last_type].offset
			csettings[last_type].offset = {offs[1] + x_diff, offs[2] + y_diff, offs[3] + z_diff,}
			csettings[last_type].gazedistance_multiplier = csettings[last_type].gazedistance_multiplier + gaze_diff
			csettings[last_type].fov_multiplier = csettings[last_type].fov_multiplier + fov_diff
			wc = true
		end
	end
	
	if isRE4 then
		exec_re4()
	end
end)

local function imgui_preset_menu(key_type)
	if imgui.button("Save Preset") and temp_settings[key_type].save_txt:len() > 0 then
		local txt = temp_settings[key_type].save_txt:gsub("%.json", "") .. ".json"
		if json.dump_file("ThirdPersonCameraController\\Presets\\"..txt, csettings[key_type]) then
			re.msg("Saved to\nreframework\\data\\ThirdPersonCameraController\\Presets\\"..temp_settings[key_type].save_txt..".json")
		end
		files_glob = nil
	end
	imgui.same_line() 
	changed, temp_settings[key_type].save_txt = imgui.input_text("  ", temp_settings[key_type].save_txt)
	tooltip("Input new preset name")
	
	if imgui.button("Load Preset") then 
		load_preset(csettings[key_type].preset_idx, key_type)
		files_glob = nil
	end
	
	imgui.same_line() 
	changed, csettings[key_type].preset_idx = imgui.combo(" ", csettings[key_type].preset_idx, files_glob or {})
	tooltip("Load settings from json files in reframework\\data\\ThirdPersonCameraController\\Presets\\")
	if changed then  
		load_preset(csettings[key_type].preset_idx, key_type)
	end
end

re.on_draw_ui(function()
	if imgui.tree_node("Third Person Camera Controller") then
		imgui.begin_rect()
		
		if imgui.button("Reset to Defaults") then
			csettings = recurse_def_settings({}, default_csettings)
			hk.reset_from_defaults_tbl(default_csettings.hotkeys)
			wc = true
		end
		
		changed, csettings.enabled = imgui.checkbox("Enabled", csettings.enabled)
		tooltip("Enable/Disable the mod")
		
		if csettings.enabled then
			
			if not files_glob then
				files_glob = fs.glob([[ThirdPersonCameraController\\Presets\\.*.json]])
				for i, path in ipairs(files_glob) do files_glob[i] = path:match("ThirdPersonCameraController\\Presets\\(.+).json") end
				table.insert(files_glob, 1, "Reset to Default")
			end
			
			changed, csettings.disable_action_cam = imgui.checkbox("Disable Action Camera", csettings.disable_action_cam); set_wc()
			tooltip("Enable/Disable forced camera movements, such as when getting grappled")
			
			if isRE4 then
				changed, csettings.walk_to_cam = imgui.checkbox("Walk Towards Camera", csettings.walk_to_cam); set_wc()
				tooltip("Allows you to walk independently from the camera by moving in the direction your character is already facing (if not facing the same direction as the camera)")
			end
			
			changed, is_alt_mode = imgui.checkbox("Use Alternate Settings", is_alt_mode); set_wc()
			
			imgui.set_next_item_open(true, 1 << 1)
			if not is_alt_mode then imgui.begin_rect(); imgui.begin_rect() end
			if imgui.tree_node("Normal Settings") then
				imgui.begin_rect()
				changed, csettings.normal.gazedistance_multiplier = imgui.drag_float("Distance Multiplier", csettings.normal.gazedistance_multiplier, 0.005, 0.01, 50.0); set_wc()
				tooltip("Affects camera distance")
				changed, csettings.normal.fov_multiplier = imgui.drag_float("Field of View Multiplier", csettings.normal.fov_multiplier, 0.001, 0.01, 3.0); set_wc()
				tooltip("Affects camera Field of View")
				changed, csettings.normal.offset = imgui_table_vec(imgui.drag_float3, "Offset", csettings.normal.offset, {0.001, -50.0, 50.0}); set_wc()
				tooltip("Affects camera offset")
				imgui_preset_menu("normal")
				imgui.end_rect(1)
				imgui.tree_pop()
			end
			if not is_alt_mode then imgui.end_rect(2); imgui.end_rect(3) end
			
			imgui.spacing()
			
			if is_alt_mode then imgui.begin_rect(); imgui.begin_rect() end
			if imgui.tree_node("Alternate Settings") then
				imgui.begin_rect()
				changed, csettings.alt.gazedistance_multiplier = imgui.drag_float("Distance Multiplier", csettings.alt.gazedistance_multiplier, 0.005, 0.01, 50.0); set_wc()
				tooltip("Affects camera distance")
				changed, csettings.alt.fov_multiplier = imgui.drag_float("Field of View Multiplier", csettings.alt.fov_multiplier, 0.001, 0.01, 3.0); set_wc()
				tooltip("Affects camera Field of View")
				changed, csettings.alt.offset = imgui_table_vec(imgui.drag_float3, "Offset", csettings.alt.offset, {0.001, -50.0, 50.0}); set_wc()
				tooltip("Affects camera offset")
				imgui_preset_menu("alt")
				imgui.end_rect(1)
				imgui.tree_pop()
			end
			if is_alt_mode then imgui.end_rect(2); imgui.end_rect(3) end
			
			imgui.spacing()
			
			imgui.set_next_item_open(true, 1 << 1)
			if imgui.tree_node("Aim Settings") then
				imgui.begin_rect()
				changed, csettings.aim.gazedistance_multiplier = imgui.drag_float("Aim Distance Multiplier", csettings.aim.gazedistance_multiplier, 0.005, 0.01, 50.0); set_wc()
				tooltip("Affects camera distance")
				changed, csettings.aim.fov_multiplier = imgui.drag_float("Aim Field of View Multiplier", csettings.aim.fov_multiplier, 0.001, 0.01, 3.0); set_wc()
				tooltip("Affects camera Field of View")
				changed, csettings.aim.offset = imgui_table_vec(imgui.drag_float3, "Aim Offset", csettings.aim.offset, {0.001, -50.0, 50.0}); set_wc()
				tooltip("Affects camera offset")
				if isRE4 then
					changed, csettings.affect_rifles = imgui.checkbox("Affect Rifles", csettings.affect_rifles); set_wc()
					tooltip("Affects first person rifles")
				end
				imgui_preset_menu("aim")
				imgui.end_rect(1)
				imgui.tree_pop()
			end
			
			imgui.spacing()
			
			if imgui.tree_node("Hotkeys") then
				imgui.begin_rect()
				changed = hk.hotkey_setter("Change to Alternate Settings"); set_wc()	
				if isRE4 then
					changed = hk.hotkey_setter("Enable Walk-Towards-Cam"); set_wc()
				end
				
				changed = hk.hotkey_setter("Modifier (TPCC)", nil,  "Modifier"); set_wc()	
				changed = hk.hotkey_setter("Increase GazeDistance", "Modifier (TPCC)"); set_wc()	
				changed = hk.hotkey_setter("Decrease GazeDistance", "Modifier (TPCC)"); set_wc()	
				changed = hk.hotkey_setter("Increase Cam FOV", "Modifier (TPCC)"); set_wc()	
				changed = hk.hotkey_setter("Decrease Cam FOV", "Modifier (TPCC)"); set_wc()	
				changed = hk.hotkey_setter("Cam Offset Forward", "Modifier (TPCC)"); set_wc()	
				changed = hk.hotkey_setter("Cam Offset Backward", "Modifier (TPCC)"); set_wc()	
				changed = hk.hotkey_setter("Cam Offset Left", "Modifier (TPCC)"); set_wc()	
				changed = hk.hotkey_setter("Cam Offset Right", "Modifier (TPCC)"); set_wc()	
				changed = hk.hotkey_setter("Cam Offset Up", "Modifier (TPCC)"); set_wc()	
				changed = hk.hotkey_setter("Cam Offset Down", "Modifier (TPCC)"); set_wc()	
				changed = hk.hotkey_setter("Reload Current Preset", "Modifier (TPCC)"); set_wc()	
				
				changed, csettings.increment = imgui.drag_float("Increment", csettings.increment, 0.0001, 0.0001, 0.1)
				
				imgui.end_rect(2)
				imgui.spacing()
				imgui.tree_pop()
			end
			
			if EMV and param and not imgui.spacing() and imgui.tree_node("Param") then
				imgui.managed_object_control_panel(param)
				imgui.tree_pop()
			end
		end
		imgui.text("																			"..version.."  |  By alphaZomega")
		imgui.end_rect(2)
		if wc then
			hk.update_hotkey_table(csettings.hotkeys)
			local last_changed_time = get_gametime()
			dump_fn = function()
				if get_gametime() - last_changed_time > 0.8 then
					dump_fn = nil
					json.dump_file("TPPCameraController.json", csettings)
				end
			end
		end
		imgui.tree_pop()
	end
end)

if isRE4 then 
	sdk.hook(sdk.find_type_definition("chainsaw.ActionCameraPlayRequest"):get_method("start"),
		function(args)
			if csettings.disable_action_cam then
				last_skipped_time = get_gametime()
				return sdk.PreHookResult.SKIP_ORIGINAL
			end
		end
	)
else --RE2 and RE3
	sdk.hook(sdk.find_type_definition(sdk.game_namespace("camera.PlayerCameraController")):get_method("onCameraUpdate"),
		function(args)
			player_cam_ctrl = sdk.to_managed_object(args[2])
		end,
		function(retval)
			exec_re2_re3()
			return retval
		end
	)
	sdk.hook(sdk.find_type_definition(sdk.game_namespace("camera.fsmv2.action.ActionCameraPlayRequestRoot")):get_method("playActionCamera(System.UInt32, System.UInt32, System.UInt32, app.ropeway.camera.ConstTargetParam, app.ropeway.camera.LookAtTargetParam, app.ropeway.camera.MotionInterpolateParam, System.Boolean, System.Boolean, System.Boolean)"),
		function(args)
			if csettings.disable_action_cam then
				last_skipped_time = get_gametime()
				return sdk.PreHookResult.SKIP_ORIGINAL
			end
		end
	)
	sdk.hook(sdk.find_type_definition(sdk.game_namespace("camera.PlayerCameraController")):get_method("attainDampingParam()"),
		function(args)
			exec_re2_re3()
		end
	)
end