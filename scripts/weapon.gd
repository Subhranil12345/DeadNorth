extends Node3D

# Weapon controller. Owns per-weapon stats and visuals; the player calls
# attack() and the weapon resolves damage against the "zombies" group.
# Switching weapon rebuilds visibility instantly — no equip animation.

signal weapon_changed(weapon_name: String)

enum WeaponType { BAT, AXE, SPEAR, PISTOL }

const WEAPONS: Dictionary = {
	WeaponType.BAT:    {"name": "Bat",    "damage": 35.0, "range": 2.4, "arc_dot": 0.35, "cooldown": 0.45, "ranged": false, "pierce": false},
	WeaponType.AXE:    {"name": "Axe",    "damage": 65.0, "range": 2.6, "arc_dot": 0.50, "cooldown": 0.85, "ranged": false, "pierce": false},
	WeaponType.SPEAR:  {"name": "Spear",  "damage": 42.0, "range": 3.6, "arc_dot": 0.85, "cooldown": 0.55, "ranged": false, "pierce": false},
	WeaponType.PISTOL: {"name": "Pistol", "damage": 28.0, "range": 60.0, "arc_dot": 0.985, "cooldown": 0.32, "ranged": true, "pierce": false},
}

const HANDS: Dictionary = {"name": "Hands", "damage": 6.0, "range": 1.35, "arc_dot": 0.62, "cooldown": 0.62, "ranged": false, "pierce": false}

@export var current_type: int = -1

var _swinging: bool = false
var _rest_rotation: Vector3
var _rest_position: Vector3
var _visuals: Dictionary = {}  # WeaponType -> Node3D wrapper


func _ready() -> void:
	_rest_rotation = rotation
	_rest_position = position
	_build_visuals()
	GameManager.weapon_unlocked.connect(_on_weapon_unlocked)
	if WEAPONS.has(current_type) and _is_weapon_unlocked(current_type):
		_equip_weapon(current_type)
	else:
		current_type = -1
		_hide_all()
		weapon_changed.emit("Hands")


# -- Public API -----------------------------------------------------------

func set_weapon(t: int) -> void:
	if not WEAPONS.has(t):
		return
	if not _is_weapon_unlocked(t):
		GameManager.show_toast("Find %s first." % String(WEAPONS[t]["name"]))
		return
	_equip_weapon(t)


func cycle_next() -> void:
	var keys := WEAPONS.keys()
	keys.sort()
	var idx: int = keys.find(current_type)
	for step in keys.size():
		var next_idx: int = (idx + 1 + step) % keys.size()
		var candidate := int(keys[next_idx])
		if _is_weapon_unlocked(candidate):
			_equip_weapon(candidate)
			return
	GameManager.show_toast("No weapons found yet.")


func get_stats() -> Dictionary:
	if WEAPONS.has(current_type):
		return WEAPONS[current_type]
	return HANDS


func get_cooldown() -> float:
	return float(get_stats()["cooldown"])


func attack(origin: Vector3, forward: Vector3, dmg_mult: float = 1.0) -> void:
	var s: Dictionary = get_stats()
	var ranged: bool = bool(s["ranged"])
	var dmg_type: String = "ranged" if ranged else "melee"
	GameManager.record_damage_use(dmg_type)
	if ranged:
		_play_recoil()
		_muzzle_flash()
	else:
		_play_swing()

	var fwd := forward
	fwd.y = 0.0
	if fwd.length() == 0.0:
		return
	fwd = fwd.normalized()

	var rng: float = float(s["range"])
	var arc: float = float(s["arc_dot"])
	var dmg: float = float(s["damage"]) * dmg_mult

	# Ranged: hitscan onto the closest zombie inside a narrow forward cone.
	if ranged:
		var best: Node = null
		var best_dist: float = INF
		for z in get_tree().get_nodes_in_group("zombies"):
			if not is_instance_valid(z) or z.get("is_dead") == true:
				continue
			var to_z: Vector3 = z.global_position - origin
			to_z.y = 0.0
			var d := to_z.length()
			if d > rng or d < 0.001:
				continue
			if fwd.dot(to_z.normalized()) < arc:
				continue
			if d < best_dist:
				best_dist = d
				best = z
		if best and best.has_method("take_damage"):
			best.take_damage(dmg, dmg_type)
		return

	# Melee: arc cone, hit everyone caught in the swing.
	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or z.get("is_dead") == true:
			continue
		var to_z: Vector3 = z.global_position - origin
		to_z.y = 0.0
		var dist := to_z.length()
		if dist > rng or dist < 0.001:
			continue
		if fwd.dot(to_z.normalized()) < arc:
			continue
		if z.has_method("take_damage"):
			z.take_damage(dmg, dmg_type)


# -- Visuals --------------------------------------------------------------

func _build_visuals() -> void:
	# Wrap the existing scene-defined Bat parts so we can toggle them as a unit.
	var bat_wrapper := Node3D.new()
	bat_wrapper.name = "_Bat"
	add_child(bat_wrapper)
	var to_wrap: Array[Node] = []
	for c in get_children():
		if c == bat_wrapper:
			continue
		if c is MeshInstance3D:
			to_wrap.append(c)
	for n in to_wrap:
		var t: Transform3D = (n as Node3D).transform
		remove_child(n)
		bat_wrapper.add_child(n)
		(n as Node3D).transform = t
	_visuals[WeaponType.BAT] = bat_wrapper

	var axe := _build_axe()
	add_child(axe)
	_visuals[WeaponType.AXE] = axe

	var spear := _build_spear()
	add_child(spear)
	_visuals[WeaponType.SPEAR] = spear

	var pistol := _build_pistol()
	add_child(pistol)
	_visuals[WeaponType.PISTOL] = pistol


