extends Control

signal scoreboard_closed

@onready var scores_list = %ScoresList
@onready var current_score = %CurrentScore
@onready var close_button = %CloseButton
@onready var reset_button = %ResetButton

var game_manager = null
var challenge_mode = null
var player_score = 0

func _ready():
	# Make sure UI can process while game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Set up buttons
	close_button.pressed.connect(_on_close_button_pressed)
	reset_button.pressed.connect(_on_reset_button_pressed)
	
	# Look for game manager
	game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.scores_updated.connect(_on_scores_updated)
		_populate_scores(game_manager.high_scores)
	
	# Look for challenge mode
	challenge_mode = get_node_or_null("/root/ChallengeMode")
	if not challenge_mode:
		challenge_mode = get_tree().current_scene.get_node_or_null("ChallengeMode")
	
	# Hide by default
	hide()

# Update UI when scores change
func _on_scores_updated(scores):
	_populate_scores(scores)

# Populate the scores list
func _populate_scores(scores):
	# Clear existing scores
	for child in scores_list.get_children():
		child.queue_free()
	
	# Add score entries
	if scores.size() == 0:
		var no_scores = Label.new()
		no_scores.text = "No scores yet"
		no_scores.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		scores_list.add_child(no_scores)
	else:
		# Remove duplicate scores (only keep the first occurrence)
		var unique_scores = []
		for score in scores:
			if not unique_scores.has(score):
				unique_scores.append(score)
		
		# Display scores
		for i in range(unique_scores.size()):
			var entry = Label.new()
			entry.text = "#%d: $%d" % [i + 1, unique_scores[i]]
			entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			
			# Highlight player's score in yellow if it matches
			if unique_scores[i] == player_score and player_score > 0:
				entry.add_theme_color_override("font_color", Color.YELLOW)
				
			scores_list.add_child(entry)

# Show scoreboard with current score
func show_score(final_score = 0):
	player_score = final_score
	current_score.text = "Your Score: $%d" % final_score
	
	# Update scores to highlight player's score if present
	if game_manager:
		_populate_scores(game_manager.high_scores)
	
	# Make sure we're centered in viewport and visible
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	
	show()

# Close scoreboard
func _on_close_button_pressed():
	hide()
	
	# Emit signal to notify parent
	emit_signal("scoreboard_closed")

# Reset game and close scoreboard
func _on_reset_button_pressed():
	hide()
	
	# Find game manager to reset properly
	var game_manager = get_node_or_null("/root/GameManager")
	
	# Unpause the game
	get_tree().paused = false
	
	if game_manager:
		# Use game manager's reset function
		game_manager.reset_game()
	else:
		# Fallback if no game manager found
		# Find main UI to reset game state
		var main_scene = get_tree().current_scene
		var main_ui = main_scene.get_node_or_null("MainUI")
		if main_ui and main_ui.has_method("reset_game"):
			# Reset all game state
			main_ui.reset_game()
	
	# Emit signal to notify parent
	emit_signal("scoreboard_closed")
	
	# If in challenge mode, use proper sequence
	if challenge_mode and challenge_mode.is_active:
		# This will:
		# - Set player to IMMOBILE
		# - Reset game state
		# - Start countdown
		# - Return to IDLE when countdown ends
		challenge_mode.external_reset_request()