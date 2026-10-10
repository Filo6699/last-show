extends RefCounted
## Dialogue graph transcribed from the team's Last show.pdf.
const SPEAKERS := {
	"richard": "РИЧАРД", "mordecai": "МОРДЕКАЙ", "bruno": "БРУНО",
	"elsa": "ЭЛЬЗА", "lili": "ЛИЛИ", "walter": "ДОКТОР ВАЛЬТЕР",
	"audience": "ЗРИТЕЛЬ", "narrator": "",
}
var sequences: Dictionary
var portraits: Dictionary = {}

func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/dialogues.json"))
	sequences = data["sequences"]
	portraits["mordecai"] = load("res://assets/ui/mordecai_dialogue.png")
	portraits["bruno"] = load("res://assets/characters/bruno_dialogue.png")
	portraits["lili"] = load("res://assets/characters/lili_dialogue.png")
	portraits["elsa"] = load("res://assets/characters/elsa_dialogue.png")

func get_sequence(id: String) -> Dictionary:
	return sequences.get(id, {})

func get_portrait(id: String) -> Texture2D:
	return portraits.get(id)
