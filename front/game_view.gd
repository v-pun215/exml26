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
const LOOK_SENS := 0.0028
const COL_GRASS_A := Color(0.24, 0.48, 0.52)
const COL_GRASS_B := Color(0.30, 0.56, 0.58)
const VIEW_VERSION := 9

var cam_target := Vector3.ZERO
var cam_dist := 250.0
var cam_yaw := 0.0
var cam_pitch := CAM_PITCH
var free_pos := Vector3.ZERO
var free_yaw := 0.0
var free_pitch := -CAM_PITCH
var mouse_reset_frames := 0
var free_cursor_free := false
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
var bg_root: Node3D
var cloud_root: Node3D
var cloud_clusters := []
var agent_root: Node3D
var camera: Camera3D
var hud: Label

var team_mats := {}
var team_colors := {}
var max_ticks := 0
var tick_rate := 20
var match_over := false
var hint_label: Label
var game_over_layer: CanvasLayer
var game_over_root: Control
var go_box: VBoxContainer
var winner_label: Label
var sub_label: Label
var score_box: VBoxContainer
var foot_label: Label
var go_winner_ls: LabelSettings
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
var obstacle_mat: ShaderMaterial
var ground_mat: ShaderMaterial
var ramp_top_mat: ShaderMaterial
var ramp_side_mat: ShaderMaterial
var pole_mat: ShaderMaterial
var aurora_curtain_shader: Shader
var map_glow_shader: Shader
var toon_shader: Shader
var outline_shader: Shader
var outline_mat: ShaderMaterial
var blob_shader: Shader
var blob_mat: ShaderMaterial
var puff_shader: Shader
var face_mat: StandardMaterial3D
var agent_faces := {}
var agent_limbs := {}
var agent_blobs := {}
var agent_states := {}
var puff_root: Node3D
var puffs: Array = []

var capture_path := ""
var capture_countdown := 0
var capture_follow := false
var capture_portrait := false
var capture_lock := false

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
	for arg in OS.get_cmdline_user_args():
		if arg == "--capture-follow":
			capture_follow = true
		elif arg == "--capture-portrait":
			capture_portrait = true
		elif arg.begins_with("--capture="):
			capture_path = arg.substr(10)
			capture_countdown = 90
	map_root = Node3D.new()
	map_root.name = "Map"
	add_child(map_root)
	agent_root = Node3D.new()
	agent_root.name = "Agents"
	add_child(agent_root)
	bg_root = Node3D.new()
	bg_root.name = "Background"
	add_child(bg_root)
	puff_root = Node3D.new()
	puff_root.name = "Puffs"
	add_child(puff_root)

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
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_angular_distance = 0.7
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.5
	sun.shadow_blur = 2.0
	sun.shadow_bias = 0.03
	sun.directional_shadow_max_distance = 300.0
	sun.directional_shadow_blend_splits = true

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight3D"
	fill.rotation = Vector3(-0.45, 2.4, 0.0)
	fill.light_energy = 0.12
	fill.light_color = Color(0.72, 0.85, 1.0)
	fill.shadow_enabled = false
	add_child(fill)

	toon_shader = load("res://toon.gdshader")
	outline_shader = load("res://outline.gdshader")
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = outline_shader
	blob_shader = load("res://blob.gdshader")
	blob_mat = ShaderMaterial.new()
	blob_mat.shader = blob_shader
	puff_shader = load("res://puff.gdshader")
	face_mat = StandardMaterial3D.new()
	face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_mat.albedo_color = Color(0.09, 0.07, 0.17)
	face_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	obstacle_mat = _toon_material(Color(0.95, 0.42, 0.34), 0.06)

	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://ground_facets.gdshader")

	ramp_top_mat = _toon_material(Color(1.0, 0.5, 0.74), 0.05, Color(0, 0, 0), 0.0, false, false)
	ramp_side_mat = _toon_material(Color(0.86, 0.34, 0.58), 0.04, Color(0, 0, 0), 0.0, false, false)
	pole_mat = _toon_material(Color(0.86, 0.86, 0.92), 0.06)

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
	hint_label = Label.new()
	hint_label.position = Vector2(12, 34)
	hint_label.text = "Enter next bot · Esc free cam"
	hint_label.modulate = Color(1, 1, 1, 0.55)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint_label)
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

	_setup_audio()
	tcp.connect_to_host(host, port)


