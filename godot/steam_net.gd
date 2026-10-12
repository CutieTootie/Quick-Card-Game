class_name SteamNet
extends Node
## Steam online play through GodotSteam (https://godotsteam.com), using Steam lobbies.
## Moves are sent as small JSON messages in the lobby chat, which is plenty for a
## turn-based game and needs no networking setup.
##
## Uses Spacewar's app ID (480), Valve's free test app, until the game has its own.
## The Steam singleton is looked up at runtime, so the game still runs without
## GodotSteam installed; the Steam option just stays hidden.

signal lobby_entered(lobby_id: int, is_host: bool)
signal lobby_left(reason: String)
signal lobbies_found(lobbies: Array) # [{id, name}]
signal message_received(data: Dictionary)
signal friend_joined(name: String)
signal friend_left(name: String)
signal problem(text: String)

const APP_ID := 480 # Spacewar. Replace with your own app ID when you have one.
const GAME_KEY := "quick-card-game" # Spacewar is shared by many test games, so tag our lobbies
const LOBBY_TYPE_FRIENDS_ONLY := 1
const LOBBY_TYPE_PUBLIC := 2
const LOBBY_COMPARISON_EQUAL := 0
const LOBBY_DISTANCE_WORLDWIDE := 3
const CHAT_ENTERED := 1
const CHAT_LEFT := 2
const CHAT_DISCONNECTED := 4
const RESULT_OK := 1

var steam: Object = null
var available := false
var unavailable_reason := ""
var my_id := 0
var lobby_id := 0
var is_host := false


func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		unavailable_reason = "Steam play needs the GodotSteam add-on. See README.md in the godot folder."
		return
	# Tell Steam which app this is before it starts (steam_appid.txt says the same).
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))
	steam = Engine.get_singleton("Steam")
	var result = steam.steamInitEx()
	var status := -1
	if typeof(result) == TYPE_DICTIONARY:
		status = int(result.get("status", -1))
	if status != 0 and not steam.isSteamRunning():
		unavailable_reason = "Steam isn't running. Open Steam, sign in, and restart the game."
		if typeof(result) == TYPE_DICTIONARY and result.has("verbal"):
			unavailable_reason += " (" + str(result.verbal) + ")"
		steam = null
		return
	available = true
	my_id = steam.getSteamID()
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.lobby_match_list.connect(_on_lobby_match_list)
	steam.lobby_message.connect(_on_lobby_message)
	steam.lobby_chat_update.connect(_on_lobby_chat_update)
	steam.join_requested.connect(_on_join_requested)


func _process(_delta: float) -> void:
	if steam:
		steam.run_callbacks()


func my_name() -> String:
	return steam.getPersonaName() if steam else "You"


func host_game() -> void:
	if not available:
		return
	leave()
	steam.createLobby(LOBBY_TYPE_PUBLIC, 2)


func find_games() -> void:
	if not available:
		return
	steam.addRequestLobbyListDistanceFilter(LOBBY_DISTANCE_WORLDWIDE)
	steam.addRequestLobbyListStringFilter("game", GAME_KEY, LOBBY_COMPARISON_EQUAL)
	steam.addRequestLobbyListStringFilter("open", "1", LOBBY_COMPARISON_EQUAL)
	steam.requestLobbyList()


func join(id: int) -> void:
	if not available:
		return
	leave()
	steam.joinLobby(id)


func invite_friend() -> void:
	if lobby_id != 0:
		steam.activateGameOverlayInviteDialog(lobby_id)


func leave() -> void:
	if steam and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	lobby_id = 0
	is_host = false


func send(data: Dictionary) -> void:
	if lobby_id == 0:
		return
	if not steam.sendLobbyChatMsg(lobby_id, JSON.stringify(data)):
		problem.emit("Couldn't send your move to Steam. Check your connection.")


func set_open(open: bool) -> void:
	if is_host and lobby_id != 0:
		steam.setLobbyData(lobby_id, "open", "1" if open else "0")


func friend_name() -> String:
	if lobby_id == 0:
		return "Friend"
	for i in steam.getNumLobbyMembers(lobby_id):
		var member: int = steam.getLobbyMemberByIndex(lobby_id, i)
		if member != my_id:
			return steam.getFriendPersonaName(member)
	return "Friend"


func member_count() -> int:
	return steam.getNumLobbyMembers(lobby_id) if lobby_id != 0 else 0


# ---- Steam callbacks ----

func _on_lobby_created(result: int, id: int) -> void:
	if result != RESULT_OK:
		problem.emit("Steam couldn't create a game (error %d). Try again." % result)
		return
	lobby_id = id
	is_host = true
	steam.setLobbyData(id, "game", GAME_KEY)
	steam.setLobbyData(id, "name", my_name())
	steam.setLobbyData(id, "open", "1")
	lobby_entered.emit(id, true)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != RESULT_OK:
		problem.emit("Couldn't join that game. It may be full or closed.")
		return
	if is_host and id == lobby_id:
		return # the host also gets this when creating
	lobby_id = id
	is_host = steam.getLobbyOwner(id) == my_id
	lobby_entered.emit(id, is_host)


func _on_lobby_match_list(lobbies: Array) -> void:
	var out := []
	for id in lobbies:
		if steam.getNumLobbyMembers(id) == 1:
			out.append({"id": id, "name": steam.getLobbyData(id, "name")})
	lobbies_found.emit(out)


func _on_lobby_message(id: int, user: int, message: String, _chat_type: int) -> void:
	if id != lobby_id or user == my_id:
		return
	var data = JSON.parse_string(message)
	if typeof(data) == TYPE_DICTIONARY:
		message_received.emit(data)


func _on_lobby_chat_update(id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if id != lobby_id or changed_id == my_id:
		return
	var who: String = steam.getFriendPersonaName(changed_id)
	if chat_state & CHAT_ENTERED:
		friend_joined.emit(who)
	elif chat_state & (CHAT_LEFT | CHAT_DISCONNECTED):
		friend_left.emit(who)


func _on_join_requested(id: int, _friend_id: int) -> void:
	# A friend invited us through the Steam overlay.
	join(id)
