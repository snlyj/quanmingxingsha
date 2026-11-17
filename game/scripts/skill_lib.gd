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
	eng.register_skill("xinggui", {"name": "星轨", "timings": {"phaseZhunbeiStart": {"who": "player", "content": Callable(self, "_xinggui_content")}}})
	eng.register_skill("caijue", {"name": "裁决", "active": {"filter": Callable(self, "_caijue_filter"), "ai_use": Callable(self, "_caijue_aiuse"), "content": Callable(self, "_caijue_content")}})
	eng.register_skill("jianxin", {"name": "剑心", "timings": {"useCardBegin": {"who": "source", "forced": true, "priority": 5, "filter": Callable(self, "_jianxin_filter"), "content": Callable(self, "_jianxin_content")}}})
	eng.register_skill("canyue", {"name": "奥义·残月", "limited": true, "active": {"filter": Callable(self, "_canyue_filter"), "ai_use": Callable(self, "_canyue_aiuse"), "content": Callable(self, "_canyue_content")}})
	eng.register_skill("zhouye", {"name": "昼夜卷", "switchable": true, "active": {"filter": Callable(self, "_zhouye_filter"), "ai_use": Callable(self, "_zhouye_aiuse"), "content": Callable(self, "_zhouye_content")}})
	eng.register_skill("jingdu", {"name": "静读", "timings": {"phaseJieshuStart": {"who": "player", "forced": true, "filter": Callable(self, "_jingdu_filter"), "content": Callable(self, "_jingdu_content")}}})
	eng.register_skill("podi", {"name": "破的", "timings": {"damageAfter": {"who": "source", "forced": true, "filter": Callable(self, "_podi_filter"), "content": Callable(self, "_podi_content")}}})
	eng.register_skill("xinyan", {"name": "心眼觉醒", "awaken": true, "timings": {"phaseZhunbeiStart": {"who": "player", "forced": true, "filter": Callable(self, "_xinyan_filter"), "content": Callable(self, "_xinyan_content")}}})
	eng.register_skill("shenshe", {"name": "神射", "text": "出牌阶段限一次。你可以将 1 张手牌当作无距离限制且不可被「闪避」响应的「突击」使用。", "active": {"filter": Callable(self, "_shenshe_filter"), "ai_use": Callable(self, "_shenshe_aiuse"), "content": Callable(self, "_shenshe_content")}})
	eng.register_skill("cuihua", {"name": "催化", "active": {"filter": Callable(self, "_cuihua_filter"), "ai_use": Callable(self, "_cuihua_aiuse"), "content": Callable(self, "_cuihua_content")}})
	eng.register_skill("yuzhen", {"name": "余震", "timings": {"damageAfter": {"who": "global", "forced": true, "filter": Callable(self, "_yuzhen_filter"), "content": Callable(self, "_yuzhen_content")}}})
	eng.register_skill("wangshou", {"name": "王手", "active": {"filter": Callable(self, "_wangshou_filter"), "ai_use": Callable(self, "_wangshou_aiuse"), "content": Callable(self, "_wangshou_content")}})
	eng.register_skill("miaosuan", {"name": "妙算", "timings": {}})
	eng.register_skill("jingsuan", {"name": "精算", "active": {"filter": Callable(self, "_hand_ge1"), "ai_use": Callable(self, "_yes"), "content": Callable(self, "_jingsuan_content")}})
	eng.register_skill("linshuang", {"name": "凛霜", "timings": {"damageAfter": {"who": "player", "filter": Callable(self, "_linshuang_filter"), "ai_decide": Callable(self, "_linshuang_ai"), "content": Callable(self, "_linshuang_content")}}})
	eng.register_skill("mowei", {"name": "魔威", "text": "魔王技，锁定技。准备阶段摸 1 张牌；摸牌阶段多摸 1 张牌；出牌阶段可使用 2 张「突击」。", "timings": {"phaseZhunbeiStart": {"who": "player", "forced": true, "content": Callable(self, "_mowei_content")}}})
	eng.register_skill("xingshi", {"name": "星蚀", "text": "魔王技，锁定技。结束阶段开始时，若你已受伤，对一名敌方角色造成 1 点雷电伤害。", "timings": {"phaseJieshuStart": {"who": "player", "forced": true, "filter": Callable(self, "_xingshi_filter"), "content": Callable(self, "_xingshi_content")}}})
	eng.register_skill("shengdun", {"name": "圣盾", "timings": {"phaseZhunbeiStart": {"who": "player", "forced": true, "filter": Callable(self, "_shengdun_filter"), "content": Callable(self, "_shengdun_content")}}})
	eng.register_skill("yuanhu", {"name": "援护", "active": {"filter": Callable(self, "_hand_ge1"), "ai_use": Callable(self, "_yuanhu_aiuse"), "content": Callable(self, "_yuanhu_content")}})
	eng.register_skill("shiji", {"name": "时计", "active": {"filter": Callable(self, "_shiji_filter"), "ai_use": Callable(self, "_shiji_aiuse"), "content": Callable(self, "_shiji_content")}})
	eng.register_skill("xingwei", {"name": "星帷"})
	eng.register_skill("lianyu", {"name": "敛羽", "timings": {"damageAfter": {"who": "player", "forced": true, "filter": Callable(self, "_lianyu_filter"), "content": Callable(self, "_lianyu_content")}}})
	eng.register_skill("mingzha", {"name": "命札"})
	eng.register_skill("yuchen", {"name": "余谶", "timings": {"phaseZhunbeiStart": {"who": "player", "filter": Callable(self, "_yuchen_filter"), "content": Callable(self, "_yuchen_content")}}})
	eng.register_skill("pokong", {"name": "破空", "active": {"filter": Callable(self, "_pokong_filter"), "ai_use": Callable(self, "_pokong_aiuse"), "content": Callable(self, "_pokong_content")}})
	eng.register_skill("xingying_lord", {"name": "星樱号令", "text": "主公技，锁定技。你的首个准备阶段开始时，若你没有「护甲」，你获得 1 点「护甲」；其他同阵营角色在濒死时对你使用「补给」后摸 1 张牌。", "timings": {"phaseZhunbeiStart": {"who": "player", "forced": true, "filter": Callable(self, "_xingying_lord_filter"), "content": Callable(self, "_xingying_lord_content")}}})


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
	var jc: Dictionary = await eng.do_judge(p, "花愈")
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


