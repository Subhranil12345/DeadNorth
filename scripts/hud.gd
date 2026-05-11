extends CanvasLayer

@onready var health_bar: ProgressBar = $Root/Stats/HealthBar
@onready var stamina_bar: ProgressBar = $Root/Stats/StaminaBar
@onready var kills_label: Label = $Root/KillsLabel
@onready var center_label: Label = $Root/CenterLabel
@onready var crosshair: Label = $Root/Crosshair
@onready var hint_label: Label = $Root/HintLabel

var _weapon_label: Label
var _skill_panel: Control
var _skill_labels: Array[Label] = []
var _scrap_label: Label
var _inventory_label: Label
var _quest_label: Label
var _objective_label: Label
var _interact_label: Label
var _toast_label: Label
var _toast_tween: Tween = null
var _player: Node = null

# New for the run-state slice:
var _warmth_bar: ProgressBar
var _trait_label: Label
var _phase_label: Label
var _weather_label: Label
var _compass_panel: Panel
var _compass_strip: Control
var _boss_panel: Panel
var _boss_bar: ProgressBar
var _boss_label: Label
var _map_overlay: Control
var _map_canvas: Control
var _map_player_dot: ColorRect
var _map_objective_dot: ColorRect

const COMPASS_WIDTH: float = 280.0
const MAP_WIDTH: float = 980.0
const MAP_HEIGHT: float = 620.0
const SKILL_TUTORIAL_SECONDS: float = 7.0
const SKILL_TUTORIAL_FADE_SECONDS: float = 1.2
const COMPASS_PX_PER_DEG: float = 1.6  # ~175° visible across the strip

var _skill_tutorial_time_left: float = SKILL_TUTORIAL_SECONDS


func _ready() -> void:
	GameManager.kills_changed.connect(_on_kills_changed)
	GameManager.player_died.connect(_on_player_died)
	GameManager.game_won.connect(_on_game_won)
	GameManager.scrap_changed.connect(_on_scrap_changed)
	GameManager.quest_changed.connect(_on_quest_changed)
	GameManager.toast.connect(_on_toast)
	GameManager.trait_changed.connect(_on_trait_changed_hud)
	GameManager.phase_changed.connect(_on_phase_changed_hud)
	GameManager.weather_changed.connect(_on_weather_changed_hud)
	GameManager.boss_spawned.connect(_on_boss_spawned)
	GameManager.boss_health_changed.connect(_on_boss_health_changed)
	GameManager.boss_defeated.connect(_on_boss_defeated)
	GameManager.inventory_changed.connect(_on_inventory_changed)

	center_label.visible = false
	hint_label.text = "WASD move | Shift sprint | LMB attack | 1-9 weapon | QEF skills | G interact | B build | M map | Esc cursor"

	_build_weapon_panel()
	_build_skill_panel()
	_build_scrap_label()
	_build_inventory_label()
	_build_quest_label()
	_build_objective_label()
	_build_interact_label()
	_build_toast_label()
	_build_warmth_bar()
	_build_trait_label()
	_build_phase_label()
	_build_weather_label()
	_build_compass()
	_build_boss_bar()
	_build_map_overlay()

	_on_kills_changed(GameManager.kills)
	_on_scrap_changed(GameManager.scrap)
	_on_inventory_changed(GameManager.resources, GameManager.unlocked_weapons)
	_on_quest_changed(GameManager.active_quest)
	# Player is added before HUD in the scene, so it should be present now.
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.health_changed.connect(_on_health_changed)
		_player.stamina_changed.connect(_on_stamina_changed)
		if _player.has_signal("warmth_changed"):
			_player.warmth_changed.connect(_on_warmth_changed)
		var w: Node = _player.get("weapon")
		if w and w.has_signal("weapon_changed"):
			w.weapon_changed.connect(_on_weapon_changed)
			if w.has_method("get_stats"):
				_on_weapon_changed(String(w.get_stats()["name"]))

	# Apply current GameManager state — these signals already fired before
	# the HUD connected, so seed the labels manually.
	if GameManager.active_trait.size() > 0:
		_on_trait_changed_hud(GameManager.active_trait)
	_on_phase_changed_hud(GameManager.phase)
	_on_weather_changed_hud(GameManager.weather)


