extends Node2D
## 二戰風雲錄 — hotseat Allies vs Axis hex battle.

enum Phase { ALLIES_BUY, AXIS_BUY, ALLIES_BOMBARD, ALLIES_MOVE, ALLIES_SHOOT, AXIS_BOMBARD, AXIS_MOVE, AXIS_SHOOT, RESULT }

## Fixed pointy-top size. A larger map must pan, not shrink the hexes.
## 33.87 leaves a small inset on the 16×10 board so the outer columns
## sit fully inside the play rect (not flush with the window or the panel).
const HEX_SIZE := 33.87
const VIEW_SIZE := Vector2(1280, 720)
const HEADER_H := 68.0
const BOTTOM_TOP := 622.0
const PANEL_LEFT := 1004.0
const DRAG_THRESH := 8.0
const ICON_ORDER: Array[String] = ["infantry", "recon", "light_tank", "medium_tank", "heavy_tank", "artillery", "engineer"]
const SLOT_NAMES := {
	"infantry": "Infantry", "recon": "Recon", "light_tank": "Light", "medium_tank": "Medium",
	"heavy_tank": "Heavy", "artillery": "Artillery", "engineer": "Engineer",
}
var phase: Phase = Phase.ALLIES_BUY
var round_num: int = 1
var battle_points: int = 18
var buy_points_left: int = 18
var buying_team: String = GameDefs.TEAM_ALLIES
var active_team: String = GameDefs.TEAM_ALLIES
var pending_buy_type: String = ""

var terrain: Array = []
var units: Array = []
var next_unit_id: int = 1

var selected_unit: UnitData = null
var reachable: Dictionary = {}
var shoot_targets: Array[UnitData] = []
var combat_log: String = ""

var allies_losses: int = 0
var axis_losses: int = 0
var allies_points_lost: int = 0
var axis_points_lost: int = 0

var hud_event: Label
var hud_losses: Label
var hud_ammo: Label
var hud_shot: Label
var hud_enter: Label
var result_headline: String = ""
var cpu_running := false
var combat_fx: Array = []

var terrain_textures: Dictionary = {}
var unit_textures: Dictionary = {}
## Source-pixel factor: screen scale = (HEX_SIZE - margin) / this.
var infantry_hex_limit: float = 197.45
var hex_highlights: Array[Vector2i] = []
var highlight_mode: String = ""
var map_origin: Vector2 = Vector2(40, 50)
var play_rect := Rect2(4, 70, 996, 548)
var map_bounds := Rect2()
var cam_offset := Vector2.ZERO
var hover_hex := Vector2i(-1, -1)
var pinned_hex := Vector2i(-1, -1)
var panning := false
var left_down := false
var left_press_pos := Vector2.ZERO
var pan_anchor_mouse := Vector2.ZERO
var pan_anchor_cam := Vector2.ZERO
var mini_drag := false
var mini_moved := false
var mini_press_local := Vector2.ZERO
var mini_press_cam := Vector2.ZERO
var _mini_tex: Texture2D

const MINI_COLOR := {
	"clear": Color(0.64, 0.58, 0.36),
	"forest": Color(0.16, 0.40, 0.20),
	"hill": Color(0.52, 0.40, 0.26),
	"town": Color(0.75, 0.70, 0.52),
	"road": Color(0.80, 0.70, 0.42),
	"river": Color(0.22, 0.45, 0.74),
	"swamp": Color(0.36, 0.42, 0.22),
}

@onready var combat_label: Label = $UI/CombatLabel
@onready var points_label: Label = $UI/PointsLabel
@onready var round_label: Label = $UI/RoundLabel
@onready var icon_tray: HBoxContainer = $UI/IconTray
@onready var confirm_btn: TextureButton = $UI/ConfirmButton
@onready var confirm_label: Label = $UI/ConfirmLabel
@onready var result_panel: PanelContainer = $UI/ResultPanel
@onready var result_label: Label = $UI/ResultPanel/Margin/VBox/ResultLabel
@onready var replay_btn: TextureButton = $UI/ResultPanel/Margin/VBox/ResultButtons/ReplayButton
@onready var home_btn: TextureButton = $UI/ResultPanel/Margin/VBox/ResultButtons/HomeButton
@onready var header_logo: TextureRect = $UI/HeaderLogo
@onready var hud_panel: PanelContainer = $UI/HudPanel
@onready var faction_badge: TextureRect = $UI/FactionBadge
@onready var round_icon: TextureRect = $UI/RoundIcon
@onready var points_icon: TextureRect = $UI/PointsIcon
@onready var hud_portrait: TextureRect = $UI/HudPanel/HudMargin/HudVBox/HudPortrait
@onready var hud_title: Label = $UI/HudPanel/HudMargin/HudVBox/HudTitle
@onready var hud_cost: Label = $UI/HudPanel/HudMargin/HudVBox/HudCost
@onready var hud_move: Label = $UI/HudPanel/HudMargin/HudVBox/HudMove
@onready var hud_range: Label = $UI/HudPanel/HudMargin/HudVBox/HudRange
@onready var hud_attack: Label = $UI/HudPanel/HudMargin/HudVBox/HudAttack
@onready var hud_status: Label = $UI/HudPanel/HudMargin/HudVBox/HudStatus
@onready var hud_special: Label = $UI/HudPanel/HudMargin/HudVBox/HudSpecial
@onready var minimap_view: Control = $UI/MinimapFrame/MinimapView
@onready var terrain_label: Label = $UI/TerrainLabel

var icon_buttons: Dictionary = {}  # type_id -> TextureButton
var icon_rings: Dictionary = {}  # type_id -> Panel


func _ready() -> void:
	_apply_battle_setup()
	_compute_map_layout()
	_cache_icons()
	_apply_ui_style()
	_load_textures()
	_measure_infantry_hex_limit()
	_rebuild_minimap_cache()
	_setup_ui()
	_set_phase(Phase.ALLIES_BUY)
	_refresh_view()


func _apply_battle_setup() -> void:
	if Session.play_custom:
		terrain = GameDefs.load_map_file()
		if terrain.is_empty():
			terrain = GameDefs.generate_battle_map(GameDefs.CUSTOM_COLS, GameDefs.CUSTOM_ROWS, 24)
		GameDefs.use_custom_grid(terrain)
		battle_points = GameDefs.CUSTOM_POINTS
	else:
		GameDefs.apply_level(Session.level)
		battle_points = GameDefs.BUY_POINTS
		terrain = GameDefs.build_map()
	buy_points_left = battle_points


func _compute_map_layout() -> void:
	# Between the header, the bottom tray, the left edge, and the right panel.
	play_rect = Rect2(4.0, HEADER_H + 2.0, PANEL_LEFT - 8.0, BOTTOM_TOP - 4.0 - (HEADER_H + 2.0))
	var w_factor := (float(GameDefs.MAP_COLS) + 0.5) * sqrt(3.0)
	var h_factor := (float(GameDefs.MAP_ROWS) - 1.0) * 1.5 + 2.0
	var map_w := w_factor * HEX_SIZE
	var map_h := h_factor * HEX_SIZE
	var left := play_rect.position.x + (play_rect.size.x - map_w) * 0.5
	var top := play_rect.position.y + (play_rect.size.y - map_h) * 0.5
	map_bounds = Rect2(left, top, map_w, map_h)
	var hex_rx := HEX_SIZE * sqrt(3.0) * 0.5
	map_origin = Vector2(left + hex_rx, top + HEX_SIZE)
	_clamp_cam()
	print("LAYOUT hex=%.2f cols=%d rows=%d map=%.1fx%.1f play=%.0fx%.0f" % [
		HEX_SIZE, GameDefs.MAP_COLS, GameDefs.MAP_ROWS, map_w, map_h, play_rect.size.x, play_rect.size.y
	])


func _cache_icons() -> void:
	icon_buttons.clear()
	icon_rings.clear()
	for type_id in ICON_ORDER:
		var slot: VBoxContainer = icon_tray.get_node("Slot%s" % SLOT_NAMES[type_id])
		icon_rings[type_id] = slot.get_node("SelectRing")
		icon_buttons[type_id] = slot.get_node("SelectRing/Icon")
		var cost_lab := slot.get_node_or_null("Cost") as Label
		if cost_lab != null:
			cost_lab.text = str(int(GameDefs.UNIT_TYPES[type_id]["cost"]))
			UiStyle.apply_font(cost_lab, 13, Color(0.92, 0.86, 0.6))


