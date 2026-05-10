extends CharacterBody3D

# Zombie controller. apply_type() takes a Dictionary describing one of the
# eight zombie types and rebuilds size, colors, and stats. The visuals live
# under a "Visuals" Node3D so we can scale them without touching the
# CharacterBody3D itself (Godot warns against scaling physics bodies).
#
# Status effects (burn / freeze / shock) are driven by the player's elemental
# skills. apply_burn / apply_freeze / apply_shock are called externally; the
# physics tick decays timers and gates movement and DoT.

@export var max_health: float = 60.0
@export var move_speed: float = 2.6
@export var attack_damage: float = 12.0
@export var attack_range: float = 1.7
@export var attack_cooldown: float = 1.2
@export var detect_range: float = 60.0
@export var hit_flash_color: Color = Color(1.0, 0.45, 0.45)

var type_name: String = "Walker"
var visual_scale: float = 1.0
var health: float
var attack_timer: float = 0.0
var is_dead: bool = false
var _flashing: bool = false
var _hit_tween: Tween = null
var _target: Node3D = null
var _body_color_cache: Color = Color(0.32, 0.42, 0.36)

# Adaptive AI: a damage type the zombie was rolled with resistance to. The
# spawner sets this to the player's most-used damage type (lazily — recent
# zombies adapt to recent player tactics). Empty string = no resistance.
var resistance_type: String = ""
const RESISTANCE_FACTOR: float = 0.6  # 40% damage reduction

# Status effect state
var burn_timer: float = 0.0
var burn_dps: float = 0.0
var freeze_timer: float = 0.0
var freeze_factor: float = 1.0   # 1.0 = normal speed, <1 = slowed
var shock_timer: float = 0.0     # >0 = stunned, can't move or attack
var _status_indicator: MeshInstance3D = null

@onready var visuals: Node3D = $Visuals
@onready var body_mesh: MeshInstance3D = $Visuals/Body
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("zombies")
	health = max_health


func apply_type(t: Dictionary) -> void:
	# Re-resolve nodes in case this is called pre-_ready (it isn't normally,
	# but the lookup is cheap and keeps the API safe).
	if visuals == null:
		visuals = $Visuals
	if body_mesh == null:
		body_mesh = $Visuals/Body
	if collision_shape == null:
		collision_shape = $CollisionShape3D

	type_name = t.get("name", "Walker")
	var scl: float = float(t.get("scale", 1.0))
	visual_scale = scl

	# Resize collision capsule.
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4 * scl
	shape.height = max(0.9, 1.8 * scl)
	collision_shape.shape = shape
	collision_shape.position = Vector3(0, shape.height * 0.5, 0)

	# Scale every visual together — uniform scale on the Visuals parent only.
	visuals.scale = Vector3.ONE * scl
	# Lift attack range with size so big zombies can actually reach the player.
	attack_range = 1.4 + 0.55 * scl

	# Rebuild materials per-instance so colour changes don't bleed across copies.
	var body_color: Color = t.get("body_color", Color(0.32, 0.42, 0.36))
	var skin_color: Color = t.get("skin_color", Color(0.62, 0.74, 0.7))
	var eye_color: Color = t.get("eye_color", Color(0.95, 0.25, 0.2))
	var rig: String = String(t.get("rig", "humanoid"))
	_body_color_cache = body_color

	if rig == "humanoid":
		_apply_humanoid_visuals(body_color, skin_color, eye_color)
	else:
		_build_animal_visuals(rig, body_color, skin_color, eye_color)

	# Stats with a small per-spawn jitter so two of the same type aren't identical.
	max_health = float(t.get("hp", 60.0)) * randf_range(0.92, 1.08)
	health = max_health
	move_speed = float(t.get("speed", 2.6)) * randf_range(0.92, 1.08)
	attack_damage = float(t.get("damage", 12.0))


func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.88
	return m


func _make_emissive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.04, 0.04, 0.04, 1.0)
	m.roughness = 0.7
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.1
	return m


func _apply_humanoid_visuals(body_color: Color, skin_color: Color, eye_color: Color) -> void:
	body_mesh.material_override = _make_mat(body_color)
	var head: MeshInstance3D = visuals.get_node_or_null("Head")
	if head:
		head.material_override = _make_mat(skin_color)
	for arm in ["ArmL", "ArmR", "LegL", "LegR"]:
		var n: MeshInstance3D = visuals.get_node_or_null(arm)
		if n:
			n.material_override = _make_mat(skin_color.darkened(0.12))
	var band: MeshInstance3D = visuals.get_node_or_null("ChestBand")
	if band:
		band.material_override = _make_mat(body_color.lightened(0.22))
	for eye in ["EyeL", "EyeR"]:
		var n: MeshInstance3D = visuals.get_node_or_null(eye)
		if n:
			n.material_override = _make_emissive(eye_color)


