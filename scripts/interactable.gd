extends StaticBody3D
## Common contract: the player only needs prompt + interacted signal.
signal interacted(id: StringName)
@export var interaction_id: StringName
@export var prompt: String = "Interact"

func interact() -> void:
	interacted.emit(interaction_id)
