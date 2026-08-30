extends Node3D

const PIECE_DATA := {
	"PAWN": {
		model = preload("res://Objects/Pieces/pawn.tscn"),
		black = preload("res://Materials/black_pawn.tres"),
		white = preload("res://Materials/white_pawn.tres")
	},
	"KNIGHT": {
		model = preload("res://Objects/Pieces/knight.tscn"),
		black = preload("res://Materials/black_knight.tres"),
		white = preload("res://Materials/piece_white.tres") # placeholder
	},
	"BISHOP": {
		model = preload("res://Objects/Pieces/bishop.tscn"),
		black = preload("res://Materials/black_bishop.tres"),
		white = preload("res://Materials/white_bishop.tres")
	},
	"ROOK": {
		model = preload("res://Objects/Pieces/rook.tscn"),
		black = preload("res://Materials/black_rook.tres"),
		white = preload("res://Materials/piece_white.tres") # placeholder
	},
	"QUEEN": {
		model = preload("res://Objects/Pieces/queen.tscn"),
		black = preload("res://Materials/black_queen.tres"),
		white = preload("res://Materials/piece_white.tres") # placeholder
	},
	"KING": {
		model = preload("res://Objects/Pieces/king.tscn"),
		black = preload("res://Materials/black_king.tres"),
		white = preload("res://Materials/piece_white.tres") # placeholder
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

@onready var btn_toQueue = $UI/HBoxContainer/btn_Queue
@onready var txt_Name = $UI/HBoxContainer/txt_Name
@onready var lbl_status = $UI/Status_Back/lbl_Status
@onready var lbl_opponent_status: Label = $UI/lbl_OpponentStatus
@onready var tree_game_queue = $UI/tree_queue
@onready var camera: Camera3D = $CameraRig/Camera3D

@onready var promotion_picker: Control = $UI/PromotionPicker
@onready var promotion_buttons: Dictionary = {
	5: $UI/PromotionPicker/Center/Panel/VBoxContainer/HBoxContainer/btn_Queen,
	4: $UI/PromotionPicker/Center/Panel/VBoxContainer/HBoxContainer/btn_Rook,
	3: $UI/PromotionPicker/Center/Panel/VBoxContainer/HBoxContainer/btn_Bishop,
	2: $UI/PromotionPicker/Center/Panel/VBoxContainer/HBoxContainer/btn_Knight,
}

@onready var btn_offer_draw: Button = $UI/MarginContainer/DrawControls/btn_OfferDraw
@onready var btn_accept_draw: Button = $UI/MarginContainer/DrawControls/btn_AcceptDraw
@onready var btn_decline_draw: Button = $UI/MarginContainer/DrawControls/btn_DeclineDraw
@onready var btn_new_game: Button = $UI/MarginContainer/DrawControls/btn_NewGame
@onready var help_panel: Control = $UI/HelpPanel

const CURSOR_SCENE := preload("res://Objects/cursor.tscn")

var selected_square: Vector2i = Vector2i(-1, -1)
var legal_targets: Array[Vector2i] = []
var highlight_nodes: Array[Node3D] = []

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
	tree_game_queue.item_activated.connect(_on_row_double_clicked)
	for piece_type: int in promotion_buttons:
		promotion_buttons[piece_type].pressed.connect(_on_promotion_button_pressed.bind(piece_type))
	btn_offer_draw.pressed.connect(_offer_draw)
	btn_accept_draw.pressed.connect(_accept_draw)
	btn_decline_draw.pressed.connect(_decline_draw)
	btn_new_game.pressed.connect(_on_new_game_pressed)

	# We don't yet know if this user is mid-game, already queued, or neither —
	# hide the queue UI and ask the server before showing anything that might
	# have to be immediately swapped out.
	btn_toQueue.visible = false
	txt_Name.visible = false
	tree_game_queue.visible = false
	lbl_status.text = "Checking game status, please wait..."
	Utilities.determine_startup_state()





func _on_screenshot_saved(path: String) -> void:
	lbl_status.text = "Screenshot saved: %s" % path
	await get_tree().create_timer(2.0).timeout
	if Utilities.app_state == "in_game":
		_update_turn_status()
	else:
		lbl_status.text = Utilities.Last_Message


func _on_row_double_clicked() -> void:
	var item: TreeItem = tree_game_queue.get_selected()
	if item:
		var game_id = item.get_metadata(0)
		Utilities.set_match(game_id)
	lbl_status.text = Utilities.Last_Message





func _on_user_added_to_queue():
	btn_toQueue.visible = false
	txt_Name.visible = false
	lbl_status.text = Utilities.Last_Message





func _on_update_queue(data):
	tree_game_queue.clear()
	tree_game_queue.set_column_title(0, "Name")
	tree_game_queue.set_column_title(1, "ID")
	var root = tree_game_queue.create_item()
	var my_queue_entry: Dictionary = {}
	for game in data["data"]:
		var item = tree_game_queue.create_item(root)
		item.set_text(0, str(game.game_name))
		item.set_text(1, str(int(game.ID)))
		item.set_metadata(0, int(game.ID))
		if str(game.get("user_a_key", "")) == Utilities.user_key:
			my_queue_entry = game
	if Utilities.app_state == "checking":
		_resolve_startup_state(my_queue_entry)
	#lbl_status.text = Utilities.Last_Message


# Called once the startup queue-check has come back. If check_for_match also
# lands a match, _on_matched/_enter_game will override this immediately after.
func _resolve_startup_state(my_queue_entry: Dictionary) -> void:
	if not my_queue_entry.is_empty():
		Utilities.app_state = "queued"
		btn_toQueue.visible = false
		txt_Name.visible = false
		tree_game_queue.visible = true
		lbl_status.text = "You're already queued as \"%s\" — waiting for an opponent..." % str(my_queue_entry.game_name)
	else:
		Utilities.app_state = "idle"
		btn_toQueue.visible = true
		txt_Name.visible = true
		tree_game_queue.visible = true
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
	btn_toQueue.visible = false
	txt_Name.visible = false
	tree_game_queue.visible = false
	load_board(Utilities.board_state)
	_update_turn_status()


func _on_game_state_updated(data: Dictionary) -> void:
	var previous_turn := Utilities.white_to_move
	_apply_state_json(data.get('game_state_json', ""))
	Utilities.set_move_history_from_json(data.get('move_history_json', ""))
	var secs_val = data.get('opponent_seconds_since_seen')
	_opponent_seconds_since_seen = int(secs_val) if secs_val != null else -1
	if Utilities.white_to_move != previous_turn:
		load_board(Utilities.board_state)
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
	btn_toQueue.visible = true
	txt_Name.visible = true
	tree_game_queue.visible = true
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
	for rank: int in range(8):
		for file: int in range(8):
			var code: int = state[rank][file]
			if code == 0:
				continue
			var piece := spawn_piece(code, rank, file)
			$Pieces.add_child(piece)





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


func _is_my_turn() -> bool:
	return (Utilities.white_to_move and Utilities.my_color == 1) \
		or (not Utilities.white_to_move and Utilities.my_color == -1)


func _raycast_to_square(screen_pos: Vector2) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 2000.0)
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

	Utilities.en_passant_target = Vector2i((from.x + to.x) / 2, from.y) \
		if type == 1 and abs(to.x - from.x) == 2 else Vector2i(-1, -1)

	Utilities.white_to_move = not Utilities.white_to_move

	_refresh_game_status()

	load_board(Utilities.board_state)
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
