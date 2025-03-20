@tool
extends Node2D

## Emitted when an overlay is added
signal overlay_added(overlay_id)

## Emitted when an overlay is removed
signal overlay_cleared(overlay_id)

# Reference to the isometric grid
var grid = null

# Dictionary to store active overlays by ID
var active_overlays = {}

# Visual node container - holds all overlay visualizations
var visual_container = null

func _ready():
	# Don't run in editor
	if Engine.is_editor_hint():
		return
		
	# Get parent grid reference
	grid = get_parent()
	if not grid or not grid.has_method("grid_to_screen"):
		push_error("GridOverlaySystem must be a child of IsometricGrid!")
		return
	
	# Create container for visual elements
	visual_container = Node2D.new()
	visual_container.name = "OverlayVisuals"
	visual_container.z_index = 10 # Set z_index to ensure visibility
	add_child(visual_container)
	
	# Set up signal connections
	_setup_signals()
	
func _setup_signals():
	# Connect to grid's signals if needed
	pass

## Adds a path overlay between two points
## Returns a unique ID for the created overlay
func add_path_overlay(start_pos: Vector2, end_pos: Vector2, color: Color = Color.RED, size: float = 4.0) -> String:
	# Generate path points between start and end
	var path_points = generate_path(start_pos, end_pos)
	
	# Create overlay ID
	var overlay_id = "path_" + str(Time.get_ticks_msec())
	
	# Create visual elements for each point
	var overlay_nodes = []
	
	for point in path_points:
		var visual = create_dot(point, color, size)
		visual_container.add_child(visual)
		overlay_nodes.append(visual)
	
	# Store in active overlays
	active_overlays[overlay_id] = {
		"type": "path",
		"points": path_points,
		"nodes": overlay_nodes
	}
	
	# Emit signal
	emit_signal("overlay_added", overlay_id)
	
	return overlay_id

## Adds individual dots at specified grid positions
func add_dots_overlay(positions: Array, color: Color = Color.GREEN, size: float = 4.0) -> String:
	# Create overlay ID
	var overlay_id = "dots_" + str(Time.get_ticks_msec())
	
	# Create visual elements for each point
	var overlay_nodes = []
	
	for pos in positions:
		var visual = create_dot(pos, color, size)
		visual_container.add_child(visual)
		overlay_nodes.append(visual)
	
	# Store in active overlays
	active_overlays[overlay_id] = {
		"type": "dots",
		"points": positions,
		"nodes": overlay_nodes
	}
	
	# Emit signal
	emit_signal("overlay_added", overlay_id)
	
	return overlay_id

## Adds a highlight to a specific tile
func add_tile_highlight(position: Vector2, color: Color = Color(0.2, 0.8, 0.2, 0.3),
		border_color: Color = Color(0.0, 1.0, 0.0, 0.8)) -> String:
	# Create overlay ID
	var overlay_id = "highlight_" + str(Time.get_ticks_msec())
	
	# Create visual elements
	var screen_pos = grid.grid_to_screen(position.x, position.y)
	
	# Create diamond shape polygon
	var points = [
		Vector2(screen_pos.x, screen_pos.y - grid.TILE_HEIGHT / 2), # Top
		Vector2(screen_pos.x + grid.TILE_WIDTH / 2, screen_pos.y), # Right
		Vector2(screen_pos.x, screen_pos.y + grid.TILE_HEIGHT / 2), # Bottom
		Vector2(screen_pos.x - grid.TILE_WIDTH / 2, screen_pos.y) # Left
	]
	
	var polygon = Polygon2D.new()
	polygon.polygon = points
	polygon.color = color
	visual_container.add_child(polygon)
	
	var outline = Line2D.new()
	outline.points = points + [points[0]] # Close the shape
	outline.width = 1.0
	outline.default_color = border_color
	visual_container.add_child(outline)
	
	# Store in active overlays
	active_overlays[overlay_id] = {
		"type": "highlight",
		"position": position,
		"nodes": [polygon, outline]
	}
	
	# Emit signal
	emit_signal("overlay_added", overlay_id)
	
	return overlay_id

## Creates a dot at the specified grid position
func create_dot(grid_pos: Vector2, color: Color, size: float) -> Node2D:
	var screen_pos = grid.grid_to_screen(grid_pos.x, grid_pos.y)
	
	var dot = Node2D.new()
	dot.position = screen_pos
	dot.z_index = 10 # Ensure each dot is visible above grid elements
	
	var circle = Polygon2D.new()
	var circle_points = []
	var segments = 8 # Number of segments for the circle
	
	for i in range(segments):
		var angle = 2 * PI * i / segments
		var x = cos(angle) * size
		var y = sin(angle) * size
		circle_points.append(Vector2(x, y))
	
	circle.polygon = circle_points
	circle.color = color
	
	dot.add_child(circle)
	
	return dot

## Generate path points between start and end positions
func generate_path(start_pos: Vector2, end_pos: Vector2) -> Array:
	var path = []
	
	# Include start position
	path.append(start_pos)
	
	# Calculate steps needed
	var dx = end_pos.x - start_pos.x
	var dy = end_pos.y - start_pos.y
	var steps = max(abs(dx), abs(dy))
	
	if steps == 0:
		# Start and end are the same
		return path
	
	# Calculate increment per step
	var x_inc = dx / steps
	var y_inc = dy / steps
	
	# Generate intermediate points
	for i in range(1, steps):
		var x = start_pos.x + i * x_inc
		var y = start_pos.y + i * y_inc
		path.append(Vector2(round(x), round(y)))
	
	# Include end position
	if end_pos != start_pos:
		path.append(end_pos)
	
	return path

## Clear a specific overlay by ID
func clear_overlay(overlay_id: String) -> bool:
	if active_overlays.has(overlay_id):
		for node in active_overlays[overlay_id].nodes:
			if is_instance_valid(node):
				node.queue_free()
		
		active_overlays.erase(overlay_id)
		emit_signal("overlay_cleared", overlay_id)
		return true
	
	return false

## Clear all overlays
func clear_all_overlays() -> void:
	var overlay_ids = active_overlays.keys()
	for id in overlay_ids:
		clear_overlay(id)

## Update overlay visuals if needed
func update_overlay(overlay_id: String, new_params: Dictionary) -> bool:
	# First clear the existing overlay
	if not clear_overlay(overlay_id):
		return false
	
	# Then create a new one with updated parameters
	match new_params.type:
		"path":
			add_path_overlay(new_params.start_pos, new_params.end_pos,
					new_params.get("color", Color.RED),
					new_params.get("size", 4.0))
		"dots":
			add_dots_overlay(new_params.positions,
					new_params.get("color", Color.GREEN),
					new_params.get("size", 4.0))
		"highlight":
			add_tile_highlight(new_params.position,
					new_params.get("color", Color(0.2, 0.8, 0.2, 0.3)),
					new_params.get("border_color", Color(0.0, 1.0, 0.0, 0.8)))
	
	return true

## Check if an overlay exists
func has_overlay(overlay_id: String) -> bool:
	return active_overlays.has(overlay_id)

## Get overlay information
func get_overlay_info(overlay_id: String) -> Dictionary:
	if active_overlays.has(overlay_id):
		return active_overlays[overlay_id]
	return {}