extends CharacterBody3D

# Driveable ground vehicle. The `vehicle_type` export selects from a roster
# of preset stats + visuals (truck, motorcycle, atv, sedan, bus, snowmobile).
# Press G near it to enter; G again to exit. While driving, WASD goes to the
# vehicle directly.

signal entered(driver: Node)
signal exited(driver: Node)

@export var vehicle_type: String = "truck"

# Stats (filled from VEHICLE_DEFS on _ready, kept as @export so tweaks can
# still override the preset in the editor or via _spawn helpers).
@export var max_speed: float = 24.0
@export var reverse_speed: float = 10.0
@export var accel: float = 14.0
@export var brake: float = 24.0
@export var turn_speed: float = 1.6  # rad/s scaled by speed/max

const VEHICLE_DEFS: Dictionary = {
	"truck":      {"label": "Truck",      "max_speed": 26.0, "reverse": 10.0, "accel": 14.0, "brake": 24.0, "turn": 1.6, "cam_arm": 7.5,  "cam_h": 2.2},
	"motorcycle": {"label": "Motorcycle", "max_speed": 34.0, "reverse": 6.0,  "accel": 22.0, "brake": 28.0, "turn": 2.4, "cam_arm": 5.4,  "cam_h": 1.6},
	"atv":        {"label": "ATV",        "max_speed": 22.0, "reverse": 9.0,  "accel": 16.0, "brake": 22.0, "turn": 2.0, "cam_arm": 5.8,  "cam_h": 1.8},
	"sedan":      {"label": "Sedan",      "max_speed": 32.0, "reverse": 12.0, "accel": 18.0, "brake": 26.0, "turn": 1.75,"cam_arm": 6.6,  "cam_h": 1.8},
	"bus":        {"label": "School Bus", "max_speed": 18.0, "reverse": 7.0,  "accel": 10.0, "brake": 18.0, "turn": 1.1, "cam_arm": 11.5, "cam_h": 3.6},
	"snowmobile": {"label": "Snowmobile", "max_speed": 28.0, "reverse": 8.0,  "accel": 18.0, "brake": 20.0, "turn": 2.0, "cam_arm": 5.6,  "cam_h": 1.7},
}

var _speed: float = 0.0
var driver: Node = null

var _camera: Camera3D


func _ready() -> void:
	add_to_group("vehicles")
	collision_layer = 1
	collision_mask = 1
	var def: Dictionary = VEHICLE_DEFS.get(vehicle_type, VEHICLE_DEFS["truck"])
	max_speed = float(def["max_speed"])
	reverse_speed = float(def["reverse"])
	accel = float(def["accel"])
	brake = float(def["brake"])
	turn_speed = float(def["turn"])
	_dispatch_build(vehicle_type)
	_add_name_label(String(def["label"]))
	_build_camera(float(def["cam_arm"]), float(def["cam_h"]))


func _dispatch_build(t: String) -> void:
	match t:
		"motorcycle": _build_motorcycle()
		"atv":        _build_atv()
		"sedan":      _build_sedan()
		"bus":        _build_bus()
		"snowmobile": _build_snowmobile()
		_:            _build_truck()


# -- Truck ----------------------------------------------------------------

func _build_truck() -> void:
	_add_collision(Vector3(2.1, 1.6, 4.2), Vector3(0, 0.9, 0))

	_add_box(Vector3(2.0, 0.9, 4.0), Vector3(0, 0.7, 0), Color(0.62, 0.17, 0.13), 0.25, 0.62)
	_add_box(Vector3(1.7, 0.85, 1.8), Vector3(0, 1.55, 0.25), Color(0.28, 0.44, 0.52), 0.1, 0.35)
	_add_box(Vector3(1.8, 0.15, 1.6), Vector3(0, 1.25, -1.0), Color(0.4, 0.13, 0.13))
	_add_box(Vector3(2.2, 0.16, 0.18), Vector3(0, 0.72, -2.18), Color(0.12, 0.13, 0.14), 0.35, 0.45)
	_add_box(Vector3(1.5, 0.12, 0.08), Vector3(0, 0.98, -2.24), Color(0.08, 0.09, 0.1), 0.45, 0.35)
	_add_box(Vector3(1.45, 0.12, 0.12), Vector3(0, 2.05, 0.25), Color(0.08, 0.1, 0.12), 0.2, 0.55)
	_add_box(Vector3(1.8, 0.08, 1.2), Vector3(0, 2.08, -1.0), Color(0.1, 0.11, 0.12), 0.2, 0.5)
	_add_box(Vector3(0.12, 0.75, 1.55), Vector3(-1.05, 1.35, 0.2), Color(0.42, 0.1, 0.08), 0.2, 0.65)
	_add_box(Vector3(0.12, 0.75, 1.55), Vector3(1.05, 1.35, 0.2), Color(0.42, 0.1, 0.08), 0.2, 0.65)

	_add_headlights([Vector3(-0.7, 0.85, -2.05), Vector3(0.7, 0.85, -2.05)])
	_add_wheels(0.45, 0.3, [-1.0, 1.0], [-1.4, 1.4])


