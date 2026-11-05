class_name TuningPanel
extends CanvasLayer

signal tuning_changed(name: String, value: Variant)
signal panel_visibility_changed(opened: bool)

const Store = preload("res://scripts/dev/tuning_store.gd")
var _app: Node
var _root: PanelContainer
var _search: LineEdit
var _filename: LineEdit
var _status: Label
var _list: VBoxContainer
var _rows: Dictionary = {}
var _factory: Dictionary = Store.defaults()
var _groups: Dictionary = {}

func setup(app: Node) -> void:
	_app = app
	if _root != null:
		return
	layer = 90
	_root = PanelContainer.new()
	var tuning_theme: Theme = app.menu_overlay.theme.duplicate()
	tuning_theme.default_font_size = 13
	var neutral := StyleBoxFlat.new()
	neutral.bg_color = Color(0.075, 0.085, 0.095, 0.96)
	neutral.border_color = Color(0.28, 0.30, 0.33, 0.9)
	neutral.set_border_width_all(1)
	tuning_theme.set_stylebox("panel", "PanelContainer", neutral)
	var button_style := StyleBoxFlat.new()
	button_style.bg_color = Color(0.12, 0.13, 0.15, 0.96)
	button_style.border_color = Color(0.30, 0.32, 0.35, 0.9)
	button_style.set_border_width_all(1)
	button_style.content_margin_left = 9
	button_style.content_margin_right = 9
	button_style.content_margin_top = 5
	button_style.content_margin_bottom = 5
	var button_hover: StyleBoxFlat = button_style.duplicate()
	button_hover.bg_color = Color(0.19, 0.20, 0.22, 0.98)
	var button_pressed: StyleBoxFlat = button_style.duplicate()
	button_pressed.bg_color = Color(0.09, 0.10, 0.11, 0.98)
	tuning_theme.set_stylebox("normal", "Button", button_style)
	tuning_theme.set_stylebox("hover", "Button", button_hover)
	tuning_theme.set_stylebox("focus", "Button", button_hover)
	tuning_theme.set_stylebox("pressed", "Button", button_pressed)
	_root.theme = tuning_theme
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.offset_left = 24.0
	_root.offset_top = 24.0
	_root.offset_right = -24.0
	_root.offset_bottom = -24.0
	add_child(_root)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_root.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	margin.add_child(body)
	_search = LineEdit.new()
	_search.placeholder_text = "Search tuning fields…"
	_search.custom_minimum_size.y = 30
	_search.text_changed.connect(_filter)
	body.add_child(_search)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	_filename = LineEdit.new()
	_filename.text = "custom.json"
	_filename.placeholder_text = "Preset filename"
	_filename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_filename)
	_button(actions, "Save", func(): _save())
	_button(actions, "Load", func(): _load(_user_path()))
	_button(actions, "Reset defaults", func(): _apply_values(Store.defaults()))
	_button(actions, "Copy diff", _copy_diff)
	var presets := HBoxContainer.new()
	body.add_child(presets)
	var picker := OptionButton.new()
	picker.add_item("Shipped presets…")
	for preset in ["Source-tight", "Quake-fast", "Chaos"]:
		picker.add_item(preset)
	picker.item_selected.connect(func(index: int):
		if index > 0:
			_load("res://presets/" + picker.get_item_text(index) + ".json")
	)
	presets.add_child(picker)
	if app.has_method("replay_latest"):
		_button(presets, "Replay latest", func(): _app.call("replay_latest"))
		_button(presets, "Save replay", func(): _app.call("save_replay"))
	_status = Label.new()
	_status.text = "Changes apply immediately. Presets save to user://presets/."
	_status.add_theme_color_override("font_color", Color(0.66, 0.68, 0.71))
	body.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	var invariants := Label.new()
	invariants.text = "Read-only: TICK_RATE = %s · FIXED_DELTA = %s · METRES_TO_SOURCE_UNITS = %s" % [Tuning.TICK_RATE, Tuning.FIXED_DELTA, Tuning.METRES_TO_SOURCE_UNITS]
	invariants.add_theme_font_size_override("font_size", 12)
	invariants.add_theme_color_override("font_color", Color(0.58, 0.60, 0.63))
	invariants.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(invariants)
	_rebuild()
	_root.hide()

func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)

func toggle() -> void:
	set_open(not is_open())

func is_open() -> bool:
	return _root != null and _root.visible

func set_open(opened: bool) -> void:
	if _root == null or opened == is_open():
		return
	_root.visible = opened
	if opened:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_rebuild()
		_search.grab_focus()
	panel_visibility_changed.emit(opened)

func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_groups.clear()
	var names := Store.fields()
	names.sort()
	for name in names:
		var group: String = name.get_slice("_", 0)
		if not _groups.has(group):
			var heading := Label.new()
			heading.text = group
			heading.add_theme_font_size_override("font_size", 12)
			heading.add_theme_color_override("font_color", Color(0.62, 0.64, 0.67))
			_list.add_child(heading)
			_groups[group] = heading
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		_rows[name] = row
		var label := Label.new()
		label.text = name
		label.custom_minimum_size.x = 300.0
		label.add_theme_color_override("font_color", Color(0.78, 0.79, 0.81))
		label.tooltip_text = name
		row.add_child(label)
		_editor(row, name, Tuning.get(name))
	var computed := Label.new()
	computed.text = "MAX_GROUND_ANGLE (computed, read-only): %.6f radians" % Tuning.MAX_GROUND_ANGLE
	computed.add_theme_font_size_override("font_size", 12)
	computed.add_theme_color_override("font_color", Color(0.58, 0.60, 0.63))
	_list.add_child(computed)
	_filter(_search.text)

