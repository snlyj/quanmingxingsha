extends RefCounted

# 全明星杀 · 技能库（星樱坂学园包）：按无名杀技能定义格式注册进新引擎
# def = {name, timings={时机:{who, priority, filter, content, forced, ai_decide}}, active={filter, content, ai_use}}
# 技能规则文本与设计稿 v1.1 一致；V0.28 起「星眠」保护期按设计稿改为「到本回合结束」（引擎 run_turn 结束阶段后解除）。


func register_all(eng) -> void:
	eng.register_skill("huayu", {"name": "花愈", "timings": {"damageAfter": {"who": "player", "filter": Callable(self, "_huayu_filter"), "content": Callable(self, "_huayu_content")}}})
	eng.register_skill("yingyuan", {"name": "樱愿", "active": {"filter": Callable(self, "_hand_ge1"), "ai_use": Callable(self, "_yingyuan_aiuse"), "content": Callable(self, "_yingyuan_content")}})
	eng.register_skill("fengji", {"name": "风纪", "active": {"filter": Callable(self, "_fengji_filter"), "ai_use": Callable(self, "_yes"), "content": Callable(self, "_fengji_content")}})
	eng.register_skill("linghu", {"name": "铃护", "timings": {"damageBefore": {"who": "player", "priority": 10, "filter": Callable(self, "_linghu_filter"), "ai_decide": Callable(self, "_linghu_ai"), "content": Callable(self, "_linghu_content")}}})
	eng.register_skill("xinqu", {"name": "心曲", "timings": {"phaseZhunbeiStart": {"who": "player", "filter": Callable(self, "_others_exist"), "content": Callable(self, "_xinqu_content")}}})
	eng.register_skill("gesheng", {"name": "歌声", "active": {"filter": Callable(self, "_others_exist_p"), "ai_use": Callable(self, "_yes"), "content": Callable(self, "_gesheng_content")}})
	eng.register_skill("buqu", {"name": "不屈", "timings": {"damageAfter": {"who": "player", "forced": true, "content": Callable(self, "_buqu_content")}}})
	eng.register_skill("yuanqi", {"name": "元气补给", "active": {"filter": Callable(self, "_yuanqi_filter"), "ai_use": Callable(self, "_yuanqi_ai"), "content": Callable(self, "_yuanqi_content")}})
	eng.register_skill("xingmian", {"name": "星眠", "timings": {"phaseZhunbeiStart": {"who": "player", "ai_decide": Callable(self, "_xingmian_ai"), "content": Callable(self, "_xingmian_content")}, "phaseJieshu": {"who": "player", "forced": true, "filter": Callable(self, "_xingmian_end_filter"), "content": Callable(self, "_xingmian_end_content")}}})
	eng.register_skill("chahui", {"name": "茶会", "active": {"filter": Callable(self, "_chahui_filter"), "ai_use": Callable(self, "_chahui_aiuse"), "content": Callable(self, "_chahui_content")}})
	eng.register_skill("qinyin", {"name": "琴音", "active": {"filter": Callable(self, "_qinyin_filter"), "ai_use": Callable(self, "_qinyin_aiuse"), "content": Callable(self, "_qinyin_content")}})
	eng.register_skill("nuhe", {"name": "怒喝", "timings": {"attackDodged": {"who": "source", "filter": Callable(self, "_nuhe_filter"), "ai_decide": Callable(self, "_nuhe_ai"), "content": Callable(self, "_nuhe_content")}}})
	eng.register_skill("shifeng", {"name": "侍奉", "active": {"filter": Callable(self, "_shifeng_filter"), "ai_use": Callable(self, "_shifeng_aiuse"), "content": Callable(self, "_shifeng_content")}})
	eng.register_skill("maobu", {"name": "猫步", "timings": {"useCardBegin": {"who": "target", "priority": 10, "filter": Callable(self, "_maobu_filter"), "ai_decide": Callable(self, "_maobu_ai"), "content": Callable(self, "_maobu_content")}}})


# ---------- 通用小工具 ----------
func _yes(eng, p) -> bool:
	return true


func _hand_ge1(eng, p) -> bool:
	return not (p["hand"] as Array).is_empty()


func _others_exist(eng, ctx, p) -> bool:
	for t in eng.players:
		if t != p and t["alive"]:
			return true
	return false


