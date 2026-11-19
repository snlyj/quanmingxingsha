class_name BattleScreen
extends Control
const CardDefs = preload("res://data/cards.gd")
const Puzzles = preload("res://data/puzzles.gd")
const EngineScript = preload("res://scripts/engine.gd")
const HelpText = preload("res://data/help.gd")
const Art = preload("res://scripts/art.gd")
const Palette = preload("res://scripts/ui_palette.gd")
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
const C_INK := Palette.INK
const C_INK_SOFT := Palette.MUTED
const C_WHITE := Color(1, 1, 1)
const C_RED := Color(0.85, 0.25, 0.35)
const C_BLACK := Color(0.30, 0.28, 0.38)
const C_GOLD := Color(0.91, 0.64, 0.24)
const C_PLATE := Color(1.0, 0.36, 0.54)
const C_INDIGO := Color(0.35, 0.32, 0.55)
const C_TABLE_ACTION := Palette.ROSE_PRIMARY
const C_TARGET_AVAILABLE := Color("#73ab9d")
const C_ACTIVE_SEAT := Color("#72a7d8")
const C_DESIGNATED_SEAT := Color("#efb56b")
const DESIGNATED_TARGET_MS := 2200
const TABLE_ACTION_H := 102.0
const TABLE_ACTION_GAP := 12.0

var _night_ui := false
var _table_surface := Color(Palette.MILK, 0.96)
var _table_inset := Palette.LILAC_SOFT
var _table_edge := Palette.LILAC_EDGE
var _table_text := Palette.INK
var _table_note := Palette.MUTED
var _table_button := Palette.MILK

var font_reg: Font
var font_bold: Font
var go_home: Callable

var players: Array = []
var eng = null # 新引擎实例（engine.gd）
var me_panel_ref: Control = null
var fx_root: Control = null
var target_traces: Node2D = null
var target_trace_fades: Node2D = null
var turn_banner_panel: PanelContainer = null
var turn_banner: Label = null
var turn_banner_tween: Tween = null
var play_callout_panel: PanelContainer = null
var play_callout_label: Label = null
var play_result_label: Label = null
var play_callout_tween: Tween = null
var skill_notice_panel: PanelContainer = null
var skill_notice_actor: Label = null
var skill_notice_title: Label = null
var skill_notice_tween: Tween = null
var last_turn_seat := -1
var sfx_players: Array = []
var sfx_streams: Dictionary = {}
var _sfx_last_ms: Dictionary = {}
var cv_played_count := 0
var _cv_seat_ms := {}
var _result_music_scene := ""
var sfx_count := 0  # 播放请求计数（测试用）
const AudioCfg = preload("res://scripts/audio.gd")
const Meta = preload("res://scripts/meta.gd")
var puzzle_id: String = ""  # V0.37 残局关卡 id
var puzzle_panel: PanelContainer = null
var puzzle_label: Label = null
var puzzle_hint_shown: bool = false
var puzzle_hint_btn: Button = null
var open_puzzles_cb: Callable = Callable()
var tutorial := false  # V0.30 教学关（脚本化单挑）
var ask_bar_fill: ColorRect = null
var ask_bar_bg_ref: Panel = null
var ask_deadline_ms := 0
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
var sort_btn: Button = null
var hand_sort_by_suit: bool = false
var concede_btn: Button
var info_overlay: Panel
var info_title: Label
var info_text: RichTextLabel
var me_hp_label: Label
var me_chips: HBoxContainer
var seat_panels: Array = []
var prompt_label: Label
var prompt_context_label: Label
var prompt_header: HBoxContainer
var prompt_btns: HBoxContainer
var _prompt_surface_style: StyleBoxFlat
var _prompt_surface_tween: Tween
var prompt_action_width := 892.0
var hand_row: Control
var player_info: Label
var player_portrait: TextureRect
var skill_btns: VBoxContainer
var end_play_btn: Button
var log_lines: Array = []
var _seat_gem_styles: Dictionary = {}
var _seat_frame_styles: Dictionary = {}
var _own_frame_styles: Dictionary = {}
var _phase_active_style: StyleBoxFlat
var _phase_idle_style: StyleBoxFlat
var _last_phase_text := ""

const SUITS := ["红桃", "方块", "梅花", "黑桃"]
const RED_SUITS := ["红桃", "方块"]
const PHASE_NAMES := ["准备", "判定", "摸牌", "出牌", "弃牌", "结束"]


func _ready() -> void:
	font_reg = load("res://assets/fonts/NotoSansSC-Regular.otf")
	font_bold = load("res://assets/fonts/NotoSansSC-Bold.otf")
	var scene := get_tree().current_scene
	_night_ui = scene != null and "theme_night" in scene and bool(scene.get("theme_night"))
	if _night_ui:
		_table_surface = Color(Palette.NIGHT_PANEL, 0.96)
		_table_inset = Palette.NIGHT_PANEL.lightened(0.08)
		_table_edge = Palette.NIGHT_BORDER
		_table_text = Palette.NIGHT_INK
		_table_note = Palette.NIGHT_MUTED
		_table_button = _table_inset
	rng.randomize()
	auto_confirm = auto_confirm_saved()  # V0.27：「自动确认」默认关闭，设置持久化在 user://settings.cfg [play]
	double_tap_play = double_tap_saved()
	reduced_motion = reduced_motion_saved()


# V0.24 修复：对局中途「退出」回主页时，引擎协程还挂在「等待作答/结束出牌」上，整个引擎实例（牌堆、日志、技能表）
# 永远不会被释放（每退出一局泄漏一份）。离开场景树时令其判负收尾并放行所有等待，协程随之结束、引擎得以回收
func _exit_tree() -> void:
	_clear_press_feedback()
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
		s.shadow_color = Palette.SHADOW
		s.shadow_size = 5
		s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


func _wire_btn_bounce(b: Button) -> void:
	if bool(b.get_meta("_bounce_wired", false)):
		return
	b.set_meta("_bounce_wired", true)
	b.ready.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.button_down.connect(func() -> void:
		if b.has_node("PressFeedback") or not _motion_enabled() or b.disabled or float(b.get_meta("drag_px", 0.0)) > 10.0:
			return
		b.pivot_offset = b.size * 0.5
		_ease_button_scale(b, Vector2(0.976, 0.976), 0.075))
	b.button_up.connect(func() -> void:
		if b.has_node("PressFeedback"):
			return
		if not _motion_enabled():
			var down: Variant = b.get_meta("_press_scale") if b.has_meta("_press_scale") else null
			if down is Tween and down.is_valid():
				down.kill()
			b.scale = Vector2.ONE
			return
		_ease_button_scale(b, Vector2.ONE, 0.15))


func _ease_button_scale(button: Button, target: Vector2, duration: float) -> void:
	var old: Variant = button.get_meta("_press_scale") if button.has_meta("_press_scale") else null
	if old is Tween and old.is_valid():
		old.kill()
	var movement := button.create_tween()
	movement.tween_property(button, "scale", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	button.set_meta("_press_scale", movement)


func _make_press_feedback(parent: Control, corner: int) -> Panel:
	var cue := Panel.new()
	cue.name = "PressFeedback"
	cue.mouse_filter = MOUSE_FILTER_IGNORE
	if not _press_cue_styles.has(corner):
		_press_cue_styles[corner] = style(Color(Palette.ROSE_SOFT, 0.16), corner, Palette.ROSE_EDGE, 4)
	cue.add_theme_stylebox_override("panel", _press_cue_styles[corner])
	cue.hide()
	parent.add_child(cue)
	cue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return cue


func _show_press_feedback(cue: Panel, button: Button) -> void:
	_clear_press_feedback()
	if not is_instance_valid(cue) or button.disabled or _lp_swallowing():
		return
	_press_cue = cue
	_press_button = button
	cue.show()


func _clear_press_feedback(only: Panel = null) -> void:
	if only != null and only != _press_cue:
		return
	if is_instance_valid(_press_cue):
		_press_cue.hide()
	_press_cue = null
	_press_button = null


func _interrupt_press_feedback() -> void:
	if is_instance_valid(_press_button):
		_press_button.set_meta("press_interrupted", true)
	_clear_press_feedback()


func _bind_press_feedback(button: Button, action: Callable, corner: int) -> void:
	var cue := _make_press_feedback(button, corner)
	button.button_down.connect(func() -> void:
		button.set_meta("press_interrupted", false)
		_show_press_feedback(cue, button))
	button.button_up.connect(_clear_press_feedback.bind(cue))
	button.mouse_exited.connect(cue.hide)
	button.mouse_entered.connect(func() -> void:
		if _press_cue == cue and not button.disabled:
			cue.show())
	button.visibility_changed.connect(func() -> void:
		if _press_cue == cue and not button.is_visible_in_tree():
			_interrupt_press_feedback())
	button.pressed.connect(func() -> void:
		if not bool(button.get_meta("press_interrupted", false)) and not _lp_swallowing():
			action.call())


func _set_btn_theme(b: Button, bg: Color, border: Color, fg: Color, radius: int = 18, bw: int = 2, shadow: bool = false, pad: Vector2i = Vector2i(-1, -1), hover_border: Color = Color(-1, 0, 0, 0)) -> void:
	var hb: Color = hover_border if hover_border.r >= 0.0 else border
	var n_sb := style(bg, radius, border, bw, shadow)
	var h_sb := style(bg.lightened(0.07), radius, hb, bw, shadow)
	var p_sb := style(bg.darkened(0.08), radius, hb, bw, false)
	var disabled_bg := Palette.NIGHT_PANEL if _night_ui else Palette.DISABLED_BG
	var disabled_fg := Palette.NIGHT_MUTED if _night_ui else Palette.DISABLED_INK
	var d_sb := style(disabled_bg, radius, Color(_table_edge, 0.60), mini(bw, 1))
	if pad.x >= 0:
		for sb_i in [n_sb, h_sb, p_sb, d_sb]:
			_tight(sb_i, pad.x, pad.y)
	b.add_theme_stylebox_override("normal", n_sb)
	b.add_theme_stylebox_override("hover", h_sb)
	b.add_theme_stylebox_override("pressed", p_sb)
	b.add_theme_stylebox_override("disabled", d_sb)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", disabled_fg)


func plain_btn(text: String, bg: Color = Palette.MILK, fg: Color = Palette.ROSE_PRIMARY, fsize: int = 28) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_reg)
	b.add_theme_font_size_override("font_size", fsize)
	_set_btn_theme(b, bg, _table_edge, fg, 18, 1, false, Vector2i(-1, -1), Palette.ROSE_EDGE)
	_wire_btn_bounce(b)
	b.pressed.connect(func() -> void: play_sfx("click"))
	return b


func wait(sec: float) -> void:
	if fast:
		await get_tree().process_frame
		return
	# 可被「点空白桌面」打断的等待：点击时刻晚于本次等待开始即提前结束（无名杀点击跳过动画停顿）
	var skip_at_start := skip_motion_events
	var tm := get_tree().create_timer(sec)
	while tm.time_left > 0.0:
		if skip_motion_events != skip_at_start:
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
		speed_btn.text = "倍速 %sx" % str(SPEEDS[speed_idx])
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
	if not asking and interactive and in_play_phase and (targeting or not selected_card.is_empty() or skill_mode != "" or muniu_storing):
		_on_cancel_pressed()
		return
	if asking and ask_sel_has:
		_ask_clear_sel()
		return
	skip_motion_events += 1
	_skip_transient_motion()


func log_msg(msg: String) -> void:
	log_lines.append(msg)
	while log_lines.size() > 5:
		log_lines.pop_front()


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
			var rb := plain_btn("", _table_inset, _table_text, 28)
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
		p.custom_minimum_size = Vector2(300, 224)
		var tile_fill := Palette.ROSE_SOFT if i == 0 else Palette.SKY_SOFT
		var tile_edge := Palette.ROSE_EDGE if i == 0 else Palette.SKY_EDGE
		p.add_theme_stylebox_override("panel", style(Color(tile_fill, 0.95), 26, tile_edge, 1, true))
		var pv := VBoxContainer.new()
		pv.alignment = BoxContainer.ALIGNMENT_CENTER
		pv.add_theme_constant_override("separation", 10)
		var sn_l := lbl(seat_names[i], 28, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER)
		sn_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pv.add_child(sn_l)
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
	var start := plain_btn("开始对战（先选将）", C_TABLE_ACTION, C_WHITE, 40)
	start.custom_minimum_size = Vector2(560, 110)
	start.pressed.connect(func() -> void: start_match(false))
	row.add_child(start)
	vb.add_child(row)


# 新增 UI 成员（V0.3 桌面布局）
var phase_label: Label
var phase_pills: Array = []
var _table_phase_plate: Panel
var _table_phase_rect := Rect2()
var prompt_panel: PanelContainer
var draft_layer: HBoxContainer
var draft_refresh_btn: Button
var _draft_candidates: Array = []
var _draft_refresh_used := false
var _draft_confirming := false
var history_btn: Button
var in_play_phase: bool = false
var selected_card: Dictionary = {}
var sel_anim_card: Dictionary = {}
var vw := 1920.0
var safe_insets := Vector4.ZERO
var table_hud_height := 104.0
var tools_layer: ColorRect
var tools_btn: Button
var bubble_nodes := {}
var bubble_order: Array = []  # 同屏气泡最多 2 个，超出时先收最早的
var skill_sig := ""
var skill_passives: HBoxContainer = null
var speed_idx := 0
var speed_btn: Button = null
const SPEEDS := [1.0, 1.5, 2.0]
var skip_motion_events := 0  # 点空白桌面跳过当前等待（AI 出牌间隔/动画停顿）
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
var settlement_layer: Control = null
var target_candidates: Array = []
var draft_banner: Label
var glow_frames: Dictionary = {}
var _designated_targets: Array[int] = []
var _designated_until_ms := 0
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
const DRAG_START_PX := 28.0
const SNAP_PX := 64.0
const SNAP_RELEASE_PX := 88.0
const DRAG_SNAP_TIME := 0.16
const DRAG_DETACH_TIME := 0.105
const HAND_SETTLE_TIME := 0.18
const HAND_DRAW_TIME := 0.24
const HAND_RETURN_TIME := 0.245
const HAND_CARD_GAP := 10.0
const HAND_BROWSE_BUTTON_W := 86.0
var hand_x0 := 352.0
var hand_x1 := 1230.0
var hand_cards: Array = []  # 手牌节点（wrap），meta "card" 指向牌字典本身
var hand_viewport: Panel
var hand_prev_btn: Button
var hand_next_btn: Button
var hand_scroll_offset := 0.0
var hand_scroll_limit := 0.0
var action_bar: Control
var confirm_btn: Button
var cancel_btn: Button
var me_click_btn: Button
var ask_secs_label: Label
var asking := false
var ask_seq := 0
var ask_timeout := 15.0
const OPENING_LUCK_SECONDS := 20.0
var ask_default: Variant = null
var ask_default_caption := ""
var sel_target := -1
var discard_mode := false
var discard_need := 0
var discard_sel: Array = []
var discard_queue: Array = []
var discard_confirm_btn: Button = null
var respond_name := ""
var respond_names: Array = []
var muniu_storing: bool = false
var drag_wrap: Control = null
var drag_press := {}  # 从按下起只进入一种手势：点按、横览或拖出牌
var drag_previous := {}
var drag_hover_seat := -1
var drag_line: Line2D
var drag_hint: Label
var drag_pose := Vector3.ZERO
var drag_pose_offset := Vector3.ZERO
var drag_pose_tween: Tween
var hand_cancel_release := false
var drag_end_ms := 0
var _press_cue: Panel = null
var _press_button: Button = null
var _press_cue_styles: Dictionary = {}


func show_played_card(card: Dictionary, from_seat: int, hand_wrap: Control) -> Control:
	if card.is_empty():
		return null
	var from := _pz_center() + Vector2(0, -260)
	var hand_launch := {}
	if from_seat == 0:
		hand_launch = fly_from_hand if is_same(fly_from_hand.get("card"), card) else _hand_flight_origin(hand_wrap)
		from = Vector2(hand_launch.get("pos", _hand_point(120)))
	elif from_seat > 0:
		from = seat_center(from_seat)
	return _pz_add(card, "", from, hand_launch, true)


func _hand_flight_origin(w: Control) -> Dictionary:
	if not is_instance_valid(w):
		return {}
	var xf := get_global_transform().affine_inverse() * w.get_global_transform()
	return {"pos": xf * (w.size * 0.5), "scale": xf.get_scale(), "rotation": xf.get_rotation()}


func set_phase(text: String) -> void:
	if phase_label == null or text == _last_phase_text:
		return
	_last_phase_text = text
	phase_label.text = text
	for i in mini(PHASE_NAMES.size(), phase_pills.size()):
		var pn := phase_pills[i] as Panel
		if pn == null or not is_instance_valid(pn):
			continue
		var active := text.contains(PHASE_NAMES[i])
		if pn.get_meta("phase_active", false) == active:
			continue
		pn.set_meta("phase_active", active)
		pn.add_theme_stylebox_override("panel", _phase_active_style if active else _phase_idle_style)
		var lb := pn.get_node_or_null("PhLbl") as Label
		if lb != null:
			lb.add_theme_color_override("font_color", C_WHITE if active else _table_note)


func show_hint(text: String, context: String = "") -> void:
	if prompt_panel == null or prompt_label == null:
		return
	if asking and ask_mode == "opening_luck" and context != ask_context:
		return
	prompt_panel.visible = true
	prompt_label.text = text
	prompt_label.tooltip_text = text
	prompt_context_label.text = context
	prompt_context_label.visible = context != ""
	prompt_header.visible = prompt_context_label.visible or ask_secs_label.visible


func hide_prompt() -> void:
	if prompt_panel == null or prompt_label == null:
		return
	_reset_prompt_surface()
	ask_deadline_ms = 0
	_countdown_seconds = -1
	if ask_bar_bg_ref != null:
		ask_bar_bg_ref.visible = false
	if ask_secs_label != null:
		ask_secs_label.visible = false
	prompt_header.visible = false
	prompt_label.text = ""
	for ch in prompt_btns.get_children():
		prompt_btns.remove_child(ch)
		ch.queue_free()
	prompt_panel.visible = false


func _emphasize_new_prompt() -> void:
	if not _motion_enabled():
		return
	var tint := Palette.NIGHT_BORDER if _night_ui else Palette.ROSE_SOFT
	var amount := 0.20 if _night_ui else 0.72
	_prompt_surface_style.bg_color = Color(_table_surface.lerp(tint, amount), _table_surface.a)
	_prompt_surface_style.border_color = Palette.ROSE_EDGE
	_prompt_surface_tween = prompt_panel.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_prompt_surface_tween.tween_property(_prompt_surface_style, "bg_color", _table_surface, 0.24)
	_prompt_surface_tween.tween_property(_prompt_surface_style, "border_color", _table_edge, 0.24)


func _reset_prompt_surface() -> void:
	if _prompt_surface_tween == null:
		return
	if _prompt_surface_tween.is_valid():
		_prompt_surface_tween.kill()
	_prompt_surface_tween = null
	_prompt_surface_style.bg_color = _table_surface
	_prompt_surface_style.border_color = _table_edge


func _table_safe_insets() -> Vector4:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.size == Vector2i.ZERO:
		return Vector4.ZERO
	var screen_to_local := (get_viewport().get_screen_transform() * get_global_transform_with_canvas()).affine_inverse()
	var start := screen_to_local * Vector2(safe.position)
	var end := screen_to_local * Vector2(safe.end)
	# 预留两侧较大的值，左右横屏互换时也避开开孔或系统导航区。
	var side := ceilf(maxf(maxf(start.x, vw - end.x), 0.0))
	return Vector4(side, ceilf(maxf(start.y, 0.0)), side, ceilf(maxf(1080.0 - end.y, 0.0)))


