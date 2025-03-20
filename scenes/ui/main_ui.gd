extends CanvasLayer

## Emitted when the game ends
## @param successful: Boolean indicating whether the player succeeded (true) or failed (false)
signal game_over(successful)

## Emitted when the game is reset
signal game_reset

## Emitted when a round is won and player is ready for the next round
signal next_round

## Emitted when movement is confirmed or canceled
signal movement_confirmed(confirmed)

@onready var move_info_label = %MoveInfoLabel
@onready var turns_label = %TurnsLabel
@onready var money_label = %MoneyLabel
@onready var total_money_label = %TotalMoneyLabel
@onready var round_label = %RoundLabel
@onready var turns_panel = %TurnsPanel
@onready var countdown_label = %CountdownLabel

var scoreboard_scene = preload("res://scenes/ui/scoreboard.tscn")
var scoreboard = null

const DEFAULT_MAX_TURNS = 20
var turns_remaining = DEFAULT_MAX_TURNS
var pending_move_data = null
var player_start_position = null
var player_money = 0
var total_money = 0
var current_round = 1
var game_manager = null
var movement_range = 2 # Player's movement range
var player_has_moved = false # Track if player has moved away from start
var challenge_mode = null

func _ready():
	# Find or create scoreboard
	scoreboard = get_node_or_null("Scoreboard")
	if not scoreboard:
		scoreboard = scoreboard_scene.instantiate()
		add_child(scoreboard)
		scoreboard.visible = false
	
	# Connect move confirmation dialog buttons
	var confirm_button = get_node_or_null("MoveConfirmDialog/VBoxContainer/HBoxContainer/ConfirmButton")
	var cancel_button = get_node_or_null("MoveConfirmDialog/VBoxContainer/HBoxContainer/CancelButton")
	
	if confirm_button:
		confirm_button.pressed.connect(confirm_move)
	else:
		push_error("Confirm button not found in MoveConfirmDialog")
		
	if cancel_button:
		cancel_button.pressed.connect(cancel_move)
	else:
		push_error("Cancel button not found in MoveConfirmDialog")
		
	# Get the GameManager singleton
	game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		# Connect to GameManager signals
		game_manager.connect("round_won", _on_round_won)
		game_manager.connect("game_over", _on_game_manager_game_over)
		game_manager.connect("game_reset", _on_game_reset)
		game_manager.connect("round_reset", _on_round_reset)
		game_manager.connect("turn_started", _on_turn_started)
		game_manager.connect("turn_ended", _on_turn_ended)
	else:
		push_error("GameManager not found! Game state will not work correctly.")
		
	# Connect to IsometricGrid for win condition
	var grid = get_tree().get_root().get_node_or_null("Main/IsometricGrid")
	if grid and grid.has_signal("round_won"):
		if grid.is_connected("round_won", _on_grid_round_won):
			grid.disconnect("round_won", _on_grid_round_won)
		grid.connect("round_won", _on_grid_round_won)
	
	# Find challenge mode
	challenge_mode = get_node_or_null("/root/ChallengeMode")
	if not challenge_mode:
		var scene = get_tree().current_scene
		challenge_mode = scene.get_node_or_null("ChallengeMode")
		
	if challenge_mode:
		challenge_mode.connect("round_countdown_changed", _on_round_countdown_changed)
		challenge_mode.connect("challenge_toggled", _on_challenge_toggled)
		
	# Make sure countdown label is hidden and properly configured
	if countdown_label:
		countdown_label.visible = false
		countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	# Initialize UI
	update_turns_display()
	update_money_display()
	update_round_display()

# Check if the move is within range
func is_move_in_range(start_pos, end_pos):
	var distance = abs(start_pos.x - end_pos.x) + abs(start_pos.y - end_pos.y)
	return distance <= movement_range

# Request confirmation for a move
func request_move_confirmation(start_pos, end_pos, location_name = ""):
	# Store move data for later
	pending_move_data = {
		"start_pos": start_pos,
		"end_pos": end_pos,
		"location_name": location_name
	}
	
	# Calculate distance for this move
	var distance = abs(start_pos.x - end_pos.x) + abs(start_pos.y - end_pos.y)
	
	# Format move info with distance
	var move_text = "Move to "
	if location_name:
		move_text += location_name + " "
	move_text += "(" + str(distance) + " tiles)"
	
	# Update label if it exists
	if move_info_label:
		move_info_label.text = move_text
	
	# Show dialog
	show_move_dialog()

# Show the move confirmation dialog
func show_move_dialog():
	var dialog = get_node_or_null("MoveConfirmDialog")
	if dialog:
		dialog.visible = true

# Hide the move dialog
func hide_move_dialog():
	var dialog = get_node_or_null("MoveConfirmDialog")
	if dialog:
		dialog.visible = false

# Confirm the pending move
func confirm_move():
	if pending_move_data:
		emit_signal("movement_confirmed", true)
		hide_move_dialog()
		pending_move_data = null
		
# Cancel the pending move
func cancel_move():
	if pending_move_data:
		emit_signal("movement_confirmed", false)
		hide_move_dialog()
		pending_move_data = null

# Update the turns display
func update_turns_display():
	if turns_label:
		turns_label.text = str(turns_remaining)

