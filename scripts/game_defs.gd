class_name GameDefs
extends RefCounted
## Terrain and unit definitions for 二戰風雲錄 / WWII Tales.

const TERRAIN := {
	"clear": {"move": 1.0, "defense": 0, "blocks_los": false, "label": "平原"},
	"road": {"move": 1.0, "defense": 0, "blocks_los": false, "label": "道路"},
	"forest": {"move": 2.0, "defense": 2, "blocks_los": true, "label": "森林"},
	"hill": {"move": 2.0, "defense": 1, "blocks_los": false, "label": "丘陵"},
	"town": {"move": 2.0, "defense": 3, "blocks_los": false, "label": "城鎮"},
	"river": {"move": 3.0, "defense": 0, "blocks_los": false, "label": "河流"},
	"swamp": {"move": 2.0, "defense": 0, "blocks_los": false, "label": "沼澤"},
}

const UNIT_TYPES := {
	"infantry": {
		"cost": 2, "move": 4, "range": 1, "attack": 3, "hp": 4, "ammo": 4,
		"label": "步兵", "blurb": "森林與城鎮掩護好",
		"can_enter_forest": true, "vehicle": false, "sight": 4,
	},
	"recon": {
		"cost": 3, "move": 7, "range": 2, "attack": 2, "hp": 4, "ammo": 4,
		"label": "裝甲偵察", "blurb": "沿路便宜，火力弱",
		"can_enter_forest": false, "vehicle": true, "sight": 4,
	},
	"light_tank": {
		"cost": 4, "move": 6, "range": 2, "attack": 4, "hp": 5, "ammo": 4,
		"label": "輕戰車", "blurb": "禁入森林，行動快",
		"can_enter_forest": false, "vehicle": true, "sight": 4,
	},
	"medium_tank": {
		"cost": 5, "move": 5, "range": 2, "attack": 6, "hp": 5, "ammo": 4,
		"label": "中型戰車", "blurb": "禁入森林，主力戰車",
		"can_enter_forest": false, "vehicle": true, "sight": 4,
	},
	"heavy_tank": {
		"cost": 7, "move": 3, "range": 2, "attack": 8, "hp": 6, "ammo": 3,
		"label": "重戰車", "blurb": "克制戰車，行動慢",
		"can_enter_forest": false, "vehicle": true, "sight": 4,
		"bonus_vs": ["light_tank", "medium_tank", "heavy_tank", "recon"],
		"bonus_attack": 2,
	},
	"artillery": {
		"cost": 4, "move": 2, "range": 5, "min_range": 2, "attack": 5, "hp": 4, "ammo": 3,
		"label": "火砲", "blurb": "間接砲，隣接攻擊2",
		"can_enter_forest": true, "vehicle": false, "sight": 4,
		"adjacent_attack": 2,
	},
	"engineer": {
		"cost": 3, "move": 3, "range": 1, "attack": 2, "hp": 4, "ammo": 4,
		"label": "工兵", "blurb": "過河耗2，助車過河",
		"can_enter_forest": true, "vehicle": false, "sight": 4,
	},
}

const MAX_ROUNDS := 5
const DEPLOY_DEPTH := 2
const SIGHT_RANGE := 4
const HILL_SIGHT_BONUS := 1
## One side, in order. Header uses these Traditional Chinese names.
const SIDE_PHASE_LABELS: Array[String] = ["砲擊階段", "移動階段", "直接射擊"]
const CUSTOM_COLS := 24
const CUSTOM_ROWS := 16
const CUSTOM_POINTS := 24
const CUSTOM_MAP_PATH := "user://custom_map.json"

## Width and height are each multiplied from level 1, not the area.
## Points are the buy budget for each side. Maps are built in code.
const LEVELS := [
	{"id": 1, "cols": 16, "rows": 10, "points": 18},
	{"id": 2, "cols": 32, "rows": 20, "points": 28},
	{"id": 3, "cols": 32, "rows": 20, "points": 36},
	{"id": 4, "cols": 64, "rows": 40, "points": 48},
	{"id": 5, "cols": 64, "rows": 40, "points": 60},
	{"id": 6, "cols": 80, "rows": 50, "points": 72},
]

static var level_index := 1
static var MAP_COLS := 16
static var MAP_ROWS := 10
static var BUY_POINTS := 18
static var town_list: Array[Vector2i] = []

