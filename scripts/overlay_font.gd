## HUD overlay label that mirrors simulation state from the Game of Life node.
##
## Assign the [Node2D] running the Game of Life script to [member target]
## in the Inspector. The label updates every frame with generation count,
## FPS, active colour scheme, and enabled feature flags.
extends Label

## The Node2D that holds the Game of Life simulation script.
@export var target: Node


## Validates [member target] and disables processing if it is unset.
func _ready() -> void:
	if target == null:
		text = "ERROR: Target not set"
		modulate = Color.RED
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS


## Updates the label text and colour each frame to reflect the current
## simulation state read from [member target].
func _process(_delta: float) -> void:
	if target == null:
		return
	var scheme_name: String = target.ColorScheme.keys()[target.color_scheme]
	var text_color: Color = target.color_schemes[target.color_scheme]["alive"]
	text = "Gen: %d | FPS: %d | %s%s%s\n[SPACE/R] Neustart | [C] Farbschema | [G] Glow | [ESC] Löschen" % [
		target.generation,
		Engine.get_frames_per_second(),
		scheme_name,
		" | Glow" if target.enable_glow else "",
		" | Auto-Restart" if target.auto_restart_on_stable else ""
	]
	modulate = text_color
