extends Control
const HelpText = preload("res://data/help.gd")
const CardDefsM = preload("res://data/cards.gd")
const Art = preload("res://scripts/art.gd")
const Puzzles = preload("res://data/puzzles.gd")
const Meta = preload("res://scripts/meta.gd")
const MusicDirector = preload("res://scripts/music.gd")
const AudioCfg = preload("res://scripts/audio.gd")

# 《全明星杀》V0.1 单机版外壳：
# 主页（5人身份场入口 + 人物图鉴入口）/ 人物图鉴（按系列分类）/ 角色详情 / 对战占位页
# 全部界面在此以代码构建，方便快速迭代；对战逻辑在后续版本接入。

const C_BG_TOP := Color(1.0, 0.85, 0.92)
const C_BG_BOT := Color(0.85, 0.93, 1.0)
const C_PINK := Color(1.0, 0.45, 0.65)
const C_PINK_DEEP := Color(0.92, 0.30, 0.52)
const C_PURPLE := Color(0.62, 0.55, 0.95)
const C_CREAM := Color(1.0, 0.98, 0.95)
const C_INK := Color(0.35, 0.25, 0.35)
const C_INK_SOFT := Color(0.55, 0.45, 0.55)
const C_WHITE := Color(1, 1, 1)
const C_GOLD := Color(0.91, 0.64, 0.24)
const C_PLATE := Color(1.0, 0.36, 0.54)
const C_SKY := Color(0.30, 0.62, 0.92)

var font_reg: Font
var font_bold: Font
var screen_root: Control
var bg: Control
var veil_ref: ColorRect
var vig_ref: TextureRect
var petal_far: CPUParticles2D
var petal_near: CPUParticles2D
var theme_night := false
var bg_tex_ref: TextureRect
var music: MusicDirector


class PetalBG:
	extends Control
	var top_col: Color
	var bot_col: Color
	var petal_col := Color(1, 1, 1, 0.35)
	var rng := RandomNumberGenerator.new()

	func _ready() -> void:
		rng.seed = 20261114
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# 纵向柔和渐变（分段矩形模拟）
		var steps := 32
		for i in steps:
			var t0 := float(i) / steps
			var col := top_col.lerp(bot_col, t0)
			draw_rect(Rect2(0, size.y * t0, size.x, size.y / steps + 2.0), col)
		# 柔光圆斑
		for i in 14:
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			var r := rng.randf_range(40.0, 130.0)
			draw_circle(p, r, Color(1, 1, 1, 0.10))
		# 樱花瓣（小椭圆近似：小圆 + 高光）
		for i in 46:
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			var r := rng.randf_range(7.0, 15.0)
			draw_circle(p, r, petal_col)
			draw_circle(p + Vector2(r * 0.5, r * 0.4), r * 0.55, Color(1, 0.75, 0.85, 0.30))


func _ready() -> void:
	# V0.30：带命令行参数（自测/截图）运行时，局外数据写到独立的测试文件，不碰玩家存档
	if not OS.get_cmdline_user_args().is_empty():
		Meta.reset_for_test("user://meta_test.json")
	if OS.has_feature("android"):
		Engine.max_fps = 30  # 安卓端封顶 30fps：降低长时对局发热与被系统杀进程的风险
	font_reg = load("res://assets/fonts/NotoSansSC-Regular.otf")
	font_bold = load("res://assets/fonts/NotoSansSC-Bold.otf")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bgtr := TextureRect.new()
	bgtr.texture = load("res://assets/bg/bg_blossom_day.webp")
	bgtr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bgtr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bgtr.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bgtr)
	bgtr.set_anchors_preset(Control.PRESET_FULL_RECT)
	bgtr.position = Vector2(-20, -24)
	bgtr.size = Vector2(1960, 1128)
	bg = bgtr
	bg_tex_ref = bgtr
	var veil := ColorRect.new()
	veil_ref = veil
	veil.color = Color(1, 1, 1, 0.08)
	veil.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(veil)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.position = Vector2.ZERO
	veil.size = Vector2(1920, 1080)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.24, 0.09, 0.20, 0.0), Color(0.24, 0.09, 0.20, 0.22)])
	var gt2 := GradientTexture2D.new()
	gt2.gradient = grad
	gt2.fill = GradientTexture2D.FILL_RADIAL
	gt2.fill_from = Vector2(0.5, 0.47)
	gt2.fill_to = Vector2(0.5, 1.08)
	gt2.width = 960
	gt2.height = 540
	var vig := TextureRect.new()
	vig_ref = vig
	vig.texture = gt2
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(vig)
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.position = Vector2.ZERO
	vig.size = Vector2(1920, 1080)
	petal_far = _make_petals(30, false, 26.0, 48.0, 15.0)
	add_child(petal_far)
	petal_near = _make_petals(14, true, 55.0, 95.0, 9.0)
	add_child(petal_near)
	screen_root = Control.new()
	screen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen_root)
	# V0.26 长按说明卡（全局唯一、复用）
	if IntroPop.inst == null:
		add_child(IntroPop.new())
	# V0.32：常驻背景音乐（Music 总线；主页/对局/紧张残局切换，详见 scripts/music.gd）
	music = MusicDirector.new()
	add_child(music)
	music.play_scene("home")
	_fit_wide()
	get_tree().root.size_changed.connect(_fit_wide)
	if OS.get_cmdline_user_args().has("--night"):
		theme_night = true  # 截图自测：夜主题
		apply_theme()
	show_home()
	_maybe_shot()


func apply_theme() -> void:
	if bg_tex_ref != null:
		bg_tex_ref.texture = load("res://assets/bg/bg_festival_night.webp") if theme_night else load("res://assets/bg/bg_blossom_day.webp")
	if veil_ref != null:
		veil_ref.color = Color(0.08, 0.06, 0.22, 0.20) if theme_night else Color(1, 1, 1, 0.08)
	var pm := Color(0.72, 0.78, 1.0) if theme_night else Color(1, 1, 1)
	if petal_far != null:
		petal_far.modulate = pm
	if petal_near != null:
		petal_near.modulate = pm


func toggle_theme() -> void:
	theme_night = not theme_night
	apply_theme()
	show_home()


# 仅供开发自测：带 --shot=home|gallery|detail|battle 运行时自动跳转并截图退出
var ui_bs: BattleScreen

func _maybe_shot() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--soak" or a.begins_with("--soak="):
			_run_soak()
			return
	if OS.get_cmdline_user_args().has("--uitest"):
		_run_ui_test()
		return
	# V0.24 新增自测：--stress=<局数>[,<模式>][,<种子>] 多种子压力测试；--regtest 回归断言；--uiplay=<局数> 真人路径随机点选
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stress=") or a == "--regtest" or a.begins_with("--uiplay="):
			var TS = load("res://scripts/selftest.gd")
			var ts = TS.new()
			add_child(ts)
			ts.run(self, a)
			return
	if OS.get_cmdline_user_args().has("--engtest"):
		_run_eng_test()
		return
	if OS.get_cmdline_user_args().has("--ybtest"):
		_run_yb_test()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--modetest="):
			_run_mode_test(a.trim_prefix("--modetest="))
			return
	if OS.get_cmdline_user_args().has("--simulate"):
		start_simulation()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sample2="):
			var key2 := a.trim_prefix("--sample2=")
			for ch in screen_root.get_children():
				ch.queue_free()
			await get_tree().create_timer(0.2).timeout
			var SUI2 = load("res://scripts/sample_ui2.gd")
			var sui2 = SUI2.new()
			screen_root.add_child(sui2)
			sui2.build(key2)
			await get_tree().create_timer(0.9).timeout
			await RenderingServer.frame_post_draw
			var simg3 := get_viewport().get_texture().get_image()
			simg3.save_png("/tmp/ask_sample2_%s.png" % key2)
			get_tree().quit()
			return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sample="):
			var key := a.trim_prefix("--sample=")
			for ch in screen_root.get_children():
				ch.queue_free()
			await get_tree().create_timer(0.2).timeout
			var SUI = load("res://scripts/sample_ui.gd")
			var sui = SUI.new()
			screen_root.add_child(sui)
			sui.build(key)
			await get_tree().create_timer(0.9).timeout
			await RenderingServer.frame_post_draw
			var simg2 := get_viewport().get_texture().get_image()
			simg2.save_png("/tmp/ask_sample_%s.png" % key)
			get_tree().quit()
			return
	var target := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			target = a.trim_prefix("--shot=")
	if target == "":
		return
	await get_tree().create_timer(0.5).timeout
	if target == "draft":
		show_battle()
		var bs2: BattleScreen = null
		for ch in screen_root.get_children():
			if ch is BattleScreen:
				bs2 = ch
		bs2.start_match(false)
		await get_tree().create_timer(2.2).timeout
		await RenderingServer.frame_post_draw
		var dimg := get_viewport().get_texture().get_image()
		dimg.save_png("/tmp/ask_shot_draft.png")
		get_tree().quit()
		return
	if target.begins_with("v25_"):
		await _shot_v25(target)
		return
	if target.begins_with("v26_"):
		await _shot_v26(target)
		return
	if target.begins_with("v27_"):
		await _shot_v27(target)
		return
	if target == "table2":
		show_battle()
		var bs4: BattleScreen = null
		for ch in screen_root.get_children():
			if ch is BattleScreen:
				bs4 = ch
		bs4.start_match(false)
		for step in 300:
			await get_tree().create_timer(0.7).timeout
			if not is_instance_valid(bs4) or bs4.game_over:
				break
			if bs4.draft_layer != null and bs4.draft_layer.visible:
				for b in bs4.draft_layer.get_children():
					if b is Button:
						(b as Button).pressed.emit()
						break
				continue
			if step < 6 and bs4.prompt_panel.visible and bs4.prompt_btns.get_child_count() > 0:
				_drv_first(bs4)
				continue
			if step >= 6:
				await RenderingServer.frame_post_draw
				var timg2 := get_viewport().get_texture().get_image()
				timg2.save_png("/tmp/ask_shot_table.png")
				get_tree().quit()
				return
		get_tree().quit()
		return
	if target == "settle" or target == "dying" or target == "burst" or target == "yburst":
		show_battle()
		var bsx: BattleScreen = null
		for ch in screen_root.get_children():
			if ch is BattleScreen:
				bsx = ch
		bsx.start_match(false)
		for step in 40:
			await get_tree().create_timer(0.5).timeout
			if not is_instance_valid(bsx):
				break
			if bsx.draft_layer != null and bsx.draft_layer.visible:
				for b in bsx.draft_layer.get_children():
					if b is Button:
						(b as Button).pressed.emit()
						break
				continue
			if bsx.prompt_panel.visible and bsx.prompt_btns.get_child_count() > 0:
				_drv_first(bsx)
				continue
			if step >= 5:
				break
		if target == "settle":
			var dmgv := [7, 5, 3, 4, 2]
			for i in bsx.players.size():
				bsx.players[i]["stat_damage"] = dmgv[i]
				bsx.players[i]["stat_taken"] = 9 - i
				bsx.players[i]["stat_kills"] = 1 if i == 0 else 0
				bsx.players[i]["stat_heal"] = i
			bsx.players[3]["alive"] = false
			bsx.players[4]["alive"] = false
			bsx.end_game("主公阵营获胜！")
		elif target == "dying":
			bsx._eng_fx("dying", {"seat": 2})
		elif target == "yburst":
			bsx._eng_fx("yingbian", {"seat": 2, "text": "应变·目标+"})
			bsx._eng_fx("attack", {"src_seat": 2, "tgt_seat": 0, "nature": "冰"})
		else:
			bsx._eng_fx("attack", {"src_seat": 2, "tgt_seat": 0, "nature": "火"})
		await get_tree().create_timer(0.34 if target == "burst" or target == "yburst" else 0.8).timeout
		await RenderingServer.frame_post_draw
		var simg := get_viewport().get_texture().get_image()
		simg.save_png("/tmp/ask_shot_%s.png" % target)
		get_tree().quit()
		return
	if target == "ddz" or target == "duel":
		show_battle_mode("doudizhu" if target == "ddz" else "duel")
		var bsm: BattleScreen = null
		for ch in screen_root.get_children():
			if ch is BattleScreen:
				bsm = ch
		bsm.start_match(false)
		for step in 300:
			await get_tree().create_timer(0.7).timeout
			if not is_instance_valid(bsm) or bsm.game_over:
				break
			if bsm.draft_layer != null and bsm.draft_layer.visible:
				for b in bsm.draft_layer.get_children():
					if b is Button:
						(b as Button).pressed.emit()
						break
				continue
			if step < 6 and bsm.prompt_panel.visible and bsm.prompt_btns.get_child_count() > 0:
				_drv_first(bsm)
				continue
			if step >= 6:
				await RenderingServer.frame_post_draw
				var mimg := get_viewport().get_texture().get_image()
				mimg.save_png("/tmp/ask_shot_%s.png" % target)
				get_tree().quit()
				return
		get_tree().quit()
		return
	if target == "table":
		show_battle()
		var bs3: BattleScreen = null
		for ch in screen_root.get_children():
			if ch is BattleScreen:
				bs3 = ch
		bs3.start_match(false)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for step in 300:
			await get_tree().create_timer(0.7).timeout
			if not is_instance_valid(bs3) or bs3.game_over:
				break
			if bs3.draft_layer != null and bs3.draft_layer.visible:
				for b in bs3.draft_layer.get_children():
					if b is Button:
						(b as Button).pressed.emit()
						break
				continue
			if bs3.prompt_panel.visible and bs3.prompt_btns.get_child_count() > 0:
				_drv_first(bs3)
				continue
			if bs3.in_play_phase and step % 3 == 0 and bs3.end_play_btn != null and not bs3.end_play_btn.disabled:
				bs3.end_play_btn.pressed.emit()
			if step >= 16:
				await RenderingServer.frame_post_draw
				var timg := get_viewport().get_texture().get_image()
				timg.save_png("/tmp/ask_shot_table.png")
				get_tree().quit()
				return
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		var simg := get_viewport().get_texture().get_image()
		simg.save_png("/tmp/ask_shot_table.png")
		get_tree().quit()
		return
	if target == "cardwall":
		await _shot_cardwall()
		return
	if target in ["records", "tutorial", "tutorial2", "settings"]:
		await _shot_v30(target)
		return
	match target:
		"gallery":
			show_gallery()
		"detail":
			show_detail(Characters.LIST[0])
		"battle":
			show_battle()
		"ddzsetup":
			show_battle_mode("doudizhu")
		"duelsetup":
			show_battle_mode("duel")
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/ask_shot_%s.png" % target)
	get_tree().quit()


func clear_screen() -> void:
	for ch in screen_root.get_children():
		ch.queue_free()