# -- Motorcycle -----------------------------------------------------------

func _build_motorcycle() -> void:
	_add_collision(Vector3(0.6, 1.2, 2.2), Vector3(0, 0.7, 0))

	# Fuel tank + seat
	_add_box(Vector3(0.4, 0.45, 0.85), Vector3(0, 0.95, 0.0), Color(0.18, 0.18, 0.22), 0.3, 0.4)
	_add_box(Vector3(0.42, 0.16, 0.7), Vector3(0, 1.18, -0.4), Color(0.08, 0.08, 0.09), 0.05, 0.55)
	# Engine block under tank
	_add_box(Vector3(0.46, 0.4, 0.55), Vector3(0, 0.55, 0.05), Color(0.32, 0.32, 0.35), 0.6, 0.3)
	# Handlebars
	_add_box(Vector3(0.7, 0.06, 0.06), Vector3(0, 1.15, 0.55), Color(0.1, 0.1, 0.12), 0.7, 0.3)
	_add_box(Vector3(0.06, 0.5, 0.06), Vector3(0, 0.95, 0.5), Color(0.12, 0.12, 0.14), 0.5, 0.35)
	# Front fork / rear frame
	_add_box(Vector3(0.08, 0.7, 0.08), Vector3(0, 0.65, 0.8), Color(0.18, 0.18, 0.22), 0.7, 0.3)
	_add_box(Vector3(0.1, 0.35, 0.9), Vector3(0, 0.85, -0.7), Color(0.45, 0.12, 0.1), 0.3, 0.5)
	# Exhaust pipe
	_add_box(Vector3(0.1, 0.1, 1.0), Vector3(0.32, 0.5, -0.5), Color(0.62, 0.62, 0.66), 0.85, 0.2)

	_add_headlights([Vector3(0, 1.0, 1.05)])
	# Two wheels (front + back), bigger profile
	_add_wheels(0.5, 0.22, [0.0], [-0.95, 0.9])


# -- ATV (Quad) -----------------------------------------------------------

func _build_atv() -> void:
	_add_collision(Vector3(1.4, 1.1, 1.9), Vector3(0, 0.65, 0))

	# Low body
	_add_box(Vector3(1.3, 0.4, 1.5), Vector3(0, 0.55, 0), Color(0.18, 0.42, 0.22), 0.25, 0.55)
	# Front nose + fenders
	_add_box(Vector3(1.05, 0.25, 0.4), Vector3(0, 0.6, 0.85), Color(0.14, 0.32, 0.18), 0.2, 0.55)
	# Seat
	_add_box(Vector3(0.55, 0.2, 0.7), Vector3(0, 0.95, -0.1), Color(0.08, 0.08, 0.09), 0.05, 0.55)
	# Handlebars
	_add_box(Vector3(0.8, 0.06, 0.06), Vector3(0, 1.1, 0.5), Color(0.1, 0.1, 0.12), 0.7, 0.3)
	_add_box(Vector3(0.06, 0.4, 0.06), Vector3(0, 0.9, 0.5), Color(0.12, 0.12, 0.14), 0.5, 0.35)
	# Roll cage
	for x in [-0.55, 0.55]:
		_add_box(Vector3(0.08, 1.0, 0.08), Vector3(x, 1.25, -0.6), Color(0.12, 0.12, 0.14), 0.7, 0.3)
	_add_box(Vector3(1.2, 0.08, 0.08), Vector3(0, 1.7, -0.6), Color(0.12, 0.12, 0.14), 0.7, 0.3)

	_add_headlights([Vector3(-0.32, 0.7, 1.0), Vector3(0.32, 0.7, 1.0)])
	# 4 wide knobby wheels
	_add_wheels(0.42, 0.36, [-0.78, 0.78], [-0.75, 0.75])