const TEAM_ALLIES := "allies"
const TEAM_AXIS := "axis"

const TEAM_LABEL := {
	TEAM_ALLIES: "盟軍",
	TEAM_AXIS: "軸心",
}

const TEAM_TINT := {
	TEAM_ALLIES: Color(0.55, 1.0, 0.55, 1.0),
	TEAM_AXIS: Color(1.0, 0.45, 0.45, 1.0),
}

const TEAM_RING := {
	TEAM_ALLIES: Color(0.25, 0.85, 0.35, 0.95),
	TEAM_AXIS: Color(0.95, 0.25, 0.25, 0.95),
}


static func level_spec(index: int) -> Dictionary:
	var i := clampi(index, 1, LEVELS.size()) - 1
	return LEVELS[i]


static func apply_level(index: int) -> void:
	var spec := level_spec(index)
	level_index = int(spec["id"])
	MAP_COLS = int(spec["cols"])
	MAP_ROWS = int(spec["rows"])
	BUY_POINTS = int(spec["points"])


static func town_quota(cols: int, rows: int) -> int:
	return maxi(2, int(cols * rows / 40))


static func deploy_cols(team: String) -> Array:
	# Allies enter from the left edge; Axis from the right edge. Depth is two columns.
	var cols: Array = []
	if team == TEAM_ALLIES:
		for i in DEPLOY_DEPTH:
			cols.append(i)
	else:
		for i in DEPLOY_DEPTH:
			cols.append(MAP_COLS - DEPLOY_DEPTH + i)
	return cols


static func build_map() -> Array:
	var rows: Array = _authored_level_one() if level_index <= 1 else _generate_map(MAP_COLS, MAP_ROWS, level_index)
	_ensure_swamp(rows, MAP_COLS, MAP_ROWS)
	_cache_towns(rows)
	return rows


static func generate_battle_map(cols: int, rows: int, seed_level: int) -> Array:
	var grid := _generate_map(cols, rows, seed_level)
	_ensure_swamp(grid, cols, rows)
	return grid


static func use_custom_grid(grid: Array) -> void:
	MAP_ROWS = grid.size()
	MAP_COLS = (grid[0] as Array).size()
	BUY_POINTS = CUSTOM_POINTS
	_cache_towns(grid)


static func cache_towns(rows: Array) -> void:
	_cache_towns(rows)


static func _cache_towns(rows: Array) -> void:
	town_list.clear()
	for r in rows.size():
		var row: Array = rows[r]
		for c in row.size():
			if str(row[c]) == "town":
				town_list.append(Vector2i(int(c), int(r)))


static func _authored_level_one() -> Array:
	# 16x10 hand-authored. Allies = leftmost columns, Axis = rightmost columns.
	# Vertical river (col 7) with two road bridges; east-west road on row 2; three towns.
	var rows := [
		["clear", "clear", "forest", "hill", "swamp", "clear", "forest", "river", "hill", "swamp", "forest", "clear", "clear", "hill", "clear", "clear"],
		["clear", "hill", "clear", "clear", "forest", "hill", "clear", "river", "clear", "forest", "clear", "hill", "clear", "clear", "clear", "clear"],
		["road", "road", "road", "road", "road", "road", "road", "road", "road", "road", "road", "road", "road", "road", "road", "road"],
		["clear", "clear", "hill", "forest", "swamp", "clear", "hill", "river", "swamp", "clear", "forest", "town", "clear", "forest", "clear", "hill"],
		["forest", "clear", "clear", "clear", "town", "hill", "clear", "river", "forest", "clear", "hill", "clear", "clear", "clear", "clear", "clear"],
		["clear", "clear", "forest", "hill", "swamp", "clear", "forest", "river", "clear", "hill", "clear", "clear", "forest", "clear", "hill", "clear"],
		["road", "road", "road", "road", "clear", "road", "road", "road", "road", "road", "road", "clear", "road", "road", "road", "road"],
		["hill", "clear", "clear", "forest", "clear", "town", "clear", "river", "hill", "forest", "clear", "clear", "hill", "clear", "clear", "clear"],
		["clear", "clear", "hill", "clear", "forest", "swamp", "clear", "river", "clear", "swamp", "forest", "hill", "clear", "forest", "clear", "clear"],
		["clear", "clear", "clear", "clear", "hill", "clear", "forest", "river", "clear", "clear", "clear", "forest", "hill", "clear", "clear", "clear"],
	]
	return rows