func _draw_minimap() -> void:
	var sz := minimap.size
	var span := minf(sz.x, sz.y)
	var pad := 8.0
	var scale := (span - pad * 2.0) / maxf(arena, 1.0)
	var origin := Vector2(sz.x * 0.5, sz.y * 0.5)

	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.99, 0.97, 0.93, 0.9), true)
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.45, 0.38, 0.62, 0.6), false, 1.0)

	var field := arena * scale
	minimap.draw_rect(Rect2(origin - Vector2(field, field) * 0.5, Vector2(field, field)),
		Color(0.66, 0.87, 0.48, 0.95), true)
	minimap.draw_rect(Rect2(origin - Vector2(field, field) * 0.5, Vector2(field, field)),
		Color(0.55, 0.45, 0.85, 0.6), false, 1.0)

	for quad in mini_ramps:
		var pts := PackedVector2Array()
		for p in quad:
			pts.append(origin + p * scale)
		minimap.draw_colored_polygon(pts, Color(0.99, 0.62, 0.80, 0.95))

	for poly in mini_obstacles:
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(origin + p * scale)
		minimap.draw_colored_polygon(pts, Color(0.94, 0.50, 0.40, 0.95))

	for team in mini_flags.keys():
		var fp: Vector2 = mini_flags[team]
		var col: Color = team_colors.get(team, Color(1, 1, 1))
		var sp := origin + fp * scale
		minimap.draw_line(sp + Vector2(0, 2.5), sp + Vector2(0, -7.0), Color(0.3, 0.26, 0.4, 0.95), 1.0)
		minimap.draw_rect(Rect2(sp + Vector2(0.5, -7.0), Vector2(6.0, 4.0)), col, true)
		minimap.draw_rect(Rect2(sp + Vector2(0.5, -7.0), Vector2(6.0, 4.0)), Color(0.3, 0.26, 0.4, 0.8), false, 1.0)
		minimap.draw_circle(sp + Vector2(0, 2.5), 1.2, Color(0.3, 0.26, 0.4, 0.95))

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
		var light := Color.from_hsv(base.h, base.s * 0.45, minf(1.0, base.v * 0.75 + 0.15))
		var col := base.lerp(light, hfrac)
		var sp := origin + Vector2(pos.x, pos.z) * scale
		minimap.draw_circle(sp, 4.0, col)


func _toon_material(color: Color, rim := 0.08,
		emission := Color(0, 0, 0), emission_strength := 0.0, vertex_color := false,
		outlined := true) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = toon_shader
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("rim_strength", rim)
	mat.set_shader_parameter("emission_color", emission)
	mat.set_shader_parameter("emission_strength", emission_strength)
	mat.set_shader_parameter("use_vertex_color", vertex_color)
	if outlined:
		mat.next_pass = outline_mat
	return mat


func _spawn_clouds() -> void:
	var cloud_mat := _toon_material(Color(0.95, 0.97, 1.0), 0.02, Color(1, 1, 1), 0.85)

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	cloud_root = Node3D.new()
	cloud_root.name = "Clouds"
	add_child(cloud_root)
	for i in range(20):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(260.0, 700.0)
		var base_y := rng.randf_range(80.0, 200.0)
		var cluster := Node3D.new()
		cluster.position = Vector3(cos(ang) * dist, base_y, sin(ang) * dist)
		cloud_root.add_child(cluster)
		cloud_clusters.append({"node": cluster, "base_y": base_y, "phase": rng.randf() * TAU})
		for p in range(rng.randi_range(4, 6)):
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = rng.randf_range(16.0, 34.0)
			sm.height = sm.radius * 1.35
			sm.radial_segments = 10
			sm.rings = 6
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
		mat.set_shader_parameter("intensity", rng.randf_range(0.15, 0.3))
		mat.set_shader_parameter("color_a", Color(0.72, 0.88, 1.0))
		mat.set_shader_parameter("color_b", Color(0.92, 0.86, 1.0))
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		curtain_root.add_child(quad)


