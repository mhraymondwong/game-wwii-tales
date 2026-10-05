extends Node
## Original low-string march. Synthesized (not a copied tune); loops for the whole session.

const STREAM_PATH := "res://assets/audio/front_march.wav"
const VOLUME_DB := -11.0

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BgmPlayer"
	_player.volume_db = VOLUME_DB
	add_child(_player)
	var raw := load(STREAM_PATH) as AudioStreamWAV
	if raw == null:
		push_error("BGM missing: %s" % STREAM_PATH)
		return
	# Imported WAV defaults to loop disabled. Duplicate so loop_end can be set.
	var stream := raw.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	var frames := int(round(stream.get_length() * float(stream.mix_rate)))
	if frames < 2:
		var channels := 2 if stream.stereo else 1
		var bps := 2
		frames = int(stream.data.size() / (bps * channels))
	stream.loop_end = maxi(frames, 2)
	_player.stream = stream
	_player.play()
	print("BGM loop=", stream.loop_mode, " frames=", stream.loop_end, " sec=", stream.get_length(), " db=", VOLUME_DB)
