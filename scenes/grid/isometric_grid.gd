@tool
extends Node2D

const MovementStateMachine = preload("res://scenes/player/movement_state_machine.gd")

const TILE_WIDTH = 32
const TILE_HEIGHT = 16
const GRID_SIZE = 8
const PLAYER1_START = "H1" # Chess notation for player's starting position
@export var MOVEMENT_RANGE: int = 2 # Number of tiles the player can move at a time.

## Emitted when player completes a movement to a new grid position
## @param grid_position: Vector2 representing the grid coordinates the player moved to
signal player_moved(grid_position)

## Emitted when mouse hovers over a grid position
## @param grid_position: Vector2 representing the grid coordinates being hovered over
signal grid_mouse_hover(grid_position)

## Emitted when mouse exits the grid
signal grid_mouse_exit

## Emitted with the player's starting tile in chess notation
## @param starting_tile: String representing chess notation (e.g. "H8")
signal player_starting_tile(starting_tile)

## Emitted with the player's movement range
## @param movement_range: int representing how many tiles the player can move
signal player_movement_range(movement_range)

## Emitted when a player movement path is calculated
## @param path_tiles: Array of Vector2 representing each tile in the path including start and destination
signal player_path_calculated(path_tiles)

## Emitted when player wins a round by returning to starting position
signal round_won

var grid_tiles = []
var grid_offset = Vector2.ZERO
var player_instance = null
var debug_ui = null
var main_ui = null
var hover_grid_pos = Vector2(-1, -1) # Track which tile is being hovered
var target_grid_pos = Vector2(-1, -1) # Track the clicked target tile
var path_tiles = [] # Array of tiles in the calculated path, excluding player's current position
var explosion_created = false # Flag to prevent multiple explosions
var player_is_moving = false # Track if player is currently moving
var movement_state = null # Reference to movement state machine
var impassable_tiles = [] # Array of Vector2 positions that cannot be moved to
var grid_to_chess_friendly = true
var explosion_scene

# Reference to the player scene for runtime instances
@export var player_scene: PackedScene
# Debug mode to show grid coordinates when clicked
@export var debug_mode: bool = false
# Reference to the debug UI scene
@export var debug_ui_scene: PackedScene

# Create the grid for the game
func _create_grid():
	# Add to isometric_grid group for easy reference
	add_to_group("isometric_grid")
	
	# Calculate the offset to center the grid
	calculate_grid_offset()
	draw_grid()
	add_labels()
	queue_redraw()

# Setup the debug UI
func _setup_debug_ui():
	# Find existing debug UI in the scene tree
	debug_ui = get_tree().get_root().get_node_or_null("Main/DebugUI")
	
	if not debug_ui and debug_ui_scene:
		# Create debug UI instance if needed and add to scene
		debug_ui = debug_ui_scene.instantiate()
		get_tree().get_root().add_child(debug_ui)

# Create the player instance
func _create_player():
	# Check if we already have a player instance
	player_instance = get_node_or_null("Player1")
	
	# If we don't have a player instance and we have a player scene assigned
	if not player_instance and player_scene:
		# Instance the player scene
		player_instance = player_scene.instantiate()
		player_instance.name = "Player1"
		add_child(player_instance)
		
		# Set the player to start position
		var start_pos = chess_to_grid(PLAYER1_START)
		var screen_pos = grid_to_screen(start_pos.x, start_pos.y)
		player_instance.position = screen_pos
		
		# Also store the grid position if it has current_grid_pos property
		if "current_grid_pos" in player_instance:
			player_instance.current_grid_pos = start_pos
		
		print("Player instance created at position: ", screen_pos)
	
	if player_instance:
		# Set initial position based on PLAYER1_START chess notation
		var start_pos = chess_to_grid(PLAYER1_START)
		
		# Set position properties
		player_instance.current_grid_pos = Vector2(start_pos.x, start_pos.y)
		player_instance.position = grid_to_screen(start_pos.x, start_pos.y)
		player_instance.target_position = player_instance.position
		player_instance.should_move = false
		
		# Update debug UI with initial position
		_update_debug_info(start_pos.x, start_pos.y)
		
		# Inform the main UI about the player's starting position
		if main_ui:
			main_ui.set_player_start_position(player_instance.current_grid_pos)
		
		# Emit signal for initial player position to update fog of war
		emit_signal("player_moved", player_instance.current_grid_pos)
		
		# Inform the game manager about the initial player position
		var game_manager = get_node_or_null("/root/GameManager")
		if game_manager and game_manager.has_method("update_player_position"):
			game_manager.update_player_position(player_instance.current_grid_pos, true)
	else:
		push_error("Player1 node not found and player_scene not assigned to IsometricGrid!")
	
	# If we have a player instance, ensure we have the signal connected
	if player_instance and player_instance.has_signal("movement_completed"):
		if player_instance.is_connected("movement_completed", _on_player_movement_completed):
			player_instance.disconnect("movement_completed", _on_player_movement_completed)
		player_instance.connect("movement_completed", _on_player_movement_completed)
		print("Connected to player movement_completed signal")
		
	# Initialize movement state machine
	movement_state = MovementStateMachine.new(self)

func _ready():
	if Engine.is_editor_hint():
		set_process(false)
		return

	# Create grid
	_create_grid()
	
	# Setup debug
	_setup_debug_ui()
	
	# Create player
	_create_player()
	
	# Connect signals
	_setup_signals()
	
	# Find game manager
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		# Connect to game manager signals
		game_manager.connect("game_reset", _on_game_reset)
		game_manager.connect("round_reset", _on_next_round)
		game_manager.connect("player_died", _on_player_died)
	else:
		push_error("GameManager not found in IsometricGrid")
	
	# Emit initial player position signal to update UI
	emit_signal("player_starting_tile", PLAYER1_START)
	emit_signal("player_movement_range", MOVEMENT_RANGE)

func _enter_tree():
	# This gets called when the node enters the scene tree, including in the editor
	calculate_grid_offset()
	queue_redraw()
	update_editor_player_position()
		
func _get_configuration_warnings():
	var warnings = []
	if not player_scene:
		warnings.append("Player scene is not assigned!")
	return warnings

# Update player position in the editor
func update_editor_player_position():
	# Only run this in the editor
	if not Engine.is_editor_hint():
		return
		
	# Find the Player1 node if it exists
	player_instance = get_node_or_null("Player1")
	if player_instance:
		# Convert the PLAYER1_START position to grid coordinates
		var start_pos = chess_to_grid(PLAYER1_START)
		# Convert to screen position
		var screen_pos = grid_to_screen(start_pos.x, start_pos.y)
		# Set player position
		player_instance.position = screen_pos

func calculate_grid_offset():
	var grid_width = GRID_SIZE * TILE_WIDTH
	var grid_height = GRID_SIZE * TILE_HEIGHT / 2
	grid_offset = Vector2(-grid_width / 2, -grid_height / 2)

func draw_grid():
	# Initialize the grid tiles
	grid_tiles.clear()
	for y in range(GRID_SIZE):
		grid_tiles.append([])
		for x in range(GRID_SIZE):
			grid_tiles[y].append(Vector2(x, y))

