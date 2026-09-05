extends Node3D

const PIECE_DATA := {
	"PAWN": {
		model = preload("res://Objects/Pieces/pawn.tscn"),
		black = preload("res://Materials/piece_black_shader.tres"),
		white = preload("res://Materials/piece_white_shader.tres")
	},
	"KNIGHT": {
		model = preload("res://Objects/Pieces/knight.tscn"),
		black = preload("res://Materials/piece_black_shader.tres"),
		white = preload("res://Materials/piece_white_shader.tres")
	},
	"BISHOP": {
		model = preload("res://Objects/Pieces/bishop.tscn"),
		black = preload("res://Materials/piece_black_shader.tres"),
		white = preload("res://Materials/piece_white_shader.tres")
	},
	"ROOK": {
		model = preload("res://Objects/Pieces/rook.tscn"),
		black = preload("res://Materials/piece_black_shader.tres"),
		white = preload("res://Materials/piece_white_shader.tres")
	},
	"QUEEN": {
		model = preload("res://Objects/Pieces/queen.tscn"),
		black = preload("res://Materials/piece_black_shader.tres"),
		white = preload("res://Materials/piece_white_shader.tres")
	},
	"KING": {
		model = preload("res://Objects/Pieces/king.tscn"),
		black = preload("res://Materials/piece_black_shader.tres"),
		white = preload("res://Materials/piece_white_shader.tres")
	}
}

const TYPE_TO_NAME := {
	1: "PAWN",
	2: "KNIGHT",
	3: "BISHOP",
	4: "ROOK",
	5: "QUEEN",
	6: "KING"
}

const PROMOTION_ICONS := {
	1: {
		5: preload("res://UserInterface/icons/white_queen.png"),
		4: preload("res://UserInterface/icons/white_rook.png"),
		3: preload("res://UserInterface/icons/white_bishop.png"),
		2: preload("res://UserInterface/icons/white_knight.png"),
	},
	-1: {
		5: preload("res://UserInterface/icons/black_queen.png"),
		4: preload("res://UserInterface/icons/black_rook.png"),
		3: preload("res://UserInterface/icons/black_bishop.png"),
		2: preload("res://UserInterface/icons/black_knight.png"),
	}
}

const SQUARE_SIZE: float = 0.57

const HOP_DURATION := 0.5
const HOP_HEIGHT := 1.0
const SLIDE_SPEED := 2.2 # world units/sec; distance-scaled so long slides don't look instant
const SLIDE_MIN_DURATION := 0.18
const SLIDE_MAX_DURATION := 0.55
const CAPTURE_SETTLE_TIME := 1.0
const FADE_DURATION := 0.6

@onready var join_create_panel: Control = $UI/JoinCreate
@onready var enter_queue_panel: Control = $UI/JoinCreate/margin/HBoxContainer/EnterQueue
@onready var join_queue_panel: Control = $UI/JoinCreate/margin/HBoxContainer/JoinQueue
@onready var txt_Name = $UI/JoinCreate/margin/HBoxContainer/EnterQueue/txt_Name
@onready var lbl_status = $UI/lbl_Status
@onready var lbl_opponent_status: Label = $UI/lbl_OpponentStatus
@onready var tree_game_queue = $UI/JoinCreate/margin/HBoxContainer/JoinQueue/tree_queue
@onready var btn_join_game: TextureButton = $UI/JoinCreate/margin/HBoxContainer/JoinQueue/btn_Queue
@onready var camera: Camera3D = $CameraRig/Camera3D

@onready var promotion_picker: Control = $UI/PromotionPicker
@onready var promotion_buttons: Dictionary = {
	5: $UI/PromotionPicker/Center/Panel/VBoxContainer/HBoxContainer/btn_Queen,
	4: $UI/PromotionPicker/Center/Panel/VBoxContainer/HBoxContainer/btn_Rook,
	3: $UI/PromotionPicker/Center/Panel/VBoxContainer/HBoxContainer/btn_Bishop,
	2: $UI/PromotionPicker/Center/Panel/VBoxContainer/HBoxContainer/btn_Knight,
}

@onready var chat_log: RichTextLabel = $UI/ChatPanel/ChatLog
@onready var chat_input: LineEdit = $UI/ChatPanel/ChatInput

