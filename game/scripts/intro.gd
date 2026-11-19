class_name IntroPop
extends CanvasLayer
const CardDefs = preload("res://data/cards.gd")
const Art = preload("res://scripts/art.gd")
const Palette = preload("res://scripts/ui_palette.gd")

# V0.26 长按说明卡（对照无名杀 longpress + get.nodeintro）
# - 长按（约 0.4 秒）任意带 meta "intro" 的控件弹出说明卡；松手关闭。
# - 桌面端：右键弹出（点任意处关闭）；鼠标悬停 0.7 秒弹出（移开关闭）。
# - 长按触发后注入一次「界外松开」事件，让被按住的按钮放弃本次点击（长按不出牌/不选择）；拖动超过阈值则取消长按。
# - meta "intro" 可以是 Dictionary（规格）或 Callable（触发时调用，返回规格），规格见 card_spec/char_spec/skill_spec。
# - 弹窗节点全局唯一、反复复用；弹窗本身全部 MOUSE_FILTER_IGNORE，不挡操作。

const LONGPRESS_SEC := 0.4
const HOVER_SEC := 0.7
const MOVE_CANCEL_PX := 14.0
const FAKE_POS := Vector2(-30000, -30000)

static var inst: IntroPop = null

var font_reg: Font
var font_bold: Font
var panel: PanelContainer
var face: Panel
var face_suit: Label
var face_name: Label
var face_art: TextureRect
var face_sb: StyleBoxFlat
var portrait: Control  # V0.31：角色说明卡左侧改为 CG 卡面（按角色重建）
var title_l: Label
var sub_l: Label
var body: RichTextLabel
var scroll: ScrollContainer

var mode := ""            # "" / hold / sticky / hover
var lp_token := 0
var lp_pos := Vector2.ZERO
var lp_pending := false
var lp_fired := false
var hover_token := 0
var hover_pos := Vector2.ZERO
var hover_rect := Rect2()
var injecting := false
var shown_count := 0      # 自测用：累计弹出次数
var last_spec: Dictionary = {}
var enable_hover := true
var hover_timer: Timer


func _ready() -> void:
	inst = self
	layer = 90
	font_reg = load("res://assets/fonts/NotoSansSC-Regular.otf")
	font_bold = load("res://assets/fonts/NotoSansSC-Bold.otf")
	enable_hover = not OS.has_feature("mobile")
	hover_timer = Timer.new()
	hover_timer.one_shot = true
	hover_timer.timeout.connect(func() -> void: _hover_fire(hover_token))
	add_child(hover_timer)
	_build()


func _exit_tree() -> void:
	if inst == self:
		inst = null


static func _sb(color: Color, radius: int, border: Color = Color(0, 0, 0, 0), bw: int = 0, shadow: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	if shadow:
		s.shadow_color = Palette.SHADOW
		s.shadow_size = 16
		s.shadow_offset = Vector2(0, 6)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 20
	s.content_margin_bottom = 22
	return s


func _mk_label(size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font_bold if bold else font_reg)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build() -> void:
	panel = PanelContainer.new()
	panel.name = "IntroPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _sb(Palette.MILK, 22, Palette.LILAC_EDGE, 2, true))
	panel.visible = false
	add_child(panel)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 22)
	panel.add_child(hb)
	# 左：牌面（卡牌）或立绘（角色）
	face = Panel.new()
	face.custom_minimum_size = Vector2(150, 210)
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face_sb = _sb(Palette.LILAC_SOFT, 14, Palette.LILAC_EDGE, 2)
	face.add_theme_stylebox_override("panel", face_sb)
	hb.add_child(face)
	# V0.29：长按牌说明卡左侧显示原创卡图（与手牌同一套样式）
	face_art = TextureRect.new()
	face_art.position = Vector2(5, 5)
	face_art.size = Vector2(140, 150)
	face_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(face_art)
	var chip := Panel.new()
	chip.position = Vector2(8, 8)
	chip.size = Vector2(66, 40)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", _sb(Color(Palette.MILK, 0.96), 10, Palette.ROSE_EDGE, 1))
	face.add_child(chip)
	face_suit = _mk_label(28, Palette.ROSE_PRIMARY, true)
	face_suit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face_suit.position = Vector2(0, -1)
	face_suit.size = Vector2(66, 40)
	face_suit.autowrap_mode = TextServer.AUTOWRAP_OFF
	chip.add_child(face_suit)
	face_name = _mk_label(24, Palette.INK, true)
	face_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	face_name.position = Vector2(4, 158)
	face_name.size = Vector2(142, 48)
	face_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	face_name.clip_text = true
	face.add_child(face_name)
	portrait = Control.new()
	portrait.name = "IntroCG"
	portrait.custom_minimum_size = Vector2(250, 330)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(portrait)
	# 右：标题 / 副标题 / 正文
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	hb.add_child(vb)
	title_l = _mk_label(40, Palette.INK, true)
	vb.add_child(title_l)
	sub_l = _mk_label(23, Palette.MUTED, false)
	vb.add_child(sub_l)
	var sep := ColorRect.new()
	sep.color = Palette.LILAC_EDGE
	sep.custom_minimum_size = Vector2(0, 2)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sep)
	scroll = ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	vb.add_child(scroll)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_override("normal_font", font_reg)
	body.add_theme_font_override("bold_font", font_bold)
	body.add_theme_font_size_override("normal_font_size", 25)
	body.add_theme_font_size_override("bold_font_size", 25)
	body.add_theme_color_override("default_color", Palette.INK)
	body.add_theme_constant_override("line_separation", 6)
	scroll.add_child(body)


