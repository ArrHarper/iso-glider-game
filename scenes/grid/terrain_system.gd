extends Node2D

## Emitted when terrain has been generated
signal terrain_generated(success)

# Default number of terrain obstacles to generate
@export var terrain_count: int = 12
# Minimum distance between terrain obstacles
@export var min_distance: int = 1
# Allow terrain to be placed near POIs (if false, will ensure terrain isn't placed on or adjacent to POIs)
@export var allow_near_pois: bool = false
# Minimum distance from player's starting position
@export var min_distance_from_player: int = 4
# Shape of the pyramid polygon (default fallback if pyramid sprite not found)
var PYRAMID_SHAPE = PackedVector2Array([Vector2(-10, 0), Vector2(0, -20), Vector2(10, 0), Vector2(0, 5)])
# Color of the terrain obstacles
@export var terrain_color: Color = Color(0.6, 0.4, 0.2, 0.8) # Brownish

var grid = null
var poi_system = null
var challenge_mode = null
var terrain_positions = [] # Array of Vector2 positions where terrain is located
var terrain_sprites = {} # Dictionary of terrain sprites indexed by position

func _ready():
	# Don't run in editor
	if Engine.is_editor_hint():
		return
	
	# Get parent grid reference
	grid = get_parent()
	print("Terrain system initialized with grid: ", grid)
	
	if not grid or not grid.has_method("grid_to_screen"):
		push_error("TerrainSystem must be a child of IsometricGrid!")
		return
	
	# Find POI system (should be a sibling node)
	poi_system = grid.get_node_or_null("POISystem")
	if not poi_system:
		push_error("POISystem not found! Terrain system needs POISystem to coordinate generation.")
		return
	
	# Look for challenge mode node
	challenge_mode = get_node_or_null("/root/ChallengeMode")
	if not challenge_mode:
		challenge_mode = get_tree().current_scene.get_node_or_null("ChallengeMode")
	
	if challenge_mode:
		challenge_mode.challenge_toggled.connect(_on_challenge_toggled)
	
	# Set up signal to generate terrain after POIs
	_setup_signals()
	
	# Fallback initialization after a delay if we never get the signal
	await get_tree().create_timer(1.0).timeout
	if terrain_positions.size() == 0:
		print("WARNING: Terrain system never received pois_generated signal, forcing initialization")
		initialize_terrain_system()

## Centralized function to manage all signal connections
func _setup_signals():
	print("Setting up Terrain system signals...")
	# Connect to POI system's pois_generated signal
	if poi_system and poi_system.has_signal("pois_generated"):
		print("Connecting to POI system's pois_generated signal...")
		# Ensure we're not already connected
		if not poi_system.is_connected("pois_generated", _on_pois_generated):
			poi_system.pois_generated.connect(_on_pois_generated)
			print("Connected to pois_generated signal.")
		else:
			print("Already connected to pois_generated signal.")
	else:
		push_error("POISystem does not have a pois_generated signal!")
	print("Signal setup complete.")

## Called when POIs have been generated
func _on_pois_generated(success: bool):
	print("Terrain system received pois_generated signal with success = ", success)
	if success:
		print("POIs generated successfully, now generating terrain...")
		initialize_terrain_system()
	else:
		push_error("POI generation failed, cannot generate terrain!")

## Called when challenge mode is toggled
func _on_challenge_toggled(is_active: bool):
	# Regenerate terrain when challenge mode changes
	initialize_terrain_system()

