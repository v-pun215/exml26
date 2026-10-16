extends Node3D

@export var host := "127.0.0.1"
@export var port := 8765

var tcp := StreamPeerTCP.new()
var buf := PackedByteArray()
var retry_in := 0.0

var arena := 200.0
var sphere_r := 1.0
var jump_h := 2.0
var have_map := false

const CAM_PITCH := 0.96
const CAM_FOV := 50.0
const ORBIT_SENS := 0.005
const VIEW_VERSION := 9

var cam_target := Vector3.ZERO
var cam_dist := 250.0
var cam_yaw := 0.0
var cam_pitch := CAM_PITCH
var last_mp := Vector2.ZERO
var have_mp := false
var caption: Label

var last_info := {}
var last_pose := {}
var agent_order: Array = []
var follow_idx := -1
var follow_pos := Vector3.ZERO
var follow_yaw := 0.0
var agent_hist := {}
var enter_was := false
var esc_was := false

var map_root: Node3D
var cloud_root: Node3D
var cloud_clusters := []
var agent_root: Node3D
var camera: Camera3D
var hud: Label

var team_mats := {}
var team_colors := {}
var agent_mats := {}
var agent_meshes := {}
var agent_vel := {}
var sphere_nodes := {}
var flag_nodes := {}
var flag_banners := []
var minimap: Control
var mini_obstacles := []
var mini_ramps := []
var mini_flags := {}
var obstacle_mat: StandardMaterial3D
var ground_mat: ShaderMaterial
var ramp_top_mat: StandardMaterial3D
var ramp_side_mat: StandardMaterial3D
var pole_mat: StandardMaterial3D
var ramp_grain_tex: ImageTexture
var aurora_curtain_shader: Shader
var map_glow_shader: Shader

var agent_grounded := {}
var agent_carrying := {}
var agent_carry_indicators := {}
var last_score := {}

var music_player: AudioStreamPlayer
var jump_player: AudioStreamPlayer
var land_player: AudioStreamPlayer
var grab_player: AudioStreamPlayer
var score_player: AudioStreamPlayer


func _ready() -> void:
	map_root = Node3D.new()
	map_root.name = "Map"
	add_child(map_root)
	agent_root = Node3D.new()
	agent_root.name = "Agents"
	add_child(agent_root)

	camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	_setup_camera()

	var sun := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "DirectionalLight3D"
		add_child(sun)
	sun.rotation = Vector3(-0.9, -0.6, 0.0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_angular_distance = 2.5
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.82
	sun.shadow_blur = 1.4
	sun.shadow_bias = 0.03
	sun.directional_shadow_max_distance = 300.0
	sun.directional_shadow_blend_splits = true

	_spawn_clouds()
	_spawn_aurora_curtains()

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(12, 10)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.text = "waiting for bridge..."
	layer.add_child(hud)
	var hint := Label.new()
	hint.position = Vector2(12, 34)
	hint.text = "v9: drag orbit · WASD move · wheel zoom · Enter follow · Esc free"
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint)
	caption = Label.new()
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -52.0
	caption.offset_bottom = -16.0
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.visible = false
	layer.add_child(caption)

	minimap = Control.new()
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.custom_minimum_size = Vector2(190, 190)
	minimap.size = Vector2(190, 190)
	minimap.offset_left = -202.0
	minimap.offset_right = -12.0
	minimap.offset_top = 12.0
	minimap.offset_bottom = 202.0
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	layer.add_child(minimap)


	obstacle_mat = StandardMaterial3D.new()
	obstacle_mat.albedo_color = Color(0.5, 0.45, 0.36)
	obstacle_mat.metallic = 0.0
	obstacle_mat.roughness = 0.9
	obstacle_mat.emission_enabled = false
	obstacle_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://ground_facets.gdshader")

	ramp_grain_tex = _make_ramp_grain(64)

	ramp_top_mat = StandardMaterial3D.new()
	ramp_top_mat.albedo_color = Color(0.69, 0.50, 0.32)
	ramp_top_mat.albedo_texture = ramp_grain_tex
	ramp_top_mat.metallic = 0.0
	ramp_top_mat.roughness = 0.65
	ramp_top_mat.uv1_scale = Vector3(0.3, 0.3, 1.0)
	ramp_top_mat.emission_enabled = true
	ramp_top_mat.emission = Color(0.69, 0.50, 0.32)
	ramp_top_mat.emission_energy_multiplier = 0.4
	ramp_top_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	ramp_side_mat = StandardMaterial3D.new()
	ramp_side_mat.albedo_color = Color(0.33, 0.22, 0.14)
	ramp_side_mat.albedo_texture = ramp_grain_tex
	ramp_side_mat.metallic = 0.0
	ramp_side_mat.roughness = 0.9
	ramp_side_mat.uv1_scale = Vector3(0.3, 0.3, 1.0)
	ramp_side_mat.emission_enabled = true
	ramp_side_mat.emission = Color(0.33, 0.22, 0.14)
	ramp_side_mat.emission_energy_multiplier = 0.3
	ramp_side_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.4, 0.36, 0.3)
	pole_mat.metallic = 0.0
	pole_mat.roughness = 0.7

	_setup_audio()
	tcp.connect_to_host(host, port)


