extends Node3D
## Top-down 3D viewer for the exml26 match sim.
##
## Run the bridge first, then press Play:
##     python3 tools/godot_bridge.py --seed 7
## The bridge streams newline-delimited JSON (`map` frame, then `tick`
## frames, same schema as data/telemetry/*.jsonl). This client renders the
## newest tick it has every frame. Coordinate map: engine (x, y, z) ->
## Godot (x, z, y), so +y ("down" on the 2D debug viewer) is +Z here.

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
const VIEW_VERSION := 6

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
var enter_was := false
var esc_was := false

var map_root: Node3D
var agent_root: Node3D
var camera: Camera3D
var hud: Label

var team_mats := {}
var team_colors := {}
var agent_mats := {}
var sphere_nodes := {}
var flag_nodes := {}
var obstacle_mat: StandardMaterial3D
var ground_mat: StandardMaterial3D
var ramp_mat: StandardMaterial3D


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
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0

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
	hint.text = "v6: drag/WASD to orbit · Enter: follow agent · Esc: free cam"
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

	obstacle_mat = StandardMaterial3D.new()
	obstacle_mat.albedo_color = Color(0.35, 0.35, 0.38)
	obstacle_mat.emission_enabled = false
	obstacle_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground_mat = StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.08, 0.09, 0.11)
	ground_mat.emission_enabled = false
	ramp_mat = StandardMaterial3D.new()
	ramp_mat.albedo_color = Color(0.9, 0.55, 0.16)
	ramp_mat.emission_enabled = false
	ramp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	tcp.connect_to_host(host, port)


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


func _update_camera() -> void:
	if follow_idx >= 0 and follow_idx < agent_order.size() and last_pose.has(agent_order[follow_idx]):
		var st: Dictionary = last_pose[agent_order[follow_idx]]
		var pos: Vector3 = st["pos"]
		var fwd := Vector3(sin(st["yaw"]), 0, cos(st["yaw"]))
		camera.position = pos - fwd * 9.0 + Vector3(0, 6.0, 0)
		camera.look_at(pos + fwd * 6.0 + Vector3(0, 1.0, 0))
	else:
		var cp := cos(cam_pitch)
		var offset := Vector3(sin(cam_yaw) * cp, sin(cam_pitch), cos(cam_yaw) * cp) * cam_dist
		camera.position = cam_target + offset
		camera.look_at(cam_target)


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
	cam_yaw += rel.x * ORBIT_SENS
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


func _process(delta: float) -> void:
	if follow_idx < 0:
		var mp := get_viewport().get_mouse_position()
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if have_mp:
				_orbit_by(mp - last_mp)
			last_mp = mp
			have_mp = true
		else:
			have_mp = false
		var kd := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			kd.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			kd.x += 1.0
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			kd.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			kd.y += 1.0
		if kd != Vector2.ZERO:
			_orbit_by(kd.normalized() * 500.0 * delta)
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
	if follow_idx >= 0:
		_update_camera()
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
	last_info.clear()
	last_pose.clear()
	agent_order.clear()
	follow_idx = -1
	_refresh_caption()

	arena = float(frame.get("arena_size", 200.0))
	sphere_r = float(frame.get("sphere_radius", 1.0))
	jump_h = float(frame.get("max_jump_height", 2.0))
	_setup_camera()

	team_mats.clear()
	team_colors.clear()
	agent_mats.clear()
	for t in frame.get("teams", []):
		var base := Color(String(t.get("color", "#ffffff")))
		team_colors[String(t.get("name", "?"))] = base
		var mat := StandardMaterial3D.new()
		mat.albedo_color = base
		mat.emission_enabled = false
		mat.roughness = 0.55
		team_mats[String(t.get("name", "?"))] = mat

	var half := arena * 0.5
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(arena, arena)
	ground.mesh = plane
	ground.material_override = ground_mat
	map_root.add_child(ground)

	var border_mat := StandardMaterial3D.new()
	border_mat.albedo_color = Color(0.5, 0.5, 0.55)
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

	for o in frame.get("obstacles", []):
		map_root.add_child(_prism(o.get("points", []), float(o.get("height", 1.0))))

	for r in frame.get("ramps", []):
		map_root.add_child(_wedge(float(r.get("cx", 0.0)), float(r.get("cy", 0.0)),
			float(r.get("dx", 1.0)), float(r.get("dy", 0.0)),
			float(r.get("length", 10.0)), float(r.get("width", 5.0)), float(r.get("height", 3.0))))

	for f in frame.get("flags", []):
		flag_nodes[String(f.get("team", "?"))] = _make_flag(f)

	have_map = true


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
		var a1 := Vector3(ax, height, az)
		var b1 := Vector3(bx, height, bz)
		st.set_normal(normal)
		st.add_vertex(a0)
		st.add_vertex(b0)
		st.add_vertex(b1)
		st.add_vertex(a0)
		st.add_vertex(b1)
		st.add_vertex(a1)
	var c := Vector3(cx, height, cz)
	for i in range(n):
		var a := Vector3(float(points[i][0]), height, float(points[i][1]))
		var b := Vector3(float(points[(i + 1) % n][0]), height, float(points[(i + 1) % n][1]))
		st.set_normal(Vector3(0, 1, 0))
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(b)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi


