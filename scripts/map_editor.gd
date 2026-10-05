extends Node2D
## Paint one custom map. Deploy columns are fixed: two on the left, two on the right.
## Right panel holds minimap, size steppers, and action icons.

const HEX_SIZE := 33.87
const HEADER_H := 44.0
const BOTTOM_TOP := 628.0
const PANEL_LEFT := 1004.0
const PLAY_INSET := 18.0
const DRAG_THRESH := 8.0
const MIN_COLS := 12
const MAX_COLS := 80
const MIN_ROWS := 8
const MAX_ROWS := 50
const BATTLE_SCENE := "res://scenes/main.tscn"
const ICON_DIR := "res://assets/ui/processed/icons/editor/%s.png"
const TERRAIN_ORDER: Array[String] = ["clear", "road", "forest", "hill", "town", "river", "swamp"]
const BRASS := Color(0.78, 0.64, 0.32, 1)
const GOLD := Color(1.0, 0.84, 0.38, 1)
const MINI_COLOR := {
	"clear": Color(0.64, 0.58, 0.36),
	"forest": Color(0.16, 0.40, 0.20),
	"hill": Color(0.52, 0.40, 0.26),
	"town": Color(0.75, 0.70, 0.52),
	"road": Color(0.80, 0.70, 0.42),
	"river": Color(0.22, 0.45, 0.74),
	"swamp": Color(0.36, 0.42, 0.22),
}

var cols := GameDefs.CUSTOM_COLS
var rows := GameDefs.CUSTOM_ROWS
var grid: Array = []
var brush := "clear"
var terrain_textures: Dictionary = {}
var play_rect := Rect2(PLAY_INSET, 46, 978, 500)
var map_bounds := Rect2()
var map_origin := Vector2.ZERO
var cam_offset := Vector2.ZERO
var hover_hex := Vector2i(-1, -1)
var left_down := false
var panning := false
var left_press_pos := Vector2.ZERO
var pan_anchor_mouse := Vector2.ZERO
var pan_anchor_cam := Vector2.ZERO
var status_label: Label
var size_label: Label
var col_value: Label
var row_value: Label
var brush_buttons: Dictionary = {}
var minimap_view: Control
var mini_drag := false
var mini_moved := false
var mini_press_local := Vector2.ZERO
var mini_press_cam := Vector2.ZERO
var _mini_tex: Texture2D


func _ready() -> void:
	_load_textures()
	_make_grid(cols, rows)
	_wire_ui()
	_layout_map()
	_rebuild_minimap_cache()
	_refresh_size_label()
	_refresh_minimap()
	_set_status("左兩欄盟軍部署，右兩欄軸心部署。點格塗地形，拖曳平移。")


func _load_textures() -> void:
	for t in TERRAIN_ORDER:
		terrain_textures[t] = load("res://processed/terrain-%s.png" % t)


func _make_grid(w: int, h: int) -> void:
	cols = w
	rows = h
	grid.clear()
	for r in h:
		var row: Array = []
		row.resize(w)
		for c in w:
			row[c] = "clear"
		grid.append(row)


func _grid_from(loaded: Array) -> void:
	grid = loaded
	rows = grid.size()
	cols = (grid[0] as Array).size()
	cam_offset = Vector2.ZERO
	_layout_map()
	_rebuild_minimap_cache()
	_refresh_size_label()
	_refresh_minimap()
	queue_redraw()


