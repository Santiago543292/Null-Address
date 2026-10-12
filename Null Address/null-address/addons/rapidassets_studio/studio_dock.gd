@tool
extends VBoxContainer

# ============================================================================
#  Rapid Assets Studio dock — login, projects, sessions, chat, one-click
#  workflows (with reference-image upload) and import of generated assets.
# ============================================================================

var state: RapidAssetsState
var api: RapidAssetsApi

# Data
var _projects: Array = []
var _sessions: Array = []
var _messages: Array = []          # each: { role, text, image_url, model_url, thumbnail_url, job_id, status, imported }
var _tracked_chains: Array = []    # each: { chain_id, in_flight }
var _tracked_jobs: Array = []      # each: { job_id, in_flight }
var _image_cache: Dictionary = {}  # url -> Texture2D (avoid re-downloading on every rebuild)
var _busy := false
var _workflow_image_path := ""
var _editor_interface = null       # injected by plugin.gd (for FileSystem rescan)

# Widgets
var _status_label: Label
var _login_box: VBoxContainer
var _main_box: VBoxContainer
var _email_edit: LineEdit
var _password_edit: LineEdit
var _account_label: Label
var _project_option: OptionButton
var _newproject_edit: LineEdit
var _session_option: OptionButton
var _chat_scroll: ScrollContainer
var _chat_list: VBoxContainer
var _workflow_option: OptionButton
var _workflow_desc: Label
var _workflow_image_label: Label
var _prompt_edit: TextEdit
var _mode_option: OptionButton
var _send_button: Button
var _generating_label: Label
var _file_dialog: FileDialog
var _poll_timer: Timer

func _ready() -> void:
	custom_minimum_size = Vector2(360, 480)
	state = RapidAssetsState.new()
	state.load_state()
	api = RapidAssetsApi.new(self, state)

	_build_ui()
	_refresh_view()

	if state.is_authenticated():
		_do_refresh_projects()