# ================= 输入：长按 / 右键 / 悬停 =================

func _vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _input(event: InputEvent) -> void:
	if injecting:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.position == FAKE_POS:
			return
		if mb.pressed:
			hover_token += 1
			hover_timer.stop()
			if mode == "sticky" or mode == "hover":
				var was := mode
				hide_pop()
				if was == "sticky":
					# 右键弹出的说明卡：点任意处只关闭，不触发下面的按钮
					get_viewport().set_input_as_handled()
					return
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				if open_at(mb.position, "sticky"):
					get_viewport().set_input_as_handled()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_lp_start(mb.position)
		else:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				lp_pending = false
				lp_token += 1
				if lp_fired:
					lp_fired = false
					if mode == "hold":
						hide_pop()
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if lp_pending and mm.position.distance_to(lp_pos) > MOVE_CANCEL_PX:
			cancel_longpress()
		if mm.button_mask == 0 and enable_hover:
			if mode == "hover" and not hover_rect.grow(6).has_point(mm.position):
				hide_pop()
			if mode == "" and mm.position.distance_to(hover_pos) > 6.0:
				hover_pos = mm.position
				hover_token += 1
				hover_timer.start(HOVER_SEC)  # 单个 Timer 反复重启，不随鼠标移动创建新计时器


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		cancel_longpress()
		if mode == "hold":
			hide_pop()


func _lp_start(pos: Vector2) -> void:
	lp_token += 1
	lp_pos = pos
	lp_pending = true
	lp_fired = false
	var tok := lp_token
	get_tree().create_timer(LONGPRESS_SEC, true, false, true).timeout.connect(func() -> void: _lp_fire(tok))


func cancel_longpress() -> void:
	lp_pending = false
	lp_token += 1


# 长按只占用触发说明的这次按压。原松手在 _input 中拦截，下一次点按可以立即开始。
func swallowing() -> bool:
	return lp_fired


func _lp_fire(tok: int) -> void:
	if tok != lp_token or not lp_pending:
		return
	lp_pending = false
	var target := find_target(lp_pos)
	if target == null:
		return
	var spec := spec_of(target)
	if spec.is_empty():
		return
	lp_fired = true
	_cancel_press()
	show_spec(spec, lp_pos, "hold")


func _hover_fire(tok: int) -> void:
	if tok != hover_token or mode != "" or not enable_hover:
		return
	if Input.get_mouse_button_mask() != 0:
		return
	var target := find_target(hover_pos)
	if target == null:
		return
	var spec := spec_of(target)
	if spec.is_empty():
		return
	hover_rect = target.get_global_rect()
	show_spec(spec, hover_pos, "hover")


# 让当前按住的控件收到一次「界外松开」：按钮不会发出 pressed，拖拽状态被清掉，鼠标焦点被释放
func _cancel_press() -> void:
	# 先把指针「移出」：BaseButton 在按住期间靠移动事件更新 pressing_inside，松开时只看这个标志决定是否发出 pressed
	var mv := InputEventMouseMotion.new()
	mv.position = FAKE_POS
	mv.global_position = FAKE_POS
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	injecting = true
	get_viewport().push_input(mv)
	injecting = false
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = FAKE_POS
	ev.global_position = FAKE_POS
	injecting = true
	get_viewport().push_input(ev)
	injecting = false


