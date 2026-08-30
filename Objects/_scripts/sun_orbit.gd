extends DirectionalLight3D

## Continuously spins this light around the world up/down axis, sweeping the
## sun across the sky like it's crossing from horizon to horizon. The sky
## shader's sun disc already follows this light (LIGHT0_DIRECTION), so this
## one script moves both the actual lighting and the visual sun together.
## Attach directly to the DirectionalLight3D node.

@export var rotate_enabled: bool = true
@export var degrees_per_second: float = 5.0
@export var clockwise: bool = true

func _process(delta: float) -> void:
	if not rotate_enabled:
		return
	var spin_sign: float = 1.0 if clockwise else -1.0
	rotate_y(deg_to_rad(degrees_per_second) * delta * spin_sign)