func _draw_minimap() -> void:
	var sz := minimap.size
	var span := minf(sz.x, sz.y)
	var pad := 8.0
	var scale := (span - pad * 2.0) / maxf(arena, 1.0)
	var origin := Vector2(sz.x * 0.5, sz.y * 0.5)

	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.07, 0.06, 0.13, 0.82), true)
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.68, 0.58, 0.95, 0.70), false, 1.0)

	var field := arena * scale
	minimap.draw_rect(Rect2(origin - Vector2(field, field) * 0.5, Vector2(field, field)),
		Color(0.14, 0.13, 0.24, 0.92), true)
	minimap.draw_rect(Rect2(origin - Vector2(field, field) * 0.5, Vector2(field, field)),
		Color(0.45, 0.38, 0.68, 0.45), false, 1.0)

	for quad in mini_ramps:
		var pts := PackedVector2Array()
		for p in quad:
			pts.append(origin + p * scale)
		minimap.draw_colored_polygon(pts, Color(0.62, 0.47, 0.78, 0.95))

	for poly in mini_obstacles:
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(origin + p * scale)
		minimap.draw_colored_polygon(pts, Color(0.30, 0.27, 0.42, 0.95))

	for team in mini_flags.keys():
		var fp: Vector2 = mini_flags[team]
		var col: Color = team_colors.get(team, Color(1, 1, 1))
		var sp := origin + fp * scale
		minimap.draw_line(sp + Vector2(0, 2.5), sp + Vector2(0, -7.0), Color(0.95, 0.95, 1.0, 0.95), 1.0)
		minimap.draw_rect(Rect2(sp + Vector2(0.5, -7.0), Vector2(6.0, 4.0)), col, true)
		minimap.draw_rect(Rect2(sp + Vector2(0.5, -7.0), Vector2(6.0, 4.0)), Color(0.95, 0.95, 1.0, 0.85), false, 1.0)
		minimap.draw_circle(sp + Vector2(0, 2.5), 1.2, Color(0.95, 0.95, 1.0, 0.95))

	for sid in last_pose.keys():
		if not last_info.has(sid):
			continue
		var info: Dictionary = last_info[sid]
		if not bool(info.get("alive", true)):
			continue
		var st: Dictionary = last_pose[sid]
		var pos: Vector3 = st["pos"]
		var team := String(info.get("team", "?"))
		var base: Color = team_colors.get(team, Color(1, 1, 1))
		var hfrac := clampf((pos.y - sphere_r) / maxf(jump_h, 0.01), 0.0, 1.0)
		var light := Color.from_hsv(base.h, base.s * 0.38, minf(1.0, base.v * 1.5 + 0.2))
		var col := base.lerp(light, hfrac)
		var sp := origin + Vector2(pos.x, pos.z) * scale
		minimap.draw_circle(sp, 4.0, col)


func _spawn_clouds() -> void:
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(0.95, 0.93, 0.9)
	cloud_mat.metallic = 0.0
	cloud_mat.roughness = 1.0
	cloud_mat.emission_enabled = true
	cloud_mat.emission = Color(0.95, 0.93, 0.9)
	cloud_mat.emission_energy_multiplier = 0.3

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	cloud_root = Node3D.new()
	cloud_root.name = "Clouds"
	add_child(cloud_root)
	for i in range(14):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.0, 480.0)
		var base_y := rng.randf_range(90.0, 170.0)
		var cluster := Node3D.new()
		cluster.position = Vector3(cos(ang) * dist, base_y, sin(ang) * dist)
		cloud_root.add_child(cluster)
		cloud_clusters.append({"node": cluster, "base_y": base_y, "phase": rng.randf() * TAU})
		for p in range(rng.randi_range(3, 5)):
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = rng.randf_range(10.0, 22.0)
			sm.height = sm.radius * 1.6
			sm.radial_segments = 8
			sm.rings = 5
			mi.mesh = sm
			mi.material_override = cloud_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(
				rng.randf_range(-18.0, 18.0),
				rng.randf_range(-4.0, 6.0),
				rng.randf_range(-18.0, 18.0))
			cluster.add_child(mi)


