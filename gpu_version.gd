## GPU-accelerated Conway's Game of Life renderer for Godot 4.
##
## Runs the simulation entirely on the GPU using two ping-pong R8 textures
## for state and a separate RGBA8 texture for colourised output.
## The result is displayed via a [Sprite2D] that is created at runtime.
extends Node2D

@export var grid_w: int = 920
@export var grid_h: int = 925
@export_range(1, 120, 1) var ticks_per_second: int = 15
@export var random_fill: bool = true
@export_range(0.0, 1.0, 0.01) var random_density: float = 0.10
@export_range(1, 8, 1) var pixel_scale: int = 1

var base_grid_w: int = 920
var base_grid_h: int = 925

## Available starting configurations for the grid.
enum StartPattern { RANDOM, RANDOM_CLUSTERS, ACORN, R_PENTOMINO, GOSPER_GLIDER_GUN }
@export var start_pattern: StartPattern = StartPattern.RANDOM_CLUSTERS

## Predefined colour palettes applied by the colour-conversion shader.
enum ColorScheme { CYAN_PURPLE, FIRE, OCEAN, MATRIX, SUNSET, MINT }
@export var color_scheme: ColorScheme = ColorScheme.CYAN_PURPLE
@export var enable_glow: bool = true
@export_range(0.0, 1.0, 0.05) var glow_strength: float = 0.3

@export var auto_restart_on_stable: bool = true
@export var stability_check_interval: int = 50

@export var inject_chaos: bool = true
@export var inject_interval: float = 10.0

@onready var gamespeed_input: LineEdit = $"../MainSettings/gamespeed"
@onready var density_input: LineEdit = $"../MainSettings/density"
@onready var pixelsize_input: LineEdit = $"../MainSettings/pixelsize"
@onready var pattern_option: OptionButton = $"../PatternSettings/pattern"
@onready var restart_option: OptionButton = $"../Restart/pattern"
@onready var restart_interval_input: LineEdit = $"../Restart/interval"
@onready var inject_option: OptionButton = $"../Inject/Inject"
@onready var inject_interval_input: LineEdit = $"../Inject/interval"

var rd: RenderingDevice
var gol_shader: RID
var gol_pipeline: RID
var uniform_set_a: RID
var uniform_set_b: RID
var texture_a: RID
var texture_b: RID
var current_is_a: bool = true

var color_shader: RID
var color_pipeline: RID
var color_texture: RID
var color_uniform_set_a: RID
var color_uniform_set_b: RID

var img: Image
var tex: ImageTexture
var sprite: Sprite2D

var acc := 0.0
var generation := 0

var last_grid_hash: int = 0
var stable_count: int = 0

var inject_timer: float = 0.0

## Colour palette definitions. Each entry provides dead-cell, alive-cell,
## and glow colours used as push constants by the colour-conversion shader.
var color_schemes := {
	ColorScheme.CYAN_PURPLE: {
		"dead": Color(0.05, 0.05, 0.15, 1.0),
		"alive": Color(0.3, 0.8, 1.0, 1.0),
		"glow": Color(0.6, 0.3, 1.0, 1.0)
	},
	ColorScheme.FIRE: {
		"dead": Color(0.1, 0.05, 0.0, 1.0),
		"alive": Color(1.0, 0.5, 0.1, 1.0),
		"glow": Color(1.0, 0.9, 0.3, 1.0)
	},
	ColorScheme.OCEAN: {
		"dead": Color(0.0, 0.05, 0.1, 1.0),
		"alive": Color(0.2, 0.7, 0.8, 1.0),
		"glow": Color(0.4, 0.9, 1.0, 1.0)
	},
	ColorScheme.MATRIX: {
		"dead": Color(0.0, 0.05, 0.0, 1.0),
		"alive": Color(0.2, 1.0, 0.2, 1.0),
		"glow": Color(0.6, 1.0, 0.6, 1.0)
	},
	ColorScheme.SUNSET: {
		"dead": Color(0.1, 0.05, 0.15, 1.0),
		"alive": Color(1.0, 0.4, 0.6, 1.0),
		"glow": Color(1.0, 0.7, 0.3, 1.0)
	},
	ColorScheme.MINT: {
		"dead": Color(0.05, 0.1, 0.1, 1.0),
		"alive": Color(0.4, 1.0, 0.8, 1.0),
		"glow": Color(0.7, 1.0, 0.9, 1.0)
	}
}


