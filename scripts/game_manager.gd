extends Node

signal round_won(money_earned)
signal game_over(final_score)
signal scores_updated(scores)
signal turn_started
signal turn_ended
signal game_reset
signal round_reset
signal player_died
signal player_victory

const SAVE_FILE = "user://high_scores.save"
const MAX_SCORES = 10
const DEFAULT_TURN_LIMIT = 20

var current_money = 0
var total_money = 0
var high_scores = []
var current_round = 0
var challenge_mode = null
var turn_limit = DEFAULT_TURN_LIMIT
var current_turn = 0
var player_start_position = null
var player_current_position = null
var game_paused = false
var game_ended = false
var is_game_ending = false # Flag to track if we're during the ending sequence

func _ready():
	load_high_scores()
	
	# Look for challenge mode
	challenge_mode = get_node_or_null("/root/ChallengeMode")
	if not challenge_mode:
		var scene = get_tree().current_scene
		challenge_mode = scene.get_node_or_null("ChallengeMode")
	
	if challenge_mode:
		challenge_mode.challenge_toggled.connect(_on_challenge_toggled)
		challenge_mode.time_expired.connect(_on_time_expired)

# Centralized win round handling
func win_round(money_earned: int):
	print("Round won with money: ", money_earned)
	current_money = money_earned
	total_money += money_earned
	current_round += 1
	
	# Signal round won to update UI and other systems
	emit_signal("round_won", money_earned)
	emit_signal("player_victory")
	
	# Wait for a short delay before resetting the round
	await get_tree().create_timer(1.0).timeout
	
	# Reset for next round
	reset_round()

# Centralized game end handling
func end_game(is_victory: bool = false):
	# Update state
	game_ended = true
	is_game_ending = true
	
	# Stop any active timers
	if challenge_mode:
		challenge_mode.stop_timer()
	
	# Log game over and score
	print("Game over! Final score: ", total_money)
	
	# Add score to high scores
	add_high_score(total_money)
	
	# If player died (not victory), trigger explosion
	if not is_victory:
		emit_signal("player_died")
	
	# Pause the game after a short delay (allow time for explosion animation)
	await get_tree().create_timer(1.0).timeout
	
	# Pause the game
	game_paused = true
	get_tree().paused = true
	
	# Emit game over signal with final score
	emit_signal("game_over", total_money)

# Handle time expiration from challenge mode
func _on_time_expired():
	print("Time expired! Checking win/loss condition.")
	
	# First check if player is at the starting position (which is a win)
	if player_current_position == player_start_position:
		# Player made it back in time, win condition
		print("Timer expired but player is at starting position! Win condition.")
		win_round(current_money)
	else:
		# Player did not make it back in time, game over
		print("Timer expired and player is not at starting position. Game over.")
		end_game(false)

# Complete game reset
func reset_game():
	print("Resetting entire game")
	
	# Reset game state variables
	current_money = 0
	total_money = 0
	current_round = 1
	current_turn = 0
	game_paused = false
	game_ended = false
	is_game_ending = false
	
	# Unpause the game if it was paused
	get_tree().paused = false
	
	# Reset challenge mode if active
	if challenge_mode:
		challenge_mode.reset_challenge_state()
	
	# Update turn limit based on challenge mode
	_update_turn_limit()
	
	# Signal game reset to all systems
	emit_signal("game_reset")

# Reset for next round
func reset_round():
	print("Resetting for next round: ", current_round)
	
	# Reset round-specific variables
	current_money = 0
	current_turn = 0
	
	# Reset player position back to start
	reset_player_position()
	
	# Signal round reset to all systems
	emit_signal("round_reset")
	
	# If in challenge mode, handle the round countdown
	if challenge_mode and challenge_mode.is_active:
		challenge_mode.external_reset_request()

# Reset player position to starting position
func reset_player_position():
	if player_start_position:
		player_current_position = player_start_position

# Start a new turn
func start_turn():
	current_turn += 1
	emit_signal("turn_started")
	
	# Start the challenge mode timer if active
	if challenge_mode and challenge_mode.is_active:
		challenge_mode.start_timer()

# End the current turn
func end_turn():
	# Stop the challenge mode timer if active
	if challenge_mode:
		challenge_mode.stop_timer()
	
	emit_signal("turn_ended")
	
	# Check if we've reached the turn limit
	if current_turn >= turn_limit:
		end_game(false)

# Check win condition (player back at start after having moved)
func check_win_condition(player_pos, has_moved):
	if player_pos == player_start_position and has_moved:
		win_round(current_money)
		return true
	return false

# Check if out of turns
func check_turns_remaining(turns_left):
	if turns_left <= 0:
		end_game(false)
		return true
	return false

# Handler for challenge mode toggle
func _on_challenge_toggled(is_active: bool):
	# Update turn limit
	_update_turn_limit()
	
	# Reset turn count when challenge mode changes
	current_turn = 0
	
	# Reset player position tracking
	if player_start_position:
		player_current_position = player_start_position

# Update turn limit based on challenge mode
func _update_turn_limit():
	turn_limit = DEFAULT_TURN_LIMIT
	
	if challenge_mode and challenge_mode.is_active:
		turn_limit += challenge_mode.get_turn_limit_modifier()
		
	# Ensure turn limit is at least 5
	turn_limit = max(5, turn_limit)

# Update player position information
func update_player_position(grid_pos, is_start_position = false):
	if is_start_position:
		player_start_position = grid_pos
	
	player_current_position = grid_pos
	
	# If challenge mode is active and the player has moved away from starting position,
	# start the timer if it's not already active
	if challenge_mode and challenge_mode.is_active and challenge_mode.enable_timer:
		if player_current_position != player_start_position:
			if not challenge_mode.timer_active:
				print("Player left starting position, starting challenge timer")
				challenge_mode.start_timer()
		else:
			# Player is at starting position, stop timer
			challenge_mode.stop_timer()

# Add score to high scores if it qualifies
func add_high_score(score: int):
	# Ignore scores of 0
	if score <= 0:
		return
		
	high_scores.append(score)
	high_scores.sort()
	high_scores.reverse() # Highest first
	
	# Trim to max scores
	if high_scores.size() > MAX_SCORES:
		high_scores.resize(MAX_SCORES)
	
	save_high_scores()
	emit_signal("scores_updated", high_scores)

# Save high scores to disk
func save_high_scores():
	var save_data = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if save_data:
		for score in high_scores:
			save_data.store_line(str(score))

# Load high scores from disk
func load_high_scores():
	if FileAccess.file_exists(SAVE_FILE):
		var save_data = FileAccess.open(SAVE_FILE, FileAccess.READ)
		high_scores.clear()
		
		while save_data.get_position() < save_data.get_length():
			var score_text = save_data.get_line()
			var score = int(score_text)
			
			# Only add scores greater than 0
			if score > 0:
				high_scores.append(score)
	else:
		high_scores = []
	
	# Sort the scores in descending order
	high_scores.sort()
	high_scores.reverse()
	
	emit_signal("scores_updated", high_scores)

# Get formatted high scores for display
func get_formatted_high_scores() -> Array:
	var formatted = []
	for i in range(high_scores.size()):
		formatted.append("#%d: $%d" % [i + 1, high_scores[i]])
	return formatted