func _build_weapon_panel() -> void:
	var p := Panel.new()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.offset_left = -260.0
	p.offset_top = 70.0
	p.offset_right = -24.0
	p.offset_bottom = 110.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.55)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	p.add_theme_stylebox_override("panel", sb)
	$Root.add_child(p)

	_weapon_label = Label.new()
	_weapon_label.text = "WEAPON: Bat"
	_weapon_label.anchor_right = 1.0
	_weapon_label.anchor_bottom = 1.0
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_weapon_label.add_theme_font_size_override("font_size", 16)
	_weapon_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	_weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_weapon_label)


func _build_skill_panel() -> void:
	var box := HBoxContainer.new()
	_skill_panel = box
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 1.0
	box.offset_left = -228.0
	box.offset_right = 228.0
	box.offset_top = -78.0
	box.offset_bottom = -28.0
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(box)

	var defs := [
		{"key": "Q", "name": "FIRE",  "color": Color(1.0, 0.55, 0.15)},
		{"key": "E", "name": "FROST", "color": Color(0.45, 0.85, 1.0)},
		{"key": "F", "name": "SHOCK", "color": Color(0.85, 0.75, 1.0)},
	]
	for def in defs:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(144, 50)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.07, 0.1, 0.6)
		sb.border_color = (def["color"] as Color)
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		cell.add_theme_stylebox_override("panel", sb)
		box.add_child(cell)

		var lbl := Label.new()
		lbl.text = "[%s] %s" % [def["key"], def["name"]]
		lbl.anchor_right = 1.0
		lbl.anchor_bottom = 1.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", def["color"])
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(lbl)
		_skill_labels.append(lbl)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	_refresh_skill_tutorial(delta)
	_refresh_interact_prompt()
	_refresh_objective_label()
	_refresh_map_marker()
	_update_compass()
	_refresh_regroup_phase_label()


func _refresh_skill_tutorial(delta: float) -> void:
	if _skill_panel == null or not _skill_panel.visible:
		return
	_skill_tutorial_time_left = max(0.0, _skill_tutorial_time_left - delta)
	if _skill_tutorial_time_left < SKILL_TUTORIAL_FADE_SECONDS:
		var alpha := _skill_tutorial_time_left / SKILL_TUTORIAL_FADE_SECONDS
		_skill_panel.modulate = Color(1, 1, 1, alpha)
	if _skill_tutorial_time_left <= 0.0:
		_skill_panel.visible = false


func _refresh_interact_prompt() -> void:
	if _interact_label == null:
		return
	if _player == null or not is_instance_valid(_player):
		_interact_label.visible = false
		return
	if bool(_player.get("in_vehicle")):
		_interact_label.text = "[G] Exit Truck"
		_interact_label.visible = true
		return
	var range_v: float = 3.5
	var p_pos: Vector3 = (_player as Node3D).global_position
	var best_text: String = ""
	var best_d: float = INF
	for n in get_tree().get_nodes_in_group("npcs"):
		var d: float = p_pos.distance_to((n as Node3D).global_position)
		if d < range_v and d < best_d:
			best_d = d
			var npc_name: String = String(n.get("npc_name") if n.get("npc_name") != null else "Stranger")
			best_text = "[G] Talk to %s" % npc_name
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.get("driver") != null:
			continue
		var d: float = p_pos.distance_to((v as Node3D).global_position)
		if d < range_v + 1.5 and d < best_d:
			best_d = d
			best_text = "[G] Enter Truck"
	for r in get_tree().get_nodes_in_group("resource_nodes"):
		if not (r is Node3D):
			continue
		var d: float = p_pos.distance_to((r as Node3D).global_position)
		if d < range_v and d < best_d:
			best_d = d
			if r.has_method("prompt_text"):
				best_text = String(r.prompt_text())
			else:
				best_text = "[G] Gather"
	if best_text == "":
		if GameManager.has_items({"wood": 10, "stone": 4}):
			_interact_label.text = "[B] Build Shelter"
			_interact_label.visible = true
		else:
			_interact_label.visible = false
	else:
		_interact_label.text = best_text
		_interact_label.visible = true


