extends SceneTree

var Tuning: Node
var World: GDScript
var MatchSim: GDScript
var Kits: GDScript
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not root.has_node("Tuning"):
		printerr("control_test: required Tuning autoload missing")
		call_deferred("quit", 1)
		return
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	MatchSim = load("res://scripts/sim/match.gd")
	Kits = load("res://scripts/sim/kits.gd")
	if World == null or not World.can_instantiate() or MatchSim == null or not MatchSim.can_instantiate() or Kits == null or not Kits.can_instantiate():
		printerr("control_test: required simulation/kit script failed to load or parse")
		call_deferred("quit", 1)
		return
	_test_creation_and_geometry()
	_test_capture_rules()
	_test_ringout_and_scoring()
	_test_friendly_damage()
	if failures == 0:
		print("PASS control default/teams/flat capture/score/bonus/winner/ringout/friendly-fire")
	else:
		printerr("FAIL control behavioral checks: ", failures)
	call_deferred("quit", 1 if failures > 0 else 0)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("control_test: ", label)

func _ground(player: Dictionary, position: Vector3) -> void:
	player.position = Vector3(position.x, Tuning.BODY_HEIGHT * 0.5, position.z)
	player.velocity = Vector3.ZERO
	player.on_ground = true
	player.ground_angle = 0.0

func _world(ids: Array = [1, 2], mode: String = "control") -> Dictionary:
	return World.create(ids, mode)

func _team_at_zone(world: Dictionary, id: int, zone_index: int) -> void:
	var zone: Dictionary = world.control.zones[zone_index]
	_ground(world.players[id], zone.position)

func _test_creation_and_geometry() -> void:
	var ffa: Dictionary = World.create([1, 2])
	_check(ffa.get("mode", "ffa") == "ffa" and ffa.get("control", {}).is_empty(), "FFA remains default")
	var world: Dictionary = _world([1, 2, 3, 4, 5, 6, 7, 8])
	var team_zero: int = 0
	var team_one: int = 0
	var previous_team: int = -1
	var ordered_ids: Array = world.players.keys()
	ordered_ids.sort()
	for id: int in ordered_ids:
		var player: Dictionary = world.players[id]
		if previous_team >= 0:
			_check(int(player.team) != previous_team, "sorted roster alternates teams")
		previous_team = int(player.team)
		if int(player.team) == 0:
			team_zero += 1
		elif int(player.team) == 1:
			team_one += 1
	_check(team_zero == 4 and team_one == 4, "4v4 cap balance")
	_check(World.floor_height(Vector3.ZERO, "control") == 0.0, "control center is flat")
	_check(World.floor_height(Vector3(12.0, 9.0, 3.0), "control") == 0.0, "control lane is flat")
	_check(World.floor_height(Vector3(1000.0, 0.0, 0.0), "control") == -INF, "control platform has bounded edges")
	_check(world.control.zones.size() == 2 and world.control.scores.size() == 2 and int(world.control.winner_team) == -1, "two-zone state initialized")
	# Actual movement must cross the old center/ramp footprint while grounded at flat height.
	var walker: Dictionary = _world([1])
	_ground(walker.players[1], Vector3(0.0, 0.0, 8.0))
	for frame in range(240):
		walker = World.step(walker, {1: InputCmd.new(Vector2.UP)}, Tuning.FIXED_DELTA)
		if float(walker.players[1].position.z) < -8.0:
			break
	_check(float(walker.players[1].position.z) < -8.0 and walker.players[1].on_ground and is_equal_approx(float(walker.players[1].position.y), Tuning.BODY_HEIGHT * 0.5), "grounded walker crosses featureless center at flat height")
	# An input-created projectile must pass through the center and remain alive.
	var shooter_world: Dictionary = _world([1])
	_ground(shooter_world.players[1], Vector3(0.0, 0.0, 8.0))
	var passed_center: bool = false
	for frame in range(80):
		var command: InputCmd = InputCmd.new()
		if frame == 0:
			command.moves = InputCmd.BASIC_SHOT
		shooter_world = World.step(shooter_world, {1: command}, Tuning.FIXED_DELTA)
		for projectile: Variant in shooter_world.projectiles.values():
			if float(projectile.position.z) < 0.0:
				passed_center = true
	_check(passed_center, "input-created projectile crosses center without center collision")