func open_at(pos: Vector2, how: String) -> bool:
	var target := find_target(pos)
	if target == null:
		return false
	var spec := spec_of(target)
	if spec.is_empty():
		return false
	show_spec(spec, pos, how)
	return true


static func spec_of(target: Control) -> Dictionary:
	if target == null or not is_instance_valid(target) or not target.has_meta("intro"):
		return {}
	var m: Variant = target.get_meta("intro")
	if m is Callable:
		if not (m as Callable).is_valid():
			return {}
		var r: Variant = (m as Callable).call()
		return r if r is Dictionary else {}
	return m if m is Dictionary else {}


# ================= 命中测试 =================
# 按绘制顺序找指针下最上层的控件：
# - 会接收鼠标的控件（STOP/PASS）照常参与命中；若它自己或祖先带 intro 则取之，否则视为被遮挡（返回 null）；
# - 带 intro 但 MOUSE_FILTER_IGNORE 的控件（装备栏、判定标记、处理区的牌）也参与命中。
var _best: Control = null
var _best_key: Array = []
var _dfs := 0


func find_target(pos: Vector2) -> Control:
	_best = null
	_best_key = []
	_dfs = 0
	_walk(get_tree().root, pos, 0, 0, Rect2(-1e7, -1e7, 2e7, 2e7))
	if _best == null:
		return null
	var n: Node = _best
	while n != null:
		if n is Control and n.has_meta("intro"):
			return n as Control
		n = n.get_parent()
	return null


func _walk(n: Node, pos: Vector2, lay: int, z: int, clip: Rect2) -> void:
	if n == self:
		return
	var my_lay := lay
	var my_z := z
	var my_clip := clip
	if n is CanvasLayer:
		if not (n as CanvasLayer).visible:
			return
		my_lay = (n as CanvasLayer).layer
		my_z = 0
		my_clip = Rect2(-1e7, -1e7, 2e7, 2e7)
	elif n is CanvasItem:
		var ci := n as CanvasItem
		if not ci.visible:
			return
		my_z = ci.z_index + (z if ci.z_as_relative else 0)
	if n is Control:
		var c := n as Control
		_dfs += 1
		var r := c.get_global_rect()
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE or c.has_meta("intro"):
			if r.has_point(pos) and my_clip.has_point(pos) and c.size.x > 0.0 and c.size.y > 0.0:
				var key: Array = [my_lay, my_z, _dfs]
				if _best == null or _key_gt(key, _best_key):
					_best = c
					_best_key = key
		if c.clip_contents:
			my_clip = my_clip.intersection(r)
	for ch in n.get_children():
		_walk(ch, pos, my_lay, my_z, my_clip)


static func _key_gt(a: Array, b: Array) -> bool:
	for i in a.size():
		if int(a[i]) != int(b[i]):
			return int(a[i]) > int(b[i])
	return false


# ================= 显示 =================

func show_spec(spec: Dictionary, at: Vector2, how: String) -> void:
	last_spec = spec
	shown_count += 1
	mode = how
	var kind := String(spec.get("kind", ""))
	var vs := _vp_size()
	var w := float(spec.get("w", 820.0 if kind == "card" else 1040.0))
	w = minf(w, vs.x - 40.0)
	face.visible = kind == "card"
	var ptex := String(spec.get("portrait", ""))
	portrait.visible = ptex != "" and kind != "card"
	if portrait.visible and String(portrait.get_meta("ptex", "")) != ptex:
		portrait.set_meta("ptex", ptex)
		for old in portrait.get_children():
			portrait.remove_child(old)
			old.queue_free()
		var cd: Dictionary = Characters.by_id(String(spec.get("char_id", "")))
		if cd.is_empty():
			cd = {"portrait": ptex, "name": String(spec.get("title", "")), "hp": 3}
		portrait.add_child(Art.cg_card(cd, Vector2(250, 330), {"zoom": 0.8, "face_y": 0.30, "fs": 30, "title": false}))
	if face.visible:
		face_suit.text = String(spec.get("face_suit", ""))
		face_suit.add_theme_color_override("font_color", spec.get("face_color", Palette.INK))
		face_name.text = String(spec.get("title", ""))
		face_art.texture = Art.card_tex(String(spec.get("title", "")))
		var fc := Art.frame_color(String(spec.get("title", "")))
		face_sb.bg_color = Palette.MILK.lerp(fc, 0.13)
		face_sb.border_color = Palette.LILAC_EDGE.lerp(fc, 0.24)
	title_l.text = String(spec.get("title", ""))
	sub_l.text = String(spec.get("sub", ""))
	sub_l.visible = sub_l.text != ""
	_set_body_font(25)
	body.text = _paper_bbcode(String(spec.get("body", "")))
	var side := 150.0 if face.visible else (250.0 if portrait.visible else 0.0)
	var text_w := w - 52.0 - (side + 22.0 if side > 0.0 else 0.0)
	body.custom_minimum_size = Vector2(text_w, 0)
	title_l.custom_minimum_size = Vector2(text_w, 0)
	sub_l.custom_minimum_size = Vector2(text_w, 0)
	title_l.size.x = text_w
	sub_l.size.x = text_w
	scroll.custom_minimum_size = Vector2(text_w, 0)
	panel.size = Vector2(w, 0)
	panel.custom_minimum_size = Vector2(w, 0)
	body.size = Vector2(text_w, body.size.y)
	panel.visible = true
	_fit(at, vs)
	_refit.call_deferred(at)


