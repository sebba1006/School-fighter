extends Node
## Sound effects and music, all synthesised in code (no audio files), in a
## retro chiptune style. main.gd adds one of these; everything else calls the
## static helpers:  Audio.play("hit"),  Audio.start_music(),  Audio.set_enabled(false)

const RATE := 22050
const MUSIC_RATE := 11025
const SETTINGS_PATH := "user://settings.cfg"
const VOICES := 8

static var instance: Node = null

var enabled := true
var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_ready := false
var _music_building := false


func _ready() -> void:
	instance = self
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		enabled = cfg.get_value("audio", "enabled", true)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -15.0
	add_child(_music)
	_build_sounds()


static func play(name: String) -> void:
	if instance != null and instance.enabled:
		instance._play(name)


static func start_music() -> void:
	if instance != null:
		instance._start_music()


static func is_enabled() -> bool:
	return instance == null or instance.enabled


static func set_enabled(on: bool) -> void:
	if instance == null:
		return
	instance.enabled = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "enabled", on)
	cfg.save(SETTINGS_PATH)
	if on:
		instance._start_music()
	else:
		instance._music.stop()


func _play(name: String) -> void:
	if not _sounds.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[name]
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()


# ---------------------------------------------------------------- sound effects

func _build_sounds() -> void:
	_sounds.step = _wav(_tone(0.04, 300, 200, "tri", 0.25, 2.0))
	_sounds.whoosh = _wav(_noise(0.12, 0.22, 1.5, 2))
	_sounds.hit = _wav(_mix(_noise(0.08, 0.35, 3.0, 1), _tone(0.14, 160, 70, "sine", 0.55, 2.0)))
	_sounds.slam = _wav(_mix(_noise(0.25, 0.4, 2.0, 3), _tone(0.3, 90, 40, "sine", 0.55, 1.5)))
	_sounds.ko = _wav(_tone(0.6, 440, 110, "square", 0.28, 1.0))
	_sounds.block = _wav(_mix(_tone(0.18, 900, 900, "sine", 0.4, 3.0), _tone(0.18, 1350, 1350, "sine", 0.3, 3.0)))
	_sounds["break"] = _wav(_noise(0.25, 0.5, 1.5, 8))
	_sounds.dizzy = _wav(_wobble(0.35, 700, 150, 12, 0.3))
	_sounds.click = _wav(_tone(0.03, 1000, 1000, "square", 0.18, 2.0))
	_sounds.turn = _wav(_tone(0.12, 660, 880, "tri", 0.3, 1.0))
	_sounds["super"] = _wav(_notes([72, 76, 79, 84], 0.07, 0.25, "square", 0.3))
	# dog barks: a short "wuf" and the big Mega Woof
	var bark := _mix(_tone(0.11, 560, 320, "square", 0.3, 1.4), _noise(0.07, 0.12, 2.0, 2))
	var bark2 := _mix(_tone(0.11, 500, 280, "square", 0.3, 1.4), _noise(0.07, 0.12, 2.0, 2))
	var gap := PackedFloat32Array()
	gap.resize(int(0.05 * RATE))
	_sounds.bark = _wav(bark + gap + bark2)
	_sounds.woof = _wav(_mix(_tone(0.45, 420, 160, "square", 0.45, 1.1), _noise(0.3, 0.2, 1.5, 3)))
	# items
	_sounds.pickup = _wav(_notes([76, 81, 88], 0.06, 0.2, "square", 0.25))
	_sounds.splash = _wav(_mix(_noise(0.3, 0.3, 1.2, 1), _tone(0.2, 900, 300, "sine", 0.2, 1.5)))
	_sounds.slip = _wav(_tone(0.3, 300, 900, "tri", 0.3, 0.8))
	_sounds.win = _wav(_notes([67, 72, 76, 79], 0.1, 0.35, "square", 0.3))


## A note sweeping from f0 to f1 Hz with a decaying volume.
func _tone(dur: float, f0: float, f1: float, wave: String, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += lerpf(f0, f1, k) / RATE
		out[i] = _wave(wave, phase) * vol * pow(1.0 - k, decay)
	return out


## Noise; `hold` > 1 keeps each random value for a few samples (crunchier).
func _noise(dur: float, vol: float, decay: float, hold: int) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var v := 0.0
	for i in n:
		if i % hold == 0:
			v = randf_range(-1.0, 1.0)
		out[i] = v * vol * pow(1.0 - float(i) / n, decay)
	return out


func _wobble(dur: float, f: float, depth: float, rate: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += (f + depth * sin(TAU * rate * t)) / RATE
		out[i] = sin(TAU * phase) * vol * (1.0 - float(i) / n)
	return out


## A short melody (MIDI note numbers); the last note rings longer.
func _notes(midi: Array, each: float, last: float, wave: String, vol: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in midi.size():
		var f := _hz(midi[i])
		out.append_array(_tone(last if i == midi.size() - 1 else each, f, f, wave, vol, 0.6))
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out


static func _wave(kind: String, phase: float) -> float:
	var p := phase - floorf(phase)
	match kind:
		"square":
			return 1.0 if p < 0.25 else -1.0
		"tri":
			return 4.0 * absf(p - 0.5) - 1.0
	return sin(TAU * p)


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _wav(samples: PackedFloat32Array, rate := RATE, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


# ---------------------------------------------------------------- music

## A looping 8-bar chiptune (lead, bass, hi-hat). Built a chunk per frame so
## the game never freezes while it's being made.
func _start_music() -> void:
	if not enabled:
		return
	if _music_ready:
		if not _music.playing:
			_music.play()
		return
	if _music_building:
		return
	_music_building = true
	var bpm := 140.0
	var eighth := 60.0 / bpm / 2.0
	# Am - F - C - G, twice. Lead notes are MIDI numbers, -1 = rest.
	var lead := [
		69, 72, 76, 72, 79, 76, 72, 76,
		65, 69, 72, 69, 77, 72, 69, 72,
		60, 64, 67, 72, 76, 72, 67, 64,
		67, 71, 74, 79, 74, 71, 67, -1,
	]
	var bass := [45, 41, 48, 43]
	var bars := 8
	var spb := int(eighth * MUSIC_RATE)  # samples per eighth note
	var total := spb * 8 * bars
	var out := PackedFloat32Array()
	out.resize(total)
	var lead_phase := 0.0
	var bass_phase := 0.0
	var i := 0
	while i < total:
		var chunk_end := mini(total, i + 12000)
		while i < chunk_end:
			var step := i / spb
			var in_step := float(i % spb) / spb
			var bar := (step / 8) % 4
			var note: int = lead[(step % 32)]
			var v := 0.0
			if note >= 0:
				lead_phase += _hz(note) / MUSIC_RATE
				v += _wave("square", lead_phase) * 0.12 * (1.0 - in_step * 0.7)
			bass_phase += _hz(bass[bar]) / MUSIC_RATE
			var beat_pos := float(i % (spb * 2)) / (spb * 2)
			v += _wave("tri", bass_phase) * 0.22 * (1.0 - beat_pos * 0.5)
			if step % 2 == 1 and in_step < 0.08:
				v += randf_range(-1.0, 1.0) * 0.05
			out[i] = v
			i += 1
		await get_tree().process_frame
	_music.stream = _wav(out, MUSIC_RATE, true)
	_music_ready = true
	_music_building = false
	if enabled:
		_music.play()