# ──────────────────────────────────────────────────────────────────────────
#  UI construction
# ──────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var title := Label.new()
	title.text = "Rapid Assets Studio"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	# Visible build badge so it's obvious which plugin version is actually loaded.
	var ver := Label.new()
	ver.text = "Build %s · history + webp + 3D import" % RapidAssetsConfig.PLUGIN_VERSION
	ver.add_theme_font_size_override("font_size", 10)
	ver.modulate = Color(0.45, 0.6, 0.8)
	add_child(ver)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.modulate = Color(0.7, 0.7, 0.7)
	add_child(_status_label)

	# ── Login view ──
	_login_box = VBoxContainer.new()
	add_child(_login_box)
	var l1 := Label.new(); l1.text = "Sign in with an authorized Studio account"; _login_box.add_child(l1)
	_email_edit = LineEdit.new(); _email_edit.placeholder_text = "Email"; _email_edit.text = state.user_email; _login_box.add_child(_email_edit)
	_password_edit = LineEdit.new(); _password_edit.placeholder_text = "Password"; _password_edit.secret = true; _login_box.add_child(_password_edit)
	var sign_btn := Button.new(); sign_btn.text = "Sign In"; sign_btn.pressed.connect(_on_sign_in); _login_box.add_child(sign_btn)
	var or_lbl := Label.new(); or_lbl.text = "— or —"; or_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; or_lbl.modulate = Color(0.6, 0.6, 0.6); _login_box.add_child(or_lbl)
	var google_btn := Button.new(); google_btn.text = "Sign in with Google"; google_btn.pressed.connect(_on_sign_in_google); _login_box.add_child(google_btn)

	# ── Main view ──
	_main_box = VBoxContainer.new()
	_main_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_main_box)

	var acc_row := HBoxContainer.new(); _main_box.add_child(acc_row)
	_account_label = Label.new(); _account_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; acc_row.add_child(_account_label)
	var refresh_btn := Button.new(); refresh_btn.text = "Refresh"; refresh_btn.pressed.connect(_do_refresh_projects); acc_row.add_child(refresh_btn)
	var logout_btn := Button.new(); logout_btn.text = "Logout"; logout_btn.pressed.connect(_on_logout); acc_row.add_child(logout_btn)

	# Projects
	var proj_row := HBoxContainer.new(); _main_box.add_child(proj_row)
	var proj_lbl := Label.new(); proj_lbl.text = "Project:"; proj_row.add_child(proj_lbl)
	_project_option = OptionButton.new(); _project_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_project_option.item_selected.connect(_on_project_selected); proj_row.add_child(_project_option)

	var newproj_row := HBoxContainer.new(); _main_box.add_child(newproj_row)
	_newproject_edit = LineEdit.new(); _newproject_edit.placeholder_text = "New project name"; _newproject_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; newproj_row.add_child(_newproject_edit)
	var create_btn := Button.new(); create_btn.text = "Create"; create_btn.pressed.connect(_on_create_project); newproj_row.add_child(create_btn)

	# Sessions
	var sess_row := HBoxContainer.new(); _main_box.add_child(sess_row)
	var sess_lbl := Label.new(); sess_lbl.text = "Session:"; sess_row.add_child(sess_lbl)
	_session_option = OptionButton.new(); _session_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_session_option.item_selected.connect(_on_session_selected); sess_row.add_child(_session_option)
	var newchat_btn := Button.new(); newchat_btn.text = "New Chat"; newchat_btn.pressed.connect(_on_new_chat); sess_row.add_child(newchat_btn)

	# Chat log
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.custom_minimum_size = Vector2(0, 200)
	_main_box.add_child(_chat_scroll)
	_chat_list = VBoxContainer.new(); _chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_scroll.add_child(_chat_list)

	_generating_label = Label.new(); _generating_label.text = "Generating..."; _generating_label.modulate = Color(0.8, 0.8, 0.4)
	_generating_label.visible = false; _main_box.add_child(_generating_label)

	# Workflow picker
	var wf_row := HBoxContainer.new(); _main_box.add_child(wf_row)
	var wf_lbl := Label.new(); wf_lbl.text = "Workflow:"; wf_row.add_child(wf_lbl)
	_workflow_option = OptionButton.new(); _workflow_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in RapidAssetsWorkflows.combo_labels():
		_workflow_option.add_item(label)
	_workflow_option.item_selected.connect(_on_workflow_selected); wf_row.add_child(_workflow_option)
	var browse_btn := Button.new(); browse_btn.text = "Image"; browse_btn.pressed.connect(_on_browse_image); wf_row.add_child(browse_btn)
	var clearwf_btn := Button.new(); clearwf_btn.text = "Clear"; clearwf_btn.pressed.connect(_on_clear_workflow); wf_row.add_child(clearwf_btn)

	_workflow_desc = Label.new(); _workflow_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workflow_desc.modulate = Color(0.6, 0.6, 0.6); _workflow_desc.visible = false; _main_box.add_child(_workflow_desc)
	_workflow_image_label = Label.new(); _workflow_image_label.modulate = Color(0.6, 0.8, 0.6); _workflow_image_label.visible = false; _main_box.add_child(_workflow_image_label)

	# Prompt + mode + send
	_prompt_edit = TextEdit.new(); _prompt_edit.placeholder_text = "Type your prompt here..."
	_prompt_edit.custom_minimum_size = Vector2(0, 60); _prompt_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_box.add_child(_prompt_edit)

	var send_row := HBoxContainer.new(); _main_box.add_child(send_row)
	var mode_lbl := Label.new(); mode_lbl.text = "Mode:"; send_row.add_child(mode_lbl)
	_mode_option = OptionButton.new(); _mode_option.add_item("thinking"); _mode_option.add_item("fast"); send_row.add_child(_mode_option)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; send_row.add_child(spacer)
	_send_button = Button.new(); _send_button.text = "Send"; _send_button.pressed.connect(_on_send); send_row.add_child(_send_button)

	# File dialog for reference image
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.gif,*.bmp,*.tga ; Images"])
	_file_dialog.file_selected.connect(_on_image_chosen)
	add_child(_file_dialog)

	# Poll timer for workflow chains
	_poll_timer = Timer.new(); _poll_timer.wait_time = RapidAssetsConfig.POLL_INTERVAL; _poll_timer.autostart = true
	_poll_timer.timeout.connect(_on_poll_tick)
	add_child(_poll_timer)

# ──────────────────────────────────────────────────────────────────────────
#  View / state helpers
# ──────────────────────────────────────────────────────────────────────────
func _refresh_view() -> void:
	var authed := state.is_authenticated()
	_login_box.visible = not authed
	_main_box.visible = authed
	if authed:
		_account_label.text = "%s  (%s)" % [state.user_name if state.user_name != "" else state.user_email, state.user_email]
	_update_workflow_ui()
	_generating_label.visible = _tracked_chains.size() > 0 or _tracked_jobs.size() > 0