func _bg_height(x: float, z: float, flat_r: float, span_r: float) -> float:
	var r := Vector2(x, z).length()
	if r <= flat_r:
		return -1.2
	var t := clampf((r - flat_r) / maxf(span_r - flat_r, 1.0), 0.0, 1.0)
	var n := 0.0
	var amp := 1.0
	var freq := 0.0042
	var norm := 0.0
	for o in range(4):
		var ridge := 1.0 - absf(sin(x * freq + 1.7 + float(o) * 3.1) * cos(z * freq * 1.3 - 2.3 + float(o) * 1.7))
		n += ridge * amp
		norm += amp
		amp *= 0.55
		freq *= 2.15
	n /= norm
	n = n * n
	return -1.2 + t * t * (70.0 + 300.0 * n)


func _add_bg_facet(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, base: Color) -> void:
	var n := (b - a).cross(c - a)
	n = n.normalized() if n.length() > 0.0001 else Vector3(0, 1, 0)
	if n.y < 0.0:
		n = -n
	var j := 0.93 + _hash01((a.x + b.x + c.x) * 0.37 + 17.0, (a.z + b.z + c.z) * 0.41 + 23.0) * 0.12
	var col := Color(base.r * j, base.g * j, base.b * j).srgb_to_linear()
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)


func _spawn_background() -> void:
	_clear(bg_root)
	var flat_r := arena * 0.5 + 50.0
	var span_r := 2400.0
	var step := 80.0
	var divisions := int(span_r * 2.0 / step)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in range(divisions):
		for iz in range(divisions):
			var x0 := -span_r + float(ix) * step
			var x1 := x0 + step
			var z0 := -span_r + float(iz) * step
			var z1 := z0 + step
			var p00 := Vector3(x0, _bg_height(x0, z0, flat_r, span_r), z0)
			var p10 := Vector3(x1, _bg_height(x1, z0, flat_r, span_r), z0)
			var p11 := Vector3(x1, _bg_height(x1, z1, flat_r, span_r), z1)
			var p01 := Vector3(x0, _bg_height(x0, z1, flat_r, span_r), z1)
			var base := COL_GRASS_A if (ix + iz) % 2 == 0 else COL_GRASS_B
			if _hash01(float(ix) * 3.7 + 91.0, float(iz) * 5.1 + 91.0) < 0.5:
				_add_bg_facet(st, p00, p10, p11, base)
				_add_bg_facet(st, p00, p11, p01, base)
			else:
				_add_bg_facet(st, p00, p10, p01, base)
				_add_bg_facet(st, p10, p11, p01, base)
	var terrain_mat := _toon_material(Color.WHITE, 0.03, Color(0.08, 0.13, 0.08), 0.05, true, false)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bg_root.add_child(mi)

	var trunk_mat := _toon_material(Color(0.52, 0.34, 0.22), 0.05)
	var canopy_a := _toon_material(Color(0.22, 0.58, 0.26), 0.06)
	var canopy_b := _toon_material(Color(0.32, 0.72, 0.32), 0.06)

	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var placed := 0
	var attempts := 0
	while placed < 620 and attempts < 7000:
		attempts += 1
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(flat_r + 20.0, span_r * 0.92)
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		var h := _bg_height(x, z, flat_r, span_r)
		if h > 85.0:
			continue
		bg_root.add_child(_make_tree(rng, x, z, h,
			trunk_mat, canopy_a if placed % 2 == 0 else canopy_b))
		placed += 1


func _make_tree(rng: RandomNumberGenerator, x: float, z: float, ground_h: float,
		trunk_mat: Material, canopy_mat: Material) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(x, ground_h - 0.4, z)
	root.rotation.y = rng.randf() * TAU
	root.scale = Vector3.ONE * rng.randf_range(0.8, 2.2)

	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.22
	tm.bottom_radius = 0.4
	tm.height = 3.0
	tm.radial_segments = 6
	trunk.mesh = tm
	trunk.position = Vector3(0, 1.5, 0)
	trunk.material_override = trunk_mat
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trunk)

	for layer in [[2.4, 4.2, 3.2], [1.7, 3.0, 5.4]]:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = float(layer[0])
		cm.height = float(layer[1])
		cm.radial_segments = 7
		cone.mesh = cm
		cone.position = Vector3(0, float(layer[2]), 0)
		cone.material_override = canopy_mat
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(cone)

	return root


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
	cam_dist = arena * 1.7
	cam_target = Vector3.ZERO
	cam_yaw = 0.0
	cam_pitch = CAM_PITCH
	free_pos = Vector3(0.0, sin(cam_pitch), cos(cam_pitch)) * cam_dist
	free_yaw = 0.0
	free_pitch = -cam_pitch
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAM_FOV
	camera.near = 1.0
	camera.far = 4000.0
	_update_camera()