func _gold_ring_style(selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_corner_radius_all(38)
	if selected:
		box.set_border_width_all(3)
		box.border_color = Color(1.0, 0.85, 0.35, 1.0)
	else:
		box.set_border_width_all(0)
		box.border_color = Color(0, 0, 0, 0)
	return box


func _apply_ui_style() -> void:
	# Force load project CJK font (Noto Sans CJK TC)
	var _face := UiStyle.cjk_face_report()
	UiStyle.apply_font(points_label, 22, Color(0.96, 0.92, 0.78))
	UiStyle.apply_font(round_label, 26, Color(0.96, 0.92, 0.78))
	UiStyle.apply_font(combat_label, 14, Color(1.0, 0.92, 0.55))
	UiStyle.apply_font(result_label, 18, Color(0.95, 0.93, 0.85))
	UiStyle.apply_font(hud_title, 18, Color(0.96, 0.90, 0.55))
	UiStyle.apply_font(hud_cost, 15, Color(0.94, 0.92, 0.84))
	UiStyle.apply_font(hud_move, 15, Color(0.94, 0.92, 0.84))
	UiStyle.apply_font(hud_range, 15, Color(0.94, 0.92, 0.84))
	UiStyle.apply_font(hud_attack, 15, Color(0.94, 0.92, 0.84))
	UiStyle.apply_font(hud_status, 15, Color(0.94, 0.92, 0.84))
	UiStyle.apply_font(hud_special, 13, Color(0.95, 0.88, 0.6))
	UiStyle.apply_font(confirm_label, 15, Color(0.9, 0.85, 0.65))
	UiStyle.apply_font(terrain_label, 14, Color(0.90, 0.88, 0.78))
	UiStyle.style_panel(result_panel)
	for type_id in ICON_ORDER:
		UiStyle.setup_icon_button(icon_buttons[type_id], type_id, 72.0)
		(icon_rings[type_id] as Panel).add_theme_stylebox_override("panel", _gold_ring_style(false))
	UiStyle.setup_icon_button(confirm_btn, "confirm", 72.0)
	UiStyle.setup_texture_button(replay_btn, "btn-replay", 48.0)
	UiStyle.setup_texture_button(home_btn, "btn-back", 48.0)
	# Tall card frame (plain dark + gold) so stats stay inside — landscape plaque was letterboxed
	UiStyle.style_panel(hud_panel)
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0.12, 0.14, 0.11, 0.96)
	card.set_border_width_all(3)
	card.border_color = Color(0.78, 0.66, 0.35, 1.0)
	card.set_corner_radius_all(8)
	card.content_margin_left = 4
	card.content_margin_right = 4
	card.content_margin_top = 4
	card.content_margin_bottom = 4
	hud_panel.add_theme_stylebox_override("panel", card)
	hud_panel.clip_contents = true
	for lab in [hud_title, hud_cost, hud_move, hud_range, hud_attack, hud_status, hud_special, terrain_label, combat_label]:
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiStyle.style_panel(get_node("UI/MinimapFrame") as PanelContainer)
	# Minimap stays on top. The card under it holds the text, inside the frame.
	hud_panel.offset_left = PANEL_LEFT
	hud_panel.offset_top = 220.0
	hud_panel.offset_right = 1272.0
	hud_panel.offset_bottom = 614.0
	combat_label.visible = false
	terrain_label.text = "地形　—"
	# Full logo plaque + WWII Tales, no squash (KEEP_ASPECT inside 240x72)
	header_logo.texture = load("res://assets/ui/processed/logo.png") as Texture2D
	header_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	header_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	round_icon.texture = UiStyle.load_icon_texture("round")
	points_icon.texture = UiStyle.load_icon_texture("points")
	faction_badge.texture = UiStyle.load_icon_texture("badge-allies")
	_ensure_info_lines()


func _load_textures() -> void:
	for t in ["clear", "forest", "hill", "town", "road", "river", "swamp"]:
		terrain_textures[t] = load("res://processed/terrain-%s.png" % t)
	for u in GameDefs.unit_type_ids():
		unit_textures[u] = load("res://processed/unit-%s.png" % u)


func _measure_infantry_hex_limit() -> void:
	# Opaque squad pixels must stay inside the pointy hex, not just its bounding box.
	var tex: Texture2D = unit_textures["infantry"]
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var tw := img.get_width()
	var th := img.get_height()
	var bytes := img.get_data()
	var cx := (float(tw) - 1.0) * 0.5
	var cy := (float(th) - 1.0) * 0.5
	var half_flat := sqrt(3.0) * 0.5
	var inv_sqrt3 := 1.0 / sqrt(3.0)
	var limit := 1.0
	var i := 0
	for y in th:
		for x in tw:
			var alpha := bytes[i + 3]
			i += 4
			if alpha < 16:
				continue
			var dx0 := absf(float(x) - cx)
			var dy0 := absf(float(y) - cy)
			limit = maxf(limit, maxf(dx0 / half_flat, dy0 + dx0 * inv_sqrt3))
	infantry_hex_limit = limit
	print("INFANTRY_HEX_LIMIT=", limit)


func _setup_ui() -> void:
	for type_id in ICON_ORDER:
		var tid: String = type_id
		icon_buttons[type_id].pressed.connect(func(): _on_icon_pressed(tid))
		# Restore dim/afford state after hover brighten from UiStyle
		icon_buttons[type_id].mouse_exited.connect(_refresh_affordability)
	confirm_btn.pressed.connect(_on_confirm)
	replay_btn.pressed.connect(_on_replay)
	home_btn.pressed.connect(_on_home)
	result_panel.visible = false
	_refresh_hud_panel()


func _on_replay() -> void:
	get_tree().reload_current_scene()


func _on_home() -> void:
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")


func _on_icon_pressed(type_id: String) -> void:
	if cpu_running:
		return
	if phase != Phase.ALLIES_BUY and phase != Phase.AXIS_BUY:
		return
	var cost: int = int(GameDefs.UNIT_TYPES[type_id]["cost"])
	if cost > buy_points_left:
		_flash_hud("點數不足")
		return
	pending_buy_type = type_id
	hex_highlights.clear()
	var cols: Array = GameDefs.deploy_cols(buying_team)
	for col in cols:
		for row in range(GameDefs.MAP_ROWS):
			if _unit_at(col, row) == null and _can_place_on(type_id, col, row):
				hex_highlights.append(Vector2i(col, row))
	highlight_mode = "place"
	_refresh_icon_selection()
	_refresh_hud_panel()
	_refresh_view()


func _on_confirm() -> void:
	if cpu_running:
		return
	if phase == Phase.ALLIES_BUY or phase == Phase.AXIS_BUY:
		_end_buy()
	elif _is_battle_phase():
		_advance_phase()


func _set_phase(p: Phase) -> void:
	phase = p
	selected_unit = null
	reachable.clear()
	shoot_targets.clear()
	hex_highlights.clear()
	pending_buy_type = ""
	var battle := _is_battle_phase()
	match phase:
		Phase.ALLIES_BUY:
			buying_team = GameDefs.TEAM_ALLIES
			active_team = GameDefs.TEAM_ALLIES
			buy_points_left = battle_points
			icon_tray.visible = true
			confirm_btn.visible = true
			confirm_label.visible = true
			confirm_label.text = "結束部署"
			result_panel.visible = false
		Phase.AXIS_BUY:
			buying_team = GameDefs.TEAM_AXIS
			active_team = GameDefs.TEAM_AXIS
			buy_points_left = battle_points
			icon_tray.visible = true
			confirm_btn.visible = true
			confirm_label.visible = true
			confirm_label.text = "結束部署"
			result_panel.visible = false
		Phase.ALLIES_BOMBARD, Phase.ALLIES_MOVE, Phase.ALLIES_SHOOT:
			active_team = GameDefs.TEAM_ALLIES
			icon_tray.visible = false
			confirm_btn.visible = true
			confirm_label.visible = true
			confirm_label.text = _confirm_caption()
			result_panel.visible = false
			if phase == Phase.ALLIES_BOMBARD:
				_reset_team_flags(GameDefs.TEAM_ALLIES)
		Phase.AXIS_BOMBARD, Phase.AXIS_MOVE, Phase.AXIS_SHOOT:
			active_team = GameDefs.TEAM_AXIS
			icon_tray.visible = false
			confirm_btn.visible = true
			confirm_label.visible = true
			confirm_label.text = _confirm_caption()
			result_panel.visible = false
			if phase == Phase.AXIS_BOMBARD:
				_reset_team_flags(GameDefs.TEAM_AXIS)
		Phase.RESULT:
			icon_tray.visible = false
			confirm_btn.visible = false
			confirm_label.visible = false
			_show_result()
	var cpu_phase := Session.vs_cpu and (
		phase == Phase.AXIS_BUY
		or phase == Phase.AXIS_BOMBARD
		or phase == Phase.AXIS_MOVE
		or phase == Phase.AXIS_SHOOT
	)
	if cpu_phase:
		icon_tray.visible = false
		confirm_btn.visible = false
		confirm_label.visible = false
		_set_event(_cpu_status_text())
	elif phase == Phase.ALLIES_BUY or phase == Phase.AXIS_BUY:
		_set_event("剩餘點數 %d" % buy_points_left)
	elif battle:
		_set_event("")
	_refresh_losses()
	_refresh_header()
	_refresh_icon_selection()
	_refresh_affordability()
	_refresh_hud_panel()
	_refresh_view()
	if not Session.vs_cpu:
		return
	if phase == Phase.AXIS_BUY:
		_begin_cpu_buy()
	elif phase == Phase.AXIS_BOMBARD:
		_begin_cpu_bombard()
	elif phase == Phase.AXIS_MOVE:
		_begin_cpu_move()
	elif phase == Phase.AXIS_SHOOT:
		_begin_cpu_shoot()