# Update the money display
func update_money_display():
	if money_label:
		money_label.text = "$" + str(player_money)
	if total_money_label:
		total_money_label.text = "$" + str(total_money)

# Update the round display
func update_round_display():
	if round_label:
		round_label.text = "Round " + str(current_round)

# Set the player's starting position
func set_player_start_position(pos):
	player_start_position = pos
	
	# Initialize game manager with player starting position
	if game_manager:
		game_manager.update_player_position(pos, true)

# Add money to the player's balance
func add_money(amount):
	player_money += amount
	update_money_display()
	
	if game_manager:
		game_manager.current_money = player_money

# Show a notification
func show_notification(message, duration = 2.0):
	var notification = Label.new()
	notification.text = message
	notification.add_theme_font_size_override("font_size", 9)
	
	# Position in top right using absolute positioning
	var viewport_size = get_viewport().get_visible_rect().size
	notification.position = Vector2(viewport_size.x - 150, 10)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notification.modulate = Color(1, 1, 0) # Yellow color
	
	add_child(notification)
	
	# Create a tween to fade out the notification
	var tween = create_tween()
	tween.tween_property(notification, "modulate", Color(1, 1, 0, 0), duration)
	tween.tween_callback(notification.queue_free)

# Decrement the turns counter and check for game over
func consume_turn(player_current_pos):
	if turns_remaining > 0:
		turns_remaining -= 1
		update_turns_display()
		
		# Track if player has moved away from starting position
		if player_current_pos != player_start_position:
			player_has_moved = true
		# Check if player has returned to start (win condition)
		elif player_has_moved:
			# Player is back at start and has moved before - win condition!
			if game_manager:
				game_manager.check_win_condition(player_current_pos, player_has_moved)
				print("Win condition detected: Player back at starting position")
			return false
			
		# Check if out of turns - delegate to GameManager
		if turns_remaining == 0:
			if game_manager:
				game_manager.check_turns_remaining(turns_remaining)
			return false
	
	return turns_remaining > 0

# Decrement turns without checking for win condition - now the IsometricGrid handles that
func consume_turn_no_win_check(player_current_pos):
	if turns_remaining > 0:
		turns_remaining -= 1
		update_turns_display()
		
		# Check if out of turns - delegate to GameManager
		if turns_remaining == 0:
			if game_manager:
				game_manager.check_turns_remaining(turns_remaining)
			return false
	
	return turns_remaining > 0

# Handle round won event from the IsometricGrid
func _on_grid_round_won():
	# Delegate to game manager to handle the win
	if game_manager:
		game_manager.win_round(player_money)
	else:
		# Fallback if game manager not available
		print("Round won with money earned: ", player_money)
		show_notification("Round Won! You made it back safely with $%d" % player_money, 3.0)
		total_money += player_money
		update_money_display()

# Handle round won event from GameManager
func _on_round_won(money_earned):
	print("Round won with money earned: ", money_earned)
	
	# Show notification
	show_notification("Round Won! You made it back safely with $%d" % player_money, 3.0)
	
	# Update UI
	total_money += player_money
	update_money_display()

# Handle game over event from GameManager
func _on_game_manager_game_over(final_score):
	print("Game over signal received with final score: ", final_score)
	
	# Show the scoreboard
	if scoreboard:
		scoreboard.show_score(final_score)

# Reset the turns counter for a new game
func reset_turns():
	turns_remaining = DEFAULT_MAX_TURNS
	update_turns_display()

# Reset the entire game
func reset_game():
	if game_manager:
		game_manager.reset_game()
	else:
		# Fallback if game manager not available
		_on_game_reset()
		emit_signal("game_reset")

# Handle game reset from GameManager
func _on_game_reset():
	turns_remaining = DEFAULT_MAX_TURNS
	player_money = 0
	total_money = 0
	current_round = 1
	player_has_moved = false
	update_turns_display()
	update_money_display()
	update_round_display()

# Handle round reset from GameManager
func _on_round_reset():
	# Increment round count
	current_round += 1
	update_round_display()
	
	# Reset player money for next round
	player_money = 0
	update_money_display()
	
	# Reset turns
	reset_turns()
	
	# Reset player movement tracking
	player_has_moved = false

# Update turn limit based on challenge mode
func _update_turn_limit():
	if game_manager:
		game_manager._update_turn_limit()
		turns_remaining = game_manager.turn_limit
		update_turns_display()

# Handle when challenge mode is toggled
func _on_challenge_toggled(is_active: bool):
	_update_turn_limit()
	
	# Reset player movement tracking when challenge mode changes
	player_has_moved = false

# Handle turn start events
func _on_turn_started():
	# Update display
	update_turns_display()

# Handle turn end events
func _on_turn_ended():
	# Update display
	turns_remaining -= 1
	update_turns_display()

# Handle countdown updates
func _on_round_countdown_changed(count: int):
	if countdown_label:
		if count > 0:
			countdown_label.text = str(count)
			countdown_label.visible = true
		else:
			countdown_label.text = "GO!"
			# Create a quick fade out animation
			var tween = create_tween()
			tween.tween_property(countdown_label, "modulate", Color(1, 1, 1, 0), 0.5)
			tween.tween_callback(func():
				countdown_label.visible = false
				countdown_label.modulate = Color(1, 1, 1, 1)
			)