func _others_exist_p(eng, p) -> bool:
	return _others_exist(eng, {}, p)


func _worst_card(eng, p, cands) -> Dictionary:
	var pref := ["突击", "特饮", "全场乱斗", "弹幕齐射", "单挑", "悄悄借走", "突然检查", "灵感爆发", "闪避", "补给"]
	# V0.30：本回合还能出「突击」且有够得着的敌人时，留下最后一张突击（参照无名杀 get.value：可用的杀价值更高）
	if eng.turn_player == p and not bool(p.get("used_attack", false)):
		var atk_n := 0
		for c in p["hand"]:
			if String(c["name"]) == "突击":
				atk_n += 1
		if atk_n == 1 and not eng.ai_pick_target(p, true).is_empty():
			pref = ["特饮", "全场乱斗", "弹幕齐射", "单挑", "悄悄借走", "突然检查", "灵感爆发", "闪避", "补给", "突击"]
	for want in pref:
		for c in cands:
			if String(c["name"]) == want:
				return c
	return cands[cands.size() - 1]


func _best_victim_card(eng, victim) -> Dictionary:
	var pref := ["补给", "特饮", "灵感爆发", "突击", "闪避", "落雷", "全员休整"]
	for want in pref:
		for c in victim["hand"]:
			if String(c["name"]) == want:
				return c
	if not (victim["hand"] as Array).is_empty():
		return (victim["hand"] as Array)[0]
	return {}


func _enemy_most_cards(eng, p, cands) -> Dictionary:
	var best: Dictionary = {}
	var bn := -1
	for t in cands:
		if (t["hand"] as Array).size() > bn:
			bn = (t["hand"] as Array).size()
			best = t
	return best


func _ally_least_cards(eng, p, cands) -> Dictionary:
	var best: Dictionary = {}
	var bn := 999
	for t in cands:
		if not eng.ai_is_enemy(p, t) and (t["hand"] as Array).size() < bn:
			bn = (t["hand"] as Array).size()
			best = t
	if best.is_empty():
		return cands[0]
	return best


# ---------- 花宫雏 ----------
func _huayu_filter(eng, ctx, p) -> bool:
	return int(p["hp"]) < int(p["max_hp"]) and not eng.round_marked(p, "huayu")


func _huayu_content(eng, ctx, p) -> void:
	eng.mark_round(p, "huayu")
	var jc: Dictionary = eng.do_judge(p, "花愈")
	if not jc.is_empty() and eng.is_red(jc):
		eng.log_msg("「花愈」判定为红色，%s 回复 1 点体力。" % eng.pname(p))
		eng.heal(p, 1)


func _yingyuan_aiuse(eng, p) -> bool:
	return (p["hand"] as Array).size() >= 3


func _yingyuan_content(eng, p) -> void:
	var cost: Dictionary = await eng.pick_card(p, {"prompt": "「樱愿」：弃置 1 张手牌作为代价", "ai": Callable(self, "_worst_card")})
	if cost.is_empty():
		return
	eng.discard_from_hand(p, cost)
	var cands: Array = []
	for t in eng.players:
		if t["alive"]:
			cands.append(t)
	var tgt: Dictionary = await eng.pick_target(p, cands, "「樱愿」：选择一名角色", Callable(self, "_yingyuan_target"))
	if tgt.is_empty():
		return
	var opts: Array = [{"label": "摸 2 张牌", "value": "draw"}]
	if int(tgt["hp"]) < int(tgt["max_hp"]):
		opts.append({"label": "回复 1 点体力", "value": "heal"})
	var heal_line := 1 if int(eng.round_no) >= 30 else 2
	var ai_v := "heal" if int(tgt["hp"]) <= heal_line and int(tgt["hp"]) < int(tgt["max_hp"]) else "draw"
	var v = await eng.pick_option(tgt, opts, "%s 选择「樱愿」的效果" % eng.pname(tgt), ai_v)
	if String(v) == "heal":
		eng.heal(tgt, 1, p)
		eng.log_msg("「樱愿」：%s 选择回复 1 点体力。" % eng.pname(tgt))
	else:
		eng.draw_cards(tgt, 2)
		eng.log_msg("「樱愿」：%s 选择摸 2 张牌。" % eng.pname(tgt))