# ---------- 白石星奈 ----------
func _xinggui_content(eng, ctx, p) -> void:
	await eng.do_guanxing(p, 2)
	eng.draw_cards(p, 1)
	eng.log_msg("「星轨」：%s 观星整理牌堆顶，并摸 1 张牌。" % eng.pname(p))


func _caijue_filter(eng, p) -> bool:
	if (p["hand"] as Array).is_empty():
		return false
	return _others_exist_p(eng, p)


func _caijue_aiuse(eng, p) -> bool:
	var has_foe := false
	for t in eng.players:
		if t != p and t["alive"] and eng.ai_is_enemy(p, t):
			has_foe = true
			if int(t["hp"]) <= 1 or (t["hand"] as Array).is_empty():
				return true
	return has_foe and (p["hand"] as Array).size() >= 2


func _caijue_target(eng, p, cands) -> Dictionary:
	var foes: Array = []
	for t in cands:
		if eng.ai_is_enemy(p, t):
			foes.append(t)
	return _weakest(eng, p, foes if not foes.is_empty() else cands)


func _caijue_content(eng, p) -> void:
	var cost: Dictionary = await eng.pick_card(p, {"prompt": "「裁决」：弃置 1 张手牌作为代价", "ai": Callable(self, "_worst_card")})
	if cost.is_empty():
		return
	eng.discard_from_hand(p, cost)
	var cands: Array = []
	for t in eng.players:
		if t != p and t["alive"]:
			cands.append(t)
	var tgt: Dictionary = await eng.pick_target(p, cands, "「裁决」：选择一名角色接受裁决", Callable(self, "_caijue_target"))
	if tgt.is_empty():
		return
	eng.observe_hostile(p, tgt)
	if (tgt["hand"] as Array).is_empty():
		eng.log_msg("「裁决」：%s 没有手牌，受到 %s 造成的 1 点雷电伤害！" % [eng.pname(tgt), eng.pname(p)])
		await eng.damage(p, tgt, 1, "裁决", "雷")
		return
	var opts: Array = [
		{"label": "交给 %s 1 张手牌" % eng.pname(p), "value": "give"},
		{"label": "受到 1 点雷电伤害", "value": "dmg"},
	]
	var ai_v := "give" if (int(tgt["hp"]) <= 2 or (tgt["hand"] as Array).size() >= 3) else "dmg"
	var choice := String(await eng.pick_option(tgt, opts, "%s 发动「裁决」：请选择一项" % eng.pname(p), ai_v))
	if choice == "give" and not (tgt["hand"] as Array).is_empty():
		var gc: Dictionary = await eng.pick_card(tgt, {"prompt": "「裁决」：选择 1 张手牌交给 %s" % eng.pname(p), "ai": Callable(self, "_worst_card")})
		if gc.is_empty() and not (tgt["hand"] as Array).is_empty():
			gc = (tgt["hand"] as Array)[0]
		if not gc.is_empty():
			(tgt["hand"] as Array).erase(gc)
			eng.gain_card(p, gc)
			eng.changed()
			eng.log_msg("「裁决」：%s 将 1 张手牌交给 %s。" % [eng.pname(tgt), eng.pname(p)])
			return
	eng.log_msg("「裁决」：%s 选择承受 1 点雷电伤害！" % eng.pname(tgt))
	await eng.damage(p, tgt, 1, "裁决", "雷")


