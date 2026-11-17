extends RefCounted

# 全明星杀 · 新引擎核心（按无名杀 noname v1.10.9 结构重构）
# 事件/触发模型对照 noname：game.createEvent + lib.skill.trigger
# 技能定义格式：{name, timings={时机:{who, priority, filter, content, forced}}}
# 本文件只管规则，不碰 UI；一切询问走 ui 回调（键见 set_ui）。

const AI_STALEMATE_ROUND := 25
const AI_REBEL_LORD_BONUS := 4.5

var players: Array = []
var deck: Array = []
var discard_pile: Array = []
var skill_lib: Dictionary = {}
var ui: Dictionary = {}
var log_lines: Array = []
var game_over := false
var winner_text := ""
var turn_player: Dictionary = {}
var round_no := 0
var phase_text := ""
var discard_need := 0  # V0.25：弃牌阶段还需弃几张（仅界面多选用，不影响结算）


func changed() -> void:
	if ui.has("changed"):
		(ui["changed"] as Callable).call()


func pace(sec: float) -> void:
	if ui.has("pace"):
		await (ui["pace"] as Callable).call(sec)


func is_ai(p: Dictionary) -> bool:
	return not (ui.has("is_human") and bool((ui["is_human"] as Callable).call(p)))


func think(min_s: float, max_s: float) -> void:
	await pace(randf_range(min_s, max_s))


var fx_on := false
var turn_hook: Callable = Callable()  # 自测钩子：每个回合开始前与对局结束时调用 (eng, p)；正式对局不设置


func fx(kind: String, data: Dictionary) -> void:
	if fx_on and ui.has("fx"):
		(ui["fx"] as Callable).call(kind, data)


func set_ui(callbacks: Dictionary) -> void:
	ui = callbacks


func log_msg(s: String) -> void:
	log_lines.append(s)
	if ui.has("log"):
		(ui["log"] as Callable).call(s)


func register_skill(sid: String, def: Dictionary) -> void:
	skill_lib[sid] = def


var _skill_owner: RefCounted


func load_skills() -> void:
	var SL = preload("res://scripts/skill_lib.gd")
	_skill_owner = SL.new()
	_skill_owner.register_all(self)


func has_skill(p: Dictionary, sid: String) -> bool:
	return (p["skills"] as Array).has(sid)


func add_skill(p: Dictionary, sid: String) -> void:
	if not has_skill(p, sid):
		(p["skills"] as Array).append(sid)


# ---------- 基础工具 ----------
func is_red(c: Dictionary) -> bool:
	if c.has("color"):  # V0.28：多张牌转化的虚拟牌按共同颜色（无名杀 get.color：颜色不同则无色）
		return String(c["color"]) == "红"
	return String(c["suit"]) == "红桃" or String(c["suit"]) == "方块"


func is_black(c: Dictionary) -> bool:
	if c.has("color"):
		return String(c["color"]) == "黑"
	return not is_red(c)


func card_text(c: Dictionary) -> String:
	var pt := int(c.get("point", 0))
	return "%s%s「%s」" % [String(c["suit"]), str(pt) if pt > 0 else "", String(c["name"])]


# V0.28：多张牌当一张牌使用时的虚拟牌颜色/花色/点数（对照无名杀 get.color/get.suit/get.number：全部相同才保留，否则无色/无花色）
static func shared_color(cards: Array) -> String:
	var col := ""
	for c in cards:
		var r := String(c["suit"]) == "红桃" or String(c["suit"]) == "方块"
		var cc := "红" if r else "黑"
		if col == "":
			col = cc
		elif col != cc:
			return "无"
	return col if col != "" else "无"


static func shared_suit(cards: Array) -> String:
	var su := ""
	for c in cards:
		if su == "":
			su = String(c["suit"])
		elif su != String(c["suit"]):
			return "无色" if shared_color(cards) == "无" else ("红色" if shared_color(cards) == "红" else "黑色")
	return su


static func shared_point(cards: Array) -> int:
	var pt := -1
	for c in cards:
		if pt < 0:
			pt = int(c["point"])
		elif pt != int(c["point"]):
			return 0
	return maxi(pt, 0)


func alive_players() -> Array:
	var out: Array = []
	for p in players:
		if p["alive"]:
			out.append(p)
	return out


func next_alive_seat(from_seat: int) -> int:
	var n := players.size()
	for i in range(1, n + 1):
		var p: Dictionary = players[(from_seat + i) % n]
		if p["alive"]:
			return int(p["seat"])
	return from_seat


# 太公阴符：出牌阶段开始时横置/重置一名角色；结束时可重铸一张手牌
func taigong_start(p: Dictionary) -> void:
	var tr: Dictionary = p["equip"]["treasure"]
	if tr.is_empty() or String(tr["name"]) != "太公阴符" or not p["alive"] or game_over:
		return
	var tgt: Dictionary = {}
	if is_ai(p):
		if bool(p.get("chained", false)):
			tgt = p
		else:
			var best: Dictionary = {}
			for t in players:
				if t != p and t["alive"] and not bool(t.get("chained", false)) and ai_is_enemy(p, t):
					if best.is_empty() or int(t["hp"]) < int(best["hp"]):
						best = t
			tgt = best
	elif ui.has("pick_option"):
		var opts: Array = []
		for t in players:
			if t["alive"]:
				opts.append({"label": "%s（%s）" % [pname(t), "已横置" if bool(t.get("chained", false)) else "未横置"], "value": t})
		opts.append({"label": "不发动", "value": {}})
		var v: Variant = await (ui["pick_option"] as Callable).call(p, opts, "「太公阴符」：出牌阶段开始，可横置或重置一名角色")
		if v is Dictionary and not (v as Dictionary).is_empty():
			tgt = v
	if not tgt.is_empty():
		toggle_chain(tgt)
		log_msg("「太公阴符」：%s %s。" % [pname(p), ("横置了 " + pname(tgt)) if bool(tgt.get("chained", false)) else ("重置了 " + pname(tgt))])


func taigong_end(p: Dictionary) -> void:
	var tr: Dictionary = p["equip"]["treasure"]
	if tr.is_empty() or String(tr["name"]) != "太公阴符" or not p["alive"] or game_over:
		return
	if (p["hand"] as Array).is_empty():
		return
	var do_it := false
	if is_ai(p):
		do_it = (p["hand"] as Array).size() >= 4
	elif ui.has("pick_option"):
		var v: Variant = await (ui["pick_option"] as Callable).call(p, [{"label": "重铸一张手牌", "value": true}, {"label": "不重铸", "value": false}], "「太公阴符」：出牌阶段结束，可重铸一张手牌")
		do_it = bool(v)
	if not do_it:
		return
	var c := {}
	if is_ai(p):
		c = ai_pick_discard(p)
	elif ui.has("choose_discard"):
		c = await (ui["choose_discard"] as Callable).call(p)
	if c.is_empty():
		c = ai_pick_discard(p)
	if not c.is_empty():
		discard_from_hand(p, c)
		draw_cards(p, 1)
		log_msg("「太公阴符」：%s 重铸了 %s。" % [pname(p), card_text(c)])


# 木牛流马：扣置手牌为「粮」，或连粮转交给其他角色
func muniu_store(p: Dictionary, c: Dictionary) -> void:
	var tr: Dictionary = p["equip"]["treasure"]
	if tr.is_empty() or String(tr["name"]) != "木牛流马":
		return
	(p["hand"] as Array).erase(c)
	if not tr.has("stored"):
		tr["stored"] = []
	(tr["stored"] as Array).append(c)
	log_msg("%s 将 %s 扣置于「木牛流马」下（现有 %d 张粮）。" % [pname(p), card_text(c), (tr["stored"] as Array).size()])
	changed()


func muniu_give(p: Dictionary, tgt: Dictionary) -> void:
	var tr: Dictionary = p["equip"]["treasure"]
	if tr.is_empty() or String(tr["name"]) != "木牛流马":
		return
	p["equip"]["treasure"] = {}
	tgt["equip"]["treasure"] = tr
	var n := (tr.get("stored", []) as Array).size()
	log_msg("%s 将「木牛流马」（连同 %d 张粮）转交给 %s。" % [pname(p), n, pname(tgt)])
	changed()


# 飞扬（斗地主地主技能）：判定阶段开始时，弃两张手牌并弃置自己判定区一张牌
func feiyang_offer(p: Dictionary) -> void:
	if (p["judge"] as Array).is_empty() or (p["hand"] as Array).size() < 2 or game_over:
		return
	var do_it := false
	if is_ai(p):
		do_it = (p["hand"] as Array).size() >= 3
	elif ui.has("pick_option"):
		var v: Variant = await (ui["pick_option"] as Callable).call(p, [{"label": "弃置两张手牌，清掉一张判定牌", "value": true}, {"label": "不发动", "value": false}], "地主技能「飞扬」：判定区有牌，是否弃两张手牌清掉它？")
		do_it = bool(v)
	if not do_it:
		return
	for i in 2:
		var c := {}
		if is_ai(p):
			c = ai_pick_discard(p)
		elif ui.has("choose_discard"):
			c = await (ui["choose_discard"] as Callable).call(p)
		if c.is_empty():
			c = ai_pick_discard(p)
		if c.is_empty():
			break
		discard_from_hand(p, c)
	if (p["judge"] as Array).is_empty():
		return
	var jc: Dictionary = (p["judge"] as Array)[(p["judge"] as Array).size() - 1]
	if not is_ai(p) and (p["judge"] as Array).size() > 1 and ui.has("pick_option"):
		var opts: Array = []
		for c2 in p["judge"]:
			opts.append({"label": card_text(c2), "value": c2})
		var v2: Variant = await (ui["pick_option"] as Callable).call(p, opts, "「飞扬」：选择要弃置的判定牌")
		if v2 is Dictionary and not (v2 as Dictionary).is_empty():
			jc = v2
	(p["judge"] as Array).erase(jc)
	discard_pile.append(jc)
	log_msg("「飞扬」：%s 弃置两张手牌，清掉判定区的 %s。" % [pname(p), card_text(jc)])
	changed()


func concede(p: Dictionary) -> void:
	if game_over:
		return
	game_over = true
	if mode == "doudizhu":
		winner_text = "农民阵营获胜！" if String(p["identity"]) == "地主" else "地主获胜！"
	elif mode == "duel":
		var other: Dictionary = players[0] if p == players[1] else players[1]
		winner_text = "%s 在单挑中获胜！" % pname(other)
	else:
		# V0.24 修复：忠臣认输旧版判「主公阵营获胜」（等于替自己阵营赢下对局）；认输方所在阵营判负
		winner_text = "反贼阵营获胜！" if String(p["identity"]) in ["主公", "忠臣"] else "主公阵营获胜！"
	log_msg("%s 认输，本局结束。" % pname(p))
	changed()


func prev_alive_seat(from_seat: int) -> int:
	var n := players.size()
	for i in range(1, n + 1):
		var p: Dictionary = players[(from_seat - i + n * 2) % n]
		if p["alive"]:
			return int(p["seat"])
	return from_seat


func seat_order_from(start_seat: int) -> Array:
	# 从 start_seat 开始按座次环绕（含自己），无名杀触发结算顺序
	var out: Array = []
	var n := players.size()
	for i in n:
		out.append(players[(start_seat + i) % n])
	return out


func dist_between(a: int, b: int) -> int:
	# 对照 noname get.distance：只数存活角色的座次（阵亡角色不占距离），取顺/逆时针较短的一侧
	# V0.24 修复：旧版用原始座位号差值配合存活人数取模，有人阵亡后距离会算错（如 5 人局 3 号位阵亡，1 号与 4 号的距离被算成 1）
	if a == b:
		return 0
	var alive_seats: Array = []
	for p in players:
		if bool(p["alive"]) or int(p["seat"]) == a or int(p["seat"]) == b:
			alive_seats.append(int(p["seat"]))
	var ia := alive_seats.find(a)
	var ib := alive_seats.find(b)
	if ia < 0 or ib < 0:
		return 99
	var n := alive_seats.size()
	var d := absi(ia - ib)
	return mini(d, n - d)


func eff_dist(src: Dictionary, tgt: Dictionary) -> int:
	var d := dist_between(int(src["seat"]), int(tgt["seat"]))
	if not (tgt["equip"]["plus"] as Dictionary).is_empty():
		d += 1
	if not (src["equip"]["minus"] as Dictionary).is_empty():
		d -= 1
	return maxi(d, 1)


func weapon_range(p: Dictionary) -> int:
	var w: Dictionary = p["equip"]["weapon"]
	if w.is_empty():
		return 1
	return int(w.get("range", 1))


func in_attack_range(src: Dictionary, tgt: Dictionary) -> bool:
	return eff_dist(src, tgt) <= weapon_range(src)


# ---------- 牌的移动 ----------
func reshuffle_if_needed() -> void:
	if deck.is_empty() and not discard_pile.is_empty():
		deck = discard_pile.duplicate()
		discard_pile.clear()
		# 地契是局外生成的牌，离开牌局后销毁，不回到牌堆
		for c in deck.duplicate():
			if String((c as Dictionary)["name"]) == "地契":
				deck.erase(c)
		# 木牛流马里扣置的「粮」随洗牌回到牌堆
		var extra: Array = []
		for c in deck:
			if (c as Dictionary).has("stored"):
				extra.append_array((c as Dictionary)["stored"])
				(c as Dictionary).erase("stored")
		deck.append_array(extra)
		deck.shuffle()


func draw_cards(p: Dictionary, n: int) -> Array:
	var got: Array = []
	for i in n:
		reshuffle_if_needed()
		if deck.is_empty():
			break
		var c: Dictionary = deck.pop_back()
		(p["hand"] as Array).append(c)
		got.append(c)
	if not got.is_empty():
		changed()
		fx("draw", {"seat": int(p["seat"]), "n": got.size()})
	return got


func discard_from_hand(p: Dictionary, c: Dictionary) -> void:
	(p["hand"] as Array).erase(c)
	# 虚拟/转化牌（继往开来等）只是结算载体，不进入弃牌堆，避免洗牌后混进牌堆
	if not bool(c.get("virtual", false)):
		discard_pile.append(c)
	changed()
	# 金蝉脱壳：因弃置而失去此牌时，摸一张牌
	if String(c["name"]) == "金蝉脱壳" and p["alive"] and not game_over:
		draw_cards(p, 1)
		log_msg("「金蝉脱壳」被弃置：%s 摸 1 张牌。" % pname(p))


func gain_card(p: Dictionary, c: Dictionary) -> void:
	if String(c["name"]) == "地契":
		log_msg("「地契」离开装备区，被销毁。")
		return
	(p["hand"] as Array).append(c)


# ---------- 判定 ----------
func do_judge(p: Dictionary, reason: String) -> Dictionary:
	reshuffle_if_needed()
	if deck.is_empty():
		return {}
	var c: Dictionary = deck.pop_back()
	log_msg("%s 进行判定（%s）：%s。" % [pname(p), reason, card_text(c)])
	fx("judge", {"seat": int(p["seat"]), "card": c, "label": reason})
	discard_pile.append(c)
	return c


func pname(p: Dictionary) -> String:
	if p.is_empty():
		return "规则"
	return "%s（%d号位）" % [String(p["char_name"]), int(p["seat"]) + 1]


# ---------- 触发系统（对照 noname 的 event.trigger） ----------
# ctx 常用键：player(事件主体) source(来源) target(目标) card num(数值,可改) name(事件名)
func fire(timing: String, ctx: Dictionary) -> void:
	if game_over:
		return
	var start_seat := 0
	if not turn_player.is_empty():
		start_seat = int(turn_player["seat"])
	var entries: Array = []
	for p in seat_order_from(start_seat):
		for sid in (p["skills"] as Array):
			var def: Dictionary = skill_lib.get(sid, {})
			if def.is_empty():
				continue
			var timings: Dictionary = def.get("timings", {})
			if not timings.has(timing):
				continue
			var t: Dictionary = timings[timing]
			var who := String(t.get("who", "player"))
			var ok := false
			match who:
				"player":
					ok = ctx.get("player", {}) == p
				"source":
					ok = ctx.get("source", {}) == p
				"target":
					ok = ctx.get("target", {}) == p
				"global":
					ok = true
			if not ok:
				continue
			if not bool(p["alive"]) and not bool(t.get("dead_ok", false)):
				continue
			entries.append({"p": p, "sid": sid, "t": t, "prio": int(t.get("priority", 0)), "ord": entries.size()})
	# V0.24 修复：sort_custom 不是稳定排序，同优先级技能可能打乱「从当前回合角色起按座次」的触发顺序（对照 noname 同时机按座次结算）
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["prio"]) > int(b["prio"]) or (int(a["prio"]) == int(b["prio"]) and int(a["ord"]) < int(b["ord"])))
	for e in entries:
		if game_over:
			return
		var p: Dictionary = e["p"]
		var t: Dictionary = e["t"]
		if t.has("filter"):
			if not bool((t["filter"] as Callable).call(self, ctx, p)):
				continue
		var go := bool(t.get("forced", false))
		if not go:
			go = await decide_skill(p, String(e["sid"]), timing, ctx, t)
		if not go:
			continue
		var _def: Dictionary = skill_lib.get(String(e["sid"]), {})
		fx("skill", {"seat": int(p["seat"]), "name": String(_def.get("name", e["sid"])), "sid": String(e["sid"])})
		await (t["content"] as Callable).call(self, ctx, p)
		if bool(ctx.get("cancelled", false)):
			return


func decide_skill(p: Dictionary, sid: String, timing: String, ctx: Dictionary, t: Dictionary = {}) -> bool:
	# 是否发动技能：真人走 UI 回调；AI 优先用技能条目自带的 ai_decide，其次全局回调，缺省发动
	if ui.has("is_human") and bool((ui["is_human"] as Callable).call(p)):
		if ui.has("ask_skill"):
			return bool(await (ui["ask_skill"] as Callable).call(p, sid, timing, ctx))
		return true
	if t.has("ai_decide"):
		return bool((t["ai_decide"] as Callable).call(self, ctx, p))
	if ui.has("ai_skill"):
		return bool((ui["ai_skill"] as Callable).call(self, p, sid, timing, ctx))
	return true


# ================= 对局搭建 =================
const CardDefs = preload("res://data/cards.gd")
const SUITS := ["黑桃", "红桃", "梅花", "方块"]


func build_deck() -> void:
	deck.clear()
	discard_pile.clear()
	var comp := {}
	for card_name in CardDefs.DEFS:
		comp[card_name] = int(CardDefs.DEFS[card_name]["n"])
	var k := 0
	for card_name in comp:
		var pile_list: Array = []
		if CardDefs.PILE.has(card_name):
			pile_list = CardDefs.PILE[card_name]
		for i in int(comp[card_name]):
			var c := {}
			c["name"] = card_name
			if i < pile_list.size():
				var sp: Array = pile_list[i]
				c["suit"] = String(sp[0])
				c["point"] = int(sp[1])
				c["nature"] = String(sp[2]) if sp.size() > 2 else ""
				c["yb"] = (sp[3] as Array).duplicate() if sp.size() > 3 else []
			else:
				c["suit"] = SUITS[k % 4]
				c["point"] = (k % 13) + 1
				c["nature"] = ""
				c["yb"] = []
			deck.append(c)
			k += 1
	if mode == "doudizhu":
		for card_name in CardDefs.DDZ_PILE:
			for sp in CardDefs.DDZ_PILE[card_name]:
				var dc := {}
				dc["name"] = card_name
				dc["suit"] = String(sp[0])
				dc["point"] = int(sp[1])
				dc["nature"] = ""
				dc["yb"] = []
				deck.append(dc)
	deck.shuffle()


