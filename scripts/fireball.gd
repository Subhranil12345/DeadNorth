extends Node3D

# Self-contained fireball projectile. The player creates a Node3D, sets this
# script + direction, and adds it to the scene tree. _ready builds visuals;
# _process flies it forward and explodes on impact or when range expires.

@export var speed: float = 28.0
@export var damage: float = 75.0
@export var burn_dps: float = 8.0
@export var burn_duration: float = 4.0
@export var max_distance: float = 35.0
@export var explosion_radius: float = 4.5
@export var hit_radius: float = 1.4

var direction: Vector3 = Vector3.FORWARD
var _traveled: float = 0.0
var _done: bool = false


func _ready() -> void:
	# Glowing core sphere.
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	core.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.18, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
	mat.emission_energy_multiplier = 3.5
	core.material_override = mat
	add_child(core)
	# Soft outer glow.
	var glow := MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = 0.6
	sm2.height = 1.2
	glow.mesh = sm2
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(1.0, 0.4, 0.05, 0.18)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.emission_enabled = true
	gmat.emission = Color(1.0, 0.4, 0.05)
	gmat.emission_energy_multiplier = 1.6
	glow.material_override = gmat
	add_child(glow)
	# Point light so it lights nearby walls/zombies at night.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 1.6
	light.omni_range = 7.0
	add_child(light)


func _process(delta: float) -> void:
	if _done:
		return
	var step := direction * speed * delta
	global_position += step
	_traveled += step.length()

	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or z.get("is_dead") == true:
			continue
		if global_position.distance_to(z.global_position) <= hit_radius:
			_explode()
			return

	if _traveled >= max_distance:
		_explode()


func _explode() -> void:
	if _done:
		return
	_done = true
	# Damage + burn in radius
	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or z.get("is_dead") == true:
			continue
		var d := global_position.distance_to(z.global_position)
		if d <= explosion_radius:
			var falloff: float = clamp(1.0 - d / explosion_radius * 0.5, 0.5, 1.0)
			if z.has_method("take_damage"):
				z.take_damage(damage * falloff, "fire")
			if z.has_method("apply_burn"):
				z.apply_burn(burn_dps, burn_duration)

	# Spawn explosion visual on the parent so it survives our queue_free.
	var parent := get_parent()
	if parent:
		var burst := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		burst.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.55, 0.15, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.1)
		mat.emission_energy_multiplier = 3.0
		burst.material_override = mat
		parent.add_child(burst)
		burst.global_position = global_position
		var t := burst.create_tween()
		t.tween_property(burst, "scale", Vector3.ONE * (explosion_radius / 0.5), 0.35)
		t.parallel().tween_property(mat, "albedo_color", Color(1.0, 0.55, 0.15, 0.0), 0.45)
		t.tween_callback(burst.queue_free)
	queue_free()
