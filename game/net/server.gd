extends Node
## The online game server. Listens for WebSocket connections, keeps track of
## who is who (a secret token per player, so a dropped connection can come
## back), creates lobbies with short codes and passes messages to them.
## Start it with:  godot --headless --path game -- --server   (PORT env var sets the port)

const Wire = preload("res://net/wire.gd")
const Lobby = preload("res://net/lobby.gd")

## No 0/O or 1/I/L so codes are easy to read out loud.
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 5
const MAX_LOBBIES := 500
const MAX_MESSAGE := 4096
const NAME_LENGTH := 12
## How many open lobbies the list shows at most.
const LIST_MAX := 8

var _tcp := TCPServer.new()
var _peers := {}  # peer id -> {"ws": WebSocketPeer, "token": String}
var _sessions := {}  # token -> {"name": String, "peer": int, "lobby": String}
var lobbies := {}  # code -> Lobby
var _next_peer := 1
var _crypto := Crypto.new()


func start(port: int) -> Error:
	var err := _tcp.listen(port)
	if err == OK:
		print("School Fighter server listening on port %d" % port)
	return err


func stop() -> void:
	for id in _peers:
		_peers[id].ws.close()
	_tcp.stop()


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = MAX_MESSAGE * 4
		ws.accept_stream(_tcp.take_connection())
		_peers[_next_peer] = {"ws": ws, "token": ""}
		_next_peer += 1

	for id in _peers.keys():
		var peer: Dictionary = _peers[id]
		var ws: WebSocketPeer = peer.ws
		ws.poll()
		while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			var text := ws.get_packet().get_string_from_utf8()
			if text.length() <= MAX_MESSAGE:
				var msg = Wire.decode(text)
				if msg is Dictionary:
					_on_message(id, msg)
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_on_closed(id)

	var now := Time.get_ticks_msec()
	for code in lobbies.keys():
		var lobby: Lobby = lobbies[code]
		lobby.tick(now)
		_flush(lobby)
		if lobby.is_empty():
			lobbies.erase(code)
			print("lobby %s closed (%d lobbies)" % [code, lobbies.size()])


func _on_message(peer_id: int, msg: Dictionary) -> void:
	var peer: Dictionary = _peers[peer_id]
	var t = msg.get("t")
	if t == "ping":
		_send_peer(peer_id, {"t": "pong"})
		return
	if t == "hello":
		_hello(peer_id, msg)
		return
	var token: String = peer.token
	if token == "":
		_send_peer(peer_id, {"t": "error", "code": "say_hello"})
		return
	var session: Dictionary = _sessions[token]
	var now := Time.get_ticks_msec()
	match t:
		"create":
			_leave(token)
			if lobbies.size() >= MAX_LOBBIES:
				_send_token(token, {"t": "error", "code": "server_full"})
				return
			var code := _new_code()
			var lobby := Lobby.new(code)
			lobbies[code] = lobby
			lobby.add_member(token, session.name, now)
			session.lobby = code
			print("lobby %s created (%d lobbies)" % [code, lobbies.size()])
			_flush(lobby)
		"join":
			var code := str(msg.get("code", "")).strip_edges().to_upper()
			if session.lobby == code and lobbies.has(code):
				lobbies[code].set_connected(token, true, now)
				_flush(lobbies[code])
				return
			if not lobbies.has(code):
				_send_token(token, {"t": "error", "code": "not_found"})
				return
			var lobby: Lobby = lobbies[code]
			var err := lobby.add_member(token, session.name, now)
			if err != "":
				_send_token(token, {"t": "error", "code": err})
				return
			_leave(token)
			session.lobby = code
			print("lobby %s: player joined (%d/4)" % [code, lobby.members.size()])
			_flush(lobby)
		"leave":
			_leave(token)
			_send_token(token, {"t": "left"})
		"list":
			# Open lobbies: just the code and how many players (no names or settings).
			var open := []
			for code in lobbies:
				var lobby: Lobby = lobbies[code]
				if lobby.is_open() and code != session.lobby and not lobby.kicked.has(token):
					open.append({"code": code, "players": lobby.members.size()})
					if open.size() >= LIST_MAX:
						break
			_send_token(token, {"t": "lobbies", "list": open})
		_:
			if lobbies.has(session.lobby):
				var lobby: Lobby = lobbies[session.lobby]
				lobby.handle(token, msg, now)
				_flush(lobby)


func _hello(peer_id: int, msg: Dictionary) -> void:
	var name := str(msg.get("name", "")).strip_edges().left(NAME_LENGTH)
	if name == "":
		name = "PLAYER"
	var token := str(msg.get("token", ""))
	if not _sessions.has(token):
		token = _crypto.generate_random_bytes(16).hex_encode()
		_sessions[token] = {"name": name, "peer": -1, "lobby": ""}
	var session: Dictionary = _sessions[token]
	# The same player connecting again replaces their old connection.
	if session.peer != -1 and session.peer != peer_id and _peers.has(session.peer):
		_peers[session.peer].token = ""
		_peers[session.peer].ws.close()
	session.peer = peer_id
	session.name = name
	_peers[peer_id].token = token
	_send_peer(peer_id, {"t": "welcome", "token": token, "name": name})
	if lobbies.has(session.lobby):
		var lobby: Lobby = lobbies[session.lobby]
		var m := lobby.member(token)
		if not m.is_empty():
			m.name = name
		lobby.set_connected(token, true, Time.get_ticks_msec())
		_flush(lobby)
	else:
		session.lobby = ""


func _on_closed(peer_id: int) -> void:
	var token: String = _peers[peer_id].token
	_peers.erase(peer_id)
	if token == "" or not _sessions.has(token):
		return
	var session: Dictionary = _sessions[token]
	if session.peer != peer_id:
		return
	session.peer = -1
	if lobbies.has(session.lobby):
		var lobby: Lobby = lobbies[session.lobby]
		lobby.set_connected(token, false, Time.get_ticks_msec())
		_flush(lobby)
	else:
		_sessions.erase(token)


func _leave(token: String) -> void:
	var session: Dictionary = _sessions[token]
	if lobbies.has(session.lobby):
		var lobby: Lobby = lobbies[session.lobby]
		lobby.remove_member(token, Time.get_ticks_msec())
		_flush(lobby)
	session.lobby = ""


func _flush(lobby: Lobby) -> void:
	for item in lobby.outbox:
		var target: String = item[0]
		if target == "*":
			for m in lobby.members:
				_send_token(m.token, item[1])
		else:
			_send_token(target, item[1])
	lobby.outbox.clear()
	# Forget players who were removed from this lobby while offline.
	for token in _sessions.keys():
		var s: Dictionary = _sessions[token]
		if s.lobby == lobby.code and lobby.member(token).is_empty():
			s.lobby = ""
			if s.peer == -1:
				_sessions.erase(token)


func _send_token(token: String, msg: Dictionary) -> void:
	if _sessions.has(token) and _sessions[token].peer != -1:
		_send_peer(_sessions[token].peer, msg)


func _send_peer(peer_id: int, msg: Dictionary) -> void:
	if _peers.has(peer_id):
		var ws: WebSocketPeer = _peers[peer_id].ws
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(Wire.encode(msg))


func _new_code() -> String:
	while true:
		var code := ""
		for i in CODE_LENGTH:
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
		if not lobbies.has(code):
			return code
	return ""
