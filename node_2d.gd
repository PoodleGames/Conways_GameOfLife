# Godot 4.x - Optimized Conway's Game of Life
extends Node2D

@export var grid_w: int = 512
@export var grid_h: int = 512
@export_range(1, 60, 1) var ticks_per_second: int = 30
@export var random_fill: bool = true
@export_range(0.0, 1.0, 0.01) var random_density: float = 0.15
@export_range(1, 8, 1) var pixel_scale: int = 2

# Interessante Startmuster
enum StartPattern { RANDOM, RANDOM_CLUSTERS, ACORN, R_PENTOMINO, GOSPER_GLIDER_GUN }
@export var start_pattern: StartPattern = StartPattern.RANDOM_CLUSTERS

var grid: PackedByteArray
var next_grid: PackedByteArray
var neighbor_cache: PackedInt32Array
var img: Image
var tex: ImageTexture
var sprite: Sprite2D
var paused := false
var acc := 0.0
var generation := 0

# Optimierung: Lookup-Table für Zellübergang
var survival_lut: PackedByteArray
var birth_lut: PackedByteArray

func _ready() -> void:
	# Survival/Birth Lookup Tables (Conway: B3/S23)
	survival_lut = PackedByteArray([0, 0, 255, 255, 0, 0, 0, 0, 0])
	birth_lut = PackedByteArray([0, 0, 0, 255, 0, 0, 0, 0, 0])
	
	# Grids initialisieren
	var size: int = grid_w * grid_h
	grid = PackedByteArray()
	grid.resize(size)
	grid.fill(0)
	next_grid = PackedByteArray()
	next_grid.resize(size)
	
	# Neighbor Cache
	neighbor_cache = PackedInt32Array()
	neighbor_cache.resize(size)
	
	# Bild setup
	img = Image.create(grid_w, grid_h, false, Image.FORMAT_L8)
	tex = ImageTexture.create_from_image(img)
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.scale = Vector2(pixel_scale, pixel_scale)
	add_child(sprite)
	
	# Schöner Start
	if random_fill:
		initialize_pattern()
	else:
		clear_grid()
	
	upload_to_texture()

func _process(delta: float) -> void:
	handle_input()
	if paused:
		return
	
	var tps: int = clampi(ticks_per_second, 1, 60)
	var step: float = 1.0 / float(tps)
	acc += delta
	
	var max_steps: int = 5
	var steps: int = 0
	while acc >= step and steps < max_steps:
		acc -= step
		sim_step_optimized()
		steps += 1
		generation += 1
	
	if steps > 0:
		upload_to_texture()

func handle_input() -> void:
	if Input.is_action_just_pressed("ui_accept"):
		paused = !paused
	
	if Input.is_action_just_pressed("ui_select"):
		initialize_pattern()
		generation = 0
		upload_to_texture()
	
	if Input.is_action_just_pressed("ui_cancel"):
		clear_grid()
		generation = 0
		upload_to_texture()

# --- OPTIMIERTE SIMULATION ---
func sim_step_optimized() -> void:
	# 1. Pass: Nachbarn zählen
	for y in range(grid_h):
		var row: int = y * grid_w
		var prev_row: int = (y - 1) * grid_w if y > 0 else -1
		var next_row: int = (y + 1) * grid_w if y < grid_h - 1 else -1
		
		for x in range(grid_w):
			var idx: int = row + x
			var count: int = 0
			
			# Nachbarn zählen (unrolled)
			if y > 0:
				if x > 0 and grid[prev_row + x - 1] != 0: count += 1
				if grid[prev_row + x] != 0: count += 1
				if x < grid_w - 1 and grid[prev_row + x + 1] != 0: count += 1
			
			if x > 0 and grid[idx - 1] != 0: count += 1
			if x < grid_w - 1 and grid[idx + 1] != 0: count += 1
			
			if y < grid_h - 1:
				if x > 0 and grid[next_row + x - 1] != 0: count += 1
				if grid[next_row + x] != 0: count += 1
				if x < grid_w - 1 and grid[next_row + x + 1] != 0: count += 1
			
			neighbor_cache[idx] = count
	
	# 2. Pass: Neue Generation berechnen
	for i in range(grid_w * grid_h):
		var alive: bool = grid[i] != 0
		var n: int = neighbor_cache[i]
		
		if alive:
			next_grid[i] = survival_lut[n]
		else:
			next_grid[i] = birth_lut[n]
	
	# Swap
	var tmp: PackedByteArray = grid
	grid = next_grid
	next_grid = tmp

# --- SCHÖNE STARTMUSTER ---
func initialize_pattern() -> void:
	clear_grid()
	
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

func seed_random_simple() -> void:
	for i in range(grid_w * grid_h):
		grid[i] = 255 if randf() < random_density else 0

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
						grid[y * grid_w + x] = 255

func place_acorn() -> void:
	var cx: int = grid_w / 2
	var cy: int = grid_h / 2
	var pattern: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(1, 2),
		Vector2i(3, 1),
		Vector2i(4, 0),
		Vector2i(5, 0),
		Vector2i(6, 0)
	]
	place_pattern(pattern, cx, cy)

func place_r_pentomino() -> void:
	var cx: int = grid_w / 2
	var cy: int = grid_h / 2
	var pattern: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(1, 2)
	]
	place_pattern(pattern, cx, cy)

func place_gosper_glider_gun() -> void:
	var cx: int = 20
	var cy: int = grid_h / 2
	var pattern: Array[Vector2i] = [
		# Linker Block
		Vector2i(0, 4), Vector2i(0, 5), Vector2i(1, 4), Vector2i(1, 5),
		# Mittlerer Teil
		Vector2i(10, 4), Vector2i(10, 5), Vector2i(10, 6),
		Vector2i(11, 3), Vector2i(11, 7),
		Vector2i(12, 2), Vector2i(12, 8),
		Vector2i(13, 2), Vector2i(13, 8),
		Vector2i(14, 5),
		Vector2i(15, 3), Vector2i(15, 7),
		Vector2i(16, 4), Vector2i(16, 5), Vector2i(16, 6),
		Vector2i(17, 5),
		# Rechter Teil
		Vector2i(20, 2), Vector2i(20, 3), Vector2i(20, 4),
		Vector2i(21, 2), Vector2i(21, 3), Vector2i(21, 4),
		Vector2i(22, 1), Vector2i(22, 5),
		Vector2i(24, 0), Vector2i(24, 1), Vector2i(24, 5), Vector2i(24, 6),
		# Rechter Block
		Vector2i(34, 2), Vector2i(34, 3), Vector2i(35, 2), Vector2i(35, 3)
	]
	place_pattern(pattern, cx, cy)

func place_pattern(pattern: Array[Vector2i], cx: int, cy: int) -> void:
	for pos in pattern:
		var x: int = cx + pos.x
		var y: int = cy + pos.y
		if x >= 0 and x < grid_w and y >= 0 and y < grid_h:
			grid[y * grid_w + x] = 255

# --- RENDERING ---
func upload_to_texture() -> void:
	img.set_data(grid_w, grid_h, false, Image.FORMAT_L8, grid)
	tex.update(img)

func clear_grid() -> void:
	grid.fill(0)

func _draw() -> void:
	if Engine.get_frames_per_second() > 0:
		var info: String = "Gen: %d | FPS: %d | %s" % [
			generation,
			Engine.get_frames_per_second(),
			"PAUSED" if paused else "Running"
		]
		draw_string(ThemeDB.fallback_font, Vector2(10, 20), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GREEN)
	queue_redraw()
