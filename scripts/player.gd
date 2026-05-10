extends CharacterBody3D

# Third-person player controller. Yaw on the body, pitch on a child pivot.
# Stamina drains while sprinting and regenerates otherwise. Melee + ranged
# attacks live on the equipped Weapon (1/2/3/4 to swap). Three elemental
# skills (Q fire / E frost / F shock) trigger AoE / projectile / chain
# effects with shared cooldowns.

signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 6.0
@export var mouse_sensitivity: float = 0.0025
@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var stamina_drain: float = 25.0
@export var stamina_regen: float = 18.0

# Survival meter — drains outside the sanctuary, drains faster in storms.
# Below `warmth_critical` the player loses HP each second.
@export var max_warmth: float = 100.0
@export var warmth_drain_base: float = 1.4
@export var warmth_critical: float = 22.0
@export var warmth_dps: float = 1.0

# Skill tuning ------------------------------------------------------------
@export var skill_fire_cooldown: float = 6.0
@export var skill_frost_cooldown: float = 8.0
@export var skill_lightning_cooldown: float = 10.0

# Trait-driven multipliers — recomputed on trait_changed.
var damage_mult: float = 1.0
var ranged_dmg_mult: float = 1.0
var heal_mult: float = 1.0
var warmth_drain_mult: float = 1.0
var stamina_drain_mult: float = 1.0
var stamina_regen_mult: float = 1.0
var skill_cd_mults: Array[float] = [1.0, 1.0, 1.0]
var lightning_chain_targets: int = 3

# Elemental skill slots — order matches HUD layout (Q / E / F).
const SKILL_FIRE: int = 0
const SKILL_FROST: int = 1
const SKILL_LIGHTNING: int = 2

const SKILL_DEFS: Array = [
	{"name": "Fireball",       "key": "Q", "color": Color(1.0, 0.55, 0.15)},
	{"name": "Frost Nova",     "key": "E", "color": Color(0.45, 0.85, 1.0)},
	{"name": "Chain Lightning","key": "F", "color": Color(0.85, 0.75, 1.0)},
]

var skill_timers: Array[float] = [0.0, 0.0, 0.0]

signal warmth_changed(current: float, maximum: float)

var health: float
var stamina: float
var warmth: float
var attack_timer: float = 0.0
var is_dead: bool = false

# Vehicle state
var in_vehicle: bool = false
var current_vehicle: Node = null

const FOOTPRINT_STEP_DISTANCE: float = 1.05
const FOOTPRINT_LIFETIME: float = 70.0
var _last_footprint_pos: Vector3 = Vector3.ZERO
var _footprint_left: bool = false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var weapon: Node3D = $Weapon
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("player")
	# Connect to the autoload trait signal — this fires after world._ready
	# calls reset_game(), so we'll get the run's actual trait shortly.
	GameManager.trait_changed.connect(_on_trait_changed)
	if GameManager.active_trait.size() > 0:
		_on_trait_changed(GameManager.active_trait)
	health = max_health
	stamina = max_stamina
	warmth = max_warmth
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_first_person()
	_last_footprint_pos = global_position
	# Defer the first signal emission so HUD has a chance to connect.
	call_deferred("_emit_initial_state")


func _setup_first_person() -> void:
	var spring_arm := camera_pivot.get_node_or_null("SpringArm3D") as SpringArm3D
	if spring_arm:
		spring_arm.spring_length = 0.0
		spring_arm.margin = 0.0
	camera.position = Vector3.ZERO
	camera.fov = 82.0
	camera.near = 0.035
	for c in get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
	if weapon:
		if weapon.has_method("set_rest_pose"):
			weapon.set_rest_pose(Vector3(0.42, 1.45, -0.78), Vector3(-0.08, -0.03, 0.0))


func _emit_initial_state() -> void:
	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)
	warmth_changed.emit(warmth, max_warmth)


