class_name BattleScreen
extends Control
const CardDefs = preload("res://data/cards.gd")
const EngineScript = preload("res://scripts/engine.gd")
const HelpText = preload("res://data/help.gd")
const Art = preload("res://scripts/art.gd")
const HP_FULL_TEX = preload("res://assets/ui/hp_petal.png")
const HP_EMPTY_TEX = preload("res://assets/ui/hp_petal_empty.png")

# 《全明星杀》V0.2 对战核心（单机 vs AI）
# 范围：5人身份场 / 选将 / 身份 / 距离 / 回合流程 / 濒死奖惩 / 胜负判定
# 牌堆：基本牌 + 8 种即时锦囊（延时锦囊与装备牌在后续版本加入）
# 角色技能：7 名角色的 14 个技能全部接入（见各技能函数）

signal decided(value)
signal end_play_pressed

const C_PINK := Color(1.0, 0.45, 0.65)
const C_PINK_DEEP := Color(0.92, 0.30, 0.52)
const C_PURPLE := Color(0.62, 0.55, 0.95)
const C_INK := Color(0.35, 0.25, 0.35)
const C_INK_SOFT := Color(0.55, 0.45, 0.55)
const C_WHITE := Color(1, 1, 1)
const C_RED := Color(0.85, 0.25, 0.35)
const C_BLACK := Color(0.30, 0.28, 0.38)
const C_GOLD := Color(0.91, 0.64, 0.24)
const C_PLATE := Color(1.0, 0.36, 0.54)
const C_INDIGO := Color(0.35, 0.32, 0.55)

var font_reg: Font
var font_bold: Font
var go_home: Callable

var players: Array = []
var eng = null # 新引擎实例（engine.gd）
var me_panel_ref: Control = null
var fx_root: Control = null
var turn_banner: Label = null
var turn_banner_tween: Tween = null
var last_turn_seat := -1
var sfx_players: Array = []
var sfx_streams: Dictionary = {}
var voice_player: AudioStreamPlayer = null
var sfx_count := 0  # 播放请求计数（测试用）
const AudioCfg = preload("res://scripts/audio.gd")
const Meta = preload("res://scripts/meta.gd")
var tutorial := false  # V0.30 教学关（脚本化单挑）
var ask_bar_fill: ColorRect = null
var ask_bar_bg_ref: Panel = null
var ask_bar_tween: Tween = null
var match_banner: Label = null
var match_banner_tween: Tween = null
var turn_seat: int = 0
var round_no: int = 1
var game_over: bool = false
var auto_all: bool = false # 全AI模拟模式（自测用）
var fast: bool = false
var interactive: bool = false # 是否处于真人出牌阶段
var pending_target_for: Dictionary = {} # {card=..., kind="attack"} 等待点选目标
var rng := RandomNumberGenerator.new()

# UI 节点
var turn_label: Label
var deck_label: Label
var disc_label: Label
var round_label: Label
var guess_marks := {}
var auto_mode := false
var auto_takeover := false
var concede_arm := false
var auto_btn: Button
var concede_btn: Button
var info_overlay: Panel
var info_title: Label
var info_text: RichTextLabel
var me_hp_label: Label
var me_chips: HBoxContainer
var seat_panels: Array = []
var log_label: Label
var prompt_label: Label
var prompt_btns: HBoxContainer
var hand_row: Control
var player_info: Label
var player_portrait: TextureRect
var skill_btns: VBoxContainer
var end_play_btn: Button
var log_lines: Array = []

const SUITS := ["红桃", "方块", "梅花", "黑桃"]
const RED_SUITS := ["红桃", "方块"]


func _ready() -> void:
	font_reg = load("res://assets/fonts/NotoSansSC-Regular.otf")
	font_bold = load("res://assets/fonts/NotoSansSC-Bold.otf")
	rng.randomize()
	auto_confirm = auto_confirm_saved()  # V0.27：「自动确认」默认关闭，设置持久化在 user://settings.cfg [play]


# V0.24 修复：对局中途「退出」回主页时，引擎协程还挂在「等待作答/结束出牌」上，整个引擎实例（牌堆、日志、技能表）
# 永远不会被释放（每退出一局泄漏一份）。离开场景树时令其判负收尾并放行所有等待，协程随之结束、引擎得以回收
func _exit_tree() -> void:
	if speed_idx != 0:
		Engine.time_scale = 1.0  # 倍速只作用于本局，离开对局恢复
		speed_idx = 0
	if eng == null:
		return
	if not eng.game_over:
		eng.game_over = true
		eng.winner_text = "中途退出"
	eng.ui = {}
	eng.turn_hook = Callable()
	decided.emit(null)
	end_play_pressed.emit()


func lbl(text: String, size: int, color: Color = C_INK, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold if bold else font_reg)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func style(color: Color, radius: int = 22, border: Color = Color(0, 0, 0, 0), bw: int = 0, shadow: bool = false) -> StyleBoxFlat:
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
		s.shadow_color = Color(0.85, 0.4, 0.55, 0.35)
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 5)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


func plain_btn(text: String, bg: Color = C_WHITE, fg: Color = C_PINK_DEEP, fsize: int = 28) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_reg)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_stylebox_override("normal", style(bg, 18, C_GOLD, 2))
	b.add_theme_stylebox_override("hover", style(bg.lightened(0.05), 18, C_PINK_DEEP, 2))
	b.add_theme_stylebox_override("pressed", style(bg.darkened(0.05), 18, C_PINK_DEEP, 2))
	b.add_theme_stylebox_override("disabled", style(Color(0.92, 0.90, 0.92), 18, Color(0.7, 0.68, 0.72), 2))
	b.pressed.connect(func() -> void: play_sfx("click"))
	return b


func wait(sec: float) -> void:
	if fast:
		await get_tree().process_frame
		return
	# 可被「点空白桌面」打断的等待：点击时刻晚于本次等待开始即提前结束（无名杀点击跳过动画停顿）
	var t0 := Time.get_ticks_msec()
	var tm := get_tree().create_timer(sec)
	while tm.time_left > 0.0:
		if skip_tap_ms >= t0:
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return


func _fx_click_through(n: Node) -> void:
	# 动画不挡操作：特效层/处理区里新加的任何节点（含 Panel 闪光、飞牌、横幅）一律点击穿透
	if n is Control:
		(n as Control).mouse_filter = MOUSE_FILTER_IGNORE
	for d in n.find_children("*", "Control", true, false):
		(d as Control).mouse_filter = MOUSE_FILTER_IGNORE


func cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	Engine.time_scale = float(SPEEDS[speed_idx])
	if speed_btn != null:
		speed_btn.text = "%sx" % str(SPEEDS[speed_idx])
	show_hint("对局速度：%sx（动画与 AI 出牌间隔同步加快，倒计时仍按真实秒数）" % str(SPEEDS[speed_idx]))


func _on_table_bg_input(event: InputEvent) -> void:
	# 点空白桌面：有选中的牌时取消选择（无名杀 ui.click.window），否则跳过当前等待
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if not pressed:
		return
	if guess_popup != null and guess_popup.visible:
		guess_popup.visible = false
		guess_popup_seat = -1
		return
	if settings_panel != null and settings_panel.visible:
		settings_panel.visible = false
		return
	# V0.27：选择中点空白桌面 = 取消（含技能选择、合璧长枪/木牛转运选目标）；询问中则清掉已选未确认的项
	if not asking and interactive and in_play_phase and (targeting or not selected_card.is_empty() or skill_mode != ""):
		_on_cancel_pressed()
		return
	if asking and ask_sel_has:
		_ask_clear_sel()
		return
	skip_tap_ms = Time.get_ticks_msec()


func log_msg(msg: String) -> void:
	log_lines.append(msg)
	while log_lines.size() > 5:
		log_lines.pop_front()
	if log_label:
		log_label.text = "\n".join(log_lines)


# ---------------- 界面骨架 ----------------

func set_my_role(r: String) -> void:
	my_role = r
	refresh_role_btns()


func refresh_role_btns() -> void:
	for rb in role_btns:
		var r := String(rb.get_meta("role"))
		rb.text = ("✓ 我当" if r == my_role else "我当") + r if game_mode == "doudizhu" else (("✓ 我" if r == my_role else "我") + r)


func show_setup() -> void:
	for ch in get_children():
		ch.queue_free()
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 48)
	m.add_theme_constant_override("margin_right", 48)
	m.add_theme_constant_override("margin_top", 36)
	m.add_theme_constant_override("margin_bottom", 36)
	add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	m.add_child(vb)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	var back := plain_btn("← 返回主页")
	back.custom_minimum_size = Vector2(220, 68)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: go_home.call())
	bar.add_child(back)
	var title_text := "5人身份场 · 和 AI 进行对战"
	var config_text := "身份配置：主公 1 人 · 忠臣 1 人 · 反贼 2 人 · 内奸 1 人（随机分配身份与座位，除主公外开局隐藏）"
	var seat_names := ["你（玩家）", "AI 玩家 1", "AI 玩家 2", "AI 玩家 3", "AI 玩家 4"]
	if game_mode == "doudizhu":
		title_text = "斗地主 · 3 人对战"
		config_text = "地主 1 人 · 农民 2 人（同队）｜全员起手 4 张，开局叫分（1~3 倍）决定地主：地主先手、补摸 1 张，自带技能「飞扬」「跋扈」与护身「地契」；含专属牌攻守兼备/进退自如/继往开来"
		seat_names = ["你（玩家）", "AI 玩家 1", "AI 玩家 2"]
	elif game_mode == "twovtwo":
		title_text = "欢乐 2v2 · 4 人同盟排位"
		config_text = "1·4号位【红方同盟】 vs 2·3号位【蓝方同盟】｜1号位先手首轮摸1张，4号位（你的队友）起手5张；队友手牌相互可见，队友阵亡时存活方摸1张牌"
		seat_names = ["1号位·你（红方）", "2号位·AI（蓝方）", "3号位·AI（蓝方）", "4号位·队友（红方）"]
	elif game_mode == "boss":
		title_text = "魔王挑战 · 3v1 联军讨伐（PVE）"
		config_text = "1·2·4号位【学园联军】联手迎战 3号位【8体力暴走大魔王】｜魔王自带锁定技「魔威」「星蚀」；联军手牌共享，任一联军阵亡时其余存活队友各摸 1 张牌"
		seat_names = ["1号位·你（联军）", "2号位·队友（联军）", "3号位·BOSS（魔王·8血）", "4号位·队友（联军）"]
	elif game_mode == "duel":
		title_text = "单挑对决 · 1 对 1"
		config_text = "两人单挑，击杀对手获胜｜先手先出牌、起手 3 张；后手起手 4 张"
		seat_names = ["你（玩家）", "AI 玩家 1"]
		if my_role not in ["先手", "后手"]:
			my_role = "先手"
	var t := Art.halo(lbl(title_text, 46, C_INK, true), 10)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(t)
	vb.add_child(bar)
	vb.add_child(Art.halo(lbl(config_text, 30, C_INK, false, HORIZONTAL_ALIGNMENT_CENTER), 7))
	role_btns.clear()
	if game_mode == "doudizhu":
		vb.add_child(Art.halo(lbl("开局叫分定地主：轮流叫 1~3 倍，价高者成为地主（倍数显示在结算页）", 26, C_INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER), 6))
	if game_mode == "duel":
		var rrow := HBoxContainer.new()
		rrow.alignment = BoxContainer.ALIGNMENT_CENTER
		rrow.add_theme_constant_override("separation", 20)
		var roles: Array = ["先手", "后手"]
		for r in roles:
			var rb := plain_btn("", Color(1, 1, 1, 0.9), C_INK, 28)
			rb.custom_minimum_size = Vector2(240, 64)
			rb.set_meta("role", r)
			rb.pressed.connect(func() -> void: set_my_role(r))
			rrow.add_child(rb)
			role_btns.append(rb)
		vb.add_child(rrow)
		refresh_role_btns()
	var seats := HBoxContainer.new()
	seats.alignment = BoxContainer.ALIGNMENT_CENTER
	seats.add_theme_constant_override("separation", 24)
	vb.add_child(seats)
	for i in seat_names.size():
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(300, 220)
		p.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.88), 26, C_GOLD if i == 0 else Color(0.75, 0.72, 0.85), 3, true))
		var pv := VBoxContainer.new()
		pv.alignment = BoxContainer.ALIGNMENT_CENTER
		pv.add_child(lbl(seat_names[i], 36, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER))
		var sub_text := "身份：开局揭晓" if i == 0 else "身份：隐藏"
		if game_mode == "doudizhu":
			sub_text = "身份：叫分决定" if i == 0 else "身份：叫分决定"
		elif game_mode == "twovtwo":
			sub_text = "阵营：红方（与4号位同队）" if (i == 0 or i == 3) else "阵营：蓝方（敌方同盟）"
		elif game_mode == "boss":
			sub_text = "BOSS：8体力+魔威·星蚀" if i == 2 else "阵营：学园联军（3人同队）"
		elif game_mode == "duel":
			sub_text = "单挑：先手 / 后手" if i == 0 else "单挑对手"
		pv.add_child(lbl(sub_text, 26, C_INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER))
		p.add_child(pv)
		seats.add_child(p)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var start := plain_btn("开始对战（先选将）", C_PLATE, C_WHITE, 40)
	start.custom_minimum_size = Vector2(560, 110)
	start.pressed.connect(func() -> void: start_match(false))
	row.add_child(start)
	vb.add_child(row)


# 新增 UI 成员（V0.3 桌面布局）
var phase_label: Label
var announce_label: Label
var prompt_panel: PanelContainer
var draft_layer: HBoxContainer
var log_panel: PanelContainer
var in_play_phase: bool = false
var selected_card: Dictionary = {}
var sel_anim_card: Dictionary = {}
var breath_t := 0.0
var vw := 1920.0
var bubble_nodes := {}
var bubble_order: Array = []  # 同屏气泡最多 2 个，超出时先收最早的
var skill_sig := ""
var skill_passives: HBoxContainer = null
var speed_idx := 0
var speed_btn: Button = null
const SPEEDS := [1.0, 1.5, 2.0]
var skip_tap_ms := -1  # 点空白桌面跳过当前等待（AI 出牌间隔/动画停顿）
var targeting: bool = false
var spear_targeting: bool = false
var spear_cards: Array = []  # V0.32：合璧长枪由玩家自选的两张手牌
var muniu_targeting: bool = false
var game_mode: String = "identity"
var my_role: String = ""
var match_players: int = 5
var role_btns: Array = []
var difficulty: int = 1
var diff_layer: Control = null
var diff_btns: Array = []
var dying_holder: PanelContainer = null
var dying_seat: int = -1
var burst_node: Control = null
var burst_tween: Tween = null
var settlement_layer: Control = null
var target_candidates: Array = []
var draft_banner: Label
var seat_table_label: Label
var seat_table_panel: PanelContainer
var glow_frames: Dictionary = {}
var showcase_panel: Panel
var showcase_band: Panel
var showcase_glyph: Label
var showcase_owner: Label
var showcase_plate: Panel
var showcase_top: Label
var showcase_name: Label
var showcase_kind: Label
var table_nodes: Array = []
# ---- V0.25 出牌手感 ----
const CARD_W := 172.0
const CARD_H := 268.0
const HAND_Y := 784.0
const HAND_H := 296.0
const LIFT := 36.0
const DRAG_START_PX := 18.0
const SNAP_PX := 46.0
var hand_x0 := 352.0
var hand_x1 := 1230.0
var hand_cards: Array = []  # 手牌节点（wrap），meta "card" 指向牌字典本身
var action_bar: HBoxContainer
var confirm_btn: Button
var cancel_btn: Button
var me_click_btn: Button
var ask_secs_label: Label
var asking := false
var ask_seq := 0
var ask_timeout := 15.0
var ask_default: Variant = null
var sel_target := -1
var discard_mode := false
var discard_need := 0
var discard_sel: Array = []
var discard_queue: Array = []
var discard_confirm_btn: Button = null
var respond_name := ""
var drag_wrap: Control = null
var drag_press := {}  # {wrap, pos, offset}
var drag_hover_seat := -1
var drag_line: Line2D
var drag_end_ms := 0


func show_played_card(card: Dictionary, owner: String, from_seat: int = -1) -> void:
	# V0.25：牌飞入桌面中央处理区（自己的牌从手牌实际位置起飞，AI 从座位起飞），按顺序堆叠，结算后飞向弃牌堆
	if card.is_empty():
		return
	var from := _pz_center() + Vector2(0, -260)
	if from_seat == 0:
		var w := _find_wrap(card)
		if w != null:
			from = w.global_position - global_position + Vector2(CARD_W, CARD_H) * 0.5
		elif not fly_from_hand.is_empty():
			from = Vector2(fly_from_hand["pos"])
		else:
			from = hand_row.position + Vector2(hand_row.size.x * 0.5, 120) if hand_row != null else seat_center(0)
	elif from_seat > 0:
		from = seat_center(from_seat)
	_pz_add(card, owner, from)


func set_phase(text: String) -> void:
	if phase_label:
		phase_label.text = text


func show_hint(text: String) -> void:
	prompt_panel.visible = true
	prompt_label.text = text


func hide_prompt() -> void:
	if ask_bar_tween and ask_bar_tween.is_valid():
		ask_bar_tween.kill()
	if ask_bar_bg_ref != null:
		ask_bar_bg_ref.visible = false
	if ask_secs_label != null:
		ask_secs_label.visible = false
	prompt_label.text = ""
	for ch in prompt_btns.get_children():
		prompt_btns.remove_child(ch)
		ch.queue_free()
	prompt_panel.visible = false


func build_table() -> void:
	vw = get_viewport_rect().size.x
	for ch in get_children():
		ch.queue_free()
	seat_panels.clear()
	selected_card = {}
	targeting = false
	var bg_catch := Control.new()
	bg_catch.name = "BgCatch"
	bg_catch.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_catch.size = Vector2(vw, 1080)
	bg_catch.mouse_filter = MOUSE_FILTER_STOP
	bg_catch.gui_input.connect(_on_table_bg_input)
	add_child(bg_catch)
	# 顶部：logo（左）/ 阶段标题（中）/ 牌堆胶囊（右）
	var logo := lbl("全明星杀", 44, C_PINK_DEEP, true)
	logo.position = Vector2(48, 22)
	logo.autowrap_mode = TextServer.AUTOWRAP_OFF
	logo.add_theme_color_override("font_shadow_color", Color(0.92, 0.30, 0.52, 0.30))
	logo.add_theme_constant_override("shadow_offset_x", 3)
	logo.add_theme_constant_override("shadow_offset_y", 3)
	add_child(logo)
	var logo_en := lbl("A L L   S T A R   K I L L", 16, Color(0.72, 0.45, 0.08), true)
	logo_en.position = Vector2(50, 78)
	logo_en.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(logo_en)
	var rule := Panel.new()
	rule.position = Vector2(50, 104)
	rule.size = Vector2(120, 4)
	rule.mouse_filter = MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override("panel", style(C_GOLD, 2))
	add_child(rule)
	var back := plain_btn("← 退出", C_WHITE, C_PINK_DEEP, 22)
	back.position = Vector2(48, 120)
	back.size = Vector2(132, 46)
	back.pressed.connect(func() -> void: go_home.call())
	add_child(back)
	phase_label = Art.halo(lbl("", 34, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER), 9)
	# V0.27：阶段标题放到功能条与右侧信息胶囊之间，不再与功能按钮重叠
	phase_label.position = Vector2(FEAT_END, 26)
	phase_label.size = Vector2(maxf(vw - 530.0 - FEAT_END, 300.0), 46)
	phase_label.clip_text = true
	phase_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(phase_label)
	turn_label = Art.halo(lbl("", 22, C_INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER), 6)
	turn_label.position = Vector2(FEAT_END, 84)
	turn_label.size = Vector2(maxf(vw - 530.0 - FEAT_END, 300.0), 32)
	turn_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(turn_label)
	var pill_defs := [[vw - 520, 156], [vw - 352, 140], [vw - 200, 152]]
	var pill_lbls: Array = []
	var pill_init := ["牌堆 --", "弃牌 0", "选将中"]  # 开局前（选将/叫分）不留空白胶囊
	for pd in pill_defs:
		var pill := Panel.new()
		pill.position = Vector2(pd[0], 24)
		pill.size = Vector2(pd[1], 52)
		pill.mouse_filter = MOUSE_FILTER_IGNORE
		pill.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.85), 26, Color(1, 1, 1, 0.7), 1, true))
		add_child(pill)
		var pl := lbl(String(pill_init[pill_lbls.size()]), 23, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER)
		pl.position = Vector2(pd[0], 36)
		pl.size = Vector2(pd[1], 32)
		pl.autowrap_mode = TextServer.AUTOWRAP_OFF
		add_child(pl)
		pill_lbls.append(pl)
	deck_label = pill_lbls[0]
	disc_label = pill_lbls[1]
	round_label = pill_lbls[2]
	# 中央宣告
	announce_label = lbl("", 48, C_PINK_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER)
	announce_label.position = Vector2(0, 640)
	announce_label.size = Vector2(vw, 64)
	announce_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	announce_label.modulate = Color(1, 1, 1, 0)
	add_child(announce_label)
	# 功能条（对着无名杀补：记牌器/战况记录/手牌排序/托管/认输）
	var feat_defs := ["记牌", "记录", "排序", "托管", "认输", "倍速", "设置"]
	for fi in feat_defs.size():
		var fb := plain_btn(feat_defs[fi], Color(1, 1, 1, 0.92), C_INK, 24)
		fb.position = Vector2(16 + fi * 118, 24)
		fb.size = Vector2(108, 52)
		add_child(fb)
		match feat_defs[fi]:
			"记牌":
				fb.pressed.connect(func() -> void: open_info_overlay("记牌器 · 战场情报", counter_text()))
			"记录":
				fb.pressed.connect(func() -> void: open_info_overlay("战况记录", "\n".join(eng.log_lines) if eng != null else ""))
			"排序":
				fb.pressed.connect(func() -> void: sort_my_hand())
			"托管":
				auto_btn = fb
				fb.pressed.connect(func() -> void: toggle_auto())
			"认输":
				concede_btn = fb
				fb.pressed.connect(func() -> void: on_concede_pressed())
			"设置":
				settings_btn = fb
				fb.pressed.connect(func() -> void: toggle_settings_panel())
			"倍速":
				speed_btn = fb
				fb.text = "%sx" % str(SPEEDS[speed_idx])
				fb.pressed.connect(func() -> void: cycle_speed())
	# 信息浮层（记牌器/战况记录共用）
	info_overlay = Panel.new()
	info_overlay.position = Vector2(0, 0)
	info_overlay.size = Vector2(vw, 1080)
	info_overlay.mouse_filter = MOUSE_FILTER_STOP
	info_overlay.add_theme_stylebox_override("panel", style(Color(0.16, 0.1, 0.24, 0.72), 0))
	info_overlay.visible = false
	add_child(info_overlay)
	var card_panel := Panel.new()
	card_panel.position = Vector2((vw - 1160) / 2.0, 130)
	card_panel.size = Vector2(1160, 800)
	card_panel.mouse_filter = MOUSE_FILTER_IGNORE
	card_panel.add_theme_stylebox_override("panel", style(Color(1, 0.99, 1, 0.98), 24, C_GOLD, 3, true))
	info_overlay.add_child(card_panel)
	info_title = lbl("", 34, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	info_title.position = Vector2((vw - 1160) / 2.0, 152)
	info_title.size = Vector2(1160, 48)
	info_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	info_overlay.add_child(info_title)
	info_text = RichTextLabel.new()
	info_text.bbcode_enabled = false
	info_text.fit_content = false
	info_text.scroll_active = true
	info_text.position = Vector2((vw - 1160) / 2.0 + 44, 216)
	info_text.size = Vector2(1160 - 88, 800 - 170)
	info_text.add_theme_font_override("normal_font", font_reg)
	info_text.add_theme_font_size_override("normal_font_size", 25)
	info_text.add_theme_color_override("default_color", C_INK)
	info_overlay.add_child(info_text)
	var close_btn := plain_btn("关闭", Color(1, 1, 1, 0.95), C_PINK_DEEP, 26)
	close_btn.position = Vector2(vw / 2.0 - 90, 130 + 800 + 18)
	close_btn.size = Vector2(180, 60)
	close_btn.pressed.connect(func() -> void: info_overlay.visible = false)
	info_overlay.add_child(close_btn)
	_extend_cover(info_overlay, Color(0.16, 0.1, 0.24, 0.72))
	# 四个 AI 座位（环绕桌面）
	var seat_pos: Dictionary
	if match_players == 3:
		seat_pos = {1: Vector2(452, 120), 2: Vector2(vw - 702, 120)}
	elif match_players == 2:
		seat_pos = {1: Vector2((vw - 250) / 2.0, 120)}
	elif match_players == 4:
		seat_pos = {1: Vector2(76, 250), 2: Vector2((vw - 250) / 2.0, 114), 3: Vector2(vw - 326, 250)}
	else:
		seat_pos = {1: Vector2(64, 296), 2: Vector2(452, 120), 3: Vector2(vw - 702, 120), 4: Vector2(vw - 314, 296)}
	for i in match_players - 1:
		var seat_idx := i + 1
		var panel := make_seat_panel(seat_idx)
		panel.position = seat_pos[seat_idx]
		panel.size = Vector2(250, 372)
		add_child(panel)
		seat_panels.append(panel)
		table_nodes.append(panel)
		var glow := Panel.new()
		glow.position = seat_pos[seat_idx] - Vector2(7, 7)
		glow.size = Vector2(264, 386)
		glow.mouse_filter = MOUSE_FILTER_IGNORE
		glow.add_theme_stylebox_override("panel", style(Color(1, 0.45, 0.65, 0.0), 26, C_PINK_DEEP, 5, true))
		glow.visible = false
		add_child(glow)
		glow_frames[seat_idx] = glow
		var gt := create_tween().set_loops()
		gt.tween_property(glow, "modulate:a", 0.45, 0.55)
		gt.tween_property(glow, "modulate:a", 1.0, 0.55)
	# 提示条（提问/选目标时出现）
	# V0.25 手杀式提示条：窄条文字 + 倒计时进度条（位于处理区下方）；作答按钮统一放在手牌上方的操作栏位置
	hand_x0 = 352.0
	hand_x1 = vw - 690.0
	var bar_cx := (hand_x0 + hand_x1) * 0.5
	prompt_panel = PanelContainer.new()
	prompt_panel.position = Vector2(bar_cx - 450, 596)
	prompt_panel.size = Vector2(900, 72)
	prompt_panel.mouse_filter = MOUSE_FILTER_IGNORE
	prompt_panel.add_theme_stylebox_override("panel", style(Color(0.16, 0.10, 0.22, 0.80), 18, Color(1.0, 0.80, 0.42, 0.85), 2, true))
	var pv := VBoxContainer.new()
	pv.mouse_filter = MOUSE_FILTER_IGNORE
	pv.add_theme_constant_override("separation", 6)
	prompt_panel.add_child(pv)
	prompt_label = lbl("", 25, Color(1.0, 0.95, 0.86), true, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt_label.clip_text = true
	prompt_label.mouse_filter = MOUSE_FILTER_IGNORE
	pv.add_child(prompt_label)
	var ask_bar_bg := Panel.new()
	ask_bar_bg_ref = ask_bar_bg
	ask_bar_bg.visible = false
	ask_bar_bg.custom_minimum_size = Vector2(0, 8)
	ask_bar_bg.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.18), 4))
	ask_bar_bg.mouse_filter = MOUSE_FILTER_IGNORE
	pv.add_child(ask_bar_bg)
	ask_bar_fill = ColorRect.new()
	ask_bar_fill.color = Color(0.25, 0.90, 0.80, 0.95)
	ask_bar_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	ask_bar_fill.mouse_filter = MOUSE_FILTER_IGNORE
	ask_bar_bg.add_child(ask_bar_fill)
	ask_secs_label = lbl("", 20, Color(1, 1, 1, 0.9), true, HORIZONTAL_ALIGNMENT_RIGHT)
	ask_secs_label.position = prompt_panel.position + Vector2(900 - 80, 12)
	ask_secs_label.size = Vector2(64, 28)
	ask_secs_label.mouse_filter = MOUSE_FILTER_IGNORE
	ask_secs_label.visible = false
	prompt_panel.visible = false
	add_child(prompt_panel)
	add_child(ask_secs_label)
	prompt_btns = HBoxContainer.new()
	prompt_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_btns.add_theme_constant_override("separation", 14)
	prompt_btns.position = Vector2(bar_cx - 560, 682)
	prompt_btns.size = Vector2(1120, 66)
	add_child(prompt_btns)
	# 操作栏（手杀：确定 / 取消 / 结束 位于手牌正上方）
	action_bar = HBoxContainer.new()
	action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	action_bar.add_theme_constant_override("separation", 18)
	action_bar.position = Vector2(bar_cx - 430, 682)
	action_bar.size = Vector2(860, 66)
	action_bar.visible = false
	add_child(action_bar)
	confirm_btn = _make_action_btn("确定", C_GOLD, Color(0.25, 0.16, 0.05))
	confirm_btn.pressed.connect(_on_confirm_pressed)
	action_bar.add_child(confirm_btn)
	cancel_btn = _make_action_btn("取消", Color(1, 1, 1, 0.96), C_PINK_DEEP)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	action_bar.add_child(cancel_btn)
	# V0.28：重铸（无名杀 recastable）——选中可重铸的牌后出现，点击即重铸（弃置并摸一张）
	recast_btn = _make_action_btn("重铸", Color(0.62, 0.80, 1.0), Color(0.10, 0.18, 0.35))
	recast_btn.pressed.connect(_on_recast_pressed)
	recast_btn.visible = false
	action_bar.add_child(recast_btn)
	# V0.33：手气卡（对标手杀开局换牌，首轮未出牌前最多换 2 次）
	luck_btn = _make_action_btn("手气卡×2", Color(0.95, 0.56, 0.72), C_WHITE)
	luck_btn.pressed.connect(_on_luck_pressed)
	luck_btn.visible = false
	action_bar.add_child(luck_btn)
	# 选将层
	draft_layer = HBoxContainer.new()
	draft_layer.position = Vector2(vw * 0.5 - 624, 262)
	draft_layer.size = Vector2(1248, 470)
	draft_layer.alignment = BoxContainer.ALIGNMENT_CENTER
	draft_layer.add_theme_constant_override("separation", 24)
	draft_layer.visible = false
	add_child(draft_layer)
	# 难度选择层（选将时显示，位于选将卡下方）
	diff_layer = Control.new()
	diff_layer.visible = false
	add_child(diff_layer)
	diff_layer.position = Vector2(vw * 0.5 - 460, 756)
	diff_layer.size = Vector2(920, 56)
	var dl := lbl("AI 难度", 24, C_PINK_DEEP, true)
	dl.autowrap_mode = TextServer.AUTOWRAP_OFF
	dl.position = Vector2(0, 8)
	dl.size = Vector2(110, 40)
	diff_layer.add_child(dl)
	for di in 3:
		var db := Button.new()
		db.focus_mode = Control.FOCUS_NONE
		db.text = ["简单", "普通", "困难"][di]
		db.add_theme_font_override("font", font_bold)
		db.add_theme_font_size_override("font_size", 24)
		diff_layer.add_child(db)
		db.position = Vector2(118 + di * 118, 0)
		db.size = Vector2(108, 52)
		var dv := di
		db.pressed.connect(func() -> void: _on_difficulty(dv))
		diff_btns.append(db)
	refresh_diff_buttons()
	# V0.33：选将支持「换一批」与「自由点将」（对标手杀换将卡/无名杀自由点将）
	var rbtn := plain_btn("🔄 换一批", Color(1, 1, 1, 0.94), C_PINK_DEEP, 23)
	rbtn.position = Vector2(500, 0)
	rbtn.size = Vector2(170, 52)
	rbtn.pressed.connect(_on_reshuffle_draft)
	diff_layer.add_child(rbtn)
	var fpbtn := plain_btn("★ 自由点将", C_GOLD, Color(0.24, 0.14, 0.05), 23)
	fpbtn.position = Vector2(686, 0)
	fpbtn.size = Vector2(190, 52)
	fpbtn.pressed.connect(_open_free_pick)
	diff_layer.add_child(fpbtn)
	# 左下：自己的角色牌
	var me_panel := Panel.new()
	me_panel_ref = me_panel
	me_panel.position = Vector2(40, 676)
	me_panel.size = Vector2(292, 372)
	me_panel.mouse_filter = MOUSE_FILTER_IGNORE
	me_panel.set_meta("seat", 0)
	me_panel.set_meta("intro", Callable(self, "_intro_seat").bind(0))
	me_panel.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.94), 22, C_GOLD, 3, true))
	add_child(me_panel)
	table_nodes.append(me_panel)
	# 特效层（最上层，不拦点击）
	fx_root = Control.new()
	fx_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_root.mouse_filter = MOUSE_FILTER_IGNORE
	fx_root.child_entered_tree.connect(_fx_click_through)
	add_child(fx_root)
	turn_banner = lbl("", 54, Color(1.0, 0.72, 0.25), true, HORIZONTAL_ALIGNMENT_CENTER)
	turn_banner.position = Vector2(0, 520)
	turn_banner.size = Vector2(vw, 72)
	turn_banner.autowrap_mode = TextServer.AUTOWRAP_OFF
	turn_banner.modulate = Color(1, 1, 1, 0)
	turn_banner.mouse_filter = MOUSE_FILTER_IGNORE
	turn_banner.add_theme_constant_override("outline_size", 10)
	turn_banner.add_theme_color_override("font_outline_color", Color(0.45, 0.2, 0.3, 0.9))
	fx_root.add_child(turn_banner)
	for wx in [vw * 0.5 - 395, vw * 0.5 + 195]:
		var wing := Panel.new()
		wing.position = Vector2(wx, 35)
		wing.size = Vector2(200, 3)
		wing.mouse_filter = MOUSE_FILTER_IGNORE
		wing.add_theme_stylebox_override("panel", style(Color(1.0, 0.72, 0.25, 0.75), 2))
		turn_banner.add_child(wing)
	match_banner = lbl("", 88, Color(1.0, 0.75, 0.25), true, HORIZONTAL_ALIGNMENT_CENTER)
	match_banner.position = Vector2(0, 430)
	match_banner.size = Vector2(vw, 120)
	match_banner.autowrap_mode = TextServer.AUTOWRAP_OFF
	match_banner.modulate = Color(1, 1, 1, 0)
	match_banner.mouse_filter = MOUSE_FILTER_IGNORE
	match_banner.add_theme_constant_override("outline_size", 14)
	match_banner.add_theme_color_override("font_outline_color", Color(0.5, 0.2, 0.25, 0.95))
	fx_root.add_child(match_banner)
	_ensure_sfx()
	me_panel.clip_contents = true
	player_portrait = TextureRect.new()
	player_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	player_portrait.mouse_filter = MOUSE_FILTER_IGNORE
	me_panel.add_child(player_portrait)
	player_portrait.position = Vector2(7, -2)
	player_portrait.size = Vector2(278, 336)
	var me_plate := Panel.new()
	me_plate.position = Vector2(-6, 282)
	me_plate.size = Vector2(252, 52)
	me_plate.rotation = -0.02
	me_plate.mouse_filter = MOUSE_FILTER_IGNORE
	me_plate.add_theme_stylebox_override("panel", style(C_PLATE, 10, Color(1, 1, 1, 0.9), 2, true))
	me_panel.add_child(me_plate)
	var mgloss := Panel.new()
	mgloss.set_anchors_preset(Control.PRESET_TOP_WIDE)
	mgloss.size = Vector2(0, 20)
	mgloss.mouse_filter = MOUSE_FILTER_IGNORE
	mgloss.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.16), 9))
	me_plate.add_child(mgloss)
	player_info = lbl("", 21, C_WHITE, true)
	player_info.position = Vector2(16, 9)
	player_info.size = Vector2(224, 36)
	player_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	player_info.clip_text = true
	me_plate.add_child(player_info)
	me_hp_label = lbl("", 25, C_PINK_DEEP, true)
	me_hp_label.position = Vector2(16, 340)
	me_hp_label.size = Vector2(264, 30)
	me_hp_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	me_panel.add_child(me_hp_label)
	_add_seat_overlays(me_panel, Vector2(292, 372), true)
	var me_pl := Art.name_plate({"name": "", "rarity": "SR"}, 24, true)
	me_pl.position = Vector2(8, 54)
	me_panel.add_child(me_pl)
	Art.add_corners(me_panel, Vector2(292, 336), 34.0, 0.0)
	_build_guess_popup()
	me_chips = HBoxContainer.new()
	me_chips.position = Vector2(356, 988)
	me_chips.add_theme_constant_override("separation", 10)
	add_child(me_chips)
	table_nodes.append(me_chips)
	skill_passives = HBoxContainer.new()
	skill_passives.position = Vector2(vw - 674, 694)
	skill_passives.add_theme_constant_override("separation", 8)
	add_child(skill_passives)
	table_nodes.append(skill_passives)
	skill_sig = ""
	skill_btns = VBoxContainer.new()
	skill_btns.position = Vector2(vw - 674, 748)
	skill_btns.size = Vector2(230, 170)
	skill_btns.add_theme_constant_override("separation", 14)
	add_child(skill_btns)
	table_nodes.append(skill_btns)
	# 底部中央：手牌区
	# V0.25 手牌层（对照无名杀 updatehl：重叠排布、放不下自动压缩；节点按牌复用，位置变化才补间）
	hand_row = Control.new()
	hand_row.position = Vector2(hand_x0, HAND_Y)
	hand_row.size = Vector2(hand_x1 - hand_x0, HAND_H)
	hand_row.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(hand_row)
	table_nodes.append(hand_row)
	hand_cards.clear()
	drag_line = Line2D.new()
	drag_line.width = 5.0
	drag_line.default_color = Color(1.0, 0.85, 0.45, 0.9)
	drag_line.visible = false
	add_child(drag_line)
	# 自己的头像也可点选（以自己为目标的牌：补给、增兵减灶、洞烛先机等）
	me_click_btn = Button.new()
	me_click_btn.flat = true
	me_click_btn.focus_mode = Control.FOCUS_NONE
	me_click_btn.position = Vector2(40, 676)
	me_click_btn.size = Vector2(292, 372)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		me_click_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	me_click_btn.pressed.connect(func() -> void: _on_seat_clicked(0))
	me_click_btn.set_meta("intro", Callable(self, "_intro_seat").bind(0))
	add_child(me_click_btn)
	table_nodes.append(me_click_btn)
	# 选将身份横幅（仅选将时显示）
	draft_banner = lbl("", 46, C_PINK_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER)
	draft_banner.add_theme_constant_override("outline_size", 8)
	draft_banner.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	draft_banner.position = Vector2(0, 108)
	draft_banner.size = Vector2(1920, 130)
	draft_banner.autowrap_mode = TextServer.AUTOWRAP_OFF
	draft_banner.visible = false
	add_child(draft_banner)
	# 右上角座次表
	seat_table_panel = PanelContainer.new()
	seat_table_panel.position = Vector2(vw - 356, 84)
	seat_table_panel.size = Vector2(328, 150)
	seat_table_panel.clip_contents = true
	seat_table_panel.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.86), 16, C_GOLD, 2, true))
	seat_table_panel.visible = false
	seat_table_label = lbl("", 17, C_INK, false)
	seat_table_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	seat_table_label.clip_text = true
	seat_table_label.add_theme_constant_override("line_spacing", 2)
	seat_table_panel.add_child(seat_table_label)
	add_child(seat_table_panel)
	# 出牌展示（桌面中央）
	showcase_panel = Panel.new()
	showcase_panel.position = Vector2(vw * 0.5 - 112, 300)
	showcase_panel.size = Vector2(224, 310)
	showcase_panel.mouse_filter = MOUSE_FILTER_IGNORE
	showcase_panel.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.97), 16, C_GOLD, 3, true))
	showcase_panel.pivot_offset = Vector2(112, 155)
	showcase_panel.visible = false
	showcase_band = Panel.new()
	showcase_band.position = Vector2(0, 0)
	showcase_band.size = Vector2(224, 46)
	showcase_band.mouse_filter = MOUSE_FILTER_IGNORE
	showcase_band.add_theme_stylebox_override("panel", style(C_PLATE, 0))
	showcase_panel.add_child(showcase_band)
	showcase_top = lbl("", 25, C_WHITE, true)
	showcase_top.position = Vector2(12, 8)
	showcase_top.size = Vector2(180, 32)
	showcase_top.autowrap_mode = TextServer.AUTOWRAP_OFF
	showcase_top.mouse_filter = MOUSE_FILTER_IGNORE
	showcase_band.add_child(showcase_top)
	var halo2 := Panel.new()
	halo2.position = Vector2(52, 64)
	halo2.size = Vector2(120, 120)
	halo2.mouse_filter = MOUSE_FILTER_IGNORE
	halo2.add_theme_stylebox_override("panel", style(Color(1, 0.36, 0.54, 0.13), 60))
	showcase_panel.add_child(halo2)
	var sc_inner := Panel.new()
	sc_inner.position = Vector2(5, 5)
	sc_inner.size = Vector2(214, 300)
	sc_inner.mouse_filter = MOUSE_FILTER_IGNORE
	sc_inner.add_theme_stylebox_override("panel", style(Color(0, 0, 0, 0), 13, Color(0.91, 0.64, 0.24, 0.45), 1))
	showcase_panel.add_child(sc_inner)
	showcase_glyph = lbl("", 96, C_PLATE, true, HORIZONTAL_ALIGNMENT_CENTER)
	showcase_glyph.position = Vector2(0, 74)
	showcase_glyph.size = Vector2(224, 116)
	showcase_glyph.mouse_filter = MOUSE_FILTER_IGNORE
	showcase_panel.add_child(showcase_glyph)
	showcase_name = lbl("", 34, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	showcase_name.position = Vector2(0, 208)
	showcase_name.size = Vector2(224, 44)
	showcase_name.mouse_filter = MOUSE_FILTER_IGNORE
	showcase_panel.add_child(showcase_name)
	showcase_kind = lbl("", 19, C_INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER)
	showcase_kind.position = Vector2(0, 258)
	showcase_kind.size = Vector2(224, 26)
	showcase_kind.mouse_filter = MOUSE_FILTER_IGNORE
	showcase_panel.add_child(showcase_kind)
	showcase_plate = Panel.new()
	showcase_plate.position = Vector2(-64, 310)
	showcase_plate.size = Vector2(352, 50)
	showcase_plate.mouse_filter = MOUSE_FILTER_IGNORE
	showcase_plate.add_theme_stylebox_override("panel", style(C_INDIGO, 25, Color(1, 1, 1, 0.9), 2, true))
	showcase_panel.add_child(showcase_plate)
	showcase_owner = lbl("", 27, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	showcase_owner.position = Vector2(-64, 318)
	showcase_owner.size = Vector2(352, 36)
	showcase_owner.mouse_filter = MOUSE_FILTER_IGNORE
	showcase_owner.add_theme_constant_override("outline_size", 5)
	showcase_owner.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
	showcase_panel.add_child(showcase_owner)
	add_child(showcase_panel)
	# V0.25 处理区层（节点池复用）与看破链面板
	pz_layer = Control.new()
	pz_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	pz_layer.mouse_filter = MOUSE_FILTER_IGNORE
	pz_layer.child_entered_tree.connect(_fx_click_through)
	add_child(pz_layer)
	pz_pool.clear()
	pz_live.clear()
	nullify_panel = PanelContainer.new()
	nullify_panel.position = Vector2(vw * 0.5 - 640, 486)
	nullify_panel.size = Vector2(330, 100)
	nullify_panel.mouse_filter = MOUSE_FILTER_IGNORE
	nullify_panel.add_theme_stylebox_override("panel", style(Color(0.16, 0.10, 0.22, 0.82), 14, Color(0.85, 0.62, 0.1), 2, true))
	nullify_label = lbl("", 17, Color(1.0, 0.92, 0.7), true)
	nullify_label.mouse_filter = MOUSE_FILTER_IGNORE
	nullify_panel.add_child(nullify_label)
	nullify_panel.visible = false
	nullify_panel.set_meta("intro", Callable(self, "_intro_card").bind({"name": "看破"}))
	add_child(nullify_panel)
	# 右下：结束按钮 + 战报
	end_play_btn = _make_action_btn("结束", C_PLATE, C_WHITE)
	end_play_btn.disabled = true
	end_play_btn.pressed.connect(_on_end_play_btn)
	action_bar.add_child(end_play_btn)
	log_panel = PanelContainer.new()
	log_panel.position = Vector2(vw - 414, 742)
	log_panel.size = Vector2(374, 258)
	log_panel.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.82), 18, C_GOLD, 2, true))
	var log_vb := VBoxContainer.new()
	log_vb.add_theme_constant_override("separation", 4)
	log_panel.add_child(log_vb)
	var log_head := lbl("战报 LOG", 20, C_PINK_DEEP, true)
	log_vb.add_child(log_head)
	log_label = lbl("", 19, C_INK, false)
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_vb.add_child(log_label)
	var accent := Panel.new()
	accent.position = Vector2(vw - 414, 758)
	accent.size = Vector2(5, 40)
	accent.mouse_filter = MOUSE_FILTER_IGNORE
	accent.add_theme_stylebox_override("panel", style(C_PLATE, 2))
	add_child(accent)
	table_nodes.append(accent)
	add_child(log_panel)
	table_nodes.append(log_panel)