func _wedge(cx: float, cy: float, dx: float, dz: float, length: float, width: float, height: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(ramp_mat)
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
	# slope
	var slope_n := (Vector3(0, 1, 0) - a * (height / maxf(length, 0.01))).normalized()
	st.set_normal(slope_n)
	st.add_vertex(low_l)
	st.add_vertex(low_r)
	st.add_vertex(high_r)
	st.add_vertex(low_l)
	st.add_vertex(high_r)
	st.add_vertex(high_l)
	# sides
	st.set_normal(-s)
	st.add_vertex(low_l)
	st.add_vertex(high_l0)
	st.add_vertex(high_l)
	st.set_normal(s)
	st.add_vertex(low_r)
	st.add_vertex(high_r)
	st.add_vertex(high_r0)
	# tall back face at the high end
	st.set_normal(a)
	st.add_vertex(high_l0)
	st.add_vertex(high_r0)
	st.add_vertex(high_r)
	st.add_vertex(high_l0)
	st.add_vertex(high_r)
	st.add_vertex(high_l)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi


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
	mat.emission_enabled = false
	mat.roughness = 0.55
	mi.material_override = mat
	agent_mats[sid] = mat
	root.add_child(mi)
	return root


func _make_flag(f: Dictionary) -> MeshInstance3D:
	var team := String(f.get("team", "?"))
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 3.0, 2.0)
	mi.mesh = box
	mi.material_override = team_mats.get(team, obstacle_mat)
	mi.position = Vector3(float(f.get("x", 0.0)), 1.5, float(f.get("y", 0.0)))
	map_root.add_child(mi)
	return mi


func _apply_tick(frame: Dictionary) -> void:
	if not have_map:
		return
	var tick := int(frame.get("tick", 0))
	for s in frame.get("spheres", []):
		var sid := int(s.get("id", -1))
		var team := String(s.get("team", "?"))
		var player := int(s.get("player", 0))
		var node := sphere_nodes.get(sid, null) as Node3D
		if node == null:
			node = _make_agent(sid, team, player)
			agent_root.add_child(node)
			sphere_nodes[sid] = node
		var sy := float(s.get("z", 0.0))
		node.position = Vector3(float(s.get("x", 0.0)), sy, float(s.get("y", 0.0)))
		node.visible = bool(s.get("alive", true))
		var hfrac := clampf((sy - sphere_r) / maxf(jump_h, 0.01), 0.0, 1.0)
		var base: Color = team_colors.get(team, Color(1, 1, 1))
		(agent_mats[sid] as StandardMaterial3D).albedo_color = base.lerp(Color(1, 1, 1), hfrac * 0.85)
		last_info[sid] = {"team": team, "player": player}
		last_pose[sid] = {"pos": node.position, "yaw": float(s.get("yaw", 0.0))}
	_refresh_order()
	_refresh_caption()
	for f in frame.get("flags", []):
		var team := String(f.get("team", "?"))
		if flag_nodes.has(team):
			(flag_nodes[team] as Node3D).position = Vector3(float(f.get("x", 0.0)), 1.5, float(f.get("y", 0.0)))
	var sc: Dictionary = frame.get("score", {})
	var order: Array = sc.keys()
	order.sort()
	var parts: Array = []
	for k in order:
		parts.append("%s %d" % [String(k).to_upper(), int(sc[k])])
	var score_txt := " · ".join(parts) if not parts.is_empty() else "-"
	hud.text = "tick %d   %s   orb (%.2f, %.2f) mb%d" % [tick, score_txt, cam_yaw, cam_pitch, int(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))]