func _set_status(msg: String, err := false) -> void:
	_status_label.text = msg
	_status_label.modulate = Color(0.9, 0.4, 0.4) if err else Color(0.6, 0.8, 0.6)

func _set_busy(b: bool, msg := "") -> void:
	_busy = b
	if msg != "":
		_set_status(msg)
	_send_button.disabled = b

func _update_workflow_ui() -> void:
	var wf := RapidAssetsWorkflows.from_index(_workflow_option.selected if _workflow_option else 0)
	var has_wf := not wf.is_empty()
	_workflow_desc.visible = has_wf
	_workflow_desc.text = (wf.description if has_wf else "")
	var needs_img: bool = has_wf and bool(wf.get("requires_image", false))
	_workflow_image_label.visible = needs_img
	if needs_img:
		_workflow_image_label.text = ("Reference image: (none - required)" if _workflow_image_path == "" else "Reference image: " + _workflow_image_path.get_file())

# ──────────────────────────────────────────────────────────────────────────
#  Auth
# ──────────────────────────────────────────────────────────────────────────
func _on_sign_in() -> void:
	if _busy: return
	_set_busy(true, "Signing in...")
	var r = await api.sign_in(_email_edit.text.strip_edges(), _password_edit.text)
	_set_busy(false)
	if not r.ok:
		_set_status(r.error, true)
		return
	_password_edit.text = ""
	_set_status("Signed in. Loading projects...")
	_refresh_view()
	_do_refresh_projects()

func _on_sign_in_google() -> void:
	if _busy: return
	_set_busy(true, "Opening Google sign-in in your browser...")
	var r = await api.sign_in_google()
	_set_busy(false)
	if not r.ok:
		_set_status(r.error, true)
		return
	_set_status("Signed in. Loading projects...")
	_refresh_view()
	_do_refresh_projects()

func _on_logout() -> void:
	state.clear_auth()
	_projects.clear(); _sessions.clear(); _messages.clear(); _tracked_chains.clear(); _tracked_jobs.clear()
	_set_status("Signed out.")
	_refresh_view(); _rebuild_chat()

# ──────────────────────────────────────────────────────────────────────────
#  Projects / sessions
# ──────────────────────────────────────────────────────────────────────────
func _do_refresh_projects() -> void:
	if _busy or not state.is_authenticated(): return
	_set_busy(true, "Loading projects...")
	var r = await api.get_projects(state.show_shared_projects)
	_set_busy(false)
	if not r.ok:
		_set_status(r.error, true); return
	_projects = r.items
	_project_option.clear()
	var sel_idx := 0
	for i in _projects.size():
		var p = _projects[i]
		_project_option.add_item(str(p.get("name", p.get("id", "project"))))
		if str(p.get("id", "")) == state.selected_project_id:
			sel_idx = i
	if _projects.size() > 0:
		_project_option.selected = sel_idx
		state.selected_project_id = str(_projects[sel_idx].get("id", ""))
		state.save_state()
		_set_status("Loaded %d project(s)." % _projects.size())
		_do_refresh_sessions()

func _on_project_selected(idx: int) -> void:
	if idx < 0 or idx >= _projects.size(): return
	state.selected_project_id = str(_projects[idx].get("id", ""))
	state.selected_session_id = ""
	state.save_state()
	_messages.clear(); _tracked_chains.clear(); _tracked_jobs.clear(); _rebuild_chat()
	_do_refresh_sessions()

func _do_refresh_sessions() -> void:
	if state.selected_project_id == "": return
	var r = await api.get_sessions(state.selected_project_id)
	if not r.ok:
		_set_status(r.error, true); return
	_sessions = r.items
	_session_option.clear()
	_session_option.add_item("(new chat)")
	for s in _sessions:
		_session_option.add_item(str(s.get("title", s.get("session_id", "session"))))
	_set_status("Loaded %d session(s)." % _sessions.size())

func _on_session_selected(idx: int) -> void:
	if idx <= 0:
		_on_new_chat(); return
	var s = _sessions[idx - 1]
	state.selected_session_id = str(s.get("session_id", ""))
	state.save_state()
	# Restore this session's chat history so switching back to a previous chat
	# shows its messages (the backend keeps memory keyed by session_id).
	_messages.clear(); _tracked_chains.clear(); _tracked_jobs.clear(); _rebuild_chat()
	_set_busy(true, "Loading chat history...")
	var r = await api.get_session(state.selected_session_id)
	_set_busy(false)
	if not r.ok:
		_set_status(r.error, true); return
	_ingest_history(r.messages)
	_rebuild_chat()
	_set_status("Loaded chat (%d message(s))." % _messages.size())

