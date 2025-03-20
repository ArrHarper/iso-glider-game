extends RefCounted

# Define movement states
enum MovementState {IDLE, HOVER, PATH_PLANNED, MOVEMENT_EXECUTING, MOVEMENT_COMPLETED, IMMOBILE}

# Current state
var current_state = MovementState.IDLE

# Reference to grid owner
var owner

# Shared data for all states
var current_path = []
var start_position = Vector2.ZERO
var target_position = Vector2.ZERO
var hover_position = Vector2.ZERO
var was_path_found = false
var has_moved_from_start = false # Track if player has moved away from the starting position
var initial_start_position = Vector2.ZERO # Store the initial start position

func _init(owner_node):
	owner = owner_node
	if owner.player_instance:
		start_position = owner.player_instance.current_grid_pos
		initial_start_position = start_position # Vector2 is already passed by value

# Main state transition function
func transition_to(new_state, params = {}):
	# Only log if state is actually changing
	if new_state != current_state:
		print("Movement state: ", _state_to_string(current_state), " -> ", _state_to_string(new_state))
	
	# If we're in IMMOBILE state, only allow transitions to IDLE
	if current_state == MovementState.IMMOBILE and new_state != MovementState.IDLE:
		print("Blocked state transition: Player is IMMOBILE")
		return false
	
	# Always update start position to match player's current position
	if owner.player_instance:
		start_position = owner.player_instance.current_grid_pos
		# print("Updated movement start position to: ", start_position)
	
	# Exit current state
	match current_state:
		MovementState.HOVER:
			owner.clear_movement_range()
		MovementState.PATH_PLANNED:
			owner.clear_target_highlight()
		MovementState.MOVEMENT_EXECUTING:
			pass # Nothing special on exit
		MovementState.IMMOBILE:
			owner.queue_redraw() # Force immediate redraw when exiting immobile state

	# Update state
	current_state = new_state

	# Enter new state
	match new_state:
		MovementState.IDLE:
			current_path = []
			was_path_found = false

		MovementState.HOVER:
			hover_position = params.get("hover_pos", Vector2(-1, -1))
			# Only calculate path for valid hover positions
			if hover_position != Vector2(-1, -1):
				current_path = owner.find_gridlocked_path(
					start_position,
					hover_position,
					owner.MOVEMENT_RANGE
				)
				was_path_found = current_path.size() > 0
				# Visualization
				owner.update_path_visualization(current_path)

		MovementState.PATH_PLANNED:
			target_position = params.get("target_pos", Vector2(-1, -1))
			# Use exactly the same path that was calculated during hover
			# or recalculate if we're jumping directly to this state
			if current_path.is_empty() or current_path[-1] != target_position:
				current_path = owner.find_gridlocked_path(
					start_position,
					target_position,
					owner.MOVEMENT_RANGE
				)
				was_path_found = current_path.size() > 0
			
			if was_path_found:
				owner.update_path_visualization(current_path)
				owner.show_target_highlight(target_position)

				# If confirmation is required, show dialog
				if owner.player_instance and owner.player_instance.MOVEMENT_CONFIRM and owner.main_ui:
					owner.main_ui.request_move_confirmation(
						start_position,
						target_position,
						owner.get_grid_name(target_position)
					)
				else:
					# No confirmation needed, move directly to execution
					transition_to(MovementState.MOVEMENT_EXECUTING)
			else:
				# If no valid path, go back to IDLE
				transition_to(MovementState.IDLE)

		MovementState.MOVEMENT_EXECUTING:
			if not was_path_found or current_path.is_empty():
				transition_to(MovementState.IDLE)
				return
				
			# Start actual movement using the exact same path
			var screen_path = []
			for point in current_path:
				screen_path.append(owner.grid_to_screen(point.x, point.y))

			# Set up player movement
			owner.player_instance.set_movement_path(screen_path)
			owner.player_instance.should_move = true
			owner.player_is_moving = true
			
			# Check if this is moving away from the initial start position
			if not has_moved_from_start and target_position != initial_start_position:
				has_moved_from_start = true
				print("Player has moved away from starting position")

		MovementState.MOVEMENT_COMPLETED:
			# Update player's grid position
			start_position = target_position
			owner.player_instance.current_grid_pos = target_position
			
			# Reset movement flag
			owner.player_is_moving = false

			# Clear visualization
			owner.clear_movement_range()
			owner.clear_target_highlight()

			# Update fog of war or other grid-related signals
			owner.emit_signal("player_moved", target_position)

			# Consume a turn
			if owner.main_ui != null:
				owner.main_ui.consume_turn(target_position)

			# DO NOT transition back to idle immediately to avoid infinite recursion
			# The state will remain as MOVEMENT_COMPLETED until something else changes it
			# Typically this will happen on the next frame when the mouse moves
			current_path = []
			was_path_found = false
			
		MovementState.IMMOBILE:
			# Clear any existing path or highlights
			current_path = []
			was_path_found = false
			owner.clear_movement_range()
			owner.clear_target_highlight()

	# Return true if transition was successful
	return true

# Helper function to get state name for debugging
func _state_to_string(state):
	match state:
		MovementState.IDLE: return "IDLE"
		MovementState.HOVER: return "HOVER"
		MovementState.PATH_PLANNED: return "PATH_PLANNED"
		MovementState.MOVEMENT_EXECUTING: return "MOVEMENT_EXECUTING"
		MovementState.MOVEMENT_COMPLETED: return "MOVEMENT_COMPLETED"
		MovementState.IMMOBILE: return "IMMOBILE"
		_: return "UNKNOWN"

# Handle movement confirmation response
func handle_movement_confirmation(confirmed):
	if current_state == MovementState.PATH_PLANNED:
		if confirmed:
			transition_to(MovementState.MOVEMENT_EXECUTING)
		else:
			transition_to(MovementState.IDLE)

# Reset player movement state for a new round/game
func reset():
	current_state = MovementState.IDLE
	current_path = []
	was_path_found = false
	has_moved_from_start = false
	
	# Update initial start position from grid if possible
	if owner and owner.player_instance:
		initial_start_position = owner.player_instance.current_grid_pos
		start_position = initial_start_position
