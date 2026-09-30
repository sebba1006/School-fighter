extends Node
## Connection from the game to the online server. Remembers the player's name
## and secret token, so a dropped connection (bad wifi, phone locked for a bit)
## reconnects by itself and lands back in the same lobby or match.

signal message(msg: Dictionary)
## "offline", "connecting" or "online"
signal status_changed(status: String)

const Wire = preload("res://net/wire.gd")
const Config = preload("res://net/config.gd")
const SAVE_PATH := "user://online.cfg"
const PING_EVERY_MS := 20000

var url := Config.DEFAULT_SERVER
var player_name := ""
var token := ""
var status := "offline"
## Save name/token/server to disk (off for test clients sharing one process).
var persist := true

var _ws: WebSocketPeer = null
var _want_online := false
var _retry_at := 0
var _retry_delay := 1000
var _last_ping := 0


func _ready() -> void:
	if persist:
		var cfg := ConfigFile.new()
		if cfg.load(SAVE_PATH) == OK:
			player_name = cfg.get_value("online", "name", "")
			token = cfg.get_value("online", "token", "")
			url = cfg.get_value("online", "server", Config.DEFAULT_SERVER)


func save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("online", "name", player_name)
	cfg.set_value("online", "token", token)
	cfg.set_value("online", "server", url)
	cfg.save(SAVE_PATH)


func go_online(p_url: String, p_name: String) -> void:
	url = p_url
	player_name = p_name
	save()
	_want_online = true
	if _ws == null:
		_open()


func go_offline() -> void:
	_want_online = false
	if _ws != null:
		_ws.close()
	_ws = null
	_set_status("offline")


## Drops the connection without giving up (used by tests to simulate bad wifi).
func drop_connection() -> void:
	if _ws != null:
		_ws.close()


func send(msg: Dictionary) -> bool:
	if status != "online" or _ws == null:
		return false
	_ws.send_text(Wire.encode(msg))
	return true


func _open() -> void:
	_ws = WebSocketPeer.new()
	_set_status("connecting")
	if _ws.connect_to_url(url) != OK:
		_ws = null
		_retry_later()


func _retry_later() -> void:
	_retry_at = Time.get_ticks_msec() + _retry_delay
	_retry_delay = mini(10000, _retry_delay * 2)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _ws == null:
		if _want_online and _retry_at > 0 and now >= _retry_at:
			_retry_at = 0
			_open()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if status != "online":
				_set_status("online")
				_retry_delay = 1000
				_last_ping = now
				send({"t": "hello", "name": player_name, "token": token})
			while _ws != null and _ws.get_available_packet_count() > 0:
				var msg = Wire.decode(_ws.get_packet().get_string_from_utf8())
				if not msg is Dictionary:
					continue
				if msg.get("t") == "welcome":
					token = msg.token
					player_name = msg.name
					save()
				if msg.get("t") != "pong":
					message.emit(msg)
			if now - _last_ping > PING_EVERY_MS:
				_last_ping = now
				send({"t": "ping"})
		WebSocketPeer.STATE_CLOSED:
			_ws = null
			if _want_online:
				_set_status("connecting")
				_retry_later()
			else:
				_set_status("offline")


func _set_status(s: String) -> void:
	if s != status:
		status = s
		status_changed.emit(s)
