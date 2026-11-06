extends SceneTree

var Tuning: Node
var World: GDScript
var Prediction: GDScript
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	Prediction = load("res://scripts/net/prediction.gd")
	_test_movement_ownership_and_combat()
	_test_ack_replay_and_stale()
	_test_interpolation_and_discontinuity()
	_test_smoothing_and_cap()
	if failures == 0:
		print("PASS network prediction movement/purity/no-combat/ACK/replay/stale/interpolation/yaw/respawn/smoothing/cap")
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _fixture() -> Dictionary:
	var world: Dictionary = World.create([1, 2])
	for id in world.players:
		var player: Dictionary = world.players[id]
		player.position = Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 6.0 - (int(id) - 1) * 1.0)
		player.spawn = player.position
		player.velocity = Vector3.ZERO
		player.on_ground = true
		player.ground_angle = 0.0
	world.next_entity_id = 3
	world.projectiles[1] = {"id": 1, "position": Vector3(0.0, 1.0, 0.0), "velocity": Vector3.RIGHT, "owner": 2, "element": "earth", "slot": "basic_shot", "age": 0.1, "deflections": 0, "behavior": "level", "damage": 5.0, "kb_base": 4.0, "kb_scale": 0.2, "momentum": Vector3.ZERO, "size": 0.5, "duration": 2.0, "hitstun": 0.2, "kb_up": 1.0, "curve": 0.0, "gravity": 0.0, "homing": 0.0, "bounce_count": 0, "hit_ids": [], "spike_pop_speed": 0.0, "spike_damage_mult": 1.0, "spike_kb_mult": 1.0}
	world.walls[2] = {"id": 2, "position": Vector3(2.0, 1.0, 0.0), "size": Vector3(1.0, 2.0, 0.5), "owner": 2, "element": "water", "age": 0.1, "duration": 4.0, "hp": 2, "hit_shoves": {}}
	return world

func _test_movement_ownership_and_combat() -> void:
	var world: Dictionary = _fixture()
	var before: Dictionary = world.duplicate(true)
	var prediction: RefCounted = Prediction.new()
	prediction.begin(world, 1, 0.0)
	var command: InputCmd = InputCmd.new(Vector2.RIGHT, false, true, 0.0, 1)
	var moved: Dictionary = prediction.advance(command, 1.0 / 64.0)
	_check(moved.players[1].position.x > world.players[1].position.x, "local movement advances")
	_check(moved.players[1].attack_time > 0.0, "local windup is predicted")
	_check(world == before, "begin and advance preserve input world")
	_check(moved.projectiles == before.projectiles and moved.walls == before.walls and moved.next_entity_id == before.next_entity_id, "prediction preserves authoritative entities and allocation state")
	command.move = Vector2.LEFT
	var wire: Array = prediction.unacknowledged()
	_check(float(wire[0].move[0]) == 1.0, "queued input owns immutable command wire")
	wire[0].move[0] = -0.5
	_check(float(prediction.unacknowledged()[0].move[0]) == 1.0, "wire return is independently owned")
	moved.players[1].position = Vector3.ZERO
	moved.projectiles[1].position = Vector3.ZERO
	_check(prediction.predicted.projectiles[1].position == before.projectiles[1].position, "prediction return independently owns nested projectile state")
	_check(prediction.predicted.players[1].position != Vector3.ZERO, "advance return independently owns state")
	for tick in range(2, 40):
		prediction.advance(InputCmd.new(Vector2.ZERO, false, false, 0.0, tick), 1.0 / 64.0)
	_check(prediction.predicted.players[2].damage == 0.0, "predicted shove cannot deal damage")
	_check(prediction.predicted.players[1].attack_hits.is_empty(), "predicted shove cannot claim hits")
	_check(prediction.predicted.events.is_empty(), "prediction emits no authoritative combat or presentation events")
	_check(prediction.predicted.projectiles == before.projectiles and prediction.predicted.walls == before.walls and prediction.predicted.next_entity_id == before.next_entity_id, "predicted combat cannot mutate authoritative entity state")
	var falling: Dictionary = _fixture()
	falling.players[1].position = Vector3(0.0, Tuning.KILL_PLANE - 1.0, 0.0)
	falling.players[1].on_ground = false
	prediction.begin(falling, 1, 0.0)
	prediction.advance(InputCmd.new(Vector2.ZERO, false, false, 0.0, 1), 1.0 / 64.0)
	_check(prediction.predicted.players[1].stocks == falling.players[1].stocks, "client cannot award a KO")
	_check(prediction.predicted.players[1].position != falling.players[1].spawn, "client cannot predict respawn")

