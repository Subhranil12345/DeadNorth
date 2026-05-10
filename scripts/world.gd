extends Node3D

# Builds a wide static survival level on _ready and runs the zombie spawner.
# Trees and cabins are scattered with density falling off from the player's
# spawn so the world feels populated nearby and lonely in the wilderness.

@export var zombie_scene: PackedScene
@export var max_alive: int = 8
@export var initial_wave: int = 5
@export var spawn_interval: float = 3.0
@export var night_spawn_interval: float = 1.6
@export var spawn_radius_min: float = 14.0
@export var spawn_radius_max: float = 32.0
@export var arena_half_x: float = 8000.0  # 16 km wide
@export var arena_half_z: float = 6000.0  # 12 km deep

var _spawn_timer: float = 0.0
var _is_night: bool = false

# Safe zone — populated in _build_safe_zone.
var _safe_zone: Node3D = null
const SAFE_ZONE_RADIUS: float = 16.0
const SAFE_ZONE_BUFFER: float = 4.0  # extra clearance for spawns
const VEHICLE_SPAWN_OFFSET: Vector3 = Vector3(7.0, 0.5, 6.0)
const OBJECTIVE_POS: Vector3 = Vector3(5200.0, 0.0, -4300.0)
const SHELTER_WOOD_COST: int = 10
const SHELTER_STONE_COST: int = 4
var _vehicle: Node = null

# Weather + phase
var _weather_timer: float = 0.0
const WEATHER_CYCLE_SECS: float = 90.0  # weather rolls every ~1.5 minutes
var _world_env_path: NodePath = NodePath("../WorldEnvironment")
var _boss_spawned: bool = false
var _defense_started: bool = false
var _remote_players: Dictionary = {}
var _objective_reached: bool = false


# -- Zombie roster --------------------------------------------------------

const ZOMBIE_TYPES: Array = [
	{
		"name": "Walker",
		"scale": 1.0,
		"body_color": Color(0.28, 0.44, 0.34),
		"skin_color": Color(0.58, 0.72, 0.66),
		"eye_color": Color(1.0, 0.28, 0.18),
		"hp": 60.0,
		"speed": 2.6,
		"damage": 12.0,
		"weight": 30,
	},
	{
		"name": "Runner",
		"scale": 0.85,
		"body_color": Color(0.63, 0.34, 0.24),
		"skin_color": Color(0.82, 0.62, 0.48),
		"eye_color": Color(1.0, 0.56, 0.12),
		"hp": 35.0,
		"speed": 4.6,
		"damage": 9.0,
		"weight": 22,
	},
	{
		"name": "Brute",
		"scale": 1.55,
		"body_color": Color(0.22, 0.31, 0.25),
		"skin_color": Color(0.46, 0.58, 0.48),
		"eye_color": Color(1.0, 0.18, 0.1),
		"hp": 200.0,
		"speed": 1.6,
		"damage": 28.0,
		"weight": 7,
	},
	{
		"name": "Crawler",
		"scale": 0.55,
		"body_color": Color(0.62, 0.45, 0.28),
		"skin_color": Color(0.78, 0.58, 0.42),
		"eye_color": Color(1.0, 0.5, 0.1),
		"hp": 25.0,
		"speed": 3.6,
		"damage": 6.0,
		"weight": 13,
	},
	{
		"name": "Shrieker",
		"scale": 1.2,
		"body_color": Color(0.34, 0.25, 0.5),
		"skin_color": Color(0.62, 0.54, 0.78),
		"eye_color": Color(0.9, 0.22, 1.0),
		"hp": 50.0,
		"speed": 2.9,
		"damage": 10.0,
		"weight": 7,
	},
	{
		"name": "Bloater",
		"scale": 1.7,
		"body_color": Color(0.48, 0.58, 0.28),
		"skin_color": Color(0.64, 0.76, 0.45),
		"eye_color": Color(0.85, 1.0, 0.2),
		"hp": 130.0,
		"speed": 1.4,
		"damage": 20.0,
		"weight": 6,
	},
	{
		"name": "Stalker",
		"scale": 1.05,
		"body_color": Color(0.12, 0.18, 0.27),
		"skin_color": Color(0.36, 0.43, 0.56),
		"eye_color": Color(1.0, 0.05, 0.05),
		"hp": 80.0,
		"speed": 3.6,
		"damage": 16.0,
		"weight": 10,
	},
	{
		"name": "Husk",
		"scale": 1.1,
		"body_color": Color(0.46, 0.68, 0.82),
		"skin_color": Color(0.78, 0.9, 0.96),
		"eye_color": Color(0.4, 0.85, 1.0),
		"hp": 130.0,
		"speed": 1.8,
		"damage": 14.0,
		"weight": 5,
	},
	{
		"name": "Wolf",
		"rig": "wolf",
		"scale": 0.9,
		"body_color": Color(0.22, 0.25, 0.28),
		"skin_color": Color(0.58, 0.62, 0.62),
		"eye_color": Color(1.0, 0.35, 0.12),
		"hp": 48.0,
		"speed": 5.2,
		"damage": 13.0,
		"weight": 11,
	},
	{
		"name": "Tiger",
		"rig": "tiger",
		"scale": 1.25,
		"body_color": Color(0.9, 0.46, 0.14),
		"skin_color": Color(0.96, 0.76, 0.34),
		"eye_color": Color(1.0, 0.9, 0.35),
		"hp": 125.0,
		"speed": 4.4,
		"damage": 24.0,
		"weight": 4,
	},
	{
		"name": "Giant Spider",
		"rig": "spider",
		"scale": 1.05,
		"body_color": Color(0.12, 0.09, 0.13),
		"skin_color": Color(0.32, 0.12, 0.32),
		"eye_color": Color(0.9, 0.2, 1.0),
		"hp": 70.0,
		"speed": 3.8,
		"damage": 15.0,
		"weight": 8,
	},
	{
		"name": "Frost Beetle",
		"rig": "beetle",
		"scale": 0.95,
		"body_color": Color(0.12, 0.34, 0.42),
		"skin_color": Color(0.46, 0.85, 0.9),
		"eye_color": Color(0.35, 1.0, 0.9),
		"hp": 90.0,
		"speed": 2.4,
		"damage": 17.0,
		"weight": 7,
	},
]


func _ready() -> void:
	GameManager.reset_game()
	randomize()
	_build_level()
	for i in initial_wave:
		_spawn_zombie()

	# Hook the day/night cycle if it exists.
	var dn := get_node_or_null("../DayNight")
	if dn and dn.has_signal("phase_changed"):
		dn.phase_changed.connect(_on_phase_changed)

	GameManager.world_state_changed.connect(_on_world_state_changed)
	GameManager.weather_changed.connect(_on_weather_changed)
	GameManager.phase_changed.connect(_on_phase_changed_run)
	if MultiplayerManager.is_multiplayer_active():
		MultiplayerManager.remote_player_state.connect(_on_remote_player_state)
		MultiplayerManager.remote_player_left.connect(_on_remote_player_left)
	# Snap environment to whatever weather reset_game just rolled (always clear).
	_apply_weather(GameManager.weather)