func setup_game(char_list: Array, identities: Array) -> void:
	# char_list: [{name, hp, skills:[sid,...]}]，与 identities 一一对应（0 号位=真人位）
	players.clear()
	game_over = false
	winner_text = ""
	round_no = 0
	build_deck()
	for i in char_list.size():
		var cd: Dictionary = char_list[i]
		var p := {}
		p["seat"] = i
		p["identity"] = String(identities[i])
		p["char_name"] = String(cd["name"])
		p["char"] = cd.get("char", {})
		p["max_hp"] = int(cd["hp"]) + (1 if String(identities[i]) == "主公" else 0)
		p["hp"] = p["max_hp"]
		p["hand"] = []
		p["equip"] = {"weapon": {}, "armor": {}, "minus": {}, "plus": {}, "treasure": {}}
		p["judge"] = []
		p["skills"] = (cd.get("skills", []) as Array).duplicate()
		p["alive"] = true
		p["used_attack"] = false
		p["attack_count"] = 0
		p["drunk"] = false
		p["skip_draw"] = false
		p["skip_use"] = false
		p["hammer_used"] = false
		p["round_marks"] = {}
		p["turn_used"] = {}
		p["dream_guard"] = false
		p["dream_pending"] = false
		p["chained"] = false
		p["stat_damage"] = 0
		p["stat_taken"] = 0
		p["stat_kills"] = 0
		p["stat_heal"] = 0
		p["belief"] = {}
		players.append(p)
	fan_total = 0
	for idn in identities:
		if String(idn) == "反贼":
			fan_total += 1
	revealed_fan_dead = 0
	ddz_landlord_seat = -1
	ddz_multiplier = 1
	for p in players:
		var start_n := 4
		if mode == "duel" and int(p["seat"]) == duel_first_seat:
			start_n = 3
		draw_cards(p, start_n)
	if mode == "doudizhu":
		log_msg("对局开始：斗地主（全员起手 4 张，先叫分决定地主，倍数 1~3 倍）。")
	elif mode == "duel":
		log_msg("对局开始：单挑对决（先手起手 3 张，后手 4 张）。")
	else:
		log_msg("对局开始：%d 人身份场。" % players.size())
	fx_on = true
	changed()


func lord_player() -> Dictionary:
	for p in players:
		if String(p["identity"]) == "主公":
			return p
	return {}


func first_player() -> Dictionary:
	if mode == "doudizhu":
		for p in players:
			if String(p["identity"]) == "地主":
				return p
		return {}
	if mode == "duel":
		return players[duel_first_seat] if players.size() > duel_first_seat else {}
	return lord_player()


# ================= 体力与伤害 =================
func heal(p: Dictionary, n: int, src: Dictionary = {}) -> void:
	if not p["alive"]:
		return
	var before := int(p["hp"])
	p["hp"] = mini(int(p["hp"]) + n, int(p["max_hp"]))
	if int(p["hp"]) > before:
		var gained := int(p["hp"]) - before
		if not src.is_empty():
			src["stat_heal"] = int(src.get("stat_heal", 0)) + gained
		log_msg("%s 回复 %d 点体力（%d/%d）。" % [pname(p), gained, int(p["hp"]), int(p["max_hp"])])
		changed()
		fx("heal", {"seat": int(p["seat"]), "num": gained})
		if not src.is_empty():
			observe_heal(src, p)


func damage(src: Dictionary, tgt: Dictionary, num: int, cause: String, nature: String = "", spread: bool = false, ignore_armor: bool = false) -> void:
	if not tgt["alive"] or game_over or num <= 0:
		return
	var ctx := {"name": "damage", "player": tgt, "target": tgt, "source": src, "num": num, "cause": cause, "cancelled": false}
	await fire("damageBefore", ctx)
	if bool(ctx.get("cancelled", false)):
		return
	await fire("damageBegin", ctx)
	if bool(ctx.get("cancelled", false)):
		return
	num = int(ctx.get("num", num))
	if num <= 0:
		return
	# 藤蔓铠甲：火焰伤害 +1；银狮铠甲：单次伤害至多为 1（破甲光剑无视防具）
	if not ignore_armor:
		var tarmor: Dictionary = tgt["equip"]["armor"]
		if not tarmor.is_empty():
			if nature == "火" and String(tarmor["name"]) == "藤蔓铠甲":
				num += 1
				log_msg("「藤蔓铠甲」弱点：火焰伤害 +1。")
			if String(tarmor["name"]) == "银狮铠甲" and num > 1:
				num = 1
				log_msg("「银狮铠甲」：伤害减为 1 点。")
	# 地契（斗地主）：可弃置地契防止此次伤害（弃置后销毁）
	if num > 0:
		var dq: Dictionary = tgt["equip"]["treasure"]
		if not dq.is_empty() and String(dq["name"]) == "地契":
			var prevent := false
			if is_ai(tgt):
				prevent = num >= 2 or int(tgt["hp"]) <= num
			elif ui.has("pick_option"):
				var pv: Variant = await (ui["pick_option"] as Callable).call(tgt, [{"label": "弃置地契，防止 %d 点伤害" % num, "value": true}, {"label": "不用", "value": false}], "「地契」：是否弃置地契，防止此次伤害？")
				prevent = bool(pv)
			if prevent:
				tgt["equip"]["treasure"] = {}
				log_msg("「地契」：%s 弃置地契，防止了 %d 点伤害！（地契已销毁）" % [pname(tgt), num])
				fx("dodge", {"seat": int(tgt["seat"])})
				changed()
				return
	var hp_before_d := int(tgt["hp"])
	tgt["hp"] = hp_before_d - num
	var lost := mini(num, hp_before_d)
	tgt["stat_taken"] = int(tgt.get("stat_taken", 0)) + lost
	if not src.is_empty():
		src["stat_damage"] = int(src.get("stat_damage", 0)) + lost
	observe_damage(src, tgt, lost)
	log_msg("%s 受到 %s 的 %d 点伤害（%s），体力剩余 %d。" % [pname(tgt), pname(src), num, cause, maxi(int(tgt["hp"]), 0)])
	fx("damage", {"seat": int(tgt["seat"]), "num": num, "src_seat": int(src["seat"]) if not src.is_empty() else -1, "nature": nature})
	if num >= 2 and not spread:
		fx("heavy_hit", {"seat": int(src["seat"]) if not src.is_empty() else int(tgt["seat"]), "tgt_seat": int(tgt["seat"]), "num": num})
	changed()
	# 羁绊锁链（对照 noname 连环规则）：处于连环状态的角色受到属性伤害时重置，其后其他连环角色依次受到同等属性伤害
	# V0.24 修复：旧版受伤后不重置连环状态，锁链永久有效，之后每次属性伤害都会反复传导
	var chain_spread := false
	if (nature == "火" or nature == "雷" or nature == "冰") and bool(tgt.get("chained", false)):
		tgt["chained"] = false
		log_msg("%s 的「羁绊锁链」因属性伤害而解开。" % pname(tgt))
		fx("chain", {"seat": int(tgt["seat"]), "on": false})
		chain_spread = not spread
	await pace(0.55)
	ctx["num"] = num
	# 烂银铠甲：受到「突击」造成的伤害时弃置自身
	if cause.begins_with("突击"):
		var larmor: Dictionary = tgt["equip"]["armor"]
		if not larmor.is_empty() and String(larmor["name"]) == "烂银铠甲":
			tgt["equip"]["armor"] = {}
			discard_pile.append(larmor)
			log_msg("「烂银铠甲」受击碎裂，被弃置。")
			changed()
	# V0.24 修复：对照 noname content.damage——扣体力后先结算濒死（濒死求桃/阵亡），再触发「受到伤害后」(damageEnd/damageAfter)
	# 旧版先触发受伤后技能再进濒死，0 体力时「不屈」「花愈」等会先于求桃结算
	if int(tgt["hp"]) <= 0 and tgt["alive"]:
		await handle_dying(tgt, src)
	if game_over:
		return
	await fire("damageEnd", ctx)
	await fire("damageAfter", ctx)
	# 羁绊锁链传导：属性伤害沿锁链传给其他被锁角色（传导不再二次传导；无名杀 lib.linked = 火/雷/神/冰）
	if chain_spread:
		var chained_others: Array = []
		for q in seat_order_from(int(turn_player["seat"]) if not turn_player.is_empty() else int(tgt["seat"])):
			if q != tgt and q["alive"] and bool(q.get("chained", false)):
				chained_others.append(q)
		for q in chained_others:
			if game_over:
				break
			if not q["alive"] or not bool(q.get("chained", false)):
				continue
			log_msg("「羁绊锁链」传导：%s 受到牵连。" % pname(q))
			fx("chain_hit", {"seat": int(q["seat"])})
			await damage(src, q, num, cause + "·传导", nature, true)


# ================= 响应（出闪/求桃等） =================
func find_in_hand(p: Dictionary, card_name: String) -> Dictionary:
	for c in p["hand"]:
		if String(c["name"]) == card_name:
			return c
	return {}


func respond_with(p: Dictionary, card_name: String, reason: String, responded_card: Dictionary = {}) -> bool:
	# 请求 p 打出一张 card_name 作为响应；成功返回 true
	var c := find_in_hand(p, card_name)
	var converted := false
	if c.is_empty() and card_name == "闪避" and not (p["hand"] as Array).is_empty():
		# 烂银铠甲：可将任意一张手牌当作「闪避」打出
		var arm2: Dictionary = p["equip"]["armor"]
		if not arm2.is_empty() and String(arm2["name"]) == "烂银铠甲":
			if is_ai(p):
				c = ai_pick_discard(p)
				converted = not c.is_empty()
			elif ui.has("pick_option") and ui.has("choose_discard"):
				var yv: Variant = await (ui["pick_option"] as Callable).call(p, [{"label": "用一张手牌当闪避", "value": true}, {"label": "不发动", "value": false}], "「烂银铠甲」：是否将一张手牌当作「闪避」打出？")
				if bool(yv):
					c = await (ui["choose_discard"] as Callable).call(p)
					converted = not c.is_empty()
	if c.is_empty():
		return false
	var use := true
	if not converted and ui.has("is_human") and bool((ui["is_human"] as Callable).call(p)):
		if ui.has("ask_respond"):
			use = bool(await (ui["ask_respond"] as Callable).call(p, card_name, reason))
	if not use:
		return false
	# V0.27：真人在响应时选中了具体哪一张（如两张不同花色的闪避），就打出那一张
	if not converted and ui.has("resp_pref"):
		var pc: Variant = (ui["resp_pref"] as Callable).call(p)
		if pc is Dictionary and not (pc as Dictionary).is_empty() and String(pc.get("name", "")) == card_name:
			for hc in p["hand"]:
				if is_same(hc, pc):
					c = hc
	if not converted and is_ai(p) and difficulty == 0 and card_name == "闪避" and randf() < 0.15:
		return false
	if is_ai(p):
		await think(0.7, 1.2)
	if ui.has("played"):
		(ui["played"] as Callable).call(c, pname(p))
	discard_from_hand(p, c)
	if converted:
		log_msg("%s 以「烂银铠甲」将 %s 当作「闪避」打出（%s）。" % [pname(p), card_text(c), reason])
	else:
		log_msg("%s 打出 %s（%s）。" % [pname(p), card_text(c), reason])
	if card_name == "闪避" and not converted:
		await yb_response_effects(p, c, responded_card)
	await yinyue_trigger(p, c)
	return true


# 银月长枪：回合外使用/打出黑色手牌后，可立即对范围内一名角色使用一张「突击」
func yinyue_trigger(p: Dictionary, used_card: Dictionary) -> void:
	if not p["alive"] or game_over:
		return
	if turn_player.is_empty() or turn_player == p:
		return
	if not is_black(used_card):
		return
	var weap: Dictionary = p["equip"]["weapon"]
	if weap.is_empty() or String(weap["name"]) != "银月长枪":
		return
	var sha := find_in_hand(p, "突击")
	if sha.is_empty():
		return
	var cands: Array = []
	for t in players:
		if t != p and t["alive"] and in_attack_range(p, t) and not bool(t.get("dream_guard", false)):
			cands.append(t)
	if cands.is_empty():
		return
	var tgt: Dictionary = {}
	if is_ai(p):
		var foes: Array = []
		for t in cands:
			if ai_is_enemy(p, t):
				foes.append(t)
		if foes.is_empty():
			return
		foes.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["hp"]) < int(y["hp"]))
		tgt = foes[0]
	elif ui.has("pick_option"):
		var opts: Array = []
		for t in cands:
			opts.append({"label": pname(t), "value": t})
		opts.append({"label": "不出突击", "value": {}})
		var v: Variant = await (ui["pick_option"] as Callable).call(p, opts, "「银月长枪」：你打出了黑色牌，可立即对一名角色使用「突击」")
		if v is Dictionary and not (v as Dictionary).is_empty():
			tgt = v
	if not tgt.is_empty():
		log_msg("「银月长枪」发动：%s 借势出击！" % pname(p))
		await use_attack(p, tgt, sha, false)


# ================= 看破（无懈可击） =================
func ai_wants_nullify(p: Dictionary, user: Dictionary, victim: Dictionary, negated_now: bool, trick: String = "") -> bool:
	# 当前结果对 p 不利时，按推测关系与概率决定是否翻转
	var p_supports := p == user or ai_is_ally(p, user)
	if not victim.is_empty() and ai_is_enemy(p, victim):
		p_supports = true
	var p_opposes := false
	if not victim.is_empty():
		p_opposes = p == victim or ai_is_ally(p, victim)
	var want_stand := p_supports and not (p_opposes and p != user)
	var want_negate := p_opposes and not (p_supports and p == user)
	if want_stand == want_negate:
		return false
	if not negated_now and want_negate:
		var prob := 0.35
		if p == victim:
			prob = 0.75
		elif p_opposes:
			prob = 0.45
		if difficulty == 0:
			prob *= 0.5
		if difficulty == 2 and p != victim and trick not in ["悄悄借走", "单挑", "借力打力", "火焰试炼", "灵感爆发", "落雷", "沉迷游戏", "断粮封锁"]:
			prob *= 0.4
		return randf() < prob
	if negated_now and want_stand:
		return randf() < (0.4 if difficulty == 0 else 0.55)
	return false


# 金蝉脱壳：受影响者手牌全为「金蝉脱壳」时，可令该牌对其无效并摸两张牌
func jinchan_negate(victim: Dictionary, user: Dictionary, card_name: String) -> bool:
	if victim.is_empty() or victim == user or not victim["alive"] or game_over:
		return false
	var hand: Array = victim["hand"]
	if hand.is_empty():
		return false
	for c in hand:
		if String(c["name"]) != "金蝉脱壳":
			return false
	var use := false
	if is_ai(victim):
		use = not (card_name == "全员休整" and int(victim["hp"]) < int(victim["max_hp"]))
	elif ui.has("pick_option"):
		var v: Variant = await (ui["pick_option"] as Callable).call(victim, [{"label": "金蝉脱壳：令其无效并摸两张牌", "value": true}, {"label": "不用", "value": false}], "%s 对你使用「%s」，你的手牌全是「金蝉脱壳」，是否脱壳？" % [pname(user), card_name])
		use = bool(v)
	if not use:
		return false
	var jc: Dictionary = hand[0]
	hand.erase(jc)
	discard_pile.append(jc)
	if ui.has("played"):
		(ui["played"] as Callable).call(jc, pname(victim))
	draw_cards(victim, 2)
	log_msg("%s 打出「金蝉脱壳」：%s 的「%s」对其无效，%s 摸 2 张牌！" % [pname(victim), pname(user), card_name, pname(victim)])
	fx("nullify", {"seat": int(victim["seat"]), "negated": true})
	changed()
	return true


func nullify_window(trick: String, user: Dictionary, victim: Dictionary, trick_card: Dictionary = {}) -> bool:
	# 锦囊生效前开窗：受影响者可先以「金蝉脱壳」脱壳；其余人按座次打出「看破」翻转结果
	if CardDefs.kind_of(trick) == "锦囊牌" and await jinchan_negate(victim, user, trick):
		return true
	var negated := false
	var resp_target: Dictionary = trick_card if not trick_card.is_empty() else {"name": trick}
	var guard := 0
	while guard < 12:
		guard += 1
		var actor: Dictionary = {}
		for p in seat_order_from(int(user["seat"])):
			if not p["alive"]:
				continue
			if p == user and not negated:
				continue
			if find_in_hand(p, "看破").is_empty():
				continue
			var go := false
			if is_ai(p):
				go = ai_wants_nullify(p, user, victim, negated, trick)
			elif ui.has("ask_respond"):
				var vname := pname(victim) if not victim.is_empty() else "全场"
				var state := "已被看破" if negated else "即将生效"
				go = bool(await (ui["ask_respond"] as Callable).call(p, "看破", "%s 对 %s 使用「%s」（当前：%s）" % [pname(user), vname, trick, state]))
			if go:
				actor = p
				break
		if actor.is_empty():
			break
		if is_ai(actor):
			await think(0.6, 1.0)
		var c := find_in_hand(actor, "看破")
		if ui.has("played"):
			(ui["played"] as Callable).call(c, pname(actor))
		discard_from_hand(actor, c)
		await yb_response_effects(actor, c, resp_target)
		resp_target = c
		negated = not negated
		if negated:
			log_msg("%s 打出「看破」：%s 的「%s」被看破！" % [pname(actor), pname(user), trick])
		else:
			log_msg("%s 打出「看破」反制：「%s」恢复生效！" % [pname(actor), trick])
		fx("nullify", {"seat": int(actor["seat"]), "negated": negated})
		await pace(0.5)
	return negated


func toggle_chain(t: Dictionary) -> void:
	t["chained"] = not bool(t.get("chained", false))
	changed()
	if bool(t["chained"]):
		log_msg("%s 被「羁绊锁链」连上。" % pname(t))
	else:
		log_msg("%s 的「羁绊锁链」被解开。" % pname(t))
	fx("chain", {"seat": int(t["seat"]), "on": bool(t["chained"])})


# ================= 应变（无名杀应变篇，card/yingbian.js + lib.yingbian） =================
# 词条存于卡牌 dict 的 "yb" 数组（对照 yingbian 原表逐张标注）：条件词与效果词各一类。
# 规则：声明使用此牌后（牌已离手），若满足其任一条件词，则获得其全部效果词。
# 简单条件（lib.yingbian.condition.simple）：空巢=手牌数为 0；富甲=手牌数全场最多（或之一）；残躯=体力值为 1。
# 复杂条件「助战」（lib.yingbian.condition.complex.zhuzhan）：声明使用后，按座次依次询问其他角色，
# 第一名自愿弃置一张与所用牌同类型（get.type2：基本/锦囊/装备）的手牌者响应成功，条件即成立。
const YB_COND_NAMES := ["空巢", "富甲", "残躯", "助战"]
const YB_EFF_NAMES := ["目标+", "目标-", "伤害+", "摸牌", "反甲", "强命"]


func yb_condition_met(src: Dictionary, cond: String) -> bool:
	match cond:
		"空巢":
			return (src["hand"] as Array).is_empty()
		"富甲":
			var n := (src["hand"] as Array).size()
			for q in players:
				if q["alive"] and (q["hand"] as Array).size() > n:
					return false
			return true
		"残躯":
			return int(src["hp"]) == 1
	return false


func eval_yingbian(src: Dictionary, card: Dictionary) -> Dictionary:
	var out := {"triggered": false, "conds": [], "effs": []}
	var tags: Array = card.get("yb", [])
	if tags.is_empty():
		return out
	var conds: Array = []
	var effs: Array = []
	for t in tags:
		var ts := String(t)
		if YB_COND_NAMES.has(ts):
			if yb_condition_met(src, ts):
				conds.append(ts)
		elif YB_EFF_NAMES.has(ts):
			effs.append(ts)
	if conds.is_empty() or effs.is_empty():
		return out
	out["triggered"] = true
	out["conds"] = conds
	out["effs"] = effs
	return out


func yb_card_type(c: Dictionary) -> String:
	# 对照 get.type2：基本牌 / 锦囊牌（含延时）/ 装备牌 三大类
	var kind := CardDefs.kind_of(String(c["name"]))
	if kind == "基本牌":
		return "基本牌"
	if kind == "锦囊牌" or kind == "延时锦囊":
		return "锦囊牌"
	return "装备牌"


func yb_extra_candidates(src: Dictionary, card: Dictionary, first_tgt: Dictionary) -> Array:
	# 「目标+」的合法追加目标（照 yingbian_changeTarget 的 targetEnabled2/targetInRange 过滤，按牌名分流）
	var nm := String(card["name"])
	var cands: Array = []
	for t in players:
		if t == src or t == first_tgt or not t["alive"]:
			continue
		match nm:
			"突击":
				if in_attack_range(src, t) and not bool(t.get("dream_guard", false)):
					cands.append(t)
			"逐近弃远":
				if not pick_card_from(t).is_empty():
					cands.append(t)
			"水淹七军":
				cands.append(t)
			_:
				cands.append(t)
	return cands