func _yingyuan_target(eng, p, cands) -> Dictionary:
	if int(p["hp"]) < int(p["max_hp"]):
		return p
	var best: Dictionary = {}
	var bh := 999
	for t in cands:
		if not eng.ai_is_enemy(p, t) and int(t["hp"]) < bh:
			bh = int(t["hp"])
			best = t
	return best if not best.is_empty() else p


# ---------- 柚木铃奈 ----------
func _fengji_filter(eng, p) -> bool:
	for t in eng.players:
		if t != p and t["alive"] and not (t["hand"] as Array).is_empty():
			return true
	return false


func _fengji_content(eng, p) -> void:
	var cands: Array = []
	for t in eng.players:
		if t != p and t["alive"] and not (t["hand"] as Array).is_empty():
			cands.append(t)
	var tgt: Dictionary = await eng.pick_target(p, cands, "「风纪」：选择一名角色，观看并弃置其一张手牌", Callable(self, "_enemy_most_cards"))
	if tgt.is_empty():
		return
	var names: Array = []
	for c in tgt["hand"]:
		names.append(eng.card_text(c))
	eng.log_msg("「风纪」：%s 的手牌：%s。" % [eng.pname(tgt), "、".join(names)])
	var vc: Dictionary = _best_victim_card(eng, tgt)
	if eng.is_human(p) and eng.ui.has("pick_from_hand"):
		var got = await (eng.ui["pick_from_hand"] as Callable).call(p, tgt)
		if got is Dictionary and not (got as Dictionary).is_empty():
			vc = got
	if not vc.is_empty():
		eng.discard_from_hand(tgt, vc)
		eng.log_msg("「风纪」：弃置了 %s 的 %s。" % [eng.pname(tgt), eng.card_text(vc)])


func _linghu_filter(eng, ctx, p) -> bool:
	for c in p["hand"]:
		if eng.is_red(c):
			return true
	return false


func _linghu_ai(eng, ctx, p) -> bool:
	var num := int(ctx.get("num", 1))
	if int(p["hp"]) - num <= 0:
		return true
	var reds := 0
	for c in p["hand"]:
		if eng.is_red(c):
			reds += 1
	return num >= 2 or (reds >= 2 and (p["hand"] as Array).size() >= 4)


func _linghu_content(eng, ctx, p) -> void:
	var rc: Dictionary = await eng.pick_card(p, {"prompt": "「铃护」：弃置 1 张红色手牌，防止这次伤害", "red_only": true})
	if rc.is_empty():
		return
	eng.discard_from_hand(p, rc)
	ctx["cancelled"] = true
	eng.log_msg("「铃护」：%s 弃置 %s，防止了这次伤害。" % [eng.pname(p), eng.card_text(rc)])


# ---------- 宫坂歌织 ----------
func _xinqu_content(eng, ctx, p) -> void:
	var cands: Array = []
	for t in eng.players:
		if t != p and t["alive"]:
			cands.append(t)
	var tgt: Dictionary = await eng.pick_target(p, cands, "「心曲」：选择一名角色观看手牌", Callable(self, "_enemy_most_cards"))
	if tgt.is_empty():
		return
	var names: Array = []
	var has_atk := false
	for c in tgt["hand"]:
		names.append(eng.card_text(c))
		if String(c["name"]) == "突击":
			has_atk = true
	eng.log_msg("「心曲」：%s 的手牌：%s。" % [eng.pname(tgt), "、".join(names) if not names.is_empty() else "（无手牌）"])
	if has_atk:
		eng.draw_cards(p, 1)
		eng.log_msg("「心曲」：对方有「突击」，%s 摸 1 张牌。" % eng.pname(p))


func _gesheng_content(eng, p) -> void:
	var cands: Array = []
	for t in eng.players:
		if t != p and t["alive"]:
			cands.append(t)
	var tgt: Dictionary = await eng.pick_target(p, cands, "「歌声」：选择一名角色，与你各摸 1 张牌", Callable(self, "_ally_least_cards"))
	if tgt.is_empty():
		return
	eng.draw_cards(p, 1)
	eng.draw_cards(tgt, 1)
	eng.log_msg("「歌声」：%s 与 %s 各摸 1 张牌。" % [eng.pname(p), eng.pname(tgt)])