## Initialises the local [RenderingDevice], compiles both compute shaders,
## creates GPU textures, seeds the initial pattern, and sets up the display sprite.
func _ready() -> void:
	base_grid_w = grid_w
	base_grid_h = grid_h

	rd = RenderingServer.create_local_rendering_device()
	if not rd:
		push_error("GPU Compute nicht verfügbar!")
		return

	var gol_shader_file := load("res://game_of_life.glsl") as RDShaderFile
	if not gol_shader_file:
		push_error("game_of_life.glsl konnte nicht geladen werden!")
		return
	var gol_shader_spirv := gol_shader_file.get_spirv()
	gol_shader = rd.shader_create_from_spirv(gol_shader_spirv)
	gol_pipeline = rd.compute_pipeline_create(gol_shader)

	var color_shader_file := load("res://color_converter.glsl") as RDShaderFile
	if not color_shader_file:
		push_error("color_converter.glsl konnte nicht geladen werden!")
		return
	var color_shader_spirv := color_shader_file.get_spirv()
	color_shader = rd.shader_create_from_spirv(color_shader_spirv)
	color_pipeline = rd.compute_pipeline_create(color_shader)

	create_gpu_textures()

	img = Image.create(grid_w, grid_h, false, Image.FORMAT_RGBA8)
	tex = ImageTexture.create_from_image(img)
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.scale = Vector2(pixel_scale, pixel_scale)
	add_child(sprite)

	if random_fill:
		initialize_pattern()
	else:
		clear_grid()

	upload_to_gpu()
	convert_colors_gpu()
	download_from_gpu()

	call_deferred("setup_ui")


## Connects all UI controls to their respective signal handlers and
## populates option buttons with the available enum values.
func setup_ui() -> void:
	if gamespeed_input:
		gamespeed_input.text = str(ticks_per_second)
		gamespeed_input.text_changed.connect(_on_gamespeed_changed)
		gamespeed_input.text_submitted.connect(func(_t): gamespeed_input.release_focus())

	if density_input:
		density_input.text = str(random_density)
		density_input.text_changed.connect(_on_density_changed)
		density_input.text_submitted.connect(func(_t): density_input.release_focus())

	if pixelsize_input:
		pixelsize_input.text = str(pixel_scale)
		pixelsize_input.max_length = 1
		pixelsize_input.text_changed.connect(_on_pixelsize_changed)
		pixelsize_input.text_submitted.connect(func(_t): pixelsize_input.release_focus())

	if pattern_option:
		pattern_option.clear()
		pattern_option.add_item("RANDOM", StartPattern.RANDOM)
		pattern_option.add_item("RANDOM_CLUSTERS", StartPattern.RANDOM_CLUSTERS)
		pattern_option.add_item("ACORN", StartPattern.ACORN)
		pattern_option.add_item("R_PENTOMINO", StartPattern.R_PENTOMINO)
		pattern_option.add_item("GOSPER_GLIDER_GUN", StartPattern.GOSPER_GLIDER_GUN)
		pattern_option.selected = start_pattern
		pattern_option.item_selected.connect(_on_pattern_selected)
		pattern_option.item_selected.connect(func(_i): pattern_option.release_focus())

	if restart_option:
		restart_option.clear()
		restart_option.add_item("true", 0)
		restart_option.add_item("false", 1)
		restart_option.selected = 0 if auto_restart_on_stable else 1
		restart_option.item_selected.connect(_on_restart_option_selected)
		restart_option.item_selected.connect(func(_i): restart_option.release_focus())

	if restart_interval_input:
		restart_interval_input.text = str(stability_check_interval)
		restart_interval_input.text_changed.connect(_on_restart_interval_changed)
		restart_interval_input.text_submitted.connect(func(_t): restart_interval_input.release_focus())

	if inject_option:
		inject_option.clear()
		inject_option.add_item("true", 0)
		inject_option.add_item("false", 1)
		inject_option.selected = 0 if inject_chaos else 1
		inject_option.item_selected.connect(_on_inject_option_selected)
		inject_option.item_selected.connect(func(_i): inject_option.release_focus())

	if inject_interval_input:
		inject_interval_input.text = str(inject_interval)
		inject_interval_input.text_changed.connect(_on_inject_interval_changed)
		inject_interval_input.text_submitted.connect(func(_t): inject_interval_input.release_focus())


## Updates [member ticks_per_second] when the user edits the speed field.
func _on_gamespeed_changed(new_text: String) -> void:
	var value = new_text.to_int()
	if value >= 1:
		ticks_per_second = value