func lbl(text: String, size: int, color: Color = C_INK, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold if bold else font_reg)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func style(color: Color, radius: int = 24, border: Color = Color(0, 0, 0, 0), bw: int = 0, shadow: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	if shadow:
		s.shadow_color = Color(0.35, 0.15, 0.25, 0.30)
		s.shadow_size = 12
		s.shadow_offset = Vector2(0, 6)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	return s


func _tight_sb(sb: StyleBoxFlat, h: int, v: int) -> StyleBoxFlat:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


func _wire_btn_bounce(b: Button) -> void:
	if bool(b.get_meta("_bounce_wired", false)):
		return
	b.set_meta("_bounce_wired", true)
	b.ready.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.button_down.connect(func() -> void:
		if b.disabled or float(b.get_meta("drag_px", 0.0)) > 10.0:
			return
		b.pivot_offset = b.size * 0.5
		var tw := create_tween().bind_node(b)
		tw.tween_property(b, "scale", Vector2(0.965, 0.965), 0.07))
	b.button_up.connect(func() -> void:
		var tw2 := create_tween().bind_node(b)
		tw2.tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


func _style_btn(b: Button, bg: Color, border: Color, fg: Color = C_WHITE, radius: int = 18, bw: int = 2, shadow: bool = true, pad: Vector2i = Vector2i(-1, -1), bounce: bool = true, hover_border: Color = Color(-1, 0, 0, 0)) -> Button:
	var hb: Color = hover_border if hover_border.r >= 0.0 else border
	var n_sb := style(bg, radius, border, bw, shadow)
	var h_sb := style(bg.lightened(0.08), radius, hb, bw, shadow)
	var p_sb := style(bg.darkened(0.08), radius, hb, bw, false)
	var d_sb := style(Color(0.76, 0.73, 0.80, 0.92), radius, Color(0.68, 0.65, 0.72, 0.70), mini(bw, 2), false)
	if pad.x >= 0:
		for sb_i in [n_sb, h_sb, p_sb, d_sb]:
			_tight_sb(sb_i, pad.x, pad.y)
	b.add_theme_stylebox_override("normal", n_sb)
	b.add_theme_stylebox_override("hover", h_sb)
	b.add_theme_stylebox_override("pressed", p_sb)
	b.add_theme_stylebox_override("disabled", d_sb)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	var lum := 0.299 * fg.r + 0.587 * fg.g + 0.114 * fg.b
	b.add_theme_color_override("font_disabled_color", Color(0.96, 0.95, 0.98, 0.78) if lum > 0.65 else Color(0.55, 0.52, 0.58))
	if bounce:
		_wire_btn_bounce(b)
	return b


func cute_button(text: String, sub: String, bg_color: Color, min_size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", style(bg_color, 26, C_GOLD, 3, true))
	b.add_theme_stylebox_override("hover", style(bg_color.lightened(0.08), 26, Color(1.0, 0.88, 0.52), 3, true))
	b.add_theme_stylebox_override("pressed", style(bg_color.darkened(0.08), 26, C_GOLD, 3, false))
	b.add_theme_stylebox_override("disabled", style(Color(0.66, 0.63, 0.70, 0.92), 26, Color(0.78, 0.75, 0.82, 0.65), 2, false))
	var gloss := Panel.new()
	gloss.mouse_filter = MOUSE_FILTER_IGNORE
	gloss.set_anchors_preset(Control.PRESET_TOP_WIDE)
	gloss.offset_left = 4
	gloss.offset_right = -4
	gloss.offset_top = 3
	gloss.offset_bottom = maxf(28.0, min_size.y * 0.42)
	gloss.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.18), 22))
	b.add_child(gloss)
	var rim := Panel.new()
	rim.mouse_filter = MOUSE_FILTER_IGNORE
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rim.offset_left = 5
	rim.offset_top = 5
	rim.offset_right = -5
	rim.offset_bottom = -5
	rim.add_theme_stylebox_override("panel", style(Color(0, 0, 0, 0), 21, Color(1.0, 0.94, 0.78, 0.40), 1))
	b.add_child(rim)
	Art.add_corners(b, min_size, clampf(min_size.y * 0.24, 20.0, 32.0), 1.0)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	var t_fs := (38 if min_size.y <= 112 else 44) if sub != "" else (26 if min_size.x <= 240 else 32)
	var t := lbl(text, t_fs, Color(1.0, 0.98, 0.92), true, HORIZONTAL_ALIGNMENT_CENTER)
	t.clip_text = true
	t.add_theme_color_override("font_outline_color", Color(0.22, 0.08, 0.18, 0.88))
	t.add_theme_constant_override("outline_size", 6)
	t.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_child(t)
	var s_lbl: Label = null
	if sub != "":
		var s := lbl(sub, 23, Color(1.0, 0.96, 0.86, 0.96), true, HORIZONTAL_ALIGNMENT_CENTER)
		s.clip_text = true
		s.add_theme_color_override("font_outline_color", Color(0.18, 0.06, 0.16, 0.82))
		s.add_theme_constant_override("outline_size", 4)
		s.mouse_filter = MOUSE_FILTER_IGNORE
		vb.add_child(s)
		s_lbl = s
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 10
	vb.offset_right = -10
	b.add_child(vb)
	b.set_meta("_last_dis", false)
	b.draw.connect(func() -> void:
		var cur_dis := b.disabled
		if bool(b.get_meta("_last_dis", false)) != cur_dis:
			b.set_meta("_last_dis", cur_dis)
			t.modulate.a = 0.62 if cur_dis else 1.0
			if s_lbl != null:
				s_lbl.modulate.a = 0.62 if cur_dis else 1.0
			gloss.modulate.a = 0.25 if cur_dis else 1.0)
	_wire_btn_bounce(b)
	b.pressed.connect(func() -> void: AudioCfg.play_ui(self, "click"))
	return b


func back_bar(title: String, back_to: Callable, back_text: String = "← 返回主页") -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	var back := Button.new()
	back.text = back_text
	back.custom_minimum_size = Vector2(220, 68)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_override("font", font_reg)
	back.add_theme_font_size_override("font_size", 30)
	_style_btn(back, Color(1, 1, 1, 0.90), C_GOLD, C_PINK_DEEP, 20, 2, true, Vector2i(16, 10), true, C_PINK)
	back.pressed.connect(func() -> void:
		AudioCfg.play_ui(self, "click")
		back_to.call())
	bar.add_child(back)
	var t := Art.halo(lbl(title, 46, C_INK, true), 10)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(t)
	return bar


func page_margin() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 48)
	m.add_theme_constant_override("margin_right", 48)
	m.add_theme_constant_override("margin_top", 36)
	m.add_theme_constant_override("margin_bottom", 36)
	screen_root.add_child(m)
	return m


# ---------------- 主页 ----------------

func show_home() -> void:
	if music != null:
		music.play_scene("home")
	clear_screen()
	var m := page_margin()
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	m.add_child(vb)

	# V0.41 手杀式顶部玩家状态与曲风金栏
	var top_bar := PanelContainer.new()
	var tb_sb := style(Color(0.16, 0.08, 0.22, 0.86), 18, C_GOLD, 2, true)
	tb_sb.content_margin_left = 20
	tb_sb.content_margin_right = 20
	tb_sb.content_margin_top = 8
	tb_sb.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", tb_sb)
	var top_hb := HBoxContainer.new()
	top_hb.add_theme_constant_override("separation", 18)
	top_bar.add_child(top_hb)
	var rate_str := Meta.win_rate_text("all")
	var bstrk := Meta.best_streak()
	var prof_txt := "🌸 星樱首席牌手  ·  战绩 %s%s" % [rate_str if rate_str != "—" else "0 局", ("  ·  🔥最高 %d 连胜" % bstrk) if bstrk > 0 else ""]
	var prof_l := lbl(prof_txt, 22, Color(1.0, 0.95, 0.86), true)
	prof_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	top_hb.add_child(prof_l)
	var bgm_l := lbl("🎵 正在播放：《%s》" % MusicDirector.track_title("home"), 21, Color(1.0, 0.84, 0.52), true, HORIZONTAL_ALIGNMENT_CENTER)
	bgm_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bgm_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	top_hb.add_child(bgm_l)
	var beans_l := lbl("🪙 欢斗豆：%d" % Meta.beans(), 22, Color(1.0, 0.86, 0.36), true)
	beans_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	top_hb.add_child(beans_l)
	var style_b := Button.new()
	style_b.focus_mode = Control.FOCUS_NONE
	style_b.text = "🎼 " + MusicDirector.style_label()
	style_b.custom_minimum_size = Vector2(198, 46)
	style_b.add_theme_font_override("font", font_bold)
	style_b.add_theme_font_size_override("font_size", 20)
	_style_btn(style_b, Color(0.32, 0.16, 0.42, 0.95), C_GOLD, Color(1.0, 0.96, 0.86), 14, 2, false, Vector2i(14, 6))
	style_b.pressed.connect(func() -> void:
		AudioCfg.play_ui(self, "click")
		if music != null:
			music.cycle_style()
		else:
			var nx := "classic" if MusicDirector.style_key() == "sakura" else "sakura"
			AudioCfg.set_v("bgm_style", nx)
		show_home())
	top_hb.add_child(style_b)
	vb.add_child(top_bar)

	var title := lbl("全明星杀", 72, C_PINK_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(1, 0.97, 0.90, 0.92))
	title.add_theme_color_override("font_shadow_color", Color(0.28, 0.08, 0.20, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 5)
	vb.add_child(title)
	var sub := Art.halo(lbl("━━ ✦  A L L   S T A R   K I L L  ·  二次元学园策略卡牌对战  ✦ ━━", 24, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER), 8)
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	vb.add_child(sub)

	# 主页看板角色卡带 + 二次元语音台词互动气泡
	var strip := HBoxContainer.new()
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 22)
	home_showcase_ids = Meta.get_showcase(Characters.LIST)
	for slot_i in home_showcase_ids.size():
		var pid := String(home_showcase_ids[slot_i])
		var ch_d := Characters.by_id(pid)
		if ch_d.is_empty():
			ch_d = Characters.LIST[slot_i % Characters.LIST.size()]
		var wrap_b := Button.new()
		wrap_b.flat = true
		wrap_b.focus_mode = Control.FOCUS_NONE
		wrap_b.custom_minimum_size = Vector2(166, 198)
		var cc := Art.cg_card(ch_d, Vector2(166, 198), {"zoom": 0.62, "face_y": 0.34, "title": true, "hp": false, "fs": 19})
		wrap_b.add_child(cc)
		_attach_l2d_breath(cc, float(slot_i) * 0.7, 0.018, 2.2)
		if _home_touch_slot == slot_i:
			_home_touch_slot = -1
			cc.scale = Vector2(0.86, 0.86)
			var ptw := create_tween().bind_node(cc)
			ptw.tween_property(cc, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_spawn_touch_burst(wrap_b, Vector2(83, 86), ["💕", "🌸", "✨"], "+2♥")
		wrap_b.set_meta("intro", IntroPop.char_spec(ch_d))
		var idx_s := slot_i
		wrap_b.pressed.connect(func() -> void:
			Meta.touch_char(pid, 2)
			_home_touch_slot = idx_s
			_on_home_showcase_clicked(idx_s)
			var new_pid := String(home_showcase_ids[idx_s]) if idx_s < home_showcase_ids.size() else pid
			if not AudioCfg.play_cv(self, new_pid, "touch"):
				AudioCfg.play_ui(self, "skill"))
		strip.add_child(wrap_b)
	vb.add_child(strip)

	var lead_id := String(home_showcase_ids[0]) if not home_showcase_ids.is_empty() else "sena"
	var lead_ch := Characters.by_id(lead_id)
	var lead_nm := String(lead_ch.get("name", "白石星奈"))
	var lead_line := BattleScreen.line_for(lead_id, "skill")
	if lead_line == "":
		lead_line = "星樱学园全明星集结，请指示下一场对局！"
	var bub_box := PanelContainer.new()
	bub_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bub_box.custom_minimum_size = Vector2(1180, 0)
	var bub_sb := style(Color(1.0, 0.97, 0.98, 0.88), 20, C_GOLD, 2, true)
	bub_sb.content_margin_left = 24
	bub_sb.content_margin_right = 24
	bub_sb.content_margin_top = 8
	bub_sb.content_margin_bottom = 8
	bub_box.add_theme_stylebox_override("panel", bub_sb)
	var bub_lbl := lbl("💬 【%s】：「%s」  （点击看板切换角色 · 长按查看详情）" % [lead_nm, lead_line], 19, C_PINK_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER)
	bub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bub_lbl.custom_minimum_size = Vector2(1120, 0)
	bub_box.add_child(bub_lbl)
	vb.add_child(bub_box)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	var b_battle := cute_button("⚔ 5人身份场", "主公 / 忠臣 / 反贼 / 内奸", C_PLATE, Vector2(384, 108))
	b_battle.pressed.connect(show_battle)
	btn_row.add_child(b_battle)
	var b_ddz := cute_button("👑 斗地主", "叫分明牌加倍 · 🪙%d 欢斗豆" % Meta.beans(), Color(0.92, 0.54, 0.18), Vector2(384, 108))
	b_ddz.pressed.connect(func() -> void: show_battle_mode("doudizhu"))
	btn_row.add_child(b_ddz)
	var b_2v2 := cute_button("🤝 欢乐 2v2", "4 人同盟排位 · 手牌互通", Color(0.84, 0.32, 0.50), Vector2(384, 108))
	b_2v2.pressed.connect(func() -> void: show_battle_mode("twovtwo"))
	btn_row.add_child(b_2v2)
	vb.add_child(btn_row)
	var btn_row2 := HBoxContainer.new()
	btn_row2.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row2.add_theme_constant_override("separation", 24)
	var b_boss := cute_button("👹 魔王挑战", "3v1 联军讨伐 8 血魔王", Color(0.54, 0.28, 0.78), Vector2(384, 108))
	b_boss.pressed.connect(func() -> void: show_battle_mode("boss"))
	btn_row2.add_child(b_boss)
	var b_duel := cute_button("⚡ 单挑对决", "1 对 1 · 先手3张 / 后手4张", Color(0.32, 0.48, 0.88), Vector2(384, 108))
	b_duel.pressed.connect(func() -> void: show_battle_mode("duel"))
	btn_row2.add_child(b_duel)
	var pz_done := Meta.puzzles_cleared_count()
	var pz_all := Puzzles.count()
	var b_pz := cute_button("🧩 残局闯关", "%d 关一回合绝杀 · 已破 %d/%d" % [pz_all, pz_done, pz_all], Color(0.82, 0.38, 0.20), Vector2(384, 108))
	b_pz.pressed.connect(show_puzzles)
	btn_row2.add_child(b_pz)
	vb.add_child(btn_row2)

	var theme_row := HBoxContainer.new()
	theme_row.alignment = BoxContainer.ALIGNMENT_CENTER
	theme_row.add_theme_constant_override("separation", 14)
	var ready_n := Meta.daily_claimable_count()
	var daily_txt := ("📋 每日委托 (%d)" % ready_n) if ready_n > 0 else "📋 每日委托"
	var b_daily := cute_button(daily_txt, "", Color(0.94, 0.42, 0.60) if ready_n > 0 else Color(0.68, 0.42, 0.80), Vector2(236, 78))
	b_daily.pressed.connect(_open_daily_overlay)
	theme_row.add_child(b_daily)
	var b_chars := cute_button("👤 图鉴百科", "", C_SKY, Vector2(212, 78))
	b_chars.pressed.connect(show_gallery)
	theme_row.add_child(b_chars)
	var b_meta := cute_button("🏆 战绩·成就", "", Color(0.88, 0.45, 0.56), Vector2(212, 78))
	b_meta.pressed.connect(show_records)
	theme_row.add_child(b_meta)
	var b_tut := cute_button("🎓 教学关", "", Color(0.92, 0.58, 0.28), Vector2(212, 78))
	b_tut.pressed.connect(show_tutorial)
	theme_row.add_child(b_tut)
	var b_help := cute_button("📖 新手说明", "", Color(0.28, 0.64, 0.50), Vector2(212, 78))
	b_help.pressed.connect(show_help)
	theme_row.add_child(b_help)
	var b_theme := cute_button("🌸 昼樱主题" if theme_night else "🌙 祭典夜", "", Color(0.92, 0.66, 0.24) if theme_night else Color(0.32, 0.28, 0.58), Vector2(212, 78))
	b_theme.pressed.connect(toggle_theme)
	theme_row.add_child(b_theme)
	vb.add_child(theme_row)

	var foot := lbl("单机版 · 六大玩法 · 全量 197/203 张牌（55种）· 角色池：第一至三弹共 %d 人 · V%s" % [Characters.LIST.size(), String(ProjectSettings.get_setting("application/config/version", ""))], 26, C_WHITE, false, HORIZONTAL_ALIGNMENT_CENTER)
	# V0.24：页脚原为浅灰字直接压在背景图上，看不清；改白字加深色描边
	foot.add_theme_color_override("font_outline_color", Color(0.30, 0.10, 0.22, 0.85))
	foot.add_theme_constant_override("outline_size", 8)
	vb.add_child(foot)


# ---------------- V0.26 新手说明 ----------------

func show_help() -> void:
	clear_screen()
	var m := page_margin()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	m.add_child(vb)
	vb.add_child(back_bar("新手说明", show_home))
	var pc := PanelContainer.new()
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.92), 26, C_GOLD, 3, true))
	vb.add_child(pc)
	var rt := RichTextLabel.new()
	rt.name = "HelpText"
	rt.bbcode_enabled = true
	rt.scroll_active = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_override("normal_font", font_reg)
	rt.add_theme_font_override("bold_font", font_bold)
	rt.add_theme_font_size_override("normal_font_size", 28)
	rt.add_theme_font_size_override("bold_font_size", 28)
	rt.add_theme_color_override("default_color", C_INK)
	rt.add_theme_constant_override("line_separation", 8)
	rt.text = HelpText.bbcode()
	pc.add_child(rt)
	# 触屏拖动滚动（RichTextLabel 自带滚轮/滚动条；手机上加一个按住拖动）
	rt.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var sb := rt.get_v_scroll_bar()
			sb.value -= (event as InputEventMouseMotion).relative.y)


