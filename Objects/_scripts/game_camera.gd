extends Node3D

@onready var camera: Camera3D = $Camera3D
@export var min_pitch_deg := 10.0
@export var max_pitch_deg := 80.0
@export var distance := 0.01
@export var min_distance := 0.01
@export var max_distance := 20.0
@export var rotate_speed := 0.1
@export var zoom_speed := 0.1

var yaw := 0.0
var pitch := 45.0
var focal_point := Vector3.ZERO
var focal_point_target := Vector3.ZERO



func _unhandled_input(event):
	# --- MOVEMENT MODE CHECK ---
	if not Input.is_action_pressed("move_view"):
		return
	# --- ORBIT (LMB) ---
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			yaw -= event.relative.x * rotate_speed
			pitch += event.relative.y * rotate_speed
			pitch = clamp(pitch, min_pitch_deg, max_pitch_deg)
	# --- ZOOM ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance -= zoom_speed
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance += zoom_speed
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_recenter_to_mouse()
		distance = clamp(distance, min_distance, max_distance)


func _recenter_to_mouse():
	var viewport := get_viewport()
	var mouse_pos: Vector2 = viewport.get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = camera.project_ray_normal(mouse_pos)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 2000.0)
	var result := space_state.intersect_ray(query)
	if result:
		focal_point_target = result.position




func _process(delta):
	focal_point = focal_point.lerp(focal_point_target, delta * 5.0)
	var yaw_rad = deg_to_rad(yaw)
	var pitch_rad = deg_to_rad(pitch)
	var x = distance * cos(pitch_rad) * sin(yaw_rad)
	var y = distance * sin(pitch_rad)
	var z = distance * cos(pitch_rad) * cos(yaw_rad)
	global_transform.origin = focal_point + Vector3(x, y, z)
	look_at(focal_point, Vector3.UP)