func _follow_zoom() -> float:
	return clampf(cam_dist / 250.0, 0.3, 2.4)


func _update_camera() -> void:
	if capture_lock:
		return
	if follow_idx >= 0 and follow_idx < agent_order.size() and last_pose.has(agent_order[follow_idx]):
		var st: Dictionary = last_pose[agent_order[follow_idx]]
		follow_pos = st["pos"]
		follow_yaw = float(st.get("yaw", 0.0))
		_place_follow_cam()
	else:
		camera.position = free_pos
		camera.rotation = Vector3(free_pitch, free_yaw, 0.0)


func _place_follow_cam() -> void:
	if capture_lock:
		return
	var fwd := Vector3(sin(follow_yaw), 0, cos(follow_yaw))
	var zf := _follow_zoom()
	camera.position = follow_pos - fwd * (8.5 * zf) + Vector3(0, 4.2 * zf, 0)
	camera.look_at(follow_pos + Vector3(0, 1.8 * zf, 0))


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


func _free_fwd() -> Vector3:
	return Vector3(-cos(free_pitch) * sin(free_yaw), sin(free_pitch), -cos(free_pitch) * cos(free_yaw))


func _free_right() -> Vector3:
	return Vector3(cos(free_yaw), 0.0, -sin(free_yaw))


func _clamp_free_pos() -> void:
	var lim := arena * 0.5 + 150.0
	free_pos.x = clampf(free_pos.x, -lim, lim)
	free_pos.z = clampf(free_pos.z, -lim, lim)
	free_pos.y = clampf(free_pos.y, 2.0, 600.0)


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
	if event is InputEventMouseMotion:
		if mouse_reset_frames > 0:
			mouse_reset_frames -= 1
			return
		if follow_idx < 0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			free_yaw -= event.relative.x * LOOK_SENS
			free_pitch = clampf(free_pitch - event.relative.y * LOOK_SENS, -1.55, 1.55)
	if event is InputEventMouseButton and event.pressed:
		if follow_idx < 0 and free_cursor_free and event.button_index == MOUSE_BUTTON_LEFT:
			free_cursor_free = false
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if follow_idx < 0:
					free_pos -= _free_fwd() * 40.0
					_clamp_free_pos()
					_update_camera()
				else:
					cam_dist = clampf(cam_dist * 0.9, 60.0, 600.0)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if follow_idx < 0:
					free_pos += _free_fwd() * 40.0
					_clamp_free_pos()
					_update_camera()
				else:
					cam_dist = clampf(cam_dist * 1.1, 60.0, 600.0)
					_update_camera()


func _process(delta: float) -> void:
	if follow_idx < 0 and not match_over and capture_path == "":
		var want := Input.MOUSE_MODE_VISIBLE if free_cursor_free else Input.MOUSE_MODE_CAPTURED
		if Input.mouse_mode != want:
			Input.mouse_mode = want
			mouse_reset_frames = 3
	elif Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_agent_poses()
	if follow_idx < 0 and not match_over:
		var mv := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			mv += _free_fwd()
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			mv -= _free_fwd()
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			mv -= _free_right()
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			mv += _free_right()
		if mv != Vector3.ZERO:
			free_pos += mv.normalized() * 140.0 * delta
		_clamp_free_pos()
		_update_camera()
	elif follow_idx >= 0 and not match_over:
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
		if follow_idx >= 0:
			follow_idx = -1
			free_cursor_free = false
			_refresh_caption()
			_update_camera()
		else:
			free_cursor_free = not free_cursor_free
	esc_was = esc_now
	_roll_agents(delta)
	_animate_agents(delta)
	_update_puffs(delta)
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
	if capture_countdown > 0 and have_map:
		free_yaw = 0.0
		free_pitch = -cam_pitch
		capture_countdown -= 1
		if capture_follow and capture_countdown == 60:
			_cycle_follow()
		if capture_portrait and agent_order.size() > 0 and last_pose.has(agent_order[0]):
			var pid: int = agent_order[0]
			var pp: Vector3 = last_pose[pid]["pos"]
			var pstate: Dictionary = agent_states.get(pid, {})
			var pfacing: Vector3 = pstate.get("facing", Vector3.FORWARD)
			camera.position = pp + pfacing * 2.6 + Vector3(0.0, 4.2, 0.0)
			camera.look_at(pp + Vector3(0.0, 0.6, 0.0), Vector3.UP)
			capture_lock = true
		if capture_countdown == 0:
			_capture_frame.call_deferred()


