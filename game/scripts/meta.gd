extends RefCounted
# V0.30 局外系统：战绩记录 / 角色熟练度 / 成就 / 教学完成标记。数据存 user://meta.json。
# 自测时 selftest 会把 path 指到 user://meta_test.json，不影响玩家数据。

static var path := "user://meta.json"
static var _data := {}
static var _loaded_path := ""

const MASTERY_XP := [0, 40, 120, 250, 450]
const MASTERY_TITLE := ["见习", "熟练", "精通", "大师", "传说"]
const MAX_RECORDS := 50

# 成就：id, 名称, 说明
const ACHIEVEMENTS := [
	["first_game", "初次登场", "完成 1 局对战"],
	["first_win", "初战告捷", "赢得 1 局对战"],
	["games_10", "常客", "累计完成 10 局"],
	["games_50", "老玩家", "累计完成 50 局"],
	["wins_10", "胜利者", "累计赢得 10 局"],
	["id_lord", "樱下之主", "以主公身份获胜"],
	["id_loyal", "忠心耿耿", "以忠臣身份获胜"],
	["id_rebel", "揭竿而起", "以反贼身份获胜"],
	["id_nei", "笑到最后", "以内奸身份获胜"],
	["ddz_landlord", "地主之威", "斗地主以地主身份获胜"],
	["ddz_farmer", "农民翻身", "斗地主以农民身份获胜"],
	["duel_win", "单挑王", "赢得一局单挑"],
	["dmg_8", "火力全开", "单局造成至少 8 点伤害"],
	["kills_3", "连斩", "单局击杀至少 3 名角色"],
	["heal_5", "樱花治愈", "单局回复至少 5 点体力"],
	["mvp", "本局 MVP", "获得一次本局 MVP"],
	["flawless", "毫发无伤", "获胜且全局未受伤害"],
	["all_chars", "全员集合", "用全部 7 名角色各完成 1 局"],
	["mastery_3", "得心应手", "任一角色熟练度达到 Lv3"],
	["tutorial", "新手毕业", "完成教学关"],
	["puzzle_first", "初破残局", "通过任意 1 关残局挑战"],
	["puzzle_master", "破局宗师", "累计通关 10 关不同的残局挑战"],
	["puzzle_all", "残局大师", "通关全部残局挑战（15 关）"],
	["rich_beans", "欢斗富豪", "累计拥有至少 2000 欢斗豆"],
	["streak_3", "势如破竹", "常规对战达成 3 连胜"],
]


static func _blank() -> Dictionary:
	return {"version": 2, "records": [], "totals": {}, "chars": {}, "ach": {}, "puzzles": {}, "beans": 1000, "win_streak": 0, "best_streak": 0, "tutorial_done": false, "banned_chars": [], "showcase": ["sena", "hina", "reo"]}


static func load_data() -> Dictionary:
	if _loaded_path == path and not _data.is_empty():
		return _data
	_loaded_path = path
	_data = _blank()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				for k in _data.keys():
					if (v as Dictionary).has(k):
						_data[k] = v[k]
				_data["version"] = int((v as Dictionary).get("version", 1))
				if migrate(_data):
					save()
	return _data


# V0.31：角色全面原创化后改了名字和 id。旧存档里按旧名记的熟练度、战绩逐条改成新名（合并同名累计），
# 存档版本升到 2；只迁移一次，之后照常读写。
static func migrate(d: Dictionary) -> bool:
	if int(d.get("version", 1)) >= 2:
		return false
	var CharsT = load("res://data/characters.gd")
	var nc := {}
	for cn in (d["chars"] as Dictionary).keys():
		var nn: String = CharsT.migrate_name(String(cn))
		var cs: Dictionary = d["chars"][cn]
		if nc.has(nn):
			var o: Dictionary = nc[nn]
			for k in ["games", "wins", "xp"]:
				o[k] = int(o.get(k, 0)) + int(cs.get(k, 0))
		else:
			nc[nn] = cs
	d["chars"] = nc
	for r in d["records"]:
		if r is Dictionary and (r as Dictionary).has("char"):
			r["char"] = CharsT.migrate_name(String(r["char"]))
	d["version"] = 2
	return true