func _editor(row: HBoxContainer, name: String, value: Variant) -> void:
	if value is bool:
		var checkbox := CheckBox.new()
		checkbox.button_pressed = value
		checkbox.toggled.connect(func(next: bool): _change(name, next))
		row.add_child(checkbox)
	elif value is float or value is int:
		var limits := Store.bounds(name, _factory[name])
		_numeric(row, float(value), limits, typeof(value) == TYPE_INT, func(next: float): _change(name, int(next) if value is int else next))
	elif value is Color:
		_color(row, value, func(next: Color): _change(name, next))
	elif value is Vector2 or value is Vector3:
		var count: int = 2 if value is Vector2 else 3
		for index in range(count):
			var component := SpinBox.new()
			component.min_value = 0.001 if name == "HUD_REFERENCE_SIZE" else -1000000.0
			component.max_value = 1000000.0
			component.step = 0.001
			component.value = value[index]
			component.prefix = ["x: ", "y: ", "z: "][index]
			component.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			component.value_changed.connect(func(next: float):
				var vector: Variant = Tuning.get(name)
				vector[index] = next
				_change(name, vector)
			)
			row.add_child(component)
	elif value is Array:
		var palette := HFlowContainer.new()
		palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(palette)
		for index in range(value.size()):
			_color(palette, value[index], func(next: Color):
				var colors: Array[Color] = Tuning.get(name).duplicate()
				colors[index] = next
				_change(name, colors)
			)

func _color(parent: Node, value: Color, changed: Callable) -> void:
	var picker := ColorPickerButton.new()
	picker.color = value
	picker.custom_minimum_size = Vector2(48.0, 28.0)
	picker.color_changed.connect(changed)
	parent.add_child(picker)

func _numeric(row: HBoxContainer, value: float, limits: Vector2, integer: bool, changed: Callable) -> void:
	var slider := HSlider.new()
	var spin := SpinBox.new()
	for control in [slider, spin]:
		control.min_value = limits.x
		control.max_value = limits.y
		control.step = 1.0 if integer else 0.0001
		control.value = value
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 100.0
	spin.custom_minimum_size.x = 150.0
	row.add_child(slider)
	row.add_child(spin)
	slider.value_changed.connect(func(next: float):
		spin.set_value_no_signal(next)
		changed.call(next)
	)
	spin.value_changed.connect(func(next: float):
		slider.set_value_no_signal(next)
		changed.call(next)
	)

func _change(name: String, value: Variant) -> void:
	if Tuning.get(name) == value:
		return
	if _app.has_method("_can_edit_tuning") and not _app.call("_can_edit_tuning", name):
		_status.text = "The host owns simulation tuning; local camera/audio/network controls remain editable."
		return
	var decoded := Store.decode(Store.encode({name: value}))
	if decoded.is_empty():
		_status.text = "Rejected unsafe value for " + name
		return
	Tuning.set(name, decoded[name])
	tuning_changed.emit(name, decoded[name])
	_status.text = "Changed " + name

func _apply_values(values: Dictionary) -> void:
	var valid := Store.decode(Store.encode(values))
	if valid.is_empty():
		_status.text = "Preset is empty or invalid; nothing changed."
		return
	var previous := Store.snapshot()
	for name in valid:
		if previous[name] != valid[name] and _app.has_method("_can_edit_tuning") and not _app.call("_can_edit_tuning", name):
			_status.text = "Preset rejected: the host owns simulation tuning."
			return
	Store.apply(valid)
	for name in valid:
		if previous[name] != Tuning.get(name):
			tuning_changed.emit(name, Tuning.get(name))
	_rebuild()
	_status.text = "Applied %d fields." % valid.size()

func _filter(query: String) -> void:
	var groups: Dictionary = {}
	for name in _rows:
		var matches: bool = query.is_empty() or query.to_lower() in name.to_lower()
		_rows[name].visible = matches
		if matches:
			groups[name.get_slice("_", 0)] = true
	for group in _groups:
		_groups[group].visible = groups.has(group)

func _user_path() -> String:
	var filename := _filename.text.strip_edges().get_file()
	if filename.is_empty():
		filename = "custom.json"
	if not filename.ends_with(".json"):
		filename += ".json"
	return "user://presets/" + filename

func _save() -> void:
	var error := Store.save(_user_path(), Store.snapshot())
	_status.text = "Saved " + _user_path() if error == OK else "Save failed: " + error_string(error)

func _load(path: String) -> void:
	var values := Store.load_values(path)
	if path.begins_with("res://presets/") and not values.is_empty():
		var complete := Store.defaults()
		complete.merge(values, true)
		values = complete
	_apply_values(values)

func _copy_diff() -> void:
	var factory := Store.defaults()
	var lines := PackedStringArray()
	for name in Store.fields():
		var value: Variant = Tuning.get(name)
		if value != factory[name]:
			lines.append("var %s = %s" % [name, var_to_str(value)])
	var text := "\n".join(lines)
	print(text)
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(text)
	_status.text = "Copied %d changed fields (also printed)." % lines.size()