func _test_ack_replay_and_stale() -> void:
	var initial: Dictionary = _fixture()
	var prediction: RefCounted = Prediction.new()
	prediction.begin(initial, 1, 0.0)
	var first: InputCmd = InputCmd.new(Vector2.RIGHT, false, false, 0.2, 1)
	var second: InputCmd = InputCmd.new(Vector2.DOWN, false, false, 0.4, 2)
	prediction.advance(first, 0.02)
	prediction.advance(second, 0.03)
	var authoritative: Dictionary = World.step(initial, {1: first}, 0.02)
	authoritative.players[1].position.x -= 0.2
	var expected: Dictionary = World.step(authoritative, {1: second}, 0.03)
	prediction.reconcile(authoritative, 1, 0.1)
	_check(prediction.pending.size() == 1 and int(prediction.pending[0].tick) == 2, "ACK removes only acknowledged inputs")
	_check(prediction.predicted.players[1].position.is_equal_approx(expected.players[1].position), "reconciliation replays remaining input with original duration")
	var reconciled: Dictionary = prediction.predicted.duplicate(true)
	var stale: Dictionary = initial.duplicate(true)
	prediction.reconcile(stale, 0, 0.2)
	_check(prediction.predicted == reconciled, "old snapshot and ACK ignored")
	stale.tick = 100
	prediction.reconcile(stale, 0, 0.3)
	_check(prediction.predicted == reconciled, "ACK regression ignored despite newer world tick")
	authoritative.tick = 2
	prediction.reconcile(authoritative, 2, 0.4)
	_check(prediction.pending.is_empty(), "complete ACK clears queue")
	var saved: Dictionary = prediction.predicted.duplicate(true)
	prediction.advance(second, 0.03)
	_check(prediction.predicted == saved, "duplicate sequence cannot advance prediction")