func _on_trait_changed(trait_def: Dictionary) -> void:
	# Reset multipliers, then apply this trait's overrides.
	damage_mult = float(trait_def.get("damage_mult", 1.0))
	ranged_dmg_mult = float(trait_def.get("ranged_dmg_mult", 1.0))
	heal_mult = float(trait_def.get("heal_mult", 1.0))
	warmth_drain_mult = float(trait_def.get("warmth_drain", 1.0))
	stamina_drain_mult = float(trait_def.get("stamina_drain", 1.0))
	stamina_regen_mult = float(trait_def.get("stamina_regen", 1.0))
	skill_cd_mults = [
		float(trait_def.get("skill_fire_cd", 1.0)),
		float(trait_def.get("skill_frost_cd", 1.0)),
		float(trait_def.get("skill_shock_cd", 1.0)),
	]
	lightning_chain_targets = 3 + int(trait_def.get("shock_chain_bonus", 0))
	# Stat additions (e.g. Tough +30 max HP). Always recompute max_health
	# from the base so re-traiting downward (-15) clears a previous +30.
	var hp_add: float = float(trait_def.get("max_health_add", 0.0))
	var was_full: bool = health >= max_health - 0.001
	max_health = max(20.0, 100.0 + hp_add)
	if was_full:
		health = max_health
	else:
		health = min(health, max_health)
	health_changed.emit(health, max_health)


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

	# Interact (talk to NPC, pick up, enter/exit vehicle).
	if event.is_action_pressed("interact"):
		_try_interact()
		return

	# While driving, block all on-foot inputs except interact (handled above).
	if in_vehicle:
		return

	if event.is_action_pressed("build_shelter"):
		_try_build_shelter()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.1, 0.55)

	if event.is_action_pressed("attack") and attack_timer <= 0.0:
		_do_attack()

	# Weapon swap (1..4)
	if weapon and weapon.has_method("set_weapon"):
		for i in 4:
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				weapon.set_weapon(i)
				break

	# Elemental skills
	if event.is_action_pressed("skill_fire") and skill_timers[SKILL_FIRE] <= 0.0:
		_cast_fireball()
		skill_timers[SKILL_FIRE] = skill_fire_cooldown * skill_cd_mults[SKILL_FIRE]
	if event.is_action_pressed("skill_frost") and skill_timers[SKILL_FROST] <= 0.0:
		_cast_frost_nova()
		skill_timers[SKILL_FROST] = skill_frost_cooldown * skill_cd_mults[SKILL_FROST]
	if event.is_action_pressed("skill_lightning") and skill_timers[SKILL_LIGHTNING] <= 0.0:
		_cast_chain_lightning()
		skill_timers[SKILL_LIGHTNING] = skill_lightning_cooldown * skill_cd_mults[SKILL_LIGHTNING]


func _physics_process(delta: float) -> void:
	# Cooldowns tick regardless of life state so they reset on respawn.
	for i in skill_timers.size():
		if skill_timers[i] > 0.0:
			skill_timers[i] = max(0.0, skill_timers[i] - delta)

	# When riding, the vehicle is the controlled body — keep our position
	# pinned to it so group lookups (zombies, safe zone) still resolve sanely.
	if in_vehicle:
		if current_vehicle and is_instance_valid(current_vehicle):
			global_position = (current_vehicle as Node3D).global_position
		return

	# Sanctuary regen + warmth drain.
	_tick_survival(delta)

	if is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 20.0) * delta
		move_and_slide()
		return

	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") and stamina > 10.0:
		velocity.y = jump_velocity
		stamina = max(0.0, stamina - 10.0)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	if direction.length() > 0.0:
		direction = direction.normalized()

	var moving := input_dir != Vector2.ZERO
	var sprinting := Input.is_action_pressed("sprint") and stamina > 0.0 and moving
	var current_speed := sprint_speed if sprinting else walk_speed

	if sprinting:
		stamina = max(0.0, stamina - stamina_drain * stamina_drain_mult * delta)
	else:
		stamina = min(max_stamina, stamina + stamina_regen * stamina_regen_mult * delta)
	stamina_changed.emit(stamina, max_stamina)

	if moving:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, current_speed * 4.0 * delta)

	if attack_timer > 0.0:
		attack_timer -= delta

	move_and_slide()
	_maybe_leave_footprint(moving)


