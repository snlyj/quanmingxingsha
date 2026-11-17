extends RefCounted
# V0.29 美术统一：卡图/卡背/类型边框色/调色板（规范见 docs/美术规范.md）
# 所有卡图均为本项目原创生成（同名牌共用一张），不含任何第三方游戏素材。

const CardDefsA = preload("res://data/cards.gd")

# ---- 调色板（樱花动漫风）----
const BLOSSOM := Color(1.0, 0.48, 0.66)        # 主色：樱粉
const BLOSSOM_DEEP := Color(0.90, 0.30, 0.50)  # 强调：深樱
const PLUM := Color(0.24, 0.13, 0.25)         # 描边/正文：梅紫
const CREAM := Color(1.0, 0.97, 0.94)         # 面板底：奶白
const GOLD := Color(0.93, 0.70, 0.32)         # 点缀：金
const NIGHT := Color(0.13, 0.09, 0.19)        # 夜间面板底
const RED_SUIT := Color(0.86, 0.18, 0.30)
const BLACK_SUIT := Color(0.18, 0.15, 0.27)

# ---- 牌类型边框色：基本 / 锦囊 / 延时锦囊 / 装备 ----
const FRAME := {
	"基本": Color(0.91, 0.36, 0.50),
	"锦囊": Color(0.55, 0.42, 0.84),
	"延时": Color(0.29, 0.25, 0.56),
	"装备": Color(0.18, 0.60, 0.53),
}

const SLUG := {
	"突击": "tuji",
	"闪避": "shanbi",
	"补给": "buji",
	"特饮": "teyin",
	"结界手环": "jiejie",
	"疾行之靴": "jixing",
	"远行披风": "yuanxing",
	"魔导连弩": "liannu",
	"双生短刃": "shuangsheng",
	"破甲光剑": "pojia",
	"星光长剑": "xingguang",
	"合璧长枪": "hebi",
	"战锤": "zhanchui",
	"星月画戟": "xingyue",
	"破空长弓": "pokong",
	"音波炮": "yinbo",
	"防护立场": "fanghu",
	"银狮铠甲": "yinshi",
	"藤蔓铠甲": "tengman",
	"古锭巨剑": "guding",
	"雷霆法杖": "leiting",
	"银月长枪": "yinyue",
	"七宝利刃": "qibao",
	"钢纹长槊": "gangwen",
	"烂银铠甲": "lanyin",
	"木牛流马": "muniu",
	"太公阴符": "taigong",
	"物资发放": "wuzi",
	"全员休整": "quanyuan",
	"全场乱斗": "luandou",
	"弹幕齐射": "danmu",
	"单挑": "dantiao",
	"灵感爆发": "linggan",
	"悄悄借走": "qiaoqiao",
	"突然检查": "jiancha",
	"借力打力": "jieli",
	"看破": "kanpo",
	"火焰试炼": "huoyan",
	"羁绊锁链": "jiban",
	"声东击西": "shengdong",
	"增兵减灶": "zengbing",
	"弃甲曳兵": "qijia",
	"金蝉脱壳": "jinchan",
	"水淹七军": "shuiyan",
	"逐近弃远": "zhujin",
	"出其不意": "chuqi",
	"洞烛先机": "dongzhu",
	"攻守兼备": "gongshou",
	"进退自如": "jintui",
	"继往开来": "jiwang",
	"沉迷游戏": "chenmi",
	"落雷": "luolei",
	"断粮封锁": "duanliang",
	"草木疑兵": "caomu",
	"浮雷": "fulei",
	"__back__": "back",}

static var _cache: Dictionary = {}


static func group_of(nm: String) -> String:
	var k := String((CardDefsA.DEFS.get(nm, {}) as Dictionary).get("kind", ""))
	if k == "基本牌":
		return "基本"
	if k == "锦囊牌":
		return "锦囊"
	if k == "延时锦囊":
		return "延时"
	if k == "":
		return "基本"
	return "装备"


static func frame_color(nm: String) -> Color:
	return FRAME[group_of(nm)]


static func card_tex(nm: String) -> Texture2D:
	var slug := String(SLUG.get(nm, ""))
	if slug == "":
		return null
	if _cache.has(slug):
		return _cache[slug]
	var path := "res://assets/cards/%s.webp" % slug
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[slug] = t
	return t


static func back_tex() -> Texture2D:
	return card_tex("__back__")


static func suit_sym(suit: String) -> String:
	return String({"红桃": "♥", "方块": "♦", "梅花": "♣", "黑桃": "♠"}.get(suit, ""))


static func point_str(pt: int) -> String:
	if pt <= 0:
		return ""
	return String({1: "A", 11: "J", 12: "Q", 13: "K"}.get(pt, str(pt)))