# ---------- 黑泽玲央 ----------
func _jianxin_filter(eng, ctx, p) -> bool:
	var card: Dictionary = ctx.get("card", {})
	var tgt: Dictionary = ctx.get("target", {})
	if card.is_empty() or String(card.get("name", "")) != "突击" or tgt.is_empty() or not bool(tgt.get("alive", false)):
		return false
	var c_draw := (tgt["hand"] as Array).size() <= int(p["hp"])
	var c_dmg := int(tgt["hp"]) >= int(p["hp"]) and not bool(p.get("jianxin_dmg_turn", false))
	return c_draw or c_dmg


func _jianxin_content(eng, ctx, p) -> void:
	var tgt: Dictionary = ctx["target"]
	if (tgt["hand"] as Array).size() <= int(p["hp"]):
		eng.draw_cards(p, 1)
		eng.log_msg("「剑心」：%s 手牌数不大于 %s 的体力，%s 摸 1 张牌。" % [eng.pname(tgt), eng.pname(p), eng.pname(p)])
	if int(tgt["hp"]) >= int(p["hp"]) and not bool(p.get("jianxin_dmg_turn", false)):
		p["jianxin_dmg_turn"] = true
		ctx["dmg_bonus"] = int(ctx.get("dmg_bonus", 0)) + 1
		eng.log_msg("「剑心」：%s 体力不小于 %s，此「突击」伤害 +1！" % [eng.pname(tgt), eng.pname(p)])


func _canyue_filter(eng, p) -> bool:
	if bool(p.get("limited_used_canyue", false)):
		return false
	return int(p["hp"]) < int(p["max_hp"])


func _canyue_aiuse(eng, p) -> bool:
	if int(p["hp"]) <= 2:
		return true
	var sha_cnt := 0
	for c in p["hand"]:
		if String(c["name"]) == "突击":
			sha_cnt += 1
	return sha_cnt >= 2 and not eng.ai_pick_target(p, true).is_empty()


func _canyue_content(eng, p) -> void:
	p["limited_used_canyue"] = true
	p["canyue_turn"] = true
	p["used_attack"] = false
	eng.draw_cards(p, 2)
	eng.heal(p, 1, p)
	eng.log_msg("★限定技「奥义·残月」：%s 摸 2 张牌、回复 1 点体力，本回合使用「突击」无次数限制！" % eng.pname(p))


# ---------- 神乐坂真昼（转换技 · 昼夜卷 + 静读） ----------
func _zhouye_filter(eng, p) -> bool:
	var st := int(p.get("switch_zhouye", 0))
	if st == 0:
		return not (p["hand"] as Array).is_empty() and _others_exist_p(eng, p)
	return not eng.alive_players().is_empty()


func _zhouye_aiuse(eng, p) -> bool:
	var st := int(p.get("switch_zhouye", 0))
	if st == 1:
		return true
	for t in eng.players:
		if t != p and t["alive"] and eng.ai_is_enemy(p, t):
			if int(t["hp"]) <= 1 or (p["hand"] as Array).size() >= 2:
				return true
	return false


