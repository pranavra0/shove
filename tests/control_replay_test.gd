extends SceneTree

var Tuning: Node
var World: GDScript
var Tape: GDScript
var Store: GDScript
var failures: int = 0

const REPLAY_PATH: String = "user://control_replay_test.json"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not root.has_node("Tuning"):
		printerr("control_replay_test: required Tuning autoload missing")
		call_deferred("quit", 1)
		return
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	Tape = load("res://scripts/dev/replay.gd")
	Store = load("res://scripts/dev/tuning_store.gd")
	if World == null or not World.can_instantiate() or Tape == null or not Tape.can_instantiate() or Store == null or not Store.can_instantiate():
		printerr("control_replay_test: required simulation/persistence script failed to load or parse")
		call_deferred("quit", 1)
		return
	var original: Dictionary = Store.snapshot()
	_test_control_replay()
	Store.apply(original)
	if failures == 0:
		print("PASS control replay mode/team/capture/KO/respawn/live tuning patch exactness")
	else:
		printerr("FAIL control replay behavioral checks: ", failures)
	call_deferred("quit", 1 if failures > 0 else 0)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("control_replay_test: ", label)

func _test_control_replay() -> void:
	var initial: Dictionary = World.create([1, 2, 3], "control")
	var zone: Dictionary = initial.control.zones[0]
	var player: Dictionary = initial.players[1]
	player.position = Vector3(zone.position.x, Tuning.BODY_HEIGHT * 0.5, zone.position.z)
	player.velocity = Vector3.ZERO
	player.on_ground = true
	player.ground_angle = 0.0
	var second_zone: Dictionary = initial.control.zones[1]
	var second_capturer: Dictionary = initial.players[3]
	second_capturer.position = Vector3(second_zone.position.x, Tuning.BODY_HEIGHT * 0.5, second_zone.position.z)
	second_capturer.velocity = Vector3.ZERO
	second_capturer.on_ground = true
	second_capturer.ground_angle = 0.0
	var out_player: Dictionary = initial.players[2]
	out_player.position = Vector3(100.0, Tuning.KILL_PLANE - 1.0, 100.0)
	out_player.stocks = 1
	out_player.on_ground = false
	var tape: Variant = Tape.new()
	tape.begin(initial, Store.snapshot())
	var world: Dictionary = initial
	var saw_capture: bool = false
	var saw_score: bool = false
	var saw_ko: bool = false
	var saw_respawn: bool = false
	for tick: int in range(40):
		var patch: Dictionary = {}
		if tick == 0:
			patch = {"CP_CAPTURE_TIME": 0.1, "CP_RESPAWN_DELAY": 0.02, "CP_SCORE_RATE": 20.0}
			Store.apply(patch)
		var commands: Dictionary = {1: InputCmd.new(Vector2.ZERO, false, false, 0.0, tick), 2: InputCmd.new(Vector2.ZERO, false, false, 0.0, tick)}
		tape.record(commands, patch)
		world = World.step(world, commands, Tuning.FIXED_DELTA)
		saw_capture = saw_capture or (int(world.control.zones[0].owner) == 0 and int(world.control.zones[1].owner) == 0)
		saw_score = saw_score or float(world.control.scores[0]) > 0.0
		for event: Dictionary in world.events:
			if event.type == "ko" and int(event.player) == 2:
				saw_ko = true
		saw_respawn = saw_respawn or (int(world.players[2].stocks) == 0 and float(world.players[2].respawn_remaining) <= 0.0 and float(world.players[2].invuln) > 0.0)
	tape.finish(world)
	_check(saw_capture, "recorded steps produced actual zone captures")
	_check(saw_score, "recorded steps produced actual team scoring")
	_check(saw_ko and saw_respawn, "recorded steps produced KO and delayed respawn")
	var save_result: Error = tape.save(REPLAY_PATH)
	if save_result != OK:
		_check(false, "control replay serializes: %s" % error_string(save_result))
		_cleanup_replay()
		return
	var loaded: Variant = Tape.new()
	var load_result: Error = loaded.load_file(REPLAY_PATH)
	if load_result != OK:
		_check(false, "control replay loads: %s" % error_string(load_result))
		_cleanup_replay()
		return
	Tuning.CP_LANE_OFFSET = 6.0
	Store.apply(loaded.settings)
	var replayed: Dictionary = loaded.restart()
	var replay_saw_capture: bool = false
	var replay_saw_score: bool = false
	var replay_saw_respawn: bool = false
	while loaded.has_next():
		var commands: Dictionary = loaded.next_commands()
		Store.apply(loaded.frame_settings)
		replayed = World.step(replayed, commands, Tuning.FIXED_DELTA)
		replay_saw_capture = replay_saw_capture or (int(replayed.control.zones[0].owner) == 0 and int(replayed.control.zones[1].owner) == 0)
		replay_saw_score = replay_saw_score or float(replayed.control.scores[0]) > 0.0
		replay_saw_respawn = replay_saw_respawn or (int(replayed.players[2].stocks) == 0 and float(replayed.players[2].respawn_remaining) <= 0.0 and float(replayed.players[2].invuln) > 0.0)
	_check(replay_saw_capture and replay_saw_score and replay_saw_respawn, "loaded settings restore layout for actual replay capture, scoring, and respawn")
	_check(replayed == loaded.final_world and replayed == world, "mode/team/zone/timer/scoring state replays exactly")
	_cleanup_replay()

func _cleanup_replay() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(REPLAY_PATH)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
