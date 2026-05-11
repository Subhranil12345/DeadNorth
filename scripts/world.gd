extends Node3D

# Builds a wide static survival level on _ready and runs the zombie spawner.
# Trees and cabins are scattered with density falling off from the player's
# spawn so the world feels populated nearby and lonely in the wilderness.

@export var zombie_scene: PackedScene
@export var max_alive: int = 160
@export var initial_wave: int = 14
@export var spawn_interval: float = 1.8
@export var night_spawn_interval: float = 1.0
@export var spawn_radius_min: float = 14.0
@export var spawn_radius_max: float = 32.0
@export var arena_half_x: float = 2000.0  # 4 km wide
@export var arena_half_z: float = 2000.0  # 4 km deep

var _spawn_timer: float = 0.0
var _is_night: bool = false
var _starfield: Node3D = null
var _snow_particles: GPUParticles3D = null

# Procedural noise textures shared across surfaces with the same material
# family (wood, brick, sand, etc.). Generated once on first request to avoid
# per-mesh GPU upload churn. _noise_normals holds matching normal-map
# variants so materials can have surface relief without separate authoring.
var _noise_textures: Dictionary = {}
var _noise_normals: Dictionary = {}

# Safe zone — populated in _build_safe_zone.
var _safe_zone: Node3D = null
const SAFE_ZONE_RADIUS: float = 16.0
const SAFE_ZONE_BUFFER: float = 4.0  # extra clearance for spawns
const VEHICLE_SPAWN_OFFSET: Vector3 = Vector3(7.0, 0.5, 6.0)
const OBJECTIVE_POS: Vector3 = Vector3(1300.0, 0.0, -1075.0)
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
	if _starfield and is_instance_valid(_starfield):
		_starfield.visible = _is_night


# -- Weather --------------------------------------------------------------

func _on_weather_changed(weather_name: String) -> void:
	_apply_weather(weather_name)


func _apply_weather(weather_name: String) -> void:
	var def: Dictionary = GameManager.WEATHER_DEFS.get(weather_name, GameManager.WEATHER_DEFS["clear"])
	var env_holder := get_node_or_null(_world_env_path) as WorldEnvironment
	if env_holder != null and env_holder.environment != null:
		var env: Environment = env_holder.environment
		env.fog_density = float(def.get("fog_density", 0.008))
		env.fog_light_color = def.get("fog_color", Color(0.78, 0.83, 0.9))
	# Snow particle emission tracks weather severity.
	if _snow_particles and is_instance_valid(_snow_particles):
		var emit: bool = weather_name == "snowstorm" or weather_name == "blizzard"
		_snow_particles.emitting = emit
		if emit:
			var pm: ParticleProcessMaterial = _snow_particles.process_material
			if pm:
				if weather_name == "blizzard":
					pm.initial_velocity_min = 2.0
					pm.initial_velocity_max = 6.0
					_snow_particles.amount = 1100
				else:
					pm.initial_velocity_min = 0.5
					pm.initial_velocity_max = 2.5
					_snow_particles.amount = 700


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
	_build_rugged_terrain(level)
	_scatter_field_vehicles(level)
	_scatter_set_dressing(level)
	_build_mines_and_pickups(level)
	_build_desert_caves(level)
	_build_objective(level)
	_build_safe_zone(level)
	_scatter_loot(level)
	_seed_regional_zombies(level)
	_spawn_regional_bosses(level)
	_build_starfield(level)
	_build_snow_particles(level)


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

	var mat: StandardMaterial3D = _textured_mat(Color(0.78, 0.85, 0.9), "snow", 60.0, 0.95)
	mesh_inst.material_override = mat
	sb.add_child(mesh_inst)


func get_biome_at(pos: Vector3) -> String:
	if pos.x > arena_half_x * 0.7:
		return "ocean"
	if absf(pos.x * 0.3 + pos.z - 225.0) < 50.0:
		return "river"
	if pos.x < -arena_half_x * 0.45:
		return "desert"
	if pos.z > arena_half_z * 0.5:
		return "plains"
	if pos.z < -arena_half_z * 0.55:
		return "autumn"
	return "snow"


func _build_biomes(parent: Node3D) -> void:
	_add_biome_patch(parent, Vector3(-1463, 0, 0), Vector2(1075, arena_half_z * 2.0), Color(0.74, 0.62, 0.38), "Desert")
	_add_biome_patch(parent, Vector3(0, 0, 1138), Vector2(2800, 725), Color(0.34, 0.52, 0.32), "Plains")
	_add_biome_patch(parent, Vector3(0, 0, -1175), Vector2(2800, 650), Color(0.56, 0.36, 0.18), "AutumnWoods")
	_add_biome_patch(parent, Vector3(1725, 0, 0), Vector2(550, arena_half_z * 2.0), Color(0.1, 0.32, 0.46, 0.86), "Ocean", true)
	for i in 13:
		var x := -1350.0 + i * 225.0
		var z := 225.0 - x * 0.3
		_add_biome_patch(parent, Vector3(x, 0, z), Vector2(180, 130), Color(0.08, 0.38, 0.52, 0.82), "River", true)
	_build_aquatic_life(parent)


func _add_biome_patch(parent: Node3D, center: Vector3, size: Vector2, color: Color, patch_name: String, transparent: bool = false) -> void:
	var patch := MeshInstance3D.new()
	patch.name = patch_name
	var plane := PlaneMesh.new()
	plane.size = size
	patch.mesh = plane
	patch.position = Vector3(center.x, 0.025, center.z)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Ocean/River get the animated water shader; everything else uses noise-
	# textured StandardMaterial3D.
	if patch_name == "Ocean" or patch_name == "River":
		patch.material_override = _get_water_mat()
		parent.add_child(patch)
		return
	var mat: StandardMaterial3D
	match patch_name:
		"Desert": mat = _textured_mat(color, "sand", 48.0, 0.96)
		"Plains": mat = _textured_mat(color, "dirt", 50.0, 0.96)
		"AutumnWoods": mat = _textured_mat(color, "dirt", 50.0, 0.96)
		_: mat = _textured_mat(color, "snow", 50.0, 0.96)
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
		var p := Vector3(rng.randf_range(1513.0, 1900.0), 0.18, rng.randf_range(-1300.0, 1350.0))
		_make_fish_school(water, p, rng.randf_range(0.75, 1.25), Color(0.32, 0.74, 0.82))
	for i in 18:
		var x := rng.randf_range(-1200.0, 1100.0)
		var p := Vector3(x, 0.18, 225.0 - x * 0.3 + rng.randf_range(-22.0, 22.0))
		_make_fish_school(water, p, rng.randf_range(0.55, 0.9), Color(0.75, 0.58, 0.28))
	for i in 7:
		var p := Vector3(rng.randf_range(1550.0, 1900.0), 0.08, rng.randf_range(-1250.0, 1250.0))
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


func _ensure_noise_textures() -> void:
	if _noise_textures.size() > 0:
		return
	# Grayscale noise textures keyed by surface family. Albedo color from the
	# caller tints them, so the same "wood" texture works for brown, gray, or
	# painted timber alike. Generation is async on Godot 4 NoiseTexture2D —
	# materials briefly look untextured at world load, then snap in.
	var defs: Dictionary = {
		"snow":    {"freq": 0.06,  "oct": 4, "normal_scale": 0.15},
		"wood":    {"freq": 0.55,  "oct": 5, "normal_scale": 0.6},
		"brick":   {"freq": 0.35,  "oct": 3, "normal_scale": 0.7},
		"stone":   {"freq": 0.32,  "oct": 5, "normal_scale": 0.6},
		"sand":    {"freq": 0.18,  "oct": 4, "normal_scale": 0.3},
		"dirt":    {"freq": 0.22,  "oct": 5, "normal_scale": 0.45},
		"bark":    {"freq": 1.4,   "oct": 5, "normal_scale": 0.8},
		"metal":   {"freq": 0.5,   "oct": 3, "normal_scale": 0.25},
		"grass":   {"freq": 0.8,   "oct": 5, "normal_scale": 0.4},
		"asphalt": {"freq": 0.6,   "oct": 4, "normal_scale": 0.3},
	}
	for key in defs.keys():
		var d: Dictionary = defs[key]
		var noise := FastNoiseLite.new()
		noise.frequency = float(d["freq"])
		noise.fractal_octaves = int(d["oct"])
		noise.seed = int(hash(key)) & 0x7FFFFFFF
		var tex := NoiseTexture2D.new()
		tex.noise = noise
		tex.width = 256
		tex.height = 256
		tex.normalize = true
		tex.seamless = true
		_noise_textures[key] = tex
		# Matching normal map — same noise treated as a heightfield. Godot
		# converts grayscale to tangent-space normals when as_normal_map is true.
		var ntex := NoiseTexture2D.new()
		ntex.noise = noise
		ntex.width = 256
		ntex.height = 256
		ntex.normalize = true
		ntex.seamless = true
		ntex.as_normal_map = true
		ntex.bump_strength = float(d["normal_scale"]) * 6.0
		_noise_normals[key] = ntex


