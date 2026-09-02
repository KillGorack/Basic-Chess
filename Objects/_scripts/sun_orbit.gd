extends DirectionalLight3D

## Continuously spins this light around the world up/down axis for shadows,
## and pushes its horizontal (compass) facing to the sky shader's
## sun_azimuth_dir uniform every frame, so the sun disc sweeps around the
## sky in sync with the light's rotation. The sun's ELEVATION stays
## independent, controlled purely by the sky shader's own sun_angle uniform,
## regardless of the light's actual tilt (kept fixed here for good shadow
## bounce).
## Attach directly to the DirectionalLight3D node.

@export var rotate_enabled: bool = true
@export var degrees_per_second: float = 5.0
@export var clockwise: bool = true

@onready var _sky_material: ShaderMaterial = (get_parent().get_node("WorldEnvironment") as WorldEnvironment).environment.sky.sky_material

func _ready() -> void:
	_update_sky_azimuth()

func _process(delta: float) -> void:
	if rotate_enabled:
		var spin_sign: float = 1.0 if clockwise else -1.0
		rotate_y(deg_to_rad(degrees_per_second) * delta * spin_sign)
	_update_sky_azimuth()

func _update_sky_azimuth() -> void:
	# The light's local +Z (opposite its -Z shine direction) already points
	# toward the sun; take just its horizontal (X/Z) component so the sky's
	# sun disc sweeps in sync with the light's rotation, independent of the
	# light's elevation/tilt.
	var toward_sun: Vector3 = global_transform.basis.z
	_sky_material.set_shader_parameter("sun_azimuth_dir", Vector2(toward_sun.x, toward_sun.z))
