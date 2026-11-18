extends RefCounted

# V0.37 残局闯关（对标三国杀移动版「残局闯关」/ 无名杀「残局模式」）
# 每关为固定牌局：你（1号位·挑战者）对阵若干「守关者」，须在【你的第一个回合内】击破全部守关者。
# 规则：挑战者本回合跳过摸牌阶段（只能用给定的手牌/装备破局）；守关者由 AI 以「困难」强度应对（会出闪避、会自救）。
# 牌：[牌名, 花色, 点数, 属性(可省)]；skills 为空表示「白板」（无技能），me/foes 的 char 只决定头像与名字。
# deck_top：牌堆顶依次摸到的牌（第一张最先摸到），用于含摸牌效果的关卡，保证解法确定。

const LIST: Array = [
	{
		"id": "p01", "name": "破甲一击", "stars": 1,
		"brief": "守关者身披「藤蔓铠甲」，普通突击对她无效。",
		"goal": "本回合内击破【柚木铃奈】（体力 2，穿藤蔓铠甲）。",
		"hint": "「破甲光剑」无视防具：先装备武器，再喝「特饮」打出加伤突击。",
		"me": {"char": "hina", "hp": 3, "skills": [], "hand": [["破甲光剑", "黑桃", 6], ["特饮", "黑桃", 3], ["突击", "梅花", 5], ["闪避", "方块", 3]]},
		"foes": [{"char": "rena", "hp": 2, "max_hp": 3, "skills": [], "equip": [["藤蔓铠甲", "梅花", 2]]}],
		"seed": 37001,
	},
	{
		"id": "p02", "name": "决斗时机", "stars": 1,
		"brief": "对手手握两张突击和一张闪避，体力只剩 1 点。",
		"goal": "本回合内击破【绯山响】（体力 1，手牌：突击×2、闪避×1）。",
		"hint": "直接突击会被闪避；「单挑」由目标先出突击——先单挑，让对手先把突击耗光。",
		"me": {"char": "koume", "hp": 2, "max_hp": 3, "skills": [], "hand": [["单挑", "黑桃", 1], ["突击", "黑桃", 7], ["突击", "梅花", 8]]},
		"foes": [{"char": "hibiki", "hp": 1, "max_hp": 3, "skills": [], "hand": [["突击", "梅花", 9], ["突击", "梅花", 10], ["闪避", "方块", 6]]}],
		"seed": 37002,
	},
	{
		"id": "p03", "name": "先拆后杀", "stars": 2,
		"brief": "守关者握有一张闪避和一张补给，濒死时会自救。",
		"goal": "本回合内击破【夜宫静羽】（体力 3，手牌：闪避×1、补给×1）。",
		"hint": "四张突击硬打会被闪避一次、再被补给救回。先用两张「突然检查」拆光她的手牌，再装备「魔导连弩」四连突击。",
		"me": {"char": "hibiki", "hp": 3, "skills": [], "hand": [["魔导连弩", "梅花", 1], ["突击", "黑桃", 8], ["突击", "梅花", 5], ["突击", "方块", 6], ["突击", "红桃", 10], ["突然检查", "黑桃", 3], ["突然检查", "梅花", 3]]},
		"foes": [{"char": "shizuha", "hp": 3, "skills": [], "hand": [["闪避", "方块", 5], ["补给", "红桃", 3]]}],
		"seed": 37003,
	},
	{
		"id": "p04", "name": "缴械夺弩", "stars": 2,
		"brief": "守关者装备着「魔导连弩」，手里却没有突击。",
		"goal": "本回合内击破【森崎千夏】（体力 2，手牌：闪避×1，装备魔导连弩）。",
		"hint": "对她使用「借力打力」并令她攻击你：她没有突击，只能把连弩交给你。装备连弩后连续突击。",
		"me": {"char": "kaori", "hp": 3, "skills": [], "hand": [["借力打力", "梅花", 12], ["突击", "黑桃", 7], ["突击", "梅花", 6], ["突击", "方块", 9]]},
		"foes": [{"char": "chinatsu", "hp": 2, "max_hp": 4, "skills": [], "hand": [["闪避", "红桃", 8]], "equip": [["魔导连弩", "方块", 1]]}],
		"seed": 37004,
	},
	{
		"id": "p05", "name": "火烧连营", "stars": 3,
		"brief": "两名守关者都穿着怕火的「藤蔓铠甲」。",
		"goal": "本回合内击破【宫坂歌织】（体力 2）与【藤代小梅】（体力 3），两人均穿藤蔓铠甲。",
		"hint": "用「羁绊锁链」连住两人，再用火焰突击打体力 2 的歌织：伤害 2 点并沿锁链传导，藤甲再 +1。打错人会留下一个。",
		"me": {"char": "nana", "hp": 3, "skills": [], "hand": [["羁绊锁链", "梅花", 10], ["突击", "红桃", 4, "火"], ["突击", "梅花", 8], ["闪避", "方块", 7]]},
		"foes": [
			{"char": "kaori", "hp": 2, "max_hp": 3, "skills": [], "equip": [["藤蔓铠甲", "黑桃", 2]]},
			{"char": "koume", "hp": 3, "skills": [], "equip": [["藤蔓铠甲", "梅花", 2]]},
		],
		"seed": 37005,
	},
	{
		"id": "p06", "name": "残月逆袭", "stars": 3,
		"brief": "你只剩 1 点体力，但手握限定技「奥义·残月」。",
		"goal": "本回合内击破【久远寺绫】（体力 3，手牌：闪避×1）。",
		"hint": "先发动「奥义·残月」回复 1 血并解锁无限突击；先出一张「突击」骗掉「闪避」，再喝「特饮」配合后续两次「突击」完成 3 点斩杀（若提前喝特饮撞闪避则伤害不足）。",
		"me": {"char": "reo", "hp": 1, "max_hp": 4, "skills": ["jianxin", "canyue"], "hand": [["突击", "黑桃", 8], ["突击", "梅花", 9]]},
		"foes": [{"char": "aya", "hp": 3, "max_hp": 4, "skills": [], "hand": [["闪避", "方块", 11]]}],
		"deck_top": [["突击", "梅花", 7], ["特饮", "方块", 9], ["闪避", "红桃", 8]],
		"seed": 37006,
	},
	{
		"id": "p07", "name": "昼夜连环", "stars": 4,
		"brief": "三名守关者：一人在你攻击范围外，一人穿藤蔓铠甲。",
		"goal": "本回合内击破全部三名守关者（2号位、3号位体力 1；4号位体力 2 穿藤蔓铠甲）。",
		"hint": "3号位够不着、4号位不怕普通突击——用锁链连住这两人，再以「昼夜卷·阳」（弃闪避）的火焰伤害一网打尽，最后突击 2号位。",
		"me": {"char": "mahiru", "hp": 3, "skills": ["zhouye"], "hand": [["羁绊锁链", "梅花", 11], ["突击", "梅花", 8], ["闪避", "方块", 8]]},
		"foes": [
			{"char": "rin", "hp": 1, "max_hp": 3, "skills": []},
			{"char": "yukine", "hp": 1, "max_hp": 3, "skills": []},
			{"char": "lilia", "hp": 2, "max_hp": 3, "skills": [], "equip": [["藤蔓铠甲", "梅花", 2]]},
		],
		"seed": 37007,
	},
	{
		"id": "p08", "name": "拼点远射", "stars": 3,
		"brief": "对手装备「远行披风」拉开距离，你手里只有一张突击与一张闪避。",
		"goal": "本回合内击破【天城雪音】（体力 2，手牌 1 张 J 点，装备远行披风距离 2）。",
		"hint": "你目前够不着她——发动「王手」与之拼点并亮出「闪避（9点）」，凭借「妙算 +3」以 12 点赢过 11 点，获得无距离限制与突击伤害 +1，保留手里的「突击」一击绝杀！",
		"me": {"char": "rin", "hp": 3, "skills": ["wangshou", "miaosuan"], "hand": [["突击", "黑桃", 8], ["闪避", "红桃", 9]]},
		"foes": [{"char": "yukine", "hp": 2, "max_hp": 3, "skills": [], "hand": [["突击", "黑桃", 11]], "equip": [["远行披风", "方块", 13]]}],
		"deck_top": [["闪避", "红桃", 3], ["闪避", "方块", 4]],
		"seed": 37008,
	},
	{
		"id": "p09", "name": "破盾连斩", "stars": 4,
		"brief": "圣盾骑士身带 2 点护甲与 2 点体力，还握有一张闪避。",
		"goal": "本回合内击破【圣护院莉莉娅】（体力 2 · 护甲 2 · 共计 4 点承伤，手牌：闪避×1）。",
		"hint": "先装连弩，再出「火焰试炼」（弃红桃闪避）先削去 1 点护甲；接着先出一张「突击」骗掉她的「闪避」，再喝「特饮」打出 2 伤突击+最后 1 伤突击破盾斩杀！",
		"me": {"char": "nana", "hp": 3, "skills": [], "hand": [["魔导连弩", "梅花", 1], ["火焰试炼", "红桃", 3], ["特饮", "黑桃", 9], ["突击", "黑桃", 7], ["突击", "梅花", 8], ["突击", "方块", 10], ["闪避", "红桃", 5]]},
		"foes": [{"char": "lilia", "hp": 2, "max_hp": 3, "shield": 2, "skills": [], "hand": [["闪避", "红桃", 2]]}],
		"seed": 37009,
	},
	{
		"id": "p10", "name": "星夜觉醒", "stars": 4,
		"brief": "2 血触发【心眼觉醒】！但 3号位距离高达 3 且手握两张闪避。",
		"goal": "本回合内击破全部三名守关者（3号位体力 2、装远行披风、持闪避×2；2·4号位各 1 血）。",
		"hint": "准备阶段自动觉醒摸得「特饮」与「闪避」并习得「神射」！必须先喝「特饮」，再将「闪避」当作「神射」（无视距离、不可闪避）2 伤秒杀 3号位，最后装备连弩双突击收割左右。",
		"me": {"char": "aya", "hp": 2, "max_hp": 4, "skills": ["podi", "xinyan"], "hand": [["魔导连弩", "梅花", 1], ["突击", "黑桃", 8], ["突击", "梅花", 9]]},
		"foes": [
			{"char": "sena", "hp": 1, "max_hp": 3, "skills": []},
			{"char": "lilia", "hp": 2, "max_hp": 3, "skills": [], "equip": [["远行披风", "方块", 13]], "hand": [["闪避", "方块", 11], ["闪避", "红桃", 12]]},
			{"char": "nana", "hp": 1, "max_hp": 3, "skills": []},
		],
		"deck_top": [["特饮", "黑桃", 3], ["闪避", "方块", 5]],
		"seed": 37010,
	},
	{
		"id": "p11", "name": "命札破阵", "stars": 4,
		"brief": "守关者装有「结界手环」，牌堆顶则是红桃「补给」护身。",
		"goal": "第 1 回合内击破【雪音】（体力 3 · 装备：结界手环）。",
		"hint": "先装「魔导连弩」并喝「特饮」，再对敌人出「突击」。敌方「结界手环」将翻出红桃「补给」，务必发动「命札」打出黑牌「看破」改判黑色破除判定闪，再补第二张「突击」斩杀！",
		"me": {"char": "yuu", "hp": 3, "skills": ["mingzha"], "hand": [["魔导连弩", "梅花", 1], ["特饮", "黑桃", 3], ["突击", "红桃", 7], ["突击", "方块", 9], ["看破", "黑桃", 11]]},
		"foes": [{"char": "yukine", "hp": 3, "max_hp": 3, "skills": [], "equip": [["结界手环", "黑桃", 2]]}],
		"deck_top": [["补给", "红桃", 6], ["突击", "黑桃", 5]],
		"seed": 40011,
	},
	{
		"id": "p12", "name": "影羽破空", "stars": 4,
		"brief": "开局手握 2 枚「影羽」标记，但 1 号位手中有「闪避」护体。",
		"goal": "第 1 回合内击破全部 2 名守关者（1号位体力 2 持闪避、2号位体力 1 持红桃牌）。",
		"hint": "注意出牌顺序！若先发动「破空」，增伤突击会撞进 1 号位的「闪避」。应先用起手「突击」骗出其「闪避」，再开「破空」摸出「突击」与「火焰试炼」分别斩杀两人！",
		"me": {"char": "sana", "hp": 4, "skills": ["lianyu", "pokong"], "marks": {"影羽": 2}, "hand": [["突击", "黑桃", 7], ["闪避", "红桃", 5]]},
		"foes": [{"char": "sena", "hp": 2, "max_hp": 3, "skills": [], "hand": [["闪避", "方块", 5]]}, {"char": "hina", "hp": 1, "max_hp": 3, "skills": [], "hand": [["突击", "红桃", 9]]}],
		"deck_top": [["突击", "梅花", 8], ["火焰试炼", "红桃", 3]],
		"seed": 40012,
	},
	{
		"id": "p13", "name": "星时抉择", "stars": 3,
		"brief": "敌人身穿「藤蔓铠甲」且手里攥着「闪避」，需借「时计」选牌破防。",
		"goal": "第 1 回合内击破身穿「藤蔓铠甲」的【莉莉娅】（体力 2 · 持闪避×1）。",
		"hint": "开局先发动「时计」观星 2 选 1，务必拿「火突击」而非「特饮」（普通突击会被藤蔓免疫）；再用「突然检查」拆掉其手牌「闪避」，最后火突击触发藤蔓双倍火伤一击带走！",
		"me": {"char": "sakuya", "hp": 3, "skills": ["shiji"], "hand": [["突然检查", "黑桃", 3], ["突击", "黑桃", 8], ["闪避", "方块", 4]]},
		"foes": [{"char": "lilia", "hp": 2, "max_hp": 3, "skills": [], "equip": [["藤蔓铠甲", "梅花", 2]], "hand": [["闪避", "红桃", 2]]}],
		"deck_top": [["突击", "红桃", 7, "火"], ["特饮", "黑桃", 9]],
		"seed": 40013,
	},
	{
		"id": "p14", "name": "洪流弃甲", "stars": 3,
		"brief": "满血目标装有「银狮铠甲」，先砍只会白白触发回血机制！",
		"goal": "第 1 回合内击破身穿「银狮铠甲」的满血守关者【神崎凛】（2/2 体力）。",
		"hint": "关键细节：满血失去「银狮铠甲」不会回复体力！先对其用「水淹七军」逼其满血自弃银狮，再喝「特饮」打出 2 伤「突击」完成击杀（先突击再水淹反而会让对方回满血）！",
		"me": {"char": "nana", "hp": 3, "skills": [], "hand": [["水淹七军", "梅花", 7], ["特饮", "黑桃", 3], ["突击", "红桃", 6]]},
		"foes": [{"char": "rin", "hp": 2, "max_hp": 2, "skills": [], "equip": [["银狮铠甲", "梅花", 1]]}],
		"deck_top": [["突击", "黑桃", 9]],
		"seed": 40014,
	},
	{
		"id": "p15", "name": "霜封破御", "stars": 4,
		"brief": "1 号位【星川幽】握有「命札」和闪避，2 号位穿「藤蔓铠甲」且躲在远行披风后。",
		"goal": "第 1 回合内同时击溃双守关者（星川幽 2 血 + 真昼 3 血）。",
		"hint": "先用「羁绊锁链」横置两名敌人，喝下「特饮」，再对星川幽打出「火突击」并发动「霜封」：先行冻结「命札」防止改判，判定黑牌强命无视闪避打出 2 点火伤，并传导藤蔓 3 点火伤双杀收官！",
		"me": {"char": "mafuyu", "hp": 3, "skills": ["shuangfeng", "bingxin"], "hand": [["羁绊锁链", "梅花", 10], ["特饮", "黑桃", 3], ["突击", "红桃", 7, "火"]]},
		"foes": [{"char": "yuu", "hp": 2, "max_hp": 3, "skills": ["mingzha"], "hand": [["突击", "红桃", 4], ["闪避", "黑桃", 8]]}, {"char": "mahiru", "hp": 3, "max_hp": 3, "skills": [], "equip": [["藤蔓铠甲", "梅花", 2], ["远行披风", "方块", 13]]}],
		"deck_top": [["突击", "黑桃", 10], ["闪避", "红桃", 6]],
		"seed": 40015,
	},
]