func _on_create_project() -> void:
	if _busy or _newproject_edit.text.strip_edges() == "": return
	_set_busy(true, "Creating project...")
	var r = await api.create_project(_newproject_edit.text.strip_edges())
	_set_busy(false)
	if not r.ok:
		_set_status(r.error, true); return
	_newproject_edit.text = ""
	_do_refresh_projects()

func _on_new_chat() -> void:
	state.selected_session_id = ""
	state.save_state()
	_messages.clear(); _tracked_chains.clear(); _tracked_jobs.clear(); _rebuild_chat()
	_set_status("Started a new chat.")

# ──────────────────────────────────────────────────────────────────────────
#  Workflow picker
# ──────────────────────────────────────────────────────────────────────────
func _on_workflow_selected(_idx: int) -> void:
	_workflow_image_path = ""
	_update_workflow_ui()

func _on_clear_workflow() -> void:
	_workflow_option.selected = 0
	_workflow_image_path = ""
	_update_workflow_ui()

func _on_browse_image() -> void:
	_file_dialog.popup_centered_ratio(0.6)

func _on_image_chosen(path: String) -> void:
	_workflow_image_path = path
	_update_workflow_ui()

# ──────────────────────────────────────────────────────────────────────────
#  Send
# ──────────────────────────────────────────────────────────────────────────
func _on_send() -> void:
	if _busy or state.selected_project_id == "": return
	var wf := RapidAssetsWorkflows.from_index(_workflow_option.selected)
	var prompt := _prompt_edit.text.strip_edges()
	if prompt == "" and wf.is_empty():
		return
	if not wf.is_empty() and wf.get("requires_image", false) and _workflow_image_path == "":
		_set_status("The %s workflow requires a reference image." % wf.label, true)
		return

	var outgoing := prompt
	if outgoing == "" and not wf.is_empty():
		outgoing = "Run the %s workflow" % wf.label

	var workflow_id := str(wf.get("id", ""))
	var image_path := _workflow_image_path

	_messages.append({
		"role": "user",
		"text": ("[%s] %s" % [wf.label, outgoing]) if not wf.is_empty() else outgoing,
	})

	# Reset composer
	_prompt_edit.text = ""
	_workflow_option.selected = 0
	_workflow_image_path = ""
	_update_workflow_ui()
	_rebuild_chat()

	var busy_msg := "Sending prompt..."
	if not wf.is_empty():
		busy_msg = "Running %s..." % wf.label
	_set_busy(true, busy_msg)

	var image_urls: Array = []
	if image_path != "":
		var up = await api.upload_image(image_path)
		if not up.ok:
			_set_busy(false)
			_set_status("Image upload failed: " + up.error, true)
			return
		image_urls.append(up.url)

	var final_prompt := outgoing
	for i in image_urls.size():
		final_prompt += "\n[IMAGE_INPUT_%d]\nURL: %s\n[/IMAGE_INPUT_%d]" % [i + 1, image_urls[i], i + 1]

	var mode := _mode_option.get_item_text(_mode_option.selected)
	var r = await api.ask(final_prompt, mode, workflow_id, image_urls)
	_set_busy(false)
	if not r.ok:
		_set_status(r.error, true)
		return
	_apply_ask_response(r.data)
	_set_status("Prompt sent.")
	_rebuild_chat()