## Updates [member random_density] when the user edits the density field.
func _on_density_changed(new_text: String) -> void:
	var value = new_text.to_float()
	if value >= 0.0 and value <= 1.0:
		random_density = value


## Updates [member pixel_scale] and recreates the simulation when the grid
## resolution changes as a result of a different pixel scale.
func _on_pixelsize_changed(new_text: String) -> void:
	var value = new_text.to_int()
	if value >= 1 and value <= 8:
		pixel_scale = value
		var new_grid_w = base_grid_w / pixel_scale
		var new_grid_h = base_grid_h / pixel_scale

		if new_grid_w != grid_w or new_grid_h != grid_h:
			grid_w = new_grid_w
			grid_h = new_grid_h
			recreate_simulation()
		else:
			if sprite:
				sprite.scale = Vector2(pixel_scale, pixel_scale)


## Sets the active starting pattern from the option button selection index.
func _on_pattern_selected(index: int) -> void:
	start_pattern = index as StartPattern


## Enables or disables auto-restart based on the option button selection.
func _on_restart_option_selected(index: int) -> void:
	auto_restart_on_stable = (index == 0)


## Updates [member stability_check_interval] when the user edits the interval field.
func _on_restart_interval_changed(new_text: String) -> void:
	var value = new_text.to_int()
	if value > 0:
		stability_check_interval = value


## Enables or disables chaos injection based on the option button selection.
func _on_inject_option_selected(index: int) -> void:
	inject_chaos = (index == 0)


## Updates [member inject_interval] when the user edits the inject interval field.
func _on_inject_interval_changed(new_text: String) -> void:
	var value = new_text.to_float()
	if value > 0.0:
		inject_interval = value


## Creates the R8 ping-pong textures for Game of Life state and the RGBA8
## output texture for colourised display, then builds all uniform sets.
func create_gpu_textures() -> void:
	var fmt_r8 := RDTextureFormat.new()
	fmt_r8.width = grid_w
	fmt_r8.height = grid_h
	fmt_r8.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt_r8.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)

	var empty_data := PackedByteArray()
	empty_data.resize(grid_w * grid_h)
	empty_data.fill(0)

	texture_a = rd.texture_create(fmt_r8, RDTextureView.new(), [empty_data])
	texture_b = rd.texture_create(fmt_r8, RDTextureView.new(), [empty_data])

	var fmt_rgba := RDTextureFormat.new()
	fmt_rgba.width = grid_w
	fmt_rgba.height = grid_h
	fmt_rgba.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt_rgba.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)

	var empty_rgba := PackedByteArray()
	empty_rgba.resize(grid_w * grid_h * 4)
	empty_rgba.fill(0)

	color_texture = rd.texture_create(fmt_rgba, RDTextureView.new(), [empty_rgba])

	create_uniform_sets()


## Builds the four uniform sets required for double-buffered GoL dispatch
## and the two uniform sets for the colour-conversion shader.
func create_uniform_sets() -> void:
	var uniform_input_a := RDUniform.new()
	uniform_input_a.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_input_a.binding = 0
	uniform_input_a.add_id(texture_a)

	var uniform_output_b := RDUniform.new()
	uniform_output_b.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_output_b.binding = 1
	uniform_output_b.add_id(texture_b)

	uniform_set_a = rd.uniform_set_create([uniform_input_a, uniform_output_b], gol_shader, 0)

	var uniform_input_b := RDUniform.new()
	uniform_input_b.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_input_b.binding = 0
	uniform_input_b.add_id(texture_b)

	var uniform_output_a := RDUniform.new()
	uniform_output_a.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_output_a.binding = 1
	uniform_output_a.add_id(texture_a)

	uniform_set_b = rd.uniform_set_create([uniform_input_b, uniform_output_a], gol_shader, 0)

	var color_in_a := RDUniform.new()
	color_in_a.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_in_a.binding = 0
	color_in_a.add_id(texture_a)

	var color_out := RDUniform.new()
	color_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_out.binding = 1
	color_out.add_id(color_texture)

	color_uniform_set_a = rd.uniform_set_create([color_in_a, color_out], color_shader, 0)

	var color_in_b := RDUniform.new()
	color_in_b.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_in_b.binding = 0
	color_in_b.add_id(texture_b)

	color_uniform_set_b = rd.uniform_set_create([color_in_b, color_out], color_shader, 0)