# ---------------- 人物图鉴 ----------------

func show_gallery() -> void:
	clear_screen()
	var m := page_margin()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	m.add_child(vb)
	var bbar := back_bar("人物图鉴（共 %d 名角色）" % Characters.LIST.size(), show_home)
	var to_cards := Button.new()
	to_cards.text = "🃏 切换至卡牌图鉴（55种）"
	to_cards.custom_minimum_size = Vector2(340, 68)
	to_cards.focus_mode = Control.FOCUS_NONE
	to_cards.add_theme_font_override("font", font_bold)
	to_cards.add_theme_font_size_override("font_size", 26)
	_style_btn(to_cards, C_PLATE, C_GOLD, C_WHITE, 20, 2, true, Vector2i(18, 10))
	to_cards.pressed.connect(show_card_gallery)
	bbar.add_child(to_cards)
	vb.add_child(bbar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 26)
	scroll.add_child(inner)

	for w in Characters.WORKS:
		var head := PanelContainer.new()
		head.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.82), 22, C_GOLD, 2, true))
		var hv := VBoxContainer.new()
		hv.add_child(lbl("系列 · %s" % w["work"], 40, C_PINK_DEEP, true))
		hv.add_child(lbl(w["note"], 26, C_INK_SOFT))
		head.add_child(hv)
		inner.add_child(head)

		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 22)
		inner.add_child(grid)
		for c in Characters.by_work(w["work"]):
			grid.add_child(make_char_card(c, scroll))

	var soon := PanelContainer.new()
	soon.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.55), 22, Color(0.91, 0.64, 0.24, 0.6), 2))
	var sl := lbl("更多系列的角色包制作中，敬请期待", 28, C_INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER)
	soon.add_child(sl)
	inner.add_child(soon)


func _wire_scroll_drag(ctrl: BaseButton, scroll: ScrollContainer) -> void:
	ctrl.set_meta("drag_px", 0.0)
	ctrl.button_down.connect(func() -> void: ctrl.set_meta("drag_px", 0.0))
	if scroll == null:
		return
	var sc: ScrollContainer = scroll
	ctrl.gui_input.connect(func(event: InputEvent) -> void:
		var dy := 0.0
		if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			ctrl.set_meta("drag_px", 0.0)
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			ctrl.set_meta("drag_px", 0.0)
		elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			dy = (event as InputEventMouseMotion).relative.y
		elif event is InputEventScreenDrag:
			dy = (event as InputEventScreenDrag).relative.y
		if dy != 0.0:
			if is_instance_valid(sc):
				sc.scroll_vertical -= int(roundf(dy))
			ctrl.set_meta("drag_px", float(ctrl.get_meta("drag_px", 0.0)) + absf(dy)))


func make_char_card(c: Dictionary, scroll: ScrollContainer = null) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(400, 500)
	_style_btn(b, Color(1, 1, 1, 0.90), C_GOLD, C_INK, 26, 3, true, Vector2i(-1, -1), false, C_PINK)
	var vb := VBoxContainer.new()
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 4)
	var cc := Art.cg_card(c, Vector2(372, 420), {"zoom": 0.80, "face_y": 0.30, "fs": 34})
	var ccw := CenterContainer.new()
	ccw.mouse_filter = MOUSE_FILTER_IGNORE
	ccw.custom_minimum_size = Vector2(380, 432)
	ccw.add_child(cc)
	vb.add_child(ccw)
	var sk_names: Array = []
	for skd in c["skills"]:
		sk_names.append("【%s】" % String(skd["name"]))
	var cid_m := String(c["id"])
	var banned_m := Meta.is_char_banned(cid_m)
	var cst := Meta.char_stats_by_name(String(c["name"]))
	var cg_n := int(cst.get("games", 0))
	var cw_n := int(cst.get("wins", 0))
	var blv_m := Meta.bond_level(cid_m)
	var bond_tag := (" · 💍誓约" if blv_m >= 5 else (" · ♥Lv%d" % blv_m if Meta.affection(cid_m) > 0 else ""))
	var stat_suf := " · 🚫已禁用" if banned_m else (bond_tag + (" · %d胜" % cw_n if cw_n > 0 else ""))
	var sk_mg := MarginContainer.new()
	sk_mg.mouse_filter = MOUSE_FILTER_IGNORE
	sk_mg.add_theme_constant_override("margin_left", 14)
	sk_mg.add_theme_constant_override("margin_right", 14)
	var skl := lbl(" ".join(PackedStringArray(sk_names)) + stat_suf, 20, C_PINK_DEEP if banned_m else C_INK_SOFT, banned_m, HORIZONTAL_ALIGNMENT_CENTER)
	skl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skl.custom_minimum_size = Vector2(368, 0)
	skl.mouse_filter = MOUSE_FILTER_IGNORE
	sk_mg.add_child(skl)
	vb.add_child(sk_mg)
	if banned_m:
		b.modulate = Color(0.84, 0.80, 0.86, 0.90)
	b.add_child(vb)
	b.set_meta("intro", IntroPop.char_spec(c))
	_wire_scroll_drag(b, scroll)
	b.pressed.connect(func() -> void:
		if float(b.get_meta("drag_px", 0.0)) > 18.0:
			b.set_meta("drag_px", 0.0)
			return
		show_detail(c))
	return b


# ---------------- 角色详情 ----------------

func show_detail(c: Dictionary) -> void:
	clear_screen()
	var m := page_margin()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	m.add_child(vb)
	vb.add_child(back_bar("人物图鉴", show_gallery, "← 返回图鉴"))

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 36)
	vb.add_child(row)

	var cid_touch := String(c["id"])
	var is_vow_c := Meta.is_vowed(cid_touch)
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_stylebox_override("panel", style(Color(1, 0.95, 0.98, 0.90) if is_vow_c else Color(1, 1, 1, 0.75), 28, C_PINK_DEEP if is_vow_c else C_GOLD, 4 if is_vow_c else 3, true))
	var lcc := CenterContainer.new()
	var cg_wrap := Art.cg_card(c, Vector2(520, 693), {"fs": 44})
	var cg_inner := cg_wrap.get_node_or_null("Clip") as Control
	if cg_inner != null:
		_attach_l2d_breath(cg_inner, 0.0, 0.015, 2.5)
	lcc.add_child(cg_wrap)
	left.add_child(lcc)
	row.add_child(left)

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.92), 28, C_GOLD, 3, true))
	var r_sc := ScrollContainer.new()
	r_sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(r_sc)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 12)
	r_sc.add_child(rv)
	var nm_d := lbl(c["name"], 52, C_PINK_DEEP, true)
	nm_d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(nm_d)
	var wk_d := lbl("%s · 系列：%s" % [String(c.get("title", "")), String(c["work"])], 24, C_INK_SOFT)
	wk_d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(wk_d)
	var hp_text := ""
	for i in int(c["hp"]):
		hp_text += "♥"
	var hp_d := lbl("体力：%s（%d 点）" % [hp_text, int(c["hp"])], 25, C_INK, true)
	hp_d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(hp_d)
	var intro := lbl(c["intro"], 24, C_INK)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(intro)
	var sep := HSeparator.new()
	rv.add_child(sep)
	for sk in c["skills"]:
		var sk_t := lbl("技能 · %s" % sk["name"], 29, C_PINK_DEEP, true)
		sk_t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rv.add_child(sk_t)
		var st := lbl(sk["text"], 23, C_INK)
		st.add_theme_constant_override("line_spacing", 4)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rv.add_child(st)
	var sep2 := HSeparator.new()
	rv.add_child(sep2)
	var cid_d := String(c["id"])
	var cstat := Meta.char_stats_by_name(String(c["name"]))
	var cg := int(cstat.get("games", 0))
	var cw := int(cstat.get("wins", 0))
	var cxp := int(cstat.get("xp", 0))
	var lv_d := Meta.level_of(cxp)
	var rate_s := (" · 胜率 %.0f%%" % (100.0 * float(cw) / float(cg))) if cg > 0 else ""
	var stat_card := PanelContainer.new()
	var sc_sb := style(Color(0.99, 0.95, 0.97), 18, Color(0.91, 0.64, 0.24, 0.55), 2)
	sc_sb.content_margin_left = 18
	sc_sb.content_margin_right = 18
	sc_sb.content_margin_top = 10
	sc_sb.content_margin_bottom = 10
	stat_card.add_theme_stylebox_override("panel", sc_sb)
	var sc_vb := VBoxContainer.new()
	sc_vb.add_theme_constant_override("separation", 6)
	stat_card.add_child(sc_vb)
	var stat_lbl := lbl("⚔ 熟练度 Lv.%d · 战绩 %d 胜 / %d 局%s   |   🪙 欢斗豆：%d" % [lv_d, cw, cg, rate_s, Meta.beans()], 22, C_INK, true)
	stat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sc_vb.add_child(stat_lbl)
	var bond_row := HBoxContainer.new()
	bond_row.add_theme_constant_override("separation", 12)
	var bond_lbl := lbl("💕 羁绊：%s" % Meta.bond_title(cid_d), 22, C_PINK_DEEP, true)
	bond_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	bond_row.add_child(bond_lbl)
	var bond_bar := ProgressBar.new()
	bond_bar.show_percentage = false
	bond_bar.custom_minimum_size = Vector2(260, 16)
	bond_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bond_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bond_bar.max_value = 500.0
	bond_bar.value = float(clampi(Meta.affection(cid_d), 0, 500))
	bond_bar.add_theme_stylebox_override("background", style(Color(0.94, 0.86, 0.90), 8))
	bond_bar.add_theme_stylebox_override("fill", style(C_PINK_DEEP, 8))
	bond_row.add_child(bond_bar)
	sc_vb.add_child(bond_row)
	rv.add_child(stat_card)
	var act_hb := HBoxContainer.new()
	act_hb.add_theme_constant_override("separation", 12)
	rv.add_child(act_hb)
	var sc_list := Meta.get_showcase(Characters.LIST)
	var is_pin := (not sc_list.is_empty() and String(sc_list[0]) == cid_d)
	var mk_det_btn := func(txt: String, bg: Color, w_min: float = 216.0) -> Button:
		var b := Button.new()
		b.text = txt
		b.custom_minimum_size = Vector2(w_min, 56)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", font_bold)
		b.add_theme_font_size_override("font_size", 22)
		_style_btn(b, bg, C_GOLD, C_WHITE, 16, 2, true, Vector2i(14, 8))
		return b
	var pin_b: Button = mk_det_btn.call("★ 当前看板" if is_pin else "☆ 设为看板", C_GOLD if is_pin else C_PLATE, 196.0)
	pin_b.pressed.connect(func() -> void:
		AudioCfg.play_ui(self, "click")
		home_showcase_ids = Meta.pin_showcase_char(cid_d)
		show_detail(c))
	act_hb.add_child(pin_b)
	var is_ban := Meta.is_char_banned(cid_d)
	var ban_b: Button = mk_det_btn.call("✓ 已禁用(恢复)" if is_ban else "🚫 禁用点将", Color(0.55, 0.36, 0.42) if is_ban else Color(0.45, 0.45, 0.56), 196.0)
	var ban_msg := lbl("", 21, C_PINK_DEEP, true)
	ban_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ban_b.pressed.connect(func() -> void:
		AudioCfg.play_ui(self, "click")
		if Meta.toggle_ban_char(cid_d, Characters.LIST.size()):
			show_detail(c)
		else:
			ban_msg.text = "至少需保留 8 名启用武将，无法继续禁用！")
	act_hb.add_child(ban_b)
	var v_cats := ["touch", "skill", "attack", "hurt", "dying", "vow"]
	var v_names := ["摸头互动", "必杀语音", "出击语音", "受创语音", "绝境语音", "💍誓约告白"]
	var v_idx := [0]
	var v_lbl := lbl("🎙 点击左侧立绘触摸部位（头/脸/心口）或点按钮试听：「%s」" % BattleScreen.line_for(cid_d, "head"), 22, C_PINK_DEEP, true)
	v_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var voice_b: Button = mk_det_btn.call("🎙 语音鉴赏", Color(0.62, 0.36, 0.78), 186.0)
	voice_b.pressed.connect(func() -> void:
		v_idx[0] = (int(v_idx[0]) + 1) % v_cats.size()
		var cat_k := String(v_cats[int(v_idx[0])])
		var cat_n := String(v_names[int(v_idx[0])])
		if cat_k == "vow" and not Meta.is_vowed(cid_d):
			AudioCfg.play_ui(self, "click")
			v_lbl.text = "🔒 💍誓约告白需好感度达到 Lv.5（500♥）解锁！当前：%s" % Meta.bond_title(cid_d)
			return
		if not AudioCfg.play_cv(self, cid_d, cat_k):
			AudioCfg.play_ui(self, "skill")
		v_lbl.text = "🎙 %s：「%s」" % [cat_n, BattleScreen.line_for(cid_d, "head" if cat_k == "touch" else cat_k)])
	act_hb.add_child(voice_b)
	var gift_b: Button = mk_det_btn.call("🎁 赠礼(100🪙+35♥)", Color(0.92, 0.42, 0.58), 236.0)
	gift_b.pressed.connect(func() -> void:
		var gr := Meta.gift_char(cid_d, 100, 35)
		if not bool(gr.get("ok", false)):
			AudioCfg.play_ui(self, "click")
			ban_msg.text = String(gr.get("msg", "欢斗豆不足"))
			return
		if not AudioCfg.play_cv(self, cid_d, "touch"):
			AudioCfg.play_ui(self, "heal")
		stat_lbl.text = "⚔ 熟练度 Lv.%d · 战绩 %d 胜 / %d 局%s   |   🪙 欢斗豆：%d" % [lv_d, cw, cg, rate_s, Meta.beans()]
		bond_lbl.text = "💕 羁绊：%s" % Meta.bond_title(cid_d)
		bond_bar.value = float(clampi(Meta.affection(cid_d), 0, 500))
		var g_line := BattleScreen.line_for(cid_d, "vow" if bool(gr.get("vowed", false)) else "head")
		v_lbl.text = ("💍 【达成永恒誓约！】「%s」" % g_line) if bool(gr.get("vowed", false)) else ("🎁 【收到礼物 · 好感+35♥】「%s」" % g_line)
		_bounce_control(cg_wrap)
		_spawn_touch_burst(left, left.size * 0.45, ["💍", "💖", "🌸"] if bool(gr.get("vowed", false)) else ["🎁", "💖", "✨"], "+35♥"))
	act_hb.add_child(gift_b)
	left.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := ev as InputEventMouseButton
			var ry := clampf(mb.position.y / maxf(left.size.y, 1.0), 0.0, 1.0)
			var zone_cat := "head" if ry < 0.30 else ("face" if ry < 0.52 else ("body" if ry < 0.76 else "attack"))
			var zone_nm := "🌸摸头杀(+2♥)" if zone_cat == "head" else ("💕轻触脸颊(+2♥)" if zone_cat == "face" else ("💓心口互动(+2♥)" if zone_cat == "body" else "✨并肩互动(+2♥)"))
			var cv_cat := "touch" if (zone_cat == "head" or zone_cat == "face") else ("hurt" if zone_cat == "body" else "attack")
			Meta.touch_char(cid_d, 2)
			if not AudioCfg.play_cv(self, cid_d, cv_cat):
				AudioCfg.play_ui(self, "heal")
			_bounce_control(cg_wrap)
			_spawn_touch_burst(left, mb.position, ["💕", "🌸", "✨"], "+2♥")
			stat_lbl.text = "⚔ 熟练度 Lv.%d · 战绩 %d 胜 / %d 局%s   |   🪙 欢斗豆：%d" % [lv_d, cw, cg, rate_s, Meta.beans()]
			bond_lbl.text = "💕 羁绊：%s" % Meta.bond_title(cid_d)
			bond_bar.value = float(clampi(Meta.affection(cid_d), 0, 500))
			v_lbl.text = "%s：「%s」" % [zone_nm, BattleScreen.line_for(cid_d, zone_cat)])
	rv.add_child(v_lbl)
	rv.add_child(ban_msg)
	row.add_child(right)


