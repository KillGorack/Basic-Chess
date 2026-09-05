extends RigidBody3D

const KNOCK_IMPULSE_STRENGTH := 0.35
const KNOCK_TORQUE_STRENGTH := 0.5

var piece: int = 0
var team: int = 0
var has_moved: bool = false

func _ready() -> void:
	freeze = true
	freeze_mode = FREEZE_MODE_KINEMATIC

func assign_piece(piece_type: int, team_id: int) -> void:
	piece = piece_type
	team = team_id
	has_moved = false

func knock_over(push_dir: Vector3) -> void:
	freeze = false
	apply_impulse(push_dir * KNOCK_IMPULSE_STRENGTH, Vector3(0, 0.15, 0))
	apply_torque_impulse(Vector3(push_dir.z, 0, -push_dir.x) * KNOCK_TORQUE_STRENGTH)
