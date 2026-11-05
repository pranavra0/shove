class_name NetworkLobby
extends RefCounted

const COLOR_NAMES := ["Cyan", "Coral", "Lilac", "Gold", "Mint", "Pink", "Blue", "Amber"]
var app: Node
var _stats_layer: CanvasLayer
var _stats_label: Label

func setup(owner: Node) -> void:
	app = owner
	_stats_layer = CanvasLayer.new()
	_stats_layer.layer = 4
	app.add_child(_stats_layer)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 12)
	_stats_label.add_theme_color_override("font_color", Color("#dddddd"))
	_stats_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	_stats_label.add_theme_constant_override("shadow_offset_x", 0)
	_stats_label.add_theme_constant_override("shadow_offset_y", 0)
	_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_layer.add_child(_stats_label)

func show_setup(hosting: bool) -> void:
	app.flow.phase = "setup"
	app._clear_menu("Host a match" if hosting else "Join a match")
	app._menu_label("2–8 players")
	app._menu_field("Player name", "PlayerName", "Player")
	var colors := OptionButton.new()
	colors.name = "PlayerColor"
	for label in COLOR_NAMES:
		colors.add_item(label)
	app.menu_panel.add_child(colors)
	if not hosting:
		app._menu_field("Server IP", "ServerAddress", "127.0.0.1")
	app._menu_label("UDP port")
	var port := SpinBox.new()
	port.name = "Port"
	port.min_value = 1
	port.max_value = 65535
	port.value = Tuning.NET_PORT
	app.menu_panel.add_child(port)
	app._menu_button("Host" if hosting else "Connect", "Connect", func() -> void:
		var player_name: String = app.menu_panel.find_child("PlayerName", true, false).text.strip_edges()
		var selected_port: int = int(port.value)
		var color: int = colors.selected
		var error: Error
		if hosting:
			error = app.network.host(selected_port, player_name, color)
		else:
			var address: String = app.menu_panel.find_child("ServerAddress", true, false).text.strip_edges()
			error = app.network.join(address, selected_port, player_name, color)
		if error != OK:
			show_error("Cannot open connection: " + error_string(error))
		elif hosting:
			show_lobby()
		else:
			app._clear_menu("Connecting…")
			app._menu_label("Waiting for the host. Check the IP and UDP port.")
			app._menu_button("Cancel", "Cancel", app.show_menu)
	)
	app._menu_button("Back", "Back", app.show_menu)

func show_lobby() -> void:
	var net: NetSession = app.network
	app.local_id = net.local_id
	app.flow.phase = "lobby"
	app._clear_menu("Lobby")
	var ids: Array = net.members.keys()
	ids.sort()
	var human_count: int = 0
	for id in ids:
		var member: Dictionary = net.members[id]
		if not member.get("bot", false):
			human_count += 1
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s%s" % [member.name, " (you)" if id == net.local_id else ""]
		label.custom_minimum_size.x = 225
		row.add_child(label)
		var status := Label.new()
		status.text = "BOT" if member.get("bot", false) else ("READY" if member.ready else "WAITING")
		row.add_child(status)
		app.menu_panel.add_child(row)
	if net.members.has(net.local_id):
		var self_member: Dictionary = net.members[net.local_id]
		var ready := CheckButton.new()
		ready.name = "Ready"
		ready.text = "Ready to play"
		ready.button_pressed = self_member.ready
		ready.toggled.connect(net.set_ready)
		app.menu_panel.add_child(ready)
		var colors := OptionButton.new()
		colors.name = "LobbyColor"
		for label in COLOR_NAMES:
			colors.add_item(label)
		colors.select(clampi(int(self_member.color), 0, COLOR_NAMES.size() - 1))
		colors.item_selected.connect(func(index: int) -> void: net.set_profile(self_member.name, index, self_member.ready))
		app.menu_panel.add_child(colors)
	if net.hosting:
		app._menu_label("Bot fill")
		var fill := OptionButton.new()
		fill.name = "BotFill"
		for count in range(maxi(0, 8 - human_count) + 1):
			fill.add_item("%d bot%s" % [count, "" if count == 1 else "s"], count)
		fill.select(clampi(net.bot_fill, 0, fill.item_count - 1))
		fill.item_selected.connect(func(index: int) -> void: net.set_bot_fill(fill.get_item_id(index)))
		app.menu_panel.add_child(fill)
		var start: Button = app._menu_button("Start match", "HostStart", func() -> void: net.start_match())
		var all_ready: bool = human_count + net.bot_fill >= 2
		for member in net.members.values():
			if not member.get("bot", false) and not member.ready:
				all_ready = false
		start.disabled = not all_ready
	app._menu_button("Leave session", "LeaveSession", app.show_menu)
	app._sync_cursor()

func show_pause(value: bool) -> void:
	app.paused = value
	if not value:
		app.menu_overlay.hide()
	else:
		app._clear_menu("Online match continues")
		app._menu_button("Resume", "Resume", show_pause.bind(false))
		app._menu_button("Leave session", "LeaveSession", app.show_menu)
	app._sync_cursor()

func show_winner() -> void:
	var winner: int = int(app.flow.winner)
	var name: String = str(app.network.members.get(winner, {}).get("name", "No one"))
	var result: String = "It’s a draw." if winner == -1 else ("You win." if winner == app.local_id else name + " wins.")
	app._clear_menu(result)
	if app.network.hosting:
		app._menu_button("Rematch", "Rematch", func() -> void: app.network.start_match())
		app._menu_button("Return to lobby", "ReturnLobby", app.network.return_to_lobby)
	app._menu_button("Leave session", "LeaveSession", app.show_menu)
	app._sync_cursor()

func show_error(reason: String) -> void:
	app.network.close()
	app.show_menu()
	app.flow.phase = "setup"
	app._clear_menu("Connection closed")
	app._menu_label(reason)
	app._menu_button("Back", "Back", app.show_menu)

func render_frame() -> void:
	_stats_label.visible = app.network.active and Tuning.NET_DEBUG_ENABLED
	if not _stats_label.visible:
		return
	var stats: Dictionary = app.network.stats
	_stats_label.position = Vector2(app.get_viewport().get_visible_rect().size.x - 285, 66)
	_stats_label.text = "%s / ENet\nRTT %.0f ms · %.1f snapshots/s\nCorrection %.3f m · pending %d\nSimulated drops %d" % ["HOST" if app.network.hosting else "CLIENT", float(stats.get("ping", 0.0)), float(stats.get("snapshot_rate", 0.0)), float(stats.get("correction", 0.0)), int(stats.get("input_depth", 0)), int(stats.get("dropped", 0))]
