extends SceneTree

var Tuning: Node
var World: GDScript
var BotSim: GDScript
var MatchSim: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Autoloads exist only after deferred initialization in --script mode.
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	BotSim = load("res://scripts/sim/bot.gd")
	MatchSim = load("res://scripts/sim/match.gd")
	assert(World != null and BotSim != null and MatchSim != null)
	var scene: PackedScene = load("res://scenes/main.tscn")
	assert(scene != null, "Main scene must load")
	var sandbox = scene.instantiate()
	root.add_child(sandbox)
	current_scene = sandbox
	assert(sandbox.flow.phase == "menu" and sandbox.world.is_empty(), "Startup must show the menu, not silently start a match")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Menus must release the mouse")
	for button_name in ["PlayBots", "Host", "Join", "Tuning", "Quit"]:
		assert(_button(sandbox, button_name) != null, "Main menu must expose %s" % button_name)

	_button(sandbox, "Host").pressed.emit()
	assert(sandbox.flow.phase == "setup")
	assert(sandbox.find_child("PlayerName", true, false) is LineEdit)
	assert(sandbox.find_child("Port", true, false) is SpinBox)
	_button(sandbox, "Back").pressed.emit()
	_button(sandbox, "Join").pressed.emit()
	assert(sandbox.find_child("ServerAddress", true, false) is LineEdit)
	_button(sandbox, "Back").pressed.emit()
	_button(sandbox, "Tuning").pressed.emit()
	assert(sandbox.tuning_panel.is_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	sandbox.tuning_panel.set_open(false)

	_button(sandbox, "PlayBots").pressed.emit()
	assert(sandbox.flow.phase == "setup", "Play vs Bots must open setup")
	var bots: OptionButton = sandbox.find_child("BotCount", true, false)
	assert(bots.item_count == 7, "Every bot count from 1 through 7 must be selectable")
	for index in range(7):
		assert(bots.get_item_id(index) == index + 1)
	bots.select(1)
	_button(sandbox, "Start").pressed.emit()
	assert(sandbox.flow.phase == "countdown" and sandbox.flow.countdown == 3)
	assert(sandbox.world.players.size() == 3 and sandbox.bot_ids == [2, 3])
	assert(sandbox.world.tick == 0, "Countdown must not advance World")
	var neutral = sandbox.sample_input()
	assert(neutral.move == Vector2.ZERO and not neutral.jump and not neutral.shove, "Input must remain neutral outside play")

	# Escape pauses the scene-owned flow; resume uses its actual UI button.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	sandbox._unhandled_input(escape)
	assert(sandbox.paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	var paused_elapsed: float = sandbox.flow.elapsed
	await _frames(4)
	assert(sandbox.world.tick == 0 and sandbox.flow.elapsed == paused_elapsed, "Pause must freeze both World and countdown")
	_button(sandbox, "Resume").pressed.emit()
	assert(not sandbox.paused and sandbox.flow.phase == "countdown")
	await _wait_countdown(sandbox, 2)
	assert(sandbox.world.tick == 0)
	await _wait_countdown(sandbox, 1)
	assert(sandbox.world.tick == 0)
	await _wait_phase(sandbox, "playing", int(ceil(Tuning.MATCH_COUNTDOWN / Tuning.FIXED_DELTA)) + 8)

	var initial_positions: Dictionary = {}
	for player_id in sandbox.bot_ids:
		initial_positions[player_id] = sandbox.world.players[player_id].position
	var initial_tick: int = int(sandbox.world.tick)
	await _frames(24)
	assert(sandbox.world.tick > initial_tick, "Playing must advance World in physics")
	var moved: bool = false
	for player_id in sandbox.bot_ids:
		var position: Vector3 = sandbox.world.players[player_id].position
		moved = moved or position.distance_to(initial_positions[player_id]) > 0.01
	assert(moved, "Bot commands must actually move players in the scene")
	assert(not sandbox.bot_memory.is_empty(), "Scene must retain bot decision memory")

	sandbox._unhandled_input(escape)
	assert(sandbox.paused)
	var paused_tick: int = int(sandbox.world.tick)
	await _frames(4)
	assert(sandbox.world.tick == paused_tick, "Pause during play must stop World ticks")
	_button(sandbox, "Resume").pressed.emit()

	# Force an actual World KO, not a manually assigned flow phase.
	var events: Array = []
	sandbox.world_event.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	sandbox.world.players[1].invuln = 30.0
	_force_fall(sandbox.world.players[2], 2)
	await _wait_phase(sandbox, "ringout", 8)
	assert(sandbox.world.players[2].stocks == 1)
	assert(_count(events, "ko") == 1, "A World KO must be dispatched exactly once")
	var ringout_tick: int = int(sandbox.world.tick)
	await _frames(8)
	var slow_ticks: int = int(sandbox.world.tick) - ringout_tick
	assert(slow_ticks > 0 and slow_ticks < 8, "Ringout must schedule fewer fixed World ticks rather than change World dt")
	assert(_count(events, "ko") == 1, "Skipped slowmo ticks must not redispatch stale events")
	await _wait_phase(sandbox, "playing", int(ceil(Tuning.MATCH_RINGOUT_TIME / Tuning.FIXED_DELTA)) + 8)

	events.clear()
	for player_id in sandbox.bot_ids:
		_force_fall(sandbox.world.players[player_id], 1)
	await _wait_phase(sandbox, "ringout", 8)
	assert(_count(events, "ko") == 2)
	await _wait_phase(sandbox, "round_end", int(ceil(Tuning.MATCH_RINGOUT_TIME / Tuning.FIXED_DELTA)) + 8)
	var final_tick: int = int(sandbox.world.tick)
	await _wait_phase(sandbox, "winner", int(ceil(Tuning.MATCH_ROUND_END / Tuning.FIXED_DELTA)) + 8)
	assert(sandbox.flow.winner == 1, "The last player with stocks must win")
	assert(sandbox.world.tick == final_tick, "World must stop during round end and winner screens")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	_button(sandbox, "Rematch").pressed.emit()
	assert(sandbox.flow.phase == "countdown" and sandbox.world.tick == 0)
	assert(sandbox.bot_ids == [2, 3] and sandbox.bot_memory.is_empty(), "Rematch must reset bots while retaining participants")
	for player in sandbox.world.players.values():
		assert(player.stocks == Tuning.STOCKS and player.damage == 0.0)

	# Exercise the remaining setup endpoints, including practice's no-winner rule.
	sandbox.show_menu()
	_button(sandbox, "PlayBots").pressed.emit()
	bots = sandbox.find_child("BotCount", true, false)
	bots.select(6)
	_button(sandbox, "Start").pressed.emit()
	assert(sandbox.world.players.size() == 8 and sandbox.bot_ids.size() == 7)
	sandbox.show_menu()
	_button(sandbox, "PlayBots").pressed.emit()
	var solo: CheckButton = sandbox.find_child("SoloPractice", true, false)
	solo.button_pressed = true
	bots = sandbox.find_child("BotCount", true, false)
	assert(bots.disabled)
	_button(sandbox, "Start").pressed.emit()
	assert(sandbox.world.players.size() == 1 and sandbox.bot_ids.is_empty())
	await _wait_phase(sandbox, "playing", int(ceil(Tuning.MATCH_COUNTDOWN / Tuning.FIXED_DELTA)) + 8)
	await _frames(8)
	assert(sandbox.flow.phase == "playing", "Solo practice must not immediately declare a winner")
	sandbox._unhandled_input(escape)
	_button(sandbox, "MainMenu").pressed.emit()
	assert(sandbox.flow.phase == "menu" and sandbox.world.is_empty())
	assert(sandbox.player_views.is_empty() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	print("PASS offline scene: menu/setup/1–7 bots/solo/countdown/physics movement/pause/KO slowmo/winner/rematch")
	call_deferred("quit", 0)

func _button(sandbox: Node, node_name: String) -> Button:
	var button := sandbox.find_child(node_name, true, false) as Button
	assert(button != null, "Expected UI button %s" % node_name)
	return button

func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
	# physics_frame precedes node physics callbacks; finish the final frame.
	await process_frame

func _wait_countdown(sandbox: Node, number: int) -> void:
	for frame in range(int(ceil(1.0 / Tuning.FIXED_DELTA)) + 8):
		if sandbox.get("flow").countdown == number:
			assert(sandbox.get("flow").phase == "countdown")
			return
		await _frames(1)
	assert(false, "Countdown did not display %d" % number)

func _wait_phase(sandbox: Node, phase: String, max_frames: int) -> void:
	for frame in range(max_frames):
		if sandbox.get("flow").phase == phase:
			return
		await _frames(1)
	assert(false, "Scene did not reach phase %s (got %s)" % [phase, sandbox.get("flow").phase])

func _force_fall(player: Dictionary, stocks: int) -> void:
	player.stocks = stocks
	player.position = Vector3(Tuning.PLATFORM_SIZE, Tuning.KILL_PLANE - 2.0, 0.0)
	player.velocity = Vector3.ZERO
	player.on_ground = false

func _count(events: Array, type: String) -> int:
	var count: int = 0
	for event in events:
		if event.type == type:
			count += 1
	return count
