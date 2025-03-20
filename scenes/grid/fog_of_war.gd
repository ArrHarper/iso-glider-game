@tool
extends Node2D

# Constants for fog state
enum FogState {HIDDEN, REVEALED}

# Reference to the isometric grid
var grid = null

# Store fog tiles indexed by grid position Vector2
var fog_tiles = {}

# Visibility map to track which tiles are revealed
var visibility_map = []

# Reference to POI system
var poi_system = null

# Get coordinates for 4 adjacent tiles in cardinal directions
func get_adjacent_tiles(grid_pos: Vector2) -> Array:
	return [
		Vector2(grid_pos.x + 1, grid_pos.y), # East
		Vector2(grid_pos.x - 1, grid_pos.y), # West
		Vector2(grid_pos.x, grid_pos.y + 1), # South
		Vector2(grid_pos.x, grid_pos.y - 1) # North
	]

func _ready():
	# Don't run in editor
	if Engine.is_editor_hint():
		return
		
	# Get parent grid reference
	grid = get_parent()
	if not grid or not grid.has_method("grid_to_screen"):
		push_error("FogOfWar must be a child of IsometricGrid!")
		return
	
	# Wait one frame to ensure everything is properly set up
	await get_tree().process_frame
	
	# Find the POI system
	poi_system = grid.get_node_or_null("POISystem")
	
	# Initialize fog system
	initialize_fog()
	
	# Set up signal connections
	_setup_signals()
	
	# Initial reveal around player
	var player = grid.get_node_or_null("Player1")
	if player:
		reveal_tiles_around_player(player.current_grid_pos)

# Initialize the fog of war system
func initialize_fog():
	# Clear existing fog tiles
	for tile in fog_tiles.values():
		if is_instance_valid(tile):
			tile.queue_free()
	fog_tiles.clear()
	
	# Initialize visibility map (empty initially, will add as revealed)
	visibility_map.clear()
	
	# Create fog tile for each grid position
	for y in range(grid.GRID_SIZE):
		for x in range(grid.GRID_SIZE):
			create_fog_tile(x, y)
	
	# Wait for POI system to initialize
	await get_tree().process_frame
	
	# Update fog for POIs
	update_for_pois()
	
	# Find player to reveal initial tiles around
	var player = grid.get_node_or_null("Player1")
	if player:
		reveal_tiles_around_player(player.current_grid_pos)

# Create a fog tile at the given grid coordinates
func create_fog_tile(grid_x, grid_y):
	var pos = grid.grid_to_screen(grid_x, grid_y)
	
	# Create a Polygon2D node for the fog tile
	var fog_tile = Polygon2D.new()
	add_child(fog_tile)
	
	# Set polygon shape (diamond)
	var points = [
		Vector2(pos.x, pos.y - grid.TILE_HEIGHT / 2), # Top
		Vector2(pos.x + grid.TILE_WIDTH / 2, pos.y), # Right
		Vector2(pos.x, pos.y + grid.TILE_HEIGHT / 2), # Bottom
		Vector2(pos.x - grid.TILE_WIDTH / 2, pos.y) # Left
	]
	fog_tile.polygon = points
	
	# Set fog color with opacity
	fog_tile.color = Color(0.1, 0.1, 0.2, 0.8)
	
	# Store the fog tile by grid position
	fog_tiles[Vector2(grid_x, grid_y)] = fog_tile
	
	# Set above other grid elements
	fog_tile.z_index = 10
	
	return fog_tile

# Set up signal connections
func _setup_signals():
	# Connect to grid's player_moved signal
	if grid and grid.has_signal("player_moved"):
		grid.player_moved.connect(_on_grid_player_moved)
	
	# Find player and connect to its movement signal
	var player = grid.get_node_or_null("Player1")
	if player and player is CharacterBody2D and player.has_signal("movement_completed"):
		player.movement_completed.connect(_on_player_movement_completed)

# Called when grid signals that player has moved
func _on_grid_player_moved(grid_pos):
	print("Revealing fog at: ", grid_pos)
	reveal_tiles_around_player(grid_pos)

# Called when player completes a movement
func _on_player_movement_completed():
	# Find player
	var player = grid.get_node_or_null("Player1")
	if player:
		reveal_tiles_around_player(player.current_grid_pos)

# Reveal tiles around player at given grid position
func reveal_tiles_around_player(grid_pos: Vector2):
	# Reveal the tile the player is on
	reveal_tile(grid_pos.x, grid_pos.y)
	
	# Reveal adjacent tiles
	var adjacent_tiles = get_adjacent_tiles(grid_pos)
	for tile in adjacent_tiles:
		if tile.x >= 0 and tile.x < grid.GRID_SIZE and tile.y >= 0 and tile.y < grid.GRID_SIZE:
			reveal_tile(tile.x, tile.y)

# Reveal a specific tile
func reveal_tile(grid_x, grid_y):
	# Update visibility map
	var grid_pos = Vector2(grid_x, grid_y)
	
	# Add to visibility map if not already there
	if not grid_pos in visibility_map:
		visibility_map.append(grid_pos)
	
	# Update fog visual
	if fog_tiles.has(grid_pos):
		# Set alpha based on visibility status
		fog_tiles[grid_pos].color.a = get_fog_alpha(grid_pos)

# Reset fog of war for new game
func reset_fog():
	# Completely reinitialize the fog system
	for tile in fog_tiles.values():
		if is_instance_valid(tile):
			tile.queue_free()
	fog_tiles.clear()
	
	# Clear visibility map
	visibility_map.clear()
	
	# Create fog tile for each grid position
	for y in range(grid.GRID_SIZE):
		for x in range(grid.GRID_SIZE):
			create_fog_tile(x, y)
	
	# Wait a frame to ensure POI system is updated
	await get_tree().process_frame
	
	# Update fog for POIs
	update_for_pois()
	
	# Reveal around player
	var player = grid.get_node_or_null("Player1")
	if player:
		reveal_tiles_around_player(player.current_grid_pos)

# Update fog tiles based on current visibility
func update_fog_visuals():
	for pos in fog_tiles.keys():
		fog_tiles[pos].color.a = get_fog_alpha(pos)

# Called after POI system initializes to ensure POIs are visible
func update_for_pois():
	if poi_system:
		for poi_pos in poi_system.poi_positions:
			if fog_tiles.has(poi_pos):
				fog_tiles[poi_pos].color.a = get_fog_alpha(poi_pos)

# Get the fog alpha value for a specific grid position
func get_fog_alpha(grid_pos: Vector2) -> float:
	# Always make POI tiles visible with semi-transparent fog
	if poi_system and poi_system.poi_positions.has(grid_pos) and not poi_system.collected_pois.has(grid_pos):
		return 0.3 # Semi-transparent fog for POIs
	
	# Check if tile is in visibility map
	for i in range(visibility_map.size()):
		if visibility_map[i] == grid_pos:
			return 0.0 # Fully revealed
	
	# Default to hidden
	return 1.0 # Fully hidden