func make_seat_panel(seat_idx: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", style(C_GOLD, 22, Color(1, 1, 1, 0.9), 2, true))
	b.add_theme_stylebox_override("hover", style(C_GOLD.lightened(0.1), 22, Color(1, 1, 1, 0.95), 2, true))
	b.add_theme_stylebox_override("pressed", style(C_GOLD.darkened(0.05), 22, Color(1, 1, 1, 0.95), 2, false))
	b.add_theme_stylebox_override("disabled", style(C_GOLD, 22, Color(1, 1, 1, 0.9), 2, true))
	var mat := Panel.new()
	mat.position = Vector2(5, 5)
	mat.size = Vector2(240, 362)
	mat.mouse_filter = MOUSE_FILTER_IGNORE
	mat.add_theme_stylebox_override("panel", style(Color(1, 1, 1), 18))
	b.add_child(mat)
	var tr := TextureRect.new()
	tr.name = "Portrait"
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(tr)
	tr.position = Vector2(7, 7)
	tr.size = Vector2(236, 358)
	var inner := Panel.new()
	inner.position = Vector2(7, 7)
	inner.size = Vector2(236, 358)
	inner.mouse_filter = MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", style(Color(0, 0, 0, 0), 18, Color(1, 1, 1, 0.55), 1))
	b.add_child(inner)
	var gem := Panel.new()
	gem.name = "Gem"
	gem.position = Vector2(12, 12)
	gem.size = Vector2(50, 50)
	gem.mouse_filter = MOUSE_FILTER_IGNORE
	gem.add_theme_stylebox_override("panel", style(C_PLATE, 25, Color(1, 1, 1), 3, true))
	b.add_child(gem)
	var ghl := Panel.new()
	ghl.position = Vector2(9, 7)
	ghl.size = Vector2(13, 13)
	ghl.mouse_filter = MOUSE_FILTER_IGNORE
	ghl.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.75), 6))
	gem.add_child(ghl)
	var gt := lbl("?", 27, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	gt.name = "GemText"
	gt.position = Vector2(0, 7)
	gt.size = Vector2(50, 36)
	gem.add_child(gt)
	var guess := Panel.new()
	guess.name = "Guess"
	guess.position = Vector2(186, 12)
	guess.size = Vector2(54, 40)
	guess.mouse_filter = MOUSE_FILTER_IGNORE
	guess.add_theme_stylebox_override("panel", style(Color(0.25, 0.2, 0.45, 0.85), 12, Color(1, 1, 1, 0.8), 1, true))
	guess.visible = false
	b.add_child(guess)
	var gt2 := lbl("", 20, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	gt2.name = "GuessText"
	gt2.position = Vector2(0, 5)
	gt2.size = Vector2(54, 30)
	gt2.autowrap_mode = TextServer.AUTOWRAP_OFF
	guess.add_child(gt2)
	var pips := VBoxContainer.new()
	pips.name = "Pips"
	pips.position = Vector2(214, 14)
	pips.add_theme_constant_override("separation", 6)
	pips.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(pips)
	var info_bg := Panel.new()
	info_bg.position = Vector2(7, 322)
	info_bg.size = Vector2(236, 43)
	info_bg.mouse_filter = MOUSE_FILTER_IGNORE
	info_bg.add_theme_stylebox_override("panel", style(Color(0, 0, 0, 0.32), 10))
	b.add_child(info_bg)
	var info := lbl("", 17, C_WHITE, false)
	info.name = "Info"
	info.position = Vector2(13, 331)
	info.size = Vector2(224, 24)
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.clip_text = true
	info.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(info)
	var chip := Panel.new()
	chip.name = "Chip"
	chip.position = Vector2(158, 325)
	chip.size = Vector2(84, 38)
	chip.mouse_filter = MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", style(Color(0.1, 0.06, 0.1, 0.72), 19, Color(1, 1, 1, 0.5), 1))
	b.add_child(chip)
	var ct := lbl("✋ 0", 21, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	ct.name = "ChipText"
	ct.position = Vector2(0, 6)
	ct.size = Vector2(84, 26)
	chip.add_child(ct)
	# V0.31 CG 卡框：左侧竖排名牌（系列徽标 + 竖排名字 + 稀有度，按角色在 refresh 里重建）+ 四角金饰
	var plate := Art.name_plate({"name": "", "rarity": "SR"}, 24, true)
	plate.position = Vector2(8, 66)
	b.add_child(plate)
	Art.add_corners(b, Vector2(250, 372), 34.0, -3.0)
	_add_seat_overlays(b, Vector2(250, 372), false)
	# 猜身份按钮（身份局、身份未明时）：座位本身只在选目标时可点，猜测用独立小按钮
	var gb := Button.new()
	gb.name = "GuessBtn"
	gb.focus_mode = Control.FOCUS_NONE
	gb.position = Vector2(182, 214)
	gb.size = Vector2(58, 40)
	gb.text = "猜"
	gb.add_theme_font_override("font", font_bold)
	gb.add_theme_font_size_override("font_size", 20)
	gb.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	gb.add_theme_stylebox_override("normal", style(Color(0.25, 0.2, 0.45, 0.7), 12, Color(1, 1, 1, 0.7), 1))
	gb.add_theme_stylebox_override("hover", style(Color(0.35, 0.28, 0.6, 0.85), 12, Color(1, 1, 1, 0.9), 1))
	gb.add_theme_stylebox_override("pressed", style(Color(0.35, 0.28, 0.6, 0.85), 12, Color(1, 1, 1, 0.9), 1))
	gb.pressed.connect(func() -> void: _open_guess(seat_idx))
	gb.visible = false
	b.add_child(gb)
	b.set_meta("seat", seat_idx)
	b.set_meta("intro", Callable(self, "_intro_seat").bind(seat_idx))
	b.pressed.connect(func() -> void: _on_seat_clicked(seat_idx))
	return b


# ---------------- V0.25 座位组件：装备栏 / 判定区图标 / 连环 / 濒死 / 阵亡 / 阶段标签 / 体力槽动画 ----------------
# 对照无名杀 layout：装备在头像左侧竖排、判定区小圆标在头像上沿、横置（连环）有锁链带、阵亡置灰并亮身份。
# 所有子节点建桌时一次建好，refresh 只改 visible/text，避免每次刷新分配节点（安卓 30fps）。

const SLOT_TAGS := {"weapon": "武", "armor": "防", "minus": "-1", "plus": "+1", "treasure": "宝"}
const JUDGE_SHORT := {
	"沉迷游戏": "判定不为红桃：跳过本回合出牌阶段。",
	"断粮封锁": "判定不为梅花：跳过本回合摸牌阶段。",
	"草木疑兵": "判定不为梅花：本回合少摸一张牌，摸牌后两名邻座各摸一张。",
	"落雷": "判定为黑桃 2~9：受到 3 点雷电伤害；否则移给下家。",
	"浮雷": "判定为黑桃：受到 X 点雷电伤害（X 为累计生效次数）；之后移给下家。",
}
const JUDGE_ICON := {"落雷": "雷", "浮雷": "浮", "沉迷游戏": "乐", "断粮封锁": "兵", "草木疑兵": "草"}
var pip_full_sb: StyleBoxFlat = null
var pip_empty_sb: StyleBoxFlat = null
var gray_mat: ShaderMaterial = null
var guess_popup: PanelContainer = null
var guess_popup_seat := -1
var float_stack := {}  # seat -> [上次飘字毫秒, 叠层序号]：同一座位连续飘字向上错开，不重叠


func _ensure_seat_res() -> void:
	if pip_full_sb == null:
		pip_full_sb = style(Color(1.0, 0.42, 0.62), 10, Color(1, 1, 1, 0.95), 2, true)
		pip_empty_sb = style(Color(0.25, 0.25, 0.3, 0.35), 10, Color(1, 1, 1, 0.65), 1)
	if gray_mat == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform float amt = 1.0;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV) * COLOR;\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(mix(c.rgb, vec3(g) * 0.82, amt), c.a);\n}\n"
		gray_mat = ShaderMaterial.new()
		gray_mat.shader = sh


func _tight(sb: StyleBoxFlat, h: int, v: int) -> StyleBoxFlat:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


func _add_seat_overlays(pn: Control, sz: Vector2, is_me: bool) -> void:
	_ensure_seat_res()
	# 装备栏：5 个槽位固定节点，左侧竖排
	var eqv := VBoxContainer.new()
	eqv.name = "Equips"
	# V0.31：左上让给竖排名牌，装备栏改为左下、自下而上排
	eqv.position = Vector2(10, 186) if not is_me else Vector2(10, 150)
	eqv.size = Vector2(176, 130)
	eqv.alignment = BoxContainer.ALIGNMENT_END
	eqv.add_theme_constant_override("separation", 3)
	eqv.mouse_filter = MOUSE_FILTER_IGNORE
	pn.add_child(eqv)
	for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
		var row := PanelContainer.new()
		row.name = slot
		row.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel", _tight(style(Color(0.13, 0.10, 0.20, 0.82), 8, Color(1.0, 0.82, 0.45, 0.55), 1), 3, 2))
		var hb := HBoxContainer.new()
		hb.mouse_filter = MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 4)
		row.add_child(hb)
		var tag := lbl(String(SLOT_TAGS[slot]), 15, Color(0.25, 0.16, 0.05), true, HORIZONTAL_ALIGNMENT_CENTER)
		tag.name = "Tag"
		tag.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.custom_minimum_size = Vector2(28, 22)
		tag.add_theme_stylebox_override("normal", _tight(style(C_GOLD, 6), 2, 0))
		hb.add_child(tag)
		var nm := lbl("", 16, C_WHITE, true)
		nm.name = "Name"
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		hb.add_child(nm)
		row.visible = false
		row.set_meta("intro", Callable(self, "_intro_equip").bind(pn, slot))
		eqv.add_child(row)
	# 判定区：最多 4 个小圆标
	var jh := HBoxContainer.new()
	jh.name = "Judges"
	jh.position = Vector2(68, 18) if not is_me else Vector2(12, 12)
	jh.add_theme_constant_override("separation", 4)
	jh.mouse_filter = MOUSE_FILTER_IGNORE
	pn.add_child(jh)
	for i in 4:
		var jl := lbl("", 18, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
		jl.custom_minimum_size = Vector2(32, 32)
		jl.add_theme_stylebox_override("normal", _tight(style(Color(0.45, 0.25, 0.70, 0.92), 16, Color(1, 1, 1, 0.9), 2, true), 0, 0))
		jl.visible = false
		jl.set_meta("intro", Callable(self, "_intro_judge").bind(pn, i))
		jh.add_child(jl)
	# 连环：斜跨头像的锁链带
	var ch := Panel.new()
	ch.name = "Chain"
	ch.position = Vector2(8, sz.y * 0.44)
	ch.size = Vector2(sz.x - 16, 30)
	ch.pivot_offset = ch.size * 0.5
	ch.rotation = -0.2
	ch.mouse_filter = MOUSE_FILTER_IGNORE
	ch.add_theme_stylebox_override("panel", style(Color(0.30, 0.34, 0.48, 0.88), 6, Color(0.80, 0.85, 1.0, 0.9), 2, true))
	var chl := lbl("— 连 环 —", 19, Color(0.88, 0.92, 1.0), true, HORIZONTAL_ALIGNMENT_CENTER)
	chl.size = ch.size
	chl.position = Vector2(0, 1)
	ch.add_child(chl)
	ch.visible = false
	pn.add_child(ch)
	# 濒死：红色脉冲描边
	var dy := Panel.new()
	dy.name = "Dying"
	dy.position = Vector2.ZERO
	dy.size = sz
	dy.mouse_filter = MOUSE_FILTER_IGNORE
	dy.add_theme_stylebox_override("panel", style(Color(0.9, 0.05, 0.2, 0.16), 22, Color(1.0, 0.15, 0.25), 6))
	dy.visible = false
	pn.add_child(dy)
	# 阵亡印章
	var dl := lbl("阵亡", 62, Color(0.95, 0.92, 0.92), true, HORIZONTAL_ALIGNMENT_CENTER)
	dl.name = "Dead"
	dl.size = Vector2(sz.x, 90)
	dl.position = Vector2(0, sz.y * 0.36)
	dl.pivot_offset = dl.size * 0.5
	dl.rotation = -0.3
	dl.add_theme_constant_override("outline_size", 12)
	dl.add_theme_color_override("font_outline_color", Color(0.55, 0.08, 0.14, 0.95))
	dl.visible = false
	pn.add_child(dl)
	# 当前阶段标签
	var ph := Label.new()
	ph.name = "PhaseTag"
	ph.add_theme_font_override("font", font_bold)
	ph.add_theme_font_size_override("font_size", 19)
	ph.add_theme_color_override("font_color", Color(0.25, 0.14, 0.04))
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.add_theme_stylebox_override("normal", _tight(style(Color(1.0, 0.80, 0.35), 15, Color(1, 1, 1, 0.95), 2, true), 4, 0))
	ph.size = Vector2(104, 32)
	ph.position = Vector2(sz.x * 0.5 - 52, -18) if not is_me else Vector2(sz.x - 114, 12)
	ph.mouse_filter = MOUSE_FILTER_IGNORE
	ph.visible = false
	pn.add_child(ph)
	pn.move_child(ch, eqv.get_index())  # 锁链带画在装备栏下面，不遮装备
	for n in [eqv, jh, ch, dy, dl, ph]:
		for sub in (n as Node).find_children("*", "Control", true, false):
			(sub as Control).mouse_filter = MOUSE_FILTER_IGNORE


func _equip_short(p: Dictionary, slot: String) -> String:
	var e: Dictionary = p["equip"][slot]
	if e.is_empty():
		return ""
	var n := String(e["name"])
	if slot == "treasure" and n == "木牛流马":
		return "木牛·%d" % (e.get("stored", []) as Array).size()
	if slot == "weapon":
		return "%s %d" % [n.substr(0, 4), CardDefs.weapon_range_of(n)]
	return n.substr(0, 4)


func _update_seat_overlays(pn: Control, p: Dictionary, portrait: CanvasItem) -> void:
	var alive := bool(p["alive"])
	var eqv := pn.get_node_or_null("Equips")
	if eqv == null:
		return
	for row in eqv.get_children():
		var slot := String(row.name)
		var txt := _equip_short(p, slot) if alive else ""
		(row as Control).visible = txt != ""
		if txt != "":
			var nl: Label = (row.get_child(0) as Node).get_node("Name")
			nl.text = txt
	var js: Array = p["judge"] if alive else []
	var jh := pn.get_node("Judges")
	for i in jh.get_child_count():
		var jl := jh.get_child(i) as Label
		if i < js.size():
			var jn := String(js[i]["name"])
			jl.text = String(JUDGE_ICON.get(jn, jn.substr(0, 1)))
			jl.tooltip_text = jn
			jl.visible = true
		else:
			jl.visible = false
	(pn.get_node("Chain") as Control).visible = alive and bool(p.get("chained", false))
	var dy := pn.get_node("Dying") as Control
	var dying := alive and int(p["hp"]) <= 0
	if dying and not dy.visible:
		dy.visible = true
		dy.modulate.a = 1.0
		var t := dy.create_tween().set_loops()
		t.tween_property(dy, "modulate:a", 0.25, 0.45)
		t.tween_property(dy, "modulate:a", 1.0, 0.45)
		dy.set_meta("tw", t)
	elif not dying and dy.visible:
		dy.visible = false
		if dy.has_meta("tw"):
			var t2: Tween = dy.get_meta("tw")
			if t2 != null and t2.is_valid():
				t2.kill()
			dy.remove_meta("tw")
	var dead_lbl := pn.get_node("Dead") as Label
	if not alive and not dead_lbl.visible:
		dead_lbl.visible = true
		if not fast and not auto_all:
			dead_lbl.scale = Vector2(2.2, 2.2)
			dead_lbl.modulate.a = 0.0
			var st := dead_lbl.create_tween().set_parallel(true)
			st.tween_property(dead_lbl, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			st.tween_property(dead_lbl, "modulate:a", 1.0, 0.2)
	elif alive and dead_lbl.visible:
		dead_lbl.visible = false
	if portrait != null:
		portrait.material = null if alive else gray_mat
	var ph := pn.get_node("PhaseTag") as Label
	var show_ph := alive and int(p["seat"]) == turn_seat and eng != null and String(eng.phase_text) != "" and not game_over
	ph.visible = show_ph
	if show_ph:
		ph.text = String(eng.phase_text)


func _sync_pips(pips: VBoxContainer, p: Dictionary) -> void:
	# 体力槽：节点复用；扣血时失去的那几格放大闪红后熄灭，回血时亮绿（对照无名杀 $damage/$recover 的体力条变化）
	var mx := int(p["max_hp"])
	var hp := maxi(0, int(p["hp"]))
	if pips.get_child_count() != mx:
		for chd in pips.get_children():
			pips.remove_child(chd)
			chd.queue_free()
		for i in mx:
			var dot := Panel.new()
			dot.custom_minimum_size = Vector2(21, 21)
			dot.pivot_offset = Vector2(10.5, 10.5)
			dot.mouse_filter = MOUSE_FILTER_IGNORE
			dot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			# V0.29：体力图标改为樱花（满=粉樱，失去=灰樱）
			var hl := TextureRect.new()
			hl.name = "Hl"
			hl.position = Vector2(-2, -2)
			hl.size = Vector2(25, 25)
			hl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			hl.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hl.mouse_filter = MOUSE_FILTER_IGNORE
			dot.add_child(hl)
			pips.add_child(dot)
		pips.set_meta("hp_shown", hp)
	var shown := int(pips.get_meta("hp_shown")) if pips.has_meta("hp_shown") else hp
	for i in mx:
		var dot := pips.get_child(i) as Panel
		var full := i < hp
		(dot.get_node("Hl") as TextureRect).texture = HP_FULL_TEX if full else HP_EMPTY_TEX
		var changed_pip := (i >= hp and i < shown) or (i >= shown and i < hp)
		if changed_pip and not fast and not auto_all:
			var lost := i >= hp
			dot.scale = Vector2(1.7, 1.7)
			dot.modulate = Color(1.0, 0.25, 0.25) if lost else Color(0.4, 1.0, 0.5)
			var tw: Tween = dot.create_tween().set_parallel(true)
			tw.tween_property(dot, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(dot, "modulate", Color.WHITE, 0.5)
	pips.set_meta("hp_shown", hp)


func _fx_reveal_gem(seat: int) -> void:
	# 阵亡亮身份：身份宝石翻面（横向缩到 0 再展开），刷新后显示真实身份
	var pn := seat_panel_of(seat)
	if pn == null or fast or auto_all:
		return
	var gem := pn.get_node_or_null("Gem") as Control
	if gem == null:
		return
	gem.pivot_offset = gem.size * 0.5
	var t: Tween = gem.create_tween()
	t.tween_property(gem, "scale:x", 0.0, 0.14)
	t.tween_property(gem, "scale", Vector2(1.35, 1.35), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(gem, "scale", Vector2.ONE, 0.12)


func _open_guess(seat_idx: int) -> void:
	# 身份猜测：弹出 主/忠/反/内/清除 小菜单（替代旧版循环切换；对照无名杀身份标记菜单）
	if guess_popup == null or targeting or game_mode != "identity":
		return
	var pn := seat_panel_of(seat_idx)
	if pn == null:
		return
	if guess_popup.visible and guess_popup_seat == seat_idx:
		guess_popup.visible = false
		guess_popup_seat = -1
		return
	guess_popup_seat = seat_idx
	var w := 5 * 58 + 4 * 6 + 16
	var x := clampf(pn.position.x + pn.size.x * 0.5 - w * 0.5, 8.0, vw - w - 8.0)
	guess_popup.position = Vector2(x, pn.position.y + 60)
	guess_popup.visible = true
	guess_popup.move_to_front()


func _pick_guess(mark: String) -> void:
	if guess_popup_seat > 0:
		if mark == "":
			guess_marks.erase(guess_popup_seat)
		else:
			guess_marks[guess_popup_seat] = mark
	guess_popup.visible = false
	guess_popup_seat = -1
	_queue_refresh()


func _build_guess_popup() -> void:
	guess_popup = PanelContainer.new()
	guess_popup.add_theme_stylebox_override("panel", style(Color(0.16, 0.10, 0.24, 0.94), 16, Color(1.0, 0.82, 0.45, 0.9), 2, true))
	guess_popup.visible = false
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	guess_popup.add_child(hb)
	for mk in ["主", "忠", "反", "内", ""]:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = mk if mk != "" else "清"
		b.custom_minimum_size = Vector2(58, 52)
		b.add_theme_font_override("font", font_bold)
		b.add_theme_font_size_override("font_size", 24)
		var m: String = mk
		b.pressed.connect(func() -> void: _pick_guess(m))  # 只隐藏弹层，不释放按钮（避免 V0.24 信号内释放）
		hb.add_child(b)
	add_child(guess_popup)


# ---------------- 基础工具 ----------------

func card_text(c: Dictionary) -> String:
	var suits_ch := {"红桃": "♥", "方块": "♦", "梅花": "♣", "黑桃": "♠"}
	return "%s %s%d" % [c["name"], suits_ch[c["suit"]], int(c["point"])]


func is_red(c: Dictionary) -> bool:
	return RED_SUITS.has(c["suit"])


func alive_players() -> Array:
	var out: Array = []
	for p in players:
		if p["alive"]:
			out.append(p)
	return out


func dist_between(a: int, b: int) -> int:
	if a == b:
		return 0
	var alive_seats: Array = []
	for p in alive_players():
		alive_seats.append(int(p["seat"]))
	var ia := alive_seats.find(a)
	var ib := alive_seats.find(b)
	var n := alive_seats.size()
	var d := absi(ia - ib)
	return mini(d, n - d)


const DELAYED_NAMES := ["落雷", "沉迷游戏", "断粮封锁", "草木疑兵", "浮雷"]
const ARMOR_NAMES := ["结界手环", "防护立场", "藤蔓铠甲", "银狮铠甲", "烂银铠甲"]


func card_kind(c: Dictionary) -> String:
	return CardDefs.kind_of(String(c["name"]))


func equip_name(p: Dictionary, slot: String) -> String:
	var e: Dictionary = p["equip"][slot]
	return String(e.get("name", "")) if not e.is_empty() else ""


func eff_dist(src: Dictionary, tgt: Dictionary) -> int:
	if int(src.get("nodist_seat", -1)) == int(tgt["seat"]):
		return 1
	var d := dist_between(int(src["seat"]), int(tgt["seat"]))
	if not (tgt["equip"]["plus"] as Dictionary).is_empty():
		d += 1
	if not (src["equip"]["minus"] as Dictionary).is_empty():
		d -= 1
	return maxi(d, 1)


func weapon_range(p: Dictionary) -> int:
	var w := equip_name(p, "weapon")
	var r := CardDefs.weapon_range_of(w) if w != "" else 1
	if (p.get("skills", []) as Array).has("podi"):
		r += 1
	return r


func attack_reachable(src: Dictionary, card: Dictionary, tgt: Dictionary) -> bool:
	if tgt.get("dream_guard", false):
		return false
	return eff_dist(src, tgt) <= weapon_range(src)


func all_target_cards(tgt: Dictionary) -> Array:
	# 返回 [{zone="hand"/"weapon"/..., card=...}]，供突然检查/悄悄借走选择区域
	var out: Array = []
	for c in tgt["hand"]:
		out.append({"zone": "hand", "card": c})
	for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
		var e: Dictionary = tgt["equip"][slot]
		if not e.is_empty():
			out.append({"zone": slot, "card": e})
	for c in tgt["judge"]:
		out.append({"zone": "delayed", "card": c})
	return out


func pname(p: Dictionary) -> String:
	if int(p["seat"]) == 0:
		return "你（%s）" % p["char"]["name"]
	return "%s（AI%d）" % [p["char"]["name"], int(p["seat"])]


func identity_visible(p: Dictionary) -> String:
	if game_mode != "identity":
		return String(p["identity"])
	if int(p["seat"]) == 0 or p["identity"] == "主公" or not p["alive"]:
		return p["identity"]
	return "？？"


# ---------------- 界面刷新 ----------------


# V0.31：座位/自己的头像改为 CG 裁切（以脸为中心的上半身），并按角色重建左侧竖排名牌（只在换角色时重建）
func _seat_cg(pn: Control, tr: TextureRect, ch: Dictionary, aspect: float, plate_pos: Vector2) -> void:
	if pn == null or tr == null:
		return
	var cid := String(ch.get("id", ""))
	if String(pn.get_meta("cg_id", "")) == cid:
		return
	pn.set_meta("cg_id", cid)
	tr.texture = Art.cg_crop(ch, aspect, 0.62, 0.32)
	var old := pn.get_node_or_null("Plate")
	var idx := -1
	if old != null:
		idx = old.get_index()
		pn.remove_child(old)
		old.queue_free()
	var pl := Art.name_plate(ch, 24, true)
	pl.position = plate_pos
	pn.add_child(pl)
	if idx >= 0:
		pn.move_child(pl, idx)


# V0.24 闪退修复（交接说明「安卓 15 选突击目标时应用自行关闭」的根因）：
# 旧版 refresh() 重建手牌行/技能按钮时对旧节点直接调用 free()。点击手牌「突击」进入选目标、点技能按钮、点装备牌时，
# 按钮的 pressed 信号处理函数会同步调用 refresh()，于是正在发射信号的按钮（及其父节点）在信号回调中途被立即释放，
# 信号返回后引擎继续访问已释放的按钮内存（use-after-free）。桌面调试版内存未被回收不一定崩，
# 安卓 release 版（Scudo 分配器/内存标记）会直接触发原生崩溃，表现为应用无报错自行关闭。
# 现统一改为 remove_child + queue_free（帧末才释放），并把引擎频繁的 changed() 合并为每帧最多一次刷新。
func refresh() -> void:
	if players.is_empty() or seat_panels.is_empty():
		return
	if eng != null:
		deck_label.text = "牌堆 %d" % eng.deck.size()
		disc_label.text = "弃牌 %d" % eng.discard_pile.size()
		round_label.text = "第 %d 轮" % round_no
	if turn_seat >= 0 and turn_seat < players.size():
		turn_label.text = "当前回合：%s" % pname(players[turn_seat])
	for panel in seat_panels:
		var seat_idx := int(panel.get_meta("seat"))
		var p: Dictionary = players[seat_idx]
		var tr: TextureRect = panel.get_node("Portrait")
		_seat_cg(panel, tr, p["char"], 236.0 / 358.0, Vector2(8, 66))
		var idt := identity_visible(p)
		var gem_text: Label = panel.get_node("Gem/GemText")
		gem_text.text = "?" if idt.begins_with("？") else idt.substr(0, 1)
		var chip_text: Label = panel.get_node("Chip/ChipText")
		var p_sh := int(p.get("shield", 0))
		chip_text.text = ("🛡%d ✋%d" % [p_sh, p["hand"].size()]) if p_sh > 0 else ("✋ %d" % p["hand"].size())
		(panel.get_node("Guess") as Control).visible = false
		var gm := String(guess_marks.get(seat_idx, ""))
		var gbtn := panel.get_node("GuessBtn") as Button
		gbtn.visible = game_mode == "identity" and bool(p["alive"]) and idt.begins_with("？")
		gbtn.text = gm if gm != "" else "猜"
		var info: Label = panel.get_node("Info")
		# V0.25/V0.33 距离与可达性动态角标（随当前选中的牌实时提示：突击/顺手/断粮/逐近弃远）
		if p["alive"]:
			var dd := eff_dist(players[0], p)
			var wr := weapon_range(players[0])
			var inr: bool = bool(players[0]["alive"]) and dd <= wr
			var tag_txt := "可攻击" if inr else "够不着(范围%d)" % wr
			var tag_ok := inr
			if not selected_card.is_empty():
				var scn := String(selected_card.get("name", ""))
				if scn == "悄悄借走" or scn == "断粮封锁":
					tag_ok = dd <= 1
					tag_txt = "距离1可达" if tag_ok else "需距离1"
				elif scn == "逐近弃远":
					tag_ok = true
					tag_txt = "近距·获得1张" if dd <= 1 else "远距·弃置1张"
				elif scn == "突击":
					tag_ok = inr and not bool(p.get("dream_guard", false))
					tag_txt = "星眠免疫" if bool(p.get("dream_guard", false)) else ("攻击可达" if inr else "距离不足")
			var mate_prefix := "★队友 · " if ((game_mode == "twovtwo" or game_mode == "boss") and String(p["identity"]) == String(players[0]["identity"])) else ("👑BOSS · " if (game_mode == "boss" and String(p["identity"]) == "魔王") else "")
			info.text = "%s距 %d · %s" % [mate_prefix, dd, tag_txt]
			info.modulate = Color(1, 0.96, 0.78, 1) if (not selected_card.is_empty() and tag_ok) else (Color(1, 1, 1, 1) if tag_ok else Color(0.72, 0.72, 0.78, 0.85))
		else:
			info.text = "已阵亡 · %s" % idt
			info.modulate = Color(1, 1, 1, 1)
		_sync_pips(panel.get_node("Pips") as VBoxContainer, p)
		_update_seat_overlays(panel, p, tr)
		# 边框与明暗：行动中高亮、可选中高亮、不可选中变暗、阵亡变灰
		var frame := C_GOLD
		if seat_idx == turn_seat and p["alive"]:
			frame = C_PINK_DEEP
		if targeting and target_candidates.has(seat_idx):
			frame = Color(0.30, 0.75, 0.40)
			if seat_idx == sel_target or seat_idx == extra_target:
				frame = Color(1.0, 0.70, 0.20)
		panel.add_theme_stylebox_override("normal", style(frame, 22, Color(1, 1, 1, 0.9), 2, true))
		panel.add_theme_stylebox_override("disabled", style(frame, 22, Color(1, 1, 1, 0.9), 2, true))
		if not p["alive"]:
			panel.modulate = Color(0.62, 0.62, 0.68, 0.85)
		elif targeting and not target_candidates.has(seat_idx):
			panel.modulate = Color(1, 1, 1, 0.45)
		else:
			panel.modulate = Color(1, 1, 1, 1)
		panel.disabled = not targeting
	if guess_popup != null and guess_popup.visible and targeting:
		guess_popup.visible = false
	# 座次表
	if seat_table_panel:
		seat_table_panel.visible = true
		var lines: Array = ["座次表"]
		for p in players:
			var s := int(p["seat"])
			var mark := "▶" if s == turn_seat else "　"
			var who := "（你）" if s == 0 else ""
			var st := ""
			if p["alive"]:
				st = "♥%d" % int(p["hp"])
			else:
				st = "阵亡"
			lines.append("%s%d号 %s%s %s %s" % [mark, s + 1, p["char"]["name"], who, identity_visible(p), st])
		seat_table_label.text = "\n".join(lines)
		for seat_key in glow_frames:
			(glow_frames[seat_key] as Control).visible = int(seat_key) == turn_seat and players[int(seat_key)]["alive"]
	# 自己
	var me: Dictionary = players[0]
	if me_panel_ref != null:
		var me_frame := C_GOLD
		if targeting and target_candidates.has(0):
			me_frame = Color(1.0, 0.70, 0.20) if sel_target == 0 or extra_target == 0 else Color(0.30, 0.75, 0.40)
		me_panel_ref.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.94), 22, me_frame, 5 if me_frame != C_GOLD else 3, true))
	if me_click_btn != null:
		me_click_btn.disabled = not (targeting and target_candidates.has(0))
		me_click_btn.mouse_filter = MOUSE_FILTER_STOP if not me_click_btn.disabled else MOUSE_FILTER_IGNORE
	_seat_cg(me_panel_ref, player_portrait, me["char"], 278.0 / 336.0, Vector2(8, 54))
	var hearts2 := ""
	for i in int(me["max_hp"]):
		hearts2 += "♥" if i < int(me["hp"]) else "♡"
	player_info.text = "%s · %s" % [String(me["char"].get("title", me["char"]["name"])), me["identity"]]
	var h_cnt: int = (me["hand"] as Array).size()
	var h_lim: int = maxi(int(me["hp"]), 0)
	var over_txt: String = ("（需弃%d）" % (h_cnt - h_lim)) if (h_cnt > h_lim and turn_seat == 0) else ""
	var me_sh: int = int(me.get("shield", 0))
	var sh_txt: String = ("🛡%d " % me_sh) if me_sh > 0 else ""
	me_hp_label.text = "%s%s %d/%d · 手牌 %d/%d%s" % [sh_txt, hearts2, int(me["hp"]), int(me["max_hp"]), h_cnt, h_lim, over_txt]
	# 自己的体力变化：数值条闪红/闪绿（座位体力槽同理）
	var me_hp := int(me["hp"])
	if me_hp_label.has_meta("hp_shown") and int(me_hp_label.get_meta("hp_shown")) != me_hp and not fast and not auto_all:
		var lost := me_hp < int(me_hp_label.get_meta("hp_shown"))
		me_hp_label.modulate = Color(1.6, 0.4, 0.4) if lost else Color(0.5, 1.6, 0.6)
		var mt: Tween = me_hp_label.create_tween()
		mt.tween_property(me_hp_label, "modulate", Color.WHITE, 0.6)
	me_hp_label.set_meta("hp_shown", me_hp)
	if me_panel_ref != null:
		_update_seat_overlays(me_panel_ref, me, player_portrait)
	_sync_hand()
	_update_action_bar()
	refresh_skill_buttons()


func make_hand_card(c: Dictionary) -> Control:
	# V0.25：牌面节点只在入手时建一次，之后选中/置灰/位置都在原节点上更新（_sync_hand / _apply_card_state）
	var wrap := Control.new()
	wrap.size = Vector2(CARD_W, CARD_H)
	wrap.custom_minimum_size = Vector2(CARD_W, CARD_H)
	wrap.pivot_offset = Vector2(CARD_W * 0.5, CARD_H)
	wrap.mouse_filter = MOUSE_FILTER_IGNORE
	var cb := Button.new()
	cb.focus_mode = Control.FOCUS_NONE
	cb.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb_norm := style(Color(1, 1, 1, 0.98), 14, C_GOLD, 2, true)
	cb.add_theme_stylebox_override("normal", sb_norm)
	cb.add_theme_stylebox_override("hover", sb_norm)
	cb.add_theme_stylebox_override("pressed", sb_norm)
	cb.add_theme_stylebox_override("disabled", sb_norm)
	wrap.set_meta("sb", sb_norm)
	_build_card_face(cb, c, Vector2(CARD_W, CARD_H), sb_norm)
	wrap.set_meta("frame_col", Art.frame_color(String(c["name"])))
	# 选中时的外发光（复用一个节点，显隐切换）
	var glow := Panel.new()
	glow.name = "Glow"
	glow.position = Vector2(-7, -7)
	glow.size = Vector2(CARD_W + 14, CARD_H + 14)
	glow.mouse_filter = MOUSE_FILTER_IGNORE
	glow.add_theme_stylebox_override("panel", style(Color(0, 0, 0, 0), 19, Color(1.0, 0.80, 0.30, 0.95), 5))
	glow.visible = false
	wrap.add_child(glow)
	var cref: Dictionary = c
	cb.gui_input.connect(func(event: InputEvent) -> void: _on_card_gui_input(wrap, event))
	cb.pressed.connect(func() -> void: _on_hand_card_clicked(cref))
	wrap.add_child(cb)
	wrap.move_child(cb, 0)
	wrap.set_meta("card", c)
	wrap.set_meta("intro", Callable(self, "_intro_card").bind(c))
	wrap.set_meta("state", "")
	return wrap


# V0.29 美术统一：卡面 = 类型色边框 + 原创卡图 + 左上花色点数 + 底部牌名/类型/属性/应变标签（docs/美术规范.md）
func _build_card_face(cb: Control, c: Dictionary, sz: Vector2, sb: StyleBoxFlat) -> void:
	var nm_text := String(c["name"])
	var fc := Art.frame_color(nm_text)
	sb.bg_color = fc
	sb.border_color = fc
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(int(round(sz.x * 0.08)))
	var k := sz.x / 172.0
	var art := TextureRect.new()
	art.name = "Art"
	art.position = Vector2(6, 6) * k
	art.size = Vector2(160, 168) * k
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = Art.card_tex(nm_text)
	art.mouse_filter = MOUSE_FILTER_IGNORE
	cb.add_child(art)
	# 左上：花色 + 点数（奶白圆角底）
	var red := is_red(c)
	var chip := Panel.new()
	chip.position = Vector2(8, 8) * k
	chip.size = Vector2(62, 34) * k
	chip.mouse_filter = MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", style(Color(1, 0.98, 0.95, 0.92), int(10 * k)))
	cb.add_child(chip)
	var top := lbl("%s%s" % [Art.suit_sym(String(c.get("suit", ""))), Art.point_str(int(c.get("point", 0)))], int(24 * k), Art.RED_SUIT if red else Art.BLACK_SUIT, true, HORIZONTAL_ALIGNMENT_CENTER)
	top.name = "Top"
	top.position = Vector2(0, -1) * k
	top.size = chip.size
	top.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.mouse_filter = MOUSE_FILTER_IGNORE
	chip.add_child(top)
	# 底部牌名条（类型色底）
	var plate := Panel.new()
	plate.position = Vector2(4, 176) * k
	plate.size = Vector2(164, 88) * k
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", style(fc, int(10 * k)))
	cb.add_child(plate)
	var nm := lbl(nm_text, int((28 if nm_text.length() <= 4 else 23) * k), C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	nm.name = "Name"
	nm.position = Vector2(0, 178) * k
	nm.size = Vector2(172, 38) * k
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.clip_text = true
	nm.mouse_filter = MOUSE_FILTER_IGNORE
	cb.add_child(nm)
	var nat := String(c.get("nature", ""))
	var kind_t := card_kind(c) + (("·" + nat) if nat != "" else "")
	var kind := lbl(kind_t, int(18 * k), Color(1, 0.95, 0.97, 0.92), false, HORIZONTAL_ALIGNMENT_CENTER)
	kind.name = "Kind"
	kind.position = Vector2(0, 216) * k
	kind.size = Vector2(172, 24) * k
	kind.autowrap_mode = TextServer.AUTOWRAP_OFF
	kind.clip_text = true
	kind.mouse_filter = MOUSE_FILTER_IGNORE
	cb.add_child(kind)
	if nat == "火" or nat == "雷" or nat == "冰":
		var ncol := Color(1.0, 0.55, 0.20) if nat == "火" else (Color(0.62, 0.45, 1.0) if nat == "雷" else Color(0.35, 0.72, 1.0))
		var nchip := Panel.new()
		nchip.position = Vector2(126, 8) * k
		nchip.size = Vector2(38, 34) * k
		nchip.mouse_filter = MOUSE_FILTER_IGNORE
		nchip.add_theme_stylebox_override("panel", style(ncol, int(10 * k)))
		cb.add_child(nchip)
		var nb := lbl(nat, int(21 * k), C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
		nb.size = nchip.size
		nb.autowrap_mode = TextServer.AUTOWRAP_OFF
		nb.mouse_filter = MOUSE_FILTER_IGNORE
		nchip.add_child(nb)
	var ybt: Array = c.get("yb", [])
	if not ybt.is_empty():
		var ybl := lbl("应变 " + "·".join(PackedStringArray(ybt)), int(15 * k), Color(1.0, 0.90, 0.55), true, HORIZONTAL_ALIGNMENT_CENTER)
		ybl.position = Vector2(0, 240) * k
		ybl.size = Vector2(172, 20) * k
		ybl.autowrap_mode = TextServer.AUTOWRAP_OFF
		ybl.clip_text = true
		ybl.mouse_filter = MOUSE_FILTER_IGNORE
		cb.add_child(ybl)


# ================= V0.25 手牌层与出牌手感 =================
# 对照无名杀：game/check.js（可选 selectable / 选中 selected 上浮）、ui/click cardtouchmove/windowtouchend（拖拽出牌）、
# ui.updatehl（重叠压缩）、配置 auto_confirm（点目标即确认）。

func _make_action_btn(text: String, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.custom_minimum_size = Vector2(196, 64)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.58))
	b.add_theme_stylebox_override("normal", style(bg, 32, Color(1, 1, 1, 0.85), 2, true))
	b.add_theme_stylebox_override("hover", style(bg.lightened(0.08), 32, Color(1, 1, 1, 0.95), 2, true))
	b.add_theme_stylebox_override("pressed", style(bg.darkened(0.08), 32, Color(1, 1, 1, 0.95), 2, false))
	b.add_theme_stylebox_override("disabled", style(Color(0.86, 0.84, 0.88, 0.82), 32, Color(1, 1, 1, 0.5), 2))
	var gl := Panel.new()
	gl.mouse_filter = MOUSE_FILTER_IGNORE
	gl.position = Vector2(10, 4)
	gl.size = Vector2(176, 24)
	gl.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.18), 12))
	b.add_child(gl)
	return b


