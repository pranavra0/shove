class_name MatchSim
extends RefCounted

# The scene owns menu/setup entry and World stepping; this state only tracks round flow.
static func create() -> Dictionary:
	return {
		"phase": "menu", "elapsed": 0.0, "winner": -1, "winner_team": -1,
		"countdown": int(ceil(Tuning.MATCH_COUNTDOWN)),
		"resume_phase": "playing", "last_event_tick": -1,
	}

static func step(state: Dictionary, world: Dictionary, dt: float) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	var phase: String = result.phase
	if phase == "menu" or phase == "setup" or phase == "winner":
		return result
	result.elapsed = float(result.elapsed) + maxf(dt, 0.0)
	var mode: String = str(world.get("mode", "ffa"))
	if mode == "control":
		var control: Dictionary = world.get("control", {})
		result.winner_team = int(control.get("winner_team", -1))
	if phase == "countdown":
		result.countdown = int(ceil(maxf(0.0, Tuning.MATCH_COUNTDOWN - float(result.elapsed))))
		if result.elapsed >= Tuning.MATCH_COUNTDOWN:
			_enter(result, "playing")
		return result
	if phase == "round_end":
		if result.elapsed >= Tuning.MATCH_ROUND_END:
			_enter(result, "winner")
		return result
	if phase != "playing" and phase != "ringout":
		return result
	if mode == "control":
		if int(result.winner_team) >= 0:
			_enter(result, "round_end")
			return result
		var control_ko: bool = false
		if int(world.tick) != int(result.last_event_tick):
			result.last_event_tick = int(world.tick)
			for event: Dictionary in world.events:
				if str(event.get("type", "")) == "ko":
					control_ko = true
					break
		if control_ko:
			result.resume_phase = "playing"
			_enter(result, "ringout")
		elif phase == "ringout" and result.elapsed >= Tuning.MATCH_RINGOUT_TIME:
			_enter(result, "playing")
		return result
	var live: Array = []
	for id in world.players:
		if world.players[id].stocks > 0:
			live.append(id)
	# A sole participant is practice, not an immediate win. Losing all stocks still ends it.
	var finished: bool = live.is_empty() or (world.players.size() > 1 and live.size() == 1)
	var ko: bool = false
	if int(world.tick) != int(result.last_event_tick):
		result.last_event_tick = int(world.tick)
		for event in world.events:
			if event.type == "ko":
				ko = true
				break
	if ko:
		result.resume_phase = "round_end" if finished else "playing"
		_enter(result, "ringout")
	elif phase == "ringout":
		result.resume_phase = "round_end" if finished else "playing"
		if result.elapsed >= Tuning.MATCH_RINGOUT_TIME:
			_enter(result, result.resume_phase)
	elif finished:
		_enter(result, "round_end")
	if result.phase == "round_end":
		result.winner = int(live[0]) if live.size() == 1 else -1
	return result

static func _enter(state: Dictionary, phase: String) -> void:
	state.phase = phase
	state.elapsed = 0.0
