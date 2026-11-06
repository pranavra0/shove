extends SceneTree

var Kits: Script
var Store: Script

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var tune: Node = root.get_node_or_null("Tuning")
	if tune == null:
		push_error("Tuning autoload must be available before the panel test")
		quit(1)
		return
	Kits = load("res://scripts/sim/kits.gd")
	Store = load("res://scripts/dev/tuning_store.gd")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var sim: GDScript = load("res://scripts/sim/world.gd")
	if Kits == null or Store == null or scene == null or sim == null:
		push_error("Panel test scripts and scene must load")
		quit(1)
		return
	var app = scene.instantiate()
	root.add_child(app)
	current_scene = app
	app.start_offline(1)
	app.flow.phase = "playing"
	app.set_physics_process(false)
	var panel = app.tuning_panel
	panel.set_open(true)
	panel._search.text = "gravity"
	panel._search.text_changed.emit(panel._search.text)
	assert(panel._rows.GRAVITY.visible and not panel._rows.FRICTION.visible)
	panel._search.text = ""
	panel._search.text_changed.emit(panel._search.text)
	assert(panel._rows.GRAVITY.visible and panel._rows.FRICTION.visible, "Clearing search must restore all tuning groups")
	assert(not app._can_control(), "Tuning must release gameplay input without pausing simulation")
	var state: Dictionary = sim.create([1])
	state.players[1].on_ground = false
	state.players[1].position.y += 3.0
	var original_fall: Dictionary = sim.step(state, {}, tune.FIXED_DELTA)
	var gravity: float = tune.GRAVITY
	var spin: SpinBox = panel._rows.GRAVITY.get_child(2)
	spin.value = gravity * 0.5
	var changed_fall: Dictionary = sim.step(state, {}, tune.FIXED_DELTA)
	assert(is_equal_approx(changed_fall.players[1].velocity.y, original_fall.players[1].velocity.y * 0.5), "Editing a live numeric control must change the next sim step")
	panel._search.text = "earth.basic_shot.damage"
	panel._search.text_changed.emit(panel._search.text)
	assert(panel._element_groups.earth.section.visible and panel._move_rows.has("earth.basic_shot.damage"), "Move parameters must be searchable by element, slot, and field")
	var kit_row: HBoxContainer = panel._move_rows["earth.basic_shot.damage"]
	var base_damage: float = float(Kits.move("earth", "basic_shot").damage)
	var kit_spin: SpinBox = kit_row.get_child(2)
	kit_spin.value = base_damage * 1.25
	assert(is_equal_approx(float(Kits.move("earth", "basic_shot").damage), base_damage * 1.25), "Editing a per-move control must update effective move behavior")
	assert(is_equal_approx(float(Kits.base_move("earth", "basic_shot").damage), base_damage), "Sparse override must preserve legacy base move")
	var shove_row: HBoxContainer = panel._move_rows["earth.shove.damage"]
	var sparse_before_scalar: Dictionary = tune.KIT_OVERRIDES.duplicate(true)
	var scalar_shove: float = tune.SHOVE_DAMAGE
	panel._change("SHOVE_DAMAGE", scalar_shove * 1.1)
	assert(is_equal_approx(float(shove_row.get_child(2).value), scalar_shove * 1.1), "Changing a base scalar must refresh visible derived move values")
	assert(tune.KIT_OVERRIDES == sparse_before_scalar, "Changing a base scalar must not create or alter a sparse move override")
	panel._change("SHOVE_DAMAGE", scalar_shove)
	panel._apply_values(Store.defaults())
	assert(tune.KIT_OVERRIDES.is_empty(), "Reset defaults must clear move overrides")
	panel._search.text = ""
	panel._search.text_changed.emit(panel._search.text)
	for tick in range(50):
		app._physics_process(tune.FIXED_DELTA)
	panel._load("res://presets/Chaos.json")
	assert(tune.GRAVITY == 8.0 and tune.MOMENTUM_TRANSFER == 2.8)
	for tick in range(40):
		app._physics_process(tune.FIXED_DELTA)
	panel._load("res://presets/Source-tight.json")
	assert(is_equal_approx(tune.GRAVITY, gravity) and tune.MOMENTUM_TRANSFER == 0.85)
	for tick in range(30):
		app._physics_process(tune.FIXED_DELTA)
	app.save_replay()
	var expected: Dictionary = app.world.duplicate(true)
	var tape_script: GDScript = load("res://scripts/dev/replay.gd")
	var persisted = tape_script.new()
	assert(persisted.load_file("user://replays/latest.json") == OK and persisted.final_world == expected)
	app.recording = null
	app.latest_tape = null
	app.replay_latest()
	for tick in range(125):
		app._physics_process(tune.FIXED_DELTA)
	assert(not app.replaying and app.replay_verified and app.world == expected, "Scene replay must apply initial and mid-tape tuning, reproducing the exact World")
	app.show_menu()
	app.save_replay()
	app.replay_latest()
	for tick in range(125):
		app._physics_process(tune.FIXED_DELTA)
	assert(app.replay_verified and app.world == expected, "Replay must survive return to menu and save there")
	print("PASS live panel empty-search/numeric physics/preset cutover/input release/full scene replay across live tuning/menu")
	quit(0)