func _process(delta):
	# Only run this code if not in the editor
	if not Engine.is_editor_hint() and movement_state:
		# Skip hover detection if player is currently moving
		if player_is_moving:
			return
		
		# If we're in MOVEMENT_COMPLETED state and player is no longer moving, go to IDLE
		if movement_state.current_state == get_movement_state_enum().MOVEMENT_COMPLETED and not player_is_moving:
			movement_state.transition_to(get_movement_state_enum().IDLE)
			
		# Update hover position
		var mouse_pos = get_global_mouse_position() - global_position
		var grid_pos = screen_to_grid(mouse_pos.x, mouse_pos.y)
		
		# Check if the mouse is within grid bounds and position changed
		if grid_pos.x >= 0 and grid_pos.x < GRID_SIZE and grid_pos.y >= 0 and grid_pos.y < GRID_SIZE:
			if grid_pos != hover_grid_pos:
				hover_grid_pos = grid_pos
				
				# Use state machine to handle hover
				var MovementState = get_movement_state_enum()
				movement_state.transition_to(MovementState.HOVER, {"hover_pos": hover_grid_pos})
				
				# Emit signal for mouse hover
				emit_signal("grid_mouse_hover", hover_grid_pos)
				
				queue_redraw() # Redraw to show hover effect
		elif hover_grid_pos != Vector2(-1, -1):
			# Mouse exited the grid
			hover_grid_pos = Vector2(-1, -1)
			
			# Use state machine to handle mouse exit
			var MovementState = get_movement_state_enum()
			movement_state.transition_to(MovementState.IDLE)
			
			# Emit signal for mouse exit
			emit_signal("grid_mouse_exit")
			
			queue_redraw()

func _draw():
	# Draw the grid lines
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos = grid_to_screen(x, y)
			# Draw diamond shape for each tile
			var points = [
				Vector2(pos.x, pos.y - TILE_HEIGHT / 2), # Top
				Vector2(pos.x + TILE_WIDTH / 2, pos.y), # Right
				Vector2(pos.x, pos.y + TILE_HEIGHT / 2), # Bottom
				Vector2(pos.x - TILE_WIDTH / 2, pos.y) # Left
			]
			
			# Get player start position for highlighting
			var start_pos = chess_to_grid(PLAYER1_START)
			var is_start_tile = Vector2(x, y) == start_pos
			
			# Check if this tile has a POI
			var has_poi = false
			var poi_system = get_node_or_null("POISystem")
			if poi_system and not Engine.is_editor_hint():
				var current_pos = Vector2(x, y)
				has_poi = current_pos in poi_system.poi_positions and not current_pos in poi_system.collected_pois
			
			# Check if this tile is impassable terrain
			var is_terrain = false
			var current_pos = Vector2(x, y)
			if not Engine.is_editor_hint():
				is_terrain = current_pos in impassable_tiles
			
			# Determine tile state (normal, hovered, target, or movement indicator)
			var is_hovered = not Engine.is_editor_hint() and Vector2(x, y) == hover_grid_pos
			var is_target = not Engine.is_editor_hint() and Vector2(x, y) == target_grid_pos
			var is_path_tile = not Engine.is_editor_hint() and Vector2(x, y) in path_tiles
			
			# Select colors based on tile state
			var fill_color
			var border_color
			
			# Check if player is immobile and this is the player's tile
			var is_player_tile = false
			if player_instance and player_instance.get("current_grid_pos") != null:
				is_player_tile = Vector2(x, y) == player_instance.current_grid_pos
			var is_immobile = movement_state and movement_state.current_state == movement_state.MovementState.IMMOBILE
			
			if is_player_tile and is_immobile:
				# Immobile state (yellow)
				fill_color = Color(1.0, 1.0, 0.0, 0.3)
				border_color = Color(1.0, 1.0, 0.0, 0.8)
			elif is_target:
				# Target tile (red)
				fill_color = Color(0.8, 0.2, 0.2, 0.3)
				border_color = Color(1.0, 0.0, 0.0, 0.8)
			elif is_path_tile:
				# Path tile (light blue)
				fill_color = Color(0.2, 0.6, 0.8, 0.4)
				border_color = Color(0.0, 0.8, 1.0, 0.8)
			elif is_terrain:
				# Terrain tile (brown)
				fill_color = Color(0.6, 0.4, 0.2, 0.3)
				border_color = Color(0.6, 0.4, 0.2, 0.8)
			elif has_poi:
				# POI tile (purple)
				fill_color = Color(0.7, 0.3, 1.0, 0.3)
				border_color = Color(0.7, 0.0, 1.0, 0.8)
			elif is_start_tile:
				# Start tile (green)
				fill_color = Color(0.2, 0.8, 0.2, 0.3)
				border_color = Color(0.0, 1.0, 0.0, 0.8)
			elif is_hovered:
				# Hover tile (white)
				fill_color = Color(0.5, 0.5, 0.5, 0.3)
				border_color = Color.WHITE
			else:
				# Normal tile
				fill_color = Color(0.2, 0.2, 0.2, 0.1)
				border_color = Color.DIM_GRAY
			
			draw_colored_polygon(points, fill_color)
			draw_polyline(points + [points[0]], border_color, 1.0)

func grid_to_screen(grid_x, grid_y):
	# Convert grid coordinates to screen coordinates
	var screen_x = (grid_x - grid_y) * TILE_WIDTH / 2
	var screen_y = (grid_x + grid_y) * TILE_HEIGHT / 2
	return Vector2(screen_x, screen_y) + grid_offset

func screen_to_grid(screen_x, screen_y):
	# Convert screen coordinates to grid coordinates (inverse of grid_to_screen)
	var local_x = screen_x - grid_offset.x
	var local_y = screen_y - grid_offset.y
	
	# Isometric transformation
	var grid_y = (local_y / (TILE_HEIGHT * 0.5) - local_x / (TILE_WIDTH * 0.5)) * 0.5
	var grid_x = (local_y / (TILE_HEIGHT * 0.5) + local_x / (TILE_WIDTH * 0.5)) * 0.5
	
	# Debug output for edge cases
	var raw_x = grid_x
	var raw_y = grid_y
	
	# Fix for edge cases near grid boundaries - check if we're close to a valid grid position
	# and use more precise detection for diamond-shaped tiles
	if (raw_x >= -0.3 and raw_x <= GRID_SIZE - 0.7) and (raw_y >= -0.3 and raw_y <= GRID_SIZE - 0.7):
		# We're close to grid boundaries - use more precise detection
		# For each nearby grid position, check if the point is within the diamond shape
		var closest_dist = INF
		var closest_pos = Vector2(-1, -1)
		
		# Check the 9 grid cells around the estimated position
		for x_offset in [-1, 0, 1]:
			for y_offset in [-1, 0, 1]:
				var test_x = floor(raw_x) + x_offset
				var test_y = floor(raw_y) + y_offset
				
				# Skip invalid grid positions
				if test_x < 0 or test_x >= GRID_SIZE or test_y < 0 or test_y >= GRID_SIZE:
					continue
				
				# Get screen coordinates for this grid position
				var test_screen = grid_to_screen(test_x, test_y)
				
				# Calculate distance to the screen position
				var dist = Vector2(screen_x, screen_y).distance_to(test_screen)
				
				# If this is closer than our previous best, update it
				if dist < closest_dist:
					closest_dist = dist
					closest_pos = Vector2(test_x, test_y)
		
		# If we found a close enough position, use it
		if closest_dist < TILE_WIDTH * 0.75 and closest_pos != Vector2(-1, -1):
			return closest_pos
	
	# Fall back to rounding if our diamond detection doesn't find anything
	return Vector2(round(grid_x), round(grid_y))