func _zhouye_content(eng, p) -> void:
	var st := int(p.get("switch_zhouye", 0))
	if st == 0:
		var cost: Dictionary = await eng.pick_card(p, {"prompt": "「昼夜卷·阳」：弃置 1 张手牌作为代价", "ai": Callable(self, "_worst_card")})
		if cost.is_empty():
			return
		var cands: Array = []
		for t in eng.players:
			if t != p and t["alive"]:
				cands.append(t)
		var tgt: Dictionary = await eng.pick_target(p, cands, "「昼夜卷·阳」：选择 1 名其他角色造成 1 点火焰伤害", Callable(self, "_caijue_target"))
		if tgt.is_empty():
			return
		eng.discard_from_hand(p, cost)
		p["switch_zhouye"] = 1
		eng.fx("switch_skill", {"seat": int(p["seat"]), "name": "昼夜卷", "state": "阴"})
		eng.observe_hostile(p, tgt)
		eng.log_msg("☯「昼夜卷·阳」：%s 弃置 %s，对 %s 造成 1 点火焰伤害（昼夜卷转为【阴】）。" % [eng.pname(p), eng.card_text(cost), eng.pname(tgt)])
		await eng.damage(p, tgt, 1, "昼夜卷", "火")
	else:
		var cands2: Array = eng.alive_players()
		var tgt2: Dictionary = await eng.pick_target(p, cands2, "「昼夜卷·阴」：选择 1 名角色摸 2 张牌并弃 1 张牌", Callable(self, "_yingyuan_target"))
		if tgt2.is_empty():
			return
		p["switch_zhouye"] = 0
		eng.fx("switch_skill", {"seat": int(p["seat"]), "name": "昼夜卷", "state": "阳"})
		eng.draw_cards(tgt2, 2)
		var dc: Dictionary = {}
		if eng.is_ai(tgt2):
			dc = eng.ai_pick_discard(tgt2)
		elif eng.ui.has("choose_discard"):
			dc = await (eng.ui["choose_discard"] as Callable).call(tgt2)
		if dc.is_empty() and not (tgt2["hand"] as Array).is_empty():
			dc = eng.ai_pick_discard(tgt2)
		if not dc.is_empty():
			eng.discard_from_hand(tgt2, dc)
		eng.log_msg("☯「昼夜卷·阴」：%s 令 %s 摸 2 张牌并弃置 1 张牌（昼夜卷转为【阳】）。" % [eng.pname(p), eng.pname(tgt2)])


func _jingdu_filter(eng, ctx, p) -> bool:
	return (p["hand"] as Array).size() <= int(p["hp"])


func _jingdu_content(eng, ctx, p) -> void:
	eng.draw_cards(p, 1)
	eng.log_msg("「静读」：%s 手牌数不大于体力值，摸 1 张牌。" % eng.pname(p))


# ---------- 久远寺绫（破的 + 觉醒技 · 心眼觉醒 + 衍生技 · 神射） ----------
func _podi_filter(eng, ctx, p) -> bool:
	if not String(ctx.get("cause", "")).begins_with("突击"):
		return false
	var tgt: Dictionary = ctx.get("target", {})
	if tgt.is_empty() or not bool(tgt.get("alive", false)):
		return false
	return not (tgt["hand"] as Array).is_empty()


func _podi_content(eng, ctx, p) -> void:
	var tgt: Dictionary = ctx["target"]
	if (tgt["hand"] as Array).is_empty():
		return
	var dc: Dictionary = eng.ai_pick_discard(tgt)
	if dc.is_empty():
		dc = (tgt["hand"] as Array)[0]
	eng.discard_from_hand(tgt, dc)
	eng.log_msg("「破的」：%s 突击命中，令 %s 弃置了 %s。" % [eng.pname(p), eng.pname(tgt), eng.card_text(dc)])


func _xinyan_filter(eng, ctx, p) -> bool:
	if bool(p.get("awakened_xinyan", false)):
		return false
	return int(p["hp"]) <= 2 or int(p.get("stat_damage", 0)) >= 2


func _xinyan_content(eng, ctx, p) -> void:
	p["awakened_xinyan"] = true
	p["max_hp"] = maxi(1, int(p["max_hp"]) - 1)
	if int(p["hp"]) > int(p["max_hp"]):
		p["hp"] = int(p["max_hp"])
	eng.heal(p, 1, p)
	eng.draw_cards(p, 2)
	eng.add_skill(p, "shenshe")
	eng.fx("awaken", {"seat": int(p["seat"]), "name": "心眼觉醒", "char": String(p["char_name"])})
	eng.log_msg("★觉醒技「心眼觉醒」：%s 减 1 点体力上限、回复 1 点体力并摸 2 张牌，习得技能「神射」！" % eng.pname(p))
	eng.changed()


