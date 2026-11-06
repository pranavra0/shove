extends SceneTree

var Store: Script
var Kits: Script
var InputCommand: Script

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var tuning: Node = root.get_node_or_null("Tuning")
	if not _check(tuning != null, "Tuning autoload must be available"):
		return
	Store = load("res://scripts/dev/tuning_store.gd")
	Kits = load("res://scripts/sim/kits.gd")
	InputCommand = load("res://scripts/sim/input_cmd.gd")
	if not _check(Store != null and Kits != null and InputCommand != null, "Tuning, kit, and command scripts must load"):
		return
	var main_script: Script = load("res://scripts/main.gd")
	if not _check(main_script != null, "Main scene script must load"):
		return
	var packed: PackedScene = load("res://scenes/main.tscn")
	if not _check(packed != null, "Main scene must load"):
		return
	var app = packed.instantiate()
	if not _check(app != null, "Main scene must instantiate"):
		return
	if not _check(app.has_method("start_match") and app.get_script() == main_script, "Instantiated main scene must have the initialized gameplay script"):
		app.free()
		return
	root.add_child(app)
	current_scene = app
	if not _check(app.tuning_panel != null, "Main scene must initialize the tuning panel"):
		return
	app.start_match([1])
	app.flow.phase = "playing"
	app.paused = false
	if not _check(app.world.has("players") and app.world.players.has(1) and app.world.players[1].has("spawn"), "Offline match must initialize its player spawn"):
		return
	var player: Dictionary = app.world.players[1]
	player.position = player.spawn
	player.velocity = Vector3.ZERO
	player.on_ground = true
	var panel = app.tuning_panel
	panel.set_open(true)
	panel._toggle_element("earth")
	if not _check(panel._move_rows.has("earth.high_jump.speed"), "Expanded Earth section must expose high-jump speed control"):
		return
	var original_speed: float = float(Kits.move("earth", "high_jump").speed)
	var row: HBoxContainer = panel._move_rows["earth.high_jump.speed"]
	var editor: SpinBox = row.get_child(2)
	editor.value = original_speed * 1.5
	if not _check(is_equal_approx(float(Kits.move("earth", "high_jump").speed), original_speed * 1.5), "Changing a real per-move control must update the active kit definition"):
		return
	var jump_command = InputCommand.new(Vector2.ZERO, false, false, 0.0, int(app.world.tick))
	jump_command.moves = InputCommand.HIGH_JUMP
	app._capture_sim_step({1: jump_command})
	var remaining_ticks: int = 12
	while remaining_ticks > 0 and float(app.world.players[1].velocity.y) <= original_speed * 1.4:
		remaining_ticks -= 1
		var advance = InputCommand.new(Vector2.ZERO, false, false, 0.0, int(app.world.tick))
		app._capture_sim_step({1: advance})
	var jumped: Dictionary = app.world.players[1]
	if not _check(float(jumped.velocity.y) > original_speed * 1.4 and jumped.position.y > float(player.spawn.y), "Edited high-jump speed must activate after windup and physically lift the player"):
		return
	panel._filename.text = "kit-tuning-scene-smoke.json"
	panel._save()
	if not _check(FileAccess.file_exists("user://presets/kit-tuning-scene-smoke.json"), "Named tuning preset must persist"):
		return
	panel._apply_values(Store.defaults())
	if not _check(tuning.KIT_OVERRIDES.is_empty(), "Reset defaults must clear sparse move overrides"):
		return
	panel._load("user://presets/kit-tuning-scene-smoke.json")
	if not _check(is_equal_approx(float(Kits.move("earth", "high_jump").speed), original_speed * 1.5), "Reloading the named preset must restore its move override"):
		return
	if not panel._move_rows.has("earth.high_jump.speed"):
		panel._toggle_element("earth")
	if not _check(panel._move_rows.has("earth.high_jump.speed"), "Reloaded panel must expose move controls after lazy rebuild"):
		return
	var before_rejected: Dictionary = tuning.KIT_OVERRIDES.duplicate(true)
	app.network.active = true
	app.network.hosting = false
	row = panel._move_rows["earth.high_jump.speed"]
	editor = row.get_child(2)
	editor.value = original_speed
	if not _check(tuning.KIT_OVERRIDES == before_rejected and is_equal_approx(float(editor.value), original_speed * 1.5), "Client UI must reject local edits to authoritative simulation move tuning"):
		return
	app.network.active = false
	print("PASS kit tuning scene: real move control, windup-aware high-jump physics, named preset save/load/reset and client UI authority restriction")
	quit(0)

func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("FAIL kit tuning scene: " + message)
	_cleanup_preset()
	quit(1)
	return false

func _cleanup_preset() -> void:
	var path := ProjectSettings.globalize_path("user://presets/kit-tuning-scene-smoke.json")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