@onready var btn_offer_draw: TextureButton = $UI/MarginContainer/DrawControls/btn_OfferDraw
@onready var btn_accept_draw: TextureButton = $UI/MarginContainer/DrawControls/btn_AcceptDraw
@onready var btn_decline_draw: TextureButton = $UI/MarginContainer/DrawControls/btn_DeclineDraw
@onready var btn_new_game: TextureButton = $UI/MarginContainer/DrawControls/btn_NewGame
@onready var help_panel: Control = $UI/HelpPanel

const CURSOR_SCENE := preload("res://Objects/cursor.tscn")

var selected_square: Vector2i = Vector2i(-1, -1)
var legal_targets: Array[Vector2i] = []
var highlight_nodes: Array[Node3D] = []

# Mirrors board_state with the live piece node currently sitting on each
# square (or null), so a move can animate the existing node instead of
# rebuilding the whole board.
var piece_nodes: Array = []

var promotion_pending: bool = false
signal promotion_chosen(piece_type: int)

# Purely presentational — how long since the opponent last polled/moved.
# -1 means no reading yet (e.g. the first few seconds after entering a game).
var _opponent_seconds_since_seen: int = -1

func _ready() -> void:
	load_board(Utilities.board_state)
	Utilities.signal_add_local_to_queue.connect(_on_user_added_to_queue)
	Utilities.signal_update_queue.connect(_on_update_queue)
	Utilities.signal_set_match.connect(_on_set_match)
	Utilities.signal_matched.connect(_on_matched)
	Utilities.signal_game_state_updated.connect(_on_game_state_updated)
	Utilities.signal_screenshot_saved.connect(_on_screenshot_saved)
	Utilities.signal_chat_updated.connect(_on_chat_log_updated)
	chat_input.text_submitted.connect(_on_chat_submitted)
	btn_join_game.pressed.connect(_join_selected_game)
	for piece_type: int in promotion_buttons:
		promotion_buttons[piece_type].pressed.connect(_on_promotion_button_pressed.bind(piece_type))
	btn_offer_draw.pressed.connect(_offer_draw)
	btn_accept_draw.pressed.connect(_accept_draw)
	btn_decline_draw.pressed.connect(_decline_draw)
	btn_new_game.pressed.connect(_on_new_game_pressed)

	# We don't yet know if this user is mid-game, already queued, or neither —
	# hide the queue UI and ask the server before showing anything that might
	# have to be immediately swapped out.
	join_create_panel.visible = false
	lbl_status.text = "Checking game status, please wait..."
	Utilities.determine_startup_state()





func _on_screenshot_saved(path: String) -> void:
	lbl_status.text = "Screenshot saved: %s" % path
	await get_tree().create_timer(2.0).timeout
	if Utilities.app_state == "in_game":
		_update_turn_status()
	else:
		lbl_status.text = Utilities.Last_Message


func _join_selected_game() -> void:
	var item: TreeItem = tree_game_queue.get_selected()
	if not item:
		return
	var game_id = item.get_metadata(0)
	Utilities.set_match(game_id)
	lbl_status.text = Utilities.Last_Message





func _on_user_added_to_queue():
	enter_queue_panel.visible = false
	lbl_status.text = Utilities.Last_Message





func _on_update_queue(data):
	tree_game_queue.clear()
	var root = tree_game_queue.create_item()
	var my_queue_entry: Dictionary = {}
	for game in data["data"]:
		var item = tree_game_queue.create_item(root)
		item.set_text(0, str(game.game_name))
		item.set_metadata(0, int(game.ID))
		if str(game.get("user_a_key", "")) == Utilities.user_key:
			my_queue_entry = game
	if Utilities.app_state == "checking":
		_resolve_startup_state(my_queue_entry)
	#lbl_status.text = Utilities.Last_Message


# Called once the startup queue-check has come back. If check_for_match also
# lands a match, _on_matched/_enter_game will override this immediately after.
func _resolve_startup_state(my_queue_entry: Dictionary) -> void:
	join_create_panel.visible = true
	join_queue_panel.visible = true
	if not my_queue_entry.is_empty():
		Utilities.app_state = "queued"
		enter_queue_panel.visible = false
		lbl_status.text = "You're already queued as \"%s\" — waiting for an opponent..." % str(my_queue_entry.game_name)
	else:
		Utilities.app_state = "idle"
		enter_queue_panel.visible = true
		lbl_status.text = "Enter a name and queue up for a new game!"