# ---- V0.31 角色 CG 卡面 ----
# 每名角色一张完整 CG（assets/cg/<id>.webp，864×1152，竖版场景插画）。
# 角色数据里的 focus 是脸部中心（归一化坐标），所有小框都按它裁切：脸放在框高的 face_y 处，保证不被切掉。
const CORNER_TEX = preload("res://assets/ui/frame_corner.png")
const EMBLEM_TEX = preload("res://assets/ui/series_emblem.png")
const PETAL_TEX = preload("res://assets/ui/hp_petal.png")
const RARITY_COL := {"SSR": Color(0.96, 0.72, 0.25), "SR": Color(0.66, 0.50, 0.92), "R": Color(0.45, 0.70, 0.90)}
static var _cg_cache := {}
static var _font_bold: Font = null


static func bold_font() -> Font:
	if _font_bold == null:
		_font_bold = load("res://assets/fonts/NotoSansSC-Bold.otf")
	return _font_bold


# 按目标框宽高比 aspect(w/h) 裁 CG：zoom=显示 CG 高度的比例（1=整张高），face_y=脸在框内的纵向位置
static func cg_crop(ch: Dictionary, aspect: float, zoom: float = 1.0, face_y: float = 0.30) -> Texture2D:
	var path := String(ch.get("portrait", ""))
	var key := "%s@%.3f@%.2f@%.2f" % [path, aspect, zoom, face_y]
	if _cg_cache.has(key):
		return _cg_cache[key]
	var base: Texture2D = load(path) if path != "" and ResourceLoader.exists(path) else null
	if base == null:
		return null
	var sz := base.get_size()
	var f: Vector2 = ch.get("focus", Vector2(0.5, 0.25))
	var h := sz.y * clampf(zoom, 0.2, 1.0)
	var w := h * maxf(aspect, 0.1)
	if w > sz.x:
		w = sz.x
		h = w / maxf(aspect, 0.1)
	var x := clampf(f.x * sz.x - w * 0.5, 0.0, sz.x - w)
	var y := clampf(f.y * sz.y - face_y * h, 0.0, sz.y - h)
	var at := AtlasTexture.new()
	at.atlas = base
	at.region = Rect2(x, y, w, h)
	_cg_cache[key] = at
	return at


# 兼容旧接口：给立绘路径 + 宽高比，返回以脸为中心的上半身裁切
static func bust(path: String, aspect: float) -> Texture2D:
	return cg_crop({"portrait": path, "focus": _focus_of_path(path)}, aspect, 0.55, 0.36)


static func _focus_of_path(path: String) -> Vector2:
	var CharsA = load("res://data/characters.gd")
	for c in CharsA.LIST:
		if String(c["portrait"]) == path:
			return c["focus"]
	return Vector2(0.5, 0.25)