func _on_phase_changed(_t: float, phase_name: String) -> void:
	_is_night = phase_name == "night"


# -- Weather --------------------------------------------------------------

func _on_weather_changed(weather_name: String) -> void:
	_apply_weather(weather_name)


func _apply_weather(weather_name: String) -> void:
	var def: Dictionary = GameManager.WEATHER_DEFS.get(weather_name, GameManager.WEATHER_DEFS["clear"])
	var env_holder := get_node_or_null(_world_env_path) as WorldEnvironment
	if env_holder == null or env_holder.environment == null:
		return
	var env: Environment = env_holder.environment
	env.fog_density = float(def.get("fog_density", 0.008))
	env.fog_light_color = def.get("fog_color", Color(0.78, 0.83, 0.9))


func _tick_weather(delta: float) -> void:
	if GameManager.game_over:
		return
	_weather_timer += delta
	if _weather_timer < WEATHER_CYCLE_SECS:
		return
	_weather_timer = 0.0
	# Walk along WEATHER_ORDER with a small chance of skipping ahead.
	var order: Array = GameManager.WEATHER_ORDER
	var idx: int = (GameManager.weather_index + 1) % order.size()
	if randf() < 0.2:
		idx = (idx + 1) % order.size()
	GameManager.weather_index = idx
	GameManager.set_weather(String(order[idx]))


# -- Run phase ------------------------------------------------------------

func _on_phase_changed_run(phase_name: String) -> void:
	if phase_name == "regroup":
		_spawn_timer = max(_spawn_timer, 2.0)
	elif phase_name == "defend":
		if _defense_started:
			return
		_defense_started = true
		# Push the spawner harder during the siege.
		max_alive += 4
		spawn_interval = max(1.0, spawn_interval * 0.7)
		night_spawn_interval = max(0.8, night_spawn_interval * 0.8)
		for i in 4:
			_spawn_zombie(true)
	elif phase_name == "boss":
		_spawn_boss()


# -- Level build ----------------------------------------------------------

func _build_level() -> void:
	var level := Node3D.new()
	level.name = "Level"
	add_child(level)

	_build_ground(level)
	_build_biomes(level)
	_build_walls(level)
	_build_buildings(level)
	_build_trees(level)
	_scatter_set_dressing(level)
	_build_mines_and_pickups(level)
	_build_objective(level)
	_build_safe_zone(level)
	_scatter_loot(level)


func _build_ground(parent: Node3D) -> void:
	var sb := StaticBody3D.new()
	sb.name = "Ground"
	sb.collision_layer = 1
	sb.collision_mask = 0
	parent.add_child(sb)

	var shape := BoxShape3D.new()
	shape.size = Vector3(arena_half_x * 2.0, 1.0, arena_half_z * 2.0)
	var coll := CollisionShape3D.new()
	coll.shape = shape
	coll.position = Vector3(0, -0.5, 0)
	sb.add_child(coll)

	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(arena_half_x * 2.0, arena_half_z * 2.0)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	mesh_inst.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.74, 0.82, 0.86, 1.0)
	mat.roughness = 0.95
	mesh_inst.material_override = mat
	sb.add_child(mesh_inst)


func get_biome_at(pos: Vector3) -> String:
	if pos.x > arena_half_x * 0.7:
		return "ocean"
	if absf(pos.x * 0.3 + pos.z - 900.0) < 190.0:
		return "river"
	if pos.x < -arena_half_x * 0.45:
		return "desert"
	if pos.z > arena_half_z * 0.5:
		return "plains"
	if pos.z < -arena_half_z * 0.55:
		return "autumn"
	return "snow"


func _build_biomes(parent: Node3D) -> void:
	_add_biome_patch(parent, Vector3(-5850, 0, 0), Vector2(4300, arena_half_z * 2.0), Color(0.74, 0.62, 0.38), "Desert")
	_add_biome_patch(parent, Vector3(0, 0, 4550), Vector2(11200, 2900), Color(0.34, 0.52, 0.32), "Plains")
	_add_biome_patch(parent, Vector3(0, 0, -4700), Vector2(11200, 2600), Color(0.56, 0.36, 0.18), "AutumnWoods")
	_add_biome_patch(parent, Vector3(6900, 0, 0), Vector2(2200, arena_half_z * 2.0), Color(0.1, 0.32, 0.46, 0.86), "Ocean", true)
	for i in 13:
		var x := -5400.0 + i * 900.0
		var z := 900.0 - x * 0.3
		_add_biome_patch(parent, Vector3(x, 0, z), Vector2(720, 520), Color(0.08, 0.38, 0.52, 0.82), "River", true)
	_build_aquatic_life(parent)


func _add_biome_patch(parent: Node3D, center: Vector3, size: Vector2, color: Color, patch_name: String, transparent: bool = false) -> void:
	var patch := MeshInstance3D.new()
	patch.name = patch_name
	var plane := PlaneMesh.new()
	plane.size = size
	patch.mesh = plane
	patch.position = Vector3(center.x, 0.025, center.z)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.96
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(color.r * 0.35, color.g * 0.45, color.b * 0.55)
		mat.emission_energy_multiplier = 0.35
	patch.material_override = mat
	parent.add_child(patch)


func _build_aquatic_life(parent: Node3D) -> void:
	var water := Node3D.new()
	water.name = "AquaticLife"
	parent.add_child(water)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7712
	for i in 30:
		var p := Vector3(rng.randf_range(6050.0, 7600.0), 0.18, rng.randf_range(-5200.0, 5400.0))
		_make_fish_school(water, p, rng.randf_range(0.75, 1.25), Color(0.32, 0.74, 0.82))
	for i in 18:
		var x := rng.randf_range(-4800.0, 4400.0)
		var p := Vector3(x, 0.18, 900.0 - x * 0.3 + rng.randf_range(-90.0, 90.0))
		_make_fish_school(water, p, rng.randf_range(0.55, 0.9), Color(0.75, 0.58, 0.28))
	for i in 7:
		var p := Vector3(rng.randf_range(6200.0, 7600.0), 0.08, rng.randf_range(-5000.0, 5000.0))
		_make_water_monster(water, p, rng.randf_range(1.2, 1.8))