func _on_set_match(data: Dictionary) -> void:
	if data.get('status') != "success" or not data.has('data'):
		lbl_status.text = Utilities.Last_Message
		return
	_enter_game(data['data'], -1) # joiner is always black


func _on_matched(data: Dictionary) -> void:
	# Fires both for "someone just joined my queued game" and for either
	# player reconnecting mid-game, so the color has to come from the row.
	var color: int = 1 if data.get('user_a_key') == Utilities.user_key else -1
	_enter_game(data, color)


func _enter_game(row: Dictionary, color: int) -> void:
	Utilities.game_id = int(row['ID'])
	Utilities.my_color = color
	Utilities.app_state = "in_game"
	_opponent_seconds_since_seen = -1
	_apply_state_json(row.get('game_state_json', ""))
	Utilities.set_move_history_from_json(row.get('move_history_json', ""))
	join_create_panel.visible = false
	load_board(Utilities.board_state)
	_update_turn_status()


func _on_game_state_updated(data: Dictionary) -> void:
	# A response can arrive after we've already applied a local move (its
	# request was still queued behind an earlier, slower one). Anything
	# reporting fewer moves than we already have locally predates that move —
	# applying it would revert the board and then re-push the reverted state
	# to the server as truth. Discard it instead of trusting it blindly.
	var incoming_history = JSON.parse_string(data.get('move_history_json', ""))
	if typeof(incoming_history) == TYPE_ARRAY and incoming_history.size() < Utilities.move_history.size():
		return
	var old_board: Array = Utilities.board_state.duplicate(true)
	_apply_state_json(data.get('game_state_json', ""))
	Utilities.set_move_history_from_json(data.get('move_history_json', ""))
	Utilities.set_chat_log_from_json(data.get('chat_log_json', ""))
	var secs_val = data.get('opponent_seconds_since_seen')
	_opponent_seconds_since_seen = int(secs_val) if secs_val != null else -1
	if Utilities.board_state != old_board:
		_apply_remote_update(old_board, Utilities.board_state)
		_clear_selection()
	_update_turn_status()


func _update_turn_status() -> void:
	_update_draw_ui()
	if Utilities.app_state != "in_game":
		lbl_opponent_status.text = ""
		return
	if Utilities.game_over:
		lbl_opponent_status.text = ""
		if Utilities.winner == 0:
			lbl_status.text = "%s — Draw." % Utilities.draw_reason
		else:
			var winner_name := "White" if Utilities.winner == 1 else "Black"
			var outcome := "You win!" if Utilities.winner == Utilities.my_color else "You lose."
			lbl_status.text = "Checkmate — %s wins! %s" % [winner_name, outcome]
		return
	var color_name := "White" if Utilities.my_color == 1 else "Black"
	var turn_text := "Your turn" if _is_my_turn() else "Waiting on your opponent..."
	if Utilities.in_check and _is_my_turn():
		turn_text += " — Check!"
	if Utilities.draw_offered_by == Utilities.my_color:
		turn_text += " (draw offered, waiting on your opponent)"
	elif Utilities.draw_offered_by == -Utilities.my_color:
		turn_text = "Your opponent has offered a draw"
	lbl_status.text = "You are %s — %s" % [color_name, turn_text]
	lbl_opponent_status.text = "Opponent %s" % _format_time_ago(_opponent_seconds_since_seen) if _opponent_seconds_since_seen >= 0 else ""


# Formats a seconds count as a relative "time ago" string, forum-post style.
func _format_time_ago(seconds: int) -> String:
	if seconds < 30:
		return "active now"
	if seconds < 60:
		return "%d seconds ago" % seconds
	var minutes := seconds / 60
	if minutes < 60:
		return "%d minute%s ago" % [minutes, "" if minutes == 1 else "s"]
	var hours := minutes / 60
	if hours < 24:
		return "%d hour%s ago" % [hours, "" if hours == 1 else "s"]
	var days := hours / 24
	if days < 7:
		return "%d day%s ago" % [days, "" if days == 1 else "s"]
	var weeks := days / 7
	if weeks < 5:
		return "%d week%s ago" % [weeks, "" if weeks == 1 else "s"]
	var months := days / 30
	return "%d month%s ago" % [months, "" if months == 1 else "s"]