func _hand_has(c: Dictionary) -> bool:
	if players.is_empty():
		return false
	for h in players[0]["hand"]:
		if is_same(h, c):
			return true
	return false


func _find_wrap(c: Dictionary) -> Control:
	for w in hand_cards:
		if is_instance_valid(w) and is_same(w.get_meta("card"), c):
			return w
	return null


func _deck_point() -> Vector2:
	# 牌堆胶囊中心（battle 本地坐标）
	return Vector2(vw - 520 + 78, 50)


func _sync_hand() -> void:
	if hand_row == null or players.is_empty():
		return
	var hand: Array = players[0]["hand"]
	var keep: Array = []
	for w in hand_cards:
		if not is_instance_valid(w):
			continue
		var c: Dictionary = w.get_meta("card")
		var still := false
		for h in hand:
			if is_same(h, c):
				still = true
				break
		if still:
			keep.append(w)
		else:
			if w == drag_wrap:
				_drag_reset()
			hand_row.remove_child(w)
			w.queue_free()  # V0.24 闪退修复：不得立即 free
	hand_cards = keep
	var ordered: Array = []
	for h in hand:
		var w := _find_wrap(h)
		if w == null:
			w = make_hand_card(h)
			hand_row.add_child(w)
			w.position = _deck_point() - hand_row.position - Vector2(CARD_W * 0.5, 0)
			w.scale = Vector2(0.5, 0.5)
			w.modulate.a = 0.0
			w.set_meta("fresh", true)
		ordered.append(w)
	hand_cards = ordered
	for i in ordered.size():
		if (ordered[i] as Node).get_index() != i:
			hand_row.move_child(ordered[i], i)
	# 选择状态随手牌变化校正
	discard_sel = discard_sel.filter(func(c: Dictionary) -> bool: return _hand_has(c))
	spear_cards = spear_cards.filter(func(c: Dictionary) -> bool: return _hand_has(c))
	if not selected_card.is_empty() and not _hand_has(selected_card):
		selected_card = {}
		sel_target = -1
		if not spear_targeting and not muniu_targeting:
			targeting = false
			target_candidates = []
	for w in ordered:
		_apply_card_state(w)
	_layout_hand(true)


func _is_lifted(w: Control) -> bool:
	var c: Dictionary = w.get_meta("card")
	if discard_mode:
		for d in discard_sel:
			if is_same(d, c):
				return true
		return false
	if asking and ask_sel_has and ask_sel_val is Dictionary and is_same(ask_sel_val, c):
		return true
	if skill_mode != "":
		return not skill_card.is_empty() and is_same(skill_card, c)
	if spear_targeting:
		for sc in spear_cards:
			if is_same(sc, c):
				return true
		return false
	return not selected_card.is_empty() and is_same(selected_card, c)


func _layout_hand(animate: bool) -> void:
	var n := hand_cards.size()
	if n == 0 or hand_row == null:
		return
	var avail := hand_row.size.x
	var step := CARD_W + 10.0
	if n > 1:
		step = minf(CARD_W + 10.0, (avail - CARD_W) / float(n - 1))
	step = maxf(step, 30.0)
	var total := CARD_W + step * float(n - 1)
	var x0 := maxf((avail - total) * 0.5, 0.0)
	var mid := float(n - 1) * 0.5
	var ang := 0.0 if mid <= 0.0 else minf(1.2, 7.0 / mid)
	var dip := 0.0 if mid <= 0.0 else 14.0 / (mid * mid)
	for i in n:
		var w: Control = hand_cards[i]
		if w == drag_wrap:
			continue
		var off := float(i) - mid
		var y := 8.0 + off * off * dip
		if _is_lifted(w):
			y -= LIFT
		_tween_card(w, Vector2(x0 + step * float(i), y), deg_to_rad(off * ang), animate)


func _tween_card(w: Control, pos: Vector2, rot: float, animate: bool) -> void:
	var key := "%d,%d,%d" % [int(pos.x), int(pos.y), int(rad_to_deg(rot) * 10.0)]
	var fresh := bool(w.get_meta("fresh", false))
	if String(w.get_meta("lay", "")) == key and not fresh:
		return
	w.set_meta("lay", key)
	var old: Variant = (w.get_meta("tw") if w.has_meta("tw") else null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	if not animate or fast or auto_all or not is_inside_tree():
		w.position = pos
		w.rotation = rot
		w.scale = Vector2.ONE
		w.modulate.a = 1.0
		w.set_meta("fresh", false)
		return
	var spring := bool(w.get_meta("spring", false))
	w.set_meta("spring", false)
	var tw := w.create_tween()
	tw.set_parallel(true)
	var dur := 0.34 if spring else 0.22
	var trans := Tween.TRANS_BACK if spring else Tween.TRANS_CUBIC
	tw.tween_property(w, "position", pos, dur).set_trans(trans).set_ease(Tween.EASE_OUT)
	tw.tween_property(w, "rotation", rot, dur)
	tw.tween_property(w, "scale", Vector2.ONE, dur)
	w.set_meta("fresh", false)
	if w.modulate.a < 1.0:
		tw.tween_property(w, "modulate:a", 1.0, 0.2)
	w.set_meta("tw", tw)


func _card_state_key(c: Dictionary) -> String:
	if discard_mode:
		return "d"
	if spear_targeting and not asking:
		return "r1"
	if not pick_cards.is_empty():
		for pc in pick_cards:
			if is_same(pc, c):
				return "r1"
		return "r0"
	if respond_name != "":
		return "r1" if String(c["name"]) == respond_name else "r0"
	if skill_mode != "" and not asking:
		return "r1" if _skill_card_ok(c) else "r0"
	if interactive and turn_seat == 0 and in_play_phase and not asking and not players.is_empty():
		return "u" if card_usable(players[0], c) else "x"
	return "i"


func _apply_card_state(w: Control) -> void:
	var c: Dictionary = w.get_meta("card")
	var st := _card_state_key(c)
	var lifted := _is_lifted(w)
	var key := st + ("L" if lifted else "")
	if String(w.get_meta("state", "")) == key:
		return
	w.set_meta("state", key)
	var cb := w.get_child(0) as Control
	if st == "x" or st == "r0":
		cb.modulate = Color(0.58, 0.58, 0.64, 0.9)
	elif st == "i":
		cb.modulate = Color(0.96, 0.96, 0.98, 1.0)
	else:
		cb.modulate = Color(1, 1, 1, 1)
	var sb: StyleBoxFlat = w.get_meta("sb")
	if lifted:
		sb.border_color = Color(1.0, 0.78, 0.30)
		sb.set_border_width_all(4)
	elif st == "r1":
		sb.border_color = Color(0.30, 0.80, 0.45)
		sb.set_border_width_all(4)
	else:
		sb.border_color = w.get_meta("frame_col", C_GOLD)
		sb.set_border_width_all(4)
	var glow := w.get_node_or_null("Glow") as Control
	if glow == null:
		return
	var gtw: Variant = (w.get_meta("gtw") if w.has_meta("gtw") else null)
	if gtw is Tween and (gtw as Tween).is_valid():
		(gtw as Tween).kill()
	glow.visible = lifted or st == "r1"
	glow.modulate.a = 1.0
	if glow.visible and not fast and not auto_all and is_inside_tree():
		var t := w.create_tween().set_loops()
		t.tween_property(glow, "modulate:a", 0.35, 0.5)
		t.tween_property(glow, "modulate:a", 1.0, 0.5)
		w.set_meta("gtw", t)


func _nudge_card(card: Dictionary) -> void:
	var w := _find_wrap(card)
	if w == null or fast or auto_all:
		return
	var base_x := w.position.x
	var tw := w.create_tween()
	tw.tween_property(w, "position:x", base_x + 8.0, 0.05)
	tw.tween_property(w, "position:x", base_x - 8.0, 0.08)
	tw.tween_property(w, "position:x", base_x, 0.06)


# ---------- 拖拽出牌 ----------

func _can_drag(w: Control) -> bool:
	if not interactive or turn_seat != 0 or game_over or asking or discard_mode or not in_play_phase:
		return false
	if spear_targeting or muniu_targeting or players.is_empty():
		return false
	var c: Dictionary = w.get_meta("card")
	return _hand_has(c) and card_usable(players[0], c)


func _on_card_gui_input(w: Control, event: InputEvent) -> void:
	if not is_instance_valid(w):
		return
	if _lp_swallowing():  # V0.26：长按说明触发后，本次按压不再参与拖拽/出牌
		drag_press = {}
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			drag_press = {"wrap": w, "pos": mb.global_position, "offset": mb.global_position - w.global_position}
		else:
			if drag_wrap == w:
				_drag_finish(mb.global_position)
			drag_press = {}
	elif event is InputEventMouseMotion and not drag_press.is_empty() and drag_press.get("wrap") == w:
		var mm := event as InputEventMouseMotion
		if drag_wrap == null:
			if (mm.global_position - Vector2(drag_press["pos"])).length() >= DRAG_START_PX and _can_drag(w):
				_drag_begin(w)
		if drag_wrap == w:
			_drag_move(mm.global_position)


func _drag_begin(w: Control) -> void:
	var c: Dictionary = w.get_meta("card")
	if selected_card.is_empty() or not is_same(selected_card, c):
		_select_card(c, false)  # 拖拽开始时的选中不触发自动确认（松手位置才决定出不出）
		if selected_card.is_empty() or not is_same(selected_card, c):
			return
	drag_wrap = w
	var old: Variant = (w.get_meta("tw") if w.has_meta("tw") else null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	w.rotation = 0.0
	w.scale = Vector2(1.06, 1.06)
	w.z_index = 20
	drag_hover_seat = -1
	if drag_line != null:
		drag_line.visible = true
		drag_line.clear_points()
	_apply_seat_frames()


func _drag_move(gp: Vector2) -> void:
	var w := drag_wrap
	if w == null or not is_instance_valid(w):
		return
	var c: Dictionary = w.get_meta("card")
	var card_pos: Vector2 = gp - Vector2(drag_press.get("offset", Vector2(CARD_W * 0.5, CARD_H * 0.5)))
	var hover := -1
	if card_needs_target(c):
		for s in target_candidates:
			var pn := seat_panel_of(int(s))
			if pn == null:
				continue
			if Rect2(pn.global_position, pn.size).grow(SNAP_PX).has_point(gp):
				hover = int(s)
				break
	if hover >= 0:
		# 吸附：牌向目标头像中心靠拢
		var pn2 := seat_panel_of(hover)
		var sc := pn2.global_position + pn2.size * 0.5 - Vector2(CARD_W, CARD_H) * 0.5
		card_pos = card_pos.lerp(sc, 0.38)
	if hover != drag_hover_seat:
		drag_hover_seat = hover
		sel_target = hover if hover >= 0 else (target_candidates[0] if target_candidates.size() == 1 else -1)
		_apply_seat_frames()
		_update_action_bar()
	w.global_position = card_pos
	if drag_line != null:
		var a := hand_row.position + Vector2(hand_row.size.x * 0.5, 40)
		var b := card_pos - global_position + Vector2(CARD_W * 0.5, CARD_H * 0.35)
		if hover >= 0:
			b = seat_center(hover)
		drag_line.points = PackedVector2Array([a, b])
		var release_ok := hover >= 0 or (not card_needs_target(c) and gp.y < hand_row.global_position.y - 30.0)
		drag_line.default_color = Color(0.45, 1.0, 0.55, 0.95) if release_ok else Color(1.0, 0.85, 0.45, 0.8)


func _drag_finish(gp: Vector2) -> void:
	var w := drag_wrap
	if w == null:
		return
	var c: Dictionary = w.get_meta("card")
	var hover := drag_hover_seat
	_drag_reset()
	drag_end_ms = Time.get_ticks_msec()
	var play := false
	var tgt := -1
	if card_needs_target(c):
		if hover >= 0:
			play = true
			tgt = hover
	elif gp.y < hand_row.global_position.y - 30.0:
		# V0.27：无目标牌拖出手牌区只算「选中」，仍需点「确定」（只有拖到合法目标头像上松手才直接打出）
		if is_instance_valid(w):
			w.set_meta("lay", "")
			w.set_meta("spring", true)
		if not is_same(selected_card, c):
			_select_card(c)
		else:
			_show_sel_hint()
			_maybe_auto_confirm()
		_layout_hand(true)
		return
	if is_instance_valid(w):
		w.set_meta("lay", "")
		w.set_meta("spring", not play)
	if play:
		_play_selected.call_deferred(c, tgt, -2)
	else:
		_layout_hand(true)


func _drag_reset() -> void:
	if drag_wrap != null and is_instance_valid(drag_wrap):
		drag_wrap.z_index = 0
	drag_wrap = null
	drag_hover_seat = -1
	if drag_line != null:
		drag_line.visible = false
	_apply_seat_frames()


# ---------- 选择 / 确认 ----------

func _select_card(card: Dictionary, allow_auto: bool = true) -> void:
	var me: Dictionary = players[0]
	var nm := String(card["name"])
	selected_card = card
	sel_anim_card = card
	sel_target = -1
	target_candidates = []
	targeting = false
	if card_needs_target(card):
		for p in candidates_for(me, card):
			target_candidates.append(int(p["seat"]))
		if target_candidates.is_empty():
			selected_card = {}
			show_hint("「%s」没有可选的目标" % nm)
			_queue_refresh()
			return
		targeting = true
		extra_target = -1
		if target_candidates.size() == 1:
			# 唯一合法目标：预先选好，但仍要点「确定」
			sel_target = int(target_candidates[0])
	_show_sel_hint()
	play_sfx("draw")
	_queue_refresh()
	if allow_auto:
		_maybe_auto_confirm()


func _play_selected(card: Dictionary, tgt_seat: int, extra: int = -1) -> void:
	if not interactive or turn_seat != 0 or game_over or players.is_empty() or asking:
		return
	var me: Dictionary = players[0]
	if not _hand_has(card) or unusable_reason(me, card) != "":
		cancel_targeting()
		return
	var needs := card_needs_target(card)
	if needs:
		var ok := false
		for p in candidates_for(me, card):
			if int(p["seat"]) == tgt_seat:
				ok = true
		if not ok:
			return
	var w := _find_wrap(card)
	if w != null:
		fly_from_hand = {"card": card, "pos": w.global_position - global_position + Vector2(CARD_W, CARD_H) * 0.5}
	targeting = false
	selected_card = {}
	target_candidates = []
	sel_target = -1
	extra_target = -1
	hide_prompt()
	interactive = false
	_update_action_bar()
	# 羁绊锁链：已在出牌前点选了第二个目标（或确认只连一人）时，引擎随后的「第二个目标」询问直接用这个选择
	pre_answers = []
	if String(card["name"]) == "羁绊锁链" and extra != -2:
		pre_answers.append({"kind": "chain2", "value": players[extra] if extra >= 0 and extra < players.size() else {}})
	if card_kind(card) in ["武器", "防具", "饰品", "宝物"]:
		eng.play_equip(me, card)
		show_played_card(card, pname(me), 0)
	elif needs:
		await execute_targeted_card(me, card, players[tgt_seat])
	else:
		await execute_simple_card(me, card)
	pre_answers = []
	fly_from_hand = {}
	if not game_over and is_inside_tree():
		interactive = true
		maybe_restore_hint()
		refresh()


func _on_confirm_pressed() -> void:
	# V0.27：「确定」是出牌/发动的唯一入口（拖到合法目标松手除外）
	if not _can_confirm():
		return
	if skill_mode != "":
		_commit_skill()
		return
	if spear_targeting:
		_commit_spear()
		return
	if muniu_targeting:
		_commit_muniu_give()
		return
	_play_selected(selected_card, sel_target, extra_target)


func _on_cancel_pressed() -> void:
	cancel_targeting()


func _on_end_play_btn() -> void:
	if not interactive:
		return
	if not selected_card.is_empty() or targeting or skill_mode != "":
		targeting = false
		spear_targeting = false
		spear_cards = []
		muniu_targeting = false
		selected_card = {}
		target_candidates = []
		sel_target = -1
		extra_target = -1
		skill_mode = ""
		skill_card = {}
	end_play_pressed.emit()


func _update_action_bar() -> void:
	if action_bar == null or confirm_btn == null:
		return
	var show_bar := in_play_phase and turn_seat == 0 and not asking and not game_over and not discard_mode
	action_bar.visible = show_bar
	if not show_bar:
		return
	confirm_btn.disabled = not _can_confirm()
	if recast_btn != null:
		var rc_ok: bool = skill_mode == "" and not spear_targeting and not muniu_targeting and not selected_card.is_empty() and eng != null and eng.can_recast(selected_card) and _hand_has(selected_card)
		recast_btn.visible = rc_ok
		recast_btn.disabled = not (rc_ok and interactive)
	if luck_btn != null:
		var lk_ok: bool = not tutorial and round_no <= 1 and luck_left > 0 and not players.is_empty() and not (players[0]["hand"] as Array).is_empty() and int(players[0].get("attack_count", 0)) == 0 and (players[0]["turn_used"] as Dictionary).is_empty()
		luck_btn.visible = lk_ok
		luck_btn.disabled = not (lk_ok and interactive)
		luck_btn.text = "手气卡×%d" % luck_left
	cancel_btn.disabled = not interactive or (selected_card.is_empty() and not targeting and skill_mode == "")
	end_play_btn.disabled = not interactive


func _apply_seat_frames() -> void:
	# 拖拽悬停的目标头像放大一点（吸附反馈）
	for panel in seat_panels:
		var s := int(panel.get_meta("seat"))
		var want := Vector2(1.06, 1.06) if s == drag_hover_seat else Vector2.ONE
		(panel as Control).pivot_offset = (panel as Control).size * 0.5
		(panel as Control).scale = want
	if me_panel_ref != null:
		me_panel_ref.pivot_offset = me_panel_ref.size * 0.5
		me_panel_ref.scale = Vector2(1.04, 1.04) if drag_hover_seat == 0 else Vector2.ONE


# ---------- 弃牌多选 ----------

func _toggle_discard(card: Dictionary) -> void:
	var idx := -1
	for i in discard_sel.size():
		if is_same(discard_sel[i], card):
			idx = i
	if idx >= 0:
		discard_sel.remove_at(idx)
	elif discard_sel.size() < discard_need:
		discard_sel.append(card)
	else:
		# 已选满：替换最早选的那张（手杀同款，省一次取消）
		discard_sel.remove_at(0)
		discard_sel.append(card)
	play_sfx("draw")
	_update_discard_ui()
	_queue_refresh()


func _update_discard_ui() -> void:
	if not discard_mode:
		return
	prompt_label.text = "%s（已选 %d/%d）" % [discard_prompt, discard_sel.size(), discard_need]
	if discard_confirm_btn != null and is_instance_valid(discard_confirm_btn):
		discard_confirm_btn.disabled = discard_sel.size() != discard_need


var discard_prompt := ""
var pick_cards: Array = []
var discard_auto_left := 0
var fly_from_hand: Dictionary = {}


func _default_answer(options: Array) -> Variant:
	for o in options:
		if bool((o as Dictionary).get("default", false)):
			return o["value"]
	for o in options:
		var v: Variant = o["value"]
		if v == null:
			return v
		if v is bool and not bool(v):
			return v
		if v is int and int(v) == -1:
			return v
		if v is Dictionary and (v as Dictionary).is_empty():
			return v
	if options.is_empty():
		return null
	return options[0]["value"]


func _start_countdown(seq: int) -> void:
	if ask_bar_tween and ask_bar_tween.is_valid():
		ask_bar_tween.kill()
	if ask_timeout <= 0.0 or auto_all or ask_bar_fill == null:
		if ask_bar_bg_ref != null:
			ask_bar_bg_ref.visible = false
		if ask_secs_label != null:
			ask_secs_label.visible = false
		return
	ask_bar_bg_ref.visible = true
	ask_secs_label.visible = true
	_countdown_tick(ask_timeout)
	ask_bar_tween = create_tween()
	# 倒计时按真实时间走：倍速（Engine.time_scale）下补偿时长
	ask_bar_tween.tween_method(_countdown_tick, ask_timeout, 0.0, ask_timeout * maxf(Engine.time_scale, 0.01))
	ask_bar_tween.tween_callback(func() -> void:
		if ask_seq == seq and asking:
			log_msg("（作答超时，已自动选择）")
			_on_decided(ask_default)
	)


func _countdown_tick(v: float) -> void:
	if ask_bar_fill == null:
		return
	ask_bar_fill.scale.x = clampf(v / maxf(ask_timeout, 0.01), 0.0, 1.0)
	ask_bar_fill.color = Color(0.95, 0.30, 0.35, 0.95) if v < 5.0 else Color(0.25, 0.90, 0.80, 0.95)
	if ask_secs_label != null:
		ask_secs_label.text = "%ds" % int(ceil(v))


# ================= V0.25 处理区与结算动画 =================
# 对照无名杀 player.$throw（牌飞入处理区）、$draw（牌堆飞入）、$judge / $phaseJudge（判定牌）、$equip、$addVirtualJudge。
# 处理区节点池复用（最多 PZ_MAX 张同时显示），空闲 PZ_IDLE 秒后整体淡出飞向弃牌堆。
const FX_CAP := 90  # 特效层节点上限：超过时跳过新的飘字类特效，防止堆积
const PZ_W := 140.0
const PZ_H := 218.0  # V0.29：与手牌同比例（172:268）
const PZ_MAX := 4
const PZ_IDLE := 1.7
var pz_pool: Array = []      # 复用的处理区牌节点
var pz_live: Array = []      # 当前显示中的（按时间顺序）
var pz_clear_tw: Tween = null
var pz_layer: Control = null
var nullify_chain: Array = []
var nullify_panel: PanelContainer = null
var nullify_label: Label = null


func _pz_center() -> Vector2:
	return Vector2(vw * 0.5, 300.0 + PZ_H * 0.5)


func _pz_make() -> Control:
	var root := Control.new()
	root.size = Vector2(PZ_W, PZ_H + 40)
	root.pivot_offset = Vector2(PZ_W * 0.5, PZ_H * 0.5)
	root.mouse_filter = MOUSE_FILTER_IGNORE
	var face := Panel.new()
	face.name = "Face"
	face.size = Vector2(PZ_W, PZ_H)
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.98), 12, C_GOLD, 3, true))
	root.add_child(face)
	# V0.29：牌面内容在 _pz_fill 里按牌重建（_build_card_face，与手牌同一套样式）
	# 牌背（判定翻面用）
	var back := Panel.new()
	back.name = "Back"
	back.size = Vector2(PZ_W, PZ_H)
	back.mouse_filter = MOUSE_FILTER_IGNORE
	back.add_theme_stylebox_override("panel", style(Color(0.36, 0.14, 0.30), 12, Art.GOLD, 3, true))
	var bkt := TextureRect.new()
	bkt.position = Vector2(4, 4)
	bkt.size = Vector2(PZ_W - 8, PZ_H - 8)
	bkt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bkt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bkt.texture = Art.back_tex()
	bkt.mouse_filter = MOUSE_FILTER_IGNORE
	back.add_child(bkt)
	back.visible = false
	root.add_child(back)
	# 结果印章（判定）
	var stamp := Label.new()
	stamp.name = "Stamp"
	stamp.add_theme_font_override("font", font_bold)
	stamp.add_theme_font_size_override("font_size", 40)
	stamp.add_theme_constant_override("outline_size", 12)
	stamp.add_theme_color_override("font_color", Color(1, 1, 1))
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.position = Vector2(-10, 60)
	stamp.size = Vector2(PZ_W + 20, 56)
	stamp.pivot_offset = Vector2((PZ_W + 20) * 0.5, 28)
	stamp.rotation = -0.22
	stamp.mouse_filter = MOUSE_FILTER_IGNORE
	stamp.visible = false
	root.add_child(stamp)
	# 说明条（谁 → 谁）
	var cap_bg := Panel.new()
	cap_bg.name = "CapBg"
	cap_bg.position = Vector2(-6, PZ_H + 6)
	cap_bg.size = Vector2(PZ_W + 12, 28)
	cap_bg.mouse_filter = MOUSE_FILTER_IGNORE
	cap_bg.add_theme_stylebox_override("panel", style(Color(0.16, 0.10, 0.22, 0.78), 15))
	root.add_child(cap_bg)
	var cap := lbl("", 15, Color(1, 0.96, 0.88), true, HORIZONTAL_ALIGNMENT_CENTER)
	cap.name = "Cap"
	cap.position = Vector2(-4, PZ_H + 9)
	cap.size = Vector2(PZ_W + 8, 22)
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.clip_text = true
	cap.mouse_filter = MOUSE_FILTER_IGNORE
	root.add_child(cap)
	return root