# ──────────────────────────────────────────────────────────────────────────
#  Response handling
# ──────────────────────────────────────────────────────────────────────────
func _ingest_history(messages) -> void:
	# Convert a backend `messages` array (from /session/{id} metadata or /ask) into
	# chat rows. Beyond plain text turns this MUST handle the asset/workflow rows the
	# backend stores with content=null: generated images/3D models live in
	# `tool_generation`, and completed workflows in `outputs[].result`. Without this,
	# reopening an older chat that generated assets shows an empty history.
	if not (messages is Array):
		return
	for m in messages:
		if not (m is Dictionary): continue
		var t := str(m.get("type", "")).to_lower()

		# Generated asset (image / 3D model / etc.) — stored on an AI msg, content=null.
		var tool_gen = m.get("tool_generation", null)
		if tool_gen is Dictionary:
			_add_tool_message(tool_gen)
			continue

		# Completed workflow card — assets are nested under outputs[].result.
		if t == "workflow_progress" or (m.get("outputs", null) is Array):
			var wname := str(m.get("workflow_name", ""))
			if wname != "":
				_messages.append({ "role": "assistant", "text": "Workflow: " + wname })
			for o in m.get("outputs", []):
				if o is Dictionary:
					var res = o.get("result", o)
					if res is Dictionary:
						_add_tool_message(res)
			continue

		# In-flight workflow chain placeholder (no assets yet) — nothing to render.
		if m.has("workflow_chain") and m.get("content", null) == null:
			continue

		var msg_name := str(m.get("name", ""))
		var content = m.get("content", null)
		var looks_tool: bool = content is Dictionary and (content.has("job_id") or content.has("image_url") or content.has("image_path") or content.has("model_url"))
		if msg_name != "" or t == "tool" or looks_tool:
			_add_tool_message(content)
		else:
			var txt := _content_to_text(content)
			if txt != "":
				_messages.append({ "role": ("user" if t == "human" or t == "user" else "assistant"), "text": txt })

func _apply_ask_response(data) -> void:
	if not (data is Dictionary):
		return
	if str(data.get("session_id", "")) != "":
		state.selected_session_id = str(data.session_id)
		state.save_state()

	# Assistant text messages
	if data.has("messages") and data["messages"] is Array:
		for m in data["messages"]:
			if not (m is Dictionary): continue
			var t := str(m.get("type", "")).to_lower()
			var msg_name := str(m.get("name", ""))
			var content = m.get("content", null)
			var looks_tool: bool = content is Dictionary and (content.has("job_id") or content.has("image_url") or content.has("image_path") or content.has("model_url"))
			if msg_name != "" or t == "tool" or looks_tool:
				_add_tool_message(content)
			else:
				var txt := _content_to_text(content)
				if txt != "":
					_messages.append({ "role": ("user" if t == "human" or t == "user" else "assistant"), "text": txt })

	# Workflow chain -> poll the chain endpoint.
	if data.has("workflow_chain") and data["workflow_chain"] is Dictionary:
		var chain_id := str(data["workflow_chain"].get("chain_id", ""))
		if chain_id != "" and not _is_tracking(chain_id):
			_tracked_chains.append({ "chain_id": chain_id, "in_flight": false })
			_set_status("Running workflow...")
	else:
		# Normal generation -> poll the pending jobs so the image actually arrives.
		if data.has("pending_jobs") and data["pending_jobs"] is Array:
			for jid in data["pending_jobs"]:
				_register_job(str(jid))
	_refresh_view()

func _register_job(job_id: String) -> void:
	if job_id == "":
		return
	for j in _tracked_jobs:
		if j.job_id == job_id:
			return
	_tracked_jobs.append({ "job_id": job_id, "in_flight": false })

func _add_tool_message(content) -> void:
	# Tool results may arrive as a dict or, from raw session JSON, as a JSON string.
	if content is String:
		content = JSON.parse_string(content)
	if not (content is Dictionary):
		return
	var img := RapidAssetsApi.resolve_asset_url(_first_nonempty([_dget(content, "image_url"), _dget(content, "image_path")]))
	var model := RapidAssetsApi.resolve_asset_url(_dget(content, "model_url"))
	var thumb := RapidAssetsApi.resolve_asset_url(_dget(content, "thumbnail_url"))
	_upsert_result(_dget(content, "job_id"), img, model, thumb)

func _upsert_result(job_id: String, image: String, model: String, thumb: String) -> void:
	if image == "" and model == "" and thumb == "":
		return
	var found = null
	for m in _messages:
		if job_id != "" and str(m.get("job_id", "")) == job_id:
			found = m
			break
	if found == null and image != "":
		for m in _messages:
			if str(m.get("image_url", "")) == image:
				found = m
				break
	if found == null:
		found = { "role": "tool", "status": "completed", "job_id": job_id }
		_messages.append(found)
	found["role"] = "tool"
	found["status"] = "completed"
	if image != "": found["image_url"] = image
	if model != "": found["model_url"] = model
	if thumb != "": found["thumbnail_url"] = thumb