# Shows/hides the draw-offer/respond/new-game buttons for the current state.
func _update_draw_ui() -> void:
	if Utilities.app_state != "in_game":
		btn_offer_draw.visible = false
		btn_accept_draw.visible = false
		btn_decline_draw.visible = false
		btn_new_game.visible = false
		return
	if Utilities.game_over:
		btn_offer_draw.visible = false
		btn_accept_draw.visible = false
		btn_decline_draw.visible = false
		btn_new_game.visible = true
		return
	btn_new_game.visible = false
	var offer_pending_for_me: bool = Utilities.draw_offered_by == -Utilities.my_color
	btn_accept_draw.visible = offer_pending_for_me
	btn_decline_draw.visible = offer_pending_for_me
	btn_offer_draw.visible = not offer_pending_for_me and Utilities.draw_offered_by == 0 \
		and _is_my_turn() and not Utilities.in_check


func _offer_draw() -> void:
	if not _is_my_turn() or Utilities.game_over or Utilities.draw_offered_by != 0 or Utilities.in_check:
		return
	Utilities.draw_offered_by = Utilities.my_color
	Utilities.white_to_move = not Utilities.white_to_move
	# No piece moved, so the position is unchanged; since I could only offer
	# while not in check, my opponent can't be in check in this position either.
	Utilities.in_check = false
	_clear_selection()
	_update_turn_status()
	Utilities.send_move()


func _accept_draw() -> void:
	if Utilities.draw_offered_by != -Utilities.my_color or Utilities.game_over:
		return
	Utilities.game_over = true
	Utilities.winner = 0
	Utilities.draw_reason = "By agreement"
	Utilities.draw_offered_by = 0
	_update_turn_status()
	Utilities.send_move()


func _decline_draw() -> void:
	if Utilities.draw_offered_by != -Utilities.my_color or Utilities.game_over:
		return
	Utilities.draw_offered_by = 0
	_update_turn_status()
	Utilities.send_move()


func _on_new_game_pressed() -> void:
	if not Utilities.game_over:
		return
	Utilities.leave_game()
	_opponent_seconds_since_seen = -1
	_clear_selection()
	load_board(Utilities.board_state)
	join_create_panel.visible = true
	enter_queue_panel.visible = true
	join_queue_panel.visible = true
	_update_turn_status() # hides the draw/new-game buttons now that app_state is back to "idle"
	lbl_status.text = "Enter a name and queue up for a new game!"


func _apply_state_json(json_string: String) -> void:
	if json_string.is_empty():
		return
	var parsed = JSON.parse_string(json_string)
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("board"):
		Utilities.board_state = parsed["board"]
		Utilities.white_to_move = parsed.get("white_to_move", true)
		Utilities.game_over = parsed.get("game_over", false)
		Utilities.winner = parsed.get("winner", 0)
		Utilities.in_check = parsed.get("in_check", false)
		Utilities.white_king_moved = parsed.get("white_king_moved", false)
		Utilities.black_king_moved = parsed.get("black_king_moved", false)
		Utilities.white_rook_a_moved = parsed.get("white_rook_a_moved", false)
		Utilities.white_rook_h_moved = parsed.get("white_rook_h_moved", false)
		Utilities.black_rook_a_moved = parsed.get("black_rook_a_moved", false)
		Utilities.black_rook_h_moved = parsed.get("black_rook_h_moved", false)
		var ep: Array = parsed.get("en_passant_target", [-1, -1])
		Utilities.en_passant_target = Vector2i(int(ep[0]), int(ep[1]))
		Utilities.draw_offered_by = parsed.get("draw_offered_by", 0)
		Utilities.draw_reason = parsed.get("draw_reason", "Stalemate")



func into_queue():
	Utilities.get_into_queue(txt_Name.text)


func exit_game() -> void:
	get_tree().quit()





func load_board(state: Array) -> void:
	for child: Node in $Pieces.get_children():
		child.queue_free()
	piece_nodes = []
	for rank: int in range(8):
		piece_nodes.append([null, null, null, null, null, null, null, null])
	for rank: int in range(8):
		for file: int in range(8):
			var code: int = state[rank][file]
			if code == 0:
				continue
			var piece := spawn_piece(code, rank, file)
			$Pieces.add_child(piece)
			piece_nodes[rank][file] = piece





