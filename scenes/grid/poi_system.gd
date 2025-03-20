extends Node2D

## Emitted when a player collects a POI
## @param amount: The reward value of the collected POI
signal poi_collected(amount)

## Emitted when POIs have been generated on the map
signal pois_generated(success)

const MIN_REWARD = 10
const MAX_REWARD = 100
const POI_COUNT = 3
const POI_COLOR = Color(0.7, 0.3, 1.0, 0.7) # Purple color with some transparency

# Minimum distance between POIs in grid units
@export var min_poi_distance: int = 3

# Define polygon shapes
var SHAPES = {}
# Define colors for each shape
var SHAPE_COLORS = {
	"square": Color(0, 0.8, 0, 0.7), # green
	"gem": Color(0.0627451, 0.105882, 1, 0.7), # blue
	"triangle": Color(1, 0.8, 0, 0.7), # yellow
	"diamond": Color(0.0627451, 0.105882, 1, 0.7) # blue
}

var grid = null
var poi_positions = [] # Array of Vector2 positions where POIs are located
var poi_sprites = {} # Dictionary of POI sprites indexed by position
var collected_pois = [] # Array of positions where POIs have been collected
var available_shapes = [] # Shapes that haven't been used yet
var player_start_position = null # Store the player's starting position

func _ready():
	# Don't run in editor
	if Engine.is_editor_hint():
		return
	
	# Define shapes
	SHAPES = {
		"square": PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]),
		"diamond": PackedVector2Array([Vector2(0, -8), Vector2(8, 0), Vector2(0, 8), Vector2(-8, 0)]),
		"triangle": PackedVector2Array([Vector2(-8, 8), Vector2(8, 8), Vector2(0, -8)]),
		"gem": PackedVector2Array([Vector2(0, 0), Vector2(8, -16), Vector2(0, -24), Vector2(-8, -16)])
	}
		
	# Get parent grid reference
	grid = get_parent()
	print("POI system initialized with grid: ", grid)
	
	if not grid or not grid.has_method("grid_to_screen"):
		push_error("POISystem must be a child of IsometricGrid!")
		return
	
	# Set up signals
	_setup_signals()
	
	# Wait one frame to ensure everything is properly set up
	await get_tree().process_frame
	
	# Fallback initialization if we don't receive player_starting_tile signal
	# Wait a short time to see if we get the signal
	await get_tree().create_timer(0.5).timeout
	
	# If we still don't have a player start position, use a fallback
	if player_start_position == null:
		print("WARNING: No player_starting_tile signal received after timeout, using fallback")
		
		# First try to get player's starting position from the grid's chess notation
		if grid.has_method("chess_to_grid") and "PLAYER1_START" in grid:
			player_start_position = grid.chess_to_grid(grid.PLAYER1_START)
			print("Using chess_to_grid for player start position: ", grid.PLAYER1_START, " -> ", player_start_position)
		elif grid.has_method("get_player_grid_pos"):
			player_start_position = grid.get_player_grid_pos()
			print("Using get_player_grid_pos fallback: ", player_start_position)
		elif grid.player_instance and grid.player_instance.has_method("get_current_grid_pos"):
			player_start_position = grid.player_instance.get_current_grid_pos()
			print("Using player_instance.get_current_grid_pos fallback: ", player_start_position)
		elif grid.player_instance:
			player_start_position = grid.player_instance.current_grid_pos
			print("Using player_instance.current_grid_pos fallback: ", player_start_position)
		else:
			# Last resort: use a center position
			player_start_position = Vector2(int(grid.GRID_SIZE / 2), int(grid.GRID_SIZE / 2))
			print("EXTREME FALLBACK: Using center position: ", player_start_position)
		
		initialize_poi_system()

## Centralized function to manage all signal connections
func _setup_signals():
	print("Setting up POI system signals...")
	
	# Connect to grid's player_moved signal
	if grid and grid.has_signal("player_moved"):
		print("Connecting to player_moved signal...")
		grid.player_moved.connect(_on_player_moved)
		print("Connected to player_moved signal.")
	else:
		push_error("IsometricGrid does not have a player_moved signal!")
	
	# Connect to grid's player_starting_tile signal to know player's start position
	if grid and grid.has_signal("player_starting_tile"):
		print("Connecting to player_starting_tile signal...")
		grid.player_starting_tile.connect(_on_player_starting_tile)
		print("Connected to player_starting_tile signal.")
	else:
		print("WARNING: IsometricGrid does not have a player_starting_tile signal! Will use fallback method.")
	
	# Connect our own poi_collected signal to update grid visualization
	if not is_connected("poi_collected", _on_poi_collected):
		poi_collected.connect(_on_poi_collected)
		
	print("Signal setup complete.")

