extends Control

# UI 风格样本渲染器（开发用）：同一张对局桌面的三种配色/质感方向
var T: Dictionary = {}

func th() -> Dictionary:
	return {
		"A": {"bg_top": Color("ffd9e8"), "bg_bot": Color("cfe2ff"), "panel": Color(1, 1, 1, 0.9), "border": Color("ff7ba9"), "accent": Color("ff5c8a"), "accent2": Color("e8a33d"), "ink": Color("4a2b3a"), "soft": Color("8a5a6e"), "card": Color("fff7fa"), "dark": false, "radius": 24, "shadow": true, "deco": "petal"},
		"B": {"bg_top": Color("a8d8ff"), "bg_bot": Color("f2faff"), "panel": Color(1, 1, 1, 0.96), "border": Color("6fb7f2"), "accent": Color("1f8ef5"), "accent2": Color("ffb340"), "ink": Color("22344a"), "soft": Color("5d7a94"), "card": Color("ffffff"), "dark": false, "radius": 16, "shadow": false, "deco": "cloud"},
		"C": {"bg_top": Color("1d1440"), "bg_bot": Color("57205e"), "panel": Color(0.13, 0.1, 0.24, 0.92), "border": Color("ff6ec7"), "accent": Color("ff5da2"), "accent2": Color("ffd76a"), "ink": Color("ffedf7"), "soft": Color("c9a8d8"), "card": Color(0.16, 0.12, 0.3, 0.97), "dark": true, "radius": 20, "shadow": true, "deco": "star"},
	}

var font_reg: Font
var font_bold: Font

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
		s.shadow_color = Color(0, 0, 0, 0.25)
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
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

func build(theme_key: String) -> void:
	var all: Dictionary = th()
	T = all[theme_key]
	font_reg = load("res://assets/fonts/NotoSansSC-Regular.otf")
	font_bold = load("res://assets/fonts/NotoSansSC-Bold.otf")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, T["bg_top"])
	gr.set_color(1, T["bg_bot"])
	gt.gradient = gr
	gt.fill_from = Vector2(0.5, 0)
	gt.fill_to = Vector2(0.5, 1)
	gt.width = 1920
	gt.height = 1080
	var bg := TextureRect.new()
	bg.texture = gt
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	_deco()
	_topbar()
	var chars := [1, 2, 3, 4]
	var seats := [Vector2(56, 300), Vector2(430, 128), Vector2(1240, 128), Vector2(1614, 300)]
	for i in 4:
		_seat_card(seats[i], int(chars[i]), i == 1)
	_center()
	_own_area()
	_log_panel()

func _deco() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var kind: String = T["deco"]
	for i in 26:
		var x := rng.randf_range(0, 1900)
		var y := rng.randf_range(0, 1060)
		if kind == "petal":
			var p := Panel.new()
			var s := rng.randf_range(10, 22)
			p.size = Vector2(s, s * 0.7)
			p.position = Vector2(x, y)
			p.rotation = rng.randf_range(0, 3.0)
			p.add_theme_stylebox_override("panel", st(Color(1, 0.62, 0.78, rng.randf_range(0.15, 0.4)), 8, Color.TRANSPARENT, 0))
			p.mouse_filter = MOUSE_FILTER_IGNORE
			add_child(p)
		elif kind == "cloud":
			var p2 := Panel.new()
			p2.size = Vector2(rng.randf_range(90, 190), rng.randf_range(26, 44))
			p2.position = Vector2(x, y)
			p2.add_theme_stylebox_override("panel", st(Color(1, 1, 1, 0.5), 22, Color.TRANSPARENT, 0))
			p2.mouse_filter = MOUSE_FILTER_IGNORE
			add_child(p2)
		else:
			var star := lb("✦", int(rng.randf_range(13, 30)), Color(1, 0.9, 0.6, rng.randf_range(0.35, 0.9)))
			star.position = Vector2(x, y)
			add_child(star)