func _is_battle_phase() -> bool:
	return phase == Phase.ALLIES_BOMBARD or phase == Phase.ALLIES_MOVE or phase == Phase.ALLIES_SHOOT \
		or phase == Phase.AXIS_BOMBARD or phase == Phase.AXIS_MOVE or phase == Phase.AXIS_SHOOT


func _phase_kind() -> String:
	match phase:
		Phase.ALLIES_BOMBARD, Phase.AXIS_BOMBARD:
			return "bombard"
		Phase.ALLIES_MOVE, Phase.AXIS_MOVE:
			return "move"
		Phase.ALLIES_SHOOT, Phase.AXIS_SHOOT:
			return "direct"
		_:
			return ""


func _confirm_caption() -> String:
	match _phase_kind():
		"bombard":
			return "結束砲擊"
		"move":
			return "結束移動"
		"direct":
			return "結束射擊"
		_:
			return "結束回合"


func _cpu_status_text() -> String:
	match phase:
		Phase.AXIS_BUY:
			return "電腦部署中"
		Phase.AXIS_BOMBARD:
			return "電腦砲擊中"
		Phase.AXIS_MOVE:
			return "電腦移動中"
		Phase.AXIS_SHOOT:
			return "電腦射擊中"
		_:
			return "電腦行動中"


func _reset_team_flags(team: String) -> void:
	for u in units:
		if u.team == team and not u.destroyed:
			u.reset_turn_flags()


func _refresh_header() -> void:
	if active_team == GameDefs.TEAM_AXIS:
		faction_badge.texture = UiStyle.load_icon_texture("badge-axis")
	else:
		faction_badge.texture = UiStyle.load_icon_texture("badge-allies")
	var side_col := Color(0.55, 0.95, 0.62) if active_team == GameDefs.TEAM_ALLIES else Color(1.0, 0.55, 0.5)
	round_label.add_theme_color_override("font_color", side_col)
	if phase == Phase.RESULT:
		round_label.text = "結算"
		points_label.text = ""
		points_icon.visible = false
		return
	if phase == Phase.ALLIES_BUY or phase == Phase.AXIS_BUY:
		if Session.play_custom:
			round_label.text = "自訂地圖　部署階段"
		else:
			round_label.text = "第 %d 關　部署階段" % GameDefs.level_index
		points_label.text = str(buy_points_left)
		points_icon.visible = true
	else:
		var kind := _phase_kind()
		var phase_name := "回合"
		if kind == "bombard":
			phase_name = GameDefs.SIDE_PHASE_LABELS[0]
		elif kind == "move":
			phase_name = GameDefs.SIDE_PHASE_LABELS[1]
		elif kind == "direct":
			phase_name = GameDefs.SIDE_PHASE_LABELS[2]
		round_label.text = "%s　第 %d / %d 回合" % [phase_name, round_num, GameDefs.MAX_ROUNDS]
		points_label.text = ""
		points_icon.visible = false


func _refresh_icon_selection() -> void:
	for type_id in ICON_ORDER:
		var ring: Panel = icon_rings[type_id]
		ring.add_theme_stylebox_override("panel", _gold_ring_style(type_id == pending_buy_type))


func _refresh_affordability() -> void:
	var buying := phase == Phase.ALLIES_BUY or phase == Phase.AXIS_BUY
	for type_id in ICON_ORDER:
		var btn: TextureButton = icon_buttons[type_id]
		if not buying:
			btn.modulate = Color.WHITE
			continue
		var cost: int = int(GameDefs.UNIT_TYPES[type_id]["cost"])
		if cost > buy_points_left:
			btn.modulate = Color(0.45, 0.45, 0.45, 0.75)
		else:
			btn.modulate = Color.WHITE


func _flash_hud(msg: String) -> void:
	_set_event(msg)
	combat_label.text = ""


func _ensure_info_lines() -> void:
	if hud_event != null:
		return
	var box := get_node("UI/HudPanel/HudMargin/HudVBox") as VBoxContainer
	box.add_theme_constant_override("separation", 1)
	hud_ammo = Label.new()
	hud_ammo.name = "HudAmmo"
	_style_info_label(hud_ammo, 14, Color(0.94, 0.92, 0.84))
	box.add_child(hud_ammo)
	hud_shot = Label.new()
	hud_shot.name = "HudShot"
	_style_info_label(hud_shot, 14, Color(0.94, 0.92, 0.84))
	box.add_child(hud_shot)
	hud_enter = Label.new()
	hud_enter.name = "HudEnter"
	_style_info_label(hud_enter, 14, Color(0.86, 0.95, 0.78))
	box.add_child(hud_enter)
	if terrain_label.get_parent() != box:
		terrain_label.get_parent().remove_child(terrain_label)
		box.add_child(terrain_label)
	_style_info_label(terrain_label, 14, Color(0.90, 0.88, 0.78))
	hud_event = Label.new()
	hud_event.name = "HudEvent"
	_style_info_label(hud_event, 14, Color(1.0, 0.92, 0.55))
	box.add_child(hud_event)
	hud_losses = Label.new()
	hud_losses.name = "HudLosses"
	_style_info_label(hud_losses, 13, Color(0.90, 0.86, 0.72))
	box.add_child(hud_losses)
	var order: Array[Node] = [
		hud_portrait, hud_title, hud_special, hud_enter, terrain_label,
		hud_cost, hud_attack, hud_range, hud_move, hud_status, hud_ammo, hud_shot,
		hud_event, hud_losses,
	]
	for i in order.size():
		box.move_child(order[i], i)
	_style_info_label(hud_special, 14, Color(0.95, 0.88, 0.6))
	# Scene labels used word-wrap, which collapsed their height to 1px inside the card.
	_style_info_label(hud_title, 18, Color(0.96, 0.90, 0.55))
	hud_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for lab in [hud_cost, hud_attack, hud_range, hud_move, hud_status]:
		_style_info_label(lab, 15, Color(0.94, 0.92, 0.84))
	hud_portrait.custom_minimum_size = Vector2(72, 40)
	hud_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_refresh_losses()


func _style_info_label(lab: Label, size: int, color: Color) -> void:
	lab.layout_mode = 2
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lab.clip_text = true
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	lab.custom_minimum_size.y = size + 6
	UiStyle.apply_font(lab, size, color)


func _set_stat(lab: Label, value: String) -> void:
	if lab == null:
		return
	lab.text = value
	lab.visible = value != ""


func _set_event(msg: String) -> void:
	if hud_event != null:
		hud_event.text = msg
		hud_event.visible = msg != ""


func _refresh_losses() -> void:
	if hud_losses == null:
		return
	hud_losses.text = "盟軍損失 %d　軸心損失 %d" % [allies_losses, axis_losses]


func _clear_hud_stats() -> void:
	for lab in [hud_cost, hud_move, hud_range, hud_attack, hud_status, hud_ammo, hud_shot, hud_special, hud_enter]:
		_set_stat(lab, "")
	hud_portrait.texture = null
	hud_portrait.modulate = Color.WHITE
	hud_portrait.visible = false


func _phase_hint() -> String:
	match phase:
		Phase.ALLIES_BUY:
			return "點左側兩欄放置。"
		Phase.AXIS_BUY:
			return "點右側兩欄放置。"
		Phase.ALLIES_BOMBARD, Phase.AXIS_BOMBARD:
			return "砲擊階段，僅火砲可射擊。"
		Phase.ALLIES_MOVE, Phase.AXIS_MOVE:
			return "移動階段，每單位可移動一次。"
		Phase.ALLIES_SHOOT, Phase.AXIS_SHOOT:
			return "直接射擊，火砲不再射擊。"
		_:
			return ""