func yb_pick_extra_target(src: Dictionary, first_tgt: Dictionary, card: Dictionary = {}) -> Dictionary:
	# 应变「目标+」：为此次使用增加一个合法目标（可选，照 yingbian_changeTarget）
	var use_card: Dictionary = card if not card.is_empty() else {"name": "突击"}
	var cands := yb_extra_candidates(src, use_card, first_tgt)
	if cands.is_empty():
		return {}
	if is_ai(src):
		var foes: Array = []
		for t in cands:
			if ai_is_enemy(src, t):
				foes.append(t)
		if foes.is_empty():
			return {}
		foes.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["hp"]) < int(y["hp"]))
		return foes[0]
	if ui.has("pick_option"):
		var opts: Array = []
		for t in cands:
			opts.append({"label": pname(t), "value": t})
		opts.append({"label": "不追加目标", "value": {}})
		var v: Variant = await (ui["pick_option"] as Callable).call(src, opts, "「应变·目标+」：可为此次「%s」增加一个目标" % String(use_card["name"]))
		if v is Dictionary and not (v as Dictionary).is_empty():
			return v
	return {}


func yb_zhuzhan_pick(p: Dictionary, type_name: String) -> Dictionary:
	# 助战者弃置的牌：同类型中优先按 AI 弃牌偏好挑一张
	var matching: Array = []
	for c in p["hand"]:
		if yb_card_type(c) == type_name:
			matching.append(c)
	if matching.is_empty():
		return {}
	var pref := ai_pick_discard(p)
	if matching.has(pref):
		return pref
	return matching[0]


func yb_zhuzhan(src: Dictionary, card: Dictionary, first_tgt: Dictionary) -> bool:
	# 复杂条件「助战」：按座次（自使用者起环绕）依次询问其他角色，第一名响应者弃一张同类型手牌
	var type_name := yb_card_type(card)
	# 无合法追加目标时助战无收益，AI 不响应、也不打扰真人（照各牌 ai.yingbian 的 base 评估）
	if yb_extra_candidates(src, card, first_tgt).is_empty():
		return false
	for q in seat_order_from(int(src["seat"])):
		if q == src or not q["alive"] or game_over:
			continue
		var matching: Array = []
		for c in q["hand"]:
			if yb_card_type(c) == type_name:
				matching.append(c)
		if matching.is_empty():
			continue
		var given: Dictionary = {}
		if is_ai(q):
			# 照默认助战 AI：对使用者态度 <=0 不响应；盟友才弃牌助战
			if not ai_is_ally(q, src):
				continue
			given = yb_zhuzhan_pick(q, type_name)
		elif ui.has("pick_card"):
			var prompt := "%s 对 %s 使用了 %s，是否弃置一张%s牌为其助战？（助战成功：此次使用获得「目标+」）" % [pname(src), pname(first_tgt) if not first_tgt.is_empty() else "全场", card_text(card), type_name]
			var v: Variant = await (ui["pick_card"] as Callable).call(q, matching, prompt)
			if v is Dictionary and matching.has(v):
				given = v
		if given.is_empty():
			continue
		discard_from_hand(q, given)
		log_msg("「应变·助战」：%s 弃置 %s，响应了 %s 的助战。" % [pname(q), card_text(given), pname(src)])
		fx("yingbian", {"seat": int(q["seat"]), "text": "应变·助战"})
		return true
	return false


func eval_yingbian_full(src: Dictionary, card: Dictionary, first_tgt: Dictionary) -> Dictionary:
	# 先评估简单条件；未触发且牌带「助战」词条时，再走助战询问（照 _yingbian 的 simple→complex 顺序）
	var out := eval_yingbian(src, card)
	if bool(out["triggered"]):
		return out
	var tags: Array = card.get("yb", [])
	if not tags.has("助战"):
		return out
	var effs: Array = []
	for t in tags:
		var ts := String(t)
		if YB_EFF_NAMES.has(ts):
			effs.append(ts)
	if effs.is_empty():
		return out
	if await yb_zhuzhan(src, card, first_tgt):
		return {"triggered": true, "conds": ["助战"], "effs": effs}
	return out


func yb_response_effects(p: Dictionary, card: Dictionary, responded_card: Dictionary) -> void:
	# 应变（响应打出时）：「闪避」「看破」的词条在其打出后评估（照 _yingbian 于 respond 事件触发）
	var tags: Array = card.get("yb", [])
	if tags.is_empty():
		return
	var yb := eval_yingbian(p, card)
	if not bool(yb["triggered"]):
		return
	var cond_s := "·".join(PackedStringArray(yb["conds"]))
	var eff_s := "·".join(PackedStringArray(yb["effs"]))
	log_msg("「应变」触发：%s 的 %s 满足【%s】，获得效果【%s】。" % [pname(p), card_text(card), cond_s, eff_s])
	fx("yingbian", {"seat": int(p["seat"]), "text": "应变·" + eff_s})
	if (yb["effs"] as Array).has("摸牌"):
		draw_cards(p, 1)
		log_msg("「应变·摸牌」：%s 摸 1 张牌。" % pname(p))
	if (yb["effs"] as Array).has("反甲"):
		# 「反甲」= 获得响应的牌（照 lib.yingbian.effect.gain：获得所响应的那张牌）
		var got: Dictionary = {}
		# V0.24 修复：旧版找不到原牌时按牌名在弃牌堆里随便取一张同名牌（会拿到早先弃掉的另一张），
		# 现只取所响应的那张实体牌；转化/虚拟牌取其底牌（src_cards）；仅有牌名时才按名回溯最近一张
		var pool: Array = []
		if not responded_card.is_empty():
			if bool(responded_card.get("virtual", false)):
				pool = (responded_card.get("src_cards", []) as Array).duplicate()
			elif responded_card.size() == 1 and responded_card.has("name"):
				for i in range(discard_pile.size() - 1, -1, -1):
					if String(discard_pile[i]["name"]) == String(responded_card["name"]):
						pool.append(discard_pile[i])
						break
			else:
				pool.append(responded_card)
		for gc in pool:
			if discard_pile.has(gc):
				got = gc
				discard_pile.erase(got)
				gain_card(p, got)
				log_msg("「应变·反甲」：%s 获得了 %s。" % [pname(p), card_text(got)])


func yb_aoe_remove(p: Dictionary, card: Dictionary, targets: Array, is_heal: bool) -> Array:
	# 应变「目标-」：声明使用后满足条件时，可令一名目标不成为此次目标（目标数须大于 1，照 yingbian_changeTarget）
	var yb := eval_yingbian(p, card)
	if not bool(yb["triggered"]) or not (yb["effs"] as Array).has("目标-"):
		return targets
	if targets.size() <= 1:
		return targets
	var cond_s2 := "·".join(PackedStringArray(yb["conds"]))
	log_msg("「应变」触发：%s 的 %s 满足【%s】，获得效果【目标-】。" % [pname(p), card_text(card), cond_s2])
	fx("yingbian", {"seat": int(p["seat"]), "text": "应变·目标-"})
	var cands: Array = []
	for t in targets:
		if t != p:
			cands.append(t)
	if cands.is_empty():
		return targets
	var victim: Dictionary = {}
	if is_ai(p):
		var pool: Array = []
		for t in cands:
			if is_heal and ai_is_enemy(p, t):
				pool.append(t)
			elif not is_heal and ai_is_ally(p, t):
				pool.append(t)
		if pool.is_empty():
			return targets
		pool.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["hp"]) < int(y["hp"]))
		victim = pool[0]
	elif ui.has("pick_option"):
		var opts: Array = []
		for t in cands:
			opts.append({"label": pname(t), "value": t})
		opts.append({"label": "不减少目标", "value": {}})
		var v: Variant = await (ui["pick_option"] as Callable).call(p, opts, "「应变·目标-」：可令一名角色不成为此次「%s」的目标" % String(card["name"]))
		if v is Dictionary and not (v as Dictionary).is_empty():
			victim = v
	if victim.is_empty():
		return targets
	var out := targets.duplicate()
	out.erase(victim)
	log_msg("「应变·目标-」：%s 不成为此次「%s」的目标。" % [pname(victim), String(card["name"])])
	return out


# ================= 基本牌使用 =================
func use_attack(src: Dictionary, tgt: Dictionary, card: Dictionary, counts := true, already_discarded := false) -> void:
	if bool(tgt.get("dream_guard", false)):
		log_msg("%s 处于「星眠」保护中，不能成为「突击」的目标。" % pname(tgt))
		return
	if not already_discarded:
		discard_from_hand(src, card)
	if ui.has("played"):
		(ui["played"] as Callable).call(card, pname(src), pname(tgt))
		await pace(0.3)
	if counts:
		src["attack_count"] = int(src.get("attack_count", 0)) + 1
		src["used_attack"] = int(src["attack_count"]) >= attack_limit(src)
	var was_last := (src["hand"] as Array).is_empty()
	var dmg := 1 + (1 if bool(src["drunk"]) else 0)
	src["drunk"] = false
	var nature := String(card.get("nature", ""))
	log_msg("%s 对 %s 使用「%s突击」。" % [pname(src), pname(tgt), (nature + "·") if nature != "" else ""])
	fx("attack", {"src_seat": int(src["seat"]), "tgt_seat": int(tgt["seat"]), "nature": nature})
	var ctx := {"name": "useCard", "player": src, "source": src, "target": tgt, "card": card, "cancelled": false, "dmg_bonus": 0}
	await fire("useCardBegin", ctx)
	dmg += int(ctx.get("dmg_bonus", 0))
	# V0.24 修复：「猫步」等只令此「突击」对该目标无效（对照 noname 的 excluded：仅排除该目标），
	# 旧版直接 return，导致「应变·目标+」「星月画戟」追加的其他目标也一并作废
	var primary_cancelled := bool(ctx.get("cancelled", false))
	if game_over or not src["alive"]:
		return
	var weap: Dictionary = src["equip"]["weapon"]
	var wname := String(weap["name"]) if not weap.is_empty() else ""
	# 雷霆法杖（朱雀羽扇）：可将普通「突击」变为火属性
	if nature == "" and wname == "雷霆法杖":
		var convert := false
		if is_ai(src):
			var tarmor4: Dictionary = tgt["equip"]["armor"]
			convert = (not tarmor4.is_empty() and String(tarmor4["name"]) == "藤蔓铠甲") or bool(tgt.get("chained", false))
		elif ui.has("pick_option"):
			var cv: Variant = await (ui["pick_option"] as Callable).call(src, [{"label": "变为火突击", "value": true}, {"label": "保持普通突击", "value": false}], "「雷霆法杖」：是否将这张「突击」变为火属性？")
			convert = bool(cv)
		if convert:
			nature = "火"
			log_msg("「雷霆法杖」：这张「突击」燃起了火焰！")
	# 金蝉脱壳：目标手牌全为金蝉时，可令此「突击」无效
	if not primary_cancelled and await jinchan_negate(tgt, src, "突击"):
		return
	# 钢纹长槊：指定目标后，可令目标弃置你一张手牌，随后你弃置其一张手牌
	if not primary_cancelled and wname == "钢纹长槊" and not (src["hand"] as Array).is_empty() and not (tgt["hand"] as Array).is_empty():
		var trig := false
		if is_ai(src):
			trig = ai_is_enemy(src, tgt) and (src["hand"] as Array).size() >= 2
		elif ui.has("pick_option"):
			var tv: Variant = await (ui["pick_option"] as Callable).call(src, [{"label": "发动钢纹长槊", "value": true}, {"label": "不发动", "value": false}], "「钢纹长槊」：是否令 %s 弃置你一张手牌，随后你弃置其一张手牌？" % pname(tgt))
			trig = bool(tv)
		if trig:
			var mine: Array = src["hand"]
			var taken1: Dictionary = mine[randi() % mine.size()]
			discard_from_hand(src, taken1)
			log_msg("「钢纹长槊」：%s 弃置了 %s 的 %s。" % [pname(tgt), pname(src), card_text(taken1)])
			if tgt["alive"] and not (tgt["hand"] as Array).is_empty():
				# V0.24 修复：钢纹长槊只弃对方「手牌」，旧版可能拆到装备/判定区
				var th: Array = tgt["hand"]
				var taken2: Dictionary = th[randi() % th.size()]
				if not taken2.is_empty():
					discard_from_hand(tgt, taken2)
					log_msg("「钢纹长槊」：%s 弃置了 %s 的 %s。" % [pname(src), pname(tgt), card_text(taken2)])
			changed()
	# 应变：声明使用后（牌已离手）满足条件词则触发效果词（突击实装 伤害+/强命/目标+，条件含简单条件与助战）
	var yb := await eval_yingbian_full(src, card, tgt)
	var yb_hit := false
	var yb_extra: Dictionary = {}
	if bool(yb["triggered"]):
		var cond_s := "·".join(PackedStringArray(yb["conds"]))
		var eff_s := "·".join(PackedStringArray(yb["effs"]))
		log_msg("「应变」触发：%s 的 %s 满足【%s】，获得效果【%s】。" % [pname(src), card_text(card), cond_s, eff_s])
		fx("yingbian", {"seat": int(src["seat"]), "text": "应变·" + eff_s})
		if (yb["effs"] as Array).has("伤害+"):
			dmg += 1
			log_msg("「应变·伤害+」：此次「突击」伤害 +1。")
		if (yb["effs"] as Array).has("强命"):
			yb_hit = true
			log_msg("「应变·强命」：此次「突击」不可被响应。")
		if (yb["effs"] as Array).has("目标+"):
			yb_extra = await yb_pick_extra_target(src, tgt, card)
	if not primary_cancelled:
		await resolve_attack_hit(src, tgt, card, dmg, wname, nature, yb_hit)
	# 应变「目标+」追加的目标紧随其后结算（照 yingbian_changeTarget：目标在结算前加入）
	if not yb_extra.is_empty() and bool(yb_extra["alive"]) and src["alive"] and not game_over:
		log_msg("「应变·目标+」：%s 也成为此次「突击」的目标。" % pname(yb_extra))
		fx("attack", {"src_seat": int(src["seat"]), "tgt_seat": int(yb_extra["seat"]), "nature": nature})
		if not await attack_target_excluded(src, yb_extra, card):
			await resolve_attack_hit(src, yb_extra, card, dmg, wname, nature, yb_hit)
	# 星月画戟：突击是最后一张手牌时，可再追加至多两名目标
	if wname == "星月画戟" and was_last and src["alive"] and not game_over:
		var extras: Array = []
		for t in players:
			if t != src and t != tgt and t["alive"] and in_attack_range(src, t) and not bool(t.get("dream_guard", false)):
				extras.append(t)
		var chosen: Array = []
		if not extras.is_empty():
			if is_ai(src):
				var foes: Array = []
				for t in extras:
					if ai_is_enemy(src, t):
						foes.append(t)
				var pool: Array = foes if not foes.is_empty() else extras
				pool.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["hp"]) < int(y["hp"]))
				chosen = pool.slice(0, mini(2, pool.size()))
			elif ui.has("pick_option"):
				var pool2 := extras.duplicate()
				for i in 2:
					if pool2.is_empty():
						break
					var opts: Array = []
					for t in pool2:
						opts.append({"label": pname(t), "value": t})
					opts.append({"label": "不再追加", "value": {}})
					var v: Variant = await (ui["pick_option"] as Callable).call(src, opts, "「星月画戟」：突击是你最后一张手牌，可再指定一名目标")
					if not (v is Dictionary) or (v as Dictionary).is_empty():
						break
					chosen.append(v)
					pool2.erase(v)
		for t in chosen:
			if not t["alive"] or game_over:
				continue
			log_msg("「星月画戟」追加目标：%s。" % pname(t))
			fx("attack", {"src_seat": int(src["seat"]), "tgt_seat": int(t["seat"]), "nature": nature})
			if not await attack_target_excluded(src, t, card):
				await resolve_attack_hit(src, t, card, dmg, wname, nature, yb_hit)


# 追加目标同样经过「成为目标时」的技能（如猫步），被排除时只跳过该目标
func attack_target_excluded(src: Dictionary, t: Dictionary, card: Dictionary) -> bool:
	var c2 := {"name": "useCard", "player": src, "source": src, "target": t, "card": card, "cancelled": false}
	await fire("useCardBegin", c2)
	return bool(c2.get("cancelled", false)) or game_over


func resolve_attack_hit(src: Dictionary, tgt: Dictionary, card: Dictionary, dmg: int, wname: String, nature: String = "", unrespondable := false) -> void:
	var ctx := {"name": "useCard", "player": src, "source": src, "target": tgt, "card": card, "cancelled": false}
	var armor: Dictionary = tgt["equip"]["armor"]
	var ignore_armor := wname == "破甲光剑" or wname == "七宝利刃"
	# 藤蔓铠甲：普通突击无效（破甲光剑无视防具）
	if not ignore_armor and not armor.is_empty() and String(armor["name"]) == "藤蔓铠甲" and nature == "":
		log_msg("「藤蔓铠甲」生效：普通「突击」对 %s 无效。" % pname(tgt))
		return
	# 防护立场：黑色突击无效（破甲光剑无视防具）
	if not ignore_armor and not armor.is_empty() and String(armor["name"]) == "防护立场" and is_black(card):
		log_msg("「防护立场」生效：黑色「突击」对 %s 无效。" % pname(tgt))
		return
	# 结界手环：判定红色视为打出闪避（破甲光剑无视防具；应变强命不可被响应，此判定亦不触发）
	if not unrespondable and not ignore_armor and not armor.is_empty() and String(armor["name"]) == "结界手环":
		var jc := do_judge(tgt, "结界手环")
		if not jc.is_empty() and is_red(jc):
			log_msg("「结界手环」判定成功，%s 视为打出「闪避」。" % pname(tgt))
			fx("dodge", {"seat": int(tgt["seat"])})
			await fire("attackDodged", ctx)
			await weapon_after_dodge(src, tgt, card, dmg, wname, nature, ctx)
			return
	var d := dmg
	var dodged := false
	if not unrespondable:
		dodged = await respond_with(tgt, "闪避", "抵挡突击", card)
	if dodged:
		fx("dodge", {"seat": int(tgt["seat"])})
		await fire("attackDodged", ctx)
		var forced := await weapon_after_dodge(src, tgt, card, dmg, wname, nature, ctx)
		if not forced:
			return
	# 七宝利刃：目标未损失体力时伤害 +1
	if wname == "七宝利刃" and int(tgt["hp"]) == int(tgt["max_hp"]):
		d += 1
		log_msg("「七宝利刃」生效：%s 未损失体力，伤害 +1。" % pname(tgt))
	# 古锭巨剑：目标没有手牌时伤害 +1
	if wname == "古锭巨剑" and (tgt["hand"] as Array).is_empty():
		d += 1
		log_msg("「古锭巨剑」生效：%s 没有手牌，伤害 +1。" % pname(tgt))
	# 音波炮（寒冰剑）：可防止此次伤害，改为弃置目标两张牌
	if wname == "音波炮" and tgt["alive"]:
		var pool_n := (tgt["hand"] as Array).size()
		for slot in ["weapon", "armor", "minus", "plus"]:
			if not (tgt["equip"][slot] as Dictionary).is_empty():
				pool_n += 1
		pool_n += (tgt["judge"] as Array).size()
		if pool_n > 0:
			var use_ice := false
			if is_ai(src):
				use_ice = pool_n >= 2 and int(tgt["hp"]) > d and ai_is_enemy(src, tgt)
			elif ui.has("pick_option"):
				var iv: Variant = await (ui["pick_option"] as Callable).call(src, [{"label": "改为弃置其两张牌", "value": true}, {"label": "照常造成伤害", "value": false}], "「音波炮」：是否防止此次伤害，改为弃置 %s 的两张牌？" % pname(tgt))
				use_ice = bool(iv)
			if use_ice:
				for i in mini(2, pool_n):
					var taken := pick_card_from(tgt, src)
					if taken.is_empty():
						break
					remove_card_anywhere(tgt, taken)
					discard_pile.append(taken)
					log_msg("「音波炮」：弃置 %s 的 %s。" % [pname(tgt), card_text(taken)])
				changed()
				return
	# 冰属性「突击」（无名杀 icesha_skill，继承寒冰剑 hanbing_skill）：伤害结算前，使用者可防止此次伤害，改为依次弃置目标两张牌
	# 触发条件照原技能 filter：冰属性、非传导（本函数只结算直接命中，传导走 damage() 不经此处）、目标有可弃置的牌
	if nature == "冰" and tgt["alive"]:
		var fpool := (tgt["hand"] as Array).size() + (tgt["judge"] as Array).size()
		for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
			if not (tgt["equip"][slot] as Dictionary).is_empty():
				fpool += 1
		if fpool > 0:
			var use_frost := false
			if is_ai(src):
				use_frost = fpool >= 2 and int(tgt["hp"]) > d and ai_is_enemy(src, tgt)
			elif ui.has("pick_option"):
				var fv: Variant = await (ui["pick_option"] as Callable).call(src, [{"label": "改为弃置其两张牌", "value": true}, {"label": "照常造成伤害", "value": false}], "「冰·突击」：是否防止此次伤害，改为依次弃置 %s 的两张牌？" % pname(tgt))
				use_frost = bool(fv)
			if use_frost:
				for i in mini(2, fpool):
					var ftaken := pick_card_from(tgt, src)
					if ftaken.is_empty():
						break
					remove_card_anywhere(tgt, ftaken)
					discard_pile.append(ftaken)
					log_msg("「冰·突击」：弃置 %s 的 %s。" % [pname(tgt), card_text(ftaken)])
				changed()
				return
	var hp_before := int(tgt["hp"])
	await damage(src, tgt, d, "突击", nature, false, ignore_armor)
	var dealt := hp_before - int(tgt["hp"])
	if dealt > 0:
		# 双生短刃：命中摸 1；破空长弓：命中可卸对方坐骑
		# V0.30 修复：连环传导可能让出牌者自己阵亡，阵亡后不再触发武器效果（旧版阵亡角色仍摸 1 张）
		if not src["alive"]:
			pass
		elif wname == "双生短刃":
			draw_cards(src, 1)
			log_msg("「双生短刃」：%s 摸 1 张牌。" % pname(src))
		elif wname == "破空长弓" and tgt["alive"]:
			var mount_slot := ""
			if not (tgt["equip"]["minus"] as Dictionary).is_empty():
				mount_slot = "minus"
			elif not (tgt["equip"]["plus"] as Dictionary).is_empty():
				mount_slot = "plus"
			if mount_slot != "":
				var do_it := true
				if not is_ai(src) and ui.has("pick_option"):
					var mv: Variant = await (ui["pick_option"] as Callable).call(src, [{"label": "卸掉坐骑", "value": true}, {"label": "不用", "value": false}], "「破空长弓」：是否弃置 %s 的坐骑？" % pname(tgt))
					do_it = bool(mv)
				if do_it:
					var mc: Dictionary = tgt["equip"][mount_slot]
					tgt["equip"][mount_slot] = {}
					discard_pile.append(mc)
					changed()
					log_msg("「破空长弓」：弃置 %s 的 %s。" % [pname(tgt), card_text(mc)])