# ---------------- 对战（V0.2 起接入 BattleScreen） ----------------

func show_battle() -> void:
	if music != null:
		music.play_scene("battle")
	clear_screen()
	var bs := BattleScreen.new()
	bs.set_anchors_preset(Control.PRESET_FULL_RECT)
	bs.go_home = Callable(self, "show_home")
	screen_root.add_child(bs)
	bs.show_setup()


func show_battle_mode(m: String) -> void:
	if music != null:
		music.play_scene("battle")
	clear_screen()
	var bs := BattleScreen.new()
	bs.game_mode = m
	bs.set_anchors_preset(Control.PRESET_FULL_RECT)
	bs.go_home = Callable(self, "show_home")
	screen_root.add_child(bs)
	bs.show_setup()


func start_puzzle(pid: String) -> void:
	if music != null:
		music.play_scene("battle")
	clear_screen()
	var bs := BattleScreen.new()
	bs.game_mode = "puzzle"
	bs.puzzle_id = pid
	bs.set_anchors_preset(Control.PRESET_FULL_RECT)
	bs.go_home = Callable(self, "show_home")
	bs.open_puzzles_cb = Callable(self, "show_puzzles")
	screen_root.add_child(bs)
	bs.start_match(false)


func show_puzzles() -> void:
	clear_screen()
	var m := page_margin()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	m.add_child(vb)
	var done_n := Meta.puzzles_cleared_count()
	var total_n := Puzzles.count()
	var bbar := back_bar("残局闯关（一回合绝杀 · 已通关 %d / %d）" % [done_n, total_n], show_home)
	vb.add_child(bbar)
	var sub := Art.halo(lbl("每关为固定手牌与残局阵容，须在【你的本回合内】击破全部守关者；长按手牌或敌人可随时查看详情。", 25, C_INK, false, HORIZONTAL_ALIGNMENT_CENTER), 6)
	vb.add_child(sub)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var ch_vb := VBoxContainer.new()
	ch_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch_vb.add_theme_constant_override("separation", 18)
	sc.add_child(ch_vb)
	var make_pz_card := func(i: int, grid_tgt: GridContainer) -> void:
		var ps: Dictionary = Puzzles.LIST[i]
		var pid := String(ps["id"])
		var cleared := Meta.puzzle_cleared(pid)
		var stars := int(ps.get("stars", 1))
		var star_s := "★".repeat(stars) + "☆".repeat(maxi(0, 4 - stars))
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", style(Color(0.94, 1.0, 0.95, 0.95) if cleared else Color(1, 0.99, 1, 0.94), 20, Color(0.28, 0.72, 0.42) if cleared else C_GOLD, 3, true))
		var mg := MarginContainer.new()
		mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			mg.add_theme_constant_override("margin_" + side, 16)
		card.add_child(mg)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 16)
		mg.add_child(row)
		var ch0 := Characters.by_id(String((ps["me"] as Dictionary).get("char", "hina")))
		if not ch0.is_empty():
			var port := Art.cg_card(ch0, Vector2(126, 164), {"zoom": 0.56, "face_y": 0.34, "title": false, "hp": false, "fs": 16})
			port.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(port)
		var info := VBoxContainer.new()
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 6)
		row.add_child(info)
		var hd := HBoxContainer.new()
		hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hd.add_theme_constant_override("separation", 10)
		var p_ttl := lbl("第 %d 关 · %s" % [i + 1, String(ps["name"])], 26, C_INK, true)
		p_ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p_ttl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p_ttl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hd.add_child(p_ttl)
		var p_st := lbl(star_s, 20, C_GOLD, true)
		p_st.autowrap_mode = TextServer.AUTOWRAP_OFF
		p_st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hd.add_child(p_st)
		var p_ok := lbl("✓ 已破关" if cleared else "待挑战", 20, Color(0.18, 0.62, 0.32) if cleared else C_PINK_DEEP, true)
		p_ok.autowrap_mode = TextServer.AUTOWRAP_OFF
		p_ok.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hd.add_child(p_ok)
		info.add_child(hd)
		var br_lbl := lbl(String(ps["brief"]), 21, C_INK_SOFT)
		br_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		br_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(br_lbl)
		var gl_lbl := lbl("目标：" + String(ps["goal"]), 20, C_INK, true)
		gl_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gl_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(gl_lbl)
		var go_b := Button.new()
		go_b.text = "重玩此关" if cleared else "挑战本关"
		go_b.custom_minimum_size = Vector2(150, 56)
		go_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go_b.focus_mode = Control.FOCUS_NONE
		go_b.add_theme_font_override("font", font_bold)
		go_b.add_theme_font_size_override("font_size", 23)
		_style_btn(go_b, Color(0.32, 0.68, 0.44) if cleared else C_PLATE, C_GOLD, C_WHITE, 16, 2, true, Vector2i(14, 8), false)
		_wire_scroll_drag(go_b, sc)
		go_b.pressed.connect(func() -> void:
			if float(go_b.get_meta("drag_px", 0.0)) > 18.0:
				go_b.set_meta("drag_px", 0.0)
				return
			start_puzzle(pid))
		row.add_child(go_b)
		grid_tgt.add_child(card)
	for ch_no in [1, 2]:
		var indices: Array = []
		var ch_done := 0
		for i in total_n:
			var pid0 := String((Puzzles.LIST[i] as Dictionary)["id"])
			if Puzzles.chapter_of(pid0) == ch_no:
				indices.append(i)
				if Meta.puzzle_cleared(pid0):
					ch_done += 1
		if indices.is_empty():
			continue
		var ch_head := PanelContainer.new()
		ch_head.add_theme_stylebox_override("panel", style(Color(0.95, 0.97, 1.0, 0.90) if ch_no == 2 else Color(1, 1, 1, 0.85), 18, Color(0.45, 0.68, 0.95) if ch_no == 2 else C_GOLD, 2, true))
		var ch_txt := ("❄ 第二章 · 新锐名局（改判/影羽/观星/水淹/霜封 · %d/%d）" % [ch_done, indices.size()]) if ch_no == 2 else ("🌸 第一章 · 樱社入门（经典破防与绝杀 · %d/%d）" % [ch_done, indices.size()])
		ch_head.add_child(lbl(ch_txt, 26, Color(0.18, 0.38, 0.68) if ch_no == 2 else C_PINK_DEEP, true))
		ch_vb.add_child(ch_head)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 20)
		grid.add_theme_constant_override("v_separation", 18)
		ch_vb.add_child(grid)
		for i_p in indices:
			make_pz_card.call(int(i_p), grid)


func show_tutorial() -> void:
	if music != null:
		music.play_scene("battle")
	clear_screen()
	var bs := BattleScreen.new()
	bs.tutorial = true
	bs.game_mode = "duel"
	bs.set_anchors_preset(Control.PRESET_FULL_RECT)
	bs.go_home = Callable(self, "show_home")
	screen_root.add_child(bs)
	bs.start_match(false)


# ---------------- V0.30 战绩 · 熟练度 · 成就 ----------------

func _meta_panel(parent: Control, title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	parent.add_child(pc)
	pc.add_theme_stylebox_override("panel", style(Color(1.0, 0.97, 0.94, 0.94), 22, C_GOLD, 2, true))
	var mg := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + side, 18)
	pc.add_child(mg)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	mg.add_child(vb)
	vb.add_child(lbl(title, 32, C_PINK_DEEP, true))
	return vb