func _textured_mat(base_color: Color, key: String, uv_scale: float = 4.0, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	_ensure_noise_textures()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.roughness = roughness
	mat.metallic = metallic
	var tex: NoiseTexture2D = _noise_textures.get(key, null)
	if tex != null:
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	var ntex: NoiseTexture2D = _noise_normals.get(key, null)
	if ntex != null:
		mat.normal_enabled = true
		mat.normal_texture = ntex
		mat.normal_scale = 0.5
	return mat


# Shared shader materials. Created lazily, reused across all instances of
# the same surface (one ocean material, one foliage material) so we don't
# rebuild shaders per-mesh.
var _water_mat: ShaderMaterial = null
var _foliage_mat: ShaderMaterial = null


func _get_water_mat() -> ShaderMaterial:
	if _water_mat != null:
		return _water_mat
	var sh := Shader.new()
	sh.code = "shader_type spatial;\n" + \
		"render_mode blend_mix, depth_draw_opaque, cull_back;\n" + \
		"uniform vec3 water_color : source_color = vec3(0.08, 0.32, 0.46);\n" + \
		"uniform vec3 foam_color : source_color = vec3(0.7, 0.86, 0.95);\n" + \
		"uniform float scroll_speed = 0.04;\n" + \
		"uniform float wave_freq = 8.0;\n" + \
		"uniform sampler2D noise_tex : hint_default_white;\n" + \
		"void fragment() {\n" + \
		"    vec2 uv1 = UV * wave_freq + vec2(TIME * scroll_speed, TIME * scroll_speed * 0.7);\n" + \
		"    vec2 uv2 = UV * wave_freq * 1.7 - vec2(TIME * scroll_speed * 1.3, TIME * scroll_speed * 0.4);\n" + \
		"    float n1 = texture(noise_tex, uv1).r;\n" + \
		"    float n2 = texture(noise_tex, uv2).r;\n" + \
		"    float n = (n1 + n2) * 0.5;\n" + \
		"    vec3 col = mix(water_color, foam_color, smoothstep(0.5, 0.85, n) * 0.55);\n" + \
		"    ALBEDO = col;\n" + \
		"    METALLIC = 0.4;\n" + \
		"    ROUGHNESS = 0.18;\n" + \
		"    EMISSION = water_color * 0.08;\n" + \
		"    ALPHA = 0.88;\n" + \
		"}\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_ensure_noise_textures()
	var ntex: NoiseTexture2D = _noise_textures.get("stone", null)
	if ntex != null:
		mat.set_shader_parameter("noise_tex", ntex)
	_water_mat = mat
	return mat


func _get_foliage_mat(base_color: Color) -> ShaderMaterial:
	# One shared ShaderMaterial across all trees — avoids hundreds of
	# duplicate materials. The shader uses TIME for animation so each instance
	# in the world sways with a different phase via its world-space position.
	if _foliage_mat != null:
		return _foliage_mat
	var sh := Shader.new()
	sh.code = "shader_type spatial;\n" + \
		"uniform vec3 albedo : source_color = vec3(0.12, 0.3, 0.22);\n" + \
		"uniform float sway_amount = 0.08;\n" + \
		"uniform float sway_speed = 1.2;\n" + \
		"uniform float roughness_val = 0.95;\n" + \
		"void vertex() {\n" + \
		"    // Sway scales with height above the trunk base.\n" + \
		"    float h = max(0.0, VERTEX.y - 1.2) * sway_amount;\n" + \
		"    float t = TIME * sway_speed;\n" + \
		"    VERTEX.x += sin(t + VERTEX.x * 0.35 + VERTEX.z * 0.25) * h;\n" + \
		"    VERTEX.z += cos(t * 0.8 + VERTEX.x * 0.22) * h * 0.7;\n" + \
		"}\n" + \
		"void fragment() {\n" + \
		"    ALBEDO = albedo;\n" + \
		"    ROUGHNESS = roughness_val;\n" + \
		"}\n"
	_foliage_mat = ShaderMaterial.new()
	_foliage_mat.shader = sh
	_foliage_mat.set_shader_parameter("albedo", Vector3(base_color.r, base_color.g, base_color.b))
	return _foliage_mat


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
		var radius := rng.randf_range(50.0, 1400.0)
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
		# Most houses are walkable; closed cabins are the minority decoration.
		if placed % 3 == 0:
			_make_cabin(parent, p, rng.randf() * TAU)
		else:
			_make_enterable_house(parent, p, rng.randf() * TAU)
		placed += 1
	_build_settlements(parent)


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
	# Dispatcher — picks one of four walkable-interior variants based on a
	# hash of the position so the same spot looks the same between runs but
	# the settlement as a whole varies.
	var seed_i: int = int(absf(pos.x * 13.0 + pos.z * 7.0))
	var variants := ["cabin_hut", "brick", "suburban", "lodge"]
	var pick: String = variants[seed_i % variants.size()]
	match pick:
		"brick":     _house_brick(parent, pos, yaw)
		"suburban":  _house_suburban(parent, pos, yaw)
		"lodge":     _house_lodge(parent, pos, yaw)
		_:           _house_cabin_hut(parent, pos, yaw)
	# Every enterable variant gets a warmth_zone node so being inside any
	# house refills warmth (smaller radius than the central sanctuary).
	_add_house_warmth_zone(parent, pos)


func _add_house_warmth_zone(parent: Node3D, pos: Vector3) -> void:
	var zone := Node3D.new()
	zone.name = "HouseWarmthZone"
	zone.add_to_group("warmth_zone")
	zone.set_meta("radius", 5.5)
	parent.add_child(zone)
	zone.global_position = pos + Vector3(0, 1.0, 0)


# A wall segment with a centered door-sized gap. The two side pieces get
# proper collision via _make_fence; a thin header beam spans the gap so the
# silhouette still reads as a wall.
func _wall_with_door(parent: Node3D, center: Vector3, span: float, height: float, thickness: float, color: Color, gap: float = 1.7, axis: String = "x", texture_key: String = "") -> void:
	var side_len: float = (span - gap) * 0.5
	if side_len <= 0.05:
		return
	var side_off: float = (span + gap) * 0.25
	if axis == "x":
		_make_fence(parent, center + Vector3(-side_off, 0, 0), Vector3(side_len, height, thickness), color, texture_key)
		_make_fence(parent, center + Vector3(side_off, 0, 0), Vector3(side_len, height, thickness), color, texture_key)
		_add_box(parent, Vector3(gap + 0.2, height * 0.18, thickness * 1.05), center + Vector3(0, height * 0.41, 0), color.darkened(0.4), "DoorHeader")
		# Invisible monster-only barrier filling the door gap so zombies can't
		# walk in. Player is on layer 1 only; barrier sits on layer 2.
		_make_monster_door_block(parent, center, Vector3(gap, height, thickness))
	else:
		_make_fence(parent, center + Vector3(0, 0, -side_off), Vector3(thickness, height, side_len), color, texture_key)
		_make_fence(parent, center + Vector3(0, 0, side_off), Vector3(thickness, height, side_len), color, texture_key)
		_add_box(parent, Vector3(thickness * 1.05, height * 0.18, gap + 0.2), center + Vector3(0, height * 0.41, 0), color.darkened(0.4), "DoorHeader")
		_make_monster_door_block(parent, center, Vector3(thickness, height, gap))


# Invisible static body on layer 2 only. Zombies (layer 1|2, mask 1|2) detect
# it via their mask; the player (layer 1, mask 1) doesn't see it at all so
# they can walk through the doorway as normal.
func _make_monster_door_block(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = "MonsterDoorBlock"
	sb.position = pos
	sb.collision_layer = 2
	sb.collision_mask = 0
	parent.add_child(sb)
	var sh := BoxShape3D.new()
	sh.size = size
	var col := CollisionShape3D.new()
	col.shape = sh
	sb.add_child(col)


# Cosmetic window — emissive panel hung against a wall. No collision; just
# visual interest from outside and a glow at night.
func _add_window(parent: Node3D, pos: Vector3, size: Vector3, tint: Color = Color(0.5, 0.78, 0.92)) -> void:
	_add_glow_box(parent, size, pos, tint, 0.55)


# Variant 1: Cabin Hut — single room, log-style walls, simple bed and fire.
func _house_cabin_hut(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var house := Node3D.new()
	house.name = "CabinHut"
	house.position = pos
	house.rotation.y = yaw
	parent.add_child(house)

	var w: float = 6.0
	var h: float = 2.8
	var d: float = 5.0
	var wall_color: Color = Color(0.46, 0.3, 0.18)
	var trim_color: Color = Color(0.22, 0.14, 0.08)

	_add_box(house, Vector3(w, 0.12, d), Vector3(0, 0.06, 0), Color(0.28, 0.2, 0.13), "Floor")
	_make_fence(house, Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, 0.22), wall_color, "wood")
	_make_fence(house, Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.22, h, d), wall_color, "wood")
	_make_fence(house, Vector3(w * 0.5, h * 0.5, 0), Vector3(0.22, h, d), wall_color, "wood")
	_wall_with_door(house, Vector3(0, h * 0.5, -d * 0.5), w, h, 0.22, wall_color, 1.6, "x", "wood")

	# Sloped roof
	var roof_h: float = 1.4
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(w + 0.4, roof_h, d + 0.4)
	roof.mesh = prism
	roof.position = Vector3(0, h + roof_h * 0.5, 0)
	roof.material_override = _textured_mat(Color(0.18, 0.12, 0.08), "wood", 6.0, 0.9)
	house.add_child(roof)

	# Window slits — left/right walls
	_add_window(house, Vector3(-w * 0.5 - 0.06, 1.6, 0.6), Vector3(0.08, 0.45, 0.8))
	_add_window(house, Vector3(w * 0.5 + 0.06, 1.6, -0.6), Vector3(0.08, 0.45, 0.8))

	# Hearth on the back wall
	_add_box(house, Vector3(1.4, 0.7, 0.9), Vector3(0, 0.35, d * 0.5 - 0.6), Color(0.32, 0.32, 0.34), "Hearth")
	_add_glow_box(house, Vector3(1.0, 0.32, 0.32), Vector3(0, 0.32, d * 0.5 - 0.95), Color(1.0, 0.5, 0.14), 1.4)
	# Stone chimney up through the roof
	_add_box(house, Vector3(0.85, h + roof_h + 0.6, 0.85), Vector3(0, (h + roof_h + 0.6) * 0.5, d * 0.5 - 0.4), Color(0.28, 0.28, 0.3), "Chimney")

	# Bed against the left wall
	_add_box(house, Vector3(1.6, 0.32, 0.78), Vector3(-w * 0.5 + 1.0, 0.22, -0.2), Color(0.26, 0.24, 0.22), "Bed")
	_add_box(house, Vector3(1.6, 0.18, 0.78), Vector3(-w * 0.5 + 1.0, 0.45, -0.2), Color(0.46, 0.3, 0.22), "Quilt")
	_add_box(house, Vector3(0.4, 0.2, 0.5), Vector3(-w * 0.5 + 0.5, 0.5, -0.45), Color(0.9, 0.88, 0.82), "Pillow")

	# Small table + stool by the door
	_add_box(house, Vector3(1.0, 0.55, 0.7), Vector3(w * 0.5 - 1.2, 0.32, 0.6), Color(0.28, 0.18, 0.1), "Table")
	_add_box(house, Vector3(0.4, 0.4, 0.4), Vector3(w * 0.5 - 1.2, 0.22, -0.2), Color(0.22, 0.14, 0.08), "Stool")

	# Door header (visual) + hanging lantern
	_add_box(house, Vector3(1.7, 0.14, 0.18), Vector3(0, 2.05, -d * 0.5 - 0.05), trim_color, "DoorHeader")
	_add_glow_box(house, Vector3(0.28, 0.24, 0.28), Vector3(0, h - 0.45, 0), Color(1.0, 0.72, 0.38), 1.2)


# Variant 2: Brick House — single story, two rooms (kitchen + sitting room).
func _house_brick(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var house := Node3D.new()
	house.name = "BrickHouse"
	house.position = pos
	house.rotation.y = yaw
	parent.add_child(house)

	var w: float = 7.0
	var h: float = 3.0
	var d: float = 6.0
	var wall_color: Color = Color(0.55, 0.24, 0.18)
	var trim_color: Color = Color(0.32, 0.26, 0.22)

	_add_box(house, Vector3(w, 0.14, d), Vector3(0, 0.07, 0), Color(0.4, 0.32, 0.24), "Floor")
	_make_fence(house, Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, 0.24), wall_color, "brick")
	_make_fence(house, Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.24, h, d), wall_color, "brick")
	_make_fence(house, Vector3(w * 0.5, h * 0.5, 0), Vector3(0.24, h, d), wall_color, "brick")
	_wall_with_door(house, Vector3(0, h * 0.5, -d * 0.5), w, h, 0.24, wall_color, 1.8, "x", "brick")

	# Internal wall dividing kitchen (front, z<0) from sitting room (back, z>0).
	_wall_with_door(house, Vector3(0, h * 0.5, 0.0), w, h, 0.18, trim_color, 1.6, "x", "wood")

	# Brick texture cue — horizontal trim bands on the outside
	for y in [0.55, 1.3, 2.05]:
		_add_box(house, Vector3(w + 0.05, 0.06, d + 0.05), Vector3(0, y, 0), Color(0.36, 0.18, 0.12), "BrickBand")

	# Low-pitched roof
	var roof_h: float = 1.0
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(w + 0.5, roof_h, d + 0.5)
	roof.mesh = prism
	roof.position = Vector3(0, h + roof_h * 0.5, 0)
	roof.material_override = _style_mat(Color(0.16, 0.12, 0.1), 0.9)
	house.add_child(roof)

	# Windows in the outer walls
	_add_window(house, Vector3(-w * 0.5 - 0.06, 1.7, -1.5), Vector3(0.08, 0.7, 1.1))
	_add_window(house, Vector3(-w * 0.5 - 0.06, 1.7, 1.5), Vector3(0.08, 0.7, 1.1))
	_add_window(house, Vector3(w * 0.5 + 0.06, 1.7, -1.5), Vector3(0.08, 0.7, 1.1))
	_add_window(house, Vector3(w * 0.5 + 0.06, 1.7, 1.5), Vector3(0.08, 0.7, 1.1))
	_add_window(house, Vector3(0, 1.7, d * 0.5 + 0.07), Vector3(1.2, 0.7, 0.08))

	# Kitchen (front half — south side of internal wall)
	_add_box(house, Vector3(1.8, 0.9, 0.7), Vector3(-1.6, 0.45, -d * 0.5 + 0.6), Color(0.5, 0.45, 0.36), "Counter")
	_add_box(house, Vector3(0.7, 1.6, 0.7), Vector3(0.6, 0.8, -d * 0.5 + 0.6), Color(0.85, 0.85, 0.85), "Fridge")
	_add_box(house, Vector3(0.9, 0.85, 0.7), Vector3(1.8, 0.42, -d * 0.5 + 0.6), Color(0.25, 0.25, 0.28), "Stove")
	_add_box(house, Vector3(0.18, 0.18, 0.18), Vector3(1.8, 0.95, -d * 0.5 + 0.6), Color(0.18, 0.18, 0.2), "Burner")

	# Sitting room (back half — north side of internal wall)
	_add_box(house, Vector3(2.2, 0.55, 0.95), Vector3(-1.3, 0.27, 1.6), Color(0.28, 0.18, 0.1), "Sofa")
	_add_box(house, Vector3(2.2, 0.45, 0.32), Vector3(-1.3, 0.6, 2.0), Color(0.32, 0.2, 0.12), "SofaBack")
	_add_box(house, Vector3(0.95, 0.4, 0.6), Vector3(1.5, 0.2, 1.4), Color(0.22, 0.14, 0.08), "CoffeeTable")
	_add_box(house, Vector3(0.7, 0.9, 0.32), Vector3(w * 0.5 - 0.4, 0.45, 0.8), Color(0.32, 0.22, 0.14), "Bookshelf")

	# Door header + lamps
	_add_box(house, Vector3(2.0, 0.16, 0.22), Vector3(0, 2.16, -d * 0.5 - 0.08), trim_color, "DoorHeader")
	_add_glow_box(house, Vector3(0.32, 0.28, 0.32), Vector3(-1.5, h - 0.45, -1.0), Color(1.0, 0.85, 0.58), 1.2)
	_add_glow_box(house, Vector3(0.32, 0.28, 0.32), Vector3(-1.5, h - 0.45, 1.6), Color(1.0, 0.85, 0.58), 1.2)


