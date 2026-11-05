extends Control

# Screen-space effects share the render clock, never the simulation clock.
var flash_remaining: float = 0.0
var speed_strength: float = 0.0
var motion_tick: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func advance(delta: float, speed: float, tick: int) -> void:
	flash_remaining = maxf(0.0, flash_remaining - delta)
	motion_tick = tick
	var span: float = maxf(0.001, Tuning.JUICE_SPEED_LINES_FULL_SPEED - Tuning.JUICE_SPEED_LINES_THRESHOLD)
	speed_strength = clampf((speed - Tuning.JUICE_SPEED_LINES_THRESHOLD) / span, 0.0, 1.0)
	queue_redraw()

func flash() -> void:
	if Tuning.JUICE_HIT_FLASH_ENABLED:
		flash_remaining = Tuning.JUICE_HIT_FLASH_DURATION

func _draw() -> void:
	if Tuning.JUICE_HIT_FLASH_ENABLED and flash_remaining > 0.0:
		var life: float = flash_remaining / maxf(0.001, Tuning.JUICE_HIT_FLASH_DURATION)
		var tint: Color = Tuning.JUICE_IVORY
		tint.a = Tuning.JUICE_HIT_FLASH_STRENGTH * life * life
		draw_rect(Rect2(Vector2.ZERO, size), tint)
	if not Tuning.JUICE_SPEED_LINES_ENABLED or speed_strength <= 0.0:
		return
	var centre: Vector2 = size * 0.5
	for index in range(maxi(0, Tuning.JUICE_SPEED_LINES_COUNT)):
		# Integer hashing is reproducible for a given World tick and line index.
		var seed_value: int = ((index + 1) * 73856093 + (motion_tick / 5) * 19349663) & 0x7fffffff
		var fraction: float = float(seed_value % 1009) / 1009.0
		var angle: float = TAU * float(index) / maxf(1.0, Tuning.JUICE_SPEED_LINES_COUNT) + fraction * 0.17
		var direction := Vector2(cos(angle), sin(angle))
		var edge_distance: float = minf(centre.x / maxf(0.001, absf(direction.x)), centre.y / maxf(0.001, absf(direction.y)))
		var outside: Vector2 = centre + direction * edge_distance * (1.0 + fraction * 0.08)
		var inside: Vector2 = outside - direction * edge_distance * Tuning.JUICE_SPEED_LINES_LENGTH * (0.5 + fraction) * speed_strength
		var color: Color = Tuning.JUICE_CYAN if index % 3 else Tuning.JUICE_IVORY
		color.a = Tuning.JUICE_SPEED_LINES_STRENGTH * speed_strength * (0.3 + fraction * 0.7)
		draw_line(inside, outside, color, Tuning.JUICE_SPEED_LINES_WIDTH, true)
