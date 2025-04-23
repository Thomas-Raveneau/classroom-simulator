class_name SteamUser

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

func _init(_id: int, _name: String, _is_host: bool = false) -> void:
	id = _id
	name = _name
	is_host = _is_host
	status = Steam.getFriendPersonaState(id) as Status

func _to_string() -> String:
	return str({"id": id, "name": name, "status": status})

func get_friends(
	status_filters: Array[Status] = [Status.ONLINE, Status.LOOKING_TO_PLAY],
	relationship_filters: Array[Relationship] = [Relationship.FRIEND]
) -> Array[SteamUser]:
	var filtered_friends: Array = Steam.getUserSteamFriends().filter(
		func (friend: Dictionary) -> bool:
			if friend.name == "[unknown]":
				return false
			if status_filters.size() > 0 && !status_filters.has(friend.status):
				return false
			var relationship: Relationship = Steam.getFriendRelationship(friend.id) as Relationship
			if relationship_filters.size() > 0 && !relationship_filters.has(relationship):
				return false
			return true
	).map(
		func (friend: Dictionary) -> SteamUser:
			return SteamUser.new(friend.id, friend.name)
	)
	var friends: Array[SteamUser]
	friends.assign(filtered_friends)
	return friends