# Variant 3: Suburban — three rooms (kitchen / living / bedroom) + porch.
func _house_suburban(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var house := Node3D.new()
	house.name = "SuburbanHouse"
	house.position = pos
	house.rotation.y = yaw
	parent.add_child(house)

	var w: float = 7.6
	var h: float = 2.9
	var d: float = 6.6
	var wall_color: Color = Color(0.78, 0.74, 0.64)
	var trim_color: Color = Color(0.32, 0.26, 0.18)

	_add_box(house, Vector3(w, 0.14, d), Vector3(0, 0.07, 0), Color(0.42, 0.34, 0.24), "Floor")
	_make_fence(house, Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, 0.22), wall_color, "wood")
	_make_fence(house, Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.22, h, d), wall_color, "wood")
	_make_fence(house, Vector3(w * 0.5, h * 0.5, 0), Vector3(0.22, h, d), wall_color, "wood")
	_wall_with_door(house, Vector3(0, h * 0.5, -d * 0.5), w, h, 0.22, wall_color, 1.8, "x", "wood")

	# Interior wall #1 — splits the front half (kitchen) from the back, with
	# a centered doorway so the player can pass through.
	var int_a_z: float = -0.6
	_wall_with_door(house, Vector3(0, h * 0.5, int_a_z), w, h, 0.16, trim_color, 1.8, "x", "wood")

	# Interior wall #2 — splits the back half into living room (west) and
	# bedroom (east). Spans from int_a_z to the back wall with a doorway.
	var int_b_x: float = 0.8
	var int_b_span: float = (d * 0.5) - int_a_z
	var int_b_center_z: float = (int_a_z + d * 0.5) * 0.5
	_wall_with_door(house, Vector3(int_b_x, h * 0.5, int_b_center_z), int_b_span, h, 0.16, trim_color, 1.4, "z", "wood")

	# Pitched roof
	var roof_h: float = 1.4
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(w + 0.6, roof_h, d + 0.6)
	roof.mesh = prism
	roof.position = Vector3(0, h + roof_h * 0.5, 0)
	roof.material_override = _style_mat(Color(0.42, 0.22, 0.14), 0.9)
	house.add_child(roof)

	# Front porch with two posts
	_add_box(house, Vector3(w + 0.4, 0.18, 1.4), Vector3(0, 0.09, -d * 0.5 - 0.8), Color(0.34, 0.22, 0.14), "Porch")
	for x in [-w * 0.5 + 0.3, w * 0.5 - 0.3]:
		_add_box(house, Vector3(0.22, 2.2, 0.22), Vector3(x, 1.1, -d * 0.5 - 1.4), Color(0.32, 0.2, 0.12), "PorchPost")
	_add_box(house, Vector3(w + 0.4, 0.12, 1.6), Vector3(0, 2.3, -d * 0.5 - 0.9), Color(0.3, 0.18, 0.1), "PorchCeil")

	# Windows
	_add_window(house, Vector3(-w * 0.5 - 0.06, 1.7, -1.5), Vector3(0.08, 0.7, 1.1))
	_add_window(house, Vector3(-w * 0.5 - 0.06, 1.7, 1.6), Vector3(0.08, 0.7, 1.1))
	_add_window(house, Vector3(w * 0.5 + 0.06, 1.7, -1.5), Vector3(0.08, 0.7, 1.1))
	_add_window(house, Vector3(w * 0.5 + 0.06, 1.7, 1.6), Vector3(0.08, 0.7, 1.1))
	_add_window(house, Vector3(2.0, 1.7, d * 0.5 + 0.07), Vector3(1.4, 0.7, 0.08))

	# Kitchen (front room — small)
	_add_box(house, Vector3(2.4, 0.9, 0.6), Vector3(-1.4, 0.45, -d * 0.5 + 0.5), Color(0.62, 0.58, 0.5), "KitCounter")
	_add_box(house, Vector3(0.65, 1.5, 0.6), Vector3(0.2, 0.75, -d * 0.5 + 0.5), Color(0.86, 0.86, 0.84), "Fridge")
	_add_box(house, Vector3(0.85, 0.85, 0.6), Vector3(1.4, 0.42, -d * 0.5 + 0.5), Color(0.22, 0.22, 0.24), "Stove")

	# Living room (back-left)
	_add_box(house, Vector3(2.0, 0.5, 0.85), Vector3(-1.8, 0.25, 1.5), Color(0.26, 0.34, 0.42), "Sofa")
	_add_box(house, Vector3(2.0, 0.42, 0.3), Vector3(-1.8, 0.6, 1.92), Color(0.22, 0.3, 0.38), "SofaBack")
	_add_box(house, Vector3(0.85, 0.4, 0.55), Vector3(-1.0, 0.2, 0.5), Color(0.2, 0.13, 0.08), "CoffeeTable")
	_add_box(house, Vector3(0.92, 0.5, 0.18), Vector3(-1.0, 0.55, d * 0.5 - 0.35), Color(0.1, 0.12, 0.14), "TV")

	# Bedroom (back-right)
	_add_box(house, Vector3(1.9, 0.42, 1.05), Vector3(w * 0.5 - 1.4, 0.21, 1.2), Color(0.32, 0.22, 0.16), "Bed")
	_add_box(house, Vector3(1.9, 0.22, 1.05), Vector3(w * 0.5 - 1.4, 0.55, 1.2), Color(0.52, 0.32, 0.24), "Bedspread")
	_add_box(house, Vector3(0.45, 0.22, 0.6), Vector3(w * 0.5 - 1.85, 0.66, 0.5), Color(0.96, 0.92, 0.84), "Pillow")
	_add_box(house, Vector3(0.65, 0.95, 0.42), Vector3(w * 0.5 - 0.4, 0.48, 2.4), Color(0.34, 0.22, 0.14), "Dresser")

	# Lamps
	_add_box(house, Vector3(2.0, 0.16, 0.22), Vector3(0, 2.16, -d * 0.5 - 0.08), trim_color, "DoorHeader")
	_add_glow_box(house, Vector3(0.32, 0.28, 0.32), Vector3(-1.6, h - 0.45, -1.6), Color(1.0, 0.85, 0.58), 1.2)
	_add_glow_box(house, Vector3(0.32, 0.28, 0.32), Vector3(-1.6, h - 0.45, 1.6), Color(1.0, 0.85, 0.58), 1.2)
	_add_glow_box(house, Vector3(0.32, 0.28, 0.32), Vector3(w * 0.5 - 1.4, h - 0.45, 1.6), Color(1.0, 0.85, 0.58), 1.2)
	_add_glow_box(house, Vector3(0.18, 0.18, 0.22), Vector3(0, 1.9, -d * 0.5 - 1.4), Color(1.0, 0.78, 0.42), 1.5)