func add_labels():
	# Remove existing labels first
	for child in get_children():
		if child is Label:
			child.queue_free()
	
	# Add horizontal labels (A-H)
	for x in range(GRID_SIZE):
		var label = Label.new()
		label.text = char(65 + x) # ASCII 'A' starts at 65
		var pos = grid_to_screen(x, -1.0) # Increased offset from -0.5 to -1.0
		label.position = Vector2(pos.x - 5, pos.y - 15) # Increased vertical offset
		add_child(label)
	
	# Add vertical labels (1-8)
	for y in range(GRID_SIZE):
		var label = Label.new()
		label.text = str(y + 1)
		var pos = grid_to_screen(-1.2, y) # Increased offset from -0.5 to -1.0
		label.position = Vector2(pos.x + 5, pos.y - 15) # Increased horizontal offset
		add_child(label)

func _unhandled_input(event):
	# This handler is disabled in favor of the new _input and _handle_click methods
	pass
	# Only handle input if not in the editor
	# if Engine.is_editor_hint():
	# 	return
		
	# # Handle mouse clicks on grid
	# if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
	# 	# Skip if player is already moving
	# 	if player_is_moving:
	# 		return
			
	# 	var mouse_pos = get_global_mouse_position() - global_position
	# 	var grid_pos = screen_to_grid(mouse_pos.x, mouse_pos.y)
		
	# 	# Only handle clicks within grid bounds
	# 	if grid_pos.x >= 0 and grid_pos.x < GRID_SIZE and grid_pos.y >= 0 and grid_pos.y < GRID_SIZE:
	# 		# Get integer grid coordinates for display/lookup
	# 		var grid_x = int(grid_pos.x)
	# 		var grid_y = int(grid_pos.y)
			
	# 		if debug_mode:
	# 			print("Grid clicked at: ", grid_x, ", ", grid_y)
				
	# 		# Update target grid position
	# 		if player_instance:
	# 			# Use state machine to handle target selection
	# 			var MovementState = get_movement_state_enum()
	# 			movement_state.transition_to(MovementState.PATH_PLANNED, {"target_pos": Vector2(grid_x, grid_y)})
				
	# 			# Mark this input as handled

func setup_player():
	# Check if we already have a player instance
	player_instance = get_node_or_null("Player1")
	
	# If we don't have a player instance and we have a player scene assigned
	if not player_instance and player_scene:
		# Instance the player scene
		player_instance = player_scene.instantiate()
		player_instance.name = "Player1"
		add_child(player_instance)
		
		# Set the player to start position
		var start_pos = chess_to_grid(PLAYER1_START)
		var screen_pos = grid_to_screen(start_pos.x, start_pos.y)
		player_instance.position = screen_pos
		
		# Also store the grid position if it has current_grid_pos property
		if "current_grid_pos" in player_instance:
			player_instance.current_grid_pos = start_pos
		
		print("Player instance created at position: ", screen_pos)
	
	if player_instance:
		# Set initial position based on PLAYER1_START chess notation
		var start_pos = chess_to_grid(PLAYER1_START)
		
		# Set position properties
		player_instance.current_grid_pos = Vector2(start_pos.x, start_pos.y)
		player_instance.position = grid_to_screen(start_pos.x, start_pos.y)
		player_instance.target_position = player_instance.position
		player_instance.should_move = false
		
		# Update debug UI with initial position
		_update_debug_info(start_pos.x, start_pos.y)
		
		# Inform the main UI about the player's starting position
		if main_ui:
			main_ui.set_player_start_position(player_instance.current_grid_pos)
		
		# Emit signal for initial player position to update fog of war
		emit_signal("player_moved", player_instance.current_grid_pos)
		
		# Inform the game manager about the initial player position
		var game_manager = get_node_or_null("/root/GameManager")
		if game_manager and game_manager.has_method("update_player_position"):
			game_manager.update_player_position(player_instance.current_grid_pos, true)
	else:
		push_error("Player1 node not found and player_scene not assigned to IsometricGrid!")
	
	# If we have a player instance, ensure we have the signal connected
	if player_instance and player_instance.has_signal("movement_completed"):
		if player_instance.is_connected("movement_completed", _on_player_movement_completed):
			player_instance.disconnect("movement_completed", _on_player_movement_completed)
		player_instance.connect("movement_completed", _on_player_movement_completed)
		print("Connected to player movement_completed signal")

func setup_debug_ui():
	# Find existing debug UI in the scene tree
	debug_ui = get_tree().get_root().get_node_or_null("Main/DebugUI")
	
	if not debug_ui and debug_ui_scene:
		# Create debug UI instance if needed and add to scene
		debug_ui = debug_ui_scene.instantiate()
		get_tree().get_root().add_child(debug_ui)

func setup_main_ui():
	# Find existing main UI in the scene tree
	main_ui = get_tree().get_root().get_node_or_null("Main/MainUI")
	
	if not main_ui:
		# Try to load MainUI scene
		var main_ui_scene = load("res://scenes/ui/main_ui.tscn")
		if main_ui_scene:
			main_ui = main_ui_scene.instantiate()
			get_tree().get_root().get_node("Main").add_child(main_ui)
	
	# Connect signals - ensure only one connection exists
	if main_ui:
		# Movement confirmation signal
		if main_ui.is_connected("movement_confirmed", _on_movement_confirmed):
			main_ui.disconnect("movement_confirmed", _on_movement_confirmed)
		main_ui.connect("movement_confirmed", _on_movement_confirmed)
		
		# Inform about player's starting position
		if player_instance:
			main_ui.set_player_start_position(player_instance.current_grid_pos)

