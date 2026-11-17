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

var current_scene := ""
var _players: Array[AudioStreamPlayer] = []
var _active_idx := 0
var _fades: Array[Tween] = []


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
	for p in _players:
		if is_instance_valid(p):
			p.stop()


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