func _pz_take() -> Control:
	for n in pz_pool:
		if is_instance_valid(n) and not pz_live.has(n):
			return n
	if pz_pool.size() < PZ_MAX + 2:
		var n2 := _pz_make()
		pz_layer.add_child(n2)
		pz_pool.append(n2)
		return n2
	# 池满：回收最早的那张
	var oldest: Control = pz_live.pop_front()
	return oldest


func _pz_fill(n: Control, card: Dictionary, caption: String) -> void:
	n.set_meta("intro", Callable(self, "_intro_card").bind(card))
	var face := n.get_node("Face") as Panel
	for ch in face.get_children():
		face.remove_child(ch)
		ch.queue_free()
	var fsb := style(Color(1, 1, 1, 0.98), 12, C_GOLD, 3, true)
	face.add_theme_stylebox_override("panel", fsb)
	_build_card_face(face, card, Vector2(PZ_W, PZ_H), fsb)
	(n.get_node("Cap") as Label).text = caption
	(n.get_node("CapBg") as Control).visible = caption != ""
	(n.get_node("Back") as Control).visible = false
	(n.get_node("Face") as Control).visible = true
	(n.get_node("Stamp") as Control).visible = false
	n.modulate = Color(1, 1, 1, 1)


func _pz_slot(i: int, cnt: int) -> Vector2:
	var step := minf(PZ_W + 14.0, 470.0 / maxf(float(cnt), 1.0))
	var total := PZ_W + step * float(cnt - 1)
	var c := _pz_center()
	return Vector2(c.x - total * 0.5 + step * float(i), c.y - PZ_H * 0.5)


func _pz_relayout() -> void:
	var cnt := pz_live.size()
	for i in cnt:
		var n: Control = pz_live[i]
		if n.has_meta("flying") and bool(n.get_meta("flying")):
			continue
		var dst := _pz_slot(i, cnt)
		if fast:
			n.position = dst
			continue
		var tw := n.create_tween()
		tw.tween_property(n, "position", dst, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _pz_arm_clear() -> void:
	if pz_clear_tw and pz_clear_tw.is_valid():
		pz_clear_tw.kill()
	pz_clear_tw = create_tween()
	pz_clear_tw.tween_interval(0.05 if fast else PZ_IDLE)
	pz_clear_tw.tween_callback(_pz_clear)


func _pz_clear() -> void:
	# 结算完：处理区的牌缩小飞向弃牌堆并淡出
	var dst := Vector2(vw - 352 + 70, 50)
	for n in pz_live:
		if not is_instance_valid(n):
			continue
		n.set_meta("flying", false)
		if fast:
			n.visible = false
			continue
		var tw: Tween = n.create_tween().set_parallel(true)
		tw.tween_property(n, "position", dst - Vector2(PZ_W, PZ_H) * 0.25, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(n, "scale", Vector2(0.25, 0.25), 0.32)
		tw.tween_property(n, "modulate:a", 0.0, 0.32)
		tw.chain().tween_callback(func() -> void: if is_instance_valid(n): n.visible = false)
	pz_live.clear()
	_nullify_reset()


func _pz_add(card: Dictionary, caption: String, from_pos: Vector2) -> Control:
	if pz_layer == null or card.is_empty() or auto_all:
		return null
	var n := _pz_take()
	pz_live.erase(n)
	pz_live.append(n)
	while pz_live.size() > PZ_MAX:
		var old: Control = pz_live.pop_front()
		old.visible = false
	_pz_fill(n, card, caption)
	n.visible = true
	pz_layer.move_child(n, pz_layer.get_child_count() - 1)
	var cnt := pz_live.size()
	var dst := _pz_slot(cnt - 1, cnt)
	var old_tw: Variant = n.get_meta("tw") if n.has_meta("tw") else null
	if old_tw is Tween and (old_tw as Tween).is_valid():
		(old_tw as Tween).kill()
	if fast:
		n.position = dst
		n.scale = Vector2.ONE
		n.rotation = 0.0
	else:
		n.position = from_pos - Vector2(PZ_W, PZ_H) * 0.5
		n.scale = Vector2(0.6, 0.6)
		n.rotation = randf_range(-0.35, 0.35)
		n.set_meta("flying", true)
		var tw: Tween = n.create_tween().set_parallel(true)
		tw.tween_property(n, "position", dst, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "rotation", deg_to_rad(randf_range(-3.0, 3.0)), 0.30)
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(n):
				n.set_meta("flying", false)
				_pz_relayout())
		n.set_meta("tw", tw)
	_pz_relayout()
	_pz_arm_clear()
	return n


func judge_outcome(reason: String, c: Dictionary) -> Array:
	# 与引擎判定条件一致（engine.gd 判定阶段 / 结界手环 / 花愈），只用于显示印章
	var suit := String(c.get("suit", ""))
	var pt := int(c.get("point", 0))
	match reason:
		"落雷":
			return ["命中", false] if suit == "黑桃" and pt >= 2 and pt <= 9 else ["未命中", true]
		"浮雷":
			return ["命中", false] if suit == "黑桃" else ["未命中", true]
		"沉迷游戏":
			return ["生效", false] if suit != "红桃" else ["失效", true]
		"断粮封锁", "草木疑兵":
			return ["生效", false] if suit != "梅花" else ["失效", true]
		"结界手环", "花愈":
			return ["成功", true] if is_red(c) else ["失败", false]
	return ["", true]


func _pz_judge(seat: int, card: Dictionary, reason: String) -> void:
	var from := seat_center(seat) if seat >= 0 and seat < players.size() else _deck_point()
	var n := _pz_add(card, "%s判定" % reason, _deck_point().lerp(from, 0.3))
	if n == null:
		return
	var res := judge_outcome(reason, card)
	var stamp := n.get_node("Stamp") as Label
	stamp.text = String(res[0])
	stamp.add_theme_color_override("font_outline_color", Color(0.2, 0.62, 0.34) if bool(res[1]) else Color(0.86, 0.18, 0.28))
	if fast:
		stamp.visible = stamp.text != ""
		return
	# 先显示牌背，翻面露出牌面，再盖结果印章
	var face := n.get_node("Face") as Control
	var back := n.get_node("Back") as Control
	face.visible = false
	back.visible = true
	n.scale = Vector2(0.8, 0.8)
	var tw := n.create_tween()
	tw.tween_interval(0.34)
	tw.tween_property(n, "scale:x", 0.02, 0.12)
	tw.tween_callback(func() -> void:
		face.visible = true
		back.visible = false)
	tw.tween_property(n, "scale:x", 1.0, 0.14)
	if stamp.text != "":
		tw.tween_callback(func() -> void:
			stamp.visible = true
			stamp.scale = Vector2(2.0, 2.0)
			stamp.modulate.a = 0.0)
		tw.tween_property(stamp, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(stamp, "modulate:a", 1.0, 0.12)


# ---------- 看破链 ----------

func _nullify_reset() -> void:
	nullify_chain.clear()
	if nullify_panel != null:
		nullify_panel.visible = false


func _nullify_push(seat: int, negated: bool) -> void:
	if nullify_panel == null or auto_all:
		return
	var nm := String(players[seat]["char"]["name"]) if seat >= 0 and seat < players.size() else "?"
	nullify_chain.append("%s 打出「看破」→ %s" % [nm, "锦囊失效" if negated else "锦囊恢复生效"])
	var lines: Array = ["看破链"]
	var start := maxi(0, nullify_chain.size() - 5)
	for i in range(start, nullify_chain.size()):
		lines.append("%d. %s" % [i + 1, nullify_chain[i]])
	nullify_label.text = "\n".join(lines)
	nullify_panel.visible = true
	nullify_panel.modulate.a = 1.0


# ---------- 摸牌 / 装备 / 延时锦囊 ----------

func fx_draw_fly(seat: int, n: int) -> void:
	if fx_root == null or auto_all:
		return
	var from := _deck_point()
	var to := seat_center(seat)
	if seat == 0 and hand_row != null:
		to = hand_row.position + Vector2(hand_row.size.x * 0.5, 130)
	if not fast:
		var cnt := mini(n, 4)
		for i in cnt:
			var back := Panel.new()
			back.size = Vector2(60, 84)
			back.pivot_offset = Vector2(30, 42)
			back.position = from - Vector2(30, 42)
			back.mouse_filter = MOUSE_FILTER_IGNORE
			back.add_theme_stylebox_override("panel", style(Color(0.36, 0.30, 0.58), 8, Color(1.0, 0.82, 0.45), 2, true))
			fx_root.add_child(back)
			back.rotation = randf_range(-0.3, 0.3)
			var tw := back.create_tween()
			tw.tween_interval(0.08 * i)
			tw.tween_property(back, "position", to - Vector2(30, 42) + Vector2((i - cnt * 0.5) * 18.0, 0), 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(back, "rotation", 0.0, 0.36)
			tw.tween_property(back, "modulate:a", 0.0, 0.12)
			tw.tween_callback(back.queue_free)
	if seat != 0:
		fx_float(seat, "+%d" % n, Color(0.30, 0.55, 0.95), 40, 50.0)
	else:
		_fx_float_at(to + Vector2(0, -150), "摸 %d 张" % n, Color(0.30, 0.55, 0.95), 34)


func _fx_float_at(pos: Vector2, text: String, color: Color, fsize: int) -> void:
	if fx_root == null or fast or auto_all or fx_root.get_child_count() > FX_CAP:
		return
	var lb := lbl(text, fsize, color, true, HORIZONTAL_ALIGNMENT_CENTER)
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	lb.size = Vector2(260, 52)
	lb.pivot_offset = Vector2(130, 26)
	lb.position = pos - Vector2(130, 26)
	lb.mouse_filter = MOUSE_FILTER_IGNORE
	lb.add_theme_constant_override("outline_size", 8)
	lb.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
	fx_root.add_child(lb)
	lb.scale = Vector2(0.5, 0.5)
	var tw := lb.create_tween()
	tw.tween_property(lb, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lb, "position:y", lb.position.y - 40.0, 0.8)
	tw.tween_property(lb, "modulate:a", 0.0, 0.25)
	tw.tween_callback(lb.queue_free)


func fx_equip_fly(seat: int, nm: String) -> void:
	if fx_root == null or fast or auto_all:
		return
	var pn := seat_panel_of(seat)
	if pn == null:
		return
	var from := _pz_center()
	var to := pn.position + Vector2(pn.size.x * 0.5, pn.size.y * 0.62)
	if seat == 0 and me_panel_ref != null:
		to = me_panel_ref.position + Vector2(90, 120)
	var chip := PanelContainer.new()
	chip.mouse_filter = MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", style(Color(0.16, 0.14, 0.24, 0.92), 12, Color(1.0, 0.82, 0.45), 2, true))
	var cl := lbl("⚙ " + nm, 22, C_WHITE, true)
	cl.mouse_filter = MOUSE_FILTER_IGNORE
	chip.add_child(cl)
	fx_root.add_child(chip)
	chip.position = from - Vector2(70, 18)
	chip.scale = Vector2(1.3, 1.3)
	var tw := chip.create_tween()
	tw.tween_property(chip, "position", to - Vector2(70, 18), 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(chip, "scale", Vector2(0.9, 0.9), 0.42)
	tw.tween_property(chip, "modulate:a", 0.0, 0.2)
	tw.tween_callback(chip.queue_free)
	fx_target_ring(seat, Color(1.0, 0.82, 0.45))


func card_usable(me: Dictionary, c: Dictionary) -> bool:
	return unusable_reason(me, c) == ""


func unusable_reason(me: Dictionary, c: Dictionary) -> String:
	var n := String(c["name"])
	match n:
		"闪避":
			return "「闪避」只能在受到「突击」时打出"
		"特饮":
			# V0.24 修复：对照 noname jiu（usable: 1）每回合限用一次；旧版可连喝多张，多余的白白浪费
			if bool(me.get("drink_used", false)) or bool(me.get("drunk", false)):
				return "「特饮」每回合只能使用一次"
		"突击":
			if bool(me.get("used_attack", false)) and equip_name(me, "weapon") != "魔导连弩" and not bool(me.get("canyue_turn", false)):
				return "本回合已经使用过一张「突击」了"
			var has_t := false
			for p in alive_players():
				if int(p["seat"]) != 0 and attack_reachable(me, c, p):
					has_t = true
			if not has_t:
				return "攻击范围内没有目标（看看武器范围与距离）"
		"补给":
			# V0.28：对照无名杀「桃」——出牌阶段只能对自己使用（濒死求援时才能救别人）
			if int(me["hp"]) >= int(me["max_hp"]):
				return "体力已满，出牌阶段「补给」只能对自己使用"
		"突然检查":
			var any_c := false
			for p in alive_players():
				if int(p["seat"]) != 0 and not all_target_cards(p).is_empty():
					any_c = true
			if not any_c:
				return "没有可检查的目标"
		"悄悄借走":
			var any_s := false
			for p in alive_players():
				if int(p["seat"]) != 0 and eff_dist(me, p) <= 1 and not all_target_cards(p).is_empty():
					any_s = true
			if not any_s:
				return "距离 1 内没有可借走的目标"
		"单挑":
			if alive_players().size() < 2:
				return "没有可单挑的目标"
		"落雷", "浮雷":
			# V0.28：对照无名杀「闪电」——只能放进自己的判定区
			for d in me["judge"]:
				if String(d["name"]) == n:
					return "你的判定区已有「%s」" % n
		"沉迷游戏", "断粮封锁", "草木疑兵":
			var ok := false
			for p in alive_players():
				if int(p["seat"]) == 0:
					continue
				if n == "断粮封锁" and eff_dist(me, p) > 1:
					continue
				var dup := false
				for d in p["judge"]:
					if String(d["name"]) == n:
						dup = true
				if not dup:
					ok = true
			if not ok:
				return "距离 1 内没有可放置的目标" if n == "断粮封锁" else "所有目标身上都已有这张判定牌"
		"弃甲曳兵":
			var any_e := false
			for p in alive_players():
				if int(p["seat"]) == 0:
					continue
				for slot in ["weapon", "armor", "minus", "plus"]:
					if not (p["equip"][slot] as Dictionary).is_empty():
						any_e = true
			if not any_e:
				return "没有装备了牌的目标"
		"金蝉脱壳":
			return "「金蝉脱壳」只能在其他牌对你生效时响应使用"
		"出其不意":
			var any_q := false
			for p in alive_players():
				if int(p["seat"]) != 0 and not (p["hand"] as Array).is_empty():
					any_q = true
			if not any_q:
				return "没有持有手牌的目标"
		"逐近弃远":
			var any_z := false
			for p in alive_players():
				if int(p["seat"]) != 0 and not all_target_cards(p).is_empty():
					any_z = true
			if not any_z:
				return "没有可弃置或获得牌的目标"
		"看破":
			return "「看破」只能在锦囊生效前响应打出"
		"借力打力":
			var any_w := false
			for p in alive_players():
				if int(p["seat"]) != 0 and not (p["equip"]["weapon"] as Dictionary).is_empty():
					any_w = true
			if not any_w:
				return "没有装备武器的目标"
		"火焰试炼":
			var any_h := false
			for p in alive_players():
				if int(p["seat"]) != 0 and not (p["hand"] as Array).is_empty():
					any_h = true
			if not any_h:
				return "没有可试炼的目标（对方需要有手牌）"
	return ""


func refresh_skill_buttons() -> void:
	# V0.25 技能栏常驻（对照无名杀/十周年：技能按钮一直在，按 可用/已用/不可用 三态变色；锁定/被动技为小标签，点开看说明）。
	# 只有技能列表变化时才重建节点，平时仅改样式——不在每次 refresh 时整排 queue_free/new。
	if skill_btns == null:
		return
	var ents := _skill_entries()
	var keys: Array = []
	for e in ents:
		keys.append(String(e["key"]))
	var key_sig := "|".join(PackedStringArray(keys))
	if key_sig != skill_sig:
		skill_sig = key_sig
		for ch in skill_btns.get_children():
			skill_btns.remove_child(ch)
			ch.queue_free()  # V0.24 闪退修复：不得立即 free
		if skill_passives != null:
			for ch2 in skill_passives.get_children():
				skill_passives.remove_child(ch2)
				ch2.queue_free()
		for e in ents:
			if String(e["kind"]) == "passive":
				var pb := Button.new()
				pb.focus_mode = Control.FOCUS_NONE
				pb.text = String(e["text"])
				pb.add_theme_font_override("font", font_bold)
				pb.add_theme_font_size_override("font_size", 19)
				pb.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
				pb.add_theme_stylebox_override("normal", _tight(style(Color(0.30, 0.22, 0.45, 0.85), 14, Color(1.0, 0.82, 0.45, 0.8), 1, true), 10, 4))
				pb.add_theme_stylebox_override("hover", _tight(style(Color(0.38, 0.28, 0.56, 0.92), 14, Color(1.0, 0.82, 0.45, 0.95), 1, true), 10, 4))
				pb.add_theme_stylebox_override("pressed", _tight(style(Color(0.38, 0.28, 0.56, 0.92), 14, Color(1.0, 0.82, 0.45, 0.95), 1), 10, 4))
				var title := String(e["name"])
				var desc := String(e["desc"])
				pb.pressed.connect(func() -> void:
					if _lp_swallowing():
						return
					open_info_overlay("技能 · " + title, IntroPop.highlight(desc), true))
				pb.set_meta("key", e["key"])
				pb.set_meta("intro", Callable(self, "_intro_skill_sid").bind(String(e["key"]).substr(2)))
				skill_passives.add_child(pb)
				continue
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(230 if String(e["kind"]) != "muniu_store" else 300, 64)
			b.add_theme_font_override("font", font_bold)
			b.add_theme_font_size_override("font_size", 24)
			var gloss2 := Panel.new()
			gloss2.mouse_filter = MOUSE_FILTER_IGNORE
			gloss2.set_anchors_preset(Control.PRESET_TOP_WIDE)
			gloss2.size = Vector2(0, 26)
			gloss2.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.20), 24))
			b.add_child(gloss2)
			b.pressed.connect(e["cb"])
			b.set_meta("key", e["key"])
			if e.has("sid"):
				b.set_meta("intro", Callable(self, "_intro_skill_sid").bind(String(e["sid"])))
			elif String(e["kind"]) == "spear":
				b.set_meta("intro", Callable(self, "_intro_card").bind({"name": "合璧长枪"}))
			elif String(e["kind"]).begins_with("muniu"):
				b.set_meta("intro", Callable(self, "_intro_card").bind({"name": "木牛流马"}))
			skill_btns.add_child(b)
	# 样式/状态原地更新
	var bi := 0
	for e in ents:
		if String(e["kind"]) == "passive":
			continue
		if bi >= skill_btns.get_child_count():
			break
		var b2 := skill_btns.get_child(bi) as Button
		bi += 1
		var st := String(e["state"])
		var base: Color = e["color"]
		var sig2 := st + String(e["text"])
		if b2.has_meta("st") and String(b2.get_meta("st")) == sig2:
			continue
		b2.set_meta("st", sig2)
		b2.text = String(e["text"])
		b2.disabled = st != "ready" and st != "sel"
		var col := base
		var fcol := C_WHITE
		if st == "sel":
			col = Color(1.0, 0.72, 0.22)
			fcol = Color(0.25, 0.16, 0.05)
		elif st == "used":
			col = Color(0.55, 0.52, 0.60, 0.80)
			fcol = Color(1, 1, 1, 0.75)
		elif st == "idle":
			col = Color(base.r, base.g, base.b, 0.45)
			fcol = Color(1, 1, 1, 0.8)
		b2.add_theme_color_override("font_color", fcol)
		b2.add_theme_color_override("font_disabled_color", fcol)
		b2.add_theme_stylebox_override("normal", style(col, 32, Color(1, 1, 1, 0.98) if st == "sel" else Color(1, 1, 1, 0.75), 4 if st == "sel" else 2, st == "ready" or st == "sel"))
		b2.add_theme_stylebox_override("hover", style(col.lightened(0.08), 32, Color(1, 1, 1, 0.9), 2, true))
		b2.add_theme_stylebox_override("pressed", style(col.darkened(0.08), 32, Color(1, 1, 1, 0.9), 2, false))
		b2.add_theme_stylebox_override("disabled", style(col, 32, Color(1, 1, 1, 0.45), 2, false))


func _skill_entries() -> Array:
	var out: Array = []
	if players.is_empty() or eng == null:
		return out
	var me: Dictionary = players[0]
	var can_act := interactive and bool(me["alive"]) and turn_seat == 0
	var avail := {}
	if can_act:
		for d in eng.active_options(me):
			avail[String(d["sid"])] = true
	var texts := {}
	for sk in (me["char"].get("skills", []) as Array):
		texts[String(sk.get("sid", ""))] = String(sk.get("text", ""))
	for sid in (me["skills"] as Array):
		var def: Dictionary = eng.skill_lib.get(sid, {})
		if def.is_empty():
			continue
		var nm := String(def.get("name", sid))
		if def.has("active"):
			var is_lim := bool(def.get("limited", false))
			var is_sw := bool(def.get("switchable", false))
			var lim_used := is_lim and bool(me.get("limited_used_" + String(sid), false))
			var st := "ready" if avail.has(sid) else ("used" if (lim_used or bool((me["turn_used"] as Dictionary).get(sid, false))) else "idle")
			if st == "ready" and skill_mode == String(sid):
				st = "sel"
			var pref := "★限定 " if is_lim else ("☯" + ("阴 " if int(me.get("switch_" + String(sid), 0)) == 1 else "阳 ") if is_sw else "✦ ")
			var tx := (pref + nm) if st != "used" else ("✓ %s 已发动" % nm if lim_used else "✓ %s 已用" % nm)
			var bcol: Color = Color(0.88, 0.32, 0.28) if is_lim else (Color(0.48, 0.36, 0.86) if is_sw else C_PLATE)
			var sid_c := String(sid)
			out.append({"key": "a:" + sid_c, "sid": sid_c, "kind": "active", "state": st, "text": tx, "color": bcol, "cb": func() -> void: _on_skill_button(sid_c)})
		else:
			var is_awk := bool(def.get("awaken", false))
			var awk_done := is_awk and bool(me.get("awakened_" + String(sid), false))
			var p_txt := ("★已觉醒 " + nm) if awk_done else (("★觉醒 " + nm) if is_awk else nm)
			out.append({"key": "p:" + String(sid), "kind": "passive", "name": nm, "text": p_txt, "desc": String(texts.get(sid, String(def.get("text", "（被动技能，满足条件时自动触发或询问你是否发动）"))))})
	if not can_act:
		return out
	# 合璧长枪：两张手牌拼一张突击
	if equip_name(me, "weapon") == "合璧长枪" and (me["hand"] as Array).size() >= 2 and not bool(me.get("used_attack", false)):
		var has_t := false
		for p in alive_players():
			if int(p["seat"]) != 0 and attack_reachable(me, {"name": "突击"}, p):
				has_t = true
		if has_t:
			out.append({"key": "spear", "kind": "spear", "state": "sel" if spear_targeting else "ready", "text": "✦ 长枪突击", "color": Color(0.55, 0.42, 0.85), "cb": _on_spear_button})
	# 木牛流马：存粮 / 转运
	var trm: Dictionary = me["equip"]["treasure"]
	if not trm.is_empty() and String(trm["name"]) == "木牛流马":
		out.append({"key": "muniu_s", "kind": "muniu_store", "state": "ready", "text": "🌾 存粮（先选手牌）", "color": Color(0.45, 0.62, 0.35), "cb": _on_muniu_store})
		out.append({"key": "muniu_g", "kind": "muniu_give", "state": "sel" if muniu_targeting else "ready", "text": "🚚 转运木牛", "color": Color(0.45, 0.62, 0.35), "cb": _on_muniu_give})
	return out


# ---------------- 提问系统（真人点选 / AI 自动） ----------------

func _on_decided(value: Variant) -> void:
	decided.emit(value)


func maybe_restore_hint() -> void:
	if interactive and turn_seat == 0 and not game_over and in_play_phase:
		show_hint("你的出牌阶段：点牌选中后点「确定」，或把牌拖到目标上；灰色牌暂时用不了")


func ask(prompt: String, options: Array, on_built: Callable = Callable(), mode: String = "") -> Variant:
	# V0.24 修复：认输/对局结束后引擎协程收尾时不再弹出新的询问（否则会卡在无人应答的提问上，结算界面迟迟不出）
	if eng != null and eng.game_over:
		return null
	asking = true
	ask_seq += 1
	var my_seq := ask_seq
	prompt_panel.visible = true
	prompt_label.text = prompt
	for ch in prompt_btns.get_children():
		prompt_btns.remove_child(ch)
		ch.queue_free()
	# V0.27：选牌/选人类询问（mode=pick）与响应询问（mode=respond）改为「先选中，再确定」
	if mode == "":
		for opt in options:
			var ov0: Variant = (opt as Dictionary).get("value")
			if ov0 is Dictionary and not (ov0 as Dictionary).is_empty():
				mode = "pick"
				break
	ask_mode = mode
	ask_prompt = prompt
	ask_options = options
	ask_sel_has = false
	ask_sel_val = null
	ask_opt_btns = []
	ask_confirm_btn = null
	if mode == "pick" or mode == "respond":
		_build_select_ask(options)
		ask_default = _default_answer(options)
		if on_built.is_valid():
			on_built.call()
		_start_countdown(my_seq)
		_update_action_bar()
		_queue_refresh()
		var result2: Variant = await decided
		if ask_seq == my_seq:
			asking = false
			_ask_reset_sel()
			hide_prompt()
			maybe_restore_hint()
			_update_action_bar()
			_queue_refresh()
		return result2
	var first := true
	for opt in options:
		var lab := String(opt["label"])
		var b: Button
		if first and options.size() > 1:
			b = _make_action_btn(lab, C_GOLD, Color(0.25, 0.16, 0.05))
		else:
			b = _make_action_btn(lab, Color(1, 1, 1, 0.96), C_PINK_DEEP)
		first = false
		var tw_w := clampf(64.0 + lab.length() * 26.0, 150.0, 420.0)
		b.custom_minimum_size = Vector2(tw_w, 64)
		(b.get_child(0) as Control).size = Vector2(tw_w - 20, 24)
		if lab.length() > 10:
			b.add_theme_font_size_override("font_size", 22)
		var v: Variant = opt["value"]
		b.pressed.connect(func() -> void: _on_decided(v))
		_attach_option_intro(b, lab, v)
		prompt_btns.add_child(b)
	ask_default = _default_answer(options)
	if on_built.is_valid():
		on_built.call()
	_start_countdown(my_seq)
	_update_action_bar()
	_queue_refresh()
	var result: Variant = await decided
	if ask_seq == my_seq:
		asking = false
		hide_prompt()
		maybe_restore_hint()
		_update_action_bar()
		_queue_refresh()
	return result


func ask_choose_target(prompt: String, candidates: Array, allow_cancel: bool = true) -> int:
	var options: Array = []
	for p in candidates:
		options.append({"label": pname(p), "value": int(p["seat"])})
	if allow_cancel:
		options.append({"label": "取消", "value": -1})
	if options.is_empty():
		return -1
	var picked: Variant = await ask(prompt, options, Callable(), "pick")
	if picked is int or picked is float:
		return int(picked)
	return -1


# ---------------- 牌堆与开局 ----------------

func start_match(sim: bool) -> void:
	auto_all = sim
	fast = sim
	if tutorial:
		game_mode = "duel"
		my_role = "先手"
		difficulty = 0
		tut_step = 0
	match_players = 3 if game_mode == "doudizhu" else (2 if game_mode == "duel" else (4 if (game_mode == "twovtwo" or game_mode == "boss") else 5))
	game_over = false
	round_no = 1
	log_lines.clear()
	build_table()
	if fx_root != null:
		move_child(fx_root, get_child_count() - 1)
	var identities: Array
	var n := 5
	if game_mode == "doudizhu":
		n = 3
		match_players = 3
		identities = ["农民", "农民", "农民"]  # 地主由开局叫分决定（引擎 run_ddz_bidding）
	elif game_mode == "twovtwo":
		n = 4
		match_players = 4
		identities = ["红方", "蓝方", "蓝方", "红方"]
	elif game_mode == "boss":
		n = 4
		match_players = 4
		identities = ["联军", "联军", "魔王", "联军"]
	elif game_mode == "duel":
		n = 2
		match_players = 2
		identities = ["先手", "后手"] if my_role == "先手" else ["后手", "先手"]
	else:
		match_players = 5
		identities = ["主公", "忠臣", "反贼", "反贼", "内奸"]
		identities.shuffle()
	luck_left = 2
	lord_pre_char = {}
	var pool: Array = Characters.LIST.duplicate()
	pool.shuffle()
	if game_mode == "identity" and String(identities[0]) != "主公":
		lord_pre_char = pool[0]
	var cand_pool: Array = []
	for c in pool:
		if lord_pre_char.is_empty() or String(c["id"]) != String(lord_pre_char.get("id", "")):
			cand_pool.append(c)
	var human_candidates: Array = cand_pool.slice(0, mini(3, cand_pool.size()))
	var human_char: Dictionary
	if tutorial:
		human_char = _char_by_name("花宫雏")
	elif sim:
		human_char = human_candidates[0]
	else:
		human_char = await ask_pick_character(human_candidates, String(identities[0]))
	var rest: Array = []
	for c in pool:
		if String(c["id"]) != String(human_char["id"]) and (lord_pre_char.is_empty() or String(c["id"]) != String(lord_pre_char.get("id", ""))):
			rest.append(c)
	rest.shuffle()
	var seat_chars: Array = [human_char]
	var r_idx := 0
	for i in range(1, n):
		if game_mode == "identity" and String(identities[i]) == "主公" and not lord_pre_char.is_empty():
			seat_chars.append(lord_pre_char)
		else:
			seat_chars.append(rest[r_idx % rest.size()])
			r_idx += 1
	if tutorial:
		seat_chars = [human_char, _char_by_name("柚木铃奈")]
	var char_list: Array = []
	for i in n:
		var cd: Dictionary = seat_chars[i]
		var sk: Array = []
		for s in cd["skills"]:
			sk.append(String((s as Dictionary)["sid"]))
		char_list.append({"name": String(cd["name"]), "hp": int(cd["hp"]), "skills": sk, "char": cd})
	eng = EngineScript.new()
	eng.set_ui({
		"is_human": Callable(self, "_eng_is_human"),
		"log": Callable(self, "_eng_log"),
		"changed": Callable(self, "_eng_changed"),
		"pace": Callable(self, "_eng_pace"),
		"played": Callable(self, "_eng_played"),
		"fx": Callable(self, "_eng_fx"),
		"ask_skill": Callable(self, "_eng_ask_skill"),
		"ask_respond": Callable(self, "_eng_ask_respond"),
		"ask_save": Callable(self, "_eng_ask_save"),
		"resp_pref": Callable(self, "_eng_resp_pref"),
		"pick_card": Callable(self, "_eng_pick_card"),
		"pick_target": Callable(self, "_eng_pick_target"),
		"pick_option": Callable(self, "_eng_pick_option"),
		"pick_from_hand": Callable(self, "_eng_pick_from_hand"),
		"choose_discard": Callable(self, "_eng_choose_discard"),
		"play_phase": Callable(self, "_eng_play_phase"),
	})
	eng.load_skills()
	eng.difficulty = difficulty
	eng.mode = game_mode
	if game_mode == "duel":
		eng.duel_first_seat = identities.find("先手")
	eng.setup_game(char_list, identities)
	players = eng.players
	if tutorial:
		_tut_rig()
	turn_seat = 0
	var first_id := "主公" if game_mode == "identity" else ("地主" if game_mode == "doudizhu" else ("红方" if game_mode == "twovtwo" else ("联军" if game_mode == "boss" else "先手")))
	for p in players:
		if p["identity"] == first_id:
			turn_seat = int(p["seat"])
			break
	if game_mode == "duel":
		log_msg("对局开始！你执【%s】，角色是【%s】。" % [identities[0], human_char["name"]])
	elif game_mode == "twovtwo":
		log_msg("对局开始！欢乐 2v2：你（1号位）与 4号位【%s】同属红方阵营。" % String(players[3]["char_name"]))
	elif game_mode == "boss":
		log_msg("对局开始！魔王挑战：你与 2号位【%s】、4号位【%s】组成联军，讨伐 3号位 8血魔王【%s】！" % [String(players[1]["char_name"]), String(players[3]["char_name"]), String(players[2]["char_name"])])
	elif game_mode == "doudizhu":
		log_msg("对局开始！你的角色是【%s】，先叫分决定地主。" % human_char["name"])
	else:
		log_msg("对局开始！你的身份是【%s】，角色是【%s】。" % [identities[0], human_char["name"]])
	for p in players:
		if p["identity"] == "主公":
			log_msg("主公是 %s。" % pname(p))
	refresh()
	_update_music_scene()
	await wait(0.8)
	run_game()


func ask_pick_character(candidates: Array, my_identity: String) -> Dictionary:
	var goals := {
		"主公": "目标：消灭所有反贼和内奸。你的身份是公开的，体力上限 +1。",
		"忠臣": "目标：保护主公，消灭反贼和内奸。",
		"反贼": "目标：击杀主公。主公阵亡即获胜。",
		"内奸": "目标：先除掉反贼与忠臣，最后与主公单挑获胜。",
		"地主": "目标：击杀两名农民。你先手出牌、起手 5 张，拥有技能「飞扬」「跋扈」与护身「地契」。",
		"农民": "目标：与另一名农民合力击杀地主。地主阵亡即获胜。",
		"先手": "目标：击杀对手。先手出牌，起手 3 张牌。",
		"后手": "目标：击杀对手。后手出牌，起手 4 张牌。",
		"红方": "目标：与 4 号位队友合力击败 2·3 号位蓝方两名对手（长按队友头像可看队友手牌，队友阵亡摸 1 张）。",
		"联军": "目标：与 2·4 号位两名联军队友合力击败 3 号位 8 体力大魔王（长按队友或点「记牌」可看全体队友手牌）。",
	}
	var word := "先后手" if game_mode == "duel" else "身份"
	if game_mode == "doudizhu":
		draft_banner.text = "斗地主：开局叫分决定地主\n轮流叫 1~3 倍，价高者成为地主（先手、起手 5 张，带「飞扬」「跋扈」「地契」）；两名农民合力围攻地主。"
	else:
		var lord_line := ""
		if game_mode == "identity" and my_identity != "主公" and not lord_pre_char.is_empty():
			lord_line = "　｜　主公将面：【%s】（%d体力）" % [String(lord_pre_char["name"]), int(lord_pre_char["hp"]) + 1]
		draft_banner.text = "你的%s：【%s】%s\n%s" % [word, my_identity, lord_line, String(goals.get(my_identity, ""))]
	draft_banner.visible = true
	draft_my_identity = my_identity
	for n in table_nodes:
		(n as Control).visible = false
	turn_label.text = "开局选将"
	draft_layer.visible = true
	diff_layer.visible = true
	_populate_draft_cards(candidates, my_identity)
	var picked: Variant = await decided
	if free_pick_overlay != null and is_instance_valid(free_pick_overlay):
		free_pick_overlay.visible = false
	draft_layer.visible = false
	diff_layer.visible = false
	draft_banner.visible = false
	for n in table_nodes:
		(n as Control).visible = true
	for ch in draft_layer.get_children():
		draft_layer.remove_child(ch)
		ch.queue_free()
	return picked


func _populate_draft_cards(candidates: Array, my_identity: String) -> void:
	for ch in draft_layer.get_children():
		draft_layer.remove_child(ch)
		ch.queue_free()
	var hp_bonus := 1 if my_identity == "主公" else 0
	var card_idx := 0
	for c in candidates:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(400, 470)
		b.add_theme_stylebox_override("normal", style(Color(1, 1, 1, 0.95), 22, C_GOLD, 3, true))
		b.add_theme_stylebox_override("hover", style(Color(1, 0.97, 0.98, 1.0), 22, C_PINK_DEEP, 3, true))
		b.add_theme_stylebox_override("pressed", style(Color(1, 0.93, 0.95, 1.0), 22, C_PINK_DEEP, 3, false))
		var vb := VBoxContainer.new()
		vb.mouse_filter = MOUSE_FILTER_IGNORE
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = 16
		vb.offset_right = -16
		vb.offset_top = 8
		vb.add_theme_constant_override("separation", 4)
		# V0.31：选将卡改为完整 CG 卡面（竖排名牌 + 体力樱花，主公体力 +1 一并显示）
		var cdisp: Dictionary = (c as Dictionary).duplicate()
		cdisp["hp"] = int(c["hp"]) + hp_bonus
		var ccard := Art.cg_card(cdisp, Vector2(368, 300), {"zoom": 0.58, "face_y": 0.32, "fs": 27})
		ccard.name = "DraftCG"
		vb.add_child(ccard)
		for s in c["skills"]:
			# V0.24 修复：技能说明过长时溢出选将卡底边、压到下方「AI 难度」按钮（完整说明可在人物图鉴查看）
			var desc := String(s["text"])
			if desc.length() > 40:
				desc = desc.substr(0, 40) + "…"
			var sk := lbl("【%s】%s" % [s["name"], desc], 19, C_INK_SOFT, false)
			sk.mouse_filter = MOUSE_FILTER_IGNORE
			sk.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			vb.add_child(sk)
		b.clip_contents = true
		b.add_child(vb)
		# 选将演出：入场逐张淡入、悬停放大、点选时金光脉冲后再确认（向手杀选将靠拢）
		b.pivot_offset = Vector2(200, 235)
		b.modulate.a = 0.0
		var idx_now := card_idx
		card_idx += 1
		b.mouse_entered.connect(func() -> void:
			var tw := create_tween().bind_node(b)
			tw.tween_property(b, "scale", Vector2(1.03, 1.03), 0.14))
		b.mouse_exited.connect(func() -> void:
			var tw := create_tween().bind_node(b)
			tw.tween_property(b, "scale", Vector2.ONE, 0.14))
		var cref: Dictionary = c
		b.set_meta("intro", IntroPop.char_spec(c))
		b.pressed.connect(func() -> void:
			var tw := create_tween().bind_node(b)
			tw.tween_property(b, "scale", Vector2(1.07, 1.07), 0.09)
			tw.tween_property(b, "scale", Vector2(1.02, 1.02), 0.12)
			await tw.finished
			if is_instance_valid(b):
				_on_decided(cref))
		draft_layer.add_child(b)
		var tin := create_tween().bind_node(b)
		tin.tween_interval(0.09 * idx_now)
		tin.tween_property(b, "modulate:a", 1.0, 0.28)


# ---------------- 对局主循环 ----------------

func run_game() -> void:
	if not auto_all:
		show_match_banner()
		_maybe_first_hint()
		await wait(1.0)
	await eng.run_game()
	round_no = eng.round_no
	if auto_all:
		var f := FileAccess.open("/tmp/ask_sim_result.txt", FileAccess.WRITE)
		f.store_string("finished rounds=%d winner_log=%s" % [round_no, eng.winner_text])
		f.close()
		get_tree().quit()
		return
	end_game(eng.winner_text)


# ---------------- 对局结束 ----------------

func end_game(text: String) -> void:
	if game_over:
		return
	game_over = true
	interactive = false
	var your_result := ""
	if players.size() > 0:
		var my_id := String(players[0]["identity"])
		if text.contains("主公阵营获胜"):
			your_result = "你赢了！" if my_id in ["主公", "忠臣"] else "你输了。"
		elif text.contains("反贼阵营获胜"):
			your_result = "你赢了！" if my_id == "反贼" else "你输了。"
		elif text.contains("内奸"):
			your_result = "你赢了！" if my_id == "内奸" else "你输了。"
		if game_mode == "duel":
			# V0.24 修复：单挑认输时自己仍存活，旧版按「是否存活」判定会显示「你赢了！」
			var me_name: String = eng.pname(players[0]) if eng != null else ""
			your_result = "你赢了！" if me_name != "" and text.contains(me_name) else "你输了。"
		elif game_mode == "doudizhu":
			if text.contains("地主获胜"):
				your_result = "你赢了！" if my_id == "地主" else "你输了。"
			elif text.contains("农民阵营获胜"):
				your_result = "你赢了！" if my_id == "农民" else "你输了。"
		elif game_mode == "twovtwo":
			if text.contains("红方获胜"):
				your_result = "你赢了！" if my_id == "红方" else "你输了。"
			elif text.contains("蓝方获胜"):
				your_result = "你赢了！" if my_id == "蓝方" else "你输了。"
		elif game_mode == "boss":
			if text.contains("联军获胜"):
				your_result = "你赢了！" if my_id == "联军" else "你输了。"
			elif text.contains("魔王获胜"):
				your_result = "你赢了！" if my_id == "魔王" else "你输了。"
	if text.contains("未分胜负"):
		your_result = "平局"
	log_msg("对局结束：%s %s" % [text, your_result])
	turn_label.text = "对局结束"
	meta_result = {}
	if not auto_all and players.size() > 0:
		meta_result = _record_meta(text, your_result)
	if your_result == "你赢了！":
		play_sfx("win")
	elif your_result == "你输了。":
		play_sfx("lose")
	if auto_all:
		return
	hide_prompt()
	build_settlement(text, your_result)
	refresh()


# ---------------- V0.30 教学关：脚本化单挑 ----------------
# 固定花宫雏（先手）对柚木铃奈（简单 AI，体力 2），起手发好「星光长剑/突击/闪避/补给」，
# 按步骤提示：装备 → 选突击 → 选目标 → 确定 → 结束回合 → 对手回合响应 → 自由练习。完成（分出胜负）记「新手毕业」。
var tut_step := 0
var tut_saw_enemy_turn := false  # V0.32：教学第 4 步保持到对手回合响应结束，不再只闪一句文字
var tut_panel: PanelContainer = null
var tut_label: Label = null
var tut_timer: Timer = null
const TUT_TEXT := [
	"教学 1/5：点手牌里的「星光长剑」选中它，再点「确定」装备（装备后攻击范围变大）。",
	"教学 2/5：点「突击」选中，然后点对手的头像，把她选为目标。",
	"教学 3/5：点「确定」出牌。对手没有「闪避」就会受到 1 点伤害。",
	"教学 4/5：没有要出的牌了，点「结束」结束回合。对手回合里如果对你出「突击」，点亮的「闪避」会提示你抵挡：点它选中，再点「确定」。",
	"教学 5/5：自由练习！击败对手就能毕业。长按任意牌或角色可以看说明。",
]


func _char_by_name(nm: String) -> Dictionary:
	for c in Characters.LIST:
		if String(c["name"]) == nm:
			return c
	return Characters.LIST[0]


func _tut_rig() -> void:
	var me: Dictionary = players[0]
	for c in (me["hand"] as Array).duplicate():
		(me["hand"] as Array).erase(c)
		eng.deck.append(c)
	for want in ["星光长剑", "突击", "闪避", "补给"]:
		for c in eng.deck:
			if String(c["name"]) == want:
				eng.deck.erase(c)
				(me["hand"] as Array).append(c)
				break
	var foe: Dictionary = players[1]
	foe["hp"] = 2
	# V0.32：保证首个对手回合有「突击」，第 4 步能真正进入一次响应练习
	var foe_has_attack := false
	for c in foe["hand"]:
		if String(c["name"]) == "突击":
			foe_has_attack = true
	if not foe_has_attack and not (foe["hand"] as Array).is_empty():
		var back: Dictionary = (foe["hand"] as Array).pop_back()
		eng.deck.append(back)
		for c in eng.deck:
			if String(c["name"]) == "突击":
				eng.deck.erase(c)
				(foe["hand"] as Array).append(c)
				break
	if tut_timer == null:
		tut_timer = Timer.new()
		tut_timer.wait_time = 0.3
		tut_timer.timeout.connect(_tut_tick)
		add_child(tut_timer)
	tut_timer.start()
	_tut_show(0)


func _tut_show(i: int) -> void:
	tut_step = i
	if tut_panel == null or not is_instance_valid(tut_panel):
		tut_panel = PanelContainer.new()
		tut_panel.mouse_filter = MOUSE_FILTER_IGNORE
		tut_panel.add_theme_stylebox_override("panel", style(Color(1.0, 0.97, 0.94, 0.96), 20, Art.BLOSSOM_DEEP, 3, true))
		# 放在左上空白区（对手座位与己方立绘之间），不挡座位与出牌提示条
		var tw := minf(760.0, vw / 2.0 - 190.0)
		tut_panel.position = Vector2(40, 190)
		tut_panel.custom_minimum_size = Vector2(tw, 0)
		tut_panel.size = Vector2(tw, 0)
		var mg := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			mg.add_theme_constant_override("margin_" + side, 14)
		mg.mouse_filter = MOUSE_FILTER_IGNORE
		tut_panel.add_child(mg)
		tut_label = lbl("", 26, C_INK, true, HORIZONTAL_ALIGNMENT_LEFT)
		tut_label.mouse_filter = MOUSE_FILTER_IGNORE
		tut_label.custom_minimum_size = Vector2(tw - 28.0, 0)
		mg.add_child(tut_label)
		add_child(tut_panel)
	tut_label.text = TUT_TEXT[clampi(i, 0, TUT_TEXT.size() - 1)]
	move_child(tut_panel, get_child_count() - 1)


func _tut_tick() -> void:
	if not tutorial or players.is_empty() or eng == null:
		return
	if game_over:
		tut_timer.stop()
		if tut_panel != null and is_instance_valid(tut_panel):
			tut_panel.visible = false
		return
	var me: Dictionary = players[0]
	match tut_step:
		0:
			if not (me["equip"]["weapon"] as Dictionary).is_empty():
				_tut_show(1)
		1:
			if not selected_card.is_empty() and String(selected_card.get("name", "")) == "突击" and sel_target == 1:
				_tut_show(2)
			elif bool(me["used_attack"]):
				_tut_show(3)
		2:
			if bool(me["used_attack"]):
				_tut_show(3)
		3:
			if turn_seat == 1 and not tut_saw_enemy_turn:
				tut_saw_enemy_turn = true
				_tut_show(3)
			elif turn_seat == 0 and tut_saw_enemy_turn:
				_tut_show(4)


# V0.30 局外：记录战绩/熟练度/成就（教学关只记完成标记）
var meta_result: Dictionary = {}


func _record_meta(text: String, your_result: String) -> Dictionary:
	if tutorial:
		var got := Meta.mark_tutorial()
		return {"new_ach": got}
	var me: Dictionary = players[0]
	var res := "win" if your_result == "你赢了！" else ("lose" if your_result == "你输了。" else "draw")
	var mvi := _mvp_info(text)
	return Meta.record({
		"mode": game_mode, "char": String(me["char_name"]), "identity": String(me["identity"]),
		"result": res, "rounds": int(eng.round_no) if eng != null else 0,
		"dmg": int(me.get("stat_damage", 0)), "kills": int(me.get("stat_kills", 0)),
		"heal": int(me.get("stat_heal", 0)), "taken": int(me.get("stat_taken", 0)),
		"mvp": int(mvi[0]) == 0,
	})


func _mvp_info(winner_text: String) -> Array:
	var mvp_seat := -1
	var mvp_score := -1.0
	for p in players:
		var idn := String(p["identity"])
		var in_win := false
		if winner_text.contains("主公阵营"):
			in_win = idn in ["主公", "忠臣"]
		elif winner_text.contains("反贼阵营"):
			in_win = idn == "反贼"
		elif winner_text.contains("内奸"):
			in_win = idn == "内奸" and bool(p["alive"])
		elif winner_text.contains("地主获胜"):
			in_win = idn == "地主"
		elif winner_text.contains("农民阵营"):
			in_win = idn == "农民"
		elif winner_text.contains("红方获胜"):
			in_win = idn == "红方"
		elif winner_text.contains("蓝方获胜"):
			in_win = idn == "蓝方"
		elif winner_text.contains("联军获胜"):
			in_win = idn == "联军"
		elif winner_text.contains("魔王获胜"):
			in_win = idn == "魔王"
		elif game_mode == "duel":
			in_win = bool(p["alive"])
		var sc := float(int(p.get("stat_damage", 0))) + 3.0 * float(int(p.get("stat_kills", 0))) + 0.8 * float(int(p.get("stat_heal", 0)))
		if in_win and sc > mvp_score:
			mvp_score = sc
			mvp_seat = int(p["seat"])
	return [mvp_seat, mvp_score]


func build_settlement(winner_text: String, your_result: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.16, 0.05, 0.12, 0.55)
	dim.position = Vector2.ZERO
	dim.size = Vector2(vw, 1080)
	add_child(dim)
	settlement_layer = dim
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.97), 26, C_GOLD, 3, true))
	panel.position = Vector2(vw / 2.0 - 570, 110)
	panel.size = Vector2(1140, 860)
	dim.add_child(panel)
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 44)
	mg.add_theme_constant_override("margin_right", 44)
	mg.add_theme_constant_override("margin_top", 30)
	mg.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(mg)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	mg.add_child(vb)
	var win := your_result == "你赢了！"
	var title := lbl(your_result if your_result != "" else winner_text, 62, C_PINK_DEEP if win else Color(0.45, 0.45, 0.55), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub_text2 := winner_text + " · 身份全部揭示"
	if game_mode == "doudizhu" and eng != null:
		sub_text2 += " · 叫分倍数 ×%d" % int(eng.ddz_multiplier)
	var sub := lbl(sub_text2, 24, Color(0.55, 0.4, 0.45))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	# 本局 MVP（对标清瑶版 MVP 结算）：胜方阵营内综合评分最高者
	var mvi := _mvp_info(winner_text)
	var mvp_seat := int(mvi[0])
	var mvp_score := float(mvi[1])
	if mvp_seat >= 0:
		var mp: Dictionary = {}
		for p2 in players:
			if int(p2["seat"]) == mvp_seat:
				mp = p2
		var mvp_row := HBoxContainer.new()
		mvp_row.alignment = BoxContainer.ALIGNMENT_CENTER
		mvp_row.add_theme_constant_override("separation", 22)
		# V0.31：MVP 头像改为 CG 卡面（脸部特写）
		var mframe := Art.cg_card(mp["char"], Vector2(132, 172), {"zoom": 0.5, "face_y": 0.36, "fs": 16, "hp": false, "title": false})
		mframe.name = "MvpCG"
		mvp_row.add_child(mframe)
		var mvp_texts := VBoxContainer.new()
		mvp_texts.add_theme_constant_override("separation", 4)
		var mt := lbl("★ 本局 MVP", 40, C_GOLD, true)
		mt.autowrap_mode = TextServer.AUTOWRAP_OFF
		mt.custom_minimum_size = Vector2(620, 0)
		mvp_texts.add_child(mt)
		var mn := lbl("%s · %s" % [String(mp["char"]["name"]), String(mp["identity"])], 30, Color(0.3, 0.22, 0.3), true)
		mn.autowrap_mode = TextServer.AUTOWRAP_OFF
		mn.custom_minimum_size = Vector2(620, 0)
		mvp_texts.add_child(mn)
		var msc := lbl("输出 %d · 击杀 %d · 治疗 %d · 综合评分 %.1f" % [int(mp.get("stat_damage", 0)), int(mp.get("stat_kills", 0)), int(mp.get("stat_heal", 0)), mvp_score], 24, Color(0.5, 0.4, 0.45))
		msc.autowrap_mode = TextServer.AUTOWRAP_OFF
		msc.custom_minimum_size = Vector2(620, 0)
		mvp_texts.add_child(msc)
		mvp_row.add_child(mvp_texts)
		vb.add_child(mvp_row)
	for p in players:
		var row := PanelContainer.new()
		var is_me := int(p["seat"]) == 0
		var is_mvp := int(p["seat"]) == mvp_seat
		row.add_theme_stylebox_override("panel", style(Color(1.0, 0.93, 0.96, 0.95) if is_me else Color(0.97, 0.96, 0.98, 0.9), 14, C_GOLD if is_mvp else Color(1, 1, 1, 0.6), 3 if is_mvp else 1))
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 16)
		row.add_child(hb2)
		var idc := Color(0.55, 0.55, 0.6)
		match String(p["identity"]):
			"主公":
				idc = Color(0.85, 0.6, 0.08)
			"忠臣":
				idc = Color(0.3, 0.6, 0.95)
			"反贼":
				idc = Color(0.88, 0.3, 0.35)
			"内奸":
				idc = Color(0.6, 0.35, 0.85)
			"地主":
				idc = Color(0.88, 0.45, 0.1)
			"农民":
				idc = Color(0.3, 0.65, 0.35)
			"先手", "后手":
				idc = Color(0.35, 0.5, 0.8)
		var head := lbl("%d号 %s%s" % [int(p["seat"]) + 1, String(p["char"]["name"]), " ★MVP" if is_mvp else ""], 26, Color(0.3, 0.22, 0.3), true)
		head.custom_minimum_size = Vector2(230, 0)
		hb2.add_child(head)
		var idl := lbl(String(p["identity"]), 24, idc, true)
		idl.custom_minimum_size = Vector2(80, 0)
		hb2.add_child(idl)
		var st := lbl("存活" if p["alive"] else "阵亡", 22, Color(0.3, 0.65, 0.4) if p["alive"] else Color(0.6, 0.6, 0.65))
		st.custom_minimum_size = Vector2(70, 0)
		hb2.add_child(st)
		var medals: Array = []
		if int(p.get("stat_kills", 0)) >= 2:
			medals.append("⚔破敌")
		if int(p.get("stat_damage", 0)) >= 4:
			medals.append("💥猛攻")
		if int(p.get("stat_taken", 0)) >= 4:
			medals.append("🛡铁壁")
		if int(p.get("stat_heal", 0)) >= 3:
			medals.append("💚仁心")
		var medal_s := ("  [" + "·".join(PackedStringArray(medals)) + "]") if not medals.is_empty() else ""
		var stat := lbl("输出 %d · 击杀 %d · 承伤 %d · 治疗 %d%s" % [int(p.get("stat_damage", 0)), int(p.get("stat_kills", 0)), int(p.get("stat_taken", 0)), int(p.get("stat_heal", 0)), medal_s], 22, Color(0.45, 0.38, 0.42))
		stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb2.add_child(stat)
		vb.add_child(row)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	if not meta_result.is_empty():
		var mt_parts: Array = []
		if meta_result.has("xp"):
			var lvl := int(meta_result["level"])
			mt_parts.append("熟练度 +%d · %s Lv%d %s%s" % [int(meta_result["xp"]), String(players[0]["char_name"]), lvl, Meta.MASTERY_TITLE[lvl - 1], "（升级！）" if bool(meta_result["level_up"]) else ""])
		var names: Array = []
		for a in meta_result.get("new_ach", []):
			names.append(String(a[1]))
		if not names.is_empty():
			mt_parts.append("解锁成就：" + "、".join(PackedStringArray(names)))
		if not mt_parts.is_empty():
			var ml := lbl("　".join(PackedStringArray(mt_parts)), 22, C_GOLD.darkened(0.15), true)
			ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(ml)
	vb.add_child(btn_row)
	var again := plain_btn("再来一局", C_PLATE, C_WHITE, 30)
	again.custom_minimum_size = Vector2(240, 66)
	again.pressed.connect(func() -> void: start_match(false))
	btn_row.add_child(again)
	var log_b := plain_btn("📜 完整战报", Color(1, 0.97, 0.92), Color(0.35, 0.22, 0.10), 28)
	log_b.custom_minimum_size = Vector2(220, 66)
	log_b.pressed.connect(func() -> void:
		open_info_overlay("本局完整战报", "\n".join(eng.log_lines) if eng != null else "")
		move_child(info_overlay, get_child_count() - 1))
	btn_row.add_child(log_b)
	var home := plain_btn("返回主页", C_WHITE, C_PINK_DEEP, 30)
	home.custom_minimum_size = Vector2(240, 66)
	home.pressed.connect(func() -> void: go_home.call())
	btn_row.add_child(home)
	_extend_cover(dim, Color(0.16, 0.05, 0.12, 0.55))


