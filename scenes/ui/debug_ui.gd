extends CanvasLayer

@onready var player_moving_to_label = $DebugPanel/MarginContainer/DebugUIGrid/PlayerMovingToLabel
@onready var range_label = $DebugPanel/MarginContainer/DebugUIGrid/RangeLabel
@onready var position_label = $DebugPanel/MarginContainer/DebugUIGrid/PositionLabel
@onready var path_label = $DebugPanel/MarginContainer/DebugUIGrid/PathLabel

func _ready():
	# Wait one frame for all nodes to be ready
	await get_tree().process_frame
	
	# Print debug information about our node access
	print("Debug UI Nodes:")
	print("- player_moving_to_label: ", player_moving_to_label)
	print("- position_label: ", position_label)
	print("- range_label: ", range_label)
	print("- path_label: ", path_label)
	
	# Initialize with empty text
	update_debug_text("", Vector2.ZERO, Vector2.ZERO)
	
	# Set up signals
	_setup_signals()

## Centralized function to manage all signal connections
func _setup_signals():
	# Try to find the isometric grid in the scene tree first (preferred)
	var isometric_grid = get_tree().current_scene.get_node_or_null("IsometricGrid")
	
	# Fallback to finding via group if necessary
	if not isometric_grid:
		var grid_nodes = get_tree().get_nodes_in_group("isometric_grid")
		if grid_nodes.size() > 0:
			isometric_grid = grid_nodes[0]
	
	# Connect to grid signals if found
	if isometric_grid:
		# Connect to player_movement_range signal if it exists
		if isometric_grid.has_signal("player_movement_range"):
			isometric_grid.connect("player_movement_range", func(range_value): update_debug_text("", Vector2.ZERO, Vector2.ZERO))
	else:
		push_error("DebugUI: Could not find IsometricGrid node!")
	
	# Future signal connections would go here
	pass

# Update the debug text with movement information
func update_debug_text(grid_name: String, grid_pos: Vector2, screen_pos: Vector2):
	# Player movement information
	if player_moving_to_label:
		player_moving_to_label.text = "Player moving to: %s (Grid: %s, %s)" % [
			grid_name,
			grid_pos.x,
			grid_pos.y
		]
		print("Updated player_moving_to_label: ", player_moving_to_label.text)
	else:
		print("ERROR: player_moving_to_label is null")
	
	# Screen position information
	if position_label:
		if grid_name.is_empty():
			position_label.text = "Screen position: --"
		else:
			position_label.text = "Screen position: (%.1f, %.1f)" % [
				screen_pos.x,
				screen_pos.y
			]
		print("Updated position_label: ", position_label.text)
	else:
		print("ERROR: position_label is null")
	
	# Movement range information
	if range_label:
		var grid = get_tree().get_root().get_node_or_null("Main/IsometricGrid")
		if grid:
			range_label.text = "Movement Range: " + str(grid.MOVEMENT_RANGE) + " tile(s)"
		else:
			range_label.text = "Movement Range: Unknown"

# Update the path text display
func update_path_text(path_info: String):
	if !path_label:
		return
		
	path_label.text = path_info