func _refresh_objective_label() -> void:
	if _objective_label == null or _player == null or not is_instance_valid(_player):
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("objective_status"):
		_objective_label.text = String(scene.objective_status((_player as Node3D).global_position))
		_objective_label.visible = true
	else:
		_objective_label.visible = false


func _refresh_map_marker() -> void:
	if _map_overlay == null or not _map_overlay.visible or _player == null or not is_instance_valid(_player):
		return
	_map_player_dot.position = _world_to_map((_player as Node3D).global_position) - _map_player_dot.size * 0.5
	_map_objective_dot.position = _world_to_map(Vector3(1300.0, 0.0, -1075.0)) - _map_objective_dot.size * 0.5


func _world_to_map(world_pos: Vector3) -> Vector2:
	var scene := get_tree().current_scene
	var half_x := 2000.0
	var half_z := 2000.0
	if scene != null:
		var scene_half_x = scene.get("arena_half_x")
		var scene_half_z = scene.get("arena_half_z")
		if scene_half_x != null:
			half_x = float(scene_half_x)
		if scene_half_z != null:
			half_z = float(scene_half_z)
	var x := inverse_lerp(-half_x, half_x, world_pos.x) * MAP_WIDTH
	var y := inverse_lerp(-half_z, half_z, world_pos.z) * MAP_HEIGHT
	return Vector2(clamp(x, 0.0, MAP_WIDTH), clamp(y, 0.0, MAP_HEIGHT))


# -- HUD construction -----------------------------------------------------

func _build_scrap_label() -> void:
	_scrap_label = Label.new()
	_scrap_label.anchor_left = 1.0
	_scrap_label.anchor_right = 1.0
	_scrap_label.offset_left = -280.0
	_scrap_label.offset_top = 50.0
	_scrap_label.offset_right = -24.0
	_scrap_label.offset_bottom = 74.0
	_scrap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scrap_label.add_theme_font_size_override("font_size", 18)
	_scrap_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_scrap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrap_label.text = "SCRAP  0"
	$Root.add_child(_scrap_label)


func _build_inventory_label() -> void:
	_inventory_label = Label.new()
	_inventory_label.anchor_left = 1.0
	_inventory_label.anchor_right = 1.0
	_inventory_label.offset_left = -320.0
	_inventory_label.offset_top = 140.0
	_inventory_label.offset_right = -24.0
	_inventory_label.offset_bottom = 196.0
	_inventory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_inventory_label.add_theme_font_size_override("font_size", 14)
	_inventory_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.8))
	_inventory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory_label.text = ""
	$Root.add_child(_inventory_label)


func _build_quest_label() -> void:
	_quest_label = Label.new()
	_quest_label.anchor_right = 1.0
	_quest_label.offset_top = 42.0
	_quest_label.offset_bottom = 64.0
	_quest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quest_label.add_theme_font_size_override("font_size", 14)
	_quest_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 0.9))
	_quest_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_label.text = ""
	$Root.add_child(_quest_label)


func _build_objective_label() -> void:
	_objective_label = Label.new()
	_objective_label.anchor_right = 1.0
	_objective_label.offset_top = 112.0
	_objective_label.offset_bottom = 136.0
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.add_theme_font_size_override("font_size", 15)
	_objective_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.58))
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_label.text = ""
	$Root.add_child(_objective_label)