# V0.24 4:3 适配：主界面在较高视口里把 1080 高的内容区垂直居中（main._fit_wide），
# 全屏遮罩只有 1080 高，这里在其下垫一块向上下延伸的同色底板覆盖留白（不移动遮罩内的任何节点）
func _extend_cover(layer: Control, col: Color) -> void:
	var pad := floorf(maxf(get_viewport_rect().size.y - 1080.0, 0.0) * 0.5)
	if pad <= 0.0:
		return
	var back := ColorRect.new()
	back.color = col
	back.mouse_filter = MOUSE_FILTER_STOP
	back.position = Vector2(0, -pad)
	back.size = Vector2(layer.size.x, 1080.0 + pad * 2.0)
	back.show_behind_parent = true
	layer.add_child(back)
	layer.move_child(back, 0)
	if layer is ColorRect:
		(layer as ColorRect).color = Color(0, 0, 0, 0)
	elif layer is Panel:
		layer.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func zone_label(zone: String) -> String:
	return {"hand": "手牌", "weapon": "武器", "armor": "防具", "minus": "饰品·疾行之靴", "plus": "饰品·远行披风", "treasure": "宝物", "delayed": "判定区"}.get(zone, zone)


# ---------------- 真人出牌操作 ----------------


func card_needs_target(card: Dictionary) -> bool:
	# V0.28：「补给」（桃）与「落雷/浮雷」（闪电）只能对自己使用，不再选目标（无名杀 selectTarget:-1）
	return String(card["name"]) in ["突击", "突然检查", "悄悄借走", "单挑", "借力打力", "火焰试炼", "羁绊锁链", "沉迷游戏", "断粮封锁", "草木疑兵", "声东击西", "弃甲曳兵", "增兵减灶", "逐近弃远", "水淹七军", "出其不意", "洞烛先机", "继往开来"]


func candidates_for(me: Dictionary, card: Dictionary) -> Array:
	var n := String(card["name"])
	var out: Array = []
	for p in alive_players():
		var seat := int(p["seat"])
		match n:
			"突击":
				if seat != 0 and attack_reachable(me, card, p):
					out.append(p)
			"增兵减灶":
				out.append(p)
			"洞烛先机":
				out.append(p)
			"继往开来":
				if not (p["hand"] as Array).is_empty() and (seat != 0 or (p["hand"] as Array).size() >= 2):
					out.append(p)
			"出其不意":
				if seat != 0 and not (p["hand"] as Array).is_empty():
					out.append(p)
			"声东击西":
				if seat != 0:
					out.append(p)
			"弃甲曳兵":
				if seat != 0:
					var has_e := false
					for slot in ["weapon", "armor", "minus", "plus"]:
						if not (p["equip"][slot] as Dictionary).is_empty():
							has_e = true
					if has_e:
						out.append(p)
			"突然检查":
				if seat != 0 and not all_target_cards(p).is_empty():
					out.append(p)
			"逐近弃远":
				if seat != 0 and not all_target_cards(p).is_empty():
					out.append(p)
			"水淹七军":
				if seat != 0:
					out.append(p)
			"悄悄借走":
				if seat != 0 and eff_dist(me, p) <= 1 and not all_target_cards(p).is_empty():
					out.append(p)
			"单挑":
				if seat != 0:
					out.append(p)
			"借力打力":
				if seat != 0 and not (p["equip"]["weapon"] as Dictionary).is_empty():
					out.append(p)
			"火焰试炼":
				if seat != 0 and not (p["hand"] as Array).is_empty():
					out.append(p)
			"羁绊锁链":
				out.append(p)  # V0.28：对照无名杀「铁索连环」filterTarget:true，可选自己
			"沉迷游戏", "断粮封锁", "草木疑兵":
				if seat != 0 and (n != "断粮封锁" or eff_dist(me, p) <= 1):
					var dup := false
					for d in p["judge"]:
						if String(d["name"]) == n:
							dup = true
					if not dup:
						out.append(p)
	return out


func cancel_targeting() -> void:
	targeting = false
	spear_targeting = false
	spear_cards = []
	muniu_targeting = false
	selected_card = {}
	target_candidates = []
	sel_target = -1
	extra_target = -1
	skill_mode = ""
	skill_card = {}
	if not asking:
		hide_prompt()
		maybe_restore_hint()
	refresh()


func _on_hand_card_clicked(card: Dictionary) -> void:
	# V0.25：点一下选中上浮（再点取消），用「确定」/点目标/拖拽出牌；弃牌阶段为多选；响应时点亮的牌可直接点打出
	if Time.get_ticks_msec() - drag_end_ms < 200:
		return
	if _lp_swallowing():  # V0.26：长按看说明后的松手不算点击
		return
	if players.is_empty() or game_over or not _hand_has(card):
		return
	if discard_mode:
		_toggle_discard(card)
		return
	if asking:
		# V0.27：点亮的牌点一下只是选中（上浮），点「确定」才打出/提交；再点一下取消选中
		var picked_ok := false
		for pc in pick_cards:
			if is_same(pc, card):
				picked_ok = true
		if picked_ok and ask_mode == "pick":
			_ask_select(card)
		elif ask_mode == "respond" and respond_name != "" and String(card["name"]) == respond_name:
			_ask_select(card)
		else:
			_nudge_card(card)
		return
	if not interactive or turn_seat != 0:
		return
	var me: Dictionary = players[0]
	if skill_mode != "":
		_skill_card_tap(card)
		return
	if spear_targeting:
		_toggle_spear_card(card)
		return
	if muniu_targeting:
		muniu_targeting = false
		targeting = false
		target_candidates = []
	if not selected_card.is_empty() and is_same(selected_card, card):
		cancel_targeting()
		return
	var reason := unusable_reason(me, card)
	if reason != "":
		if equip_name(me, "treasure") == "木牛流马":
			selected_card = card
			targeting = false
			target_candidates = []
			sel_target = -1
			show_hint(reason + "（也可以点「存粮」把它放进木牛流马）")
			_queue_refresh()
			return
		show_hint(reason + "（点其他牌继续）")
		_nudge_card(card)
		return
	_select_card(card)


func _on_seat_clicked(seat_idx: int) -> void:
	if not targeting and seat_idx != 0 and not players.is_empty() and eng != null:
		var order := ["", "主", "忠", "反", "内"]
		var cur := String(guess_marks.get(seat_idx, ""))
		guess_marks[seat_idx] = order[(order.find(cur) + 1) % order.size()]
		refresh()
		return
	if not targeting or not interactive:
		return
	if not target_candidates.has(seat_idx):
		return
	# V0.27：点目标 = 选中/取消选中该目标（多目标牌可选多个），点「确定」才结算；
	# 只有开启「自动确认」时，选够后自动提交（无名杀 auto_confirm）
	var maxn := 1
	if skill_mode == "" and not spear_targeting and not muniu_targeting and not selected_card.is_empty():
		maxn = card_max_targets(selected_card)
	if sel_target == seat_idx:
		sel_target = extra_target
		extra_target = -1
	elif extra_target == seat_idx:
		extra_target = -1
	elif sel_target < 0:
		sel_target = seat_idx
	elif maxn >= 2 and extra_target < 0:
		extra_target = seat_idx
	elif maxn >= 2:
		extra_target = seat_idx
	else:
		sel_target = seat_idx
	play_sfx("draw")
	_show_sel_hint()
	refresh()
	_maybe_auto_confirm()


func choose_zone_entry(me: Dictionary, tgt: Dictionary) -> Dictionary:
	var entries := all_target_cards(tgt)
	if entries.is_empty():
		return {}
	var zones_present: Array = []
	for e in entries:
		if not zones_present.has(String(e["zone"])):
			zones_present.append(String(e["zone"]))
	if zones_present.size() <= 1 and zones_present[0] == "hand":
		return entries[rng.randi_range(0, entries.size() - 1)]
	var options: Array = []
	for e in entries:
		if String(e["zone"]) == "hand":
			continue
		options.append({"label": "%s：%s" % [zone_label(String(e["zone"])), card_text(e["card"])], "value": e})
	var hand_any := false
	for e in entries:
		if String(e["zone"]) == "hand":
			hand_any = true
	if hand_any:
		options.append({"label": "手牌（随机一张）", "value": {"zone": "hand", "card": {}}})
	var picked: Variant = await ask("选择 %s 身上的一张牌" % pname(tgt), options)
	if picked is Dictionary and String(picked.get("zone", "")) == "hand" and (picked["card"] as Dictionary).is_empty():
		var hand_entries: Array = entries.filter(func(e: Dictionary) -> bool: return String(e["zone"]) == "hand")
		return hand_entries[rng.randi_range(0, hand_entries.size() - 1)]
	return picked if picked is Dictionary else {}