# 突击被闪避后的武器追击：战锤（贯石斧）弃二强制命中 / 星光长剑（青龙）再出突击；返回 true 表示强制命中、继续结算伤害
func weapon_after_dodge(src: Dictionary, tgt: Dictionary, card: Dictionary, dmg: int, wname: String, nature: String, ctx: Dictionary) -> bool:
	if not src["alive"] or not tgt["alive"] or game_over:
		return false
	if wname == "战锤" and (src["hand"] as Array).size() >= 2:
		var force := false
		if is_ai(src):
			force = ai_is_enemy(src, tgt) and ((src["hand"] as Array).size() >= 4 or int(tgt["hp"]) <= dmg)
		elif ui.has("pick_option"):
			var gv: Variant = await (ui["pick_option"] as Callable).call(src, [{"label": "弃两张牌，强制命中", "value": true}, {"label": "算了", "value": false}], "「战锤」：是否弃置两张手牌，令这张「突击」强制命中？")
			force = bool(gv)
		if force:
			for i in 2:
				var wc := ai_pick_discard(src)
				if wc.is_empty():
					break
				discard_from_hand(src, wc)
			log_msg("「战锤」生效：%s 弃置两张牌，「突击」强制命中！" % pname(src))
			return true
	elif wname == "星光长剑":
		var again := find_in_hand(src, "突击")
		if not again.is_empty():
			var do_again := false
			if is_ai(src):
				do_again = ai_is_enemy(src, tgt)
			elif ui.has("pick_option"):
				var av: Variant = await (ui["pick_option"] as Callable).call(src, [{"label": "再来一张「突击」", "value": true}, {"label": "收手", "value": false}], "「星光长剑」：你的「突击」被闪避了，是否再对 %s 使用一张「突击」？" % pname(tgt))
				do_again = bool(av)
			if do_again:
				log_msg("「星光长剑」：%s 乘胜追击，再次出击！" % pname(src))
				await use_attack(src, tgt, again, false)
	return false


func spear_attack(p: Dictionary, tgt: Dictionary, chosen: Array = []) -> bool:
	# 合璧长枪：任意两张手牌当作一张「突击」使用；真人界面可传入自选的两张，AI 缺省自动挑
	if (p["hand"] as Array).size() < 2:
		return false
	if bool(p["used_attack"]) and not has_unlimited_attack(p):
		return false
	var c1 := {}
	var c2 := {}
	if chosen.size() == 2:
		for c in p["hand"]:
			if is_same(c, chosen[0]):
				c1 = c
			elif is_same(c, chosen[1]):
				c2 = c
		if c1.is_empty() or c2.is_empty() or c1 == c2:
			return false
	else:
		c1 = ai_pick_discard(p)
		if c1.is_empty():
			return false
		var rest: Array = (p["hand"] as Array).duplicate()
		rest.erase(c1)
		c2 = rest[0]
		for want in ["落雷", "沉迷游戏", "断粮封锁", "灵感爆发", "突然检查", "悄悄借走", "单挑", "全场乱斗", "弹幕齐射", "物资发放", "全员休整", "特饮", "突击"]:
			var found := false
			for c in rest:
				if String(c["name"]) == want:
					c2 = c
					found = true
					break
			if found:
				break
	var virtual := {"name": "突击", "suit": shared_suit([c1, c2]), "point": shared_point([c1, c2]), "color": shared_color([c1, c2]), "nature": "", "yb": [], "virtual": true, "src_cards": [c1, c2]}
	discard_from_hand(p, c1)
	discard_from_hand(p, c2)
	log_msg("%s 以「合璧长枪」将 %s 与 %s 当作「突击」使用。" % [pname(p), card_text(c1), card_text(c2)])
	await use_attack(p, tgt, virtual, true, true)
	return true


# V0.28：重铸（对照无名杀 recastable：出牌阶段将此牌置入弃牌堆，然后摸一张牌）——目前只有「羁绊锁链」可重铸
func can_recast(c: Dictionary) -> bool:
	return String(c.get("name", "")) == "羁绊锁链"


func recast(p: Dictionary, card: Dictionary) -> bool:
	if not can_recast(card) or not (p["hand"] as Array).has(card):
		return false
	if ui.has("played"):
		(ui["played"] as Callable).call(card, pname(p), "重铸")
	discard_from_hand(p, card)
	log_msg("%s 重铸了 %s。" % [pname(p), card_text(card)])
	draw_cards(p, 1)
	changed()
	return true


func use_supply(p: Dictionary, card: Dictionary, tgt: Dictionary) -> void:
	discard_from_hand(p, card)
	log_msg("%s 对 %s 使用「补给」。" % [pname(p), pname(tgt)])
	heal(tgt, 1, p)


func use_drink(p: Dictionary, card: Dictionary) -> void:
	discard_from_hand(p, card)
	p["drunk"] = true
	p["drink_used"] = true
	log_msg("%s 使用「特饮」：下一张「突击」伤害 +1。" % pname(p))


# ================= 濒死与死亡 =================
func handle_dying(dying: Dictionary, src: Dictionary) -> void:
	await fire("dying", {"name": "dying", "player": dying, "target": dying, "source": src})
	fx("dying", {"seat": int(dying["seat"])})
	# V0.24 修复：对照 noname content.dying/_save——求桃从「当前回合角色」开始按座次询问（旧版从濒死者开始）；
	# 某角色救援后体力仍不大于 0 时继续询问同一角色，其拒绝后才轮到下一名，每名角色只轮一遍
	var start_seat := int(turn_player["seat"]) if not turn_player.is_empty() else int(dying["seat"])
	var order := seat_order_from(start_seat)
	var oi := 0
	while oi < order.size() and int(dying["hp"]) <= 0 and dying["alive"] and not game_over:
		var p: Dictionary = order[oi]
		if not p["alive"]:
			oi += 1
			continue
		var c := find_in_hand(p, "补给")
		if c.is_empty() and p == dying:
			c = find_in_hand(p, "特饮")
		if c.is_empty():
			oi += 1
			continue
		var do_save := true
		if ui.has("is_human") and bool((ui["is_human"] as Callable).call(p)):
			if ui.has("ask_save"):
				do_save = bool(await (ui["ask_save"] as Callable).call(p, dying))
		else:
			do_save = ai_should_save(p, dying)
		if not do_save:
			oi += 1
			continue
		discard_from_hand(p, c)
		log_msg("%s 对 %s 使用 %s 救援。" % [pname(p), pname(dying), card_text(c)])
		heal(dying, 1, p)
	if int(dying["hp"]) <= 0 and dying["alive"]:
		await die(dying, src)
	elif dying["alive"]:
		fx("revived", {"seat": int(dying["seat"])})


func ai_should_save(rescuer: Dictionary, dying: Dictionary) -> bool:
	if rescuer == dying:
		return true
	if mode == "duel":
		return false
	if mode == "doudizhu":
		return ai_is_ally(rescuer, dying)
	var di := String(dying["identity"])
	if di == "主公":
		if String(rescuer["identity"]) == "内奸":
			return not (revealed_fan_dead >= fan_total and alive_players().size() <= 3)
		return true
	if difficulty == 0 and randf() < 0.25:
		return false
	return ai_is_ally(rescuer, dying)


func die(p: Dictionary, killer: Dictionary) -> void:
	p["alive"] = false
	if not killer.is_empty() and killer != p:
		killer["stat_kills"] = int(killer.get("stat_kills", 0)) + 1
		if bool(killer.get("alive", false)):
			fx("kill_spree", {"seat": int(killer["seat"]), "kills": int(killer["stat_kills"]), "name": String(killer["char_name"])})
	if String(p["identity"]) == "反贼":
		revealed_fan_dead += 1
	fx("death", {"seat": int(p["seat"])})
	changed()
	log_msg("%s 阵亡（身份：%s）。" % [pname(p), String(p["identity"])])
	for c in (p["hand"] as Array).duplicate():
		discard_from_hand(p, c)
	for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
		var e: Dictionary = p["equip"][slot]
		if not e.is_empty():
			discard_pile.append(e)
			p["equip"][slot] = {}
	for c in (p["judge"] as Array).duplicate():
		discard_pile.append(c)
	p["judge"] = []
	await fire("die", {"name": "die", "player": p, "target": p, "source": killer})
	# 奖惩（对照 mode/identity.js；其他模式无奖惩）
	if mode == "identity" and not killer.is_empty() and killer["alive"]:
		if String(p["identity"]) == "反贼":
			draw_cards(killer, 3)
			log_msg("%s 击杀反贼，摸 3 张牌。" % pname(killer))
		elif String(killer["identity"]) == "主公" and String(p["identity"]) == "忠臣":
			for c in (killer["hand"] as Array).duplicate():
				discard_from_hand(killer, c)
			for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
				var e2: Dictionary = killer["equip"][slot]
				if not e2.is_empty():
					discard_pile.append(e2)
					killer["equip"][slot] = {}
			log_msg("主公误杀忠臣，弃置所有手牌与装备。")
	# V0.24 补齐斗地主死亡奖惩（对照 mode/doudizhu.js 规则说明与 dieAfter2 的 chooseDrawRecover(2)）：
	# 一名农民阵亡后，若另一名农民存活，其可以选择摸两张牌或回复 1 点体力
	if mode == "doudizhu" and String(p["identity"]) == "农民":
		check_over()
		if game_over:
			return
		for mate in players:
			if mate == p or not mate["alive"] or String(mate["identity"]) != "农民":
				continue
			var choice := "draw"
			var can_heal := int(mate["hp"]) < int(mate["max_hp"])
			if can_heal:
				if is_ai(mate):
					choice = "heal" if int(mate["hp"]) <= 2 else "draw"
				elif ui.has("pick_option"):
					var cv: Variant = await (ui["pick_option"] as Callable).call(mate, [{"label": "摸两张牌", "value": "draw"}, {"label": "回复 1 点体力", "value": "heal"}], "队友阵亡：请选择一项奖励")
					choice = String(cv)
			if choice == "heal":
				log_msg("农民 %s 阵亡，队友 %s 选择回复 1 点体力。" % [pname(p), pname(mate)])
				heal(mate, 1)
			else:
				log_msg("农民 %s 阵亡，队友 %s 选择摸两张牌。" % [pname(p), pname(mate)])
				draw_cards(mate, 2)
		return
	check_over()


func check_over() -> void:
	if mode == "duel":
		for p in players:
			if not p["alive"]:
				game_over = true
				var other: Dictionary = players[0] if p == players[1] else players[1]
				winner_text = "%s 在单挑中获胜！" % pname(other)
				log_msg("对局结束：%s" % winner_text)
				return
		return
	if mode == "doudizhu":
		var dizhu: Dictionary = {}
		var nong_alive := 0
		for p in players:
			if String(p["identity"]) == "地主":
				dizhu = p
			elif p["alive"]:
				nong_alive += 1
		if not dizhu.is_empty():
			if not bool(dizhu["alive"]):
				game_over = true
				winner_text = "农民阵营获胜！"
			elif nong_alive == 0:
				game_over = true
				winner_text = "地主获胜！"
			if game_over:
				log_msg("对局结束：%s" % winner_text)
		return
	var lord := lord_player()
	if lord.is_empty():
		return
	var fan_alive := false
	var nei_alive := false
	var others_alive := false
	for p in players:
		if not p["alive"]:
			continue
		if String(p["identity"]) == "反贼":
			fan_alive = true
		elif String(p["identity"]) == "内奸":
			nei_alive = true
		# V0.24 修复：旧版把内奸自己也算进「其他存活者」，导致内奸永远无法获胜（对照 identity.js：主公阵亡时场上只剩内奸则内奸胜）
		if p != lord and String(p["identity"]) != "内奸":
			others_alive = true
	if not bool(lord["alive"]):
		game_over = true
		if nei_alive and not others_alive:
			winner_text = "内奸获胜！"
		else:
			winner_text = "反贼阵营获胜！"
	elif not fan_alive and not nei_alive:
		game_over = true
		winner_text = "主公阵营获胜！"
	if game_over:
		log_msg("对局结束：%s" % winner_text)


# ================= 回合流程（阶段表对照 noname content.js phase()） =================
func run_turn(p: Dictionary) -> void:
	if not p["alive"] or game_over:
		return
	if is_ai(p):
		await think(0.6, 1.0)
	turn_player = p
	phase_text = "准备阶段"
	changed()
	p["dream_guard"] = false
	p["turn_used"] = {}
	p["drink_used"] = false
	p["used_attack"] = false
	p["attack_count"] = 0
	p["hammer_used"] = false
	p["canyue_turn"] = false
	p["jianxin_dmg_turn"] = false
	var base := {"name": "phase", "player": p, "target": p}
	await fire("phaseBefore", base.duplicate())
	await fire("phaseBeginStart", base.duplicate())
	await fire("phaseBegin", base.duplicate())
	# 准备阶段
	await fire("phaseZhunbeiStart", base.duplicate())
	await fire("phaseZhunbei", base.duplicate())
	await fire("phaseZhunbeiEnd", base.duplicate())
	# 跋扈（斗地主地主）：准备阶段摸一张牌
	if mode == "doudizhu" and String(p["identity"]) == "地主":
		draw_cards(p, 1)
		log_msg("「跋扈」：地主 %s 摸 1 张牌。" % pname(p))
	phase_text = "判定阶段"
	changed()
	# 判定阶段：判定区延时牌由二期结算（resolve_delayed 占位钩子）
	await fire("phaseJudgeStart", base.duplicate())
	# 飞扬（斗地主地主）：判定开始时可弃两张手牌清掉一张判定牌
	if mode == "doudizhu" and String(p["identity"]) == "地主":
		await feiyang_offer(p)
	await resolve_delayed_phase(p)
	await fire("phaseJudge", base.duplicate())
	await fire("phaseJudgeEnd", base.duplicate())
	if not p["alive"] or game_over:
		return
	phase_text = "摸牌阶段"
	changed()
	# 摸牌阶段
	await fire("phaseDrawStart", base.duplicate())
	if not bool(p["skip_draw"]):
		var draw_n := 2
		if bool(p.get("caomu_less", false)):
			draw_n = 1
			log_msg("「草木疑兵」：%s 少摸一张牌。" % pname(p))
		draw_cards(p, draw_n)
		log_msg("%s 摸 %d 张牌。" % [pname(p), draw_n])
	p["skip_draw"] = false
	if bool(p.get("caomu_cheer", false)):
		p["caomu_cheer"] = false
		p["caomu_less"] = false
		var nb1: Dictionary = players[prev_alive_seat(int(p["seat"]))]
		var nb2: Dictionary = players[next_alive_seat(int(p["seat"]))]
		for q in [nb1, nb2]:
			if q != p and q["alive"]:
				draw_cards(q, 1)
				log_msg("「草木疑兵」：邻座的 %s 摸 1 张牌。" % pname(q))
	await fire("phaseDraw", base.duplicate())
	await fire("phaseDrawEnd", base.duplicate())
	phase_text = "出牌阶段"
	changed()
	# 出牌阶段
	await fire("phaseUseStart", base.duplicate())
	await taigong_start(p)
	if not bool(p["skip_use"]):
		if ui.has("is_human") and bool((ui["is_human"] as Callable).call(p)) and ui.has("play_phase"):
			await (ui["play_phase"] as Callable).call(self, p)
		else:
			await ai_play_phase(p)
	p["skip_use"] = false
	await taigong_end(p)
	await fire("phaseUse", base.duplicate())
	await fire("phaseUseEnd", base.duplicate())
	if not p["alive"] or game_over:
		return
	phase_text = "弃牌阶段"
	changed()
	# 弃牌阶段
	await fire("phaseDiscardStart", base.duplicate())
	await discard_phase(p)
	await fire("phaseDiscard", base.duplicate())
	await fire("phaseDiscardEnd", base.duplicate())
	phase_text = "结束阶段"
	changed()
	# 结束阶段
	await fire("phaseJieshuStart", base.duplicate())
	await fire("phaseJieshu", base.duplicate())
	await fire("phaseJieshuEnd", base.duplicate())
	p["drunk"] = false
	p["canyue_turn"] = false
	p["jianxin_dmg_turn"] = false
	# V0.28：「星眠」保护到本回合结束（与设计稿、技能说明一致）
	if bool(p.get("dream_guard", false)) and not xingmian_legacy:
		p["dream_guard"] = false
		log_msg("%s 从星眠中醒来，「星眠」保护结束。" % pname(p))
	await pace(0.25)


func discard_phase(p: Dictionary) -> void:
	var limit := maxi(int(p["hp"]), 0)
	while (p["hand"] as Array).size() > limit and p["alive"]:
		var c: Dictionary = {}
		if ui.has("is_human") and bool((ui["is_human"] as Callable).call(p)) and ui.has("choose_discard"):
			discard_need = (p["hand"] as Array).size() - limit  # V0.25：供界面一次多选 N 张
			c = await (ui["choose_discard"] as Callable).call(p)
			discard_need = 0
		if c.is_empty():
			c = ai_pick_discard(p)
		if c.is_empty():
			break
		if is_ai(p):
			await think(0.45, 0.75)
		discard_from_hand(p, c)
		log_msg("%s 弃置 %s。" % [pname(p), card_text(c)])


func ai_find_sha(p: Dictionary, tgt: Dictionary) -> Dictionary:
	# 选一张「突击」：有属性的优先；目标穿藤蔓铠甲且只有普通突击时返回空（不做无用功）
	# V0.30：目标有「防护立场」时不出黑色突击（无视防具的武器除外）
	var wname := ""
	var wp: Dictionary = p["equip"].get("weapon", {})
	if not wp.is_empty():
		wname = String(wp["name"])
	var ignore_armor := wname == "破甲光剑" or wname == "七宝利刃"
	var armor := ""
	if not tgt.is_empty() and not ignore_armor:
		var ta: Dictionary = tgt["equip"]["armor"]
		if not ta.is_empty():
			armor = String(ta["name"])
	var plain := {}
	for c in p["hand"]:
		if String(c["name"]) != "突击":
			continue
		if armor == "防护立场" and is_black(c):
			continue
		if String(c.get("nature", "")) != "":
			return c
		if plain.is_empty():
			plain = c
	if armor == "藤蔓铠甲":
		return {}
	return plain