func _shenshe_cands(eng, p) -> Array:
	var out: Array = []
	for t in eng.players:
		if t != p and t["alive"] and not bool(t.get("dream_guard", false)):
			out.append(t)
	return out


func _shenshe_filter(eng, p) -> bool:
	if (p["hand"] as Array).is_empty():
		return false
	return not _shenshe_cands(eng, p).is_empty()


func _shenshe_aiuse(eng, p) -> bool:
	for t in _shenshe_cands(eng, p):
		if eng.ai_is_enemy(p, t):
			return true
	return false


func _shenshe_content(eng, p) -> void:
	var c: Dictionary = await eng.pick_card(p, {"prompt": "「神射」：选择 1 张手牌当作无距离限制且不可闪避的「突击」", "ai": Callable(self, "_worst_card")})
	if c.is_empty():
		return
	var cands: Array = _shenshe_cands(eng, p)
	var tgt: Dictionary = await eng.pick_target(p, cands, "「神射」：选择目标（无视距离、不可闪避）", Callable(self, "_qinyin_target"))
	if tgt.is_empty():
		return
	eng.discard_from_hand(p, c)
	var vsha := {"name": "突击", "suit": String(c["suit"]), "point": int(c["point"]), "nature": "", "yb": [], "virtual": true, "src_cards": [c], "force_hit": true}
	eng.log_msg("「神射」：%s 将 %s 化作必中之矢射向 %s（无视距离、不可闪避）！" % [eng.pname(p), eng.card_text(c), eng.pname(tgt)])
	await eng.use_attack(p, tgt, vsha, false, true)


# ---------- 结城奈奈（催化 + 余震） ----------
func _cuihua_filter(eng, p) -> bool:
	return not eng.alive_players().is_empty()


func _cuihua_aiuse(eng, p) -> bool:
	return true


func _cuihua_target(eng, p, cands) -> Dictionary:
	for t in cands:
		if eng.ai_is_enemy(p, t) and not bool(t.get("chained", false)):
			return t
	for t in cands:
		if eng.ai_is_ally(p, t) and bool(t.get("chained", false)):
			return t
	return p if cands.has(p) else cands[0]


func _cuihua_content(eng, p) -> void:
	var cands: Array = eng.alive_players()
	var tgt: Dictionary = await eng.pick_target(p, cands, "「催化」：选择 1 名角色横置或重置锁链，然后你摸 1 张牌", Callable(self, "_cuihua_target"))
	if tgt.is_empty():
		return
	eng.toggle_chain(tgt)
	eng.fx("chain", {"seat": int(tgt["seat"]), "on": bool(tgt.get("chained", false))})
	eng.draw_cards(p, 1)
	eng.log_msg("「催化」：%s %s了 %s 的羁绊锁链，并摸 1 张牌。" % [eng.pname(p), "横置" if bool(tgt.get("chained", false)) else "重置", eng.pname(tgt)])


func _yuzhen_filter(eng, ctx, p) -> bool:
	var nat := String(ctx.get("nature", ""))
	if nat not in ["火", "雷", "冰"]:
		return false
	var used_n := int((p["round_marks"] as Dictionary).get("yuzhen_cnt", 0))
	return used_n < 2


func _yuzhen_content(eng, ctx, p) -> void:
	var used_n := int((p["round_marks"] as Dictionary).get("yuzhen_cnt", 0)) + 1
	(p["round_marks"] as Dictionary)["yuzhen_cnt"] = used_n
	eng.draw_cards(p, 1)
	eng.log_msg("「余震」：场上发生%s属性伤害，%s 引发连锁反应摸 1 张牌（本轮 %d/2）。" % [String(ctx.get("nature", "")), eng.pname(p), used_n])


# ---------- 早乙女凛（王手 + 妙算） ----------
func _wangshou_cands(eng, p) -> Array:
	var out: Array = []
	for t in eng.players:
		if t != p and t["alive"] and not (t["hand"] as Array).is_empty():
			out.append(t)
	return out


func _wangshou_filter(eng, p) -> bool:
	if (p["hand"] as Array).is_empty():
		return false
	return not _wangshou_cands(eng, p).is_empty()


func _wangshou_aiuse(eng, p) -> bool:
	for t in _wangshou_cands(eng, p):
		if eng.ai_is_enemy(p, t):
			return true
	return false