func _dget(d, key: String) -> String:
	if d is Dictionary:
		var v = d.get(key, null)
		# A JSON null arrives as a real null Variant; str(null) is "<null>", which
		# would be mistaken for a valid URL. Treat null/"<null>"/"null" as empty.
		if v == null:
			return ""
		var s := str(v)
		if s == "<null>" or s == "null" or s == "None":
			return ""
		return s
	return ""

func _first_nonempty(arr: Array) -> String:
	for v in arr:
		if str(v) != "":
			return str(v)
	return ""

# ──────────────────────────────────────────────────────────────────────────
#  Workflow chain polling
# ──────────────────────────────────────────────────────────────────────────
func _on_poll_tick() -> void:
	if not state.is_authenticated():
		return
	for job in _tracked_jobs.duplicate():
		if not job.get("in_flight", false):
			job["in_flight"] = true
			_poll_job(job)
	for chain in _tracked_chains.duplicate():
		if not chain.get("in_flight", false):
			chain["in_flight"] = true
			_poll_chain(chain)

func _poll_job(job: Dictionary) -> void:
	var job_id: String = job.job_id
	var r = await api.poll_job(job_id)
	job["in_flight"] = false
	if not r.ok or not (r.data is Dictionary):
		return
	var data: Dictionary = r.data
	var status := str(data.get("status", "")).to_lower()
	# If completed but the status payload has no asset, fetch the full result.
	if status in ["completed", "succeeded", "success"] and _extract_image(data) == "":
		var gr = await api.get_generation_result(job_id)
		if gr.ok and gr.data is Dictionary:
			data = gr.data
			status = str(data.get("status", status)).to_lower()
	_apply_job_data(job_id, data)
	if status in ["completed", "succeeded", "success", "failed", "error", "cancelled", "canceled"]:
		_tracked_jobs = _tracked_jobs.filter(func(j): return j.job_id != job_id)
	_refresh_view()
	_rebuild_chat()

func _apply_job_data(job_id: String, data: Dictionary) -> void:
	var d = data.get("data", null)
	var image := RapidAssetsApi.resolve_asset_url(_first_nonempty([_dget(data, "image_path"), _dget(d, "image_url"), _dget(d, "image_path")]))
	var model := RapidAssetsApi.resolve_asset_url(_first_nonempty([_dget(data, "model_url"), _dget(d, "model_url")]))
	var thumb := RapidAssetsApi.resolve_asset_url(_first_nonempty([_dget(data, "thumbnail_url"), _dget(d, "thumbnail_url")]))
	_upsert_result(job_id, image, model, thumb)

func _extract_image(data: Dictionary) -> String:
	var d = data.get("data", null)
	return _first_nonempty([_dget(data, "image_path"), _dget(data, "model_url"), _dget(data, "thumbnail_url"), _dget(d, "image_url"), _dget(d, "image_path"), _dget(d, "model_url")])

func _poll_chain(chain: Dictionary) -> void:
	var chain_id: String = chain.chain_id
	var r = await api.get_chain_status(chain_id)
	chain["in_flight"] = false
	if not r.ok or not (r.data is Dictionary):
		return
	var data: Dictionary = r.data
	var status := str(data.get("status", "")).to_lower()

	if data.has("tasks") and data["tasks"] is Array:
		for task in data["tasks"]:
			if task is Dictionary:
				_ingest_chain_result(_dget(task, "job_id"), task.get("result", null))
	if data.has("outputs") and data["outputs"] is Dictionary:
		for key in data["outputs"]:
			_ingest_chain_result("", data["outputs"][key])

	if status in ["completed", "failed", "cancelled", "canceled", "error"]:
		_tracked_chains = _tracked_chains.filter(func(c): return c.chain_id != chain_id)
		_set_status("Workflow completed." if status == "completed" else "Workflow failed.", status != "completed")

	_refresh_view()
	_rebuild_chat()

# A workflow step's result/output is a Dictionary for single-image steps, or an
# Array of result dicts for fan-out steps (Pose Variations, Image Variations,
# Facial Pose Sheet). Handle both so multi-image workflows actually render.
func _ingest_chain_result(default_job_id: String, obj) -> void:
	if obj is Array:
		for item in obj:
			if item is Dictionary:
				var item_jid := _dget(item, "job_id")
				_add_chain_result(item_jid if item_jid != "" else default_job_id, item)
	elif obj is Dictionary:
		var jid := _dget(obj, "job_id")
		_add_chain_result(jid if jid != "" else default_job_id, obj)