func execute_targeted_card(me: Dictionary, card: Dictionary, tgt: Dictionary) -> void:
	var n := String(card["name"])
	match n:
		"突击", "单挑", "借力打力", "火焰试炼", "羁绊锁链", "落雷", "沉迷游戏", "断粮封锁", "草木疑兵", "浮雷", "声东击西", "弃甲曳兵", "增兵减灶", "补给", "出其不意", "洞烛先机", "继往开来":
			await eng.play_card(me, card, tgt)
		"突然检查", "悄悄借走", "逐近弃远":
			var entry := await choose_zone_entry(me, tgt)
			if entry.is_empty():
				eng.discard_from_hand(me, card)
				log_msg("你使用「%s」，但 %s 身上没有任何牌。" % [n, pname(tgt)])
			else:
				await eng.play_card(me, card, tgt, entry["card"])
	refresh()


func execute_simple_card(me: Dictionary, card: Dictionary) -> void:
	await eng.play_card(me, card, {})
	refresh()


func _on_difficulty(d: int) -> void:
	difficulty = d
	if eng != null:
		eng.difficulty = d
	refresh_diff_buttons()


func refresh_diff_buttons() -> void:
	for i in diff_btns.size():
		var b: Button = diff_btns[i]
		if i == difficulty:
			b.add_theme_stylebox_override("normal", style(C_PLATE, 26, Color(1, 1, 1, 0.8), 2, true))
			b.add_theme_color_override("font_color", C_WHITE)
		else:
			b.add_theme_stylebox_override("normal", style(Color(1, 1, 1, 0.92), 26, C_GOLD, 2, true))
			b.add_theme_color_override("font_color", C_PINK_DEEP)


func _on_spear_button() -> void:
	if not interactive or turn_seat != 0 or game_over:
		return
	if spear_targeting:
		cancel_targeting()
		return
	var me: Dictionary = players[0]
	if (me["hand"] as Array).size() < 2:
		show_hint("「合璧长枪」需要两张手牌")
		return
	target_candidates = []
	for p in candidates_for(me, {"name": "突击"}):
		target_candidates.append(int(p["seat"]))
	if target_candidates.is_empty():
		show_hint("攻击范围内没有目标")
		return
	selected_card = {}
	spear_cards = []
	sel_target = -1
	extra_target = -1
	skill_mode = ""
	skill_card = {}
	muniu_targeting = false
	spear_targeting = true
	targeting = true
	if target_candidates.size() == 1:
		sel_target = int(target_candidates[0])
	_show_sel_hint()
	refresh()


func _toggle_spear_card(card: Dictionary) -> void:
	for i in spear_cards.size():
		if is_same(spear_cards[i], card):
			spear_cards.remove_at(i)
			_show_sel_hint()
			refresh()
			return
	if spear_cards.size() >= 2:
		show_hint("「合璧长枪」最多选两张手牌；再点已选的牌可取消")
		_nudge_card(card)
		return
	spear_cards.append(card)
	play_sfx("draw")
	_show_sel_hint()
	refresh()
	_maybe_auto_confirm()


func _on_muniu_store() -> void:
	if not interactive or turn_seat != 0 or game_over:
		return
	var me: Dictionary = players[0]
	if selected_card.is_empty() or not (me["hand"] as Array).has(selected_card):
		show_hint("先点选一张手牌，再点「存粮」")
		return
	var c: Dictionary = selected_card
	selected_card = {}
	eng.muniu_store(me, c)
	refresh()


func _on_muniu_give() -> void:
	if not interactive or turn_seat != 0 or game_over:
		return
	if muniu_targeting:
		cancel_targeting()
		return
	target_candidates = []
	for p in alive_players():
		if int(p["seat"]) != 0:
			target_candidates.append(int(p["seat"]))
	if target_candidates.is_empty():
		show_hint("没有可以转交的角色")
		return
	selected_card = {}
	sel_target = -1
	extra_target = -1
	skill_mode = ""
	skill_card = {}
	spear_targeting = false
	muniu_targeting = true
	targeting = true
	if target_candidates.size() == 1:
		sel_target = int(target_candidates[0])
	_show_sel_hint()
	refresh()
	_maybe_auto_confirm()


func _on_skill_button(skill_id: String) -> void:
	# V0.27：点技能按钮只进入「技能选择」状态（按钮高亮），选好牌/目标后点「确定」才发动；再点一次按钮或「取消」退出
	if not interactive or turn_seat != 0 or game_over:
		return
	if skill_mode == skill_id:
		cancel_targeting()
		return
	cancel_targeting()
	_enter_skill_mode(skill_id)


# ---------------- 新引擎 UI 回调 ----------------

func _eng_is_human(p: Dictionary) -> bool:
	return not auto_all and not auto_mode and int(p["seat"]) == 0


func open_info_overlay(title: String, body: String, bb: bool = false) -> void:
	if info_overlay == null:
		return
	info_title.text = title
	info_text.bbcode_enabled = bb
	info_text.text = body
	info_overlay.visible = true
	if title == "战况记录":
		await get_tree().process_frame
		info_text.scroll_to_line(maxi(info_text.get_line_count() - 1, 0))


func counter_text() -> String:
	if eng == null:
		return "尚未开局"
	var seen := {}
	for c in eng.discard_pile:
		seen[String(c["name"])] = int(seen.get(String(c["name"]), 0)) + 1
	if not players.is_empty():
		for c in players[0]["hand"]:
			seen[String(c["name"])] = int(seen.get(String(c["name"]), 0)) + 1
		for p in players:
			for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
				var eq: Dictionary = p["equip"][slot]
				if not eq.is_empty():
					seen[String(eq["name"])] = int(seen.get(String(eq["name"]), 0)) + 1
			for jc in p["judge"]:
				seen[String(jc["name"])] = int(seen.get(String(jc["name"]), 0)) + 1
	# 统计关键牌剩余
	var key_names := ["突击", "闪避", "补给", "特饮", "看破", "单挑", "突然检查", "悄悄借走", "全场乱斗", "弹幕齐射"]
	var key_parts: Array = []
	for kn in key_names:
		var total_n := int((CardDefs.DEFS.get(kn, {}) as Dictionary).get("n", 0))
		var left_n := maxi(0, total_n - int(seen.get(kn, 0)))
		key_parts.append("%s ×%d" % [kn, left_n])
	var lines: Array = [
		"牌堆剩余 %d 张 · 弃牌堆 %d 张" % [eng.deck.size(), eng.discard_pile.size()],
	]
	if (game_mode == "twovtwo" or game_mode == "boss") and not players.is_empty():
		lines.append("")
		lines.append("【同盟队友实时手牌与状态】")
		for mp in players:
			if int(mp["seat"]) != 0 and String(mp["identity"]) == String(players[0]["identity"]):
				var mh: Array = []
				for mc in mp["hand"]:
					mh.append(card_text(mc))
				var mst := ("存活 ♥%d/%d" % [int(mp["hp"]), int(mp["max_hp"])]) if bool(mp["alive"]) else "已阵亡"
				lines.append("  · %s（%s）：%s" % [pname(mp), mst, "、".join(PackedStringArray(mh)) if not mh.is_empty() else "（无手牌）"])
	lines.append("")
	lines.append("【关键牌剩余速查】")
	lines.append("  ".join(PackedStringArray(key_parts)))
	if not eng.discard_pile.is_empty():
		var rec_cards: Array = []
		var dsz: int = (eng.discard_pile as Array).size()
		for i in range(dsz - 1, maxi(-1, dsz - 13), -1):
			rec_cards.append(card_text(eng.discard_pile[i]))
		lines.append("")
		lines.append("【最近弃牌堆明细（最新在前，共 %d 张）】" % dsz)
		lines.append("  ".join(PackedStringArray(rec_cards)))
	lines.append("")
	lines.append("以下按已出现的牌推算未见张数：")
	var kind_order := ["基本牌", "锦囊牌", "延时锦囊", "武器", "防具", "饰品"]
	for kind in kind_order:
		var parts: Array = []
		for nm in CardDefs.DEFS:
			if CardDefs.kind_of(nm) != kind:
				continue
			var left := int(CardDefs.DEFS[nm]["n"]) - int(seen.get(nm, 0))
			if left > 0:
				parts.append("%s ×%d" % [nm, left])
		if not parts.is_empty():
			lines.append("【%s】" % kind)
			lines.append("  ".join(parts))
	return "\n".join(lines)


func hand_sort_cmp(a: Dictionary, b: Dictionary) -> bool:
	var rank := {"基本牌": 0, "锦囊牌": 1, "延时锦囊": 2, "武器": 3, "防具": 4, "饰品": 5}
	var ra := int(rank.get(CardDefs.kind_of(String(a["name"])), 9))
	var rb := int(rank.get(CardDefs.kind_of(String(b["name"])), 9))
	if ra != rb:
		return ra < rb
	if String(a["name"]) != String(b["name"]):
		return String(a["name"]) < String(b["name"])
	return int(a["point"]) < int(b["point"])


func sort_my_hand() -> void:
	if players.is_empty():
		return
	(players[0]["hand"] as Array).sort_custom(hand_sort_cmp)
	refresh()


func toggle_auto() -> void:
	auto_mode = not auto_mode
	if auto_btn:
		auto_btn.text = "托管中" if auto_mode else "托管"
	show_hint("已开启托管，静替你出牌。" if auto_mode else "已关闭托管。")
	# V0.25 修复：在自己出牌阶段中途开托管，旧版要等你手动点「结束」才生效；现立即由 AI 接管本阶段剩余出牌
	if auto_mode and in_play_phase and turn_seat == 0 and not asking and eng != null and not eng.game_over:
		cancel_targeting()  # V0.27：托管接管前清掉未确认的选择（牌/目标/技能选择状态）
		auto_takeover = true
		end_play_pressed.emit()


func on_concede_pressed() -> void:
	if eng == null or eng.game_over:
		return
	if not concede_arm:
		concede_arm = true
		if concede_btn:
			concede_btn.text = "确认认输？"
		await get_tree().create_timer(2.5).timeout
		concede_arm = false
		if concede_btn and eng != null and not eng.game_over:
			concede_btn.text = "认输"
		return
	concede_arm = false
	eng.concede(players[0])
	# V0.24 修复：旧版在自己的出牌阶段或有提问等待作答时认输，引擎仍卡在等待「结束出牌」/作答，结算界面不出现
	in_play_phase = false
	targeting = false
	hide_prompt()
	decided.emit(null)
	end_play_pressed.emit()
	refresh()


func _eng_log(m: String) -> void:
	log_msg(m)


func _eng_changed() -> void:
	if eng == null or players.is_empty():
		return
	if not eng.turn_player.is_empty():
		turn_seat = int(eng.turn_player["seat"])
		if turn_seat != last_turn_seat:
			last_turn_seat = turn_seat
			discard_queue.clear()
			discard_auto_left = 0
			if not auto_all:
				show_turn_banner(String(eng.turn_player["char_name"]))
				if turn_seat == 0:
					play_sfx("turn")
		if eng.phase_text != "":
			set_phase("%s · %s" % [eng.phase_text, pname(eng.turn_player)])
	round_no = eng.round_no
	_update_music_scene()
	_queue_refresh()


func _update_music_scene() -> void:
	var director := get_tree().get_first_node_in_group("music_director") as MusicDirector
	if director == null:
		return
	director.play_scene(_battle_music_scene())


func _battle_music_scene() -> String:
	if eng == null or players.is_empty():
		return "battle"
	if game_over:
		return "battle"
	var alive := 0
	var key_low := false  # 「关键角色」濒临出局：自己、主公/地主；单挑为任一方
	var me: Dictionary = players[0]
	for p in players:
		if not bool(p["alive"]):
			continue
		alive += 1
		if int(p["hp"]) > 1:
			continue
		var idn := String(p.get("identity", ""))
		if p == me or game_mode == "duel" or idn == "主公" or idn == "地主":
			key_low = true
	# 关键角色 1 血、或身份场打到最后两人时切紧张曲；其余保持对局曲（音乐层另有最短停留时间防抖）
	if key_low or (game_mode == "identity" and alive <= 2):
		return "tense"
	return "battle"


var _refresh_pending := false


func _queue_refresh() -> void:
	# 引擎每次改动牌区都会回调 changed()（一张牌的结算可触发十几次），合并为本帧末一次重建，降低安卓端 CPU 与节点分配压力
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_do_queued_refresh")


func _do_queued_refresh() -> void:
	_refresh_pending = false
	if is_inside_tree():
		refresh()


func _eng_pace(sec: float) -> void:
	if fast or auto_all:
		return
	await wait(sec)


func _eng_played(card: Dictionary, owner: String, target_name: String = "") -> void:
	if String(card["name"]) in ["全场乱斗", "弹幕齐射"] and not auto_all:
		fx_screen_shake()
	var seat := -1
	for p in players:
		if pname(p) == owner:
			seat = int(p["seat"])
	var label := _short_name(owner) if target_name == "" else "%s ➜ %s" % [_short_name(owner), _short_name(target_name)]
	if seat >= 0 and not auto_all:
		fx_target_ring(seat, Color(1.0, 0.72, 0.22))
	show_played_card(card, label, seat)
	refresh()


func _eng_ask_skill(p: Dictionary, sid: String, timing: String, ctx: Dictionary) -> bool:
	var def: Dictionary = eng.skill_lib.get(sid, {})
	var nm := String(def.get("name", sid))
	var v: Variant = await ask("是否发动技能「%s」？" % nm, [{"label": "发动", "value": true}, {"label": "不发动", "value": false}])
	return bool(v)


func _eng_ask_respond(p: Dictionary, card_name: String, reason: String) -> bool:
	# V0.25：响应时手里能打出的牌亮起（其余置灰），可直接点那张牌作答；限时作答，超时视为不出
	respond_name = card_name
	resp_pref_card = {}
	if tutorial and tut_step == 3 and card_name == "闪避" and not players.is_empty() and p == players[0]:
		# V0.32：教学第 4 步的响应练习：面板改为当前情境提示，并保留到玩家作答
		if tut_panel != null and is_instance_valid(tut_panel) and tut_label != null:
			tut_panel.visible = true
			tut_label.text = "教学 4/5：对手对你出「突击」了！点手牌里亮起的「闪避」选中，再点「确定」抵挡；点「不出」会受到 1 点伤害。"
			move_child(tut_panel, get_child_count() - 1)
	var v: Variant = await ask("是否打出「%s」？（%s）" % [card_name, reason], [{"label": "打出「%s」" % card_name, "value": true}, {"label": "不出", "value": false}], Callable(), "respond")
	respond_name = ""
	_queue_refresh()
	return v is bool and bool(v)


func _eng_ask_save(p: Dictionary, dying: Dictionary) -> bool:
	respond_name = "补给"
	resp_pref_card = {}
	var v: Variant = await ask("%s 濒临阵亡，是否使用救援牌？" % pname(dying), [{"label": "使用救援", "value": true}, {"label": "不救", "value": false}], Callable(), "respond")
	respond_name = ""
	_queue_refresh()
	return v is bool and bool(v)


func _eng_pick_card(p: Dictionary, cands: Array, prompt: String) -> Dictionary:
	# V0.27：技能选择状态里已选好的牌直接作答（发动前已经确认过）
	if skill_pre.has("card"):
		var pc0: Dictionary = skill_pre["card"]
		skill_pre.erase("card")
		for c0 in cands:
			if is_same(c0, pc0):
				return c0
	var options: Array = []
	for c in cands:
		options.append({"label": card_text(c), "value": c})
	options.append({"label": "取消", "value": {}})
	# V0.25：候选牌在自己手里时同步点亮，可直接点牌选择
	pick_cards = cands.filter(func(c: Variant) -> bool: return c is Dictionary and _hand_has(c))
	var v: Variant = await ask(prompt, options)
	pick_cards = []
	_queue_refresh()
	if v is Dictionary:
		return v
	return {}


func _eng_pick_target(p: Dictionary, cands: Array, prompt: String) -> Dictionary:
	if skill_pre.has("target"):
		var pt0: int = int(skill_pre["target"])
		skill_pre.erase("target")
		for t0 in cands:
			if int(t0["seat"]) == pt0:
				return t0
	var si := await ask_choose_target(prompt, cands, false)
	if si >= 0 and si < players.size():
		return players[si]
	return {}


func _eng_pick_option(p: Dictionary, options: Array, prompt: String) -> Variant:
	# V0.27：出牌前已点选的附加目标（羁绊锁链第二目标）直接作答，不再重复询问
	if not pre_answers.is_empty() and (String((pre_answers[0] as Dictionary).get("kind", "")) != "chain2" or prompt.find("羁绊锁链") >= 0):
		var pa: Dictionary = pre_answers[0]
		for o0 in options:
			var ov1: Variant = (o0 as Dictionary).get("value")
			if typeof(ov1) == typeof(pa["value"]) and ((ov1 is Dictionary and (pa["value"] as Dictionary).is_empty() and (ov1 as Dictionary).is_empty()) or is_same(ov1, pa["value"])):
				pre_answers.pop_front()
				return ov1
	var v: Variant = await ask(prompt, options)
	# 防御：作答必须是选项之一（点亮手牌作答、超时默认等途径若串到别的提问，回落到默认项，避免引擎拿到错类型的值）
	for o in options:
		var ov: Variant = (o as Dictionary).get("value")
		if typeof(ov) == typeof(v) and ov == v:
			return v
	return _default_answer(options)


func _eng_pick_from_hand(p: Dictionary, victim: Dictionary) -> Dictionary:
	var options: Array = []
	for c in victim["hand"]:
		options.append({"label": card_text(c), "value": c})
	var v: Variant = await ask("选择要弃置的牌（%s 的手牌）" % pname(victim), options)
	if v is Dictionary:
		return v
	return {}


func _eng_choose_discard(p: Dictionary) -> Dictionary:
	# V0.25：弃牌阶段一次多选（手杀/无名杀 selectCard 范围），凑满张数才能确定；智能选择/超时交给 AI 挑
	var phase_need := int(eng.discard_need) if eng != null else 0
	if phase_need <= 0:
		discard_queue.clear()
		discard_auto_left = 0
	while not discard_queue.is_empty():
		var q: Dictionary = discard_queue.pop_front()
		if _hand_has(q):
			return q
	if discard_auto_left > 0:
		discard_auto_left -= 1
		return {}
	var hand: Array = p["hand"]
	if hand.is_empty():
		return {}
	var need := mini(maxi(phase_need, 1), hand.size())
	discard_mode = true
	discard_need = need
	discard_sel = []
	discard_prompt = ("弃牌阶段：手牌超出上限，请弃置 %d 张" % need) if phase_need > 0 else "请选择 1 张手牌"
	selected_card = {}
	targeting = false
	_queue_refresh()
	var v: Variant = await ask(discard_prompt, [{"label": "确定", "value": "__confirm"}, {"label": "智能选择", "value": "__auto", "default": true}], func() -> void:
		discard_confirm_btn = prompt_btns.get_child(0) as Button
		_update_discard_ui())
	var picked: Array = discard_sel.duplicate()
	discard_mode = false
	discard_sel = []
	discard_confirm_btn = null
	_queue_refresh()
	if v is String and String(v) == "__confirm" and picked.size() == need:
		discard_queue = picked.slice(1)
		return picked[0]
	discard_auto_left = need - 1
	return {}


func _eng_play_phase(eng_ref, p: Dictionary) -> void:
	if eng != null and eng.game_over:
		return
	auto_takeover = false
	interactive = true
	in_play_phase = true
	end_play_btn.disabled = false
	show_hint("你的出牌阶段：点牌选中后点「确定」，或把牌拖到目标上；灰色牌暂时用不了")
	refresh()
	await end_play_pressed
	in_play_phase = false
	targeting = false
	spear_targeting = false
	spear_cards = []
	muniu_targeting = false
	selected_card = {}
	sel_target = -1
	extra_target = -1
	skill_mode = ""
	skill_card = {}
	target_candidates = []
	_drag_reset()
	if not asking:
		hide_prompt()
	interactive = false
	end_play_btn.disabled = true
	pending_target_for.clear()
	refresh()
	if auto_takeover and auto_mode and eng_ref != null and not eng_ref.game_over and bool(p["alive"]):
		auto_takeover = false
		await eng_ref.ai_play_phase(p)


# ---------------- 特效层（对照无名杀/手杀：飘字、连线、技能名、飞牌） ----------------

const CHAR_LINES := {
	"hina": {"attack": ["花瓣啊，听我的心愿！", "对不起，这一下是必须的"], "hurt": ["呜…没关系的", "好痛…但还能坚持"], "dying": "花签…还没许完愿呢…", "death": "花瓣…都飘走了…", "skill": "把心愿，交给樱花吧", "heal": "谢谢你…暖洋洋的"},
	"rena": {"attack": ["站住！违反校规！", "风纪检查，不许动！"], "hurt": ["好、好痛…", "我、我不会退让的！"], "dying": "铃声…还没停…", "death": "风纪…就到这里了…", "skill": "风纪委员，执行！", "heal": "哼，这次就谢谢你"},
	"kaori": {"attack": ["听我的歌吧！", "上吧，麦克风！"], "hurt": ["呜哇，麦克风要掉了…", "好痛…歌声不能停！"], "dying": "最后…再唱一首…", "death": "谢幕了…谢谢大家…", "skill": "你的心跳，我听见了", "heal": "恢复啦！继续演出！"},
	"chinatsu": {"attack": ["全速冲刺——！", "看我的起跑！"], "hurt": ["摔一跤而已！", "呜…再来一次！"], "dying": "终点线…就在前面…", "death": "跑不动了…", "skill": "元气补给，满格！", "heal": "能量回来啦！"},
	"shizuha": {"attack": ["呜…茶要凉了啦", "别打扰我睡觉…"], "hurt": ["好困…被打醒了…", "呜…好痛…"], "dying": "星星…好远啊…", "death": "呼啊…睡着了…", "skill": "呼啊…我去看星星了哦", "heal": "嗯…热茶暖暖的…"},
	"hibiki": {"attack": ["听好了，练习曲开始！", "这一击，用琴音！"], "hurt": ["笨、笨蛋，轻一点…", "呜…琴弦要断了…"], "dying": "琴弦…断了…", "death": "演奏…结束了…", "skill": "吵死了，都安静！", "heal": "哼…还算你识相"},
	"koume": {"attack": ["请恕我失礼了", "这、这一杯请您收下！"], "hurt": ["呜…围裙要脏了…", "对不起，我没躲开…"], "dying": "茶…还没泡好…", "death": "今天…打烊了…", "skill": "请让我来招待您吧", "heal": "感谢您的温柔"},
	"sena": {"attack": ["按学生会章程，予以肃清！", "这一步，也在星轨推算之中。"], "hurt": ["唔…推算偏了一分吗…", "学生会长绝不会退缩！"], "dying": "星轨…还没有走到尽头…", "death": "会长室的灯…先熄了…", "skill": "星辰轨迹，尽在掌握！", "heal": "重整态势，继续推演"},
	"reo": {"attack": ["看剑！一刀两断！", "我的竹刀，绝不迟疑！"], "hurt": ["好刀法…再战！", "这点伤，连热身都不算！"], "dying": "剑道…还没有登顶…", "death": "胜负已分…佩服…", "skill": "秘剑·残月——斩！", "heal": "气息调匀，剑锋重燃！"},
	"mahiru": {"attack": ["翻至阳之卷，星火燎原！", "书页记载的命数，收下吧"], "hurt": ["唔…把书页弄乱了…", "阴与阳的平衡…还在…"], "dying": "借书证…还没到期呢…", "death": "合上书卷…晚安…", "skill": "昼夜轮转，阴阳易位！", "heal": "静下心来，再读一页"},
	"aya": {"attack": ["一矢中的，破！", "落樱百步，逃不掉的！"], "hurt": ["弓弦未乱，还能再射！", "这点小伤，休想动摇我"], "dying": "弦…要断了吗…", "death": "漂亮的胜负…", "skill": "心眼开阖，神射无双！", "heal": "调息完毕，重挽长弓"},
	"nana": {"attack": ["尝尝特制星光试剂！", "小心爆炸哦——砰！"], "hurt": ["哇啊！烧杯差点碎了！", "呜…配方算错了吗…"], "dying": "实验…还没写完报告…", "death": "实验室…要先关门啦…", "skill": "催化剂投入，连锁反应开始！", "heal": "喝口营养液，满血复活！"},
	"rin": {"attack": ["这一手，将军（王手）！", "棋路早已算定，无处可逃！"], "hurt": ["嗯…弃子争先罢了", "这一步，还在计算之内"], "dying": "终盘…还没分出胜负…", "death": "是我输了这局棋…", "skill": "妙算入神，一子定乾坤！", "heal": "复盘重整，再弈一局"},
	"yukine": {"attack": ["违规预算，予以冻结！", "凝结吧，冰霜之刃！"], "hurt": ["账目…不容许任何差池！", "寒霜会记住这次冒犯"], "dying": "决算报告…还没交接…", "death": "冰雪…终究会融化吗…", "skill": "精算无遗，凛霜反噬！", "heal": "账目核销，状态恢复"},
	"lilia": {"attack": ["以骑士团之名，突进！", "荣耀之剑，绝不偏斜！"], "hurt": ["圣盾尚在，无妨！", "休想越过我的防线！"], "dying": "骑士的誓言…永不磨灭…", "death": "请大家…继续前进吧…", "skill": "展开吧，圣纹护盾！", "heal": "荣光庇佑，重振旗鼓！"},
}


func show_bubble(seat: int, cat: String) -> void:
	if fx_root == null or seat < 0 or seat >= players.size():
		return
	var cid := String(players[seat]["char"]["id"])
	if not CHAR_LINES.has(cid):
		return
	var entry = CHAR_LINES[cid].get(cat, "")
	var text := ""
	if entry is Array:
		if (entry as Array).is_empty():
			return
		text = String(entry[randi() % (entry as Array).size()])
	else:
		text = String(entry)
	if text == "":
		return
	if auto_all:
		return
	if bubble_nodes.has(seat) and is_instance_valid(bubble_nodes[seat]):
		(bubble_nodes[seat] as Node).queue_free()
	bubble_order.erase(seat)
	# 同屏最多 2 个气泡：收掉最早的
	var live: Array = []
	for bs_seat in bubble_order:
		if bubble_nodes.has(bs_seat) and is_instance_valid(bubble_nodes[bs_seat]) and not (bubble_nodes[bs_seat] as Node).is_queued_for_deletion():
			live.append(bs_seat)
	bubble_order = live
	while bubble_order.size() >= 2:
		var old_seat: int = bubble_order.pop_front()
		(bubble_nodes[old_seat] as Node).queue_free()
		bubble_nodes.erase(old_seat)
	var pn := seat_panel_of(seat)
	if pn == null:
		return
	var bw := clampi(48 + text.length() * 21, 130, 350)
	var bh := 52
	var bub := Panel.new()
	bub.size = Vector2(bw, bh)
	bub.position = Vector2(clampf(pn.position.x + pn.size.x * 0.5 - bw * 0.5, 8.0, vw - bw - 8.0), pn.position.y - bh - 16)
	var side_tail := 0
	if pn.position.y < 200.0:
		# 顶排座位上方是功能条：气泡改放到座位侧面（左半屏放右侧，右半屏放左侧），不压按钮
		if pn.position.x + pn.size.x * 0.5 < vw * 0.5:
			bub.position = Vector2(pn.position.x + pn.size.x + 14, pn.position.y + 36)
			side_tail = -1
		else:
			bub.position = Vector2(pn.position.x - bw - 14, pn.position.y + 36)
			side_tail = 1
	bub.mouse_filter = MOUSE_FILTER_IGNORE
	bub.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.96), 14, C_GOLD, 2, true))
	var tail := Panel.new()
	tail.size = Vector2(16, 16)
	tail.rotation = PI / 4.0
	tail.position = Vector2(bw * 0.5 - 8, bh - 9)
	if side_tail == -1:
		tail.position = Vector2(-7, bh * 0.5 - 8)
	elif side_tail == 1:
		tail.position = Vector2(bw - 9, bh * 0.5 - 8)
	tail.mouse_filter = MOUSE_FILTER_IGNORE
	tail.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.96), 2))
	bub.add_child(tail)
	var bl := lbl(text, 20, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	bl.position = Vector2(6, 13)
	bl.size = Vector2(bw - 12, 28)
	bl.autowrap_mode = TextServer.AUTOWRAP_OFF
	bl.clip_text = true
	bl.mouse_filter = MOUSE_FILTER_IGNORE
	bub.add_child(bl)
	fx_root.add_child(bub)
	bubble_nodes[seat] = bub
	bubble_order.append(seat)
	bub.modulate.a = 0.0
	bub.position.y += 8
	var btw := create_tween().bind_node(bub)
	btw.tween_property(bub, "modulate:a", 1.0, 0.15)
	btw.parallel().tween_property(bub, "position:y", bub.position.y - 8.0, 0.18)
	btw.tween_interval(1.5)
	btw.tween_property(bub, "modulate:a", 0.0, 0.3)
	btw.tween_callback(func() -> void: if is_instance_valid(bub): bub.queue_free())

func seat_panel_of(seat: int) -> Control:
	if seat == 0:
		return me_panel_ref
	if seat - 1 >= 0 and seat - 1 < seat_panels.size():
		return seat_panels[seat - 1]
	return null


func seat_center(seat: int) -> Vector2:
	var pn := seat_panel_of(seat)
	if pn == null:
		return Vector2(vw * 0.5, 540)
	return pn.position + pn.size * 0.5


func _process(delta: float) -> void:
	if not is_visible_in_tree() or players.is_empty():
		return
	breath_t += delta
	for i in seat_panels.size():
		var panel := seat_panels[i] as Control
		if panel == null:
			continue
		var tr := panel.get_node_or_null("Portrait") as Control
		if tr == null:
			continue
		var active := (i + 1) == turn_seat
		var amp := 3.2 if active else 1.6
		var spd := 1.5 if active else 0.8
		tr.position.y = 7.0 + sin(breath_t * spd + float(i) * 1.7) * amp
	if player_portrait != null and me_panel_ref != null and me_panel_ref.visible:
		player_portrait.position.y = -2.0 + sin(breath_t * 0.8 + 0.6) * 1.4


func fx_float(seat: int, text: String, color: Color, fsize: int = 46, rise: float = 84.0) -> void:
	if fx_root == null or auto_all or fx_root.get_child_count() > FX_CAP:
		return
	var lb := lbl(text, fsize, color, true, HORIZONTAL_ALIGNMENT_CENTER)
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	lb.size = Vector2(320, 64)
	lb.pivot_offset = Vector2(160, 32)
	var c := seat_center(seat)
	# 同一座位短时间内多次飘字（连续伤害、伤害+濒死等）逐层上移，不叠在一起
	var now := Time.get_ticks_msec()
	var st: Array = float_stack.get(seat, [0, 0])
	var k := int(st[1]) + 1 if now - int(st[0]) < 420 else 0
	k = k % 4
	float_stack[seat] = [now, k]
	lb.position = c + Vector2(-160, -110 - 70 * k)
	lb.mouse_filter = MOUSE_FILTER_IGNORE
	lb.add_theme_constant_override("outline_size", 9)
	lb.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
	fx_root.add_child(lb)
	lb.scale = Vector2(0.4, 0.4)
	var tw := create_tween().bind_node(lb)
	tw.tween_property(lb, "scale", Vector2(1.14, 1.14), 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lb, "position:y", lb.position.y - rise, 0.95)
	tw.tween_property(lb, "scale", Vector2.ONE, 0.07)
	tw.tween_interval(0.5)
	tw.tween_property(lb, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void: if is_instance_valid(lb): lb.queue_free())


func fx_flash(seat: int, color: Color) -> void:
	var pn := seat_panel_of(seat)
	if pn == null or fx_root == null:
		return
	var ov := Panel.new()
	ov.position = pn.position
	ov.size = pn.size
	ov.mouse_filter = MOUSE_FILTER_IGNORE
	ov.add_theme_stylebox_override("panel", style(Color(color.r, color.g, color.b, 0.42), 24))
	fx_root.add_child(ov)
	var tw := create_tween().bind_node(ov)
	tw.tween_property(ov, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: if is_instance_valid(ov): ov.queue_free())


func fx_shake(seat: int) -> void:
	var pn := seat_panel_of(seat)
	if pn == null or pn.has_meta("shaking"):
		return
	pn.set_meta("shaking", true)
	var base := pn.position
	var tw := create_tween().bind_node(pn)
	tw.tween_property(pn, "position:x", base.x + 10.0, 0.05)
	tw.tween_property(pn, "position:x", base.x - 10.0, 0.08)
	tw.tween_property(pn, "position:x", base.x + 6.0, 0.07)
	tw.tween_property(pn, "position:x", base.x, 0.06)
	tw.tween_callback(func() -> void: pn.remove_meta("shaking"))


func fx_target_ring(seat: int, col: Color) -> void:
	if fx_root == null:
		return
	var pn := seat_panel_of(seat)
	if pn == null:
		return
	var ring := Panel.new()
	ring.position = pn.position - Vector2(10, 10)
	ring.size = pn.size + Vector2(20, 20)
	ring.pivot_offset = ring.size * 0.5
	ring.mouse_filter = MOUSE_FILTER_IGNORE
	ring.add_theme_stylebox_override("panel", style(Color(0, 0, 0, 0), 22, col, 4))
	fx_root.add_child(ring)
	var tw := create_tween().bind_node(ring)
	tw.tween_property(ring, "scale", Vector2(1.035, 1.035), 0.16)
	tw.tween_property(ring, "scale", Vector2.ONE, 0.16)
	tw.tween_property(ring, "scale", Vector2(1.035, 1.035), 0.16)
	tw.tween_property(ring, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void: if is_instance_valid(ring): ring.queue_free())


func fx_target_mark(src_seat: int, tgt_seat: int) -> void:
	if fx_root == null or src_seat < 0 or tgt_seat < 0 or src_seat == tgt_seat:
		return
	fx_target_ring(tgt_seat, Color(1.0, 0.72, 0.25, 0.95))
	var a := seat_center(src_seat)
	var b := seat_center(tgt_seat)
	var d := b - a
	var line := ColorRect.new()
	line.color = Color(1.0, 0.72, 0.25, 0.8)
	line.size = Vector2(d.length(), 5)
	line.position = a + Vector2(0, -2.5)
	line.pivot_offset = Vector2(0, 2.5)
	line.rotation = d.angle()
	line.mouse_filter = MOUSE_FILTER_IGNORE
	fx_root.add_child(line)
	var twl := create_tween().bind_node(line)
	twl.tween_interval(0.6)
	twl.tween_property(line, "modulate:a", 0.0, 0.25)
	twl.tween_callback(func() -> void: if is_instance_valid(line): line.queue_free())
	var dot := Panel.new()
	dot.size = Vector2(24, 24)
	dot.pivot_offset = Vector2(12, 12)
	dot.position = a - Vector2(12, 12)
	dot.rotation = 0.785
	dot.mouse_filter = MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", style(Color(1.0, 0.78, 0.30, 1.0), 4, Color(1, 1, 1, 0.95), 2))
	fx_root.add_child(dot)
	var tw := create_tween().bind_node(dot)
	tw.tween_property(dot, "position", b - Vector2(12, 12), 0.24)
	tw.tween_property(dot, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void: if is_instance_valid(dot): dot.queue_free())


func fx_attack_fx(src_seat: int, tgt_seat: int, nature: String = "") -> void:
	if fx_root == null or src_seat == tgt_seat:
		return
	fx_burst(src_seat, tgt_seat)
	fx_target_ring(tgt_seat, Color(1.0, 0.30, 0.40, 0.95))
	var a := seat_center(src_seat)
	var b := seat_center(tgt_seat)
	var d := b - a
	var line := ColorRect.new()
	line.color = Color(1.0, 0.35, 0.5, 0.75)
	line.size = Vector2(d.length(), 6)
	line.position = a + Vector2(0, -3)
	line.pivot_offset = Vector2(0, 3)
	line.rotation = d.angle()
	line.mouse_filter = MOUSE_FILTER_IGNORE
	fx_root.add_child(line)
	var twl := create_tween().bind_node(line)
	twl.tween_interval(0.28)
	twl.tween_property(line, "modulate:a", 0.0, 0.25)
	twl.tween_callback(func() -> void: if is_instance_valid(line): line.queue_free())
	var dot := Panel.new()
	dot.size = Vector2(30, 30)
	dot.pivot_offset = Vector2(15, 15)
	dot.position = a - Vector2(15, 15)
	dot.mouse_filter = MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", style(Color(1.0, 0.8, 0.3, 1.0), 15, Color(1, 1, 1, 0.9), 2))
	fx_root.add_child(dot)
	var tw := create_tween().bind_node(dot)
	tw.tween_property(dot, "position", b - Vector2(15, 15), 0.2)
	tw.tween_callback(func() -> void:
		if is_instance_valid(dot): dot.queue_free()
		fx_slash(tgt_seat, nature)
		fx_float(tgt_seat, "✕", Color(0.95, 0.2, 0.3), 64, 40.0)
	)


# 出框攻击（对标琉璃版）：攻击者立绘放大冲出座位框、朝目标方向扑出，再回位淡出
func fx_burst(src_seat: int, tgt_seat: int) -> void:
	if fx_root == null or fast or src_seat < 0 or src_seat >= players.size():
		return
	var pn := seat_panel_of(src_seat)
	if pn == null:
		return
	if burst_tween and burst_tween.is_valid():
		burst_tween.kill()
	if burst_node != null and is_instance_valid(burst_node):
		burst_node.queue_free()
	burst_node = null
	var p: Dictionary = players[src_seat]
	var ch: Dictionary = p.get("char", {})
	if not ch.has("portrait"):
		return
	var base_pos := pn.position
	var base_size := pn.size
	var big_size := base_size * 1.45
	var dir := seat_center(tgt_seat) - seat_center(src_seat)
	var dist := dir.length()
	if dist > 1.0:
		dir = dir / dist
	else:
		dir = Vector2.DOWN
	var big_center := seat_center(src_seat) + dir * minf(dist * 0.30, 190.0)
	big_center.x = clampf(big_center.x, big_size.x * 0.5 + 6.0, vw - big_size.x * 0.5 - 6.0)
	big_center.y = clampf(big_center.y, big_size.y * 0.5 + 6.0, 1080.0 - big_size.y * 0.5 - 6.0)
	# V0.31：出框的是整张 CG 卡（金框 + 竖排名牌），用 scale 放大冲出，不再改 size（子节点不随 size 缩放）
	var holder := Art.cg_card(ch, base_size, {"zoom": 0.72, "face_y": 0.32, "fs": 26, "hp": false, "title": false})
	holder.name = "BurstCG"
	holder.position = base_pos
	holder.pivot_offset = base_size * 0.5
	holder.rotation = clampf(dir.x * 0.05, -0.05, 0.05)
	var glow := Panel.new()
	glow.name = "Glow"
	glow.size = base_size
	glow.mouse_filter = MOUSE_FILTER_IGNORE
	glow.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0), 18, Color(1.0, 0.85, 0.4, 0.95) if src_seat == 0 else Color(1.0, 0.45, 0.6, 0.95), 5, true))
	holder.add_child(glow)
	fx_root.add_child(holder)
	burst_node = holder
	var big_scale := Vector2(1.45, 1.45)
	var big_pos := big_center - base_size * 0.5
	burst_tween = create_tween().bind_node(holder)
	burst_tween.tween_property(holder, "position", big_pos, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	burst_tween.parallel().tween_property(holder, "scale", big_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	burst_tween.tween_interval(0.30)
	burst_tween.tween_property(holder, "position", base_pos, 0.22)
	burst_tween.parallel().tween_property(holder, "scale", Vector2.ONE, 0.22)
	burst_tween.parallel().tween_property(holder, "modulate:a", 0.0, 0.22)
	burst_tween.tween_callback(func() -> void:
		if is_instance_valid(holder): holder.queue_free()
		if burst_node == holder: burst_node = null
	)


# 斩击光轨：三道斜向光刃在目标座位上交错扫过（颜色随突击属性：普通金/火橙/雷紫/冰青）
func fx_slash(tgt_seat: int, nature: String = "") -> void:
	if fx_root == null:
		return
	var c := seat_center(tgt_seat)
	var col := Color(1.0, 0.80, 0.30)
	if nature == "火":
		col = Color(1.0, 0.50, 0.15)
	elif nature == "雷":
		col = Color(0.70, 0.55, 1.0)
	elif nature == "冰":
		col = Color(0.45, 0.80, 1.0)
	var defs := [[320.0, 14.0, -52.0, 0.0], [268.0, 9.0, 4.0, 0.07], [216.0, 6.0, 56.0, 0.14]]
	for d in defs:
		var len_ := float(d[0])
		var h := float(d[1])
		var bar := Panel.new()
		bar.size = Vector2(len_, h)
		bar.pivot_offset = Vector2(len_ * 0.5, h * 0.5)
		bar.position = c + Vector2(-len_ * 0.5 - 26.0, float(d[2]))
		bar.rotation = -0.62
		bar.mouse_filter = MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("panel", style(Color(col.r, col.g, col.b, 0.85), int(h * 0.5)))
		var core := Panel.new()
		core.size = Vector2(len_, maxf(h * 0.42, 2.0))
		core.position = Vector2(0, (h - core.size.y) * 0.5)
		core.mouse_filter = MOUSE_FILTER_IGNORE
		core.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.95), int(core.size.y * 0.5)))
		bar.add_child(core)
		fx_root.add_child(bar)
		bar.modulate.a = 0.0
		var tw := create_tween().bind_node(bar)
		tw.tween_interval(float(d[3]))
		tw.tween_property(bar, "modulate:a", 1.0, 0.05)
		tw.parallel().tween_property(bar, "position:x", bar.position.x + 52.0, 0.17)
		tw.tween_property(bar, "modulate:a", 0.0, 0.15)
		tw.tween_callback(func() -> void: if is_instance_valid(bar): bar.queue_free())