## Generate terrain positions across the map
func initialize_terrain_system():
	print("Initializing terrain system...")
	# Clear any existing terrain
	for sprite in terrain_sprites.values():
		if is_instance_valid(sprite):
			sprite.queue_free()
	
	terrain_positions.clear()
	terrain_sprites.clear()
	
	# Get player position - prefer to use the starting position from chess notation
	var player_pos = null
	if grid.has_method("chess_to_grid") and "PLAYER1_START" in grid:
		player_pos = grid.chess_to_grid(grid.PLAYER1_START)
		print("Using chess_to_grid for player position: ", grid.PLAYER1_START, " -> ", player_pos)
	elif grid.has_method("get_player_grid_pos"):
		player_pos = grid.get_player_grid_pos()
		print("Using get_player_grid_pos for player position: ", player_pos)
	elif grid.player_instance:
		player_pos = grid.player_instance.current_grid_pos
		print("Using player_instance.current_grid_pos for player position: ", player_pos)
	
	if not player_pos:
		print("Warning: Could not determine player position for terrain generation")
		player_pos = Vector2(0, 0) # Default fallback
	
	# Get POI positions from POI system
	var poi_positions = []
	if poi_system and poi_system.has_method("get_poi_positions"):
		poi_positions = poi_system.get_poi_positions()
		print("Got POI positions for terrain avoidance: ", poi_positions)
	else:
		poi_positions = poi_system.poi_positions if poi_system else []
		print("Using poi_system.poi_positions directly: ", poi_positions)
	
	# Adjust terrain count based on challenge mode
	var adjusted_terrain_count = terrain_count
	if challenge_mode and challenge_mode.is_active:
		adjusted_terrain_count += challenge_mode.get_terrain_tiles_modifier()
		print("Challenge mode active: adjusted terrain count to ", adjusted_terrain_count)
	
	print("Generating terrain with player at ", player_pos, " and POIs at ", poi_positions)
	
	# Generate terrain positions
	var attempts = 0
	var max_attempts = adjusted_terrain_count * 10 # Prevent infinite loops
	
	while terrain_positions.size() < adjusted_terrain_count and attempts < max_attempts:
		var x = randi() % grid.GRID_SIZE
		var y = randi() % grid.GRID_SIZE
		var pos = Vector2(x, y)
		
		# Check if position is valid
		if is_terrain_position_valid(pos, player_pos, poi_positions):
			terrain_positions.append(pos)
			print("Added terrain at ", pos)
		
		attempts += 1
	
	if terrain_positions.size() < adjusted_terrain_count:
		print("Warning: Could only place ", terrain_positions.size(), " of ", adjusted_terrain_count, " terrain obstacles")
	
	# Create terrain visual indicators
	for pos in terrain_positions:
		create_terrain_sprite(pos)
	
	print("Terrain System initialized with positions: ", terrain_positions)
	
	# Request a redraw of the grid to show terrain
	if grid and grid.has_method("queue_redraw"):
		grid.queue_redraw()
	
	# Inform grid that these positions are impassable
	if grid and grid.has_method("set_impassable_tiles"):
		grid.set_impassable_tiles(terrain_positions)
	
	# Emit signal that terrain has been generated
	emit_signal("terrain_generated", terrain_positions.size() > 0)
	print("terrain_generated signal emitted with success = ", terrain_positions.size() > 0)

## Check if position is valid for terrain placement
func is_terrain_position_valid(pos: Vector2, player_pos: Vector2, poi_positions: Array) -> bool:
	# Don't place on player's position
	if pos == player_pos:
		return false
	
	# Check minimum distance from player's current position
	var player_distance = abs(pos.x - player_pos.x) + abs(pos.y - player_pos.y) # Manhattan distance
	if player_distance < min_distance_from_player:
		return false
		
	# Check minimum distance from player's starting position if possible
	if grid.has_method("chess_to_grid") and "PLAYER1_START" in grid:
		var player_start_pos = grid.chess_to_grid(grid.PLAYER1_START)
		var start_distance = abs(pos.x - player_start_pos.x) + abs(pos.y - player_start_pos.y)
		if start_distance < 3: # Minimum 3 tiles away (this creates a 5x5 area with player start in center)
			return false
	
	# Check if position conflicts with POIs
	if not allow_near_pois:
		for poi_pos in poi_positions:
			var poi_distance = abs(pos.x - poi_pos.x) + abs(pos.y - poi_pos.y) # Manhattan distance
			if poi_distance < 2: # Keep at least 1 tile away from POIs
				return false
	
	# Check minimum distance from other terrain
	for terrain_pos in terrain_positions:
		var terrain_distance = abs(pos.x - terrain_pos.x) + abs(pos.y - terrain_pos.y) # Manhattan distance
		if terrain_distance < min_distance:
			return false
	
	return true

## Create a visual sprite for terrain at the given grid position
func create_terrain_sprite(grid_pos: Vector2):
	var polygon = Polygon2D.new()
	polygon.polygon = PYRAMID_SHAPE
	polygon.color = terrain_color
	polygon.position = grid.grid_to_screen(grid_pos.x, grid_pos.y)
	polygon.z_index = 25 # Same as POIs - above fog of war but below player
	add_child(polygon)
	
	# Add to our tracking dictionary
	terrain_sprites[grid_pos] = polygon

## Get the terrain positions - useful for other systems
func get_terrain_positions() -> Array:
	return terrain_positions

## Debug function to highlight all terrain
func debug_highlight_terrain():
	for pos in terrain_positions:
		if terrain_sprites.has(pos):
			var sprite = terrain_sprites[pos]
			if is_instance_valid(sprite):
				sprite.color = Color(1, 0, 0, 0.8) # Bright red
	
	print("DEBUG: Highlighted all terrain positions")