func _make_fish_school(parent: Node3D, pos: Vector3, scl: float, color: Color) -> void:
	var fish := Node3D.new()
	fish.position = pos
	fish.rotation.y = randf() * TAU
	parent.add_child(fish)
	_add_box(fish, Vector3(0.7, 0.18, 0.26) * scl, Vector3.ZERO, color, "FishBody")
	_add_box(fish, Vector3(0.15, 0.28, 0.1) * scl, Vector3(-0.42 * scl, 0, 0), color.darkened(0.25), "FishTail")
	_add_box(fish, Vector3(0.16, 0.06, 0.32) * scl, Vector3(0.1 * scl, 0.13 * scl, 0), color.darkened(0.35), "FishFin")


func _make_water_monster(parent: Node3D, pos: Vector3, scl: float) -> void:
	var monster := Node3D.new()
	monster.name = "UnderwaterMonster"
	monster.position = pos
	monster.rotation.y = randf() * TAU
	parent.add_child(monster)
	_add_box(monster, Vector3(1.8, 0.45, 0.62) * scl, Vector3(0, 0.04, 0), Color(0.07, 0.14, 0.16), "MonsterBody")
	_add_box(monster, Vector3(0.5, 0.24, 0.5) * scl, Vector3(0.95 * scl, 0.04, 0), Color(0.06, 0.1, 0.12), "MonsterHead")
	_add_glow_box(monster, Vector3(0.08, 0.08, 0.08) * scl, Vector3(1.22 * scl, 0.14, -0.16 * scl), Color(0.4, 1.0, 0.78), 1.8)
	_add_glow_box(monster, Vector3(0.08, 0.08, 0.08) * scl, Vector3(1.22 * scl, 0.14, 0.16 * scl), Color(0.4, 1.0, 0.78), 1.8)


func _build_walls(parent: Node3D) -> void:
	var height := 6.0
	var thickness := 2.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.22, 0.26, 1.0)
	mat.roughness = 0.95

	var walls := [
		[Vector3(0, height * 0.5, -arena_half_z), Vector3(arena_half_x * 2.0 + thickness, height, thickness)],
		[Vector3(0, height * 0.5, arena_half_z), Vector3(arena_half_x * 2.0 + thickness, height, thickness)],
		[Vector3(-arena_half_x, height * 0.5, 0), Vector3(thickness, height, arena_half_z * 2.0)],
		[Vector3(arena_half_x, height * 0.5, 0), Vector3(thickness, height, arena_half_z * 2.0)],
	]
	for w in walls:
		var pos: Vector3 = w[0]
		var size: Vector3 = w[1]
		var sb := StaticBody3D.new()
		sb.position = pos
		parent.add_child(sb)

		var shape := BoxShape3D.new()
		shape.size = size
		var coll := CollisionShape3D.new()
		coll.shape = shape
		sb.add_child(coll)

		var mesh_inst := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mesh_inst.mesh = bm
		mesh_inst.material_override = mat
		sb.add_child(mesh_inst)


func _style_mat(c: Color, rough: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = rough
	mat.metallic = metallic
	return mat


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, node_name: String = "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	if node_name != "":
		m.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	m.material_override = _style_mat(color)
	parent.add_child(m)
	return m


func _add_glow_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, energy: float = 0.8) -> MeshInstance3D:
	var m := _add_box(parent, size, pos, color)
	var mat := m.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return m


func _add_cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, node_name: String = "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	if node_name != "":
		m.name = node_name
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 8
	m.mesh = cm
	m.position = pos
	m.material_override = _style_mat(color)
	parent.add_child(m)
	return m


func _build_buildings(parent: Node3D) -> void:
	# Anchored cabins near spawn so the player has cover immediately.
	var anchor: Array[Array] = [
		[Vector3(-15, 0, -10), 0.0],
		[Vector3(18, 0, -8), -PI / 8.0],
		[Vector3(-12, 0, 18), PI / 6.0],
		[Vector3(20, 0, 19), -PI / 3.0],
	]
	for entry in anchor:
		_make_cabin(parent, entry[0], entry[1])

	# Scattered houses out into the widened wilderness.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9182
	var scattered := 44
	var placed := 0
	var attempts := 0
	while placed < scattered and attempts < scattered * 12:
		attempts += 1
		var radius := rng.randf_range(80.0, 5600.0)
		var angle := rng.randf() * TAU
		var p := Vector3(cos(angle) * radius, 0, sin(angle) * radius * 0.82)
		if abs(p.x) > arena_half_x - 30 or abs(p.z) > arena_half_z - 30:
			continue
		# Avoid overlapping anchor cabins.
		var ok := true
		for entry in anchor:
			if (entry[0] as Vector3).distance_to(p) < 14.0:
				ok = false
				break
		if not ok:
			continue
		if placed % 3 == 0:
			_make_enterable_house(parent, p, rng.randf() * TAU)
		else:
			_make_cabin(parent, p, rng.randf() * TAU)
		placed += 1


func _make_cabin(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var w := 6.0
	var h := 3.4
	var d := 5.0

	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation.y = yaw
	parent.add_child(sb)

	var shape := BoxShape3D.new()
	shape.size = Vector3(w, h, d)
	var coll := CollisionShape3D.new()
	coll.shape = shape
	coll.position = Vector3(0, h * 0.5, 0)
	sb.add_child(coll)

	var wall_mesh := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(w, h, d)
	wall_mesh.mesh = wm
	wall_mesh.position = Vector3(0, h * 0.5, 0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.5, 0.34, 0.22, 1.0)
	wmat.roughness = 0.9
	wall_mesh.material_override = wmat
	sb.add_child(wall_mesh)

	var roof_h := 1.6
	var roof_mesh := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(w + 0.4, roof_h, d + 0.4)
	roof_mesh.mesh = prism
	roof_mesh.position = Vector3(0, h + roof_h * 0.5, 0)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.16, 0.19, 0.22, 1.0)
	rmat.roughness = 0.9
	roof_mesh.material_override = rmat
	sb.add_child(roof_mesh)

	var snow_cap := MeshInstance3D.new()
	var snow_prism := PrismMesh.new()
	snow_prism.size = Vector3(w + 0.65, 0.22, d + 0.65)
	snow_cap.mesh = snow_prism
	snow_cap.position = Vector3(0, h + roof_h + 0.15, 0)
	snow_cap.material_override = _style_mat(Color(0.84, 0.9, 0.92), 0.98)
	sb.add_child(snow_cap)

	var door_mesh := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(1.0, 1.9, 0.05)
	door_mesh.mesh = dm
	door_mesh.position = Vector3(0, 0.95, -d * 0.5 - 0.03)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.14, 0.1, 0.08, 1.0)
	dmat.roughness = 0.9
	door_mesh.material_override = dmat
	sb.add_child(door_mesh)

	_add_box(sb, Vector3(1.18, 0.12, 0.12), Vector3(0, 1.9, -d * 0.5 - 0.08), Color(0.74, 0.58, 0.34))
	_add_box(sb, Vector3(0.12, 2.1, 0.12), Vector3(-0.6, 1.05, -d * 0.5 - 0.08), Color(0.74, 0.58, 0.34))
	_add_box(sb, Vector3(0.12, 2.1, 0.12), Vector3(0.6, 1.05, -d * 0.5 - 0.08), Color(0.74, 0.58, 0.34))

	for x in [-1.75, 1.75]:
		_add_glow_box(sb, Vector3(0.82, 0.62, 0.08), Vector3(x, 1.95, -d * 0.5 - 0.07), Color(0.5, 0.82, 0.95), 0.55)
		_add_box(sb, Vector3(0.96, 0.1, 0.12), Vector3(x, 2.31, -d * 0.5 - 0.09), Color(0.18, 0.12, 0.08))
		_add_box(sb, Vector3(0.96, 0.1, 0.12), Vector3(x, 1.59, -d * 0.5 - 0.09), Color(0.18, 0.12, 0.08))
		_add_box(sb, Vector3(0.1, 0.78, 0.12), Vector3(x - 0.48, 1.95, -d * 0.5 - 0.09), Color(0.18, 0.12, 0.08))
		_add_box(sb, Vector3(0.1, 0.78, 0.12), Vector3(x + 0.48, 1.95, -d * 0.5 - 0.09), Color(0.18, 0.12, 0.08))

	_add_box(sb, Vector3(0.55, 1.0, 0.55), Vector3(w * 0.28, h + roof_h + 0.45, d * 0.08), Color(0.18, 0.16, 0.14), "Chimney")
	_add_box(sb, Vector3(w + 0.25, 0.18, 0.18), Vector3(0, 0.18, -d * 0.5 - 0.12), Color(0.22, 0.16, 0.1), "FrontSkid")


