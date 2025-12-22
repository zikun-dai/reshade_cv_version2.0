--Classic Cameras (RE2R/RE3R Classic)
--By alphaZomega
--Allows placement and playback of classic fixed camera angles in Resident Evil 2 and 3 Remake
local version = "1.17" --Nov 18, 2024

--Fixed an issue with Semi-Fixed cameras drifting to player on camera transitions
--Fixed an issue with Running Quick Turn turning you around as soon as you start running if it's set to Circle
--Running Quick Turn can now only be triggered with the Hotkey
--Running Quick Turn now turns more accurately respective to your stick direction
--'Turn Camera to Enemy' now drifts to face the enemy rather than instantly snapping
--Tweaked and fixed issues with 'Tank Sensitivity' option

local isRE2 = (reframework:get_game_name() == "re2")
local isRE3 = (reframework:get_game_name() == "re3")
if not isRE2 and not isRE3 then return end

local default_ccs = {
	enabled = true,
	always_follow_player = false,
	do_run_turnaround = false,
	cam_rel_delay_time = 0.35,
	do_autoaim = true,
	autoaim_all = true,
	autoaim_hitscan = false,
	autoaim_beam_size = 3.0,
	walk_type = 3,
	run_type = 5,
	turn_speed = 1.0,
	turn_speed_jog = 1.0,
	enable_practice = false,
	no_damage = false,
	reticle_type = 2,
	use_lasersight = true,
	laser_color = 0xFF0000FF,
	laser_intensity = 10.0,
	flashing_items = true,
	player_light_strength = 104,
	env_light_strength = 0,
	use_env_light = false,
	lock_on_type = 2,
	disable_during_aim = false,
	disable_during_bites = false,
	follow_cam_do_pitch = true,
	follow_cam_do_yaw = true,
	follow_cam_do_twist = false,
	follow_cam_do_edges = false,
	follow_cam_randomize = false,
	follow_cam_edge_limit = 0.25,
	follow_cam_damp_rate = 0.25,
	Controls_idx = 4,
	Autoaim_idx = 3,
	Camera_idx = 2,
	show_button_prompts = true,
	cam_switch_delay = 1.0,
	--do_spatial_audio = true,
	tank_walk_bwd_invert = false,
	show_window = true,
	use_dpad_controls = true,
	do_dpad_swap = false,
	freeze_angle_toggle = false,
	turn_angle_do_bend = false,
	fix_jog_anim = true,
	do_detect_behind = true,
	use_quickturn_button = true,
	hold_circle_to_run = true,
	hold_circle_to_run_stick = true,
	cam_rel_walk_do_strafe = false,
	disable_pivot = true,
	do_classic_aim = false,
	do_remake_run = false,
	do_remake_run_reset = false,
	no_vignette = true,
	no_cam_light_overrides = false,
	no_pl_light_overrides = false,
	tank_sensitivity = 0.5,
	do_invert_y = false,
	run_button_type = 2,
	do_use_kb_run = false,
	autobright_type = 2,
	do_auto_brighten_gamma = true,
	do_auto_brighten_ev = true,
	auto_brighten_rate_ev = 1.3,
	auto_brighten_rate_gamma = 1.1,
	do_qturn_fix = true,
}

local function setup_gamepad_specific_defaults()
	local is_pad_connected = sdk.call_native_func(sdk.get_native_singleton("via.hid.Gamepad"), sdk.find_type_definition("via.hid.GamePad"), "getMergedDevice", 0):get_Connecting()
	default_ccs.hotkeys = {
		["Enable"] = is_pad_connected and "T" or "T",
		["Cast Ray"] = "[Not Bound]",
		["Draw Collider"] = "[Not Bound]", 
		["Snap Cam"] = "[Not Bound]",
		["Use Colliders"] = "[Not Bound]",
		["Disable Autoaim"] = is_pad_connected and "A (X)" or "LShift",
		["Disable Autoaim_$"] = is_pad_connected and "LT (L2)" or nil,
		["Freeze Angle"] = is_pad_connected and "RT (R2)" or "LAlt",
		["Strafe / Classic Aim"] = is_pad_connected and "A (X)" or "C",	
		["Turn Camera To Enemy"] = is_pad_connected and "LStickPush" or "B",
		["Turn Camera To Enemy_$"] = is_pad_connected and "LT (L2)" or nil,
		["Allow D-pad Shortcuts"] = "RStickPush",
		["Turn Camera"] = is_pad_connected and "RStickPush" or "V",
		["Autoaim Button"] = "[Not Bound]",
		["Toggle Laser Sight"] = is_pad_connected and "LB (L1)" or "L",
		["Toggle Laser Sight_$"] = is_pad_connected and "LT (L2)" or nil,
		["Running Quick Turn"] = is_pad_connected and "B (Circle)" or "Q",
		["Toggle Follow Cam"] = is_pad_connected and "A (X)" or "H",
		["Toggle Follow Cam_$"] = is_pad_connected and "RT (R2)" or nil,
	}
end
setup_gamepad_specific_defaults()

local hk = require("Hotkeys/Hotkeys")

local ccs = hk.recurse_def_settings(json.load_file("ClassicCams\\CCSettings.json") or {}, default_ccs)

hk.setup_hotkeys(ccs.hotkeys)

local changed, wc = false
local c_changed = false
local current_loc_string
local player
local classic_cam
local mfsm2
local camera
local cam_joint
local og_cam_mat
local fixed_cam_mat
local cams = {}
local cams_list = {}
local mousedata = {}
local sound_listeners = {}
local spring_aim_timer = gtime
local last_qt_time = gtime
local ticks = 0

local just_aimed = false
local just_aimed_time = false
local is_aiming = false
local is_drawing = false
local is_shooting = false
local is_ada_hack_gun = false
local is_sherry_crouch = false
local was_manual_aim = false
local is_manual_aim = false
local ran_this_frame = false
local is_jacked = false
local is_lasersight_visible = false
local is_jogging = false
local is_walking = false
local is_disabled_aiming = false
local is_disabled_bite = false
local is_grappled = false
local is_strafe_button = false
local is_classic_aim = false
--local is_carry_sherry = false
local prev_yaw
local player_screen_pos
local node_name = ""
local prev_node_name = ""

local autoaim_enemy
local lookat_enemy
local target_enemy
local last_target_enemy = {}
local lasersight
local pl_cam_ctrl

local temp = {
	fns = {},
	control_fns = {},
	do_draw=true, 
	do_snap_cams=true,
	do_use_colliders=true,
	cached_gameobjs = {},
	presets_data = {},
	last_cam_change_time = 0.0,
}

local function get_enum(typename)
	local enum, names, reverse_enum = {}, {}, {}
	for i, field in ipairs(sdk.find_type_definition(typename):get_fields()) do
		if field:is_static() and field:get_data() ~= nil then
			enum[field:get_name()] = field:get_data() 
			reverse_enum[field:get_data()] = field:get_name()
			table.insert(names, field:get_name())
		end
	end
	return {enum=enum, names=names, reverse_enum=reverse_enum}
end

local locations = get_enum(sdk.game_namespace("gamemastering.Location.ID")).reverse_enum
local maps = get_enum(sdk.game_namespace("gamemastering.Map.ID")).reverse_enum
local areas = get_enum(sdk.game_namespace("gamemastering.Map.Area")).reverse_enum
local scenarios = get_enum(sdk.game_namespace("ScenarioDefine.ScenarioNo")).reverse_enum
local scenario_types = get_enum(sdk.game_namespace("gamemastering.ScenarioSequenceManager.ManageType")).reverse_enum
local kind_ids = get_enum(sdk.game_namespace("EnemyDefine.KindID")).reverse_enum

local em = sdk.get_managed_singleton(sdk.game_namespace("EnemyManager"))
local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
local option_manager = sdk.get_managed_singleton(sdk.game_namespace("OptionManager"))
local renderer = sdk.get_native_singleton("via.render.Renderer")
local og_gamma = sdk.call_native_func(renderer, sdk.find_type_definition("via.render.Renderer"), "get_Gamma")
local input_system = sdk.get_managed_singleton(sdk.game_namespace("InputSystem"))
local rstick = input_system:get_RStick()
local lstick = input_system:get_LStick()

local game_clock = sdk.get_managed_singleton(sdk.game_namespace("GameClock"))
local mouse = sdk.call_native_func(sdk.get_native_singleton("via.hid.Mouse"), sdk.find_type_definition("via.hid.Mouse"), "get_Device")
local lookat_method = sdk.find_type_definition("via.matrix"):get_method("makeLookAtLH")
local set_node_method = sdk.find_type_definition("via.motion.MotionFsm2Layer"):get_method("setCurrentNode(System.String, via.behaviortree.SetNodeInfo, via.motion.SetMotionTransitionInfo)")
local make_euler_method = sdk.find_type_definition("via.matrix"):get_method("makeEuler(via.vec3, via.math.RotationOrder)")
local clamp_method = sdk.find_type_definition("via.math"):get_method("clamp(System.Single, System.Single, System.Single)")
local col = ValueType.new(sdk.find_type_definition("via.Color")); col.rgba = 0xFFB9C8C8
local interper = sdk.create_instance("via.motion.SetMotionTransitionInfo"):add_ref()
local setn = ValueType.new(sdk.find_type_definition("via.behaviortree.SetNodeInfo"))
interper:set_InterpolationFrame(12.0)
setn:call("set_Fullname", true)

local via_physics_system = sdk.get_native_singleton("via.physics.System")
local contact_pt_td = sdk.find_type_definition("via.physics.ContactPoint")
local ray_result = sdk.create_instance("via.physics.CastRayResult"):add_ref()
local ray_method = sdk.find_type_definition("via.physics.System"):get_method("castRay(via.physics.CastRayQuery, via.physics.CastRayResult)")
local ray_query = sdk.create_instance("via.physics.CastRayQuery"):add_ref()
ray_query:clearOptions()
ray_query:enableAllHits()
ray_query:enableNearSort()
local filter_info = ray_query:get_FilterInfo()
filter_info:set_Group(0)
local shape_cast_result = sdk.create_instance("via.physics.ShapeCastResult"):add_ref()
local shape_ray_method = sdk.find_type_definition("via.physics.System"):get_method("castSphere(via.Sphere, via.vec3, via.vec3, System.UInt32, via.physics.FilterInfo, via.physics.ShapeCastResult)")
local shape_ray_method2 = sdk.find_type_definition("via.physics.System"):get_method("castShape(via.physics.ShapeCastQuery, via.physics.ShapeCastResult)")
local shape_cast_result = sdk.create_instance("via.physics.ShapeCastResult"):add_ref()
local sphere = ValueType.new(sdk.find_type_definition("via.Sphere"))
local box = ValueType.new(sdk.find_type_definition("via.physics.BoxShape"))
box:set_UserData(sdk.create_instance("via.physics.UserData"):add_ref())
local shape_cast_query = sdk.create_instance("via.physics.ShapeCastQuery"):add_ref()
shape_cast_query:set_Shape(box)
shape_cast_query:set_FilterInfo(filter_info)

local pl_ctrl
local pl_pos, pl_center_pos
local gtime = game_clock:get_ActualPlayingTime() * 0.000001
local sweetlight_def_intensity = {}
local timescale_mult = 1.0
local deltatime, last_time
local pl_condition
local pl_xform

local is_pad = false
local is_paused = false

local inhibit_arrs = {
	shortcuts = sdk.create_managed_array(sdk.game_namespace("InputDefine.Kind"), 4):add_ref(),
	move = sdk.create_managed_array(sdk.game_namespace("InputDefine.Kind"), 1):add_ref(),
	qt = sdk.create_managed_array(sdk.game_namespace("InputDefine.Kind"), 1):add_ref(),
}
if not pcall(function()
	inhibit_arrs.move[0] = 1 --DX11 throws an error with this
	inhibit_arrs.qt[0] = 32
	inhibit_arrs.shortcuts[0], inhibit_arrs.shortcuts[1], inhibit_arrs.shortcuts[2], inhibit_arrs.shortcuts[3] = 17179869184, 34359738368, 68719476736, 137438953472
end) then
	inhibit_arrs.move[0].value__ = 1 
	inhibit_arrs.qt[0].value__ = 32
	inhibit_arrs.shortcuts[0].value__, inhibit_arrs.shortcuts[1].value__, inhibit_arrs.shortcuts[2].value__, inhibit_arrs.shortcuts[3].value__ = 17179869184, 34359738368, 68719476736, 137438953472
end

local function cast_ray(start_position, end_position, layer, maskbits, shape_radius, do_reverse, box_rotation)
	local result = {}
	local result_obj = shape_radius and shape_cast_result or ray_result
	filter_info:set_Layer(layer)
	filter_info:set_MaskBits(maskbits)
	result_obj:clear()
	if shape_radius then
		if box_rotation ~= nil then
			if not box_rotation then
				box_rotation = lookat_method:call(nil, start_position, end_position, Vector3f.new(0,1,0)):inverse():to_quat():to_euler()
			end
			box:set_Extent(Vector3f.new(shape_radius, shape_radius, shape_radius))
			box:get_Box():set_RotateAngle(box_rotation)
			shape_ray_method2:call(shape_cast_query, result_obj)
		else
			sphere:set_Radius(shape_radius)
			shape_ray_method:call(nil, sphere, start_position, end_position, 1, filter_info, result_obj)
		end
	else
		ray_query:call("setRay(via.vec3, via.vec3)", start_position, end_position)
		ray_method:call(via_physics_system, ray_query, result_obj)
	end
	local num_contact_pts = result_obj:get_NumContactPoints()
	if num_contact_pts > 0 then
		for i=1, num_contact_pts do
			local new_contactpoint = result_obj:call("getContactPoint(System.UInt32)", i-1)
			local new_collidable = result_obj:call("getContactCollidable(System.UInt32)", i-1)
			local contact_pos = sdk.get_native_field(new_contactpoint, contact_pt_td, "Position")
			local game_object = new_collidable:call("get_GameObject")
			if do_reverse then
				table.insert(result, 1, {game_object, contact_pos})
			else
				table.insert(result, {game_object, contact_pos})
			end
		end
	end
	return result
end

local function is_obscured(position, start_mat, ray_layer, ray_maskbits, leeway)
	start_mat = start_mat or og_cam_mat
	local ray_results = cast_ray(start_mat[3], position, ray_layer or 12, ray_maskbits or 0)
	return ray_results[1] and (start_mat[3] - ray_results[1][2]):length() + (leeway or 0.1) < (start_mat[3] - position):length()
end

local function get_aim_point_on_enemy()
	local ray_results = cast_ray(og_cam_mat[3], og_cam_mat[3] + og_cam_mat[2] * -25.0, 4, 2, 0.01)
	target_enemy.is_rayed = ray_results[1] and (ray_results[1][1] == target_enemy.gameobj)
	return ray_results[1] and ray_results[1][2] or target_enemy.ray_pos
end

local function getC(gameobj, component_name)
	return gameobj:call("getComponent(System.Type)", sdk.typeof(component_name))
end

local function convert_vec_to_json(vec)
	local elem_ct = vec.w and 4 or vec.z and 3 or 2
	return "Vector"..elem_ct.."f.new("..vec.x..", "..vec.y..(vec.z and (", "..vec.z..(vec.w and (", "..vec.w) or "")) or "")..")"
end

local function convert_mat_to_json(matrix)
	local output = "Matrix4x4f.new("
	for r=0, 3 do
		output = output.."Vector4f.new("..matrix[r].x..", "..matrix[r].y..", "..matrix[r].z..", "..matrix[r].w..")"..(r == 3 and ")" or ", ")
	end
	return output
end

local damaping = {
	fn_float = function(source, target, factor)
		return source + (target - source) * factor * timescale_mult * deltatime
	end,
	fn_mat = function(source, target, factor)
		local result = Matrix4x4f.identity()
		local mult = timescale_mult * deltatime
		for i = 0, 3 do
			result[i].x = source[i].x + (target[i].x - source[i].x) * factor * mult
			result[i].y = source[i].y + (target[i].y - source[i].y) * factor * mult
			result[i].z = source[i].z + (target[i].z - source[i].z) * factor * mult
			result[i].w = source[i].w + (target[i].w - source[i].w) * factor * mult
		end
		return result
	end,
}

local damping
damping = {
	timescale_mult = 1, 
	deltatime = 1,
    fn_float = function(source, target, factor)
        return source + (target - source) * factor * damping.timescale_mult * damping.deltatime
    end,
    fn_mat = function(source, target, factor)
        local result = Matrix4x4f.identity()
        local mult = factor * damping.timescale_mult * damping.deltatime
        for i = 0, 3 do
            result[i].x = source[i].x + (target[i].x - source[i].x) * mult
            result[i].y = source[i].y + (target[i].y - source[i].y) * mult
            result[i].z = source[i].z + (target[i].z - source[i].z) * mult
            result[i].w = source[i].w + (target[i].w - source[i].w) * mult
        end
        return result
    end,
	fn_vec = function(source, target, factor)
		local mult = factor * damping.timescale_mult * damping.deltatime
		local x = source.x + (target.x - source.x) * mult
		local y = source.y + (target.y - source.y) * mult
		local z = source.z and source.z + (target.z - source.z) * mult
		local w = source.w and source.w + (target.w - source.w) * mult
		local result = source.w and Vector4f.new(x,y,z,w) or source.z and Vector3f.new(x,y,z) or Vector2f.new(x,y)
		return result
	end,
	fn_quat = function(current, target, factor)
		return current:slerp(target, factor * damping.timescale_mult * damping.deltatime)
	end,
}

local function set_wc(name)
	wc = wc or changed
	if name and imgui.begin_popup_context_item(name) then  
		if imgui.menu_item("Reset Value") then
			ccs[name] = default_ccs[name]
			wc = true
		end
		imgui.end_popup() 
	end
end

local function tooltip(text)
    if imgui.is_item_hovered() then imgui.set_tooltip(text) end
end

local function normalize_single(x, x_min, x_max, r_min, r_max)
	return (r_max - r_min) * ((x - x_min) / (x_max - x_min)) + r_min
end

local function normalize_angle(angle)
    angle = (angle + math.pi) % (2 * math.pi)
    if angle < 0 then angle = angle + (2 * math.pi) end
    return angle - math.pi
end

local function find_index(tbl, value, key)
	for i, item in (tbl[1] and ipairs or pairs)(tbl) do
		if item == value then return i end
	end
end

local function merge_tables(table_a, table_b)
	for key_b, value_b in pairs(table_b) do table_a[key_b] = value_b end
	return table_a
end