# -- Sedan ----------------------------------------------------------------

func _build_sedan() -> void:
	_add_collision(Vector3(1.85, 1.35, 4.1), Vector3(0, 0.75, 0))

	# Lower chassis
	_add_box(Vector3(1.75, 0.5, 3.9), Vector3(0, 0.55, 0), Color(0.22, 0.34, 0.52), 0.55, 0.35)
	# Hood (sloped via offset position)
	_add_box(Vector3(1.7, 0.18, 1.3), Vector3(0, 0.85, 1.1), Color(0.18, 0.28, 0.44), 0.5, 0.35)
	# Trunk
	_add_box(Vector3(1.7, 0.2, 1.0), Vector3(0, 0.84, -1.3), Color(0.18, 0.28, 0.44), 0.5, 0.35)
	# Roof / cabin
	_add_box(Vector3(1.65, 0.55, 2.0), Vector3(0, 1.18, -0.05), Color(0.2, 0.3, 0.48), 0.5, 0.35)
	# Roof flat
	_add_box(Vector3(1.55, 0.1, 1.7), Vector3(0, 1.5, -0.05), Color(0.12, 0.18, 0.3), 0.45, 0.4)
	# Windows
	_add_glow_box(Vector3(1.5, 0.42, 0.06), Vector3(0, 1.18, 0.95), Color(0.45, 0.62, 0.78), 0.4)  # windshield
	_add_glow_box(Vector3(1.5, 0.42, 0.06), Vector3(0, 1.18, -1.05), Color(0.45, 0.62, 0.78), 0.4) # rear
	_add_glow_box(Vector3(0.06, 0.4, 1.6), Vector3(-0.83, 1.18, -0.05), Color(0.4, 0.55, 0.72), 0.35)
	_add_glow_box(Vector3(0.06, 0.4, 1.6), Vector3(0.83, 1.18, -0.05), Color(0.4, 0.55, 0.72), 0.35)
	# Bumpers
	_add_box(Vector3(1.85, 0.18, 0.16), Vector3(0, 0.45, 2.04), Color(0.08, 0.1, 0.12), 0.4, 0.4)
	_add_box(Vector3(1.85, 0.18, 0.16), Vector3(0, 0.45, -2.04), Color(0.08, 0.1, 0.12), 0.4, 0.4)

	_add_headlights([Vector3(-0.6, 0.7, 2.0), Vector3(0.6, 0.7, 2.0)])
	_add_taillights([Vector3(-0.6, 0.7, -2.0), Vector3(0.6, 0.7, -2.0)])
	_add_wheels(0.38, 0.25, [-0.86, 0.86], [-1.45, 1.4])


# -- School Bus -----------------------------------------------------------

func _build_bus() -> void:
	_add_collision(Vector3(2.6, 2.7, 7.6), Vector3(0, 1.4, 0))

	# Main yellow body
	_add_box(Vector3(2.5, 2.2, 7.2), Vector3(0, 1.4, 0), Color(0.96, 0.76, 0.16), 0.15, 0.55)
	# Front cabin (slight overhang)
	_add_box(Vector3(2.45, 0.7, 1.2), Vector3(0, 1.95, 3.2), Color(0.92, 0.72, 0.14), 0.15, 0.55)
	# Roof
	_add_box(Vector3(2.65, 0.18, 7.4), Vector3(0, 2.55, 0), Color(0.6, 0.48, 0.1), 0.2, 0.55)
	# Windows down both sides
	for z_off in [-2.8, -1.6, -0.4, 0.8, 2.0, 3.0]:
		_add_glow_box(Vector3(0.06, 0.55, 0.9), Vector3(-1.27, 1.85, z_off), Color(0.45, 0.62, 0.78), 0.35)
		_add_glow_box(Vector3(0.06, 0.55, 0.9), Vector3(1.27, 1.85, z_off), Color(0.45, 0.62, 0.78), 0.35)
	# Front windshield
	_add_glow_box(Vector3(2.3, 0.75, 0.08), Vector3(0, 2.05, 3.78), Color(0.5, 0.68, 0.82), 0.4)
	# Rear emergency door window
	_add_glow_box(Vector3(1.4, 0.5, 0.08), Vector3(0, 1.85, -3.62), Color(0.45, 0.62, 0.78), 0.35)
	# Bumpers + grill
	_add_box(Vector3(2.65, 0.25, 0.18), Vector3(0, 0.65, 3.82), Color(0.08, 0.1, 0.12), 0.4, 0.4)
	_add_box(Vector3(2.65, 0.25, 0.18), Vector3(0, 0.65, -3.62), Color(0.08, 0.1, 0.12), 0.4, 0.4)
	_add_box(Vector3(0.2, 0.7, 0.1), Vector3(0, 1.05, 3.84), Color(0.16, 0.18, 0.2), 0.5, 0.4)
	# Stop sign on driver side
	var stop_post := _add_box(Vector3(0.08, 0.45, 0.06), Vector3(-1.3, 1.5, -0.5), Color(0.12, 0.13, 0.14))
	_add_glow_box(Vector3(0.55, 0.55, 0.04), Vector3(-1.32, 1.6, -0.5), Color(0.92, 0.18, 0.14), 0.6)
	stop_post.rotation.y = 0.0

	_add_headlights([Vector3(-0.85, 1.1, 3.82), Vector3(0.85, 1.1, 3.82)])
	_add_taillights([Vector3(-0.95, 1.05, -3.6), Vector3(0.95, 1.05, -3.6)])
	# 6 wheels (3 axles)
	_add_wheels(0.56, 0.35, [-1.18, 1.18], [-2.9, -0.1, 2.7])


