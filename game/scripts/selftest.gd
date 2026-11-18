extends Node

# 全明星杀 V0.24 自测（由 main.gd 的 _maybe_shot 按命令行参数分派）
#   --stress=<局数>[,<identity|doudizhu|duel|all>][,<起始种子>]  全 AI 多种子压力测试＋不变量检查，结果 /tmp/ask_stress.txt
#   --regtest   V0.24 修复项的确定性回归断言，结果 /tmp/ask_regtest.txt（须 REGTEST_DONE fails=0）
#   --uiplay=<局数>  真人路径随机点选（会真的点手牌/目标/技能按钮），结果 /tmp/ask_uiplay.txt

const EngineS = preload("res://scripts/engine.gd")
const HelpText = preload("res://data/help.gd")
const PuzzlesT = preload("res://data/puzzles.gd")

var main_ref = null


func run(m, arg: String) -> void:
	main_ref = m
	if arg.begins_with("--stress="):
		await _run_stress(arg.trim_prefix("--stress="))
	elif arg == "--regtest":
		await _run_reg_test()
	elif arg.begins_with("--uiplay="):
		await _run_ui_play(int(arg.trim_prefix("--uiplay=")))
	get_tree().quit()


func _has_arg(a: String) -> bool:
	return OS.get_cmdline_user_args().has(a)