# Variant 4: Lodge — larger single room with vaulted feel, bunks, big table.
func _house_lodge(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var house := Node3D.new()
	house.name = "Lodge"
	house.position = pos
	house.rotation.y = yaw
	parent.add_child(house)

	var w: float = 9.0
	var h: float = 3.2
	var d: float = 7.0
	var wall_color: Color = Color(0.34, 0.22, 0.13)
	var trim_color: Color = Color(0.18, 0.11, 0.07)

	_add_box(house, Vector3(w, 0.14, d), Vector3(0, 0.07, 0), Color(0.28, 0.2, 0.13), "Floor")
	_make_fence(house, Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, 0.24), wall_color, "wood")
	_make_fence(house, Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.24, h, d), wall_color, "wood")
	_make_fence(house, Vector3(w * 0.5, h * 0.5, 0), Vector3(0.24, h, d), wall_color, "wood")
	_wall_with_door(house, Vector3(0, h * 0.5, -d * 0.5), w, h, 0.24, wall_color, 2.0, "x", "wood")

	# Sloped lodge roof with rafters
	var roof_h: float = 2.0
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(w + 0.7, roof_h, d + 0.7)
	roof.mesh = prism
	roof.position = Vector3(0, h + roof_h * 0.5, 0)
	roof.material_override = _style_mat(Color(0.14, 0.1, 0.08), 0.9)
	house.add_child(roof)
	# Visible rafters from below
	for z in [-2.4, -0.8, 0.8, 2.4]:
		_add_box(house, Vector3(w - 0.4, 0.18, 0.18), Vector3(0, h + 0.2, z), Color(0.22, 0.14, 0.08), "Rafter")

	# Windows along both side walls + a big front window
	for z in [-2.0, 0.0, 2.0]:
		_add_window(house, Vector3(-w * 0.5 - 0.06, 1.7, z), Vector3(0.08, 0.8, 1.0))
		_add_window(house, Vector3(w * 0.5 + 0.06, 1.7, z), Vector3(0.08, 0.8, 1.0))
	_add_window(house, Vector3(0, 1.85, d * 0.5 + 0.07), Vector3(2.4, 1.0, 0.08))

	# Long communal table down the middle
	_add_box(house, Vector3(3.6, 0.18, 1.2), Vector3(0, 0.75, 0), Color(0.36, 0.22, 0.12), "LongTable")
	for x in [-1.5, 1.5]:
		for z in [-0.45, 0.45]:
			_add_box(house, Vector3(0.14, 0.75, 0.14), Vector3(x, 0.37, z), Color(0.26, 0.16, 0.08), "TableLeg")
	# Benches either side
	_add_box(house, Vector3(3.6, 0.18, 0.42), Vector3(0, 0.4, -0.95), Color(0.32, 0.2, 0.1), "BenchN")
	_add_box(house, Vector3(3.6, 0.18, 0.42), Vector3(0, 0.4, 0.95), Color(0.32, 0.2, 0.1), "BenchS")

	# Bunk beds along the west wall
	_add_box(house, Vector3(0.9, 0.35, 1.9), Vector3(-w * 0.5 + 0.7, 0.22, 2.0), Color(0.28, 0.18, 0.1), "BunkLower")
	_add_box(house, Vector3(0.9, 0.2, 1.9), Vector3(-w * 0.5 + 0.7, 0.5, 2.0), Color(0.6, 0.4, 0.22), "BunkLowerQuilt")
	_add_box(house, Vector3(0.9, 0.35, 1.9), Vector3(-w * 0.5 + 0.7, 1.7, 2.0), Color(0.28, 0.18, 0.1), "BunkUpper")
	_add_box(house, Vector3(0.9, 0.2, 1.9), Vector3(-w * 0.5 + 0.7, 2.0, 2.0), Color(0.4, 0.26, 0.16), "BunkUpperQuilt")
	# Bunk ladder
	for y in [0.55, 0.95, 1.35]:
		_add_box(house, Vector3(0.2, 0.05, 0.42), Vector3(-w * 0.5 + 1.3, y, 0.6), Color(0.24, 0.16, 0.1), "BunkLadder")

	# Big fireplace on the back wall
	_add_box(house, Vector3(2.2, 1.6, 0.9), Vector3(0, 0.8, d * 0.5 - 0.6), Color(0.34, 0.34, 0.36), "Hearth")
	_add_glow_box(house, Vector3(1.6, 0.55, 0.4), Vector3(0, 0.45, d * 0.5 - 0.95), Color(1.0, 0.45, 0.12), 1.8)
	_add_box(house, Vector3(1.1, h + roof_h + 0.6, 1.1), Vector3(0, (h + roof_h + 0.6) * 0.5, d * 0.5 - 0.4), Color(0.3, 0.3, 0.32), "Chimney")

	# Lamps + door header
	_add_box(house, Vector3(2.4, 0.18, 0.26), Vector3(0, h - 0.2, -d * 0.5 - 0.08), trim_color, "DoorHeader")
	_add_glow_box(house, Vector3(0.36, 0.36, 0.36), Vector3(-2.5, h - 0.4, 0), Color(1.0, 0.82, 0.42), 1.6)
	_add_glow_box(house, Vector3(0.36, 0.36, 0.36), Vector3(2.5, h - 0.4, 0), Color(1.0, 0.82, 0.42), 1.6)


