class_name SteamLobby
extends Node

signal on_created
signal on_joined
signal on_left
signal on_invite_received(user: SteamUser, lobby_id: int)

var id: int = 0
var lobby_name: String = ""
var users_count: int = 0

func _ready() -> void:
	Steam.lobby_invite.connect(_on_invite_received)
	Steam.lobby_joined.connect(_on_joined)
	NetworkManager.peer.lobby_created.connect(_on_created)
	NetworkManager.peer.lobby_data_update.connect(_on_lobby_update)
	auto_join()

func create() -> void:
	if id != 0:
		return
	NetworkManager.local_user.is_host = true
	NetworkManager.peer.create_lobby(
		SteamMultiplayerPeer.LOBBY_TYPE_FRIENDS_ONLY, 
		GameSettings.MAX_PLAYERS
	)

func join(lobby_id: int) -> void:
	NetworkManager.peer.connect_lobby(lobby_id)

func auto_join() -> void:
	var args: Array = OS.get_cmdline_args()
	if args.size() == 0: 
		return
	if args[0] != "+connect_lobby" || int(args[1]) == 0:
		return
	join(int(args[1]))

func leave() -> void:
	if id == 0:
		return
	#if NetworkManager.local_user.is_host && NetworkManager.lobby.players.size() > 1:
		#var new_host: SteamUser
		#for member_id in members.keys():
			#if member_id ==  NetworkManager.local_user.steam.id:
				#continue
			#new_host = members[member_id]
			#break
		#Steam.setLobbyOwner(id, new_host.id)
	#for player_id in NetworkManager.lobby.players.keys():
		#var player: NetworkPlayer = NetworkManager.lobby.players[player_id]
		#NetworkManager.steam.network.close_session(player.steam)
	Steam.leaveLobby(id)
	id = 0
	users_count = 0
	lobby_name = ""
	on_left.emit()

func invite(user: SteamUser) -> void:
	var success: bool = Steam.inviteUserToLobby(id, user.id)
	if (!success):
		printerr("Invitation was not successful")

func set_private(private: bool) -> void:
	if !NetworkManager.local_user.is_host:
		return
	if private:
		Steam.setLobbyType(id, Steam.LOBBY_TYPE_PRIVATE)
	else:
		Steam.setLobbyType(id, Steam.LOBBY_TYPE_FRIENDS_ONLY)

func get_host_id() -> int:
	return Steam.getLobbyOwner(id)

func _on_created(result: Steam.Result, lobby_id: int) -> void:
	if result != Steam.RESULT_OK:
		return
	id = lobby_id
	lobby_name = "%s's lobby" % NetworkManager.local_user.steam.name
	users_count = Steam.getNumLobbyMembers(id)
	Steam.setLobbyData(id, "name", lobby_name)
	on_created.emit()

func _on_joined(lobby_id: int, _permissions: int, _locked: bool, response: Steam.ChatRoomEnterResponse) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS || id != 0:
		return
	id = lobby_id
	users_count = Steam.getNumLobbyMembers(id)
	on_joined.emit()

func _on_invite_received(user_id: int, lobby_id: int, _game_id: int) -> void:
	var user: SteamUser = SteamUser.new(user_id)
	on_invite_received.emit(user, lobby_id)

func _on_lobby_update(success: int, _lobby_id: int, _user_id: int) -> void:
	if !success || id == 0:
		return
	var owner_id: int = Steam.getLobbyOwner(id)
	if owner_id == NetworkManager.local_user.steam.id && !NetworkManager.local_user.is_host:
		NetworkManager.local_user.is_host = true
		lobby_name = "%s's lobby" %  NetworkManager.local_user.steam.name
		Steam.setLobbyData(id, "name", lobby_name)
		return
	lobby_name = Steam.getLobbyData(id, "name")
	users_count = Steam.getNumLobbyMembers(id)