func _wire_ui() -> void:
	status_label = $UI/StatusLabel
	UiStyle.apply_font(status_label, 16, Color(0.92, 0.9, 0.8))
	size_label = $UI/RightColumn/SizeLabel
	col_value = $UI/RightColumn/ColStep/ColValue
	row_value = $UI/RightColumn/RowStep/RowValue
	UiStyle.apply_font(size_label, 18, Color(0.96, 0.88, 0.55))
	size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_font(col_value, 15, Color(0.92, 0.86, 0.62))
	col_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_font(row_value, 15, Color(0.92, 0.86, 0.62))
	row_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_setup_step($UI/RightColumn/ColStep/ColMinus)
	_setup_step($UI/RightColumn/ColStep/ColPlus)
	_setup_step($UI/RightColumn/RowStep/RowMinus)
	_setup_step($UI/RightColumn/RowStep/RowPlus)
	$UI/RightColumn/ColStep/ColMinus.pressed.connect(_nudge_cols.bind(-1))
	$UI/RightColumn/ColStep/ColPlus.pressed.connect(_nudge_cols.bind(1))
	$UI/RightColumn/RowStep/RowMinus.pressed.connect(_nudge_rows.bind(-1))
	$UI/RightColumn/RowStep/RowPlus.pressed.connect(_nudge_rows.bind(1))
	var brushes := $UI/BrushRow
	for tid in TERRAIN_ORDER:
		var b := brushes.get_node("Brush" + tid) as Button
		_setup_icon_button(b, "brush-" + tid, 68)
		b.pressed.connect(_pick_brush.bind(tid))
		brush_buttons[tid] = b
	_mark_brush()
	var actions := $UI/RightColumn/ActionGrid
	_bind_action(actions.get_node("GenerateButton"), "editor-generate", _on_generate)
	_bind_action(actions.get_node("ClearButton"), "editor-clear", _on_clear)
	_bind_action(actions.get_node("SaveButton"), "editor-save", _on_save)
	_bind_action(actions.get_node("LoadButton"), "editor-load", _on_load)
	_bind_action(actions.get_node("TryButton"), "editor-play", _on_try)
	_bind_action(actions.get_node("BackButton"), "editor-back", _on_back)
	minimap_view = $UI/MinimapFrame/MinimapView
	UiStyle.style_panel($UI/MinimapFrame as PanelContainer)
	# Center the 2-col action grid inside the right column.
	var grid_box := actions as GridContainer
	grid_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _bind_action(node: Node, stem: String, cb: Callable) -> void:
	var btn := node as Button
	_setup_icon_button(btn, stem, 58)
	btn.pressed.connect(cb)


func _setup_step(btn: Button) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(32, 32)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiStyle.apply_font(btn, 18, Color(0.96, 0.88, 0.55))
	btn.add_theme_color_override("font_color", Color(0.96, 0.9, 0.62))
	btn.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.78))
	btn.add_theme_color_override("font_pressed_color", Color(0.75, 0.64, 0.32))
	_apply_plate(btn, false, 16, 2)


func _setup_icon_button(btn: Button, stem: String, side: int) -> void:
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.expand_icon = true
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tex := load(ICON_DIR % stem) as Texture2D
	if tex == null:
		push_error("Missing editor icon: %s" % stem)
	btn.icon = tex
	btn.custom_minimum_size = Vector2(side, side)
	for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		btn.add_theme_color_override(key, Color.WHITE)
	_apply_plate(btn, false, int(side / 2), 6 if side < 68 else 8)


func _plate(hot: bool, hover: bool, radius: int = 34, pad: int = 8) -> StyleBoxFlat:
	var plate := StyleBoxFlat.new()
	if hot:
		plate.bg_color = Color(0.20, 0.16, 0.08, 1)
	elif hover:
		plate.bg_color = Color(0.14, 0.13, 0.11, 1)
	else:
		plate.bg_color = Color(0.07, 0.08, 0.10, 1)
	if hot:
		plate.border_color = GOLD
		plate.set_border_width_all(4 if radius >= 28 else 3)
	elif hover:
		plate.border_color = Color(0.95, 0.82, 0.48)
		plate.set_border_width_all(2)
	else:
		plate.border_color = BRASS
		plate.set_border_width_all(2)
	plate.set_corner_radius_all(radius)
	plate.content_margin_left = pad
	plate.content_margin_right = pad
	plate.content_margin_top = pad
	plate.content_margin_bottom = pad
	return plate


func _apply_plate(btn: Button, hot: bool, radius: int = 34, pad: int = 8) -> void:
	btn.add_theme_stylebox_override("normal", _plate(hot, false, radius, pad))
	btn.add_theme_stylebox_override("hover", _plate(hot, true, radius, pad))
	var pressed := _plate(hot, false, radius, pad)
	pressed.bg_color = Color(0.05, 0.05, 0.06, 1)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", _plate(hot, true, radius, pad))


func _pick_brush(tid: String) -> void:
	brush = tid
	_mark_brush()
	_set_status("筆刷　%s" % str(GameDefs.TERRAIN[tid]["label"]))


func _mark_brush() -> void:
	for tid in brush_buttons:
		_apply_plate(brush_buttons[tid] as Button, str(tid) == brush, 34, 8)


func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg


func _on_generate() -> void:
	grid = GameDefs.generate_battle_map(cols, rows, 24)
	rows = grid.size()
	cols = (grid[0] as Array).size()
	_layout_map()
	_rebuild_minimap_cache()
	_set_status("已自動生成　%d×%d" % [cols, rows])
	_refresh_minimap()
	queue_redraw()


func _on_clear() -> void:
	_make_grid(cols, rows)
	_layout_map()
	_rebuild_minimap_cache()
	_refresh_size_label()
	_set_status("已清空")
	_refresh_minimap()
	queue_redraw()


