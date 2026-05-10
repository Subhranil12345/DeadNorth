extends Node3D

# Lootable crate scattered around the wilderness. Picks up on player
# proximity (no physics dependency) and grants scrap. Spins gently so
# they're visible at distance.

@export var scrap_value: int = 10
const PICKUP_RANGE: float = 1.7

var _spin: float = 0.0


func _ready() -> void:
	add_to_group("loot")
	_build_visual()


func _build_visual() -> void:
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.55, 0.62)
	box.mesh = bm
	box.position = Vector3(0, 0.35, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.64, 0.42, 0.2)
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.78, 0.3)
	mat.emission_energy_multiplier = 0.35
	box.material_override = mat
	add_child(box)

	_add_band(Vector3(0.78, 0.08, 0.68), Vector3(0, 0.36, 0), Color(0.18, 0.14, 0.1))
	_add_band(Vector3(0.08, 0.64, 0.68), Vector3(-0.24, 0.35, 0), Color(0.18, 0.14, 0.1))
	_add_band(Vector3(0.08, 0.64, 0.68), Vector3(0.24, 0.35, 0), Color(0.18, 0.14, 0.1))
	_add_band(Vector3(0.36, 0.08, 0.08), Vector3(0, 0.68, -0.34), Color(0.95, 0.72, 0.28))

	# Yellow ring on the ground so it pops at distance.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.7
	ring.mesh = tm
	ring.position = Vector3(0, 0.02, 0)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.95, 0.78, 0.3, 0.85)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.8, 0.2)
	rmat.emission_energy_multiplier = 1.4
	ring.material_override = rmat
	add_child(ring)


func _add_band(size: Vector3, pos: Vector3, color: Color) -> void:
	var band := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	band.mesh = bm
	band.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	band.material_override = mat
	add_child(band)


func _process(delta: float) -> void:
	_spin += delta
	rotation.y = _spin * 1.2
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if global_position.distance_to((p as Node3D).global_position) < PICKUP_RANGE:
		GameManager.add_scrap(scrap_value)
		GameManager.show_toast("+%d scrap" % scrap_value)
		queue_free()
