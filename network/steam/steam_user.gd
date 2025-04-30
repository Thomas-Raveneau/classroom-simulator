class_name SteamUser

signal on_friends_refreshed
signal on_friend_lobby_update()

enum Status {
	OFFLINE,
	ONLINE,
	BUSY,
	AWAY_LONG,
	SNOOZE,
	TRADING,
	LOOKING_TO_PLAY
}

enum Relationship {
	NONE,
	BLOCKED,
	REQUESTER,
	FRIEND,
	REQUESTED,
	IGNORING,
	IGNORED
}

var id: int = 0
var name: String = ""
var status: Status = Status.OFFLINE
var is_host: bool = false
var lobby: SteamFriendLobby
var friends: Array[SteamUser] = []

func _init(
	_id: int, 
	_name: String = "", 
	_lobby: SteamFriendLobby = null, 
	_is_host: bool = false
) -> void:
	id = _id
	name = _name
	is_host = _is_host
	lobby = _lobby
	if name.is_empty():
		name = Steam.getFriendPersonaName(id)
	status = Steam.getFriendPersonaState(id) as Status
	Steam.persona_state_change.connect(_on_friend_update)
	Steam.lobby_data_update.connect(_on_friend_lobby_update)

func _to_string() -> String:
	return str({ "id": id, "name": name, "is_host": is_host})

func filter_friend(
	friend: Dictionary,
	game_info: Dictionary,
	is_playing_filter: bool,
	status_filters: Array[Status],
	relationship_filters: Array[Relationship]
) -> bool:
	if status_filters.size() > 0 && !status_filters.has(friend.status):
		return false
	var relationship: Relationship = Steam.getFriendRelationship(friend.id) as Relationship
	if relationship_filters.size() > 0 && !relationship_filters.has(relationship):
		return false
	if is_playing_filter:
		if !game_info || game_info.id !=  NetworkManager.steam.app_id:
			return false
	return true

func format_friend(friend: Dictionary, game_info: Dictionary) -> SteamUser:
	if (!game_info || game_info.lobby == 0):
		return SteamUser.new(friend.id, friend.name)
	Steam.requestLobbyData(game_info.lobby)
	var friend_lobby: SteamFriendLobby = SteamFriendLobby.new(game_info.lobby)
	return SteamUser.new(friend.id, friend.name, friend_lobby)

func refresh_friends(
	is_playing_filter: bool = true,
	status_filters: Array[Status] = [
		Status.ONLINE, 
		Status.BUSY,
		Status.AWAY_LONG,
		Status.TRADING,
		Status.SNOOZE,
		Status.LOOKING_TO_PLAY,
	],
	relationship_filters: Array[Relationship] = [Relationship.FRIEND]
) -> void:
	var new_friends: Array[SteamUser] = []
	for friend: Dictionary in Steam.getUserSteamFriends():
		var game_info: Dictionary = Steam.getFriendGamePlayed(friend.id)
		var filtered: bool = filter_friend(
			friend, 
			game_info,
			is_playing_filter, 
			status_filters, 
			relationship_filters
		)
		if filtered:
			new_friends.append(format_friend(friend, game_info))
	friends.assign(new_friends)
	on_friends_refreshed.emit()

func get_friends_lobbies() -> Array[SteamFriendLobby]:
	var unique_lobbies: Dictionary = {}
	var friends_lobbies: Array[SteamFriendLobby] = [] 
	for friend in friends:
		if !friend.lobby || friend.lobby.id == 0:
			continue
		if unique_lobbies.get(friend.lobby.id): 
			continue
		unique_lobbies[friend.lobby.id] = friend.lobby.name
		friends_lobbies.append(friend.lobby)
	return friends_lobbies

func _on_friend_update(_user_id: int, _flag: Steam.PersonaChange) -> void:
	refresh_friends()

func _on_friend_lobby_update(success: int, lobby_id: int, _user_id: int) -> void:
	if !success:
		return
	var friend_lobby_name: String = Steam.getLobbyData(lobby_id, "name")
	for friend in friends:
		if !friend.lobby || friend.lobby.id != lobby_id:
			continue
		friend.lobby.name = friend_lobby_name
	on_friend_lobby_update.emit()
