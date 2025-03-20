extends Control

signal scoreboard_closed

@onready var scores_list = %ScoresList
@onready var current_score = %CurrentScore
@onready var close_button = %CloseButton
@onready var reset_button = %ResetButton

# References to game systems
var game_manager = null
var challenge_mode = null
var player_score = 0
var player_rounds = 0
var high_score_position = -1 # Position in high scores list if player got a high score

func _ready():
	# Make sure UI can process while game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Set up buttons
	reset_button.pressed.connect(_on_reset_button_pressed)
	
	# Look for game manager - this will still be a singleton
	game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.scores_updated.connect(_on_scores_updated)
		game_manager.high_score_achieved.connect(_on_high_score_achieved)
		_populate_scores(game_manager.high_scores)
	
	# Look for challenge mode in the main scene
	challenge_mode = get_tree().current_scene.get_node_or_null("ChallengeMode")
	if not challenge_mode:
		# Try to get it from autoload
		challenge_mode = get_node_or_null("/root/ChallengeMode")
	
	# Hide by default
	hide()

# Handle when a high score is achieved
func _on_high_score_achieved(score_data, position):
	high_score_position = position
	
	# Only show name input if the board is visible
	if visible:
		show_name_input_dialog()

# Show dialog to enter name for high score
func show_name_input_dialog():
	if high_score_position < 0:
		return
	
	# Create a custom name input dialog
	var dialog = ConfirmationDialog.new()
	dialog.title = "New High Score!"
	dialog.size = Vector2(300, 150)
	
	# Create a container for layout
	var container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.modulate = Color(1, 0, 0, 0.8)
	
	# Add a label for instructions
	var label = Label.new()
	label.text = "You got a high score! Enter your name:"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)
	
	# Add spacing
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	container.add_child(spacer)
	
	# Add a line edit for name input
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "Enter your name"
	line_edit.max_length = 12 # Limit name length
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Set default name if any exists in OS
	var system_name = OS.get_environment("USERNAME") if OS.get_environment("USERNAME") else ""
	if system_name:
		line_edit.text = system_name
	
	container.add_child(line_edit)
	
	# Add container to dialog
	dialog.add_child(container)
	
	# Position the content container in the dialog
	container.position = Vector2(10, 10)
	container.size = Vector2(dialog.size) - Vector2(20, 50) # Adjust for dialog margins/buttons
	
	# Connect the confirmed signal
	dialog.confirmed.connect(func():
		var player_name = line_edit.text.strip_edges()
		
		# Default name if empty
		if player_name.is_empty():
			player_name = "Player"
		
		# Update the high score with the player's name
		if game_manager:
			game_manager.update_high_score_name(high_score_position, player_name)
		
		# Clean up
		dialog.queue_free()
	)
	
	# Connect the canceled signal to clean up
	dialog.canceled.connect(func():
		# If user cancels, use "Player" as default name
		if game_manager:
			game_manager.update_high_score_name(high_score_position, "Player")
		
		# Clean up
		dialog.queue_free()
	)
	
	# Add to scene and show
	add_child(dialog)
	dialog.popup_centered()
	
	# Set focus to line edit
	line_edit.grab_focus()

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
		no_scores.add_theme_font_size_override("font_size", 14)
		scores_list.add_child(no_scores)
	else:
		# Create scores header
		var header = HBoxContainer.new()
		header.size_flags_horizontal = SIZE_EXPAND_FILL
		
		var rank_header = Label.new()
		rank_header.text = "Rank"
		rank_header.add_theme_font_size_override("font_size", 14)
		rank_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_header.size_flags_horizontal = SIZE_EXPAND_FILL
		rank_header.size_flags_stretch_ratio = 0.5
		
		var name_header = Label.new()
		name_header.text = "Name"
		name_header.add_theme_font_size_override("font_size", 14)
		name_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_header.size_flags_horizontal = SIZE_EXPAND_FILL
		
		var money_header = Label.new()
		money_header.text = "Money"
		money_header.add_theme_font_size_override("font_size", 14)
		money_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		money_header.size_flags_horizontal = SIZE_EXPAND_FILL
		
		var rounds_header = Label.new()
		rounds_header.text = "Rounds"
		rounds_header.add_theme_font_size_override("font_size", 14)
		rounds_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rounds_header.size_flags_horizontal = SIZE_EXPAND_FILL
		rounds_header.size_flags_stretch_ratio = 0.75
		
		header.add_child(rank_header)
		header.add_child(name_header)
		header.add_child(money_header)
		header.add_child(rounds_header)
		
		scores_list.add_child(header)
		
		# Add a separator
		var separator = HSeparator.new()
		scores_list.add_child(separator)
		
		# Display scores
		for i in range(scores.size()):
			var score = scores[i]
			
			var row = HBoxContainer.new()
			row.size_flags_horizontal = SIZE_EXPAND_FILL
			
			var rank_label = Label.new()
			rank_label.text = "#" + str(i + 1)
			rank_label.add_theme_font_size_override("font_size", 14)
			rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rank_label.size_flags_horizontal = SIZE_EXPAND_FILL
			rank_label.size_flags_stretch_ratio = 0.5
			
			var name_label = Label.new()
			name_label.text = score.name
			name_label.add_theme_font_size_override("font_size", 14)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.size_flags_horizontal = SIZE_EXPAND_FILL
			
			var money_label = Label.new()
			money_label.text = "$" + str(score.money)
			money_label.add_theme_font_size_override("font_size", 14)
			money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			money_label.size_flags_horizontal = SIZE_EXPAND_FILL
			
			var rounds_label = Label.new()
			rounds_label.text = str(score.rounds)
			rounds_label.add_theme_font_size_override("font_size", 14)
			rounds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rounds_label.size_flags_horizontal = SIZE_EXPAND_FILL
			rounds_label.size_flags_stretch_ratio = 0.75
			
			row.add_child(rank_label)
			row.add_child(name_label)
			row.add_child(money_label)
			row.add_child(rounds_label)
			
			# Highlight player's score in yellow if it matches
			if score.money == player_score and player_rounds == score.rounds and player_score > 0:
				rank_label.add_theme_color_override("font_color", Color.YELLOW)
				name_label.add_theme_color_override("font_color", Color.YELLOW)
				money_label.add_theme_color_override("font_color", Color.YELLOW)
				rounds_label.add_theme_color_override("font_color", Color.YELLOW)
				
			scores_list.add_child(row)

# Show scoreboard with current score
func show_score(final_score = 0, rounds = 0):
	player_score = final_score
	player_rounds = rounds
	current_score.text = "Your Score: $%d (Rounds: %d)" % [final_score, rounds]
	current_score.add_theme_font_size_override("font_size", 14)
	
	# Update scores to highlight player's score if present
	if game_manager:
		_populate_scores(game_manager.high_scores)
		
		# If player has a high score, show the name input dialog
		if high_score_position >= 0:
			show_name_input_dialog()
	
	# Make sure we're centered in viewport and visible
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	
	show()

# Close scoreboard
func _on_close_button_pressed():
	hide()
	
	# Reset high score position
	high_score_position = -1
	
	# Emit signal to notify parent
	emit_signal("scoreboard_closed")

# Reset game and close scoreboard
func _on_reset_button_pressed():
	hide()
	
	# Reset high score position
	high_score_position = -1
	
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