func _faction_color(team: String) -> Color:
	if team == GameDefs.TEAM_AXIS:
		return Color(1.0, 0.58, 0.5)
	return Color(0.55, 0.95, 0.62)


func _portrait_tint(team: String) -> Color:
	if team == GameDefs.TEAM_AXIS:
		return Color(1.0, 0.86, 0.84, 1.0)
	return Color(0.86, 1.0, 0.86, 1.0)


func _show_type_card(type_id: String, _damaged: bool = false, live: UnitData = null) -> void:
	var d: Dictionary = GameDefs.UNIT_TYPES[type_id]
	var team := buying_team
	if live != null:
		team = live.team
	hud_title.visible = true
	hud_title.text = str(d["label"])
	hud_title.add_theme_color_override("font_color", _faction_color(team))
	hud_portrait.visible = true
	hud_portrait.texture = unit_textures.get(type_id, null)
	hud_portrait.modulate = _portrait_tint(team)
	_set_stat(hud_cost, "費用　%d" % int(d["cost"]))
	var atk := int(d["attack"])
	var rng := int(d["range"])
	var max_m := int(d["move"])
	var remain := max_m
	var hp_now := GameDefs.starting_hp(type_id)
	var hp_max := hp_now
	var ammo_now := GameDefs.starting_ammo(type_id)
	var ammo_max := ammo_now
	var fired := "未射"
	var wound := ""
	if live != null:
		atk = live.base_attack()
		rng = live.max_range()
		max_m = live.max_move()
		remain = 0 if live.moved else max_m
		hp_now = live.hp
		hp_max = live.max_hp
		ammo_now = live.ammo
		ammo_max = live.max_ammo
		fired = "已射" if live.shot else "未射"
		if live.hp < live.max_hp:
			wound = "　受損"
	var min_r := int(d.get("min_range", 1))
	var range_text := "射程　%d" % rng
	if min_r > 1:
		range_text = "射程　%d–%d" % [min_r, rng]
	var attack_text := "攻擊　%d" % atk
	if type_id == "heavy_tank":
		attack_text = "攻擊　%d／裝甲%d" % [atk, atk + int(d.get("bonus_attack", 0))]
	elif type_id == "artillery":
		attack_text = "攻擊　%d／隣%d" % [atk, int(d.get("adjacent_attack", 2))]
	_set_stat(hud_attack, attack_text)
	_set_stat(hud_range, range_text)
	_set_stat(hud_move, "移動　%d/%d" % [remain, max_m])
	_set_stat(hud_status, "生命　%d/%d%s" % [hp_now, hp_max, wound])
	_set_stat(hud_ammo, "彈藥　%d/%d" % [ammo_now, ammo_max])
	_set_stat(hud_shot, fired)
	_set_stat(hud_special, str(d.get("blurb", "")))


func _refresh_hud_panel(unit: UnitData = null) -> void:
	if unit != null and not unit.destroyed:
		_show_type_card(unit.type_id, unit.hp < unit.max_hp, unit)
		_refresh_terrain_label()
		return
	if pending_buy_type != "" and (phase == Phase.ALLIES_BUY or phase == Phase.AXIS_BUY):
		_show_type_card(pending_buy_type)
		_refresh_terrain_label()
		return
	_clear_hud_stats()
	var hint := result_headline if phase == Phase.RESULT and result_headline != "" else _phase_hint()
	hud_title.text = hint
	hud_title.add_theme_color_override("font_color", Color(0.96, 0.90, 0.55))
	hud_title.visible = hint != ""
	_refresh_terrain_label()


func _end_buy() -> void:

	if phase == Phase.ALLIES_BUY:
		if _count_team(GameDefs.TEAM_ALLIES) == 0:
			_flash_hud("請先部署單位")
			return
		_set_phase(Phase.AXIS_BUY)
	elif phase == Phase.AXIS_BUY:
		if _count_team(GameDefs.TEAM_AXIS) == 0:
			_flash_hud("請先部署單位")
			return
		round_num = 1
		_set_phase(Phase.ALLIES_BOMBARD)


func _count_team(team: String) -> int:
	var n := 0
	for u in units:
		if u.team == team and not u.destroyed:
			n += 1
	return n


func _advance_phase() -> void:
	match phase:
		Phase.ALLIES_BOMBARD:
			_set_phase(Phase.ALLIES_MOVE)
		Phase.ALLIES_MOVE:
			_set_phase(Phase.ALLIES_SHOOT)
		Phase.ALLIES_SHOOT:
			_set_phase(Phase.AXIS_BOMBARD)
		Phase.AXIS_BOMBARD:
			_set_phase(Phase.AXIS_MOVE)
		Phase.AXIS_MOVE:
			_set_phase(Phase.AXIS_SHOOT)
		Phase.AXIS_SHOOT:
			if round_num >= GameDefs.MAX_ROUNDS:
				_set_phase(Phase.RESULT)
			else:
				round_num += 1
				_set_phase(Phase.ALLIES_BOMBARD)


func _show_result() -> void:
	var allies_towns := 0
	var axis_towns := 0
	for row in range(GameDefs.MAP_ROWS):
		for col in range(GameDefs.MAP_COLS):
			if terrain[row][col] != "town":
				continue
			var u := _unit_at(col, row)
			if u == null:
				continue
			if u.team == GameDefs.TEAM_ALLIES:
				allies_towns += 1
			elif u.team == GameDefs.TEAM_AXIS:
				axis_towns += 1
	var lines: PackedStringArray = []
	lines.append("—— 結果 ——")
	lines.append("盟軍城鎮 %d　軸心城鎮 %d" % [allies_towns, axis_towns])
	lines.append("盟軍損失 %d　軸心損失 %d" % [allies_losses, axis_losses])
	var winner := "平手"
	if allies_towns > axis_towns:
		winner = "盟軍勝"
	elif axis_towns > allies_towns:
		winner = "軸心勝"
	else:
		if axis_losses > allies_losses:
			winner = "盟軍勝"
		elif allies_losses > axis_losses:
			winner = "軸心勝"
	lines.append(winner)
	result_label.text = "\n".join(lines)
	result_panel.visible = true
	result_headline = winner
	_refresh_losses()
	_set_event(winner)


func _clamp_axis(cam: float, map_pos: float, map_size: float, view_pos: float, view_size: float) -> float:
	if map_size <= view_size + 0.5:
		return map_pos - (view_pos + (view_size - map_size) * 0.5)
	var cmin := map_pos - view_pos
	var cmax := (map_pos + map_size) - (view_pos + view_size)
	return clampf(cam, cmin, cmax)


func _clamp_cam() -> void:
	cam_offset.x = _clamp_axis(cam_offset.x, map_bounds.position.x, map_bounds.size.x, play_rect.position.x, play_rect.size.x)
	cam_offset.y = _clamp_axis(cam_offset.y, map_bounds.position.y, map_bounds.size.y, play_rect.position.y, play_rect.size.y)


func _refresh_view() -> void:
	queue_redraw()
	if minimap_view != null:
		minimap_view.queue_redraw()


func _hex_at_screen(screen: Vector2) -> Vector2i:
	return HexUtils.pixel_to_oddr(screen + cam_offset - map_origin, HEX_SIZE)


func _note_empty_hex(hex: Vector2i) -> void:
	if _in_bounds(hex.x, hex.y) and _unit_at(hex.x, hex.y) == null:
		pinned_hex = hex
		_refresh_terrain_label()


func _highlighted_hex() -> Vector2i:
	if _in_bounds(hover_hex.x, hover_hex.y):
		return hover_hex
	if _in_bounds(pinned_hex.x, pinned_hex.y):
		return pinned_hex
	if selected_unit != null and not selected_unit.destroyed:
		return Vector2i(selected_unit.col, selected_unit.row)
	return Vector2i(-1, -1)


func _panel_type_id() -> String:
	if selected_unit != null and not selected_unit.destroyed:
		return selected_unit.type_id
	return pending_buy_type


func _refresh_terrain_label() -> void:
	if terrain_label == null:
		return
	var h := _highlighted_hex()
	if not _in_bounds(h.x, h.y):
		terrain_label.text = "掩護　—"
		if hud_enter != null:
			_set_stat(hud_enter, "")
		return
	var tid := _terrain_at(h.x, h.y)
	var d: Dictionary = GameDefs.TERRAIN[tid]
	terrain_label.text = "%s　掩護 +%d" % [str(d["label"]), int(d["defense"])]
	if hud_enter == null:
		return
	var type_id := _panel_type_id()
	if type_id == "":
		_set_stat(hud_enter, "")
		return
	var occ := _unit_at(h.x, h.y)
	if selected_unit != null and occ != null and occ.id == selected_unit.id:
		_set_stat(hud_enter, "進入　目前所在")
		return
	if occ != null:
		_set_stat(hud_enter, "進入　已有單位")
		return
	var team := selected_unit.team if selected_unit != null else buying_team
	var help := _engineer_adjacent_to(h.x, h.y, team)
	var cost := GameDefs.enter_cost(type_id, tid, help)
	_set_stat(hud_enter, "進入　可以" if cost >= 0.0 else "進入　不可")