func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(capture_path)
	get_tree().quit()


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
			(agent_mats[sid] as ShaderMaterial).set_shader_parameter("base_color", base.lerp(Color(1, 1, 1), hfrac * 0.85))


func _animate_agents(delta: float) -> void:
	for sid in agent_states.keys():
		var state: Dictionary = agent_states[sid]
		var node := sphere_nodes.get(sid, null) as Node3D
		if node == null:
			continue
		var v: Vector3 = agent_vel.get(sid, Vector3.ZERO)
		var sp := Vector2(v.x, v.z).length()

		var facing: Vector3 = state["facing"]
		if sp > 0.6:
			var want := Vector3(v.x, 0.0, v.z).normalized()
			facing = facing.lerp(want, clampf(delta * 9.0, 0.0, 1.0)).normalized()
		state["facing"] = facing

		var prev_vy: float = state["prev_vy"]
		var grounded := node.position.y <= sphere_r * 1.08
		var squash: float = state["squash"]
		if grounded and prev_vy < -4.0:
			squash = clampf(-prev_vy * 0.06, 0.3, 1.0)
			_spawn_dust(node.position, Vector3(v.x, 0.0, v.z))
		state["prev_vy"] = v.y
		squash = move_toward(squash, 0.0, delta * 3.4)
		state["squash"] = squash

		var air := clampf((node.position.y - sphere_r) / maxf(jump_h, 0.01), 0.0, 1.0)
		var body_scale := Vector3(
			1.0 - air * 0.07 + squash * 0.38,
			1.0 + air * 0.14 - squash * 0.44,
			1.0 - air * 0.07 + squash * 0.38)
		var mesh := agent_meshes.get(sid, null) as MeshInstance3D
		if mesh != null:
			mesh.scale = body_scale

		var face: Dictionary = agent_faces.get(sid, {})
		if not face.is_empty():
			var face_root := face["root"] as Node3D
			face_root.basis = Basis.looking_at(-facing, Vector3.UP)
			face_root.scale = body_scale

		var limbs: Dictionary = agent_limbs.get(sid, {})
		if not limbs.is_empty():
			var limb_root := limbs["root"] as Node3D
			limb_root.basis = Basis.looking_at(-facing, Vector3.UP)
			var phase: float = state.get("phase", 0.0)
			var swing := sin(phase) * clampf(sp * 0.07, 0.0, 1.0)
			(limbs["leg_l"] as Node3D).rotation.x = swing * 0.85
			(limbs["leg_r"] as Node3D).rotation.x = -swing * 0.85
			(limbs["arm_l"] as Node3D).rotation.x = -swing * 0.65
			(limbs["arm_r"] as Node3D).rotation.x = swing * 0.65

		var blob: Dictionary = agent_blobs.get(sid, {})
		if not blob.is_empty():
			var blob_node := blob["node"] as MeshInstance3D
			var blob_copy := blob["mat"] as ShaderMaterial
			blob_node.position = Vector3(0.0, 0.06 - node.position.y, 0.0)
			blob_node.scale = Vector3.ONE * (1.0 + air * 0.5)
			blob_copy.set_shader_parameter("blob_color", Color(0.09, 0.13, 0.1, 0.5 - air * 0.28))

		var trail_t: float = state["trail"] - delta
		if sp > 8.0 and trail_t <= 0.0:
			trail_t = 0.06
			var team := String(last_info.get(sid, {}).get("team", "?")) if last_info.has(sid) else "?"
			var tint: Color = team_colors.get(team, Color(1, 1, 1))
			_spawn_puff(node.position - facing * sphere_r * 0.95,
				Color(tint.r, tint.g, tint.b, 0.28),
				sphere_r * 1.05, 0.26, Vector3.ZERO, 0.15)
		state["trail"] = trail_t


