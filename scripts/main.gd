extends Node3D

signal world_event(event: Dictionary)


var world: Dictionary = {}
var flow: Dictionary = {}
var bot_ids: Array = []
var bot_memory: Dictionary = {}
var local_id: int = 1
var paused: bool = false
var player_views: Dictionary = {}
var camera_pivot: Node3D
var menu_overlay: CenterContainer
var menu_panel: VBoxContainer
var yaw: float = 0.0
var pitch: float = Tuning.PITCH_INITIAL
var _world_time: float = 0.0
var _match_ids: Array = []
var camera: Camera3D
var arena: ArenaView
var juice: JuiceView
var synth: SynthAudio
var game_hud: GameHUD
var presentation_time: float = 0.0
var capture_mode: bool = false
var _last_countdown: int = -1
var tuning_panel: TuningPanel
var gizmos: DevGizmos
var recording: ReplayTape
var latest_tape: ReplayTape
var replaying: bool = false
var replay_verified: bool = false
var _replay_restore: Dictionary = {}
var _tuning_patch: Dictionary = {}
var _dev_actions: Array[int] = []
var _rebuild_art: bool = false
var _rebuild_audio: bool = false
var network: NetSession
var network_ui: NetworkLobby
var _network_view_epoch: int = -1
var _receiving_network_settings: bool = false

func _ready() -> void:
	_build_world()
	_build_camera()
	_build_hud()
	juice = JuiceView.new()
	add_child(juice)
	synth = SynthAudio.new()
	add_child(synth)
	game_hud = GameHUD.new()
	add_child(game_hud)
	game_hud.setup(self)
	tuning_panel = TuningPanel.new()
	add_child(tuning_panel)
	tuning_panel.setup(self)
	tuning_panel.tuning_changed.connect(_on_tuning_changed)
	tuning_panel.panel_visibility_changed.connect(func(_opened: bool) -> void: _sync_cursor())
	gizmos = DevGizmos.new()
	add_child(gizmos)
	network = NetSession.new()
	network.name = "Network"
	add_child(network)
	network.command_provider = sample_input
	network.lobby_updated.connect(_on_network_lobby)
	network.world_updated.connect(_on_network_world)
	network.authoritative_events.connect(_on_network_events)
	network.settings_changed.connect(_on_network_settings)
	network.connection_error.connect(_on_network_error)
	network_ui = NetworkLobby.new()
	network_ui.setup(self)
	show_menu()

func show_menu() -> void:
	_stop_replay()
	tuning_panel.set_open(false)
	if recording != null and not world.is_empty():
		recording.finish(world)
		latest_tape = recording
	recording = null
	if network != null and network.active:
		network.close()
	local_id = 1
	_network_view_epoch = -1
	paused = false
	flow = MatchSim.create()
	world = {}
	juice.clear()
	game_hud.reset_match()
	bot_ids.clear()
	bot_memory.clear()
	_world_time = 0.0
	_clear_players()
	_sync_cursor()
	_clear_menu("SHOVE")
	_menu_label("M O M E N T U M   I S   A   W E A P O N")
	_menu_label("Build speed. Pick your moment.\nSend your friends into the void.")
	_menu_button("Play vs Bots", "PlayBots", _show_offline_setup)
	_menu_button("Host", "Host", _show_network_setup.bind(true))
	_menu_button("Join", "Join", _show_network_setup.bind(false))
	_menu_button("Tuning", "Tuning", _show_tuning)
	_menu_button("Quit", "Quit", func() -> void: get_tree().quit())
	_menu_label("WASD  /  SPACE hop  /  E shove\nF1 live tuning  /  ESC pause")