func _add_chain_result(job_id: String, obj: Dictionary) -> void:
	var img := RapidAssetsApi.resolve_asset_url(_first_nonempty([_dget(obj, "image_path"), _dget(obj, "image_url")]))
	var model := RapidAssetsApi.resolve_asset_url(_dget(obj, "model_url"))
	var thumb := RapidAssetsApi.resolve_asset_url(_dget(obj, "thumbnail_url"))
	_upsert_result(job_id, img, model, thumb)

func _is_tracking(chain_id: String) -> bool:
	for c in _tracked_chains:
		if c.chain_id == chain_id:
			return true
	return false

# ──────────────────────────────────────────────────────────────────────────
#  Chat rendering — only user / assistant / finished generations
# ──────────────────────────────────────────────────────────────────────────
func _rebuild_chat() -> void:
	for c in _chat_list.get_children():
		c.queue_free()

	var shown := 0
	for m in _messages:
		if not _should_show(m):
			continue
		shown += 1
		_chat_list.add_child(_build_message_widget(m))

	if shown == 0:
		var empty := Label.new(); empty.text = "No messages yet."; empty.modulate = Color(0.5, 0.5, 0.5)
		_chat_list.add_child(empty)
	await get_tree().process_frame
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)

func _should_show(m: Dictionary) -> bool:
	var role := str(m.get("role", ""))
	if role == "user" or role == "assistant":
		return str(m.get("text", "")) != "" or _has_artifact(m)
	return _has_artifact(m)

func _has_artifact(m: Dictionary) -> bool:
	return str(m.get("image_url", "")) != "" or str(m.get("model_url", "")) != "" or str(m.get("thumbnail_url", "")) != ""

func _build_message_widget(m: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)

	var role := str(m.get("role", ""))
	var title := Label.new()
	title.text = "You" if role == "user" else ("Assistant" if role == "assistant" else "Generation")
	title.add_theme_font_size_override("font_size", 12)
	box.add_child(title)

	if (role == "user" or role == "assistant") and str(m.get("text", "")) != "":
		var txt := Label.new(); txt.text = str(m.text); txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(txt)

	var preview_url := str(m.get("thumbnail_url", ""))
	if preview_url == "":
		preview_url = str(m.get("image_url", ""))
	if preview_url != "":
		var tex_rect := TextureRect.new()
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(256, 256)
		box.add_child(tex_rect)
		if _image_cache.has(preview_url):
			tex_rect.texture = _image_cache[preview_url]
		else:
			_load_preview(preview_url, tex_rect)

	if str(m.get("image_url", "")) != "":
		var iurl := str(m["image_url"])
		var imp := Button.new(); imp.text = "Import Image"
		imp.pressed.connect(func(): _import_asset(iurl))
		box.add_child(imp)

	if str(m.get("model_url", "")) != "":
		var murl := str(m["model_url"])
		var impm := Button.new(); impm.text = "Import 3D Model"
		impm.pressed.connect(func(): _import_model(murl))
		box.add_child(impm)

	return panel

func _load_preview(url: String, tex_rect: TextureRect) -> void:
	var r = await api.download_bytes(url)
	if not r.ok or r.bytes.size() == 0:
		push_warning("[RapidAssets] Image download failed: " + url)
		return
	var tex := _make_texture(r.bytes)
	if tex == null:
		push_warning("[RapidAssets] Could not decode image (%d bytes): %s" % [r.bytes.size(), url])
		return
	_image_cache[url] = tex
	if is_instance_valid(tex_rect):
		tex_rect.texture = tex

func _make_texture(bytes: PackedByteArray) -> Texture2D:
	var img := Image.new()
	if img.load_png_from_buffer(bytes) == OK:  return ImageTexture.create_from_image(img)
	if img.load_jpg_from_buffer(bytes) == OK:  return ImageTexture.create_from_image(img)
	if img.load_webp_from_buffer(bytes) == OK: return ImageTexture.create_from_image(img)
	return null