--Manually writes a ValueType at a field's position or specific offset
local function write_valuetype(parent_obj, offset_or_field_name, value)
    local offset = tonumber(offset_or_field_name) or parent_obj:get_type_definition():get_field(offset_or_field_name):get_offset_from_base()
    for i=0, (value.type or value:get_type_definition()):get_valuetype_size()-1 do
        parent_obj:write_byte(offset+i, value:read_byte(i))
    end
end

-- Edits the fields of a RE Managed Object using a dictionary of field/method names to values. Use the string "nil" to save values as nil
local function edit_obj(obj, fields)
	local td = obj:get_type_definition()
    for name, value in pairs(fields) do
		local field = td:get_field(name) or td:get_field("<"..name..">k__BackingField")
		name = (field and field:get_name()) or name
		if value == "nil" then value = nil end
		if obj["set"..name] ~= nil then --Methods
			obj:call("set"..name, value) 
        elseif type(value) == "userdata" and value.type and tostring(value.type):find("RETypeDef") then --valuetypes
			write_valuetype(obj, name, value) 
		elseif type(value) == "table" then --All other fields
			if obj[name] and type(obj[name])=="userdata" and obj[name].add_ref then
				obj[name] = edit_obj(obj[name], value)
			end
		elseif field then
			local field_type = field:get_type()
			if type(value) == "string" and field_type:is_value_type() and not field_type:is_a("System.String") then 
				if field_type:get_method(".ctor(System.String)") then
					local new_val = ValueType.new(field_type)
					new_val:call(".ctor(System.String)", value)
					write_valuetype(obj, name, new_val)
				end
			else
				obj[name] = value
			end
		end
    end
	return obj
end

--[[
local noticep = sdk.create_instance(sdk.game_namespace("NoticePoint")):add_ref()
local function check_onscreen(position)
	noticep["<Position>k__BackingField"] = position
	noticep:updatePeriodicPlayer()
	return noticep["<InScreen>k__BackingField"]
end]]

local disp_sz = imgui.get_display_size()
local size = ValueType.new(sdk.find_type_definition("via.Size"))
local world2screen_mth = sdk.find_type_definition("via.math"):get_method("worldPos2ScreenPosDepth(via.vec3, via.mat4, via.mat4, via.Size)")

local function world2screen(world_pos, w, h)
	size.w = w or disp_sz.x
	size.h = h or disp_sz.y
	local wm = cam_joint:get_WorldMatrix()
    local delta = world_pos - wm[3]
    if delta:dot(wm[2] * -1.0) <= 0.0 then return end --behind cam
	
	local fov = camera:get_FOV()
	local proj_mtx = camera:get_ProjectionMatrix()
	proj_mtx[0].x = 1.0 / math.tan(0.5 * (fov-1.0) * 0.0174533)
	proj_mtx[1].y = camera:get_AspectRatio() / math.tan(0.5 * (fov-1.0) * 0.0174533) --some stupid distortion that shouldnt be there and I cant get rid of
	
	return world2screen_mth:call(nil, world_pos, camera:get_ViewMatrix(), proj_mtx, size)
end

local function world_text(text, pos, color)
	local coords = world2screen(pos)
	if coords then draw.text(text, coords.x, coords.y, color) end
end

local function get_onscreen_coords(world_pos, from_mat)
	local pos_2d = world2screen(world_pos)
	return pos_2d and pos_2d.x >= 0 and pos_2d.x <= disp_sz.x and pos_2d.y >= 0 and pos_2d.y <= disp_sz.y and (not from_mat or not is_obscured(world_pos, from_mat)) and pos_2d
end

--Some gameobjects have generic duplicate names like "Cage" and must be found by GUID
--Use gameobject:ToString() to get a gameobject's GUID
local function find_gameobj(parent_name)
	if parent_name then
		if temp.cached_gameobjs[parent_name] and temp.cached_gameobjs[parent_name]:get_Valid() then
			return temp.cached_gameobjs[parent_name]
		end
		local go
		if parent_name:find("-") then
			local guid = ValueType.new(sdk.find_type_definition("System.Guid"))
			guid:call(".ctor(System.String)", parent_name)
			go = scene:call("findGameObject(System.Guid)", guid)
		else
			go = scene:call("findGameObject(System.String)", parent_name)
		end
		temp.cached_gameobjs[parent_name] = go
		return go
	end
end
 
local function get_lasersight()
	local lasersight = scene:call("findGameObject(System.String)", "CCLaserSight")
	if not lasersight then
		local wp02 = scene:call("findGameObject(System.String)", "wp0200")
		local spawned = false
		local pfb = sdk.create_instance("via.Prefab"):add_ref()
		pfb:set_Path((isRE2 and "objectroot" or "escape").."/prefab/character/weapon/wp0200.pfb")
		pfb:set_Standby(true)
		temp.fns.spawn_laser = function()
			spawned = spawned or not not pfb:call("instantiate(via.vec3)", Vector3f.new(0,0,0))
			local wp02_new = scene:call("findGameObject(System.String)", "wp0200")
			if wp02_new ~= wp02 then
				temp.fns.spawn_laser = nil
				local xform = wp02_new:get_Transform():find("LaserSight")
				xform:get_GameObject():set_Name("CCLaserSight")
				xform:set_LocalEulerAngle(Vector3f.new(0,0,0))
				xform:set_Parent(nil)
				wp02_new:destroy(wp02_new)
			end
		end
	end
	return lasersight and getC(lasersight, sdk.game_namespace("LaserSightController"))
end

local autoaim_joints = {
	  [-1] = {precision=0.75, body="Chest", head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={}}, 				 	 --Default
	em4000 = {precision=0.75, body="Chest", head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={}},					 --Dog
	em6000 = {precision=1.00, body="Chest", head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={"L_UpperArm"}},		 --G Adult
	em6100 = {precision=1.00, body="Chest", head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={}},		 			 --G Adult spawn
	em6200 = {precision=0.75, body="Chest", head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={}}, 					 --Tyrant
	em6300 = {precision=0.75, body="Chest", head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={"Heart"}},			 --Super Tyrant
	em7000 = {precision=1.00, body="Chest", head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={"ShoulderEyeball"}},  --G1
	em7100 = {precision=1.00, body="Chest", head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={"ShoulderEyeball", "BackEyeball"}},  --G2
	em7200 = {precision=1.20, body="Chest", head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={"ShoulderEyeball", "ThighEyeball", "ChestEyeball",}}, --G3
	em7300 = {precision=2.00, body="Chest", head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={"Chest_chain"}}, 	 --G4
	em7400 = {precision=2.00, body="COG",   head="Head", l_leg="L_Shin", r_leg="R_Shin", weak={"mainEye"}}, 		 --G5
	em0000 = {precision=0.75, body="spine_2", head="head", l_leg="l_leg_tibia", r_leg="r_leg_tibia", weak={}},		 --Zombie
	em5000 = {precision=0.75, body="spine_2", head="head", l_leg="l_leg_tibia", r_leg="r_leg_tibia", weak={}}, 		 --Ivy has 24 weak points randomly spawned at joints p100-p123
}

autoaim_joints.em4000.get_targetable_joints = function(enemy) --Dog
	return {autoaim_joints.em6000.body, autoaim_joints.em6000.head}
end

autoaim_joints.em6000.get_targetable_joints = function(enemy) --G Adult 
	return {autoaim_joints.em6000.weak[1]}
end

autoaim_joints.em6100.get_targetable_joints = function(enemy) --G Adult spawn 
	return {"COG"}
end

autoaim_joints.em6200.get_targetable_joints = function(enemy) --Tyrant 
	return {autoaim_joints.em6200.body, autoaim_joints.em6200.head}
end

autoaim_joints.em6300.get_targetable_joints = function(enemy) --SuperTyrant 
	return {autoaim_joints.em6300.body, autoaim_joints.em6300.head, autoaim_joints.em6300.weak[1]}
end

autoaim_joints.em7000.get_targetable_joints = function(enemy) --G1 
	return {autoaim_joints.em7000.head, autoaim_joints.em7000.weak[1]}
end

autoaim_joints.em7100.get_targetable_joints = function(enemy) --G2 
	return {autoaim_joints.em7100.weak[1], autoaim_joints.em7100.weak[2]}
end

autoaim_joints.em7200.get_targetable_joints = function(enemy) --G3
	local current_joints = {}
	for i, joint_name in ipairs(enemy.joint_tbl.weak) do
		if not enemy.think.EyeData[i-1].IsEyeClose then
			table.insert(current_joints, joint_name)
		end
	end
	current_joints[1] = current_joints[1] or "Weakpoint_Base"
	return current_joints
end

autoaim_joints.em7300.get_targetable_joints = function(enemy) --G4 
	return {autoaim_joints.em7300.weak[1]}
end

autoaim_joints.em7400.get_targetable_joints = function(enemy) --G5 
	return {autoaim_joints.em7400.weak[1]}
end

autoaim_joints.em5000.get_targetable_joints = function(enemy) --Ivy
	local current_joints = merge_tables({}, autoaim_joints.em5000.all)
	for i, weakpart in pairs(enemy.think["<WeakParts>k__BackingField"].PartsList) do
		if weakpart:get_IsLive() then
			table.insert(current_joints,  "p"..weakpart["<PartsID>k__BackingField"])
		end
	end
	return current_joints
end

for name, tbl in pairs(autoaim_joints) do
	tbl.extremeties = {[tbl.head]=true, [tbl.l_leg]=true, [tbl.r_leg]=true}
	tbl.all = {tbl.body, tbl.head, tbl.l_leg, tbl.r_leg, table.unpack(tbl.weak)}
	tbl.all_no_extremeties = {}
	for i, joint_name in ipairs(tbl.all) do
		if not tbl.extremeties[joint_name] then
			table.insert(tbl.all_no_extremeties, joint_name)
		end
	end
	tbl.get_targetable_joints = tbl.get_targetable_joints or function(enemy)
		return merge_tables({}, tbl.all)
		--return merge_tables({}, (ccs.autoaim_all and tbl.all) or tbl.all_no_extremeties)
	end
end

autoaim_joints.em0100, autoaim_joints.em0200, autoaim_joints.em8000, autoaim_joints.em8100 = autoaim_joints.em0000, autoaim_joints.em0000, autoaim_joints.em0000, autoaim_joints.em0000 --zombies
autoaim_joints.em8200, autoaim_joints.em8300, autoaim_joints.em8400, autoaim_joints.em8500 = autoaim_joints.em0000, autoaim_joints.em0000, autoaim_joints.em0000, autoaim_joints.em0000 --zombies
autoaim_joints.em0300, autoaim_joints.em0400, autoaim_joints.em0500, autoaim_joints.em0600 = autoaim_joints.em0000, autoaim_joints.em0000, autoaim_joints.em0000, autoaim_joints.em0000 --zombies RE3

local Enemy = {
	
	cache = {},

	new = function(self, result_tbl, o)
		o = o or {}
		self.__index = self
		setmetatable(o, self)
		o.gameobj = 		result_tbl[1]
		o.ray_pos = 		result_tbl[2]
		local cache = 		self.cache[o.gameobj] or o
		o.xform = 			cache.xform or o.gameobj:get_Transform()
		o.pos = 			o.xform:get_Position()
		o.is_zombie = 		cache.is_zombie or not not o.xform:getJointByName("spine_0") 
		o.cc = 				cache.cc or getC(o.gameobj, sdk.game_namespace("enemy.EnemyCharacterController"))
		o.mfsm = 			cache.mfsm or getC(o.gameobj, "via.motion.MotionFsm2")
		o.kind = 			cache.kind or kind_ids[getC(o.gameobj, sdk.game_namespace("EnemyController")):get_KindID()]
		o.joint_tbl = 		cache.joint_tbl or autoaim_joints[o.kind] or autoaim_joints[-1]
		o.is_weakpoint_em = cache.is_weakpoint_em or (o.kind=="em5000" or o.kind=="em6000")
		o.hp = 				cache.hp or getC(o.gameobj, sdk.game_namespace("EnemyHitPointController"))
		o.think = 			cache.think or getC(o.gameobj, sdk.game_namespace("enemy.EnemyThinkBehavior"))
		o.is_fast = 		cache.is_fast or o.kind == "em4000" or o.kind == "em2000"
		o.targeted_behind = not is_manual_aim and o.targeted_behind
		o.aim_offset = 		not just_aimed and cache.aim_offset or Vector3f.new(0,0,0)
		
		self.cache[o.gameobj] = cache
		return o
	end,
	
	get_closest_aimed_joint = function(self)
		local joint_tbl = self.joint_tbl
		local dist, closest_joint = 9999
		self.targetable_joints = self.joint_tbl.get_targetable_joints(self)
		self.ray_pos = ccs.autoaim_all and get_aim_point_on_enemy() or self.ray_pos
		for i, joint_name in ipairs(self.targetable_joints) do
			local joint = self.xform:getJointByName(joint_name)
			local joint_dist = (ccs.autoaim_all or not joint_tbl.extremeties[joint_name]) and (joint:get_Position() - self.ray_pos):length()
			if joint_dist and joint_dist < dist then
				dist = joint_dist
				closest_joint = joint_name
			end
		end
		return ((dist <= joint_tbl.precision) and closest_joint) or joint_tbl.body
	end,
	
	get_autoaim_joint = function(self)
		self.ray_pos = not ccs.autoaim_all and get_aim_point_on_enemy() or self.ray_pos
		if self.autoaim_jointname and not was_manual_aim and not self.targeted_behind then 
			return self.xform:getJointByName(self.autoaim_jointname), (self.autoaim_jointname == self.joint_tbl.body)
		end
		self.autoaim_jointname = (self.targeted_behind and self.joint_tbl.body) or self:get_closest_aimed_joint()   --its cheap to get instant lock-on to the head from behind, you should have to aim a little
		self.autoaim_joint = self.xform:getJointByName(self.autoaim_jointname)
		return self.autoaim_joint, (self.autoaim_jointname == self.joint_tbl.body)
	end,
	
	autoaim = function(self)
		if ccs.do_autoaim then 
			local last_joint = self.autoaim_joint
			local joint, is_body_aimed = self:get_autoaim_joint()
			local j_pos = joint:get_Position()
			local do_change_offset
			if not ccs.autoaim_all then --'Normal' mode targeting:
				local aim_pos = og_cam_mat[3] + og_cam_mat[2] * -(og_cam_mat[3] - self.ray_pos):length()
				if self.is_rayed then
					local multip = normalize_single(rstick["<Magnitude>k__BackingField"], 0.2, 1, 0.0, 0.8)
					temp.control_fns.sensitivity_fn = function()
						temp.control_fns.sensitivity_fn = nil
						rstick:call("update(via.vec2, via.vec2)", rstick["<Axis>k__BackingField"] * multip, rstick["<RawAxis>k__BackingField"] * multip)
					end
				end
				self.has_changed_joint = self.has_changed_joint or (joint ~= last_joint)
				self.aim_offset = (just_aimed or self.has_changed_joint or (self.aim_offset:length() >= self.joint_tbl.precision + 1.5)) and Vector3f.new(0,0,0) or self.aim_offset 
				local do_change_offset = not ccs.autoaim_all and (was_manual_aim and not is_manual_aim) and not self.has_changed_joint 
				self.aim_offset = do_change_offset and ((og_cam_mat[3] + og_cam_mat[2] * -(og_cam_mat[3] - self.ray_pos):length()) - j_pos) or self.aim_offset
			end
			if not is_manual_aim and (self.xform:get_Position() - pl_pos):length() > 0.25 then
				local pitch_yaw_roll = lookat_method:call(nil, j_pos + self.aim_offset, og_cam_mat[3], og_cam_mat[1]):to_quat():conjugate():to_euler()
				pl_cam_ctrl["<Yaw>k__BackingField"] = pitch_yaw_roll.y
				self.has_changed_joint = nil
				if not is_body_aimed or ((gtime - just_aimed_time) < 0.25) then
					pl_cam_ctrl["<Pitch>k__BackingField"] = pitch_yaw_roll.x
				end
				self.hp["<NoDamage>k__BackingField"] = ccs.enable_practice
			end
		end
	end,
	
	update = function(self)
		if self.gameobj and sdk.is_managed_object(self.gameobj) and self.gameobj.get_Valid and self.gameobj:get_Valid() then
			self.pos = self.xform:get_Position()
			self.center_pos = Vector3f.new(self.pos.x, self.pos.y + 1.0, self.pos.z)
			self.nodename = self.mfsm:getCurrentNodeName(0)
		else
			self.cache[self.gameobj] = nil
		end
	end,
}

local function check_enemy_rays()
	local final_result, backup, closest_result
	local pitch = pl_cam_ctrl["<Pitch>k__BackingField"]
	local pl_mat = player:get_Transform():getJointByName("head"):get_WorldMatrix()
	
	local function get_results(shape_radius, mat, dist, box_param)
		mat = mat or og_cam_mat
		local found_enemy
		local sign = (mat==og_cam_mat and -1) or 1
		local already_checked = {}
		local matrix_pos = (mat==og_cam_mat and pl_mat[3]) or mat[3]
		local ray_start_pos = (dist and matrix_pos) or (shape_radius and (matrix_pos + mat[2] * (shape_radius + 0.25))) or matrix_pos
		local ray_results = cast_ray(ray_start_pos, mat[3] + mat[2] * (dist or 20.0) * sign, 4, 2, shape_radius, true, box_param) --reverse ray results from nearest to furthest contact points
		unique_ray_results = {}
		for i, result in ipairs(ray_results) do
			if not already_checked[result[1] ] then
				already_checked[result[1] ] = true
				table.insert(unique_ray_results, result)
			end
		end
		table.sort(unique_ray_results, function(a, b) 
			a.dist = a.dist or (a[1]:get_Transform():get_Position() - pl_mat[3]):length()
			b.dist = b.dist or (b[1]:get_Transform():get_Position() - pl_mat[3]):length()
			return a.dist < b.dist
		end)
		for i, result in ipairs(unique_ray_results) do
			local hp = getC(result[1], sdk.game_namespace("EnemyHitPointController"))
			if hp and hp:get_IsLive() then
				local enemy = Enemy:new(result, Enemy.cache[result[1] ])
				enemy.is_ray_on_enemy = not shape_radius or shape_radius <= 0.5 or (enemy.ray_pos - enemy.xform:get_Position()):length() < 0.5
				local em_pos = ((dist) and enemy.xform:get_Position()) or enemy.ray_pos
				enemy.nodename = enemy.mfsm:getCurrentNodeName(0) 
				if dist then em_pos = Vector3f.new(em_pos.x, em_pos.y + 1.0, em_pos.z) end
				if not enemy.nodename:find("DEAD") and not enemy.nodename:find("HANG") and is_obscured(em_pos, pl_mat, 12, 0, 0.0) == nil then
					local is_laying = enemy.is_zombie and enemy.cc and (enemy.cc["<Height>k__BackingField"]["<Current>k__BackingField"] < 0.6)
					found_enemy = (not is_laying or pitch < -0.2 or (not shape_radius and result[1]==last_target_enemy.gameobj)) and enemy
					backup = enemy
					if found_enemy then break end
				end
			end
		end
		return found_enemy
	end
	
	if is_drawing and ccs.do_detect_behind and not was_manual_aim then 
		closest_result = get_results(12.0, nil, 0.1) --giant sphere
		closest_result = closest_result or backup
	end
	
	final_result = get_results() --line ray
	
	if not final_result then 
		final_result = get_results(0.5) --small ray
	end
	
	if not final_result and ccs.autoaim_beam_size > 0.5 then 
		final_result = get_results(ccs.autoaim_beam_size) --big ray
	end
	
	final_result = final_result or backup or closest_result
	
	if closest_result and closest_result ~= final_result and (pl_mat[3] - closest_result.xform:get_Position()):length() * 1.5 < (pl_mat[3] - final_result.xform:get_Position()):length() then
		final_result = closest_result
	end
	
	if final_result and not final_result.is_ray_on_enemy then
		final_result.ray_pos = final_result.xform:getJointByName(final_result.joint_tbl.body):get_Position()
	end
	
	if final_result then
		local delta = final_result.pos - pl_mat[3]
		final_result.targeted_behind = (not was_aiming and final_result.targeted_behind) or (delta:dot(pl_mat[2] * -1.0) > 0.0)
	end
	
	return final_result