func _build_interact_label() -> void:
	_interact_label = Label.new()
	_interact_label.anchor_left = 0.5
	_interact_label.anchor_right = 0.5
	_interact_label.anchor_top = 0.5
	_interact_label.anchor_bottom = 0.5
	_interact_label.offset_left = -180.0
	_interact_label.offset_right = 180.0
	_interact_label.offset_top = 60.0
	_interact_label.offset_bottom = 92.0
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_label.add_theme_font_size_override("font_size", 18)
	_interact_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_label.visible = false
	$Root.add_child(_interact_label)


func _build_toast_label() -> void:
	_toast_label = Label.new()
	_toast_label.anchor_left = 0.5
	_toast_label.anchor_right = 0.5
	_toast_label.anchor_bottom = 1.0
	_toast_label.offset_left = -300.0
	_toast_label.offset_right = 300.0
	_toast_label.offset_top = -160.0
	_toast_label.offset_bottom = -120.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 18)
	_toast_label.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.modulate = Color(1, 1, 1, 0)
	$Root.add_child(_toast_label)


# -- Signal handlers ------------------------------------------------------

func _on_scrap_changed(total: int) -> void:
	if _scrap_label:
		_scrap_label.text = "SCRAP  %d" % total


func _on_inventory_changed(resource_counts: Dictionary, unlocked: Dictionary) -> void:
	if _inventory_label == null:
		return
	var tool_text := "Hands"
	if unlocked.size() > 0:
		tool_text = ""
		var i := 0
		for k in unlocked.keys():
			if i > 0:
				tool_text += ", "
			tool_text += String(k)
			i += 1
	_inventory_label.text = "WOOD %d  STONE %d\nORE %d  FISH %d\nTOOLS %s" % [
		int(resource_counts.get("wood", 0)),
		int(resource_counts.get("stone", 0)),
		int(resource_counts.get("ore", 0)),
		int(resource_counts.get("fish", 0)),
		tool_text,
	]


func _on_quest_changed(quest: Dictionary) -> void:
	if _quest_label == null:
		return
	if quest == null or quest.size() == 0:
		_quest_label.text = "Talk to Foreman Ash for work."
		_quest_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7, 0.7))
		return
	var done: bool = int(quest.get("progress", 0)) >= int(quest.get("count", 1))
	if done:
		_quest_label.text = "QUEST COMPLETE — return to Foreman Ash"
		_quest_label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.45))
	else:
		_quest_label.text = "QUEST: " + GameManager.quest_text()
		_quest_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 0.9))


func _on_toast(text: String) -> void:
	if _toast_label == null:
		return
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.text = text
	_toast_label.modulate = Color(1, 1, 1, 1)
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.6)


# -- Survival / trait / phase / weather ----------------------------------

func _build_warmth_bar() -> void:
	# The Stats VBox grows downward as we append; bump its top offset so the
	# new rows don't extend off-screen.
	var stats: VBoxContainer = $Root/Stats
	stats.offset_top = -160.0
	var lbl := Label.new()
	lbl.text = "WARMTH"
	lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(lbl)
	_warmth_bar = ProgressBar.new()
	_warmth_bar.custom_minimum_size = Vector2(260, 14)
	_warmth_bar.max_value = 100.0
	_warmth_bar.value = 100.0
	_warmth_bar.modulate = Color(0.55, 0.85, 1.0)
	_warmth_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(_warmth_bar)


func _build_trait_label() -> void:
	# Top-left, below the centered hint line. Stays out of the way of
	# the Stats VBox at the bottom-left.
	_trait_label = Label.new()
	_trait_label.offset_left = 24.0
	_trait_label.offset_top = 50.0
	_trait_label.offset_right = 520.0
	_trait_label.offset_bottom = 72.0
	_trait_label.add_theme_font_size_override("font_size", 13)
	_trait_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_trait_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trait_label.text = ""
	$Root.add_child(_trait_label)


func _build_phase_label() -> void:
	_phase_label = Label.new()
	_phase_label.anchor_right = 1.0
	_phase_label.offset_top = 86.0
	_phase_label.offset_bottom = 110.0
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 16)
	_phase_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.78))
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_label.text = ""
	$Root.add_child(_phase_label)