# ──────────────────────────────────────────────────────────────────────────
#  Import generated asset into the project
# ──────────────────────────────────────────────────────────────────────────
func _import_asset(url: String) -> void:
	if url == "": return
	_set_status("Importing into project...")
	var r = await api.download_bytes(url)
	if not r.ok or r.bytes.size() == 0:
		_set_status("Download failed.", true); return
	DirAccess.make_dir_recursive_absolute(RapidAssetsConfig.IMPORT_DIR)
	var fname := url.get_file()
	if fname == "" or not fname.contains("."):
		fname = "generated_%d.png" % Time.get_ticks_msec()
	var dest := RapidAssetsConfig.IMPORT_DIR + "/" + fname
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		_set_status("Could not write file.", true); return
	f.store_buffer(r.bytes)
	f.close()
	# Ask the editor to rescan the filesystem so the asset appears in the
	# FileSystem dock. Use the injected editor interface (reliable on all
	# Godot 4.x) and fall back to the 4.2+ global singleton.
	var fs = _get_editor_filesystem()
	if fs:
		fs.scan()
	else:
		push_warning("[Rapid Assets] Imported %s but could not trigger a FileSystem rescan — refresh manually." % dest)
	_set_status("Imported: " + dest)

func _import_model(url: String) -> void:
	# Download a generated 3D model, save it into the project, let the editor import
	# it into a scene, then place that scene into the currently-open 3D scene so it
	# shows up in the viewport (not just the FileSystem dock).
	if url == "": return
	_set_status("Importing 3D model...")
	var r = await api.download_bytes(url)
	if not r.ok or r.bytes.size() == 0:
		_set_status("Download failed.", true); return
	DirAccess.make_dir_recursive_absolute(RapidAssetsConfig.IMPORT_DIR)
	var fname := url.get_file()
	if fname == "" or not fname.contains("."):
		fname = "model_%d.glb" % Time.get_ticks_msec()
	# Godot only auto-imports recognised 3D extensions; default anything odd to .glb.
	var ext := fname.get_extension().to_lower()
	if ext != "glb" and ext != "gltf" and ext != "fbx" and ext != "obj":
		fname = fname.get_basename() + ".glb"
	var dest := RapidAssetsConfig.IMPORT_DIR + "/" + fname
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		_set_status("Could not write file.", true); return
	f.store_buffer(r.bytes)
	f.close()

	var fs = _get_editor_filesystem()
	if fs == null:
		_set_status("Saved %s, but no editor access to import it — refresh FileSystem manually." % dest, true)
		return

	# Rescan so the editor imports the model into a PackedScene, then wait for it.
	fs.scan()
	await get_tree().process_frame
	while fs.is_scanning():
		await get_tree().process_frame
	var res = null
	var tries := 0
	while tries < 180:
		if ResourceLoader.exists(dest):
			res = load(dest)
			if res != null:
				break
		await get_tree().process_frame
		tries += 1

	if res == null:
		_set_status("Saved %s. Open it from the FileSystem dock to add it to your scene." % dest, true)
		return

	if _editor_interface == null:
		_set_status("Saved & imported %s (no editor interface to place it)." % dest, true)
		return
	var scene_root = _editor_interface.get_edited_scene_root()
	if scene_root == null:
		_set_status("Imported %s. Open or create a 3D scene, then re-import to place it." % dest, true)
		return

	var inst = null
	if res is PackedScene:
		inst = res.instantiate()
	elif res is Mesh:
		inst = MeshInstance3D.new()
		inst.mesh = res
	if inst == null:
		_set_status("Imported %s but could not instantiate it into the scene." % dest, true)
		return

	scene_root.add_child(inst)
	inst.owner = scene_root          # so it appears in the Scene dock and is saved
	_editor_interface.edit_node(inst)
	_set_status("Imported 3D model into the open scene: " + dest)

func set_editor_interface(ei) -> void:
	_editor_interface = ei

func _get_editor_filesystem():
	if _editor_interface and _editor_interface.has_method("get_resource_filesystem"):
		return _editor_interface.get_resource_filesystem()
	if Engine.has_singleton("EditorInterface"):
		var ei = Engine.get_singleton("EditorInterface")
		if ei and ei.has_method("get_resource_filesystem"):
			return ei.get_resource_filesystem()
	return null

# ──────────────────────────────────────────────────────────────────────────
#  Helpers
# ──────────────────────────────────────────────────────────────────────────
func _content_to_text(content) -> String:
	if content == null:
		return ""
	if content is String:
		return content
	if content is Dictionary:
		for k in ["text", "message", "content"]:
			if str(content.get(k, "")) != "":
				return str(content[k])
		return JSON.stringify(content)
	if content is Array:
		var parts := []
		for item in content:
			var s := _content_to_text(item)
			if s != "": parts.append(s)
		return "\n".join(parts)
	return str(content)