end

re.on_pre_application_entry("LateUpdateBehavior", function()
	disp_sz = imgui.get_display_size()
	if temp.do_snap_cams and classic_cam and temp.final_pos and temp.final_rot then
		cam_joint:set_Position(temp.final_pos)
		cam_joint:set_EulerAngle(temp.final_rot)
	end
end)

re.on_application_entry("LateUpdateBehavior", function()
	ran_this_frame = false
	local last_gtime = gtime
	gtime = game_clock:get_ActualPlayingTime() * 0.000001
	local last_player = player
	player = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager")):call("get_CurrentPlayer")
	mfsm2 = player and getC(player, "via.motion.MotionFsm2")
	camera = sdk.get_primary_camera()
	cam_joint = camera and camera:get_GameObject():get_Transform():get_Joints()[0]
	og_cam_mat = cam_joint and cam_joint:get_WorldMatrix()
	is_pad = (input_system["<InputMode>k__BackingField"] == 0)
	local was_paused = is_paused
	is_paused = ((gtime == last_gtime) or not player or game_clock._MeasurePauseSpendingTime or game_clock._MeasureInventorySpendingTime or (player and not player:get_UpdateSelf())) 
		and (sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "get_GlobalSpeed") > 0.1)
	last_qt_time = player and last_qt_time or 0
	spring_aim_timer = player and spring_aim_timer or 0
	
	deltatime = camera:get_GameObject():get_Transform():get_DeltaTime()
	timescale_mult = 1 / sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "get_GlobalSpeed") 
	damping.deltatime, damping.timescale_mult = deltatime, timescale_mult
	
	if temp.real_stick then
		lstick:call("update(via.vec2, via.vec2)", temp.real_stick[1], temp.real_stick[2])
		rstick:call("update(via.vec2, via.vec2)", temp.real_stick[3], temp.real_stick[4])
		temp.real_stick = nil
	end
	
	--local cam_type = getC(camera:get_GameObject(), sdk.game_namespace("camera.CameraSystem")):get_BusyCameraType()
	local was_jacked = is_jacked
	is_jacked = player and mfsm2 and (not mfsm2:getCurrentNodeName(3):find("IDLE") or mfsm2:getCurrentNodeName(0):find("STEP"))
	prev_node_name = node_name
	node_name = mfsm2 and mfsm2:getCurrentNodeName(0)
	
	--[[if is_jacked and is_carry_sherry and is_walking and not temp.is_look_turn then
		is_jacked = false
		node_name = "JOGGING"
	end]]
	
	for name, fn in pairs(temp.fns) do
		fn()
	end
	
	if player and not sound_listeners[1] then
		temp.frozen_mat_dpad = nil
		sound_listeners = {}
		local s_listeners = scene:call("findComponents(System.Type)", sdk.typeof(sdk.game_namespace("SoundListenerController"))):add_ref()
		for i, listener in pairs(s_listeners.get_elements and s_listeners or {})  do
			sound_listeners[i] = listener:get_GameObject():get_Transform()
		end
	end
	
	if player and pl_cam_ctrl and ccs.enabled and not is_paused then
		
		pl_xform = player:get_Transform()
		last_pl_pos = pl_pos
		pl_pos = pl_xform:get_Position()
		pl_center_pos = Vector3f.new(pl_pos.x, pl_pos.y+1, pl_pos.z) --not hips because thats bouncy
		
		local location = locations[em["<LastPlayerStayLocationID>k__BackingField"]]
		local map = maps[em["<LastPlayerStaySceneID>k__BackingField"]]
		local area = areas[em["<LastPlayerStaySceneArea>k__BackingField"]]
		local area_changed = current_loc_string ~= location.."."..map.."."..area
		current_loc_string = location.."."..map.."."..area
		
		local motion = getC(player, "via.motion.Motion")
		
		pl_ctrl = getC(player, sdk.game_namespace("survivor.player.PlayerController"))
		pl_condition = getC(player, sdk.game_namespace("survivor.SurvivorCondition"))
		
		local rstick_x_mag = math.abs(rstick["<Axis>k__BackingField"].x)
		local rstick_y_mag = math.abs(rstick["<Axis>k__BackingField"].y)
		local lstick_x_mag = math.abs(lstick["<Axis>k__BackingField"].x)
		local lstick_y_mag = math.abs(lstick["<Axis>k__BackingField"].y)
		is_strafe_button = hk.check_hotkey("Strafe / Classic Aim", true)
		
		local was_aiming = is_aiming
		is_aiming =  (pl_cam_ctrl["<NowKind>k__BackingField"] == 3) and not is_sherry_crouch
		just_aimed = is_aiming and not was_aiming
		just_aimed_time = just_aimed and gtime or just_aimed_time
		is_drawing = is_aiming and (just_aimed or node_name:find("START") or ((gtime - last_qt_time) < 0.5))
		last_qt_time = (node_name:find("QUICK_TURN") and gtime) or last_qt_time
		is_shooting = is_aiming and (node_name:find("SHOT") or mfsm2:getCurrentNodeName(4):find("RECOIL"))
		local is_reload = is_aiming and mfsm2:getCurrentNodeName(4):find("RELOAD")
		was_manual_aim = is_manual_aim
		is_manual_aim = ((is_pad and ((rstick_x_mag > 0.5) or rstick_y_mag > 0.5)) or (not is_pad and (math.abs(mouse:get_DeltaPosition().x) > 3.0) or math.abs(mouse:get_DeltaPosition().y) > 3.0))
		temp.parent_obj = classic_cam and temp.parent_obj
		if not ccs.freeze_angle_toggle then
			temp.freeze_angle_on = hk.check_hotkey("Freeze Angle", true)
		elseif hk.check_hotkey("Freeze Angle") then
			temp.freeze_angle_on =  not temp.freeze_angle_on
		end
		
		if autoaim_enemy and (not (is_drawing or (ccs.lock_on_type==2 and is_aiming and ((gtime - last_qt_time) > 0.25))) or (temp.is_tank_turn and lstick_x_mag > 0.9) or (was_manual_aim and not is_manual_aim and lstick_x_mag < 0.5) or autoaim_enemy.mfsm:getCurrentNodeName(0):find("DEAD")) then
			autoaim_enemy = nil --reset autoaim enemy under these conditions
		end
		
		local was_jogging, was_walking = is_jogging, is_walking
		is_jogging = node_name:find("JOG")
		is_walking = node_name:find("GAZING")
		is_ada_hack_gun = is_aiming and (getC(player, sdk.game_namespace("survivor.Equipment"))["<EquipType>k__BackingField"] == 41)
		is_sherry_crouch = (player:get_Name() == "pl3000" and node_name:find("HOLD"))
		
		--slow down funny jogging animation
		if last_pl_pos and ccs.fix_jog_anim then
			local mlayer = motion:getLayer(0)
			local speed = mlayer:get_Speed()
			if is_jogging then
				local mname = mlayer:get_HighestWeightMotionNode():get_MotionName()
				local on_stairs = getC(player, sdk.game_namespace("GroundFixer")):get_OnStairs()
				local curr_hp = getC(player, sdk.game_namespace("HitPointController"))["<CurrentHitPoint>k__BackingField"]
				pl_speed = node_name == "JOGGING" and curr_hp > 800 and not (on_stairs or in_water) and (mname:find("pl0") and 0.80 or mname:find("pl1") and 0.85) or 1.0 --I literally cant find how to detect when in the water, its like a secret
				mlayer:set_Speed(pl_speed)
			end
			if speed ~= 1.0 then
				local further_pos = Vector3f.new(last_pl_pos.x, pl_pos.y, last_pl_pos.z):lerp(pl_pos, (1.0 + (1 - speed)))
				pl_xform:set_Position(further_pos)
				if node_name ~= "JOGGING" then mlayer:set_Speed(1.0) end
			end
		end
		
		local last_classic_cam = classic_cam
		
		if area_changed then
			classic_cam = nil
			cams_list[current_loc_string] = json.load_file("ClassicCams\\"..reframework:get_game_name().."\\"..current_loc_string..".json")
			cams = cams_list[current_loc_string]
			temp.cached_gameobjs = {}
		end
		
		local wall_checker = getC(player, sdk.game_namespace("survivor.SurvivorWallHitChecker"))
		wall_checker["<PermitJog>k__BackingField"] = true
		wall_checker["<PermitWalk>k__BackingField"] = true
		
		if cams and not is_ada_hack_gun then
			
			local dist = 9999
			if temp.do_use_colliders and (not classic_cam or (not temp.freeze_angle_on and ((os.clock() - temp.last_cam_change_time > ccs.cam_switch_delay) or not player_screen_pos or not (is_jogging or is_walking))))  then
				for name, cam_tbl in pairs(cams) do
					if cam_tbl.mat then
						local cmat = load("return "..cam_tbl.mat)()
						local p_obj = find_gameobj(cam_tbl.parent_name)
						local p_pos = p_obj and p_obj:get_Transform():get_Position()
						for i, collider in ipairs(cam_tbl.colliders or {}) do
							local cpos = load("return "..collider.col_pos)()
							cpos = (p_pos and (cpos + p_pos)) or cpos
							local this_dist = (cpos - pl_pos):length()
							if this_dist < dist and this_dist < collider.radius then
								dist = this_dist
								classic_cam = cam_tbl
								temp.radius = collider.radius
								temp.cpos = cpos
								temp.ray_pos = temp.cpos
								temp.cmat = cmat
								temp.exist_cam_idx = find_index(cams_list[current_loc_string].names, classic_cam.name)
								temp.cam_name_txt = classic_cam.name
							end
						end
					end
				end
			end
			temp.last_cam_change_time = (classic_cam ~= last_classic_cam and os.clock()) or temp.last_cam_change_time or os.clock()
			
			is_grappled = (getC(player, sdk.game_namespace("JackDominator"))["<JackOwner>k__BackingField"]["<Symbol>k__BackingField"] == 4)
			local did_skip = is_disabled_bite or is_disabled_aiming
			is_disabled_bite = ccs.disable_during_bites and is_grappled
			is_disabled_aiming = ccs.disable_during_aim and is_aiming
			
			--IF IN CLASSIC CAMERA MODE:
			if classic_cam and pl_cam_ctrl and temp.cmat then
				
				classic_cam.data = classic_cam.data or {}
				ran_this_frame = true
				if ccs.no_vignette then
					getC(camera:get_GameObject(), "via.render.ToneMapping"):call("setVignetting", 2)
				end
				local can_autoaim = (ccs.lock_on_type==2 and is_aiming) or is_drawing
				
				lookat_enemy = ((gtime - last_qt_time) > 0.25) and check_enemy_rays() or (last_target_enemy.targeted and last_target_enemy)
				
				if ccs.do_autoaim and can_autoaim then
					autoaim_enemy = autoaim_enemy or lookat_enemy
				end
				target_enemy = autoaim_enemy or lookat_enemy
				
				local was_targeted = last_target_enemy.targeted
				last_target_enemy = ((is_drawing or (was_targeted and hk.check_hotkey("Turn Camera To Enemy"))) and target_enemy) or last_target_enemy
				
				if last_target_enemy.xform and ccs.hotkeys["Turn Camera To Enemy"] ~= "[Not Bound]" then
					last_target_enemy:update()
					last_target_enemy.visible = (is_obscured(last_target_enemy.center_pos, fixed_cam_mat, 12, 0, 0.0) == nil)
					if hk.check_hotkey("Turn Camera To Enemy") then
						last_target_enemy.alive = last_target_enemy.hp:get_IsLive() and not last_target_enemy.nodename:find("DEAD")
						last_target_enemy.targeted = last_target_enemy.visible and last_target_enemy.alive and not last_target_enemy.targeted
					else
						last_target_enemy.targeted = was_targeted
					end
					last_target_enemy.last_targeted_time = (last_target_enemy.targeted and last_target_enemy.visible and gtime) or last_target_enemy.last_targeted_time or gtime
					last_target_enemy.targeted = (is_aiming and (gtime - last_target_enemy.last_targeted_time < 3.0)) and last_target_enemy.targeted
					if last_classic_cam ~= classic_cam then
						last_target_enemy.last_targeted_time = 0.0
					end
				end
				
				local is_disable_autoaim = ((is_pad and input_system:get_AnalogL() <= 0.835) or hk.check_hotkey("Disable Autoaim", true))
				if autoaim_enemy and not is_disabled_aiming and not temp.is_tank_turn and not is_disable_autoaim and (ccs.hotkeys["Autoaim Button"] == "[Not Bound]" or hk.check_hotkey("Autoaim Button", true)) then
					autoaim_enemy:autoaim()
				end
				
				--Snap camera to point:
				if temp.do_snap_cams and not is_disabled_bite and not is_disabled_aiming then
					
					local do_follow = classic_cam.follow_player or ccs.always_follow_player
					
					temp.parent_obj = find_gameobj(classic_cam.parent_name)
					local parent_pos = temp.parent_obj and temp.parent_obj:get_Transform():get_Position()
					temp.final_pos = parent_pos and (parent_pos + temp.cmat[3]) or temp.cmat[3]
					temp.cpos = (parent_pos and parent_pos + load("return " .. classic_cam.colliders[classic_cam.col_idx].col_pos)()) or temp.cpos
					local pl_cam_joint = pl_cam_ctrl:get_GameObject():get_Transform():get_Joints()[0]
					pl_cam_joint:set_Position(temp.final_pos)
					pl_cam_joint:set_Rotation(temp.cmat:to_quat())
					cam_joint:set_Position(temp.final_pos)
					cam_joint:set_Rotation(temp.cmat:to_quat())
					camera:set_FOV(classic_cam.fov)
					
					--Remove game yaw influence
					if pl_cam_ctrl["<ForceTwirlerParam>k__BackingField"] then 
						pl_cam_ctrl["<ForceTwirlerParam>k__BackingField"].Time = 0.001
					end
					
					--Correct audio position
					if sound_listeners[1] and fixed_cam_mat and not is_paused then
						for i, listener in ipairs(sound_listeners) do
							if listener and listener.set_Rotation then
								listener:set_Rotation(fixed_cam_mat:to_quat())
								listener:set_Position(fixed_cam_mat[3])
							end
						end
					end
					
					--Set player aiming pitch to be flat like the original games:
					local mag = rstick_x_mag; mag = rstick_y_mag > mag and rstick_y_mag or mag
					spring_aim_timer = ((should_spring_aim or mag >= 0.5 or is_aiming) and gtime) or spring_aim_timer
					local should_spring_aim = not is_jacked and (is_jogging or (was_aiming and not is_aiming) or (((just_aimed and mag <= 0.5) or (gtime - spring_aim_timer > 3.0)) and not lookat_enemy))
					local weighted_mag = should_spring_aim and mag or 1.0
					
					pl_cam_ctrl["<PitchMin>k__BackingField"]["<Current>k__BackingField"] = -1.046 * weighted_mag --+   0.152
					pl_cam_ctrl["<PitchMax>k__BackingField"]["<Current>k__BackingField"] =  1.204 * weighted_mag --+  -0.173
					
					if ccs.follow_cam_randomize and not classic_cam.data.rand and not classic_cam.follow_player then
						classic_cam.data.rand = {follow_player = true}
						classic_cam.data.rand.follow_twist = ccs.follow_cam_do_twist and (classic_cam.follow_twist or math.random(0,1)==1)
						classic_cam.data.rand.follow_no_pitch = ccs.follow_cam_do_pitch and (classic_cam.follow_no_pitch or math.random(0,1)==1)
						classic_cam.data.rand.follow_no_yaw = ccs.follow_cam_do_yaw and (classic_cam.follow_no_yaw or math.random(0,1)==1)
						classic_cam.data.rand.dead_zone_sz = classic_cam.dead_zone_sz or math.random(0, 50+math.random(0, math.floor(50 * ccs.follow_cam_edge_limit)))*0.01
						classic_cam.data.rand.follow_loose = ccs.follow_cam_do_edges and (classic_cam.follow_loose or math.random(0,1)==1)
					end
					local cc_data = ccs.follow_cam_randomize and classic_cam.data.rand or classic_cam 
					 
					--Manage follow cam
					local allow_twist = ccs.follow_cam_do_twist or cc_data.follow_twist
					local lookat_mat = lookat_method:call(nil, pl_center_pos, temp.final_pos, allow_twist and temp.cmat[1] or Vector3f.new(0,1,0)):inverse()
					local lookat_eulers = lookat_mat:to_quat():to_euler()
					temp.last_lookat_eulers = ((os.clock() - temp.last_cam_change_time > ccs.cam_rel_delay_time) and lookat_eulers) or temp.last_lookat_eulers or lookat_eulers --stored lookat eulers from previous camera, which is still used for the first x seconds after a camera change
					local bend_enemy_center_pos = is_aiming and last_target_enemy.targeted and last_target_enemy.center_pos
					local is_twisty = (temp.cmat:to_quat():to_euler().z > 0.01)
					
					if fixed_cam_mat and (do_follow or bend_enemy_center_pos or hk.check_hotkey("Turn Camera", true)) and (not is_twisty or classic_cam.follow_player) then
						local bend_lookat_mat = bend_enemy_center_pos and lookat_method:call(nil, bend_enemy_center_pos, temp.final_pos, ccs.follow_cam_do_twist and temp.cmat[1] or Vector3f.new(0,1,0)):inverse()
						local interp_mat = bend_lookat_mat or lookat_mat
						local do_transition_cam = ((last_classic_cam ~= classic_cam) and (fixed_cam_mat[3] - temp.cmat[3]):length() > 0.001) or (did_skip and not (is_disabled_aiming or is_disabled_bite))
						local no_yaw = not ccs.follow_cam_do_pitch or cc_data.follow_no_pitch
						local no_pitch = not ccs.follow_cam_do_yaw or cc_data.follow_no_yaw
						
						if hk.check_hotkey("Turn Camera", true)  then
							local mouse_multip = is_pad and 1.0 or 0.5
							local mat = ((ccs.turn_angle_do_bend or do_transition_cam) and (do_follow and interp_mat or temp.cmat)) or fixed_cam_mat
							local eul = mat:to_quat():to_euler()
							eul.x = eul.x + rstick["<Axis>k__BackingField"].y * rstick["<Magnitude>k__BackingField"] * mouse_multip * timescale_mult * deltatime
							eul.y = eul.y - rstick["<Axis>k__BackingField"].x * rstick["<Magnitude>k__BackingField"] * mouse_multip * timescale_mult * deltatime
							eul.z = ccs.follow_cam_do_twist and eul.z or 0
							interp_mat = make_euler_method:call(nil, eul, 0)
						else
							local pl_2d_pos = ((ccs.follow_cam_do_edges and not cc_data.follow_player) or cc_data.follow_loose) and not bend_enemy_center_pos and world2screen(pl_pos)
							if pl_2d_pos then
								local edge_limit = (cc_data.follow_loose and (cc_data.dead_zone_sz or 0.0)) or ccs.follow_cam_edge_limit
								local ratio_x = no_pitch and 0 or math.abs((pl_2d_pos.x / disp_sz.x) - 0.5) * 2 - edge_limit
								local ratio_y = no_yaw and 0 or math.abs((pl_2d_pos.y / disp_sz.y) - 0.5) * 2 - edge_limit
								if ratio_x < 0 then ratio_x = 0 end; if ratio_x > 1 then ratio_x = 1 end
								if ratio_y < 0 then ratio_y = 0 end; if ratio_y > 1 then ratio_y = 1 end
								local ratio = (ratio_x + ratio_y) / 2
								--local ratio = ((no_pitch and 0 or ratio_x) + (no_yaw and 0 or ratio_y)) / 2
								ratio = (edge_limit==0.0 and normalize_single(ratio, -0.2, 1, 0, 1)) or ratio
								interp_mat = temp.cmat:to_quat():slerp(lookat_mat:to_quat(), ratio):to_mat4()
							end
						end
						
						local factor =  ccs.follow_cam_damp_rate * 0.33
						if  was_paused or do_transition_cam or hk.chk_trig("Turn Camera") then -- or (bend_enemy_center_pos and not ccs.always_follow_player and hk.check_hotkey("Turn Camera To Enemy"))
							damping.cam = interp_mat:to_quat()
						else
							damping.cam = damping.fn_quat(fixed_cam_mat:to_quat(), interp_mat:to_quat(), factor)
						end
						damping.pos = damping.fn_vec(pl_xform:get_Position(), temp.final_pos, factor)
						
						if no_yaw or no_pitch then
							local eulers, cam_eulers = damping.cam:to_euler(), cam_joint:get_EulerAngle()
							cam_joint:set_EulerAngle(Vector3f.new((no_pitch and eulers.x or cam_eulers.x), (no_yaw and eulers.y or cam_eulers.y), eulers.z))
						else
							cam_joint:set_Rotation(damping.cam)
						end
					end
					temp.final_rot = cam_joint:get_EulerAngle()
					
					--Manage SweetLights
					local cam_xform = camera:get_GameObject():get_Transform()
					local sweetlight = cam_xform:find("SweetLight")
					local e_sweetlight = cam_xform:find("EnvironmentSweetLight")
					if sweetlight then 
						local do_override = not ccs.no_pl_light_overrides and classic_cam.override_pl_light
						local sw_ctrl = do_override and getC(sweetlight:get_GameObject(), sdk.game_namespace("SweetLightController"))
						if sw_ctrl and not sw_ctrl.ProjectionSpotLightEnable then
							sw_ctrl.ProjectionSpotLightEnable = true
						end
						if sweetlight_def_intensity.pl then 
							local multip = (do_override and classic_cam.pl_light_str) or ccs.player_light_strength * 0.01
							getC(sweetlight:get_GameObject(), "via.render.ProjectionSpotLight"):set_Intensity((sweetlight_def_intensity.pl) * multip)
						end
						sweetlight:set_EulerAngle(lookat_eulers)	
						sweetlight:set_Position((temp.final_pos + (lookat_mat:to_quat():to_mat4()[2] * -((pl_center_pos - temp.final_pos):length() - 2.5))))
					end
					
					if e_sweetlight then 
						if sweetlight_def_intensity.env then 
							local multip = (not ccs.no_cam_light_overrides and classic_cam.override_light and classic_cam.light_str) or ccs.env_light_strength * 0.01
							getC(e_sweetlight:get_GameObject(), "via.render.SpotLight"):set_Intensity(sweetlight_def_intensity.env * multip)
						end
						e_sweetlight:set_EulerAngle(temp.final_rot)
						e_sweetlight:set_Position(temp.final_pos)
					end
					
					--CONTROLS--------------
					local lstick_mag = lstick["<Magnitude>k__BackingField"]
					
					if ccs.run_type > 2 and (is_walking or is_jogging) and not (was_walking or was_jogging) then
						pl_cam_ctrl["<Yaw>k__BackingField"] = pl_xform:get_EulerAngle().y + math.pi --align on start
					end
					
					--Manage analog stick jogging:
					if not is_jacked and not temp.is_move_dpad and not (is_pad and ccs.use_dpad_controls and ccs.do_dpad_swap) and ((ccs.run_type ~= 1) or ccs.do_run_turnaround) then
						
						if (prev_node_name ~= node_name) and (node_name:sub(1,9)=="JOG_START" or node_name=="JOG_TURN"  or (node_name:sub(1,7)=="JOGGING" and prev_node_name:find("WALK"))) or temp.do_restart_fix_jog  then
							
							local did_set = false
							local axis = lstick["<Axis>k__BackingField"]
							local r_start = lstick["<Angle>k__BackingField"] + math.pi
							local is_rel = (ccs.run_type==2 or ccs.run_type==4)
							local do_run_turnaround = ccs.do_run_turnaround and not (ccs.run_type==1 or ccs.run_type==3 or ccs.run_type==5) and not temp.qt_dir
							temp.is_run_turnaround = do_run_turnaround and node_name=="JOG_TURN"
							
							--Correct the player cam-relative stick inputs to match the character's direction:
							if ccs.run_type == 5 and not temp.do_restart_fix_jog then -- and not temp.is_run_turnaround then
								pl_cam_ctrl["<Yaw>k__BackingField"] = pl_xform:get_EulerAngle().y + (math.pi - (math.atan(math.floor(axis.y * 10 + 0.5)/10,  math.floor(axis.x * 10 + 0.5)/10) - math.pi / 2))
							elseif not temp.is_run_turnaround then
								if ccs.run_type == 4 or (ccs.run_type == 2 and not is_pad) then
									pl_cam_ctrl["<Yaw>k__BackingField"] = temp.qt_dir or temp.last_lookat_eulers.y
								elseif ccs.run_type == 2 then
									temp.relative_stick_dir = temp.qt_dir or temp.last_lookat_eulers.y
								end
							end
							temp.do_restart_fix_jog = nil
							
							temp.fns.fix_jog = function()
								temp.fns.fix_jog = not is_jacked and player and temp.fns.fix_jog or nil
								
								if temp.fns.fix_jog and not is_paused then
									--Control direction while running:
									local cr_l_axis = lstick["<Axis>k__BackingField"]
									local multip = ((ccs.run_type == 5 or ccs.run_type == 4 or (ccs.run_type == 3 and axis.y > -0.5)) and 1) or -1
									temp.use_old_rel_run_style = ccs.run_type == 2 and temp.use_old_rel_run_style or not is_pad or rstick["<Magnitude>k__BackingField"] > 0.5
									
									if ccs.run_type == 4 then --measure tank-turn stick directions relative to stick direction at run start:
										local r2 = lstick["<Angle>k__BackingField"] + math.pi * multip
										local radius = math.abs(lstick["<Magnitude>k__BackingField"])
										cr_l_axis = Vector2f.new(radius * math.sin(r_start - r2), radius * math.cos(r_start - r2))
									end
									
									if ((node_name ~= "JOG_END.START" or prev_node_name=="JOGGING") and ((node_name ~= "JOG_TURN" or not temp.is_run_turnaround) or (ccs.run_type == 5))) and not temp.fns.running_qturn_fn then
										if ccs.run_type == 5 and node_name == "JOG_TURN" and prev_node_name ~= "JOG_TURN" then
											pl_cam_ctrl["<Yaw>k__BackingField"] = pl_xform:get_EulerAngle().y + ((axis.y > -0.33) and math.pi or 0)  --force forward pivot
										elseif ccs.run_type >= 3 and not is_walking then --and not temp.is_run_turnaround then 
											local axis_x = (math.abs(cr_l_axis.x) ~= 1.0 and cr_l_axis.y > 0) and normalize_single(cr_l_axis.x, -1, 1, -ccs.tank_sensitivity, ccs.tank_sensitivity) or cr_l_axis.x
											local yaw_sub = axis_x * 0.045 * multip * ccs.turn_speed_jog * timescale_mult * deltatime
											if yaw_sub > 0.04 then yaw_sub = 0.04 end; if yaw_sub < -0.04 then yaw_sub = -0.04 end
											local new_yaw = pl_cam_ctrl["<Yaw>k__BackingField"] - yaw_sub --calculate tank turn
											if math.abs(pl_cam_ctrl["<Yaw>k__BackingField"] - new_yaw) > 0.005 then
												pl_cam_ctrl["<Yaw>k__BackingField"] = new_yaw --only change yaw if its a non-miniscule change
											end
										elseif ccs.run_type == 2 and not temp.is_run_turnaround then
											pl_cam_ctrl["<Yaw>k__BackingField"] = (temp.use_old_rel_run_style and cam_joint:get_EulerAngle().y) or (pl_xform:get_EulerAngle().y + math.pi) --cam relative
										end
										
										if not did_set and not temp.qt_dir and (ccs.run_type == 1 or node_name ~= "JOG_TURN" or gtime - last_qt_time > 0.25) then 
											did_set = not not set_node_method:call(mfsm2:getLayer(0), node_name, setn, interper) --reset action once
										end
									end
									
									--Open doors that the player "backs" into:
									pcall(function()
										local door = getC(player, sdk.game_namespace("TerrainAnalyzer")).HitResultCache.GameObject
										door = door and door:get_Name():find("CollidersMoving") and getC(door:get_Transform():get_Parent():get_GameObject(), sdk.game_namespace("gimmick.action.GimmickDoorBase")) 
										if door and not door:get_IsLocked() and not door:get_IsOpened() and (not door._SaveData or door._SaveData.HasOpened) --some doors should be unopenable but are active and not locked
										and (Vector3f.new(pl_pos.x, pl_pos.y+1.0, pl_pos.z) - door:getCommonCenterPos()):length() < 0.5 and not get_onscreen_coords(door:getCommonCenterPos()) then
											door:requestOpenByLever(door:calcSide(pl_pos))
										end
									end)
									
									--Make the player face the direction they were when they stopped running (or turned, in some cases):
									if (ccs.run_type == 2 and temp.is_run_turnaround) or node_name == "JOG_END.START" or (not node_name:find("JOG") and node_name ~= "GAZING_WALKING.FRONT") then
										pl_cam_ctrl["<Yaw>k__BackingField"] = pl_xform:get_EulerAngle().y + math.pi
										pl_ctrl["<CharAngle>k__BackingField"]["<Current>k__BackingField"] = pl_ctrl["<MoveAngle>k__BackingField"]["<Current>k__BackingField"]
										temp.qt_dir, temp.use_old_rel_run_style, temp.is_run_turnaround = nil
										
										temp.fns.fix_jog = (node_name ~= "JOG_END.START") and function()
											temp.fns.fix_jog = nil
											if is_jacked then return end
											mfsm2:restartTree()
											set_node_method:call(mfsm2:getLayer(0), node_name, setn, interper)
										end or nil
									end
								end
							end or nil
						end
					end
					
					if is_pad and ccs.do_remake_run and not temp.is_move_dpad then 
						if not is_jogging then
							getC(player, sdk.game_namespace("survivor.SurvivorUserVariablesUpdater")):set_Jog(lstick_mag >= 0.99)
						elseif ccs.do_remake_run_reset and lstick_mag < 0.99 and (node_name == "JOGGING" or node_name == "GAZING_WALKING") then
							pl_cam_ctrl["<Yaw>k__BackingField"] = lstick["<Angle>k__BackingField"]
							pl_ctrl["<CharAngle>k__BackingField"]["<Current>k__BackingField"] = lstick["<Angle>k__BackingField"] + math.pi
						end
					end
					
					--Cam relative walking (also Sherry crouch):
					if node_name ~= prev_node_name and (is_sherry_crouch or ccs.walk_type == 2) and not is_jacked and not temp.is_move_dpad and node_name:find("WALK") and lstick_mag > 0 and (classic_cam == last_classic_cam) then
						local start_node_name = node_name
						local start_time = gtime
						local start_yaw = temp.last_lookat_eulers.y
						
						temp.control_fns.fix_rel_walk_dir_fn = function()
							temp.control_fns.fix_rel_walk_dir_fn = player and temp.control_fns.fix_rel_walk_dir_fn
							if not is_paused then
								if not temp.is_move_dpad and node_name == start_node_name then
									local cam_dir = lookat_eulers.y
									if is_aiming or ccs.cam_rel_walk_do_strafe or is_strafe_button then
										pl_ctrl["<MoveAngle>k__BackingField"]["<Current>k__BackingField"] = cam_dir + pl_ctrl:get_LocalMoveAngleTarget() + math.pi
									elseif not temp.is_look_turn then
										local axis, angle = lstick["<Axis>k__BackingField"], lstick["<Angle>k__BackingField"]
										local yaw = normalize_angle(cam_dir + angle)
										pl_cam_ctrl["<Yaw>k__BackingField"] = yaw
										local new_axis = Vector2f.new(axis.x * math.cos(-angle) - axis.y * math.sin(-angle), axis.x * math.sin(-angle) + axis.y * math.cos(-angle))
										lstick:call("update(via.vec2, via.vec2)", new_axis, new_axis)
									end
								else
									temp.control_fns.fix_rel_walk_dir_fn = nil
									pl_cam_ctrl["<Yaw>k__BackingField"] = pl_xform:get_EulerAngle().y + math.pi
									pl_ctrl["<MoveAngle>k__BackingField"]["<Current>k__BackingField"] = pl_cam_ctrl["<Yaw>k__BackingField"]
								end
							end
						end
					end
					
					--Make the player face the direction they were when they stopped running (or turned, in some cases):
					if node_name == "JOG_END.START" or (node_name == "JOG_TURN" and prev_node_name == "JOGGING") or node_name == "STAND.WALK_END" or (was_jacked and not is_jacked) then
						pl_cam_ctrl["<Yaw>k__BackingField"] = player:get_Transform():get_EulerAngle().y + math.pi
					end
					
					--Make the player look down while dropping off jumps (to see FloatIcon)
					if is_jacked and getC(player, sdk.game_namespace("JackDominator"))["<JackOwner>k__BackingField"]:get_GimmickKind() == 11 then
						pl_cam_ctrl["<Pitch>k__BackingField"] = -1.046
					end
					
					--Make gamepad QuickTurn work based on player direction relative to camera:
					if is_pad and not (temp.is_tank_turn or temp.is_move_dpad) and (node_name=="QUICK_TURN" or (ccs.walk_type == 2 and ccs.cam_rel_walk_do_strafe and node_name:find("WALKING") and node_name:find("BACK"))) and (hk.pad:get_Button() | 262272 == hk.pad:get_Button())  then
					--	set_node_method:call(mfsm2:getLayer(0), "QUICK_TURN_EX", setn, interper)
					end
					
					--_G.cc_globals = {temp=temp, classic_cam=classic_cam, fixed_cam_mat=fixed_cam_mat, og_cam_mat=og_cam_mat, node_name=node_name, player=player, scene=scene, 
					--	pl_center_pos=pl_center_pos, gtime=gtime, ticks=ticks, mfsm2=mfsm2, camera=camera, cam_joint=cam_joint, ccs=ccs, is_obscured=is_obscured, find_gameobj=find_gameobj, cast_ray=cast_ray,}
					--ble = classic_cam
					
					if classic_cam.do_custom_func and not classic_cam.data.cust_fn_stopped then
						_G.temp, _G.classic_cam, _G.fixed_cam_mat, _G.og_cam_mat, _G.node_name, _G.player, _G.scene, _G.pl_center_pos, _G.gtime, _G.ticks, _G.mfsm2, _G.camera, _G.cam_joint, _G.ccs, _G.is_obscured, _G.find_gameobj, _G.cast_ray 
							= temp, classic_cam, fixed_cam_mat, og_cam_mat, node_name, player, scene, pl_center_pos, gtime, ticks, mfsm2, camera, cam_joint, ccs, is_obscured, find_gameobj, cast_ray
						_G.Stop = function()
							classic_cam.data.cust_fn_stopped = true
						end
						try, output = pcall(load(classic_cam.custom_func_code))
						temp.custom_func_error = not try and "Error at time "..os.clock()..":\n	"..output or nil
						_G.temp, _G.classic_cam, _G.fixed_cam_mat, _G.og_cam_mat, _G.node_name, _G.player, _G.scene, _G.pl_center_pos, _G.gtime, _G.ticks, _G.mfsm2, _G.camera, _G.cam_joint, _G.ccs, _G.is_obscured, _G.find_gameobj, _G.cast_ray, _G.Stop  = nil
					end
				end
			end
		end
		
		if ccs.enable_practice then
			local hp = getC(player, sdk.game_namespace("HitPointController"))
			hp:set_Invincible(not ccs.no_damage)
			hp:set_NoDamage(ccs.no_damage)
		end
		
		prev_yaw = pl_cam_ctrl["<Yaw>k__BackingField"]
	end
	
	if player and not is_paused then
		lasersight = get_lasersight()
		local equipment = getC(player, sdk.game_namespace("survivor.Equipment"))
		local equip_wp = equipment["<EquipWeapon>k__BackingField"]
		local light_pos = equip_wp and equip_wp["<LaserSightTipPosition>k__BackingField"]
		local cam_mat = light_pos and cam_joint:get_WorldMatrix()
		is_lasersight_visible = cam_mat and (not classic_cam or (not is_obscured(light_pos, cam_mat, 4, 6) and not is_obscured(light_pos, cam_mat, 12, 0, 0.33)))
		
		if lasersight and equip_wp and equip_wp:get_type_definition():is_a(sdk.game_namespace("implement.Gun")) and (mfsm2:getCurrentNodeName(0):find("HOLD") or wc) and equipment["<EquipType>k__BackingField"] ~= 41 then 
			lasersight.WeaponPartsBits = ccs.use_lasersight and 0 or 9999
			if ccs.use_lasersight then
				local equip_wp_xform = equip_wp and equip_wp:get_GameObject():get_Transform()
				local og_lasersight = equip_wp_xform:find("LaserSight")
				if og_lasersight then og_lasersight:get_GameObject():set_DrawSelf(false) end
				if (wc or not equip_wp_xform:find("CCLaserSight")) then
					local xform = lasersight:get_GameObject():get_Transform()
					lasersight.SightEmitJointName = equip_wp["<MuzzleJointName>k__BackingField"]
					lasersight:set_Owner(equip_wp)
					xform:set_Parent(equip_wp_xform)
					xform:set_ParentJoint(lasersight.SightEmitJointName)
					xform:set_LocalPosition(Vector3f.new(0,-0.05,0))
					xform:set_LocalEulerAngle(Vector3f.new(0.038,-0.030,-0.043))
					equipment:get_LookAt().WorkList[0]._UserData.Damping.PositionLerpSpeedSetting.DampingTime = 0.01
					lasersight.SightLineVisibleCurve._BaseValue = ccs.laser_intensity
					local col = ccs.laser_color
					lasersight:write_dword(184, col)
					lasersight.IsChangeColor = true
					temp.fns.change_lasercolor_fn = function()
						temp.fns.change_lasercolor_fn = nil
						lasersight["<LineColorMaterialParam>k__BackingField"]:set_ValueF4(Vector4f.new((col & 0x000000FF) / 255, ((col & 0x0000FF00) >> 8) / 255, ((col & 0x00FF0000) >> 16) / 255, ((col & 0xFF000000) >> 24) / 255))
					end
				end
				lasersight:lateUpdate()
				lasersight["<Light>k__BackingField"]:get_Transform():set_Position(light_pos)
				lasersight["<Light>k__BackingField"]:set_DrawSelf(is_lasersight_visible) -- and not is_obscured(light_pos, cam_mat, 4, 4)
			end
		end
	end
	
	fixed_cam_mat = cam_joint:get_WorldMatrix()
	player_screen_pos = player and pl_center_pos and get_onscreen_coords(pl_center_pos, fixed_cam_mat)
	--is_carry_sherry = false
	
	if wc then 
		wc = false
		hk.update_hotkey_table(ccs.hotkeys)
		json.dump_file("ClassicCams\\CCSettings.json", ccs)
	end
	
	if c_changed and current_loc_string then 
		c_changed = false
		local names = {}
		for name, cam in pairs(cams) do
			if cam.name then table.insert(names, name) end
			for fname, field in pairs(cam) do cam[fname] = cam[fname] or nil end
			cam.data = nil
		end
		table.sort(names)
		cams.names = names
		json.dump_file("ClassicCams\\"..reframework:get_game_name():upper().."\\"..current_loc_string..".json", cams)
	end