static func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_data))


static func reset_for_test(p: String) -> void:
	path = p
	_loaded_path = ""
	_data = {}
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


static func level_of(xp: int) -> int:
	var lv := 1
	for i in MASTERY_XP.size():
		if xp >= int(MASTERY_XP[i]):
			lv = i + 1
	return lv


static func next_xp(xp: int) -> int:
	for t in MASTERY_XP:
		if xp < int(t):
			return int(t)
	return -1


static func _bump(d: Dictionary, key: String, won: bool) -> void:
	var t: Dictionary = d["totals"]
	var v: Array = t.get(key, [0, 0])
	t[key] = [int(v[0]) + 1, int(v[1]) + (1 if won else 0)]


static func beans() -> int:
	return int(load_data().get("beans", 1000))


static func _apply_beans(d: Dictionary, delta: int) -> Dictionary:
	var old_b := int(d.get("beans", 1000))
	var cur := maxi(0, old_b + delta)
	var aid := false
	if cur < 200:
		cur += 300
		aid = true
	d["beans"] = cur
	return {"beans": cur, "beans_delta": delta, "beans_aid": aid}


# 记录一局：rec = {mode, char, identity, result("win"/"lose"/"draw"), rounds, dmg, kills, heal, taken, mvp(bool)}
# 返回 {"xp": 本局熟练度, "level": 当前等级, "level_up": bool, "new_ach": [[id,名称,说明],...]}
static func record(rec: Dictionary) -> Dictionary:
	var d := load_data()
	var won := String(rec.get("result", "")) == "win"
	var r := rec.duplicate()
	r["t"] = int(Time.get_unix_time_from_system())
	(d["records"] as Array).push_front(r)
	while (d["records"] as Array).size() > MAX_RECORDS:
		(d["records"] as Array).pop_back()
	_bump(d, "all", won)
	_bump(d, "mode|" + String(rec.get("mode", "")), won)
	_bump(d, "id|%s|%s" % [String(rec.get("mode", "")), String(rec.get("identity", ""))], won)
	# 熟练度：完成 +10，获胜 +15，伤害每点 +1（上限 10），击杀每名 +5，MVP +5
	var xp := 10 + (15 if won else 0) + mini(int(rec.get("dmg", 0)), 10) + 5 * int(rec.get("kills", 0)) + (5 if bool(rec.get("mvp", false)) else 0)
	var cn := String(rec.get("char", ""))
	var cs: Dictionary = (d["chars"] as Dictionary).get(cn, {"games": 0, "wins": 0, "xp": 0})
	var old_lv := level_of(int(cs["xp"]))
	cs["games"] = int(cs["games"]) + 1
	cs["wins"] = int(cs["wins"]) + (1 if won else 0)
	cs["xp"] = int(cs["xp"]) + xp
	d["chars"][cn] = cs
	var binfo := {}
	if rec.has("beans_delta"):
		binfo = _apply_beans(d, int(rec["beans_delta"]))
	var ws := (int(d.get("win_streak", 0)) + 1) if won else 0
	d["win_streak"] = ws
	d["best_streak"] = maxi(int(d.get("best_streak", 0)), ws)
	var new_lv := level_of(int(cs["xp"]))
	var new_ach := _check_achievements(d, rec)
	save()
	var out := {"xp": xp, "level": new_lv, "level_up": new_lv > old_lv, "win_streak": ws, "best_streak": int(d["best_streak"]), "new_ach": new_ach}
	for bk in binfo:
		out[bk] = binfo[bk]
	return out


