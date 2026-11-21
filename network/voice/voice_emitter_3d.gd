class_name VoiceEmitter3D
extends AudioStreamPlayer3D
## Where the voice of a player comes out of in the game. Add one to the character:
## with `LobbyConfig.voice_range` set to PROXIMITY, the voice of the player who has
## authority over the character is played here, and fades with distance as set on
## this node (`max_distance`, `unit_size`, `attenuation_model`).
##
## Unused in EVERYONE range: the node can stay in the scene.

var _voice: VoiceChat

func _ready() -> void:
	_voice = VoiceChat.find_for(self)
	if _voice != null:
		_voice.register_emitter(get_multiplayer_authority(), self)

func _exit_tree() -> void:
	if _voice != null:
		_voice.unregister_emitter(get_multiplayer_authority(), self)
		_voice = null