func _build_weather_label() -> void:
	_weather_label = Label.new()
	_weather_label.anchor_left = 1.0
	_weather_label.anchor_right = 1.0
	_weather_label.offset_left = -280.0
	_weather_label.offset_top = 116.0
	_weather_label.offset_right = -24.0
	_weather_label.offset_bottom = 138.0
	_weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weather_label.add_theme_font_size_override("font_size", 14)
	_weather_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.9))
	_weather_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(_weather_label)


func _build_compass() -> void:
	_compass_panel = Panel.new()
	_compass_panel.anchor_left = 0.5
	_compass_panel.anchor_right = 0.5
	_compass_panel.offset_left = -COMPASS_WIDTH * 0.5
	_compass_panel.offset_right = COMPASS_WIDTH * 0.5
	_compass_panel.offset_top = 50.0
	_compass_panel.offset_bottom = 80.0
	_compass_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_panel.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.55)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	_compass_panel.add_theme_stylebox_override("panel", sb)
	$Root.add_child(_compass_panel)

	_compass_strip = Control.new()
	_compass_strip.anchor_top = 0.0
	_compass_strip.anchor_bottom = 1.0
	_compass_strip.position = Vector2(COMPASS_WIDTH * 0.5, 0)
	_compass_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_panel.add_child(_compass_strip)

	# Repeat tick set 3x for wraparound: -360°, 0°, +360°.
	var labels := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for cycle in [-1, 0, 1]:
		for i in 8:
			var deg: float = i * 45.0 + cycle * 360.0
			var t := Label.new()
			t.text = labels[i]
			t.size = Vector2(40, 30)
			t.position = Vector2(deg * COMPASS_PX_PER_DEG - 20.0, 0.0)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			t.add_theme_font_size_override("font_size", 14)
			t.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 0.9) if labels[i].length() == 1 else Color(0.7, 0.7, 0.78, 0.85))
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_compass_strip.add_child(t)

	# Center marker — small amber bar.
	var marker := ColorRect.new()
	marker.color = Color(1.0, 0.85, 0.5)
	marker.size = Vector2(2, 18)
	marker.position = Vector2(COMPASS_WIDTH * 0.5 - 1.0, 6.0)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_panel.add_child(marker)


func _update_compass() -> void:
	if _compass_strip == null or _player == null or not is_instance_valid(_player):
		return
	var fwd: Vector3 = -(_player as Node3D).global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() == 0.0:
		return
	fwd = fwd.normalized()
	# Heading: 0 = north (-Z), 90 = east (+X), -90 = west (-X).
	var heading_rad: float = atan2(fwd.x, -fwd.z)
	var heading_deg: float = rad_to_deg(heading_rad)
	# Per-session bias plus weather-driven wobble — the unreliability beat.
	var wobble: float = float(GameManager.current_weather_def().get("compass_wobble", 0.0))
	var t_secs: float = Time.get_ticks_msec() / 1000.0
	var displayed: float = heading_deg + GameManager.compass_bias_deg + sin(t_secs * 0.7) * wobble
	_compass_strip.position.x = -displayed * COMPASS_PX_PER_DEG


func _build_boss_bar() -> void:
	_boss_panel = Panel.new()
	_boss_panel.anchor_left = 0.5
	_boss_panel.anchor_right = 0.5
	_boss_panel.offset_left = -240.0
	_boss_panel.offset_right = 240.0
	_boss_panel.offset_top = 18.0
	_boss_panel.offset_bottom = 46.0
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.04, 0.05, 0.65)
	sb.border_color = Color(0.85, 0.5, 0.6)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_boss_panel.add_theme_stylebox_override("panel", sb)
	$Root.add_child(_boss_panel)

	_boss_bar = ProgressBar.new()
	_boss_bar.anchor_right = 1.0
	_boss_bar.anchor_bottom = 1.0
	_boss_bar.offset_left = 8.0
	_boss_bar.offset_right = -8.0
	_boss_bar.offset_top = 4.0
	_boss_bar.offset_bottom = -4.0
	_boss_bar.modulate = Color(0.95, 0.45, 0.55)
	_boss_bar.show_percentage = false
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.add_child(_boss_bar)

	_boss_label = Label.new()
	_boss_label.anchor_right = 1.0
	_boss_label.anchor_bottom = 1.0
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_label.add_theme_font_size_override("font_size", 14)
	_boss_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_boss_label.text = "FROST TITAN"
	_boss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.add_child(_boss_label)


