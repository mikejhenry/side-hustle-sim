class_name Interactable
extends Node3D
## Something the player can use with [E]. The prompt callable returns "" when it isn't usable right now.

var prompt: Callable
var action: Callable
var radius := 2.2
var in_car := false   # usable while driving (otherwise on foot only)


func _ready() -> void:
	add_to_group("interactable")


func get_prompt() -> String:
	if prompt.is_valid():
		return prompt.call()
	return ""


func use() -> void:
	if action.is_valid():
		action.call()