func ai_has_pressure_attack(p: Dictionary) -> bool:
	# V0.32：残局破僵局用——当前还能对有效敌人出一张「突击」时，优先进攻而不是回复
	if bool(p["used_attack"]) and not has_unlimited_attack(p):
		return false
	var tgt := ai_pick_target(p, true)
	if tgt.is_empty():
		return false
	return not ai_find_sha(p, tgt).is_empty()


func ai_in_stalemate_endgame(p: Dictionary) -> bool:
	return round_no >= AI_STALEMATE_ROUND and alive_players().size() <= 2


func ai_pick_discard(p: Dictionary) -> Dictionary:
	var hand: Array = p["hand"]
	if hand.is_empty():
		return {}
	if difficulty == 0 and randf() < 0.3:
		return hand[randi() % hand.size()]
	# 优先弃：多余装备/锦囊，其次重复突击，最后才动闪避/补给
	var pref := ["落雷", "沉迷游戏", "断粮封锁", "灵感爆发", "突然检查", "悄悄借走", "单挑", "全场乱斗", "弹幕齐射", "物资发放", "全员休整", "特饮", "突击"]
	var picked: Dictionary = {}
	for want in pref:
		for c in hand:
			if String(c["name"]) == want:
				picked = c
				break
		if not picked.is_empty():
			break
	if picked.is_empty():
		picked = hand[hand.size() - 1]
	# 困难：低体力时留住最后一张闪避
	if difficulty == 2 and String(picked["name"]) == "闪避" and int(p["hp"]) <= 2:
		var dodge_n := 0
		for c in hand:
			if String(c["name"]) == "闪避":
				dodge_n += 1
		if dodge_n <= 1:
			for c in hand:
				if String(c["name"]) != "闪避" and String(c["name"]) != "补给":
					return c
	return picked

var difficulty := 1  # 0 简单 1 普通 2 困难
var mode: String = "identity"
var duel_first_seat: int = 0
var ddz_multiplier: int = 1
var ddz_landlord_seat: int = -1
var fan_total := 2
var revealed_fan_dead := 0


func belief_of(p: Dictionary, t: Dictionary) -> float:
	var b: Dictionary = p.get("belief", {})
	return float(b.get(int(t["seat"]), 0.0))


func belief_add(p: Dictionary, t: Dictionary, delta: float) -> void:
	var b: Dictionary = p.get("belief", {})
	var seat := int(t["seat"])
	b[seat] = clampf(float(b.get(seat, 0.0)) + delta, -6.0, 6.0)
	p["belief"] = b


func belief_threshold() -> float:
	match difficulty:
		0:
			return 1.6
		2:
			return 0.6
	return 1.0


func ai_is_enemy(p: Dictionary, t: Dictionary) -> bool:
	if p == t:
		return false
	if mode == "duel":
		return true
	if mode == "doudizhu":
		return String(p["identity"]) != String(t["identity"])
	# V0.32：身份场只剩两人且未分胜负时，双方必然敌对（主忠/反贼同阵营两人存活时对局已结束）
	if bool(p["alive"]) and bool(t["alive"]) and alive_players().size() <= 2:
		return true
	var pi := String(p["identity"])
	var lord := lord_player()
	if not lord.is_empty() and t == lord:
		if pi == "内奸":
			return revealed_fan_dead >= fan_total and alive_players().size() <= 3
		return pi == "反贼"
	if pi == "反贼" and String(t["identity"]) == "反贼":
		return false
	if pi == "内奸":
		if revealed_fan_dead >= fan_total:
			return true
		# V0.30（参照无名杀 get.situation / 内奸 attitude）：内奸帮弱势一方——
		# 主公方明显占优时把（疑似）忠臣当敌人，否则打（疑似）反贼
		var bv := belief_of(p, t)
		if situation() >= 2:
			return bv > -belief_threshold()
		return bv <= -belief_threshold()
	var en := belief_of(p, t) <= -belief_threshold()
	if difficulty == 0 and randf() < 0.12:
		en = not en
	return en


func ai_is_ally(p: Dictionary, t: Dictionary) -> bool:
	if mode == "duel":
		return false
	if mode == "doudizhu":
		return p != t and String(p["identity"]) == String(t["identity"])
	if p == t:
		return true
	if bool(p["alive"]) and bool(t["alive"]) and alive_players().size() <= 2:
		return false
	var pi := String(p["identity"])
	if pi == "反贼" and String(t["identity"]) == "反贼":
		return true
	var lord := lord_player()
	if not lord.is_empty() and t == lord:
		return pi == "主公" or pi == "忠臣"
	if pi == "内奸":
		return false
	return belief_of(p, t) >= belief_threshold()


func observe_damage(src: Dictionary, tgt: Dictionary, num: int) -> void:
	if mode != "identity":
		return
	if src.is_empty() or src == tgt or num <= 0:
		return
	var lord := lord_player()
	for o in players:
		if o == src or not o["alive"]:
			continue
		var oc := camp_of(String(o["identity"]))
		if not lord.is_empty() and tgt == lord:
			if oc == "fan":
				belief_add(o, src, 2.0)
			else:
				belief_add(o, src, -2.2)
		if tgt == o:
			belief_add(o, src, -2.5)
		if not lord.is_empty() and src == lord and tgt != o:
			if oc == "fan":
				belief_add(o, tgt, 1.5)
			else:
				belief_add(o, tgt, -1.5)
		if tgt != o and belief_of(o, tgt) >= 1.5:
			belief_add(o, src, -1.2)


func observe_heal(src: Dictionary, tgt: Dictionary) -> void:
	if mode != "identity":
		return
	if src.is_empty() or src == tgt:
		return
	var lord := lord_player()
	for o in players:
		if o == src or not o["alive"]:
			continue
		var oc := camp_of(String(o["identity"]))
		if not lord.is_empty() and tgt == lord:
			if oc == "fan":
				belief_add(o, src, -2.0)
			elif oc == "nei":
				belief_add(o, src, 1.0)
			else:
				belief_add(o, src, 2.0)
		if tgt == o:
			belief_add(o, src, 2.0)


func observe_hostile(user: Dictionary, tgt: Dictionary) -> void:
	if mode != "identity":
		return
	var lord := lord_player()
	if lord.is_empty() or tgt != lord:
		return
	for o in players:
		if o == user or not o["alive"]:
			continue
		if camp_of(String(o["identity"])) == "fan":
			belief_add(o, user, 1.5)
		else:
			belief_add(o, user, -1.5)


# 局势（参照无名杀 get.situation）：主公方存活体力和 − 反贼方存活体力和；>0 主公方占优
func situation() -> int:
	var v := 0
	for q in players:
		if not q["alive"]:
			continue
		var c := camp_of(String(q["identity"]))
		if c == "loyal":
			v += int(q["hp"]) + 1
		elif c == "fan":
			v -= int(q["hp"]) + 1
	return v


# 突击目标评分（参照无名杀 ai.basic chooseTarget + get.attitude）：越高越优先
func ai_target_score(p: Dictionary, t: Dictionary) -> float:
	var sc := 10.0 - float(int(t["hp"])) * 2.0 - float((t["hand"] as Array).size()) * 0.4
	if int(t["hp"]) <= 1:
		sc += 4.0
	var ar: Dictionary = t["equip"]["armor"]
	if not ar.is_empty():
		sc -= 1.5
	if mode == "identity":
		if String(p["identity"]) == "反贼" and String(t["identity"]) == "主公":
			var bonus := AI_REBEL_LORD_BONUS if difficulty >= 1 else AI_REBEL_LORD_BONUS * 0.5
			if int(t["hp"]) <= 2:
				bonus += 1.2
			sc += bonus
		elif String(p["identity"]) == "主公" and absf(belief_of(p, t)) < 0.8:
			sc -= 1.5
	return sc


func camp_of(identity: String) -> String:
	if identity == "主公" or identity == "忠臣":
		return "loyal"
	if identity == "反贼":
		return "fan"
	return "nei"


func true_is_enemy(a: Dictionary, b: Dictionary) -> bool:
	var ca := camp_of(String(a["identity"]))
	var cb := camp_of(String(b["identity"]))
	if ca == "nei" or cb == "nei":
		return true
	return ca != cb


func ai_pick_weapon_holder(p: Dictionary) -> Dictionary:
	var fallback: Dictionary = {}
	for t in players:
		if t == p or not t["alive"]:
			continue
		if (t["equip"]["weapon"] as Dictionary).is_empty():
			continue
		if ai_is_enemy(p, t):
			return t
		fallback = t
	return fallback


func ai_pick_enemy_with_hand(p: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var bhp := 999
	for t in players:
		if t == p or not t["alive"] or not ai_is_enemy(p, t):
			continue
		if (t["hand"] as Array).is_empty():
			continue
		if int(t["hp"]) < bhp:
			bhp = int(t["hp"])
			best = t
	return best


func ai_pick_target(p: Dictionary, want_enemy: bool) -> Dictionary:
	if difficulty == 2 and want_enemy:
		var lord := lord_player()
		if not lord.is_empty() and lord != p and lord["alive"] and int(lord["hp"]) <= 2 and ai_is_enemy(p, lord) and in_attack_range(p, lord):
			return lord
	var best: Dictionary = {}
	var best_sc := -1e9
	for t in players:
		if t == p or not t["alive"]:
			continue
		if bool(t.get("dream_guard", false)):
			continue
		if ai_is_enemy(p, t) != want_enemy:
			continue
		if not in_attack_range(p, t):
			continue
		var sc := ai_target_score(p, t) if want_enemy else -float(int(t["hp"]))
		if sc > best_sc:
			best_sc = sc
			best = t
	if best.is_empty() and want_enemy:
		# 还没有定论时：对嫌疑最重（分数最低）的非主公角色试探
		var worst: Dictionary = {}
		var worst_b := -0.3
		var lord2 := lord_player()
		for t in players:
			if t == p or not t["alive"] or t == lord2:
				continue
			if bool(t.get("dream_guard", false)):
				continue
			if ai_is_ally(p, t):
				continue
			if not in_attack_range(p, t):
				continue
			var bv := belief_of(p, t)
			if bv <= worst_b:
				worst_b = bv
				worst = t
		best = worst
	return best


func ai_play_phase(p: Dictionary) -> void:
	var guard := 0
	while p["alive"] and not game_over and guard < 20:
		guard += 1
		await think(1.3, 2.1)
		if await ai_try_action(p):
			continue
		break


func ai_try_action(p: Dictionary) -> bool:
	# 装备：有就装（更强武器替换在 play_equip 内比较）
	for c in (p["hand"] as Array).duplicate():
		var k := CardDefs.kind_of(String(c["name"]))
		if k == "武器" or k == "防具" or k == "饰品" or k == "宝物":
			var slot := equip_slot_of(String(c["name"]))
			var cur: Dictionary = p["equip"][slot]
			if cur.is_empty() or (slot == "weapon" and CardDefs.weapon_range_of(String(c["name"])) > CardDefs.weapon_range_of(String(cur["name"]))):
				play_equip(p, c)
				return true
	# 木牛流马：存粮与转运
	var trq: Dictionary = p["equip"]["treasure"]
	if not trq.is_empty() and String(trq["name"]) == "木牛流马":
		var stored: Array = trq.get("stored", [])
		if stored.size() >= 2:
			for t in players:
				if t != p and t["alive"] and ai_is_ally(p, t) and (t["equip"]["treasure"] as Dictionary).is_empty() and (t["hand"] as Array).size() <= 2:
					muniu_give(p, t)
					return true
		if stored.size() < 3 and (p["hand"] as Array).size() >= 5:
			var junk := ai_pick_discard(p)
			if not junk.is_empty():
				muniu_store(p, junk)
				return true
	# 主动技能（注册表 active 条目，每回合一次）
	for sid in (p["skills"] as Array).duplicate():
		var sdef: Dictionary = skill_lib.get(sid, {})
		if sdef.is_empty() or not sdef.has("active"):
			continue
		if bool((p["turn_used"] as Dictionary).get(sid, false)):
			continue
		if bool(sdef.get("limited", false)) and bool(p.get("limited_used_" + String(sid), false)):
			continue
		var act: Dictionary = sdef["active"]
		if act.has("filter") and not bool((act["filter"] as Callable).call(self, p)):
			continue
		if act.has("ai_use") and not bool((act["ai_use"] as Callable).call(self, p)):
			continue
		p["turn_used"][sid] = true
		if bool(sdef.get("limited", false)):
			p["limited_used_" + String(sid)] = true
		await (act["content"] as Callable).call(self, p)
		return true
	# 洞烛先机：对自己使用（卜算＋摸 2，恒有益）
	var dz := find_in_hand(p, "洞烛先机")
	if not dz.is_empty():
		await play_card(p, dz, p)
		return true
	# 出其不意：对有手牌的敌人使用（约 3/4 概率花色不同造成 1 点伤害）
	var cq := find_in_hand(p, "出其不意")
	if not cq.is_empty():
		var cq_tgt: Dictionary = {}
		var cq_hp := 99
		for t in players:
			if t != p and t["alive"] and ai_is_enemy(p, t) and not (t["hand"] as Array).is_empty() and int(t["hp"]) < cq_hp:
				cq_hp = int(t["hp"])
				cq_tgt = t
		if not cq_tgt.is_empty():
			await play_card(p, cq, cq_tgt)
			return true
	# 攻守兼备 / 进退自如（斗地主专属）：有其他存活角色就用（用法在 play_card 内抉择）
	for ddn in ["攻守兼备", "进退自如"]:
		var ddc := find_in_hand(p, ddn)
		if not ddc.is_empty() and alive_players().size() >= 2:
			await play_card(p, ddc, {})
			return true
	# 继往开来（斗地主专属）：手牌 2 张以上时对自己使用
	var jw := find_in_hand(p, "继往开来")
	if not jw.is_empty() and (p["hand"] as Array).size() >= 2:
		await play_card(p, jw, p)
		return true
	# 灵感爆发
	var wzh := find_in_hand(p, "灵感爆发")
	if not wzh.is_empty():
		await play_card(p, wzh, {})
		return true
	# 物资发放
	var wg := find_in_hand(p, "物资发放")
	if not wg.is_empty():
		await play_card(p, wg, {})
		return true
	# 全员休整：受伤的己方（含自己）多于受伤的敌方才放
	# V0.24 修复：旧版只要场上有人受伤就放，常常只给敌人回血（斗地主 1v1 残局因此久拖不决）
	var ty := find_in_hand(p, "全员休整")
	if not ty.is_empty() and ai_taoyuan_gain(p) > 0:
		await play_card(p, ty, {})
		return true
	# V0.28：落雷/浮雷只能放自己判定区（无名杀 shandian ai：局势对己方不利/人少时才放）
	for ln in ["落雷", "浮雷"]:
		var lc := find_in_hand(p, ln)
		if not lc.is_empty() and ai_want_lightning(p, ln):
			await play_card(p, lc, p)
			return true
	# 延时锦囊：给敌人（断粮封锁限距离 1）
	for dn in ["沉迷游戏", "断粮封锁", "草木疑兵"]:
		var dc := find_in_hand(p, dn)
		if dc.is_empty():
			continue
		var tgt := pick_delayed_target(p, dn)
		if not tgt.is_empty():
			await play_card(p, dc, tgt)
			return true
	# 悄悄借走（距离1内）/ 突然检查（任意距离）：对有牌的敌人
	for tn in ["悄悄借走", "突然检查"]:
		var tc := find_in_hand(p, tn)
		if tc.is_empty():
			continue
		var tgt2 := pick_card_target(p, tn == "悄悄借走")
		if not tgt2.is_empty():
			await play_card(p, tc, tgt2)
			return true
	# 单挑：挑手牌少的敌人
	var jd := find_in_hand(p, "单挑")
	if not jd.is_empty():
		var tgt3 := pick_duel_target(p)
		if not tgt3.is_empty():
			await play_card(p, jd, tgt3)
			return true
	# 增兵减灶：给自己（手牌不多时）或手牌少的盟友
	var zb := find_in_hand(p, "增兵减灶")
	if not zb.is_empty():
		var zt: Dictionary = {}
		if (p["hand"] as Array).size() <= 4:
			zt = p
		else:
			for t in players:
				if t != p and t["alive"] and ai_is_ally(p, t) and (t["hand"] as Array).size() <= 2:
					zt = t
					break
		if not zt.is_empty():
			await play_card(p, zb, zt)
			return true
	# 声东击西：把废牌塞给牌多的敌人，再从其处拿两张给自己
	var sd := find_in_hand(p, "声东击西")
	if not sd.is_empty() and alive_players().size() > 2 and (p["hand"] as Array).size() >= 3:
		var rich: Dictionary = {}
		var rich_n := 2
		for t in players:
			if t != p and t["alive"] and ai_is_enemy(p, t) and (t["hand"] as Array).size() > rich_n:
				rich_n = (t["hand"] as Array).size()
				rich = t
		if not rich.is_empty():
			await play_card(p, sd, rich)
			return true
	# 弃甲曳兵：拆装备多的敌人
	var qj := find_in_hand(p, "弃甲曳兵")
	if not qj.is_empty():
		for t in players:
			if t != p and t["alive"] and ai_is_enemy(p, t):
				var en := 0
				for slot in ["weapon", "armor", "minus", "plus"]:
					if not (t["equip"][slot] as Dictionary).is_empty():
						en += 1
				if en >= 2:
					await play_card(p, qj, t)
					return true
	# 水淹七军：单目标——挑带装备或残血的敌人（装备越多越优先，其次体力越低）
	var sy := find_in_hand(p, "水淹七军")
	if not sy.is_empty():
		var best_t: Dictionary = {}
		var best_score := -1.0
		for t in players:
			if t != p and t["alive"] and ai_is_enemy(p, t):
				var en2 := 0
				for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
					if not (t["equip"][slot] as Dictionary).is_empty():
						en2 += 1
				if en2 >= 1 or int(t["hp"]) <= 1:
					var score := float(en2) * 2.0 - float(t["hp"]) * 0.3
					if score > best_score:
						best_score = score
						best_t = t
		if not best_t.is_empty():
			await play_card(p, sy, best_t)
			return true
	# 逐近弃远：对有牌的敌人（近则夺、远则拆）
	var zj := find_in_hand(p, "逐近弃远")
	if not zj.is_empty():
		var tgt9 := pick_card_target(p, false)
		if not tgt9.is_empty():
			await play_card(p, zj, tgt9)
			return true
	# 弹幕齐射：敌人>=2 才放
	var wj := find_in_hand(p, "弹幕齐射")
	if not wj.is_empty() and count_enemies(p) >= 2:
		await play_card(p, wj, {})
		return true
	# 全场乱斗：敌人>=2 且自己有突击垫底
	var nm := find_in_hand(p, "全场乱斗")
	if not nm.is_empty() and count_enemies(p) >= 2 and not find_in_hand(p, "突击").is_empty():
		await play_card(p, nm, {})
		return true
	# 借力打力：找有武器的人
	var jd2 := find_in_hand(p, "借力打力")
	if not jd2.is_empty():
		var holder := ai_pick_weapon_holder(p)
		if not holder.is_empty():
			await play_card(p, jd2, holder)
			return true
	# 火焰试炼：手牌富余时烧敌人
	var hg := find_in_hand(p, "火焰试炼")
	if not hg.is_empty() and (p["hand"] as Array).size() >= 3:
		var et := ai_pick_enemy_with_hand(p)
		if not et.is_empty():
			await play_card(p, hg, et)
			return true
	# 羁绊锁链：两名以上未锁敌人时连起来；自己/队友被锁时解开；否则重铸（V0.28，对照无名杀铁索 ai + recastable）
	var sl := find_in_hand(p, "羁绊锁链")
	if not sl.is_empty():
		var unchained: Array = []
		var mine_locked: Array = []
		for t in players:
			if not t["alive"]:
				continue
			if t != p and ai_is_enemy(p, t) and not bool(t.get("chained", false)):
				unchained.append(t)
			if (t == p or ai_is_ally(p, t)) and bool(t.get("chained", false)):
				mine_locked.append(t)
		if unchained.size() >= 2:
			unchained.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["hp"]) > int(y["hp"]))
			ai_chain_second = {"t": unchained[1]}
			await play_card(p, sl, unchained[0])
			ai_chain_second = {}
			return true
		if not mine_locked.is_empty():
			ai_chain_second = {"t": mine_locked[1] if mine_locked.size() >= 2 else {}}
			await play_card(p, sl, mine_locked[0])
			ai_chain_second = {}
			return true
		recast(p, sl)
		return true
	# 补给自己（V0.30：残局第 30 轮起只在 2 血及以下时吃，其余留着濒死自救，避免回复拉锯）
	# V0.32：两人残局且本回合还能进攻时，除 1 血外不先回复，避免双方互相奶满拖到回合上限
	var skip_supply_for_attack := ai_in_stalemate_endgame(p) and int(p["hp"]) > 1 and ai_has_pressure_attack(p)
	if int(p["hp"]) < int(p["max_hp"]) and not skip_supply_for_attack and (round_no < 30 or int(p["hp"]) <= 2):
		var sup := find_in_hand(p, "补给")
		if not sup.is_empty():
			use_supply(p, sup, p)
			return true
	# 特饮+突击（对照 noname jiu：usable 1，每回合限一次）
	if not bool(p["drunk"]) and not bool(p.get("drink_used", false)):
		var atk0 := find_in_hand(p, "突击")
		var drk := find_in_hand(p, "特饮")
		var tgt0 := ai_pick_target(p, true)
		if not atk0.is_empty() and not drk.is_empty() and not tgt0.is_empty():
			use_drink(p, drk)
			return true
	# 突击
	if not bool(p["used_attack"]) or has_unlimited_attack(p):
		var tgt := ai_pick_target(p, true)
		var atk := ai_find_sha(p, tgt)
		if atk.is_empty() and not tgt.is_empty():
			# 首选目标打不动（如穿藤蔓铠甲又无属性突击）时，改打其他敌人
			for t in players:
				if t != p and t != tgt and t["alive"] and ai_is_enemy(p, t) and not bool(t.get("dream_guard", false)):
					var a2 := ai_find_sha(p, t)
					if not a2.is_empty():
						atk = a2
						tgt = t
						break
		if not atk.is_empty() and not tgt.is_empty():
			await use_attack(p, tgt, atk)
			return true
	# 合璧长枪：没有突击时拼两张牌当突击
	var w2: Dictionary = p["equip"]["weapon"]
	if not w2.is_empty() and String(w2["name"]) == "合璧长枪" and (not bool(p["used_attack"]) or has_unlimited_attack(p)) and (p["hand"] as Array).size() >= 3:
		var tgt3 := ai_pick_target(p, true)
		if not tgt3.is_empty():
			await spear_attack(p, tgt3)
			return true
	return false


