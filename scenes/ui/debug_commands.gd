extends Node

func _ready():
	# Register auto-load
	print("Debug commands initialized")

func _input(event):
	# Check for debug key combinations
	if event is InputEventKey and event.pressed:
		# P key - Test POI system
		if event.keycode == KEY_P and event.ctrl_pressed:
			print("Debug: Testing POI system")
			test_poi_system()
			
		# E key - Emit player moved signal
		if event.keycode == KEY_E and event.ctrl_pressed:
			print("Debug: Emitting player_moved signal")
			test_emit_player_moved()
			
		# M key - Test money reward
		if event.keycode == KEY_M and event.ctrl_pressed:
			print("Debug: Testing money reward")
			test_money_reward()

# Find and test the POI system
func test_poi_system():
	var main = get_tree().current_scene
	var grid = main.get_node_or_null("IsometricGrid")
	if grid:
		print("Found grid, testing POI system...")
		if grid.has_method("test_poi_system"):
			grid.test_poi_system()
		else:
			print("Grid doesn't have test_poi_system method")
	else:
		print("IsometricGrid not found!")

# Test emitting the player_moved signal
func test_emit_player_moved():
	var main = get_tree().current_scene
	var grid = main.get_node_or_null("IsometricGrid")
	if grid:
		print("Found grid, testing player_moved signal...")
		if grid.has_method("test_emit_player_moved"):
			grid.test_emit_player_moved()
		else:
			print("Grid doesn't have test_emit_player_moved method")
	else:
		print("IsometricGrid not found!")

# Test the money reward system directly
func test_money_reward():
	var main = get_tree().current_scene
	var main_ui = main.get_node_or_null("MainUI")
	if main_ui:
		print("Found MainUI, testing money reward...")
		if main_ui.has_method("_on_poi_collected"):
			# Test with a fixed reward amount of 50
			main_ui._on_poi_collected(50)
			print("Triggered money reward of $50")
		else:
			print("MainUI doesn't have _on_poi_collected method")
	else:
		print("MainUI not found!")