func _wangshou_content(eng, p) -> void:
	var cands: Array = _wangshou_cands(eng, p)
	if cands.is_empty():
		return
	var tgt: Dictionary = await eng.pick_target(p, cands, "「王手」：选择 1 名有手牌的角色进行【拼点】", Callable(self, "_caijue_target"))
	if tgt.is_empty():
		return
	eng.observe_hostile(p, tgt)
	var res: Dictionary = await eng.pindian(p, tgt, "王手")
	if res.is_empty():
		return
	if bool(res.get("win", false)):
		eng.draw_cards(p, 1)
		p["nodist_seat"] = int(tgt["seat"])
		p["drunk"] = true
		eng.changed()
		eng.log_msg("「王手」拼点获胜！%s 摸 1 张牌，本回合对 %s 无距离限制且下一张「突击」伤害 +1！" % [eng.pname(p), eng.pname(tgt)])
	else:
		var tc: Dictionary = res.get("tgt_card", {})
		if not tc.is_empty() and eng.discard_pile.has(tc):
			eng.discard_pile.erase(tc)
			eng.gain_card(p, tc)
			eng.changed()
			eng.log_msg("「王手」拼点未赢：%s 获得了 %s 的拼点牌 %s。" % [eng.pname(p), eng.pname(tgt), eng.card_text(tc)])


# ---------- 天城雪音（精算 + 凛霜） ----------
func _jingsuan_content(eng, p) -> void:
	var c: Dictionary = await eng.pick_card(p, {"prompt": "「精算」：弃置 1 张手牌并摸 2 张牌（黑色牌且已受伤则额外回复 1 点体力）", "ai": Callable(self, "_worst_card")})
	if c.is_empty():
		return
	var was_blk: bool = eng.is_black(c)
	eng.discard_from_hand(p, c)
	eng.draw_cards(p, 2)
	if was_blk and int(p["hp"]) < int(p["max_hp"]):
		eng.heal(p, 1, p)
		eng.log_msg("「精算」：%s 弃置黑色牌 %s，摸 2 张牌并回复 1 点体力。" % [eng.pname(p), eng.card_text(c)])
	else:
		eng.log_msg("「精算」：%s 弃置 %s，摸 2 张牌。" % [eng.pname(p), eng.card_text(c)])


func _linshuang_filter(eng, ctx, p) -> bool:
	var src: Dictionary = ctx.get("source", {})
	return not src.is_empty() and src != p and bool(src.get("alive", false))


func _linshuang_ai(eng, ctx, p) -> bool:
	var src: Dictionary = ctx.get("source", {})
	return not eng.ai_is_ally(p, src)


func _linshuang_content(eng, ctx, p) -> void:
	var src: Dictionary = ctx["source"]
	if (src["hand"] as Array).is_empty():
		eng.log_msg("「凛霜」：%s 没有手牌，受到 %s 造成的 1 点冰属性伤害！" % [eng.pname(src), eng.pname(p)])
		await eng.damage(p, src, 1, "凛霜", "冰")
		return
	var opts: Array = [
		{"label": "弃置 1 张手牌", "value": "drop"},
		{"label": "受到 1 点冰属性伤害", "value": "ice"},
	]
	var ai_v := "drop" if (int(src["hp"]) <= 2 or (src["hand"] as Array).size() >= 2) else "ice"
	var v := String(await eng.pick_option(src, opts, "%s 发动「凛霜」：请选择一项" % eng.pname(p), ai_v))
	if v == "drop" and not (src["hand"] as Array).is_empty():
		var dc: Dictionary = {}
		if eng.is_ai(src):
			dc = eng.ai_pick_discard(src)
		elif eng.ui.has("choose_discard"):
			dc = await (eng.ui["choose_discard"] as Callable).call(src)
		if dc.is_empty() and not (src["hand"] as Array).is_empty():
			dc = eng.ai_pick_discard(src)
		if not dc.is_empty():
			eng.discard_from_hand(src, dc)
			eng.log_msg("「凛霜」：%s 选择弃置了 %s。" % [eng.pname(src), eng.card_text(dc)])
			return
	eng.log_msg("「凛霜」：%s 选择承受 1 点冰属性伤害！" % eng.pname(src))
	await eng.damage(p, src, 1, "凛霜", "冰")


# ---------- 魔王挑战专属技（魔威 + 星蚀） ----------
func _mowei_content(eng, ctx, p) -> void:
	eng.draw_cards(p, 1)
	eng.log_msg("「魔威」：%s 准备阶段摸 1 张牌。" % eng.pname(p))