func set_rest_pose(pos: Vector3, rot: Vector3) -> void:
	position = pos
	rotation = rot
	_rest_position = pos
	_rest_rotation = rot


func _hide_all() -> void:
	for k in _visuals:
		(_visuals[k] as Node3D).visible = false


func _equip_weapon(t: int) -> void:
	current_type = t
	for k in _visuals:
		(_visuals[k] as Node3D).visible = (k == t)
	weapon_changed.emit(String(WEAPONS[t]["name"]))


func _is_weapon_unlocked(t: int) -> bool:
	if not WEAPONS.has(t):
		return false
	return GameManager.has_weapon(String(WEAPONS[t]["name"]))


func _on_weapon_unlocked(weapon_name: String) -> void:
	if current_type >= 0:
		return
	for k in WEAPONS.keys():
		if String(WEAPONS[k]["name"]) == weapon_name:
			_equip_weapon(int(k))
			return


func _make_box(size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO, metallic: float = 0.0, rough: float = 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = rough
	mi.material_override = mat
	mi.position = pos
	return mi


func _build_axe() -> Node3D:
	var n := Node3D.new()
	n.name = "_Axe"
	n.add_child(_make_box(Vector3(0.07, 0.07, 1.05), Color(0.36, 0.23, 0.13)))
	n.add_child(_make_box(Vector3(0.5, 0.36, 0.08), Color(0.8, 0.82, 0.84), Vector3(0.2, 0.0, -0.58), 0.65, 0.34))
	n.add_child(_make_box(Vector3(0.18, 0.44, 0.07), Color(0.62, 0.65, 0.68), Vector3(-0.14, 0.0, -0.56), 0.55, 0.38))
	n.add_child(_make_box(Vector3(0.16, 0.16, 0.08), Color(0.16, 0.12, 0.09), Vector3(0.0, 0.0, -0.18)))
	return n


func _build_spear() -> Node3D:
	var n := Node3D.new()
	n.name = "_Spear"
	n.add_child(_make_box(Vector3(0.06, 0.06, 1.75), Color(0.48, 0.34, 0.2), Vector3(0.0, 0.0, -0.42)))
	n.add_child(_make_box(Vector3(0.16, 0.16, 0.45), Color(0.86, 0.88, 0.9), Vector3(0.0, 0.0, -1.45), 0.75, 0.28))
	n.add_child(_make_box(Vector3(0.34, 0.08, 0.08), Color(0.22, 0.17, 0.11), Vector3(0.0, 0.0, -0.88)))
	n.add_child(_make_box(Vector3(0.1, 0.1, 0.14), Color(0.9, 0.65, 0.24), Vector3(0.0, 0.0, 0.45), 0.35, 0.45))
	return n


func _build_pistol() -> Node3D:
	var n := Node3D.new()
	n.name = "_Pistol"
	# Grip
	n.add_child(_make_box(Vector3(0.09, 0.26, 0.12), Color(0.1, 0.1, 0.11), Vector3(0.0, -0.06, 0.0)))
	# Slide
	n.add_child(_make_box(Vector3(0.08, 0.12, 0.42), Color(0.34, 0.36, 0.39), Vector3(0.0, 0.08, -0.15), 0.7, 0.3))
	n.add_child(_make_box(Vector3(0.1, 0.08, 0.12), Color(0.9, 0.65, 0.22), Vector3(0.0, 0.12, 0.04), 0.35, 0.42))
	n.add_child(_make_box(Vector3(0.06, 0.06, 0.18), Color(0.08, 0.08, 0.09), Vector3(0.0, 0.04, -0.42), 0.4, 0.35))
	return n


func _muzzle_flash() -> void:
	var v: Node3D = _visuals.get(current_type, null)
	if v == null:
		return
	var flash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	flash.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.5, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.35)
	mat.emission_energy_multiplier = 3.0
	flash.material_override = mat
	flash.position = Vector3(0.0, 0.07, -0.36)
	v.add_child(flash)
	var t := create_tween()
	t.tween_property(flash, "scale", Vector3(0.1, 0.1, 0.1), 0.06)
	t.parallel().tween_property(mat, "albedo_color", Color(1.0, 0.9, 0.5, 0.0), 0.06)
	t.tween_callback(flash.queue_free)


# -- Animation ------------------------------------------------------------

func _play_swing() -> void:
	if _swinging:
		return
	_swinging = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", _rest_rotation + Vector3(-1.5, -0.4, -0.3), 0.10)
	tween.parallel().tween_property(self, "position", _rest_position + Vector3(0.0, 0.05, -0.25), 0.10)
	tween.tween_property(self, "rotation", _rest_rotation, 0.18)
	tween.parallel().tween_property(self, "position", _rest_position, 0.18)
	tween.tween_callback(func() -> void: _swinging = false)


func _play_recoil() -> void:
	if _swinging:
		return
	_swinging = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", _rest_rotation + Vector3(-0.28, 0.0, 0.0), 0.05)
	tween.parallel().tween_property(self, "position", _rest_position + Vector3(0.0, 0.02, 0.08), 0.05)
	tween.tween_property(self, "rotation", _rest_rotation, 0.18)
	tween.parallel().tween_property(self, "position", _rest_position, 0.18)
	tween.tween_callback(func() -> void: _swinging = false)


# Backwards-compat for any old callers.
func play_swing() -> void:
	_play_swing()