func move_player_to_grid(grid_x, grid_y):
	# Apply movement constraints if player exists
	if player_instance and player_instance is CharacterBody2D:
		var current_pos = player_instance.current_grid_pos
		var target_pos = Vector2(grid_x, grid_y)
		var new_target_pos = target_pos
		
		# First, calculate all tiles within movement range (for determining eligibility)
		var range_value = MOVEMENT_RANGE
		var eligible_tiles = []
		
		if player_instance.PLAYER_GRIDLOCKED:
			# For gridlocked movement with turns allowed, calculate all reachable tiles
			for x in range(GRID_SIZE):
				for y in range(GRID_SIZE):
					var test_pos = Vector2(x, y)
					
					# Skip the current position
					if test_pos == current_pos:
						continue
						
					# Try to find a path to this position
					var path = find_gridlocked_path(current_pos, test_pos, range_value)
					if not path.is_empty():
						eligible_tiles.append(test_pos)
		else:
			# Non-gridlocked movement (unchanged)
			for x in range(-range_value, range_value + 1):
				for y in range(-range_value, range_value + 1):
					var test_pos = Vector2(current_pos.x + x, current_pos.y + y)
					
					# Skip the current position
					if test_pos == current_pos:
						continue
						
					# Check if position is within grid bounds
					if test_pos.x < 0 or test_pos.x >= GRID_SIZE or test_pos.y < 0 or test_pos.y >= GRID_SIZE:
						continue
						
					# Calculate distance (Manhattan distance)
					var dist = abs(current_pos.x - test_pos.x) + abs(current_pos.y - test_pos.y)
					
					# Check if within range
					if dist <= range_value:
						eligible_tiles.append(test_pos)
		
		# Check if target is in eligible tiles
		if not target_pos in eligible_tiles:
			# Target is out of range or invalid, find closest valid position
			new_target_pos = current_pos # Default fallback
			
			if player_instance.PLAYER_GRIDLOCKED:
				# Try to find a partial path toward the target
				var best_path = []
				var best_distance = INF
				
				# Try two approaches:
				# 1. Move along X axis as much as possible
				var step_x = 1 if target_pos.x > current_pos.x else -1
				var max_steps_x = min(range_value, abs(target_pos.x - current_pos.x))
				var test_pos_x = Vector2(current_pos.x + step_x * max_steps_x, current_pos.y)
				
				if test_pos_x.x >= 0 and test_pos_x.x < GRID_SIZE:
					var dist_x = abs(test_pos_x.x - target_pos.x) + abs(test_pos_x.y - target_pos.y)
					if dist_x < best_distance:
						best_distance = dist_x
						best_path = [current_pos, test_pos_x]
				
				# 2. Move along Y axis as much as possible
				var step_y = 1 if target_pos.y > current_pos.y else -1
				var max_steps_y = min(range_value, abs(target_pos.y - current_pos.y))
				var test_pos_y = Vector2(current_pos.x, current_pos.y + step_y * max_steps_y)
				
				if test_pos_y.y >= 0 and test_pos_y.y < GRID_SIZE:
					var dist_y = abs(test_pos_y.x - target_pos.x) + abs(test_pos_y.y - target_pos.y)
					if dist_y < best_distance:
						best_distance = dist_y
						best_path = [current_pos, test_pos_y]
				
				# 3. Try partial path with turn
				if abs(target_pos.x - current_pos.x) > 0 and abs(target_pos.y - current_pos.y) > 0:
					# Get maximum steps we can take in each direction
					var remaining_steps = range_value
					var x_steps = min(remaining_steps, abs(target_pos.x - current_pos.x))
					remaining_steps -= x_steps
					var y_steps = min(remaining_steps, abs(target_pos.y - current_pos.y))
					
					var intermediate = Vector2(
						current_pos.x + (step_x * x_steps),
						current_pos.y
					)
					var final = Vector2(
						intermediate.x,
						intermediate.y + (step_y * y_steps)
					)
					
					if final.x >= 0 and final.x < GRID_SIZE and final.y >= 0 and final.y < GRID_SIZE:
						var dist_xy = abs(final.x - target_pos.x) + abs(final.y - target_pos.y)
						if dist_xy < best_distance:
							best_distance = dist_xy
							best_path = [current_pos, intermediate, final]
				
				# Now try the other order (Y then X)
				var remaining_steps_2 = range_value
				var y_steps_2 = min(remaining_steps_2, abs(target_pos.y - current_pos.y))
				remaining_steps_2 -= y_steps_2
				var x_steps_2 = min(remaining_steps_2, abs(target_pos.x - current_pos.x))
				
				var intermediate_2 = Vector2(
					current_pos.x,
					current_pos.y + (step_y * y_steps_2)
				)
				var final_2 = Vector2(
					intermediate_2.x + (step_x * x_steps_2),
					intermediate_2.y
				)
				
				if final_2.x >= 0 and final_2.x < GRID_SIZE and final_2.y >= 0 and final_2.y < GRID_SIZE:
					var dist_yx = abs(final_2.x - target_pos.x) + abs(final_2.y - target_pos.y)
					if dist_yx < best_distance:
						best_distance = dist_yx
						best_path = [current_pos, intermediate_2, final_2]
				
				if not best_path.is_empty():
					new_target_pos = best_path[best_path.size() - 1]
					
					# Emit signal with the best path we found
					if best_path.size() > 1:
						emit_signal("player_path_calculated", best_path)
			else:
				# For non-gridlocked movement, use existing code (unchanged)
				var direction = (target_pos - current_pos).normalized()
				var distance = abs(target_pos.x - current_pos.x) + abs(target_pos.y - current_pos.y)
				var steps = min(range_value, distance)
				
				if distance > 0:
					# Handle diagonal movement
					var step_x = (target_pos.x - current_pos.x) / distance * steps
					var step_y = (target_pos.y - current_pos.y) / distance * steps
					
					# Round to get valid grid positions
					var dest_x = int(round(current_pos.x + step_x))
					var dest_y = int(round(current_pos.y + step_y))
					
					# Ensure position is within grid bounds
					dest_x = clamp(dest_x, 0, GRID_SIZE - 1)
					dest_y = clamp(dest_y, 0, GRID_SIZE - 1)
					
					# Check that we didn't exceed the movement range
					var test_pos = Vector2(dest_x, dest_y)
					var test_dist = abs(current_pos.x - test_pos.x) + abs(current_pos.y - test_pos.y)
					
					if test_dist <= range_value:
						new_target_pos = test_pos
		else:
			# Target is within eligible range
			new_target_pos = target_pos
		
		# Update path visualization
		if player_instance.PLAYER_GRIDLOCKED:
			var path = find_gridlocked_path(current_pos, new_target_pos, range_value)
			if path.size() > 1:
				update_path_visualization(path)
				
				# Emit signal with calculated path
				emit_signal("player_path_calculated", path)
		else:
			# For non-gridlocked movement, at least show the target position
			path_tiles = [new_target_pos]
			queue_redraw()
		
		# Get the screen position for the target
		var target_screen_pos = grid_to_screen(new_target_pos.x, new_target_pos.y)
		
		# Update the target grid position for reference
		target_grid_pos = new_target_pos
		
		# Display target selection
		queue_redraw()
		
		# Update grid_x and grid_y to the new target position
		grid_x = int(new_target_pos.x)
		grid_y = int(new_target_pos.y)
	
	# Convert grid position to chess notation for display
	var grid_name = char(65 + int(grid_x)) + str(int(grid_y) + 1)
	
	# If confirmation is required, show the confirmation dialog
	if player_instance and player_instance.MOVEMENT_CONFIRM and main_ui:
		main_ui.request_move_confirmation(
			player_instance.current_grid_pos,
			Vector2(grid_x, grid_y),
			grid_name
		)
		# Store target for later use
		target_grid_pos = Vector2(grid_x, grid_y)
		return
	
	# If no confirmation needed, move player immediately
	execute_player_move(grid_x, grid_y)

# Execute the actual player movement
func execute_player_move(grid_x, grid_y):
	# Validate grid coordinates
	if grid_x < 0 or grid_x >= GRID_SIZE or grid_y < 0 or grid_y >= GRID_SIZE:
		print("ERROR: Attempted to move player to invalid grid position: ", grid_x, ", ", grid_y)
		return
		
	if not player_instance:
		print("ERROR: No player instance found when trying to execute move")
		return
	
	print("Executing player move to grid: ", grid_x, ", ", grid_y)
	
	# Store the target grid position for later
	target_grid_pos = Vector2(grid_x, grid_y)
	
	# Convert grid coordinates to screen coordinates
	var target_pos = grid_to_screen(grid_x, grid_y)
	print("Target screen position: ", target_pos)
	
	# Update debug UI with movement information
	_update_debug_info(grid_x, grid_y)
	
	# If the player is a CharacterBody2D, set up its movement
	if player_instance is CharacterBody2D:
		print("Setting up CharacterBody2D movement")
		
		# Find the path from current position to target
		var current_pos = player_instance.current_grid_pos
		var target_grid_pos = Vector2(grid_x, grid_y)
		var grid_path = []
		
		if player_instance.PLAYER_GRIDLOCKED:
			# Use our gridlocked pathfinding
			grid_path = find_gridlocked_path(current_pos, target_grid_pos, MOVEMENT_RANGE)
			
			# Emit signal with calculated path
			if not grid_path.is_empty():
				emit_signal("player_path_calculated", grid_path)
		else:
			# For non-gridlocked movement, just use start and end points
			grid_path = [current_pos, target_grid_pos]
		
		# Convert grid path to screen coordinates
		var screen_path = []
		for point in grid_path:
			screen_path.append(grid_to_screen(point.x, point.y))
		
		# Set the movement path for the player
		if player_instance.has_method("set_movement_path"):
			player_instance.set_movement_path(screen_path)
		
		# Set the target position and activate movement
		player_instance.target_position = target_pos
		player_instance.should_move = true
		player_is_moving = true # Mark player as moving
		
		# Connect to the movement_completed signal if it exists and if not already connected
		if player_instance.has_signal("movement_completed"):
			print("Player has movement_completed signal")
			if not player_instance.is_connected("movement_completed", _on_player_movement_completed):
				print("Connecting to movement_completed signal")
				player_instance.connect("movement_completed", _on_player_movement_completed)
		else:
			print("ERROR: Player does not have movement_completed signal")
	else:
		print("Player is not a CharacterBody2D, using fallback movement")
		# Fallback for non-CharacterBody2D players
		player_instance.position = target_pos
		# Clear target highlight since we moved instantly
		target_grid_pos = Vector2(-1, -1)
		queue_redraw()