func _xingshi_filter(eng, ctx, p) -> bool:
	return int(p["hp"]) < int(p["max_hp"]) and _others_exist(eng, ctx, p)


func _xingshi_content(eng, ctx, p) -> void:
	var foes: Array = []
	for t in eng.players:
		if t != p and t["alive"] and eng.ai_is_enemy(p, t):
			foes.append(t)
	if foes.is_empty():
		return
	var tgt: Dictionary = _enemy_most_cards(eng, p, foes)
	if tgt.is_empty():
		tgt = foes[0]
	eng.log_msg("「星蚀」：魔王 %s 降下星蚀雷罚，攻击 %s！" % [eng.pname(p), eng.pname(tgt)])
	await eng.damage(p, tgt, 1, "星蚀", "雷")


# ---------- 圣护院莉莉娅（圣盾 + 援护） & 主公技（星樱号令） ----------
func _shengdun_filter(eng, ctx, p) -> bool:
	return int(p.get("shield", 0)) <= 0 and int(eng.round_no) <= 25


func _shengdun_content(eng, ctx, p) -> void:
	eng.gain_shield(p, 1)
	eng.log_msg("🛡「圣盾」：%s 凝聚圣纹护盾，获得 1 点「护甲」（当前护甲 %d）。" % [eng.pname(p), int(p.get("shield", 0))])


func _yuanhu_aiuse(eng, p) -> bool:
	if int(eng.round_no) >= 25:
		return false
	return (p["hand"] as Array).size() >= 2


func _yuanhu_content(eng, p) -> void:
	var c: Dictionary = await eng.pick_card(p, {"prompt": "「援护」：弃置 1 张手牌，令一名角色获得 1 点「护甲」（若其已受伤你摸 1 张牌）", "ai": Callable(self, "_worst_card")})
	if c.is_empty():
		return
	var cands: Array = eng.alive_players()
	var tgt: Dictionary = await eng.pick_target(p, cands, "「援护」：选择获得 1 点「护甲」的角色", Callable(self, "_yingyuan_target"))
	if tgt.is_empty():
		return
	eng.discard_from_hand(p, c)
	eng.gain_shield(tgt, 1)
	var drew_extra := false
	if int(tgt["hp"]) < int(tgt["max_hp"]):
		eng.draw_cards(p, 1)
		drew_extra = true
	eng.log_msg("🛡「援护」：%s 弃置 %s，令 %s 获得 1 点「护甲」%s。" % [eng.pname(p), eng.card_text(c), eng.pname(tgt), "，并因目标已受伤摸 1 张牌" if drew_extra else ""])


func _xingying_lord_filter(eng, ctx, p) -> bool:
	return int(eng.round_no) <= 1 and int(p.get("shield", 0)) <= 0


func _xingying_lord_content(eng, ctx, p) -> void:
	eng.gain_shield(p, 1)
	eng.log_msg("👑主公技「星樱号令」：%s 号令学园，获得 1 点「护甲」！" % eng.pname(p))


# ---------- 星野咲夜（时计 + 星帷） ----------
func _shiji_filter(eng, p) -> bool:
	return not (eng.deck as Array).is_empty() or not (eng.discard_pile as Array).is_empty()


func _shiji_aiuse(eng, p) -> bool:
	return int(eng.round_no) < 30


func _shiji_score(eng, p, c: Dictionary) -> float:
	var nm := String(c.get("name", ""))
	var sc := 1.0
	if nm == "补给" and int(p["hp"]) < int(p["max_hp"]):
		sc += 5.0
	elif nm in ["特饮", "灵感爆发", "突然检查", "悄悄借走", "看破", "洞烛先机"]:
		sc += 3.5
	elif nm == "突击":
		sc += 2.5 if not bool(p.get("used_attack", false)) else 1.2
	elif nm == "闪避":
		sc += 2.2
	if eng.is_black(c) and eng.has_skill(p, "xingwei"):
		sc += 0.6
	return sc