func _nudge_cols(delta: int) -> void:
	_resize_to(cols + delta, rows)


func _nudge_rows(delta: int) -> void:
	_resize_to(cols, rows + delta)


func _resize_to(new_cols: int, new_rows: int) -> void:
	new_cols = clampi(new_cols, MIN_COLS, MAX_COLS)
	new_rows = clampi(new_rows, MIN_ROWS, MAX_ROWS)
	if new_cols == cols and new_rows == rows:
		_refresh_size_label()
		_set_status("地圖　%d×%d" % [cols, rows])
		return
	var next: Array = []
	for r in new_rows:
		var row: Array = []
		row.resize(new_cols)
		for c in new_cols:
			if r < grid.size() and c < (grid[r] as Array).size():
				row[c] = grid[r][c]
			else:
				row[c] = "clear"
		next.append(row)
	grid = next
	cols = new_cols
	rows = new_rows
	cam_offset = Vector2.ZERO
	_layout_map()
	_rebuild_minimap_cache()
	_refresh_size_label()
	_set_status("地圖　%d×%d" % [cols, rows])
	_refresh_minimap()
	queue_redraw()


func _refresh_size_label() -> void:
	var line := "%d×%d" % [cols, rows]
	if size_label:
		size_label.text = line
	if col_value:
		col_value.text = str(cols)
	if row_value:
		row_value.text = str(rows)


func _on_save() -> void:
	# user://custom_map.json
	if GameDefs.save_map_file(grid):
		_set_status("已儲存")
	else:
		_set_status("儲存失敗")


func _on_load() -> void:
	var loaded := GameDefs.load_map_file()
	if loaded.is_empty():
		_set_status("沒有已存地圖")
		return
	_grid_from(loaded)
	_set_status("已讀取　%d×%d" % [cols, rows])


func _on_try() -> void:
	if not GameDefs.save_map_file(grid):
		_set_status("儲存失敗")
		return
	Session.play_custom = true
	Session.vs_cpu = false
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _on_back() -> void:
	Session.play_custom = false
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")


func _layout_map() -> void:
	# Map fills the area left of the right panel, with a small left inset so the
	# outer hex column is not clipped against the window edge.
	play_rect = Rect2(
		PLAY_INSET,
		HEADER_H + 2.0,
		PANEL_LEFT - PLAY_INSET - 6.0,
		BOTTOM_TOP - 6.0 - (HEADER_H + 2.0)
	)
	var w_factor := (float(cols) + 0.5) * sqrt(3.0)
	var h_factor := (float(rows) - 1.0) * 1.5 + 2.0
	var map_w := w_factor * HEX_SIZE
	var map_h := h_factor * HEX_SIZE
	var left := play_rect.position.x + (play_rect.size.x - map_w) * 0.5
	var top := play_rect.position.y + (play_rect.size.y - map_h) * 0.5
	map_bounds = Rect2(left, top, map_w, map_h)
	var hex_rx := HEX_SIZE * sqrt(3.0) * 0.5
	map_origin = Vector2(left + hex_rx, top + HEX_SIZE)
	_clamp_cam()


func _clamp_axis(cam: float, map_pos: float, map_size: float, view_pos: float, view_size: float) -> float:
	if map_size <= view_size + 0.5:
		return map_pos - (view_pos + (view_size - map_size) * 0.5)
	return clampf(cam, map_pos - view_pos, (map_pos + map_size) - (view_pos + view_size))


func _clamp_cam() -> void:
	cam_offset.x = _clamp_axis(cam_offset.x, map_bounds.position.x, map_bounds.size.x, play_rect.position.x, play_rect.size.x)
	cam_offset.y = _clamp_axis(cam_offset.y, map_bounds.position.y, map_bounds.size.y, play_rect.position.y, play_rect.size.y)


func _hex_center(col: int, row: int) -> Vector2:
	return map_origin + HexUtils.oddr_to_pixel(col, row, HEX_SIZE) - cam_offset


func _hex_at_screen(screen: Vector2) -> Vector2i:
	return HexUtils.pixel_to_oddr(screen + cam_offset - map_origin, HEX_SIZE)


func _in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < cols and row >= 0 and row < rows