func _test_capture_rules() -> void:
	var saved_capture: float = Tuning.CP_CAPTURE_TIME
	var saved_score_rate: float = Tuning.CP_SCORE_RATE
	Tuning.CP_CAPTURE_TIME = 0.2
	Tuning.CP_SCORE_RATE = 0.0
	var world: Dictionary = _world([1, 2, 3])
	_team_at_zone(world, 1, 0)
	_ground(world.players[2], Vector3.ZERO)
	_team_at_zone(world, 3, 1)
	world = World.step(world, {}, 0.1)
	_check(is_equal_approx(float(world.control.zones[0].progress), 0.5) and int(world.control.zones[0].capturing) == 0, "uncontested partial capture advances")
	var partial: float = float(world.control.zones[0].progress)
	world = World.step(world, {}, 0.1)
	_check(int(world.control.zones[0].owner) == 0 and is_equal_approx(float(world.control.zones[0].progress), 1.0), "capture completes and owns zone")
	# Contest freezes capture; an empty zone also freezes after every occupant leaves.
	_team_at_zone(world, 2, 0)
	world.control.zones[0].owner = -1
	world.control.zones[0].progress = partial
	world.control.zones[0].capturing = 0
	world = World.step(world, {}, 0.1)
	_check(is_equal_approx(float(world.control.zones[0].progress), partial), "contested capture freezes exactly")
	_ground(world.players[1], Vector3.ZERO)
	_ground(world.players[2], Vector3.ZERO)
	world = World.step(world, {}, 0.1)
	_check(is_equal_approx(float(world.control.zones[0].progress), partial), "empty zone freezes")
	# A different team's fresh progress must replace, not inherit, the old partial.
	_ground(world.players[1], world.control.zones[0].position)
	world.players[1].team = 1
	world.control.zones[0].capturing = 0
	world.control.zones[0].progress = 0.75
	world = World.step(world, {}, 0.02)
	_check(int(world.control.zones[0].capturing) == 1 and float(world.control.zones[0].progress) <= 0.1, "switching capturer discards old partial")
	world.control.zones[0].owner = 0
	world.control.zones[0].capturing = -1
	world.control.zones[0].progress = 0.0
	world = World.step(world, {}, 0.02)
	_check(int(world.control.zones[0].owner) == 0 and float(world.control.zones[0].progress) > 0.0, "owner retained while enemy claim advances")
	# Independently test airborne and respawning exclusions.
	var excluded: Dictionary = _world([1])
	_team_at_zone(excluded, 1, 0)
	excluded.players[1].on_ground = false
	excluded.players[1].position.y += 3.0
	excluded = World.step(excluded, {}, 0.1)
	_check(float(excluded.control.zones[0].progress) == 0.0, "airborne participant excluded")
	excluded = _world([1])
	_team_at_zone(excluded, 1, 0)
	excluded.players[1].respawn_remaining = 1.0
	excluded = World.step(excluded, {}, 0.1)
	_check(float(excluded.control.zones[0].progress) == 0.0, "respawning participant excluded")
	# Spawn a real wall via InputCmd, land a player on its top, and verify it cannot capture.
	var wall_world: Dictionary = _world([1, 2])
	var wall_zone: Dictionary = wall_world.control.zones[0]
	var wall_move: Dictionary = Kits.move("earth", "wall")
	_ground(wall_world.players[1], wall_zone.position - Vector3.FORWARD * float(wall_move.placement_distance))
	wall_world.players[1].team = 1
	var original_capture_time: float = Tuning.CP_CAPTURE_TIME
	Tuning.CP_CAPTURE_TIME = 100.0
	var wall_command: InputCmd = InputCmd.new()
	wall_command.moves = InputCmd.WALL
	for frame in range(80):
		var commands: Dictionary = {}
		if frame == 0:
			commands[1] = wall_command
		wall_world = World.step(wall_world, commands, Tuning.FIXED_DELTA)
		if not wall_world.walls.is_empty():
			break
	var wall_spawned: bool = not wall_world.walls.is_empty()
	_check(wall_spawned, "wall-top fixture spawned by actual ability input")
	if wall_spawned:
		var wall: Dictionary = wall_world.walls.values()[0]
		var zone_progress: float = float(wall_world.control.zones[0].progress)
		_ground(wall_world.players[1], Vector3.ZERO)
		var wall_top: float = wall.position.y + wall.size.y * 0.5
		wall_world.players[2].position = Vector3(wall.position.x, wall_top + Tuning.BODY_HEIGHT * 0.5 + 1.0, wall.position.z)
		wall_world.players[2].velocity = Vector3(0.0, -10.0, 0.0)
		wall_world.players[2].on_ground = false
		for frame in range(30):
			wall_world = World.step(wall_world, {}, Tuning.FIXED_DELTA)
			if wall_world.players[2].on_ground:
				break
		_check(Vector2(wall_world.players[2].position.x - wall_zone.position.x, wall_world.players[2].position.z - wall_zone.position.z).length() <= float(wall_zone.radius), "wall-top fixture remains inside capture radius")
		_check(wall_world.players[2].on_ground and wall_world.players[2].position.y - Tuning.BODY_HEIGHT * 0.5 > Tuning.CP_CAPTURE_HEIGHT, "wall-top fixture is supported above zone floor")
		_ground(wall_world.players[1], Vector3.ZERO)
		var progress_before: float = float(wall_world.control.zones[0].progress)
		Tuning.CP_CAPTURE_TIME = original_capture_time
		wall_world = World.step(wall_world, {}, 0.1)
		_check(is_equal_approx(float(wall_world.control.zones[0].progress), progress_before) and is_equal_approx(progress_before, zone_progress), "wall-top standing does not advance capture")
	Tuning.CP_CAPTURE_TIME = saved_capture
	Tuning.CP_SCORE_RATE = saved_score_rate

