extends SceneTree
## Run with a real rendering display, for example:
## godot --path . --script tools/screenshot.gd -- --scenario=all --output=/tmp/shove-captures
## --headless uses the dummy renderer and cannot capture the game's viewport.
## --hold keeps the rendered game window open after capture for manual inspection.

const CAPTURE_SIZE := Vector2i(1280, 800)
const SCENARIOS := ["menu", "arena", "character", "bhop", "impact", "ko", "hud", "tuning", "debug", "countdown", "winner", "projectile", "earth", "water", "fire", "air", "spike", "wall_block", "deflect", "tuning_element", "dummy", "trajectory"]
const SETTLE_FRAMES := 3

var _scenario := "all"
var _output := "user://screenshots"
var _hold := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _parse_arguments():
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		_fail("Viewport capture requires an actual rendering window; --headless uses the dummy renderer. Run on a display (or a GPU-backed virtual display) without --headless.")
		return

	var output_path := ProjectSettings.globalize_path(_output).simplify_path()
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path)
	if directory_error != OK:
		_fail("Cannot create screenshot directory '%s': %s" % [output_path, error_string(directory_error)])
		return

	root.size = CAPTURE_SIZE
	root.content_scale_size = CAPTURE_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.title = "SHOVE / viewport capture"
	root.position = DisplayServer.screen_get_position() + Vector2i(32, 32)

	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	var scene := load(scene_path) as PackedScene
	if scene == null:
		_fail("Cannot load the configured main scene: %s" % scene_path)
		return
	var app := scene.instantiate()
	if app == null:
		_fail("Cannot instantiate the configured main scene: %s" % scene_path)
		return
	root.add_child(app)
	current_scene = app
	await process_frame
	if not app.has_method("capture_scenario"):
		_fail("Main scene does not implement capture_scenario(name).")
		return

	var selected: Array = SCENARIOS if _scenario == "all" else [_scenario]
	for scenario: String in selected:
		var result: Variant = await app.call("capture_scenario", scenario)
		if result is Dictionary:
			if not result.get("available", false):
				_fail("Capture scenario '%s' is unavailable: %s" % [scenario, result.get("reason", "no reason supplied")])
				return
		elif result != true:
			_fail("Main scene failed to prepare capture scenario '%s'." % scenario)
			return
		# Await completed rendering, not a wall-clock delay or just physics ticks.
		# The main scene supplies a deterministic, held scenario pose.
		for frame in range(SETTLE_FRAMES):
			await process_frame
			await RenderingServer.frame_post_draw
		var texture := root.get_texture()
		if texture == null:
			_fail("Renderer returned no viewport texture for '%s'. Use a real rendering display, not a headless dummy renderer." % scenario)
			return
		var image := texture.get_image()
		if image == null or image.is_empty():
			_fail("Renderer returned an empty viewport image for '%s'. Use a real rendering display, not a headless dummy renderer." % scenario)
			return
		if image.get_size() != CAPTURE_SIZE:
			_fail("Viewport for '%s' was %s instead of the required %s." % [scenario, image.get_size(), CAPTURE_SIZE])
			return
		var path := output_path.path_join(scenario + ".png")
		var save_error := image.save_png(path)
		if save_error != OK:
			_fail("Cannot save '%s': %s" % [path, error_string(save_error)])
			return
		print("CAPTURE %s" % path)

	if _hold:
		print("Capture complete. Window held open for manual inspection; close the window to exit.")
	else:
		quit(0)


func _parse_arguments() -> bool:
	# Accept options both before and after Godot's '--' separator.
	var arguments := OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	for argument: String in arguments:
		if argument.begins_with("--scenario="):
			_scenario = argument.trim_prefix("--scenario=")
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument == "--hold":
			_hold = true
	if _scenario != "all" and not SCENARIOS.has(_scenario):
		push_error("Unknown capture scenario '%s'. Expected all, %s." % [_scenario, ", ".join(SCENARIOS)])
		return false
	if _output.is_empty() or (not _output.is_absolute_path() and not _output.begins_with("user://")):
		push_error("--output must name an absolute directory (default: user://screenshots).")
		return false
	return true


func _fail(message: String) -> void:
	push_error("Screenshot capture failed: " + message)
	quit(1)
