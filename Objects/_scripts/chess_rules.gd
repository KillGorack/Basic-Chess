class_name ChessRules
extends RefCounted

# get_legal_moves() is pseudo-legal only; get_true_legal_moves() filters for check.
# Castling and en passant depend on state outside the board array (move history),
# so the caller passes that in and merges the results in separately.
# Board encoding matches Utilities.board_state: positive = white, negative = black,
# magnitude 1..6 = pawn, knight, bishop, rook, queen, king.

const KNIGHT_OFFSETS := [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
	Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)
]

const DIAGONAL_DIRS := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const ORTHOGONAL_DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static func get_legal_moves(board: Array, rank: int, file: int) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var code: int = board[rank][file]
	if code == 0:
		return moves

	var team: int = 1 if code > 0 else -1
	var type: int = abs(code)

	match type:
		1:
			_add_pawn_moves(board, rank, file, team, moves)
		2:
			_add_offset_moves(board, rank, file, team, KNIGHT_OFFSETS, moves)
		3:
			_add_sliding_moves(board, rank, file, team, DIAGONAL_DIRS, moves)
		4:
			_add_sliding_moves(board, rank, file, team, ORTHOGONAL_DIRS, moves)
		5:
			_add_sliding_moves(board, rank, file, team, DIAGONAL_DIRS, moves)
			_add_sliding_moves(board, rank, file, team, ORTHOGONAL_DIRS, moves)
		6:
			_add_offset_moves(board, rank, file, team, DIAGONAL_DIRS + ORTHOGONAL_DIRS, moves)

	return moves


static func _in_bounds(r: int, f: int) -> bool:
	return r >= 0 and r < 8 and f >= 0 and f < 8


static func _is_enemy(board: Array, r: int, f: int, team: int) -> bool:
	var occupant: int = board[r][f]
	return occupant != 0 and sign(occupant) != team


static func _is_empty(board: Array, r: int, f: int) -> bool:
	return board[r][f] == 0


static func _add_pawn_moves(board: Array, rank: int, file: int, team: int, moves: Array[Vector2i]) -> void:
	var dir: int = 1 if team == 1 else -1
	var start_rank: int = 1 if team == 1 else 6
	var one_step: int = rank + dir

	if _in_bounds(one_step, file) and _is_empty(board, one_step, file):
		moves.append(Vector2i(one_step, file))
		var two_step: int = rank + dir * 2
		if rank == start_rank and _in_bounds(two_step, file) and _is_empty(board, two_step, file):
			moves.append(Vector2i(two_step, file))

	for df in [-1, 1]:
		var nf: int = file + df
		if _in_bounds(one_step, nf) and _is_enemy(board, one_step, nf, team):
			moves.append(Vector2i(one_step, nf))


static func _add_offset_moves(board: Array, rank: int, file: int, team: int, offsets: Array, moves: Array[Vector2i]) -> void:
	for offset in offsets:
		var nr: int = rank + offset.x
		var nf: int = file + offset.y
		if _in_bounds(nr, nf) and (_is_empty(board, nr, nf) or _is_enemy(board, nr, nf, team)):
			moves.append(Vector2i(nr, nf))


static func _add_sliding_moves(board: Array, rank: int, file: int, team: int, dirs: Array, moves: Array[Vector2i]) -> void:
	for dir in dirs:
		var nr: int = rank + dir.x
		var nf: int = file + dir.y
		while _in_bounds(nr, nf):
			if _is_empty(board, nr, nf):
				moves.append(Vector2i(nr, nf))
			elif _is_enemy(board, nr, nf, team):
				moves.append(Vector2i(nr, nf))
				break
			else:
				break
			nr += dir.x
			nf += dir.y


# CHECK / CHECKMATE DETECTION ====================================

static func find_king(board: Array, team: int) -> Vector2i:
	for r in range(8):
		for f in range(8):
			if board[r][f] == 6 * team:
				return Vector2i(r, f)
	return Vector2i(-1, -1)


static func is_square_attacked(board: Array, r: int, f: int, by_team: int) -> bool:
	for rr in range(8):
		for ff in range(8):
			var code: int = board[rr][ff]
			if code != 0 and sign(code) == by_team:
				if get_legal_moves(board, rr, ff).has(Vector2i(r, f)):
					return true
	return false


static func is_in_check(board: Array, team: int) -> bool:
	var king_pos := find_king(board, team)
	if king_pos == Vector2i(-1, -1):
		return false
	return is_square_attacked(board, king_pos.x, king_pos.y, -team)


