extends CharacterBody3D

# Drivable truck. Press G near it to enter; G again to exit. While the
# player is the driver the vehicle reads WASD directly via Input. Exiting
# pops the player out the side door at ground level.
#
# Visuals (body + cabin + four wheels) and the chase camera are built in
# _ready so this works without a paired scene file.

signal entered(driver: Node)
signal exited(driver: Node)

@export var max_speed: float = 24.0
@export var reverse_speed: float = 10.0
@export var accel: float = 14.0
@export var brake: float = 24.0
@export var turn_speed: float = 1.6  # rad/s scaled by speed/max

var _speed: float = 0.0
var driver: Node = null

var _camera: Camera3D


func _ready() -> void:
	add_to_group("vehicles")
	collision_layer = 1
	collision_mask = 1
	_build_visuals()
	_build_camera()


func _build_visuals() -> void:
	# Physics shape — one box covering the chassis.
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.1, 1.6, 4.2)
	col.shape = sh
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# Body
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 0.9, 4.0)
	body.mesh = bm
	body.position = Vector3(0, 0.7, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.62, 0.17, 0.13)
	bmat.metallic = 0.25
	bmat.roughness = 0.62
	body.material_override = bmat
	add_child(body)

	# Cabin
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.7, 0.85, 1.8)
	cabin.mesh = cm
	cabin.position = Vector3(0, 1.55, 0.25)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.28, 0.44, 0.52)
	cmat.metallic = 0.1
	cmat.roughness = 0.35
	cabin.material_override = cmat
	add_child(cabin)

	# Cargo bed cap (slightly raised lip)
	var bed := MeshInstance3D.new()
	var bdm := BoxMesh.new()
	bdm.size = Vector3(1.8, 0.15, 1.6)
	bed.mesh = bdm
	bed.position = Vector3(0, 1.25, -1.0)
	var bedmat := StandardMaterial3D.new()
	bedmat.albedo_color = Color(0.4, 0.13, 0.13)
	bed.material_override = bedmat
	add_child(bed)

	_add_box(Vector3(2.2, 0.16, 0.18), Vector3(0, 0.72, -2.18), Color(0.12, 0.13, 0.14), 0.35, 0.45)
	_add_box(Vector3(1.5, 0.12, 0.08), Vector3(0, 0.98, -2.24), Color(0.08, 0.09, 0.1), 0.45, 0.35)
	_add_box(Vector3(1.45, 0.12, 0.12), Vector3(0, 2.05, 0.25), Color(0.08, 0.1, 0.12), 0.2, 0.55)
	_add_box(Vector3(1.8, 0.08, 1.2), Vector3(0, 2.08, -1.0), Color(0.1, 0.11, 0.12), 0.2, 0.5)
	_add_box(Vector3(0.12, 0.75, 1.55), Vector3(-1.05, 1.35, 0.2), Color(0.42, 0.1, 0.08), 0.2, 0.65)
	_add_box(Vector3(0.12, 0.75, 1.55), Vector3(1.05, 1.35, 0.2), Color(0.42, 0.1, 0.08), 0.2, 0.65)

	# Headlights
	for x in [-0.7, 0.7]:
		var hl := MeshInstance3D.new()
		var bxm := BoxMesh.new()
		bxm.size = Vector3(0.3, 0.2, 0.1)
		hl.mesh = bxm
		hl.position = Vector3(x, 0.85, -2.05)
		var hlm := StandardMaterial3D.new()
		hlm.albedo_color = Color(1.0, 0.95, 0.7)
		hlm.emission_enabled = true
		hlm.emission = Color(1.0, 0.95, 0.7)
		hlm.emission_energy_multiplier = 1.4
		hl.material_override = hlm
		add_child(hl)

	# Wheels — purely cosmetic, the chassis box handles the physics.
	for x in [-1.0, 1.0]:
		for z in [-1.4, 1.4]:
			var w := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.45
			wm.bottom_radius = 0.45
			wm.height = 0.3
			wm.radial_segments = 10
			w.mesh = wm
			w.rotation = Vector3(0, 0, PI / 2.0)
			w.position = Vector3(x, 0.45, z)
			var wmat := StandardMaterial3D.new()
			wmat.albedo_color = Color(0.1, 0.1, 0.12)
			wmat.roughness = 0.95
			w.material_override = wmat
			add_child(w)

			var hub := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = 0.2
			hm.bottom_radius = 0.2
			hm.height = 0.32
			hm.radial_segments = 8
			hub.mesh = hm
			hub.rotation = w.rotation
			hub.position = w.position
			var hmat := StandardMaterial3D.new()
			hmat.albedo_color = Color(0.62, 0.64, 0.66)
			hmat.metallic = 0.6
			hmat.roughness = 0.35
			hub.material_override = hmat
			add_child(hub)


func _add_box(size: Vector3, pos: Vector3, color: Color, metallic: float = 0.0, rough: float = 0.85) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = rough
	mesh.material_override = mat
	add_child(mesh)
	return mesh


func _build_camera() -> void:
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	pivot.position = Vector3(0, 2.2, 0)
	pivot.rotation.x = -0.18
	add_child(pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = 7.5
	arm.collision_mask = 1
	arm.margin = 0.2
	pivot.add_child(arm)
	_camera = Camera3D.new()
	_camera.fov = 78.0
	_camera.position = Vector3(0, 0.4, 0)
	arm.add_child(_camera)


# -- Driver swap ----------------------------------------------------------

func enter(p: Node) -> bool:
	if driver != null:
		return false
	driver = p
	if _camera and is_instance_valid(_camera):
		_camera.make_current()
	if p.has_method("set_in_vehicle"):
		p.set_in_vehicle(self)
	entered.emit(p)
	return true


func exit_vehicle() -> void:
	if driver == null:
		return
	var p: Node = driver
	driver = null
	if p.has_method("set_in_vehicle"):
		p.set_in_vehicle(null)
	# Pop the player out to the left of the truck so they don't clip into it.
	if p is Node3D:
		var side: Vector3 = global_transform.basis.x.normalized()
		(p as Node3D).global_position = global_position + side * 1.8 + Vector3(0, 0.2, 0)
	exited.emit(p)


func _physics_process(delta: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
	if not is_on_floor():
		velocity.y -= gravity * delta

	if driver == null:
		# No driver — coast to a halt.
		_speed = move_toward(_speed, 0.0, brake * 0.4 * delta)
	else:
		var fw: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		if fw > 0.01:
			_speed = move_toward(_speed, max_speed, accel * delta)
		elif fw < -0.01:
			_speed = move_toward(_speed, -reverse_speed, brake * delta)
		else:
			_speed = move_toward(_speed, 0.0, accel * 0.6 * delta)

		var turn: float = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		if absf(_speed) > 0.4:
			# Turn rate scales with speed so parked-truck-spin doesn't happen.
			var t_strength: float = turn_speed * clamp(absf(_speed) / max_speed, 0.25, 1.0)
			rotate_y(turn * t_strength * delta * signf(_speed))

	var fwd: Vector3 = -global_transform.basis.z
	velocity.x = fwd.x * _speed
	velocity.z = fwd.z * _speed
	move_and_slide()
