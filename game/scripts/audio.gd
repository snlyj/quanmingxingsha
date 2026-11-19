extends RefCounted
# V0.32/V0.41 声音设置与总线：Master ← SFX / Voice / Music。
# 设置存 user://settings.cfg [audio]。背景音乐由 scripts/music.gd 播放。

const SETTINGS_PATH := "user://settings.cfg"
const VoiceLines = preload("res://data/voice_lines.gd")
const DEFAULTS := {
	"master": 0.8,
	"sfx_on": true,
	"sfx_vol": 0.76,
	"voice_on": true,
	"voice_vol": 0.8,
	"music_on": true,
	"music_vol": 0.52,
	"bgm_style": "sakura",
}
const SFX_FILES := [
	"hit", "hit_heavy", "fire_hit", "thunder_hit", "ice_hit", "heal", "dodge", "draw", "skill",
	"win", "lose", "dying", "death", "revive", "click", "play", "turn",
	"select", "card", "card_slide", "slash", "equip", "trick", "nullify", "judge", "chain",
	"shield", "shield_block", "shield_crack", "shield_break", "spree",
]

static var _inited := false
static var _cfg := {}
static var _sfx_cache := {}
static var _voice_cache := {}
static var _voice_player: AudioStreamPlayer
static var _voice_switch: Tween
static var _voice_priority := 0
static var _voice_started_ms := 0
static var _music_duck: Tween
static var _music_duck_db := 0.0


static func ensure() -> void:
	if _inited:
		return
	_inited = true
	for b in ["SFX", "Voice", "Music"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	_cfg = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in DEFAULTS.keys():
			_cfg[k] = cf.get_value("audio", k, DEFAULTS[k])
	apply()


static func get_v(key: String) -> Variant:
	ensure()
	return _cfg.get(key, DEFAULTS.get(key))


static func set_v(key: String, v: Variant, persist: bool = true) -> void:
	ensure()
	_cfg[key] = v
	apply()
	if persist:
		var cf := ConfigFile.new()
		cf.load(SETTINGS_PATH)
		cf.set_value("audio", key, v)
		cf.save(SETTINGS_PATH)


static func _db(x: float) -> float:
	return linear_to_db(maxf(x, 0.0001))


static func apply() -> void:
	var m := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(m, _db(float(_cfg["master"])))
	AudioServer.set_bus_mute(m, float(_cfg["master"]) <= 0.001)
	var s := AudioServer.get_bus_index("SFX")
	if s >= 0:
		AudioServer.set_bus_volume_db(s, _db(float(_cfg["sfx_vol"])))
		AudioServer.set_bus_mute(s, not bool(_cfg["sfx_on"]))
	var v := AudioServer.get_bus_index("Voice")
	if v >= 0:
		AudioServer.set_bus_volume_db(v, _db(float(_cfg["voice_vol"])))
		AudioServer.set_bus_mute(v, not voice_audible())
	if not voice_audible() and is_instance_valid(_voice_player):
		stop_cv()
	var mu := AudioServer.get_bus_index("Music")
	if mu >= 0:
		_set_music_duck_db(_music_duck_db)
		AudioServer.set_bus_mute(mu, not bool(_cfg["music_on"]) or float(_cfg["music_vol"]) <= 0.001)


static func voice_audible() -> bool:
	ensure()
	return bool(_cfg["voice_on"]) and float(_cfg["master"]) > 0.001 and float(_cfg["voice_vol"]) > 0.001


static func _set_music_duck_db(db: float) -> void:
	_music_duck_db = db
	var bus := AudioServer.get_bus_index("Music")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, _db(float(_cfg["music_vol"])) + db)


static func _voice_tween() -> Tween:
	# Godot 4.3 的 Tween 随场景时间推进，变速对局中按实际秒数淡入淡出。
	var tween := _voice_player.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.01))


static func _duck_music(db: float, duration: float) -> void:
	if _music_duck and _music_duck.is_valid():
		_music_duck.kill()
	if not is_instance_valid(_voice_player) or not _voice_player.is_inside_tree():
		_set_music_duck_db(db)
		return
	_music_duck = _voice_tween()
	_music_duck.tween_method(_set_music_duck_db, _music_duck_db, db, duration).set_trans(Tween.TRANS_SINE)


