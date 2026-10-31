extends RefCounted
## Story coordinates for the supplied October Layout; source units are metres.
const ID := "supplied-october-2026-full-scenario-v1"
const TRUNK := Vector3(0,.85,0)
# Curtain at the backstage end of the dressing passage.
const DRESSING_GATE := Vector3(-22.63,1.4,34.32)
const TECHNICAL_GATE := Vector3(-20,1.4,46)
const DRESSING_YAW := -2.677945
const MIRROR := Vector3(-46.7,1.45,31.45)
const SERVICE_X := -20.0
const SERVICE_START := 46.0
const CLINIC_START := 54.0
const CLINIC_CENTER := Vector3(-20,.05,57)
const PHOTOS := Vector3(-16.75,1.6,57)
const WALTER_WAIT := Vector3(-21.5, .95, 58.0)
const ARENA_MORDECAI := Vector3(-12,1.25,29)
const HALL_MORDECAI := Vector3(-14,1.25,24)
const BRUNO := Vector3(-16,1.55,22)
const ELSA_DRESSING := Vector3(-45,2.1,39.5)
const ELSA_HALL := Vector3(-20,2.6,42)
const LILI := Vector3(-1.4,1.2,1.3)

static func vanity_meshes(model: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D]=[]
	for node in model.find_children("*","MeshInstance3D",true,false):
		if not node.mesh or not String(node.name).begins_with("vanity_table"):continue
		for index in node.mesh.get_surface_count():
			var material:Material=node.get_active_material(index)
			if material and material.resource_name.begins_with("Clouded_mirror"):
				result.append(node);break
	return result

static func in_passage(p: Vector3) -> bool:
	var offset := Vector2(p.x+28,p.z-37)
	var along := offset.dot(Vector2(-.894427,.447214))
	var across := offset.dot(Vector2(-.447214,-.894427))
	# The passage starts at its curtain (DRESSING_GATE, along -6).
	return along >= -6 and along <= 16 and absf(across)<1.8

static func room_at(p: Vector3) -> String:
	if p.z>=CLINIC_START and p.z<=CLINIC_START+6 and p.x>=SERVICE_X-3.6 and p.x<=SERVICE_X+3.4:return "clinic"
	if p.z>=SERVICE_START and p.z<CLINIC_START and absf(p.x-SERVICE_X)<=1.4:return "service"
	if Vector2(p.x+48.1356,p.z-40.1154).length()<10.2 or in_passage(p):return "dressing"
	return "arena"

static func contains(p: Vector3) -> bool:
	return Vector2(p.x,p.z).length()<50.3 or Vector2(p.x+48.1356,p.z-40.1154).length()<10.25 or in_passage(p) or (p.x>=-44 and p.x<=-16 and p.z>=37 and p.z<=59) or room_at(p) in ["service","clinic"]

static func safe_position(phase: String) -> Vector3:
	if phase=="roof":return Vector3(-10,40.02,-18)
	if phase in ["home","bathroom"]:return Vector3(155,.05,1.8)
	if phase=="intro": return Vector3(0,.36,-5.8)
	if phase=="lili":return Vector3(-3,.05,3)
	if phase in ["bruno","elsa_hall","to_technical"]: return Vector3(SERVICE_X,.05,38)
	if phase in ["mirror","elsa_dressing","to_hall"]:return Vector3(-48,.05,40)
	if phase in ["technical","photos","walter","contract","roof_key","trapped","complete"]:return CLINIC_CENTER
	return Vector3(-14,.05,28)