func ai_taoyuan_gain(p: Dictionary) -> int:
	# 全员休整对 p 的净收益：受伤的自己/友方 +1，受伤的敌方 -1（立场不明者不计）
	var gain := 0
	for t in players:
		if not t["alive"] or int(t["hp"]) >= int(t["max_hp"]):
			continue
		if t == p or ai_is_ally(p, t):
			gain += 1
		elif ai_is_enemy(p, t):
			gain -= 1
	return gain


func ai_ddz_bid_desire(p: Dictionary) -> int:
	# AI 叫分意愿：按手牌强度估（突击/补给/装备/锦囊越强叫得越高）
	var score := 0.0
	for c in p["hand"]:
		var cn := String(c["name"])
		var k := CardDefs.kind_of(cn)
		if cn == "突击":
			score += 1.0
		elif cn == "补给":
			score += 1.2
		elif k == "武器" or k == "防具" or k == "饰品" or k == "宝物":
			score += 1.0
		elif k == "锦囊牌" or k == "延时锦囊":
			score += 0.7
		elif cn == "闪避":
			score += 0.6
		else:
			score += 0.3
	if score >= 4.2:
		return 3
	if score >= 3.2:
		return 2
	if score >= 2.4:
		return 1
	return 0


func run_ddz_bidding() -> void:
	# 叫分（对照 mode/doudizhu.js 的叫地主流程）：自随机座位起轮流叫 1~3 倍，价高者成为地主；
	# 若全员不叫，最后一名被问者必须叫（原版在绕回时移除「不叫地主」选项）
	for p in players:
		p["identity"] = "农民"
	var start := randi() % players.size()
	var order := seat_order_from(start)
	var high := 0
	var high_seat := -1
	var asked := 0
	for p in order:
		if game_over:
			return
		asked += 1
		var is_last := asked == order.size()
		var bid := 0
		if is_ai(p):
			await think(0.8, 1.4)
			var desire := ai_ddz_bid_desire(p)
			if is_last and high == 0:
				desire = maxi(desire, 1)
			bid = desire if desire > high else 0
		elif ui.has("pick_option"):
			var opts: Array = []
			if not (is_last and high == 0):
				opts.append({"label": "不叫", "value": 0})
			for lv in range(high + 1, 4):
				opts.append({"label": "%d 倍" % lv, "value": lv})
			var v: Variant = await (ui["pick_option"] as Callable).call(p, opts, "叫分定地主：当前最高 %s，请选择你的叫分" % ("无人叫分" if high == 0 else "%d 倍" % high))
			bid = int(v)
		if bid > high:
			high = bid
			high_seat = int(p["seat"])
			log_msg("%s 叫 %d 倍。" % [pname(p), bid])
		else:
			log_msg("%s 不叫。" % pname(p))
	if high_seat < 0:
		high_seat = int(order[order.size() - 1]["seat"])
		high = 1
	var lord: Dictionary = players[high_seat]
	lord["identity"] = "地主"
	ddz_landlord_seat = high_seat
	ddz_multiplier = high
	draw_cards(lord, 1)
	lord["equip"]["treasure"] = {"name": "地契", "suit": "梅花", "point": 13}
	log_msg("叫分结束：%s 以 %d 倍成为地主（先手，起手 5 张，自带「飞扬」「跋扈」）！本局倍数 ×%d。" % [pname(lord), high, high])
	log_msg("地主 %s 获得「地契」（可弃置以防止一次伤害）。" % pname(lord))
	changed()


func run_game() -> void:
	if mode == "doudizhu" and ddz_landlord_seat < 0:
		await run_ddz_bidding()
	var lord := first_player()
	if lord.is_empty():
		return
	var order := seat_order_from(int(lord["seat"]))
	var idx := 0
	var safety := 0
	while not game_over and safety < 400:
		safety += 1
		var p: Dictionary = order[idx % order.size()]
		idx += 1
		if bool(p["alive"]) and int(p["seat"]) == int(lord["seat"]):
			round_no += 1
			for q in players:
				q["round_marks"] = {}
		if turn_hook.is_valid():
			turn_hook.call(self, p)
		await run_turn(p)
	if turn_hook.is_valid():
		turn_hook.call(self, {})
	if not game_over:
		game_over = true
		winner_text = "局面上限：未分胜负"
		log_msg("对局结束：%s" % winner_text)


# ================= 二期：全牌型结算（对照 card/standard.js） =================
func equip_slot_of(card_name: String) -> String:
	var k := CardDefs.kind_of(card_name)
	if k == "武器":
		return "weapon"
	if k == "防具":
		return "armor"
	if k == "宝物":
		return "treasure"
	if k == "饰品":
		return "minus" if card_name == "疾行之靴" else "plus"
	return ""


func attack_limit(p: Dictionary) -> int:
	if has_unlimited_attack(p):
		return 999
	if mode == "doudizhu" and String(p["identity"]) == "地主":
		return 2
	return 1


func has_unlimited_attack(p: Dictionary) -> bool:
	if bool(p.get("canyue_turn", false)):
		return true
	var w: Dictionary = p["equip"]["weapon"]
	return not w.is_empty() and String(w["name"]) == "魔导连弩"


func target_has_cards(t: Dictionary) -> bool:
	if not (t["hand"] as Array).is_empty():
		return true
	for slot in ["weapon", "armor", "minus", "plus"]:
		if not (t["equip"][slot] as Dictionary).is_empty():
			return true
	return not (t["judge"] as Array).is_empty()


func pick_card_from(t: Dictionary, src: Dictionary = {}) -> Dictionary:
	# 拆/借/法杖的选牌。给出 src 时按来源立场挑选（V0.24 修复：旧版对敌人也优先拆判定区的「沉迷游戏」等，等于帮敌人解围）：
	# 敌对：装备（武器>防具>坐骑>宝物）> 随机手牌 > 判定牌（别无可选时）；友方：判定牌 > 随机手牌 > 装备
	if not src.is_empty():
		var friendly := is_ai(src) and ai_is_ally(src, t) and src != t
		var eqs: Array = []
		for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
			var e0: Dictionary = t["equip"][slot]
			if not e0.is_empty():
				eqs.append(e0)
		var hand0: Array = t["hand"]
		var judge0: Array = t["judge"]
		if friendly:
			if not judge0.is_empty():
				return judge0[0]
			if not hand0.is_empty():
				return hand0[randi() % hand0.size()]
			if not eqs.is_empty():
				return eqs[eqs.size() - 1]
			return {}
		# V0.30（参照无名杀 guohe ai：防具价值高于武器）：
		# 够不着对方时先拆「远行披风」等防御坐骑，再拆防具，然后武器/宝物/进攻坐骑
		var order := ["armor", "weapon", "treasure", "plus", "minus"]
		if src != t and not in_attack_range(src, t):
			order = ["plus", "armor", "weapon", "treasure", "minus"]
		for slot in order:
			var e1: Dictionary = t["equip"][slot]
			if not e1.is_empty():
				return e1
		if not hand0.is_empty():
			return hand0[randi() % hand0.size()]
		if not judge0.is_empty():
			return judge0[0]
		return {}
	# 无来源（仅判断「有没有牌」）：装备 > 判定牌 > 手牌第一张
	for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
		var e: Dictionary = t["equip"][slot]
		if not e.is_empty():
			return e
	if not (t["judge"] as Array).is_empty():
		return (t["judge"] as Array)[0]
	if not (t["hand"] as Array).is_empty():
		return (t["hand"] as Array)[0]
	return {}


# V0.25 修复：真人使用「突然检查/悄悄借走/逐近弃远」时界面先选好目标的那张牌，
# 但结算前（看破窗口、应变·助战等）那张牌可能已离开目标区域；旧版仍按原选择结算，
# 把已进弃牌堆的牌再弃置/获得一次 → 同一张牌出现两份。现结算前校验仍在目标身上，否则重新选。
func owns_card(t: Dictionary, c: Dictionary) -> bool:
	if c.is_empty() or t.is_empty():
		return false
	for h in t["hand"]:
		if is_same(h, c):
			return true
	for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
		if is_same(t["equip"][slot], c):
			return true
	for j in t["judge"]:
		if is_same(j, c):
			return true
	return false


func remove_card_anywhere(t: Dictionary, c: Dictionary) -> void:
	if (t["hand"] as Array).has(c):
		(t["hand"] as Array).erase(c)
		return
	for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
		var e: Dictionary = t["equip"][slot]
		if e == c:
			t["equip"][slot] = {}
			# 银狮铠甲：离开装备区时，若未满体力则回复 1 点
			if slot == "armor" and String(c["name"]) == "银狮铠甲" and t["alive"] and int(t["hp"]) < int(t["max_hp"]):
				t["hp"] = int(t["hp"]) + 1
				t["stat_heal"] = int(t.get("stat_heal", 0)) + 1
				log_msg("「银狮铠甲」离场：%s 回复 1 点体力。" % pname(t))
				fx("heal", {"seat": int(t["seat"]), "num": 1})
				changed()
			return
	if (t["judge"] as Array).has(c):
		(t["judge"] as Array).erase(c)


func play_equip(p: Dictionary, card: Dictionary) -> void:
	if ui.has("played"):
		(ui["played"] as Callable).call(card, pname(p))
	var slot := equip_slot_of(String(card["name"]))
	if slot == "":
		return
	(p["hand"] as Array).erase(card)
	var old: Dictionary = p["equip"][slot]
	if not old.is_empty():
		# V0.24 修复：被顶替的旧装备同样是「离开装备区」，银狮铠甲的离场回血要生效（对照 noname baiyin_skill：lose 装备区）
		remove_card_anywhere(p, old)
		discard_pile.append(old)
	var placed := card.duplicate()
	if slot == "weapon":
		placed["range"] = CardDefs.weapon_range_of(String(card["name"]))
	p["equip"][slot] = placed
	log_msg("%s 装备了 %s。" % [pname(p), card_text(card)])
	fx("equip", {"seat": int(p["seat"]), "name": String(card["name"])})
	changed()


func resolve_delayed_phase(p: Dictionary) -> void:
	# 判定区按「后放先结」的叠放顺序结算
	lightning_back = []
	await _resolve_delayed_inner(p)
	# V0.28：对照无名杀 addJudgeNext——其他角色都放不下时回到自己的判定区（下回合再判）
	for bc in lightning_back:
		if p["alive"] and not game_over:
			(p["judge"] as Array).append(bc)
			log_msg("「%s」没有其他角色可以接收，留在 %s 的判定区。" % [String(bc["name"]), pname(p)])
		else:
			discard_pile.append(bc)
	lightning_back = []


var lightning_back: Array = []
var xingmian_legacy := false  # 仅平衡压测对照用：true = 旧口径（保护持续到下个回合开始）
var ai_chain_second: Dictionary = {}  # AI 使用羁绊锁链时预先选好的第二目标（空 = 只连一人）


func _move_or_back(p: Dictionary, card: Dictionary) -> void:
	if move_lightning(p, card):
		return
	if p["alive"] and not game_over:
		lightning_back.append(card)
	else:
		discard_pile.append(card)


func _resolve_delayed_inner(p: Dictionary) -> void:
	while not (p["judge"] as Array).is_empty() and p["alive"] and not game_over:
		var zone: Array = p["judge"]
		var card: Dictionary = zone[zone.size() - 1]
		zone.erase(card)
		var nm := String(card["name"])
		log_msg("%s 判定区结算：%s。" % [pname(p), card_text(card)])
		# V0.24 修复：延时锦囊判定前开看破窗口（被看破则本次不判定：落雷/浮雷照常移交下家，其余弃置）
		var placer_seat := int(card.get("placer", -1))
		var placer: Dictionary = {}
		if placer_seat >= 0 and placer_seat < players.size() and placer_seat != int(p["seat"]):
			placer = players[placer_seat]
		if placer.is_empty():
			# 自己放置/移交而来：以判定者上家为「使用者」开窗，判定者本人仍可看破
			placer = players[prev_alive_seat(int(p["seat"]))]
		var dt_negated := false
		if placer != p:
			dt_negated = await nullify_window(nm, placer, p)
		if not p["alive"] or game_over:
			discard_pile.append(card)
			break
		if dt_negated:
			log_msg("%s 判定区的「%s」被看破，本次不判定。" % [pname(p), nm])
			if nm == "落雷" or nm == "浮雷":
				_move_or_back(p, card)
			else:
				discard_pile.append(card)
			continue
		if nm == "落雷":
			var jc := do_judge(p, "落雷")
			if not jc.is_empty() and String(jc["suit"]) == "黑桃" and int(jc["point"]) >= 2 and int(jc["point"]) <= 9:
				discard_pile.append(card)
				log_msg("「落雷」命中！")
				await damage({}, p, 3, "落雷", "雷")
			else:
				_move_or_back(p, card)
		elif nm == "沉迷游戏":
			discard_pile.append(card)
			var jc2 := do_judge(p, "沉迷游戏")
			if not jc2.is_empty() and String(jc2["suit"]) != "红桃":
				p["skip_use"] = true
				log_msg("「沉迷游戏」生效：%s 跳过出牌阶段。" % pname(p))
			else:
				log_msg("「沉迷游戏」判定未生效。")
		elif nm == "断粮封锁":
			discard_pile.append(card)
			var jc3 := do_judge(p, "断粮封锁")
			if not jc3.is_empty() and String(jc3["suit"]) != "梅花":
				p["skip_draw"] = true
				log_msg("「断粮封锁」生效：%s 跳过摸牌阶段。" % pname(p))
			else:
				log_msg("「断粮封锁」判定未生效。")
		elif nm == "草木疑兵":
			discard_pile.append(card)
			var jc5 := do_judge(p, "草木疑兵")
			if not jc5.is_empty() and String(jc5["suit"]) != "梅花":
				p["caomu_less"] = true
				p["caomu_cheer"] = true
				log_msg("「草木疑兵」生效：%s 本回合少摸一张牌，摸牌后其邻座各摸一张。" % pname(p))
			else:
				log_msg("「草木疑兵」判定为梅花，未生效。")
		elif nm == "浮雷":
			var jc4 := do_judge(p, "浮雷")
			if not jc4.is_empty() and String(jc4["suit"]) == "黑桃":
				var fx4 := int(card.get("fulei_x", 0)) + 1
				card["fulei_x"] = fx4
				log_msg("「浮雷」命中！第 %d 次雷击。" % fx4)
				await damage({}, p, fx4, "浮雷", "雷")
			else:
				log_msg("「浮雷」未命中。")
			if not game_over and p["alive"]:
				_move_or_back(p, card)
			else:
				discard_pile.append(card)
		else:
			discard_pile.append(card)


# 落雷/浮雷移交（对照 noname shandian：判定未生效时移至下家；下家判定区已有同名牌则继续顺延，直到找到可放置者或绕回自己）
# V0.24 修复：旧版下家已有同名牌时直接把牌弃掉，原版应顺延给再下一家
func move_lightning(p: Dictionary, card: Dictionary) -> bool:
	var nm := String(card["name"])
	var seat := int(p["seat"])
	for i in players.size():
		seat = next_alive_seat(seat)
		if seat == int(p["seat"]):
			return false
		var np: Dictionary = players[seat]
		var dup := false
		for c2 in np["judge"]:
			if String(c2["name"]) == nm:
				dup = true
		if not dup:
			card["placer"] = -1
			(np["judge"] as Array).append(card)
			log_msg("「%s」%s转移给 %s。" % [nm, "未命中，" if nm == "落雷" else "", pname(np)])
			return true
	return false


func shuiyan_resolve(p: Dictionary, t: Dictionary) -> void:
	# 「水淹七军」对单个目标的结算（对照 shuiyanqijunx content：无装备直接受雷伤；有装备二选一）
	var eqs: Array = []
	for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
		var eq2: Dictionary = t["equip"][slot]
		if not eq2.is_empty():
			eqs.append(eq2)
	var take_dmg := true
	if not eqs.is_empty():
		if is_ai(t):
			take_dmg = not (int(t["hp"]) <= 1 or (eqs.size() == 1 and int(t["hp"]) <= 3))
		elif ui.has("pick_option"):
			var wv: Variant = await (ui["pick_option"] as Callable).call(t, [{"label": "弃置装备区全部 %d 张牌" % eqs.size(), "value": false}, {"label": "受到 1 点雷电伤害", "value": true}], "「水淹七军」：选择一项")
			take_dmg = bool(wv)
	if take_dmg:
		await damage(p, t, 1, "水淹七军", "雷")
	else:
		for eq3 in eqs:
			remove_card_anywhere(t, eq3)
			discard_pile.append(eq3)
		log_msg("%s 弃置了装备区的全部 %d 张牌。" % [pname(t), eqs.size()])
		changed()


func zhujin_resolve(p: Dictionary, tgt: Dictionary, forced_entry: Dictionary = {}) -> void:
	# 「逐近弃远」对单个目标的结算（距离 1 获得、距离大于 1 弃置，照 zhujinqiyuan content）
	var taken3: Dictionary = forced_entry if owns_card(tgt, forced_entry) else pick_card_from(tgt, p)
	if taken3.is_empty():
		return
	remove_card_anywhere(tgt, taken3)
	if eff_dist(p, tgt) <= 1:
		gain_card(p, taken3)
		log_msg("%s「逐近弃远」（距离 1）：获得 %s 的 %s。" % [pname(p), pname(tgt), card_text(taken3)])
	else:
		discard_pile.append(taken3)
		log_msg("%s「逐近弃远」（距离大于 1）：弃置 %s 的 %s。" % [pname(p), pname(tgt), card_text(taken3)])


func yb_trick_extra(p: Dictionary, card: Dictionary, tgt: Dictionary) -> Dictionary:
	# 锦囊应变统一入口：触发且含「目标+」时返回追加目标，否则返回 {}
	var yb := await eval_yingbian_full(p, card, tgt)
	if not bool(yb["triggered"]):
		return {}
	var cond_s := "·".join(PackedStringArray(yb["conds"]))
	var eff_s := "·".join(PackedStringArray(yb["effs"]))
	log_msg("「应变」触发：%s 的 %s 满足【%s】，获得效果【%s】。" % [pname(p), card_text(card), cond_s, eff_s])
	fx("yingbian", {"seat": int(p["seat"]), "text": "应变·" + eff_s})
	if (yb["effs"] as Array).has("目标+"):
		var extra := await yb_pick_extra_target(p, tgt, card)
		if not extra.is_empty():
			log_msg("「应变·目标+」：%s 也成为此次「%s」的目标。" % [pname(extra), String(card["name"])])
		return extra
	return {}


