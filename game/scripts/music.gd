class_name MusicDirector
extends Node

# 场景背景音乐：主页 / 对局 / 紧张残局。
# 曲目均来自 Kevin MacLeod (incompetech.com)，CC BY 4.0；署名见 data/help.gd。
const TRACKS := {
	"home": "res://assets/bgm/home_carefree.mp3",
	"battle": "res://assets/bgm/battle_volatile_reaction.mp3",
	"tense": "res://assets/bgm/tense_hitman.mp3",
}
const FADE_SEC := 0.75
const FADE_DB := -34.0
const TENSE_MIN_SEC := 20.0

var current_scene := ""
var _players: Array[AudioStreamPlayer] = []
var _active_idx := 0
var _fades: Array[Tween] = []
var _switched_ms := -1000000


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
			p.stream = null  # 释放 MP3 播放实例，避免退出时资源泄漏


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
	# 紧张曲至少停留 TENSE_MIN_SEC 秒再回落到对局曲，避免体力在 1/2 之间反复时来回切歌
	if current_scene == "tense" and scene == "battle" and Time.get_ticks_msec() - _switched_ms < int(TENSE_MIN_SEC * 1000.0):
		return
	_switched_ms = Time.get_ticks_msec()
	# 无头运行（自测/导出）没有音频输出，只记场景不解码播放，也避免退出时 MP3 播放实例泄漏
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
	var path := String(TRACKS.get(scene, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	return stream
