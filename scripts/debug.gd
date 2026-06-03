# Godot 4.x
extends Node2D

@export var print_on_ready: bool = true
@export var print_on_input: bool = true
@export var include_groups: bool = true

func _ready() -> void:
	if print_on_ready:
		print_scene_tree()

func _input(event: InputEvent) -> void:
	if not print_on_input:
		return
	# Drück F8 um jederzeit den Baum zu dumpen
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		print_scene_tree()

func print_scene_tree() -> void:
	var root := get_tree().root
	# Aktuelle Szene ist in der Regel das letzte Child vom root viewport
	var current_scene := get_tree().current_scene

	print("\n================ SCENE TREE DUMP ================")
	print("Root:        ", root.get_path(), "  [", root.get_class(), "]")
	if current_scene:
		print("CurrentScene:", current_scene.get_path(), "  [", current_scene.get_class(), "]")
		print("------------------------------------------------")
		_print_node_recursive(current_scene, 0)
	else:
		print("No current_scene found. Dumping root children:")
		print("------------------------------------------------")
		_print_node_recursive(root, 0)
	print("=================================================\n")

func _print_node_recursive(n: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var path := str(n.get_path())
	var cls := n.get_class()

	var extra := ""
	if n is CanvasItem:
		var ci := n as CanvasItem
		extra += " vis=%s" % str(ci.visible)
	if n is Node2D:
		var n2 := n as Node2D
		extra += " pos=%s rot=%.2f scale=%s" % [str(n2.position), n2.rotation, str(n2.scale)]
	if n is Control:
		var c := n as Control
		extra += " rect_pos=%s size=%s" % [str(c.position), str(c.size)]

	if include_groups:
		var groups := n.get_groups()
		if groups.size() > 0:
			extra += " groups=%s" % str(groups)

	print("%s- %s  [%s]%s" % [indent, path, cls, extra])

	for child in n.get_children():
		if child is Node:
			_print_node_recursive(child, depth + 1)