static func count() -> int:
	return LIST.size()


static func by_id(pid: String) -> Dictionary:
	for p in LIST:
		if String(p["id"]) == pid:
			return p
	return {}


static func chapter_of(pid: String) -> int:
	var idx := index_of(pid)
	return 2 if idx >= 10 else 1


static func index_of(pid: String) -> int:
	for i in LIST.size():
		if String(LIST[i]["id"]) == pid:
			return i
	return -1


static func next_id(pid: String) -> String:
	var idx := index_of(pid)
	if idx >= 0 and idx + 1 < LIST.size():
		return String(LIST[idx + 1]["id"])
	return ""


static func identities(spec: Dictionary) -> Array:
	var ids: Array = ["挑战者"]
	for _f in spec.get("foes", []):
		ids.append("守关")
	return ids


static func seat_specs(spec: Dictionary) -> Array:
	var out: Array = [spec["me"]]
	for f in spec.get("foes", []):
		out.append(f)
	return out


# 从牌堆取出一张指定的牌（优先同名同花色同点数同属性的实体牌；没有则改造一张同名牌；都没有则新建）
static func _take(eng, cs: Array) -> Dictionary:
	var nm := String(cs[0])
	var suit := String(cs[1]) if cs.size() > 1 else "红桃"
	var point := int(cs[2]) if cs.size() > 2 else 5
	var nature := String(cs[3]) if cs.size() > 3 else ""
	var pick: Dictionary = {}
	for c in eng.deck:
		if String(c["name"]) == nm and String(c["suit"]) == suit and int(c["point"]) == point and String(c.get("nature", "")) == nature:
			pick = c
			break
	if pick.is_empty():
		for c in eng.deck:
			if String(c["name"]) == nm:
				pick = c
				break
	if pick.is_empty():
		pick = {"name": nm}
	else:
		eng.deck.erase(pick)
	pick["suit"] = suit
	pick["point"] = point
	pick["nature"] = nature
	pick["yb"] = []  # 残局牌不带应变词条，保证解法确定
	return pick