func _show_offline_setup() -> void:
	flow.phase = "setup"
	_clear_menu("Offline setup")
	_menu_label("Free-for-all: you against 1–7 bots, or practice alone.")
	var bots := OptionButton.new()
	bots.name = "BotCount"
	for count in range(1, 8):
		bots.add_item("%d bot%s" % [count, "" if count == 1 else "s"], count)
	bots.select(1)
	menu_panel.add_child(bots)
	var solo := CheckButton.new()
	solo.name = "SoloPractice"
	solo.text = "Solo practice (no opponents)"
	solo.toggled.connect(func(enabled: bool) -> void: bots.disabled = enabled)
	menu_panel.add_child(solo)
	_menu_button("Start", "Start", func() -> void: start_offline(0 if solo.button_pressed else bots.get_selected_id()))
	_menu_button("Back", "Back", show_menu)

func _show_network_setup(hosting: bool) -> void:
	network_ui.show_setup(hosting)

func _show_tuning() -> void:
	tuning_panel.set_open(true)

func start_offline(bot_count: int) -> void:
	var ids: Array = [local_id]
	for index in range(clampi(bot_count, 0, 7)):
		ids.append(local_id + index + 1)
	start_match(ids)

func start_match(ids: Array) -> void:
	_stop_replay()
	tuning_panel.set_open(false)
	_clear_players()
	juice.clear()
	game_hud.reset_match()
	_last_countdown = -1
	_match_ids = ids.duplicate()
	bot_ids.clear()
	bot_memory.clear()
	world = World.create(ids)
	for player_id in world.players:
		player_views[player_id] = _build_player(int(player_id))
		if int(player_id) != local_id:
			bot_ids.append(player_id)
	bot_ids.sort()
	yaw = float(world.players[local_id].yaw) if world.players.has(local_id) else 0.0
	pitch = Tuning.PITCH_INITIAL
	paused = false
	_world_time = 0.0
	flow = MatchSim.create()
	flow.phase = "countdown"
	menu_overlay.hide()
	_begin_recording()
	_sync_cursor()

func sample_input() -> InputCmd:
	var tick: int = int(world.get("tick", 0))
	if not _can_control() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return InputCmd.new(Vector2.ZERO, false, false, yaw, tick)
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return InputCmd.new(axis, Input.is_action_pressed("jump"), Input.is_action_pressed("shove"), yaw, tick)

func _physics_process(_delta: float) -> void:
	_apply_rebuilds()
	_run_dev_actions()
	if network.active:
		juice.freeze_remaining = maxf(0.0, juice.freeze_remaining - Tuning.FIXED_DELTA)
		_sync_cursor()
		return
	if replaying:
		_replay_tick()
		return
	if paused or world.is_empty():
		return
	if juice.freeze_remaining > 0.0:
		juice.freeze_remaining = maxf(0.0, juice.freeze_remaining - Tuning.FIXED_DELTA)
		return
	var previous_phase: String = str(flow.phase)
	if previous_phase == "playing" or previous_phase == "ringout":
		# Slow motion changes tick scheduling, never World.step's fixed 64 Hz dt.
		var scale: float = Tuning.MATCH_RINGOUT_SCALE if previous_phase == "ringout" else 1.0
		if Tuning.DEV_SLOWMO_ENABLED:
			scale *= Tuning.DEV_SLOWMO_SCALE
		_world_time += Tuning.FIXED_DELTA * scale
		while _world_time + 0.0000001 >= Tuning.FIXED_DELTA:
			_world_time = maxf(0.0, _world_time - Tuning.FIXED_DELTA)
			var commands: Dictionary = {}
			if world.players.has(local_id):
				commands[local_id] = sample_input()
			for player_id in bot_ids:
				var decision: Dictionary = BotSim.command(world, int(player_id), bot_memory.get(player_id, {}), Tuning.FIXED_DELTA)
				commands[player_id] = decision.cmd
				bot_memory[player_id] = decision.memory
			recording.record(commands, _tuning_patch)
			_tuning_patch.clear()
			world = World.step(world, commands, Tuning.FIXED_DELTA)
			_dispatch_events(world.events)
	flow = MatchSim.step(flow, world, Tuning.FIXED_DELTA)
	if str(flow.phase) != previous_phase:
		_world_time = 0.0
		if flow.phase == "winner":
			recording.finish(world)
			latest_tape = recording
			save_replay()
			_show_winner()
	if flow.phase == "countdown" and int(flow.countdown) != _last_countdown:
		_last_countdown = int(flow.countdown)
		synth.countdown(_last_countdown)
	_sync_cursor()