func do_guanxing(p: Dictionary, n: int) -> void:
	# 卜算（对照 chooseToGuanxing）：查看牌堆顶 n 张，可调整顺序或将其中一张置于牌堆底，然后照常摸取
	reshuffle_if_needed()
	var cnt := mini(n, deck.size())
	if cnt <= 0:
		return
	if is_ai(p) or cnt == 1 or not ui.has("pick_option"):
		log_msg("%s 卜算 %d（保持牌序）。" % [pname(p), cnt])
		return
	var top1: Dictionary = deck[deck.size() - 1]
	var top2: Dictionary = deck[deck.size() - 2]
	var opts: Array = [
		{"label": "保持顺序（先摸 %s，再摸 %s）" % [card_text(top1), card_text(top2)], "value": "keep"},
		{"label": "交换两张（先摸 %s）" % card_text(top2), "value": "swap"},
		{"label": "将 %s 放到牌堆底" % card_text(top1), "value": "bottom1"},
		{"label": "将 %s 放到牌堆底" % card_text(top2), "value": "bottom2"},
	]
	var v: Variant = await (ui["pick_option"] as Callable).call(p, opts, "卜算：牌堆顶两张牌，如何处置？")
	match (String(v) if v is String else "keep"):
		"swap":
			deck[deck.size() - 1] = top2
			deck[deck.size() - 2] = top1
			log_msg("%s 卜算：交换了牌堆顶两张牌的顺序。" % pname(p))
		"bottom1":
			deck.pop_back()
			deck.push_front(top1)
			log_msg("%s 卜算：将 %s 放到牌堆底。" % [pname(p), card_text(top1)])
		"bottom2":
			deck.remove_at(deck.size() - 2)
			deck.push_front(top2)
			log_msg("%s 卜算：将 %s 放到牌堆底。" % [pname(p), card_text(top2)])
		_:
			log_msg("%s 卜算：保持牌序。" % pname(p))


func effect_nanman(p: Dictionary, card: Dictionary, vname: String) -> void:
	var nm := vname
	log_msg("%s 使用「全场乱斗」！" % pname(p))
	var nm_targets: Array = []
	for t0 in seat_order_from(int(p["seat"])):
		if t0 != p and bool(t0["alive"]):
			nm_targets.append(t0)
	nm_targets = await yb_aoe_remove(p, card, nm_targets, false)
	for t in nm_targets:
		if not t["alive"] or game_over:
			continue
		var tarmor5: Dictionary = t["equip"]["armor"]
		var pweap5: Dictionary = p["equip"]["weapon"]
		if not tarmor5.is_empty() and String(tarmor5["name"]) == "藤蔓铠甲" and (pweap5.is_empty() or String(pweap5["name"]) != "破甲光剑"):
			log_msg("「藤蔓铠甲」：%s 免疫「全场乱斗」。" % pname(t))
			continue
		if await nullify_window(nm, p, t, card):
			log_msg("「全场乱斗」对 %s 被看破。" % pname(t))
			continue
		var ok := await respond_with(t, "突击", "响应全场乱斗")
		if not ok:
			await damage(p, t, 1, "全场乱斗")


func effect_wanjian(p: Dictionary, card: Dictionary, vname: String) -> void:
	var nm := vname
	log_msg("%s 使用「弹幕齐射」！" % pname(p))
	var wj_targets: Array = []
	for t0 in seat_order_from(int(p["seat"])):
		if t0 != p and bool(t0["alive"]):
			wj_targets.append(t0)
	wj_targets = await yb_aoe_remove(p, card, wj_targets, false)
	for t in wj_targets:
		if not t["alive"] or game_over:
			continue
		var tarmor6: Dictionary = t["equip"]["armor"]
		var pweap6: Dictionary = p["equip"]["weapon"]
		if not tarmor6.is_empty() and String(tarmor6["name"]) == "藤蔓铠甲" and (pweap6.is_empty() or String(pweap6["name"]) != "破甲光剑"):
			log_msg("「藤蔓铠甲」：%s 免疫「弹幕齐射」。" % pname(t))
			continue
		if await nullify_window(nm, p, t, card):
			log_msg("「弹幕齐射」对 %s 被看破。" % pname(t))
			continue
		# V0.24 修复：结界手环（八卦阵）对任何需要打出「闪避」的场合生效（对照 noname bagua_skill：chooseToRespondBegin），旧版只在被「突击」时判定
		if not tarmor6.is_empty() and String(tarmor6["name"]) == "结界手环":
			var bjc := do_judge(t, "结界手环")
			if not bjc.is_empty() and is_red(bjc):
				log_msg("「结界手环」判定成功，%s 视为打出「闪避」。" % pname(t))
				fx("dodge", {"seat": int(t["seat"])})
				continue
		var ok2 := await respond_with(t, "闪避", "响应弹幕齐射", card)
		if not ok2:
			await damage(p, t, 1, "弹幕齐射")


func effect_taoyuan(p: Dictionary, card: Dictionary, vname: String) -> void:
	var nm := vname
	log_msg("%s 使用「全员休整」。" % pname(p))
	var xz_targets: Array = []
	# V0.24 修复：对照 noname taoyuan——从使用者开始按座次逐个结算（旧版固定从 1 号位开始，影响看破询问顺序）
	for t0 in seat_order_from(int(p["seat"])):
		if bool(t0["alive"]) and int(t0["hp"]) < int(t0["max_hp"]):
			xz_targets.append(t0)
	xz_targets = await yb_aoe_remove(p, card, xz_targets, true)
	for t in xz_targets:
		if t["alive"] and int(t["hp"]) < int(t["max_hp"]):
			if await nullify_window(nm, p, t, card):
				log_msg("「全员休整」对 %s 被看破。" % pname(t))
				continue
			heal(t, 1, p)


func effect_wugu(p: Dictionary, card: Dictionary, vname: String) -> void:
	var nm := vname
	var n := alive_players().size()
	var shown: Array = []
	for i in n:
		reshuffle_if_needed()
		if deck.is_empty():
			break
		shown.append(deck.pop_back())
	log_msg("%s 使用「物资发放」，亮出 %d 张牌。" % [pname(p), shown.size()])
	for t in seat_order_from(int(p["seat"])):
		if shown.is_empty():
			break
		if not t["alive"]:
			continue
		if await nullify_window(nm, p, t, card):
			log_msg("「物资发放」对 %s 被看破。" % pname(t))
			continue
		# V0.24 修复：对照 noname wugu——每名角色从亮出的牌中「自选」一张；旧版一律拿第一张，真人无从选择
		var got: Dictionary = shown[0]
		if shown.size() > 1:
			if is_ai(t):
				var best_v := -99.0
				for sc in shown:
					var v := ai_card_value(t, sc)
					if v > best_v:
						best_v = v
						got = sc
			elif ui.has("pick_option"):
				var wopts: Array = []
				for sc in shown:
					wopts.append({"label": card_text(sc), "value": sc})
				var wv: Variant = await (ui["pick_option"] as Callable).call(t, wopts, "「物资发放」：选择一张牌获得")
				if wv is Dictionary and shown.has(wv):
					got = wv
		shown.erase(got)
		gain_card(t, got)
		log_msg("%s 拿取 %s。" % [pname(t), card_text(got)])
	for left in shown:
		discard_pile.append(left)


func ai_card_value(p: Dictionary, c: Dictionary) -> float:
	# AI 粗略估牌价值（物资发放挑牌用）：缺血时补给最高，其次闪避/无中/突击，装备按空槽加分
	var nm := String(c["name"])
	var k := CardDefs.kind_of(nm)
	if nm == "补给":
		return 9.0 if int(p["hp"]) < int(p["max_hp"]) else 5.0
	if nm == "闪避":
		return 6.0
	if nm == "看破":
		return 5.5
	if nm == "灵感爆发" or nm == "洞烛先机":
		return 5.0
	if nm == "突击":
		return 4.5 if find_in_hand(p, "突击").is_empty() else 3.0
	if k == "武器" or k == "防具" or k == "饰品" or k == "宝物":
		var slot := equip_slot_of(nm)
		return 4.8 if slot != "" and (p["equip"][slot] as Dictionary).is_empty() else 1.5
	if k == "延时锦囊":
		return 3.5
	return 4.0


func jiwang_use_as_trick(jt: Dictionary) -> void:
	# 「继往开来」第二项：将所有手牌当做一张普通锦囊牌使用（全部手牌即此牌的代价）
	# 可选锦囊与目标合法性按各牌 filterTarget 近似：无目标类直接可用；目标类须存在合法目标
	var others: Array = []
	for t in players:
		if t != jt and t["alive"]:
			others.append(t)
	var any_injured := false
	for t in players:
		if t["alive"] and int(t["hp"]) < int(t["max_hp"]):
			any_injured = true
	var avail: Array = []  # [{name, mode}]，mode: none=无目标 self=对自己 other=需选一名其他角色 any=任意一名（含自己）
	avail.append({"name": "灵感爆发", "mode": "none"})
	if not others.is_empty():
		avail.append({"name": "全场乱斗", "mode": "none"})
		avail.append({"name": "弹幕齐射", "mode": "none"})
	avail.append({"name": "物资发放", "mode": "none"})
	if any_injured:
		avail.append({"name": "全员休整", "mode": "none"})
	avail.append({"name": "洞烛先机", "mode": "self"})
	avail.append({"name": "增兵减灶", "mode": "any"})
	for t in others:
		if not pick_card_from(t).is_empty():
			avail.append({"name": "突然检查", "mode": "other"})
			avail.append({"name": "逐近弃远", "mode": "other"})
			break
	for t in others:
		if not (t["hand"] as Array).is_empty():
			avail.append({"name": "出其不意", "mode": "other"})
			avail.append({"name": "火焰试炼", "mode": "other"})
			break
	if not others.is_empty():
		avail.append({"name": "单挑", "mode": "other"})
		avail.append({"name": "羁绊锁链", "mode": "other"})
	for t in others:
		if not (t["equip"]["weapon"] as Dictionary).is_empty():
			avail.append({"name": "借力打力", "mode": "other"})
			break
	for t in others:
		if eff_dist(jt, t) <= 1 and not pick_card_from(t).is_empty():
			avail.append({"name": "悄悄借走", "mode": "other"})
			break
	var pick: Dictionary = {}
	if is_ai(jt):
		for cand in avail:
			if String(cand["name"]) in ["灵感爆发", "全场乱斗", "洞烛先机", "弹幕齐射", "突然检查", "增兵减灶"]:
				pick = cand
				break
		if pick.is_empty():
			pick = avail[0]
	elif ui.has("pick_option"):
		var opts: Array = []
		for cand in avail:
			opts.append({"label": "当作「%s」使用" % String(cand["name"]), "value": cand})
		var v: Variant = await (ui["pick_option"] as Callable).call(jt, opts, "「继往开来」：将全部手牌当作哪张锦囊牌使用？")
		if v is Dictionary and not (v as Dictionary).is_empty():
			pick = v
	if pick.is_empty():
		pick = avail[0]
	var tname := String(pick["name"])
	var tmode := String(pick["mode"])
	var t2: Dictionary = {}
	if tmode == "self":
		t2 = jt
	elif tmode == "any":
		t2 = jt
	elif tmode == "other":
		var cands: Array = []
		for t in others:
			match tname:
				"突然检查", "逐近弃远":
					if not pick_card_from(t).is_empty():
						cands.append(t)
				"出其不意", "火焰试炼":
					if not (t["hand"] as Array).is_empty():
						cands.append(t)
				"借力打力":
					if not (t["equip"]["weapon"] as Dictionary).is_empty():
						cands.append(t)
				"悄悄借走":
					if eff_dist(jt, t) <= 1 and not pick_card_from(t).is_empty():
						cands.append(t)
				_:
					cands.append(t)
		if cands.is_empty():
			cands = others
		if is_ai(jt):
			var foes: Array = []
			for t in cands:
				if ai_is_enemy(jt, t):
					foes.append(t)
			t2 = foes[0] if not foes.is_empty() else cands[0]
		elif ui.has("pick_target"):
			t2 = await (ui["pick_target"] as Callable).call(jt, cands, "选择「%s」的目标" % tname)
		if t2.is_empty():
			t2 = cands[0]
	# 支付代价：全部手牌弃置，其中一张留作此锦囊的载体（改名后由 play_card 正常打出并弃置）
	# V0.24 修复：旧版把第一张手牌的牌名直接改写成目标锦囊名（实体牌被永久改名，牌堆构成被破坏，如一张「闪避」从此变成「灵感爆发」）；
	# 改为弃置全部手牌，以一张虚拟牌（花色点数取第一张，无应变词条）结算，对照 noname 视为牌 VCard
	var cost: Array = (jt["hand"] as Array).duplicate()
	var first: Dictionary = cost[0]
	var vcard := {"name": tname, "suit": String(first["suit"]), "point": int(first["point"]), "nature": "", "yb": [], "virtual": true, "src_cards": cost}
	for c in cost:
		discard_from_hand(jt, c)
	log_msg("「继往开来」：%s 将全部 %d 张手牌当作「%s」使用！" % [pname(jt), cost.size(), tname])
	(jt["hand"] as Array).append(vcard)
	await play_card(jt, vcard, t2)
	# 虚拟牌不进入弃牌堆（play_card 内的弃置会把它放进去，这里收回）
	(jt["hand"] as Array).erase(vcard)
	discard_pile.erase(vcard)
	deck.erase(vcard)
	for q in players:
		for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
			if (q["equip"][slot] as Dictionary) == vcard:
				q["equip"][slot] = {}
		(q["judge"] as Array).erase(vcard)
		(q["hand"] as Array).erase(vcard)