func spawn_piece(code: int, rank: int, file: int) -> Node3D:
	var type: int = abs(code)
	var is_white: bool = code > 0
	var piece_name: String = TYPE_TO_NAME[type]
	var data: Dictionary = PIECE_DATA[piece_name]
	var piece: Node3D = data.model.instantiate()
	piece.assign_piece(type, 1 if is_white else -1)
	if not is_white:
		piece.rotate_y(PI)
	apply_piece_material(piece, data, is_white)
	_isolate_materials(piece)
	piece.transform.origin = board_to_world(rank, file)
	return piece





func apply_piece_material(piece: Node3D, data: Dictionary, is_white: bool) -> void:
	var mesh: MeshInstance3D = get_mesh(piece)
	if mesh == null or mesh.mesh == null:
		return
	var material: Material = data.white if is_white else data.black
	for i in mesh.mesh.get_surface_count():
		mesh.set_surface_override_material(i, material)





func board_to_world(rank: int, file: int) -> Vector3:
	return Vector3(
		(file - 3.5) * SQUARE_SIZE,
		0.0,
		(rank - 3.5) * SQUARE_SIZE
	)





func get_mesh(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
		var found := get_mesh(child)
		if found:
			return found
	return null


func get_all_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		result.append_array(get_all_meshes(child))
	return result


# The piece/felt materials are shared .tres resources reused across every
# piece of that type and color. Duplicate them per-instance so fading out a
# captured piece can't fade every other piece sharing that material.
func _isolate_materials(piece: Node3D) -> void:
	for mesh: MeshInstance3D in get_all_meshes(piece):
		if mesh.material_override:
			mesh.material_override = mesh.material_override.duplicate()
		if mesh.mesh:
			for i in mesh.mesh.get_surface_count():
				var mat := mesh.get_surface_override_material(i)
				if mat:
					mesh.set_surface_override_material(i, mat.duplicate())




# MOVEMENT / CAPTURE ANIMATION =================================

# Diffs two board states and animates exactly the squares that changed —
# used for both the local player's move and an incoming opponent move, so
# hopping/capture behaves identically regardless of who moved.
func _apply_remote_update(old_state: Array, new_state: Array) -> void:
	var vacated: Array[Vector2i] = []
	var filled: Array[Vector2i] = []
	for rank in range(8):
		for file in range(8):
			if old_state[rank][file] == new_state[rank][file]:
				continue
			if new_state[rank][file] == 0:
				vacated.append(Vector2i(rank, file))
			else:
				filled.append(Vector2i(rank, file))

	# More than a single ply's worth of squares changed (e.g. reconnecting
	# after missing moves) — too ambiguous to animate meaningfully, just snap.
	if vacated.size() + filled.size() == 0 or vacated.size() + filled.size() > 4:
		load_board(new_state)
		return

	for dest in filled:
		var moved_code: int = new_state[dest.x][dest.y]
		var origin_index := -1
		for i in vacated.size():
			var origin: Vector2i = vacated[i]
			if old_state[origin.x][origin.y] == moved_code:
				origin_index = i
				break
		if origin_index == -1:
			# Promotion: the arriving code differs from what left (pawn -> queen).
			for i in vacated.size():
				var origin: Vector2i = vacated[i]
				if sign(old_state[origin.x][origin.y]) == sign(moved_code) \
						and abs(old_state[origin.x][origin.y]) == 1:
					origin_index = i
					break
		if origin_index != -1:
			var origin: Vector2i = vacated[origin_index]
			vacated.remove_at(origin_index)
			_animate_piece_move(origin, dest, moved_code)

	# Any square that emptied without a matching arrival lost its piece
	# outright — an en passant capture, which doesn't land on the mover's
	# own destination square.
	for square in vacated:
		_capture_square_if_occupied(square)

	_verify_board_sync(new_state)


# Cheap self-healing check: confirms the piece actually sitting on every
# square matches the authoritative board_state we were just given. The
# matching above is a heuristic — if a reconnect ever lands more than one
# move in a single update and two same-type/color pieces are both part of
# it, it can pair the wrong "vanished" square with the wrong "appeared"
# square, wrongly treating a relocated piece as captured. board_state itself
# (used for all move legality/check logic) is never affected by that, but
# the visual board can end up showing a missing or ghost piece. This runs
# after every move, local or remote, and any mismatch triggers an instant
# full rebuild from the real state rather than leaving a lingering desync.
func _verify_board_sync(state: Array) -> void:
	for rank in range(8):
		for file in range(8):
			var expected: int = state[rank][file]
			var node: Node3D = piece_nodes[rank][file]
			var actual: int = 0
			if node != null and is_instance_valid(node):
				actual = node.piece * node.team
			if actual != expected:
				load_board(state)
				return


func _animate_piece_move(from: Vector2i, to: Vector2i, code: int) -> void:
	_capture_square_if_occupied(to)
	var node: Node3D = piece_nodes[from.x][from.y]
	piece_nodes[from.x][from.y] = null
	piece_nodes[to.x][to.y] = node
	if node == null:
		return
	var target := board_to_world(to.x, to.y)
	# Every piece but the knight only ever has a legal move when its path is
	# clear, so sliding always reads correctly for them. The knight is the one
	# piece allowed to jump over occupied squares, and its L-shaped move isn't
	# a straight line anyway, so it hops instead.
	if node.piece == 2:
		await _hop_tween(node, target)
	else:
		await _slide_tween(node, target)
	if is_instance_valid(node) and abs(code) != node.piece:
		_swap_promoted_piece(to, code)


func _hop_tween(node: Node3D, target: Vector3) -> void:
	var start: Vector3 = node.transform.origin
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_method(
		func(t: float): node.transform.origin = start.lerp(target, t) + Vector3(0, sin(t * PI) * HOP_HEIGHT, 0),
		0.0, 1.0, HOP_DURATION
	)
	await tween.finished


func _slide_tween(node: Node3D, target: Vector3) -> void:
	var start: Vector3 = node.transform.origin
	var duration := clampf(start.distance_to(target) / SLIDE_SPEED, SLIDE_MIN_DURATION, SLIDE_MAX_DURATION)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "transform:origin", target, duration)
	await tween.finished