func _shiji_content(eng, p) -> void:
	var revealed: Array = []
	for _i in 2:
		eng.reshuffle_if_needed()
		if (eng.deck as Array).is_empty():
			break
		revealed.append((eng.deck as Array).pop_back())
	if revealed.is_empty():
		return
	var rev_txt: Array = []
	for rc in revealed:
		rev_txt.append(eng.card_text(rc))
	eng.log_msg("⌛「时计」：%s 亮出牌堆顶：%s。" % [eng.pname(p), "、".join(PackedStringArray(rev_txt))])
	var pick_idx := 0
	if revealed.size() >= 2:
		var c0: Dictionary = revealed[0]
		var c1: Dictionary = revealed[1]
		var ai_idx := 0 if _shiji_score(eng, p, c0) >= _shiji_score(eng, p, c1) else 1
		if eng.is_human(p):
			var opts: Array = [
				{"label": "收入手牌：" + eng.card_text(c0), "value": 0},
				{"label": "收入手牌：" + eng.card_text(c1), "value": 1},
			]
			var v: Variant = await eng.pick_option(p, opts, "「时计」：选择 1 张加入手牌（另一张弃置）", ai_idx)
			pick_idx = clampi(int(v), 0, 1)
		else:
			pick_idx = ai_idx
	var chosen: Dictionary = revealed[pick_idx]
	eng.gain_card(p, chosen)
	for i in revealed.size():
		if i != pick_idx:
			(eng.discard_pile as Array).append(revealed[i])
	if revealed.size() >= 2 and eng.is_red(revealed[0]) == eng.is_red(revealed[1]):
		eng.gain_shield(p, 1)
		eng.log_msg("⌛「时计」同色共鸣：%s 获得 1 点「护甲」（当前护甲 %d）！" % [eng.pname(p), int(p.get("shield", 0))])
	if (p["hand"] as Array).size() > int(p["hp"]):
		var dc: Dictionary = await eng.pick_card(p, {"prompt": "「时计」：手牌数大于体力值，须弃置 1 张手牌", "ai": Callable(self, "_worst_card")})
		if dc.is_empty() and not (p["hand"] as Array).is_empty():
			dc = eng.ai_pick_discard(p)
		if not dc.is_empty():
			eng.discard_from_hand(p, dc)
			eng.log_msg("「时计」：%s 弃置了 %s。" % [eng.pname(p), eng.card_text(dc)])
	eng.changed()


# ---------- 御影纱奈（敛羽 + 破空） ----------
func _lianyu_filter(eng, ctx, p) -> bool:
	return int(ctx.get("num", 0)) > 0 and eng.mark_count(p, "影羽") < 4


func _lianyu_content(eng, ctx, p) -> void:
	var add_n: int = mini(int(ctx.get("num", 1)), 4 - int(eng.mark_count(p, "影羽")))
	if add_n <= 0:
		return
	var nv: int = eng.add_mark(p, "影羽", add_n, 4)
	eng.log_msg("🪶「敛羽」：%s 受到伤害后凝聚 %d 枚「影羽」（当前 %d/4，手牌上限+%d）。" % [eng.pname(p), add_n, nv, nv])


func _pokong_filter(eng, p) -> bool:
	return eng.mark_count(p, "影羽") >= 1


func _pokong_aiuse(eng, p) -> bool:
	var cnt: int = eng.mark_count(p, "影羽")
	return cnt >= 2 or (cnt >= 1 and (int(p["hp"]) <= 2 or (p["hand"] as Array).size() <= 1))


func _pokong_content(eng, p) -> void:
	var cnt: int = eng.mark_count(p, "影羽")
	if cnt <= 0:
		return
	eng.add_mark(p, "影羽", -cnt, 4)
	eng.draw_cards(p, cnt)
	var bonus_txt := ""
	if cnt >= 2:
		p["pokong_atk_bonus"] = int(p.get("pokong_atk_bonus", 0)) + 1
		p["drunk"] = true
		p["used_attack"] = int(p.get("attack_count", 0)) >= eng.attack_limit(p)
		bonus_txt = "，并获得本回合突击次数上限 +1 且下一张突击伤害 +1"
	eng.log_msg("🪶「破空」：%s 消耗 %d 枚「影羽」摸 %d 张牌%s！" % [eng.pname(p), cnt, cnt, bonus_txt])
	eng.changed()


# ---------- 星川幽（命札 + 余谶） ----------
func _yuchen_filter(eng, ctx, p) -> bool:
	return (p["hand"] as Array).size() < int(p["max_hp"])


func _yuchen_content(eng, ctx, p) -> void:
	eng.draw_cards(p, 1)
	eng.log_msg("🔮「余谶」：%s 手牌少于体力上限，摸 1 张牌。" % eng.pname(p))
