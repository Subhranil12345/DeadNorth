extends Node

signal status_changed(text: String)
signal remote_player_state(peer_id: int, position: Vector3, rotation_y: float)
signal remote_player_left(peer_id: int)

const MAX_PLAYERS: int = 4
const DEFAULT_PORT: int = 27015
const SEND_INTERVAL: float = 0.06

var enabled: bool = false
var is_host: bool = false
var mode: String = "single"

var _peer: ENetMultiplayerPeer = null
var _send_timer: float = 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: _set_status("Connected to host."))
	multiplayer.connection_failed.connect(func() -> void: _set_status("Connection failed."))
	multiplayer.server_disconnected.connect(func() -> void: _set_status("Disconnected from host."))


func start_singleplayer() -> void:
	_close_peer()
	enabled = false
	is_host = false
	mode = "single"
	_set_status("Single player")


func host_game(port: int = DEFAULT_PORT) -> bool:
	_close_peer()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		_set_status("Could not host on port %d." % port)
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	enabled = true
	is_host = true
	mode = "host"
	_set_status("Hosting on port %d." % port)
	return true


func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	_close_peer()
	var clean_address := address.strip_edges()
	if clean_address == "":
		clean_address = "127.0.0.1"
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(clean_address, port)
	if err != OK:
		_set_status("Could not join %s:%d." % [clean_address, port])
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	enabled = true
	is_host = false
	mode = "client"
	_set_status("Joining %s:%d..." % [clean_address, port])
	return true


func is_multiplayer_active() -> bool:
	return enabled and multiplayer.multiplayer_peer != null


func _process(delta: float) -> void:
	if not is_multiplayer_active():
		return
	if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = SEND_INTERVAL

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	if multiplayer.is_server():
		rpc("_client_receive_player_state", multiplayer.get_unique_id(), player.global_position, player.rotation.y)
	else:
		rpc_id(1, "_server_receive_player_state", player.global_position, player.rotation.y)


@rpc("any_peer", "unreliable")
func _server_receive_player_state(remote_position: Vector3, rotation_y: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	remote_player_state.emit(sender, remote_position, rotation_y)
	rpc("_client_receive_player_state", sender, remote_position, rotation_y)


@rpc("authority", "unreliable")
func _client_receive_player_state(peer_id: int, remote_position: Vector3, rotation_y: float) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	remote_player_state.emit(peer_id, remote_position, rotation_y)


func _on_peer_connected(peer_id: int) -> void:
	_set_status("Player %d joined." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	remote_player_left.emit(peer_id)
	_set_status("Player %d left." % peer_id)


func _close_peer() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null


func _set_status(text: String) -> void:
	status_changed.emit(text)