# -- Snowmobile -----------------------------------------------------------

func _build_snowmobile() -> void:
	_add_collision(Vector3(1.05, 1.0, 2.4), Vector3(0, 0.55, 0))

	# Main body / cowl
	_add_box(Vector3(0.95, 0.45, 1.6), Vector3(0, 0.6, -0.1), Color(0.18, 0.24, 0.36), 0.35, 0.45)
	# Front sloped hood
	_add_box(Vector3(0.85, 0.25, 0.7), Vector3(0, 0.78, 0.85), Color(0.1, 0.15, 0.25), 0.4, 0.4)
	# Windshield
	_add_glow_box(Vector3(0.7, 0.45, 0.05), Vector3(0, 1.1, 0.55), Color(0.55, 0.7, 0.85), 0.5)
	# Seat
	_add_box(Vector3(0.5, 0.18, 0.85), Vector3(0, 0.92, -0.45), Color(0.08, 0.08, 0.09), 0.05, 0.55)
	# Handlebars
	_add_box(Vector3(0.75, 0.06, 0.06), Vector3(0, 1.1, 0.4), Color(0.1, 0.1, 0.12), 0.7, 0.3)
	_add_box(Vector3(0.06, 0.4, 0.06), Vector3(0, 0.9, 0.4), Color(0.12, 0.12, 0.14), 0.5, 0.35)
	# Skis at the front
	for x in [-0.35, 0.35]:
		_add_box(Vector3(0.18, 0.05, 1.1), Vector3(x, 0.18, 0.9), Color(0.85, 0.9, 0.95), 0.3, 0.4)
		# upturned tip
		_add_box(Vector3(0.18, 0.12, 0.16), Vector3(x, 0.27, 1.42), Color(0.85, 0.9, 0.95), 0.3, 0.4)
	# Rear track (treads — represented as a long dark slab + drive cylinders)
	_add_box(Vector3(0.55, 0.32, 1.45), Vector3(0, 0.25, -0.55), Color(0.06, 0.06, 0.07), 0.4, 0.85)
	for z in [-1.1, -0.55, 0.0]:
		var roller := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18
		cm.bottom_radius = 0.18
		cm.height = 0.5
		cm.radial_segments = 10
		roller.mesh = cm
		roller.rotation = Vector3(0, 0, PI / 2.0)
		roller.position = Vector3(0, 0.22, z)
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.1, 0.1, 0.12)
		rmat.roughness = 0.85
		roller.material_override = rmat
		add_child(roller)

	_add_headlights([Vector3(0, 0.95, 1.15)])


# -- Shared builders ------------------------------------------------------