func _build_settlements(parent: Node3D) -> void:
	var settlements: Array[Dictionary] = [
		{"name": "Snow Hamlet", "center": Vector3(450, 0, -650), "count": 7, "spread": 32.0},
		{"name": "Desert Outpost", "center": Vector3(-1500, 0, 100), "count": 6, "spread": 38.0},
		{"name": "River Shacks", "center": Vector3(-225, 0, 295), "count": 8, "spread": 30.0},
		{"name": "Plainstead", "center": Vector3(-200, 0, 1450), "count": 7, "spread": 42.0},
		{"name": "Autumn Cabins", "center": Vector3(300, 0, -1350), "count": 6, "spread": 36.0},
		{"name": "Coast Houses", "center": Vector3(1380, 0, 600), "count": 5, "spread": 34.0},
		# New POIs to fill empty quadrants — feel populated everywhere.
		{"name": "Lakeside Camp", "center": Vector3(-1000, 0, 1300), "count": 5, "spread": 30.0},
		{"name": "Hilltop Watch", "center": Vector3(1100, 0, -1450), "count": 5, "spread": 32.0},
	]
	for settlement in settlements:
		var center: Vector3 = settlement["center"]
		var count: int = int(settlement["count"])
		var spread: float = float(settlement["spread"])
		var hub := Node3D.new()
		hub.name = String(settlement["name"]).replace(" ", "")
		hub.position = center
		parent.add_child(hub)
		for i in count:
			var angle: float = TAU * float(i) / float(max(1, count))
			var ring: float = spread * (0.55 + 0.18 * float(i % 3))
			var pos := center + Vector3(cos(angle) * ring, 0.0, sin(angle) * ring)
			if i % 2 == 0:
				_make_enterable_house(parent, pos, angle + PI)
			else:
				_make_cabin(parent, pos, angle + PI)
		_add_box(parent, Vector3(spread * 1.6, 0.08, 3.0), center + Vector3(0, 0.045, 0), Color(0.22, 0.2, 0.17), "SettlementTrack")
		var label := Label3D.new()
		label.text = String(settlement["name"]).to_upper()
		label.font_size = 32
		label.outline_size = 8
		label.outline_modulate = Color(0, 0, 0, 0.85)
		label.modulate = Color(0.9, 0.84, 0.62)
		label.position = center + Vector3(0, 5.2, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		parent.add_child(label)


func _build_trees(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	# Trees are scattered across the map with a density falloff. Most cluster
	# near the player's spawn; the deep wilderness is sparse.
	_scatter_trees(parent, rng, 80, 8.0, 80.0)
	_scatter_trees(parent, rng, 160, 80.0, 280.0)
	_scatter_trees(parent, rng, 230, 280.0, 750.0)
	_scatter_trees(parent, rng, 320, 750.0, 1850.0)


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


func _build_rugged_terrain(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33071

	# Pass 1: small ground ridges — visual variation, no collision.
	for i in 200:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(80.0, 1850.0)
		var pos := Vector3(cos(angle) * radius, 0.04, sin(angle) * radius * 0.84)
		if absf(pos.x) > arena_half_x - 40.0 or absf(pos.z) > arena_half_z - 40.0:
			continue
		if pos.length() < 40.0:
			continue
		var biome := get_biome_at(pos)
		var color := Color(0.34, 0.35, 0.34)
		var key := "stone"
		if biome == "desert":
			color = Color(0.62, 0.47, 0.25)
			key = "sand"
		elif biome == "plains":
			color = Color(0.24, 0.36, 0.2)
			key = "dirt"
		elif biome == "autumn":
			color = Color(0.38, 0.22, 0.12)
			key = "dirt"
		elif biome == "river" or biome == "ocean":
			color = Color(0.1, 0.22, 0.27)
			key = "stone"
		var size := Vector3(rng.randf_range(5.0, 16.0), rng.randf_range(0.12, 0.45), rng.randf_range(1.4, 4.8))
		var ridge := MeshInstance3D.new()
		ridge.name = "GroundRidge"
		var bm := BoxMesh.new()
		bm.size = size
		ridge.mesh = bm
		ridge.position = pos
		ridge.material_override = _textured_mat(color, key, max(2.0, size.x * 0.4), 0.95)
		ridge.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.05, 0.05))
		parent.add_child(ridge)

	# Pass 2: mud ramps — visual only, gentle bumps near roads.
	for i in 28:
		var p := Vector3(rng.randf_range(-arena_half_x + 225.0, arena_half_x - 225.0), 0.06, rng.randf_range(-arena_half_z + 200.0, arena_half_z - 200.0))
		if p.length() < 80.0:
			continue
		var ramp := _add_box(parent, Vector3(rng.randf_range(8.0, 18.0), 0.35, rng.randf_range(5.0, 11.0)), p, Color(0.28, 0.25, 0.22), "MudRamp")
		ramp.material_override = _textured_mat(Color(0.28, 0.25, 0.22), "dirt", 4.0, 0.96)
		ramp.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.05, 0.05))

	# Pass 3: big biome-flavored hills/dunes/mounds — solid collision so the
	# player can climb on them (or be blocked by them). Distributed by biome.
	_build_terrain_hills(parent, rng)


func _build_terrain_hills(parent: Node3D, rng: RandomNumberGenerator) -> void:
	# Desert dunes — tall stepped wedges of sand.
	for i in 30:
		var x: float = rng.randf_range(-arena_half_x + 150.0, -arena_half_x * 0.45)
		var z: float = rng.randf_range(-arena_half_z + 150.0, arena_half_z - 150.0)
		var p := Vector3(x, 0.0, z)
		if _near_named_poi(p, 55.0):
			continue
		_make_dune(parent, p, rng.randf_range(2.0, 5.5), rng.randf_range(14.0, 32.0), rng.randf() * TAU, rng)

	# Snow hills — wide low domes.
	for i in 28:
		var x: float = rng.randf_range(-arena_half_x * 0.4, arena_half_x * 0.7)
		var z: float = rng.randf_range(-arena_half_z * 0.55, arena_half_z * 0.55)
		var p := Vector3(x, 0.0, z)
		if p.length() < 220.0:
			continue
		if get_biome_at(p) != "snow":
			continue
		if _near_named_poi(p, 55.0):
			continue
		_make_hill(parent, p, rng.randf_range(2.0, 4.0), rng.randf_range(16.0, 28.0), Color(0.82, 0.86, 0.9), "snow", rng)

	# Autumn mounds — earthy rolling hills near the southern edge.
	for i in 22:
		var x: float = rng.randf_range(-arena_half_x * 0.55, arena_half_x * 0.55)
		var z: float = rng.randf_range(-arena_half_z, -arena_half_z * 0.4)
		var p := Vector3(x, 0.0, z)
		if get_biome_at(p) != "autumn":
			continue
		if _near_named_poi(p, 55.0):
			continue
		_make_hill(parent, p, rng.randf_range(2.5, 5.0), rng.randf_range(14.0, 22.0), Color(0.42, 0.24, 0.13), "dirt", rng)

	# Plains gentle bumps — minimal, just enough to break flatness.
	for i in 14:
		var x: float = rng.randf_range(-arena_half_x * 0.55, arena_half_x * 0.55)
		var z: float = rng.randf_range(arena_half_z * 0.35, arena_half_z * 0.92)
		var p := Vector3(x, 0.0, z)
		if get_biome_at(p) != "plains":
			continue
		if _near_named_poi(p, 55.0):
			continue
		_make_hill(parent, p, rng.randf_range(1.2, 2.5), rng.randf_range(12.0, 22.0), Color(0.32, 0.46, 0.26), "dirt", rng)

	# Generic gray rocky outcrops anywhere — biome-agnostic stone uplifts.
	for i in 18:
		var x: float = rng.randf_range(-arena_half_x + 200.0, arena_half_x - 200.0)
		var z: float = rng.randf_range(-arena_half_z + 200.0, arena_half_z - 200.0)
		var p := Vector3(x, 0.0, z)
		if p.length() < 180.0:
			continue
		if _near_named_poi(p, 50.0):
			continue
		_make_outcrop(parent, p, rng.randf_range(1.8, 3.6), rng.randf_range(6.0, 12.0), rng)


# Stepped sand dune — slanted wedge of stacked boxes. Climbable on the
# shallow side.
func _make_dune(parent: Node3D, pos: Vector3, height: float, width: float, yaw: float, rng: RandomNumberGenerator) -> void:
	var dune := StaticBody3D.new()
	dune.name = "Dune"
	dune.position = pos
	dune.rotation.y = yaw
	parent.add_child(dune)
	var sand_color := Color(0.86, 0.68, 0.34)
	var steps: int = 5
	for i in steps:
		var step_h: float = height / float(steps)
		var w: float = width * (1.0 - float(i) * 0.13)
		var d: float = width * 0.55 * (1.0 - float(i) * 0.15)
		var y: float = step_h * 0.5 + float(i) * step_h
		var z_off: float = (height * float(i) / float(steps)) * 0.8
		var size := Vector3(w, step_h, d)
		var col := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		col.shape = sh
		col.position = Vector3(0, y, z_off - height * 0.4)
		dune.add_child(col)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = col.position
		mi.material_override = _textured_mat(sand_color.darkened(float(i) * 0.04), "sand", max(2.0, w * 0.25), 0.96)
		dune.add_child(mi)