func _dispatch_events(events: Array) -> void:
	juice.consume(events, world, local_id)
	game_hud.consume(events)
	for event in events:
		synth.play_event(event)
		if player_views.has(event.player):
			player_views[event.player].react(event)
	for event in events:
		world_event.emit(event)

func _can_control() -> bool:
	return not paused and not replaying and not tuning_panel.is_open() and not world.is_empty() and flow.get("phase", "menu") in ["playing", "ringout"] and world.players.has(local_id) and int(world.players[local_id].stocks) > 0

func _sync_cursor() -> void:
	var mode: int = Input.MOUSE_MODE_CAPTURED if _can_control() and get_window().has_focus() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode

func _set_paused(value: bool) -> void:
	if network.active:
		network_ui.show_pause(value)
		return
	paused = value
	_sync_cursor()
	if not paused:
		menu_overlay.hide()
		return
	_clear_menu("Paused")
	_menu_label("The offline match is paused.")
	_menu_button("Resume", "Resume", _set_paused.bind(false))
	_menu_button("Restart match", "Restart", _rematch)
	_menu_button("Main menu", "MainMenu", show_menu)

func _rematch() -> void:
	if network.active:
		if network.hosting:
			network.start_match()
		return
	start_match(_match_ids)

func _show_winner() -> void:
	if network.active:
		network_ui.show_winner()
		return
	var winner: int = int(flow.winner)
	var title: String = "Draw" if winner < 0 else ("You win!" if winner == local_id else "Bot %d wins!" % winner)
	_clear_menu(title)
	_menu_label("Round complete — all stocks have been settled.")
	_menu_button("Rematch", "Rematch", _rematch)
	_menu_button("Main menu", "MainMenu", show_menu)

func _process(delta: float) -> void:
	# Presentation only: authoritative simulation and flow advance in physics.
	presentation_time += delta
	arena.animate(delta, presentation_time)
	gizmos.render_frame(world)
	network_ui.render_frame()
	if world.is_empty():
		synth.update_motion(0.0, false, delta)
		_update_camera(delta)
		game_hud.render_frame(world, flow, local_id, camera, delta)
		return
	if not network.active or juice.freeze_remaining <= 0.0:
		for player_id in world.players:
			player_views[player_id].render_state(world.players[player_id], delta, presentation_time)
	_update_camera(delta)
	juice.render_frame(world, local_id, camera, delta)
	game_hud.render_frame(world, flow, local_id, camera, delta)
	var human: Dictionary = world.players.get(local_id, {})
	if not human.is_empty():
		var velocity: Vector3 = human.velocity
		synth.update_motion(Vector2(velocity.x, velocity.z).length(), human.on_ground, delta)