func _add_collision(size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	col.position = pos
	add_child(col)


func _add_wheels(radius: float, width: float, x_offsets: Array, z_offsets: Array) -> void:
	for x in x_offsets:
		for z in z_offsets:
			var w := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = radius
			wm.bottom_radius = radius
			wm.height = width
			wm.radial_segments = 10
			w.mesh = wm
			w.rotation = Vector3(0, 0, PI / 2.0)
			w.position = Vector3(float(x), radius, float(z))
			var wmat := StandardMaterial3D.new()
			wmat.albedo_color = Color(0.1, 0.1, 0.12)
			wmat.roughness = 0.95
			w.material_override = wmat
			add_child(w)

			var hub := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = radius * 0.45
			hm.bottom_radius = radius * 0.45
			hm.height = width + 0.02
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


func _add_headlights(positions: Array) -> void:
	for p in positions:
		var hl := MeshInstance3D.new()
		var bxm := BoxMesh.new()
		bxm.size = Vector3(0.3, 0.2, 0.1)
		hl.mesh = bxm
		hl.position = p
		var hlm := StandardMaterial3D.new()
		hlm.albedo_color = Color(1.0, 0.95, 0.7)
		hlm.emission_enabled = true
		hlm.emission = Color(1.0, 0.95, 0.7)
		hlm.emission_energy_multiplier = 1.4
		hl.material_override = hlm
		add_child(hl)


func _add_taillights(positions: Array) -> void:
	for p in positions:
		var tl := MeshInstance3D.new()
		var bxm := BoxMesh.new()
		bxm.size = Vector3(0.3, 0.18, 0.08)
		tl.mesh = bxm
		tl.position = p
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.18, 0.12)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.2, 0.12)
		mat.emission_energy_multiplier = 1.0
		tl.material_override = mat
		add_child(tl)


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


func _add_glow_box(size: Vector3, pos: Vector3, color: Color, energy: float = 0.6) -> MeshInstance3D:
	var m := _add_box(size, pos, color, 0.1, 0.35)
	var mat := m.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return m


func _add_name_label(text: String) -> void:
	var label := Label3D.new()
	label.text = "[%s]" % text.to_upper()
	label.font_size = 28
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.modulate = Color(0.92, 0.95, 0.78)
	label.position = Vector3(0, 3.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)


func _build_camera(arm_length: float, pivot_y: float) -> void:
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	pivot.position = Vector3(0, pivot_y, 0)
	pivot.rotation.x = -0.18
	add_child(pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = arm_length
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
	# Pop the player out to the left of the vehicle so they don't clip into it.
	if p is Node3D:
		var side: Vector3 = global_transform.basis.x.normalized()
		(p as Node3D).global_position = global_position + side * 1.8 + Vector3(0, 0.2, 0)
	exited.emit(p)


func _physics_process(delta: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Defensive: if driver died while in the seat, eject them so the body
	# doesn't keep cruising via Input polling.
	if driver != null and driver.get("is_dead") == true:
		exit_vehicle()

	# Engines die in deep water. Engine still cuts even if the player tries
	# to coast in — that's intentional so they back out instead of crossing.
	var in_water: bool = _is_over_water()

	if driver == null:
		_speed = move_toward(_speed, 0.0, brake * 0.4 * delta)
	elif in_water:
		# Water — kill thrust, heavy drag. No steering authority while stuck.
		_speed = move_toward(_speed, 0.0, brake * 1.6 * delta)
		if not _water_toast_shown:
			_water_toast_shown = true
			GameManager.show_toast("The engine sputters — back out of the water!")
	else:
		_water_toast_shown = false
		var fw: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		if fw > 0.01:
			_speed = move_toward(_speed, max_speed, accel * delta)
		elif fw < -0.01:
			_speed = move_toward(_speed, -reverse_speed, brake * delta)
		else:
			_speed = move_toward(_speed, 0.0, accel * 0.6 * delta)

		var turn: float = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		if absf(_speed) > 0.4:
			# Turn rate scales with speed so parked spin doesn't happen.
			var t_strength: float = turn_speed * clamp(absf(_speed) / max_speed, 0.25, 1.0)
			rotate_y(turn * t_strength * delta * signf(_speed))

	var fwd: Vector3 = -global_transform.basis.z
	velocity.x = fwd.x * _speed
	velocity.z = fwd.z * _speed
	move_and_slide()


var _water_toast_shown: bool = false


func _is_over_water() -> bool:
	# Ask the world script which biome we're in. Cached lookup; safe if the
	# world is missing the helper (e.g. running scenes in isolation).
	var world := get_tree().current_scene
	if world == null or not world.has_method("get_biome_at"):
		return false
	var b: String = world.get_biome_at(global_position)
	return b == "ocean"
