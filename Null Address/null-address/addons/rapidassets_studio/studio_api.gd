@tool
class_name RapidAssetsApi
extends RefCounted

# ============================================================================
#  Async HTTP client for the Game AI Studio backend + middleware.
#  Every method returns a Dictionary via `await`. HTTPRequest nodes are created
#  under `host` (must be inside the scene tree) and freed after each call.
# ============================================================================

# Cloudflare's Browser Integrity Check on rapidassets.ai 403s non-browser
# User-Agents (Godot's default is "GodotEngine/..."), so every request —
# API calls and asset downloads alike — must identify as a real browser.
const _BROWSER_UA := "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

var host: Node
var state: RapidAssetsState

func _init(p_host: Node, p_state: RapidAssetsState) -> void:
	host = p_host
	state = p_state

# ── Low-level request (text body) ─────────────────────────────────────────
func _request(method: int, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
	var http := HTTPRequest.new()
	host.add_child(http)
	http.timeout = RapidAssetsConfig.REQUEST_TIMEOUT
	headers.append(_BROWSER_UA)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return { "ok": false, "code": 0, "error": "Request failed to start (%d)" % err }
	var res = await http.request_completed
	http.queue_free()
	return _wrap(res)

# ── Low-level request (raw bytes body, for multipart upload) ───────────────
func _request_raw(method: int, url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	var http := HTTPRequest.new()
	host.add_child(http)
	http.timeout = RapidAssetsConfig.REQUEST_TIMEOUT
	headers.append(_BROWSER_UA)
	var err := http.request_raw(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return { "ok": false, "code": 0, "error": "Upload failed to start (%d)" % err }
	var res = await http.request_completed
	http.queue_free()
	return _wrap(res)

func _wrap(res: Array) -> Dictionary:
	# res = [result, response_code, headers, body]
	var code: int = res[1]
	var bytes: PackedByteArray = res[3]
	var text := bytes.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	return {
		"ok": code >= 200 and code < 300,
		"code": code,
		"json": parsed,
		"raw": text,
	}

func _err(r: Dictionary) -> String:
	if r.has("error"):
		return str(r.error)
	if r.json is Dictionary:
		for k in ["message", "detail", "error"]:
			if r.json.has(k) and str(r.json[k]) != "":
				return "%d: %s" % [r.code, str(r.json[k])]
	return "HTTP %d" % r.code

# ── Token refresh ──────────────────────────────────────────────────────────
func _ensure_token() -> String:
	if state.refresh_token == "":
		return state.access_token
	if state.token_expires_at - 60 > int(Time.get_unix_time_from_system()):
		return state.access_token

	var url := RapidAssetsConfig.FIREBASE_REFRESH_URL % RapidAssetsConfig.FIREBASE_API_KEY
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded", "Accept: application/json"])
	var body := "grant_type=refresh_token&refresh_token=" + state.refresh_token.uri_encode()
	var r := await _request(HTTPClient.METHOD_POST, url, headers, body)
	if r.ok and r.json is Dictionary:
		state.access_token = str(r.json.get("id_token", state.access_token))
		var rt := str(r.json.get("refresh_token", ""))
		if rt != "":
			state.refresh_token = rt
		var ein := int(str(r.json.get("expires_in", "3600")))
		state.token_expires_at = int(Time.get_unix_time_from_system()) + ein
		state.save_state()
	return state.access_token

func _auth_request(method: int, url: String, json_body: String = "") -> Dictionary:
	var token := await _ensure_token()
	var headers := PackedStringArray(["Accept: application/json"])
	if json_body != "":
		headers.append("Content-Type: application/json")
	if token != "":
		headers.append("Authorization: Bearer " + token)
	return await _request(method, url, headers, json_body)

# ── Sign in (Firebase REST + Nest /auth/firebase-login) ────────────────────
func sign_in(email: String, password: String) -> Dictionary:
	var url := RapidAssetsConfig.FIREBASE_SIGNIN_URL % RapidAssetsConfig.FIREBASE_API_KEY
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var payload := JSON.stringify({ "email": email, "password": password, "returnSecureToken": true })
	var r := await _request(HTTPClient.METHOD_POST, url, headers, payload)
	if not r.ok or not (r.json is Dictionary):
		return { "ok": false, "error": _err(r) }

	var fb: Dictionary = r.json
	var id_token := str(fb.get("idToken", ""))
	if id_token == "":
		return { "ok": false, "error": "Firebase sign-in did not return an ID token." }

	return await _finish_sign_in(fb, id_token, email)

# Shared tail of every sign-in flow: link the Firebase user with the Nest backend
# and persist the session. `fb` is the Firebase auth response (signInWithPassword
# or signInWithIdp — both use the same field names).
func _finish_sign_in(fb: Dictionary, id_token: String, fallback_email: String) -> Dictionary:
	var nurl := RapidAssetsConfig.BACKEND_BASE_URL + "/auth/firebase-login"
	var nheaders := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var nr := await _request(HTTPClient.METHOD_POST, nurl, nheaders, JSON.stringify({ "idToken": id_token }))

	var uid := str(fb.get("localId", ""))
	var uname := str(fb.get("displayName", ""))
	var uemail := str(fb.get("email", fallback_email))
	if nr.ok and nr.json is Dictionary and nr.json.has("user") and nr.json["user"] is Dictionary:
		var u: Dictionary = nr.json["user"]
		if str(u.get("id", "")) != "":    uid = str(u.id)
		if str(u.get("name", "")) != "":  uname = str(u.name)
		if str(u.get("email", "")) != "": uemail = str(u.email)

	state.access_token = id_token
	state.refresh_token = str(fb.get("refreshToken", ""))
	var ein := int(str(fb.get("expiresIn", "3600")))
	state.token_expires_at = int(Time.get_unix_time_from_system()) + ein
	state.user_id = uid
	state.user_name = uname
	state.user_email = uemail
	state.save_state()
	return { "ok": true }

# ── Google sign-in (loopback OAuth -> Firebase signInWithIdp) ───────────────
# Same flow as the Unity/Unreal plugins: open the system browser on Google's
# consent screen with a 127.0.0.1 redirect, catch the code on a local TCP
# socket, exchange it for a Google id_token, then sign in to Firebase with it.
func sign_in_google() -> Dictionary:
	# 1. Loopback listener on a free port.
	var server := TCPServer.new()
	var port := -1
	for p in range(53682, 53782):
		if server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	if port == -1:
		return { "ok": false, "error": "Could not open a local port for Google sign-in." }

	var redirect := "http://127.0.0.1:%d" % port
	var state_token := "%d%d" % [randi(), Time.get_ticks_usec()]
	var auth_url := RapidAssetsConfig.GOOGLE_AUTH_URL + "?" + "&".join(PackedStringArray([
		"client_id=" + RapidAssetsConfig.GOOGLE_CLIENT_ID.uri_encode(),
		"redirect_uri=" + redirect.uri_encode(),
		"response_type=code",
		"scope=" + "openid email profile".uri_encode(),
		"state=" + state_token,
		"prompt=select_account",
	]))
	OS.shell_open(auth_url)

	# 2. Wait (up to 3 minutes) for the browser to hit the redirect with ?code=...
	var code := ""
	var waited := 0.0
	while waited < 180.0:
		if server.is_connection_available():
			var peer := server.take_connection()
			var tries := 0
			while peer.get_available_bytes() == 0 and tries < 50:
				peer.poll()
				await host.get_tree().create_timer(0.05).timeout
				tries += 1
			var req := ""
			if peer.get_available_bytes() > 0:
				req = peer.get_utf8_string(peer.get_available_bytes())
			var page := "<html><body style=\"font-family:sans-serif\"><h3>Sign-in complete.</h3>You can close this tab and return to Godot.</body></html>"
			var resp := "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s" % [page.to_utf8_buffer().size(), page]
			peer.put_data(resp.to_utf8_buffer())
			peer.disconnect_from_host()

			var line := req.get_slice("\r\n", 0)
			if line.contains("code="):
				var qs := line.get_slice(" ", 1).get_slice("?", 1)
				var got_state := ""
				for kv in qs.split("&"):
					var k := kv.get_slice("=", 0)
					if k == "code":
						code = kv.get_slice("=", 1).uri_decode()
					elif k == "state":
						got_state = kv.get_slice("=", 1)
				if got_state != state_token:
					server.stop()
					return { "ok": false, "error": "Google sign-in was rejected (state mismatch)." }
				break
			# Not the OAuth redirect (e.g. favicon request) — keep listening.
		await host.get_tree().create_timer(0.2).timeout
		waited += 0.2
	server.stop()
	if code == "":
		return { "ok": false, "error": "Google sign-in timed out or was cancelled." }

	# 3. Exchange the code for a Google id_token.
	var theaders := PackedStringArray(["Content-Type: application/x-www-form-urlencoded", "Accept: application/json"])
	var tbody := "&".join(PackedStringArray([
		"code=" + code.uri_encode(),
		"client_id=" + RapidAssetsConfig.GOOGLE_CLIENT_ID.uri_encode(),
		"client_secret=" + RapidAssetsConfig.GOOGLE_CLIENT_SECRET.uri_encode(),
		"redirect_uri=" + redirect.uri_encode(),
		"grant_type=authorization_code",
	]))
	var tr := await _request(HTTPClient.METHOD_POST, RapidAssetsConfig.GOOGLE_TOKEN_URL, theaders, tbody)
	if not tr.ok or not (tr.json is Dictionary):
		return { "ok": false, "error": "Google token exchange failed: " + _err(tr) }
	var gid_token := str(tr.json.get("id_token", ""))
	if gid_token == "":
		return { "ok": false, "error": "Google did not return an ID token." }

	# 4. Sign in to Firebase with the Google id_token.
	var iurl := RapidAssetsConfig.FIREBASE_IDP_URL % RapidAssetsConfig.FIREBASE_API_KEY
	var iheaders := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var ipayload := JSON.stringify({
		"postBody": "id_token=" + gid_token + "&providerId=google.com",
		"requestUri": "http://localhost",
		"returnSecureToken": true,
		"returnIdpCredential": true,
	})
	var r := await _request(HTTPClient.METHOD_POST, iurl, iheaders, ipayload)
	if not r.ok or not (r.json is Dictionary):
		return { "ok": false, "error": _err(r) }
	var fb: Dictionary = r.json
	var id_token := str(fb.get("idToken", ""))
	if id_token == "":
		return { "ok": false, "error": "Firebase did not return an ID token." }

	# 5. Backend link + session storage (same as email/password sign-in).
	return await _finish_sign_in(fb, id_token, str(fb.get("email", "")))

# ── Projects ───────────────────────────────────────────────────────────────
func get_projects(shared: bool = false) -> Dictionary:
	var t := "shared" if shared else "my"
	var url := RapidAssetsConfig.BACKEND_BASE_URL + "/api/projects?type=" + t
	var r := await _auth_request(HTTPClient.METHOD_GET, url)
	if not r.ok:
		return { "ok": false, "error": _err(r), "items": [] }
	var items := []
	if r.json is Array:
		items = r.json
	elif r.json is Dictionary:
		if r.json.has("projects"): items = r.json["projects"]
		elif r.json.has("data"):   items = r.json["data"]
	return { "ok": true, "items": items }

func create_project(name: String) -> Dictionary:
	var url := RapidAssetsConfig.BACKEND_BASE_URL + "/api/projects"
	var r := await _auth_request(HTTPClient.METHOD_POST, url, JSON.stringify({ "name": name }))
	if not r.ok:
		return { "ok": false, "error": _err(r) }
	return { "ok": true, "project": r.json }

# ── Sessions ───────────────────────────────────────────────────────────────
func get_sessions(project_id: String) -> Dictionary:
	var url := RapidAssetsConfig.MIDDLEWARE_BASE_URL + "/project/" + project_id.uri_encode() + "/sessions"
	var r := await _auth_request(HTTPClient.METHOD_GET, url)
	if not r.ok:
		return { "ok": false, "error": _err(r), "items": [] }
	var items := []
	if r.json is Dictionary and r.json.has("users") and r.json["users"] is Dictionary:
		for key in r.json["users"]:
			var arr = r.json["users"][key]
			if arr is Array:
				for s in arr:
					if s is Dictionary and str(s.get("session_id", "")) != "":
						items.append(s)
	return { "ok": true, "items": items }

# ── Session detail (load a past chat's messages) ───────────────────────────
func get_session(session_id: String) -> Dictionary:
	if session_id == "":
		return { "ok": false, "error": "No session id", "messages": [] }
	var url := RapidAssetsConfig.MIDDLEWARE_BASE_URL + "/session/" + session_id.uri_encode() + "?userId=" + state.user_id.uri_encode()
	if state.selected_project_id != "":
		url += "&projectId=" + state.selected_project_id.uri_encode()
	var r := await _auth_request(HTTPClient.METHOD_GET, url)
	if not r.ok:
		return { "ok": false, "error": _err(r), "messages": [] }
	var msgs := []
	if r.json is Dictionary and r.json.has("messages") and r.json["messages"] is Array:
		msgs = r.json["messages"]
	return { "ok": true, "messages": msgs }

# ── Ask (send prompt / run workflow) ───────────────────────────────────────
func ask(prompt: String, mode: String, workflow_id: String = "", image_urls: Array = []) -> Dictionary:
	var payload := {
		"query": prompt,
		"userId": state.user_id,
		"hitl": false,
		"mode": "thinking" if mode == "" else mode,
	}
	if state.selected_project_id != "":
		payload["projectId"] = state.selected_project_id
	if state.selected_session_id != "":
		payload["session_id"] = state.selected_session_id
	if workflow_id != "":
		payload["workflow"] = workflow_id
	if image_urls.size() > 0:
		payload["image_urls"] = image_urls

	var url := RapidAssetsConfig.MIDDLEWARE_BASE_URL + "/ask"
	var r := await _auth_request(HTTPClient.METHOD_POST, url, JSON.stringify(payload))
	if not r.ok:
		return { "ok": false, "error": _err(r) }
	return { "ok": true, "data": r.json }

# ── Image upload (multipart, matches web Studio /api/v1/upload-image) ───────
func upload_image(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { "ok": false, "error": "Image file not found: " + path }
	var ext := path.get_extension().to_lower()
	if ext == "webp":
		return { "ok": false, "error": "WebP format is not supported. Use PNG, JPEG, or GIF." }

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return { "ok": false, "error": "Could not open image file." }
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() == 0:
		return { "ok": false, "error": "Image file is empty." }

	var token := await _ensure_token()
	var boundary := "----RapidAssetsStudio" + str(Time.get_ticks_usec())
	var filename := path.get_file()
	var pre := "--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % [boundary, filename, _mime(ext)]
	var post := "\r\n--%s--\r\n" % boundary

	var body := PackedByteArray()
	body.append_array(pre.to_utf8_buffer())
	body.append_array(bytes)
	body.append_array(post.to_utf8_buffer())

	var headers := PackedStringArray([
		"Accept: application/json",
		"Content-Type: multipart/form-data; boundary=" + boundary,
	])
	if token != "":
		headers.append("Authorization: Bearer " + token)

	var url := RapidAssetsConfig.BACKEND_BASE_URL + "/api/v1/upload-image"
	var r := await _request_raw(HTTPClient.METHOD_POST, url, headers, body)
	if not r.ok:
		return { "ok": false, "error": _err(r) }
	if not (r.json is Dictionary):
		return { "ok": false, "error": "Upload endpoint returned a non-JSON response." }

	var success := true
	if r.json.has("success"):
		success = bool(r.json["success"])
	var result_url := ""
	for k in ["url", "fileUrl", "image_url"]:
		if str(r.json.get(k, "")) != "":
			result_url = str(r.json[k])
			break
	if not success or result_url == "":
		return { "ok": false, "error": "Upload endpoint did not return an image url." }
	return { "ok": true, "url": result_url }

# ── Single-job polling (normal image / model generations) ──────────────────
func poll_job(job_id: String) -> Dictionary:
	var url := RapidAssetsConfig.MIDDLEWARE_BASE_URL + "/poll-status/" + job_id.uri_encode() + "?userId=" + state.user_id.uri_encode()
	var r := await _auth_request(HTTPClient.METHOD_GET, url)
	if not r.ok:
		return { "ok": false }
	return { "ok": true, "data": r.json }

func get_generation_result(job_id: String) -> Dictionary:
	var url := RapidAssetsConfig.MIDDLEWARE_BASE_URL + "/generation-result/" + job_id.uri_encode() + "?userId=" + state.user_id.uri_encode()
	var r := await _auth_request(HTTPClient.METHOD_GET, url)
	if not r.ok:
		return { "ok": false }
	return { "ok": true, "data": r.json }

# ── Workflow chain status (non-streaming poll) ─────────────────────────────
func get_chain_status(chain_id: String) -> Dictionary:
	var url := RapidAssetsConfig.MIDDLEWARE_BASE_URL + "/workflow-chain/" + chain_id.uri_encode() + "?userId=" + state.user_id.uri_encode()
	var r := await _auth_request(HTTPClient.METHOD_GET, url)
	if not r.ok:
		return { "ok": false, "error": _err(r) }
	return { "ok": true, "data": r.json }

# ── Download raw bytes (image preview / import) ────────────────────────────
func download_bytes(url: String) -> Dictionary:
	var resolved := resolve_asset_url(url)
	var headers := PackedStringArray([_BROWSER_UA])
	# Only send our bearer token to our own backend. Google Cloud Storage signed URLs
	# authenticate via query params; an extra Authorization header makes GCS reject the
	# request ("only one authentication mechanism allowed"), so never send it there.
	if resolved.contains("rapidassets.ai"):
		var token := await _ensure_token()
		if token != "":
			headers.append("Authorization: Bearer " + token)
	var http := HTTPRequest.new()
	host.add_child(http)
	http.timeout = RapidAssetsConfig.REQUEST_TIMEOUT
	var err := http.request(resolved, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return { "ok": false, "bytes": PackedByteArray() }
	var res = await http.request_completed
	http.queue_free()
	var code: int = res[1]
	return { "ok": code >= 200 and code < 300, "bytes": res[3] }

# ── Helpers ────────────────────────────────────────────────────────────────
static func resolve_asset_url(url: String) -> String:
	if url == "" or not url.begins_with("gs://"):
		return url
	return "https://storage.googleapis.com/" + url.substr(5)

static func _mime(ext: String) -> String:
	match ext:
		"png":  return "image/png"
		"jpg", "jpeg": return "image/jpeg"
		"gif":  return "image/gif"
		"bmp":  return "image/bmp"
		"tga":  return "image/x-tga"
		_:      return "application/octet-stream"