func _spawn_dust(pos: Vector3, dir: Vector3) -> void:
	var base := pos + Vector3(0.0, -sphere_r * 0.8, 0.0)
	for i in range(6):
		var a := TAU * float(i) / 6.0 + randf() * 0.6
		var off := Vector3(cos(a), 0.0, sin(a)) * sphere_r
		_spawn_puff(base + off, Color(1.0, 0.97, 0.88, 0.6),
			sphere_r * 1.1, 0.42, off.normalized() * 2.4 + Vector3(0.0, 1.2, 0.0), 1.3)


func _spawn_puff(pos: Vector3, color: Color, size: float, life: float,
		vel: Vector3, growth: float) -> void:
	if puffs.size() > 160:
		return
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = puff_shader
	mat.set_shader_parameter("puff_color", color)
	mat.set_shader_parameter("alpha", 1.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.global_position = pos
	puff_root.add_child(mi)
	puffs.append({"node": mi, "mat": mat, "vel": vel, "life": life, "max": life,
		"growth": growth, "size": size})


func _update_puffs(delta: float) -> void:
	var i := puffs.size() - 1
	while i >= 0:
		var p: Dictionary = puffs[i]
		var life: float = p["life"] - delta
		var node := p["node"] as MeshInstance3D
		if life <= 0.0 or node == null:
			if node != null:
				node.queue_free()
			puffs.remove_at(i)
			i -= 1
			continue
		p["life"] = life
		var t := 1.0 - life / float(p["max"])
		var mat := p["mat"] as ShaderMaterial
		mat.set_shader_parameter("alpha", pow(1.0 - t, 1.4))
		node.global_position += (p["vel"] as Vector3) * delta
		var s := float(p["size"]) * (1.0 + float(p["growth"]) * t)
		node.scale = Vector3(s, s, s)
		if camera != null:
			node.look_at(camera.global_position, Vector3.UP)
		i -= 1


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
		var amount := sp * delta / maxf(sphere_r, 0.01)
		(agent_meshes[sid] as MeshInstance3D).rotate(axis, amount)
		var state: Dictionary = agent_states.get(sid, {})
		if not state.is_empty():
			state["phase"] = float(state.get("phase", 0.0)) + amount


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
			"game_over":
				_show_game_over(frame)


func _clear(node: Node3D) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _build_map(frame: Dictionary) -> void:
	_clear(map_root)
	_clear(agent_root)
	_clear(puff_root)
	sphere_nodes.clear()
	flag_nodes.clear()
	flag_banners.clear()
	agent_hist.clear()
	last_info.clear()
	last_pose.clear()
	agent_order.clear()
	agent_grounded.clear()
	agent_carrying.clear()
	agent_faces.clear()
	agent_limbs.clear()
	agent_blobs.clear()
	agent_states.clear()
	puffs.clear()
	last_score.clear()
	follow_idx = -1
	_refresh_caption()

	arena = float(frame.get("arena_size", 200.0))
	sphere_r = float(frame.get("sphere_radius", 1.0))
	jump_h = float(frame.get("max_jump_height", 2.0))
	max_ticks = int(frame.get("max_ticks", 0))
	tick_rate = int(frame.get("tick_rate", 20))
	match_over = false
	if game_over_root != null:
		game_over_root.visible = false
	hud.visible = true
	hint_label.visible = true
	minimap.visible = true
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
		var mat := _toon_material(base, 0.08)
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
	glow_mat.set_shader_parameter("intensity", 0.10)
	glow_plane_mi.material_override = glow_mat
	glow_plane_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_root.add_child(glow_plane_mi)

	var border_mat := _toon_material(Color(0.58, 0.42, 0.88), 0.06)
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

	_spawn_background()

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
			_add_ground_quad(st,
				Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0),
				Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi


func _add_ground_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)


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
	var mat := _toon_material(team_colors.get(team, Color(1, 1, 1)), 0.10)
	mi.material_override = mat
	agent_mats[sid] = mat
	agent_meshes[sid] = mi
	root.add_child(mi)

	var face_root := Node3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = sphere_r * 0.21
	eye_mesh.height = sphere_r * 0.42
	eye_mesh.radial_segments = 18
	eye_mesh.rings = 10
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		var edir := Vector3(sx * 0.42, 0.34, 0.84).normalized()
		eye.position = edir * sphere_r * 0.92
		eye.basis = Basis.looking_at(-edir, Vector3.UP)
		eye.scale = Vector3(1.0, 1.18, 0.36)
		eye.material_override = face_mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		face_root.add_child(eye)
	root.add_child(face_root)
	agent_faces[sid] = {"root": face_root}

	var limb_root := Node3D.new()
	var limb_mesh := CapsuleMesh.new()
	limb_mesh.radius = sphere_r * 0.14
	limb_mesh.height = sphere_r * 0.62
	limb_mesh.radial_segments = 10
	limb_mesh.rings = 4
	var arm_l := MeshInstance3D.new()
	var arm_r := MeshInstance3D.new()
	var leg_l := MeshInstance3D.new()
	var leg_r := MeshInstance3D.new()
	for part in [arm_l, arm_r, leg_l, leg_r]:
		part.mesh = limb_mesh
		part.material_override = mat
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		limb_root.add_child(part)
	arm_l.position = Vector3(-0.76, -0.05, 0.06) * sphere_r
	arm_r.position = Vector3(0.76, -0.05, 0.06) * sphere_r
	arm_l.rotation = Vector3(0.0, 0.0, PI - 0.22)
	arm_r.rotation = Vector3(0.0, 0.0, PI + 0.22)
	leg_l.position = Vector3(-0.30, -0.74, 0.0) * sphere_r
	leg_r.position = Vector3(0.30, -0.74, 0.0) * sphere_r
	leg_l.rotation = Vector3(0.0, 0.0, PI - 0.30)
	leg_r.rotation = Vector3(0.0, 0.0, PI + 0.30)
	root.add_child(limb_root)
	agent_limbs[sid] = {"root": limb_root, "arm_l": arm_l, "arm_r": arm_r,
		"leg_l": leg_l, "leg_r": leg_r}

	var blob := MeshInstance3D.new()
	var blob_quad := QuadMesh.new()
	blob_quad.size = Vector2(sphere_r * 2.8, sphere_r * 2.8)
	blob.mesh = blob_quad
	var blob_copy := blob_mat.duplicate() as ShaderMaterial
	blob.material_override = blob_copy
	blob.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(blob)
	agent_blobs[sid] = {"node": blob, "mat": blob_copy}

	var indicator := Node3D.new()
	indicator.position = Vector3(0, sphere_r * 1.9, 0)
	indicator.visible = false

	var ind_mat := _toon_material(Color.WHITE, 0.05, Color.WHITE, 0.35)
	var ind_chip := MeshInstance3D.new()
	var ind_chip_mesh := BoxMesh.new()
	ind_chip_mesh.size = Vector3(0.22, 0.22, 0.04)
	ind_chip.mesh = ind_chip_mesh
	ind_chip.material_override = ind_mat
	indicator.add_child(ind_chip)

	root.add_child(indicator)
	agent_carry_indicators[sid] = {"root": indicator, "mat": ind_mat, "base_y": sphere_r * 1.9}
	agent_states[sid] = {"facing": Vector3.FORWARD, "squash": 0.0, "prev_vy": 0.0,
		"trail": 0.0, "phase": 0.0}
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


