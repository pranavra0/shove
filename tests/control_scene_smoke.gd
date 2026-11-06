extends SceneTree

var Tuning: Node
var WorldSim: GDScript
var _original_capture_time: float
var _original_score_target: float
var _original_score_rate: float
var _capture_dir: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _parse_capture_dir():
		return
	# --script autoloads are ready only after deferred SceneTree startup.
	Tuning = root.get_node_or_null("Tuning")
	if Tuning == null:
		_fail("Tuning autoload was unavailable after deferred startup.")
		return
	WorldSim = load("res://scripts/sim/world.gd") as GDScript
	if WorldSim == null:
		_fail("Control scene smoke could not load World simulation.")
		return
	if Tuning.get("CP_CAPTURE_TIME") == null or Tuning.get("CP_SCORE_TARGET") == null or Tuning.get("CP_SCORE_RATE") == null:
		_fail("Control tuning fields were unavailable after autoload startup.")
		return
	_original_capture_time = float(Tuning.CP_CAPTURE_TIME)
	_original_score_target = float(Tuning.CP_SCORE_TARGET)
	_original_score_rate = float(Tuning.CP_SCORE_RATE)
	# Keep capture bounded and use an integer target visible in the ordinary
	# team-score HUD. Scoring stays paused until the KO/respawn/input path passes.
	Tuning.CP_CAPTURE_TIME = 0.1
	Tuning.CP_SCORE_TARGET = 2.0
	Tuning.CP_SCORE_RATE = 0.0

	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_fail("Main scene must load for control mode smoke coverage.")
		return
	var sandbox: Node = scene.instantiate()
	if sandbox == null:
		_fail("Main scene did not instantiate.")
		return
	root.add_child(sandbox)
	current_scene = sandbox
	if not _has_main_components(sandbox):
		_fail("Main scene script/components are unavailable after attachment.")
		return
	if sandbox.get("flow").get("phase", "") != "menu" or not sandbox.get("world").is_empty():
		_fail("Startup must retain the FFA-default main menu.")
		return
	var play: Button = _button(sandbox, "PlayBots")
	if play == null:
		_fail("Main menu has no PlayBots entry.")
		return
	play.pressed.emit()
	var mode: OptionButton = sandbox.find_child("Mode", true, false) as OptionButton
	var bot_count: OptionButton = sandbox.find_child("BotCount", true, false) as OptionButton
	var start: Button = _button(sandbox, "Start")
	if mode == null or bot_count == null or start == null or mode.item_count != 2 or mode.selected != 0:
		_fail("Offline setup must expose named Mode (FFA default), BotCount, and Start.")
		return
	mode.select(1)
	mode.item_selected.emit(1)
	bot_count.select(bot_count.get_item_index(7))
	if not await _capture_checkpoint("control_setup"):
		return
	start.pressed.emit()
	var world: Dictionary = sandbox.get("world")
	if world.get("mode", "") != "control" or world.get("players", {}).size() != 8:
		_fail("Selecting Control points must start eight participants in control mode.")
		return
	var team_counts: Array[int] = [0, 0]
	for player: Dictionary in world.players.values():
		var team: int = int(player.get("team", -1))
		if team < 0 or team > 1:
			_fail("Every control-mode participant must have a valid team.")
			return
		team_counts[team] += 1
	if team_counts != [4, 4] or sandbox.get("bot_ids").size() != 7:
		_fail("Control setup must create balanced 4v4 teams with seven bots.")
		return
	if sandbox.get("arena").mode != "control" or sandbox.find_child("ControlZones", true, false) == null:
		_fail("Arena mode and the ControlZones lifecycle owner were not installed before the match.")
		return
	if sandbox.get("flow").get("phase", "") != "countdown":
		_fail("Starting control mode must use the ordinary scene countdown.")
		return
	if not await _wait_phase(sandbox, "playing", int(ceil(Tuning.MATCH_COUNTDOWN / Tuning.FIXED_DELTA)) * 4 + 120):
		_fail("Control scene did not enter playing through its countdown.")
		return

	var capture_seen: bool = false
	var capture_limit: int = 1200
	for frame in range(capture_limit):
		await _frames(1)
		var current_world: Dictionary = sandbox.get("world")
		for zone: Dictionary in current_world.get("control", {}).get("zones", []):
			if int(zone.get("owner", -1)) >= 0:
				capture_seen = true
				break
		if capture_seen:
			break
	if not capture_seen:
		_fail("Production bot commands did not capture a zone through Main physics and World.step.")
		return

	# Stage the same fall fixture used by the original scene smoke; the KO itself,
	# timer, and respawn are driven by the attached scene's normal physics loop.
	var ko_events: Array[Dictionary] = []
	sandbox.world_event.connect(func(event: Dictionary) -> void:
		if str(event.get("type", "")) == "ko" and int(event.get("player", -1)) == int(sandbox.get("local_id")):
			ko_events.append(event.duplicate(true))
	)
	world = sandbox.get("world")
	var local_player: Dictionary = world.players[int(sandbox.get("local_id"))]
	local_player.stocks = 1
	local_player.position = Vector3(0.0, Tuning.KILL_PLANE - 2.0, 0.0)
	local_player.velocity = Vector3.ZERO
	local_player.on_ground = false
	var ko_seen: bool = false
	for frame in range(120):
		await _frames(1)
		world = sandbox.get("world")
		local_player = world.players[int(sandbox.get("local_id"))]
		if ko_events.size() == 1 and int(local_player.stocks) == 0 and float(local_player.get("respawn_remaining", 0.0)) > 0.0:
			ko_seen = true
			break
	if not ko_seen:
		_fail("The staged fall did not produce exactly one actual delayed zero-stock KO.")
		return

	var respawn_seen: bool = false
	for frame in range(1200):
		await _frames(1)
		world = sandbox.get("world")
		local_player = world.players[int(sandbox.get("local_id"))]
		if int(local_player.stocks) == 0 and float(local_player.get("respawn_remaining", 0.0)) <= 0.0 and WorldSim.is_player_active(local_player):
			respawn_seen = true
			break
	if not respawn_seen:
		_fail("A zero-stock control player did not become active after delayed respawn in the scene.")
		return
	if not await _wait_for_control_focus(sandbox):
		_fail("Rendered smoke requires a focused window and production mouse capture after respawn.")
		return
	# preserves production mouse-capture gating. Unit tests cover headless input rules.
	sandbox.call("_sync_cursor")
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_fail("Rendered smoke requires the focused game window to capture the mouse after respawn.")
		return
	Input.action_press("shove")
	var local_id: int = int(sandbox.get("local_id"))
	var attack_serial_before: int = int(sandbox.get("world").players[local_id].attack_serial)
	var input_seen: bool = false
	for frame in range(120):
		var sampled: InputCmd = sandbox.call("sample_input")
		if sampled.shove:
			input_seen = true
		await _frames(1)
		world = sandbox.get("world")
		if int(world.players[local_id].attack_serial) > attack_serial_before:
			break
	Input.action_release("shove")
	world = sandbox.get("world")
	if not input_seen or int(world.players[local_id].attack_serial) <= attack_serial_before:
		_fail("Captured post-respawn shove input did not activate a real player attack at zero stocks.")
		return

	# Enable normal positive scoring through Main's recorded live-tuning path only
	# after zero-stock physical input is proven.
	Tuning.CP_SCORE_RATE = _original_score_rate
	sandbox.call("_on_tuning_changed", "CP_SCORE_RATE", _original_score_rate)
	var winner_team: int = -1
	var winner_seen: bool = false
	for frame in range(12000):
		await _frames(1)
		world = sandbox.get("world")
		winner_team = int(world.get("control", {}).get("winner_team", -1))
		if str(sandbox.get("flow").get("phase", "")) == "winner":
			winner_seen = true
			break
	if winner_team < 0 or not winner_seen:
		_fail("Natural control scoring did not reach the actual scene team-winner UI within the bounded interval.")
		return
	var winner_heading: Label = sandbox.get("menu_panel").get_child(0) as Label
	if winner_heading == null or not winner_heading.text.contains("Team %d wins" % (winner_team + 1)):
		_fail("Offline control winner UI displayed a draw/player result instead of the winning team.")
		return
	if float(world.control.scores[winner_team]) < 1.0:
		_fail("The naturally winning team did not have a visible positive control score.")
		return
	if not await _capture_checkpoint("control_winner"):
		return
	var rematch: Button = _button(sandbox, "Rematch")
	if rematch == null:
		_fail("Actual team-winner UI did not expose Rematch.")
		return
	rematch.pressed.emit()
	world = sandbox.get("world")
	if world.get("mode", "") != "control" or sandbox.get("flow").get("phase", "") != "countdown":
		_fail("Control rematch did not preserve the selected mode through the real winner UI.")
		return
	if world.control.winner_team != -1 or world.control.scores != [0.0, 0.0]:
		_fail("Control rematch did not reset team winner and scores.")
		return
	for zone: Dictionary in world.control.zones:
		if int(zone.owner) != -1 or float(zone.progress) != 0.0:
			_fail("Control rematch did not reset capture ownership/progress.")
			return

	Tuning.CP_CAPTURE_TIME = _original_capture_time
	Tuning.CP_SCORE_TARGET = _original_score_target
	Tuning.CP_SCORE_RATE = _original_score_rate
	sandbox.call("show_menu")
	play = _button(sandbox, "PlayBots")
	if play == null:
		_fail("Fresh main menu lost the PlayBots entry.")
		return
	play.pressed.emit()
	mode = sandbox.find_child("Mode", true, false) as OptionButton
	start = _button(sandbox, "Start")
	if mode == null or start == null or mode.selected != 0:
		_fail("Fresh offline setup must default to FFA after a control rematch.")
		return
	start.pressed.emit()
	world = sandbox.get("world")
	if world.get("mode", "") != "ffa":
		_fail("Default offline start did not create an FFA world.")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	print("PASS control scene: actual mode UI/countdown/bot capture/zero-stock delayed respawn/focused input/team winner/rematch/default FFA")
	quit(0)

