extends CharacterBody3D

# Frost Titan boss. Built procedurally — large humanoid with two glowing
# shoulder pustules and a glowing chest core that work as visual weak
# points. Mechanically:
#  * Phase 1 (HP > 50%): slow advance, hits hard.
#  * Phase 2 (HP <= 50%): enrages — speed +60%, attack damage +25%, glow
#    shifts to red, AoE shockwave damage on attack.
# Damage is biased toward ranged + skills (the design's "use weak points"
# beat) — melee deals 0.5×, pistol/skills deal 1.0×.

@export var max_health: float = 800.0
@export var move_speed: float = 1.4
@export var enraged_speed_mult: float = 1.6
@export var attack_damage: float = 32.0
@export var attack_range: float = 3.6
@export var attack_cooldown: float = 1.6
@export var detect_range: float = 100.0
@export var visual_scale: float = 3.4

var type_name: String = "Frost Titan"
var health: float
var attack_timer: float = 0.0
var is_dead: bool = false
var enraged: bool = false
var _target: Node3D = null
var visuals: Node3D = null
var collision_shape: CollisionShape3D = null


func _ready() -> void:
	add_to_group("zombies")  # so player skills/weapons hit us through existing code
	add_to_group("boss")
	# Match zombie collision layers so monster-only doorway barriers also
	# block the boss.
	collision_layer = 1 | 2
	collision_mask = 1 | 2
	_build()
	health = max_health
	GameManager.notify_boss_spawned(self, max_health)


func _build() -> void:
	# Capsule collision sized for the visual scale.
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var sh := CapsuleShape3D.new()
	sh.radius = 1.2
	sh.height = 5.6
	col.shape = sh
	col.position = Vector3(0, 2.8, 0)
	add_child(col)
	collision_shape = col

	# Visuals parent — scaled up uniformly.
	var vroot := Node3D.new()
	vroot.name = "Visuals"
	add_child(vroot)
	visuals = vroot

	# Body — frost-blue chunky humanoid.
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 1.0
	bm.height = 4.4
	bm.radial_segments = 8
	bm.rings = 2
	body.mesh = bm
	body.position = Vector3(0, 2.5, 0)
	body.material_override = _mat(Color(0.45, 0.62, 0.78), 0.85)
	vroot.add_child(body)

	# Head
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(1.4, 1.4, 1.4)
	head.mesh = hm
	head.position = Vector3(0, 5.4, 0)
	head.material_override = _mat(Color(0.7, 0.85, 0.95), 0.9)
	vroot.add_child(head)

	for x in [-0.45, 0.45]:
		var horn := MeshInstance3D.new()
		var horn_mesh := BoxMesh.new()
		horn_mesh.size = Vector3(0.18, 0.55, 0.18)
		horn.mesh = horn_mesh
		horn.position = Vector3(x, 6.05, -0.08)
		horn.rotation = Vector3(0.28, 0.0, x * 0.35)
		horn.material_override = _mat(Color(0.82, 0.94, 1.0), 0.75)
		vroot.add_child(horn)

	# Eyes
	for x in [-0.32, 0.32]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.13
		em.height = 0.26
		eye.mesh = em
		eye.position = Vector3(x, 5.5, -0.7)
		eye.material_override = _emissive(Color(0.4, 0.95, 1.0), 2.0)
		vroot.add_child(eye)

	# Two glowing shoulder pustules (visual weak points)
	for x in [-1.3, 1.3]:
		var p := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.5
		pm.height = 1.0
		p.mesh = pm
		p.position = Vector3(x, 4.4, 0)
		p.material_override = _emissive(Color(0.35, 0.85, 1.0), 2.6)
		vroot.add_child(p)

	# Glowing chest core
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.7
	cm.height = 1.4
	core.mesh = cm
	core.position = Vector3(0, 3.0, -0.6)
	core.material_override = _emissive(Color(0.4, 0.9, 1.0), 3.0)
	core.name = "Core"
	vroot.add_child(core)

	# Arms
	for x in [-1.4, 1.4]:
		var arm := MeshInstance3D.new()
		var am := CapsuleMesh.new()
		am.radius = 0.42
		am.height = 2.6
		am.radial_segments = 8
		am.rings = 2
		arm.mesh = am
		arm.position = Vector3(x, 3.0, 0)
		arm.material_override = _mat(Color(0.4, 0.55, 0.7), 0.85)
		vroot.add_child(arm)

	for x in [-0.55, 0.55]:
		var leg := MeshInstance3D.new()
		var lm := CapsuleMesh.new()
		lm.radius = 0.42
		lm.height = 2.4
		lm.radial_segments = 8
		lm.rings = 2
		leg.mesh = lm
		leg.position = Vector3(x, 0.95, 0.1)
		leg.material_override = _mat(Color(0.32, 0.46, 0.62), 0.88)
		vroot.add_child(leg)

	# Cold breath light
	var aura := OmniLight3D.new()
	aura.light_color = Color(0.5, 0.85, 1.0)
	aura.light_energy = 1.6
	aura.omni_range = 12.0
	aura.position = Vector3(0, 4.0, 0)
	vroot.add_child(aura)

	vroot.scale = Vector3.ONE * (visual_scale / 3.4)


