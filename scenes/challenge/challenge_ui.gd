extends CanvasLayer

@onready var timer_label = %TimerLabel
@onready var challenge_button = %ChallengeButton
@onready var panel = $Panel

var challenge_mode = null

func _ready():
	# Check if UI elements exist before using them
	if !timer_label or !challenge_button or !panel:
		push_error("ChallengeUI: Required UI elements not found!")
		return
		
	# Connect button signal
	challenge_button.pressed.connect(_on_challenge_button_pressed)
	
	# Look for challenge mode
	challenge_mode = get_node_or_null("/root/ChallengeMode")
	
	if not challenge_mode:
		# Try to find challenge mode in the current scene
		challenge_mode = get_tree().current_scene.get_node_or_null("ChallengeMode")
	
	# If we still don't have it, something is wrong
	if not challenge_mode:
		push_error("Could not find ChallengeMode node!")
		timer_label.hide()
		return
	
	# Connect signals
	challenge_mode.challenge_toggled.connect(_on_challenge_toggled)
	challenge_mode.time_changed.connect(_on_time_changed)
	
	# Initial UI state
	_update_button_text(challenge_mode.is_active)
	if timer_label:
		timer_label.text = challenge_mode.get_formatted_time()
		timer_label.visible = challenge_mode.is_active && challenge_mode.enable_timer
	
	# Position panel exactly below TurnsPanel
	await get_tree().process_frame
	var turns_panel = get_node_or_null("/root/Main/MainUI/TurnsPanel")
	if turns_panel and panel:
		panel.position.y = turns_panel.position.y + turns_panel.size.y + 5
		print("Positioned ChallengeUI panel at y:", panel.position.y)
		print("TurnsPanel bottom position:", turns_panel.position.y + turns_panel.size.y)
	else:
		print("Could not find TurnsPanel to position ChallengeUI")

func _on_challenge_button_pressed():
	if challenge_mode:
		challenge_mode.toggle_challenge_mode()

func _on_challenge_toggled(is_active: bool):
	_update_button_text(is_active)
	if timer_label and challenge_mode:
		timer_label.visible = is_active && challenge_mode.enable_timer

func _on_time_changed(time_left: float):
	if challenge_mode and timer_label:
		timer_label.text = challenge_mode.get_formatted_time()
		
		# Change color based on time remaining
		if time_left <= 3.0:
			timer_label.add_theme_color_override("font_color", Color.RED)
		elif time_left <= 5.0:
			timer_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			timer_label.add_theme_color_override("font_color", Color.GREEN)

func _update_button_text(is_active: bool):
	if challenge_button:
		if is_active:
			challenge_button.text = "Disable"
		else:
			challenge_button.text = "Enable"