## Advances the simulation, handles input, triggers stability checks,
## and schedules chaos injection according to [member inject_interval].
func _process(delta: float) -> void:
	handle_input()

	var tps: int = maxi(ticks_per_second, 1)
	var step: float = 1.0 / float(tps)
	acc += delta

	var steps: int = 0
	while acc >= step and steps < 10:
		acc -= step
		sim_step_gpu()
		steps += 1
		generation += 1

	if steps > 0:
		convert_colors_gpu()
		download_from_gpu()

		if auto_restart_on_stable and generation % stability_check_interval == 0:
			check_stability()

	if inject_chaos:
		inject_timer += delta
		if inject_timer >= inject_interval:
			inject_timer = 0.0
			inject_random_life()


## Dispatches one Game of Life generation on the GPU using the active
## ping-pong buffer pair, then flips [member current_is_a].
func sim_step_gpu() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, gol_pipeline)

	if current_is_a:
		rd.compute_list_bind_uniform_set(compute_list, uniform_set_a, 0)
	else:
		rd.compute_list_bind_uniform_set(compute_list, uniform_set_b, 0)

	var x_groups := ceili(grid_w / 8.0)
	var y_groups := ceili(grid_h / 8.0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

	current_is_a = !current_is_a


## Runs the colour-conversion shader, uploading the active palette and glow
## settings as push constants before dispatch.
func convert_colors_gpu() -> void:
	var colors = color_schemes[color_scheme]

	var push_data := PackedByteArray()
	push_data.resize(64)

	var offset := 0
	push_data.encode_float(offset, colors["dead"].r); offset += 4
	push_data.encode_float(offset, colors["dead"].g); offset += 4
	push_data.encode_float(offset, colors["dead"].b); offset += 4
	push_data.encode_float(offset, colors["dead"].a); offset += 4

	push_data.encode_float(offset, colors["alive"].r); offset += 4
	push_data.encode_float(offset, colors["alive"].g); offset += 4
	push_data.encode_float(offset, colors["alive"].b); offset += 4
	push_data.encode_float(offset, colors["alive"].a); offset += 4

	push_data.encode_float(offset, colors["glow"].r); offset += 4
	push_data.encode_float(offset, colors["glow"].g); offset += 4
	push_data.encode_float(offset, colors["glow"].b); offset += 4
	push_data.encode_float(offset, colors["glow"].a); offset += 4

	push_data.encode_float(offset, glow_strength); offset += 4
	push_data.encode_float(offset, 1.0 if enable_glow else 0.0)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, color_pipeline)

	if current_is_a:
		rd.compute_list_bind_uniform_set(compute_list, color_uniform_set_a, 0)
	else:
		rd.compute_list_bind_uniform_set(compute_list, color_uniform_set_b, 0)

	rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())

	var x_groups := ceili(grid_w / 8.0)
	var y_groups := ceili(grid_h / 8.0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()


## Compares the live-cell count against the previous check to detect a
## stable or oscillating state. Reinitialises the grid after five
## consecutive identical counts.
func check_stability() -> void:
	var current_texture: RID = texture_a if current_is_a else texture_b
	var data := rd.texture_get_data(current_texture, 0)

	var alive_count: int = 0
	for i in range(data.size()):
		if data[i] > 0:
			alive_count += 1

	if alive_count == last_grid_hash:
		stable_count += 1
		if stable_count >= 5:
			initialize_pattern()
			upload_to_gpu()
			generation = 0
			stable_count = 0
			last_grid_hash = 0
			convert_colors_gpu()
			download_from_gpu()
			return
	else:
		stable_count = 0

	last_grid_hash = alive_count


## Writes between 50 and 100 random live cells directly into the active
## GPU texture to perturb a stagnating simulation.
func inject_random_life() -> void:
	var current_texture: RID = texture_a if current_is_a else texture_b
	var data := rd.texture_get_data(current_texture, 0)

	for i in range(randi_range(50, 100)):
		var idx: int = randi() % data.size()
		data[idx] = 255

	rd.texture_update(current_texture, 0, data)


## Per-key debounce flags to ensure single-press behaviour for C and G.
var c_lock: bool = false
var g_lock: bool = false


## Processes keyboard input for simulation control.
## Releases UI focus on confirm/cancel, restarts or clears the grid,
## and cycles the colour scheme or toggles glow with debounce guards.
func handle_input() -> void:
	if Input.is_action_just_pressed("ui_select") or Input.is_action_just_pressed("ui_cancel"):
		if gamespeed_input and gamespeed_input.has_focus():
			gamespeed_input.release_focus()
		if density_input and density_input.has_focus():
			density_input.release_focus()
		if pixelsize_input and pixelsize_input.has_focus():
			pixelsize_input.release_focus()
		if restart_interval_input and restart_interval_input.has_focus():
			restart_interval_input.release_focus()
		if inject_interval_input and inject_interval_input.has_focus():
			inject_interval_input.release_focus()
		if pattern_option and pattern_option.has_focus():
			pattern_option.release_focus()
		if restart_option and restart_option.has_focus():
			restart_option.release_focus()
		if inject_option and inject_option.has_focus():
			inject_option.release_focus()

	if Input.is_action_just_pressed("ui_select") or Input.is_key_pressed(KEY_R) or Input.is_key_pressed(KEY_SPACE):
		initialize_pattern()
		upload_to_gpu()
		generation = 0
		stable_count = 0
		last_grid_hash = 0
		convert_colors_gpu()
		download_from_gpu()

	if Input.is_action_just_pressed("ui_cancel"):
		clear_grid()
		upload_to_gpu()
		generation = 0
		stable_count = 0
		last_grid_hash = 0
		convert_colors_gpu()
		download_from_gpu()

	if Input.is_key_pressed(KEY_C):
		if not c_lock:
			c_lock = true
			color_scheme = (color_scheme + 1) % ColorScheme.size()
			convert_colors_gpu()
			download_from_gpu()
	else:
		c_lock = false

	if Input.is_key_pressed(KEY_G):
		if not g_lock:
			g_lock = true
			enable_glow = !enable_glow
			convert_colors_gpu()
			download_from_gpu()
	else:
		g_lock = false


var cpu_grid: PackedByteArray


## Resets [member cpu_grid] and seeds it according to [member start_pattern].
func initialize_pattern() -> void:
	cpu_grid = PackedByteArray()
	cpu_grid.resize(grid_w * grid_h)
	cpu_grid.fill(0)

	match start_pattern:
		StartPattern.RANDOM:
			seed_random_simple()
		StartPattern.RANDOM_CLUSTERS:
			seed_random_clusters()
		StartPattern.ACORN:
			place_acorn()
		StartPattern.R_PENTOMINO:
			place_r_pentomino()
		StartPattern.GOSPER_GLIDER_GUN:
			place_gosper_glider_gun()


## Fills the grid with uniformly distributed live cells at [member random_density].
func seed_random_simple() -> void:
	for i in range(grid_w * grid_h):
		cpu_grid[i] = 255 if randf() < random_density else 0


## Seeds the grid with small random clusters whose total coverage is
## proportional to [member random_density].
func seed_random_clusters() -> void:
	var num_seeds: int = int(grid_w * grid_h * random_density * 0.3)
	for _i in range(num_seeds):
		var cx: int = randi_range(5, grid_w - 6)
		var cy: int = randi_range(5, grid_h - 6)
		var size: int = randi_range(2, 4)
		for dy in range(-size, size + 1):
			for dx in range(-size, size + 1):
				if randf() < 0.6:
					var x: int = cx + dx
					var y: int = cy + dy
					if x >= 0 and x < grid_w and y >= 0 and y < grid_h:
						cpu_grid[y * grid_w + x] = 255


## Places the Acorn methuselah pattern at the centre of the grid.
func place_acorn() -> void:
	var cx: int = grid_w / 2
	var cy: int = grid_h / 2
	var pattern: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 2),
		Vector2i(3, 1), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)
	]
	place_pattern(pattern, cx, cy)