# Handle movement confirmation from UI
func _on_movement_confirmed(confirmed):
	print("Movement confirmation received: ", confirmed) # Debug output
	
	if movement_state:
		movement_state.handle_movement_confirmation(confirmed)
	else:
		print("ERROR: Movement state machine not initialized")

# Set movement state from external systems (like challenge mode)
func set_movement_state(state_name: String):
	if not movement_state:
		print("ERROR: Movement state machine not initialized")
		return
		
	# Get the movement state enum
	var MovementState = get_movement_state_enum()
	
	# Convert string state name to enum value
	match state_name.to_upper():
		"IDLE":
			movement_state.transition_to(MovementState.IDLE)
			print("Movement state changed to IDLE")
		"HOVER":
			movement_state.transition_to(MovementState.HOVER)
			print("Movement state changed to HOVER")
		"PATH_PLANNED":
			movement_state.transition_to(MovementState.PATH_PLANNED)
			print("Movement state changed to PATH_PLANNED")
		"MOVEMENT_EXECUTING":
			movement_state.transition_to(MovementState.MOVEMENT_EXECUTING)
			print("Movement state changed to MOVEMENT_EXECUTING")
		"MOVEMENT_COMPLETED":
			movement_state.transition_to(MovementState.MOVEMENT_COMPLETED)
			print("Movement state changed to MOVEMENT_COMPLETED")
		"IMMOBILE":
			movement_state.transition_to(MovementState.IMMOBILE)
			print("Movement state changed to IMMOBILE")
		_:
			print("ERROR: Unknown movement state: ", state_name)

# Handle player movement completion
func _on_player_movement_completed():
	player_is_moving = false
	
	# Update the player's current_grid_pos based on its actual position
	if player_instance:
		var screen_pos = player_instance.position
		var updated_grid_pos = screen_to_grid(screen_pos.x, screen_pos.y)
		player_instance.current_grid_pos = updated_grid_pos
		
		# Update the movement state machine's start position
		if movement_state:
			movement_state.start_position = updated_grid_pos
	
	# Get player position
	var player_pos = player_instance.current_grid_pos
	
	# Emit the player_moved signal to notify other systems
	print("signal: player_moved | position: ", player_pos)
	emit_signal("player_moved", player_pos)
	
	# Check for win condition - player returned to start after moving away
	# Get player start position from the grid's own record
	var start_pos = chess_to_grid(PLAYER1_START)
	# Check if player has moved away from start (tracked in movement state)
	var has_moved_away = movement_state and movement_state.has_moved_from_start
	
	if player_pos == start_pos and has_moved_away:
		print("Win condition met in grid: Player returned to starting position!")
		emit_signal("round_won")
	
	# Decrement turns in main_ui (but don't let it check for win condition)
	if main_ui and main_ui.has_method("consume_turn_no_win_check"):
		var turns_remaining = main_ui.consume_turn_no_win_check(player_pos)
		if not turns_remaining:
			return # Game over or round won
	elif main_ui and main_ui.has_method("consume_turn"):
		# Fallback to old method if we haven't updated main_ui yet
		var turns_remaining = main_ui.consume_turn(player_pos)
		if not turns_remaining:
			return # Game over or round won
	
	# Attempt to reveal fog of war at new position
	reveal_fog_at_position(player_pos)
	
	# Check for POI at this position
	check_for_poi(player_pos)
	
	# Check for terrain at this position
	check_for_terrain_effect(player_pos)

# Handle game over event
func _on_player_died():
	# Disable input when player dies
	set_process_input(false)
	print("Player died signal received")
	
	# Make player explode
	if player_instance and not explosion_created:
		_explode_player()

# Create a simple explosion effect at the player's position
func _explode_player():
	if not player_instance:
		return
	
	print("Player exploded!")
	explosion_created = true
	
	# Hide the player sprite
	player_instance.visible = false
	
	# Create explosion particles
	var explosion = CPUParticles2D.new()
	add_child(explosion)
	
	# Set position to player position
	explosion.position = player_instance.position
	
	# Configure particle properties
	explosion.emitting = true
	explosion.amount = 50
	explosion.lifetime = 0.5
	explosion.explosiveness = 0.9
	explosion.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	explosion.spread = 180
	explosion.gravity = Vector2(0, 98)
	explosion.initial_velocity_min = 50
	explosion.initial_velocity_max = 150
	explosion.scale_amount_min = 2.0
	explosion.scale_amount_max = 4.0
	explosion.color = Color("ff004d")
	
	# Set a timer to queue_free the particles after they're done
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 1.5
	timer.one_shot = true
	timer.timeout.connect(func(): explosion.queue_free(); timer.queue_free())
	timer.start()

# Handle game reset
func _on_game_reset():
	# Reset the player position
	var start_pos = chess_to_grid(PLAYER1_START)
	
	# Find game manager once for this method
	var game_manager = get_node_or_null("/root/GameManager")
	
	# Make sure player is visible
	if player_instance:
		player_instance.visible = true
		player_instance.position = grid_to_screen(start_pos.x, start_pos.y)
		player_instance.current_grid_pos = start_pos
		player_instance.target_position = player_instance.position
		player_instance.should_move = false
		
		# Only reset explosion flag if game wasn't recently ended (prevents double explosion)
		if game_manager and not game_manager.is_game_ending:
			explosion_created = false
		
		player_is_moving = false
	
	# Reinitialize movement state machine
	if movement_state:
		movement_state.reset() # Use our new reset method
	else:
		# If movement state machine doesn't exist, create it
		movement_state = MovementStateMachine.new(self)
	
	# Clear any path
	path_tiles.clear()
	target_grid_pos = Vector2(-1, -1)
	
	# Reset impassable tiles
	impassable_tiles.clear()
	
	# Regenerate terrain
	var terrain_system = get_node_or_null("TerrainSystem")
	if terrain_system and terrain_system.has_method("initialize_terrain_system"):
		terrain_system.initialize_terrain_system()
	
	# Regenerate POIs
	var poi_system = get_node_or_null("POISystem")
	if poi_system and poi_system.has_method("initialize_poi_system"):
		poi_system.initialize_poi_system()
	
	# Reset fog of war
	var fog_system = get_node_or_null("FogOfWar")
	if fog_system and fog_system.has_method("reset_fog"):
		fog_system.reset_fog()
		# Reveal starting area
		if fog_system.has_method("reveal_area_around"):
			fog_system.reveal_area_around(start_pos, 1)
	
	# Re-enable input processing
	set_process_input(true)
	
	queue_redraw()
	
	# Emit signal for initial player position to update fog of war
	emit_signal("player_moved", player_instance.current_grid_pos)
	
	# Inform the game manager about the reset player position
	if game_manager and game_manager.has_method("update_player_position"):
		game_manager.update_player_position(player_instance.current_grid_pos, true)