func _deploy_tint(col: int) -> Color:
	if col < GameDefs.DEPLOY_DEPTH:
		return Color(0.25, 0.9, 0.35, 0.22)
	if col >= cols - GameDefs.DEPLOY_DEPTH:
		return Color(0.95, 0.25, 0.22, 0.22)
	return Color(0, 0, 0, 0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.08, 0.09, 0.10))
	draw_rect(play_rect, Color(0.11, 0.13, 0.12))
	if grid.is_empty():
		return
	var pad := HEX_SIZE * 2.0
	for r in rows:
		for c in cols:
			var center := _hex_center(c, r)
			if center.x < play_rect.position.x - pad or center.x > play_rect.end.x + pad:
				continue
			if center.y < play_rect.position.y - pad or center.y > play_rect.end.y + pad:
				continue
			var tid := str(grid[r][c])
			var tex: Texture2D = terrain_textures.get(tid)
			var mod := Color.WHITE
			if tex == null and tid == "swamp":
				tex = terrain_textures.get("clear")
				mod = Color(0.62, 0.58, 0.32, 1)
			var dest := Rect2(center - Vector2(HEX_SIZE * sqrt(3.0) / 2.0, HEX_SIZE), Vector2(HEX_SIZE * sqrt(3.0), HEX_SIZE * 2.0))
			if tex != null:
				draw_texture_rect(tex, dest, false, mod)
			var tint := _deploy_tint(c)
			if tint.a > 0.0:
				draw_colored_polygon(HexUtils.hex_corners(center, HEX_SIZE - 1.0), tint)
			var corners := HexUtils.hex_corners(center, HEX_SIZE - 0.5)
			var outline := PackedVector2Array(corners)
			outline.append(corners[0])
			draw_polyline(outline, Color(0.15, 0.15, 0.18, 0.55), 1.2, true)
	if _in_bounds(hover_hex.x, hover_hex.y):
		var hc := _hex_center(hover_hex.x, hover_hex.y)
		var hcors := HexUtils.hex_corners(hc, HEX_SIZE - 1.5)
		var ho := PackedVector2Array(hcors)
		ho.append(hcors[0])
		draw_polyline(ho, Color(1, 0.92, 0.45, 0.9), 2.0, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if play_rect.has_point(motion.position):
			var hx := _hex_at_screen(motion.position)
			hover_hex = hx if _in_bounds(hx.x, hx.y) else Vector2i(-1, -1)
		else:
			hover_hex = Vector2i(-1, -1)
		if left_down and not panning and motion.position.distance_to(left_press_pos) >= DRAG_THRESH:
			panning = true
			pan_anchor_mouse = left_press_pos
			pan_anchor_cam = cam_offset
		if panning:
			cam_offset = pan_anchor_cam - (motion.position - pan_anchor_mouse)
			_clamp_cam()
			_refresh_minimap()
		queue_redraw()
		return
	if not (event is InputEventMouseButton):
		return
	var btn := event as InputEventMouseButton
	if btn.button_index == MOUSE_BUTTON_LEFT:
		if btn.pressed:
			if play_rect.has_point(btn.position):
				left_down = true
				panning = false
				left_press_pos = btn.position
				pan_anchor_cam = cam_offset
		else:
			if left_down and not panning and play_rect.has_point(left_press_pos):
				_paint_at(_hex_at_screen(left_press_pos))
			left_down = false
			panning = false
	elif btn.button_index == MOUSE_BUTTON_RIGHT or btn.button_index == MOUSE_BUTTON_MIDDLE:
		if btn.pressed and play_rect.has_point(btn.position):
			panning = true
			left_down = false
			pan_anchor_mouse = btn.position
			pan_anchor_cam = cam_offset
		elif not btn.pressed:
			panning = false


func _paint_at(hex: Vector2i) -> void:
	if not _in_bounds(hex.x, hex.y):
		return
	grid[hex.y][hex.x] = brush
	var d: Dictionary = GameDefs.TERRAIN[brush]
	_set_status("%s　欄 %d　列 %d" % [str(d["label"]), hex.x, hex.y])
	_rebuild_minimap_cache()
	_refresh_minimap()
	queue_redraw()


func _refresh_minimap() -> void:
	if minimap_view != null:
		minimap_view.queue_redraw()


func _rebuild_minimap_cache() -> void:
	var px_w := 280
	var px_h := 180
	var img := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.13, 0.11, 1))
	if map_bounds.size.x >= 1.0 and not grid.is_empty():
		# Stamp a small disk per hex so sparse boards (12×8) still look filled.
		var stamp := maxi(2, int(round(minf(float(px_w) / float(cols + 1), float(px_h) / float(rows + 1)) * 0.55)))
		for row in rows:
			for col in cols:
				var world := map_origin + HexUtils.oddr_to_pixel(col, row, HEX_SIZE)
				var t := (world - map_bounds.position) / map_bounds.size
				var cx := clampi(int(t.x * float(px_w)), 0, px_w - 1)
				var cy := clampi(int(t.y * float(px_h)), 0, px_h - 1)
				var colr: Color = MINI_COLOR.get(str(grid[row][col]), Color.GRAY)
				for dy in range(-stamp, stamp + 1):
					for dx in range(-stamp, stamp + 1):
						if dx * dx + dy * dy > stamp * stamp:
							continue
						var x := cx + dx
						var y := cy + dy
						if x < 0 or y < 0 or x >= px_w or y >= px_h:
							continue
						img.set_pixel(x, y, colr)
	_mini_tex = ImageTexture.create_from_image(img)