func _refit(at: Vector2) -> void:
	if panel.visible:
		_fit(at, _vp_size())


func _fit(at: Vector2, vs: Vector2) -> void:
	# 正文过长时限高并允许滚动；整卡夹在屏幕内（16:9 / 20:9 / 4:3 均不出界）
	var max_h := vs.y - 40.0
	var head_h := title_l.get_minimum_size().y + (sub_l.get_minimum_size().y if sub_l.visible else 0.0) + 30.0
	var body_h := body.get_content_height()
	if body_h <= 0.0:
		body_h = body.get_minimum_size().y
	var avail := max_h - head_h - 42.0
	if body_h > avail and body.get_theme_font_size("normal_font_size") > 21:
		# 内容太长（如角色卡带多件装备）：先缩小字号，仍放不下再限高
		_set_body_font(21)
		body_h = body.get_content_height()
	scroll.custom_minimum_size.y = minf(body_h, avail)
	var side_h := 210.0 if face.visible else (330.0 if portrait.visible else 0.0)
	var h := maxf(head_h + scroll.custom_minimum_size.y + 42.0, side_h + 42.0)
	panel.size = Vector2(panel.custom_minimum_size.x, h)
	var p := at + Vector2(28, -h * 0.5)
	if p.x + panel.size.x > vs.x - 20.0:
		p.x = at.x - 28.0 - panel.size.x
	p.x = clampf(p.x, 20.0, maxf(20.0, vs.x - 20.0 - panel.size.x))
	p.y = clampf(p.y, 20.0, maxf(20.0, vs.y - 20.0 - h))
	panel.position = p


func hide_pop() -> void:
	mode = ""
	if panel != null:
		panel.visible = false


func is_open() -> bool:
	return panel != null and panel.visible


func pop_rect() -> Rect2:
	return Rect2(panel.position, panel.size)


# ================= 规格构造 =================

const SUIT_SYM := {"红桃": "♥", "方块": "♦", "梅花": "♣", "黑桃": "♠"}
const KW_TERMS := ["锁定技", "限定技", "觉醒技", "出牌阶段", "摸牌阶段", "判定阶段", "弃牌阶段", "准备阶段", "结束阶段", "回合开始", "回合结束", "攻击范围", "距离", "濒死", "判定", "连环状态", "横置", "重置", "重铸"]
const KW_HURT := ["火焰伤害", "雷电伤害", "伤害", "失去体力", "弃置"]
const KW_GOOD := ["回复", "摸两张牌", "摸一张牌", "摸牌", "获得"]
const KW_CARDS := ["突击", "闪避", "补给", "特饮"]
const RULE_NAME := "#a43e6b"
const RULE_TIMING := "#4c6387"
const RULE_HARM := "#a04161"
const RULE_GAIN := "#346b5c"
const RULE_VARIANT := "#87551c"
const RULE_SECTION := "#665389"

# 对局追加的装备、判定和计数行仍可使用原来的亮色标记。
const LEGACY_PAPER_INK := {
	"#ffd27a": RULE_NAME,
	"#8fd3ff": RULE_TIMING,
	"#ff8a8a": RULE_HARM,
	"#9df0a8": RULE_GAIN,
	"#c9b8e8": RULE_SECTION,
}