func _make_enterable_house(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var house := Node3D.new()
	house.name = "EnterableHouse"
	house.position = pos
	house.rotation.y = yaw
	parent.add_child(house)

	var w := 7.2
	var h := 3.0
	var d := 6.2
	var wall_color := Color(0.43, 0.28, 0.18)
	var trim_color := Color(0.16, 0.11, 0.08)
	_add_box(house, Vector3(w, 0.12, d), Vector3(0, 0.06, 0), Color(0.25, 0.2, 0.16), "HouseFloor")
	_make_fence(house, Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, 0.22), wall_color)
	_make_fence(house, Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.22, h, d), wall_color)
	_make_fence(house, Vector3(w * 0.5, h * 0.5, 0), Vector3(0.22, h, d), wall_color)
	var door_gap := 1.7
	var side_len := (w - door_gap) * 0.5
	var side_off := (w + door_gap) * 0.25
	_make_fence(house, Vector3(-side_off, h * 0.5, -d * 0.5), Vector3(side_len, h, 0.22), wall_color)
	_make_fence(house, Vector3(side_off, h * 0.5, -d * 0.5), Vector3(side_len, h, 0.22), wall_color)
	_add_box(house, Vector3(w + 0.8, 0.42, d + 0.8), Vector3(0, h + 0.35, 0), Color(0.14, 0.16, 0.17), "FlatRoof")
	_add_box(house, Vector3(w + 1.0, 0.14, d + 1.0), Vector3(0, h + 0.63, 0), Color(0.82, 0.86, 0.82), "SeasonDusting")
	_add_box(house, Vector3(1.4, 0.16, 0.16), Vector3(0, 2.1, -d * 0.5 - 0.08), trim_color, "DoorHeader")
	_add_box(house, Vector3(1.3, 0.55, 0.8), Vector3(1.8, 0.35, 1.2), Color(0.22, 0.14, 0.08), "Table")
	_add_box(house, Vector3(1.8, 0.32, 0.78), Vector3(-2.0, 0.22, 1.6), Color(0.26, 0.24, 0.22), "Bed")
	_add_glow_box(house, Vector3(0.32, 0.28, 0.32), Vector3(0, 2.55, 1.8), Color(1.0, 0.72, 0.38), 1.1)


func _build_trees(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	# Trees are scattered across the map with a density falloff. Most cluster
	# near the player's spawn; the deep wilderness is sparse.
	_scatter_trees(parent, rng, 180, 8.0, 200.0)
	_scatter_trees(parent, rng, 140, 200.0, 600.0)
	_scatter_trees(parent, rng, 80, 600.0, 1500.0)
	_scatter_trees(parent, rng, 160, 1500.0, 5200.0)


func _scatter_trees(parent: Node3D, rng: RandomNumberGenerator, count: int, r_min: float, r_max: float) -> void:
	var attempts := 0
	var placed := 0
	while placed < count and attempts < count * 5:
		attempts += 1
		var angle := rng.randf() * TAU
		var r := rng.randf_range(r_min, r_max)
		var pos := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		if abs(pos.x) > arena_half_x - 5 or abs(pos.z) > arena_half_z - 5:
			continue
		if pos.length() < SAFE_ZONE_RADIUS + 2.0:
			continue
		if _near_buildings(pos, 5.0):
			continue
		_make_tree(parent, pos, rng.randf_range(0.85, 1.35))
		placed += 1


func _scatter_set_dressing(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44119
	for i in 70:
		var angle := rng.randf() * TAU
		var r := rng.randf_range(22.0, 520.0)
		var pos := Vector3(cos(angle) * r, 0.05, sin(angle) * r * 0.75)
		if pos.length() < SAFE_ZONE_RADIUS + 5.0 or _near_buildings(pos, 8.0):
			continue
		var rock := _add_box(parent, Vector3(rng.randf_range(0.8, 2.4), rng.randf_range(0.18, 0.7), rng.randf_range(0.7, 2.0)), pos, Color(0.36, 0.4, 0.42))
		rock.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))

	for i in 18:
		var angle := rng.randf() * TAU
		var r := rng.randf_range(28.0, 190.0)
		var pos := Vector3(cos(angle) * r, 0.45, sin(angle) * r * 0.75)
		if _near_buildings(pos, 6.0):
			continue
		var drum := _add_cylinder(parent, 0.34, 0.9, pos, Color(0.7, 0.18, 0.14), "SupplyDrum")
		drum.rotation.y = rng.randf() * TAU
		_add_box(drum, Vector3(0.78, 0.08, 0.78), Vector3.ZERO + Vector3(0, 0.48, 0), Color(0.16, 0.18, 0.2))

	for i in 14:
		var angle := rng.randf() * TAU
		var r := rng.randf_range(35.0, 260.0)
		var post_pos := Vector3(cos(angle) * r, 1.1, sin(angle) * r * 0.7)
		if _near_buildings(post_pos, 7.0):
			continue
		var sign_node := Node3D.new()
		sign_node.position = post_pos
		sign_node.rotation.y = rng.randf() * TAU
		parent.add_child(sign_node)
		_add_box(sign_node, Vector3(0.12, 2.0, 0.12), Vector3(0, -0.1, 0), Color(0.23, 0.15, 0.09))
		_add_box(sign_node, Vector3(1.15, 0.52, 0.08), Vector3(0, 0.72, -0.04), Color(0.9, 0.65, 0.26))
		_add_box(sign_node, Vector3(0.2, 0.08, 0.1), Vector3(-0.32, 0.72, -0.1), Color(0.16, 0.12, 0.09))
		_add_box(sign_node, Vector3(0.2, 0.08, 0.1), Vector3(0.32, 0.72, -0.1), Color(0.16, 0.12, 0.09))