func _test_ringout_and_scoring() -> void:
	var saved_penalty: float = Tuning.CP_RINGOUT_PENALTY
	var saved_delay: float = Tuning.CP_RESPAWN_DELAY
	var saved_rate: float = Tuning.CP_SCORE_RATE
	var saved_target: float = Tuning.CP_SCORE_TARGET
	Tuning.CP_RINGOUT_PENALTY = 2.0
	Tuning.CP_RESPAWN_DELAY = 0.2
	Tuning.CP_SCORE_RATE = 4.0
	Tuning.CP_SCORE_TARGET = 100.0
	var world: Dictionary = _world([1, 2])
	world.control.zones[0].owner = 0
	world.control.zones[1].owner = 0
	world = World.step(world, {}, 0.1)
	_check(is_equal_approx(float(world.control.scores[0]), 0.4) and is_zero_approx(float(world.control.scores[1])), "only both-owned team scores")
	world.control.scores[0] = 0.5
	world.control.scores[1] = 5.0
	var victim_team: int = int(world.players[2].team)
	world.players[2].stocks = 1
	world.players[2].damage = 50.0
	world.players[2].hitstun = 0.5
	world.players[2].attack_time = 0.3
	world.players[2].cooldown = 0.4
	world.players[2].attack_hits = [1]
	world.players[2].cooldowns = {"basic_shot": 1.0}
	world.players[2].move_state = {"slot": "wall", "windup": 0.2, "duration": 0.3, "aim": Vector3.FORWARD, "strafe": 0.0, "activated": false}
	world.players[2].attack_serial = 7
	world.players[2].position.y = Tuning.KILL_PLANE - 1.0
	world.players[2].on_ground = false
	world = World.step(world, {}, 0.1)
	_check(int(world.players[2].stocks) == 0 and float(world.players[2].respawn_remaining) > 0.0, "ringout loses stock and begins delay")
	_check(float(world.players[2].damage) == 0.0 and float(world.players[2].hitstun) == 0.0 and float(world.players[2].attack_time) == 0.0 and float(world.players[2].cooldown) == 0.0, "ringout clears combat state")
	_check(world.players[2].attack_hits.is_empty() and world.players[2].cooldowns.is_empty() and world.players[2].move_state.is_empty() and int(world.players[2].attack_serial) == 7, "ringout clears transient abilities but preserves attack serial")
	_check(is_equal_approx(float(world.control.scores[victim_team]), 3.0), "single ringout penalty targets victim team exactly once")
	_check(is_equal_approx(float(world.control.scores[0]), 0.9), "other team's scoring continues during victim ringout")
	_check(not World.is_player_active(world.players[2]), "zero-stock player is inactive during respawn delay")
	var ko_count: int = 0
	for event: Dictionary in world.events:
		if event.type == "ko":
			ko_count += 1
	_check(ko_count == 1, "single ringout event")
	world = World.step(world, {}, 0.1)
	_check(float(world.players[2].respawn_remaining) > 0.0 and not World.is_player_active(world.players[2]), "respawn delay does not expire early")
	_check(world.events.is_empty(), "ringout penalty and KO do not repeat during delay")
	_check(is_equal_approx(float(world.control.scores[victim_team]), 3.0), "ringout penalty is not applied again during delay")
	var clamp_world: Dictionary = _world([1, 2])
	clamp_world.control.scores[1] = 0.5
	clamp_world.players[2].stocks = 1
	clamp_world.players[2].position.y = Tuning.KILL_PLANE - 1.0
	clamp_world.players[2].on_ground = false
	clamp_world = World.step(clamp_world, {}, 0.1)
	_check(is_zero_approx(float(clamp_world.control.scores[1])), "ringout penalty never makes team score negative")
	world = World.step(world, {}, 0.11)
	_check(is_zero_approx(float(world.players[2].respawn_remaining)) and float(world.players[2].invuln) > 0.0, "timer expiry respawns with invulnerability")
	_check(World.is_player_active(world.players[2]) and int(world.players[2].attack_serial) == 7, "respawned zero-stock player remains active with monotonic serial")
	var before_damage: float = float(world.players[2].damage)
	_ground(world.players[1], Vector3.ZERO)
	_ground(world.players[2], Vector3(0.0, 0.0, -1.4))
	world.players[1].yaw = 0.0
	world.players[1].attack_time = Tuning.SHOVE_ACTIVE
	world.players[1].attack_hits = []
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	_check(float(world.players[2].damage) == before_damage and float(world.players[2].invuln) > 0.0, "respawn invulnerability protects restored player")
	world.players[2].invuln = 0.0
	world.players[1].attack_time = Tuning.SHOVE_ACTIVE
	world.players[1].attack_hits = []
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	_check(float(world.players[2].damage) > before_damage, "respawned zero-stock player remains hittable")
	world.players[2].invuln = 0.0
	world.control.zones[0].owner = -1
	world.control.zones[0].capturing = -1
	world.control.zones[0].progress = 0.0
	_ground(world.players[2], world.control.zones[0].position)
	_ground(world.players[1], world.control.zones[1].position)
	world = World.step(world, {}, 0.1)
	_check(float(world.control.zones[0].progress) > 0.0, "zero-stock respawn can capture")
	Tuning.CP_SCORE_TARGET = 0.5
	world = _world([1, 2])
	world.control.zones[0].owner = 1
	world.control.zones[1].owner = 1
	world = World.step(world, {}, 0.2)
	var match_state: Dictionary = MatchSim.create()
	match_state.phase = "playing"
	match_state = MatchSim.step(match_state, world, 0.2)
	_check(int(match_state.get("winner_team", -1)) == 1, "target score chooses team winner through MatchSim")
	Tuning.CP_RINGOUT_PENALTY = saved_penalty
	Tuning.CP_RESPAWN_DELAY = saved_delay
	Tuning.CP_SCORE_RATE = saved_rate
	Tuning.CP_SCORE_TARGET = saved_target
 
