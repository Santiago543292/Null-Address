@tool
class_name RapidAssetsConfig
extends RefCounted

# ============================================================================
#  Endpoint configuration (Rapid Assets dev) — same defaults as the Unity,
#  Unreal and Blender plugins.
# ============================================================================

const BACKEND_BASE_URL    := "https://rapidassets.ai/backend"     # NestJS auth / projects (prod = /backend)
const MIDDLEWARE_BASE_URL := "https://rapidassets.ai/middleware"  # Python chat / generation
const FIREBASE_API_KEY    := "AIzaSyA3notJ9UfpD_JMMhGFtC2bkLYL9O5Ai5U"

const FIREBASE_SIGNIN_URL  := "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=%s"
const FIREBASE_REFRESH_URL := "https://securetoken.googleapis.com/v1/token?key=%s"
const FIREBASE_IDP_URL     := "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=%s"

# Desktop-type OAuth client (project rapidassets-production). Per Google's model the
# secret for an installed/desktop client is non-confidential and ships in the app.
const GOOGLE_CLIENT_ID     := "991179890674-nrjl4qoklbvv2thdiqpoqotcjcusaul7.apps.googleusercontent.com"
const GOOGLE_CLIENT_SECRET := "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"
const GOOGLE_AUTH_URL      := "https://accounts.google.com/o/oauth2/v2/auth"
const GOOGLE_TOKEN_URL     := "https://oauth2.googleapis.com/token"

const REQUEST_TIMEOUT := 60.0   # seconds per HTTP request
const POLL_INTERVAL   := 2.0    # seconds between workflow-chain polls
const IMPORT_DIR      := "res://RapidAssets"  # where generated assets are saved
const PLUGIN_VERSION  := "0.2.0"              # bump on each shipped build (shown in dock)