# Wide low dome made of progressively smaller stacked boxes. Player can
# walk up the lower steps if the height per step is small enough.
func _make_hill(parent: Node3D, pos: Vector3, height: float, width: float, color: Color, texture_key: String, rng: RandomNumberGenerator) -> void:
	var hill := StaticBody3D.new()
	hill.name = "Hill"
	hill.position = pos
	hill.rotation.y = rng.randf() * TAU
	parent.add_child(hill)
	var layers: int = 4
	for i in layers:
		var step_h: float = height / float(layers)
		var shrink: float = 1.0 - float(i) * 0.22
		var w: float = width * shrink
		var d: float = width * shrink * rng.randf_range(0.85, 1.05)
		var y: float = step_h * 0.5 + float(i) * step_h * 0.85
		var size := Vector3(w, step_h, d)
		var col := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		col.shape = sh
		col.position = Vector3(0, y, 0)
		hill.add_child(col)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = col.position
		# Slight tilt per layer for visual organic-ness.
		mi.rotation = Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.4, 0.4), rng.randf_range(-0.06, 0.06))
		mi.material_override = _textured_mat(color.darkened(float(i) * 0.05), texture_key, max(2.0, w * 0.25), 0.95)
		hill.add_child(mi)


# Rocky outcrop — a chunky pile of irregularly-stacked stone boxes.
func _make_outcrop(parent: Node3D, pos: Vector3, height: float, width: float, rng: RandomNumberGenerator) -> void:
	var outcrop := StaticBody3D.new()
	outcrop.name = "Outcrop"
	outcrop.position = pos
	outcrop.rotation.y = rng.randf() * TAU
	parent.add_child(outcrop)
	var stone_color := Color(0.45, 0.45, 0.46)
	var chunks: int = 4
	for i in chunks:
		var h: float = height * rng.randf_range(0.5, 1.0)
		var w: float = width * rng.randf_range(0.55, 1.0)
		var d: float = width * rng.randf_range(0.55, 1.0)
		var ox: float = rng.randf_range(-width * 0.3, width * 0.3)
		var oz: float = rng.randf_range(-width * 0.3, width * 0.3)
		var y: float = h * 0.5 + rng.randf_range(-0.2, 0.4)
		var size := Vector3(w, h, d)
		var col := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		col.shape = sh
		col.position = Vector3(ox, y, oz)
		col.rotation = Vector3(rng.randf_range(-0.18, 0.18), rng.randf() * TAU, rng.randf_range(-0.18, 0.18))
		outcrop.add_child(col)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = col.position
		mi.rotation = col.rotation
		mi.material_override = _textured_mat(stone_color.darkened(rng.randf_range(0.0, 0.18)), "stone", max(2.0, w * 0.3), 0.95)
		outcrop.add_child(mi)


# Quick "is this point near a placed POI" check so terrain features don't
# spawn on top of settlements/sanctuary/mine/objective.
func _near_named_poi(pos: Vector3, radius: float) -> bool:
	if pos.length() < SAFE_ZONE_RADIUS + radius:
		return true
	var pois: Array = [
		# Settlements
		Vector3(450, 0, -650), Vector3(-1500, 0, 100), Vector3(-225, 0, 295),
		Vector3(-200, 0, 1450), Vector3(300, 0, -1350), Vector3(1380, 0, 600),
		Vector3(-1000, 0, 1300), Vector3(1100, 0, -1450),
		# Mine + objective
		Vector3(-1075, 0, 275), OBJECTIVE_POS,
		# Desert caves
		Vector3(-1750, 0, 600), Vector3(-1820, 0, -480),
		Vector3(-1300, 0, -1450), Vector3(-1640, 0, 1180),
	]
	for c in pois:
		if pos.distance_to(c) < radius:
			return true
	return false


func _scatter_field_vehicles(parent: Node3D) -> void:
	# Each entry: [position, yaw, vehicle_type]. Types are picked roughly by
	# biome — snowmobiles in snow, ATVs/sedans in desert, etc.
	var placements: Array = [
		# Near spawn — varied so players see options immediately
		[Vector3(-62, 0.7, 54),      0.0,  "truck"],
		[Vector3(48, 0.7, -68),      1.6,  "motorcycle"],
		[Vector3(140, 0.7, 32),     -0.6,  "atv"],
		[Vector3(-90, 0.7, -65),     2.4,  "snowmobile"],
		[Vector3(-110, 0.7, 90),     1.2,  "sedan"],
		# Snow region scattered
		[Vector3(180, 0.7, -205),    0.73, "snowmobile"],
		[Vector3(-375, 0.7, 380),    1.46, "truck"],
		[Vector3(-205, 0.7, -495),   2.1,  "sedan"],
		[Vector3(470, 0.7, -410),    3.0,  "motorcycle"],
		[Vector3(550, 0.7, 370),     0.3,  "snowmobile"],
		# Desert region
		[Vector3(-1370, 0.7, -195),  2.19, "atv"],
		[Vector3(-1070, 0.7, 295),   2.92, "atv"],
		[Vector3(-1275, 0.7, 475),   1.05, "motorcycle"],
		[Vector3(-950, 0.7, -550),   4.1,  "sedan"],
		# Plains
		[Vector3(635, 0.7, 1045),    3.65, "sedan"],
		[Vector3(925, 0.7, 975),     0.9,  "bus"],
		[Vector3(375, 0.7, 1150),    2.2,  "atv"],
		# Autumn woods
		[Vector3(-305, 0.7, -1055),  4.38, "truck"],
		[Vector3(-700, 0.7, -950),   1.7,  "motorcycle"],
		[Vector3(300, 0.7, -925),    3.4,  "sedan"],
		# Coast
		[Vector3(1540, 0.7, 305),    5.11, "motorcycle"],
		[Vector3(1130, 0.7, -800),   0.4,  "bus"],
		[Vector3(1450, 0.7, -300),   1.9,  "sedan"],
		# Road convoy — a small lineup on the trail leading to the radio tower
		[Vector3(900, 0.7, -600),    0.7,  "truck"],
		[Vector3(910, 0.7, -620),    0.7,  "sedan"],
		[Vector3(920, 0.7, -643),    0.7,  "motorcycle"],
	]
	for entry in placements:
		_spawn_field_vehicle(parent, entry[0], float(entry[1]), String(entry[2]))


func _spawn_field_vehicle(parent: Node3D, pos: Vector3, yaw: float, type_id: String = "truck") -> void:
	var script := load("res://scripts/vehicle.gd") as GDScript
	var v: CharacterBody3D = script.new()
	v.vehicle_type = type_id
	v.name = type_id.capitalize() + "Field"
	parent.add_child(v)
	v.global_position = pos
	v.rotation.y = yaw


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
	trunk_mesh.material_override = _textured_mat(Color(0.36, 0.25, 0.16), "bark", 4.0, 0.95)
	sb.add_child(trunk_mesh)

	var foliage_mat: ShaderMaterial = _get_foliage_mat(Color(0.12, 0.3, 0.22))

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


