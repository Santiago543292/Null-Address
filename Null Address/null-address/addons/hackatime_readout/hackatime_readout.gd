@tool
extends EditorPlugin

## Hackatime Readout
##
## Adds a bottom-panel readout of today's Hackatime total.
##
## READ-ONLY BY DESIGN. This plugin only ever runs `wakatime-cli --today`,
## which is a *query* against the Hackatime API. It never passes an --entity,
## never sends a heartbeat, and never writes to the offline heartbeat queue.
## Opening, refreshing, or staring at this panel cannot add a single second to
## your tracked time.
##
## It reads the same config the Godot Super-Wakatime plugin uses, so if that
## plugin is reporting, this one shows the same numbers.

## Display "2h10m" instead of the CLI's "2h 10m". Set false for the spaced form.
const COMPACT := true
## How often to re-query, in seconds. Queries are read-only, so this is cheap.
const REFRESH_SECONDS := 60.0
const PANEL_TITLE := "Hackatime"

var _panel: HBoxContainer
var _time_label: Label
var _raw_label: Label
var _refresh_button: Button
var _timer: Timer
var _cli_path := ""
var _busy := false


func _enter_tree() -> void:
	_cli_path = _find_cli()

	_panel = HBoxContainer.new()
	_panel.add_theme_constant_override("separation", 10)

	_time_label = Label.new()
	_time_label.text = "--"
	_panel.add_child(_time_label)

	_raw_label = Label.new()
	_raw_label.text = ""
	_raw_label.modulate = Color(1, 1, 1, 0.5)
	_panel.add_child(_raw_label)

	_refresh_button = Button.new()
	_refresh_button.text = "↻"
	_refresh_button.tooltip_text = "Re-query Hackatime (read-only)"
	_refresh_button.pressed.connect(refresh)
	_panel.add_child(_refresh_button)

	add_control_to_bottom_panel(_panel, PANEL_TITLE)

	_timer = Timer.new()
	_timer.wait_time = REFRESH_SECONDS
	_timer.autostart = true
	_timer.timeout.connect(refresh)
	add_child(_timer)

	refresh()


func _exit_tree() -> void:
	if _timer != null:
		_timer.stop()
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()


## Query Hackatime for today's total. Sends nothing, changes nothing.
func refresh() -> void:
	if _busy:
		return

	if _cli_path.is_empty():
		_cli_path = _find_cli()

	if _cli_path.is_empty():
		_set_text("no wakatime-cli", "Install/run the Godot Super-Wakatime plugin once so it fetches the CLI.")
		return

	_busy = true
	_set_text("...", "")

	# Run off the main thread so a slow network call never stalls the editor.
	var task := func() -> void:
		var output: Array = []
		# NOTE: "--today" only. No --entity, no --write: this is a pure query.
		var exit_code := OS.execute(_cli_path, ["--today"], output, true)
		var raw: String = ""
		if exit_code == 0 and output.size() > 0:
			raw = str(output[0]).strip_edges()
		call_deferred("_on_result", exit_code, raw)

	WorkerThreadPool.add_task(task)


func _on_result(exit_code: int, raw: String) -> void:
	_busy = false

	if exit_code != 0 or raw.is_empty():
		_set_text("unavailable", "Hackatime query failed (exit %d). Check ~/.wakatime.cfg." % exit_code)
		return

	_set_text(format_time(raw), raw)


func _set_text(primary: String, secondary: String) -> void:
	if _time_label == null:
		return
	_time_label.text = primary
	_raw_label.text = "" if secondary.is_empty() else "(%s)" % secondary
	_panel.tooltip_text = secondary


## "2h 10m" -> "2h10m". Also handles "45m", "1d 2h 3m", "0 secs".
static func format_time(raw: String) -> String:
	var t := raw.strip_edges()
	if t.is_empty():
		return "--"
	if not COMPACT:
		return t
	# Drop the spaces the CLI puts between the number and its unit.
	return t.replace(" ", "")


## Locate the wakatime-cli binary that the Super-Wakatime plugin installs into
## the user's home directory (~/.wakatime/wakatime-cli-<platform>-<arch>[.exe]).
func _find_cli() -> String:
	var home := OS.get_environment("USERPROFILE")
	if home.is_empty():
		home = OS.get_environment("HOME")
	if home.is_empty():
		return ""

	var dir_path := home.path_join(".wakatime")
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""

	dir.list_dir_begin()
	var best := ""
	while true:
		var f := dir.get_next()
		if f.is_empty():
			break
		if dir.current_is_dir():
			continue
		# Match the real CLI, and skip the .backup copy the plugin leaves behind.
		if f.begins_with("wakatime-cli") and not f.ends_with(".backup"):
			best = dir_path.path_join(f)
			break
	dir.list_dir_end()

	return best
