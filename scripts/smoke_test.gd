extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var start_packed: PackedScene = load("res://scenes/start_screen.tscn") as PackedScene
	if start_packed == null:
		push_error("SMOKE FAIL: could not load start_screen.tscn")
		quit(1)
		return
	var start_node: Node = start_packed.instantiate()
	root.add_child(start_node)
	await process_frame
	await process_frame
	if start_node.get_node_or_null("MenuBox/StartButton") == null:
		push_error("SMOKE FAIL: start screen missing StartButton")
		quit(1)
		return
	if start_node.get_node_or_null("MenuBox/CpuButton") == null:
		push_error("SMOKE FAIL: missing 對電腦 button")
		quit(1)
		return
	if start_node.get_node_or_null("MenuBox/EditorButton") == null:
		push_error("SMOKE FAIL: missing 地圖編輯 button")
		quit(1)
		return
	var custom := start_node.find_child("CustomMap", true, false) as Button
	if custom == null or not str(custom.text).begins_with("自訂地圖"):
		push_error("SMOKE FAIL: missing 自訂地圖 row")
		quit(1)
		return
	print("SMOKE OK: start_screen loaded custom=", custom.text, " disabled=", custom.disabled)
	start_node.queue_free()
	await process_frame

	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("SMOKE FAIL: could not load main.tscn")
		quit(1)
		return
	var root_node: Node = packed.instantiate()
	root.add_child(root_node)
	await process_frame
	await process_frame
	var phase_val = root_node.get("phase")
	if phase_val == null:
		push_error("SMOKE FAIL: battle missing phase")
		quit(1)
		return
	# Phase.ALLIES_BUY == 0
	if int(phase_val) != 0:
		push_error("SMOKE FAIL: expected ALLIES_BUY phase 0, got %s" % phase_val)
		quit(1)
		return
	if root_node.get_node_or_null("UI/HeaderLogo") == null:
		push_error("SMOKE FAIL: missing HeaderLogo")
		quit(1)
		return
	if root_node.get_node_or_null("UI/TopBar") == null:
		push_error("SMOKE FAIL: missing TopBar")
		quit(1)
		return
	if root_node.get_node_or_null("UI/FactionBadge") == null:
		push_error("SMOKE FAIL: missing FactionBadge")
		quit(1)
		return
	if root_node.get_node_or_null("UI/HudPanel/HudMargin/HudVBox/HudPortrait") == null:
		push_error("SMOKE FAIL: missing HudPortrait")
		quit(1)
		return
	if root_node.get_node_or_null("UI/IconTray/SlotHeavy/SelectRing/Icon") == null:
		push_error("SMOKE FAIL: missing heavy tank icon")
		quit(1)
		return
	if root_node.get_node_or_null("UI/IconTray/SlotLight/SelectRing/Icon") == null:
		push_error("SMOKE FAIL: missing light tank icon")
		quit(1)
		return
	if root_node.get_node_or_null("UI/IconTray/SlotHalftrack") != null:
		push_error("SMOKE FAIL: halftrack buy slot still present")
		quit(1)
		return
	var conf = root_node.get_node_or_null("UI/ConfirmButton") as TextureButton
	if conf == null or conf.texture_normal == null:
		push_error("SMOKE FAIL: missing confirm icon")
		quit(1)
		return
	if root_node.get_node_or_null("UI/HudPanel") == null:
		push_error("SMOKE FAIL: missing HudPanel")
		quit(1)
		return
	var cols = root_node.get("terrain")
	if cols == null or (cols as Array).size() != 10:
		push_error("SMOKE FAIL: map rows expected 10")
		quit(1)
		return
	if ((cols as Array)[0] as Array).size() != 16:
		push_error("SMOKE FAIL: map cols expected 16")
		quit(1)
		return
	if root_node.get_node_or_null("UI/MinimapFrame/MinimapView") == null:
		push_error("SMOKE FAIL: missing MinimapView")
		quit(1)
		return
	var round_lab := root_node.get_node_or_null("UI/RoundLabel") as Label
	if round_lab == null or not str(round_lab.text).contains("部署"):
		push_error("SMOKE FAIL: deployment round text missing, got %s" % (round_lab.text if round_lab else "null"))
		quit(1)
		return
	# textures for new units
	var ut = root_node.get("unit_textures")
	if ut == null or not (ut as Dictionary).has("recon"):
		push_error("SMOKE FAIL: missing recon texture")
		quit(1)
		return
	var event_lab := root_node.get_node_or_null("UI/HudPanel/HudMargin/HudVBox/HudEvent") as Label
	if event_lab == null or not str(event_lab.text).contains("剩餘"):
		push_error("SMOKE FAIL: buy points line missing, got %s" % (event_lab.text if event_lab else "null"))
		quit(1)
		return
	var loss_lab := root_node.get_node_or_null("UI/HudPanel/HudMargin/HudVBox/HudLosses") as Label
	if loss_lab == null or not str(loss_lab.text).contains("盟軍損失") or not str(loss_lab.text).contains("軸心損失"):
		push_error("SMOKE FAIL: loss tally missing, got %s" % (loss_lab.text if loss_lab else "null"))
		quit(1)
		return
	var bgm := root.get_node_or_null("Bgm/BgmPlayer") as AudioStreamPlayer
	if bgm == null or bgm.stream == null:
		push_error("SMOKE FAIL: BGM player missing")
		quit(1)
		return
	if bgm.stream is AudioStreamWAV:
		var wav := bgm.stream as AudioStreamWAV
		if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD or wav.loop_end < 2:
			push_error("SMOKE FAIL: BGM not looping forward, mode=%s end=%s" % [wav.loop_mode, wav.loop_end])
			quit(1)
			return
	print("SMOKE OK: battle loaded; phase=", phase_val, " map=16x10 hex=", root_node.get("HEX_SIZE"), " units=", (root_node.get("units") as Array).size())
	print("SMOKE FONT=", UiStyle.cjk_face_report())
	print("SMOKE BGM playing=", bgm.playing, " loop_end=", (bgm.stream as AudioStreamWAV).loop_end)
	var texs = root_node.get("terrain_textures")
	if texs == null or (texs as Dictionary).get("swamp") == null:
		push_error("SMOKE FAIL: swamp texture missing")
		quit(1)
		return
	var utex = root_node.get("unit_textures")
	if utex == null or (utex as Dictionary).get("light_tank") == null or (utex as Dictionary).get("heavy_tank") == null:
		push_error("SMOKE FAIL: tank textures missing")
		quit(1)
		return
	root_node.queue_free()
	await process_frame
	var editor_packed: PackedScene = load("res://scenes/map_editor.tscn") as PackedScene
	if editor_packed == null:
		push_error("SMOKE FAIL: map editor scene missing")
		quit(1)
		return
	var editor := editor_packed.instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame
	if editor.find_child("TryButton", true, false) == null:
		push_error("SMOKE FAIL: editor missing 試玩")
		quit(1)
		return
	if editor.find_child("GenerateButton", true, false) == null:
		push_error("SMOKE FAIL: editor missing 自動生成")
		quit(1)
		return
	var editor_grid = editor.get("grid")
	if editor_grid == null or (editor_grid as Array).size() != 16:
		push_error("SMOKE FAIL: editor map is not 24x16 rows")
		quit(1)
		return
	if editor.get_node_or_null("UI/ActionRow") != null:
		push_error("SMOKE FAIL: action row still on the bottom")
		quit(1)
		return
	if editor.get_node_or_null("UI/RightColumn/ActionGrid/GenerateButton") == null:
		push_error("SMOKE FAIL: right panel missing generate")
		quit(1)
		return
	var size_lab := editor.get_node_or_null("UI/RightColumn/SizeLabel") as Label
	if size_lab == null or size_lab.text != "24×16":
		push_error("SMOKE FAIL: size line expected 24×16 got %s" % (size_lab.text if size_lab else "null"))
		quit(1)
		return
	var gen := editor.get_node("UI/RightColumn/ActionGrid/GenerateButton") as Button
	if gen.text != "":
		push_error("SMOKE FAIL: action button has a caption")
		quit(1)
		return
	editor.grid[1][2] = "town"
	editor.call("_resize_to", 18, 10)
	if int(editor.get("cols")) != 18 or int(editor.get("rows")) != 10:
		push_error("SMOKE FAIL: resize did not apply")
		quit(1)
		return
	if str((editor.grid[1] as Array)[2]) != "town":
		push_error("SMOKE FAIL: resize dropped painted terrain")
		quit(1)
		return
	if str((editor.grid[0] as Array)[17]) != "clear":
		push_error("SMOKE FAIL: new column was not clear")
		quit(1)
		return
	editor.call("_resize_to", 4, 2)
	if int(editor.get("cols")) != 12 or int(editor.get("rows")) != 8:
		push_error("SMOKE FAIL: size limits not applied got %s x %s" % [editor.get("cols"), editor.get("rows")])
		quit(1)
		return
	await process_frame
	var back := editor.get_node("UI/RightColumn/ActionGrid/BackButton") as Button
	var panel := editor.get_node("UI/RightPanel") as Control
	var back_end := back.get_global_rect().end.y
	var panel_end := panel.get_global_rect().end.y
	if back_end > panel_end + 1.0:
		push_error("SMOKE FAIL: back button overflows right panel %.1f > %.1f" % [back_end, panel_end])
		quit(1)
		return
	var brush := editor.get_node("UI/BrushRow") as Control
	var brush_rect := brush.get_global_rect()
	var panel_rect := panel.get_global_rect()
	if brush_rect.intersects(panel_rect):
		push_error("SMOKE FAIL: brushes overlap the right panel")
		quit(1)
		return
	if editor.get_node_or_null("UI/MinimapFrame/MinimapView") == null:
		push_error("SMOKE FAIL: editor missing minimap")
		quit(1)
		return
	if panel_rect.position.x < 1000.0:
		push_error("SMOKE FAIL: right panel not on the right got x=%.1f" % panel_rect.position.x)
		quit(1)
		return
	print("SMOKE OK: map editor 24x16 right panel")
	quit(0)