# ---------- 森崎千夏 ----------
func _buqu_content(eng, ctx, p) -> void:
	eng.draw_cards(p, 1)
	eng.log_msg("「不屈」：%s 摸 1 张牌。" % eng.pname(p))


func _yuanqi_filter(eng, p) -> bool:
	if int(p["hp"]) >= int(p["max_hp"]):
		return false
	for c in p["hand"]:
		if eng.is_black(c):
			return true
	return false


func _yuanqi_content(eng, p) -> void:
	var bc: Dictionary = await eng.pick_card(p, {"prompt": "「元气补给」：选择一张黑色手牌当作「补给」", "black_only": true, "ai": Callable(self, "_worst_card")})
	if bc.is_empty():
		return
	eng.discard_from_hand(p, bc)
	eng.log_msg("「元气补给」：%s 把 %s 当作「补给」使用。" % [eng.pname(p), eng.card_text(bc)])
	eng.heal(p, 1)


# ---------- 夜宫静羽 ----------
func _xingmian_ai(eng, ctx, p) -> bool:
	# V0.30：残局（第 25 轮起）只在 1 血时星眠，避免与回复型角色无限拉锯（斗地主 turn_cap）
	if int(eng.round_no) >= 25:
		return int(p["hp"]) <= 1
	if int(p["hp"]) <= 2:
		return true
	if (p["hand"] as Array).size() <= 2:
		for c in p["hand"]:
			if String(c["name"]) == "突击":
				return false
		return true
	return false


# V0.30：元气补给——本回合还能出突击且手里有突击时，先出突击；体力只差 1 时不急着回复
func _yuanqi_ai(eng, p) -> bool:
	var lost := int(p["max_hp"]) - int(p["hp"])
	# V0.32：两人残局（第 25 轮起）能进攻时不回复；无法进攻时只在 1 血自救，避免身份场回合上限
	if int(eng.round_no) >= 25 and eng.alive_players().size() <= 2:
		if int(p["hp"]) > 1 and eng.ai_has_pressure_attack(p):
			return false
		return int(p["hp"]) <= 1
	# 残局（第 30 轮起）只在 2 血及以下时回复，避免与对手无限拉锯
	if int(eng.round_no) >= 30:
		return int(p["hp"]) <= 2
	if lost >= 2 or int(p["hp"]) <= 1:
		return true
	if not bool(p["used_attack"]):
		for c in p["hand"]:
			if String(c["name"]) == "突击" and not eng.ai_pick_target(p, true).is_empty():
				return false
	return true


func _xingmian_content(eng, ctx, p) -> void:
	p["skip_use"] = true
	p["dream_guard"] = true
	p["dream_pending"] = true
	eng.log_msg("「星眠」：%s 跳过出牌阶段，进星眠境（本回合结束前不能成为「突击」的目标）。" % eng.pname(p))


func _xingmian_end_filter(eng, ctx, p) -> bool:
	return bool(p.get("dream_pending", false))


func _xingmian_end_content(eng, ctx, p) -> void:
	p["dream_pending"] = false
	eng.draw_cards(p, 3)
	eng.heal(p, 1)
	eng.log_msg("「星眠」结算：%s 摸 3 张牌并回复 1 点体力。" % eng.pname(p))


func _chahui_filter(eng, p) -> bool:
	if (p["hand"] as Array).is_empty():
		return false
	for t in eng.players:
		if t != p and t["alive"] and int(t["hp"]) < int(t["max_hp"]):
			return true
	return false


func _chahui_content(eng, p) -> void:
	var cost: Dictionary = await eng.pick_card(p, {"prompt": "「茶会」：弃置 1 张手牌作为代价", "ai": Callable(self, "_worst_card")})
	if cost.is_empty():
		return
	eng.discard_from_hand(p, cost)
	var cands: Array = []
	for t in eng.players:
		if t != p and t["alive"] and int(t["hp"]) < int(t["max_hp"]):
			cands.append(t)
	var tgt: Dictionary = await eng.pick_target(p, cands, "「茶会」：选择一名已受伤的角色", Callable(self, "_chahui_target"))
	if tgt.is_empty():
		return
	eng.heal(tgt, 1, p)
	eng.log_msg("「茶会」：%s 请 %s 喝了一杯热茶。" % [eng.pname(p), eng.pname(tgt)])