func _hover_at(screen: Vector2) -> void:
	var next := Vector2i(-1, -1)
	if play_rect.has_point(screen):
		var hex := _hex_at_screen(screen)
		if _in_bounds(hex.x, hex.y):
			next = hex
	if next != hover_hex:
		hover_hex = next
		_refresh_terrain_label()
		_refresh_view()


func _can_place_on(type_id: String, col: int, row: int) -> bool:
	var t: String = terrain[row][col]
	if t == "river":
		return false
	if not bool(GameDefs.UNIT_TYPES[type_id]["can_enter_forest"]) and t == "forest":
		return false
	return true


func _unit_at(col: int, row: int) -> UnitData:
	for u in units:
		if not u.destroyed and u.col == col and u.row == row:
			return u
	return null


func _in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < GameDefs.MAP_COLS and row >= 0 and row < GameDefs.MAP_ROWS


func _terrain_at(col: int, row: int) -> String:
	return terrain[row][col]


func _engineer_adjacent_to(col: int, row: int, team: String) -> bool:
	for n in HexUtils.oddr_neighbors(col, row):
		if not _in_bounds(n.x, n.y):
			continue
		var u := _unit_at(n.x, n.y)
		if u != null and not u.destroyed and u.team == team and u.type_id == "engineer":
			return true
	return false


func _step_cost(unit: UnitData, _from_col: int, _from_row: int, to_col: int, to_row: int) -> float:
	var help := _engineer_adjacent_to(to_col, to_row, unit.team)
	return GameDefs.enter_cost(unit.type_id, _terrain_at(to_col, to_row), help)


func _compute_reachable(unit: UnitData) -> Dictionary:
	var max_m := float(unit.max_move())
	var start := Vector2i(unit.col, unit.row)
	var best: Dictionary = {}
	best[start] = 0.0
	var pq: Array = [[0.0, start]]
	while not pq.is_empty():
		pq.sort_custom(func(a, b): return a[0] < b[0])
		var item = pq.pop_front()
		var spent: float = item[0]
		var cell: Vector2i = item[1]
		if spent > best.get(cell, INF):
			continue
		for n in HexUtils.oddr_neighbors(cell.x, cell.y):
			if not _in_bounds(n.x, n.y):
				continue
			var other := _unit_at(n.x, n.y)
			if other != null and other.id != unit.id:
				continue
			var sc := _step_cost(unit, cell.x, cell.y, n.x, n.y)
			if sc == -1.0:
				continue
			var new_spent: float
			if sc == -2.0:
				if spent >= max_m:
					continue
				new_spent = max_m
			else:
				new_spent = spent + sc
			if new_spent > max_m + 0.001:
				continue
			if new_spent < best.get(n, INF):
				best[n] = new_spent
				pq.append([new_spent, n])
	var result: Dictionary = {}
	for cell in best:
		if cell == start:
			continue
		var raw: float = best[cell]
		var rounded := int(ceili(raw))
		if rounded < 1:
			rounded = 1
		if rounded <= unit.max_move():
			result[cell] = raw
	return result


func _blocks_los(col: int, row: int) -> bool:
	return bool(GameDefs.TERRAIN[_terrain_at(col, row)]["blocks_los"])


func _hex_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := HexUtils.axial_distance(a, b)
	var out: Array[Vector2i] = []
	if n == 0:
		out.append(a)
		return out
	var aa := HexUtils.oddr_to_axial(a.x, a.y)
	var bb := HexUtils.oddr_to_axial(b.x, b.y)
	for i in range(n + 1):
		var t := float(i) / float(n)
		var axial := HexUtils.axial_round(lerpf(aa.x, bb.x, t), lerpf(aa.y, bb.y, t))
		out.append(HexUtils.axial_to_oddr(axial.x, axial.y))
	return out


func _has_los(from: Vector2i, to: Vector2i) -> bool:
	var line := _hex_line(from, to)
	for i in range(1, line.size() - 1):
		var h: Vector2i = line[i]
		if _in_bounds(h.x, h.y) and _blocks_los(h.x, h.y):
			return false
	return true


func _effective_range(unit: UnitData) -> int:
	return unit.max_range()


func _unit_sees(unit: UnitData, hex: Vector2i) -> bool:
	if unit == null or unit.destroyed:
		return false
	var dist := HexUtils.axial_distance(Vector2i(unit.col, unit.row), hex)
	var on_hill := _terrain_at(unit.col, unit.row) == "hill"
	if dist > GameDefs.sight_range(unit.type_id, on_hill):
		return false
	if dist <= 1:
		return true
	return _has_los(Vector2i(unit.col, unit.row), hex)


func _side_sees(team: String, hex: Vector2i) -> bool:
	for u in units:
		if u.destroyed or u.team != team:
			continue
		if _unit_sees(u, hex):
			return true
	return false


func _can_shoot(attacker: UnitData, target: UnitData) -> bool:
	if attacker.destroyed or target.destroyed:
		return false
	if attacker.ammo <= 0:
		return false
	if attacker.team == target.team:
		return false
	var from := Vector2i(attacker.col, attacker.row)
	var to := Vector2i(target.col, target.row)
	var dist := HexUtils.axial_distance(from, to)
	if dist < 1:
		return false
	# Artillery may snap-shoot an adjacent target for reduced attack. Indirect starts at min range.
	if attacker.type_id == "artillery" and dist == 1:
		return true
	if dist < attacker.min_range() or dist > attacker.max_range():
		return false
	if attacker.type_id == "artillery":
		return _side_sees(attacker.team, to)
	return _unit_sees(attacker, to)


func _defense_of(target: UnitData) -> int:
	return int(GameDefs.TERRAIN[_terrain_at(target.col, target.row)]["defense"])


func _resolve_combat(attacker: UnitData, target: UnitData) -> void:
	if not attacker.spend_shot():
		return
	var atk := attacker.current_attack_vs(target)
	var defn := _defense_of(target)
	var result := atk - defn
	var tlabel: String = target.label()
	var alabel: String = attacker.label()
	var kind := "miss"
	var line := "未命中"
	var lost_points := int(target.def()["cost"])
	if result >= 1 and target.take_hit():
		kind = "destroy"
		if target.team == GameDefs.TEAM_ALLIES:
			allies_losses += 1
			allies_points_lost += lost_points
		else:
			axis_losses += 1
			axis_points_lost += lost_points
		line = "消滅，損失 %d" % lost_points
		combat_log = "戰鬥：%s攻擊%s → 結果%d，消滅。" % [alabel, tlabel, result]
	elif result >= 1:
		kind = "hit"
		line = "命中，敵軍受損"
		combat_log = "戰鬥：%s攻擊%s → 結果%d，生命 %d/%d。" % [alabel, tlabel, result, target.hp, target.max_hp]
	else:
		kind = "miss"
		line = "未命中"
		combat_log = "戰鬥：%s攻擊%s → 結果%d，未命中。" % [alabel, tlabel, result]
	_spawn_fx(kind, Vector2i(attacker.col, attacker.row), Vector2i(target.col, target.row))
	_set_event(line)
	_refresh_losses()
	combat_label.text = line


func _hex_center(col: int, row: int) -> Vector2:
	return map_origin + HexUtils.oddr_to_pixel(col, row, HEX_SIZE) - cam_offset


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_at(event.position)
		if left_down and not panning and event.position.distance_to(left_press_pos) >= DRAG_THRESH:
			panning = true
			pan_anchor_mouse = left_press_pos
			pan_anchor_cam = cam_offset
		if panning:
			cam_offset = pan_anchor_cam - (event.position - pan_anchor_mouse)
			_clamp_cam()
			_refresh_view()
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
				_on_hex_clicked(_hex_at_screen(left_press_pos))
			left_down = false
			panning = false
		return
	if btn.button_index == MOUSE_BUTTON_RIGHT or btn.button_index == MOUSE_BUTTON_MIDDLE:
		if btn.pressed and play_rect.has_point(btn.position):
			panning = true
			left_down = false
			pan_anchor_mouse = btn.position
			pan_anchor_cam = cam_offset
		elif not btn.pressed:
			panning = false