func _show_game_over(frame: Dictionary) -> void:
	match_over = true
	hud.visible = false
	hint_label.visible = false
	minimap.visible = false
	caption.visible = false
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if game_over_layer == null:
		game_over_layer = CanvasLayer.new()
		game_over_layer.layer = 20
		add_child(game_over_layer)
		game_over_root = Control.new()
		game_over_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		game_over_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		game_over_layer.add_child(game_over_root)

		var bg := ColorRect.new()
		bg.color = Color(0.04, 0.04, 0.09, 0.97)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		game_over_root.add_child(bg)

		go_box = VBoxContainer.new()
		go_box.set_anchors_preset(Control.PRESET_CENTER)
		go_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		go_box.grow_vertical = Control.GROW_DIRECTION_BOTH
		go_box.alignment = BoxContainer.ALIGNMENT_CENTER
		go_box.add_theme_constant_override("separation", 14)
		go_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		game_over_root.add_child(go_box)

		var over := Label.new()
		over.text = "MATCH COMPLETE"
		var over_ls := LabelSettings.new()
		over_ls.font_size = 28
		over_ls.font_color = Color(0.8, 0.82, 0.95, 0.7)
		over.label_settings = over_ls
		over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		go_box.add_child(over)

		winner_label = Label.new()
		go_winner_ls = LabelSettings.new()
		go_winner_ls.font_size = 84
		go_winner_ls.outline_size = 16
		go_winner_ls.outline_color = Color(0.02, 0.02, 0.06, 0.95)
		go_winner_ls.shadow_size = 18
		go_winner_ls.shadow_color = Color(0, 0, 0, 0.55)
		go_winner_ls.shadow_offset = Vector2(0, 6)
		winner_label.label_settings = go_winner_ls
		winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		go_box.add_child(winner_label)

		sub_label = Label.new()
		var sub_ls := LabelSettings.new()
		sub_ls.font_size = 26
		sub_ls.font_color = Color(0.9, 0.9, 0.98, 0.85)
		sub_label.label_settings = sub_ls
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		go_box.add_child(sub_label)

		var divider := ColorRect.new()
		divider.custom_minimum_size = Vector2(340, 2)
		divider.color = Color(1, 1, 1, 0.18)
		divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		go_box.add_child(divider)

		score_box = VBoxContainer.new()
		score_box.alignment = BoxContainer.ALIGNMENT_CENTER
		score_box.add_theme_constant_override("separation", 6)
		go_box.add_child(score_box)

		foot_label = Label.new()
		var foot_ls := LabelSettings.new()
		foot_ls.font_size = 16
		foot_ls.font_color = Color(1, 1, 1, 0.45)
		foot_label.label_settings = foot_ls
		foot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		go_box.add_child(foot_label)

	var winner_raw = frame.get("winner")
	var winner := String(winner_raw) if typeof(winner_raw) == TYPE_STRING else ""
	if winner != "":
		winner_label.text = winner.to_upper()
		go_winner_ls.font_color = team_colors.get(winner, Color.WHITE)
		sub_label.text = "WINS THE MATCH"
	else:
		winner_label.text = "DRAW"
		go_winner_ls.font_color = Color(0.92, 0.92, 0.98)
		sub_label.text = "A stalemate."

	for child in score_box.get_children():
		score_box.remove_child(child)
		child.queue_free()
	var sc: Dictionary = frame.get("score", {})
	var entries: Array = []
	for k in sc.keys():
		entries.append([String(k), int(sc[k])])
	entries.sort_custom(func(a, b): return a[1] > b[1])
	for e in entries:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.color = team_colors.get(e[0], Color.WHITE)
		row.add_child(sw)
		var lbl := Label.new()
		lbl.text = "%s    %d" % [e[0].to_upper(), e[1]]
		var ls := LabelSettings.new()
		ls.font_size = 22
		ls.font_color = Color(0.95, 0.95, 1.0, 0.9)
		lbl.label_settings = ls
		row.add_child(lbl)
		score_box.add_child(row)

	game_over_root.visible = true
	game_over_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(game_over_root, "modulate:a", 1.0, 0.6)


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
				var ind_mat := indicator["mat"] as ShaderMaterial
				ind_mat.set_shader_parameter("base_color", carry_color)
				ind_mat.set_shader_parameter("emission_color", carry_color)
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
	var time_txt := "tick %d" % tick
	if max_ticks > 0:
		var remain_s := maxi(0, int(ceil(float(max_ticks - tick) / float(tick_rate))))
		time_txt = "%d:%02d left" % [int(remain_s / 60.0), remain_s % 60]
	hud.text = "%s   %s" % [time_txt, score_txt]
