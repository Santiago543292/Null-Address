@tool
class_name RapidAssetsWorkflows
extends RefCounted

# ============================================================================
#  Workflow catalog — mirrors the frontend WORKFLOW_CATALOG and the Unity /
#  Unreal / Blender plugins. The `id` is the exact value sent in the /ask
#  request's `workflow` field.
# ============================================================================

static func catalog() -> Array:
	return [
		{ "id": "character_turnaround_v1",        "label": "Character Turnaround", "description": "360 turnaround sheet for any character",                "placeholder": "Describe the character's style, outfit, and proportions...", "category": "character", "requires_image": true },
		{ "id": "bg_removal_v1",                  "label": "Background Removal",   "description": "Remove backgrounds cleanly from images",               "placeholder": "Upload a reference image - background will be removed",       "category": "image",     "requires_image": true },
		{ "id": "color_palette_extraction_v1",    "label": "Color Palette",        "description": "Extract color palettes from any image",                "placeholder": "Upload a reference image to extract its palette...",         "category": "analyze",   "requires_image": true },
		{ "id": "image_analysis_v1",              "label": "Image Analysis",       "description": "Analyze and describe image contents",                  "placeholder": "Upload a reference image to analyze...",                     "category": "analyze",   "requires_image": true },
		{ "id": "style_transfer_v1",              "label": "Style Transfer",       "description": "Apply one image's style to another",                   "placeholder": "Describe the style you want to apply...",                    "category": "image",     "requires_image": false },
		{ "id": "parallel_variations",            "label": "Image Variations",     "description": "Multiple variations from a single prompt",             "placeholder": "Upload a reference image - how many variations? (1-4)",       "category": "image",     "requires_image": true },
		{ "id": "parallel_pose_edits",            "label": "Pose Variations",      "description": "Body poses from front view (T-pose, standing, running)", "placeholder": "Name poses max 4 - e.g. standing, crouching, T-pose, running", "category": "character", "requires_image": true },
		{ "id": "character_facial_pose_sheet_v1", "label": "Facial Pose Sheet",    "description": "Generate a facial expression sheet for a character",   "placeholder": "Upload a reference image - how many facial poses? (1-9)",     "category": "character", "requires_image": true },
	]

# Combo labels with a leading "None" entry at index 0.
static func combo_labels() -> Array:
	var labels := ["None"]
	for w in catalog():
		labels.append("%s  -  %s" % [w.label, _pretty_category(w.category)])
	return labels

# Maps a combo index (0 == None) back to a workflow dictionary, or {} for None.
static func from_index(index: int) -> Dictionary:
	var c := catalog()
	if index <= 0 or index > c.size():
		return {}
	return c[index - 1]

static func _pretty_category(key: String) -> String:
	match key:
		"character": return "Character"
		"image":     return "Image"
		"analyze":   return "Analyze"
		_:           return key