end)

local function presets_menu(glob_path, show_save_menu)
	
	local p_data = temp.presets_data[glob_path] or {preset_text=""}
	temp.presets_data[glob_path] = p_data
	 
	if not p_data.glob then
		p_data.glob = fs.glob("ClassicCams.*Preset.*"..glob_path..".*json")
		for i, path in ipairs(p_data.glob) do p_data.glob[i] = path:match("ClassicCams\\Presets\\"..glob_path.."\\(.+).json") end
		table.insert(p_data.glob, 1, "[Select Preset]")
	end
	
	local clicked_button 
	if show_save_menu then
		if imgui.button("Save preset") and p_data.preset_text:len() > 0 then
			local txt = p_data.preset_text:gsub("%.json", "") .. ".json"
			if json.dump_file("ClassicCams\\Presets\\"..glob_path.."\\"..txt, ccs) then
				re.msg("Saved to\nreframework\\data\\ClassicCams\\Presets\\"..glob_path.."\\"..txt)
			end
			p_data.glob = nil
		end
		imgui.same_line() 
		changed, p_data.preset_text = imgui.input_text("  ", p_data.preset_text)
		tooltip("Input new preset name and save the current settings to a json file in\n[Game Directory]\\reframework\\data\\ClassicCams\\Presets\\"..glob_path.."\\")
		clicked_button = imgui.button("Load preset")
		imgui.same_line()
	end
	
	changed, ccs[glob_path.."_idx"] = imgui.combo(show_save_menu and " " or (glob_path.." Setting"), ccs[glob_path.."_idx"], p_data.glob or {})
	tooltip(show_save_menu and ("Load full settings from a json file from\n[Game Directory]\\reframework\\data\\ClassicCams\\Presets\\"..glob_path.."\\") or ((p_data.cache and p_data.cache.desc or "Apply premade " .. glob_path .. " settings")))
	clicked_button = clicked_button or (not show_save_menu and changed)
	
	if ccs[glob_path.."_idx"] > 1 then
		if (not p_data.cache or clicked_button) then
			local old_idx = ccs[glob_path.."_idx"]
			p_data.cache = json.load_file("ClassicCams\\Presets\\"..glob_path.."\\"..p_data.glob[ccs[glob_path.."_idx"]]..".json")
			if clicked_button then
				ccs = hk.recurse_def_settings(json.load_file("ClassicCams\\Presets\\"..glob_path.."\\"..p_data.glob[ccs[glob_path.."_idx"]]..".json"), ccs); wc = true
				ccs[glob_path.."_idx"] = old_idx
				p_data.glob, ccs.desc = nil
			end
		end
		if not show_save_menu then
			for name, value in pairs(p_data.cache) do
				if ccs[name] ~= nil and ccs[name] ~= value then
					ccs[glob_path.."_idx"], p_data.cache = 1, nil
				end
			end
		end
	end
