class_name MusicDirector
extends Node

# V0.41 场景背景音乐：支持「樱华国风（二次元×手杀风）」与「经典交响（Kevin MacLeod CC BY 4.0）」双曲风切换。
const AudioCfgM = preload("res://scripts/audio.gd")

const TRACKS := {
	"home": "res://assets/bgm/home_sakura.ogg",
	"battle": "res://assets/bgm/battle_storm.ogg",
	"tense": "res://assets/bgm/tense_climax.ogg",
}
const TRACKS_SAKURA := {
	"home": "res://assets/bgm/home_sakura.ogg",
	"battle": "res://assets/bgm/battle_storm.ogg",
	"tense": "res://assets/bgm/tense_climax.ogg",
}
const TRACKS_CLASSIC := {
	"home": "res://assets/bgm/home_carefree.ogg",
	"battle": "res://assets/bgm/battle_volatile_reaction.ogg",
	"tense": "res://assets/bgm/tense_hitman.ogg",
}
const TRACK_TITLES := {
	"sakura": {
		"home": "樱华序曲·星樱学园",
		"battle": "绯樱战阵·破阵乐",
		"tense": "宿命决战·残月",
	},
	"classic": {
		"home": "Carefree·晴空序曲",
		"battle": "Volatile·激战交响",
		"tense": "Hitman·决胜时刻",
	},
}
const FADE_SEC := 0.75
const FADE_DB := -34.0
const TENSE_MIN_SEC := 20.0

var current_scene := ""
var _players: Array[AudioStreamPlayer] = []
var _active_idx := 0
var _fades: Array[Tween] = []
var _switched_ms := -1000000


static func style_key() -> String:
	var s := String(AudioCfgM.get_v("bgm_style"))
	return "classic" if s == "classic" else "sakura"


static func style_label() -> String:
	return "🌸 樱华国风" if style_key() == "sakura" else "🎻 经典交响"


static func track_title(scene: String = "home") -> String:
	var sk := style_key()
	var mp: Dictionary = TRACK_TITLES.get(sk, TRACK_TITLES["sakura"])
	return String(mp.get(scene if scene != "" and scene != "off" else "home", "樱华序曲·星樱学园"))


func cycle_style() -> String:
	var next_s := "classic" if style_key() == "sakura" else "sakura"
	AudioCfgM.set_v("bgm_style", next_s)
	var sc := current_scene if current_scene != "" else "home"
	current_scene = ""
	_switched_ms = -1000000
	play_scene(sc)
	return style_label()


func _ready() -> void:
	add_to_group("music_director")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = 0.0
		add_child(p)
		_players.append(p)


func _exit_tree() -> void:
	for t in _fades:
		if t is Tween and (t as Tween).is_valid():
			(t as Tween).kill()
	_fades.clear()
	for p in _players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		for p in _players:
			if is_instance_valid(p):
				p.stop()
				p.stream = null


func play_scene(scene: String) -> void:
	if scene != "off" and not TRACKS.has(scene):
		return
	if scene == current_scene:
		var cur := _players[_active_idx]
		if scene != "off" and cur.playing:
			return
	if scene == "off":
		_stop_all()
		current_scene = "off"
		return
	if current_scene == "tense" and scene == "battle" and Time.get_ticks_msec() - _switched_ms < int(TENSE_MIN_SEC * 1000.0):
		return
	_switched_ms = Time.get_ticks_msec()
	if DisplayServer.get_name() == "headless":
		current_scene = scene
		return
	var stream := _stream_for(scene)
	if stream == null:
		_stop_all()
		current_scene = scene
		return

	var old := _players[_active_idx]
	_active_idx = 1 - _active_idx
	var next := _players[_active_idx]
	next.stream = stream
	next.volume_db = FADE_DB
	next.play()
	current_scene = scene
	_fade(old, FADE_DB, true)
	_fade(next, 0.0, false)


func _stop_all() -> void:
	for t in _fades:
		if t is Tween and (t as Tween).is_valid():
			(t as Tween).kill()
	_fades.clear()
	for p in _players:
		p.stop()


func _fade(player: AudioStreamPlayer, target_db: float, stop_after: bool) -> void:
	_fades = _fades.filter(func(t: Tween) -> bool: return t != null and t.is_valid())
	var tween := player.create_tween()
	tween.tween_property(player, "volume_db", target_db, FADE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if stop_after:
		tween.tween_callback(player.stop)
	_fades.append(tween)


func _stream_for(scene: String) -> AudioStream:
	var table: Dictionary = TRACKS_CLASSIC if style_key() == "classic" else TRACKS_SAKURA
	var path := String(table.get(scene, TRACKS.get(scene, "")))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	return stream
