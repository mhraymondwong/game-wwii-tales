extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var d := HexUtils.axial_distance(Vector2i(0, 0), Vector2i(1, 0))
	assert(d == 1)
	# Seven units. A damaging hit is -1 HP. Heavy tanks hit other armor harder.
	var specs := {
		"infantry": {"cost": 2, "move": 4, "attack": 3, "range": 1, "min_range": 1, "hp": 4, "ammo": 4, "label": "步兵"},
		"recon": {"cost": 3, "move": 7, "attack": 2, "range": 2, "min_range": 1, "hp": 4, "ammo": 4, "label": "裝甲偵察"},
		"light_tank": {"cost": 4, "move": 6, "attack": 4, "range": 2, "min_range": 1, "hp": 5, "ammo": 4, "label": "輕戰車"},
		"medium_tank": {"cost": 5, "move": 5, "attack": 6, "range": 2, "min_range": 1, "hp": 5, "ammo": 4, "label": "中型戰車"},
		"heavy_tank": {"cost": 7, "move": 3, "attack": 8, "range": 2, "min_range": 1, "hp": 6, "ammo": 3, "label": "重戰車"},
		"artillery": {"cost": 4, "move": 2, "attack": 5, "range": 5, "min_range": 2, "hp": 4, "ammo": 3, "label": "火砲"},
		"engineer": {"cost": 3, "move": 3, "attack": 2, "range": 1, "min_range": 1, "hp": 4, "ammo": 4, "label": "工兵"},
	}
	assert(GameDefs.unit_type_ids().size() == 7)
	assert(GameDefs.unit_type_ids() == ["infantry", "recon", "light_tank", "medium_tank", "heavy_tank", "artillery", "engineer"])
	for id in specs:
		var want: Dictionary = specs[id]
		var got: Dictionary = GameDefs.UNIT_TYPES[id]
		assert(int(got["cost"]) == int(want["cost"]))
		assert(int(got["move"]) == int(want["move"]))
		assert(int(got["attack"]) == int(want["attack"]))
		assert(int(got["range"]) == int(want["range"]))
		assert(int(got.get("min_range", 1)) == int(want["min_range"]))
		assert(GameDefs.starting_hp(id) == int(want["hp"]))
		assert(GameDefs.starting_ammo(id) == int(want["ammo"]))
		assert(str(got["label"]) == str(want["label"]))
		var unit := UnitData.new(1, id, "allies", 0, 0)
		assert(unit.hp == int(want["hp"]) and unit.ammo == int(want["ammo"]))
	var heavy := UnitData.new(1, "heavy_tank", "axis", 0, 0)
	var light := UnitData.new(2, "light_tank", "allies", 2, 0)
	var med := UnitData.new(3, "medium_tank", "allies", 2, 1)
	var recon := UnitData.new(4, "recon", "allies", 3, 0)
	var foot := UnitData.new(5, "infantry", "allies", 1, 0)
	var art := UnitData.new(6, "artillery", "axis", 0, 0)
	var art_far := UnitData.new(7, "infantry", "allies", 4, 0)
	assert(heavy.current_attack_vs(light) == 10)
	assert(heavy.current_attack_vs(med) == 10)
	assert(heavy.current_attack_vs(heavy) == 10)
	assert(heavy.current_attack_vs(recon) == 10)
	assert(heavy.current_attack_vs(foot) == 8)
	assert(art.current_attack_vs(foot) == 2)
	assert(HexUtils.axial_distance(Vector2i(art.col, art.row), Vector2i(art_far.col, art_far.row)) == 4)
	assert(art.current_attack_vs(art_far) == 5)
	assert(not foot.take_hit())
	assert(foot.hp == 3 and foot.damaged)
	assert(foot.take_hit() == false)
	assert(foot.take_hit() == false)
	assert(foot.take_hit())
	assert(foot.destroyed and foot.hp == 0)
	assert(med.spend_shot() and med.ammo == 3)
	# Swamp, forest, river, road.
	assert(GameDefs.enter_cost("infantry", "swamp", false) == 2.0)
	assert(GameDefs.enter_cost("engineer", "swamp", false) == 2.0)
	assert(GameDefs.enter_cost("artillery", "swamp", false) == 2.0)
	assert(GameDefs.enter_cost("recon", "swamp", false) == 4.0)
	assert(GameDefs.enter_cost("light_tank", "swamp", false) == 4.0)
	assert(GameDefs.enter_cost("medium_tank", "swamp", false) == 4.0)
	assert(GameDefs.enter_cost("heavy_tank", "swamp", false) == 4.0)
	assert(GameDefs.enter_cost("infantry", "forest", false) == 2.0)
	assert(GameDefs.enter_cost("artillery", "forest", false) == 2.0)
	assert(GameDefs.enter_cost("light_tank", "forest", false) < 0.0)
	assert(GameDefs.enter_cost("recon", "forest", false) < 0.0)
	assert(GameDefs.enter_cost("engineer", "river", false) == 2.0)
	assert(GameDefs.enter_cost("infantry", "river", false) == 3.0)
	assert(GameDefs.enter_cost("artillery", "river", false) == 3.0)
	assert(GameDefs.enter_cost("medium_tank", "river", false) < 0.0)
	assert(GameDefs.enter_cost("medium_tank", "river", true) == 2.0)
	assert(GameDefs.enter_cost("heavy_tank", "road", false) == 1.0)
	assert(GameDefs.enter_cost("artillery", "road", false) == 1.0)
	assert(GameDefs.enter_cost("recon", "road", false) == 1.0)
	assert(int(GameDefs.TERRAIN["swamp"]["defense"]) == 0)
	assert(int(GameDefs.TERRAIN["town"]["defense"]) == 3)
	assert(int(GameDefs.TERRAIN["forest"]["defense"]) == 2)
	assert(GameDefs.sight_range("infantry", false) == 4)
	assert(GameDefs.sight_range("artillery", true) == 5)
	assert(GameDefs.SIDE_PHASE_LABELS == ["砲擊階段", "移動階段", "直接射擊"])
	# Six levels keep their sizes. Every map includes swamp.
	assert(GameDefs.MAX_ROUNDS == 5)
	assert(GameDefs.LEVELS.size() == 6)
	var table := [
		[1, 16, 10, 18],
		[2, 32, 20, 28],
		[3, 32, 20, 36],
		[4, 64, 40, 48],
		[5, 64, 40, 60],
		[6, 80, 50, 72],
	]
	for spec in table:
		var level := int(spec[0])
		var cols := int(spec[1])
		var rows_n := int(spec[2])
		var points := int(spec[3])
		GameDefs.apply_level(level)
		assert(GameDefs.level_index == level)
		assert(GameDefs.MAP_COLS == cols)
		assert(GameDefs.MAP_ROWS == rows_n)
		assert(GameDefs.BUY_POINTS == points)
		var m: Array = GameDefs.build_map()
		assert(m.size() == rows_n)
		assert((m[0] as Array).size() == cols)
		var allies: Array = GameDefs.deploy_cols(GameDefs.TEAM_ALLIES)
		var axis: Array = GameDefs.deploy_cols(GameDefs.TEAM_AXIS)
		assert(allies == [0, 1])
		assert(axis == [cols - 2, cols - 1])
		var towns := 0
		var river_mid := 0
		var full_road := false
		var left_towns := 0
		var right_towns := 0
		var swamps := 0
		var mid := int(cols / 2)
		for row in m:
			var cells: Array = row
			towns += cells.count("town")
			swamps += cells.count("swamp")
			if cells[0] == "road" and cells[cols - 1] == "road" and cells.count("road") == cols:
				full_road = true
			var river_here := false
			for c in cols:
				if str(cells[c]) == "town":
					if c < mid:
						left_towns += 1
					elif c > mid:
						right_towns += 1
				if str(cells[c]) == "river" and absi(c - mid) <= 2:
					river_here = true
				if c < 2 or c >= cols - 2:
					assert(str(cells[c]) != "river")
			if river_here:
				river_mid += 1
		assert(swamps >= 1)
		assert(towns >= 2)
		assert(left_towns >= 1 and right_towns >= 1)
		if level == 1:
			assert(river_mid >= 8)
		else:
			assert(towns == GameDefs.town_quota(cols, rows_n))
			assert(river_mid >= rows_n - 3)
		assert(full_road)
		var roster: Array[String] = GameDefs.cpu_purchase(points)
		var spent := 0
		var kinds := {}
		for id in roster:
			spent += int(GameDefs.UNIT_TYPES[id]["cost"])
			kinds[id] = true
		assert(spent <= points)
		assert(points - spent < 2)
		assert(kinds.size() >= 4)
		assert(kinds.has("infantry"))
		assert(kinds.has("medium_tank"))
		print("LEVEL %d %dx%d points=%d towns=%d swamp=%d spent=%d" % [level, cols, rows_n, points, towns, swamps, spent])
	GameDefs.apply_level(1)
	var roster1: Array[String] = GameDefs.cpu_roster()
	assert(roster1 == ["medium_tank", "artillery", "light_tank", "engineer", "infantry"])
	var custom: Array = GameDefs.generate_battle_map(GameDefs.CUSTOM_COLS, GameDefs.CUSTOM_ROWS, 24)
	assert(custom.size() == 16 and (custom[0] as Array).size() == 24)
	var custom_swamp := 0
	for row in custom:
		custom_swamp += (row as Array).count("swamp")
		assert(str((row as Array)[0]) != "river" and str((row as Array)[1]) != "river")
		assert(str((row as Array)[22]) != "river" and str((row as Array)[23]) != "river")
	assert(custom_swamp >= 1)
	assert(GameDefs.save_map_file(custom))
	var raw := FileAccess.get_file_as_string(GameDefs.CUSTOM_MAP_PATH)
	var parsed = JSON.parse_string(raw)
	assert(typeof(parsed) == TYPE_DICTIONARY)
	assert(int((parsed as Dictionary)["width"]) == 24)
	assert(int((parsed as Dictionary)["height"]) == 16)
	assert(((parsed as Dictionary)["terrain"] as Array).size() == 16)
	var loaded: Array = GameDefs.load_map_file()
	assert(loaded.size() == custom.size())
	assert(str((loaded[3] as Array)[3]) == str((custom[3] as Array)[3]))
	assert(GameDefs.has_custom_map())
	print("LOGIC OK: seven units, swamp cost, phase order, six levels, editor map")
	quit(0)