static func _generate_map(cols: int, rows: int, level: int) -> Array:
	# Procedural. No stored art per level. River sits between the deploy edges,
	# one or two roads run left to right (bridges where they cross the river),
	# towns are about one per 40 hexes. Some clear hexes become swamp.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1800 + level * 131
	var grid: Array = []
	for r in rows:
		var row: Array = []
		row.resize(cols)
		for c in cols:
			row[c] = "clear"
		grid.append(row)
	var road_rows: Array[int] = []
	road_rows.append(clampi(int(rows / 5), 1, rows - 2))
	if rows >= 16:
		var second := clampi(int(rows * 3 / 5), 1, rows - 2)
		if second != road_rows[0]:
			road_rows.append(second)
	var mid := int(cols / 2)
	for r in rows:
		if r in road_rows:
			continue
		for c in range(DEPLOY_DEPTH, cols - DEPLOY_DEPTH):
			if absi(c - mid) <= 1:
				continue
			var roll := rng.randi() % 100
			if roll < 14:
				grid[r][c] = "forest"
			elif roll < 24:
				grid[r][c] = "hill"
			elif roll < 34:
				grid[r][c] = "swamp"
	for r in rows:
		if r in road_rows:
			continue
		var wobble := int(round(sin(float(r) * 0.47 + float(level) * 0.8) * 1.35))
		var c := clampi(mid + wobble, DEPLOY_DEPTH + 1, cols - DEPLOY_DEPTH - 2)
		grid[r][c] = "river"
	for r in road_rows:
		for c in cols:
			grid[r][c] = "road"
	_stamp_towns(grid, cols, rows, level)
	_ensure_swamp(grid, cols, rows)
	return grid


static func _ensure_swamp(grid: Array, cols: int, rows: int) -> void:
	for r in rows:
		for c in cols:
			if str(grid[r][c]) == "swamp":
				return
	var r0 := 1 if rows > 2 else 0
	var r1 := rows - 1 if rows > 2 else rows
	for r in range(r0, r1):
		for c in range(DEPLOY_DEPTH, cols - DEPLOY_DEPTH):
			if str(grid[r][c]) == "clear":
				grid[r][c] = "swamp"
				return


static func _stamp_towns(grid: Array, cols: int, rows: int, level: int) -> void:
	var target := town_quota(cols, rows)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5200 + level * 89
	var spots: Array[Vector2i] = []
	for r in range(1, rows - 1):
		for c in range(DEPLOY_DEPTH, cols - DEPLOY_DEPTH):
			var tid := str(grid[r][c])
			if tid == "river" or tid == "road":
				continue
			spots.append(Vector2i(c, r))
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Vector2i = spots[i]
		spots[i] = spots[j]
		spots[j] = swap
	var chosen: Array[Vector2i] = []
	var min_dist := 4
	if target >= 30:
		min_dist = 3
	if target >= 80:
		min_dist = 2
	for s in spots:
		if chosen.size() >= target:
			break
		var ok := true
		for ch in chosen:
			if absi(ch.x - s.x) + absi(ch.y - s.y) < min_dist:
				ok = false
				break
		if ok:
			chosen.append(s)
	if chosen.size() < target:
		for s in spots:
			if chosen.size() >= target:
				break
			var seen := false
			for ch in chosen:
				if ch == s:
					seen = true
					break
			if not seen:
				chosen.append(s)
	var mid := int(cols / 2)
	_balance_town_sides(chosen, spots, mid)
	for ch in chosen:
		grid[ch.y][ch.x] = "town"


static func _balance_town_sides(chosen: Array[Vector2i], spots: Array[Vector2i], mid: int) -> void:
	var left_n := 0
	var right_n := 0
	for ch in chosen:
		if ch.x < mid:
			left_n += 1
		elif ch.x > mid:
			right_n += 1
	if left_n > 0 and right_n > 0:
		return
	var need_left := left_n == 0
	for s in spots:
		var on_side := s.x < mid if need_left else s.x > mid
		if not on_side:
			continue
		var taken := false
		for ch in chosen:
			if ch == s:
				taken = true
				break
		if taken:
			continue
		for i in chosen.size():
			var ch: Vector2i = chosen[i]
			var other := ch.x > mid if need_left else ch.x < mid
			if other:
				chosen[i] = s
				return
		return