func _on_hex_clicked(hex: Vector2i) -> void:
	if cpu_running:
		return
	_note_empty_hex(hex)
	if not _in_bounds(hex.x, hex.y):
		if _is_battle_phase():
			selected_unit = null
			reachable.clear()
			shoot_targets.clear()
			hex_highlights.clear()
			_refresh_hud_panel()
			_refresh_view()
		return
	match phase:
		Phase.ALLIES_BUY, Phase.AXIS_BUY:
			_click_buy(hex)
		Phase.ALLIES_BOMBARD, Phase.ALLIES_MOVE, Phase.ALLIES_SHOOT, Phase.AXIS_BOMBARD, Phase.AXIS_MOVE, Phase.AXIS_SHOOT:
			_click_battle(hex)
		Phase.RESULT:
			pass


func _click_buy(hex: Vector2i) -> void:
	if pending_buy_type == "":
		_flash_hud("先選兵種圖示")
		return
	var cols: Array = GameDefs.deploy_cols(buying_team)
	if not cols.has(hex.x):
		_flash_hud("非部署欄")
		return
	if _unit_at(hex.x, hex.y) != null:
		_flash_hud("此格已有單位")
		return
	if not _can_place_on(pending_buy_type, hex.x, hex.y):
		_flash_hud("地形不符")
		return
	var cost: int = GameDefs.UNIT_TYPES[pending_buy_type]["cost"]
	if cost > buy_points_left:
		_flash_hud("點數不足")
		return
	var u := UnitData.new(next_unit_id, pending_buy_type, buying_team, hex.x, hex.y)
	next_unit_id += 1
	units.append(u)
	buy_points_left -= cost
	var bought := pending_buy_type
	pending_buy_type = ""
	hex_highlights.clear()
	_refresh_header()
	_refresh_affordability()
	_refresh_icon_selection()
	_refresh_hud_panel()
	_set_event("花費 %d，剩餘 %d" % [cost, buy_points_left])
	_refresh_view()


func _click_battle(hex: Vector2i) -> void:
	var clicked_unit := _unit_at(hex.x, hex.y)
	var kind := _phase_kind()
	if selected_unit != null and selected_unit.team == active_team and not selected_unit.destroyed:
		if kind == "move" and not selected_unit.moved and reachable.has(hex) and clicked_unit == null:
			selected_unit.col = hex.x
			selected_unit.row = hex.y
			selected_unit.moved = true
			reachable.clear()
			hex_highlights.clear()
			_refresh_hud_panel(selected_unit)
			_flash_hud("已移動")
			_refresh_view()
			return
		var shooting := (kind == "bombard" and selected_unit.type_id == "artillery") or (kind == "direct" and selected_unit.type_id != "artillery")
		if shooting and clicked_unit != null and clicked_unit.team != active_team and not selected_unit.shot:
			if selected_unit.ammo <= 0:
				_flash_hud("沒有彈藥")
				_refresh_hud_panel(selected_unit)
				_refresh_view()
				return
			if _can_shoot(selected_unit, clicked_unit):
				_resolve_combat(selected_unit, clicked_unit)
				shoot_targets.clear()
				hex_highlights.clear()
				reachable.clear()
				var acted := selected_unit
				selected_unit = null
				_refresh_hud_panel()
				if acted != null and not acted.destroyed:
					_refresh_hud_panel(acted)
				_refresh_view()
				return
	if clicked_unit != null:
		selected_unit = clicked_unit
		reachable.clear()
		shoot_targets.clear()
		hex_highlights.clear()
		_refresh_hud_panel(selected_unit)
		if clicked_unit.team != active_team:
			_refresh_view()
			return
		if kind == "move":
			if clicked_unit.moved:
				_flash_hud("已移動")
			else:
				reachable = _compute_reachable(clicked_unit)
				for cell in reachable:
					hex_highlights.append(cell)
				highlight_mode = "move"
		elif kind == "bombard":
			if clicked_unit.type_id != "artillery":
				_flash_hud("僅火砲可射擊")
			elif clicked_unit.shot or clicked_unit.ammo <= 0:
				_flash_hud("無法砲擊")
			else:
				_prepare_shoot_highlights(clicked_unit)
		elif kind == "direct":
			if clicked_unit.type_id == "artillery":
				_flash_hud("火砲本階段不射擊")
			elif clicked_unit.shot or clicked_unit.ammo <= 0:
				_flash_hud("無法射擊")
			else:
				_prepare_shoot_highlights(clicked_unit)
		_refresh_hud_panel(selected_unit)
		_refresh_view()
		return
	selected_unit = null
	reachable.clear()
	shoot_targets.clear()
	hex_highlights.clear()
	_refresh_hud_panel()
	_refresh_view()


func _prepare_shoot_highlights(unit: UnitData) -> void:
	shoot_targets.clear()
	hex_highlights.clear()
	if unit.shot:
		return
	for u in units:
		if u.destroyed or u.team == unit.team:
			continue
		if _can_shoot(unit, u):
			shoot_targets.append(u)
			hex_highlights.append(Vector2i(u.col, u.row))
	highlight_mode = "shoot"


func _hex_on_screen(center: Vector2) -> bool:
	var pad := HEX_SIZE * 2.0
	return (
		center.x >= play_rect.position.x - pad
		and center.x <= play_rect.end.x + pad
		and center.y >= play_rect.position.y - pad
		and center.y <= play_rect.end.y + pad
	)


func _deploy_tint(col: int) -> Color:
	var allies := col < GameDefs.DEPLOY_DEPTH
	var axis := col >= GameDefs.MAP_COLS - GameDefs.DEPLOY_DEPTH
	if not allies and not axis:
		return Color(0, 0, 0, 0)
	var hot := (phase == Phase.ALLIES_BUY and allies) or (phase == Phase.AXIS_BUY and axis)
	var alpha := 0.26 if hot else 0.10
	if allies:
		return Color(0.25, 0.9, 0.35, alpha)
	return Color(0.95, 0.25, 0.22, alpha)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.08, 0.09, 0.10))
	draw_rect(play_rect, Color(0.11, 0.13, 0.12))
	if terrain.is_empty():
		return
	for row in range(GameDefs.MAP_ROWS):
		for col in range(GameDefs.MAP_COLS):
			var center := _hex_center(col, row)
			if not _hex_on_screen(center):
				continue
			var tid: String = terrain[row][col]
			var tex: Texture2D = terrain_textures.get(tid)
			var mod := Color.WHITE
			if tex == null and tid == "swamp":
				tex = terrain_textures.get("clear")
				mod = Color(0.62, 0.58, 0.32, 1)
			var dest := Rect2(
				center - Vector2(HEX_SIZE * sqrt(3.0) / 2.0, HEX_SIZE),
				Vector2(HEX_SIZE * sqrt(3.0), HEX_SIZE * 2.0)
			)
			if tex != null:
				draw_texture_rect(tex, dest, false, mod)
			var tint := _deploy_tint(col)
			if tint.a > 0.0:
				draw_colored_polygon(HexUtils.hex_corners(center, HEX_SIZE - 1.0), tint)
			var corners := HexUtils.hex_corners(center, HEX_SIZE - 0.5)
			var outline := PackedVector2Array(corners)
			outline.append(corners[0])
			draw_polyline(outline, Color(0.15, 0.15, 0.18, 0.5), 1.2, true)

	for h in hex_highlights:
		var c := _hex_center(h.x, h.y)
		var colr: Color
		match highlight_mode:
			"move":
				colr = Color(0.2, 0.75, 1.0, 0.35)
			"shoot":
				colr = Color(1.0, 0.25, 0.2, 0.4)
			"place":
				colr = Color(0.3, 1.0, 0.4, 0.35)
			_:
				colr = Color(1, 1, 0, 0.3)
		draw_colored_polygon(HexUtils.hex_corners(c, HEX_SIZE - 2.0), colr)

	if _in_bounds(hover_hex.x, hover_hex.y):
		var hc := _hex_center(hover_hex.x, hover_hex.y)
		var hcorners := HexUtils.hex_corners(hc, HEX_SIZE - 1.5)
		var houtline := PackedVector2Array(hcorners)
		houtline.append(hcorners[0])
		draw_polyline(houtline, Color(1, 1, 1, 0.7), 1.5, true)

	if selected_unit != null and not selected_unit.destroyed:
		var c := _hex_center(selected_unit.col, selected_unit.row)
		var corners := HexUtils.hex_corners(c, HEX_SIZE - 1.0)
		var outline := PackedVector2Array(corners)
		outline.append(corners[0])
		draw_polyline(outline, Color(1.0, 0.9, 0.2, 0.95), 2.5, true)

	var hex_w := HEX_SIZE * sqrt(3.0)
	for u in units:
		if u.destroyed:
			continue
		var c := _hex_center(u.col, u.row)
		if not _hex_on_screen(c):
			continue
		var tex: Texture2D = unit_textures[u.type_id]
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var dw: float
		var dh: float
		if u.type_id == "infantry":
			# Fit the opaque squad inside the pointy hex with a few pixels of margin.
			# The bounding box is wider than the slanted corners, so do not use it.
			var sm := maxf(HEX_SIZE - 3.0, 1.0)
			var sc := sm / maxf(infantry_hex_limit, 1.0)
			dw = tw * sc
			dh = th * sc
		else:
			var target := hex_w * 0.78
			var sc2 := target / maxf(tw, th)
			dw = tw * sc2
			dh = th * sc2
			if minf(dw, dh) < hex_w * 0.42:
				var boost := (hex_w * 0.5) / minf(dw, dh)
				dw *= boost
				dh *= boost
		var dest := Rect2(c - Vector2(dw, dh) * 0.5, Vector2(dw, dh))
		var tint: Color = GameDefs.TEAM_TINT[u.team]
		if u.type_id == "infantry":
			# Keep painted olive/khaki readable. Side color is the ring, not a hard multiply.
			tint = Color(0.94, 1.0, 0.90, 1.0) if u.team == GameDefs.TEAM_ALLIES else Color(1.0, 0.92, 0.90, 1.0)
		draw_texture_rect(tex, dest, false, tint)
		var ring_col: Color = GameDefs.TEAM_RING[u.team]
		var ring := HexUtils.hex_corners(c, minf(HEX_SIZE * 0.7, maxf(dw, dh) * 0.55))
		var ro := PackedVector2Array(ring)
		ro.append(ring[0])
		draw_polyline(ro, ring_col, 2.2, true)
		if u.hp < u.max_hp:
			draw_circle(c + Vector2(dw * 0.38, -dh * 0.38), 5, Color(1.0, 0.7, 0.1))

	_draw_combat_fx()


