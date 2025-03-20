extends CharacterBody2D

## Emitted when the player has completed movement to the target position
signal movement_completed

# Player movement speed
@export var speed: float = 200.0

# Movement constraints
@export var PLAYER_GRIDLOCKED: bool = true # When true, only allows movement along X/Y axis. Do not show in debug UI.
@export var MOVEMENT_CONFIRM: bool = false # When true, requires confirmation before moving. Do not show in debug UI.

# Store movement range from grid
var movement_range: int = 2 # Default value that will be updated

# Variables for movement
var target_position: Vector2 = Vector2.ZERO
var current_grid_pos: Vector2 = Vector2(0, 0)
var should_move: bool = false
var movement_path: Array = [] # Array of screen positions for tile-by-tile movement
var current_path_index: int = 0 # Current index in the movement path

func _ready():
	# Initialize target position to current position
	target_position = position
	print("Player initialized at position: ", position)
	
	# Set up signals
	_setup_signals()
	
	# Connect to isometric grid signals for movement range
	var grid = get_node_or_null("/root/Main/IsometricGrid")
	if grid:
		if grid.is_connected("player_movement_range", _on_player_movement_range):
			grid.disconnect("player_movement_range", _on_player_movement_range)
		grid.connect("player_movement_range", _on_player_movement_range)

# Handle movement range signal from grid
func _on_player_movement_range(range_value: int):
	movement_range = range_value
	print("Player movement range set to: ", movement_range)

func _physics_process(delta):
	if should_move:
		if movement_path.size() > 0:
			# Get the next position in the path
			var next_target = movement_path[current_path_index]
			
			# Calculate the direction to move
			var direction = position.direction_to(next_target)
			
			# Set velocity
			velocity = direction * speed
			
			# Move using CharacterBody2D's built-in functions
			move_and_slide()
			
			# Check if we've reached the current target (or close enough)
			if position.distance_to(next_target) < 5:
				# Snap to the exact position
				position = next_target
				
				# Check if we've reached the end of the path
				if current_path_index == movement_path.size() - 1:
					# We've completed the entire path
					velocity = Vector2.ZERO
					should_move = false
					movement_path.clear()
					current_path_index = 0
					
					print("Reached final target position: ", position)
					
					# Make sure to update the current_grid_pos with the final position in the path
					if movement_path.size() > 0:
						var grid = get_node_or_null("/root/Main/IsometricGrid")
						if grid:
							current_grid_pos = grid.screen_to_grid(position.x, position.y)
							print("Updated player's current_grid_pos to: ", current_grid_pos)
					
					# Emit signal that movement is completed
					movement_completed.emit()
				else:
					# Move to the next point in the path
					current_path_index += 1
					# print("Moving to next path point: ", movement_path[current_path_index])
		else:
			# Fallback to direct movement if no path is provided
			print("No path provided, moving directly towards target: ", target_position)
			
			# Calculate the direction to move
			var direction = position.direction_to(target_position)
			
			# Set velocity
			velocity = direction * speed
			
			# Move using CharacterBody2D's built-in functions
			move_and_slide()
			
			# Check if we've reached the target (or close enough)
			if position.distance_to(target_position) < 5:
				# Snap to the exact position
				position = target_position
				velocity = Vector2.ZERO
				should_move = false
				
				print("Reached target position: ", position)
				
				# Make sure to update the current_grid_pos with the target position
				var grid = get_node_or_null("/root/Main/IsometricGrid")
				if grid:
					current_grid_pos = grid.screen_to_grid(position.x, position.y)
					print("Updated player's current_grid_pos to: ", current_grid_pos)
				
				# Emit signal that movement is completed
				movement_completed.emit()

# Set the movement path for tile-by-tile movement
func set_movement_path(path: Array):
	movement_path = path
	current_path_index = 0
	
	if movement_path.size() > 0:
		print("Movement path set with ", movement_path.size(), " points: ", movement_path)
		# The final target position is the last point in the path
		target_position = movement_path[movement_path.size() - 1]
	else:
		print("Empty movement path provided!")

## Centralized function to manage all signal connections
func _setup_signals():
	# Connect to isometric grid signals if available
	var grid = get_tree().get_nodes_in_group("isometric_grid")
	if grid.size() > 0:
		var isometric_grid = grid[0]
		if isometric_grid.has_signal("player_movement_range") and not isometric_grid.is_connected("player_movement_range", _on_player_movement_range):
			isometric_grid.connect("player_movement_range", _on_player_movement_range)
	# Future signal connections would go here
	pass