static func starting_hp(type_id: String) -> int:
	return int(UNIT_TYPES[type_id]["hp"])


static func starting_ammo(type_id: String) -> int:
	return int(UNIT_TYPES[type_id]["ammo"])


static func unit_type_ids() -> Array[String]:
	return ["infantry", "recon", "light_tank", "medium_tank", "heavy_tank", "artillery", "engineer"]


static func is_vehicle(type_id: String) -> bool:
	return bool(UNIT_TYPES[type_id].get("vehicle", false))


static func sight_range(type_id: String, on_hill: bool) -> int:
	var sight := int(UNIT_TYPES[type_id].get("sight", SIGHT_RANGE))
	if on_hill:
		sight += HILL_SIGHT_BONUS
	return sight


## Cost to enter one hex. Negative means blocked.
## Road is 1 for foot, vehicles, and towed guns (no extra, no half-cost).
## River is a road bridge when the hex itself is road, not river.
static func enter_cost(type_id: String, terrain_id: String, engineer_help: bool = false) -> float:
	var vehicle := is_vehicle(type_id)
	if terrain_id == "forest":
		if vehicle or not bool(UNIT_TYPES[type_id].get("can_enter_forest", false)):
			return -1.0
		return float(TERRAIN["forest"]["move"])
	if terrain_id == "river":
		if type_id == "engineer":
			return 2.0
		if vehicle:
			return 2.0 if engineer_help else -1.0
		return 3.0
	if terrain_id == "swamp":
		return 4.0 if vehicle else 2.0
	if terrain_id == "road":
		return 1.0
	if not TERRAIN.has(terrain_id):
		return -1.0
	return float(TERRAIN[terrain_id]["move"])


static func save_map_file(grid: Array, path: String = CUSTOM_MAP_PATH) -> bool:
	var rows: Array = []
	for row in grid:
		var cells: Array = []
		for cell in row:
			cells.append(str(cell))
		rows.append(cells)
	if rows.is_empty():
		return false
	var width := (rows[0] as Array).size()
	var height := rows.size()
	# width / height / terrain are the file contract. cols / rows / grid stay so older readers still open it.
	var payload := {
		"width": width,
		"height": height,
		"terrain": rows,
		"cols": width,
		"rows": height,
		"grid": rows,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload))
	f.close()
	return true


static func has_custom_map(path: String = CUSTOM_MAP_PATH) -> bool:
	return not load_map_file(path).is_empty()


static func load_map_file(path: String = CUSTOM_MAP_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var dict := data as Dictionary
	var grid = dict.get("terrain", [])
	if typeof(grid) != TYPE_ARRAY or (grid as Array).is_empty():
		grid = dict.get("grid", [])
	if typeof(grid) != TYPE_ARRAY or (grid as Array).is_empty():
		return []
	var out: Array = []
	var width := -1
	for row in grid:
		if typeof(row) != TYPE_ARRAY:
			return []
		var cells: Array = []
		for cell in row:
			var id := str(cell)
			if not TERRAIN.has(id):
				id = "clear"
			cells.append(id)
		if width < 0:
			width = cells.size()
		if cells.size() != width or width < 4:
			return []
		out.append(cells)
	if out.size() < 4:
		return []
	return out


static func cpu_roster() -> Array[String]:
	return cpu_purchase(BUY_POINTS)


static func cpu_purchase(points: int) -> Array[String]:
	# Mixed force. Spends the budget; leftover is smaller than the cheapest unit.
	var pattern: Array[String] = ["medium_tank", "artillery", "light_tank", "engineer", "recon", "heavy_tank", "infantry"]
	var out: Array[String] = []
	var left := points
	var i := 0
	var stalls := 0
	while left >= 2 and stalls < pattern.size():
		var id: String = pattern[i % pattern.size()]
		i += 1
		var cost := int(UNIT_TYPES[id]["cost"])
		if cost <= left:
			out.append(id)
			left -= cost
			stalls = 0
		else:
			stalls += 1
	while left >= 2:
		out.append("infantry")
		left -= 2
	return out