static func _sb(bg: Color, r: int, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(r)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s


# 四角金饰：加到任意矩形控件上（cs=角饰边长）
static func add_corners(parent: Control, sz: Vector2, cs: float, inset: float = -2.0) -> void:
	for k in 4:
		var t := TextureRect.new()
		t.name = "Corner%d" % k
		t.texture = CORNER_TEX
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.size = Vector2(cs, cs)
		t.flip_h = k == 1 or k == 3
		t.flip_v = k >= 2
		t.position = Vector2(inset if not t.flip_h else sz.x - cs - inset, inset if not t.flip_v else sz.y - cs - inset)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(t)


# 竖排名牌（系列徽标 + 竖排名字 + 稀有度），返回 Panel；fs=字号
static func name_plate(ch: Dictionary, fs: int, with_emblem: bool = true) -> Panel:
	var nm := String(ch.get("name", ""))
	var rar := String(ch.get("rarity", "SR"))
	var rc: Color = RARITY_COL.get(rar, RARITY_COL["SR"])
	var w := float(fs) * 1.5
	var em := w - 6.0 if with_emblem else 0.0
	var h := em + nm.length() * fs * 1.08 + fs * 0.9 + 14.0
	var pl := Panel.new()
	pl.name = "Plate"
	pl.size = Vector2(w, h)
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _sb(Color(0.20, 0.10, 0.22, 0.86), int(w * 0.5), rc, 2)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	pl.add_theme_stylebox_override("panel", sb)
	if with_emblem:
		var e := TextureRect.new()
		e.name = "Emblem"
		e.texture = EMBLEM_TEX
		e.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		e.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		e.position = Vector2(3, 3)
		e.size = Vector2(em, em)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pl.add_child(e)
	var l := Label.new()
	l.name = "SeatName"
	var chars := PackedStringArray()
	for ci in nm.length():
		chars.append(nm[ci])
	l.text = "\n".join(chars)
	l.add_theme_font_override("font", bold_font())
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92))
	l.add_theme_color_override("font_outline_color", Color(0.35, 0.12, 0.25))
	l.add_theme_constant_override("outline_size", maxi(3, fs / 6))
	l.add_theme_constant_override("line_spacing", int(-fs * 0.22))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, em + 4.0)
	l.size = Vector2(w, nm.length() * fs * 1.08 + 6.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pl.add_child(l)
	var r := Label.new()
	r.name = "Rarity"
	r.text = rar
	r.add_theme_font_override("font", bold_font())
	r.add_theme_font_size_override("font_size", maxi(11, int(fs * 0.5)))
	r.add_theme_color_override("font_color", rc.lightened(0.35))
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.position = Vector2(0, h - fs * 0.9 - 6.0)
	r.size = Vector2(w, fs * 0.8)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pl.add_child(r)
	return pl


# 完整 CG 卡面：CG + 华丽金框 + 四角饰 + 左侧竖排名牌（徽标/稀有度）+ 体力樱花 + 底部称号。
# opt: zoom(默认 1) / face_y / name(默认 true) / hp(默认 true) / title(默认 size.y>=300) / fs(名字字号)
static func cg_card(ch: Dictionary, size: Vector2, opt: Dictionary = {}) -> Control:
	var root := Control.new()
	root.name = "CgCard"
	root.size = size
	root.custom_minimum_size = size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bw := maxf(3.0, roundf(size.x * 0.022))
	var rarc: Color = RARITY_COL.get(String(ch.get("rarity", "SR")), RARITY_COL["SR"])
	var back := Panel.new()
	back.name = "Back"
	back.size = size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := _sb(Color(0.20, 0.10, 0.22), int(bw * 3), GOLD, int(bw))
	bsb.shadow_color = Color(0.25, 0.08, 0.2, 0.45)
	bsb.shadow_size = int(bw * 2.5)
	back.add_theme_stylebox_override("panel", bsb)
	root.add_child(back)
	var clip := Control.new()
	clip.name = "Clip"
	clip.clip_contents = true
	clip.position = Vector2(bw + 1, bw + 1)
	clip.size = size - Vector2(bw + 1, bw + 1) * 2.0
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(clip)
	var tr := TextureRect.new()
	tr.name = "CG"
	tr.texture = cg_crop(ch, clip.size.x / maxf(clip.size.y, 1.0), float(opt.get("zoom", 1.0)), float(opt.get("face_y", 0.30)))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.size = clip.size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(tr)
	# 底部压暗（称号可读）
	var shade := TextureRect.new()
	shade.name = "Shade"
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.12, 0.05, 0.14, 0.0))
	gr.set_color(1, Color(0.12, 0.05, 0.14, 0.78))
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.position = Vector2(0, clip.size.y * 0.70)
	shade.size = Vector2(clip.size.x, clip.size.y * 0.30)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(shade)
	# 内描边（奶白细线 + 稀有度色）
	var inner := Panel.new()
	inner.name = "Inner"
	inner.position = clip.position
	inner.size = clip.size
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), int(bw * 2), Color(rarc.r, rarc.g, rarc.b, 0.85), maxi(1, int(bw * 0.5))))
	root.add_child(inner)
	add_corners(root, size, clampf(size.x * 0.16, 18.0, 64.0), -bw * 0.4)
	var fs := int(opt.get("fs", clampi(int(size.x * 0.105), 16, 46)))
	if bool(opt.get("name", true)):
		var pl := name_plate(ch, fs, true)
		pl.position = Vector2(bw + 6, bw + 8)
		root.add_child(pl)
		if bool(opt.get("hp", true)):
			var hpv := VBoxContainer.new()
			hpv.name = "HpMarks"
			hpv.add_theme_constant_override("separation", 1)
			hpv.position = Vector2(pl.position.x + (pl.size.x - fs * 0.95) * 0.5, pl.position.y + pl.size.y + 4)
			hpv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for i in int(ch.get("hp", 3)):
				var pt := TextureRect.new()
				pt.texture = PETAL_TEX
				pt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pt.custom_minimum_size = Vector2(fs * 0.95, fs * 0.95)
				pt.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hpv.add_child(pt)
			root.add_child(hpv)
	if bool(opt.get("title", size.y >= 300.0)) and String(ch.get("title", "")) != "":
		var tl := Label.new()
		tl.name = "Title"
		tl.text = String(ch["title"])
		tl.add_theme_font_override("font", bold_font())
		tl.add_theme_font_size_override("font_size", maxi(13, int(fs * 0.62)))
		tl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
		tl.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.2, 0.9))
		tl.add_theme_constant_override("outline_size", 4)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tl.position = Vector2(bw + fs * 1.6, size.y - bw - fs * 1.25)
		tl.size = Vector2(size.x - bw * 2 - fs * 2.1, fs)
		tl.clip_text = true
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tl)
	return root


# 浮在背景图上的标题/说明文字：统一加奶油色描边（昼夜背景都能读清）
static func halo(l: Label, px: int = 8) -> Label:
	l.add_theme_color_override("font_outline_color", Color(1.0, 0.97, 0.94, 0.92))
	l.add_theme_constant_override("outline_size", px)
	return l
