extends StaticBody3D

@export var display_name: String = "Resource"
@export var resource_id: String = "wood"
@export var amount: int = 1
@export var uses_left: int = 1
@export var unlock_weapon_name: String = ""
@export var node_kind: String = "wood"


func _ready() -> void:
	add_to_group("resource_nodes")
	collision_layer = 1
	collision_mask = 0
	_build_collision()
	_build_visuals()
	_build_label()


func prompt_text() -> String:
	if unlock_weapon_name != "":
		return "[G] Pick up %s" % unlock_weapon_name
	var verb := "Gather"
	if node_kind == "mine":
		verb = "Mine"
	elif node_kind == "fish":
		verb = "Catch"
	return "[G] %s %s" % [verb, display_name]


func interact(_player: Node) -> void:
	if unlock_weapon_name != "":
		GameManager.unlock_weapon(unlock_weapon_name)
		queue_free()
		return

	GameManager.add_item(resource_id, amount)
	GameManager.show_toast("+%d %s" % [amount, display_name])
	uses_left -= 1
	if uses_left <= 0:
		queue_free()
	else:
		_pulse()


func _build_collision() -> void:
	if has_node("CollisionShape3D"):
		return
	var shape := BoxShape3D.new()
	if node_kind == "mine":
		shape.size = Vector3(1.8, 1.4, 1.8)
	elif node_kind == "weapon":
		shape.size = Vector3(1.2, 0.9, 1.2)
	else:
		shape.size = Vector3(1.3, 0.8, 1.3)
	var coll := CollisionShape3D.new()
	coll.name = "CollisionShape3D"
	coll.shape = shape
	coll.position.y = shape.size.y * 0.5
	add_child(coll)


func _build_visuals() -> void:
	match node_kind:
		"weapon":
			_build_weapon_pickup()
		"mine":
			_build_mine_rock()
		"stone":
			_build_stone()
		"fish":
			_build_fish()
		_:
			_build_wood()


func _build_weapon_pickup() -> void:
	_make_box(Vector3(1.15, 0.18, 0.8), Vector3(0, 0.1, 0), Color(0.28, 0.18, 0.1))
	_make_box(Vector3(0.14, 0.14, 1.0), Vector3(0, 0.36, 0), Color(0.5, 0.32, 0.17))
	var tool_color := Color(0.78, 0.8, 0.76)
	if unlock_weapon_name == "Pistol":
		tool_color = Color(0.18, 0.2, 0.22)
	elif unlock_weapon_name == "Spear":
		tool_color = Color(0.78, 0.58, 0.25)
	elif unlock_weapon_name == "Axe":
		tool_color = Color(0.7, 0.72, 0.72)
	_make_box(Vector3(0.42, 0.16, 0.16), Vector3(0.26, 0.36, -0.42), tool_color)


func _build_mine_rock() -> void:
	_make_box(Vector3(1.55, 1.0, 1.25), Vector3(0, 0.5, 0), Color(0.26, 0.28, 0.28))
	_make_box(Vector3(0.72, 0.58, 0.48), Vector3(-0.45, 0.96, 0.18), Color(0.18, 0.2, 0.22))
	_make_box(Vector3(0.38, 0.24, 0.16), Vector3(0.35, 0.8, -0.62), Color(0.5, 0.72, 0.78))
	_make_box(Vector3(0.3, 0.18, 0.12), Vector3(-0.48, 0.5, -0.5), Color(0.78, 0.54, 0.24))


func _build_stone() -> void:
	_make_box(Vector3(1.2, 0.55, 0.95), Vector3(0, 0.28, 0), Color(0.34, 0.37, 0.38))
	_make_box(Vector3(0.62, 0.36, 0.52), Vector3(0.38, 0.62, -0.22), Color(0.45, 0.48, 0.48))


func _build_fish() -> void:
	_make_box(Vector3(0.82, 0.22, 0.28), Vector3(0, 0.28, 0), Color(0.38, 0.72, 0.82))
	_make_box(Vector3(0.18, 0.3, 0.12), Vector3(-0.48, 0.28, 0), Color(0.25, 0.52, 0.64))
	_make_box(Vector3(0.22, 0.08, 0.36), Vector3(0.12, 0.43, 0), Color(0.18, 0.42, 0.55))


func _build_wood() -> void:
	for i in 3:
		var log := _make_cylinder(0.16, 1.05, Vector3(0, 0.22 + i * 0.18, -0.2 + i * 0.2), Color(0.42, 0.27, 0.14))
		log.rotation.z = PI * 0.5
		log.rotation.y = i * 0.28


func _build_label() -> void:
	var label := Label3D.new()
	label.text = unlock_weapon_name if unlock_weapon_name != "" else display_name
	label.font_size = 22
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.modulate = Color(1.0, 0.95, 0.78)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 1.65, 0)
	add_child(label)


func _make_box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_inst.mesh = mesh
	mesh_inst.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh_inst.material_override = mat
	add_child(mesh_inst)
	return mesh_inst


func _make_cylinder(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 7
	mesh_inst.mesh = mesh
	mesh_inst.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	mesh_inst.material_override = mat
	add_child(mesh_inst)
	return mesh_inst


func _pulse() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector3(1.08, 1.08, 1.08), 0.08)
	t.tween_property(self, "scale", Vector3.ONE, 0.12)