# Handle next round (new map)
func _on_next_round():
	# Reset the player position
	var start_pos = chess_to_grid(PLAYER1_START)
	# Directly set position and grid position properties instead of calling a non-existent method
	var screen_pos = grid_to_screen(start_pos.x, start_pos.y)
	player_instance.position = screen_pos
	player_instance.current_grid_pos = start_pos
	player_instance.target_position = screen_pos
	player_instance.should_move = false
	
	# Update movement state machine
	if movement_state:
		movement_state.start_position = start_pos
		# Explicitly transition back to IDLE state to ensure movement works again
		movement_state.transition_to(movement_state.MovementState.IDLE)
	
	# Clear any path
	path_tiles.clear()
	target_grid_pos = Vector2(-1, -1)
	
	# Reset impassable tiles
	impassable_tiles.clear()
	
	# Regenerate terrain
	var terrain_system = get_node_or_null("TerrainSystem")
	if terrain_system and terrain_system.has_method("generate_terrain"):
		terrain_system.generate_terrain()
	
	# Regenerate POIs
	var poi_system = get_node_or_null("POISystem")
	if poi_system and poi_system.has_method("initialize_poi_system"):
		poi_system.initialize_poi_system()
	
	# Reset fog of war
	var fog_system = get_node_or_null("FogOfWar")
	if fog_system and fog_system.has_method("reset_fog"):
		fog_system.reset_fog()
		# Reveal starting area
		if fog_system.has_method("reveal_area_around"):
			fog_system.reveal_area_around(start_pos, 1)
	
	# Redraw
	queue_redraw()
	
	# Emit signal for initial player position to update fog of war
	emit_signal("player_moved", player_instance.current_grid_pos)
	
	# Update game manager with player position
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("update_player_position"):
		game_manager.update_player_position(player_instance.current_grid_pos, true)

# Convert chess notation (e.g., "A1", "E5") to grid coordinates
func chess_to_grid(chess_pos: String) -> Vector2:
	if chess_pos.length() != 2:
		push_error("Invalid chess position format: " + chess_pos)
		return Vector2(GRID_SIZE / 2, GRID_SIZE / 2) # Default to center if invalid
	
	# Convert letter (A-H) to x-coordinate (0-7)
	var x = chess_pos.unicode_at(0) - "A".unicode_at(0)
	
	# Convert number (1-8) to y-coordinate (0-7)
	var y = int(chess_pos[1]) - 1
	
	# Validate grid coordinates
	if x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE:
		push_error("Chess position out of bounds: " + chess_pos)
		return Vector2(GRID_SIZE / 2, GRID_SIZE / 2) # Default to center if out of bounds
	
	return Vector2(x, y)

# Editor helper method to return a reference to this grid
static func get_editor_grid():
	var editor_interface = Engine.get_singleton("EditorInterface")
	if editor_interface:
		var scene_root = editor_interface.get_edited_scene_root()
		if scene_root:
			return scene_root.find_child("IsometricGrid", true, false)
	return null

# Snap a sprite to the nearest grid tile
func snap_sprite_to_grid(sprite: Node2D) -> void:
	if not sprite:
		push_error("Cannot snap null sprite to grid")
		return
	
	# Get the sprite's position relative to the grid
	var sprite_pos = sprite.global_position - global_position
	
	# Convert to grid coordinates (nearest grid cell)
	var grid_pos = screen_to_grid(sprite_pos.x, sprite_pos.y)
	
	# Clamp to grid boundaries
	grid_pos.x = clamp(grid_pos.x, 0, GRID_SIZE - 1)
	grid_pos.y = clamp(grid_pos.y, 0, GRID_SIZE - 1)
	
	# Convert back to screen coordinates
	var snapped_pos = grid_to_screen(grid_pos.x, grid_pos.y)
	
	# Set the sprite's position
	sprite.global_position = global_position + snapped_pos
	
	if debug_mode:
		print("Snapped sprite to grid position: ", grid_pos)
		print("Screen position: ", snapped_pos)
	
	return

# Helper function to add a sprite to a specific grid position
func add_sprite_to_grid(sprite: Node2D, grid_x: int, grid_y: int) -> void:
	if not sprite:
		push_error("Cannot add null sprite to grid")
		return
	
	# Clamp to grid boundaries
	grid_x = clamp(grid_x, 0, GRID_SIZE - 1)
	grid_y = clamp(grid_y, 0, GRID_SIZE - 1)
	
	# Convert to screen coordinates
	var screen_pos = grid_to_screen(grid_x, grid_y)
	
	# Set the sprite's position
	sprite.global_position = global_position + screen_pos
	
	if debug_mode:
		print("Added sprite to grid position: ", Vector2(grid_x, grid_y))
		print("Screen position: ", screen_pos)
	
	return