func _build_map_overlay() -> void:
	_map_overlay = Control.new()
	_map_overlay.name = "MapOverlay"
	_map_overlay.anchor_right = 1.0
	_map_overlay.anchor_bottom = 1.0
	_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_overlay.visible = false
	$Root.add_child(_map_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.68)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_overlay.add_child(dim)

	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -560.0
	panel.offset_right = 560.0
	panel.offset_top = -380.0
	panel.offset_bottom = 380.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.06, 0.94)
	sb.border_color = Color(0.7, 0.78, 0.82, 0.5)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", sb)
	_map_overlay.add_child(panel)

	var title := Label.new()
	title.text = "DEAD NORTH FIELD MAP"
	title.offset_left = 28.0
	title.offset_top = 18.0
	title.offset_right = 500.0
	title.offset_bottom = 50.0
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var hint := Label.new()
	hint.text = "M CLOSE"
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.offset_left = -160.0
	hint.offset_top = 24.0
	hint.offset_right = -28.0
	hint.offset_bottom = 48.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.78, 0.86, 0.9))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hint)

	_map_canvas = Control.new()
	_map_canvas.position = Vector2(70.0, 74.0)
	_map_canvas.size = Vector2(MAP_WIDTH, MAP_HEIGHT)
	_map_canvas.clip_contents = true
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_map_canvas)

	_add_map_rect("Snow", Vector2.ZERO, Vector2(MAP_WIDTH, MAP_HEIGHT), Color(0.88, 0.92, 0.92))
	_add_map_rect("Desert", Vector2.ZERO, Vector2(MAP_WIDTH * 0.275, MAP_HEIGHT), Color(0.86, 0.48, 0.18))
	_add_map_rect("Autumn", Vector2(0, 0), Vector2(MAP_WIDTH, MAP_HEIGHT * 0.225), Color(0.5, 0.26, 0.12))
	_add_map_rect("Plains", Vector2(0, MAP_HEIGHT * 0.75), Vector2(MAP_WIDTH, MAP_HEIGHT * 0.25), Color(0.28, 0.5, 0.25))
	_add_map_rect("Ocean", Vector2(MAP_WIDTH * 0.85, 0), Vector2(MAP_WIDTH * 0.15, MAP_HEIGHT), Color(0.08, 0.34, 0.72))
	for i in 9:
		var river := _add_map_rect("River", Vector2(180.0 + i * 78.0, 360.0 - i * 24.0), Vector2(160.0, 22.0), Color(0.05, 0.42, 0.82))
		river.rotation = -0.32
	_add_map_label("DESERT", Vector2(36, 300), Color(1.0, 0.9, 0.65))
	_add_map_label("SNOW", Vector2(430, 300), Color(0.1, 0.14, 0.18))
	_add_map_label("AUTUMN", Vector2(420, 72), Color(1.0, 0.84, 0.56))
	_add_map_label("PLAINS", Vector2(426, 535), Color(0.82, 1.0, 0.76))
	_add_map_label("OCEAN", Vector2(850, 300), Color(0.75, 0.92, 1.0))

	_map_objective_dot = _add_map_dot(Color(1.0, 0.24, 0.18), Vector2(14, 14))
	_map_player_dot = _add_map_dot(Color(0.25, 1.0, 0.45), Vector2(12, 12))
	_add_map_legend(panel)