func _near_buildings(pos: Vector3, radius: float) -> bool:
	var building_centers := [
		Vector3(-15, 0, -10),
		Vector3(18, 0, -8),
		Vector3(-12, 0, 18),
		Vector3(20, 0, 19),
	]
	for c in building_centers:
		if pos.distance_to(c) < radius:
			return true
	return false


func _make_tree(parent: Node3D, pos: Vector3, scl: float) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation.y = randf() * TAU
	parent.add_child(sb)

	var trunk_h := 1.8 * scl
	var trunk_r := 0.18 * scl

	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = trunk_r
	trunk_shape.height = trunk_h
	var trunk_coll := CollisionShape3D.new()
	trunk_coll.shape = trunk_shape
	trunk_coll.position = Vector3(0, trunk_h * 0.5, 0)
	sb.add_child(trunk_coll)

	var trunk_mesh := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = trunk_r
	tm.bottom_radius = trunk_r * 1.15
	tm.height = trunk_h
	tm.radial_segments = 6
	trunk_mesh.mesh = tm
	trunk_mesh.position = Vector3(0, trunk_h * 0.5, 0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.36, 0.25, 0.16, 1.0)
	tmat.roughness = 0.95
	trunk_mesh.material_override = tmat
	sb.add_child(trunk_mesh)

	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.12, 0.3, 0.22, 1.0)
	foliage_mat.roughness = 0.95

	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.82, 0.9, 0.92, 1.0)
	snow_mat.roughness = 0.98

	for j in 3:
		var fy: float = trunk_h + 0.1 + j * 1.1 * scl
		var fr: float = (1.7 - j * 0.45) * scl
		var fh: float = 1.7 * scl
		var fmesh := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = fr
		cone.height = fh
		cone.radial_segments = 7
		fmesh.mesh = cone
		fmesh.position = Vector3(0, fy, 0)
		fmesh.material_override = foliage_mat
		sb.add_child(fmesh)

		if j == 2:
			var cap := MeshInstance3D.new()
			var cap_mesh := CylinderMesh.new()
			cap_mesh.top_radius = 0.0
			cap_mesh.bottom_radius = fr * 0.5
			cap_mesh.height = fh * 0.35
			cap_mesh.radial_segments = 7
			cap.mesh = cap_mesh
			cap.position = Vector3(0, fy + fh * 0.22, 0)
			cap.material_override = snow_mat
			sb.add_child(cap)


# -- Safe zone + loot -----------------------------------------------------

func _build_safe_zone(parent: Node3D) -> void:
	var zone := Node3D.new()
	zone.name = "SafeZone"
	zone.add_to_group("safe_zone")
	zone.set_meta("radius", SAFE_ZONE_RADIUS)
	parent.add_child(zone)
	zone.global_position = Vector3.ZERO
	_safe_zone = zone

	# Glowing perimeter ring on the ground.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = SAFE_ZONE_RADIUS - 0.25
	tm.outer_radius = SAFE_ZONE_RADIUS + 0.25
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.4, 0.95, 0.6, 0.85)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.emission_enabled = true
	rmat.emission = Color(0.3, 0.95, 0.5)
	rmat.emission_energy_multiplier = 1.4
	ring.material_override = rmat
	ring.position = Vector3(0, 0.05, 0)
	zone.add_child(ring)

	# Square fence with a gap on the south side for the gate.
	var w: float = 22.0
	var d: float = 22.0
	var thickness: float = 0.5
	var height: float = 2.6
	var fence_color: Color = Color(0.27, 0.2, 0.14)
	# Gate gap on the south side wide enough to drive the truck through.
	var gate_width: float = 4.5
	var side_len: float = (w - gate_width) * 0.5
	var side_off: float = (w + gate_width) * 0.25
	var segs: Array = [
		[Vector3(0, height * 0.5, -d * 0.5),       Vector3(w, height, thickness)],         # north
		[Vector3(w * 0.5, height * 0.5, 0),        Vector3(thickness, height, d)],         # east
		[Vector3(-w * 0.5, height * 0.5, 0),       Vector3(thickness, height, d)],         # west
		[Vector3(-side_off, height * 0.5, d * 0.5), Vector3(side_len, height, thickness)], # south-left
		[Vector3(side_off, height * 0.5, d * 0.5),  Vector3(side_len, height, thickness)], # south-right
	]
	for s in segs:
		_make_fence(zone, s[0], s[1], fence_color)

	# Sanctuary lamp so the area glows at night.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.95, 0.78)
	lamp.light_energy = 2.0
	lamp.omni_range = 28.0
	lamp.position = Vector3(0, 5.5, 0)
	zone.add_child(lamp)

	# NPCs.
	_spawn_npc(zone, Vector3(-6, 0, -4), "Doc Wren",      "doctor",   Color(0.3, 0.7, 0.85),  Color(0.95, 0.98, 1.0))
	_spawn_npc(zone, Vector3(6, 0, -4),  "Mechanic Kade", "mechanic", Color(0.85, 0.55, 0.18), Color(0.98, 0.85, 0.45))
	_spawn_npc(zone, Vector3(0, 0, -7),  "Foreman Ash",   "foreman",  Color(0.55, 0.55, 0.62), Color(0.92, 0.92, 0.95))

	# Garage spot — a flat concrete pad with a "GARAGE" decal-ish panel.
	var pad := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(4.5, 0.1, 6.0)
	pad.mesh = pm
	pad.position = VEHICLE_SPAWN_OFFSET + Vector3(0, -0.45, 0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.24, 0.25, 0.27)
	pmat.roughness = 0.95
	pad.material_override = pmat
	zone.add_child(pad)
	_build_safehouse_props(zone)