func _minimap_content_rect(view_size: Vector2) -> Rect2:
	var margin := 6.0
	var avail := view_size - Vector2(margin * 2.0, margin * 2.0)
	if avail.x < 4.0 or avail.y < 4.0 or map_bounds.size.x < 1.0 or map_bounds.size.y < 1.0:
		return Rect2()
	var map_aspect := map_bounds.size.x / map_bounds.size.y
	var avail_aspect := avail.x / avail.y
	var sz := Vector2(avail.y * map_aspect, avail.y) if avail_aspect > map_aspect else Vector2(avail.x, avail.x / map_aspect)
	return Rect2((view_size - sz) * 0.5, sz)


func _visible_world_rect() -> Rect2:
	return Rect2(play_rect.position + cam_offset, play_rect.size)


func _viewport_on_minimap(content: Rect2) -> Rect2:
	if content.size.x < 1.0:
		return Rect2()
	var inter := _visible_world_rect().intersection(map_bounds)
	if inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return content
	var scale := content.size / map_bounds.size
	return Rect2(content.position + (inter.position - map_bounds.position) * scale, inter.size * scale)


func _minimap_to_world(local: Vector2, content: Rect2) -> Vector2:
	var t := Vector2(0.5, 0.5)
	if content.size.x > 0.0 and content.size.y > 0.0:
		t = (local - content.position) / content.size
	t.x = clampf(t.x, 0.0, 1.0)
	t.y = clampf(t.y, 0.0, 1.0)
	return map_bounds.position + Vector2(t.x * map_bounds.size.x, t.y * map_bounds.size.y)


func _center_cam_on(world: Vector2) -> void:
	cam_offset = world - play_rect.get_center()
	_clamp_cam()


func paint_minimap(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.06, 0.07, 0.08, 1))
	var content := _minimap_content_rect(c.size)
	if content.size.x < 2.0:
		return
	c.draw_rect(content, Color(0.14, 0.15, 0.12, 1))
	if grid.is_empty():
		return
	if _mini_tex != null:
		c.draw_texture_rect(_mini_tex, content, false)
	else:
		var scale := content.size / map_bounds.size
		var rad := HEX_SIZE * minf(scale.x, scale.y) * 0.92
		for row in range(rows):
			for col in range(cols):
				var world := map_origin + HexUtils.oddr_to_pixel(col, row, HEX_SIZE)
				var center := content.position + (world - map_bounds.position) * scale
				var tid: String = grid[row][col]
				c.draw_colored_polygon(HexUtils.hex_corners(center, rad), MINI_COLOR.get(tid, Color.GRAY))
	var box := _viewport_on_minimap(content)
	c.draw_rect(box, Color(1.0, 0.92, 0.45, 0.16), true)
	c.draw_rect(box, Color(1.0, 0.92, 0.45, 0.95), false, 2.0)


func minimap_begin(local: Vector2, c: Control) -> void:
	var content := _minimap_content_rect(c.size)
	mini_drag = true
	mini_moved = false
	mini_press_local = local
	var box := _viewport_on_minimap(content)
	if not box.has_point(local):
		_center_cam_on(_minimap_to_world(local, content))
		mini_moved = true
	mini_press_cam = cam_offset
	mini_press_local = local
	queue_redraw()
	_refresh_minimap()


func minimap_move(local: Vector2, c: Control) -> void:
	if not mini_drag:
		return
	if local.distance_to(mini_press_local) < 3.0:
		return
	mini_moved = true
	var content := _minimap_content_rect(c.size)
	var w0 := _minimap_to_world(mini_press_local, content)
	var w1 := _minimap_to_world(local, content)
	cam_offset = mini_press_cam + (w1 - w0)
	_clamp_cam()
	queue_redraw()
	_refresh_minimap()


func minimap_end(local: Vector2, c: Control) -> void:
	if mini_drag and not mini_moved:
		var content := _minimap_content_rect(c.size)
		_center_cam_on(_minimap_to_world(local, content))
		queue_redraw()
		_refresh_minimap()
	mini_drag = false
	mini_moved = false