# V0.24 修复：AI 只在有受伤的非敌方角色时发动「茶会」（旧版无条件发动且找不到友方时回血给 cands[0]，常给敌人回血，斗地主 1v1 残局因此久拖不决）
func _chahui_aiuse(eng, p) -> bool:
	for t in eng.players:
		if t != p and t["alive"] and int(t["hp"]) < int(t["max_hp"]) and eng.ai_is_ally(p, t):
			return (p["hand"] as Array).size() >= 2 or int(t["hp"]) <= 1
	return false


func _chahui_target(eng, p, cands) -> Dictionary:
	var best: Dictionary = {}
	var bh := 999
	for t in cands:
		if eng.ai_is_ally(p, t) and int(t["hp"]) < bh:
			bh = int(t["hp"])
			best = t
	return best if not best.is_empty() else cands[0]


# ---------- 绯山响 ----------
# V0.24 修复：可选目标改为「攻击范围内、未处于星眠保护的其他角色」——旧版用 AI 敌我推测过滤，
# 真人玩家没有推测数据，导致真人绯山响几乎永远无法发动「琴音」
func _qinyin_cands(eng, p) -> Array:
	var cands: Array = []
	for t in eng.players:
		if t != p and t["alive"] and eng.in_attack_range(p, t) and not bool(t.get("dream_guard", false)):
			cands.append(t)
	return cands


func _qinyin_filter(eng, p) -> bool:
	var has_red := false
	for c in p["hand"]:
		if eng.is_red(c):
			has_red = true
	if not has_red:
		return false
	return not _qinyin_cands(eng, p).is_empty()


func _qinyin_aiuse(eng, p) -> bool:
	var has_foe := false
	for t in _qinyin_cands(eng, p):
		if eng.ai_is_enemy(p, t):
			has_foe = true
	return has_foe and (eng.find_in_hand(p, "突击").is_empty() or bool(p["used_attack"]))


func _qinyin_content(eng, p) -> void:
	var rc: Dictionary = await eng.pick_card(p, {"prompt": "「琴音」：选择一张红色手牌当作「突击」", "red_only": true, "ai": Callable(self, "_worst_card")})
	if rc.is_empty():
		return
	var cands: Array = _qinyin_cands(eng, p)
	var tgt: Dictionary = await eng.pick_target(p, cands, "「琴音」：选择突击目标", Callable(self, "_qinyin_target"))
	if tgt.is_empty():
		# 目标没了：牌不消耗（发动中止）
		return
	eng.log_msg("「琴音」：%s 把 %s 当作「突击」使用。" % [eng.pname(p), eng.card_text(rc)])
	# V0.24 修复：以虚拟「突击」结算（花色点数取原牌、无属性、无应变词条），对照 noname viewAs 转化牌；
	# 旧版直接把原牌（如「补给」）当突击结算，牌名不是「突击」导致「猫步」等以牌名判断的效果失灵，且会误读原牌的应变词条
	eng.discard_from_hand(p, rc)
	var vsha := {"name": "突击", "suit": String(rc["suit"]), "point": int(rc["point"]), "nature": "", "yb": [], "virtual": true, "src_cards": [rc]}
	await eng.use_attack(p, tgt, vsha, false, true)


func _qinyin_target(eng, p, cands) -> Dictionary:
	var foes: Array = []
	for t in cands:
		if eng.ai_is_enemy(p, t):
			foes.append(t)
	return _weakest(eng, p, foes if not foes.is_empty() else cands)


# V0.24 修复（对照设计稿「你可以从该角色的手牌或装备区中选择 1 张牌并将其弃置」）：
# ①改为可选发动（旧版为锁定技强制发动）；②只能弃手牌或装备区的牌（旧版会拆到判定区的延时锦囊，等于帮对方解除「沉迷游戏」）；
# ③真人可自选装备或随机一张手牌（旧版由程序代选）
func _nuhe_pool(tgt: Dictionary) -> Array:
	var out: Array = []
	for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
		var e: Dictionary = tgt["equip"][slot]
		if not e.is_empty():
			out.append(e)
	return out


func _nuhe_filter(eng, ctx, p) -> bool:
	var tgt: Dictionary = ctx.get("target", {})
	if tgt.is_empty() or not bool(tgt["alive"]):
		return false
	return not (tgt["hand"] as Array).is_empty() or not _nuhe_pool(tgt).is_empty()