func _mat(c: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.07, 0.1, 1)
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


# -- Combat ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)

	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

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
	var dist: float = to_target.length()
	if dist < 0.001:
		move_and_slide()
		return

	var dir: Vector3 = to_target.normalized()
	var look_pos: Vector3 = global_position + dir
	look_at(Vector3(look_pos.x, global_position.y, look_pos.z), Vector3.UP)

	var speed: float = move_speed
	if enraged:
		speed *= enraged_speed_mult

	if dist > attack_range * 0.85:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
		if attack_timer <= 0.0:
			_do_attack()

	if attack_timer > 0.0:
		attack_timer -= delta

	move_and_slide()


func _do_attack() -> void:
	attack_timer = attack_cooldown
	if not is_instance_valid(_target):
		return
	var d: float = global_position.distance_to(_target.global_position)
	if d <= attack_range and _target.has_method("take_damage"):
		var dmg: float = attack_damage * (1.25 if enraged else 1.0)
		_target.take_damage(dmg)
	# Punch animation
	if visuals:
		var tween := create_tween()
		tween.tween_property(visuals, "position:z", -0.6, 0.1)
		tween.tween_property(visuals, "position:z", 0.0, 0.22)
	# Phase-2 shockwave: small AoE around feet to discourage hugging.
	if enraged:
		_shockwave()


func _shockwave() -> void:
	var burst := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	burst.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.95, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.95, 1.0)
	mat.emission_energy_multiplier = 2.5
	burst.material_override = mat
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position + Vector3(0, 0.4, 0)
	var t := burst.create_tween()
	t.tween_property(burst, "scale", Vector3(8, 1.2, 8), 0.4)
	t.parallel().tween_property(mat, "albedo_color", Color(0.6, 0.95, 1.0, 0.0), 0.45)
	t.tween_callback(burst.queue_free)


# -- Damage ---------------------------------------------------------------

func take_damage(amount: float, dmg_type: String = "physical") -> void:
	if is_dead:
		return
	# Boss damage profile: melee is half-effective, pistol/skills full,
	# shock skill +25% (electricity through frost armor).
	var mult: float = 1.0
	match dmg_type:
		"melee":
			mult = 0.5
		"shock":
			mult = 1.25
		_:
			mult = 1.0
	health -= amount * mult
	GameManager.notify_boss_health(max(0.0, health), max_health)
	# Flash visuals
	_flash()
	# Phase-2 trigger
	if not enraged and health <= max_health * 0.5:
		_enrage()
	if health <= 0.0:
		_die()


func _flash() -> void:
	if visuals == null:
		return
	var orig: Vector3 = visuals.scale
	var t := create_tween()
	t.tween_property(visuals, "scale", orig * 1.05, 0.05)
	t.tween_property(visuals, "scale", orig, 0.12)


func _enrage() -> void:
	enraged = true
	GameManager.show_toast("The Titan ROARS — it's enraged!")
	# Recolor the glowing parts to red.
	for child in visuals.get_children():
		if child is MeshInstance3D:
			var m: StandardMaterial3D = (child as MeshInstance3D).material_override as StandardMaterial3D
			if m and m.emission_enabled:
				m.emission = Color(1.0, 0.35, 0.18)


func _die() -> void:
	is_dead = true
	GameManager.notify_boss_defeated()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	# Big collapse: tip over and fade.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation:x", -PI / 2.0, 1.4)
	tween.tween_property(self, "position:y", position.y - 0.8, 1.6).set_delay(0.4)
	tween.chain().tween_interval(2.5)
	tween.chain().tween_callback(queue_free)