func _update_camera(delta: float) -> void:
	if capture_mode:
		return
	if world.is_empty():
		camera.global_position = Tuning.CAMERA_MENU_POSITION
		camera.look_at(Tuning.CAMERA_MENU_TARGET)
		camera.fov = Tuning.CAMERA_FOV
		return
	var camera_id: int = local_id
	if not world.players.has(camera_id) or world.players[camera_id].stocks <= 0:
		for id in world.players:
			if world.players[id].stocks > 0:
				camera_id = id
				break
	if not world.players.has(camera_id):
		return
	var state: Dictionary = world.players[camera_id]
	var velocity: Vector3 = state.velocity
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed: float = horizontal.length()
	var target: Vector3 = state.position + Vector3.UP * Tuning.CAMERA_TARGET_HEIGHT
	target += horizontal * Tuning.CAMERA_LOOKAHEAD
	if Tuning.JUICE_KO_CAMERA_ENABLED and juice.ko_remaining > 0.0:
		target = target.lerp(juice.ko_target + Vector3.UP, Tuning.CAMERA_KO_TRACK)
	var weight: float = 1.0 - exp(-delta * Tuning.CAMERA_SMOOTH)
	camera_pivot.position = camera_pivot.position.lerp(target, weight)
	var strafe: float = horizontal.dot(Vector3.RIGHT.rotated(Vector3.UP, yaw))
	var tilt: float = -strafe * Tuning.CAMERA_TILT
	var basis := Basis.from_euler(Vector3(pitch, yaw, tilt))
	var distance: float = Tuning.CAMERA_DISTANCE
	if Tuning.JUICE_KO_CAMERA_ENABLED and juice.ko_remaining > 0.0:
		distance *= Tuning.CAMERA_KO_ZOOM
	var desired: Vector3 = camera_pivot.position + basis * Vector3(0.0, 0.0, distance)
	if Tuning.CAMERA_COLLISION_ENABLED:
		var ray := PhysicsRayQueryParameters3D.create(camera_pivot.position, desired)
		var collision: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
		if not collision.is_empty():
			desired = collision.position + collision.normal * Tuning.CAMERA_COLLISION_MARGIN
	if Tuning.CAMERA_BOB_ENABLED and state.on_ground:
		desired.y += sin(presentation_time * Tuning.CAMERA_BOB_RATE) * minf(speed, Tuning.WALK_SPEED) * Tuning.CAMERA_BOB
	if Tuning.JUICE_SHAKE_ENABLED:
		desired += Vector3(sin(presentation_time * 83.0), cos(presentation_time * 97.0), 0.0) * juice.shake
	camera.global_position = desired
	camera.look_at(camera_pivot.position)
	camera.rotation.z = tilt
	var desired_fov: float = Tuning.CAMERA_FOV + clampf(speed - Tuning.WALK_SPEED, 0.0, Tuning.CAMERA_FOV_SPEED_RANGE) / Tuning.CAMERA_FOV_SPEED_RANGE * Tuning.CAMERA_FOV_BOOST
	camera.fov = lerpf(camera.fov, desired_fov, weight)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if flow.get("phase", "menu") in ["countdown", "playing", "ringout", "round_end"]:
			_set_paused(not paused)
		elif flow.get("phase", "menu") != "menu":
			show_menu()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _can_control() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * Tuning.MOUSE_SENSITIVITY
		pitch = clampf(pitch - event.relative.y * Tuning.MOUSE_SENSITIVITY, Tuning.CAMERA_MIN_PITCH, Tuning.CAMERA_MAX_PITCH)

func _clear_players() -> void:
	for view in player_views.values():
		remove_child(view)
		view.queue_free()
	player_views.clear()

func _clear_menu(title: String) -> void:
	for child in menu_panel.get_children():
		menu_panel.remove_child(child)
		child.queue_free()
	var heading := _menu_label(title)
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color("#edfaf4"))
	if title == "SHOVE":
		heading.add_theme_font_size_override("font_size", 76)
	menu_overlay.anchor_right = 0.43 if flow.get("phase", "menu") in ["menu", "setup"] else 1.0
	menu_overlay.show()

func _menu_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Tuning.HUD_FONT_SIZE)
	menu_panel.add_child(label)
	return label