func _test_friendly_damage() -> void:
	# An airborne down-dash traverses a grounded teammate without friendly damage.
	var world: Dictionary = _world([1, 2])
	_ground(world.players[2], Vector3.ZERO)
	world.players[1].position = Vector3(0.0, 2.0, 0.0)
	world.players[1].velocity = Vector3.ZERO
	world.players[1].on_ground = false
	world.players[1].team = 0
	world.players[2].team = 0
	var slam: InputCmd = InputCmd.new(Vector2.ZERO, false, false, 0.0, 0)
	slam.moves = InputCmd.DOWN_DASH
	world = World.step(world, {1: slam}, Tuning.FIXED_DELTA)
	var saw_slam: bool = false
	for frame in range(90):
		saw_slam = saw_slam or bool(world.players[1].down_dashing) or str(world.players[1].move_state.get("slot", "")) == "down_dash"
		world = World.step(world, {}, Tuning.FIXED_DELTA)
	_check(saw_slam and float(world.players[2].damage) == 0.0, "actual friendly down-dash slam cannot damage teammate")
	_ground(world.players[1], Vector3(0.0, 0.0, 0.0))
	_ground(world.players[2], Vector3(0.0, 0.0, -1.4))
	world.players[1].yaw = 0.0
	world.players[1].attack_time = Tuning.SHOVE_ACTIVE
	world.players[1].team = 0
	world.players[2].team = 0
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	_check(float(world.players[2].damage) == 0.0 and world.players[1].attack_hits.is_empty(), "friendly melee is ignored")
	# A real ability command creates a projectile that crosses its teammate unharmed.
	world = _world([1, 2])
	_ground(world.players[1], Vector3.ZERO)
	_ground(world.players[2], Vector3(0.0, 0.0, -2.0))
	world.players[1].yaw = 0.0
	world.players[1].team = 0
	world.players[2].team = 0
	var shot: InputCmd = InputCmd.new(Vector2.ZERO, false, false, 0.0, 0)
	shot.moves = InputCmd.BASIC_SHOT
	var saw_projectile_spawn: bool = false
	var passed_teammate: bool = false
	for frame in range(40):
		var commands: Dictionary = {}
		if frame == 0:
			commands[1] = shot
		world = World.step(world, commands, Tuning.FIXED_DELTA)
		for event: Dictionary in world.events:
			saw_projectile_spawn = saw_projectile_spawn or str(event.get("type", "")) == "projectile_spawn"
		for projectile: Variant in world.projectiles.values():
			passed_teammate = passed_teammate or float(projectile.position.z) < -2.5
	_check(saw_projectile_spawn and passed_teammate and float(world.players[2].damage) == 0.0, "actual friendly projectile passes through teammate without damage")
	# Compare actual hit impulses with and without ownership bonus.
	var boosted: Dictionary = _world([1, 2])
	boosted.control.zones[0].owner = 0
	boosted.control.zones[1].owner = 0
	_ground(boosted.players[1], Vector3.ZERO)
	_ground(boosted.players[2], Vector3(0.0, 0.0, -1.4))
	boosted.players[1].yaw = 0.0
	boosted.players[1].attack_time = Tuning.SHOVE_ACTIVE
	boosted = World.step(boosted, {}, Tuning.FIXED_DELTA)
	var plain: Dictionary = _world([1, 2])
	_ground(plain.players[1], Vector3.ZERO)
	_ground(plain.players[2], Vector3(0.0, 0.0, -1.4))
	plain.players[1].yaw = 0.0
	plain.players[1].attack_time = Tuning.SHOVE_ACTIVE
	plain = World.step(plain, {}, Tuning.FIXED_DELTA)
	_check(float(boosted.players[2].damage) > 0.0 and float(plain.players[2].damage) > 0.0, "both impulse fixtures produce an actual enemy hit")
	_check(is_equal_approx(float(boosted.players[2].damage), float(plain.players[2].damage)), "knockback bonus does not change damage")
	var impulse_ratio: float = boosted.players[2].velocity.length() / plain.players[2].velocity.length()
	_check(is_equal_approx(impulse_ratio, Tuning.CP_KB_BONUS), "both-owned knockback bonus matches live tuning")