func _swap_promoted_piece(square: Vector2i, code: int) -> void:
	var old_node: Node3D = piece_nodes[square.x][square.y]
	var new_piece := spawn_piece(code, square.x, square.y)
	$Pieces.add_child(new_piece)
	piece_nodes[square.x][square.y] = new_piece
	if old_node:
		old_node.queue_free()


func _capture_square_if_occupied(square: Vector2i) -> void:
	var occupant: Node3D = piece_nodes[square.x][square.y]
	if occupant == null:
		return
	piece_nodes[square.x][square.y] = null
	_knock_over_and_remove(occupant)


func _knock_over_and_remove(piece: Node3D) -> void:
	var push_dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if push_dir.length() < 0.01:
		push_dir = Vector3.RIGHT
	piece.knock_over(push_dir.normalized())
	await get_tree().create_timer(CAPTURE_SETTLE_TIME).timeout
	if not is_instance_valid(piece):
		return
	await _fade_out(piece)
	if is_instance_valid(piece):
		piece.queue_free()


func _fade_out(piece: Node3D) -> void:
	var meshes := get_all_meshes(piece)
	for mesh in meshes:
		if mesh.material_override is StandardMaterial3D:
			mesh.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if mesh.mesh:
			for i in mesh.mesh.get_surface_count():
				var mat := mesh.get_surface_override_material(i)
				if mat is StandardMaterial3D:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tween := create_tween()
	tween.tween_method(
		func(alpha: float): _set_piece_alpha(meshes, alpha),
		1.0, 0.0, FADE_DURATION
	)
	await tween.finished


func _set_piece_alpha(meshes: Array[MeshInstance3D], alpha: float) -> void:
	for mesh in meshes:
		if not is_instance_valid(mesh):
			continue
		if mesh.material_override is StandardMaterial3D:
			mesh.material_override.albedo_color.a = alpha
		if mesh.mesh:
			for i in mesh.mesh.get_surface_count():
				var mat := mesh.get_surface_override_material(i)
				if mat is StandardMaterial3D:
					mat.albedo_color.a = alpha




# PROMOTION PICKER ================================================

func _on_promotion_button_pressed(piece_type: int) -> void:
	promotion_chosen.emit(piece_type)


