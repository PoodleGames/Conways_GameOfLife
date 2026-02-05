extends Label

# Zieh hier im Inspector den Node rein,
# der dein Game-of-Life-Script hat (Node2D ganz oben)
@export var target: Node


func _ready() -> void:
	if target == null:
		text = "ERROR: Target not set"
		modulate = Color.RED
		set_process(false)
		return

	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	# Sicherheitscheck
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