func show_records() -> void:
	clear_screen()
	var d := Meta.load_data()
	var m := page_margin()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	m.add_child(root)
	root.add_child(back_bar("战绩 · 熟练度 · 成就", show_home))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.15
	cols.add_child(right)
	# 战绩汇总（按模式 / 按身份胜率）
	var sv := _meta_panel(left, "战绩")
	var sum_lbl := lbl("总计：%s　｜　🔥连胜 %d（最高 %d）　｜　残局：%d/%d　｜　🪙%d豆" % [Meta.win_rate_text("all"), int(d.get("win_streak", 0)), int(d.get("best_streak", 0)), Meta.puzzles_cleared_count(), Puzzles.count(), Meta.beans()], 22, C_INK, true)
	sum_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(sum_lbl)
	var tops: Array = Meta.top_chars(3)
	if not tops.is_empty():
		var tv := _meta_panel(left, "🏆 本命武将榜 Top%d" % tops.size())
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 14)
		tv.add_child(trow)
		for idx_t in tops.size():
			var td: Dictionary = tops[idx_t]
			var tc_box := VBoxContainer.new()
			tc_box.add_theme_constant_override("separation", 4)
			var tch: Dictionary = {}
			for cand_c in Characters.LIST:
				if String(cand_c["name"]) == String(td["name"]):
					tch = cand_c
					break
			if not tch.is_empty():
				tc_box.add_child(Art.cg_card(tch, Vector2(146, 178), {"zoom": 0.56, "face_y": 0.34, "title": false, "hp": false, "fs": 16}))
			var wr := int(round(100.0 * float(td["wins"]) / float(maxi(int(td["games"]), 1))))
			tc_box.add_child(lbl("#%d %s" % [idx_t + 1, String(td["name"])], 21, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER))
			tc_box.add_child(lbl("胜 %d/%d (%d%%)" % [int(td["wins"]), int(td["games"]), wr], 18, C_PINK_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER))
			trow.add_child(tc_box)
	for mk in [["identity", "身份场", ["主公", "忠臣", "反贼", "内奸"]], ["doudizhu", "斗地主", ["地主", "农民"]], ["twovtwo", "欢乐2v2", ["红方", "蓝方"]], ["boss", "魔王挑战", ["联军", "魔王"]], ["duel", "单挑", ["先手", "后手"]]]:
		sv.add_child(lbl("%s：%s" % [mk[1], Meta.win_rate_text("mode|" + String(mk[0]))], 24, C_INK, true))
		var parts: Array = []
		for idn in mk[2]:
			parts.append("%s %s" % [idn, Meta.win_rate_text("id|%s|%s" % [mk[0], idn])])
		var pl := lbl("　" + "　｜　".join(PackedStringArray(parts)), 20, C_INK_SOFT)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sv.add_child(pl)
	# 角色熟练度
	var mv := _meta_panel(left, "角色熟练度")
	for c in Characters.LIST:
		var cn := String(c["name"])
		var cs: Dictionary = (d["chars"] as Dictionary).get(cn, {"games": 0, "wins": 0, "xp": 0})
		var xp := int(cs["xp"])
		var lv := Meta.level_of(xp)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var nl := lbl("%s　Lv%d %s" % [cn, lv, Meta.MASTERY_TITLE[lv - 1]], 22, C_INK, true)
		nl.custom_minimum_size = Vector2(300, 0)
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(nl)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(220, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nx := Meta.next_xp(xp)
		var lo := int(Meta.MASTERY_XP[lv - 1])
		bar.max_value = 1.0
		bar.value = 1.0 if nx < 0 else float(xp - lo) / float(maxi(nx - lo, 1))
		bar.add_theme_stylebox_override("background", style(Color(0.95, 0.88, 0.90), 9))
		bar.add_theme_stylebox_override("fill", style(Art.BLOSSOM, 9))
		row.add_child(bar)
		var xl := lbl("%d 局 胜 %d · %d XP" % [int(cs["games"]), int(cs["wins"]), xp], 19, C_INK_SOFT)
		xl.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(xl)
		mv.add_child(row)
	# 成就
	var av := _meta_panel(right, "成就（%d / %d）" % [(d["ach"] as Dictionary).size(), Meta.ACHIEVEMENTS.size()])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	av.add_child(grid)
	for a in Meta.ACHIEVEMENTS:
		var got := (d["ach"] as Dictionary).has(String(a[0]))
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size = Vector2(360, 0)
		var ach_sb := style(Color(1.0, 0.93, 0.96) if got else Color(0.93, 0.92, 0.94), 14, C_GOLD if got else Color(0.8, 0.78, 0.82), 2)
		ach_sb.content_margin_left = 14
		ach_sb.content_margin_right = 14
		ach_sb.content_margin_top = 10
		ach_sb.content_margin_bottom = 10
		cell.add_theme_stylebox_override("panel", ach_sb)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		cell.add_child(cv)
		var ach_t := lbl(("★ " if got else "☆ ") + String(a[1]), 21, C_PINK_DEEP if got else Color(0.55, 0.52, 0.58), true)
		ach_t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(ach_t)
		var ach_d := lbl(String(a[2]), 18, C_INK_SOFT)
		ach_d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(ach_d)
		grid.add_child(cell)
	# 最近战绩
	var rv := _meta_panel(right, "最近对局")
	var recs: Array = d["records"]
	if recs.is_empty():
		rv.add_child(lbl("还没有对局记录，去打一局吧！", 22, C_INK_SOFT))
	var mode_cn := {"identity": "身份场", "doudizhu": "斗地主", "twovtwo": "欢乐2v2", "boss": "魔王挑战", "duel": "单挑"}
	var res_cn := {"win": "胜", "lose": "负", "draw": "平"}
	for i in mini(recs.size(), 12):
		var r: Dictionary = recs[i]
		var tt := Time.get_datetime_string_from_unix_time(int(r.get("t", 0)) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60, true).substr(5, 11)
		var line := "%s　%s　%s·%s　%s　输出 %d 击杀 %d%s" % [tt, String(mode_cn.get(String(r.get("mode", "")), "")), String(r.get("char", "")), String(r.get("identity", "")), String(res_cn.get(String(r.get("result", "")), "")), int(r.get("dmg", 0)), int(r.get("kills", 0)), "　★MVP" if bool(r.get("mvp", false)) else ""]
		var rl := lbl(line, 20, C_INK if String(r.get("result", "")) == "win" else C_INK_SOFT)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rv.add_child(rl)


func start_simulation() -> void:
	clear_screen()
	var bs := BattleScreen.new()
	bs.set_anchors_preset(Control.PRESET_FULL_RECT)
	bs.go_home = Callable(self, "show_home")
	screen_root.add_child(bs)
	bs.start_match(true)


# 仅供开发自测：自动点选走完真人交互流程（选将/提问/结束出牌）
func _run_ui_test() -> void:
	clear_screen()
	ui_bs = BattleScreen.new()
	ui_bs.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_bs.go_home = Callable(self, "show_home")
	screen_root.add_child(ui_bs)
	ui_bs.start_match(false)
	ui_bs.fast = true  # 测试驱动走快速节奏，只验逻辑不验演出时长
	_ui_test_loop()


func _ui_test_loop() -> void:
	var ticks := 0
	while ticks < 400:
		await get_tree().create_timer(0.25).timeout
		ticks += 1
		if ui_bs == null or not is_instance_valid(ui_bs):
			break
		if ui_bs.game_over:
			break
		var pressed := false
		if ui_bs.targeting and ui_bs.action_bar.visible and not ui_bs.confirm_btn.disabled:
			ui_bs.confirm_btn.pressed.emit()  # V0.27：选好目标后点「确定」
			pressed = true
		elif ui_bs.targeting and not ui_bs.target_candidates.is_empty():
			for panel in ui_bs.seat_panels:
				if int(panel.get_meta("seat")) == int(ui_bs.target_candidates[0]) and ui_bs.sel_target != int(ui_bs.target_candidates[0]):
					(panel as Button).pressed.emit()
					pressed = true
					break
		if not pressed and ui_bs.draft_layer != null and ui_bs.draft_layer.visible:
			for b in ui_bs.draft_layer.get_children():
				if b is Button:
					(b as Button).pressed.emit()
					pressed = true
					break
		if not pressed and ui_bs.prompt_btns != null:
			for b in ui_bs.prompt_btns.get_children():
				if b is Button and not (b as Button).disabled:
					(b as Button).pressed.emit()
					pressed = true
					break
		if not pressed and ui_bs.interactive:
			ui_bs.end_play_pressed.emit()
	var f := FileAccess.open("/tmp/ask_uitest.txt", FileAccess.WRITE)
	var state := "no_bs"
	if ui_bs != null and is_instance_valid(ui_bs):
		state = "game_over=%s rounds=%d alive=%d turn_seat=%d" % [str(ui_bs.game_over), ui_bs.round_no, ui_bs.alive_players().size(), ui_bs.turn_seat]
	f.store_string(state)
	f.close()
	get_tree().quit()


# 仅供开发自测：真实渲染长跑压测（多局连打，监控节点/内存增长与闪退）
func _run_soak() -> void:
	Engine.time_scale = 3.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--soakts="):
			Engine.time_scale = float(a.trim_prefix("--soakts="))
	var games := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--soak="):
			games = maxi(1, int(a.trim_prefix("--soak=")))
	var lines: Array = []
	for g in games:
		clear_screen()
		ui_bs = BattleScreen.new()
		ui_bs.set_anchors_preset(Control.PRESET_FULL_RECT)
		ui_bs.go_home = Callable(self, "show_home")
		screen_root.add_child(ui_bs)
		ui_bs.start_match(false)
		var ticks := 0
		while ticks < 2600:
			await get_tree().create_timer(0.25).timeout
			ticks += 1
			if ticks % 200 == 0 and is_instance_valid(ui_bs):
				printerr("SOAKSTATE g=%d tick=%d over=%s draft=%s prompt=%s inter=%s turn=%d rounds=%d" % [g + 1, ticks, str(ui_bs.game_over), str(ui_bs.draft_layer.visible) if ui_bs.draft_layer else "?", str(ui_bs.prompt_panel.visible) if ui_bs.prompt_panel else "?", str(ui_bs.interactive), ui_bs.turn_seat, ui_bs.round_no])
			if ui_bs == null or not is_instance_valid(ui_bs) or ui_bs.game_over:
				break
			var pressed := false
			if ui_bs.targeting and ui_bs.action_bar.visible and not ui_bs.confirm_btn.disabled:
				ui_bs.confirm_btn.pressed.emit()  # V0.27：选好目标后点「确定」
				pressed = true
			elif ui_bs.targeting and not ui_bs.target_candidates.is_empty():
				for panel in ui_bs.seat_panels:
					if int(panel.get_meta("seat")) == int(ui_bs.target_candidates[0]) and ui_bs.sel_target != int(ui_bs.target_candidates[0]):
						(panel as Button).pressed.emit()
						pressed = true
						break
			if not pressed and ui_bs.draft_layer != null and ui_bs.draft_layer.visible:
				for b in ui_bs.draft_layer.get_children():
					if b is Button:
						(b as Button).pressed.emit()
						pressed = true
						break
			if not pressed and ui_bs.prompt_btns != null:
				for b in ui_bs.prompt_btns.get_children():
					if b is Button and not (b as Button).disabled:
						(b as Button).pressed.emit()
						pressed = true
						break
			if not pressed and ui_bs.interactive:
				ui_bs.end_play_pressed.emit()
		var rss_mb := 0.0
		var statm := FileAccess.get_file_as_string("/proc/self/statm").split(" ")
		if statm.size() > 1:
			rss_mb = float(statm[1]) * 4096.0 / 1048576.0
		var stat := "game %d over=%s rounds=%d ticks=%d nodes=%d objects=%d res=%d static_mb=%.1f rss_mb=%.1f" % [g + 1, str(ui_bs.game_over) if is_instance_valid(ui_bs) else "?", ui_bs.round_no if is_instance_valid(ui_bs) else -1, ticks, get_tree().get_node_count(), int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)), OS.get_static_memory_usage() / 1048576.0, rss_mb]
		lines.append(stat)
		printerr("SOAK ", stat)
		await get_tree().create_timer(0.5).timeout
	var f := FileAccess.open("/tmp/ask_soak.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()


# 仅供开发自测：新引擎（engine.gd）全 AI 跑局验证
func _run_mode_test(m: String) -> void:
	var Engine = preload("res://scripts/engine.gd")
	var lines: Array = []
	var pool: Array = Characters.by_work("星樱坂学园").duplicate()
	for g in 3:
		var eng = Engine.new()
		eng.load_skills()
		eng.mode = m
		pool.shuffle()
		var ids: Array = []
		var n := 5
		if m == "doudizhu":
			n = 3
			ids = ["地主", "农民", "农民"]
			ids.shuffle()
		elif m == "duel":
			n = 2
			ids = ["先手", "后手"]
			eng.duel_first_seat = 0
		else:
			ids = ["主公", "忠臣", "反贼", "反贼", "内奸"]
		var chars: Array = []
		for i in n:
			var cd: Dictionary = pool[i]
			var sk: Array = []
			for s in cd["skills"]:
				sk.append(String((s as Dictionary)["sid"]))
			chars.append({"name": String(cd["name"]), "hp": int(cd["hp"]), "skills": sk})
		eng.setup_game(chars, ids)
		await eng.run_game()
		var extra := ""
		if m == "doudizhu":
			extra = " mult=%d lord_seat=%d" % [int(eng.ddz_multiplier), int(eng.ddz_landlord_seat)]
		lines.append("game%d over=%s winner=%s rounds=%d logs=%d%s" % [g + 1, str(eng.game_over), eng.winner_text, eng.round_no, eng.log_lines.size(), extra])
		if OS.get_cmdline_user_args().has("--logdump"):
			var lf := FileAccess.open("/tmp/ask_mode_log.txt", FileAccess.WRITE)
			lf.store_string("LINES=" + str(eng.log_lines.size()) + "\n" + "\n".join(eng.log_lines))
			lf.close()
	var f := FileAccess.open("/tmp/ask_mode_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()


# 仅供开发自测：应变＋冰突击确定性断言（V0.18：冰突击/简单条件/目标+/伤害+/强命/富甲评估/牌堆构成；V0.19：助战·目标+ 突击/逐近弃远/水淹七军＋水淹单目标）
func _run_yb_test() -> void:
	var Engine = preload("res://scripts/engine.gd")
	var lines: Array = []
	var pool: Array = Characters.by_work("星樱坂学园").duplicate()
	var chars: Array = []
	for i in 5:
		var cd: Dictionary = pool[i]
		var sk: Array = []
		for s in cd["skills"]:
			sk.append(String((s as Dictionary)["sid"]))
		chars.append({"name": String(cd["name"]), "hp": 4, "skills": sk})
	var ids := ["反贼", "主公", "忠臣", "反贼", "忠臣"]
	var eng = Engine.new()
	eng.load_skills()
	var res := {"fail": 0}
	var check := func(label: String, ok: bool, detail: String = "") -> void:
		if not ok:
			res["fail"] = int(res["fail"]) + 1
		lines.append("%s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	# 牌堆构成（对照 yingbian 原表：冰突击 5、词条突击 9、全堆 190；用未发牌的独立实例数原始牌堆）
	var eng0 = Engine.new()
	eng0.build_deck()
	var ice_n := 0
	var yb_n := 0
	var zz_n := 0
	for c in eng0.deck:
		if String(c["name"]) == "突击" and String(c.get("nature", "")) == "冰":
			ice_n += 1
		if not (c.get("yb", []) as Array).is_empty():
			yb_n += 1
		if (c.get("yb", []) as Array).has("助战"):
			zz_n += 1
	check.call("deck_total_197", eng0.deck.size() == 197, "size=%d" % eng0.deck.size())
	check.call("deck_ice_sha_5", ice_n == 5, "ice=%d" % ice_n)
	check.call("deck_yb_total_27", yb_n == 27, "yb=%d" % yb_n)
	check.call("deck_yb_zhuzhan_4", zz_n == 4, "zz=%d" % zz_n)
	eng.setup_game(chars, ids)
	var A: Dictionary = eng.players[0]
	var B: Dictionary = eng.players[1]
	var E: Dictionary = eng.players[4]
	var reset := func(p: Dictionary, hp: int, hand: Array) -> void:
		p["hp"] = hp
		p["max_hp"] = 4
		p["hand"] = hand
		p["alive"] = true
		p["drunk"] = false
	var mk := func(nm: String, suit: String, pt: int, nat: String = "", yb: Array = []) -> Dictionary:
		return {"name": nm, "suit": suit, "point": pt, "nature": nat, "yb": yb}
	# a) 冰突击命中：防止伤害，弃目标两张牌
	reset.call(A, 4, [mk.call("突击", "黑桃", 7, "冰")])
	reset.call(B, 4, [mk.call("补给", "红桃", 3), mk.call("补给", "红桃", 4), mk.call("补给", "红桃", 6)])
	await eng.use_attack(A, B, (A["hand"] as Array)[0])
	check.call("ice_convert", int(B["hp"]) == 4 and (B["hand"] as Array).size() == 1, "B hp=%d hand=%d" % [int(B["hp"]), (B["hand"] as Array).size()])
	# b) 冰突击：目标仅 1 张牌时不转换，照常 1 点伤害
	reset.call(A, 4, [mk.call("突击", "黑桃", 8, "冰")])
	reset.call(B, 4, [mk.call("补给", "红桃", 3)])
	await eng.use_attack(A, B, (A["hand"] as Array)[0])
	check.call("ice_damage_when_pool1", int(B["hp"]) == 3 and (B["hand"] as Array).size() == 1, "B hp=%d hand=%d" % [int(B["hp"]), (B["hand"] as Array).size()])
	# c) 应变 残躯·目标+：体力 1 时触发，第一目标与追加目标各受 1 点伤害（AI 追加选敌走身份推测，预置 A 对 E 的敌对推测）
	reset.call(A, 1, [mk.call("突击", "黑桃", 9, "", ["残躯", "目标+"])])
	reset.call(B, 4, [])
	reset.call(E, 4, [])
	eng.belief_add(A, E, -6.0)
	await eng.use_attack(A, B, (A["hand"] as Array)[0])
	check.call("yb_canqu_add", int(B["hp"]) == 3 and int(E["hp"]) == 3, "B hp=%d E hp=%d" % [int(B["hp"]), int(E["hp"])])
	# c2) 残躯未满足（体力 3）：不触发，无追加目标
	reset.call(A, 3, [mk.call("突击", "黑桃", 9, "", ["残躯", "目标+"])])
	reset.call(B, 4, [])
	reset.call(E, 4, [])
	await eng.use_attack(A, B, (A["hand"] as Array)[0])
	check.call("yb_canqu_miss", int(B["hp"]) == 3 and int(E["hp"]) == 4, "B hp=%d E hp=%d" % [int(B["hp"]), int(E["hp"])])
	# d) 应变 空巢·伤害+：打出后手牌为 0，伤害 2
	reset.call(A, 3, [mk.call("突击", "红桃", 10, "火", ["空巢", "伤害+"])])
	reset.call(B, 4, [])
	await eng.use_attack(A, B, (A["hand"] as Array)[0])
	check.call("yb_kongchao_damage", int(B["hp"]) == 2, "B hp=%d" % int(B["hp"]))
	# e) 应变 强命：目标持闪避也不可响应
	reset.call(A, 3, [mk.call("突击", "方块", 8, "", ["残躯", "强命"]), mk.call("补给", "红桃", 3)])
	reset.call(B, 4, [mk.call("闪避", "方块", 2)])
	A["hp"] = 1
	await eng.use_attack(A, B, (A["hand"] as Array)[0])
	check.call("yb_hit_unrespondable", int(B["hp"]) == 3 and (B["hand"] as Array).size() == 1, "B hp=%d hand=%d" % [int(B["hp"]), (B["hand"] as Array).size()])
	# f) 富甲评估：手牌全场最多时条件成立
	reset.call(A, 3, [mk.call("补给", "红桃", 3), mk.call("补给", "红桃", 4), mk.call("补给", "红桃", 6)])
	for q in eng.players:
		if q != A:
			reset.call(q, 4, [])
	var fev: Dictionary = eng.eval_yingbian(A, mk.call("突击", "黑桃", 5, "", ["富甲", "摸牌"]))
	check.call("yb_fujia_eval", bool(fev["triggered"]), str(fev))
	# g) 应变 助战·目标+（突击黑桃10）：盟友 D（反贼同队）弃一张基本牌响应，追加目标 E 受 1 点伤害
	var C: Dictionary = eng.players[2]
	var D: Dictionary = eng.players[3]
	reset.call(A, 4, [mk.call("突击", "黑桃", 10, "", ["助战", "目标+"])])
	reset.call(B, 4, [])
	reset.call(C, 4, [])
	reset.call(D, 4, [mk.call("补给", "红桃", 3)])
	reset.call(E, 2, [])
	eng.belief_add(A, E, -6.0)
	await eng.use_attack(A, B, (A["hand"] as Array)[0])
	check.call("yb_zhuzhan_sha", int(B["hp"]) == 3 and int(E["hp"]) == 1 and (D["hand"] as Array).is_empty(), "B hp=%d E hp=%d D hand=%d" % [int(B["hp"]), int(E["hp"]), (D["hand"] as Array).size()])
	# g2) 助战类型不符：盟友只有锦囊牌时不能为基本牌（突击）助战，不触发、无追加
	reset.call(A, 4, [mk.call("突击", "黑桃", 10, "", ["助战", "目标+"])])
	reset.call(B, 4, [])
	reset.call(C, 4, [])
	reset.call(D, 4, [mk.call("灵感爆发", "红桃", 7)])
	reset.call(E, 2, [])
	await eng.use_attack(A, B, (A["hand"] as Array)[0])
	check.call("yb_zhuzhan_type_miss", int(B["hp"]) == 3 and int(E["hp"]) == 2 and (D["hand"] as Array).size() == 1, "B hp=%d E hp=%d D hand=%d" % [int(B["hp"]), int(E["hp"]), (D["hand"] as Array).size()])
	# h) 应变 助战·目标+（逐近弃远梅花3）：盟友弃一张锦囊牌响应，A 先后获得 B 与追加目标 E 的牌（均距离 1）
	reset.call(A, 4, [mk.call("逐近弃远", "梅花", 3, "", ["助战", "目标+"])])
	reset.call(B, 4, [mk.call("补给", "红桃", 3)])
	reset.call(C, 4, [])
	reset.call(D, 4, [mk.call("灵感爆发", "红桃", 7)])
	reset.call(E, 2, [mk.call("补给", "红桃", 4)])
	await eng.play_card(A, (A["hand"] as Array)[0], B)
	check.call("yb_zhuzhan_zhujin", (A["hand"] as Array).size() == 2 and (B["hand"] as Array).is_empty() and (E["hand"] as Array).is_empty() and (D["hand"] as Array).is_empty(), "A hand=%d B=%d E=%d D=%d" % [(A["hand"] as Array).size(), (B["hand"] as Array).size(), (E["hand"] as Array).size(), (D["hand"] as Array).size()])
	# i) 水淹七军单目标＋助战·目标+：只结算 B 与追加目标 E，C 不受影响；盟友弃锦囊牌响应
	reset.call(A, 4, [mk.call("水淹七军", "黑桃", 3, "", ["助战", "目标+"])])
	reset.call(B, 4, [])
	reset.call(C, 4, [])
	reset.call(D, 4, [mk.call("灵感爆发", "红桃", 7)])
	reset.call(E, 2, [])
	await eng.play_card(A, (A["hand"] as Array)[0], B)
	check.call("yb_zhuzhan_shuiyan", int(B["hp"]) == 3 and int(E["hp"]) == 1 and int(C["hp"]) == 4 and (D["hand"] as Array).is_empty(), "B hp=%d E hp=%d C hp=%d D hand=%d" % [int(B["hp"]), int(E["hp"]), int(C["hp"]), (D["hand"] as Array).size()])
	# j) 应变 闪避[空巢·摸牌]：B 只剩这张闪避，打出后手牌为 0，触发摸 1 张
	reset.call(A, 4, [mk.call("突击", "黑桃", 6)])
	reset.call(B, 4, [mk.call("闪避", "红桃", 2, "", ["空巢", "摸牌"])])
	await eng.use_attack(A, B, (A["hand"] as Array)[0])
	check.call("yb_shan_draw", int(B["hp"]) == 4 and (B["hand"] as Array).size() == 1, "B hp=%d hand=%d" % [int(B["hp"]), (B["hand"] as Array).size()])
	# k) 应变 闪避[残躯·反甲]：B 体力 1 打出闪避，获得所响应的那张「突击」
	reset.call(A, 4, [mk.call("突击", "方块", 6)])
	reset.call(B, 1, [mk.call("闪避", "方块", 4, "", ["残躯", "反甲"])])
	await eng.use_attack(A, B, (A["hand"] as Array)[0])
	check.call("yb_shan_gain", int(B["hp"]) == 1 and (B["hand"] as Array).size() == 1 and String(((B["hand"] as Array)[0] as Dictionary)["name"]) == "突击", "B hp=%d hand=%d" % [int(B["hp"]), (B["hand"] as Array).size()])
	# l) 应变 全员休整[富甲·目标-]：A 手牌全场最多，AI 令一名敌人（主公 B）不成为目标，其余受伤者照常回复
	reset.call(A, 2, [mk.call("全员休整", "红桃", 1, "", ["富甲", "目标-"]), mk.call("补给", "红桃", 3), mk.call("补给", "红桃", 4), mk.call("补给", "红桃", 6)])
	reset.call(B, 2, [])
	reset.call(C, 2, [])
	reset.call(D, 2, [])
	reset.call(E, 2, [])
	await eng.play_card(A, (A["hand"] as Array)[0], {})
	check.call("yb_taoyuan_remove", int(B["hp"]) == 2 and int(A["hp"]) == 3 and int(D["hp"]) == 3, "A hp=%d B hp=%d D hp=%d" % [int(A["hp"]), int(B["hp"]), int(D["hp"])])
	# m) 应变 逐近弃远[富甲·强命]：跳过看破窗（B 持看破也不得响应），效果照常结算且日志留痕
	reset.call(A, 4, [mk.call("逐近弃远", "黑桃", 12, "", ["富甲", "强命"]), mk.call("补给", "红桃", 3), mk.call("补给", "红桃", 4), mk.call("补给", "红桃", 6)])
	reset.call(B, 4, [mk.call("看破", "黑桃", 11), mk.call("补给", "红桃", 8)])
	var log_mark: int = eng.log_lines.size()
	await eng.play_card(A, (A["hand"] as Array)[0], B)
	var has_hit_log := false
	for i in range(log_mark, eng.log_lines.size()):
		if String(eng.log_lines[i]).contains("应变·强命"):
			has_hit_log = true
	check.call("yb_zhujin_hit", has_hit_log and (A["hand"] as Array).size() == 4 and (B["hand"] as Array).size() == 1, "A hand=%d B hand=%d log=%s" % [(A["hand"] as Array).size(), (B["hand"] as Array).size(), str(has_hit_log)])
	# n) 出其不意：展示的手牌花色与本体不同 → 1 点伤害
	reset.call(A, 4, [mk.call("出其不意", "红桃", 3)])
	reset.call(B, 4, [mk.call("突击", "黑桃", 6)])
	reset.call(C, 4, [])
	reset.call(D, 4, [])
	reset.call(E, 4, [])
	await eng.play_card(A, (A["hand"] as Array)[0], B)
	check.call("chuqi_diff_suit", int(B["hp"]) == 3 and (B["hand"] as Array).size() == 1, "B hp=%d hand=%d" % [int(B["hp"]), (B["hand"] as Array).size()])
	# n2) 出其不意：花色相同 → 无伤害
	reset.call(A, 4, [mk.call("出其不意", "方块", 12)])
	reset.call(B, 4, [mk.call("补给", "方块", 3)])
	await eng.play_card(A, (A["hand"] as Array)[0], B)
	check.call("chuqi_same_suit", int(B["hp"]) == 4, "B hp=%d" % int(B["hp"]))
	# o) 洞烛先机：对自己使用，卜算后摸 2（手牌 1→弃置本体→摸 2 = 2 张）
	reset.call(A, 4, [mk.call("洞烛先机", "红桃", 7)])
	reset.call(B, 4, [])
	var deck_before: int = eng.deck.size()
	await eng.play_card(A, (A["hand"] as Array)[0], A)
	check.call("dongzhu_self_draw", (A["hand"] as Array).size() == 2 and eng.deck.size() == deck_before - 2, "A hand=%d deck %d->%d" % [(A["hand"] as Array).size(), deck_before, eng.deck.size()])
	# p) 斗地主：叫分＋专属牌（独立引擎实例，mode=doudizhu）
	var eng2 = Engine.new()
	eng2.load_skills()
	eng2.mode = "doudizhu"
	eng2.build_deck()
	var ddz_n := 0
	for c in eng2.deck:
		if String(c["name"]) in ["攻守兼备", "进退自如", "继往开来"]:
			ddz_n += 1
	check.call("ddz_deck_203", eng2.deck.size() == 203 and ddz_n == 6, "size=%d ddz=%d" % [eng2.deck.size(), ddz_n])
	var chars3: Array = []
	for i in 3:
		var cd3: Dictionary = pool[i]
		var sk3: Array = []
		for s3 in cd3["skills"]:
			sk3.append(String((s3 as Dictionary)["sid"]))
		chars3.append({"name": String(cd3["name"]), "hp": 4, "skills": sk3})
	eng2.setup_game(chars3, ["农民", "农民", "农民"])
	await eng2.run_ddz_bidding()
	var lord_n := 0
	var lord_ok := false
	for q in eng2.players:
		if String(q["identity"]) == "地主":
			lord_n += 1
			lord_ok = (q["hand"] as Array).size() == 5 and String((q["equip"]["treasure"] as Dictionary).get("name", "")) == "地契"
	check.call("ddz_bidding", lord_n == 1 and lord_ok and eng2.ddz_multiplier >= 1 and eng2.ddz_multiplier <= 3 and eng2.ddz_landlord_seat >= 0, "lord_n=%d mult=%d" % [lord_n, eng2.ddz_multiplier])
	var A2: Dictionary = eng2.players[0]
	var B2: Dictionary = eng2.players[1]
	var C2: Dictionary = eng2.players[2]
	# p1) 攻守兼备当作弹幕齐射：无人受伤时 AI 选齐射，B/C 无闪避各受 1 点伤害
	reset.call(A2, 4, [mk.call("攻守兼备", "黑桃", 10)])
	reset.call(B2, 4, [])
	reset.call(C2, 4, [])
	await eng2.play_card(A2, (A2["hand"] as Array)[0], {})
	check.call("ddz_gongshou_wanjian", int(B2["hp"]) == 3 and int(C2["hp"]) == 3, "B hp=%d C hp=%d" % [int(B2["hp"]), int(C2["hp"])])
	# p2) 继往开来选项一（弃置摸牌）：剩 3 张手牌时 AI 选弃置重摸
	reset.call(A2, 4, [mk.call("继往开来", "黑桃", 6), mk.call("补给", "红桃", 3), mk.call("补给", "红桃", 4), mk.call("补给", "红桃", 6)])
	reset.call(B2, 4, [])
	reset.call(C2, 4, [])
	await eng2.play_card(A2, (A2["hand"] as Array)[0], A2)
	check.call("ddz_jiwang_redraw", (A2["hand"] as Array).size() == 3, "A hand=%d" % (A2["hand"] as Array).size())
	# p3) 继往开来选项二（当作锦囊）：剩 2 张手牌时 AI 选当作「灵感爆发」摸 2
	reset.call(A2, 4, [mk.call("继往开来", "红桃", 6), mk.call("补给", "红桃", 3), mk.call("补给", "红桃", 4)])
	var log_mark2: int = eng2.log_lines.size()
	await eng2.play_card(A2, (A2["hand"] as Array)[0], A2)
	var has_jw_log := false
	for i in range(log_mark2, eng2.log_lines.size()):
		if String(eng2.log_lines[i]).contains("当作「灵感爆发」"):
			has_jw_log = true
	check.call("ddz_jiwang_as_trick", has_jw_log and (A2["hand"] as Array).size() == 2, "A hand=%d log=%s" % [(A2["hand"] as Array).size(), str(has_jw_log)])
	lines.append("YBTEST_DONE fails=%d" % int(res["fail"]))
	var f := FileAccess.open("/tmp/ask_ybtest.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("\n".join(lines))
	get_tree().quit()


func _run_eng_test() -> void:
	var Engine = preload("res://scripts/engine.gd")
	var lines: Array = []
	var pool: Array = Characters.by_work("星樱坂学园").duplicate()
	for g in 3:
		var eng = Engine.new()
		eng.load_skills()
		var chars: Array = []
		var ids := ["主公", "忠臣", "反贼", "反贼", "内奸"]
		pool.shuffle()
		for i in 5:
			var cd: Dictionary = pool[i]
			var sk: Array = []
			for s in cd["skills"]:
				sk.append(String((s as Dictionary)["sid"]))
			chars.append({"name": String(cd["name"]), "hp": int(cd["hp"]), "skills": sk})
		eng.setup_game(chars, ids)
		await eng.run_game()
		lines.append("game%d over=%s winner=%s rounds=%d logs=%d" % [g + 1, str(eng.game_over), eng.winner_text, eng.round_no, eng.log_lines.size()])
		if OS.get_cmdline_user_args().has("--logdump"):
			var lf := FileAccess.open("/tmp/ask_eng_log.txt", FileAccess.WRITE)
			lf.store_string("\n".join(eng.log_lines))
			lf.close()
	var f := FileAccess.open("/tmp/ask_eng_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()


var drift_t := 0.0


func _process(delta: float) -> void:
	drift_t += delta
	if bg != null:
		bg.position = Vector2(-20 + sin(drift_t * TAU / 26.0) * 9.0, -24 + cos(drift_t * TAU / 33.0) * 6.0)


func _petal_texture(near: bool) -> Texture2D:
	var w := 30 if near else 20
	var h := 22 if near else 15
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (float(x) / float(maxi(w - 1, 1))) * 2.0 - 1.0
			var v := (float(y) / float(maxi(h - 1, 1))) * 2.0 - 1.0
			var r := pow(absf(u), 2.4) + pow(absf(v), 1.5)
			var a := clampf(1.0 - r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1.0, 0.62 + 0.20 * a, 0.74 + 0.18 * a, a * 0.9))
	return ImageTexture.create_from_image(img)


func _make_petals(amount: int, near: bool, vmin: float, vmax: float, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(980, 6)
	p.position = Vector2(960, -16)
	p.direction = Vector2(0.25, 1)
	p.spread = 18.0
	p.gravity = Vector2(-6, 4)
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.angular_velocity_min = -110.0
	p.angular_velocity_max = 110.0
	p.scale_amount_min = 0.85
	p.scale_amount_max = 1.45
	p.texture = _petal_texture(near)
	return p


func _fit_wide() -> void:
	# V0.24 修复：stretch aspect=expand 下 4:3 等较方的屏幕视口会变高（1920×1440），旧版背景/遮罩高度写死 1080，底部露出空白
	var vs := get_viewport_rect().size
	var w := vs.x
	var h := maxf(vs.y, 1080.0)
	if bg != null:
		bg.size = Vector2(w + 40.0, h + 48.0)
	if veil_ref != null:
		veil_ref.size = Vector2(w, h)
	if vig_ref != null:
		vig_ref.size = Vector2(w, h)
	# 界面按 1080 高设计：视口更高时（4:3、平板）把内容区垂直居中，上下由背景填充
	if screen_root != null:
		var pad := floorf(maxf(vs.y - 1080.0, 0.0) * 0.5)
		screen_root.offset_top = pad
		screen_root.offset_bottom = -pad
	for p in [petal_far, petal_near]:
		if p != null:
			p.position.x = w * 0.5
			p.emission_rect_extents = Vector2(w * 0.5 + 20.0, 6)


# ---------------- V0.25 关键画面截图 / 录屏驱动（仅开发自测） ----------------
# --shot=v25_<场景>：select 选牌+目标高亮、drag 拖拽吸附、discard 弃牌多选、respond 响应倒计时、
#                     fly 出牌飞行、hit 受击、skill 技能横幅、dying 濒死、seat 座位状态
func _v25_battle() -> BattleScreen:
	show_battle()
	var bs: BattleScreen = null
	for ch in screen_root.get_children():
		if ch is BattleScreen:
			bs = ch
	return bs


func _v25_reach_play(bs: BattleScreen) -> bool:
	for step in 900:
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(bs) or bs.game_over:
			return false
		if bs.draft_layer != null and bs.draft_layer.visible:
			for b in bs.draft_layer.get_children():
				if b is Button:
					(b as Button).pressed.emit()
					break
			continue
		if bs.interactive and bs.turn_seat == 0 and bs.in_play_phase and not bs.asking:
			return true
		if bs.asking:
			bs.test_answer(-1)  # V0.27：询问改为「选中+确定」，截图驱动直接按默认项作答
	return false


func _v25_capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/ask_shot_%s.png" % name)


func _v25_give(bs: BattleScreen, nm: String, suit: String, point: int) -> Dictionary:
	var c := {"name": nm, "suit": suit, "point": point, "nature": "", "yb": []}
	(bs.players[0]["hand"] as Array).append(c)
	bs.refresh()
	return c


func _shot_v25(target: String) -> void:
	var scene := target.trim_prefix("v25_")
	var bs := _v25_battle()
	bs.start_match(false)
	if scene == "demo":
		Engine.time_scale = 8.0  # 录屏：开局到自己出牌阶段快进，正片从自己回合开始
	if not await _v25_reach_play(bs):
		printerr("V25_NO_PLAY over=%s winner=%s" % [str(bs.game_over if is_instance_valid(bs) else "freed"), String(bs.eng.winner_text) if is_instance_valid(bs) and bs.eng != null else ""])
		await _v25_capture(target)
		get_tree().quit()
		return
	await get_tree().create_timer(1.2).timeout
	var me: Dictionary = bs.players[0]
	match scene:
		"select", "drag":
			me["used_attack"] = false
			var sha := _v25_give(bs, "突击", "黑桃", 7)
			await get_tree().create_timer(0.4).timeout
			bs._select_card(sha)
			await get_tree().create_timer(0.6).timeout
			if scene == "drag" and not bs.target_candidates.is_empty():
				var w := bs._find_wrap(sha)
				var pn := bs.seat_panel_of(int(bs.target_candidates[0]))
				var start := w.global_position + Vector2(86, 134)
				var press := InputEventMouseButton.new()
				press.button_index = MOUSE_BUTTON_LEFT
				press.pressed = true
				press.global_position = start
				bs._on_card_gui_input(w, press)
				var dest := pn.global_position + pn.size * 0.5 + Vector2(40, 60)
				for k in 10:
					var mm := InputEventMouseMotion.new()
					mm.global_position = start.lerp(dest, float(k + 1) / 10.0)
					bs._on_card_gui_input(w, mm)
					await get_tree().process_frame
				await get_tree().create_timer(0.3).timeout
		"discard":
			for i in 3:
				_v25_give(bs, ["闪避", "补给", "看破"][i], ["方块", "红桃", "梅花"][i], 3 + i)
			bs.eng.discard_need = 2
			var runner := func() -> void:
				await bs._eng_choose_discard(me)
			runner.call()
			await get_tree().create_timer(0.4).timeout
			bs.drag_end_ms = 0
			((bs.hand_cards[0] as Control).get_child(0) as Button).pressed.emit()
			await get_tree().create_timer(0.5).timeout
		"seats", "hit":
			var pl: Array = bs.players
			var n := pl.size()
			(pl[1] as Dictionary)["equip"]["weapon"] = {"name": "钢纹长槊", "suit": "黑桃", "point": 12}
			(pl[1] as Dictionary)["equip"]["armor"] = {"name": "结界手环", "suit": "梅花", "point": 2}
			(pl[1] as Dictionary)["equip"]["minus"] = {"name": "疾行之靴", "suit": "黑桃", "point": 5}
			me["equip"]["weapon"] = {"name": "雷霆法杖", "suit": "方块", "point": 1}
			me["equip"]["plus"] = {"name": "远行披风", "suit": "红桃", "point": 13}
			me["judge"].append({"name": "沉迷游戏", "suit": "黑桃", "point": 6})
			if n > 2:
				(pl[2] as Dictionary)["judge"].append({"name": "沉迷游戏", "suit": "黑桃", "point": 6})
				(pl[2] as Dictionary)["judge"].append({"name": "落雷", "suit": "黑桃", "point": 1})
				(pl[2] as Dictionary)["chained"] = true
			me["chained"] = true
			if n > 3:
				(pl[3] as Dictionary)["hp"] = 0
			if n > 4:
				(pl[4] as Dictionary)["alive"] = false
				(pl[4] as Dictionary)["hp"] = 0
				bs._eng_fx("death", {"seat": 4})
			bs.guess_marks[1] = "反"
			bs.refresh()
			await get_tree().create_timer(0.9).timeout
			if scene == "hit":
				(pl[1] as Dictionary)["hp"] = int((pl[1] as Dictionary)["hp"]) - 2
				bs._eng_fx("damage", {"seat": 1, "num": 2, "nature": "雷"})
				bs._eng_fx("chain_hit", {"seat": 1})
				bs.refresh()
				await get_tree().create_timer(0.12).timeout
			else:
				if n > 3:
					bs._open_guess(n - 2)
				await get_tree().create_timer(0.3).timeout
		"demo":
			# 录屏：选牌上浮 → 取消 → 拖向目标吸附松手出牌 → 开托管让对局自然进行
			Engine.time_scale = 1.0
			printerr("DEMO_START_FRAME %d" % Engine.get_process_frames())
			me["used_attack"] = false
			var dsha := _v25_give(bs, "突击", "黑桃", 7)
			await get_tree().create_timer(0.8).timeout
			bs._select_card(dsha)
			await get_tree().create_timer(1.2).timeout
			bs._on_cancel_pressed()
			await get_tree().create_timer(0.5).timeout
			var dcands: Array = bs.candidates_for(me, dsha)
			if not dcands.is_empty():
				var dw := bs._find_wrap(dsha)
				var dpn := bs.seat_panel_of(int(dcands[0]["seat"]))
				var dstart := dw.global_position + Vector2(86, 134)
				var dpress := InputEventMouseButton.new()
				dpress.button_index = MOUSE_BUTTON_LEFT
				dpress.pressed = true
				dpress.global_position = dstart
				bs._on_card_gui_input(dw, dpress)
				var ddest := dpn.global_position + dpn.size * 0.5
				for k in 30:
					var dmm := InputEventMouseMotion.new()
					dmm.global_position = dstart.lerp(ddest, float(k + 1) / 30.0)
					bs._on_card_gui_input(dw, dmm)
					await get_tree().process_frame
				await get_tree().create_timer(0.5).timeout
				var drel := InputEventMouseButton.new()
				drel.button_index = MOUSE_BUTTON_LEFT
				drel.pressed = false
				drel.global_position = ddest
				bs._on_card_gui_input(dw, drel)
			else:
				printerr("DEMO_NO_TARGET")
			await get_tree().create_timer(2.5).timeout
			bs.toggle_auto()
			await get_tree().create_timer(12.0).timeout
			printerr("DEMO_END_FRAME %d" % Engine.get_process_frames())
			get_tree().quit()
			return
		"banner":
			bs.refresh()
			await get_tree().create_timer(0.3).timeout
			bs._eng_fx("skill", {"seat": 2, "name": "风纪", "big": false})
			bs.show_bubble(1, "attack")
			await get_tree().create_timer(0.3).timeout
		"respond":
			_v25_give(bs, "闪避", "方块", 9)
			await get_tree().create_timer(0.2).timeout
			var runner2 := func() -> void:
				await bs._eng_ask_respond(me, "闪避", "宫坂歌织 对你使用了「突击」")
			runner2.call()
			await get_tree().create_timer(5.5).timeout
		"fly", "zone":
			me["used_attack"] = false
			var sha2 := _v25_give(bs, "突击", "红桃", 10)
			await get_tree().create_timer(0.5).timeout
			bs._select_card(sha2)
			if scene == "zone":
				var p1: Dictionary = bs.players[1]
				var p2: Dictionary = bs.players[2]
				bs._eng_played({"name": "全场乱斗", "suit": "黑桃", "point": 7}, bs.pname(p1))
				await get_tree().create_timer(0.5).timeout
				bs._eng_played({"name": "看破", "suit": "梅花", "point": 12}, bs.pname(p2))
				bs._eng_fx("nullify", {"seat": 2, "negated": true})
				await get_tree().create_timer(0.5).timeout
				bs._eng_fx("judge", {"seat": 1, "card": {"name": "闪避", "suit": "黑桃", "point": 5}, "label": "落雷"})
				await get_tree().create_timer(1.1).timeout
			elif not bs.target_candidates.is_empty():
				if bs.sel_target != int(bs.target_candidates[0]):
					bs._on_seat_clicked(int(bs.target_candidates[0]))
				bs._on_confirm_pressed()
				await get_tree().create_timer(0.16).timeout
	await _v25_capture(target)
	get_tree().quit()


# --shot=v26_<场景>：card 长按手牌说明卡、char 长按座位角色卡、help 新手说明页、gallery 图鉴长按、skill 长按技能
func _v26_press(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	var wp := get_tree().root.get_final_transform() * pos  # 视口坐标 → 窗口坐标（4:3 等比例下有拉伸）
	ev.position = wp
	ev.global_position = wp
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(ev)


func _shot_v26(target: String) -> void:
	var scene := target.trim_prefix("v26_")
	if scene == "help":
		show_help()
		await get_tree().create_timer(0.8).timeout
		await _v25_capture(target)
		get_tree().quit()
		return
	if scene == "gallery":
		show_gallery()
		await get_tree().create_timer(0.8).timeout
		var cardb: Control = null
		for n in screen_root.find_children("*", "Button", true, false):
			if (n as Control).has_meta("intro"):
				cardb = n
				break
		var gp := cardb.get_global_rect().get_center()
		_v26_press(gp, true)
		await get_tree().create_timer(0.7).timeout
		await _v25_capture(target)
		get_tree().quit()
		return
	var bs := _v25_battle()
	bs.start_match(false)
	if not await _v25_reach_play(bs):
		printerr("V26_NO_PLAY")
		await _v25_capture(target)
		get_tree().quit()
		return
	await get_tree().create_timer(1.0).timeout
	var me: Dictionary = bs.players[0]
	var pos := Vector2.ZERO
	match scene:
		"card", "card43":
			var c := {"name": "突击", "suit": "黑桃", "point": 9, "nature": "", "yb": ["残躯", "目标+"]}
			(me["hand"] as Array).append(c)
			bs.refresh()
			await get_tree().create_timer(0.6).timeout
			for w in bs.hand_row.get_children():
				if w.has_meta("card") and is_same(w.get_meta("card"), c):
					pos = (w as Control).get_global_rect().get_center() + Vector2(0, -40)
		"weapon":
			var c2 := {"name": "星月画戟", "suit": "方块", "point": 12, "nature": "", "yb": []}
			(me["hand"] as Array).append(c2)
			bs.refresh()
			await get_tree().create_timer(0.6).timeout
			for w in bs.hand_row.get_children():
				if w.has_meta("card") and is_same(w.get_meta("card"), c2):
					pos = (w as Control).get_global_rect().get_center() + Vector2(0, -40)
		"char":
			var p1: Dictionary = bs.players[1]
			p1["equip"]["weapon"] = {"name": "破空长弓", "suit": "红桃", "point": 5}
			p1["equip"]["armor"] = {"name": "藤蔓铠甲", "suit": "黑桃", "point": 2}
			var has_cm := false
			for jc in p1["judge"]:
				if String(jc["name"]) == "沉迷游戏":
					has_cm = true
			if not has_cm:
				(p1["judge"] as Array).append({"name": "沉迷游戏", "suit": "黑桃", "point": 6})
			bs.refresh()
			await get_tree().create_timer(0.6).timeout
			pos = bs.seat_panel_of(1).get_global_rect().get_center()
		"skill":
			await get_tree().create_timer(0.3).timeout
			if bs.skill_btns.get_child_count() > 0:
				pos = (bs.skill_btns.get_child(0) as Control).get_global_rect().get_center()
			elif bs.skill_passives.get_child_count() > 0:
				pos = (bs.skill_passives.get_child(0) as Control).get_global_rect().get_center()
	_v26_press(pos, true)
	await get_tree().create_timer(0.75).timeout
	await _v25_capture(target)
	_v26_press(pos, false)
	get_tree().quit()



# V0.27：截图/冒烟驱动作答当前询问的第一项（选中+确定模式下直接按第一项作答）
func _drv_first(bs) -> void:
	if bs.asking and String(bs.ask_mode) != "":
		bs.test_answer(0)
	elif bs.prompt_btns.get_child_count() > 0:
		(bs.prompt_btns.get_child(0) as Button).pressed.emit()


# --shot=v27_<场景>：target 选牌+选目标等待确定、chain 多目标、skill 技能选择状态、respond 响应选中待确定、settings 设置面板
func _shot_v27(target: String) -> void:
	var scene := target.trim_prefix("v27_")
	var bs := _v25_battle()
	bs.start_match(false)
	bs.set_auto_confirm(false, false)
	if not await _v25_reach_play(bs):
		printerr("V27_NO_PLAY")
		await _v25_capture(target)
		get_tree().quit()
		return
	await get_tree().create_timer(1.0).timeout
	var me: Dictionary = bs.players[0]
	match scene:
		"target":
			me["used_attack"] = false
			me["attack_count"] = 0
			var c := _v25_give(bs, "突击", "黑桃", 9)
			await get_tree().create_timer(0.4).timeout
			bs._on_hand_card_clicked(c)
			var cs: Array = bs.target_candidates
			if not cs.is_empty() and bs.sel_target < 0:
				bs._on_seat_clicked(int(cs[0]))
		"chain":
			var c3 := _v25_give(bs, "羁绊锁链", "梅花", 11)
			await get_tree().create_timer(0.4).timeout
			bs._on_hand_card_clicked(c3)
			var n := 0
			for s2 in bs.target_candidates.duplicate():
				if int(s2) != 0 and n < 2 and bs.sel_target != int(s2):
					bs._on_seat_clicked(int(s2))
					n += 1
		"skill":
			var sid := ""
			for d in bs.eng.active_options(me):
				if bs._skill_ui_spec(String(d["sid"]))["targets"] != null:
					sid = String(d["sid"])
					break
			if sid == "":
				(me["skills"] as Array).append("yingyuan")
				sid = "yingyuan"
			_v25_give(bs, "看破", "梅花", 12)
			_v25_give(bs, "补给", "红桃", 3)
			await get_tree().create_timer(0.4).timeout
			bs._on_skill_button(sid)
			var spec: Dictionary = bs._skill_ui_spec(sid)
			if String(spec["card"]) != "none" and bs.skill_card.is_empty():
				for hc in me["hand"]:
					if bs._skill_card_ok(hc):
						bs._on_hand_card_clicked(hc)
						break
			if spec["targets"] != null and bs.sel_target < 0:
				for s3 in bs.target_candidates:
					if int(s3) != 0:
						bs._on_seat_clicked(int(s3))
						break
		"respond":
			var d1 := _v25_give(bs, "闪避", "方块", 9)
			_v25_give(bs, "闪避", "红桃", 2)
			bs.ask_timeout = 60.0
			var runner := func() -> void:
				await bs._eng_ask_respond(me, "闪避", "%s 对你使用了「突击」" % bs.pname(bs.players[1]))
			runner.call()
			await get_tree().create_timer(0.4).timeout
			bs._on_hand_card_clicked(d1)
		"settings":
			bs.toggle_settings_panel()
	await get_tree().create_timer(0.8).timeout
	await _v25_capture(target)
	get_tree().quit()


# V0.29：全部牌面拼图（预览用；与对局手牌同一个构建函数）
func _shot_cardwall() -> void:
	clear_screen()
	var bs := BattleScreen.new()
	bs.visible = false
	screen_root.add_child(bs)
	await get_tree().process_frame
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(holder)
	var names: Array = CardDefsM.DEFS.keys()
	var cols := 11
	var k := 0.66
	var cw := 172.0 * k
	var ch := 268.0 * k
	var suits := ["红桃", "黑桃", "方块", "梅花"]
	for i in names.size():
		var nm := String(names[i])
		var c := {"name": nm, "suit": suits[i % 4], "point": (i % 13) + 1, "nature": "", "yb": []}
		var face := Panel.new()
		face.size = Vector2(cw, ch)
		face.position = Vector2(40 + (i % cols) * (cw + 14), 30 + int(i / cols) * (ch + 22))
		var sb := bs.style(Color(1, 1, 1), 12, Color(1, 1, 1), 3, true)
		face.add_theme_stylebox_override("panel", sb)
		holder.add_child(face)
		bs._build_card_face(face, c, Vector2(cw, ch), sb)
	var back := TextureRect.new()
	back.texture = Art.back_tex()
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.size = Vector2(cw, ch)
	back.position = Vector2(40 + (names.size() % cols) * (cw + 14), 30 + int(names.size() / cols) * (ch + 22))
	holder.add_child(back)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/ask_shot_cardwall.png")
	get_tree().quit()


# V0.30 截图：战绩成就页（演示数据写在测试存档）/ 教学关 / 声音设置
func _shot_v30(target: String) -> void:
	if target == "records":
		var demo := [
			{"mode": "identity", "char": "花宫雏", "identity": "主公", "result": "win", "rounds": 9, "dmg": 6, "kills": 2, "heal": 3, "taken": 2, "mvp": true},
			{"mode": "identity", "char": "柚木铃奈", "identity": "反贼", "result": "lose", "rounds": 7, "dmg": 3, "kills": 0, "heal": 0, "taken": 4, "mvp": false},
			{"mode": "doudizhu", "char": "宫坂歌织", "identity": "地主", "result": "win", "rounds": 5, "dmg": 9, "kills": 2, "heal": 1, "taken": 2, "mvp": true},
			{"mode": "duel", "char": "夜宫静羽", "identity": "先手", "result": "win", "rounds": 4, "dmg": 4, "kills": 1, "heal": 0, "taken": 0, "mvp": true},
			{"mode": "doudizhu", "char": "森崎千夏", "identity": "农民", "result": "lose", "rounds": 6, "dmg": 2, "kills": 0, "heal": 5, "taken": 5, "mvp": false},
		]
		for r in demo:
			Meta.record(r)
		Meta.mark_tutorial()
		show_records()
		await get_tree().create_timer(0.8).timeout
	else:
		show_tutorial()
		var bs: BattleScreen = null
		for ch in screen_root.get_children():
			if ch is BattleScreen:
				bs = ch
		if target == "settings":
			await get_tree().create_timer(1.5).timeout
			bs.toggle_settings_panel()
			await get_tree().create_timer(0.6).timeout
		else:
			await get_tree().create_timer(2.5).timeout
			if target == "tutorial2":
				# 装备武器后进入第 2 步
				var me: Dictionary = bs.players[0]
				for c in (me["hand"] as Array):
					if String(c["name"]) == "星光长剑":
						bs.eng.discard_from_hand(me, c)
						me["equip"]["weapon"] = c
						c["range"] = 3
						break
				bs.refresh()
				await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/ask_shot_%s.png" % target)
	get_tree().quit()


var home_showcase_ids: Array = ["sena", "hina", "reo"]
var _home_touch_slot := -1
var _daily_overlay: Control = null


func _attach_l2d_breath(ctrl: Control, phase_delay: float = 0.0, amp_scale: float = 0.018, amp_y: float = 2.5) -> void:
	if ctrl == null:
		return
	ctrl.ready.connect(func() -> void:
		ctrl.pivot_offset = ctrl.size * 0.5
		var y0 := ctrl.position.y
		var tw := create_tween().bind_node(ctrl).set_loops()
		if phase_delay > 0.0:
			var dt := create_tween().bind_node(ctrl)
			dt.tween_interval(phase_delay)
			dt.tween_callback(func() -> void:
				if is_instance_valid(ctrl):
					var tw2 := create_tween().bind_node(ctrl).set_loops()
					tw2.tween_property(ctrl, "scale", Vector2(1.0 + amp_scale, 1.0 + amp_scale), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
					tw2.parallel().tween_property(ctrl, "position:y", y0 - amp_y, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
					tw2.tween_property(ctrl, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
					tw2.parallel().tween_property(ctrl, "position:y", y0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))
			tw.kill()
		else:
			tw.tween_property(ctrl, "scale", Vector2(1.0 + amp_scale, 1.0 + amp_scale), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.parallel().tween_property(ctrl, "position:y", y0 - amp_y, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(ctrl, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.parallel().tween_property(ctrl, "position:y", y0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))


func _bounce_control(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.scale = Vector2(1.045, 0.96)
	var tw := create_tween().bind_node(ctrl)
	tw.tween_property(ctrl, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _spawn_touch_burst(parent: Control, pos: Vector2, emojis: Array, tag_txt: String = "") -> void:
	if parent == null or not is_instance_valid(parent) or DisplayServer.get_name() == "headless":
		return
	for i_b in 5:
		var em_lbl := lbl(String(emojis[i_b % emojis.size()]), 28, C_PINK_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER)
		em_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		em_lbl.position = pos - Vector2(16, 16)
		parent.add_child(em_lbl)
		var ang := -PI * 0.5 + (float(i_b) - 2.0) * 0.45 + randf_range(-0.15, 0.15)
		var dist := randf_range(58.0, 96.0)
		var tw := create_tween().bind_node(em_lbl).set_parallel(true)
		tw.tween_property(em_lbl, "position", pos + Vector2(cos(ang), sin(ang)) * dist - Vector2(16, 16), 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(em_lbl, "modulate:a", 0.0, 0.72)
		tw.chain().tween_callback(func() -> void: if is_instance_valid(em_lbl): em_lbl.queue_free())
	if tag_txt != "":
		var tl := lbl(tag_txt, 26, C_PINK_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER)
		tl.add_theme_constant_override("outline_size", 6)
		tl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tl.position = pos - Vector2(40, 28)
		parent.add_child(tl)
		var tw2 := create_tween().bind_node(tl).set_parallel(true)
		tw2.tween_property(tl, "position:y", pos.y - 84.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw2.tween_property(tl, "modulate:a", 0.0, 0.85)
		tw2.chain().tween_callback(func() -> void: if is_instance_valid(tl): tl.queue_free())


func _open_daily_overlay() -> void:
	if _daily_overlay != null and is_instance_valid(_daily_overlay):
		_daily_overlay.queue_free()
	var ov := Control.new()
	ov.name = "DailyOverlay"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(ov)
	_daily_overlay = ov
	var dim := ColorRect.new()
	dim.color = Color(0.10, 0.05, 0.16, 0.68)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(dim)
	var card := PanelContainer.new()
	card.position = Vector2(410, 96)
	card.custom_minimum_size = Vector2(1100, 0)
	card.size = Vector2(1100, 0)
	var csb := style(Color(1.0, 0.98, 0.96, 0.98), 28, C_GOLD, 4, true)
	csb.content_margin_left = 30
	csb.content_margin_right = 30
	csb.content_margin_top = 20
	csb.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", csb)
	ov.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 16)
	var ttl := lbl("📋 每日社团委托（%s）" % Time.get_date_string_from_system(), 32, C_PINK_DEEP, true)
	ttl.autowrap_mode = TextServer.AUTOWRAP_OFF
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(ttl)
	var bl := lbl("🪙 欢斗豆：%d" % Meta.beans(), 25, Color(0.72, 0.44, 0.08), true)
	bl.autowrap_mode = TextServer.AUTOWRAP_OFF
	hdr.add_child(bl)
	vb.add_child(hdr)
	var sub_l := lbl("完成任意模式对局或与角色互动即可累计进度，每日 00:00 自动刷新。", 20, C_INK_SOFT)
	sub_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	vb.add_child(sub_l)
	var items := Meta.daily_status()
	for it in items:
		var tid := String(it["id"])
		var done := bool(it["done"])
		var claimed := bool(it["claimed"])
		var claimable := bool(it["claimable"])
		var row_pc := PanelContainer.new()
		var rsb := style(Color(0.95, 1.0, 0.96) if claimed else (Color(1.0, 0.94, 0.97) if claimable else Color(1, 1, 1, 0.95)), 18, C_GOLD if claimable else Color(0.84, 0.78, 0.86), 2)
		rsb.content_margin_left = 18
		rsb.content_margin_right = 18
		rsb.content_margin_top = 10
		rsb.content_margin_bottom = 10
		row_pc.add_theme_stylebox_override("panel", rsb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		row_pc.add_child(hb)
		var info_v := VBoxContainer.new()
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_v.add_theme_constant_override("separation", 4)
		hb.add_child(info_v)
		var rew_s := "🪙+%d 欢斗豆" % int(it["beans"])
		if int(it["aff"]) > 0:
			rew_s += " · ♥看板好感+%d" % int(it["aff"])
		var rt1 := lbl("%s  （%s）" % [String(it["title"]), rew_s], 23, C_INK, true)
		rt1.autowrap_mode = TextServer.AUTOWRAP_OFF
		info_v.add_child(rt1)
		var rt2 := lbl("%s  ·  进度 %d / %d" % [String(it["desc"]), int(it["prog"]), int(it["goal"])], 19, C_INK_SOFT)
		rt2.autowrap_mode = TextServer.AUTOWRAP_OFF
		info_v.add_child(rt2)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.max_value = float(int(it["goal"]))
		bar.value = float(int(it["prog"]))
		bar.add_theme_stylebox_override("background", style(Color(0.93, 0.88, 0.92), 5))
		bar.add_theme_stylebox_override("fill", style(Color(0.28, 0.74, 0.44) if done else C_PINK_DEEP, 5))
		info_v.add_child(bar)
		var cbtn := Button.new()
		cbtn.focus_mode = Control.FOCUS_NONE
		cbtn.custom_minimum_size = Vector2(150, 52)
		cbtn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cbtn.text = "✓ 已领取" if claimed else ("领取奖励" if claimable else "进行中")
		cbtn.disabled = not claimable
		cbtn.add_theme_font_override("font", font_bold)
		cbtn.add_theme_font_size_override("font_size", 22)
		_style_btn(cbtn, C_PLATE, C_GOLD, C_WHITE, 16, 2, true, Vector2i(14, 8))
		cbtn.add_theme_stylebox_override("disabled", _tight_sb(style(Color(0.86, 0.92, 0.88) if claimed else Color(0.90, 0.88, 0.92), 16, Color(0.74, 0.80, 0.76) if claimed else Color(0.78, 0.74, 0.82), 1), 14, 8))
		cbtn.add_theme_color_override("font_disabled_color", Color(0.24, 0.56, 0.34) if claimed else C_INK_SOFT)
		cbtn.pressed.connect(func() -> void:
			var r := Meta.claim_daily(tid)
			if bool(r.get("ok", false)):
				AudioCfg.play_ui(self, "heal")
				show_home()
				_open_daily_overlay())
		hb.add_child(cbtn)
		vb.add_child(row_pc)
	var bot := HBoxContainer.new()
	bot.alignment = BoxContainer.ALIGNMENT_CENTER
	bot.add_theme_constant_override("separation", 24)
	vb.add_child(bot)
	var all_ok := Meta.daily_claimable_count() > 0
	var all_b := cute_button("🎁 一键全部领取", "", Color(0.94, 0.42, 0.60) if all_ok else Color(0.70, 0.68, 0.74), Vector2(280, 66))
	all_b.disabled = not all_ok
	all_b.pressed.connect(func() -> void:
		var ar := Meta.claim_all_daily()
		if int(ar.get("claimed_n", 0)) > 0:
			AudioCfg.play_ui(self, "win")
			show_home()
			_open_daily_overlay())
	bot.add_child(all_b)
	var cls_b := cute_button("关闭", "", C_SKY, Vector2(180, 66))
	cls_b.pressed.connect(func() -> void:
		if is_instance_valid(ov):
			ov.queue_free()
		_daily_overlay = null)
	bot.add_child(cls_b)


func _on_home_showcase_clicked(slot_idx: int) -> void:
	if IntroPop.inst != null and IntroPop.inst.swallowing():
		return
	var cands: Array = []
	for c in Meta.enabled_pool(Characters.LIST):
		var cid := String(c["id"])
		if not home_showcase_ids.has(cid):
			cands.append(cid)
	if not cands.is_empty():
		var picked := String(cands[randi() % cands.size()])
		home_showcase_ids[slot_idx] = picked
		Meta.set_showcase_slot(slot_idx, picked)
	show_home()


func show_card_gallery() -> void:
	clear_screen()
	var m := page_margin()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	m.add_child(vb)
	var bbar := back_bar("卡牌图鉴（全 55 种 · 常规 197 张 / 斗地主 203 张）", show_home)
	var to_chars := Button.new()
	to_chars.text = "👤 切换至人物图鉴（%d人）" % Characters.LIST.size()
	to_chars.custom_minimum_size = Vector2(340, 68)
	to_chars.focus_mode = Control.FOCUS_NONE
	to_chars.add_theme_font_override("font", font_bold)
	to_chars.add_theme_font_size_override("font_size", 26)
	_style_btn(to_chars, C_SKY, C_GOLD, C_WHITE, 20, 2, true, Vector2i(18, 10))
	to_chars.pressed.connect(show_gallery)
	bbar.add_child(to_chars)
	vb.add_child(bbar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 24)
	scroll.add_child(inner)
	var CardDefsG = load("res://data/cards.gd")
	var groups := [
		["基本牌", ["基本牌"], "共 4 种 · 90 张（含普通/火/雷/冰突击、闪避、补给、特饮）"],
		["普通锦囊牌", ["锦囊牌"], "即时生效锦囊（含斗地主专属牌攻守兼备/进退自如/继往开来与应变新牌）"],
		["延时锦囊牌", ["延时锦囊"], "置入判定区，于判定阶段判定生效"],
		["装备牌（武器 / 防具 / 坐骑 / 宝物）", ["武器", "防具", "饰品", "宝物"], "装备入对应栏位持续生效"],
	]
	for g in groups:
		var head := PanelContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_PASS
		head.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.88), 22, C_GOLD, 2, true))
		var hv := VBoxContainer.new()
		hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hv.add_child(lbl("分类 · %s" % String(g[0]), 34, C_PINK_DEEP, true))
		hv.add_child(lbl(String(g[2]), 22, C_INK_SOFT))
		head.add_child(hv)
		inner.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 20)
		grid.add_theme_constant_override("v_separation", 20)
		inner.add_child(grid)
		var kinds: Array = g[1]
		for nm in CardDefsG.DEFS.keys():
			var d: Dictionary = CardDefsG.DEFS[nm]
			if not kinds.has(String(d.get("kind", ""))):
				continue
			var cb := Button.new()
			cb.focus_mode = Control.FOCUS_NONE
			cb.custom_minimum_size = Vector2(432, 224)
			var fcol := Art.frame_color(String(nm))
			_style_btn(cb, Color(1, 1, 1, 0.95), fcol, C_INK, 20, 3, true, Vector2i(-1, -1), false, C_GOLD)
			var hb := HBoxContainer.new()
			hb.mouse_filter = MOUSE_FILTER_IGNORE
			hb.set_anchors_preset(Control.PRESET_FULL_RECT)
			hb.offset_left = 14
			hb.offset_right = -14
			hb.offset_top = 12
			hb.offset_bottom = -12
			hb.add_theme_constant_override("separation", 14)
			var tr := TextureRect.new()
			tr.texture = Art.card_tex(String(nm))
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.custom_minimum_size = Vector2(130, 186)
			tr.mouse_filter = MOUSE_FILTER_IGNORE
			hb.add_child(tr)
			var tv := VBoxContainer.new()
			tv.mouse_filter = MOUSE_FILTER_IGNORE
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tv.add_theme_constant_override("separation", 6)
			var title_l := lbl("%s（×%d）" % [String(nm), int(d.get("n", 1))], 25, C_INK, true)
			title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tv.add_child(title_l)
			tv.add_child(lbl(String(d.get("kind", "")), 19, fcol, true))
			var desc := String(d.get("effect", ""))
			if desc.length() > 74:
				desc = desc.substr(0, 74) + "…"
			var dl := lbl(desc, 18, C_INK_SOFT)
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.add_theme_constant_override("line_spacing", 2)
			tv.add_child(dl)
			hb.add_child(tv)
			cb.add_child(hb)
			var spec := IntroPop.card_spec({"name": String(nm), "suit": "", "point": 0})
			cb.set_meta("intro", spec)
			_wire_scroll_drag(cb, scroll)
			cb.pressed.connect(func() -> void:
				if float(cb.get_meta("drag_px", 0.0)) > 18.0:
					cb.set_meta("drag_px", 0.0)
					return
				if IntroPop.inst != null and not IntroPop.inst.swallowing():
					IntroPop.inst.show_spec(spec, cb.get_global_rect().get_center(), "sticky"))
			grid.add_child(cb)