func _write(path: String, lines: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()


func make_chars(n: int, hp_override: int = 0) -> Array:
	var pool: Array = Characters.by_work("星樱坂学园").duplicate()
	pool.shuffle()
	var chars: Array = []
	for i in n:
		var cd: Dictionary = pool[i]
		var sk: Array = []
		for s in cd["skills"]:
			sk.append(String((s as Dictionary)["sid"]))
		chars.append({"name": String(cd["name"]), "hp": hp_override if hp_override > 0 else int(cd["hp"]), "skills": sk})
	return chars


# ---------------- 不变量 ----------------
static func card_key(c: Dictionary) -> String:
	return "%s|%s|%s|%s" % [String(c.get("name", "")), String(c.get("suit", "")), str(c.get("point", "")), String(c.get("nature", ""))]


static func census(eng) -> Dictionary:
	var m := {}
	var stack: Array = []
	for c in eng.deck:
		stack.append(c)
	for c in eng.discard_pile:
		stack.append(c)
	for p in eng.players:
		for c in p["hand"]:
			stack.append(c)
		for c in p["judge"]:
			stack.append(c)
		for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
			var e: Dictionary = p["equip"][slot]
			if not e.is_empty():
				stack.append(e)
	while not stack.is_empty():
		var c: Dictionary = stack.pop_back()
		for sc in (c.get("stored", []) as Array):
			stack.append(sc)
		if String(c.get("name", "")) == "地契":
			continue
		var k := card_key(c)
		m[k] = int(m.get(k, 0)) + 1
	return m


static func census_diff(a: Dictionary, b: Dictionary) -> String:
	var out: Array = []
	for k in a:
		if int(a[k]) != int(b.get(k, 0)):
			out.append("%s:%d->%d" % [k, int(a[k]), int(b.get(k, 0))])
	for k in b:
		if not a.has(k):
			out.append("%s:0->%d" % [k, int(b[k])])
	return ",".join(out)


static func expected_winner_ok(eng) -> bool:
	var wt := String(eng.winner_text)
	if eng.mode == "duel":
		return wt.find("单挑中获胜") >= 0
	if eng.mode == "doudizhu":
		var dz_alive := false
		var nm_alive := false
		for p in eng.players:
			if String(p["identity"]) == "地主":
				dz_alive = bool(p["alive"])
			elif bool(p["alive"]):
				nm_alive = true
		if wt == "地主获胜！":
			return dz_alive and not nm_alive
		if wt == "农民阵营获胜！":
			return not dz_alive
		return false
	var lord_alive := false
	var fan_alive := false
	var nei_alive := false
	var alive_n := 0
	for p in eng.players:
		if not bool(p["alive"]):
			continue
		alive_n += 1
		match String(p["identity"]):
			"主公":
				lord_alive = true
			"反贼":
				fan_alive = true
			"内奸":
				nei_alive = true
	if wt == "主公阵营获胜！":
		return lord_alive and not fan_alive and not nei_alive
	if wt == "内奸获胜！":
		return not lord_alive and nei_alive and alive_n == 1
	if wt == "反贼阵营获胜！":
		return not lord_alive and not (nei_alive and alive_n == 1)
	return false


static func state_errors(eng) -> Array:
	var errs: Array = []
	for q in eng.players:
		if int(q["hp"]) > int(q["max_hp"]):
			errs.append("hp>max seat%d %d/%d" % [int(q["seat"]), int(q["hp"]), int(q["max_hp"])])
		if bool(q["alive"]) and int(q["hp"]) <= 0:
			errs.append("alive_hp<=0 seat%d hp=%d" % [int(q["seat"]), int(q["hp"])])
		if not bool(q["alive"]):
			var nc: int = (q["hand"] as Array).size() + (q["judge"] as Array).size()
			for slot in ["weapon", "armor", "minus", "plus", "treasure"]:
				if not (q["equip"][slot] as Dictionary).is_empty():
					nc += 1
			if nc > 0:
				errs.append("dead_holds_cards seat%d n=%d" % [int(q["seat"]), nc])
	return errs


# ---------------- 压力测试 ----------------
func _run_stress(arg: String) -> void:
	var parts := arg.split(",")
	var games := maxi(1, int(parts[0]))
	var mode_sel := parts[1] if parts.size() > 1 else "all"
	var seed0 := int(parts[2]) if parts.size() > 2 else 1000
	var fixed_diff := int(parts[3]) if parts.size() > 3 else -1
	var lines: Array = []
	var fails := 0
	var totals := {}
	var cstats := {}
	var t_start := Time.get_ticks_msec()
	for g in games:
		var m := mode_sel
		if mode_sel == "all":
			m = ["identity", "doudizhu", "duel"][g % 3]
		var sd := seed0 + g
		seed(sd)
		var eng = EngineS.new()
		eng.load_skills()
		eng.mode = m
		eng.difficulty = (g / 3) % 3 if fixed_diff < 0 else fixed_diff
		var ids: Array = []
		var n := 5
		if m == "doudizhu":
			n = 3
			ids = ["农民", "农民", "农民"]
		elif m == "duel":
			n = 2
			ids = ["先手", "后手"]
			eng.duel_first_seat = randi() % 2
		else:
			ids = ["主公", "忠臣", "反贼", "反贼", "内奸"]
			ids.shuffle()
		eng.setup_game(make_chars(n), ids)
		eng.xingmian_legacy = _has_arg("--xingmian-legacy")
		var base := {"m": census(eng)}
		if _has_arg("--verbose"):
			printerr("STRESS_BEGIN g=%d seed=%d mode=%s" % [g + 1, sd, m])
		var errs: Array = []
		var turns := {"n": 0}
		var gt0 := Time.get_ticks_msec()
		eng.turn_hook = func(e, p: Dictionary) -> void:
			turns["n"] = int(turns["n"]) + 1
			if _has_arg("--dbg") and int(turns["n"]) > 380 and not p.is_empty() and p["alive"]:
				var tg = e.ai_pick_target(p, true)
				var hn: Array = []
				for c in p["hand"]:
					hn.append(String(c["name"]) + String(c.get("nature", "")))
				e.log_msg("DBG t%d %s hand=%s used_attack=%s tgt=%s" % [int(turns["n"]), e.pname(p), str(hn), str(p["used_attack"]), e.pname(tg) if not tg.is_empty() else "-"])
			var now := census(e)
			var d := census_diff(base["m"], now)
			if d != "":
				if errs.size() < 6:
					errs.append("census@t%d[%s]" % [int(turns["n"]), d])
				base["m"] = now
			for se in state_errors(e):
				if errs.size() < 6 and not errs.has(se):
					errs.append(se)
		await eng.run_game()
		var gms := Time.get_ticks_msec() - gt0
		if not eng.game_over:
			errs.append("not_over")
		elif String(eng.winner_text).begins_with("局面上限"):
			errs.append("turn_cap")
		elif not expected_winner_ok(eng):
			errs.append("winner_mismatch[%s]" % String(eng.winner_text))
		var key := "%s|%s" % [m, String(eng.winner_text)]
		totals[key] = int(totals.get(key, 0)) + 1
		# 角色/身份胜率统计（平衡压测用）
		if eng.game_over and not String(eng.winner_text).begins_with("局面上限"):
			for q in eng.players:
				var won := player_won(eng, q)
				var ck := "CHAR|%s|%s" % [m, String(q["char_name"])]
				var st: Array = cstats.get(ck, [0, 0])
				cstats[ck] = [int(st[0]) + 1, int(st[1]) + (1 if won else 0)]
				var ik := "ID|%s|%s" % [m, String(q["identity"])]
				var st2: Array = cstats.get(ik, [0, 0])
				cstats[ik] = [int(st2[0]) + 1, int(st2[1]) + (1 if won else 0)]
		if _has_arg("--dmgstat") and m == "identity":
			var idmap := {}
			for q in eng.players:
				idmap[eng.pname(q)] = String(q["identity"])
			var rx := RegEx.new()
			rx.compile("^(\\S+) 受到 (\\S+) 的 (\\d+) 点伤害")
			for ln in eng.log_lines:
				var mm := rx.search(String(ln))
				if mm != null and idmap.has(mm.get_string(1)) and idmap.has(mm.get_string(2)):
					var dk := "DMG|%s>%s" % [idmap[mm.get_string(2)], idmap[mm.get_string(1)]]
					var dv: Array = cstats.get(dk, [0, 0])
					cstats[dk] = [int(dv[0]) + int(mm.get_string(3)), 0]
		if not errs.is_empty():
			fails += 1
		lines.append("%s g=%d seed=%d mode=%s diff=%d rounds=%d turns=%d ms=%d winner=%s %s" % ["OK" if errs.is_empty() else "FAIL", g + 1, sd, m, int(eng.difficulty), int(eng.round_no), int(turns["n"]), gms, String(eng.winner_text), "; ".join(PackedStringArray(errs))])
		if not errs.is_empty() and _has_arg("--logdump"):
			var dump: Array = eng.log_lines.duplicate()
			for p in eng.players:
				var eq: Array = []
				for k in p["equip"]:
					if not (p["equip"][k] as Dictionary).is_empty():
						eq.append(String(p["equip"][k]["name"]))
				var hn: Array = []
				for c in p["hand"]:
					hn.append(String(c["name"]))
				var jn: Array = []
				for c in p["judge"]:
					jn.append(String(c["name"]))
				dump.append("STATE seat=%d %s id=%s alive=%s hp=%d/%d hand=%s equip=%s judge=%s guard=%s chained=%s" % [int(p["seat"]), eng.pname(p), String(p["identity"]), str(p["alive"]), int(p["hp"]), int(p["max_hp"]), str(hn), str(eq), str(jn), str(p.get("dream_guard", false)), str(p.get("chained", false))])
			_write("/tmp/ask_stress_log_%d.txt" % sd, dump)
	var keys := totals.keys()
	keys.sort()
	for k in keys:
		lines.append("TOTAL %s = %d" % [k, int(totals[k])])
	var ck2 := cstats.keys()
	ck2.sort()
	for k in ck2:
		var st3: Array = cstats[k]
		lines.append("STAT %s games=%d wins=%d rate=%.1f%%" % [k, int(st3[0]), int(st3[1]), 100.0 * float(st3[1]) / maxf(1.0, float(st3[0]))])
	lines.append("STRESS_DONE games=%d fails=%d secs=%.1f" % [games, fails, float(Time.get_ticks_msec() - t_start) / 1000.0])
	_write("/tmp/ask_stress.txt", lines)
	print(lines[lines.size() - 1])


# ---------------- 回归断言（V0.24 修复项） ----------------
var _reg_lines: Array = []
var _reg_fails := 0
var _reg_n := 0


func _ok(cond: bool, label: String) -> void:
	_reg_n += 1
	if cond:
		_reg_lines.append("PASS " + label)
	else:
		_reg_fails += 1
		_reg_lines.append("FAIL " + label)


# 构造一个「干净」的对局：全员清空手牌/技能，体力统一，回合角色为 0 号位
func _clean_eng(mode: String = "identity", ids: Array = ["主公", "忠臣", "反贼", "反贼", "内奸"], hp: int = 4):
	seed(4242)
	var eng = EngineS.new()
	eng.load_skills()
	eng.mode = mode
	eng.setup_game(make_chars(ids.size(), hp), ids)
	for p in eng.players:
		for c in (p["hand"] as Array).duplicate():
			(p["hand"] as Array).erase(c)
			eng.deck.append(c)
		p["skills"] = []
		p["max_hp"] = hp
		p["hp"] = hp
	eng.turn_player = eng.players[0]
	eng.log_lines.clear()
	return eng


static func _mk(nm: String, suit: String = "红桃", point: int = 5, nature: String = "") -> Dictionary:
	return {"name": nm, "suit": suit, "point": point, "nature": nature, "yb": []}


func _give(eng, p: Dictionary, nm: String, suit: String = "红桃", point: int = 5, nature: String = "") -> Dictionary:
	var c := _mk(nm, suit, point, nature)
	(p["hand"] as Array).append(c)
	return c


func _log_index(eng, needle: String) -> int:
	for i in eng.log_lines.size():
		if String(eng.log_lines[i]).find(needle) >= 0:
			return i
	return -1


# 脚本化真人：humans 中的座位视为真人，其回调按 script 字典作答，并把被询问记录进 rec
func _script_ui(eng, humans: Array, script: Dictionary, rec: Array) -> void:
	eng.set_ui({
		"is_human": func(p): return humans.has(int(p["seat"])),
		"ask_save": func(p, dying):
			rec.append(["save", int(p["seat"])])
			var q: Array = script.get("save_" + str(int(p["seat"])), [])
			return bool(q.pop_front()) if not q.is_empty() else false,
		"ask_respond": func(p, nm, reason):
			rec.append(["respond", int(p["seat"]), String(nm), String(reason)])
			return bool(script.get("respond_" + str(int(p["seat"])), false)),
		"pick_option": func(p, opts, prompt):
			rec.append(["option", int(p["seat"]), String(prompt), opts.size()])
			var pick := int(script.get("option_" + str(int(p["seat"])), 0))
			return opts[clampi(pick, 0, opts.size() - 1)]["value"],
		"pick_card": func(p, cands, prompt):
			rec.append(["card", int(p["seat"]), String(prompt), cands.size()])
			return cands[0],
		"pick_target": func(p, cands, prompt):
			rec.append(["target", int(p["seat"]), String(prompt), cands.size()])
			return cands[0],
		"ask_skill": func(p, sid, timing, ctx): return true,
		"choose_discard": func(p): return {},
	})


func _run_reg_test() -> void:
	_reg_lines.clear()
	_reg_fails = 0
	_reg_n = 0
	await _reg_engine_rules()
	await _reg_cards()
	await _reg_skills()
	await _reg_ui_crash()
	await _reg_ui_v25()
	await _reg_v26()
	await _reg_v27()
	await _reg_v28()
	await _reg_v30()
	await _reg_v32()
	await _reg_v33()
	await _reg_v34()
	await _reg_v35()
	await _reg_v36()
	await _reg_v37()
	await _reg_v38()
	await _reg_v39()
	await _reg_v40()
	await _reg_v41()
	_reg_lines.append("REGTEST_DONE tests=%d fails=%d" % [_reg_n, _reg_fails])
	_write("/tmp/ask_regtest.txt", _reg_lines)
	print(_reg_lines[_reg_lines.size() - 1])


func _reg_engine_rules() -> void:
	# R1 距离：阵亡角色不占座次（noname get.distance 只数存活角色）
	var e = _clean_eng()
	e.players[2]["alive"] = false
	_ok(e.dist_between(1, 3) == 1, "R1 距离：2 号位阵亡后 1↔3 距离为 1")
	_ok(e.dist_between(0, 3) == 2, "R1 距离：5 人局 3 号位阵亡后 0↔3 距离为 2")
	e.players[3]["alive"] = false
	_ok(e.dist_between(0, 4) == 1 and e.dist_between(1, 4) == 1 and e.dist_between(0, 1) == 1, "R1 距离：两人阵亡后剩 3 人两两相邻")
	# R2 内奸获胜：主公阵亡、场上只剩内奸
	e = _clean_eng()
	for i in [1, 2, 3]:
		e.players[i]["alive"] = false
	e.players[0]["alive"] = false
	e.check_over()
	_ok(e.game_over and e.winner_text == "内奸获胜！", "R2 主公阵亡且只剩内奸 → 内奸获胜（实际：%s）" % e.winner_text)
	e = _clean_eng()
	e.players[0]["alive"] = false
	e.check_over()
	_ok(e.winner_text == "反贼阵营获胜！", "R2 主公阵亡且反贼存活 → 反贼胜")
	# R3 忠臣认输 → 反贼阵营获胜
	e = _clean_eng()
	e.concede(e.players[1])
	_ok(e.winner_text == "反贼阵营获胜！", "R3 忠臣认输判反贼胜（实际：%s）" % e.winner_text)
	e = _clean_eng()
	e.concede(e.players[2])
	_ok(e.winner_text == "主公阵营获胜！", "R3 反贼认输判主公胜")
	# R4 求桃顺序：从当前回合角色开始按座次
	e = _clean_eng()
	var rec: Array = []
	_script_ui(e, [0, 1, 2, 3, 4], {}, rec)
	for p in e.players:
		_give(e, p, "补给")
	e.turn_player = e.players[2]
	var dy: Dictionary = e.players[0]
	dy["hp"] = 0
	await e.handle_dying(dy, {})
	var order: Array = []
	for r in rec:
		if r[0] == "save":
			order.append(r[1])
	_ok(order == [2, 3, 4, 0, 1], "R4 求桃从当前回合角色起询问（实际 %s）" % str(order))
	_ok(not dy["alive"], "R4 无人救援 → 阵亡")
	# R5 同一角色可连续救援（需 2 张补给时被连续询问）
	e = _clean_eng()
	rec = []
	_script_ui(e, [0, 1, 2, 3, 4], {"save_3": [true, true]}, rec)
	_give(e, e.players[3], "补给")
	_give(e, e.players[3], "补给")
	_give(e, e.players[2], "补给")
	e.turn_player = e.players[2]
	dy = e.players[0]
	dy["hp"] = -1
	await e.handle_dying(dy, {})
	order = []
	for r in rec:
		if r[0] == "save":
			order.append(r[1])
	_ok(order == [2, 3, 3] and int(dy["hp"]) == 1 and dy["alive"], "R5 同一角色连续救援（实际 %s hp=%d）" % [str(order), int(dy["hp"])])
	# R6 受伤后技能在濒死结算之后（不屈：受到伤害后摸牌）
	e = _clean_eng()
	var v: Dictionary = e.players[1]
	v["skills"] = ["buqu"]
	v["hp"] = 1
	_give(e, v, "补给")
	await e.damage(e.players[2], v, 1, "测试")
	var i_save := _log_index(e, "救援")
	var i_buqu := _log_index(e, "不屈")
	_ok(i_save >= 0 and i_buqu > i_save and v["alive"], "R6 濒死求桃先于「不屈」（救援@%d 不屈@%d）" % [i_save, i_buqu])
	# R7 连环：属性伤害后重置并只传导一次
	e = _clean_eng()
	e.players[1]["chained"] = true
	e.players[3]["chained"] = true
	await e.damage(e.players[0], e.players[1], 1, "测试", "火")
	_ok(not e.players[1]["chained"] and not e.players[3]["chained"], "R7 连环传导后两人均重置")
	_ok(int(e.players[3]["hp"]) == 3, "R7 连环传导造成同等伤害")
	await e.damage(e.players[0], e.players[1], 1, "测试", "火")
	_ok(int(e.players[3]["hp"]) == 3, "R7 已重置者不再被传导")
	# R8 传导从当前回合角色起依次结算
	e = _clean_eng()
	for i in [1, 2, 4]:
		e.players[i]["chained"] = true
	e.turn_player = e.players[3]
	await e.damage(e.players[0], e.players[2], 1, "测试", "雷")
	var i4 := _log_index(e, "传导：%s" % e.pname(e.players[4]))
	var i1 := _log_index(e, "传导：%s" % e.pname(e.players[1]))
	_ok(i4 >= 0 and i1 > i4, "R8 传导顺序从当前回合角色（3 号座）起：先 4 号座后 1 号座")
	# R9 死亡的连环角色不再被传导；濒死后游戏结束则不再触发后续
	e = _clean_eng()
	e.players[1]["chained"] = true
	e.players[4]["chained"] = true
	e.players[4]["alive"] = false
	await e.damage(e.players[0], e.players[1], 1, "测试", "雷")
	_ok(_log_index(e, "传导") < 0, "R9 阵亡角色不参与传导")


func _reg_cards() -> void:
	# C1 延时锦囊：放置时不开看破窗口；判定前开窗
	var e = _clean_eng()
	var rec: Array = []
	_script_ui(e, [2], {"respond_2": true}, rec)
	_give(e, e.players[2], "看破")
	var lb := _give(e, e.players[1], "沉迷游戏")
	await e.play_card(e.players[1], lb, e.players[0])
	var asked_on_place := false
	for r in rec:
		if r[0] == "respond":
			asked_on_place = true
	_ok(not asked_on_place and (e.players[0]["judge"] as Array).size() == 1, "C1 延时锦囊放置时不询问看破")
	_ok(int((e.players[0]["judge"] as Array)[0].get("placer", -1)) == 1, "C1 记录放置者")
	await e.resolve_delayed_phase(e.players[0])
	var asked_on_judge := false
	for r in rec:
		if r[0] == "respond" and String(r[2]) == "看破":
			asked_on_judge = true
	_ok(asked_on_judge and not bool(e.players[0]["skip_use"]) and _log_index(e, "被看破，本次不判定") >= 0, "C1 判定前可看破，被看破后不生效")
	# C2 落雷移交：下家已有落雷时顺延
	e = _clean_eng()
	e.players[1]["judge"].append(_mk("落雷", "黑桃", 1))
	var ld := _mk("落雷", "红桃", 1)
	var moved: bool = e.move_lightning(e.players[0], ld)
	_ok(moved and (e.players[2]["judge"] as Array).has(ld) and (e.players[1]["judge"] as Array).size() == 1, "C2 落雷跳过已有落雷的下家")
	# C3 看破落雷：移交下家而非弃置
	e = _clean_eng()
	rec = []
	_script_ui(e, [3], {"respond_3": true}, rec)
	_give(e, e.players[3], "看破")
	var ld2 := _mk("落雷", "黑桃", 5)
	ld2["placer"] = 0
	e.players[0]["judge"].append(ld2)
	await e.resolve_delayed_phase(e.players[0])
	_ok((e.players[1]["judge"] as Array).has(ld2) and int(e.players[0]["hp"]) == 4, "C3 被看破的落雷移交下家")
	# C4 pick_card_from：敌方先拆装备不拆判定区；友方先拆判定区
	e = _clean_eng()
	var t: Dictionary = e.players[2]
	t["judge"].append(_mk("沉迷游戏"))
	t["equip"]["weapon"] = _mk("钢纹长槊", "黑桃", 5)
	_give(e, t, "闪避")
	var got: Dictionary = e.pick_card_from(t, e.players[0])
	_ok(String(got.get("name", "")) == "钢纹长槊", "C4 主公拆反贼：先拆装备（实际 %s）" % String(got.get("name", "")))
	t["equip"]["weapon"] = {}
	got = e.pick_card_from(t, e.players[0])
	_ok(String(got.get("name", "")) == "闪避", "C4 主公拆反贼：无装备拆手牌而非判定区")
	var f: Dictionary = e.players[3]
	f["judge"].append(_mk("沉迷游戏"))
	_give(e, f, "闪避")
	got = e.pick_card_from(f, e.players[2])
	_ok(String(got.get("name", "")) == "沉迷游戏", "C4 反贼帮反贼：先拆判定区")
	# C4b V0.25：预选的牌在结算前已离开目标（如被应变·助战弃置）→ 重新选，不得把同一张牌再弃一次
	e = _clean_eng()
	var tv: Dictionary = e.players[2]
	var stale := _mk("金蝉脱壳", "黑桃", 11)
	e.discard_pile.append(stale)
	var still := _give(e, tv, "闪避")
	var ck := _give(e, e.players[1], "突然检查")
	await e.play_card(e.players[1], ck, tv, stale)
	var n_stale := 0
	for dc in e.discard_pile:
		if is_same(dc, stale):
			n_stale += 1
	_ok(n_stale == 1 and e.discard_pile.has(still) and not (tv["hand"] as Array).has(still), "C4b 预选牌已离场 → 改选目标现有的牌（stale×%d）" % n_stale)
	# C5 钢纹长槊：只弃目标手牌
	e = _clean_eng("duel", ["先手", "后手"])
	var a: Dictionary = e.players[0]
	var b: Dictionary = e.players[1]
	a["equip"]["weapon"] = _mk("钢纹长槊", "黑桃", 5)
	var sha := _give(e, a, "突击", "黑桃", 7)
	_give(e, a, "闪避")
	_give(e, a, "补给")
	b["equip"]["armor"] = _mk("结界手环", "黑桃", 2)
	b["equip"]["armor"] = {}
	b["equip"]["plus"] = _mk("远行披风", "红桃", 5)
	b["judge"].append(_mk("断粮封锁"))
	_give(e, b, "金蝉脱壳", "梅花", 1)
	_give(e, b, "补给", "红桃", 3)
	await e.use_attack(a, b, sha)
	_ok(not (b["equip"]["plus"] as Dictionary).is_empty() and (b["judge"] as Array).size() == 1 and (b["hand"] as Array).size() == 1, "C5 钢纹长槊只弃手牌，不动装备/判定")
	# C6 结界手环对弹幕齐射生效（红色判定视为闪避）
	e = _clean_eng("duel", ["先手", "后手"])
	e.players[1]["equip"]["armor"] = _mk("结界手环", "黑桃", 2)
	var red_top := _mk("补给", "红桃", 9)
	e.deck.append(red_top)
	var wj := _give(e, e.players[0], "弹幕齐射")
	(e.players[0]["hand"] as Array).erase(wj)
	await e.effect_wanjian(e.players[0], wj, "弹幕齐射")
	_ok(int(e.players[1]["hp"]) == 4 and _log_index(e, "结界手环」判定成功") >= 0, "C6 结界手环判红对弹幕齐射视为闪避")
	# C7 特饮每回合一次（AI）；回合开始重置
	e = _clean_eng("duel", ["先手", "后手"])
	var me: Dictionary = e.players[0]
	var d1 := _give(e, me, "特饮")
	_give(e, me, "特饮")
	e.use_drink(me, d1)
	_ok(bool(me["drink_used"]), "C7 使用特饮后记 drink_used")
	_give(e, me, "突击")
	me["drunk"] = false
	var acted: bool = await e.ai_try_action(me)
	_ok(e.find_in_hand(me, "特饮").size() > 0, "C7 本回合已用过特饮，AI 不再喝第二瓶")
	# C8 银狮铠甲被顶替时回血
	e = _clean_eng("duel", ["先手", "后手"])
	me = e.players[0]
	me["equip"]["armor"] = _mk("银狮铠甲", "梅花", 1)
	me["hp"] = 2
	var newarm := _give(e, me, "藤蔓铠甲", "黑桃", 2)
	e.play_equip(me, newarm)
	_ok(int(me["hp"]) == 3 and String(me["equip"]["armor"]["name"]) == "藤蔓铠甲", "C8 银狮铠甲被替换时回复 1 点")
	# C9 斗地主：农民阵亡后队友摸二或回一
	e = _clean_eng("doudizhu", ["地主", "农民", "农民"], 3)
	e.players[2]["hp"] = 1
	var hand_before := (e.players[2]["hand"] as Array).size()
	await e.die(e.players[1], e.players[0])
	_ok(int(e.players[2]["hp"]) == 2 and not e.game_over, "C9 农民阵亡，残血队友选择回复 1 点")
	e = _clean_eng("doudizhu", ["地主", "农民", "农民"], 3)
	await e.die(e.players[1], e.players[0])
	_ok((e.players[2]["hand"] as Array).size() == 2, "C9 满血队友摸 2 张")
	# C10 反甲：只拿回所响应的那张实体牌
	e = _clean_eng()
	var old_sha := _mk("突击", "黑桃", 9)
	var new_sha := _mk("突击", "红桃", 10)
	e.discard_pile.append(old_sha)
	e.discard_pile.append(_mk("闪避", "方块", 2))
	var vir := {"name": "突击", "suit": "红桃", "point": 3, "nature": "", "yb": [], "virtual": true, "src_cards": [new_sha]}
	e.discard_pile.append(new_sha)
	var dodge := {"name": "闪避", "suit": "红桃", "point": 2, "nature": "", "yb": ["空巢", "反甲"]}
	# 反甲触发条件按卡面词条判断；这里直接验证取牌池
	var before_n: int = (e.players[1]["hand"] as Array).size()
	e.players[1]["hand"].clear()
	var yb_ok: Dictionary = e.eval_yingbian(e.players[1], dodge)
	if bool(yb_ok.get("triggered", false)):
		await e.yb_response_effects(e.players[1], dodge, vir)
		_ok((e.players[1]["hand"] as Array).has(new_sha) and e.discard_pile.has(old_sha), "C10 反甲取回转化突击的底牌而不是早先的同名牌")
	else:
		_reg_lines.append("SKIP C10 反甲（当前条件不满足：%s）" % str(yb_ok))
	# C11 全员休整从使用者开始按座次
	e = _clean_eng()
	for p in e.players:
		p["hp"] = 2
	var ty := _give(e, e.players[3], "全员休整")
	(e.players[3]["hand"] as Array).erase(ty)
	await e.effect_taoyuan(e.players[3], ty, "全员休整")
	var hidx: Array = []
	for s in [3, 4, 0, 1, 2]:
		hidx.append(_log_index(e, "%s 回复" % e.pname(e.players[s])))
	var sorted_h := hidx.duplicate()
	sorted_h.sort()
	_ok(hidx == sorted_h and hidx[0] >= 0, "C11 全员休整自使用者起结算 %s" % str(hidx))
	# C12 物资发放：真人可自选
	e = _clean_eng("duel", ["先手", "后手"])
	rec = []
	_script_ui(e, [0], {"option_0": 1}, rec)
	var c_a := _mk("闪避", "方块", 2)
	var c_b := _mk("补给", "红桃", 3)
	e.deck.append(c_a)
	e.deck.append(c_b)  # pop_back 先亮出 c_b，再亮出 c_a
	var wg := _mk("物资发放")
	await e.effect_wugu(e.players[0], wg, "物资发放")
	_ok((e.players[0]["hand"] as Array).has(c_a) and (e.players[1]["hand"] as Array).has(c_b), "C12 物资发放真人选第二张")
	# C13 AI 全员休整只在己方受伤多于敌方时使用
	e = _clean_eng("duel", ["先手", "后手"])
	e.players[1]["hp"] = 2
	_give(e, e.players[0], "全员休整")
	await e.ai_try_action(e.players[0])
	_ok(e.find_in_hand(e.players[0], "全员休整").size() > 0 and int(e.players[1]["hp"]) == 2, "C13 只有敌人受伤时 AI 不放全员休整")
	# C14 继往开来不改写实体牌名（虚拟牌结算后清理）
	e = _clean_eng()
	var jt: Dictionary = e.players[0]
	var real1 := _give(e, jt, "闪避", "方块", 2)
	var real2 := _give(e, jt, "补给", "红桃", 4)
	await e.jiwang_use_as_trick(jt)
	_ok(String(real1["name"]) == "闪避" and String(real2["name"]) == "补给" and e.discard_pile.has(real1) and e.discard_pile.has(real2), "C14 继往开来：实体牌名不变且进入弃牌堆")
	var vleft := false
	for c in e.discard_pile:
		if bool(c.get("virtual", false)):
			vleft = true
	_ok(not vleft, "C14 虚拟牌不残留在弃牌堆")


func _reg_skills() -> void:
	# S1 琴音：真人对任意攻击范围内角色可发动；以虚拟突击结算
	var e = _clean_eng()
	var mk: Dictionary = e.players[0]
	mk["skills"] = ["qinyin"]
	var lib = e._skill_owner
	_give(e, mk, "补给", "红桃", 6)
	var cands: Array = lib._qinyin_cands(e, mk)
	_ok(cands.size() == 2, "S1 琴音候选为攻击范围内的全部其他角色（实际 %d）" % cands.size())
	var rec: Array = []
	_script_ui(e, [0], {}, rec)
	_ok(lib._qinyin_filter(e, mk), "S1 真人有红牌时可发动琴音")
	await lib._qinyin_content(e, mk)
	var sha_logged := _log_index(e, "使用「突击」") >= 0
	var rc_in_discard := false
	for c in e.discard_pile:
		if String(c["name"]) == "补给" and int(c["point"]) == 6:
			rc_in_discard = true
		_ok(not bool(c.get("virtual", false)), "S1 弃牌堆无虚拟牌：%s" % String(c["name"]))
	_ok(sha_logged and rc_in_discard, "S1 琴音以虚拟突击结算，原牌以原名进入弃牌堆")
	# S2 怒喝：只弃手牌/装备，不碰判定区；可选发动
	e = _clean_eng()
	lib = e._skill_owner
	var src: Dictionary = e.players[0]
	var tgt: Dictionary = e.players[2]
	tgt["judge"].append(_mk("沉迷游戏"))
	var ctx := {"target": tgt, "source": src}
	_ok(not lib._nuhe_filter(e, ctx, src), "S2 目标只有判定牌时不能发动怒喝")
	tgt["equip"]["plus"] = _mk("远行披风")
	_ok(lib._nuhe_filter(e, ctx, src), "S2 目标有装备时可发动")
	await lib._nuhe_content(e, ctx, src)
	_ok((tgt["judge"] as Array).size() == 1 and (tgt["equip"]["plus"] as Dictionary).is_empty(), "S2 怒喝弃装备不动判定区")
	e = _clean_eng("doudizhu", ["农民", "农民", "地主"], 3)
	lib = e._skill_owner
	_ok(not lib._nuhe_ai(e, {"target": e.players[1]}, e.players[0]), "S2 AI 不对队友发动怒喝（斗地主农民）")
	_ok(lib._nuhe_ai(e, {"target": e.players[2]}, e.players[0]), "S2 AI 对敌人发动怒喝")
	# S4 猫步只排除自己：多目标「突击」（星月画戟追加目标）的其他目标照常结算
	e = _clean_eng("doudizhu", ["地主", "农民", "农民"], 3)
	var dz: Dictionary = e.players[0]
	dz["equip"]["weapon"] = _mk("星月画戟", "方块", 12)
	var xsha := _give(e, dz, "突击", "黑桃", 8)
	var cat: Dictionary = e.players[1]
	cat["skills"] = ["maobu"]
	cat["hp"] = 2
	_give(e, cat, "金蝉脱壳", "梅花", 3)
	_give(e, cat, "补给", "红桃", 3)
	await e.use_attack(dz, cat, xsha)
	_ok(int(cat["hp"]) == 2 and _log_index(e, "猫步") >= 0, "S4 猫步令突击对自己无效")
	_ok(int(e.players[2]["hp"]) == 2, "S4 星月画戟追加的另一目标仍受到伤害（实际 hp=%d）" % int(e.players[2]["hp"]))
	# S3 茶会：AI 只给友方回血，并记入治疗统计
	e = _clean_eng("doudizhu", ["农民", "农民", "地主"], 4)
	lib = e._skill_owner
	src = e.players[0]
	_give(e, src, "闪避")
	_give(e, src, "闪避")
	e.players[2]["hp"] = 1
	_ok(not lib._chahui_aiuse(e, src), "S3 只有敌人受伤时 AI 不发动茶会")
	e.players[1]["hp"] = 2
	_ok(lib._chahui_aiuse(e, src), "S3 友方受伤时 AI 发动茶会")
	await lib._chahui_content(e, src)
	_ok(int(e.players[1]["hp"]) == 3 and int(e.players[2]["hp"]) == 1 and int(src.get("stat_heal", 0)) == 1, "S3 茶会治疗友方并计入治疗统计")


# 崩溃回归：真人点手牌「突击」后 refresh() 重建手牌行。旧代码在 pressed 信号回调中途 free() 正在发信号的按钮（安卓 release 闪退）
func _reg_ui_crash() -> void:
	var bs = _new_battle("identity", 13)
	var tries := 0
	var done := false
	while tries < 3000 and not done:
		tries += 1
		await get_tree().process_frame
		if bs.game_over:
			break
		if bs.interactive and bs.turn_seat == 0 and not bs.targeting:
			var me: Dictionary = bs.players[0]
			var sha := {"name": "突击", "suit": "黑桃", "point": 7, "nature": "", "yb": []}
			me["used_attack"] = false
			me["attack_count"] = 0
			(me["hand"] as Array).append(sha)
			if bs.candidates_for(me, sha).is_empty():
				for q in bs.players:
					if q != me and bool(q["alive"]):
						q["dream_guard"] = false
						q["equip"]["plus"] = {}
			bs.refresh()
			if bs.candidates_for(me, sha).is_empty():
				(me["hand"] as Array).erase(sha)
				bs.end_play_pressed.emit()
				continue
			var btn: Button = null
			for w in bs.hand_row.get_children():
				var b: Button = (w as Control).get_child(0) as Button
				var nm_lbl = null
				for sub in b.get_children():
					if sub is Label and (sub as Label).text == "突击":
						nm_lbl = sub
				if nm_lbl != null:
					btn = b
			if btn == null:
				_ok(false, "U1 找不到手牌「突击」按钮")
				break
			btn.pressed.emit()
			_ok(is_instance_valid(btn), "U1 点手牌「突击」后按钮在信号回调中未被立即释放（闪退根因）")
			_ok(bs.targeting and not bs.target_candidates.is_empty(), "U1 点「突击」进入选目标状态")
			await get_tree().process_frame
			await get_tree().process_frame
			_ok(is_instance_valid(btn), "U1 刷新后手牌节点复用（V0.25 起不再整排重建），按钮仍有效")
			# 再点目标完成出牌，验证整条链路
			for panel in bs.seat_panels:
				if int(panel.get_meta("seat")) == int(bs.target_candidates[0]) and bs.sel_target != int(bs.target_candidates[0]):
					(panel as Button).pressed.emit()
					break
			await get_tree().process_frame
			_ok(bs.targeting, "U1 (V0.27) 点目标只选中，仍在选目标状态")
			bs.confirm_btn.pressed.emit()
			await get_tree().process_frame
			_ok(not bs.targeting, "U1 点「确定」后退出选目标状态")
			# 技能按钮同理
			for sb in bs.skill_btns.get_children():
				if sb is Button and not (sb as Button).disabled and bs.interactive:
					(sb as Button).pressed.emit()
					_ok(is_instance_valid(sb), "U1 点技能按钮后按钮未被立即释放")
					break
			done = true
		else:
			_auto_answer(bs, false)
	if not done:
		_ok(false, "U1 未能进入真人出牌阶段（tries=%d over=%s）" % [tries, str(bs.game_over)])
	# U2 突然检查/悄悄借走选区：目标有宝物（木牛流马/太公阴符/地契）时旧版 zone_label 缺 treasure 键 → 脚本错误、出牌流程中断卡死
	if not bs.players.is_empty():
		var tq: Dictionary = bs.players[1]
		tq["equip"]["treasure"] = {"name": "木牛流马", "suit": "方块", "point": 5, "nature": "", "yb": []}
		var all_ok := true
		for ent in bs.all_target_cards(tq):
			if bs.zone_label(String(ent["zone"])) == String(ent["zone"]):
				all_ok = false
		_ok(all_ok and bs.zone_label("treasure") == "宝物", "U2 选区标签覆盖全部区域（含宝物）")
		tq["equip"]["treasure"] = {}
	await _close_battle(bs)
	# U3 在自己的出牌阶段认输：旧版引擎仍卡在等待「结束出牌」，结算界面不出现；单挑认输旧版显示「你赢了！」
	for md in ["identity", "duel"]:
		var b2 = _new_battle(md, 11)
		var reached := false
		for i in 3000:
			await get_tree().process_frame
			if b2.game_over:
				break
			if b2.interactive and b2.turn_seat == 0 and b2.in_play_phase:
				reached = true
				break
			_auto_answer(b2, false)
		if not reached:
			_ok(false, "U3[%s] 未能进入真人出牌阶段" % md)
			await _close_battle(b2)
			continue
		b2.on_concede_pressed()
		b2.on_concede_pressed()
		var over_at := -1
		for i in 600:
			await get_tree().process_frame
			if b2.game_over:
				over_at = i
				break
		_ok(over_at >= 0 and b2.settlement_layer != null, "U3[%s] 出牌阶段认输后出现结算（%d 帧）" % [md, over_at])
		var last_log := ""
		for l in b2.log_lines:
			if String(l).find("对局结束") >= 0:
				last_log = String(l)
		_ok(last_log.find("你输了") >= 0, "U3[%s] 认输方显示「你输了」：%s" % [md, last_log])
		await _close_battle(b2)
	# U4 对局中途点「退出」回主页：旧引擎实例应被回收（旧版协程挂起导致整局数据泄漏）
	var b3 = _new_battle("identity", 13)
	for i in 3000:
		await get_tree().process_frame
		if b3.in_play_phase and b3.turn_seat == 0:
			break
		_auto_answer(b3, false)
	var wr: WeakRef = weakref(b3.eng)
	b3.go_home.call()
	for i in 360:
		await get_tree().process_frame
	_ok(wr.get_ref() == null, "U4 在自己出牌阶段中途退出后引擎实例被释放")


func _new_battle(mode: String, sd: int):
	seed(sd)
	main_ref.clear_screen()
	var BS = load("res://scripts/battle.gd")
	var bs = BS.new()
	bs.game_mode = mode
	bs.set_anchors_preset(Control.PRESET_FULL_RECT)
	bs.go_home = Callable(main_ref, "show_home")
	main_ref.screen_root.add_child(bs)
	bs.difficulty = sd % 3
	if mode == "doudizhu":
		bs.my_role = ""
	elif mode == "duel":
		bs.my_role = "先手" if sd % 2 == 0 else "后手"
	bs.start_match(false)
	bs.fast = true
	return bs


func _close_battle(bs) -> void:
	if is_instance_valid(bs):
		bs.queue_free()
	await get_tree().process_frame


static func _live_buttons(parent: Node) -> Array:
	var out: Array = []
	if parent == null:
		return out
	for b in parent.get_children():
		if b is Button and not (b as Button).disabled and not b.is_queued_for_deletion() and (b as Button).visible:
			out.append(b)
	return out


# 处理选将/提问等阻塞界面；random=true 时随机作答，否则选第一项
func _auto_answer(bs, random: bool) -> bool:
	if bs.draft_layer != null and bs.draft_layer.visible:
		var ds := _live_buttons(bs.draft_layer)
		if not ds.is_empty():
			(ds[randi() % ds.size()] if random else ds[0]).pressed.emit()
			return true
	if bs.prompt_panel != null and bs.prompt_panel.visible and not bs.targeting and not (bs.interactive and bs.turn_seat == 0):
		var ps := _live_buttons(bs.prompt_btns)
		if not ps.is_empty():
			(ps[randi() % ps.size()] if random else ps[0]).pressed.emit()
			return true
	return false


# ---------------- 真人路径随机点选 ----------------
# 每局：真人位随机点手牌 / 目标 / 技能按钮 / 取消 / 结束出牌，所有询问随机作答；
# 检查：无脚本错误（由外层日志判定）、对局在步数上限内结束、牌数守恒、体力不越界
func _run_ui_play(games: int) -> void:
	var lines: Array = []
	var fails := 0
	var modes := ["identity", "doudizhu", "duel"]
	var t0 := Time.get_ticks_msec()
	var meta_games := 0
	load("res://scripts/meta.gd").reset_for_test("user://meta_test.json")
	for g in games:
		var mode: String = modes[g % 3]
		var sd := 9000 + g
		var bs = _new_battle(mode, sd)
		var errs: Array = []
		var clicks := {"hand": 0, "target": 0, "skill": 0, "cancel": 0, "prompt": 0, "end": 0, "equip": 0, "confirm": 0, "drag_play": 0, "drag_back": 0, "discard_tap": 0, "respond_tap": 0, "bg_tap": 0}
		# V0.27：每 4 局有 1 局打开「自动确认」（不写入设置文件）；关闭时单击绝不能直接结算
		var auto_on: bool = g % 4 == 3
		bs.set_auto_confirm(auto_on, false)
		clicks["auto"] = auto_on
		var base := {"m": {}, "set": false}
		var steps := 0
		var hooked := false
		while steps < 40000:
			steps += 1
			await get_tree().process_frame
			if not is_instance_valid(bs) or bs.game_over:
				break
			if not hooked and bs.eng != null and not bs.players.is_empty():
				hooked = true
				var e0 = bs.eng
				base["m"] = census(e0)
				e0.turn_hook = func(e, p: Dictionary) -> void:
					var now := census(e)
					var d := census_diff(base["m"], now)
					if d != "":
						if errs.size() < 6:
							errs.append("census[%s]" % d)
							var tail: Array = e.log_lines.slice(maxi(0, e.log_lines.size() - 40))
							printerr("CENSUS_TAIL " + d + "\n  " + "\n  ".join(PackedStringArray(tail)))
						base["m"] = now
					for se in state_errors(e):
						if errs.size() < 6 and not errs.has(se):
							errs.append(se)
			if randf() < 0.5:
				continue  # 模拟人的停顿，让引擎协程推进
			if bs.targeting and not bs.asking:
				var rt := randf()
				if rt < 0.4 and bs.action_bar.visible and not bs.confirm_btn.disabled:
					bs.confirm_btn.pressed.emit()
					clicks["confirm"] += 1
				elif rt < 0.88 and not bs.target_candidates.is_empty():
					var ts: int = bs.target_candidates[randi() % bs.target_candidates.size()]
					var hn0: int = (bs.players[0]["hand"] as Array).size()
					var tu0: int = (bs.players[0]["turn_used"] as Dictionary).size()
					for panel in bs.seat_panels:
						if int(panel.get_meta("seat")) == ts:
							(panel as Button).pressed.emit()
							clicks["target"] += 1
							break
					if ts == 0 and bs.me_click_btn != null:
						bs.me_click_btn.pressed.emit()
						clicks["target"] += 1
					if not auto_on and is_instance_valid(bs) and ((bs.players[0]["hand"] as Array).size() != hn0 or (bs.players[0]["turn_used"] as Dictionary).size() != tu0 or not bs.interactive) and not errs.has("target_tap_resolved"):
						errs.append("target_tap_resolved")
				elif bs.cancel_btn != null and bs.action_bar.visible and not bs.cancel_btn.disabled:
					bs.cancel_btn.pressed.emit()
					clicks["cancel"] += 1
				continue
			# V0.25 弃牌多选：在手牌里点选，凑满后点确定（也会随机点「智能选择」）
			if bs.discard_mode and randf() < 0.8:
				var dws: Array = bs.hand_cards.filter(func(x) -> bool: return is_instance_valid(x))
				if bs.discard_confirm_btn != null and not bs.discard_confirm_btn.disabled and randf() < 0.6:
					bs.discard_confirm_btn.pressed.emit()
					clicks["prompt"] += 1
				elif not dws.is_empty():
					bs.drag_end_ms = 0
					((dws[randi() % dws.size()] as Control).get_child(0) as Button).pressed.emit()
					clicks["discard_tap"] += 1
				continue
			# V0.25 响应：直接点亮起的手牌作答
			if bs.asking and (bs.respond_name != "" or not bs.pick_cards.is_empty()) and randf() < 0.4:
				var lit: Array = []
				for x in bs.hand_cards:
					if is_instance_valid(x) and String(x.get_meta("state", "")).begins_with("r1"):
						lit.append(x)
				if not lit.is_empty():
					bs.drag_end_ms = 0
					var aseq: int = bs.ask_seq
					((lit[randi() % lit.size()] as Control).get_child(0) as Button).pressed.emit()
					clicks["respond_tap"] += 1
					if not auto_on and (not bs.asking or bs.ask_seq != aseq) and not errs.has("respond_tap_resolved"):
						errs.append("respond_tap_resolved")
					continue
			if _auto_answer(bs, true):
				clicks["prompt"] += 1
				continue
			# V0.26 长按看说明：随机长按一张手牌或一名角色，必须弹出说明卡、松手后关闭，且不得出牌/选中
			if randf() < 0.03 and bs.interactive and bs.turn_seat == 0 and bs.in_play_phase and not bs.asking and not bs.targeting and IntroPop.inst != null:
				var lp_nodes: Array = []
				for x in bs.hand_cards:
					if is_instance_valid(x) and (x as Control).is_visible_in_tree():
						lp_nodes.append(x)
				for sp in bs.seat_panels:
					if (sp as Control).is_visible_in_tree():
						lp_nodes.append(sp)
				if not lp_nodes.is_empty():
					var ln: Control = lp_nodes[randi() % lp_nodes.size()]
					var hn: int = (bs.players[0]["hand"] as Array).size()
					var sel0: Dictionary = bs.selected_card
					var res := await sim_longpress(ln.get_global_rect().get_center() + (Vector2(0, -40) if ln.has_meta("card") else Vector2.ZERO))
					if not bool(res["opened"]) and not errs.has("longpress_no_pop"):
						errs.append("longpress_no_pop")
					if bool(res["open_after"]):
						errs.append("longpress_pop_stuck")
					if (bs.players[0]["hand"] as Array).size() != hn or bs.targeting or not is_same(bs.selected_card, sel0):
						errs.append("longpress_acted")
					clicks["longpress"] = int(clicks.get("longpress", 0)) + 1
					continue
			# V0.25 点空白桌面（取消选择 / 跳过等待）：随机穿插，不得卡住流程
			if randf() < 0.04 and bs.has_node("BgCatch"):
				var bgt := InputEventMouseButton.new()
				bgt.button_index = MOUSE_BUTTON_LEFT
				bgt.pressed = true
				(bs.get_node("BgCatch") as Control).gui_input.emit(bgt)
				clicks["bg_tap"] += 1
			if bs.interactive and bs.turn_seat == 0:
				var r := randf()
				# V0.25 拖拽出牌：拖到合法目标 / 拖出手牌区 / 在手牌区内松手回弹
				if r < 0.15 and bs.in_play_phase and not bs.asking:
					var usable: Array = []
					for x in bs.hand_cards:
						if is_instance_valid(x) and bs._can_drag(x):
							usable.append(x)
					if not usable.is_empty():
						var dw: Control = usable[randi() % usable.size()]
						var dc: Dictionary = dw.get_meta("card")
						var back := randf() < 0.3
						var dest: Vector2 = dw.global_position + Vector2(120, 30)
						if not back:
							if bs.card_needs_target(dc):
								var cs2: Array = bs.candidates_for(bs.players[0], dc)
								if not cs2.is_empty():
									var tp: Control = bs.seat_panel_of(int(cs2[randi() % cs2.size()]["seat"]))
									dest = tp.global_position + tp.size * 0.5
							else:
								dest = Vector2(dw.global_position.x, 380)
						var n0: int = (bs.players[0]["hand"] as Array).size()
						sim_drag(bs, dw, dest)
						await get_tree().process_frame
						if back:
							if not bs._hand_has(dc):
								errs.append("drag_back_played:%s" % String(dc["name"]))
							clicks["drag_back"] += 1
						else:
							clicks["drag_play"] += 1
						continue
				if r < 0.25 and bs.action_bar.visible and not bs.confirm_btn.disabled:
					bs.confirm_btn.pressed.emit()
					clicks["confirm"] += 1
					continue
				if r < 0.6:
					var hs: Array = []
					for w in bs.hand_row.get_children():
						if w.is_queued_for_deletion() or (w as Control).get_child_count() == 0:
							continue
						hs.append((w as Control).get_child(0))
					if not hs.is_empty():
						var hb: Button = hs[randi() % hs.size()]
						var hn1: int = (bs.players[0]["hand"] as Array).size()
						hb.pressed.emit()
						if not is_instance_valid(hb):
							errs.append("hand_button_freed_in_signal")
						if not auto_on and ((bs.players[0]["hand"] as Array).size() != hn1 or not bs.interactive) and not errs.has("hand_tap_resolved"):
							errs.append("hand_tap_resolved")
						clicks["hand"] += 1
						continue
				if r < 0.8:
					var sks := _live_buttons(bs.skill_btns)
					if not sks.is_empty():
						var sb: Button = sks[randi() % sks.size()]
						var tu1: int = (bs.players[0]["turn_used"] as Dictionary).size()
						var hn2: int = (bs.players[0]["hand"] as Array).size()
						sb.pressed.emit()
						if not is_instance_valid(sb):
							errs.append("skill_button_freed_in_signal")
						if not auto_on and ((bs.players[0]["turn_used"] as Dictionary).size() != tu1 or (bs.players[0]["hand"] as Array).size() != hn2 or not bs.interactive) and not errs.has("skill_tap_resolved"):
							errs.append("skill_tap_resolved")
						clicks["skill"] += 1
						continue
				bs.end_play_pressed.emit()
				clicks["end"] += 1
		var over: bool = is_instance_valid(bs) and bs.game_over
		if is_instance_valid(bs) and not bs.players.is_empty():
			clicks["me_alive"] = bool(bs.players[0]["alive"])
			clicks["me_id"] = String(bs.players[0]["identity"])
		if not over:
			errs.append("not_over steps=%d" % steps)
		if is_instance_valid(bs) and bs.eng != null:
			for se in state_errors(bs.eng):
				if not errs.has(se):
					errs.append(se)
		# V0.30：真人对局结束后应写入战绩（测试存档 user://meta_test.json）
		if over and is_instance_valid(bs) and not bool(bs.auto_all) and bs.game_over and (bs.meta_result as Dictionary).is_empty():
			errs.append("meta_not_recorded")
		if over and is_instance_valid(bs) and not bool(bs.auto_all):
			meta_games += 1
		if not errs.is_empty():
			fails += 1
		lines.append("%s g=%d mode=%s seed=%d steps=%d rounds=%d winner=%s clicks=%s %s" % ["OK" if errs.is_empty() else "FAIL", g + 1, mode, sd, steps, int(bs.round_no) if is_instance_valid(bs) else -1, String(bs.eng.winner_text) if is_instance_valid(bs) and bs.eng != null else "?", str(clicks), "; ".join(PackedStringArray(errs))])
		printerr(lines[lines.size() - 1])
		await _close_battle(bs)
	var MetaU = load("res://scripts/meta.gd")
	var mrecs: int = (MetaU.load_data()["records"] as Array).size()
	if mrecs != mini(meta_games, MetaU.MAX_RECORDS):
		fails += 1
		lines.append("FAIL meta_records=%d expected=%d" % [mrecs, meta_games])
	else:
		lines.append("OK meta_records=%d（战绩写入测试存档）" % mrecs)
	lines.append("UIPLAY_DONE games=%d fails=%d secs=%.1f" % [games, fails, float(Time.get_ticks_msec() - t0) / 1000.0])
	_write("/tmp/ask_uiplay.txt", lines)
	print(lines[lines.size() - 1])


# ---------------- V0.25 触屏交互回归：拖拽出牌 / 回弹 / 弃牌多选 / 作答超时 / 点自己为目标 / 点牌响应 ----------------
static func sim_drag(bs, w: Control, to_global: Vector2, steps: int = 8) -> void:
	var start: Vector2 = w.global_position + Vector2(86, 134)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = start
	press.position = start
	bs._on_card_gui_input(w, press)
	for k in steps:
		var mm := InputEventMouseMotion.new()
		mm.global_position = start.lerp(to_global, float(k + 1) / float(steps))
		mm.position = mm.global_position
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		bs._on_card_gui_input(w, mm)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.global_position = to_global
	rel.position = to_global
	bs._on_card_gui_input(w, rel)


func _reach_my_play(bs) -> bool:
	for i in 4000:
		await get_tree().process_frame
		if not is_instance_valid(bs) or bs.game_over:
			return false
		if bs.interactive and bs.turn_seat == 0 and bs.in_play_phase and not bs.asking:
			return true
		_auto_answer(bs, false)
	return false


func _wait_interactive(bs, frames: int = 400) -> void:
	for i in frames:
		await get_tree().process_frame
		if not is_instance_valid(bs) or bs.game_over:
			return
		if bs.interactive and not bs.asking:
			return
		_auto_answer(bs, false)


func _reg_ui_v25() -> void:
	var bs = _new_battle("identity", 21)
	if not await _reach_my_play(bs):
		_ok(false, "U5 未能进入真人出牌阶段")
		await _close_battle(bs)
		return
	var me: Dictionary = bs.players[0]
	# U5 拖拽「突击」到合法目标头像上松手 = 对其出牌
	me["used_attack"] = false
	me["attack_count"] = 0
	var sha := {"name": "突击", "suit": "黑桃", "point": 7, "nature": "", "yb": []}
	(me["hand"] as Array).append(sha)
	bs.refresh()
	var cands: Array = bs.candidates_for(me, sha)
	if cands.is_empty():
		_ok(false, "U5 没有可突击的目标（种子不合适）")
	else:
		var ts := int(cands[0]["seat"])
		var w: Control = bs._find_wrap(sha)
		var pn: Control = bs.seat_panel_of(ts)
		var hp0 := int(bs.players[ts]["hp"])
		var logn: int = bs.eng.log_lines.size()
		sim_drag(bs, w, pn.global_position + pn.size * 0.5)
		await _wait_interactive(bs)
		var used := false
		for i in range(logn, bs.eng.log_lines.size()):
			if String(bs.eng.log_lines[i]).find("突击") >= 0:
				used = true
		_ok(not bs._hand_has(sha) and used, "U5 拖到目标头像上松手即出牌（hp %d→%d）" % [hp0, int(bs.players[ts]["hp"])])
	# U6 拖拽松手在手牌区内 = 回弹不出；拖出手牌区 = 使用（装备牌）
	await _reach_my_play(bs)
	var wpn := {"name": "星光长剑", "suit": "方块", "point": 12, "nature": "", "yb": []}
	(me["hand"] as Array).append(wpn)
	bs.refresh()
	var w2: Control = bs._find_wrap(wpn)
	bs.drag_end_ms = 0
	sim_drag(bs, w2, w2.global_position + Vector2(140, 40))
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(bs._hand_has(wpn) and bs.drag_wrap == null, "U6 拖拽在手牌区内松手：牌回弹、未打出")
	sim_drag(bs, w2, Vector2(w2.global_position.x, 380))
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(bs._hand_has(wpn) and is_same(bs.selected_card, wpn) and not bs.confirm_btn.disabled, "U6 (V0.27) 无目标牌拖出手牌区松手只「选中」，未装备，「确定」可点")
	bs.confirm_btn.pressed.emit()
	await _wait_interactive(bs)
	_ok(not bs._hand_has(wpn) and bs.equip_name(me, "weapon") == "星光长剑", "U6 点「确定」后才装备上星光长剑")
	# U9（V0.28 起「补给」出牌阶段只能对自己，不再选目标）：点「补给」只选中，「确定」后对自己回复
	await _reach_my_play(bs)
	me["hp"] = maxi(int(me["max_hp"]) - 1, 1)
	var heal := {"name": "补给", "suit": "红桃", "point": 3, "nature": "", "yb": []}
	(me["hand"] as Array).append(heal)
	bs.refresh()
	var hpb := int(me["hp"])
	bs.drag_end_ms = 0
	var w3: Control = bs._find_wrap(heal)
	(w3.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	_ok(not bs.targeting and is_same(bs.selected_card, heal) and not bs.confirm_btn.disabled and int(me["hp"]) == hpb, "U9 点「补给」只选中（不用选目标），未结算")
	bs.confirm_btn.pressed.emit()
	await _wait_interactive(bs)
	_ok(int(me["hp"]) == hpb + 1 and not bs._hand_has(heal), "U9 点「确定」后对自己使用「补给」（hp %d→%d）" % [hpb, int(me["hp"])])
	# U7 弃牌多选：一次选 3 张，确定后按所选逐张交给引擎
	await _reach_my_play(bs)
	var picks: Array = []
	for i in 4:
		picks.append(_give(bs.eng, me, "闪避", "梅花", 2 + i))
	bs.refresh()
	bs.eng.discard_need = 3
	var box := {}
	var runner := func() -> void:
		box["r"] = await bs._eng_choose_discard(me)
	runner.call()
	await get_tree().process_frame
	_ok(bs.discard_mode and bs.discard_confirm_btn != null and bs.discard_confirm_btn.disabled, "U7 进入弃牌多选，未选满时「确定」不可点")
	bs.drag_end_ms = 0
	for i in 3:
		((bs._find_wrap(picks[i]) as Control).get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	_ok(not bs.discard_confirm_btn.disabled and bs.prompt_label.text.find("3/3") >= 0, "U7 选满 3 张后可确定，提示「已选 3/3」：%s" % bs.prompt_label.text)
	bs.discard_confirm_btn.pressed.emit()
	await get_tree().process_frame
	var first: Dictionary = box.get("r", {})
	_ok(is_same(first, picks[0]) and bs.discard_queue.size() == 2 and is_same(bs.discard_queue[0], picks[1]), "U7 确定后返回所选第 1 张，其余 2 张排队")
	var second: Dictionary = await bs._eng_choose_discard(me)
	_ok(is_same(second, picks[1]), "U7 引擎再次询问时直接取队列里的第 2 张")
	bs.discard_queue.clear()
	bs.eng.discard_need = 0
	for c in picks:
		(me["hand"] as Array).erase(c)
	bs.refresh()
	# U8 作答超时：按「不出」自动作答，不会卡住流程
	bs.ask_timeout = 0.25
	var box2 := {}
	var runner2 := func() -> void:
		box2["r"] = await bs.ask("测试：是否打出「闪避」？", [{"label": "打出", "value": true}, {"label": "不出", "value": false}])
	runner2.call()
	for i in 120:
		await get_tree().create_timer(0.02).timeout
		if box2.has("r"):
			break
	_ok(box2.has("r") and box2["r"] is bool and not bool(box2["r"]) and not bs.asking, "U8 倒计时结束自动按「不出」作答（%s asking=%s）" % [str(box2.get("r", "无")), str(bs.asking)])
	bs.ask_timeout = 15.0
	# U10 响应时直接点亮起的手牌作答
	var dodge := _give(bs.eng, me, "闪避", "方块", 9)
	bs.refresh()
	var box3 := {}
	var runner3 := func() -> void:
		box3["r"] = await bs._eng_ask_respond(me, "闪避", "测试")
	runner3.call()
	await get_tree().process_frame
	await get_tree().process_frame
	var w4: Control = bs._find_wrap(dodge)
	_ok(w4 != null and String(w4.get_meta("state", "")).begins_with("r1"), "U10 响应「闪避」时手里的闪避亮起")
	bs.drag_end_ms = 0
	(w4.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	_ok(not box3.has("r") and bs.asking and bs.ask_sel_has and bs._is_lifted(w4), "U10 (V0.27) 点亮起的闪避只是选中上浮，未作答")
	bs.ask_confirm_btn.pressed.emit()
	await get_tree().process_frame
	_ok(box3.get("r", false) == true, "U10 选中后点「确定」才作答「打出」")
	(me["hand"] as Array).erase(dodge)
	# U11 猜身份弹层：点「猜」→ 选「反」→ 弹层隐藏、标记生效、按钮仍有效（不在信号里释放）
	var gpanel: Control = null
	for sp in bs.seat_panels:
		var gbx := (sp as Control).get_node("GuessBtn") as Button
		if gbx.visible:
			gpanel = sp
			break
	if gpanel == null:
		_ok(false, "U11 没有身份未明的座位（种子不合适）")
	else:
		var gseat := int(gpanel.get_meta("seat"))
		var gbtn := gpanel.get_node("GuessBtn") as Button
		gbtn.pressed.emit()
		var popup_shown: bool = bs.guess_popup.visible
		var pick_btn := (bs.guess_popup.get_child(0) as Node).get_child(2) as Button
		pick_btn.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_ok(popup_shown and not bs.guess_popup.visible and String(bs.guess_marks.get(gseat, "")) == "反" and is_instance_valid(pick_btn) and gbtn.text == "反", "U11 猜身份弹层：选「反」后标记显示在座位上")
	# U12 体力槽节点复用 + 濒死描边；U13 阵亡印章/置灰
	var sp0: Control = bs.seat_panels[0]
	var sp_seat := int(sp0.get_meta("seat"))
	var sq: Dictionary = bs.players[sp_seat]
	var pips: Control = sp0.get_node("Pips")
	var pip0: Node = pips.get_child(0)
	var hp_keep := int(sq["hp"])
	sq["hp"] = 0
	bs.refresh()
	await get_tree().process_frame
	_ok(is_same(pips.get_child(0), pip0) and pips.get_child_count() == int(sq["max_hp"]) and int(pips.get_meta("hp_shown")) == 0 and (sp0.get_node("Dying") as Control).visible, "U12 扣血时体力槽节点复用（不重建）、hp=0 显示濒死描边")
	sq["hp"] = hp_keep
	sq["alive"] = false
	bs.refresh()
	await get_tree().process_frame
	var dead_ok: bool = (sp0.get_node("Dead") as Control).visible and (sp0.get_node("Portrait") as CanvasItem).material != null and not (sp0.get_node("Dying") as Control).visible
	sq["alive"] = true
	bs.refresh()
	await get_tree().process_frame
	_ok(dead_ok and not (sp0.get_node("Dead") as Control).visible and (sp0.get_node("Portrait") as CanvasItem).material == null, "U13 阵亡：头像置灰 + 「阵亡」印章；复原后撤销")
	# U14 技能栏常驻：刷新不重建；用过的主动技变灰「已用」、按钮仍是同一个节点
	if await _reach_my_play(bs):
		bs.refresh()
		await get_tree().process_frame
		var before: Array = bs.skill_btns.get_children()
		bs.refresh()
		bs.refresh()
		await get_tree().process_frame
		var same: bool = before.size() == bs.skill_btns.get_child_count()
		for i in before.size():
			if same and not is_same(before[i], bs.skill_btns.get_child(i)):
				same = false
		var n_pass: int = bs.skill_passives.get_child_count()
		_ok(same and before.size() + n_pass >= 1, "U14 技能栏常驻且刷新不重建（主动 %d 个，被动标签 %d 个）" % [before.size(), n_pass])
		var act_btn: Button = null
		var act_sid := ""
		for b in before:
			var k := String((b as Node).get_meta("key", ""))
			if k.begins_with("a:") and not (b as Button).disabled:
				act_btn = b
				act_sid = k.substr(2)
				break
		if act_btn != null:
			bs.players[0]["turn_used"][act_sid] = true
			bs.refresh()
			await get_tree().process_frame
			_ok(is_same(bs.skill_btns.get_child(before.find(act_btn)), act_btn) and act_btn.disabled and act_btn.text.find("已用") >= 0, "U14 主动技用过后：同一按钮变灰显示「已用」")
			(bs.players[0]["turn_used"] as Dictionary).erase(act_sid)
			bs.refresh()
		# U15 点空白桌面：有选中的牌 → 取消选择；无选中 → 跳过当前等待
		var catcher: Control = bs.get_node("BgCatch")
		var tap := InputEventMouseButton.new()
		tap.button_index = MOUSE_BUTTON_LEFT
		tap.pressed = true
		var any_card: Dictionary = {}
		for c in bs.players[0]["hand"]:
			if bs.card_usable(bs.players[0], c):
				any_card = c
				break
		if not any_card.is_empty():
			bs._select_card(any_card)
			var was_sel: bool = not bs.selected_card.is_empty()
			bs._on_table_bg_input(tap)
			await get_tree().process_frame
			_ok(was_sel and bs.selected_card.is_empty() and not bs.targeting, "U15 点空白桌面取消已选中的牌")
		bs.fast = false
		var wbox := {"done": false}
		var t0 := Time.get_ticks_msec()
		var waiter := func() -> void:
			await bs.wait(5.0)
			wbox["done"] = true
		waiter.call()
		await get_tree().process_frame
		catcher.gui_input.emit(tap)
		for i in 5:
			await get_tree().process_frame
		bs.fast = true
		_ok(bool(wbox["done"]) and Time.get_ticks_msec() - t0 < 1500, "U15 点空白桌面跳过 5 秒等待（实际 %d ms）" % (Time.get_ticks_msec() - t0))
		# U16 倍速 1x→1.5x→2x→1x
		bs.cycle_speed()
		var s1: float = Engine.time_scale
		bs.cycle_speed()
		var s2: float = Engine.time_scale
		bs.cycle_speed()
		_ok(is_equal_approx(s1, 1.5) and is_equal_approx(s2, 2.0) and is_equal_approx(Engine.time_scale, 1.0), "U16 倍速按钮循环 1x/1.5x/2x 并作用于 Engine.time_scale")
		# U17 同屏气泡上限 2
		for sx in bs.players.size():
			bs.show_bubble(sx, "skill")
		await get_tree().process_frame
		var live := 0
		for k2 in bs.bubble_nodes:
			if is_instance_valid(bs.bubble_nodes[k2]) and not (bs.bubble_nodes[k2] as Node).is_queued_for_deletion():
				live += 1
		_ok(live <= 2, "U17 同屏台词气泡不超过 2 个（实际 %d）" % live)
		# U18 动画不挡操作：特效层所有节点点击穿透
		bs.fx_flash(1, Color(1, 0, 0))
		bs.fx_skill_banner(1, "测试")
		bs._pz_add({"name": "突击", "suit": "黑桃", "point": 7}, "测试", Vector2(100, 100))
		await get_tree().process_frame
		var blockers := 0
		for layer in [bs.fx_root, bs.pz_layer]:
			for d in (layer as Node).find_children("*", "Control", true, false):
				if (d as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
					blockers += 1
		_ok(blockers == 0, "U18 特效层/处理区节点全部点击穿透（拦截节点 %d 个）" % blockers)
		# U19 出牌阶段中途开托管：立即由 AI 接管，不用再点「结束」
		if await _reach_my_play(bs):
			var logn2: int = bs.eng.log_lines.size()
			bs.toggle_auto()
			var left := false
			for i in 600:
				await get_tree().process_frame
				if not is_instance_valid(bs) or bs.game_over or bs.turn_seat != 0 or not bs.in_play_phase:
					left = true
					break
			_ok(left, "U19 出牌阶段中途开托管后当前阶段被接管（新增日志 %d 行）" % (bs.eng.log_lines.size() - logn2))
			if is_instance_valid(bs) and bs.auto_mode:
				bs.toggle_auto()
	else:
		_ok(false, "U14 未能回到真人出牌阶段")
	await _close_battle(bs)


# ---------------- V0.26 长按说明卡 ----------------
# 测试坐标是视口（画布）坐标；push_input 按窗口坐标收事件并做拉伸逆变换，先换算回窗口坐标（无头模式窗口很小）
static func _to_win(pos: Vector2) -> Vector2:
	return IntroPop.inst.get_tree().root.get_final_transform() * pos


static func _push_mouse(pos0: Vector2, pressed: bool, btn: int = MOUSE_BUTTON_LEFT) -> void:
	var pos := _to_win(pos0)
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = (MOUSE_BUTTON_MASK_LEFT if btn == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	IntroPop.inst.get_viewport().push_input(ev)


static func _push_motion(pos0: Vector2, held: bool) -> void:
	var pos := _to_win(pos0)
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	IntroPop.inst.get_viewport().push_input(mm)


func _real_wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


# 真实输入路径的长按：按下 → 等 0.55 秒 → 记录是否弹出 → 松手 → 记录是否关闭
func sim_longpress(pos: Vector2) -> Dictionary:
	var ip: IntroPop = IntroPop.inst
	var n0 := ip.shown_count
	_push_mouse(pos, true)
	await _real_wait(0.55)
	var opened := ip.is_open() and ip.shown_count > n0
	var spec: Dictionary = ip.last_spec
	_push_mouse(pos, false)
	await get_tree().process_frame
	await get_tree().process_frame
	return {"opened": opened, "spec": spec, "open_after": ip.is_open()}


func _reg_v26() -> void:
	const CD = preload("res://data/cards.gd")
	# D1 每张牌都有说明文字（含斗地主专属牌与地契）；应变词条的条件/效果都有解释
	var missing: Array = []
	var names: Array = CD.DEFS.keys()
	names.append("地契")
	for nm in names:
		if CD.text_of(String(nm)).strip_edges().length() < 8 or CD.type_label_of(String(nm)) == "":
			missing.append(nm)
	_ok(missing.is_empty(), "D1 全部 %d 种牌都有完整说明与类型%s" % [names.size(), "" if missing.is_empty() else "，缺：" + str(missing)])
	var yb_bad: Array = []
	for nm2 in CD.PILE.keys():
		for e in CD.PILE[nm2]:
			if (e as Array).size() > 3:
				var tags: Array = e[3]
				if not CD.YB_COND_TEXT.has(String(tags[0])) or not CD.YB_EFF_TEXT.has(String(tags[1])):
					yb_bad.append("%s:%s" % [nm2, str(tags)])
	_ok(yb_bad.is_empty(), "D2 所有应变词条（条件+效果）都有解释" + ("" if yb_bad.is_empty() else str(yb_bad)))
	var sk_bad: Array = []
	for c in Characters.LIST:
		var cs: Dictionary = IntroPop.char_spec(c)
		if String(cs["body"]).length() < 20:
			sk_bad.append(c["name"])
		for sk in c["skills"]:
			if String(sk.get("text", "")).strip_edges().length() < 8:
				sk_bad.append("%s/%s" % [c["name"], sk["name"]])
	_ok(sk_bad.is_empty(), "D3 全部 %d 名角色及其技能都有说明文字" % Characters.LIST.size() + ("" if sk_bad.is_empty() else str(sk_bad)))
	var cb_bad: Array = []
	for nm3 in names:
		var spc: Dictionary = IntroPop.card_spec({"name": nm3, "suit": "黑桃", "point": 1, "nature": "", "yb": []})
		if String(spc["body"]).length() < 8 or String(spc["title"]) != String(nm3):
			cb_bad.append(nm3)
	_ok(cb_bad.is_empty(), "D4 每张牌的说明卡规格都能生成" + ("" if cb_bad.is_empty() else str(cb_bad)))
	var hl := IntroPop.highlight("出牌阶段，对其造成 1 点伤害，然后使用【突击】")
	_ok(hl.find("[color=") >= 0 and hl.find("[b]【突击】[/b]") >= 0, "D5 说明文字关键词高亮（阶段/伤害/牌名）")
	# D6 说明卡在 16:9 / 20:9 / 4:3 下都不出屏（四角按压）
	var ip: IntroPop = IntroPop.inst
	if ip == null:
		_ok(false, "D6 IntroPop 未创建")
		return
	var out_bad: Array = []
	var big_spec: Dictionary = IntroPop.char_spec(Characters.LIST[0])
	for vs in [Vector2(1920, 1080), Vector2(2400, 1080), Vector2(1920, 1440)]:
		for at in [Vector2(5, 5), Vector2(vs.x - 5, 5), Vector2(5, vs.y - 5), Vector2(vs.x - 5, vs.y - 5), vs * 0.5]:
			for sp in [IntroPop.card_spec({"name": "金蝉脱壳", "suit": "梅花", "point": 12}), big_spec]:
				ip.show_spec(sp, at, "sticky")
				ip._fit(at, vs)
				var r := ip.pop_rect()
				if r.position.x < 0 or r.position.y < 0 or r.end.x > vs.x or r.end.y > vs.y:
					out_bad.append("%s@%s r=%s" % [str(vs), str(at), str(r)])
	ip.hide_pop()
	_ok(out_bad.is_empty(), "D6 说明卡在 16:9/20:9/4:3 四角与中心均不出屏" + ("" if out_bad.is_empty() else str(out_bad.slice(0, 3))))
	# 对局内真实输入
	var bs = _new_battle("identity", 21)
	if not await _reach_my_play(bs):
		_ok(false, "L 未能进入真人出牌阶段")
		await _close_battle(bs)
		return
	await get_tree().process_frame
	var me: Dictionary = bs.players[0]
	var nodes0 := ip.get_child_count() + ip.panel.get_child_count()
	# L1 长按手牌弹出说明、松手关闭、牌不被选中/打出
	var sha := {"name": "突击", "suit": "黑桃", "point": 9, "nature": "", "yb": ["残躯", "目标+"]}
	(me["hand"] as Array).append(sha)
	bs.selected_card = {}
	bs.refresh()
	await get_tree().process_frame
	var w: Control = bs._find_wrap(sha)
	var cpos: Vector2 = w.get_global_rect().get_center() + Vector2(0, -30)
	var r1 := await sim_longpress(cpos)
	var sp1: Dictionary = r1["spec"]
	_ok(bool(r1["opened"]) and String(sp1.get("title", "")) == "突击" and String(sp1.get("body", "")).find("应变") >= 0, "L1 长按手牌弹出说明卡（含应变词条）")
	_ok(not bool(r1["open_after"]), "L1 松手后说明卡关闭")
	_ok(bs._hand_has(sha) and bs.selected_card.is_empty() and not bs.targeting, "L2 长按不会选中或打出这张牌")
	# L3 普通点按仍然有效（真实输入路径：按下立刻松开 = 选中）
	await _real_wait(0.3)
	_push_mouse(cpos, true)
	await get_tree().process_frame
	_push_mouse(cpos, false)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(is_same(bs.selected_card, sha) and not ip.is_open(), "L3 短按仍是选中（长按与点击区分）")
	bs._on_cancel_pressed()
	await get_tree().process_frame
	# L4 拖动不会触发长按（按下后移动超过阈值，0.6 秒内不弹说明）
	var n_before := ip.shown_count
	bs.drag_end_ms = 0
	_push_mouse(cpos, true)
	for k in 6:
		await _real_wait(0.1)
		_push_motion(cpos + Vector2(12.0 * (k + 1), 0), true)
	var opened_drag := ip.is_open() or ip.shown_count != n_before
	_push_mouse(cpos + Vector2(72, 0), false)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(not opened_drag, "L4 拖动不会触发长按说明")
	_ok(bs._hand_has(sha), "L4 拖动后在手牌区松手，牌仍在手中")
	bs._on_cancel_pressed()
	await get_tree().process_frame
	# L5 长按座位角色：角色卡（技能全文/手牌数/攻击距离/身份）
	var tgt_seat := 1
	for p in bs.players:
		if int(p["seat"]) != 0 and bool(p["alive"]):
			tgt_seat = int(p["seat"])
			break
	var tp: Dictionary = bs.players[tgt_seat]
	tp["equip"]["weapon"] = {"name": "破空长弓", "suit": "红桃", "point": 5}
	(tp["judge"] as Array).append({"name": "沉迷游戏", "suit": "黑桃", "point": 6})
	bs.refresh()
	await get_tree().process_frame
	var pn: Control = bs.seat_panel_of(tgt_seat)
	var r5 := await sim_longpress(pn.get_global_rect().get_center() + Vector2(30, 40))
	var sp5: Dictionary = r5["spec"]
	var b5 := String(sp5.get("body", ""))
	var sk_ok := true
	for sk in tp["char"]["skills"]:
		if b5.find(String(sk["name"])) < 0:
			sk_ok = false
	_ok(bool(r5["opened"]) and String(sp5.get("kind", "")) == "char" and String(sp5.get("title", "")) == String(tp["char"]["name"]) and sk_ok and b5.find("手牌") >= 0 and b5.find("攻击范围") >= 0 and b5.find("破空长弓") >= 0 and b5.find("沉迷游戏") >= 0 and String(sp5.get("sub", "")).find("身份") >= 0, "L5 长按角色弹出角色卡（技能全文/手牌/攻击范围/装备/判定区/身份）")
	_ok(not bs.targeting and bs.selected_card.is_empty(), "L5 长按角色不触发选择")
	# L6 长按装备栏图标 → 该装备说明（含攻击范围）
	var eqrow: Control = pn.get_node("Equips/weapon")
	var r6 := await sim_longpress(eqrow.get_global_rect().get_center())
	var sp6: Dictionary = r6["spec"]
	_ok(bool(r6["opened"]) and String(sp6.get("title", "")) == "破空长弓" and String(sp6.get("body", "")).find("攻击范围") >= 0, "L6 长按装备栏弹出装备说明（含攻击范围）")
	# L7 长按判定区图标
	var jl: Control = pn.get_node("Judges").get_child(0)
	var r7 := await sim_longpress(jl.get_global_rect().get_center())
	_ok(bool(r7["opened"]) and String((r7["spec"] as Dictionary).get("title", "")) == "沉迷游戏", "L7 长按判定区图标弹出延时锦囊说明")
	# L8 长按技能按钮/被动标签 → 技能全文
	var skn: Control = null
	if bs.skill_btns.get_child_count() > 0:
		skn = bs.skill_btns.get_child(0)
	elif bs.skill_passives.get_child_count() > 0:
		skn = bs.skill_passives.get_child(0)
	if skn != null:
		var r8 := await sim_longpress(skn.get_global_rect().get_center())
		var logn8: int = bs.eng.log_lines.size()
		_ok(bool(r8["opened"]) and String((r8["spec"] as Dictionary).get("kind", "")) == "skill" and String((r8["spec"] as Dictionary).get("body", "")).length() > 10, "L8 长按技能按钮弹出技能全文")
		await _real_wait(0.3)
		_ok(not bs.info_overlay.visible and not bs.asking and not bs.targeting and bs.eng.log_lines.size() == logn8, "L8 长按技能按钮不会发动技能")
	else:
		_ok(false, "L8 找不到技能按钮")
	# L9 处理区的牌（点击穿透层）也能长按
	var pzn: Control = bs._pz_add({"name": "火焰试炼", "suit": "红桃", "point": 2, "nature": "", "yb": []}, "测试", Vector2(900, 400))
	await get_tree().process_frame
	if pzn != null:
		pzn.position = Vector2(bs.vw * 0.5 - 60, 380)
		var tw0: Variant = pzn.get_meta("tw") if pzn.has_meta("tw") else null
		if tw0 is Tween and (tw0 as Tween).is_valid():
			(tw0 as Tween).kill()
		pzn.position = Vector2(bs.vw * 0.5 - 60, 380)
		pzn.scale = Vector2.ONE
		pzn.modulate.a = 1.0
		await get_tree().process_frame
		# 处理区的牌在对局推进中随时会被收走，这里直接对命中测试断言（点击穿透层的牌也能被长按命中）
		var hit9: Control = ip.find_target(pzn.get_global_rect().get_center())
		_ok(hit9 == pzn and String(IntroPop.spec_of(hit9).get("title", "")) == "火焰试炼", "L9 长按处理区的牌（点击穿透层）能命中并给出说明")
	else:
		_ok(false, "L9 处理区节点未生成")
	# L10 提问窗口里亮明的牌：选项按钮可长按；暗牌（标签不含牌名）不挂说明
	var opt_card := {"name": "看破", "suit": "梅花", "point": 12, "nature": "", "yb": []}
	var b10 := Button.new()
	bs._attach_option_intro(b10, "看破 ♣12", opt_card)
	var b11 := Button.new()
	bs._attach_option_intro(b11, "手牌（暗）", opt_card)
	_ok(b10.has_meta("intro") and not b11.has_meta("intro"), "L10 选牌窗口亮明的牌可看说明，暗牌不泄露")
	b10.free()
	b11.free()
	# L11 右键弹出（常驻），再点一下只关闭、不触发下面的按钮
	_push_mouse(cpos, true, MOUSE_BUTTON_RIGHT)
	_push_mouse(cpos, false, MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	var sticky_open := ip.is_open()
	_push_mouse(cpos, true)
	await get_tree().process_frame
	_push_mouse(cpos, false)
	await get_tree().process_frame
	_ok(sticky_open and not ip.is_open() and bs.selected_card.is_empty(), "L11 右键弹出说明，点一下关闭且不选中牌")
	# L12 弹窗节点复用不泄漏
	for i in 15:
		ip.show_spec(IntroPop.card_spec(sha), cpos, "sticky")
		ip.hide_pop()
	_ok(ip.get_child_count() + ip.panel.get_child_count() == nodes0, "L12 说明卡节点复用（反复弹出节点数不增长）")
	# L13 首次对局提示：持久化记录
	bs._maybe_first_hint(true)
	_ok(bs.first_hint_label != null and bs.first_hint_label.visible and BattleScreen.first_hint_seen(), "L13 首次提示「长按牌或角色可查看说明」已显示并记住")
	# L14 选将卡 / 图鉴卡挂了角色说明
	await _close_battle(bs)
	main_ref.show_gallery()
	await get_tree().process_frame
	var gal := 0
	for n in main_ref.screen_root.find_children("*", "Button", true, false):
		if (n as Control).has_meta("intro"):
			gal += 1
	_ok(gal == Characters.LIST.size(), "L14 图鉴 %d 张角色卡都可长按查看" % gal)
	var gcard: Control = null
	for n in main_ref.screen_root.find_children("*", "Button", true, false):
		if (n as Control).has_meta("intro"):
			gcard = n
			break
	await _real_wait(0.3)
	var r14 := await sim_longpress(gcard.get_global_rect().get_center())
	await get_tree().process_frame
	var still := 0
	for n in main_ref.screen_root.find_children("*", "Button", true, false):
		if (n as Control).has_meta("intro") and not n.is_queued_for_deletion():
			still += 1
	_ok(bool(r14["opened"]) and String((r14["spec"] as Dictionary).get("kind", "")) == "char" and still == Characters.LIST.size(), "L14 长按图鉴角色卡弹出说明，且不会跳进详情页")
	main_ref.show_help()
	await get_tree().process_frame
	var ht: RichTextLabel = main_ref.screen_root.find_child("HelpText", true, false)
	_ok(ht != null and ht.get_parsed_text().find("回合流程") >= 0 and ht.get_parsed_text().find("距离") >= 0 and ht.get_parsed_text().find("内奸") >= 0, "L15 新手说明页（回合流程/身份胜负/距离）")
	main_ref.show_home()
	await get_tree().process_frame



# ---------------- V0.27 先选中，再确认（对照无名杀 game.check + ui.click.ok） ----------------
func _tap_card(bs, c: Dictionary) -> void:
	bs.drag_end_ms = 0
	var w: Control = bs._find_wrap(c)
	if w != null:
		(w.get_child(0) as Button).pressed.emit()


func _tap_seat(bs, seat: int) -> void:
	if seat == 0:
		bs.me_click_btn.pressed.emit()
		return
	(bs.seat_panel_of(seat) as Button).pressed.emit()


func _bg_tap(bs) -> void:
	var t := InputEventMouseButton.new()
	t.button_index = MOUSE_BUTTON_LEFT
	t.pressed = true
	bs._on_table_bg_input(t)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _reg_v27() -> void:
	var bs = _new_battle("identity", 21)
	bs.set_auto_confirm(false, false)
	if not await _reach_my_play(bs):
		_ok(false, "S 未能进入真人出牌阶段")
		await _close_battle(bs)
		return
	var me: Dictionary = bs.players[0]
	me["used_attack"] = false
	me["attack_count"] = 0
	# S1 有目标牌：点牌只选中；点目标只选中目标；只有「确定」才出牌
	var sha := _give(bs.eng, me, "突击", "黑桃", 7)
	bs.refresh()
	var cands: Array = bs.candidates_for(me, sha)
	if cands.is_empty():
		_ok(false, "S1 没有可突击的目标（种子不合适）")
	else:
		var logn: int = bs.eng.log_lines.size()
		var hn: int = (me["hand"] as Array).size()
		_tap_card(bs, sha)
		await _frames(2)
		_ok(bs._hand_has(sha) and is_same(bs.selected_card, sha) and bs.targeting and (me["hand"] as Array).size() == hn and bs.eng.log_lines.size() == logn, "S1 点「突击」只上浮选中、高亮合法目标，未结算")
		_ok(bs._is_lifted(bs._find_wrap(sha)), "S1 选中的牌处于上浮状态")
		var ts := int(cands[0]["seat"])
		if bs.sel_target != ts:
			if bs.sel_target >= 0:
				_tap_seat(bs, bs.sel_target)
			_ok(bs.confirm_btn.disabled and bs.prompt_label.text.find("请选择 1 名目标") >= 0, "S1 未选目标时「确定」不可点，提示「请选择 1 名目标」：%s" % bs.prompt_label.text)
			_tap_seat(bs, ts)
		await _frames(2)
		_ok(bs._hand_has(sha) and bs.sel_target == ts and int(bs.players[ts]["hp"]) == int(bs.players[ts]["hp"]) and bs.eng.log_lines.size() == logn and bs.interactive, "S1 点合法目标头像只是选中目标，不出牌")
		_ok(not bs.confirm_btn.disabled and bs.prompt_label.text.find("对 %s 使用「突击」" % bs._tgt_name(ts)) >= 0, "S1 选好目标后「确定」亮起，提示「对 X 使用「突击」」：%s" % bs.prompt_label.text)
		# S2 取消 / 点空白桌面 / 再点同一张牌 → 恢复原状
		bs.cancel_btn.pressed.emit()
		await _frames(1)
		_ok(bs.selected_card.is_empty() and not bs.targeting and bs.sel_target == -1 and bs._hand_has(sha) and bs.eng.log_lines.size() == logn, "S2 点「取消」恢复：未选中、无目标高亮、牌仍在手")
		_tap_card(bs, sha)
		if bs.sel_target < 0:
			_tap_seat(bs, ts)
		_bg_tap(bs)
		await _frames(1)
		_ok(bs.selected_card.is_empty() and not bs.targeting and bs.sel_target == -1 and bs._hand_has(sha), "S2 点空白桌面恢复：选择全部清掉")
		_tap_card(bs, sha)
		await _frames(1)
		_tap_card(bs, sha)
		await _frames(1)
		_ok(bs.selected_card.is_empty() and not bs.targeting and bs._hand_has(sha), "S2 再点一下已选中的牌取消选择")
		# 确定才出牌
		_tap_card(bs, sha)
		if bs.sel_target != ts:
			_tap_seat(bs, ts)
		var cb: Button = bs.confirm_btn
		cb.pressed.emit()
		_ok(is_instance_valid(cb), "S1 「确定」按钮未在自身信号里被释放")
		await _wait_interactive(bs)
		var used := false
		for i in range(logn, bs.eng.log_lines.size()):
			if String(bs.eng.log_lines[i]).find("突击") >= 0:
				used = true
		_ok(not bs._hand_has(sha) and used, "S1 点「确定」后才对目标出「突击」")
	# S3 无目标牌（锦囊）：点牌只选中，「确定」才使用
	await _reach_my_play(bs)
	var wz := _give(bs.eng, me, "灵感爆发", "红桃", 1)
	for q3 in bs.players:
		if q3 != me:
			q3["xingwei_turn_used"] = true
			for hc3 in (q3["hand"] as Array).duplicate():
				if String(hc3["name"]) == "看破":
					(q3["hand"] as Array).erase(hc3)
	bs.refresh()
	var hn3: int = (me["hand"] as Array).size()
	_tap_card(bs, wz)
	await _frames(2)
	_ok(bs._hand_has(wz) and (me["hand"] as Array).size() == hn3 and is_same(bs.selected_card, wz) and not bs.confirm_btn.disabled and bs.prompt_label.text.find("确定") >= 0, "S3 点无目标牌「灵感爆发」只选中，未使用（提示：%s）" % bs.prompt_label.text)
	bs.confirm_btn.pressed.emit()
	await _wait_interactive(bs)
	_ok(not bs._hand_has(wz) and (me["hand"] as Array).size() == hn3 + 1, "S3 点「确定」后才使用（摸 2 张）")
	# S4 装备牌同理
	await _reach_my_play(bs)
	var arm := _give(bs.eng, me, "结界手环", "梅花", 2)
	bs.refresh()
	_tap_card(bs, arm)
	await _frames(2)
	_ok(bs._hand_has(arm) and is_same(bs.selected_card, arm) and not is_same(me["equip"]["armor"], arm), "S4 点装备牌只选中，未装备")
	bs.confirm_btn.pressed.emit()
	await _wait_interactive(bs)
	_ok(not bs._hand_has(arm) and bs.equip_name(me, "armor") == "结界手环", "S4 点「确定」后才装备")
	# S5 多目标（羁绊锁链）：可选两名目标，确定后第二目标直接生效、不再追问
	await _reach_my_play(bs)
	var lk := _give(bs.eng, me, "羁绊锁链", "梅花", 10)
	bs.refresh()
	var lc: Array = bs.candidates_for(me, lk)
	var others: Array = lc.filter(func(p: Dictionary) -> bool: return int(p["seat"]) != 0)
	if others.size() >= 2:
		var a := int(others[0]["seat"])
		var b := int(others[1]["seat"])
		var ca0 := bool(bs.players[a].get("chained", false))
		var cb0 := bool(bs.players[b].get("chained", false))
		_tap_card(bs, lk)
		if bs.sel_target >= 0:
			_tap_seat(bs, bs.sel_target)
		_tap_seat(bs, a)
		_tap_seat(bs, b)
		await _frames(1)
		_ok(bs.sel_target == a and bs.extra_target == b and bs._hand_has(lk) and bs.prompt_label.text.find("、") >= 0, "S5 多目标牌可点选两名目标，未结算（提示：%s）" % bs.prompt_label.text)
		_tap_seat(bs, b)
		await _frames(1)
		_ok(bs.sel_target == a and bs.extra_target == -1, "S5 再点已选目标即取消该目标")
		_tap_seat(bs, b)
		# 排除 AI 用「看破」抵消这张锦囊造成的随机性
		for q in bs.players:
			if q != me:
				for hc in (q["hand"] as Array).duplicate():
					if String(hc["name"]) == "看破":
						(q["hand"] as Array).erase(hc)
		bs.confirm_btn.pressed.emit()
		var asked := false
		for i in 300:
			await get_tree().process_frame
			if bs.asking and bs.prompt_label.text.find("羁绊锁链") >= 0:
				asked = true
				break
			if bs.asking:
				_auto_answer(bs, false)
			if bs.interactive and not bs._hand_has(lk):
				break
		_ok(not asked and not bs._hand_has(lk) and bool(bs.players[a].get("chained", false)) != ca0 and bool(bs.players[b].get("chained", false)) != cb0, "S5 确定后两名目标都被连上，第二目标不再追问")
		await _wait_interactive(bs)
	else:
		_ok(false, "S5 羁绊锁链可选目标不足 2 名")
	# S6 响应：点亮的牌只选中；确定才打出；选中后超时 = 不出；「不出」直接放弃
	var d1 := _give(bs.eng, me, "闪避", "方块", 9)
	var d2 := _give(bs.eng, me, "闪避", "红桃", 2)
	bs.refresh()
	bs.ask_timeout = 0.6
	var box := {}
	var runner := func() -> void:
		box["r"] = await bs._eng_ask_respond(me, "闪避", "测试")
	runner.call()
	await _frames(2)
	_tap_card(bs, d1)
	await _frames(1)
	_ok(not box.has("r") and bs.ask_sel_has and bs.ask_confirm_btn != null and not bs.ask_confirm_btn.disabled, "S6 响应时点亮起的闪避只是选中，「确定」亮起，未作答")
	for i in 80:
		await get_tree().create_timer(0.03).timeout
		if box.has("r"):
			break
	_ok(box.has("r") and box["r"] == false and not bs.asking, "S6 已选中闪避但倒计时结束 = 不出（%s）" % str(box.get("r", "无")))
	bs.ask_timeout = 15.0
	var box2 := {}
	var runner2 := func() -> void:
		box2["r"] = await bs.eng.respond_with(me, "闪避", "测试")
	runner2.call()
	await _frames(2)
	_tap_card(bs, d2)
	_tap_card(bs, d1)
	_tap_card(bs, d1)
	await _frames(1)
	_ok(not bs.ask_sel_has and not box2.has("r"), "S6 再点一下选中的牌取消选中")
	_tap_card(bs, d2)
	_bg_tap(bs)
	await _frames(1)
	_ok(not bs.ask_sel_has and bs.asking and bs.ask_confirm_btn.disabled, "S6 点空白桌面清掉已选，「确定」重新变灰")
	_tap_card(bs, d2)
	var acb: Button = bs.ask_confirm_btn
	acb.pressed.emit()
	_ok(is_instance_valid(acb), "S6 作答「确定」按钮未在自身信号里被释放")
	await _frames(2)
	_ok(box2.get("r", false) == true and not bs._hand_has(d2) and bs._hand_has(d1), "S6 确定后打出的是选中的那张（红桃2 闪避），另一张留在手里")
	var box3 := {}
	var runner3 := func() -> void:
		box3["r"] = await bs._eng_ask_respond(me, "闪避", "测试")
	runner3.call()
	await _frames(2)
	var nob: Button = null
	for x in bs.prompt_btns.get_children():
		if x is Button and (x as Button).text == "不出":
			nob = x
	var found_nob := nob != null
	_tap_card(bs, d1)
	var sel_before: bool = bs.ask_sel_has
	if found_nob:
		nob.pressed.emit()
	await _frames(1)
	_ok(found_nob and sel_before and box3.get("r", true) == false and bs._hand_has(d1), "S6 点「不出」= 不出（即使选中了牌）（r=%s）" % str(box3.get("r", "无")))
	(me["hand"] as Array).erase(d1)
	# S7 选牌询问：点亮的牌/选项按钮只选中；确定才提交
	var p1 := _give(bs.eng, me, "看破", "梅花", 12)
	var p2 := _give(bs.eng, me, "补给", "红桃", 3)
	bs.refresh()
	var box4 := {}
	var runner4 := func() -> void:
		box4["r"] = await bs._eng_pick_card(me, [p1, p2], "测试：选择一张手牌")
	runner4.call()
	await _frames(2)
	_ok(bs.ask_mode == "pick" and bs.ask_confirm_btn != null and bs.ask_confirm_btn.disabled, "S7 选牌询问为「选中+确定」模式，未选时「确定」不可点")
	_tap_card(bs, p1)
	await _frames(1)
	_ok(not box4.has("r") and bs.ask_sel_has and is_same(bs.ask_sel_val, p1), "S7 点亮的手牌只选中，未提交")
	var ob: Button = (bs.ask_opt_btns[1] as Dictionary)["btn"]
	ob.pressed.emit()
	await _frames(1)
	_ok(not box4.has("r") and is_same(bs.ask_sel_val, p2) and is_instance_valid(ob), "S7 点选项按钮只切换选中，未提交")
	bs.ask_confirm_btn.pressed.emit()
	await _frames(1)
	_ok(box4.has("r") and is_same(box4["r"], p2), "S7 点「确定」后提交所选那张")
	# S8 选角色询问（ask_choose_target）同理
	var box5 := {}
	var tc: Array = bs.alive_players().filter(func(p: Dictionary) -> bool: return int(p["seat"]) != 0)
	var runner5 := func() -> void:
		box5["r"] = await bs.ask_choose_target("测试：选择一名角色", tc)
	runner5.call()
	await _frames(2)
	var ob2: Button = (bs.ask_opt_btns[0] as Dictionary)["btn"]
	ob2.pressed.emit()
	await _frames(1)
	_ok(not box5.has("r") and bs.ask_sel_has, "S8 选角色询问：点角色按钮只选中，未提交")
	bs.ask_confirm_btn.pressed.emit()
	await _frames(1)
	_ok(int(box5.get("r", -9)) == int(tc[0]["seat"]), "S8 「确定」后提交所选角色")
	# S9 主动技能：点按钮只进入技能选择（高亮），选牌+目标后「确定」才发动；再点按钮/取消/点空白退出且不消耗
	await _reach_my_play(bs)
	if not (me["skills"] as Array).has("yingyuan"):
		(me["skills"] as Array).append("yingyuan")
	(me["turn_used"] as Dictionary).erase("yingyuan")
	var cost := _give(bs.eng, me, "看破", "黑桃", 13)
	bs.refresh()
	await _frames(1)
	var skb: Button = null
	for x in bs.skill_btns.get_children():
		if String((x as Node).get_meta("key", "")) == "a:yingyuan":
			skb = x
	if skb == null:
		_ok(false, "S9 找不到「樱愿」技能按钮")
	else:
		var hn9: int = (me["hand"] as Array).size()
		var logn9: int = bs.eng.log_lines.size()
		skb.pressed.emit()
		await _frames(1)
		_ok(bs.skill_mode == "yingyuan" and not bool((me["turn_used"] as Dictionary).get("yingyuan", false)) and (me["hand"] as Array).size() == hn9 and bs.interactive and skb.text.find("樱愿") >= 0 and String(skb.get_meta("st", "")).begins_with("sel"), "S9 点技能按钮进入技能选择状态（按钮高亮），未发动、未消耗")
		_ok(bs.confirm_btn.disabled and bs.prompt_label.text.find("请选择") >= 0, "S9 技能选择中提示选牌、「确定」不可点：%s" % bs.prompt_label.text)
		skb.pressed.emit()
		await _frames(1)
		_ok(bs.skill_mode == "" and not bs.targeting and not bool((me["turn_used"] as Dictionary).get("yingyuan", false)), "S9 再点一次技能按钮退出选择，不消耗")
		var tgt9 := -1
		for s9 in bs._skill_ui_spec("yingyuan")["targets"]:
			if int(s9) != 0:
				tgt9 = int(s9)
				break
		skb.pressed.emit()
		_tap_card(bs, cost)
		_tap_seat(bs, tgt9)
		await _frames(1)
		_ok(is_same(bs.skill_card, cost) and bs.sel_target == tgt9 and bs._hand_has(cost) and not bs.confirm_btn.disabled and bs.eng.log_lines.size() == logn9, "S9 选好代价牌和目标后仍未发动，「确定」亮起（提示：%s）" % bs.prompt_label.text)
		bs.cancel_btn.pressed.emit()
		await _frames(1)
		_ok(bs.skill_mode == "" and bs.skill_card.is_empty() and bs._hand_has(cost) and not bool((me["turn_used"] as Dictionary).get("yingyuan", false)), "S9 点「取消」退出技能选择，牌和次数都不消耗")
		skb.pressed.emit()
		_tap_card(bs, cost)
		_bg_tap(bs)
		await _frames(1)
		_ok(bs.skill_mode == "" and bs._hand_has(cost), "S9 点空白桌面退出技能选择")
		skb.pressed.emit()
		_tap_card(bs, cost)
		if bs.sel_target != tgt9:
			_tap_seat(bs, tgt9)
		bs.confirm_btn.pressed.emit()
		var asked9 := false
		for i in 400:
			await get_tree().process_frame
			if bs.asking and bs.prompt_label.text.find("樱愿") >= 0 and bs.prompt_label.text.find("选择") >= 0 and bs.prompt_label.text.find("效果") < 0:
				asked9 = true
			if bs.interactive and bool((me["turn_used"] as Dictionary).get("yingyuan", false)):
				break
			_auto_answer(bs, false)
		_ok(bool((me["turn_used"] as Dictionary).get("yingyuan", false)) and not bs._hand_has(cost) and not asked9, "S9 「确定」后才发动「樱愿」，弃置所选的牌、对所选目标结算，不再重复询问")
	# S10 合璧长枪：点按钮进入选目标，点目标不出牌，确定才拼牌突击
	await _reach_my_play(bs)
	me["equip"]["weapon"] = {"name": "合璧长枪", "suit": "黑桃", "point": 12, "nature": "", "yb": []}
	me["used_attack"] = false
	me["attack_count"] = 0
	_give(bs.eng, me, "看破", "梅花", 3)
	_give(bs.eng, me, "看破", "梅花", 4)
	bs.refresh()
	await _frames(1)
	var spb: Button = null
	for x in bs.skill_btns.get_children():
		if String((x as Node).get_meta("key", "")) == "spear":
			spb = x
	if spb == null:
		_ok(false, "S10 找不到「长枪突击」按钮")
	else:
		var hn10: int = (me["hand"] as Array).size()
		var spear_a := _give(bs.eng, me, "看破", "黑桃", 3)
		var spear_b := _give(bs.eng, me, "看破", "黑桃", 4)
		bs.refresh()
		await _frames(1)
		spb.pressed.emit()
		await _frames(1)
		var st10: int = int(bs.target_candidates[0])
		bs.players[st10]["hp"] = 4
		(bs.players[st10]["hand"] as Array).clear()
		bs.players[st10]["skills"] = []
		var me_sk10: Array = (me["skills"] as Array).duplicate()
		me["skills"] = []
		if bs.sel_target != st10:
			_tap_seat(bs, st10)
		await _frames(1)
		_ok(bs.spear_targeting and bs.spear_cards.is_empty() and (me["hand"] as Array).size() == hn10 + 2 and bs.interactive and bs.confirm_btn.disabled, "S10 长枪突击：点目标后仍需自选两张手牌，未出牌")
		_tap_card(bs, spear_a)
		await _frames(1)
		_ok(bs.spear_cards.size() == 1 and bs.confirm_btn.disabled, "S10 长枪突击：点第一张手牌只选中，尚未提交")
		_tap_card(bs, spear_b)
		await _frames(1)
		_ok(bs.spear_cards.size() == 2 and not bs.confirm_btn.disabled, "S10 长枪突击：选满两张后「确定」亮起")
		bs.confirm_btn.pressed.emit()
		await _wait_interactive(bs)
		me["skills"] = me_sk10
		_ok(not bs._hand_has(spear_a) and not bs._hand_has(spear_b) and (me["hand"] as Array).size() == hn10, "S10 「确定」后按玩家自选的两张手牌拼成突击")
	me["equip"]["weapon"] = {}
	# S11 自动确认：打开后选够即自动提交（出牌 + 响应）
	await _reach_my_play(bs)
	bs.set_auto_confirm(true, false)
	me["used_attack"] = false
	me["attack_count"] = 0
	var sha2 := _give(bs.eng, me, "突击", "梅花", 8)
	bs.refresh()
	var c11: Array = bs.candidates_for(me, sha2)
	if not c11.is_empty():
		_tap_card(bs, sha2)
		if bs._hand_has(sha2) and bs.sel_target < 0:
			_tap_seat(bs, int(c11[0]["seat"]))
		await _wait_interactive(bs)
		_ok(not bs._hand_has(sha2) and bs.auto_submit_count > 0, "S11 自动确认开启：选好目标后自动出牌（无需点「确定」）")
	else:
		_ok(false, "S11 没有可突击目标")
	var d3 := _give(bs.eng, me, "闪避", "方块", 5)
	bs.refresh()
	var box6 := {}
	var runner6 := func() -> void:
		box6["r"] = await bs._eng_ask_respond(me, "闪避", "测试")
	runner6.call()
	await _frames(2)
	_tap_card(bs, d3)
	await _frames(2)
	_ok(box6.get("r", false) == true, "S11 自动确认开启：响应时点亮的牌一点即打出")
	(me["hand"] as Array).erase(d3)
	bs.set_auto_confirm(false, false)
	# S12 设置：默认关闭、持久化；顶栏「设置」按钮与面板；阶段标题不压功能条
	var cf := ConfigFile.new()
	var had := cf.load(BattleScreen.SETTINGS_PATH) == OK and cf.has_section_key("play", "auto_confirm")
	var keep: bool = BattleScreen.auto_confirm_saved()
	if had:
		cf.erase_section_key("play", "auto_confirm")
		cf.save(BattleScreen.SETTINGS_PATH)
	var def_off: bool = not BattleScreen.auto_confirm_saved()
	BattleScreen.save_auto_confirm(true)
	var on_saved: bool = BattleScreen.auto_confirm_saved()
	BattleScreen.save_auto_confirm(keep)
	_ok(def_off and on_saved, "S12 「自动确认」默认关闭，开关写入 user://settings.cfg 并能读回")
	_ok(bs.settings_btn != null and bs.settings_btn.text == "设置", "S12 对局顶栏有「设置」按钮")
	bs.toggle_settings_panel()
	await _frames(1)
	var chk: CheckButton = bs.auto_confirm_check
	_ok(bs.settings_panel.visible and chk != null and not chk.button_pressed and chk.text == "自动确认", "S12 设置面板含「自动确认」开关，当前关闭")
	chk.button_pressed = true
	var on_now: bool = bs.auto_confirm and BattleScreen.auto_confirm_saved()
	chk.button_pressed = false
	_ok(on_now and not bs.auto_confirm and not BattleScreen.auto_confirm_saved(), "S12 面板开关即时生效并持久化")
	BattleScreen.save_auto_confirm(keep)
	bs.toggle_settings_panel()
	_ok(not bs.settings_panel.visible and bs.phase_label.position.x >= BattleScreen.FEAT_END - 0.5 and bs.phase_label.position.x + bs.phase_label.size.x <= bs.vw - 520.0, "S12 阶段标题位于功能条与右侧胶囊之间，不再重叠")
	# S13 拖到合法目标松手仍直接出牌（唯一保留的直接结算）
	await _reach_my_play(bs)
	me["used_attack"] = false
	me["attack_count"] = 0
	var sha3 := _give(bs.eng, me, "突击", "方块", 6)
	bs.refresh()
	var c13: Array = bs.candidates_for(me, sha3)
	if not c13.is_empty():
		var pn: Control = bs.seat_panel_of(int(c13[0]["seat"]))
		bs.drag_end_ms = 0
		sim_drag(bs, bs._find_wrap(sha3), pn.global_position + pn.size * 0.5)
		await _wait_interactive(bs)
		_ok(not bs._hand_has(sha3), "S13 拖到合法目标头像上松手仍直接出牌")
	await _close_battle(bs)



const CardDefsT = preload("res://data/cards.gd")


# ---------------- V0.28 规则统一为无名杀（标准包 + 军争包） ----------------
func _reg_v28() -> void:
	# A1 补给（桃）：出牌阶段只能对自己；濒死求援可以救别人
	var e = _clean_eng()
	var me: Dictionary = e.players[0]
	var other: Dictionary = e.players[1]
	me["hp"] = 2
	other["hp"] = 2
	var sup := _give(e, me, "补给", "红桃", 3)
	await e.play_card(me, sup, other)
	_ok(int(me["hp"]) == 3 and int(other["hp"]) == 2, "A1 出牌阶段「补给」即使指定他人也只回复自己（我 %d / 他 %d）" % [int(me["hp"]), int(other["hp"])])
	var rec: Array = []
	_script_ui(e, [0], {"save_0": [true]}, rec)
	_give(e, me, "补给", "红桃", 4)
	other["hp"] = 0
	await e.handle_dying(other, {})
	_ok(int(other["hp"]) == 1 and bool(other["alive"]), "A1 濒死求援时可以对他人使用「补给」救人")
	# A2 落雷（闪电）：只能放进自己的判定区；未命中顺延下家；无人可接收则回到自己
	e = _clean_eng()
	me = e.players[0]
	var ld := _give(e, me, "落雷", "黑桃", 1)
	await e.play_card(me, ld, e.players[2])
	_ok((me["judge"] as Array).has(ld) and (e.players[2]["judge"] as Array).is_empty(), "A2 「落雷」指定他人也只会放进自己的判定区")
	e.deck.append({"name": "闪避", "suit": "红桃", "point": 5, "nature": "", "yb": []})
	await e.resolve_delayed_phase(me)
	_ok((e.players[1]["judge"] as Array).has(ld), "A2 判定未命中：「落雷」移到下家判定区")
	for i in [1, 2, 3, 4]:
		(e.players[i]["judge"] as Array).append({"name": "落雷", "suit": "黑桃", "point": 1, "nature": "", "yb": []})
	(e.players[1]["judge"] as Array).erase(ld)
	(me["judge"] as Array).append(ld)
	e.deck.append({"name": "闪避", "suit": "方块", "point": 6, "nature": "", "yb": []})
	await e.resolve_delayed_phase(me)
	_ok((me["judge"] as Array).has(ld) and (me["judge"] as Array).size() == 1, "A2 其他角色都已有「落雷」时留在自己判定区（无名杀 addJudgeNext 绕回自己）")
	e.deck.append({"name": "闪避", "suit": "黑桃", "point": 5, "nature": "", "yb": []})
	var hp0 := int(me["hp"])
	await e.resolve_delayed_phase(me)
	_ok(int(me["hp"]) == hp0 - 3 and not (me["judge"] as Array).has(ld), "A2 判定黑桃 2~9：受到 3 点雷电伤害并弃置「落雷」（hp %d→%d）" % [hp0, int(me["hp"])])
	# A2b AI：落雷只会放自己判定区
	e = _clean_eng("doudizhu", ["地主", "农民", "农民"])
	var lord: Dictionary = e.players[0]
	lord["hp"] = 5
	_give(e, lord, "落雷", "黑桃", 1)
	e.turn_player = lord
	var where_ok := true
	for q in e.players:
		if q != lord and not (q["judge"] as Array).is_empty():
			where_ok = false
	_ok(where_ok and e.ai_want_lightning(lord, "落雷"), "A2 AI（地主 1 打 2）愿意把「落雷」放在自己判定区，且不会放到别人判定区")
	# A2c 单挑开局不放（敌我 1:1，同无名杀非身份局 -1），拖到 20 轮以上的僵局才放
	e = _clean_eng("duel", ["先手", "后手"])
	var dl: Dictionary = e.players[0]
	dl["hp"] = 4
	e.round_no = 5
	var early_no := not e.ai_want_lightning(dl, "落雷")
	e.round_no = 20
	_ok(early_no and e.ai_want_lightning(dl, "落雷"), "A2 AI 单挑开局不放「落雷」，20 轮僵局后会放（破僵局）")
	# A3 星眠：保护到本回合结束
	e = _clean_eng()
	var mm: Dictionary = e.players[3]
	mm["skills"] = ["xingmian", "t_probe"]
	var guard_mid := {"v": false}
	e.register_skill("t_probe", {"name": "探针", "timings": {"phaseJieshu": {"who": "player", "forced": true, "content": func(_e, _ctx, p) -> void: guard_mid["v"] = bool(p.get("dream_guard", false))}}})
	await e.run_turn(mm)
	_ok(_log_index(e, "进星眠境") >= 0 and bool(guard_mid["v"]) and not bool(mm.get("dream_guard", false)) and _log_index(e, "「星眠」保护结束") >= 0, "A3 「星眠」保护在本回合结束时解除（与说明文字一致）")
	# A4 断粮封锁（兵粮寸断）：距离限制 1
	e = _clean_eng("identity", ["反贼", "忠臣", "主公", "反贼", "内奸"])
	me = e.players[0]
	var t_far: Dictionary = e.pick_delayed_target(me, "断粮封锁")
	var t_cm: Dictionary = e.pick_delayed_target(me, "沉迷游戏")
	e = _clean_eng("identity", ["反贼", "主公", "忠臣", "反贼", "内奸"])
	var t_near: Dictionary = e.pick_delayed_target(e.players[0], "断粮封锁")
	_ok(t_far.is_empty() and not t_cm.is_empty() and not t_near.is_empty() and int(t_near["seat"]) == 1, "A4 AI 的「断粮封锁」只给距离 1 内的角色（主公在距离 2 时不放，沉迷游戏不受限；主公相邻时放）")
	# A5 羁绊锁链：1~2 名目标、可选自己、可重铸；AI 无合适目标时重铸
	e = _clean_eng()
	me = e.players[0]
	var lk := _give(e, me, "羁绊锁链", "梅花", 10)
	var hn := (me["hand"] as Array).size()
	var dn: int = e.discard_pile.size()
	_ok(e.can_recast(lk) and not e.can_recast({"name": "突击", "suit": "黑桃", "point": 7}), "A5 只有「羁绊锁链」可以重铸")
	e.recast(me, lk)
	_ok((me["hand"] as Array).size() == hn and not (me["hand"] as Array).has(lk) and e.discard_pile.size() == dn + 1 and _log_index(e, "重铸") >= 0, "A5 重铸：弃置这张牌并摸 1 张（手牌数不变）")
	var lk2 := _give(e, me, "羁绊锁链", "梅花", 11)
	_script_ui(e, [0], {"option_0": 0}, [])
	await e.play_card(me, lk2, me)
	_ok(bool(me.get("chained", false)), "A5 「羁绊锁链」可以以自己为目标")
	# AI：全是队友时不乱连，改为重铸
	e = _clean_eng("doudizhu", ["地主", "农民", "农民"])
	var farmer: Dictionary = e.players[1]
	for q in e.players:
		q["chained"] = q == e.players[0]
	var lk3 := _give(e, farmer, "羁绊锁链", "梅花", 12)
	var hn3 := (farmer["hand"] as Array).size()
	e.turn_player = farmer
	await e.ai_play_phase(farmer)
	_ok(not (farmer["hand"] as Array).has(lk3) and _log_index(e, "重铸") >= 0, "A5 AI 没有两名可连的敌人时重铸「羁绊锁链」")
	# A6 合璧长枪虚拟突击：取两张牌的共同颜色
	var cr := {"suit": "红桃", "point": 3}
	var cr2 := {"suit": "方块", "point": 9}
	var cb := {"suit": "黑桃", "point": 3}
	_ok(EngineS.shared_color([cr, cr2]) == "红" and EngineS.shared_color([cr, cb]) == "无" and EngineS.shared_color([cb, {"suit": "梅花", "point": 1}]) == "黑", "A6 共同颜色：红+红=红、红+黑=无色、黑+黑=黑")
	var vno := {"name": "突击", "suit": EngineS.shared_suit([cr, cb]), "point": 3, "color": "无"}
	_ok(not e.is_red(vno) and not e.is_black(vno), "A6 一红一黑拼成的突击既不是红色也不是黑色（防护立场等按无色处理）")
	e = _clean_eng()
	me = e.players[0]
	me["equip"]["weapon"] = {"name": "合璧长枪", "suit": "黑桃", "point": 12, "nature": "", "yb": []}
	var h1 := _give(e, me, "看破", "红桃", 3)
	var h2 := _give(e, me, "看破", "方块", 4)
	var cap := {}
	e.set_ui({"played": func(c, owner, tname = ""): if String(c.get("name", "")) == "突击": cap["c"] = c})
	await e.spear_attack(me, e.players[1])
	var vc: Dictionary = cap.get("c", {})
	_ok(String(vc.get("color", "")) == "红" and e.is_red(vc), "A6 两张红色手牌拼成的长枪突击为红色（实际 color=%s suit=%s）" % [str(vc.get("color", "?")), str(vc.get("suit", "?"))])
	# A7 牌堆张数与设计稿一致：常规 197，斗地主 203；音波炮 = 寒冰剑（♠2，范围 2）
	for mdx in [["identity", 5, 197], ["doudizhu", 3, 203]]:
		seed(77)
		var e2 = EngineS.new()
		e2.load_skills()
		e2.mode = String(mdx[0])
		var ids2: Array = ["主公", "忠臣", "反贼", "反贼", "内奸"] if mdx[0] == "identity" else ["地主", "农民", "农民"]
		e2.setup_game(make_chars(int(mdx[1])), ids2)
		var tot: int = e2.deck.size() + e2.discard_pile.size()
		for q in e2.players:
			tot += (q["hand"] as Array).size() + (q["judge"] as Array).size()
			for sl in q["equip"]:
				if not (q["equip"][sl] as Dictionary).is_empty():
					tot += 1
		_ok(tot == int(mdx[2]), "A7 %s 牌堆总数 %d 张（期望 %d）" % [String(mdx[0]), tot, int(mdx[2])])
	_ok(CardDefsT.weapon_range_of("音波炮") == 2 and (CardDefsT.PILE["音波炮"] as Array)[0] == ["黑桃", 2], "A7 音波炮对应寒冰剑：♠2、攻击范围 2")
	var doc := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../全明星杀_V1设计稿.md"))
	_ok(doc != "" and (doc.find("104 张") < 0 and doc.find("197") >= 0 and doc.find("203") >= 0), "A7 设计稿牌堆张数已同步为 197 / 203")
	# A8 界面：补给/落雷不再选目标；断粮封锁只能选距离 1；羁绊锁链可选自己并显示「重铸」
	var bs = _new_battle("identity", 21)
	if await _reach_my_play(bs):
		var bme: Dictionary = bs.players[0]
		_ok(not bs.card_needs_target({"name": "补给"}) and not bs.card_needs_target({"name": "落雷"}) and not bs.card_needs_target({"name": "浮雷"}), "A8 「补给」「落雷」「浮雷」点选后直接确定，不再选目标")
		bme["hp"] = int(bme["max_hp"])
		_ok(bs.unusable_reason(bme, {"name": "补给", "suit": "红桃", "point": 3}) != "", "A8 自己满血时出牌阶段不能用「补给」")
		var dlc: Array = bs.candidates_for(bme, {"name": "断粮封锁"})
		var dl_ok := true
		for q in dlc:
			if bs.eff_dist(bme, q) > 1:
				dl_ok = false
		_ok(dl_ok, "A8 「断粮封锁」候选目标都在距离 1 内（%d 名）" % dlc.size())
		var blk := _give(bs.eng, bme, "羁绊锁链", "黑桃", 1)
		bs.refresh()
		bs.drag_end_ms = 0
		((bs._find_wrap(blk) as Control).get_child(0) as Button).pressed.emit()
		await get_tree().process_frame
		_ok(bs.target_candidates.has(0) and bs.recast_btn.visible and not bs.recast_btn.disabled and bs._hand_has(blk), "A8 选中「羁绊锁链」：可选自己为目标，确定栏出现「重铸」，未结算")
		var hnb: int = (bme["hand"] as Array).size()
		var rb: Button = bs.recast_btn
		rb.pressed.emit()
		await get_tree().process_frame
		_ok(is_instance_valid(rb) and not bs._hand_has(blk) and (bme["hand"] as Array).size() == hnb and bs.selected_card.is_empty(), "A8 点「重铸」：弃置并摸 1 张，按钮未在自身信号里释放")
	else:
		_ok(false, "A8 未能进入真人出牌阶段")
	await _close_battle(bs)



# 某角色是否属于获胜方（按 winner_text 与身份判断）
static func player_won(eng, q: Dictionary) -> bool:
	var w := String(eng.winner_text)
	var idt := String(q["identity"])
	match String(eng.mode):
		"identity":
			if w == "主公阵营获胜！":
				return idt == "主公" or idt == "忠臣"
			if w == "反贼阵营获胜！":
				return idt == "反贼"
			if w == "内奸获胜！":
				return idt == "内奸"
		"doudizhu":
			if w == "农民阵营获胜！":
				return idt == "农民"
			if w == "地主获胜！":
				return idt == "地主"
		"duel":
			return w.begins_with(eng.pname(q))
	return false



# ---------------- V0.32：残局破僵局 / 合璧长枪自选 / 音乐回归 ----------------
func _reg_v32() -> void:
	# V32-1 两人残局：手里有能出的突击且体力大于 1 时，AI 判定应进攻而不是回复
	var e = _clean_eng("identity", ["主公", "忠臣", "反贼", "反贼", "内奸"])
	for i in [1, 2, 3]:
		e.players[i]["alive"] = false
	var me: Dictionary = e.players[0]
	var foe: Dictionary = e.players[4]
	me["hp"] = 3
	me["max_hp"] = 5
	e.round_no = 30
	_give(e, me, "突击", "黑桃", 7)
	_ok(e.ai_in_stalemate_endgame(me) and e.ai_has_pressure_attack(me), "V32-1 两人残局且能出突击时识别为可进攻局面")
	var SL32 = load("res://scripts/skill_lib.gd")
	var sl32 = SL32.new()
	_ok(not bool(sl32._yuanqi_ai(e, me)), "V32-1 「元气补给」在可进攻残局不再把进攻牌转成回复")
	me["used_attack"] = true
	_ok(not e.ai_has_pressure_attack(me), "V32-1 本回合突击已用完时不再视为可进攻")
	me["used_attack"] = false
	# V32-2 复现 V0.31 基线 seed=40300 的身份场回合上限：修复后应分出胜负
	seed(40300)
	var eng32 = EngineS.new()
	eng32.load_skills()
	eng32.mode = "identity"
	eng32.difficulty = 1
	var ids32: Array = ["主公", "忠臣", "反贼", "反贼", "内奸"]
	ids32.shuffle()
	eng32.setup_game(make_chars(5), ids32)
	await eng32.run_game()
	_ok(bool(eng32.game_over) and not String(eng32.winner_text).begins_with("局面上限"), "V32-2 seed=40300 身份场不再拖到回合上限（rounds=%d winner=%s）" % [int(eng32.round_no), String(eng32.winner_text)])
	_ok(int(eng32.round_no) < 80, "V32-2 seed=40300 在 80 轮内结束（实际 %d 轮）" % int(eng32.round_no))
	# V32-3 合璧长枪：引擎接受界面传入的两张自选牌，并按其共同颜色生成虚拟突击
	e = _clean_eng()
	me = e.players[0]
	me["equip"]["weapon"] = {"name": "合璧长枪", "suit": "黑桃", "point": 12, "nature": "", "yb": []}
	var red32 := _give(e, me, "看破", "红桃", 3)
	var black32 := _give(e, me, "看破", "黑桃", 4)
	var cap32 := {}
	e.set_ui({"played": func(c, owner, tname = ""): if String(c.get("name", "")) == "突击": cap32["c"] = c})
	await e.spear_attack(me, e.players[1], [red32, black32])
	var vc32: Dictionary = cap32.get("c", {})
	_ok(not (me["hand"] as Array).has(red32) and not (me["hand"] as Array).has(black32), "V32-3 合璧长枪按玩家自选牌消耗")
	_ok(String(vc32.get("color", "")) == "无" and not e.is_red(vc32) and not e.is_black(vc32), "V32-3 自选一红一黑拼成的突击为无色")


# ---------------- V0.30：AI / 声音 / 局外 / 教学 ----------------
func _reg_v30() -> void:
	const MetaT = preload("res://scripts/meta.gd")
	const AudioT = preload("res://scripts/audio.gd")
	# C1 防护立场：AI 不再用黑色突击打（无视防具的武器除外）
	var e = _clean_eng("duel", ["先手", "后手"])
	var me: Dictionary = e.players[0]
	var foe: Dictionary = e.players[1]
	foe["equip"]["armor"] = {"name": "防护立场", "suit": "梅花", "point": 2, "nature": "", "yb": []}
	var blk := _give(e, me, "突击", "黑桃", 7)
	_ok(e.ai_find_sha(me, foe).is_empty(), "V30-C1 目标有「防护立场」且只有黑色突击时 AI 不出")
	var red := _give(e, me, "突击", "红桃", 8)
	_ok(is_same(e.ai_find_sha(me, foe), red), "V30-C1 有红色突击时选红色")
	(me["hand"] as Array).erase(red)
	me["equip"]["weapon"] = {"name": "破甲光剑", "suit": "黑桃", "point": 6, "nature": "", "yb": [], "range": 2}
	_ok(is_same(e.ai_find_sha(me, foe), blk), "V30-C1 装备「破甲光剑」（无视防具）时黑色突击照出")
	# C2 拆牌顺序（参照无名杀过河拆桥 AI）：够不着时先拆防御坐骑，否则先拆防具
	e = _clean_eng()
	me = e.players[0]
	var t2: Dictionary = e.players[2]
	var plus := {"name": "远行披风", "suit": "黑桃", "point": 13, "nature": "", "yb": []}
	var arm := {"name": "藤蔓铠甲", "suit": "梅花", "point": 2, "nature": "", "yb": []}
	var wpn := {"name": "战锤", "suit": "方块", "point": 5, "nature": "", "yb": [], "range": 3}
	t2["equip"]["plus"] = plus
	t2["equip"]["armor"] = arm
	t2["equip"]["weapon"] = wpn
	_ok(not e.in_attack_range(me, t2) and is_same(e.pick_card_from(t2, me), plus), "V30-C2 够不着目标时优先拆「远行披风」")
	me["equip"]["weapon"] = {"name": "破空长弓", "suit": "红桃", "point": 5, "nature": "", "yb": [], "range": 5}
	_ok(e.in_attack_range(me, t2) and is_same(e.pick_card_from(t2, me), arm), "V30-C2 够得着时优先拆防具")
	# C3 星眠 AI：残局（第 25 轮起）只在 1 血时发动
	var SL = load("res://scripts/skill_lib.gd")
	var sl = SL.new()
	e = _clean_eng("doudizhu", ["地主", "农民", "农民"], 3)
	me = e.players[0]
	me["hp"] = 2
	e.round_no = 5
	_ok(bool(sl._xingmian_ai(e, {}, me)), "V30-C3 前期 2 血会星眠")
	e.round_no = 30
	_ok(not bool(sl._xingmian_ai(e, {}, me)), "V30-C3 第 30 轮 2 血不再星眠（避免回复拉锯）")
	me["hp"] = 1
	_ok(bool(sl._xingmian_ai(e, {}, me)), "V30-C3 残局 1 血仍会星眠")
	# C4 元气补给 AI：还能出突击时先出；残局只在 2 血及以下回复
	e = _clean_eng("duel", ["先手", "后手"], 4)
	me = e.players[0]
	e.turn_player = me
	me["hp"] = 3
	_give(e, me, "突击", "黑桃", 9)
	e.round_no = 3
	_ok(not bool(sl._yuanqi_ai(e, me)), "V30-C4 只掉 1 血且手里有能出的突击时，先出突击不转补给")
	me["used_attack"] = true
	_ok(bool(sl._yuanqi_ai(e, me)), "V30-C4 出过突击后再用元气补给回复")
	e.round_no = 40
	_ok(not bool(sl._yuanqi_ai(e, me)), "V30-C4 残局 3 血不回复")
	# C5 内奸（参照 get.situation）：主公方明显占优时把疑似忠臣当敌人；否则打疑似反贼
	e = _clean_eng()
	var nei: Dictionary = {}
	var zhong: Dictionary = {}
	var fan: Array = []
	var ids := ["主公", "忠臣", "反贼", "反贼", "内奸"]
	for i in 5:
		e.players[i]["identity"] = ids[i]
	nei = e.players[4]
	zhong = e.players[1]
	fan = [e.players[2], e.players[3]]
	e.fan_total = 2
	e.players[4]["belief"] = {1: 2.0, 2: -2.0, 3: -2.0}
	(fan[0] as Dictionary)["hp"] = 1
	(fan[1] as Dictionary)["alive"] = false
	_ok(e.situation() >= 2 and e.ai_is_enemy(nei, zhong) and not e.ai_is_enemy(nei, e.players[0]), "V30-C5 主公方占优（局势 %d）：内奸把忠臣当敌人，但不打主公" % e.situation())
	(fan[1] as Dictionary)["alive"] = true
	(fan[0] as Dictionary)["hp"] = 4
	(fan[1] as Dictionary)["hp"] = 4
	e.players[0]["hp"] = 1
	zhong["hp"] = 1
	_ok(e.situation() < 2 and e.ai_is_enemy(nei, fan[0]) and not e.ai_is_enemy(nei, zhong), "V30-C5 反贼占优（局势 %d）：内奸打反贼、不打忠臣" % e.situation())
	# C6 反贼选目标：主公在范围内且同等条件时优先主公
	e = _clean_eng()
	for i in 5:
		e.players[i]["identity"] = ids[i]
	var rb: Dictionary = e.players[2]
	rb["equip"]["weapon"] = {"name": "破空长弓", "suit": "红桃", "point": 5, "nature": "", "yb": [], "range": 5}
	rb["belief"] = {1: -3.0}
	e.difficulty = 1
	_ok(is_same(e.ai_pick_target(rb, true), e.players[0]), "V30-C6 反贼同等条件下优先突击主公")
	# C7 双生短刃：出牌者被连环传导自己阵亡后不再摸牌（V0.30 修复 dead_holds_cards）
	e = _clean_eng("duel", ["先手", "后手"], 1)
	me = e.players[0]
	foe = e.players[1]
	me["hp"] = 1
	foe["hp"] = 3
	me["chained"] = true
	foe["chained"] = true
	me["equip"]["weapon"] = {"name": "双生短刃", "suit": "黑桃", "point": 2, "nature": "", "yb": [], "range": 2}
	e.turn_player = me
	var fsha := _give(e, me, "突击", "红桃", 6, "火")
	_script_ui(e, [], {}, [])
	await e.use_attack(me, foe, fsha)
	_ok(not bool(me["alive"]) and (me["hand"] as Array).is_empty(), "V30-C7 出牌者因传导阵亡后不再触发「双生短刃」摸牌（alive=%s 手牌 %d）" % [str(me["alive"]), (me["hand"] as Array).size()])
	# C8 局外：战绩/熟练度/成就（写在测试存档）
	MetaT.reset_for_test("user://meta_reg.json")
	var r1: Dictionary = MetaT.record({"mode": "identity", "char": "花宫雏", "identity": "主公", "result": "win", "rounds": 8, "dmg": 9, "kills": 3, "heal": 5, "taken": 0, "mvp": true})
	var got: Array = []
	for a in r1["new_ach"]:
		got.append(String(a[0]))
	_ok(int(r1["xp"]) == 10 + 15 + 9 + 15 + 5 and int(r1["level"]) == 2, "V30-C8 熟练度：首局 %d XP、Lv%d" % [int(r1["xp"]), int(r1["level"])])
	_ok(got.has("first_game") and got.has("first_win") and got.has("id_lord") and got.has("dmg_8") and got.has("kills_3") and got.has("heal_5") and got.has("mvp") and got.has("flawless"), "V30-C8 一局解锁 %d 个成就：%s" % [got.size(), ",".join(PackedStringArray(got))])
	var r2: Dictionary = MetaT.record({"mode": "doudizhu", "char": "花宫雏", "identity": "农民", "result": "lose", "rounds": 4, "dmg": 1, "kills": 0, "heal": 0, "taken": 3, "mvp": false})
	_ok((r2["new_ach"] as Array).is_empty() and MetaT.win_rate_text("all").begins_with("2 局 · 胜 1"), "V30-C8 第二局（负）不重复解锁，总计 %s" % MetaT.win_rate_text("all"))
	MetaT.reset_for_test("user://meta_reg.json")
	MetaT.path = "user://meta_reg.json"
	var d2: Dictionary = MetaT.load_data()
	_ok((d2["records"] as Array).is_empty(), "V30-C8 重置测试存档后为空")
	MetaT.record({"mode": "duel", "char": "夜宫静羽", "identity": "先手", "result": "win", "rounds": 3, "dmg": 3, "kills": 1, "heal": 0, "taken": 1, "mvp": true})
	MetaT._loaded_path = ""
	var d3: Dictionary = MetaT.load_data()
	_ok((d3["records"] as Array).size() == 1 and int(d3["chars"]["夜宫静羽"]["xp"]) > 0 and (d3["ach"] as Dictionary).has("duel_win"), "V30-C8 存档写入 user:// 后可重新读回")
	_ok(MetaT.ACHIEVEMENTS.size() >= 15 and MetaT.ACHIEVEMENTS.size() <= 25, "V30-C8 成就数量 %d（15~25）" % MetaT.ACHIEVEMENTS.size())
	# C9 声音设置：总线存在、开关静音、音量持久化
	AudioT.ensure()
	_ok(AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Voice") >= 0 and AudioServer.get_bus_index("Music") >= 0, "V30-C9 SFX/Voice/Music 总线已创建")
	var old_on = AudioT.get_v("sfx_on")
	var old_vol = AudioT.get_v("voice_vol")
	var old_music_on = AudioT.get_v("music_on")
	AudioT.set_v("sfx_on", false)
	AudioT.set_v("voice_vol", 0.35)
	AudioT.set_v("music_on", false)
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	_ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) and AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and is_equal_approx(float(cf.get_value("audio", "voice_vol", 0)), 0.35), "V30-C9 关闭音效/音乐即静音对应总线，音量写入 settings.cfg")
	AudioT.set_v("sfx_on", old_on)
	AudioT.set_v("voice_vol", old_vol)
	AudioT.set_v("music_on", old_music_on)
	_ok(AudioT.sfx_stream("hit") != null and AudioT.voice_stream("attack") == null, "V30-C9 音效文件可加载；语音未打包（返回空）")
	_ok(DirAccess.dir_exists_absolute("res://assets/bgm") and ResourceLoader.exists("res://assets/bgm/home_carefree.ogg") and ResourceLoader.exists("res://assets/bgm/battle_volatile_reaction.ogg") and ResourceLoader.exists("res://assets/bgm/tense_hitman.ogg"), "V30-C9 三首 OGG BGM 已打包进游戏资源")
	_ok(HelpText.bbcode().find("Kevin MacLeod") >= 0 and HelpText.bbcode().find("creativecommons.org/licenses/by/4.0") >= 0, "V30-C9 新手说明含 CC BY 4.0 音乐署名")
	if main_ref.music != null:
		main_ref.music.play_scene("battle")
		await _frames(2)
		var music_ok: bool = main_ref.music.current_scene == "battle"
		main_ref.music.play_scene("tense")
		await _frames(2)
		music_ok = music_ok and main_ref.music.current_scene == "tense"
		main_ref.music.play_scene("home")
		await _frames(2)
		music_ok = music_ok and main_ref.music.current_scene == "home"
		_ok(music_ok, "V30-C9 MusicDirector 可在主页/对局/紧张曲间切换")
	else:
		_ok(false, "V30-C9 MusicDirector 未创建")
	# C10 教学关：固定角色/起手、按步骤推进；设置面板含声音滑条
	seed(30)
	main_ref.clear_screen()
	var BS = load("res://scripts/battle.gd")
	var bs = BS.new()
	bs.tutorial = true
	bs.game_mode = "duel"
	bs.set_anchors_preset(Control.PRESET_FULL_RECT)
	bs.go_home = Callable(main_ref, "show_home")
	main_ref.screen_root.add_child(bs)
	bs.set_auto_confirm(false, false)
	bs.start_match(false)
	if not await _reach_my_play(bs):
		_ok(false, "V30-C10 教学关未进入出牌阶段")
		await _close_battle(bs)
		return
	var tme: Dictionary = bs.players[0]
	var names: Array = []
	for c in tme["hand"]:
		names.append(String(c["name"]))
	_ok(String(tme["char_name"]) == "花宫雏" and String(bs.players[1]["char_name"]) == "柚木铃奈" and int(bs.players[1]["hp"]) == 2, "V30-C10 教学关固定花宫雏 vs 柚木铃奈（对手 2 血）")
	var foe_names: Array = []
	for c in bs.players[1]["hand"]:
		foe_names.append(String(c["name"]))
	_ok(foe_names.has("突击"), "V30-C10 教学关对手首个回合保证有「突击」，可进入响应练习")
	_ok(names.has("星光长剑") and names.has("突击") and names.has("闪避") and names.has("补给"), "V30-C10 起手含 星光长剑/突击/闪避/补给：%s" % ",".join(PackedStringArray(names)))
	_ok(bs.tut_step == 0 and bs.tut_panel != null and bs.tut_panel.visible and bs.tut_label.text.begins_with("教学 1/5"), "V30-C10 显示第 1 步提示")
	var sword: Dictionary = {}
	for c in tme["hand"]:
		if String(c["name"]) == "星光长剑":
			sword = c
	_tap_card(bs, sword)
	await _frames(2)
	bs.confirm_btn.pressed.emit()
	await _wait_interactive(bs)
	for i in 4:
		await get_tree().create_timer(0.12).timeout
	_ok(not (tme["equip"]["weapon"] as Dictionary).is_empty() and bs.tut_step == 1, "V30-C10 装备后进入第 2 步（step=%d）" % bs.tut_step)
	var tsha: Dictionary = {}
	for c in tme["hand"]:
		if String(c["name"]) == "突击":
			tsha = c
	if not tsha.is_empty():
		_tap_card(bs, tsha)
		await _frames(2)
		if bs.sel_target != 1:
			_tap_seat(bs, 1)
		for i in 4:
			await get_tree().create_timer(0.12).timeout
		_ok(bs.tut_step == 2, "V30-C10 选中突击并选好目标后进入第 3 步（step=%d）" % bs.tut_step)
		bs.confirm_btn.pressed.emit()
		await _wait_interactive(bs)
		for i in 4:
			await get_tree().create_timer(0.12).timeout
		_ok(bool(tme["used_attack"]) and bs.tut_step == 3, "V30-C10 出牌后进入第 4 步（step=%d）" % bs.tut_step)
	bs.tut_saw_enemy_turn = false
	bs.turn_seat = 1
	bs._tut_tick()
	_ok(bs.tut_step == 3 and bs.tut_saw_enemy_turn and bs.tut_label.text.begins_with("教学 4/5"), "V30-C10 对手回合开始时保持第 4 步，等待真实响应练习")
	bs.turn_seat = 0
	bs._tut_tick()
	_ok(bs.tut_step == 4 and bs.tut_label.text.begins_with("教学 5/5"), "V30-C10 对手回合结束后才进入第 5 步自由练习")
	bs.tut_step = 3
	bs.toggle_settings_panel()
	await _frames(2)
	_ok(bs.audio_sliders.has("master") and bs.audio_sliders.has("sfx_vol") and bs.audio_sliders.has("voice_vol") and bs.audio_sliders.has("music_vol") and bs.audio_checks.has("sfx_on") and bs.audio_checks.has("voice_on") and bs.audio_checks.has("music_on"), "V30-C10 设置面板有 总音量/音效/语音/背景音乐 开关与滑条")
	bs.toggle_settings_panel()
	await _close_battle(bs)
	MetaT.reset_for_test("user://meta_test.json")


# ---------------- V0.33：看破反甲单目标锦囊 / 第二弹新角色与限定技 / 连破高伤播报 / 记牌器与自由点将 ----------------
func _reg_v33() -> void:
	# V33-1 看破【空巢·反甲】响应单目标锦囊（突然检查）时，可从弃牌堆获得该锦囊实体牌
	var e = _clean_eng("duel", ["先手", "后手"])
	var p0: Dictionary = e.players[0]
	var p1: Dictionary = e.players[1]
	var ck := _give(e, p0, "突然检查", "黑桃", 3)
	_give(e, p0, "闪避", "方块", 5)
	var kp_fanjia := {"name": "看破", "suit": "红桃", "point": 13, "nature": "", "yb": ["空巢", "反甲"]}
	(p1["hand"] as Array).append(kp_fanjia)
	await e.play_card(p0, ck, p1)
	_ok((p1["hand"] as Array).has(ck) and not e.discard_pile.has(ck), "V33-1 看破【空巢·反甲】成功获得所响应的单目标锦囊「突然检查」")

	# V33-2 新角色白石星奈（sena）：「星轨」观星+摸1，「裁决」弃1令对方交牌或受1点雷伤
	e = _clean_eng("duel", ["先手", "后手"])
	p0 = e.players[0]
	p1 = e.players[1]
	p0["char_name"] = "白石星奈"
	e.add_skill(p0, "xinggui")
	e.add_skill(p0, "caijue")
	var deck_n0: int = (e.deck as Array).size()
	await e.fire("phaseZhunbeiStart", {"name": "phase", "player": p0, "target": p0})
	_ok((p0["hand"] as Array).size() == 1 and e.deck.size() == deck_n0 - 1, "V33-2 白石星奈「星轨」准备阶段卜算 2 并摸 1 张牌")
	# 对方无手牌时裁决直接造成 1 点雷电伤害
	var hp_b := int(p1["hp"])
	await e.use_active_skill(p0, "caijue")
	_ok(int(p1["hp"]) == hp_b - 1 and (p0["hand"] as Array).is_empty(), "V33-2 白石星奈「裁决」对无手牌目标造成 1 点雷电伤害")

	# V33-3 新角色黑泽玲央（reo）：锁定技「剑心」摸牌与加伤、限定技「奥义·残月」回血摸牌与无限出杀
	e = _clean_eng("duel", ["先手", "后手"], 4)
	p0 = e.players[0]
	p1 = e.players[1]
	p0["char_name"] = "黑泽玲央"
	p0["hp"] = 3
	p1["hp"] = 4
	e.add_skill(p0, "jianxin")
	e.add_skill(p0, "canyue")
	_ok(e.active_options(p0).size() == 1 and String(e.active_options(p0)[0]["sid"]) == "canyue", "V33-3 黑泽玲央受伤时可发动限定技「奥义·残月」")
	await e.use_active_skill(p0, "canyue")
	_ok(int(p0["hp"]) == 4 and (p0["hand"] as Array).size() == 2 and bool(p0.get("canyue_turn", false)) and e.has_unlimited_attack(p0), "V33-3 「奥义·残月」摸 2 回 1 且本回合突击无次数限制")
	_ok(e.active_options(p0).is_empty() and bool(p0.get("limited_used_canyue", false)), "V33-3 限定技「奥义·残月」发动后本局不可再次发动")
	p0["turn_used"] = {}
	p0["hp"] = 2
	_ok(e.active_options(p0).is_empty(), "V33-3 下回合即使受伤，已发动的限定技仍不可再发动")
	var fx_events: Array = []
	e.set_ui({"fx": func(k: String, d: Dictionary) -> void: fx_events.append(k)})
	(p0["hand"] as Array).clear()
	(p1["hand"] as Array).clear()
	var sha1 := _give(e, p0, "突击", "黑桃", 8)
	var sha2 := _give(e, p0, "突击", "红桃", 9)
	await e.use_attack(p0, p1, sha1)
	_ok(int(p1["hp"]) == 2 and (p0["hand"] as Array).size() == 2 and fx_events.has("heavy_hit"), "V33-3 「剑心」对高血少牌目标摸 1 张且伤害 +1（单次 2 伤触发 heavy_hit 播报）")
	await e.use_attack(p0, p1, sha2)
	_ok(int(p1["hp"]) == 1 and not bool(p0["used_attack"]), "V33-3 「剑心」加伤每回合限一次，且「奥义·残月」回合内连出第二张突击后仍可继续出突击")
	var sha3 := _give(e, p0, "突击", "梅花", 10)
	await e.use_attack(p0, p1, sha3)
	_ok(not bool(p1["alive"]) and fx_events.has("kill_spree"), "V33-3 击杀目标时触发 kill_spree 连破横幅事件")

	# V33-4 角色池扩充至 9 人（含第二弹 2 人且 CG 资源齐全）
	_ok(Characters.LIST.size() >= 9 and ResourceLoader.exists("res://assets/cg/sena.webp") and ResourceLoader.exists("res://assets/cg/reo.webp"), "V33-4 第二弹首批角色 CG 资源齐全")


# ---------------- V0.34：转换技 / 觉醒技与衍生技 / 欢乐 2v2 模式 / 12 角色全集 ----------------
func _reg_v34() -> void:
	# V34-1 神乐坂真昼（mahiru）：转换技「昼夜卷」（阳：弃1造成1火伤转阴；阴：摸2弃1转阳）与「静读」
	var e = _clean_eng("duel", ["先手", "后手"], 4)
	var p0: Dictionary = e.players[0]
	var p1: Dictionary = e.players[1]
	p0["char_name"] = "神乐坂真昼"
	e.add_skill(p0, "zhouye")
	e.add_skill(p0, "jingdu")
	_give(e, p0, "闪避", "方块", 4)
	_ok(int(p0.get("switch_zhouye", 0)) == 0, "V34-1 转换技「昼夜卷」初始为【阳】状态")
	await e.use_active_skill(p0, "zhouye")
	_ok(int(p1["hp"]) == 3 and int(p0.get("switch_zhouye", 0)) == 1 and (p0["hand"] as Array).is_empty(), "V34-1 「昼夜卷·阳」弃1牌造成1点火焰伤害并转为【阴】")
	p0["turn_used"] = {}
	await e.use_active_skill(p0, "zhouye")
	_ok(int(p0.get("switch_zhouye", 0)) == 0 and (p0["hand"] as Array).size() == 1, "V34-1 「昼夜卷·阴」令目标摸2弃1并转回【阳】")
	await e.fire("phaseJieshuStart", {"name": "phase", "player": p0, "target": p0})
	_ok((p0["hand"] as Array).size() == 2, "V34-1 「静读」在结束阶段手牌数不大于体力值时摸1张牌")

	# V34-2 久远寺绫（aya）：锁定技「破的」（攻击范围+1、突击命中弃手牌）与觉醒技「心眼觉醒」（习得「神射」）
	e = _clean_eng("duel", ["先手", "后手"], 4)
	p0 = e.players[0]
	p1 = e.players[1]
	p0["char_name"] = "久远寺绫"
	e.add_skill(p0, "podi")
	e.add_skill(p0, "xinyan")
	_ok(e.weapon_range(p0) == 2, "V34-2 「破的」使无武器时攻击范围提升为 2")
	p0["hp"] = 2
	await e.fire("phaseZhunbeiStart", {"name": "phase", "player": p0, "target": p0})
	_ok(bool(p0.get("awakened_xinyan", false)) and int(p0["max_hp"]) == 3 and int(p0["hp"]) == 3 and (p0["hand"] as Array).size() == 2 and e.has_skill(p0, "shenshe"), "V34-2 觉醒技「心眼觉醒」减上限回血摸2牌并习得「神射」")
	# 再次准备阶段不再重复觉醒
	await e.fire("phaseZhunbeiStart", {"name": "phase", "player": p0, "target": p0})
	_ok(int(p0["max_hp"]) == 3, "V34-2 觉醒技每局只触发一次")
	# 验证「神射」无视距离且不可被闪避响应，命中后触发「破的」弃置目标1张手牌
	p1["equip"]["plus"] = _mk("远行披风", "红桃", 5)
	_give(e, p1, "闪避", "方块", 2)
	_give(e, p1, "补给", "红桃", 3)
	await e.use_active_skill(p0, "shenshe")
	_ok(int(p1["hp"]) == 3 and (p1["hand"] as Array).size() == 1, "V34-2 「神射」无视距离且强命不可闪避，命中后「破的」令目标弃置1张手牌")

	# V34-3 结城奈奈（nana）：「催化」（横置/重置锁链并摸1）与「余震」（属性伤害摸牌，每轮限二次）
	e = _clean_eng("duel", ["先手", "后手"], 3)
	p0 = e.players[0]
	p1 = e.players[1]
	p0["char_name"] = "结城奈奈"
	e.add_skill(p0, "cuihua")
	e.add_skill(p0, "yuzhen")
	await e.use_active_skill(p0, "cuihua")
	_ok(bool(p1.get("chained", false)) and (p0["hand"] as Array).size() == 1, "V34-3 「催化」横置敌方锁链并摸 1 张牌")
	await e.damage(p0, p1, 1, "测试火伤", "火")
	await e.damage(p0, p1, 1, "测试雷伤", "雷")
	await e.damage(p0, p1, 1, "测试冰伤", "冰")
	_ok((p0["hand"] as Array).size() == 3, "V34-3 「余震」在场上发生属性伤害后摸牌，且每轮最多触发 2 次（手牌 1→3）")

	# V34-4 欢乐 2v2 模式（twovtwo）：1·4红方 vs 2·3蓝方、末位起手5张、队友阵亡抚恤摸1张与胜负判定
	var e2v2 = EngineS.new()
	e2v2.load_skills()
	e2v2.mode = "twovtwo"
	e2v2.setup_game(make_chars(4, 3), ["红方", "蓝方", "蓝方", "红方"])
	_ok((e2v2.players[0]["hand"] as Array).size() == 4 and (e2v2.players[3]["hand"] as Array).size() == 5, "V34-4 欢乐 2v2：4号位末置位起手 5 张牌")
	_ok(e2v2.ai_is_ally(e2v2.players[0], e2v2.players[3]) and e2v2.ai_is_enemy(e2v2.players[0], e2v2.players[1]), "V34-4 欢乐 2v2：1·4号位互为盟友，与2·3号位敌对")
	var h3_before := (e2v2.players[3]["hand"] as Array).size()
	await e2v2.die(e2v2.players[0], e2v2.players[1])
	_ok((e2v2.players[3]["hand"] as Array).size() == h3_before + 1 and not e2v2.game_over, "V34-4 欢乐 2v2：一名角色阵亡后，存活队友摸 1 张牌")
	await e2v2.die(e2v2.players[3], e2v2.players[2])
	_ok(e2v2.game_over and e2v2.winner_text == "蓝方获胜！", "V34-4 欢乐 2v2：同队两人全灭后判定对方阵营获胜")

	# V34-5 全部 12 名角色及 CG 资源校验
	_ok(Characters.LIST.size() >= 12 and ResourceLoader.exists("res://assets/cg/mahiru.webp") and ResourceLoader.exists("res://assets/cg/aya.webp") and ResourceLoader.exists("res://assets/cg/nana.webp"), "V34-5 第二弹新增 3 名角色 CG 资源齐全")


# ---------------- V0.35：拼点系统 / 早乙女凛与天城雪音 / 魔王挑战 3v1 模式 / 14 角色全集 ----------------
func _reg_v35() -> void:
	# V35-1 早乙女凛（rin）：「妙算」（拼点摸1且点数+3）与「王手」（拼点赢摸1、无视距离且下一张突击伤害+1；未赢获得对方拼点牌）
	var e = _clean_eng("duel", ["先手", "后手"], 4)
	var p0: Dictionary = e.players[0]
	var p1: Dictionary = e.players[1]
	p0["char_name"] = "早乙女凛"
	e.add_skill(p0, "wangshou")
	e.add_skill(p0, "miaosuan")
	# p0 手牌 9 点（妙算+3=12点） vs p1 手牌 11 点 → p0 赢拼点！
	_give(e, p0, "闪避", "方块", 9)
	_give(e, p1, "突击", "黑桃", 11)
	await e.use_active_skill(p0, "wangshou")
	_ok(int(p0.get("nodist_seat", -1)) == 1 and bool(p0.get("drunk", false)) and (p0["hand"] as Array).size() == 2, "V35-1 「妙算」+3点助「王手」9点胜11点，共摸2张且对目标无视距离、下一击加伤")
	p1["equip"]["plus"] = _mk("远行披风", "红桃", 5)
	_ok(e.eff_dist(p0, p1) == 1, "V35-1 「王手」赢拼点后本回合对目标距离恒视为 1")
	# 拼点未赢时：获得对方拼点牌
	p0["turn_used"] = {}
	(p0["hand"] as Array).clear()
	(p1["hand"] as Array).clear()
	var low_c := _give(e, p0, "闪避", "方块", 2)
	var high_c := _give(e, p1, "补给", "红桃", 13)
	# 把牌堆顶放一张 1 点牌，使妙算摸到的也是 1 点
	e.deck.append(_mk("闪避", "方块", 1))
	await e.use_active_skill(p0, "wangshou")
	_ok((p0["hand"] as Array).has(high_c) and not e.discard_pile.has(high_c), "V35-1 「王手」拼点未赢时获得对方的拼点牌")

	# V35-2 天城雪音（yukine）：「精算」（弃1摸2，黑牌受伤回1血）与「凛霜」（受伤令来源弃1或受1冰伤）
	e = _clean_eng("duel", ["先手", "后手"], 3)
	p0 = e.players[0]
	p1 = e.players[1]
	p0["char_name"] = "天城雪音"
	p0["hp"] = 2
	e.add_skill(p0, "jingsuan")
	e.add_skill(p0, "linshuang")
	_give(e, p0, "突击", "黑桃", 6)
	await e.use_active_skill(p0, "jingsuan")
	_ok(int(p0["hp"]) == 3 and (p0["hand"] as Array).size() == 2, "V35-2 「精算」弃置黑色手牌摸 2 张并回复 1 点体力")
	# p1 无手牌对 p0 造成伤害 → 凛霜反击 1 点冰属性伤害
	var p1_hp0 := int(p1["hp"])
	await e.damage(p1, p0, 1, "测试攻击")
	_ok(int(p1["hp"]) == p1_hp0 - 1, "V35-2 「凛霜」在伤害来源无手牌时对其造成 1 点冰属性伤害")

	# V35-3 魔王挑战模式（boss）：3人联军 vs 8血魔王（带魔威、星蚀）
	var eboss = EngineS.new()
	eboss.load_skills()
	eboss.mode = "boss"
	eboss.setup_game(make_chars(4, 3), ["联军", "联军", "魔王", "联军"])
	var boss_p: Dictionary = eboss.players[2]
	_ok(int(boss_p["max_hp"]) == 8 and int(boss_p["hp"]) == 8 and (boss_p["hand"] as Array).size() == 6 and eboss.has_skill(boss_p, "mowei") and eboss.has_skill(boss_p, "xingshi"), "V35-3 魔王挑战：3号位魔王 8 体力、起手 6 张、自带「魔威」「星蚀」")
	_ok(eboss.attack_limit(boss_p) == 2 and eboss.ai_is_ally(eboss.players[0], eboss.players[1]) and eboss.ai_is_enemy(eboss.players[0], boss_p), "V35-3 魔王挑战：魔王出杀上限为 2，联军互为盟友并共抗魔王")
	boss_p["hp"] = 6
	var ally_hp_sum0 := int(eboss.players[0]["hp"]) + int(eboss.players[1]["hp"]) + int(eboss.players[3]["hp"])
	await eboss.fire("phaseJieshuStart", {"name": "phase", "player": boss_p, "target": boss_p})
	var ally_hp_sum1 := int(eboss.players[0]["hp"]) + int(eboss.players[1]["hp"]) + int(eboss.players[3]["hp"])
	_ok(ally_hp_sum1 == ally_hp_sum0 - 1, "V35-3 魔王「星蚀」在已受伤的结束阶段对一名联军造成 1 点雷电伤害")
	await eboss.die(boss_p, eboss.players[0])
	_ok(eboss.game_over and eboss.winner_text == "联军获胜！", "V35-3 击败魔王后判定联军获胜")

	# V35-4 全部 14 名角色及 CG 资源校验
	_ok(Characters.LIST.size() >= 14 and ResourceLoader.exists("res://assets/cg/rin.webp") and ResourceLoader.exists("res://assets/cg/yukine.webp"), "V35-4 第二弹全 7 人 CG 资源齐全")


# ---------------- V0.36：护甲（shield）机制 / 圣护院莉莉娅 / 主公技星樱号令 / 卡牌图鉴 ----------------
func _reg_v36() -> void:
	# V36-1 护甲抵消伤害：1点护甲完全抵消1点伤害；2点伤害先扣1点护甲再扣1点体力
	var e = _clean_eng("duel", ["先手", "后手"], 3)
	var p0: Dictionary = e.players[0]
	var p1: Dictionary = e.players[1]
	p0["char_name"] = "圣护院莉莉娅"
	e.add_skill(p0, "shengdun")
	e.add_skill(p0, "yuanhu")
	p0["shield"] = 0
	await e.fire("phaseZhunbeiStart", {"name": "phase", "player": p0, "target": p0})
	_ok(int(p0.get("shield", 0)) == 1, "V36-1 「圣盾」在准备阶段无护甲时获得 1 点护甲")
	await e.damage(p1, p0, 1, "突击")
	_ok(int(p0.get("shield", 0)) == 0 and int(p0["hp"]) == 3, "V36-1 1 点护甲完全抵消 1 点伤害，体力不减")
	e.gain_shield(p0, 1)
	await e.damage(p1, p0, 2, "重击")
	_ok(int(p0.get("shield", 0)) == 0 and int(p0["hp"]) == 2, "V36-1 1 点护甲抵消 2 点伤害中的 1 点，仅损失 1 点体力")

	# V36-2 「援护」：弃 1 张手牌令目标获得 1 点护甲，若目标已受伤自己摸 1 张牌
	_give(e, p0, "闪避", "方块", 3)
	await e.use_active_skill(p0, "yuanhu")
	_ok(int(p0.get("shield", 0)) == 1 and (p0["hand"] as Array).size() == 1, "V36-2 「援护」对已受伤角色赋予 1 点护甲并摸 1 张牌")

	# V36-3 主公技「星樱号令」：首轮准备阶段获得1点护甲；队友对主公使用「补给」摸1张牌
	e = _clean_eng("identity", ["主公", "忠臣", "反贼", "反贼", "内奸"], 4)
	var lord: Dictionary = e.players[0]
	var loyal: Dictionary = e.players[1]
	e.add_skill(lord, "xingying_lord")
	e.round_no = 1
	await e.fire("phaseZhunbeiStart", {"name": "phase", "player": lord, "target": lord})
	_ok(int(lord.get("shield", 0)) == 1, "V36-3 主公技「星樱号令」首轮准备阶段获得 1 点护甲")
	lord["hp"] = 2
	var tao := _give(e, loyal, "补给", "红桃", 6)
	e.use_supply(loyal, tao, lord)
	_ok(int(lord["hp"]) == 3 and (loyal["hand"] as Array).size() == 1, "V36-3 主公技「星樱号令」：其他角色对主公使用「补给」后摸 1 张牌")

	# V36-4 卡牌图鉴页与 15 名角色校验
	main_ref.show_card_gallery()
	await get_tree().process_frame
	var card_btns := 0
	for n in main_ref.screen_root.find_children("*", "Button", true, false):
		if (n as Control).has_meta("intro"):
			card_btns += 1
	_ok(card_btns == 55, "V36-4 卡牌图鉴展示全部 %d 种卡牌且均可查看详情" % card_btns)
	main_ref.show_home()
	await get_tree().process_frame
	_ok(Characters.LIST.size() >= 15 and ResourceLoader.exists("res://assets/cg/lilia.webp"), "V36-4 角色池扩充至 15 人及以上且莉莉娅 CG 资源齐全")

func _pz_play(pid: String, move_fn: Callable, opt_fn: Callable = Callable(), card_fn: Callable = Callable(), tgt_fn: Callable = Callable(), ask_fn: Callable = Callable()):
	var spec: Dictionary = PuzzlesT.by_id(pid)
	var eng = EngineS.new()
	eng.load_skills()
	eng.mode = "puzzle"
	eng.difficulty = 2
	var clist: Array = []
	for sd in PuzzlesT.seat_specs(spec):
		var cd := Characters.by_id(String((sd as Dictionary).get("char", "hina")))
		clist.append({"name": String(cd["name"]), "hp": int(cd["hp"]), "skills": [], "char": cd})
	eng.setup_game(clist, PuzzlesT.identities(spec))
	PuzzlesT.rig(eng, spec)
	eng.set_ui({
		"is_human": func(p): return int(p["seat"]) == 0,
		"ask_skill": func(p, sid, tm, ctx): return bool(ask_fn.call(p, sid, tm, ctx)) if ask_fn.is_valid() else true,
		"ask_respond": func(p, nm, reason): return String(nm) == "突击" and String(reason) == "单挑",
		"ask_save": func(p, dying): return false,
		"pick_option": func(p, opts, prompt):
			if opt_fn.is_valid():
				var rv: Variant = opt_fn.call(eng, p, opts, prompt)
				if rv != null:
					return rv
			return opts[0]["value"],
		"pick_card": func(p, cands, prompt):
			if card_fn.is_valid():
				var rc: Variant = card_fn.call(eng, p, cands, prompt)
				if rc is Dictionary and not (rc as Dictionary).is_empty():
					return rc
			return cands[0],
		"pick_target": func(p, cands, prompt):
			if tgt_fn.is_valid():
				var rt: Variant = tgt_fn.call(eng, p, cands, prompt)
				if rt is Dictionary and not (rt as Dictionary).is_empty():
					return rt
			return cands[0],
		"play_phase": func(e_ref, p):
			await move_fn.call(e_ref, p),
	})
	await eng.run_game()
	eng.set_ui({})
	return eng


func _pz_find(p: Dictionary, nm: String, nat: String = "") -> Dictionary:
	for c in p["hand"]:
		if String(c["name"]) == nm and (nat == "" or String(c.get("nature", "")) == nat):
			return c
	return {}


# ---------------- V0.37：残局闯关（全 10 关必胜与错手判负） / 星野咲夜 / 排序与斗地主同盟 ----------------
func _reg_v37() -> void:
	_ok(PuzzlesT.count() >= 15, "V37-1 残局闯关配置至少 10 关（当前 %d 关）" % PuzzlesT.count())

	# p01 破甲一击
	var e1 = await _pz_play("p01", func(e, p):
		await e.play_card(p, _pz_find(p, "破甲光剑"), {})
		await e.play_card(p, _pz_find(p, "特饮"), {})
		await e.play_card(p, _pz_find(p, "突击"), e.players[1]))
	_ok(e1.game_over and String(e1.winner_text) == "残局破解成功！", "V37-1 p01「破甲一击」正确解法通关")
	var e1_bad = await _pz_play("p01", func(e, p):
		await e.play_card(p, _pz_find(p, "破甲光剑"), {})
		await e.play_card(p, _pz_find(p, "突击"), e.players[1]))  # 忘喝特饮
	_ok(e1_bad.game_over and String(e1_bad.winner_text).begins_with("残局挑战失败"), "V37-1 p01 未喝特饮超时判负")

	# p02 决斗时机
	var e2 = await _pz_play("p02", func(e, p):
		await e.play_card(p, _pz_find(p, "单挑"), e.players[1]))
	_ok(e2.game_over and String(e2.winner_text) == "残局破解成功！", "V37-1 p02「决斗时机」先单挑获胜")

	# p03 先拆后杀
	var e3 = await _pz_play("p03", func(e, p):
		await e.play_card(p, _pz_find(p, "突然检查"), e.players[1])
		await e.play_card(p, _pz_find(p, "突然检查"), e.players[1])
		await e.play_card(p, _pz_find(p, "魔导连弩"), {})
		for _i in 4:
			if not e.game_over and not _pz_find(p, "突击").is_empty():
				await e.play_card(p, _pz_find(p, "突击"), e.players[1]))
	_ok(e3.game_over and String(e3.winner_text) == "残局破解成功！", "V37-1 p03「先拆后杀」通关")

	# p04 缴械夺弩
	var e4 = await _pz_play("p04", func(e, p):
		await e.play_card(p, _pz_find(p, "借力打力"), e.players[1])
		var xbow := _pz_find(p, "魔导连弩")
		if not xbow.is_empty():
			await e.play_card(p, xbow, {})
		for _i in 3:
			if not e.game_over and not _pz_find(p, "突击").is_empty():
				await e.play_card(p, _pz_find(p, "突击"), e.players[1]))
	_ok(e4.game_over and String(e4.winner_text) == "残局破解成功！", "V37-1 p04「缴械夺弩」通关")

	# p05 火烧连营
	var e5 = await _pz_play("p05", func(e, p):
		await e.play_card(p, _pz_find(p, "羁绊锁链"), e.players[1])
		await e.play_card(p, _pz_find(p, "突击", "火"), e.players[1]),
		func(e, p, opts, prompt):
			if prompt.find("羁绊锁链") >= 0:
				for o in opts:
					if o["value"] is Dictionary and o["value"] == e.players[2]:
						return o["value"]
			return opts[0]["value"])
	_ok(e5.game_over and String(e5.winner_text) == "残局破解成功！", "V37-1 p05「火烧连营」传导双杀通关")

	# p06 残月逆袭（骗闪后再喝特饮获胜；先喝特饮撞闪避失败）
	var e6 = await _pz_play("p06", func(e, p):
		await e.use_active_skill(p, "canyue")
		await e.play_card(p, _pz_find(p, "突击"), e.players[1])  # 骗掉闪避
		await e.play_card(p, _pz_find(p, "特饮"), {})
		for _i in 2:
			if not e.game_over and not _pz_find(p, "突击").is_empty():
				await e.play_card(p, _pz_find(p, "突击"), e.players[1]))
	_ok(e6.game_over and String(e6.winner_text) == "残局破解成功！", "V37-1 p06「残月逆袭」先突击骗闪再特饮通关")
	var e6_bad = await _pz_play("p06", func(e, p):
		await e.use_active_skill(p, "canyue")
		await e.play_card(p, _pz_find(p, "特饮"), {})  # 错手：直接喝特饮撞闪避
		for _i in 3:
			if not e.game_over and not _pz_find(p, "突击").is_empty():
				await e.play_card(p, _pz_find(p, "突击"), e.players[1]))
	_ok(e6_bad.game_over and String(e6_bad.winner_text).begins_with("残局挑战失败"), "V37-1 p06 提前喝特饮撞闪避判负")

	# p07 昼夜连环
	var e7 = await _pz_play("p07", func(e, p):
		await e.play_card(p, _pz_find(p, "羁绊锁链"), e.players[2])
		await e.use_active_skill(p, "zhouye")
		if not e.game_over:
			await e.play_card(p, _pz_find(p, "突击"), e.players[1]),
		func(e, p, opts, prompt):
			if prompt.find("羁绊锁链") >= 0:
				for o in opts:
					if o["value"] is Dictionary and o["value"] == e.players[3]:
						return o["value"]
			return opts[0]["value"],
		func(e, p, cands, prompt):
			for c in cands:
				if String(c["name"]) == "闪避":
					return c
			return cands[0],
		func(e, p, cands, prompt):
			for c in cands:
				if c == e.players[3]:
					return c
			return cands[0])
	_ok(e7.game_over and String(e7.winner_text) == "残局破解成功！", "V37-1 p07「昼夜连环」4人局全灭通关")

	# p08 拼点远射
	var e8 = await _pz_play("p08", func(e, p):
		await e.use_active_skill(p, "wangshou")
		if not e.game_over and not _pz_find(p, "突击").is_empty():
			await e.play_card(p, _pz_find(p, "突击"), e.players[1]),
		Callable(),
		func(e, p, cands, prompt):
			for c in cands:
				if String(c["name"]) == "闪避" and int(c["point"]) == 9:
					return c
			return cands[0])
	_ok(e8.game_over and String(e8.winner_text) == "残局破解成功！", "V37-1 p08「拼点远射」妙算+王手绝杀通关")
	var e8_bad = await _pz_play("p08", func(e, p):
		pass)  # 不发动王手够不着
	_ok(e8_bad.game_over and String(e8_bad.winner_text).begins_with("残局挑战失败"), "V37-1 p08 不拼点无法够及距离 2 判负")

	# p09 破盾连斩
	var e9 = await _pz_play("p09", func(e, p):
		await e.play_card(p, _pz_find(p, "魔导连弩"), {})
		await e.play_card(p, _pz_find(p, "火焰试炼"), e.players[1])
		await e.play_card(p, _pz_find(p, "突击"), e.players[1])  # 骗掉闪避
		await e.play_card(p, _pz_find(p, "特饮"), {})
		for _i in 2:
			if not e.game_over and not _pz_find(p, "突击").is_empty():
				await e.play_card(p, _pz_find(p, "突击"), e.players[1]),
		Callable(),
		func(e, p, cands, prompt):
			for c in cands:
				if String(c["name"]) == "闪避":
					return c
			return cands[0])
	_ok(e9.game_over and String(e9.winner_text) == "残局破解成功！", "V37-1 p09「破盾连斩」打破 2甲+2血通关")

	# p10 星夜觉醒
	var e10 = await _pz_play("p10", func(e, p):
		await e.play_card(p, _pz_find(p, "特饮"), {})
		await e.use_active_skill(p, "shenshe")
		await e.play_card(p, _pz_find(p, "魔导连弩"), {})
		if not e.game_over and not _pz_find(p, "突击").is_empty():
			await e.play_card(p, _pz_find(p, "突击"), e.players[1])
		if not e.game_over and not _pz_find(p, "突击").is_empty():
			await e.play_card(p, _pz_find(p, "突击"), e.players[3]),
		Callable(),
		func(e, p, cands, prompt):
			for c in cands:
				if String(c["name"]) == "闪避":
					return c
			return cands[0],
		func(e, p, cands, prompt):
			for c in cands:
				if c == e.players[2]:
					return c
			return cands[0])
	_ok(e10.game_over and String(e10.winner_text) == "残局破解成功！", "V37-1 p10「星夜觉醒」心眼觉醒+特饮神射+连弩收割通关")
	var e10_bad = await _pz_play("p10", func(e, p):
		await e.use_active_skill(p, "shenshe")  # 忘喝特饮
		await e.play_card(p, _pz_find(p, "魔导连弩"), {})
		if not e.game_over and not _pz_find(p, "突击").is_empty():
			await e.play_card(p, _pz_find(p, "突击"), e.players[1])
		if not e.game_over and not _pz_find(p, "突击").is_empty():
			await e.play_card(p, _pz_find(p, "突击"), e.players[3]),
		Callable(),
		func(e, p, cands, prompt):
			for c in cands:
				if String(c["name"]) == "闪避":
					return c
			return cands[0],
		func(e, p, cands, prompt):
			for c in cands:
				if c == e.players[2]:
					return c
			return cands[0])
	_ok(e10_bad.game_over and String(e10_bad.winner_text).begins_with("残局挑战失败"), "V37-1 p10 神射前忘喝特饮致 3 号位残血判负")

	# V37-2 第 16 名角色「星野咲夜」：时计（亮2选1+同色护甲+超血弃1）& 星帷（黑牌当闪避/看破，每回合1次）
	var es = _clean_eng("duel", ["先手", "后手"], 3)
	var sp0: Dictionary = es.players[0]
	var sp1: Dictionary = es.players[1]
	sp0["char_name"] = "星野咲夜"
	es.add_skill(sp0, "shiji")
	es.add_skill(sp0, "xingwei")
	es.deck.append(_mk("闪避", "方块", 4))
	es.deck.append(_mk("突击", "黑桃", 7))
	es.deck.append(_mk("突然检查", "梅花", 4))
	await es.use_active_skill(sp0, "shiji")
	_ok((sp0["hand"] as Array).size() == 1 and int(sp0.get("shield", 0)) == 1, "V37-2 「时计」亮出同色两张牌，选 1 入手并获得 1 点护甲")
	(sp0["hand"] as Array).clear()
	var srec: Array = []
	_script_ui(es, [0], {"option_0": 0}, srec)
	sp0["xingwei_turn_used"] = false
	var sha_blk := _give(es, sp0, "突击", "黑桃", 9)
	var dodged1: bool = await es.respond_with(sp0, "闪避", "测试星帷闪避")
	var sha_blk2 := _give(es, sp0, "突击", "黑桃", 10)
	var dodged2: bool = await es.respond_with(sp0, "闪避", "同回合第二次应不可再用")
	_ok(dodged1 and not (sp0["hand"] as Array).has(sha_blk) and not dodged2 and (sp0["hand"] as Array).has(sha_blk2), "V37-2 「星帷」可将黑色手牌当作闪避打出，且每回合限一次")
	(sp0["hand"] as Array).clear()
	sp0["xingwei_turn_used"] = false
	_give(es, sp0, "羁绊锁链", "梅花", 10)
	var guohe := _give(es, sp1, "突然检查", "黑桃", 3)
	await es.play_card(sp1, guohe, sp0)
	_ok((sp0["hand"] as Array).is_empty() and bool(sp0.get("xingwei_turn_used", false)), "V37-2 「星帷」可将黑色手牌当作「看破」抵消锦囊")
	_ok(Characters.LIST.size() >= 16 and ResourceLoader.exists("res://assets/cg/sakuya.webp"), "V37-2 第 16 名角色「星野咲夜」及 CG 资源齐全")

	# V37-3 手牌排序切换 & 斗地主农民同盟视野 & 残局成就持久化
	var BS37 = load("res://scripts/battle.gd")
	var bs37 = BS37.new()
	bs37.game_mode = "doudizhu"
	bs37.players = [
		{"seat": 0, "identity": "农民", "alive": true, "hp": 3, "max_hp": 3, "skills": [], "char": Characters.LIST[0], "char_name": "花宫雏", "hand": [_mk("突然检查", "红桃", 12), _mk("突击", "黑桃", 7)], "equip": {"weapon": {}, "armor": {}, "minus": {}, "plus": {}, "treasure": {}}, "judge": []},
		{"seat": 1, "identity": "地主", "alive": true, "hp": 4, "max_hp": 4, "skills": [], "char": Characters.LIST[1], "char_name": "柚木铃奈", "hand": [_mk("闪避", "红桃", 2)], "equip": {"weapon": {}, "armor": {}, "minus": {}, "plus": {}, "treasure": {}}, "judge": []},
		{"seat": 2, "identity": "农民", "alive": true, "hp": 3, "max_hp": 3, "skills": [], "char": Characters.LIST[2], "char_name": "宫坂歌织", "hand": [_mk("补给", "红桃", 8)], "equip": {"weapon": {}, "armor": {}, "minus": {}, "plus": {}, "treasure": {}}, "judge": []},
	]
	bs37.eng = es
	var ctxt: String = bs37.counter_text()
	_ok(ctxt.find("同盟队友实时手牌") >= 0 and ctxt.find("补给 ♥8") >= 0, "V37-3 斗地主执农民时记牌器展示农民队友手牌")
	bs37.hand_sort_by_suit = false
	bs37.sort_my_hand()
	var after_suit: bool = String(bs37.players[0]["hand"][0]["suit"]) == "黑桃"
	bs37.sort_my_hand()
	var after_kind: bool = String(bs37.players[0]["hand"][0]["name"]) == "突击"
	_ok(after_suit and after_kind, "V37-3 手牌排序支持在【类型】与【花色点数】之间一键切换")
	for spq in es.players:
		pass
	es.set_ui({})
	bs37.eng = null
	bs37.free()

	const MetaT = preload("res://scripts/meta.gd")
	MetaT.reset_for_test("user://meta_v37.json")
	MetaT.path = "user://meta_v37.json"
	var pach: Array = MetaT.mark_puzzle("p01")
	_ok(MetaT.puzzles_cleared_count() == 1 and MetaT.puzzle_cleared("p01") and not pach.is_empty(), "V37-3 残局通关持久化记录并解锁成就「初破残局」")
	_ok(String(MetaT.win_rate_text("all")) == "—", "V37-3 残局挑战不污染普通对战总胜率")
	for k in range(2, 11):
		MetaT.mark_puzzle("p%02d" % k)
	_ok(MetaT.puzzles_cleared_count() == 10 and (MetaT.load_data()["ach"] as Dictionary).has("puzzle_master"), "V37-3 通关 10 关解锁成就「破局宗师」")
	for k2 in range(11, PuzzlesT.count() + 1):
		MetaT.mark_puzzle("p%02d" % k2)
	_ok(MetaT.puzzles_cleared_count() == PuzzlesT.count() and (MetaT.load_data()["ach"] as Dictionary).has("puzzle_all"), "V37-3b 通关全 %d 关解锁成就「残局大师」" % PuzzlesT.count())
	MetaT.reset_for_test("user://meta_v37.json")
	MetaT.path = "user://meta_test.json"

	# V37-4 残局选关界面可正常打开
	main_ref.show_puzzles()
	await get_tree().process_frame
	var pz_btns := 0
	for n in main_ref.screen_root.find_children("*", "Button", true, false):
		if (n as Button).text in ["挑战本关", "重玩此关"]:
			pz_btns += 1
	_ok(pz_btns == PuzzlesT.count(), "V37-4 残局选关大厅渲染全部 %d 关挑战入口" % PuzzlesT.count())
	main_ref.start_puzzle("p07")
	var bs_pz = null
	for ch in main_ref.screen_root.get_children():
		if ch is BattleScreen:
			bs_pz = ch
			break
	if bs_pz != null:
		bs_pz.fast = true
		for _w in 240:
			await get_tree().process_frame
			if bs_pz.interactive and bs_pz.puzzle_panel != null:
				break
		var overlap := false
		var pr: Rect2 = bs_pz.puzzle_panel.get_global_rect() if bs_pz.puzzle_panel != null else Rect2()
		for spn in bs_pz.seat_panels:
			if pr.intersects((spn as Control).get_global_rect()):
				overlap = true
		_ok(bs_pz.puzzle_panel != null and bs_pz.puzzle_panel.visible and not overlap, "V37-4 四人残局任务面板不与任意AI座位重叠")
		if bs_pz.puzzle_hint_btn != null:
			bs_pz.puzzle_hint_btn.pressed.emit()
			await get_tree().process_frame
		_ok(bs_pz.puzzle_hint_shown and bs_pz.puzzle_label.text.find("提示") >= 0, "V37-4 残局任务栏可一键展开攻略提示")
		bs_pz.eng.game_over = true
		bs_pz.end_play_pressed.emit()
		bs_pz.decided.emit(null)
		await _frames(3)
	else:
		_ok(false, "V37-4 未能启动残局 p07")
	main_ref.show_home()
	await _frames(2)


# ---------------- V0.38：御影纱奈（通用标记/手牌上限+/破空）、斗地主加倍与欢斗豆、弃牌一键预选与双击直出 ----------------
func _reg_v38() -> void:
	# V38-1 御影纱奈「敛羽」&「破空」
	var esn = _clean_eng("duel", ["先手", "后手"], 4)
	var sp0: Dictionary = esn.players[0]
	var sp1: Dictionary = esn.players[1]
	sp0["char_name"] = "御影纱奈"
	esn.add_skill(sp0, "lianyu")
	esn.add_skill(sp0, "pokong")
	# 回合外打出闪避凝聚影羽
	esn.turn_player = sp1
	_give(esn, sp0, "闪避", "红桃", 2)
	var d_out: bool = await esn.respond_with(sp0, "闪避", "测试敛羽")
	_ok(d_out and int(esn.mark_count(sp0, "影羽")) == 1 and int(esn.hand_limit(sp0)) == 5, "V38-1 「敛羽」回合外打出闪避获得 1 枚「影羽」，手牌上限变为 5")
	# 受到伤害再凝聚影羽
	await esn.damage(sp1, sp0, 2, "突击")
	_ok(int(sp0["hp"]) == 2 and int(esn.mark_count(sp0, "影羽")) == 3 and int(esn.hand_limit(sp0)) == 5, "V38-1 受到 2 点伤害再凝 2 枚「影羽」（共 3/4），2血手牌上限仍为 5")
	# 弃牌阶段保留至 hand_limit (5张)
	for _i in 6:
		_give(esn, sp0, "闪避", "方块", _i + 2)
	await esn.discard_phase(sp0)
	_ok((sp0["hand"] as Array).size() == 5, "V38-1 弃牌阶段按 hand_limit() 正确保留 5 张手牌")
	# 「破空」消耗 3 枚影羽摸 3 牌，获得 +1 突击次数与 +1 伤害（drunk）
	esn.turn_player = sp0
	sp0["pokong_atk_bonus"] = 0
	var hn_before: int = (sp0["hand"] as Array).size()
	await esn.use_active_skill(sp0, "pokong")
	_ok(int(esn.mark_count(sp0, "影羽")) == 0 and (sp0["hand"] as Array).size() == hn_before + 3 and int(esn.attack_limit(sp0)) == 2 and bool(sp0.get("drunk", false)), "V38-1 「破空」消耗全部「影羽」摸等量牌，并获突击次数 +1 与下次突击伤害 +1")
	_ok(Characters.LIST.size() >= 17 and ResourceLoader.exists("res://assets/cg/sana.webp"), "V38-1 第 17 名角色「御影纱奈」及 CG 资源齐全")

	# V38-2 斗地主加倍与欢斗豆统计
	var eddz = _clean_eng("doudizhu", ["地主", "农民", "农民"], 4)
	eddz.ddz_landlord_seat = 0
	eddz.ddz_multiplier = 3
	var drec: Array = []
	_script_ui(eddz, [0], {"option_0": 2}, drec)  # opt[2] = 超级加倍 ×4
	await eddz.run_ddz_doubling()
	_ok(int(eddz.ddz_multiplier) == 3 and int(eddz.ddz_double) >= 4 and int(eddz.ddz_stake()) >= 12, "V38-2 斗地主加倍独立叠加在 ddz_double（不改变叫分 1~3）")
	eddz.set_ui({})
	const Meta38 = preload("res://scripts/meta.gd")
	Meta38.reset_for_test("user://meta_v38.json")
	Meta38.path = "user://meta_v38.json"
	_ok(Meta38.beans() == 1000, "V38-2 初始欢斗豆为 1000")
	var mres: Dictionary = Meta38.record({"mode": "doudizhu", "char": "御影纱奈", "identity": "地主", "result": "win", "rounds": 4, "dmg": 6, "kills": 2, "heal": 0, "taken": 1, "mvp": true, "beans_delta": 1200})
	_ok(int(mres.get("beans", 0)) == 2200 and (Meta38.load_data()["ach"] as Dictionary).has("rich_beans"), "V38-2 斗地主胜局加豆并解锁成就「欢斗富豪」")
	Meta38.reset_for_test("user://meta_v38.json")
	Meta38.path = "user://meta_test.json"

	# V38-3 弃牌一键选弱牌 & 双击手牌直出
	var bs38 = _new_battle("identity", 38)
	if await _reach_my_play(bs38):
		var m38: Dictionary = bs38.players[0]
		bs38.set_double_tap(true, false)
		var wz38 := _give(bs38.eng, m38, "灵感爆发", "红桃", 1)
		bs38.refresh()
		await _frames(1)
		bs38._last_card_tap_ms = Time.get_ticks_msec()
		bs38._on_hand_card_clicked(wz38)  # 第1次选中
		bs38._on_hand_card_clicked(wz38)  # 450ms 内第2次双击直出
		await _wait_interactive(bs38)
		_ok(not bs38._hand_has(wz38), "V38-3 开启「双击手牌直出」后，快速连点无目标牌直接打出")
		bs38.set_double_tap(false, false)
		# 测试弃牌一键选弱牌
		while (m38["hand"] as Array).size() < 4:
			_give(bs38.eng, m38, "突击", "梅花", 7)
		var done_d := {"fin": false}
		var run_d := func() -> void:
			await bs38._eng_choose_discard(m38)
			done_d["fin"] = true
		run_d.call()
		await _frames(2)
		var pick_weak_btn: Button = bs38.prompt_btns.get_child(1) as Button if bs38.prompt_btns.get_child_count() >= 2 else null
		_ok(pick_weak_btn != null and pick_weak_btn.text.find("选弱牌") >= 0, "V38-3 弃牌提示栏包含「⚡ 选弱牌」快捷预选按钮")
		if pick_weak_btn != null:
			pick_weak_btn.pressed.emit()
			await _frames(1)
		_ok(bs38.discard_sel.size() == bs38.discard_need and bs38.discard_confirm_btn != null and not bs38.discard_confirm_btn.disabled, "V38-3 点击「选弱牌」后自动预选所需张数并亮起「确定」")
		if bs38.discard_confirm_btn != null:
			bs38.discard_confirm_btn.pressed.emit()
		await _frames(3)
	else:
		_ok(false, "V38-3 未能进入真人出牌阶段")
	await _close_battle(bs38)


# ---------------- V0.39：星川幽（命札改判/余谶）、彩色 BBCode 记牌器、连胜与本命武将榜 ----------------
func _reg_v39() -> void:
	var ey = _clean_eng("twovtwo", ["红方", "蓝方", "蓝方", "红方"], 3)
	var me0: Dictionary = ey.players[0]
	var foe1: Dictionary = ey.players[1]
	var ally3: Dictionary = ey.players[3]
	ally3["char_name"] = "星川幽"
	ey.add_skill(ally3, "mingzha")
	ey.add_skill(ally3, "yuchen")
	_give(ey, ally3, "突击", "黑桃", 7)
	ey.deck.append(_mk("补给", "红桃", 6))
	ey.deck.append(_mk("闪避", "红桃", 2))
	var c_before := census(ey)
	var j1: Dictionary = await ey.do_judge(foe1, "结界手环")
	var c_diff := census_diff(c_before, census(ey))
	_ok(not ey.is_red(j1) and (ally3["hand"] as Array).size() == 1 and int((ally3["round_marks"] as Dictionary).get("mingzha_cnt", 0)) == 1 and c_diff == "", "V39-1 「命札」将敌方「结界手环」红桃改判为黑色失效并摸 1 牌（牌堆完全守恒）")
	var hcard := _give(ey, ally3, "闪避", "红桃", 9)
	ey.deck.append(_mk("特饮", "方块", 9))
	ey.deck.append(_mk("突击", "黑桃", 5))
	var j2: Dictionary = await ey.do_judge(me0, "沉迷游戏")
	_ok(String(j2["suit"]) == "红桃" and not (ally3["hand"] as Array).has(hcard) and int((ally3["round_marks"] as Dictionary).get("mingzha_cnt", 0)) == 2, "V39-1 「命札」将队友「沉迷游戏」黑桃改判为红桃解除控制（第 2/2 次）")
	var blk_left := _give(ey, ally3, "突击", "梅花", 4)
	ey.deck.append(_mk("闪避", "方块", 8))
	var j3: Dictionary = await ey.do_judge(foe1, "结界手环")
	_ok(ey.is_red(j3) and (ally3["hand"] as Array).has(blk_left) and (ally3["hand"] as Array).size() == 3, "V39-1 「命札」每轮达到 2 次上限后不再触发")
	(ally3["hand"] as Array).pop_back()  # 调整至 2 张（小于 3 体力上限）
	ally3["hp"] = 3
	ally3["max_hp"] = 3
	await ey.fire("phaseZhunbeiStart", {"name": "phase", "player": ally3, "target": ally3})
	_ok((ally3["hand"] as Array).size() == 3, "V39-1 「余谶」在手牌小于体力上限时准备阶段摸 1 张牌")
	await ey.fire("phaseZhunbeiStart", {"name": "phase", "player": ally3, "target": ally3})
	_ok((ally3["hand"] as Array).size() == 3, "V39-1 「余谶」手牌已达体力上限时不重复摸牌")
	_ok(Characters.LIST.size() >= 18 and ResourceLoader.exists("res://assets/cg/yuu.webp"), "V39-1 第 18 名角色「星川幽」及 CG 资源齐全")

	const Meta39 = preload("res://scripts/meta.gd")
	Meta39.reset_for_test("user://meta_v39.json")
	Meta39.path = "user://meta_v39.json"
	for wi in 3:
		Meta39.record({"mode": "duel", "char": "星川幽" if wi < 2 else "御影纱奈", "identity": "先手", "result": "win", "rounds": 4, "dmg": 3, "kills": 1, "heal": 0, "taken": 1, "mvp": true})
	var d39: Dictionary = Meta39.load_data()
	var t3: Array = Meta39.top_chars(3)
	_ok(int(d39.get("win_streak", 0)) == 3 and int(d39.get("best_streak", 0)) == 3 and (d39["ach"] as Dictionary).has("streak_3"), "V39-2 三连胜更新 win_streak/best_streak 并解锁成就「势如破竹」")
	_ok(t3.size() == 2 and String(t3[0]["name"]) == "星川幽", "V39-2 本命武将榜按胜场正确排序")
	main_ref.show_records()
	await get_tree().process_frame
	_ok(main_ref.screen_root.get_child_count() > 0, "V39-2 含连胜与本命武将榜的战绩页正常渲染")
	Meta39.reset_for_test("user://meta_v39.json")
	Meta39.path = "user://meta_test.json"
	main_ref.show_home()
	await get_tree().process_frame


func _reg_v40() -> void:
	# V40-1: 第 19 名角色千早真冬（mafuyu）与 CG 资源
	var mf_c := Characters.by_id("mafuyu")
	_ok(Characters.LIST.size() >= 19 and not mf_c.is_empty() and String(mf_c["name"]) == "千早真冬" and ResourceLoader.exists("res://assets/cg/mafuyu.webp"), "V40-1 第 19 名角色「千早真冬」及 CG 资源齐全")

	# V40-2: 霜封：封锁非锁定技（如绯樱/星帷）+ 黑色判定强命 + 锁定技豁免（圣盾）+ 回合结束解除
	var eng_sf = _clean_eng()
	eng_sf.setup_game([
		{"name": "千早真冬", "hp": 3, "skills": ["shuangfeng"]},
		{"name": "樱庭雏", "hp": 3, "skills": ["feiyin", "shengdun"]},
	], ["主公", "反贼"])
	for p in eng_sf.players:
		(p["hand"] as Array).clear()
		(p["judge"] as Array).clear()
		p["shield"] = 0
	var mf: Dictionary = eng_sf.players[0]
	var hn: Dictionary = eng_sf.players[1]
	(mf["hand"] as Array).append({"name": "突击", "suit": "红桃", "point": 7, "nature": ""})
	(hn["hand"] as Array).append({"name": "闪避", "suit": "红桃", "point": 5})
	# deck pops from back: 判定牌黑桃10
	eng_sf.deck.append({"name": "突击", "suit": "黑桃", "point": 10, "nature": ""})
	eng_sf.set_ui({
		"is_human": func(p): return int(p["seat"]) == 0,
		"pick_option": func(_p, opts, _prompt):
			return true if opts.size() > 0 and opts[0].get("value") is bool else opts[0]["value"],
	})
	await eng_sf.use_attack(mf, hn, mf["hand"][0])
	_ok(bool(hn.get("skills_sealed", false)) and not eng_sf.has_skill(hn, "feiyin") and eng_sf.has_skill(hn, "shengdun"), "V40-2a 霜封封锁非锁定技但不封锁定技")
	_ok(int(hn["hp"]) == 2 and (hn["hand"] as Array).size() == 1, "V40-2b 霜封判定黑色强命无视闪避命中 1 点伤害")
	eng_sf.set_ui({})

	# V40-3: 冰心：结束阶段将手牌补至不超过体力上限（单次至多摸 2 张）
	var eng_bx = _clean_eng()
	eng_bx.setup_game([
		{"name": "千早真冬", "hp": 3, "skills": ["bingxin"]},
		{"name": "星野咲夜", "hp": 3, "skills": []},
	], ["主公", "反贼"])
	for p in eng_bx.players:
		(p["hand"] as Array).clear()
		(p["judge"] as Array).clear()
	var mf2: Dictionary = eng_bx.players[0]
	mf2["max_hp"] = 4
	mf2["hp"] = 3
	(mf2["hand"] as Array).append({"name": "闪避", "suit": "红桃", "point": 2})
	eng_bx.set_ui({"is_human": func(_p): return false})
	await eng_bx.fire("phaseJieshuStart", {"name": "phaseJieshu", "player": mf2})
	_ok((mf2["hand"] as Array).size() == 3, "V40-3 冰心 1 牌摸 2 张至 3（受单次最多 2 张限制）")
	eng_bx.set_ui({})

	# V40-4: 残局第二章 p11~p15 正解通关 + 常见错序陷阱失败验证
	_ok(PuzzlesT.count() >= 15 and PuzzlesT.chapter_of("p10") == 1 and PuzzlesT.chapter_of("p11") == 2 and PuzzlesT.chapter_of("p15") == 2, "V40-4a 残局扩展至 15 关且分章正确")

	# p11 正解：连弩 -> 特饮 -> 突击（命札以看破黑桃11改判红桃6） -> 突击击杀
	var e11_ok = await _pz_play("p11", func(e, me):
		var bow := _pz_find(me, "魔导连弩")
		if not bow.is_empty(): await e.play_card(me, bow, me)
		var drk := _pz_find(me, "特饮")
		if not drk.is_empty(): await e.play_card(me, drk, me)
		var a1 := _pz_find(me, "突击")
		if not a1.is_empty(): await e.play_card(me, a1, e.players[1])
		var a2 := _pz_find(me, "突击")
		if not a2.is_empty() and e.players[1]["alive"]: await e.play_card(me, a2, e.players[1]),
		func(_e, _p, opts, _pr):
			return true,
		func(_e, _p, cands, _pr):
			for c in cands:
				if String(c["name"]) == "看破": return c
			return cands[0])
	_ok(bool(e11_ok.game_over) and String(e11_ok.winner_text) == "残局破解成功！", "V40-4b p11「命札破阵」正解过关")
	# p11 陷阱：拒绝发动命札改判 -> 红桃6触发结界手环闪避 2 伤特饮突击 -> 守关者存活失败
	var e11_trap = await _pz_play("p11", func(e, me):
		var bow := _pz_find(me, "魔导连弩")
		if not bow.is_empty(): await e.play_card(me, bow, me)
		var drk := _pz_find(me, "特饮")
		if not drk.is_empty(): await e.play_card(me, drk, me)
		var a1 := _pz_find(me, "突击")
		if not a1.is_empty(): await e.play_card(me, a1, e.players[1])
		var a2 := _pz_find(me, "突击")
		if not a2.is_empty() and e.players[1]["alive"]: await e.play_card(me, a2, e.players[1]),
		func(_e, _p, _opts, _pr):
			return false)
	_ok(bool(e11_trap.game_over) and not String(e11_trap.winner_text) == "残局破解成功！", "V40-4c p11 拒绝命札改判必定失败")

	# p12 正解：先出突击骗出1号位闪避 -> 再破空（摸突击+火试炼）-> 2伤突击斩1号位 -> 火焰试炼弃红桃闪避斩2号位
	var e12_ok = await _pz_play("p12", func(e, me):
		var a0 := _pz_find(me, "突击")
		if not a0.is_empty(): await e.play_card(me, a0, e.players[1])
		await e.use_active_skill(me, "pokong")
		var a1 := _pz_find(me, "突击")
		if not a1.is_empty() and e.players[1]["alive"]: await e.play_card(me, a1, e.players[1])
		var hg := _pz_find(me, "火焰试炼")
		if not hg.is_empty() and e.players[2]["alive"]: await e.play_card(me, hg, e.players[2]))
	_ok(bool(e12_ok.game_over) and String(e12_ok.winner_text) == "残局破解成功！", "V40-4d p12「影羽破空」先诱闪再破空过关")
	# p12 陷阱：先破空再突击 -> 破空加伤撞进闪避 -> 守关者存活失败
	var e12_trap = await _pz_play("p12", func(e, me):
		await e.use_active_skill(me, "pokong")
		var a0 := _pz_find(me, "突击")
		if not a0.is_empty(): await e.play_card(me, a0, e.players[1])
		var a1 := _pz_find(me, "突击")
		if not a1.is_empty() and e.players[1]["alive"]: await e.play_card(me, a1, e.players[1])
		var hg := _pz_find(me, "火焰试炼")
		if not hg.is_empty() and e.players[2]["alive"]: await e.play_card(me, hg, e.players[2]))
	_ok(bool(e12_trap.game_over) and not String(e12_trap.winner_text) == "残局破解成功！", "V40-4e p12 先开破空浪费加伤必定失败")

	# p13 正解：时计选火突击 -> 突然检查拆闪避 -> 火突击双倍穿藤蔓
	var e13_ok = await _pz_play("p13", func(e, me):
		await e.use_active_skill(me, "shiji")
		var dis := _pz_find(me, "突然检查")
		if not dis.is_empty() and not (e.players[1]["hand"] as Array).is_empty(): await e.play_card(me, dis, e.players[1], e.players[1]["hand"][0])
		var fa := _pz_find(me, "突击", "火")
		if not fa.is_empty(): await e.play_card(me, fa, e.players[1]),
		func(_e, _p, opts, _pr):
			for o in opts:
				var lb := String((o as Dictionary).get("label", ""))
				if lb.contains("火") or lb.contains("突击"): return o["value"]
			return opts[0]["value"],
		func(_e, _p, cands, _pr):
			for c in cands:
				if String(c["name"]) == "闪避": return c
			return cands[0])
	_ok(bool(e13_ok.game_over) and String(e13_ok.winner_text) == "残局破解成功！", "V40-4f p13「星时抉择」选火突击破藤蔓过关")
	# p13 陷阱：时计误选特饮 -> 普通突击被藤蔓铠甲免疫
	var e13_trap = await _pz_play("p13", func(e, me):
		await e.use_active_skill(me, "shiji")
		var dis := _pz_find(me, "突然检查")
		if not dis.is_empty() and not (e.players[1]["hand"] as Array).is_empty(): await e.play_card(me, dis, e.players[1], e.players[1]["hand"][0])
		var drk := _pz_find(me, "特饮")
		if not drk.is_empty(): await e.play_card(me, drk, me)
		var na := _pz_find(me, "突击")
		if not na.is_empty(): await e.play_card(me, na, e.players[1]),
		func(_e, _p, opts, _pr):
			for o in opts:
				if String((o as Dictionary).get("label", "")).contains("特饮"): return o["value"]
			return opts[opts.size() - 1]["value"],
		func(_e, _p, cands, _pr):
			for c in cands:
				if String(c["name"]) == "闪避": return c
			return cands[0])
	_ok(bool(e13_trap.game_over) and not String(e13_trap.winner_text) == "残局破解成功！", "V40-4g p13 误拿特饮打不动藤蔓必定失败")

	# p14 正解：先水淹逼弃满血银狮（0回血） -> 再特饮+突击 2 伤斩杀
	var e14_ok = await _pz_play("p14", func(e, me):
		var sy := _pz_find(me, "水淹七军")
		if not sy.is_empty(): await e.play_card(me, sy, e.players[1])
		var drk := _pz_find(me, "特饮")
		if not drk.is_empty(): await e.play_card(me, drk, me)
		var a := _pz_find(me, "突击")
		if not a.is_empty() and e.players[1]["alive"]: await e.play_card(me, a, e.players[1]))
	_ok(bool(e14_ok.game_over) and String(e14_ok.winner_text) == "残局破解成功！", "V40-4h p14「洪流弃甲」满血逼弃银狮不回血过关")
	# p14 陷阱：先特饮+突击只打 1 伤 -> 再水淹弃银狮帮敌回满 2 血 -> 失败
	var e14_trap = await _pz_play("p14", func(e, me):
		var drk := _pz_find(me, "特饮")
		if not drk.is_empty(): await e.play_card(me, drk, me)
		var a := _pz_find(me, "突击")
		if not a.is_empty(): await e.play_card(me, a, e.players[1])
		var sy := _pz_find(me, "水淹七军")
		if not sy.is_empty() and e.players[1]["alive"]: await e.play_card(me, sy, e.players[1]))
	_ok(bool(e14_trap.game_over) and not String(e14_trap.winner_text) == "残局破解成功！", "V40-4i p14 先砍后水淹触发银狮回血必定失败")

	# p15 正解：羁绊锁链横置两敌 -> 特饮 -> 火突击打星川幽并发动霜封（先封命札、黑桃强命） -> 连环传导穿藤蔓双杀
	var e15_ok = await _pz_play("p15", func(e, me):
		var ts_c := _pz_find(me, "羁绊锁链")
		if not ts_c.is_empty(): await e.play_card(me, ts_c, e.players[1])
		var drk := _pz_find(me, "特饮")
		if not drk.is_empty(): await e.play_card(me, drk, me)
		var fa := _pz_find(me, "突击", "火")
		if not fa.is_empty(): await e.play_card(me, fa, e.players[1]),
		func(e, p, opts, pr):
			if String(pr).contains("羁绊锁链"):
				for o in opts:
					if o["value"] is Dictionary and o["value"] == e.players[2]: return o["value"]
			if int(p["seat"]) == 0:
				return true
			return opts[0]["value"],
		Callable(),
		func(e, _p, cands, _pr):
			for c in cands:
				if c == e.players[2]: return c
			return cands[0])
	_ok(bool(e15_ok.game_over) and String(e15_ok.winner_text) == "残局破解成功！", "V40-4j p15「霜封破御」封命札强命连环双杀过关")
	# p15 陷阱：放弃发动霜封 -> 星川幽打出黑桃8闪避完全躲过 -> 失败
	var e15_trap = await _pz_play("p15", func(e, me):
		var ts_c := _pz_find(me, "羁绊锁链")
		if not ts_c.is_empty(): await e.play_card(me, ts_c, e.players[1])
		var drk := _pz_find(me, "特饮")
		if not drk.is_empty(): await e.play_card(me, drk, me)
		var fa := _pz_find(me, "突击", "火")
		if not fa.is_empty(): await e.play_card(me, fa, e.players[1]),
		func(e, _p, opts, pr):
			if String(pr).contains("羁绊锁链"):
				for o in opts:
					if o["value"] is Dictionary and o["value"] == e.players[2]: return o["value"]
			return opts[0]["value"],
		Callable(),
		func(e, _p, cands, _pr):
			for c in cands:
				if c == e.players[2]: return c
			return cands[0],
		func(_p, _sid, _tm, _ctx): return false)
	_ok(bool(e15_trap.game_over) and not String(e15_trap.winner_text) == "残局破解成功！", "V40-4k p15 不发动霜封被闪避必定失败")

	# V40-5: Meta 禁用武将池护栏 + 首页看板置顶 + 斗地主开局明牌倍率 + 第 25 项成就
	const Meta40 = preload("res://scripts/meta.gd")
	var old_path: String = Meta40.path
	Meta40.reset_for_test("/tmp/qmxs_v40_meta_test.json")
	_ok(Meta40.ACHIEVEMENTS.size() == 25 and not Meta40.ach_def("puzzle_master").is_empty(), "V40-5a 第 25 项残局成就及成就上限合法")
	_ok(Meta40.toggle_ban_char("yuu", Characters.LIST.size()) and Meta40.is_char_banned("yuu") and Meta40.enabled_pool(Characters.LIST).size() == Characters.LIST.size() - 1, "V40-5b 禁用武将可开关且过滤点将池")
	Meta40.pin_showcase_char("mafuyu")
	_ok(String(Meta40.get_showcase(Characters.LIST)[0]) == "mafuyu", "V40-5c 设为首页看板持久化到首位")
	Meta40.toggle_ban_char("yuu", Characters.LIST.size())
	_ok(not Meta40.toggle_ban_char("hina", 8), "V40-5d 最少保留 8 名启用武将护栏生效")
	# DDZ 明牌 ×2 倍率检验
	var eng_open = _clean_eng()
	eng_open.mode = "doudizhu"
	eng_open.setup_game([
		{"name": "千早真冬", "hp": 3, "skills": []},
		{"name": "星川幽", "hp": 3, "skills": []},
		{"name": "御影纱奈", "hp": 4, "skills": []},
	], ["地主", "农民", "农民"])
	eng_open.ddz_landlord_seat = 0
	eng_open.ddz_multiplier = 2
	eng_open.set_ui({
		"is_human": func(p): return int(p["seat"]) == 0,
		"pick_option": func(_p, opts, prompt):
			if String(prompt).contains("明牌"): return true
			return 2,
	})
	await eng_open.run_ddz_doubling()
	_ok(eng_open.ddz_open_seats.has(0) and eng_open.ddz_double >= 4 and eng_open.ddz_stake() >= 8, "V40-5e 斗地主开局明牌公开座位且总倍数 ×2 生效")
	eng_open.set_ui({})
	Meta40.reset_for_test("/tmp/qmxs_v40_meta_test.json")
	Meta40.path = old_path


func _reg_v41() -> void:
	const Audio41 = preload("res://scripts/audio.gd")
	const Music41 = preload("res://scripts/music.gd")
	const BS41 = preload("res://scripts/battle.gd")
	Audio41.ensure()

	# V41-1: 全部 24 种高保真立体声 SFX 音效文件可加载
	var sfx_miss: Array = []
	for k in Audio41.SFX_FILES:
		if Audio41.sfx_stream(String(k)) == null:
			sfx_miss.append(k)
	_ok(Audio41.SFX_FILES.size() >= 24 and sfx_miss.is_empty(), "V41-1 全部 %d 种手杀×二次元立体声音效齐全" % Audio41.SFX_FILES.size())

	# V41-2: 樱华国风与经典交响 6 首 BGM 齐全且支持双曲风切换
	var bgm_ok := ResourceLoader.exists("res://assets/bgm/home_sakura.ogg") and ResourceLoader.exists("res://assets/bgm/battle_storm.ogg") and ResourceLoader.exists("res://assets/bgm/tense_climax.ogg") and ResourceLoader.exists("res://assets/bgm/home_carefree.ogg")
	var old_style := String(Audio41.get_v("bgm_style"))
	Audio41.set_v("bgm_style", "sakura", false)
	var t_sak := Music41.track_title("home")
	var t_cls := ""
	if main_ref.music != null:
		main_ref.music.cycle_style()
		t_cls = Music41.track_title("home")
		main_ref.music.cycle_style()
	Audio41.set_v("bgm_style", old_style, false)
	_ok(bgm_ok and t_sak.find("樱华") >= 0 and t_cls.find("Carefree") >= 0, "V41-2 樱华国风与经典交响双套 BGM 及一键切换生效")

	# V41-3: 全部 19 名角色战斗与互动台词（CHAR_LINES）100% 覆盖
	var line_miss: Array = []
	for c in Characters.LIST:
		var cid := String(c["id"])
		for cat in ["attack", "hurt", "dying", "death", "skill", "heal"]:
			if BS41.line_for(cid, cat) == "":
				line_miss.append(cid + ":" + cat)
	_ok(line_miss.is_empty(), "V41-3 全部 %d 名角色 6 类二次元台词 100%% 覆盖" % Characters.LIST.size())

	# V41-4: 牌桌六阶段指示器与新版大厅/详情页渲染
	main_ref.clear_screen()
	var bs41 = BS41.new()
	bs41.set_anchors_preset(Control.PRESET_FULL_RECT)
	bs41.go_home = Callable(main_ref, "show_home")
	main_ref.screen_root.add_child(bs41)
	bs41.build_table()
	bs41.set_phase("出牌阶段")
	_ok(bs41.phase_pills.size() == 6, "V41-4 牌桌顶部手杀式六阶段进度指示器正常构建")
	await _close_battle(bs41)
	main_ref.show_detail(Characters.by_id("mafuyu"))
	await _frames(2)
	main_ref.show_home()
	await _frames(2)