## Called when the player's starting tile is set
func _on_player_starting_tile(start_pos: Vector2):
	print("Received player starting position: ", start_pos)
	player_start_position = start_pos
	
	# Initialize POI system now that we have the player's starting position
	initialize_poi_system()

# Get player's quadrant (0=top-left, 1=top-right, 2=bottom-left, 3=bottom-right)
func get_quadrant(grid_pos: Vector2) -> int:
	var half_size = int(grid.GRID_SIZE / 2)
	
	# Ensure grid_pos components are integers
	var x = int(grid_pos.x)
	var y = int(grid_pos.y)
	
	# Print for debugging
	print("Calculating quadrant for position: ", grid_pos, ", half_size: ", half_size)
	
	# Handle edge cases - always move towards the center of a quadrant rather than randomly
	if x == half_size: # On vertical middle line
		# Check if we're in upper or lower half to decide which side to move to
		if y < half_size:
			x = x - 1 # Move to left quadrant (0 or 2)
		else:
			x = x + 1 # Move to right quadrant (1 or 3)
		print("Position on vertical middle line, adjusted x to: ", x)
		
	if y == half_size: # On horizontal middle line
		# Check if we're in left or right half to decide which side to move to
		if x < half_size:
			y = y - 1 # Move to top quadrant (0 or 1)
		else:
			y = y + 1 # Move to bottom quadrant (2 or 3)
		print("Position on horizontal middle line, adjusted y to: ", y)
	
	# Now determine the quadrant
	if x < half_size:
		if y < half_size:
			return 0 # Top-left
		else:
			return 2 # Bottom-left
	else:
		if y < half_size:
			return 1 # Top-right
		else:
			return 3 # Bottom-right

# Get random position within a specific quadrant
func get_random_position_in_quadrant(quadrant: int) -> Vector2:
	var half_size = int(grid.GRID_SIZE / 2)
	var x_start = 0
	var y_start = 0
	var x_end = half_size - 1 # Avoid boundary
	var y_end = half_size - 1 # Avoid boundary
	
	match quadrant:
		0: # Top-left
			x_start = 0
			y_start = 0
		1: # Top-right
			x_start = half_size + 1 # Ensure we're clearly in the right quadrant
			y_start = 0
			x_end = grid.GRID_SIZE - 1
		2: # Bottom-left
			x_start = 0
			y_start = half_size + 1 # Ensure we're clearly in the bottom quadrant
			y_end = grid.GRID_SIZE - 1
		3: # Bottom-right
			x_start = half_size + 1 # Ensure we're clearly in the right quadrant
			y_start = half_size + 1 # Ensure we're clearly in the bottom quadrant
			x_end = grid.GRID_SIZE - 1
			y_end = grid.GRID_SIZE - 1
	
	var x = x_start + randi() % (x_end - x_start + 1)
	var y = y_start + randi() % (y_end - y_start + 1)
	
	print("Generated position in quadrant ", quadrant, ": ", Vector2(x, y))
	return Vector2(x, y)

# Check if position is far enough from other POIs
func is_position_valid(pos: Vector2, existing_positions: Array) -> bool:
	for existing_pos in existing_positions:
		var distance = abs(existing_pos.x - pos.x) + abs(existing_pos.y - pos.y) # Manhattan distance
		if distance < min_poi_distance:
			return false
	return true

