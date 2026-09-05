extends Resource
class_name PieceSettings

enum PieceType {PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6}

@export var piece_type: PieceType = PieceType.PAWN
@export var piece_model: PackedScene
@export var piece_black_icon: Texture
@export var piece_white_icon: Texture

