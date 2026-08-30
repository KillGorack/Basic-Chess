extends RigidBody3D

const KNOCK_IMPULSE_STRENGTH := 0.35
const KNOCK_TORQUE_STRENGTH := 0.5

var piece: int = 0        # 1 pawn, 2 knight, 3 bishop, 4 rook, 5 queen, 6 king
var team: int = 0         # 1 = white, -1 = black
var has_moved: bool = false

func _ready() -> void:
	# Pieces sit exactly on their square via scripted transforms/tweens, not
	# physics — frozen keeps them from drifting until a capture knocks one over.
	# Kinematic (not the default static) freeze mode matters here: these get
	# repositioned by the hop tween every move, and a static-frozen body's
	# collider can go stale for raycasts since the physics engine assumes
	# static bodies don't move. Kinematic is the mode meant for that case.
	freeze = true
	freeze_mode = FREEZE_MODE_KINEMATIC

func assign_piece(piece_type: int, team_id: int) -> void:
	piece = piece_type
	team = team_id
	has_moved = false

# Unfreezes into a live RigidBody3D and topples it in the given horizontal
# direction, for a captured piece being knocked off the board.
func knock_over(push_dir: Vector3) -> void:
	freeze = false
	apply_impulse(push_dir * KNOCK_IMPULSE_STRENGTH, Vector3(0, 0.15, 0))
	apply_torque_impulse(Vector3(push_dir.z, 0, -push_dir.x) * KNOCK_TORQUE_STRENGTH)