static func _simulate_move(board: Array, from: Vector2i, to: Vector2i) -> Array:
	var sim: Array = board.duplicate(true)
	var code: int = sim[from.x][from.y]
	var team: int = 1 if code > 0 else -1
	var type: int = abs(code)
	if type == 1 and (to.x == 7 or to.x == 0):
		code = 5 * team # mirror the auto-queen promotion used when applying a real move
	sim[to.x][to.y] = code
	sim[from.x][from.y] = 0
	return sim


# Legal moves for the piece at (rank, file), excluding any that would leave its own king in check.
static func get_true_legal_moves(board: Array, rank: int, file: int) -> Array[Vector2i]:
	var code: int = board[rank][file]
	if code == 0:
		return []
	var team: int = 1 if code > 0 else -1
	var legal: Array[Vector2i] = []
	for target in get_legal_moves(board, rank, file):
		var sim_board := _simulate_move(board, Vector2i(rank, file), target)
		if not is_in_check(sim_board, team):
			legal.append(target)
	return legal


static func has_any_legal_move(board: Array, team: int) -> bool:
	for r in range(8):
		for f in range(8):
			var code: int = board[r][f]
			if code != 0 and sign(code) == team and get_true_legal_moves(board, r, f).size() > 0:
				return true
	return false


# CASTLING ========================================================
# The king/rook "has moved" flags live outside the board array (they're
# per-game state tracked by the caller), so they're passed in rather than
# derived here.
static func get_castle_targets(board: Array, team: int, king_moved: bool, rook_a_moved: bool, rook_h_moved: bool) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	if king_moved or is_in_check(board, team):
		return targets

	var rank: int = 0 if team == 1 else 7
	if board[rank][4] != 6 * team:
		return targets

	# Kingside: king e->g, rook h->f. Squares f/g must be empty, and e/f/g must be unattacked.
	if not rook_h_moved and board[rank][7] == 4 * team \
			and _is_empty(board, rank, 5) and _is_empty(board, rank, 6) \
			and not is_square_attacked(board, rank, 4, -team) \
			and not is_square_attacked(board, rank, 5, -team) \
			and not is_square_attacked(board, rank, 6, -team):
		targets.append(Vector2i(rank, 6))

	# Queenside: king e->c, rook a->d. Squares b/c/d must be empty (b only needs
	# to be clear, not safe, since only the king's own path has to be unattacked).
	if not rook_a_moved and board[rank][0] == 4 * team \
			and _is_empty(board, rank, 1) and _is_empty(board, rank, 2) and _is_empty(board, rank, 3) \
			and not is_square_attacked(board, rank, 4, -team) \
			and not is_square_attacked(board, rank, 3, -team) \
			and not is_square_attacked(board, rank, 2, -team):
		targets.append(Vector2i(rank, 2))

	return targets


# EN PASSANT ======================================================
# The target square is only valid for the one move right after an enemy
# pawn's two-square opening push, so it's tracked outside the board (by the
# caller) and passed in rather than derived from board state alone.

static func get_en_passant_targets(board: Array, rank: int, file: int, ep_square: Vector2i) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	if ep_square == Vector2i(-1, -1):
		return targets

	var code: int = board[rank][file]
	if abs(code) != 1:
		return targets
	var team: int = 1 if code > 0 else -1
	var dir: int = 1 if team == 1 else -1

	if rank + dir != ep_square.x or abs(file - ep_square.y) != 1:
		return targets

	var sim_board := _simulate_en_passant(board, Vector2i(rank, file), ep_square)
	if not is_in_check(sim_board, team):
		targets.append(ep_square)
	return targets


static func _simulate_en_passant(board: Array, from: Vector2i, to: Vector2i) -> Array:
	var sim: Array = board.duplicate(true)
	sim[to.x][to.y] = sim[from.x][from.y]
	sim[from.x][from.y] = 0
	sim[from.x][to.y] = 0 # the captured pawn sits beside the mover, not on the target square
	return sim


static func has_en_passant_move(board: Array, team: int, ep_square: Vector2i) -> bool:
	if ep_square == Vector2i(-1, -1):
		return false
	var dir: int = 1 if team == 1 else -1
	var origin_rank: int = ep_square.x - dir
	if origin_rank < 0 or origin_rank > 7:
		return false
	for df in [-1, 1]:
		var f: int = ep_square.y + df
		if f >= 0 and f <= 7 and board[origin_rank][f] == 1 * team \
				and not get_en_passant_targets(board, origin_rank, f, ep_square).is_empty():
			return true
	return false
