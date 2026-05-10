extends Node

# Drives the sun rotation, sun energy, and the WorldEnvironment colors over
# a configurable day length. Emits phase_changed when crossing a named
# boundary so other systems (spawner, AI) can react to night.

signal phase_changed(time_of_day: float, phase_name: String)

@export var day_length_seconds: float = 240.0  # 4 minutes per full cycle
@export_range(0.0, 1.0) var time_of_day: float = 0.32  # start mid-morning
@export var paused: bool = false
@export var environment_node_path: NodePath
@export var sun_node_path: NodePath

@onready var environment_node: WorldEnvironment = get_node_or_null(environment_node_path)
@onready var sun_node: DirectionalLight3D = get_node_or_null(sun_node_path)

var _phase_name: String = ""

# Color stops keyed by time_of_day. Format documented in _build_phases().
var _stops: Array = []


func _ready() -> void:
	_stops = _build_phases()
	_apply()


func _process(delta: float) -> void:
	if paused:
		return
	time_of_day = fposmod(time_of_day + delta / day_length_seconds, 1.0)
	_apply()


# -- Phase data -----------------------------------------------------------

func _build_phases() -> Array:
	# Entries are evaluated by linear interpolation between adjacent stops.
	# Each stop: time, sky_color, fog_color, ambient_color, ambient_energy,
	# sun_energy, sun_color, phase_name (string used for phase_changed).
	return [
		{"t": 0.00, "sky": Color(0.04, 0.06, 0.13), "fog": Color(0.06, 0.08, 0.14),
			"amb": Color(0.12, 0.15, 0.22), "amb_e": 0.35,
			"sun_e": 0.0, "sun_c": Color(0.4, 0.5, 0.7), "name": "night"},
		{"t": 0.22, "sky": Color(0.06, 0.08, 0.16), "fog": Color(0.10, 0.12, 0.18),
			"amb": Color(0.18, 0.20, 0.28), "amb_e": 0.40,
			"sun_e": 0.05, "sun_c": Color(0.55, 0.5, 0.75), "name": "night"},
		{"t": 0.28, "sky": Color(0.85, 0.55, 0.4), "fog": Color(0.78, 0.62, 0.55),
			"amb": Color(0.6, 0.5, 0.45), "amb_e": 0.55,
			"sun_e": 0.6, "sun_c": Color(1.0, 0.7, 0.5), "name": "dawn"},
		{"t": 0.42, "sky": Color(0.55, 0.7, 0.85), "fog": Color(0.78, 0.83, 0.9),
			"amb": Color(0.7, 0.78, 0.85), "amb_e": 0.6,
			"sun_e": 0.95, "sun_c": Color(1.0, 0.96, 0.88), "name": "day"},
		{"t": 0.62, "sky": Color(0.55, 0.7, 0.85), "fog": Color(0.78, 0.83, 0.9),
			"amb": Color(0.7, 0.78, 0.85), "amb_e": 0.6,
			"sun_e": 0.95, "sun_c": Color(1.0, 0.96, 0.88), "name": "day"},
		{"t": 0.74, "sky": Color(0.85, 0.45, 0.3), "fog": Color(0.6, 0.4, 0.42),
			"amb": Color(0.5, 0.4, 0.42), "amb_e": 0.5,
			"sun_e": 0.45, "sun_c": Color(1.0, 0.6, 0.4), "name": "dusk"},
		{"t": 0.82, "sky": Color(0.06, 0.08, 0.16), "fog": Color(0.10, 0.12, 0.18),
			"amb": Color(0.18, 0.20, 0.28), "amb_e": 0.40,
			"sun_e": 0.05, "sun_c": Color(0.6, 0.5, 0.75), "name": "night"},
		{"t": 1.00, "sky": Color(0.04, 0.06, 0.13), "fog": Color(0.06, 0.08, 0.14),
			"amb": Color(0.12, 0.15, 0.22), "amb_e": 0.35,
			"sun_e": 0.0, "sun_c": Color(0.4, 0.5, 0.7), "name": "night"},
	]


# -- Per-frame work -------------------------------------------------------

func _apply() -> void:
	var t := time_of_day
	var a: Dictionary = _stops[0]
	var b: Dictionary = _stops[_stops.size() - 1]
	for i in range(_stops.size() - 1):
		if t >= float(_stops[i]["t"]) and t <= float(_stops[i + 1]["t"]):
			a = _stops[i]
			b = _stops[i + 1]
			break

	var span: float = float(b["t"]) - float(a["t"])
	var local_t: float = 0.0 if span <= 0.0 else (t - float(a["t"])) / span

	var sky: Color = (a["sky"] as Color).lerp(b["sky"], local_t)
	var fog: Color = (a["fog"] as Color).lerp(b["fog"], local_t)
	var amb: Color = (a["amb"] as Color).lerp(b["amb"], local_t)
	var amb_e: float = lerp(float(a["amb_e"]), float(b["amb_e"]), local_t)
	var sun_e: float = lerp(float(a["sun_e"]), float(b["sun_e"]), local_t)
	var sun_c: Color = (a["sun_c"] as Color).lerp(b["sun_c"], local_t)

	if environment_node and environment_node.environment:
		var env: Environment = environment_node.environment
		env.background_color = sky
		env.fog_light_color = fog
		env.ambient_light_color = amb
		env.ambient_light_energy = amb_e

	if sun_node:
		sun_node.light_energy = sun_e
		sun_node.light_color = sun_c
		sun_node.shadow_enabled = sun_e > 0.08
		sun_node.transform = Transform3D(_sun_basis(t), sun_node.transform.origin)

	# Choose phase name from the upcoming stop so the change fires as we enter
	# the new phase rather than as we leave the old one.
	var name_now: String = String(b["name"]) if local_t > 0.5 else String(a["name"])
	if name_now != _phase_name:
		_phase_name = name_now
		phase_changed.emit(t, _phase_name)


func _sun_basis(t: float) -> Basis:
	# t = 0.5 (noon) -> light points straight down (-Y)
	# t = 0.25 (sunrise) -> light from +X horizon
	# t = 0.75 (sunset) -> light from -X horizon
	var sun_x: float = (t - 0.5) * TAU
	var sx := sin(sun_x)
	var cx := cos(sun_x)
	# Derived so that basis * (0, 0, -1) == (sx, -cx, 0).
	return Basis(
		Vector3(-cx, -sx, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(-sx, cx, 0.0)
	)
