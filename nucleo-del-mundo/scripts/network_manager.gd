# =============================================================
# network_manager.gd — Autoload "Net"
# Gestiona la conexión multijugador (modelo host-listen).
# GDD §10: el host actúa como servidor con autoridad total.
# =============================================================
extends Node

const PORT := 7777
const MAX_PLAYERS := 4

signal connection_succeeded
signal connection_failed
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int): player_connected.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int): player_disconnected.emit(id))
	multiplayer.connected_to_server.connect(func(): connection_succeeded.emit())
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Crea el servidor (el jugador que hospeda la partida).
func host_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## Se conecta a un host existente por IP (misma red WiFi).
func join_game(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


## IP local del host para compartir con otros jugadores.
func local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.count(".") == 3 and not addr.begins_with("127."):
			return addr
	return "127.0.0.1"


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()