func _menu_button(text: String, node_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(330, 48)
	if action.is_valid():
		button.pressed.connect(action)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(func() -> void: synth.ui_click())
	menu_panel.add_child(button)
	return button

func _menu_field(title: String, node_name: String, value: String) -> void:
	_menu_label(title)
	var field := LineEdit.new()
	field.name = node_name
	field.text = value
	menu_panel.add_child(field)

func _build_world() -> void:
	arena = ArenaView.new()
	add_child(arena)

func _build_player(player_id: int) -> Node3D:
	var view := AvatarView.new()
	view.name = "Player%d" % player_id
	var label: String = "YOU" if player_id == local_id else "BOT %02d" % player_id
	if network != null and network.active and network.members.has(player_id):
		label = "YOU / " + str(network.members[player_id].name) if player_id == local_id else str(network.members[player_id].name)
	view.setup(player_id, _player_color(player_id), label)
	view.scale = Vector3(Tuning.BODY_RADIUS / 0.4, Tuning.BODY_HEIGHT / 1.8, Tuning.BODY_RADIUS / 0.4)
	add_child(view)
	return view

func _player_color(player_id: int) -> Color:
	if network != null and network.active and network.members.has(player_id):
		return Tuning.HUD_PLAYER_COLORS[posmod(int(network.members[player_id].color), Tuning.HUD_PLAYER_COLORS.size())]
	return Tuning.HUD_PLAYER_COLORS[posmod(player_id - 1, Tuning.HUD_PLAYER_COLORS.size())]

func _build_camera() -> void:
	camera_pivot = Node3D.new()
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.position.z = Tuning.CAMERA_DISTANCE
	camera.current = true
	camera_pivot.add_child(camera)
	camera.fov = Tuning.CAMERA_FOV
	camera.far = Tuning.CAMERA_FAR

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	var theme := Theme.new()
	theme.default_font_size = 19
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#173b49")
	normal.border_color = Color("#366170")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color("#286576")
	hover.border_color = Color("#62e7e4")
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color("#b44e4a")
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", hover)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.065, 0.09, 0.93)
	panel_style.set_corner_radius_all(14)
	panel_style.border_color = Color("#315664")
	panel_style.set_border_width_all(1)
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	add_child(layer)
	menu_overlay = CenterContainer.new()
	menu_overlay.name = "MenuOverlay"
	menu_overlay.theme = theme
	menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(menu_overlay)
	var panel := PanelContainer.new()
	menu_overlay.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	menu_panel = VBoxContainer.new()
	menu_panel.name = "Menu"
	menu_panel.add_theme_constant_override("separation", 10)
	margin.add_child(menu_panel)

func capture_scenario(scenario: String) -> Variant:
	# Deterministic presentation staging; never used by a live match.
	set_physics_process(false)
	capture_mode = true
	presentation_time = 1.0
	Tuning.DEV_HITBOX_ENABLED = scenario == "debug"
	Tuning.DEV_VELOCITY_ENABLED = scenario == "debug"
	if scenario == "menu":
		show_menu()
		camera.global_position = Tuning.CAMERA_MENU_POSITION
		camera.look_at(Tuning.CAMERA_MENU_TARGET)
		return true
	start_offline(7 if scenario == "hud" else (0 if scenario == "character" else (1 if scenario == "impact" else 5)))
	flow.phase = "playing"
	menu_overlay.hide()
	var placements: Array = [Vector3(-2, 0, 7), Vector3(0, 0, 4), Vector3(5, 0, 3), Vector3(-6, 0, -2), Vector3(7, 0, -5), Vector3(-3, 0, -7), Vector3(11, 0, 7), Vector3(-11, 0, 5)]
	var i: int = 0
	for id in world.players:
		var p: Dictionary = world.players[id]
		p.position = placements[i]
		p.position.y = World.floor_height(p.position) + Tuning.BODY_HEIGHT * 0.5
		p.damage = float(i * 27)
		p.stocks = 3 - i % 3
		i += 1
	if scenario == "bhop":
		world.players[local_id].position.y += 1.5
		world.players[local_id].velocity = Vector3(5.0, 3.0, -19.0)
		world.players[local_id].on_ground = false
		game_hud.consume([{"type":"jump", "player":local_id}])
	if scenario == "impact":
		world.players[2].position = world.players[local_id].position + Vector3(0.8, 0, -1.2)
		world.players[2].hitstun = Tuning.HITSTUN
		world.players[2].velocity = Vector3(7, 6, -18)
		world.players[local_id].attack_time = Tuning.SHOVE_ACTIVE * 0.7
		_dispatch_events([{"type":"hit", "player":2, "attacker":local_id, "position":world.players[2].position, "strength":22.0}])
	if scenario == "ko":
		flow.phase = "ringout"
		world.players[2].position = Vector3(21, -5, 4)
		world.players[2].hitstun = Tuning.HITSTUN
		world.players[2].velocity = Vector3(12, -8, 0)
		_dispatch_events([{"type":"ko", "player":2, "position":world.players[2].position}])
	if scenario == "debug":
		world.players[2].velocity = Vector3(8, 4, -12)
		world.players[2].attack_time = Tuning.SHOVE_ACTIVE
		world.players[3].invuln = 1.0
		world.players[6].position = Vector3(35, 6, 0)
	if scenario == "countdown":
		flow.phase = "countdown"
		flow.countdown = 2
	if scenario == "winner":
		flow.phase = "winner"
		flow.winner = local_id
		_show_winner()
	for id in world.players:
		player_views[id].render_state(world.players[id], 1.0, presentation_time)
	game_hud.render_frame(world, flow, local_id, camera, 1.0 if scenario == "bhop" else 0.0)
	camera.fov = Tuning.CAMERA_FOV + (Tuning.CAMERA_FOV_BOOST if scenario == "bhop" else 0.0)
	if scenario in ["arena", "hud", "tuning"]:
		camera.global_position = Vector3(34, 18, 38)
		camera.look_at(Vector3(0, -3, 0))
	elif scenario == "character":
		camera.global_position = world.players[local_id].position + Vector3(1.4, 1.0, -3.0)
		camera.look_at(world.players[local_id].position + Vector3.UP * 0.9)
	elif scenario == "ko":
		camera.global_position = Vector3(28, 7, 18)
		camera.look_at(Vector3(17, -3, 2))
	else:
		camera.global_position = Vector3(-5, 5.2, 14)
		camera.look_at(Vector3(0, 1, 3))
	if scenario == "tuning":
		tuning_panel.set_open(true)
	return true

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if key == KEY_F1:
		if not replaying:
			tuning_panel.toggle()
		get_viewport().set_input_as_handled()
	elif key >= KEY_F2 and key <= KEY_F12 and not world.is_empty():
		_dev_actions.append(key)
		get_viewport().set_input_as_handled()
	elif key == KEY_M and _can_control():
		Tuning.MUSIC_ENABLED = not Tuning.MUSIC_ENABLED
		_on_tuning_changed("MUSIC_ENABLED", Tuning.MUSIC_ENABLED)

func _on_tuning_changed(name: String, value: Variant) -> void:
	if network != null and network.active and network.hosting and not _receiving_network_settings:
		network.push_tuning(name, value)
	if not replaying:
		_tuning_patch[name] = value
	if name == "HUD_DEBUG_ENABLED":
		game_hud.debug_visible = value
	if name == "CAMERA_FAR":
		camera.far = value
	if name == "VIS_TAG_FONT_SIZE":
		_rebuild_art = true
	if name.begins_with("PLATFORM") or name.begins_with("CENTER") or name.begins_with("RAMP") or name.begins_with("LEDGE") or name.begins_with("BODY") or name in ["HUD_PLAYER_COLORS", "VIS_EDGE_COLOR", "VIS_LANE_COLOR", "VIS_TOP_COLOR", "VIS_ROCK_COLOR", "VIS_EDGE_EMISSION", "VIS_ROCK_DEPTH", "VIS_DEBRIS_COUNT", "VIS_FOG_DENSITY", "VIS_SUN_ENERGY", "VIS_AMBIENT_ENERGY", "VIS_RIM_LIGHT_ENERGY", "VIS_SHADOW_SOFTNESS", "VIS_VOID_CLOUD_EMISSION"]:
		_rebuild_art = true
	if name in ["AUDIO_SAMPLE_RATE", "AUDIO_VOICES", "AUDIO_MUSIC_BPM"]:
		_rebuild_audio = true

func _apply_rebuilds() -> void:
	if _rebuild_art:
		_rebuild_art = false
		remove_child(arena)
		arena.queue_free()
		_build_world()
		_clear_players()
		for id in world.get("players", {}):
			player_views[id] = _build_player(int(id))
	if _rebuild_audio:
		_rebuild_audio = false
		synth.rebuild()

func _apply_settings(values: Dictionary) -> void:
	for name in values:
		if Tuning.get(name) != values[name]:
			Tuning.set(name, values[name])
			_on_tuning_changed(name, values[name])
	_apply_rebuilds()

func _begin_recording() -> void:
	recording = ReplayTape.new()
	recording.begin(world, TuningStore.snapshot())
	_tuning_patch.clear()

func save_replay() -> void:
	if network.active and not network.hosting:
		print("Only the host has the complete authoritative InputCmd stream.")
		return
	if not replaying and recording != null and not world.is_empty():
		recording.finish(world)
		latest_tape = recording
	if latest_tape == null:
		return
	DirAccess.make_dir_recursive_absolute("user://replays")
	var error: Error = latest_tape.save("user://replays/latest.json")
	if error == OK:
		print("REPLAY SAVED ", ProjectSettings.globalize_path("user://replays/latest.json"))
	else:
		push_error("Replay save failed: " + error_string(error))

func replay_latest() -> void:
	if network.active:
		print("Leave the online session before replaying; full input recordings belong to the host.")
		return
	if replaying:
		return
	if recording != null and not recording.frames.is_empty() and not world.is_empty():
		recording.finish(world)
		latest_tape = recording
	if latest_tape == null:
		latest_tape = ReplayTape.new()
		if latest_tape.load_file("user://replays/latest.json") != OK:
			latest_tape = null
			return
	_replay_restore = TuningStore.snapshot()
	replaying = true
	replay_verified = false
	tuning_panel.set_open(false)
	_apply_settings(latest_tape.settings)
	world = latest_tape.restart()
	_clear_players()
	for id in world.players:
		player_views[id] = _build_player(int(id))
	juice.clear()
	game_hud.reset_match()
	flow = MatchSim.create()
	flow.phase = "playing"
	paused = false
	menu_overlay.hide()
	_sync_cursor()

func _replay_tick() -> void:
	if not latest_tape.has_next():
		replay_verified = world == latest_tape.final_world
		print("REPLAY VERIFIED " if replay_verified else "REPLAY MISMATCH ", world.tick)
		_stop_replay()
		flow.phase = "winner"
		_clear_menu("Replay complete")
		_menu_label("Exact final state verified." if replay_verified else "Recorded final state did not match.")
		_menu_button("Replay again", "ReplayAgain", replay_latest)
		_menu_button("Main menu", "MainMenu", show_menu)
		_sync_cursor()
		return
	var commands: Dictionary = latest_tape.next_commands()
	_apply_settings(latest_tape.frame_settings)
	world = World.step(world, commands, Tuning.FIXED_DELTA)
	_dispatch_events(world.events)

func _stop_replay() -> void:
	if not replaying:
		return
	replaying = false
	_apply_settings(_replay_restore)
	_replay_restore.clear()
	_tuning_patch.clear()

func _run_dev_actions() -> void:
	for key in _dev_actions:
		if network.active and key in [KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F9, KEY_F10, KEY_F12]:
			if key == KEY_F2 and network.hosting:
				network.start_match()
			else:
				print("World mutation hotkeys are offline-only; lobby bot fill and host rematch remain available online.")
			continue
		if key == KEY_F2:
			_rematch()
		elif key == KEY_F3 and world.players.size() < 8:
			var id: int = 2
			while world.players.has(id):
				id += 1
			var ids: Array = world.players.keys()
			ids.append(id)
			world.players[id] = World.create(ids).players[id]
			player_views[id] = _build_player(id)
			bot_ids.append(id)
			_match_ids.append(id)
			_begin_recording()
		elif key == KEY_F4 and not bot_ids.is_empty():
			var id: int = int(bot_ids.pop_back())
			world.players.erase(id)
			bot_memory.erase(id)
			_match_ids.erase(id)
			player_views[id].queue_free()
			player_views.erase(id)
			_begin_recording()
		elif key == KEY_F5:
			Tuning.DEV_SLOWMO_ENABLED = not Tuning.DEV_SLOWMO_ENABLED
		elif key == KEY_F6:
			Tuning.DEV_HITBOX_ENABLED = not Tuning.DEV_HITBOX_ENABLED
		elif key == KEY_F7:
			Tuning.DEV_VELOCITY_ENABLED = not Tuning.DEV_VELOCITY_ENABLED
		elif key == KEY_F8:
			Tuning.HUD_DEBUG_ENABLED = not Tuning.HUD_DEBUG_ENABLED
			game_hud.debug_visible = Tuning.HUD_DEBUG_ENABLED
		elif key == KEY_F9 and world.players.has(local_id):
			world.players[local_id].damage += Tuning.DEV_DAMAGE_AMOUNT
			_begin_recording()
		elif key == KEY_F10 and world.players.has(local_id):
			var player: Dictionary = world.players[local_id]
			player.position = Vector3(0, Tuning.CENTER_HEIGHT + Tuning.BODY_HEIGHT * 0.5, 0)
			player.velocity = Vector3.ZERO
			player.on_ground = true
			_begin_recording()
		elif key == KEY_F11:
			save_replay()
		elif key == KEY_F12:
			replay_latest()
	_dev_actions.clear()

func _can_edit_tuning(name: String) -> bool:
	if network == null or not network.active or network.hosting:
		return true
	return name.begins_with("NET_") or name.begins_with("CAMERA_") or name.begins_with("VIS_") or name.begins_with("JUICE_") or name.begins_with("HUD_") or name.begins_with("AUDIO_") or name.begins_with("MUSIC_") or name.begins_with("SFX_") or name in ["MOUSE_SENSITIVITY", "PITCH_INITIAL", "DEV_HITBOX_ENABLED", "DEV_VELOCITY_ENABLED", "DEV_VELOCITY_SCALE", "DEV_GIZMO_SEGMENTS"]

func _on_network_lobby() -> void:
	if network.active and network.flow.get("phase", "lobby") == "lobby":
		network_ui.show_lobby()

func _on_network_world(next_world: Dictionary, next_flow: Dictionary) -> void:
	var previous_phase: String = str(flow.get("phase", "menu"))
	local_id = network.local_id
	world = next_world
	flow = next_flow
	if world.is_empty():
		_clear_players()
		juice.clear()
		game_hud.reset_match()
		network_ui.show_lobby()
		return
	if _network_view_epoch != network.epoch or player_views.keys() != world.players.keys():
		_network_view_epoch = network.epoch
		_clear_players()
		for id in world.players:
			player_views[id] = _build_player(int(id))
		_match_ids = world.players.keys()
		bot_ids = []
		for id in _match_ids:
			if id < 0:
				bot_ids.append(id)
		juice.clear()
		game_hud.reset_match()
		tuning_panel.set_open(false)
		yaw = float(world.players.get(local_id, {}).get("yaw", 0.0))
		pitch = Tuning.PITCH_INITIAL
		paused = false
		menu_overlay.hide()
		_last_countdown = -1
	if network.hosting:
		recording = network.recording
	if flow.phase == "countdown" and int(flow.countdown) != _last_countdown:
		_last_countdown = int(flow.countdown)
		synth.countdown(_last_countdown)
	if flow.phase == "winner" and previous_phase != "winner":
		if network.hosting:
			latest_tape = recording
			save_replay()
		_show_winner()
	_sync_cursor()

func _on_network_events(events: Array, event_world: Dictionary) -> void:
	var rendered_world: Dictionary = world
	world = event_world
	_dispatch_events(events)
	world = rendered_world

func _on_network_error(reason: String) -> void:
	network_ui.show_error(reason)

func _on_network_settings(values: Dictionary) -> void:
	_receiving_network_settings = true
	_apply_settings(values)
	_receiving_network_settings = false
