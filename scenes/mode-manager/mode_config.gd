# create a mode_config.gd for each game mode
extends Resource
class_name ModeConfig

@export var mode_name: String = ""
@export var turn_limit: int = -1 # -1 for unlimited
@export var permadeath: bool = false
@export var fog_of_war: bool = true
@export var grid_size: Vector2 = Vector2(8, 8)
@export var starting_resources: Dictionary = {}
# Add any other configuration parameters