## Places the R-pentomino methuselah pattern at the centre of the grid.
func place_r_pentomino() -> void:
	var cx: int = grid_w / 2
	var cy: int = grid_h / 2
	var pattern: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1),
		Vector2i(1, 1), Vector2i(1, 2)
	]
	place_pattern(pattern, cx, cy)


## Places the Gosper Glider Gun near the left edge of the grid,
## vertically centred.
func place_gosper_glider_gun() -> void:
	var cx: int = 50
	var cy: int = grid_h / 2
	var pattern: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(0, 5), Vector2i(1, 4), Vector2i(1, 5),
		Vector2i(10, 4), Vector2i(10, 5), Vector2i(10, 6),
		Vector2i(11, 3), Vector2i(11, 7),
		Vector2i(12, 2), Vector2i(12, 8),
		Vector2i(13, 2), Vector2i(13, 8),
		Vector2i(14, 5),
		Vector2i(15, 3), Vector2i(15, 7),
		Vector2i(16, 4), Vector2i(16, 5), Vector2i(16, 6),
		Vector2i(17, 5),
		Vector2i(20, 2), Vector2i(20, 3), Vector2i(20, 4),
		Vector2i(21, 2), Vector2i(21, 3), Vector2i(21, 4),
		Vector2i(22, 1), Vector2i(22, 5),
		Vector2i(24, 0), Vector2i(24, 1), Vector2i(24, 5), Vector2i(24, 6),
		Vector2i(34, 2), Vector2i(34, 3), Vector2i(35, 2), Vector2i(35, 3)
	]
	place_pattern(pattern, cx, cy)


