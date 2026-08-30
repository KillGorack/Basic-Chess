extends RigidBody3D

var piece: int = 0        # 1 pawn, 2 knight, 3 bishop, 4 rook, 5 queen, 6 king
var team: int = 0         # 1 = white, -1 = black
var has_moved: bool = false

func _ready() -> void:
	pass

func assign_piece(piece_type: int, team_id: int) -> void:
	piece = piece_type
	team = team_id
	has_moved = false
