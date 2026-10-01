extends RefCounted
## Player stats, saved on this device (user://stats.cfg).
## Online: your own results. Local: which fighters win battles on this device.

const PATH := "user://stats.cfg"

## Set to false by tests and tools so they don't touch the real file.
static var enabled := true


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg


static func get_value(section: String, key: String, default: Variant = 0) -> Variant:
	return _load().get_value(section, key, default)


## One finished online match for you.
static func record_online(char_id: String, won: bool, damage: int, kos: int, supers: int) -> void:
	if not enabled:
		return
	var cfg := _load()
	_add(cfg, "online", "played", 1)
	_add(cfg, "online", "wins" if won else "losses", 1)
	_add(cfg, "online", "damage", damage)
	_add(cfg, "online", "kos", kos)
	_add(cfg, "online", "supers", supers)
	_add(cfg, "online_fighters", char_id + "_played", 1)
	if won:
		_add(cfg, "online_fighters", char_id + "_wins", 1)
	cfg.save(PATH)


## One finished local match: every fighter that played, and the winners.
static func record_local(played: Array, winners: Array) -> void:
	if not enabled:
		return
	var cfg := _load()
	_add(cfg, "local", "played", 1)
	for c in played:
		_add(cfg, "local_fighters", c + "_played", 1)
	for c in winners:
		_add(cfg, "local_fighters", c + "_wins", 1)
	cfg.save(PATH)


static func reset() -> void:
	var cfg := ConfigFile.new()
	cfg.save(PATH)


static func _add(cfg: ConfigFile, section: String, key: String, amount: int) -> void:
	cfg.set_value(section, key, int(cfg.get_value(section, key, 0)) + amount)