func _build_safehouse_props(zone: Node3D) -> void:
	for x in [-10.5, 10.5]:
		for z in [-10.5, 10.5]:
			_add_box(zone, Vector3(0.75, 3.2, 0.75), Vector3(x, 1.6, z), Color(0.18, 0.12, 0.08), "FencePost")

	var tower := Node3D.new()
	tower.name = "WatchTower"
	tower.position = Vector3(-8.0, 0.0, 8.0)
	zone.add_child(tower)
	for x in [-0.75, 0.75]:
		for z in [-0.75, 0.75]:
			_add_box(tower, Vector3(0.18, 3.2, 0.18), Vector3(x, 1.6, z), Color(0.26, 0.17, 0.1))
	_add_box(tower, Vector3(2.1, 0.25, 2.1), Vector3(0, 3.05, 0), Color(0.46, 0.31, 0.18))
	_add_box(tower, Vector3(2.4, 0.22, 2.4), Vector3(0, 3.95, 0), Color(0.12, 0.16, 0.18))
	_add_glow_box(tower, Vector3(0.55, 0.35, 0.2), Vector3(0, 3.45, -1.0), Color(1.0, 0.82, 0.42), 1.6)

	for x in [-5.5, -4.3, 4.3, 5.5]:
		_add_box(zone, Vector3(1.05, 0.38, 0.55), Vector3(x, 0.2, 10.6), Color(0.42, 0.35, 0.24), "Sandbag")
	for z in [-5.5, -4.3, 4.3, 5.5]:
		_add_box(zone, Vector3(0.55, 0.38, 1.05), Vector3(10.6, 0.2, z), Color(0.42, 0.35, 0.24), "Sandbag")

	for x in [-2.2, 2.2]:
		var barrel := _add_cylinder(zone, 0.36, 0.95, Vector3(x, 0.48, 6.8), Color(0.72, 0.22, 0.16), "FuelBarrel")
		barrel.rotation.y = PI * 0.25


