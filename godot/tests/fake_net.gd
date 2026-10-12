extends SteamNet
## Stand-in for Steam in tests: two of these pass messages to each other directly.

var peer: SteamNet


func _ready() -> void:
	available = true


func _process(_delta: float) -> void:
	pass


func my_name() -> String:
	return "Host" if is_host else "Guest"


func host_game() -> void:
	lobby_id = 1
	is_host = true
	lobby_entered.emit(1, true)


func join(_id: int) -> void:
	lobby_id = 1
	is_host = false
	lobby_entered.emit(1, false)
	peer.friend_joined.emit("Guest")


func send(data: Dictionary) -> void:
	# Round-trip through JSON like the real lobby chat does.
	var copy = JSON.parse_string(JSON.stringify(data))
	peer.call_deferred("emit_signal", "message_received", copy)


func member_count() -> int:
	return 2 if lobby_id != 0 and peer.lobby_id != 0 else (1 if lobby_id != 0 else 0)


func friend_name() -> String:
	return "Guest" if is_host else "Host"


func leave() -> void:
	lobby_id = 0


func find_games() -> void:
	lobbies_found.emit([])


func set_open(_open: bool) -> void:
	pass