end

local function display_mod_menu()

	if imgui.button("Reset settings") then
		setup_gamepad_specific_defaults()
		ccs = hk.recurse_def_settings({}, default_ccs)
		hk.reset_from_defaults_tbl(default_ccs.hotkeys)
		hk.update_hotkey_table(default_ccs.hotkeys)
		wc = true
	end
	tooltip("Set all settings to their original / default values")
	imgui.same_line()
	imgui.text("*Right click on most options to reset them")
	
	imgui.indent()
	imgui.begin_rect()
	
	changed, ccs.enabled = imgui.checkbox("Enabled", ccs.enabled)
	tooltip("Enable / Disable the mod")
	if changed then classic_cam = nil end
	
	if not ccs.show_window then 
		imgui.same_line()
		if imgui.button("Spawn window") then
			ccs.show_window = true
		end
		tooltip("Create a separate window of this menu")
	end
	
	presets_menu("Controls")
	presets_menu("Autoaim")
	presets_menu("Camera")
	
	if imgui.tree_node("Save / Load Settings") then
		imgui.begin_rect()
		presets_menu("Custom", true)
		imgui.end_rect(1)
		imgui.tree_pop()
	end
	
	if imgui.tree_node("Hotkeys") then
		imgui.begin_rect() 
		changed = hk.hotkey_setter("Enable", nil, "Toggle Mod", "Toggle the mod and its fixed cameras on and off with this button"); set_wc()
		changed = hk.hotkey_setter("Toggle Laser Sight", nil, nil, "Turn the laser sight on / off"); set_wc()
		changed = hk.hotkey_setter("Strafe / Classic Aim", nil, nil, "Hold this button to strafe while using Tank Controls, or to use Classic Aim while aiming"); set_wc()
		changed = hk.hotkey_setter("Running Quick Turn", nil, nil, "Do a 180 degree turn while running\nDisables default Quick Turn on gamepad while running"); set_wc()
		changed = hk.hotkey_setter("Freeze Angle", nil, nil, "The camera angle will not change while this button is held down"); set_wc(); imgui.same_line()
		changed, ccs.freeze_angle_toggle = imgui.checkbox("Toggle", ccs.freeze_angle_toggle); set_wc("freeze_angle_toggle")
		tooltip("Makes 'Freeze Angle' be toggled on and off, rather than held")
		changed = hk.hotkey_setter("Toggle Follow Cam", nil, nil, "Press this button to enable or disable Follow Cam mode"); set_wc()
		changed = hk.hotkey_setter("Turn Camera", nil, nil, "Hold this button down and push the rstick to turn the camera in that direction"); set_wc(); imgui.same_line()
		changed, ccs.turn_angle_do_bend = imgui.checkbox("Bend", ccs.turn_angle_do_bend); set_wc("turn_angle_do_bend")
		tooltip("Makes 'Turn Camera's turn spring back to the original position")
		changed = hk.hotkey_setter("Turn Camera To Enemy", nil, nil, "The fixed camera will look towards the enemy if this button is toggled while aiming at an enemy"); set_wc()
		changed = hk.hotkey_setter("Autoaim Button", nil, nil, "If bound, autoaim will only be active while this button is held down"); set_wc()
		changed = hk.hotkey_setter("Disable Autoaim", nil, nil, "Temporarily disables autoaim while this button held down"); set_wc()
		changed = hk.hotkey_setter("Allow D-pad Shortcuts", nil, nil, "You can use the D-pad weapon shortcuts while holding this button"); set_wc()
		
		imgui.end_rect(2)
		imgui.tree_pop()
	end
	
	if imgui.tree_node("Control Options") then
		imgui.begin_rect()
		
		imgui.begin_rect()
		changed, ccs.use_dpad_controls = imgui.checkbox("D-Pad tank controls", ccs.use_dpad_controls); set_wc("use_dpad_controls")
		tooltip("Use tank controls on your gamepad's d-pad\nRun by holding the Circle (B) button")
		if ccs.use_dpad_controls then
			changed, ccs.do_dpad_swap = imgui.checkbox("Left stick for weapon shortcuts", ccs.do_dpad_swap); set_wc("do_dpad_swap")
			tooltip("Disables movement with the left analog stick, replacing it with the weapon shortcuts originally on the d-pad")
		end
		imgui.end_rect(1)
		
		changed, ccs.do_classic_aim = imgui.checkbox("Classic aim", ccs.do_classic_aim); set_wc("do_classic_aim")
		tooltip("You will turn left and right the movement stick while aiming, and your feet will be planted on the ground unable to move")
		
		changed, ccs.do_remake_run = imgui.checkbox("Auto run", ccs.do_remake_run); set_wc("do_remake_run")
		tooltip("Makes you start jogging when you push the stick far enough")
		if ccs.do_remake_run and not imgui.same_line() then
			changed, ccs.do_remake_run_reset = imgui.checkbox("Auto run direction reset", ccs.do_remake_run_reset); set_wc("do_remake_run_reset")
			tooltip("Your direction will reset to be relative to the current camera if you push the stick too lightly during Auto Run")
		end
		
		local run_buttons = {"Disabled", "Circle", "Square", "X"}
		if ccs.run_button_type > 1 then
			changed, ccs.hold_circle_to_run = imgui.checkbox("Hold button to run", ccs.hold_circle_to_run); set_wc("hold_circle_to_run")
			tooltip("Keep holding the button to run\n*Must set the run type option in the game's Controls menu to 'Toggle'")
			
			if ccs.hold_circle_to_run and not imgui.same_line() then
				changed, ccs.hold_circle_to_run_stick = imgui.checkbox("On stick", ccs.hold_circle_to_run_stick); set_wc("hold_circle_to_run_stick")
				tooltip("Keep holding the ".. run_buttons[ccs.run_button_type] .." button to run while using the analog stick")
				imgui.same_line()
				changed, ccs.do_use_kb_run = imgui.checkbox("On KB", ccs.do_use_kb_run); set_wc("do_use_kb_run")
				tooltip("Keep holding the keyboard key to run")
			end
		end
		changed, ccs.run_button_type = imgui.combo("Run button", ccs.run_button_type, run_buttons); set_wc("run_button_type")
		tooltip("Which gamepad button will be used to run")
		
		local walk_types, turn_speed, turn_speed_jog = {"Original", "Camera relative", "Tank controls"} --, "True Tank Controls"}
		changed, ccs.walk_type = imgui.combo("Walk type", ccs.walk_type, walk_types); set_wc("walk_type")
		tooltip("Set the way the player walks when using analog sticks or keyboard\n\n"..walk_types[ccs.walk_type]..":\n" 
			.. (ccs.walk_type==1 and "	Normal walking and strafing from third person perspective. Based on the player's direction"
			or  ccs.walk_type==3 and "	Turn instead of strafing. Based on the player's direction"
			--or  ccs.walk_type==4 and "	Turn instead of strafing, and you can only turn in-place. Based on the player's direction"
			or  ccs.walk_type==2 and "	Walking and strafing relative to the current fixed camera\n	Direction will carry over from camera to camera so let go of inputting backwards/sideways for a moment\n	and resume inputting relative to the current fixed camera to correct orientation after a camera switch")
		)
		local run_types = {"Original", "Camera relative", "Tank controls", "Tank controls (cam-relative run)", "Tank controls (no run backwards)"}
		changed, ccs.run_type = imgui.combo("Run type", ccs.run_type, run_types); set_wc("run_type")
		tooltip("Set the way the player runs when using analog sticks or keyboard\n\n"..run_types[ccs.run_type]..":\n" 
			.. (ccs.run_type==1 and "	Normal running from third person perspective, based on the player's direction"
			or  ccs.run_type==3 and "	Steer your direction by pressing left or right while running forwards or backwards"
			or  ccs.run_type==4 and "	Start running or pivot in any direction, then steer yourself by pressing left or right relative to that direction"
			or  ccs.run_type==5 and "	Steer your direction by pressing left or right while running forwards. You cannot run or pivot backwards or sideways"
			or  ccs.run_type==2 and "	You will run in the direction you input relative to the current fixed camera and then face that direction\n	Direction will carry over from camera to camera so let go of inputting backwards/sideways for a moment\n	and resume inputting relative to the current fixed camera to correct orientation after a camera switch"))
		
		if ccs.run_type == 2 or ccs.run_type == 4 then
			changed, ccs.cam_rel_delay_time = imgui.slider_float("Cam-relative delay", ccs.cam_rel_delay_time, 0.0, 1.0); set_wc("cam_rel_delay_time")
			tooltip("The amount of seconds after a camera change that your inputs will still be relative to the previous camera\nCtrl+click to type-in")
		end
		
		if ccs.walk_type >= 3 or ccs.use_dpad_controls then
			changed, turn_speed = imgui.slider_int("Turn speed (walk)", ccs.turn_speed * 100, 0, 200, "%.1d%%")
			ccs.turn_speed = turn_speed * 0.01; set_wc("turn_speed")
			tooltip("The speed at which you turn when using Tank Controls (walk)\nCtrl+click to type-in")
			changed, turn_speed_jog = imgui.slider_int("Turn speed (jog)", ccs.turn_speed_jog * 100, 0, 200, "%.1d%%")
			ccs.turn_speed_jog = turn_speed_jog * 0.01; set_wc("turn_speed_jog")
			tooltip("The speed at which you turn when using Tank Controls (run)\nCtrl+click to type-in")
			changed, ccs.tank_sensitivity = imgui.slider_float("Tank sensitivity", ccs.tank_sensitivity, 0, 2, "%.2fx"); set_wc("tank_sensitivity")
			tooltip("Multiplier for how little motion it takes to start turning hard with the thumbstick while running on Tank Controls\nCtrl+click to type-in")
		end
		
		changed, ccs.use_quickturn_button = imgui.checkbox("Running quick turn", ccs.use_quickturn_button); set_wc("use_quickturn_button")
		tooltip("Press the hotkey while running to quick turn")
		imgui.same_line()
		changed = hk.hotkey_setter("Running Quick Turn", nil, "", "Do a 180 degree turn while running\nDisables default Quick Turn on gamepad while running"); set_wc()
		
		if ccs.walk_type == 2 then
			changed, ccs.cam_rel_walk_do_strafe = imgui.checkbox("Strafe always (camera relative walk)", ccs.cam_rel_walk_do_strafe)
			tooltip("You will always strafe during cam-relative walk with this checked")
		end
		
		if ccs.walk_type >= 3 then
			changed, ccs.tank_walk_bwd_invert = imgui.checkbox("Invert turning when backing up", ccs.tank_walk_bwd_invert); set_wc("tank_walk_bwd_invert")
			tooltip("Pressing left while walking backwards will make you face more right and move more left")
		end
		
		changed, ccs.do_invert_y = imgui.checkbox("Invert Y aiming (Gamepad)", ccs.do_invert_y); set_wc("do_invert_y")
		tooltip("Invert aiming controls on the Y axis on gamepad")
		
		if ccs.run_type ~= 3 and ccs.run_type ~= 5  then
			changed, ccs.do_run_turnaround = imgui.checkbox("Run turnaround", ccs.do_run_turnaround); set_wc("do_run_turnaround")
			tooltip("After you start running, let go and then press 'W' or push the stick North to reorient your controls in the forward direction")
		end
		
		if sdk.get_tdb_version() > 67 then
			changed, ccs.disable_pivot = imgui.checkbox("Disable pivot", ccs.disable_pivot); set_wc("disable_pivot")
			tooltip("Removes the ability to hard-turn (pivot) while running in the RTX version of the game")
		end
		
		changed, ccs.do_qturn_fix = imgui.checkbox("Quick turn fix", ccs.do_qturn_fix); set_wc("do_qturn_fix")
		tooltip("Forces quick turns to rotate completely\nDisable if you're having quick turn issues")
		
		--changed, ccs.do_cam_rel_sherry_crouch = imgui.checkbox("Cam-Relative Sherry Crouch", ccs.do_cam_rel_sherry_crouch); set_wc("do_cam_rel_sherry_crouch")
		--tooltip("Makes it so Sherry will move relative to the camera when crouching")
		
		imgui.end_rect(2)
		imgui.tree_pop()
	end
	
	if imgui.tree_node("Autoaim / Lasersight Options") then
		imgui.begin_rect()
		changed, ccs.do_autoaim = imgui.checkbox("Autoaim", ccs.do_autoaim); set_wc("do_autoaim")
		tooltip("Autoaim your weapon at the enemy")
		if ccs.do_autoaim then
			changed, ccs.autoaim_all = imgui.checkbox("Autotarget head/legs", ccs.autoaim_all); set_wc("autoaim_all")
			tooltip("Locks-on to the enemy and targets the head or legs when aiming up or down while autoaiming")
			changed, ccs.autoaim_hitscan = imgui.checkbox("Autoaim hitscan", ccs.autoaim_hitscan); set_wc("autoaim_hitscan")
			tooltip("Hitscan bullets will automatically hit their target even if the gun is not pointed at it")
			changed, ccs.do_detect_behind = imgui.checkbox("Autoaim behind", ccs.do_detect_behind); set_wc("do_detect_behind")
			tooltip("Detect and autoatim at enemies in any direction")
			--changed, ccs.spring_back_aim = imgui.checkbox("Spring Aim", ccs.spring_back_aim); set_wc("spring_back_aim")
			--tooltip("Your aim will always try to recenter on the vertical axis")
			
			changed, ccs.autoaim_beam_size = imgui.slider_float("Autoaim beam size", ccs.autoaim_beam_size, 0.5, 10.0, "%.2f meters"); set_wc("autoaim_beam_size")
			tooltip("Determines how precise you must be when pointing your weapon to autoaim at a target\nA beam of this diameter is shot out from your weapon when you aim; enemies caught in this beam are autoaimed at.\nCtrl+click to type-in")
			changed, ccs.lock_on_type = imgui.combo("Lock-on type", ccs.lock_on_type,  {"While Drawing", "While Aiming"}); set_wc("lock_on_type")
			tooltip("Choose whether autoaim is active only while drawing your weapon or always while aiming it")
			changed, ccs.reticle_type = imgui.combo("Reticle type", ccs.reticle_type, {"None", "On Enemy", "On World"}); set_wc("reticle_type")
			tooltip("Choose whether a reticle is displayed and where")
			changed, ccs.use_lasersight = imgui.checkbox("Laser sight", ccs.use_lasersight); set_wc("use_lasersight")
			tooltip("All weapons will have a laser sight")
			
			if ccs.use_lasersight then
				changed, ccs.laser_color = imgui.color_edit("Laser color", ccs.laser_color); set_wc("laser_color")
				tooltip("The color of the laser sight")
				changed, ccs.laser_intensity = imgui.slider_float("Laser intensity", ccs.laser_intensity, 0.0, 10.0); set_wc("laser_intensity")
				tooltip("The brightness of the laser beam\nCtrl+click to type-in")
			end
			local practice_changed = false
			changed, ccs.enable_practice = imgui.checkbox("Practice mode", ccs.enable_practice); set_wc("enable_practice"); practice_changed = practice_changed or changed
			tooltip("Makes enemies and the player invulnerable, and gives infinite ammo")
			if ccs.enable_practice and not imgui.same_line() then
				changed, ccs.no_damage = imgui.checkbox("No damage", ccs.no_damage); set_wc("no_damage"); practice_changed = practice_changed or changed
				tooltip("You can be hit but will take no damage")
			end
			if practice_changed then 
				getC(player, sdk.game_namespace("HitPointController")):set_Invincible(ccs.enable_practice and not ccs.no_damage)
				getC(player, sdk.game_namespace("HitPointController")):set_NoDamage(ccs.enable_practice and ccs.no_damage)
			end
		end
		imgui.end_rect(1)
		imgui.tree_pop()
	end
	
	if imgui.tree_node("Camera Options") then
		imgui.begin_rect()
		changed, ccs.cam_switch_delay = imgui.slider_float("Camera change delay", ccs.cam_switch_delay, 0.0, 5.0, "%.2f seconds"); set_wc("cam_switch_delay")
		tooltip("How soon the camera can switch after a previous switch (if you are still onscreen)\nCtrl+click to type-in")
		changed, ccs.always_follow_player = imgui.checkbox("Always follow player", ccs.always_follow_player); set_wc("always_follow_player")
		tooltip("All fixed cameras will follow the player")
		changed, ccs.follow_cam_randomize = imgui.checkbox("Randomized follow cams", ccs.follow_cam_randomize); set_wc("follow_cam_randomize")
		tooltip("Cameras will follow with randomly assigned follow-cam settings\nWhich settings can be assigned is based on which options you have enabled here (such as Semi-Fixed or Twist)\nUncheck and re-check this box to randomize settings")
		if changed then
			for i, cam in pairs(cams) do cam.data = {} end
		end
		changed, ccs.follow_cam_do_pitch = imgui.checkbox("Follow up/down", ccs.follow_cam_do_pitch); set_wc("follow_cam_do_pitch")
		tooltip("Cameras will follow on the Y axis")
		changed, ccs.follow_cam_do_yaw = imgui.checkbox("Follow left/right", ccs.follow_cam_do_yaw); set_wc("follow_cam_do_yaw")
		tooltip("Allow following cameras to track horizontally")
		changed, ccs.follow_cam_do_twist = imgui.checkbox("Allow twist", ccs.follow_cam_do_twist); set_wc("follow_cam_do_twist")
		tooltip("Cameras will twist / roll while following")
		changed, ccs.follow_cam_do_edges = imgui.checkbox("Semi-fixed mode", ccs.follow_cam_do_edges); set_wc("follow_cam_do_edges")
		tooltip("The camera will follow only once you reach a certain distance from the edge of the screen")
		if ccs.follow_cam_do_edges then
			local edge_limit
			changed, edge_limit = imgui.slider_int("Dead zone size", ccs.follow_cam_edge_limit * 100, 0, 100, "%.1d%%")
			ccs.follow_cam_edge_limit = edge_limit * 0.01; set_wc("follow_cam_edge_limit")
			tooltip("How far from the center of the screen you can get before the camera starts to follow\nCtrl+click to type-in")
		end
		changed, ccs.follow_cam_damp_rate = imgui.slider_float("Follow speed", ccs.follow_cam_damp_rate, 0.0, 1.0, "%.4fx"); set_wc("follow_cam_damp_rate")
		tooltip("How fast the camera follows the player\nFollows at full speed at 1.0x\nCtrl+click to type-in")
		
		imgui.end_rect(1)
		imgui.tree_pop()
	end
	
	if imgui.tree_node("Visibility Options") then
		imgui.begin_rect()
		
		changed, ccs.flashing_items = imgui.checkbox("Flashing items", ccs.flashing_items); set_wc("flashing_items")
		tooltip("Make certain items and ammo flash for higher visibility")
		
		changed, ccs.no_vignette = imgui.checkbox("No vignette", ccs.no_vignette); set_wc("no_vignette")
		tooltip("Disables the default vignette (dark edges) around the screen")
		
		changed, ccs.no_pl_light_overrides = imgui.checkbox("No player light overrides", ccs.no_pl_light_overrides); set_wc("no_pl_light_overrides")
		tooltip("Individual cameras will not override the Player Light strength from these options")
		imgui.same_line()
		changed, ccs.no_cam_light_overrides = imgui.checkbox("No camera light overrides", ccs.no_cam_light_overrides); set_wc("no_cam_light_overrides")
		tooltip("Individual cameras will not override the Camera Light strength from these options")
		
		changed, ccs.env_light_strength = imgui.slider_int("Camera light stength", ccs.env_light_strength, 0, 200, "%.1d%%"); set_wc("env_light_strength")
		tooltip("The strength of the light attached to the camera\nCtrl+click to type-in")
		
		changed, ccs.player_light_strength = imgui.slider_int("Player light stength", ccs.player_light_strength, 0, 200, "%.1d%%"); set_wc("player_light_strength")
		tooltip("The strength of the light following the player\nCtrl+click to type-in")
		
		changed, ccs.autobright_type = imgui.combo("Auto-brightness", ccs.autobright_type,  {"Disabled", "When holding flashlight", "Always"}); set_wc("autobright_type")
		tooltip("Brighten the current scene automatically")
		if ccs.autobright_type > 1 then
			changed, ccs.do_auto_brighten_ev = imgui.checkbox("Use EV", ccs.do_auto_brighten_ev); set_wc("do_auto_brighten_ev")
			tooltip("Brighten the current scene using EV")
			imgui.same_line()
			changed, ccs.do_auto_brighten_gamma = imgui.checkbox("Use gamma", ccs.do_auto_brighten_gamma); set_wc("do_auto_brighten_gamma")
			tooltip("Brighten the current scene using gamma")
			if ccs.do_auto_brighten_ev then 
				changed, ccs.auto_brighten_rate_ev = imgui.slider_float("Brightness rate (EV)", ccs.auto_brighten_rate_ev, 0, 2, "%.2fx"); set_wc("auto_brighten_rate_ev")
				tooltip("Multiplier for the amount that the EV is changed when using Auto Brightness")
			end
			if ccs.do_auto_brighten_gamma then 
				changed, ccs.auto_brighten_rate_gamma = imgui.slider_float("Brightness rate (gamma)", ccs.auto_brighten_rate_gamma, 0, 2, "%.2fx"); set_wc("auto_brighten_rate_gamma")
				tooltip("Multiplier for the amount that the gamma is changed when using Auto Brightness")
			end
		end
		
		imgui.end_rect(1)
		imgui.tree_pop()
	end
	
	if imgui.tree_node("Advanced Options") then
		
		imgui.begin_rect()
		changed, ccs.disable_during_aim = imgui.checkbox("Disable mod while aiming", ccs.disable_during_aim); set_wc("disable_during_aim")
		tooltip("Fixed cameras will deactivate while the player is aiming")
		
		changed, ccs.disable_during_bites = imgui.checkbox("Disable mod during grapple", ccs.disable_during_bites); set_wc("disable_during_bites")
		tooltip("Fixed cameras will deactivate while the player is being grappled or bitten")
		
		changed, ccs.show_button_prompts = imgui.checkbox("Show button prompts", ccs.show_button_prompts); set_wc("show_button_prompts")
		tooltip("Display full button prompts over floating arrows")
		
		--changed, ccs.do_spatial_audio = imgui.checkbox("Camera Spatial Audio", ccs.do_spatial_audio); set_wc("do_spatial_audio")
		--tooltip("The sound will come from the perspective of the fixed camera, rather than the player")
		
		changed, ccs.fix_jog_anim = imgui.checkbox("Fix Jog Animation", ccs.fix_jog_anim); set_wc("fix_jog_anim")
		tooltip("Synchronizes the player character's footsteps with their jog speed at 'Fine' health")
		
		if imgui.tree_node("Camera Editor") then
			
			imgui.begin_rect()
			imgui.text_colored(current_loc_string, 0xFFAAFFFF)
			imgui.text_colored(classic_cam and classic_cam.name, 0xFF0000FF)
			imgui.same_line()
			imgui.text_colored(classic_cam and "["..classic_cam.col_idx.."]", 0xFFFFFFFF)
			
			local is_probing = (temp.cpos ~= temp.ray_pos)
			changed, temp.do_snap_cams = imgui.checkbox("Snap cams", temp.do_snap_cams); imgui.same_line()
			tooltip("Fix cameras to their positions")
			changed = hk.hotkey_setter("Snap Cam", nil, ""); set_wc()
			
			changed, temp.do_draw = imgui.checkbox("Draw collider", temp.do_draw); imgui.same_line()
			tooltip("Display collider Spheres")
			changed = hk.hotkey_setter("Draw Collider", nil, ""); set_wc()
			
			changed, temp.do_use_colliders = imgui.checkbox("Use colliders", temp.do_use_colliders); imgui.same_line()
			tooltip("Change cameras by touching their colliders")
			changed = hk.hotkey_setter("Use Colliders", nil, ""); set_wc()
			
			changed, temp.do_cast_ray = imgui.checkbox("Raycast collider", temp.do_cast_ray); imgui.same_line()
			tooltip("Allows placement of a collider in front of the crosshair")
			temp.do_use_colliders = not changed and temp.do_use_colliders
			if changed and temp.cpos and is_probing and not temp.do_cast_ray then
				temp.radius = classic_cam and classic_cam.colliders[classic_cam.col_idx].radius or temp.radius
				temp.ray_pos = temp.cpos 
			end
			changed = hk.hotkey_setter("Cast Ray", nil, ""); set_wc()
			
			if temp.do_cast_ray then
				temp.cmat = cam_joint:get_WorldMatrix()
				local ray_results = cast_ray(temp.cmat[3], temp.cmat[3] + temp.cmat[2] * -100.0, 2, 8)
				temp.gobj = ray_results[1] and ray_results[1][1]
				temp.ray_pos = ray_results[1] and ray_results[1][2] or temp.ray_pos
			end
			
			if temp.do_draw then
				if is_probing then
					world_text((temp.gobj and temp.gobj:get_Name().."" or ""), temp.ray_pos, 0xFF0000FF)
					draw.sphere(temp.ray_pos, temp.radius, 0x22AAAAFF, true)
				end
				if classic_cam then
					for i, collider in ipairs(classic_cam.colliders) do
						local pos = load("return "..collider.col_pos)()
						world_text(classic_cam.name.."\nCollider"..i, pos, 0xFFFFFFFF)
						draw.sphere(pos, collider.radius, 0x22FFAAAA, true)
					end
				end
				if temp.parent_obj then
					world_text(temp.parent_obj:get_Name(), temp.parent_obj:get_Transform():get_Position(), 0xFF77FF77)
				end
			end
			
			if current_loc_string then --and imgui.tree_node("Cameras") then
				cams_list[current_loc_string] = cams_list[current_loc_string] or {}
				cams_list[current_loc_string].names = cams_list[current_loc_string].names or {}
				
				if cams_list[current_loc_string].names["1"] then
					local fixed = {}
					for i, name in pairs(cams_list[current_loc_string].names) do if tonumber(i) then fixed[tonumber(i)] = name end end
					table.sort(fixed)
					cams_list[current_loc_string].names = fixed
				end
				
				changed, temp.exist_cam_idx = imgui.combo("Existing area cams", temp.exist_cam_idx, cams_list[current_loc_string].names)
				tooltip("Switch to a specific camera in the current area")
				
				if changed then
					classic_cam = cams_list[current_loc_string][cams_list[current_loc_string].names[temp.exist_cam_idx] ]
					temp.cpos = load("return "..classic_cam.colliders[classic_cam.col_idx].col_pos)()
					temp.cmat = load("return "..classic_cam.mat)()
					temp.radius = classic_cam.colliders[classic_cam.col_idx].radius
					temp.ray_pos = temp.cpos
					temp.cam_name_txt = classic_cam.name
					temp.do_use_colliders = false
				end
				
				changed, temp.cam_name_txt = imgui.input_text("New Cam Name", temp.cam_name_txt)
				tooltip("Type in the name for a camera to save")
				if changed then temp.do_use_colliders = false end
				
				changed, temp.radius = imgui.drag_float("Collider Radius", temp.radius or 1.0, 0.01, 0, 20)
				tooltip("The radius of the sphere for the selected collider")
				if changed and classic_cam and not is_probing then
					classic_cam.colliders[classic_cam.col_idx].radius = temp.radius
					if changed then temp.do_use_colliders = false end
				end
				
				if classic_cam then
					changed, classic_cam.fov = imgui.drag_float("FOV", classic_cam.fov or camera:get_FOV(), 0.1, 30, 120)
					tooltip("The field of view of the current camera")
				end
				
				if classic_cam then
					
					changed, classic_cam.parent_name = imgui.input_text("Parent Object", classic_cam.parent_name)
					tooltip("Set an object name or GUID that this camera will be attached to")
					if classic_cam.parent_name == "" then classic_cam.parent_name = nil end
					temp.parent_obj = find_gameobj(classic_cam.parent_name)
					
					changed, classic_cam.follow_player = imgui.checkbox("Follow player", classic_cam.follow_player); c_changed = c_changed or changed
					tooltip("Make this camera follow the player")
					
					imgui.same_line()
					changed, classic_cam.follow_twist = imgui.checkbox("Twist", classic_cam.follow_twist); c_changed = c_changed or changed
					tooltip("Allow this camera to roll / twist while following")	
					
					imgui.same_line()
					changed, classic_cam.follow_loose = imgui.checkbox("SemiFixed", classic_cam.follow_loose); c_changed = c_changed or changed
					tooltip("Make this camera follow loosely")

					imgui.same_line()
					changed, classic_cam.follow_no_pitch = imgui.checkbox("No pitch", classic_cam.follow_no_pitch); c_changed = c_changed or changed
					tooltip("Make this camera not follow vertically")	
					
					imgui.same_line()
					changed, classic_cam.follow_no_yaw = imgui.checkbox("No yaw", classic_cam.follow_no_yaw); c_changed = c_changed or changed
					tooltip("Make this camera not follow horizontally")
					
					if classic_cam.follow_loose then
						changed, classic_cam.dead_zone_sz = imgui.slider_float("Dead zone size", classic_cam.dead_zone_sz, 0.0, 1.0); c_changed = c_changed or changed
						tooltip("How far from the center of the screen you can get before this camera starts to follow\nCtrl+click to type-in")
					end
					
					changed, classic_cam.override_light = imgui.checkbox("Cam light      ", classic_cam.override_light); c_changed = c_changed or changed
					tooltip("Override the brightness of the Camera Light")
					
					imgui.same_line()
					changed, classic_cam.override_pl_light = imgui.checkbox("Player light", classic_cam.override_pl_light); c_changed = c_changed or changed
					tooltip("Override the brightness of the Player Light")
					
					if classic_cam.override_light then
						changed, classic_cam.light_str = imgui.slider_float("Camera light strength", classic_cam.light_str, 0.0, 5.0); c_changed = c_changed or changed
						tooltip("Override how strong the camera light is during this camera")
					end
					
					if classic_cam.override_pl_light then
						changed, classic_cam.pl_light_str = imgui.drag_float("Player light strength", classic_cam.pl_light_str, 0.01, 0.0, 100.0); c_changed = c_changed or changed
						tooltip("Override how strong the player light is during this camera")
					end
					
					changed, temp.ray_pos = imgui.drag_float3("Collider position", temp.ray_pos, 0.1, -9999, 9999); c_changed = c_changed or changed
					tooltip("The position of the selected collider")
					
					if imgui.button("Add collider") then
						table.insert(classic_cam.colliders, {radius=1.0, col_pos=convert_vec_to_json(temp.ray_pos)})
						classic_cam.col_idx = #classic_cam.colliders
						temp.cpos = temp.ray_pos
						c_changed = true
					end
					tooltip("Adds a new collider to this camera")
					
					if #classic_cam.colliders > 1 and not imgui.same_line() then 
						if imgui.button("Delete collider") then
							table.remove(classic_cam.colliders, classic_cam.col_idx)
							classic_cam.col_idx = #classic_cam.colliders
							temp.cpos = load("return "..classic_cam.colliders[#classic_cam.colliders].col_pos)()
							c_changed = true
						end
						tooltip("Remove the selected collider from this camera")
					end
					
					if not imgui.same_line() and imgui.button("Save collider") then
						local offset = temp.parent_obj and (temp.ray_pos - temp.parent_obj:get_Transform():get_Position())
						classic_cam.colliders[classic_cam.col_idx].col_pos = convert_vec_to_json(offset or temp.ray_pos)
						classic_cam.colliders[classic_cam.col_idx].radius = temp.radius
						temp.cpos = temp.ray_pos
						temp.do_cast_ray = false
						c_changed = true
					end
					tooltip("Update the selected collider with the settings in the Camera Editor")
					
					imgui.same_line()
					imgui.begin_rect()
					for i, collider in ipairs(classic_cam.colliders) do
						if i % 10 ~= 1 then imgui.same_line() end
						local show_rect = (classic_cam.col_idx==i)
						if show_rect then imgui.begin_rect(); imgui.begin_rect() end
						if imgui.button(i) then
							classic_cam.col_idx = i
							temp.cpos = load("return "..collider.col_pos)()
							temp.radius = collider.radius
							temp.ray_pos = temp.cpos
							--temp.do_use_colliders = false
						end
						tooltip("Select collider")
						if show_rect then imgui.end_rect(1); imgui.end_rect(2) end
					end
					imgui.same_line()
					imgui.text("Colliders")
					imgui.end_rect(1)
				end
				
				if temp.ray_pos and temp.radius then 
					local idx = find_index(cams_list[current_loc_string].names, temp.cam_name_txt)
					if imgui.button((idx and "Update" or "Create").." cam") then
						temp.do_cast_ray = false
						if not idx then
							table.insert(cams_list[current_loc_string].names, temp.cam_name_txt)
							table.sort(cams_list[current_loc_string].names)
						end
						local wmatrix = cam_joint:get_WorldMatrix()
						local offset = temp.parent_obj and (cam_joint:get_WorldMatrix()[3] - temp.parent_obj:get_Transform():get_Position())
						wmatrix[3] = offset or wmatrix[3]; wmatrix[3].w = 1.0
						if not cams_list[current_loc_string][temp.cam_name_txt] then 
							temp.do_cast_ray = true
						end
						local old = cams_list[current_loc_string][temp.cam_name_txt]
						cams_list[current_loc_string][temp.cam_name_txt] = {
							name = temp.cam_name_txt,
							mat = convert_mat_to_json(wmatrix),
							fov = camera:get_FOV(),
							parent_name = old and old.parent_name,
							colliders = old and old.colliders or {{radius=temp.radius, col_pos=convert_vec_to_json(temp.ray_pos)}},
							col_idx = old and old.col_idx or 1,
							follow_player = old and old.follow_player,
							follow_twist = old and old.follow_twist,
							follow_loose = old and old.follow_loose,
							follow_no_pitch = old and old.follow_no_pitch,
							follow_no_yaw = old and old.follow_no_yaw,
							dead_zone_sz = old and old.dead_zone_sz,
							override_light = old and old.override_light,
							override_pl_light = old and old.override_pl_light,
							light_str = old and old.light_str,
							pl_light_str = old and old.pl_light_str,
							do_custom_func = old and old.do_custom_func,
							custom_func_code = old and old.custom_func_code,
						}
						temp.exist_cam_idx = idx
						classic_cam = cams_list[current_loc_string][temp.cam_name_txt]
						temp.cmat = wmatrix
						c_changed = true
						cams = cams_list[current_loc_string]
					end
					tooltip(idx and "Update this camera" or "Create this camera")
				end
				
				if classic_cam and temp.ray_pos and not imgui.same_line() then 
					if imgui.button("Delete cam") then
						cams_list[current_loc_string][classic_cam.name] = nil
						table.remove(cams_list[current_loc_string].names, find_index(cams_list[current_loc_string].names, classic_cam.name))
						classic_cam = nil
						c_changed = true
					end
					tooltip("Delete this camera")
				end
				
				imgui.same_line()
				if imgui.tree_node("Custom Function") then
					imgui.begin_rect()
					changed, classic_cam.do_custom_func = imgui.checkbox("Use custom function", classic_cam.do_custom_func); c_changed = c_changed or changed
					tooltip("Runs a function while this cam is active\nAccessible Script Variables:\n	Stop()\n	temp\n	classic_cam\n	fixed_cam_mat\n	og_cam_mat\n	node_name\n	player\n	scene\n	pl_center_pos\n	gtime\n	ticks\n	mfsm2\n	camera\n	cam_joint\n	ccs\n	is_obscured()\n	find_gameobj()\n	cast_ray()")
					imgui.same_line()
					c_changed = imgui.button("Save code") or c_changed
					tooltip("Saves the function code to the camera")
					imgui.set_next_item_width(1920)
					changed, classic_cam.custom_func_code = imgui.input_text_multiline("Function code", classic_cam.custom_func_code, 500)
					if changed then classic_cam.do_custom_func = false end
					if temp.custom_func_error then
						imgui.text_colored(temp.custom_func_error, 0xFF0000FF)
					end
					imgui.end_rect(1)
					imgui.tree_pop()
				end
				
				--[[if EMV and imgui.tree_node("All Cameras") then 
					EMV.read_imgui_element(cams_list, nil, true) 
					imgui.tree_pop()
				end]]
				
			end
			imgui.end_rect(1)
		end
		
		imgui.end_rect(2)
		imgui.tree_pop()
	end
	
	imgui.text("													v"..version.."  |  By alphaZomega")
	imgui.end_rect(1)
	imgui.unindent()
end

re.on_draw_ui(function()
	if imgui.tree_node(reframework:get_game_name():upper().."R Classic") then
		display_mod_menu()
		imgui.tree_pop()
	end
end)

re.on_frame(function()
	
	ticks = ticks + 1
	math.randomseed(math.floor(os.clock()*100))
	
	if reframework:is_drawing_ui() then
		if not ccs.show_window or imgui.begin_window(reframework:get_game_name():upper().."R Classic", true, 0) == false then 
			ccs.show_window = false
		else
			imgui.push_id(91723)
			display_mod_menu()
			imgui.pop_id()
			imgui.end_window()
		end
	end
	
	for gameobj, enemy in pairs(Enemy.cache) do
		enemy:update()
	end

	temp.gobj = temp.gobj and sdk.to_managed_object(temp.gobj) and temp.gobj.get_Valid and temp.gobj:get_Valid() and temp.gobj
	
	if hk.check_hotkey("Enable") then
		ccs.enabled = not ccs.enabled
		temp.do_use_colliders = ccs.enabled or temp.do_use_colliders
		classic_cam = nil
		wc = true
	end
	
	if hk.check_hotkey("Snap Cam") then
		temp.do_snap_cams = not temp.do_snap_cams
	end
	
	if hk.check_hotkey("Toggle Laser Sight") then
		ccs.use_lasersight = not ccs.use_lasersight
	end
	
	if hk.check_hotkey("Draw Collider") then
		temp.do_draw = not temp.do_draw
	end
	
	if hk.check_hotkey("Use Colliders") then
		temp.do_use_colliders = not temp.do_use_colliders
	end
	
	if hk.check_hotkey("Cast Ray") then
		temp.do_cast_ray = not temp.do_cast_ray
		if temp.cpos and not temp.do_cast_ray then temp.ray_pos = temp.cpos end
		temp.do_use_colliders = not temp.do_cast_ray and temp.do_use_colliders
	end
	
	if hk.check_hotkey("Toggle Follow Cam") then
		ccs.always_follow_player = not ccs.always_follow_player
	end
end)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("camera.CameraSystem")):get_method("get_IsAimAssist"),
	nil,
	function(retval)
		return (classic_cam and autoaim_enemy and sdk.to_ptr(true)) or retval
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("camera.PlayerCameraController")):get_method("onCameraUpdate"),
	function(args)
		pl_cam_ctrl = sdk.to_managed_object(args[2])
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("survivor.Inventory")):get_method("reduceSlot("..sdk.game_namespace("EquipmentDefine.EquipCategory")..", System.Int32)"),
	function(args)
		if classic_cam and ccs.enable_practice and getC(player, sdk.game_namespace("survivor.Equipment"))["<EquipWeapon>k__BackingField"]:get_type_definition():is_a(sdk.game_namespace("implement.Gun")) then 
			return sdk.PreHookResult.SKIP_ORIGINAL 
		end
	end
)

