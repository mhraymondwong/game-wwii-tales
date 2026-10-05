extends Control
## 二戰風雲錄 start screen — full-bleed art, logo plaque, image buttons.

const BATTLE_SCENE := "res://scenes/main.tscn"

@onready var how_to_panel: PanelContainer = $HowToPanel
@onready var menu_box: VBoxContainer = $MenuBox
@onready var logo: TextureRect = $Logo

var level_panel: PanelContainer
var custom_btn: Button


func _ready() -> void:
	_install_bottom_gradient()
	_style_ui()
	how_to_panel.visible = false
	$MenuBox/StartButton.pressed.connect(_on_start)
	$MenuBox/HowToButton.pressed.connect(_on_how_to)
	$MenuBox/QuitButton.pressed.connect(_on_quit)
	$HowToPanel/Margin/VBox/BackButton.pressed.connect(_on_back)
	_add_cpu_button()
	_build_level_picker()


func _install_bottom_gradient() -> void:
	var old := get_node_or_null("BottomGradient")
	var grad_rect := UiStyle.make_bottom_gradient()
	grad_rect.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	grad_rect.anchor_top = 0.55
	grad_rect.offset_top = 0
	grad_rect.offset_bottom = 0
	if old:
		var idx := old.get_index()
		old.queue_free()
		add_child(grad_rect)
		move_child(grad_rect, idx)
	else:
		add_child(grad_rect)
		move_child(grad_rect, 1)


func _style_ui() -> void:
	var logo_tex := UiStyle.load_ui_texture("logo")
	if logo_tex:
		logo.texture = logo_tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tw := float(logo_tex.get_width())
		var th := float(logo_tex.get_height())
		# Fit full plaque + "WWII Tales" + gold line; leave room for three menu buttons
		var target_h := 200.0
		var sc := target_h / maxf(th, 1.0)
		var dw := tw * sc
		var dh := th * sc
		logo.anchor_left = 0.5
		logo.anchor_right = 0.5
		logo.offset_left = -dw * 0.5
		logo.offset_right = dw * 0.5
		logo.offset_top = 20.0
		logo.offset_bottom = 20.0 + dh
	# Room for 開始戰鬥, 對電腦, and 地圖編輯 under the logo.
	menu_box.offset_top = -460.0
	UiStyle.setup_texture_button($MenuBox/StartButton, "btn-start", 64.0)
	UiStyle.setup_texture_button($MenuBox/HowToButton, "btn-howto", 64.0)
	UiStyle.setup_texture_button($MenuBox/QuitButton, "btn-quit", 64.0)
	UiStyle.style_panel(how_to_panel)
	UiStyle.apply_font($HowToPanel/Margin/VBox/HowTitle, 22, Color(0.95, 0.88, 0.55))
	UiStyle.apply_font($HowToPanel/Margin/VBox/HowBody, 16, Color(0.92, 0.90, 0.82))
	UiStyle.setup_texture_button($HowToPanel/Margin/VBox/BackButton, "btn-return", 64.0)


func _on_start() -> void:
	_open_levels(false)


func _add_cpu_button() -> void:
	var cpu := _brass_menu_button("對電腦", "CpuButton")
	menu_box.add_child(cpu)
	menu_box.move_child(cpu, 1)
	cpu.pressed.connect(_on_cpu)
	var editor := _brass_menu_button("地圖編輯", "EditorButton")
	menu_box.add_child(editor)
	menu_box.move_child(editor, 2)
	editor.pressed.connect(_on_editor)


func _brass_menu_button(text: String, node_name: String) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.custom_minimum_size = Vector2(220, 46)
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.22, 0.16, 0.08, 0.92)
	plate.border_color = Color(0.86, 0.72, 0.36, 1)
	plate.set_border_width_all(2)
	plate.set_corner_radius_all(8)
	plate.content_margin_left = 12
	plate.content_margin_right = 12
	var hover := plate.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.32, 0.24, 0.1, 0.96)
	btn.add_theme_stylebox_override("normal", plate)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", plate)
	UiStyle.apply_font(btn, 20, Color(0.96, 0.9, 0.7))
	btn.add_theme_color_override("font_color", Color(0.97, 0.91, 0.72))
	btn.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.82))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.78, 0.55))
	return btn


func _on_editor() -> void:
	Session.play_custom = false
	Session.vs_cpu = false
	get_tree().change_scene_to_file("res://scenes/map_editor.tscn")


func _on_cpu() -> void:
	_open_levels(true)