func _make_fence(parent: Node3D, pos: Vector3, size: Vector3, color: Color, texture_key: String = "") -> void:
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
	var mat: StandardMaterial3D
	if texture_key != "":
		# Scale UVs by the larger face dim so texel density stays consistent
		# across thin/long wall segments.
		var s: float = max(1.0, max(size.x, max(size.y, size.z)) * 0.6)
		mat = _textured_mat(color, texture_key, s, 0.95)
	else:
		mat = StandardMaterial3D.new()
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
	while placed < 86 and attempts < 860:
		attempts += 1
		var angle: float = rng.randf() * TAU
		var r: float = rng.randf_range(20.0, 1400.0)
		var p := Vector3(cos(angle) * r, 1.0, sin(angle) * r * 0.84)
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
	# Burning Club — a portable warmth source. Placed near spawn so new
	# players can grab it before venturing into the storm.
	_spawn_resource(parent, Vector3(14.0, 0.0, 8.0), "Burning Club", "wood", 0, 1, "weapon", "Burning Club")
	_spawn_resource(parent, Vector3(-1480.0, 0.0, 220.0), "Burning Club", "wood", 0, 1, "weapon", "Burning Club")
	_spawn_resource(parent, Vector3(420.0, 0.0, -1100.0), "Burning Club", "wood", 0, 1, "weapon", "Burning Club")
	_spawn_resource(parent, Vector3(190.0, 0.0, 173.0), "River Spear", "wood", 0, 1, "weapon", "Spear")
	_spawn_resource(parent, Vector3(72.0, 0.0, 46.0), "Hunting Knife", "wood", 0, 1, "weapon", "Knife")
	_spawn_resource(parent, Vector3(-320.0, 0.0, -890.0), "Brush Machete", "wood", 0, 1, "weapon", "Machete")
	_spawn_resource(parent, Vector3(715.0, 0.0, 1030.0), "Old Rifle", "wood", 0, 1, "weapon", "Rifle")
	_spawn_resource(parent, Vector3(-1300.0, 0.0, -230.0), "Pump Shotgun", "wood", 0, 1, "weapon", "Shotgun")
	_spawn_resource(parent, OBJECTIVE_POS + Vector3(-18.0, 0.0, 8.0), "Signal Pistol", "wood", 0, 1, "weapon", "Pistol")
	_scatter_random_weapon_pickups(parent)

	var wood_points := [
		Vector3(9, 0, -12), Vector3(-8, 0, 12), Vector3(24, 0, 28),
		Vector3(-42, 0, 34), Vector3(120, 0, -88), Vector3(-180, 0, 70),
		Vector3(350, 0, 1005), Vector3(470, 0, 1120), Vector3(-175, 0, -970),
		Vector3(125, 0, -1105), Vector3(755, 0, -400), Vector3(-650, 0, 475),
	]
	for p in wood_points:
		_spawn_resource(parent, p, "Wood", "wood", 4, 1, "wood")

	var stone_points := [
		Vector3(16, 0, 38), Vector3(-35, 0, -42), Vector3(220, 0, 140),
		Vector3(-380, 0, 120), Vector3(-1060, 0, 305), Vector3(-1025, 0, 245),
		Vector3(-980, 0, 340), Vector3(875, 0, -638),
	]
	for p in stone_points:
		_spawn_resource(parent, p, "Stone", "stone", 3, 1, "stone")

	var mine_pos := Vector3(-1075, 0, 275)
	_make_mine_entrance(parent, mine_pos, PI * 0.38)
	for i in 10:
		var offset := Vector3(-18.0 + i * 4.0, 0.0, -8.0 + (i % 3) * 5.5)
		_spawn_resource(parent, mine_pos + offset, "Ore Vein", "ore", 3, 4, "mine")
	for i in 6:
		var x := -600.0 + i * 190.0
		_spawn_resource(parent, Vector3(x, 0.0, 225.0 - x * 0.3 + 20.0), "Fish", "fish", 1, 1, "fish")
	for i in 7:
		_spawn_resource(parent, Vector3(1525.0 + i * 45.0, 0.0, -525.0 + i * 135.0), "Ocean Fish", "fish", 2, 1, "fish")
	_scatter_resource_density(parent)


func _scatter_random_weapon_pickups(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55140
	var pool := [
		["Rusty Knife", "Knife"],
		["Trail Machete", "Machete"],
		["Hunter Rifle", "Rifle"],
		["Sawed Shotgun", "Shotgun"],
		["Spare Pistol", "Pistol"],
		["Field Axe", "Axe"],
		["Long Spear", "Spear"],
	]
	for i in 46:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(120.0, 1400.0)
		var p := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius * 0.86)
		p.x = clamp(p.x, -arena_half_x + 30.0, arena_half_x - 30.0)
		p.z = clamp(p.z, -arena_half_z + 30.0, arena_half_z - 30.0)
		if p.length() < 60.0:
			continue
		var choice: Array = pool[rng.randi_range(0, pool.size() - 1)]
		_spawn_resource(parent, p, String(choice[0]), "wood", 0, 1, "weapon", String(choice[1]))


func _scatter_resource_density(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 88031
	for i in 58:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(40.0, 1350.0)
		var p := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius * 0.86)
		var biome := get_biome_at(p)
		if biome == "ocean":
			_spawn_resource(parent, p, "Ocean Fish", "fish", 2, 1, "fish")
		elif biome == "river":
			_spawn_resource(parent, p, "Fish", "fish", 1, 1, "fish")
		elif biome == "desert":
			_spawn_resource(parent, p, "Stone", "stone", 2, 1, "stone")
		elif biome == "plains" or biome == "autumn":
			_spawn_resource(parent, p, "Wood", "wood", 4, 1, "wood")
		else:
			_spawn_resource(parent, p, "Stone", "stone", 3, 1, "stone")


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


func _build_desert_caves(parent: Node3D) -> void:
	# A few cave mouths in the western desert. Each is a sandstone arch with
	# a dark interior recess — visual landmark + future loot/encounter spot.
	var caves: Array = [
		[Vector3(-1750.0, 0.0, 600.0),  -PI * 0.18],
		[Vector3(-1820.0, 0.0, -480.0),  PI * 0.12],
		[Vector3(-1300.0, 0.0, -1450.0), PI * 0.55],
		[Vector3(-1640.0, 0.0, 1180.0), -PI * 0.65],
	]
	for entry in caves:
		_make_desert_cave(parent, entry[0], float(entry[1]))


