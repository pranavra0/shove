class_name SynthAudio
extends Node

# All streams are baked once at startup. Playback only reuses a fixed voice pool.
var _samples: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_cursor: int = 0
var _music: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _wind_amount: float = 0.0
var _foot_distance: float = 0.0
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _sample_rate: int

func _ready() -> void:
	rebuild()

func _exit_tree() -> void:
	for voice in _voices:
		voice.stop()
		voice.stream = null
	if is_instance_valid(_music):
		_music.stop()
		_music.stream = null
	if is_instance_valid(_wind):
		_wind.stop()
		_wind.stream = null
	_samples.clear()

# Explicit configuration boundary for sample-rate, tempo and voice-count changes.
# Ordinary volume and enable changes are applied without rebuilding any samples.
func rebuild() -> void:
	for voice in _voices:
		voice.stop()
		voice.free()
	_voices.clear()
	if is_instance_valid(_music):
		_music.stop()
		_music.free()
	if is_instance_valid(_wind):
		_wind.stop()
		_wind.free()
	_samples.clear()
	_voice_cursor = 0
	_foot_distance = 0.0
	_wind_amount = 0.0
	_sample_rate = maxi(8000, Tuning.AUDIO_SAMPLE_RATE)
	_random.seed = 73191
	for kind in ["jump", "land", "whoosh", "hit", "ko", "countdown", "go", "ui", "footstep"]:
		_samples[kind] = _bake_effect(kind)
	for index in range(maxi(1, Tuning.AUDIO_VOICES)):
		var voice := AudioStreamPlayer.new()
		voice.name = "SFX%d" % index
		add_child(voice)
		_voices.append(voice)
	_music = AudioStreamPlayer.new()
	_music.name = "ProceduralMusic"
	_music.stream = _bake_music()
	add_child(_music)
	_wind = AudioStreamPlayer.new()
	_wind.name = "SpeedWind"
	_wind.stream = _bake_wind()
	_wind.volume_db = -80.0
	add_child(_wind)
	_wind.play()
	_process(0.0)

func _process(_delta: float) -> void:
	if _music == null:
		return
	_music.volume_db = _volume_db(Tuning.MUSIC_VOLUME)
	if Tuning.MUSIC_ENABLED and Tuning.MUSIC_VOLUME > 0.0:
		if not _music.playing:
			_music.play()
	elif _music.playing:
		_music.stop()
	for voice in _voices:
		voice.volume_db = _volume_db(Tuning.SFX_VOLUME)
	_wind.volume_db = _volume_db(Tuning.SFX_VOLUME * Tuning.AUDIO_WIND_GAIN * _wind_amount)