--Make consumables flash
sdk.hook(sdk.find_type_definition(sdk.game_namespace("gimmick.action.SetItem")):get_method("onLoadGameData"),
	function(args)
		if not ccs.flashing_items then return end
		local set_item = sdk.to_managed_object(args[2])
		temp.fns[set_item] = function()
			temp.fns[set_item] = nil
			local mesh = set_item["<MeshComponent>k__BackingField"]
			if mesh and mesh:getMaterialVariableName(0, 5) == "FlashIntensity" then 
				mesh:setMaterialFloat(0, 5, 50.0)
				mesh:setMaterialFloat(0, 6, 0.5)
			end
		end
	end
)

--Make consumables flash again (game resets it here for some reason)
sdk.hook(sdk.find_type_definition(sdk.game_namespace("gui.FloatIconBehavior")):get_method("onDestroy"),
	function(args)
		if not ccs.flashing_items then return end
		local parent_obj = sdk.to_managed_object(args[2])["<ParentObject>k__BackingField"]
		if parent_obj then
			local try, set_item = pcall(getC, parent_obj, sdk.game_namespace("gimmick.action.SetItem"))
			local mesh = try and set_item and set_item["<MeshComponent>k__BackingField"]
			if mesh and mesh:getMaterialVariableName(0, 5) == "FlashIntensity" then 
				mesh:setMaterialFloat(0, 5, 50.0)
				mesh:setMaterialFloat(0, 6, 0.5)
			end
		end
	end
)