# -- Combat ---------------------------------------------------------------

func _aim_forward() -> Vector3:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() == 0.0:
		return Vector3.ZERO
	return fwd.normalized()


func _do_attack() -> void:
	var fwd := _aim_forward()
	if fwd == Vector3.ZERO:
		return
	if weapon and weapon.has_method("attack"):
		var stats: Dictionary = weapon.get_stats() if weapon.has_method("get_stats") else {}
		var ranged: bool = bool(stats.get("ranged", false))
		var mult: float = damage_mult * (ranged_dmg_mult if ranged else 1.0)
		weapon.attack(global_position, fwd, mult)
		attack_timer = float(weapon.get_cooldown()) if weapon.has_method("get_cooldown") else 0.45
	else:
		attack_timer = 0.45


# -- Elemental skills -----------------------------------------------------

func _cast_fireball() -> void:
	var fwd := _aim_forward()
	if fwd == Vector3.ZERO:
		return
	GameManager.record_damage_use("fire")
	var origin: Vector3 = global_position + fwd * 0.8 + Vector3(0.0, 1.4, 0.0)
	var fb := Node3D.new()
	fb.set_script(load("res://scripts/fireball.gd"))
	fb.direction = fwd
	fb.damage = float(fb.damage) * damage_mult
	fb.burn_dps = float(fb.burn_dps) * damage_mult
	get_tree().current_scene.add_child(fb)
	fb.global_position = origin


func _cast_frost_nova() -> void:
	GameManager.record_damage_use("frost")
	var radius: float = 7.5
	var dmg: float = 30.0 * damage_mult
	var slow_factor: float = 0.4
	var slow_duration: float = 4.5

	# Visual: expanding cyan ring on the ground.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.35
	tm.outer_radius = 0.6
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.9, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.85, 1.0)
	mat.emission_energy_multiplier = 2.2
	ring.material_override = mat
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector3(0.0, 0.15, 0.0)
	var t := ring.create_tween()
	t.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(mat, "albedo_color", Color(0.55, 0.9, 1.0, 0.0), 0.5)
	t.tween_callback(ring.queue_free)

	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or z.get("is_dead") == true:
			continue
		var d := global_position.distance_to(z.global_position)
		if d <= radius:
			if z.has_method("take_damage"):
				z.take_damage(dmg, "frost")
			if z.has_method("apply_freeze"):
				z.apply_freeze(slow_factor, slow_duration)


