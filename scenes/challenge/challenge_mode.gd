extends Node

## Signal indicating the challenge mode has been toggled on/off
signal challenge_toggled(is_active: bool)

## Signal when the timer's time changes
signal time_changed(time_left: float)

## Signal when the timer expires
signal time_expired

## Signal for round start countdown
signal round_countdown_changed(count: int)

# Challenge mode settings
@export_category("Challenge Mode Settings")
@export var is_active: bool = false
@export var enable_timer: bool = true

const DEFAULT_TIME_PER_TURN: float = 12.0
const DEFAULT_TURN_LIMIT_MODIFIER: int = -3
const DEFAULT_TERRAIN_TILES_MODIFIER: int = 1
const ROUND_START_COUNTDOWN: float = 2.0

var time_per_turn: float = DEFAULT_TIME_PER_TURN
var turn_limit_modifier: int = DEFAULT_TURN_LIMIT_MODIFIER
var terrain_tiles_modifier: int = DEFAULT_TERRAIN_TILES_MODIFIER

# Timer variables
var current_timer: float = 0.0
var timer_active: bool = false

# Round start countdown variables
var countdown_active: bool = false
var countdown_timer: float = 0.0

# Reference to GameManager
var game_manager = null

func _ready():
	# Initialize timer
	reset_timer()
	
	# Get reference to GameManager
	game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		print("WARNING: GameManager not found in challenge mode")

func _process(delta):
	if countdown_active:
		countdown_timer -= delta
		var count = int(ceil(countdown_timer))
		emit_signal("round_countdown_changed", count)
		
		if countdown_timer <= 0:
			countdown_active = false
			_start_new_round()
	elif timer_active and is_active and enable_timer:
		current_timer -= delta
		emit_signal("time_changed", current_timer)
		
		if current_timer <= 0:
			timer_active = false
			# Signal to GameManager that time expired
			emit_signal("time_expired")

## Start the round countdown sequence
func start_round_countdown():
	# Set player to immobile during countdown
	var main_scene = get_tree().current_scene
	var grid = main_scene.get_node_or_null("IsometricGrid")
	if grid and "movement_state" in grid and grid.movement_state:
		grid.movement_state.transition_to(grid.movement_state.MovementState.IMMOBILE)
	
	# Start countdown
	countdown_active = true
	countdown_timer = ROUND_START_COUNTDOWN
	timer_active = false
	emit_signal("round_countdown_changed", int(ceil(countdown_timer)))

## Internal function to start the new round after countdown
func _start_new_round():
	var main_scene = get_tree().current_scene
	var grid = main_scene.get_node_or_null("IsometricGrid")
	
	# Allow player movement again - this will trigger an immediate redraw
	if grid and "movement_state" in grid and grid.movement_state:
		grid.movement_state.transition_to(grid.movement_state.MovementState.IDLE)
		
	# Wait until next frame before starting timer to ensure visuals are updated
	await get_tree().process_frame
	
	# Start the challenge timer if active
	if is_active and enable_timer:
		start_timer()

## Toggle challenge mode on/off
func toggle_challenge_mode():
	is_active = !is_active
	
	# Reset challenge mode state
	reset_challenge_state()
	
	emit_signal("challenge_toggled", is_active)
	
	if is_active:
		print("Challenge mode activated")
		
		# Request game reset via GameManager
		if game_manager:
			game_manager.reset_game()
		else:
			# Fallback if GameManager not available
			var main_scene = get_tree().current_scene
			var grid = main_scene.get_node_or_null("IsometricGrid")
			if grid and grid.has_method("_on_game_reset"):
				grid._on_game_reset()
			
		# Start the round countdown
		start_round_countdown()
	else:
		print("Challenge mode deactivated")
		
		# Request game reset via GameManager
		if game_manager:
			game_manager.reset_game()
		else:
			# Fallback if GameManager not available
			var main_scene = get_tree().current_scene
			var grid = main_scene.get_node_or_null("IsometricGrid")
			if grid and grid.has_method("_on_game_reset"):
				grid._on_game_reset()
		
	return is_active

## Completely reset all challenge mode state
func reset_challenge_state():
	# Stop timer and countdown
	timer_active = false
	countdown_active = false
	countdown_timer = 0.0
	
	# Reset timer to full time
	reset_timer()
	
	# Force emit signal to update UI with reset timer
	emit_signal("time_changed", current_timer)
	emit_signal("round_countdown_changed", 0)
	
	print("Challenge timer reset to: ", current_timer, " seconds")

## Start the timer for the current turn
func start_timer():
	if is_active and enable_timer:
		reset_timer()
		timer_active = true

## Stop the timer for the current turn
func stop_timer():
	timer_active = false

## Reset the timer to the full time
func reset_timer():
	# Ensure we're using the correct time_per_turn from the scene settings
	current_timer = time_per_turn
	emit_signal("time_changed", current_timer)

## Get the current turn limit modifier
func get_turn_limit_modifier() -> int:
	if is_active:
		return turn_limit_modifier
	return 0

## Get the current terrain tiles modifier
func get_terrain_tiles_modifier() -> int:
	if is_active:
		return terrain_tiles_modifier
	return 0

## Get formatted time string (MM:SS format)
func get_formatted_time() -> String:
	var minutes = int(current_timer) / 60
	var seconds = int(current_timer) % 60
	return "%02d:%02d" % [minutes, seconds]

## Allow external systems to request a reset of challenge mode state
func external_reset_request():
	reset_challenge_state()
	print("Challenge mode externally reset")
	
	# Start round countdown for new round
	start_round_countdown()