func _process(_delta: float) -> void:
	if combat_fx.is_empty():
		return
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for fx in combat_fx:
		if now - int(fx["t0"]) < int(fx["ms"]):
			keep.append(fx)
	combat_fx = keep
	queue_redraw()


func _spawn_fx(kind: String, from_hex: Vector2i, to_hex: Vector2i) -> void:
	combat_fx.append({
		"kind": kind,
		"from": from_hex,
		"to": to_hex,
		"t0": Time.get_ticks_msec(),
		"ms": 520,
	})
	queue_redraw()


func _draw_combat_fx() -> void:
	var now := Time.get_ticks_msec()
	for fx in combat_fx:
		var age := clampf(float(now - int(fx["t0"])) / float(fx["ms"]), 0.0, 1.0)
		var fade := 1.0 - age
		var a: Vector2 = _hex_center((fx["from"] as Vector2i).x, (fx["from"] as Vector2i).y)
		var b: Vector2 = _hex_center((fx["to"] as Vector2i).x, (fx["to"] as Vector2i).y)
		var kind := str(fx["kind"])
		var line_col := Color(1.0, 0.95, 0.7, fade * 0.85)
		if kind == "hit":
			line_col = Color(0.55, 0.22, 0.08, fade * 0.9)
		elif kind == "destroy":
			line_col = Color(1.0, 0.45, 0.2, fade * 0.95)
		draw_line(a, b, line_col, 2.2, true)
		if kind == "miss":
			draw_circle(b, 6.0 + age * 16.0, Color(1.0, 0.96, 0.65, fade * 0.45))
			draw_arc(b, 8.0 + age * 14.0, 0.0, TAU, 20, Color(1.0, 1.0, 0.8, fade * 0.9), 2.0, true)
		elif kind == "hit":
			draw_circle(b, 7.0 + age * 10.0, Color(0.28, 0.08, 0.04, fade * 0.8))
			draw_circle(b, 3.5, Color(0.85, 0.35, 0.12, fade * 0.9))
			draw_arc(b, 11.0 + age * 6.0, 0.0, TAU, 18, Color(0.35, 0.1, 0.05, fade), 3.0, true)
		else:
			draw_circle(b, 8.0 + age * 8.0, Color(0.2, 0.05, 0.04, fade * 0.75))
			var arm := 9.0 + age * 3.0
			var xcol := Color(1.0, 0.92, 0.85, fade)
			draw_line(b + Vector2(-arm, -arm), b + Vector2(arm, arm), xcol, 3.0, true)
			draw_line(b + Vector2(-arm, arm), b + Vector2(arm, -arm), xcol, 3.0, true)


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



func _rebuild_minimap_cache() -> void:
	# One terrain image for the whole map. Panning only redraws the view box.
	var px_w := 280
	var px_h := 180
	var img := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.13, 0.11, 1))
	if map_bounds.size.x >= 1.0 and not terrain.is_empty():
		for row in GameDefs.MAP_ROWS:
			for col in GameDefs.MAP_COLS:
				var world := map_origin + HexUtils.oddr_to_pixel(col, row, HEX_SIZE)
				var t := (world - map_bounds.position) / map_bounds.size
				var x := clampi(int(t.x * float(px_w)), 0, px_w - 1)
				var y := clampi(int(t.y * float(px_h)), 0, px_h - 1)
				var colr: Color = MINI_COLOR.get(str(terrain[row][col]), Color.GRAY)
				img.set_pixel(x, y, colr)
				if x + 1 < px_w:
					img.set_pixel(x + 1, y, colr)
				if y + 1 < px_h:
					img.set_pixel(x, y + 1, colr)
	_mini_tex = ImageTexture.create_from_image(img)

func paint_minimap(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.06, 0.07, 0.08, 1))
	var content := _minimap_content_rect(c.size)
	if content.size.x < 2.0:
		return
	c.draw_rect(content, Color(0.14, 0.15, 0.12, 1))
	if terrain.is_empty():
		return
	var scale := content.size / map_bounds.size
	var rad := HEX_SIZE * minf(scale.x, scale.y) * 0.92
	if _mini_tex != null:
		c.draw_texture_rect(_mini_tex, content, false)
	else:
		for row in range(GameDefs.MAP_ROWS):
			for col in range(GameDefs.MAP_COLS):
				var world := map_origin + HexUtils.oddr_to_pixel(col, row, HEX_SIZE)
				var center := content.position + (world - map_bounds.position) * scale
				var tid: String = terrain[row][col]
				c.draw_colored_polygon(HexUtils.hex_corners(center, rad), MINI_COLOR.get(tid, Color.GRAY))
	for u in units:
		if u.destroyed:
			continue
		var world := map_origin + HexUtils.oddr_to_pixel(u.col, u.row, HEX_SIZE)
		var center := content.position + (world - map_bounds.position) * scale
		var dot := maxf(1.5, rad * 0.42)
		c.draw_circle(center, dot, Color(0.02, 0.02, 0.02, 0.85))
		c.draw_circle(center, dot * 0.68, GameDefs.TEAM_RING[u.team])
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
	_refresh_view()


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
	_refresh_view()


func minimap_end(local: Vector2, c: Control) -> void:
	if mini_drag and not mini_moved:
		var content := _minimap_content_rect(c.size)
		_center_cam_on(_minimap_to_world(local, content))
		_refresh_view()
	mini_drag = false
	mini_moved = false


func _begin_cpu_buy() -> void:
	if cpu_running:
		return
	cpu_running = true
	_cpu_buy_async()


func _cpu_gap(base: float) -> float:
	var n := GameDefs.cpu_roster().size()
	if n >= 16:
		return minf(base, 0.1)
	if n >= 10:
		return minf(base, 0.16)
	return base


func _cpu_buy_async() -> void:
	await get_tree().create_timer(0.25).timeout
	if not is_inside_tree() or phase != Phase.AXIS_BUY:
		cpu_running = false
		return
	for type_id in GameDefs.cpu_roster():
		if not is_inside_tree() or phase != Phase.AXIS_BUY:
			break
		if _cpu_place(type_id):
			_refresh_header()
			_refresh_losses()
			_set_event("花費 %d，剩餘 %d" % [int(GameDefs.UNIT_TYPES[type_id]["cost"]), buy_points_left])
			_refresh_view()
			await get_tree().create_timer(_cpu_gap(0.38)).timeout
	cpu_running = false
	if is_inside_tree() and phase == Phase.AXIS_BUY:
		_end_buy()


