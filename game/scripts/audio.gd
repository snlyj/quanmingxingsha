extends RefCounted
# V0.32/V0.41 声音设置与总线：Master ← SFX / Voice / Music。
# 设置存 user://settings.cfg [audio]。BGM 由 scripts/music.gd 播放（支持「樱华国风」与「经典交响」双曲风切换）。

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULTS := {
	"master": 0.8,
	"sfx_on": true,
	"sfx_vol": 0.8,
	"voice_on": true,
	"voice_vol": 0.8,
	"music_on": true,
	"music_vol": 0.65,
	"bgm_style": "sakura",
}
const SFX_FILES := [
	"hit", "fire_hit", "thunder_hit", "heal", "dodge", "draw", "skill",
	"win", "lose", "dying", "death", "revive", "click", "play", "turn",
	"card", "slash", "equip", "trick", "nullify", "judge", "chain",
	"shield", "spree",
]

static var _inited := false
static var _cfg := {}
static var _sfx_cache := {}
static var _voice_cache := {}


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
		AudioServer.set_bus_mute(v, not bool(_cfg["voice_on"]))
	var mu := AudioServer.get_bus_index("Music")
	if mu >= 0:
		AudioServer.set_bus_volume_db(mu, _db(float(_cfg["music_vol"])))
		AudioServer.set_bus_mute(mu, not bool(_cfg["music_on"]) or float(_cfg["music_vol"]) <= 0.001)


# 文件音效（assets/sfx/*.ogg，44.1kHz 立体声程序合成，见 素材/art_src/sfx/gen_sfx.py）
static func sfx_stream(key: String) -> AudioStream:
	if _sfx_cache.has(key):
		return _sfx_cache[key]
	var path := "res://assets/sfx/%s.ogg" % key
	var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_sfx_cache[key] = st
	return st


# 语音：没有打包对应文件时返回 null（当前版本均为 null）
static func voice_stream(key: String) -> AudioStream:
	if _voice_cache.has(key):
		return _voice_cache[key]
	var path := "res://assets/voice/%s.ogg" % key
	var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_voice_cache[key] = st
	return st


# 大厅/局外 UI 通用音效触发（无头测试不解码，避免退出泄漏）
static func play_ui(host: Node, key: String = "click") -> void:
	if DisplayServer.get_name() == "headless" or host == null or not host.is_inside_tree():
		return
	ensure()
	if not bool(_cfg.get("sfx_on", true)) or float(_cfg.get("master", 0.8)) <= 0.001:
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