# 文件音效（assets/sfx/*.ogg，44.1kHz 立体声程序合成，见 素材/art_src/sfx/gen_sfx.py）
static func sfx_stream(key: String) -> AudioStream:
	if _sfx_cache.has(key):
		return _sfx_cache[key]
	var path := "res://assets/sfx/%s.ogg" % key
	var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_sfx_cache[key] = st
	return st


# 通用事件语音（保持未打包单名 key 返回 null，兼容 V30-C9 断言）
static func voice_stream(key: String) -> AudioStream:
	if _voice_cache.has(key):
		return _voice_cache[key]
	var path := "res://assets/voice/%s.ogg" % key
	var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_voice_cache[key] = st
	return st


# 按角色和事件精确查找，字幕与同名 OGG 共用分类。
static func cv_stream(cid: String, cat: String) -> AudioStream:
	return voice_stream("cv_%s_%s" % [cid, cat])


static func cv_text(cid: String, cat: String) -> String:
	return String(VoiceLines.LINES.get(cid, {}).get(cat, ""))


static func play_cv(host: Node, cid: String, cat: String = "touch", priority: int = 3, preview: bool = true) -> bool:
	if DisplayServer.get_name() == "headless" or host == null or not host.is_inside_tree():
		return false
	ensure()
	if not voice_audible():
		return false
	var st := cv_stream(cid, cat)
	if st == null:
		return false
	if not is_instance_valid(_voice_player):
		_voice_player = AudioStreamPlayer.new()
		_voice_player.name = "GameVoicePlayer"
		_voice_player.bus = "Voice"
		host.get_tree().root.add_child(_voice_player)
		_voice_player.finished.connect(_finish_voice)
	var now := Time.get_ticks_msec()
	var switching := _voice_switch != null and _voice_switch.is_valid()
	if _voice_player.playing or switching:
		var elapsed := now - _voice_started_ms
		if not switching and _voice_player.stream == st and elapsed < 220:
			return preview
		if not preview and (priority <= _voice_priority or (priority < 4 and elapsed < 340)):
			return false
		if switching:
			_voice_switch.kill()
			_voice_switch = null
	if _voice_player.playing:
		_voice_priority = priority
		_voice_started_ms = now
		_voice_switch = _voice_tween()
		_voice_switch.tween_property(_voice_player, "volume_db", -21.0, 0.065).set_trans(Tween.TRANS_SINE)
		_voice_switch.tween_callback(_start_voice.bind(st, priority))
		return true
	_start_voice(st, priority)
	return true


static func _start_voice(stream: AudioStream, priority: int) -> void:
	_voice_switch = null
	_voice_started_ms = Time.get_ticks_msec()
	_voice_priority = priority
	_voice_player.volume_db = 0.0
	_voice_player.stream = stream
	_voice_player.play()
	_duck_music(-2.8, 0.11)


static func _finish_voice() -> void:
	if _voice_switch and _voice_switch.is_valid():
		return
	_voice_priority = 0
	_duck_music(0.0, 0.31)


static func stop_cv() -> void:
	if not is_instance_valid(_voice_player):
		return
	if _voice_switch and _voice_switch.is_valid():
		_voice_switch.kill()
	_voice_switch = null
	_voice_player.stop()
	_finish_voice()


# 大厅/局外 UI 通用音效触发（无头测试不解码，避免退出泄漏）
static func play_ui(host: Node, key: String = "click") -> void:
	if DisplayServer.get_name() == "headless" or host == null or not host.is_inside_tree():
		return
	ensure()
	if not bool(_cfg["sfx_on"]) or float(_cfg["sfx_vol"]) <= 0.001 or float(_cfg["master"]) <= 0.001:
		return
	var st := sfx_stream(key)
	if st == null:
		return
	var rt := host.get_tree().root
	var pl := rt.get_node_or_null("_UiSfxPlayer") as AudioStreamPlayer
	if pl == null:
		pl = AudioStreamPlayer.new()
		pl.name = "_UiSfxPlayer"
		pl.bus = "SFX"
		rt.add_child(pl)
	pl.stream = st
	pl.play()