func _build_level_picker() -> void:
	level_panel = PanelContainer.new()
	level_panel.name = "LevelPanel"
	level_panel.visible = false
	level_panel.set_anchors_preset(Control.PRESET_CENTER)
	level_panel.offset_left = -300.0
	level_panel.offset_top = -320.0
	level_panel.offset_right = 300.0
	level_panel.offset_bottom = 320.0
	UiStyle.style_panel(level_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	level_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = "選擇關卡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_font(title, 26, Color(0.96, 0.88, 0.55))
	box.add_child(title)
	for i in range(1, GameDefs.LEVELS.size() + 1):
		var spec: Dictionary = GameDefs.level_spec(i)
		var btn := Button.new()
		btn.name = "Level%d" % i
		btn.text = "第 %d 關    %d×%d    %d 點" % [i, int(spec["cols"]), int(spec["rows"]), int(spec["points"])]
		btn.custom_minimum_size = Vector2(460, 44)
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_paint_level_button(btn, i == 1)
		btn.pressed.connect(_start_level.bind(i))
		box.add_child(btn)
	custom_btn = Button.new()
	custom_btn.name = "CustomMap"
	custom_btn.text = "自訂地圖"
	custom_btn.custom_minimum_size = Vector2(460, 44)
	custom_btn.focus_mode = Control.FOCUS_NONE
	custom_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	custom_btn.pressed.connect(_start_custom)
	box.add_child(custom_btn)
	_refresh_custom_button()
	var back := Button.new()
	back.name = "LevelBack"
	back.text = "返回"
	back.custom_minimum_size = Vector2(180, 40)
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_paint_level_button(back, false)
	back.pressed.connect(_close_levels)
	box.add_child(back)
	add_child(level_panel)


func _paint_level_button(btn: Button, hot: bool, dim: bool = false) -> void:
	var plate := StyleBoxFlat.new()
	if dim:
		plate.bg_color = Color(0.09, 0.08, 0.07, 0.72)
		plate.border_color = Color(0.36, 0.32, 0.24, 0.5)
		plate.set_border_width_all(1)
	else:
		plate.bg_color = Color(0.34, 0.26, 0.1, 0.96) if hot else Color(0.14, 0.12, 0.08, 0.94)
		plate.border_color = Color(1.0, 0.84, 0.38, 1) if hot else Color(0.55, 0.46, 0.28, 0.9)
		plate.set_border_width_all(3 if hot else 1)
	plate.set_corner_radius_all(8)
	plate.content_margin_left = 10
	plate.content_margin_right = 10
	plate.content_margin_top = 4
	plate.content_margin_bottom = 4
	var hover := plate.duplicate() as StyleBoxFlat
	if not dim:
		hover.bg_color = Color(0.42, 0.32, 0.12, 0.98)
		hover.border_color = Color(1.0, 0.9, 0.5, 1)
	btn.add_theme_stylebox_override("normal", plate)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", plate)
	btn.add_theme_stylebox_override("focus", plate)
	btn.add_theme_stylebox_override("disabled", plate)
	UiStyle.apply_font(btn, 20, Color(0.97, 0.92, 0.78))
	var ink := Color(0.48, 0.44, 0.36) if dim else (Color(1.0, 0.94, 0.72) if hot else Color(0.94, 0.9, 0.78))
	btn.add_theme_color_override("font_color", ink)
	btn.add_theme_color_override("font_hover_color", ink if dim else Color(1, 0.97, 0.86))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.78, 0.55))
	btn.add_theme_color_override("font_disabled_color", Color(0.48, 0.44, 0.36))
	btn.disabled = dim


func _open_levels(vs_cpu: bool) -> void:
	Session.vs_cpu = vs_cpu
	_refresh_custom_button()
	menu_box.visible = false
	logo.visible = false
	how_to_panel.visible = false
	level_panel.visible = true


func _close_levels() -> void:
	level_panel.visible = false
	logo.visible = true
	menu_box.visible = true


func _start_level(index: int) -> void:
	Session.play_custom = false
	Session.level = index
	GameDefs.apply_level(index)
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _refresh_custom_button() -> void:
	if custom_btn == null:
		return
	var loaded := GameDefs.load_map_file()
	var ok := not loaded.is_empty()
	if ok:
		var w := (loaded[0] as Array).size()
		custom_btn.text = "自訂地圖    %d×%d    %d 點" % [w, loaded.size(), GameDefs.CUSTOM_POINTS]
	else:
		custom_btn.text = "自訂地圖"
	_paint_level_button(custom_btn, false, not ok)


func _start_custom() -> void:
	var loaded := GameDefs.load_map_file()
	if loaded.is_empty():
		_refresh_custom_button()
		return
	Session.play_custom = true
	GameDefs.use_custom_grid(loaded)
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _on_how_to() -> void:
	menu_box.visible = false
	how_to_panel.visible = true


func _on_back() -> void:
	how_to_panel.visible = false
	menu_box.visible = true


func _on_quit() -> void:
	get_tree().quit()