# Find a valid path from start_pos to target_pos, respecting the gridlocked constraint
# Returns an array of points representing the path including the start and target
func find_gridlocked_path(start_pos: Vector2, target_pos: Vector2, max_steps: int) -> Array:
	# If start and target are the same, return just the start position
	if start_pos == target_pos:
		return [start_pos]
	
	# If target is impassable terrain, return empty array
	# if target_pos in impassable_tiles:
	# 	print("Target position is impassable terrain")
	# 	return []
	
	# If target is out of range, return empty array
	var manhattan_dist = abs(start_pos.x - target_pos.x) + abs(start_pos.y - target_pos.y)
	if manhattan_dist > max_steps:
		# Debug: Show when a tile is too far away
		var target_name = char(65 + int(target_pos.x)) + str(int(target_pos.y) + 1)
		# print("Target " + target_name + " is beyond movement range (distance = " + str(manhattan_dist) + ", max_steps = " + str(max_steps) + ")")
		return []
	
	# If target is directly reachable by moving along X or Y axis, calculate all intermediate points
	if start_pos.x == target_pos.x or start_pos.y == target_pos.y:
		var path = [start_pos]
		var direction = Vector2(
			sign(target_pos.x - start_pos.x),
			sign(target_pos.y - start_pos.y)
		)
		
		var current = start_pos
		var path_blocked = false
		
		while current != target_pos:
			var next_pos = current + direction
			
			# Check if the next position is impassable
			if next_pos in impassable_tiles:
				print("Straight line path blocked by terrain at ", next_pos)
				path_blocked = true
				break
				
			current = next_pos
			path.append(current)
			
			# Safety check to prevent infinite loops
			if path.size() > max_steps + 1:
				print("Safety limit reached in straight line path")
				break
		
		if path_blocked:
			return [] # Path is blocked, return empty array
		return path
	
	# For diagonal movement (where we need to make a turn)
	# Create multiple possible paths and pick the best one
	var possible_paths = []
	
	# Option 1: Move horizontally first, then vertically
	var path1 = [start_pos]
	var remaining_steps = max_steps
	var dx = target_pos.x - start_pos.x
	var dy = target_pos.y - start_pos.y
	var dir_x = sign(dx)
	var dir_y = sign(dy)
	
	# Add as many horizontal steps as we can (up to the x-distance or remaining steps)
	var current = start_pos
	var steps_taken = 0
	var path1_blocked = false
	
	while steps_taken < min(abs(dx), remaining_steps):
		var next_pos = Vector2(current.x + dir_x, current.y)
		
		# Check if the next position is impassable
		if next_pos in impassable_tiles:
			path1_blocked = true
			break
			
		current = next_pos
		path1.append(current)
		steps_taken += 1
		remaining_steps -= 1
	
	# Add remaining vertical steps if path isn't blocked
	if not path1_blocked:
		while current != target_pos and remaining_steps > 0:
			var next_pos = Vector2(current.x, current.y + dir_y)
			
			# Check if the next position is impassable
			if next_pos in impassable_tiles:
				path1_blocked = true
				break
				
			current = next_pos
			path1.append(current)
			remaining_steps -= 1
	
	# Only add this path if it reaches the target and isn't blocked
	if current == target_pos and not path1_blocked:
		possible_paths.append(path1)
	
	# Option 2: Move vertically first, then horizontally
	var path2 = [start_pos]
	remaining_steps = max_steps
	
	# Reset for second path
	current = start_pos
	steps_taken = 0
	var path2_blocked = false
	
	# Add as many vertical steps as we can
	while steps_taken < min(abs(dy), remaining_steps):
		var next_pos = Vector2(current.x, current.y + dir_y)
		
		# Check if the next position is impassable
		if next_pos in impassable_tiles:
			path2_blocked = true
			break
			
		current = next_pos
		path2.append(current)
		steps_taken += 1
		remaining_steps -= 1
	
	# Add remaining horizontal steps if path isn't blocked
	if not path2_blocked:
		while current != target_pos and remaining_steps > 0:
			var next_pos = Vector2(current.x + dir_x, current.y)
			
			# Check if the next position is impassable
			if next_pos in impassable_tiles:
				path2_blocked = true
				break
				
			current = next_pos
			path2.append(current)
			remaining_steps -= 1
	
	# Only add this path if it reaches the target and isn't blocked
	if current == target_pos and not path2_blocked:
		possible_paths.append(path2)
	
	# If we have any valid paths, return the one that gets closest to the target
	if possible_paths.size() > 0:
		var best_path = []
		var best_distance = INF
		
		for path in possible_paths:
			var end_point = path[path.size() - 1]
			var distance = abs(end_point.x - target_pos.x) + abs(end_point.y - target_pos.y)
			
			if distance < best_distance:
				best_distance = distance
				best_path = path
			elif distance == best_distance and path.size() < best_path.size():
				# If same distance, prefer shorter path
				best_path = path
		
		# If this is the exact path to the target, return it
		if best_distance == 0:
			return best_path
		
		# Check if the target is directly reachable from the last point and we still have steps left
		var last_point = best_path[best_path.size() - 1]
		var steps_to_target = abs(last_point.x - target_pos.x) + abs(last_point.y - target_pos.y)
		var total_steps = best_path.size() - 1 + steps_to_target
		
		if total_steps <= max_steps:
			# We can reach the target exactly, let's add the remaining steps
			if last_point.x != target_pos.x:
				# Move horizontally to reach the target's x
				var x_dir = sign(target_pos.x - last_point.x)
				var x_steps = abs(target_pos.x - last_point.x)
				
				for i in range(x_steps):
					best_path.append(Vector2(last_point.x + x_dir * (i + 1), last_point.y))
				
				last_point = best_path[best_path.size() - 1]
			
			if last_point.y != target_pos.y:
				# Move vertically to reach the target's y
				var y_dir = sign(target_pos.y - last_point.y)
				var y_steps = abs(target_pos.y - last_point.y)
				
				for i in range(y_steps):
					best_path.append(Vector2(last_point.x, last_point.y + y_dir * (i + 1)))
			
			return best_path
		
		# If we can't reach the target exactly, return the best partial path
		return best_path
	
	# If no valid paths, return an empty array
	return []

# Calculate the tile where the player would move to if clicked
func update_movement_indicator():
	if not player_instance or hover_grid_pos == Vector2(-1, -1):
		path_tiles.clear()
		return
		
	var current_pos = player_instance.current_grid_pos
	var target_pos = hover_grid_pos
	
	# Clear previous path tiles
	path_tiles.clear()
	
	# Only handle gridlocked movement - ignore non-gridlocked as per request
	if player_instance.PLAYER_GRIDLOCKED:
		# Calculate the path using the SAME function that will be used for actual movement
		# This ensures what we preview matches what will happen on click
		var path = find_gridlocked_path(current_pos, target_pos, MOVEMENT_RANGE)
		
		if not path.is_empty() and path.size() > 1:
			# Skip the first point which is the current position
			for i in range(1, path.size()):
				path_tiles.append(path[i])
			
			# Emit signal with calculated path
			emit_signal("player_path_calculated", path)
			
			# Update debug UI with path information
			_update_path_debug_info(path)
		else:
			# No valid path found
			_update_path_debug_info([])
	else:
		# Non-gridlocked movement - simplified
		path_tiles = [target_pos]
		
		# Still update debug UI
		_update_path_debug_info([target_pos])

# Shows the highlight for the target tile
func show_target_highlight(pos: Vector2):
	target_grid_pos = pos
	queue_redraw()

# Clears the movement range tiles
func clear_movement_range():
	path_tiles.clear()
	
	# Clear the path text in the debug UI
	_update_path_debug_info([])
	
	queue_redraw()

# Clears the target highlight
func clear_target_highlight():
	target_grid_pos = Vector2(-1, -1)
	queue_redraw()

# Get the current grid position of the player
func get_player_grid_pos() -> Vector2:
	if player_instance and player_instance.has_method("get_current_grid_pos"):
		return player_instance.get_current_grid_pos()
	return Vector2(-1, -1)

# Add this function to test emitting the signal manually
func test_emit_player_moved():
	if player_instance:
		var grid_pos = screen_to_grid(player_instance.position.x, player_instance.position.y)
		print("Manually emitting player_moved signal with position: ", grid_pos)
		emit_signal("player_moved", grid_pos)
		print("Signal emitted!")

# Modify the existing emit_signal calls to include debug prints
func handle_movement_completion():
	# Update player movement state
	player_is_moving = false
	
	if player_instance:
		# Get player's current grid position
		var player_pos = player_instance.current_grid_pos
		
		# Debug output
		print("Player movement completed, emitting player_moved signal with position: ", player_pos)
		
		# Emit the signal
		emit_signal("player_moved", player_pos)
		
		# Notify the debug UI
		_update_player_debug_info()
		
		# Attempt to reveal fog of war at new position
		reveal_fog_at_position(player_pos)
		
		# Check for POI at this position
		check_for_poi(player_pos)
		
		# Check for terrain at this position
		check_for_terrain_effect(player_pos)
		
		print("player_moved signal emitted")

# Test the POI system directly
func test_poi_system():
	var poi_system = get_node_or_null("POISystem")
	if poi_system:
		print("Found POI system, testing collection...")
		if poi_system.has_method("debug_collect_all_pois"):
			poi_system.debug_collect_all_pois()
		else:
			print("POI system doesn't have debug_collect_all_pois method")
	else:
		print("POI system not found!")

## Centralized function to manage all signal connections
func _setup_signals():
	# Connect to player moved signal for updates
	player_instance.connect("move_requested", _on_player_move_requested)
	
	# Find MainUI
	main_ui = find_main_ui()
	if main_ui:
		# Connect to movement confirmation
		main_ui.connect("movement_confirmed", _on_movement_confirmed)
	else:
		push_error("Unable to find MainUI - please check scene structure!")
	
	# Connect POI system signals
	var poi_system = get_node_or_null("POISystem")
	if poi_system and poi_system.has_signal("poi_collected"):
		# Connect POI collected signal to money handler
		if not poi_system.is_connected("poi_collected", _on_poi_collected):
			poi_system.connect("poi_collected", _on_poi_collected)
			print("Connected POI system signals")
	
	# Create and connect explosion scene
	explosion_scene = load("res://scenes/player/explosion.tscn")

