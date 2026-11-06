extends SceneTree

var Tuning: Node
var World: GDScript
var Kits: GDScript

const SLOT_BITS: Dictionary = {
	"basic_shot": InputCmd.BASIC_SHOT,
	"curve_shot": InputCmd.CURVE_SHOT,
	"quick_fire": InputCmd.QUICK_FIRE,
	"high_jump": InputCmd.HIGH_JUMP,
	"down_dash": InputCmd.DOWN_DASH,
	"wall": InputCmd.WALL,
	"h_dash": InputCmd.H_DASH,
	"recovery": InputCmd.RECOVERY,
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	Kits = load("res://scripts/sim/kits.gd")
	var old_center: float = float(Tuning.CENTER_HEIGHT)
	var old_ramp: float = float(Tuning.RAMP_HEIGHT)
	var old_ledge: float = float(Tuning.LEDGE_HEIGHT)
	Tuning.CENTER_HEIGHT = 0.0
	Tuning.RAMP_HEIGHT = 0.0
	Tuning.LEDGE_HEIGHT = 0.0
	_test_move_lifecycles()
	_test_all_move_replay()
	Tuning.CENTER_HEIGHT = old_center
	Tuning.RAMP_HEIGHT = old_ramp
	Tuning.LEDGE_HEIGHT = old_ledge
	print("PASS M3 kit timing and replay")
	call_deferred("quit", 0)

func _fixture() -> Dictionary:
	var world: Dictionary = World.create([1, 2])
	_put(world.players[1], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 6.0))
	_put(world.players[2], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 2.0))
	world.players[1].yaw = 0.0
	world.players[2].yaw = PI
	return world

func _put(player: Dictionary, position: Vector3) -> void:
	player.position = position
	player.velocity = Vector3.ZERO
	player.on_ground = is_equal_approx(position.y, World.floor_height(position) + Tuning.BODY_HEIGHT * 0.5)
	player.ground_angle = World.floor_angle(position)

func _cmd(moves: int = 0, yaw: float = 0.0, pitch: float = 0.0, shove: bool = false) -> InputCmd:
	var command: InputCmd = InputCmd.new(Vector2.ZERO, false, shove, yaw)
	command.moves = moves
	command.pitch = pitch
	return command

func _count(events: Array, event_type: String) -> int:
	var total: int = 0
	for event: Variant in events:
		if str(event.get("type", "")) == event_type:
			total += 1
	return total

func _step(world: Dictionary, command: InputCmd = null) -> Dictionary:
	var commands: Dictionary = {}
	if command != null:
		commands[1] = command
	return World.step(world, commands, Tuning.FIXED_DELTA)

func _remaining_cooldown(player: Dictionary, slot: String) -> float:
	return float(player.cooldown) if slot == "shove" else float(player.cooldowns.get(slot, 0.0))

func _move_event(events: Array, slot: String) -> bool:
	for event: Dictionary in events:
		if str(event.get("type", "")) == "move" and str(event.get("slot", "")) == slot:
			return true
	return false

func _place_for_slot(player: Dictionary, slot: String) -> void:
	if slot == "recovery" or slot == "down_dash":
		_put(player, Vector3(4.0, 8.0, 6.0))
		player.on_ground = false
	else:
		_put(player, Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 6.0))