static func _paper_bbcode(text: String) -> String:
	for old_color in LEGACY_PAPER_INK:
		text = text.replace("[color=%s]" % old_color, "[color=%s]" % LEGACY_PAPER_INK[old_color])
	return text


static func esc(t: String) -> String:
	return t.replace("[", "[lb]")


# 深玫瑰显示牌名和技能名，规则阶段、伤害、收益分别使用蓝、红、绿字。
static func highlight(text: String) -> String:
	var t := esc(text)
	var re := RegEx.new()
	var alts: Array = ["【[^】]+】", "「[^」]+」"]
	for arr in [KW_TERMS, KW_HURT, KW_GOOD, KW_CARDS]:
		for k in arr:
			alts.append(String(k))
	re.compile("|".join(PackedStringArray(alts)))
	var out := ""
	var last := 0
	for m in re.search_all(t):
		out += t.substr(last, m.get_start() - last)
		var s := m.get_string()
		var col := RULE_NAME
		if KW_TERMS.has(s):
			col = RULE_TIMING
		elif KW_HURT.has(s):
			col = RULE_HARM
		elif KW_GOOD.has(s):
			col = RULE_GAIN
		out += "[color=%s][b]%s[/b][/color]" % [col, s]
		last = m.get_end()
	out += t.substr(last)
	return out


static func card_desc_bb(c: Dictionary, with_type: bool = false) -> String:
	var nm := String(c.get("name", ""))
	var lines: Array = []
	if with_type:
		lines.append("[color=%s]%s[/color]" % [RULE_SECTION, CardDefs.type_label_of(nm)])
	var tx := CardDefs.text_of(nm)
	lines.append(highlight(tx if tx != "" else "（暂无说明）"))
	if CardDefs.kind_of(nm) == "武器":
		lines.append("[color=%s][b]攻击范围：%d[/b][/color]" % [RULE_TIMING, CardDefs.weapon_range_of(nm)])
	var yb: Array = c.get("yb", [])
	if yb.size() >= 2:
		lines.append("[color=%s][b]%s[/b][/color]" % [RULE_VARIANT, esc(CardDefs.yingbian_text(yb))])
	return "\n".join(PackedStringArray(lines))


static func card_spec(c: Dictionary) -> Dictionary:
	var nm := String(c.get("name", ""))
	var suit := String(c.get("suit", ""))
	var sym := String(SUIT_SYM.get(suit, ""))
	var pt := int(c.get("point", 0))
	var pts := {1: "A", 11: "J", 12: "Q", 13: "K"}
	var pstr := String(pts.get(pt, str(pt))) if pt > 0 else ""
	var red := suit == "红桃" or suit == "方块"
	var sub_parts: Array = []
	if sym != "":
		sub_parts.append("%s%s %s" % [suit, "", pstr])
	sub_parts.append(CardDefs.type_label_of(nm))
	var nat := String(c.get("nature", ""))
	if nat != "":
		sub_parts.append(String(CardDefs.NATURE_TEXT.get(nat, nat)))
	return {
		"kind": "card", "title": nm, "sub": " · ".join(PackedStringArray(sub_parts)),
		"body": card_desc_bb(c), "face_suit": "%s%s" % [sym, pstr],
		"face_color": Palette.ROSE_PRIMARY if red else Palette.INK,
	}


static func timing_label(timing: String, who: String = "") -> String:
	match timing:
		"phaseZhunbeiStart":
			return "准备阶段开始时"
		"phaseJieshuStart":
			return "结束阶段开始时"
		"phaseJieshu":
			return "结束阶段"
		"damageBefore", "damageAfter":
			var subject: String = {"player": "你受到", "source": "你造成", "global": "场上有角色受到"}.get(who, "")
			var stage := "前" if timing == "damageBefore" else "后"
			return "伤害结算%s" % stage if subject == "" else "%s伤害%s" % [subject, stage]
		"useCardBegin":
			return "你成为牌的目标时" if who == "target" else ("你使用牌时" if who == "source" else "使用牌时")
		"attackDodged":
			return "你的突击被闪避后" if who == "source" else "突击被闪避后"
	return ""


static func _skill_row(label: String, text: String) -> String:
	return "[color=%s][b]%s[/b][/color]  %s" % [RULE_SECTION, label, highlight(text)]