func _make_desert_cave(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var cave := Node3D.new()
	cave.name = "DesertCave"
	cave.position = pos
	cave.rotation.y = yaw
	parent.add_child(cave)

	# Surrounding rock formation — irregular boulders piled around the mouth.
	_add_box(cave, Vector3(12.0, 6.5, 3.0), Vector3(0, 3.0, 2.6), Color(0.68, 0.52, 0.32), "CaveCliff")
	_add_box(cave, Vector3(4.6, 4.6, 4.2), Vector3(-4.0, 2.3, 0.6), Color(0.74, 0.55, 0.3), "CaveBoulderL")
	_add_box(cave, Vector3(4.2, 4.0, 3.8), Vector3(4.2, 2.0, 0.4), Color(0.7, 0.5, 0.28), "CaveBoulderR")
	_add_box(cave, Vector3(3.5, 2.2, 2.5), Vector3(-2.5, 5.2, 1.2), Color(0.62, 0.46, 0.26), "CaveBoulderTop")
	_add_box(cave, Vector3(2.8, 1.6, 2.0), Vector3(3.0, 5.6, 0.9), Color(0.66, 0.48, 0.28), "CaveBoulderTopR")

	# Mouth opening — dark interior. Tilted slightly so it looks carved.
	var arch_h: float = 3.8
	_add_box(cave, Vector3(1.0, arch_h, 1.4), Vector3(-2.2, arch_h * 0.5, -0.2), Color(0.18, 0.12, 0.08), "CaveJambL")
	_add_box(cave, Vector3(1.0, arch_h, 1.4), Vector3(2.2, arch_h * 0.5, -0.2), Color(0.18, 0.12, 0.08), "CaveJambR")
	_add_box(cave, Vector3(5.5, 0.8, 1.4), Vector3(0, arch_h - 0.2, -0.2), Color(0.16, 0.1, 0.06), "CaveLintel")
	_add_box(cave, Vector3(3.6, arch_h - 0.6, 1.4), Vector3(0, (arch_h - 0.6) * 0.5, -0.4), Color(0.025, 0.03, 0.04), "CaveInterior")

	# Faint torch glow inside so the cave reads as "occupied" at night.
	_add_glow_box(cave, Vector3(0.35, 0.35, 0.22), Vector3(-1.3, 2.2, -0.6), Color(1.0, 0.55, 0.18), 1.4)
	_add_glow_box(cave, Vector3(0.35, 0.35, 0.22), Vector3(1.3, 2.2, -0.6), Color(1.0, 0.55, 0.18), 1.4)

	# Sand drift at the entrance.
	_add_box(cave, Vector3(7.0, 0.18, 1.6), Vector3(0, 0.09, -1.0), Color(0.86, 0.66, 0.34), "CaveSand")

	var label := Label3D.new()
	label.text = "CAVE"
	label.font_size = 30
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.modulate = Color(0.96, 0.78, 0.42)
	label.position = Vector3(0, 7.6, -0.4)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	cave.add_child(label)


func _follow_player_with_snow() -> void:
	if _snow_particles == null or not is_instance_valid(_snow_particles):
		return
	if not _snow_particles.emitting:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var p_pos: Vector3 = (player as Node3D).global_position
	_snow_particles.global_position = Vector3(p_pos.x, p_pos.y + 22.0, p_pos.z)


func _build_snow_particles(parent: Node3D) -> void:
	# Box of falling snow that hovers above the player. Only emits during
	# snowstorm/blizzard weather. Followed in _process so it travels with
	# the player rather than being a fixed-position effect.
	var p := GPUParticles3D.new()
	p.name = "SnowParticles"
	p.amount = 700
	p.lifetime = 5.0
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.preprocess = 2.0
	p.visibility_aabb = AABB(Vector3(-40, -25, -40), Vector3(80, 50, 80))

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.gravity = Vector3(0, -3.0, 0)
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.2
	pm.scale_min = 0.05
	pm.scale_max = 0.12
	pm.color = Color(0.95, 0.98, 1.0, 0.9)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(35.0, 0.2, 35.0)
	p.process_material = pm

	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.98, 1.0, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.35
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm

	p.position = Vector3(0, 22.0, 0)
	parent.add_child(p)
	_snow_particles = p


func _build_starfield(parent: Node3D) -> void:
	# Stars are tiny unshaded emissive points arranged on a sphere shell high
	# above the playable area. Hidden by default; the day/night phase flips
	# them on when night begins (see _on_phase_changed).
	var stars := Node3D.new()
	stars.name = "Starfield"
	stars.visible = false
	parent.add_child(stars)
	_starfield = stars

	var rng := RandomNumberGenerator.new()
	rng.seed = 9971
	var palette: Array = [
		Color(1.0, 1.0, 1.0),
		Color(0.85, 0.92, 1.0),
		Color(1.0, 0.95, 0.8),
		Color(0.95, 0.88, 1.0),
		Color(0.7, 0.85, 1.0),
	]
	var dome_radius: float = 2200.0
	for i in 240:
		var theta: float = rng.randf() * TAU
		# Bias phi away from the horizon so stars cluster near the zenith.
		var phi: float = rng.randf_range(0.05, 1.35)
		var pos := Vector3(
			cos(theta) * sin(phi) * dome_radius,
			cos(phi) * dome_radius,
			sin(theta) * sin(phi) * dome_radius
		)
		var star := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var size: float = rng.randf_range(1.8, 4.5)
		sm.radius = size
		sm.height = size * 2.0
		sm.radial_segments = 5
		sm.rings = 4
		star.mesh = sm
		star.position = pos
		var mat := StandardMaterial3D.new()
		var col: Color = palette[rng.randi() % palette.size()]
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = rng.randf_range(2.5, 5.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.disable_receive_shadows = true
		star.material_override = mat
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stars.add_child(star)

	# A moon disc — also unshaded, sits at a fixed direction.
	var moon := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 110.0
	mm.height = 220.0
	moon.mesh = mm
	moon.position = Vector3(-900.0, 1700.0, -1500.0)
	var moon_mat := StandardMaterial3D.new()
	moon_mat.albedo_color = Color(0.92, 0.94, 0.98)
	moon_mat.emission_enabled = true
	moon_mat.emission = Color(0.78, 0.85, 0.95)
	moon_mat.emission_energy_multiplier = 1.6
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon.material_override = moon_mat
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.add_child(moon)


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


func _seed_regional_zombies(parent: Node3D) -> void:
	if zombie_scene == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 44291
	var regions := [
		{"center": Vector3(0, 0, 0), "radius": 340.0, "count": 18, "type": "snow"},
		{"center": Vector3(-1400, 0, -200), "radius": 375.0, "count": 18, "type": "desert"},
		{"center": Vector3(-225, 0, 295), "radius": 425.0, "count": 20, "type": "river"},
		{"center": Vector3(650, 0, 1050), "radius": 400.0, "count": 18, "type": "plains"},
		{"center": Vector3(-325, 0, -1075), "radius": 375.0, "count": 18, "type": "autumn"},
		{"center": Vector3(1550, 0, 300), "radius": 425.0, "count": 16, "type": "coast"},
	]
	for region in regions:
		var center: Vector3 = region["center"]
		var count: int = int(region["count"])
		var radius: float = float(region["radius"])
		for i in count:
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(25.0, radius)
			var p := center + Vector3(cos(angle) * dist, 1.0, sin(angle) * dist * 0.82)
			p.x = clamp(p.x, -arena_half_x + 20.0, arena_half_x - 20.0)
			p.z = clamp(p.z, -arena_half_z + 20.0, arena_half_z - 20.0)
			if p.length() < SAFE_ZONE_RADIUS + 32.0:
				continue
			_spawn_zombie_at(parent, p, _regional_zombie_type(String(region["type"])), false)


func _regional_zombie_type(region: String) -> Dictionary:
	match region:
		"desert":
			return {"name": "Dune Husk", "scale": 1.1, "body_color": Color(0.62, 0.42, 0.22), "skin_color": Color(0.82, 0.62, 0.38), "eye_color": Color(1.0, 0.5, 0.1), "hp": 85.0, "speed": 2.9, "damage": 14.0}
		"river":
			return {"name": "River Spider", "rig": "spider", "scale": 1.15, "body_color": Color(0.12, 0.24, 0.28), "skin_color": Color(0.22, 0.48, 0.52), "eye_color": Color(0.2, 0.9, 1.0), "hp": 80.0, "speed": 3.3, "damage": 15.0}
		"plains":
			return {"name": "Plainstalker", "rig": "wolf", "scale": 1.2, "body_color": Color(0.28, 0.34, 0.2), "skin_color": Color(0.46, 0.52, 0.32), "eye_color": Color(0.9, 1.0, 0.25), "hp": 90.0, "speed": 3.8, "damage": 16.0}
		"autumn":
			return {"name": "Ash Runner", "scale": 1.0, "body_color": Color(0.44, 0.2, 0.12), "skin_color": Color(0.62, 0.36, 0.22), "eye_color": Color(1.0, 0.3, 0.08), "hp": 75.0, "speed": 4.0, "damage": 13.0}
		"coast":
			return {"name": "Coast Beetle", "rig": "beetle", "scale": 1.2, "body_color": Color(0.08, 0.24, 0.32), "skin_color": Color(0.24, 0.58, 0.68), "eye_color": Color(0.45, 1.0, 0.85), "hp": 105.0, "speed": 2.7, "damage": 17.0}
		_:
			return {"name": "Frost Husk", "scale": 1.1, "body_color": Color(0.32, 0.5, 0.62), "skin_color": Color(0.7, 0.86, 0.92), "eye_color": Color(0.45, 0.9, 1.0), "hp": 90.0, "speed": 2.8, "damage": 15.0}


func _spawn_regional_bosses(parent: Node3D) -> void:
	if zombie_scene == null:
		return
	var bosses := [
		{"name": "Frost Matriarch", "pos": Vector3(260, 1, -280), "rig": "tiger", "scale": 2.2, "hp": 520.0, "speed": 2.6, "damage": 31.0, "body": Color(0.6, 0.8, 0.9), "skin": Color(0.86, 0.96, 1.0), "eye": Color(0.25, 0.9, 1.0)},
		{"name": "Dune Warden", "pos": Vector3(-1470, 1, -245), "rig": "humanoid", "scale": 2.45, "hp": 610.0, "speed": 1.9, "damage": 36.0, "body": Color(0.7, 0.45, 0.2), "skin": Color(0.88, 0.62, 0.34), "eye": Color(1.0, 0.45, 0.12)},
		{"name": "River Broodmother", "pos": Vector3(-220, 1, 338), "rig": "spider", "scale": 2.4, "hp": 560.0, "speed": 2.4, "damage": 32.0, "body": Color(0.08, 0.22, 0.28), "skin": Color(0.18, 0.44, 0.52), "eye": Color(0.3, 1.0, 0.95)},
		{"name": "Plain Alpha", "pos": Vector3(735, 1, 1065), "rig": "wolf", "scale": 2.15, "hp": 500.0, "speed": 3.2, "damage": 30.0, "body": Color(0.28, 0.38, 0.2), "skin": Color(0.46, 0.6, 0.34), "eye": Color(0.9, 1.0, 0.18)},
		{"name": "Ashfang", "pos": Vector3(-365, 1, -1120), "rig": "tiger", "scale": 2.25, "hp": 540.0, "speed": 2.9, "damage": 34.0, "body": Color(0.5, 0.18, 0.09), "skin": Color(0.74, 0.35, 0.16), "eye": Color(1.0, 0.28, 0.08)},
		{"name": "Coast Shellback", "pos": Vector3(1595, 1, 310), "rig": "beetle", "scale": 2.55, "hp": 650.0, "speed": 2.0, "damage": 38.0, "body": Color(0.06, 0.18, 0.28), "skin": Color(0.18, 0.52, 0.65), "eye": Color(0.5, 1.0, 0.85)},
	]
	for b in bosses:
		var boss_type := {
			"name": String(b["name"]),
			"rig": String(b["rig"]),
			"scale": float(b["scale"]),
			"body_color": b["body"],
			"skin_color": b["skin"],
			"eye_color": b["eye"],
			"hp": float(b["hp"]),
			"speed": float(b["speed"]),
			"damage": float(b["damage"]),
		}
		_spawn_zombie_at(parent, b["pos"], boss_type, true)


func _spawn_zombie_at(parent: Node3D, pos: Vector3, type_def: Dictionary, territorial_boss: bool) -> Node3D:
	var z := zombie_scene.instantiate()
	z.position = pos
	parent.add_child(z)
	if z.has_method("apply_type"):
		z.apply_type(type_def)
	if territorial_boss:
		z.name = String(type_def.get("name", "TerritorialBoss")).replace(" ", "")
		z.add_to_group("territorial_bosses")
		z.set("detect_range", 130.0)
		_add_boss_label(z, String(type_def.get("name", "Territorial Boss")))
	else:
		z.set("detect_range", 95.0)
	return z


func _add_boss_label(boss: Node3D, label_text: String) -> void:
	var label := Label3D.new()
	label.text = label_text.to_upper()
	label.font_size = 34
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.modulate = Color(1.0, 0.56, 0.28)
	label.position = Vector3(0, 3.8, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	boss.add_child(label)


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
	_follow_player_with_snow()

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
	# Biome bias: deserts are sparse, autumn woods are haunted, ocean is dead.
	var biome_mult: float = _biome_spawn_mult()
	if biome_mult <= 0.01:
		# Ocean — skip the spawn entirely, but keep the timer ticking.
		_spawn_timer = max(0.5, base_int)
		return
	_spawn_timer = max(0.5, base_int / (weather_mult * biome_mult))

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


func _biome_spawn_mult() -> float:
	# Multiplier on spawn frequency based on the biome the player is currently
	# standing in. Higher = more spawns. 0 = no spawns this tick.
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return 1.0
	var b: String = get_biome_at((player as Node3D).global_position)
	match b:
		"desert":
			return 0.7
		"autumn":
			return 1.4
		"plains":
			return 0.95
		"river":
			return 1.15
		"ocean":
			return 0.0
		_:
			return 1.0


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