# Handle POI collection rewards
func _on_poi_collected(reward):
	print("POI collected with reward: ", reward)
	# Forward the reward to the main UI to update money
	if main_ui and main_ui.has_method("add_money"):
		main_ui.add_money(reward)
		print("Added money to player: ", reward)

# Check if a path is valid (all points within grid and total steps <= max_steps)
func is_valid_path(path: Array, max_steps: int) -> bool:
	if path.size() < 2:
		return false
	
	# Check if all points are within grid bounds
	for point in path:
		if point.x < 0 or point.x >= GRID_SIZE or point.y < 0 or point.y >= GRID_SIZE:
			# Debug: show which point is out of bounds
			print("Point " + str(point) + " is out of grid bounds")
			return false
	
	# Calculate total path distance
	var total_dist = 0
	for i in range(1, path.size()):
		total_dist += abs(path[i - 1].x - path[i].x) + abs(path[i - 1].y - path[i].y)
	
	# Check if total distance is within movement range
	var valid = total_dist <= max_steps
	if !valid:
		print("Path total distance " + str(total_dist) + " exceeds max steps " + str(max_steps))
	
	return valid

# Updates the path visualization based on the provided path
func update_path_visualization(path: Array):
	path_tiles.clear()
	
	# Skip the first point (current position) for visualization
	if path.size() > 1:
		for i in range(1, path.size()):
			path_tiles.append(path[i])
		
		# Update debug UI with path information
		_update_path_debug_info(path)
	
	queue_redraw()

# Get grid name in chess notation for a given position
func get_grid_name(grid_pos: Vector2) -> String:
	return char(65 + int(grid_pos.x)) + str(int(grid_pos.y) + 1)

# Helper function to get the MovementState enum
func get_movement_state_enum():
	if movement_state:
		return movement_state.MovementState
	return null

func update_movement_start_position():
	if movement_state and player_instance:
		movement_state.start_position = player_instance.current_grid_pos

## Sets tiles that are impassable (cannot be moved to)
## @param positions: Array of Vector2 coordinates that should be marked as impassable
func set_impassable_tiles(positions: Array) -> void:
	impassable_tiles = positions.duplicate()
	print("Set impassable tiles at positions: ", impassable_tiles)
	queue_redraw()

## Checks if a grid position is valid for movement
## @param grid_pos: Vector2 grid position to check
## @return bool: True if position is valid for movement
func is_valid_move_position(grid_pos: Vector2) -> bool:
	# Check if position is within grid bounds
	if grid_pos.x < 0 or grid_pos.x >= GRID_SIZE or grid_pos.y < 0 or grid_pos.y >= GRID_SIZE:
		return false
		
	# Check if position is an impassable terrain tile
	for pos in impassable_tiles:
		if Vector2(int(pos.x), int(pos.y)) == Vector2(int(grid_pos.x), int(grid_pos.y)):
			return false
			
	return true

# Handles mouse click on grid
func _input(event):
	if Engine.is_editor_hint():
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position() - global_position
		var grid_pos = screen_to_grid(mouse_pos.x, mouse_pos.y)
		
		# Only process click if it's within the grid
		if grid_pos.x >= 0 and grid_pos.x < GRID_SIZE and grid_pos.y >= 0 and grid_pos.y < GRID_SIZE:
			# Use state machine to handle click
			_handle_click(grid_pos)
			get_viewport().set_input_as_handled()

# Handle click based on current movement state
func _handle_click(grid_pos):
	if not movement_state or not player_instance:
		print("Warning: No movement state machine or player instance available.")
		return
		
	# Get current state
	var current_state = movement_state.current_state
	var MovementState = get_movement_state_enum()
	
	# Handle click based on current state
	match current_state:
		MovementState.IDLE, MovementState.HOVER:
			# Plan path to clicked tile
			movement_state.transition_to(MovementState.PATH_PLANNED, {"target_pos": grid_pos})
			
		MovementState.PATH_PLANNED:
			# If clicking same tile, execute movement
			if grid_pos == movement_state.target_position:
				movement_state.transition_to(MovementState.MOVEMENT_EXECUTING)
			else:
				# Plan new path to different tile
				movement_state.transition_to(MovementState.PATH_PLANNED, {"target_pos": grid_pos})
				
		MovementState.MOVEMENT_EXECUTING, MovementState.MOVEMENT_COMPLETED:
			# Ignore clicks during movement
			pass
			
		MovementState.IMMOBILE:
			# Ignore clicks while immobile
			pass

# Find the MainUI node in the scene
func find_main_ui():
	# First, try to find it in the Main scene
	var main_scene = get_tree().root.get_node_or_null("Main")
	if main_scene:
		var ui = main_scene.get_node_or_null("MainUI")
		if ui:
			return ui
	
	# Try to find directly in the scene tree
	var main_ui = get_tree().get_nodes_in_group("main_ui")
	if main_ui.size() > 0:
		return main_ui[0]
		
	# Try to load MainUI scene
	var main_ui_scene = load("res://scenes/ui/main_ui.tscn")
	if main_ui_scene:
		var ui_instance = main_ui_scene.instantiate()
		get_tree().root.add_child(ui_instance)
		return ui_instance
	
	return null

# Handle player movement request
func _on_player_move_requested(target_position):
	# This is used to connect to the player's move_requested signal
	# Implementation will depend on the specific movement logic
	pass

# Reveal fog around player position
func reveal_fog_at_position(pos):
	var fog_system = get_node_or_null("FogOfWar")
	if fog_system and fog_system.has_method("reveal_area_around"):
		fog_system.reveal_area_around(pos, 1) # Reveal 1 tile radius

# Check for POI at player position
func check_for_poi(pos):
	var poi_system = get_node_or_null("POISystem")
	if poi_system and poi_system.has_method("check_position"):
		poi_system.check_position(pos)

# Check for terrain effects at player position
func check_for_terrain_effect(pos):
	var terrain_system = get_node_or_null("TerrainSystem")
	if terrain_system and terrain_system.has_method("apply_terrain_effect"):
		terrain_system.apply_terrain_effect(pos)

# Convert grid coordinates to chess notation (e.g., "A1", "E5")
func grid_to_chess(grid_x, grid_y) -> String:
	# Convert x-coordinate (0-7) to letter (A-H)
	var letter = char(65 + grid_x)
	
	# Convert y-coordinate (0-7) to number (1-8)
	var number = grid_y + 1
	
	return letter + str(number)

func _update_debug_info(grid_x, grid_y):
	if debug_ui and debug_ui.has_method("update_debug_text"):
		var grid_name = char(65 + grid_x) + str(grid_y + 1)
		var target_pos = grid_to_screen(grid_x, grid_y)
		debug_ui.update_debug_text(grid_name, Vector2(grid_x, grid_y), target_pos)

func _update_player_debug_info():
	if debug_ui and debug_ui.has_method("update_debug_text") and player_instance:
		var player_pos = player_instance.current_grid_pos
		var chess_notation = char(65 + int(player_pos.x)) + str(int(player_pos.y) + 1)
		debug_ui.update_debug_text(chess_notation, player_pos, player_instance.position)

func _update_path_debug_info(path: Array):
	if debug_ui and debug_ui.has_method("update_path_text"):
		var path_info = "Path: "
		for i in range(path.size()):
			var pos = path[i]
			var tile_name = get_grid_name(pos)
			path_info += tile_name
			if i < path.size() - 1:
				path_info += " → "
		debug_ui.update_path_text(path_info)