func _show_promotion_picker(team: int) -> int:
	promotion_pending = true
	for piece_type: int in promotion_buttons:
		promotion_buttons[piece_type].icon = PROMOTION_ICONS[team].get(piece_type)
	promotion_picker.visible = true
	var chosen: int = await promotion_chosen
	promotion_picker.visible = false
	promotion_pending = false
	return chosen




# INPUT / MOVE HANDLING ========================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and chat_input.visible:
		_close_chat_input()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SLASH:
		# Only reaches here if no focused Control already ate the keystroke
		# (e.g. typing "/" into txt_Name), so this is safe to treat as "open chat".
		if Utilities.app_state == "in_game" and not chat_input.visible:
			_open_chat_input()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("Halp"):
		help_panel.visible = not help_panel.visible
		return
	if Utilities.app_state != "in_game" or Utilities.game_over or promotion_pending or not _is_my_turn():
		return
	if Input.is_action_pressed("move_view"):
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var square := _raycast_to_square(event.position)
	if square == Vector2i(-1, -1):
		return
	_handle_square_click(square)


func _open_chat_input() -> void:
	chat_input.visible = true
	chat_input.text = ""
	chat_input.grab_focus()


func _close_chat_input() -> void:
	chat_input.visible = false
	chat_input.text = ""
	chat_input.release_focus()


func _on_chat_submitted(text: String) -> void:
	var message := text.strip_edges()
	if not message.is_empty():
		Utilities.send_chat_message(message)
	_close_chat_input()


func _on_chat_log_updated() -> void:
	chat_log.clear()
	for entry: Dictionary in Utilities.chat_log:
		var is_white: bool = int(entry.get("color", 0)) == 1
		var who := "White" if is_white else "Black"
		var name_color := "white" if is_white else "gray"
		chat_log.append_text("[color=%s][b]%s:[/b][/color] %s\n" % [name_color, who, str(entry.get("text", ""))])


func _is_my_turn() -> bool:
	return (Utilities.white_to_move and Utilities.my_color == 1) \
		or (not Utilities.white_to_move and Utilities.my_color == -1)


func _raycast_to_square(screen_pos: Vector2) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var space_state := get_world_3d().direct_space_state
	# Board only (layer 2) — pieces are RigidBody3D on the default layer, and
	# hitting a piece's collision mesh instead of the flat board gives a hit
	# point off the square's center, which world_to_board can round to the
	# wrong square, especially once physics has nudged a piece off-center.
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 2000.0)
	query.collision_mask = 2
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return Vector2i(-1, -1)
	return world_to_board(result.position)


func world_to_board(pos: Vector3) -> Vector2i:
	var file := int(round(pos.x / SQUARE_SIZE + 3.5))
	var rank := int(round(pos.z / SQUARE_SIZE + 3.5))
	if rank < 0 or rank > 7 or file < 0 or file > 7:
		return Vector2i(-1, -1)
	return Vector2i(rank, file)


func _handle_square_click(square: Vector2i) -> void:
	if selected_square == Vector2i(-1, -1):
		if _owns_piece_at(square.x, square.y):
			_select_square(square.x, square.y)
		return

	if square == selected_square:
		_clear_selection()
		return

	if legal_targets.has(square):
		_apply_local_move(selected_square, square)
		_clear_selection()
		return

	if _owns_piece_at(square.x, square.y):
		_select_square(square.x, square.y)
	else:
		_clear_selection()


func _owns_piece_at(rank: int, file: int) -> bool:
	var code: int = Utilities.board_state[rank][file]
	return code != 0 and sign(code) == Utilities.my_color


func _select_square(rank: int, file: int) -> void:
	_clear_highlights()
	selected_square = Vector2i(rank, file)
	legal_targets = ChessRules.get_true_legal_moves(Utilities.board_state, rank, file)
	var code: int = Utilities.board_state[rank][file]
	if abs(code) == 6:
		legal_targets.append_array(_get_castle_targets(1 if code > 0 else -1))
	elif abs(code) == 1:
		legal_targets.append_array(ChessRules.get_en_passant_targets(Utilities.board_state, rank, file, Utilities.en_passant_target))
	for target in legal_targets:
		var marker := CURSOR_SCENE.instantiate() as Node3D
		add_child(marker)
		marker.transform.origin = board_to_world(target.x, target.y)
		highlight_nodes.append(marker)


