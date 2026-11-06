extends SceneTree

var Tuning: Node
var World: GDScript
var Kits: GDScript
var Tape: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	Kits = load("res://scripts/sim/kits.gd")
	Tape = load("res://scripts/dev/replay.gd")
	var packed: PackedScene = load("res://scenes/main.tscn")
	if not _check(packed != null, "Main scene must load"):
		return
	var app = packed.instantiate()
	root.add_child(app)
	current_scene = app
	app.selected_element = "water"
	app.start_match([1])
	app.flow.phase = "playing"
	app.paused = false
	if not await _wait_for_control_focus(app):
		_fail("Rendered input smoke could not acquire real native window focus and gameplay mouse capture.")
		return
	if not app.get_window().has_focus():
		_fail("Rendered input smoke requires a focused display window.")
		return
	app._sync_cursor()
	if not _check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Gameplay must capture the mouse in the focused window"):
		return
	app.pitch = 0.0
	var pitch_down: float = app.pitch
	app.pitch = -0.6
	var down_command: InputCmd = app.sample_input()
	if not _check(is_equal_approx(down_command.pitch, -0.6) and World.aim_direction(down_command.yaw, down_command.pitch).y < 0.0, "Negative camera pitch aims down"):
		return
	app.pitch = 0.6
	var up_command: InputCmd = app.sample_input()
	if not _check(is_equal_approx(up_command.pitch, 0.6) and World.aim_direction(up_command.yaw, up_command.pitch).y > 0.0, "Positive camera pitch aims up"):
		return
	app.pitch = pitch_down
	var actions: Array[String] = ["basic_shot", "curve_shot", "quick_fire", "shove", "high_jump", "down_dash", "wall", "h_dash", "recovery"]
	for action in actions:
		_release_all(actions)
		if action != "basic_shot":
			app.start_match([1])
			app.flow.phase = "playing"
			app.paused = false
			app._sync_cursor()
		var before_position: Vector3 = app.world.players[1].position
		if action in ["recovery", "down_dash"]:
			Input.action_press("high_jump")
			await _tick(app)
			Input.action_release("high_jump")
			await _advance(app, 10)
			before_position = app.world.players[1].position
		if action == "curve_shot":
			Input.action_press(action)
			await _tick(app)
			Input.action_release(action)
			await _tick(app)
		else:
			Input.action_press(action)
			await _tick(app)
			Input.action_release(action)
		if not _check_activation_cooldown(app, action):
			return
		if action != "shove":
			await _advance(app, _windup(action) + 2)
		else:
			await _advance(app, int(ceil(float(Tuning.SHOVE_WINDUP / Tuning.FIXED_DELTA))) + 1)
		var after_windup: Dictionary = app.world.players[1]
		if action in ["high_jump", "down_dash", "h_dash", "recovery"] and not _check(after_windup.position != before_position, "%s must produce a physical displacement" % action):
			return
		var player: Dictionary = after_windup
		match action:
			"shove":
				if not _check(float(player.attack_time) > 0.0, "Shove must activate"):
					return
			"high_jump":
				if not _check(float(player.velocity.y) > 0.0 and player.position.y > before_position.y, "High jump physically lifts player"):
					return
			"down_dash":
				if not _check(float(player.velocity.y) < 0.0, "Down dash activation must start downward"):
					return
				var dash_start_y: float = float(player.position.y)
				var landing_deadline: int = int(app.world.tick) + 180
				var landed: bool = false
				while int(app.world.tick) < landing_deadline:
					await _tick(app)
					player = app.world.players[1]
					if player.on_ground:
						landed = true
						break
				if not _check(landed and float(player.position.y) < dash_start_y, "Down dash must travel downward and land"):
					return
			"h_dash":
				if not _check(player.position != before_position, "Horizontal dash physically moves"):
					return
			"recovery":
				if not _check(int(player.recovery_used) > 0 and player.position != before_position, "Recovery must be used and move player"):
					return
		if action in ["basic_shot", "curve_shot", "quick_fire"]:
			if not _check(not app.world.projectiles.is_empty(), "%s must spawn projectile" % action):
				return
		elif action == "wall":
			if not _check(not app.world.walls.is_empty(), "Wall must spawn"):
				return
		app.kit_entities.render_world(app.world)
	if not _check(app.recording != null and app.recording.frames.size() > 0, "Input actions must be recorded"):
		return
	var expected_world: Dictionary = app.world.duplicate(true)
	app.recording.finish(app.world)
	app.latest_tape = app.recording
	app.save_replay()
	var loaded = Tape.new()
	if not _check(loaded.load_file("user://replays/latest.json") == OK, "Saved replay must load"):
		return
	var replayed: Dictionary = loaded.restart()
	while loaded.has_next():
		var commands: Dictionary = loaded.next_commands()
		replayed = World.step(replayed, commands, Tuning.FIXED_DELTA)
	if not _check(replayed == expected_world and loaded.final_world == expected_world, "Replay must reproduce the final world"):
		return
	_release_all(actions)
	app.queue_free()
	await process_frame
	print("PASS kit scene: actual InputMap actions, focused mouse capture, physical pitch, entities and replay")
	quit(0)

func _wait_for_control_focus(app) -> bool:
	var window: Window = app.get_window()
	var deadline_msec: int = Time.get_ticks_msec() + 30000
	var next_focus_request_msec: int = 0
	while Time.get_ticks_msec() < deadline_msec:
		var now_msec: int = Time.get_ticks_msec()
		if now_msec >= next_focus_request_msec:
			window.grab_focus()
			next_focus_request_msec = now_msec + 500
		if window.has_focus() and app._can_control():
			app._sync_cursor()
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				return true
		await physics_frame
		await process_frame
	return false

func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false

func _fail(message: String) -> void:
	push_error("FAIL kit scene: " + message)
	quit(1)

func _windup(action: String) -> int:
	return int(ceil(float(Kits.move("water", action).windup) / Tuning.FIXED_DELTA))

func _tick(app) -> void:
	app._sync_cursor()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_fail("Gameplay input lost focus or mouse capture")
		return
	await physics_frame
	await process_frame

func _advance(app, ticks: int) -> void:
	var target_tick: int = int(app.world.tick) + ticks
	while int(app.world.tick) < target_tick:
		await _tick(app)

func _check_activation_cooldown(app, action: String) -> bool:
	if action == "recovery":
		return true
	var player: Dictionary = app.world.players[app.local_id]
	var cooldown: float = float(player.cooldown) if action == "shove" else float(player.cooldowns.get(action, 0.0))
	return _check(cooldown > 0.0, "%s cooldown starts on activation" % action)

func _release_all(actions: Array[String]) -> void:
	for action in actions:
		if Input.is_action_pressed(action):
			Input.action_release(action)
