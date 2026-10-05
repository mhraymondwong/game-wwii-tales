class_name UiStyle
extends RefCounted
## Shared UI helpers for 二戰風雲錄 / WWII Tales.

const UI_TEX := "res://assets/ui/processed/%s.png"
const ICON_TEX := "res://assets/ui/processed/icons/%s.png"
const CJK_FONT_PATH := "res://assets/fonts/NotoSansCJK-Regular.ttc"
const CJK_FACE_TC := 3  # Noto Sans CJK TC
const CJK_FACE_NAME := "Noto Sans CJK TC"

static var _cjk_base: FontFile = null
static var _cjk_font: Font = null
static var _cjk_face_used: String = ""


static func cjk_font() -> Font:
	if _cjk_font != null:
		return _cjk_font
	var ff := FontFile.new()
	var err := ff.load_dynamic_font(CJK_FONT_PATH)
	if err != OK:
		push_error("Failed to load CJK font: %s err=%s" % [CJK_FONT_PATH, err])
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Noto Sans CJK TC", "Noto Sans CJK HK"])
		_cjk_face_used = "SystemFont fallback"
		_cjk_font = sys
		return _cjk_font
	_cjk_base = ff
	# Godot 4.7: pick TC face via FontVariation
	var fv := FontVariation.new()
	fv.base_font = ff
	if ff.get_face_count() > CJK_FACE_TC:
		fv.set_variation_face_index(CJK_FACE_TC)
		_cjk_face_used = CJK_FACE_NAME
	else:
		_cjk_face_used = "face0"
	_cjk_font = fv
	print("CJK_FONT_FACE=", _cjk_face_used, " variation_index=", fv.get_variation_face_index(), " faces=", ff.get_face_count())
	return _cjk_font


static func cjk_face_report() -> String:
	cjk_font()
	return _cjk_face_used


static func apply_font(control: Control, size: int = 16, color: Color = Color(0.95, 0.93, 0.85)) -> void:
	var f := cjk_font()
	if control is Label:
		var lab := control as Label
		lab.add_theme_font_override("font", f)
		lab.add_theme_font_size_override("font_size", size)
		lab.add_theme_color_override("font_color", color)
	elif control is Button:
		var btn := control as Button
		btn.add_theme_font_override("font", f)
		btn.add_theme_font_size_override("font_size", size)
		btn.add_theme_color_override("font_color", Color(0.18, 0.14, 0.08))
	else:
		var theme := Theme.new()
		theme.default_font = f
		theme.default_font_size = size
		control.theme = theme


static func style_panel(panel: PanelContainer) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.10, 0.12, 0.92)
	box.set_border_width_all(2)
	box.border_color = Color(0.72, 0.62, 0.35, 0.9)
	box.set_corner_radius_all(6)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", box)


static func make_bottom_gradient() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0),
		Color(0.02, 0.03, 0.04, 0.55),
		Color(0.02, 0.03, 0.04, 0.92),
	])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0.5, 0.0)
	gtex.fill_to = Vector2(0.5, 1.0)
	gtex.width = 64
	gtex.height = 256
	var rect := TextureRect.new()
	rect.name = "BottomGradient"
	rect.texture = gtex
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	return rect


static func load_ui_texture(stem: String) -> Texture2D:
	return load(UI_TEX % stem) as Texture2D


static func load_icon_texture(stem: String) -> Texture2D:
	return load(ICON_TEX % stem) as Texture2D


static func make_click_mask(tex: Texture2D) -> BitMap:
	var img: Image = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		var err := img.decompress()
		if err != OK:
			return null
	var mask := BitMap.new()
	mask.create_from_image_alpha(img, 0.5)
	return mask


static func setup_texture_button(btn: TextureButton, stem: String, target_height: float = 64.0) -> void:
	var tex := load_ui_texture(stem)
	if tex == null:
		push_error("Missing UI texture: %s" % stem)
		return
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var sc := target_height / maxf(th, 1.0)
	var dw := tw * sc
	var dh := th * sc
	btn.custom_minimum_size = Vector2(dw, dh)
	btn.size = Vector2(dw, dh)
	var mask := make_click_mask(tex)
	if mask != null:
		btn.texture_click_mask = mask
	btn.focus_mode = Control.FOCUS_NONE
	btn.modulate = Color.WHITE
	_bind_hover(btn)


static func setup_icon_button(btn: TextureButton, stem: String, px: float = 72.0) -> void:
	var tex := load_icon_texture(stem)
	if tex == null:
		push_error("Missing icon texture: %s" % stem)
		return
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(px, px)
	btn.size = Vector2(px, px)
	var mask := make_click_mask(tex)
	if mask != null:
		btn.texture_click_mask = mask
	btn.focus_mode = Control.FOCUS_NONE
	btn.modulate = Color.WHITE
	_bind_hover(btn)


static func _bind_hover(btn: TextureButton) -> void:
	if not btn.mouse_entered.is_connected(_on_tex_btn_hover.bind(btn)):
		btn.mouse_entered.connect(_on_tex_btn_hover.bind(btn))
	if not btn.mouse_exited.is_connected(_on_tex_btn_unhover.bind(btn)):
		btn.mouse_exited.connect(_on_tex_btn_unhover.bind(btn))
	if not btn.button_down.is_connected(_on_tex_btn_down.bind(btn)):
		btn.button_down.connect(_on_tex_btn_down.bind(btn))
	if not btn.button_up.is_connected(_on_tex_btn_up.bind(btn)):
		btn.button_up.connect(_on_tex_btn_up.bind(btn))


static func _on_tex_btn_hover(btn: TextureButton) -> void:
	if not btn.button_pressed:
		btn.modulate = Color(1.14, 1.14, 1.14, 1.0)


static func _on_tex_btn_unhover(btn: TextureButton) -> void:
	btn.modulate = Color.WHITE


static func _on_tex_btn_down(btn: TextureButton) -> void:
	btn.modulate = Color(0.78, 0.78, 0.78, 1.0)


static func _on_tex_btn_up(btn: TextureButton) -> void:
	if btn.is_hovered():
		btn.modulate = Color(1.14, 1.14, 1.14, 1.0)
	else:
		btn.modulate = Color.WHITE