func play_card(p: Dictionary, card: Dictionary, tgt: Dictionary, forced_entry: Dictionary = {}) -> void:
	var nm := String(card["name"])
	var kind := CardDefs.kind_of(nm)
	if kind == "锦囊牌" or kind == "延时锦囊":
		fx("trick", {"seat": int(p["seat"]), "name": nm})
	var is_equip := kind == "武器" or kind == "防具" or kind == "饰品"
	if ui.has("played") and nm != "突击" and not is_equip:
		(ui["played"] as Callable).call(card, pname(p), pname(tgt) if not tgt.is_empty() and tgt != p else "")
		await pace(0.3)
	if not tgt.is_empty() and tgt != p and nm != "突击":
		fx("target", {"src_seat": int(p["seat"]), "tgt_seat": int(tgt["seat"])})
	if is_equip:
		play_equip(p, card)
		return
	if not tgt.is_empty() and tgt != p and nm in ["突然检查", "悄悄借走", "单挑", "火焰试炼", "借力打力", "羁绊锁链", "弃甲曳兵", "逐近弃远", "出其不意"]:
		observe_hostile(p, tgt)
	var yb_no_window := false
	if nm == "逐近弃远" and (card.get("yb", []) as Array).has("强命"):
		var hidx := (p["hand"] as Array).find(card)
		if hidx >= 0:
			(p["hand"] as Array).remove_at(hidx)
			var ybq := eval_yingbian(p, card)
			if bool(ybq["triggered"]) and (ybq["effs"] as Array).has("强命"):
				yb_no_window = true
				log_msg("「应变·强命」：%s 的 %s 满足【%s】，此次使用不可被看破。" % [pname(p), card_text(card), "·".join(PackedStringArray(ybq["conds"]))])
				fx("yingbian", {"seat": int(p["seat"]), "text": "应变·强命"})
			(p["hand"] as Array).insert(hidx, card)
	# V0.24/V0.33 修复：单目标普通锦囊在声明使用后即离手进入弃牌堆/处理区，再开看破窗口——
	# 这样看破【空巢·反甲】在窗口期即可从弃牌堆获得该锦囊实体牌（对齐无名杀原版时序）
	var single_win_tricks := ["突然检查", "悄悄借走", "单挑", "借力打力", "火焰试炼", "羁绊锁链", "声东击西", "增兵减灶", "弃甲曳兵", "逐近弃远", "出其不意", "洞烛先机", "继往开来"]
	if nm in single_win_tricks:
		discard_from_hand(p, card)
		if not yb_no_window and await nullify_window(nm, p, tgt, card):
			log_msg("%s 的「%s」被看破，未生效。" % [pname(p), nm])
			return
	if kind == "延时锦囊":
		if nm == "落雷" or nm == "浮雷":
			tgt = p  # V0.28：对照无名杀「闪电/浮雷」——只能放进自己的判定区
		(p["hand"] as Array).erase(card)
		card["placer"] = int(p["seat"])
		(tgt["judge"] as Array).append(card)
		log_msg("%s 将 %s 放入 %s 的判定区。" % [pname(p), card_text(card), pname(tgt)])
		return
	match nm:
		"突击":
			await use_attack(p, tgt, card)
		"补给":
			use_supply(p, card, p)  # V0.28：对照无名杀「桃」——出牌阶段只能对自己使用
		"特饮":
			use_drink(p, card)
		"攻守兼备":
			discard_from_hand(p, card)
			var gs_choice := "弹幕齐射"
			if is_ai(p):
				if ai_taoyuan_gain(p) > 0:
					gs_choice = "全员休整"
			elif ui.has("pick_option"):
				var gv: Variant = await (ui["pick_option"] as Callable).call(p, [{"label": "当作「弹幕齐射」使用（全体其他角色需出闪避）", "value": "弹幕齐射"}, {"label": "当作「全员休整」使用（全体受伤角色回 1 点体力）", "value": "全员休整"}], "「攻守兼备」：选择用法")
				gs_choice = String(gv)
			log_msg("%s 将「攻守兼备」当作「%s」使用！" % [pname(p), gs_choice])
			if gs_choice == "全员休整":
				await effect_taoyuan(p, card, "全员休整")
			else:
				await effect_wanjian(p, card, "弹幕齐射")
		"进退自如":
			discard_from_hand(p, card)
			var jt_choice := "物资发放"
			if is_ai(p):
				jt_choice = "全场乱斗" if count_enemies(p) >= 1 and alive_players().size() >= 3 else "物资发放"
			elif ui.has("pick_option"):
				var jv: Variant = await (ui["pick_option"] as Callable).call(p, [{"label": "当作「全场乱斗」使用（全体其他角色需出突击）", "value": "全场乱斗"}, {"label": "当作「物资发放」使用（亮出存活人数张牌轮流拿取）", "value": "物资发放"}], "「进退自如」：选择用法")
				jt_choice = String(jv)
			log_msg("%s 将「进退自如」当作「%s」使用！" % [pname(p), jt_choice])
			if jt_choice == "全场乱斗":
				await effect_nanman(p, card, "全场乱斗")
			else:
				await effect_wugu(p, card, "物资发放")
		"继往开来":
			var jw_tgt: Dictionary = tgt if not tgt.is_empty() else p
			if (jw_tgt["hand"] as Array).is_empty():
				log_msg("「继往开来」：%s 没有手牌，不生效。" % pname(jw_tgt))
			else:
				var jw_choice := 0
				if is_ai(jw_tgt):
					jw_choice = 0 if (jw_tgt["hand"] as Array).size() > 2 else 1
				elif ui.has("pick_option"):
					var wv: Variant = await (ui["pick_option"] as Callable).call(jw_tgt, [{"label": "弃置所有手牌，然后摸等量的牌", "value": 0}, {"label": "将所有手牌当做一张普通锦囊牌使用", "value": 1}], "「继往开来」：%s，请选择一项" % pname(jw_tgt))
					jw_choice = int(wv)
				if jw_choice == 0:
					var cnt := (jw_tgt["hand"] as Array).size()
					for c in (jw_tgt["hand"] as Array).duplicate():
						discard_from_hand(jw_tgt, c)
					draw_cards(jw_tgt, cnt)
					log_msg("「继往开来」：%s 弃置全部手牌并摸 %d 张牌。" % [pname(jw_tgt), cnt])
				else:
					await jiwang_use_as_trick(jw_tgt)
		"出其不意":
			if (tgt["hand"] as Array).is_empty():
				log_msg("「出其不意」：%s 已没有手牌，不生效。" % pname(tgt))
			else:
				var shown: Dictionary = {}
				if is_ai(p):
					var th: Array = tgt["hand"]
					shown = th[randi() % th.size()]
				elif ui.has("pick_from_hand"):
					shown = await (ui["pick_from_hand"] as Callable).call(p, tgt)
					if shown.is_empty():
						var th2: Array = tgt["hand"]
						shown = th2[randi() % th2.size()]
				log_msg("%s「出其不意」：展示了 %s 的手牌 %s。" % [pname(p), pname(tgt), card_text(shown)])
				fx("target", {"src_seat": int(p["seat"]), "tgt_seat": int(tgt["seat"])})
				if String(shown["suit"]) != String(card["suit"]):
					log_msg("花色不同（%s ≠ %s），「出其不意」命中！" % [String(shown["suit"]), String(card["suit"])])
					await damage(p, tgt, 1, "出其不意")
				else:
					log_msg("花色相同（%s），「出其不意」未造成伤害。" % String(card["suit"]))
		"洞烛先机":
			var dz_tgt: Dictionary = tgt if not tgt.is_empty() else p
			await do_guanxing(dz_tgt, 2)
			draw_cards(dz_tgt, 2)
			log_msg("%s 使用「洞烛先机」：%s 卜算 2 并摸 2 张牌。" % [pname(p), pname(dz_tgt)])
		"灵感爆发":
			discard_from_hand(p, card)
			if await nullify_window(nm, p, p, card):
				log_msg("%s 的「灵感爆发」被看破。" % pname(p))
			else:
				draw_cards(p, 2)
				log_msg("%s 使用「灵感爆发」，摸 2 张牌。" % pname(p))
		"突然检查":
			var taken: Dictionary = forced_entry if owns_card(tgt, forced_entry) else pick_card_from(tgt, p)
			if not taken.is_empty():
				remove_card_anywhere(tgt, taken)
				discard_pile.append(taken)
				log_msg("%s「突然检查」：弃置 %s 的 %s。" % [pname(p), pname(tgt), card_text(taken)])
		"悄悄借走":
			var taken2: Dictionary = forced_entry if owns_card(tgt, forced_entry) else pick_card_from(tgt, p)
			if not taken2.is_empty():
				remove_card_anywhere(tgt, taken2)
				gain_card(p, taken2)
				log_msg("%s「悄悄借走」：拿走 %s 的 %s。" % [pname(p), pname(tgt), card_text(taken2)])
		"单挑":
			await resolve_duel(p, tgt)
		"借力打力":
			var a := tgt
			var cands: Array = []
			# V0.24 修复：排除处于「星眠」保护（不能成为突击目标）的角色——旧版选中后突击被拦下，借刀既不出杀也不交武器
			for t in players:
				if t != a and t["alive"] and in_attack_range(a, t) and not bool(t.get("dream_guard", false)):
					cands.append(t)
			var b: Dictionary = {}
			if not cands.is_empty():
				if is_ai(p):
					var pool: Array = []
					if ai_is_enemy(p, a):
						for t in cands:
							if not ai_is_enemy(a, t):
								pool.append(t)
					if pool.is_empty():
						for t in cands:
							if ai_is_enemy(a, t):
								pool.append(t)
					if pool.is_empty():
						pool = cands
					var bhp := 999
					for t in pool:
						if int(t["hp"]) < bhp:
							bhp = int(t["hp"])
							b = t
				elif ui.has("pick_target"):
					b = await (ui["pick_target"] as Callable).call(p, cands, "选择 %s 要攻击的目标" % pname(a))
			if b.is_empty():
				log_msg("「借力打力」：%s 的攻击范围内没有目标，作罢。" % pname(a))
			else:
				var atk := find_in_hand(a, "突击")
				var will := false
				if not atk.is_empty():
					if is_ai(a):
						will = ai_is_enemy(a, b)
					elif ui.has("ask_respond"):
						will = bool(await (ui["ask_respond"] as Callable).call(a, "突击", "「借力打力」要求你攻击 %s，否则你的武器归 %s" % [pname(b), pname(p)]))
				if will:
					log_msg("%s 在「借力打力」下对 %s 出「突击」。" % [pname(a), pname(b)])
					await use_attack(a, b, atk)
				else:
					var w: Dictionary = a["equip"]["weapon"]
					a["equip"]["weapon"] = {}
					gain_card(p, w)
					changed()
					log_msg("%s 未出「突击」，其武器 %s 归 %s 所有。" % [pname(a), card_text(w), pname(p)])
		"火焰试炼":
			var thand: Array = (tgt["hand"] as Array).duplicate()
			var reveal: Dictionary = {}
			if not thand.is_empty():
				if is_ai(tgt):
					reveal = thand[randi() % thand.size()]
				elif ui.has("pick_card"):
					reveal = await (ui["pick_card"] as Callable).call(tgt, thand, "火焰试炼：选择一张手牌展示")
					if reveal.is_empty():
						reveal = thand[randi() % thand.size()]
				else:
					reveal = thand[0]
			if reveal.is_empty():
				log_msg("「火焰试炼」：%s 没有手牌可展示，作罢。" % pname(tgt))
			else:
				if ui.has("played"):
					(ui["played"] as Callable).call(reveal, pname(tgt))
				log_msg("%s 在「火焰试炼」中展示了 %s。" % [pname(tgt), card_text(reveal)])
				var suit := String(reveal["suit"])
				var matches: Array = []
				for c in p["hand"]:
					if String(c["suit"]) == suit:
						matches.append(c)
				var use_c: Dictionary = {}
				if not matches.is_empty():
					if is_ai(p):
						use_c = matches[0]
					elif ui.has("pick_card"):
						use_c = await (ui["pick_card"] as Callable).call(p, matches, "弃置一张 %s 牌，对 %s 造成 1 点火焰伤害？" % [suit, pname(tgt)])
				if use_c.is_empty():
					log_msg("%s 没有弃置 %s 牌，「火焰试炼」无事发生。" % [pname(p), suit])
				else:
					discard_from_hand(p, use_c)
					log_msg("%s 弃置 %s，「火焰试炼」命中！" % [pname(p), card_text(use_c)])
					await damage(p, tgt, 1, "火焰试炼", "火")
		"羁绊锁链":
			toggle_chain(tgt)
			var cands2: Array = []
			for t in players:
				if t != tgt and t["alive"]:
					cands2.append(t)
			var t2: Dictionary = {}
			if not cands2.is_empty():
				if is_ai(p) and ai_chain_second.has("t"):
					var pre2: Dictionary = ai_chain_second["t"]
					if not pre2.is_empty() and cands2.has(pre2):
						t2 = pre2
				elif is_ai(p):
					var bhp2 := -1
					for t in cands2:
						if ai_is_enemy(p, t) and not bool(t.get("chained", false)) and int(t["hp"]) > bhp2:
							bhp2 = int(t["hp"])
							t2 = t
				elif ui.has("pick_option"):
					var opts: Array = []
					for t in cands2:
						opts.append({"label": pname(t), "value": t})
					opts.append({"label": "只连一人", "value": {}})
					var v2: Variant = await (ui["pick_option"] as Callable).call(p, opts, "「羁绊锁链」：可再选择一名角色")
					if v2 is Dictionary:
						t2 = v2
			if not t2.is_empty():
				toggle_chain(t2)
		"全场乱斗":
			discard_from_hand(p, card)
			await effect_nanman(p, card, "全场乱斗")
		"弹幕齐射":
			discard_from_hand(p, card)
			await effect_wanjian(p, card, "弹幕齐射")
		"水淹七军":
			# 对照无名杀 shuiyanqijunx：单目标锦囊（V0.19 起由全体改为单目标，应变·目标+可追加一名）
			discard_from_hand(p, card)
			log_msg("%s 使用「水淹七军」！" % pname(p))
			var sy_extra := await yb_trick_extra(p, card, tgt)
			var sy_targets: Array = []
			if not tgt.is_empty() and tgt != p and bool(tgt["alive"]):
				sy_targets.append(tgt)
			if not sy_extra.is_empty() and bool(sy_extra["alive"]):
				sy_targets.append(sy_extra)
			for t in sy_targets:
				if not t["alive"] or game_over:
					continue
				if await nullify_window(nm, p, t, card):
					log_msg("「水淹七军」对 %s 被看破。" % pname(t))
					continue
				await shuiyan_resolve(p, t)
		"逐近弃远":
			var zj_extra := await yb_trick_extra(p, card, tgt)
			zhujin_resolve(p, tgt, forced_entry)
			if not zj_extra.is_empty() and bool(zj_extra["alive"]) and p["alive"] and not game_over:
				if await nullify_window(nm, p, zj_extra, card):
					log_msg("「逐近弃远」对追加目标 %s 被看破。" % pname(zj_extra))
				else:
					zhujin_resolve(p, zj_extra)
		"声东击西":
			if alive_players().size() <= 2:
				draw_cards(p, 1)
				log_msg("「声东击西」只剩两名角色，改为重铸：%s 摸 1 张牌。" % pname(p))
				return
			var give := {}
			if is_ai(p):
				give = ai_pick_discard(p)
			elif ui.has("choose_discard"):
				give = await (ui["choose_discard"] as Callable).call(p)
			if give.is_empty():
				give = ai_pick_discard(p)
			if not give.is_empty():
				(p["hand"] as Array).erase(give)
				(tgt["hand"] as Array).append(give)
				log_msg("%s 交给 %s 一张手牌。" % [pname(p), pname(tgt)])
				changed()
			var recv: Dictionary = {}
			if is_ai(p):
				recv = p
			elif ui.has("pick_option"):
				var ropts: Array = [{"label": pname(p) + "（你）", "value": p}]
				for q in players:
					if q != p and q != tgt and q["alive"]:
						ropts.append({"label": pname(q), "value": q})
				var rv: Variant = await (ui["pick_option"] as Callable).call(p, ropts, "「声东击西」：%s 要将两张牌交给谁？" % pname(tgt))
				if rv is Dictionary and not (rv as Dictionary).is_empty():
					recv = rv
			if recv.is_empty():
				recv = p
			var give_n := mini(2, (tgt["hand"] as Array).size())
			var moved_n := 0
			for i in give_n:
				var gc := {}
				if is_ai(tgt):
					gc = ai_pick_discard(tgt)
				elif ui.has("choose_discard"):
					gc = await (ui["choose_discard"] as Callable).call(tgt)
				if gc.is_empty():
					gc = ai_pick_discard(tgt)
				if gc.is_empty():
					break
				(tgt["hand"] as Array).erase(gc)
				(recv["hand"] as Array).append(gc)
				moved_n += 1
			if moved_n > 0:
				log_msg("%s 将 %d 张牌交给 %s。" % [pname(tgt), moved_n, pname(recv)])
				changed()
		"增兵减灶":
			draw_cards(tgt, 3)
			log_msg("「增兵减灶」：%s 摸 3 张牌。" % pname(tgt))
			var nonbasic: Array = []
			for c in tgt["hand"]:
				if CardDefs.kind_of(String(c["name"])) != "基本牌":
					nonbasic.append(c)
			var opt2 := false
			if nonbasic.is_empty() or (tgt["hand"] as Array).size() < 2:
				opt2 = not nonbasic.is_empty() and (tgt["hand"] as Array).size() >= 2
				if nonbasic.is_empty():
					opt2 = true
			elif is_ai(tgt):
				opt2 = false
			elif ui.has("pick_option"):
				var ov: Variant = await (ui["pick_option"] as Callable).call(tgt, [{"label": "弃置一张非基本牌", "value": false}, {"label": "弃置两张牌", "value": true}], "「增兵减灶」：选择要付出的代价")
				opt2 = bool(ov)
			if not opt2:
				var dc := {}
				if is_ai(tgt):
					dc = nonbasic[0]
				elif ui.has("choose_discard"):
					dc = await (ui["choose_discard"] as Callable).call(tgt)
				if dc.is_empty():
					dc = ai_pick_discard(tgt)
				if not dc.is_empty():
					discard_from_hand(tgt, dc)
					log_msg("%s 弃置了 %s。" % [pname(tgt), card_text(dc)])
			else:
				for i in 2:
					var dc2 := {}
					if is_ai(tgt):
						dc2 = ai_pick_discard(tgt)
					elif ui.has("choose_discard"):
						dc2 = await (ui["choose_discard"] as Callable).call(tgt)
					if dc2.is_empty():
						dc2 = ai_pick_discard(tgt)
					if dc2.is_empty():
						break
					discard_from_hand(tgt, dc2)
					log_msg("%s 弃置了 %s。" % [pname(tgt), card_text(dc2)])
		"弃甲曳兵":
			var cntA := 0
			var cntB := 0
			for c in tgt["hand"]:
				var kn := String(c["name"])
				var kd := CardDefs.kind_of(kn)
				if kd == "武器" or kn == "疾行之靴":
					cntA += 1
				elif kd == "防具" or kn == "远行披风":
					cntB += 1
			if not (tgt["equip"]["weapon"] as Dictionary).is_empty():
				cntA += 1
			if not (tgt["equip"]["minus"] as Dictionary).is_empty():
				cntA += 1
			if not (tgt["equip"]["armor"] as Dictionary).is_empty():
				cntB += 1
			if not (tgt["equip"]["plus"] as Dictionary).is_empty():
				cntB += 1
			var sideA := true
			if is_ai(tgt):
				sideA = cntA <= cntB
			elif ui.has("pick_option"):
				var sv: Variant = await (ui["pick_option"] as Callable).call(tgt, [{"label": "弃武器与疾行之靴（%d 张）" % cntA, "value": true}, {"label": "弃防具与远行披风（%d 张）" % cntB, "value": false}], "「弃甲曳兵」：选择要弃置的一侧")
				sideA = bool(sv)
			var dropped := 0
			var hand_copy: Array = (tgt["hand"] as Array).duplicate()
			for c in hand_copy:
				var kn2 := String(c["name"])
				var kd2 := CardDefs.kind_of(kn2)
				var hit := (kd2 == "武器" or kn2 == "疾行之靴") if sideA else (kd2 == "防具" or kn2 == "远行披风")
				if hit:
					(tgt["hand"] as Array).erase(c)
					discard_pile.append(c)
					dropped += 1
			for slot in (["weapon", "minus"] if sideA else ["armor", "plus"]):
				var eq: Dictionary = tgt["equip"][slot]
				if not eq.is_empty():
					remove_card_anywhere(tgt, eq)
					discard_pile.append(eq)
					dropped += 1
			log_msg("%s 被「弃甲曳兵」：弃置了 %d 张牌（%s）。" % [pname(tgt), dropped, "武器侧" if sideA else "防具侧"])
			changed()
		"全员休整":
			discard_from_hand(p, card)
			await effect_taoyuan(p, card, "全员休整")
		"物资发放":
			discard_from_hand(p, card)
			await effect_wugu(p, card, "物资发放")


func resolve_duel(a: Dictionary, b: Dictionary) -> void:
	log_msg("%s 与 %s 单挑！" % [pname(a), pname(b)])
	var cur := b
	var other := a
	var guard := 0
	while guard < 20:
		guard += 1
		var ok := await respond_with(cur, "突击", "单挑")
		if not ok:
			await damage(other, cur, 1, "单挑")
			return
		var tmp := cur
		cur = other
		other = tmp


func count_enemies(p: Dictionary) -> int:
	var n := 0
	for t in players:
		if t != p and t["alive"] and ai_is_enemy(p, t):
			n += 1
	return n


# 落雷/浮雷放自己判定区的意愿：会在全场轮转，敌人多于己方（含自己）且自己血量不危险时才放
func ai_want_lightning(p: Dictionary, nm: String) -> bool:
	for c in p["judge"]:
		if String(c["name"]) == nm:
			return false
	# 僵局破除：对局拖长（20 轮以上）且自己体力不低时也愿意放，让伤害在场上流转
	if round_no >= 20 and int(p["hp"]) >= 3:
		return true
	if int(p["hp"]) <= 3 and nm == "落雷":
		return false
	if int(p["hp"]) <= 2:
		return false
	var en := 0
	var al := 0
	for t in players:
		if not t["alive"]:
			continue
		if t == p or ai_is_ally(p, t):
			al += 1
		elif ai_is_enemy(p, t):
			en += 1
	if mode == "identity" and String(p["identity"]) == "内奸":
		return players.filter(func(t: Dictionary) -> bool: return bool(t["alive"])).size() > 2
	return en > al


func pick_delayed_target(p: Dictionary, dname: String) -> Dictionary:
	var best: Dictionary = {}
	var best_hp := -1
	for t in players:
		if t == p or not t["alive"] or not ai_is_enemy(p, t):
			continue
		if dname == "断粮封锁" and eff_dist(p, t) > 1:
			continue  # V0.28：对照无名杀「兵粮寸断」range global 1
		var has := false
		for c in t["judge"]:
			if String(c["name"]) == dname:
				has = true
		if has:
			continue
		if int(t["hp"]) > best_hp:
			best_hp = int(t["hp"])
			best = t
	return best


func pick_card_target(p: Dictionary, dist1: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_n := -1
	for t in players:
		if t == p or not t["alive"] or not ai_is_enemy(p, t):
			continue
		if not target_has_cards(t):
			continue
		if dist1 and eff_dist(p, t) > 1:
			continue
		var cnt := (t["hand"] as Array).size()
		if cnt > best_n:
			best_n = cnt
			best = t
	return best


func pick_duel_target(p: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_n := 999
	for t in players:
		if t == p or not t["alive"] or not ai_is_enemy(p, t):
			continue
		if (t["hand"] as Array).size() < best_n:
			best_n = (t["hand"] as Array).size()
			best = t
	return best


# ================= 选择助手（对照 noname 的 chooseCard/chooseTarget/chooseControl） =================
func is_human(p: Dictionary) -> bool:
	return ui.has("is_human") and bool((ui["is_human"] as Callable).call(p))


func pick_card(p: Dictionary, opts: Dictionary) -> Dictionary:
	var cands: Array = []
	for c in p["hand"]:
		if opts.has("names") and not (opts["names"] as Array).has(String(c["name"])):
			continue
		if bool(opts.get("red_only", false)) and not is_red(c):
			continue
		if bool(opts.get("black_only", false)) and not is_black(c):
			continue
		cands.append(c)
	if cands.is_empty():
		return {}
	if is_human(p) and ui.has("pick_card"):
		var got = await (ui["pick_card"] as Callable).call(p, cands, String(opts.get("prompt", "选择一张手牌")))
		if got is Dictionary:
			return got
		return {}
	if opts.has("ai"):
		var got2 = (opts["ai"] as Callable).call(self, p, cands)
		if got2 is Dictionary:
			return got2
	return cands[0]


func pick_target(p: Dictionary, cands: Array, prompt: String, ai: Callable) -> Dictionary:
	if cands.is_empty():
		return {}
	if is_human(p) and ui.has("pick_target"):
		var got = await (ui["pick_target"] as Callable).call(p, cands, prompt)
		if got is Dictionary:
			return got
		return {}
	if ai.is_valid():
		var got2 = ai.call(self, p, cands)
		if got2 is Dictionary:
			return got2
	return cands[0]


func pick_option(p: Dictionary, options: Array, prompt: String, ai_value: Variant) -> Variant:
	if is_human(p) and ui.has("pick_option"):
		return await (ui["pick_option"] as Callable).call(p, options, prompt)
	return ai_value


func mark_round(p: Dictionary, key: String) -> void:
	(p["round_marks"] as Dictionary)[key] = true


func round_marked(p: Dictionary, key: String) -> bool:
	return bool((p["round_marks"] as Dictionary).get(key, false))



func active_options(p: Dictionary) -> Array:
	var out: Array = []
	if not p["alive"]:
		return out
	for sid in (p["skills"] as Array):
		var def: Dictionary = skill_lib.get(sid, {})
		if def.is_empty() or not def.has("active"):
			continue
		if bool((p["turn_used"] as Dictionary).get(sid, false)):
			continue
		if bool(def.get("limited", false)) and bool(p.get("limited_used_" + String(sid), false)):
			continue
		var act: Dictionary = def["active"]
		if act.has("filter") and not bool((act["filter"] as Callable).call(self, p)):
			continue
		out.append({"sid": sid, "name": String(def.get("name", sid))})
	return out


func use_active_skill(p: Dictionary, sid: String) -> void:
	var def: Dictionary = skill_lib.get(sid, {})
	if def.is_empty() or not def.has("active"):
		return
	p["turn_used"][sid] = true
	if bool(def.get("limited", false)):
		p["limited_used_" + String(sid)] = true
	fx("skill", {"seat": int(p["seat"]), "name": String(def.get("name", sid)), "sid": sid, "big": true})
	await (def["active"]["content"] as Callable).call(self, p)
	changed()
