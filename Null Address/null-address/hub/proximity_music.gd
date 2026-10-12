extends Area3D

## Proximity music trigger.
##
## Plays a track when the player comes within range, and fades it back out when
## they leave. Used on the HUB doorway to bring in "ungood night" as you
## approach.
##
## It does NOT use the Music autoload's single-bed crossfade, because that would
## replace the level's own music. Instead it owns a dedicated AudioStreamPlayer
## so the proximity cue layers OVER the bed and can come and go freely.

@export_group("Track")
## Path to the audio file to play on approach.
@export_file("*.ogg", "*.mp3", "*.wav") var track := ""
## Volume at full proximity, in dB.
@export var volume_db := -6.0
## Should the track loop while the player is near?
@export var loop := true

@export_group("Range")
## Start the track when the player is this close, in metres.
@export var trigger_radius := 9.0
## How long the fade in / out takes.
@export var fade_seconds := 1.6
## Once triggered, keep playing even if the player leaves. Good for a one-shot
## sting that should not restart.
@export var one_shot := false

@export_group("Approach")
## Ramp the volume UP as the player closes the distance, so it pulls them in.
@export var ramp_with_distance := true
## Volume when the player is at the far edge of the range, in dB.
@export var volume_far_db := -26.0
## Distance at which the ramp reaches full volume.
@export var full_volume_radius := 2.5
## Seconds to swell once the player is inside `full_volume_radius`.
@export var swell_seconds := 2.2
## Peak volume during the swell, in dB. Positive values clip - keep it modest.
@export var swell_peak_db := 1.5

@export_group("Glitch")
## Restart the track from a random offset when re-entering, so it never sounds
## like the same loop twice.
@export var random_start := true

var _player: AudioStreamPlayer
var _stream: AudioStream
var _inside := false
var _fired := false
var _tween: Tween
var _swelling := false
var _player_body: Node3D


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

	_player = AudioStreamPlayer.new()
	_player.name = "ProximityMusic"
	_player.volume_db = -80.0
	add_child(_player)

	if track != "":
		_stream = load(track)
		if _stream == null:
			push_warning("ProximityMusic: could not load '%s'" % track)
		elif _stream is AudioStreamMP3 and loop:
			(_stream as AudioStreamMP3).loop = true
		elif _stream is AudioStreamOggVorbis and loop:
			(_stream as AudioStreamOggVorbis).loop = true
		elif _stream is AudioStreamWAV and loop:
			(_stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


func _is_player(body: Node) -> bool:
	# the player is the only CharacterBody3D in the hub
	return body is CharacterBody3D


func _on_enter(body: Node3D) -> void:
	if not _is_player(body):
		return
	_inside = true
	_player_body = body
	if _fired and one_shot:
		return
	_start()


## Called every frame to keep the volume matched to the distance.
func _process(_delta: float) -> void:
	if not ramp_with_distance or not _player.playing or _swelling:
		return
	if _player_body == null or not is_instance_valid(_player_body):
		return
	var d := global_position.distance_to(_player_body.global_position)
	var t := clampf(
		inverse_lerp(trigger_radius, full_volume_radius, d), 0.0, 1.0)
	_player.volume_db = lerpf(volume_far_db, volume_db, t)


func _on_exit(body: Node3D) -> void:
	if not _is_player(body):
		return
	_inside = false
	if one_shot:
		return
	_stop()


func _start() -> void:
	if _stream == null or _player == null:
		return
	_fired = true
	if _player.playing:
		return
	_player.stream = _stream
	if random_start and _stream.get_length() > 1.0:
		_player.play(_rng_offset())
	else:
		_player.play()
	if ramp_with_distance:
		_player.volume_db = volume_far_db
	else:
		_fade_to(volume_db)


func _rng_offset() -> float:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randf_range(0.0, maxf(_stream.get_length() - 0.5, 0.0))


func _stop() -> void:
	if _player == null or not _player.playing:
		return
	_fade_to(-80.0)
	if _tween != null:
		_tween.chain().tween_callback(_player.stop)


func _fade_to(target_db: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", target_db, fade_seconds)


## Swell to peak volume over `swell_seconds`. Used when the player commits and
## steps into the door - the sound closes over them.
func swell() -> void:
	if _player == null:
		return
	_swelling = true
	if not _player.playing:
		_player.stream = _stream
		_player.play()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_tween.tween_property(_player, "volume_db", swell_peak_db, swell_seconds)


## Stop immediately and stay stopped. Used when the music bed takes over the
## same track, so the two do not play over each other.
func silence() -> void:
	one_shot = true
	_swelling = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _player != null:
		_player.stop()
		_player.volume_db = -80.0
	set_process(false)


## Is the cue currently audible?
func is_playing() -> bool:
	return _player != null and _player.playing and _player.volume_db > -60.0
