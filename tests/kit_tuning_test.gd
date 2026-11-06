extends SceneTree

var Tuning: Node
var Kits: GDScript
var TuningStore: GDScript
var World: GDScript
var InputCmd: GDScript
var failed: bool = false
const PRESET_PATH := "user://kit_tuning_regression.json"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Tuning = root.get_node("Tuning")
	Kits = load("res://scripts/sim/kits.gd")
	TuningStore = load("res://scripts/dev/tuning_store.gd")
	World = load("res://scripts/sim/world.gd")
	InputCmd = load("res://scripts/sim/input_cmd.gd")
	var original: Dictionary = TuningStore.snapshot()
	_test_override_and_reset()
	_test_json_persistence_and_rejection()
	TuningStore.apply(original)
	_remove_preset()
	if failed:
		call_deferred("quit", 1)
	else:
		print("PASS kit tuning override behavior/persistence")
		call_deferred("quit", 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("kit_tuning_test: " + message)
		failed = true

func _world_hit(element: String, overrides: Dictionary = {}) -> Dictionary:
	Tuning.KIT_OVERRIDES = overrides
	var world: Dictionary = World.create([1, 2])
	world.players[1].element = element
	world.players[1].position = Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 6.0)
	world.players[1].spawn = world.players[1].position
	world.players[2].position = Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 4.6)
	world.players[2].spawn = world.players[2].position
	var command := {1: InputCmd.new(Vector2.ZERO, false, true)}
	world = World.step(world, command, Tuning.FIXED_DELTA)
	world = World.step(world, command, Tuning.FIXED_DELTA)
	return world

func _test_override_and_reset() -> void:
	var overrides: Dictionary = {"fire": {"shove": {"damage": 27.0, "windup": Tuning.FIXED_DELTA, "reach": 1.1}}}
	var overridden: Dictionary = _world_hit("fire", overrides)
	var reset_outcome: Dictionary = _world_hit("fire")
	_check(overridden.players[2].damage == 27.0 and reset_outcome.players[2].damage != 27.0, "override/reset did not affect simulation outcomes")

func _test_json_persistence_and_rejection() -> void:
	var exact_damage: float = 23.123456789012345
	var values: Dictionary = {"KIT_OVERRIDES": {"fire": {"shove": {"damage": exact_damage, "windup": Tuning.FIXED_DELTA, "reach": 1.1}}}}
	_remove_preset()
	_check(TuningStore.save(PRESET_PATH, values) == OK, "preset save failed")
	var loaded: Dictionary = TuningStore.load_values(PRESET_PATH)
	_check(not loaded.is_empty(), "preset JSON load failed")
	if loaded.is_empty():
		return
	_check(loaded.KIT_OVERRIDES.fire.shove.damage == exact_damage, "nested float changed across JSON persistence")
	var persisted: Dictionary = _world_hit("fire", loaded.KIT_OVERRIDES)
	_check(persisted.players[2].damage == exact_damage, "loaded preset did not reproduce simulation outcome")
	var baseline: Dictionary = _world_hit("earth")
	_check(baseline.players[2].damage != exact_damage, "different element/base move did not produce distinct outcome")
	var before: Dictionary = TuningStore.snapshot()
	var bad: Dictionary = {"KIT_OVERRIDES": {"air": {"basic_shot": {"damage": 16.0, "unknown": 4.0}}}}
	_check(TuningStore.decode(bad).is_empty(), "unknown nested field accepted")
	TuningStore.apply(bad)
	_check(TuningStore.snapshot() == before, "invalid apply mutated live Tuning")
	bad = {"KIT_OVERRIDES": {"air": {"basic_shot": {"damage": INF}}}}
	_check(TuningStore.decode(bad).is_empty(), "non-finite nested number accepted")
	bad = {"KIT_OVERRIDES": {"earth": {"wall": {"wall_hp": 1.5}}}}
	_check(TuningStore.decode(bad).is_empty(), "fractional wall HP accepted")
	bad = {"KIT_OVERRIDES": {"earth": {"wall": {"wall_width": 0.0}}}}
	_check(TuningStore.decode(bad).is_empty(), "zero wall width accepted")
	_check(TuningStore.kit_bounds("earth", "wall", "wall_width").x > 0.0, "wall width range permits invalid entity")
	_check(TuningStore.kit_bounds("earth", "wall", "duration").x > 0.0, "wall lifetime range permits invalid entity")
func _remove_preset() -> void:
	var absolute: String = ProjectSettings.globalize_path(PRESET_PATH)
	if FileAccess.file_exists(PRESET_PATH):
		DirAccess.remove_absolute(absolute)