func _cast_chain_lightning() -> void:
	GameManager.record_damage_use("shock")
	var first_range: float = 18.0
	var chain_range: float = 9.0
	# Stormcaller trait can extend the chain.
	var base_damages: Array[float] = [60.0, 40.0, 25.0, 18.0, 14.0]
	var max_targets: int = clamp(lightning_chain_targets, 1, base_damages.size())
	var damages: Array[float] = []
	for i in max_targets:
		damages.append(base_damages[i] * damage_mult)
	var stun_duration: float = 0.7

	var fwd := _aim_forward()
	if fwd == Vector3.ZERO:
		return

	# Pick the best forward target — score = forward dot product minus a
	# small distance penalty so we don't snap onto something far away.
	var first: Node = null
	var best_score: float = -INF
	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or z.get("is_dead") == true:
			continue
		var to_z: Vector3 = z.global_position - global_position
		to_z.y = 0.0
		var d := to_z.length()
		if d > first_range or d < 0.001:
			continue
		var dot := fwd.dot(to_z.normalized())
		if dot < 0.4:
			continue
		var score := dot - d * 0.02
		if score > best_score:
			best_score = score
			first = z
	if first == null:
		return

	var origin: Vector3 = global_position + Vector3(0.0, 1.5, 0.0)
	var prev_pos: Vector3 = origin
	var hit_set: Dictionary = {}
	var current: Node = first

	for i in damages.size():
		if current == null or not is_instance_valid(current) or current.get("is_dead") == true:
			break
		hit_set[current.get_instance_id()] = true
		var here: Vector3 = (current as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
		_spawn_lightning_bolt(prev_pos, here)
		if current.has_method("take_damage"):
			current.take_damage(damages[i], "shock")
		if current.has_method("apply_shock"):
			current.apply_shock(stun_duration)
		prev_pos = here

		# Find next target — nearest unvisited zombie within chain_range.
		var next: Node = null
		var nearest: float = chain_range
		for z in get_tree().get_nodes_in_group("zombies"):
			if not is_instance_valid(z) or z.get("is_dead") == true:
				continue
			if hit_set.has(z.get_instance_id()):
				continue
			var d2: float = (current as Node3D).global_position.distance_to(z.global_position)
			if d2 < nearest:
				nearest = d2
				next = z
		current = next


func _spawn_lightning_bolt(from: Vector3, to: Vector3) -> void:
	var diff: Vector3 = to - from
	var length: float = diff.length()
	if length < 0.05:
		return
	var bolt := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = length
	bolt.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.78, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.78, 1.0)
	mat.emission_energy_multiplier = 4.0
	bolt.material_override = mat

	get_tree().current_scene.add_child(bolt)
	bolt.global_position = (from + to) * 0.5

	# Cylinder default axis is +Y. Build a basis whose Y aligns with `dir`.
	var dir: Vector3 = diff.normalized()
	var bolt_basis: Basis = Basis()
	if dir.dot(Vector3.UP) > 0.999:
		bolt_basis = Basis()
	elif dir.dot(Vector3.UP) < -0.999:
		bolt_basis = Basis(Vector3.RIGHT, PI)
	else:
		var axis: Vector3 = Vector3.UP.cross(dir).normalized()
		var angle: float = acos(clamp(Vector3.UP.dot(dir), -1.0, 1.0))
		bolt_basis = Basis(axis, angle)
	bolt.global_transform = Transform3D(bolt_basis, bolt.global_position)

	var t := bolt.create_tween()
	t.tween_property(bolt, "scale", Vector3(0.15, 1.0, 0.15), 0.18)
	t.parallel().tween_property(mat, "albedo_color", Color(0.85, 0.78, 1.0, 0.0), 0.22)
	t.tween_callback(bolt.queue_free)


# -- Damage ---------------------------------------------------------------

func take_damage(amount: float) -> void:
	if is_dead:
		return
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()


func _die() -> void:
	is_dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameManager.notify_player_died()
	# Topple the body forward.
	var tween := create_tween()
	tween.tween_property(self, "rotation:x", -PI / 2.0, 0.6)


# -- Interact + vehicle ---------------------------------------------------

const INTERACT_RANGE: float = 3.5


func _try_interact() -> void:
	# Inside the truck — G exits.
	if in_vehicle:
		if current_vehicle and current_vehicle.has_method("exit_vehicle"):
			current_vehicle.exit_vehicle()
		return

	var best: Node = null
	var best_d: float = INF
	for n in get_tree().get_nodes_in_group("npcs"):
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d < INTERACT_RANGE and d < best_d:
			best_d = d
			best = n
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.get("driver") != null:
			continue
		var d: float = global_position.distance_to((v as Node3D).global_position)
		# Vehicles get a slightly larger interact radius — the truck is big.
		if d < INTERACT_RANGE + 1.5 and d < best_d:
			best_d = d
			best = v
	for r in get_tree().get_nodes_in_group("resource_nodes"):
		if not (r is Node3D):
			continue
		var d: float = global_position.distance_to((r as Node3D).global_position)
		if d < INTERACT_RANGE and d < best_d:
			best_d = d
			best = r
	if best == null:
		return
	if best.has_method("enter"):
		best.enter(self)
	elif best.has_method("interact"):
		best.interact(self)


