extends CanvasLayer

@onready var debug_label = $DebugPanel/MarginContainer/VBoxContainer/DebugLabel
# Store path text to preserve it when updating other debug text
var current_path_text = ""

func _ready():
	# Wait one frame for all nodes to be ready
	await get_tree().process_frame
	
	# Check if debug_label exists
	if !debug_label:
		push_error("Debug label not found! Debug UI will not show text.")
		return
		
	# Initialize with empty text
	update_debug_text("", Vector2.ZERO, Vector2.ZERO)
	
	# Set up signals
	_setup_signals()

## Centralized function to manage all signal connections
func _setup_signals():
	# Connect to isometric grid signals if available
	var grid = get_tree().get_nodes_in_group("isometric_grid")
	if grid.size() > 0:
		var isometric_grid = grid[0]
		# Connect to player_movement_range signal if we need to react to changes
		if isometric_grid.has_signal("player_movement_range"):
			isometric_grid.connect("player_movement_range", func(range_value): update_debug_text("", Vector2.ZERO, Vector2.ZERO))
	
	# Future signal connections would go here
	pass

# Update the debug text with movement information
func update_debug_text(grid_name: String, grid_pos: Vector2, screen_pos: Vector2):
	if !debug_label:
		return
		
	var text = ""
	
	if grid_name.is_empty():
		text = "Click on a grid tile to move the player"
	else:
		text = "Player moving to: %s (Grid: %s, %s)\nScreen position: (%.1f, %.1f)" % [
			grid_name,
			grid_pos.x,
			grid_pos.y,
			screen_pos.x,
			screen_pos.y
		]
	
	# Add movement constraint information - get from grid rather than player
	var grid = get_tree().get_root().get_node_or_null("Main/IsometricGrid")
	if grid:
		text += "\nMovement Range: " + str(grid.MOVEMENT_RANGE) + " tile(s)"
	
	# Add path information if available
	if not current_path_text.is_empty():
		text += "\n\n" + current_path_text
	
	debug_label.text = text

# Update the path text display
func update_path_text(path_info: String):
	if !debug_label:
		return
		
	current_path_text = path_info
	
	# Update the full debug text to include the new path info
	var grid = get_tree().get_root().get_node_or_null("Main/IsometricGrid")
	if grid and grid.player_instance:
		var player = grid.player_instance
		var current_pos = player.current_grid_pos
		var current_tile = char(65 + int(current_pos.x)) + str(int(current_pos.y) + 1)
		update_debug_text(current_tile, current_pos, player.position)
	else:
		# If we can't get the player info, just update with the path
		var text = debug_label.text
		if "\n\n" in text:
			# Replace existing path text
			text = text.substr(0, text.rfind("\n\n")) + "\n\n" + path_info
		else:
			# Add path text
			text += "\n\n" + path_info
		debug_label.text = text