func _make_fence(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	parent.add_child(sb)
	var sh := BoxShape3D.new()
	sh.size = size
	var col := CollisionShape3D.new()
	col.shape = sh
	sb.add_child(col)
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	m.material_override = mat
	sb.add_child(m)


func _spawn_npc(parent: Node3D, pos: Vector3, npc_name: String, role: String, body_color: Color, trim: Color) -> void:
	var script := load("res://scripts/npc.gd") as GDScript
	var n: StaticBody3D = script.new()
	n.npc_name = npc_name
	n.role = role
	n.body_color = body_color
	n.trim_color = trim
	parent.add_child(n)
	n.global_position = pos


func _scatter_loot(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 88273
	var script := load("res://scripts/loot_crate.gd") as GDScript
	var placed: int = 0
	var attempts: int = 0
	while placed < 28 and attempts < 280:
		attempts += 1
		var angle: float = rng.randf() * TAU
		var r: float = rng.randf_range(35.0, 600.0)
		var p := Vector3(cos(angle) * r, 1.0, sin(angle) * r * 0.7)
		if absf(p.x) > arena_half_x - 5 or absf(p.z) > arena_half_z - 5:
			continue
		if p.length() < SAFE_ZONE_RADIUS + 6.0:
			continue
		var c: Node3D = script.new()
		c.scrap_value = rng.randi_range(8, 22)
		parent.add_child(c)
		c.global_position = p
		placed += 1


func _build_mines_and_pickups(parent: Node3D) -> void:
	_spawn_resource(parent, Vector3(3.0, 0.0, -6.0), "Crude Bat", "wood", 0, 1, "weapon", "Bat")
	_spawn_resource(parent, Vector3(-20.0, 0.0, -13.0), "Camp Axe", "wood", 0, 1, "weapon", "Axe")
	_spawn_resource(parent, Vector3(760.0, 0.0, 690.0), "River Spear", "wood", 0, 1, "weapon", "Spear")
	_spawn_resource(parent, OBJECTIVE_POS + Vector3(-18.0, 0.0, 8.0), "Signal Pistol", "wood", 0, 1, "weapon", "Pistol")

	var wood_points := [
		Vector3(9, 0, -12), Vector3(-8, 0, 12), Vector3(24, 0, 28),
		Vector3(-42, 0, 34), Vector3(120, 0, -88), Vector3(-180, 0, 70),
		Vector3(1400, 0, 4020), Vector3(1880, 0, 4480), Vector3(-700, 0, -3880),
		Vector3(500, 0, -4420), Vector3(3020, 0, -1600), Vector3(-2600, 0, 1900),
	]
	for p in wood_points:
		_spawn_resource(parent, p, "Wood", "wood", 4, 1, "wood")

	var stone_points := [
		Vector3(16, 0, 38), Vector3(-35, 0, -42), Vector3(220, 0, 140),
		Vector3(-380, 0, 120), Vector3(-4240, 0, 1220), Vector3(-4100, 0, 980),
		Vector3(-3920, 0, 1360), Vector3(3500, 0, -2550),
	]
	for p in stone_points:
		_spawn_resource(parent, p, "Stone", "stone", 3, 1, "stone")

	var mine_pos := Vector3(-4300, 0, 1100)
	_make_mine_entrance(parent, mine_pos, PI * 0.38)
	for i in 10:
		var offset := Vector3(-18.0 + i * 4.0, 0.0, -8.0 + (i % 3) * 5.5)
		_spawn_resource(parent, mine_pos + offset, "Ore Vein", "ore", 3, 4, "mine")
	for i in 6:
		var x := -2400.0 + i * 760.0
		_spawn_resource(parent, Vector3(x, 0.0, 900.0 - x * 0.3 + 80.0), "Fish", "fish", 1, 1, "fish")
	for i in 7:
		_spawn_resource(parent, Vector3(6100.0 + i * 180.0, 0.0, -2100.0 + i * 540.0), "Ocean Fish", "fish", 2, 1, "fish")


func _spawn_resource(parent: Node3D, pos: Vector3, label_text: String, item_id: String, amount: int, uses: int, kind: String, unlock_name: String = "") -> Node3D:
	var node_script := load("res://scripts/resource_node.gd") as GDScript
	var resource_node: StaticBody3D = node_script.new()
	resource_node.display_name = label_text
	resource_node.resource_id = item_id
	resource_node.amount = amount
	resource_node.uses_left = uses
	resource_node.node_kind = kind
	resource_node.unlock_weapon_name = unlock_name
	parent.add_child(resource_node)
	resource_node.global_position = pos
	return resource_node


func _make_mine_entrance(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var mine := Node3D.new()
	mine.name = "MineEntrance"
	mine.position = pos
	mine.rotation.y = yaw
	parent.add_child(mine)
	_add_box(mine, Vector3(10.0, 5.5, 2.0), Vector3(0, 2.75, 3.0), Color(0.22, 0.2, 0.18), "MineBackRock")
	_add_box(mine, Vector3(1.0, 3.6, 1.0), Vector3(-3.2, 1.8, -0.4), Color(0.14, 0.1, 0.07), "MinePostL")
	_add_box(mine, Vector3(1.0, 3.6, 1.0), Vector3(3.2, 1.8, -0.4), Color(0.14, 0.1, 0.07), "MinePostR")
	_add_box(mine, Vector3(7.6, 0.9, 1.0), Vector3(0, 3.65, -0.4), Color(0.16, 0.1, 0.06), "MineHeader")
	_add_box(mine, Vector3(4.4, 2.8, 1.0), Vector3(0, 1.4, -0.5), Color(0.03, 0.035, 0.04), "MineDark")
	_add_glow_box(mine, Vector3(0.35, 0.35, 0.22), Vector3(-2.8, 2.25, -1.1), Color(1.0, 0.65, 0.28), 1.6)
	var label := Label3D.new()
	label.text = "MINE"
	label.font_size = 34
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.modulate = Color(0.95, 0.82, 0.55)
	label.position = Vector3(0, 4.7, -0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	mine.add_child(label)


func _build_objective(parent: Node3D) -> void:
	var objective := Node3D.new()
	objective.name = "OldRadioTower"
	objective.add_to_group("objective")
	objective.set_meta("radius", 14.0)
	objective.position = OBJECTIVE_POS
	parent.add_child(objective)

	for x in [-1.8, 1.8]:
		for z in [-1.8, 1.8]:
			var leg := _add_box(objective, Vector3(0.22, 13.0, 0.22), Vector3(x, 6.5, z), Color(0.46, 0.48, 0.48), "TowerLeg")
			leg.rotation.z = 0.08 * sign(x)
	for y in [2.2, 5.0, 7.8, 10.6]:
		_add_box(objective, Vector3(4.6, 0.18, 0.18), Vector3(0, y, -1.8), Color(0.56, 0.58, 0.58), "TowerBrace")
		_add_box(objective, Vector3(4.6, 0.18, 0.18), Vector3(0, y, 1.8), Color(0.56, 0.58, 0.58), "TowerBrace")
		_add_box(objective, Vector3(0.18, 0.18, 4.6), Vector3(-1.8, y, 0), Color(0.56, 0.58, 0.58), "TowerBrace")
		_add_box(objective, Vector3(0.18, 0.18, 4.6), Vector3(1.8, y, 0), Color(0.56, 0.58, 0.58), "TowerBrace")
	_add_glow_box(objective, Vector3(1.0, 0.7, 1.0), Vector3(0, 13.7, 0), Color(1.0, 0.25, 0.18), 3.5)
	_add_box(objective, Vector3(5.8, 0.35, 5.8), Vector3(0, 0.18, 0), Color(0.25, 0.25, 0.24), "TowerPad")
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.35)
	light.light_energy = 2.4
	light.omni_range = 36.0
	light.position = Vector3(0, 13.8, 0)
	objective.add_child(light)
	var label := Label3D.new()
	label.text = "OLD RADIO TOWER"
	label.font_size = 38
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.modulate = Color(1.0, 0.88, 0.48)
	label.position = Vector3(0, 4.5, -5.5)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	objective.add_child(label)
	_make_enterable_house(parent, OBJECTIVE_POS + Vector3(-13.0, 0.0, 11.0), -PI * 0.18)


func build_player_shelter(target_pos: Vector3, yaw: float) -> void:
	var cost := {"wood": SHELTER_WOOD_COST, "stone": SHELTER_STONE_COST}
	if not GameManager.spend_items(cost):
		GameManager.show_toast("Need %d wood and %d stone for a shelter." % [SHELTER_WOOD_COST, SHELTER_STONE_COST])
		return
	target_pos.x = clamp(target_pos.x, -arena_half_x + 8.0, arena_half_x - 8.0)
	target_pos.z = clamp(target_pos.z, -arena_half_z + 8.0, arena_half_z - 8.0)
	var parent := get_node_or_null("Level") as Node3D
	if parent == null:
		parent = self
	var shelter := Node3D.new()
	shelter.name = "PlayerShelter"
	shelter.add_to_group("safe_zone")
	shelter.set_meta("radius", 10.0)
	shelter.global_position = Vector3(target_pos.x, 0.0, target_pos.z)
	shelter.rotation.y = yaw
	parent.add_child(shelter)
	_add_box(shelter, Vector3(5.6, 0.16, 4.6), Vector3(0, 0.08, 0), Color(0.3, 0.22, 0.14), "ShelterFloor")
	for x in [-2.4, 2.4]:
		for z in [-1.9, 1.9]:
			_add_box(shelter, Vector3(0.24, 2.8, 0.24), Vector3(x, 1.4, z), Color(0.26, 0.16, 0.08), "ShelterPost")
	_add_box(shelter, Vector3(6.1, 0.35, 5.1), Vector3(0, 3.0, 0), Color(0.15, 0.18, 0.16), "ShelterRoof")
	_make_fence(shelter, Vector3(0, 1.15, 2.05), Vector3(5.6, 2.2, 0.18), Color(0.38, 0.27, 0.16))
	_make_fence(shelter, Vector3(-2.75, 1.15, 0), Vector3(0.18, 2.2, 4.0), Color(0.38, 0.27, 0.16))
	_make_fence(shelter, Vector3(2.75, 1.15, 0), Vector3(0.18, 2.2, 4.0), Color(0.38, 0.27, 0.16))
	_add_glow_box(shelter, Vector3(0.42, 0.34, 0.24), Vector3(0, 2.35, -1.5), Color(1.0, 0.68, 0.32), 1.4)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 9.7
	tm.outer_radius = 10.0
	ring.mesh = tm
	ring.position = Vector3(0, 0.05, 0)
	ring.material_override = _style_mat(Color(0.45, 0.9, 0.55, 0.58))
	shelter.add_child(ring)
	GameManager.show_toast("Shelter built. Warmth recovers inside.")


func objective_status(player_pos: Vector3) -> String:
	if _objective_reached:
		return "OBJECTIVE SECURED  Build, mine, and prepare for the Titan"
	var meters := int(player_pos.distance_to(OBJECTIVE_POS))
	return "OBJECTIVE  Reach Old Radio Tower  %dm" % meters


func _check_objective() -> void:
	if _objective_reached:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if (player as Node3D).global_position.distance_to(OBJECTIVE_POS) <= 15.0:
		_objective_reached = true
		GameManager.show_toast("Radio tower reached. The expedition can now push deeper.")


func _spawn_vehicle() -> void:
	if _vehicle and is_instance_valid(_vehicle):
		return
	var script := load("res://scripts/vehicle.gd") as GDScript
	var v: CharacterBody3D = script.new()
	v.name = "PlayerTruck"
	add_child(v)
	v.global_position = VEHICLE_SPAWN_OFFSET
	_vehicle = v
	GameManager.show_toast("Truck delivered to the garage.")


func _on_remote_player_state(peer_id: int, remote_position: Vector3, rotation_y: float) -> void:
	var avatar: Node3D = _remote_players.get(peer_id, null)
	if avatar == null or not is_instance_valid(avatar):
		avatar = _build_remote_player(peer_id)
		_remote_players[peer_id] = avatar
		avatar.global_position = remote_position
	else:
		avatar.global_position = avatar.global_position.lerp(remote_position, 0.45)
	avatar.rotation.y = lerp_angle(avatar.rotation.y, rotation_y, 0.45)


func _on_remote_player_left(peer_id: int) -> void:
	var avatar: Node3D = _remote_players.get(peer_id, null)
	if avatar and is_instance_valid(avatar):
		avatar.queue_free()
	_remote_players.erase(peer_id)


func _build_remote_player(peer_id: int) -> Node3D:
	var avatar := Node3D.new()
	avatar.name = "Ally_%d" % peer_id
	add_child(avatar)
	_add_box(avatar, Vector3(0.72, 1.1, 0.42), Vector3(0, 0.95, 0), Color(0.18, 0.34, 0.48), "AllyCoat")
	_add_box(avatar, Vector3(0.42, 0.42, 0.42), Vector3(0, 1.75, 0), Color(0.82, 0.72, 0.58), "AllyHead")
	_add_box(avatar, Vector3(0.62, 0.14, 0.2), Vector3(0, 1.45, -0.28), Color(0.95, 0.72, 0.28), "AllyScarf")
	_add_box(avatar, Vector3(0.2, 0.72, 0.2), Vector3(-0.5, 1.0, -0.04), Color(0.13, 0.24, 0.34), "AllyArmL")
	_add_box(avatar, Vector3(0.2, 0.72, 0.2), Vector3(0.5, 1.0, -0.04), Color(0.13, 0.24, 0.34), "AllyArmR")
	var label := Label3D.new()
	label.text = "ALLY %d" % peer_id
	label.font_size = 28
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 1)
	label.modulate = Color(0.7, 0.95, 1.0)
	label.position = Vector3(0, 2.45, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	avatar.add_child(label)
	return avatar


func _on_world_state_changed() -> void:
	if GameManager.car_owned:
		_spawn_vehicle()


func _spawn_boss() -> void:
	if _boss_spawned:
		return
	_boss_spawned = true
	var script := load("res://scripts/boss.gd") as GDScript
	var b: CharacterBody3D = script.new()
	b.name = "FrostTitan"
	add_child(b)
	# Drop the Titan on the south horizon so the player sees it advance.
	var p := get_tree().get_first_node_in_group("player")
	var origin: Vector3 = p.global_position if p else Vector3.ZERO
	b.global_position = origin + Vector3(0, 1.0, 35.0)


# -- Spawner --------------------------------------------------------------

func _process(delta: float) -> void:
	if GameManager.game_over:
		return

	_tick_weather(delta)
	_check_objective()

	# Boss phase: don't keep adding small zombies — focus is the Titan.
	if GameManager.phase == "boss":
		return
	if GameManager.phase == "regroup":
		_tick_regroup(delta)
		return

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	var weather_mult: float = float(GameManager.current_weather_def().get("spawn_mult", 1.0))
	var base_int: float = night_spawn_interval if _is_night else spawn_interval
	_spawn_timer = max(0.5, base_int / weather_mult)

	var alive := 0
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.get("is_dead") == false:
			alive += 1

	var cap := max_alive + (3 if _is_night else 0)
	if GameManager.phase == "defend":
		cap += 4
	if alive < cap:
		_spawn_zombie(GameManager.phase == "defend")


func _tick_regroup(delta: float) -> void:
	GameManager.tick_regroup(_is_player_in_safe_zone(), delta)


func _is_player_in_safe_zone() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	for zone in get_tree().get_nodes_in_group("safe_zone"):
		if not (zone is Node3D):
			continue
		var center: Vector3 = (zone as Node3D).global_position
		var radius: float = float(zone.get_meta("radius", SAFE_ZONE_RADIUS))
		if (player as Node3D).global_position.distance_to(center) <= radius:
			return true
	return false


func _spawn_zombie(near_safe_zone: bool = false) -> void:
	if zombie_scene == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	var origin: Vector3 = player.global_position if player else Vector3.ZERO

	var sz_center: Vector3 = Vector3.ZERO
	var sz_radius: float = SAFE_ZONE_RADIUS
	if _safe_zone and is_instance_valid(_safe_zone):
		sz_center = _safe_zone.global_position
		sz_radius = float(_safe_zone.get_meta("radius", SAFE_ZONE_RADIUS))
	var min_clear: float = sz_radius + SAFE_ZONE_BUFFER

	var pos: Vector3
	if near_safe_zone:
		pos = _pick_siege_spawn_position(sz_center, min_clear)
	else:
		for attempt in 8:
			var angle := randf() * TAU
			var dist := randf_range(spawn_radius_min, spawn_radius_max)
			pos = origin + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			pos.x = clamp(pos.x, -arena_half_x + 4.0, arena_half_x - 4.0)
			pos.z = clamp(pos.z, -arena_half_z + 4.0, arena_half_z - 4.0)
			if pos.distance_to(sz_center) >= min_clear:
				break
	pos.y = 1.0
	# If the player is camping inside the safe zone, skip the spawn entirely.
	if not near_safe_zone and pos.distance_to(sz_center) < min_clear:
		return

	var z := zombie_scene.instantiate()
	z.position = pos
	add_child(z)
	# Type assignment must happen after add_child so onready vars resolve.
	if z.has_method("apply_type"):
		z.apply_type(_pick_zombie_type())
	# Adaptive AI: 60% chance the zombie carries resistance to the player's
	# most-used damage type. Skipped if the player hasn't done much yet.
	if z.has_method("set_resistance"):
		var dom: String = GameManager.dominant_damage_type()
		if dom != "" and randf() < 0.6:
			z.set_resistance(dom)


func _pick_siege_spawn_position(center: Vector3, min_clear: float) -> Vector3:
	var lanes := [
		Vector3(1, 0, 0),
		Vector3(-1, 0, 0),
		Vector3(0, 0, 1),
		Vector3(0, 0, -1),
	]
	var dir: Vector3 = lanes[randi() % lanes.size()]
	var tangent := Vector3(-dir.z, 0, dir.x)
	var distance: float = min_clear + randf_range(3.0, 9.0)
	var offset: float = randf_range(-10.0, 10.0)
	var pos := center + dir * distance + tangent * offset
	pos.x = clamp(pos.x, -arena_half_x + 4.0, arena_half_x - 4.0)
	pos.z = clamp(pos.z, -arena_half_z + 4.0, arena_half_z - 4.0)
	return pos


func _pick_zombie_type() -> Dictionary:
	var total := 0
	for t in ZOMBIE_TYPES:
		total += int(t["weight"])
	var r := randi() % total
	for t in ZOMBIE_TYPES:
		r -= int(t["weight"])
		if r < 0:
			return t
	return ZOMBIE_TYPES[0]