func _spawn_aurora_curtains() -> void:
	if aurora_curtain_shader == null:
		aurora_curtain_shader = load("res://aurora_curtain.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	var curtain_root := Node3D.new()
	curtain_root.name = "AuroraCurtains"
	add_child(curtain_root)
	for i in range(7):
		var ang := (TAU / 7.0) * float(i) + rng.randf_range(-0.2, 0.2)
		var dist := rng.randf_range(420.0, 650.0)
		var width := rng.randf_range(260.0, 420.0)
		var height := rng.randf_range(700.0, 1000.0)
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(width, height)
		quad.mesh = qm
		quad.position = Vector3(cos(ang) * dist, height * -0.05, sin(ang) * dist)
		quad.rotation.y = -ang - PI * 0.5

		var mat := ShaderMaterial.new()
		mat.shader = aurora_curtain_shader
		mat.set_shader_parameter("seed", rng.randf() * 50.0)
		mat.set_shader_parameter("density", rng.randf_range(1.5, 4.0))
		mat.set_shader_parameter("speed", rng.randf_range(0.08, 0.18))
		mat.set_shader_parameter("intensity", rng.randf_range(1.0, 1.6))
		mat.set_shader_parameter("color_a", Color(0.85, 0.32, 0.62))
		mat.set_shader_parameter("color_b", Color(0.3, 0.78, 0.78))
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		curtain_root.add_child(quad)


func _make_ramp_grain(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for y in range(size):
		for x in range(size):
			var fx := float(x) / size
			var fy := float(y) / size
			var grain := 0.5 + 0.5 * sin(fy * TAU * 14.0 + sin(fx * TAU * 2.0) * 1.3)
			var v := 0.84 + grain * 0.1
			v += rng.randf_range(-0.04, 0.04)
			v = clampf(v, 0.68, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


func _setup_audio() -> void:
	music_player = AudioStreamPlayer.new()
	var music := load("res://audio/music/ambient_loop.wav") as AudioStreamWAV
	if music != null:
		music.loop_mode = AudioStreamWAV.LOOP_FORWARD
		music_player.stream = music
	music_player.volume_db = -14.0
	music_player.autoplay = true
	add_child(music_player)

	jump_player = AudioStreamPlayer.new()
	jump_player.stream = load("res://audio/sfx/jump.wav")
	jump_player.volume_db = -6.0
	add_child(jump_player)

	land_player = AudioStreamPlayer.new()
	land_player.stream = load("res://audio/sfx/land.wav")
	land_player.volume_db = -6.0
	add_child(land_player)

	grab_player = AudioStreamPlayer.new()
	grab_player.stream = load("res://audio/sfx/grab.wav")
	grab_player.volume_db = -4.0
	add_child(grab_player)

	score_player = AudioStreamPlayer.new()
	score_player.stream = load("res://audio/sfx/score.wav")
	score_player.volume_db = -3.0
	add_child(score_player)


func _setup_camera() -> void:
	cam_dist = arena * 1.25
	cam_target = Vector3.ZERO
	cam_yaw = 0.0
	cam_pitch = CAM_PITCH
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAM_FOV
	camera.near = 1.0
	camera.far = 2000.0
	_update_camera()


func _follow_zoom() -> float:
	return clampf(cam_dist / 250.0, 0.3, 2.4)


func _update_camera() -> void:
	if follow_idx >= 0 and follow_idx < agent_order.size() and last_pose.has(agent_order[follow_idx]):
		var st: Dictionary = last_pose[agent_order[follow_idx]]
		follow_pos = st["pos"]
		follow_yaw = float(st.get("yaw", 0.0))
		_place_follow_cam()
	else:
		var cp := cos(cam_pitch)
		var offset := Vector3(sin(cam_yaw) * cp, sin(cam_pitch), cos(cam_yaw) * cp) * cam_dist
		camera.position = cam_target + offset
		camera.look_at(cam_target)


func _place_follow_cam() -> void:
	var fwd := Vector3(sin(follow_yaw), 0, cos(follow_yaw))
	var zf := _follow_zoom()
	camera.position = follow_pos - fwd * (9.0 * zf) + Vector3(0, 6.0 * zf, 0)
	camera.look_at(follow_pos + fwd * (4.0 * zf))


func _agent_tag(sid: int) -> String:
	if last_info.has(sid):
		var info: Dictionary = last_info[sid]
		var team := String(info.get("team", "?"))
		var initial := team.left(1).to_upper() if team.length() > 0 else "?"
		return "%s%d" % [initial, int(info.get("player", 0))]
	return "#%d" % sid


func _refresh_caption() -> void:
	if follow_idx >= 0 and follow_idx < agent_order.size():
		caption.text = "%s   (Enter: next · Esc: free cam)" % _agent_tag(agent_order[follow_idx])
		caption.visible = true
	else:
		caption.visible = false


func _orbit_by(rel: Vector2) -> void:
	cam_yaw -= rel.x * ORBIT_SENS
	cam_pitch = clampf(cam_pitch + rel.y * ORBIT_SENS, 0.15, 1.45)
	_update_camera()


func _cycle_follow() -> void:
	_refresh_order()
	if agent_order.is_empty():
		follow_idx = -1
	elif follow_idx + 1 < agent_order.size():
		follow_idx += 1
	else:
		follow_idx = -1
	_refresh_caption()
	_update_camera()


func _refresh_order() -> void:
	var arr: Array = last_info.keys()
	arr.sort_custom(func(a, b):
		var ia: Dictionary = last_info[a]
		var ib: Dictionary = last_info[b]
		var ta := String(ia.get("team", "?"))
		var tb := String(ib.get("team", "?"))
		if ta == tb:
			return int(ia.get("player", 0)) < int(ib.get("player", 0))
		return ta < tb
	)
	agent_order = arr
	if follow_idx >= agent_order.size():
		follow_idx = -1


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				cam_dist = clampf(cam_dist * 0.9, 60.0, 600.0)
				if follow_idx < 0:
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				cam_dist = clampf(cam_dist * 1.1, 60.0, 600.0)
				if follow_idx < 0:
					_update_camera()


func _process(delta: float) -> void:
	_update_agent_poses()
	if follow_idx < 0:
		var mp := get_viewport().get_mouse_position()
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if have_mp:
				_orbit_by(mp - last_mp)
			last_mp = mp
			have_mp = true
		else:
			have_mp = false
		var fwd_g := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
		var right_g := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
		var mv := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			mv += fwd_g
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			mv -= fwd_g
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			mv -= right_g
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			mv += right_g
		if mv != Vector3.ZERO:
			cam_target += mv.normalized() * cam_dist * 0.9 * delta
			var lim := arena * 0.5 + 40.0
			cam_target.x = clampf(cam_target.x, -lim, lim)
			cam_target.z = clampf(cam_target.z, -lim, lim)
			cam_target.y = 0.0
			_update_camera()
	else:
		var sid: int = agent_order[follow_idx] if follow_idx < agent_order.size() else -1
		if last_pose.has(sid):
			var dp := _display_pose(sid)
			follow_pos = dp[0]
			follow_yaw = float(dp[1])
			_place_follow_cam()
	var enter_now := Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER)
	if enter_now and not enter_was:
		_cycle_follow()
	enter_was = enter_now
	var esc_now := Input.is_physical_key_pressed(KEY_ESCAPE)
	if esc_now and not esc_was:
		follow_idx = -1
		_refresh_caption()
		_update_camera()
	esc_was = esc_now
	_roll_agents(delta)
	_squash_agents()
	_drift_clouds(delta)
	_sway_flags(delta)
	_spin_carry_indicators(delta)
	if minimap != null and have_map:
		minimap.queue_redraw()
	tcp.poll()
	var st := tcp.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTED:
		_pump()
	elif st != StreamPeerTCP.STATUS_CONNECTING:
		retry_in -= delta
		if retry_in <= 0.0:
			retry_in = 1.0
			hud.text = "waiting for bridge %s:%d ..." % [host, port]
			tcp.connect_to_host(host, port)


func _display_pose(sid: int) -> Array:
	if not agent_hist.has(sid):
		return [Vector3.ZERO, 0.0]
	var h: Dictionary = agent_hist[sid]
	var t0 := int(h["t0"])
	var t1 := int(h["t1"])
	if t1 <= t0:
		return [h["p1"], float(h["y1"])]
	var a := clampf(float(Time.get_ticks_msec() - t1) / float(maxi(t1 - t0, 1)), 0.0, 1.0)
	var p0: Vector3 = h["p0"]
	var p1: Vector3 = h["p1"]
	return [p0.lerp(p1, a), lerp_angle(float(h["y0"]), float(h["y1"]), a)]


func _update_agent_poses() -> void:
	for sid in sphere_nodes.keys():
		if not agent_hist.has(sid):
			continue
		var node := sphere_nodes[sid] as Node3D
		if node == null:
			continue
		node.position = _display_pose(sid)[0]
		var hfrac := clampf((node.position.y - sphere_r) / maxf(jump_h, 0.01), 0.0, 1.0)
		if last_info.has(sid) and agent_mats.has(sid):
			var team := String((last_info[sid] as Dictionary).get("team", "?"))
			var base: Color = team_colors.get(team, Color(1, 1, 1))
			(agent_mats[sid] as StandardMaterial3D).albedo_color = base.lerp(Color(1, 1, 1), hfrac * 0.85)


func _squash_agents() -> void:
	for sid in agent_meshes.keys():
		var mesh := agent_meshes[sid] as MeshInstance3D
		if mesh == null or not agent_vel.has(sid):
			continue
		var vz: float = (agent_vel[sid] as Vector3).y
		var s := clampf(vz * 0.025, -0.22, 0.22)
		mesh.scale = Vector3(1.0 - s * 0.5, 1.0 + s, 1.0 - s * 0.5)


func _spin_carry_indicators(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for sid in agent_carry_indicators.keys():
		var entry: Dictionary = agent_carry_indicators[sid]
		var ind_root := entry["root"] as Node3D
		if ind_root.visible:
			var base_y: float = entry["base_y"]
			ind_root.position.y = base_y + sin(t * 1.2 + float(sid)) * 0.08


func _sway_flags(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry in flag_banners:
		var node := entry["node"] as Node3D
		node.rotation.y = sin(t * 1.4 + entry["phase"]) * 0.35


func _drift_clouds(delta: float) -> void:
	if cloud_root == null:
		return
	cloud_root.rotation.y += delta * 0.012
	var t := Time.get_ticks_msec() / 1000.0
	for entry in cloud_clusters:
		var node := entry["node"] as Node3D
		node.position.y = entry["base_y"] + sin(t * 0.25 + entry["phase"]) * 3.0


func _roll_agents(delta: float) -> void:
	for sid in sphere_nodes.keys():
		var node := sphere_nodes[sid] as Node3D
		if node == null or not node.visible or not agent_vel.has(sid) or not agent_meshes.has(sid):
			continue
		var v: Vector3 = agent_vel[sid]
		var sp := Vector2(v.x, v.z).length()
		if sp < 0.05:
			continue
		var axis := Vector3(v.z, 0, -v.x).normalized()
		(agent_meshes[sid] as MeshInstance3D).rotate(axis, sp * delta / maxf(sphere_r, 0.01))


func _pump() -> void:
	var n := tcp.get_available_bytes()
	if n > 0:
		var res := tcp.get_data(n)
		if res[0] == OK:
			buf.append_array(res[1])
			_drain_lines()


func _drain_lines() -> void:
	while true:
		var idx := buf.find(10)
		if idx < 0:
			break
		var line := buf.slice(0, idx).get_string_from_utf8()
		buf = buf.slice(idx + 1)
		if line.strip_edges().is_empty():
			continue
		var frame = JSON.parse_string(line)
		if typeof(frame) != TYPE_DICTIONARY:
			continue
		match String(frame.get("type", "")):
			"map":
				_build_map(frame)
			"tick":
				_apply_tick(frame)


func _clear(node: Node3D) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _build_map(frame: Dictionary) -> void:
	_clear(map_root)
	_clear(agent_root)
	sphere_nodes.clear()
	flag_nodes.clear()
	flag_banners.clear()
	agent_hist.clear()
	last_info.clear()
	last_pose.clear()
	agent_order.clear()
	agent_grounded.clear()
	agent_carrying.clear()
	last_score.clear()
	follow_idx = -1
	_refresh_caption()

	arena = float(frame.get("arena_size", 200.0))
	sphere_r = float(frame.get("sphere_radius", 1.0))
	jump_h = float(frame.get("max_jump_height", 2.0))
	_setup_camera()

	team_mats.clear()
	team_colors.clear()
	agent_mats.clear()
	agent_meshes.clear()
	agent_vel.clear()
	agent_carry_indicators.clear()
	for t in frame.get("teams", []):
		var base := Color(String(t.get("color", "#ffffff")))
		team_colors[String(t.get("name", "?"))] = base
		var mat := StandardMaterial3D.new()
		mat.albedo_color = base
		mat.emission_enabled = false
		mat.roughness = 0.55
		team_mats[String(t.get("name", "?"))] = mat

	var half := arena * 0.5
	var ground := _make_ground_mesh(arena, 28)
	ground.material_override = ground_mat
	map_root.add_child(ground)

	var glow_size := arena * 2.4
	var glow_plane_mi := MeshInstance3D.new()
	var glow_plane := PlaneMesh.new()
	glow_plane.size = Vector2(glow_size, glow_size)
	glow_plane_mi.mesh = glow_plane
	glow_plane_mi.position = Vector3(0, 0.45, 0)
	if map_glow_shader == null:
		map_glow_shader = load("res://map_glow.gdshader")
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = map_glow_shader
	glow_mat.set_shader_parameter("plane_size", glow_size)
	glow_mat.set_shader_parameter("arena_half", half)
	glow_mat.set_shader_parameter("falloff", 26.0)
	glow_mat.set_shader_parameter("intensity", 0.16)
	glow_plane_mi.material_override = glow_mat
	glow_plane_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_root.add_child(glow_plane_mi)

	var border_mat := StandardMaterial3D.new()
	border_mat.albedo_color = Color(0.4, 0.37, 0.48)
	border_mat.metallic = 0.0
	border_mat.roughness = 0.9
	for spec in [
		[Vector3(0, 1, -half), Vector3(arena + 2.0, 2.0, 1.0)],
		[Vector3(0, 1, half), Vector3(arena + 2.0, 2.0, 1.0)],
		[Vector3(-half, 1, 0), Vector3(1.0, 2.0, arena + 2.0)],
		[Vector3(half, 1, 0), Vector3(1.0, 2.0, arena + 2.0)],
	]:
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[1]
		wall.mesh = box
		wall.position = spec[0]
		wall.material_override = border_mat
		map_root.add_child(wall)

	mini_obstacles.clear()
	mini_ramps.clear()
	mini_flags.clear()

	for o in frame.get("obstacles", []):
		var pts: Array = o.get("points", [])
		map_root.add_child(_prism(pts, float(o.get("height", 1.0))))
		var flat := PackedVector2Array()
		for p in pts:
			flat.append(Vector2(float(p[0]), float(p[1])))
		if flat.size() >= 3:
			mini_obstacles.append(flat)

	for r in frame.get("ramps", []):
		var rcx := float(r.get("cx", 0.0))
		var rcy := float(r.get("cy", 0.0))
		var rdx := float(r.get("dx", 1.0))
		var rdy := float(r.get("dy", 0.0))
		var rlen := float(r.get("length", 10.0))
		var rwid := float(r.get("width", 5.0))
		map_root.add_child(_wedge(rcx, rcy, rdx, rdy, rlen, rwid, float(r.get("height", 3.0))))
		var dir := Vector2(rdx, rdy).normalized()
		var side := Vector2(-dir.y, dir.x)
		var ctr := Vector2(rcx, rcy)
		var quad2 := PackedVector2Array()
		quad2.append(ctr - dir * rlen * 0.5 - side * rwid * 0.5)
		quad2.append(ctr - dir * rlen * 0.5 + side * rwid * 0.5)
		quad2.append(ctr + dir * rlen * 0.5 + side * rwid * 0.5)
		quad2.append(ctr + dir * rlen * 0.5 - side * rwid * 0.5)
		mini_ramps.append(quad2)

	for f in frame.get("flags", []):
		flag_nodes[String(f.get("team", "?"))] = _make_flag(f)

	have_map = true


func _hash01(x: float, z: float) -> float:
	var v := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return v - floor(v)


func _rock_height(x: float, z: float, base_height: float) -> float:
	return base_height * (1.0 + _hash01(x * 0.6, z * 0.6) * 0.3)


func _face_normal_up(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n := (b - a).cross(c - a)
	if n.length() < 0.0001:
		return Vector3(0, 1, 0)
	n = n.normalized()
	if n.y < 0.0:
		n = -n
	return n


func _ground_height(x: float, z: float) -> float:
	var broad := _hash01(x * 0.035, z * 0.035) * 0.06
	var fine := _hash01(x * 0.21 + 11.0, z * 0.21 + 11.0) * 0.02
	return -(broad + fine)


func _facet_color(cx: float, cz: float) -> Color:
	var t := _hash01(cx * 0.07 + 31.0, cz * 0.07 + 31.0)
	var warm := Color(0.62, 0.78, 0.42)
	var cool := Color(0.32, 0.62, 0.48)
	var col := cool.lerp(warm, t)
	var shade := 0.9 + _hash01(cx * 0.33 + 7.0, cz * 0.33 + 7.0) * 0.22
	return Color(col.r * shade, col.g * shade, col.b * shade)


func _add_facet(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var mx := (a.x + b.x + c.x) / 3.0
	var mz := (a.z + b.z + c.z) / 3.0
	var col := _facet_color(mx, mz)
	var phase := _hash01(mx * 1.37 + 3.0, mz * 1.91 + 9.0)
	var rate := _hash01(mx * 0.73 + 21.0, mz * 2.41 + 17.0)
	var uv := Vector2(phase, rate)
	st.set_normal(_face_normal_up(a, b, c))
	st.set_color(col)
	st.set_uv(uv)
	st.add_vertex(a)
	st.set_color(col)
	st.set_uv(uv)
	st.add_vertex(b)
	st.set_color(col)
	st.set_uv(uv)
	st.add_vertex(c)


func _make_ground_mesh(size: float, divisions: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var step := size / float(divisions)
	for ix in range(divisions):
		for iz in range(divisions):
			var x0 := -half + float(ix) * step
			var x1 := x0 + step
			var z0 := -half + float(iz) * step
			var z1 := z0 + step

			var p00 := Vector3(x0, _ground_height(x0, z0), z0)
			var p10 := Vector3(x1, _ground_height(x1, z0), z0)
			var p11 := Vector3(x1, _ground_height(x1, z1), z1)
			var p01 := Vector3(x0, _ground_height(x0, z1), z1)

			if _hash01(float(ix) * 3.7, float(iz) * 5.1) < 0.5:
				_add_facet(st, p00, p10, p11)
				_add_facet(st, p00, p11, p01)
			else:
				_add_facet(st, p00, p10, p01)
				_add_facet(st, p10, p11, p01)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi


func _prism(points: Array, height: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(obstacle_mat)
	var n := points.size()
	if n < 3:
		var empty := MeshInstance3D.new()
		empty.mesh = ArrayMesh.new()
		return empty
	var cx := 0.0
	var cz := 0.0
	for p in points:
		cx += float(p[0])
		cz += float(p[1])
	cx /= float(n)
	cz /= float(n)
	for i in range(n):
		var ax := float(points[i][0])
		var az := float(points[i][1])
		var bx := float(points[(i + 1) % n][0])
		var bz := float(points[(i + 1) % n][1])
		var ex := bx - ax
		var ez := bz - az
		var leng := Vector2(ex, ez).length()
		var normal := Vector3(0, 1, 0)
		if leng > 0.0001:
			normal = Vector3(ez / leng, 0, -ex / leng)
		var a0 := Vector3(ax, 0, az)
		var b0 := Vector3(bx, 0, bz)
		var a1 := Vector3(ax, _rock_height(ax, az, height), az)
		var b1 := Vector3(bx, _rock_height(bx, bz, height), bz)
		st.set_normal(normal)
		st.add_vertex(a0)
		st.add_vertex(b0)
		st.add_vertex(b1)
		st.add_vertex(a0)
		st.add_vertex(b1)
		st.add_vertex(a1)
	var c := Vector3(cx, _rock_height(cx, cz, height), cz)
	for i in range(n):
		var a := Vector3(float(points[i][0]), _rock_height(float(points[i][0]), float(points[i][1]), height), float(points[i][1]))
		var b := Vector3(float(points[(i + 1) % n][0]), _rock_height(float(points[(i + 1) % n][0]), float(points[(i + 1) % n][1]), height), float(points[(i + 1) % n][1]))
		st.set_normal(_face_normal_up(c, a, b))
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(b)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi


func _wedge(cx: float, cy: float, dx: float, dz: float, length: float, width: float, height: float) -> Node3D:
	var dl := Vector2(dx, dz).normalized()
	var a := Vector3(dl.x, 0, dl.y)
	var s := Vector3(-dl.y, 0, dl.x)
	var c := Vector3(cx, 0, cy)
	var l2 := length * 0.5
	var w2 := width * 0.5
	var low_l := c - a * l2 - s * w2
	var low_r := c - a * l2 + s * w2
	var high_l0 := c + a * l2 - s * w2
	var high_r0 := c + a * l2 + s * w2
	var high_l := high_l0 + Vector3(0, height, 0)
	var high_r := high_r0 + Vector3(0, height, 0)
	var slope_n := (Vector3(0, 1, 0) - a * (height / maxf(length, 0.01))).normalized()

	var root := Node3D.new()

	var top_st := SurfaceTool.new()
	top_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	top_st.set_material(ramp_top_mat)
	top_st.set_normal(slope_n)
	top_st.set_uv(Vector2(-l2, -w2))
	top_st.add_vertex(low_l)
	top_st.set_uv(Vector2(-l2, w2))
	top_st.add_vertex(low_r)
	top_st.set_uv(Vector2(l2, w2))
	top_st.add_vertex(high_r)
	top_st.set_uv(Vector2(-l2, -w2))
	top_st.add_vertex(low_l)
	top_st.set_uv(Vector2(l2, w2))
	top_st.add_vertex(high_r)
	top_st.set_uv(Vector2(l2, -w2))
	top_st.add_vertex(high_l)
	var top_mi := MeshInstance3D.new()
	top_mi.mesh = top_st.commit()
	root.add_child(top_mi)

	var side_st := SurfaceTool.new()
	side_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	side_st.set_material(ramp_side_mat)
	side_st.set_normal(-s)
	side_st.set_uv(Vector2(-l2, 0.0))
	side_st.add_vertex(low_l)
	side_st.set_uv(Vector2(l2, 0.0))
	side_st.add_vertex(high_l0)
	side_st.set_uv(Vector2(l2, height))
	side_st.add_vertex(high_l)
	side_st.set_normal(s)
	side_st.set_uv(Vector2(-l2, 0.0))
	side_st.add_vertex(low_r)
	side_st.set_uv(Vector2(l2, height))
	side_st.add_vertex(high_r)
	side_st.set_uv(Vector2(l2, 0.0))
	side_st.add_vertex(high_r0)
	side_st.set_normal(a)
	side_st.set_uv(Vector2(-w2, 0.0))
	side_st.add_vertex(high_l0)
	side_st.set_uv(Vector2(w2, 0.0))
	side_st.add_vertex(high_r0)
	side_st.set_uv(Vector2(w2, height))
	side_st.add_vertex(high_r)
	side_st.set_uv(Vector2(-w2, 0.0))
	side_st.add_vertex(high_l0)
	side_st.set_uv(Vector2(w2, height))
	side_st.add_vertex(high_r)
	side_st.set_uv(Vector2(-w2, height))
	side_st.add_vertex(high_l)
	var side_mi := MeshInstance3D.new()
	side_mi.mesh = side_st.commit()
	root.add_child(side_mi)

	return root


func _make_agent(sid: int, team: String, _player: int) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = sphere_r
	sm.height = sphere_r * 2.0
	sm.radial_segments = 24
	sm.rings = 16
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = team_colors.get(team, Color(1, 1, 1))
	mat.metallic = 0.05
	mat.roughness = 0.4
	mat.rim_enabled = true
	mat.rim = 0.35
	mat.rim_tint = 0.5
	mat.emission_enabled = false
	mi.material_override = mat
	agent_mats[sid] = mat
	agent_meshes[sid] = mi
	root.add_child(mi)

	var indicator := Node3D.new()
	indicator.position = Vector3(0, sphere_r * 1.9, 0)
	indicator.visible = false

	var ind_mat := StandardMaterial3D.new()
	ind_mat.metallic = 0.0
	ind_mat.roughness = 0.6
	ind_mat.emission_enabled = true
	ind_mat.emission_energy_multiplier = 0.35
	var ind_chip := MeshInstance3D.new()
	var ind_chip_mesh := BoxMesh.new()
	ind_chip_mesh.size = Vector3(0.22, 0.22, 0.04)
	ind_chip.mesh = ind_chip_mesh
	ind_chip.material_override = ind_mat
	indicator.add_child(ind_chip)

	root.add_child(indicator)
	agent_carry_indicators[sid] = {"root": indicator, "mat": ind_mat, "base_y": sphere_r * 1.9}
	return root


func _make_flag(f: Dictionary) -> Node3D:
	var team := String(f.get("team", "?"))
	var root := Node3D.new()
	root.position = Vector3(float(f.get("x", 0.0)), 0.0, float(f.get("y", 0.0)))

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.4
	base_mesh.bottom_radius = 1.6
	base_mesh.height = 0.3
	base.mesh = base_mesh
	base.position = Vector3(0, 0.15, 0)
	base.material_override = team_mats.get(team, pole_mat)
	root.add_child(base)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.1
	pole_mesh.bottom_radius = 0.14
	pole_mesh.height = 4.0
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 2.0, 0)
	pole.material_override = pole_mat
	root.add_child(pole)

	var pivot := Node3D.new()
	pivot.position = Vector3(0, 3.5, 0)
	root.add_child(pivot)

	var banner := MeshInstance3D.new()
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(1.5, 0.9, 0.08)
	banner.mesh = banner_mesh
	banner.position = Vector3(0.85, 0.0, 0)
	banner.material_override = team_mats.get(team, pole_mat)
	pivot.add_child(banner)
	flag_banners.append({"node": pivot, "phase": randf() * TAU})

	map_root.add_child(root)
	return root


func _apply_tick(frame: Dictionary) -> void:
	if not have_map:
		return
	var tick := int(frame.get("tick", 0))
	for s in frame.get("spheres", []):
		var sid := int(s.get("id", -1))
		var team := String(s.get("team", "?"))
		var player := int(s.get("player", 0))
		var yaw := float(s.get("yaw", 0.0))
		var raw := Vector3(float(s.get("x", 0.0)), float(s.get("z", 0.0)), float(s.get("y", 0.0)))
		var now := Time.get_ticks_msec()
		var node := sphere_nodes.get(sid, null) as Node3D
		if node == null:
			node = _make_agent(sid, team, player)
			agent_root.add_child(node)
			sphere_nodes[sid] = node
			node.position = raw
			agent_hist[sid] = {"p0": raw, "y0": yaw, "t0": now, "p1": raw, "y1": yaw, "t1": now}
		elif agent_hist.has(sid):
			var h: Dictionary = agent_hist[sid]
			h["p0"] = h["p1"]
			h["y0"] = h["y1"]
			h["t0"] = h["t1"]
			h["p1"] = raw
			h["y1"] = yaw
			h["t1"] = now
		else:
			agent_hist[sid] = {"p0": raw, "y0": yaw, "t0": now, "p1": raw, "y1": yaw, "t1": now}
		node.visible = bool(s.get("alive", true))
		last_info[sid] = {"team": team, "player": player, "alive": bool(s.get("alive", true))}
		last_pose[sid] = {"pos": raw, "yaw": yaw}
		agent_vel[sid] = Vector3(float(s.get("vx", 0.0)), float(s.get("vz", 0.0)), float(s.get("vy", 0.0)))

		var grounded := bool(s.get("grounded", true))
		var was_grounded = agent_grounded.get(sid, grounded)
		if grounded and not was_grounded:
			land_player.play()
		elif not grounded and was_grounded and float(s.get("vz", 0.0)) > 3.0:
			jump_player.play()
		agent_grounded[sid] = grounded

		var carrying = s.get("carrying", null)
		if carrying != null and agent_carrying.get(sid, null) == null:
			grab_player.play()
		agent_carrying[sid] = carrying
		if agent_carry_indicators.has(sid):
			var indicator: Dictionary = agent_carry_indicators[sid]
			var ind_root := indicator["root"] as Node3D
			ind_root.visible = carrying != null
			if carrying != null:
				var carry_color: Color = team_colors.get(String(carrying), Color(1, 1, 1))
				var ind_mat := indicator["mat"] as StandardMaterial3D
				ind_mat.albedo_color = carry_color
				ind_mat.emission = carry_color
	_refresh_order()
	_refresh_caption()
	for f in frame.get("flags", []):
		var team := String(f.get("team", "?"))
		mini_flags[team] = Vector2(float(f.get("x", 0.0)), float(f.get("y", 0.0)))
		if flag_nodes.has(team) and int(f.get("carried_by", -1)) == -1:
			(flag_nodes[team] as Node3D).position = Vector3(float(f.get("x", 0.0)), 0.0, float(f.get("y", 0.0)))
	var sc: Dictionary = frame.get("score", {})
	for k in sc.keys():
		if int(sc[k]) > int(last_score.get(k, 0)):
			score_player.play()
		last_score[k] = int(sc[k])
	var order: Array = sc.keys()
	order.sort()
	var parts: Array = []
	for k in order:
		parts.append("%s %d" % [String(k).to_upper(), int(sc[k])])
	var score_txt := " · ".join(parts) if not parts.is_empty() else "-"
	hud.text = "tick %d   %s   orb (%.2f, %.2f) mb%d" % [tick, score_txt, cam_yaw, cam_pitch, int(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))]
