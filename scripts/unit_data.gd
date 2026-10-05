class_name UnitData
extends RefCounted

var id: int
var type_id: String
var team: String  # "allies" | "axis"
var col: int
var row: int
var moved: bool = false
var shot: bool = false
var damaged: bool = false
var destroyed: bool = false
var max_hp: int = 1
var hp: int = 1
var max_ammo: int = 0
var ammo: int = 0

func _init(p_id: int, p_type: String, p_team: String, p_col: int, p_row: int) -> void:
	id = p_id
	type_id = p_type
	team = p_team
	col = p_col
	row = p_row
	max_hp = GameDefs.starting_hp(p_type)
	hp = max_hp
	max_ammo = GameDefs.starting_ammo(p_type)
	ammo = max_ammo

func def() -> Dictionary:
	return GameDefs.UNIT_TYPES[type_id]

func label() -> String:
	return str(def()["label"])

func max_move() -> int:
	return int(def()["move"])

func base_attack() -> int:
	return int(def()["attack"])

func current_attack_vs(target: UnitData) -> int:
	var a := base_attack()
	if target == null:
		return a
	if type_id == "artillery":
		var dist := HexUtils.axial_distance(Vector2i(col, row), Vector2i(target.col, target.row))
		if dist <= 1:
			return int(def().get("adjacent_attack", 2))
	var bonus: Array = def().get("bonus_vs", [])
	if target.type_id in bonus:
		a += int(def().get("bonus_attack", 0))
	return a


func min_range() -> int:
	return int(def().get("min_range", 1))


func max_range() -> int:
	return int(def()["range"])

func base_range() -> int:
	return int(def()["range"])

func can_enter_forest() -> bool:
	return bool(def()["can_enter_forest"])

func river_mode() -> String:
	return str(def().get("river_mode", "none"))

func hill_range_bonus() -> int:
	return int(def().get("hill_range_bonus", 1))

func has_ammo() -> bool:
	return ammo > 0 and not destroyed

func spend_shot() -> bool:
	if destroyed or ammo <= 0:
		return false
	ammo -= 1
	shot = true
	return true

## One damaging hit. Returns true when HP reaches 0 and the unit is destroyed.
func take_hit() -> bool:
	if destroyed:
		return true
	hp -= 1
	if hp <= 0:
		hp = 0
		destroyed = true
		damaged = false
		return true
	damaged = hp < max_hp
	return false

func reset_turn_flags() -> void:
	moved = false
	shot = false
