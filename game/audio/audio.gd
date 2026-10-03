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


func _ready() -> void:
	instance = self
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		enabled = cfg.get_value("audio", "enabled", true)
		music_choice = cfg.get_value("audio", "music", "school")
		if not MUSIC_LIST.has(music_choice):
			music_choice = "school"
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
	_sounds.whistle = _wav(_wobble(0.55, 2600, 180, 30, 0.18))  # the Gym Teacher's whistle (a fast trill)
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

## The songs. Lead and bass are MIDI notes per eighth note (-1 = rest), 8 bars.
## Boss fights switch to "boss" by themselves; the MUSIC button picks the rest.
const MUSIC_LIST := ["school", "hype", "chill", "boss"]
const MUSIC_TITLES := {"school": "SCHOOL", "hype": "HYPE", "chill": "CHILL", "boss": "BOSS"}


## One bar = 8 eighth notes. `chord` notes are repeated to fill the bar.
static func _bar(notes: Array) -> Array:
	var out := []
	for i in 8:
		out.append(notes[i % notes.size()])
	return out


static func _song(id: String) -> Dictionary:
	match id:
		"hype":
			# C - G - Am - F, bright arpeggios, kick and snare
			var lead := []
			for ch in [[60, 64, 67, 72, 76, 72, 67, 64], [67, 71, 74, 79, 83, 79, 74, 71], [69, 72, 76, 81, 84, 81, 76, 72], [65, 69, 72, 77, 81, 77, 72, 69]]:
				lead.append_array(ch)
			lead.append_array([72, -1, 76, 79, 84, 79, 76, 72, 74, -1, 79, 83, 86, 83, 79, 74, 76, -1, 81, 84, 88, 84, 81, 76, 77, 76, 74, 72, 69, 67, 65, -1])
			var bass := []
			for r in [36, 43, 45, 41, 36, 43, 45, 41]:
				bass.append_array(_bar([r, r, r + 12, r]))
			return {"bpm": 160.0, "lead": lead, "lead_wave": "square", "lead_vol": 0.10, "bass": bass, "bass_vol": 0.20, "kick": true, "snare": true, "hat": 0.04}
		"chill":
			# Fmaj7 - Em7 - Dm7 - Cmaj7, soft and slow
			var lead := []
			for ch in [[77, -1, 76, -1, 72, -1, 69, -1], [76, -1, 74, -1, 71, -1, 67, -1], [74, -1, 72, -1, 69, -1, 65, -1], [72, -1, 71, -1, 67, -1, 64, -1]]:
				lead.append_array(ch)
			lead.append_array([69, -1, -1, 72, -1, 76, -1, -1, 67, -1, -1, 71, -1, 74, -1, -1, 65, -1, -1, 69, -1, 72, -1, -1, 64, -1, 67, -1, 72, -1, -1, -1])
			var bass := []
			for r in [41, 40, 38, 36, 41, 40, 38, 36]:
				bass.append_array(_bar([r, -1, r, -1, r + 7, -1, r, -1]))
			return {"bpm": 96.0, "lead": lead, "lead_wave": "tri", "lead_vol": 0.16, "bass": bass, "bass_vol": 0.18, "kick": false, "snare": false, "hat": 0.02}
		"boss":
			# E minor, fast and heavy: Em Em C D | Em Em C B
			var lead := [
				64, 67, 71, 67, 76, 74, 71, 67,
				64, 67, 71, 74, 76, 79, 76, 74,
				72, 71, 67, 64, 72, 74, 76, 72,
				74, 72, 69, 66, 74, 76, 78, 74,
				76, -1, 76, 74, 76, 79, 76, 74,
				71, -1, 71, 69, 71, 74, 71, 69,
				67, 72, 76, 79, 76, 72, 67, 72,
				71, 75, 78, 83, 78, 75, 71, -1,
			]
			var bass := []
			for r in [40, 40, 36, 38, 40, 40, 36, 35]:
				bass.append_array(_bar([r, r + 12]))  # pumping octaves
			return {"bpm": 180.0, "lead": lead, "lead_wave": "square", "lead_vol": 0.11, "bass": bass, "bass_wave": "square", "bass_vol": 0.10, "kick": true, "snare": true, "hat": 0.05}
	# "school": the original theme, Am - F - C - G
	var lead := [
		69, 72, 76, 72, 79, 76, 72, 76,
		65, 69, 72, 69, 77, 72, 69, 72,
		60, 64, 67, 72, 76, 72, 67, 64,
		67, 71, 74, 79, 74, 71, 67, -1,
	]
	lead.append_array(lead.duplicate())
	var bass := []
	for r in [45, 41, 48, 43, 45, 41, 48, 43]:
		bass.append_array(_bar([r]))
	return {"bpm": 140.0, "lead": lead, "lead_wave": "square", "lead_vol": 0.12, "bass": bass, "bass_vol": 0.22, "kick": false, "snare": false, "hat": 0.05}