static func skill_spec(nm: String, text: String, active: bool, extra: String = "", definition: Dictionary = {}, selection: Dictionary = {}) -> Dictionary:
	var rows: Array[String] = []
	var types: Array[String] = ["主动技" if active else "被动技"]
	for flag in ["locked", "limited", "awaken", "switchable"]:
		if bool(definition.get(flag, false)):
			types.append({"locked": "锁定技", "limited": "限定技", "awaken": "觉醒技", "switchable": "转换技"}[flag])
	var summary: Dictionary = definition.get("summary", {})
	var timings: Array[String] = []
	if active:
		timings.append("你的出牌阶段")
	var triggers: Dictionary = definition.get("timings", {})
	for timing in triggers:
		var visible_timing := timing_label(String(timing), String(triggers[timing].get("who", "player")))
		if visible_timing != "" and not timings.has(visible_timing):
			timings.append(visible_timing)
	if not timings.is_empty():
		rows.append(_skill_row("时机", "、".join(timings)))
	if summary.has("condition"):
		rows.append(_skill_row("条件", String(summary["condition"])))
	var cost := String(summary.get("cost", ""))
	if cost == "":
		var card_type := String(selection.get("card", "none"))
		var card_amount: String = {"any": "1 张手牌", "red": "1 张红色手牌", "black": "1 张黑色手牌"}.get(card_type, "")
		if card_amount != "":
			cost = "%s（%s）" % [card_amount, String(selection.get("card_role", "作为代价"))]
	if cost != "":
		rows.append(_skill_row("代价", cost))
	var times := String(summary.get("limit", ""))
	if times == "" and not definition.is_empty():
		if bool(definition.get("limited", false)) or bool(definition.get("awaken", false)):
			times = "整局限 1 次"
		elif active:
			times = "每个出牌阶段限 1 次"
	if extra != "":
		times = "%s · %s" % [times, extra] if times != "" else extra
	if times != "":
		rows.append(_skill_row("次数", times))
	rows.append(_skill_row("效果与规则", text if text != "" else "暂无技能说明。"))
	return {"kind": "skill", "title": nm, "sub": " · ".join(types), "body": "\n\n".join(rows), "w": 820.0}


# 角色说明卡（图鉴/选将用：只有静态资料）；rt 为对局中的动态信息（BBCode 行，可空）
static func char_spec(cd: Dictionary, rt: Dictionary = {}) -> Dictionary:
	var lines: Array = []
	var head: Array = []
	var hp := int(cd.get("hp", 0))
	if rt.has("hp_line"):
		head.append(String(rt["hp_line"]))
	else:
		head.append("体力 %d" % hp)
	head.append("系列 · %s" % String(cd.get("work", "")))
	if rt.has("ident"):
		head.append(String(rt["ident"]))
	if rt.has("stats"):
		lines.append("[color=%s]%s[/color]" % [RULE_TIMING, esc(String(rt["stats"]))])
	var used: Dictionary = rt.get("used", {})
	var skills: Array = rt.get("skills", cd.get("skills", []))
	for sk in skills:
		var snm := String(sk.get("name", ""))
		var active: bool = sk.has("btn") or bool(sk.get("active", false))
		var tag := "[color=%s]〔主动〕[/color]" % RULE_NAME if active else "[color=%s]〔被动〕[/color]" % RULE_SECTION
		var n_used := int(used.get(snm, 0))
		var utag := ""
		if rt.has("used"):
			utag = " [color=%s]（本局已发动 %d 次）[/color]" % [RULE_GAIN, n_used] if n_used > 0 else " [color=#625774]（本局未发动）[/color]"
		lines.append("%s [color=%s][b]【%s】[/b][/color]%s\n%s" % [tag, RULE_NAME, esc(snm), utag, highlight(String(sk.get("text", "")))])
	if rt.has("equips"):
		lines.append(String(rt["equips"]))
	if rt.has("judges"):
		lines.append(String(rt["judges"]))
	if not rt.has("stats") and cd.has("intro"):
		lines.append("[color=#625774]%s[/color]" % esc(String(cd["intro"])))
	return {"kind": "char", "title": String(cd.get("name", "")), "sub": "  ·  ".join(PackedStringArray(head)), "portrait": String(cd.get("portrait", "")), "char_id": String(cd.get("id", "")), "body": "\n".join(PackedStringArray(lines)), "w": 1120.0}


func _set_body_font(px: int) -> void:
	body.add_theme_font_size_override("normal_font_size", px)
	body.add_theme_font_size_override("bold_font_size", px)
