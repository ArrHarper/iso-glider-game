@tool
extends Node

## Template for creating new grid overlay system components
## Replace "Template" with your specific overlay type name throughout this file

## Controls whether this overlay component is enabled
@export var overlay_enabled: bool = true

## Color of the overlay elements (customize based on your needs)
@export var overlay_color: Color = Color(0.0, 0.7, 1.0, 0.7) # Default cyan

## Size of the overlay elements
@export var overlay_size: float = 4.0

# Reference to the grid and overlay system
var grid = null
var overlay_system = null

# ID of the current active overlay(s)
var current_overlay_id: String = ""
# Add more overlay IDs if your component manages multiple overlays
# var overlay_ids: Array = []

func _ready():
	# Don't run in editor
	if Engine.is_editor_hint():
		return
		
	# Find required nodes
	await get_tree().process_frame
	_find_dependencies()
	_connect_signals()

func _find_dependencies():
	# Get parent or find grid
	if get_parent() and get_parent().is_in_group("isometric_grid"):
		grid = get_parent()
	else:
		grid = get_tree().get_first_node_in_group("isometric_grid")
	
	if not grid:
		push_error("OverlayComponent: Isometric grid not found!")
		return false
		
	# Get overlay system
	overlay_system = grid.get_node_or_null("GridOverlaySystem")
	if not overlay_system:
		push_error("OverlayComponent: GridOverlaySystem not found!")
		return false
		
	return true

func _connect_signals():
	if not grid:
		return
		
	# Example: Connect to grid signals
	# if grid.has_signal("signal_name") and not grid.is_connected("signal_name", _on_signal_name):
	#     grid.connect("signal_name", _on_signal_name)
	
	# CUSTOMIZE: Connect to any relevant signals for your component
	pass

# CUSTOMIZE: Add methods for responding to signals
# func _on_some_signal(parameter):
#     if not overlay_enabled or not overlay_system:
#         return
#
#     _clear_current_overlay()
#     
#     # Create new overlay
#     current_overlay_id = overlay_system.add_some_overlay(...)

# CUSTOMIZE: Add methods for creating different types of overlays
func create_overlay(positions: Array) -> void:
	"""
	Creates a new overlay based on the provided positions.
	
	Parameters:
	positions - An array of Vector2 grid coordinates where overlay elements should appear
	"""
	if not overlay_enabled or not overlay_system:
		return
		
	# Clear any existing overlay first
	_clear_current_overlay()
	
	# CUSTOMIZE: Choose the appropriate overlay type for your needs
	# Example: Adding dots at specified positions
	current_overlay_id = overlay_system.add_dots_overlay(
		positions,
		overlay_color,
		overlay_size
	)
	
	# Example: Adding a path between two points
	# if positions.size() >= 2:
	#     current_overlay_id = overlay_system.add_path_overlay(
	#         positions[0],
	#         positions[1],
	#         overlay_color,
	#         overlay_size
	#     )
	
	# Example: Highlighting a specific tile
	# if positions.size() > 0:
	#     current_overlay_id = overlay_system.add_tile_highlight(
	#         positions[0],
	#         Color(overlay_color.r, overlay_color.g, overlay_color.b, 0.3),
	#         Color(overlay_color.r, overlay_color.g, overlay_color.b, 0.8)
	#     )

# Clear current overlay
func _clear_current_overlay() -> void:
	if current_overlay_id != "" and overlay_system and overlay_system.has_overlay(current_overlay_id):
		overlay_system.clear_overlay(current_overlay_id)
		current_overlay_id = ""
	
	# CUSTOMIZE: If managing multiple overlays, clear them all
	# for id in overlay_ids:
	#     if overlay_system and overlay_system.has_overlay(id):
	#         overlay_system.clear_overlay(id)
	# overlay_ids.clear()

# Public method to clear all overlays managed by this component
func clear_all_overlays() -> void:
	_clear_current_overlay()

# Public methods to enable/disable overlays
func enable_overlay() -> void:
	overlay_enabled = true

func disable_overlay() -> void:
	overlay_enabled = false
	_clear_current_overlay()

# Toggle overlay visibility
func toggle_overlay() -> void:
	overlay_enabled = not overlay_enabled
	if not overlay_enabled:
		_clear_current_overlay()

# CUSTOMIZE: Add any additional helper methods specific to your component
# func calculate_positions() -> Array:
#     # Calculate positions for your overlay based on game state
#     var positions = []
#     # Add logic here
#     return positions

# CUSTOMIZE: Add custom processing if needed
# func _process(delta):
#     if not overlay_enabled or not overlay_system:
#         return
#
#     # Update overlays based on changing conditions
#     pass 