# Generate POI positions using quadrants
func initialize_poi_system():
	print("Initializing POI system...")
	
	# Clear any existing POIs
	for sprite in poi_sprites.values():
		if is_instance_valid(sprite):
			sprite.queue_free()
	
	poi_positions.clear()
	poi_sprites.clear()
	collected_pois.clear()
	
	# Reset available shapes
	available_shapes = SHAPES.keys().duplicate()
	
	# Check if we have the player's starting position
	if player_start_position == null:
		print("Warning: Player starting position not found, using random POI distribution")
		return initialize_poi_system_fallback()
	
	# Determine which quadrant the player is in
	var player_quadrant = get_quadrant(player_start_position)
	print("Player is in quadrant: ", player_quadrant, " at position: ", player_start_position)
	
	# Get available quadrants (all except player's)
	var available_quadrants = [0, 1, 2, 3]
	available_quadrants.erase(player_quadrant)
	print("Available quadrants after removing player's quadrant: ", available_quadrants)
	
	# Assign one POI to each of the remaining quadrants
	for i in range(min(POI_COUNT, available_quadrants.size())):
		var quadrant = available_quadrants[i]
		var max_attempts = 20 # Prevent infinite loops
		var attempts = 0
		var position = null
		
		# Try to find valid position in this quadrant
		while attempts < max_attempts:
			position = get_random_position_in_quadrant(quadrant)
			# Double-check the position is in the expected quadrant
			var actual_quadrant = get_quadrant(position)
			if actual_quadrant != quadrant:
				print("Warning: Generated position is in wrong quadrant. Expected ", quadrant, " but got ", actual_quadrant)
				attempts += 1
				continue
				
			if is_position_valid(position, poi_positions) and position != player_start_position:
				break
			attempts += 1
		
		if attempts == max_attempts:
			print("Warning: Could not find valid position in quadrant ", quadrant)
			continue
		
		# Add the valid position to our POIs
		poi_positions.append(position)
		print("Added POI at ", position, " in quadrant ", quadrant)
	
	# Create POI visual indicators
	for pos in poi_positions:
		create_poi_sprite(pos)
	
	print("POI System initialized with positions: ", poi_positions)
	
	# Request a redraw of the grid to show POI highlights
	if grid:
		grid.queue_redraw()
		
	# Emit signal that POIs have been generated
	emit_signal("pois_generated", poi_positions.size() > 0)
	print("pois_generated signal emitted with success = ", poi_positions.size() > 0)

# Fallback to old system if player position can't be determined
func initialize_poi_system_fallback():
	print("Using fallback POI generation method")
	
	# Generate POI positions
	while poi_positions.size() < POI_COUNT:
		var x = randi() % grid.GRID_SIZE
		var y = randi() % grid.GRID_SIZE
		var pos = Vector2(x, y)
		
		# Check minimum distance requirement
		if is_position_valid(pos, poi_positions):
			poi_positions.append(pos)
	
	# Create POI visual indicators
	for pos in poi_positions:
		create_poi_sprite(pos)
	
	print("POI System initialized with positions: ", poi_positions)
	
	# Request a redraw of the grid to show POI highlights
	if grid:
		grid.queue_redraw()
		
	# Emit signal that POIs have been generated
	emit_signal("pois_generated", true)

# Create a visual sprite for a POI at the given grid position
func create_poi_sprite(grid_pos):
	# Select a random shape from available shapes
	if available_shapes.size() == 0:
		push_error("No shapes available for POI creation!")
		return
	
	var shape_key = available_shapes[randi() % available_shapes.size()]
	available_shapes.erase(shape_key) # Remove shape so it's not used again
	
	var polygon = Polygon2D.new()
	polygon.polygon = SHAPES[shape_key]
	polygon.color = SHAPE_COLORS[shape_key] # Use shape-specific color
	polygon.position = grid.grid_to_screen(grid_pos.x, grid_pos.y) # Pass x and y separately
	polygon.z_index = 25 # Ensure it's above fog of war but below player
	add_child(polygon)
	
	# Add to our tracking dictionary
	poi_sprites[grid_pos] = polygon

## Called when the player moves to a new grid position
func _on_player_moved(grid_pos: Vector2):
	# print("Player moved to: ", grid_pos)
	# Convert to integer position for consistency with how positions are stored
	var pos_key = Vector2(int(grid_pos.x), int(grid_pos.y))
	
	# Check if this position has a POI through different methods
	var has_poi = false
	var collected = false
	
	# Method 1: Direct check in the array (exact match)
	if poi_positions.has(pos_key):
		has_poi = true
	
	# Method 2: Check with integer coordinates for all positions
	if not has_poi:
		for pos in poi_positions:
			if Vector2(int(pos.x), int(pos.y)) == pos_key:
				has_poi = true
				break
	
	# Check if already collected
	for collected_pos in collected_pois:
		if Vector2(int(collected_pos.x), int(collected_pos.y)) == pos_key:
			collected = true
			break
	
	if has_poi and not collected:
		# Get the reward from POI
		var reward = _get_poi_reward()
		print("Player collected POI at ", pos_key, " with reward: ", reward)
		
		# Add to collected array
		collected_pois.append(pos_key)
		
		# Remove the sprite
		var sprite_to_remove = null
		var key_to_remove = null
		
		for sprite_key in poi_sprites.keys():
			if Vector2(int(sprite_key.x), int(sprite_key.y)) == pos_key:
				sprite_to_remove = poi_sprites[sprite_key]
				key_to_remove = sprite_key
				break
		
		if sprite_to_remove:
			if is_instance_valid(sprite_to_remove):
				sprite_to_remove.queue_free()
			poi_sprites.erase(key_to_remove)
		
		# Emit collected signal with reward amount
		print("Emitting poi_collected signal with reward: ", reward)
		emit_signal("poi_collected", reward)
		
		# Also try using connect syntax for compatibility
		poi_collected.emit(reward)
		
		# Request a redraw to update tile highlights
		if grid:
			grid.queue_redraw()
		# print("No POI at position: ", pos_key, " or already collected")

