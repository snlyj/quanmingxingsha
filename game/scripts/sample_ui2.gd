extends Control

# UI 精致化样本（D 樱庭昼 / E 祭典夜）：插画背景 + 材质边框 + 宝石徽章 + 铭牌
var T: Dictionary = {}
var font_reg: Font
var font_bold: Font

func themes() -> Dictionary:
	return {
		"D": {"bg": "res://assets/bg/bg_blossom_day.webp", "veil": Color(1, 1, 1, 0.10), "frame": Color("e8a33d"), "frame2": Color("ff8fab"), "plate": Color("ff5c8a"), "ink": Color("40222e"), "soft": Color("7a4a5c"), "glass": Color(1, 1, 1, 0.88), "dark": false, "gem": Color("ff5c8a"), "chip": Color(0.16, 0.1, 0.14, 0.72), "accent": Color("ff5c8a"), "band": Color("ffd9e4")},
		"E": {"bg": "res://assets/bg/bg_festival_night.webp", "veil": Color(0.05, 0.02, 0.12, 0.18), "frame": Color("f2c14e"), "frame2": Color("ff6ec7"), "plate": Color("b13d8f"), "ink": Color("fff3e2"), "soft": Color("e8c9a8"), "glass": Color(0.1, 0.07, 0.2, 0.85), "dark": true, "gem": Color("ff5da2"), "chip": Color(0.05, 0.03, 0.1, 0.78), "accent": Color("ff5da2"), "band": Color("2c1e4a")},
	}