func _parse_capture_dir() -> bool:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	for argument: String in arguments:
		if argument.begins_with("--capture-dir="):
			_capture_dir = argument.trim_prefix("--capture-dir=")
	if _capture_dir.is_empty():
		return true
	if not _capture_dir.is_absolute_path():
		_capture_dir = ProjectSettings.globalize_path(_capture_dir if _capture_dir.begins_with("user://") else "res://" + _capture_dir)
	_capture_dir = _capture_dir.simplify_path()
	var error: Error = DirAccess.make_dir_recursive_absolute(_capture_dir)
	if error != OK:
		_fail("Cannot create capture directory '%s': %s" % [_capture_dir, error_string(error)])
		return false
	return true

func _capture_checkpoint(name: String) -> bool:
	if _capture_dir.is_empty():
		return true
	for frame in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	var texture: ViewportTexture = root.get_texture()
	if texture == null:
		_fail("Renderer returned no viewport texture for %s." % name)
		return false
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		_fail("Renderer returned an empty viewport image for %s." % name)
		return false
	var path: String = _capture_dir.path_join(name + ".png")
	var error: Error = image.save_png(path)
	if error != OK:
		_fail("Cannot save '%s': %s" % [path, error_string(error)])
		return false
	print("CAPTURE %s" % path)
	return true

func _wait_for_control_focus(owner: Node) -> bool:
	for frame in range(120):
		if owner.get_window().has_focus() and owner.call("_can_control"):
			owner.call("_sync_cursor")
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				return true
		await process_frame
	return owner.get_window().has_focus() and owner.call("_can_control") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _has_main_components(owner: Node) -> bool:
	if not owner.has_method("_can_control") or not owner.has_method("_sync_cursor") or not owner.has_method("sample_input") or not owner.has_method("_on_tuning_changed"):
		return false
	if not owner.get("flow") is Dictionary or not owner.get("world") is Dictionary:
		return false
	if not owner.get("menu_panel") is VBoxContainer or not owner.get("arena") is Node3D or not owner.get("bot_ids") is Array:
		return false
	return owner.has_signal("world_event")

func _button(owner: Node, node_name: String) -> Button:
	return owner.find_child(node_name, true, false) as Button

func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame

func _wait_phase(owner: Node, phase: String, max_frames: int) -> bool:
	for frame in range(max_frames):
		if str(owner.get("flow").get("phase", "")) == phase:
			return true
		await _frames(1)
	return str(owner.get("flow").get("phase", "")) == phase

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
