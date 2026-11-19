extends GutTest

func test_host_is_peer_one() -> void:
	assert_true(LobbyMember.new(1, 10, "Host").is_host)
	assert_false(LobbyMember.new(2, 11, "Client").is_host)

func test_ready_flag_reads_member_data() -> void:
	var member: LobbyMember = LobbyMember.new(2, 11, "Client")
	assert_false(member.is_ready)
	member.data[LobbyMember.READY_KEY] = true
	assert_true(member.is_ready)

func test_dictionary_round_trip() -> void:
	var member: LobbyMember = LobbyMember.new(7, 123456789, "Ada")
	member.data["team"] = 2
	var copy: LobbyMember = LobbyMember.from_dict(member.to_dict())
	assert_eq(copy.peer_id, 7)
	assert_eq(copy.user_id, 123456789)
	assert_eq(copy.name, "Ada")
	assert_eq(copy.data.get("team"), 2)

func test_invalid_dictionary_is_rejected() -> void:
	assert_null(LobbyMember.from_dict({}))
	assert_null(LobbyMember.from_dict({ "peer_id": "1", "user_id": 1, "name": "x" }))
	assert_null(LobbyMember.from_dict({ "peer_id": 1, "user_id": 1, "name": 5 }))
	assert_null(LobbyMember.from_dict({ "peer_id": 1, "user_id": 1, "name": "x", "data": [] }))
