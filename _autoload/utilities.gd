extends Node

var http_request: HTTPRequest
var url = "https://www.killgorack.com/PX4/api.php"
var api_params: Dictionary = {}
var function_complete: String = ""
var requestor_ready: bool = true
var game_ident: String
var game_id: int = -1
var my_color: int = 0 # 1 = white, -1 = black
var heartbeat_timer: Timer
var request_busy: bool = false
var user_key: String = ""
var Last_Message: String = ""

var chat_log: Array = []
var _pending_chat_message: String = ""
signal signal_chat_updated()

# How often the heartbeat polls the server. In-game is faster than the lobby
# since that's also what chat responsiveness rides on — tune this to taste.
const LOBBY_POLL_INTERVAL := 5.0
const IN_GAME_POLL_INTERVAL := 3.0

var requests_queue: Array = []

signal signal_add_local_to_queue()
signal signal_update_queue()
signal signal_set_match()

var board_state := [
	[ 4, 2, 3, 5, 6, 3, 2, 4 ],
	[ 1, 1, 1, 1, 1, 1, 1, 1 ],
	[ 0, 0, 0, 0, 0, 0, 0, 0 ],
	[ 0, 0, 0, 0, 0, 0, 0, 0 ],
	[ 0, 0, 0, 0, 0, 0, 0, 0 ],
	[ 0, 0, 0, 0, 0, 0, 0, 0 ],
	[ -1, -1, -1, -1, -1, -1, -1, -1 ],
	[ -4, -2, -3, -5, -6, -3, -2, -4 ],
]

var white_to_move := true
var move_history: Array = []
var game_over := false
var winner: int = 0 # 1 = white, -1 = black, 0 = draw
var in_check := false # true if the side currently to move is in check

# Castling rights: once true, that piece has moved and can never castle again.
var white_king_moved := false
var black_king_moved := false
var white_rook_a_moved := false # queenside rook, file 0
var white_rook_h_moved := false # kingside rook, file 7
var black_rook_a_moved := false
var black_rook_h_moved := false

# The square a pawn skipped over on its last two-square push; only capturable
# en passant on the very next move, then it's cleared again.
var en_passant_target: Vector2i = Vector2i(-1, -1)

# 0 = no offer pending, 1/-1 = that color has offered a draw and is waiting on a response.
var draw_offered_by: int = 0
var draw_reason: String = "Stalemate" # shown when winner == 0; overwritten to "By agreement" on an accepted offer

var app_state: String = "checking" # "checking" | "idle" | "queued" | "in_game"

signal signal_matched(data: Dictionary)
signal signal_game_state_updated(data: Dictionary)
signal signal_screenshot_saved(path: String)

const SAVE_PATH := "user://userdata.save"
var screenshot_dir: String = ""

func _ready() -> void:
	_load_or_create_user_key()
	http_request = HTTPRequest.new()
	http_request.use_threads = true
	add_child(http_request)
	http_request.connect("request_completed", Callable(self, "_on_request_completed"))
	api_params = {
		"ap": "game",
		"cn": "hme",
		"vc": Creds.apiKEY,
		"api": "json",
		"apikeyid": Creds.apiID
	}
	# --- HEARTBEAT SETUP ---
	heartbeat_timer = Timer.new()
	heartbeat_timer.wait_time = LOBBY_POLL_INTERVAL
	heartbeat_timer.autostart = true
	heartbeat_timer.one_shot = false
	add_child(heartbeat_timer)
	heartbeat_timer.timeout.connect(_on_heartbeat_timeout)

	screenshot_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("My Games/Basic Chess/Screenshots")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ScreenCapture"):
		_take_screenshot()


func _take_screenshot() -> void:
	var image: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var path := screenshot_dir.path_join("chess_%s.png" % timestamp)
	image.save_png(path)
	signal_screenshot_saved.emit(path)


# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
#  Entry points for requests.. (get in line fackers!)
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
const STARTING_BOARD := [
	[ 4, 2, 3, 5, 6, 3, 2, 4 ],
	[ 1, 1, 1, 1, 1, 1, 1, 1 ],
	[ 0, 0, 0, 0, 0, 0, 0, 0 ],
	[ 0, 0, 0, 0, 0, 0, 0, 0 ],
	[ 0, 0, 0, 0, 0, 0, 0, 0 ],
	[ 0, 0, 0, 0, 0, 0, 0, 0 ],
	[ -1, -1, -1, -1, -1, -1, -1, -1 ],
	[ -4, -2, -3, -5, -6, -3, -2, -4 ],
]

func _reset_game_state() -> void:
	board_state = STARTING_BOARD.duplicate(true)
	white_to_move = true
	move_history = []
	game_over = false
	winner = 0
	in_check = false
	white_king_moved = false
	black_king_moved = false
	white_rook_a_moved = false
	white_rook_h_moved = false
	black_rook_a_moved = false
	black_rook_h_moved = false
	en_passant_target = Vector2i(-1, -1)
	draw_offered_by = 0
	draw_reason = "Stalemate"
	game_id = -1
	my_color = 0