# Process POI collection when player steps on it
func collect_poi(grid_position):
	# Convert to integer position for consistency
	var grid_pos_int = Vector2(int(grid_position.x), int(grid_position.y))
	
	# Check if this POI was already collected using integer comparison
	for pos in collected_pois:
		if Vector2(int(pos.x), int(pos.y)) == grid_pos_int:
			print("POI already collected, ignoring")
			return
	
	# Mark as collected
	collected_pois.append(grid_position)
	
	# Find the correct sprite to remove using integer comparison
	var sprite_to_remove = null
	var poi_key_to_remove = null
	
	for pos in poi_sprites.keys():
		if Vector2(int(pos.x), int(pos.y)) == grid_pos_int:
			sprite_to_remove = poi_sprites[pos]
			poi_key_to_remove = pos
			break
	
	# Remove the sprite
	if sprite_to_remove:
		if is_instance_valid(sprite_to_remove):
			sprite_to_remove.queue_free()
		poi_sprites.erase(poi_key_to_remove)
	
	# Generate random reward amount
	var reward = randi_range(MIN_REWARD, MAX_REWARD)
	
	# Emit signal with reward amount
	emit_signal("poi_collected", reward)
	
	print("POI collected at: ", grid_position, " with reward: $", reward)
	
	# Request a redraw to update tile highlights
	if grid:
		grid.queue_redraw()

# Debug function to manually test POI collection
func debug_collect_all_pois():
	print("Debug: Collecting all POIs...")
	for pos in poi_positions.duplicate():
		# Convert to integer position
		var pos_int = Vector2(int(pos.x), int(pos.y))
		
		# Check if already collected using integer comparison
		var already_collected = false
		for collected_pos in collected_pois:
			var collected_int = Vector2(int(collected_pos.x), int(collected_pos.y))
			if collected_int == pos_int:
				already_collected = true
				break
		
		if not already_collected:
			print("Debug: Collecting POI at ", pos)
			collect_poi(pos)

## Returns a random reward value for a collected POI
func _get_poi_reward() -> int:
	return randi_range(MIN_REWARD, MAX_REWARD)

## Called when a POI is collected, to update grid visualization
func _on_poi_collected(_amount):
	# Request a redraw of the grid to update POI highlighting
	if grid:
		grid.queue_redraw()

## Returns the current POI positions - useful for other systems
func get_poi_positions() -> Array:
	return poi_positions

## Check if player is at a POI position and collect it if so
func check_position(grid_pos: Vector2):
	# print("POI System: Checking position ", grid_pos)
	# Convert to integer position for consistency
	var pos_key = Vector2(int(grid_pos.x), int(grid_pos.y))
	
	# Check if there's a POI at this position
	var has_poi = false
	
	# First check with direct comparison
	if poi_positions.has(pos_key):
		has_poi = true
	
	# Check with integer coordinates for all positions if not found
	if not has_poi:
		for pos in poi_positions:
			if Vector2(int(pos.x), int(pos.y)) == pos_key:
				has_poi = true
				break
	
	# Check if already collected
	var collected = false
	for collected_pos in collected_pois:
		if Vector2(int(collected_pos.x), int(collected_pos.y)) == pos_key:
			collected = true
			break
	
	# If there's a POI that hasn't been collected, collect it
	if has_poi and not collected:
		print("Found uncollected POI at ", pos_key, ", collecting it")
		collect_poi(pos_key)
	# else:
	# 	print("No uncollected POI at position: ", pos_key)