--Turn float icon into an arrow
sdk.hook(sdk.find_type_definition(sdk.game_namespace("gui.FloatIconBehavior")):get_method("doStart"),
	function(args)
		local float_icon = classic_cam and sdk.to_managed_object(args[2])
		if not float_icon or (ccs.show_button_prompts and float_icon["<ButtonTypeValue>k__BackingField"] == 8) then return end
		local arrow = float_icon:get_PanelIconMain():get_Child()
		arrow:get_Child():set_Visible(false)
		arrow:get_Next():set_Visible(false)
	end
)

if isRE3 then --Disable RE3 floating icon description
	sdk.hook(sdk.find_type_definition("offline.gui.EsFloatIconItemInfoBehavior"):get_method("doAwake"),
		function(args)
			if classic_cam then 
				sdk.to_managed_object(args[2]):set_Enabled(false)
			end
		end
	)
end

--Turn float icon into an arrow and make it be in the correct position for the fixed camera (requires updating the camera position in pre-UpdateBehavior)
sdk.hook(sdk.find_type_definition(sdk.game_namespace("gui.FloatIconBehavior")):get_method("transformWorldToScreen(via.vec3)"),
	function(args)
		if not classic_cam then return end
		local org_pos = sdk.to_valuetype(sdk.to_int64(args[4]), "via.vec3")
		local world_pos = Vector3f.new(org_pos.x, org_pos.y, org_pos.z)
		pos_2d = world2screen(world_pos, 1920, 1080)
		local float_icon = sdk.to_managed_object(args[3])
		local p_icon = float_icon.PanelIconMain or float_icon:get_PanelIconMain()
		if p_icon:get_Child():get_Next() then 
			if not ccs.show_button_prompts then 
				p_icon:get_Child():get_Next():set_Visible(false)
			end
			float_icon:get_GameObject():set_DrawSelf(not not pos_2d)
		end
	end,
	function(retval)
		if pos_2d then
			local pos = sdk.to_valuetype(retval, "via.vec3")
			pos.x, pos.y, pos.z = pos_2d.x, pos_2d.y, 0.0
			retval, pos_2d = sdk.to_ptr(pos:get_address()), nil
		end
		return retval
	end
)

local function reticle_hook_fn(args)
	if not ccs.do_autoaim or (classic_cam and ccs.reticle_type == 1) then return 1 end
	local reticle = sdk.to_managed_object(args[2])
	if not reticle["<PanelCurrentWeapon>k__BackingField"] then return end
	
	if ran_this_frame and not is_disabled_aiming and not is_disabled_bite then
		local last_pos = temp.reticle_pos
		local ls_pos = (is_lasersight_visible and ccs.reticle_type == 3) and getC(player, sdk.game_namespace("survivor.Equipment"))["<EquipWeapon>k__BackingField"]["<LaserSightTipPosition>k__BackingField"]
		local pos_3d = ls_pos or (ccs.reticle_type == 2 and autoaim_enemy and not autoaim_enemy.nodename:find("DEAD") and autoaim_enemy.autoaim_joint and autoaim_enemy.autoaim_joint:get_Position())
		temp.reticle_pos = pos_3d and world2screen(pos_3d, 1920, 1080)
		temp.reticle_pos = temp.reticle_pos and (last_pos or temp.reticle_pos):lerp(temp.reticle_pos, 0.5)
		if temp.reticle_pos and (ccs.autoaim_hitscan or 11) then
			if last_pos and (temp.reticle_pos - last_pos):length() < 3 then temp.reticle_pos = last_pos:lerp(temp.reticle_pos, 0.5) end
			reticle["<PanelMain>k__BackingField"]:set_Position(temp.reticle_pos)
		else
			return 1
		end
	else
		reticle["<PanelMain>k__BackingField"]:set_Position(Vector2f.new(960, 540))
	end
end

sdk.hook(sdk.find_type_definition(sdk.game_namespace("gui."..(isRE3 and "Es" or "").."ReticleBehavior")):get_method("draw"), reticle_hook_fn)
sdk.hook(sdk.find_type_definition(sdk.game_namespace("gui."..(isRE3 and "Es" or "").."ReticleBehavior")):get_method("drawSparkShot"), reticle_hook_fn)
sdk.hook(sdk.find_type_definition(sdk.game_namespace("gui."..(isRE3 and "Es" or "").."ReticleBehavior")):get_method("drawSexyGun"), reticle_hook_fn)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("weapon.generator.ShellGeneratorBase")):get_method(("generateShell(!weapon.shell.ShellManager.WeaponShellTypeKind, !BitFlag`1<!weapon.shell.ShellDefine.ShellTypeAttribute>, !weapon.shell.ShellUserDataBase, via.vec3, via.Quaternion, System.String, System.Action`1<!weapon.shell.IShell>, System.Boolean, System.Boolean, System.UInt32)"):gsub("!", sdk.game_namespace(""))),
	function(args)
		if not (ccs.enabled and ccs.do_autoaim and ccs.autoaim_hitscan) then return end
		if autoaim_enemy then
			local pos = sdk.to_valuetype(args[6], "via.vec3")
			local new_rot = lookat_method:call(nil, Vector3f.new(pos.x, pos.y, pos.z), autoaim_enemy.autoaim_joint:get_Position(), Vector3f.new(0,1,0)):to_quat():conjugate()
			local rot = sdk.to_valuetype(args[7], "via.Quaternion")
			rot.x, rot.y, rot.z, rot.w = new_rot.x, new_rot.y, new_rot.z, new_rot.w
			args[7] = sdk.to_ptr(rot:get_address())
		end
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("camera.fsmv2.action.ActionCameraPlayRequestRoot")):get_method(("playActionCamera(System.UInt32, System.UInt32, System.UInt32, !camera.ConstTargetParam, !camera.LookAtTargetParam, !camera.MotionInterpolateParam, System.Boolean, System.Boolean, System.Boolean)"):gsub("!", sdk.game_namespace(""))),
	function(args)
		if classic_cam and ccs.disable_during_bites then return sdk.PreHookResult.SKIP_ORIGINAL end
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("SweetLightController")):get_method("setSpotLightParam"),
	function(args)
		sw_ctrl = sdk.to_managed_object(args[2])
	end,
	function(retval)
		local name = sw_ctrl:get_GameObject():get_Name()
		sweetlight_def_intensity.pl 		  = name=="SweetLight" and sw_ctrl.RefProjectionSpotLight:get_Intensity() or sweetlight_def_intensity.pl
		sweetlight_def_intensity.env, sw_ctrl = name=="EnvironmentSweetLight" and sw_ctrl.RefProjectionSpotLight:get_Intensity() or sweetlight_def_intensity.env, nil
		return retval
	end
)

re.on_script_reset(function()
	sdk.call_native_func(renderer, sdk.find_type_definition("via.render.Renderer"), "set_Gamma", og_gamma)
end)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("gui.SelectBrightnessBehavior")):get_method("rootStateFinished"),
	nil,
	function(retval)
		og_gamma = sdk.call_native_func(renderer, sdk.find_type_definition("via.render.Renderer"), "get_Gamma")
		return retval
	end
)


sdk.hook(sdk.find_type_definition(sdk.game_namespace("posteffect.param.ToneMapping")):get_method("copyFromImpl"),
	function(args)
		if ccs.enabled and ccs.autobright_type > 1 and not temp.auto_bright_fn and pl_condition then
			local tonemap = sdk.to_managed_object(args[2])
			local ev_goal = sdk.to_managed_object(args[3]).EV
			if ev_goal < 4.0 then return end
			temp.auto_bright_fn = function()
				
				temp.auto_bright_fn = (player and ccs.enabled and ccs.autobright_type > 1 and temp.auto_bright_fn) or nil --and (math.abs(damping_float_obj["<Current>k__BackingField"] - ev_goal) > 0.01) 
				if not is_paused then 
					local has_flashlight = ccs.autobright_type == 3 or pl_condition["<_TakeFlashLight>k__BackingField"]
					damping.gamma = damping.fn_float(damping.gamma or 0, ((ccs.do_auto_brighten_gamma and has_flashlight) and (og_gamma * ((2 - ccs.auto_brighten_rate_gamma) * 1.0))) or og_gamma, 0.01)
					sdk.call_native_func(renderer, sdk.find_type_definition("via.render.Renderer"), "set_Gamma", temp.auto_bright_fn and damping.gamma or og_gamma)
					
					damping.ev = damping.fn_float(damping.ev or 0, ((ccs.do_auto_brighten_ev and has_flashlight) and (ev_goal * ((2 - ccs.auto_brighten_rate_ev) * 1.0))) or ev_goal, 0.01)
					tonemap.EV = damping.ev
				end
			end
		end
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("posteffect.param.ToneMapping")):get_method("copyFromImpl"),
	function(args)
		if temp.auto_bright_fn then
			temp.auto_bright_fn()
		end
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("survivor.player.PlayerActionOrderer")):get_method("set_JogMode"),
	function(args)
		if sdk.to_int64(args[3]) == 1 and not temp.is_move_dpad and ccs.run_type == 5 and math.abs(lstick["<Angle>k__BackingField"]) > (math.pi / 2) then
			return 1
		end
	end
)