func _build_animal_visuals(rig: String, body_color: Color, skin_color: Color, eye_color: Color) -> void:
	_clear_visuals()
	match rig:
		"wolf":
			_build_quadruped_visuals(false, body_color, skin_color, eye_color)
		"tiger":
			_build_quadruped_visuals(true, body_color, skin_color, eye_color)
		"spider":
			_build_spider_visuals(body_color, skin_color, eye_color)
		"beetle":
			_build_beetle_visuals(body_color, skin_color, eye_color)
		_:
			_build_quadruped_visuals(false, body_color, skin_color, eye_color)


func _clear_visuals() -> void:
	for child in visuals.get_children():
		visuals.remove_child(child)
		child.free()


func _part_box(node_name: String, size: Vector3, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.rotation = rot
	mesh.material_override = _make_mat(color)
	visuals.add_child(mesh)
	return mesh


func _glow_box(node_name: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := _part_box(node_name, size, pos, Color(0.04, 0.04, 0.04))
	mesh.material_override = _make_emissive(color)
	return mesh


func _build_quadruped_visuals(is_tiger: bool, body_color: Color, skin_color: Color, eye_color: Color) -> void:
	body_mesh = _part_box("Body", Vector3(0.8, 0.55, 1.65), Vector3(0, 0.72, 0), body_color)
	_part_box("Chest", Vector3(0.9, 0.65, 0.62), Vector3(0, 0.82, -0.55), body_color.lightened(0.08))
	_part_box("Head", Vector3(0.55, 0.45, 0.62), Vector3(0, 0.98, -1.18), skin_color)
	_part_box("Snout", Vector3(0.36, 0.24, 0.38), Vector3(0, 0.9, -1.55), skin_color.darkened(0.18))
	_part_box("EarL", Vector3(0.18, 0.32, 0.12), Vector3(-0.25, 1.26, -1.18), body_color.darkened(0.12), Vector3(0.0, 0.0, -0.35))
	_part_box("EarR", Vector3(0.18, 0.32, 0.12), Vector3(0.25, 1.26, -1.18), body_color.darkened(0.12), Vector3(0.0, 0.0, 0.35))
	_part_box("Tail", Vector3(0.18, 0.18, 0.88), Vector3(0, 0.88, 1.05), body_color.darkened(0.05), Vector3(0.45, 0.0, 0.0))
	for x in [-0.32, 0.32]:
		for z in [-0.55, 0.55]:
			_part_box("Leg", Vector3(0.22, 0.7, 0.22), Vector3(x, 0.28, z), skin_color.darkened(0.25))
	_glow_box("EyeL", Vector3(0.08, 0.08, 0.05), Vector3(-0.13, 1.04, -1.5), eye_color)
	_glow_box("EyeR", Vector3(0.08, 0.08, 0.05), Vector3(0.13, 1.04, -1.5), eye_color)
	if is_tiger:
		for z in [-0.45, -0.05, 0.35]:
			_part_box("Stripe", Vector3(0.86, 0.08, 0.08), Vector3(0, 1.03, z), Color(0.08, 0.06, 0.05))
		_part_box("StripeL", Vector3(0.08, 0.45, 0.08), Vector3(-0.44, 0.82, -0.28), Color(0.08, 0.06, 0.05), Vector3(0, 0, 0.25))
		_part_box("StripeR", Vector3(0.08, 0.45, 0.08), Vector3(0.44, 0.82, -0.28), Color(0.08, 0.06, 0.05), Vector3(0, 0, -0.25))


func _build_spider_visuals(body_color: Color, skin_color: Color, eye_color: Color) -> void:
	body_mesh = _part_box("Body", Vector3(1.0, 0.42, 1.1), Vector3(0, 0.55, 0.05), body_color)
	_part_box("Abdomen", Vector3(1.15, 0.52, 0.9), Vector3(0, 0.56, 0.75), skin_color.darkened(0.15))
	_part_box("Head", Vector3(0.72, 0.34, 0.45), Vector3(0, 0.6, -0.72), skin_color)
	for x in [-0.48, 0.48]:
		for z in [-0.55, -0.15, 0.25, 0.65]:
			var side := signf(x)
			_part_box("Leg", Vector3(0.9, 0.11, 0.11), Vector3(x + side * 0.38, 0.46, z), body_color.darkened(0.08), Vector3(0.0, z * 0.35, side * 0.35))
	_glow_box("EyeL", Vector3(0.08, 0.08, 0.05), Vector3(-0.14, 0.68, -0.96), eye_color)
	_glow_box("EyeR", Vector3(0.08, 0.08, 0.05), Vector3(0.14, 0.68, -0.96), eye_color)


func _build_beetle_visuals(body_color: Color, skin_color: Color, eye_color: Color) -> void:
	body_mesh = _part_box("Shell", Vector3(1.05, 0.55, 1.35), Vector3(0, 0.62, 0.25), body_color)
	_part_box("ShellSplit", Vector3(0.06, 0.58, 1.38), Vector3(0, 0.64, 0.25), skin_color.lightened(0.15))
	_part_box("Head", Vector3(0.65, 0.38, 0.48), Vector3(0, 0.62, -0.75), skin_color)
	_part_box("Horn", Vector3(0.18, 0.18, 0.58), Vector3(0, 0.75, -1.15), skin_color.lightened(0.2), Vector3(-0.25, 0.0, 0.0))
	for x in [-0.52, 0.52]:
		for z in [-0.35, 0.1, 0.55]:
			_part_box("Leg", Vector3(0.62, 0.14, 0.14), Vector3(x, 0.38, z), body_color.darkened(0.25), Vector3(0, z * 0.35, signf(x) * 0.2))
	_glow_box("EyeL", Vector3(0.08, 0.08, 0.05), Vector3(-0.16, 0.68, -0.99), eye_color)
	_glow_box("EyeR", Vector3(0.08, 0.08, 0.05), Vector3(0.16, 0.68, -0.99), eye_color)


func _physics_process(delta: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)

	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	# Status effects
	if burn_timer > 0.0:
		burn_timer = max(0.0, burn_timer - delta)
		health = max(0.0, health - burn_dps * delta)
		if health <= 0.0:
			_die()
			return
	if freeze_timer > 0.0:
		freeze_timer = max(0.0, freeze_timer - delta)
		if freeze_timer <= 0.0:
			freeze_factor = 1.0
	if shock_timer > 0.0:
		shock_timer = max(0.0, shock_timer - delta)
	_update_status_indicator()

	if not is_on_floor():
		velocity.y -= gravity * delta

	if not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player")
		if _target == null:
			move_and_slide()
			return

	if _target.get("is_dead") == true:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist > detect_range or dist < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var dir := to_target.normalized()
	var look_pos := global_position + dir
	look_at(Vector3(look_pos.x, global_position.y, look_pos.z), Vector3.UP)

	# Stunned: drift to a halt, no attacks.
	if shock_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		if attack_timer > 0.0:
			attack_timer -= delta
		move_and_slide()
		return

	var effective_speed := move_speed * freeze_factor
	if dist > attack_range * 0.85:
		velocity.x = dir.x * effective_speed
		velocity.z = dir.z * effective_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if attack_timer <= 0.0:
			_do_attack()

	if attack_timer > 0.0:
		attack_timer -= delta

	move_and_slide()


func _do_attack() -> void:
	attack_timer = attack_cooldown
	if not is_instance_valid(_target):
		return
	var d := global_position.distance_to(_target.global_position)
	if d <= attack_range and _target.has_method("take_damage"):
		_target.take_damage(attack_damage)
	if visuals:
		var tween := create_tween()
		tween.tween_property(visuals, "position:z", -0.25 * visual_scale, 0.08)
		tween.tween_property(visuals, "position:z", 0.0, 0.18)


func take_damage(amount: float, dmg_type: String = "physical") -> void:
	if is_dead:
		return
	# Adaptive resistance: 40% reduction when matching this zombie's roll.
	if resistance_type != "" and dmg_type == resistance_type:
		amount *= RESISTANCE_FACTOR
	health -= amount
	_flash_hit()
	_play_hit_reaction()
	if health <= 0.0:
		_die()
		return
	var p := get_tree().get_first_node_in_group("player")
	if p:
		var knock: Vector3 = (global_position - p.global_position)
		knock.y = 0.0
		if knock.length() > 0.0:
			velocity += knock.normalized() * (3.5 / max(0.6, visual_scale))


func set_resistance(dmg_type: String) -> void:
	resistance_type = dmg_type
	if dmg_type == "" or body_mesh == null:
		return
	# Subtle color tint so the player can read which zombies are resistant.
	var tint: Color = Color(1, 1, 1)
	match dmg_type:
		"fire":   tint = Color(1.0, 0.55, 0.4)
		"frost":  tint = Color(0.55, 0.85, 1.0)
		"shock":  tint = Color(0.85, 0.78, 1.0)
		"melee":  tint = Color(0.85, 0.75, 0.65)
		"ranged": tint = Color(0.7, 0.7, 0.7)
	var blended: Color = _body_color_cache.lerp(tint, 0.35)
	_body_color_cache = blended
	var mat: StandardMaterial3D = body_mesh.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = blended


# -- Status effects -------------------------------------------------------

func apply_burn(dps: float, duration: float) -> void:
	if is_dead:
		return
	burn_dps = max(burn_dps, dps)
	burn_timer = max(burn_timer, duration)


func apply_freeze(slow_mult: float, duration: float) -> void:
	if is_dead:
		return
	freeze_factor = min(freeze_factor, clamp(slow_mult, 0.05, 1.0))
	freeze_timer = max(freeze_timer, duration)


func apply_shock(duration: float) -> void:
	if is_dead:
		return
	shock_timer = max(shock_timer, duration)


func _update_status_indicator() -> void:
	var any_active: bool = burn_timer > 0.0 or freeze_timer > 0.0 or shock_timer > 0.0
	if not any_active:
		if _status_indicator and is_instance_valid(_status_indicator):
			_status_indicator.queue_free()
			_status_indicator = null
		return
	if _status_indicator == null or not is_instance_valid(_status_indicator):
		_status_indicator = MeshInstance3D.new()
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = 0.18
		sphere_mesh.height = 0.36
		_status_indicator.mesh = sphere_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 1, 1, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(1, 1, 1)
		mat.emission_energy_multiplier = 2.0
		_status_indicator.material_override = mat
		add_child(_status_indicator)
		_status_indicator.position = Vector3(0.0, 2.4 * visual_scale, 0.0)
	# Burn > shock > freeze priority for color.
	var c: Color = Color(1, 1, 1)
	if burn_timer > 0.0:
		c = Color(1.0, 0.5, 0.15)
	elif shock_timer > 0.0:
		c = Color(0.85, 0.78, 1.0)
	elif freeze_timer > 0.0:
		c = Color(0.45, 0.85, 1.0)
	var status_material: StandardMaterial3D = _status_indicator.material_override as StandardMaterial3D
	if status_material:
		status_material.emission = c
		status_material.albedo_color = Color(c.r, c.g, c.b, 0.85)


func _flash_hit() -> void:
	if _flashing or body_mesh == null:
		return
	var mat := body_mesh.material_override
	if not (mat is StandardMaterial3D):
		return
	_flashing = true
	var sm: StandardMaterial3D = mat
	sm.albedo_color = hit_flash_color
	await get_tree().create_timer(0.09).timeout
	if is_instance_valid(body_mesh):
		var current := body_mesh.material_override
		if current is StandardMaterial3D:
			(current as StandardMaterial3D).albedo_color = _body_color_cache
	_flashing = false


func _play_hit_reaction() -> void:
	if visuals == null or not is_instance_valid(visuals):
		return
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	visuals.position = Vector3.ZERO
	visuals.scale = Vector3.ONE * visual_scale
	_hit_tween = create_tween()
	_hit_tween.set_trans(Tween.TRANS_SINE)
	_hit_tween.set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(visuals, "position", Vector3(0.0, 0.06 * visual_scale, 0.18 * visual_scale), 0.06)
	_hit_tween.parallel().tween_property(visuals, "scale", Vector3.ONE * visual_scale * 1.04, 0.06)
	_hit_tween.tween_property(visuals, "position", Vector3.ZERO, 0.13)
	_hit_tween.parallel().tween_property(visuals, "scale", Vector3.ONE * visual_scale, 0.13)


func _die() -> void:
	is_dead = true
	GameManager.register_kill(type_name)
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if _status_indicator and is_instance_valid(_status_indicator):
		_status_indicator.queue_free()
		_status_indicator = null
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation:x", -PI / 2.0, 0.45)
	tween.tween_property(self, "position:y", position.y - 0.4, 0.6).set_delay(0.2)
	tween.chain().tween_interval(1.6)
	tween.chain().tween_callback(queue_free)
