extends Node2D

## Emitted when player requests to move to a new target position
## @param target_position: Vector2 representing the screen coordinates to move to
signal move_requested(target_position)

# Player movement speed
@export var move_speed: float = 200.0

var target_pos: Vector2 = Vector2.ZERO
var current_grid_pos: Vector2 = Vector2(0, 0) # Start at grid position 0,0
var is_moving: bool = false

func _ready():
	# Initialize starting position
	position = Vector2.ZERO
	
	# Set up signals
	_setup_signals()

func _process(delta):
	if is_moving:
		# Move towards the target position
		var distance = target_pos - position
		var direction = distance.normalized()
		var movement = direction * move_speed * delta
		
		# If we're close to the target, snap to it
		if distance.length() < movement.length():
			position = target_pos
			is_moving = false
		else:
			position += movement

## Centralized function to manage all signal connections
func _setup_signals():
	# Currently this script only emits signals, it doesn't connect to any
	# Future signal connections would go here
	pass

# Set a new target position for the player to move to
func move_to_grid_position(grid_x, grid_y):
	# Store the grid position
	current_grid_pos = Vector2(grid_x, grid_y)
	
	# Get the parent grid to convert coordinates
	var grid = get_parent()
	if grid.has_method("grid_to_screen"):
		target_pos = grid.grid_to_screen(grid_x, grid_y)
		is_moving = true
		move_requested.emit(target_pos)

# Called by the grid when a tile is clicked
func handle_tile_click(grid_x, grid_y):
	move_to_grid_position(grid_x, grid_y)