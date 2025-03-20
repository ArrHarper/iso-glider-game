extends Node2D

# Reference to the grid sprite scene
@export var grid_sprite_scene: PackedScene

# Reference to the isometric grid
var grid = null

# Dictionary to track sprites on grid positions
var grid_sprites = {}

func _ready():
	# Find the grid in the scene
	grid = get_tree().get_root().find_child("IsometricGrid", true, false)
	if not grid:
		push_error("IsometricGrid not found in the scene tree!")
		return
	
	# Wait one frame to ensure everything is properly set up
	await get_tree().process_frame

func add_sprite_at_grid(grid_x: int, grid_y: int):
	if not grid_sprite_scene or not grid:
		push_error("Missing grid_sprite_scene or grid reference")
		return null
	
	# Create grid position key
	var grid_pos_key = Vector2(grid_x, grid_y)
	
	# Check if there's already a sprite at this position
	if grid_sprites.has(grid_pos_key):
		print("A sprite already exists at this grid position: ", grid_pos_key)
		return null
	
	# Create new sprite instance
	var sprite_instance = grid_sprite_scene.instantiate()
	add_child(sprite_instance)
	
	# Set its grid position
	sprite_instance.set_grid_position(grid_x, grid_y)
	
	# Store in our grid sprites dictionary
	grid_sprites[grid_pos_key] = sprite_instance
	
	if grid.debug_mode:
		print("Added sprite at grid position: ", grid_pos_key)
	
	return sprite_instance

func remove_sprite_at_grid(grid_x: int, grid_y: int):
	# Create grid position key
	var grid_pos_key = Vector2(grid_x, grid_y)
	
	# Check if there's a sprite at this position
	if grid_sprites.has(grid_pos_key):
		# Get the sprite
		var sprite = grid_sprites[grid_pos_key]
		
		# Remove from dictionary
		grid_sprites.erase(grid_pos_key)
		
		# Free the sprite
		sprite.queue_free()
		
		if grid.debug_mode:
			print("Removed sprite at grid position: ", grid_pos_key)
		
		return true
	
	return false

# Check if a grid position has a sprite
func has_sprite_at_grid(grid_x: int, grid_y: int) -> bool:
	return grid_sprites.has(Vector2(grid_x, grid_y))

# Manual sprite placement/removal with spacebar
func _unhandled_input(event):
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
		if grid and grid_sprite_scene:
			# Get mouse position
			var mouse_pos = get_global_mouse_position()
			
			# Get the mouse position relative to the grid
			var grid_relative_pos = mouse_pos - grid.global_position
			
			# Convert to grid coordinates
			var grid_pos = grid.screen_to_grid(grid_relative_pos.x, grid_relative_pos.y)
			
			# Make sure it's within grid bounds
			if grid_pos.x >= 0 and grid_pos.x < grid.GRID_SIZE and grid_pos.y >= 0 and grid_pos.y < grid.GRID_SIZE:
				# Check if there's already a sprite at this position
				var grid_pos_key = Vector2(grid_pos.x, grid_pos.y)
				
				if grid_sprites.has(grid_pos_key):
					# Remove sprite if it exists
					remove_sprite_at_grid(grid_pos.x, grid_pos.y)
				else:
					# Add new sprite
					add_sprite_at_grid(grid_pos.x, grid_pos.y)
				
				# Accept the event so it doesn't propagate to other nodes
				get_viewport().set_input_as_handled()