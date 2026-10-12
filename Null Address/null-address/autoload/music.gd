extends Node


##     Music.play("menu")        # crossfade to the menu bed
##     Music.play("hub")         # crossfade to the act 0 bed
##     Music.stop()              # fade out
##
## Screens can also just set `track` in their own _ready(); see the TRACKS
## table below for the ids.

signal track_changed(id: String)

## Music beds, by id. Add a row here to add a track — nothing else needs
## touching.
##
## Godot imports .mp3 as AudioStreamMP3, which loops by default.
const TRACKS := {
	"menu": {
		"path": "res://Assets/Music/Park Bird & Reponix - Are You Lost_ (slowed reverb).mp3",
		"volume_db": -8.0,
	},
	# The track the hub switches to once the ACT door has risen. Referenced by
	# UID because the filename has spaces and brackets in it.
	"ungood": {
		"path": "res://Assets/Music/07 - ungood night - un-good Night.wav",
		"volume_db": -9.0,
	},

	"hub": {
		"path": "res://Assets/Music/Dreamcorp - Nevermind Everything's Ok [Extended].mp3",
		"volume_db": -10.0,
	},
}

## Optional per-act overrides, keyed by act id. Anything not listed here falls
## back to "hub", so the whole game runs on the Dreamcorp bed and only the UI
## screens differ.
##
##     Music.play_for_act("office", "THE OFFICE FLOOR")
##
## Add a row here when an act deserves its own track.
const ACT_TRACKS := {
	# "tunnel": "tunnel_bed",
}

## The bed everything in-game uses when an act has no override.
const DEFAULT_ACT_TRACK := "hub"
## The bed every UI screen uses (main menu, settings, act select).
const MENU_TRACK := "menu"

## Crossfade time in seconds. Long and slow suits the mood.
@export var fade_seconds := 2.5
## Master music level, folded in on top of each track's own volume_db.
@export var master_db := 0.0
## Start silent and fade in the first track.
@export var fade_in_on_start := true

var current_id := ""
## Volume offset requested while a crossfade was still running.
var _ramp_pending := 0.0
var _current: AudioStreamPlayer
var _incoming: AudioStreamPlayer
var _fade_tween: Tween


func _ready() -> void:
	# Two players so one can fade in while the other fades out.
	_current = _make_player("Current")
	_incoming = _make_player("Incoming")
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	# Re-assert the ramp every frame. It is a single assignment, and it means a
	# crossfade finishing, a track change or anything else cannot silently drop
	# the volume offset.
	_apply_ramp()


func _make_player(nm: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = nm
	p.bus = "Master"
	p.volume_db = -80.0
	add_child(p)
	return p


## Crossfade to a track id from TRACKS. No-op if it is already playing.
func play(id: String) -> void:
	if id == current_id and _current.playing:
		return
	if not TRACKS.has(id):
		push_warning("Music: no track '%s' (have: %s)"
			% [id, ", ".join(TRACKS.keys())])
		return

	var stream: AudioStream = load(TRACKS[id]["path"])
	if stream == null:
		push_warning("Music: could not load '%s'" % TRACKS[id]["path"])
		return

	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true

	var target_db: float = float(TRACKS[id]["volume_db"]) + master_db

	# Hand the old current over to the incoming slot so it can fade out.
	var old := _current
	_current = _incoming
	_incoming = old

	_current.stream = stream
	_current.volume_db = -80.0 if fade_in_on_start else target_db
	_current.play()

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(_current, "volume_db", target_db, fade_seconds)

	if _incoming.playing:
		_fade_tween.tween_property(_incoming, "volume_db", -80.0, fade_seconds)
		_fade_tween.chain().tween_callback(_incoming.stop)

	current_id = id
	track_changed.emit(id)

	# a ramp requested mid-fade gets applied the moment the fade lands
	if _fade_tween != null:
		_fade_tween.chain().tween_callback(_apply_ramp)


## Play the right bed for an act. Falls back to the default in-game track, so
## a new act never plays nothing.
func play_for_act(act_id: String, _title: String = "") -> void:
	var id: String = ACT_TRACKS.get(act_id, DEFAULT_ACT_TRACK)
	play(id)


## Play the UI bed. Used by the main menu, settings and act select.
func play_menu() -> void:
	play(MENU_TRACK)


## Switch to the "ungood night" bed and hand back a handle the caller can use to
## drive the volume. Used when the ACT door rises: the music changes and then
## swells as the map falls apart.
func play_ungood() -> void:
	play("ungood")


## Set the live music volume as an offset from the current track's own level.
## `extra_db` of 0 is the track's normal volume; +6 is twice as loud to the ear.
##
## A crossfade tween is left to finish rather than killed: killing it mid-fade
## leaves the volume wherever the tween had reached, and the ramp then reads as
## no change. The ramp is re-applied every frame by its caller, so waiting one
## fade is invisible.
func set_ramp(extra_db: float) -> void:
	_ramp_pending = extra_db
	_apply_ramp()


## Push `_ramp_pending` onto the live player. No-op while a crossfade is still
## animating the volume, because the tween would immediately overwrite it.
func _apply_ramp() -> void:
	if _current == null or not _current.playing:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		return
	var base := -9.0
	if TRACKS.has(current_id):
		base = float(TRACKS[current_id]["volume_db"])
	_current.volume_db = base + master_db + _ramp_pending


## The volume offset currently applied, in dB.
func ramp_db() -> float:
	# report the REQUESTED offset, not the live volume, so it is correct even
	# while a crossfade is still settling
	return _ramp_pending


## Fade out whatever is playing and stop.
func stop() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	for p in [_current, _incoming]:
		if p.playing:
			_fade_tween.tween_property(p, "volume_db", -80.0, fade_seconds)
	_fade_tween.chain().tween_callback(func() -> void:
		_current.stop()
		_incoming.stop()
	)
	current_id = ""


## Is a given track the one currently playing?
func is_playing(id: String) -> bool:
	return current_id == id and _current != null and _current.playing