# 按关卡数据布置牌局：在 eng.setup_game 之后调用
static func rig(eng, spec: Dictionary) -> void:
	var specs := seat_specs(spec)
	for p in eng.players:
		for c in (p["hand"] as Array):
			eng.deck.append(c)
		(p["hand"] as Array).clear()
	for i in mini(specs.size(), eng.players.size()):
		var sd: Dictionary = specs[i]
		var p: Dictionary = eng.players[i]
		var mx := int(sd.get("max_hp", sd.get("hp", 3)))
		p["max_hp"] = mx
		p["hp"] = mini(int(sd.get("hp", mx)), mx)
		p["skills"] = (sd.get("skills", []) as Array).duplicate()
		p["shield"] = int(sd.get("shield", 0))
		p["chained"] = bool(sd.get("chained", false))
		p["marks"] = (sd.get("marks", {}) as Dictionary).duplicate()
		for cs in sd.get("hand", []):
			(p["hand"] as Array).append(_take(eng, cs))
		for cs in sd.get("equip", []):
			var ec := _take(eng, cs)
			var slot: String = eng.equip_slot_of(String(ec["name"]))
			if slot != "":
				p["equip"][slot] = ec
		for cs in sd.get("judge", []):
			(p["judge"] as Array).append(_take(eng, cs))
	seed(int(spec.get("seed", 37000)))
	eng.deck.shuffle()
	var tops: Array = spec.get("deck_top", [])
	for i in range(tops.size() - 1, -1, -1):
		eng.deck.append(_take(eng, tops[i]))
	eng.players[0]["skip_draw"] = true
	eng.puzzle_turn_limit = int(spec.get("turns", 1))
	eng.puzzle_turns_used = 0
	eng.log_msg("【残局·%s】%s" % [String(spec["name"]), String(spec["goal"])])
	eng.changed()