static func mark_tutorial() -> Array:
	var d := load_data()
	d["tutorial_done"] = true
	var out := []
	if not (d["ach"] as Dictionary).has("tutorial"):
		d["ach"]["tutorial"] = int(Time.get_unix_time_from_system())
		out.append(ach_def("tutorial"))
	save()
	return out


static func mark_puzzle(pid: String) -> Array:
	var d := load_data()
	var pz: Dictionary = d.get("puzzles", {})
	pz[pid] = int(Time.get_unix_time_from_system())
	d["puzzles"] = pz
	var out := []
	var pz_script = load("res://data/puzzles.gd")
	var total_n: int = pz_script.count() if pz_script != null else 10
	if pz.size() >= 1 and not (d["ach"] as Dictionary).has("puzzle_first"):
		d["ach"]["puzzle_first"] = int(Time.get_unix_time_from_system())
		out.append(ach_def("puzzle_first"))
	if pz.size() >= 10 and not (d["ach"] as Dictionary).has("puzzle_master"):
		d["ach"]["puzzle_master"] = int(Time.get_unix_time_from_system())
		out.append(ach_def("puzzle_master"))
	if pz.size() >= total_n and not (d["ach"] as Dictionary).has("puzzle_all"):
		d["ach"]["puzzle_all"] = int(Time.get_unix_time_from_system())
		out.append(ach_def("puzzle_all"))
	save()
	return out


static func puzzle_cleared(pid: String) -> bool:
	var pz: Dictionary = load_data().get("puzzles", {})
	return pz.has(pid)


static func puzzles_cleared_count() -> int:
	var pz: Dictionary = load_data().get("puzzles", {})
	return pz.size()


static func ach_def(id: String) -> Array:
	for a in ACHIEVEMENTS:
		if String(a[0]) == id:
			return a
	return [id, id, ""]


static func _check_achievements(d: Dictionary, rec: Dictionary) -> Array:
	var won := String(rec.get("result", "")) == "win"
	var mode := String(rec.get("mode", ""))
	var idn := String(rec.get("identity", ""))
	var all: Array = d["totals"].get("all", [0, 0])
	var got: Array = []
	var cond := {
		"first_game": int(all[0]) >= 1,
		"first_win": int(all[1]) >= 1,
		"games_10": int(all[0]) >= 10,
		"games_50": int(all[0]) >= 50,
		"wins_10": int(all[1]) >= 10,
		"id_lord": won and mode == "identity" and idn == "主公",
		"id_loyal": won and mode == "identity" and idn == "忠臣",
		"id_rebel": won and mode == "identity" and idn == "反贼",
		"id_nei": won and mode == "identity" and idn == "内奸",
		"ddz_landlord": won and mode == "doudizhu" and idn == "地主",
		"ddz_farmer": won and mode == "doudizhu" and idn == "农民",
		"duel_win": won and mode == "duel",
		"dmg_8": int(rec.get("dmg", 0)) >= 8,
		"kills_3": int(rec.get("kills", 0)) >= 3,
		"heal_5": int(rec.get("heal", 0)) >= 5,
		"mvp": bool(rec.get("mvp", false)),
		"flawless": won and int(rec.get("taken", 0)) == 0,
		"all_chars": (d["chars"] as Dictionary).size() >= 7,
		"rich_beans": int(d.get("beans", 1000)) >= 2000,
		"streak_3": int(d.get("best_streak", 0)) >= 3,
		"mastery_3": false,
	}
	for cn in (d["chars"] as Dictionary).keys():
		if level_of(int(d["chars"][cn]["xp"])) >= 3:
			cond["mastery_3"] = true
	for id in cond.keys():
		if bool(cond[id]) and not (d["ach"] as Dictionary).has(id):
			d["ach"][id] = int(Time.get_unix_time_from_system())
			got.append(ach_def(id))
	return got