func _nuhe_ai(eng, ctx, p) -> bool:
	var tgt: Dictionary = ctx.get("target", {})
	return not eng.ai_is_ally(p, tgt)


func _nuhe_content(eng, ctx, p) -> void:
	var tgt: Dictionary = ctx["target"]
	var eqs := _nuhe_pool(tgt)
	var hand: Array = tgt["hand"]
	var taken: Dictionary = {}
	if eng.is_human(p) and eng.ui.has("pick_option"):
		var opts: Array = []
		for e in eqs:
			opts.append({"label": "装备：" + eng.card_text(e), "value": e})
		if not hand.is_empty():
			opts.append({"label": "手牌（随机一张，共 %d 张）" % hand.size(), "value": {"hand": true}})
		var v: Variant = await eng.ui["pick_option"].call(p, opts, "「怒喝」：弃置 %s 的一张牌" % eng.pname(tgt))
		if v is Dictionary and bool((v as Dictionary).get("hand", false)) and not hand.is_empty():
			taken = hand[randi() % hand.size()]
		elif v is Dictionary and not (v as Dictionary).is_empty():
			taken = v
	else:
		if not eqs.is_empty():
			taken = eqs[0]
		elif not hand.is_empty():
			taken = hand[randi() % hand.size()]
	if taken.is_empty():
		return
	eng.remove_card_anywhere(tgt, taken)
	eng.discard_pile.append(taken)
	eng.log_msg("「怒喝」：%s 弃置 %s 的 %s。" % [eng.pname(p), eng.pname(tgt), eng.card_text(taken)])


# ---------- 藤代小梅 ----------
func _shifeng_filter(eng, p) -> bool:
	if (p["hand"] as Array).is_empty():
		return false
	return _others_exist_p(eng, p)


func _shifeng_aiuse(eng, p) -> bool:
	return (p["hand"] as Array).size() >= 4


func _shifeng_content(eng, p) -> void:
	var give: Dictionary = await eng.pick_card(p, {"prompt": "「侍奉」：选择一张手牌交给另一名角色", "ai": Callable(self, "_worst_card")})
	if give.is_empty():
		return
	var cands: Array = []
	for t in eng.players:
		if t != p and t["alive"]:
			cands.append(t)
	var tgt: Dictionary = await eng.pick_target(p, cands, "「侍奉」：选择要侍奉的角色", Callable(self, "_ally_least_cards"))
	if tgt.is_empty():
		return
	(p["hand"] as Array).erase(give)
	eng.gain_card(tgt, give)
	eng.draw_cards(p, 2)
	eng.log_msg("「侍奉」：%s 把 %s 交给 %s，并摸 2 张牌。" % [eng.pname(p), eng.card_text(give), eng.pname(tgt)])


func _maobu_filter(eng, ctx, p) -> bool:
	var card: Dictionary = ctx.get("card", {})
	if card.is_empty() or String(card["name"]) != "突击":
		return false
	if eng.round_marked(p, "maobu"):
		return false
	for c in p["hand"]:
		if eng.is_black(c):
			return true
	return false


func _maobu_ai(eng, ctx, p) -> bool:
	var blacks := 0
	for c in p["hand"]:
		if eng.is_black(c):
			blacks += 1
	return int(p["hp"]) <= 2 or blacks >= 2 or (p["hand"] as Array).size() >= 4


func _maobu_content(eng, ctx, p) -> void:
	var bc: Dictionary = await eng.pick_card(p, {"prompt": "「猫步」：弃置 1 张黑色手牌，令这张「突击」对你无效", "black_only": true, "ai": Callable(self, "_worst_card")})
	if bc.is_empty():
		return
	eng.mark_round(p, "maobu")
	eng.discard_from_hand(p, bc)
	ctx["cancelled"] = true
	eng.log_msg("「猫步」：%s 弃置 %s，闪身躲开了这次「突击」。" % [eng.pname(p), eng.card_text(bc)])



func _weakest(eng, p, cands) -> Dictionary:
	var best: Dictionary = {}
	var bh := 999
	for t in cands:
		if int(t["hp"]) < bh:
			bh = int(t["hp"])
			best = t
	return best