func _clear_highlights() -> void:
	for marker in highlight_nodes:
		marker.queue_free()
	highlight_nodes.clear()


func _clear_selection() -> void:
	selected_square = Vector2i(-1, -1)
	legal_targets.clear()
	_clear_highlights()


func _apply_local_move(from: Vector2i, to: Vector2i) -> void:
	var old_board: Array = Utilities.board_state.duplicate(true)
	var code: int = Utilities.board_state[from.x][from.y]
	var team: int = 1 if code > 0 else -1
	var type: int = abs(code)
	var captured: int = Utilities.board_state[to.x][to.y]
	var promoted: bool = false
	var is_castle: bool = type == 6 and abs(to.y - from.y) == 2
	var is_en_passant: bool = type == 1 and from.y != to.y and to == Utilities.en_passant_target

	if type == 1 and (to.x == 7 or to.x == 0):
		code = (await _show_promotion_picker(team)) * team
		promoted = true

	_update_castle_rights(from, type, team)

	if is_en_passant:
		captured = Utilities.board_state[from.x][to.y] # the captured pawn sits beside the mover, not on the target square

	Utilities.record_move(from, to, code, captured, promoted)

	Utilities.board_state[to.x][to.y] = code
	Utilities.board_state[from.x][from.y] = 0

	if is_en_passant:
		Utilities.board_state[from.x][to.y] = 0

	if is_castle:
		var kingside: bool = to.y == 6
		var rook_from := Vector2i(from.x, 7 if kingside else 0)
		var rook_to := Vector2i(from.x, 5 if kingside else 3)
		var rook_code: int = Utilities.board_state[rook_from.x][rook_from.y]
		Utilities.record_move(rook_from, rook_to, rook_code, 0, false)
		Utilities.board_state[rook_to.x][rook_to.y] = rook_code
		Utilities.board_state[rook_from.x][rook_from.y] = 0

	@warning_ignore("integer_division") # from.x and to.x always differ by exactly 2 here, so the sum is always even
	Utilities.en_passant_target = Vector2i((from.x + to.x) / 2, from.y) \
		if type == 1 and abs(to.x - from.x) == 2 else Vector2i(-1, -1)

	Utilities.white_to_move = not Utilities.white_to_move

	_refresh_game_status()

	_apply_remote_update(old_board, Utilities.board_state)
	_update_turn_status()
	Utilities.send_move()


# Once a king or rook leaves its home square, that side's castling right is
# gone for good, even if the piece later returns.
func _update_castle_rights(from: Vector2i, type: int, team: int) -> void:
	if type == 6:
		if team == 1:
			Utilities.white_king_moved = true
		else:
			Utilities.black_king_moved = true
	elif type == 4:
		var home_rank: int = 0 if team == 1 else 7
		if from == Vector2i(home_rank, 0):
			if team == 1:
				Utilities.white_rook_a_moved = true
			else:
				Utilities.black_rook_a_moved = true
		elif from == Vector2i(home_rank, 7):
			if team == 1:
				Utilities.white_rook_h_moved = true
			else:
				Utilities.black_rook_h_moved = true


func _get_castle_targets(team: int) -> Array[Vector2i]:
	var king_moved: bool = Utilities.white_king_moved if team == 1 else Utilities.black_king_moved
	var rook_a_moved: bool = Utilities.white_rook_a_moved if team == 1 else Utilities.black_rook_a_moved
	var rook_h_moved: bool = Utilities.white_rook_h_moved if team == 1 else Utilities.black_rook_h_moved
	return ChessRules.get_castle_targets(Utilities.board_state, team, king_moved, rook_a_moved, rook_h_moved)


# Evaluates check / checkmate / stalemate for the side about to move.
func _refresh_game_status() -> void:
	var team_to_move: int = 1 if Utilities.white_to_move else -1
	var in_check := ChessRules.is_in_check(Utilities.board_state, team_to_move)
	var has_move := ChessRules.has_any_legal_move(Utilities.board_state, team_to_move) \
		or not _get_castle_targets(team_to_move).is_empty() \
		or ChessRules.has_en_passant_move(Utilities.board_state, team_to_move, Utilities.en_passant_target)
	Utilities.in_check = in_check and has_move
	if not has_move:
		Utilities.game_over = true
		Utilities.winner = -team_to_move if in_check else 0