func _topbar() -> void:
	var logo := lb("全明星杀", 54, T["accent"], true)
	logo.position = Vector2(48, 26)
	add_child(logo)
	var sub := lb("5 人身份场 · 第 2 轮", 24, T["soft"])
	sub.position = Vector2(52, 96)
	add_child(sub)
	var phase := lb("出牌阶段 · 柚木铃奈", 32, T["ink"], true, HORIZONTAL_ALIGNMENT_CENTER)
	phase.position = Vector2(660, 34)
	phase.size = Vector2(600, 44)
	add_child(phase)
	var deck := lb("牌堆 62 · 弃牌 9", 24, T["soft"], false, HORIZONTAL_ALIGNMENT_RIGHT)
	deck.position = Vector2(1560, 40)
	deck.size = Vector2(320, 34)
	add_child(deck)

func _portrait(idx: int) -> Texture2D:
	var list: Array = []
	var chars = load("res://data/characters.gd")
	for c in chars.LIST:
		list.append(c)
	return load(String(list[idx]["portrait"]))

func _char_name(idx: int) -> String:
	var chars = load("res://data/characters.gd")
	return String(chars.LIST[idx]["name"])

func _seat_card(pos: Vector2, cidx: int, active: bool) -> void:
	var card := Panel.new()
	card.position = pos
	card.size = Vector2(250, 372)
	var bw := 5 if active else 2
	var bc: Color = T["accent2"] if active else T["border"]
	card.add_theme_stylebox_override("panel", st(T["panel"], int(T["radius"]), bc, bw, bool(T["shadow"])))
	add_child(card)
	var tr := TextureRect.new()
	tr.texture = _portrait(cidx)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(tr)
	tr.position = Vector2(6, 6)
	tr.size = Vector2(238, 360)
	var strip := Panel.new()
	strip.size = Vector2(238, 64)
	strip.position = Vector2(6, 302)
	strip.add_theme_stylebox_override("panel", st(Color(0, 0, 0, 0.42) if not T["dark"] else Color(0, 0, 0, 0.5), 0, Color.TRANSPARENT, 0))
	strip.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(strip)
	var nm := lb(_char_name(cidx), 27, Color.WHITE, true)
	nm.position = Vector2(14, 318)
	card.add_child(nm)
	var badge := Panel.new()
	badge.size = Vector2(46, 46)
	badge.position = Vector2(10, 10)
	badge.add_theme_stylebox_override("panel", st(T["accent"], 23, Color.WHITE, 2))
	badge.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(badge)
	var bt := lb("主" if cidx == 2 else "?", 24, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	bt.position = Vector2(10, 17)
	bt.size = Vector2(46, 32)
	card.add_child(bt)
	var hps := [4, 3, 4, 2]
	var mx := [4, 3, 4, 3]
	for i in int(mx[cidx % 4]):
		var dot := Panel.new()
		dot.size = Vector2(17, 17)
		dot.position = Vector2(222, 14 + i * 23)
		var full := i < int(hps[cidx % 4])
		dot.add_theme_stylebox_override("panel", st(Color(0.45, 0.85, 0.35) if full else Color(0.3, 0.3, 0.35, 0.4), 8, Color(1, 1, 1, 0.9), 1))
		dot.mouse_filter = MOUSE_FILTER_IGNORE
		card.add_child(dot)
	var hc := lb("手牌 %d" % [5, 3, 4, 2][cidx % 4], 21, Color.WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT)
	hc.position = Vector2(140, 322)
	hc.size = Vector2(96, 28)
	card.add_child(hc)
	if active:
		var glow := lb("▼ 行动中", 22, T["accent2"], true, HORIZONTAL_ALIGNMENT_CENTER)
		glow.position = Vector2(pos.x, pos.y - 34)
		glow.size = Vector2(250, 30)
		add_child(glow)

func _center() -> void:
	var banner := lb("— 柚木铃奈 的回合 —", 40, T["accent2"], true, HORIZONTAL_ALIGNMENT_CENTER)
	banner.position = Vector2(560, 560)
	banner.size = Vector2(800, 56)
	banner.add_theme_constant_override("outline_size", 8)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.25) if not T["dark"] else Color(0, 0, 0, 0.6))
	add_child(banner)
	var sc := Panel.new()
	sc.position = Vector2(862, 218)
	sc.size = Vector2(196, 268)
	sc.rotation = -0.03
	sc.add_theme_stylebox_override("panel", st(T["card"], 14, T["accent"], 3, true))
	add_child(sc)
	var vb := VBoxContainer.new()
	vb.position = Vector2(10, 10)
	vb.size = Vector2(176, 248)
	sc.add_child(vb)
	var top := lb("♥ 7", 26, Color("e14b5a"), true)
	vb.add_child(top)
	var big := lb("突击", 64, T["ink"], true, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(big)
	var who := lb("铃奈 → 千夏", 22, T["soft"], false, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(who)

func _own_area() -> void:
	var me := Panel.new()
	me.position = Vector2(40, 668)
	me.size = Vector2(292, 372)
	me.add_theme_stylebox_override("panel", st(T["panel"], int(T["radius"]), T["accent"], 3, bool(T["shadow"])))
	add_child(me)
	var tr := TextureRect.new()
	tr.texture = _portrait(1)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	me.add_child(tr)
	tr.position = Vector2(6, 6)
	tr.size = Vector2(280, 360)
	var strip := Panel.new()
	strip.size = Vector2(280, 88)
	strip.position = Vector2(6, 278)
	strip.add_theme_stylebox_override("panel", st(Color(0, 0, 0, 0.42), 0, Color.TRANSPARENT, 0))
	strip.mouse_filter = MOUSE_FILTER_IGNORE
	me.add_child(strip)
	var nm := lb("柚木铃奈 · 忠臣", 26, Color.WHITE, true)
	nm.position = Vector2(14, 288)
	me.add_child(nm)
	var hp := lb("♥♥♥♡ （3/4）", 24, Color(1, 0.75, 0.8), true)
	hp.position = Vector2(14, 326)
	me.add_child(hp)
	var names := ["突击", "闪避", "补给", "悄悄借走", "特饮"]
	var suits := ["♠ 8", "♥ 2", "♦ 5", "♣ 3", "♥ 9"]
	for i in 5:
		var c := Panel.new()
		c.position = Vector2(400 + i * 128, 742)
		c.size = Vector2(178, 252)
		c.rotation = deg_to_rad(-3 + i * 1.5)
		c.add_theme_stylebox_override("panel", st(T["card"], 12, T["border"], 2, bool(T["shadow"])))
		add_child(c)
		var s := lb(suits[i], 24, Color("e14b5a") if i % 2 == 1 else T["ink"], true)
		s.position = Vector2(12, 8)
		c.add_child(s)
		var n := lb(names[i], 30, T["ink"], true, HORIZONTAL_ALIGNMENT_CENTER)
		n.position = Vector2(0, 96)
		n.size = Vector2(178, 40)
		c.add_child(n)
	var sk := ["技能 · 风纪", "技能 · 铃护"]
	for i in 2:
		var b := Button.new()
		b.text = sk[i]
		b.position = Vector2(1130, 762 + i * 78)
		b.size = Vector2(240, 62)
		b.add_theme_font_size_override("font_size", 25)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", st(T["accent"], 31, Color.TRANSPARENT, 0))
		b.add_theme_stylebox_override("hover", st(T["accent"], 31, Color.TRANSPARENT, 0))
		b.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(b)
	var end := Button.new()
	end.text = "结束出牌"
	end.position = Vector2(1130, 934)
	end.size = Vector2(240, 76)
	end.add_theme_font_size_override("font_size", 30)
	end.add_theme_color_override("font_color", T["ink"])
	end.add_theme_stylebox_override("normal", st(T["panel"], 20, T["accent2"], 3))
	end.add_theme_stylebox_override("hover", st(T["panel"], 20, T["accent2"], 3))
	end.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(end)

func _log_panel() -> void:
	var lp := Panel.new()
	lp.position = Vector2(1420, 742)
	lp.size = Vector2(460, 298)
	lp.add_theme_stylebox_override("panel", st(T["panel"], int(T["radius"]), T["border"], 2, bool(T["shadow"])))
	add_child(lp)
	var t := lb("战报
夜宫静羽 对 森崎千夏 使用「突击」。
森崎千夏 打出「闪避」。
花宫雏 回复 1 点体力。", 22, T["ink"])
	t.position = Vector2(16, 12)
	lp.add_child(t)