func _test_move_lifecycles() -> void:
	for element: String in Kits.ELEMENTS:
		for slot: String in Kits.SLOTS:
			var world: Dictionary = _fixture()
			var before: Dictionary = world.duplicate(true)
			World.set_element(world, 1, element)
			var config: Dictionary = Kits.move(element, slot)
			if slot == "recovery" or slot == "down_dash":
				_put(world.players[1], Vector3(4.0, 8.0, 6.0))
				world.players[1].on_ground = false
			before = world.duplicate(true)
			var windup_ticks: int = int(ceil(float(config.windup) / Tuning.FIXED_DELTA))
			var command: InputCmd = _cmd(int(SLOT_BITS.get(slot, 0)), 0.0, 0.0, slot == "shove")
			var state: Dictionary = _step(world, command)
			assert(world == before, "World.step must preserve caller world")
			if float(config.cooldown) > 0.0:
				var remaining: float = float(state.players[1].cooldown) if slot == "shove" else float(state.players[1].cooldowns.get(slot, 0.0))
				assert(is_equal_approx(remaining, float(config.cooldown)))
			if slot != "shove":
				for tick: int in range(maxi(0, windup_ticks - 1)):
					assert(state.projectiles.is_empty() and state.walls.is_empty() and int(state.players[1].recovery_used) == 0,
						"%s %s cannot activate before windup" % [element, slot])
					state = _step(state)
			match slot:
				"basic_shot", "curve_shot", "quick_fire":
					assert(_count(state.events, "move") > 0 and not _projectile(state, slot).is_empty())
					assert(is_equal_approx(float(_projectile(state, slot).duration), float(config.duration)))
				"wall":
					assert(_count(state.events, "move") > 0 and not state.walls.is_empty())
					assert(is_equal_approx(float(state.walls.values()[0].duration), float(config.duration)))
				"high_jump":
					assert(_count(state.events, "move") > 0 and state.players[1].velocity.y > 0.0)
				"down_dash":
					assert(_count(state.events, "move") > 0 and bool(state.players[1].down_dashing))
				"h_dash":
					var velocity: Vector3 = state.players[1].velocity
					assert(_count(state.events, "move") > 0 and Vector2(velocity.x, velocity.z).length() > 0.0)
				"recovery":
					assert(_count(state.events, "move") > 0 and int(state.players[1].recovery_used) == 1)
				"shove":
					assert(_count(state.events, "shove") == 1)
			var repeated: Dictionary = _step(state, command)
			assert(_count(repeated.events, "move") == 0 and _count(repeated.events, "shove") == 0,
				"%s %s cannot repeat before cooldown" % [element, slot])
			for tick: int in range(int(ceil((float(config.active) + float(config.windup)) / Tuning.FIXED_DELTA)) + 2):
				state = _step(state)
			if slot in ["basic_shot", "curve_shot", "quick_fire", "wall"]:
				assert(not is_equal_approx(float(config.active), float(config.duration)),
					"%s active cast window differs from entity lifetime" % slot)
				var lifetime_state: Dictionary = state.duplicate(true)
				_put(lifetime_state.players[2], Vector3(100.0, Tuning.BODY_HEIGHT * 0.5, 100.0))
				for age_tick: int in range(int(ceil(float(config.duration) / Tuning.FIXED_DELTA)) + 2):
					lifetime_state = _step(lifetime_state)
				if slot == "wall":
					assert(lifetime_state.walls.is_empty(), "%s wall expires at its entity lifetime" % element)
				else:
					assert(_projectile(lifetime_state, slot).is_empty(), "%s projectile expires at its entity lifetime" % element)
			if float(config.cooldown) > 0.0:
				_test_cooldown_expiry(element, slot, config, command)

func _test_cooldown_expiry(element: String, slot: String, config: Dictionary, command: InputCmd) -> void:
	var world: Dictionary = _fixture()
	World.set_element(world, 1, element)
	_place_for_slot(world.players[1], slot)
	if slot == "shove":
		world.players[1].cooldown = Tuning.FIXED_DELTA * 1.5
	else:
		world.players[1].cooldowns[slot] = Tuning.FIXED_DELTA * 1.5
	var before_expiry: Dictionary = _step(world, command)
	assert(not _move_event(before_expiry.events, slot) and _count(before_expiry.events, "shove") == 0,
		"%s %s is blocked with half a tick remaining" % [element, slot])
	_place_for_slot(before_expiry.players[1], slot)
	var started: Dictionary = _step(before_expiry, command)
	if slot == "shove":
		assert(is_equal_approx(float(started.players[1].cooldown), float(config.cooldown)))
		return
	else:
		assert(is_equal_approx(float(started.players[1].cooldowns.get(slot, 0.0)), float(config.cooldown)))
	var windup_ticks: int = int(ceil(float(config.windup) / Tuning.FIXED_DELTA))
	for tick: int in range(windup_ticks):
		if tick == windup_ticks - 1:
			break
		assert(not _move_event(started.events, slot) and _count(started.events, "shove") == 0)
		started = _step(started)
	_assert_move_activation(started, slot, config, element)