func _cpu_place(type_id: String) -> bool:
	var cost := int(GameDefs.UNIT_TYPES[type_id]["cost"])
	if cost > buy_points_left:
		return false
	var cols: Array = GameDefs.deploy_cols(GameDefs.TEAM_AXIS)
	var best := Vector2i(-1, -1)
	var best_score := -1e9
	for row in range(GameDefs.MAP_ROWS):
		for col in cols:
			if _unit_at(col, row) != null or not _can_place_on(type_id, col, row):
				continue
			var spread := 0.0
			for u in units:
				if u.destroyed or u.team != GameDefs.TEAM_AXIS:
					continue
				spread += float(absi(u.row - row) + absi(u.col - col))
			# Prefer the back column and a spread along the edge.
			var score := spread + float(col) * 0.3
			if score > best_score:
				best_score = score
				best = Vector2i(col, row)
	if best.x < 0:
		return false
	var u := UnitData.new(next_unit_id, type_id, GameDefs.TEAM_AXIS, best.x, best.y)
	next_unit_id += 1
	units.append(u)
	buy_points_left -= cost
	return true


func _begin_cpu_bombard() -> void:
	if cpu_running:
		return
	cpu_running = true
	_cpu_bombard_async()


func _begin_cpu_move() -> void:
	if cpu_running:
		return
	cpu_running = true
	_cpu_move_async()


func _begin_cpu_shoot() -> void:
	if cpu_running:
		return
	cpu_running = true
	_cpu_shoot_async()


func _living_team(team: String) -> Array:
	var out: Array = []
	for u in units:
		if not u.destroyed and u.team == team:
			out.append(u)
	return out


func _cpu_finish_phase(expected: Phase) -> void:
	selected_unit = null
	reachable.clear()
	shoot_targets.clear()
	hex_highlights.clear()
	cpu_running = false
	if is_inside_tree() and phase == expected:
		_refresh_view()
		_advance_phase()


func _cpu_bombard_async() -> void:
	await get_tree().create_timer(0.18).timeout
	if not is_inside_tree() or phase != Phase.AXIS_BOMBARD:
		cpu_running = false
		return
	for u in _living_team(GameDefs.TEAM_AXIS):
		if not is_inside_tree() or phase != Phase.AXIS_BOMBARD:
			break
		if u.type_id != "artillery" or u.destroyed or u.shot or u.ammo <= 0:
			continue
		var target := _cpu_best_target(u)
		if target == null:
			continue
		_prepare_shoot_highlights(u)
		selected_unit = u
		_refresh_hud_panel(u)
		_refresh_view()
		await get_tree().create_timer(_cpu_gap(0.14)).timeout
		if not is_inside_tree() or phase != Phase.AXIS_BOMBARD or u.destroyed or target.destroyed:
			continue
		if _can_shoot(u, target):
			_resolve_combat(u, target)
			_refresh_view()
			await get_tree().create_timer(_cpu_gap(0.18)).timeout
	_cpu_finish_phase(Phase.AXIS_BOMBARD)


func _cpu_move_async() -> void:
	await get_tree().create_timer(0.12).timeout
	if not is_inside_tree() or phase != Phase.AXIS_MOVE:
		cpu_running = false
		return
	for u in _living_team(GameDefs.TEAM_AXIS):
		if not is_inside_tree() or phase != Phase.AXIS_MOVE:
			break
		if u.destroyed or u.moved:
			continue
		var dest := _cpu_pick_move(u)
		if dest == Vector2i(u.col, u.row):
			u.moved = true
			continue
		selected_unit = u
		hex_highlights.clear()
		hex_highlights.append(dest)
		highlight_mode = "move"
		_refresh_hud_panel(u)
		_refresh_view()
		await get_tree().create_timer(_cpu_gap(0.12)).timeout
		if not is_inside_tree() or phase != Phase.AXIS_MOVE or u.destroyed:
			continue
		if _unit_at(dest.x, dest.y) == null:
			u.col = dest.x
			u.row = dest.y
		u.moved = true
		hex_highlights.clear()
		_refresh_view()
	_cpu_finish_phase(Phase.AXIS_MOVE)


func _cpu_shoot_async() -> void:
	await get_tree().create_timer(0.12).timeout
	if not is_inside_tree() or phase != Phase.AXIS_SHOOT:
		cpu_running = false
		return
	for u in _living_team(GameDefs.TEAM_AXIS):
		if not is_inside_tree() or phase != Phase.AXIS_SHOOT:
			break
		if u.destroyed or u.type_id == "artillery" or u.shot or u.ammo <= 0:
			continue
		var target := _cpu_best_target(u)
		if target == null:
			continue
		_prepare_shoot_highlights(u)
		selected_unit = u
		_refresh_hud_panel(u)
		_refresh_view()
		await get_tree().create_timer(_cpu_gap(0.12)).timeout
		if not is_inside_tree() or phase != Phase.AXIS_SHOOT or u.destroyed or target.destroyed:
			continue
		if _can_shoot(u, target):
			_resolve_combat(u, target)
			_refresh_view()
			await get_tree().create_timer(_cpu_gap(0.16)).timeout
	_cpu_finish_phase(Phase.AXIS_SHOOT)


func _cpu_pick_move(unit: UnitData) -> Vector2i:
	# Greedy steps toward one town or enemy. Does not search the whole map.
	var origin := Vector2i(unit.col, unit.row)
	var goal := _cpu_goal_hex(unit)
	var pos := origin
	var spent := 0.0
	var max_m := float(unit.max_move())
	var t0 := Time.get_ticks_msec()
	for _step in range(unit.max_move()):
		if Time.get_ticks_msec() - t0 > 6:
			break
		var best_n := Vector2i(-1, -1)
		var best_score := 1.0e9
		for n in HexUtils.oddr_neighbors(pos.x, pos.y):
			if not _in_bounds(n.x, n.y):
				continue
			var other := _unit_at(n.x, n.y)
			if other != null and other.id != unit.id:
				continue
			var sc := _step_cost(unit, pos.x, pos.y, n.x, n.y)
			if sc < 0.0:
				continue
			var new_spent := spent + sc
			if sc == -2.0:
				if spent >= max_m:
					continue
				new_spent = max_m
			elif new_spent > max_m + 0.001:
				continue
			var score := float(HexUtils.axial_distance(n, goal)) * 10.0 + float(n.x) * 0.05
			var tid := _terrain_at(n.x, n.y)
			if tid == "town":
				score -= 28.0
			elif tid == "hill":
				score -= 2.0
			if score < best_score:
				best_score = score
				best_n = n
		if best_n.x < 0:
			break
		var stay := float(HexUtils.axial_distance(pos, goal)) * 10.0 + float(pos.x) * 0.05
		if _terrain_at(pos.x, pos.y) == "town":
			stay -= 36.0
		if best_score >= stay - 0.01:
			break
		var sc2 := _step_cost(unit, pos.x, pos.y, best_n.x, best_n.y)
		if sc2 == -2.0:
			spent = max_m
		else:
			spent += sc2
		unit.col = best_n.x
		unit.row = best_n.y
		pos = best_n
	unit.col = origin.x
	unit.row = origin.y
	return pos


func _cpu_goal_hex(unit: UnitData) -> Vector2i:
	var here := Vector2i(unit.col, unit.row)
	var best_town := here
	var best_td := 999999
	for t in GameDefs.town_list:
		var occ := _unit_at(t.x, t.y)
		if occ != null and occ.team == unit.team and occ.id != unit.id:
			continue
		var d := absi(t.x - here.x) + absi(t.y - here.y)
		if d < best_td:
			best_td = d
			best_town = t
	var best_enemy := here
	var best_ed := 999999
	for e in units:
		if e.destroyed or e.team == unit.team:
			continue
		var d2 := absi(e.col - here.x) + absi(e.row - here.y)
		if d2 < best_ed:
			best_ed = d2
			best_enemy = Vector2i(e.col, e.row)
	if best_ed < 999999 and best_ed + 2 < best_td:
		return best_enemy
	if best_td < 999999:
		return best_town
	return Vector2i(0, clampi(unit.row, 0, GameDefs.MAP_ROWS - 1))


func _cpu_best_target(unit: UnitData) -> UnitData:
	if unit.ammo <= 0 or unit.destroyed:
		return null
	var best: UnitData = null
	var best_score := -1e9
	var reach := _effective_range(unit) + 1
	for e in units:
		if e.destroyed or e.team == unit.team:
			continue
		if absi(e.col - unit.col) + absi(e.row - unit.row) > reach * 2:
			continue
		if not _can_shoot(unit, e):
			continue
		var res := unit.current_attack_vs(e) - _defense_of(e)
		if res < 1:
			continue
		var sc := float(res) * 10.0 + float(e.def()["cost"]) + float(e.max_hp - e.hp) * 6.0
		if e.hp <= 1:
			sc += 40.0
		else:
			sc += 18.0
		if sc > best_score:
			best_score = sc
			best = e
	return best
