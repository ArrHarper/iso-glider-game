# mode_manager.gd
extends Node

signal mode_changed(old_mode, new_mode)

var current_mode = null
var mode_scenes = {
    "base": "res://modes/base_mode/base_mode.tscn",
    "time_limited": "res://modes/time_limited/time_limited.tscn",
    # Add more modes as you develop them
}

# Mode-specific configuration resources
var mode_configs = {}

func _ready():
    # Preload all mode configs
    for mode_key in mode_scenes.keys():
        var config_path = "res://modes/%s/%s_config.tres" % [mode_key, mode_key]
        if ResourceLoader.exists(config_path):
            mode_configs[mode_key] = load(config_path)

func change_mode(mode_name):
    if not mode_scenes.has(mode_name):
        printerr("Mode '%s' does not exist!" % mode_name)
        return false
        
    var old_mode = current_mode
    current_mode = mode_name
    
    # Free the current scene and load the new one
    get_tree().change_scene(mode_scenes[mode_name])
    
    # Emit signal after scene is changed
    call_deferred("emit_signal", "mode_changed", old_mode, current_mode)
    return true
    
func get_mode_config(mode_name = ""):
    if mode_name == "":
        mode_name = current_mode
        
    if mode_configs.has(mode_name):
        return mode_configs[mode_name]
    return null