var music_choice := "school"
var _music_override := ""  # "boss" during boss fights
var _songs := {}  # id -> AudioStreamWAV, built once
var _building := {}  # id -> true while being built


static func music_name() -> String:
	return MUSIC_TITLES.get(instance._current_song() if instance != null else "school", "SCHOOL")


## The MUSIC button: next song in the list (and it's remembered).
static func next_music() -> void:
	if instance == null:
		return
	var i := MUSIC_LIST.find(instance._current_song())
	instance.music_choice = MUSIC_LIST[(i + 1) % MUSIC_LIST.size()]
	instance._music_override = ""  # picking a song by hand wins over the boss theme
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music", instance.music_choice)
	cfg.save(SETTINGS_PATH)
	instance._start_music()


## Boss fights play the boss theme while they last.
static func set_boss_music(on: bool) -> void:
	if instance == null:
		return
	instance._music_override = "boss" if on else ""
	instance._start_music()


func _current_song() -> String:
	return _music_override if _music_override != "" else music_choice


## Plays the current song, building it first if needed (a chunk per frame so
## the game never freezes while it's being made).
func _start_music() -> void:
	if not enabled:
		return
	var id := _current_song()
	if _songs.has(id):
		if _music.stream != _songs[id]:
			_music.stream = _songs[id]
			_music.play()
		elif not _music.playing:
			_music.play()
		return
	if _building.has(id):
		return
	_building[id] = true
	var song := _song(id)
	var eighth: float = 60.0 / song.bpm / 2.0
	var spb := int(eighth * MUSIC_RATE)  # samples per eighth note
	var steps: int = song.lead.size()
	var total := spb * steps
	var out := PackedFloat32Array()
	out.resize(total)
	var lead_phase := 0.0
	var bass_phase := 0.0
	var kick_phase := 0.0
	var i := 0
	while i < total:
		var chunk_end := mini(total, i + 12000)
		while i < chunk_end:
			var step := i / spb
			var in_step := float(i % spb) / spb
			var v := 0.0
			var note: int = song.lead[step]
			if note >= 0:
				lead_phase += _hz(note) / MUSIC_RATE
				v += _wave(song.lead_wave, lead_phase) * song.lead_vol * (1.0 - in_step * 0.7)
			var b: int = song.bass[step % song.bass.size()]
			if b >= 0:
				bass_phase += _hz(b) / MUSIC_RATE
				v += _wave(song.get("bass_wave", "tri"), bass_phase) * song.bass_vol * (1.0 - in_step * 0.5)
			var beat_t := float(i % (spb * 2)) / MUSIC_RATE  # seconds since the beat
			if song.kick and beat_t < 0.09:
				kick_phase += lerpf(120.0, 45.0, beat_t / 0.09) / MUSIC_RATE
				v += sin(TAU * kick_phase) * 0.35 * (1.0 - beat_t / 0.09)
			if song.snare and step % 4 == 2 and in_step < 0.35:
				v += randf_range(-1.0, 1.0) * 0.13 * (1.0 - in_step / 0.35)
			if step % 2 == 1 and in_step < 0.08:
				v += randf_range(-1.0, 1.0) * song.hat
			out[i] = v
			i += 1
		await get_tree().process_frame
	_songs[id] = _wav(out, MUSIC_RATE, true)
	_building.erase(id)
	if enabled and _current_song() == id:
		_music.stream = _songs[id]
		_music.play()
