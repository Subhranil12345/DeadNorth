extends Control

const MAIN_SCENE: String = "res://scenes/main.tscn"
const DEFAULT_PORT: int = 27015

var _ip_input: LineEdit
var _port_input: LineEdit
var _status_label: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_build_menu()
	MultiplayerManager.status_changed.connect(_on_status_changed)


func _build_menu() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.09)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var wrap := CenterContainer.new()
	wrap.anchor_right = 1.0
	wrap.anchor_bottom = 1.0
	add_child(wrap)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(520, 520)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.12, 0.15, 0.16, 0.92)
	psb.border_color = Color(0.62, 0.74, 0.7)
	psb.border_width_left = 2
	psb.border_width_right = 2
	psb.border_width_top = 2
	psb.border_width_bottom = 2
	psb.corner_radius_top_left = 8
	psb.corner_radius_top_right = 8
	psb.corner_radius_bottom_left = 8
	psb.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", psb)
	wrap.add_child(panel)

	var box := VBoxContainer.new()
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 36.0
	box.offset_top = 32.0
	box.offset_right = -36.0
	box.offset_bottom = -32.0
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "DEAD NORTH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.9, 0.96, 0.95))
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Survive the storm alone or over LAN"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.68, 0.78, 0.78))
	box.add_child(subtitle)

	box.add_child(_spacer(10))
	box.add_child(_button("Single Player", _start_singleplayer))
	box.add_child(_button("Host Multiplayer", _host_multiplayer))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "Host IP"
	_ip_input.text = "127.0.0.1"
	_ip_input.custom_minimum_size = Vector2(260, 42)
	row.add_child(_ip_input)

	_port_input = LineEdit.new()
	_port_input.placeholder_text = "Port"
	_port_input.text = str(DEFAULT_PORT)
	_port_input.custom_minimum_size = Vector2(110, 42)
	row.add_child(_port_input)

	box.add_child(_button("Join Multiplayer", _join_multiplayer))
	box.add_child(_button("Quit", _quit_game))

	box.add_child(_spacer(6))
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.42))
	box.add_child(_status_label)


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(callback)
	return b


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _start_singleplayer() -> void:
	MultiplayerManager.start_singleplayer()
	get_tree().change_scene_to_file(MAIN_SCENE)


func _host_multiplayer() -> void:
	if MultiplayerManager.host_game(_port()):
		get_tree().change_scene_to_file(MAIN_SCENE)


func _join_multiplayer() -> void:
	if MultiplayerManager.join_game(_ip_input.text, _port()):
		get_tree().change_scene_to_file(MAIN_SCENE)


func _quit_game() -> void:
	get_tree().quit()


func _port() -> int:
	var port := _port_input.text.to_int()
	if port <= 0:
		return DEFAULT_PORT
	return port


func _on_status_changed(text: String) -> void:
	if _status_label:
		_status_label.text = text