func st(bg: Color, radius: int, border: Color, bw: int, shadow: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = 12
		s.shadow_offset = Vector2(0, 5)
	return s

func lb(text: String, size: int, color: Color, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold and font_bold:
		l.add_theme_font_override("font", font_bold)
	elif font_reg:
		l.add_theme_font_override("font", font_reg)
	l.horizontal_alignment = align
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l

func panel(parent: Control, pos: Vector2, size: Vector2, style: StyleBox) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

func portrait_in(parent: Control, tex: Texture2D, pos: Vector2, size: Vector2) -> void:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	tr.position = pos
	tr.size = size

func build(key: String) -> void:
	T = themes()[key]
	font_reg = load("res://assets/fonts/NotoSansSC-Regular.otf")
	font_bold = load("res://assets/fonts/NotoSansSC-Bold.otf")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bgtex: Texture2D = load(T["bg"])
	var bg := TextureRect.new()
	bg.texture = bgtex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.position = Vector2.ZERO
	bg.size = Vector2(1920, 1080)
	var veil := ColorRect.new()
	veil.color = T["veil"]
	veil.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(veil)
	veil.position = Vector2.ZERO
	veil.size = Vector2(1920, 1080)
	_topbar()
	var seats := [Vector2(64, 296), Vector2(452, 120), Vector2(1218, 120), Vector2(1606, 296)]
	var cidx := [1, 2, 3, 4]
	for i in 4:
		_seat(seats[i], int(cidx[i]), i == 1)
	_center()
	_own()
	_hand()
	_log()

func _char(idx: int) -> Dictionary:
	var chars = load("res://data/characters.gd")
	return chars.LIST[idx]

func _topbar() -> void:
	var shadow := lb("全明星杀", 58, Color(0, 0, 0, 0.28), true)
	shadow.position = Vector2(52, 30)
	add_child(shadow)
	var logo := lb("全明星杀", 58, T["accent"] if not T["dark"] else Color("ffd76a"), true)
	logo.position = Vector2(48, 26)
	add_child(logo)
	var en := lb("A L L   S T A R   K I L L", 19, T["soft"], true)
	en.position = Vector2(52, 100)
	add_child(en)
	panel(self, Vector2(52, 128), Vector2(150, 4), st(T["frame"], 2, Color.TRANSPARENT, 0))
	var infos := ["♥ 24/24", "◆ 10000", "✦ 620"]
	for i in 3:
		var x := 1330 + i * 196
		panel(self, Vector2(x, 30), Vector2(180, 52), st(Color(1, 1, 1, 0.85) if not T["dark"] else Color(0.08, 0.06, 0.16, 0.85), 26, Color(1, 1, 1, 0.7), 1, true))
		var t := lb(infos[i], 25, T["ink"] if not T["dark"] else Color("ffe9f4"), true, HORIZONTAL_ALIGNMENT_CENTER)
		t.position = Vector2(x, 40)
		t.size = Vector2(180, 34)
		add_child(t)
	var phase := lb("出牌阶段", 30, T["ink"], true, HORIZONTAL_ALIGNMENT_CENTER)
	phase.position = Vector2(760, 34)
	phase.size = Vector2(400, 42)
	add_child(phase)
	var sub := lb("— 柚木铃奈 · 第 2 轮 —", 21, T["soft"], false, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(760, 78)
	sub.size = Vector2(400, 30)
	add_child(sub)

func _seat(pos: Vector2, cidx: int, active: bool) -> void:
	var c: Dictionary = _char(cidx)
	if active:
		panel(self, pos + Vector2(-10, -10), Vector2(270, 392), st(Color(T["frame"].r, T["frame"].g, T["frame"].b, 0.45), 26, Color.TRANSPARENT, 0))
	panel(self, pos + Vector2(5, 8), Vector2(250, 372), st(Color(0, 0, 0, 0.3), 22, Color.TRANSPARENT, 0))
	var card := panel(self, pos, Vector2(250, 372), st(T["frame"], 22, Color(1, 1, 1, 0.85), 2, true))
	panel(card, Vector2(5, 5), Vector2(240, 362), st(Color.WHITE, 18, Color.TRANSPARENT, 0))
	portrait_in(card, load(String(c["portrait"])), Vector2(7, 7), Vector2(236, 358))
	panel(card, Vector2(7, 7), Vector2(236, 358), st(Color(0, 0, 0, 0), 18, Color(1, 1, 1, 0.55), 1))
	var gem := panel(card, Vector2(12, 12), Vector2(50, 50), st(T["gem"], 25, Color.WHITE, 3, true))
	var ids := ["?", "主", "?", "?"]
	var gt := lb(ids[cidx % 4], 27, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	gt.position = Vector2(12, 19)
	gt.size = Vector2(50, 36)
	card.add_child(gt)
	var hps := [3, 4, 3, 4]
	var mxs := [3, 4, 3, 4]
	for i in int(mxs[cidx % 4]):
		var full := i < int(hps[cidx % 4])
		var dot := panel(card, Vector2(216, 14 + i * 27), Vector2(21, 21), st(Color("ff6b9d") if full else Color(0.2, 0.2, 0.25, 0.45), 10, Color(1, 1, 1, 0.95), 2, full))
		if full:
			panel(dot, Vector2(4, 3), Vector2(7, 7), st(Color(1, 1, 1, 0.85), 3, Color.TRANSPARENT, 0))
	var plate := panel(card, Vector2(-8, 316), Vector2(215, 52), st(T["plate"], 10, Color(1, 1, 1, 0.8), 2, true))
	plate.rotation = -0.02
	var nm := lb(String(c["name"]), 28, Color.WHITE, true)
	nm.position = Vector2(10, 8)
	plate.add_child(nm)
	var chip := panel(card, Vector2(168, 272), Vector2(76, 36), st(T["chip"], 18, Color(1, 1, 1, 0.5), 1))
	var ct := lb("✋ %d" % [3, 4, 2, 5][cidx % 4], 21, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	ct.position = Vector2(0, 5)
	ct.size = Vector2(76, 26)
	chip.add_child(ct)
	if active:
		var tag := lb("▼ 行动中", 23, T["frame"], true, HORIZONTAL_ALIGNMENT_CENTER)
		tag.position = Vector2(pos.x, pos.y - 36)
		tag.size = Vector2(250, 32)
		add_child(tag)
		var dmg := lb("-2", 74, Color("e8253c"), true, HORIZONTAL_ALIGNMENT_CENTER)
		dmg.position = Vector2(pos.x + 130, pos.y - 66)
		dmg.size = Vector2(150, 84)
		dmg.add_theme_constant_override("outline_size", 12)
		dmg.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
		add_child(dmg)

func _game_card(parent: Control, pos: Vector2, size: Vector2, suit: String, point: String, cname: String, ctype: String, rot: float) -> void:
	var holder := Control.new()
	holder.position = pos
	holder.size = size
	holder.rotation = rot
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	panel(holder, Vector2(3, 5), size, st(Color(0, 0, 0, 0.28), 14, Color.TRANSPARENT, 0))
	panel(holder, Vector2.ZERO, size, st(Color("fffafd") if not T["dark"] else Color("241a3e"), 14, T["frame2"], 2))
	panel(holder, Vector2(0, 0), Vector2(size.x, size.y * 0.16), st(T["plate"], 0, Color.TRANSPARENT, 0))
	var s := lb("%s %s" % [suit, point], 24, Color.WHITE, true)
	s.position = Vector2(10, 2)
	holder.add_child(s)
	var glow := panel(holder, Vector2(size.x * 0.18, size.y * 0.26), Vector2(size.x * 0.64, size.x * 0.64), st(Color(T["frame2"].r, T["frame2"].g, T["frame2"].b, 0.16), int(size.x * 0.32), Color.TRANSPARENT, 0))
	var big := lb(cname.substr(0, 1), 84, Color(T["plate"].r, T["plate"].g, T["plate"].b, 0.9), true, HORIZONTAL_ALIGNMENT_CENTER)
	big.position = Vector2(0, size.y * 0.3)
	big.size = Vector2(size.x, 100)
	holder.add_child(big)
	var nm := lb(cname, 30, T["ink"] if not T["dark"] else Color("ffe9f4"), true, HORIZONTAL_ALIGNMENT_CENTER)
	nm.position = Vector2(0, size.y * 0.74)
	nm.size = Vector2(size.x, 38)
	holder.add_child(nm)
	var tg := lb(ctype, 18, T["soft"], false, HORIZONTAL_ALIGNMENT_CENTER)
	tg.position = Vector2(0, size.y * 0.88)
	tg.size = Vector2(size.x, 24)
	holder.add_child(tg)

func _center() -> void:
	panel(self, Vector2(560, 552), Vector2(180, 3), st(T["frame"], 1, Color.TRANSPARENT, 0))
	panel(self, Vector2(1180, 552), Vector2(180, 3), st(T["frame"], 1, Color.TRANSPARENT, 0))
	var banner := lb("柚木铃奈 的回合", 38, T["frame"], true, HORIZONTAL_ALIGNMENT_CENTER)
	banner.position = Vector2(740, 528)
	banner.size = Vector2(440, 52)
	banner.add_theme_constant_override("outline_size", 6)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3) if not T["dark"] else Color(0, 0, 0, 0.7))
	add_child(banner)
	_game_card(self, Vector2(866, 206), Vector2(196, 272), "♥", "7", "突击", "基本牌", -0.035)
	var from := lb("铃奈 ➜ 千夏", 21, T["soft"], true, HORIZONTAL_ALIGNMENT_CENTER)
	from.position = Vector2(816, 492)
	from.size = Vector2(300, 28)
	add_child(from)

func _pill(pos: Vector2, size: Vector2, text: String, fill: Color, tcol: Color) -> void:
	panel(self, pos + Vector2(2, 4), size, st(Color(0, 0, 0, 0.25), int(size.y / 2), Color.TRANSPARENT, 0))
	var b := panel(self, pos, size, st(fill, int(size.y / 2), Color(1, 1, 1, 0.75), 2))
	panel(b, Vector2(4, 3), Vector2(size.x - 8, size.y * 0.42), st(Color(1, 1, 1, 0.28), int(size.y * 0.21), Color.TRANSPARENT, 0))
	var t := lb(text, 26, tcol, true, HORIZONTAL_ALIGNMENT_CENTER)
	t.position = Vector2(0, size.y * 0.26)
	t.size = Vector2(size.x, 36)
	b.add_child(t)

func _own() -> void:
	var c: Dictionary = _char(1)
	panel(self, Vector2(45, 684), Vector2(292, 372), st(Color(0, 0, 0, 0.3), 22, Color.TRANSPARENT, 0))
	var card := panel(self, Vector2(40, 676), Vector2(292, 372), st(T["frame"], 22, Color(1, 1, 1, 0.85), 2, true))
	panel(card, Vector2(5, 5), Vector2(282, 362), st(Color.WHITE, 18, Color.TRANSPARENT, 0))
	portrait_in(card, load(String(c["portrait"])), Vector2(7, 7), Vector2(278, 358))
	var plate := panel(card, Vector2(-8, 292), Vector2(250, 56), st(T["plate"], 10, Color(1, 1, 1, 0.8), 2, true))
	plate.rotation = -0.02
	var nm := lb("柚木铃奈 · 忠臣", 27, Color.WHITE, true)
	nm.position = Vector2(10, 10)
	plate.add_child(nm)
	var hp := lb("♥♥♥♡", 34, Color("ff5c7a"), true)
	hp.position = Vector2(16, 330)
	hp.add_theme_constant_override("outline_size", 5)
	hp.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	card.add_child(hp)
	var eqs := ["🗡 破甲光剑", "🛡 结界手环", "👢 疾行之靴"]
	for i in 3:
		var chip := panel(self, Vector2(356 + i * 168, 986), Vector2(158, 44), st(T["chip"], 10, Color(1, 1, 1, 0.45), 1))
		var et := lb(eqs[i], 20, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
		et.position = Vector2(0, 9)
		et.size = Vector2(158, 28)
		chip.add_child(et)
	_pill(Vector2(1246, 756), Vector2(230, 64), "✦ 风纪", T["accent"], Color.WHITE)
	_pill(Vector2(1246, 838), Vector2(230, 64), "✦ 铃护", T["accent"], Color.WHITE)
	_pill(Vector2(1246, 928), Vector2(230, 72), "结束出牌", T["frame"], Color("40222e") if not T["dark"] else Color("2a1608"))

func _hand() -> void:
	var data := [["♠", "8", "突击", "基本牌"], ["♥", "2", "闪避", "基本牌"], ["♦", "5", "补给", "基本牌"], ["♣", "3", "悄悄借走", "锦囊牌"], ["♥", "9", "特饮", "基本牌"]]
	for i in 5:
		var d: Array = data[i]
		_game_card(self, Vector2(368 + i * 128, 730 + (6 if i % 2 == 0 else 0)), Vector2(176, 244), d[0], d[1], d[2], d[3], deg_to_rad(-2.5 + i * 1.3))

func _log() -> void:
	var lp := panel(self, Vector2(1506, 742), Vector2(374, 258), st(T["glass"], 18, T["frame2"], 2, true))
	panel(lp, Vector2(0, 14), Vector2(6, 40), st(T["accent"], 3, Color.TRANSPARENT, 0))
	var h := lb("战报 LOG", 22, T["accent"], true)
	h.position = Vector2(18, 16)
	lp.add_child(h)
	var t := lb("夜宫静羽 对 森崎千夏 使用「突击」。
森崎千夏 打出「闪避」。
花宫雏 使用「补给」回复 1 点。
藤代小梅 发动【侍奉】。", 21, T["ink"])
	t.position = Vector2(18, 58)
	t.size = Vector2(340, 190)
	lp.add_child(t)

