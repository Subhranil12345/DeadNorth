extends StaticBody3D

# Sanctuary NPC. Three roles dispatched off `role`: doctor (heal for scrap),
# mechanic (repair workshop, then sell a truck), foreman (kill quests).
# Visuals are a colored capsule + cube head + a billboarded name label so
# players can spot who's who from a distance.

@export var npc_name: String = "Stranger"
@export var role: String = "doctor"  # doctor / mechanic / foreman
@export var body_color: Color = Color(0.5, 0.6, 0.8)
@export var trim_color: Color = Color(0.95, 0.95, 0.95)


func _ready() -> void:
	add_to_group("npcs")
	collision_layer = 1
	collision_mask = 0
	_build_visuals()


func _build_visuals() -> void:
	var col := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.4
	sh.height = 1.8
	col.shape = sh
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.38
	bm.height = 1.4
	body.mesh = bm
	body.position = Vector3(0, 0.9, 0)
	body.material_override = _mat(body_color)
	add_child(body)

	_box(Vector3(0.18, 0.75, 0.18), Vector3(-0.45, 1.05, -0.05), body_color.darkened(0.15), Vector3(0.35, 0.0, -0.15))
	_box(Vector3(0.18, 0.75, 0.18), Vector3(0.45, 1.05, -0.05), body_color.darkened(0.15), Vector3(-0.35, 0.0, 0.15))
	_box(Vector3(0.62, 0.12, 0.16), Vector3(0, 1.45, -0.35), trim_color, Vector3.ZERO)

	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.42, 0.42, 0.42)
	head.mesh = hm
	head.position = Vector3(0, 1.85, 0)
	head.material_override = _mat(trim_color)
	add_child(head)

	var hat_color := Color(0.12, 0.14, 0.17)
	if role == "doctor":
		hat_color = Color(0.9, 0.95, 0.98)
	elif role == "mechanic":
		hat_color = Color(0.95, 0.58, 0.14)
	elif role == "foreman":
		hat_color = Color(0.82, 0.68, 0.32)
	_box(Vector3(0.58, 0.16, 0.58), Vector3(0, 2.13, 0), hat_color, Vector3.ZERO)
	_box(Vector3(0.42, 0.08, 0.22), Vector3(0, 2.05, -0.32), hat_color.darkened(0.12), Vector3.ZERO)

	# Floating name + role label, billboarded so it always faces the camera.
	var label := Label3D.new()
	label.text = "%s\n[%s]" % [npc_name, role.to_upper()]
	label.font_size = 32
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 1)
	label.modulate = trim_color
	label.position = Vector3(0, 2.55, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _box(size: Vector3, pos: Vector3, color: Color, rot: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.rotation = rot
	mesh.material_override = _mat(color)
	add_child(mesh)
	return mesh


# -- Interaction ----------------------------------------------------------

func interact(player: Node) -> void:
	match role:
		"doctor":
			_do_doctor(player)
		"mechanic":
			_do_mechanic(player)
		"foreman":
			_do_foreman(player)
		_:
			GameManager.show_toast("%s has nothing to say." % npc_name)


func _do_doctor(p: Node) -> void:
	var cost: int = GameManager.COST_HEAL
	if p.get("health") != null and float(p.health) >= float(p.max_health) and float(p.stamina) >= float(p.max_stamina):
		GameManager.show_toast("%s: 'You're fine. Save your scrap.'" % npc_name)
		return
	if not GameManager.spend_scrap(cost):
		GameManager.show_toast("%s: 'I need %d scrap. You have %d.'" % [npc_name, cost, GameManager.scrap])
		return
	p.health = p.max_health
	p.stamina = p.max_stamina
	if p.has_signal("health_changed"):
		p.health_changed.emit(p.health, p.max_health)
		p.stamina_changed.emit(p.stamina, p.max_stamina)
	GameManager.show_toast("%s: 'Patched up. -%d scrap.'" % [npc_name, cost])


func _do_mechanic(_p: Node) -> void:
	if not GameManager.workshop_repaired:
		var repair_cost: int = GameManager.COST_REPAIR_WORKSHOP
		if not GameManager.spend_scrap(repair_cost):
			GameManager.show_toast("%s: 'Workshop's wrecked. %d scrap to fix.'" % [npc_name, repair_cost])
			return
		GameManager.workshop_repaired = true
		GameManager.world_state_changed.emit()
		GameManager.show_toast("%s: 'Workshop's running. Come back for wheels.'" % npc_name)
		return
	if GameManager.car_owned:
		GameManager.show_toast("%s: 'Truck's parked outside. Press G to drive.'" % npc_name)
		return
	var truck_cost: int = GameManager.COST_BUY_CAR
	if not GameManager.spend_scrap(truck_cost):
		GameManager.show_toast("%s: 'Truck's %d scrap. Come back when you're flush.'" % [npc_name, truck_cost])
		return
	GameManager.car_owned = true
	GameManager.world_state_changed.emit()
	GameManager.show_toast("%s: 'She's all yours. Drives like a brick but she runs.'" % npc_name)


func _do_foreman(_p: Node) -> void:
	if GameManager.active_quest.size() == 0:
		GameManager.start_random_quest()
		GameManager.show_toast("%s: '%s'" % [npc_name, GameManager.quest_text()])
		return
	if GameManager.is_quest_complete():
		var reward: int = GameManager.complete_quest()
		GameManager.show_toast("%s: 'Solid work. +%d scrap.'" % [npc_name, reward])
		return
	GameManager.show_toast("%s: '%s'" % [npc_name, GameManager.quest_text()])
