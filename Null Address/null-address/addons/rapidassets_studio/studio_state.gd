@tool
class_name RapidAssetsState
extends RefCounted

# ============================================================================
#  Persisted auth + selection state (saved to user://).
# ============================================================================

const SAVE_PATH := "user://rapidassets_studio_state.cfg"

var access_token := ""
var refresh_token := ""
var token_expires_at := 0      # unix seconds
var user_id := ""
var user_name := ""
var user_email := ""
var selected_project_id := ""
var selected_session_id := ""
var show_shared_projects := false

func is_authenticated() -> bool:
	return access_token != "" and user_id != ""

func load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	access_token        = cfg.get_value("auth", "access_token", "")
	refresh_token       = cfg.get_value("auth", "refresh_token", "")
	token_expires_at    = int(cfg.get_value("auth", "token_expires_at", 0))
	user_id             = cfg.get_value("user", "id", "")
	user_name           = cfg.get_value("user", "name", "")
	user_email          = cfg.get_value("user", "email", "")
	selected_project_id = cfg.get_value("sel", "project_id", "")
	selected_session_id = cfg.get_value("sel", "session_id", "")
	show_shared_projects = bool(cfg.get_value("sel", "show_shared", false))

func save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "access_token", access_token)
	cfg.set_value("auth", "refresh_token", refresh_token)
	cfg.set_value("auth", "token_expires_at", token_expires_at)
	cfg.set_value("user", "id", user_id)
	cfg.set_value("user", "name", user_name)
	cfg.set_value("user", "email", user_email)
	cfg.set_value("sel", "project_id", selected_project_id)
	cfg.set_value("sel", "session_id", selected_session_id)
	cfg.set_value("sel", "show_shared", show_shared_projects)
	cfg.save(SAVE_PATH)

func clear_auth() -> void:
	access_token = ""
	refresh_token = ""
	token_expires_at = 0
	user_id = ""
	user_name = ""
	user_email = ""
	selected_project_id = ""
	selected_session_id = ""
	save_state()