func play_event(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"jump":
			_play("jump")
		"land":
			_play("land")
		"shove", "whoosh":
			_play("whoosh")
		"hit":
			var strength := clampf(float(event.get("strength", 0.0)) / maxf(0.01, Tuning.AUDIO_HIT_STRENGTH_REFERENCE), 0.0, 1.0)
			# Bigger impacts sound heavier, rather than merely louder.
			_play("hit", lerpf(Tuning.AUDIO_HIT_MAX_PITCH, Tuning.AUDIO_HIT_MIN_PITCH, strength))
		"ko":
			_play("ko")
		"countdown":
			countdown(int(event.get("number", 3)))
		"ui":
			ui_click()

func update_motion(speed: float, grounded: bool, delta: float) -> void:
	if _wind == null:
		return
	var dt := maxf(delta, 0.0)
	var amount := clampf((speed - Tuning.AUDIO_WIND_START_SPEED) / maxf(0.01, Tuning.AUDIO_WIND_FULL_SPEED - Tuning.AUDIO_WIND_START_SPEED), 0.0, 1.0)
	_wind_amount = lerpf(_wind_amount, amount, 1.0 - exp(-Tuning.AUDIO_WIND_SMOOTHING * dt))
	_wind.pitch_scale = lerpf(0.65, 1.8, _wind_amount)
	if grounded and speed >= Tuning.AUDIO_FOOTSTEP_MIN_SPEED:
		_foot_distance += speed * dt
		if _foot_distance >= maxf(0.1, Tuning.AUDIO_FOOTSTEP_DISTANCE):
			_foot_distance = fmod(_foot_distance, maxf(0.1, Tuning.AUDIO_FOOTSTEP_DISTANCE))
			_play("footstep", _random.randf_range(0.9, 1.1))
	else:
		_foot_distance = 0.0

func ui_click() -> void:
	_play("ui")

func countdown(number: int) -> void:
	if number <= 0:
		_play("go")
	else:
		_play("countdown", 1.0 + float(clampi(3 - number, 0, 2)) * 0.1)

func _play(kind: String, pitch: float = 1.0) -> void:
	if _voices.is_empty() or Tuning.SFX_VOLUME <= 0.0:
		return
	var selected: AudioStreamPlayer = _voices[_voice_cursor]
	for offset in range(_voices.size()):
		var candidate: AudioStreamPlayer = _voices[(_voice_cursor + offset) % _voices.size()]
		if not candidate.playing:
			selected = candidate
			break
	_voice_cursor = (_voice_cursor + 1) % _voices.size()
	selected.stream = _samples[kind]
	selected.pitch_scale = maxf(0.01, pitch)
	selected.volume_db = _volume_db(Tuning.SFX_VOLUME)
	selected.play()

func _volume_db(linear: float) -> float:
	return linear_to_db(clampf(linear, 0.0001, 1.0)) if linear > 0.0 else -80.0

func _wav(bytes: PackedByteArray, looping: bool = false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _sample_rate
	stream.stereo = false
	stream.data = bytes
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = bytes.size() / 2
	return stream

func _pcm(bytes: PackedByteArray, index: int, sample: float) -> void:
	bytes.encode_s16(index * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

func _bake_effect(kind: String) -> AudioStreamWAV:
	var duration: float = {"jump": 0.22, "land": 0.18, "whoosh": 0.24, "hit": 0.28, "ko": 0.95, "countdown": 0.19, "go": 0.48, "ui": 0.07, "footstep": 0.085}[kind]
	var count := int(duration * _sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase := 0.0
	var filtered_noise := 0.0
	for index in range(count):
		var t := float(index) / _sample_rate
		var progress := t / duration
		var noise := _random.randf_range(-1.0, 1.0)
		filtered_noise = lerpf(filtered_noise, noise, 0.22)
		var envelope := minf(t * 500.0, 1.0) * pow(1.0 - progress, 2.0)
		var sample := 0.0
		match kind:
			"jump":
				phase += TAU * lerpf(290.0, 820.0, progress) / _sample_rate
				sample = sin(phase) * 0.42 + sin(phase * 2.0) * 0.1
			"land", "footstep":
				phase += TAU * lerpf(125.0, 45.0, progress) / _sample_rate
				sample = sin(phase) * 0.5 + filtered_noise * 0.6
				if kind == "footstep":
					sample *= 0.4
			"whoosh":
				sample = filtered_noise * sin(PI * progress) * 1.8
			"hit":
				phase += TAU * lerpf(180.0, 35.0, progress) / _sample_rate
				sample = sin(phase) * 0.65 + noise * exp(-t * 40.0) * 0.35
			"ko":
				phase += TAU * lerpf(650.0, 65.0, progress) / _sample_rate
				sample = sin(phase) * 0.45 + sin(phase * 1.5) * 0.22 + filtered_noise * 0.2
			"countdown", "go":
				phase += TAU * (880.0 if kind == "go" else 440.0) / _sample_rate
				sample = sin(phase) * 0.4 + sin(phase * 1.5) * 0.12
			"ui":
				phase += TAU * lerpf(1350.0, 850.0, progress) / _sample_rate
				sample = sin(phase) * 0.32
		_pcm(bytes, index, sample * envelope)
	return _wav(bytes)

func _bake_wind() -> AudioStreamWAV:
	# Integer harmonics make the two-second wind bed exactly periodic.
	var count := _sample_rate * 2
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for index in range(count):
		var phase := TAU * float(index) / count
		var sample := sin(phase * 113.0 + sin(phase * 7.0) * 3.0) * 0.22
		sample += sin(phase * 197.0 + sin(phase * 11.0) * 5.0) * 0.16
		sample += sin(phase * 311.0 + sin(phase * 17.0) * 4.0) * 0.09
		_pcm(bytes, index, sample)
	return _wav(bytes, true)

func _bake_music() -> AudioStreamWAV:
	# Eight bars of restrained D-minor neon synth: bass, sixteenth arp and drums.
	var beat := 60.0 / maxf(1.0, Tuning.AUDIO_MUSIC_BPM)
	var count := int(32.0 * beat * _sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var roots: Array[int] = [38, 38, 34, 34, 41, 41, 36, 36]
	var intervals: Array[int] = [0, 7, 12, 15, 12, 7, 19, 15]
	for index in range(count):
		var t := float(index) / _sample_rate
		var beats := t / beat
		var bar := mini(7, int(beats / 4.0))
		var root := 440.0 * pow(2.0, float(roots[bar] - 69) / 12.0)
		var bass_t := fmod(t, beat * 0.5)
		var bass_env := minf(bass_t * 100.0, 1.0) * exp(-bass_t * 7.0)
		var sample := (sin(TAU * root * bass_t) + 0.22 * sin(TAU * root * 2.0 * bass_t)) * bass_env * 0.26
		var arp_t := fmod(t, beat * 0.25)
		var arp_note := intervals[int(beats * 4.0) % intervals.size()]
		var arp_hz := root * 4.0 * pow(2.0, float(arp_note) / 12.0)
		var arp_env := minf(arp_t * 200.0, 1.0) * exp(-arp_t * 23.0)
		sample += (sin(TAU * arp_hz * arp_t) + sin(TAU * arp_hz * 2.0 * arp_t) * 0.18) * arp_env * 0.12
		var drum_t := fmod(t, beat)
		var kick_phase := TAU * (48.0 * drum_t + 95.0 * (1.0 - exp(-drum_t * 35.0)) / 35.0)
		sample += sin(kick_phase) * exp(-drum_t * 18.0) * minf(drum_t * 600.0, 1.0) * 0.32
		var noise := _random.randf_range(-1.0, 1.0)
		if int(beats) % 2 == 1:
			sample += noise * exp(-drum_t * 30.0) * minf(drum_t * 800.0, 1.0) * 0.15
		var hat_t := fmod(t, beat * 0.5)
		sample += noise * exp(-hat_t * 110.0) * minf(hat_t * 1000.0, 1.0) * 0.055
		# Finish at silence so sample quantization cannot click across the loop.
		var edge := minf(1.0, minf(t, float(count - 1 - index) / _sample_rate) * 250.0)
		_pcm(bytes, index, sample * edge)
	return _wav(bytes, true)