static func top_chars(limit: int = 3) -> Array:
	var d := load_data()
	var chars_d: Dictionary = d.get("chars", {})
	var arr: Array = []
	for cn in chars_d.keys():
		var cs: Dictionary = chars_d[cn]
		if int(cs.get("games", 0)) <= 0:
			continue
		arr.append({"name": String(cn), "games": int(cs.get("games", 0)), "wins": int(cs.get("wins", 0)), "xp": int(cs.get("xp", 0))})
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["wins"]) != int(b["wins"]):
			return int(a["wins"]) > int(b["wins"])
		if int(a["games"]) != int(b["games"]):
			return int(a["games"]) > int(b["games"])
		return int(a["xp"]) > int(b["xp"]))
	return arr.slice(0, mini(limit, arr.size()))


static func win_rate_text(key: String) -> String:
	var v: Array = load_data()["totals"].get(key, [0, 0])
	if int(v[0]) == 0:
		return "—"
	return "%d 局 · 胜 %d · %.0f%%" % [int(v[0]), int(v[1]), 100.0 * float(v[1]) / float(v[0])]


# V0.40 武将禁用池与首页看板持久化（保留至少 8 名可用武将，避免 8 人局选角枯竭）
static func is_char_banned(cid: String) -> bool:
	var d := load_data()
	var arr: Array = d.get("banned_chars", [])
	return arr.has(cid)


static func toggle_ban_char(cid: String, total_chars: int = 19) -> bool:
	var d := load_data()
	var arr: Array = (d.get("banned_chars", []) as Array).duplicate()
	if arr.has(cid):
		arr.erase(cid)
	else:
		if total_chars - arr.size() <= 8:
			return false
		arr.append(cid)
	d["banned_chars"] = arr
	save()
	return true


static func enabled_pool(all_chars: Array) -> Array:
	var d := load_data()
	var banned: Array = d.get("banned_chars", [])
	if banned.is_empty():
		return all_chars.duplicate()
	var out: Array = []
	for c in all_chars:
		if not banned.has(String((c as Dictionary).get("id", ""))):
			out.append(c)
	if out.size() < 8:
		return all_chars.duplicate()
	return out


static func get_showcase(all_chars: Array) -> Array:
	var d := load_data()
	var valid := {}
	for c in all_chars:
		valid[String((c as Dictionary).get("id", ""))] = true
	var out: Array = []
	for raw_id in (d.get("showcase", ["sena", "hina", "reo"]) as Array):
		var sid := String(raw_id)
		if valid.has(sid) and not out.has(sid):
			out.append(sid)
	for def_id in ["sena", "hina", "reo"]:
		if out.size() >= 3:
			break
		if valid.has(def_id) and not out.has(def_id):
			out.append(def_id)
	for c in all_chars:
		if out.size() >= 3:
			break
		var sid2 := String((c as Dictionary).get("id", ""))
		if not out.has(sid2):
			out.append(sid2)
	return out.slice(0, 3)


static func set_showcase_slot(slot_idx: int, cid: String) -> void:
	var d := load_data()
	var sc: Array = (d.get("showcase", ["sena", "hina", "reo"]) as Array).duplicate()
	while sc.size() < 3:
		sc.append("sena")
	if slot_idx >= 0 and slot_idx < sc.size():
		sc[slot_idx] = cid
	d["showcase"] = sc
	save()


static func pin_showcase_char(cid: String) -> Array:
	var d := load_data()
	var sc: Array = (d.get("showcase", ["sena", "hina", "reo"]) as Array).duplicate()
	while sc.size() < 3:
		sc.append("sena")
	var cur_idx := sc.find(cid)
	if cur_idx == 0:
		return sc
	if cur_idx > 0:
		var tmp: String = String(sc[0])
		sc[0] = cid
		sc[cur_idx] = tmp
	else:
		sc[2] = sc[1]
		sc[1] = sc[0]
		sc[0] = cid
	d["showcase"] = sc
	save()
	return sc


static func char_stats_by_name(cname: String) -> Dictionary:
	var d := load_data()
	var cs: Dictionary = (d.get("chars", {}) as Dictionary).get(cname, {})
	return cs.duplicate()