func _assert_move_activation(state: Dictionary, slot: String, config: Dictionary, element: String) -> void:
	match slot:
		"basic_shot", "curve_shot", "quick_fire":
			assert(_move_event(state.events, slot) and not _projectile(state, slot).is_empty(),
				"%s %s activates with projectile" % [element, slot])
			assert(is_equal_approx(float(_projectile(state, slot).duration), float(config.duration)))
		"wall":
			assert(_move_event(state.events, slot) and not state.walls.is_empty())
			assert(is_equal_approx(float(state.walls.values()[0].duration), float(config.duration)))
		"high_jump":
			assert(_move_event(state.events, slot) and state.players[1].velocity.y > 0.0)
		"down_dash":
			assert(_move_event(state.events, slot) and bool(state.players[1].down_dashing))
		"h_dash":
			var velocity: Vector3 = state.players[1].velocity
			assert(_move_event(state.events, slot) and Vector2(velocity.x, velocity.z).length() > 0.0)
		"recovery":
			assert(_move_event(state.events, slot) and int(state.players[1].recovery_used) > 0)
		"shove":
			assert(_count(state.events, "shove") == 1)

func _projectile(world: Dictionary, slot: String) -> Dictionary:
	for projectile: Dictionary in world.projectiles.values():
		if str(projectile.get("slot", "")) == slot and int(projectile.get("owner", 0)) == 1:
			return projectile
	return {}

func _test_all_move_replay() -> void:
	var initial: Dictionary = World.create([1, 2, 3, 4])
	var elements: Array[String] = ["earth", "water", "fire", "air"]
	for index: int in range(4):
		var player_id: int = index + 1
		_put(initial.players[player_id], Vector3(float(index) * 3.0, Tuning.BODY_HEIGHT * 0.5, 6.0))
		initial.players[player_id].yaw = 0.0
		World.set_element(initial, player_id, elements[index])
	var initial_copy: Dictionary = initial.duplicate(true)
	var tape = load("res://scripts/dev/replay.gd").new()
	tape.begin(initial, {})
	var live: Dictionary = initial
	var activated: Dictionary = {}
	var slots: Array[String] = ["basic_shot", "curve_shot", "quick_fire", "shove", "wall", "h_dash", "high_jump", "recovery", "down_dash"]
	var recorded_worlds: Array[Dictionary] = []
	for player_index: int in range(4):
		var player_id: int = player_index + 1
		for slot: String in slots:
			var move_data: Dictionary = Kits.move(elements[player_index], slot)
			var command: InputCmd = _cmd(int(SLOT_BITS.get(slot, 0)), 0.0, 0.0, slot == "shove")
			tape.record({player_id: command})
			live = World.step(live, {player_id: command}, Tuning.FIXED_DELTA)
			recorded_worlds.append(live)
			_collect_activations(live.events, player_id, activated)
			var ticks_to_wait: int = int(ceil((float(move_data.windup) + float(move_data.active)) / Tuning.FIXED_DELTA)) + 2
			for tick: int in range(ticks_to_wait):
				tape.record({})
				live = World.step(live, {}, Tuning.FIXED_DELTA)
				recorded_worlds.append(live)
				_collect_activations(live.events, player_id, activated)
	tape.finish(live)
	assert(initial == initial_copy, "World.step must not mutate replay initial world")
	for player_id: int in [1, 2, 3, 4]:
		for slot: String in slots:
			assert(activated.has("%s:%s" % [player_id, slot]), "%s did not actually activate %s" % [player_id, slot])
	var replayed: Dictionary = tape.restart()
	var frame_count: int = 0
	while tape.has_next():
		replayed = World.step(replayed, tape.next_commands(), Tuning.FIXED_DELTA)
		assert(replayed == recorded_worlds[frame_count], "Replay frame %d must match recording" % frame_count)
		frame_count += 1
	assert(frame_count == tape.frames.size() and replayed == tape.final_world)
	var path: String = "user://kit-test-replay.json"
	assert(tape.save(path) == OK)
	var loaded = load("res://scripts/dev/replay.gd").new()
	assert(loaded.load_file(path) == OK and loaded.frames == tape.frames)
	assert(loaded.restart() == tape.initial_world)
	assert(load("res://scripts/dev/replay.gd")._valid_world(live))

func _collect_activations(events: Array, player_id: int, activated: Dictionary) -> void:
	for event: Dictionary in events:
		if str(event.get("type", "")) == "move":
			activated["%s:%s" % [player_id, str(event.get("slot", ""))]] = true
		elif str(event.get("type", "")) == "shove":
			activated["%s:shove" % player_id] = true
