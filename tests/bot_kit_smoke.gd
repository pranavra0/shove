extends SceneTree

var Tuning: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Autoload-dependent scene setup must be deferred in --script mode.
	Tuning = root.get_node("Tuning")
	var packed: PackedScene = load("res://scenes/main.tscn")
	if not _check(packed != null, "main scene must load"):
		return
	var sandbox: Node = packed.instantiate()
	root.add_child(sandbox)
	current_scene = sandbox
	if not _check(str(sandbox.flow.phase) == "menu" and sandbox.world.is_empty(), "smoke must start from the real offline menu"):
		quit(1)
		return
	var counts: Dictionary = {"move": 0, "projectile_spawn": 0, "hit": 0, "wall_block": 0, "deflect": 0, "ko": 0, "bot_projectile": 0, "bot_hit": 0, "bot_shot_hit": 0, "bot_ko": 0}
	sandbox.world_event.connect(func(event: Dictionary) -> void:
		var kind: String = str(event.get("type", ""))
		if counts.has(kind):
			counts[kind] = int(counts[kind]) + 1
		if kind == "projectile_spawn" and sandbox.bot_ids.has(int(event.get("player", 0))):
			counts.bot_projectile = int(counts.bot_projectile) + 1
		if kind == "hit" and sandbox.bot_ids.has(int(event.get("attacker", 0))):
			counts.bot_hit = int(counts.bot_hit) + 1
			if str(event.get("source", "")) in ["basic_shot", "curve_shot", "quick_fire"]:
				counts.bot_shot_hit = int(counts.bot_shot_hit) + 1
		if kind == "ko" and sandbox.bot_ids.has(int(event.get("player", 0))):
			counts.bot_ko = int(counts.bot_ko) + 1
	)
	# The human receives no input; bot commands and all physics callbacks stay scene-owned.
	sandbox.capture_mode = true
	sandbox.start_offline(3)
	if not await _wait_phase(sandbox, "playing", 260):
		return
	var elapsed: int = 0
	while elapsed < 1800 and int(counts.bot_projectile) == 0:
		await _frames(1)
		elapsed += 1
	while elapsed < 1800 and int(counts.bot_shot_hit) == 0:
		await _frames(1)
		elapsed += 1
	if not _check(int(counts.bot_projectile) > 0, "bots must activate real projectiles in the scene"):
		return
	if not _check(int(counts.bot_shot_hit) > 0, "bot-fired projectiles must cause real damage"):
		return
	print("BOT_KIT_SMOKE frames=%d events=%s" % [elapsed, counts])
	sandbox.queue_free()
	await process_frame
	quit(0)

func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("bot_kit_smoke: " + message)
	quit(1)
	return false

func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func _wait_phase(sandbox: Node, phase: String, max_frames: int) -> bool:
	for i in range(max_frames):
		if str(sandbox.flow.phase) == phase:
			return true
		await _frames(1)
	return _check(false, "main scene did not reach %s within %d physics frames" % [phase, max_frames])