--Manage d-pad tank controls and other tasks that require replacing input readings
sdk.hook(sdk.find_type_definition(sdk.game_namespace("InputSystem")):get_method("update"),
	function(args)
		
		if not ccs.enabled or is_paused or is_disabled_aiming or is_disabled_bite then return nil end
		temp.real_stick = {lstick["<Axis>k__BackingField"], lstick["<RawAxis>k__BackingField"], rstick["<Axis>k__BackingField"], rstick["<RawAxis>k__BackingField"]}
		is_classic_aim = is_aiming and ((ccs.do_classic_aim and not is_strafe_button) or (not ccs.do_classic_aim and is_strafe_button))
		local l_mag = lstick["<Magnitude>k__BackingField"]
		
		--Manage analog stick walking (and make face the direction you're looking):
		local was_look_turn = temp.is_look_turn 
		temp.relative_stick_dir = temp.fns.fix_jog and temp.relative_stick_dir
		temp.is_look_turn = not is_jacked and not temp.is_move_dpad and (node_name:find("STAND%.IDLE") or node_name == "STAND.WALK_END" or node_name:find("WALKING")) and (lstick["<Power>k__BackingField"] == 0) 
			and (math.abs(temp.real_stick[3].x) > 0.33) and pl_condition and not pl_condition["<IsLight>k__BackingField"] and not hk.check_hotkey("Turn Camera", true)
		
		if hk.check_hotkey("Turn Camera", true) then
			rstick:call("update(via.vec2, via.vec2)", Vector2f.new(0,0), Vector2f.new(0,0))
		elseif temp.is_look_turn then
			if not was_look_turn then
				pl_cam_ctrl["<Yaw>k__BackingField"] = pl_xform:get_EulerAngle().y + math.pi
				set_node_method:call(mfsm2:getLayer(0), "GAZING_WALKING", setn, interper)
			end
			local new_axis = Vector2f.new(temp.real_stick[3].x, -1)
			lstick:call("update(via.vec2, via.vec2)", new_axis, new_axis)
			
			temp.fns.look_turn_fn = function()
				temp.fns.look_turn_fn = nil
				pl_xform:set_Position(Vector3f.new(pl_pos.x, pl_xform:get_Position().y, pl_pos.z)) --pl_pos is 1 frame old when this runs
			end
		end
		
		local og_angle = lstick["<Angle>k__BackingField"]
		if temp.relative_stick_dir then
			local r2 = og_angle + math.pi * (temp.use_old_rel_run_style and -1 or 1)
			local radius = math.abs(l_mag)
			local cr_l_axis = Vector2f.new(radius * math.sin(pl_xform:get_EulerAngle().y - r2 - temp.relative_stick_dir), radius * math.cos(pl_xform:get_EulerAngle().y - r2 - temp.relative_stick_dir))
			lstick:call("update(via.vec2, via.vec2)", cr_l_axis, cr_l_axis)
		end
		
		local is_up, is_dn
		local use_kb = not is_pad and ccs.do_use_kb_run
		local kb_run_key = input_system:getCommandPrimaryKey(14)
		local bbits = input_system:get_ButtonBits()
		
		local run_button = ccs.run_button_type==2 and 262272 or ccs.run_button_type==3 and 64 or ccs.run_button_type==4 and 131104
		local did_rqt_hotkey = ccs.use_quickturn_button and hk.check_hotkey("Running Quick Turn", 1)
		local run_triggered = run_button and ((use_kb and input_system:isTrigger(kb_run_key)) or (is_pad and (hk.pad:get_ButtonDown() | run_button == hk.pad:get_ButtonDown())))
		
		local did_qt = temp.is_qturn_frame and ccs.do_qturn_fix and not temp.control_fns.quickturn_fn  and temp.real_stick[1].y < 0
		temp.is_qturn_frame = nil
		temp.is_tank_turn = false
		temp.is_move_dpad = false
		
		local use_dpad_controls = is_pad and ccs.use_dpad_controls and (not hk.check_hotkey("Allow D-pad Shortcuts", true) or is_jacked)
		local analog_tank_axis = ccs.walk_type >= 3 and not temp.is_look_turn and (is_walking or is_jogging) and l_mag > 0.1 and not is_strafe_button and lstick["<Axis>k__BackingField"] 
		local was_running_w_circle = temp.started_running_w_circle
		
		if run_triggered then
			temp.started_running_w_circle = true
		end
		
		--Manage tank controls (walk and dpad-run):
		if use_dpad_controls or analog_tank_axis then
			is_up = (bbits.On | 16777216 == bbits.On)
			is_dn = (bbits.On | 33554432 == bbits.On)
			local is_l = (bbits.On | 67108864 == bbits.On)
			local is_r = (bbits.On | 134217728 == bbits.On)
			temp.is_move_dpad = is_pad and (is_up or is_dn or is_l or is_r)
			is_up = is_up or (analog_tank_axis and analog_tank_axis.y > 0.25)
			is_dn = is_dn or (analog_tank_axis and analog_tank_axis.y < -0.25)
			is_l = is_l or (analog_tank_axis and analog_tank_axis.x < -0.2)
			is_r = is_r or (analog_tank_axis and analog_tank_axis.x > 0.2)
			local is_v = is_up or is_dn
			local is_h = is_l or is_r
			local is_move = is_v or is_h
			temp.frozen_mat_dpad = not (temp.is_move_dpad and is_walking and is_h and not is_v) and player:get_Transform():get_WorldMatrix() or temp.frozen_mat_dpad or player:get_Transform():get_WorldMatrix()
			
			if is_move then
				local dpad_as_dir = Vector2f.new(((not is_v or is_jogging) and ((is_l and -1.0) or (is_r and 1.0)) or 0.0), ((is_dn and -1.0) or (is_up and 1.0) or 0.0))
				lstick:call("update(via.vec2, via.vec2)", dpad_as_dir, dpad_as_dir)
				
				if (not is_aiming or is_classic_aim or is_sherry_crouch) and not is_strafe_button then
					if not is_jacked and (is_walking or is_sherry_crouch) and (analog_tank_axis or not is_v) then
					
						temp.fns.tank_pos_fn = function()
							temp.fns.tank_pos_fn = nil
							if analog_tank_axis then
								local char_ang = pl_ctrl["<CharAngle>k__BackingField"]["<Current>k__BackingField"]
								if gtime - last_qt_time > 0.66 and not node_name:find("QUICK") and math.abs(pl_ctrl["<CharAngle>k__BackingField"]._Target - char_ang) > 0.1 then
									pl_ctrl["<CharAngle>k__BackingField"]:updateParam()
									pl_ctrl["<CharAngle>k__BackingField"]:updateParam()
									pl_ctrl["<CharAngle>k__BackingField"]:updateParam()
									pl_ctrl["<CharAngle>k__BackingField"]:updateParam() --interpolate at 5x speed
								end
								local t = normalize_single(math.abs(lstick["<Axis>k__BackingField"].y), -0.02, 1, 0, 2)
								temp.frozen_mat_dpad = temp.frozen_mat_dpad:interpolate(pl_xform:get_WorldMatrix(), t > 1 and 1 or t)
								temp.is_tank_turn = true
							end
							player:get_Transform():set_Position(Vector3f.new(temp.frozen_mat_dpad[3].x, player:get_Transform():get_Position().y, temp.frozen_mat_dpad[3].z)) 
						end
					end
					
					if is_h then
						local bwd_multip = (ccs.tank_walk_bwd_invert and is_dn and -1) or 1 --reverse turn direction when backing up during tank turn
						local jog_multip = is_jogging and (0.045 * ccs.turn_speed_jog)
						if analog_tank_axis then
							local new_yaw = pl_cam_ctrl["<Yaw>k__BackingField"] - analog_tank_axis.x * bwd_multip * (jog_multip and (jog_multip * 0.33) or (0.057 * ccs.turn_speed)) * timescale_mult * deltatime
							pl_cam_ctrl["<Yaw>k__BackingField"] = new_yaw
						else
							pl_cam_ctrl["<Yaw>k__BackingField"] = pl_cam_ctrl["<Yaw>k__BackingField"] - (is_l and -1 or is_r and 1 or 0) * bwd_multip * (jog_multip or (0.057 * ccs.turn_speed)) * timescale_mult * deltatime
						end
					end
				end
			end
			
			--disable automatic pivoting (only on RTX version):
			if not is_jacked and sdk.get_tdb_version() > 67 then 
				local tree = mfsm2:getLayer(0):get_tree_object()
				local nodes = tree:get_nodes()
				local do_inihibit_turn = is_move or (ccs.disable_pivot and ccs.run_type ~= 2)
				tree:get_node_by_name("JOG_END"):get_data():get_transition_conditions()[1] = do_inihibit_turn and 0 or 62
				tree:get_node_by_name("JOGGING"):get_data():get_transition_conditions()[5] = do_inihibit_turn and 0 or 12
			end
			
			if ccs.do_invert_y then
				local invert = Vector2f.new(temp.real_stick[3].x, -temp.real_stick[3].y)
				rstick:call("update(via.vec2, via.vec2)", invert, invert)
			end
		end
		
		if is_classic_aim then
			if lstick["<Magnitude>k__BackingField"] > 0.2 and gtime - last_qt_time > 0.25 then
				rstick:call("update(via.vec2, via.vec2)", lstick["<Axis>k__BackingField"], lstick["<RawAxis>k__BackingField"])
				temp.real_stick[3], temp.real_stick[4] = rstick["<Axis>k__BackingField"], rstick["<RawAxis>k__BackingField"]
				lstick:call("update(via.vec2, via.vec2)", Vector2f.new(0,0), Vector2f.new(0,0))
			end
			if run_triggered then
				set_node_method:call(mfsm2:getLayer(0), "QUICK_TURN_EX", setn, interper) --you cant run during classic aim so it quickturns
			end
		end
		
		--Manage Running Quick Turn and Circle-Jog-Start:
		if did_qt or ((run_triggered or did_rqt_hotkey) and (node_name == "JOGGING" or node_name == "JOG_END.START" or node_name == "JOG_START" or is_walking or node_name:find("QUICK"))) then -- 4284416 is X
			if is_jogging and not temp.fns.running_qturn_fn and not did_qt then
				if did_rqt_hotkey and not prev_node_name:find("GAZING") then
					temp.started_running_w_circle = was_running_w_circle
					temp.fns.stop_running_fn = nil
					temp.qt_dir = ((temp.relative_stick_dir and temp.relative_stick_dir + math.pi) or (player:get_Transform():get_EulerAngle().y)) - lstick["<Angle>k__BackingField"]
					temp.fns.fix_jog, temp.relative_stick_dir = nil
					pl_cam_ctrl["<Yaw>k__BackingField"] = temp.qt_dir
					local did_set = false
					local start = gtime
					
					temp.fns.running_qturn_fn = function()
						temp.fns.running_qturn_fn = (gtime - start < 0.15) and temp.fns.running_qturn_fn or nil
						pl_cam_ctrl["<Yaw>k__BackingField"] = temp.qt_dir
						did_set = did_set or set_node_method:call(mfsm2:getLayer(0), "JOG_TURN", setn, interper)
						if not temp.fns.running_qturn_fn then 
							temp.do_restart_fix_jog = true --triggers fix_jog creation as this function finishes
						end
						temp.fns.fix_jog, temp.relative_stick_dir = nil
					end
				end
			elseif did_qt or (run_triggered and (is_dn or is_walking or is_sherry_crouch)) then
				if is_dn or did_qt then 
					if did_qt then
						local did_run = false
						local yaw = pl_cam_ctrl["<Yaw>k__BackingField"]
						local blank_vec = Vector2f.new(0,0)
						local start = gtime 
						local eul = pl_xform:get_EulerAngle()
						pl_xform:set_EulerAngle(Vector3f.new(eul.x, yaw + math.pi, eul.z))
						pl_ctrl["<CharAngle>k__BackingField"]["<Current>k__BackingField"] = yaw + math.pi
						pl_ctrl["<WatchAngle>k__BackingField"]["<Current>k__BackingField"] = yaw + math.pi	
						
						temp.control_fns.quickturn_fn = function() --fucking quick turn and its bullshit mystery way of deciding how much to turn
							temp.control_fns.quickturn_fn = gtime - start < 0.45 and temp.control_fns.quickturn_fn or nil
							pl_ctrl["<MoveAngle>k__BackingField"]["<Current>k__BackingField"] = yaw + math.pi
							temp.real_stick = temp.real_stick and {blank_vec, blank_vec, blank_vec, blank_vec}
							lstick:call("update(via.vec2, via.vec2)", blank_vec, blank_vec)
							did_run = did_run or set_node_method:call(mfsm2:getLayer(0), "QUICK_TURN_EX", setn, interper)
						end
					else
						set_node_method:call(mfsm2:getLayer(0), "QUICK_TURN_EX", setn, interper)
					end
				else
					set_node_method:call(mfsm2:getLayer(0), "JOGGING", setn, interper) --start running
				end
			end
		end
		
		--Manage hold-circle run-stop:
		if ccs.hold_circle_to_run and is_jogging and temp.started_running_w_circle and not temp.fns.stop_running_fn and not temp.fns.running_qturn_fn
		and (not is_pad or temp.is_move_dpad or ccs.hold_circle_to_run_stick) and ((is_pad and run_button and (hk.pad:get_Button() | run_button ~= hk.pad:get_Button())) or (use_kb and not hk.kb:isDown(kb_run_key))) then
			local start = gtime
			
			temp.fns.stop_running_fn = function()
				temp.fns.stop_running_fn = gtime - start < 0.2 and temp.fns.stop_running_fn or nil
				if player and not temp.fns.stop_running_fn and not temp.fns.running_qturn_fn then 
					getC(player, sdk.game_namespace("survivor.SurvivorUserVariablesUpdater")):set_Jog(false)
					temp.started_running_w_circle = nil
					temp.fns.fix_jog = nil
				end
			end
		end
		
		input_system.Inhibit.SkipReset = ccs.use_quickturn_button and is_pad and is_jogging --Quick turn does not get disabled unless this is true
		input_system:call("setInhibit(System.Boolean, "..sdk.game_namespace("").."InputDefine.Kind[])", ccs.use_quickturn_button and is_jogging, inhibit_arrs.qt)
		input_system:call("setInhibit(System.Boolean, "..sdk.game_namespace("").."InputDefine.Kind[])", use_dpad_controls and (temp.is_move_dpad or (lstick["<Magnitude>k__BackingField"] == 0)), inhibit_arrs.shortcuts)
		
		for i, fn in pairs(temp.control_fns) do
			fn()
		end
	end,
	function(retval)
		if is_pad and temp.real_stick and ccs.use_dpad_controls and not hk.check_hotkey("Allow D-pad Shortcuts", true) and ccs.do_dpad_swap and not is_jacked then
			local is_wep_swap = (ccs.do_dpad_swap and not temp.is_move_dpad and lstick["<Magnitude>k__BackingField"] > 0.0)
			if not temp.is_move_dpad then 
				lstick:call("update(via.vec2, via.vec2)", Vector2f.new(0,0), Vector2f.new(0,0)) --clear actual LStick because we're using it for shortcuts
			end
			input_system:call("setForce("..sdk.game_namespace("InputDefine.Kind")..", System.Boolean)", 17179869184, temp.real_stick[1].y > 0.9)  --up
			input_system:call("setForce("..sdk.game_namespace("InputDefine.Kind")..", System.Boolean)", 34359738368, temp.real_stick[1].y < -0.9) --down
			input_system:call("setForce("..sdk.game_namespace("InputDefine.Kind")..", System.Boolean)", 68719476736, temp.real_stick[1].x < -0.9) --left
			input_system:call("setForce("..sdk.game_namespace("InputDefine.Kind")..", System.Boolean)", 137438953472, temp.real_stick[1].x > 0.9) --right
			input_system:call("setInhibit(System.Boolean, "..sdk.game_namespace("").."InputDefine.Kind[])", is_wep_swap, inhibit_arrs.move)
		else
			input_system:call("setForce("..sdk.game_namespace("InputDefine.Kind")..", System.Boolean)", 2, is_classic_aim) --force "watch" to make turn
			input_system:call("setInhibit(System.Boolean, "..sdk.game_namespace("").."InputDefine.Kind[])", is_classic_aim, inhibit_arrs.move) --move
		end
		input_system:call("setForce("..sdk.game_namespace("InputDefine.Kind")..", System.Boolean)", 1, temp.is_move_dpad or temp.is_look_turn) --move
		
		return retval
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("survivor.Inventory")):get_method("equipMainSlot"),
	function(args)
		if ccs.use_dpad_controls and temp.is_move_dpad then return sdk.PreHookResult.SKIP_ORIGINAL end
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("gui.GUIMaster")):get_method("openShortcut"),
	function(args)
		if ccs.use_dpad_controls and temp.is_move_dpad then return sdk.PreHookResult.SKIP_ORIGINAL end
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("gui.GUIMaster")):get_method("get_EnableShortcut"),
	nil,
	function(retval)
		if ccs.use_dpad_controls and temp.is_move_dpad then return sdk.to_ptr(false) end
		return retval
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("EnemyManager")):get_method("requestHideDeadEnemys(System.Single)"),
	function(args)
		if classic_cam and is_grappled then return sdk.PreHookResult.SKIP_ORIGINAL end
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("EnemyManager")):get_method("cancelHideDeadEnemys()"),
	function(args)
		if classic_cam and is_grappled then return sdk.PreHookResult.SKIP_ORIGINAL end
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("survivor.fsmv2.action.SurvivorQuickTurnExAction")):get_method("onStart"),
	function(args)
		temp.is_qturn_frame = not temp.control_fns.quickturn_fn
	end
)

sdk.hook(sdk.find_type_definition(sdk.game_namespace("survivor.fsmv2.action.SurvivorQuickTurnAction")):get_method("onStart"),
	function(args)
		temp.is_qturn_frame = not temp.control_fns.quickturn_fn
	end
)