func _try_build_shelter() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("build_player_shelter"):
		return
	var fwd := _aim_forward()
	if fwd == Vector3.ZERO:
		fwd = -global_transform.basis.z
	scene.build_player_shelter(global_position + fwd.normalized() * 4.0, rotation.y)


# Called by vehicle.gd when the player enters/exits.
func set_in_vehicle(vehicle: Node) -> void:
	if vehicle != null:
		in_vehicle = true
		current_vehicle = vehicle
		visible = false
		velocity = Vector3.ZERO
		if collision_shape:
			collision_shape.set_deferred("disabled", true)
	else:
		in_vehicle = false
		current_vehicle = null
		visible = true
		if collision_shape:
			collision_shape.set_deferred("disabled", false)
		if camera and is_instance_valid(camera):
			camera.make_current()


func _tick_survival(delta: float) -> void:
	if is_dead:
		return
	var in_sanctuary: bool = false
	for sz in get_tree().get_nodes_in_group("safe_zone"):
		if not (sz is Node3D):
			continue
		var center: Vector3 = (sz as Node3D).global_position
		var radius: float = float(sz.get_meta("radius", 16.0))
		if global_position.distance_to(center) <= radius:
			in_sanctuary = true
			break

	# Warmth: drain outside, recover inside. Weather can multiply the drain.
	if in_sanctuary:
		if warmth < max_warmth:
			warmth = min(max_warmth, warmth + 12.0 * delta)
	else:
		var weather_mult: float = float(GameManager.current_weather_def().get("warmth_drain_mult", 1.0))
		var drain: float = warmth_drain_base * warmth_drain_mult * weather_mult
		warmth = max(0.0, warmth - drain * delta)
	warmth_changed.emit(warmth, max_warmth)

	# Frostbite: low warmth chips at health.
	if warmth < warmth_critical and warmth_critical > 0.0:
		var bite: float = warmth_dps * (1.0 - warmth / warmth_critical)
		health = max(0.0, health - bite * delta)
		health_changed.emit(health, max_health)
		if health <= 0.0:
			_die()
			return

	# Sanctuary heal — scaled by trait heal_mult.
	if in_sanctuary:
		if health < max_health:
			health = min(max_health, health + 10.0 * heal_mult * delta)
			health_changed.emit(health, max_health)
		if stamina < max_stamina:
			stamina = min(max_stamina, stamina + 18.0 * heal_mult * delta)
			stamina_changed.emit(stamina, max_stamina)


func _maybe_leave_footprint(moving: bool) -> void:
	if not moving or not is_on_floor() or in_vehicle:
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("get_biome_at"):
		var biome_name: String = String(scene.get_biome_at(global_position))
		if biome_name != "snow":
			return
	if global_position.distance_to(_last_footprint_pos) < FOOTPRINT_STEP_DISTANCE:
		return
	_last_footprint_pos = global_position

	var print_mesh := MeshInstance3D.new()
	print_mesh.name = "Footprint"
	print_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.018, 0.56)
	print_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.55, 0.62, 0.72)
	mat.roughness = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	print_mesh.material_override = mat
	var side := -0.18 if _footprint_left else 0.18
	var local_offset: Vector3 = global_transform.basis.x * side - global_transform.basis.z * 0.08
	_footprint_left = not _footprint_left
	if scene:
		scene.add_child(print_mesh)
	else:
		get_parent().add_child(print_mesh)
	print_mesh.global_position = Vector3(global_position.x + local_offset.x, global_position.y + 0.025, global_position.z + local_offset.z)
	print_mesh.rotation.y = rotation.y
	var t := create_tween()
	t.tween_interval(FOOTPRINT_LIFETIME)
	t.tween_callback(print_mesh.queue_free)
