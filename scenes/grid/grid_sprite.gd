@tool
extends Node2D

# Reference to the isometric grid
var grid = null
# Store the current grid position
var current_grid_pos = Vector2(-1, -1)

# Editor property to snap to grid
@export var editor_snap_to_grid: bool = false:
	set(value):
		editor_snap_to_grid = false
		if Engine.is_editor_hint() and value:
			_find_grid()
			snap_to_grid()

# Editor properties to manually set grid position
@export_group("Editor Grid Position")
@export_range(0, 7, 1) var editor_grid_x: int = 0:
	set(value):
		editor_grid_x = value
		if Engine.is_editor_hint():
			_update_editor_grid_position()

@export_range(0, 7, 1) var editor_grid_y: int = 0:
	set(value):
		editor_grid_y = value
		if Engine.is_editor_hint():
			_update_editor_grid_position()

@export var apply_grid_position: bool = false:
	set(value):
		apply_grid_position = false
		if Engine.is_editor_hint() and value:
			_find_grid()
			set_grid_position(editor_grid_x, editor_grid_y)

func _ready():
	if not Engine.is_editor_hint():
		# Only run this in-game, not in editor
		_find_grid()

func _find_grid():
	# Try to find the grid in the scene
	if Engine.is_editor_hint():
		# Use static method when in editor
		var EditorInterface = Engine.get_singleton("EditorInterface")
		if EditorInterface:
			var edited_scene_root = EditorInterface.get_edited_scene_root()
			if edited_scene_root:
				grid = edited_scene_root.find_child("IsometricGrid", true, false)
	else:
		# Runtime lookup
		grid = get_tree().get_root().find_child("IsometricGrid", true, false)
		
	if not grid:
		push_error("IsometricGrid not found in the scene tree!")

func _update_editor_grid_position():
	if Engine.is_editor_hint() and grid:
		set_grid_position(editor_grid_x, editor_grid_y)

func set_grid_position(grid_x: int, grid_y: int) -> void:
	_find_grid()
	if grid:
		# Set the grid position
		current_grid_pos = Vector2(grid_x, grid_y)
		# Update visual position
		grid.add_sprite_to_grid(self, grid_x, grid_y)
		
		# Update editor properties to match
		if Engine.is_editor_hint():
			editor_grid_x = grid_x
			editor_grid_y = grid_y
	else:
		push_error("Grid not found, cannot set grid position")

func snap_to_grid() -> void:
	_find_grid()
	if grid:
		grid.snap_sprite_to_grid(self)
		
		# Update our current grid position after snapping
		var relative_pos = global_position - grid.global_position
		current_grid_pos = grid.screen_to_grid(relative_pos.x, relative_pos.y)
		
		# Ensure positions are within grid bounds
		current_grid_pos.x = clamp(current_grid_pos.x, 0, grid.GRID_SIZE - 1)
		current_grid_pos.y = clamp(current_grid_pos.y, 0, grid.GRID_SIZE - 1)
		
		# Update editor properties to match
		if Engine.is_editor_hint():
			editor_grid_x = int(current_grid_pos.x)
			editor_grid_y = int(current_grid_pos.y)
	else:
		push_error("Grid not found, cannot snap to grid")

# Get the current grid position
func get_grid_position() -> Vector2:
	return current_grid_pos