func get_into_queue(GName: String):
	_reset_game_state()
	requests_queue.append({
		"type": "add_to_queue",
		"data": {
			"game_name": GName
		}
	})
	requestor()

# Leaves a finished game and returns to the lobby, ready to queue up or join another.
func leave_game() -> void:
	_reset_game_state()
	app_state = "idle"
	get_queue_data()
	requestor()

# On launch we don't yet know if this user_key already belongs to an
# in-progress game, an unmatched queue entry, or neither — ask for both
# right away instead of waiting on the next heartbeat tick.
func determine_startup_state() -> void:
	check_for_match()
	get_queue_data()
	requestor()

func get_queue_data():
	for r in requests_queue:
		if r.type == "get_queue":
			return
	requests_queue.append({
		"type": "get_queue",
		"data": {}
	})

func set_match(id_to_join: int):
	requests_queue.append({
		"type": "set_matched",
		"data": {
			"id": id_to_join
		}
	})
	requestor()

func check_for_match():
	for r in requests_queue:
		if r.type == "check_for_match":
			return
	requests_queue.append({
		"type": "check_for_match",
		"data": {}
	})

func send_move():
	requests_queue.append({
		"type": "update_game_state",
		"data": {}
	})
	requestor()

# Piggybacks on the same update_game_state call moves already use — no
# separate chat endpoint, just one more optional field on a request that's
# already being sent/polled regularly.
func send_chat_message(text: String) -> void:
	if text.is_empty():
		return
	_pending_chat_message = text
	requests_queue.append({
		"type": "update_game_state",
		"data": {}
	})
	requestor()

func set_chat_log_from_json(json_string: String) -> void:
	if json_string.is_empty():
		return
	var parsed = JSON.parse_string(json_string)
	if typeof(parsed) == TYPE_ARRAY:
		chat_log = parsed
		signal_chat_updated.emit()

func record_move(from: Vector2i, to: Vector2i, piece: int, captured: int, promoted: bool) -> void:
	move_history.append({
		"from": [from.x, from.y],
		"to": [to.x, to.y],
		"piece": piece,
		"captured": captured,
		"promoted": promoted,
		"white": piece > 0
	})

func set_move_history_from_json(json_string: String) -> void:
	if json_string.is_empty():
		return
	var parsed = JSON.parse_string(json_string)
	if typeof(parsed) == TYPE_ARRAY:
		move_history = parsed
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# Switchboard for the requests queue. (fired in heartbeat)
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
func requestor():
	if request_busy:
		return
	if requests_queue.size() == 0:
		return
	var req = requests_queue.pop_front()
	request_busy = true
	match req.type:
		"get_queue":
			_send_get_queue()
		"add_to_queue":
			_send_add_to_queue(req.data['game_name'])
		"set_matched":
			_send_set_matched(req.data['id'])
		"check_for_match":
			_send_check_for_match()
		"update_game_state":
			_send_update_game_state()
		"get_game_state":
			_send_get_game_state()





func _send_add_to_queue(Name):
	function_complete = "add_to_queue"
	var post_data = {
		"function": "add_player_to_unmached_queue",
		"game_name": Name,
		"user_a_key": user_key,
		"game_state_json": _state_json(),
		"move_history_json": _move_history_json(),
		"formidentifier": "alacarte\\game\\chessAPI"
	}
	var post_data_encoded = encode_dict_string(post_data)
	var full_url = url + "?" + encode_dict_string(api_params)
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	http_request.request(full_url, headers, HTTPClient.METHOD_POST, post_data_encoded)




func _send_get_queue():
	function_complete = "update_queue"
	var post_data = {
		"function": "get_unmached_players",
		"formidentifier": "alacarte\\game\\chessAPI"
	}
	var post_data_encoded = encode_dict_string(post_data)
	var full_url = url + "?" + encode_dict_string(api_params)
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	http_request.request(full_url, headers, HTTPClient.METHOD_POST, post_data_encoded)






func _send_set_matched(id_to_join: int):
	function_complete = "set_mached_player"
	var post_data = {
		"ID": id_to_join,
		"function": "set_mached_player",
		"user_key": user_key,
		"formidentifier": "alacarte\\game\\chessAPI"
	}
	var post_data_encoded = encode_dict_string(post_data)
	var full_url = url + "?" + encode_dict_string(api_params)
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	http_request.request(full_url, headers, HTTPClient.METHOD_POST, post_data_encoded)




func _send_check_for_match():
	function_complete = "check_for_match"
	var post_data = {
		"function": "check_for_match",
		"user_a_key": user_key,
		"formidentifier": "alacarte\\game\\chessAPI"
	}
	var post_data_encoded = encode_dict_string(post_data)
	var full_url = url + "?" + encode_dict_string(api_params)
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	http_request.request(full_url, headers, HTTPClient.METHOD_POST, post_data_encoded)