func fx_skill_banner(seat: int, skill_name: String) -> void:
	if fx_root == null or auto_all or fx_root.get_child_count() > FX_CAP:
		return
	# V0.25 技能名横幅：深色缎带底（先横向展开）+ 金字 + 扫光，对照十周年发动技能的名字条（代码绘制，无贴图）
	var c0 := seat_center(seat)
	var bx := clampf(c0.x - 190.0, 8.0, vw - 388.0)
	var rib := Panel.new()
	rib.size = Vector2(380, 62)
	rib.position = Vector2(bx, c0.y - 139)
	rib.pivot_offset = Vector2(190, 31)
	rib.mouse_filter = MOUSE_FILTER_IGNORE
	rib.add_theme_stylebox_override("panel", style(Color(0.20, 0.10, 0.26, 0.88), 31, Color(1.0, 0.78, 0.35, 0.95), 3, true))
	fx_root.add_child(rib)
	for side in [-1, 1]:
		var tail := Panel.new()
		tail.size = Vector2(30, 30)
		tail.rotation = PI / 4.0
		tail.position = Vector2(190 + side * 196 - 15, 10)
		tail.mouse_filter = MOUSE_FILTER_IGNORE
		tail.add_theme_stylebox_override("panel", style(Color(1.0, 0.78, 0.35, 0.9), 4))
		rib.add_child(tail)
	rib.scale = Vector2(0.05, 1.0)
	var rtw := create_tween().bind_node(rib)
	rtw.tween_property(rib, "scale:x", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rtw.tween_interval(0.66)
	rtw.tween_property(rib, "modulate:a", 0.0, 0.3)
	rtw.tween_callback(func() -> void: if is_instance_valid(rib): rib.queue_free())
	var lb := lbl("【%s】" % skill_name, 42, Color(1.0, 0.80, 0.30), true, HORIZONTAL_ALIGNMENT_CENTER)
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	lb.size = Vector2(340, 60)
	lb.pivot_offset = Vector2(170, 30)
	lb.position = Vector2(bx + 20, c0.y - 138)
	lb.mouse_filter = MOUSE_FILTER_IGNORE
	lb.add_theme_constant_override("outline_size", 9)
	lb.add_theme_color_override("font_outline_color", Color(0.5, 0.22, 0.3, 0.95))
	fx_root.add_child(lb)
	var sheen := Panel.new()
	sheen.size = Vector2(46, 64)
	sheen.position = lb.position + Vector2(-30, -2)
	sheen.rotation = 0.35
	sheen.mouse_filter = MOUSE_FILTER_IGNORE
	sheen.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.5), 6))
	fx_root.add_child(sheen)
	var stw := create_tween().bind_node(sheen)
	stw.tween_property(sheen, "position:x", lb.position.x + 330.0, 0.45).set_delay(0.18)
	stw.parallel().tween_property(sheen, "modulate:a", 0.0, 0.45).set_delay(0.18)
	stw.tween_callback(func() -> void: if is_instance_valid(sheen): sheen.queue_free())
	lb.scale = Vector2(0.4, 0.4)
	var tw := create_tween().bind_node(lb)
	tw.tween_property(lb, "scale", Vector2(1.08, 1.08), 0.16)
	tw.tween_property(lb, "scale", Vector2.ONE, 0.08)
	tw.tween_interval(0.55)
	tw.tween_property(lb, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void: if is_instance_valid(lb): lb.queue_free())


func show_turn_banner(char_name: String) -> void:
	if turn_banner == null:
		return
	turn_banner.text = "— %s 的回合 —" % char_name
	if turn_banner_tween and turn_banner_tween.is_valid():
		turn_banner_tween.kill()
	turn_banner.modulate = Color(1, 1, 1, 0)
	turn_banner_tween = create_tween()
	turn_banner_tween.tween_property(turn_banner, "modulate:a", 1.0, 0.18)
	turn_banner_tween.tween_interval(0.75)
	turn_banner_tween.tween_property(turn_banner, "modulate:a", 0.0, 0.35)


func _eng_fx(kind: String, data: Dictionary) -> void:
	if fx_root == null or players.is_empty():
		return
	var seat := int(data.get("seat", -1))
	match kind:
		"damage":
			var dcol := Color(0.92, 0.18, 0.28)
			var nat := String(data.get("nature", ""))
			if nat == "火":
				dcol = Color(1.0, 0.52, 0.16)
			elif nat == "雷":
				dcol = Color(0.65, 0.45, 1.0)
			elif nat == "冰":
				dcol = Color(0.40, 0.75, 1.0)
			fx_float(seat, "-%d" % int(data["num"]), dcol, 60)
			fx_shake(seat)
			fx_flash(seat, Color(1.0, 0.25, 0.35))
			if seat == 0:
				fx_vignette()
			play_sfx("hit")
			if randf() < 0.35:
				show_bubble(seat, "hurt")
		"heal":
			fx_float(seat, "+%d" % int(data["num"]), Color(0.25, 0.78, 0.38), 56)
			fx_flash(seat, Color(0.4, 1.0, 0.55))
			play_sfx("heal")
			if randf() < 0.3:
				show_bubble(seat, "heal")
		"draw":
			fx_draw_fly(seat, int(data["n"]))
			play_sfx("draw")
		"skill":
			_count_skill(seat, String(data.get("name", "")))
			if bool(data.get("big", false)) and not fast:
				fx_cutin(seat, String(data["name"]))
			else:
				fx_skill_banner(seat, String(data["name"]))
			play_sfx("skill")
			show_bubble(seat, "skill")
		"judge":
			_pz_judge(seat, data["card"], String(data["label"]))
			play_sfx("judge")
		"trick":
			_nullify_reset()
			play_sfx("trick")
		"equip":
			fx_equip_fly(seat, String(data.get("name", "")))
			play_sfx("equip")
		"attack":
			fx_attack_fx(int(data["src_seat"]), int(data["tgt_seat"]), String(data.get("nature", "")))
			play_sfx("slash")
		"yingbian":
			fx_float(seat, String(data.get("text", "应变")), Color(0.95, 0.45, 0.75), 40, 70.0)
			play_sfx("skill")
		"target":
			fx_target_mark(int(data.get("src_seat", -1)), int(data.get("tgt_seat", -1)))
			if randf() < 0.3:
				show_bubble(int(data["src_seat"]), "attack")
		"dodge":
			fx_float(seat, "闪避！", Color(0.3, 0.6, 1.0), 44, 60.0)
			play_sfx("dodge")
		"dying":
			fx_float(seat, "濒死！", Color(0.75, 0.15, 0.6), 56, 50.0)
			fx_flash(seat, Color(0.9, 0.1, 0.4))
			play_sfx("dying")
			show_bubble(seat, "dying")
			fx_dying_show(seat)
		"death":
			_fx_reveal_gem(seat)
			play_sfx("death")
			show_bubble(seat, "death")
			if seat == dying_seat:
				fx_dying_hide()
		"revived":
			if seat == dying_seat:
				fx_dying_hide()
			fx_float(seat, "获救！", Color(0.25, 0.78, 0.38), 48, 50.0)
			play_sfx("revive")
		"nullify":
			fx_float(seat, "看破！", Color(0.85, 0.62, 0.1), 50, 55.0)
			_nullify_push(seat, bool(data.get("negated", true)))
			play_sfx("nullify")
		"chain":
			if bool(data.get("on", false)):
				fx_float(seat, "锁链！", Color(0.35, 0.45, 0.9), 44, 55.0)
				fx_target_ring(seat, Color(0.45, 0.55, 1.0))
			else:
				fx_float(seat, "解开", Color(0.55, 0.55, 0.6), 40, 55.0)
			play_sfx("chain")
		"chain_hit":
			fx_float(seat, "传导！", Color(1.0, 0.52, 0.16), 44, 60.0)
			fx_target_ring(seat, Color(1.0, 0.52, 0.16))
			play_sfx("hit")
		"heavy_hit":
			var hnum := int(data.get("num", 2))
			var htitle := "万夫莫敌 · 无双乱舞！" if hnum >= 3 else "雷霆万钧 · 癫狂屠戮！"
			fx_spree_banner(htitle, "单次造成 %d 点高额伤害" % hnum, false)
			fx_screen_shake()
		"kill_spree":
			var kcnt := int(data.get("kills", 1))
			var knm := String(data.get("name", ""))
			var ktitles := {1: "一破 · 卧龙出山", 2: "双连 · 一战成名", 3: "三连 · 举世皆惊"}
			var ktitle := String(ktitles.get(kcnt, "四连 · 天下无双"))
			fx_spree_banner(ktitle, "%s 已累计击杀 %d 人" % [knm, kcnt], true)
			fx_screen_shake()
		"awaken":
			var awk_nm := String(data.get("name", "觉醒"))
			var awk_ch := String(data.get("char", ""))
			fx_spree_banner("★ 觉醒 · %s ★" % awk_nm, "%s 突破界限，习得新技能！" % awk_ch, true)
			fx_screen_shake()
			play_sfx("win")
		"switch_skill":
			var sw_st := String(data.get("state", "阳"))
			fx_float(seat, "☯ 转为【%s】" % sw_st, Color(0.76, 0.54, 1.0), 42, 66.0)
		"pindian":
			var s_seat := int(data.get("src_seat", 0))
			var t_seat := int(data.get("tgt_seat", 1))
			var sc: Dictionary = data.get("src_card", {})
			var tc: Dictionary = data.get("tgt_card", {})
			var spt := int(data.get("src_pt", 0))
			var tpt := int(data.get("tgt_pt", 0))
			var pwin := bool(data.get("win", false))
			if not sc.is_empty():
				_pz_add(sc, "%s 拼点(%d点)%s" % [_short_name(pname(players[s_seat])), spt, "★胜" if pwin else ""], seat_center(s_seat))
			if not tc.is_empty():
				_pz_add(tc, "%s 拼点(%d点)%s" % [_short_name(pname(players[t_seat])), tpt, "★胜" if not pwin else ""], seat_center(t_seat))
			fx_float(s_seat, "⚡拼点胜！" if pwin else "拼点未赢", Color(1.0, 0.80, 0.22) if pwin else Color(0.70, 0.72, 0.82), 46, 68.0)
			play_sfx("skill" if pwin else "card")
		"shield":
			var sh_d := int(data.get("delta", 1))
			var sh_col := Color(0.35, 0.78, 1.0) if sh_d > 0 else Color(0.75, 0.85, 0.95)
			fx_float(seat, ("🛡护甲+%d" % sh_d) if sh_d > 0 else ("🛡抵消%d" % (-sh_d)), sh_col, 44, 62.0)
			play_sfx("equip" if sh_d > 0 else "dodge")


# ---------------- 濒死救援特写 ----------------

func fx_dying_show(seat: int) -> void:
	fx_dying_hide()
	if seat < 0 or seat >= players.size() or fx_root == null:
		return
	dying_seat = seat
	var p: Dictionary = players[seat]
	var holder := PanelContainer.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.97), 22, Color(0.85, 0.2, 0.35), 5, true))
	holder.position = Vector2(vw / 2.0 - 200, 168)
	holder.size = Vector2(400, 540)
	var vb := VBoxContainer.new()
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 8)
	holder.add_child(vb)
	var dcc := Art.cg_card(p["char"], Vector2(368, 396), {"zoom": 0.78, "face_y": 0.30, "fs": 32, "title": false})
	dcc.name = "DyingCG"
	vb.add_child(dcc)
	var cap := lbl("%s 濒临死亡！" % pname(p), 36, Color(0.85, 0.15, 0.3), true)
	cap.mouse_filter = MOUSE_FILTER_IGNORE
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cap)
	var savers: Array = []
	for q in players:
		if not q["alive"]:
			continue
		var can := false
		for c in q["hand"]:
			if String(c["name"]) == "补给":
				can = true
			if q == p and String(c["name"]) == "特饮":
				can = true
		if can:
			savers.append(pname(q))
	var sub := lbl("可救援：" + ("、".join(PackedStringArray(savers)) if not savers.is_empty() else "无人持有补给"), 21, Color(0.45, 0.3, 0.35))
	sub.mouse_filter = MOUSE_FILTER_IGNORE
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	fx_root.add_child(holder)
	dying_holder = holder
	holder.pivot_offset = Vector2(200, 270)
	holder.scale = Vector2(0.92, 0.92)
	var tw := create_tween().bind_node(holder)
	tw.set_loops()
	tw.tween_property(holder, "scale", Vector2(1.0, 1.0), 0.55)
	tw.tween_property(holder, "scale", Vector2(0.94, 0.94), 0.55)


func fx_dying_hide() -> void:
	if dying_holder != null and is_instance_valid(dying_holder):
		dying_holder.queue_free()
	dying_holder = null
	dying_seat = -1


# ---------------- 程序合成音效（无外部音频资源） ----------------

func _ensure_sfx() -> void:
	if not sfx_players.is_empty():
		var ok := true
		for pl0 in sfx_players:
			if not is_instance_valid(pl0) or not (pl0 as Node).is_inside_tree():
				ok = false
		if ok:
			return
		# V0.30：重建界面后旧播放器已离开场景树（会报 Playback can only happen...），重新创建
		for pl1 in sfx_players:
			if is_instance_valid(pl1) and not (pl1 as Node).is_inside_tree():
				(pl1 as Node).queue_free()
		sfx_players.clear()
	AudioCfg.ensure()
	for i in 8:
		var pl := AudioStreamPlayer.new()
		pl.bus = "SFX"
		add_child(pl)
		sfx_players.append(pl)
	sfx_streams["hit"] = _synth_hit()
	sfx_streams["heal"] = _synth_melody([660.0, 880.0], 0.09)
	sfx_streams["skill"] = _synth_melody([990.0, 1320.0], 0.07)
	sfx_streams["draw"] = _synth_melody([1250.0], 0.05)
	sfx_streams["dodge"] = _synth_melody([520.0, 940.0], 0.05)
	sfx_streams["win"] = _synth_melody([523.0, 659.0, 784.0, 1047.0], 0.11)
	sfx_streams["lose"] = _synth_melody([392.0, 330.0, 262.0], 0.16)
	sfx_streams["judge"] = _synth_melody([1047.0, 1319.0], 0.06)
	sfx_streams["trick"] = _synth_melody([740.0, 587.0], 0.07)
	sfx_streams["equip"] = _synth_melody([440.0, 554.0, 659.0], 0.05)
	sfx_streams["slash"] = _synth_melody([1560.0, 1180.0, 880.0], 0.035)
	sfx_streams["dying"] = _synth_melody([620.0, 620.0, 620.0], 0.12)
	sfx_streams["death"] = _synth_melody([330.0, 262.0, 196.0], 0.18)
	sfx_streams["revive"] = _synth_melody([523.0, 659.0, 784.0], 0.08)
	sfx_streams["nullify"] = _synth_melody([988.0, 988.0], 0.05)
	sfx_streams["chain"] = _synth_melody([494.0, 494.0, 659.0], 0.06)
	# V0.17.0 音效补全：锦囊/装备/判定/攻击挥击/锁链/看破/濒死/阵亡/获救/胜负结算
	sfx_streams["trick"] = _synth_melody([880.0, 1174.0, 1568.0], 0.06)
	sfx_streams["equip"] = _synth_clink()
	sfx_streams["judge"] = _synth_melody([330.0, 330.0, 659.0], 0.1)
	sfx_streams["slash"] = _synth_whoosh()
	sfx_streams["chain"] = _synth_chain()
	sfx_streams["nullify"] = _synth_melody([988.0, 587.0], 0.09)
	sfx_streams["dying"] = _synth_melody([196.0, 196.0, 147.0], 0.12)
	sfx_streams["death"] = _synth_melody([392.0, 311.0, 262.0, 196.0], 0.13)
	sfx_streams["revive"] = _synth_melody([523.0, 659.0, 784.0, 1047.0], 0.08)
	sfx_streams["win"] = _synth_melody([523.0, 659.0, 784.0, 1047.0, 1319.0], 0.11)
	sfx_streams["lose"] = _synth_melody([392.0, 370.0, 349.0, 262.0], 0.14)
	# V0.30：有文件音效的事件改用 assets/sfx/*.ogg（统一音色），其余保留程序合成
	for k in AudioCfg.SFX_FILES:
		var st := AudioCfg.sfx_stream(k)
		if st != null:
			sfx_streams[k] = st
	if voice_player != null and is_instance_valid(voice_player):
		voice_player.queue_free()
	voice_player = AudioStreamPlayer.new()
	voice_player.bus = "Voice"
	add_child(voice_player)


const VOICE_KEYS := {"slash": "attack", "dodge": "dodge", "heal": "heal", "dying": "dying", "win": "win", "lose": "lose", "skill": "skill"}


func play_sfx(key: String) -> void:
	if auto_all or fast or not is_inside_tree():
		return
	if not sfx_streams.has(key):
		return
	sfx_count += 1
	# 语音（有打包语音文件且开启时才会响；当前版本未打包）
	if VOICE_KEYS.has(key) and voice_player != null and not voice_player.playing and bool(AudioCfg.get_v("voice_on")):
		var vs := AudioCfg.voice_stream(String(VOICE_KEYS[key]))
		if vs != null:
			if voice_player.is_inside_tree():
				voice_player.stream = vs
				voice_player.play()
	for pl in sfx_players:
		if not is_instance_valid(pl) or not (pl as Node).is_inside_tree():
			continue
		if not (pl as AudioStreamPlayer).playing:
			(pl as AudioStreamPlayer).stream = sfx_streams[key]
			(pl as AudioStreamPlayer).play()
			return


