extends ColorRect

## Filming controller for the VHS overlay.
##
## Two jobs:
##   1. Toggle the effect on/off - the tape look only appears while the player
##      is holding the camera up and filming.
##   2. Ramp the intensity the deeper the player gets, so the footage degrades
##      as the game goes on.
##
## It drives the shader's own uniforms - it does not modify the shader. Tune
## everything from the exported values below.

@export_group("Toggle")
## Input action that starts/stops filming. Add this action in
## Project Settings > Input Map (default binding: F).
@export var film_action := "film"
## Start with the camera already up.
##
## This defaults to TRUE: Null Address is found-footage, so the tape look should
## be on from the moment the act loads. With it false the screen is clean until
## the player presses F, which reads as "the shader is broken".
@export var filming := true
## Seconds to fade the overlay in/out so it does not pop.
@export var fade_seconds := 0.25

@export_group("Intensity Ramp")
## How the effect gets worse over time. 0 = never ramps.
@export var ramp_seconds := 900.0
## Starting values, used at t=0. These match the shader's own defaults.
@export var base_smearing := 0.5
@export var base_noise := 0.08
@export var base_jitter := 0.002
@export var base_scanline := 0.1
@export var base_vignette := 0.3
@export var base_sharpening := 0.4
## Values at full ramp. The tape is falling apart by now.
@export var max_smearing := 0.95
@export var max_noise := 0.30
@export var max_jitter := 0.020
@export var max_scanline := 0.34
@export var max_vignette := 0.62
@export var max_sharpening := 0.85

@export_group("Crack")
## Leave the glass-crack off: at full strength its 8-spoke star reads as a
## pentagram / radar overlay rather than a cracked lens.
@export var crack_intensity := 0.0
@export var crack_size := 0.0

var _material: ShaderMaterial
var _elapsed := 0.0
var _alpha := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = material as ShaderMaterial
	if _material == null:
		push_warning("Filming: no ShaderMaterial on this ColorRect.")
		set_process(false)
		return
	_alpha = 1.0 if filming else 0.0
	modulate.a = _alpha
	_apply(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(film_action):
		filming = not filming
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_elapsed += delta

	# Fade the overlay in or out.
	var want := 1.0 if filming else 0.0
	if not is_equal_approx(_alpha, want):
		var step := delta / maxf(fade_seconds, 0.01)
		_alpha = move_toward(_alpha, want, step)
		modulate.a = _alpha

	if not filming and _alpha <= 0.0:
		return

	_apply(clampf(_elapsed / maxf(ramp_seconds, 1.0), 0.0, 1.0))


## Push the current intensity into the shader's uniforms.
func _apply(t: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("smearing", lerpf(base_smearing, max_smearing, t))
	_material.set_shader_parameter("static_noise", lerpf(base_noise, max_noise, t))
	_material.set_shader_parameter("vertical_jitter", lerpf(base_jitter, max_jitter, t))
	_material.set_shader_parameter("scanline_opacity", lerpf(base_scanline, max_scanline, t))
	_material.set_shader_parameter("vignette_intensity", lerpf(base_vignette, max_vignette, t))
	_material.set_shader_parameter("sharpening", lerpf(base_sharpening, max_sharpening, t))
	_material.set_shader_parameter("crack_intensity", crack_intensity)
	_material.set_shader_parameter("crack_size", crack_size)


## Call this to jump the ramp (e.g. on entering a new level).
func set_progress(t: float) -> void:
	_elapsed = clampf(t, 0.0, 1.0) * ramp_seconds
	_apply(clampf(t, 0.0, 1.0))