func _add_map_rect(rect_name: String, pos: Vector2, rect_size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = rect_name
	rect.position = pos
	rect.size = rect_size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_canvas.add_child(rect)
	return rect


func _add_map_label(text: String, pos: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = Vector2(130, 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_canvas.add_child(label)


func _add_map_dot(color: Color, dot_size: Vector2) -> ColorRect:
	var dot := ColorRect.new()
	dot.size = dot_size
	dot.color = color
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_canvas.add_child(dot)
	return dot


func _add_map_legend(panel: Panel) -> void:
	var legend := Label.new()
	legend.text = "GREEN: YOU    RED: RADIO TOWER    WHITE: SNOW    ORANGE: DESERT    BLUE: WATER"
	legend.offset_left = 70.0
	legend.offset_top = 704.0
	legend.offset_right = 1050.0
	legend.offset_bottom = 732.0
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 14)
	legend.add_theme_color_override("font_color", Color(0.88, 0.92, 0.86))
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(legend)


# -- Signal handlers ------------------------------------------------------

func _on_warmth_changed(current: float, maximum: float) -> void:
	if _warmth_bar == null:
		return
	_warmth_bar.max_value = maximum
	_warmth_bar.value = current
	# Pulse red when freezing.
	if current / max(1.0, maximum) < 0.22:
		_warmth_bar.modulate = Color(1.0, 0.5, 0.5)
	else:
		_warmth_bar.modulate = Color(0.55, 0.85, 1.0)


func _on_trait_changed_hud(trait_def: Dictionary) -> void:
	if _trait_label == null or trait_def.size() == 0:
		return
	_trait_label.text = "TRAIT: %s — %s" % [String(trait_def.get("name", "")), String(trait_def.get("desc", ""))]


func _on_phase_changed_hud(phase_name: String) -> void:
	if _phase_label == null:
		return
	match phase_name:
		"explore":
			_phase_label.text = "PHASE: Explore"
			_phase_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
		"regroup":
			_refresh_regroup_phase_label()
			_phase_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		"defend":
			_phase_label.text = "PHASE: DEFEND THE SANCTUARY"
			_phase_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
		"boss":
			_phase_label.text = "PHASE: FROST TITAN"
			_phase_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.7))
		"won":
			_phase_label.text = "PHASE: Cleared"
			_phase_label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.55))


func _on_weather_changed_hud(weather_name: String) -> void:
	if _weather_label == null:
		return
	_weather_label.text = "WEATHER  %s" % weather_name.capitalize()


func _refresh_regroup_phase_label() -> void:
	if _phase_label == null or GameManager.phase != "regroup":
		return
	if GameManager.regroup_counting_down:
		var seconds_left: int = int(ceil(GameManager.regroup_time_left))
		_phase_label.text = "PHASE: REGROUP  %ds" % seconds_left
	else:
		_phase_label.text = "PHASE: REGROUP AT SANCTUARY"


func _on_boss_spawned() -> void:
	if _boss_panel:
		_boss_panel.visible = true


func _on_boss_health_changed(current: float, maximum: float) -> void:
	if _boss_bar == null:
		return
	_boss_bar.max_value = maximum
	_boss_bar.value = current


func _on_boss_defeated() -> void:
	if _boss_panel:
		_boss_panel.visible = false


func _on_weapon_changed(weapon_name: String) -> void:
	if _weapon_label:
		_weapon_label.text = "WEAPON: %s" % weapon_name


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current


func _on_kills_changed(n: int) -> void:
	kills_label.text = "KILLS  %d / %d" % [n, GameManager.KILLS_TO_BOSS]


func _on_player_died() -> void:
	center_label.text = "YOU DIED\n\nPress R to restart"
	center_label.visible = true
	crosshair.visible = false


func _on_game_won() -> void:
	center_label.text = "AREA CLEARED\n\nPress R to restart"
	center_label.visible = true
	crosshair.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		if _map_overlay:
			_map_overlay.visible = not _map_overlay.visible
			crosshair.visible = not _map_overlay.visible and not GameManager.game_over
			_refresh_map_marker()
		return
	if event.is_action_pressed("restart") and GameManager.game_over:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_tree().reload_current_scene()