func _send_update_game_state():
	function_complete = "update_game_state"
	var post_data = {
		"function": "update_game_state",
		"user_key": user_key,
		"ID": game_id,
		"game_state_json": _state_json(),
		"move_history_json": _move_history_json(),
		"formidentifier": "alacarte\\game\\chessAPI"
	}
	if not _pending_chat_message.is_empty():
		post_data["chat_message"] = _pending_chat_message
		_pending_chat_message = ""
	var post_data_encoded = encode_dict_string(post_data)
	var full_url = url + "?" + encode_dict_string(api_params)
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	http_request.request(full_url, headers, HTTPClient.METHOD_POST, post_data_encoded)




func _send_get_game_state():
	function_complete = "get_game_state"
	var post_data = {
		"function": "get_game_state",
		"user_key": user_key,
		"ID": game_id,
		"formidentifier": "alacarte\\game\\chessAPI"
	}
	var post_data_encoded = encode_dict_string(post_data)
	var full_url = url + "?" + encode_dict_string(api_params)
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	http_request.request(full_url, headers, HTTPClient.METHOD_POST, post_data_encoded)




func _on_heartbeat_timeout():
	heartbeat_timer.wait_time = IN_GAME_POLL_INTERVAL if app_state == "in_game" else LOBBY_POLL_INTERVAL
	match app_state:
		"checking":
			check_for_match()
			get_queue_data()
		"idle":
			get_queue_data()
			check_for_match()
		"queued":
			check_for_match()
		"in_game":
			get_game_state()
	requestor()





func get_game_state():
	for r in requests_queue:
		if r.type == "get_game_state":
			return
	requests_queue.append({
		"type": "get_game_state",
		"data": {}
	})





func _on_request_completed(_result, _response_code, _headers, body):
	var text: String = body.get_string_from_utf8()
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		request_busy = false
		if requests_queue.size() > 0:
			requestor()
		return
	var json_result = json.data
	if function_complete == "add_to_queue":
		Utilities.Last_Message = json_result['message']
		print(json_result['message'])
		if json_result.get('status') == "success":
			app_state = "queued"
		signal_add_local_to_queue.emit()
	if function_complete == "update_queue":
		Utilities.Last_Message = json_result['message']
		signal_update_queue.emit(json_result)
	if function_complete == "set_mached_player":
		Utilities.Last_Message = json_result['message']
		print(json_result['message'])
		signal_set_match.emit(json_result)
	if function_complete == "check_for_match":
		if json_result.get('matched') == true:
			var data: Dictionary = json_result['data']
			if int(data['ID']) != game_id:
				signal_matched.emit(data)
	if function_complete == "update_game_state":
		if json_result.get('status') != "success":
			Utilities.Last_Message = json_result.get('message', "")
	if function_complete == "get_game_state":
		if json_result.get('status') == "success":
			signal_game_state_updated.emit(json_result['data'])
	request_busy = false
	# Drain any requests queued up alongside this one (e.g. the startup
	# match-check + queue-check pair) right away instead of leaving them
	# to trickle out one per heartbeat tick.
	if requests_queue.size() > 0:
		requestor()









# HELPERS ====================================================

func _state_json() -> String:
	return JSON.stringify({
		"board": board_state,
		"white_to_move": white_to_move,
		"game_over": game_over,
		"winner": winner,
		"in_check": in_check,
		"white_king_moved": white_king_moved,
		"black_king_moved": black_king_moved,
		"white_rook_a_moved": white_rook_a_moved,
		"white_rook_h_moved": white_rook_h_moved,
		"black_rook_a_moved": black_rook_a_moved,
		"black_rook_h_moved": black_rook_h_moved,
		"en_passant_target": [en_passant_target.x, en_passant_target.y],
		"draw_offered_by": draw_offered_by,
		"draw_reason": draw_reason
	})

func _move_history_json() -> String:
	return JSON.stringify(move_history)

func encode_dict_string(data: Dictionary) -> String:
	var query_string = []
	for key in data.keys():
		var encoded_key = String(key).uri_encode()
		var encoded_value = str(data[key]).uri_encode()
		query_string.append(encoded_key + "=" + encoded_value)
	return String("&").join(query_string)

func random_string(length: int, use_special: bool = false) -> String:
	var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var specials = "!@#$%^&*()-_=+[]{}<>?/|"
	if use_special:
		chars += specials
	var result := ""
	for i in length:
		result += chars[randi() % chars.length()]
	return result

func _load_or_create_user_key() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var data = file.get_as_text()
		user_key = data.strip_edges()
		file.close()
	else:
		user_key = _generate_new_key()
		_save_user_key()

func _generate_new_key() -> String:
	return random_string(32, false)

func _save_user_key() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(user_key)
	file.close()

func reset_user_key() -> void:
	user_key = _generate_new_key()
	_save_user_key()
	