func _build_table_hud() -> void:
	var left := safe_insets.x + 26.0
	var right := vw - safe_insets.z - 26.0
	var top := safe_insets.y
	tools_btn = plain_btn("托管中 ▾" if auto_mode else "工具 ▾", _table_inset, _table_text, 28)
	var tool_height := table_hud_height - 16.0 if table_hud_height > 104.0 else 72.0
	tools_btn.position = Vector2(left, top + (table_hud_height - tool_height) * 0.5)
	tools_btn.custom_minimum_size = Vector2(176, tool_height)
	tools_btn.size = tools_btn.custom_minimum_size
	tools_btn.pressed.connect(func() -> void: _set_tools_open(true))
	add_child(tools_btn)

	var count_width := 128.0
	var round_width := 148.0
	var count_gap := 8.0
	var counter_left := right - (count_width * 2.0 + round_width + count_gap * 2.0)
	var pill_lbls: Array[Label] = []
	for initial in ["牌堆 —", "弃牌 0", "选将中"]:
		var counter := lbl(initial, 24, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
		counter.position = Vector2(counter_left + pill_lbls.size() * (count_width + count_gap), top + (table_hud_height - 54.0) * 0.5)
		counter.size = Vector2(round_width if pill_lbls.size() == 2 else count_width, 54)
		counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		counter.autowrap_mode = TextServer.AUTOWRAP_OFF
		counter.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		counter.mouse_filter = MOUSE_FILTER_IGNORE
		var count_surface := Palette.SKY_SOFT if not _night_ui and pill_lbls.is_empty() else _table_inset
		var count_edge := Palette.SKY_EDGE if not _night_ui and pill_lbls.is_empty() else _table_edge
		counter.add_theme_stylebox_override("normal", _tight(style(count_surface, 17, count_edge, 1), 8, 4))
		add_child(counter)
		pill_lbls.append(counter)
	deck_label = pill_lbls[0]
	disc_label = pill_lbls[1]
	round_label = pill_lbls[2]

	var phase_left := left + tools_btn.size.x + 16.0
	var phase_right := counter_left - 16.0
	var phase_width := minf(584.0, phase_right - phase_left)
	var phase_x := clampf((vw - phase_width) * 0.5, phase_left, phase_right - phase_width)
	var phase_y := top + (table_hud_height - 84.0) * 0.5
	_table_phase_rect = Rect2(phase_x, phase_y, phase_width, 84)
	_table_phase_plate = Panel.new()
	_table_phase_plate.name = "TablePhasePlate"
	_table_phase_plate.position = _table_phase_rect.position
	_table_phase_plate.size = _table_phase_rect.size
	_table_phase_plate.mouse_filter = MOUSE_FILTER_IGNORE
	_table_phase_plate.add_theme_stylebox_override("panel", style(Color(_table_surface, 0.90), 18, _table_edge, 1, true))
	add_child(_table_phase_plate)
	phase_label = lbl("选将准备", 31, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
	phase_label.position = Vector2(phase_x + 8.0, phase_y + 2.0)
	phase_label.size = Vector2(phase_width - 16.0, 42)
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phase_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	phase_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	phase_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(phase_label)
	if _phase_active_style == null:
		_phase_active_style = style(C_TABLE_ACTION, 10, Palette.ROSE_EDGE, 1)
		_phase_idle_style = style(_table_inset, 10, Color(_table_edge, 0.72), 1)
	var gap := 7.0
	var width := minf(72.0, (phase_width - 20.0 - gap * (PHASE_NAMES.size() - 1)) / PHASE_NAMES.size())
	var phases_width := (width + gap) * PHASE_NAMES.size() - gap
	var start_x := phase_x + (phase_width - phases_width) * 0.5
	for i in PHASE_NAMES.size():
		var pill := Panel.new()
		pill.position = Vector2(start_x + i * (width + gap), phase_y + 46.0)
		pill.size = Vector2(width, 30)
		pill.mouse_filter = MOUSE_FILTER_IGNORE
		pill.add_theme_stylebox_override("panel", _phase_idle_style)
		var label := lbl(PHASE_NAMES[i], 19, _table_note, true, HORIZONTAL_ALIGNMENT_CENTER)
		label.name = "PhLbl"
		label.size = pill.size
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.mouse_filter = MOUSE_FILTER_IGNORE
		pill.add_child(label)
		add_child(pill)
		phase_pills.append(pill)
	turn_label = lbl("", 18, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
	turn_label.visible = false
	add_child(turn_label)


func _set_draft_hud(drafting: bool) -> void:
	for counter in [deck_label, disc_label, round_label]:
		counter.visible = not drafting
	for pill in phase_pills:
		pill.visible = not drafting
	var rect := _table_phase_rect
	if drafting:
		var draft_size := Vector2(minf(rect.size.x, 300.0), 54.0)
		rect = Rect2(rect.get_center() - draft_size * 0.5, draft_size)
		set_phase("选将准备")
	_table_phase_plate.position = rect.position
	_table_phase_plate.size = rect.size
	phase_label.position = rect.position + Vector2(8.0, 6.0 if drafting else 2.0)
	phase_label.size.x = rect.size.x - 16.0


func _set_tools_open(open: bool) -> void:
	if tools_layer == null or not is_instance_valid(tools_layer):
		return
	tools_layer.visible = open
	if open:
		move_child(tools_layer, get_child_count() - 1)


func _open_battle_history() -> void:
	open_info_overlay("战况记录", "\n".join(eng.log_lines) if eng != null else "\n".join(log_lines))


func _open_seat_list() -> void:
	var lines: Array[String] = []
	for p in players:
		var seat := int(p["seat"])
		var mark := "▶ " if seat == turn_seat and p["alive"] else ""
		var who := "（你）" if seat == 0 else ""
		var state := "体力 %d/%d · 手牌 %d" % [int(p["hp"]), int(p["max_hp"]), p["hand"].size()] if p["alive"] else "阵亡"
		lines.append("%s%d号位　%s%s　%s　%s" % [mark, seat + 1, p["char"]["name"], who, identity_visible(p), state])
	open_info_overlay("座次表", "\n\n".join(lines) if not lines.is_empty() else "尚未开局")


func _build_table_tools() -> void:
	tools_layer = ColorRect.new()
	tools_layer.name = "BattleTools"
	tools_layer.color = Color(0.12, 0.06, 0.15, 0.44)
	tools_layer.mouse_filter = MOUSE_FILTER_STOP
	tools_layer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_set_tools_open(false))
	tools_layer.visible = false
	add_child(tools_layer)
	tools_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var surface := PanelContainer.new()
	surface.position = Vector2(safe_insets.x + 26.0, safe_insets.y + table_hud_height + 12.0)
	surface.custom_minimum_size.x = 590.0
	surface.add_theme_stylebox_override("panel", _tight(style(_table_surface, 22, _table_edge, 1, true), 20, 18))
	tools_layer.add_child(surface)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 12)
	surface.add_child(contents)
	var header := lbl("对局工具", 30, _table_text, true)
	header.autowrap_mode = TextServer.AUTOWRAP_OFF
	contents.add_child(header)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	contents.add_child(grid)
	for title in ["战况记录", "座次表", "记牌器", "排序：类型", "托管", "倍速", "设置", "认输", "返回大厅", "关闭"]:
		var button := plain_btn(title, _table_inset, _table_text, 27)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(238, table_hud_height - 20.0)
		button.clip_text = true
		grid.add_child(button)
		match title:
			"战况记录":
				button.pressed.connect(_open_battle_history)
			"座次表":
				button.pressed.connect(_open_seat_list)
			"记牌器":
				button.pressed.connect(func() -> void: open_info_overlay("记牌器 · 战场情报", counter_text(), true))
			"排序：类型":
				sort_btn = button
				button.pressed.connect(func() -> void:
					_set_tools_open(false)
					sort_my_hand())
			"托管":
				auto_btn = button
				button.text = "托管中" if auto_mode else "开始托管"
				button.pressed.connect(func() -> void:
					_set_tools_open(false)
					toggle_auto())
			"倍速":
				speed_btn = button
				button.text = "倍速 %sx" % str(SPEEDS[speed_idx])
				button.pressed.connect(cycle_speed)
			"设置":
				settings_btn = button
				button.pressed.connect(func() -> void:
					_set_tools_open(false)
					toggle_settings_panel())
			"认输":
				concede_btn = button
				button.pressed.connect(on_concede_pressed)
			"返回大厅":
				button.pressed.connect(func() -> void:
					if go_home.is_valid():
						go_home.call())
			"关闭":
				button.pressed.connect(func() -> void: _set_tools_open(false))


func build_table() -> void:
	vw = get_viewport_rect().size.x
	safe_insets = _table_safe_insets()
	table_hud_height = 144.0 if OS.has_feature("android") or OS.has_feature("ios") else 104.0
	_interrupt_press_feedback()
	_reset_prompt_surface()
	_hide_turn_banner()
	_designated_targets.clear()
	_designated_until_ms = 0
	if is_instance_valid(target_traces):
		remove_child(target_traces)
		target_traces.queue_free()
	if is_instance_valid(target_trace_fades):
		remove_child(target_trace_fades)
		target_trace_fades.queue_free()
	for ch in get_children():
		ch.queue_free()
	table_nodes.clear()
	seat_panels.clear()
	diff_btns.clear()
	glow_frames.clear()
	phase_pills.clear()
	_last_phase_text = ""
	sort_btn = null
	puzzle_panel = null
	puzzle_hint_btn = null
	puzzle_label = null
	selected_card = {}
	targeting = false
	var bg_catch := Control.new()
	bg_catch.name = "BgCatch"
	bg_catch.mouse_filter = MOUSE_FILTER_STOP
	bg_catch.gui_input.connect(_on_table_bg_input)
	add_child(bg_catch)
	bg_catch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var table_tint := ColorRect.new()
	table_tint.color = Color(Palette.NIGHT_PANEL, 0.21) if _night_ui else Color(Palette.MILK, 0.13)
	table_tint.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(table_tint)
	table_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vertical_pad := maxf((get_viewport_rect().size.y - 1080.0) * 0.5, 0.0)
	table_tint.offset_top = -vertical_pad
	table_tint.offset_bottom = vertical_pad
	# 指示线贴着牌桌绘制，角色牌、处理区和响应按钮盖在上层。
	target_trace_fades = Node2D.new()
	target_trace_fades.name = "TargetTraceFades"
	add_child(target_trace_fades)
	target_traces = Node2D.new()
	target_traces.name = "TargetTraces"
	add_child(target_traces)
	pz_flight_layer = Control.new()
	pz_flight_layer.name = "HandFlight"
	pz_flight_layer.mouse_filter = MOUSE_FILTER_IGNORE
	pz_flight_layer.child_entered_tree.connect(_fx_click_through)
	add_child(pz_flight_layer)
	_build_table_hud()
	# 信息浮层（记牌器/战况记录共用）
	info_overlay = Panel.new()
	info_overlay.position = Vector2(0, 0)
	info_overlay.size = Vector2(vw, 1080)
	info_overlay.mouse_filter = MOUSE_FILTER_STOP
	info_overlay.add_theme_stylebox_override("panel", style(Color(Palette.NIGHT_PANEL, 0.70), 0))
	info_overlay.visible = false
	add_child(info_overlay)
	var dialog_width := minf(1160.0, vw - safe_insets.x - safe_insets.z - 56.0)
	var dialog_x := (vw - dialog_width) * 0.5
	var dialog_y := safe_insets.y + 112.0
	var close_top := 1080.0 - safe_insets.w - 118.0
	var card_panel := Panel.new()
	card_panel.position = Vector2(dialog_x, dialog_y)
	card_panel.size = Vector2(dialog_width, close_top - dialog_y - 16.0)
	card_panel.mouse_filter = MOUSE_FILTER_IGNORE
	card_panel.add_theme_stylebox_override("panel", style(Palette.MILK, 24, Palette.LILAC_EDGE, 1, true))
	info_overlay.add_child(card_panel)
	info_title = lbl("", 34, C_INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	info_title.position = Vector2(dialog_x, dialog_y + 24)
	info_title.size = Vector2(dialog_width, 48)
	info_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	info_overlay.add_child(info_title)
	info_text = RichTextLabel.new()
	info_text.bbcode_enabled = false
	info_text.fit_content = false
	info_text.scroll_active = true
	info_text.position = Vector2(dialog_x + 40, dialog_y + 96)
	info_text.size = Vector2(dialog_width - 80, close_top - dialog_y - 136)
	info_text.add_theme_font_override("normal_font", font_reg)
	info_text.add_theme_font_size_override("normal_font_size", 25)
	info_text.add_theme_color_override("default_color", C_INK)
	info_overlay.add_child(info_text)
	var close_btn := plain_btn("关闭", Palette.LILAC_SOFT, Palette.INK, 26)
	close_btn.position = Vector2(vw / 2.0 - 108, close_top)
	close_btn.size = Vector2(216, 92)
	close_btn.pressed.connect(func() -> void: info_overlay.visible = false)
	info_overlay.add_child(close_btn)
	_extend_cover(info_overlay, Color(Palette.NIGHT_PANEL, 0.70))
	# 座位在两侧留出同一块中央处理区。单挑对手与左下的自己斜向相对。
	var seat_pos: Dictionary
	var upper_y := safe_insets.y + table_hud_height + 24.0
	var side_y := minf(maxf(upper_y + 104.0, 280.0), 286.0 - safe_insets.w)
	var prompt_top := 530.0 - safe_insets.w
	_build_play_notice()
	var notice_height := play_callout_panel.get_combined_minimum_size().y
	play_area = _table_play_area(prompt_top, notice_height)
	play_callout_panel.position = Vector2(play_area.position.x, play_area.end.y + 8.0)
	play_callout_panel.custom_minimum_size = Vector2(play_area.size.x, notice_height)
	play_callout_panel.size = play_callout_panel.custom_minimum_size
	_build_skill_notice(side_y)
	var rail_margin := clampf(play_area.position.x - safe_insets.x - 532.0, 12.0, 42.0)
	var left_x := safe_insets.x + rail_margin
	var right_x := vw - safe_insets.z - rail_margin - 250.0
	var inner_left := play_area.position.x - 264.0
	var inner_right := play_area.end.x + 14.0
	if match_players == 3:
		seat_pos = {1: Vector2(inner_left, upper_y), 2: Vector2(inner_right, upper_y)}
	elif match_players == 2:
		seat_pos = {1: Vector2(lerpf(inner_right, right_x, 0.65), upper_y)}
	elif match_players == 4:
		seat_pos = {1: Vector2(left_x, side_y), 2: Vector2(inner_right, upper_y), 3: Vector2(right_x, side_y)}
	else:
		seat_pos = {1: Vector2(left_x, side_y), 2: Vector2(inner_left, upper_y), 3: Vector2(inner_right, upper_y), 4: Vector2(right_x, side_y)}
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
		glow.add_theme_stylebox_override("panel", style(Color(C_ACTIVE_SEAT, 0.08), 26, C_ACTIVE_SEAT, 3, true))
		glow.visible = false
		add_child(glow)
		glow_frames[seat_idx] = glow
	# 提示条（提问/选目标时出现）
	# V0.25 手杀式提示条：文字可智能换行 + 倒计时进度条（位于处理区下方）；作答按钮统一放在手牌上方的操作栏位置
	hand_x0 = 352.0 + safe_insets.x
	hand_x1 = vw - 690.0 - safe_insets.z
	var bar_cx := (hand_x0 + hand_x1) * 0.5
	prompt_action_width = clampf(hand_x1 - hand_x0, 420.0, 892.0)
	prompt_panel = PanelContainer.new()
	prompt_panel.position = Vector2(bar_cx - prompt_action_width * 0.5, prompt_top)
	prompt_panel.custom_minimum_size = Vector2(prompt_action_width, 74)
	prompt_panel.size = prompt_panel.custom_minimum_size
	prompt_panel.mouse_filter = MOUSE_FILTER_IGNORE
	_prompt_surface_style = _tight(style(_table_surface, 16, _table_edge, 1, true), 16, 7)
	prompt_panel.add_theme_stylebox_override("panel", _prompt_surface_style)
	var pv := VBoxContainer.new()
	pv.mouse_filter = MOUSE_FILTER_IGNORE
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 3)
	prompt_panel.add_child(pv)
	prompt_header = HBoxContainer.new()
	prompt_header.alignment = BoxContainer.ALIGNMENT_END
	prompt_header.mouse_filter = MOUSE_FILTER_IGNORE
	prompt_header.visible = false
	pv.add_child(prompt_header)
	prompt_context_label = lbl("", 26, _table_text, true)
	prompt_context_label.add_theme_font_override("font", Art.compact_bold_font(26))
	prompt_context_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt_context_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	prompt_context_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_context_label.mouse_filter = MOUSE_FILTER_IGNORE
	prompt_header.add_child(prompt_context_label)
	ask_secs_label = lbl("", 18, Palette.ROSE_SOFT if _night_ui else C_TABLE_ACTION, true, HORIZONTAL_ALIGNMENT_RIGHT)
	ask_secs_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	ask_secs_label.mouse_filter = MOUSE_FILTER_IGNORE
	ask_secs_label.visible = false
	prompt_header.add_child(ask_secs_label)
	prompt_label = lbl("", 25, _table_text, true, HORIZONTAL_ALIGNMENT_LEFT)
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.custom_minimum_size.y = 64.0
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.max_lines_visible = 2
	prompt_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	prompt_label.mouse_filter = MOUSE_FILTER_IGNORE
	pv.add_child(prompt_label)
	var ask_bar_bg := Panel.new()
	ask_bar_bg_ref = ask_bar_bg
	ask_bar_bg.visible = false
	ask_bar_bg.custom_minimum_size = Vector2(0, 5)
	ask_bar_bg.add_theme_stylebox_override("panel", style(_table_inset, 4))
	ask_bar_bg.mouse_filter = MOUSE_FILTER_IGNORE
	pv.add_child(ask_bar_bg)
	ask_bar_fill = ColorRect.new()
	ask_bar_fill.color = Color("#739fca")
	ask_bar_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	ask_bar_fill.mouse_filter = MOUSE_FILTER_IGNORE
	ask_bar_bg.add_child(ask_bar_fill)
	prompt_panel.visible = false
	add_child(prompt_panel)
	prompt_btns = HBoxContainer.new()
	prompt_btns.alignment = BoxContainer.ALIGNMENT_BEGIN
	prompt_btns.add_theme_constant_override("separation", int(TABLE_ACTION_GAP))
	prompt_btns.position = Vector2(bar_cx - prompt_action_width * 0.5, 649 - safe_insets.w)
	prompt_btns.size = Vector2(prompt_action_width, TABLE_ACTION_H)
	prompt_btns.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(prompt_btns)
	# 固定操作位置，隐藏空位后也不会移动其他按钮。
	action_bar = Control.new()
	action_bar.position = prompt_btns.position
	action_bar.size = prompt_btns.size
	action_bar.mouse_filter = MOUSE_FILTER_IGNORE
	action_bar.visible = false
	add_child(action_bar)
	confirm_btn = _make_action_btn("出牌", C_TABLE_ACTION, C_WHITE)
	_bind_press_feedback(confirm_btn, _on_confirm_pressed, 18)
	_place_table_action(confirm_btn, 0)
	cancel_btn = _make_action_btn("取消", _table_button, _table_text)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	_place_table_action(cancel_btn, 1)
	# V0.28：重铸（无名杀 recastable）——选中可重铸的牌后出现，点击即重铸（弃置并摸一张）
	recast_btn = _make_action_btn("重铸", _table_inset if _night_ui else Palette.SKY_SOFT, _table_text)
	recast_btn.pressed.connect(_on_recast_pressed)
	recast_btn.visible = false
	_place_table_action(recast_btn, 2)
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
	diff_layer.position = Vector2(vw * 0.5 - 368, 756)
	diff_layer.size = Vector2(736, 56)
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
	draft_refresh_btn = plain_btn("换一批（剩 1 次）", _table_inset, _table_text, 23)
	draft_refresh_btn.position = Vector2(500, 0)
	draft_refresh_btn.size = Vector2(236, 52)
	draft_refresh_btn.pressed.connect(_on_reshuffle_draft)
	diff_layer.add_child(draft_refresh_btn)
	# 左下：自己的角色牌
	var me_panel := Panel.new()
	me_panel_ref = me_panel
	me_panel.position = Vector2(40 + safe_insets.x, 676 - safe_insets.w)
	me_panel.size = Vector2(292, 372)
	me_panel.mouse_filter = MOUSE_FILTER_IGNORE
	me_panel.set_meta("seat", 0)
	me_panel.set_meta("intro", Callable(self, "_intro_seat").bind(0))
	me_panel.add_theme_stylebox_override("panel", style(_table_surface, 22, _table_edge, 1, true))
	add_child(me_panel)
	table_nodes.append(me_panel)
	var me_glow := Panel.new()
	me_glow.position = me_panel.position - Vector2(7, 7)
	me_glow.size = Vector2(306, 386)
	me_glow.mouse_filter = MOUSE_FILTER_IGNORE
	me_glow.add_theme_stylebox_override("panel", style(Color(C_ACTIVE_SEAT, 0.08), 26, C_ACTIVE_SEAT, 3, true))
	me_glow.visible = false
	add_child(me_glow)
	glow_frames[0] = me_glow
	# 特效层（最上层，不拦点击）
	fx_root = Control.new()
	fx_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_root.mouse_filter = MOUSE_FILTER_IGNORE
	fx_root.child_entered_tree.connect(_fx_click_through)
	add_child(fx_root)
	turn_banner_panel = PanelContainer.new()
	turn_banner_panel.position = Vector2(26.0 + safe_insets.x, safe_insets.y + table_hud_height + 14.0)
	turn_banner_panel.custom_minimum_size = Vector2(214, 46)
	turn_banner_panel.size = turn_banner_panel.custom_minimum_size
	turn_banner_panel.hide()
	turn_banner_panel.mouse_filter = MOUSE_FILTER_IGNORE
	turn_banner_panel.add_theme_stylebox_override("panel", _tight(style(_table_surface, 15, _table_edge, 1, true), 12, 6))
	fx_root.add_child(turn_banner_panel)
	turn_banner = lbl("", 23, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
	turn_banner.autowrap_mode = TextServer.AUTOWRAP_OFF
	turn_banner.mouse_filter = MOUSE_FILTER_IGNORE
	turn_banner_panel.add_child(turn_banner)
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
	player_portrait.pivot_offset = Vector2(139, 168)
	var me_plate := Panel.new()
	me_plate.position = Vector2(7, 279)
	me_plate.size = Vector2(278, 86)
	me_plate.mouse_filter = MOUSE_FILTER_IGNORE
	me_plate.add_theme_stylebox_override("panel", style(_table_surface, 9))
	me_panel.add_child(me_plate)
	player_info = lbl("", 27, _table_text, true)
	player_info.position = Vector2(12, 8)
	player_info.size = Vector2(252, 40)
	player_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	player_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	me_plate.add_child(player_info)
	me_hp_label = lbl("", 22, _table_note, true)
	me_hp_label.position = Vector2(12, 324)
	me_hp_label.size = Vector2(268, 31)
	me_hp_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	me_hp_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	me_panel.add_child(me_hp_label)
	_add_seat_overlays(me_panel, Vector2(292, 372), true)
	Art.add_corners(me_panel, Vector2(292, 372), 23.0, 0.0)
	_build_guess_popup()
	me_chips = HBoxContainer.new()
	me_chips.position = Vector2(356 + safe_insets.x, 988 - safe_insets.w)
	me_chips.add_theme_constant_override("separation", 10)
	add_child(me_chips)
	table_nodes.append(me_chips)
	skill_passives = HBoxContainer.new()
	skill_passives.position = Vector2(vw - 674 - safe_insets.z, 684 - safe_insets.w)
	skill_passives.add_theme_constant_override("separation", 8)
	add_child(skill_passives)
	table_nodes.append(skill_passives)
	skill_sig = ""
	skill_btns = VBoxContainer.new()
	skill_btns.position = Vector2(vw - 674 - safe_insets.z, 738 - safe_insets.w)
	skill_btns.size = Vector2(244, 210)
	skill_btns.add_theme_constant_override("separation", 14)
	add_child(skill_btns)
	table_nodes.append(skill_btns)
	_build_hand_controls()
	# 自己的头像也可点选（以自己为目标的牌：补给、增兵减灶、洞烛先机等）
	me_click_btn = Button.new()
	me_click_btn.flat = true
	me_click_btn.focus_mode = Control.FOCUS_NONE
	me_click_btn.position = me_panel_ref.position
	me_click_btn.size = Vector2(292, 372)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		me_click_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_bind_press_feedback(me_click_btn, _on_seat_clicked.bind(0), 22)
	me_click_btn.set_meta("intro", Callable(self, "_intro_seat").bind(0))
	add_child(me_click_btn)
	table_nodes.append(me_click_btn)
	# 选将身份横幅（仅选将时显示）
	draft_banner = lbl("", 34, C_PINK_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER)
	draft_banner.add_theme_font_override("font", Art.compact_bold_font(34))
	draft_banner.add_theme_constant_override("outline_size", 6)
	draft_banner.add_theme_constant_override("line_spacing", 5)
	draft_banner.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	draft_banner.position = Vector2(safe_insets.x, safe_insets.y + table_hud_height + 12.0)
	draft_banner.size = Vector2(vw - safe_insets.x - safe_insets.z, 90)
	draft_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draft_banner.visible = false
	add_child(draft_banner)
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
	# 处理区层（节点池复用）
	pz_clip = Control.new()
	pz_clip.name = "PlayArea"
	pz_clip.position = play_area.position
	pz_clip.size = play_area.size
	pz_clip.clip_contents = true
	pz_clip.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(pz_clip)
	pz_layer = Control.new()
	# 处理区沿用牌桌坐标，外层限制牌面与飞行轨迹的可见范围。
	pz_layer.position = -play_area.position
	pz_layer.mouse_filter = MOUSE_FILTER_IGNORE
	pz_layer.child_entered_tree.connect(_fx_click_through)
	pz_clip.add_child(pz_layer)
	pz_pool.clear()
	pz_live.clear()
	nullify_count = 0
	# 结束出牌保留在行动条。
	end_play_btn = _make_action_btn("结束出牌", _table_inset, _table_text)
	end_play_btn.disabled = true
	end_play_btn.pressed.connect(_on_end_play_btn)
	_place_table_action(end_play_btn, 3)
	history_btn = plain_btn("战报", _table_inset, _table_text, 25)
	history_btn.name = "BattleHistory"
	history_btn.custom_minimum_size = Vector2(152, 72)
	history_btn.size = history_btn.custom_minimum_size
	history_btn.position = Vector2(vw - safe_insets.z - 40.0 - history_btn.size.x, 742.0 - safe_insets.w)
	history_btn.tooltip_text = "查看本局战况记录"
	history_btn.pressed.connect(_open_battle_history)
	add_child(history_btn)
	table_nodes.append(history_btn)
	_build_table_tools()


func make_seat_panel(seat_idx: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", style(_table_surface, 18, _table_edge, 2, true))
	b.add_theme_stylebox_override("hover", style(_table_inset, 18, Palette.ROSE_EDGE, 2, true))
	b.add_theme_stylebox_override("pressed", style(_table_surface, 18, Palette.ROSE_EDGE, 2))
	b.add_theme_stylebox_override("disabled", style(_table_surface, 18, _table_edge, 2, true))
	var mat := Panel.new()
	mat.position = Vector2(5, 5)
	mat.size = Vector2(240, 362)
	mat.mouse_filter = MOUSE_FILTER_IGNORE
	mat.add_theme_stylebox_override("panel", style(_table_inset, 14))
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
	gem.add_theme_stylebox_override("panel", style(_table_inset, 25, _table_edge, 1, true))
	b.add_child(gem)
	var gt := lbl("?", 27, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
	gt.name = "GemText"
	gt.position = Vector2(0, 7)
	gt.size = Vector2(50, 36)
	gem.add_child(gt)
	var pips := VBoxContainer.new()
	pips.name = "Pips"
	pips.position = Vector2(214, 14)
	pips.add_theme_constant_override("separation", 6)
	pips.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(pips)
	var info_bg := Panel.new()
	info_bg.position = Vector2(7, 287)
	info_bg.size = Vector2(236, 78)
	info_bg.mouse_filter = MOUSE_FILTER_IGNORE
	info_bg.add_theme_stylebox_override("panel", style(_table_surface, 8))
	b.add_child(info_bg)
	var seat_name := lbl("", 27, _table_text, true)
	seat_name.name = "SeatName"
	seat_name.position = Vector2(16, 291)
	seat_name.size = Vector2(216, 39)
	seat_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	seat_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	seat_name.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(seat_name)
	var info := lbl("", 20, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
	info.name = "Info"
	info.position = Vector2(13, 104)
	info.size = Vector2(194, 38)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.mouse_filter = MOUSE_FILTER_IGNORE
	info.add_theme_stylebox_override("normal", _tight(style(_table_surface, 9), 6, 2))
	info.hide()
	b.add_child(info)
	var ct := lbl("", 22, _table_note, true)
	ct.name = "ChipText"
	ct.position = Vector2(16, 326)
	ct.size = Vector2(216, 35)
	ct.autowrap_mode = TextServer.AUTOWRAP_OFF
	ct.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(ct)
	Art.add_corners(b, Vector2(250, 372), 22.0, 0.0)
	_add_seat_overlays(b, Vector2(250, 372), false)
	# 猜身份按钮（身份局、身份未明时）：座位本身只在选目标时可点，猜测用独立小按钮
	var gb := Button.new()
	gb.name = "GuessBtn"
	gb.focus_mode = Control.FOCUS_NONE
	gb.position = Vector2(164, 156)
	gb.size = Vector2(78, 64)
	gb.custom_minimum_size = gb.size
	gb.text = "猜身份"
	gb.add_theme_font_override("font", font_bold)
	gb.add_theme_font_size_override("font_size", 21)
	_set_btn_theme(gb, _table_inset, _table_edge, _table_text, 14, 1, true, Vector2i(4, 2), Palette.ROSE_EDGE)
	_wire_btn_bounce(gb)
	gb.pressed.connect(func() -> void: _open_guess(seat_idx))
	gb.visible = false
	b.add_child(gb)
	var eb := Button.new()
	eb.name = "EmoteBtn"
	eb.focus_mode = Control.FOCUS_NONE
	eb.position = Vector2(164, 222)
	eb.size = Vector2(78, 62)
	eb.custom_minimum_size = eb.size
	eb.text = "🌹"
	eb.add_theme_font_override("font", font_bold)
	eb.add_theme_font_size_override("font_size", 22)
	_set_btn_theme(eb, _table_button, _table_edge, _table_text, 14, 1, true, Vector2i(4, 2), Palette.ROSE_EDGE)
	_wire_btn_bounce(eb)
	eb.pressed.connect(func() -> void: _throw_seat_emote(seat_idx))
	b.add_child(eb)
	b.set_meta("seat", seat_idx)
	b.set_meta("intro", Callable(self, "_intro_seat").bind(seat_idx))
	_bind_press_feedback(b, _on_seat_clicked.bind(seat_idx), 18)
	return b


# ---------------- V0.25 座位组件：装备栏 / 判定区图标 / 连环 / 濒死 / 阵亡 / 阶段标签 / 体力槽动画 ----------------
# 对照无名杀 layout：装备在头像左侧竖排、判定区小圆标在头像上沿、横置（连环）有锁链带、阵亡置灰并亮身份。
# 所有子节点建桌时一次建好，refresh 只改有变化的内容。

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
var _impact_width: Curve


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
	eqv.position = Vector2(10, 143) if not is_me else Vector2(10, 134)
	eqv.size = Vector2(152, 142)
	eqv.alignment = BoxContainer.ALIGNMENT_END
	eqv.add_theme_constant_override("separation", 3)
	eqv.mouse_filter = MOUSE_FILTER_IGNORE
	pn.add_child(eqv)
	for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
		var row := PanelContainer.new()
		row.name = slot
		row.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel", _tight(style(_table_surface, 8, _table_edge, 1), 3, 2))
		var hb := HBoxContainer.new()
		hb.mouse_filter = MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 4)
		row.add_child(hb)
		var tag := lbl(String(SLOT_TAGS[slot]), 15, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
		tag.name = "Tag"
		tag.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.custom_minimum_size = Vector2(28, 22)
		tag.add_theme_stylebox_override("normal", _tight(style(_table_inset, 6), 2, 0))
		hb.add_child(tag)
		var nm := lbl("", 16, _table_text, true)
		nm.name = "Name"
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		hb.add_child(nm)
		row.visible = false
		row.set_meta("intro", Callable(self, "_intro_equip").bind(pn, slot))
		eqv.add_child(row)
	# 判定区：最多 4 个小圆标
	var jh := HBoxContainer.new()
	jh.name = "Judges"
	jh.position = Vector2(13, 66) if not is_me else Vector2(12, 12)
	jh.add_theme_constant_override("separation", 4)
	jh.mouse_filter = MOUSE_FILTER_IGNORE
	pn.add_child(jh)
	for i in 4:
		var jl := lbl("", 18, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
		jl.custom_minimum_size = Vector2(32, 32)
		jl.add_theme_stylebox_override("normal", _tight(style(_table_inset, 16, _table_edge, 1, true), 0, 0))
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
	var badge_top := 56.0 if is_me else 14.0
	var actor_badge := _make_seat_badge("回合", Color("#305986"), C_ACTIVE_SEAT)
	actor_badge.name = "TurnBadge"
	actor_badge.position = Vector2(14 if is_me else 67, badge_top)
	pn.add_child(actor_badge)
	var assigned_badge := _make_seat_badge("目标", Color("#774814"), C_DESIGNATED_SEAT)
	assigned_badge.name = "DesignatedTargetBadge"
	assigned_badge.position = Vector2(210 if is_me else 140, badge_top)
	pn.add_child(assigned_badge)
	var target_tag := lbl("", 20, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
	target_tag.name = "TargetTag"
	target_tag.position = Vector2(67, 14) if not is_me else Vector2(sz.x - 184.0, 56)
	target_tag.size = Vector2(141, 42) if not is_me else Vector2(159, 40)
	target_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	target_tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	target_tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	target_tag.mouse_filter = MOUSE_FILTER_IGNORE
	target_tag.add_theme_stylebox_override("normal", _tight(style(_table_surface, 10, _table_edge, 1), 6, 3))
	target_tag.visible = false
	pn.add_child(target_tag)
	if is_me:
		var status := lbl("", 21, _table_text, true)
		status.name = "Info"
		status.position = Vector2(13, 103)
		status.size = Vector2(266, 38)
		status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status.mouse_filter = MOUSE_FILTER_IGNORE
		status.add_theme_stylebox_override("normal", _tight(style(_table_surface, 9), 7, 2))
		status.visible = false
		pn.add_child(status)
	pn.move_child(ch, eqv.get_index())  # 锁链带画在装备栏下面，不遮装备
	for n in [eqv, jh, ch, dy, dl]:
		for sub in (n as Node).find_children("*", "Control", true, false):
			(sub as Control).mouse_filter = MOUSE_FILTER_IGNORE


func _make_seat_badge(text: String, bg: Color, edge: Color) -> Label:
	var badge := lbl(text, 28, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	badge.size = Vector2(68, 42)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge.mouse_filter = MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("normal", _tight(style(bg, 10, edge, 2), 5, 0))
	badge.hide()
	return badge


func _sync_seat_badges(panel: Control, seat: int, alive: bool) -> void:
	var actor_badge := panel.get_node("TurnBadge") as Label
	actor_badge.visible = alive and not game_over and seat == turn_seat
	var tag := panel.get_node("TargetTag") as Label
	tag.visible = alive and not game_over and targeting and target_candidates.has(seat)
	var assigned_badge := panel.get_node("DesignatedTargetBadge") as Label
	assigned_badge.visible = alive and not game_over and not tag.visible and _designated_targets.has(seat)
	if not tag.visible:
		return
	var compact := seat > 0 and actor_badge.visible
	if seat > 0:
		tag.position.x = 140.0 if compact else 67.0
		tag.size.x = 68.0 if compact else 141.0
	if seat == drag_hover_seat:
		tag.text = "松手" if compact else "松手出牌"
		return
	if seat == sel_target:
		tag.text = "已选" if compact else "① 已选"
	elif seat == extra_target:
		tag.text = "已选" if compact else "② 已选"
	else:
		tag.text = "可选" if compact else "✓ 可选"
	if seat > 0 and not compact and _target_uses_distance(String(selected_card.get("name", ""))):
		tag.text += " · 距%d" % eff_dist(players[0], players[seat])


func _replace_designated_targets(seats: Array) -> void:
	_clear_designated_targets()
	for seat in seats:
		_add_designated_target(int(seat))


func _add_designated_target(seat: int) -> void:
	if auto_all or game_over or seat < 0 or seat >= players.size() or not players[seat]["alive"]:
		return
	_designated_until_ms = Time.get_ticks_msec() + DESIGNATED_TARGET_MS
	if not _designated_targets.has(seat):
		_designated_targets.append(seat)
		_queue_refresh()


func _clear_designated_targets() -> void:
	if is_instance_valid(target_traces):
		for trace in target_traces.get_children():
			if _motion_enabled() and not game_over and trace.progress > 0.0:
				trace.reparent(target_trace_fades, false)
				trace.fade_out()
			else:
				target_traces.remove_child(trace)
				trace.queue_free()
	if _designated_targets.is_empty():
		return
	_designated_targets.clear()
	_designated_until_ms = 0
	_queue_refresh()


func _seat_frame_color(seat: int, alive: bool) -> Color:
	if not alive or game_over:
		return _table_edge
	if targeting and target_candidates.has(seat):
		return C_TABLE_ACTION if seat == sel_target or seat == extra_target else C_TARGET_AVAILABLE
	if _designated_targets.has(seat):
		return C_DESIGNATED_SEAT
	return C_ACTIVE_SEAT if seat == turn_seat else _table_edge


func _sync_seat_frame(panel: Control, seat: int, alive: bool) -> void:
	_sync_seat_badges(panel, seat, alive)
	var frame := _seat_frame_color(seat, alive)
	if panel.get_meta("frame_color", Color.TRANSPARENT) == frame:
		return
	var styles := _own_frame_styles if seat == 0 else _seat_frame_styles
	if not styles.has(frame):
		styles[frame] = style(_table_surface, 22 if seat == 0 else 18, frame, 2 if frame == _table_edge else 4, true)
	if seat == 0:
		panel.add_theme_stylebox_override("panel", styles[frame])
	else:
		panel.add_theme_stylebox_override("normal", styles[frame])
		panel.add_theme_stylebox_override("disabled", styles[frame])
		panel.add_theme_stylebox_override("hover", styles[frame])
	panel.set_meta("frame_color", frame)


func _target_uses_distance(card_name: String) -> bool:
	return spear_targeting or card_name in ["突击", "悄悄借走", "断粮封锁", "逐近弃远"]


func _seat_status_text(seat: int, p: Dictionary) -> String:
	if not p["alive"]:
		return ""
	var flags: Array[String] = []
	var identity := String(p["identity"])
	if game_mode == "doudizhu" and eng != null and eng.ddz_open_seats.has(seat):
		flags.append("明牌")
	if seat != 0 and identity == String(players[0]["identity"]):
		if game_mode in ["twovtwo", "boss"] or (game_mode == "doudizhu" and identity == "农民"):
			flags.append("队友")
	if bool(p.get("skills_sealed", false)):
		flags.append("封技")
	var shield := int(p.get("shield", 0))
	if shield > 0:
		flags.append("护甲%d" % shield)
	var feather := int((p.get("marks", {}) as Dictionary).get("影羽", 0))
	if feather > 0:
		flags.append("影羽%d" % feather)
	if seat > 0 and targeting:
		var card_name := String(selected_card.get("name", ""))
		if _target_uses_distance(card_name):
			var distance := eff_dist(players[0], p)
			if card_name == "逐近弃远":
				flags.push_front("近距 · 获得一张" if distance <= 1 else "远距 · 弃置一张")
			elif (card_name == "突击" or spear_targeting) and bool(p.get("dream_guard", false)):
				flags.push_front("星眠免疫")
			elif not target_candidates.has(seat):
				flags.push_front("距离 %d" % distance)
	return " · ".join(flags)


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
	var chained := alive and bool(p.get("chained", false))
	var dying := alive and int(p["hp"]) <= 0
	var js: Array = p["judge"] if alive else []
	# 只比较面板会用到的值。手牌或回合变化时无需重复更新装备和状态节点。
	var state: Array = [alive, chained, dying]
	if alive:
		var equipment: Dictionary = p["equip"]
		for slot in SLOT_TAGS:
			state.append((equipment[slot] as Dictionary).get("name", ""))
		var treasure: Dictionary = equipment["treasure"]
		if treasure.get("name", "") == "木牛流马":
			state.append((treasure.get("stored", []) as Array).size())
		for card in js:
			state.append(card["name"])
	if pn.get_meta("overlay_state", []) == state:
		return
	var eqv := pn.get_node_or_null("Equips")
	if eqv == null:
		return
	pn.set_meta("overlay_state", state)
	for row in eqv.get_children():
		var slot := String(row.name)
		var txt := _equip_short(p, slot) if alive else ""
		(row as Control).visible = txt != ""
		if txt != "":
			var nl: Label = (row.get_child(0) as Node).get_node("Name")
			nl.text = txt
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
	(pn.get_node("Chain") as Control).visible = chained
	var dy := pn.get_node("Dying") as Control
	dy.visible = dying
	var dead_lbl := pn.get_node("Dead") as Label
	if not alive and not dead_lbl.visible:
		dead_lbl.visible = true
		if _motion_enabled():
			dead_lbl.scale = Vector2(2.2, 2.2)
			dead_lbl.modulate.a = 0.0
			var st := dead_lbl.create_tween().set_parallel(true)
			st.tween_property(dead_lbl, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			st.tween_property(dead_lbl, "modulate:a", 1.0, 0.2)
	elif alive and dead_lbl.visible:
		dead_lbl.visible = false
	if portrait != null:
		portrait.material = null if alive else gray_mat


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
	elif pips.has_meta("hp_shown") and int(pips.get_meta("hp_shown")) == hp:
		return
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
	if pn == null or not _motion_enabled():
		return
	var gem := pn.get_node_or_null("Gem") as Control
	if gem == null:
		return
	gem.pivot_offset = gem.size * 0.5
	var t: Tween = gem.create_tween()
	t.tween_property(gem, "scale:x", 0.22, 0.07)
	t.tween_property(gem, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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
	var x := clampf(pn.position.x + pn.size.x * 0.5 - w * 0.5, safe_insets.x + 8.0, vw - safe_insets.z - w - 8.0)
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
	guess_popup.add_theme_stylebox_override("panel", style(_table_surface, 16, _table_edge, 1, true))
	guess_popup.visible = false
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	guess_popup.add_child(hb)
	var role_cols := {"主": Color(0.84, 0.22, 0.34), "忠": Color(0.86, 0.56, 0.14), "反": Color(0.20, 0.62, 0.44), "内": Color(0.42, 0.34, 0.72), "": Color(0.36, 0.32, 0.44)}
	for mk in ["主", "忠", "反", "内", ""]:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = mk if mk != "" else "清"
		b.custom_minimum_size = Vector2(62, 52)
		b.add_theme_font_override("font", font_bold)
		b.add_theme_font_size_override("font_size", 24)
		var gcol: Color = role_cols[mk]
		_set_btn_theme(b, gcol, Color(1.0, 0.88, 0.56), C_WHITE, 14, 2, true, Vector2i(6, 4))
		_wire_btn_bounce(b)
		var m: String = mk
		b.pressed.connect(func() -> void:
			play_sfx("click")
			_pick_guess(m))  # 只隐藏弹层，不释放按钮（避免 V0.24 信号内释放）
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
func _seat_cg(pn: Control, tr: TextureRect, ch: Dictionary, aspect: float) -> void:
	if pn == null or tr == null:
		return
	var cid := String(ch.get("id", ""))
	if String(pn.get_meta("cg_id", "")) == cid:
		return
	pn.set_meta("cg_id", cid)
	tr.texture = Art.cg_crop(ch, aspect, 0.62, 0.32)


# V0.24 闪退修复（交接说明「安卓 15 选突击目标时应用自行关闭」的根因）：
# 旧版 refresh() 重建手牌行/技能按钮时对旧节点直接调用 free()。点击手牌「突击」进入选目标、点技能按钮、点装备牌时，
# 按钮的 pressed 信号处理函数会同步调用 refresh()，于是正在发射信号的按钮（及其父节点）在信号回调中途被立即释放，
# 信号返回后引擎继续访问已释放的按钮内存（use-after-free）。桌面调试版内存未被回收不一定崩，
# 安卓 release 版（Scudo 分配器/内存标记）会直接触发原生崩溃，表现为应用无报错自行关闭。
# 现统一改为 remove_child + queue_free（帧末才释放），并把引擎频繁的 changed() 合并为每帧最多一次刷新。
func refresh() -> void:
	# 同步刷新已读到最新状态，帧尾不必再重复刷新一次。
	_refresh_pending = false
	if players.is_empty() or seat_panels.is_empty():
		return
	if eng != null:
		deck_label.text = "牌堆 %d" % eng.deck.size()
		disc_label.text = "弃牌 %d" % eng.discard_pile.size()
		if int(eng.round_no) == 0:
			round_label.text = "开局"
		else:
			round_label.text = ("第 %d 轮 · ×%d" % [round_no, int(eng.ddz_stake())]) if game_mode == "doudizhu" else ("第 %d 轮" % round_no)
	if turn_seat >= 0 and turn_seat < players.size():
		var tp: Dictionary = players[turn_seat]
		var ph_s := String(eng.phase_text) if eng != null and String(eng.phase_text) != "" else "准备阶段"
		var actor := "你的回合" if turn_seat == 0 else "%d号位  %s" % [turn_seat + 1, tp["char"]["name"]]
		set_phase("▶ %s   /   %s" % [actor, ph_s])
	for panel in seat_panels:
		var seat_idx := int(panel.get_meta("seat"))
		var p: Dictionary = players[seat_idx]
		var tr: TextureRect = panel.get_node("Portrait")
		_seat_cg(panel, tr, p["char"], 236.0 / 358.0)
		var idt := identity_visible(p)
		var gem_pn := panel.get_node("Gem") as Panel
		var gem_col := _table_inset
		if not idt.begins_with("？"):
			var role_tint := Palette.ROSE_SOFT if idt in ["主公", "地主", "魔王"] else Palette.SKY_SOFT
			gem_col = _table_inset.lerp(role_tint, 0.12) if _night_ui else role_tint
		if gem_pn.get_meta("style_color", Color.TRANSPARENT) != gem_col:
			if not _seat_gem_styles.has(gem_col):
				_seat_gem_styles[gem_col] = style(gem_col, 25, _table_edge, 1, true)
			gem_pn.add_theme_stylebox_override("panel", _seat_gem_styles[gem_col])
			gem_pn.set_meta("style_color", gem_col)
		var gem_text: Label = panel.get_node("Gem/GemText")
		gem_text.text = "?" if idt.begins_with("？") else idt.substr(0, 1)
		var seat_name := panel.get_node("SeatName") as Label
		seat_name.text = String(p["char"]["name"])
		var chip_text := panel.get_node("ChipText") as Label
		chip_text.text = "体力 %d/%d · 手牌 %d" % [int(p["hp"]), int(p["max_hp"]), p["hand"].size()] if p["alive"] else "已阵亡 · %s" % idt
		var gm := String(guess_marks.get(seat_idx, ""))
		var gbtn := panel.get_node("GuessBtn") as Button
		gbtn.visible = not targeting and game_mode == "identity" and bool(p["alive"]) and idt.begins_with("？")
		gbtn.text = gm if gm != "" else "猜"
		var ebtn := panel.get_node("EmoteBtn") as Button
		ebtn.visible = bool(p["alive"]) and not targeting
		var info := panel.get_node("Info") as Label
		info.text = _seat_status_text(seat_idx, p)
		info.visible = info.text != ""
		_sync_seat_frame(panel, seat_idx, bool(p["alive"]))
		_sync_pips(panel.get_node("Pips") as VBoxContainer, p)
		_update_seat_overlays(panel, p, tr)
		if not p["alive"]:
			panel.modulate = Color(0.62, 0.62, 0.68, 0.85)
		elif targeting and not target_candidates.has(seat_idx):
			panel.modulate = Color(1, 1, 1, 0.45)
		else:
			panel.modulate = Color(1, 1, 1, 1)
		panel.disabled = not (targeting and target_candidates.has(seat_idx) and bool(p["alive"]))
	if guess_popup != null and guess_popup.visible and targeting:
		guess_popup.visible = false
	for seat_key in glow_frames:
		var seat := int(seat_key)
		(glow_frames[seat_key] as Control).visible = not game_over and seat == turn_seat and players[seat]["alive"]
	# 自己
	var me: Dictionary = players[0]
	if me_click_btn != null:
		me_click_btn.disabled = not (targeting and target_candidates.has(0) and bool(me["alive"]))
		me_click_btn.mouse_filter = MOUSE_FILTER_STOP if not me_click_btn.disabled else MOUSE_FILTER_IGNORE
	_seat_cg(me_panel_ref, player_portrait, me["char"], 278.0 / 336.0)
	player_info.text = "%s · %s" % [me["char"]["name"], me["identity"]]
	var h_cnt: int = (me["hand"] as Array).size()
	var h_lim: int = eng.hand_limit(me) if eng != null else maxi(int(me["hp"]), 0)
	me_hp_label.text = "体力 %d/%d · 手牌 %d/%d" % [int(me["hp"]), int(me["max_hp"]), h_cnt, h_lim]
	# 自己的体力变化：数值条闪红/闪绿（座位体力槽同理）
	var me_hp := int(me["hp"])
	if me_hp_label.has_meta("hp_shown") and int(me_hp_label.get_meta("hp_shown")) != me_hp and not fast and not auto_all:
		var lost := me_hp < int(me_hp_label.get_meta("hp_shown"))
		me_hp_label.modulate = Color(1.6, 0.4, 0.4) if lost else Color(0.5, 1.6, 0.6)
		var mt: Tween = me_hp_label.create_tween()
		mt.tween_property(me_hp_label, "modulate", Color.WHITE, 0.6)
	me_hp_label.set_meta("hp_shown", me_hp)
	if me_panel_ref != null:
		var self_status := me_panel_ref.get_node("Info") as Label
		var state := _seat_status_text(0, me)
		if h_cnt > h_lim and turn_seat == 0 and me["alive"]:
			state += (" · " if state != "" else "") + "超出上限 %d 张" % (h_cnt - h_lim)
		self_status.text = state
		self_status.visible = state != ""
		_sync_seat_frame(me_panel_ref, 0, bool(me["alive"]))
		_update_seat_overlays(me_panel_ref, me, player_portrait)
	_sync_hand()
	_update_action_bar()
	refresh_skill_buttons()
	if is_instance_valid(_press_button):
		if _press_button.disabled or not _press_button.is_visible_in_tree():
			_interrupt_press_feedback()
		elif _press_button.get_parent() == drag_press.get("wrap") and not _hand_accepts_press():
			_interrupt_press_feedback()
			drag_press.clear()
			hand_cancel_release = true


func _build_hand_controls() -> void:
	var top := HAND_Y - safe_insets.w
	var width := hand_x1 - hand_x0
	var hand_dock := Panel.new()
	hand_dock.position = Vector2(hand_x0 - 6.0, top + 24.0)
	hand_dock.size = Vector2(width + 12.0, HAND_H - 25.0)
	hand_dock.mouse_filter = MOUSE_FILTER_IGNORE
	hand_dock.add_theme_stylebox_override("panel", style(Color(_table_inset, 0.83), 20, Color(_table_edge, 0.82), 1))
	add_child(hand_dock)
	table_nodes.append(hand_dock)

	hand_viewport = Panel.new()
	hand_viewport.position = Vector2(hand_x0, top - LIFT - 10.0)
	hand_viewport.size = Vector2(width, HAND_H + LIFT + 10.0)
	hand_viewport.clip_contents = true
	hand_viewport.mouse_filter = MOUSE_FILTER_STOP
	hand_viewport.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	hand_viewport.gui_input.connect(_on_hand_viewport_gui_input)
	add_child(hand_viewport)
	table_nodes.append(hand_viewport)

	hand_row = Control.new()
	hand_row.position.y = LIFT + 10.0
	hand_row.size = Vector2(width, HAND_H)
	hand_row.mouse_filter = MOUSE_FILTER_IGNORE
	hand_viewport.add_child(hand_row)
	hand_cards.clear()
	hand_scroll_offset = 0.0
	hand_scroll_limit = 0.0
	drag_wrap = null
	drag_press.clear()
	drag_previous.clear()
	drag_hover_seat = -1
	hand_cancel_release = false

	hand_prev_btn = _build_hand_page_button("‹", "浏览上一组手牌", Vector2(hand_x0, top + 68.0), -1)
	hand_next_btn = _build_hand_page_button("›", "浏览下一组手牌", Vector2(hand_x1 - HAND_BROWSE_BUTTON_W, top + 68.0), 1)
	# 离手牌在底板上方经过，座位始终绘制在飞牌前。
	move_child(hand_dock, pz_flight_layer.get_index())
	# 手牌的裁剪区域含上浮空间，重叠处的点击优先交给出牌/响应按钮。
	for control in [hand_viewport, hand_prev_btn, hand_next_btn]:
		move_child(control, prompt_panel.get_index())
	drag_line = Line2D.new()
	drag_line.width = 4.0
	drag_line.z_index = 19
	drag_line.visible = false
	add_child(drag_line)
	drag_hint = lbl("", 26, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
	drag_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drag_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	drag_hint.clip_text = true
	drag_hint.position = Vector2(hand_x0, top - 103.0)
	drag_hint.size = Vector2(width, 54.0)
	drag_hint.mouse_filter = MOUSE_FILTER_IGNORE
	drag_hint.z_index = 21
	drag_hint.add_theme_stylebox_override("normal", _tight(style(_table_surface, 16, _table_edge, 1), 12, 4))
	drag_hint.visible = false
	add_child(drag_hint)


func _build_hand_page_button(text: String, help: String, pos: Vector2, direction: int) -> Button:
	var button := plain_btn(text, _table_inset, _table_text, 44)
	button.position = pos
	button.size = Vector2(HAND_BROWSE_BUTTON_W - 8.0, 138.0)
	button.tooltip_text = help
	button.visible = false
	button.pressed.connect(func() -> void: _scroll_hand_page(direction))
	add_child(button)
	table_nodes.append(button)
	return button


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
	_make_press_feedback(wrap, 14)
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
	chip.add_theme_stylebox_override("panel", style(Color(1, 0.98, 0.95, 0.95), int(10 * k), C_GOLD, 1))
	cb.add_child(chip)
	var top := lbl("%s%s" % [Art.suit_sym(String(c.get("suit", ""))), Art.point_str(int(c.get("point", 0)))], int(24 * k), Art.RED_SUIT if red else Art.BLACK_SUIT, true, HORIZONTAL_ALIGNMENT_CENTER)
	top.name = "Top"
	top.position = Vector2(0, -1) * k
	top.size = chip.size
	top.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.mouse_filter = MOUSE_FILTER_IGNORE
	chip.add_child(top)
	# 底部牌名条（类型色底 + 手杀式顶部鎏金分割线）
	var plate := Panel.new()
	plate.position = Vector2(4, 176) * k
	plate.size = Vector2(164, 88) * k
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", style(fc.darkened(0.08), int(10 * k), Color(1.0, 0.86, 0.52, 0.65), 1))
	cb.add_child(plate)
	var gbar := ColorRect.new()
	gbar.color = Color(0.96, 0.78, 0.38, 0.92)
	gbar.position = Vector2(8, 174) * k
	gbar.size = Vector2(156, maxf(2.0, 2.5 * k))
	gbar.mouse_filter = MOUSE_FILTER_IGNORE
	cb.add_child(gbar)
	var nm := lbl(nm_text, int((28 if nm_text.length() <= 4 else 23) * k), C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	nm.add_theme_color_override("font_outline_color", Color(0.18, 0.06, 0.16, 0.88))
	nm.add_theme_constant_override("outline_size", maxi(2, int(3 * k)))
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
	b.clip_text = true
	b.custom_minimum_size = Vector2(188, 64)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 28)
	var edge := Palette.ROSE_EDGE if bg == C_TABLE_ACTION else _table_edge
	_set_btn_theme(b, bg, edge, fg, 19, 1, false, Vector2i(14, 10), Palette.ROSE_EDGE)
	_wire_btn_bounce(b)
	b.pressed.connect(func() -> void: play_sfx("click"))
	return b


func _size_table_action(button: Button) -> void:
	var width := floorf((prompt_action_width - TABLE_ACTION_GAP * 3.0) / 4.0)
	button.custom_minimum_size = Vector2(width, TABLE_ACTION_H)
	button.add_theme_font_size_override("font_size", clampi(floori((width - 24.0) / 4.6), 16, 27))


func _place_table_action(button: Button, slot: int) -> void:
	_size_table_action(button)
	button.position.x = (button.custom_minimum_size.x + TABLE_ACTION_GAP) * slot
	button.size = button.custom_minimum_size
	action_bar.add_child(button)


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
	return deck_label.position + deck_label.size * 0.5


func _sync_hand() -> void:
	if hand_row == null or players.is_empty():
		return
	var hand: Array = players[0]["hand"]
	if not _hand_order_matches(hand):
		_reconcile_hand(hand)
	# 数量和顺序不变时，响应/弃牌/技能的选择状态仍可能变化。
	if not discard_sel.is_empty():
		discard_sel = discard_sel.filter(func(c: Dictionary) -> bool: return _hand_has(c))
	if not spear_cards.is_empty():
		spear_cards = spear_cards.filter(func(c: Dictionary) -> bool: return _hand_has(c))
	if not selected_card.is_empty() and not _hand_has(selected_card):
		selected_card = {}
		sel_target = -1
		if not spear_targeting and not muniu_targeting:
			targeting = false
			target_candidates = []
	for w in hand_cards:
		_apply_card_state(w)
	_layout_hand(true)


func _hand_order_matches(hand: Array) -> bool:
	if hand.size() != hand_cards.size():
		return false
	for i in hand.size():
		var w: Variant = hand_cards[i]
		if not is_instance_valid(w) or not is_same(w.get_meta("card"), hand[i]):
			return false
	return true


func _reconcile_hand(hand: Array) -> void:
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
			if drag_press.get("wrap") == w:
				_clear_press_feedback()
				drag_press.clear()
				hand_cancel_release = true
				if IntroPop.inst != null:
					IntroPop.inst.cancel_longpress()
			w.get_parent().remove_child(w)
			w.queue_free()  # V0.24 闪退修复：不得立即 free
	hand_cards = keep
	var ordered: Array = []
	for h in hand:
		var w := _find_wrap(h)
		if w == null:
			w = make_hand_card(h)
			hand_row.add_child(w)
			w.global_position = global_position + _deck_point() - Vector2(CARD_W * 0.5, 0)
			w.scale = Vector2(0.5, 0.5)
			w.modulate.a = 0.0
			w.set_meta("fresh", true)
		ordered.append(w)
	hand_cards = ordered
	var child_index := 0
	for w: Control in ordered:
		if w.get_parent() != hand_row:
			continue
		if w.get_index() != child_index:
			hand_row.move_child(w, child_index)
		child_index += 1


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
	if not is_instance_valid(hand_row) or not is_instance_valid(hand_viewport):
		return
	var width := hand_x1 - hand_x0
	var browsable := n > 1 and CARD_W + (CARD_W - 18.0) * float(n - 1) > width
	var inset := HAND_BROWSE_BUTTON_W if browsable else 0.0
	var avail := width - 2.0 * inset
	hand_viewport.position.x = hand_x0 + inset
	hand_viewport.size.x = avail
	var step := CARD_W + HAND_CARD_GAP
	if not browsable and n > 1:
		step = minf(step, (avail - CARD_W) / float(n - 1))
	var total := CARD_W + step * float(maxi(n - 1, 0))
	hand_row.size.x = maxf(avail, total)
	hand_scroll_limit = maxf(total - avail, 0.0) if browsable else 0.0
	hand_prev_btn.visible = browsable
	hand_next_btn.visible = browsable
	_set_hand_scroll(hand_scroll_offset)
	if n == 0:
		return
	var x0 := maxf((avail - total) * 0.5, 0.0)
	var mid := float(n - 1) * 0.5
	var ang := 0.0 if browsable or mid <= 0.0 else minf(1.2, 7.0 / mid)
	var dip := 0.0 if browsable or mid <= 0.0 else 14.0 / (mid * mid)
	for i in n:
		var w: Control = hand_cards[i]
		if w == drag_wrap:
			continue
		var off := float(i) - mid
		var y := 8.0 + off * off * dip
		if _is_lifted(w):
			y -= LIFT
		_tween_card(w, Vector2(x0 + step * float(i), y), deg_to_rad(off * ang), animate)


func _hand_point(height: float) -> Vector2:
	if not is_instance_valid(hand_viewport):
		return seat_center(0)
	return hand_viewport.position + Vector2(hand_viewport.size.x * 0.5, height + LIFT + 10.0)


func _set_hand_scroll(offset: float) -> void:
	hand_scroll_offset = clampf(offset, 0.0, hand_scroll_limit)
	hand_row.position.x = -hand_scroll_offset
	hand_prev_btn.disabled = is_zero_approx(hand_scroll_offset)
	hand_next_btn.disabled = is_equal_approx(hand_scroll_offset, hand_scroll_limit)


func _scroll_hand_page(direction: int) -> void:
	if hand_scroll_limit <= 0.0:
		return
	var step := CARD_W + HAND_CARD_GAP
	var visible_cards := maxi(1, floori((hand_viewport.size.x + HAND_CARD_GAP) / step))
	_set_hand_scroll(hand_scroll_offset + float(visible_cards * direction) * step)


func _ensure_hand_card_visible(w: Control) -> void:
	if hand_scroll_limit <= 0.0 or not is_instance_valid(w) or w.get_parent() != hand_row:
		return
	var x := w.position.x
	if x < hand_scroll_offset:
		_set_hand_scroll(x)
	elif x + CARD_W > hand_scroll_offset + hand_viewport.size.x:
		_set_hand_scroll(x + CARD_W - hand_viewport.size.x)


func _on_hand_viewport_gui_input(event: InputEvent) -> void:
	if hand_scroll_limit <= 0.0 or not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
			_set_hand_scroll(hand_scroll_offset - (CARD_W + HAND_CARD_GAP))
			hand_viewport.accept_event()
		MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
			_set_hand_scroll(hand_scroll_offset + CARD_W + HAND_CARD_GAP)
			hand_viewport.accept_event()
		MOUSE_BUTTON_LEFT:
			_begin_hand_press(null, mb.global_position)


func _tween_card(w: Control, pos: Vector2, rot: float, animate: bool) -> void:
	var key := "%d,%d,%d" % [int(pos.x), int(pos.y), int(rad_to_deg(rot) * 10.0)]
	var fresh := bool(w.get_meta("fresh", false))
	var returning := w.has_meta("returning")
	if animate and String(w.get_meta("lay", "")) == key and not fresh:
		return
	w.set_meta("lay", key)
	var old: Variant = (w.get_meta("tw") if w.has_meta("tw") else null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var spring := bool(w.get_meta("spring", false))
	w.set_meta("spring", false)
	if not animate or fast or auto_all or reduced_motion or not is_inside_tree():
		if returning:
			_finish_hand_return(w, pos)
		w.position = pos
		w.rotation = rot
		w.scale = Vector2.ONE
		w.modulate.a = 1.0
		w.set_meta("fresh", false)
		return
	var tw := w.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var dur := HAND_RETURN_TIME if spring or returning else (HAND_DRAW_TIME if fresh else HAND_SETTLE_TIME)
	if returning:
		# 回落期间借用桌面层，目的地始终跟随手牌行的滚动。
		var start := hand_row.get_global_transform().affine_inverse() * (get_global_transform() * w.position)
		var move_card := func(p: Vector2) -> void:
			w.position = get_global_transform().affine_inverse() * (hand_row.get_global_transform() * p)
		tw.tween_method(move_card, start, pos, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(w, "position", pos, dur)
	tw.tween_property(w, "rotation", rot, dur)
	tw.tween_property(w, "scale", Vector2.ONE, dur)
	w.set_meta("fresh", false)
	if w.modulate.a < 1.0:
		tw.tween_property(w, "modulate:a", 1.0, dur)
	if returning:
		tw.chain().tween_callback(_finish_hand_return.bind(w, pos))
	w.set_meta("tw", tw)


func _dock_hand_card(w: Control) -> void:
	if not is_instance_valid(hand_row) or w.get_parent() == hand_row:
		return
	w.reparent(hand_row, true)
	var child_index := 0
	for card: Control in hand_cards:
		if card == w:
			break
		if card.get_parent() == hand_row:
			child_index += 1
	hand_row.move_child(w, child_index)


func _finish_hand_return(w: Control, pos: Vector2) -> void:
	if not hand_cards.has(w):
		return
	_dock_hand_card(w)
	w.position = pos
	w.z_index = 0
	w.remove_meta("returning")
	(w.get_child(0) as Control).mouse_filter = MOUSE_FILTER_STOP
	w.set_meta("intro", Callable(self, "_intro_card").bind(w.get_meta("card")))


func _respond_card_ok(c: Dictionary) -> bool:
	var nm := String(c.get("name", ""))
	if not respond_names.is_empty():
		return respond_names.has(nm)
	return respond_name != "" and nm == respond_name


func _card_state_key(c: Dictionary) -> String:
	if discard_mode:
		return "d"
	if muniu_storing and not asking:
		return "r1"
	if spear_targeting and not asking:
		return "r1"
	if not pick_cards.is_empty():
		for pc in pick_cards:
			if is_same(pc, c):
				return "r1"
		return "r0"
	if respond_name != "" or not respond_names.is_empty():
		return "r1" if _respond_card_ok(c) else "r0"
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
	if w == null or fast or auto_all or reduced_motion:
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
	if skill_mode != "" or spear_targeting or muniu_targeting or muniu_storing or players.is_empty():
		return false
	var c: Dictionary = w.get_meta("card")
	return _hand_has(c) and card_usable(players[0], c)


func _on_card_gui_input(w: Control, event: InputEvent) -> void:
	if not is_instance_valid(w):
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_begin_hand_press(w, mb.global_position)
		else:
			_release_hand_press(mb.global_position)
	elif event is InputEventMouseMotion:
		_move_hand_press((event as InputEventMouseMotion).global_position)


func _input(event: InputEvent) -> void:
	# GUI 焦点可能在拖出的牌转到桌面层时变化，按下之后由同一套手势接管释放。
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			_clear_press_feedback()
			_release_hand_press(mb.position)
		elif hand_cancel_release:
			hand_cancel_release = false
	elif event is InputEventMouseMotion and not drag_press.is_empty():
		_move_hand_press((event as InputEventMouseMotion).position)


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT and what != NOTIFICATION_APPLICATION_PAUSED:
		return
	_interrupt_press_feedback()
	if drag_press.is_empty():
		return
	hand_cancel_release = true
	drag_press.clear()
	if IntroPop.inst != null:
		IntroPop.inst.cancel_longpress()
	if drag_wrap != null:
		_restore_drag_selection(false)


func _hand_accepts_press() -> bool:
	return not game_over and (asking or discard_mode or (interactive and in_play_phase and turn_seat == 0))


func _begin_hand_press(w: Control, gp: Vector2) -> void:
	if _lp_swallowing():
		return
	if is_instance_valid(drag_wrap):
		_restore_drag_selection()
	drag_end_ms = 0
	hand_cancel_release = false
	var grip := Vector2.ZERO if w == null else gp - w.global_position
	drag_press = {
		"wrap": w, "pos": gp, "offset": grip, "latest": gp,
		"scroll": hand_scroll_offset, "gesture": "pending",
	}
	if is_instance_valid(w) and _hand_accepts_press():
		_show_press_feedback(w.get_node("PressFeedback") as Panel, w.get_child(0) as Button)


func _move_hand_press(gp: Vector2) -> void:
	if drag_press.is_empty() or _lp_swallowing() or gp == drag_press["latest"]:
		return
	drag_press["latest"] = gp
	var movement := gp - Vector2(drag_press["pos"])
	if drag_press["gesture"] == "pending" and movement.length() >= DRAG_START_PX:
		_clear_press_feedback()
		if IntroPop.inst != null:
			IntroPop.inst.cancel_longpress()
		var pressed_card: Variant = drag_press["wrap"]
		if hand_scroll_limit > 0.0 and absf(movement.x) >= absf(movement.y) * 1.6:
			drag_press["gesture"] = "browse"
		elif movement.y < -DRAG_START_PX * 0.45 and is_instance_valid(pressed_card) and _can_drag(pressed_card):
			drag_press["gesture"] = "drag"
			_drag_begin(pressed_card)
		else:
			drag_press["gesture"] = "moved"
	match drag_press["gesture"]:
		"browse":
			_set_hand_scroll(float(drag_press["scroll"]) - movement.x)
		"drag":
			_drag_move(gp)


func _release_hand_press(gp: Vector2) -> void:
	if hand_cancel_release:
		hand_cancel_release = false
		drag_end_ms = Time.get_ticks_msec()
	if drag_press.is_empty():
		return
	_clear_press_feedback()
	if drag_press["gesture"] != "pending" or _lp_swallowing():
		drag_end_ms = Time.get_ticks_msec()
	if is_instance_valid(drag_wrap):
		_drag_finish(gp)
	drag_press.clear()


func _drag_begin(w: Control) -> void:
	var c: Dictionary = w.get_meta("card")
	drag_previous = {
		"card": selected_card, "target": sel_target, "extra": extra_target,
		"candidates": target_candidates, "targeting": targeting,
	}
	if selected_card.is_empty() or not is_same(selected_card, c):
		_select_card(c, false)  # 拖拽开始时的选中不触发自动确认（松手位置才决定出不出）
		if selected_card.is_empty() or not is_same(selected_card, c):
			return
	drag_wrap = w
	var old: Variant = (w.get_meta("tw") if w.has_meta("tw") else null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	# 真正拖出的牌退出裁剪区域，横览始终留在原手牌层。
	w.reparent(self, true)
	w.rotation = 0.0
	w.scale = Vector2(1.035, 1.035)
	w.modulate.a = 1.0
	w.z_index = 20
	drag_hover_seat = -1
	if drag_line != null:
		drag_line.visible = true
		drag_line.clear_points()
	drag_hint.visible = true
	_apply_seat_frames()


func _drag_target_at(gp: Vector2) -> int:
	var point := get_global_transform_with_canvas().affine_inverse() * gp
	var retained := -1
	var closest := -1
	var best_distance := INF
	for i in players.size():
		var panel := seat_panel_of(i)
		if panel == null or not panel.is_visible_in_tree():
			continue
		# 以原始座位边界为准，预览时的放大不会改变吸附范围。
		var rect := Rect2(panel.position, panel.size)
		var legal := target_candidates.has(i) and bool(players[i]["alive"])
		if rect.has_point(point):
			return i if legal else -1
		if not legal:
			continue
		if i == drag_hover_seat and rect.grow(SNAP_RELEASE_PX).has_point(point):
			retained = i
		if rect.grow(SNAP_PX).has_point(point):
			var distance := rect.get_center().distance_squared_to(point)
			if distance < best_distance:
				closest = i
				best_distance = distance
	return retained if retained >= 0 else closest


func _drag_move(gp: Vector2) -> void:
	var w := drag_wrap
	if w == null or not is_instance_valid(w):
		return
	var c: Dictionary = w.get_meta("card")
	var table_xf := get_global_transform_with_canvas()
	var table_inv := table_xf.affine_inverse()
	var pos := table_inv * (gp - Vector2(drag_press.get("offset", w.size * 0.5)))
	var scale_factor := 1.035
	var needs_target := card_needs_target(c)
	var hover := _drag_target_at(gp) if needs_target else -1
	if hover >= 0:
		# 吸附预览停在靠近目标的桌内一侧，留出肖像、血量及目标提示。
		var pad := minf(16.0, minf(play_area.size.x, play_area.size.y) * 0.25)
		var preview_area := play_area.grow(-pad)
		scale_factor = minf(0.70, minf(preview_area.size.x / w.size.x, preview_area.size.y / w.size.y))
		var preview_size := w.size * scale_factor
		pos = (seat_center(hover) - preview_size * 0.5).clamp(preview_area.position, preview_area.end - preview_size)
	drag_pose = Vector3(pos.x, pos.y, scale_factor)
	if hover != drag_hover_seat:
		drag_hover_seat = hover
		sel_target = hover if hover >= 0 else (target_candidates[0] if target_candidates.size() == 1 else -1)
		_transition_drag_pose(hover >= 0)
		_apply_seat_frames()
		_update_action_bar()
	_draw_drag_pose(drag_pose_offset)
	if drag_line != null:
		var a := _hand_point(40)
		var b := pos + w.size * Vector2(0.5, 0.35) * scale_factor
		if hover >= 0:
			var panel := seat_panel_of(hover)
			var bounds := Rect2(panel.position, panel.size).grow(12)
			b = b.clamp(bounds.position, bounds.end)
		drag_line.points = PackedVector2Array([a, b])
		var release_ok := hover >= 0 or (not needs_target and gp.y < hand_row.global_position.y - 30.0)
		drag_line.default_color = Color(0.45, 1.0, 0.55, 0.95) if release_ok else Color(1.0, 0.85, 0.45, 0.8)
	var card_name := String(c["name"])
	if hover >= 0:
		drag_hint.text = "松手对 %s 使用【%s】" % [String(players[hover]["char_name"]), card_name]
	elif not needs_target:
		drag_hint.text = "松手选中【%s】，随后出牌" % card_name if gp.y < hand_row.global_position.y - 30.0 else "向上拖出后松手选中"
	else:
		drag_hint.text = "拖到可选角色出牌，松手可取消"


func _transition_drag_pose(snapping: bool) -> void:
	_stop_drag_pose()
	if not _motion_enabled():
		return
	var scale_factor := drag_wrap.scale.x
	var drawn := drag_wrap.position + drag_wrap.pivot_offset * (1.0 - scale_factor)
	# 松开吸附后，位置继续跟随手指，余量在短时间内消失。
	drag_pose_offset = Vector3(drawn.x, drawn.y, scale_factor) - drag_pose
	var duration := DRAG_SNAP_TIME if snapping else DRAG_DETACH_TIME
	drag_pose_tween = drag_wrap.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	drag_pose_tween.tween_method(_draw_drag_pose, drag_pose_offset, Vector3.ZERO, duration)


func _draw_drag_pose(offset: Vector3) -> void:
	if not is_instance_valid(drag_wrap):
		return
	drag_pose_offset = offset
	var pose := drag_pose + offset
	drag_wrap.scale = Vector2.ONE * pose.z
	drag_wrap.position = Vector2(pose.x, pose.y) - drag_wrap.pivot_offset * (1.0 - pose.z)


func _stop_drag_pose() -> void:
	if drag_pose_tween != null and drag_pose_tween.is_valid():
		drag_pose_tween.kill()
	drag_pose_tween = null
	drag_pose_offset = Vector3.ZERO


func _drag_finish(gp: Vector2) -> void:
	var w := drag_wrap
	if w == null:
		return
	var c: Dictionary = w.get_meta("card")
	if not _can_drag(w):
		_restore_drag_selection()
		return
	if card_needs_target(c):
		var hover := _drag_target_at(gp)
		if hover >= 0:
			var origin := _hand_flight_origin(w)
			_drag_reset()
			# 等 GUI 松手完成再消耗牌，避免手牌节点在触摸释放分发中离树。
			_play_selected.call_deferred(c, hover, -2, origin)
			return
	elif gp.y < hand_row.global_position.y - 30.0:
		# 无目标牌进入普通确认流程。
		_drag_reset()
		_layout_hand(true)
		_show_sel_hint()
		_maybe_auto_confirm()
		return
	_restore_drag_selection()


func _restore_drag_selection(animate_return: bool = true) -> void:
	var previous := drag_previous
	_drag_reset(animate_return)
	if not interactive or game_over or asking:
		_layout_hand(true)
		return
	var card: Dictionary = previous.get("card", {})
	if card.is_empty() or not _hand_has(card):
		cancel_targeting()
		return
	selected_card = card
	sel_target = int(previous["target"])
	extra_target = int(previous["extra"])
	target_candidates = previous["candidates"]
	targeting = bool(previous["targeting"])
	_show_sel_hint()
	refresh()


func _drag_reset(animate_return: bool = false) -> void:
	_stop_drag_pose()
	if is_instance_valid(drag_wrap):
		if animate_return and not fast and not auto_all and not reduced_motion:
			drag_wrap.set_meta("returning", true)
			drag_wrap.remove_meta("intro")
			(drag_wrap.get_child(0) as Control).mouse_filter = MOUSE_FILTER_IGNORE
			drag_wrap.z_index = 19
		else:
			_dock_hand_card(drag_wrap)
			drag_wrap.z_index = 0
		drag_wrap.set_meta("lay", "")
		drag_wrap.set_meta("spring", true)
	drag_wrap = null
	drag_previous = {}
	drag_hover_seat = -1
	if is_instance_valid(drag_line):
		drag_line.visible = false
	if is_instance_valid(drag_hint):
		drag_hint.visible = false
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
	play_sfx("select")
	_queue_refresh()
	if allow_auto:
		_maybe_auto_confirm()


func _play_selected(card: Dictionary, tgt_seat: int, extra: int = -1, drag_origin: Dictionary = {}) -> void:
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
	fly_from_hand = drag_origin if not drag_origin.is_empty() else _hand_flight_origin(_find_wrap(card))
	if not fly_from_hand.is_empty():
		fly_from_hand["card"] = card
	targeting = false
	selected_card = {}
	target_candidates = []
	sel_target = -1
	extra_target = -1
	hide_prompt()
	interactive = false
	_apply_seat_frames()
	_update_action_bar()
	_queue_refresh()
	# 羁绊锁链：已在出牌前点选了第二个目标（或确认只连一人）时，引擎随后的「第二个目标」询问直接用这个选择
	pre_answers = []
	if String(card["name"]) == "羁绊锁链" and extra != -2:
		pre_answers.append({"kind": "chain2", "value": players[extra] if extra >= 0 and extra < players.size() else {}})
	if card_kind(card) in ["武器", "防具", "饰品", "宝物"]:
		await eng.play_equip(me, card)
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
	if muniu_storing:
		_commit_muniu_store()
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
	if not selected_card.is_empty() or targeting or skill_mode != "" or muniu_storing:
		targeting = false
		spear_targeting = false
		spear_cards = []
		muniu_targeting = false
		muniu_storing = false
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
	var show_bar := interactive and in_play_phase and turn_seat == 0 and not asking and not game_over and not discard_mode
	var selecting := show_bar and (not selected_card.is_empty() or targeting or skill_mode != "" or spear_targeting or muniu_targeting or muniu_storing)
	action_bar.visible = show_bar
	confirm_btn.visible = selecting
	cancel_btn.visible = selecting
	cancel_btn.disabled = not selecting
	end_play_btn.disabled = not show_bar
	confirm_btn.disabled = not selecting or not _can_confirm()
	if selecting:
		confirm_btn.text = _primary_action_label()
		confirm_btn.tooltip_text = _confirm_disabled_hint() if confirm_btn.disabled else ""
	if not show_bar:
		recast_btn.hide()
		return
	var can_recast: bool = selecting and skill_mode == "" and not spear_targeting and not muniu_targeting and not muniu_storing and not selected_card.is_empty() and eng != null and eng.can_recast(selected_card) and _hand_has(selected_card)
	recast_btn.visible = can_recast


func _primary_action_label() -> String:
	if skill_mode != "":
		return "发动技能"
	if muniu_storing:
		return "存入木牛"
	if muniu_targeting:
		return "转交木牛"
	if not selected_card.is_empty() and card_kind(selected_card) in ["武器", "防具", "饰品", "宝物"]:
		return "装备"
	return "出牌"


func _confirm_disabled_hint() -> String:
	if not interactive:
		return "正在结算，稍候即可出牌"
	if not selected_card.is_empty() and skill_mode == "" and not spear_targeting and not muniu_targeting and not muniu_storing and not players.is_empty():
		var reason := unusable_reason(players[0], selected_card)
		if reason != "":
			return reason
	var selection := _sel_hint_text()
	return selection if selection != "" else "先选择一张可用手牌"


func _apply_seat_frames() -> void:
	# 拖拽悬停只刷新描边和提示，头像位置及大小保持固定。
	for panel in seat_panels:
		var s := int(panel.get_meta("seat"))
		if s < players.size():
			_sync_seat_frame(panel, s, bool(players[s]["alive"]))
	if me_panel_ref != null and not players.is_empty():
		_sync_seat_frame(me_panel_ref, 0, bool(players[0]["alive"]))


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
	play_sfx("select")
	_update_discard_ui()
	_queue_refresh()


func _auto_select_discard_cards() -> void:
	if not discard_mode or players.is_empty() or eng == null:
		return
	var me: Dictionary = players[0]
	var sim_hand: Array = (me["hand"] as Array).duplicate()
	var chosen: Array = []
	var need_n := mini(discard_need, sim_hand.size())
	var fake := me.duplicate()
	for _i in need_n:
		fake["hand"] = sim_hand
		var c: Dictionary = eng.ai_pick_discard(fake)
		if c.is_empty():
			break
		chosen.append(c)
		sim_hand.erase(c)
	discard_sel = chosen
	play_sfx("select")
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
var _countdown_seconds := -1
var _countdown_warning := false


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
	# 等候选项和可响应手牌完成这一帧的展示后再开始计时。
	await get_tree().process_frame
	if ask_seq != seq or not asking or not is_visible_in_tree() or ask_timeout <= 0.0 or auto_all:
		return
	ask_deadline_ms = Time.get_ticks_msec() + roundi(1000.0 * ask_timeout)
	ask_bar_bg_ref.visible = true
	ask_secs_label.visible = true
	prompt_header.visible = true
	_countdown_tick(ask_timeout)


func _countdown_tick(v: float) -> void:
	if ask_bar_fill == null:
		return
	ask_bar_fill.scale.x = clampf(v / maxf(ask_timeout, 0.01), 0.0, 1.0)
	var warning := v < 5.0
	if _countdown_seconds < 0 or warning != _countdown_warning:
		_countdown_warning = warning
		ask_bar_fill.color = C_TABLE_ACTION if warning else Color("#739fca")
	var seconds := ceili(v)
	if ask_secs_label == null or seconds == _countdown_seconds:
		return
	_countdown_seconds = seconds
	var countdown := "剩余 %d 秒" % seconds
	if ask_default_caption != "" and ask_default_caption.length() <= 8:
		countdown += " · 超时%s" % ask_default_caption
	ask_secs_label.text = countdown


# ================= V0.25 处理区与结算动画 =================
# 对照无名杀 player.$throw（牌飞入处理区）、$draw（牌堆飞入）、$judge / $phaseJudge（判定牌）、$equip、$addVirtualJudge。
# 处理区节点池复用（最多 PZ_MAX 张同时显示），空闲 PZ_IDLE 秒后整体淡出飞向弃牌堆。
const FX_CAP := 36
const CARD_FLY_TIME := 0.23
const PLAYED_CARD_SLIDE := 0.46
const PLAYED_CARD_HOLD := 0.20
const PZ_W := 140.0
const PZ_H := CARD_H * PZ_W / CARD_W
const PZ_CAP_EXTENT := 42.0
const PZ_CAP_MARGIN := 6.0
const PZ_SPACING := 18.0
const PZ_EDGE_PAD := 12.0
const PZ_MAX := 4
const PZ_IDLE := 2.5
var play_area := Rect2(610, 120, 700, 350)
var pz_clip: Control = null
var pz_flight_layer: Control = null
var pz_pool: Array = []      # 复用的处理区牌节点
var pz_live: Array = []      # 当前显示中的（按时间顺序）
var pz_clear_tw: Tween = null
var pz_layer: Control = null
var nullify_count := 0


func _build_play_notice() -> void:
	play_callout_panel = PanelContainer.new()
	play_callout_panel.name = "BattleActionNotice"
	play_callout_panel.custom_minimum_size.y = 86.0
	play_callout_panel.mouse_filter = MOUSE_FILTER_IGNORE
	play_callout_panel.add_theme_stylebox_override("panel", _tight(style(Color("#322338"), 17, Color("#98778f"), 2), 16, 4))
	var lines := VBoxContainer.new()
	lines.mouse_filter = MOUSE_FILTER_IGNORE
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 1)
	play_callout_panel.add_child(lines)
	play_callout_label = lbl("", 32, Color("#fff9fb"), true, HORIZONTAL_ALIGNMENT_CENTER)
	play_callout_label.name = "ActionSource"
	play_result_label = lbl("", 28, Color("#ffe5ab"), true, HORIZONTAL_ALIGNMENT_CENTER)
	play_result_label.name = "ActionResult"
	for line in [play_callout_label, play_result_label]:
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.clip_text = true
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.mouse_filter = MOUSE_FILTER_IGNORE
		lines.add_child(line)
	play_callout_panel.hide()
	add_child(play_callout_panel)


func _build_skill_notice(side_y: float) -> void:
	# 使用头像与工具之间的空白，技能不会盖住中央的牌或响应窗口。
	var left := safe_insets.x + 26.0
	var width := clampf(play_area.position.x - left - 276.0, 148.0, 406.0)
	var height := 88.0
	skill_notice_panel = PanelContainer.new()
	skill_notice_panel.name = "BattleSkillNotice"
	skill_notice_panel.mouse_filter = MOUSE_FILTER_IGNORE
	skill_notice_panel.custom_minimum_size = Vector2(width, height)
	skill_notice_panel.size = skill_notice_panel.custom_minimum_size
	skill_notice_panel.position = Vector2(left, minf(safe_insets.y + table_hud_height + 12.0, side_y - height - 6.0))
	skill_notice_panel.add_theme_stylebox_override("panel", _tight(style(Color("#2d243d"), 17, Color("#b498c9"), 2), 14, 4))
	var lines := VBoxContainer.new()
	lines.mouse_filter = MOUSE_FILTER_IGNORE
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 1)
	skill_notice_panel.add_child(lines)
	skill_notice_actor = lbl("", 24, Color("#f4e9ff"), true, HORIZONTAL_ALIGNMENT_CENTER)
	skill_notice_actor.name = "SkillActor"
	skill_notice_title = lbl("", 30, Color("#ffdda3"), true, HORIZONTAL_ALIGNMENT_CENTER)
	skill_notice_title.name = "SkillTitle"
	for line in [skill_notice_actor, skill_notice_title]:
		line.mouse_filter = MOUSE_FILTER_IGNORE
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.clip_text = true
		lines.add_child(line)
	skill_notice_panel.hide()
	add_child(skill_notice_panel)


func _table_play_area(prompt_top: float, notice_height: float) -> Rect2:
	var safe_width := vw - safe_insets.x - safe_insets.z
	# 两侧为座位留出两列肖像、边距和间隔，上下避开阶段栏、出牌播报和操作提问。
	var width := clampf(safe_width - 1120.0, 1.0, 700.0)
	var top := safe_insets.y + table_hud_height + 16.0
	var bottom := prompt_top - notice_height - 18.0
	return Rect2(safe_insets.x + (safe_width - width) * 0.5, top, width, maxf(bottom - top, 1.0))


func _pz_fit_scale() -> float:
	var full_width := float(PZ_MAX) * PZ_W + float(PZ_MAX - 1) * PZ_SPACING + PZ_CAP_MARGIN * 2.0
	var width_fit := maxf(play_area.size.x - PZ_EDGE_PAD * 2.0, 1.0) / full_width
	var height_fit := maxf(play_area.size.y - PZ_EDGE_PAD * 2.0, 1.0) / (PZ_H + PZ_CAP_EXTENT)
	return minf(1.0, minf(width_fit, height_fit))


func _pz_center() -> Vector2:
	# 视觉中心包括牌下的来源标签，卡面中心略向上。
	return play_area.get_center() - Vector2(0.0, PZ_CAP_EXTENT * 0.5 * _pz_fit_scale())


func _pz_launch_point(from_pos: Vector2, launch_scale: float) -> Vector2:
	var half_width := (PZ_W * 0.5 + PZ_CAP_MARGIN) * launch_scale + PZ_EDGE_PAD
	var half_height := PZ_H * 0.5 * launch_scale + PZ_EDGE_PAD
	var start := play_area.position + Vector2(half_width, half_height)
	var end := play_area.end - Vector2(half_width, half_height + PZ_CAP_EXTENT * launch_scale)
	return from_pos.clamp(start, end.max(start))


func _pz_make() -> Control:
	var root := Control.new()
	root.size = Vector2(PZ_W, PZ_H + PZ_CAP_EXTENT)
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
	cap_bg.position = Vector2(-PZ_CAP_MARGIN, PZ_H + 6)
	cap_bg.size = Vector2(PZ_W + PZ_CAP_MARGIN * 2.0, 36)
	cap_bg.mouse_filter = MOUSE_FILTER_IGNORE
	cap_bg.add_theme_stylebox_override("panel", style(_table_surface, 16, _table_edge, 1, true))
	root.add_child(cap_bg)
	var cap := lbl("", 19, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
	cap.name = "Cap"
	cap.position = Vector2(2, PZ_H + 10)
	cap.size = Vector2(PZ_W - 4, 28)
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.clip_text = true
	cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	var cap := n.get_node("Cap") as Label
	cap.text = caption
	cap.visible = caption != ""
	(n.get_node("CapBg") as Control).visible = caption != ""
	(n.get_node("Back") as Control).visible = false
	(n.get_node("Face") as Control).visible = true
	var stamp := n.get_node("Stamp") as Label
	stamp.text = ""
	stamp.visible = false
	n.modulate = Color(1, 1, 1, 1)


func _pz_slot(i: int, cnt: int) -> Vector2:
	var step := (PZ_W + PZ_SPACING) * _pz_fit_scale()
	var center := _pz_center() + Vector2((float(i) - float(cnt - 1) * 0.5) * step, 0.0)
	return center - Vector2(PZ_W, PZ_H) * 0.5


func _pz_relayout() -> void:
	var cnt := pz_live.size()
	for i in cnt:
		var n: Control = pz_live[i]
		if n.has_meta("flying") and bool(n.get_meta("flying")):
			continue
		var dst := _pz_slot(i, cnt)
		_pz_stop_tween(n, "tw")
		if n.position.is_equal_approx(dst):
			continue
		if not _motion_enabled():
			n.position = dst
			continue
		var tw := n.create_tween()
		tw.tween_property(n, "position", dst, 0.21).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		n.set_meta("tw", tw)


func _pz_stop_tween(n: Control, key: String) -> void:
	if n.has_meta(key):
		var tween: Tween = n.get_meta(key)
		if tween.is_valid():
			tween.kill()
		n.remove_meta(key)


func _pz_clip_card(n: Control) -> void:
	if n.get_parent() != pz_layer:
		n.reparent(pz_layer, false)


func _pz_finish_motion() -> void:
	for n: Control in pz_pool:
		if not is_instance_valid(n):
			continue
		_pz_stop_tween(n, "tw")
		_pz_stop_tween(n, "reveal_tw")
		_pz_clip_card(n)
		n.set_meta("flying", false)
		var index := pz_live.find(n)
		if index < 0:
			n.hide()
			continue
		n.position = _pz_slot(index, pz_live.size())
		n.scale = Vector2.ONE * _pz_fit_scale()
		n.rotation = 0.0
		var back := n.get_node("Back") as Control
		if back.visible:
			back.hide()
			(n.get_node("Face") as Control).show()
		var stamp := n.get_node("Stamp") as Label
		stamp.scale = Vector2.ONE
		stamp.modulate.a = 1.0
		stamp.visible = stamp.text != ""


func _pz_arm_clear(landing_time: float = 0.0) -> void:
	if pz_clear_tw and pz_clear_tw.is_valid():
		pz_clear_tw.kill()
	pz_clear_tw = create_tween()
	pz_clear_tw.tween_interval(0.05 if fast else landing_time + PZ_IDLE)
	pz_clear_tw.tween_callback(func() -> void:
		if asking and not fast:
			_pz_arm_clear()
		else:
			_pz_clear())


func _pz_clear() -> void:
	# 结算完：处理区的牌缩小飞向弃牌堆并淡出
	var dst := disc_label.position + disc_label.size * 0.5
	for n in pz_live:
		if not is_instance_valid(n):
			continue
		_pz_stop_tween(n, "tw")
		_pz_stop_tween(n, "reveal_tw")
		_pz_clip_card(n)
		n.set_meta("flying", false)
		if not _motion_enabled():
			n.visible = false
			continue
		var tw: Tween = n.create_tween().set_parallel(true)
		tw.tween_property(n, "position", dst - Vector2(PZ_W, PZ_H) * 0.25, CARD_FLY_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(n, "scale", Vector2(0.25, 0.25), CARD_FLY_TIME)
		tw.tween_property(n, "modulate:a", 0.0, CARD_FLY_TIME)
		tw.chain().tween_callback(func() -> void: if is_instance_valid(n): n.visible = false)
		n.set_meta("tw", tw)
	pz_live.clear()
	_nullify_reset()


func _pz_add(card: Dictionary, caption: String, from_pos: Vector2, hand_launch: Dictionary = {}, played: bool = false) -> Control:
	if pz_layer == null or card.is_empty() or auto_all:
		return null
	var n := _pz_take()
	pz_live.erase(n)
	pz_live.append(n)
	while pz_live.size() > PZ_MAX:
		var old: Control = pz_live.pop_front()
		_pz_stop_tween(old, "tw")
		_pz_stop_tween(old, "reveal_tw")
		old.visible = false
		_pz_clip_card(old)
	_pz_stop_tween(n, "tw")
	_pz_stop_tween(n, "reveal_tw")
	_pz_clip_card(n)
	n.set_meta("flying", false)
	_pz_fill(n, card, caption)
	n.visible = true
	pz_layer.move_child(n, pz_layer.get_child_count() - 1)
	var cnt := pz_live.size()
	var dst := _pz_slot(cnt - 1, cnt)
	var settled_scale := Vector2.ONE * _pz_fit_scale()
	var fly_from_wrap := not hand_launch.is_empty()
	var travel_time := PLAYED_CARD_SLIDE if played else CARD_FLY_TIME
	if not _motion_enabled():
		n.position = dst
		n.scale = settled_scale
		n.rotation = 0.0
		if played:
			play_sfx("card")
	else:
		var origin := from_pos
		if played:
			play_sfx("card_slide")
			n.reparent(pz_flight_layer, false)
		if fly_from_wrap:
			n.scale = Vector2(hand_launch["scale"]) * Vector2(CARD_W / PZ_W, CARD_H / PZ_H)
			n.rotation = float(hand_launch["rotation"])
		elif played:
			n.scale = settled_scale * 0.82
			n.rotation = 0.0
		else:
			var launch_scale := settled_scale.x * 0.6
			origin = _pz_launch_point(from_pos, launch_scale)
			n.scale = Vector2.ONE * launch_scale
			n.rotation = rng.randf_range(-0.12, 0.12)
		n.position = origin - n.pivot_offset
		n.set_meta("flying", true)
		var tw: Tween = n.create_tween().set_parallel(true)
		var easing := Tween.EASE_IN_OUT if played else Tween.EASE_OUT
		if played:
			# 从实际手牌或座位出发，滑入处理区后停稳。
			var start := n.position
			var lift := minf(28.0, start.distance_to(dst) * 0.06)
			tw.tween_method(func(t: float) -> void:
				n.position = start.lerp(dst, t) - Vector2(0.0, 4.0 * lift * t * (1.0 - t))
			, 0.0, 1.0, travel_time).set_trans(Tween.TRANS_SINE).set_ease(easing)
		else:
			tw.tween_property(n, "position", dst, travel_time).set_trans(Tween.TRANS_SINE).set_ease(easing)
		tw.tween_property(n, "scale", settled_scale, travel_time).set_trans(Tween.TRANS_SINE).set_ease(easing)
		tw.tween_property(n, "rotation", 0.0, travel_time).set_trans(Tween.TRANS_SINE).set_ease(easing)
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(n):
				n.set_meta("flying", false)
				_pz_clip_card(n)
				if played:
					play_sfx("card")
				_pz_relayout())
		n.set_meta("tw", tw)
	_pz_relayout()
	_pz_arm_clear(travel_time if _motion_enabled() else 0.0)
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
	if not _motion_enabled():
		stamp.visible = stamp.text != ""
		return
	# 先显示牌背，翻面露出牌面，再盖结果印章
	var face := n.get_node("Face") as Control
	var back := n.get_node("Back") as Control
	face.visible = false
	back.visible = true
	var tw := n.create_tween()
	tw.tween_interval(CARD_FLY_TIME)
	tw.tween_property(n, "scale:x", _pz_fit_scale() * 0.04, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		face.visible = true
		back.visible = false)
	tw.tween_property(n, "scale:x", _pz_fit_scale(), 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if stamp.text != "":
		tw.tween_callback(func() -> void:
			stamp.visible = true
			stamp.scale = Vector2(1.17, 1.17)
			stamp.modulate.a = 0.0)
		tw.tween_property(stamp, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(stamp, "modulate:a", 1.0, 0.10)
	n.set_meta("reveal_tw", tw)


# ---------- 看破链 ----------

func _nullify_reset() -> void:
	nullify_count = 0


func _nullify_push(seat: int, negated: bool) -> void:
	if auto_all:
		return
	nullify_count += 1
	_show_play_notice("%s 响应「看破」" % _event_seat_name(seat),
		"第 %d 次看破 · %s" % [nullify_count, "锦囊失效" if negated else "锦囊恢复生效"])


# ---------- 摸牌 / 装备 / 延时锦囊 ----------

func fx_draw_fly(seat: int, n: int) -> void:
	if not _can_show_fx():
		return
	var from := _deck_point()
	var to := seat_center(seat)
	if seat == 0 and hand_row != null:
		to = _hand_point(130)
	if _motion_enabled():
		var cnt := mini(n, 3)
		var back_style := style(Color(0.36, 0.30, 0.58), 8, Color(1.0, 0.82, 0.45), 2)
		for i in cnt:
			var back := Panel.new()
			back.size = Vector2(60, 84)
			back.pivot_offset = Vector2(30, 42)
			back.position = from - Vector2(30, 42)
			back.mouse_filter = MOUSE_FILTER_IGNORE
			back.add_theme_stylebox_override("panel", back_style)
			_add_motion_fx(back)
			var tw := back.create_tween()
			tw.tween_property(back, "position", to - Vector2(30, 42) + Vector2((i - (cnt - 1) * 0.5) * 18.0, 0), CARD_FLY_TIME).set_delay(0.027 * i).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(back, "modulate:a", 0.0, 0.10)
			tw.tween_callback(back.queue_free)
	if seat != 0:
		fx_float(seat, "+%d" % n, Color(0.30, 0.55, 0.95), 40, 50.0)
	else:
		_fx_float_at(to + Vector2(0, -150), "摸 %d 张" % n, Color(0.30, 0.55, 0.95), 34)


func _fx_float_at(pos: Vector2, text: String, color: Color, fsize: int) -> void:
	if fast or not _can_show_fx():
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
	var tw := lb.create_tween()
	if _motion_enabled():
		_add_float_motion(lb, tw, 24.0)
	else:
		tw.tween_interval(0.52)
		tw.tween_property(lb, "modulate:a", 0.0, 0.18)
	tw.tween_callback(lb.queue_free)


func fx_equip_fly(seat: int, nm: String) -> void:
	if not _can_show_fx():
		return
	var pn := seat_panel_of(seat)
	if pn == null:
		return
	if not _motion_enabled():
		fx_float(seat, "装备 · " + nm, C_GOLD, 35)
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
	_add_motion_fx(chip)
	chip.position = from - Vector2(70, 18)
	var tw := chip.create_tween()
	tw.tween_property(chip, "position", to - Vector2(70, 18), CARD_FLY_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(chip, "modulate:a", 0.0, 0.18)
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
			var any_w_in_range := false
			for p in alive_players():
				if int(p["seat"]) != 0 and not (p["equip"]["weapon"] as Dictionary).is_empty():
					any_w = true
					if _jieli_has_target(p):
						any_w_in_range = true
			if not any_w:
				return "没有装备武器的目标"
			if not any_w_in_range:
				return "武器持有者的攻击范围内没有可用目标"
		"继往开来":
			var any_jw := false
			for p in alive_players():
				var s_jw := int(p["seat"])
				if not (p["hand"] as Array).is_empty() and (s_jw != 0 or (p["hand"] as Array).size() >= 2):
					any_jw = true
			if not any_jw:
				return "场上没有持有手牌的目标（对自己用需另有其他手牌）"
		"水淹七军":
			if alive_players().size() < 2:
				return "没有可使用「水淹七军」的目标"
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
				pb.custom_minimum_size = Vector2(72, 44)
				_set_btn_theme(pb, _table_inset, _table_edge, _table_text, 14, 1, true, Vector2i(12, 6))
				_wire_btn_bounce(pb)
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
			b.clip_text = true
			b.custom_minimum_size = Vector2(244, 62)
			b.add_theme_font_override("font", font_bold)
			b.add_theme_font_size_override("font_size", 21 if String(e["kind"]) == "muniu_store" else 23)
			var gloss2 := Panel.new()
			gloss2.mouse_filter = MOUSE_FILTER_IGNORE
			gloss2.set_anchors_preset(Control.PRESET_TOP_WIDE)
			gloss2.offset_left = 8
			gloss2.offset_right = -8
			gloss2.offset_top = 4
			gloss2.offset_bottom = 24
			gloss2.add_theme_stylebox_override("panel", style(Color(Palette.MILK, 0.08), 20))
			b.add_child(gloss2)
			b.set_meta("_last_dis", false)
			b.draw.connect(func() -> void:
				if bool(b.get_meta("_last_dis", false)) != b.disabled:
					b.set_meta("_last_dis", b.disabled)
					gloss2.visible = not b.disabled)
			_wire_btn_bounce(b)
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
		var col := C_TABLE_ACTION if st == "sel" else _table_inset.lerp(base, 0.18)
		var edge := Palette.ROSE_EDGE if st == "sel" else _table_edge
		var ink := C_WHITE if st == "sel" else _table_text
		_set_btn_theme(b2, col, edge, ink, 30, 2 if st == "sel" else 1, st in ["ready", "sel"], Vector2i(10, 6), Palette.ROSE_EDGE)


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
	for sk in ((me.get("char", {}) as Dictionary).get("skills", []) as Array):
		texts[String(sk.get("sid", ""))] = String(sk.get("text", ""))
	for sid in (me.get("skills", []) as Array):
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
		out.append({"key": "muniu_s", "kind": "muniu_store", "state": "sel" if muniu_storing else "ready", "text": "🌾 存粮 (选手牌)", "color": Color(0.45, 0.62, 0.35), "cb": _on_muniu_store})
		out.append({"key": "muniu_g", "kind": "muniu_give", "state": "sel" if muniu_targeting else "ready", "text": "🚚 转运木牛", "color": Color(0.45, 0.62, 0.35), "cb": _on_muniu_give})
	return out


# ---------------- 提问系统（真人点选 / AI 自动） ----------------

func _on_decided(value: Variant) -> void:
	decided.emit(value)


func maybe_restore_hint() -> void:
	if interactive and turn_seat == 0 and not game_over and in_play_phase:
		show_hint("选一张手牌出牌，或拖到可用目标。", "你的出牌阶段")


func ask(prompt: String, options: Array, on_built: Callable = Callable(), mode: String = "", presentation: Dictionary = {}) -> Variant:
	# 对局结束后不再建立询问，避免协程等待无人可答的窗口。
	if eng != null and eng.game_over:
		return null
	_set_tools_open(false)
	asking = true
	ask_seq += 1
	var my_seq := ask_seq
	hide_prompt()
	if mode == "":
		for opt in options:
			var value: Variant = (opt as Dictionary).get("value")
			if value is Dictionary and not (value as Dictionary).is_empty():
				mode = "pick"
				break
	ask_mode = mode
	ask_prompt = prompt
	ask_context = String(presentation.get("context", ""))
	if mode == "respond" and not ask_context.is_empty():
		_hide_play_notice()
	ask_confirm_text = String(presentation.get("confirm", "确认选择"))
	ask_options = options
	ask_default = _default_answer(options)
	ask_default_caption = ""
	ask_sel_has = false
	ask_sel_val = null
	ask_opt_btns = []
	ask_confirm_btn = null
	show_hint(prompt, ask_context)
	_emphasize_new_prompt()
	for option in options:
		if _ask_same(option["value"], ask_default):
			ask_default_caption = String(option["label"])
			break
	if mode == "pick" or mode == "respond":
		_build_select_ask(options)
	else:
		for index in options.size():
			var option: Dictionary = options[index]
			var label := String(option["label"])
			var value: Variant = option["value"]
			var button := _make_prompt_button(label, index == 0 and options.size() > 1)
			button.pressed.connect(func() -> void: _on_decided(value))
			_attach_option_intro(button, label, value)
			prompt_btns.add_child(button)
	if on_built.is_valid():
		on_built.call()
	_fit_prompt_btns()
	_update_action_bar()
	_queue_refresh()
	_start_countdown(my_seq)
	var result: Variant = await decided
	if ask_seq == my_seq:
		asking = false
		_ask_reset_sel()
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
	var pspec: Dictionary = {}
	if tutorial:
		game_mode = "duel"
		my_role = "先手"
		difficulty = 0
		tut_step = 0
	elif game_mode == "puzzle":
		pspec = Puzzles.by_id(puzzle_id)
		if pspec.is_empty():
			pspec = Puzzles.LIST[0]
		puzzle_id = String(pspec["id"])
		difficulty = 2
		puzzle_hint_shown = false
	match_players = Puzzles.identities(pspec).size() if game_mode == "puzzle" else (3 if game_mode == "doudizhu" else (2 if game_mode == "duel" else (4 if (game_mode == "twovtwo" or game_mode == "boss") else 5)))
	game_over = false
	_result_music_scene = ""
	_cv_seat_ms.clear()
	round_no = 1
	last_turn_seat = -1
	log_lines.clear()
	build_table()
	if fx_root != null:
		move_child(fx_root, get_child_count() - 1)
	var identities: Array
	var n := 5
	if game_mode == "puzzle":
		identities = Puzzles.identities(pspec)
		n = identities.size()
		match_players = n
	elif game_mode == "doudizhu":
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
	lord_pre_char = {}
	var pool: Array = Meta.enabled_pool(Characters.LIST)
	pool.shuffle()
	if game_mode == "identity" and String(identities[0]) != "主公":
		lord_pre_char = pool[0]
	var cand_pool: Array = []
	for c in pool:
		if lord_pre_char.is_empty() or String(c["id"]) != String(lord_pre_char.get("id", "")):
			cand_pool.append(c)
	var human_candidates: Array = cand_pool.slice(0, mini(3, cand_pool.size()))
	var human_char: Dictionary
	var seat_chars: Array = []
	if game_mode == "puzzle":
		for sd in Puzzles.seat_specs(pspec):
			var cd0 := Characters.by_id(String((sd as Dictionary).get("char", "hina")))
			seat_chars.append(cd0 if not cd0.is_empty() else Characters.LIST[0])
		human_char = seat_chars[0]
	else:
		if tutorial:
			human_char = _char_by_name("花宫雏")
		elif sim:
			human_char = human_candidates[0]
		else:
			human_char = await ask_pick_character(human_candidates, String(identities[0]))
			if not is_inside_tree() or human_char.is_empty():
				return
		var rest: Array = []
		for c in pool:
			if String(c["id"]) != String(human_char["id"]) and (lord_pre_char.is_empty() or String(c["id"]) != String(lord_pre_char.get("id", ""))):
				rest.append(c)
		rest.shuffle()
		seat_chars = [human_char]
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
		"opening_luck": Callable(self, "_eng_opening_luck"),
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
	if game_mode == "puzzle":
		Puzzles.rig(eng, pspec)
	players = eng.players
	if tutorial:
		_tut_rig()
	elif game_mode == "puzzle":
		_puzzle_show(pspec)
	turn_seat = 0
	var first_id := "主公" if game_mode == "identity" else ("地主" if game_mode == "doudizhu" else ("红方" if game_mode == "twovtwo" else ("联军" if game_mode == "boss" else ("挑战者" if game_mode == "puzzle" else "先手"))))
	for p in players:
		if p["identity"] == first_id:
			turn_seat = int(p["seat"])
			break
	if not fast and not tutorial and game_mode != "puzzle":
		turn_seat = -1
		set_phase("起手准备")
	if game_mode == "duel":
		log_msg("对局开始！你执【%s】，角色是【%s】。" % [identities[0], human_char["name"]])
	elif game_mode == "twovtwo":
		log_msg("对局开始！欢乐 2v2：你（1号位）与 4号位【%s】同属红方阵营。" % String(players[3]["char_name"]))
	elif game_mode == "boss":
		log_msg("对局开始！魔王挑战：你与 2号位【%s】、4号位【%s】组成联军，讨伐 3号位 8血魔王【%s】！" % [String(players[1]["char_name"]), String(players[3]["char_name"]), String(players[2]["char_name"])])
	elif game_mode == "puzzle":
		log_msg("残局挑战·【%s】：%s" % [String(pspec["name"]), String(pspec["goal"])])
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
	_draft_refresh_used = false
	_draft_confirming = false
	draft_refresh_btn.disabled = false
	draft_refresh_btn.text = "换一批（剩 1 次）"
	for n in table_nodes:
		(n as Control).visible = false
	_set_draft_hud(true)
	turn_label.text = "开局选将"
	draft_layer.visible = true
	_update_music_scene()
	diff_layer.visible = true
	_populate_draft_cards(candidates, my_identity)
	_layout_draft()
	var picked: Variant = await decided
	if not is_inside_tree():
		return {}
	var chosen: Dictionary = picked if picked is Dictionary and _draft_candidates.has(picked) else {}
	_draft_candidates.clear()
	draft_layer.visible = false
	diff_layer.visible = false
	draft_banner.visible = false
	_set_draft_hud(false)
	for n in table_nodes:
		(n as Control).visible = true
	for ch in draft_layer.get_children():
		draft_layer.remove_child(ch)
		ch.queue_free()
	return chosen


func _layout_draft() -> void:
	var width := vw - safe_insets.x - safe_insets.z
	var center_x := safe_insets.x + width * 0.5
	draft_banner.position = Vector2(safe_insets.x, safe_insets.y + table_hud_height + 12.0)
	draft_banner.size.x = width
	draft_banner.size.y = maxf(90.0, draft_banner.get_combined_minimum_size().y)
	draft_layer.position = Vector2(center_x - draft_layer.size.x * 0.5, maxf(262.0, draft_banner.position.y + draft_banner.size.y + 20.0))
	diff_layer.position = Vector2(center_x - diff_layer.size.x * 0.5, draft_layer.position.y + draft_layer.size.y + 24.0)


func _populate_draft_cards(candidates: Array, my_identity: String) -> void:
	_draft_candidates = candidates.duplicate()
	for ch in draft_layer.get_children():
		draft_layer.remove_child(ch)
		ch.queue_free()
	var hp_bonus := 1 if my_identity == "主公" else 0
	var card_idx := 0
	for c in candidates:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(400, 470)
		_set_btn_theme(b, Palette.MILK, Palette.LILAC_EDGE, Palette.INK, 22, 1, true, Vector2i(-1, -1), Palette.ROSE_EDGE)
		var vb := VBoxContainer.new()
		vb.mouse_filter = MOUSE_FILTER_IGNORE
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = 16
		vb.offset_right = -16
		vb.offset_top = 8
		vb.add_theme_constant_override("separation", 4)
		# 选将时展示角色基础体力及主公的体力加成。
		var cdisp: Dictionary = (c as Dictionary).duplicate()
		cdisp["hp"] = int(c["hp"]) + hp_bonus
		var ccard := Art.cg_card(cdisp, Vector2(368, 300), {"zoom": 0.58, "face_y": 0.32, "fs": 27, "draft": true})
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
		b.pressed.connect(_confirm_draft_card.bind(b, cref))
		draft_layer.add_child(b)
		var tin := create_tween().bind_node(b)
		tin.tween_interval(0.09 * idx_now)
		tin.tween_property(b, "modulate:a", 1.0, 0.28)


func _confirm_draft_card(button: Button, character: Dictionary) -> void:
	if _draft_confirming or not draft_layer.visible or button.get_parent() != draft_layer:
		return
	_draft_confirming = true
	draft_refresh_btn.disabled = true
	for candidate: Button in draft_layer.get_children():
		candidate.disabled = true
	var tw := button.create_tween()
	tw.tween_property(button, "scale", Vector2(1.07, 1.07), 0.09)
	tw.tween_property(button, "scale", Vector2(1.02, 1.02), 0.12)
	await tw.finished
	if is_instance_valid(button) and button.get_parent() == draft_layer:
		_on_decided(character)


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
	_clear_designated_targets()
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
		elif game_mode == "puzzle":
			your_result = "你赢了！" if text.contains("残局破解成功") else "你输了。"
	if puzzle_panel != null and is_instance_valid(puzzle_panel):
		puzzle_panel.visible = false
	if text.contains("未分胜负"):
		your_result = "平局"
	log_msg("对局结束：%s %s" % [text, your_result])
	turn_label.text = "对局结束"
	meta_result = {}
	if not auto_all and players.size() > 0:
		meta_result = _record_meta(text, your_result)
	if your_result == "你赢了！":
		play_sfx("win")
		_result_music_scene = "result_win"
	elif your_result == "你输了。":
		play_sfx("lose")
		_result_music_scene = "result_lose"
	else:
		_result_music_scene = "result_draw"
	if auto_all:
		return
	_update_music_scene()
	hide_prompt()
	build_settlement(text, your_result)
	refresh()


# ---------------- V0.30 教学关：脚本化单挑 ----------------
# 固定花宫雏（先手）对柚木铃奈（简单 AI，体力 2），起手发好「星光长剑/突击/闪避/补给」，
# 按步骤提示：装备 → 选突击 → 选目标 → 出牌 → 结束出牌 → 对手回合响应 → 自由练习。
var tut_step := 0
var tut_saw_enemy_turn := false  # V0.32：教学第 4 步保持到对手回合响应结束，不再只闪一句文字
var tut_panel: PanelContainer = null
var tut_label: Label = null
var tut_timer: Timer = null
const TUT_TEXT := [
	"教学 1/5 · 选择【星光长剑】，点「装备」增加攻击范围。",
	"教学 2/5 · 选择【突击】，再点对手头像。",
	"教学 3/5 · 点「出牌」。对手可用【闪避】抵挡。",
	"教学 4/5 · 点「结束出牌」。受到突击时，选中【闪避】并点「打出闪避」。",
	"教学 5/5 · 击败对手完成练习。长按手牌或角色可读说明。",
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


func _puzzle_show(pspec: Dictionary) -> void:
	if puzzle_panel == null or not is_instance_valid(puzzle_panel):
		puzzle_panel = PanelContainer.new()
		puzzle_panel.add_theme_stylebox_override("panel", _tight(style(Color(1.0, 0.98, 0.93, 0.95), 16, Color(0.85, 0.52, 0.16), 3, true), 14, 10))
		var side := seat_panel_of(1)
		var x := safe_insets.x + 22.0
		var right := play_area.position.x - 16.0
		if match_players == 3:
			right = side.position.x - 14.0
		elif match_players == 4:
			x = side.position.x + side.size.x + 14.0
		var tw := minf(550.0, right - x)
		puzzle_panel.position = Vector2(x, maxf(184.0, play_area.position.y + 46.0))
		puzzle_panel.custom_minimum_size = Vector2(tw, 0)
		puzzle_panel.size = Vector2(tw, 0)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		puzzle_panel.add_child(vb)
		puzzle_label = lbl("", 19, C_INK, true, HORIZONTAL_ALIGNMENT_LEFT)
		puzzle_label.custom_minimum_size = Vector2(tw - 28.0, 0)
		vb.add_child(puzzle_label)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		puzzle_hint_btn = plain_btn("💡 看提示", Color(1.0, 0.94, 0.78), Color(0.45, 0.25, 0.05), 19)
		_set_btn_theme(puzzle_hint_btn, Color(1.0, 0.94, 0.78), C_GOLD, Color(0.45, 0.25, 0.05), 14, 2, false, Vector2i(10, 6), C_PINK_DEEP)
		puzzle_hint_btn.custom_minimum_size = Vector2(104, 46)
		row.add_child(puzzle_hint_btn)
		var rst := plain_btn("重开", Color(1, 1, 1, 0.95), C_PINK_DEEP, 19)
		_set_btn_theme(rst, Color(1, 1, 1, 0.95), C_GOLD, C_PINK_DEEP, 14, 2, false, Vector2i(10, 6), C_PINK_DEEP)
		rst.custom_minimum_size = Vector2(80, 46)
		rst.pressed.connect(_restart_puzzle)
		row.add_child(rst)
		vb.add_child(row)
		add_child(puzzle_panel)
	var idx_n := Puzzles.index_of(String(pspec.get("id", ""))) + 1
	var update_txt := func() -> void:
		var base_s := "【残局 %d/%d · %s】\n目标：%s" % [idx_n, Puzzles.count(), String(pspec["name"]), String(pspec["goal"])]
		if puzzle_hint_shown:
			base_s += "\n💡 提示：%s" % String(pspec["hint"])
		puzzle_label.text = base_s
		if puzzle_hint_btn != null:
			puzzle_hint_btn.text = "收起提示" if puzzle_hint_shown else "💡 看提示"
	puzzle_hint_btn.pressed.connect(func() -> void:
		puzzle_hint_shown = not puzzle_hint_shown
		update_txt.call())
	update_txt.call()


func _restart_puzzle() -> void:
	if eng != null:
		eng.game_over = true
	in_play_phase = false
	targeting = false
	asking = false
	hide_prompt()
	decided.emit(null)
	end_play_pressed.emit()
	await get_tree().process_frame
	if is_inside_tree():
		start_match(false)


func _tut_show(i: int) -> void:
	tut_step = i
	if tut_panel == null or not is_instance_valid(tut_panel):
		tut_panel = PanelContainer.new()
		tut_panel.mouse_filter = MOUSE_FILTER_IGNORE
		tut_panel.add_theme_stylebox_override("panel", style(Color(1.0, 0.97, 0.94, 0.96), 20, Art.BLOSSOM_DEEP, 3, true))
		# 放在左上空白区（对手座位与己方立绘之间），不挡座位与出牌提示条
		var x := safe_insets.x + 40.0
		var tw := minf(760.0, play_area.position.x - x - 16.0)
		tut_panel.position = Vector2(x, maxf(190.0, play_area.position.y + 52.0))
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
	if game_mode == "puzzle":
		if your_result == "你赢了！" and puzzle_id != "":
			var pgot := Meta.mark_puzzle(puzzle_id)
			return {"new_ach": pgot, "puzzle_clear": true}
		return {}
	var me: Dictionary = players[0]
	var res := "win" if your_result == "你赢了！" else ("lose" if your_result == "你输了。" else "draw")
	var mvi := _mvp_info(text)
	var rec := {
		"mode": game_mode, "char": String(me["char_name"]), "identity": String(me["identity"]),
		"result": res, "rounds": int(eng.round_no) if eng != null else 0,
		"dmg": int(me.get("stat_damage", 0)), "kills": int(me.get("stat_kills", 0)),
		"heal": int(me.get("stat_heal", 0)), "taken": int(me.get("stat_taken", 0)),
		"mvp": int(mvi[0]) == 0,
	}
	if game_mode == "doudizhu" and eng != null and res in ["win", "lose"]:
		var stake := int(eng.ddz_stake())
		var base_b := stake * (200 if String(me["identity"]) == "地主" else 100)
		rec["beans_delta"] = base_b if res == "win" else -base_b
	return Meta.record(rec)


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
		elif winner_text.contains("残局破解成功"):
			in_win = idn == "挑战者"
		elif game_mode == "duel":
			in_win = bool(p["alive"])
		var sc := float(int(p.get("stat_damage", 0))) + 3.0 * float(int(p.get("stat_kills", 0))) + 0.8 * float(int(p.get("stat_heal", 0)))
		if in_win and sc > mvp_score:
			mvp_score = sc
			mvp_seat = int(p["seat"])
	return [mvp_seat, mvp_score]


func build_settlement(winner_text: String, your_result: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(Palette.NIGHT_PANEL, 0.70)
	dim.position = Vector2.ZERO
	dim.size = Vector2(vw, 1080)
	add_child(dim)
	settlement_layer = dim
	var panel := PanelContainer.new()
	var panel_width := minf(1220.0, vw - safe_insets.x - safe_insets.z - 80.0)
	panel.add_theme_stylebox_override("panel", _tight(style(Palette.MILK, 28, Palette.LILAC_EDGE, 1, true), 0, 0))
	panel.position = Vector2((vw + safe_insets.x - safe_insets.z - panel_width) * 0.5, 92 + safe_insets.y)
	panel.size = Vector2(panel_width, 896 - safe_insets.y - safe_insets.w)
	dim.add_child(panel)
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 36)
	mg.add_theme_constant_override("margin_right", 36)
	mg.add_theme_constant_override("margin_top", 24)
	mg.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(mg)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	mg.add_child(layout)
	var win := your_result == "你赢了！"
	var title := lbl(your_result if your_result != "" else winner_text, 62, C_TABLE_ACTION if win else C_INK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	var sub_text2 := winner_text
	if game_mode == "doudizhu" and eng != null:
		sub_text2 += " · 叫分×%d · 加倍×%d（总×%d）" % [int(eng.ddz_multiplier), int(eng.ddz_double), int(eng.ddz_stake())]
	var sub := lbl(sub_text2, 24, C_INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(sub)
	var review_scroll := ScrollContainer.new()
	review_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	review_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(review_scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 9)
	review_scroll.add_child(vb)
	# 本局 MVP 为胜方阵营内综合评分最高者。
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
		var mt := lbl("本局 MVP", 40, Color(0.50, 0.32, 0.11), true)
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
		row.add_theme_stylebox_override("panel", _tight(style(Palette.ROSE_SOFT if is_me else Palette.LILAC_SOFT, 14, Palette.ROSE_EDGE if is_mvp else Palette.LILAC_EDGE, 1), 16, 8))
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
			"挑战者":
				idc = Color(0.85, 0.45, 0.1)
			"守关":
				idc = Color(0.55, 0.30, 0.78)
			"先手", "后手":
				idc = Color(0.35, 0.5, 0.8)
		var head := lbl("%s%s" % [String(p["char"]["name"]), " · 你" if is_me else ""], 26, C_INK, true)
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
		if int(meta_result.get("win_streak", 0)) >= 2:
			mt_parts.append("🔥%d连胜！" % int(meta_result["win_streak"]))
		if meta_result.has("beans"):
			var bd := int(meta_result.get("beans_delta", 0))
			var bsign := ("+%d" % bd) if bd >= 0 else str(bd)
			var aid_t := "（含低保 +300）" if bool(meta_result.get("beans_aid", false)) else ""
			mt_parts.append("🪙欢斗豆 %s → %d%s" % [bsign, int(meta_result["beans"]), aid_t])
		var names: Array = []
		for a in meta_result.get("new_ach", []):
			names.append(String(a[1]))
		if not names.is_empty():
			mt_parts.append("解锁成就：" + "、".join(PackedStringArray(names)))
		if int(meta_result.get("daily_ready", 0)) > 0:
			mt_parts.append("📋 有 %d 项今日委托可回主页领奖！" % int(meta_result.get("daily_ready", 0)))
		if not mt_parts.is_empty():
			var ml := lbl("　".join(PackedStringArray(mt_parts)), 22, C_GOLD.darkened(0.15), true)
			ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(ml)
	if game_mode == "puzzle" and not win:
		var pspec_end := Puzzles.by_id(puzzle_id)
		if not pspec_end.is_empty():
			var hl := lbl("💡 通关思路：" + String(pspec_end.get("hint", "")), 22, Color(0.45, 0.26, 0.08), true, HORIZONTAL_ALIGNMENT_CENTER)
			hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(hl)
	layout.add_child(btn_row)
	if game_mode == "puzzle":
		var nid := Puzzles.next_id(puzzle_id)
		if win and nid != "":
			var next_b := plain_btn("下一关 ▶", C_TABLE_ACTION, C_WHITE, 28)
			next_b.custom_minimum_size = Vector2(190, 92)
			next_b.pressed.connect(func() -> void:
				puzzle_id = nid
				start_match(false))
			btn_row.add_child(next_b)
		var retry_b := plain_btn("重玩本关", C_TABLE_ACTION if not win else Palette.LILAC_SOFT, C_WHITE if not win else C_INK, 26)
		retry_b.custom_minimum_size = Vector2(170, 92)
		retry_b.pressed.connect(func() -> void: start_match(false))
		btn_row.add_child(retry_b)
		if open_puzzles_cb.is_valid():
			var list_b := plain_btn("选关列表", Color(1, 1, 1, 0.95), C_INDIGO, 26)
			list_b.custom_minimum_size = Vector2(166, 92)
			list_b.pressed.connect(func() -> void: open_puzzles_cb.call())
			btn_row.add_child(list_b)
	else:
		var again := plain_btn("再来一局", C_TABLE_ACTION, C_WHITE, 30)
		again.custom_minimum_size = Vector2(240, 92)
		again.pressed.connect(func() -> void: start_match(false))
		btn_row.add_child(again)
	var log_b := plain_btn("完整战报", Palette.SKY_SOFT, C_INK, 26)
	log_b.custom_minimum_size = Vector2(180, 92)
	log_b.pressed.connect(func() -> void:
		open_info_overlay("本局完整战报", "\n".join(eng.log_lines) if eng != null else "")
		move_child(info_overlay, get_child_count() - 1))
	btn_row.add_child(log_b)
	var home := plain_btn("返回主页", Palette.LILAC_SOFT, C_INK, 28)
	home.custom_minimum_size = Vector2(180, 92)
	home.pressed.connect(func() -> void: go_home.call())
	btn_row.add_child(home)
	_extend_cover(dim, dim.color)


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
				if seat != 0 and not (p["equip"]["weapon"] as Dictionary).is_empty() and _jieli_has_target(p):
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


func _jieli_has_target(a: Dictionary) -> bool:
	for q in alive_players():
		if q != a and attack_reachable(a, {"name": "突击"}, q):
			return true
	return false


func cancel_targeting() -> void:
	targeting = false
	spear_targeting = false
	spear_cards = []
	muniu_targeting = false
	muniu_storing = false
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
	_ensure_hand_card_visible(_find_wrap(card))
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
		elif ask_mode == "respond" and _respond_card_ok(card):
			_ask_select(card)
		else:
			_nudge_card(card)
		return
	if not interactive or turn_seat != 0:
		return
	var me: Dictionary = players[0]
	if muniu_storing:
		selected_card = {} if is_same(selected_card, card) else card
		_show_sel_hint()
		_queue_refresh()
		_maybe_auto_confirm()
		return
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
		if double_tap_play and (Time.get_ticks_msec() - _last_card_tap_ms) <= 450 and _can_confirm():
			_on_confirm_pressed()
			return
		cancel_targeting()
		return
	_last_card_tap_ms = Time.get_ticks_msec()
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
	play_sfx("select")
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
		"突击", "单挑", "借力打力", "火焰试炼", "羁绊锁链", "落雷", "沉迷游戏", "断粮封锁", "草木疑兵", "浮雷", "声东击西", "弃甲曳兵", "增兵减灶", "补给", "水淹七军", "出其不意", "洞烛先机", "继往开来":
			await eng.play_card(me, card, tgt)
		"突然检查", "悄悄借走", "逐近弃远":
			var entry := await choose_zone_entry(me, tgt)
			if entry.is_empty():
				eng.discard_from_hand(me, card)
				log_msg("你使用「%s」，但 %s 身上没有任何牌。" % [n, pname(tgt)])
			else:
				await eng.play_card(me, card, tgt, entry["card"])
	_queue_refresh()


func execute_simple_card(me: Dictionary, card: Dictionary) -> void:
	await eng.play_card(me, card, {})
	_queue_refresh()


func _on_difficulty(d: int) -> void:
	difficulty = d
	if eng != null:
		eng.difficulty = d
	refresh_diff_buttons()


func refresh_diff_buttons() -> void:
	for i in diff_btns.size():
		var b: Button = diff_btns[i]
		_wire_btn_bounce(b)
		if i == difficulty:
			_set_btn_theme(b, C_TABLE_ACTION, Palette.ROSE_EDGE, C_WHITE, 24, 1, true, Vector2i(10, 6))
		else:
			_set_btn_theme(b, _table_inset, _table_edge, _table_text, 24, 1, true, Vector2i(10, 6), Palette.ROSE_EDGE)


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
	muniu_storing = false
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
	play_sfx("select")
	_show_sel_hint()
	refresh()
	_maybe_auto_confirm()


func _on_muniu_store() -> void:
	if not interactive or asking or turn_seat != 0 or game_over or eng == null or players.is_empty():
		return
	if muniu_storing:
		cancel_targeting()
		return
	var me: Dictionary = players[0]
	if equip_name(me, "treasure") != "木牛流马":
		return
	if (me["hand"] as Array).is_empty():
		show_hint("没有可以存入「木牛流马」的手牌")
		return
	if not _hand_has(selected_card):
		selected_card = {}
	targeting = false
	target_candidates = []
	sel_target = -1
	extra_target = -1
	spear_targeting = false
	spear_cards = []
	muniu_targeting = false
	skill_mode = ""
	skill_card = {}
	muniu_storing = true
	_show_sel_hint()
	_queue_refresh()
	_maybe_auto_confirm()


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
	muniu_storing = false
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
	_set_tools_open(false)
	info_title.text = title
	info_text.bbcode_enabled = bb
	info_text.text = body
	info_overlay.visible = true
	move_child(info_overlay, get_child_count() - 1)
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
		var col_k := "#9a95a0" if left_n == 0 else ("#c77d14" if left_n <= 2 else "#2e8555")
		key_parts.append("[color=%s][b]%s ×%d[/b][/color]" % [col_k, kn, left_n])
	var lines: Array = [
		"[b][color=#3d2f42]牌堆剩余 %d 张 · 弃牌堆 %d 张[/color][/b]" % [eng.deck.size(), eng.discard_pile.size()],
	]
	var fmt_c := func(cd: Dictionary) -> String:
		var col_s := "#d63649" if is_red(cd) else "#2b2a38"
		return "[color=%s]%s[/color]" % [col_s, card_text(cd)]
	var can_see_ally := (game_mode == "twovtwo" or game_mode == "boss" or (game_mode == "doudizhu" and not players.is_empty() and String(players[0]["identity"]) == "农民"))
	if can_see_ally and not players.is_empty():
		lines.append("")
		lines.append("[b][color=#c9345a]【同盟队友实时手牌与状态】[/color][/b]")
		for mp in players:
			if int(mp["seat"]) != 0 and String(mp["identity"]) == String(players[0]["identity"]):
				var mh: Array = []
				for mc in mp["hand"]:
					mh.append(fmt_c.call(mc))
				var mst := ("存活 ♥%d/%d" % [int(mp["hp"]), int(mp["max_hp"])]) if bool(mp["alive"]) else "已阵亡"
				lines.append("  · [b]%s[/b]（%s）：%s" % [pname(mp), mst, "、".join(PackedStringArray(mh)) if not mh.is_empty() else "（无手牌）"])
	if game_mode == "doudizhu" and not eng.ddz_open_seats.is_empty():
		var open_rows: Array = []
		for os_seat in eng.ddz_open_seats:
			var si := int(os_seat)
			if si < 0 or si >= players.size():
				continue
			var op: Dictionary = players[si]
			var oh: Array = []
			for oc in op["hand"]:
				oh.append(fmt_c.call(oc))
			var ost := ("存活 ♥%d/%d" % [int(op["hp"]), int(op["max_hp"])]) if bool(op["alive"]) else "已阵亡"
			open_rows.append("  · [b]%s[/b]（%s · %s）：%s" % [pname(op), String(op["identity"]), ost, "、".join(PackedStringArray(oh)) if not oh.is_empty() else "（无手牌）"])
		if not open_rows.is_empty():
			lines.append("")
			lines.append("[b][color=#b87312]【斗地主明牌 · 公开手牌（当前×%d倍）】[/color][/b]" % int(eng.ddz_stake()))
			lines.append_array(open_rows)
	lines.append("")
	lines.append("[b][color=#b83258]【关键牌剩余速查】[/color][/b]")
	lines.append("　".join(PackedStringArray(key_parts)))
	if not eng.discard_pile.is_empty():
		var rec_cards: Array = []
		var dsz: int = (eng.discard_pile as Array).size()
		for i in range(dsz - 1, maxi(-1, dsz - 13), -1):
			rec_cards.append(fmt_c.call(eng.discard_pile[i]))
		lines.append("")
		lines.append("[b][color=#664396]【最近弃牌堆明细（最新在前，共 %d 张）】[/color][/b]" % dsz)
		lines.append("  ".join(PackedStringArray(rec_cards)))
	lines.append("")
	lines.append("[color=#554555]以下按已出现的牌推算未见张数：[/color]")
	var kind_order := ["基本牌", "锦囊牌", "延时锦囊", "武器", "防具", "饰品", "宝物"]
	for kind in kind_order:
		var parts: Array = []
		for nm in CardDefs.DEFS:
			if CardDefs.kind_of(nm) != kind:
				continue
			var left := int(CardDefs.DEFS[nm]["n"]) - int(seen.get(nm, 0))
			if left > 0:
				parts.append("%s ×%d" % [nm, left])
		if not parts.is_empty():
			lines.append("[b][color=#b83258]【%s】[/color][/b]" % kind)
			lines.append("  ".join(parts))
	return "\n".join(lines)


func hand_sort_cmp(a: Dictionary, b: Dictionary) -> bool:
	var rank := {"基本牌": 0, "锦囊牌": 1, "延时锦囊": 2, "武器": 3, "防具": 4, "饰品": 5, "宝物": 6}
	var ra := int(rank.get(CardDefs.kind_of(String(a["name"])), 9))
	var rb := int(rank.get(CardDefs.kind_of(String(b["name"])), 9))
	if ra != rb:
		return ra < rb
	if String(a["name"]) != String(b["name"]):
		return String(a["name"]) < String(b["name"])
	return int(a["point"]) < int(b["point"])


func hand_sort_suit_cmp(a: Dictionary, b: Dictionary) -> bool:
	var srank := {"黑桃": 0, "红桃": 1, "梅花": 2, "方块": 3}
	var sa := int(srank.get(String(a.get("suit", "")), 9))
	var sb := int(srank.get(String(b.get("suit", "")), 9))
	if sa != sb:
		return sa < sb
	if int(a.get("point", 0)) != int(b.get("point", 0)):
		return int(a.get("point", 0)) < int(b.get("point", 0))
	return String(a["name"]) < String(b["name"])


func sort_my_hand() -> void:
	if players.is_empty():
		return
	hand_sort_by_suit = not hand_sort_by_suit
	if hand_sort_by_suit:
		(players[0]["hand"] as Array).sort_custom(hand_sort_suit_cmp)
	else:
		(players[0]["hand"] as Array).sort_custom(hand_sort_cmp)
	if sort_btn != null and is_instance_valid(sort_btn):
		sort_btn.text = "排序：花色" if hand_sort_by_suit else "排序：类型"
	show_hint("已按【花色点数】整理手牌（再点切回类型）" if hand_sort_by_suit else "已按【卡牌类型】整理手牌（再点切换花色）")
	refresh()


func toggle_auto() -> void:
	auto_mode = not auto_mode
	if auto_btn:
		auto_btn.text = "取消托管" if auto_mode else "开始托管"
	if is_instance_valid(tools_btn):
		tools_btn.text = "托管中 ▾" if auto_mode else "工具 ▾"
	show_hint("已开启托管，静替你出牌。" if auto_mode else "已关闭托管。")
	# V0.25 修复：在自己出牌阶段中途开托管，旧版要等你手动点「结束」才生效；现立即由 AI 接管本阶段剩余出牌
	if auto_mode and in_play_phase and turn_seat == 0 and not asking and eng != null and not eng.game_over:
		cancel_targeting()  # V0.27：托管接管前清掉未确认的选择（牌/目标/技能选择状态）
		auto_takeover = true
		end_play_pressed.emit()


func _style_concede_btn(armed: bool) -> void:
	if concede_btn == null or not is_instance_valid(concede_btn):
		return
	if armed:
		concede_btn.text = "确认认输"
		concede_btn.add_theme_font_size_override("font_size", 27)
		_set_btn_theme(concede_btn, Color(0.84, 0.18, 0.34), C_GOLD, C_WHITE, 18, 2, true, Vector2i(6, 6), C_GOLD)
	else:
		concede_btn.text = "认输"
		concede_btn.add_theme_font_size_override("font_size", 27)
		_set_btn_theme(concede_btn, _table_inset, _table_edge, _table_text, 18, 1, false, Vector2i(10, 6), Palette.ROSE_EDGE)


func on_concede_pressed() -> void:
	if eng == null or eng.game_over:
		return
	if not concede_arm:
		concede_arm = true
		_style_concede_btn(true)
		await get_tree().create_timer(2.5).timeout
		concede_arm = false
		if concede_btn and eng != null and not eng.game_over:
			_style_concede_btn(false)
		return
	_style_concede_btn(false)
	concede_arm = false
	_set_tools_open(false)
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
			_clear_designated_targets()
			discard_queue.clear()
			discard_auto_left = 0
			if not auto_all and turn_seat == 0:
				show_turn_banner()
				play_sfx("turn")
			else:
				_hide_turn_banner()
	round_no = eng.round_no
	_update_music_scene()
	_queue_refresh()


func _update_music_scene() -> void:
	if auto_all or not is_inside_tree():
		return
	var director := get_tree().get_first_node_in_group("music_director") as MusicDirector
	if director == null:
		return
	director.play_scene(_battle_music_scene())


func _battle_music_scene() -> String:
	if not _result_music_scene.is_empty():
		return _result_music_scene
	if is_instance_valid(draft_layer) and draft_layer.visible:
		return "draft"
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
	# 合并同一动作的出牌事件和牌区变动，保留出牌动画的即时反馈。
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_do_queued_refresh")


func _do_queued_refresh() -> void:
	if not _refresh_pending:
		return
	_refresh_pending = false
	if is_inside_tree():
		refresh()


func _eng_pace(sec: float) -> void:
	if fast or auto_all:
		return
	await wait(sec)


func _eng_played(card: Dictionary, owner: String, target_name: String = "") -> void:
	var seat := -1
	var target_seat := -1
	for p in players:
		var table_name := pname(p)
		var engine_name: String = eng.pname(p) if eng != null else table_name
		if owner == table_name or owner == engine_name:
			seat = int(p["seat"])
		if target_name == table_name or target_name == engine_name:
			target_seat = int(p["seat"])
	# 响应牌不清掉仍在结算的目标。
	if target_seat >= 0:
		_replace_designated_targets([target_seat])
	elif target_name in ["", "重铸"]:
		_clear_designated_targets()
	if seat >= 0 and target_seat >= 0 and seat != target_seat:
		# 从确认出牌开始指向目标，和离手动画同步。
		if String(card.get("name", "")) == "突击":
			fx_attack_fx(seat, target_seat, String(card.get("nature", "")))
		else:
			fx_target_mark(seat, target_seat)
	elif seat >= 0 and not auto_all:
		fx_target_ring(seat, Color(1.0, 0.72, 0.22))
	if seat == 0:
		_battle_haptic(12)
	var actor := _event_seat_name(seat) if seat >= 0 else _short_name(owner)
	_show_play_callout(card, actor, _event_seat_name(target_seat), target_name)
	var hand_wrap: Control = null
	if seat == 0:
		var physical := card
		var costs: Array = card.get("src_cards", [])
		if costs.size() == 1:
			physical = costs[0]
		hand_wrap = _find_wrap(physical)
	var staged := show_played_card(card, seat, hand_wrap)
	_queue_refresh()
	if staged == null or not _motion_enabled():
		return
	# 处理区的牌已经接手画面，等待规则移除实体手牌时不显示第二张。
	var departing := hand_wrap if target_name != "展示" else null
	if is_instance_valid(departing):
		departing.hide()
	await wait(PLAYED_CARD_SLIDE + PLAYED_CARD_HOLD)
	if is_instance_valid(departing) and not departing.is_queued_for_deletion():
		departing.show()


func _eng_ask_skill(p: Dictionary, sid: String, timing: String, ctx: Dictionary) -> bool:
	var def: Dictionary = eng.skill_lib.get(sid, {})
	var nm := String(def.get("name", sid))
	var v: Variant = await ask("发动「%s」？" % nm, [{"label": "发动技能", "value": true}, {"label": "不发动", "value": false}], Callable(), "", {"context": IntroPop.timing_label(timing)})
	return bool(v)


func _eng_ask_respond(p: Dictionary, card_name: String, reason: String) -> bool:
	# V0.25：响应时手里能打出的牌亮起（其余置灰），可直接点那张牌作答；限时作答，超时视为不出
	respond_name = card_name
	respond_names = [card_name]
	resp_pref_card = {}
	if tutorial and tut_step == 3 and card_name == "闪避" and not players.is_empty() and p == players[0]:
		# V0.32：教学第 4 步的响应练习：面板改为当前情境提示，并保留到玩家作答
		if tut_panel != null and is_instance_valid(tut_panel) and tut_label != null:
			tut_panel.visible = true
			tut_label.text = "对手使用了「突击」。选中亮起的闪避，再点「打出闪避」。"
			move_child(tut_panel, get_child_count() - 1)
	var reply := "打出%s" % card_name
	var v: Variant = await ask("选择一张「%s」" % card_name, [{"label": reply, "value": true}, {"label": "不响应", "value": false}], Callable(), "respond", {"context": reason, "confirm": reply})
	respond_name = ""
	respond_names = []
	_queue_refresh()
	return v is bool and bool(v)


func _eng_ask_save(p: Dictionary, dying: Dictionary) -> bool:
	respond_name = "补给"
	respond_names = ["补给", "特饮"] if p == dying else ["补给"]
	resp_pref_card = {}
	var save_hint := "补给/特饮" if p == dying else "补给"
	var need := maxi(1, 1 - int(dying["hp"]))
	var context := "%s 濒死 · 需回复 %d 点体力" % [String(dying["char_name"]), need]
	var v: Variant = await ask("选一张救援牌（%s）" % save_hint, [{"label": "救援", "value": true}, {"label": "不救", "value": false}], Callable(), "respond", {"context": context, "confirm": "救援"})
	respond_name = ""
	respond_names = []
	_queue_refresh()
	return v is bool and bool(v)


func _eng_pick_card(p: Dictionary, cands: Array, prompt: String) -> Dictionary:
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
	discard_prompt = "请选择 %d 张手牌弃置" % need
	selected_card = {}
	targeting = false
	_queue_refresh()
	var v: Variant = await ask(discard_prompt, [{"label": "弃置 %d 张" % need, "value": "__confirm"}, {"label": "自动弃牌", "value": "__auto", "default": true}], func() -> void:
		discard_confirm_btn = prompt_btns.get_child(0) as Button
		var auto_pick_b := _make_action_btn("⚡ 选弱牌", Color(0.98, 0.76, 0.30), Color(0.24, 0.14, 0.04))
		auto_pick_b.custom_minimum_size = Vector2(180, 64)
		auto_pick_b.pressed.connect(_auto_select_discard_cards)
		prompt_btns.add_child(auto_pick_b)
		prompt_btns.move_child(auto_pick_b, 1)
		_update_discard_ui(), "", {"context": "手牌超过上限" if phase_need > 0 else ""})
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
	maybe_restore_hint()
	refresh()
	await end_play_pressed
	in_play_phase = false
	targeting = false
	spear_targeting = false
	spear_cards = []
	muniu_targeting = false
	muniu_storing = false
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

static func line_for(cid: String, cat: String = "skill") -> String:
	return AudioCfg.cv_text(cid, cat)


func show_bubble(seat: int, cat: String, seconds: float = 1.8) -> void:
	if not _motion_enabled() or not _can_show_fx() or seat < 0 or seat >= players.size():
		return
	var ch: Dictionary = players[seat].get("char", {})
	var cid := String(ch.get("id", ""))
	var text := line_for(cid, cat)
	if text == "":
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
	_add_motion_fx(bub)
	bubble_nodes[seat] = bub
	bubble_order.append(seat)
	bub.modulate.a = 0.0
	bub.position.y += 8
	var btw := create_tween().bind_node(bub)
	btw.tween_property(bub, "modulate:a", 1.0, 0.15)
	btw.parallel().tween_property(bub, "position:y", bub.position.y - 8.0, 0.18)
	btw.tween_interval(clampf(seconds - 0.3, 1.5, 6.0))
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


func _process(_delta: float) -> void:
	if _designated_until_ms > 0:
		var now := Time.get_ticks_msec()
		if asking:
			_designated_until_ms = maxi(_designated_until_ms, now + 700)
		elif now >= _designated_until_ms:
			_clear_designated_targets()
	if ask_deadline_ms > 0 and asking:
		var remaining := ask_deadline_ms - Time.get_ticks_msec()
		if remaining <= 0:
			ask_deadline_ms = 0
			log_msg("作答超时，已按默认选项处理。")
			_on_decided(ask_default)
		else:
			_countdown_tick(float(remaining) / 1000.0)


func _motion_enabled() -> bool:
	return not reduced_motion and not fast and not auto_all


func _can_show_fx() -> bool:
	return is_instance_valid(fx_root) and not auto_all and fx_root.get_child_count() < FX_CAP


func _add_motion_fx(node: Node) -> void:
	node.set_meta("transient_motion", true)
	fx_root.add_child(node)


func _skip_transient_motion() -> void:
	_pz_finish_motion()
	if is_instance_valid(target_trace_fades):
		for trace in target_trace_fades.get_children():
			target_trace_fades.remove_child(trace)
			trace.queue_free()
	if is_instance_valid(target_traces):
		for trace in target_traces.get_children():
			trace.finish()
	_hide_turn_banner()
	_stop_drag_pose()
	_draw_drag_pose(Vector3.ZERO)
	_layout_hand(false)
	_reset_prompt_surface()
	if not is_instance_valid(fx_root):
		return
	for node in fx_root.get_children():
		if node.has_meta("transient_motion"):
			fx_root.remove_child(node)
			node.queue_free()


func _add_float_motion(label: Label, tween: Tween, rise: float) -> void:
	label.set_meta("transient_motion", true)
	label.scale = Vector2(0.978, 0.978)
	label.modulate.a = 0.15
	tween.set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 1.0, 0.08)
	tween.tween_property(label, "scale", Vector2.ONE, 0.16)
	tween.tween_property(label, "position:y", label.position.y - rise, 0.68)
	tween.tween_property(label, "modulate:a", 0.0, 0.22).set_delay(0.49).set_ease(Tween.EASE_IN_OUT)


func fx_float(seat: int, text: String, color: Color, fsize: int = 46, rise: float = 84.0) -> void:
	if not _can_show_fx():
		return
	var lb := lbl(text, fsize, color, true, HORIZONTAL_ALIGNMENT_CENTER)
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	lb.size = Vector2(320, 64)
	lb.pivot_offset = Vector2(160, 32)
	var center := seat_center(seat)
	var now := Time.get_ticks_msec()
	var recent: Array = float_stack.get(seat, [0, 0])
	var row := (int(recent[1]) + 1) % 3 if now - int(recent[0]) < 410 else 0
	float_stack[seat] = [now, row]
	lb.position = Vector2(clampf(center.x - 160.0, 4.0, vw - 324.0), maxf(116.0, center.y - 65.0) + row * 43.0)
	lb.mouse_filter = MOUSE_FILTER_IGNORE
	lb.add_theme_constant_override("outline_size", 7)
	lb.add_theme_color_override("font_outline_color", Color(0.15, 0.09, 0.20, 0.98))
	fx_root.add_child(lb)
	var tw := lb.create_tween()
	if _motion_enabled():
		_add_float_motion(lb, tw, minf(rise, 34.0))
	else:
		tw.tween_interval(0.56)
		tw.tween_property(lb, "modulate:a", 0.0, 0.17)
	tw.chain().tween_callback(lb.queue_free)


func _fade_effect(item: CanvasItem, fade_in: float, hold: float, fade_out: float) -> void:
	var tween := item.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if fade_in > 0.0:
		item.modulate.a = 0.0
		tween.tween_property(item, "modulate:a", 1.0, fade_in)
	tween.tween_property(item, "modulate:a", 0.0, fade_out).set_delay(hold)
	tween.tween_callback(item.queue_free)


func fx_flash(seat: int, color: Color) -> void:
	var panel := seat_panel_of(seat)
	if not _motion_enabled() or not _can_show_fx() or panel == null:
		return
	var pulse := Panel.new()
	pulse.name = "SeatImpactGlow"
	pulse.position = panel.position
	pulse.size = panel.size
	pulse.add_theme_stylebox_override("panel", style(Color(color, 0.075), 22, Color(color.lightened(0.12), 0.80), 3))
	_add_motion_fx(pulse)
	_fade_effect(pulse, 0.07, 0.055, 0.22)


func fx_target_ring(seat: int, col: Color) -> void:
	if not _can_show_fx() or fast:
		return
	var panel := seat_panel_of(seat)
	if panel == null:
		return
	var ring := Panel.new()
	ring.position = panel.position - Vector2(5, 5)
	ring.size = panel.size + Vector2(10, 10)
	ring.add_theme_stylebox_override("panel", style(Color(0, 0, 0, 0), 22, col, 3))
	if _motion_enabled():
		_add_motion_fx(ring)
		_fade_effect(ring, 0.075, 0.14, 0.21)
	else:
		fx_root.add_child(ring)
		_fade_effect(ring, 0.0, 0.31, 0.19)


class TargetTrace extends Node2D:
	const INK := Color("#513746")
	const LIGHT := Color("#fff3e8")
	var points: PackedVector2Array
	var path_length := 0.0
	var _distances: PackedFloat32Array
	var tint: Color:
		set(value):
			tint = value
			queue_redraw()
	var progress := 0.0:
		set(value):
			progress = value
			queue_redraw()
	var tail_progress := 0.0:
		set(value):
			tail_progress = value
			queue_redraw()
	var arrival := 0.0:
		set(value):
			arrival = value
			queue_redraw()
	var _animation: Tween

	func set_route(path: PackedVector2Array) -> void:
		points = path
		path_length = 0.0
		_distances = PackedFloat32Array([0.0])
		for i in range(1, points.size()):
			path_length += points[i - 1].distance_to(points[i])
			_distances.append(path_length)

	func point_at(fraction: float) -> Vector2:
		if path_length <= 0.0:
			return Vector2.ZERO
		if fraction <= 0.0:
			return points[0]
		if fraction >= 1.0:
			return points[-1]
		var distance := fraction * path_length
		var i := clampi(_distances.bsearch(distance), 1, points.size() - 1)
		var length := _distances[i] - _distances[i - 1]
		return points[i - 1].lerp(points[i], (distance - _distances[i - 1]) / maxf(0.001, length))

	func start(travel_time: float) -> void:
		_animation = create_tween()
		_animation.tween_property(self, "progress", 1.0, travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_animation.tween_property(self, "arrival", 1.0, 0.32)
		_animation.parallel().tween_property(self, "tail_progress", 1.0, 0.22).set_delay(0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	func finish() -> void:
		if _animation and _animation.is_valid():
			_animation.kill()
		progress = 1.0
		tail_progress = 1.0
		arrival = 1.0

	func fade_out() -> void:
		# 退场时保留已画出的部分，让下一次指定可以立即开始。
		if _animation and _animation.is_valid():
			_animation.kill()
		_animation = create_tween()
		_animation.tween_property(self, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_SINE)
		_animation.tween_callback(queue_free)

	func _path_between(start_fraction: float, end_fraction: float) -> PackedVector2Array:
		var start_index := _distances.bsearch(start_fraction * path_length, false)
		var end_index := mini(_distances.bsearch(end_fraction * path_length), points.size() - 1)
		var portion := PackedVector2Array([point_at(start_fraction)])
		portion.append_array(points.slice(start_index, end_index))
		portion.append(point_at(end_fraction))
		return portion

	func _draw_bright_trail() -> void:
		var trail := _path_between(tail_progress, progress)
		var light := 1.0 - tail_progress
		draw_polyline(trail, Color(tint, 0.26 * light), 15.0, true)
		var colors := PackedColorArray([Color(tint, 0.16 * light)])
		var span := maxf((progress - tail_progress) * path_length, 0.001)
		var traveled := 0.0
		for i in range(1, trail.size()):
			traveled += trail[i - 1].distance_to(trail[i])
			var blend := clampf(traveled / span, 0.0, 1.0)
			colors.append(Color(tint.lerp(LIGHT, blend * blend), lerpf(0.16, 1.0, blend) * light))
		draw_polyline_colors(trail, colors, 5.0, true)
		var tip := trail[-1]
		draw_circle(tip, 12.0, Color(tint, 0.20 * light), true, -1.0, true)
		draw_circle(tip, 7.0, Color(tint, 0.68 * light), true, -1.0, true)
		draw_circle(tip, 3.6, Color(LIGHT, light), true, -1.0, true)

	func _draw() -> void:
		if path_length <= 0.0 or progress <= 0.0:
			return
		var guide := _path_between(0.0, progress)
		draw_polyline(guide, Color(INK, 0.64), 8.0, true)
		draw_polyline(guide, Color(tint, 0.82), 3.8, true)
		draw_circle(points[0], 5.5, Color(INK, 0.72), true, -1.0, true)
		draw_circle(points[0], 3.4, tint, true, -1.0, true)
		if tail_progress < progress:
			_draw_bright_trail()
		if arrival > 0.0:
			var tip := points[-1]
			var forward := point_at(0.95).direction_to(tip)
			var base := tip - forward * 16.0
			var wing := forward.orthogonal() * 7.0
			var arrow := PackedVector2Array([base + wing, tip, base - wing])
			var opacity := smoothstep(0.0, 0.20, arrival)
			draw_polyline(arrow, Color(INK, 0.77 * opacity), 8.0, true)
			draw_polyline(arrow, Color(tint.lerp(LIGHT, 0.22), opacity), 3.8, true)
			if arrival < 1.0:
				var pulse := sin(PI * arrival) * (1.0 - arrival)
				draw_arc(tip, lerpf(7.0, 27.0, arrival), 0.0, TAU, 32, Color(tint, pulse), 2.6, true)


func _trace_port(rect: Rect2, toward: Vector2) -> Vector2:
	var center := rect.get_center()
	var direction := center.direction_to(toward)
	var half := rect.size * 0.5
	var edge_distance := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
	return center + direction * (edge_distance + 9.0)


func _trace_path(source: Control, target: Control) -> PackedVector2Array:
	var source_rect := source.get_rect()
	var target_rect := target.get_rect()
	var middle := source_rect.get_center().lerp(target_rect.get_center(), 0.5)
	var inward := 1.0 if middle.x < vw * 0.5 else -1.0
	var obstacles: Array[Rect2] = [source_rect.grow(-8.0), target_rect.grow(-8.0)]
	for panel in seat_panels:
		if panel != source and panel != target and panel.visible:
			obstacles.append(panel.get_rect())
	if me_panel_ref != source and me_panel_ref != target and me_panel_ref.visible:
		obstacles.append(me_panel_ref.get_rect())
	var lowest_score := INF
	var best := PackedVector2Array()
	# 座位靠得很近时，把线弯向桌心，给箭头留出距离。
	for offset in [Vector2.ZERO, Vector2(0, 170), Vector2(inward * 245, 0),
		Vector2(0, 310), Vector2(inward * 375, 0), Vector2(0, -170), Vector2(0, -310)]:
		var via: Vector2 = middle + offset
		if source_rect.grow(12).has_point(via) or target_rect.grow(12).has_point(via):
			continue
		var start := _trace_port(source_rect, via)
		var end := _trace_port(target_rect, via)
		var path := PackedVector2Array([start])
		var length := 0.0
		var score := 0.0
		for step in range(1, 25):
			var t := step / 24.0
			var point := start.lerp(via, t).lerp(via.lerp(end, t), t)
			var segment := Rect2(path[-1], Vector2.ZERO).expand(point).grow(8.0)
			for obstacle in obstacles:
				if segment.intersects(obstacle):
					score += 1.0
			length += path[-1].distance_to(point)
			path.append(point)
		if length < 120.0:
			score += 1.0 + (120.0 - length) / 24.0
		if score == 0.0:
			return path
		if score < lowest_score:
			lowest_score = score
			best = path
	return best


func _fx_trace(src_seat: int, tgt_seat: int, color: Color, travel_time: float) -> void:
	if auto_all or game_over or not is_instance_valid(target_traces) or src_seat == tgt_seat:
		return
	var source := seat_panel_of(src_seat)
	var target := seat_panel_of(tgt_seat)
	if source == null or target == null:
		return
	if target_traces.get_child_count() > 0 and int(target_traces.get_child(0).get_meta("src_seat")) != src_seat:
		_replace_designated_targets([tgt_seat])
	for trace in target_traces.get_children():
		if trace.get_meta("src_seat") == src_seat and trace.get_meta("tgt_seat") == tgt_seat:
			# 普通突击可能已声明，之后由装备改变属性色。
			if trace.tint != color:
				trace.tint = color
			return
	var trace := TargetTrace.new()
	trace.name = "TargetTrace"
	trace.set_meta("src_seat", src_seat)
	trace.set_meta("tgt_seat", tgt_seat)
	trace.set_route(_trace_path(source, target))
	trace.tint = color
	target_traces.add_child(trace, true)
	if _motion_enabled():
		trace.start(travel_time)
	else:
		trace.finish()


func fx_target_mark(src_seat: int, tgt_seat: int) -> void:
	_fx_trace(src_seat, tgt_seat, Color("#ffd17e"), 0.26)


func fx_attack_fx(src_seat: int, tgt_seat: int, nature: String = "") -> void:
	_fx_trace(src_seat, tgt_seat, _attack_color(nature, Color("#ff8cb1")), 0.26)


func _attack_color(nature: String, fallback: Color) -> Color:
	match nature:
		"火":
			return Color(1.0, 0.58, 0.29)
		"雷":
			return Color(0.80, 0.66, 1.0)
		"冰":
			return Color(0.56, 0.86, 1.0)
	return fallback


func fx_slash(tgt_seat: int, color: Color) -> void:
	if not _motion_enabled() or not _can_show_fx():
		return
	var strike := Line2D.new()
	strike.name = "AttackImpact"
	strike.width = 12.0
	strike.default_color = color.lightened(0.19)
	if _impact_width == null:
		_impact_width = Curve.new()
		_impact_width.add_point(Vector2(0.0, 0.16))
		_impact_width.add_point(Vector2(0.48, 1.0))
		_impact_width.add_point(Vector2(1.0, 0.13))
	strike.width_curve = _impact_width
	strike.antialiased = true
	strike.begin_cap_mode = Line2D.LINE_CAP_ROUND
	strike.end_cap_mode = Line2D.LINE_CAP_ROUND
	strike.add_point(Vector2(-57, 36))
	strike.add_point(Vector2(-2, -9))
	strike.add_point(Vector2(57, -36))
	strike.position = seat_center(tgt_seat)
	strike.modulate.a = 0.0
	strike.scale = Vector2(0.98, 0.98)
	_add_motion_fx(strike)
	var tw := strike.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(strike, "scale", Vector2(1.05, 1.05), 0.32).set_ease(Tween.EASE_OUT)
	tw.tween_property(strike, "modulate:a", 1.0, 0.075)
	tw.tween_property(strike, "modulate:a", 0.0, 0.20).set_delay(0.13)
	tw.chain().tween_callback(strike.queue_free)


func fx_skill_banner(seat: int, skill_name: String, important: bool = false) -> void:
	if auto_all or not is_instance_valid(skill_notice_panel) or seat < 0 or seat >= players.size():
		return
	if skill_notice_tween and skill_notice_tween.is_valid():
		skill_notice_tween.kill()
	_hide_turn_banner()
	skill_notice_actor.text = "你 · %s" % String(players[0]["char_name"]) if seat == 0 else _event_seat_name(seat)
	skill_notice_title.text = "发动「%s」" % skill_name
	skill_notice_title.add_theme_color_override("font_color", Color("#ffdda3") if important else Color("#efe0ff"))
	var width := skill_notice_panel.size.x - 28.0
	for line in [skill_notice_actor, skill_notice_title]:
		var preferred_size := 24 if line == skill_notice_actor else 30
		var measured_width := font_bold.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, preferred_size).x
		var fitted_size := maxi(18, floori(preferred_size * width / maxf(width, measured_width)))
		line.add_theme_font_size_override("font_size", fitted_size)
		line.add_theme_font_override("font", Art.compact_bold_font(fitted_size))
	var motion := _motion_enabled()
	skill_notice_panel.modulate.a = 0.66 if motion else 1.0
	skill_notice_panel.show()
	skill_notice_tween = skill_notice_panel.create_tween()
	if motion:
		skill_notice_tween.tween_property(skill_notice_panel, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	skill_notice_tween.tween_interval(0.05 if fast else 2.0)
	if motion:
		skill_notice_tween.tween_property(skill_notice_panel, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	skill_notice_tween.tween_callback(skill_notice_panel.hide)


func show_turn_banner() -> void:
	if turn_banner == null or turn_banner_panel == null:
		return
	_hide_turn_banner()
	if is_instance_valid(skill_notice_panel) and skill_notice_panel.visible:
		return
	turn_banner.text = "轮到你了"
	var motion := _motion_enabled()
	var top := safe_insets.y + table_hud_height + 14.0
	turn_banner_panel.position.y = top + (6.0 if motion else 0.0)
	turn_banner_panel.modulate.a = 1.0
	turn_banner_panel.show()
	turn_banner_tween = turn_banner_panel.create_tween()
	if motion:
		turn_banner_tween.tween_property(turn_banner_panel, "position:y", top, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	turn_banner_tween.tween_interval(0.95)
	if motion:
		turn_banner_tween.tween_property(turn_banner_panel, "modulate:a", 0.0, 0.18)
	turn_banner_tween.tween_callback(turn_banner_panel.hide)


func _hide_turn_banner() -> void:
	if turn_banner_tween and turn_banner_tween.is_valid():
		turn_banner_tween.kill()
	turn_banner_tween = null
	if is_instance_valid(turn_banner_panel):
		turn_banner_panel.hide()


func _event_seat_name(seat: int) -> String:
	if seat < 0 or seat >= players.size():
		return ""
	return "你" if seat == 0 else "%d号位 %s" % [seat + 1, String(players[seat]["char_name"])]


func _show_play_callout(card: Dictionary, actor: String, target: String, detail: String) -> void:
	if auto_all or card.is_empty():
		return
	var cname := String(card.get("name", ""))
	var kind := CardDefs.kind_of(cname)
	var action_txt := ""
	var result_txt := ""
	if target != "":
		action_txt = "%s 使用「%s」" % [actor, cname]
		result_txt = "目标  %s" % target
	elif detail == "重铸":
		action_txt = "%s 重铸「%s」" % [actor, cname]
	elif detail == "自救":
		action_txt = "%s 使用「%s」自救" % [actor, cname]
	elif detail == "展示":
		action_txt = "%s 展示「%s」" % [actor, cname]
	elif not detail.is_empty():
		action_txt = "%s 响应「%s」" % [actor, cname]
	elif kind in ["武器", "防具", "饰品", "宝物"]:
		action_txt = "%s 装备「%s」" % [actor, cname]
	else:
		action_txt = "%s 打出「%s」" % [actor, cname]
	_show_play_notice(action_txt, result_txt)


func _show_play_notice(text: String, result: String = "", result_color: Color = Color("#ffe5ab")) -> void:
	if auto_all or not is_instance_valid(play_callout_panel):
		return
	_hide_play_notice()
	play_callout_label.text = text
	play_result_label.text = result
	play_result_label.visible = not result.is_empty()
	play_result_label.add_theme_color_override("font_color", result_color)
	var text_width := play_callout_panel.size.x - 32.0
	for line in [play_callout_label, play_result_label]:
		var preferred_size := 32 if line == play_callout_label else 28
		var font := Art.compact_bold_font(preferred_size)
		var measured_width := font.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, preferred_size).x
		var fitted_size := maxi(preferred_size - 5, floori(preferred_size * text_width / maxf(text_width, measured_width)))
		line.add_theme_font_override("font", Art.compact_bold_font(fitted_size))
		line.add_theme_font_size_override("font_size", fitted_size)
	play_callout_panel.visible = true
	play_callout_panel.modulate = Color(1, 1, 1, 1)
	play_callout_tween = create_tween()
	play_callout_tween.tween_interval(0.05 if fast else 3.0)
	play_callout_tween.tween_property(play_callout_panel, "modulate:a", 0.0, 0.26)
	play_callout_tween.tween_callback(func() -> void:
		if play_callout_panel != null and is_instance_valid(play_callout_panel):
			play_callout_panel.visible = false)


func _hide_play_notice() -> void:
	if play_callout_tween and play_callout_tween.is_valid():
		play_callout_tween.kill()
	if is_instance_valid(play_callout_panel):
		play_callout_panel.hide()


func _show_resolved_health(data: Dictionary, damage: bool) -> void:
	var recipient := _event_seat_name(int(data.get("seat", -1)))
	if recipient == "":
		return
	var source := _event_seat_name(int(data.get("src_seat", -1)))
	var cause := String(data.get("cause", ""))
	var effect := "伤害" if damage else "回复"
	var title := "%s结算" % effect
	if cause != "":
		title = "「%s」结算" % cause if source == "" else "%s ·「%s」" % [source, cause]
	elif source != "":
		title = "%s 造成伤害" % source if damage else "%s 提供回复" % source
	if damage and bool(data.get("spread", false)):
		effect = "传导"
	var sign := "−" if damage else "+"
	var result := "%s  %s %s%d 体力" % [effect, recipient, sign, int(data["num"])]
	_show_play_notice(title, result, Color("#ffc1ce") if damage else Color("#c7f6d5"))


func _eng_fx(kind: String, data: Dictionary) -> void:
	if fx_root == null or players.is_empty():
		return
	var seat := int(data.get("seat", -1))
	match kind:
		"damage":
			var nat := String(data.get("nature", ""))
			var dcol := _attack_color(nat, Color(1.0, 0.44, 0.51))
			var amount := int(data["num"])
			_show_resolved_health(data, true)
			if bool(data.get("attack_hit", false)):
				fx_slash(seat, dcol)
			fx_flash(seat, dcol)
			fx_float(seat, "−%d" % amount, dcol, 64 if amount >= 2 else 54, 34.0)
			if seat == 0:
				_battle_haptic(28 if amount >= 2 else 20)
			var impact_sound := "hit_heavy" if amount >= 2 else "hit"
			match nat:
				"火": impact_sound = "fire_hit"
				"雷": impact_sound = "thunder_hit"
				"冰": impact_sound = "ice_hit"
			play_sfx(impact_sound, 1.0 if amount >= 2 and nat != "" else 0.0)
			if seat == 0 or rng.randf() < 0.78:
				play_cv_battle(seat, "hurt", 2)
		"heal":
			_show_resolved_health(data, false)
			fx_float(seat, "+%d" % int(data["num"]), Color(0.25, 0.78, 0.38), 56)
			fx_flash(seat, Color(0.4, 1.0, 0.55))
			play_sfx("heal")
			if rng.randf() < 0.65:
				play_cv_battle(seat, "heal", 1)
		"draw":
			fx_draw_fly(seat, int(data.get("n", data.get("num", 1))))
			play_sfx("draw")
		"skill":
			_count_skill(seat, String(data.get("name", "")))
			var sid_fx := String(data.get("sid", ""))
			var important := bool(data.get("big", false)) or sid_fx in ["shuangfeng", "mingzha", "xinyan", "canyue"]
			fx_skill_banner(seat, String(data["name"]), important)
			play_sfx("skill")
			play_cv_battle(seat, "skill", 3 if important else 2)
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
			var a_src := int(data.get("src_seat", -1))
			var a_tgt := int(data.get("tgt_seat", -1))
			var extra := bool(data.get("extra_target", false))
			_add_designated_target(a_tgt)
			if _event_seat_name(a_src) != "" and _event_seat_name(a_tgt) != "":
				_show_play_callout({"name": "突击"}, _event_seat_name(a_src), _event_seat_name(a_tgt), "")
			fx_attack_fx(a_src, a_tgt, String(data.get("nature", "")))
			if not extra:
				play_sfx("slash")
				if a_src == 0 or rng.randf() < 0.80:
					play_cv_battle(a_src, "attack", 1)
		"yingbian":
			fx_float(seat, String(data.get("text", "应变")), Color(0.95, 0.45, 0.75), 40, 70.0)
			play_sfx("skill")
		"target":
			var source := int(data.get("src_seat", -1))
			var target := int(data.get("tgt_seat", -1))
			var card_name := String(data.get("card", ""))
			_add_designated_target(target)
			if card_name != "" and _event_seat_name(source) != "" and _event_seat_name(target) != "":
				_show_play_callout({"name": card_name}, _event_seat_name(source), _event_seat_name(target), "")
			fx_target_mark(source, target)
		"dodge":
			var dodge_color := Color(0.58, 0.80, 1.0)
			_show_play_notice("%s 成功闪避" % _event_seat_name(seat))
			fx_target_ring(seat, dodge_color)
			fx_float(seat, "闪避", dodge_color, 45, 34.0)
			var barrier := bool(data.get("barrier", false))
			play_sfx("shield_block" if barrier else "dodge")
			if not barrier:
				play_cv_battle(seat, "dodge", 2)
		"dying":
			fx_target_ring(seat, Color(1.0, 0.33, 0.46))
			play_sfx("dying")
			play_cv_battle(seat, "dying", 4)
			fx_dying_show(seat)
		"death":
			_fx_reveal_gem(seat)
			play_sfx("death")
			play_cv_battle(seat, "death", 5)
			if seat == dying_seat:
				fx_dying_hide()
		"revived":
			if seat == dying_seat:
				fx_dying_hide()
			fx_float(seat, "获救！", Color(0.25, 0.78, 0.38), 48, 50.0)
			play_sfx("revive")
			play_cv_battle(seat, "heal", 5)
		"nullify":
			var response := String(data.get("name", "看破"))
			fx_float(seat, response, Color(1.0, 0.82, 0.40), 46, 28.0)
			if response == "看破":
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
		"kill_spree":
			var kcnt := int(data.get("kills", 1))
			var knm := String(data.get("name", ""))
			var ktitle := "首次击破" if kcnt == 1 else "%d 连击破" % kcnt
			fx_spree_banner(ktitle, "%s 已累计击杀 %d 人" % [knm, kcnt])
			play_sfx("spree")
		"awaken":
			var awk_nm := String(data.get("name", "觉醒"))
			var awk_ch := String(data.get("char", ""))
			fx_spree_banner("★ 觉醒 · %s ★" % awk_nm, "%s 突破界限，习得新技能！" % awk_ch)
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
			var sh_now := int(data.get("shield", 0))
			if sh_d < 0:
				_show_play_notice("%s 的护甲" % _event_seat_name(seat), "抵消 %d 点伤害" % -sh_d, Color("#c4ebff"))
			var sh_col := Color(0.35, 0.78, 1.0) if sh_d > 0 else (Color(1.0, 0.56, 0.25) if sh_now == 0 else Color(0.75, 0.85, 0.95))
			var sh_msg := ("🛡护甲+%d" % sh_d) if sh_d > 0 else (("🛡抵消%d·碎甲" % (-sh_d)) if sh_now == 0 else ("🛡抵消%d" % (-sh_d)))
			fx_target_ring(seat, sh_col)
			fx_float(seat, sh_msg, sh_col, 44, 62.0)
			var armor_sound := "shield"
			if sh_d < 0:
				if int(data.get("remaining_damage", 0)) > 0:
					armor_sound = "shield_crack"
				else:
					armor_sound = "shield_break" if sh_now == 0 else "shield_block"
			play_sfx(armor_sound)
		"prevented":
			var prevent_color := Color(0.60, 0.91, 0.86)
			_show_play_notice("%s ·「%s」" % [_event_seat_name(seat), String(data["name"])], "抵消 %d 点伤害" % int(data["num"]), Color("#c4ebff"))
			fx_target_ring(seat, prevent_color)
			fx_float(seat, "%s · 抵消 %d" % [String(data["name"]), int(data["num"])], prevent_color, 40)
			play_sfx("shield_block")
		"mark":
			var mk_n := String(data.get("name", ""))
			var mk_d := int(data.get("delta", 1))
			var mk_v := int(data.get("val", 0))
			var mk_s := ("🪶%s+%d (%d)" % [mk_n, mk_d, mk_v]) if mk_d > 0 else ("🪶%s-%d (%d)" % [mk_n, -mk_d, mk_v])
			fx_float(seat, mk_s, Color(0.95, 0.42, 0.46) if mk_d > 0 else Color(0.95, 0.75, 0.30), 42, 62.0)
		"doubling":
			var dm := int(data.get("mul", 2))
			fx_float(seat, "⚡超级加倍！" if dm >= 4 else "⚡加倍！", Color(1.0, 0.76, 0.18), 48, 70.0)
			play_sfx("skill")
		"open_hand":
			fx_float(seat, "👁 明牌 ×2！", Color(1.0, 0.84, 0.28), 48, 74.0)
			play_sfx("skill")
		"seal":
			fx_float(seat, "❄ 霜封·封技！", Color(0.55, 0.85, 1.0), 44, 64.0)
			play_sfx("skill")


# ---------------- 濒死救援特写 ----------------

func fx_dying_show(seat: int) -> void:
	fx_dying_hide()
	if seat < 0 or seat >= players.size() or not is_instance_valid(fx_root) or auto_all:
		return
	var portrait := seat_panel_of(seat)
	if portrait == null:
		return
	dying_seat = seat
	var holder := PanelContainer.new()
	holder.name = "DyingNotice"
	holder.add_theme_stylebox_override("panel", _tight(style(Color(0.24, 0.08, 0.18, 0.96), 15, Color(1.0, 0.48, 0.55), 2), 16, 5))
	var title := lbl("濒死", 25, Color(1.0, 0.88, 0.89), true, HORIZONTAL_ALIGNMENT_CENTER)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	holder.add_child(title)
	holder.size = holder.get_combined_minimum_size()
	holder.position = portrait.position + Vector2((portrait.size.x - holder.size.x) * 0.5, 10.0)
	fx_root.add_child(holder)
	dying_holder = holder


func fx_dying_hide() -> void:
	if dying_holder != null and is_instance_valid(dying_holder):
		var parent := dying_holder.get_parent()
		if parent != null:
			parent.remove_child(dying_holder)
		dying_holder.queue_free()
	dying_holder = null
	dying_seat = -1


# ---------------- 牌桌音效 ----------------

func _ensure_sfx() -> void:
	if not sfx_players.is_empty():
		var first: AudioStreamPlayer = sfx_players[0]
		if is_instance_valid(first) and first.is_inside_tree() and not first.is_queued_for_deletion():
			return
		for player in sfx_players:
			if is_instance_valid(player) and not player.is_queued_for_deletion():
				player.queue_free()
		sfx_players.clear()
	AudioCfg.ensure()
	for i in 6:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		sfx_players.append(player)
	for key in AudioCfg.SFX_FILES:
		sfx_streams[key] = AudioCfg.sfx_stream(key)


const SFX_MIN_GAP_MS := {"click": 55, "select": 65, "card": 45, "card_slide": 65, "draw": 90}
const SFX_PRIORITIES := {
	"dying": 3, "death": 3, "revive": 3, "win": 3, "lose": 3,
	"hit": 2, "hit_heavy": 2, "fire_hit": 2, "thunder_hit": 2, "ice_hit": 2,
	"dodge": 2, "shield_block": 2, "shield_crack": 2, "shield_break": 2, "skill": 2,
}
var last_haptic_ms := -120


func _battle_haptic(duration_ms: int) -> void:
	if not OS.has_feature("android") or not _motion_enabled():
		return
	var now := Time.get_ticks_msec()
	if now - last_haptic_ms < 120:
		return
	last_haptic_ms = now
	Input.vibrate_handheld(duration_ms)


func play_cv_battle(seat: int, cat: String, priority: int = 1) -> bool:
	if auto_all or seat < 0 or seat >= players.size():
		return false
	var ch_d: Variant = (players[seat] as Dictionary).get("char", {})
	if not (ch_d is Dictionary):
		return false
	var cid := String((ch_d as Dictionary).get("id", ""))
	if cid == "":
		return false
	var now := Time.get_ticks_msec()
	if priority <= 1 and now - int(_cv_seat_ms.get(seat, -1000)) < 820:
		return false
	var clip := AudioCfg.cv_stream(cid, cat)
	if clip == null:
		return false
	var simulated := fast or DisplayServer.get_name() == "headless"
	var played := simulated or AudioCfg.play_cv(self, cid, cat, priority, false)
	if not simulated and (played or not AudioCfg.voice_audible()):
		show_bubble(seat, cat, clip.get_length())
	if not played:
		return false
	cv_played_count += 1
	_cv_seat_ms[seat] = now
	return true


func play_sfx(key: String, gain_db: float = 0.0) -> void:
	if auto_all or fast or not is_inside_tree():
		return
	var stream := sfx_streams.get(key) as AudioStream
	if stream == null:
		return
	sfx_count += 1
	if DisplayServer.get_name() == "headless" or not bool(AudioCfg.get_v("sfx_on")) or float(AudioCfg.get_v("master")) <= 0.001 or float(AudioCfg.get_v("sfx_vol")) <= 0.001:
		return
	var min_gap := int(SFX_MIN_GAP_MS.get(key, 0))
	var now := Time.get_ticks_msec()
	if min_gap > 0 and now - int(_sfx_last_ms.get(key, -min_gap)) < min_gap:
		return
	var priority := int(SFX_PRIORITIES.get(key, 1))
	var lowest := priority
	var candidate: AudioStreamPlayer
	for player: AudioStreamPlayer in sfx_players:
		if not is_instance_valid(player) or not player.is_inside_tree() or player.is_queued_for_deletion():
			continue
		if not player.playing:
			candidate = player
			break
		var active_priority := int(player.get_meta("priority", 1))
		if active_priority < lowest:
			lowest = active_priority
			candidate = player
	if candidate != null:
		_sfx_last_ms[key] = now
		candidate.set_meta("priority", priority)
		candidate.volume_db = gain_db
		# 轻微变化只用于频繁短音，保留命中和护甲的固定辨识度。
		candidate.pitch_scale = [0.98, 1.0, 1.02][sfx_count % 3] if min_gap > 0 else 1.0
		candidate.stream = stream
		candidate.play()


func show_match_banner() -> void:
	if match_banner == null:
		return
	match_banner.text = "对 局 开 始"
	if match_banner_tween and match_banner_tween.is_valid():
		match_banner_tween.kill()
	match_banner.modulate = Color(1, 1, 1, 0)
	match_banner.scale = Vector2(0.94, 0.94) if _motion_enabled() else Vector2.ONE
	match_banner.pivot_offset = Vector2(960, 60)
	match_banner_tween = create_tween()
	match_banner_tween.tween_property(match_banner, "modulate:a", 1.0, 0.15)
	if _motion_enabled():
		match_banner_tween.parallel().tween_property(match_banner, "scale", Vector2.ONE, 0.16)
	match_banner_tween.tween_interval(0.6)
	match_banner_tween.tween_property(match_banner, "modulate:a", 0.0, 0.3)


var _emote_cycle := 0


func _throw_seat_emote(seat_idx: int) -> void:
	if fx_root == null or seat_idx <= 0 or seat_idx >= players.size():
		return
	var emotes := [
		{"icon": "🌹", "txt": "🌹 赠花 · 好感+2！", "col": Color(1.0, 0.45, 0.68), "sfx": "heal", "cat": "heal"},
		{"icon": "💖", "txt": "💖 狂热应援 · 好感+2！", "col": Color(1.0, 0.62, 0.82), "sfx": "skill", "cat": "skill"},
		{"icon": "🥿", "txt": "🥿 吃我一记爱心拖鞋！", "col": Color(1.0, 0.78, 0.32), "sfx": "hit", "cat": "hurt"},
	]
	var em: Dictionary = emotes[_emote_cycle % emotes.size()]
	_emote_cycle += 1
	var cid := String(players[seat_idx]["char"].get("id", ""))
	if String(em["icon"]) != "🥿":
		Meta.touch_char(cid, 2)
	var feedback := func() -> void:
		fx_float(seat_idx, String(em["txt"]), em["col"], 36, 34.0)
		play_sfx(String(em["sfx"]))
		play_cv_battle(seat_idx, String(em["cat"]), 2)
	if not _motion_enabled():
		feedback.call()
		return
	var fly := lbl(String(em["icon"]), 56, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	fly.position = Vector2(148, 788)
	fly.size = Vector2(64, 64)
	_add_motion_fx(fly)
	play_sfx("play")
	var tw := fly.create_tween()
	tw.tween_property(fly, "position", seat_center(seat_idx) - Vector2(32, 32), CARD_FLY_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(feedback)
	tw.tween_callback(fly.queue_free)


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
		out.append({"sid": sid, "name": nm, "text": String(sk2.get("text", def.get("text", "（暂无说明）"))), "active": def.has("active")})
	if sids.is_empty():
		for sk3 in (p["char"].get("skills", []) as Array):
			out.append({"sid": String(sk3.get("sid", "")), "name": String(sk3["name"]), "text": String(sk3["text"]), "active": sk3.has("btn")})
	if game_mode == "doudizhu" and String(p.get("identity", "")) == "地主":
		for d in DDZ_SKILLS:
			out.append({"name": d["name"], "text": d["text"], "active": false})
	return out


func _intro_skill_sid(sid: String) -> Dictionary:
	if players.is_empty():
		return {}
	var me: Dictionary = players[0]
	for sk in _skills_of(me):
		if String(sk.get("sid", "")) == sid:
			var def: Dictionary = eng.skill_lib.get(sid, {}) if eng != null else {}
			var selection: Dictionary = eng.active_selection(me, sid) if eng != null else {}
			var nm := String(sk["name"])
			return IntroPop.skill_spec(nm, String(sk["text"]), bool(sk["active"]), _skill_used_text(0, nm), def, selection)
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
	var p_mk2 := int((p.get("marks", {}) as Dictionary).get("影羽", 0))
	if p_mk2 > 0:
		st.append("🪶影羽 %d/4（手牌上限+%d）" % [p_mk2, p_mk2])
	if bool(p.get("skills_sealed", false)):
		st.append("❄ 本回合非锁定技失效")
	var ddz_ally2 := game_mode == "doudizhu" and String(me["identity"]) == "农民" and String(p["identity"]) == "农民"
	var see_ally := ((game_mode == "twovtwo" or game_mode == "boss") or ddz_ally2) and seat != 0 and String(p["identity"]) == String(me["identity"])
	var see_open: bool = game_mode == "doudizhu" and eng != null and eng.ddz_open_seats.has(seat)
	if see_ally or see_open:
		var mcards: Array = []
		for mc in p["hand"]:
			mcards.append(card_text(mc))
		var htag := "队友手牌：" if see_ally else "明牌手牌："
		st.append(htag + ("、".join(PackedStringArray(mcards)) if not mcards.is_empty() else "无"))
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
		first_hint_label = lbl("长按手牌或角色\n查看详细效果", 26, _table_text, true, HORIZONTAL_ALIGNMENT_CENTER)
		first_hint_label.name = "FirstHint"
		first_hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		first_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		first_hint_label.mouse_filter = MOUSE_FILTER_IGNORE
		first_hint_label.add_theme_stylebox_override("normal", _tight(style(_table_surface, 14, _table_edge, 1, true), 18, 9))
		add_child(first_hint_label)
	first_hint_label.size = Vector2(374, 92)
	first_hint_label.position = Vector2(history_btn.position.x + history_btn.size.x - first_hint_label.size.x,
		history_btn.position.y + history_btn.size.y + 12.0)
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
var auto_confirm := false
var double_tap_play := false
var reduced_motion := false
var reduced_motion_check: CheckButton
var _last_card_tap_ms := 0
var double_tap_check: CheckButton = null
var extra_target := -1          # 多目标牌（羁绊锁链）的第二个目标
var skill_mode := ""            # 技能选择状态中的技能 sid
var skill_card: Dictionary = {} # 技能选择状态中选中的手牌
var pre_answers: Array = []     # 出牌确认时已选好的附加作答（羁绊锁链第二目标）
var resp_pref_card: Dictionary = {}  # 响应时选中的那张牌（引擎优先打出它）
var ask_mode := ""
var ask_prompt := ""
var ask_context := ""
var ask_confirm_text := ""
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


static func double_tap_saved() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return false
	return bool(cf.get_value("play", "double_tap_play", false))


static func save_double_tap(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("play", "double_tap_play", on)
	cf.save(SETTINGS_PATH)


static func reduced_motion_saved() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return false
	return bool(config.get_value("play", "reduced_motion", false))


func set_reduced_motion(on: bool, persist: bool = true) -> void:
	reduced_motion = on
	if persist:
		var config := ConfigFile.new()
		config.load(SETTINGS_PATH)
		config.set_value("play", "reduced_motion", on)
		config.save(SETTINGS_PATH)
	if on:
		_skip_transient_motion()
	if is_instance_valid(reduced_motion_check):
		reduced_motion_check.set_pressed_no_signal(on)


func set_double_tap(on: bool, persist: bool = true) -> void:
	double_tap_play = on
	if persist:
		save_double_tap(on)
	if double_tap_check != null and is_instance_valid(double_tap_check) and double_tap_check.button_pressed != on:
		double_tap_check.set_pressed_no_signal(on)


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
		if double_tap_check != null and is_instance_valid(double_tap_check):
			double_tap_check.set_pressed_no_signal(double_tap_play)
		if is_instance_valid(reduced_motion_check):
			reduced_motion_check.set_pressed_no_signal(reduced_motion)
		move_child(settings_panel, get_child_count() - 1)


func _build_settings_panel() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.position = Vector2(safe_insets.x + 26.0, safe_insets.y + table_hud_height + 12.0)
	settings_panel.custom_minimum_size = Vector2(660, 0)
	settings_panel.mouse_filter = MOUSE_FILTER_STOP
	settings_panel.add_theme_stylebox_override("panel", _tight(style(Palette.MILK, 22, Palette.LILAC_EDGE, 1, true), 22, 14))
	settings_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	settings_panel.add_child(vb)
	var tl := lbl("对局设置", 28, C_TABLE_ACTION, true)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	vb.add_child(tl)
	var chk_row := HBoxContainer.new()
	chk_row.add_theme_constant_override("separation", 20)
	vb.add_child(chk_row)
	auto_confirm_check = CheckButton.new()
	auto_confirm_check.focus_mode = Control.FOCUS_NONE
	auto_confirm_check.text = "自动确认"
	auto_confirm_check.custom_minimum_size.y = 46
	auto_confirm_check.add_theme_font_override("font", font_bold)
	auto_confirm_check.add_theme_font_size_override("font_size", 24)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		auto_confirm_check.add_theme_color_override(k, C_INK)
	auto_confirm_check.set_pressed_no_signal(auto_confirm)
	auto_confirm_check.toggled.connect(func(on: bool) -> void:
		set_auto_confirm(on)
		show_hint("自动确认已开启。选好后会自动出牌或作答。" if on else "自动确认已关闭。选好后仍需确认操作。"))
	chk_row.add_child(auto_confirm_check)
	double_tap_check = CheckButton.new()
	double_tap_check.focus_mode = Control.FOCUS_NONE
	double_tap_check.text = "双击手牌直出"
	double_tap_check.custom_minimum_size.y = 46
	double_tap_check.add_theme_font_override("font", font_bold)
	double_tap_check.add_theme_font_size_override("font_size", 24)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		double_tap_check.add_theme_color_override(k, C_INK)
	double_tap_check.set_pressed_no_signal(double_tap_play)
	double_tap_check.toggled.connect(func(on: bool) -> void:
		set_double_tap(on)
		show_hint("双击手牌直出：%s" % ("已开启——快速双击已选中的牌可直接打出" if on else "已关闭")))
	chk_row.add_child(double_tap_check)
	reduced_motion_check = CheckButton.new()
	reduced_motion_check.name = "ReducedMotion"
	reduced_motion_check.focus_mode = Control.FOCUS_NONE
	reduced_motion_check.text = "减少动态效果"
	reduced_motion_check.custom_minimum_size.y = 46
	reduced_motion_check.add_theme_font_override("font", font_bold)
	reduced_motion_check.add_theme_font_size_override("font_size", 24)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		reduced_motion_check.add_theme_color_override(state, C_INK)
	reduced_motion_check.set_pressed_no_signal(reduced_motion)
	reduced_motion_check.toggled.connect(func(on: bool) -> void: set_reduced_motion(on))
	chk_row.add_child(reduced_motion_check)
	var desc := lbl("自动确认：选够目标自动提交；双击直出：450ms 内双击同一张牌直出。", 19, C_INK_SOFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_OFF
	vb.add_child(desc)
	# V0.32/V0.44 声音设置：总音量、音效/语音/背景音乐开关与音量
	var at := lbl("声音与配音", 24, C_TABLE_ACTION, true)
	at.autowrap_mode = TextServer.AUTOWRAP_OFF
	vb.add_child(at)
	build_audio_rows(vb)
	var bgm_hb := HBoxContainer.new()
	bgm_hb.add_theme_constant_override("separation", 12)
	vb.add_child(bgm_hb)
	var bgm_lbl := lbl("配乐曲风", 24, C_INK, true)
	bgm_lbl.custom_minimum_size = Vector2(190, 0)
	bgm_hb.add_child(bgm_lbl)
	var bgm_btn := plain_btn(MusicDirector.style_label(), Palette.LILAC_SOFT, C_INK, 22)
	bgm_btn.custom_minimum_size = Vector2(300, 48)
	bgm_btn.pressed.connect(func() -> void:
		var md := get_tree().get_first_node_in_group("music_director") as MusicDirector
		if md != null:
			bgm_btn.text = md.cycle_style()
		else:
			var nx := "classic" if MusicDirector.style_key() == "sakura" else "sakura"
			AudioCfg.set_v("bgm_style", nx)
			bgm_btn.text = MusicDirector.style_label()
		show_hint("已切换背景音乐曲风为：%s" % bgm_btn.text))
	bgm_hb.add_child(bgm_btn)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	var hb_cv := plain_btn("🎙 试听语音", Palette.ROSE_SOFT, C_TABLE_ACTION, 23)
	hb_cv.custom_minimum_size = Vector2(170, 52)
	hb_cv.pressed.connect(func() -> void:
		var cid_t := String(players[0]["char"]["id"]) if not players.is_empty() and players[0].has("char") else "sena"
		if not play_cv_battle(0, "skill", 3):
			AudioCfg.play_cv(self, cid_t, "skill")
		show_hint("正在试听角色战斗语音（请在上方调节语音开关与音量）"))
	hb.add_child(hb_cv)
	var hb1 := plain_btn("新手说明", Palette.SKY_SOFT, C_INK, 24)
	hb1.custom_minimum_size = Vector2(150, 52)
	hb1.pressed.connect(func() -> void:
		settings_panel.visible = false
		open_info_overlay("新手说明", HelpText.bbcode(), true))
	hb.add_child(hb1)
	var hb2 := plain_btn("关闭", Palette.LILAC_SOFT, C_INK, 24)
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
			cb.custom_minimum_size = Vector2(190, 46)
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
		sl.custom_minimum_size = Vector2(360, 34)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.focus_mode = Control.FOCUS_NONE
		sl.set_value_no_signal(float(AudioCfg.get_v(vol_key)))
		sl.value_changed.connect(func(v: float) -> void: AudioCfg.set_v(vol_key, v))
		sl.drag_ended.connect(func(_c: bool) -> void: play_sfx("click"))
		hb.add_child(sl)
		audio_sliders[vol_key] = sl
	var note := lbl("音乐、音效和语音可分别调节。角色开口时，配乐会轻轻退后。", 18, C_INK_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_OFF
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
		return eng != null and eng.active_choice_is_valid(players[0], skill_mode, skill_card, sel_target)
	if spear_targeting or muniu_targeting:
		return sel_target >= 0 and target_candidates.has(sel_target) and (muniu_targeting or spear_cards.size() == 2)
	if muniu_storing:
		return eng != null and equip_name(players[0], "treasure") == "木牛流马" and not selected_card.is_empty() and _hand_has(selected_card)
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
	if skill_mode == "" and not spear_targeting and not muniu_targeting and not muniu_storing and card_max_targets(selected_card) >= 2:
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
			return "「%s」请选择%s（%s）" % [nm, card_desc, String(spec.get("card_role", "作为代价"))]
		if spec["targets"] != null and sel_target < 0:
			return "「%s」：请选择 1 名标有「可选」的角色" % nm
		var parts: Array = []
		if need_card:
			parts.append("用 %s" % card_text(skill_card))
		if spec["targets"] != null:
			parts.append("对 %s" % _tgt_name(sel_target))
		return "%s发动「%s」" % [" ".join(parts) + " " if not parts.is_empty() else "", nm]
	if spear_targeting:
		if sel_target < 0:
			return "「合璧长枪」：请选择 1 名目标，再点选两张要拼的手牌"
		if spear_cards.size() < 2:
			return "对 %s 使用「合璧长枪」：请再点选 %d 张手牌（已选 %d/2）" % [_tgt_name(sel_target), 2 - spear_cards.size(), spear_cards.size()]
		return "用 %s 和 %s 拼成突击，对 %s 出牌" % [card_text(spear_cards[0]), card_text(spear_cards[1]), _tgt_name(sel_target)]
	if muniu_targeting:
		if sel_target < 0:
			return "「木牛流马」：请选择 1 名要转交的角色"
		return "把木牛流马转交给 %s" % _tgt_name(sel_target)
	if muniu_storing:
		if selected_card.is_empty():
			return "「木牛流马」：请选择 1 张手牌存粮"
		return "把 %s 存入木牛流马" % card_text(selected_card)
	if selected_card.is_empty():
		return ""
	var cn := String(selected_card["name"])
	if card_needs_target(selected_card):
		var mx := card_max_targets(selected_card)
		if sel_target < 0:
			return "「%s」：请选择 %s 名目标（标有「可选」）%s" % [cn, "1~2" if mx >= 2 else "1", "；也可点「重铸」弃置并摸 1 张" if eng != null and eng.can_recast(selected_card) else ""]
		var who := _tgt_name(sel_target)
		if extra_target >= 0:
			who += "、" + _tgt_name(extra_target)
		var more := "（可再选 1 名）" if mx >= 2 and extra_target < 0 and target_candidates.size() >= 2 else ""
		return "对 %s 使用「%s」%s" % [who, cn, more]
	if card_kind(selected_card) in ["武器", "防具", "饰品", "宝物"]:
		return "装备「%s」" % cn
	return "使用「%s」" % cn


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


func _commit_muniu_store() -> void:
	var card := selected_card
	selected_card = {}
	muniu_storing = false
	hide_prompt()
	eng.muniu_store(players[0], card)
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


# 规则层提供候选角色；这里转换为牌桌使用的座位号。
func _skill_ui_spec(sid: String) -> Dictionary:
	if eng == null or players.is_empty():
		return {"card": "none", "targets": null}
	var spec: Dictionary = eng.active_selection(players[0], sid)
	if spec["targets"] != null:
		spec["targets"] = (spec["targets"] as Array).map(func(t: Dictionary) -> int: return int(t["seat"]))
	return spec


func _skill_card_ok(c: Dictionary) -> bool:
	return skill_mode != "" and eng != null and eng.active_card_matches(c, String(_skill_ui_spec(skill_mode)["card"]))


func _enter_skill_mode(sid: String) -> void:
	if eng == null or players.is_empty() or not eng.can_use_active(players[0], sid):
		show_hint("当前无法发动这个技能")
		return
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
	play_sfx("select")
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
	play_sfx("select")
	_show_sel_hint()
	_queue_refresh()
	_maybe_auto_confirm()


func _commit_skill() -> void:
	var sid := skill_mode
	var spec := _skill_ui_spec(sid)
	var choice := {}
	if String(spec["card"]) != "none":
		choice["card"] = skill_card
	if spec["targets"] != null:
		choice["target"] = sel_target
	skill_mode = ""
	skill_card = {}
	targeting = false
	target_candidates = []
	sel_target = -1
	hide_prompt()
	interactive = false
	end_play_btn.disabled = true
	refresh()
	await eng.use_active_skill(players[0], sid, choice)
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


func _make_prompt_button(label: String, prominent: bool = false) -> Button:
	var button := _make_action_btn(label, C_TABLE_ACTION, C_WHITE) if prominent else _make_action_btn(label, _table_button, _table_text)
	button.custom_minimum_size = Vector2(clampf(64.0 + label.length() * 24.0, 136.0, 360.0), TABLE_ACTION_H)
	button.add_theme_font_size_override("font_size", 21 if label.length() > 10 else 26)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = label
	return button


class PromptChoiceScroll extends ScrollContainer:
	const SWIPE_THRESHOLD := 18.0
	var _press_control: Control
	var _press_position := Vector2.ZERO
	var _press_scroll := 0
	var _touch_index := -1
	var _swiping := false

	func watch_choice(button: Button) -> void:
		button.gui_input.connect(_choice_input.bind(button))

	func _gui_input(event: InputEvent) -> void:
		_choice_input(event, self)

	func _start_press(control: Control, point: Vector2) -> void:
		_press_control = control
		_press_position = point
		_press_scroll = scroll_horizontal
		_swiping = false

	func _move_press(point: Vector2) -> void:
		var movement := point - _press_position
		if not _swiping and movement.length() >= SWIPE_THRESHOLD:
			_swiping = true
			if _press_control is Button:
				_press_control.notification(Control.NOTIFICATION_SCROLL_BEGIN)
			if IntroPop.inst != null:
				IntroPop.inst.cancel_longpress()
		if _swiping:
			scroll_horizontal = roundi(float(_press_scroll) - movement.x)

	func _tap_choice(button: Button) -> void:
		if is_instance_valid(button) and button.is_inside_tree() and not button.disabled:
			button.pressed.emit()

	func _choice_input(event: InputEvent, control: Control) -> void:
		# 手机触摸会生成鼠标事件；只处理一份，避免同一划动重复滚动。
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_touch_index = -1
				_start_press(control, control.get_global_transform_with_canvas() * event.position)
			elif _press_control == control:
				var button := control as Button
				if button != null and event.device == InputEvent.DEVICE_ID_EMULATION:
					# 等原生触摸释放再触发按钮，以免作答时提前销毁触摸焦点。
					if button.button_pressed and not _swiping and not event.canceled and Rect2(Vector2.ZERO, button.size).has_point(event.position):
						_tap_choice.call_deferred(button)
					button.notification(Control.NOTIFICATION_SCROLL_BEGIN)
				elif button != null and event.canceled:
					button.notification(Control.NOTIFICATION_SCROLL_BEGIN)
				_press_control = null
			if control == self:
				accept_event()
		elif event is InputEventMouseMotion and _press_control == control and _touch_index == -1:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT and event.global_position != IntroPop.FAKE_POS:
				_move_press(control.get_global_transform_with_canvas() * event.position)
			if control == self:
				accept_event()
		elif not Input.emulate_mouse_from_touch:
			# 未开启触摸模拟时，原生触摸仍可滑动与点选。
			if event is InputEventScreenTouch:
				if event.pressed and _touch_index == -1:
					_touch_index = event.index
					_start_press(control, control.get_global_transform_with_canvas() * event.position)
				elif not event.pressed and event.index == _touch_index:
					var choice := control as Button
					var tap: bool = not _swiping and not event.canceled and _press_control == control
					_touch_index = -1
					_press_control = null
					if tap and choice != null and Rect2(Vector2.ZERO, choice.size).has_point(event.position):
						_tap_choice(choice)
			elif event is InputEventScreenDrag and event.index == _touch_index and _press_control == control:
				_move_press(control.get_global_transform_with_canvas() * event.position)


func _fit_prompt_btns() -> void:
	var buttons := prompt_btns.get_children()
	if buttons.is_empty():
		return
	var fixed_count := 1 if ask_confirm_btn != null or discard_mode else 0
	if fixed_count == 1 and buttons.size() >= 2 and bool(buttons[1].get_meta("ask_decline", false)):
		fixed_count = 2
	var required := float(buttons.size() - 1) * TABLE_ACTION_GAP
	for i in buttons.size():
		var button := buttons[i] as Button
		if i < fixed_count:
			_size_table_action(button)
		else:
			button.custom_minimum_size.y = TABLE_ACTION_H
		required += button.get_combined_minimum_size().x
	if required <= prompt_action_width:
		prompt_btns.size = Vector2(prompt_action_width, TABLE_ACTION_H)
		return
	var choices := buttons.slice(fixed_count)
	if choices.is_empty():
		return
	var scroll := PromptChoiceScroll.new()
	scroll.name = "PromptChoiceScroll"
	scroll.custom_minimum_size = Vector2(100, TABLE_ACTION_H)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	scroll.add_child(row)
	prompt_btns.add_child(scroll)
	for button: Button in choices:
		button.reparent(row, false)
		button.custom_minimum_size.y = TABLE_ACTION_H - 16.0
		scroll.watch_choice(button)
	# 选项移入滚动区后再缩回固定宽度，此前容器会受所有按钮的最小尺寸限制。
	prompt_btns.size = Vector2(prompt_action_width, TABLE_ACTION_H)
	if ask_context == "":
		ask_context = "可左右滑动查看更多选项"
		show_hint(ask_prompt, ask_context)


func _build_select_ask(options: Array) -> void:
	ask_confirm_btn = _make_prompt_button(ask_confirm_text, true)
	ask_confirm_btn.disabled = true
	ask_confirm_btn.tooltip_text = "先选一张亮起的手牌" if ask_mode == "respond" else "先选择一项"
	_bind_press_feedback(ask_confirm_btn, _ask_confirm, 18)
	prompt_btns.add_child(ask_confirm_btn)
	for opt in options:
		var lab := String(opt["label"])
		var value: Variant = opt["value"]
		if ask_mode == "respond" and value is bool and bool(value):
			continue
		var button := _make_prompt_button(lab)
		var decline := _is_cancel_val(value)
		if decline or ask_mode == "respond":
			button.pressed.connect(func() -> void: _on_decided(value))
		else:
			button.pressed.connect(func() -> void: _ask_select(value))
			ask_opt_btns.append({"btn": button, "value": value})
		_attach_option_intro(button, lab, value)
		prompt_btns.add_child(button)
		if decline:
			button.set_meta("ask_decline", true)
			prompt_btns.move_child(button, 1)


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
		play_sfx("select")
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
	ask_context = ""
	ask_options = []
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
		ask_confirm_btn.tooltip_text = "" if ask_sel_has else ("先选一张亮起的手牌" if ask_mode == "respond" else "先选择一项")
	for e in ask_opt_btns:
		var b: Button = e["btn"]
		if not is_instance_valid(b):
			continue
		var on := ask_sel_has and _ask_same(ask_sel_val, e["value"])
		if bool(b.get_meta("ask_selected", false)) == on:
			continue
		b.set_meta("ask_selected", on)
		var selected_bg := Palette.NIGHT_PANEL.lerp(C_TABLE_ACTION, 0.52) if _night_ui else Palette.ROSE_SOFT
		var bg := selected_bg if on else _table_button
		var edge := Palette.ROSE_EDGE if on else _table_edge
		_set_btn_theme(b, bg, edge, _table_text, 19, 2 if on else 1, false, Vector2i(14, 10), Palette.ROSE_EDGE)
	show_hint("已选 %s" % _ask_sel_label() if ask_sel_has else ask_prompt, ask_context)
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
	fly_from_hand = _hand_flight_origin(_find_wrap(c))
	if not fly_from_hand.is_empty():
		fly_from_hand["card"] = c
	cancel_targeting()
	interactive = false
	_update_action_bar()
	await eng.recast(players[0], c)
	fly_from_hand = {}
	if not game_over and is_inside_tree():
		interactive = true
		maybe_restore_hint()
		refresh()


# ================= 连破与高伤横幅、开局手气卡、选将换批 =================
var luck_btn: Button = null
var lord_pre_char: Dictionary = {}
var draft_my_identity := "主公"


func fx_spree_banner(title_text: String, sub_text: String) -> void:
	if fast or not _can_show_fx():
		return
	var box := PanelContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	var bg_col := Color(0.52, 0.08, 0.16, 0.94)
	var bd_col := Color(1.0, 0.82, 0.32)
	box.add_theme_stylebox_override("panel", style(bg_col, 24, bd_col, 4, true))
	var vb := VBoxContainer.new()
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	var tl := lbl(title_text, 32, Color(1.0, 0.94, 0.72), true, HORIZONTAL_ALIGNMENT_CENTER)
	tl.add_theme_constant_override("outline_size", 8)
	tl.add_theme_color_override("font_outline_color", Color(0.22, 0.04, 0.08, 0.95))
	vb.add_child(tl)
	var sl := lbl(sub_text, 20, Color(1.0, 0.92, 0.88), false, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(sl)
	box.add_child(vb)
	box.size = Vector2(maxf(482.0, box.get_combined_minimum_size().x), 88)
	box.position = Vector2((vw - box.size.x) * 0.5, safe_insets.y + table_hud_height + 22.0)
	box.pivot_offset = box.size * 0.5
	if _motion_enabled():
		_add_motion_fx(box)
	else:
		fx_root.add_child(box)
	var tw := box.create_tween()
	if _motion_enabled():
		box.scale = Vector2(0.96, 0.96)
		tw.tween_property(box, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.78)
	tw.tween_property(box, "modulate:a", 0.0, 0.16)
	tw.tween_callback(box.queue_free)


func _eng_opening_luck() -> void:
	if fast or auto_all or tutorial:
		return
	var previous_timeout := ask_timeout
	ask_timeout = OPENING_LUCK_SECONDS
	await ask("可更换全部起手牌，或保留手牌开始对局。", [{"label": "保留手牌", "value": true}],
		Callable(self, "_add_opening_luck_button"), "opening_luck", {"context": "起手换牌"})
	luck_btn = null
	ask_timeout = previous_timeout


func _add_opening_luck_button() -> void:
	luck_btn = _make_prompt_button("手气卡 ×%d" % eng.opening_luck_left, true)
	luck_btn.pressed.connect(_on_luck_pressed)
	prompt_btns.add_child(luck_btn)
	prompt_btns.move_child(luck_btn, 0)


func _on_luck_pressed() -> void:
	if not asking or ask_mode != "opening_luck" or ask_deadline_ms <= Time.get_ticks_msec() or eng == null or not is_instance_valid(luck_btn):
		return
	var count: int = eng.redraw_opening_hand()
	if count <= 0:
		return
	var left: int = eng.opening_luck_left
	luck_btn.text = "手气卡 ×%d" % left
	luck_btn.disabled = left == 0
	log_msg("「手气卡」：你更换了 %d 张起手牌（本局剩余 %d 次）。" % [count, left])
	show_hint("已更换 %d 张起手牌，剩余 %d 次。" % [count, left], ask_context)
	refresh()


func _on_reshuffle_draft() -> void:
	if draft_layer == null or not draft_layer.visible or _draft_refresh_used or _draft_confirming:
		return
	_draft_refresh_used = true
	draft_refresh_btn.disabled = true
	draft_refresh_btn.text = "本局已换将"
	var pool: Array = []
	for c in Meta.enabled_pool(Characters.LIST):
		if not _draft_candidates.has(c) and String(c["id"]) != String(lord_pre_char.get("id", "")):
			pool.append(c)
	pool.shuffle()
	play_sfx("card")
	_populate_draft_cards(pool.slice(0, mini(3, pool.size())), draft_my_identity)