## Stamps a relative cell pattern into [member cpu_grid] at the given origin.
## Cells outside grid bounds are silently skipped.
func place_pattern(pattern: Array[Vector2i], cx: int, cy: int) -> void:
	for pos in pattern:
		var x: int = cx + pos.x
		var y: int = cy + pos.y
		if x >= 0 and x < grid_w and y >= 0 and y < grid_h:
			cpu_grid[y * grid_w + x] = 255


## Fills [member cpu_grid] with zeros, resulting in an empty grid.
func clear_grid() -> void:
	cpu_grid = PackedByteArray()
	cpu_grid.resize(grid_w * grid_h)
	cpu_grid.fill(0)


## Uploads [member cpu_grid] to [member texture_a] and resets the ping-pong
## state so texture_a is treated as the current generation.
func upload_to_gpu() -> void:
	rd.texture_update(texture_a, 0, cpu_grid)
	current_is_a = true


## Reads the colourised RGBA8 output texture from the GPU and updates
## the display [ImageTexture].
func download_from_gpu() -> void:
	var data := rd.texture_get_data(color_texture, 0)
	img.set_data(grid_w, grid_h, false, Image.FORMAT_RGBA8, data)
	tex.update(img)


## Frees all GPU textures and uniform sets, then recreates them at the
## current grid dimensions. Used when [member pixel_scale] changes.
func recreate_simulation() -> void:
	if rd:
		rd.free_rid(uniform_set_a)
		rd.free_rid(uniform_set_b)
		rd.free_rid(color_uniform_set_a)
		rd.free_rid(color_uniform_set_b)
		rd.free_rid(texture_a)
		rd.free_rid(texture_b)
		rd.free_rid(color_texture)

	create_gpu_textures()

	img = Image.create(grid_w, grid_h, false, Image.FORMAT_RGBA8)
	tex = ImageTexture.create_from_image(img)

	if sprite:
		sprite.texture = tex
		sprite.scale = Vector2(pixel_scale, pixel_scale)

	initialize_pattern()
	upload_to_gpu()
	generation = 0
	stable_count = 0
	last_grid_hash = 0
	convert_colors_gpu()
	download_from_gpu()


## Draws a HUD overlay showing generation count, FPS, active colour scheme,
## and glow/auto-restart state, plus a control reference line.
## Calls [method queue_redraw] every frame to keep the display current.
func _draw() -> void:
	var scheme_name: String = ColorScheme.keys()[color_scheme]
	var text_color: Color = color_schemes[color_scheme]["alive"]

	var base_pos = Vector2(10, 20)
	if sprite:
		base_pos = sprite.position + Vector2(10, 20)

	var info: String = "Gen: %d | FPS: %d | %s%s%s" % [
		generation,
		Engine.get_frames_per_second(),
		scheme_name,
		" | Glow" if enable_glow else "",
		" | Auto-Restart" if auto_restart_on_stable else ""
	]

	draw_string(ThemeDB.fallback_font, base_pos, info,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, text_color)

	var controls: String = "[SPACE/R] Neustart | [C] Farbschema | [G] Glow | [ESC] Löschen"
	draw_string(ThemeDB.fallback_font, base_pos + Vector2(0, 20), controls,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_color.darkened(0.3))

	queue_redraw()


## Releases all GPU resources when the node leaves the scene tree.
func _exit_tree() -> void:
	if rd:
		rd.free_rid(uniform_set_a)
		rd.free_rid(uniform_set_b)
		rd.free_rid(color_uniform_set_a)
		rd.free_rid(color_uniform_set_b)
		rd.free_rid(texture_a)
		rd.free_rid(texture_b)
		rd.free_rid(color_texture)
		rd.free_rid(gol_pipeline)
		rd.free_rid(color_pipeline)
		rd.free_rid(gol_shader)
		rd.free_rid(color_shader)
		rd.free()
