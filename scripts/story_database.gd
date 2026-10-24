extends RefCounted
## Story dialogue graph.
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
	portraits["mordecai"] = load("res://assets/characters/colored/mordecai.png")
	portraits["bruno"] = load("res://assets/characters/colored/bruno.png")
	portraits["lili"] = load("res://assets/characters/colored/lili.png")
	portraits["elsa"] = load("res://assets/characters/colored/elsa.png")
	portraits["walter"] = load("res://assets/characters/colored/walter.png")
	# Fraction from the crown to the upper thighs in each supplied full-body PNG.
	# Keep framing with the artwork, including lines that override the speaker.
	for id in ["mordecai", "bruno", "lili", "walter"]:
		portraits[id].set_meta("dialogue_hip_fraction", {"mordecai": 0.72, "bruno": 0.60, "lili": 0.55, "walter": 0.57}[id])
		portraits[id].set_meta("dialogue_height", 0.82 if id == "lili" else 1.0)

func get_sequence(id: String) -> Dictionary:
	return sequences.get(id, {})

func get_portrait(id: String) -> Texture2D:
	return portraits.get(id)

func speaker_name(id: String, name_seen: bool) -> String:
	if id == "richard" and not name_seen: return "Я"
	return SPEAKERS.get(id, "")

func preceding_portrait(sequence: String, node: String) -> String:
	# Recover old saves made during a reply, before portrait context was saved.
	# Walk backwards to the closest interlocutor on each path; ambiguous paths
	# deliberately return no sprite rather than inventing who is present.
	var nodes: Dictionary = get_sequence(sequence).get("nodes", {})
	var pending: Array = [node]
	var visited: Dictionary = {}
	var found: Dictionary = {}
	while not pending.is_empty():
		var current: String = pending.pop_front()
		if visited.has(current): continue
		visited[current] = true
		var entry: Dictionary = nodes.get(current, {})
		var who: String = entry.get("speaker", "narrator")
		if entry.has("portrait") or who not in ["richard", "narrator"]:
			var id: String = entry.get("portrait", who)
			found[id if portraits.has(id) else ""] = true
			continue
		for previous in nodes:
			var line: Dictionary = nodes[previous]
			if not line.has("choices") and line.get("next", "end") == current: pending.append(previous)
			for choice in line.get("choices", []):
				if choice.next == current: pending.append(previous)
	return str(found.keys()[0]) if found.size() == 1 else ""

func get_photo(id: String, before: bool) -> Texture2D:
	var path := "res://assets/story/photos/" + id + ("_before.webp" if before else "_after.webp")
	return load(path) if ResourceLoader.exists(path) else null