func _synth_melody(freqs: Array, step: float) -> AudioStreamWAV:
	var rate := 22050
	var total := int(rate * step * freqs.size()) + 800
	var bytes := PackedByteArray()
	bytes.resize(total)
	for i in total:
		var t := float(i) / rate
		var idx := mini(int(t / step), freqs.size() - 1)
		var f := float(freqs[idx])
		var lt := t - idx * step
		var env := clampf(1.0 - lt / (step * 1.6), 0.0, 1.0)
		var v := sin(TAU * f * t) * env * 0.5
		bytes[i] = int(clampf(128.0 + v * 110.0, 0.0, 255.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


func _synth_whoosh() -> AudioStreamWAV:
	# 挥击：噪声包络先升后降＋下行啁啾，模拟破空声
	var rate := 22050
	var dur := 0.18
	var total := int(rate * dur)
	var bytes := PackedByteArray()
	bytes.resize(total)
	var seed := 777
	var phase := 0.0
	for i in total:
		var t := float(i) / rate
		seed = (seed * 1103515245 + 12345) % 2147483648
		var noise := (float(seed % 2000) / 1000.0 - 1.0)
		var f := 1400.0 - 900.0 * (t / dur)
		phase += TAU * f / rate
		var env := sin(PI * t / dur)
		var v := (noise * 0.55 + sin(phase) * 0.3) * env
		bytes[i] = int(clampf(128.0 + v * 105.0, 0.0, 255.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


func _synth_clink() -> AudioStreamWAV:
	# 装备：两次金属轻击（高频正弦＋泛音，指数衰减）
	var rate := 22050
	var dur := 0.2
	var total := int(rate * dur)
	var bytes := PackedByteArray()
	bytes.resize(total)
	for i in total:
		var t := float(i) / rate
		var v := 0.0
		for hit_t in [0.0, 0.055]:
			if t >= float(hit_t):
				var lt: float = t - float(hit_t)
				var dec := exp(-lt * 38.0)
				v += (sin(TAU * 2093.0 * lt) * 0.6 + sin(TAU * 2637.0 * lt) * 0.35 + sin(TAU * 3520.0 * lt) * 0.2) * dec
		bytes[i] = int(clampf(128.0 + v * 62.0, 0.0, 255.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


func _synth_chain() -> AudioStreamWAV:
	# 锁链：四下短促噪声咔哒，间隔递减
	var rate := 22050
	var dur := 0.24
	var total := int(rate * dur)
	var bytes := PackedByteArray()
	bytes.resize(total)
	var seed := 4242
	var ticks := [0.0, 0.06, 0.115, 0.165]
	for i in total:
		var t := float(i) / rate
		seed = (seed * 1103515245 + 12345) % 2147483648
		var noise := (float(seed % 2000) / 1000.0 - 1.0)
		var v := 0.0
		for tt in ticks:
			var lt: float = t - float(tt)
			if lt >= 0.0 and lt < 0.035:
				v += noise * (1.0 - lt / 0.035) * 0.8 + sin(TAU * 1180.0 * lt) * (1.0 - lt / 0.035) * 0.3
		bytes[i] = int(clampf(128.0 + v * 100.0, 0.0, 255.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


func _synth_hit() -> AudioStreamWAV:
	var rate := 22050
	var total := int(rate * 0.14)
	var bytes := PackedByteArray()
	bytes.resize(total)
	var seed := 12345
	for i in total:
		var t := float(i) / rate
		seed = (seed * 1103515245 + 12345) % 2147483648
		var noise := (float(seed % 2000) / 1000.0 - 1.0)
		var env := clampf(1.0 - t / 0.14, 0.0, 1.0)
		var thump := sin(TAU * (150.0 - 700.0 * t) * t) * 0.7
		var v := (noise * 0.35 + thump) * env
		bytes[i] = int(clampf(128.0 + v * 105.0, 0.0, 255.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


func show_match_banner() -> void:
	if match_banner == null:
		return
	match_banner.text = "对 局 开 始"
	if match_banner_tween and match_banner_tween.is_valid():
		match_banner_tween.kill()
	match_banner.modulate = Color(1, 1, 1, 0)
	match_banner.scale = Vector2(0.6, 0.6)
	match_banner.pivot_offset = Vector2(960, 60)
	match_banner_tween = create_tween()
	match_banner_tween.tween_property(match_banner, "modulate:a", 1.0, 0.15)
	match_banner_tween.parallel().tween_property(match_banner, "scale", Vector2.ONE, 0.2)
	match_banner_tween.tween_interval(0.6)
	match_banner_tween.tween_property(match_banner, "modulate:a", 0.0, 0.3)


func fx_cutin(seat: int, skill_name: String) -> void:
	if fx_root == null or seat < 0 or seat >= players.size():
		return
	var p: Dictionary = players[seat]
	var ch: Dictionary = p.get("char", {})
	if not ch.has("portrait"):
		fx_skill_banner(seat, skill_name)
		return
	var from_left := seat <= 2
	var holder := PanelContainer.new()
	holder.size = Vector2(430, 545)
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.97), 22, Color(1.0, 0.72, 0.25), 5, true))
	var vb := VBoxContainer.new()
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	holder.add_child(vb)
	var ccc := Art.cg_card(ch, Vector2(400, 440), {"zoom": 0.82, "face_y": 0.30, "fs": 34, "title": false})
	ccc.name = "CutinCG"
	vb.add_child(ccc)
	var cap := lbl("【%s】%s" % [skill_name, String(ch["name"])], 34, C_PINK_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER)
	cap.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_child(cap)
	var start_x := -450.0 if from_left else vw
	var end_x := 110.0 if from_left else vw - 540.0
	holder.position = Vector2(start_x, 235)
	fx_root.add_child(holder)
	var tw := create_tween().bind_node(holder)
	tw.tween_property(holder, "position:x", end_x, 0.26)
	tw.tween_interval(0.7)
	tw.tween_property(holder, "position:x", start_x, 0.26)
	tw.tween_callback(func() -> void: if is_instance_valid(holder): holder.queue_free())


func fx_vignette() -> void:
	if fx_root == null:
		return
	var ov := Panel.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = MOUSE_FILTER_IGNORE
	ov.add_theme_stylebox_override("panel", style(Color(0, 0, 0, 0), 0, Color(1.0, 0.2, 0.3, 0.85), 34))
	fx_root.add_child(ov)
	var tw := create_tween().bind_node(ov)
	tw.tween_property(ov, "modulate:a", 0.0, 0.55)
	tw.tween_callback(func() -> void: if is_instance_valid(ov): ov.queue_free())


func fx_screen_shake() -> void:
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(7, 3), 0.05)
	tw.tween_property(self, "position", Vector2(-7, -2), 0.07)
	tw.tween_property(self, "position", Vector2(4, 1), 0.06)
	tw.tween_property(self, "position", Vector2.ZERO, 0.06)


func _short_name(s: String) -> String:
	if s.begins_with("你"):
		return "你"
	var k := s.find("（")
	return s.substr(0, k) if k > 0 else s


# ================= V0.26 长按说明卡：各来源的规格提供 =================
const SETTINGS_PATH := "user://settings.cfg"
var skill_use_count := {}  # seat -> {技能名: 次数}
var first_hint_label: Label = null


func _lp_swallowing() -> bool:
	return IntroPop.inst != null and IntroPop.inst.swallowing()


func _intro_card(c: Dictionary) -> Dictionary:
	return IntroPop.card_spec(c)


func _count_skill(seat: int, nm: String) -> void:
	if seat < 0 or nm == "":
		return
	var d: Dictionary = skill_use_count.get(seat, {})
	d[nm] = int(d.get(nm, 0)) + 1
	skill_use_count[seat] = d


func _skill_used_text(seat: int, nm: String) -> String:
	var n := int((skill_use_count.get(seat, {}) as Dictionary).get(nm, 0))
	return "本局已发动 %d 次" % n if n > 0 else "本局尚未发动"


const DDZ_SKILLS := [
	{"name": "飞扬", "text": "地主技。判定阶段开始时，若你的判定区有牌，你可以弃置两张手牌，然后弃置你判定区里的一张牌。"},
	{"name": "跋扈", "text": "地主技，锁定技。准备阶段，你摸一张牌；出牌阶段，你可以多使用一张【突击】。"},
]


# 座位上角色的技能列表（含是否主动）：角色自带技能 + 斗地主地主技
func _skills_of(p: Dictionary) -> Array:
	var out: Array = []
	var texts := {}
	for sk in (p["char"].get("skills", []) as Array):
		texts[String(sk.get("sid", ""))] = sk
	var sids: Array = p.get("skills", [])
	for sid in sids:
		var sk2: Dictionary = texts.get(String(sid), {})
		var def: Dictionary = eng.skill_lib.get(sid, {}) if eng != null else {}
		var nm := String(sk2.get("name", def.get("name", sid)))
		out.append({"name": nm, "text": String(sk2.get("text", def.get("text", "（暂无说明）"))), "active": def.has("active")})
	if sids.is_empty():
		for sk3 in (p["char"].get("skills", []) as Array):
			out.append({"name": String(sk3["name"]), "text": String(sk3["text"]), "active": sk3.has("btn")})
	if game_mode == "doudizhu" and String(p.get("identity", "")) == "地主":
		for d in DDZ_SKILLS:
			out.append({"name": d["name"], "text": d["text"], "active": false})
	return out


func _intro_skill_sid(sid: String) -> Dictionary:
	if players.is_empty():
		return {}
	var me: Dictionary = players[0]
	for sk in _skills_of(me):
		var def: Dictionary = eng.skill_lib.get(sid, {}) if eng != null else {}
		if String(sk["name"]) == String(def.get("name", sid)):
			return IntroPop.skill_spec(String(sk["name"]), String(sk["text"]), bool(sk["active"]), _skill_used_text(0, String(sk["name"])))
	return {}


func _seat_of_node(pn: Control) -> int:
	if pn == null or not is_instance_valid(pn):
		return -1
	if pn == me_panel_ref:
		return 0
	return int(pn.get_meta("seat")) if pn.has_meta("seat") else -1


func _intro_equip(pn: Control, slot: String) -> Dictionary:
	var seat := _seat_of_node(pn)
	if seat < 0 or seat >= players.size():
		return {}
	var e: Dictionary = players[seat]["equip"][slot]
	if e.is_empty():
		return {}
	var sp: Dictionary = IntroPop.card_spec(e)
	if String(e.get("name", "")) == "木牛流马":
		var n := (e.get("stored", []) as Array).size()
		sp["body"] = String(sp["body"]) + "\n[color=#9df0a8]当前「粮」：%d 张[/color]" % n
	return sp


func _intro_judge(pn: Control, i: int) -> Dictionary:
	var seat := _seat_of_node(pn)
	if seat < 0 or seat >= players.size():
		return {}
	var js: Array = players[seat]["judge"]
	if i >= js.size():
		return {}
	var c: Dictionary = js[i]
	var sp: Dictionary = IntroPop.card_spec(c)
	if String(c.get("name", "")) == "浮雷":
		sp["body"] = String(sp["body"]) + "\n[color=#ff8a8a]已累计生效 %d 次[/color]" % int(c.get("fulei_x", 0))
	return sp


func _intro_seat(seat: int) -> Dictionary:
	if seat < 0 or seat >= players.size():
		return {}
	var p: Dictionary = players[seat]
	var me: Dictionary = players[0]
	var rt := {}
	var p_sh2 := int(p.get("shield", 0))
	var sh_part := (" · 护甲 🛡%d" % p_sh2) if p_sh2 > 0 else ""
	rt["hp_line"] = ("体力 %d/%d%s" % [maxi(int(p["hp"]), 0), int(p["max_hp"]), sh_part]) if bool(p["alive"]) else "已阵亡"
	var idv := identity_visible(p)
	if idv == "？？":
		var gm := String(guess_marks.get(seat, ""))
		rt["ident"] = "身份未知（你猜：%s）" % gm if gm != "" else "身份未知"
	else:
		rt["ident"] = "身份：%s" % idv
	var st: Array = []
	st.append("手牌 %d 张" % (p["hand"] as Array).size())
	st.append("攻击范围 %d" % weapon_range(p))
	if seat != 0 and bool(p["alive"]) and bool(me["alive"]):
		st.append("与你的距离 %d" % eff_dist(me, p))
		st.append("你能突击到TA" if attack_reachable(me, {"name": "突击"}, p) else "不在你的攻击范围内")
	if bool(p.get("chained", false)):
		st.append("连环状态")
	if (game_mode == "twovtwo" or game_mode == "boss") and seat != 0 and String(p["identity"]) == String(me["identity"]):
		var mcards: Array = []
		for mc in p["hand"]:
			mcards.append(card_text(mc))
		st.append("队友手牌：" + ("、".join(PackedStringArray(mcards)) if not mcards.is_empty() else "无"))
	rt["stats"] = "  ·  ".join(PackedStringArray(st))
	rt["skills"] = _skills_of(p)
	rt["used"] = skill_use_count.get(seat, {})
	var eq_lines: Array = []
	var slot_nm := {"weapon": "武器", "armor": "防具", "minus": "-1 坐骑", "plus": "+1 坐骑", "treasure": "宝物"}
	for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
		var e: Dictionary = p["equip"][slot]
		if e.is_empty():
			continue
		var nm := String(e["name"])
		var extra := "（攻击范围 %d）" % CardDefs.weapon_range_of(nm) if slot == "weapon" else ""
		eq_lines.append("[color=#ffd27a][b]%s【%s】[/b][/color]%s %s" % [slot_nm[slot], nm, extra, IntroPop.highlight(CardDefs.text_of(nm))])
	rt["equips"] = "[color=#c9b8e8][b]装备区[/b][/color]\n" + ("\n".join(PackedStringArray(eq_lines)) if not eq_lines.is_empty() else "（无）")
	var j_lines: Array = []
	for c in p["judge"]:
		var jn := String(c["name"])
		j_lines.append("[color=#ffd27a][b]【%s】[/b][/color] %s" % [jn, IntroPop.highlight(String(JUDGE_SHORT.get(jn, CardDefs.text_of(jn))))])
	rt["judges"] = "[color=#c9b8e8][b]判定区[/b][/color]\n" + ("\n".join(PackedStringArray(j_lines)) if not j_lines.is_empty() else "（无）")
	var sp: Dictionary = IntroPop.char_spec(p["char"], rt)
	return sp


# 提问按钮：值是一张（标签上已亮明的）牌 → 牌说明；值是一名角色 → 角色说明。暗牌（标签不含牌名）不挂说明，防止泄露
func _attach_option_intro(b: Button, lab: String, v: Variant) -> void:
	if not (v is Dictionary):
		if (v is int) and lab != "取消" and int(v) >= 0 and int(v) < players.size() and lab.find(String(players[int(v)]["char"]["name"])) >= 0:
			b.set_meta("intro", Callable(self, "_intro_seat").bind(int(v)))
		return
	var d: Dictionary = v
	if d.has("name") and d.has("suit") and lab.find(String(d["name"])) >= 0:
		b.set_meta("intro", Callable(self, "_intro_card").bind(d))
	elif d.has("card") and (d["card"] is Dictionary) and lab.find(String((d["card"] as Dictionary).get("name", "?"))) >= 0:
		b.set_meta("intro", Callable(self, "_intro_card").bind(d["card"]))
	elif d.has("seat") and d.has("char"):
		b.set_meta("intro", Callable(self, "_intro_seat").bind(int(d["seat"])))


# 首次进入对局的一次性提示（记在 user://settings.cfg，看过就不再出现）
static func first_hint_seen() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return false
	return bool(cf.get_value("help", "longpress_hint", false))


static func mark_first_hint_seen() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("help", "longpress_hint", true)
	cf.save(SETTINGS_PATH)


func _maybe_first_hint(force: bool = false) -> void:
	if auto_all or (not force and first_hint_seen()):
		return
	mark_first_hint_seen()
	if first_hint_label == null or not is_instance_valid(first_hint_label):
		first_hint_label = lbl("💡 长按牌或角色可查看说明（电脑上右键或鼠标悬停也可以）", 30, Color(1.0, 0.96, 0.86), true, HORIZONTAL_ALIGNMENT_CENTER)
		first_hint_label.name = "FirstHint"
		first_hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		first_hint_label.mouse_filter = MOUSE_FILTER_IGNORE
		first_hint_label.add_theme_stylebox_override("normal", _tight(style(Color(0.20, 0.12, 0.28, 0.90), 26, Color(1.0, 0.80, 0.42, 0.95), 3, true), 30, 12))
		add_child(first_hint_label)
	first_hint_label.size = Vector2(0, 0)
	first_hint_label.reset_size()
	first_hint_label.position = Vector2((vw - first_hint_label.size.x) * 0.5, 150)
	first_hint_label.visible = true
	first_hint_label.modulate.a = 1.0
	var tw := first_hint_label.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(first_hint_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void: first_hint_label.visible = false)


# ================= V0.27 先选中，再确认 =================
# 对照无名杀 game.check() + ui.click.ok()：点牌/点目标/点技能只改变「选中状态」，由「确定」统一提交；
# 只有拖拽到合法目标头像上松手保留直接打出（无名杀 ui.click 拖拽松手同样直接 ok）。
# 「自动确认」（无名杀 auto_confirm）默认关闭：开启后选够且无需再选时自动提交。
const FEAT_END := 16.0 + 7.0 * 118.0
var auto_confirm := false
var extra_target := -1          # 多目标牌（羁绊锁链）的第二个目标
var skill_mode := ""            # 技能选择状态中的技能 sid
var skill_card: Dictionary = {} # 技能选择状态中选中的手牌
var skill_pre: Dictionary = {}  # 确认发动后预先作答引擎询问 {card, target}
var pre_answers: Array = []     # 出牌确认时已选好的附加作答（羁绊锁链第二目标）
var resp_pref_card: Dictionary = {}  # 响应时选中的那张牌（引擎优先打出它）
var ask_mode := ""
var ask_prompt := ""
var ask_options: Array = []
var ask_sel_has := false
var ask_sel_val: Variant = null
var ask_opt_btns: Array = []    # [{btn, value}]
var ask_confirm_btn: Button = null
var settings_btn: Button = null
var settings_panel: PanelContainer = null
var auto_confirm_check: CheckButton = null
var auto_submit_count := 0      # 自动确认触发次数（测试用）


static func auto_confirm_saved() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return false
	return bool(cf.get_value("play", "auto_confirm", false))


static func save_auto_confirm(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("play", "auto_confirm", on)
	cf.save(SETTINGS_PATH)


func set_auto_confirm(on: bool, persist: bool = true) -> void:
	auto_confirm = on
	if persist:
		save_auto_confirm(on)
	if auto_confirm_check != null and is_instance_valid(auto_confirm_check) and auto_confirm_check.button_pressed != on:
		auto_confirm_check.set_pressed_no_signal(on)


func toggle_settings_panel() -> void:
	if settings_panel == null or not is_instance_valid(settings_panel):
		_build_settings_panel()
	settings_panel.visible = not settings_panel.visible
	if settings_panel.visible:
		auto_confirm_check.set_pressed_no_signal(auto_confirm)
		move_child(settings_panel, get_child_count() - 1)


func _build_settings_panel() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.position = Vector2(16.0 + 4.0 * 118.0, 84)
	settings_panel.custom_minimum_size = Vector2(560, 0)
	settings_panel.mouse_filter = MOUSE_FILTER_STOP
	settings_panel.add_theme_stylebox_override("panel", style(Color(1, 1, 1, 0.97), 22, C_GOLD, 3, true))
	settings_panel.visible = false
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 20)
	settings_panel.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	mc.add_child(vb)
	var tl := lbl("设置", 30, C_PINK_DEEP, true)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	vb.add_child(tl)
	auto_confirm_check = CheckButton.new()
	auto_confirm_check.focus_mode = Control.FOCUS_NONE
	auto_confirm_check.text = "自动确认"
	auto_confirm_check.add_theme_font_override("font", font_bold)
	auto_confirm_check.add_theme_font_size_override("font_size", 28)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		auto_confirm_check.add_theme_color_override(k, C_INK)
	auto_confirm_check.set_pressed_no_signal(auto_confirm)
	auto_confirm_check.toggled.connect(func(on: bool) -> void:
		set_auto_confirm(on)
		show_hint("自动确认：%s" % ("已开启——选够且无需再选时自动出牌/作答" if on else "已关闭——选中后需点「确定」才会出牌")))
	vb.add_child(auto_confirm_check)
	var desc := lbl("关闭（默认）：点牌、点目标、点技能只会选中，点「确定」才会出牌/发动。\n开启：选择已经选够、没有其他可选时自动提交（同无名杀「自动确认」）。", 21, C_INK_SOFT)
	desc.custom_minimum_size = Vector2(520, 0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc)
	# V0.32 声音设置：总音量、音效/语音/背景音乐开关与音量
	var at := lbl("声音", 26, C_PINK_DEEP, true)
	vb.add_child(at)
	build_audio_rows(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	var hb1 := plain_btn("新手说明", Color(1, 0.94, 0.80), C_INK, 24)
	hb1.custom_minimum_size = Vector2(160, 52)
	hb1.pressed.connect(func() -> void:
		settings_panel.visible = false
		open_info_overlay("新手说明", HelpText.bbcode(), true))
	hb.add_child(hb1)
	var hb2 := plain_btn("关闭", Color(1, 1, 1, 0.96), C_PINK_DEEP, 24)
	hb2.custom_minimum_size = Vector2(120, 52)
	hb2.pressed.connect(func() -> void: settings_panel.visible = false)
	hb.add_child(hb2)
	add_child(settings_panel)


var audio_sliders := {}  # key -> HSlider（测试用）
var audio_checks := {}   # key -> CheckButton（测试用）


func build_audio_rows(vb: VBoxContainer) -> void:
	AudioCfg.ensure()
	for row in [["总音量", "", "master"], ["音效", "sfx_on", "sfx_vol"], ["语音", "voice_on", "voice_vol"], ["背景音乐", "music_on", "music_vol"]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		vb.add_child(hb)
		var on_key := String(row[1])
		var vol_key := String(row[2])
		if on_key == "":
			var l := lbl(String(row[0]), 24, C_INK, true)
			l.custom_minimum_size = Vector2(190, 0)
			hb.add_child(l)
		else:
			var cb := CheckButton.new()
			cb.focus_mode = Control.FOCUS_NONE
			cb.text = String(row[0])
			cb.custom_minimum_size = Vector2(190, 0)
			cb.add_theme_font_override("font", font_bold)
			cb.add_theme_font_size_override("font_size", 24)
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
				cb.add_theme_color_override(k, C_INK)
			cb.set_pressed_no_signal(bool(AudioCfg.get_v(on_key)))
			cb.toggled.connect(func(on: bool) -> void: AudioCfg.set_v(on_key, on))
			hb.add_child(cb)
			audio_checks[on_key] = cb
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(320, 44)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.focus_mode = Control.FOCUS_NONE
		sl.set_value_no_signal(float(AudioCfg.get_v(vol_key)))
		sl.value_changed.connect(func(v: float) -> void: AudioCfg.set_v(vol_key, v))
		sl.drag_ended.connect(func(_c: bool) -> void: play_sfx("click"))
		hb.add_child(sl)
		audio_sliders[vol_key] = sl
	var note := lbl("背景音乐：Kevin MacLeod（CC BY 4.0，署名见新手说明）。语音：本版未打包配音。", 19, C_INK_SOFT)
	note.custom_minimum_size = Vector2(520, 0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)


func card_max_targets(card: Dictionary) -> int:
	return 2 if String(card.get("name", "")) == "羁绊锁链" else 1


func _tgt_name(seat: int) -> String:
	if seat < 0 or seat >= players.size():
		return ""
	return "你自己" if seat == 0 else pname(players[seat])


func _can_confirm() -> bool:
	if not interactive or asking or game_over or players.is_empty() or turn_seat != 0 or discard_mode:
		return false
	if skill_mode != "":
		var spec := _skill_ui_spec(skill_mode)
		if String(spec["card"]) != "none" and (skill_card.is_empty() or not _hand_has(skill_card) or not _skill_card_ok(skill_card)):
			return false
		if spec["targets"] != null and (sel_target < 0 or not target_candidates.has(sel_target)):
			return false
		return true
	if spear_targeting or muniu_targeting:
		return sel_target >= 0 and target_candidates.has(sel_target) and (muniu_targeting or spear_cards.size() == 2)
	if selected_card.is_empty() or not _hand_has(selected_card):
		return false
	if unusable_reason(players[0], selected_card) != "":
		return false
	if card_needs_target(selected_card) and (sel_target < 0 or not target_candidates.has(sel_target)):
		return false
	return true


# 选择是否「已经选够、没有其他可选」：自动确认据此提交
func _selection_complete() -> bool:
	if not _can_confirm():
		return false
	if skill_mode == "" and not spear_targeting and not muniu_targeting and card_max_targets(selected_card) >= 2:
		return extra_target >= 0 or target_candidates.size() < 2
	return true


func _maybe_auto_confirm() -> void:
	if not auto_confirm or not _selection_complete():
		return
	auto_submit_count += 1
	# 延后一帧提交：当前仍在按钮/手牌的 pressed 信号里，不能在信号中释放发信号的节点
	_on_confirm_pressed.call_deferred()


func _show_sel_hint() -> void:
	var t := _sel_hint_text()
	if t != "":
		show_hint(t)
	_update_action_bar()


func _sel_hint_text() -> String:
	if skill_mode != "":
		var spec := _skill_ui_spec(skill_mode)
		var nm := String((eng.skill_lib.get(skill_mode, {}) as Dictionary).get("name", skill_mode)) if eng != null else skill_mode
		var need_card := String(spec["card"]) != "none"
		var card_desc: String = {"any": "1 张手牌", "red": "1 张红色手牌", "black": "1 张黑色手牌"}.get(String(spec["card"]), "")
		if need_card and skill_card.is_empty():
			return "「%s」：请选择%s（%s）——再点技能按钮或「取消」退出" % [nm, card_desc, String(spec.get("card_role", "作为代价"))]
		if spec["targets"] != null and sel_target < 0:
			return "「%s」：请选择 1 名角色（绿色高亮）" % nm
		var parts: Array = []
		if need_card:
			parts.append("用 %s" % card_text(skill_card))
		if spec["targets"] != null:
			parts.append("对 %s" % _tgt_name(sel_target))
		return "%s发动「%s」——点「确定」发动" % [" ".join(parts) + " " if not parts.is_empty() else "", nm]
	if spear_targeting:
		if sel_target < 0:
			return "「合璧长枪」：请选择 1 名目标，再点选两张要拼的手牌"
		if spear_cards.size() < 2:
			return "对 %s 使用「合璧长枪」：请再点选 %d 张手牌（已选 %d/2）" % [_tgt_name(sel_target), 2 - spear_cards.size(), spear_cards.size()]
		return "对 %s 使用 %s 与 %s 拼成突击——点「确定」出牌" % [_tgt_name(sel_target), card_text(spear_cards[0]), card_text(spear_cards[1])]
	if muniu_targeting:
		if sel_target < 0:
			return "「木牛流马」：请选择 1 名要转交的角色"
		return "把木牛流马转交给 %s——点「确定」" % _tgt_name(sel_target)
	if selected_card.is_empty():
		return ""
	var cn := String(selected_card["name"])
	if card_needs_target(selected_card):
		var mx := card_max_targets(selected_card)
		if sel_target < 0:
			return "「%s」：请选择 %s 名目标（绿色高亮，或拖到目标头像上）%s" % [cn, "1~2" if mx >= 2 else "1", "；也可点「重铸」弃置并摸 1 张" if eng != null and eng.can_recast(selected_card) else ""]
		var who := _tgt_name(sel_target)
		if extra_target >= 0:
			who += "、" + _tgt_name(extra_target)
		var more := "（可再选 1 名）" if mx >= 2 and extra_target < 0 and target_candidates.size() >= 2 else ""
		return "对 %s 使用「%s」%s——点「确定」出牌" % [who, cn, more]
	if card_kind(selected_card) in ["武器", "防具", "饰品", "宝物"]:
		return "装备「%s」——点「确定」装备（再点一下这张牌取消）" % cn
	return "使用「%s」——点「确定」使用（再点一下这张牌取消）" % cn


func _commit_spear() -> void:
	if spear_cards.size() != 2:
		return
	var seat := sel_target
	var chosen: Array = spear_cards.duplicate()
	spear_targeting = false
	spear_cards = []
	targeting = false
	target_candidates = []
	sel_target = -1
	hide_prompt()
	interactive = false
	_update_action_bar()
	await eng.spear_attack(players[0], players[seat], chosen)
	if not game_over and is_inside_tree():
		interactive = true
		maybe_restore_hint()
		refresh()


func _commit_muniu_give() -> void:
	var seat := sel_target
	muniu_targeting = false
	targeting = false
	target_candidates = []
	sel_target = -1
	hide_prompt()
	eng.muniu_give(players[0], players[seat])
	maybe_restore_hint()
	refresh()


# 技能选择所需：card = none/any/red/black；targets = null（无需选人）或候选座位数组
func _skill_ui_spec(sid: String) -> Dictionary:
	var me: Dictionary = players[0]
	var others_alive: Array = []
	var all_alive: Array = []
	for t in players:
		if bool(t["alive"]):
			all_alive.append(int(t["seat"]))
			if t != me:
				others_alive.append(int(t["seat"]))
	match sid:
		"yingyuan":
			return {"card": "any", "card_role": "作为代价弃置", "targets": all_alive}
		"fengji":
			return {"card": "none", "targets": others_alive.filter(func(s: int) -> bool: return not (players[s]["hand"] as Array).is_empty())}
		"gesheng":
			return {"card": "none", "targets": others_alive}
		"yuanqi":
			return {"card": "black", "card_role": "当作「补给」", "targets": null}
		"chahui":
			return {"card": "any", "card_role": "作为代价弃置", "targets": others_alive.filter(func(s: int) -> bool: return int(players[s]["hp"]) < int(players[s]["max_hp"]))}
		"qinyin":
			var qs: Array = []
			if eng != null and eng.get("_skill_owner") != null:
				for t in eng._skill_owner._qinyin_cands(eng, me):
					qs.append(int(t["seat"]))
			return {"card": "red", "card_role": "当作「突击」", "targets": qs}
		"shifeng":
			return {"card": "any", "card_role": "交给对方", "targets": others_alive}
		"caijue":
			return {"card": "any", "card_role": "作为代价弃置", "targets": others_alive}
		"canyue":
			return {"card": "none", "targets": null}
		"zhouye":
			if int(me.get("switch_zhouye", 0)) == 0:
				return {"card": "any", "card_role": "昼夜卷·阳：弃置并造成1点火焰伤害", "targets": others_alive}
			return {"card": "none", "targets": all_alive}
		"shenshe":
			var ss: Array = []
			if eng != null and eng.get("_skill_owner") != null:
				for t in eng._skill_owner._shenshe_cands(eng, me):
					ss.append(int(t["seat"]))
			return {"card": "any", "card_role": "当作无视距离且强命的「突击」", "targets": ss}
		"cuihua":
			return {"card": "none", "targets": all_alive}
		"wangshou":
			return {"card": "none", "targets": others_alive.filter(func(s: int) -> bool: return not (players[s]["hand"] as Array).is_empty())}
		"jingsuan":
			return {"card": "any", "card_role": "精算置换（弃1摸2，黑色牌且受伤则回1血）", "targets": null}
		"yuanhu":
			return {"card": "any", "card_role": "作为代价弃置（令目标获得1点护甲）", "targets": all_alive}
	return {"card": "none", "targets": null}


func _skill_card_ok(c: Dictionary) -> bool:
	if skill_mode == "":
		return false
	match String(_skill_ui_spec(skill_mode)["card"]):
		"any":
			return true
		"red":
			return is_red(c)
		"black":
			return not is_red(c)
	return false


func _enter_skill_mode(sid: String) -> void:
	var spec := _skill_ui_spec(sid)
	skill_mode = sid
	skill_card = {}
	sel_target = -1
	extra_target = -1
	targeting = false
	target_candidates = []
	if spec["targets"] != null:
		target_candidates = (spec["targets"] as Array).duplicate()
		if target_candidates.is_empty():
			skill_mode = ""
			show_hint("现在没有可选的角色，无法发动")
			refresh()
			return
		targeting = true
		if target_candidates.size() == 1:
			sel_target = int(target_candidates[0])
	if String(spec["card"]) != "none":
		var cands: Array = (players[0]["hand"] as Array).filter(func(c: Dictionary) -> bool: return _skill_card_ok(c))
		if cands.size() == 1:
			skill_card = cands[0]
	play_sfx("draw")
	_show_sel_hint()
	refresh()
	_maybe_auto_confirm()


func _skill_card_tap(card: Dictionary) -> void:
	if String(_skill_ui_spec(skill_mode)["card"]) == "none":
		_nudge_card(card)
		return
	if not _skill_card_ok(card):
		show_hint("这张牌不能用于这个技能（%s）" % _sel_hint_text())
		_nudge_card(card)
		return
	if not skill_card.is_empty() and is_same(skill_card, card):
		skill_card = {}
	else:
		skill_card = card
	play_sfx("draw")
	_show_sel_hint()
	_queue_refresh()
	_maybe_auto_confirm()


func _commit_skill() -> void:
	var sid := skill_mode
	var spec := _skill_ui_spec(sid)
	skill_pre = {}
	if String(spec["card"]) != "none":
		skill_pre["card"] = skill_card
	if spec["targets"] != null:
		skill_pre["target"] = sel_target
	skill_mode = ""
	skill_card = {}
	targeting = false
	target_candidates = []
	sel_target = -1
	hide_prompt()
	interactive = false
	end_play_btn.disabled = true
	refresh()
	await eng.use_active_skill(players[0], sid)
	skill_pre = {}
	if not game_over and is_inside_tree() and turn_seat == 0 and players[0]["alive"]:
		interactive = true
		end_play_btn.disabled = false
		maybe_restore_hint()
	refresh()


# ---------- 询问：选中 + 确定 ----------

func _is_cancel_val(v: Variant) -> bool:
	if v == null:
		return true
	if v is bool:
		return not bool(v)
	if v is int:
		return int(v) == -1
	if v is Dictionary:
		return (v as Dictionary).is_empty()
	return false


func _build_select_ask(options: Array) -> void:
	ask_confirm_btn = _make_action_btn("确定", C_GOLD, Color(0.25, 0.16, 0.05))
	ask_confirm_btn.disabled = true
	ask_confirm_btn.custom_minimum_size = Vector2(170, 64)
	(ask_confirm_btn.get_child(0) as Control).size = Vector2(150, 24)
	ask_confirm_btn.pressed.connect(_ask_confirm)
	prompt_btns.add_child(ask_confirm_btn)
	var selectable: Array = []
	for opt in options:
		var lab := String(opt["label"])
		var v: Variant = opt["value"]
		if ask_mode == "respond" and v is bool and bool(v):
			continue  # 「打出X」由「确定」代替：先点亮的牌选中，再点确定
		var b := _make_action_btn(lab, Color(1, 1, 1, 0.96), C_PINK_DEEP)
		var tw_w := clampf(64.0 + lab.length() * 26.0, 150.0, 420.0)
		b.custom_minimum_size = Vector2(tw_w, 64)
		(b.get_child(0) as Control).size = Vector2(tw_w - 20, 24)
		if lab.length() > 10:
			b.add_theme_font_size_override("font_size", 22)
		if _is_cancel_val(v) or ask_mode == "respond":
			b.pressed.connect(func() -> void: _on_decided(v))
		else:
			b.pressed.connect(func() -> void: _ask_select(v))
			ask_opt_btns.append({"btn": b, "value": v})
			selectable.append(v)
		_attach_option_intro(b, lab, v)
		prompt_btns.add_child(b)
	# 不预选：点一下就是「选中」，避免点已预选的牌反而取消；选中后才能点「确定」
	prompt_label.text = ask_prompt + ("（点亮的牌选中后点「确定」）" if ask_mode == "respond" else "（选中后点「确定」）")


func _ask_same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		return is_same(a, b)
	return a == b


func _ask_select(v: Variant, preselect: bool = false) -> void:
	if not asking:
		return
	if ask_sel_has and _ask_same(ask_sel_val, v) and not preselect:
		_ask_clear_sel()
		return
	ask_sel_has = true
	ask_sel_val = v
	if not preselect:
		play_sfx("draw")
	_ask_refresh_btns()
	if not preselect or auto_confirm:
		_ask_maybe_auto()


func _ask_maybe_auto() -> void:
	if auto_confirm and ask_sel_has:
		auto_submit_count += 1
		_ask_confirm.call_deferred()


func _ask_clear_sel() -> void:
	ask_sel_has = false
	ask_sel_val = null
	_ask_refresh_btns()


func _ask_reset_sel() -> void:
	ask_sel_has = false
	ask_sel_val = null
	ask_mode = ""
	ask_opt_btns = []
	ask_confirm_btn = null


func _ask_sel_label() -> String:
	if not ask_sel_has:
		return ""
	if ask_sel_val is Dictionary:
		var d: Dictionary = ask_sel_val
		if d.has("name") and d.has("suit"):
			return card_text(d)
		if d.has("zone"):
			return "手牌（随机一张）" if (d["card"] as Dictionary).is_empty() else card_text(d["card"])
		if d.has("seat"):
			return pname(d)
	for o in ask_options:
		if _ask_same((o as Dictionary).get("value"), ask_sel_val):
			return String(o["label"])
	return str(ask_sel_val)


func _ask_refresh_btns() -> void:
	if ask_confirm_btn != null and is_instance_valid(ask_confirm_btn):
		ask_confirm_btn.disabled = not ask_sel_has
	for e in ask_opt_btns:
		var b: Button = e["btn"]
		if not is_instance_valid(b):
			continue
		var on := ask_sel_has and _ask_same(ask_sel_val, e["value"])
		var bg := Color(1.0, 0.86, 0.45) if on else Color(1, 1, 1, 0.96)
		b.add_theme_stylebox_override("normal", style(bg, 32, Color(1.0, 0.55, 0.15) if on else Color(1, 1, 1, 0.85), 4 if on else 2, true))
		b.add_theme_stylebox_override("hover", style(bg.lightened(0.06), 32, Color(1.0, 0.55, 0.15) if on else Color(1, 1, 1, 0.95), 4 if on else 2, true))
	if ask_sel_has and ask_mode == "respond":
		prompt_label.text = "已选 %s——点「确定」打出，点「不出」放弃" % _ask_sel_label()
	elif ask_sel_has:
		prompt_label.text = "%s——已选：%s，点「确定」" % [ask_prompt, _ask_sel_label()]
	else:
		prompt_label.text = ask_prompt + ("（点亮的牌选中后点「确定」）" if ask_mode == "respond" else "（选中后点「确定」）")
	_queue_refresh()


func _ask_confirm() -> void:
	if not asking or not ask_sel_has:
		return
	if ask_mode == "respond":
		resp_pref_card = ask_sel_val if ask_sel_val is Dictionary else {}
		_on_decided(true)
		return
	_on_decided(ask_sel_val)


func _eng_resp_pref(p: Dictionary) -> Dictionary:
	var c := resp_pref_card
	resp_pref_card = {}
	return c


# 测试/截图驱动：直接作答当前询问（第 idx 个选项；-1 = 默认项），绕开选中流程
func test_answer(idx: int = -1) -> bool:
	if not asking:
		return false
	if discard_mode:
		_on_decided("__auto")
		return true
	if idx < 0 or idx >= ask_options.size():
		_on_decided(ask_default)
	else:
		_on_decided(ask_options[idx]["value"])
	return true


# ================= V0.28 重铸 =================
var recast_btn: Button = null


func _on_recast_pressed() -> void:
	if not interactive or asking or turn_seat != 0 or game_over or selected_card.is_empty():
		return
	var c: Dictionary = selected_card
	if not _hand_has(c) or not eng.can_recast(c):
		return
	cancel_targeting()
	interactive = false
	_update_action_bar()
	eng.recast(players[0], c)
	interactive = true
	maybe_restore_hint()
	refresh()


# ================= V0.33 手杀风连破/高伤横幅、开局手气卡、换将与自由点将 =================
var luck_btn: Button = null
var luck_left := 2
var lord_pre_char: Dictionary = {}
var draft_my_identity := "主公"
var free_pick_overlay: Control = null


func fx_spree_banner(title_text: String, sub_text: String, is_kill: bool) -> void:
	if fx_root == null or fast or auto_all:
		return
	var box := PanelContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	var bg_col := Color(0.52, 0.08, 0.16, 0.94) if is_kill else Color(0.45, 0.18, 0.06, 0.94)
	var bd_col := Color(1.0, 0.82, 0.32) if is_kill else Color(1.0, 0.64, 0.22)
	box.add_theme_stylebox_override("panel", style(bg_col, 24, bd_col, 4, true))
	var vb := VBoxContainer.new()
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	var tl := lbl(title_text, 44, Color(1.0, 0.94, 0.72), true, HORIZONTAL_ALIGNMENT_CENTER)
	tl.add_theme_constant_override("outline_size", 8)
	tl.add_theme_color_override("font_outline_color", Color(0.22, 0.04, 0.08, 0.95))
	vb.add_child(tl)
	var sl := lbl(sub_text, 22, Color(1.0, 0.92, 0.88), false, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(sl)
	box.add_child(vb)
	box.size = Vector2(620, 108)
	box.position = Vector2(vw * 0.5 - 310, 128 if is_kill else 242)
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2(0.45, 0.45)
	box.modulate.a = 0.0
	fx_root.add_child(box)
	var tw := create_tween().bind_node(box)
	tw.set_parallel(true)
	tw.tween_property(box, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, 0.16)
	tw.chain().tween_interval(1.05)
	tw.chain().tween_property(box, "modulate:a", 0.0, 0.30)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(box):
			box.queue_free())


func _on_luck_pressed() -> void:
	if not interactive or asking or turn_seat != 0 or game_over or luck_left <= 0 or eng == null or players.is_empty():
		return
	var me: Dictionary = players[0]
	var hand: Array = me["hand"]
	if hand.is_empty():
		return
	cancel_targeting()
	luck_left -= 1
	var cnt := hand.size()
	for c in hand.duplicate():
		hand.erase(c)
		eng.deck.insert(0, c)
	eng.deck.shuffle()
	eng.draw_cards(me, cnt)
	log_msg("「手气卡」：你更换了 %d 张起手牌（本局剩余 %d 次）。" % [cnt, luck_left])
	show_hint("已使用手气卡重新摸取 %d 张手牌（剩余 %d 次）" % [cnt, luck_left])
	refresh()


func _on_reshuffle_draft() -> void:
	if draft_layer == null or not draft_layer.visible:
		return
	var pool: Array = []
	for c in Characters.LIST:
		if lord_pre_char.is_empty() or String(c["id"]) != String(lord_pre_char.get("id", "")):
			pool.append(c)
	pool.shuffle()
	play_sfx("card")
	_populate_draft_cards(pool.slice(0, mini(3, pool.size())), draft_my_identity)


func _open_free_pick() -> void:
	if draft_layer == null or not draft_layer.visible:
		return
	if free_pick_overlay != null and is_instance_valid(free_pick_overlay):
		free_pick_overlay.queue_free()
	var ov := Control.new()
	ov.name = "FreePickOverlay"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ov)
	free_pick_overlay = ov
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.12, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_extend_cover(dim, dim.color)
	ov.add_child(dim)
	var pc := PanelContainer.new()
	pc.position = Vector2(vw * 0.5 - 760, 76)
	pc.size = Vector2(1520, 920)
	pc.add_theme_stylebox_override("panel", style(Color(1.0, 0.97, 0.95, 0.98), 28, C_GOLD, 4, true))
	ov.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)
	var top := HBoxContainer.new()
	var ttl := lbl("★ 自由点将（点击任意角色立即出战）", 36, C_PINK_DEEP, true)
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(ttl)
	var close_b := plain_btn("关闭", Color(1, 1, 1, 0.95), C_PINK_DEEP, 26)
	close_b.custom_minimum_size = Vector2(140, 54)
	close_b.pressed.connect(func() -> void:
		if is_instance_valid(ov):
			ov.queue_free())
	top.add_child(close_b)
	vb.add_child(top)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	sc.add_child(grid)
	var hp_bonus := 1 if draft_my_identity == "主公" else 0
	for c in Characters.LIST:
		if not lord_pre_char.is_empty() and String(c["id"]) == String(lord_pre_char.get("id", "")):
			continue
		var cb := Button.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.custom_minimum_size = Vector2(276, 360)
		cb.add_theme_stylebox_override("normal", style(Color(1, 1, 1, 0.95), 20, C_GOLD, 2, true))
		cb.add_theme_stylebox_override("hover", style(Color(1, 0.96, 0.98, 1.0), 20, C_PINK_DEEP, 3, true))
		var cvb := VBoxContainer.new()
		cvb.mouse_filter = MOUSE_FILTER_IGNORE
		cvb.set_anchors_preset(Control.PRESET_FULL_RECT)
		cvb.offset_left = 10
		cvb.offset_right = -10
		cvb.offset_top = 8
		var cdisp: Dictionary = (c as Dictionary).duplicate()
		cdisp["hp"] = int(c["hp"]) + hp_bonus
		var ccard := Art.cg_card(cdisp, Vector2(252, 260), {"zoom": 0.62, "face_y": 0.32, "fs": 24})
		cvb.add_child(ccard)
		var sks: Array = []
		for s in c["skills"]:
			sks.append("【%s】" % String(s["name"]))
		var slb := lbl(" ".join(PackedStringArray(sks)), 18, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER)
		slb.mouse_filter = MOUSE_FILTER_IGNORE
		cvb.add_child(slb)
		cb.add_child(cvb)
		var cref: Dictionary = c
		cb.set_meta("intro", IntroPop.char_spec(c))
		cb.pressed.connect(func() -> void:
			if is_instance_valid(ov):
				ov.queue_free()
			_on_decided(cref))
		grid.add_child(cb)