func _test_interpolation_and_discontinuity() -> void:
	var a: Dictionary = _fixture()
	a.players[2].yaw = deg_to_rad(170.0)
	var prediction: RefCounted = Prediction.new()
	prediction.begin(a, 1, 1.0)
	var b: Dictionary = a.duplicate(true)
	b.tick = 1
	b.projectiles[1].position.x = 2.0
	b.projectiles[1].velocity = Vector3(3.0, 0.0, 0.0)
	b.projectiles[3] = {"id": 3, "position": Vector3(9.0, 1.0, 0.0), "velocity": Vector3.ZERO, "owner": 2, "element": "fire", "slot": "curve_shot", "age": 0.0, "deflections": 0, "behavior": "spike", "damage": 7.0, "kb_base": 4.0, "kb_scale": 0.2, "momentum": Vector3.ZERO, "size": 0.5, "duration": 2.0, "hitstun": 0.2, "kb_up": 1.0, "curve": 0.0, "gravity": 0.0, "homing": 0.0, "bounce_count": 0, "hit_ids": [], "spike_pop_speed": 0.0, "spike_damage_mult": 1.0, "spike_kb_mult": 1.0}
	b.players[2].position.x += 2.0
	b.players[2].yaw = deg_to_rad(-170.0)
	prediction.reconcile(b, 0, 1.2)
	var rendered: Dictionary = prediction.render_world(1.1 + Tuning.NET_INTERPOLATION, 0.0)
	_check(is_equal_approx(rendered.players[2].position.x, 5.0), "remote position interpolates snapshot bracket")
	_check(is_equal_approx(rendered.projectiles[1].position.x, 1.0) and is_equal_approx(rendered.projectiles[1].velocity.x, 2.0), "same projectile ID interpolates position and velocity")
	_check(not rendered.projectiles.has(3), "projectile membership comes from the historical bracket, not the newest snapshot")
	_check(absf(absf(float(rendered.players[2].yaw)) - PI) < 0.001, "yaw interpolation uses shortest arc")
	_check(prediction.render_world(0.0, 0.0).players[2].position == a.players[2].position, "before history snaps oldest")
	_check(prediction.render_world(5.0, 0.0).players[2].position == b.players[2].position, "after history snaps newest without extrapolation")
	_check(prediction.render_world(1.2 + Tuning.NET_INTERPOLATION, 0.0).projectiles.has(3), "new projectile joins membership at its snapshot boundary")
	var c: Dictionary = b.duplicate(true)
	c.tick = 2
	c.players[2].stocks -= 1
	c.players[2].position.x += 1.0
	c.projectiles[1].owner = 1
	c.projectiles[1].behavior = "lob"
	c.projectiles[1].position.x = 8.0
	c.projectiles.erase(3)
	prediction.reconcile(c, 1, 1.4)
	rendered = prediction.render_world(1.3 + Tuning.NET_INTERPOLATION, 0.0)
	_check(rendered.players[2].position == c.players[2].position, "stock change snaps rather than lerping respawn")
	_check(rendered.projectiles[1].position == b.projectiles[1].position or rendered.projectiles[1].position == c.projectiles[1].position, "ownership and behavior changes snap projectile state instead of blending")
	_check((rendered.projectiles[1].owner == b.projectiles[1].owner and rendered.projectiles[1].behavior == b.projectiles[1].behavior) or (rendered.projectiles[1].owner == c.projectiles[1].owner and rendered.projectiles[1].behavior == c.projectiles[1].behavior), "owner and behavior switch together at the projectile boundary")
	_check(prediction.render_world(1.4 + Tuning.NET_INTERPOLATION, 0.0).projectiles.has(1) and not prediction.render_world(1.4 + Tuning.NET_INTERPOLATION, 0.0).projectiles.has(3), "despawned projectile leaves membership at its snapshot boundary")
	var d: Dictionary = c.duplicate(true)
	d.tick = 3
	d.players[2].position.x += Tuning.NET_TELEPORT_DISTANCE + 1.0
	prediction.reconcile(d, 2, 1.6)
	rendered = prediction.render_world(1.5 + Tuning.NET_INTERPOLATION, 0.0)
	_check(rendered.players[2].position == d.players[2].position, "large teleport snaps")

func _test_smoothing_and_cap() -> void:
	var world: Dictionary = _fixture()
	var prediction: RefCounted = Prediction.new()
	prediction.begin(world, 1, 0.0)
	var mismatch: Dictionary = world.duplicate(true)
	mismatch.tick = 1
	mismatch.players[1].position.x += 0.5
	prediction.reconcile(mismatch, 0, 0.1)
	var magnitude: float = prediction.correction_magnitude
	_check(magnitude > 0.0, "mismatch records visual correction")
	var rendered: Dictionary = prediction.render_world(0.1, 0.0)
	_check(rendered.players[1].position.is_equal_approx(world.players[1].position), "correction initially preserves visual continuity")
	prediction.render_world(0.2, 0.1)
	_check(prediction.correction_magnitude < magnitude, "visual offset decays")
	_check(prediction.predicted.players[1].position == mismatch.players[1].position, "smoothing never modifies simulation")
	mismatch.tick = 2
	mismatch.players[1].stocks -= 1
	mismatch.players[1].position.x += 1.0
	prediction.reconcile(mismatch, 1, 0.3)
	_check(prediction.correction_magnitude == 0.0, "local respawn clears correction")
	var cap: int = Tuning.NET_MAX_PENDING
	Tuning.NET_MAX_PENDING = 3
	prediction.begin(world, 1, 0.0)
	for tick in range(1, 8):
		prediction.advance(InputCmd.new(Vector2.ZERO, false, false, 0.0, tick), 1.0 / 64.0)
	_check(prediction.pending.size() == 3, "pending queue capped")
	_check(int(prediction.pending[0].tick) == 5 and int(prediction.pending[2].tick) == 7, "pending cap retains newest ordered commands")
	Tuning.NET_MAX_PENDING = cap
